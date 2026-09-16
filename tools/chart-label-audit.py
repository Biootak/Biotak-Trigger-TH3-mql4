#!/usr/bin/env python3
"""chart-label-audit — the gate behind P-LBL-06/07/08 (the chart-side blocks).

WHY THIS EXISTS
The chart-side text blocks (the ATR/TH columns, the bottom-right trade card) are
SCREEN-SPACE objects anchored to a chart corner, so every one of them is one
arithmetic mistake away from a bug the user sees in the same second:

  * two rows drawn on top of each other (a row Y derived in two places),
  * a row parked off the chart edge (an input the layout never clamps),
  * a card whose seams are uneven (one gap for one pair, another for the next),
  * a row that is not on the other rows' centre axis,
  * a brand pair whose letters OVERLAP, because the gap between `TR` and `ex`
    was guessed in pixels instead of measured (that one shipped: at 96 DPI the
    guess was ~2 px short, at 144 DPI ~12 px - the letters read as one blob),
  * and THE P-LBL-07 SHAPE: one visual card split across two corners, so
    changing one half silently moves only that half.

None of the other gates can see any of that: `write-budget` counts writes per
frame, `gesture-budget` counts heavy passes per drag, `zorder` owns paint order,
`ui-text` owns caption metrics for the panel chrome, `probe-budget` owns
control->reader wiring. This one owns THE ARITHMETIC OF A CHART CORNER STACK.

Checks, all on the source, no terminal:

  1 OWNER    the card's Ys AND Xs have ONE owner (`TRexTradeCardLayout`) and
             every writer uses it (`DisplayTRexTitleBlock`,
             `DisplayTradePlanTopRows`, `CreateATRTradeLabel`); no writer derives
             a position itself, and no writer re-derives a row's TEXT (the
             string that is MEASURED must be the string that is DRAWN).
  2 ANCHOR   every piece of the card is created in the same corner family
             (`CORNER_RIGHT_LOWER` + `ANCHOR_RIGHT_LOWER`). A top-anchored piece
             inside a bottom-anchored stack IS the split card.
  3 MEASURED no guessed glyph widths: the retired `brandSize * 0.7` gap between
             `TR` and `ex` must not come back, the pair's spacing must be the
             measured `wEx`, and the rows must be measured with `PnlRawTextW`.
  4 RAW EM   the raw em box has ONE owner (`PnlRawLineH` in the metrics file):
             no other module does `pt * PnlDpi() / 72`, and `PnlRawTextW`
             measures through it - so the row pitch and the row widths can never
             describe two different fonts.
  5 INPUTS   every number the model needs is read from the SOURCE: the input
             defaults from PropertiesAndInputs.mqh, the clamp bounds from the
             constants file, and the clamp's condition must name the same
             constant it clamps to (a decorative bound is a lie).
  7 DECOUPLED the trade card answers to its OWN master (`inpShowATRTradeLabels`
             + the two row flags) and never to the ATR-overview global
             (`g_atrLabelsVisible`): the wipe gate, the 2 s pump, the mask writer
             and BOTH EventHandlers call sites are checked, so the ring's `ATR`
             tile / the label card's `ATR LABELS` row / the A key cannot remove
             the trade plan again (P-UI-84).
  6 GEOMETRY a python mirror of the owner's arithmetic over an input grid
             (font 4..24, row gap 0..60, bottom margin 0..120, rows -1000..1000,
             DPI 96/120/144/192, chart height 320..2160, row widths 20..640):
               I1  the clamp holds (rows never negative, never past the bound)
               I2  ONE pitch between every pair of rows (even seams)
               I3  the brand row's top never crosses the chart ceiling
               I4  more rows never draws LOWER (monotone)
               I5  the SHIPPED defaults hold the whole card on the smallest
                   supported chart (320 px)
               I6  all three rows sit on ONE centre axis (within the 1 px the
                   integer halves can differ by)
               I7  the brand pair has zero overlap and zero gap

MQL4 INTEGER DIVISION truncates toward zero while python's `//` floors, so the
mirror uses `idiv()`; the owner floors the chart-clamp result at 0, which makes
the difference harmless - the audit keeps both halves honest.

Usage:  python tools/chart-label-audit.py [--quiet] [--model] [--selftest]
        --model    print the grid's worst case and the retired guess's error.
        --selftest seeds each fault into a doctored source and requires the
        matching check to catch it (a gate that cannot fail proves nothing).
Exit 0 = clean, 1 = the card can overlap, leave the chart, or lost its owner.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LABELS = os.path.join(ROOT, "Biotak", "LabelFunctions.mqh")
INPUTS = os.path.join(ROOT, "Biotak", "PropertiesAndInputs.mqh")
CONSTS = os.path.join(ROOT, "Biotak", "ConstantsAndEnums.mqh")
METRICS = os.path.join(ROOT, "Biotak", "UtilityFunctions.mqh")
EVENTS = os.path.join(ROOT, "Biotak", "EventHandlers.mqh")

QUIET = "--quiet" in sys.argv
SHOW_MODEL = "--model" in sys.argv

# --- source access (patchable, so --selftest can doctor a file) --------------
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


def func(text, signature):
    """(signature text, { ... } block) of the function declared at `signature`.

    The signature matters as much as the block now: the card's writers must
    TAKE the layout (`const STrexCardLayout &L`) instead of owning it.
    """
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
                return src[i:j], src[j:k + 1]
    return None


def body(text, signature):
    """The { ... } block of the function whose declaration starts at `signature`."""
    got = func(text, signature)
    return got[1] if got else None


def function_blocks(text):
    """[(name, whole definition)] for every function definition in the file.

    Used to ask "how many times does ONE render pass lay the card out" - a
    question no single writer's body can answer.
    """
    src = strip_comments(text)
    out, seen = [], set()
    types = ("void|bool|int|string|double|float|color|long|uint|datetime|short|char")
    for m in re.finditer(r"^[ \t]*(?:%s)\s+([A-Za-z_]\w*)\s*\(" % types, src, re.M):
        if m.start() in seen:
            continue
        j = src.find("{", m.end())
        if j < 0:
            continue
        depth = 0
        for k in range(j, len(src)):
            if src[k] == "{":
                depth += 1
            elif src[k] == "}":
                depth -= 1
                if depth == 0:
                    seen.add(m.start())
                    out.append((m.group(1), src[m.start():k + 1]))
                    break
    return out


# --- source readers ---------------------------------------------------------
def input_default(name):
    m = re.search(r"input\s+int\s+%s\s*=\s*(-?\d+)\s*;" % re.escape(name), read(INPUTS))
    return int(m.group(1)) if m else None


def macro_value(name):
    m = re.search(r"#define\s+%s\s+(-?\d+)\b" % re.escape(name), read(CONSTS))
    return int(m.group(1)) if m else None


def owner_clamps(owner):
    """((lo, hi), honest): the bounds the owner clamps `rows` to, and whether
    each clamp's CONDITION names the same bound it assigns to."""
    lo = re.search(r"if\(\s*rows\s*<\s*(-?\d+)\s*\)\s*rows\s*=\s*(\S+)\s*;", owner)
    hi = re.search(r"if\(\s*rows\s*>\s*(\S+?)\s*\)\s*rows\s*=\s*(\S+?)\s*;", owner)
    if not lo or not hi:
        return (None, None), False
    hi_cond, hi_val = hi.group(1), hi.group(2)
    lo_cond, lo_val = int(lo.group(1)), lo.group(2)
    honest = (lo_cond == 0 and lo_val == "0" and hi_cond == hi_val
              and not re.match(r"^-?\d+$", hi_val) is None or hi_cond == hi_val)
    if lo_cond != 0 or lo_val != "0":
        honest = False
    if hi_cond != hi_val:
        honest = False
    hi_n = int(hi_val) if re.match(r"^-?\d+$", hi_val) else macro_value(hi_val)
    if hi_n is None:
        honest = False
    return (0, hi_n), honest


