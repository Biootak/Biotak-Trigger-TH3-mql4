#!/usr/bin/env python3
"""
RENDER THE "Box Settings" GEAR PANEL the way MT4 will draw it — with MT4
completely out of the loop. Same engine as panel-mt4-sim.py, so the panel and
the reference cards are drawn by ONE rasteriser and can be compared pixel for
pixel instead of by memory.

  python tools/sim-gear-panel.py                 -> sim-gear-panel.html
  python tools/sim-gear-panel.py out.html        -> that file
  python tools/sim-gear-panel.py out.html --side -> panel beside a reference card

P-DRAW-90 (2026-09-29) — THE CONTENT IS PARSED, NOT TRANSCRIBED.
The first cut of this proof RE-TYPED every tab's block list by hand and it went
stale within a day: the Style tab still read "Half box / Back / Line / Reset
layout" after the panel grew LAYER, its SHAPE rows became "50 % line / Extend
right / Lock / Behind candles", and one row painted `gl_filter_m.bmp` — a raster
that exists in NO commit of this repo, so the proof drew a hole where the panel
draws `bk_fill_on.bmp`. Every number in here is now READ OUT OF THE SOURCE that
ships it, in the same spirit as the geometry:

  B) the tab's block list, row labels, row faces and guards come from
     DrawStripGearContent / DrawStripSwitchName / DrawStripSlotText /
     DrawStripGearRowText / DrawStripGearRowRes / DrawStripIconRes in
     Biotak/DrawStrip.mqh, and the slot caps from DrawToolbar's DrawKindCaps;
  A) the seats (pad, row pitch, head, foot, tab metrics) from DrawStrip.mqh's
     DSTRIP_* defines, checked against BiotakPanels.mqh's PNL_* by audit().

Anything the walker does not model is listed in `L["unmodelled"]` and printed,
so a future edit to the content shows up as a REPORTED gap instead of a proof
that quietly keeps painting yesterday's panel.

Usage notes: `SIM_TAB` picks the tab for the standalone render (default 3 = Row);
`SIM_KIND` picks the demo drawing kind (default DK_RECT — a Box, the kind whose
caps cover the widest block set short of the text family).
"""

import os
import re
import sys
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
# TH3_ROOT: read the same surface from another tree (tools/before-after.py).
ROOT = os.environ.get("TH3_ROOT") or os.path.dirname(HERE)

# the recovered engine (MT4's own draw model, card proven)
_spec = importlib.util.spec_from_file_location("mt4sim", os.path.join(HERE, "legacy", "panel-mt4-sim.py"))
mt4 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mt4)

Canvas = mt4.Canvas
D = mt4.D
PT = mt4.PT
ACCENT = "gold"
ANAME = "gold"

DRAWSTRIP = os.path.join(ROOT, "Biotak", "DrawStrip.mqh")
DRAWTOOL = os.path.join(ROOT, "Biotak", "DrawToolbar.mqh")


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


DS_TEXT = "\n".join(t[2] for t in mql_unit_lines(DRAWSTRIP))
DT_TEXT = "\n".join(t[2] for t in mql_unit_lines(DRAWTOOL))

# ── the panel's own constants, spelled from Biotak/DrawStrip.mqh ───────────────
GEAR_W   = 312      # DSTRIP_GEAR_W
GEAR_W2  = 624      # DSTRIP_GEAR_W2
PAD      = 16       # DSTRIP_GEAR_PAD
HEAD_H   = 56       # DSTRIP_GEAR_HEAD_H
ROW_H    = 42       # DSTRIP_GEAR_ROW_H
TB_H     = 7        # DSTRIP_GEAR_TB_H
HR_H     = 5        # DSTRIP_GEAR_HR_H
FOOT_H   = 48       # DSTRIP_GEAR_FOOT_H (card PNL_FOOT_H=48)
AIR      = 0        # DSTRIP_GEAR_AIR (retired 6, see P-DRAW-78b)
ROW_GAP  = 10       # DSTRIP_ROW_GAP
CAP_DX   = 14       # DSTRIP_GEAR_CAP_DX: the caption's x inside the cell
CAP_X    = PAD + CAP_DX   # DSTRIP_GEAR_CAP_X — the one owner of that seat
LBL_PT   = 9        # DSTRIP_GEAR_LBL_PT
CHIP_Y   = 10       # DSTRIP_CARD_CHIP_Y
LBL_Y    = 14       # DSTRIP_CARD_LBL_Y
SEC_CNT_W = 24      # DSTRIP_SEC_CNT_W
EDIT_H    = 22      # DSTRIP_GEAR_EDIT_H
FOOT_BW  = 72       # DSTRIP_GEAR_FOOT_BW
FOOT_N   = 3        # DSTRIP_GEAR_FOOT_N (P-DRAW-90: Reset | All · Copy)
FOOT_GLYPH_ADV = 20  # DSTRIP_GEAR_FOOT_GLYPH_ADV: the ring plus its gap (P-DRAW-107)
FOOT_GAP = 8
FOOT_PAD = 8        # card PNL_BTN_PAD
MARK_VIS = 30
MARK_Y   = 13
MARK_PAD = 7
GLYPH    = 15
XBTN     = 26
MARK_Y_OFF = 6

INK    = "rgba(243,246,251,1)"
MUTED  = "rgba(140,150,166,1)"
LABEL  = "rgba(203,212,226,1)"
ACCENT_C = "rgba(255,194,71,1)"
ACCENT2 = "rgba(255,138,0,1)"      # BIO_CLR_ACCENT2
AINK = "rgba(26,18,6,1)"           # BIO_CLR_ACCENT_INK
FOOTBG = "rgba(18,22,29,1)"
LINE_C = "rgba(34,40,50,1)"
FIELD  = "rgba(24,29,39,1)"
FIELD_BD = "rgba(51,60,76,1)"
CARD_C = "rgba(29,34,44,1)"
VER_BG = "rgba(62,55,49,1)"
VER_BD = "rgba(94,82,56,1)"

Z_CARD, Z_TOPBAR, Z_BAND, Z_SEP, Z_HAIR = 1480, 1481, 1486, 1490, 1495
Z_BASE, Z_SKIN, Z_CHIP, Z_INK, Z_TEXT = 1500, 1501, 1502, 1503, 1520

# ── the demo kind. DK_RECT's caps cover every block the four tabs build. ──────
DEMO_KIND = os.environ.get("SIM_KIND", "DK_RECT")
DEMO_KIND_NAME = {"DK_RECT": "Rectangle", "DK_TRIANGLE": "Triangle",
                  "DK_ELLIPSE": "Ellipse", "DK_CHANNEL": "Channel",
                  "DK_LINE": "Trend line", "DK_FIBO": "Fibonacci",
                  "DK_TEXT": "Text", "DK_ARROW": "Arrow"}.get(DEMO_KIND, "Rectangle")
