#!/usr/bin/env python3
"""
sim-strip-panels.py — RENDER THE STRIP'S THREE SURFACES the way MT4 will draw
them, from the SAME literals the MQL compiles.

  python tools/sim-strip-panels.py              -> tools/sim-strip-panels.html
  python tools/sim-strip-panels.py out.html     -> that file
  python tools/sim-strip-panels.py out.html -p  -> ...plus strip-*.png rasters

NOTHING below is hand-written geometry. Every number is read out of the source
that ships it:

  Biotak/DrawStrip.mqh        DSTRIP_* geometry (the gate's own reader)
  Biotak/ConstantsAndEnums.mqh  the palette (BioPickColor) + BIO_CLR_* ink
  Biotak/BiotakPanels.mqh     the cards' PNL_* seats, via panel-mt4-sim.py

and every pixel of chrome is the real bake out of Files/Icons/ — MT4 cannot
blur, round a corner or gradient at runtime, so the appearance IS the BMP bytes
placed at the source's own seats.

The settings panel is NOT re-modelled here: tools/sim-gear-panel.py already
mirrors DrawStripGearLayout/DrawStripGearPaint and is what `check-gear-panel.py`
gates on, so this imports it and renders through it. One mirror per surface.

Caveat — text. MT4 renders OBJ_LABEL with Arial at its own DPI; this proof uses
the pt->px conversion panel-mt4-sim.py proved against the terminal, so layout is
exact and glyph shapes are approximate.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# TH3_ROOT: render from another tree's sources and bakes — tools/before-after.py
# imports this module twice, once per tree. Unset, this is the repo it lives in.
ROOT = os.environ.get("TH3_ROOT") or os.path.dirname(HERE)
sys.path.insert(0, HERE)

_s = importlib.util.spec_from_file_location("mt4sim", os.path.join(HERE, "legacy", "panel-mt4-sim.py"))
mt4 = importlib.util.module_from_spec(_s)
_s.loader.exec_module(mt4)

_s2 = importlib.util.spec_from_file_location("gearpanel", os.path.join(HERE, "sim-gear-panel.py"))
G = importlib.util.module_from_spec(_s2)
_s2.loader.exec_module(G)

Canvas = mt4.Canvas

DRAWSTRIP = os.path.join(ROOT, "Biotak", "DrawStrip.mqh")
CONSTS = os.path.join(ROOT, "Biotak", "ConstantsAndEnums.mqh")


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


DS = "\n".join(t[2] for t in mql_unit_lines(DRAWSTRIP))
CN = open(CONSTS, encoding="utf-8", errors="replace").read()


# ── the geometry: DSTRIP_* straight out of DrawStrip.mqh ────────────────────
# P-DRAW-116 left five of these as ALIASES of the cards' own table
# (`#define DSTRIP_SKIN_M PNL_MARGIN`), and this reader only understood plain
# digits — so it died with `KeyError: 'DSTRIP_SKIN_M'` the day the aliases landed,
# which took the strip page, the icon sheet and before/after with it. An alias is
# resolved FROM ITS OWNER (CardMetrics.mqh, the one table BiotakPanels and
# DrawStrip both read), never re-typed here: a second literal is exactly the
# defect P-DRAW-116 removed.
CARD_METRICS = os.path.join(ROOT, "Biotak", "CardMetrics.mqh")


def card_defines():
    try:
        text = open(CARD_METRICS, encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    return {m.group(1): int(m.group(2))
            for m in re.finditer(r"#define\s+((?:PNL|BIO)_\w+)\s+(-?\d+)", text)}


CARDS = card_defines()


def ds_defines():
    rx = re.compile(r"#define\s+(DSTRIP_\w+)\s+(-?\d+|[A-Za-z_]\w*)")
    out = {}
    for line in DS.split("\n"):
        m = rx.match(line.strip())
        if not m:
            continue
        val = m.group(2)
        if re.fullmatch(r"-?\d+", val):
            out[m.group(1)] = int(val)
        elif val in CARDS:
            out[m.group(1)] = CARDS[val]
    return out


D = ds_defines()
PAD = D["DSTRIP_PAD"]
CELL = D["DSTRIP_CELL"]
GAP = D["DSTRIP_GAP"]
SWATCH = D["DSTRIP_SWATCH"]
HEAD_AIR = D["DSTRIP_HEAD_AIR"]
SEP_W = D["DSTRIP_SEP_W"]
SEP_H = D["DSTRIP_SEP_H"]
SEP_AIR = D["DSTRIP_SEP_AIR"]
ACT_N = D["DSTRIP_ACT_N"]
SKIN_M = D["DSTRIP_SKIN_M"]          # 14 — the baked shadow margin
SKIN_TOPT = D["DSTRIP_SKIN_TOPT"]    # 58 — cap height INCLUDING the margin
SKIN_BOTT = D["DSTRIP_SKIN_BOTT"]    # 18
SKIN_MID = D["DSTRIP_SKIN_MID"]      # 42 — one band
SKIN_CAP = D["DSTRIP_SKIN_CAP"]      # 28 — corner cap
PICK_CELL = D["DSTRIP_PICK_CELL"]
PICK_GAP = D["DSTRIP_PICK_GAP"]
PICK_ROW = D["DSTRIP_PICK_ROW"]
PICK_MAX = D["DSTRIP_PICK_MAX"]
PREC_LW = D["DSTRIP_PREC_LW"]
POP_EDIT_H = D["DSTRIP_POP_EDIT_H"]
HEX_W = D["DSTRIP_HEX_W"]
OP_VW = D["DSTRIP_OP_VW"]
TRK_H = D["DSTRIP_TRK_H"]
KNOB_W = D["DSTRIP_KNOB_W"]
KNOB_H = D["DSTRIP_KNOB_H"]
BOARD_HDR = D["DSTRIP_BOARD_HDR"]
PHEAD_XW = D["DSTRIP_PHEAD_XW"]
BPIN_XW = D["DSTRIP_BPIN_XW"]
BIOPICK_COLS = 8                      # ConstantsAndEnums.mqh:877

# ── the ink: the strip's aliases, restated as CSS (ConstantsAndEnums 1000-1020) ──
INK = "rgba(243,246,251,1)"      # BIO_CLR_INK
MUTED = "rgba(140,150,166,1)"    # BIO_CLR_MUTED
LABEL = "rgba(203,212,226,1)"    # BIO_CLR_LABEL
ACCENT = "rgba(255,194,71,1)"    # BIO_CLR_ACCENT
FIELD = "rgba(24,29,39,1)"       # BIO_CLR_FIELD
FIELD_BD = "rgba(51,60,76,1)"    # BIO_CLR_FIELD_BD
LINE_C = "rgba(34,40,50,1)"      # BIO_CLR_HAIRLINE
DEL_INK = "rgba(255,138,138,1)"  # DSTRIP_CLR_DEL_INK
PICK_RIM = "rgba(62,72,92,1)"    # DSTRIP_CLR_PICK
PLATE = "rgba(23,28,37,1)"       # BIO_CLR_PANEL
CARD = "rgba(29,34,44,1)"        # BIO_CLR_CARD


# ── the palette: BioPickColor's own table, page 0 = the board's 8 x 8 ───────
def bio_pick():
    out, body = [], CN[CN.index("color BioPickColor"):]
    body = body[:body.index("};")]
    for m in re.finditer(r"C'(\d+),(\d+),(\d+)'|BIO_CLR_BRAND", body):
        out.append((255, 171, 0) if not m.group(1) else (int(m.group(1)), int(m.group(2)), int(m.group(3))))
    return out


PAL = bio_pick()
PAGE0 = PAL[:BIOPICK_COLS * 8] if len(PAL) >= 64 else PAL
assert PAGE0, "BioPickColor parsed empty — the palette table moved"


def rgb(c):
    return "rgb(%d,%d,%d)" % c


# ── THE ART'S OWN SIZE, AND THE SEAT THAT CENTRES IT ─────────────────────────
# MT4 crops a bitmap label at its NATIVE size and never scales it, and
# DrawStripFaceZ places it at x+(w-pw)/2, y+(h-ph)/2 (integer arithmetic on two
# ints). A browser does the opposite by default — `width:100%` STRETCHES — so
# every face here has to be placed at its own size or the proof lies about how
# big every glyph is: the shipped chip is 26px and the shipped icons 24/15px
# inside a 32px cell, not 32.
_NATIVE = {}


def native(res):
    if res not in _NATIVE:
        _NATIVE[res] = mt4.read_bmp(os.path.join(mt4.ICONS, res))[:2]
    return _NATIVE[res]


def face(c, res, x, y, w, h, z):
    """DrawStripFaceZ, verbatim: the art at its own size, centred in the cell."""
    pw, ph = native(res)
    c.img(res, x + (w - pw) // 2, y + (h - ph) // 2, pw, ph, z)


# ── THE LEGIBILITY FLOOR (ConstantsAndEnums BioLum/BioContrast/BioSwatchBorder)
# Every colour cell's rim is one of two answers, and neither is a guess: the
# accent marks the cell the drawing wears, and every other rim is the floor's
# own verdict on that swatch. Mirrored here because the proof must paint the
# same rim MT4 will — a hand-picked grey was what the old proof wore.
_BIO_MIN_CONTRAST = 1.7
PANEL_RGB = (23, 28, 37)     # BIO_CLR_PANEL
CARD_RGB = (29, 34, 44)      # BIO_CLR_CARD
MUTED_RGB = (140, 150, 166)  # BIO_CLR_MUTED
HAIRLINE_RGB = (34, 40, 50)  # BIO_CLR_HAIRLINE


def _lum(c):
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def contrast(a, b):
    la, lb = _lum(a), _lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def swatch_border(fill, backdrop):
    """BioSwatchBorder: the rim a swatch of `fill` must carry on `backdrop`."""
    return MUTED if contrast(fill, backdrop) < _BIO_MIN_CONTRAST else LINE_C


def ring_ink(col, backdrop):
    """StrapRingInk: the BORDER colour while it reads against the plate, the
    legibility floor's own outline when it does not."""
    return MUTED if contrast(col, backdrop) < _BIO_MIN_CONTRAST else rgb(col)