# --- the model (mirror of the owner) ---------------------------------------
def bottom_of(L):
    """The card's FLOOR: the bottom margin plus the requested blank rows.

    Not `y_trade`: that row can be switched off (None), while the floor the
    owner stacks from is `bottom` and does not depend on which rows are drawn.
    """
    return L["bottom"]


def idiv(a, b):
    """MQL4 int/int truncates toward zero (python's // floors)."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def em(raw_pt, dpi):
    """PnlRawLineH: the em box MT4 gives a RAW point size."""
    pt = raw_pt if raw_pt > 0 else 1
    return int(round(pt * dpi / 72.0))


def card(font, row_gap, margin_bottom, inp_rows, dpi, chart_h, lo, hi,
         w_tp, w_hunter, w_tr, w_ex, show_tp=True, show_sl=True,
         height_clamp=True, forget_clamp=False, centred=True, old_guess=False,
         pack=True):
    """The owner's arithmetic, exactly. Returns the laid-out card.

    `pack=False` is the RETIRED behaviour (P-LBL-09): every row keeps its slot
    even when it is switched off, so the others do not move down into it and the
    card leaves a hole above the chart's floor.
    """
    if forget_clamp:
        rows = inp_rows
    else:
        rows = min(max(inp_rows, lo), hi)
    fs = max(1, font)
    brand = fs + 6
    fs_em = max(1, em(fs, dpi))
    brand_em = max(1, em(brand, dpi))
    gap = row_gap if row_gap > 0 else 0
    pitch = fs_em + gap
    # the card's floor: its own input, clamped by hand to the named bound (the
    # input is applied raw at init, so 0 / -5 / 5000 all have to be safe)
    mb_top = macro_value("TREX_CARD_MAX_MARGIN_BOTTOM") or 200
    bottom = min(max(0, margin_bottom), mb_top)
    top_pad = macro_value("TREX_CARD_TOP_PAD") or 8
    drawn = 1 + (1 if show_tp else 0) + (1 if show_sl else 0)
    slots = 3 if not pack else drawn              # the retired card reserved 3
    if height_clamp and chart_h > 0:
        max_rows = (idiv(chart_h - top_pad - brand_em - bottom, pitch)
                    - (slots - 1))
        if max_rows < 0:
            max_rows = 0
        if rows > max_rows:
            rows = max_rows
    w_brand = w_tr + w_ex
    card_w = max(w_brand,
                 w_hunter if show_sl else 0,
                 w_tp if show_tp else 0, 1)
    y = bottom + rows * pitch
    y_trade = None
    y_hunter = None
    if show_tp:
        y_trade = y
        y += pitch
    elif not pack:
        y += pitch                                # the retired hole
    if show_sl:
        y_hunter = y
        y += pitch
    elif not pack:
        y += pitch                                # the retired hole
    y_brand = y
    right = max(8, 25)                          # inpLabelsMarginLeft default 25
    x_trade = right + idiv(card_w - w_tp, 2)
    x_hunter = right + idiv(card_w - w_hunter, 2)
    x_brand = right + idiv(card_w - w_brand, 2)
    if old_guess:                               # the retired pixel guess
        x_brand = right
    if not centred:                             # flush-right rows (the old card)
        x_trade = right
        x_hunter = right
        x_brand = right
    x_ex = x_brand
    x_tr = x_ex + (int(round(1.4 * brand)) if old_guess else w_ex)
    return {
        "rows": rows, "pitch": pitch, "fs_em": fs_em, "brand_em": brand_em,
        "bottom": bottom,
        "y_trade": y_trade, "y_hunter": y_hunter, "y_brand": y_brand,
        "x_trade": x_trade, "x_hunter": x_hunter, "x_brand": x_brand,
        "show_tp": show_tp, "show_sl": show_sl, "drawn": drawn,
        "w_tp": w_tp, "w_hunter": w_hunter, "w_brand": w_brand, "w_ex": w_ex,
        "x_ex": x_ex, "x_tr": x_tr, "top_pad": top_pad, "fs": fs, "brand": brand,
        "card_w": card_w,
    }


# --- checks -----------------------------------------------------------------
WRITERS = ("DisplayTRexTitleBlock", "DisplayTradePlanTopRows", "CreateATRTradeLabel")


def check_owner():
    problems = []
    labels = read(LABELS)
    owner = body(labels, "void TRexTradeCardLayout(")
    if owner is None:
        return ["TRexTradeCardLayout() is gone - the card has no owner"], None

    # 1. the writers CONSUME the layout. The P-LBL-09 shape is the opposite:
    #    every writer calling the owner itself, i.e. the card laid out once per
    #    ROW - and a row that is switched off leaving its slot reserved.
    for name in WRITERS:
        got = func(labels, "bool %s(" % name)
        if got is None:
            problems.append("%s() not found" % name)
            continue
        sig, blk = got
        if "const STrexCardLayout &L" not in sig:
            problems.append("%s() does not TAKE the owner's layout" % name)
        if "TRexTradeCardLayout(" in blk:
            problems.append("%s() lays the card out itself (the owner runs once per pass)"
                            % name)
        for leaked in ("inpLabelsMarginBottom", "inpLabelsMarginLeft",
                       "PnlRawLineH(", "PnlRawTextW("):
            if leaked in blk:
                problems.append("%s() computes card geometry itself (%s)"
                                % (name, leaked))
        for m in re.finditer(r"(?<![\w.])[xy](?:Brand|Hunter|Trade|Ex|TR|Sp)\s*=\s*([^;,]+)",
                             blk):
            if m.group(1).strip() != "0":
                problems.append("%s() derives %s itself (%s)"
                                % (name, m.group(1), m.group(2).strip()))

    # 2. EXACTLY ONE layout per render pass, computed BEFORE anything is drawn:
    #    the card's cost is then two text measurements per row per pass, never
    #    one pass per row (what the user meant by "zero load").
    passes = 0
    for fname, whole in function_blocks(labels):
        # the BODY, not the definition: a function's own name is not a call site
        blk = whole[whole.index("{"):]
        hits = [w for w in WRITERS if ("%s(" % w) in blk]
        if not hits:
            continue
        passes += 1
        n = blk.count("TRexTradeCardLayout(")
        first_write = min(blk.find("%s(" % w) for w in hits)
        if n != 1:
            problems.append("%s() lays the card out %d times per pass (must be 1)"
                            % (fname, n))
        elif blk.find("TRexTradeCardLayout(") > first_write:
            problems.append("%s() draws before it lays the card out" % fname)
    if passes == 0:
        problems.append("no render pass draws the card at all")

    # 3. the texts that are MEASURED must be the texts that are DRAWN
    for helper, defined_in in (("TradePlanTPRowText", "CreateATRTradeLabel"),
                               ("TradePlanHunterText", "DisplayTradePlanTopRows")):
        if labels.count("string %s(" % helper) != 1:
            problems.append("%s() is not defined exactly once" % helper)
        blk = body(labels, "bool %s(" % defined_in)
        if blk is not None and ("%s(plan)" % helper) not in blk:
            problems.append("%s() does not use %s()" % (defined_in, helper))
        if "%s(plan)" % helper not in owner:
            problems.append("the owner does not measure %s()" % helper)
    # P-BK-58: the FLOOR's clamp is shared with the note row's fallback slot, so it moved into
    # its own owner (`LabelFloorMargin`) and the card CALLS it - asking the card's body for the
    # two literals would now report a lost owner that is merely one call away. The floor's OWN
    # body is what gets read (and it must be a single definition).
    floor = body(labels, "int LabelFloorMargin(")
    if floor is None:
        problems.append("the card's floor has no owner (LabelFloorMargin)")
        floor = ""
    elif labels.count("int LabelFloorMargin(") != 1:
        problems.append("LabelFloorMargin() is not defined exactly once")
    if floor and "LabelFloorMargin()" not in owner:
        problems.append("the card does not read the floor's own owner")
    # the knobs must be READ here: an input nobody reads is a dead control
    # (P-UI-47). `inpATRTradeLabelRowGap` is the card's own seam - it was dead
    # until P-LBL-09 wired it, and the shared `inpLabelRowGap` must NOT come
    # back (that is what made the corner card inherit the grid's spacing).
    for needed in ("inpTrexStampGapRows", "inpATRTradeLabelRowGap",
                   "GetCachedChartHeight()", "TREX_CARD_TOP_PAD",
                   "TREX_CARD_MAX_GAP_ROWS", "TREX_CARD_MAX_ROW_GAP",
                   "PnlRawTextW(\"TR\"", "PnlRawTextW(\"ex\"",
                   "L.xTR", "rightEdge"):
        if needed not in owner:
            problems.append("the owner lost: %s" % needed)
    for needed in ("TREX_CARD_MAX_MARGIN_BOTTOM", "inpLabelsMarginBottom"):
        if needed not in owner + floor:
            problems.append("the owner lost: %s" % needed)
    for banned in ("inpLabelRowGap", "inpLabelColumnGap"):
        if banned in owner or banned in floor:
            problems.append("the owner reads the shared grid input %s" % banned)
    # the seam clamp must be honest: condition and value name the same bound
    if not re.search(r"if\(gap\s*<\s*0\)\s*gap\s*=\s*0;", owner):
        problems.append("the card's row gap has no lower bound (a 0/-5 input)")
    if not re.search(r"if\(gap\s*>\s*TREX_CARD_MAX_ROW_GAP\)\s*gap\s*=\s*TREX_CARD_MAX_ROW_GAP;",
                     owner):
        problems.append("the card's row gap is not clamped to the named bound")
    if not re.search(r"if\(bottom\s*<\s*0\)\s*bottom\s*=\s*0;", floor):
        problems.append("the card's floor has no lower bound (a 0/-5 input)")
    if not re.search(r"if\(bottom\s*>\s*TREX_CARD_MAX_MARGIN_BOTTOM\)\s*"
                     r"bottom\s*=\s*TREX_CARD_MAX_MARGIN_BOTTOM;", floor):
        problems.append("the card's floor is not clamped to the named bound")
    return problems, owner


def check_anchor():
    problems = []
    labels = read(LABELS)
    for sig in ("bool CreateTRexPiece(", "bool CreateATRTradePiece("):
        blk = body(labels, sig)
        if blk is None:
            problems.append("%s not found" % sig)
            continue
        for prop in ("CORNER_RIGHT_LOWER", "ANCHOR_RIGHT_LOWER"):
            if prop not in blk:
                problems.append("%s: %s is gone (the card is bottom-anchored)"
                                % (sig.rstrip("(").strip(), prop))
    return problems


def check_measured():
    """No guessed glyph widths anywhere in the card's family."""
    problems = []
    labels = read(LABELS)
    code = strip_comments(labels)      # the retired formula lives on in prose
    # the exact expression that shipped the bug
    for m in re.finditer(r"2\.0\s*\*\s*brandSize\s*\*\s*0\.7|brandSize\s*\*\s*0\.7", code):
        problems.append("the retired guessed brand gap is back (%s)" % m.group(0))
    owner = body(labels, "void TRexTradeCardLayout(")
    if owner is None:
        return problems + ["TRexTradeCardLayout() is gone"]
    if len(re.findall(r"PnlRawTextW\(", owner)) < 4:
        problems.append("the owner no longer measures every row")
    if not re.search(r"L\.xTR\s*=\s*L\.xEx\s*\+\s*wEx\s*;", owner):
        problems.append("the TR/ex gap is not the measured wEx")
    # the bottom row's tokens need real air (two spaces), not one
    m = re.search(r"return\s+StringFormat\(\"#SL:-%d(.*?)#TP1\+%d", code, re.S)
    if not m or "  " not in m.group(1):
        problems.append("the #SL/TP row lost its wide token gaps")
    return problems


