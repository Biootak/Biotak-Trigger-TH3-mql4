#!/usr/bin/env python3
"""
THE GEAR PANEL GATE. Renders every tab of the "Box Settings" panel from the
constants the MQL uses and fails the build when a number, a seat or a face drifts.

Why this exists, in one line: the panel's only proof used to be a screenshot, and
a screenshot proves a paint, not a layout. Every defect on this surface was found
by eye AFTER a build that was green, and the eye could only see the tab that was
open. Four tabs, four blind spots.

What it checks, and what each failure means:
  height   every tab's gh must land on (104 + 42n) for n in 1..10 — the plate is
           baked per card count, so a gh that misses is a wrong card, and the MQL
           silently falls to the composed W branch instead of the one bake
  plate    the branch the MQL would take, named, plus the exact object it creates
  seats    the row/head/label/switch/pad numbers against BiotakPanels.mqh
  faces    every raster the panel paints must exist on disk — a missing file is a
           hole the compiler cannot name (same class as the resource gate)
  arity    the tab list and its enum must agree, so a fifth tab cannot be added to
           the enum and forgotten in the tabs

Usage:  python tools/check-gear-panel.py [--png]     (--png writes tools/legacy/gear-N.png)
"""

import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ICONS = os.path.join(ROOT, "Files", "Icons")
DRAWSTRIP = os.path.join(ROOT, "Biotak", "DrawStrip.mqh")

sys.path.insert(0, HERE)
import importlib.util

_s = importlib.util.spec_from_file_location("mt4sim", os.path.join(HERE, "legacy", "panel-mt4-sim.py"))
mt4 = importlib.util.module_from_spec(_s)
_s.loader.exec_module(mt4)

_s2 = importlib.util.spec_from_file_location("gearpanel", os.path.join(HERE, "sim-gear-panel.py"))
G = importlib.util.module_from_spec(_s2)
_s2.loader.exec_module(G)

# P-DRAW-117 (2026-10-01) — ONE MIRROR, TWO KINDS. The panel's group list is
# KIND-AWARE (a fibo opens LEVELS where a box opens neither LEVELS nor MARK), so a
# gate that walked a rectangle's groups only was blind to the one group whose rows
# are elastic and whose ceiling this build changed. The same module is imported a
# second time with `SIM_KIND` set, exactly as tools/sim-strip-panels.py does for the
# cards — no second model, no transcribed list.
MODELS = [(os.environ.get("SIM_KIND", "DK_RECT"), G)]
for _kind in ("DK_FIBO",):
    _prev = os.environ.get("SIM_KIND")
    os.environ["SIM_KIND"] = _kind
    _spec = importlib.util.spec_from_file_location(
        "gearpanel_" + _kind, os.path.join(HERE, "sim-gear-panel.py"))
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    if _prev is None:
        os.environ.pop("SIM_KIND", None)
    else:
        os.environ["SIM_KIND"] = _prev
    MODELS.append((_kind, _mod))

FAIL = []


def mql_unit_lines(path):
    """(origin, lineno, text) following #include "..." in place, like the compiler."""
    out = []
    seen = set()

    def walk(p):
        p = os.path.normpath(p)
        if p in seen:
            return
        seen.add(p)
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            return
        base = os.path.dirname(p)
        for i, ln in enumerate(lines, 1):
            m = re.match(r'\s*#include\s+"([^"]+)"', ln)
            if m:
                cand = os.path.normpath(os.path.join(base, m.group(1).replace("\\", os.sep)))
                if os.path.exists(cand):
                    walk(cand)
                continue
            out.append((p, i, ln))

    walk(os.path.normpath(path))
    return out


def check(cond, msg):
    if not cond:
        FAIL.append(msg)
    return cond


def mql_defines():
    """Read the panel's geometry back out of the MQL, so the gate cannot drift
    from the source it claims to police: a literal changed in DrawStrip.mqh and
    not here is reported, not silently passed."""
    got = {}
    if not os.path.exists(DRAWSTRIP):
        return got
    rx = re.compile(r"#define\s+(DSTRIP_\w+)\s+(\d+)")
    for _, _, line in mql_unit_lines(DRAWSTRIP):
        m = rx.match(line.strip())
        if m:
            got[m.group(1)] = int(m.group(2))
    return got