# ══════════════════════════════════════════════════════════════════════════
# THE 9-SLICE PLATE (DrawStripSkinPaintAt). MT4 crops a bitmap label and never
# scales it, so a plate is: one top cap, k 42px mid bands, one bottom cap. The
# law is 48 + 42k (DrawStrip.mqh:3077) — k = (h - 48) / 42, and a height that
# misses it falls back to the legacy flat rect.
# ══════════════════════════════════════════════════════════════════════════
def plate(c, fam, x, y, w, h, z=0):
    """fam 1 = the strip's ds_* set, fam 2 = the board's own (same bakes)."""
    k = (h - 48) // SKIN_MID
    exact = (h - 48) % SKIN_MID == 0
    gw = w + 2 * SKIN_M
    if exact:
        c.img("ds_top_l.bmp", x - SKIN_M, y - SKIN_M, SKIN_CAP, SKIN_TOPT, z)
        c.img("ds_top_m.bmp", x - SKIN_M + SKIN_CAP, y - SKIN_M, gw - 2 * SKIN_CAP, SKIN_TOPT, z)
        c.img("ds_top_r.bmp", x + w + SKIN_M - SKIN_CAP, y - SKIN_M, SKIN_CAP, SKIN_TOPT, z)
        for i in range(k):
            by = y + SKIN_TOPT - SKIN_M + i * SKIN_MID
            c.img("ds_mid_l.bmp", x - SKIN_M, by, SKIN_CAP, SKIN_MID, z)
            c.rect(x, by, w, SKIN_MID, PLATE, z)
            c.img("ds_mid_r.bmp", x + w + SKIN_M - SKIN_CAP, by, SKIN_CAP, SKIN_MID, z)
        by = y + h - 4
        c.img("ds_bot_l.bmp", x - SKIN_M, by, SKIN_CAP, SKIN_BOTT, z)
        c.img("ds_bot_m.bmp", x - SKIN_M + SKIN_CAP, by, gw - 2 * SKIN_CAP, SKIN_BOTT, z)
        c.img("ds_bot_r.bmp", x + w + SKIN_M - SKIN_CAP, by, SKIN_CAP, SKIN_BOTT, z)
        return "ds_* eight-piece  %dx%d  (48+42*%d)" % (gw, h + 2 * SKIN_M, k)
    c.rect(x, y, w, h, PLATE, z, border=LINE_C)
    return "legacy flat rect (height off the 48+42k law)"