def check_raw_em():
    problems = []
    pattern = re.compile(r"\(double\)PnlDpi\(\)\s*/\s*72")
    for name in sorted(os.listdir(os.path.join(ROOT, "Biotak"))):
        if not name.endswith(".mqh"):
            continue
        path = os.path.join(ROOT, "Biotak", name)
        for _m in pattern.finditer(read(path)):
            if path != METRICS:
                problems.append("raw em arithmetic outside the metrics owner: %s" % name)
    if len(pattern.findall(read(METRICS))) < 2:
        problems.append("PnlRawLineH/PnlLineH no longer own the em arithmetic")
    if body(read(METRICS), "int PnlRawLineH(") is None:
        problems.append("PnlRawLineH() is gone")
    wid = body(read(METRICS), "int PnlRawTextW(")
    if wid is None or "PnlRawLineH(" not in wid:
        problems.append("PnlRawTextW() does not measure through PnlRawLineH()")
    return problems


def check_row_bound():
    """A ROW'S WIDTH BOUND IS NEVER DERIVED FROM A SIZE WE DO NOT HAVE (P-UI-94).

    The three column sections (ATR, fractal TH, standard TH) each asked the
    chart-width cache for the width a row may use before it wraps. That cache
    answers 0 while the size is not known yet - a fresh attach, a minimized
    window, a failed read - so `cache - margin * 2` came out NEGATIVE and the
    wrap test was TRUE for every column: the block laid itself out one column
    per ROW, and its own section slot was measured from that, pushing the next
    section (and the mode/overlay rows after it) down the chart.

    The bound has ONE owner now, an unknown size answers 0 = "no bound", and
    every wrap test must ask for that sentinel explicitly. A bound derived by
    hand again - or a test that treats 0 as a real width - is the same bug back.
    """
    problems = []
    labels = read(LABELS)
    code = strip_comments(labels)      # the retired formula lives on in prose
    owner = body(labels, "int LabelRowMaxWidth(")
    if owner is None:
        return ["LabelRowMaxWidth() is gone - the row bound has no owner again"]
    if not re.search(r"if\s*\(\s*cw\s*<=\s*0\s*\)\s*return\s+0\s*;", owner):
        problems.append("LabelRowMaxWidth() no longer answers 0 for an unknown chart width")
    if not re.search(r">\s*0\s*\)\s*\?\s*usable\s*:\s*0", owner):
        problems.append("LabelRowMaxWidth() can return a negative bound again")
    for m in re.finditer(r"int\s+maxWidth\s*=\s*([^;]+);", code):
        if "LabelRowMaxWidth(" not in m.group(1):
            problems.append("a label section derives its row bound by hand again (%s)"
                            % m.group(1).strip())
    sites = code.count("LabelRowMaxWidth(") - 1          # minus the definition
    if sites < 3:
        problems.append("only %d of the three column sections use the row bound" % sites)
    guarded = len(re.findall(r"if\s*\(\s*maxWidth\s*>\s*0\s*&&", code))
    if guarded < sites:
        problems.append("a wrap test treats the \"no bound\" sentinel as a real width "
                        "(%d of %d guarded)" % (guarded, sites))
    return problems