# the values the demo drawing wears (one state, named, so the render is stable)
DEMO_LEVELS = 7          # DrawStripGearLevelCount() on the held fibo
DEMO_PRESETS = ["Scalp", "Swing"]      # DrawPresetName(k, i) != ""
DEMO_STATE = {}          # slot -> 0/1 as DrawSlotRead returns it
#── P-DRAW-117: the demo's OWN look. The FORMAT of each line is the MQL's
#── (`DrawStripGearHeadSub` / `DrawStripGearGroupDigest`); the VALUES are this
#── render's demo drawing, which is what a mirror may choose. One owner here, so
#── the head and the group rows cannot disagree about the drawing they describe.
DEMO_HEX = "#FFAB00"
DEMO_WIDTH = 2
DEMO_STYLE = "Solid"
DEMO_FILL = 1
DEMO_TONE = 50
DEMO_CELLS = 6
DG_PAD = 12              # DSTRIP_GEAR_DG_PAD: the digest's inset from the cell's edge
#── P-DRAW-118: the two colours the demo drawing wears (the same pair the head's
#── look line and the group digests state), and the rim a swatch wears when it is
#── NOT the current one (`BioSwatchBorder(c, BIO_CLR_CARD)` in the MQL).
DEMO_RGB = (255, 171, 0)
DEMO_FILL_RGB = (0, 128, 0)
SWATCH_BD = "rgba(51,60,76,1)"
#── P-DRAW-118 (2026-10-01): the COLOUR ROLE ROW — the cards' own quick row. The
#── strip is preview + the palette's first row + the `+` opener, and its count is
#── the CARDS' `PNL_QSW_N` (one number for one row of one palette).
GRG_SWATCH = 0      # DSTRIP_GRG_SWATCH — a colour cell (its colour is in s_dsGGC)
GRG_PREV   = 2      # DSTRIP_GRG_PREV — the role's own colour block
GRG_PLUS   = 3      # DSTRIP_GRG_PLUS — the "+" opener
SWQ_N    = 8        # DSTRIP_GEAR_SWQ_N (== PNL_QSW_N)
SWQ_CELL = 24       # DSTRIP_GEAR_SWQ_CELL — ds_swatch24's native canvas
SWQ_GAP  = 4        # DSTRIP_GEAR_SWQ_GAP
SWQ_PREV = 24       # DSTRIP_GEAR_SWQ_PREV
SWQ_PLUS = 22       # DSTRIP_GEAR_SWQ_PLUS


def bio_pal_row0(n):
    """The palette's FIRST ROW — `BioPal(i)` == `BioPickColor(0, i)`, the same
    eight the cards' quick row applies (P-DRAW-24). Parsed, never typed: the table
    is `ConstantsAndEnums.mqh`'s `BioPickColor`, and a retuned palette must move
    this render with it."""
    path = os.path.join(ROOT, "Biotak", "ConstantsAndEnums.mqh")
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    body = text[text.index("color BioPickColor") :]
    body = body[: body.index("};")]
    out = []
    for m in re.finditer(r"C'(\d+),(\d+),(\d+)'|BIO_CLR_BRAND", body):
        out.append((255, 171, 0) if not m.group(1)
                   else (int(m.group(1)), int(m.group(2)), int(m.group(3))))
    return out[:n]


SWATCHES = bio_pal_row0(SWQ_N)
assert len(SWATCHES) == SWQ_N, "BioPickColor parsed short — the palette row moved"


def rgb(c):
    return "rgb(%d,%d,%d)" % c


def demo_look_line():
    """DrawStripGearHeadSub() for the demo drawing: hex · width · style · tone."""
    line = DEMO_HEX
    if 1 <= DEMO_WIDTH <= 5:
        line += " \u00b7 %dpx" % DEMO_WIDTH
    line += " \u00b7 " + DEMO_STYLE
    if DEMO_FILL >= 0.5:
        line += " \u00b7 %d%%" % DEMO_TONE
    return line


def digest_of(gid):
    """DrawStripGearGroupDigest()'s own lines, for the demo drawing."""
    if gid == "DSTRIP_GEAR_PAINT":
        return DEMO_HEX if DEMO_FILL < 0.5 else (DEMO_HEX + " \u00b7 %d%%" % DEMO_TONE)
    if gid == "DSTRIP_GEAR_STYLE":
        return "%dpx \u00b7 %s" % (DEMO_WIDTH, DEMO_STYLE)
    if gid == "DSTRIP_GEAR_LEVELS":
        return "%d levels" % DEMO_LEVELS
    if gid == "DSTRIP_GEAR_MARK":
        return "10pt" if DEMO_KIND == "DK_TEXT" else "glyph 3"
    if gid == "DSTRIP_GEAR_TPL":
        return DEMO_PRESETS[0] if DEMO_PRESETS else "none"
    return "%d cells" % DEMO_CELLS


# ════════════════════════════════════════════════════════════════════════════
# A. THE SOURCE READERS — every table below is parsed, never typed.
# ════════════════════════════════════════════════════════════════════════════
def _strip_line_comments(text):
    """Drop `// …` that is not inside a string literal (panel-mt4-sim's rule)."""
    out = []
    for line in text.split("\n"):
        q, cut = False, -1
        i = 0
        while i < len(line) - 1:
            ch = line[i]
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                q = not q
            elif not q and ch == "/" and line[i + 1] == "/":
                cut = i
                break
            i += 1
        out.append(line[:cut] if cut >= 0 else line)
    return "\n".join(out)


DS = _strip_line_comments(DS_TEXT)
DT = _strip_line_comments(DT_TEXT)
U8 = lambda s: s.encode("utf-8", "replace").decode("utf-8")


