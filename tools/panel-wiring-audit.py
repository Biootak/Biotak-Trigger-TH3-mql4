"""panel-wiring-audit — the gate behind P-UI-47 / P-UI-70 (panel controls).

WHAT IT PROVES, and why each half exists
-----------------------------------------
The settings card is a four-layer machine: the SPEC says which rows exist, the
SET DEF says what kind of control each row is, the VALUE layer
(PnlDefValSet / PnlCurrentSet / PnlApplySet) reads and writes the runtime
setting, and the SETTINGS LAYER (RuntimeSettings.mqh) persists it. Every bug the
user reported as "this control does nothing / it forgets my setting" was one of
those four layers disagreeing with the other three:

  * P-UI-47  a row whose runtime copy is consumed by NOBODY (a slider that
             writes a mirror the engine never reads);
  * P-UI-70c the same row RETIRED half-way (the spec row deleted while its
             address kept working) and a caption that named nothing;
  * P-UI-70d a whole feature (the TRex card's size / gap / colours) that lived
             only in the Inputs dialog, i.e. a control that did not exist.

So the gate walks the REAL source and requires, for every card:

  [spec]    every row's kind is one the renderer and the press pipeline know;
  [def]     every LEGACY row's setting has a PnlSetDef branch (its kind/label);
  [values]  every non-band row's setting has a PnlDefValSet AND a PnlCurrentSet
            branch, and - unless it is a colour row - a PnlApplySet branch;
  [persist] every setting a panel row can WRITE is persisted by the settings
            layer (an override key) or is derived from one, so a change cannot
            die with the session;
  [palette] every colour kind the panel hands to the palette is handled by all
            four palette functions, and the palette's target table is exactly
            PAL_BASE_TARGETS long (a short table is a kind the cycler cannot
            name);
  [press]   the press chain is self-healing and the whole card is grabbable
            (P-UI-70a/b), i.e. the two defects the user felt as "the panels
            can't be dragged" and "buttons stop working";
  [chrome]  every bitmap the runtime can load is DECLARED with a #resource and
            exists on disk — the P-UI-71c class, where a composed card body was
            sliced, referenced and never declared, so the whole card rendered
            as loose widgets on the chart ("پشت پس زمینه نداره");
  [mouse]   the physical mouse button has ONE owner (P-UI-73) and a gesture is
            only torn down by a release, so a press-side CLICK/OBJECT_CLICK echo
            cannot kill the drag that same press started;
  [heal]    no panel gesture LATCH can outlive its gesture (P-UI-81): a press
            edge — the one witness the terminal cannot withhold — reaps every
            latch through its own finish path, so one missed release can never
            brick every control of every card.

USAGE
-----
    python tools/panel-wiring-audit.py            # source checks
    python tools/panel-wiring-audit.py --quiet
    python tools/panel-wiring-audit.py --selftest # negative control
"""

import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PANELS = os.path.join(ROOT, "Biotak", "BiotakPanels.mqh")
SETTINGS = os.path.join(ROOT, "Biotak", "RuntimeSettings.mqh")
KIT = os.path.join(ROOT, "Biotak", "BiotakKit.mqh")
MENU = os.path.join(ROOT, "Biotak", "BiotakMenu.mqh")
GLOBALS = os.path.join(ROOT, "Biotak", "GlobalVariables.mqh")
ENTRY = os.path.join(ROOT, "Biotak Trigger TH3.mq4")
# P-LM-09: the second entry. Lite compiles the domain half and no UI half, so the
# leg meter's timer line must exist in ONE OnTimer and not both (P-BUILD-01's shape).
ENTRY_LITE = os.path.join(ROOT, "Biotak Trigger TH3 Lite.mq4")
UTILS = os.path.join(ROOT, "Biotak", "UtilityFunctions.mqh")
BASEKNOT = os.path.join(ROOT, "Biotak", "BaseKnotTool.mqh")
# P-UI-96: the TH3 item's own modules - the arm path's three halves live one
# per file (the press in the menu, the session in the controller, the toggle in
# the tool), and the mouse-move channel's owner lives in the event router.
TH3TOOL = os.path.join(ROOT, "Biotak", "TH3Tool.mqh")
TH3CTRL = os.path.join(ROOT, "Biotak", "TH3", "TH3Controller.mqh")
TH3RENDER = os.path.join(ROOT, "Biotak", "TH3", "TH3Renderer.mqh")
EVENTS = os.path.join(ROOT, "Biotak", "EventHandlers.mqh")
PIPELINE = os.path.join(ROOT, "Biotak", "LevelPipeline.mqh")
HTF = os.path.join(ROOT, "Biotak", "HTFCandles.mqh")
ICONS = os.path.join(ROOT, "Files", "Icons")
MANIFEST_PATH = os.path.join(ROOT, "tools", "icon-manifest.txt")
# P-LM-19: the baked handle rasters' palette — the [leg-dir] check keeps the
# generator's two colours on the same two the line wears.
GENICONS = os.path.join(ROOT, "tools", "gen-th3-icons.js")
# P-TH-01: the fractal ladder and its two measuring sticks — the modules the
# [th-percent] check and its mutants patch.
FRACTALS = os.path.join(ROOT, "Biotak", "FractalTimeframes.mqh")
THCALC = os.path.join(ROOT, "Biotak", "THCalculations.mqh")
ADAPT = os.path.join(ROOT, "Biotak", "AdaptiveScaling.mqh")

QUIET = "--quiet" in sys.argv
_PATCHED = {}


def read(path):
    if path in _PATCHED:
        return _PATCHED[path]
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


RET_TYPES = ("void", "int", "double", "string", "bool", "color", "long",
             "datetime", "short", "float", "char", "uchar", "uint", "ulong")


def body(text, sig):
    """The `{ ... }` body of the DEFINITION of the function named in `sig`.

    SR-PANELWIRE-0: this used to be `text.find(sig)`, i.e. the first textual
    mention - and a doc comment that merely NAMED the function returned the
    NEXT function's body instead. Every check built on it then passed for the
    wrong reason (a gate that is vacuous is worse than no gate), so the lookup
    is anchored on a line-start definition whose prefix is a return type.

    Brace-counted from the opening brace, so a nested block cannot terminate
    the scan early.
    """
    name = sig.rstrip("(").split()[-1]     # accept both "Name(" and "void Name("
    for m in re.finditer(r"\b" + re.escape(name) + r"\s*\(", text):
        line_at = text.rfind("\n", 0, m.start()) + 1
        prefix = text[line_at:m.start()]
        if prefix.strip() == "":
            continue                       # a continuation line / a call
        if prefix.lstrip().startswith("//") or prefix.lstrip().startswith("*"):
            continue                       # a comment that names the function
        if re.fullmatch(r"\s*(?:%s)\s*&?\s*" % "|".join(RET_TYPES), prefix) is None:
            continue
        at = m.end()
        break
    else:
        return None
    i = text.find("{", at)
    if i < 0:
        return None
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return None


def stmt_body(text, head):
    """The `{ ... }` body of a STATEMENT whose line starts with `head` - an `if(...)`
    branch, a `for(...)` loop, a bare call. `body()` above anchors on a function
    DEFINITION (SR-PANELWIRE-0) and cannot reach a branch at all: it looks the
    signature up as a name and requires a return-type prefix, so `body(x,
    "if(id == CHARTEVENT_OBJECT_CLICK)")` never matched anything and every check
    built on it reported its "the branch lost its call" fault on clean source - a
    gate that fires unconditionally is as useless as one that never fires. The
    first matching statement wins (the branches of a router are written in the
    order the events are handled). Brace-counted from the opening brace, so a
    nested block cannot terminate the scan early.
    """
    for m in re.finditer(r"(?m)^[ \t]*" + re.escape(head) + r"[ \t]*\r?\n?[ \t]*\{",
                         text):
        i = m.end() - 1
        depth = 0
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    return text[i + 1:j]
        break
    return None


def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


# ─────────────────────────────────────────────────────────────────────────────
# SR-PANELWIRE-1: the spec (which rows exist, and of what kind)
# ─────────────────────────────────────────────────────────────────────────────
KINDS = {"PNL_K_SL": 0, "PNL_K_SW": 1, "PNL_K_SEG": 2, "PNL_K_COL": 4,
         "PNL_K_NAV": 5, "PNL_K_TXT": 6, "PNL_K_SEC": 7, "PNL_K_CSET": 8,
         "PNL_K_DUAL": 9, "PNL_K_LEGACY": -1}


def parse_spec(text):
    """PnlSpecBuild -> {item: [ (kind_name, s0, n) ... ]} in source order."""
    blk = body(text, "void PnlSpecBuild(")
    if blk is None:
        return None
    out = {}
    for m in re.finditer(r"PnlSpecAdd\(\s*(\d+)\s*,\s*(\w+)\s*,\s*(-?\d+)\s*,\s*(\d+)", blk):
        item, kind, s0, n = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4))
        out.setdefault(item, []).append((kind, s0, n))
    return out


# ─────────────────────────────────────────────────────────────────────────────
# SR-PANELWIRE-2: the value layer (per item block, which addresses it speaks)
# ─────────────────────────────────────────────────────────────────────────────
def item_block(text, sig, item):
    """The `case N:` arm of a switch, or the `if(item==N)` arm of a chain."""
    whole = body(text, sig)
    if whole is None:
        return None
    m = re.search(r"case\s+%d\s*:(.*?)(?=\n\s*case\s+\d+\s*:)" % item, whole, re.S)
    if m:
        return m.group(1)
    m = re.search(r"if\(item\s*==\s*%d\)(.*?)(?=\n\s*else\s+if\(item\s*==\s*\d+\)|\Z)" % item,
                  whole, re.S)
    return m.group(1) if m else None


def rows_spoken(block):
    """Which SETTING rows a value-layer arm speaks, and whether it has a
    fallthrough.

    SR-PANELWIRE-2b: comments are stripped first. A commented-out branch
    (`//case 5: ... if(row==0) ...`) used to count as coverage for the row it
    named, i.e. a gate could be satisfied by code that no longer runs.
    """
    if block is None:
        return None, False
    block = strip_comments(block)
    rows = set(int(x) for x in re.findall(r"row\s*==\s*(\d+)", block))
    for lo, hi in re.findall(r"row\s*>=\s*(\d+)\s*&&\s*row\s*<=\s*(\d+)", block):
        rows.update(range(int(lo), int(hi) + 1))
    return rows, bool(re.search(r"\belse\b", block))


def covered_rows(rows, has_else, top):
    """`rows` plus whatever the fallthrough answers.

    The renderer's own convention: the LAST address is always answered by the
    trailing unconditional statement (which is why a bare `return 0;` is a
    branch), and a real `else` answers everything between the highest explicit
    address and the top - which is how card 2's `else` carries CARD MARGIN
    while rows 14..18 above it are palette-only colour rows.
    """
    out = set(rows)
    if top >= 0:
        out.add(top)
    if has_else and rows:
        for r in range(max(rows) + 1, top + 1):
            out.add(r)
    return out


VALUE_KINDS = {0, 1, 2, 6, 8, 9}   # slider / switch / segment / text / cset / dual


def kind_of(arm):
    """The kind a legacy def arm declares (a bare slider when it says nothing)."""
    m = re.search(r"\bkind\s*=\s*(PNL_K_\w+|\d+)", strip_comments(arm))
    if m is None:
        return 0
    tok = m.group(1)
    return KINDS[tok] if tok in KINDS else int(tok)


def def_row_arms(arm_text, top):
    """[(setting row, arm text)] for a def/apply arm, the trailing `else`
    included as `top`. The LAST bare `else` wins, which is what keeps card 3's
    nested TH-mode else from being mistaken for the card's own fallthrough.
    """
    out = list(row_arms(arm_text)) if arm_text else []
    if arm_text:
        tail = None
        for m in re.finditer(r"(?:^|\n)\s*else\b(?!\s*if)", arm_text):
            tail = arm_text[m.end():]
        if tail is not None:
            row = top if top is not None else (max(r for r, _ in out) + 1 if out else 0)
            out.append((row, tail))
    return out


def def_row_kinds(arm_text, top):
    """setting row -> kind, including the arm's own trailing `else`."""
    out = {}
    for row, arm in def_row_arms(arm_text, top):
        # a NESTED else (card 3's TH-mode branch) sets no caption, so requiring
        # one on the fallthrough keeps the two apart.
        if row == top and 'label=' not in arm.replace(" ", ""):
            continue
        out[row] = kind_of(arm)
    return out


def settings_written(block):
    """`g_x = ...` assignments inside the value layer's arm."""
    if block is None:
        return set()
    return set(re.findall(r"\b(g_\w+)\s*=", strip_comments(block)))


# ─────────────────────────────────────────────────────────────────────────────
# SR-PANELWIRE-3: the colour kinds the panel can hand to the palette
# ─────────────────────────────────────────────────────────────────────────────
def colour_kinds(text):
    """Every PAL_* a panel row can target, with the site that names it."""
    blk = body(text, "int PnlColorKindSet(")
    if blk is None:
        return None
    out = {}
    for m in re.finditer(r"return\s+(PAL_\w+)\s*\+", blk):
        out.setdefault(m.group(1), "an offset family")
    for m in re.finditer(r"return\s+(PAL_\w+)\s*;", blk):
        out.setdefault(m.group(1), "a fixed row")
    # the delegated families (card 12's tabs) are checked through their own defs
    for m in re.finditer(r"return\s+(\w+)\(", blk):
        for k in re.findall(r"PAL_\w+", body(text, "int %s(" % m.group(1)) or ""):
            out.setdefault(k, "via %s()" % m.group(1))
    return out


# ─────────────────────────────────────────────────────────────────────────────
# SR-PANELWIRE-4: the press chain (P-UI-70)
# ─────────────────────────────────────────────────────────────────────────────
def check_press(text):
    problems = []
    blk = body(text, "void PnlHandleMouseMove(")
    if blk is None:
        return ["PnlHandleMouseMove() is gone - the panel has no pointer engine"]
    if "PnlPressAllowed()" not in blk:
        problems.append("the press chain is not self-healing: a stale drag claim "
                        "dead-locks every coordinate control (P-UI-70b)")
    # P-UI-75a: the GRAB has ONE owner and TWO entries (the press chain and the
    # polled shadow), so every promise P-UI-70a made about it is asserted at that
    # owner - a chain that still spelled `PnlCardBodyHit(` itself would mean the
    # grab had been copied back into the chain, which is the drift this project
    # keeps paying for.
    grab = body(text, "bool PnlTryGrabMove(")
    if grab is None:
        problems.append("PnlTryGrabMove() is gone - the grab has no owner, so the "
                        "press chain and the polled shadow cannot share one "
                        "contract (P-UI-75a)")
    else:
        if "PnlCardBodyHit(" not in grab:
            problems.append("the card body is not a drag handle - only the 56 px "
                            "header can move the panel (P-UI-70a)")
        if "PnlHeaderHit(" not in grab:
            problems.append("the header is no longer a drag handle")
        if "DragClaim(DRAG_PANEL_MOVE)" not in grab:
            problems.append("the header/body drag no longer claims DRAG_PANEL_MOVE "
                            "(it must not borrow the knob's identity)")
        if "g_PnlMoveItem" not in grab or "CircLockChart()" not in grab:
            problems.append("the grab no longer records the gesture / locks the view")
    if "PnlTryGrabMove(mx,my,false)" not in blk:
        problems.append("the press chain no longer reaches the grab - a press on "
                        "the card falls on the floor")
    # EVERY affordance, not a sample: the grab turns an unclaimed press into a
    # panel MOVE, so a control consulted after it does not just "not work" - it
    # drags the whole card away under the user's finger. The order rule is now
    # anchored on the SHARED predicate the grab asks (`PnlPointOnControl`), which
    # must name the same controls, in the same order, as the press chain.
    # R-KEYCAP (2026-09-14): the header's .key cap joined the list - it sits
    # INSIDE the drag handle, so a cap the chain does not claim before the grab
    # is a cap that moves the card instead of flipping the switch it advertises.
    CONTROLS = ("PnlClosePressHit(", "PnlDdAnchorHit(", "PnlKnobHit(",
                "PnlTrackHit(", "PnlSwitchHit(", "PnlCsetHit(",
                "PnlDualHit(", "PnlColorAddHit(", "PnlQuickSwatchHit(",
                "PnlBandHit(", "PnlKeycapHit(")
    pc = body(text, "string PnlPressClaimCode(")
    if pc is None:
        problems.append("PnlPressClaimCode() is gone - a POLLED grab would steal a "
                        "press aimed at a control (P-UI-75a) and a refusal can no "
                        "longer name the claimant (P-UI-88)")
    else:
        wrapper = body(text, "bool PnlPointOnControl(")
        if wrapper is None or "PnlPressClaimCode(" not in wrapper:
            problems.append("PnlPointOnControl() no longer delegates to the ONE "
                            "claim owner - two lists of controls, free to drift "
                            "(P-UI-88)")
        if "PnlPressClaimCode(" not in (grab or ""):
            problems.append("the grab does not ask the claim owner - the press "
                            "chain and the polled shadow cannot share one list "
                            "(P-UI-88)")
        seen = []
        for control in CONTROLS:
            c = pc.find(control)
            if c < 0:
                problems.append("the grab's control predicate lost %s"
                                % control.rstrip("("))
            else:
                seen.append((c, control))
        if seen != sorted(seen):
            problems.append("the grab's control predicate names the controls in a "
                            "DIFFERENT order than the press chain")
        if "PnlDdHit(" in pc:
            problems.append("the grab's predicate calls PnlDdHit(), which APPLIES "
                            "the option under the cursor")
        elif "g_PnlDdItem" not in pc:
            problems.append("the grab's predicate ignores an OPEN dropdown, which "
                            "owns the next press anywhere")
        # P-UI-76: the RELEASE-channel controls (colour preview, quick swatches,
        # NAV pill, segmented cells, the text field, the header/footer buttons)
        # are claimed on the release, so a grab that eats their press eats their
        # click too - the control reads as DEAD for every click that moved, which
        # is every human click. The grab must refuse their pixels as well, through
        # ONE owner whose geometry is READ BACK from the control's own object.
        if "PnlNameControlAt(" not in pc:
            problems.append("the claim owner lost the RELEASE-channel family "
                            "(PnlNameControlAt), so those widgets are no longer "
                            "named at all (P-UI-76/P-UI-88)")
        # P-UI-88 (2026-09-14): A CLAIM MAY REFUSE A PRESS ONLY IF THE PRESS **IS**
        # ITS ACTION - AND EVERY PRESS LEAVES A LINE.
        #   * the claim owner answers with the claimant's own NAME (a code), so a
        #     refusal reads `C:strip` instead of an anonymous `C` (the report that
        #     needed a screenshot, a coordinate guess and a log archaeology pass);
        #   * `rel` is the ONE claim the grab does NOT refuse: those widgets act on
        #     the RELEASED click, and P-UI-80's dead zone - written AFTER P-UI-76 -
        #     already keeps a tap from moving the card, so the hard refusal only
        #     left the pill / field / button faces as the last un-draggable pixels
        #     of the card («پنل هم درگ نمیشه کردش»);
        #   * every affordance of the press chain names its code AT THE ACT SITE,
        #     the twin of the refusal line, so "nothing happened" and "nothing was
        #     pressed" are distinguishable from the log alone.
        CLAIM_CODES = ("close", "dd", "anch", "knob", "track", "sw",
                       "cset", "dual", "add", "strip", "band", "key", "rel")
        ACT_CODES = ("close", "dd", "anch", "slider", "sw", "cset", "dual",
                     "add", "strip", "band", "key")
        for code in CLAIM_CODES:
            if 'return "%s";' % code not in pc:
                problems.append("the claim owner lost the code `%s` - a press on "
                                "that widget is refused (or stolen) anonymously "
                                "again (P-UI-88)" % code)
        if 'if(ownGesture)' not in (grab or ""):
            problems.append("the grab's refusal is not driven by the ONE "
                            "own-gesture set - the refusal rule and the set it "
                            "names are free to drift (P-UI-89)")
        for code in ("close", "dd", "anch", "knob", "track"):
            if 'claim == "%s"' % code not in (grab or ""):
                problems.append("the own-gesture set lost `%s` - a widget whose "
                                "press IS its own pointer gesture now has its "
                                "gesture stolen (P-UI-89)" % code)
        if 'claim != "" && claim != "rel"' in (grab or ""):
            problems.append("the grab refuses the TAP family outright again - the "
                            "faces of the switch / colour cell / colour strip / "
                            "band / cap are the part of the card that cannot be "
                            "dragged, and the dead zone already protects their "
                            "click (P-UI-88/P-UI-89)")
        if "softClaim" not in (grab or ""):
            problems.append("the grab does not record that its press was soft-"
                            "claimed - a soft grab and a body grab look identical "
                            "in the ledger (P-UI-88)")
        for code in ACT_CODES:
            if 'UIPressAct("%s")' % code not in blk:
                problems.append("the press chain acts for `%s` without naming it - "
                                "the act half of the ledger is silent for that "
                                "control, i.e. a press that DID something leaves no "
                                "line either (P-UI-88)" % code)
        nc = body(text, "bool PnlNameControlAt(")
        if nc is None:
            problems.append("PnlNameControlAt() is gone - the grab can no longer ask "
                            "whether a pixel belongs to a release-channel control")
        else:
            if "PnlCtrlRectHit(" not in nc:
                problems.append("the release-channel controls are hit-tested from "
                                "re-derived constants instead of the object's own "
                                "rect (that is how a hit drifts from a paint)")
            for fam, names in (("colour preview", ('"CB"',)),
                               ("quick swatches", ('"Q"', "PNL_QSW_N")),
                               ("NAV pill", ('"NAV"',)),
                               ("segmented cells", ('"C"',)),
                               ("text field", ('"ED"',)),
                               ("header/footer buttons", ('"close"', '"done"',
                                                        '"rst"', '"pal"'))):
                for nm in names:
                    if nm not in nc:
                        problems.append("the grab's control predicate lost the %s "
                                        "(%s) — it becomes grabbable again and its "
                                        "click is spent" % (fam, nm))
        rect = body(text, "bool PnlCtrlRectHit(")
        if rect is None:
            problems.append("PnlCtrlRectHit() is gone - the control rects are magic "
                            "numbers again")
        else:
            for prop in ("OBJPROP_XDISTANCE", "OBJPROP_YDISTANCE",
                         "OBJPROP_XSIZE", "OBJPROP_YSIZE"):
                if prop not in rect:
                    problems.append("PnlCtrlRectHit() does not read %s, so its rect "
                                    "is not the drawn control" % prop)

    # P-UI-76: the SLIDER press. The knob and the track are two shapes of ONE
    # press, and the press must APPLY the value it landed on: the knob branch used
    # to arm a drag and apply nothing, while its grab zone is 12 px wider than the
    # drawn knob - so a click that missed the white circle by a few px armed a
    # gesture a motionless press never fulfilled and read as «کار نمیکنه».
    if "PnlKnobHit(mx,my,it,r) || PnlTrackHit(mx,my,it,r)" not in blk:
        problems.append("the slider's knob and track are claimed by MORE than one "
                        "branch - the knob's wider grab zone then arms a drag that "
                        "applies nothing (P-UI-76)")
    elif ("PnlValueFromX(it,r,mx,v)" not in blk or
          "PnlSetVisualValue(it,r,v)" not in blk):
        problems.append("a slider press no longer applies the value it landed on - "
                        "a click on the slider changes nothing (P-UI-76)")
    g = blk.find("PnlTryGrabMove(")
    for control in CONTROLS:
        c = blk.find(control)
        if c < 0:
            problems.append("the press chain lost %s" % control.rstrip("("))
    # P-UI-89 (2026-09-14): A CARD FULL OF CONTROLS CAN STILL BE DRAGGED FROM
    # EVERY PIXEL — the one rule this group has carried since P-UI-70 ("every
    # affordance BEFORE the grab, or the grab steals its press") is now SPLIT BY
    # WHO OWNS THE MOVE, because the grab no longer steals anything: it only ARMS.
    #   * the widgets whose press IS their own pointer gesture (the X/Done pair, an
    #     open popover, its anchor, the slider's knob/track) MUST be consulted
    #     before the arm — an arm taken first would hold the pointer they need;
    #   * the TAP family (switch, colour cell, colour strip, dual/ALL cell, `+`
    #     chip, section band, the header's .key cap) MUST be consulted after the
    #     arm and must still ACT — that is what makes their pixels draggable
    #     without making them unreachable.
    # Before this rule the faces of that second family were the part of the card
    # that could not be dragged at all (the ledger: every `moved=1` arm of the day
    # sat in the 56 px header), which is the report this rule answers.
    OWN_GESTURE = ("PnlClosePressHit(", "PnlDdAnchorHit(", "PnlKnobHit(",
                   "PnlTrackHit(")
    TAP_FAMILY = ("PnlSwitchHit(", "PnlCsetHit(", "PnlDualHit(",
                  "PnlColorAddHit(", "PnlQuickSwatchHit(", "PnlBandHit(",
                  "PnlKeycapHit(")
    # ── PANELDRAG-OFF (2026-09-14): THE ARM IS RETIRED — AND THIS GROUP SAYS SO.
    #    The assertion that lived here read a SUBSTRING that the comment now
    #    CONTAINS (`...PnlTryGrabMove(mx,my,false);` is still spelled inside the
    #    retired line), i.e. the gate would have stayed green with the feature
    #    commented out — the exact "green that means nothing" this project has
    #    paid for twice (P-UI-81, P-UI-83: a gate must read the SITE). Retirement
    #    is therefore its own assertion, and it fails in BOTH directions:
    #      * an ACTIVE arm line = the removed gesture is half-restored;
    #      * a DELETED site = the restore path is gone (R-RETIRED says a retired
    #        surface is commented in place, never removed);
    #      * a second copy = the feature is growing back beside the marker.
    #    The order rules below (own-gesture before the arm, tap family after it)
    #    still run against the retired site's POSITION, so a restore inherits
    #    them unchanged.
    if blk.count("PnlTryGrabMove(mx,my,false)") != 1:
        problems.append("the retired arm site is not exactly ONE line - a second "
                        "copy of the card-move gesture is growing beside the "
                        "marker (PANELDRAG-OFF)")
    if "      // if(!s_PnlClickChannel) PnlTryGrabMove(mx,my,false);" not in blk:
        problems.append("the retired card-move arm site is GONE instead of "
                        "commented - the restore path no longer exists, and "
                        "R-RETIRED keeps a retired surface commented in place "
                        "(PANELDRAG-OFF)")
    if re.search(r"(?m)^\s*(?:if\(!s_PnlClickChannel\)\s*)?PnlTryGrabMove\(mx,my,false\);", blk):
        problems.append("the press chain ARMS the card-move gesture again - the "
                        "removed feature is half-restored (PANELDRAG-OFF)")
    if g >= 0:
        for control in OWN_GESTURE:
            c = blk.find(control)
            if c > g:
                problems.append("%s is consulted AFTER the arm, so the arm takes "
                                "the gesture that control needs (P-UI-89)"
                                % control.rstrip("("))
        for control in TAP_FAMILY:
            c = blk.find(control)
            if c < 0 or c < g:
                problems.append("%s is not consulted after the arm - its face is "
                                "either un-draggable (the arm was never reached) "
                                "or stolen (P-UI-89)" % control.rstrip("("))
    own = body(text, "bool PnlPressAllowed(")
    if own is None:
        problems.append("PnlPressAllowed() is gone")
    else:
        if "UILeftButtonDown()" not in own and "TERMINAL_KEYSTATE_LEFT" not in own:
            problems.append("the stale-claim recovery no longer checks the physical "
                            "button - it would steal a LIVE gesture")
        if "g_DragOwner = DRAG_NONE" not in own:
            problems.append("the stale-claim recovery never releases the claim")
        if "foreign claim" not in own:
            problems.append("a press refused by a foreign live claim is silent "
                            "again - a stuck ring/box claim reads as \"the whole "
                            "panel is dead\" with nothing in the log (P-UI-88)")
    return problems


# ─────────────────────────────────────────────────────────────────────────────
# SR-PANELWIRE-5: the drag's two entries, one contract and its own frames
# (P-UI-75). Every rule here is a defect that shipped and was FELT: a drag that
# existed on one delivery channel only, and a card painted 10x/s while its
# coordinates landed 30x/s.
# ─────────────────────────────────────────────────────────────────────────────
def check_drag():
    problems = []
    panels = read(PANELS)
    util = read(UTILS)
    chain = body(panels, "void PnlHandleMouseMove(") or ""
    step = body(panels, "void PnlDragStep(")
    poll = body(panels, "void PnlDragPoll(")
    polled = body(panels, "void RefreshKitOnBar(") or ""

    def define(src, name):
        m = re.search(r"(?m)^#define\s+%s\s+(\d+)\s*" % name, src)
        return int(m.group(1)) if m else None

    lo, hi = define(panels, "PNL_MOVE_FRAME_MIN_MS"), define(panels, "PNL_MOVE_FRAME_MAX_MS")
    nom = define(panels, "PNL_MOVE_COALESCE_MS")
    if lo is None or hi is None or nom is None:
        problems.append("the drag's frame window lost a bound (PNL_MOVE_FRAME_MIN_MS "
                        "/ PNL_MOVE_FRAME_MAX_MS / PNL_MOVE_COALESCE_MS)")
    elif not (lo <= nom <= hi):
        problems.append("the frame window's bounds are inverted (start %d must sit "
                        "inside %d..%d)" % (nom, lo, hi))
    if "static int  s_PnlMoveFrameMs = PNL_MOVE_COALESCE_MS;" not in panels:
        problems.append("the frame window is not initialised from the declared "
                        "start, so a graft of its bounds cannot move it")

    # (a) ONE batch owner: the drag writes coordinates in exactly one place (and
    #     it is the function both entries call). The ONLY other sanctioned mover
    #     is the discrete resize clamp - a single corrective shot triggered by
    #     CHART_CHANGE, not a gesture - because a third writer cannot share the
    #     drag's frame window (P-UI-75b). A drift shows up here as a new caller.
    callers = [l.strip() for l in panels.splitlines()
               if re.match(r"^\s*PnlMoveBy\s*\(", l)]
    sanctioned = ["PnlMoveBy(g_PnlOpen, ndx, ndy);",
                  "PnlMoveBy(g_PnlMoveItem, mx - g_PnlMoveLastX, my - g_PnlMoveLastY);"]
    if sorted(callers) != sorted(sanctioned):
        problems.append("PnlMoveBy has exactly TWO sanctioned callers - the drag "
                        "batch (PnlDragStep) and the discrete resize clamp "
                        "(PnlClampOpenPanel). found: %s" % (callers,))
    if step is None:
        problems.append("PnlDragStep() is gone - the drag has no batch owner")
    else:
        if "now - s_PnlMoveTick < (uint)s_PnlMoveFrameMs" not in step:
            problems.append("the drag batch is not gated by its own adaptive "
                            "window (a hard rate cannot adapt to the machine)")
        if "PnlMoveBy(" not in step:
            problems.append("the batch owner does not move the card")
        if "DragFrameRedraw()" not in step:
            problems.append("the batch owner does not pay for its own frame - the "
                            "card would jump behind the cursor (P-UI-75b)")
        if "s_PnlMoveFrameMs * 3 + cost) / 4" not in step:
            problems.append("the frame window never adapts to the MEASURED batch "
                            "cost (it is a fixed rate again)")
        for bound in ("PNL_MOVE_FRAME_MIN_MS", "PNL_MOVE_FRAME_MAX_MS"):
            if bound not in step:
                problems.append("the adaptive window is not clamped by %s" % bound)
        if "ChartRedraw()" in step:
            problems.append("the drag repaints raw instead of through the drag's "
                            "frame owner")
    if panels.count("DragFrameRedraw(") != 1:
        problems.append("DragFrameRedraw must have exactly ONE caller (the batch "
                        "owner) - found %d calls" % panels.count("DragFrameRedraw("))
    owner = body(util, "void DragFrameRedraw(") or ""
    if "PANELDRAG-OFF" not in util:
        problems.append("DragFrameRedraw's owner lost its PANELDRAG-OFF note - it "
                        "is now an unexplained uncalled function the next session "
                        "will either delete or rewire blind")
    if "ChartRedraw()" not in owner:
        problems.append("DragFrameRedraw() no longer paints")
    if "g_lastChartRedrawTime" not in owner:
        problems.append("the drag's frame does not count for the tick throttle - "
                        "the tick would immediately repaint the same picture")

    # (b) the polled shadow: conservative witnesses, and it must go through the
    #     SAME grab / step / finish.
    if poll is None:
        problems.append("PnlDragPoll() is gone - the drag is back on one delivery "
                        "channel, where a press without a mouse-move edge is dead "
                        "(the P-BK-03 trap)")
    else:
        # PANELDRAG-OFF: the shadow is retired WITH the gesture — the pump must
        # NOT call it (its per-tick KEYSTATE probe was the feature's only
        # always-on cost and it armed ZERO of the day's 197 drags, so a restored
        # call would buy nothing and pay every tick), while the function stays
        # compiled for the restore path.
        if re.search(r"(?m)^\s*//\s*PnlDragPoll\(\);", polled) is None:
            problems.append("the retired poll call was DELETED instead of "
                            "commented - the restore path is gone "
                            "(PANELDRAG-OFF)")
        if re.search(r"(?m)^\s*PnlDragPoll\(\);", polled):
            problems.append("the card drag's poll is wired back into the tick/"
                            "timer pump - the removed gesture is half-restored "
                            "and pays a probe per tick (PANELDRAG-OFF)")
        if "PnlTryGrabMove(g_LastUIX, g_LastUIY,true)" not in poll:
            problems.append("the poll arms the grab with its own code instead of "
                            "the shared owner")
        if "PnlDragStep(g_LastUIX, g_LastUIY)" not in poll:
            problems.append("the poll moves the card with its own code instead of "
                            "the shared batch owner")
        if "PnlDragFinish(s_PnlMoveMoved, s_PnlMoveMoved)" not in poll:
            problems.append("the poll must end through the shared finish and pin "
                            "the spot only when it can prove the card moved")
        if "UILeftButtonDown()" not in poll:
            problems.append("the poll never asks the physical button, so it would "
                            "arm a drag out of a hover")
        if "g_MouseWasDown" not in poll:
            problems.append("the poll does not stand down when the EVENT channel "
                            "saw the press - two owners of one gesture")
        if "g_DragOwner" not in poll:
            problems.append("the poll ignores a claim held by another engine")
        if "s_PnlClickActed" not in poll:
            problems.append("the poll can re-open a gesture a control already spent")
        # The poll runs on every tick AND every 250 ms timer, so its IDLE path is
        # the price of this whole feature: the live-drag test first, then the
        # cheap state guards, and only THEN any hit test or TerminalInfoInteger
        # read (one int compare with the card closed - the user's "cost near
        # zero" is a property of the ORDER, not of a comment).
        tail_at = poll.find("PnlDragStep(g_LastUIX, g_LastUIY)")
        tail = poll[tail_at:] if tail_at >= 0 else ""
        if not poll.lstrip().startswith("if(g_PnlMoveItem >= 0)"):
            problems.append("the poll no longer tests the live drag FIRST - an idle "
                            "tick would pay for the guards before it can bail out")
        cheap = tail.find("g_PnlOpen < 0 || g_PnlOpen == 13")
        heavy = [h for h in (tail.find("g_PnlDragItem >= 0"),
                             tail.find("g_DragOwner != DRAG_NONE"),
                             tail.find("g_MouseWasDown"),
                             tail.find("s_PnlClickActed"),
                             tail.find("UILeftButtonDown()"),
                             tail.find("PnlTryGrabMove("),
                             tail.find("PnlPressClaimCode("),
                             tail.find("PnlPointOnControl("),
                             tail.find("PnlHeaderHit("),
                             tail.find("PnlCardBodyHit("),
                             tail.find("PnlPalettePointInside(")) if h >= 0]
        if cheap < 0 or len(heavy) != 6 or min(heavy) < cheap:
            problems.append("the poll's idle path is not cheap: the open-card guard "
                            "(`g_PnlOpen`) must come BEFORE every hit test and "
                            "every TerminalInfoInteger read")
    if "PnlDragStep(mx, my)" not in chain or \
            "PnlDragFinish(s_PnlMoveMoved, s_PnlMoveMoved)" not in chain:
        problems.append("the press chain does not use the shared batch owner / "
                        "conditional finish - the two entries cannot share one "
                        "window (P-UI-80: a tap must pin nothing)")
    if "PnlDragFinish(true, true)" in chain:
        problems.append("the press chain ends every drag unconditionally - a tap "
                        "drifts the card and eats its own release (P-UI-80)")
    # P-UI-89: ONE arm site, and it is the click channel's excluding guard. Two
    # calls would make the second refuse a press the first one already armed (a
    # bogus `M` refusal per press in the ledger); none would leave the card
    # un-draggable from every pixel except the header.
    # PANELDRAG-OFF: the same retirement rule as `[press]`, on the SAME site read
    # through the drag's own reader — plus the branch itself, which is what
    # actually diverts a held press: a live `if(g_PnlMoveItem >= 0)` with the arm
    # retired is dead code, but a live branch with the arm back is a gesture the
    # user removed. Both halves must agree or the retirement is a coat of paint.
    if chain.count("PnlTryGrabMove(mx,my,false)") != 1 or \
            "      // if(!s_PnlClickChannel) PnlTryGrabMove(mx,my,false);" not in chain:
        problems.append("the chain's retired arm site is gone or duplicated - the "
                        "card-move gesture is back, or unrestorable "
                        "(PANELDRAG-OFF)")
    if re.search(r"(?m)^\s*(?:if\(!s_PnlClickChannel\)\s*)?PnlTryGrabMove\(mx,my,false\);", chain):
        problems.append("the chain arms the removed card-move gesture again "
                        "(PANELDRAG-OFF)")
    if "if(false && g_PnlMoveItem >= 0)" not in chain:
        problems.append("the move branch is not RETIRED (it must read "
                        "`if(false && g_PnlMoveItem >= 0)` while PANELDRAG-OFF "
                        "holds) - a live branch can divert a press into the "
                        "removed gesture (PANELDRAG-OFF)")
    # (c) P-UI-77: the channel that ARMED the drag owns its release. The event
    #     sparam bit is one witness of two (P-UI-73a): a drag the poll armed
    #     never showed its press on that bit, so ending it on a bare bit-clear
    #     murders a working drag in its first step and eats its release - the
    #     card reads as fixed. The grab records its channel, the move block
    #     demands the physical probe's agreement only for a poll-armed drag,
    #     and every finish drops the flag with the gesture.
    grab = body(panels, "bool PnlTryGrabMove(")
    if grab is None or "s_PnlMoveByPoll  = byPoll;" not in grab:
        problems.append("the grab does not record which channel armed it - the "
                        "release cannot belong to the arming channel (P-UI-77)")
    else:
        if "PnlTryGrabMove(mx,my,false)" not in chain:
            problems.append("the press chain does not arm as the event channel - "
                            "its release ownership is undeclared (P-UI-77)")
    if "!s_PnlMoveByPoll || UILeftButtonUp()" not in chain:
        problems.append("a poll-armed drag ends on the bare event bit - the "
                        "first disagreeing event murders it and the card reads "
                        "as fixed (P-UI-77)")
    fin2 = body(panels, "void PnlDragFinish(")
    if fin2 is None or "s_PnlMoveByPoll = false;" not in fin2:
        problems.append("the finish does not drop the arming-channel flag - a "
                        "later drag would inherit another gesture's release "
                        "rule (P-UI-77)")
    # (d) P-UI-78: the gesture names its own decisions - arm (whose channel),
    #     refusal (which reason) and finish (moved? whose rule?). Three Prints
    #     per gesture at most, and the per-move batch path stays silent, or the
    #     ledger itself becomes the perf problem it was built to find.
    if grab is None or "panel drag armed by " not in grab or \
            'byPoll ? "poll" : "event"' not in grab:
        problems.append("the grab does not ledger its arming channel - the next "
                        "\"can't drag\" cannot name its own entry (P-UI-78)")
    ref = body(panels, "void PnlGrabRefused(")
    if ref is None:
        problems.append("PnlGrabRefused() is gone - refusals have no single "
                        "owner again (P-UI-78)")
    else:
        # P-UI-88: the control refusal carries the CLAIMANT's code, so its needle
        # is the opening of the expression rather than the bare `"C"`.
        for code, needle in (("M", 'PnlGrabRefused("M",byPoll'),
                             ("X", 'PnlGrabRefused("X",byPoll'),
                             ("P", 'PnlGrabRefused("P",byPoll'),
                             ("C:<claimant>", 'PnlGrabRefused("C:"+claim,byPoll'),
                             ("H", 'PnlGrabRefused("H",byPoll')):
            if needle not in grab:
                problems.append("a grab refusal lost its ledger call (%s) - that "
                                "refusal is silent again (P-UI-78/P-UI-88)" % code)
        if "if(!byPoll)" not in ref:
            problems.append("refusals print from the poll too - one line per "
                            "tick while held, i.e. a log flood (P-UI-78)")
    if fin2 is None or "panel drag finished moved=" not in fin2:
        problems.append("the finish does not ledger moved/channel - a jump or a "
                        "dead drag leaves no trace (P-UI-78)")
    if step is not None and "Print(" in step:
        problems.append("the per-move batch path prints - the ledger fires at "
                        "drag rate instead of gesture rate (P-UI-78)")
    # (f) P-UI-79: the refusal names the remembered rect (an "outside" without
    #     a stated rect answers nothing), and a rect-miss falls back to the
    #     paint itself (the body skins) before it may refuse.
    if ref is None or "rect=" not in ref:
        problems.append("a refusal no longer states the remembered rect - the "
                        "next (H) cannot be judged (P-UI-79)")
    if body(panels, "bool PnlSkinHit(") is None:
        problems.append("PnlSkinHit() is gone - a rect/paint divergence has no "
                        "paint-anchored fallback (P-UI-79)")
    elif "PnlSkinHit(g_PnlOpen,mx,my)" not in (grab or ""):
        problems.append("the grab never asks the paint - a stale rect refuses "
                        "presses sitting on the drawn card (P-UI-79)")
    if grab is not None and 'viaSkin ? "skin" : "rect"' not in grab:
        problems.append("the arm line lost its via= origin - a skin-fallback "
                        "grab is indistinguishable from a rect one (P-UI-79)")
    # (g) P-UI-80: the menu's dead zone (ORB_DRAG_THRESHOLD parity). Tremor at
    #     or under the threshold must track without moving, painting, pinning
    #     or suppressing - otherwise every tap drifts the committed spot and
    #     eats its own release click (the 12:44 chase).
    if define(panels, "PNL_DRAG_THRESHOLD_PX") is None:
        problems.append("the drag lost its dead-zone bound "
                        "(PNL_DRAG_THRESHOLD_PX)")
    if grab is not None and ("s_PnlMoveGrabX" not in grab or
                             "s_PnlMoveGrabY" not in grab):
        problems.append("the grab does not record the press point - the dead "
                        "zone has no anchor (P-UI-80)")
    # P-UI-89: the bound the batch path applies is resolved by ONE owner, because
    # a press that landed on a control's own pixel owes the card a LONGER proof
    # (P-UI-76 measured the hand: "a hand that moves 1-3 px on every real click",
    # so the menu's 3 px would creep the card on every toggle attempt).
    if define(panels, "PNL_DRAG_CTRL_PX") is None:
        problems.append("the control-pixel proof bound is gone "
                        "(PNL_DRAG_CTRL_PX) - a tap on a switch creeps the card "
                        "again (P-UI-89)")
    helper = body(panels, "int PnlDragThreshPx(") or ""
    if "PNL_DRAG_CTRL_PX" not in helper or "PNL_DRAG_THRESHOLD_PX" not in helper \
            or "s_PnlMoveOnCtrl" not in helper:
        problems.append("the dead zone has no ONE owner resolving the menu bound "
                        "against the control-pixel bound (PnlDragThreshPx, P-UI-89)")
    if step is None or step.count("PnlDragThreshPx()") < 2:
        problems.append("sub-threshold tremor reaches the batch owner - taps "
                        "drift the card (P-UI-80/P-UI-89)")
    onctrl = re.search(r"s_PnlMoveOnCtrl\s*=\s*softClaim;", grab or "")
    if onctrl is None:
        problems.append("the arm does not record whether the press landed on a "
                        "control - the longer proof can never engage (P-UI-89)")
    if not re.search(r"s_PnlMoveOnCtrl\s*=\s*false;", fin2 or ""):
        problems.append("the finish does not drop the control-press flag - a "
                        "later body drag inherits another gesture's proof "
                        "(P-UI-89)")
    # (e) P-UI-78: the poll ends a live drag only on TWO consecutive release
    #     readings - one up-reading is a KEYSTATE-flicker rumour (P-BK-05) and
    #     murdered live drags mid-press.
    if poll is not None:
        if "if(!s_PnlPollUpArmed)" not in poll:
            problems.append("the poll finishes a live drag on a single "
                            "up-reading - a flicker murders it mid-press (P-UI-78)")
        if "s_PnlPollUpArmed = true;" not in poll or \
                "s_PnlPollUpArmed = false;" not in poll:
            problems.append("the rumour filter never arms/clears - the debounce "
                            "cannot work (P-UI-78)")
    bridge = body(panels, "void HandleUIChartEvent(")
    if bridge is None or bridge.count("s_PnlClickActed = false;") < 2:
        problems.append("a release no longer resyncs the press-echo latch - a "
                        "spent echo would eat a LATER genuine press (P-UI-65)")
    fin = body(panels, "void ChartPointerFinalizeOnUps(")
    if fin is None or "s_PnlMoveMoved" not in fin:
        problems.append("the button-up finalizer leaves the moved witness set, so "
                        "a later poll could pin a spot the card never reached")
    if fin is None or not re.search(r"s_PnlMoveOnCtrl\s*=\s*false;", fin):
        problems.append("the button-up finalizer leaves the control-press flag "
                        "set - the next drag measures its dead zone against a "
                        "press that is long over (P-UI-89)")
    # P-UI-83: this reads the SITE, not the file — the finalizer's own note names
    # this ledger in prose (`via=finalizer`), so a bare substring test stayed
    # true even with the Print deleted (the same vacuity panel-colour-audit was
    # caught by in P-UI-81: a gate must read the site).
    if fin is None or "panel drag finished moved=" not in fin or \
            "ms via=finalizer" not in fin:
        problems.append("the finalizer ends missed-release drags silently - an "
                        "arm/arm pair reads as a double-grab (P-UI-78 ledger)")
    # (h) P-UI-82: the batch pays for the card's OWN objects (a per-gesture list,
    #     never a chart sweep — that scan is what the adaptive window was
    #     converging onto, so the card stepped instead of tracking), and the spot
    #     is parked when the drag is PROVEN, not at the release: the next open
    #     reads the park, and a gesture that never gets a release (hotkey close,
    #     TF switch, focus stolen) must still reopen where the user left it.
    grab2 = body(panels, "bool PnlTryGrabMove(") or ""
    if "PnlMoveListSync(g_PnlOpen, true)" not in grab2:
        problems.append("the grab no longer rebuilds the move list - the batch can "
                        "move names the card has outlived and tear it (P-UI-82)")
    if step is None or "if(!s_PnlMoveMoved) PnlCommitMove(" not in step:
        problems.append("the drag parks the spot only at its RELEASE - a gesture that "
                        "never gets one reopens at the old position (P-UI-82)")
    # (i) P-UI-83: A NON-EVENT WITNESS MAY NOT END A GESTURE WHOSE EVENT CHANNEL IS
    #     STILL DELIVERING DOWN-READINGS. The user's yardstick is the menu, whose
    #     drag lives on the event bit alone (`if(!leftDown)`, BiotakMenu); the
    #     panel had two extra enders and BOTH consult the KEYSTATE probe — so on a
    #     terminal whose probe answers "free" while the button is held, the poll
    #     executed every drag it had not armed (253-500 ms per press) and the
    #     P-UI-49b delivery echo executed the rest (125-176 ms). Today's ledger:
    #     150 arms, ZERO by the poll, and no drag outliving half a second while
    #     the user kept the button down. The separator is the event bit's own
    #     RECENCY: an echo lands while down-readings are still arriving, a
    #     motionless release emits no move at all (P-BK-03) and is quiet by
    #     construction.
    wit = body(panels, "bool PnlPointerQuiet(") or ""
    if not wit:
        problems.append("the down-recency witness is gone - a non-event witness can "
                        "execute a live drag again (P-UI-83)")
    elif "s_PnlDownAt" not in wit or "PNL_DOWN_RECENT_MS" not in wit:
        problems.append("the down-recency witness no longer reads the stamp and its "
                        "window (P-UI-83)")
    if poll is not None and "UILeftButtonUp() && PnlPointerQuiet()" not in poll:
        problems.append("the poll ends a live drag on the probe ALONE - a terminal "
                        "whose probe reads free kills every drag on its second "
                        "pass (P-UI-83)")
    if fin is None or "!PnlPointerQuiet()" not in fin:
        problems.append("the button-up finalizer tears a gesture down on the probe "
                        "alone - the P-UI-49b echo of the arming press ends a live "
                        "drag ~130 ms in (P-UI-83)")
    if bridge is None or "s_PnlDownAt = GetTickCount();" not in bridge:
        problems.append("the down-recency stamp is never written - the witness "
                        "cannot answer (P-UI-83)")
    one = body(panels, "void PnlMoveOne(") or ""
    if "ObjectGetInteger" in one:
        problems.append("the move batch reads objects back again - half of every "
                        "batch is a read of a value the gesture cannot change "
                        "(P-UI-83: the menu computes its chrome, it never reads)")
    if step is None or "s_PnlMoveFrames" not in step or "s_PnlMoveWorst" not in step:
        problems.append("the gesture no longer measures its own frames - \"not live\" "
                        "cannot be answered from the log (P-UI-83)")
    return problems


# ─────────────────────────────────────────────────────────────────────────────
# the checks
# ─────────────────────────────────────────────────────────────────────────────
#--- a retired setting is allowed to answer and render nothing, but the project
#--- must SAY so at the address it retires (P-UI-47/P-UI-70c's own convention:
#--- MAGNET-OFF, MIDPOINT-OFF, VIEWLOCK-OFF ...).
RETIRE_WORDS = ("inert", "retired", "stay persisted", "stays persisted",
                "-off", "kept for the address", "dead")


def retired_addresses(spec_text):
    """(item, setting) pairs a card's own spec block documents as deliberately dead."""
    out = set()
    cur = None
    for line in spec_text.splitlines():
        m = re.match(r"\s*(?:else\s+)?if\(item\s*==\s*(\d+)\)", line)
        if m:
            cur = int(m.group(1))
        if cur is None or "//" not in line:
            continue
        low = line.lower()
        if any(w in low for w in RETIRE_WORDS):
            for n in re.findall(r"\b(\d+)\b", line.split("//", 1)[1]):
                out.add((cur, int(n)))
    return out


def delegation_targets(text):
    """(item, setting) reached through another card's delegated call.

    Card 9's SS-LS ENGINE section applies card 1's setting 8 (`PnlApplySet(1, 8, v)`),
    which is why that setting may have no row of its own and still be live.
    """
    out = set()
    for m in re.finditer(r"Pnl(?:Apply|DefVal|Current)Set\s*\(\s*(\d+)\s*,\s*(\d+)\s*,",
                         strip_comments(text)):
        out.add((int(m.group(1)), int(m.group(2))))
    return out


def check_modal():
    """[modal] - while a card is open, ONE engine owns the pointer: the card.

    P-UI-72. The ring menu's hit boxes are GEOMETRIC (CircItemAt, ToolsItemAt,
    the orb rect) and the card is movable, so parking the card on the menu put a
    ring item UNDER the control the user was aiming at. The press then claimed
    DRAG_MENU before the panel saw it, and the two symptoms the user reported as
    separate bugs were one: `PnlPressAllowed()` refuses a foreign live claim, so
    the covered control read as DEAD ("the colour buttons do nothing"); and the
    orb followed the cursor out from under the card ("the panel detaches and
    moves to another part").

    Three things must hold, none of them visible in a still screenshot:
      * the ring refuses a NEW press while a card is open (a live drag still
        finishes, and a long-press armed before the card opened still ends);
      * the hover tip keeps its own guard (the older half of the same rule);
      * the flag is declared in the globals header that is included BEFORE both
        the menu and the panels - a guard on a global the menu cannot see is a
        compile error, and a guard on a DIFFERENT flag is no guard at all.
    """
    problems = []
    menu = read(MENU)
    blk = body(menu, "CircHandleMouseMove(")
    if blk is None:
        return ["CircHandleMouseMove() is gone - the ring has no press path"]
    # the refusal must sit before the first grab (orb drag / long-press arming)
    guard = blk.find("g_UIPanelOpen")
    grab = blk.find("g_OrbDragging = true")
    arm = blk.find("g_LongPressItem  =")
    if guard < 0:
        problems.append("the ring no longer refuses to grab while a settings card "
                        "is open - a press on a card control that lies over a ring "
                        "item claims DRAG_MENU and the control reads as dead (P-UI-72)")
    else:
        for what, at in (("the orb drag", grab), ("the long-press armer", arm)):
            if at >= 0 and guard > at:
                problems.append("%s is reached BEFORE the modal guard, so the ring "
                                "still wins the press under an open card" % what)
        tail = blk[guard:guard + 200]
        if "return;" not in tail:
            problems.append("the modal guard does not REFUSE anything - it must "
                            "return before any claim")
    # a live drag or an already-armed long-press must not be frozen by the guard
    if guard >= 0 and "g_OrbDragging" not in blk[guard:guard + 120]:
        problems.append("the modal guard ignores a LIVE orb drag - the orb would "
                        "stick to the cursor until the next press")
    tip = body(menu, "CircTipOnMove(")
    if tip is not None and "g_UIPanelOpen" not in tip:
        problems.append("the ring's hover tip lost its card guard (it would arm a "
                        "phantom tip under the open card)")
    # the hold engine: a press inside an open panel must never arm a box hold
    hold = body(read(PANELS), "BkHoldLatch(")
    if hold is None:
        problems.append("BkHoldLatch() is gone - the box-hold cannot be checked")
    elif "PnlPointInside(" not in hold:
        problems.append("a press inside the open card can arm a box hold again - "
                        "mid-read it would fire and replace the card (P-BK-15)")
    # dependency: the flag has to be visible to BOTH modules
    decl = read(GLOBALS)
    if not re.search(r"static\s+bool\s+g_UIPanelOpen", decl):
        problems.append("g_UIPanelOpen is no longer declared in GlobalVariables.mqh - "
                        "the menu is included before the panels, so the modal guard "
                        "would not compile (or would read a different flag)")
    order = read(ENTRY)
    i_globals = order.find("GlobalVariables.mqh")
    i_menu = order.find("BiotakMenu.mqh")
    if i_globals < 0 or i_menu < 0 or i_globals > i_menu:
        problems.append("the include order no longer puts the globals header before "
                        "the menu - the modal guard's dependency is broken")
    return problems


def check_measure_item():
    """[measure] - the measuring tool is ONE item with ONE arm path (P-UI-95).

    P-UI-95 (2026-09-16, user: «ایتم اندازه گیری بیس رو بیار توی منوی اصلی»): the
    Base / Knot measuring tool left the Tools sub-menu and became a MAIN-RING item.
    Three silent breakages are what this section exists for:

      * the item is reachable from EXACTLY ONE family: `RING_COUNT` counts it, its
        APPENDED `RING_BASEKNOT` slot maps to `CIR_BASEKNOT`, and the Tools ladder
        does not count it a second time - a tool index with no mapping is a cell
        that draws and does nothing;
      * a press ARMS through ONE owner (`CircArmBaseKnot`), whose steps must all
        survive, and `BaseKnotArm()` has exactly ONE call site: a second copy of the
        arm path is how one surface would forget `PnlCloseAll()` (the style card or
        MINI strip left floating over a live draw session) or `SaveUIStates()`;
      * a HOLD opens the card the Tools cell always opened - `FeaturePanel` maps the
        measure feature to the Base Box card (12) and BOTH families resolve through
        it. By identity a ring item's card id is its feature code, so the measure
        tool's hold would open panel 10 (the retired Factor card) instead.
    """
    problems = []
    code = strip_comments(read(MENU))

    def num(name):
        m = re.search(r"(?m)^\s*#define\s+%s\s+(\d+)" % name, code)
        return int(m.group(1)) if m else None

    ring, slot, tools = num("RING_COUNT"), num("RING_BASEKNOT"), num("TOOL_COUNT")
    th3 = num("RING_TH3")   # TH3TOOL-ON (2026-09-19): the TH3 slot is APPENDED too
    # P-LM-09 (2026-09-20): the leg meter's item is the THIRD appended slot. This gate
    # did not know it — RING_LEG arrived with the tool and was not added here — so the
    # rule below read RING_COUNT 9 against a top of 7 and reported a fault that was the
    # GATE's, not the code's. That is the same failure mode as a stale seed anchor: a
    # gate that is wrong about the source is worse than no gate, because the reported
    # fault sends the reader to code that is doing the right thing.
    leg = num("RING_LEG")
    if ring is None or slot is None or tools is None:
        return ["RING_COUNT / RING_BASEKNOT / TOOL_COUNT are gone - the measure item "
                "has no declared slot (P-UI-95)"]
    # The rule is "the ring's LAST slot is an APPENDED one" - that is what keeps
    # every existing state key's meaning. RING_BASEKNOT held it until the TH3
    # item returned (TH3TOOL-ON, 2026-09-19) and took the new top slot, and the leg
    # meter's item took it again (RING_LEG, P-LM-09); all three are appended, so the
    # top of them is the one RING_COUNT must count.
    top = max([v for v in (slot, th3, leg) if v is not None])
    if top != ring - 1:
        problems.append("the last ring slot (%d) is not the one RING_COUNT (%d) counts: "
                        "an APPENDED slot is what keeps every existing state key's "
                        "meaning (P-UI-95)" % (top, ring))
    # ...and no two slots may collide: a slot inserted BETWEEN the others both
    # collides with the one it displaces and shifts every persisted key below.
    seen_slots = {}
    for nm, val in re.findall(r"(?m)^\s*#define\s+(RING_[A-Z0-9_]+)\s+(\d+)\b", code):
        if nm == "RING_COUNT":
            continue
        v = int(val)
        if v in seen_slots:
            problems.append("%s and %s both claim ring slot %d - a slot inserted "
                            "between the others shifts every persisted state key "
                            "(P-UI-95)" % (seen_slots[v], nm, v))
        seen_slots[v] = nm
    feats = body(code, "RingFeature(") or ""
    if "case RING_BASEKNOT: return CIR_BASEKNOT;" not in feats:
        problems.append("the measure slot no longer maps to CIR_BASEKNOT - the item "
                        "cannot be reached at all")
    if th3 is not None and "case RING_TH3: return CIR_TH3;" not in feats:
        problems.append("the appended RING_TH3 slot does not map to CIR_TH3 - the "
                        "TH3 item cannot be reached at all (TH3TOOL-ON)")
    if leg is not None and not re.search(r"case\s+RING_LEG:\s*return\s+CIR_LEG;", feats):
        problems.append("the appended RING_LEG slot does not map to CIR_LEG - the leg "
                        "meter's item cannot be reached at all (P-LM-09)")
    tf = body(code, "ToolFeature(") or ""
    if "TOOL_BASEKNOT" in tf:
        problems.append("the measure tool is counted in the Tools ladder again: ONE "
                        "family owns it, or two cells arm one session (P-UI-95)")
    arm = body(code, "CircArmBaseKnot(")
    if arm is None:
        problems.append("CircArmBaseKnot() is gone - the arm path has no owner")
    else:
        for need in ("g_UI.menuVisible = false;", "DeleteMenu();", "CreateMenu();",
                     "SaveUIStates();", "PnlCloseAll();", "BaseKnotArm();",
                     "ChartRedraw();", "return REFRESH_NONE;"):
            if need not in arm:
                problems.append("the ONE arm path no longer runs `%s`" % need)
        if code.count("BaseKnotArm();") != 1:
            problems.append("BaseKnotArm() is called from %d site(s): a second copy of "
                            "the arm path is how two surfaces drift (P-UI-95)"
                            % code.count("BaseKnotArm();"))
        if code.count("CircArmBaseKnot(") < 2:
            problems.append("nothing consumes the arm path - no surface can start a "
                            "measuring session")
    panel = body(code, "FeaturePanel(")
    if panel is None or not re.search(r"if\(feat == CIR_BASEKNOT\)\s*return 12;", panel):
        problems.append("FeaturePanel() no longer sends the measure feature to the "
                        "Base Box card (12): a hold would open the item's own feature "
                        "code instead (P-UI-95)")
    for who, sig in (("the ring", "RingPanel("), ("the tools cell", "ToolPanel(")):
        if "FeaturePanel(" not in (body(code, sig) or ""):
            problems.append("%s no longer resolves its card through FeaturePanel - the "
                            "two families can open different cards for one feature" % who)
    return problems


def check_th3_item():
    """[th3draw] - a press on the TH3 item ARMS the draw (P-UI-96).

    P-UI-96 (2026-09-19, user: the tool is pressed and there is nothing to draw
    with - the AB=CD pivots cannot be marked): the TH3 ring item flipped
    `g_enableTH3Tool` and did nothing else, so the item lit up and no session
    ever started. The only way into a drawing session was the V key, which no
    surface of the panel mentions. Four properties have to survive, and each of
    them was silently wrong before:

      * the press reaches the ONE arm path (`CircArmTH3Draw`) and NOT the enable
        flag - that switch has its own home, the TH3 TOOL card's row 0;
      * that path REPAIRS both preconditions a session needs (engine enabled;
        drawing mode AB=CD, since `TH3_MODE_STEPS` ships no click path at all)
        and persists the mode, or the card's MODE row would disagree with the
        session that is running;
      * the item is MOMENTARY like the measuring tool next to it:
        `CircFeatureOn(CIR_TH3)` reads the ARMED SESSION, so the light can never
        say "armed" while no session exists;
      * the arming press is not pivot X (`ToggleTH3Tool(true)` ->
        `TH3SessionStart(swallowGesture)`) and the session never touches the
        chart-wide mouse-move channel the ring/panel gestures ride
        (P-TH3-PERF-07: that flag has exactly ONE writer, in EventHandlers).
    """
    problems = []
    code = strip_comments(read(MENU))
    tool = strip_comments(read(TH3TOOL))
    ctrl = strip_comments(read(TH3CTRL))

    # 1. the press reaches the arm path, not the switch.
    m = re.search(r"else if\(feat == CIR_TH3\)\s*\{(.*?)\n   \}", code, re.S)
    if m is None:
        problems.append("the TH3 item's press branch is gone - nothing can arm a "
                        "draw session (P-UI-96)")
    else:
        branch = m.group(1)
        if "CircArmTH3Draw()" not in branch:
            problems.append("the TH3 item's press no longer reaches CircArmTH3Draw: "
                            "the tool is back to flipping a flag and drawing "
                            "nothing (P-UI-96)")
        if re.search(r"g_enableTH3Tool\s*=", branch):
            problems.append("the TH3 item's press writes the ENABLED switch again - "
                            "that flag's home is the card's row 0, and flipping it "
                            "is what the press used to do INSTEAD of drawing "
                            "(P-UI-96)")

    # 2. the arm path repairs what a session needs, then starts it.
    arm = body(code, "CircArmTH3Draw(")
    if arm is None:
        problems.append("CircArmTH3Draw() is gone - the arm path has no owner "
                        "(P-UI-96)")
    else:
        for need, why in (("g_enableTH3Tool = true;", "the engine-off repair"),
                          ("TH3_MODE_ABCD", "the AB=CD mode repair"),
                          ("RuntimeSettingsSaveOverridesThrottled();",
                           "the persistence of that repair"),
                          ("PnlCloseAll();", "the stale-card close"),
                          ("ToggleTH3Tool(true);",
                           "the ONE toggle, with the arming press swallowed"),
                          ("return REFRESH_NONE;", "the no-recalc return")):
            if need not in arm:
                problems.append("the TH3 arm path no longer runs `%s` (%s): a press "
                                "would arm a session that is not on, not AB=CD, "
                                "or not visible (P-UI-96)" % (need, why))

    # 3. momentary, exactly like the measuring tool.
    lit = body(code, "bool CircFeatureOn(")
    if lit is None or "TH3SessionActive()" not in lit:
        problems.append("CircFeatureOn(CIR_TH3) no longer reads TH3SessionActive - "
                        "the ring light can say 'armed' while no session exists, "
                        "which is exactly how the dead press looked (P-UI-96)")

    # 4. the arming press must not be spent as the first pivot.
    if "TH3SessionStart(fromRingItem)" not in (body(tool, "ToggleTH3Tool(") or ""):
        problems.append("ToggleTH3Tool() no longer forwards `fromRingItem` to "
                        "TH3SessionStart - the press that armed the session lands "
                        "as pivot X, in the ring's own corner (P-UI-96)")
    if "void TH3SessionStart(const bool swallowGesture = false)" not in ctrl:
        problems.append("TH3SessionStart() lost its `swallowGesture` parameter or "
                        "its false default - the V key would have to swallow a "
                        "gesture it does not have (P-UI-96)")
    if "swallowGesture ? GetTickCount() : 0" not in (body(ctrl, "TH3SessionStart(") or ""):
        problems.append("TH3SessionStart() no longer primes `lastClickTime` from "
                        "`swallowGesture` - the debounce cannot reject the arming "
                        "press (P-UI-96)")

    # 5. one press is one pivot (P-UI-96b): MT4 can deliver a single press on both
    #    the move channel and as a CLICK, and the 300 ms debounce only rejects the
    #    echo of a SHORT click - a longer hold stored the same point twice, so X
    #    and A landed on one candle and the drawn pattern had no D.
    addp = body(ctrl, "bool TH3SessionAddPoint(")
    if addp is None:
        problems.append("TH3SessionAddPoint() is gone - the session has no owner for "
                        "its four pivots (P-UI-96b)")
    else:
        for need, why in (("g_th3Session.pointCount > 0", "the previous-point test"),
                          ("iBarShift", "the bar identity"),
                          ("GetCachedPoint()", "the price tolerance")):
            if need not in addp:
                problems.append("TH3SessionAddPoint() no longer runs `%s` (%s): one "
                                "press can be spent as two pivots and the zero-length "
                                "leg that follows has no D (P-UI-96b)" % (need, why))

    # 6. the session does NOT own the chart-wide mouse-move channel.
    for path, label in ((ctrl, "the TH3 session"), (tool, "the TH3 tool")):
        if "CHART_EVENT_MOUSE_MOVE" in path:
            problems.append("%s writes CHART_EVENT_MOUSE_MOVE: that flag is "
                            "chart-scoped and shared (orb drag, panel gestures, "
                            "BaseKnot's poll shadow), so switching it OFF ends "
                            "the whole interactive UI for the rest of the attach "
                            "(P-TH3-PERF-07)" % label)
    if strip_comments(read(EVENTS)).count("CHART_EVENT_MOUSE_MOVE") != 1:
        problems.append("EventHandlers no longer has exactly ONE mouse-move "
                        "writer - the P-TH3-PERF-07 owner is not verifiable")
    return problems


def check_th3_ink():
    """[th3ink] - every TH3 ink is resolved for the chart it is drawn on (P-UI-97).

    P-UI-97 (2026-09-19, user: the drawing cannot be seen against a white chart):
    the session preview was hardcoded `clrYellow` / `clrAqua` / `clrLime`, and the
    committed pattern wrote its ladder palette (`clrGold`, `clrLimeGreen`, ...) and
    its colour inputs straight into OBJPROP_COLOR. On white paper a yellow letter
    is a smudge and gold is invisible - while on a dark chart those are exactly
    the right inks, which is why the fix cannot be "pick other constants":

      * a BRIGHT literal may not be written into OBJPROP_COLOR by either drawing
        module (the dark ones - clrDarkBlue, clrGray, ... - stay legal: they read
        on light paper and are the dark half the resolver returns unchanged);
      * every ink must arrive through `TH3InkForChart` (lightness only, hue kept,
        identity on a dark chart) or through the preview's pair
        (`TH3SessionPointInk` / `TH3SessionLineInk`, which is the renderer's own
        `(g_th3* == clrNONE) ? inpABCD* : g_th3*` rule), so the session cannot
        preview a colour the committed pattern will not keep;
      * a variable is accepted only when it was itself assigned from one of those
        (`zoneColor`, `targetInk`, `wantClr`) - an unwrapped input is the bug;
      * P-TH3-INFO-04 (2026-09-20): THE READOUT PLATE IS THE ONE SURFACE THE
        PAPER MUST NOT DECIDE. The leg meter's box and the AB=CD caption draw on
        a fixed dark plate on every theme, so its rows are its own palette
        (`TH3RO_TEXT` / `TH3RO_ACCENT`, asked through the `TH3ReadoutInk` owner)
        and its border its own hairline (`TH3RO_EDGE`): resolved, they would be
        dark-on-dark on light paper and near-white-on-white on a dark one, i.e.
        unreadable. Those names are allowed BY NAME - a palette of its own, one
        table in one place - while a raw `clrYellow` written anywhere is still
        the bug this gate exists for (see the readout-plate seed below).
    """
    problems = []
    ctrl = strip_comments(read(TH3CTRL))
    rend = strip_comments(read(TH3RENDER))
    if not ctrl or not rend:
        return ["the TH3 drawing modules are gone - P-UI-97's ink owner cannot be "
                "verified"]
    if "color TH3InkForChart(" not in ctrl:
        problems.append("TH3InkForChart() is gone from the session module - there is "
                        "no owner deciding what reads on this chart's background "
                        "(P-UI-97)")
    if "TH3InkForChart(" not in rend and "TH3SessionLineInk(" not in rend:
        problems.append("the renderer no longer resolves any ink - the committed "
                        "pattern would be painted with the raw settings again "
                        "(P-UI-97)")

    bright = re.compile(r"^clr(Yellow|Aqua|Lime|LimeGreen|Gold|DodgerBlue|OrangeRed|"
                        r"YellowGreen|Khaki|Cyan|White)$")
    # P-TH3-INFO-04: the readout plate's own palette, by name only.
    readout = re.compile(r"^TH3RO_[A-Z_]+$")
    for text, who in ((ctrl, "the session"), (rend, "the renderer")):
        # "resolved where it was computed" is READ OFF THE CODE, not assumed from a
        # name list: any local a resolver was assigned to counts, so hoisting the
        # ink out of the write call (P-TH3-INFO-01's caption writer does exactly
        # that) stays honest without teaching this gate a second allowlist. The
        # name list survives for the two local names that predate the rule.
        resolved = set(re.findall(r"\b([A-Za-z_]\w*)\s*=\s*(?:TH3InkForChart|TH3Session\w*Ink|"
                                  r"TH3ReadoutInk)\s*\(",
                                  text))
        for m in re.finditer(r"OBJPROP_COLOR\s*,\s*([^;\n]+?)\)\s*;", text):
            arg = m.group(1).strip()
            if arg.startswith("TH3InkForChart(") or arg.startswith("TH3Session"):
                continue
            if arg in resolved or arg in ("zoneColor", "targetInk", "wantClr"):
                continue                      # resolved where it was computed
            if re.fullmatch(r"clr\w+", arg) and not bright.match(arg):
                continue                      # a dark literal reads on both papers
            if readout.match(arg):
                continue                      # the readout plate's own palette (P-TH3-INFO-04)
            problems.append("%s writes `%s` into OBJPROP_COLOR - an unresolved ink is "
                            "invisible on the other background (P-UI-97)"
                            % (who, arg))
    return problems


def check_th3_caption():
    """[th3caption] - the step caption is WRAPPED, never clipped (P-TH3-INFO-01).

    MT4 truncates an object's text at 63 CHARACTERS. The user's EURUSD D1 chart
    showed exactly that cliff, mid-word:

        AB=CD | AB:504.1 | BC:765.0 | Step:267.7 pips [closed K=3.0 rat

    - 63 characters - while the walk-up SHIFT that produced the 267.7 (its own
    words are `-> SHIFT 2xLS(D1)=267.7`), the rung, T3/T5 and the milestone were
    all in the part that never rendered. The caption was ARITHMETICALLY right
    (read off the chart's own price axis: Step1 1.1290 and Step3 1.0754 are 536
    pips apart = 2 x 267.7, projecting from the real D at 1.1558, and the closed
    seed really was 162.7 pips at K=3.0), so the failure was purely the lost
    line - which is why the report reads «گام اشتباه میندازه». A caption whose
    explanation is invisible is a caption that lies.

    The gate: the cap is MT4's own 63; the caption is written ONLY by the family
    owner (`TH3InfoFamilyDraw`, which wraps); and the other TH3 modules ask the
    family owner instead of spelling `_Info` themselves - a sweep that matches
    the literal `_Info` recognises line 1 only and leaves the previous pattern's
    continuation lines lit beside the new one's.
    """
    problems = []
    rend = strip_comments(read(TH3RENDER))
    m = re.search(r"#define\s+TH3_INFO_TEXT_MAX\s+(\d+)", rend)
    if not m:
        problems.append("TH3_INFO_TEXT_MAX is gone from TH3Renderer.mqh: the caption "
                        "no longer states the cap it wraps to (P-TH3-INFO-01)")
    elif int(m.group(1)) > 63:
        problems.append("TH3_INFO_TEXT_MAX is %s, but MT4 truncates an object's text "
                        "at 63 characters: every line past that is silently cut "
                        "mid-word (P-TH3-INFO-01)" % m.group(1))

    draw = body(rend, "int TH3InfoFamilyDraw(")
    if draw is None:
        problems.append("TH3InfoFamilyDraw() is gone - the caption has no owner, so "
                        "nothing wraps it (P-TH3-INFO-01)")
    elif "TH3InfoWrap(" not in draw:
        problems.append("the caption writer no longer wraps its text: it goes to "
                        "OBJPROP_TEXT raw and MT4 cuts it at 63 characters "
                        "(P-TH3-INFO-01)")

    # the caption text itself is written NOWHERE else (one owner, or the wrap is optional)
    stray = [i for i, ln in enumerate(rend.splitlines(), 1)
             if "OBJPROP_TEXT" in ln and "infoText" in ln]
    if stray:
        problems.append("TH3Renderer.mqh still writes the caption text straight into "
                        "OBJPROP_TEXT at line(s) %s: the wrap is bypassed "
                        "(P-TH3-INFO-01)" % ", ".join(str(s) for s in stray))

    tool = strip_comments(read(TH3TOOL))
    # P-TH3-INFO-06b: the sweep SITE, not the substring. `TH3InfoFamilyDelete(`
    # now legitimately appears in the restore path too (orphan plates of skipped
    # bases), so whole-file presence no longer proves the DELETE path goes
    # through the family owner — mutant 8p walked through exactly that hole.
    # The pattern-delete sweep names its base `baseName`; only that call counts.
    if "TH3InfoFamilyDelete(baseName)" not in tool:
        problems.append("TH3Tool's pattern-delete path no longer deletes the caption through the family owner: "
                        "a surviving `_Info2` becomes the next pattern's tail "
                        "(P-TH3-INFO-01)")
    # P-TH3-DEL3: bound to the SWEEP SITE's own test, never the bare substring.
    # The delete path now names the family too (`TH3IsInfoLabelName(sparam)`),
    # and a whole-file test was satisfied by that line alone — mutant 8q walked
    # through the hole this comment's predecessors already warned about.
    if "if(!TH3IsInfoLabelName(nm))" not in tool:
        problems.append("the active-pattern sweep no longer tests the caption FAMILY: "
                        "matching the literal `_Info` recognises line 1 only, so the "
                        "previous pattern's continuation lines stay lit beside the new "
                        "one's (P-TH3-INFO-01)")

    # P-TH3-INFO-02: the caption parks BELOW the mode rows, and the mode rows
    # stand a hardcoded +45 below the ATR stack (ApplyModeLabelStyle) — a safe-Y
    # that forgets the +45 slides the caption's dark plate up inside the mode
    # block (the top-left mash: the SS/LS row wearing the caption's plate).
    safe = body(tool, "int GetABCDInfoSafeYDistance(")
    if safe is None:
        problems.append("GetABCDInfoSafeYDistance() is gone - the caption has no safe-Y "
                        "owner, so nothing keeps it below the mode block (P-TH3-INFO-02)")
    elif "g_modeLabelYOffset + 45" not in safe:
        problems.append("the caption's safe-Y no longer mirrors the mode rows' +45 "
                        "below-ATR offset: the caption parks inside the mode block "
                        "(P-TH3-INFO-02)")

    # P-TH3-INFO-10 (2026-09-22): the plate's visibility is EXISTENCE, never a
    # mask. An OBJ_RECTANGLE_LABEL does not go away under OBJPROP_TIMEFRAMES
    # (the same screen-object fact P-UI-98n proved for OBJ_BITMAP_LABEL), while
    # the OBJ_LABEL rows DO obey theirs - so every family path that masked the
    # plate left a dark bar with no ink on the chart: the report «اول نمایش
    # میده ولی بعد دیگه فقط سیاه هستش» and the fourth recurrence of the
    # "top-left dark empty bar" (INFO-06/06b/06c/08 all aimed at the rows).
    for m in re.finditer(r"ObjectSetInteger\s*\(\s*0,\s*plate,\s*OBJPROP_TIMEFRAMES\s*,\s*([^);]+)\)", rend):
        if "OBJ_ALL_PERIODS" not in m.group(1):
            problems.append(
                "the caption family writes `%s` onto its PLATE's TIMEFRAMES: a mask does "
                "not hide an OBJ_RECTANGLE_LABEL, so a darkened family leaves its empty "
                "bar on the chart (P-TH3-INFO-10)" % m.group(1).strip())
    for head, need in (("void TH3InfoFamilySetVisible(",
                        ("TH3InfoFamilyPlateDrop(", "TH3InfoFamilyPlateGrow(")),
                       ("void TH3InfoFamilyVerify(",
                        ("if(!isActive) { TH3InfoFamilyPlateDrop(base); return; }",
                         "TH3InfoFamilyPlateGrow(")),
                       ("int TH3InfoFamilyDraw(",
                        ("TH3InfoFamilyPlateDrop(",))):
        b = body(rend, head)
        if b is None:
            problems.append("%s is gone - the caption family has no visibility owner "
                            "(P-TH3-INFO-10)" % head.rstrip("("))
            continue
        for token in need:
            if token not in b:
                problems.append("%s no longer carries `%s` - a plate whose visibility is "
                                "not EXISTENCE is a plate only a mask could hide, and a "
                                "mask leaves it on the chart (P-TH3-INFO-10)"
                                % (head.rstrip("("), token))
    draw_b = body(rend, "int TH3InfoFamilyDraw(")
    if draw_b is not None and not re.search(r"if\s*\(\s*isActive\s*\)\s*\{[^}]*TH3ROPlateAt\(", draw_b):
        problems.append("TH3InfoFamilyDraw no longer gates the plate's creation on isActive: "
                        "an inactive family gets a plate no mask can hide (P-TH3-INFO-10)")
    set_b = body(tool, "void SetActiveABCDPattern(")
    if set_b is None:
        problems.append("SetActiveABCDPattern() is gone - the active-pattern sweep has no "
                        "owner (P-TH3-INFO-10)")
    elif "TH3IsInfoPlateName(" not in set_b:
        problems.append("the active-pattern sweep masks the PLATE again instead of dropping "
                        "it: a darkened family leaves its empty bar on the chart "
                        "(P-TH3-INFO-10)")
    # P-TH3-INFO-11 (2026-09-22): the heal net behind the 250 ms clock.
    heal_b = body(rend, "void TH3InfoCaptionHeal(")
    if heal_b is None:
        problems.append("TH3InfoCaptionHeal() is gone - no timer asks after a caption "
                        "whose rows died between redraws, so the dark plate recurs "
                        "(P-TH3-INFO-11)")
    elif "TH3InfoFamilyVerify(base, true)" not in heal_b:
        problems.append("the caption heal no longer verifies through the one owner: "
                        "a second writer of the family's masks (P-TH3-INFO-11)")
    # P-TH3-INFO-13 (2026-09-22): the caption is a TIMED VISITOR. The user's
    # order: «لیبل مود ها و لیبل abcd باید بعد چند ثانیه حذف بشن هرچی که
    # اطلاعاتی هستش» — every info readout leaves after a few seconds, the leg
    # meter's own contract (P-LM-09). The sweep lives in the heal net (the 250
    # ms clock) BEFORE the heal half, so a heal can never resurrect an expired
    # visit; the duration is inpModeLabelDuration, the mode rows' own input.
    heal13 = body(rend, "void TH3InfoCaptionHeal(")
    if heal13 is None:
        problems.append("TH3InfoCaptionHeal() is gone - the caption visit has no sweep "
                        "(P-TH3-INFO-13)")
    else:
        heal_head = heal13[:heal13.find("TH3InfoFamilyVerify(base, true)")
                            if "TH3InfoFamilyVerify(base, true)" in heal13 else len(heal13)]
        if "TickDeadlinePending(g_th3InfoVisitUntilMs)" not in heal_head:
            problems.append("the heal never asks the caption's visit deadline before "
                            "healing: an expired visit is resurrected by the very net "
                            "meant to keep the family honest (P-TH3-INFO-13)")
        if "TH3InfoFamilyDropActive()" not in heal_head:
            problems.append("an expired caption visit no longer drops the family through "
                            "its ONE owner: rows and plate would age apart (P-TH3-INFO-13)")
    arm = body(rend, "void TH3InfoVisitArm(")
    if arm is None:
        problems.append("TH3InfoVisitArm() is gone - the caption visit has no clock "
                        "owner (P-TH3-INFO-13)")
    elif "inpModeLabelDuration" not in arm:
        problems.append("the caption visit no longer reads inpModeLabelDuration: the "
                        "mode rows and the caption would expire on two different "
                        "settings (P-TH3-INFO-13)")
    # P-UI-57f-OFF (2026-09-22): the step-mode row's clock exemption is retired
    # by the same user order - the SS/LS row expires like every event row.
    expire = body(strip_comments(read(UTILS)), "bool CheckAndClearExpiredLabels(")
    if expire is None:
        problems.append("CheckAndClearExpiredLabels() is gone - the mode rows have no "
                        "expiry owner at all (P-UI-57f-OFF)")
    elif "g_stepModeLabelCreateTime) >= durationMs" not in expire:
        problems.append("the step-mode (SS/LS) row no longer expires on the clock: an "
                        "info row that outlives its duration is the furniture the user "
                        "ordered off the chart (P-UI-57f-OFF)")
    return problems


def check_th3_ladder():
    """[th3ladder] - AT MOST ONE LADDER IS VISIBLE (P-TH3-P6f).

    Two patterns in the store drew two Step1/3/5/7 families and the chart
    read as one mixed ladder (XAUUSD M15: Step1 115.4 against 109.6, Step3
    346.3 against 328.8 - each pattern owns its closedStep, so each owns its
    q winner and its lock). The ladder follows the caption: drawn per
    pattern, worn by the ACTIVE one only, through the same two owners - the
    draw gates it on isActive, the activation sweep re-masks the family.
    Chart objects obey TIMEFRAMES (the P-TH3-INFO-10 exception is screen
    plates only).
    """
    problems = []
    rend = strip_comments(read(TH3RENDER))
    if "bool TH3IsLadderName(" not in rend:
        problems.append("TH3IsLadderName() is gone - the ladder family has no test, so "
                        "the activation sweep cannot tell a target from ABCD ink "
                        "(P-TH3-P6f)")
    draw = body(rend, "void DrawABCDPattern(")
    if draw is None:
        problems.append("DrawABCDPattern() is gone - no owner draws the ladder at all "
                        "(P-TH3-P6f)")
    elif "TH3LadderSetVisible(mainObjName, isActive)" not in draw:
        problems.append("DrawABCDPattern no longer gates the ladder on the active "
                        "pattern: every stored pattern wears Step1/3/5/7 and the "
                        "chart reads as one mixed ladder (P-TH3-P6f)")
    tool = strip_comments(read(TH3TOOL))
    set_b = body(tool, "void SetActiveABCDPattern(")
    if set_b is None:
        problems.append("SetActiveABCDPattern() is gone - the active-pattern sweep has "
                        "no owner (P-TH3-P6f)")
    else:
        if "TH3IsLadderName(" not in set_b:
            problems.append("the active-pattern sweep is blind to the ladder family: "
                            "the newly-active pattern stays ladder-less until an "
                            "unrelated redraw (P-TH3-P6f)")
        if "ownLadder ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS" not in set_b:
            problems.append("the active-pattern sweep no longer darkens other ladders: "
                            "activation lights the new family without killing the old "
                            "one (P-TH3-P6f)")
    return problems


def check_th3_delete():
    """[th3delete] - DELETE BY PREFIX, NOT BY SUFFIX LIST (P-TH3-DEL1).

    The old cascade stripped one of seven known suffixes off the deleted
    name: deleting _Line_CD, _Ray_D/_Ray_C, _CDLabel, _HitLine/_HitLabel,
    _MPTick*, _LegPiv, _Temp_*, _Point_X, or any TH3_MP_* overlay member
    (its own prefix never matched at all) extracted NO base and the whole
    family stayed on the chart. Any member reduces to the same base
    (TH3FamilyBaseOf: prefix + digits) and ONE backward sweep kills every
    object wearing it - a rare event, so one sweep is the whole extra load.
    """
    problems = []
    rend = strip_comments(read(TH3RENDER))
    if "string TH3FamilyBaseOf(" not in rend:
        problems.append("TH3FamilyBaseOf() is gone - a deleted member no longer "
                        "reduces to its family base, so only seven suffixed "
                        "members can ever cascade (P-TH3-DEL1)")
    tool = strip_comments(read(TH3TOOL))
    del_b = body(tool, "void OnABCDMouseEvent(")
    if del_b is None:
        problems.append("OnABCDMouseEvent() is gone - pattern deletion has no owner "
                        "(P-TH3-DEL1)")
    else:
        if "TH3FamilyBaseOf(sparam)" not in del_b:
            problems.append("the delete path no longer reduces the deleted member to "
                            "its base: only members wearing a known suffix cascade "
                            "(P-TH3-DEL1)")
        if '"TH3_MP_" + baseName + "_"' not in del_b:
            problems.append("the delete sweep no longer covers the mother overlay: "
                            "deleting a pattern orphans its TH3_MP_* badge and bounds "
                            "(P-TH3-DEL1)")
        if "for(int k = ObjectsTotal(0, -1, -1) - 1; k >= 0; k--)" not in del_b:
            problems.append("the delete sweep no longer walks the object list: member "
                            "deletes remove nothing but themselves (P-TH3-DEL1)")
        # P-TH3-DEL2: our own drops queue behind our draws - the anchors decide.
        if "TH3FamilyAnchorsAlive(baseName)" not in del_b:
            problems.append("the delete path no longer asks the anchors: a redraw's "
                            "own overlay/proof drop wipes the whole ABCD "
                            "(P-TH3-DEL2)")
        if "g_th3OwnDeleteMs" not in del_b:
            problems.append("the delete path lost its maintenance window: every "
                            "member delete wipes, including the draw's own drops "
                            "(P-TH3-DEL2)")
        # P-TH3-DEL3: the window AND its stamp are WALL clock. TimeCurrent only
        # moves when a tick arrives, so on a live chart a drop queued behind our
        # own multi-second redraw read the window as already closed and wiped a
        # healthy family; a frozen clock (no-tick chart) held it open forever.
        # The window is the two-line test itself — the anchors ask AND the wall
        # clock, together. A check on either half alone is satisfied by the
        # other half's line elsewhere in the cascade (mutant 8q-15 walked through
        # exactly that hole once the DEL3 guard named the anchors too).
        # P-TH3-PB-DRAG-LOCK (2026-09-22): the window is 5 s, not 1 s - the
        # band's resize can drag for several seconds and queue MP_* drops that
        # read a 1 s window as already closed on a slow chart (the bug that
        # survived the DEL3 fix).
        if ("if(TH3FamilyAnchorsAlive(baseName)\n"
            "           && GetTickCount() - g_th3OwnDeleteMs <= 5000)") not in del_b:
            problems.append("the maintenance window lost its shape: the anchors "
                            "and the WALL clock must ask together, or a drop "
                            "queued behind our own redraw wipes the family "
                            "(P-TH3-DEL2/DEL3 / P-TH3-PB-DRAG-LOCK)")
        if "g_th3OwnDeleteMs = GetTickCount();" not in rend:
            problems.append("the dropped-object stamp is back on the tick clock "
                            "(P-TH3-DEL3)")
        # P-TH3-DEL3: a caption member's drop is DISPLAY maintenance, never a
        # delete trigger - but only while the family is alive. The anchors term
        # is load-bearing: P-TH3-RESTORE's orphan sweep drops exactly those
        # captions, and those rows carry the delete events that kill a broken
        # family whole.
        if "TH3IsInfoLabelName(sparam) && TH3FamilyAnchorsAlive(baseName)" not in del_b:
            problems.append("a caption drop is a delete trigger again: every plate "
                            "SetActive/Verify/Draw drops wipes a healthy ABCD "
                            "(P-TH3-DEL3)")
        if "bool TH3IsInfoLabelName(" not in rend:
            problems.append("TH3IsInfoLabelName() is gone - the delete path cannot "
                            "tell a caption member from a real one (P-TH3-DEL3)")
        if "TH3PatternStoreGet(baseName, patH)" not in del_b:
            problems.append("the delete path heals nothing back: an internally "
                            "dropped member stays missing until an unrelated "
                            "redraw (P-TH3-DEL2)")
    return problems


def check_th3_pb_lock():
    """[pb-lock] - the base mark's PRESS-DRAG owns the chart view (P-TH3-PB-LOCK).

    Reported: «وقتی بیس مبنا رو میکشم اسکرول پشتش باید قفل باشه که راحت بتونم
    بکشم مثل بقیه». The base mark is a press-drag (P-TH3-PB-DRAG), and a
    press-drag that holds no view lock lets the chart pan under the hand - the
    same report the leg meter (P-LM-11) and the Base/Knot box (P-BK-62) each
    answered. Four things must all hold, in the order the gesture needs them:

      1. ACQUIRE on the press edge - the earliest moment the gesture is provably
         ours.
      2. ASSERT on the held pass (P-BK-14: a third writer can flip the props
         mid-gesture).
      3. RELEASE on EVERY end: the held-move release edge, a cancel
         (right-click / B / leg-meter / draw steal), and the CHARTEVENT_CLICK
         that carries a release no move ever reported (P-LM-13: a motionless
         press/release emits no MOUSE_MOVE).
      4. ChartLockIntended NAMES the owner. Without that term the 250 ms
         ChartScrollReconcile reads our lock as a LEAK and hands the view back
         under the hand mid-drag - which is the whole reason the accessor was
         written (the P-LM-11 precedent, one for one).
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    press = body(tool, "void TH3BaseMarkDragPress(")
    if press is None or "ChartViewLockAcquire()" not in press:
        problems.append("the base mark's press edge never takes the view lock: "
                        "the chart pans under the hand mid-drag (P-TH3-PB-LOCK)")
    elif "s_bmViewLockHeld = true" not in press:
        problems.append("the base mark's press edge takes the raw lock but never "
                        "latches ownership, so nothing can release it "
                        "(P-TH3-PB-LOCK)")
    move = body(tool, "void TH3BaseMarkDragMove(")
    if move is None or "ChartViewLockAssert()" not in move:
        problems.append("the held pass stops re-asserting the view lock: a third "
                        "writer flips the props mid-gesture (P-TH3-PB-LOCK)")
    for what, src in (("the release edge", body(tool, "void TH3BaseMarkDragRelease(")),
                      ("a cancel", body(tool, "void TH3BaseMarkCancel(")),
                      ("the CLICK fallback", body(tool, "void OnABCDMouseEvent("))):
        if src is None or "TH3BaseMarkViewRelease()" not in src:
            problems.append("the base mark's view lock has no release on %s: the "
                            "chart stays locked with nothing holding it "
                            "(P-TH3-PB-LOCK)" % what)
    own = body(tool, "bool TH3BaseMarkViewOwned(")
    if own is None or "s_bmViewLockHeld" not in own:
        problems.append("TH3BaseMarkViewOwned() no longer answers the gesture's "
                        "own latch (P-TH3-PB-LOCK)")
    intended = body(strip_comments(read(PANELS)), "bool ChartLockIntended(")
    if intended is None or "TH3BaseMarkViewOwned()" not in intended:
        problems.append("ChartLockIntended() does not name the base mark's lock: "
                        "the 250 ms reconcile hard-releases it under the hand "
                        "(P-TH3-PB-LOCK)")
    return problems


def check_th3_pb_band_drag_lock():
    """[pb-band-drag-lock] - the BAND's anchor drag owns the chart view
    (P-TH3-PB-DRAG-LOCK, 2026-09-22).

    The press-drag [pb-lock] covers only the initial DRAW of the base mark.
    The BAND itself (the committed rectangle the user draws with the press-drag
    or two clicks) also gets dragged - resized by its own anchors, via
    CHARTEVENT_OBJECT_DRAG. That second drag is its own gesture, and the
    chart was panning under the hand during it because no owner held the
    view lock.

    Six things must all hold, in the order the gesture needs them:

      1. ACQUIRE on the FIRST OBJECT_DRAG for the band - the earliest moment
         we know the gesture is ours (MT4 owns the click that started the
         resize).
      2. ASSERT on every subsequent OBJECT_DRAG (P-BK-14: a third writer
         flips the props mid-drag).
      3. RELEASE on EVERY end: a button-up MOUSE_MOVE (a motionless release
         never emits MOUSE_MOVE — P-BK-03 / P-LM-13), CHARTEVENT_CLICK on
         the band, and the band's own delete path.
      4. HEARTBEAT — a stuck terminal or an off-chart release leaves both
         streams silent; the 250 ms timer is the only heal that doesn't need
         the terminal to cooperate.
      5. ChartLockIntended NAMES the owner — the same P-LM-11 / P-BK-62 rule
         the press-drag [pb-lock] enforces.
      6. The cascade recovery window holds a band drag end-to-end (5 s, not
         1 s). The original 1 s window was tuned for a single commit; a
         multi-second resize queues MP_* drops that read a 1 s window as
         already closed on a slow chart and wipe a healthy ABCD.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    on_drag = body(tool, "void TH3BaseEditorOnDrag(")
    if on_drag is None:
        problems.append("TH3BaseEditorOnDrag() is gone - the band's resize has "
                        "no owner (P-TH3-PB-DRAG-LOCK)")
    else:
        if "ChartViewLockAcquire()" not in on_drag:
            problems.append("the band's anchor drag never takes the view lock: "
                            "the chart pans under the hand mid-resize "
                            "(P-TH3-PB-DRAG-LOCK)")
        if "ChartViewLockAssert()" not in on_drag:
            problems.append("the band's resize stops re-asserting the view lock: "
                            "a third writer flips the props mid-drag "
                            "(P-TH3-PB-DRAG-LOCK)")
        if "s_bandDragLockHeld" not in on_drag:
            problems.append("the band's resize takes the raw lock but never "
                            "latches ownership, so nothing can release it "
                            "(P-TH3-PB-DRAG-LOCK)")
    on_delete = body(tool, "void TH3BaseEditorOnDelete(")
    if on_delete is None or "ChartViewLockRelease()" not in on_delete:
        problems.append("the band's delete path leaves the resize lock held: "
                        "a user Delete leaks the view lock until the 250 ms "
                        "reconcile (P-TH3-PB-DRAG-LOCK)")
    heartbeat = body(tool, "void TH3BaseBandDragHeartbeat(")
    if heartbeat is None or "ChartViewLockRelease()" not in heartbeat:
        problems.append("the band's resize has no heartbeat heal: a stuck "
                        "terminal or off-chart release leaks the lock forever "
                        "(P-TH3-PB-DRAG-LOCK)")
    move_handler = body(tool, "void OnABCDMouseEvent(")
    if (move_handler is None
        or "s_bandDragLockHeld && !leftButtonDown" not in move_handler
        or "ChartViewLockRelease()" not in move_handler):
        problems.append("the band's resize has no button-up release on the "
                        "MOUSE_MOVE stream: a still release never emits "
                        "MOUSE_MOVE — P-BK-03 / P-LM-13 (P-TH3-PB-DRAG-LOCK)")
    own = body(tool, "bool TH3BaseBandDragViewOwned(")
    if own is None or "s_bandDragLockHeld" not in own:
        problems.append("TH3BaseBandDragViewOwned() no longer answers the "
                        "band's resize latch (P-TH3-PB-DRAG-LOCK)")
    intended = body(strip_comments(read(PANELS)), "bool ChartLockIntended(")
    if intended is None or "TH3BaseBandDragViewOwned()" not in intended:
        problems.append("ChartLockIntended() does not name the band's resize "
                        "lock: the 250 ms reconcile hands the view back under "
                        "the hand during a resize (P-TH3-PB-DRAG-LOCK)")
    del_b = move_handler if move_handler is not None else tool
    if "<= 5000" not in del_b:
        problems.append("the cascade recovery window is back at 1 s: a band "
                        "resize queues MP_* drops that wipe a healthy ABCD "
                        "(P-TH3-PB-DRAG-LOCK)")
    return problems


def check_th3_band_gesture():
    """[pb-band-gesture] - the band's press edge owns the view, and a click on
    the TH3 tool's own objects never blanks the pattern (P-TH3-BAND-PRESS /
    P-TH3-BANDSEL, 2026-09-22).

    Two residuals survived P-TH3-PB-DRAG-LOCK, both from the same gesture -
    aiming at the committed band at working zoom:

      1. THE PRESS PAN. The resize lock was taken on the FIRST OBJECT_DRAG -
         but between the press and that first event the terminal had already
         begun the chart pan (the press that misses the anchor by a hair).
         The press edge on the MOUSE_MOVE stream now hit-tests the band's
         outline corridor and takes the lock there. The same early-out
         (P-TH3-PERF-05) returned before the button-up release branch ever
         ran, so the lock leaked to the 1.5 s heartbeat after EVERY resize -
         the release branch must be reachable, which means the early-out must
         name the live band gesture.
      2. THE CLICK DESELECTION. CHARTEVENT_OBJECT_CLICK on anything that is
         not an ABCD_Pattern_* member blanked the active pattern - and the
         band's click, plus the click echo that follows EVERY band drag's
         button-up, fell exactly there: the ladder masked, the caption plate
         dropped, every later re-step redraw keeping them dark. The whole
         ABCD read as deleted («بیس مبنا که میکشم ... باعث حذف abcd میشه»).
         The TH3 tool's own namespace (TH3_BaseEditor, TH3_BaseMark_1,
         TH3_P6_*, TH3_MP_*) is the pattern's own tooling - its click is a
         no-op for activation.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    events = strip_comments(read(EVENTS))

    hit = body(tool, "bool TH3BaseBandPressHit(")
    if hit is None:
        problems.append("TH3BaseBandPressHit() is gone - the band's press edge "
                        "cannot claim the view and the chart pans before the "
                        "first OBJECT_DRAG (P-TH3-BAND-PRESS)")
    elif "TH3_BAND_HIT" not in hit or "ChartTimePriceToXY" not in hit:
        problems.append("the band's press hit test lost its outline corridor "
                        "or its pixel projection (P-TH3-BAND-PRESS)")

    move_handler = body(tool, "void OnABCDMouseEvent(")
    if move_handler is None:
        problems.append("OnABCDMouseEvent() is gone (P-TH3-BAND-PRESS)")
    else:
        if "TH3BaseBandPressHit(" not in move_handler or \
           "s_bandPressDown" not in move_handler:
            problems.append("the move stream no longer claims the view on the "
                            "press edge ON the band (P-TH3-BAND-PRESS)")
        if "s_bandDragLockHeld && !leftButtonDown" not in move_handler:
            problems.append("the band gesture's button-up release branch is "
                            "gone from the move stream (P-TH3-PB-DRAG-LOCK)")
        # The P-TH3-PERF-05 early-out must let a live band gesture (and a
        # chart that carries a band) through, or the release edge above stays
        # dead code and every resize leaks the lock to the heartbeat.
        early = re.search(r"if\(id == CHARTEVENT_MOUSE_MOVE && !TH3SessionActive\(\) "
                          r"&& !TH3BaseMarkArmed\(\)\s*\n\s*&&[^\n]*\)",
                          tool)
        if not early or "s_bandDragLockHeld" not in early.group(0):
            problems.append("the idle-move early-out does not name the live "
                            "band gesture: the button-up release branch is "
                            "unreachable and every resize leaks the lock to "
                            "the 1.5 s heartbeat (P-TH3-BAND-PRESS)")

    # P-TH3-BANDSEL: the OBJECT_CLICK else-branch must not deselect on the
    # TH3 tool's own namespace.
    if "else if(StringFind(sparam, \"TH3_\") != 0)" not in events:
        problems.append("a click on the TH3 tool's own objects blanks the "
                        "active pattern again: the band's click (and every "
                        "band drag's click echo) masks the ladder and drops "
                        "the plate - the ABCD reads as deleted "
                        "(P-TH3-BANDSEL)")
    return problems


def check_leg_plate_lifetime():
    """[legplate] - the leg meter's readout is a VISITOR, and it belongs to the LINE
    (P-LM-09, place retired by P-LM-23).

    The reference leg meter prints its three rows in a dark plate ON the candles the
    leg crosses. The tool's first cut did the same, and the user's own screenshot is
    the report: a box over the price action is a box nobody reads, and one that stays
    there is furniture the chart has to live with. Two rules came out of it, and this
    gate exists so that neither can be dropped by a refactor:

      1. PLACE (P-LM-23). The plate has ONE place: past the SECOND tip ALONG the
         leg, LEG_INFO_GAP away, so the tip and its handle stay visible and the
         plate reads as the label of the head. P-LM-07/09's seven-slot walk is
         retired: it put the plate wherever was clear, and on the user's chart
         that was up-left of the tip, ON the candles - «همیشه سر نوک دوم باشه».
         A fallback slot is how the plate lands on candles, so the order, its
         push, the hit test, the strip readers and the remembered slot must all
         stay retired.
      2. LIFETIME. `LEG_INFO_SHOW_MS` on a `GetTickCount()` deadline, swept from the
         FULL entry's OnTimer (250 ms) so a tick-less chart expires it too, deleted
         through ONE owner (which deletes the plate AND its three rows), never
         resurrected by the follower, and brought back by a click on the leg -- the
         line, because the plate itself is deliberately non-selectable (P-LM-05).

    The direction is read OFF THE CODE (the placement is handed `tx - sx`), not
    assumed: the plate is one line's label, and a tip-relative slot is exactly the
    shape this rule replaced.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    entry = strip_comments(read(ENTRY))
    lite = strip_comments(read(ENTRY_LITE))

    m = re.search(r"(?m)^\s*#define\s+LEG_INFO_SHOW_MS\s+(-?\d+)", tool)
    if not m:
        problems.append("LEG_INFO_SHOW_MS is gone from TH3Tool - the plate's visit has "
                        "no declared length, so 'it disappears' is a promise with no "
                        "number behind it (P-LM-09)")
    elif int(m.group(1)) <= 0:
        problems.append("LEG_INFO_SHOW_MS is %s: a plate that never expires is the "
                        "furniture this rule exists to remove (P-LM-09)" % m.group(1))

    sweep = body(tool, "void LegMeasureExpireSweep(")
    if sweep is None:
        problems.append("LegMeasureExpireSweep() is gone - nothing ever ends a visit, so "
                        "every readout ever drawn stays on the chart (P-LM-09)")
    else:
        if "LegMeasurePlateHide(" not in sweep:
            problems.append("the sweep no longer hides a plate through its ONE owner: a "
                            "second delete path is how a row outlives its plate (P-LM-09)")
        if "TickDeadlinePending(g_legShownUntil[" not in sweep:
            problems.append("the sweep no longer asks the visit's deadline through the "
                            "wrap-safe owner (TickDeadlinePending): an absolute comparison "
                            "against GetTickCount() never closes across the 49.7-day wrap "
                            "(P-LM-09 / [tick-wrap])")
        if "g_legPlateUp[" not in sweep:
            problems.append("the sweep no longer asks whether a plate is UP: a 250 ms "
                            "timer that re-deletes every measurement forever is work the "
                            "expiry cannot need (P-PERF-02 / P-LM-09)")
        if not re.search(r"if\(g_legCount\s*<=\s*0\)\s*return;", sweep):
            problems.append("the sweep lost its empty-registry early exit: on a chart "
                            "with no measurement it must cost one comparison "
                            "(P-PERF-02 / P-LM-09)")

    dele = body(tool, "void LegInfoBoxDelete(")
    if dele is None:
        problems.append("LegInfoBoxDelete() is gone - the plate and its three rows have "
                        "no single delete owner (P-LM-09)")
    else:
        for nm in ('"_Box"', '"_Info"', '"_Info2"', '"_Info3"'):
            if nm not in dele:
                problems.append("LegInfoBoxDelete() no longer removes %s: the readout's "
                                "family is FOUR objects, and every survivor is a dark bar "
                                "or a stray row left on the chart (P-LM-09)" % nm)

    hide = body(tool, "void LegMeasurePlateHide(")
    if hide is None:
        problems.append("LegMeasurePlateHide() is gone (P-LM-09)")
    elif "LegInfoBoxDelete(" not in hide or "g_legPlateUp[" not in hide:
        problems.append("hiding a plate no longer clears its flag and/or deletes through "
                        "LegInfoBoxDelete(): the sweep and the click would disagree about "
                        "whether the readout is on the chart (P-LM-09)")

    show = body(tool, "void LegMeasurePlateShow(")
    if show is None:
        problems.append("LegMeasurePlateShow() is gone - a click has nothing to bring the "
                        "readout back with (P-LM-09)")
    else:
        if "LegMeasureBoxFromLine(" not in show:
            problems.append("the re-show path no longer rebuilds the plate from the LINE's "
                            "own anchors: it would show a tip the line has left (P-LM-09)")
        arm = show.find("g_legShownUntil[idx]")
        build = show.find("LegMeasureBoxFromLine(")
        if arm < 0 or "g_legPlateUp[idx]" not in show:
            problems.append("showing a plate no longer re-arms the visit "
                            "(g_legShownMs/g_legPlateUp): it would return only to vanish on "
                            "the previous visit's clock (P-LM-09)")
        elif build >= 0 and arm > build:
            problems.append("the clock is re-armed AFTER the plate is rebuilt, so a rebuild "
                            "that fails leaves a running timer and no plate (P-LM-09)")

    # P-LM-11: the click is the EDIT owner's still press now (the family is not
    # selectable, so no OBJECT_CLICK ever names it). The drag's END must bring the
    # readout back on a click, and the STILL-CLICK branch specifically must — the
    # moved path's own call does not answer a click.
    click = body(tool, "void LegMeasureDragEnd(")
    if click is None or "LegMeasurePlateShow(" not in click:
        problems.append("a click on the leg no longer calls LegMeasurePlateShow(): the "
                        "readout expires once and can never be read again, which is the "
                        "half of P-LM-09 the user asked for by name (P-LM-09 / P-LM-11)")
    if "        LegMeasurePlateShow(base);\n        return;" not in read(TH3TOOL):
        problems.append("the STILL-CLICK branch no longer re-arms the visit (the moved "
                        "path's own call is not a click): the readout becomes readable "
                        "only right after a real drag (P-LM-09 / P-LM-11)")

    follow = body(tool, "void LegMeasureFollowAll(")
    if follow is None:
        problems.append("LegMeasureFollowAll() is gone (P-LM-02)")
    elif "g_legPlateUp[i]" not in follow:
        problems.append("the follower no longer gates on g_legPlateUp[]: a scroll or a zoom "
                        "re-opens a plate that has finished its visit (P-LM-09)")

    # P-LM-23: ONE place - the walk and its memory are retired. A fallback slot
    # is how the plate landed on the user's candles, so the order, its push,
    # the hit test, the strip readers and the remembered slot must all stay gone.
    for dead in ("LegInfoSlotOrder(", "LegInfoSlotPush(", "LegInfoHits(",
                 "LegInfoStrip(", "LegMeasureSetSlot(", "g_legSlot"):
        if dead in tool:
            problems.append("%s survives in TH3Tool: the slot walk P-LM-23 retired is "
                            "one call away from putting the plate back on the candles "
                            "(P-LM-23)" % dead)

    rect = body(tool, "void LegInfoSlotRect(")
    if rect is None or "LEG_INFO_GAP" not in rect or "dirX" not in rect:
        problems.append("LegInfoSlotRect() no longer stands past the tip ALONG the leg "
                        "at the fixed gap: the plate's one place is gone (P-LM-23)")
    elif "LEG_INFO_SLOT_" in rect:
        problems.append("LegInfoSlotRect() still branches on slot ids: a second place "
                        "for the plate is one call away (P-LM-23)")

    if "LegInfoBoxPlace(base, tx, ty, tx - sx, ty - sy, txt, create);" not in tool:
        problems.append("the plate is no longer placed from the leg's own direction (tip "
                        "minus start, read back off the line): every candidate becomes "
                        "tip-relative again (P-LM-09)")

    top = body(tool, "void LegInfoBoxTop(")
    if top is None or "LegInfoSlotRect(" not in top or "LegInfoClampY(" not in top:
        problems.append("LegInfoBoxTop() no longer projects the one LINE rectangle and "
                        "fits it in the window: the plate is not at the second tip (P-LM-23)")

    place = body(tool, "void LegInfoBoxPlace(")
    if place is None or "LegInfoBoxTop(" not in place:
        problems.append("LegInfoBoxPlace() no longer goes through LegInfoBoxTop(): the "
                        "plate is placed from somewhere the tip rule does not own (P-LM-23)")

    gap = re.search(r"(?m)^\s*#define\s+LEG_INFO_GAP\s+(-?\d+)", tool)
    if not gap:
        problems.append("LEG_INFO_GAP is gone: the tip-to-plate distance has no declared "
                        "value, so 'with a distance' is a promise with no number (P-LM-23)")
    elif int(gap.group(1)) <= 0:
        problems.append("LEG_INFO_GAP is %s: the plate sits ON the tip it must stand "
                        "clear of, and the tip's own handle with it (P-LM-23)"
                        % gap.group(1))

    ontimer = body(entry, "void OnTimer(")
    if ontimer is None or "LegMeasureExpireSweep();" not in ontimer:
        problems.append("the FULL entry's OnTimer no longer runs LegMeasureExpireSweep(): a "
                        "plate then expires only on a tick, i.e. never on a weekend or a "
                        "dead symbol (P-LM-09)")
    if "LegMeasureExpireSweep" in (body(lite, "void OnTimer(") or ""):
        problems.append("the LITE entry runs the leg meter's sweep: Lite compiles the "
                        "domain half and not this tool's UI (P-BUILD-01 / P-LM-09)")

    return problems


def check_leg_head_follow():
    """[legdrag] - the leg is a CUSTOM trendline: the drag is ours, one pass, zero lag (P-LM-11).

    The user's report: «الان خط جابجا میشه ولی اون دایره دیرتر میچسبه» — the line moved
    under a NATIVE drag and the markers caught up late. P-LM-10 answered with three
    follow channels and the race STAYED, because the race was the terminal moving one
    object on its own paint schedule against us writing the others. So the race is
    removed: NOTHING of a measurement is selectable, and the drag is the tool's own —
    a press hit-tests the family in screen pixels, and every held move rewrites the
    whole drawing (line, both rings, the mid handle, the head, the plate) from the
    same anchors in the same MOUSE_MOVE event. What moves together, stays together.

    Pinned here:

      * THE HANDLES. `LegHandleAt` sizes an OBJ_ELLIPSE in SCREEN pixels by probing
        the chart's own projection ±rpx — a ring of exactly rpx radius, centred on
        the anchor from every direction, on every zoom (the user's «وسط باشه دقیقا
        از هر جهت»; the retired OBJ_ARROW dot anchored at its glyph's corner, 1px
        wide). `LegMeasureInk` builds the whole family through it and sets the line
        SELECTABLE=false — a native drag is the very race this rule removes.
      * THE ONE PASS. `LegMeasureEditMouse` is the edit's only entry, routed from
        EventHandlers' MOUSE_MOVE; a live drag re-anchors through `LegMeasureInk`
        ITSELF (LegMeasureDragApply — the same writer the fresh draw and the
        migration use), the view lock is taken on the press and released on every
        exit, a cancel restores the press-time snapshot, and the retired channels
        (OBJECT_DRAG, the selection gate, the timer) must stay retired.
      * THE HEAD STAYS RETIRED (P-LM-12). The user's verdict on the finished shape:
        «پیکان نباشه سرش هر دو سر دایره باشه مثل این» — the drawing is the plain
        line wearing its rings, no triangle head, in the committed family AND in
        the draw preview. The retired `_Arrow`/`LM_prev_Arrow` names survive only
        as sweeps (migration, deletes, `LegPreviewClear`), and the gate fails if
        the shape owner (`LegArrowAt`) or an `OBJ_TRIANGLE` returns.
      * THE DELETE PROMISE (P-LM-08) in its P-LM-17 shape: the line is
        SELECTABLE again, so the terminal's OWN gestures answer - right-click
        menu (Properties AND Delete), keyboard Delete on the selection, the
        object list - and CHARTEVENT_OBJECT_DELETE cascades to the whole
        family. The click-era gestures (virtual selection, the armed
        right-click, the double-click) stay retired.
      * P-LM-21: the native drag is disarmed for the drag's own duration, and
        ONLY for it. Selectability (above) and MT4's armed native drag are two
        different things: the terminal arms the drag at the press and then moves
        ONE object on its own paint schedule, and the discs are separate bitmaps
        it cannot carry, so the line slides out from under them mid-drag
        («دایره ها از خط جدا میشه»). `LegMeasureDragSelectable` is the one
        borrower: the drag turns the flag OFF once the gesture is a real drag
        (never on a still press - the terminal's own click-selection, P-LM-20,
        answers that), and BOTH exits (the commit and the abort) put it back,
        or the leg stays deaf to every native gesture the moment after the user
        first dragged it. A gate that borrows and never returns is a one-way
        `SELECTABLE=false`, which is exactly the P-LM-17 bug with a new seat.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    events = strip_comments(read(EVENTS))
    entry = strip_comments(read(ENTRY))

    # ── P-LM-21: the drag borrows selectability, and must return it ──
    sup = body(tool, "void LegMeasureDragSelectable(")
    if sup is None:
        problems.append("LegMeasureDragSelectable() is gone - the drag has no way to "
                        "disarm MT4's native drag, and the line parts from its discs "
                        "while the user drags it (P-LM-21)")
    else:
        if "OBJPROP_SELECTABLE" not in sup or "ObjectFind" not in sup:
            problems.append("LegMeasureDragSelectable() does not guard its write on the "
                            "line's own SELECTABLE: a drag on a deleted leg, or one "
                            "written blind, is a property write on nothing (P-LM-21)")
    edit = body(tool, "bool LegMeasureEditMouse(")
    if edit is None or "LegMeasureDragSelectable(s_legDragBase, false)" not in edit:
        problems.append("LegMeasureEditMouse() no longer disarms the native drag on the "
                        "first held move: the terminal moves the trendline on its own "
                        "paint schedule and the discs cannot follow it, so the family "
                        "comes apart in the user's hand (P-LM-21)")
    for name in ("void LegMeasureDragEnd(", "void LegMeasureDragAbort("):
        fn = body(tool, name)
        if fn is None or "LegMeasureDragSelectable(base, true)" not in fn:
            problems.append("%s does not return the line's SELECTABLE: the drag borrowed "
                            "it and a gesture that ends without returning it leaves the "
                            "leg deaf to the right-click menu and keyboard Delete "
                            "forever after (P-LM-21)" % name)

    # ── the handles: baked icons, centred in screen pixels, never selectable ──
    # (P-LM-16 split the owner: LegHandleAt only projects, LegHandleAtXY
    # places — the pins below read the PLACE, which is where the rules live.)
    hand = body(tool, "void LegHandleAtXY(")
    if hand is None and body(tool, "void LegHandleAt(") is None:
        problems.append("LegHandleAt()/LegHandleAtXY() are gone - the ring has no "
                        "single owner, so the handles can drift off the exact-centre "
                        "rule that replaced the glyph dot (P-LM-11)")
    if hand is None:
        hand = body(tool, "void LegHandleAt(") or ""
    if hand is None:
        problems.append("LegHandleAt() is gone - the ring has no single owner, so the "
                        "handles can drift off the exact-centre rule that replaced the "
                        "glyph dot (P-LM-11)")
    else:
        if "OBJ_BITMAP_LABEL" not in hand or "OBJPROP_BMPFILE" not in hand:
            problems.append("LegHandleAt() is not a baked-icon bitmap label any more: "
                            "chart-space rings drew as hairlines (an ellipse whose "
                            "anchors share a bar) and the user asked for icons - "
                            "«از ایکون بساز براش» (P-LM-13/14)")
        if "x - half" not in hand or "y - half" not in hand:
            problems.append("the icon is no longer CENTRED on its anchor (x/y - half): "
                            "the handle hangs off the line end (P-LM-14)")
        if "ChartTimePriceToXY" not in (body(tool, "void LegHandleAt(") or ""):
            problems.append("LegHandleAt() no longer projects its anchor through the "
                            "chart's own projection: the handle would not follow the "
                            "line (P-LM-14)")
        if "OBJPROP_SELECTABLE, false" not in hand:
            problems.append("a handle is SELECTABLE again: MT4 would drag it alone, which "
                            "is the separation this rule removes (P-LM-11)")
    if "OBJ_ELLIPSE" in tool:
        problems.append("a chart-space ellipse ring is back in the leg module: it drew "
                        "as a hairline at working zoom - the handles are baked icons "
                        "(P-LM-13/14)")
    for res in ('leg_handle_up.bmp', 'leg_handle_up_mid.bmp',
                'leg_handle_dn.bmp', 'leg_handle_dn_mid.bmp'):
        if ('#resource "\\\\Files\\\\Icons\\\\' + res + '"') not in read(TH3TOOL):
            problems.append("the handle icon %s has no #resource in TH3Tool: the bitmap "
                            "stops embedding and the handles go blank (P-LM-14/17)" % res)
        if res not in read(MANIFEST_PATH):
            problems.append("the handle icon %s is not in the icon manifest: a #resource "
                            "outside the manifest embeds a ghost (P-LM-14 / R-ICON)" % res)
    if '#resource "\\\\Files\\\\Icons\\\\leg_handle.bmp"' in read(TH3TOOL) or \
       '#resource "\\\\Files\\\\Icons\\\\leg_handle_del.bmp"' in read(TH3TOOL):
        problems.append("a retired handle raster (the violet/del pair) is embedded again: "
                        "the handles wear the leg's DIRECTION pair now (P-LM-17)")
    hnd = body(tool, "void LegMeasureHandles(")
    if hnd is None or "LEG_HANDLE_UP_RES" not in hnd or "LEG_HANDLE_DN_RES" not in hnd:
        problems.append("LegMeasureHandles() no longer builds the family's three icon "
                        "handles through the DIRECTION resource constants (P-LM-17)")
    ro = body(tool, "void LegMeasureReadout(")
    if ro is None or "LEG_BULL_INK" not in ro or "LEG_BEAR_INK" not in ro:
        problems.append("the readout no longer answers the leg's DIRECTION ink "
                        "(bull/bear, automatic): «رنگ لگ متر صعودی و نزول فرق بکنه "
                        "خودکار» (P-LM-17)")
    ink = body(tool, "void LegMeasureInk(")
    if ink is None:
        problems.append("LegMeasureInk() is gone - the family has no one writer, which is "
                        "the one-pass guarantee itself (P-LM-11)")
    else:
        if "LegMeasureHandles(base" not in ink:
            problems.append("the ink writer no longer builds the handles: a measurement "
                            "can exist without its rings again (P-LM-11)")
        if ink.count("OBJPROP_SELECTABLE, true") < 2:
            problems.append("the leg's line is not SELECTABLE twice over (create + the "
                            "refresh re-own): the terminal's own gestures (right-click "
                            "Properties/Delete, keyboard Delete) answer the selection, and "
                            "a line owned false on one path stays deaf - the user's «حذف "
                            "مثل بقیه باشه» and «تنظیماتش مثل بقیه بیاد» (P-LM-17)")
        # P-LM-17: the create branch alone is NOT enough - a leg drawn by the
        # non-selectable era survives the migration through LegMeasureInk's
        # refresh path, and a line that stays SELECTABLE=false never reaches
        # MT4's right-click menu («مثل بقیه ابجکت ها دکمه دیلیچ نمیاد»).
        # P-LM-21: the re-own is GATED now - while our own drag owns this base the
        # flag must stay OFF (MT4's native drag parts the line from its discs), so
        # the gate the check asks for is the pair, not the bare re-own line.
        if "OBJPROP_SELECTABLE, true" not in ink or "dragOwnsThis" not in ink:
            problems.append("the ink's refresh path no longer re-owns SELECTABLE, or lost "
                            "the drag-owns-this gate on that re-own: a legacy leg (drawn "
                            "before P-LM-17) stays non-selectable through the migration "
                            "and its right-click Delete never comes, and a drag that "
                            "re-owns mid-gesture re-arms the native drag that parts the "
                            "line from its discs (P-LM-17 / P-LM-21)")
        if "OBJPROP_ARROWCODE" in tool:
            problems.append("a Wingdings glyph marker is being created again in the leg "
                            "module: the dot was retired for a ring that is centred from "
                            "every direction (P-LM-11)")
    # ── P-LM-12: the head STAYS retired — the drawing is the plain line + rings ──
    # The user's verdict: «پیکان نباشه سرش هر دو سر دایره باشه مثل این». The
    # triangle projection, its shape owner and the preview's head are gone; the
    # `_Arrow` name survives only as a retired name the sweep paths delete.
    if "OBJ_TRIANGLE" in tool or "LegArrowAt" in tool:
        problems.append("the leg's arrowhead is back: the user retired it - the drawing "
                        "is the plain line wearing its rings, no head (P-LM-12)")
    pre = body(tool, "void LegPreviewClear(")
    if pre is None:
        problems.append("LegPreviewClear() is gone - the preview's line has no single "
                        "teardown (P-LM-10)")
    else:
        if '"LM_prev_Line"' not in pre:
            problems.append("LegPreviewClear() no longer deletes \"LM_prev_Line\": the "
                            "preview is left on the chart (P-LM-10)")
    lineOcc = tool.count('ObjectDelete(0, "LM_prev_Line");')
    if lineOcc != 1 or pre is None or 'ObjectDelete(0, "LM_prev_Line");' not in pre:
        problems.append("the preview line is deleted %d time(s) in TH3Tool and not "
                        "through LegPreviewClear() alone: one exit from the gesture then "
                        "leaves the preview behind (P-LM-10)" % lineOcc)
    if tool.count('"LM_prev_Arrow"') != 1 or pre is None or '"LM_prev_Arrow"' not in pre:
        problems.append("the preview's retired head name is referenced outside its ONE "
                        "retired-name sweep (LegPreviewClear): the preview is wearing an "
                        "arrow again (P-LM-12)")

    # ── the family still follows the CHART (scroll/zoom) through the follower ──
    follow = body(tool, "void LegMeasureFollowAll(")
    if follow is None:
        problems.append("LegMeasureFollowAll() is gone (P-LM-02)")
    elif "LegMeasureHandles(base" not in follow:
        problems.append("the follower no longer re-projects the handles: a zoom leaves "
                        "rings built for the previous scale (and the retired dot's sin, "
                        "a marker off its anchor, again) (P-LM-02 / P-LM-11)")

    # ── the edit owner and its three exits ──
    edit = body(tool, "bool LegMeasureEditMouse(")
    if edit is None:
        problems.append("LegMeasureEditMouse() is gone - the drag has no owner, so "
                        "nothing moves the family in lockstep any more (P-LM-11)")
    else:
        for need in ("LegMeasureHitTest(", "ChartViewLockAcquire()", "ChartViewLockHeld()",
                     "LegMeasureDragApply(", "LegMeasureDragEnd(", "LegMeasureDragAbort(",
                     "LegMeasureRideChart();",
                     "if(s_legDragMode != 0 && pressed) LegMeasureDragEnd();"):
            if need not in edit:
                problems.append("LegMeasureEditMouse() lost `%s`: the press/drag/cancel/"
                                "release state machine is incomplete (P-LM-11)" % need)
        if "g_legSess.active" not in edit:
            problems.append("the edit owner no longer stands down while the draw session "
                            "is ARMED: a press could start a drag instead of a new "
                            "measurement (P-LM-11)")
    apply_ = body(tool, "void LegMeasureDragApply(")
    if apply_ is None or "LegMeasureInk(" not in apply_:
        problems.append("the drag step no longer re-anchors through LegMeasureInk() - the "
                        "family's ONE writer: parts written elsewhere move on a different "
                        "schedule, which is the lag this rule removes (P-LM-11)")
    abort = body(tool, "void LegMeasureDragAbort(")
    if abort is None or "ChartViewLockRelease()" not in abort or "s_legSnapT1" not in abort:
        problems.append("the cancel path is gone or no longer restores the press-time "
                        "snapshot (s_legSnapT1) / no longer releases the view lock: a "
                        "right-click mid-drag would leave the leg moved and the chart "
                        "scroll-locked (P-UI-90 / P-LM-11)")
    end = body(tool, "void LegMeasureDragEnd(")
    if end is None:
        problems.append("LegMeasureDragEnd() is gone - the release has no owner (P-LM-11)")
    else:
        if "ChartViewLockRelease()" not in end:
            problems.append("the release no longer gives the view back: one drag locks "
                            "scroll + context menu forever (P-UI-90 / P-LM-11)")
        if "LegMeasureReadout(" not in end:
            problems.append("the release no longer recomputes the readout from the FINAL "
                            "anchors: the plate would advertise the numbers of the leg as "
                            "the press found it (P-LM-03 / P-LM-11)")
        if "LegMeasureDelete(" in end:
            problems.append("the CLICK gesture deletes directly again: deletion belongs "
                            "to the terminal's OWN selection gestures (right-click menu, "
                            "keyboard Delete) - a stray click must never cost a drawing "
                            "(P-LM-17)")
    # ── P-LM-17: the selection/delete gestures of the non-selectable era stay retired
    for dead in ("LegMeasureSelectionDelete", "s_legSelBase", "LegMeasureArmDelete",
                 "LegMeasureDisarm", "s_legDelArmBase", "LEG_CTX_HOLD_MS"):
        if dead in tool:
            problems.append("%s is back in TH3Tool: the click/right-click delete "
                            "gestures were rejected («دابل کلیک سخته», «حذف مثل بقیه "
                            "باشه») - the terminal's own selection answers now "
                            "(P-LM-17)" % dead)

    # ── the motionless click's release (P-LM-13) ──
    fin = body(tool, "void LegMeasureClickFinalize(")
    if fin is None or "LegMeasureDragEnd(" not in fin or "s_legDragMoved" not in fin:
        problems.append("LegMeasureClickFinalize() is gone - a motionless press/release "
                        "emits no MOUSE_MOVE, so the drag state sticks live: the view "
                        "lock stays held, the plate hangs, and the Delete key finds no "
                        "selection («چرا نمیشه حذفش کرد») (P-LM-13)")
    if "if(id == CHARTEVENT_CLICK) LegMeasureClickFinalize();" not in events:
        problems.append("CHARTEVENT_CLICK no longer reaches LegMeasureClickFinalize(): "
                        "the motionless click has no release path (P-LM-13)")

    # ── the retired channels must stay retired ──
    for dead in ("LegMeasurePickUp", "LegMeasurePickedUp", "LegMeasureFollowHeld",
                 "LegMeasureFollowTimer", "LEG_FOLLOW_MS"):
        if dead in tool:
            problems.append("%s is back in TH3Tool: a follow channel chases a native drag "
                            "that no longer exists - the race this rule removed is back "
                            "with it (P-LM-11)" % dead)
    if "LegMeasureEditMouse((int)lparam" not in events:
        problems.append("EventHandlers no longer routes MOUSE_MOVE to the edit owner "
                        "(LegMeasureEditMouse): the drag has no event to move in (P-LM-11)")
    if "LegMeasureFollowHeld" in events or \
       "CHARTEVENT_OBJECT_DRAG && StringFind(sparam, TH3_LEG_PREFIX)" in events:
        problems.append("a retired drag channel is wired again in EventHandlers "
                        "(FollowHeld / the leg OBJECT_DRAG branch) (P-LM-11)")
    if "LegMeasureSelectionDelete()" in events:
        problems.append("the retired virtual-selection Delete route is wired again in "
                        "EventHandlers (P-LM-17)")
    if "LegMeasureOnObjectDelete(sparam)" not in events:
        problems.append("EventHandlers no longer cascades the NATIVE delete of the leg's "
                        "line (LegMeasureOnObjectDelete): a right-click-menu or keyboard "
                        "deletion leaves the icons and the plate behind (P-LM-08 / "
                        "P-LM-17)")
    if "LegMeasureFollowTimer" in (body(entry, "void OnTimer(") or ""):
        problems.append("the FULL entry's OnTimer still runs the retired drag channel "
                        "(LegMeasureFollowTimer) (P-LM-11)")
    if "LegMeasureRideChart();" not in (body(entry, "void OnTimer(") or ""):
        problems.append("the FULL entry's OnTimer no longer runs the handles' third "
                        "riding channel (LegMeasureRideChart): a scroll that reports "
                        "neither mouse move nor chart change leaves the dots behind "
                        "(P-LM-16b)")

    return problems


def check_leg_selection():
    """[leg-sel] - the selection has a FACE (P-LM-18).

    The user: «حالت سلکتش با سلکت نبودنش اصلا متوجه نمیشیم همش یک شکله متر لگ» —
    the line is SELECTABLE again (P-LM-17), but a selected leg looked EXACTLY
    like a resting one: MT4's own anchor squares hide UNDER the baked handle
    icons, so nothing on the drawing answered the selection.

    Pinned here:

      * ONE READER. `LegMeasureSelected()` reads the terminal's OWN
        `OBJPROP_SELECTED` off the `_Line` — a cached second opinion of the
        selection is the lie that made the two states look alike in the first
        place.
      * THE HOLLOW PAIR. While selected, the three solid dots swap to the
        hollow `_sel` rasters (same canvases, same centres, so the grab radii
        and the exact-centre rule are untouched); all four are `#resource`d and
        manifest-listed.
      * THE WIDER LINE. `LEG_LINE_W` -> `LEG_LINE_W_SEL` through the guarded
        writers on channels that are ALREADY running — `LegMeasureInk`'s
        refresh (so a drag on a selected leg keeps the width) and
        `LegMeasureRideChart` (so a native click that selects the leg is
        answered on the next mouse-move/timer pass). No new event channel,
        therefore nothing to lag.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    sel = body(tool, "bool LegMeasureSelected(")
    if sel is None or "OBJPROP_SELECTED" not in sel or "_Line" not in sel:
        problems.append("LegMeasureSelected() is gone or no longer reads the terminal's "
                        "own OBJPROP_SELECTED off the `_Line`: a cached second opinion of "
                        "the selection is what made the two states look alike (P-LM-18)")
    hnd = body(tool, "void LegMeasureHandles(")
    if hnd is None or "LEG_HANDLE_UP_SEL_RES" not in hnd \
            or "LEG_HANDLE_DN_SEL_RES" not in hnd \
            or "LEG_HANDLE_UP_MID_SEL_RES" not in hnd \
            or "LEG_HANDLE_DN_MID_SEL_RES" not in hnd:
        problems.append("LegMeasureHandles() no longer swaps to the HOLLOW pair while "
                        "the leg is selected: a selected leg reads exactly like a "
                        "resting one - «حالت سلکتش با سلکت نبودنش ... یک شکله» (P-LM-18)")
    for res in ('leg_handle_up_sel.bmp', 'leg_handle_up_mid_sel.bmp',
                'leg_handle_dn_sel.bmp', 'leg_handle_dn_mid_sel.bmp'):
        if ('#resource "\\\\Files\\\\Icons\\\\' + res + '"') not in read(TH3TOOL):
            problems.append("the selected-handle icon %s has no #resource in TH3Tool: "
                            "the bitmap stops embedding and the selected face goes "
                            "blank (P-LM-18)" % res)
        if res not in read(MANIFEST_PATH):
            problems.append("the selected-handle icon %s is not in the icon manifest: a "
                            "#resource outside the manifest embeds a ghost "
                            "(P-LM-18 / R-ICON)" % res)
    ride = body(tool, "void LegMeasureRideChart(")
    if ride is None or "LegMeasureLineWidth" not in ride or "OBJPROP_WIDTH" not in ride:
        problems.append("LegMeasureRideChart() no longer re-widths the line on the ride "
                        "channels: a native click that selects the leg never widens it - "
                        "the state change has no event left to answer in (P-LM-18)")
    ink = body(tool, "void LegMeasureInk(")
    if ink is None or "LegMeasureLineWidth" not in ink:
        problems.append("LegMeasureInk() no longer wears the selection width in its own "
                        "pass: a drag on a selected leg drops the wider line mid-gesture "
                        "(P-LM-18)")
    if "LEG_LINE_W_SEL" not in tool:
        problems.append("the selected line width (LEG_LINE_W_SEL) is gone - the width "
                        "half of the selection face has no constant to wear (P-LM-18)")
    return problems


def check_leg_direction():
    """[leg-dir] - the leg's own direction answers everything that draws it (P-LM-19).

    The user (2026-09-21): «لگ نزول قرمز و لگ صعودی آبی پررنگ» and «۵۰ درصد
    دقیقا ۵۰ درصد باشه». P-LM-17 made the committed line directional; P-LM-19
    closes the three paths that were still drawing the leg in a colour it does not
    have, plus the one geometry rule the dot's centring depends on.

    Pinned here:

      * THE USER'S TWO COLOURS, and they must stay DISTINCT. An up leg is the
        STRONG BLUE `LEG_BULL_INK`, a down leg the RED `LEG_BEAR_INK`. Both are
        saturated mid-tone so the baked icons' white halo reads on white AND
        black charts. A gate that lets them converge to one colour silently
        retires the direction axis while every name still exists.
      * THE DRAG WRITES THE LEG'S OWN DIRECTION. `LegMeasureDragApply` used to
        re-ink the family through the fixed violet `LEG_INK`, so a green leg
        turned violet the moment the hand touched it and went back on release —
        and a leg dragged past horizontal kept its old colour while the geometry
        under it had flipped.
      * THE PREVIEW ANSWERS THE SAME QUESTION BEFORE THE RELEASE. The dashed
        draft wore the violet too, so the user could not see which leg he was
        drawing until it was drawn.
      * THE ATR IS THE LABELS' OWN COMPOSITE. `LegAtr14` was a plain Wilder
        iATR(14) — a second volatility ruler next to the Trex composite the
        strip, the knots and the trade-plan labels all read. The user:
        «از همون ATRهای ترکیبی که استفاده کردیم و در لیبل‌ها هست استفاده بشه
        و از چیز جدیدی استفاده نشه». The function is now a thin caller of
        `CalculateWeightedATR`, which already owns its multi-TF TTL cache, so a
        chart whose labels are current serves the readout a cached fetch.
      * THE DOT'S CENTRE IS THE DOT'S PLACEMENT. The baked rasters are 15px (ends)
        and 11px (mid) with the disc at canvas pixel 7 / 5; placing the icon at
        the GRAB radius (`LEG_HANDLE_R` 6 / `LEG_HANDLE_MID_R` 4) sat the visual
        centre one pixel past the anchor. The placement offsets
        (`LEG_HANDLE_HALF` 7 / `LEG_HANDLE_MID_HALF` 5) are the geometry; the
        grab radii are hit-test business and may not stand in for them again.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    gen = read(GENICONS)

    bull = re.search(r"(?m)^\s*#define\s+LEG_BULL_INK\s+C'(\d+),(\d+),(\d+)'", tool)
    bear = re.search(r"(?m)^\s*#define\s+LEG_BEAR_INK\s+C'(\d+),(\d+),(\d+)'", tool)
    if not bull:
        problems.append("LEG_BULL_INK is gone - the up leg has no colour of its own (P-LM-19)")
    if not bear:
        problems.append("LEG_BEAR_INK is gone - the down leg has no colour of its own (P-LM-19)")
    if bull and bear:
        br, bg, bb = (int(bull.group(i)) for i in (1, 2, 3))
        rr, rg, rb = (int(bear.group(i)) for i in (1, 2, 3))
        if (br, bg, bb) == (rr, rg, rb):
            problems.append("LEG_BULL_INK and LEG_BEAR_INK are the SAME colour: the leg meter's "
                            "direction axis is retired in everything but name (P-LM-19)")
        # the user asked for a STRONG BLUE up leg and a RED down one. A green or
        # a grey up leg is the P-LM-17 palette, which the user replaced.
        if not (bb > max(br, bg) and bb >= 120):
            problems.append("LEG_BULL_INK is no longer a strong blue: the user asked for "
                            "«آبی پررنگ» on the up leg and this is not it (P-LM-19)")
        if not (rr > max(rg, rb) and rr >= 150):
            problems.append("LEG_BEAR_INK is no longer a red: the user asked for «قرمز» on "
                            "the down leg and this is not it (P-LM-19)")

    # the drag's ink: the direction answer, read off the anchors it is writing
    drag = body(tool, "void LegMeasureDragApply(")
    if drag is None or "dragInk" not in drag or "LEG_BULL_INK" not in drag \
            or "LEG_BEAR_INK" not in drag:
        problems.append("LegMeasureDragApply() no longer re-inks the leg in its OWN "
                        "direction: a coloured leg turns violet under the hand and a leg "
                        "dragged past horizontal keeps its old colour (P-LM-19)")
    if drag is not None and "LEG_INK" in drag:
        problems.append("LegMeasureDragApply() still writes the fixed violet LEG_INK: the "
                        "drag repainted a green leg violet and put it back on release "
                        "(P-LM-19)")
    # the abort restores the SNAPSHOT, and the snapshot's own direction with it
    abort = body(tool, "void LegMeasureDragAbort(")
    if abort is None or "LEG_INK" in abort:
        problems.append("LegMeasureDragAbort() restores the snapshot in the fixed violet: a "
                        "cancelled drag leaves the leg in a colour it never had (P-LM-19)")

    # the preview: the direction the drag is heading, before the release
    prev = body(tool, "bool LegMeasureMouseMove(")
    if prev is None or "preCol" not in prev:
        problems.append("LegMeasureMouseMove() lost its preview colour: the dashed draft "
                        "has no ink to wear (P-LM-19)")
    elif "LEG_INK" in prev:
        problems.append("the draw preview still wears the fixed violet LEG_INK: the user "
                        "cannot see whether the leg he is drawing is up or down until the "
                        "release (P-LM-19)")
    elif "LEG_BULL_INK" not in prev or "LEG_BEAR_INK" not in prev:
        problems.append("the draw preview ignores the leg's direction: the dashed draft no "
                        "longer answers «سبز یا قرمز؟» — blue or red — before the "
                        "release (P-LM-19)")

    # the ATR: the labels' own composite, not a second ruler
    atr = body(tool, "double LegAtr14(")
    if atr is None:
        problems.append("LegAtr14() is gone - the readout has no ATR owner (P-LM-19)")
    else:
        if "CalculateWeightedATR" not in atr:
            problems.append("LegAtr14() no longer reads the labels' own composite "
                            "(CalculateWeightedATR): the box and the strip carry two "
                            "different ATRs for one timeframe - «از چیز جدیدی استفاده "
                            "نشده» is violated (P-LM-19)")
        if "iATR(" in atr:
            problems.append("LegAtr14() still reads a raw iATR: a second Wilder ruler next "
                            "to the composite the labels read is exactly the duplication "
                            "the user asked to retire (P-LM-19)")
        if "s_legAtr" in tool or "LEG_ATR_SLOTS" in tool:
            problems.append("the leg meter's own ATR memo table survives in front of the "
                            "composite's own TTL cache: a second cache for one number, "
                            "and the one behind it is already keyed by the bar count "
                            "(P-LM-19)")

    # the dot's placement offset is the canvas centre, not the grab radius
    for name, half, radius in (("LEG_HANDLE_HALF", 7, "LEG_HANDLE_R"),
                               ("LEG_HANDLE_MID_HALF", 5, "LEG_HANDLE_MID_R")):
        m = re.search(r"(?m)^\s*#define\s+%s\s+(\d+)" % name, tool)
        if not m:
            problems.append("%s is gone - the %s canvas has no placement offset, so the "
                            "icon's visual centre is back on the grab radius (P-LM-19)"
                            % (name, "15px" if half == 7 else "11px"))
            continue
        if int(m.group(1)) != half:
            problems.append("%s is %s but the canvas centres its disc at pixel %d: the "
                            "handle sits off its anchor (P-LM-19)" % (name, m.group(1), half))
        r = re.search(r"(?m)^\s*#define\s+%s\s+(\d+)" % radius, tool)
        if r and int(r.group(1)) == half:
            problems.append("%s has converged on %s: the grab radius is again standing in "
                            "for the placement offset, which is the off-centre bug "
                            "(P-LM-19)" % (radius, name))
    handles = body(tool, "void LegMeasureHandles(")
    if handles is None or "LEG_HANDLE_HALF" not in handles \
            or "LEG_HANDLE_MID_HALF" not in handles:
        problems.append("LegMeasureHandles() no longer places the icons at their canvas "
                        "centres: the ends and the mid dot drift off their anchors - the "
                        "«دقیقا وسط» rule (P-LM-19)")
    if handles is not None and re.search(r"MathRound\(\(\(double\)sx \+ \(double\)tx\) \* 0\.5\)",
                                         handles) is None:
        problems.append("the mid handle no longer rounds the EXACT pixel midpoint of the "
                        "two projected ends: integer division truncates toward zero and "
                        "the dot sits a pixel off the line's true 50%% (P-LM-19)")

    # the generator's palette must wear the same two colours the line wears
    upm = re.search(r"(?m)^\s*const LEG_UP_RGB\s*=\s*\[(\d+),\s*(\d+),\s*(\d+)\]", gen)
    dnm = re.search(r"(?m)^\s*const LEG_DN_RGB\s*=\s*\[(\d+),\s*(\d+),\s*(\d+)\]", gen)
    if not upm or not dnm:
        problems.append("gen-th3-icons.js lost its LEG_UP_RGB/LEG_DN_RGB pair: the baked "
                        "handles have no direction palette to bake (P-LM-19)")
    else:
        for label, m, want in (("LEG_UP_RGB", upm, (31, 95, 255)),
                               ("LEG_DN_RGB", dnm, (224, 64, 64))):
            got = tuple(int(m.group(i)) for i in (1, 2, 3))
            if got != want:
                problems.append("%s is %s, out of step with the line's ink %s: the baked "
                                "icons and the line disagree about the leg's direction "
                                "(P-LM-19)" % (label, got, want))
    return problems


def check_leg_tf():
    """[leg-tf] - the leg meter's TF badge is the course's 240-360% band (P-LM-22).

    The course (PDF pp. 74, 106): a leg IS three ATRs of its own TF. The user
    (2026-09-21): the leg's TF is the one where the leg reads 240%..360% of
    that TF's ATR, otherwise it belongs to a higher or a lower TF. The
    readout's line 1 already prints the leg as a share of H1/H4/D1, so the
    owner TF is the TF that lands in that band.

    Pinned here:

      * THE BAND IS THE USER'S TWO NUMBERS. `TH3_LEG_TF_LO` 2.40 and
        `TH3_LEG_TF_HI` 3.60. A band that drifts (or a midpoint that stops
        being 3.0) re-badges legs the course would hand to another TF.
      * THE WALK READS THE LABELS' COMPOSITE, one chain step at a time.
        `TH3LegOwnerTF` judges each TF through `LegAtr14` (the labels' own
        composite, P-LM-19 - never a raw `iATR`), and climbs/descends the
        chain with `TH3FractalStepTF`: above the band the leg belongs higher,
        below it lower.
      * A TF WITH NO HISTORY IS NOT A READING. The walk clears `trusted`
        there and stops on the last judged TF - the readout's contract (a
        guessed 1.0 is a lie the migration refuses to write) is unchanged.
      * THE READOUT ASKS THE WALK, NOT THE BAR COUNT. `LegMeasureReadout`
        names `TH3LegOwnerTF(legSize, ...)`; the closed step's bar-count gate
        (`TH3ClosedOwnerTF`, P-TH3-STEP-08/10) answers which GRID owns the
        pattern's B->C leg, and a free measurement wearing it could read D1
        on line 3 while line 1 showed 140% of H4.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))

    lo = re.search(r"(?m)^\s*#define\s+TH3_LEG_TF_LO\s+([\d.]+)", tool)
    hi = re.search(r"(?m)^\s*#define\s+TH3_LEG_TF_HI\s+([\d.]+)", tool)
    mid = re.search(r"(?m)^\s*#define\s+TH3_LEG_TF_MID\s+([\d.]+)", tool)
    if not lo or not hi:
        problems.append("TH3_LEG_TF_LO/HI is gone - the leg's TF band has no declared "
                        "numbers, so '240-360%' is a promise with no value behind it (P-LM-22)")
    elif abs(float(lo.group(1)) - 2.40) > 1e-9 or abs(float(hi.group(1)) - 3.60) > 1e-9:
        problems.append("the leg's TF band is %s-%s, not the user's 2.40-3.60: legs the "
                        "course hands to another TF are badged here (P-LM-22)"
                        % (lo.group(1), hi.group(1)))
    if mid is not None and abs(float(mid.group(1)) - 3.00) > 1e-9:
        problems.append("TH3_LEG_TF_MID is %s, not 3.00: the bracket/straddle fallback no "
                        "longer aims at the leg's own three ATRs (P-LM-22)" % mid.group(1))

    walk = body(tool, "int TH3LegOwnerTF(")
    if walk is None:
        problems.append("TH3LegOwnerTF() is gone - the readout has no size-based TF owner (P-LM-22)")
    else:
        if "LegAtr14(" not in walk:
            problems.append("TH3LegOwnerTF() no longer judges through LegAtr14(): the walk "
                            "reads a second volatility ruler next to the labels' composite "
                            "(P-LM-19/22)")
        if "iATR(" in walk:
            problems.append("TH3LegOwnerTF() reads a raw iATR: a second Wilder ruler next to "
                            "the composite the labels read (P-LM-19/22)")
        if "TH3FractalStepTF(" not in walk:
            problems.append("TH3LegOwnerTF() no longer climbs the chain with TH3FractalStepTF(): "
                            "above-the-band no longer means a higher TF (P-LM-22)")
        if "trusted = false" not in walk:
            problems.append("TH3LegOwnerTF() no longer clears trusted on a TF with no history: "
                            "a readout built on an unjudged step is printed as read (P-LM-22)")

    ro = body(tool, "void LegMeasureReadout(")
    if ro is None:
        problems.append("LegMeasureReadout() is gone (P-LM-03)")
    else:
        if "TH3LegOwnerTF(" not in ro:
            problems.append("LegMeasureReadout() no longer asks TH3LegOwnerTF(): line 3's TF "
                            "badge is not the 240-360% band (P-LM-22)")
        if "TH3ClosedOwnerTF(" in ro:
            problems.append("LegMeasureReadout() answers the bar-count gate (TH3ClosedOwnerTF) "
                            "again: a free measurement wears the closed step's grid rule, and "
                            "line 3 can contradict line 1's own columns (P-LM-22)")
    return problems


def check_leg_sel_atomic():
    """[leg-sel-atomic] - the selection is ONE drawing, assembled in ONE pass (P-LM-20).

    The user (2026-09-21): «موقع سلکت دایره‌ها بهم مریزه چرا اینا جز از یک چیز
    باید باشن و به هیچ وجه در هیچ سناریویی نباید بهم بریزن». The face was built
    from PIECES, each guarded and each correct alone: the line's width in one writer,
    the three handle rasters in another, the selection flag read by both at whatever
    moment each ran. A still click on the selectable line reports
    CHARTEVENT_OBJECT_CLICK — not a mouse move — so the flag changed BETWEEN two of
    those writers, and the family assembled itself out of state: a 3px line under
    the resting solid discs, or the selected rasters under a 2px line.

    Pinned here:

      * ONE ATOMIC REPAINT. `LegMeasureSelectionRepaint()` reads the terminal's own
        flag once and feeds the whole family through the ONE ink writer, so the
        line's width and the three discs cannot be written by two passes that
        disagreed.
      * THE TERMINAL'S OWN EVENT. `LegMeasureOnObjectClick()` answers
        CHARTEVENT_OBJECT_CLICK, which is the ONLY channel a still click on a
        selectable line reaches; a repaint that waits for the next mouse move is
        the race the user saw. A click OFF the family deselects the line, and the
        router's else-branch must answer that too.
      * THE DISCS PAINT ABOVE THE LINE. The handles carry an explicit ZORDER above
        the line's own; at the default 0 MT4 ties creation order, and the line is
        always created before its handles — so the selection's widened line painted
        OVER the discs that sit on its own ends and halved them.
      * THE SHADOW IS NOT AN AUTHORITY. `LegMeasureSelShadowMoved` only spots a
        CHANGE to answer; it must never BE the selection (the terminal owns the
        flag, and the object list, a script or a keyboard Delete can flip it
        outside any event we see). Its forget must run on the delete path, or a
        re-created leg of the same stamp inherits another leg's painted state.
    """
    problems = []
    tool = strip_comments(read(TH3TOOL))
    events = strip_comments(read(EVENTS))

    rep = body(tool, "void LegMeasureSelectionRepaint(")
    if rep is None:
        problems.append("LegMeasureSelectionRepaint() is gone - the selection has no "
                        "atomic answer, and the face is assembled from pieces again "
                        "(P-LM-20)")
    else:
        if "LegMeasureInk(" not in rep:
            problems.append("LegMeasureSelectionRepaint() does not feed the family "
                            "through the ONE ink writer: the line and the discs are "
                            "written by separate passes that can disagree about the "
                            "selection (P-LM-20)")
        if "OBJPROP_WIDTH" in rep or "LegMeasureHandles(" in rep:
            problems.append("LegMeasureSelectionRepaint() writes the width or the "
                            "handles directly instead of through LegMeasureInk: a "
                            "second writer is exactly how the face desynchronised "
                            "(P-LM-20)")

    clk = body(tool, "bool LegMeasureOnObjectClick(")
    if clk is None:
        problems.append("LegMeasureOnObjectClick() is gone - a still click on the "
                        "selectable line reports OBJECT_CLICK and nothing else, so the "
                        "selection changes between two ride passes and the discs "
                        "«به هم مریزه» (P-LM-20)")
    elif "LegMeasureSelectionRepaint(" not in clk:
        problems.append("LegMeasureOnObjectClick() does not call the atomic repaint: "
                        "the terminal names the object it selected and the answer is "
                        "still deferred to the next mouse move (P-LM-20)")
    elif "TH3_LEG_PREFIX" not in clk or "_Line" not in clk:
        problems.append("LegMeasureOnObjectClick() no longer gates on the leg's own "
                        "prefix and _Line suffix: a foreign object's click repaints a "
                        "family it does not own (P-LM-20)")

    # the router must carry OBJECT_CLICK to the handler, and answer a DESELECT too
    if "LegMeasureOnObjectClick" not in events:
        problems.append("EventHandlers does not route CHARTEVENT_OBJECT_CLICK to "
                        "LegMeasureOnObjectClick: the terminal's own selection event "
                        "never reaches the family (P-LM-20)")
    else:
        branch = stmt_body(events, "if(id == CHARTEVENT_OBJECT_CLICK)")
        if branch is None or "LegMeasureOnObjectClick" not in branch:
            problems.append("the OBJECT_CLICK branch lost its LegMeasureOnObjectClick "
                            "call: a still click selects the line and nothing answers "
                            "it (P-LM-20)")
        if branch is None or "LegMeasureRideChart" not in branch:
            problems.append("the OBJECT_CLICK branch lost its else-branch ride: a click "
                            "elsewhere DESELECTS the line, and without re-reading every "
                            "flag the family keeps the selected face on a leg the "
                            "terminal no longer has selected (P-LM-20)")

    # the discs must paint above the line. P-LM-20's rung carries its own Z_ ladder
    # name now (`Z_CHART_LEG_HANDLE`, declared right above Z_CHART_TOOL): the Z
    # ladder IS the paint order the zorder audit proves, and a rung named outside
    # it could not be placed. The rung is written, never read back - the zorder
    # audit bans OBJPROP_ZORDER reads in product code (P-UI-31's rule).
    if "Z_CHART_LEG_HANDLE" not in tool:
        problems.append("Z_CHART_LEG_HANDLE is gone - the discs have no paint order "
                        "over the line, and the widened selection line covers its own "
                        "handles (P-LM-20)")
    else:
        xy = body(tool, "void LegHandleAtXY(")
        if xy is None or "OBJPROP_ZORDER" not in xy:
            problems.append("LegHandleAtXY() never writes the handle ZORDER: the discs "
                            "stay at the default 0 and the line paints over them at "
                            "every width (P-LM-20)")
        if xy is None or xy.count("Z_CHART_LEG_HANDLE") < 2:
            problems.append("LegHandleAtXY() sets the ZORDER only at CREATE: a leg the "
                            "pre-ZORDER build drew keeps its default 0 forever, and the "
                            "migration is the only pass that reaches it (P-LM-20)")
        if xy is not None and "ObjectGetInteger(0, hn, OBJPROP_ZORDER)" in xy:
            problems.append("the handle's rung is read back before it is written - a "
                            "z-order read is a diagnostic, and the zorder audit bans "
                            "it in product code (P-UI-31 / P-LM-20)")

    # the shadow must stay a shadow
    sh = body(tool, "bool LegMeasureSelShadowMoved(")
    if sh is None:
        problems.append("LegMeasureSelShadowMoved() is gone - the ride pass has no way "
                        "to spot a selection change, so it re-paints nothing and the "
                        "face rides stale until the next chart event (P-LM-20)")
    elif "ObjectGetInteger" in sh or "OBJPROP_SELECTED" in sh or "LegMeasureSelected(" in sh:
        problems.append("LegMeasureSelShadowMoved() reads the terminal's selection "
                        "itself: it is a SHADOW of the painted state, never an "
                        "authority — the object list or a script can flip the flag "
                        "outside any event we see (P-LM-20)")
    forg = body(tool, "void LegMeasureSelShadowForget(")
    if forg is None:
        problems.append("LegMeasureSelShadowForget() is gone - a deleted measurement's "
                        "painted state outlives it, and a re-created leg of the same "
                        "stamp inherits it (P-LM-20)")
    dele = body(tool, "void LegMeasureDelete(")
    if dele is None or "LegMeasureSelShadowForget" not in dele:
        problems.append("LegMeasureDelete() does not forget the selection shadow: the "
                        "shadow outlives the family and the next leg of that stamp "
                        "starts in a state it never earned (P-LM-20)")
    ride = body(tool, "void LegMeasureRideChart(")
    if ride is None or "LegMeasureSelShadowMoved" not in ride:
        problems.append("LegMeasureRideChart() does not spot selection changes: a "
                        "selection that arrives by any other path (the object list, a "
                        "script) is never answered, and the face waits on the chart "
                        "to move (P-LM-20)")
    return problems


def check_bk_info_rungs():
    """[bk-info] - the Base Box INFO row's THREE rungs, on every surface (P-BK-58).

    P-BK-58 (2026-09-16, user: «لیبل اطلاعات بیس را کنار همان کارت/ردیف خانوادهٔ لیبلها
    هم نشان بده تا کاربر بتواند بین «چسبیده به باکس» و «گوشهٔ ثابت» یکی را انتخاب کند»):
    the note's HOME became a user setting, so the SAME number is now written by four
    surfaces and read by one probe:

      * the row's own def (`BkSecRowDef`, sec 4) offers the third option;
      * BOTH card mirrors (card 12's Setup tab and the MINI strip, card 13 row 2) clamp
        it to the same bound - a strip that clamps 0..1 silently eats the new rung;
      * the settings layer clamps it on INIT (the input is a raw int) and on RESTORE
        (a chart saved before the rung must not come back as something else);
      * `BK_NOTE_CHART` (BaseKnotTool) is the LAST rung the row offers, because that
        is the value the module compares against - a row that grew a fourth option
        without moving it would make the corner unreachable.
    NOTE: the row's own VALUE layer is delegated to `BkSecCurrent`/`BkSecApply`, so the
    generic [values] walk above is not the place for this: the two mirrors are.
    """
    problems = []
    panels = read(PANELS)
    settings = read(SETTINGS)
    knot = read(BASEKNOT)
    rung = re.search(r"(?m)^\s*#define\s+BK_NOTE_CHART\s+(\d+)", strip_comments(knot))
    if not rung:
        return ["BK_NOTE_CHART is gone - the corner rung has no address (P-BK-58)"]
    top = int(rung.group(1))

    sec = body(panels, "BkSecRowDef(") or ""
    m = re.search(r'sec\s*==\s*4\s*\)\s*\{\s*kind\s*=\s*2;\s*label\s*=\s*"INFO";\s*'
                  r'opts\s*=\s*"([^"]*)";\s*minV\s*=\s*(\d+);\s*maxV\s*=\s*(\d+);', sec)
    if not m:
        problems.append("the Base Box Setup INFO row is gone or was reshaped - the note's "
                        "home is not reachable from the card (P-BK-58)")
    else:
        opts, lo, hi = m.group(1).split("|"), int(m.group(2)), int(m.group(3))
        if hi != top:
            problems.append("the INFO row offers 0..%d while BK_NOTE_CHART is %d: the "
                            "corner is unreachable (P-BK-58)" % (hi, top))
        if lo != 0:
            problems.append("the INFO row's floor is %d, not 0: Auto is unreachable" % lo)
        if len(opts) != top + 1:
            problems.append("the INFO row names %d option(s) (%s) for %d rung(s) - a rung "
                            "with no name (P-BK-58)"
                            % (len(opts), "|".join(opts), top + 1))
        if not opts or opts[0].strip() != "Auto":
            problems.append("the INFO row's first rung is `%s`, not Auto: the shipped "
                            "behaviour moved" % (opts[0] if opts else ""))

    # both card mirrors write the SAME state with the SAME bound
    for what, pat in (("the Setup tab", r"sec\s*==\s*4\)\s*\{\s*g_bkShowInfo\s*=\s*ClampInt\("
                                     r"\(int\)MathRound\(v\),\s*0,\s*(\d+)\)"),
                      ("the MINI strip", r"row\s*==\s*2\)\s*\{\s*g_bkShowInfo\s*=\s*ClampInt\("
                                        r"\(int\)MathRound\(v\),\s*0,\s*(\d+)\)")):
        hit = re.search(pat, panels)
        if not hit:
            problems.append("%s no longer writes g_bkShowInfo - a surface that stopped "
                            "mirroring the row (P-BK-58)" % what)
        elif int(hit.group(1)) != top:
            problems.append("%s clamps the note's home to 0..%s while the rung is %d: the "
                            "corner is eaten there (P-BK-58)" % (what, hit.group(1), top))

    # ... and the settings layer, on init AND on restore
    for what, pat in (("init", r"g_bkShowInfo\s*=\s*ClampSettingInt\(inpBKShowInfo,\s*0,\s*(\d+)\)"),
                      ("restore", r"g_bkShowInfo\s*=\s*ClampSettingInt\(\(int\)GlobalVariableGet\([^)]*\)"
                                  r",\s*0,\s*(\d+)\)")):
        hit = re.search(pat, settings)
        if not hit:
            problems.append("the settings layer no longer clamps the note's home on %s "
                            "- a raw input or an old chart can land outside the rungs "
                            "(P-BK-58)" % what)
        elif int(hit.group(1)) != top:
            problems.append("the settings layer clamps to 0..%s on %s while the rung is "
                            "%d (P-BK-58)" % (hit.group(1), what, top))

    # the MINI strip's own def must offer the same list (a strip that shows only two
    # captions cannot be scrolled to the third rung on that surface)
    # The MINI strip's own def (card 13 lives in the same row-def writer) must offer the same
    # list: a strip whose captions stop at two cannot be scrolled to the third rung there.
    mini = body(panels, "void PnlSetDef(") or ""
    mm = re.search(r'row\s*==\s*2\s*\)\s*\{\s*kind\s*=\s*2;\s*label\s*=\s*"INFO";\s*'
                   r'opts\s*=\s*"([^"]*)";\s*minV\s*=\s*\d+;\s*maxV\s*=\s*(\d+);', mini)
    if mm is None:
        problems.append("the MINI strip's INFO row is gone or was reshaped (P-BK-58)")
    else:
        if mm.group(1).split("|") != (opts if m else []):
            problems.append("the MINI strip names `%s` where the card names `%s`: two "
                            "captions for one setting (P-BK-58)"
                            % (mm.group(1), "|".join(opts) if m else ""))
        if int(mm.group(2)) != top:
            problems.append("the MINI strip offers 0..%s while the rung is %d (P-BK-58)"
                            % (mm.group(2), top))
    return problems


def check_rows():
    """[spec]/[def]/[values] - a row nobody can read, or an address nobody wrote."""
    problems = []
    text = read(PANELS)
    spec = parse_spec(text)
    if not spec:
        return ["PnlSpecBuild() is gone - no card declares any row"]
    # SR-PANELWIRE-2a: look the layer up by NAME, never by return type. The
    # value layer's returns are double/double/int - a `void ` prefix in the
    # signature made this gate report all three layers "missing" for a while,
    # which is exactly the kind of vacuous pass a gate must never hand out.
    specblk = body(text, "PnlSpecBuild(") or ""
    retired = retired_addresses(specblk)
    delegated_to = delegation_targets(text)
    defblk = body(text, "PnlSetDef(")
    val = body(text, "PnlDefValSet(")
    cur = body(text, "PnlCurrentSet(")
    app = body(text, "PnlApplySet(")
    for name, fn in (("PnlSetDef", defblk), ("PnlDefValSet", val),
                     ("PnlCurrentSet", cur), ("PnlApplySet", app)):
        if fn is None:
            problems.append("%s() is gone - a card layer is missing" % name)
    if problems:
        return problems
    for item in sorted(spec):
        rows = spec[item]
        arm = item_block(text, "PnlSetDef(", item)
        if arm is None:
            problems.append("card %d has no PnlSetDef block" % item)
            continue
        # the card's own address space = every setting the spec names
        addrs = set()
        for kind, s0, n in rows:
            if s0 < 0:
                continue
            addrs.update(range(s0, s0 + max(1, n)))
        top = max(addrs) if addrs else -1
        # SR-PANELWIRE-2c: a card that hands its rows to a helper
        # (`BkSecRowDef(row-1, ...)`) answers through that helper, so asking the
        # card itself for a branch per row is the wrong question. The tabbed
        # Base Box card is the only one like this.
        delegated = bool(re.search(r"\w+\s*\(\s*row\s*[-+]", strip_comments(arm)))
        dval, _ = rows_spoken(item_block(text, "PnlDefValSet(", item))
        cval, _ = rows_spoken(item_block(text, "PnlCurrentSet(", item))
        aval, aelse = rows_spoken(item_block(text, "PnlApplySet(", item))
        if dval is None or cval is None or aval is None:
            problems.append("card %d is missing a value-layer arm" % item)
            continue
        # kind per SETTING row, read from the def itself
        krows = def_row_kinds(arm, top)
        dcov = covered_rows(dval, False, top)
        ccov = covered_rows(cval, False, top)
        acov = covered_rows(aval, aelse, top)
        if not delegated:
            for a in sorted(addrs):
                kind = krows.get(a, 0)
                if kind not in VALUE_KINDS:
                    continue     # colour (palette-only) / NAV / section: no value
                if a not in dcov:
                    problems.append("card %d setting %d has no PnlDefValSet branch "
                                    "(Reset cannot restore it)" % (item, a))
                if a not in ccov:
                    problems.append("card %d setting %d has no PnlCurrentSet branch "
                                    "(the control shows nothing)" % (item, a))
                if a not in acov:
                    problems.append("card %d setting %d has no PnlApplySet branch "
                                    "(moving it changes nothing)" % (item, a))
            # THE REVERSE DIRECTION (the original P-UI-70c): a branch the value
            # layer answers for an address NO row renders is a setting the user
            # can never reach - the row was retired and the address was not.
            for spoken, layer in ((dval, "PnlDefValSet"), (cval, "PnlCurrentSet"),
                                  (aval, "PnlApplySet")):
                for a in sorted(spoken):
                    if a in addrs or a == top:
                        continue
                    if (item, a) in retired or (item, a) in delegated_to:
                        continue     # documented dead, or reached by another card
                    problems.append("card %d %s answers setting %d but no row "
                                    "renders it - and nothing documents it as "
                                    "retired or delegates to it (a P-UI-47 dead "
                                    "control)" % (item, layer, a))
        # kind sanity, on the spec rows themselves
        for kind, s0, n in rows:
            if kind == "PNL_K_SEC":
                continue
            if kind == "PNL_K_LEGACY":
                if not delegated and s0 not in krows and s0 != top:
                    problems.append("card %d row %d is LEGACY with no PnlSetDef "
                                    "branch (no caption, no kind)" % (item, s0))
                continue
            if kind not in KINDS:
                problems.append("card %d row %d has an unknown kind %s" % (item, s0, kind))
                continue
            if n > 1 and kind not in ("PNL_K_CSET", "PNL_K_DUAL"):
                problems.append("card %d row %d claims %d members as a %s row"
                                % (item, s0, n, kind))
    return problems


def saved_vars():
    """Every runtime setting the project persists, across BOTH mechanisms.

    SR-PANELWIRE-3c: the project saves settings two ways - `RSSetNext(name, g_x)`
    in RuntimeSettings.mqh (the newer override table) and `GlobalVariableSet(name,
    g_x)` inside the feature's own module (HTF candles, the trigger/ATR mirrors).
    Reading only the first made this gate claim that settings which ARE persisted
    (g_HTFBorderWidth, g_atrLabelsVisible) died with the session - a false alarm
    that would have taught the next reader to ignore the gate.
    """
    out = set()
    for name in sorted(os.listdir(os.path.join(ROOT, "Biotak"))):
        if not name.endswith(".mqh"):
            continue
        src = read(os.path.join(ROOT, "Biotak", name))
        src = strip_comments(src)
        # the value may carry a cast: GlobalVariableSet(name, (double)g_x)
        out.update(re.findall(r"RSSetNext\s*\([^,]+,\s*(?:\([^)]*\)\s*)?(g_\w+)", src))
        out.update(re.findall(
            r"GlobalVariableSet\s*\([^,]+,\s*(?:\([^)]*\)\s*)?(g_\w+)", src))
    return out


#--- vars that are pure repaint/UI state (a repaint contract, not a setting) - a
#--- value the engine must re-derive, so persisting it would be wrong.
TRANSIENT = ("g_redraw", "g_forceClear", "g_labelsRelayout", "g_Pnl", "g_UI",
             "g_need", "g_dirty")


def check_persist():
    """[persist] - a control whose setting dies with the session.

    A var is exempt when nothing outside the panel reads it: that is panel UI
    state (the open Base Box tab), not a setting, and MT4 has no business
    restoring it. Everything the ENGINE reads must be saved by one of the two
    mechanisms above.
    """
    problems = []
    text = read(PANELS)
    settings = read(SETTINGS)
    saved = saved_vars()
    if not saved:
        return ["no module persists any setting - the gate cannot read the project"]
    others = ""
    for name in sorted(os.listdir(os.path.join(ROOT, "Biotak"))):
        if name.endswith(".mqh") and name != "BiotakPanels.mqh":
            others += read(os.path.join(ROOT, "Biotak", name))
    spec = parse_spec(text) or {}
    for item in sorted(spec):
        blk = item_block(text, "PnlApplySet(", item)
        if blk is None:
            continue
        for var in sorted(settings_written(blk)):
            if any(var.startswith(p) for p in TRANSIENT):
                continue
            if var in saved:
                continue
            if not re.search(r"\b%s\b" % re.escape(var), others):
                continue     # panel-local UI state: the engine never sees it
            problems.append("card %d writes %s from a panel row but nothing "
                            "persists it (the change dies with the session)"
                            % (item, var))
    return problems


def colour_rows(text):
    """(item, row) -> PAL_* from PnlColorKindSet, with the site that names it.

    SR-PANELWIRE-3b: the factory default is ROW-keyed (`PnlDefColorSet(item,row)`),
    not kind-keyed, so "does this kind have a default" is not a question the
    source can answer - the answerable question is "does every ROW that can name
    a kind have a default branch", which is what the palette's Reset needs.
    """
    blk = body(text, "PnlColorKindSet(")
    if blk is None:
        return None
    out = {}
    for line in blk.splitlines():
        body_l = strip_comments(line)
        mi = re.search(r"item\s*==\s*(\d+)", body_l)
        mr = re.search(r"row\s*==\s*(\d+)", body_l)
        mlo = re.search(r"row\s*>=\s*(\d+)", body_l)
        mhi = re.search(r"row\s*<=\s*(\d+)", body_l)
        mk = re.search(r"return\s+(PAL_\w+)", body_l)
        if mi is None or mk is None:
            continue
        item = int(mi.group(1))
        rows = []
        if mr is not None:
            rows = [int(mr.group(1))]
        elif mlo is not None and mhi is not None:
            rows = list(range(int(mlo.group(1)), int(mhi.group(1)) + 1))
        for r in rows:
            out[(item, r)] = mk.group(1)
    return out


def check_palette():
    """[palette] - a colour row the palette cannot name, paint or reset."""
    problems = []
    text = read(PANELS)
    kit = read(KIT)
    kinds = colour_kinds(text)
    if kinds is None:
        return ["PnlColorKindSet() is gone - no panel colour row is wired"]
    # 1. the target table must be exactly as long as the kind count
    base = re.search(r"#define\s+PAL_BASE_TARGETS\s+(\d+)", kit)
    names = body(text, "PalTgtLabel(")
    if base is None or names is None:
        return ["PAL_BASE_TARGETS and/or PalTgtLabel() are gone"]
    n_names = len(re.findall(r'"[^"]*"', names))
    if n_names != int(base.group(1)):
        problems.append("PalTgtLabel() has %d names for PAL_BASE_TARGETS %s - the "
                        "'apply to' cycler can land on a kind it cannot name"
                        % (n_names, base.group(1)))
    # 2. every kind must be painted and applied - and the two must name the
    # SAME runtime copy. `case PAL_X: return g_rowColor;` next to
    # `case PAL_X: return g_trColor;` compiles, renders and lies: the swatch
    # shows one setting and the press writes another.
    reads, writes = {}, {}
    for fn, store, label in (("PaletteKindColor", reads, "paints"),
                             ("PaletteApplyColor", writes, "applies")):
        blk = body(text, "%s(" % fn)
        if blk is None:
            problems.append("%s() is gone" % fn)
            continue
        for k in sorted(kinds):
            if not re.search(r"\b%s\b" % k, blk):
                problems.append("%s() does not handle %s (%s)" % (fn, k, label))
        for m in re.finditer(r"case\s+(PAL_\w+)\s*:\s*"
                             r"(?:return\s+(g_\w+)|(g_\w+)\s*=)",
                             strip_comments(blk)):
            store[m.group(1)] = m.group(2) or m.group(3)
    seen = {}
    for k, var in sorted(reads.items()):
        if var in seen:
            problems.append("PaletteKindColor() paints %s and %s with the same "
                            "copy %s - one of them cannot be set"
                            % (seen[var], k, var))
        seen[var] = k
        if k in writes and writes[k] != var:
            problems.append("%s is shown from %s but written to %s (the swatch and "
                            "the press disagree)" % (k, var, writes[k]))
    # 3. every ROW that names a kind must have a factory default (Reset path)
    rows = colour_rows(text)
    defs = body(text, "PnlDefColorSet(")
    if rows is None or defs is None:
        problems.append("the colour-row map or PnlDefColorSet() is gone")
    else:
        covered = set()
        for line in strip_comments(defs).splitlines():
            mi = re.search(r"item\s*==\s*(\d+)", line)
            if mi is None:
                continue
            item = int(mi.group(1))
            mr = re.search(r"row\s*==\s*(\d+)", line)
            mlo = re.search(r"row\s*>=\s*(\d+)", line)
            mhi = re.search(r"row\s*<=\s*(\d+)", line)
            if mr is not None:
                covered.add((item, int(mr.group(1))))
            elif mlo is not None and mhi is not None:
                for r in range(int(mlo.group(1)), int(mhi.group(1)) + 1):
                    covered.add((item, r))
        for (item, row), kind in sorted(rows.items()):
            if (item, row) not in covered:
                problems.append("row (card %d, %d) targets %s but PnlDefColorSet() has "
                                "no default for it (Reset leaves the old colour)"
                                % (item, row, kind))
    # 4. the kinds must be DECLARED in the kit, in the target range
    for k in sorted(kinds):
        m = re.search(r"#define\s+%s\s+(\d+)" % k, kit)
        if m is None:
            problems.append("%s is used by the panel but not declared in BiotakKit"
                            % k)
        elif int(m.group(1)) >= int(base.group(1)):
            problems.append("%s = %s is outside 0..PAL_BASE_TARGETS-1" % (k, m.group(1)))
    return problems


def check_trex_card():
    """[trex] - the user's own request: the TRex card must be personalisable
    FROM THE PANEL, and PIP LABELS must say what it is.

    P-UI-70d: «تنظیمات شخصی سازی این trex sl , tp ها چرا در پنل نیستش و اون pip
    lable چیه اصلا لازم نیستش». The card's size / gap / margin / colours and the
    H/L PIP LABELS caption are what the user asked for by name, so they are
    pinned here rather than left to a later rename to quietly undo.
    """
    problems = []
    text = read(PANELS)
    blk = body(text, "PnlSetDef(")
    if blk is None:
        return ["PnlSetDef() is gone"]
    arm = item_block(text, "PnlSetDef(", 2)
    if arm is None:
        return ["card 2 (ATR LABELS) has no def block"]
    arm_rows = def_row_arms(arm, 18)     # card 2's last row is SPREAD COLOR
    caps = {row: m.group(1) for row, m in
            ((r, re.search(r'label\s*=\s*"([^"]*)"', a)) for r, a in arm_rows)
            if m is not None}
    for row, want in ((10, "ROW GAP"), (11, "TRADE SIZE"), (12, "STAMP GAP"),
                      (13, "CARD MARGIN"), (14, "TR COLOR"), (15, "EX COLOR"),
                      (16, "HUNTER COLOR"), (17, "TRADE COLOR"),
                      (18, "SPREAD COLOR")):
        if caps.get(row) != want:
            problems.append("card 2 row %d should be %r so the TRex card is "
                            "personalisable from the panel; found %r"
                            % (row, want, caps.get(row)))
    if caps.get(9) != "H/L PIP LABELS":
        problems.append("card 2 row 9 must be marked 'H/L PIP LABELS' - it toggles "
                        "the pip-distance labels on the High/Low lines; found %r"
                        % caps.get(9))
    # the two new rows must move a setting the CARD actually reads
    labels_blk = read(os.path.join(ROOT, "Biotak", "LabelFunctions.mqh"))
    settings = read(SETTINGS)
    # the panel writes the runtime copy; LabelFunctions reads it through the
    # settings layer's redirect macro, so THAT is the name to look for.
    for var in ("inpATRTradeLabelFontSize", "inpTrexStampGapRows",
                "inpLabelsMarginBottom", "inpATRTradeRowColor"):
        if not re.search(r"\b%s\b" % var, labels_blk):
            problems.append("the panel writes %s but the chart never reads it (a "
                            "control that moves nothing)" % var)
        macro = re.search(r"#define\s+%s\s+(g_\w+)" % var, settings)
        if macro is None:
            problems.append("the settings layer no longer redirects %s to its "
                            "runtime copy (the panel row and the chart would "
                            "drift apart)" % var)
    return problems


def row_arms(blk):
    """Every `if(row==N) { ... }` arm of a legacy def, in source order.

    The arm ends at the next `else if(row==`/`else`/closing brace, so each arm's
    text is the arm's own - which is what a per-row invariant needs.
    """
    out = []
    for m in re.finditer(r"if\(\s*row\s*==\s*(\d+)\s*\)", blk):
        start = m.end()
        nxt = re.search(r"\n\s*(?:else\s+)?if\(\s*row\s*==|\n\s*else\b", blk[start:])
        stop = start + (nxt.start() if nxt else 600)
        out.append((int(m.group(1)), blk[start:stop]))
    return out


def check_captions():
    """[caption] - a control whose caption names nothing the user can act on."""
    problems = []
    text = read(PANELS)
    blk = body(text, "PnlSetDef(")
    if blk is None:
        return ["PnlSetDef() is gone"]
    # SR-PANELWIRE-4a: only ROW ARMS are captions. The two `kind=0; label="";`
    # prologues are the out-parameter reset every caller relies on, and a
    # section band intentionally carries a computed title - neither is a
    # caption, and treating them as one made this gate cry wolf twice.
    for row, arm in def_row_arms(blk, None):
        m = re.search(r'label\s*=\s*"([^"]*)"', arm)
        if m is None:
            # the arm assigns no literal: either it sets the label from a macro
            # (fine) or it sets nothing at all (a control that renders blank).
            if not re.search(r'label\s*=\s*[^;"\s]', arm):
                problems.append("row %d declares no caption at all - the control "
                                "renders blank" % row)
            continue
        cap = m.group(1)
        if cap == "":
            problems.append("row %d has an empty caption" % row)
        # MT4's default font has no non-ASCII glyphs (the P-LBL-02 lesson): a
        # caption in another script renders as ???????
        elif any(ord(ch) > 126 for ch in cap):
            problems.append("row %d caption %r is not ASCII: it renders as ???? "
                            "in the indicator's own font" % (row, cap))
    return problems


def label_vars():
    """Runtime copies LabelFunctions actually reads (through the redirect).

    Those are the settings whose value only becomes visible when the LABEL PASS
    runs again, i.e. the ones a panel row must follow with a relayout request.
    """
    settings = read(SETTINGS)
    labels_blk = read(os.path.join(ROOT, "Biotak", "LabelFunctions.mqh"))
    out = set()
    for m in re.finditer(r"#define\s+(inp\w+)\s+(g_\w+)", settings):
        if re.search(r"\b%s\b" % re.escape(m.group(1)), labels_blk):
            out.add(m.group(2))
    return out


def check_relayout():
    """[relayout] - a row that moves what the labels draw but never asks for a
    label relayout.

    P-UI-70d's own trap: the label card's geometry is read by the LABEL PASS, so
    a value the panel stores without `g_labelsRelayoutNeeded` is accepted, the
    chip repaints, and the chart does not move until an unrelated repaint - the
    user's «این کار نمیکنه» about a row that half-works.
    """
    problems = []
    text = read(PANELS)
    lvars = label_vars()
    if not lvars:
        return ["the settings layer no longer redirects anything LabelFunctions "
                "reads - the relayout contract cannot be checked"]
    spec = parse_spec(text) or {}
    for item in sorted(spec):
        arm = item_block(text, "PnlApplySet(", item)
        if arm is None:
            continue
        top = max([s0 + max(1, n) - 1 for _, s0, n in spec[item] if s0 >= 0] or [-1])
        for row, a in def_row_arms(arm, top):
            if not any(re.search(r"\b%s\s*=" % re.escape(v), a) for v in lvars):
                continue
            if "g_labelsRelayoutNeeded" in a:
                continue
            problems.append("card %d setting %d writes a setting the LABEL pass "
                            "reads but never asks for a relayout (the number "
                            "changes and the chart does not)" % (item, row))
    return problems


def check_purge():
    """[purge] - the card teardown must delete what the drawers make.

    P-UI-71: the hand list was bounded by `PNL_CARD_ROWS_MAX`, a ceiling that
    fell BELOW the real row count (card 2 = 19 rows, BASE BOX = 24, the ceiling
    said 16), so those rows' objects survived every rebuild. And a row's object
    name carries its DISPLAY INDEX, which a section collapse renumbers - so the
    old family survived under the old index while the live row drew under the
    new one, leaving TWO copies of the same row on the chart. The stale copy is
    in nobody's hit list, which is the user's "I click it and nothing happens".

    The wipe is a PREFIX now, so it cannot drift from `PnlName`. What this check
    has to prove is that the two still share one spelling.
    """
    problems = []
    text = read(PANELS)
    blk = body(text, "PnlName(")
    if blk is None:
        return ["PnlName() is gone - the row naming owner cannot be checked"]
    m = re.search(r'return\s+([^;]+);', blk)
    if m is None:
        return ["PnlName() no longer returns a name"]
    naming = re.sub(r"\s+", "", m.group(1))
    # the ROW prefix is everything up to and including the first `+ "_"`
    cut = naming.find('+"_"')
    if cut < 0:
        problems.append("PnlName() no longer separates the row with `_` (%s) - "
                        "every purge prefix below is written against that shape"
                        % naming[:60])
        row_pair = None
    else:
        row_pair = naming[:cut + 4]
    dblk = body(text, "PnlDestroy(")
    if dblk is None:
        return problems + ["PnlDestroy() is gone - a card can never be torn down"]
    # P-PERF-47: ONE prefix wipe, and it must cover EVERY subwindow.
    #
    # The hand list this replaced was bounded TWICE - by PNL_CARD_ROWS_MAX (a row
    # ceiling the cards outgrow) and by a window argument of 0 - and both bounds
    # dropped rows silently, which is the P-UI-71 report. The teardown is now a
    # single `ObjectsDeleteAll(0, head, -1, -1)`; what this check has to keep
    # honest is the shape of it: ONE scan, all windows. The old form (window 0)
    # is caught by name because it is what a "small tidy-up" reintroduces.
    if not re.search(r'ObjectsDeleteAll\(\s*0\s*,\s*head\s*,\s*-1\s*,\s*-1\s*\)', dblk):
        problems.append("PnlDestroy() no longer wipes the card's whole prefix in one "
                        "pass - an index-bounded hand list cannot cover a card whose "
                        "rows grew, and every row it misses stays on the chart")
    elif re.search(r'ObjectsDeleteAll\(\s*0\s*,\s*head\s*,\s*0\s*,', dblk):
        problems.append("PnlDestroy()'s wipe is bounded to the main subwindow again - "
                        "an object parked in another window survives the teardown")
    wipe = None
    m = re.search(r'string\s+head\s*=\s*([^;]+);', dblk)
    if m is None:
        problems.append("PnlDestroy() no longer derives `head`")
    else:
        wipe = re.sub(r"\s+", "", m.group(1))
        # SR-PANELWIRE-5: the two prefixes must be the SAME EXPRESSION, not
        # merely both containing a `_`. A naming change that only drops one
        # separator still leaves a wipe that matches nothing - every ghost row
        # of P-UI-71 returns, invisibly, with the gate still green.
        if row_pair is None or wipe != row_pair:
            problems.append("PnlDestroy()'s wipe prefix (%s) is not the prefix "
                            "PnlName() builds (%s) - the wipe would silently stop "
                            "matching every row object"
                            % (wipe[:50], (row_pair or "?")[:50]))
    # a leftover index loop means somebody re-introduced a ceiling
    if re.search(r'for\s*\(\s*int\s+\w+\s*=\s*0\s*;\s*\w+\s*<\s*PNL_CARD_ROWS_MAX', dblk):
        problems.append("PnlDestroy() still carries a PNL_CARD_ROWS_MAX index loop - "
                        "that ceiling is a row count the cards outgrow (P-UI-71)")
    # P-PERF-47 deleted the SECOND scan (`head + "card"`) and the ~33 hand
    # probes as strict subsets of the one above. That claim is only safe while
    # the card body is named out of the very same prefix: `PnlHead(item,"card")`
    # must be literally `head` + the kind. Check the composition rather than the
    # deleted call, so the wipe cannot drift away from the body it must cover
    # (a card that shrinks would otherwise leave its own tiles behind).
    hblk = body(text, "PnlHead(")
    if hblk is None:
        problems.append("PnlHead() is gone - the composed card body has no naming owner")
    else:
        hm = re.search(r'return\s+([^;]+);', hblk)
        head_naming = re.sub(r"\s+", "", hm.group(1)) if hm else ""
        want = (wipe + "+kind") if wipe else "?"
        if wipe is None or head_naming != want:
            problems.append("PnlHead() no longer builds every card object out of the "
                            "wipe's own prefix (%s is not %s) - the ONE wipe would stop "
                            "covering the composed card body" % (head_naming[:60], want[:60]))
    return problems


def card_specs(text):
    """Per card: [kind, s0, n] entries in source order, comments stripped."""
    blk = body(text, "PnlSpecBuild(")
    if blk is None:
        return None
    blk = strip_comments(blk)
    out = {}
    for m in re.finditer(r"PnlSpecAdd\(\s*(\d+)\s*,\s*(PNL_K_\w+)\s*,\s*(-?\d+)\s*,\s*(\d+)",
                         blk):
        out.setdefault(int(m.group(1)), []).append(
            (m.group(2), int(m.group(3)), int(m.group(4))))
    return out


def card_lines(spec, item):
    """The pair-line each display row lands on, mirroring PnlRowLine."""
    wide = len(spec) > 10          # PNL_WIDE_MIN_ROWS
    if not wide:
        return list(range(len(spec)))
    lines, ln, col = [], 0, 0
    for i, (kind, s0, n) in enumerate(spec):
        full = (kind == "PNL_K_SEC") or (item in (9, 12) and i == 0)
        slot = ln + (1 if (full and col == 1) else 0)
        lines.append(slot)
        if full:
            ln, col = slot + 1, 0
        else:
            if col == 1:
                ln += 1
            col = 1 - col
    return lines


def compiled_unit(entry):
    """Every file `entry` really compiles, following `#include` transitively.

    The walk is the include GRAPH, not the directory: `Biotak/TH3/*` (retired)
    and `Biotak/Tests/*` are on disk and deliberately NOT compiled, so a
    directory scan would demand declarations for code that does not exist in the
    built indicator.
    """
    unit, stack = set(), [entry]
    while stack:
        p = stack.pop()
        if p in unit or not os.path.exists(p):
            continue
        unit.add(p)
        for m in re.finditer(r'^\s*#include\s+"([^"]+)"', read(p), re.M):
            rel = m.group(1).replace("\\", os.sep)
            stack.append(os.path.normpath(os.path.join(os.path.dirname(p), rel)))
    return unit


def check_chrome():
    """[chrome] - P-UI-71c: a bitmap the runtime can load must be DECLARED.

    MetaEditor embeds a bitmap only where a literal `#resource` names it, and an
    OBJPROP_BMPFILE string that resolves to nothing fails SILENTLY at runtime: the
    object is created, the load does nothing, and the surface renders as bare
    labels or as no card at all. The compiled build stays green and the compile
    log says nothing — which is how the wide cards' COMPOSED body (top cap + one
    band per pair-line + footer cap + `.fade` wash, sliced by
    tools/slice-card-skins.py) shipped with all four pieces referenced and none
    declared: the user's whole Trade Plan card drew as loose widgets on the chart
    ("پشت پس زمینه نداره").

    So the rule is mechanical and total: for every `::Files\\Icons\\<name>`
    string in the compiled unit, the name (or, for a CONCATENATED reference, every
    existing bitmap sharing its literal prefix) must have a `#resource` line, and
    an exact name must exist on disk. This is the class gate; `[body]` above only
    ever checked the arithmetic.
    """
    problems = []
    unit = compiled_unit(ENTRY)
    declared, refs = {}, []
    res_re = re.compile(r'#resource\s+"[^"]*?Files[\\/]+Icons[\\/]+([^"\\/]+)"')
    ref_re = re.compile(r'::Files[\\/]+Icons[\\/]+([^"\\/]+)')
    for path in sorted(unit):
        txt = read(path)
        for m in res_re.finditer(txt):
            declared.setdefault(m.group(1), os.path.basename(path))
        # a runtime reference may be built by concatenation (`"...\\pnl_card" +
        # n + ".bmp"`), so the literal is a PREFIX and every bitmap that starts
        # with it is a candidate the terminal can actually be asked to load.
        for m in ref_re.finditer(strip_comments(txt)):
            refs.append((m.group(1), os.path.basename(path),
                         strip_comments(txt).count("\n", 0, m.start()) + 1))
    if not declared:
        return ["no #resource declaration was found anywhere - the gate cannot "
                "see the embedded bitmap set"]
    if not refs:
        return ["no runtime `::Files\\\\Icons\\\\*.bmp` reference was found - the "
                "gate would be vacuous"]
    on_disk = [n for n in os.listdir(ICONS) if n.lower().endswith(".bmp")] if os.path.isdir(ICONS) else []
    seen = set()
    for frag, src, ln in refs:
        if frag.lower().endswith(".bmp"):
            if not os.path.exists(os.path.join(ICONS, frag)):
                problems.append("%s:%d references `%s`, which does not exist in "
                                "Files/Icons - MT4 draws NOTHING for it" % (src, ln, frag))
            names = [frag]
        else:
            names = [n for n in on_disk if n.startswith(frag)]
            if not names:
                problems.append("%s:%d builds a bitmap name from the prefix `%s` "
                                "and no such file exists in Files/Icons" % (src, ln, frag))
        for n in names:
            if n in declared or (n, src, ln) in seen:
                continue
            seen.add((n, src, ln))
            problems.append("%s:%d loads `%s` at runtime but NO `#resource` line "
                            "declares it: MetaEditor does not embed it, the load "
                            "fails silently and the surface draws with no chrome "
                            "(P-UI-71c). Add `#resource \"\\\\Files\\\\Icons\\\\%s\"` "
                            "(tools/add-panel-resources.py does it for the panel set)"
                            % (src, ln, n, n))
    return problems


def check_bk_drag():
    """[bk-drag] - P-BK-18: the fill and the border must track in lockstep.

    A Base/Knot box is TWO families by design: the OBJ_RECTANGLE that carries the
    fill AND the only native drag handle MT4 will grab, and four OBJ_TREND edge
    segments that draw the visible border (P-BK-06 — some builds render a filled
    rectangle even with FILL=false, so the border cannot be the rectangle). The
    children therefore ride OUR copy of the box's anchors, and that copy is what
    the user feels:

      * it used to share ONE 30 ms gate with the cursor fallback and the paint,
        so the border stepped at 33 fps while the native fill tracked the hand at
        event rate - «یکیش لایو درگ میشه یکیش نمیشه» on a fast drag;
      * nothing re-derived the border when a gesture's END was lost (a motionless
        release emits no mouse-move at all, P-BK-03), so the residue could
        survive until a timeframe switch.

    P-BK-19 is the OTHER half of the same gesture, and it is the half the user
    feels as «من یک طرف درگ میکنم طرف دیگه تکون میخوره» - I drag one side and the
    other side moves:

      * OWNERSHIP (a). The cursor fallback is the ONE path that writes the BOX,
        and a native drag is the TERMINAL's gesture - two writers on one box is
        P-BK-07's fight one layer down, and MT4 cancels the drag the second writer
        fights (P-BK-15). The terminal now claims the gesture through its own
        OBJECT_DRAG (and through the anchors moving without us), and it is asked
        FIRST (BK_DRAG_OWNER_MS); a fresh press takes the claim back.
      * THE GRAB (b). The fallback used to translate BOTH anchors whatever the
        press had grabbed, so an EDGE drag moved the far side too. The press point
        is measured in pixels against the box's corners into a 4-bit selection,
        and the fallback writes exactly those values: a body grab is a MOVE, an
        edge/corner grab is a RESIZE that leaves the opposite side where it is.
    """
    problems = []
    src = read(BASEKNOT)
    fol = body(src, "void BaseKnotFollowDrag(")
    if fol is None:
        return ["BaseKnotFollowDrag() is gone - the ONE mid-drag children writer (P-BK-07)"]
    # (a) the child MOVE step is change-driven: the anchor compare precedes any
    #     use of the budget stamp, so a copy is paid for only when the box moved.
    cmp_at = fol.find("s_bkFolT1")
    gate_at = fol.find("s_bkDragMs")
    if cmp_at < 0:
        problems.append("BaseKnotFollowDrag() no longer compares the BOX anchors (s_bkFol*) - "
                        "the follow would write on every event instead of when the box moved")
    elif gate_at >= 0 and gate_at < cmp_at:
        problems.append("BaseKnotFollowDrag() gates the CHILD MOVE STEP on s_bkDragMs again - that "
                        "shared 30 ms budget is exactly what left the visible border trailing the "
                        "native fill (P-BK-18)")
    #     (anchored on the GATE LINE, not on the name: the retirement comments
    #     mention BK_DRAG_CURSOR_MS, so a name test would pass for the wrong reason)
    if "#define BK_DRAG_CURSOR_MS" not in src or "BK_DRAG_CURSOR_MS) return;" not in fol:
        problems.append("the (dormant) cursor-delta fallback lost its own budget (BK_DRAG_CURSOR_MS) - "
                        "it is the one path that writes the BOX itself, so a restore must stay "
                        "rate-limited")
    # (b) the pump's ONE drag promise: it must keep skipping a live drag.
    #     P-BK-18's settle heal USED to be asserted here - it is RETIRED now
    #     (BKEDGE-OFF/P-BK-74) and its live/dead state is `check_bkedge_off()`'s
    #     job, one group per promise. It is NOT re-asserted here on purpose: the
    #     two gates that stood in this spot were name tests against the pump body,
    #     and the retirement COMMENTS still spell `if(bkHandOff && !BaseKnotBorderSettled(`
    #     and `UILeftButtonUp()` - i.e. they passed on the comment, which is the
    #     exact "a gate satisfied by code that no longer runs" this file warns
    #     about elsewhere. The live form is asserted where comments are stripped.
    pump = body(src, "void BaseKnotSyncBadges(")
    if pump is None:
        problems.append("BaseKnotSyncBadges() is gone - the 500 ms pump is the settle owner")
    else:
        if "s_bkDragId != \"\" && g_bkBoxes[i].id == s_bkDragId" not in pump:
            problems.append("the pump stopped skipping the actively dragged box (P-BK-15)")
    # (c) P-BK-19a: the BOX has ONE writer per gesture. The fallback may not write
    #     a box the terminal has claimed, and the claim must be made from both
    #     witnesses the terminal gives us: its own OBJECT_DRAG, and the anchors
    #     moving without us.
    #     (the cursor fallback that USED to sit here is retired - its live/dead
    #     state is `check_bkcursor_off()`'s job, one group per promise)
    events = body(src, "bool BaseKnotOnChartEvent(")
    if "s_bkNativeClaim = true;" not in fol:
        problems.append("the anchor-driven branch stopped claiming the gesture for the terminal "
                        "(P-BK-19a) - the fallback stays armed through a live native drag")
    if events is None:
        problems.append("BaseKnotOnChartEvent() is gone - the box drag has no event entry")
    else:
        if "s_bkNativeClaim = true;" not in events:
            problems.append("an OBJECT_DRAG no longer claims the gesture for the terminal (P-BK-19a) - "
                            "the fallback would write over the gesture the terminal just started")
        if "s_bkNativeClaim = false;" not in events:
            problems.append("a fresh press does not take the claim back (P-BK-19a) - the NEXT gesture "
                            "starts out owned by the terminal that owned the last one")
    # (d) P-BK-19b/P-BK-72: the grab role has ONE live consumer now - the release's
    #     size heal - and the retired one (the cursor fallback, BKCURSOR-OFF) stays dead.
    #     The role is what tells a native corner/edge RESIZE (the docs' own rule: anchors
    #     change the size) from a BODY move (which the magnet may have enlarged), so a
    #     press that stops measuring it hands the heal an answer it must not invent, and
    #     a heal that ignores it springs the user's own resize back (the P-BK-65 report,
    #     on a native gesture now). The dormant restore-path integrity is
    #     `check_bkcursor_off()`'s job, one group per promise.
    if re.search(r"(?m)^\s*s_bkGrabSel = BaseKnotGrabRole\(shbox", src) is None:
        problems.append("the press no longer measures WHICH part of the box it grabbed "
                        "(P-BK-19b/P-BK-72) - the release's size heal then cannot tell a "
                        "native resize from a body move and undoes the user's own resize")
    if events is not None and "if(bkGripWas == 0 && s_bkGrabSel == BK_GRAB_ALL) BaseKnotBodySizeHeal(" not in events:
        problems.append("the body-size heal is no longer gated on the press-time ROLE being the "
                        "BODY (P-BK-72) - every native resize would be healed back to its "
                        "press-time size on release")
    # (e) P-PERF-42: the child set is probed ONCE per gesture, not per child per
    #     step - and the probe cannot outlive the gesture it was built for.
    one = body(src, "void BaseKnotMoveOne(")
    if one is None:
        problems.append("BaseKnotMoveOne() is gone - the per-step child mover has ONE owner")
    elif "ObjectFind" in one:
        problems.append("the per-step child move probes existence again (P-PERF-42) - that is ~10 "
                        "terminal calls per drag event for an answer that cannot change mid-gesture")
    kids = body(src, "void BaseKnotMoveChildren(")
    if kids is None:
        problems.append("BaseKnotMoveChildren() is gone - the drag's child pass has ONE owner")
    else:
        if "BaseKnotChildMaskBuild(pfx)" not in kids or "BK_CH_EDGE_T" not in kids:
            problems.append("the child move pass stopped using the per-gesture child mask (P-PERF-42)")
    if events is not None and 's_bkChildMaskId = "";' not in events:
        problems.append("a fresh press does not clear the child mask key (P-PERF-42) - the same box "
                        "dragged twice would reuse the first gesture's answer")
    # (f) P-PERF-43: the drag measures ITSELF, and the release line carries it.
    if events is not None and "s_bkPerfMoveWorst = 0" not in events:
        problems.append("the drag's own timing counters are not reset per gesture (P-PERF-43)")
    if "paint=" not in src or "move=" not in src:
        problems.append("the drag ledger no longer reports its phases (P-PERF-43) - 'the drag lags' "
                        "would be guesswork again")
    #     (the ledger line NAMES the role too, so the check is anchored on the
    #     BRANCH itself - `if(`, not on the comparison somewhere in the body)
    if "if(s_bkGrabSel == BK_GRAB_ALL)" not in fol:
        problems.append("the cursor fallback no longer separates a body MOVE from an edge/corner "
                        "RESIZE (P-BK-19b) - an edge drag would move the opposite side again")
    if "BK_GRAB_T1" not in fol or "BK_GRAB_P2" not in fol:
        problems.append("the resize half of the cursor fallback stopped writing the grabbed values "
                        "(P-BK-19b) - the side the user holds would not follow the hand")
    # (g) P-BK-61: THE EIGHT HANDLE GRIPS are the resize gesture the user asked for
    #     («یک کلیک چپ میکنم راحت هر طرف که بخوام میکشم»). They exist BECAUSE a native
    #     drag may not be fought: MT4's own rectangle has no resize points at all, so
    #     the handles are separate selectable screen objects, the TERMINAL drags the
    #     chip, and this module is the gesture's ONE writer. Three promises hold it
    #     together, and each one has a seed below.
    grip = body(src, "void BaseKnotGripDrag(")
    if grip is None:
        problems.append("BaseKnotGripDrag() is gone - the handle resize has no writer (P-BK-61)")
    else:
        if "s_bkGripLive = side;" not in grip:
            problems.append("the handle drag does not publish WHICH side it writes (P-BK-61) - the "
                            "keeper would rewrite the chip under the hand and MT4 would cancel the "
                            "native drag (P-BK-15)")
        if "s_bkNativeClaim = true;" not in grip:
            problems.append("the handle drag does not claim the gesture for the terminal (P-BK-61) - "
                            "the retired cursor fallback would stay armed over a gesture it may not "
                            "write")
        if "BaseKnotMoveChildren(" not in grip:
            problems.append("the handle drag stopped carrying the rest of the family (P-BK-61) - the "
                            "edges and the levels would only catch up on release")
        if "BaseKnotSync(" in grip:
            problems.append("the handle drag runs a FULL Sync per step (P-BK-61) - the box' own "
                            "lesson (P-BK-07/P-PERF-42) is that this is exactly the lag")
    # (g0) BKDOT-OFF/BKGRIP-OFF/BKPOINT-OFF (P-BK-71): THE MARK IS A NATIVE BOX, AND
    #     OURS POINT AT NOTHING. «یک باکس خود متاتریدر باشه»: the carrier is MT4's own
    #     rectangle — moved and selected natively — so the centre cover (P-BK-59), the
    #     corner chips (P-BK-61) and the trendline points (P-BK-69) are ALL retired IN
    #     PLACE, and a retirement may not come half back — this group holds it to five
    #     promises:
    #       * the PLAN is empty: `BaseKnotGripSideAt()` plans no live row and
    #         `BK_GRIP_COUNT` is 0, with the restore rows still spelled under
    #         `BKGRIP-OFF` (that commented block IS the restore path);
    #       * every CALL SITE is commented — a live one draws, keeps and carries a point
    #         while the plan says there is none;
    #       * the RETIRED TAILS have ONE owner (`BaseKnotRetiredPointName`) that BOTH
    #         readers walk — the once-per-attach sweep in BaseKnotLazyInit and the
    #         deselect wipe — because a chart an older build wrote keeps those squares
    #         until something deletes them, and a name swept by one reader and forgotten
    #         by the other is a ghost square that drags nothing;
    #       * the keeper that USED to place them refuses to run while the plan is empty;
    #       * the trendline carrier a P-BK-67/68/69 build left behind is migrated back to
    #         the rectangle from its own anchors, once per attach (BKTREND-OFF).
    at = body(src, "int BaseKnotGripSideAt(")
    if at is None:
        problems.append("BaseKnotGripSideAt() is gone - the handle family has no plan (BKGRIP-OFF)")
    else:
        live = re.findall(r"(?m)^\s*if\(i == \d+\) return[^;]*;", at)
        if live:
            problems.append("BaseKnotGripSideAt() plans %d live chip(s) again (BKGRIP-OFF/P-BK-71) - "
                            "the mark is a native box, so a chip of ours is a selectable square "
                            "that answers no gesture" % len(live))
        if "BKGRIP-OFF" not in at:
            problems.append("the retired corner rows are gone from BaseKnotGripSideAt() (P-BK-71) - "
                            "that commented block IS the restore path")
        cnt = re.search(r"#define\s+BK_GRIP_COUNT\s+(\d+)", src)
        if cnt is None or int(cnt.group(1)) != len(live):
            problems.append("BK_GRIP_COUNT does not equal the LIVE rows of BaseKnotGripSideAt() "
                            "(P-BK-71) - every sweep and keeper asks that number, so a stale one "
                            "walks chips no keeper creates")
        blk = body(src, "bool BaseKnotSelectionMarkersWipe(")
        if blk is not None and "BaseKnotRetiredPointName(" not in blk:
            problems.append("the drop's wipe no longer walks the retired tails' ONE table (P-BK-71) - "
                            "a reader that spells its own list drifts apart from the attach sweep")
    #     the call sites, one probe each: the definition is the ONE live mention left, so a
    #     second one is a family that came back to life without a plan (the pair that makes
    #     a half-restored feature — a chip on screen that no keeper knows about).
    stripped = strip_comments(src)
    for call, why in (("BaseKnotDotFollow(", "P-BK-59's centre cover"),
                      ("BaseKnotGripsFollow(", "the P-BK-61 corner chips"),
                      ("BaseKnotGripDrag(", "the chip resize writer")):
        if len(re.findall(re.escape(call), stripped)) > 1:
            problems.append("%s is called from a LIVE site again (P-BK-71) - %s is retired in place: "
                            "the box' own body drag is the gesture, so every call site stays "
                            "commented" % (call, why))
    #     the retired tails, ONE table: it must NAME the squares every older build wrote,
    #     and both readers must walk IT (a reader that spells its own list is the drift
    #     this table exists to prevent).
    tbl = body(src, "string BaseKnotRetiredPointName(")
    if tbl is None:
        problems.append("BaseKnotRetiredPointName() is gone (P-BK-71) - the retired point tails "
                        "have no ONE owner, so the attach sweep and the deselect wipe can drift "
                        "apart")
    else:
        tails = re.findall(r'"(\w+)"', tbl)
        for want in ("GT", "GB", "GL", "GR", "GTL", "GTR", "GBL", "GBR",
                     "G1", "G2", "DOT", "P1", "P2"):
            if want not in tails:
                problems.append("the retired tail %s is not in BaseKnotRetiredPointName() (P-BK-71) - "
                                "a chart an older build wrote keeps that square on a box whose "
                                "points are the terminal's own" % want)
        n = re.search(r"#define\s+BK_RETIRED_POINTS\s+(\d+)", src)
        if n is None or int(n.group(1)) != len(tails):
            problems.append("BK_RETIRED_POINTS does not equal the table's own rows (P-BK-71) - the "
                            "readers then walk past the list")
    lazy = body(src, "void BaseKnotLazyInit(")
    if lazy is None:
        problems.append("BaseKnotLazyInit() is gone - the one-time sweep has no home (P-BK-71)")
    else:
        if "BaseKnotRetiredPointName(" not in lazy:
            problems.append("the one-time sweep of the retired points is gone (P-BK-71) - a chart "
                            "the older builds wrote keeps selectable squares that drag nothing")
        if "OBJ_RECTANGLE" not in lazy:
            problems.append("the trendline-carrier migration is gone (BKTREND-OFF/P-BK-71) - a chart "
                            "a P-BK-67/68/69 build wrote keeps a carrier no Sync restyles")
    # (g1) P-BK-71: THE MARK IS THE BOX — MT4's own rectangle. Its two anchors ARE the
    #     knot's geometry (min/max normalisation reads them), so the TYPE is load-bearing:
    #     a trendline carrier means the retired mark came back (it has no fill, no native
    #     body drag the children ride), and the four border segments ride with the box.
    if re.search(r"ObjectCreate\(0, box, OBJ_TREND", src):
        problems.append("an OBJ_TREND carrier is back (BKTREND-OFF/P-BK-71) - the mark the user "
                        "asked for is MT4's own box")
    if re.search(r"ObjectCreate\(0, box, OBJ_RECTANGLE", src) is None:
        problems.append("the carrier is no longer created as an OBJ_RECTANGLE (P-BK-71) - the box "
                        "the user asked for is the terminal's own rectangle, and its body drag "
                        "is the gesture this module's follow rides")
    keep = body(src, "bool BaseKnotGripsFollow(")
    if keep is None:
        problems.append("BaseKnotGripsFollow() is gone - the handle family has no owner (P-BK-61), "
                        "nor a refusal while it is retired (P-BK-71)")
    else:
        if "BK_GRIP_COUNT <= 0" not in keep:
            problems.append("the retired handle keeper no longer refuses to run (P-BK-71) - it would "
                            "walk a plan whose rows are still commented out, i.e. restore itself "
                            "half-way on the first call a partial restore leaves behind")
        if "side == skip" not in keep:
            problems.append("the handle keeper no longer spares the chip the hand is dragging "
                            "(P-BK-61/P-BK-15) - writing it cancels the terminal's own drag")
        if "ObjectDelete" not in keep:
            problems.append("the handle keeper never retires a chip (P-BK-61) - a deselected or "
                            "locked box would keep its handles on screen after a restore")
        if "OBJPROP_SELECTABLE, true" not in keep and "OBJPROP_SELECTABLE, true" not in (body(src, "void BaseKnotGripCreate(") or ""):
            problems.append("a handle is stored UNSELECTABLE (P-BK-61) - the terminal would never "
                            "drag it and the whole feature would be silently absent")
    mk = body(src, "void BaseKnotGripCreate(")
    if mk is None:
        problems.append("BaseKnotGripCreate() is gone - the handle look has no owner (P-BK-61)")
    elif "OBJ_RECTANGLE_LABEL" not in mk:
        problems.append("a handle is no longer a SCREEN object (P-BK-61) - the design rests on MT4 "
                        "dragging a selectable screen square natively")
    # (g2) P-BK-71: AND THE ROUTE STAYS RETIRED. The chip OBJECT_DRAG branch is what made MT4
    #     resize the box; the box' own BODY is that gesture now, and it arrives on the BOX
    #     branch. A live chip branch would route a name no keeper creates into a writer the
    #     plan says is empty.
    if events is not None and "BaseKnotGripDrag(" in strip_comments(events):
        problems.append("the OBJECT_DRAG branch that routes a CHIP to its resize is live again "
                        "(P-BK-71) - the mark's points are the terminal's own, and the chip the "
                        "branch would write is never created (P-UI-47's fault, in a new place)")
    # (h) P-BK-61b: A BODY DRAG IS A MOVE AND ONLY A MOVE («از رنگ ریسایز نشه فقط درگ بشه»).
    #     MetaTrader's magnet snaps a dragged rectangle's two anchors independently (the
    #     fact behind P-BK-25), so the FILL could grow the box on a magnet-enabled chart.
    #     The release puts the press-time SIZE back - measured, never invented (P-BK-25's
    #     trusted baseline), and gated so a handle resize is not undone by it.
    heal = body(src, "bool BaseKnotBodySizeHeal(")
    if heal is None:
        problems.append("BaseKnotBodySizeHeal() is gone (P-BK-61b) - grabbing the box' FILL can "
                        "resize it again on a magnet-enabled terminal")
    else:
        if "s_bkSnapTrusted" not in heal:
            problems.append("the body-size heal runs without a TRUSTED press baseline "
                            "(P-BK-25/P-BK-61b) - a snapshot taken mid-drag reads the terminal's "
                            "own translation as a resize and snaps the box")
        if "GetCachedPoint()" not in heal:
            problems.append("the body-size heal lost its \"size unchanged\" compare (P-BK-61b) - "
                            "every plain body drag would pay a box rewrite on release")
    if events is not None and "BaseKnotBodySizeHeal(" not in events:
        problems.append("the release no longer restores the press-time SIZE for a body drag "
                        "(P-BK-61b) - the FILL resizes the box again")
    if events is not None and "if(bkGripWas == 0 && s_bkGrabSel == BK_GRAB_ALL) BaseKnotBodySizeHeal(" not in events:
        problems.append("the body-size heal is not gated on the gesture being a BODY drag "
                        "(P-BK-61b/P-BK-72) - it would undo a native resize on every release")
    # (i) P-BK-62: THE VIEW THE DRAG/RESIZE OWNS MUST STAY OWNED. «همیشه موقع درگ و
    #     ریسایز چارت پشتش قفل بشه» - the box tool locks the view from three
    #     gestures, but only ONE of them (the draw session) was visible to the
    #     reconcile watchdog, and the drag's own guard then early-returned for the
    #     rest of the gesture: the chart panned under a live drag/resize. Two
    #     promises hold it, and neither may be lost alone.
    owned = body(src, "bool BaseKnotViewOwned(")
    if owned is None:
        problems.append("BaseKnotViewOwned() is gone (P-BK-62) - the reconcile watchdog has "
                        "no way to see an IDLE box drag or a handle resize, so it hands the "
                        "view back under the user's hand")
    else:
        if "s_bkDragLock" not in owned or "g_bkState" not in owned:
            problems.append("BaseKnotViewOwned() no longer answers for ALL THREE gestures "
                            "(P-BK-62) - whichever latch it drops is the one the watchdog "
                            "yanks the lock away from mid-gesture")
    intended = body(read(PANELS), "bool ChartLockIntended(")
    if intended is None:
        problems.append("ChartLockIntended() is gone - the chart lock's intent query has no owner")
    elif "BaseKnotViewOwned()" not in intended:
        problems.append("the chart-lock reconcile stopped asking the BOX TOOL's own latch "
                        "(P-BK-62/P-UI-53) - an IDLE drag or a handle resize would have its "
                        "lock restored from under it, and `BaseKnotDragLockOn`'s guard then "
                        "keeps it unlocked for the rest of the gesture")
    on = body(src, "void BaseKnotDragLockOn(")
    if on is None:
        problems.append("BaseKnotDragLockOn() is gone - the drag/resize has no lock holder (P-BK-62)")
    elif "BaseKnotReassertLock(" not in on:
        problems.append("an OWNED drag lock is taken once and never re-forced (P-BK-62) - the "
                        "P-BK-14 rule the draw session already obeys (a third writer flips the "
                        "props back while the button is still down)")
    # (j) P-BK-63: A CLICK OUTSIDE THE BOX LETS IT GO («زمانی که خارج از باکس کلیک
    #     شد سلکت بودنش غیرفعال بشه»). The drop must be reachable from the CHART
    #     click, must ask the EXACT selection question, and must never run on a
    #     click that belongs to the box itself or to the UI that is sitting over it.
    drop = body(src, "bool BaseKnotDeselectOnChartClick(")
    if drop is None:
        problems.append("BaseKnotDeselectOnChartClick() is gone (P-BK-63) - a click outside "
                        "the box leaves it selected")
    else:
        if "UIPointerOverSurface" not in drop:
            problems.append("the outside-click drop lost its UI gate (P-BK-63/P-UI-92) - a click "
                            "on the Base Box strip would deselect the very box the card edits")
        if "BaseKnotBoxAtPx(" not in drop or "BaseKnotBoxAt(" not in drop:
            problems.append("the outside-click drop no longer proves the click is OUTSIDE "
                            "(P-BK-63/P-BK-24) - a press on the box' own border would let go of "
                            "the selection it just made")
        if "BaseKnotDropSelection(" not in drop:
            problems.append("the drop writes SELECTED itself instead of going through its ONE "
                            "owner `BaseKnotDropSelection` (P-BK-26/P-BK-63)")
        if "BaseKnotSelectedBoxId()" not in drop:
            problems.append("the drop asks `BaseKnotSelectedId()` (P-BK-63) - that answers the "
                            "NEWEST box when NOTHING is selected (P-BK-58's question), so a "
                            "click on empty chart could deselect a box the user never chose")
        if "BaseKnotSelectionMarkersWipe(" not in drop:
            problems.append("the drop no longer sweeps the point family's leftovers (P-BK-63/"
                            "P-BK-71) - the one-time attach sweep is then the ONLY reader of "
                            "BaseKnotRetiredPointName, so a chart an older build wrote keeps "
                            "those squares until the next re-attach")
    if events is not None and "BaseKnotDeselectOnChartClick(" not in events:
        problems.append("no CHARTEVENT_CLICK branch drops the selection (P-BK-63) - the drop "
                        "has no caller, which is how BKSELECT-KEPT's `BaseKnotDropSelection` "
                        "went dormant in the first place")
    # (k) P-BK-65: A RESIZE MAY NOT BE READ AS A MOVE. «چرا باکس ری‌سایز می‌کنم برمی‌گرده
    #     سر جای خودش یا لبه دیگه سمت دیگه میرن» - the release decided the gesture's KIND
    #     from the keeper's skip field (`s_bkGripLive`), and every mouse-channel press
    #     edge cleared that field, so one down-flicker mid-drag made the release run
    #     `BaseKnotBodySizeHeal` (the old WIDTH/HEIGHT back around the left/top corner →
    #     the far edge jumps) and let the keeper rewrite the chip under the hand (P-BK-15:
    #     MT4 cancels that drag). The kind now lives in its own latch, latched from the
    #     terminal's own OBJECT_DRAG of a chip and cleared only by a real end.
    if "s_bkGripGesture" not in src:
        problems.append("the grip GESTURE latch is gone (P-BK-65) - the release has only the "
                        "keeper's skip to read, and a press edge clears it mid-resize")
    elif grip is not None and "s_bkGripGesture = side;" not in grip:
        problems.append("a handle drag no longer latches the KIND of this press (P-BK-65) - the "
                        "terminal just named the chip and that answer is dropped")
    if events is not None:
        if "int bkGripWas = s_bkGripGesture;" not in events:
            problems.append("the release no longer reads the gesture's KIND (P-BK-65) - a chip "
                            "resize can be executed as a body drag again, and the size heal "
                            "then springs the box back to its press-time size")
        if "int bkGripWas = s_bkGripLive;" in events:
            problems.append("the release reads the keeper's SKIP as the gesture's kind "
                            "(P-BK-65) - a mouse-channel press edge clears that field mid-drag, "
                            "which IS the reported springback")
        if "const bool bkGripHeld = (s_bkGripGesture != 0);" not in events:
            problems.append("the press edge stopped asking whether a chip is held (P-BK-65) - it "
                            "re-labels a live resize and arms a mid-drag baseline (P-BK-25)")
        #     (anchored on the RESET block itself — `if(!bkGripHeld)` with the brace
        #     that opens it — because the press LATCH below wears the same guard and
        #     an anchor on the bare token would pass while one of the two was opened)
        if "if(!bkGripHeld)\n" not in events:
            problems.append("the press edge resets the gesture unconditionally again (P-BK-65) - "
                            "the same flicker that made a resize snap back")
        if "if(!bkGripHeld &&" not in events:
            problems.append("the press edge latches its box AND re-takes the baseline during a "
                            "live resize (P-BK-65/P-BK-25) - a mid-drag snapshot is a baseline "
                            "the size heal may not measure against")
        if "s_bkBoxNamed    = true;" not in events:
            problems.append("the terminal's OBJECT_DRAG of a BOX no longer records WHAT it named "
                            "(P-BK-65) - the body-size heal loses its ground truth and the "
                            "press can stay labelled a resize")
    heal = body(src, "bool BaseKnotBodySizeHeal(")
    if heal is not None and "if(!s_bkBoxNamed) return false;" not in heal:
        problems.append("the body-size heal runs without the terminal's own \"it dragged the "
                        "BOX\" witness (P-BK-65) - a handle resize would be re-sized back "
                        "around its left/top corner and the OPPOSITE edge would jump")
    clear = body(src, "void BaseKnotGestureClear(")
    if clear is None:
        problems.append("BaseKnotGestureClear() is gone (P-BK-65) - the gesture state has no "
                        "teardown owner")
    else:
        for tok in ("s_bkGripGesture = 0;", "s_bkGripLive    = 0;", "s_bkBoxNamed    = false;"):
            if tok not in clear:
                problems.append("BaseKnotGestureClear() does not clear %s (P-BK-65) - a stale "
                                "gesture answer would outlive its press" % tok.strip())
        deinit = body(src, "void BaseKnotOnDeinit(") or ""
        if "BaseKnotGestureClear();" not in deinit:
            problems.append("a removed/switched instance keeps its gesture answer (P-BK-65) - the "
                            "next attach inherits \"this press is a resize\"")
    return problems


def check_bkbox_ink():
    """[bkbox-ink] - THE DEFAULT BOX IS HOLLOW AND IN THE FOREGROUND (P-BK-74).

    «باکس پیش فرض بدون fill باشه و بگراندش غیر فعال باشه اوکی» - the user's own
    words, and the terminal's own defaults: MT4 stores its objects `background=0`,
    and its Rectangle tool draws an empty outline. The user's screenshot of MT4's
    own rectangle next to ours is what forced this: ours was painted in the CHART
    BACKGROUND colour (an invisible cover), and the border colour only ever reached
    four OBJ_TREND children drawn on top of it. The ink the object wears is the
    user's own `inpBoxBorderColor` / `inpBoxBorderStyle` / `inpBoxBorderWidth` now,
    because the rectangle IS the border (BKEDGE-OFF retires the children).

    The FILLED branch is the other half of the same promise: with the fill turned
    on the ink IS the fill, so that arm keeps colour=fill + BACK=true (behind the
    candles, zone-like) — P-BK-23's lesson, unchanged.

    `BaseKnotFillHealed()` is the pump's ONE reader deciding a box drifted, so it
    must ask the same questions the writer answers: FILL, BACK, and the ink the
    look actually uses. A reader still asking for the chart background colour is
    the P-BK-74 bug in reverse — it would pass on the very box the writer just
    changed, so a chart an older build painted invisible is never healed.
    """
    problems = []
    src = read(BASEKNOT)
    sty = body(src, "void BaseKnotStyleBox(")
    if sty is None:
        return ["BaseKnotStyleBox() is gone - the box look has ONE writer (P-BK-74)"]
    sty = strip_comments(sty)
    for prop, why in (
            ("GetBoxBorderRenderColor()",
             "the hollow rectangle is painted in a colour that is not the border's again - it "
             "becomes an invisible cover whose outline only shows because something else draws "
             "it (BKEDGE-OFF retired that something)"),
            ("OBJPROP_FILL, false",
             "the default box comes up FILLED - the user asked for no fill"),
            ("OBJPROP_BACK, false",
             "a background object forces the terminal to repaint the bars under it on every frame "
             "of a native drag, over an area exactly the size of the box (P-BK-23)"),
            ("inpBoxBorderStyle",
             "the user's border STYLE no longer reaches the object that draws the border"),
            ("inpBoxBorderWidth",
             "the user's border WIDTH no longer reaches the object that draws the border")):
        if prop not in sty:
            problems.append("BaseKnotStyleBox() lost %s (P-BK-74) - %s" % (prop, why))
    for prop, why in (("GetBoxFillRenderColor()", "the fill would be drawn with the border ink"),
                      ("OBJPROP_FILL, true", "the fill is asked for but never turned on"),
                      ("OBJPROP_BACK, true", "the fill would be drawn IN FRONT of the candles")):
        if prop not in sty:
            problems.append("the FILLED look lost %s (P-BK-74) - %s" % (prop, why))
    heal = body(src, "bool BaseKnotFillHealed(")
    if heal is None:
        problems.append("BaseKnotFillHealed() is gone - the pump's drift reader has ONE owner "
                        "(P-BK-05/06)")
    else:
        heal = strip_comments(heal)
        for prop, why in (("GetBoxBorderRenderColor()",
                           "it no longer asks the ink the hollow look actually uses, so a box an "
                           "older build left invisible reads as healed forever (P-BK-74)"),
                          ("OBJPROP_BACK",
                           "a hollow box is no longer required to be a FOREGROUND object "
                           "(P-BK-23)"),
                          ("GetBoxFillRenderColor()",
                           "the filled half of the compare is gone, so a fill the user just "
                           "turned on never gets re-asserted")):
            if prop not in heal:
                problems.append("BaseKnotFillHealed() lost %s (P-BK-74) - %s" % (prop, why))
    return problems


def check_bkedge_off():
    """[bkedge-off] - THE BORDER IS THE BOX' OWN OUTLINE (P-BK-74, 2026-09-17).

    «یک باکس متاتریدر چطور ساخته میشه همون میخوام بزاری خودش از داک رسمی نگاه کن
    متودش چیه» → the official OBJ_RECTANGLE recipe (docs.mql4.com/constants/
    objectconstants/enum_object/obj_rectangle) draws its own border; ours drew an
    invisible background-coloured rectangle and put FOUR OBJ_TREND children on top
    of it to fake the outline. The terminal's is ONE object with a native body drag
    and its own five sizing markers (P-BK-73 hands them over at the commit); ours
    was five objects with a custom gesture.

    So the four edges are RETIRED IN PLACE — BKEDGE-OFF, six marked sites — and the
    rectangle wears the border ink itself (see `check_bkbox_ink`). The P-BK-18
    settle heal goes with them: it existed only because the visible border was a
    COPY of the box that our own follow had to keep in step, so a lost gesture end
    left the copy behind. With one object there is no copy to fall behind — the
    terminal moves the outline with the object it belongs to. The sizing rubber
    band becomes one rectangle again too, so what the user sizes is what he gets.

    This group asserts the retirement in BOTH directions: a live edge (a call site
    that came back, a probe that answers "no" forever, a settle heal with nothing
    to heal) must FAIL, and so must a half-restore that deletes the dormant engine
    the uncomment would need.
    """
    problems = []
    src = read(BASEKNOT)
    marks = src.count("BKEDGE-OFF")
    if marks < 6:
        problems.append("the edge retirement lost its marker(s) - %d left, six sites are expected - "
                        "the next session cannot tell a dormant family from a live one "
                        "(BKEDGE-OFF)" % marks)
    #     THE LIVE FORM IS TESTED ON STRIPPED TEXT. A name test against the raw
    #     source would pass on the retirement comments themselves (they spell the
    #     very call they retired) - the "gate satisfied by code that no longer
    #     runs" failure this file has already been bitten by once.
    stripped = strip_comments(src)
    #     ONE live mention of the drawer is allowed: its own definition. Every call
    #     site stays commented (the same shape as the BKGRIP-OFF family's gate).
    if len(re.findall(r"BaseKnotDrawEdges\(", stripped)) > 1:
        problems.append("BaseKnotDrawEdges() is called from a LIVE site again (BKEDGE-OFF/P-BK-74) - "
                        "the border is the box' own outline, so a drawn copy sits on top of the "
                        "object the terminal already paints, and it is a second writer of the same "
                        "geometry (P-BK-07)")
    kids = body(src, "void BaseKnotMoveChildren(")
    if kids is None:
        problems.append("BaseKnotMoveChildren() is gone - the drag's child pass has ONE owner")
    elif re.search(r"(?m)^\s*if\(\(s_bkChildMask & BK_CH_EDGE_[TBLR]\) != 0\)", strip_comments(kids)):
        problems.append("the child move pass carries an edge again (BKEDGE-OFF/P-BK-74) - a trend "
                        "line the box' own outline made redundant would be moved on every drag "
                        "step to land on pixels the rectangle already paints")
    mask = body(src, "int BaseKnotChildMaskBuild(")
    if mask is None:
        problems.append("BaseKnotChildMaskBuild() is gone - the gesture's ONE existence sweep "
                        "(P-PERF-42)")
    elif re.search(r"(?m)^\s*if\(ObjectFind\(0, pfx \+ BK_EDGE_", strip_comments(mask)):
        problems.append("the gesture's existence sweep probes an edge again (BKEDGE-OFF/P-BK-74) - "
                        "nothing creates those names any more, so the probe can only answer \"no\" "
                        "while still costing a terminal call (P-PERF-42)")
    pump = body(src, "void BaseKnotSyncBadges(")
    if pump is None:
        problems.append("BaseKnotSyncBadges() is gone - the 500 ms pump has ONE owner")
    else:
        live = strip_comments(pump)
        if re.search(r"(?m)^\s*if\(bkHandOff", live) or "BaseKnotBorderSettled(" in live:
            problems.append("the P-BK-18 settle heal is LIVE again (BKEDGE-OFF/P-BK-74) - it healed "
                            "a COPY of the box; with the border retired it can only Sync a box that "
                            "is already right, and writing into a live native drag cancels it "
                            "(P-BK-15)")
        if "BaseKnotTPStale(pfx)" not in live:
            problems.append("the pump lost the pre-tick ray rebuild it shared that probe line with "
                            "(P-BK-50) - retiring the edges took a LIVE heal with it")
    #     the dormant engine stays compiled so a restore is one uncomment, and stays
    #     WHOLE so the restore is not a rewrite (the BKGRIP-OFF family's rule).
    if body(src, "void BaseKnotDrawEdges(") is None:
        problems.append("BaseKnotDrawEdges() lost its body - the retirement must stay one uncomment "
                        "away, and deleting it turns the restore into a rewrite (BKEDGE-OFF)")
    settle = body(src, "bool BaseKnotBorderSettled(")
    if settle is None:
        problems.append("BaseKnotBorderSettled() is gone - the dormant settle compare has ONE owner, "
                        "and a half-restore that uncomments the heal must find it whole (BKEDGE-OFF)")
    elif ("BK_EDGE_T" not in settle or "OBJPROP_TIME, 1" not in settle
          or "OBJPROP_PRICE, 0" not in settle):
        problems.append("BaseKnotBorderSettled() no longer compares the top edge's span AND price "
                        "against the box - half the divergence would go unseen (BKEDGE-OFF)")
    #     the sizing rubber band: ONE rectangle, MOVED. The two call sites used to
    #     delete and redraw four edges per frame - a create storm per hover, for an
    #     object the terminal never asked to be recreated.
    if len(re.findall(r"BaseKnotDrawPreviewRect\(", stripped)) < 3:
        problems.append("the sizing preview is not drawn as ONE rectangle from BOTH call sites "
                        "(BKEDGE-OFF/P-BK-74) - a call site still draws the retired edge family, or "
                        "the drawer is gone")
    if re.search(r"ObjectDelete\(0, pv\)", stripped):
        problems.append("a preview call site deletes its object again (P-BK-74) - the rectangle is "
                        "MOVED now, so a delete/recreate per mouse-move is a paint storm the "
                        "terminal never asked for")
    prev = body(src, "void BaseKnotDrawPreviewRect(")
    if prev is None:
        problems.append("BaseKnotDrawPreviewRect() is gone - the preview has no ONE drawer (P-BK-74)")
    else:
        prev = strip_comments(prev)
        for prop, why in (("OBJ_RECTANGLE",
                           "a trend-line preview is back, i.e. a shape the commit will not hand "
                           "over - what the user sizes must be what he gets"),
                          ("OBJPROP_FILL, false",
                           "the preview would show a fill the committed box does not have"),
                          ("OBJPROP_BACK, false",
                           "a background preview makes the terminal repaint the candles under it "
                           "on every frame of the sizing gesture"),
                          ("OBJPROP_SELECTABLE, false",
                           "the terminal would put its sizing markers on a box that is not "
                           "committed yet (P-BK-73)")):
            if prop not in prev:
                problems.append("BaseKnotDrawPreviewRect() lost %s (P-BK-74) - %s" % (prop, why))
    return problems


def check_bkcursor_off():
    """[bkcursor-off] - the cursor-delta fallback is RETIRED (2026-09-14).

    «داخل باکس دوتا درگ فعال داریم، یکیش رو حذف کن، اونی که لایو نیست» - TWO
    writers moved one box: the terminal's own native drag (the LIVE one: it moves
    the anchors at event rate and MT4 repaints the fill on that same frame) and a
    cursor-delta fallback that wrote the BOX itself under a 30 ms budget, because
    every write it made was a repaint the terminal never asked for - which is
    exactly what a user feels as "not live". The fallback is now DEAD BY
    CONSTRUCTION (like PANELDRAG-OFF), its body and its grab-role measurement stay
    compiled so a restore is one word.

    This group asserts the retirement in BOTH directions: a live second writer
    must FAIL, and so must a half-restore that deletes the dormant engine.
    """
    problems = []
    src = read(BASEKNOT)
    fol = body(src, "void BaseKnotFollowDrag(")
    if fol is None:
        return ["BaseKnotFollowDrag() is gone - the live box follow has ONE owner"]
    if src.count("BKCURSOR-OFF") < 3:
        problems.append("the cursor-fallback retirement lost its marker(s) - the next session cannot "
                        "tell a dormant engine from a live one (BKCURSOR-OFF)")
    if "else if(false && !s_bkNativeClaim" not in fol:
        problems.append("the cursor-delta fallback is not dead by construction - a second writer of "
                        "the BOX is back beside the terminal's own drag (BKCURSOR-OFF)")
    if re.search(r"(?m)^\s*else if\(!s_bkNativeClaim", fol):
        problems.append("a LIVE fallback branch exists beside the dead one (BKCURSOR-OFF)")
    if "ObjectMove(0, box," in fol.split("BKCURSOR-OFF")[0]:
        problems.append("the follow writes the BOX itself before the retirement marker - only the "
                        "TERMINAL may move a box it is dragging (BKCURSOR-OFF/P-BK-15)")
    # the dormant engine must still be there to uncomment
    grab = body(src, "int BaseKnotGrabRole(")
    if grab is None:
        problems.append("the retired grab-role measurement lost its body - a restore is a rewrite "
                        "again (BKCURSOR-OFF)")
    else:
        if "ChartTimePriceToXY" not in grab:
            problems.append("the dormant grab role is no longer MEASURED (P-BK-19b) - a restored "
                            "fallback would guess and move the wrong side")
        missing = [n for n in ("BK_GRAB_CORNER_PX", "BK_GRAB_EDGE_PX", "BK_GRAB_ALL")
                   if n not in grab]
        if missing:
            problems.append("the dormant grab role lost %s from its bands (P-BK-19b)" % "/".join(missing))
    #     P-BK-72: the press-time measurement itself is LIVE again — its consumer is the
    #     release's size heal (`check_bk_drag`'s (d) owns that promise), NOT the fallback
    #     above, which stays dead by construction. What this group owns is that the
    #     FALLBACK stays dead and that the engine it would need is still whole.
    if "s_bkGrabSel = BaseKnotGrabRole(shbox, s_bkDragX0, s_bkDragY0);" not in src:
        problems.append("the press-time role measurement is gone (P-BK-19b/P-BK-72) - the size "
                        "heal would obey a role nobody measured, and the dormant fallback lost "
                        "the call its restore needs")
    #     the dormant body's own role split must survive (a restored fallback
    #     without it is the very bug P-BK-19b fixed)
    if "if(s_bkGrabSel == BK_GRAB_ALL)" not in fol:
        problems.append("the dormant fallback body lost the MOVE/RESIZE split (P-BK-19b) - a restore "
                        "would move the opposite side of an edge drag again")
    return problems


def check_bkmagnet():
    """[bkmagnet] - the ADJUST magnet is RETIRED (2026-09-15, BKMAGNET2-OFF).

    «مگنت نمیخواد باشه حذفش کن» - the adjust magnet P-BK-21 had put on the drag
    release is gone by user decision. The box stays where the hand let it go,
    exactly like MT4's own rectangle. Retired the BKMAGNET-OFF way (commented
    in place, NOT merely uncalled): a dormant-but-compiling reader would still
    count as a reader in `probe-budget-audit`'s discovered reader index, and a
    re-added card row would then pass `live-control` while moving nothing -
    P-UI-47's exact failure. So the engine is comments, the release call is a
    comment, and the card rows are hidden again (addresses stay, P-UI-47).

    This group asserts the retirement in BOTH directions: a revived magnet
    must FAIL, and so must a half-retirement that leaves a live reader behind.
    """
    problems = []
    src = read(BASEKNOT)
    snap = body(src, "double BaseKnotSnapPrice(")
    if snap is None:
        return ["BaseKnotSnapPrice() is gone - the draw-time magnet owner must stay"]
    if "return price;   // BKMAGNET-OFF" not in snap.split("//--- retired snap body", 1)[0]:
        problems.append("the DRAW-time magnet is live again: corners snap onto shadows mid-draw, "
                        "exactly the behaviour BKMAGNET-OFF was a user decision to remove")
    if "BKMAGNET2-OFF" not in src or "// BaseKnotMagnetSettle(s_bkDragId);" not in src:
        problems.append("the retired release call is gone, not commented - the next session cannot "
                        "tell a retired magnet from a live one (BKMAGNET2-OFF)")
    stripped = strip_comments(src)
    if "BaseKnotMagnetSettle(s_bkDragId);" in stripped:
        problems.append("the ADJUST magnet is back on the release: the box no longer stays where "
                        "the hand let it go (BKMAGNET2-OFF)")
    if "BaseKnotMagnetPrice(" in stripped or "void BaseKnotMagnetSettle(" in stripped:
        problems.append("a LIVE magnet reader survived the retirement: a re-added card row would "
                        "pass live-control while the release never snaps (BKMAGNET2-OFF/P-UI-47)")
    if body(src, "void BaseKnotFollowDrag(") is None:
        problems.append("BaseKnotFollowDrag() is gone - the live box follow has ONE owner")
    else:
        fol = body(src, "void BaseKnotFollowDrag(")
        if "MagnetSettle" in fol or "MagnetPrice" in fol:
            problems.append("the magnet runs inside the follow: a second writer beside the terminal's "
                            "own drag (BKCURSOR-OFF/P-BK-15)")
    panels = read(PANELS)
    for r in ('PnlSpecAdd(8, PNL_K_LEGACY, 2, 1, "magnet");',
              'PnlSpecAdd(8, PNL_K_LEGACY, 3, 1, "magnet");'):
        if r in panels:
            problems.append("the card row %s is rendered again while its engine is retired: "
                            "a control that moves nothing (P-UI-47/BKMAGNET2-OFF)" % r.split(",")[2].strip())
    # P-BK-61 (2026-09-16): THE MAGNET CAME BACK, SCOPED. The user asked for it on
    # the NEW gesture («با کنترل هم مگنت فعال میشه ... حرکت رو بچسبوند به کندل های و
    # لو که دقیق باشه»): while the hand drags a HANDLE and CONTROL is held, the price
    # snaps to the candle high/low. `inpEnableMagnet`/`inpMagnetSensitivityPips`
    # therefore have a reader again - so this group now asserts WHERE that reader may
    # live (three promises), on top of the retirement above, which does NOT move: the
    # box' own drag still snaps to nothing, and its live follow is still clean.
    grip = body(src, "void BaseKnotGripDrag(")
    snap = body(src, "double BaseKnotGripSnapPrice(")
    if snap is None:
        problems.append("BaseKnotGripSnapPrice() is gone - the handle magnet's reader must stay "
                        "declared (P-BK-61), or the two MAGNET rows go back to being controls "
                        "with no reader at all")
    elif "inpMagnetSensitivityPips" not in snap or "iHigh" not in snap or "iLow" not in snap:
        problems.append("the handle magnet no longer measures the candle high/low inside the user's "
                        "own sensitivity (P-BK-61) - a magnet that invents its own measure")
    # P-BK-64 (2026-09-16): THE UNIT IS THE PIXEL, AND THE TARGET IS THE NEAREST OF
    # FOUR PRICES. «مگنت درست کار نمی‌کنه» was a unit bug: a pip gate is under 1 px
    # on a D1 chart, so the snap could never fire where the user aims. Every
    # published MT magnet (MT5's own, MQL5 market 38178/161169/Easy Toolbar) snaps
    # within a PIXEL proximity to the nearest OHLC — both halves are asserted here,
    # because only the pair makes the gesture usable.
    if snap is not None:
        if "ChartTimePriceToXY" not in snap or "BK_MAGNET_MIN_PX" not in snap \
                or "BK_MAGNET_MAX_PX" not in snap:
            problems.append("the handle magnet gates on a PRICE distance again (P-BK-64) - a pip "
                            "gate is under one pixel on a wide-timeframe chart, so a snap the "
                            "user can aim at never fires (the reported «مگنت درست کار نمی‌کنه»)")
        if "iOpen" not in snap or "iClose" not in snap:
            problems.append("the handle magnet only considers the candle high/low (P-BK-64) - every "
                            "shipped MT magnet snaps to the NEAREST of a bar's four prices "
                            "(Open/High/Low/Close), and the nearest-by-pixel rule is what makes "
                            "it feel exact instead of arbitrary")
    if grip is None:
        problems.append("BaseKnotGripDrag() is gone - the handle magnet's ONLY caller (P-BK-61)")
    elif "if(modifier && " not in grip or "BaseKnotGripSnapPrice(" not in grip:
        problems.append("the magnet is not gated on a held modifier inside the handle drag "
                        "(P-BK-61) - an ungated magnet IS the behaviour BKMAGNET2-OFF removed")
    # P-BK-66 (2026-09-16): THE MODIFIER IS SHIFT, BECAUSE CTRL IS THE TERMINAL'S OWN
    # DUPLICATE GESTURE. «من ctrl که میگیرم برای مگنت این باکس رو کپی میکنه»: MetaTrader
    # copies a draggable object on Ctrl+drag, and these handles ARE draggable objects
    # (OBJPROP_SELECTABLE is what makes them handles at all), so Ctrl cloned the chip
    # instead of letting the magnet snap it. Asserted in BOTH directions - the probe
    # reads SHIFT, and no site on the magnet's path spells CONTROL again: a magnet on
    # the terminal's copy key is a magnet the user can never hold down.
    utils = strip_comments(read(UTILS))
    if "bool UIMagnetModifierDown()" not in utils or "TERMINAL_KEYSTATE_SHIFT" not in utils:
        problems.append("the magnet's modifier probe is gone or no longer reads SHIFT (P-BK-66) - "
                        "on CONTROL the terminal DUPLICATES the dragged handle instead "
                        "(«این باکس رو کپی میکنه») and the magnet can never fire")
    if "TERMINAL_KEYSTATE_CONTROL" in utils:
        problems.append("the magnet's modifier probe reads CONTROL again (P-BK-66) - Ctrl+drag is "
                        "MetaTrader's object-copy gesture, so the handle is cloned instead of "
                        "snapped")
    if grip is not None and "UIMagnetModifierDown()" not in grip:
        problems.append("the handle drag no longer asks UIMagnetModifierDown() by role (P-BK-66) - "
                        "moving the magnet to another key must stay a one-line change in the "
                        "one owner that probes it")
    if len(re.findall(r"BaseKnotGripSnapPrice\(", stripped)) > 2:
        problems.append("BaseKnotGripSnapPrice() is called from more than the handle gesture "
                        "(P-BK-61) - the magnet may never run inside the box' own drag")
    follow = body(src, "void BaseKnotFollowDrag(")
    if follow is not None and "BaseKnotGripSnap" in follow:
        problems.append("the magnet runs inside the box' live follow again (BKMAGNET2-OFF) - a "
                        "second writer beside the terminal's own drag (BKCURSOR-OFF/P-BK-15)")
    return problems


def check_mouse():
    """[mouse] - P-UI-73: one owner for the button, and release-only teardown.

    TWO defects of one family, both of which read as "the panel can't be dragged":

      * the physical left button was probed with BOTH MQL4 conventions (`< 0` in
        the panels, `& 1` in the domain). Each spelling is blind to the other, so
        on any given build one half of the safety net was dead code - either the
        stale-claim recovery could never fire (the card stays locked out for
        good) or a watchdog could decide the button was free mid-gesture;
      * the button-up finalizer ran on CHARTEVENT_CLICK *and*
        OBJECT_CLICK, and one of those is delivered ON the press that grabs an
        object (P-UI-49b's discovery). Running the teardown on a press echo
        clears the move claim in the instant it is made: the rest of the press
        drags nothing, only where such an echo can be produced.
    """
    problems = []
    utils = read(UTILS)
    # (signature, name, the sign test that convention A needs): the two owners
    # differ ONLY in which side of zero is "down", and BOTH must also test bit 0
    # (convention B) — a function carrying only one of the two readings is blind
    # to the other build lineage, which is the whole bug class.
    pairs = (("bool UILeftButtonDown(", "UILeftButtonDown", "(v<0)"),
             ("bool UILeftButtonUp(", "UILeftButtonUp", "(v>=0)"))
    for sig, nm, sign in pairs:
        blk = body(utils, sig)
        if blk is None:
            problems.append("%s() is gone - the ONE mouse-button owner must live "
                            "in Biotak/UtilityFunctions.mqh, below every surface "
                            "that asks it (P-UI-73)" % nm)
            continue
        flat = re.sub(r"\s+", "", blk)
        if sign not in flat or "(v&1)" not in flat:
            problems.append("%s() no longer answers under BOTH MQL4 conventions "
                            "(the `<0` and the bit-0 reading of "
                            "TERMINAL_KEYSTATE_LEFT) - one build lineage would "
                            "read it wrong again" % nm)
    for path in sorted(compiled_unit(ENTRY)):
        if os.path.basename(path) == os.path.basename(UTILS):
            continue
        txt = strip_comments(read(path))
        if "TERMINAL_KEYSTATE_LEFT" in txt:
            ln = txt[:txt.index("TERMINAL_KEYSTATE_LEFT")].count("\n") + 1
            problems.append("%s:%d reads TERMINAL_KEYSTATE_LEFT directly - every "
                            "probe must ask UILeftButtonDown()/UILeftButtonUp() "
                            "(P-UI-73)" % (os.path.basename(path), ln))
    fin = body(read(PANELS), "void ChartPointerFinalizeOnUps(")
    if fin is None:
        problems.append("ChartPointerFinalizeOnUps() is gone - a motionless "
                        "release would leak the chart lock (P-BK-03)")
    else:
        g = fin.find("UILeftButtonUp()")
        t = fin.find("UIDragBudgetEnd()")
        if g < 0:
            problems.append("the button-up finalizer tears live gestures down "
                            "without asking whether the button is really up: a "
                            "CLICK/OBJECT_CLICK delivered ON the press kills the "
                            "drag that press just started (P-UI-73)")
        elif t >= 0 and g > t:
            problems.append("the release gate in the finalizer sits AFTER the "
                            "teardown it is supposed to protect")
    allowed = body(read(PANELS), "bool PnlPressAllowed(")
    if allowed is None:
        problems.append("PnlPressAllowed() is gone")
    else:
        if "UILeftButtonDown()" not in allowed:
            problems.append("the stale-claim recovery reads the button itself "
                            "instead of the owner (P-UI-73)")
        if "g_MouseWasDown" not in allowed:
            problems.append("the stale-claim recovery no longer consults the "
                            "EVENT latch - a probe that reads \"down\" after the "
                            "button came up would keep a stale claim and lock "
                            "every coordinate control of the open card out for good")
    if body(read(MENU), "void CircAbortRingGesture(") is None:
        problems.append("CircAbortRingGesture() is gone - a long-press latch "
                        "armed before a card opened sits in FRONT of the modal "
                        "guard and swallows the next press (the card reads as "
                        "un-draggable, P-UI-73)")
    else:
        for tok, why in (("g_LongPressItem", "the latch itself"),
                         ("DragReleaseIf(DRAG_MENU)", "its DRAG_MENU claim"),
                         ("CircUnlockChart()", "its chart lock")):
            if tok not in body(read(MENU), "void CircAbortRingGesture("):
                problems.append("CircAbortRingGesture() does not take back %s" % why)
    popen = body(read(PANELS), "void PnlOpen(")
    if popen is not None and "CircAbortRingGesture()" not in popen:
        problems.append("PnlOpen() no longer takes the pointer away from the ring "
                        "(P-UI-73): the ring's long-press block runs BEFORE the "
                        "modal guard, so a latch armed before this card opened "
                        "steals the next press and the card cannot be dragged")
    return problems


def check_card_body():
    """[body] - the composed card body must cover the card it was drawn for.

    P-UI-71b: the wide body is `top cap + one band per pair-line + footer cap`,
    three pieces sliced from a baked skin. The arithmetic is the whole contract:
    if `PNL_CARD_TOP_H + pairN*PNL_ROW_H + PNL_CARD_BOT_H` drifts from the card's
    own height, the bottom of the card draws on the chart again - which is what
    the user reported (the colour row outside the panel).
    """
    problems = []
    text = read(PANELS)
    spec = card_specs(text)
    if not spec:
        return ["PnlSpecBuild() is gone - no card's body can be checked"]
    consts = {}
    for name in ("PNL_HEAD_H", "PNL_ROW_H", "PNL_FOOT_H", "PNL_MARGIN",
                 "PNL_CARD_TOP_H", "PNL_CARD_BOT_H", "PNL_FADE_H",
                 "PNL_SPEC_MAX"):
        m = re.search(r"#define\s+%s\s+([^\n/]+)" % name, text)
        if m is None:
            problems.append("%s is gone - the card body cannot be sized" % name)
            continue
        expr = m.group(1).strip()
        for other, val in consts.items():
            expr = re.sub(r"\b%s\b" % other, str(val), expr)
        expr = re.sub(r"[()\s]", "", expr)
        try:
            consts[name] = int(eval(expr, {"__builtins__": {}}))  # noqa: S307
        except Exception:
            problems.append("%s is not a number the gate can read (%r)"
                            % (name, m.group(1).strip()))
    if problems:
        return problems
    # 1. the pieces must tile the grid exactly
    if consts["PNL_CARD_TOP_H"] != consts["PNL_MARGIN"] + consts["PNL_HEAD_H"]:
        problems.append("PNL_CARD_TOP_H is not margin + header - the first band "
                        "would start off the row grid")
    if consts["PNL_CARD_BOT_H"] != consts["PNL_FOOT_H"] + consts["PNL_MARGIN"]:
        problems.append("PNL_CARD_BOT_H is not footer + margin - the footer cap "
                        "would not land on the card's footer")
    # 2. every card's spec must fit the slice
    worst = max(len(v) for v in spec.values())
    if consts["PNL_SPEC_MAX"] < worst:
        problems.append("PNL_SPEC_MAX is %d but a card declares %d display rows - "
                        "PnlSpecAdd() returns early and DROPS the extra rows with "
                        "no error anywhere" % (consts["PNL_SPEC_MAX"], worst))
    # 3. the composed body must equal the card's height, for every card
    icons = os.path.join(ROOT, "Files", "Icons")
    for item in sorted(spec):
        pairn = card_lines(spec[item], item)[-1] + 1
        card_h = consts["PNL_HEAD_H"] + pairn * consts["PNL_ROW_H"] + consts["PNL_FOOT_H"]
        composed = consts["PNL_CARD_TOP_H"] + pairn * consts["PNL_ROW_H"] \
            + consts["PNL_CARD_BOT_H"]
        if composed != card_h + 2 * consts["PNL_MARGIN"]:
            problems.append("card %d composes a %d px body for a %d px card "
                            "(+2x%d margin = %d) - the bottom would draw outside"
                            % (item, composed, card_h, consts["PNL_MARGIN"],
                               card_h + 2 * consts["PNL_MARGIN"]))
    # 4. the pieces must exist, at the sizes the composition assumes
    for name, want in (("pnl_cardWtop.bmp", consts["PNL_CARD_TOP_H"]),
                       ("pnl_cardWmid.bmp", consts["PNL_ROW_H"]),
                       ("pnl_cardWbot.bmp", consts["PNL_CARD_BOT_H"]),
                       ("pnl_cardWfade.bmp", consts["PNL_FADE_H"])):
        path = os.path.join(icons, name)
        if not os.path.exists(path):
            problems.append("%s is missing - run tools/slice-card-skins.py (a wide "
                            "card would draw with no body at all)" % name)
            continue
        with open(path, "rb") as fh:
            head = fh.read(26)
        w, h = struct.unpack_from("<ii", head, 18)
        if abs(h) != want:
            problems.append("%s is %d px tall, the composition expects %d"
                            % (name, abs(h), want))
    return problems


def check_dual():
    """P-UI-74: a card control answers on BOTH delivery channels, and the
    affordance list still exists exactly ONCE.

    The report this group exists for: tapping the ATR card's colour strip did
    nothing while the palette popover applied fine. The strip's pixels were
    measured against the shipped build and they land exactly where
    `PnlCsetHit` looks - so the control was not wrong, it was UNREACHABLE: a
    coordinate control lives on the press chain only, and that one channel can
    be eaten by a foreign claim, a missed MOUSE_MOVE, or (for a cell whose
    topmost object is the bitmap "glass" skin) never produce an OBJECT_CLICK
    at all. The fix gives every card control a second channel that re-enters the
    SAME dispatch, and these checks pin the shape of it.
    """
    problems = []
    panels = read(PANELS)
    click = body(panels, "int PnlHandleClick(")
    fall = body(panels, "bool PnlClickFallback(")
    act = body(panels, "void UIPressAct(")
    move = body(panels, "void PnlHandleMouseMove(")
    bridge = body(panels, "void HandleUIChartEvent(")
    if fall is None:
        problems.append("PnlClickFallback() is gone - every coordinate control "
                        "(switch pill, cset cell, section band, '+' chip) is "
                        "reachable from the press channel only")
        return problems
    if act is None:
        problems.append("UIPressAct() is gone - the one-gesture latch has no owner")
    # ONE affordance list: the click channel must RE-ENTER the press dispatch,
    # never re-implement it (a second list is P-UI-31's two-deciders shape, one
    # layer up).
    if "PnlHandleMouseMove(" not in fall:
        problems.append("the click channel no longer re-enters PnlHandleMouseMove - "
                        "the affordance list would exist twice and drift")
    for control in ("PnlClosePressHit(", "PnlKnobHit(", "PnlTrackHit(",
                    "PnlSwitchHit(", "PnlCsetHit(", "PnlDualHit(",
                    "PnlColorAddHit(", "PnlBandHit("):
        if control in fall:
            problems.append("the click channel re-implements %s instead of "
                            "dispatching through the one owner" % control.rstrip("("))
    # BOTH click events carry the second channel: a bitmap-skinned cell fires no
    # OBJECT_CLICK at all, so the plain CHARTEVENT_CLICK is the only event those
    # pixels ever produce.
    if click is None or "PnlClickFallback(" not in click:
        problems.append("PnlHandleClick never consults the click channel")
    if bridge is None or "PnlClickFallback(" not in bridge:
        problems.append("the plain CHARTEVENT_CLICK branch never dispatches the "
                        "card's controls - a click on a bitmap-skinned cell "
                        "(the colour strip) stays dead")
    # the latch, both halves
    if act is not None:
        if "s_PnlActedSeq" not in act or "g_UIPressSeq" not in act:
            problems.append("UIPressAct() does not latch the gesture to its press "
                            "identity - the twin event acts twice")
        if "s_PnlClickChannel" not in act or "UISuppressNextClick()" not in act:
            problems.append("UIPressAct() arms the release claim on the click "
                            "channel too: there is no release left to spend, so "
                            "it eats the NEXT genuine click (P-UI-65 over-eating)")
    if "PnlGestureConsumed()" not in fall:
        problems.append("the click channel ignores the latch - one gesture acts twice")
    if move is None or "s_PnlClickActed" not in move:
        problems.append("the press chain no longer consumes the click echo (the "
                        "click of the very press that grabbed the object, P-UI-49b)")
    # a released button must never start a drag (P-UI-75 moved the grab behind
    # PnlTryGrabMove, so the refusal is asserted at the call site)
    if move is None or "PnlTryGrabMove(" not in move:
        problems.append("PnlHandleMouseMove() is gone - the panel has no pointer engine")
    else:
        g = move.find("PnlTryGrabMove(")
        cond = move.rfind("if(", 0, g + 1)
        if cond < 0 or "s_PnlClickChannel" not in move[cond:g + 24]:
            problems.append("the card-body grab is not refused on the click channel - "
                            "a released button would start a move gesture and the "
                            "card would follow the next cursor move")
    # the popover's pixels belong to the popover, and the test has ONE owner
    # (P-UI-75) so the click channel and the grab cannot disagree about them
    pal = body(panels, "bool PnlPalettePointInside(")
    if pal is None:
        problems.append("PnlPalettePointInside() is gone - the popover's rect is "
                        "tested in more than one place again")
    else:
        if "g_PalX" not in pal or "PalH()" not in pal:
            problems.append("the popover rect owner does not bound the popover")
        grab = body(panels, "bool PnlTryGrabMove(")
        if grab is not None and "PnlPalettePointInside(" not in grab:
            problems.append("the grab can start a move on the floating palette's "
                            "own pixels")
    if "PnlPalettePointInside(cx,cy)" not in fall or "g_PalMixDrag" not in fall:
        problems.append("the click channel can steal a press that landed on the "
                        "floating palette / its mixer")
    if "PnlCardPointInside(" not in fall:
        problems.append("the click channel does not bound itself to the open card's "
                        "rect - it would act on chart clicks")
    # P-UI-69's law applied to the palette's OWN two id families: ids are parsed
    # EXACTLY (a prefix test made the '+' chip apply swatch 0).
    if 'StringFind(id,"s")==0' in panels or "StringFind(id,'s')==0" in panels:
        problems.append("a palette swatch id is prefix-tested again (the P-UI-69 'Q' bug)")
    if "PalMatIdParse(" not in panels or "PalRecentIdParse(" not in panels:
        problems.append("the palette swatch ids lost their exact parsers")
    ph = body(panels, "int PalHandleClick(")
    if ph is None:
        problems.append("PalHandleClick() is gone")
    elif "PalMatIdParse(" not in ph or "PalRecentIdParse(" not in ph:
        problems.append("PalHandleClick no longer uses the exact id parsers "
                        "(\"rempty\" would apply recent[0])")
    return problems


def check_heal():
    """P-UI-81: no panel gesture latch may survive the gesture that owns it.

    The report was «بعضی اوقات جابجا میشه ولی دیگه قفل میشه هیچی کار نمیکنه» —
    the card MOVED, and from then on every control of every card was dead until
    the indicator was re-attached. The mechanism is a LATCH, not a drag: while
    `g_PnlMoveItem` (or the slider / mixer latch) is set the move chain returns
    before its control block, and all three of the latch's exits need a witness
    the terminal may never deliver — a later move event carrying the release bit
    (MT4 emits none for a release that does not travel), the KEYSTATE probe (a
    heuristic), and the button-up finalizer, which is itself gated by that same
    probe. Lose all three in one gesture and the latch is permanent.

    The repair is the witness that cannot be missed: a press EDGE proves the
    previous gesture is over, so it must reap EVERY panel latch — each one
    through its OWN finish path (claim, budget and chart lock included) — before
    anything reads the state, and never on the click channel (that button is
    already up and must not kill a live drag).
    """
    panels = read(PANELS)
    problems = []
    reap = body(panels, "void PnlReapStaleGestures(")
    if reap is None:
        problems.append("PnlReapStaleGestures() is gone - one missed release "
                        "bricks every control of every card until re-attach "
                        "(P-UI-81)")
        return problems
    for latch, why in ((r"if\(g_PnlDragItem >= 0\)", "the slider drag"),
                       (r"if\(g_PalMixDrag > 0\)", "the palette mixer drag"),
                       (r"if\(g_PnlMoveItem >= 0\)", "the card move drag")):
        if not re.search(latch, reap):
            problems.append("the reaper forgets %s - that latch alone can still "
                            "brick every control of the panel (P-UI-81)" % why)
    if "PnlDragFinish(" not in reap:
        problems.append("the reaper clears the move latch INLINE - its claim, its "
                        "chart lock and its ledger line would be left behind "
                        "(P-UI-81)")
    for owner in ("DragReleaseIf(DRAG_PANEL_KNOB)", "UIDragBudgetEnd()",
                  "CircUnlockChart()"):
        if owner not in reap:
            problems.append("the reaper leaves %s behind for a knob/mixer "
                            "gesture - a second owner of the same state "
                            "(P-UI-81)" % owner)
    if "commitMove" not in reap:
        problems.append("the reap has no commit switch - a card closed under a "
                        "gesture would pin a spot, or a real drag would lose one")
    chain = body(panels, "void PnlHandleMouseMove(") or ""
    call = re.search(r"if\(pressStart && !s_PnlClickChannel\)\s*"
                     r"PnlReapStaleGestures\(", chain)
    if call is None:
        problems.append("the move chain no longer reaps on a press edge - the next "
                        "missed release bricks the panel again (P-UI-81)")
    else:
        head = chain.find("if(g_PalOpen)")
        if head < 0 or call.start() > head:
            problems.append("the reap runs AFTER the palette/drag branches - the "
                            "latch is read before it is healed (P-UI-81)")
    poll = body(panels, "void PnlDragPoll(") or ""
    if "PnlReapStaleGestures(" in poll:
        problems.append("the tick path reaps gestures - a poll would murder a "
                        "live drag (P-UI-81)")
    return problems


# ─────────────────────────────────────────────────────────────────────────────
# P-UI-91 (2026-09-14) — WHERE THE CARD OPENS IS NOW A DECISION, NOT A DEFAULT.
#
# The report: «حالا که جابجایی دستی حذف شده، جای باز شدن کارت را هوشمند کن تا با
# منوی رینگ و کندل‌ها اورلپ نکند» — with the drag retired (P-UI-90) the user can no
# longer pull a card off the price action by hand, so the first spot has to be
# right. This group is what keeps that a MEASUREMENT:
#   * the band is read from the VISIBLE window's own bars and mapped through the
#     terminal's own price→pixel call — never a fraction of the chart (the
#     guessed-geometry class this project keeps paying for: P-UI-69/71c/79);
#   * it stays ONE caller on the OPEN path — a placement that measures the chart
#     per frame would be a new always-on cost, which is exactly what P-UI-90
#     removed;
#   * the MENU rule stays HARD (a spot on the ring/orb can never win) while the
#     candle rule is the SCORE among survivors;
#   * a parked spot only survives while it passes the same two rules.
# Seeds 60-64 revert each half.
# ─────────────────────────────────────────────────────────────────────────────
def check_placement():
    problems = []
    panels = read(PANELS)
    pos = body(panels, "void PnlComputePosition(") or ""
    band = body(panels, "bool PnlCandleBandPx(") or ""
    ovl = body(panels, "int PnlIntervalOverlap(") or ""
    if not band:
        problems.append("PnlCandleBandPx() is gone - placement no longer knows "
                        "where the candles are, and with the card drag retired "
                        "(PANELDRAG-OFF) nothing can move a card off them "
                        "(P-UI-91)")
    else:
        for needle, why in (("WindowFirstVisibleBar",
                             "the band does not ask which bars are VISIBLE"),
                            ("WindowBarsPerChart",
                             "the band does not bound its scan to the window"),
                            ("iHigh(", "the band does not read the bars' highs"),
                            ("iLow(", "the band does not read the bars' lows"),
                            ("ChartTimePriceToXY",
                             "the band does not map price -> pixels through the "
                             "terminal's own mapping")):
            if needle not in band:
                problems.append("%s (P-UI-91)" % why)
        if "PNL_CANDLE_PAD" not in band:
            problems.append("the band's breathing room is a magic number again "
                            "instead of the declared margin (P-UI-91)")
        if re.search(r"(?m)^#define\s+PNL_CANDLE_PAD\s+\d+", panels) is None:
            problems.append("PNL_CANDLE_PAD is not declared as a constant, so the "
                            "margin cannot be reasoned about (P-UI-91)")
        if re.search(r"\bch\s*[*/]", band):
            problems.append("the candle band is GUESSED from the chart height "
                            "(a fraction) instead of measured from the bars - "
                            "the card would avoid a place the candles may not "
                            "be (P-UI-91)")
        if "if(vis > 0 && bars > vis) bars = vis;" not in band:
            problems.append("the band's scan is no longer clamped to the visible "
                            "window - it walks all history once per open "
                            "(P-UI-91)")
    if panels.count("PnlCandleBandPx(") != 2:
        problems.append("PnlCandleBandPx has %d sites (definition + the ONE call "
                        "in PnlComputePosition expected) - a placement that "
                        "measures the chart on a hot path is the always-on cost "
                        "P-UI-90 removed (P-UI-91)"
                        % panels.count("PnlCandleBandPx("))
    if "PnlCandleBandPx(cdTop, cdBot)" not in pos:
        problems.append("PnlComputePosition does not measure the band - the candle "
                        "rule is declared but never asked (P-UI-91)")
    if "valid[c] = !hits;" not in pos or \
            "cx + pw <= mbx - PNL_PAD_X" not in pos or \
            "cy + ph <= mby - PNL_PAD_X" not in pos:
        problems.append("the menu rule lost its rect test - a candidate can land "
                        "on the ring/orb again (P-UI-91)")
    if "if(valid[c] &&" not in pos:
        problems.append("the MENU rule went SOFT - a candidate that overlaps the "
                        "ring/orb can now win the score (P-UI-91)")
    if "PnlIntervalOverlap(candY[c], ph, cdTop, cdBot)" not in pos:
        problems.append("the candle score is not the MEASURED overlap of the "
                        "candidate with the band (P-UI-91)")
    if "hasBand ? PnlIntervalOverlap(" not in pos:
        problems.append("the band is not optional - a chart too young to "
                        "measure must keep the OLD placement, never a made-up "
                        "band (P-UI-91)")
    if "if(!parkMenuHit && parkOv == 0)" not in pos:
        problems.append("a parked spot is honoured without passing BOTH rules - "
                        "with the drag retired an unclean park is permanent "
                        "(P-UI-91)")
    if "PnlIntervalOverlap(manY, ph, cdTop, cdBot)" not in pos:
        problems.append("the parked spot is not scored against the candle band "
                        "(P-UI-91)")
    if not ovl or "hi > lo ? hi - lo : 0" not in ovl:
        problems.append("PnlIntervalOverlap no longer returns the measured "
                        "overlap (zero only when the intervals really are "
                        "disjoint) (P-UI-91)")
    return problems


# ─────────────────────────────────────────────────────────────────────────────
# PANELDRAG-OFF (2026-09-14) — THE CARD-MOVE GESTURE IS RETIRED, AND A
# RETIREMENT IS A STATE THIS AUDIT HAS TO BE ABLE TO SEE.
#
# User decision, on measured evidence: «درگ پنل تنظیمات حذف کنیم بهتر هستش الکی
# هزینه اضافی رو اندیکاتور فشار نیاد». The two entries are cut (the press chain's
# arm, the move branch, the poll's pump call) and three things must be true at
# once, or the retirement is a coat of paint:
#   1. the SITES are retired the project's way — commented in place with the
#      marker, never deleted (R-RETIRED), and no active arm / live branch / polled
#      call may exist;
#   2. the ENGINE stays COMPILED and dormant, so a restore is an uncomment and
#      not a rewrite (the TH3TOOL-OFF / VIEWLOCK-OFF pattern);
#   3. the retirement takes NOTHING ELSE with it: the relayout primitive the two
#      re-clamp paths use, the parked positions read on open, the press-edge heal
#      of the SLIDER / MIXER latches, and the finalizer's recency gate (which is
#      what keeps a press echo from tearing a live slider gesture down).
# Seeds 25 / 31 / 54 / 59 mutate exactly these sites.
# ─────────────────────────────────────────────────────────────────────────────
def check_paneldrag_off():
    problems = []
    panels = read(PANELS)
    util = read(UTILS)
    chain = body(panels, "void PnlHandleMouseMove(") or ""
    pump = body(panels, "void RefreshKitOnBar(") or ""
    fin = body(panels, "void ChartPointerFinalizeOnUps(") or ""
    if panels.count("PANELDRAG-OFF") < 3:
        problems.append("the card-move retirement lost its marker(s) - the next "
                        "session cannot tell a dormant engine from a live one "
                        "(PANELDRAG-OFF)")
    if "      // if(!s_PnlClickChannel) PnlTryGrabMove(mx,my,false);" not in chain:
        problems.append("the retired arm site is missing from the press chain - "
                        "the restore path is gone (PANELDRAG-OFF)")
    if re.search(r"(?m)^\s*(?:if\(!s_PnlClickChannel\)\s*)?PnlTryGrabMove\(mx,my,false\);", chain):
        problems.append("the press chain arms the removed card-move gesture - "
                        "half-restored (PANELDRAG-OFF)")
    if "if(false && g_PnlMoveItem >= 0)" not in chain:
        problems.append("the move branch is not dead by construction - the "
                        "removed gesture can still divert a held press "
                        "(PANELDRAG-OFF)")
    if re.search(r"(?m)^\s*if\(g_PnlMoveItem >= 0\)", chain):
        problems.append("a live move branch exists beside the retired arm "
                        "(PANELDRAG-OFF)")
    if re.search(r"(?m)^\s*//\s*PnlDragPoll\(\);", pump) is None:
        problems.append("the retired poll call is not in the pump (deleted, not "
                        "commented) - the restore path is gone "
                        "(PANELDRAG-OFF)")
    if re.search(r"(?m)^\s*PnlDragPoll\(\);", pump):
        problems.append("the poll is wired back into the tick/timer pump - the "
                        "removed gesture pays a KEYSTATE probe per tick and "
                        "armed nothing when it was live (PANELDRAG-OFF)")
    # 2. the engine must still be there to uncomment
    for fn in ("bool PnlTryGrabMove(", "void PnlDragStep(", "void PnlDragFinish(",
               "void PnlDragPoll(", "int PnlDragThreshPx(",
               "void PnlCommitMove(", "void PnlMoveBy(",
               "void PnlMoveListBuild(", "void PnlMoveListSync("):
        if body(panels, fn) is None:
            problems.append("the retired engine lost %s - a restore is a rewrite "
                            "again (PANELDRAG-OFF)" % fn.rstrip("("))
    # 3. and the retirement took nothing else with it
    if panels.count("PnlMoveBy(g_PnlOpen, ndx, ndy);") != 1:
        problems.append("the resize re-clamp no longer moves a card - the "
                        "retirement took the relayout primitive with it "
                        "(PANELDRAG-OFF)")
    if "g_PnlManualPos[item])" not in panels:
        problems.append("the parked positions are no longer read on open - "
                        "retiring the gesture must not relocate every card "
                        "(PANELDRAG-OFF)")
    if "if(pressStart && !s_PnlClickChannel) PnlReapStaleGestures(" not in chain:
        problems.append("the press-edge heal of the SLIDER / MIXER latches went "
                        "with the drag - one missed release bricks the panel "
                        "again (PANELDRAG-OFF)")
    if "!UILeftButtonUp() || !PnlPointerQuiet()" not in fin:
        problems.append("the finalizer's recency gate went with the drag - the "
                        "P-UI-49b press echo tears a live slider / mixer gesture "
                        "down again (PANELDRAG-OFF)")
    return problems


# ─────────────────────────────────────────────────────────────────────────────
# P-TH-01 (2026-09-18) — the TH-percentage research knob's ENGINE half.
#
# WHY IT NEEDS A GATE OF ITS OWN
# The [rows] / [persist] / [relayout] checks above already prove the PANEL half:
# the row exists, it reads, it writes, it is saved, it asks for a relayout. What
# none of them can see is whether the number the slider writes ever reaches the
# LADDER THE CHART DRAWS — the P-UI-47 shape ("a slider that writes a mirror the
# engine never reads"), one layer deeper. And there is a second, quieter failure
# the panel half cannot see at all: a LATER reader scaling the two sites that
# must stay raw, which re-picks `g_fractalShift` — and with it the Structure TF
# and the whole zone hierarchy — every time the research knob moves. That is the
# confound the user's own rule forbids («بقیه دست نمیخوره روابطه به جایی 66 دیگه
# چیزها میاد»), and it would be invisible on the chart.
#
# THE MODEL: one knob -> one ratio -> one ladder.
#   `g_thPercentOverride` is read in EXACTLY one function
#   (`FractalPercentScale()`, FractalTimeframes.mqh) and turns into the ratio
#   every rung is multiplied by; `FractalPercentScaled()` is the only reader the
#   drawing paths may use. The professor's table is never edited, so 0 = OFF is
#   byte-for-byte the shipped ladder.
# ─────────────────────────────────────────────────────────────────────────────

#--- every path that resolves a rung INTO a percentage the chart draws. These
#--- MUST go through the knob (a raw read here is the knob doing nothing).
TH_PERCENT_DRAW_SITES = (
    ("FractalTimeframes.mqh", "double result = FractalPercentScaled(targetIndex);"),
    ("FractalTimeframes.mqh", "return FractalPercentScaled(i);"),
    ("THCalculations.mqh", "double percentage = FractalPercentScaled(i);"),
    ("LabelFunctions.mqh", "double percentage = FractalPercentScaled(i);"),
)

#--- ...and the two readers that must stay on the RAW table. They answer "which
#--- rung of the PROFESSOR's ladder matches this ATR / this frequency" — a
#--- measuring stick, not the drawn ladder.
TH_PERCENT_RAW_SITES = (
    ("AdaptiveScaling.mqh", "double p = MODIFIED_FRACTAL_PERCENTAGES[i];"),
    ("FrequencyOptimizer.mqh", "double fracPct = MODIFIED_FRACTAL_PERCENTAGES[f];"),
)

TH_PERCENT_OWNER = "FractalTimeframes.mqh"
#--- RuntimeSettings owns the mirror (seed / redirect / persist / restore) and
#--- BiotakPanels owns the ROW (display the value, write it back). Both are the
#--- knob's own plumbing. Everything else is the ENGINE, and the engine must go
#--- through the ratio — a module that reads the raw mirror has its own ladder.
TH_PERCENT_EXEMPT = (TH_PERCENT_OWNER, "RuntimeSettings.mqh", "BiotakPanels.mqh")


def check_th_percent():
    """[th-percent] - the research knob reaching the ladder, and ONLY the ladder."""
    problems = []
    src = {}
    for name in sorted(os.listdir(os.path.join(ROOT, "Biotak"))):
        if name.endswith(".mqh"):
            src[name] = read(os.path.join(ROOT, "Biotak", name))
    owner = src.get(TH_PERCENT_OWNER)
    if owner is None:
        return ["%s is gone - the TH percentage knob has no owner" % TH_PERCENT_OWNER]

    # 1. ONE owner. A second module reading the mirror is a second ladder: the
    #    two would disagree the moment either one changed.
    for name in sorted(src):
        if name in TH_PERCENT_EXEMPT:
            continue
        for i, line in enumerate(strip_comments(src[name]).splitlines(), 1):
            if "g_thPercentOverride" in line:
                problems.append("%s:%d reads g_thPercentOverride outside its ONE "
                                "owner (%s) - a second ladder that can disagree "
                                "with the first (P-TH-01)"
                                % (name, i, TH_PERCENT_OWNER))

    # 2. the ratio itself exists, and 0 really is OFF. The OFF path is spelled
    #    out rather than left to arithmetic: "0 = the professor's table byte for
    #    byte" is the knob's contract with every existing chart, and a ratio of
    #    1.0 is what makes `x * 1.0` bit-identical to `x`.
    for need in ("double FractalPercentScale()", "double FractalPercentScaled(",
                 "double FractalPercentRaw("):
        if need not in strip_comments(owner):
            problems.append("%s lost %s - the knob no longer turns into ONE ratio "
                            "(P-TH-01)" % (TH_PERCENT_OWNER, need))
    if "if(g_thPercentOverride <= 0.0) return 1.0;" not in strip_comments(owner):
        problems.append("%s lost the knob's OFF path - 0 must mean the professor's "
                        "table byte for byte, not a scaled ladder (P-TH-01)"
                        % TH_PERCENT_OWNER)

    # 3. every DRAWING reader goes through the knob
    for name, snip in TH_PERCENT_DRAW_SITES:
        if snip not in strip_comments(src.get(name) or ""):
            problems.append("%s no longer resolves its rung through "
                            "FractalPercentScaled (%r) - the slider would move and "
                            "the chart would not (P-TH-01)" % (name, snip))

    # 4. the measuring sticks stay raw, and say so
    for name, snip in TH_PERCENT_RAW_SITES:
        body_t = strip_comments(src.get(name) or "")
        if snip not in body_t:
            problems.append("%s no longer reads the professor's table raw (%r) - it "
                            "is a MEASURING STICK: 'which rung matches the "
                            "ATR/frequency', not the drawn ladder (P-TH-01)"
                            % (name, snip))
        if "FractalPercentScaled" in body_t:
            problems.append("%s now follows the research knob - scaling a measuring "
                            "stick re-picks g_fractalShift (and the Structure TF and "
                            "the zone hierarchy) under the knob, which is the "
                            "confound P-TH-01 must not introduce" % name)

    # 5. the panel row writes the mirror, invalidates the CACHED percentage, and
    #    asks for the relayout the label pass needs. `CalculateTimeframeTH` stores
    #    what it resolved, so a knob change without the invalidation keeps drawing
    #    the OLD ladder until an unrelated event clears it.
    panels_t = strip_comments(src.get("BiotakPanels.mqh") or "")
    # `item_block` -> `body` needs the line-start DEFINITION, so the FULL text
    # goes in and only the returned arm is stripped.
    arm = strip_comments(item_block(src.get("BiotakPanels.mqh") or "",
                                    "PnlApplySet(", 3) or "")
    cut = arm.find("row==5")
    stop = arm.find("break;", cut) if cut >= 0 else -1
    seg = arm[cut:stop] if cut >= 0 and stop > cut else ""
    if not seg:
        problems.append("the TH PERCENT row (card 3, setting 5) has no PnlApplySet "
                        "branch - the slider is decoration (P-TH-01)")
    else:
        if "g_thPercentOverride" not in seg:
            problems.append("the TH PERCENT row no longer writes g_thPercentOverride "
                            "(P-TH-01)")
        if "InvalidateTimeframeDependentCaches()" not in seg:
            problems.append("the TH PERCENT row no longer invalidates the cached "
                            "rung->percentage - the chart would keep drawing the OLD "
                            "ladder until an unrelated event cleared the cache "
                            "(P-TH-01)")
        if "g_labelsRelayoutNeeded=true" not in seg:
            problems.append("the TH PERCENT row no longer asks for a relayout - the "
                            "TH label strip is drawn by the label pass, so the knob "
                            "would move the lines and not the numbers beside them "
                            "(P-TH-01)")

    # 6. ONE bound. The slider's end stop and the persisted-override clamp must
    #    name the same constant, or a saved value is unreachable on the slider
    #    (the P-UI-70d rule: a slider whose max is past the engine's clamp stops
    #    responding at the end of its travel).
    consts = read(os.path.join(ROOT, "Biotak", "ConstantsAndEnums.mqh"))
    if "#define TH_PERCENT_OVERRIDE_MAX" not in consts:
        problems.append("TH_PERCENT_OVERRIDE_MAX is gone from ConstantsAndEnums.mqh "
                        "- the knob's one bound has no owner (P-TH-01)")
    if "maxV=TH_PERCENT_OVERRIDE_MAX" not in panels_t:
        problems.append("the TH PERCENT slider no longer names TH_PERCENT_OVERRIDE_MAX "
                        "as its max - a range that repeats a number is a range that "
                        "drifts from its clamp (P-TH-01)")
    settings_t = strip_comments(src.get("RuntimeSettings.mqh") or "")
    if not re.search(r'GlobalVariableCheck\(p \+ "TPC"\)', settings_t):
        problems.append("the TH percentage is no longer restored from its override "
                        "key (TPC) - the research value would die with the session "
                        "(P-TH-01)")
    if "TH_PERCENT_OVERRIDE_MAX" not in settings_t:
        problems.append("the restore no longer clamps through TH_PERCENT_OVERRIDE_MAX "
                        "(P-TH-01)")
    return problems



# ─────────────────────────────────────────────────────────────────────────────
# P-UI-98 / P-UI-99 (2026-09-21) — THE FIRST STEP IS DRAGGABLE, AND THE HOLD
# IS RETIRED.
#
# P-UI-98: in custom-price start-point mode the rung-1 trigger lines are the
# user's step handle. User order: «در مود کاستوم پرایس step اول قابل ویرایش
# باشه که کاربر با درگ کردن از همون جا گام دلخواهشو در تمام مود ها بتونه اعمال
# بکنه که به صورت خودکار با همون نسبت ها در تایم ها دیگه اعمال بشه ... فقط
# step اول قابل ویرایش باشه بقیه نه». The rules that make it real:
#   1. the handle match is EXACT and selective — custom-price mode only, the
#      _Zone_ rectangles excluded, the step number suffix-exact;
#   2. the drag math divides by the F-FREE natural first step the factory
#      noted (no second copy of the per-mode first-step logic);
#   3. ONE factor multiplies the factory's step sizes (the SS/LS pair keeps
#      its ratio) — and the geometry signature carries it, or a drag reads as
#      the same picture (the P-UI-52 trap with a new seat);
#   4. the render skips the dragged line's own writes (P-BK-15) — and the
#      selectability face is owned in that refresh path, step 1 ONLY;
#   5. the release settles: forced frame, deselect, the view back — and the
#      stale-drag heal drops the flags a lost release would pin forever;
#   6. the override is the placement's property — it resets with it, dies on
#      REASON_REMOVE, and the R reset clears it;
#   7. the override has ONE writer, bounded, chart-scoped.
# P-UI-99: the custom-price line's hold-to-arm is RETIRED by user order
# («اون هولد از خط کاستوم پرایس بردار ... کلیک شو بقیه ابجکت ها در حین درگ
# کردن روش ندزده») — the claim is immediate and the select/deselect pair
# carries the comfort. A retirement is a state this audit must see: no hold
# define, no hold statics, the immediate claim and the foreign-drag drain both
# present.
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# P-UI-98 / P-UI-98d / P-UI-99 (2026-09-21) — THE FIRST STEP IS DRAGGABLE, THE
# HAND-SET LINES ARM/SET, AND THE HOLD IS RETIRED.
#
# P-UI-98: in custom-price start-point mode the rung-1 trigger lines are the
# user's step handle. User order: «در مود کاستوم پرایس step اول قابل ویرایش
# باشه که کاربر با درگ کردن از همون جا گام دلخواهشو در تمام مود ها بتونه اعمال
# بکنه که به صورت خودکار با همون نسبت ها در تایم ها دیگه اعمال بشه ... فقط
# step اول قابل ویرایش باشه بقیه نه». The rules that make it real:
#   1. the handle match is EXACT and selective — custom-price mode only, the
#      _Zone_ rectangles excluded, the step number suffix-exact;
#   2. the drag math divides by the F-FREE natural first step the factory
#      noted (no second copy of the per-mode first-step logic);
#   3. ONE factor multiplies the factory's step sizes (the SS/LS pair keeps
#      its ratio) — and the geometry signature carries it, or a drag reads as
#      the same picture (the P-UI-52 trap with a new seat);
#   4. the render skips the dragged line's own writes (P-BK-15), the face is
#      owned AFTER the guarded creator (its fresh objects are born
#      non-selectable — the reported «الان step اول قابل درگ کردن نیستش»),
#      and the handle sits at a z-order above the zone fills that would
#      otherwise eat the grab;
#   5. the release settles: forced frame, deselect, the view back — the
#      stale-drag heal drops the flags a lost release would pin forever;
#   6. the override is the placement's property — it resets with it, dies on
#      REASON_REMOVE, and the R reset clears it;
#   7. the override has ONE writer, bounded, chart-scoped.
# P-UI-98d: the ARMED/SET contract — «وقتی بعد جابجایی روش کلیک شد ست نهایی
# بشه و با دبل کلیک فعال بشه؛ تا زمانی که ست نهایی نشده آزادنه درگ بشه». A
# single click SETS (deferred past the double-click window in the pending
# slots; the sweep commits — the sweep that rides BOTH always-on channels),
# a double-click re-arms, a drag's own click echo sets nothing, and a SET line
# is inert so no other object's drag can steal it. The markers are ONE small
# dot per line at the right edge (green custom line, red step-1 — «یک نشانه
# باشه که خیلی مزاحم هم نباشه»), they obey the LINES switch («وقتی لاین ها رو
# خاموش میکنم نشان ها هم نباشه»), and a SET line's dot is DELETED, not masked,
# so no mask writer can resurrect it.
# P-UI-99: the custom-price line's hold-to-arm is RETIRED by user order
# («اون هولد از خط کاستوم پرایس بردار ... کلیک شو بقیه ابجکت ها در حین درگ
# کردن روش ندزده») — the claim is immediate and ARMED-gATED, and the
# select/deselect pair carries the comfort. A retirement is a state this
# audit must see: no hold define, no hold statics, the immediate claim and
# the foreign-drag drain both present.
# ─────────────────────────────────────────────────────────────────────────────
def check_step1():
    problems = []
    events = read(EVENTS)
    glob = read(GLOBALS)
    pipe = read(PIPELINE)

    def body(src, head):
        i = src.find(head)
        if i < 0:
            return ""
        j = src.find("\n}", i)
        return src[i:j if j > 0 else len(src)]

    # 1. the handle match  (P-UI-98f: the render's own stash names the pair)
    match_fn = body(events, "bool Step1LineIsDragHandle(")
    if not match_fn:
        problems.append("Step1LineIsDragHandle() is gone - no drag handle, no "
                        "editable first step (P-UI-98)")
    else:
        if "TH_START_POINT_CUSTOM_PRICE" not in match_fn:
            problems.append("the handle match forgot the custom-price gate - a "
                            "computed midpoint ladder would be draggable too, "
                            "and its step cannot be set by hand (P-UI-98)")
        if ("g_s1MarkAboveName" not in match_fn or
                "g_s1MarkBelowName" not in match_fn):
            problems.append("the handle match no longer asks the render's own "
                            "stash - the handle is the line ONE STEP from the "
                            "custom price, which is _Above_1 above but _Below_2 "
                            "below, so no name-tail rule can name it and the "
                            "channels would answer a different line than the "
                            "one the pick chose (P-UI-98f)")
        if "g_s1MarkPeriod != Period()" not in match_fn:
            problems.append("the handle match answers another timeframe's pair "
                            "again - the stashed handle belongs to the TF it "
                            "was drawn on (P-UI-98e)")
        if "StringSubstr(name, len - 8, 8)" in match_fn:
            problems.append("the retired name-tail match is back - a suffix "
                            "cannot name _Below_2, so the below handle would be "
                            "invisible to the drag, the click and the "
                            "terminal's own channel (P-UI-98f)")

    # 1b. P-UI-98f: WHICH LINE IS THE HANDLE, AND ON WHICH SIDE.
    pick_fn = body(pipe, "void Step1HandlePick(")
    if not pick_fn:
        problems.append("Step1HandlePick() is gone - the handle is chosen by "
                        "rung number again, and the ladder's below rung 1 is "
                        "the line drawn ON the custom price line (P-UI-98f)")
    else:
        if "stepNow * 0.5" not in pick_fn:
            problems.append("a line drawn on the custom price line can carry "
                            "the step-1 handle again - its red icon lands on the "
                            "green one (the reported «اون قرمز خیلی نزدیک کاستوم "
                            "پرایس») and a hair of a downward drag collapses the "
                            "ladder to a fraction of a step (P-UI-98f)")
        if "MathAbs(dist - stepNow)" not in pick_fn:
            problems.append("the pick no longer chooses the line nearest ONE "
                            "step from the custom price (P-UI-98f)")
        if "lines[i].direction" not in pick_fn:
            problems.append("the pick no longer answers one handle per SIDE - "
                            "one line would shadow the other and a drag would "
                            "move the wrong side (P-UI-98f)")
    if ("Step1HandlePick(lines, lineCount, GetMidpointPrice(g_thStartPointType),"
            not in pipe):
        problems.append("the render does not pick the handle off the custom "
                        "price line's own anchor (P-UI-98f)")
    if "StepOverrideFactor() * NaturalFirstStep()" not in pipe:
        problems.append("the pick measures against a step of its own instead of "
                        "the project's ONE current step (F x the F-free natural "
                        "first step) - the picked pair could change mid-drag and "
                        "hand the gesture to another line (P-UI-98f)")
    if "lines[i].name == s1AboveName || lines[i].name == s1BelowName" not in pipe:
        problems.append("the render's face gate is not the picked pair - the "
                        "handle and the drag/click channels would answer "
                        "different lines (P-UI-98f)")
    if "lines[i].logicalStep == 1" in pipe:
        problems.append("the retired rung-1 gate is back in the render - the "
                        "ladder's below rung 1 IS the custom price line "
                        "(P-UI-98f)")
    above_fn = body(events, "bool Step1LineIsAbove(")
    if not above_fn:
        problems.append("Step1LineIsAbove() is gone - the drag math has to read "
                        "the side off a name tail again, and the below handle is "
                        "not _Below_1 (P-UI-98f)")
    hit_fn = body(events, "bool Step1HandleUnderCursor(")
    if not hit_fn:
        problems.append("Step1HandleUnderCursor() is gone - the press never "
                        "names the handle it landed on (P-UI-98e)")
    elif "g_s1MarkPeriod != Period()" not in hit_fn:
        problems.append("the press can be answered by another timeframe's "
                        "stash - the handle belongs to the TF it was drawn on "
                        "(P-UI-98e)")

    # 2. the drag math
    apply_fn = body(events, "void Step1LineDragApply(")
    if not apply_fn:
        problems.append("Step1LineDragApply() is gone - the drag events have no "
                        "owner (P-UI-98)")
    else:
        if "NaturalFirstStep()" not in apply_fn:
            problems.append("the drag math re-derives the first step instead of "
                            "reading the factory-noted F-free one - a second "
                            "copy of the per-mode logic that will drift "
                            "(P-UI-98)")
        if "StepOverrideFactorSet(" not in apply_fn:
            problems.append("the drag does not write the override through its "
                            "ONE writer (P-UI-98)")
        if "CustomPriceDragFrame(" not in apply_fn:
            problems.append("the drag runs its own redraw budget instead of "
                            "sharing the custom-price drag's ONE frame owner "
                            "(P-UI-61 / P-UI-98)")
        if "newFirst < _Point" not in apply_fn:
            problems.append("the wrong-side drop is not refused - a step across "
                            "the start is not a small step, it is no step "
                            "(P-UI-98)")
        if "bool above = Step1LineIsAbove(name);" not in apply_fn:
            problems.append("the drag math still decides the side by name tail - "
                            "the below handle is _Below_2, so it would be read "
                            "as the above one and the sign of the drag would "
                            "invert (P-UI-98f)")
        if "s_s1GrabDist = MathAbs(dragged - start);" not in apply_fn:
            problems.append("the drag takes no press baseline - every mode "
                            "whose drawn pair does not sit at EXACTLY one step "
                            "(SS/LS, Factor) would snap the ladder the instant "
                            "the hand closed, and a phantom drag would "
                            "re-scale it (P-UI-98f)")
        elif "s_s1GrabFactor * (newFirst / s_s1GrabDist)" not in apply_fn:
            problems.append("the drag no longer scales the factor relative to "
                            "the grab - the handle does not keep its own offset "
                            "from the custom price line (P-UI-98f)")

    # 2b. P-UI-98f: the carry's stand-down must ask "is the terminal STILL
    # moving it", not "does the price differ from our last write".
    move_fn = body(events, "void Step1HandleOwnDragMove(")
    if not move_fn:
        problems.append("Step1HandleOwnDragMove() is gone - the handle's own "
                        "carry has no owner (P-UI-98e)")
    else:
        if "bool terminalLive" not in move_fn or "s_s1SeenPrice = current;" not in move_fn:
            problems.append("the carry stands down on 'the price differs from my "
                            "last write' instead of 'the terminal moved it since "
                            "the previous event': MT4's armed drag ends as soon as "
                            "the claim borrows SELECTABLE, so a price it moved ONCE "
                            "leaves the carry standing down with nobody moving the "
                            "line - «هی قطع میشه موقع درگ کردن» (P-UI-98f)")
        if "s_s1SeenPrice = wishPrice;" not in move_fn:
            problems.append("the carry does not record its own write as the seen "
                            "price - the next event reads its own write as the "
                            "terminal moving the line and stands down again "
                            "(P-UI-98f)")

    # 2c. the gesture's own state has ONE clear owner, and it runs after the
    # echo stamp (which reads the base it clears).
    settle_fn = body(events, "void Step1DragSettle(")
    heal_fn = body(events, "void CustomPriceDragHealStale(")
    for b, who in ((settle_fn, "the settle"), (heal_fn, "the stale-drag heal")):
        if not b or "Step1GestureStateClear()" not in b:
            problems.append("%s does not clear the gesture's own state through its "
                            "ONE owner - a path that leaves the grab base, the "
                            "press baseline and the seen price behind poisons the "
                            "NEXT gesture (P-UI-98f)" % who)
    if settle_fn and "Step1GestureStateClear()" in settle_fn and \
            "g_s1JustDraggedMs = GetTickCount();" in settle_fn and \
            settle_fn.index("Step1GestureStateClear()") < \
            settle_fn.index("g_s1JustDraggedMs = GetTickCount();"):
        problems.append("the settle clears the gesture's state BEFORE its echo "
                        "stamp - the stamp reads the grab base the clear wipes, so "
                        "no drag is ever recognised as one and every release SETs "
                        "the handle it just moved (P-UI-98f)")

    # 3. the factory application + the signature term
    if "NaturalFirstStepNote(def.stepSizes[s1FirstIdx]);" not in events:
        problems.append("the factory's natural first step is not noted - the "
                        "drag denominator would be zero or stale (P-UI-98)")
    if "def.stepSizes[s1i] *= s1Factor;" not in events:
        problems.append("the override no longer multiplies the factory's step "
                        "sizes - the dragged step would not reach the ladder "
                        "(P-UI-98)")
    if "DoubleToString(StepOverrideFactor(), 6)" not in events:
        problems.append("the geometry signature dropped the override term - a "
                        "drag would read as the same picture and the ladder "
                        "would not move until a forced frame (P-UI-52 / "
                        "P-UI-98)")

    # 3b. P-UI-98g — THE CIRCLES COME WHEN YOU CLICK («فقط وقتی روش کلیک کردیم
    # دایره ها بیاد برای درگ کردن»): ARMED is not SHOWN. Every circle owner asks
    # the reveal latch, the click writes it on BOTH lines, our own drags reveal as
    # well (a hand on the line is the loudest request), and a SET, a fresh
    # placement and the placement's teardown all take it away again.
    markers_fn = body(events, "void CustomPriceMarkerSync(")
    choose_fn = body(events, "bool Step1HandleOwnClaim(")
    arm_fn = body(events, "void HandsetPlacementArm(")
    sweep_fn = body(events, "void HandsetClickSweep(")
    teardown_fn = body(events, "void CleanupCustomPriceObjects(")
    ride_fn = body(events, "void HandsetMarkersRide(")
    reveal_checks = (
        # P-UI-98q: the green circle IS the placement's face (the line is never
        # painted): it shows whenever the placement is live, with no reveal
        # latch and no LINES switch. The latch survives only as the armed
        # click-flow state, never as a visibility term.
        (markers_fn and "bool show = g_customPriceLineCreated &&" in markers_fn and
         "g_cpHandleShown" not in markers_fn and "g_linesVisible" not in markers_fn,
         "CustomPriceMarkerSync gates the green circle on the reveal latch or "
         "the LINES switch again - a live placement shows no marker until "
         "clicked, or hides it with the line family (P-UI-98q)"),
        (ride_fn and "g_s1HandleShown" in ride_fn,
         "the ride channel places the red circles without the reveal latch - a "
         "pan resurrects a handle the user never asked for (P-UI-98g)"),
        ("    if(!g_cpHandleShown)\n" in events,
         "the click on the custom price line no longer brings the green handle "
         "up - armed-but-unshown would have no way to become shown (P-UI-98g)"),
        (choose_fn and "g_cpHandleShown = true;" in events,
         "a drag of the custom price line no longer reveals its handle - the "
         "hand is on the line and no circle comes (P-UI-98g)"),
        (choose_fn and "g_s1HandleShown = true;" in choose_fn,
         "a drag of a step-1 line no longer reveals its handle - the hand is on "
         "the line and no circle comes (P-UI-98g)"),
        (arm_fn and "g_cpHandleShown = false;" in arm_fn and
         "g_s1HandleShown = false;" in arm_fn,
         "a fresh placement is no longer born hidden - the circles are back the "
         "moment the line is placed (P-UI-98g)"),
        (sweep_fn and "g_s1HandleShown = false;" in sweep_fn,
         "a SET no longer takes the red circles away - nothing may point at a "
         "line nothing can grab (P-UI-98g)"),
        (sweep_fn and "g_cpHandleShown = false;" in sweep_fn,
         "a SET no longer takes the green circle away (P-UI-98g)"),
        (teardown_fn and "g_cpHandleShown = false;" in teardown_fn and
         "g_s1HandleShown = false;" in teardown_fn,
         "the placement's teardown leaves the reveal latches set - the next "
         "placement inherits a shown handle it never asked for (P-UI-98g)"),
    )
    for ok, msg in reveal_checks:
        if not ok:
            problems.append(msg)

    # 3c. P-UI-98m - A SET CUSTOM LINE IS HIDDEN, ITS GREEN CIRCLE IS THE
    # MARKER («وقتی سلکت نیس فقط دایره سبز بمونه»). A masked line fires no
    # OBJECT_CLICK, so the re-arm is a row-based click contract (the press
    # edge records, the button-up and CHARTEVENT_CLICK edges ask it, the
    # circle's own click is the third edge), and a single click is a no-op -
    # only a double re-arms.
    cpmark_fn = body(events, "void CustomPriceMarkerSync(")
    ownarm_fn = body(events, "void CustomPriceLineOwnArm(")
    creator_fn = body(events, "bool CreateCustomPriceLine(")
    rearm_fn = body(events, "void CustomPriceRearmClickAt(")
    rearmfin_fn = body(events, "void CustomPriceRearmFinalize(")
    # P-UI-98q: the green raster reads one size up (19 px) and centres with
    # its own half; the grab tolerance covers the visible circle.
    hath_fn = body(glob, "void HandsetHandleAt(")
    if "#define CP_HANDLE_HALF       9" not in glob:
        problems.append("the green circle lost its own half: a 19 px raster "
                        "centred with the reds' half sits off its price "
                        "(P-UI-98q)")
    if "CP_HANDLE_HALF : HANDSET_HANDLE_HALF" not in (hath_fn or ""):
        problems.append("the projector centres every raster with one half: "
                        "the bigger green circle is mis-centred (P-UI-98q)")
    # P-UI-98o: the green circle ignores the LINES switch - it marks the
    # placement itself, so L hides the lines and the red circles but never it.
    if "g_linesVisible" in (cpmark_fn or ""):
        problems.append("the green circle obeys the LINES switch: with lines "
                        "off (L key) the custom price marker disappears with "
                        "them, though it marks the placement itself (P-UI-98o)")
    if "armMask" in (ownarm_fn or "") or "OBJ_ALL_PERIODS" in (ownarm_fn or "") or \
            "OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS" not in (ownarm_fn or ""):
        problems.append("the transition paints the custom line again: it is "
                        "never painted (the green circle is the placement), "
                        "the mask is only ever re-asserted (P-UI-98p)")
    if "armMask" in (creator_fn or "") or "OBJ_ALL_PERIODS" in (creator_fn or "") or \
            "OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS" not in (creator_fn or ""):
        problems.append("the creator paints the custom line: a fresh line "
                        "arrives visible though the line is never painted "
                        "(P-UI-98p)")
    showall_fn = body(events, "int ApplyHideAllState(")
    if "g_customPriceHorizontalLineName" in (showall_fn or ""):
        problems.append("the F show path resurrects the custom line: it is "
                        "never painted in any state (P-UI-98p)")
    # P-UI-98p: NEVER-PAINTED, enforced every frame. The creator and the
    # transition skip mid-gesture, and a stuck gesture flag births the next
    # line visible - one guarded read per frame re-masks on drift.
    if "if(lineExists &&" not in events:
        problems.append("the never-painted mask has no per-frame enforcer: a "
                        "line leaked visible (stuck gesture flag at creation, "
                        "profile restore) stays painted (P-UI-98p)")
    if not rearm_fn:
        problems.append("CustomPriceRearmClickAt() is gone - a masked SET "
                        "line fires no OBJECT_CLICK, so nothing can re-arm it "
                        "any more (P-UI-98m)")
    else:
        for needle, why in (
            ("if(g_cpLineArmed) return;",
             "an armed press would enter the re-arm contract beside the "
             "line's own click owner"),
            ("ObjectFind(0, g_customPriceHorizontalLineName) < 0",
             "re-arming a deleted line arms nothing"),
            ("g_cpClickHandledMs",
             "one physical click reaches two edges and reads as a double"),
            ("if(!dbl) return;",
             "a single click re-arms: the first click of a double fires "
             "first, and a deliberate look costs a drag"),
            ("CustomPriceLineOwnArm(true);",
             "the re-arm never transitions the line")):
            if needle not in rearm_fn:
                problems.append("the custom re-arm owner lost '%s': %s (P-UI-98m)"
                                % (needle, why))
    if not rearmfin_fn or "if(!g_cpClickArmed) return;" not in rearmfin_fn or \
            "if(!UILeftButtonUp()) return;" not in rearmfin_fn:
        problems.append("the still click on a SET line never finalizes: a "
                        "motionless press/release emits no MOUSE_MOVE "
                        "(P-BK-03 / P-UI-98m)")
    if "if(id == CHARTEVENT_CLICK) CustomPriceRearmFinalize();" not in events:
        problems.append("the CHARTEVENT_CLICK edge never reaches the custom "
                        "re-arm finalize (P-UI-98m)")
    if "if(pixelHit && !g_cpLineArmed)" not in events:
        problems.append("the press edge records no re-arm candidate on a SET "
                        "line: the row nobody can click wakes nothing "
                        "(P-UI-98m)")
    if "if(g_cpClickArmed)" not in events:
        problems.append("the button-up never asks the re-arm candidate "
                        "(P-UI-98m)")
    if "sparam == g_cpMarkerName" not in events:
        problems.append("the green circle's own click never reaches the "
                        "re-arm owner (P-UI-98m)")

    # 4. the render side: face AFTER creation, above the zones, dot owned
    face_fn = body(pipe, "void Step1HandleOwnFace(")
    if not face_fn:
        problems.append("the selectability face has no owner in the render - "
                        "a state that changed under the chart is never "
                        "re-owned (P-UI-98)")
    else:
        if "TH_START_POINT_CUSTOM_PRICE" not in face_fn:
            problems.append("the face owner does not gate selectability on the "
                            "custom-price mode (P-UI-98)")
        if "OBJPROP_SELECTABLE" not in face_fn or "OBJPROP_SELECTED" not in face_fn:
            problems.append("the face owner no longer writes the select/"
                            "deselect pair (P-UI-98)")
        if "ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_CHART_LABEL)" not in face_fn:
            problems.append("the handle lost its z-order above the zone fills - "
                            "a rectangle under the cursor eats the grab and "
                            "step 1 is not draggable again (P-UI-98)")
        if "S1MarkName(" not in face_fn or "S1_HANDLE_RES" not in face_fn:
            problems.append("the step-1 marker handle has no owner in the face - "
                            "the red circular drag icon the user asked for is "
                            "gone (P-UI-98d v2)")
        if "HandsetHandleAt(mark" not in face_fn:
            problems.append("the red handle is not placed through the shared "
                            "screen-middle projector - two placement idioms "
                            "drift (P-UI-98d v2)")
        if "HandsetHandlePark(mark, S1_HANDLE_RES)" not in face_fn:
            problems.append("a SET handle's icon is left on the chart - a set "
                            "line cannot be grabbed, so nothing may point at it "
                            "either (P-UI-98d v2)")
        if "g_s1MarkAboveName" not in face_fn or "g_s1MarkBelowName" not in face_fn:
            problems.append("the face owner no longer stashes the armed handles' "
                            "own OBJECT NAMES: the grab hit test cannot name the "
                            "line it claims without walking the chart, and the "
                            "carry does not know what to move (P-UI-98e)")
        if "g_linesVisible" not in face_fn:
            problems.append("the handle's show condition forgot the LINES "
                            "switch - the markers must obey the L switch with "
                            "the lines (P-UI-98d v2)")
    create_idx = pipe.find("CreateOrUpdateHLine(lines[i].name")
    face_idx = pipe.find("Step1HandleOwnFace(lines[i].name")
    if create_idx < 0:
        problems.append("the render no longer creates lines through the "
                        "guarded creator (P-UI-98)")
    elif face_idx < 0:
        problems.append("the face owner is never called from the render "
                        "(P-UI-98)")
    elif face_idx < create_idx:
        problems.append("the face is owned BEFORE the creator - a fresh line is "
                        "born SELECTABLE=false and the face write lands on "
                        "nothing, so the handle stays un-grabbable until a "
                        "topology change re-renders (P-UI-98)")
    if "Step1HandleOwnFace(lines[i].name, lines[i].price, lines[i].direction," not in pipe:
        problems.append("the face call does not pass the price/direction the "
                        "marker dot needs (P-UI-98d)")
    if "if(g_s1DragLive && lines[i].name == g_s1DragName)" not in pipe:
        problems.append("the render's drag-skip is gone - a write on the line "
                        "MT4 is dragging cancels that drag (P-BK-15 / P-UI-98)")
    if "lines[i].logicalStep == 1 &&\n           lines[i].name == g_s1DragName" in pipe:
        problems.append("the drag-skip is keyed on a RUNG again - the handle is "
                        "not always the ladder's rung 1, so the render writes "
                        "the line the hand is holding and MT4 cancels that drag "
                        "(P-BK-15 / P-UI-98f)")

    # 5. the release, the echo stamp, and the heal
    settle_fn = body(events, "void Step1DragSettle(")
    if not settle_fn:
        problems.append("Step1DragSettle() is gone - the release never settles "
                        "(P-UI-98)")
    else:
        if "CustomPriceDragFrame(true)" not in settle_fn:
            problems.append("the settle is not a FORCED frame - the gesture's "
                            "last pixel would not be painted from the final "
                            "step (P-UI-98)")
        if "OBJPROP_SELECTED" not in settle_fn:
            problems.append("the settle does not drop the grab's selection - a "
                            "selection that outlives its gesture is moved by "
                            "every later drag anywhere (P-UI-45 / P-UI-98)")
        if "g_s1JustDraggedMs = GetTickCount();" not in settle_fn:
            problems.append("the settle no longer stamps the drag echo - the "
                            "click MT4 reports at a drag's end would set the "
                            "line the user just moved (P-UI-98d)")
    if "if(g_s1DragLive) Step1DragSettle();" not in events:
        problems.append("the button-up latch no longer settles the step-1 "
                        "gesture (P-UI-98)")
    heal_fn = body(events, "void CustomPriceDragHealStale(")
    if "if(g_s1DragLive)" not in heal_fn:
        problems.append("the stale-drag heal does not cover the step-1 flags - "
                        "a lost release would pin the handle's price forever "
                        "(P-BK-03 / P-UI-98)")

    # 6. the resets
    if events.count("StepOverrideFactorReset();") < 2:
        problems.append("the override does not reset at BOTH owners (the "
                        "custom-price placement teardown and the R key) - a "
                        "stale factor would silently scale other start points "
                        "(P-UI-98)")
    # P-UI-98e: FOUR owners now - the placement teardown, the R key, the re-arm
    # click, and the fresh placement (HandsetPlacementArm). The two that are named
    # by their own function are pinned by name; the count is the floor that also
    # covers the two inline sites (the R key and the re-arm click).
    if events.count("g_s1LinesArmed = true;") < 4 or \
            "g_s1LinesArmed = true;" not in body(events, "void CleanupCustomPriceObjects(") or \
            "g_s1LinesArmed = true;" not in body(events, "void HandsetPlacementArm("):
        problems.append("the armed/set state does not wake ARMED at every reset "
                        "owner (the placement teardown, the R key, the re-arm "
                        "click, a fresh placement) - a set line would survive "
                        "its own reset (P-UI-98d / P-UI-98e)")
    # P-UI-98e: a FRESH placement wakes the pair ARMED (the C key and the ring
    # PIN both go through this one owner) - a line the user had SET must not come
    # back inert, or the first gesture on it is refused for a second reason.
    if "void HandsetPlacementArm(" not in events:
        problems.append("HandsetPlacementArm() is gone - a fresh placement cannot "
                        "wake the armed/set pair (P-UI-98e)")
    else:
        arm_fn = body(events, "void HandsetPlacementArm(")
        if "g_cpLineArmed  = true;" not in arm_fn:
            problems.append("a fresh placement leaves the custom price line SET - "
                            "the line the user just placed cannot be dragged "
                            "(P-UI-98e)")
        if "g_s1LinesArmed = true;" not in arm_fn:
            problems.append("a fresh placement leaves the step-1 handles SET - "
                            "the first step cannot be dragged on the line the "
                            "user just placed (P-UI-98e)")
        if "g_s1SetPendingMs = 0;" not in arm_fn or "g_cpSetPendingMs = 0;" not in arm_fn:
            problems.append("HandsetPlacementArm() leaves a pending click alive - "
                            "the SET a previous line's click armed would commit "
                            "against the fresh placement (P-UI-98e)")
    if "HandsetPlacementArm();" not in events or "HandsetPlacementArm();" not in read(MENU):
        problems.append("a fresh placement does not wake through "
                        "HandsetPlacementArm() at BOTH activations (the C key and "
                        "the ring PIN) - the second surface disagrees about what "
                        "\"fresh\" means again (P-UI-98e)")
    if '"Biotak_StepFactor_" + chartIdStr' not in glob:
        problems.append("the override key is not purged on REASON_REMOVE - a "
                        "removed indicator's step override would outlive it "
                        "(P-UI-98)")

    # 7. the one writer, bounded
    writer_fn = body(glob, "void StepOverrideFactorSet(")
    if not writer_fn:
        problems.append("StepOverrideFactorSet() is gone - the override has no "
                        "one writer (P-UI-98)")
    elif "MathMax(0.05, MathMin(20.0" not in writer_fn:
        problems.append("the override writer lost its bounds - a stray drop "
                        "can flatten the ladder to nothing or blow it out "
                        "(P-UI-98)")

    # 8. P-UI-98d: the armed/set machinery and its always-on sweeper
    sweep_fn = body(events, "void HandsetClickSweep(")
    if not sweep_fn or "DOUBLE_CLICK_THRESHOLD_MS" not in sweep_fn:
        problems.append("the click's double-click window has no sweeper - a "
                        "single click would set instantly and the first click "
                        "of a double would commit before the second arrives "
                        "(P-UI-98d)")
    if events.count("HandsetClickSweep();") < 2:
        problems.append("the sweeper does not ride BOTH always-on channels "
                        "(the mouse stream and the tick path) - a click that "
                        "never moves again would never commit (P-UI-98d)")
    if "if(id == CHARTEVENT_OBJECT_CLICK && Step1LineIsDragHandle(sparam))" not in events:
        problems.append("the step-1 handle has no click owner - click-to-set "
                        "and double-click-to-re-arm are words, not wiring "
                        "(P-UI-98d)")
    sync_fn = body(events, "void CustomPriceMarkerSync(")
    if not sync_fn or "CP_HANDLE_RES" not in sync_fn:
        problems.append("the custom line's green handle has no owner - it is a "
                        "baked GREEN raster now, so the colour is the icon's "
                        "(P-UI-98d v2)")
    elif "HandsetHandleAt(g_cpMarkerName, price, CP_HANDLE_RES)" not in sync_fn or \
            "HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES)" not in sync_fn:
        problems.append("the custom line's green handle is not placed (and "
                        "parked) through the shared screen-middle projector - "
                        "two placement idioms drift (P-UI-98d v2)")
    # P-UI-98d v2: the two markers are BAKED rasters, so green/red lives in the
    # icon - and a #resource outside the manifest embeds a GHOST (R-ICON, the leg
    # meter's own rule).
    for res in ("cp_handle.bmp", "s1_handle.bmp"):
        if ('#resource "\\\\Files\\\\Icons\\\\' + res + '"') not in glob:
            problems.append("the handset handle raster %s has no #resource in "
                            "GlobalVariables: the bitmap stops embedding and the "
                            "handle goes blank (P-UI-98d v2)" % res)
        if res not in read(MANIFEST_PATH):
            problems.append("the handset handle raster %s is not in the icon "
                            "manifest: a #resource outside the manifest embeds "
                            "a ghost (P-UI-98d v2 / R-ICON)" % res)
    if "OBJ_ARROW" in face_fn or "OBJ_ARROW" in sync_fn:
        problems.append("the handset markers are chart-space arrows again - the "
                        "user asked for a circular DRAG ICON centred on the line "
                        "(P-UI-98d v2)")
    if "CustomPriceMarkerSync();   // P-UI-98d: the green dot rides the line's own writer" not in events:
        problems.append("the marker sync is not called from the line's own "
                        "creator - a restored line would wear no marker "
                        "(P-UI-98d)")
    # P-UI-98n: the LINES switch syncs the markers SYNCHRONOUSLY through the
    # ride (all three circles at once). A TIMEFRAMES mask does not hide screen
    # objects, so syncing only the green dot left the reds to the next
    # render/mousemove («دیر پنهان میشن»).
    if "HandsetMarkersRide();" not in body(events, "void SetLinesVisible("):
        problems.append("the LINES switch no longer syncs the handset markers - "
                        "the circles wait for the next render/mousemove instead "
                        "of following the key (P-UI-98n)")

    # P-UI-98r: HTF CANDLES STAY BEHIND OPEN UI. Chart rectangles with
    # BACK=false paint over screen skins at ANY rung, so an open card/palette
    # masks the boxes it covers, by name, from published screen rects.
    htf = read(HTF)
    panels = read(PANELS)
    entry = read(ENTRY)
    pub_fn = body(panels, "void PnlPublishCover(")
    if not pub_fn or "PNL_MARGIN" not in pub_fn or "g_PalOpen" not in pub_fn:
        problems.append("the cover publisher is gone or half: the card-cull "
                        "reads stale rects (or none) and boxes stay over the "
                        "card (P-UI-98r)")
    open_fn = body(panels, "void PnlOpen(")
    close_fn = body(panels, "void PnlCloseAll(")
    move_fn = body(panels, "void PnlMoveBy(")
    draw_fn = body(htf, "int DrawHTFCandles(")
    prune_fn = body(htf, "void HTFDeleteIndices(")
    timer_fn = body(entry, "void OnTimer()")
    for fn, where in ((open_fn, "PnlOpen"), (close_fn, "PnlCloseAll"),
                      (move_fn, "PnlMoveBy")):
        if not fn or "PnlPublishCover();" not in fn or "HTFCardCullRefresh();" not in fn:
            problems.append("%s no longer publishes + culls: boxes drawn "
                            "before it opened (or moved with it) stay over "
                            "it (P-UI-98r)" % where)
    if not draw_fn or "HTFCardCullRefresh();" not in draw_fn:
        problems.append("a draw while a card is open births boxes unmasked: "
                        "a settings drag flickers HTF over the card until the "
                        "timer net (P-UI-98r)")
    if not timer_fn or "HTFCardCullRefresh();" not in timer_fn:
        problems.append("the timer net is gone: zoom/resize/forming drift "
                        "while a card is open converges on nothing (P-UI-98r)")
    refresh_fn = body(htf, "void HTFCardCullRefresh(")
    if not refresh_fn:
        problems.append("HTFCardCullRefresh() is gone - no cull, no release "
                        "(P-UI-98r)")
    else:
        if "HTFCullRelease();" not in refresh_fn:
            problems.append("the cull never releases: a closed card leaves "
                            "its boxes masked (P-UI-98r)")
        if "HTFCullTrack(nm[k]);" not in refresh_fn:
            problems.append("masked boxes are not tracked: the release cannot "
                            "name what the cull took (P-UI-98r)")
        if htf.count("IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS") < 2:
            problems.append("a cull release unmasks naively: it resurrects "
                            "boxes an F-hide put away (P-UI-98r)")
    if "HTFCullForget(" not in (prune_fn or ""):
        problems.append("a pruned box lingers in the cull set: its release "
                        "write fails silent and the slot lies (P-UI-98r)")
    if "OBJPROP_ZORDER" in htf:
        problems.append("the cull reaches for ZORDER: chart rectangles paint "
                        "over screen skins at any rung, so a rung cannot fix "
                        "this - masks can (P-UI-98r)")

    # 9. P-UI-99: the hold is retired, the claim is immediate AND armed-gated
    if re.search(r"(?m)^#define\s+CP_HOLD_MS", events) is not None:
        problems.append("the hold-to-arm beat is back (CP_HOLD_MS) - retired by "
                        "user order, the immediate claim replaced it "
                        "(P-UI-99-OFF)")
    if "s_cpHoldArmed" in events:
        problems.append("the hold-to-arm statics are back (s_cpHoldArmed) - "
                        "retired by user order (P-UI-99-OFF)")
    # P-UI-100 (2026-09-22): the claim may carry MORE terms than the two it was
    # born with - the foreign-draw fence (!TickDeadlinePending(s_cpForeignDrawUntil))
    # was added between the armed gate and the two condition pairs. The promise is
    # unchanged and this check still enforces every part of it: the armed gate, the
    # yield to the step-1 claim, and BOTH condition pairs verbatim.
    if re.search(r"!s1Claimed\s*&&\s*g_cpLineArmed\s*&&[\s\S]{0,300}?"
                 r"\(\(pressEdge && \(terminalGrab \|\| pixelHit\)\) \|\| \(terminalGrab && atLineNow\)\)",
                 events) is None:
        problems.append("the immediate (armed-gated) claim is gone - a press "
                        "would not grab an armed line, or worse, a SET line "
                        "would answer the pixel test (P-UI-99 / P-UI-98d)")
    if "!s1Claimed && g_cpLineArmed &&" not in events:
        problems.append("the step-1 claim no longer yields the custom-price "
                        "claim: one press would be claimed by BOTH gestures, and "
                        "the line and the handle would move together (P-UI-98e)")

    # 10. P-UI-98e: THE HANDLE'S OWN CARRY. MT4's per-object native drag is the
    # half the custom price line already stopped trusting (P-UI-49c: several
    # builds never engage it at all), so step 1 must move through the SAME own
    # channel - with the SAME numbers (the cursor conversion, the drawn-width
    # tolerance, CP_DRAG_SLOP, the absolute-off-the-grab carry, the frozen
    # stand-down) and through the SAME math owner.
    hit_fn = body(events, "bool Step1HandleUnderCursor(")
    if not hit_fn:
        problems.append("Step1HandleUnderCursor() is gone - the handle has no "
                        "hit test of its own, so its drag lives or dies by a "
                        "terminal grab that never engaged (P-UI-98e)")
    else:
        if "TH_START_POINT_CUSTOM_PRICE" not in hit_fn or "g_linesVisible" not in hit_fn:
            problems.append("the handle hit test lost its mode / visibility gates - "
                            "a press outside the custom-price placement, or on a "
                            "hidden line family, could be claimed (P-UI-98e)")
        if "ChartXYToTimePrice(" not in hit_fn or "inpCustomPriceLevelWidth" not in hit_fn:
            problems.append("the handle hit test no longer converts the cursor "
                            "(ChartXYToTimePrice) or lost its pixel tolerance: a "
                            "press the terminal does not pick up would move "
                            "nothing (P-UI-98e)")
    claim_fn = body(events, "bool Step1HandleOwnClaim(")
    if not claim_fn:
        problems.append("Step1HandleOwnClaim() is gone - no press is ever "
                        "claimed for the step-1 handle (P-UI-98e)")
    else:
        if "g_s1LinesArmed" not in claim_fn:
            problems.append("the step-1 CLAIM is not armed-gated - a SET handle "
                            "would move again, which is the half of the "
                            "user's order that makes SET mean anything "
                            "(P-UI-98e)")
        if "Step1LineDragApply(" not in claim_fn:
            problems.append("the claim does not record the grab price through the "
                            "drag's own owner - the settle's echo stamp then has "
                            "no baseline and a drag release would SET the line it "
                            "has just moved (P-UI-98e / P-UI-98d)")
        if "CustomPriceDragLockOn();" not in claim_fn:
            problems.append("the claim does not take the view lock - the chart "
                            "pans under the dragged handle and the handle is "
                            "moved against a rebased price scale (P-UI-53 / "
                            "P-UI-98e)")
    move_fn = body(events, "void Step1HandleOwnDragMove(")
    if not move_fn:
        problems.append("Step1HandleOwnDragMove() is gone - the claim has "
                        "nothing that moves the line (P-UI-98e)")
    else:
        if "CP_DRAG_SLOP" not in move_fn:
            problems.append("the carry lost its travel fence: the one-pixel "
                            "jitter of a click would write the handle's price "
                            "and re-step the whole ladder (P-UI-98e)")
        if "g_s1OwnGrabPrice + (cursorPrice - g_s1OwnGrabCursorPrice)" not in move_fn:
            problems.append("the carry is absolute-to-cursor: a gesture that was "
                            "not aimed at the line snaps it onto the cursor and "
                            "the step jumps under the user (P-UI-98e)")
        if "g_s1OwnLastWrite" not in move_fn:
            problems.append("the carry has no frozen stand-down: it rewrites the "
                            "object MT4 may be dragging itself, which cancels "
                            "that drag, or fights it (P-BK-15 / P-UI-98e)")
        if "Step1LineDragApply(g_s1DragName)" not in move_fn:
            problems.append("the carry does not route the math through the ONE "
                            "step-1 owner - a second copy of the factor "
                            "arithmetic that will drift (P-UI-98e)")
    # P-UI-98e: IN THE MOMENT. The user's order is explicit - «مثل خط کاستوم پرایس
    # که جابجا میشه بقیه سطوح هم جابجا میشن در لحظه باشه برای step اول». The
    # step-1 drag must therefore (a) mark the ladder STALE, because the levels
    # block is gated on `g_redrawTHLevelsNeeded` (the custom price line's own live
    # follow sets it through CustomPriceDragAnchorSet), and (b) be exempt from the
    # P-PERF-34 event deferral (a deferred drag frame is the lag).
    if "g_redrawTHLevelsNeeded = true;" not in apply_fn:
        problems.append("the step-1 drag no longer marks the ladder stale after it "
                        "writes the factor: the levels block is gated on that flag, "
                        "so the whole ladder would stay where it was and only the "
                        "dragged line itself would move (P-UI-98e)")
    if "if(force_redraw && g_inChartEvent && !g_customPriceLineDragging && !g_s1DragLive)" not in events:
        problems.append("the step-1 drag is not exempt from the P-PERF-34 event "
                        "deferral: its frames are scheduled instead of run, and "
                        "the other levels do not follow the hand in the moment "
                        "(P-PERF-34 / P-UI-98e)")
    # P-UI-98e: A PRESS ON THE CUSTOM PRICE LINE IS NOT THE HANDLE'S. The rung-1
    # row and the line sit within the same few pixels often enough, and the
    # step-1 claim runs first - so the line's own grab test must decide, or the
    # gesture the user aimed at the LINE re-steps the ladder instead
    # («میخوام خط کاستوم پرایس جابجا بکنم ... و step جابجا میشن»).
    # P-UI-98i: NEAREST WINS inside that yield - a press clearly on the line
    # stays the line's, but a press nearer the handle's own row belongs to the
    # handle even when the line's tolerance also covers it (a coarse chart puts
    # both within a few pixels - «روان درگ نمیشه»).
    if "bool onCustomLine = CustomPriceGrabAt((int)lparam, (int)dparam);" not in events or \
            "bool s1OnRow = (s1Hit && (!onCustomLine ||" not in events:
        problems.append("the step-1 press edge does not yield to the custom price "
                        "line's own grab test: with the two rows close, dragging "
                        "the LINE re-steps the ladder (P-UI-98e)")
    if "Step1NearerThanCustom((int)lparam, (int)dparam, s1Row)" not in events:
        problems.append("a press on BOTH rows always drags the line: the handle "
                        "has no nearest-wins term, so on a coarse chart - where "
                        "one step is a few pixels - the red handle can never be "
                        "grabbed (P-UI-98i)")
    # P-UI-98i: A MISSED PRESS EDGE STILL CLAIMS. The edge is seen on the first
    # MOVE after the press, so a press whose first move never arrived (a release
    # off-chart leaves the shared latch set) had no edge to arm on - while the
    # custom-price claim beside it recovers through MT4's own selection. The
    # terminal's pick-up is the second opinion for the handle too.
    if "if(!s1OnRow && !pressEdge && g_s1LinesArmed && !onCustomLine &&" not in events:
        problems.append("a press whose edge was missed never claims the handle: "
                        "the step-1 claim has no terminal-selection fallback, so "
                        "after one off-chart release the handle is dead until an "
                        "unrelated click resets the latch (P-UI-98i)")
    # P-UI-98i: A NATIVE-ONLY DRAG IS ADOPTED. When MT4's own drag moves the
    # line first, g_s1DragLive is up through OBJECT_DRAG with the own carry
    # never armed - and the gesture then lives or dies by OBJECT_DRAG alone
    # (the builds that stutter it cut the drag, P-UI-49c).
    if "else if(g_s1DragLive && !g_s1OwnActive && !g_customPriceLineDragging)" not in events or \
            "Step1HandleOwnClaim(g_s1DragName, (int)lparam, (int)dparam)" not in events:
        problems.append("a native-only step-1 drag is never adopted into the own "
                        "carry: on a build whose OBJECT_DRAG stutters the line "
                        "stops following the hand mid-gesture (P-UI-49c / "
                        "P-UI-98i)")
    # P-UI-98i: the press latch is retried, never frozen - with the draggable
    # flag borrowed no other channel moves the line, so a failed grab-cursor
    # conversion would freeze it for the whole gesture.
    if "if(!(g_s1OwnGrabCursorPrice > 0.0))" not in events:
        problems.append("a failed grab-cursor conversion freezes the step-1 "
                        "carry for the whole gesture: the latch is never "
                        "retried (P-UI-98i)")
    # P-UI-98i: the step-1 drag re-steps the ladder live like the line's drag,
    # so the surplus sweep owes it the same throttle.
    if "if(g_customPriceLineDragging || g_s1DragLive) {" not in pipe:
        problems.append("a full surplus sweep runs mid step-1-drag: the cleanup "
                        "throttle only knows the custom-price gesture, so it "
                        "deletes under the hand (P-UI-98i)")
    # P-UI-98j: THE STEP-1 PAIR HEALS ITSELF. A stashed handle whose object
    # vanished behind our back (a delete inside the 250 ms suppression window,
    # so the OBJECT_DELETE self-heal never fired) is never re-created by
    # sealed steady-state frames - only a TF switch rebuilt for real, which is
    # why only that fixed it («ناپدید میشه ... دیگه نمیشه جابجاش کرد»).
    healmiss_fn = body(events, "void Step1HandleHealMissing(")
    if not healmiss_fn:
        problems.append("Step1HandleHealMissing() is gone - a stashed step-1 "
                        "handle whose object vanished is never re-created: the "
                        "red circle floats on an empty chart and no press can "
                        "grab it until a TF switch rebuilds (P-UI-98j)")
    else:
        for needle, why in (
            ("TH_START_POINT_CUSTOM_PRICE",
             "the heal fires outside the custom-price placement"),
            ("!g_s1LinesArmed || g_s1DragLive",
             "the heal fires on a SET pair or mid-gesture"),
            ("IsIndicatorHidden() || !g_linesVisible",
             "the heal fires while hidden or with lines off"),
            ("g_s1MarkPeriod != Period()",
             "the heal answers another timeframe's stash"),
            ("g_buildStage != 0 || g_forceClearOnNextDraw",
             "the heal fires mid-rebuild"),
            ("S1_HEAL_MS",
             "the heal has no throttle - two ObjectFind probes per tick"),
            ("WindowPriceMax()", "the heal has no visible-window proof"),
            ("if(!(wMax > wMin)) return;",
             "the heal guesses with no window known"),
            ("g_s1MarkAbovePrice >= wMin",
             "the heal repairs a correctly culled off-screen line"),
            ("ObjectFind(0, g_s1MarkAboveName) < 0",
             "the heal rebuilds without verifying the object is gone"),
            ("g_redrawTHLevelsNeeded = true;",
             "the heal never arms the rebuild"),
            ("MarkDrawGeneration();",
             "the heal reuses a sealed signature, so no rebuild runs")):
            if needle not in healmiss_fn:
                problems.append("the step-1 self-heal lost '%s': %s (P-UI-98j)"
                                % (needle, why))
        for bad, why in (
            ("g_forceClearOnNextDraw = true",
             "the heal wipes the family for a hole - a wipe answers a "
             "topology change, and every repair would blink the chart"),
            ("ClearAllLevels(",
             "the heal deletes to repair - the render re-asserts in place")):
            if bad in healmiss_fn:
                problems.append("the step-1 self-heal contains '%s': %s (P-UI-98j)"
                                % (bad, why))
    tick_fn = body(events, "int OnCalculateHandler(")
    if not tick_fn or "Step1HandleHealMissing();" not in tick_fn:
        problems.append("the tick path never runs the step-1 self-heal: a "
                        "vanished handle waits for an unrelated rebuild "
                        "(P-UI-98j)")
    # P-UI-98j: even a SUPPRESSED delete of a stashed handle is verified -
    # our own deletes never name one, so a missing one fell inside the window.
    if "else if(id == CHARTEVENT_OBJECT_DELETE && suppressDeleteEvent && sparam != \"\" &&" not in events:
        problems.append("a suppressed delete of a step-1 handle is ignored "
                        "again: inside the 250 ms window the line vanishes "
                        "with no heal armed (P-UI-98j)")
    if "!g_s1DragLive && g_thStartPointType == TH_START_POINT_CUSTOM_PRICE" not in events:
        problems.append("the suppressed-delete fast path lost its live-gesture "
                        "and mode terms: it would rebuild mid-drag or answer "
                        "another mode's stash (P-UI-98j)")
    # P-UI-98k: OUR OWN SWEEP MUST NOT DELETE THE DRAGGED HANDLE. Every step-1
    # drag changes the pitch (F), so SweepForeignLevelObjects runs on the
    # drag's own frames while the cache still holds the pre-drag price - and
    # the render skips that same line while the gesture is live (P-BK-15). A
    # sweep without this term deletes the line being dragged, the factor math
    # then reads 0 and freezes without ever arming the redraw flag, and the
    # settle's forced frame is gated off: the below handle vanishes mid-drag
    # and stays missing until an unrelated rebuild.
    sweepforeign_fn = body(pipe, "int SweepForeignLevelObjects(")
    if not sweepforeign_fn:
        problems.append("SweepForeignLevelObjects() is gone (P-UI-98k)")
    elif "bool s1SkipSweep = (g_s1DragLive && g_s1DragName != \"\" &&" not in sweepforeign_fn:
        problems.append("the foreign sweep deletes the live-dragged handle: "
                        "the drag holds a name the chart no longer carries, "
                        "the factor math reads 0 and freezes, and the handle "
                        "stays missing past the settle (P-UI-98k)")

    # P-UI-98e / P-LM-21: THE BORROWED DRAGGABLE FLAG. MT4 re-arms its own drag on
    # every paint while SELECTABLE sits on the object, so a gesture that owns the
    # movement takes the flag off - and gives it back on both exits, or the line
    # stays deaf afterwards (the P-LM-17 bug with a new seat).
    borrow_fn = body(events, "void Step1DragSelectable(")
    if not borrow_fn:
        problems.append("Step1DragSelectable() is gone - the step-1 drag cannot "
                        "borrow the draggable flag, so the terminal keeps re-arming "
                        "its own drag and the line fights the hand "
                        "(«سریع قطع میشه», P-LM-21 / P-UI-98e)")
    elif "OBJPROP_SELECTABLE" not in borrow_fn or "OBJPROP_SELECTABLE, on" not in borrow_fn:
        problems.append("the borrow owner no longer writes the flag it borrows "
                        "(P-UI-98e)")
    if "    Step1DragSelectable(handle, false);" not in claim_fn:
        problems.append("the CLAIM never borrows the flag off - the terminal's own "
                        "drag arms at the press and re-arms on every paint, so the "
                        "gesture is cut off (P-LM-21 / P-UI-98e)")
    if "        Step1DragSelectable(name, g_s1LinesArmed &&" not in settle_fn:
        problems.append("the settle does not RETURN the borrowed flag - from the "
                        "first drag on the handle is deaf to the terminal's own "
                        "selection, its context menu and the Delete key "
                        "(P-UI-98e)")
    if "g_s1OwnBorrowed = false;" not in heal_fn:
        problems.append("the stale-drag heal leaves the borrow set - the flag is "
                        "never returned after a lost release (P-UI-98e)")
    if 'bool dragOwnsThis = (g_s1DragLive && g_s1DragName == name);' not in pipe:
        problems.append("the face owner re-arms the flag mid-gesture: the terminal's "
                        "drag loop restarts under the hand and the line fights it "
                        "(P-UI-98e)")

    # P-UI-98e: «فقط هر step اول در تایم خودش فعال باشه» - the stash names the
    # PERIOD it came from, so a stash left by the previous timeframe cannot answer
    # a press on the new one (before the TF switch's own frame re-stashes it).
    if "g_s1MarkPeriod = Period();" not in pipe:
        problems.append("the handle stash no longer stamps its own PERIOD - a stash "
                        "from the previous timeframe could answer a press on the "
                        "new one (P-UI-98e)")
    if "if(g_s1MarkPeriod != Period()) return false;" not in events:
        problems.append("the handle hit test does not refuse another timeframe's "
                        "stash (P-UI-98e)")

    if "Step1HandleOwnClaim(s1Row, (int)lparam, (int)dparam)" not in events:
        problems.append("the mouse-move press edge never claims the step-1 "
                        "handle: the handle is draggable by nothing (P-UI-98e)")

    # 10b. P-UI-98e: THE CLICK CONTRACT. ONE owner, THREE edges - our own press/
    # release pair, the CHARTEVENT_CLICK finalize (a motionless release emits no
    # MOUSE_MOVE at all, P-BK-03), and MT4's own OBJECT_CLICK. A click can reach
    # the owner twice, so the twin must be dropped or a double reads as two
    # singles and a SET lands on a line the user was re-arming.
    click_fn = body(events, "void Step1HandleClickAt(")
    if not click_fn:
        problems.append("Step1HandleClickAt() is gone - the step-1 click has no "
                        "owner, so click-to-SET and double-click-to-re-arm are "
                        "words, not wiring (P-UI-98e)")
    else:
        if "DOUBLE_CLICK_THRESHOLD_MS" not in click_fn or "g_s1SetPendingMs = now;" not in click_fn:
            problems.append("the step-1 click owner lost the double-click "
                            "window or the deferred SET slot - the first click "
                            "of a double would commit, and a double could never "
                            "cancel it (P-UI-98d / P-UI-98e)")
        if "g_s1ClickHandledMs != 0" not in click_fn or "g_s1ClickHandledMs = now;" not in click_fn:
            problems.append("the click owner has no twin-event dedupe GUARD; one "
                            "physical click reaches it through two transports "
                            "and the second would read as a double-click "
                            "(P-UI-98e)")
        if "g_s1JustDraggedMs" not in click_fn:
            problems.append("a DRAG's own click echo would SET the handle the "
                            "user just moved - the just-dragged stamp is not "
                            "read any more (P-UI-98d / P-UI-98e)")
    if "Step1HandleClickAt(sparam)" not in events:
        problems.append("MT4's own OBJECT_CLICK no longer reaches the click "
                        "owner - the terminal's report is one of the three "
                        "edges, not a second contract (P-UI-98e)")
    if "if(id == CHARTEVENT_CLICK) Step1ClickFinalize();" not in events:
        problems.append("the CHARTEVENT_CLICK finalize is gone - a still click "
                        "on a handle emits no MOUSE_MOVE, so it would never SET "
                        "or re-arm anything (P-BK-03 / P-UI-98e)")
    if "if(!rowTravelled) Step1HandleClickAt(row);" not in events:
        problems.append("the button-up half of the click contract is gone - the "
                        "press that never travelled no longer counts as a click "
                        "(P-UI-98e)")
    if "g_s1ClickRow = s1Row;" not in events:
        problems.append("the press edge no longer records the row it landed on - "
                        "a click on a SET handle cannot name the line the "
                        "double-click has to wake (P-UI-98e)")
    # P-UI-98e: THE BUTTON-UP THAT CARRIES NO MOVE MUST ALSO END THE GESTURE.
    # Without it the drag stayed live (the render keeps skipping the line's writes,
    # the borrowed flag stays off, and BOTH claims refuse the next press) until the
    # 1.5 s heal - «جابجا میشه بعد دیگه نمیشه درگش کرد».
    fin_fn = body(events, "void Step1ClickFinalize(")
    if "if(g_s1DragLive)" not in fin_fn or "Step1DragSettle();" not in fin_fn:
        problems.append("the click finalizer no longer settles a LIVE gesture: a "
                        "release that emits no MOUSE_MOVE leaves the drag stuck "
                        "and nothing can be grabbed again until the heal "
                        "(P-BK-03 / P-UI-98e)")
    if "bool wrote = (g_s1OwnLastWrite > 0.0);" not in fin_fn:
        problems.append("the click finalizer asks the click question without asking "
                        "whether the gesture WROTE a price - a drag would SET the "
                        "handle the user just moved (P-UI-98e)")
    # 10c. P-UI-98h: THE PRESS ECHO MUST NOT END A GESTURE, AND MUST NOT ARM A
    # SET. The measured MT4 fact is the panels' own (P-UI-49b/P-UI-73: one of
    # CHARTEVENT_CLICK / OBJECT_CLICK is delivered ON the PRESS that grabs a
    # selectable object); the step-1 pair met it as «هی قطع میشه موقع درگ
    # کردن» — the finalize settled the gesture that same press had claimed and
    # armed its deferred SET, which then committed after the drag and left the
    # handle inert (Step1HandleOwnClaim refuses a SET handle).
    if fin_fn and "UILeftButtonUp()" not in fin_fn:
        problems.append("the click finalizer settles a LIVE gesture without asking "
                        "whether the button is even up - a CHARTEVENT_CLICK "
                        "delivered on the PRESS kills the gesture that same press "
                        "just started (P-UI-98h)")
    if click_fn and "if(g_s1LinesArmed && !g_s1DragLive && now - g_s1JustDraggedMs > 350)" \
            not in click_fn:
        problems.append("the click owner arms the deferred SET while a drag is live - "
                        "the sweeper commits it the moment the button comes up, i.e. "
                        "right after a working drag (P-UI-98h)")
    if sweep_fn and sweep_fn.count("UILeftButtonUp()") < 2:
        problems.append("the sweeper commits a SET with the button still down - the "
                        "press echo's pending slot lands mid-press (P-UI-98h)")
    if choose_fn and "g_s1SetPendingMs = 0;" not in choose_fn:
        problems.append("the claim does not cancel the pending SET - the press echo "
                        "armed one and it commits right after the drag (P-UI-98h)")
    if settle_fn and "g_s1SetPendingMs = 0;" not in settle_fn:
        problems.append("a settle that MOVED the line leaves the pending SET alive - "
                        "the handle goes inert right after a working drag (P-UI-98h)")
    if hit_fn and "HANDSET_HANDLE_HALF" not in hit_fn:
        problems.append("the handle hit test still gates on the 1 px line instead of "
                        "the 15 px circle the hand grabs - a press on the icon's own "
                        "rim is rejected (P-UI-98h)")
    if "bool s1Wrote = (g_s1OwnLastWrite > 0.0);" not in events:
        problems.append("the release latch reads the travel AFTER the settle - the "
                        "settle clears that stamp, so the answer is always \"never "
                        "travelled\" and every drag would SET its own handle "
                        "(P-UI-98e)")
    ride_fn = body(events, "void HandsetMarkersRide(")
    if "g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0" not in ride_fn:
        problems.append("the ride channel no longer asks the armed state before "
                        "placing a step-1 icon: it would resurrect the red "
                        "handle over a SET line nothing can grab (P-UI-98d v2)")
    # P-UI-98l: the ride obeys the LINES switch and the hide-all state, on
    # BOTH sides - without them the L key parks the circles through the render
    # and the next mouse move puts them straight back.
    if ride_fn.count("&& g_linesVisible && !IsIndicatorHidden())") < 2:
        problems.append("the ride channel ignores the LINES switch or the "
                        "hide-all state: with lines off (L key) the red "
                        "circles come back on the next mouse move (P-UI-98l)")
    if "if(g_s1OwnActive)" not in events:
        problems.append("the OWNED step-1 gesture has no held pass on the mouse "
                        "stream - the line would not follow the hand (P-UI-98e)")
    # P-UI-98f: both exits clear the carry's own state through its ONE owner
    # (`Step1GestureStateClear`) - a bare flag write in one path and not the
    # other is exactly the bug the owner exists to kill.
    if "g_s1OwnActive = false;" not in settle_fn and \
            "Step1GestureStateClear()" not in settle_fn:
        problems.append("the settle leaves the carry's own flag up - a gesture "
                        "that is over keeps reading the cursor on every move "
                        "(P-UI-98e)")
    if "g_s1OwnActive = false;" not in heal_fn and \
            "Step1GestureStateClear()" not in heal_fn:
        problems.append("the stale-drag heal leaves the carry's own flag up - a "
                        "healed gesture keeps carrying the line (P-UI-98e)")
    if "else if(pressEdge || terminalGrab)" not in events:
        problems.append("the foreign-drag drain lost its arm - a selection left "
                        "by a click would ride the NEXT drag of any other "
                        "object, which is the interference the user ordered "
                        "gone (P-UI-99)")
    if "ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);" not in events:
        problems.append("the claim no longer SELECTS the line - a grab without "
                        "a face, and the deselect pair half-blind (P-UI-99)")
    if "ClearCustomPriceSelection();" not in events:
        problems.append("the button-up deselect owner is gone - the select/"
                        "deselect pair is broken (P-UI-99)")
    return problems


def main():
    problems = []
    groups = (("rows", check_rows()), ("persist", check_persist()),
              ("palette", check_palette()), ("captions", check_captions()),
              ("trex", check_trex_card()),
              ("relayout", check_relayout()), ("purge", check_purge()),
              ("body", check_card_body()),
              ("modal", check_modal()),
              ("measure", check_measure_item()),
              ("th3draw", check_th3_item()),
              ("th3ink", check_th3_ink()),
               ("th3caption", check_th3_caption()),
               ("th3ladder", check_th3_ladder()),
               ("th3delete", check_th3_delete()),
               ("pb-lock", check_th3_pb_lock()),
               ("pb-band-drag-lock", check_th3_pb_band_drag_lock()),
               ("pb-band-gesture", check_th3_band_gesture()),
              ("leg-plate", check_leg_plate_lifetime()),
              ("leg-head", check_leg_head_follow()),
              ("leg-sel", check_leg_selection()),
               ("leg-dir", check_leg_direction()),
               ("leg-tf", check_leg_tf()),
              ("leg-sel-atomic", check_leg_sel_atomic()),
              ("bk-info", check_bk_info_rungs()),
              ("press", check_press(read(PANELS))),
              ("chrome", check_chrome()),
              ("dual", check_dual()),
              ("drag", check_drag()),
              ("mouse", check_mouse()),
              ("bk-drag", check_bk_drag()),
              ("bkbox-ink", check_bkbox_ink()),
              ("bkedge-off", check_bkedge_off()),
              ("heal", check_heal()),
              ("bkcursor-off", check_bkcursor_off()),
              ("bkmagnet", check_bkmagnet()),
              ("paneldrag-off", check_paneldrag_off()),
              ("th-percent", check_th_percent()),
              ("placement", check_placement()),
              ("step1", check_step1()))
    for name, plist in groups:
        if not QUIET:
            print("  %s [%s]" % ("ok  " if not plist else "FAIL", name))
        problems.extend(plist)
    if problems:
        for msg in problems:
            print("  FAIL %s" % msg)
        print("\npanel wiring: %d problem(s) - a control is not wired to a live, "
              "persisted setting" % len(problems))
        return 1
    if not QUIET:
        n = sum(len(parse_spec(read(PANELS)).get(i, [])) for i in range(14))
        print("\npanel wiring: clean - every row of every card resolves to a live, "
              "persisted setting,\nevery colour kind is nameable and paintable, the "
              "card body covers every card it draws,\nthe teardown wipes what the "
              "drawers make, and the press chain is self-healing\n"
              "(%d declared rows across the cards)" % n)
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# negative control
# ─────────────────────────────────────────────────────────────────────────────
def selftest():
    real = dict(_PATCHED)
    cases = []

    stale = []

    def with_source(path, old, new, nth=0):
        # A seed whose anchor a refactor deleted is REPORTED, never ignored: a
        # negative control that no longer patches anything passes for the wrong
        # reason (exactly how this gate's chart-label sibling went quiet).
        _PATCHED.clear()
        src = read(path)
        i, at = -1, -1
        for _ in range(nth + 1):
            at = src.find(old, i + 1)
            if at < 0:
                break
            i = at
        if at < 0:
            stale.append(old.strip().splitlines()[0][:80])
            _PATCHED.update({path: src})
            return
        _PATCHED.update({path: src[:at] + new + src[at + len(old):]})

    def reset():
        _PATCHED.clear()
        _PATCHED.update(real)

    reset()
    cases.append(("the clean source passes every check",
                  not (check_rows() or check_persist() or check_palette()
                       or check_captions() or check_trex_card()
                       or check_relayout() or check_purge()
                       or check_card_body() or check_modal()
                       or check_measure_item() or check_bk_info_rungs()
                       or check_th3_item() or check_th3_ink()
                       or check_th3_caption() or check_th3_ladder()
                       or check_th3_delete()
                       or check_th3_pb_lock()
                       or check_leg_plate_lifetime()
                       or check_leg_head_follow() or check_leg_selection()
                        or check_leg_direction()
                        or check_leg_tf()
                       or check_leg_sel_atomic()
                       or check_press(read(PANELS)) or check_chrome()
                       or check_dual() or check_drag() or check_mouse()
                       or check_bk_drag() or check_bkcursor_off()
                       or check_bkbox_ink() or check_bkedge_off()
                       or check_heal() or check_th_percent()
                       or check_step1())))
    reset()

    # 1. P-UI-70c: the row is retired again while its address stays live
    with_source(PANELS, 'PnlSpecAdd(2, PNL_K_LEGACY, 10, 1, "gap");', "")
    cases.append(("a setting no row can reach is caught", bool(check_rows())))
    reset()

    # 2. a value-layer branch disappears (the control reads nothing)
    with_source(PANELS, "if(row==11) return g_atrTradeFontSize;", "")
    cases.append(("a control with no PnlCurrentSet branch is caught", bool(check_rows())))
    reset()

    # 3. the slider stops asking for a relayout (it moves nothing)
    with_source(PANELS, "else if(row==9)  { g_showPipDistanceLabels=(v>0.5); g_labelsRelayoutNeeded=true; flags=REFRESH_ALL; }",
                "else if(row==9)  { g_showPipDistanceLabels=(v>0.5); }")
    cases.append(("a press that changes nothing is caught",
                  bool(check_relayout() or check_rows()
                       or check_press(read(PANELS)))))
    reset()

    # 4. a setting is written but never persisted (P-UI-70d's own trap)
    with_source(SETTINGS, '   RSSetNext(p + "ATS", g_atrTradeFontSize);     // P-UI-70d\n', "")
    cases.append(("a setting with no override key is caught", bool(check_persist())))
    reset()

    # 5. the palette target table loses a name (the cycler cannot name the kind)
    with_source(PANELS, '"TRex TR", "TRex ex", "TRex Hunter", "TRex Trade", "TRex Spread"',
                '"TRex TR", "TRex ex", "TRex Hunter", "TRex Trade"')
    cases.append(("a palette target with no name is caught", bool(check_palette())))
    reset()

    # 6. a colour kind the palette cannot paint
    with_source(PANELS, "case PAL_ATR_SPREAD:     return g_atrTradeSpreadColor;",
                "case PAL_ATR_SPREAD:     return g_atrTradeRowColor;")
    cases.append(("a colour kind with no painter is caught", bool(check_palette())))
    reset()

    # 7. the card-body fallback steals the controls' presses (order inversion)
    with_source(PANELS, "      // P-UI-24: X / Done close on PRESS — before strip/dropdown/knob/track/",
                "      if(PnlTryGrabMove(mx,my)) return;   // seed: the grab eats the controls\n"
                "      // P-UI-24: X / Done close on PRESS — before strip/dropdown/knob/track/")
    cases.append(("a body fallback that eats controls is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 8. the press chain loses its self-healing guard (P-UI-70b)
    with_source(PANELS, "      if(!PnlPressAllowed()) return;   // P-UI-70b: self-healing (a stale claim",
                "      if(!DragCanGrab(DRAG_PANEL_KNOB)) return;   // (a stale claim")
    cases.append(("a press chain that can dead-lock is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 8b. P-UI-72: the ring grabs again while a card is open — the covered
    #     control reads as dead and the orb walks out from under the card.
    with_source(MENU,
                "   if(g_UIPanelOpen && g_LongPressItem < 0 && !g_OrbDragging) return;",
                "   if(false && g_LongPressItem < 0 && !g_OrbDragging) return;")
    cases.append(("a ring that can grab under an open card is caught",
                  bool(check_modal())))
    reset()

    # 8c. the guard lands after the grab (it would refuse nothing)
    with_source(MENU,
                "   if(g_UIPanelOpen && g_LongPressItem < 0 && !g_OrbDragging) return;",
                "")
    cases.append(("a modal guard placed after the grab is caught",
                  bool(check_modal())))
    reset()

    # 8d. P-UI-95: the measure tool is owned by TWO families at once (two cells
    #     that arm one session, and a tool index the layout still counts)
    with_source(MENU,
                "   // UIBK-OFF (P-UI-95): if(toolIdx == TOOL_BASEKNOT) return CIR_BASEKNOT;",
                "   if(toolIdx == TOOL_BASEKNOT) return CIR_BASEKNOT;")
    cases.append(("a measure tool counted in both families is caught",
                  bool(check_measure_item())))
    reset()

    # 8e. a SECOND copy of the arm path (the ring's own steps re-spelled)
    with_source(MENU, "   BaseKnotArm();\n", "   BaseKnotArm();\n   BaseKnotArm();\n")
    cases.append(("an arm path with two call sites is caught",
                  bool(check_measure_item())))
    reset()

    # 8f. the hold opens the item's own feature code (panel 10, the retired Factor
    #     card) instead of the Base Box card the Tools cell always opened
    with_source(MENU, "   if(feat == CIR_BASEKNOT)      return 12;",
                "   if(feat == CIR_BASEKNOT)      return feat;")
    cases.append(("a hold that opens another card than the Tools cell's is caught",
                  bool(check_measure_item())))
    reset()

    # 8g. the measure slot is inserted BETWEEN the existing ones (every persisted
    #     state key of the ring shifts by one)
    with_source(MENU, "#define RING_BASEKNOT 6", "#define RING_BASEKNOT 4")
    cases.append(("a measure slot inserted before the others is caught",
                  bool(check_measure_item())))
    reset()

    # 8h. P-UI-96: the TH3 press goes back to flipping the enable flag (the user's
    #     own report - the tool is pressed and there is nothing to draw with)
    with_source(MENU, "      refreshFlags = CircArmTH3Draw();",
                "      g_enableTH3Tool = !g_enableTH3Tool;\r\n"
                "      refreshFlags = REFRESH_ALL;")
    cases.append(("a TH3 press that only flips the enable flag is caught",
                  bool(check_th3_item())))
    reset()

    # 8i. the ring light reads the switch again: it can say "armed" with no session
    with_source(MENU, "   if(i == CIR_TH3)             return TH3SessionActive();",
                "   if(i == CIR_TH3)             return g_enableTH3Tool;")
    cases.append(("a TH3 light that reads the switch instead of the session is caught",
                  bool(check_th3_item())))
    reset()

    # 8j. the arm path stops repairing a precondition (the engine-off repair here;
    #     the mode repair is anchored the same way, one line below it)
    with_source(MENU, "      g_enableTH3Tool = true;\n", "")
    cases.append(("a TH3 arm path that skips a precondition repair is caught",
                  bool(check_th3_item())))
    reset()

    # 8k. P-TH3-PERF-07: the session takes the chart-wide mouse-move channel back.
    #     Anchored on the FUNCTION HEAD, not a body line: stage 5 added a trailing
    #     comment to TH3PreviewClear()'s call site, and a `\n`-terminated anchor
    #     then matched nothing - the seed turned into a silent no-op and the gate
    #     reported green on a rule it had stopped testing.
    with_source(TH3CTRL, "void TH3SessionCancel()\n{\n",
                "void TH3SessionCancel()\n{\n"
                "    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);\n")
    cases.append(("a TH3 session that switches the shared mouse-move flag off is caught",
                  bool(check_th3_item())))
    reset()

    # 8m2. P-UI-97: the hoisted ink is no longer resolved (a raw input reaches the
    #      write call through a local, which the name allowlist used to hide)
    with_source(TH3RENDER, "    color wantInk = TH3InkForChart(inpABCDInfoColor);",
                "    color wantInk = inpABCDInfoColor;")
    cases.append(("a hoisted ink that is never resolved is caught",
                  bool(check_th3_ink())))
    reset()

    # 8n. P-TH3-INFO-01: the caption cap is raised past MT4's own 63 characters
    #     (the user's chart lost everything after character 63, mid-word)
    with_source(TH3RENDER, "#define TH3_INFO_TEXT_MAX  63",
                "#define TH3_INFO_TEXT_MAX  120")
    cases.append(("a caption cap above MT4's 63-character limit is caught",
                  bool(check_th3_caption())))
    reset()

    # 8o. P-TH3-INFO-01: the writer stops wrapping (the raw text goes to OBJPROP_TEXT)
    with_source(TH3RENDER, "    int n = TH3InfoWrap(text, TH3_INFO_TEXT_MAX, lines);",
                "    string lines2[]; lines2 = lines; int n = 1; lines[0] = text;")
    cases.append(("a caption writer that no longer wraps is caught",
                  bool(check_th3_caption())))
    reset()

    # 8p. P-TH3-INFO-01: the delete path spells `_Info` again (lines 2..4 survive it)
    with_source(TH3TOOL, "            TH3InfoFamilyDelete(baseName);",
                "            ObjectDelete(0, baseName + \"_Info\");")
    cases.append(("a delete path that spares the caption's continuation lines is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q. P-TH3-INFO-01: the active sweep stops testing the caption family.
    #     P-TH3-P6f re-taught the anchor: the bare `continue;` is now a block
    #     (the ladder branch lives under it), so the seed names the opener.
    with_source(TH3TOOL, "        if(!TH3IsInfoLabelName(nm))\n        {\n", "")
    cases.append(("an active-pattern sweep blind to the caption family is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-7. P-TH3-P6f: the draw stops gating the ladder on the active pattern -
    #        every stored pattern wears Step1/3/5/7 (the user's mixed chart).
    with_source(TH3RENDER, "    TH3LadderSetVisible(mainObjName, isActive);\n", "")
    cases.append(("a draw that wears every pattern's ladder is caught",
                  bool(check_th3_ladder())))
    reset()

    # 8q-8. P-TH3-P6f: the draw lights the ladder unconditionally (isActive -> true).
    with_source(TH3RENDER, "    TH3LadderSetVisible(mainObjName, isActive);\n",
                "    TH3LadderSetVisible(mainObjName, true);\n")
    cases.append(("a draw that lights inactive ladders is caught",
                  bool(check_th3_ladder())))
    reset()

    # 8q-9. P-TH3-P6f: the activation sweep never darkens (own OR other).
    with_source(TH3TOOL,
                "            int wantLad = ownLadder ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;\n",
                "            int wantLad = OBJ_ALL_PERIODS;\n")
    cases.append(("an activation sweep that never darkens a ladder is caught",
                  bool(check_th3_ladder())))
    reset()

    # 8q-10. P-TH3-P6f: the ladder family test itself is renamed away.
    with_source(TH3RENDER, "bool TH3IsLadderName(const string objName)\n",
                "bool TH3IsLadderNameX(const string objName)\n")
    cases.append(("a missing ladder family test is caught",
                  bool(check_th3_ladder())))
    reset()

    # 8q-11. P-TH3-DEL1: the base is never extracted (nothing cascades).
    with_source(TH3TOOL, "        string baseName = TH3FamilyBaseOf(sparam);\n",
                "        string baseName = \"\";\n")
    cases.append(("a delete path with no base extraction is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-12. P-TH3-DEL1: the sweep loses the overlay prefix (TH3_MP_* orphans).
    with_source(TH3TOOL,
                '            string delMP = "TH3_MP_" + baseName + "_";\n',
                '            string delMP = "";\n')
    cases.append(("a delete sweep blind to the mother overlay is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-13. P-TH3-DEL1: the sweep loop never runs (members delete alone).
    with_source(TH3TOOL,
                "            for(int k = ObjectsTotal(0, -1, -1) - 1; k >= 0; k--) {\n",
                "            for(int k = 0; k < 0; k++) {\n")
    cases.append(("a delete path whose sweep never walks is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-14. P-TH3-DEL2: the maintenance window is gone (every member delete
    #        wipes - a base commit's own overlay drop kills the ABCD).
    with_source(TH3TOOL,
                "           && GetTickCount() - g_th3OwnDeleteMs <= 5000)\n",
                "           && false)\n")
    cases.append(("a delete path with no maintenance window is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-15. P-TH3-DEL2: the anchors are never asked (always wipe).
    with_source(TH3TOOL,
                "        if(TH3FamilyAnchorsAlive(baseName)\n",
                "        if(false)\n")
    cases.append(("a delete path that never asks the anchors is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-16. P-TH3-DEL2: the heal never reads the store (dropped member stays
    #        missing until an unrelated redraw).
    with_source(TH3TOOL,
                "            if(TH3PatternStoreGet(baseName, patH))\n",
                "            if(false)\n")
    cases.append(("a delete path that heals nothing back is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-17. P-TH3-DEL3: a caption drop is a delete trigger again - every plate
    #        the SetActive/Verify/Draw owners drop wipes a healthy ABCD.
    with_source(TH3TOOL,
                "        if(TH3IsInfoLabelName(sparam) && TH3FamilyAnchorsAlive(baseName)) return;\n",
                "        if(false) return;\n")
    cases.append(("a caption drop that cascades into a whole-family wipe is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-18. P-TH3-DEL3: the caption exemption forgets the anchors term - a
    #        broken family's own cleanup (P-TH3-RESTORE) can never finish.
    with_source(TH3TOOL,
                "        if(TH3IsInfoLabelName(sparam) && TH3FamilyAnchorsAlive(baseName)) return;\n",
                "        if(TH3IsInfoLabelName(sparam)) return;\n")
    cases.append(("a caption exemption that strands a broken family is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-19. P-TH3-DEL3: the maintenance window is back on the TICK clock (a
    #        drop queued behind our own multi-second redraw wipes the family).
    with_source(TH3TOOL,
                "           && GetTickCount() - g_th3OwnDeleteMs <= 5000)\n",
                "           && TimeCurrent() - (datetime)(g_th3OwnDeleteMs / 1000) <= 1)\n")
    cases.append(("a tick-clock maintenance window is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-20. P-TH3-DEL3: the stamp itself goes back to the tick clock.
    with_source(TH3RENDER,
                "    g_th3OwnDeleteMs = GetTickCount();\n",
                "    g_th3OwnDeleteMs = (uint)TimeCurrent();\n")
    cases.append(("a tick-clock dropped-object stamp is caught",
                  bool(check_th3_delete())))
    reset()

    # 8q-21. P-TH3-PB-LOCK: the press edge never takes the view (the chart pans
    #        under the hand - the user's report).
    with_source(TH3TOOL,
                "    s_bmViewLockHeld = true; ChartViewLockAcquire();   // P-TH3-PB-LOCK: the drag owns scroll+ctx\n",
                "    s_bmViewLockHeld = false;\n")
    cases.append(("a base press-drag that never takes the view lock is caught",
                  bool(check_th3_pb_lock())))
    reset()

    # 8q-22. P-TH3-PB-LOCK: the held pass stops re-asserting it (a third writer
    #        flips the props mid-gesture).
    with_source(TH3TOOL,
                "    ChartViewLockAssert();   // P-BK-14: a third writer can flip the props mid-gesture\n",
                "")
    cases.append(("a base drag that stops asserting the view lock is caught",
                  bool(check_th3_pb_lock())))
    reset()

    # 8q-23. P-TH3-PB-LOCK: the CLICK fallback keeps the lock (a motionless
    #        release leaves the chart locked with nothing holding it).
    with_source(TH3TOOL,
                "            TH3BaseMarkViewRelease();\n            s_bmDragDown = false; s_bmDragMoved = false;\n            TH3BaseMarkClick(",
                "            s_bmDragDown = false; s_bmDragMoved = false;\n            TH3BaseMarkClick(")
    cases.append(("a base drag whose motionless release keeps the lock is caught",
                  bool(check_th3_pb_lock())))
    reset()

    # 8q-24. P-TH3-PB-LOCK: a cancel no longer releases (right-click mid-drag
    #        leaves the view locked).
    with_source(TH3TOOL,
                "    TH3BaseMarkViewRelease();    // P-TH3-PB-LOCK: a cancel ends the drag's lock too\n",
                "")
    cases.append(("a base mark cancel that leaks the view lock is caught",
                  bool(check_th3_pb_lock())))
    reset()

    # 8q-25. P-TH3-PB-LOCK: the reconcile stops naming the owner, so the 250 ms
    #        watchdog hands the view back under the hand.
    with_source(PANELS,
                "    if(TH3BaseMarkViewOwned()) return true;\n",
                "")
    cases.append(("a reconcile blind to the base mark's own lock is caught",
                  bool(check_th3_pb_lock())))
    reset()

    # 8q-26. P-TH3-PB-DRAG-LOCK (2026-09-22): the band-anchor resize also
    #         takes the view lock (the press-drag lock above only covers the
    #         initial two-click / press-drag DRAW, not the resize).
    with_source(TH3TOOL,
                "        s_bandDragLockHeld = true;\n"
                "        ChartViewLockAcquire();\n",
                "")
    cases.append(("the band-anchor drag takes no view lock on the resize",
                  check_th3_pb_band_drag_lock()))
    reset()

    # 8q-27. P-TH3-PB-DRAG-LOCK: the resize drag stops re-asserting the lock
    #         (a third writer flips the props mid-drag — P-BK-14).
    with_source(TH3TOOL,
                "        ChartViewLockAssert();   // P-BK-14: a third writer can flip the props mid-drag\n",
                "")
    cases.append(("the band-anchor resize stops re-asserting the view lock",
                  check_th3_pb_band_drag_lock()))
    reset()

    # 8q-28. P-TH3-PB-DRAG-LOCK: the resize drag never releases on button-up
    #         (a still release never emits MOUSE_MOVE — P-BK-03 / P-LM-13 —
    #         so the MOUSE_MOVE branch is the heal).
    with_source(TH3TOOL,
                "        if(s_bandDragLockHeld && !leftButtonDown) {\n"
                "            s_bandDragLockHeld = false;\n"
                "            s_bandDragLive = false;\n"
                "            s_bandDragName = \"\";\n"
                "            ChartViewLockRelease();\n"
                "        }\n",
                "")
    cases.append(("the band-anchor resize never releases on button-up",
                  check_th3_pb_band_drag_lock()))
    reset()

    # 8q-29. P-TH3-PB-DRAG-LOCK: the resize drag leaks the lock past the
    #         band's delete (no release path on user delete).
    with_source(TH3TOOL,
                "    if(s_bandDragLockHeld) {\n"
                "        s_bandDragLockHeld = false;\n"
                "        s_bandDragLive = false;\n"
                "        s_bandDragName = \"\";\n"
                "        ChartViewLockRelease();\n"
                "    }\n",
                "")
    cases.append(("the band-anchor resize leaks the lock past the band's delete",
                  check_th3_pb_band_drag_lock()))
    reset()

    # 8q-30. P-TH3-PB-DRAG-LOCK: the heartbeat stops healing (a stuck
    #         terminal or off-chart release never emits button-up).
    with_source(TH3TOOL,
                "void TH3BaseBandDragHeartbeat()\n",
                "")
    cases.append(("the band-anchor resize heartbeat stops healing",
                  check_th3_pb_band_drag_lock()))
    reset()

    # 8q-31. P-TH3-PB-DRAG-LOCK: the reconcile stops naming the band's
    #         own lock, so the 250 ms watchdog hands the view back under
    #         the hand during a resize.
    with_source(PANELS,
                "    if(TH3BaseBandDragViewOwned()) return true;\n",
                "")
    cases.append(("a reconcile blind to the band's resize lock is caught",
                  check_th3_pb_band_drag_lock()))
    reset()

    # 8q-32. P-TH3-PB-DRAG-LOCK: the cascade time window reverts to 1 s —
    #         the DEL2/DEL3 fix was correct for the original commit path
    #         but a multi-second band resize (every step re-draws the
    #         family) queues drops that read a 1 s window as already
    #         closed on a slow chart and wipe a healthy ABCD.
    with_source(TH3TOOL,
                "           && GetTickCount() - g_th3OwnDeleteMs <= 5000)",
                "           && GetTickCount() - g_th3OwnDeleteMs <= 1000)")
    cases.append(("a cascade window that closes before the band drag ends is caught",
                  check_th3_pb_band_drag_lock()))
    reset()

    # 8q-33. P-TH3-BAND-PRESS: the press-edge hit test is gone - the chart
    #         pans between the press and the first OBJECT_DRAG.
    with_source(TH3TOOL,
                "bool TH3BaseBandPressHit(const int mx, const int my)\n",
                "")
    cases.append(("a band press that cannot hit-test the outline is caught",
                  check_th3_band_gesture()))
    reset()

    # 8q-34. P-TH3-BAND-PRESS: the move stream stops claiming the view on the
    #         press edge (the lock is back to first-OBJECT_DRAG only).
    with_source(TH3TOOL,
                "                if(!s_bandDragLockHeld\n"
                "                   && TH3BaseBandPressHit((int)lparam, (int)dparam)) {",
                "                if(false) {")
    cases.append(("a move stream that never claims the band press is caught",
                  check_th3_band_gesture()))
    reset()

    # 8q-35. P-TH3-BAND-PRESS: the idle-move early-out stops naming the live
    #         band gesture - the button-up release branch becomes dead code
    #         and every resize leaks the lock to the 1.5 s heartbeat.
    with_source(TH3TOOL,
                "       && !s_bandDragLockHeld && ObjectFind(0, TH3_BASE_EDITOR) < 0) return;",
                "       && ObjectFind(0, TH3_BASE_EDITOR) < 0) return;")
    cases.append(("an early-out that starves the band's release edge is caught",
                  check_th3_band_gesture()))
    reset()

    # 8q-36. P-TH3-BANDSEL: the OBJECT_CLICK else-branch deselects on the
    #         TH3 tool's own namespace again (the band's click and every
    #         band drag's click echo blank the active pattern).
    with_source(EVENTS,
                "        else if(StringFind(sparam, \"TH3_\") != 0)\n",
                "        else\n")
    cases.append(("a click on the band that blanks the pattern is caught",
                  check_th3_band_gesture()))
    reset()

    # 8q-17. P-TH3-INFO-11: the heal net stops verifying (dead question).
    # The anchor is the call's CURRENT text — the trailing comment is part of the
    # line, and a seed that no longer matches the source proves nothing (it was
    # reported as STALE, and the three cases below it went uncaught).
    with_source(TH3RENDER,
                "    TH3InfoFamilyVerify(base, true);              // (its grow re-arms the visit)\n",
                "    ;\n")
    cases.append(("a caption heal that verifies nothing is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-18. P-TH3-INFO-11: the timer never runs the heal (dead net).
    with_source(ENTRY, "    TH3InfoCaptionHeal();\n", "")
    cases.append(("a timer that never runs the caption heal is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-2. P-TH3-INFO-02: the caption's safe-Y forgets the mode rows' +45
    #       below-ATR offset - the plate parks inside the mode block.
    with_source(TH3TOOL,
                "            modeBottomY = inpModeLabelYDistance + g_modeLabelYOffset + 45 + modeBlockHeight + 4;\n",
                "            modeBottomY = inpModeLabelYDistance + g_modeLabelYOffset + modeBlockHeight + 4;\n")
    cases.append(("a caption safe-Y that forgets the modes' +45 is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-3. P-TH3-INFO-10: the hide path masks the PLATE again - an
    #       OBJ_RECTANGLE_LABEL ignores that mask, so the rows go dark and the
    #       empty bar stays (the user's «اول نمایش میده ولی بعد دیگه فقط سیاه»).
    with_source(TH3RENDER, "    if(!visible) { TH3InfoFamilyPlateDrop(base); return; }",
                "    if(!visible) { ObjectSetInteger(0, plate, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); return; }")
    cases.append(("a family hide that masks the plate is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-4. P-TH3-INFO-10: the writer keeps a plate under an INACTIVE family
    #       (and masks it instead of dropping it).
    with_source(TH3RENDER, "    if(!isActive) { TH3InfoFamilyPlateDrop(base); return n; }",
                "    if(!isActive) { ObjectSetInteger(0, plate, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); return n; }")
    cases.append(("a caption writer that plates a dark family is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-5. P-TH3-INFO-10: the healer stops dropping an inactive family's plate
    with_source(TH3RENDER, "    if(!isActive) { TH3InfoFamilyPlateDrop(base); return; }",
                "    if(!isActive) { return; }")
    cases.append(("a verify that leaves an inactive plate on the chart is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-6. P-TH3-INFO-10: the active sweep masks the plate instead of deleting it
    with_source(TH3TOOL, "        if(TH3IsInfoPlateName(nm)) ObjectDelete(0, nm);",
                "        ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);")
    cases.append(("an active sweep that masks the plate is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-7. P-TH3-INFO-12: the grow path leaves rows older than the plate it
    #       just grew - creation order paints them UNDER it (the black box).
    with_source(TH3RENDER,
                "    for(int line = 0; line < n; line++)\n    {\n        string nm = TH3InfoLineName(base, line);\n        ObjectDelete(0, nm);\n        TH3RORowAt(nm, rows[line], corner, nearX,",
                "    for(int line = 0; line < n; line++)\n    {\n        string nm = TH3InfoLineName(base, line);\n")
    cases.append(("a grow that leaves rows under their own fresh plate is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-8. P-TH3-INFO-13: the heal resurrects an expired caption visit.
    with_source(TH3RENDER,
                "    if(TH3InfoVisitPending() && !TickDeadlinePending(g_th3InfoVisitUntilMs))\n",
                "    if(false)\n")
    cases.append(("a heal that resurrects an expired caption is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-9. P-TH3-INFO-13: the visit clock stops reading inpModeLabelDuration
    with_source(TH3RENDER, "    int durSec = inpModeLabelDuration;",
                "    int durSec = 5;")
    cases.append(("a caption visit on its own private duration is caught",
                  bool(check_th3_caption())))
    reset()

    # 8q-10. P-UI-57f-OFF: the step-mode row regains its clock exemption
    with_source(UTILS,
                "        if(g_stepModeLabelCreateTime > 0) {\n            if((now - g_stepModeLabelCreateTime) >= durationMs) {\n                ClearSingleModeLabel(g_stepModeLabelName, g_stepModeLabelCreateTime);\n                anyCleared = true;\n            } else {\n                anyRemaining = true;\n            }\n        }\n",
                "")
    cases.append(("a step-mode row that outlives its duration is caught",
                  bool(check_th3_caption())))
    reset()

    # 8r. P-LM-09: the leg plate's visit has no clock on the entry's timer - the only
    #     thing running on a chart that is not ticking (weekend, dead symbol).
    with_source(ENTRY, "    LegMeasureExpireSweep();\n", "")
    cases.append(("a leg readout whose expiry never runs is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8s. P-LM-09: the STILL-CLICK path stops calling the readout back (the plate
    #     expires once and is never readable again; the moved path's own call is
    #     not a click).
    with_source(TH3TOOL,
                "        LegMeasurePlateShow(base);\n        return;\n    }\n",
                "        return;\n    }\n")
    cases.append(("a click that cannot bring the leg readout back is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8t. P-LM-09: the plate is deleted in pieces (row 3 survives its plate).
    with_source(TH3TOOL, '    ObjectDelete(0, base + "_Info3");\n', "")
    cases.append(("a half-deleted leg readout is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8u. P-LM-09: the follower resurrects a plate that has finished its visit.
    with_source(TH3TOOL, "        if(g_legPlateUp[i])\n",
                "        if(true)\n")
    cases.append(("a follower that re-opens an expired readout is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8v. P-LM-23: the plate stops going through its one place - a hardcoded box
    #     near the tip instead of the tip's own continuation.
    with_source(TH3TOOL, "    LegInfoBoxTop(tipX, tipY, dirX, dirY, bw, bh, bx, by);\n",
                "    bx = tipX - bw / 2; by = tipY - LEG_INFO_GAP - bh;\n")
    cases.append(("a plate that bypasses its one tip place is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8v-2. P-LM-23: the tip-to-plate gap collapses - the plate sits ON the tip.
    with_source(TH3TOOL, "#define LEG_INFO_GAP        40",
                "#define LEG_INFO_GAP        0")
    cases.append(("a plate with no distance from its tip is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8v-3. P-LM-23: the hit test returns - a busy LINE slot falls back to a box
    #       on the candles again.
    with_source(TH3TOOL, "    LegInfoClampY(ch, bh, by);\n",
                "    LegInfoClampY(ch, bh, by);\n"
                "    if(LegInfoHits(bx, by, bw, bh) > 0) { bx = tipX - bw / 2; by = tipY - LEG_INFO_GAP - bh; }\n")
    cases.append(("a plate that walks off its tip when busy is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8w. P-BUILD-01's shape, on this tool: Lite runs the UI half's sweep.
    with_source(ENTRY_LITE, "    CoopPump();\n",
                "    CoopPump();\n    LegMeasureExpireSweep();\n")
    cases.append(("a Lite entry running the leg meter's sweep is caught",
                  bool(check_leg_plate_lifetime())))
    reset()

    # 8x. P-LM-11: the drag step stops re-anchoring through the family's ONE writer —
    #     a part written elsewhere moves on another schedule (the lag is back).
    #     P-LM-19: the ink the drag writes is the leg's OWN direction (dragInk),
    #     not the fixed violet, so the seed anchors on that writer.
    with_source(TH3TOOL, "    LegMeasureInk(base, nt1, np1, nt2, np2, dragInk, false);\n", "")
    cases.append(("a drag that bypasses the family's one writer is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8y. P-LM-12: the preview's teardown loses its retired-name sweep - a preview
    #     mid-gesture from an older build could outlive this one wearing a head.
    with_source(TH3TOOL, '    ObjectDelete(0, "LM_prev_Arrow");   // retired name (P-LM-12)\n', "")
    cases.append(("a preview whose retired head sweep is dropped is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ag. P-LM-12: the arrowhead returns to the committed family (the shape owner
    #      is resurrected) - the user retired the head explicitly.
    with_source(TH3TOOL,
                "    LegMeasureHandles(base, t1, p1, t2, p2, ink);\n",
                "    LegMeasureHandles(base, t1, p1, t2, p2, ink);\n"
                "    LegArrowAt(base + \"_Arrow\", t1, p1, t2, p2, ink, 0);\n")
    cases.append(("an arrowhead back on the committed leg is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ah. P-LM-12: the draw preview wears an arrow again.
    with_source(TH3TOOL,
                "        // P-LM-12: the preview is the dashed line and NOTHING else — the head\n"
                "        // it used to wear was retired with the committed drawing's own head.\n"
                "        return false;",
                "        LegArrowAt(\"LM_prev_Arrow\", g_legSess.t1, g_legSess.p1, curT, curP, preCol, 0);\n"
                "        return false;")
    cases.append(("a preview wearing an arrow again is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8z. P-LM-11: the edit owner loses its MOUSE_MOVE route - the drag has no event
    #     to move in.
    with_source(EVENTS,
                "    if(id == CHARTEVENT_MOUSE_MOVE && LegMeasureEditMouse((int)lparam, (int)dparam, sparam))\n",
                "")
    cases.append(("a drag with no mouse-event owner is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8aa. P-LM-11: a retired channel comes back (chasing a drag that no longer
    #      exists natively).
    with_source(ENTRY, "    LegMeasureExpireSweep();\n",
                "    LegMeasureExpireSweep();\n    LegMeasureFollowTimer();\n")
    cases.append(("a retired drag channel wired back into the entry is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ab. P-LM-17: the line stops being SELECTABLE - the terminal's own gestures
    #      (right-click Properties/Delete, keyboard Delete) go deaf.
    with_source(TH3TOOL,
                "            ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, true);",
                "            ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);")
    cases.append(("a non-selectable leg line (native gestures go deaf) is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ab-2. P-LM-17: the re-own retreats into the create branch only - a leg the
    #        non-selectable era (P-LM-11) drew stays SELECTABLE=false through the
    #        migration and its right-click Delete never comes («مثل بقیه ابجکت ها
    #        دکمه دیلیتش نمیاد»).
    with_source(TH3TOOL,
                "        bool dragOwnsThis = (s_legDragMode != 0 && s_legDragBase == base);\n"
                "        if(!dragOwnsThis && !ObjectGetInteger(0, ln, OBJPROP_SELECTABLE))\n"
                "            ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, true);\n",
                "")
    cases.append(("a create-only SELECTABLE (legacy legs stay deaf) is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ab-2b. P-LM-21: the drag stops disarming the native drag - the line moves on
    #         the terminal's paint schedule and the discs stay behind it.
    with_source(TH3TOOL, "        LegMeasureDragSelectable(s_legDragBase, false);\n", "")
    cases.append(("a drag that lets the terminal move the line alone is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ab-2c. P-LM-21: the commit forgets to return the borrowed flag - the leg is
    #         deaf to every native gesture from the first drag on.
    with_source(TH3TOOL, "    LegMeasureDragSelectable(base, true);\n", "")
    cases.append(("a drag commit that keeps the line unselectable is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ab-2d. P-LM-21: the ABORT path keeps the flag - a cancelled drag leaves the
    #         same deafness behind.
    with_source(TH3TOOL, "        LegMeasureDragSelectable(base, true);\n", "")
    cases.append(("a drag abort that keeps the line unselectable is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ab-2e. P-LM-21: the borrower loses its guard on the line's existence.
    with_source(TH3TOOL,
                "    if(ObjectFind(0, ln) < 0) return;\n"
                "    if((bool)ObjectGetInteger(0, ln, OBJPROP_SELECTABLE) == draggable) return;\n",
                "    if((bool)ObjectGetInteger(0, ln, OBJPROP_SELECTABLE) == draggable) return;\n")
    cases.append(("a drag selectable write blind to the line is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ab-3. P-LM-18: the selection loses its face - the mid handle stops asking
    #        the terminal's own selection and a selected leg reads exactly like
    #        a resting one («حالت سلکتش با سلکت نبودنش ... یک شکله»).
    with_source(TH3TOOL,
                '    string bmpM = up ? (sel ? LEG_HANDLE_UP_MID_SEL_RES : LEG_HANDLE_UP_MID_RES)\n'
                '                     : (sel ? LEG_HANDLE_DN_MID_SEL_RES : LEG_HANDLE_DN_MID_RES);\n',
                '    string bmpM = up ? LEG_HANDLE_UP_MID_RES : LEG_HANDLE_DN_MID_RES;\n')
    cases.append(("handles that ignore the selection (solid on selected) are caught",
                  bool(check_leg_selection())))
    reset()

    # 8ab-4. P-LM-18: the ride channels stop re-widthing the line - a native click
    #        that selects the leg never widens it, the state change has no event
    #        left to answer in.
    with_source(TH3TOOL, "        int w = LegMeasureLineWidth(g_legBase[i]);\n",
                "        int w = LEG_LINE_W;\n")
    cases.append(("a ride pass that drops the selection width is caught",
                  bool(check_leg_selection())))
    reset()

    # 8ab-5. P-LM-18: the ink pass drops the selection width - a drag on a selected
    #        leg would fall back to the resting width mid-gesture.
    with_source(TH3TOOL, "        int w = LegMeasureLineWidth(base);\n",
                "        int w = LEG_LINE_W;\n")
    cases.append(("an ink pass that drops the selection width is caught",
                  bool(check_leg_selection())))
    reset()

    # 8ab-6. P-LM-18: a hollow raster loses its #resource - the selected face goes
    #        blank (an icon outside the embedding is a ghost).
    with_source(TH3TOOL,
                '#resource "\\\\Files\\\\Icons\\\\leg_handle_up_sel.bmp"\n', "")
    cases.append(("a selected-handle raster without its #resource is caught",
                  bool(check_leg_selection())))
    reset()

    # 8ab-7. P-LM-19: the two direction colours converge - the axis is retired in
    #        everything but name, and every leg on the chart wears one ink.
    with_source(TH3TOOL, "#define LEG_BULL_INK   C'31,95,255'",
                "#define LEG_BULL_INK   C'224,64,64'")
    cases.append(("a leg meter whose two direction colours are one is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-8. P-LM-19: the up leg stops being the strong blue the user asked for.
    with_source(TH3TOOL, "#define LEG_BULL_INK   C'31,95,255'",
                "#define LEG_BULL_INK   C'0,168,107'")
    cases.append(("an up leg that is no longer the strong blue is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-9. P-LM-19: the drag re-inks through the fixed violet again - a coloured
    #        leg turns violet under the hand.
    with_source(TH3TOOL, "    LegMeasureInk(base, nt1, np1, nt2, np2, dragInk, false);\n",
                "    LegMeasureInk(base, nt1, np1, nt2, np2, LEG_INK, false);\n")
    cases.append(("a drag that re-inks the leg in the fixed violet is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-10. P-LM-19: the drag's ink stops answering the leg's own direction -
    #         a leg dragged past horizontal keeps its old colour.
    with_source(TH3TOOL,
                '    color dragInk = ((nt2 >= nt1 ? np2 : np1) >= (nt2 >= nt1 ? np1 : np2))\n'
                '                    ? LEG_BULL_INK : LEG_BEAR_INK;\n',
                "    color dragInk = LEG_BULL_INK;\n")
    cases.append(("a drag that ignores the leg's direction is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-11. P-LM-19: the preview goes back to the fixed violet - the user cannot
    #         see which leg he is drawing until the release.
    with_source(TH3TOOL,
                "        color preCol = ((curP >= g_legSess.p1) ? LEG_BULL_INK : LEG_BEAR_INK);\n",
                "        color preCol = LEG_INK;\n")
    cases.append(("a preview that hides the leg's direction is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-12. P-LM-19: the ATR goes back to a raw Wilder read - a second ruler next
    #         to the composite the labels read.
    with_source(TH3TOOL, "    double a = CalculateWeightedATR(CompatTF(tf));\n",
                "    double a = iATR(NULL, tf, 14, 1);\n")
    cases.append(("an ATR that is not the labels' own composite is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-12b. P-LM-22: the readout badges the bar-count gate again - a free
    #          measurement wears the closed step's grid rule (P-TH3-STEP-08/10).
    with_source(TH3TOOL, "    ownerTF = TH3LegOwnerTF(legSize, trusted);\n",
                "    ownerTF = TH3ClosedOwnerTF(60);\n")
    cases.append(("a leg readout back on the bar-count gate is caught",
                  bool(check_leg_tf())))
    reset()

    # 8ab-12c. P-LM-22: the band drifts off the user's 240-360.
    with_source(TH3TOOL, "#define TH3_LEG_TF_HI   3.60",
                "#define TH3_LEG_TF_HI   5.00")
    cases.append(("a leg TF band that is not 240-360 is caught",
                  bool(check_leg_tf())))
    reset()

    # 8ab-12d. P-LM-22: the walk stops clearing trusted on a TF with no
    #          history - an unjudged step prints as read.
    with_source(TH3TOOL, "        if(a <= 0) { trusted = false; break; }\n",
                "        if(a <= 0) { break; }\n")
    cases.append(("a leg TF walk that trusts an unjudged step is caught",
                  bool(check_leg_tf())))
    reset()

    # 8ab-12e. P-LM-22: the walk judges through a raw Wilder read - a second
    #          ruler next to the labels' composite.
    with_source(TH3TOOL, "        double a = LegAtr14(tf);",
                "        double a = iATR(NULL, tf, 14, 1);")
    cases.append(("a leg TF walk off the labels' composite is caught",
                  bool(check_leg_tf())))
    reset()

    # 8ab-13. P-LM-19: the placement offset collapses back onto the grab radius -
    #         the handle's visual centre lands a pixel past its anchor.
    with_source(TH3TOOL, "#define LEG_HANDLE_HALF      7",
                "#define LEG_HANDLE_HALF      6")
    cases.append(("a handle placed at its grab radius, not its canvas centre, is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-14. P-LM-19: the mid handle stops rounding the exact pixel midpoint -
    #         truncating integer division sits it a pixel off the true 50%.
    with_source(TH3TOOL,
                "                      (int)MathRound(((double)sx + (double)tx) * 0.5),\n"
                "                      (int)MathRound(((double)sy + (double)ty) * 0.5),\n",
                "                      (sx + tx) / 2,\n"
                "                      (sy + ty) / 2,\n")
    cases.append(("a mid handle that does not sit on the exact 50% is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-15. P-LM-19: the generator's palette drifts off the line's ink - the
    #         baked icons and the line disagree about the direction.
    with_source(GENICONS, "const LEG_UP_RGB    = [31, 95, 255];",
                "const LEG_UP_RGB    = [0, 168, 107];")
    cases.append(("a baked palette out of step with the line's ink is caught",
                  bool(check_leg_direction())))
    reset()

    # 8ab-16. P-LM-20: the atomic repaint goes - the selection is assembled from
    #         pieces again, and the line and the discs disagree about it.
    #         (strip_comments removes the trailing P-LM-20 marker, so the anchor
    #         is the repaint's own writer call.)
    with_source(TH3TOOL,
                "    LegMeasureInk(base, t1, p1, t2, p2, ink, false);\n"
                "}\n",
                "    LegMeasureHandles(base, t1, p1, t2, p2, ink);\n"
                "}\n")
    cases.append(("a selection repaint that bypasses the one ink writer is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ab-17. P-LM-20: the OBJECT_CLICK handler goes - a still click selects the
    #         line and nothing answers it until the chart happens to move.
    with_source(TH3TOOL,
                "    string base = StringSubstr(objName, 0, len - 5);\n"
                "    LegMeasureSelectionRepaint(base);   // ONE pass: line + the three discs\n"
                "    return true;\n",
                "    return true;\n")
    cases.append(("a selection that the terminal reports and nothing answers is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ab-18. P-LM-20: the router stops carrying OBJECT_CLICK - the terminal's own
    #         selection event never reaches the family.
    with_source(EVENTS, "        if(LegMeasureOnObjectClick(sparam)) ThrottledChartRedraw();\n",
                "        ThrottledChartRedraw();\n")
    cases.append(("an OBJECT_CLICK the leg meter never sees is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ab-19. P-LM-20: the router's else-branch goes - a click elsewhere
    #         DESELECTS the line and the family keeps the selected face.
    with_source(EVENTS,
                "        else LegMeasureRideChart();   // a click off the family: deselection lands whole\n",
                "")
    cases.append(("a deselection the family keeps painting as selected is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ab-20. P-LM-20: the handle ZORDER stops being re-asserted on every pass - a
    #         leg the pre-ZORDER build drew keeps its discs under the line forever.
    with_source(TH3TOOL,
                "    ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_CHART_LEG_HANDLE);\n", "")
    cases.append(("a handle whose ZORDER is only set at create is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ab-20b. P-LM-20 / P-UI-31: the rung is read back before it is written.
    with_source(TH3TOOL, "    ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_CHART_LEG_HANDLE);\n",
                "    if((int)ObjectGetInteger(0, hn, OBJPROP_ZORDER) != Z_CHART_LEG_HANDLE)\n"
                "        ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_CHART_LEG_HANDLE);\n")
    cases.append(("a handle whose rung is read back is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ab-21. P-LM-20: the shadow becomes an authority - it reads the terminal's
    #         own flag and a selection changed outside any event we see goes
    #         unanswered.
    with_source(TH3TOOL,
                "    for(int i = 0; i < s_legSelCount; i++)\n"
                "    {\n"
                "        if(s_legShadowBase[i] != base) continue;\n",
                "    bool realSel = LegMeasureSelected(base);\n"
                "    for(int i = 0; i < s_legSelCount; i++)\n"
                "    {\n"
                "        if(s_legShadowBase[i] != base) continue;\n"
                "        if(s_legSelState[i] == realSel) return false;\n")
    cases.append(("a selection shadow that reads the terminal itself is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ab-22. P-LM-20: the delete path stops forgetting the shadow - a re-created
    #         leg of the same stamp inherits another leg's painted state.
    with_source(TH3TOOL, "    LegMeasureSelShadowForget(base);  // P-LM-20: its painted "
                         "state goes with it\n", "")
    cases.append(("a delete that leaves the painted state behind is caught",
                  bool(check_leg_sel_atomic())))
    reset()

    # 8ac. P-LM-11: the ink writer stops building the handles - a measurement can
    #      exist without its rings.
    with_source(TH3TOOL, "    LegMeasureHandles(base, t1, p1, t2, p2, ink);\n", "")
    cases.append(("a family drawn without its handle rings is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ad. P-LM-13/14: the handle reverts to a chart-space ellipse - the shape that
    #      drew as a hairline at working zoom (an ellipse whose anchors share a bar).
    with_source(TH3TOOL,
                "        if(!ObjectCreate(0, hn, OBJ_BITMAP_LABEL, 0, 0, 0)) return;",
                "        if(!ObjectCreate(0, hn, OBJ_ELLIPSE, 0, t, p, t, p)) return;")
    cases.append(("a chart-space ellipse handle (the hairline) is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ai. P-LM-14: the icon stops being centred on its anchor - it hangs off the
    #      line end by half its own width.
    with_source(TH3TOOL,
                "    int nx = x - half, ny = y - half;    // the icon's CENTRE sits on the anchor",
                "    int nx = x, ny = y;")
    cases.append(("a handle hanging off its anchor is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8aj. P-LM-13: CHARTEVENT_CLICK stops reaching the motionless-click finalize -
    #      the drag state sticks live and nothing can be deleted or selected.
    with_source(EVENTS,
                "    if(id == CHARTEVENT_CLICK) LegMeasureClickFinalize();\n", "")
    cases.append(("a stuck drag no motionless click can end is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ak. P-LM-17: the click gesture deletes DIRECTLY again - a stray click
    #      costs a drawing.
    with_source(TH3TOOL,
                "        LegMeasurePlateShow(base);\n        return;",
                "        LegMeasureDelete(base);\n        LegMeasurePlateShow(base);\n        return;")
    cases.append(("a click that deletes the leg outright is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8al. P-LM-17: the ink stops answering the leg's DIRECTION (automatic
    #      bull/bear colouring).
    with_source(TH3TOOL,
                "    accent = (pLate >= pEarly) ? LEG_BULL_INK : LEG_BEAR_INK;",
                "    accent = LEG_BULL_INK;")
    cases.append(("a leg meter with one fixed colour is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8am. P-LM-17: the native delete stops cascading to the family - the icons
    #      and the plate survive their own line.
    with_source(EVENTS, "        LegMeasureOnObjectDelete(sparam);", "")
    cases.append(("a native deletion that leaves the family behind is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8an. P-LM-16b: the dots stop riding the chart in the MOUSE_MOVE event - a
    #      drag-pan separates them from the line (the user's screenshot).
    with_source(TH3TOOL,
                "    LegMeasureRideChart();\n\n    bool leftDown  = (StringFind(buttons, \"1\") >= 0);",
                "    bool leftDown  = (StringFind(buttons, \"1\") >= 0);")
    cases.append(("dots left behind by a drag-pan are caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8ae. P-LM-11: the edit owner stops standing down while another gesture holds
    #      the view lock - a leg would steal a panel's/menu's press (P-UI-90).
    with_source(TH3TOOL,
                "    if(ChartViewLockHeld()) return false;\n",
                "")
    cases.append(("a leg that steals the pointer from a held gesture is caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8af. P-LM-17: the handles stop following the line's direction colour - the
    #      icons and the line disagree about bullish and bearish.
    with_source(TH3TOOL,
                '    string bmpH = up ? (sel ? LEG_HANDLE_UP_SEL_RES     : LEG_HANDLE_UP_RES)\n'
                '                     : (sel ? LEG_HANDLE_DN_SEL_RES     : LEG_HANDLE_DN_RES);\n',
                '    string bmpH = LEG_HANDLE_UP_RES;\n')
    cases.append(("handles ignoring the leg's direction colour are caught",
                  bool(check_leg_head_follow())))
    reset()

    # 8m. P-UI-96b: the duplicate-point guard is dropped (a held click is stored twice)
    with_source(TH3CTRL,
                "           MathAbs(g_th3Session.points[prev].price - p) <= GetCachedPoint())",
                "           false)")
    cases.append(("a session that can spend one press as two pivots is caught",
                  bool(check_th3_item())))
    reset()

    # 8l. the arming press is spent as pivot X (the swallow is no longer forwarded)
    with_source(TH3TOOL, "TH3SessionStart(fromRingItem);", "TH3SessionStart();")
    cases.append(("an arm that lets its own press become pivot X is caught",
                  bool(check_th3_item())))
    reset()

    # 8n. P-UI-97: a bright literal written straight into OBJPROP_COLOR again (the
    #     session's placed letter - the ink the user could not see on white)
    with_source(TH3CTRL, "TH3SessionPointInk());", "clrYellow);")
    cases.append(("a hardcoded bright session ink is caught", bool(check_th3_ink())))
    reset()

    # 8m3. P-TH3-INFO-04: the readout plate's palette is allowed BY NAME, so a raw
    #      bright literal on the plate itself is still the bug (the allowance is
    #      narrow: it is the palette, not "anything on the plate")
    with_source(TH3RENDER, "        ObjectSetInteger(0, plate, OBJPROP_COLOR,       TH3RO_EDGE);",
                "        ObjectSetInteger(0, plate, OBJPROP_COLOR,       clrYellow);")
    cases.append(("a raw ink on the readout plate is caught",
                  bool(check_th3_ink())))
    reset()

    # 8o. P-UI-97: an ink setting reaches OBJPROP_COLOR without the resolver
    with_source(TH3RENDER, "TH3InkForChart(inpABCDInfoColor)", "inpABCDInfoColor")
    cases.append(("an unresolved pattern ink is caught", bool(check_th3_ink())))
    reset()

    # 8p. P-UI-97: the resolver is deleted (nothing decides what reads on the paper)
    with_source(TH3CTRL, "color TH3InkForChart(", "color TH3InkForCharts(")
    cases.append(("a missing ink owner is caught", bool(check_th3_ink())))
    reset()

    # 9. a non-ASCII caption (the P-LBL-02 lesson, on the panel side)
    with_source(PANELS, 'else if(row==9)  { kind=1; label="H/L PIP LABELS"; }',
                'else if(row==9)  { kind=1; label="برچسب‌ها"; }')
    cases.append(("a caption in another script is caught", bool(check_captions())))
    reset()

    # 10. the TRex card's own panel controls disappear again (the user's ask)
    with_source(PANELS, 'else if(row==11) { label="TRADE SIZE"; minV=0; maxV=24; unit="pt"; }',
                "")
    cases.append(("the TRex card's panel settings are caught if removed",
                  bool(check_trex_card() or check_rows())))
    reset()

    # 11. a colour row is shown from one copy and written to another
    with_source(PANELS, "case PAL_ATR_TRADE:     g_atrTradeRowColor = clr;    g_labelsRelayoutNeeded=true; break;",
                "case PAL_ATR_TRADE:     g_atrTradeSpreadColor = clr; g_labelsRelayoutNeeded=true; break;")
    cases.append(("a swatch that writes a different copy is caught",
                  bool(check_palette())))
    reset()

    # 12. P-UI-71: the index-bounded purge comes back (the ghost row)
    with_source(PANELS, "   ObjectsDeleteAll(0, head, -1, -1);",
                "   for(int r=0;r<PNL_CARD_ROWS_MAX;r++) ObjectDelete(0,head+IntegerToString(r));")
    cases.append(("a card teardown that cannot cover its rows is caught",
                  bool(check_purge())))
    reset()

    # 12b. P-PERF-47: the ONE wipe is bounded to the main subwindow again
    with_source(PANELS, "   ObjectsDeleteAll(0, head, -1, -1);",
                "   ObjectsDeleteAll(0, head, 0, -1);")
    cases.append(("a card wipe bounded to one subwindow is caught",
                  bool(check_purge())))
    reset()

    # 12c. P-TH-01: the knob's own read disappears (the slider writes a mirror
    #      nothing consumes — P-UI-47, one layer deeper)
    with_source(FRACTALS, "if(g_thPercentOverride <= 0.0) return 1.0;", "")
    cases.append(("a research knob nothing consumes is caught",
                  bool(check_th_percent())))
    reset()

    # 12d. a DRAWING reader skips the knob (the slider moves, the chart does not)
    with_source(THCALC, "double percentage = FractalPercentScaled(i);",
                "double percentage = FractalPercentRaw(i);")
    cases.append(("a ladder reader that skips the knob is caught",
                  bool(check_th_percent())))
    reset()

    # 12e. a MEASURING STICK starts following the knob — the quiet one: the chart
    #      still draws, but the fractal shift (and the zone hierarchy) now moves
    #      with the research knob.
    with_source(ADAPT, "double p = MODIFIED_FRACTAL_PERCENTAGES[i];",
                "double p = FractalPercentScaled(i);")
    cases.append(("a measuring stick that follows the knob is caught",
                  bool(check_th_percent())))
    reset()

    # 12f. the knob change stops invalidating the CACHED rung->percentage (the
    #      chart keeps drawing the old ladder until something else clears it)
    with_source(PANELS, "               InvalidateTimeframeDependentCaches();\n", "")
    cases.append(("a knob whose change is cached away is caught",
                  bool(check_th_percent())))
    reset()

    # 12g. a SECOND module reads the mirror (two ladders that can disagree)
    with_source(THCALC, "double GetTimeframeTH() {",
                "double GetTimeframeTH() { double _k = g_thPercentOverride;")
    cases.append(("a second ladder owner is caught",
                  bool(check_th_percent())))
    reset()

    # 13. the row naming and the purge prefix stop agreeing
    with_source(PANELS, 'return g_UI.btnPrefix + "Pnl" + IntegerToString(item) + "_" + IntegerToString(row) + "_" + kind;',
                'return g_UI.btnPrefix + "Pnl" + IntegerToString(item) + IntegerToString(row) + "_" + kind;')
    cases.append(("a naming shape the wipe cannot match is caught",
                  bool(check_purge())))
    reset()

    # 14. the spec slice is smaller than a card (rows silently dropped)
    with_source(PANELS, "#define PNL_SPEC_MAX 32", "#define PNL_SPEC_MAX 16")
    cases.append(("a spec slice that would DROP a card's rows is caught",
                  bool(check_card_body())))
    reset()

    # 15. the footer cap loses its margin (the body stops short of the card)
    with_source(PANELS, "#define PNL_CARD_BOT_H   (PNL_FOOT_H + PNL_MARGIN)   // 62  footer + margin",
                "#define PNL_CARD_BOT_H   (PNL_FOOT_H)                // footer")
    cases.append(("a body that does not reach the card's bottom is caught",
                  bool(check_card_body())))
    reset()

    # 16. P-UI-71c: the composed body is referenced but no longer DECLARED — the
    #     exact defect that shipped (a whole card with no chrome), which every
    #     previous check passed because the files were there and the arithmetic
    #     added up.
    with_source(PANELS, '#resource "\\\\Files\\\\Icons\\\\pnl_cardWmid.bmp"\n', "")
    cases.append(("a bitmap with no #resource declaration is caught",
                  bool(check_chrome())))
    reset()

    # 17. a runtime reference to a bitmap that is not on disk (a typo = blank)
    with_source(PANELS, '"::Files\\\\Icons\\\\pnl_cardWtop.bmp", Z_PANEL_CARD);',
                '"::Files\\\\Icons\\\\pnl_cardWtp.bmp", Z_PANEL_CARD);')
    cases.append(("a runtime reference to a missing bitmap is caught",
                  bool(check_chrome())))
    reset()

    # 18. the finalizer tears down again without asking whether the button is up
    #     (P-UI-83 widened the gate to the down-recency witness; the seed asks
    #     about the WITNESS, so it moves with the site, not with the string)
    with_source(PANELS, "   if(!UILeftButtonUp() || !PnlPointerQuiet()) return;",
                "   if(false) return;")
    cases.append(("a press-side echo that can kill the drag is caught",
                  bool(check_mouse())))
    reset()

    # 19. a second probe of the same property (the two conventions disagree)
    with_source(BASEKNOT, "      UILeftButtonUp() &&          // the ONE button owner (P-UI-73): both MQL4",
                "      (TerminalInfoInteger(TERMINAL_KEYSTATE_LEFT) & 1) == 0 &&   // both MQL4")
    cases.append(("a local button probe outside the owner is caught",
                  bool(check_mouse())))
    reset()

    # 20. opening a card stops taking the pointer away from the ring
    with_source(PANELS, "   CircAbortRingGesture(); // P-UI-73: a ring long-press latch armed BEFORE this",
                "")
    cases.append(("a ring latch that can outlive the card open is caught",
                  bool(check_mouse())))
    reset()

    # 21. P-UI-74: the name router stops carrying the second channel
    with_source(PANELS, "   if(PnlClickFallback(mouseX, mouseY)) return REFRESH_NONE;",
                "   // seed: the click channel is gone")
    cases.append(("a control reachable from one delivery channel only is caught",
                  bool(check_dual())))
    reset()

    # 22. the plain CHARTEVENT_CLICK no longer dispatches (the bitmap-skinned
    #     cell's ONLY event kind)
    with_source(PANELS, "      if(StringFind(sparam, \"r\") < 0 && PnlClickFallback(cx, cy)) return;",
                "      // seed: no click dispatch")
    cases.append(("a click that never reaches the card's dispatch is caught",
                  bool(check_dual())))
    reset()

    # 23. the latch arms the release claim on the click channel too
    with_source(PANELS, "   if(!s_PnlClickChannel) UISuppressNextClick();",
                "   UISuppressNextClick();")
    cases.append(("a click-channel action that eats the NEXT click is caught",
                  bool(check_dual())))
    reset()

    # 24. the press echo of a click that already acted is acted on again
    with_source(PANELS, "      if(s_PnlClickActed) { s_PnlClickActed = false; return; }",
                "")
    cases.append(("a gesture that acts once per channel (twice) is caught",
                  bool(check_dual())))
    reset()

    # 25. PANELDRAG-OFF: the retired arm is UNCOMMENTED without a decision - the
    #     removed gesture is half-restored, which is the one way this feature can
    #     come back without anybody choosing it
    with_source(PANELS, "      // if(!s_PnlClickChannel) PnlTryGrabMove(mx,my,false);",
                "      if(!s_PnlClickChannel) PnlTryGrabMove(mx,my,false);")
    cases.append(("a half-restored card-move arm is caught",
                  bool(check_dual() or check_drag() or check_paneldrag_off())))
    reset()

    # 26. the palette's colour ids go back to a prefix test
    with_source(PANELS, "   if(PalMatIdParse(id,mr,mc))",
                "   if(StringFind(id,\"s\")==0)")
    cases.append(("a prefix-parsed swatch id is caught", bool(check_dual())))
    reset()

    # 27. P-UI-75b: the drag stops paying for its own frame (the card jumps
    #     behind the cursor again - the coordinates land faster than the paint)
    with_source(PANELS, "   DragFrameRedraw();    // the drag's own frame, once per applied batch",
                "   // seed: the batch no longer pays for its frame")
    cases.append(("a drag whose frame lags its coordinates is caught",
                  bool(check_drag())))
    reset()

    # 28. a THIRD writer of the card's coordinates appears - two writers cannot
    #     share one frame window
    with_source(PANELS, "   PnlMoveBy(g_PnlOpen, ndx, ndy);\n   return true;",
                "   PnlMoveBy(g_PnlOpen, ndx, ndy);\n   PnlMoveBy(g_PnlOpen, 0, 0);\n   return true;")
    cases.append(("a second mover of the card is caught", bool(check_drag())))
    reset()

    # 29. the frame window goes back to a HARD rate (it can no longer adapt to
    #     the machine - the P-PERF-04 defect the coalescer replaced)
    with_source(PANELS, "   if(s_PnlMoveTick != 0 && now - s_PnlMoveTick < (uint)s_PnlMoveFrameMs) return;",
                "   if(s_PnlMoveTick != 0 && now - s_PnlMoveTick < 30) return;")
    cases.append(("a drag frame rate that cannot adapt is caught",
                  bool(check_drag())))
    reset()

    # 30. the drag's frame stops counting for the tick throttle (the tick would
    #     immediately repaint the same picture - double cost per batch)
    with_source(UTILS, "    g_lastChartRedrawTime = GetTickCount();\n}",
                "    // seed: the tick throttle is not told\n}")
    cases.append(("a drag frame outside the tick throttle is caught",
                  bool(check_drag())))
    reset()

    # 31. the polled shadow leaves the pump - the drag is back on one delivery
    #     channel, where a press without a mouse-move edge is dead (P-BK-03)
    # PANELDRAG-OFF: the same seed, re-anchored on the RETIRED call - a restored
    # poll pays a KEYSTATE probe per tick for a gesture that no longer exists
    with_source(PANELS, "   // PnlDragPoll();  // P-UI-75a",
                "   PnlDragPoll();  // P-UI-75a")
    cases.append(("a half-restored drag poll is caught",
                  bool(check_drag() or check_paneldrag_off())))
    reset()

    # 32. the poll pays for a hit test before it can bail out - an idle tick
    #     (every tick, plus the 250 ms timer) stops being one int compare
    with_source(PANELS, "   if(g_PnlDragItem >= 0 || g_PalMixDrag > 0) return;   // another panel gesture owns it",
                "   PnlPointOnControl(g_LastUIX, g_LastUIY);   // seed: a hit test on the idle path\n"
                "   if(g_PnlDragItem >= 0 || g_PalMixDrag > 0) return;   // another panel gesture owns it")
    cases.append(("a poll that is not free when idle is caught", bool(check_drag())))
    reset()

    # 33. P-UI-88/P-UI-89: the grab refuses every claim outright again - the
    #     switch / colour-cell / strip / band / cap faces go back to being the part
    #     of the card that cannot be dragged («هنوز درگ نمیشه پنل تنظیمات»). The
    #     dead zone (P-UI-80) is what replaced P-UI-76's hard rule: a tap ends
    #     `moved=0`, so the control's own action still lands either way.
    with_source(PANELS, '   if(ownGesture)', '   if(claim != "")')
    cases.append(("a grab that refuses a soft claim is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 33b. P-UI-88: the claim owner answers with a bool again - the refusal line
    #      loses the claimant's name and the ledger is anonymous once more
    with_source(PANELS, "   if(PnlQuickSwatchHit(mx,my,it,r,c)) return \"strip\";   // P-UI-87: preview + quick strip",
                "   if(PnlQuickSwatchHit(mx,my,it,r,c)) return \"\";   // seed: an anonymous claim")
    cases.append(("a claim owner that cannot name the claimant is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 33c. P-UI-88: the wrapper stops delegating - two control lists, free to drift
    with_source(PANELS, '   return (PnlPressClaimCode(mx,my) != "");',
                "   return false;   // seed: a second list would live here")
    cases.append(("a claim predicate with its own list is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 33d. P-UI-88: an affordance acts without naming itself - a press that DID
    #      something leaves no line, which is how "nothing works" was read
    with_source(PANELS, 'UIPressAct("sw")', "UIPressAct()")
    cases.append(("an act site that does not name its control is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 33e. P-UI-88: the foreign-claim refusal goes silent again - a stuck ring /
    #      box claim reads as "the whole panel is dead" with no line to say so
    with_source(PANELS, '      _LOG_GATE_W Print("[UI] panel press refused (foreign claim owner=", (int)g_DragOwner, ")");',
                "      // seed: the foreign-claim refusal is silent")
    cases.append(("a silent foreign-claim refusal is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 34. the control predicate loses one family (the quick swatches)
    with_source(PANELS, "         for(int q=0;q<PNL_QSW_N;q++)",
                "         for(int q=0;q<0;q++)")
    cases.append(("a lost release-channel control family is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 35. the slider press applies nothing again (the knob's wider grab zone arms
    #     a drag a motionless click never fulfils)
    with_source(PANELS, "         PnlValueFromX(it,r,mx,v);\n",
                "")
    cases.append(("a slider press that applies nothing is caught",
                  bool(check_press(read(PANELS)))))
    reset()

    # 36. P-UI-77: the move block ends a poll-armed drag on the bare event bit
    #     again - the first disagreeing event murders a working drag (fixed card)
    with_source(PANELS, "      if(!leftDown && (!s_PnlMoveByPoll || UILeftButtonUp()))",
                "      if(!leftDown)")
    cases.append(("a poll-armed drag murdered by its own event channel is caught",
                  bool(check_drag())))
    reset()

    # 37. P-UI-77: the poll arms as the event channel - no drag is ever
    #     poll-owned, so the agreement rule never engages and the card is
    #     fixed again on a terminal whose event bit lies
    with_source(PANELS, "   if(!PnlTryGrabMove(g_LastUIX, g_LastUIY,true)) return;",
                "   if(!PnlTryGrabMove(g_LastUIX, g_LastUIY,false)) return;")
    cases.append(("a poll that never owns its drag's release is caught",
                  bool(check_drag())))
    reset()

    # 38. P-UI-78: the ledger moves into the per-move batch path - one line per
    #     drag tick instead of per gesture (the diagnosis becomes the lag)
    with_source(PANELS, "   DragFrameRedraw();    // the drag's own frame, once per applied batch",
                "   DragFrameRedraw();    // the drag's own frame, once per applied batch\n"
                "   Print(\"[UI] seed: batch\");")
    cases.append(("a ledger that prints at drag rate is caught",
                  bool(check_drag())))
    reset()

    # 39. P-UI-78: the poll is back to finishing on one up-reading - a KEYSTATE
    #     flicker murders the live drag mid-press again
    with_source(PANELS, "         if(!s_PnlPollUpArmed) { s_PnlPollUpArmed = true; return; }",
                "         // seed: single-reading finish")
    cases.append(("a poll finish without the rumour filter is caught",
                  bool(check_drag())))
    reset()

    # 40. P-UI-78: one refusal goes silent - that press shape reads as dead
    #     with no line saying why
    with_source(PANELS, '      PnlGrabRefused("C:"+claim,byPoll,mx,my,rpx,rpy,rpw,rph);',
                '      PnlGrabRefused("C",byPoll,mx,my,rpx,rpy,rpw,rph);')
    cases.append(("a silent grab refusal is caught", bool(check_drag())))
    reset()

    # 41. P-UI-79: the paint-anchored fallback is gone - a stale rect refuses
    #     presses sitting on the drawn card again
    with_source(PANELS, "      if(!PnlSkinHit(g_PnlOpen,mx,my)) { PnlGrabRefused(\"H\",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }",
                "      { PnlGrabRefused(\"H\",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }")
    cases.append(("a grab without its paint fallback is caught",
                  bool(check_drag())))
    reset()

    # 42. P-UI-79: the refusal loses the remembered rect - an (H) line cannot
    #     be judged anymore
    with_source(PANELS, "\" at \", mx, \",\", my, \" rect=\", px, \",\", py, \",\", pw, \",\", ph);",
                "\" at \", mx, \",\", my);")
    cases.append(("a refusal without its rect is caught", bool(check_drag())))
    reset()

    # 43. P-UI-78 ledger: the finalizer's missed-release end goes silent again -
    #     an arm/arm pair reads as a double-grab instead of tap, release, tap
    with_source(PANELS, "                        \" byPoll=\", (s_PnlMoveByPoll ? 1 : 0),\n"
                        "                        \" frames=\", s_PnlMoveFrames, \" worst=\", s_PnlMoveWorst,\n"
                        "                        \"ms via=finalizer\");",
                "      // seed: silent finalizer end")
    cases.append(("a silent finalizer drag-end is caught", bool(check_drag())))
    reset()

    # 44. P-UI-80: the dead zone collapses to zero - tremor moves, pins and
    #     suppresses again, like before the menu parity
    with_source(PANELS, "      MathAbs(mx - s_PnlMoveGrabX) <= PnlDragThreshPx() &&\n      MathAbs(my - s_PnlMoveGrabY) <= PnlDragThreshPx())",
                "      MathAbs(mx - s_PnlMoveGrabX) <= 0 &&\n      MathAbs(my - s_PnlMoveGrabY) <= 0)")
    cases.append(("a batch path without the dead zone is caught",
                  bool(check_drag())))
    reset()

    # 45. P-UI-80: the press chain pins and suppresses every release again -
    #     taps drift the card and swallow their own click
    with_source(PANELS, "         // poll already finished this way — now both entries speak one rule.\n         PnlDragFinish(s_PnlMoveMoved, s_PnlMoveMoved);",
                "         PnlDragFinish(true, true);   // seed: unconditional finish")
    cases.append(("an unconditional press-chain finish is caught",
                  bool(check_drag())))
    reset()

    # 46. P-UI-81: the press-edge reap is gone - a missed release bricks the
    #     whole panel again (the report: it moves, then nothing works)
    with_source(PANELS, "   if(pressStart && !s_PnlClickChannel) PnlReapStaleGestures(s_PnlMoveMoved);",
                "   // seed: no press-edge reap")
    cases.append(("a panel with no press-edge heal is caught", bool(check_heal())))
    reset()

    # 47. P-UI-81: the reap migrates onto the TICK path - a poll murders a live
    #     drag (the P-UI-73b class, one state further in)
    with_source(PANELS, "   if(!PnlTryGrabMove(g_LastUIX, g_LastUIY,true)) return;",
                "   PnlReapStaleGestures(true);\n"
                "   if(!PnlTryGrabMove(g_LastUIX, g_LastUIY,true)) return;")
    cases.append(("a tick-path reap is caught", bool(check_heal())))
    reset()

    # 48. P-UI-81: the reaper forgets one latch - that latch alone keeps the
    #     whole panel dead
    with_source(PANELS, "   if(g_PalMixDrag > 0)\n", "   if(false && g_PalMixDrag > 0)\n")
    cases.append(("a reaper that forgets a latch is caught", bool(check_heal())))
    reset()

    # 49. P-UI-82: the park migrates back to the release only - a hotkey-closed
    #     card reopens at the previous spot (the report's second half)
    with_source(PANELS, "   if(!s_PnlMoveMoved) PnlCommitMove(g_PnlMoveItem);\n", "")
    cases.append(("a drag that parks only on release is caught", bool(check_drag())))
    reset()

    # 50. P-UI-82: the grab stops rebuilding the list - a batch can move a stale
    #     shape and tear the card
    with_source(PANELS, "   PnlMoveListSync(g_PnlOpen, true);",
                "   // seed: no per-gesture rebuild")
    cases.append(("a grab that reuses a stale move list is caught", bool(check_drag())))
    reset()

    # 51. P-UI-83: the poll goes back to ending a live drag on the probe alone -
    #     on a terminal whose probe reads "free" while the button is held, every
    #     drag it did not arm dies on its second pass (253-500 ms per press)
    with_source(PANELS, "      if(UILeftButtonUp() && PnlPointerQuiet())",
                "      if(UILeftButtonUp())")
    cases.append(("a probe-only poll finish is caught", bool(check_drag())))
    reset()

    # 52. P-UI-83: the finalizer tears a gesture down on the probe alone again -
    #     the OBJECT_CLICK echo of the arming press executes the live drag
    with_source(PANELS, "   if(!UILeftButtonUp() || !PnlPointerQuiet()) return;",
                "   if(!UILeftButtonUp()) return;")
    cases.append(("a probe-only finalizer teardown is caught", bool(check_drag())))
    reset()

    # 53. P-UI-83: the batch reads its objects back (get-then-set) - half of every
    #     batch spent on a value the gesture cannot change (the menu never reads)
    with_source(PANELS,
                "   if(nx != s_PnlMoveOx)\n"
                "      ObjectSetInteger(0, s_PnlMoveNm[i], OBJPROP_XDISTANCE,\n"
                "                       s_PnlMoveX0[i] + (nx - s_PnlMoveOx));",
                "   if(nx != s_PnlMoveOx)\n"
                "      ObjectSetInteger(0, s_PnlMoveNm[i], OBJPROP_XDISTANCE,\n"
                "                       (int)ObjectGetInteger(0, s_PnlMoveNm[i], OBJPROP_XDISTANCE) + (nx - s_PnlMoveOx));")
    cases.append(("a batch that reads its objects back is caught", bool(check_drag())))
    reset()

    # 54. PANELDRAG-OFF: the retired site is DELETED instead of commented - the
    #     feature can never come back, which is the R-RETIRED rule (comment in
    #     place, never remove)
    with_source(PANELS, "      // if(!s_PnlClickChannel) PnlTryGrabMove(mx,my,false);\n",
                "      // seed: the retired site was deleted\n")
    cases.append(("a deleted (not commented) retired site is caught",
                  bool(check_press(read(PANELS)) or check_drag()
                       or check_paneldrag_off())))
    reset()

    # 55. P-UI-89: a second arm site - the tail refuses a press the early arm
    #     already owns, one bogus `M` refusal per press in the ledger
    with_source(PANELS,
                "      // The press landed on NO control of this card: the arm above is its whole",
                "      PnlTryGrabMove(mx,my,false);   // seed: the tail arms again\n"
                "      // The press landed on NO control of this card: the arm above is its whole")
    cases.append(("a chain that arms twice is caught",
                  bool(check_press(read(PANELS)) or check_drag())))
    reset()

    # 56. P-UI-89: a control press is measured by the MENU's dead zone - every
    #     toggle tap (1-3 px of hand travel, P-UI-76) creeps the card
    with_source(PANELS, "   return (s_PnlMoveOnCtrl ? PNL_DRAG_CTRL_PX : PNL_DRAG_THRESHOLD_PX);",
                "   return (PNL_DRAG_THRESHOLD_PX);")
    cases.append(("a dead zone that ignores the control-pixel bound is caught",
                  bool(check_drag())))
    reset()

    # 57. P-UI-89: a control press inherits the body's proof - the flag is set to a
    #     constant, so the longer bound is dead code
    with_source(PANELS, "   s_PnlMoveOnCtrl  = softClaim;   // P-UI-89: the proof this gesture owes the card",
                "   s_PnlMoveOnCtrl  = false;")
    cases.append(("a control press that keeps the body's proof is caught",
                  bool(check_drag())))
    reset()

    # 58. P-UI-89: the finish keeps the flag - the NEXT drag measures its dead zone
    #     against a press that is long over
    with_source(PANELS, "   s_PnlMoveOnCtrl = false;   // P-UI-89:",
                "   // seed: the finish keeps the flag")
    cases.append(("a finish that leaves the control-press flag set is caught",
                  bool(check_drag())))
    reset()

    # 59. PANELDRAG-OFF: the move branch is switched back ON while the arm stays
    #     retired - dead code becomes a live divert of every held press, and the
    #     two halves of the retirement disagree
    with_source(PANELS, "   if(false && g_PnlMoveItem >= 0)",
                "   if(g_PnlMoveItem >= 0)")
    cases.append(("a re-enabled move branch is caught",
                  bool(check_drag() or check_paneldrag_off())))
    reset()

    # 60. P-UI-91: the candle score becomes a GUESS - a third of the band that
    #     the placement never measured
    with_source(PANELS, "      int ov = (hasBand ? PnlIntervalOverlap(candY[c], ph, cdTop, cdBot) : 0);",
                "      int ov = (hasBand ? (cdBot - cdTop) / 3 : 0);   // seed: a guessed score")
    cases.append(("a guessed candle score is caught", bool(check_placement())))
    reset()

    # 61. P-UI-91: the band is measured on a HOT path (the move batch) - the
    #     always-on cost P-UI-90 removed comes back as a per-batch chart scan
    with_source(PANELS, "   PnlClampSpot(item, dx, dy, ndx, ndy);",
                "   int bt,bb; PnlCandleBandPx(bt,bb);   // seed: a per-batch band\n"
                "   PnlClampSpot(item, dx, dy, ndx, ndy);")
    cases.append(("a band measured off the open path is caught",
                  bool(check_placement())))
    reset()

    # 62. P-UI-91: the MENU rule goes soft - a spot that lands on the ring/orb can
    #     win the candle score (the card covers the menu the user needs to reach)
    with_source(PANELS, "      if(valid[c] && (pick < 0 || ov < pickOv)) { pick = c; pickOv = ov; }",
                "      if(pick < 0 || ov < pickOv) { pick = c; pickOv = ov; }   // seed: menu rule soft")
    cases.append(("a softened menu rule is caught", bool(check_placement())))
    reset()

    # 63. P-UI-91: a parked spot is honoured without the candle rule - an unclean
    #     park is permanent now that the drag is retired
    with_source(PANELS, "      if(!parkMenuHit && parkOv == 0) { px = manX; py = manY; return; }",
                "      if(!parkMenuHit) { px = manX; py = manY; return; }   // seed: park ignores candles")
    cases.append(("a park that ignores the candles is caught",
                  bool(check_placement())))
    reset()

    # 64. P-UI-91: the scan loses its window clamp - the band walks all history
    #     once per open
    with_source(PANELS, "   if(vis > 0 && bars > vis) bars = vis;",
                "   // seed: the scan is not clamped to the window")
    cases.append(("an unclamped band scan is caught", bool(check_placement())))
    reset()

    # 65. P-BK-18: the blanket 30 ms gate comes back above the anchor compare
    #     (the border steps at 33 fps again while the fill tracks the hand)
    with_source(BASEKNOT, "   BaseKnotReassertLock(false);   // P-BK-14: the drag owns the view until release (drag took ctxToo=false)",
                "   if(GetTickCount() - s_bkDragMs < 30) return;   // seed: blanket gate\n"
                "   BaseKnotReassertLock(false);   // P-BK-14: the drag owns the view until release (drag took ctxToo=false)")
    cases.append(("a blanket 30 ms gate on the child move step is caught",
                  bool(check_bk_drag())))
    reset()

    # 66. P-BK-18: the cursor fallback loses its budget (a box-write storm per
    #     mouse move where the terminal repaints nothing of its own)
    with_source(BASEKNOT, "      if(cms - s_bkDragMs < BK_DRAG_CURSOR_MS) return;",
                "      // seed: the fallback writes the BOX unbudgeted")
    cases.append(("an unbudgeted cursor fallback is caught",
                  bool(check_bk_drag())))
    reset()

    # 67. P-BK-18/BKEDGE-OFF: THE SETTLE HEAL COMES BACK TO LIFE. It healed a COPY
    #     of the box; the border IS the box now (P-BK-74), so a live heal can only
    #     Sync a box that is already right - and it writes into whatever gesture is
    #     running (P-BK-15). This is the half-restore the retirement must catch.
    with_source(BASEKNOT,
                "      // BKEDGE-OFF: if(bkHandOff && !BaseKnotBorderSettled(pfx, t1, t2, top))",
                "      if(bkHandOff && !BaseKnotBorderSettled(pfx, t1, t2, top))")
    cases.append(("a settle heal uncommented beside the retired border is caught",
                  bool(check_bkedge_off())))
    reset()

    # 67b. BKEDGE-OFF: a retired EDGE CALL SITE comes back to life - a drawn copy of
    #      the border on top of the object the terminal already paints
    with_source(BASEKNOT, "   // BaseKnotDrawEdges(pfx, t1, p1, t2, p2,",
                "   BaseKnotDrawEdges(pfx, t1, p1, t2, p2,")
    cases.append(("a live edge call site is caught", bool(check_bkedge_off())))
    reset()

    # 67c. BKEDGE-OFF: the existence sweep probes an edge again (a terminal call
    #      whose only possible answer is "no" - P-PERF-42)
    with_source(BASEKNOT,
                "   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_T) >= 0)            m |= BK_CH_EDGE_T;",
                "   if(ObjectFind(0, pfx + BK_EDGE_T) >= 0)            m |= BK_CH_EDGE_T;")
    cases.append(("an edge probe back in the gesture sweep is caught", bool(check_bkedge_off())))
    reset()

    # 67d. BKEDGE-OFF: the drag's child pass carries an edge again
    with_source(BASEKNOT,
                "   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_T) != 0) BaseKnotMoveOne(pfx + BK_EDGE_T, t1, top, t2, top);",
                "   if((s_bkChildMask & BK_CH_EDGE_T) != 0) BaseKnotMoveOne(pfx + BK_EDGE_T, t1, top, t2, top);")
    cases.append(("a drag step that carries a retired edge is caught", bool(check_bkedge_off())))
    reset()

    # 67e. BKEDGE-OFF: the dormant engine is DELETED instead of commented - the
    #      uncomment that restores the family finds half of it gone (a rewrite)
    with_source(BASEKNOT, "void BaseKnotDrawEdges(const string tag, datetime t1, const double p1,",
                "void BaseKnotDrawEdgesX(const string tag, datetime t1, const double p1,")
    cases.append(("a retirement that deleted its own engine is caught", bool(check_bkedge_off())))
    reset()

    # 67f. BKEDGE-OFF: the sizing preview deletes and redraws per frame again
    with_source(BASEKNOT, "   BaseKnotDrawPreviewRect(pv, t, p, t, p,",
                "   ObjectDelete(0, pv);\n   BaseKnotDrawPreviewRect(pv, t, p, t, p,")
    cases.append(("a preview that recreates its object per frame is caught",
                  bool(check_bkedge_off())))
    reset()

    # 67g. BKEDGE-OFF: the preview shows a fill the committed box does not have
    with_source(BASEKNOT, "   ObjectSetInteger(0, tag, OBJPROP_FILL, false);",
                "   ObjectSetInteger(0, tag, OBJPROP_FILL, true);")
    cases.append(("a preview that lies about the committed look is caught",
                  bool(check_bkedge_off())))
    reset()

    # 67h. P-BK-74/bkbox-ink: THE HOLLOW BOX IS PAINTED IN THE FILL INK AGAIN - the
    #      invisible cover the user's screenshot caught (the outline then only shows
    #      because the retired trend lines drew it)
    with_source(BASEKNOT, "      ObjectSetInteger(0, box, OBJPROP_COLOR, GetBoxBorderRenderColor());",
                "      ObjectSetInteger(0, box, OBJPROP_COLOR, GetBoxFillRenderColor());")
    cases.append(("a box painted in something other than the border ink is caught",
                  bool(check_bkbox_ink())))
    reset()

    # 67i. P-BK-74/bkbox-ink: the default box comes up FILLED (the user asked for
    #      no fill, and MT4's own rectangle ships fill=false)
    with_source(BASEKNOT, "      ObjectSetInteger(0, box, OBJPROP_FILL, false);",
                "      ObjectSetInteger(0, box, OBJPROP_FILL, true);")
    cases.append(("a default box that comes up filled is caught", bool(check_bkbox_ink())))
    reset()

    # 67j. P-BK-74/bkbox-ink: the drift reader stops asking the ink the writer uses
    #      (a box an older build left invisible then reads as healed forever)
    with_source(BASEKNOT,
                "   return ((color)ObjectGetInteger(0, box, OBJPROP_COLOR) == GetBoxBorderRenderColor());",
                "   return (true);")
    cases.append(("a drift reader that cannot see the ink is caught", bool(check_bkbox_ink())))
    reset()

    # 67k. P-BK-15: the pump stops skipping the box the user is dragging (any Sync
    #      mid-gesture snaps it back to the drag start)
    with_source(BASEKNOT,
                '      if(s_bkDragId != "" && g_bkBoxes[i].id == s_bkDragId) continue;', "")
    cases.append(("a pump that writes into a live drag is caught", bool(check_bk_drag())))
    reset()

    # 68. BKCURSOR-OFF: the retired fallback is brought back to life (a second
    #     writer of the box beside the terminal's own drag)
    with_source(BASEKNOT, "   else if(false && !s_bkNativeClaim &&",
                "   else if(!s_bkNativeClaim &&")
    cases.append(("a revived cursor fallback is caught",
                  bool(check_bkcursor_off())))
    reset()

    # 77. P-BK-58: the note's home loses a rung somewhere in the chain
    with_source(PANELS, 'else if(sec==4)  { kind=2; label="INFO"; opts="Auto|Show|Corner"; minV=0; maxV=2; }',
                'else if(sec==4)  { kind=2; label="INFO"; opts="Auto|Show"; minV=0; maxV=1; }')
    cases.append(("a card row that stopped offering the corner is caught",
                  bool(check_bk_info_rungs())))
    reset()

    with_source(PANELS, 'else if(sec==4) { g_bkShowInfo=ClampInt((int)MathRound(v),0,2);',
                'else if(sec==4) { g_bkShowInfo=ClampInt((int)MathRound(v),0,1);')
    cases.append(("a Setup tab that eats the corner rung is caught",
                  bool(check_bk_info_rungs())))
    reset()

    with_source(PANELS, 'else if(row==2)  { g_bkShowInfo=ClampInt((int)MathRound(v),0,2);',
                'else if(row==2)  { g_bkShowInfo=ClampInt((int)MathRound(v),0,1);')
    cases.append(("a MINI strip that eats the corner rung is caught",
                  bool(check_bk_info_rungs())))
    reset()

    with_source(SETTINGS,
                "g_bkShowInfo = ClampSettingInt(inpBKShowInfo, 0, 2);",
                "g_bkShowInfo = inpBKShowInfo;")
    cases.append(("a settings layer that stopped clamping on init is caught",
                  bool(check_bk_info_rungs())))
    reset()

    with_source(SETTINGS,
                'g_bkShowInfo = ClampSettingInt((int)GlobalVariableGet(p + "BXI"), 0, 2);',
                'g_bkShowInfo = ClampSettingInt((int)GlobalVariableGet(p + "BXI"), 0, 1);')
    cases.append(("a restore that clamps an old chart to two rungs is caught",
                  bool(check_bk_info_rungs())))
    reset()

    with_source(BASEKNOT, "#define BK_NOTE_CHART     2", "#define BK_NOTE_CHART     3")
    cases.append(("a rung the row cannot reach is caught",
                  bool(check_bk_info_rungs())))
    reset()

    with_source(PANELS, 'else if(row==2)  { kind=2; label="INFO"; opts="Auto|Show|Corner"; minV=0; maxV=2; }',
                'else if(row==2)  { kind=2; label="INFO"; opts="Auto|Corner"; minV=0; maxV=2; }')
    cases.append(("two captions on one surface for three rungs are caught",
                  bool(check_bk_info_rungs())))
    reset()

    # 69. P-BK-19a: the anchor-driven branch stops claiming the gesture
    with_source(BASEKNOT, "      s_bkNativeClaim = true;\n      s_bkFolT1 = t1; s_bkFolT2 = t2; s_bkFolP1 = p1; s_bkFolP2 = p2;",
                "      s_bkFolT1 = t1; s_bkFolT2 = t2; s_bkFolP1 = p1; s_bkFolP2 = p2;")
    cases.append(("an anchor move that does not claim the gesture is caught",
                  bool(check_bk_drag())))
    reset()

    # 70. P-BK-19b/P-BK-72: the press-time role measurement is DELETED - the release's
    #     size heal then obeys a role nobody measured (and the dormant fallback loses
    #     the call its restore needs).
    with_source(BASEKNOT,
                "                     s_bkGrabSel = BaseKnotGrabRole(shbox, s_bkDragX0, s_bkDragY0);",
                "                     // seed: the role measurement was deleted")
    cases.append(("a deleted role measurement is caught",
                  bool(check_bk_drag())))
    reset()

    # 70c. P-BK-72: the ROLE gate drops - a native resize (the size the user asked for)
    #      is then healed back to the press-time size on every release.
    with_source(BASEKNOT,
                "if(bkGripWas == 0 && s_bkGrabSel == BK_GRAB_ALL) BaseKnotBodySizeHeal(",
                "if(bkGripWas == 0) BaseKnotBodySizeHeal(")
    cases.append(("a heal that can undo a native resize is caught", bool(check_bk_drag())))
    reset()

    # 70b. BKCURSOR-OFF: the dormant engine loses its body entirely
    with_source(BASEKNOT, "int BaseKnotGrabRole(const string box, const int mx, const int my)",
                "int BaseKnotGrabRoleRetiredUnused(const string box, const int mx, const int my)")
    cases.append(("a deleted dormant grab-role engine is caught",
                  bool(check_bkcursor_off())))
    reset()

    # 71. P-BK-19b: the DORMANT body loses the role split (a restore would then
    #     move the opposite side of an edge drag again)
    with_source(BASEKNOT, "      if(s_bkGrabSel == BK_GRAB_ALL)   // body grab = MOVE",
                "      if(true)   // seed: every grab translates both anchors")
    cases.append(("a dormant fallback body that lost its role split is caught",
                  bool(check_bkcursor_off())))
    reset()

    # 73. P-PERF-42: the per-step child move probes existence again
    with_source(BASEKNOT, "   ObjectMove(0, nm, 0, tA, pA);",
                "   if(ObjectFind(0, nm) < 0) return;\n   ObjectMove(0, nm, 0, tA, pA);")
    cases.append(("a per-child ObjectFind in the drag step is caught",
                  bool(check_bk_drag())))
    reset()

    # 74. P-PERF-42: the child mask is never built (the pass moves nothing)
    with_source(BASEKNOT, "      s_bkChildMask = BaseKnotChildMaskBuild(pfx);",
                "      s_bkChildMask = 0;   // seed: no probe")
    cases.append(("a child pass that never builds its mask is caught",
                  bool(check_bk_drag())))
    reset()

    # 75. P-PERF-43: the drag stops measuring itself per gesture
    with_source(BASEKNOT,
                "          s_bkChildMaskId = \"\"; s_bkPerfMoveWorst = 0; s_bkPerfPaintWorst = 0; s_bkPerfPasses = 0;",
                "          s_bkChildMaskId = \"\";")
    cases.append(("a drag that never resets its timing is caught",
                  bool(check_bk_drag())))
    reset()

    # 72. P-BK-19a: the terminal's OBJECT_DRAG no longer claims the gesture.
    #     The anchor is TEXTUAL now, not the nth occurrence: P-BK-61 added a THIRD
    #     claim site (the handle drag, which claims a gesture the terminal owns just
    #     as much), and an index would silently point at whichever claim happened to
    #     sit second in the file - the mutant would then patch the wrong branch and
    #     the fault would go undetected (the seed IS the check's only proof).
    #     (re-anchored for P-BK-65, which landed its own two stores between the
    #     claim and the follow comment: the anchor is the CLAIM LINE plus the line
    #     that follows it NOW, so the mutant still patches the box branch itself)
    with_source(BASEKNOT,
                "s_bkNativeClaim = true;\n           // P-BK-65: AND IT JUST SAID WHICH OBJECT: the BOX, not a chip.",
                "/* seed: the terminal's own drag does not claim the gesture */\n"
                "           // P-BK-65: AND IT JUST SAID WHICH OBJECT: the BOX, not a chip.")
    cases.append(("an OBJECT_DRAG that does not claim the gesture is caught",
                  bool(check_bk_drag())))
    reset()

    # 77. P-BK-61: the held-modifier gate is the whole difference between the magnet
    #     the user asked for and the one BKMAGNET2-OFF removed - drop it and the
    #     handle drag snaps on every step.
    with_source(BASEKNOT,
                "   if(modifier && (side & (BK_GS_T | BK_GS_B)) != 0) gp = BaseKnotGripSnapPrice(gt, gp);",
                "   gp = BaseKnotGripSnapPrice(gt, gp);")
    cases.append(("an UNGATED handle magnet is caught", bool(check_bkmagnet())))
    reset()

    # 77b. P-BK-66: the modifier must NOT be the terminal's own copy key. Ctrl+drag
    #      duplicates the dragged object («این باکس رو کپی میکنه»), so a probe back on
    #      CONTROL is a magnet that can never fire - and the mutant that renames the
    #      probe is the same fault told the other way (the call site asks by ROLE).
    with_source(UTILS, "long v = TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT);",
                "long v = TerminalInfoInteger(TERMINAL_KEYSTATE_CONTROL);")
    cases.append(("a magnet modifier back on Ctrl (the copy key) is caught",
                  bool(check_bkmagnet())))
    reset()

    with_source(UTILS, "bool UIMagnetModifierDown()", "bool UICtrlKeyDown()")
    cases.append(("a magnet modifier probe renamed away from its role is caught",
                  bool(check_bkmagnet())))
    reset()

    with_source(BASEKNOT, "bool modifier = UIMagnetModifierDown();",
                "bool modifier = UICtrlKeyDown();")
    cases.append(("a handle drag that stops asking for the modifier by role is caught",
                  bool(check_bkmagnet())))
    reset()

    # 78. P-BK-61: the magnet may never ride the box' own live follow (that is what
    #     BKMAGNET2-OFF retired).
    with_source(BASEKNOT, "      BaseKnotMoveChildren(id, t1, p1, t2, p2);",
                "      BaseKnotGripSnapPrice(0, 0.0);\n      BaseKnotMoveChildren(id, t1, p1, t2, p2);")
    cases.append(("a magnet inside the box' live follow is caught", bool(check_bkmagnet())))
    reset()

    # 79. P-BK-61: without the published side the keeper rewrites the chip the hand
    #     is holding, and MT4 cancels the drag it is running (P-BK-15).
    with_source(BASEKNOT, "   s_bkGripLive = side;",
                "   /* seed: the hand's own side is not published */")
    cases.append(("a handle drag that hides its side is caught", bool(check_bk_drag())))
    reset()

    # 80. P-BK-61b: the body drag must never resize the box - resize has ONE home
    #     (the native corner/edge markers now), and the FILL only carries it.
    with_source(BASEKNOT, "if(bkGripWas == 0 && s_bkGrabSel == BK_GRAB_ALL) BaseKnotBodySizeHeal(s_bkDragId);", "")
    cases.append(("a body drag that may resize the box is caught", bool(check_bk_drag())))
    reset()

    # 76. BKMAGNET2-OFF: the adjust magnet is retired - each half of the
    # retirement has its own mutant (a revived magnet AND a half-retirement).
    with_source(BASEKNOT, "return price;   // BKMAGNET-OFF", "// seed: draw-time snap is back")
    cases.append(("a revived DRAW-time magnet (the retired behaviour) is caught",
                  bool(check_bkmagnet())))
    reset()

    with_source(BASEKNOT, "// BaseKnotMagnetSettle(s_bkDragId);", "BaseKnotMagnetSettle(s_bkDragId);")
    cases.append(("a revived ADJUST magnet on the release is caught",
                  bool(check_bkmagnet())))
    reset()

    with_source(BASEKNOT, "// void BaseKnotMagnetSettle(const string bid)", "void BaseKnotMagnetSettle(const string bid)")
    cases.append(("a live magnet reader behind the retirement is caught",
                  bool(check_bkmagnet())))
    reset()

    with_source(PANELS, 'PnlSpecAdd(8, PNL_K_LEGACY, 1, 1, "droplet");',
                'PnlSpecAdd(8, PNL_K_LEGACY, 1, 1, "droplet");\n      PnlSpecAdd(8, PNL_K_LEGACY, 2, 1, "magnet");')
    cases.append(("a magnet row rendered while its engine is retired is caught",
                  bool(check_bkmagnet())))
    reset()

    with_source(BASEKNOT, "                 // BaseKnotMagnetSettle(s_bkDragId);\n", "")
    cases.append(("a retirement call deleted instead of commented is caught",
                  bool(check_bkmagnet())))
    reset()

    # 81. P-BK-62: the reconcile stops asking the box tool whether it owns the view
    #     - an IDLE drag or a handle resize then has its lock handed back mid-gesture.
    with_source(PANELS, "   if(BaseKnotViewOwned()) return true;\n", "")
    cases.append(("a watchdog that restores the view under a box drag is caught",
                  bool(check_bk_drag())))
    reset()

    # 82. P-BK-62: an OWNED drag lock is taken once and never re-forced (the
    #     P-BK-14 rule) - one third-writer flip and the rest of the gesture pans.
    with_source(BASEKNOT, "      BaseKnotReassertLock(false);   // P-BK-62: owned — re-force, never re-capture\n",
                "")
    cases.append(("a drag lock that is never re-forced is caught",
                  bool(check_bk_drag())))
    reset()

    # 83. P-BK-63: the outside-click drop loses its UI gate - a click on the Base
    #     Box strip would deselect the very box the card is editing.
    with_source(BASEKNOT, "   if(UIPointerOverSurface(mx, my)) return false;               // P-UI-92: the UI is over the box\n",
                "")
    cases.append(("a drop that lets go of the box a card is editing is caught",
                  bool(check_bk_drag())))
    reset()

    # 84. P-BK-63: the drop stops proving the click is OUTSIDE - its own press on
    #     the border would let go of the selection it just made.
    with_source(BASEKNOT, "      if(BaseKnotBoxAtPx(mx, my) != \"\") return false;   // ...or on its drawn border (P-BK-24)\n",
                "")
    cases.append(("a drop that fires on the box' own border is caught",
                  bool(check_bk_drag())))
    reset()

    # 85. P-BK-63: the drop asks the NOTE's question (the newest box when nothing is
    #     selected) instead of the exact SELECTED one.
    with_source(BASEKNOT, "   string sel = BaseKnotSelectedBoxId();",
                "   string sel = BaseKnotSelectedId();")
    cases.append(("a drop aimed at a box the user never selected is caught",
                  bool(check_bk_drag())))
    reset()

    # 86. P-BK-63: the drop leaves the handles on screen - the marks outlive the
    #     selection by up to the pump's half second.
    with_source(BASEKNOT, "   BaseKnotSelectionMarkersWipe(sel);\n", "")
    cases.append(("a dropped box that keeps its handles is caught",
                  bool(check_bk_drag())))
    reset()

    # 87. BKGRIP-OFF (P-BK-71): a retired chip row is uncommented - the family comes back
    #     without a keeper, so a selectable square sits on a native box that needs none.
    with_source(BASEKNOT, "   // BKGRIP-OFF: if(i == 0) return (BK_GS_T | BK_GS_L);",
                "   if(i == 0) return (BK_GS_T | BK_GS_L);")
    cases.append(("a revived chip plan is caught", bool(check_bk_drag())))
    reset()

    # 88. BKGRIP-OFF (P-BK-71): the count and the plan part ways again (a stale
    #     BK_GRIP_COUNT walks chips no keeper creates).
    with_source(BASEKNOT, "#define BK_GRIP_COUNT 0", "#define BK_GRIP_COUNT 2")
    cases.append(("a count that disagrees with the retired plan is caught",
                  bool(check_bk_drag())))
    reset()

    # 89. P-BK-71: a READER stops walking the ONE table (the deselect wipe spells its own
    #     tail again), so the two sweeps can drift apart.
    with_source(BASEKNOT, "      string tail = BaseKnotRetiredPointName(i);",
                '      string tail = "GT";')
    cases.append(("a sweep that spells its own tail list is caught",
                  bool(check_bk_drag())))
    reset()

    # 90. P-BK-71: the one-time sweep of a chart the older builds wrote is gone -
    #     selectable squares stay on it, dragging nothing.
    with_source(BASEKNOT, "         string mtail = BaseKnotRetiredPointName(m);",
                '         string mtail = "GT";')
    cases.append(("a chart keeping the retired points is caught",
                  bool(check_bk_drag())))
    reset()

    # 90b. BKTREND-OFF (P-BK-71): the carrier goes back to the retired trendline (the mark
    #      with no fill, no native body drag, and children that ride nothing).
    with_source(BASEKNOT, "   if(!ObjectCreate(0, box, OBJ_RECTANGLE, 0, g_bkT1, g_bkP1, tc, p2)) return;",
                "   if(!ObjectCreate(0, box, OBJ_TREND, 0, g_bkT1, g_bkP1, tc, p2)) return;")
    cases.append(("a mark back on the retired trendline is caught",
                  bool(check_bk_drag())))
    reset()

    # 90c. P-BK-71: the retired keeper loses its refusal - a partial restore then walks a
    #      plan whose rows are still commented out.
    with_source(BASEKNOT, "   if(BK_GRIP_COUNT <= 0) return false;", "")
    cases.append(("a retired keeper that can still run is caught",
                  bool(check_bk_drag())))
    reset()

    # 90d. BKGRIP-OFF (P-BK-71): a retired CALL SITE comes back to life while the plan says
    #      there is no chip - the half-restore that draws a square no keeper knows about.
    with_source(BASEKNOT,
                "   // BKGRIP-OFF: if(BaseKnotGripsFollow(id, t1, top, t2, bot, !g_bkBoxes[k].locked,",
                "   if(BaseKnotGripsFollow(id, t1, top, t2, bot, !g_bkBoxes[k].locked,")
    cases.append(("a chip call site that comes back to life is caught",
                  bool(check_bk_drag())))
    reset()

    # 90e. P-BK-71: the trendline era's tails drop out of the ONE table - a chart the
    #      committed trendline build wrote keeps its P1/P2 squares.
    with_source(BASEKNOT, '"G1", "G2", "DOT", "P1", "P2"};',
                '"G1", "G2", "DOT", "", ""};')
    cases.append(("a table that forgets the trendline tails is caught",
                  bool(check_bk_drag())))
    reset()

    # 91. P-BK-64: the magnet's reach stops being a pixel proximity.
    with_source(BASEKNOT, "   if(gatePx > BK_MAGNET_MAX_PX) gatePx = BK_MAGNET_MAX_PX;\n", "")
    cases.append(("a magnet with no pixel ceiling is caught", bool(check_bkmagnet())))
    reset()

    # 92. P-BK-64: the magnet goes back to the candle high/low alone.
    with_source(BASEKNOT, "   cand[3] = iClose(_Symbol, 0, shift);\n", "")
    cases.append(("a magnet that ignores the body prices is caught",
                  bool(check_bkmagnet())))
    reset()

    # 93. P-BK-65: the release reads the keeper's skip again as the gesture's KIND -
    #     the reported springback, in one line.
    with_source(BASEKNOT, "          int bkGripWas = s_bkGripGesture;",
                "          int bkGripWas = s_bkGripLive;")
    cases.append(("a resize that can be executed as a body drag is caught",
                  bool(check_bk_drag())))
    reset()

    # 94. P-BK-65: the press edge re-labels a live resize again.
    with_source(BASEKNOT,
                "          if(!bkGripHeld)\n          {\n             s_bkDragId = \"\"; s_bkDragMoved = false;",
                "          if(true)\n          {\n             s_bkDragId = \"\"; s_bkDragMoved = false;")
    cases.append(("a press edge that re-labels a live resize is caught",
                  bool(check_bk_drag())))
    reset()

    # 95. P-BK-65: the heal loses the "the terminal dragged the BOX" ground truth.
    with_source(BASEKNOT, "   if(!s_bkBoxNamed) return false;\n", "")
    cases.append(("a heal that can undo a handle resize is caught",
                  bool(check_bk_drag())))
    reset()

    # 96. P-BK-65: the kind latch is never set, so nothing knows it was a resize.
    with_source(BASEKNOT, "   s_bkGripGesture = side;\n", "")
    cases.append(("a resize whose kind is never latched is caught",
                  bool(check_bk_drag())))
    reset()

    # 97. P-BK-65: teardown stops clearing the gesture, so it outlives the instance.
    with_source(BASEKNOT, "   BaseKnotGestureClear();   // P-BK-65: no gesture state outlives the instance either\n",
                "")
    cases.append(("a gesture answer that outlives the instance is caught",
                  bool(check_bk_drag())))
    reset()


    reset()

    # 98. P-UI-98: the handle match forgets the custom-price gate.
    with_source(EVENTS, "    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return false;\n", "")
    cases.append(("a computed ladder's step-1 becomes draggable - caught",
                  bool(check_step1())))
    reset()

    # 99. P-UI-98f: the coincident boundary line carries the step-1 handle again
    # (the reported «اون قرمز خیلی نزدیک کاستوم پرایس»).
    with_source(PIPELINE, "        if(dist < stepNow * 0.5) continue;             // on the anchor: never a handle\n", "")
    cases.append(("a red handle on the custom price line is caught",
                  bool(check_step1())))
    reset()

    # 100. P-UI-98: the render writes the dragged line again (P-BK-15).
    with_source(PIPELINE, "        if(g_s1DragLive && lines[i].name == g_s1DragName)\n            continue;",
                "        if(false)\n            continue;")
    cases.append(("a write on the dragged handle is caught", bool(check_step1())))
    reset()

    # 101. P-UI-98: the face is owned BEFORE the guarded creator again.
    with_source(PIPELINE, "            bool isNew = CreateOrUpdateHLine(lines[i].name",
                "            Step1HandleOwnFace(lines[i].name, 0, 0, 0, \"\");\n            bool isNew = CreateOrUpdateHLine(lines[i].name")
    cases.append(("a face write that lands before creation is caught",
                  bool(check_step1())))
    reset()

    # 102. P-UI-98: the handle loses its z-order above the zone fills.
    with_source(PIPELINE,
                "    ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_CHART_LABEL);\n", "")
    cases.append(("a zone rect eating the handle's grab is caught",
                  bool(check_step1())))
    reset()

    # 103. P-UI-98: the geometry signature drops the override term.
    with_source(EVENTS, "                          DoubleToString(StepOverrideFactor(), 6) + \"|\" +\n", "")
    cases.append(("a drag that reads as the same picture is caught",
                  bool(check_step1())))
    reset()

    # 104. P-UI-98: the override stops multiplying the factory's sizes.
    with_source(EVENTS, "            for(int s1i = 0; s1i < def.stepSizeCount; s1i++)\n                def.stepSizes[s1i] *= s1Factor;", "")
    cases.append(("a dragged step that never reaches the ladder is caught",
                  bool(check_step1())))
    reset()

    # 105. P-UI-98: the settle keeps the grab's selection.
    with_source(EVENTS, "    if(name != \"\" && (bool)ObjectGetInteger(0, name, OBJPROP_SELECTED))\n        ObjectSetInteger(0, name, OBJPROP_SELECTED, false);", "")
    cases.append(("a selection that outlives the step-1 drag is caught",
                  bool(check_step1())))
    reset()

    # 106. P-UI-98d: the settle stops stamping the drag echo.
    with_source(EVENTS, "        g_s1JustDraggedMs = GetTickCount();\n", "")
    cases.append(("a drag's click echo setting the line is caught",
                  bool(check_step1())))
    reset()

    # 107. P-UI-98: the button-up latch forgets the step-1 gesture.
    with_source(EVENTS, "            if(g_s1DragLive) Step1DragSettle();", "")
    cases.append(("a step-1 release with no settle is caught", bool(check_step1())))
    reset()

    # 108. P-UI-98: the stale-drag heal forgets the step-1 flags.
    with_source(EVENTS, "    if(g_s1DragLive)\n    {\n        g_s1DragLive = false;\n", "")
    cases.append(("a lost release pinning the handle is caught", bool(check_step1())))
    reset()

    # 109. P-UI-98: one reset site disappears (the R key's).
    with_source(EVENTS, "            StepOverrideFactorReset();", "")
    cases.append(("an override that survives its own reset is caught",
                  bool(check_step1())))
    reset()

    # 110. P-UI-98d: a set line survives its own reset (armed wake gone).
    with_source(EVENTS, "            g_s1LinesArmed = true;", "            ;")
    cases.append(("a set handle that survives the R reset is caught",
                  bool(check_step1())))
    reset()

    # 111. P-UI-98d: the sweeper leaves the tick path.
    with_source(EVENTS, "    HandsetClickSweep();" + chr(10) + chr(10) + "    if(IsIndicatorHidden())", "")
    cases.append(("a click that never moves again never committing is caught",
                  bool(check_step1())))
    reset()

    # 112. P-UI-98d: the step-1 click owner disappears.
    with_source(EVENTS, "    if(id == CHARTEVENT_OBJECT_CLICK && Step1LineIsDragHandle(sparam))",
                "    if(false)")
    cases.append(("a handle without its click owner is caught", bool(check_step1())))
    reset()

    # 113. P-UI-98d: the custom marker leaves the LINES switch.
    # 112b. P-UI-98d v2: the red handle stops obeying the LINES switch - the
    # user's «وقتی لاین ها رو خاموش میکنم نشان ها هم نباشه».
    with_source(PIPELINE, "       IsIndicatorHidden() || !g_linesVisible)",
                "       IsIndicatorHidden())")
    cases.append(("a marker that ignores the lines mask is caught",
                  bool(check_step1())))
    reset()

    # 114. P-UI-99-OFF: the hold-to-arm beat comes back.
    with_source(EVENTS, "// P-UI-99-OFF (2026-09-21, user order):",
                "#define CP_HOLD_MS 500\n// P-UI-99-OFF (2026-09-21, user order):")
    cases.append(("the retired hold-to-arm beat returning is caught",
                  bool(check_step1())))
    reset()

    # 115. P-UI-99: the immediate claim loses its armed gate (a SET line
    # answers the pixel test again). P-UI-100: the anchor carries the claim's
    # current text, foreign-draw fence included.
    with_source(EVENTS, "                if(!s1Claimed && g_cpLineArmed && !TickDeadlinePending(s_cpForeignDrawUntil) &&\n                   ((pressEdge && (terminalGrab || pixelHit)) || (terminalGrab && atLineNow)))",
                "                if(!s1Claimed &&\n                   ((pressEdge && (terminalGrab || pixelHit)) || (terminalGrab && atLineNow)))")
    cases.append(("a set line grabbed by the pixel test is caught",
                  bool(check_step1())))
    reset()

    # 116. P-UI-99: the foreign-drag drain loses its arm.
    with_source(EVENTS, "                else if(pressEdge || terminalGrab)", "                else if(false)")
    cases.append(("a stale selection riding another object's drag is caught",
                  bool(check_step1())))
    reset()

    # 117. P-UI-99: the claim stops selecting the line (no face).
    with_source(EVENTS, "                        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);", "")
    cases.append(("a grab without its select face is caught", bool(check_step1())))
    reset()

    # 118. P-UI-98e: the press edge stops claiming the handle (the drag dies back
    # to a terminal grab that never engaged - the report this rule exists for).
    with_source(EVENTS, "                bool s1Claimed = (s1OnRow &&\n"
                        "                                  Step1HandleOwnClaim(s1Row, (int)lparam, (int)dparam));",
                "                bool s1Claimed = false;")
    cases.append(("a step-1 handle no press can claim is caught",
                  bool(check_step1())))
    reset()

    # 119. P-UI-98e: the carry writes the cursor's own price again.
    with_source(EVENTS, "                double wishPrice = g_s1OwnGrabPrice + (cursorPrice - g_s1OwnGrabCursorPrice);",
                "                double wishPrice = cursorPrice;")
    cases.append(("a step-1 carry that snaps the handle onto the cursor is caught",
                  bool(check_step1())))
    reset()

    # 120. P-UI-98e: the carry loses its travel fence (a click re-steps the ladder).
    with_source(EVENTS, "    if(MathAbs(y - g_s1OwnGrabY) >= CP_DRAG_SLOP && g_s1OwnGrabCursorPrice > 0.0)",
                "    if(g_s1OwnGrabCursorPrice > 0.0)")
    cases.append(("a step-1 click that re-steps the whole ladder is caught",
                  bool(check_step1())))
    reset()

    # 121. P-UI-98e/98f: the settle stops clearing the carry's own state.
    with_source(EVENTS, "    Step1GestureStateClear();\n    CustomPriceDragFrame(true);",
                "    CustomPriceDragFrame(true);")
    cases.append(("a finished step-1 gesture that keeps carrying the line is caught",
                  bool(check_step1())))
    reset()

    # 121b. P-UI-98e: a fresh placement stops waking the pair ARMED.
    with_source(EVENTS, "            HandsetPlacementArm();   // P-UI-98e: the fresh line and its handles wake draggable\n", "")
    cases.append(("a freshly placed line born inert is caught", bool(check_step1())))
    reset()

    # 122. P-UI-98e: the CLAIM loses its armed gate (a SET handle moves again).
    with_source(EVENTS, "    if(!g_s1LinesArmed) return false;      // a SET handle is inert: nothing may grab it\n",
                "")
    cases.append(("a SET handle that answers the press again is caught",
                  bool(check_step1())))
    reset()

    # 122b. P-UI-98e: the step-1 drag stops marking the ladder stale (only the
    # dragged line moves, the other levels stand still).
    with_source(EVENTS, "    g_redrawTHLevelsNeeded = true;\n    CustomPriceDragFrame(false);",
                "    CustomPriceDragFrame(false);")
    cases.append(("a step-1 drag the levels do not follow is caught",
                  bool(check_step1())))
    reset()

    # 122c. P-UI-98e: the step-1 drag loses its deferral exemption (the follow
    # becomes a scheduled frame - the lag the user reported).
    with_source(EVENTS, "    if(force_redraw && g_inChartEvent && !g_customPriceLineDragging && !g_s1DragLive)",
                "    if(force_redraw && g_inChartEvent && !g_customPriceLineDragging)")
    cases.append(("a step-1 drag whose frames are only scheduled is caught",
                  bool(check_step1())))
    reset()

    # 122d. P-UI-98e: the held pass stops borrowing the draggable flag (the
    # terminal's own drag re-arms and cuts the gesture off - «سریع قطع میشه»).
    with_source(EVENTS, "    Step1DragSelectable(handle, false);\n", "")
    cases.append(("a step-1 drag the terminal's own drag fights is caught",
                  bool(check_step1())))
    reset()

    # 122d-2. P-UI-98e: the finalizer stops ending a live gesture (the release that
    # emits no MOUSE_MOVE leaves everything stuck).
    with_source(EVENTS, "    if(g_s1DragLive)\n    {\n        bool wrote = (g_s1OwnLastWrite > 0.0);\n        Step1DragSettle();          // the release the mouse stream never delivered\n",
                "    if(false)\n    {\n        bool wrote = (g_s1OwnLastWrite > 0.0);\n        Step1DragSettle();\n")
    cases.append(("a lost release that leaves the handle stuck is caught",
                  bool(check_step1())))
    reset()

    # 122d-3. P-UI-98e: the release latch asks the travel after the settle.
    with_source(EVENTS, "            bool s1Wrote = (g_s1OwnLastWrite > 0.0);\n            if(g_s1DragLive) Step1DragSettle();",
                "            if(g_s1DragLive) Step1DragSettle();")
    cases.append(("a drag that SETs its own handle is caught",
                  bool(check_step1())))
    reset()

    # 122e. P-UI-98e: the settle stops returning the borrowed flag.
    with_source(EVENTS, "        Step1DragSelectable(name, g_s1LinesArmed &&\n"
                        "                                  g_thStartPointType == TH_START_POINT_CUSTOM_PRICE);\n",
                "")
    cases.append(("a handle left un-selectable after its own drag is caught",
                  bool(check_step1())))
    reset()

    # 122f. P-UI-98e: a press on the custom price line is claimed by the handle.
    with_source(EVENTS, "                bool onCustomLine = CustomPriceGrabAt((int)lparam, (int)dparam);",
                "                bool onCustomLine = false;")
    cases.append(("a line drag that re-steps the ladder instead is caught",
                  bool(check_step1())))
    reset()

    # 122g. P-UI-98e: another timeframe's stash is answerable again.
    with_source(EVENTS, "    if(g_s1MarkPeriod != Period()) return false;   // P-UI-98e: THIS tf's step 1 only\n",
                "")
    cases.append(("another timeframe's step 1 answering the press is caught",
                  bool(check_step1())))
    reset()

    # 123. P-UI-98e: the click owner loses its twin-event dedupe (one click reads
    # as a double, or a double as two singles).
    with_source(EVENTS, "    if(g_s1ClickHandledMs != 0 && now - g_s1ClickHandledMs < 60) return;   // the same click's twin event\n",
                "")
    cases.append(("a click whose twin event reads as a double is caught",
                  bool(check_step1())))
    reset()

    # 124. P-UI-98e: the still click never reaches the click owner (no MOUSE_MOVE
    # is emitted for a motionless release).
    with_source(EVENTS, "    if(id == CHARTEVENT_CLICK) Step1ClickFinalize();\n", "")
    cases.append(("a still click that never commits is caught",
                  bool(check_step1())))
    reset()

    # 125. P-UI-98e: the press edge stops recording the row it landed on.
    with_source(EVENTS, "                    g_s1ClickRow = s1Row;\n", "")
    cases.append(("a click that cannot name its handle is caught",
                  bool(check_step1())))
    reset()

    # 126. P-UI-98e: the ride places a step-1 icon while the pair is SET.
    with_source(EVENTS, "    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0 && g_linesVisible && !IsIndicatorHidden())",
                "    if(g_s1MarkAbovePrice > 0.0 && g_linesVisible && !IsIndicatorHidden())")
    cases.append(("a red handle over a SET line is caught",
                  bool(check_step1())))
    reset()

    # 127. P-UI-98f: the face gate goes back to the rung number (the ladder's
    # below rung 1 is the boundary line ON the custom price).
    with_source(PIPELINE, "            if(lines[i].name == s1AboveName || lines[i].name == s1BelowName)",
                "            if(lines[i].logicalStep == 1)")
    cases.append(("a handle on the ladder's below rung 1 is caught",
                  bool(check_step1())))
    reset()

    # 128. P-UI-98f: the pick stops being anchored on the custom price line.
    with_source(PIPELINE, "    Step1HandlePick(lines, lineCount, GetMidpointPrice(g_thStartPointType),\n", "")
    cases.append(("a handle picked off another anchor is caught",
                  bool(check_step1())))
    reset()

    # 129. P-UI-98f: the pick measures against a step of its own (the pair could
    # change under a live drag and hand the gesture to another line).
    with_source(PIPELINE, "                    StepOverrideFactor() * NaturalFirstStep(),\n",
                "                    GetMidpointPrice(g_thStartPointType) * 0.1,\n")
    cases.append(("a pair that changes under the drag is caught",
                  bool(check_step1())))
    reset()

    # 130. P-UI-98f: the handle match goes back to a name tail.
    with_source(EVENTS, "    return (name == g_s1MarkAboveName || name == g_s1MarkBelowName);\n",
                '    return (StringSubstr(name, StringLen(name) - 8, 8) == "_Above_1");\n')
    cases.append(("a below handle no suffix can name is caught",
                  bool(check_step1())))
    reset()

    # 131. P-UI-98f: the drag math reads the side off the name again.
    with_source(EVENTS, "    bool above = Step1LineIsAbove(name);\n",
                '    bool above = (StringSubstr(name, StringLen(name) - 8, 8) == "_Above_1");\n')
    cases.append(("a below handle read as the above one is caught",
                  bool(check_step1())))
    reset()

    # 132. P-UI-98f: the pick answers one side only.
    with_source(PIPELINE, "        if(lines[i].direction > 0)\n", "        if(true)\n")
    cases.append(("a pick that shadows a side is caught", bool(check_step1())))
    reset()

    # 133. P-UI-98f: the drag drops its press baseline (a grab that moves nothing
    # rescales the ladder by the handle's own offset).
    with_source(EVENTS, "        s_s1GrabDist = MathAbs(dragged - start);\n", "")
    cases.append(("a phantom grab that snaps the step is caught",
                  bool(check_step1())))
    reset()

    # 134. P-UI-98f: the drag goes back to the absolute reading only.
    with_source(EVENTS, "                       ? (s_s1GrabFactor * (newFirst / s_s1GrabDist))\n",
                "                       ? (newFirst / natural)\n")
    cases.append(("a handle that loses its offset under the hand is caught",
                  bool(check_step1())))
    reset()

    # 135. P-UI-98f: the stand-down goes back to "differs from my last write".
    with_source(EVENTS, "        s_s1SeenPrice = current;\n", "")
    cases.append(("a carry that stands down forever is caught",
                  bool(check_step1())))
    reset()

    # 136. P-UI-98f: the carry forgets its own write is what the next event sees.
    with_source(EVENTS, "                    s_s1SeenPrice = wishPrice;   // we are the last mover\n", "")
    cases.append(("a carry that reads its own write as the terminal is caught",
                  bool(check_step1())))
    reset()

    # 137. P-UI-98f: the stale-drag heal stops clearing the gesture's state.
    with_source(EVENTS, "        Step1GestureStateClear();\n", "")
    cases.append(("a healed gesture that poisons the next one is caught",
                  bool(check_step1())))
    reset()

    # 139. P-UI-98q: the green circle waits for a click again (the placement
    # it alone faces shows nothing until asked).
    with_source(EVENTS, "    bool show = g_customPriceLineCreated &&\n                !IsIndicatorHidden() &&\n                g_thStartPointType == TH_START_POINT_CUSTOM_PRICE;\n",
                "    bool show = g_customPriceLineCreated && g_cpLineArmed && g_cpHandleShown &&\n                !IsIndicatorHidden() && g_linesVisible &&\n                g_thStartPointType == TH_START_POINT_CUSTOM_PRICE;\n")
    cases.append(("a green circle that waits for a click is caught",
                  bool(check_step1())))
    reset()

    # 140. P-UI-98g: the red circles come up without a click (the ride channel).
    with_source(EVENTS, "g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0",
                "g_s1LinesArmed && g_s1MarkAbovePrice > 0.0")
    cases.append(("a red circle the ride resurrects unasked is caught",
                  bool(check_step1())))
    reset()

    # 141. P-UI-98g: the click on the custom price line stops revealing.
    with_source(EVENTS, "    if(!g_cpHandleShown)\n", "    if(false)\n")
    cases.append(("an armed line with no way to show its handle is caught",
                  bool(check_step1())))
    reset()

    # 142. P-UI-98g: our own drag stops revealing the circles.
    with_source(EVENTS, "    g_s1HandleShown = true;\n    g_s1OwnActive = true;",
                "    g_s1OwnActive = true;")
    cases.append(("a drag that leaves no circle behind is caught",
                  bool(check_step1())))
    reset()

    # 143. P-UI-98g: a fresh placement is born with the circles already up.
    with_source(EVENTS, "    g_cpHandleShown = false;\n    g_s1HandleShown = false;\n}\n",
                "}\n")
    cases.append(("a placement that is born shown is caught",
                  bool(check_step1())))
    reset()

    # 144. P-UI-98g: a SET leaves the circles up.
    with_source(EVENTS, "            g_s1HandleShown = false;  // P-UI-98g: nothing points at a set line\n", "")
    cases.append(("a circle left over a SET line is caught",
                  bool(check_step1())))
    reset()

    # 145. P-UI-98g: the teardown leaves the reveal latches set.
    with_source(EVENTS, "        g_cpHandleShown = false;\n        g_s1HandleShown = false;\n        g_cpSetPending = \"\";",
                "        g_cpSetPending = \"\";")
    cases.append(("a placement that inherits a shown handle is caught",
                  bool(check_step1())))
    reset()

    # 138. P-UI-98f: the settle clears before its own echo stamp.
    with_source(EVENTS, "    if(!g_s1DragLive) return;\n    g_s1DragLive = false;\n",
                "    if(!g_s1DragLive) return;\n    g_s1DragLive = false;\n    Step1GestureStateClear();\n")
    cases.append(("a drag whose release SETs its own handle is caught",
                  bool(check_step1())))
    reset()

    # 146. P-UI-98h: the finalizer runs with no button witness, i.e. on the
    # press echo that the panels already measured (P-UI-49b / P-UI-73).
    with_source(EVENTS, "    if(!UILeftButtonUp()) return;\n    string row = g_s1ClickRow;\n",
                "    string row = g_s1ClickRow;\n")
    cases.append(("a CLICK on the PRESS that kills the drag is caught",
                  bool(check_step1())))
    reset()

    # 147. P-UI-98h: the click owner arms the SET while the gesture is live.
    with_source(EVENTS, "    if(g_s1LinesArmed && !g_s1DragLive && now - g_s1JustDraggedMs > 350)\n",
                "    if(g_s1LinesArmed && now - g_s1JustDraggedMs > 350)\n")
    cases.append(("a SET armed under a live drag is caught",
                  bool(check_step1())))
    reset()

    # 148. P-UI-98h: the sweeper goes back to committing with the button down
    # (the first slot - the check counts both).
    with_source(EVENTS, "DOUBLE_CLICK_THRESHOLD_MS\n       && UILeftButtonUp())",
                "DOUBLE_CLICK_THRESHOLD_MS)")
    cases.append(("a SET committed while the button is down is caught",
                  bool(check_step1())))
    reset()

    # 149. P-UI-98h: the claim stops cancelling the pending SET.
    with_source(EVENTS, '    g_s1SetPending = "";\n    g_s1SetPendingMs = 0;\n', "")
    cases.append(("a pending SET that outlives the grab is caught",
                  bool(check_step1())))
    reset()

    # 150. P-UI-98h: a settle that moved the line leaves the pending SET alive.
    with_source(EVENTS, '    if(s1Moved) { g_s1SetPending = ""; g_s1SetPendingMs = 0; }\n', "")
    cases.append(("a SET that survives the drag it belonged to is caught",
                  bool(check_step1())))
    reset()

    # 151. P-UI-98h: the grab gate goes back to the 1 px line instead of the
    # 15 px circle the hand actually grabs.
    with_source(EVENTS, "    int tolPx = HANDSET_HANDLE_HALF + (int)inpCustomPriceLevelWidth + 3;",
                "    int tolPx = (int)inpCustomPriceLevelWidth + 4;")
    cases.append(("a handle whose icon rim cannot be grabbed is caught",
                  bool(check_step1())))
    reset()

    # 152. P-UI-98i: nearest-wins goes back to custom-always-wins (on a coarse
    # chart the red handle can never be grabbed).
    with_source(EVENTS, "                bool s1OnRow = (s1Hit && (!onCustomLine ||\n                                          Step1NearerThanCustom((int)lparam, (int)dparam, s1Row)));",
                "                bool s1OnRow = (s1Hit && !onCustomLine);")
    cases.append(("a handle no press near both rows can take is caught",
                  bool(check_step1())))
    reset()

    # 153. P-UI-98i: the missed press edge stops claiming through the
    # terminal's own selection (one off-chart release kills the handle).
    with_source(EVENTS, "                if(!s1OnRow && !pressEdge && g_s1LinesArmed && !onCustomLine &&",
                "                if(false &&")
    cases.append(("a handle dead after a missed press edge is caught",
                  bool(check_step1())))
    reset()

    # 154. P-UI-98i: a native-only drag is never adopted into the own carry
    # (OBJECT_DRAG alone, and the builds where it stutters cut the drag).
    with_source(EVENTS, "            else if(g_s1DragLive && !g_s1OwnActive && !g_customPriceLineDragging)",
                "            else if(false)")
    cases.append(("a native-only drag no carry adopts is caught",
                  bool(check_step1())))
    reset()

    # 155. P-UI-98i: the press latch stops retrying (one failed conversion
    # freezes the carry for the whole gesture).
    with_source(EVENTS, "    if(!(g_s1OwnGrabCursorPrice > 0.0))",
                "    if(false)")
    cases.append(("a frozen grab latch no retry heals is caught",
                  bool(check_step1())))
    reset()

    # 156. P-UI-98i: the surplus sweep throttles for the line's drag only
    # (a full sweep deletes under the step-1 hand).
    with_source(PIPELINE, "    if(g_customPriceLineDragging || g_s1DragLive) {",
                "    if(g_customPriceLineDragging) {")
    cases.append(("a surplus sweep under the step-1 hand is caught",
                  bool(check_step1())))
    reset()

    # 157. P-UI-98j: the tick path stops running the self-heal (a vanished
    # handle waits for an unrelated rebuild again).
    with_source(EVENTS, "    Step1HandleHealMissing();\n", "")
    cases.append(("a tick path without the step-1 net is caught",
                  bool(check_step1())))
    reset()

    # 158. P-UI-98j: the heal guesses with no window known.
    with_source(EVENTS, "    if(!(wMax > wMin)) return;   // no window known: do not guess\n", "")
    cases.append(("a self-heal that repairs blind is caught",
                  bool(check_step1())))
    reset()

    # 159. P-UI-98j: the heal fires mid-gesture again.
    with_source(EVENTS, "    if(!g_s1LinesArmed || g_s1DragLive) return;\n",
                "    if(!g_s1LinesArmed) return;\n")
    cases.append(("a self-heal that rebuilds under the hand is caught",
                  bool(check_step1())))
    reset()

    # 160. P-UI-98j: a suppressed delete of a handle is ignored again.
    with_source(EVENTS, "    else if(id == CHARTEVENT_OBJECT_DELETE && suppressDeleteEvent && sparam != \"\" &&",
                "    else if(false &&")
    cases.append(("a windowed delete with no heal armed is caught",
                  bool(check_step1())))
    reset()

    # 161. P-UI-98j: the heal wipes the family for a hole.
    with_source(EVENTS, "    // topology change, never a hole.\n    g_redrawTHLevelsNeeded = true;\n    MarkDrawGeneration();\n}",
                "    // topology change, never a hole.\n    g_redrawTHLevelsNeeded = true;\n    g_forceClearOnNextDraw = true;\n    MarkDrawGeneration();\n}")
    cases.append(("a self-heal that blinks the chart is caught",
                  bool(check_step1())))
    reset()

    # 162. P-UI-98j: the heal repairs correctly culled off-screen lines.
    with_source(EVENTS, "    if(g_s1MarkAboveName != \"\" && g_s1MarkAbovePrice >= wMin && g_s1MarkAbovePrice <= wMax &&\n",
                "    if(g_s1MarkAboveName != \"\" &&\n")
    cases.append(("a self-heal that churns culled lines is caught",
                  bool(check_step1())))
    reset()

    # 163. P-UI-98k: the foreign sweep deletes the live-dragged handle again
    # (the drag holds a name the chart no longer carries).
    with_source(PIPELINE, "       bool s1SkipSweep = (g_s1DragLive && g_s1DragName != \"\" &&\n                           lines[i].name == g_s1DragName);\n",
                "")
    cases.append(("a sweep that eats the dragged handle is caught",
                  bool(check_step1())))
    reset()

    # 164. P-UI-98l: the ride stops obeying the LINES switch on the above
    # side (L off parks the circle, the next mouse move resurrects it).
    with_source(EVENTS, "    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0 && g_linesVisible && !IsIndicatorHidden())",
                "    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0)")
    cases.append(("a red circle the L key cannot hide is caught",
                  bool(check_step1())))
    reset()

    # 165. P-UI-98l: the ride stops obeying the LINES switch on the below
    # side.
    with_source(EVENTS, "    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkBelowPrice > 0.0 && g_linesVisible && !IsIndicatorHidden())",
                "    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkBelowPrice > 0.0)")
    cases.append(("a below circle the L key cannot hide is caught",
                  bool(check_step1())))
    reset()

    # 167. P-UI-98p: the transition stops re-asserting the never-painted
    # mask (the line comes back).
    with_source(EVENTS, "    // P-UI-98p: the mask is re-asserted, never lifted - the line is never\n    // painted (see the creator), the green circle is the placement.\n    if(ObjectFind(0, g_customPriceHorizontalLineName) >= 0 &&\n       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)\n        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);\n",
                "")
    cases.append(("a transition that repaints the line is caught",
                  bool(check_step1())))
    reset()

    # 168. P-UI-98m: a single click re-arms (the deliberate look costs a
    # drag).
    with_source(EVENTS, "    if(!dbl) return;\n", "")
    cases.append(("a single click that re-arms is caught",
                  bool(check_step1())))
    reset()

    # 169. P-UI-98m: the press edge records the candidate on an ARMED line
    # too (two click contracts answer one press).
    with_source(EVENTS, "                if(pixelHit && !g_cpLineArmed)\n", "                if(pixelHit)\n")
    cases.append(("a press claimed by two click owners is caught",
                  bool(check_step1())))
    reset()

    # 170. P-UI-98p: the F show path resurrects the custom line.
    with_source(EVENTS, "        // P-UI-98p: no custom-line restore - the line is never painted (the\n        // green circle is the placement), so the F cycle must not resurrect it\n        // in any state.\n",
                "        if(g_customPriceLineCreated)\n            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);\n")
    cases.append(("an F press that repaints the line is caught",
                  bool(check_step1())))
    reset()

    # 174. P-UI-98p: the creator stops re-asserting the never-painted mask
    # (a fresh line arrives visible).
    with_source(EVENTS, "    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&\n       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)\n        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);\n",
                "")
    cases.append(("a creator that paints the line is caught",
                  bool(check_step1())))
    reset()

    # 171. P-UI-98n: the LINES switch stops syncing the markers (the circles
    # wait for the next render/mousemove again).
    with_source(EVENTS, "    HandsetMarkersRide();\n}\n\n//==============================================================================\n// P-PERF-30",
                "}\n\n//==============================================================================\n// P-PERF-30")
    cases.append(("a LINES switch the circles follow late is caught",
                  bool(check_step1())))
    reset()

    # 172. P-UI-98n: the switch syncs the green dot only (the reds lag
    # again).
    with_source(EVENTS, "    HandsetMarkersRide();\n}\n\n//==============================================================================\n// P-PERF-30",
                "    CustomPriceMarkerSync();\n}\n\n//==============================================================================\n// P-PERF-30")
    cases.append(("a LINES switch that leaves the red circles is caught",
                  bool(check_step1())))
    reset()

    # 173. P-UI-98o: the green circle obeys the LINES switch again (L hides
    # the placement marker with the line family).
    with_source(EVENTS, "    bool show = g_customPriceLineCreated &&\n                !IsIndicatorHidden() &&\n                g_thStartPointType == TH_START_POINT_CUSTOM_PRICE;\n",
                "    bool show = g_customPriceLineCreated &&\n                !IsIndicatorHidden() && g_linesVisible &&\n                g_thStartPointType == TH_START_POINT_CUSTOM_PRICE;\n")
    cases.append(("a green circle the L key hides is caught",
                  bool(check_step1())))
    reset()

    # 175. P-UI-98q: the green half shrinks to the reds' (the 19 px raster
    # sits off its price).
    with_source(GLOBALS, "#define CP_HANDLE_HALF       9", "#define CP_HANDLE_HALF       7")
    cases.append(("a mis-centred green circle is caught",
                  bool(check_step1())))
    reset()

    # 177. P-UI-98r: PnlOpen stops publishing + culling (boxes drawn before
    # it opened stay over it).
    with_source(PANELS, "   // P-UI-98r: the card is placed - mask the HTF boxes under it at once\n   // (chart rectangles paint over screen skins at any rung).\n   PnlPublishCover();\n   HTFCardCullRefresh();\n",
                "")
    cases.append(("a card that opens over HTF boxes is caught",
                  bool(check_step1())))
    reset()

    # 178. P-UI-98r: PnlCloseAll stops releasing (closed card leaves boxes
    # masked).
    with_source(PANELS, "   // P-UI-98r: cover invalidated - give back what the cull took, now.\n   PnlPublishCover();\n   HTFCardCullRefresh();\n",
                "")
    cases.append(("a closed card that keeps boxes masked is caught",
                  bool(check_step1())))
    reset()

    # 179. P-UI-98r: the timer net goes (zoom/resize drift converges on
    # nothing).
    with_source(ENTRY, "    // P-UI-98r: the net under the card-cull's event hooks (open/close/drag/\n    // draw) - zoom, resize and forming-candle drift converge here within one\n    // tick of the 250 ms clock. Closed / HTF-off / nothing drawn: three bool\n    // reads and out.\n    HTFCardCullRefresh();\n",
                "")
    cases.append(("a card-cull with no timer net is caught",
                  bool(check_step1())))
    reset()

    # 180. P-UI-98r: the uncover unmasks naively (resurrects F-hidden boxes).
    with_source(HTF, "            ObjectSetInteger(0, nm[k], OBJPROP_TIMEFRAMES,\n                             IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);\n",
                "            ObjectSetInteger(0, nm[k], OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);\n")
    cases.append(("a cull that resurrects hidden boxes is caught",
                  bool(check_step1())))
    reset()

    # 181. P-UI-98r: masked boxes are not tracked (the release names
    # nothing).
    with_source(HTF, "            HTFCullTrack(nm[k]);\n", "")
    cases.append(("an untracked cull nothing releases is caught",
                  bool(check_step1())))
    reset()

    # 182. P-UI-98r: a pruned box lingers in the cull set.
    with_source(HTF, "      // P-UI-98r: a pruned box leaves the card-cull set with it - a tracked\n      // name that no longer exists must not linger (its release write would\n      // fail silent, and the slot is a lie the next refresh would keep).\n      HTFCullForget(g_HTFPrefix + id);\n      HTFCullForget(g_HTFPrefix + id + \"_F\");\n      HTFCullForget(g_HTFPrefix + id + \"_B\");\n      HTFCullForget(g_HTFPrefix + \"WU\" + id);\n      HTFCullForget(g_HTFPrefix + \"WL\" + id);\n",
                "")
    cases.append(("a pruned box the cull set keeps is caught",
                  bool(check_step1())))
    reset()

    # 176. P-UI-98p: the per-frame enforcer goes (a leaked-visible line stays
    # painted).
    with_source(EVENTS, "    // P-UI-98p: NEVER-PAINTED, enforced every frame. The creator and the\n    // transition both skip mid-gesture (P-BK-15) - and a gesture flag stuck\n    // set (a release off-chart leaves NativeDrag armed) births the next line\n    // with the terminal default, VISIBLE. Whatever the leak, one guarded read\n    // per frame re-masks on drift; a steady frame costs nothing. No gesture\n    // gate: a masked line is never MT4-dragged, so there is no native drag\n    // to cancel - and the mask is the correct state mid-gesture too.\n    if(lineExists &&\n",
                "    if(false &&\n")
    cases.append(("a leaked-visible line with no enforcer is caught",
                  bool(check_step1())))
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