def check_presence():
    """PRESENCE == THE SWITCH (P-LBL-09): the writer that can skip a row must
    REMOVE that row's object when the switch is off, and no render pass may
    duplicate the delete - two owners is the ghost row AND the double delete.

    The relayout pass wipes the prefix first, so this only bites the 2 s live
    pump: a row switched off while its numbers were frozen would otherwise keep
    drawing at the Y the packed stack no longer reserves for it.
    """
    problems = []
    labels = read(LABELS)
    tp = body(labels, "bool CreateATRTradeLabel(")
    if tp is None:
        return ["CreateATRTradeLabel() is gone"]
    if "tpName" not in tp or "ObjectDelete(0, tpName)" not in tp:
        problems.append("the #SL/TP row is not removed when its switch is off")
    hp = body(labels, "bool DisplayTradePlanTopRows(")
    if hp is None:
        return problems + ["DisplayTradePlanTopRows() is gone"]
    if 'ObjectDelete(0, labelPrefix + "TREX_Hunter")' not in hp:
        problems.append("the Hunter row is not removed when its switch is off")
    if "if(!L.showSL)" not in hp:
        problems.append("the Hunter writer no longer reads its own switch")
    # A pass may wipe the whole card (the master switch, BEFORE the layout call);
    # what it may not do is decide a single row's presence at the call site - the
    # old `if(L.showSL) ... else delete` shape, which is what P-LBL-09 removed.
    for fname, whole in function_blocks(labels):
        blk = whole[whole.index("{"):]
        cut = blk.find("TRexTradeCardLayout(")
        if cut < 0 or "DisplayTradePlanTopRows(" not in blk:
            continue
        after = blk[cut:]
        if 'ObjectDelete(0, labelPrefix + "TREX_Hunter")' in after:
            problems.append("%s() also removes the Hunter row (two owners)" % fname)
        if "if(L.showSL)" in after:
            problems.append("%s() decides the Hunter row at the call site" % fname)
    return problems


