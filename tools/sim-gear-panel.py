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
LBL_PT   = 9        # DSTRIP_GEAR_LBL_PT
CHIP_Y   = 10       # DSTRIP_CARD_CHIP_Y
LBL_Y    = 14       # DSTRIP_CARD_LBL_Y
SEC_CNT_W = 24      # DSTRIP_SEC_CNT_W
EDIT_H    = 22      # DSTRIP_GEAR_EDIT_H
FOOT_BW  = 72       # DSTRIP_GEAR_FOOT_BW
FOOT_N   = 3        # DSTRIP_GEAR_FOOT_N (P-DRAW-90: Reset | All · Copy)
FOOT_GLYPH_X = 12   # the cards' own glyph seat inside a foot button
FOOT_PLAIN_X = 16   # ... and a glyphless button's own label pad (the mock .gbtn)
FOOT_GAP = 8
FOOT_PAD = 8        # card PNL_BTN_PAD
MARK_VIS = 30
MARK_Y   = 13
MARK_PAD = 7
GLYPH    = 15
XBTN     = 26
MARK_Y_OFF = 6

TAB_H  = 24
TAB_PAD = 12
TAB_GAP = 4
TAB_UL  = 2

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
TABS = ["Paint", "Style", "Look", "Row"]
TAB_ACTIVE = 3                        # the screenshot's state (the Row tab)
TAB_BRANCH = {"Paint": "DSTRIP_GEAR_PAINT", "Style": "DSTRIP_GEAR_STYLE",
              "Look": "DSTRIP_GEAR_TPL", "Row": "DSTRIP_GEAR_STRIP"}

CONTENT = _fn_body(DS, r"void\s+DrawStripGearContent\s*\(")


def _branches():
    """`if(s_dsGear == X)` … `else if(s_dsGear == Y)` -> {X: body}."""
    marks = list(re.finditer(r"(?:else\s+)?if\s*\(\s*s_dsGear\s*==\s*(DSTRIP_GEAR_\w+)\s*\)", CONTENT))
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


def _expand_loops(text, unmodelled):
    """DrawStripGearContent's four `for` shapes -> plain DrawStripGearRow calls.

    The loops are BOUND in the source by a count this proof can read: the kind's
    own slot set (`s < DRAW_SLOT_N`), DrawStripGlyphCount(), the held drawing's
    level count (demo) and the preset list (demo). A loop whose bound is not one
    of those is left alone and REPORTED — a proof may not guess a row count.
    """
    out = text
    while True:
        m = re.search(r"for\s*\(\s*int\s+(\w+)\s*=\s*0\s*;\s*\1\s*<\s*([^;]+);", out)
        if not m:
            return out
        var, cond = m.group(1), m.group(2).strip()
        ob = out.index("{", m.end())
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
        rm = re.search(r"DrawStripGearRow\s*\(\s*([^,)]+)\s*,\s*([^)]+)\)", body)
        n, kind, arg = None, None, None
        if rm:
            kind, arg = rm.group(1).strip(), rm.group(2).strip()
            if "DRAW_SLOT_N" in cond:
                n = len([s for s in CAPS if s != _sid("MORE")])
            elif "DrawStripGlyphCount" in cond:
                n = 8                       # DrawStripGlyphCount() == 8
            elif cond == "nl":
                n = DEMO_LEVELS
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


