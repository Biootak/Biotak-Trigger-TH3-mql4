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
            cannot kill the drag that same press started.

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
UTILS = os.path.join(ROOT, "Biotak", "UtilityFunctions.mqh")
BASEKNOT = os.path.join(ROOT, "Biotak", "BaseKnotTool.mqh")
ICONS = os.path.join(ROOT, "Files", "Icons")

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
    CONTROLS = ("PnlClosePressHit(", "PnlDdAnchorHit(", "PnlKnobHit(",
                "PnlTrackHit(", "PnlSwitchHit(", "PnlCsetHit(",
                "PnlDualHit(", "PnlColorAddHit(", "PnlBandHit(")
    pc = body(text, "bool PnlPointOnControl(")
    if pc is None:
        problems.append("PnlPointOnControl() is gone - a POLLED grab would steal a "
                        "press aimed at a control (P-UI-75a)")
    else:
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
            problems.append("the grab does not refuse the RELEASE-channel controls, "
                            "so a tap on them starts a card drag and their own click "
                            "is spent (P-UI-76)")
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
        elif g >= 0 and c > g:
            problems.append("%s is consulted AFTER the grab, so the grab steals "
                            "the control's own press" % control.rstrip("("))
    own = body(text, "bool PnlPressAllowed(")
    if own is None:
        problems.append("PnlPressAllowed() is gone")
    else:
        if "UILeftButtonDown()" not in own and "TERMINAL_KEYSTATE_LEFT" not in own:
            problems.append("the stale-claim recovery no longer checks the physical "
                            "button - it would steal a LIVE gesture")
        if "g_DragOwner = DRAG_NONE" not in own:
            problems.append("the stale-claim recovery never releases the claim")
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
        if "PnlDragPoll();" not in polled:
            problems.append("the poll is not wired into the tick/timer pump, so it "
                            "never runs")
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
                             tail.find("PnlPointOnControl("),
                             tail.find("PnlHeaderHit("),
                             tail.find("PnlCardBodyHit("),
                             tail.find("PnlPalettePointInside(")) if h >= 0]
        if cheap < 0 or len(heavy) != 6 or min(heavy) < cheap:
            problems.append("the poll's idle path is not cheap: the open-card guard "
                            "(`g_PnlOpen`) must come BEFORE every hit test and "
                            "every TerminalInfoInteger read")
    if "PnlDragStep(mx, my)" not in chain or "PnlDragFinish(true, true)" not in chain:
        problems.append("the press chain does not use the shared batch owner / "
                        "finish - the two entries cannot share one window")
    if "if(!s_PnlClickChannel && PnlTryGrabMove(mx,my,false)) return;" not in chain:
        problems.append("the grab is not refused on the click channel - a released "
                        "button would start a move gesture")
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
        for code in ("\"M\"", "\"X\"", "\"P\"", "\"C\"", "\"H\""):
            if "PnlGrabRefused(%s,byPoll" % code not in grab:
                problems.append("a grab refusal lost its ledger call (%s) - that "
                                "refusal is silent again (P-UI-78)" % code)
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
    if not re.search(r'ObjectsDeleteAll\(\s*0\s*,\s*head\s*,\s*0\s*,\s*-1\s*\)', dblk):
        problems.append("PnlDestroy() no longer wipes the card's whole prefix - an "
                        "index-bounded hand list cannot cover a card whose rows "
                        "grew, and every row it misses stays on the chart")
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
    # the card body pieces must be torn down too
    m = re.search(r'ObjectsDeleteAll\(\s*0\s*,\s*head\s*\+\s*"card"', dblk)
    if m is None:
        problems.append("PnlDestroy() does not wipe the composed card body - a "
                        "card that shrinks would leave its own tiles behind")
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


def main():
    problems = []
    groups = (("rows", check_rows()), ("persist", check_persist()),
              ("palette", check_palette()), ("captions", check_captions()),
              ("trex", check_trex_card()),
              ("relayout", check_relayout()), ("purge", check_purge()),
              ("body", check_card_body()),
              ("modal", check_modal()),
              ("press", check_press(read(PANELS))),
              ("chrome", check_chrome()),
              ("dual", check_dual()),
              ("drag", check_drag()),
              ("mouse", check_mouse()))
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
                       or check_press(read(PANELS)) or check_chrome()
                       or check_dual() or check_drag() or check_mouse())))
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
    with_source(PANELS, "   ObjectsDeleteAll(0, head, 0, -1);",
                "   for(int r=0;r<PNL_CARD_ROWS_MAX;r++) ObjectDelete(0,head+IntegerToString(r));")
    cases.append(("a card teardown that cannot cover its rows is caught",
                  bool(check_purge())))
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
    with_source(PANELS, "   if(!UILeftButtonUp()) return;",
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

    # 25. a released button starts the card-move gesture again
    with_source(PANELS, "      if(!s_PnlClickChannel && PnlTryGrabMove(mx,my,false)) return;",
                "      if(PnlTryGrabMove(mx,my,false)) return;")
    cases.append(("a plain click that drags the card is caught",
                  bool(check_dual() or check_drag())))
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
    with_source(PANELS, "   PnlDragPoll();  // P-UI-75a", "   // seed: the poll is gone")
    cases.append(("a drag reachable from one delivery channel only is caught",
                  bool(check_drag())))
    reset()

    # 32. the poll pays for a hit test before it can bail out - an idle tick
    #     (every tick, plus the 250 ms timer) stops being one int compare
    with_source(PANELS, "   if(g_PnlDragItem >= 0 || g_PalMixDrag > 0) return;   // another panel gesture owns it",
                "   PnlPointOnControl(g_LastUIX, g_LastUIY);   // seed: a hit test on the idle path\n"
                "   if(g_PnlDragItem >= 0 || g_PalMixDrag > 0) return;   // another panel gesture owns it")
    cases.append(("a poll that is not free when idle is caught", bool(check_drag())))
    reset()

    # 33. P-UI-76: the grab stops refusing the RELEASE-channel controls - a tap on
    #     a quick swatch / NAV pill / Reset starts a card drag and its own click is
    #     spent by the drag's release claim (the control reads as dead)
    with_source(PANELS, "   if(PnlNameControlAt(mx,my)) return true;   // P-UI-76: the release channel's own",
                "   // seed: the release channel is grabbable")
    cases.append(("a grab that eats a release-channel control is caught",
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
    with_source(PANELS, '   if(PnlPointOnControl(mx,my)) { PnlGrabRefused("C",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }',
                '   if(PnlPointOnControl(mx,my)) return false;')
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
