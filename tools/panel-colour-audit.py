#!/usr/bin/env python3
"""panel-colour-audit — the gate behind P-UI-69 (swatch legibility).

WHY THIS EXISTS
The user's report was «رنگ ها کار نمیکنه» ("the colours don't work"). The colour
machinery was fully wired — rows, swatches, "+", the palette matrix, the mixer,
the hex field, the apply path, persistence and the chart readers all check out —
but the CONTROL was invisible: read out of the shipped screenshot pixel by pixel,
the 8th quick swatch is QuickPalColor(7) = #141414 (20,20,20) painted on the
card's own row face #1A2029 (26,32,41) with a PNL_CLR_LINE border #222832
(34,40,50). Those are contrast ratios of 1.13:1 for the fill and 1.11:1 for the
border. The row therefore read as "seven swatches and an empty slot", and tapping
the slot applied a near-black that then vanished on the chart — which is exactly
"the colours don't work" from the user's chair.

P-UI-68 closed the same trap one layer down (a colour STRIP cell whose target was
clrNONE painted MT4's CLR_NONE as ink-black). The quick strip, the palette's own
matrix, the recents and the strip cells still had it.

WHAT THIS GATE OWNS
  1 OWNER     ONE function answers "will this swatch be visible on its own
              backdrop?" (`PnlSwatchBorder`) and it is the ONLY decider of a
              swatch border: every swatch family (quick strip `Q`, the preview
              block `CB`, the colour-strip cells `CS`, the section strip `SECS`,
              the palette matrix `s{r}_{c}`, the recents `r{i}` and the palette's
              own current-colour block) goes through it, and none of them passes
              a raw `PNL_CLR_LINE` border again.
  2 THRESHOLD the floor is a NAMED constant read from the source, and the
              luminance maths it compares with is WCAG's (linearised channels),
              so the model below reproduces the panel's own decision exactly.
  3 MODEL     every colour the panel can paint as a swatch — the 8 `QuickPalColor`
              values and all 190 `PalMatColor` cells, parsed from the source —
              is measured against the face it is actually drawn on (the card face
              for the quick strip, the popover face for the palette). A colour
              below the floor must be carried by a border that is itself visible
              on that face.
  4 PARSE     the palette's quick-swatch branch matches `Q0`..`Q7` EXACTLY. The
              retired prefix test (`len==2 && id[0]=='Q'`) also matched the "+"
              chip's id `QA`, which `StringToInteger()` reads as 0 — one wiring
              change away from "pressing + silently applies the first swatch".

Usage:  python tools/panel-colour-audit.py [--quiet] [--model] [--selftest]
Exit 0 = clean, 1 = a swatch can read as empty space again.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PANELS = os.path.join(ROOT, "Biotak", "BiotakPanels.mqh")

QUIET = "--quiet" in sys.argv
SHOW_MODEL = "--model" in sys.argv

# --- source access (patchable, so --selftest can doctor the file) ------------
_PATCHED = {}
_CACHE = {}


def read(path):
    if path in _PATCHED:
        return _PATCHED[path]
    if path not in _CACHE:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            _CACHE[path] = fh.read()
    return _CACHE[path]


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def body(text, signature):
    """The { ... } block of the function whose declaration starts at `signature`."""
    src = strip_comments(text)
    i = src.find(signature)
    if i < 0:
        return None
    j = src.find("{", i)
    if j < 0:
        return None
    depth = 0
    for k in range(j, len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[j:k + 1]
    return None


# --- colours -----------------------------------------------------------------
def token(text, name):
    """A `#define NAME C'R,G,B'` colour token, as an (r, g, b) tuple."""
    m = re.search(r"#define\s+%s\s+C'(\d+),(\d+),(\d+)'" % re.escape(name), text)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def numeric(text, name):
    m = re.search(r"#define\s+%s\s+([0-9.]+)" % re.escape(name), text)
    return float(m.group(1)) if m else None


def c_literals(text):
    return [(int(r), int(g), int(b))
            for r, g, b in re.findall(r"C'(\d+),(\d+),(\d+)'", text)]


def quick_swatches(text):
    blk = body(text, "color QuickPalColor(")
    return c_literals(blk) if blk else []


def matrix_cells(text):
    blk = body(text, "color PalMatColor(")
    if blk is None:
        return []
    # the table is the brace-initialised array, not the guard expressions
    arr = blk[blk.find("{") + 1:]
    return c_literals(arr)


# --- WCAG, exactly as the panel's own helper implements it -------------------
def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = rgb
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# --- checks ------------------------------------------------------------------
FAMILIES = (
    # (label, the snippet that must carry the owner's border)
    ("quick strip \"Q\"", 'PnlSwatchBorder(qc,PNL_CLR_CARD)'),
    ("preview block \"CB\"", 'PnlSwatchBorder(cc,PNL_CLR_CARD)'),
    ("strip cells \"CS\"", 'PnlSwatchBorder(cc,PNL_CLR_CARD)'),
    ("section strip \"SECS\"", 'PnlSwatchBorder(sec,PNL_CLR_CARD)'),
    ("palette matrix", 'PnlSwatchBorder(sw,PNL_CLR_FIELD)'),
    ("palette recents", 'PnlSwatchBorder(g_PalRecent[i],PNL_CLR_FIELD)'),
    ("palette current block", 'PnlSwatchBorder(cur,PNL_CLR_FIELD)'),
)


def check_owner():
    """ONE decider for a swatch border, used by every family."""
    problems = []
    text = read(PANELS)
    for sig in ("color PnlSwatchBorder(", "double PnlContrast(", "double PnlLum("):
        if body(text, sig) is None:
            problems.append("%s is gone - a swatch family has no owner" % sig.strip())
    owner = body(text, "color PnlSwatchBorder(")
    if owner is not None:
        if "PNL_SWATCH_MIN_CONTRAST" not in owner:
            problems.append("the owner no longer reads the named floor")
        if "PnlContrast(" not in owner:
            problems.append("the owner no longer measures contrast")
        if "PNL_CLR_MUTED" not in owner:
            problems.append("the owner has no visible border ink to fall back to")
        # the DIRECTION matters: "below the floor -> visible outline". An
        # inverted comparison outlines the visible swatches and leaves the holes
        # - the model cannot see that (it reads structure, not control flow).
        if not re.search(r"PnlContrast\([^;]*?\)\s*<\s*PNL_SWATCH_MIN_CONTRAST", owner):
            problems.append("the owner's comparison is not 'BELOW the floor needs a border'")
    lumblk = body(text, "double PnlLum(")
    if lumblk is not None:
        if lumblk.count("MathPow(") < 3:
            problems.append("PnlLum is not WCAG-linearised on all three channels")
        vi = lumblk.find("int v=(int)c;")
        gi = lumblk.find("if(v < 0)")
        if vi < 0 or gi < 0 or vi > gi:
            problems.append("PnlLum's signed cast must come BEFORE its guard: `color` is "
                            "unsigned in MQL4, so `c < 0` is always false (warning 65)")
    for label, snippet in FAMILIES:
        if snippet not in text:
            problems.append("%s does not use the border owner" % label)
    # no family may go back to the flat hairline for its swatch border
    for m in re.finditer(r"PnlSetButton\(([^;]*?)PNL_CLR_LINE", text, re.S):
        inner = m.group(1)
        if '"CB"' in inner or re.search(r'"Q"\s*\+', inner):
            problems.append("a colour swatch is back on the flat PNL_CLR_LINE border")
    # EVERY border a swatch can carry - the create pass AND the refresh pass -
    # must come from the owner. The update pass is where a create-only fix rots
    # silently: `PnlUpdateRow`'s colour branch re-asserted a bare `PNL_CLR_LINE`
    # (a SECOND decider) and never re-bordered the preview/cset cells at all, so
    # a row switched to near-black read as an empty slot again until the card was
    # rebuilt - the same create-time-only shape as P-UI-66.
    SWATCH_NAME = re.compile(r'"CB"|"Q"\s*\+|"CS"\s*\+|"SECS"\s*\+|"CSK"')
    for m in re.finditer(r"OBJPROP_BORDER_COLOR", text):
        # the NAME evidence is looked for in a window (a swatch's id is built a
        # line above the write), the VALUE evidence only in the statement itself:
        # a window-wide search would find a NEIGHBOURING swatch's owner call and
        # clear a write that has none of its own.
        window = text[max(0, m.start() - 400):m.end() + 200]
        if not SWATCH_NAME.search(window):
            continue
        head = text[:m.start()]
        stmt = text[head.rfind(";") + 1:m.end() + 200]
        if "PnlSwatchBorder(" not in stmt:
            problems.append("a swatch border is written outside the owner (line %d)"
                            % (text[:m.start()].count("\n") + 1))
    upd = body(text, "void PnlUpdateRow(")
    if upd is None:
        problems.append("PnlUpdateRow() is gone - nothing re-paints a colour row")
    else:
        # both halves of the colour branch: the PREVIEW block and the strip
        for need, who in (("PnlSwatchBorder(cur,", "the preview block"),
                          ("PnlSwatchBorder(qc,", "the quick swatches")):
            if need not in upd:
                problems.append("%s is not re-bordered by PnlUpdateRow's colour "
                                "branch (a recoloured swatch keeps a stale border)" % who)
    # the POPOVER's live paths are deciders too: PalUpdateLive is what a mixer
    # drag and a preset tap go through, and it used to leave the current block's
    # border at whatever PalDraw set at OPEN time.
    live = body(text, "void PalUpdateLive(")
    if live is None:
        problems.append("PalUpdateLive() is gone - the popover has no live refresh")
    elif "PnlSwatchBorder(cur,PNL_CLR_FIELD)" not in live:
        problems.append("the palette's current block is not re-bordered live (dragging "
                        "the mixer to near-black leaves it reading as an empty slot)")
    # the RECENT strip: one painter, reached by BOTH the open path and the live
    # path, and flushed when a gesture (the only coalescing case) ends.
    if text.count("void PalPaintRecents(") != 1:
        problems.append("PalPaintRecents() is not defined exactly once")
    if "PalPaintRecents(" not in (body(text, "void PalDraw()") or ""):
        problems.append("PalDraw no longer paints the recents strip through the owner")
    flush = body(text, "void PalRefreshRecents(")
    if flush is not None and "PalPaintRecents(" not in flush:
        problems.append("PalRefreshRecents() stopped painting through the owner")
    # P-UI-81: the flush must sit in the MIXER RELEASE branch itself. Asking the
    # whole file (the old shape) went VACUOUS the moment the same flush appeared
    # at a second site (the gesture reaper in `PnlHandleMouseMove`): its negative
    # control patched the mixer block and the check still found the other copy,
    # so the seed passed without patching anything that mattered - the exact
    # "a gate that counts text instead of a promise" trap.
    engine = body(text, "void PnlHandleMouseMove(") or ""
    at = engine.find("if(g_PalMixDrag > 0)")
    mixer = engine[at:at + 420] if at >= 0 else ""
    if "PalRefreshRecents(true)" not in mixer:
        problems.append("nothing flushes the coalesced recents repaint at the end of a "
                        "mixer drag (the strip would stay one colour behind)")
    if "PalRefreshRecents(false)" not in text:
        problems.append("nothing refreshes the recents strip on an APPLY - the strip "
                        "would show a different set than the picker just produced")
    if text.count("color PnlSwatchBorder(") != 1:
        problems.append("PnlSwatchBorder() is not defined exactly once")
    return problems


def check_parse():
    """The palette's quick-swatch branch must match Q0..Q7 and nothing else.

    Anchored on the branch's own test rather than on a brace pattern: the
    handler is a long if-chain and a `(...)`-based locator would either walk
    past the branch or swallow the whole function.
    """
    problems = []
    text = read(PANELS)
    # the quick strip's swatches are dispatched by NAME in the panel's click
    # router (PalHandleClick owns the popup's own widgets) - P-UI-69.
    blk = body(text, "int PnlHandleClick(")
    if blk is None:
        return ["PnlHandleClick() is gone"]
    i = blk.find("StringGetCharacter(kind,0)=='Q'")
    if i < 0:
        return ["the quick-swatch branch is no longer where the gate looks for it"]
    # the test is ONE clause of the `if`, so start the window at the `if(` itself:
    # anchoring on the clause alone would cut the earlier `StringLen(kind)==2`
    # off and report a missing guard that is right there in the source.
    start = blk.rfind("if(", 0, i)
    cond = blk[start:i + 400]
    cond = cond[:cond.find("{")] if "{" in cond else cond
    branch = blk[i:i + 700]
    if "StringLen(kind)==2" not in cond:
        problems.append("the quick-swatch id test lost its exact-length check")
    if "'0'" not in cond or "'9'" not in cond:
        problems.append("the quick-swatch id test does not require a DIGIT (the \"+\" "
                        "chip's id \"QA\" would parse as swatch 0)")
    if "PNL_QSW_N" not in branch:
        problems.append("the quick-swatch branch no longer bounds the index")
    if "rkind!=4" not in branch:
        problems.append("the quick-swatch branch no longer gates on a colour row")
    return problems


def check_model():
    """Every swatch colour must be visible, or carried by a visible border."""
    problems = {}
    text = read(PANELS)
    floor = numeric(text, "PNL_SWATCH_MIN_CONTRAST")
    if floor is None:
        return {"the floor constant PNL_SWATCH_MIN_CONTRAST is gone": ""}, {}
    card = token(text, "PNL_CLR_CARD")
    field = token(text, "PNL_CLR_FIELD")
    muted = token(text, "PNL_CLR_MUTED")
    line = token(text, "PNL_CLR_LINE")
    missing = [n for n, v in (("PNL_CLR_CARD", card), ("PNL_CLR_FIELD", field),
                              ("PNL_CLR_MUTED", muted), ("PNL_CLR_LINE", line)) if v is None]
    if missing:
        return {"colour token(s) missing: %s" % ", ".join(missing): ""}, {}

    quick = quick_swatches(text)
    matrix = matrix_cells(text)
    if len(quick) < 8:
        problems["QuickPalColor() no longer exposes 8 swatches"] = ""
    if len(matrix) < 100:
        problems["PalMatColor() no longer exposes the Material matrix"] = ""

    holes = []
    worst = None
    for face_name, face in (("card", card), ("popover", field)):
        pass
    for kind, cols, face in (("quick", quick, card), ("matrix", matrix, field)):
        for i, c in enumerate(cols):
            r_fill = contrast(c, face)
            if r_fill >= floor:
                continue
            # the swatch is a hole unless its outline is itself visible
            r_border = contrast(muted, face)
            r_outline = contrast(muted, c)
            if r_border < floor or r_outline < 1.7:
                problems["%s swatch #%d %s is below the floor and its outline does "
                         "not carry it" % (kind, i, str(c))] = ""
            holes.append((kind, i, c, r_fill, r_border))
            if worst is None or r_fill < worst[3]:
                worst = (kind, i, c, r_fill, face_name)

    # the flat hairline MUST fail the floor, or the owner has nothing to decide
    if contrast(line, card) >= floor:
        problems["PNL_CLR_LINE alone now clears the floor - the owner's switch is "
                 "decorative"] = ""
    if contrast(muted, card) < floor:
        problems["the fallback border ink (PNL_CLR_MUTED) is itself invisible on "
                 "the card"] = ""
    if contrast(muted, field) < floor:
        problems["the fallback border ink (PNL_CLR_MUTED) is itself invisible on "
                 "the popover"] = ""
    return problems, {"floor": floor, "quick": len(quick), "matrix": len(matrix),
                      "holes": holes, "worst": worst,
                      "line_on_card": contrast(line, card),
                      "muted_on_card": contrast(muted, card),
                      "muted_on_field": contrast(muted, field)}


def main():
    owner_problems = check_owner()
    parse_problems = check_parse()
    model_problems, stats = check_model()

    problems = {}
    for msg in owner_problems + parse_problems + list(model_problems):
        problems.setdefault(msg, "")

    if not QUIET:
        for label, plist in (("[owner] ONE decider for a swatch border, used by all 7 families",
                              owner_problems),
                             ("[parse] the quick-swatch id test matches Q0..Q7 exactly",
                              parse_problems),
                             ("[model] every swatch is visible, or outlined to be",
                              list(model_problems))):
            print("  %s %s%s" % ("ok  " if not plist else "FAIL", label,
                                 "" if not plist else " - %d problem(s)" % len(plist)))

    if stats:
        if SHOW_MODEL:
            print("  model: %d swatch colours measured (%d quick + %d matrix) vs the "
                  "%.1f:1 floor" % (stats["quick"] + stats["matrix"], stats["quick"],
                                    stats["matrix"], stats["floor"]))
            print("  model: %d of them sit below the floor and carry the outline"
                  % len(stats["holes"]))
            for kind, i, c, r, rb in sorted(stats["holes"], key=lambda h: h[3])[:6]:
                print("         %-6s #%-3d RGB%-16s fill %.2f:1  outline %.2f:1"
                      % (kind, i, str(c), r, rb))
            print("  model: the retired flat border measured %.2f:1, the fallback ink "
                  "%.2f:1 (card) / %.2f:1 (popover)"
                  % (stats["line_on_card"], stats["muted_on_card"], stats["muted_on_field"]))
            if stats["worst"]:
                kind, i, c, r, face = stats["worst"]
                print("  model: worst hole %s #%d %s at %.2f:1 on the %s face - the "
                      "shipped \"empty slot\" (P-UI-69)" % (kind, i, str(c), r, face))

    if problems:
        for msg in problems:
            print("  FAIL %s" % msg)
        print("\npanel colour: %d problem class(es) - a swatch can read as empty space "
              "again" % len(problems))
        return 1

    if not QUIET:
        if stats:
            print("  ok   [contrast] floor %.1f:1; %d swatch colours need the outline, "
                  "%d are seen by fill alone"
                  % (stats["floor"], len(stats["holes"]),
                     stats["quick"] + stats["matrix"] - len(stats["holes"])))
        print("\npanel colour: clean - one border owner, a measured floor, and every "
              "swatch visible on its own face")
    return 0


# --- negative control -------------------------------------------------------
def selftest():
    real = dict(_PATCHED)
    cases = []

    stale = []

    def with_source(old, new, nth=0):
        # `nth` picks WHICH occurrence to break: a fault that exists in two
        # places (PalDraw's border and PalUpdateLive's) must be broken in the
        # one the check is about, or the seed passes for the wrong reason -
        # a negative control that silently patched the wrong site is vacuous.
        # And a seed whose anchor a refactor deleted is reported, never ignored.
        _PATCHED.clear()
        src = read(PANELS)
        i, at = -1, -1
        for _ in range(nth + 1):
            at = src.find(old, i + 1)
            if at < 0:
                break
            i = at
        if at < 0:
            stale.append(old.strip().splitlines()[0][:80])
            _PATCHED.update({PANELS: src})
            return
        _PATCHED.update({PANELS: src[:at] + new + src[at + len(old):]})

    def reset():
        _PATCHED.clear()
        _PATCHED.update(real)

    reset()
    cases.append(("the clean source passes the owner check", not check_owner()))
    cases.append(("the clean source passes the parse check", not check_parse()))
    cases.append(("the clean source passes the model", not check_model()[0]))
    cases.append(("the clean source passes every check",
                  not check_owner() and not check_parse() and not check_model()[0]))

    # 1. the shipped trap: a swatch back on the flat hairline border
    with_source('(qc==cc) ? a1 : PnlSwatchBorder(qc,PNL_CLR_CARD)',
                '(qc==cc) ? a1 : PNL_CLR_LINE')
    cases.append(("a swatch back on the flat border is caught", bool(check_owner())))
    reset()

    # 2. the floor becomes decorative (nothing ever needs an outline)
    with_source("#define PNL_SWATCH_MIN_CONTRAST 1.7",
                "#define PNL_SWATCH_MIN_CONTRAST 1.0")
    cases.append(("a decorative floor is caught", bool(check_model()[0])))
    reset()

    # 3. the floor is inverted (every swatch outlined, the bug class silenced).
    # check_owner() reads the owner's control flow, so that is where a flipped
    # comparison shows up - the model only reads structure and cannot see it.
    with_source("return (PnlContrast(fill,backdrop) < PNL_SWATCH_MIN_CONTRAST)",
                "return (PnlContrast(fill,backdrop) > PNL_SWATCH_MIN_CONTRAST)")
    cases.append(("an inverted comparison is caught", bool(check_owner())))
    reset()

    # 4. the fallback ink stops being visible itself
    with_source("#define PNL_CLR_MUTED    C'140,150,166'",
                "#define PNL_CLR_MUTED    C'40,46,58'")
    cases.append(("an invisible fallback ink is caught", bool(check_model()[0])))
    reset()

    # 5. the "Q" prefix trap comes back (the "+" chip would apply swatch 0)
    with_source("StringLen(kind)==2 && StringGetCharacter(kind,0)=='Q' &&\n"
                "      StringGetCharacter(kind,1)>='0' && StringGetCharacter(kind,1)<='9'",
                "StringLen(kind)==2 && StringGetCharacter(kind,0)=='Q'")
    cases.append(("the quick-swatch prefix trap is caught", bool(check_parse())))
    reset()

    # 6. the luminance maths loses its WCAG linearisation
    with_source("if(r > 0.03928) r=MathPow((r+0.055)/1.055,2.4); else r=r/12.92;",
                "")
    cases.append(("non-WCAG luminance is caught", bool(check_owner())))
    reset()

    # 7. the unsigned-colour trap returns (dead guard + compiler warning 65)
    with_source("   int v=(int)c;\n   if(v < 0) return 1.0;",
                "   if(c < 0) return 1.0;\n   int v=(int)c;")
    cases.append(("the unsigned-colour guard is caught", bool(check_owner())))
    reset()

    # 8. a family is dropped (the palette matrix loses the outline)
    with_source('PnlSwatchBorder(sw,PNL_CLR_FIELD)', 'PNL_CLR_LINE')
    cases.append(("a family without the owner is caught", bool(check_owner())))
    reset()

    # 9. the owner is duplicated (two deciders)
    with_source("color PnlSwatchBorder(const color fill,const color backdrop)\n{",
                "color PnlSwatchBorder(const color fill,const color backdrop)\n{\n"
                "   return PNL_CLR_LINE;\n}\ncolor PnlSwatchBorderX(const color fill,"
                "const color backdrop)\n{")
    cases.append(("a second border decider is caught", bool(check_owner())))
    reset()

    # 10. the UPDATE pass rots back to a flat border (a create-only fix: the
    # recoloured swatch keeps PNL_CLR_LINE and reads as empty space again)
    with_source("ObjectSetInteger(0,qn,OBJPROP_BORDER_COLOR,\n"
                "                             (qc==cur) ? PNL_CLR_ACCENT : PnlSwatchBorder(qc,PNL_CLR_CARD));",
                "ObjectSetInteger(0,qn,OBJPROP_BORDER_COLOR,\n"
                "                             (qc==cur) ? PNL_CLR_ACCENT : PNL_CLR_LINE);")
    cases.append(("a create-only border fix is caught", bool(check_owner())))
    reset()

    # 11. the refresh pass stops re-bordering at all
    with_source("ObjectSetInteger(0,cb,OBJPROP_BORDER_COLOR,PnlSwatchBorder(cur,PNL_CLR_CARD));",
                "")
    cases.append(("a refresh pass that skips the border is caught", bool(check_owner())))
    reset()

    # 12. the popover's live path stops re-bordering (a mixer drag to black
    # leaves the current block reading as empty space)
    with_source("ObjectSetInteger(0,p+\"cur\",OBJPROP_BORDER_COLOR,PnlSwatchBorder(cur,PNL_CLR_FIELD));",
                "", nth=1)   # PalDRAW is occurrence 0; the LIVE one is what this checks
    cases.append(("a popover that stops re-bordering live is caught", bool(check_owner())))
    reset()

    # 13. the recents strip goes back to a second painter inside PalDraw
    with_source("      PalPaintRecents(px, contY);",
                '''      for(int i=0;i<PAL_RSHOW;i++)
         PnlSetButton(p+'r'+IntegerToString(i), px, contY+18, PAL_QSW, PAL_QSW,
                      '', g_PalRecent[i], PNL_CLR_LINE, true);''')
    cases.append(("a second recents painter is caught", bool(check_owner())))
    reset()

    # 14. no apply-time refresh (the strip keeps showing the previous set)
    with_source("   PalRefreshRecents(false);", "")
    cases.append(("an apply with no recents refresh is caught", bool(check_owner())))
    reset()

    # 15. no flush at the end of a mixer drag (the strip lags one colour)
    with_source("             PalRefreshRecents(true);   // P-UI-69: flush the coalesced recents tail",
                "")
    cases.append(("a missing drag-tail flush is caught", bool(check_owner())))
    reset()

    for name, ok in cases:
        print("%-58s %s" % (name, "caught" if ok else "MISSED"))
    for anchor in stale:
        print("  STALE seed anchor (not in the source): %s" % anchor)
    missed = [n for n, ok in cases if not ok]
    if missed or stale:
        print("\nselftest FAILED: %d fault(s) went undetected, %d stale seed "
              "anchor(s)" % (len(missed), len(stale)))
        return 1
    print("\nselftest: %d/%d faults caught - the audit is not vacuous"
          % (len(cases), len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