def bmp_size(name):
    """The raster's own pixels, off its BMP header.

    P-DRAW-86: MT4 CROPS a bitmap label and never scales it, so a bake asked for
    at the wrong width is not a smaller card — it is the LEFT SLICE of the real one.
    The bake's own file is therefore an input to the layout law, not decoration:
    `pnl_card<n>` is the NARROW plate's width and `pnl_cardW*` is the WIDE one's.
    """
    p = os.path.join(ICONS, name)
    if not os.path.exists(p):
        return None
    with open(p, "rb") as fh:
        head = fh.read(26)
    w, h = struct.unpack("<ii", head[18:26])
    return (w, h)


def card_bakes():
    """How many one-piece bakes the narrow plate can ask for: `pnl_card<n>.bmp`."""
    n = []
    for f in os.listdir(ICONS) if os.path.isdir(ICONS) else []:
        m = re.match(r"pnl_card(\d+)\.bmp$", f)
        if m:
            n.append(int(m.group(1)))
    return sorted(n)


def mql_function_body(lines, name):
    """(start, end) unit-line indices of `name`'s body, bracketed by the closing
    brace at column 0 — the style every file in Biotak/ uses."""
    start = None
    for i, (_o, _l, t) in enumerate(lines):
        if re.search(r"^\s*(?:void|int|bool|string|double|color)\s+%s\s*\(" % re.escape(name), t):
            start = i
            break
    if start is None:
        return None
    for j in range(start + 1, len(lines)):
        if lines[j][2].startswith("}"):
            return (start, j)
    return (start, len(lines) - 1)


def narrow_guard(d):
    """THE NARROW/WIDE BOUNDARY, read out of DrawStripGearPlace itself.

    This is the number that was wrong (P-DRAW-86): the guard allowed as many content
    rows narrow as `DSTRIP_GEAR_WIDE_ROWS`, but the plate is `contentEnd + FOOT_H` and
    the card index is `(gh - 104) / 42`, so n content rows need card `n + 1`. Reading
    the expression instead of restating it is the only way this gate can fail when the
    guard is reverted — a transcribed 10 could never disagree with itself.
    """
    if not os.path.exists(DRAWSTRIP):
        return None
    rx = re.compile(
        r"contentEnd\s*-\s*contentTop\s*<=\s*\(?\s*([^)*]+?)\s*\)?\s*\*\s*DSTRIP_GEAR_ROW_H")
    for _, _, line in mql_unit_lines(DRAWSTRIP):
        m = rx.search(line)
        if not m:
            continue
        expr = m.group(1).strip()
        for key, val in d.items():
            expr = re.sub(r"\b%s\b" % key, str(val), expr)
        if re.fullmatch(r"[\d\s+\-*/()]+", expr):
            return int(eval(expr))          # digits and operators only
        return None
    return None