# ══════════════════════════════════════════════════════════════════════════
# LEVEL 1 — THE QUICK ROW. DrawStripLayout (DrawStrip.mqh:3006) arithmetic,
# painted the way DrawStripPaint (5365+) paints it: the plate, then grip, name,
# the two separators, the value cells (the colour seat is a RING), the four
# chrome cells.
# ══════════════════════════════════════════════════════════════════════════
DEMO_NAME = "Rectangle 1"
DEMO_ACT = ["bk_more.bmp", "bk_gear.bmp", "gl_pin_m.bmp", "bk_del.bmp"]
#--- THE ONE STATE THIS FRAME SHOWS. A cell's rim is state, so a demo that
#--- leaves it implicit compares two different frames and calls the difference
#--- a defect. These follow the mock's own state (its `.pick` seat, its
#--- `.cell.on`, its `.gear-open`), so both columns render the same moment.
#---   colour seat  : its board is OPEN   -> ACCENT ring + the gold chip
#---   half / back   : ON (DrawStripSlotOn) -> ACCENT rim + the gold chip
#---   ext / lock    : OFF                 -> the plate tone IS the rim (no rim)
#---   gear          : open                -> ACCENT rim + the gold chip
#---   pin           : not pinned          -> no rim + the muted face, which is
#---                     the face the mock carries too (gl_pin_m.bmp)
DEMO_PICK_OPEN = True          # s_dsPicker == DRAW_SLOT_COLOR
#--- the per-kind rows' two colours (see strip_cells): the drawing's BORDER and
#--- its INTERIOR, deliberately different so the merged colour cell shows both.
KIND_BORDER = PAGE0[3]         # 76,141,255 — the palette's blue
KIND_FILL = PAGE0[0]           # 255,171,0 — the palette's amber
DEMO_ACT_ON = [False, True, False, False]    # MORE, GEAR(open), PIN, DEL
DEMO_BDOCK = True              # s_dsBDock: the board's own pin, docked

# ══ THE ROW'S CELLS COME OUT OF THE SOURCE, NOT OUT OF THIS FILE ══════════
# DrawStripAllSlotAt walks the SLOT INDICES ascending with four exceptions and
# appends LEVELS last, so the order of a row is a fact of that function:
#   MORE never shows;  COLOR folds into FILLCLR on a merged kind;  BOXHALF and
#   EXTEND are skipped in the walk and served right after FILL;  the quick cap
#   cuts the tail. A Box therefore reads WIDTH · STYLE · FILL · HALF · EXTEND ·
#   LOCK · BACK · FILLCLR — the colour seat is at INDEX 10 and lands LAST, and
#   the hand-picked row this file carried before (colour first, five cells) was
#   a second and wrong answer to a question the module already answers.
SLOT = G.SLOT                       # DRAW_SLOT_* -> its number
SLOT_NAME = G.SLOT_NAME             # number -> the bare name
SLOT_N = G.DRAW_SLOT_N
QUICK_CAP = D["DSTRIP_QUICK_CAP"]
SLOT_LEVELS = int(re.search(r"#define\s+DSTRIP_SLOT_LEVELS\s+\((-?\d+)\)", DS).group(1))
#--- DRAW_WIDTH_MIN..MAX and the style/ray clamps, from the source's own table
W_MIN = int(re.search(r"#define\s+DRAW_WIDTH_MIN\s+(\d+)", G.DT_TEXT).group(1))
DEMO_W = W_MIN                      # the thinnest hairline the strip can show
DEMO_STYLE = 0
DEMO_RAY = 1                        # 0..3 = the two ray flags' four states
#--- the demo's toggles: OFF everywhere except the two the mock lights (a Box's
#--- HALF and BACK), because the mock's own frame is the frame being compared.
DEMO_ON = {("DK_RECT", "BOXHALF"): True, ("DK_RECT", "BACK"): True}


def kind_has_levels(kind):
    """DrawKindHasLevels(k): the six kinds whose look lives on per-level colours."""
    body = G._fn_body(G.DT, r"bool\s+DrawKindHasLevels\s*\([^)]*\)")
    return kind in re.findall(r"DK_\w+", body)


def kind_caps(kind):
    """DrawKindCaps(k) as the set of slot numbers (DrawSlotAvailable's own test)."""
    return G.parse_kind_caps(kind)


def kind_merged(kind, caps):
    """DrawStripMergedColor: SeatAvail(FILLCLR) && DrawSlotAvailable(COLOR).
    The channel's finer test needs the HELD OBJECT's MT4 type, which a header
    cannot answer; an OBJ_CHANNEL has an interior, so the demo answers true."""
    return SLOT["DRAW_SLOT_FILLCLR"] in caps and SLOT["DRAW_SLOT_COLOR"] in caps