def check_decoupled():
    """P-UI-84 - THE TRADE CARD ANSWERS TO ITS OWN MASTER.

    The card (brand + Hunter SL row + #SL/#TP row) is a TRADE PLAN, not part of
    the ATR overview - yet until 2026-09-14 every gate that decided it ALSO ANDed
    `g_atrLabelsVisible`, so the ring's `ATR` tile, the label card's
    `ATR LABELS` row 4 and the A hotkey each took the trade plan away with the
    ATR columns, and the two read as one control in all but name.

    The coupling had four faces and all four are asserted here: the wipe gate
    (`DisplayATRTradeLabels`), the 2 s pump (`TradePlanLiveTick`), the mask
    writer (`SetATRLabelsVisibility`) and both EventHandlers call sites. The ONE
    legal reader of `g_atrLabelsVisible` in the label module is
    `DisplayATRLabels` itself - the ATR columns it actually owns.
    """
    problems = []
    code = strip_comments(read(LABELS))
    atr_block = body(code, "void DisplayATRLabels(") or ""
    if code.count("g_atrLabelsVisible") != atr_block.count("g_atrLabelsVisible"):
        problems.append("a label pass other than DisplayATRLabels() reads "
                        "g_atrLabelsVisible (the trade card is coupled to the "
                        "ATR overview again)")
    wipe = body(code, "void DisplayATRTradeLabels(")
    if wipe is None:
        problems.append("DisplayATRTradeLabels() is gone")
    elif "if(!inpShowATRTradeLabels)" not in wipe:
        problems.append("the trade card no longer wipes on its OWN master switch")
    pump = body(code, "void TradePlanLiveTick(")
    if pump is None:
        problems.append("TradePlanLiveTick() is gone")
    elif "if(!inpShowATRTradeLabels || IsIndicatorHidden()) return;" not in pump:
        problems.append("the trade-card pump is not gated on the card's own "
                        "master + the indicator F-hide")
    mask = body(code, "void SetATRLabelsVisibility(")
    if mask is None:
        problems.append("SetATRLabelsVisibility() is gone")
    else:
        if "bool cardOn = (inpShowATRTradeLabels && !IsIndicatorHidden());" not in mask:
            problems.append("the card's mask writer lost its OWN predicate")
        if re.search(r"shouldShow\s*&&\s*inpShowATRTradeLabels", mask):
            problems.append("the card's mask writer is back on the ATR "
                            "overview's shouldShow")
    events = strip_comments(read(EVENTS))
    if re.search(r"if\s*\(\s*g_atrLabelsVisible\s*\)\s*DisplayATRTradeLabels\(", events):
        problems.append("an EventHandlers call site guards the trade card with "
                        "the ATR overview switch")
    if "DisplayATRTradeLabels(objectPrefix);" not in events:
        problems.append("EventHandlers no longer paints the trade card")
    return problems


def check_inputs(owner):
    problems = []
    (lo, hi), honest = owner_clamps(owner)
    defaults = {}
    for name in ("inpFontSize", "inpATRTradeLabelRowGap", "inpLabelsMarginBottom",
                 "inpTrexStampGapRows"):
        defaults[name] = input_default(name)
        if defaults[name] is None:
            problems.append("input %s not found in PropertiesAndInputs.mqh" % name)
    for name in ("TREX_CARD_MAX_GAP_ROWS", "TREX_CARD_TOP_PAD", "TREX_CARD_MAX_ROW_GAP",
                 "TREX_CARD_MAX_MARGIN_BOTTOM"):
        if macro_value(name) is None:
            problems.append("constant %s not found in ConstantsAndEnums.mqh" % name)
    if lo is None:
        problems.append("the owner's row clamp is gone")
    elif not honest:
        problems.append("a clamp's condition and value disagree (decorative bound)")
    return problems, defaults, lo, hi


FONTS = (6, 8, 12, 24)
GAPS = (0, 18, 60)
MARGINS = (0, 25, 120)
ROWREQ = (-1000, 0, 1, 20, 1000)
DPIS = (96, 144, 192)
HEIGHTS = (0, 320, 600, 1080, 2160)
WIDTHS = (20, 160, 640)
COMPOS = ((True, True), (True, False), (False, True), (False, False))