def hit_rects(L, tab, M=None):
    """THE HIT BOXES, from the same seats the paint used.

    This is the gate that would have caught the dead panel. `DrawStripGearHit` is
    a COORDINATE hit test (P-DRAW-84) because every painter in DrawStrip.mqh is
    born OBJPROP_SELECTABLE=false, so MT4 never fires OBJECT_CLICK for a control.
    A control the paint draws but the hit test never asks is a button that cannot
    be pressed — and it compiles, and it looks right, and it is dead. So this
    function mirrors the MQL's own `DrawStripGearHit` and the gate asserts that
    every PAINTED control has a NON-EMPTY hit rect on every state.

    P-DRAW-117: the TAB ROW is retired, and the group headers are ROWS — they are
    asked by the SAME row loop, against the SAME `s_dsGRY/Col` seats the paint
    writes (DrawStrip_Base.mqh, the row probe). So they arrive here through the
    `row` blocks below, exactly like the settings they open — which is the whole
    point of the accordion: one seat array, one hit test, no second grid.
    """
    if M is None:
        M = globals()["G"]
    G = M          # this mirror's own constants (the gate walks more than one kind)
    rects = []
    PAD = G.PAD
    HEAD_H, ROW_H = G.HEAD_H, G.ROW_H
    FOOT_BW, GEAR_W = G.FOOT_BW, G.GEAR_W
    cap_w = G.cap_w
    px, gy = PAD, 0
    colW = GEAR_W - 2 * PAD

    # the head's X, and the head itself (the carry)
    rects.append(("head X", 26, 26))
    rects.append(("head carry", GEAR_W, HEAD_H))

    for b in L["blocks"]:
        kind, name, y = b[0], b[1], b[2]
        ry = gy + y
        if kind == "section":
            continue                       # a caption band is not a control
        elif kind == "caption":
            # P-DRAW-90: a caption that SHARES its row with a field owns that
            # field — it is the Color group's hex seat, and it must have a box.
            rects.append(("edit " + name, colW - cap_w(), G.EDIT_H))
        elif kind == "grid":
            # the block's OWN cell count, not the 5 this mirror used to assume
            n = int(b[3][0]) if b[3] else 0
            for i in range(n):
                rects.append(("grid %s[%d]" % (name, i), G.CHIP_W, G.CHIP_H))
        elif kind == "swq":
            # P-DRAW-118 (2026-10-01) — THE COLOUR ROLE ROW. Every cell of it is a GRID
            # cell (`s_dsGGKind` 0/2/3), and the MQL asks them all through the same grid
            # probe that reads `s_dsGGX/Y/W/H` — so the boxes are the paint's own seats:
            # the preview, the palette's own row, and the `+` opener.
            rects.append(("swq %s preview" % name, G.SWQ_PREV, G.SWQ_CELL))
            for i in range(G.SWQ_N):
                rects.append(("swq %s[%d]" % (name, i), G.SWQ_CELL, G.SWQ_CELL))
            rects.append(("swq %s +" % name, G.SWQ_PLUS, G.SWQ_PLUS))
        else:
            rects.append(("row " + (name or ""), colW, ROW_H))

    # the foot — P-DRAW-90: three commands, the design's own `Reset | All · Copy`.
    # The SEAT is the paint's (DrawStripFootX, 280/592 wide per tab); this mirror
    # only asserts each one owns a non-empty box, which is what the dead-button
    # class (P-DRAW-84) needs.
    for label in ["Reset", "All", "Copy"][:G.FOOT_N]:
        bw = max(FOOT_BW, 32 + mt4.text_w(label, 8) + 8)
        rects.append(("foot " + label, bw + 16, 28 + 16))
    return rects


def no_chart_colour():
    """THE PANEL NEVER TAKES A COLOUR OFF THE CHART (P-DRAW-89).

    The plate's transparency was retired, and the bug it carried is the one class
    no compiler names: `StrapBodyTone` short-circuited to `GetCachedChartBgColor()`,
    so every tone-driven surface (the tab track, the rows, the cells, the grips)
    wore `CHART_COLOR_BACKGROUND` — cyan on the dark template, magenta-blue on the
    light one. Measured: census `bgcolor=-16924895` = 0xFEFDBF21, a value in no
    palette and no painter here.

    So the gate asserts the SURFACE PANEL code reads no chart colour at all. The
    one legitimate reader is the box's own mid-ink blend (a chart OBJECT's colour,
    not a panel surface) and is named here rather than skipped blindly.
    """
    allowed = {}          # file:line -> the reason that read is allowed
    n = 0
    for origin, ln, line in mql_unit_lines(DRAWSTRIP):
        s = line.strip()
        if s.startswith("//") or s.startswith("//---"):
            continue
        if "GetCachedChartBgColor" not in s and "CHART_COLOR_BACKGROUND" not in s:
            continue
        n += 1
        tag = "%s:%d" % (os.path.basename(origin), ln)
        if "BlendColorTowardsBG" in s and "BOX_MID_FADE" in s:
            allowed[tag] = "the box's own mid ink, not a panel surface"
            continue
        check(False, "%s reads a chart colour into a panel surface: %s"
              % (tag, s[:90]))
    return n, len(allowed)