def strip_slots_all(kind):
    """DrawStripAllSlotAt's whole walk, in order, before the quick cap."""
    caps = kind_caps(kind)
    merged = kind_merged(kind, caps)
    out = []
    for s in range(SLOT_N):
        if s == SLOT["DRAW_SLOT_MORE"]:
            continue
        if merged and s == SLOT["DRAW_SLOT_COLOR"]:
            continue
        if s in (SLOT["DRAW_SLOT_BOXHALF"], SLOT["DRAW_SLOT_EXTEND"]):
            continue
        if s not in caps:
            continue
        out.append(s)
        if s == SLOT["DRAW_SLOT_FILL"]:
            for x in (SLOT["DRAW_SLOT_BOXHALF"], SLOT["DRAW_SLOT_EXTEND"]):
                if x in caps:
                    out.append(x)
    if kind_has_levels(kind):
        out.append(SLOT_LEVELS)
    return merged, out


def strip_slots(kind):
    """The quick row: the walk cut at DSTRIP_QUICK_CAP. The rest is the
    more-popover's own (DrawStripOverflowSlotAt)."""
    merged, allslots = strip_slots_all(kind)
    return merged, allslots[:QUICK_CAP], allslots



# ── EVERY KIND, not only the box. The list is the enum and the label is
# DrawKindName — both read, so a kind added to the toolbar shows up here by
# itself and a kind this file forgot cannot go unnoticed.
KIND_NAMES = {}


def draw_kinds():
    m = re.search(r"enum\s+EDrawKind\s*\{(.*?)\}", G.DT, re.S)
    body = m.group(1)
    out = []
    for m in re.finditer(r"^\s*(DK_\w+)\s*(?:=|,)", body, re.M):
        k = m.group(1)
        if k not in ("DK_NONE", "DK_COUNT") and k not in out:
            out.append(k)
    return out


def kind_name(kind):
    """DrawKindName(k): the strip's own word for the kind ("Box", "Fibo", …)."""
    if kind not in KIND_NAMES:
        body = G._fn_body(G.DT, r"string\s+DrawKindName\s*\([^)]*\)")
        m = re.search(r"case\s+%s\s*:\s*return\s+\"([^\"]*)\"" % kind, body)
        KIND_NAMES[kind] = m.group(1) if m else kind
    return KIND_NAMES[kind]


KINDS = draw_kinds()


def slot_face(kind, slot, on=None):
    """DrawStripIconRes(slot, obj) with the demo's own values for the families
    whose face carries a VALUE (a width, a style, a ray state, an ON arm)."""
    n = SLOT_NAME.get(slot, "LEVELS" if slot == SLOT_LEVELS else "")
    on = (DEMO_ON if on is None else on).get((kind, n), False)
    if slot == SLOT_LEVELS:
        return "bk_levels.bmp"
    if n == "WIDTH":  return "bk_w%d.bmp" % DEMO_W
    if n == "STYLE":  return "bk_style%d.bmp" % DEMO_STYLE
    if n == "RAY":    return "bk_ray%d.bmp" % DEMO_RAY
    if n == "FILL":   return "bk_fill_on.bmp" if on else "bk_bucket.bmp"
    if n == "BOXHALF":return "bk_half_on.bmp" if on else "bk_half_off.bmp"
    if n == "EXTEND": return "bk_ext_on.bmp" if on else "bk_ext_off.bmp"
    if n == "LOCK":   return "bk_lock_on_g.bmp" if on else "bk_lock_off.bmp"
    #--- P-UI-131: the BACK seat is ONE shape in two inks, like every other toggle in
    #--- the row (`bk_lock_off`/`bk_lock_on_g`, `bk_ext_off`/`bk_ext_on`). The mock used
    #--- to draw a grey chevron face (`gl_layers_m`, 26 px) against the terminal's amber
    #--- one (`bk_back_on`, 24 px) — a mock that differs from the chart is how a
    #--- two-glyph control survived review: the preview agreed with itself.
    if n == "BACK":   return "bk_back_on.bmp" if on else "bk_back_off.bmp"
    if n == "FONT":   return "gl_textsize_m.bmp"
    if n == "GLYPH":  return "bk_glyph.bmp"
    return ""


def strip_cells(kind, on=None, border=None, fill=None):
    """The quick row of `kind` as cells the painter can place.

    A colour seat is the MERGED one (its ring is the border's colour and its
    centre the interior's) or the lone COLOR of a kind with no interior — which
    the paint draws as a ring with the PLATE tone inside ("a ring with a hole").
    `border`/`fill` are the demo drawing's two colours: the defaults (the first
    swatch for both) keep section 1 on the frame the mock was drawn for, and the
    per-kind rows pass two DIFFERENT colours, because a merged seat painted in
    one colour proves nothing about the two roles it carries.
    """
    merged, slots, _all = strip_slots(kind)
    on = DEMO_ON if on is None else on
    border = PAGE0[0] if border is None else border
    fill = PAGE0[0] if fill is None else fill
    cells = []
    for s in slots:
        n = SLOT_NAME.get(s, "LEVELS" if s == SLOT_LEVELS else "?")
        is_color = (s in (SLOT["DRAW_SLOT_COLOR"], SLOT["DRAW_SLOT_FILLCLR"]))
        cells.append(dict(
            slot=s, name=n, color=is_color,
            ring=border,
            mid=fill if merged else None,
            res="" if is_color else slot_face(kind, s, on),
            on=on.get((kind, n), False)))
    return cells


DEMO_CELLS = strip_cells("DK_RECT")          # the frame the mock was drawn on


