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
    if ring is None or slot is None or tools is None:
        return ["RING_COUNT / RING_BASEKNOT / TOOL_COUNT are gone - the measure item "
                "has no declared slot (P-UI-95)"]
    if slot != ring - 1:
        problems.append("RING_BASEKNOT (%d) is not the slot RING_COUNT (%d) counts: an "
                        "APPENDED slot is what keeps every existing state key's "
                        "meaning (P-UI-95)" % (slot, ring))
    feats = body(code, "RingFeature(") or ""
    if "case RING_BASEKNOT: return CIR_BASEKNOT;" not in feats:
        problems.append("the measure slot no longer maps to CIR_BASEKNOT - the item "
                        "cannot be reached at all")
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
    # (b) the settle heal: the pump must compare the box against its own top edge,
    #     through the ONE button owner, and must keep skipping a live drag.
    pump = body(src, "void BaseKnotSyncBadges(")
    if pump is None:
        problems.append("BaseKnotSyncBadges() is gone - the 500 ms pump is the settle owner")
    else:
        if "if(bkHandOff && !BaseKnotBorderSettled(" not in pump:
            problems.append("the pump no longer settles a box whose border is behind it (P-BK-18) - "
                            "a lost gesture end leaves the border adrift until a TF switch")
        if "bkHandOff" not in pump or "UILeftButtonUp()" not in pump:
            problems.append("the settle heal lost its button gate (the ONE owner, P-UI-73) - writing "
                            "into a live native drag cancels it (P-BK-15)")
        if "s_bkDragId != \"\" && g_bkBoxes[i].id == s_bkDragId" not in pump:
            problems.append("the pump stopped skipping the actively dragged box (P-BK-15)")
    settle = body(src, "bool BaseKnotBorderSettled(")
    if settle is None:
        problems.append("BaseKnotBorderSettled() is gone - the settle compare needs its ONE owner")
    else:
        if "BK_EDGE_T" not in settle or "OBJPROP_TIME, 1" not in settle or "OBJPROP_PRICE, 0" not in settle:
            problems.append("BaseKnotBorderSettled() no longer compares the top edge's span AND price "
                            "against the box - half the divergence would go unseen")
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
    # (d) P-BK-19b: the grab-role measurement fed the CURSOR FALLBACK only, and that
    #     fallback is retired (BKCURSOR-OFF) - so the press must NOT measure a role
    #     any more. The dormant restore-path integrity is
    #     `check_bkcursor_off()`'s job, one group per promise.
    if re.search(r"(?m)^\s*s_bkGrabSel = BaseKnotGrabRole\(shbox", src):
        problems.append("the press measures a grab role again although the cursor fallback is "
                        "retired - that role has no consumer (BKCURSOR-OFF/P-BK-19b)")
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
    # (g0) BKMIDGRIP-OFF (2026-09-16): FOUR CORNERS, and the COUNT lives in ONE place.
    #     The mid-edge chips are retired by user decision, so the live family is the
    #     four corners; every sweep must ask `BK_GRIP_COUNT` instead of a literal 8,
    #     and a chart the older build already wrote must be swept ONCE - a ghost chip
    #     is a SELECTABLE square that drags nothing (the terminal would keep handing
    #     the selection to it).
    at = body(src, "int BaseKnotGripSideAt(")
    if at is None:
        problems.append("BaseKnotGripSideAt() is gone - the handle family has no plan (BKMIDGRIP-OFF)")
    else:
        corners = re.findall(r"if\(i == \d+\) return \(BK_GS_[TBLR] \| BK_GS_[TBLR]\);", at)
        if re.search(r"if\(i == \d+\) return BK_GS_[TBLR];", at):
            problems.append("a single-side (mid-edge) chip row is live again (BKMIDGRIP-OFF) - the "
                            "user retired exactly those four squares")
        if len(corners) != 4:
            problems.append("BaseKnotGripSideAt() plans %d corner chips, the family is FOUR corners "
                            "(BKMIDGRIP-OFF)" % len(corners))
        cnt = re.search(r"#define\s+BK_GRIP_COUNT\s+(\d+)", src)
        if cnt is None or int(cnt.group(1)) != len(corners):
            problems.append("BK_GRIP_COUNT does not equal the corner rows of BaseKnotGripSideAt() "
                            "(BKMIDGRIP-OFF) - a sweep would walk a chip that has no side")
        for sig, why in (("bool BaseKnotGripsFollow(", "the keeper's sweep"),
                         ("bool BaseKnotSelectionMarkersWipe(", "the drop's wipe")):
            blk = body(src, sig)
            if blk is not None and re.search(r"i < 8\b", blk):
                problems.append("%s loops to a hard-coded 8 (BKMIDGRIP-OFF) - the count lives in "
                                "BK_GRIP_COUNT and nowhere else" % why)
    lazy = body(src, "void BaseKnotLazyInit(")
    if lazy is None or '"GT"' not in lazy:
        problems.append("the one-time sweep of the retired mid-edge chips is gone (BKMIDGRIP-OFF) - "
                        "a chart the older build wrote keeps four selectable squares that drag nothing")
    keep = body(src, "bool BaseKnotGripsFollow(")
    if keep is None:
        problems.append("BaseKnotGripsFollow() is gone - the handle family has no owner (P-BK-61)")
    else:
        if "side == skip" not in keep:
            problems.append("the handle keeper no longer spares the chip the hand is dragging "
                            "(P-BK-61/P-BK-15) - writing it cancels the terminal's own drag")
        if "ObjectDelete" not in keep:
            problems.append("the handle keeper never retires a chip (P-BK-61) - a deselected or "
                            "locked box would keep its eight handles on screen")
        if "OBJPROP_SELECTABLE, true" not in keep and "OBJPROP_SELECTABLE, true" not in (body(src, "void BaseKnotGripCreate(") or ""):
            problems.append("a handle is stored UNSELECTABLE (P-BK-61) - the terminal would never "
                            "drag it and the whole feature would be silently absent")
    mk = body(src, "void BaseKnotGripCreate(")
    if mk is None:
        problems.append("BaseKnotGripCreate() is gone - the handle look has no owner (P-BK-61)")
    elif "OBJ_RECTANGLE_LABEL" not in mk:
        problems.append("a handle is no longer a SCREEN object (P-BK-61) - the design rests on MT4 "
                        "dragging a selectable screen square natively")
    if events is not None and "BaseKnotGripDrag(" not in events:
        problems.append("no OBJECT_DRAG branch routes a handle to its resize (P-BK-61) - the handles "
                        "would be draggable objects that move nothing (P-UI-47's fault, in a new place)")
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
    if events is not None and "if(bkGripWas == 0) BaseKnotBodySizeHeal(" not in events:
        problems.append("the body-size heal is not gated on the gesture being a BODY drag "
                        "(P-BK-61b) - it would undo a handle resize on every release")
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
                        "the box leaves it selected and wearing its eight handles")
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
            problems.append("the drop leaves the eight handles (and the centre grip) on screen "
                            "(P-BK-63) - they are only retired by the 500 ms pump, so the "
                            "deselected box keeps wearing its marks for up to half a second")
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
    if re.search(r"(?m)^\s*//\s*s_bkGrabSel = BaseKnotGrabRole\(shbox", src) is None:
        problems.append("the retired press-time role measurement is deleted, not commented - the "
                        "restore path is gone (BKCURSOR-OFF)")
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
        problems.append("BaseKnotGripSnapPrice() is gone - the Ctrl magnet's reader must stay "
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
        problems.append("BaseKnotGripDrag() is gone - the Ctrl magnet's ONLY caller (P-BK-61)")
    elif "if(ctrl && " not in grip or "BaseKnotGripSnapPrice(" not in grip:
        problems.append("the magnet is not gated on CONTROL inside the handle drag (P-BK-61) - an "
                        "ungated magnet IS the behaviour BKMAGNET2-OFF removed")
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


def main():
    problems = []
    groups = (("rows", check_rows()), ("persist", check_persist()),
              ("palette", check_palette()), ("captions", check_captions()),
              ("trex", check_trex_card()),
              ("relayout", check_relayout()), ("purge", check_purge()),
              ("body", check_card_body()),
              ("modal", check_modal()),
              ("measure", check_measure_item()),
              ("bk-info", check_bk_info_rungs()),
              ("press", check_press(read(PANELS))),
              ("chrome", check_chrome()),
              ("dual", check_dual()),
              ("drag", check_drag()),
              ("mouse", check_mouse()),
              ("bk-drag", check_bk_drag()),
              ("heal", check_heal()),
              ("bkcursor-off", check_bkcursor_off()),
              ("bkmagnet", check_bkmagnet()),
              ("paneldrag-off", check_paneldrag_off()),
              ("placement", check_placement()))
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
                       or check_press(read(PANELS)) or check_chrome()
                       or check_dual() or check_drag() or check_mouse()
                       or check_bk_drag() or check_bkcursor_off()
                       or check_heal())))
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

    # 67. P-BK-18: the settle heal's gate is opened (a write into a live native
    #     drag would cancel the terminal's own gesture, P-BK-15)
    with_source(BASEKNOT, "      if(bkHandOff && !BaseKnotBorderSettled(pfx, t1, t2, top))",
                "      if(true)")
    cases.append(("a settle heal that ignores the button gate is caught",
                  bool(check_bk_drag())))
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

    # 70. BKCURSOR-OFF: the dormant restore path is DELETED instead of commented
    with_source(BASEKNOT,
                "                    // s_bkGrabSel = BaseKnotGrabRole(shbox, s_bkDragX0, s_bkDragY0);",
                "                    // seed: the dormant role call was deleted, not commented")
    cases.append(("a deleted (not dormant) role call is caught",
                  bool(check_bkcursor_off())))
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

    # 77. P-BK-61: the Ctrl gate is the whole difference between the magnet the user
    #     asked for and the one BKMAGNET2-OFF removed - drop it and the handle drag
    #     snaps on every step.
    with_source(BASEKNOT,
                "   if(ctrl && (side & (BK_GS_T | BK_GS_B)) != 0) gp = BaseKnotGripSnapPrice(gt, gp);",
                "   gp = BaseKnotGripSnapPrice(gt, gp);")
    cases.append(("an UNGATED handle magnet is caught", bool(check_bkmagnet())))
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
    #     (the eight handles), and the FILL only carries it.
    with_source(BASEKNOT, "if(bkGripWas == 0) BaseKnotBodySizeHeal(s_bkDragId);", "")
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

    # 87. BKMIDGRIP-OFF: a mid-edge chip row comes back to life.
    with_source(BASEKNOT, "   if(i == 3) return (BK_GS_B | BK_GS_R);",
                "   if(i == 3) return (BK_GS_B | BK_GS_R);\n   if(i == 4) return BK_GS_T;")
    cases.append(("a revived mid-edge chip is caught", bool(check_bk_drag())))
    reset()

    # 88. BKMIDGRIP-OFF: a corner row is dropped (the count and the plan part ways).
    with_source(BASEKNOT, "   if(i == 3) return (BK_GS_B | BK_GS_R);\n", "")
    cases.append(("a corner that the family no longer plans is caught",
                  bool(check_bk_drag())))
    reset()

    # 89. BKMIDGRIP-OFF: a sweep walks a hard-coded 8 again.
    with_source(BASEKNOT, "   for(int i = 0; i < BK_GRIP_COUNT; i++)\n   {\n      int side = BaseKnotGripSideAt(i);",
                "   for(int i = 0; i < 8; i++)\n   {\n      int side = BaseKnotGripSideAt(i);")
    cases.append(("a sweep that walks a retired chip is caught",
                  bool(check_bk_drag())))
    reset()

    # 90. BKMIDGRIP-OFF: the one-time sweep of a chart the older build wrote is gone -
    #     four selectable squares stay on it, dragging nothing.
    with_source(BASEKNOT, '      string midNames[4] = {"GT", "GB", "GL", "GR"};',
                '      string midNames[4] = {"", "", "", ""};')
    cases.append(("a chart keeping the retired chips is caught",
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