def check_geometry(lo, hi, height_clamp=True, **kw):
    """I1..I4 + I6 + I7 over the grid. Returns (problems, stats).

    Problems are keyed by MESSAGE with one example combo each: a grid this size
    would otherwise print a million near-identical lines and bury the finding.
    """
    problems = {}

    def add(msg, combo):
        problems.setdefault(msg, combo)

    infeasible = 0
    worst_top, worst_combo = 0, None
    for font in FONTS:
        for gap in GAPS:
            for margin in MARGINS:
                for req in ROWREQ:
                    for dpi in DPIS:
                        for h in HEIGHTS:
                            for w_tp in WIDTHS:
                                for w_h in (20, 160):
                                    for w_ex in (20, 160):
                                      w_tr = w_ex
                                      for (show_tp, show_sl) in COMPOS:
                                        comp = "tp=%d sl=%d" % (show_tp, show_sl)
                                        c = ("[font=%d gap=%d margin=%d rows=%d dpi=%d "
                                             "h=%d wTP=%d wH=%d wEx=%d %s]"
                                             % (font, gap, margin, req, dpi, h,
                                                w_tp, w_h, w_ex, comp))
                                        L = card(font, gap, margin, req, dpi, h,
                                                 lo, hi, w_tp, w_h, w_tr, w_ex,
                                                 show_tp, show_sl, height_clamp, **kw)
                                        # I1 the clamp holds - and the lower bound is
                                        # PHYSICALLY 0 (negative rows would draw the rows
                                        # into each other), not just "whatever lo says".
                                        if L["rows"] < 0 or L["rows"] > hi:
                                            add("I1 rows outside [0, the clamped bound]", c)
                                        # I8 PACKED (P-LBL-09): the lowest DRAWN row owns the
                                        # bottom margin and every drawn row above it is one
                                        # pitch higher - a switched-off row leaves NO hole.
                                        anchors = [a for a in (L["y_trade"], L["y_hunter"]) if a is not None]
                                        anchors.append(L["y_brand"])
                                        want = [bottom_of(L) + L["rows"] * L["pitch"]
                                                + i * L["pitch"] for i in range(len(anchors))]
                                        if anchors != want:
                                            add("I8 a switched-off row left a hole", c)
                                        # I8b the brand is ALWAYS strictly above every
                                        # drawn row below it
                                        others = anchors[:-1]
                                        if others and L["y_brand"] <= max(others):
                                            add("I8 the brand is not the card's top row", c)
                                        # I2 SAME SEAM: every pair of drawn rows is separated
                                        # by exactly one row gap. The card's extra air (the
                                        # blank rows the input asked for) is I8's business.
                                        if show_tp and show_sl:
                                            want_gap = L["pitch"] - L["fs_em"]
                                            seam1 = L["y_hunter"] - (L["y_trade"] + L["fs_em"])
                                            seam2 = L["y_brand"] - (L["y_hunter"] + L["fs_em"])
                                            if seam1 != want_gap or seam2 != want_gap:
                                                add("I2 the seams are not all one row gap", c)
                                        # I3 ceiling. Some input combinations cannot fit ANY
                                        # two-row card on a 320 px chart (24pt font, 60px
                                        # gap, 120px bottom margin) - those are counted and
                                        # reported, not asserted: the invariant is "the owner
                                        # never grants rows the chart cannot hold".
                                        if h > 0:
                                            base_top = (bottom_of(L) + L["drawn"] * L["pitch"]
                                                        + L["brand_em"] + L["top_pad"])
                                            if base_top > h:
                                                infeasible += 1
                                            elif L["y_brand"] + L["brand_em"] > h - L["top_pad"]:
                                                add("I3 brand row crosses the chart ceiling", c)
                                        # I6 one centre axis (1 px for the halves)
                                        centres = [L["x_brand"] + L["w_brand"] / 2.0]
                                        if show_tp:
                                            centres.append(L["x_trade"] + L["w_tp"] / 2.0)
                                        if show_sl:
                                            centres.append(L["x_hunter"] + L["w_hunter"] / 2.0)
                                        if max(centres) - min(centres) > 1.0:
                                            add("I6 the drawn rows are not centred on one axis", c)
                                        # I9 the axis is the WIDEST DRAWN row
                                        want_w = max(L["w_brand"],
                                                     L["w_tp"] if show_tp else 0,
                                                     L["w_hunter"] if show_sl else 0, 1)
                                        if L["card_w"] != want_w:
                                            add("I9 the centring axis is not the widest drawn row", c)
                                        # I7 the brand pair: no overlap, no gap
                                        if L["x_tr"] - L["x_ex"] != L["w_ex"]:
                                            add("I7 the TR/ex spacing is not the measured wEx", c)
                                        if h and L["rows"] > 0 and L["y_brand"] + L["brand_em"] > worst_top:
                                            worst_top = L["y_brand"] + L["brand_em"]
                                            worst_combo = (h, c)
    # I4 monotone: more rows never draws lower
    for gap in (0, 18, 60):
        prev = None
        for req in range(0, 25):
            L = card(8, gap, 25, req, 96, 900, lo, hi, 160, 160, 40, 40)
            if prev is not None and L["y_brand"] < prev:
                add("I4 more rows drew LOWER", "gap=%d rows=%d" % (gap, req))
            prev = L["y_brand"]
    return problems, {"worst_top": worst_top, "worst_combo": worst_combo,
                      "infeasible": infeasible}


def main():
    problems = []
    owner_problems, owner = check_owner()
    anchor_problems = check_anchor()
    measured_problems = check_measured()
    em_problems = check_raw_em()
    presence_problems = check_presence()
    decoupled_problems = check_decoupled()
    input_problems, defaults, lo, hi = check_inputs(owner if owner else "")
    bound_problems = check_row_bound()
    problems = {}
    for msg in (owner_problems + anchor_problems + measured_problems
                + em_problems + presence_problems + decoupled_problems + input_problems
                + bound_problems):
        problems.setdefault(msg, "")

    if lo is None:
        lo, hi = 0, 20

    if not QUIET:
        for label, plist in (("[owner] one owner for the card's Ys AND Xs", owner_problems),
                             ("[anchor] every piece is CORNER_RIGHT_LOWER/ANCHOR_RIGHT_LOWER", anchor_problems),
                             ("[measured] row widths measured, brand gap = wEx", measured_problems),
                             ("[raw em] PnlRawLineH owns the raw em", em_problems),
                             ("[presence] a switched-off row is removed by its writer", presence_problems),
                             ("[decoupled] the card answers to its own master, never the ATR overview", decoupled_problems),
                             ("[row bound] one owner, unknown size = no bound", bound_problems),
                             ("[inputs] defaults + clamp bounds read from the source", input_problems)):
            print("  %s %s%s" % ("ok  " if not plist else "FAIL", label,
                                 "" if not plist else " - %d problem(s)" % len(plist)))

    height_clamp = bool(owner and "GetCachedChartHeight()" in owner)
    model_problems, stats = check_geometry(lo, hi, height_clamp)
    for msg, combo in model_problems.items():
        problems.setdefault(msg, combo)

    combos = (len(FONTS) * len(GAPS) * len(MARGINS) * len(ROWREQ) * len(DPIS)
              * len(HEIGHTS) * len(WIDTHS) * 2 * 2)
    if SHOW_MODEL:
        print("  model: %d combos (font x gap x margin x rows x DPI x height x widths)" % combos)
        print("  model: %d of them cannot fit ANY two-row card on that chart height "
              "(user-input extremes, reported not asserted)" % stats["infeasible"])
        print("  model: worst brand-row top %s of %s"
              % (stats["worst_top"], stats["worst_combo"][0] if stats["worst_combo"] else "-"))
        # The shipped bug, quantified: `ex` advances 1112/1000 em in Arial Bold
        # (the metrics owner's table: 'e' 556 + 'x' 556), while the retired code
        # reserved `2.0 * brandSize * 0.7` px = 1.4 * brandSize for it.
        brand = (defaults.get("inpFontSize") or 8) + 6
        guess = 1.4 * brand
        for dpi in DPIS:
            real = int(round(1112 * em(brand, dpi) / 1000.0))
            print("  model: brandSize=%d at %d DPI -> `ex` is ~%d px wide, the retired "
                  "guess allowed %.1f px = %.1f px of OVERLAP (the measured owner: 0)"
                  % (brand, dpi, real, guess, max(0.0, real - guess)))

    if problems:
        for msg, combo in problems.items():
            print("  FAIL %s%s" % (msg, ("  e.g. %s" % combo) if combo else ""))
        print("\nchart label geometry: %d problem class(es) - the card can overlap, leave the "
              "chart, or draw off-axis" % len(problems))
        return 1

    # I5: the SHIPPED defaults must hold the whole card on the smallest chart
    font = defaults.get("inpFontSize")
    gap = defaults.get("inpATRTradeLabelRowGap")
    margin = defaults.get("inpLabelsMarginBottom")
    req = defaults.get("inpTrexStampGapRows")
    if None in (font, gap, margin, req):
        print("  FAIL I5 the shipped defaults could not be read")
        return 1
    L = card(font, gap, margin, req, 96, 320, lo, hi, 200, 160, 40, 40, height_clamp)
    if L["y_brand"] + L["brand_em"] > 320 - L["top_pad"]:
        print("  FAIL I5 the shipped defaults do not fit a 320px chart (brand top %d)"
              % (L["y_brand"] + L["brand_em"]))
        return 1
    if not QUIET:
        print("  ok   [geometry] %d combos: one pitch, one axis, no row past the ceiling" % combos)
        print("  ok   [defaults] font=%d rowGap=%d margin=%d rows=%d -> brand top %d of 320"
              % (font, gap, margin, req, L["y_brand"] + L["brand_em"]))

    print("\nchart label geometry: clean - one owner, one anchor, measured widths, "
          "clamp %d..%d and chart-aware" % (lo, hi))
    return 0