def strip_layout(cells=None, name=DEMO_NAME):
    cells = DEMO_CELLS if cells is None else cells
    x = PAD
    x += CELL                                  # grip
    x += HEAD_AIR
    badge_x = x
    x += mt4.text_w(name, 9)                   # the name's own ink
    x += SEP_AIR
    sep0 = x
    x += SEP_W + SEP_AIR
    cx = []
    for i in range(len(cells)):
        if i:
            x += GAP
        cx.append(x)
        x += CELL
    x += SEP_AIR
    sep1 = x
    x += SEP_W + SEP_AIR
    ax = []
    for a in range(ACT_N):
        if a:
            x += GAP
        ax.append(x)
        x += CELL
    x += PAD
    return dict(badge=badge_x, sep=(sep0, sep1), cx=cx, ax=ax, w=x,
                h=PAD + CELL + PAD)


def paint_strip(cells=None, name=DEMO_NAME, act_on=None, pick_open=DEMO_PICK_OPEN):
    cells = DEMO_CELLS if cells is None else cells
    act_on = DEMO_ACT_ON if act_on is None else act_on
    L = strip_layout(cells, name)
    c = Canvas()
    c.origin(0, 0)
    note = plate(c, 1, 0, 0, L["w"], L["h"])
    ry = PAD
    #--- grip. The real writer is `DrawStripBtn(hg, …, plate, LABEL, plate)`:
    #--- BORDER_COLOR is the PLATE tone, so the cell carries NO visible rim. A
    #--- rim the colour of the fill is what most of this row wears (P-DRAW-66),
    #--- and drawing it as a hairline was the proof's own invention.
    c.rect(PAD, ry, CELL, CELL, PLATE, 1500, border=PLATE)
    face(c, "pnl_chip.bmp", PAD, ry, CELL, CELL, 1501)
    face(c, "bk_grip.bmp", PAD, ry, CELL, CELL, 1503)
    #--- the badge: the title's own ink, band-centred (StrapInkY over the row)
    c.text(L["badge"], ry + (CELL - mt4.font_px(9)) // 2, name, LABEL, 9, True, "lu", 1520)
    #--- the two group separators (identity | values | commands)
    for sx in L["sep"]:
        c.rect(sx, ry + (CELL - SEP_H) // 2, SEP_W, SEP_H, LINE_C, 1503)
    #--- value cells
    for i, cel in enumerate(cells):
        x = L["cx"][i]
        if cel["color"]:
            # P-DRAW-64a: the seat is the BORDER's ring, the centre the interior's
            bcol = cel["ring"]                 # DrawStripColorRead(obj, COLOR)
            ccol = cel["mid"]                  # None on a kind with no interior
            c.rect(x, ry, CELL, CELL, PLATE, 1500,
                   border=ACCENT if pick_open else ring_ink(bcol, PANEL_RGB))
            face(c, "pnl_chip_gold.bmp" if pick_open else "pnl_chip.bmp",
                 x, ry, CELL, CELL, 1501)
            sw = x + (CELL - SWATCH) // 2
            swy = ry + (CELL - SWATCH) // 2
            c.rect(sw, swy, SWATCH, SWATCH, rgb(ccol if ccol else PANEL_RGB), 1500,
                   border=ACCENT if pick_open else
                          swatch_border(ccol if ccol else PANEL_RGB, CARD_RGB))
            face(c, "ds_swatch24.bmp", sw, swy, SWATCH, SWATCH, 1501)
        else:
            on = cel["on"]
            # `if(DrawStripHasPicker(slot)) rim = PICK; else if(chipOn) rim = ACCENT`
            # — a cell carrying no picker shows no rim while it is OFF.
            c.rect(x, ry, CELL, CELL, PLATE, 1500, border=ACCENT if on else PLATE)
            face(c, "pnl_chip_gold.bmp" if on else "pnl_chip.bmp", x, ry, CELL, CELL, 1501)
            face(c, cel["res"], x, ry, CELL, CELL, 1503)
    #--- chrome: more / gear / pin / del. `DrawStripActRes` names the face; the
    #--- bin is `bk_del.bmp` like its neighbours — it is NOT a glyph. DSTRIP_CLR_DEL_INK
    #--- is the BUTTON's text colour and that button's text is "", so nothing of
    #--- the red reaches the chart: the destructive cue is the baked bin.
    for a in range(ACT_N):
        x = L["ax"][a]
        on = act_on[a]
        c.rect(x, ry, CELL, CELL, PLATE, 1500, border=ACCENT if on else PLATE)
        face(c, "pnl_chip_gold.bmp" if on else "pnl_chip.bmp", x, ry, CELL, CELL, 1501)
        face(c, DEMO_ACT[a], x, ry, CELL, CELL, 1503)
    return c, note, L


# ══════════════════════════════════════════════════════════════════════════
# LEVEL 2 — THE COLOUR BOARD. DrawStripLayout's colour branch (3055+):
# 8 x 8 page-0 grid, RECENT, then HEX and the OPACITY bar SHARING one band.
# Its own 9-slice plate, at its own rect (P-DRAW-48) — the strip never grows.
# ══════════════════════════════════════════════════════════════════════════
BOARD_PAD = PAD                                  # the board uses DSTRIP_PAD (8)
DEMO_RECENT = [PAGE0[0], PAGE0[3], PAGE0[10], PAGE0[1], PAGE0[7]]


def board_layout():
    n = len(PAGE0)
    rows = (n + BIOPICK_COLS - 1) // BIOPICK_COLS
    gw = BIOPICK_COLS * PICK_CELL + (BIOPICK_COLS - 1) * PICK_GAP
    h = 48 + PICK_ROW * (rows + 2)               # DrawStrip.mqh:3077
    return dict(w=gw + 2 * BOARD_PAD, h=h, rows=rows,
                recY=BOARD_HDR + rows * PICK_ROW,
                hexY=BOARD_HDR + (rows + 1) * PICK_ROW)


def paint_board():
    L = board_layout()
    c = Canvas()
    c.origin(0, 0)
    note = plate(c, 2, 0, 0, L["w"], L["h"])
    bx = BOARD_PAD
    # header (rides the skin's own 44 top cap)
    gx = bx
    gy = (BOARD_HDR - CELL) // 2
    # the header's carry grip is TWO faces and no button: no rim at all
    face(c, "pnl_chip.bmp", gx, gy, CELL, CELL, 1501)
    face(c, "bk_grip.bmp", gx, gy, CELL, CELL, 1503)
    inkY = (BOARD_HDR - mt4.font_px(9)) // 2
    hx = gx + CELL + 8
    #--- the header's right end is placed FIRST: the kind caption has to FIT in
    #--- front of the page seats, and that is where they start (P-UI-133 — with
    #--- the old order the caption of a long kind ran under the 1/2 label).
    xx = L["w"] - BOARD_PAD - PHEAD_XW
    px2 = xx - BPIN_XW - 2
    xy = (BOARD_HDR - PHEAD_XW) // 2
    pgx = px2 - 10 - 2 * 20
    hdr_fit = pgx - 24                      # the page LABEL's own left edge
    c.text(hx, inkY, "BORDER", ACCENT, 9, True, "lu", 1520)
    hx += mt4.text_w("BORDER", 9) + 12
    c.text(hx, inkY, "FILL", LABEL, 9, False, "lu", 1520)
    hx += mt4.text_w("FILL", 9) + 12
    #--- the caption is the KIND's own name, uppercased, wearing the code's own
    #--- dot (the demo's "RECTANGLE" was a second, wrong answer: a box reads
    #--- "· BOX"), PnlFit-ed into the room left of the page label.
    dot = " \u00b7 "                       # DrawStrip.mqh: a space, 183, a space
    c.text(hx, inkY, mt4.fit(dot + " " + kind_name("DK_RECT").upper(), 9, hdr_fit - hx),
           MUTED, 9, True, "lu", 1520)
    #--- close: `DrawStripBtn("…PHeadX", …, plate, LABEL, LINE, "x")` — MT4
    #--- centres a button's own text, so the glyph is centred in its 26px seat.
    c.rect(xx, xy, PHEAD_XW, PHEAD_XW, PLATE, 1500, border=LINE_C)
    c.text(xx + (PHEAD_XW - mt4.text_w("x", 9)) // 2, xy + (PHEAD_XW - mt4.font_px(9)) // 2,
           "x", LABEL, 9, False, "lu", 1520)
    #--- the pin: rim = docked ? ACCENT : LINE, face = gold while docked
    c.rect(px2, xy, BPIN_XW, BPIN_XW, PLATE, 1500,
           border=ACCENT if DEMO_BDOCK else LINE_C)
    face(c, "gl_pin_gold.bmp" if DEMO_BDOCK else "gl_pin_m.bmp",
         px2, xy, BPIN_XW, BPIN_XW, 1503)
    #--- the page seats: ink dims to the hairline on the page it cannot leave
    pgy = (BOARD_HDR - 20) // 2
    for k in range(2):
        edge = (k == 0)                    # BioPickPage()==0 on this frame
        c.rect(pgx + k * 20, pgy, 20, 20, PLATE, 1500,
               border=LINE_C)
        c.text(pgx + k * 20 + (20 - mt4.text_w("<" if k == 0 else ">", 8)) // 2,
               pgy + (20 - mt4.font_px(8)) // 2, "<" if k == 0 else ">",
               LINE_C if edge else LABEL, 8, False, "lu", 1520)
    c.text(pgx - 26, (BOARD_HDR - mt4.font_px(7)) // 2, "1/2", LABEL, 7, False, "lu", 1520)
    # the 8 x 8 page-0 grid
    for r in range(L["rows"]):
        for col in range(BIOPICK_COLS):
            pc = PAGE0[r * BIOPICK_COLS + col]
            x = BOARD_PAD + col * (PICK_CELL + PICK_GAP)
            y = BOARD_HDR + r * PICK_ROW + (PICK_ROW - PICK_CELL) // 2
            cur = (r == 0 and col == 0)
            # `DrawStripBtn(pn, …, pc, DrawStripInkOn(pc), cur ? ACCENT
            #  : BioSwatchBorder(pc, BIO_CLR_CARD))` + the ring/cell glass
            c.rect(x, y, PICK_CELL, PICK_CELL, rgb(pc), 1500,
                   border=ACCENT if cur else swatch_border(pc, CARD_RGB))
            face(c, "ds_ring32.bmp" if cur else "ds_cell32.bmp",
                 x, y, PICK_CELL, PICK_CELL, 1501)
    # RECENT
    ry = L["recY"] + (PICK_ROW - PICK_CELL) // 2
    c.text(BOARD_PAD, L["recY"] + (PICK_ROW - mt4.font_px(8)) // 2, "RECENT", MUTED, 8, False, "lu", 1520)
    for i, rc in enumerate(DEMO_RECENT):
        x = BOARD_PAD + PREC_LW + i * (PICK_CELL + PICK_GAP)
        cur = (rc == PAGE0[0])
        c.rect(x, ry, PICK_CELL, PICK_CELL, rgb(rc), 1500,
               border=ACCENT if cur else swatch_border(rc, CARD_RGB))
        face(c, "ds_ring32.bmp" if cur else "ds_cell32.bmp",
             x, ry, PICK_CELL, PICK_CELL, 1501)
    # HEX + the OPACITY bar, ONE band (P-DRAW-66)
    hy = L["hexY"]
    c.text(BOARD_PAD, hy + (PICK_ROW - mt4.font_px(8)) // 2, "HEX", MUTED, 8, False, "lu", 1520)
    ex = BOARD_PAD + PREC_LW
    ey = hy + (PICK_ROW - POP_EDIT_H) // 2
    c.rect(ex, ey, HEX_W, POP_EDIT_H, FIELD, 1500, border=FIELD_BD)
    c.text(ex + 6, ey + (POP_EDIT_H - mt4.font_px(8)) // 2, "#FFAB00", LABEL, 8, False, "lu", 1520)
    otx = ex + HEX_W + BOARD_PAD
    otw = L["w"] - BOARD_PAD - otx - OP_VW
    oty = hy + (PICK_ROW - TRK_H) // 2
    op = 72
    okx = otx + int(op / 100.0 * (otw - KNOB_W))
    c.rect(otx, oty, otw, TRK_H, LINE_C, 1500)
    if okx > otx:
        c.rect(otx, oty, okx - otx, TRK_H, ACCENT, 1501)
    c.rect(okx, hy + (PICK_ROW - KNOB_H) // 2, KNOB_W, KNOB_H, ACCENT, 1502, border=LINE_C)
    ov = "%d%%" % op
    c.text(L["w"] - BOARD_PAD - mt4.text_w(ov, 8), hy + (PICK_ROW - mt4.font_px(8)) // 2,
           ov, INK, 8, False, "lu", 1520)
    return c, note, L


# ══════════════════════════════════════════════════════════════════════════
# LEVEL 3 — THE SETTINGS PANEL. Not re-modelled: sim-gear-panel.py is the
# proven mirror and check-gear-panel.py gates on it. One mirror per surface.
# P-DRAW-117 (2026-10-01): the panel is an ACCORDION now — its nav is a column of
# group ROWS, and the group list is KIND-AWARE (a fibo opens LEVELS, a box does
# not). The caption below reads the name out of the mirror instead of a second
# list here: `GEAR_TABS` was one, and it went stale the day the tab row did.
# ══════════════════════════════════════════════════════════════════════════


def gear_for(kind):
    """sim-gear-panel.py re-imported with SIM_KIND=kind.

    The settings panel is KIND-AWARE: DrawStripGearContent asks DrawKindCaps, so
    a fibo's tabs are not a box's (the box's FILL/HALF/EXTEND rows, the fibo's
    level rows). One mirror, one import per kind — no second panel model.
    """
    prev = os.environ.get("SIM_KIND")
    os.environ["SIM_KIND"] = kind
    try:
        spec = importlib.util.spec_from_file_location(
            "gearp_" + kind, os.path.join(HERE, "sim-gear-panel.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    finally:
        if prev is None:
            os.environ.pop("SIM_KIND", None)
        else:
            os.environ["SIM_KIND"] = prev
    return mod


def panel_box(mod, kind, tab=0):
    """A settings panel for `kind`, tab `tab`, as (html, canvas, w, h)."""
    gl = mod.layout(tab)
    gc = mod.paint(gl, [], tab)
    w, h = gl["w"] + 2 * SKIN_M, gl["h"] + 2 * SKIN_M
    html = ("<div class='stage'><div class='cap'>%s — tab %s</div>"
            "<div class='wrap' style='width:%dpx;height:%dpx'>%s</div>"
            "<div class='facts'>kind %s · w %d · h %d · cardN %d · exact %s</div></div>") \
        % (kind_name(kind), gl["tab_name"], w, h, gc.to_html(),
           kind, gl["w"], gl["h"], gl["card_n"], gl["exact"])
    return html, gc, w, h


# ══════════════════════════════════════════════════════════════════════════
# THE PAGE
# ══════════════════════════════════════════════════════════════════════════
def stage(title, builder, facts):
    c, note, L = builder()
    W = L["w"] + 2 * SKIN_M
    H = L["h"] + 2 * SKIN_M
    box = ("<div class='stage'><div class='cap'>%s</div>"
           "<div class='wrap' style='width:%dpx;height:%dpx'>%s</div>"
           "<div class='facts'>%s · plate: %s</div></div>")
    return box % (title, W, H, c.to_html(), facts, note), c, W, H


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") \
        else os.path.join(HERE, "sim-strip-panels.html")
    want_png = "-p" in sys.argv or "--png" in sys.argv

    s_html, s_c, s_w, s_h = stage(
        "1 · QUICK ROW  (DrawStripLayout + DrawStripPaint)",
        paint_strip,
        "cell %d · gap %d · pad %d · head air %d · sep %dx%d air %d"
        % (CELL, GAP, PAD, HEAD_AIR, SEP_W, SEP_H, SEP_AIR))

    b_html, b_c, b_w, b_h = stage(
        "2 · COLOUR BOARD  (P-DRAW-48: its own card, the strip never grows)",
        paint_board,
        "grid %d x %d of %d · cell %d · pitch %d · header %d"
        % (BIOPICK_COLS, (len(PAGE0) + BIOPICK_COLS - 1) // BIOPICK_COLS,
           len(PAGE0), PICK_CELL, PICK_ROW, BOARD_HDR))

    gl = G.layout(0)
    gc = G.paint(gl, [], 0)
    g_html = ("<div class='stage'><div class='cap'>3 · SETTINGS PANEL — %s open</div>"
              "<div class='wrap' style='width:%dpx;height:%dpx'>%s</div>"
              "<div class='facts'>w %d · h %d · cardN %d · exact %s"
              " · groups %s  (tools/sim-gear-panel.py, the gate's own mirror)</div></div>") \
        % (gl["tab_name"], gl["w"] + 28, gl["h"] + 28, gc.to_html(),
           gl["w"], gl["h"], gl["card_n"], gl["exact"], ", ".join(G.TABS))

    # ══ 4 · EVERY KIND. The strip is kind-aware: DrawKindCaps decides which
    # controls a row carries, so a fibo's row is NOT a box's. One row per kind
    # the toolbar defines, in the enum's own order, built by the same painter as
    # section 1 (no second geometry for the other kinds).
    kind_html = ["<h1 style='margin-top:22px'>every kind — the quick row the strip builds for it</h1>",
                 "<div class='sub'>One fixed frame per kind: every toggle OFF, no picker, no "
                 "settings panel, badge = the demo drawing's name. Cells, their order and the "
                 "faces come from DrawStripAllSlotAt + DrawStripIconRes. The demo drawing wears "
                 "a <b style='color:#4C8DFF'>blue</b> border and an "
                 "<b style='color:#FFAB00'>amber</b> interior (palette swatches 4 and 1), because "
                 "the MERGED colour cell is a ring of the border's colour around the interior's — "
                 "one colour would not show it. A kind with no interior shows the ring alone, the "
                 "plate tone inside.</div>"]
    kind_c = []
    kind_w = []
    for k in KINDS:
        cells = strip_cells(k, {}, border=KIND_BORDER, fill=KIND_FILL)   # toggles OFF, two colours
        kc, _knote, kl = paint_strip(cells, kind_name(k) + " 1",
                                     act_on=[False] * ACT_N, pick_open=False)
        merged, slots, allslots = strip_slots(k)
        names = " · ".join(SLOT_NAME.get(s, "LEVELS" if s == SLOT_LEVELS else "?") for s in slots)
        over = len(allslots) - len(slots)
        facts = ("%s · %d cells%s%s · row %dpx"
                 % (names, len(slots),
                    " · merged colour" if merged else "",
                    " · %d in more-popover" % over if over else "",
                    kl["w"]))
        kind_html.append("<div class='stage'><div class='cap'>%s — %s</div>"
                         "<div class='wrap' style='width:%dpx;height:%dpx'>%s</div>"
                         "<div class='facts'>%s</div></div>"
                         % (kind_name(k), k, kl["w"] + 2 * SKIN_M, kl["h"] + 2 * SKIN_M,
                            kc.to_html(), facts))
        kind_c.append(kc)
        kind_w.append(kl["w"])

    # ══ 5 · THE SETTINGS PANEL OF A FIBO. The panel reads the same caps, so its
    # tabs are not a box's — one re-import of the proven mirror, kind as the only
    # variable, side by side with the box's own tab 0 from section 3.
    fibo_html = ["<h1 style='margin-top:22px'>the settings panel is kind-aware — box vs fibo</h1>",
                 "<div class='sub'>Same mirror, same tab, only SIM_KIND differs. The box shows "
                 "FILL · HALF · EXTEND rows and no level block; the fibo shows its level rows "
                 "because DrawKindHasLevels(k) is true for it. Nothing here is a second model of "
                 "the panel.</div>", g_html]
    fibo_c = []
    for k in ("DK_FIBO", "DK_FIBOCHAN"):
        h, cc, _w, _h = panel_box(gear_for(k), k, 0)
        fibo_html.append(h)
        fibo_c.append(cc)

    html = ["<html><head><meta charset='utf-8'><title>strip panels — simulation</title><style>",
            "body{background:#0f1320;color:#CBD4E2;font:13px Arial;margin:0;padding:18px}",
            "h1{font-size:15px;margin:0 0 4px;color:#F3F6FB}",
            ".sub{color:#8C96A6;font-size:11px;margin-bottom:16px;max-width:900px;line-height:1.7}",
            ".stage{display:inline-block;vertical-align:top;margin:0 22px 22px 0}",
            ".cap{font:11px Arial;color:#FFC247;margin-bottom:8px;letter-spacing:.4px}",
            ".wrap{position:relative}",
            ".facts{font:10px Consolas,monospace;color:#6C7A90;margin-top:8px}",
            "img{position:absolute;image-rendering:pixelated}",
            "i{position:absolute;display:block}",
            "span{position:absolute;display:block}",
            "</style></head><body>",
            "<h1>Biotak TH3 — strip panels · simulation</h1>",
            "<div class='sub'>Every surface below is rendered from the numbers and the bitmaps the "
            "indicator itself ships: <b>DSTRIP_*</b> out of Biotak/DrawStrip.mqh, the palette out of "
            "<b>BioPickColor</b>, and the real 9-slice bakes out of Files/Icons/. Text glyphs are the "
            "browser's Arial at the same point size; every pixel of chrome is the shipped bake.</div>",
            s_html, b_html, g_html] + kind_html + fibo_html + ["</body></html>"]

    open(out, "w", encoding="utf-8").write("\n".join(html))
    print("strip  %dx%d" % (s_w, s_h))
    print("board  %dx%d   (grid %d cells)" % (b_w, b_h, len(PAGE0)))
    print("gear   %dx%d   cardN=%d exact=%s" % (gl["w"] + 28, gl["h"] + 28, gl["card_n"], gl["exact"]))
    print("kinds  %d rows   width %d..%d" % (len(KINDS), min(kind_w), max(kind_w)))
    for k, cells in zip(KINDS, kind_w):
        _m, slots, allslots = strip_slots(k)
        print("  %-12s %-18s %d cells  %s"
              % (k, kind_name(k), len(slots),
                 " ".join(SLOT_NAME.get(s, "LEVELS" if s == SLOT_LEVELS else "?") for s in slots)))

    if want_png:
        for tag, cc, W, H in (("strip", s_c, s_w, s_h), ("board", b_c, b_w, b_h),
                              ("gear", gc, gl["w"] + 28, gl["h"] + 28)):
            w, h, rgba = cc.to_raster(W, H)
            p = os.path.join(HERE, "strip-%s.png" % tag)
            open(p, "wb").write(mt4.png(w, h, rgba))
            print("png -> %s" % p)

    allops = s_c.ops + b_c.ops + gc.ops
    for cc in kind_c + fibo_c:
        allops = allops + cc.ops
    miss = sorted({op[1] for op in allops if op[0] == "img" and op[1] is None})
    print("missing bakes: %s" % (miss or "none — every face painted exists on disk"))
    print("-> %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