def walk(tab_name):
    """DrawStripGearContent for one tab -> [(kind, name, y, extra), …]."""
    unmodelled = []
    branch = _expand_loops(BRANCHES.get(TAB_BRANCH[tab_name], ""), unmodelled)
    body, ung = _apply_guards(branch)
    unmodelled += ung
    blocks, y = [], 0
    # the calls, in source order, with the y advance each one really makes
    pat = re.compile(
        r'DrawStripGearSection\s*\(\s*"([^"]+)"'
        r'|DrawStripGearCaptionIn\s*\(\s*"([^"]+)"'
        r'|DrawStripGearGridChips\s*\(\s*(DRAW_SLOT_\w+)\s*,\s*([^)]+)\)'
        r'|DrawStripGearRow\s*\(\s*([^,)]+)\s*,\s*([^)]+)\)'
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
        elif tok.startswith("DrawStripGearGridStamp"):
            if pend_grid:
                slot, n = pend_grid
                cols = (GEAR_W - 2 * PAD + 8) // (48 + 8)      # DSTRIP_GEAR_CHIP 48
                rows = max(1, (n + cols - 1) // cols)
                blocks.append(["grid", slot, y, n])
                y += rows * ROW_H
                pend_grid = None
        elif m.group(7) is not None:
            for b in reversed(blocks):
                if b[0] == "caption" and b[1] is not None and b[3] is None:
                    b[3] = int(m.group(7))
                    break
        elif tok.startswith("y +="):
            y += ROW_H
    return dict(blocks=blocks, unmodelled=unmodelled, y=y)


# ════════════════════════════════════════════════════════════════════════════
def row_label(kind, arg):
    if kind == "1":
        return SWITCH_NAME.get(int(arg) if arg.isdigit() else -1,
                               DEMO_SLOT_TEXT.get(int(arg) if arg.isdigit() else -1, "Interior"))
    if kind == "3":
        return ROW_TEXT.get(3, "Save current look")
    if kind == "5":
        return ROW_TEXT.get("L5_%s" % arg, ROW_TEXT["L5_else"])
    if kind == "7":
        return "New %s wears this look" % DEMO_KIND_NAME
    if kind == "6":
        return DEMO_SLOT_TEXT.get(int(arg) if arg.isdigit() else -1, "")
    return ""


def row_res(kind, arg):
    if kind == "1":
        s = int(arg) if arg.isdigit() else -1
        nm = SLOT_NAME.get(s, "")
        if nm in DEMO_ON and DEMO_ON[nm]:
            return ON_RES.get(nm, ICON_RES.get(s, ""))
        return ICON_RES.get(s, "")
    return ""


# ── the seats audit: the panel's numbers against the cards' own ──────────────
def cap_w():
    """DrawStripGearCapW() — the widest of COLOR/FILL plus the row gap."""
    w = max(mt4.text_w("COLOR", LBL_PT), mt4.text_w("FILL", LBL_PT))
    return max(PAD, w + ROW_GAP)


GEAR_COL = 312               # DSTRIP_GEAR_COL
WIDE_ROWS = 10               # DSTRIP_GEAR_WIDE_ROWS
GRID_GAP = 8                 # DSTRIP_GEAR_GRID_GAP
CHIP_W = 48                  # DSTRIP_GEAR_CHIP
CHIP_H = 32                  # DSTRIP_GEAR_CHIP_H


def layout(tab=TAB_ACTIVE):
    """DrawStripGearLayout() + DrawStripGearPlace(): parsed content, and the
    SAME narrow/wide decision the panel makes (P-DRAW-86).

    A NARROW plate must fit the baked card set: `cardN = (gh-104)/42` and
    `pnl_card<n>` stops at 10, so at most `WIDE_ROWS - 1` content rows stay
    narrow; past that the panel splits into two 312 columns and the plate is
    624 — the branch `DrawStripGearPlace` takes, and the one that decides
    whether MT4 draws a baked card or a composed W body.
    """
    tab_name = TABS[tab]
    W = walk(tab_name)
    tabs_y = HEAD_H
    content_top = HEAD_H + ROW_H           # head + the tab row
    rows = []
    for kind, name, by, extra in W["blocks"]:
        if kind == "row" and name is None:
            k, a = extra
            name = row_label(k, a)
            extra = (k, a, row_res(k, a))
        elif kind == "grid":
            name, extra = extra, (extra,)
        rows.append([kind, name, by, extra, 0])

    nrows = len(rows)
    content_end = nrows * ROW_H
    w = GEAR_W
    if content_end > (WIDE_ROWS - 1) * ROW_H:
        blk = [r[2] for r in rows if r[0] in ("section", "caption")]
        split = None
        if len(blk) >= 2:                  # split on the best BLOCK boundary
            best = None
            for by in blk[1:]:
                h = max(by, content_end - by)
                if best is None or h < best[1]:
                    best = (by, h)
            split = best[0] if best else None
        elif nrows >= 4:                   # ...else at half the ROW list
            split = rows[(nrows + 1) // 2][2]
        if split is not None:
            for r in rows:
                r[4] = 1 if r[2] >= split else 0
            col0 = [r for r in rows if r[4] == 0]
            col1 = [r for r in rows if r[4] == 1]
            # DrawStripGearShiftItems packs each column from contentTop
            for i, r in enumerate(col0):
                r[2] = i * ROW_H
            for i, r in enumerate(col1):
                r[2] = i * ROW_H
            content_end = max(len(col0), len(col1)) * ROW_H
            w = GEAR_W2

    blocks = [(k, n, content_top + by, ex, col) for k, n, by, ex, col in rows]
    end = content_top + content_end
    gh = end + FOOT_H + AIR
    card_n = (gh - 104) // 42
    exact = (gh - 104) % 42 == 0 and 1 <= card_n <= 10
    return dict(tabs_y=tabs_y, top=content_top, end=end, foot_y=end, h=gh, w=w,
                card_n=card_n, exact=exact, blocks=blocks, wide=(w == GEAR_W2),
                unmodelled=W["unmodelled"], tab_name=tab_name)


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
        c.img("pnl_cardWtop.bmp", gx - 14, gy - 14, gw + 28, 70, Z_CARD)
        for li in range(pair_n):
            c.img("pnl_cardWmid.bmp", gx - 14, gy + 70 + li * ROW_H, gw + 28, ROW_H, Z_CARD)
        c.img("pnl_cardWbot.bmp", gx - 14, gy + 70 + pair_n * ROW_H, gw + 28, 62, Z_CARD)
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
    c.text(htx, hy + 12, "Box Settings", INK, PT["title"], True, z=Z_TEXT)
    c.text(htx, hy + 35, "SERVING 1 DRAWING", MUTED, PT["sub"], True, z=Z_TEXT)
    c.rect(ver_x, hy + 20, vw, 16, VER_BG, Z_BASE)
    c.text(ver_x + vw / 2, hy + 28, ver, ACCENT_C, PT["ver"], True, "lu", Z_TEXT)
    close_x = gx + gw - PAD - XBTN
    c.rect(close_x, hy + 15, XBTN, XBTN, "rgba(28,34,44,1)", Z_BASE)
    c.img("pnl_xbtn.bmp", close_x - 2, hy + 13, XBTN + 4, XBTN + 4, Z_SKIN)
    c.img("gl_x_%s.bmp" % ANAME, close_x + (XBTN - GLYPH) // 2,
          hy + 15 + (XBTN - GLYPH) // 2, GLYPH, GLYPH, Z_INK)

    # ── TAB ROW (DrawStripGearPaint) ──────────────────────────────────────────
    ty = gy + L["tabs_y"] + (ROW_H - TAB_H) // 2
    total = sum(TAB_PAD + mt4.text_w(t, 8) for t in TABS) + (len(TABS) - 1) * TAB_GAP
    col_w = gw - 2 * PAD
    tx = gx + PAD + max(0, (col_w - total) // 2)
    for i, t in enumerate(TABS):
        tw = TAB_PAD + mt4.text_w(t, 8)
        sel = (i == tab)
        c.rect(tx, ty, tw, TAB_H, CARD_C, Z_BASE)
        c.text(tx + tw / 2, ty + TAB_H / 2, t, INK if sel else MUTED, 8, sel, "lu", Z_TEXT)
        if sel:
            c.rect(tx + 7, ty + TAB_H - 1, tw - 14, TAB_UL, ACCENT_C, Z_INK)
        tx += tw + TAB_GAP

    # ── CONTENT ROWS ─────────────────────────────────────────────────────────
    px = gx + PAD
    cw = col_w
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
            c.text(pxr, ry + LBL_Y, name, LABEL, LBL_PT, True, z=Z_TEXT)
            e = extra
            ex = pxr + cap_w()
            c.rect(ex, ry + (ROW_H - EDIT_H) // 2, cw - cap_w(), EDIT_H, FIELD, Z_BASE,
                   border=FIELD_BD)
            if e in (0, 4):
                c.text(ex + 4, ry + (ROW_H - EDIT_H) // 2 + (EDIT_H - mt4.font_px(8)) // 2,
                       "#FFAB00", LABEL, 8, False, "lu", Z_TEXT)
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
            c.text(pxr + PAD, ry + LBL_Y, name, LABEL, LBL_PT, True, z=Z_TEXT)
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
        # the design gives the ring to `Reset` alone; the pair is plain text.
        if f == 0:
            c.img("gl_reset_m.bmp", fx + FOOT_GLYPH_X, fy + 6, GLYPH, GLYPH, Z_INK)
            c.text(fx + 32, fy + 17, label, MUTED, 8, True, z=Z_TEXT)
        else:
            c.text(fx + FOOT_PLAIN_X, fy + 17, label, MUTED, 8, True, z=Z_TEXT)
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
    html.append("<h3>Box Settings panel &mdash; tab %d (%s) &mdash; h=%d w=%d cardN=%d exact=%s "
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

    print("tab %d (%s): h=%d w=%d cardN=%d exact=%s -> %s"
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