# --- negative control -------------------------------------------------------
# A gate that cannot fail proves nothing. `--selftest` doctors one file at a
# time and requires the matching check to catch the fault.
def selftest():
    real = dict(_PATCHED)
    cases = []

    stale = []

    def with_source(path, old, new):
        # A SEED THAT CANNOT FIND ITS ANCHOR IS A VACUOUS CONTROL. A refactor that
        # rewrites the line a seed patches used to leave the seed silently
        # no-op'ing and the case "passing" - so the anchor is required to exist
        # and its absence is reported as loudly as a missed fault.
        src = read(path)
        if old not in src:
            stale.append(old.strip().splitlines()[0][:80])
        _PATCHED.clear()
        _PATCHED.update({path: src.replace(old, new, 1)})

    def reset():
        _PATCHED.clear()
        _PATCHED.update(real)

    reset()
    cases.append(("the clean source passes the owner check", not check_owner()[0]))
    cases.append(("the clean source passes every check",
                  not check_owner()[0] and not check_anchor() and not check_measured()
                  and not check_raw_em() and not check_presence()
                  and not check_decoupled() and not check_row_bound()
                  and check_geometry(0, 20)[0] == {}))

    # 1. a writer lays the card out itself again - the card computed once per
    #    ROW, which is the shape the P-LBL-09 refactor removed
    with_source(LABELS, "   if(!L.showSL) {",
                "   STrexCardLayout L2;\n   TRexTradeCardLayout(plan, L2);\n"
                "   if(!L.showSL) {")
    cases.append(("a writer laying the card out itself is caught",
                  bool(check_owner()[0])))
    reset()

    # 1b. the same layout computed twice in one pass (wasted measurements)
    with_source(LABELS,
                "    TRexTradeCardLayout(plan, L);\n"
                "    CreateATRTradeLabel(labelPrefix, plan, L);",
                "    TRexTradeCardLayout(plan, L);\n"
                "    TRexTradeCardLayout(plan, L);\n"
                "    CreateATRTradeLabel(labelPrefix, plan, L);")
    cases.append(("the owner running twice per pass is caught", bool(check_owner()[0])))
    reset()

    # 1c. a writer stops consuming the layout (geometry comes from nowhere)
    with_source(LABELS,
                "bool DisplayTRexTitleBlock(const string labelPrefix, "
                "const STrexCardLayout &L) {",
                "bool DisplayTRexTitleBlock(const string labelPrefix) {")
    cases.append(("a writer not taking the layout is caught", bool(check_owner()[0])))
    reset()

    # 2. the brand half goes back to the top corner (the split card)
    with_source(LABELS, "InitATRChartLabel(name, CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER);\n    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(8, xPos));\n    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(8, yPos));",
                         "InitATRChartLabel(name, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER);\n    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(8, xPos));\n    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(8, yPos));")
    cases.append(("a top-anchored piece in the bottom stack is caught", bool(check_anchor())))
    reset()

    # 2b. a switched-off row that keeps its object (the stale row, P-LBL-09)
    with_source(LABELS, "       ObjectDelete(0, tpName);",
                        "       ObjectDelete(0, \"\");")
    cases.append(("a row that survives its switch is caught", bool(check_presence())))
    reset()

    # 2c. the delete duplicated at the call site (two owners)
    with_source(LABELS, "    DisplayTradePlanTopRows(labelPrefix, plan, L);\n}",
                        "    DisplayTradePlanTopRows(labelPrefix, plan, L);\n"
                        "    ObjectDelete(0, labelPrefix + \"TREX_Hunter\");\n}")
    cases.append(("a duplicated row delete is caught", bool(check_presence())))
    reset()

    # 2d. the caller-decides shape comes back (`if(L.showSL) ... else delete`)
    with_source(LABELS, "    DisplayTradePlanTopRows(labelPrefix, plan, L);\n}",
                        "    if(L.showSL)\n"
                        "        DisplayTradePlanTopRows(labelPrefix, plan, L);\n}")
    cases.append(("the caller deciding a row's presence is caught",
                  bool(check_presence())))
    reset()

    # 3. the guessed brand gap comes back (the shipped letter overlap)
    with_source(LABELS, "   L.xTR     = L.xEx + wEx;              // measured: exactly 0 px of overlap",
                        "   L.xTR     = L.xEx + (int)(2.0 * brandSize * 0.7);")
    cases.append(("the retired guessed brand gap is caught", bool(check_measured())))
    reset()

    # 4. a writer stops using the measured text owner
    with_source(LABELS, "TradePlanTPRowText(plan), inpATRTradeRowColor",
                        "\"#SL:-1 #TP1+1 #TP2+1 #TP3+1\", inpATRTradeRowColor")
    cases.append(("a writer not drawing the measured text is caught", bool(check_owner()[0])))
    reset()

    # 5. the single-space #SL/TP row comes back (the "stuck together" report)
    with_source(LABELS, "StringFormat(\"#SL:-%d  #TP1+%d  #TP2+%d  #TP3+%d\"",
                        "StringFormat(\"#SL:-%d #TP1+%d #TP2+%d #TP3+%d\"")
    cases.append(("a single-space #SL/TP row is caught", bool(check_measured())))
    reset()

    # 6. raw em arithmetic duplicated outside the metrics owner
    with_source(LABELS, "int em      = PnlRawLineH(fs);",
                        "int em      = (int)MathRound(fs * (double)PnlDpi() / 72.0);")
    cases.append(("a duplicated raw-em computation is caught", bool(check_raw_em())))
    reset()

    # 7. the owner stops reading the knob (a dead control, P-UI-47)
    with_source(LABELS, "int rows = inpTrexStampGapRows;", "int rows = 1;")
    cases.append(("an unread knob input is caught", bool(check_owner()[0])))
    reset()

    # 7b. the card goes back to the shared grid spacing (the stretched card)
    with_source(LABELS, "   int gap     = inpATRTradeLabelRowGap;",
                        "   int gap     = inpLabelRowGap;")
    cases.append(("the card reading the grid's row gap is caught",
                  bool(check_owner()[0])))
    reset()

    # 7c. the seam's upper bound disappears (an input from the dialog)
    with_source(LABELS, "   if(gap > TREX_CARD_MAX_ROW_GAP) gap = TREX_CARD_MAX_ROW_GAP;\n", "")
    cases.append(("an unbounded card seam is caught", bool(check_owner()[0])))
    reset()

    # 7d. the floor's lower bound disappears (the card through the floor)
    with_source(LABELS, "   if(bottom < 0) bottom = 0;\n", "")
    cases.append(("an unbounded card floor is caught", bool(check_owner()[0])))
    reset()

    # 8. the chart-height bound is dropped
    with_source(LABELS, "   int chartH = GetCachedChartHeight();", "   int chartH = 0;")
    model, _ = check_geometry(0, 20, height_clamp=False)
    cases.append(("dropping the chart-height clamp is caught",
                  bool(check_owner()[0]) and bool(model)))
    reset()

    # 9. a clamp whose condition lies about its value
    with_source(CONSTS, "#define TREX_CARD_MAX_GAP_ROWS 20", "#define TREX_CARD_MAX_GAP_ROWS 60")
    _got, honest = owner_clamps(body(read(LABELS), "void TRexTradeCardLayout("))
    bounds, _ = owner_clamps(body(read(LABELS), "void TRexTradeCardLayout("))
    cases.append(("a widened bound is picked up from the constants file",
                  honest and bounds[1] == 60))
    reset()

    # 10. the bound constant disappears
    with_source(CONSTS, "#define TREX_CARD_MAX_GAP_ROWS 20", "#define TREX_CARD_MAX_GAP_ROWSX 20")
    problems, _defaults, _lo, _hi = check_inputs(body(read(LABELS), "void TRexTradeCardLayout("))
    cases.append(("a renamed/missing bound constant is caught", bool(problems)))
    reset()

    # 12. the trade card is re-coupled to the ATR overview - all four faces
    #     (P-UI-84). Each seed patches ONE face and the check must catch it.
    with_source(LABELS,
                "    if(!inpShowATRTradeLabels) {\n        // Defensive wipe",
                "    if(!inpShowATRTradeLabels || !g_atrLabelsVisible) {\n"
                "        // Defensive wipe")
    cases.append(("the card's wipe gate back on the ATR overview is caught",
                  bool(check_decoupled())))
    reset()

    with_source(LABELS,
                "    if(!inpShowATRTradeLabels || IsIndicatorHidden()) return;\n"
                "    static uint s_lastMs = 0;",
                "    if(!inpShowATRTradeLabels || !g_atrLabelsVisible || IsIndicatorHidden()) return;\n"
                "    static uint s_lastMs = 0;")
    cases.append(("the card's pump back on the ATR overview is caught",
                  bool(check_decoupled())))
    reset()

    with_source(LABELS,
                "    bool cardOn = (inpShowATRTradeLabels && !IsIndicatorHidden());\n"
                "    long tradeTF = cardOn ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;",
                "    long tradeTF = (shouldShow && inpShowATRTradeLabels) ? "
                "OBJ_ALL_PERIODS : OBJ_NO_PERIODS;")
    cases.append(("the card's mask writer back on shouldShow is caught",
                  bool(check_decoupled())))
    reset()

    with_source(EVENTS,
                "        DisplayATRTradeLabels(objectPrefix);\n"
                "        // Own layer: repaint AFTER the clear",
                "        if(g_atrLabelsVisible) DisplayATRTradeLabels(objectPrefix);\n"
                "        // Own layer: repaint AFTER the clear")
    cases.append(("an EventHandlers call site guarded by the ATR overview is caught",
                  bool(check_decoupled())))
    reset()

    # 10b. the row bound goes back to a raw chart-size subtraction (P-UI-94): an
    #      unknown width is negative, and every column wraps
    with_source(LABELS, "    int maxWidth = LabelRowMaxWidth(startXPos);",
                        "    int maxWidth = GetCachedChartWidth() - startXPos * 2;")
    cases.append(("a hand-derived row bound is caught", bool(check_row_bound())))
    reset()

    # 10c. the wrap test stops asking for the "no bound" sentinel
    with_source(LABELS, "if(maxWidth > 0 && currentXPos + labelWidth + xStep > maxWidth) {",
                        "if(currentXPos + labelWidth + xStep > maxWidth) {")
    cases.append(("an unguarded wrap test is caught", bool(check_row_bound())))
    reset()

    # 10d. the owner stops answering 0 for an unknown chart width
    with_source(LABELS, "    if(cw <= 0) return 0;",
                        "    if(cw <= 0) cw = 0;")
    cases.append(("an owner that no longer answers 0 is caught", bool(check_row_bound())))
    reset()

    # 11. the model's own invariants have teeth
    cases.append(("an off-axis layout is caught", bool(check_geometry(0, 20, centred=False)[0])))
    cases.append(("a model without the clamp is caught", bool(check_geometry(0, 20, forget_clamp=True)[0])))
    cases.append(("negative rows in the model are caught", bool(check_geometry(-5, 20)[0])))
    cases.append(("the retired guess is caught by the model",
                  card(8, 18, 25, 0, 96, 900, 0, 20, 160, 160, 40, 40, old_guess=True)["x_tr"]
                  != card(8, 18, 25, 0, 96, 900, 0, 20, 160, 160, 40, 40)["x_ex"] + 40))
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