def main():
    want_png = "--png" in sys.argv

    print("=" * 66)
    print("GEAR PANEL GATE  (%s)" % os.path.basename(DRAWSTRIP))
    print("=" * 66)

    # 1. the literals agree with the source
    d = mql_defines()
    pairs = [("DSTRIP_GEAR_W", G.GEAR_W), ("DSTRIP_GEAR_W2", G.GEAR_W2),
             ("DSTRIP_GEAR_PAD", G.PAD), ("DSTRIP_GEAR_HEAD_H", G.HEAD_H),
             ("DSTRIP_GEAR_ROW_H", G.ROW_H), ("DSTRIP_GEAR_FOOT_H", G.FOOT_H),
             ("DSTRIP_GEAR_AIR", G.AIR), ("DSTRIP_ROW_GAP", G.ROW_GAP),
             ("DSTRIP_GEAR_LBL_PT", G.LBL_PT),
             # P-DRAW-117: the accordion's own numbers — the group row's kind, the
             # digest's inset, the level list's block pitch and the row ceiling the
             # mirrors read for their own row budget.
             ("DSTRIP_GEAR_DG_PAD", G.DG_PAD), ("DSTRIP_GRK_GROUP", G.GRK_GROUP),
             # P-DRAW-118: the COLOUR ROLE ROW's own seats — the mirror renders the
             # cards' quick row from these, so a retuned cell or count must fail HERE.
             ("DSTRIP_GEAR_SWQ_N", G.SWQ_N), ("DSTRIP_GEAR_SWQ_CELL", G.SWQ_CELL),
             ("DSTRIP_GEAR_SWQ_GAP", G.SWQ_GAP), ("DSTRIP_GEAR_SWQ_PREV", G.SWQ_PREV),
             ("DSTRIP_GEAR_SWQ_PLUS", G.SWQ_PLUS),
             ("DSTRIP_GRG_SWATCH", G.GRG_SWATCH), ("DSTRIP_GRG_PREV", G.GRG_PREV),
             ("DSTRIP_GRG_PLUS", G.GRG_PLUS),
             ("DSTRIP_GEAR_CAP_DX", G.CAP_DX),
             ("DSTRIP_GEAR_LVLBLK", G.LVLBLK), ("DSTRIP_GLIST_MAX", G.GLIST_MAX)]
    if d:
        for key, mine in pairs:
            if key in d:
                check(d[key] == mine, "literal %s: mql=%d sim=%d" % (key, d[key], mine))
        print("  literals: %d compared against DrawStrip.mqh" % len([k for k, _ in pairs if k in d]))
    else:
        print("  literals: DrawStrip.mqh not readable - NOT CHECKED")

    # 1b. THE BAKE SET IS THE LAW (P-DRAW-86). A narrow plate must ask for a bake
    # that exists; if it does not, DrawStripGearPlate's else-branch composes the W
    # body, whose bake is GEAR_W2+28 wide, and MT4 crops it to the narrow width — a
    # 312px panel painted as the left half of a 624px card. The two facts that decide
    # this are both readable here: the guard's own row ceiling (from the MQL) and the
    # bakes' own widths (from the BMP headers).
    nreads, nok = no_chart_colour()
    print("  chart-colour reads: %d total, %d allowed (panel surfaces must be 0)" % (nreads, nok))
    bakes = card_bakes()
    rows_max = narrow_guard(d)
    if rows_max is None:
        print("  narrow guard: DrawStripGearPlace not readable - NOT CHECKED")
    else:
        # P-DRAW-117: AND THE COUNT IS THE ROWS THEMSELVES. With the tab band retired
        # the body starts at the head (`contentTop` = 56), so the plate's height is
        # `56 + 42R + 48` = `104 + 42R` and `cardN` = R — the tab build's `R + 1` is
        # the extra cell it carried for the tab row. So the ceiling is R <= the last
        # bake, not R + 1 <= it.
        check(bakes and rows_max <= bakes[-1],
              "narrow guard allows %d rows -> cardN=%d, but pnl_card stops at %d "
              "-> the plate falls to the composed W body (%.0fpx bake in a %dpx plate)"
              % (rows_max, rows_max, bakes[-1] if bakes else 0,
                 bmp_size("pnl_cardWtop.bmp")[0] if bmp_size("pnl_cardWtop.bmp") else 0,
                 G.GEAR_W))
        print("  narrow guard: <= %d rows (cardN %d) against %d bake(s) pnl_card1..%d"
              % (rows_max, rows_max, len(bakes), bakes[-1] if bakes else 0))
    wn = bmp_size("pnl_card%d.bmp" % bakes[-1]) if bakes else None
    ww = bmp_size("pnl_cardWtop.bmp")
    if wn:
        check(wn[0] == G.GEAR_W + 28,
              "pnl_card%d.bmp is %dpx wide, the narrow plate asks for %d"
              % (bakes[-1], wn[0], G.GEAR_W + 28))
    if ww:
        check(ww[0] == G.GEAR_W2 + 28,
              "pnl_cardWtop.bmp is %dpx wide, the wide plate asks for %d"
              % (ww[0], G.GEAR_W2 + 28))
    if wn and ww:
        print("  bakes: narrow %dx%d  wide %dx%d" % (wn[0], wn[1], ww[0], ww[1]))

    # 1d. THE COLUMN WIDTH IS THIS TAB'S BEFORE THE CONTENT READS IT (P-DRAW-91).
    # `DrawStripGearContent` sizes the hex fields from `DrawStripGearColW()` =
    # `s_dsGearW - 2*PAD`, so `s_dsGearW` must already hold THIS tab's width when it
    # runs. It was reset only inside `DrawStripGearPlace`, which the layout calls
    # AFTER the content pass: open Style/Row (624), switch to Paint, and the Paint
    # tab measured its COLOR/FILL fields against the previous tab's 592 while the
    # plate asked for 312 — two bars 312px past the card's right edge, reported on a
    # live terminal 2026-09-30.
    #
    # ORDER HERE MEANS EXECUTION, NOT TEXT. The first cut of this assertion compared
    # two unit-line indices and a deliberately reverted tree PASSED it, because
    # `DrawStripGearPlace` is DEFINED above `DrawStripGearLayout` — the wording came
    # first, the call came last. So the source is read as the two FUNCTION BODIES:
    # inside the layout, the reset must precede the call; inside the place, it must
    # not appear at all. Measured on the reverted tree: `resets=0` in the layout.
    lines = list(mql_unit_lines(DRAWSTRIP))
    lay = mql_function_body(lines, "DrawStripGearLayout")
    plc = mql_function_body(lines, "DrawStripGearPlace")
    if lay:
        ls, le = lay
        inside = list(enumerate(lines[ls:le], ls))
        resets = [i for i, (_o, _l, t) in inside
                  if re.search(r"s_dsGearW\s*=\s*DSTRIP_GEAR_W\s*;", t)]
        calls = [i for i, (_o, _l, t) in inside
                 if re.search(r"DrawStripGearContent\s*\(\s*y\s*,", t)]
        check(len(calls) == 1,
              "DrawStripGearLayout: %d DrawStripGearContent call(s), expected 1 (P-DRAW-91)"
              % len(calls))
        check(len(resets) == 1,
              "DrawStripGearLayout: `s_dsGearW = DSTRIP_GEAR_W` is written %d time(s) — "
              "ONE, and BEFORE DrawStripGearContent (P-DRAW-91)" % len(resets))
        if resets and calls:
            check(resets[0] < calls[0],
                  "DrawStripGearLayout: the column reset at unit line %d comes AFTER "
                  "DrawStripGearContent at %d — the hex fields measure against the "
                  "PREVIOUS tab's column and run off the card (P-DRAW-91)"
                  % (resets[0], calls[0]))
            print("  column width: 1 writer of s_dsGearW=DSTRIP_GEAR_W at unit line %d, "
                  "before DrawStripGearContent at %d (P-DRAW-91)" % (resets[0], calls[0]))
    else:
        print("  column width: DrawStripGearLayout not readable - NOT CHECKED")

    # 1e. THE PLATE'S WIDTH IS THE SAME TAB'S (P-DRAW-91b). `s_dsGearW0` is what the
    # head, the tab row, the foot, the plate bake and the grip all read — so a value
    # left over from the PREVIOUS tab draws this tab's chrome at another tab's width
    # (a 624 head over a 312 body, or the reverse). It may therefore only ever hold 0
    # (nothing open) or `s_dsGearW` (this pass's own decision), and the assignment must
    # be the one that immediately follows the layout call.
    if True:
        writes = [(_o, _l, t) for _o, _l, t in lines
                  if re.search(r"s_dsGearW0\s*=", t) and "static" not in t]
        bad = [w for w in writes if not re.search(r"s_dsGearW0\s*=\s*(0|s_dsGearW)\s*;", w[2])]
        check(not bad,
              "s_dsGearW0 takes a value that is neither 0 nor s_dsGearW: %s — the "
              "panel's chrome would wear another tab's width (P-DRAW-91b)"
              % ", ".join("%s:%d" % (src, ln) for src, ln, _t in bad))
        check(len(writes) == 2,
              "s_dsGearW0 is written %d time(s); expected exactly the pair `= 0` (nothing "
              "open) and `= s_dsGearW` (this pass) (P-DRAW-91b)" % len(writes))
        if not bad:
            print("  plate width: s_dsGearW0 only 0 / s_dsGearW (%d write(s)) - one tab's "
                  "own answer (P-DRAW-91b)" % len(writes))
    if plc:
        ps, pe = plc
        second = [(_o, _l) for _o, _l, t in lines[ps:pe]
                  if re.search(r"s_dsGearW\s*=\s*DSTRIP_GEAR_W\s*;", t)]
        check(not second,
              "DrawStripGearPlace writes `s_dsGearW = DSTRIP_GEAR_W` again (%s) — the "
              "second writer of one value, and too late for the first reader "
              "(P-DRAW-91)" % (", ".join("%s:%d" % s for s in second) or "?"))

    # 2. per GROUP: height lands on the plate law, and every painted face exists.
    # P-DRAW-117 (2026-10-01) — AND EVERY GROUP OF MORE THAN ONE KIND IS WALKED.
    # The old loop walked the four tabs of a rectangle only, so the LEVELS group
    # (the fibo family's own list, and the one group whose rows are elastic) was
    # never rendered by a gate that claims to render "every tab of the panel". A
    # second import of the same mirror with `SIM_KIND` set is the same model on a
    # fibo — one mirror, two states, no second table.
    for kind_name, M in MODELS:
        print("")
        print("  ---- %s: %d group(s) — %s" % (kind_name, len(M.TABS), ", ".join(M.TABS)))
        for t, name in enumerate(M.TABS):
            L = M.layout(t)
            gh, gw, cn, ex = L["h"], L["w"], L["card_n"], L["exact"]
            # the plate's own law is the 42 grid: with the tab band retired the body
            # starts at the head, so `gh = 104 + 42R` for R rows (cardN = R when the
            # plate is narrow; a WIDE plate composes and its cardN is the taller
            # column's row count, which is allowed past 10 by construction).
            check((gh - 104) % 42 == 0, "%s/%s: gh=%d misses (104+42n)" % (kind_name, name, gh))
            if gw == M.GEAR_W:
                # P-DRAW-86: a NARROW plate must fit the baked card set (1..10)
                check(1 <= cn <= 10,
                      "%s/%s: narrow cardN=%d has no bake — the plate would be the "
                      "left half of a %dpx W card" % (kind_name, name, cn, M.GEAR_W2 + 28))
            branch = ("bake pnl_card%d" % cn) if gw == M.GEAR_W else "composed W"
            print("  %-6s gh=%-4d w=%-4d cardN=%-3d %-16s blocks=%d rows=%d"
                  % (name, gh, gw, cn, branch, len(L["blocks"]),
                     (gh - 104) // M.ROW_H))
            if L.get("unmodelled"):
                check(False, "%s/%s: statements the walker did not model: %s"
                      % (kind_name, name, "; ".join(L["unmodelled"][:3])))

            notes = []
            c = M.paint(L, notes, t)
            if want_png and M is G:
                W, H = gw + 56, gh + 60
                w, h, rgba = c.to_raster(W, H)
                open(os.path.join(HERE, "legacy", "gear-%d.png" % t), "wb").write(mt4.png(w, h, rgba))

            # P-DRAW-90: A `None` NAME IS A HOLE, and the old `and op[1]` filter
            # threw it away — so the one class this gate exists for (a face the panel
            # paints that no file backs, P-PANELUI-01) could not fail it. Measured:
            # the mirror asked for `gl_filter_m.bmp`, absent from every commit.
            holes = sorted({op[1] for op in c.ops if op[0] == "img" and op[1] is None})
            faces = sorted({op[1] for op in c.ops if op[0] == "img" and op[1]})
            missing = [f for f in faces if not os.path.exists(os.path.join(ICONS, f))]
            check(not holes and not missing,
                  "%s/%s: painted face(s) missing on disk: %s"
                  % (kind_name, name, ", ".join(missing) or "(a NAMED hole)"))
            check(len(faces) > 0, "%s/%s: painted no raster at all" % (kind_name, name))

            # P-DRAW-110: AND NOTHING IS PAINTED BESIDE THE PLATE. The plate is the
            # rect its own bakes cover — `(-14, -14)` to `(gw + 14, gh + 14)`, because
            # every cap is asked `gw + 28` at `-14` and the composed body must close
            # on the same bottom edge. A face whose box leaves it is off the card the
            # user sees: the composed W body started at the top cap's HEIGHT (`+70`)
            # instead of its edge (`+56`, the head), so the body ran 14px low and the
            # foot cap ended at `gy + gh + 28`. The narrow plates bake and never show
            # it.
            out = [(o[1], o[2], o[3], o[4], o[5]) for o in c.ops
                   if o[0] == "img" and (o[2] < -14 or o[3] < -14 or
                                         o[2] + (o[4] or 0) > gw + 14 or
                                         o[3] + (o[5] or 0) > gh + 14)]
            check(not out, "%s/%s: %d face(s) painted off the plate: %s"
                  % (kind_name, name, len(out),
                     "; ".join("%s at %s,%s %sx%s" % t for t in out[:3])))

            # every block must own its own seat: stacked labels are the one defect a
            # height check cannot see, because the height stays right. The seat is the
            # WHOLE seat, `(column, y)` — a WIDE plate packs BOTH columns from
            # contentTop on purpose, so a bare y repeats by design there.
            seats = [(b[4] if len(b) > 4 else 0, b[2]) for b in L["blocks"]]
            check(len(seats) == len(set(seats)),
                  "%s/%s: two blocks share a seat -> stacked labels" % (kind_name, name))

            # THE DEAD-BUTTON GATE. A control the paint draws and the coordinate hit
            # test never asks is a button that cannot be pressed. This is the whole
            # class that shipped: P-DRAW-84, every control in this panel was one.
            hits = hit_rects(L, t, M)
            empty = [n for n, w, h in hits if w <= 0 or h <= 0]
            check(not empty, "%s/%s: control(s) with no hit box: %s"
                  % (kind_name, name, ", ".join(empty)))
            # and the count of hit boxes must cover the count of painted controls —
            # with the grid's OWN cell count, not a hard-coded 5
            painted = [b for b in L["blocks"] if b[0] in ("row", "caption", "grid", "swq")]
            ncells = sum(int(b[3][0]) for b in painted if b[0] == "grid" and b[3])
            # P-DRAW-118: a colour row is preview + the palette's own row + the `+`,
            # and the count is the mirror's parsed SWQ_N (the MQL's own define).
            ncells += sum(2 + M.SWQ_N for b in painted if b[0] == "swq")
            # P-DRAW-117: the tab row's buttons are gone; the two painted controls
            # that are not blocks are the head's X and the head itself (the carry).
            npaint = len(painted) + 2 + ncells
            check(len(hits) >= npaint,
                  "%s/%s: %d hit boxes for %d painted controls"
                  % (kind_name, name, len(hits), npaint))
            print("       %d controls, all with a hit box" % len(hits))

    # 3. seats against the card owner
    print("")
    for label, a, b in G.audit(G.layout(0)):
        check(a == b, "seat %s: panel=%s card=%s" % (label, a, b))
    print("  seats: %d compared against BiotakPanels.mqh" % len(G.audit(G.layout(0))))

    # 4. GROUP ARITY: the registry, the names, the faces and the digests agree.
    # P-DRAW-117 (2026-10-01) — a group is a ROW of the panel's own nav, so a group
    # the registry lists but the name, the icon or the DIGEST table does not answer is
    # a row with no word, no face or no value: it compiles, it paints, and it says
    # nothing — which is the shape every one of this panel's shipped defects had.
    reg = G.REGISTRY
    check(len(reg) >= 2, "DrawStripGearGroups lists %d group(s)" % len(reg))
    for gid, guard in reg:
        check(gid.startswith("DSTRIP_GEAR_"), "registry id %s is not a DSTRIP_GEAR_* id" % gid)
        for fn in ("DrawStripGearGroupText", "DrawStripGearGroupRes", "DrawStripGearGroupDigest",
                   "DrawStripGearGroupTip"):
            span = mql_function_body(lines, fn)
            txt = "\n".join(l for _o, _l, l in lines[span[0]:span[1]]) if span else ""
            check(span and gid in txt, "%s() has no branch for %s (P-DRAW-117)" % (fn, gid))
    print("  groups: %d in the registry (%s), each with a name, a face and a digest"
          % (len(reg), ", ".join(g for g, _ in reg)))

    print("")
    if FAIL:
        print("[FAIL] gear panel gate: %d problem(s)" % len(FAIL))
        for f in FAIL:
            print("   - %s" % f)
        return 1
    print("[PASS] gear panel gate: %d group(s) over %d kind(s), %d seats, all faces present"
          % (len(G.TABS), len(MODELS), len(G.audit(G.layout(0)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