def _fn_body(text, sig_re):
    """The brace-balanced body of the first function matching sig_re."""
    m = re.search(sig_re, text)
    if not m:
        return ""
    ob = text.index("{", m.end() - 1)
    depth = 0
    for i in range(ob, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[ob + 1:i]
    return ""


def _safe_eval(expr):
    """a bitmask expression (`1 << 3 | 8`) — digits and operators only."""
    return int(eval(expr, {"__builtins__": {}}, {}))


def parse_defines(text, prefix):
    out = {}
    for m in re.finditer(r"#define\s+(%s\w*)\s+(-?\d+)\s*$" % prefix, text, re.M):
        out[m.group(1)] = int(m.group(2))
    return out


def parse_slot_ids():
    """DRAW_SLOT_* from DrawToolbar.mqh (the one owner of the slot numbers)."""
    ids = parse_defines(DT, "DRAW_SLOT_")
    by_num = {v: k[len("DRAW_SLOT_"):] for k, v in ids.items()}
    return ids, by_num


SLOT, SLOT_NAME = parse_slot_ids()


# ── P-BUILD-08: the version chip's text is the SOURCE HASH, not a typed "T2" ──
# The chip used to be the sim's own literal `ver = "T2"` while the MQL read
# TH3_BUILD_TAG — two typed strings that could drift apart and then both lie about
# which build is on screen. The value is now READ from the generated header the
# MQL itself compiles (Biotak/BuildHash.mqh), and a missing one is a hard stop: a
# proof that cannot name the stamp must not draw a plausible one.
BUILDHASH = os.path.join(ROOT, "Biotak", "BuildHash.mqh")


def parse_build_hash():
    try:
        text = open(BUILDHASH, encoding="utf-8-sig", errors="replace").read()
    except OSError:
        raise SystemExit(
            "sim-gear-panel: %s is missing - run `node tools/gen-build-hash.js`" % BUILDHASH
        )
    vals = dict(re.findall(r'#define\s+(TH3_SRC_\w+)\s+"([^"]*)"', text))
    for k in ("TH3_SRC_HASH", "TH3_SRC_SHORT"):
        if k not in vals:
            raise SystemExit("sim-gear-panel: %s not defined in %s" % (k, BUILDHASH))
    return vals["TH3_SRC_HASH"], vals["TH3_SRC_SHORT"]


SRC_HASH, SRC_SHORT = parse_build_hash()


def case_returns(body):
    """{DK_x: "expression"} out of a switch body, FALL-THROUGH LABELS INCLUDED.

    `case DK_HLINE:` stands alone on its line and the `return` belongs to the
    `case DK_VLINE:` under it — the two labels are the SAME answer. A regex that
    demands `return` on the label's own line reads HLINE as no-match, i.e. as a
    kind with ZERO caps, and every reader of it then draws an empty row for a
    kind that really has five controls (P-DRAW proof bug, 2026-09-29: HLINE,
    FIBO and TRIANGLE came out with 0 / 1 cells).
    """
    out, pending = {}, []
    for chunk in re.split(r"\bcase\s+", body)[1:]:
        m = re.match(r"(DK_\w+)\s*:", chunk)
        if not m:
            continue
        pending.append(m.group(1))
        r = re.search(r"return\s+([^;]+);", chunk)
        if r:
            for k in pending:
                out[k] = r.group(1)
            pending = []
    return out


def parse_kind_caps(kind):
    """DrawKindCaps(kind) -> set of slot ids, from DRAW_CAP_* and the switch."""
    caps = {n: (1 << v) for n, v in SLOT.items()}
    for m in re.finditer(r"#define\s+(DRAW_CAP_\w+)\s+\(?(.*?)\)?\s*$", DT, re.M):
        expr = m.group(2).strip()
        expr = re.sub(r"\bDRAW_CAP_\w+\b", lambda mm: str(caps.get(mm.group(0), 0)), expr)
        expr = re.sub(r"\bDRAW_SLOT_\w+\b", lambda mm: str(SLOT.get(mm.group(0), 0)), expr)
        expr = re.sub(r"\s+", " ", expr)
        # the shift (`1 << DRAW_SLOT_X`) is part of the expression — `<` too
        if re.fullmatch(r"[\d\s|()<>]+", expr):
            caps[m.group(1)] = _safe_eval(expr)   # keyed by the MACRO name
    body = _fn_body(DT, r"int\s+DrawKindCaps\s*\([^)]*\)")
    mask = 0
    expr = case_returns(body).get(kind, "")
    if not expr:
        return set()
    # every table is keyed by the FULL macro name, so the substitution reads
    # group(0) — `mm.group(1)` is the bare suffix and resolved to 0 for all of them.
    expr = re.sub(r"\bDRAW_CAP_\w+\b", lambda mm: str(caps.get(mm.group(0), 0)), expr)
    expr = re.sub(r"\bDRAW_SLOT_\w+\b", lambda mm: str(SLOT.get(mm.group(0), 0)), expr)
    # the case expression spans lines and may end on the joining `|`; eval()
    # cannot see a `|` at end-of-line, so the whole expression is flattened.
    expr = re.sub(r"[\s|]+$", "", re.sub(r"^[\s|]+", "", expr))
    expr = re.sub(r"\s+", " ", expr)
    if not re.fullmatch(r"[\d\s|()<>]+", expr):
        return set()
    mask = _safe_eval(expr)
    return {v for v in SLOT.values() if mask & (1 << v)}


CAPS = parse_kind_caps(DEMO_KIND)
DRAW_SLOT_N = SLOT.get("DRAW_SLOT_N", 13)


def _sid(bare):
    """a bare suffix from a source regex -> the slot's number (-1 if unknown)."""
    return SLOT.get("DRAW_SLOT_" + bare, -1)


def slot_of(a):
    """A row's argument as the slot it names: `DRAW_SLOT_FILL` -> 3, `"4"` -> 4.

    P-DRAW-117: the walker reads a row's kind and its argument out of the source's
    own call, and the source spells the argument as a SLOT SYMBOL as often as it
    spells it as a number (`DrawStripGearRow(1, DRAW_SLOT_FILL, y)`). A mirror that
    only understood digits answered `-1` for every such row and drew a label-less
    band — which is what the first render of the accordion showed.
    """
    if a is None:
        return -1
    a = a.strip()
    if a.isdigit():
        return int(a)
    return SLOT.get(a, -1)


def parse_switch_names():
    """DrawStripSwitchName -> {slot: label} (the row labels for kind-1 rows)."""
    body = _fn_body(DS, r"string\s+DrawStripSwitchName\s*\([^)]*\)")
    out = {}
    for m in re.finditer(r"if\s*\(\s*slot\s*==\s*DRAW_SLOT_(\w+)\s*\)\s*return\s*\"([^\"]*)\"", body):
        out[_sid(m.group(1))] = U8(m.group(2))
    return out


SWITCH_NAME = parse_switch_names()


def parse_icon_res():
    """DrawStripIconRes -> {slot: raster name (the OFF/plain state)}."""
    body = _fn_body(DS, r"string\s+DrawStripIconRes\s*\([^)]*\)")
    out = {}
    for m in re.finditer(r"if\s*\(\s*slot\s*==\s*DRAW_SLOT_(\w+)\s*\)\s*\n?\s*return\s+\"([^\"]*)\"",
                         body):
        out[_sid(m.group(1))] = m.group(2).split("\\\\")[-1]
    # the state-carrying branches (the `?( … : … )` pair) take their OFF arm
    for m in re.finditer(r"if\s*\(\s*slot\s*==\s*DRAW_SLOT_(\w+)\s*\)\s*\n?\s*return\s+\(.*?\?\s*\"([^\"]*)\""
                         r"\s*:\s*\"([^\"]*)\"", body, re.S):
        out[_sid(m.group(1))] = m.group(3).split("\\\\")[-1]
    # the value-indexed families (bk_w<n> / bk_style<n> / bk_ray<n>) — demo index
    for m in re.finditer(r"if\s*\(\s*slot\s*==\s*DRAW_SLOT_(\w+)\s*\)\s*\n?\s*\{", body):
        blk = body[m.end():m.end() + 400]
        stem = re.search(r'return\s+"::Files\\\\\\\\Icons\\\\\\\\\\\\([A-Za-z_]+)"\s*\+', blk)
        if stem:
            out[_sid(m.group(1))] = stem.group(1) + "0.bmp"
    return out


ICON_RES = parse_icon_res()
# the demo's ON states — the two the strip shows lit in this frame
DEMO_ON = {"FILL": True, "BACK": False, "LOCK": False, "BOXHALF": False, "EXTEND": False}
ON_RES = {"FILL": "bk_fill_on.bmp", "BOXHALF": "bk_half_on.bmp", "EXTEND": "bk_ext_on.bmp",
          "LOCK": "bk_lock_on_g.bmp", "BACK": "bk_back_on.bmp"}


def parse_slot_text():
    """DrawStripSlotText -> {slot: caption} for the value-dependent rows the Row
    tab draws (kind 6): a colour, a width, a style — the demo's own values."""
    body = _fn_body(DS, r"string\s+DrawStripSlotText\s*\(")
    out = {}
    for m in re.finditer(r"if\s*\(\s*slot\s*==\s*DRAW_SLOT_(\w+)\s*\)\s*return\s*\"([^\"]*)\"", body):
        out[_sid(m.group(1))] = m.group(2)
    return out


DEMO_SLOT_TEXT = {
    _sid("COLOR"): "#FFAB00", _sid("WIDTH"): "2px", _sid("STYLE"): "Solid",
    _sid("FILL"): "Interior on", _sid("FILLCLR"): "#FFAB00 50%",
    _sid("BOXHALF"): "50 % line off", _sid("EXTEND"): "Extend right off",
    _sid("LOCK"): "Lock off", _sid("BACK"): "Layer: front", _sid("RAY"): "Segment"}


def parse_row_text():
    """DrawStripGearRowText -> per-kind label rules, as literals."""
    body = _fn_body(DS, r"string\s+DrawStripGearRowText\s*\(")
    out = {}
    m = re.search(r"if\s*\(\s*kind\s*==\s*3\s*\)\s*return\s*\"([^\"]*)\"", body)
    if m:
        out[3] = U8(m.group(1))
    for m in re.finditer(r"if\s*\(\s*arg\s*==\s*(\d+)\s*\)\s*return\s*\"([^\"]*)\"", body):
        out["L5_%s" % m.group(1)] = U8(m.group(2))
    out["L5_else"] = "Reset layout"
    return out


ROW_TEXT = parse_row_text()


# ════════════════════════════════════════════════════════════════════════════
# B. THE CONTENT WALKER — DrawStripGearContent's own statements, in order.
# ════════════════════════════════════════════════════════════════════════════
# ── P-DRAW-117 (2026-10-01): THE GROUP REGISTRY, PARSED, NOT RETYPED ─────────
# The panel's nav is a list of ROWS now — `DrawStripGearGroups` fills `s_dsGearGrp`
# and every reader (the walk, the paint, the hit test, the tool) asks that one
# owner. This mirror asks it too: the ids in the source's own order, each with the
# guard the source wraps it in (`DrawKindHasLevels(s_dsKind)` for the levels
# family, a kind comparison for the marks), evaluated for the demo kind the same
# way the MQL's own `if` does.
def parse_kind_has_levels():
    """The level family, out of the OWNER of the answer — `DrawKindHasLevels` lives
    in the toolbar's own unit (DrawToolbar.mqh -> Toolbar_A.mqh), which this file
    already reads as `DT` for exactly this reason: a face read out of the wrong
    unit is an empty answer, and an empty answer silently offers a box a LEVELS
    group it can never have.
    """
    body = _fn_body(DT, r"bool\s+DrawKindHasLevels\s*\(")
    return set(re.findall(r"k\s*==\s*(DK_\w+)", body))


LEVEL_KINDS = parse_kind_has_levels()


def parse_group_registry():
    """[(id, guard)] in the source's own order; guard in ('levels', 'mark', None).

    The guard sits BEFORE the write (`if(DrawKindHasLevels(s_dsKind)) { s_dsGearGrp…`),
    so it is read from the same statement the id is: splitting on the assignment
    alone would drop it and offer a RECT a levels group it can never have.
    """
    body = _fn_body(DS, r"int\s+DrawStripGearGroups\s*\(")
    out = []
    prev = 0
    for m in re.finditer(r"s_dsGearGrp\[n \+ 1\] = (DSTRIP_GEAR_\w+); n\+\+;", body):
        head = body[prev:m.start()]
        guard = None
        if "DrawKindHasLevels" in head:
            guard = "levels"
        elif "DK_TEXT" in head or "DK_ARROW" in head:
            guard = "mark"
        out.append((m.group(1), guard))
        prev = m.end()
    return out


REGISTRY = parse_group_registry()


def group_ids():
    out = []
    for gid, guard in REGISTRY:
        if guard == "levels" and DEMO_KIND not in LEVEL_KINDS:
            continue
        if guard == "mark" and DEMO_KIND not in ("DK_TEXT", "DK_ARROW"):
            continue
        out.append(gid)
    return out


GROUPS = group_ids()


def parse_group_faces(fn):
    """DrawStripGearGroupText / DrawStripGearGroupRes -> {id: what it returns}.

    The MARK group's answer is a ternary over the kind, so both arms are read and
    the demo kind picks one — a transcribed name here would be a second table
    beside the source's own, which is the whole defect this file exists to avoid.
    """
    body = _fn_body(DS, r"string\s+%s\s*\(" % fn)
    out = {}
    for m in re.finditer(r"if\s*\(\s*gid\s*==\s*(DSTRIP_GEAR_\w+)\s*\)\s*return\s+"
                         r"\(s_dsKind == DK_ARROW \? \"([^\"]*)\" : \"([^\"]*)\"\)", body):
        out[m.group(1)] = m.group(2) if DEMO_KIND == "DK_ARROW" else m.group(3)
    for m in re.finditer(r"if\s*\(\s*gid\s*==\s*(DSTRIP_GEAR_\w+)\s*\)\s*return\s+\"([^\"]*)\"",
                         body):
        out[m.group(1)] = m.group(2)
    return out


GROUP_TEXT = parse_group_faces("DrawStripGearGroupText")
GROUP_RES = {g: r.split("\\\\")[-1] for g, r in parse_group_faces("DrawStripGearGroupRes").items()}

# the demo kind's own list of groups, by name (the source's words, in its order)
TABS = [GROUP_TEXT[g] for g in GROUPS]
GROUP_AT = {n: g for n, g in zip(TABS, GROUPS)}
TAB_ACTIVE = len(TABS) - 1             # the screenshot's state (the last group)
GLIST_MAX = int((re.search(r"#define\s+DSTRIP_GLIST_MAX\s+(\d+)", DS) or [0, "16"])[1])
GRK_GROUP = int((re.search(r"#define\s+DSTRIP_GRK_GROUP\s+(\d+)", DS) or [0, "9"])[1])
LVLBLK = int((re.search(r"#define\s+DSTRIP_GEAR_LVLBLK\s+(\d+)", DS) or [0, "5"])[1])

CONTENT = _fn_body(DS, r"void\s+DrawStripGearContent\s*\(")


def _branches():
    """`if(gOpen == X)` … `else if(gOpen == Y)` -> {X: body}.

    P-DRAW-117: the accordion asks the open group through `gOpen` (the same value,
    with `-1` for a folded panel), and this mirror follows the source's own
    selector rather than a name it carries itself — `s_dsGear` is still accepted so
    a reader can see which spelling the chain is on.
    """
    marks = list(re.finditer(r"(?:else\s+)?if\s*\(\s*(?:gOpen|s_dsGear)\s*==\s*(DSTRIP_GEAR_\w+)\s*\)", CONTENT))
    out = {}
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(CONTENT)
        seg = CONTENT[m.end():end]
        ob = seg.index("{")
        depth, close = 0, len(seg)
        for j in range(ob, len(seg)):
            if seg[j] == "{":
                depth += 1
            elif seg[j] == "}":
                depth -= 1
                if depth == 0:
                    close = j
                    break
        out[m.group(1)] = seg[ob + 1:close]
    return out


BRANCHES = _branches()


def _blank_block(text, start):
    """Blank `{ … }` from `start` (inclusive of the brace), returning the new text."""
    ob = text.index("{", start)
    depth = 0
    for i in range(ob, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[:start] + " " * (i + 1 - start) + text[i + 1:]
    return text


def _apply_guards(text):
    """Blank every guard whose DrawSlotAvailable() is false for the demo kind.

    Two forms exist in the source: a braced block (`if(...) { ... }`) and the
    single following statement (`if(...) DrawStripGearRow(...);`). Both are
    handled, and a guard on a slot the kind OWNS keeps its body verbatim.
    """
    out, unknown = text, []
    while True:
        m = re.search(r"if\s*\(\s*(!?)DrawSlotAvailable\s*\(\s*\w+\s*,\s*DRAW_SLOT_(\w+)\s*\)\s*\)", out)
        if not m:
            return out, unknown
        want = (_sid(m.group(2)) in CAPS)
        if m.group(1) == "!":
            want = not want
        if want:
            # the guard is true: strip the guard, keep the body
            out = out[:m.start()] + out[m.end():]
            # ...and repair the statement shape it wrapped
            out = re.sub(r"^\s*\)\s*", "", out[m.start():], count=1) if False else out
            continue
        brace = out.find("{", m.end())
        semi = out.find(";", m.end())
        if brace >= 0 and (semi < 0 or brace < semi):
            out = _blank_block(out, m.start())
        else:
            out = out[:m.start()] + " " * (semi + 1 - m.start()) + out[semi + 1:]


def _expand_loops(text, unmodelled, headers_before=0):
    """DrawStripGearContent's four `for` shapes -> plain DrawStripGearRow calls.

    The loops are BOUND in the source by a count this proof can read: the kind's
    own slot set (`s < DRAW_SLOT_N`), DrawStripGlyphCount(), the held drawing's
    level count (demo) and the preset list (demo). A loop whose bound is not one
    of those is left alone and REPORTED — a proof may not guess a row count.

    P-DRAW-117: the LEVEL list's bound is `i < nl && i < room`, and `room` is
    `DSTRIP_GLIST_MAX - 2 - s_dsGRN` — the group headers ride the same row array
    as the letters now, so the seats they spend are read out of the source
    (`headers_before`) and subtracted here. A proof that ignored them would draw
    more level rows than the panel can build.
    """
    out = text
    while True:
        m = re.search(r"for\s*\(\s*int\s+(\w+)\s*=\s*0\s*;\s*\1\s*<\s*([^;]+);", out)
        if not m:
            return out
        var, cond = m.group(1), m.group(2).strip()
        # P-DRAW-117: a loop with a SINGLE-STATEMENT body (`for(…) if(…);`) has no
        # brace to index — the old `out.index("{", …)` found the FUNCTION's own brace
        # and swallowed everything to it. Reported, never guessed: the Mark group's
        # glyph list is that shape, and a kind the demo does not walk must show up as
        # an UNMODELLED statement, not as a crash or as a silently wrong row count.
        ob = out.find("{", m.end())
        if ob < 0 or (0 <= out.find(";", m.end()) < ob):
            unmodelled.append("for(%s < %s) { one statement }" % (var, cond))
            return out
        depth, close = 0, len(out)
        for i in range(ob, len(out)):
            if out[i] == "{":
                depth += 1
            elif out[i] == "}":
                depth -= 1
                if depth == 0:
                    close = i
                    break
        body = out[ob + 1:close]
        # the ARGUMENT, not the argument and the layout cursor: `a` used to swallow
        # `, y`, so every generated row carried the cursor in its own argument and its
        # label and its face resolved to -1 (see slot_of).
        rm = re.search(r"DrawStripGearRow\s*\(\s*([^,)]+)\s*,\s*([^,)]+)", body)
        n, kind, arg = None, None, None
        if rm:
            kind, arg = rm.group(1).strip(), rm.group(2).strip()
            if "DRAW_SLOT_N" in cond:
                n = len([s for s in CAPS if s != _sid("MORE")])
            elif "DrawStripGlyphCount" in cond:
                n = 8                       # DrawStripGlyphCount() == 8
            elif "nl" in cond:
                room = GLIST_MAX - 2 - headers_before   # the source's own `room`
                if room < 0:
                    room = 0
                n = min(DEMO_LEVELS, room)
            elif "DRAW_PRESET_MAX" in cond:
                n = len(DEMO_PRESETS)
        if n is None or kind is None:
            unmodelled.append("for(%s < %s) { … }" % (var, cond))
            return out
        gen = []
        for k in range(n):
            a = arg.replace(var + ")", str(k) + ")")
            a = re.sub(r"\b%s\b" % var, str(k), a)
            if a.strip() in ("s", "i", "g"):
                a = str(k)
            gen.append("DrawStripGearRow(%s, %s);" % (kind, a))
        out = out[:m.start()] + " ".join(gen) + out[close + 1:]


def walk(gid, headers_before=0):
    """DrawStripGearContent's body for ONE group -> [(kind, name, y, extra), …].

    `gid` is a DSTRIP_GEAR_* id and `headers_before` is how many group rows stand
    above this group's body (they spend seats of the same row array the level list
    rides — see `_expand_loops`).
    """
    unmodelled = []
    branch = _expand_loops(BRANCHES.get(gid, ""), unmodelled, headers_before)
    body, ung = _apply_guards(branch)
    unmodelled += ung
    blocks, y = [], 0
    # the calls, in source order, with the y advance each one really makes
    pat = re.compile(
        r'DrawStripGearSection\s*\(\s*"([^"]+)"'
        r'|DrawStripGearCaptionIn\s*\(\s*"([^"]+)"'
        r'|DrawStripGearGridChips\s*\(\s*(DRAW_SLOT_\w+)\s*,\s*([^)]+)\)'
        r'|DrawStripGearRow\s*\(\s*([^,)]+)\s*,\s*([^,)]+)'
        r'|DrawStripGearQuickRow\s*\(\s*(DRAW_SLOT_\w+)\s*,\s*y\s*\)'
        r'|DrawStripGearGridStamp\s*\('
        r'|s_dsGearEditY\s*\[\s*(\d+)\s*\]\s*=\s*y'
        r'|for\s*\(\s*int\s+\w+\s*=\s*0\s*;\s*\w+\s*<\s*(nl|DrawPresetName|DrawStripGlyphCount|DRAW_SLOT_N|DRAW_PRESET_MAX)'
        r'|y\s*\+=\s*DSTRIP_GEAR_ROW_H\s*;', re.S)
    pend_grid = None
    in_loop = None
    for m in pat.finditer(body):
        tok = m.group(0)
        if m.group(1) is not None:
            blocks.append(["section", U8(m.group(1)), y, None])
            y += ROW_H
        elif m.group(2) is not None:
            blocks.append(["caption", U8(m.group(2)), y, None])
        elif m.group(3) is not None:
            slot = m.group(3)
            cnt = m.group(4).strip()
            n = int(cnt) if cnt.isdigit() else {"DrawStripFontCount()": 6,
                                                "DrawStripGlyphCount()": 8}.get(cnt, 0)
            pend_grid = (slot, n)
        elif m.group(5) is not None:
            if m.group(5).strip().startswith("int i") or m.group(5).strip().isdigit():
                blocks.append(["row", None, y, (m.group(5).strip(), m.group(6).strip())])
                y += ROW_H
        elif tok.startswith("DrawStripGearQuickRow"):
            # P-DRAW-118: the colour ROLE row — preview + the palette's row + the `+`,
            # all of them grid cells in the MQL (`DrawStripGearQuickRow` is the only
            # writer of `s_dsGG*` outside the chip helper), placed as ONE row.
            blocks.append(["swq", m.group(7), y, None])
            y += ROW_H
        elif tok.startswith("DrawStripGearGridStamp"):
            if pend_grid:
                slot, n = pend_grid
                cols = (GEAR_W - 2 * PAD + 8) // (48 + 8)      # DSTRIP_GEAR_CHIP 48
                rows = max(1, (n + cols - 1) // cols)
                blocks.append(["grid", slot, y, n])
                y += rows * ROW_H
                pend_grid = None
        elif m.group(8) is not None:
            # the edit seat a caption OWNS (`s_dsGearEditY[0] = y`): its index is the
            # caption block's own, and the paint draws the field on that row.
            for b in reversed(blocks):
                if b[0] == "caption" and b[1] is not None and b[3] is None:
                    b[3] = int(m.group(8))
                    break
        elif tok.startswith("y +="):
            y += ROW_H
    return dict(blocks=blocks, unmodelled=unmodelled, y=y)


# ════════════════════════════════════════════════════════════════════════════
def row_label(kind, arg):
    s = slot_of(arg)
    if kind == str(GRK_GROUP):
        return GROUP_TEXT.get(str(arg).strip(), "")
    if kind == "1":
        return SWITCH_NAME.get(s, DEMO_SLOT_TEXT.get(s, "Interior"))
    if kind == "3":
        return ROW_TEXT.get(3, "Save current look")
    if kind == "5":
        return ROW_TEXT.get("L5_%s" % arg, ROW_TEXT["L5_else"])
    if kind == "7":
        return "New %s wears this look" % DEMO_KIND_NAME
    if kind == "6":
        # the more-cell is the LEVELS seat and the MQL names it (DrawStripGearRowText)
        if str(arg).strip() == "DRAW_SLOT_MORE":
            return "Levels"
        return DEMO_SLOT_TEXT.get(s, "")
    return ""


def row_res(kind, arg):
    if kind == str(GRK_GROUP):
        return GROUP_RES.get(str(arg).strip(), "")
    if kind == "1":
        s = slot_of(arg)
        nm = SLOT_NAME.get(s, "")
        if nm in DEMO_ON and DEMO_ON[nm]:
            return ON_RES.get(nm, ICON_RES.get(s, ""))
        return ICON_RES.get(s, "")
    return ""


# ── the seats audit: the panel's numbers against the cards' own ──────────────
def cap_w():
    """DrawStripGearCapW() — the caption's own seat PLUS the widest label PLUS the
    row gap (its `DSTRIP_GEAR_CAP_X + w + DSTRIP_ROW_GAP`, clamped to the pad).

    The `CAP_X` term was missing, so every caption/field pair this mirror drew was
    ~30px left of the MQL's own seats and the field's width ~30px wide: MEASURED
    here, `COLOR` at `pxr` and its field at `pxr + 56` against the source's caption
    at `+30` and field at `+86` (DrawStripGearCapW / DrawStrip_GearA). The gate's
    hit-box count could not see it — both shapes are non-empty — which is exactly
    why the seat is MIRRORED here rather than approximated.
    """
    w = max(mt4.text_w("COLOR", LBL_PT), mt4.text_w("FILL", LBL_PT))
    return max(PAD, CAP_X + w + ROW_GAP)


GEAR_COL = 312               # DSTRIP_GEAR_COL
WIDE_ROWS = 10               # DSTRIP_GEAR_WIDE_ROWS
GRID_GAP = 8                 # DSTRIP_GEAR_GRID_GAP
CHIP_W = 48                  # DSTRIP_GEAR_CHIP
CHIP_H = 32                  # DSTRIP_GEAR_CHIP_H


def layout(tab=TAB_ACTIVE):
    """DrawStripGearLayout() + DrawStripGearPlace(): the ACCORDION, parsed.

    P-DRAW-117. The body is a column of group ROWS — the headers above the open
    group, that group's own settings, then the headers below it — and:
      * `content_top` is the head's bottom edge (56): the tab band is retired, so
        the plate's arithmetic is `gh = 104 + 42R` and `cardN = R`;
      * a NARROW plate must fit the baked card set (`pnl_card<n>` stops at 10), so
        at most `WIDE_ROWS` rows stay narrow;
      * past that the panel is 624 and splits at the boundary between the BLOCKS it
        built — a group header owns its own settings (the walk registers a block per
        header) and a long level list opens one every LVLBLK rows, so the split can
        land inside the list without ever taking a header from its content
        (`DrawStripGearPlace`'s own rule, and the reason it reads the block map).

    Every height is a DELTA between two blocks' own y — a grid that wraps to two
    rows is two rows here, the way `DrawStripGearGridStamp` advanced the cursor.
    """
    gid = GROUPS[tab]
    heads, tails = GROUPS[:tab + 1], GROUPS[tab + 1:]
    W = walk(gid, tab)
    content_top = HEAD_H
    rows, units = [], []

    def unit(kind, name, y, extra):
        units.append([kind, name, y, extra, 0, 0])
        return units[-1]

    y = 0
    blk = []
    for g in heads:                        # the headers ABOVE the open group
        blk.append(y)
        e = unit("row", GROUP_TEXT[g], y, (str(GRK_GROUP), g, GROUP_RES[g]))
        e[5] = ROW_H                       # a header is one row, like every row
        y += ROW_H
    body_start = y
    cb = W["blocks"]
    for i, (kind, name, by, extra) in enumerate(cb):
        nxt = cb[i + 1][2] if i + 1 < len(cb) else W["y"]
        if kind == "section":
            blk.append(body_start + by)
        elif kind == "row" and name is None:
            kk, aa = extra
            if kk == "4" and aa.isdigit() and int(aa) % LVLBLK == 0:
                blk.append(body_start + by)      # the level list's own sub-blocks
            name = row_label(kk, aa)
            extra = (kk, aa, row_res(kk, aa))
        elif kind == "grid":
            name, extra = extra, (extra,)
        elif kind == "swq":
            # P-DRAW-118: one colour role — the cells are the paint's own, so the row
            # carries its slot and nothing else.
            name, extra = extra, (extra,)
        e = unit(kind, name, body_start + by, extra)
        e[5] = max(ROW_H, nxt - by)              # the block's own height
    y = body_start + W["y"]
    for g in tails:                          # ...and the headers BELOW it
        blk.append(y)
        e = unit("row", GROUP_TEXT[g], y, (str(GRK_GROUP), g, GROUP_RES[g]))
        e[5] = ROW_H
        y += ROW_H
    content_end = y
    w = GEAR_W
    if content_end > WIDE_ROWS * ROW_H:
        split = None
        best = None
        for b in blk[1:]:
            h = max(b, content_end - b)
            if best is None or h < best[1]:
                best = (b, h)
        if best is not None:
            split = best[0]
        if split is not None:
            # DrawStripGearShiftItems: whole blocks move, each column packs from
            # contentTop, and a block keeps its own internal height while it packs.
            hi = {u[2]: u[5] for u in units}
            content_end = 0
            for col in (0, 1):
                items = [u for u in units if (u[2] >= split) == (col == 1)]
                top = 0
                for b in sorted({u[2] for u in items}):
                    for u in [x for x in items if x[2] == b]:
                        u[2], u[4] = top, col
                    top += hi[b]
                content_end = max(content_end, top)
            w = GEAR_W2

    rows = [(k, n, content_top + yy, ex, col) for k, n, yy, ex, col, _h in units]
    end = content_top + content_end
    gh = end + FOOT_H + AIR
    card_n = (gh - 104) // 42
    exact = (gh - 104) % 42 == 0 and 1 <= card_n <= 10
    return dict(top=content_top, end=end, foot_y=end, h=gh, w=w,
                card_n=card_n, exact=exact, blocks=rows, wide=(w == GEAR_W2),
                unmodelled=W["unmodelled"], tab_name=TABS[tab], gid=gid)


def paint(L, notes, tab=TAB_ACTIVE):
    c = Canvas()
    c.origin(0, 0)
    gx, gy = 0, 0
    gh, gw = L["h"], L["w"]

    # ── THE PLATE. DrawStripGearPlate: narrow && exact -> pnl_card{cardN} ──────
    if L["exact"] and gw == GEAR_W:
        c.img("pnl_card%d.bmp" % L["card_n"], gx - 14, gy - 14, gw + 28, gh + 28, Z_CARD)
        notes.append(("plate", "bake pnl_card%d" % L["card_n"], gw + 28, gh + 28))
    else:
        pair_n = L["card_n"] if L["exact"] else (gh - 104 + 41) // 42
        pair_n = max(1, pair_n)
        # P-DRAW-110 (2026-10-01): the body starts at the HEAD's own edge, not at the
        # top cap's height — the cap's 14px pad is spent ABOVE `gy - 14`, so `gy + 70`
        # put the whole body 14px low on the wide tabs. The cards' own composition is
        # the owner (BiotakPanels_Build.mqh:727-737, `PNL_HEAD_H`); the MQL now reads
        # `DSTRIP_GEAR_HEAD_H` the same way.
        c.img("pnl_cardWtop.bmp", gx - 14, gy - 14, gw + 28, 70, Z_CARD)
        for li in range(pair_n):
            c.img("pnl_cardWmid.bmp", gx - 14, gy + HEAD_H + li * ROW_H, gw + 28, ROW_H, Z_CARD)
        c.img("pnl_cardWbot.bmp", gx - 14, gy + HEAD_H + pair_n * ROW_H, gw + 28, 62, Z_CARD)
        notes.append(("plate", "composed W", gw + 28, gh + 28))

    # ── HEADER (DrawStripGearHeadPaint) ───────────────────────────────────────
    hy = gy + 0
    c.img("pnl_topbar%s_%s.bmp" % ("W" if gw > GEAR_W else "", ANAME), gx, hy, gw, TB_H, Z_TOPBAR)
    c.img("pnl_hair%s_%s.bmp" % ("W" if gw > GEAR_W else "", ANAME),
          gx, hy + HEAD_H - HR_H, gw, HR_H, Z_HAIR)
    c.img("pnl_mark_%s.bmp" % ANAME, gx + PAD - MARK_PAD, hy + MARK_Y - MARK_PAD,
          MARK_VIS + 2 * MARK_PAD, MARK_VIS + 2 * MARK_PAD, Z_SKIN)
    c.img("gl_box_i_%s.bmp" % ANAME,
          gx + PAD + (MARK_VIS - GLYPH) // 2, hy + MARK_Y + (MARK_VIS - GLYPH) // 2,
          GLYPH, GLYPH, Z_INK)
    htx = gx + PAD + MARK_VIS + 10
    ver = SRC_SHORT   # P-BUILD-08: DrawStrip_GearB's `TH3_SRC_SHORT`, parsed not typed
    vw = 10 + mt4.text_w(ver, PT["ver"])
    ver_x = gx + gw - 16 - XBTN - 6 - vw
    # P-DRAW-117: line 1 is the panel's title and line 2 is the DRAWING's live look
    # (`DrawStripGearHeadSub`: hex · width · style), not the retired selection count.
    c.text(htx, hy + 12, DEMO_KIND_NAME + " Settings", INK, PT["title"], True, z=Z_TEXT)
    c.text(htx, hy + 35, demo_look_line(), MUTED, PT["sub"], True, z=Z_TEXT)
    c.rect(ver_x, hy + 20, vw, 16, VER_BG, Z_BASE)
    c.text(ver_x + vw / 2, hy + 28, ver, ACCENT_C, PT["ver"], True, "lu", Z_TEXT)
    close_x = gx + gw - PAD - XBTN
    c.rect(close_x, hy + 15, XBTN, XBTN, "rgba(28,34,44,1)", Z_BASE)
    c.img("pnl_xbtn.bmp", close_x - 2, hy + 13, XBTN + 4, XBTN + 4, Z_SKIN)
    c.img("gl_x_%s.bmp" % ANAME, close_x + (XBTN - GLYPH) // 2,
          hy + 15 + (XBTN - GLYPH) // 2, GLYPH, GLYPH, Z_INK)

    # ── NO TAB ROW — the group rows below ARE the nav (P-DRAW-117) ──────────────────────────────────────────

    # ── CONTENT ROWS ─────────────────────────────────────────────────────────
    px = gx + PAD
    # P-DRAW-109 (2026-10-01): ONE COLUMN'S CELL, NOT THE WHOLE BOX. `col_w`
    # (592 on a 624 tab) is the TAB TRACK's width; every row, caption, grid and
    # section inside a column is `DrawStripGearCellW()` — 280 on EVERY tab — and
    # the MQL's own paint reads it (DrawStrip_GearB.mqh:880), its hit test reads
    # it (:461), its content pass reads it (DrawStrip_GearA.mqh:342). MEASURED:
    # with the box, the wide tabs' column-1 switch/chip lands at `pxr + 592 - 40`
    # = 880 for a plate that ends at 638 — 242px off the card, six ops per wide
    # tab (pnl_sw_*, pnl_cntchip), and the chip grid packed `(592+8)//56` = 10 per
    # row where the MQL lays 5. The mirror lied about exactly the two tabs the
    # user was told to look at.
    cw = GEAR_W - 2 * PAD
    for kind, name, y, extra, col in L["blocks"]:
        # P-DRAW-30: the wide pass TRANSLATES whole blocks into the right column
        pxr = px + col * GEAR_COL
        ry = gy + y
        if kind == "section":
            c.img("pnl_secdot_%s.bmp" % ANAME, pxr + PAD - 4, ry + 14, 14, 14, Z_CHIP)
            c.text(pxr + PAD + 14, ry + LBL_Y, name, MUTED, 7, True, z=Z_TEXT)
            lx = pxr + PAD + 14 + mt4.text_w(name, 7) + ROW_GAP
            c.rect(lx, ry + 21, (pxr + cw - 16 - 16) - lx, 1, LINE_C, Z_BASE)
            c.img("pnl_cntchip.bmp", pxr + cw - SEC_CNT_W - 2, ry + 11,
                  SEC_CNT_W + 4, 20, Z_CHIP)
        elif kind == "caption":
            # a caption that shares its row with a field IS the row's label, and it
            # sits on the same seat the row labels do (`DSTRIP_GEAR_CAP_X`).
            c.text(pxr + CAP_X, ry + LBL_Y, name, LABEL, LBL_PT, True, z=Z_TEXT)
            e = extra
            ex = pxr + cap_w()
            c.rect(ex, ry + (ROW_H - EDIT_H) // 2, cw - cap_w(), EDIT_H, FIELD, Z_BASE,
                   border=FIELD_BD)
            if e in (0, 4):
                c.text(ex + 4, ry + (ROW_H - EDIT_H) // 2 + (EDIT_H - mt4.font_px(8)) // 2,
                       "#FFAB00", LABEL, 8, False, "lu", Z_TEXT)
        elif kind == "swq":
            #── P-DRAW-118 (2026-10-01) — THE CARDS' OWN QUICK ROW. The colour this
            #── role holds now, the palette's own first row (`BioPal` = `BioPickColor
            #── (0, i)`, parsed out of ConstantsAndEnums), then the `+` that opens the
            #── board. Every cell is a grid cell in the MQL (DrawStripGearQuickRow),
            #── so the face is the strip's own `ds_swatch24` at its native 24 — the
            #── icon diet's own skin for a colour cell (P-DRAW-33).
            cur = DEMO_RGB if str(name) == "DRAW_SLOT_COLOR" else DEMO_FILL_RGB
            cx0 = pxr + PAD
            cy0 = ry + (ROW_H - SWQ_CELL) // 2
            c.rect(cx0, cy0, SWQ_CELL, SWQ_CELL, rgb(cur), Z_BASE, border=ACCENT_C)
            c.img("ds_swatch24.bmp", cx0, cy0, SWQ_CELL, SWQ_CELL, Z_SKIN)
            sx = cx0 + SWQ_PREV + SWQ_GAP
            for i, sw in enumerate(SWATCHES):
                wx = sx + i * (SWQ_CELL + SWQ_GAP)
                c.rect(wx, cy0, SWQ_CELL, SWQ_CELL, rgb(sw), Z_BASE, border=SWATCH_BD)
                c.img("ds_swatch24.bmp", wx, cy0, SWQ_CELL, SWQ_CELL, Z_SKIN)
            ax = sx + SWQ_N * (SWQ_CELL + SWQ_GAP)
            c.rect(ax, cy0, SWQ_PLUS, SWQ_PLUS, FIELD, Z_BASE, border=FIELD_BD)
            c.text(ax + SWQ_PLUS / 2.0, cy0 + SWQ_PLUS / 2.0, "+", LABEL, 8, True, "lu", Z_TEXT)
        elif kind == "grid":
            # the grid's real cells: DSTRIP_GEAR_CHIP 48 x DSTRIP_GEAR_CHIP_H 32,
            # on the row pitch, the first one carrying the accent (the current value)
            n = int(name)
            cols = max(1, (cw + GRID_GAP) // (CHIP_W + GRID_GAP))
            for i in range(n):
                gxx = pxr + i % cols * (CHIP_W + GRID_GAP)
                gyy = ry + (i // cols) * ROW_H + CHIP_Y
                cur = (i == 1)
                c.rect(gxx, gyy, CHIP_W, CHIP_H, ACCENT_C if cur else FIELD, Z_BASE,
                       border=ACCENT2 if cur else FIELD_BD)
                c.text(gxx + 6, gyy + 10, str(i + 1), LABEL if not cur else AINK,
                       8, True, "lu", Z_TEXT)
        else:
            k, a, res = extra if (extra and len(extra) == 3) else (None, None, "")
            if k == str(GRK_GROUP):
                # P-DRAW-117: A GROUP HEADER — the cards' own chip (gold while THIS
                # group is the open one), the group's icon, its name, and the value it
                # holds right-aligned inside the cell. No switch: a group is not a
                # boolean. The seats are the MQL's own (DrawStrip_GearB.mqh:1005-1030).
                cur = (a == L["gid"])
                c.img("pnl_chip_gold.bmp" if cur else "pnl_chip.bmp",
                      pxr + PAD, ry + CHIP_Y, 22, 22, Z_SKIN)
                if res:
                    c.img(res, pxr + PAD + 1, ry + CHIP_Y + 1, 20, 20, Z_INK)
                c.text(pxr + PAD + 30, ry + LBL_Y, name, INK if cur else LABEL, LBL_PT,
                       True, z=Z_TEXT)
                dg = digest_of(a)
                c.text(pxr + cw - DG_PAD - mt4.text_w(dg, 8), ry + LBL_Y, dg,
                       ACCENT_C if cur else MUTED, 8, True, z=Z_TEXT)
                if cur:
                    c.img("pnl_rail_gold.bmp", pxr, ry, 2, ROW_H, Z_SKIN)
                continue
            # P-DRAW-117: THE LABEL STARTS WHERE THE CHIP ENDS when the row wears one
            # — the MQL's own `PAD + (res == "" ? 0 : 22 + 8)` (DrawStrip_GearB). This
            # mirror drew both at `+PAD`, so every icon row's chip sat ON its word.
            c.text(pxr + PAD + (30 if res else 0), ry + LBL_Y, name, LABEL, LBL_PT,
                   True, z=Z_TEXT)
            if res:
                c.img("pnl_chip.bmp", pxr + PAD, ry + CHIP_Y, 22, 22, Z_SKIN)
                c.img(res, pxr + PAD + 1, ry + CHIP_Y + 1, 20, 20, Z_INK)
            is_sw = (k in ("1", "4", "6"))
            state = "pnl_sw_on_gold.bmp" if (is_sw and DEMO_STATE.get(a, k == "1")) \
                else ("pnl_sw_off.bmp" if is_sw else "gl_nav_m.bmp")
            c.img(state, pxr + cw - 40 if is_sw else pxr + cw - 18,
                  ry + CHIP_Y, 40 if is_sw else 15, 22, 1506)

    # ── FOOT (DrawStripGearPaint) ────────────────────────────────────────────
    fy0 = gy + L["foot_y"]
    # P-DRAW-90: the foot's own grid — `Reset` at the content's left edge, the pair
    # flush to its right; ONE formula, the MQL's DrawStripFootX/DrawStripFootBw.
    fcw = gw - 2 * PAD
    labels = ["Reset", "All", "Copy"][:FOOT_N]
    bws = [max(FOOT_BW, 32 + mt4.text_w(lb, 8) + FOOT_PAD) for lb in labels]
    for f, label in enumerate(labels):
        bw = bws[f]
        if f == 0:
            fx = px
        else:
            fx = px + fcw - (sum(bws[1:]) + FOOT_GAP * (len(bws) - 2))
            fx += sum(bws[1:f]) + FOOT_GAP * (f - 1)
        fy = fy0 + 10
        c.rect(fx, fy, bw, 28, FOOTBG, Z_BASE)
        c.img("pnl_btn_ghost.bmp", fx - FOOT_PAD, fy - FOOT_PAD,
              bw + 2 * FOOT_PAD, 28 + 2 * FOOT_PAD, Z_SKIN)
        # P-DRAW-107: the ink is the CENTRED group — [ring + FOOT_GLYPH_ADV][word] —
        # the MQL's own DrawStripFootLabelX / DrawStripFootGlyphX. The cards'
        # left-aligned pair (`+12` / `+16` / `+32`) is retired: on a 72px plate it
        # left 40px of plate to the right of `All`.
        adv = 0 if f else FOOT_GLYPH_ADV
        tx = fx + (bw - adv - mt4.text_w(label, 8)) // 2
        # the design gives the ring to `Reset` alone; the pair is plain text.
        if f == 0:
            c.img("gl_reset_m.bmp", tx, fy + 6, GLYPH, GLYPH, Z_INK)
            c.text(tx + adv, fy + 17, label, MUTED, 8, True, z=Z_TEXT)
        else:
            c.text(tx, fy + 17, label, MUTED, 8, True, z=Z_TEXT)
    return c


def audit(L):
    rows = []
    rows.append(("row pitch", ROW_H, 42))
    rows.append(("header height", HEAD_H, 56))
    rows.append(("side pad", PAD, 16))
    rows.append(("chip top in row", CHIP_Y, 10))
    rows.append(("label top in row", LBL_Y, 14))
    rows.append(("switch w", 40, 40))
    rows.append(("switch h", 22, 22))
    rows.append(("row label pt", LBL_PT, 9))
    rows.append(("label row gap", ROW_GAP, 10))
    rows.append(("foot button w floor", FOOT_BW, 72))
    return rows


def main():
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") \
        else os.path.join(HERE, "sim-gear-panel.html")
    side = "--side" in sys.argv
    tab = int(os.environ.get("SIM_TAB", TAB_ACTIVE))

    L = layout(tab)
    notes = []
    c = paint(L, notes, tab)

    html = ["<html><head><meta charset='utf-8'><style>",
            "body{background:#c8c8e8;font:12px Arial;margin:0;padding:18px}",
            "canvas{background:#c8c8e8;display:block;margin:0 auto}",
            "img{position:absolute}i{position:absolute;display:block}span{position:absolute;display:block}",
            "h3{font:13px Arial;color:#333;margin:14px 0 6px}</style></head><body>"]
    html.append("<h3>Box Settings panel &mdash; group %d (%s) &mdash; h=%d w=%d cardN=%d exact=%s "
                "&mdash; kind %s</h3>"
                % (tab, L["tab_name"], L["h"], L["w"], L["card_n"], L["exact"], DEMO_KIND))
    html.append(c.to_html())
    for kind, what, w, h in notes:
        html.append("<p style='font:11px Arial;color:#111'>plate: <b>%s</b> %dx%d</p>" % (what, w, h))
    if side:
        html.append("<h3>reference card, same engine</h3>")
        ref = mt4.render_card(2)
        if ref:
            html.append(ref.to_html())
    html.append("</body></html>")

    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(html))

    print("group %d (%s): h=%d w=%d cardN=%d exact=%s -> %s"
          % (tab, L["tab_name"], L["h"], L["w"], L["card_n"], L["exact"], out))
    for kind, what, w, h in notes:
        print("  plate %s  %dx%d" % (what, w, h))
    print("  kind %s caps: %s" % (DEMO_KIND, sorted(SLOT_NAME[s] for s in CAPS)))

    bad = [(n, a, b) for n, a, b in audit(L) if a != b]
    if bad:
        print("SEAT DIVERGENCE:")
        for n, a, b in bad:
            print("   %-24s panel=%s card=%s" % (n, a, b))
    else:
        print("seats: all agree with the card")

    # P-DRAW-90: A STATEMENT THE WALKER DID NOT MODEL IS REPORTED, never silently
    # dropped — a proof that quietly skips is how the Style tab kept painting
    # "Half box" for a day.
    if L.get("unmodelled"):
        print("UNMODELLED statements in DrawStripGearContent's %s branch:" % L["tab_name"])
        for u in L["unmodelled"][:8]:
            print("   %s" % u.strip()[:100])

    miss = [op[1] for op in c.ops if op[0] == "img" and op[1] is None]
    if miss:
        print("MISSING ASSETS (drawn as holes): %s" % sorted(set(miss)))
    else:
        print("assets: every face this panel paints exists on disk")
    return 0


if __name__ == "__main__":
    sys.exit(main())
