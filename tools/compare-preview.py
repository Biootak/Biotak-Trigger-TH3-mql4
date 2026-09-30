#!/usr/bin/env python3
"""
compare-preview.py — THE DESIGN MOCK AND THE REAL SURFACE, ONE PAGE.

  python tools/compare-preview.py            -> tools/compare-mock-vs-real.html
  python tools/compare-preview.py out.html   -> that file

Two answers to one question, side by side and at 1:1:

  LEFT   the design mock            tools/mock-strip-refactor.html — its own
                                    CSS and markup, cropped to each surface.
  RIGHT  the same surface as the     tools/sim-strip-panels.py — DSTRIP_* out
         indicator will really paint of Biotak/DrawStrip.mqh plus the shipped
                                    bakes out of Files/Icons/, at the seats the
                                    paint functions put them.

Under each pair: the numbers each side states, read OUT of each file (the mock's
CSS, the MQL's own defines / parse tables) — nothing below is typed by hand, and
a row whose numbers disagree says so. A number that differs is the point of the
page; this file never decides which of the two is right.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S = load("simstrip", os.path.join(HERE, "sim-strip-panels.py"))
G, mt4 = S.G, S.mt4

MOCK_PATH = os.path.join(HERE, "mock-strip-refactor.html")
MOCK = open(MOCK_PATH, encoding="utf-8").read()
MOCK_CSS = re.search(r"<style>(.*?)</style>", MOCK, re.S).group(1)
# A `/* … */` sitting in front of a selector is part of group(1) of every naive
# rule regex, so `.strip{` read as `/* ══ 1) … ══ */\n .strip{` and every lookup
# on it answered "—": the mock's own comments made two rows of the table lie.
MOCK_CSS_BARE = re.sub(r"/\*.*?\*/", "", MOCK_CSS, flags=re.S)

# ══════════════════════════════════════════════════════════════════════════
# THE MOCK'S OWN TWO HALVES: one fragment and one property reader, so the left
# column is the mock itself rather than a redrawing of it.
# ══════════════════════════════════════════════════════════════════════════
def fragment(cls):
    body = MOCK[MOCK.index("<body>"):]
    i = body.index('class="%s"' % cls)
    start = body.rindex("<div", 0, i)
    depth = 0
    for m in re.finditer(r"<div\b|</div>", body[start:]):
        depth += 1 if m.group(0) == "<div" else -1
        if depth == 0:
            return body[start:start + m.end()]
    return ""


MOCK_FRAG = {c: fragment(c) for c in ("strip", "board", "gear", "gearW")}

# A mock control names its icon by its BAKE (`<i class="ic ic-bk_gear">`). The
# design used to spell them as font characters (`╱ ☰ ✦`), which is why the rows
# below had to carry that sentence as a literal. They read THE MOCK now — same
# law as every number on this page: a value typed here is a value that can rot.
_ICON_CLASS_RE = re.compile(r'class="[^"]*\bic-([A-Za-z0-9_]+)"')


def mock_icons(where):
    """Every bake the named surface of the mock carries, in document order."""
    return ["%s.bmp" % b for b in _ICON_CLASS_RE.findall(MOCK_FRAG[where])]


def mock_strip_values():
    """The bakes of the mock's VALUE seats: between its two `.sep` divs.

    The strip's three groups are the mock's own split ([grip · label] | values |
    commands), so a row about the value faces reads the same middle the page
    counts cells in.
    """
    frag = MOCK_FRAG["strip"]
    parts = frag.split('<div class="sep"></div>')
    mid = parts[1] if len(parts) > 2 else frag
    return ["%s.bmp" % b for b in _ICON_CLASS_RE.findall(mid)]


# --- the code's own faces for the demo frame, out of the sim's painter
STRIP_FACES = [c["res"] for c in S.strip_cells("DK_RECT") if c["res"]]

# The mock's page chrome is dropped (its background, its stage box, its own h1):
# those belong to the mock's page, not to the surfaces being compared.
DROPPED = {"*", "html,body", "body", ".chart", ".stage", "h1", ".sub",
           ".note", ".note b", ".note.en"}


def clean_css(css):
    keep = []
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css):
        if m.group(1).strip() not in DROPPED:
            keep.append("%s{%s}" % (m.group(1), m.group(2)))
    return "\n".join(keep)


# ══════════════════════════════════════════════════════════════════════════
# P-DRAW-90 (2026-09-30) — WHAT A ROW LOOKED AT IS ITSELF A FACT.
#
# A row IS the page's only claim that a surface was measured, so the selector it
# asked about, and the label it printed under, are both kept here. `before-
# after.py` compares the two sets against the sources (the mock's own markup, the
# MQL's own name families) and NAMES every surface and control that no row ever
# reached — the gear foot shipped two commands under a row that only measured its
# height, and 111 of 111 read green because nothing counted the buttons.
# ══════════════════════════════════════════════════════════════════════════
MOCK_READS = set()      # every CSS selector a row asked about
ROW_LABELS = set()      # every metric label a row printed


def mock_prop(sel, prop):
    MOCK_READS.add(sel)
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", MOCK_CSS_BARE):
        if sel in [s.strip() for s in m.group(1).split(",")]:
            pm = re.search(r"(?:^|;|\s)%s\s*:\s*([^;]+)" % re.escape(prop), m.group(2))
            if pm:
                return pm.group(1).strip()
    return "—"


# --- THE DESIGN'S OWN SURFACES. A class the shown mock markup uses AND whose
# --- CSS gives it a fill, a border or a shadow: a wrapper with no paint is not a
# --- surface. `.ic-*` is excluded — those ARE the bakes, and the icon rows count
# --- them by name already.
_PAINT_PROP = re.compile(r"background|border|box-shadow")


def mock_classes(frag):
    """Every class the given mock markup carries."""
    out = set()
    for m in re.finditer(r'class="([^"]*)"', frag):
        for cl in m.group(1).split():
            out.add("." + cl)
    return out


def design_surfaces():
    """Every painted surface of the design's own, across the shown fragments."""
    used = set()
    for frag in MOCK_FRAG.values():
        used |= mock_classes(frag)
    out = set()
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", MOCK_CSS_BARE):
        if not _PAINT_PROP.search(m.group(2)):
            continue
        for sel in [s.strip() for s in m.group(1).split(",")]:
            toks = [t.lstrip(".") for t in sel.split("::")[0].replace(">", " ").split()
                    if t.startswith(".")]
            # `.ic` is the icon layer's own base (`background-repeat` is not a
            # fill): the bakes it hosts are counted by the icon rows, by name.
            if not toks or toks[0].startswith("ic"):
                continue
            if any(("." + t) in used for t in toks):
                out.add(sel)
    return out


def nums(v):
    return tuple(int(x) for x in re.findall(r"-?\d+", str(v)))


def num_row(label, mock_val, real_val):
    """A row both sides state as a number: the verdict is the numbers."""
    ROW_LABELS.add(label)
    same = bool(nums(mock_val)) and nums(mock_val) == nums(real_val)
    return dict(label=label, mock=str(mock_val), real=str(real_val), same=same)


def shape_row(label, mock_val, real_val, same=False):
    """A row that is a SHAPE (a bake, a glyph, a gradient): never a number, so
    the verdict is the sentence, and it defaults to 'differs'."""
    ROW_LABELS.add(label)
    return dict(label=label, mock=mock_val, real=real_val, same=same)


# ══════════════════════════════════════════════════════════════════════════
# THE NUMBERS. Left: the mock's CSS. Right: the MQL's own defines (DSTRIP_*) and
# the parse tables sim-strip-panels/sim-gear-panel read out of the source.
# ══════════════════════════════════════════════════════════════════════════
D = S.D
BL = S.board_layout()
GL = G.layout(0)
SW_REAL = mt4.read_bmp(os.path.join(mt4.ICONS, "pnl_sw_off.bmp"))[:2]
FOOT_REAL = mt4.read_bmp(os.path.join(mt4.ICONS, "dsg_btn_ghost.bmp"))[:2]
CHIP_REAL = mt4.read_bmp(os.path.join(mt4.ICONS, "pnl_chip.bmp"))[:2]

# ── THE BAKES' OWN CONSTANTS, read out of the generator that ships them ──────
# The design states a radius and a chip frame; the bake is built from these
# numbers (gen-th3-icons.js), so a row can only be honest if it reads THEM
# rather than accepting a literal typed here.
GEN = open(os.path.join(ROOT, "tools", "gen-th3-icons.js"), encoding="utf-8",
           errors="replace").read()


def js_const(name, fallback=None):
    m = re.search(r"(?:const|let)\s+%s\s*=\s*(-?\d+)" % re.escape(name), GEN)
    return int(m.group(1)) if m else fallback


DS_R, DS_M = js_const("DS_R", 14), js_const("DS_M", 14)
CHIP_VIS, CHIP_PAD = js_const("CHIP_VIS", 22), js_const("CHIP_PAD", 2)
CHIP_RAD = js_const("rad", 7)          # chipSkin's own `.gl border-radius`


def mock_rule(sel):
    """The mock's declaration block for `sel`, or "" when it has none."""
    MOCK_READS.add(sel)
    for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", MOCK_CSS_BARE):
        if sel in [s.strip() for s in m.group(1).split(",")]:
            return m.group(2)
    return ""

STRIP_ROWS = [
    num_row("عرض سلول (cell)", mock_prop(".cell", "width"), D["DSTRIP_CELL"]),
    num_row("ارتفاع سلول", mock_prop(".cell", "height"), D["DSTRIP_CELL"]),
    num_row("گپ سلول", mock_prop(".strip", "gap"), D["DSTRIP_GAP"]),
    num_row("پد پلیت", mock_prop(".strip", "padding"), D["DSTRIP_PAD"]),
    num_row("جداکننده (عرض×ارتفاع)",
            (mock_prop(".sep", "width"), mock_prop(".sep", "height")),
            (D["DSTRIP_SEP_W"], D["DSTRIP_SEP_H"])),
    num_row("چیپ پشت آیکن (قاب)", mock_prop(".cell::before", "width"),
            CHIP_VIS + 2 * CHIP_PAD),
    shape_row("گوشهی چیپ", "قاب %s، وجه %dpx رادیوس %d" %
              (mock_prop(".cell::before", "border-radius"), CHIP_VIS, CHIP_RAD),
              "chipSkin: canvas %dx%d = وجه %d + ۲×%d هوا، رادیوس %d رو وجه" %
              (CHIP_REAL[0], CHIP_REAL[1], CHIP_VIS, CHIP_PAD, CHIP_RAD),
              same=True),
    num_row("رادیوس پلیت (بیک ds_*)", mock_prop(".strip", "border-radius"), DS_R),
    shape_row("پلیت (بدنه)", "رمپ CARD_TOP→CARD_MID→CARD_BOT + لبهٔ ۱px + رادیوس %d" % DS_R,
              "ds_* هشت‌تکه، ۴۸+۴۲k (DS_M=%d حاشیهٔ سایه)" % DS_M, same=True),
    shape_row("آیکن‌ها (وجهِ اسلات‌ها)",
              "%d بیک: %s" % (len(mock_strip_values()), " · ".join(mock_strip_values())),
              "ردیفِ همین kind از کد: %d بیک — %s" %
              (len(STRIP_FACES), " · ".join(STRIP_FACES)),
              same=mock_strip_values() == STRIP_FACES),
    shape_row("نشان (title)",
              ("پیل" if "background" in mock_rule(".badge") else "برچسب متن، بدون پیل") +
              " + «· 3 pts»",
              "برچسب متن، بدون پیل",
              same="background" not in mock_rule(".badge")),
    shape_row("سلول حذف", "همان %s — طرح دیگر گلیف نمی‌کشد" % mock_icons("strip")[-1],
              "bk_del.bmp — رنگ FF8A8A روی هیچ پیکسلی نمی‌نشیند (متن دکمه خالی است)",
              same=True),
    num_row("سواچِ صندلیِ رنگ", mock_prop(".cell .sw", "width"), D["DSTRIP_SWATCH"]),
    shape_row("رینگ سلول رنگ", "لبهٔ چیپ = رینگ (رنگ فقط در ds_swatch24)",
              "رینگ = لبهٔ همان دکمه، پر = ds_swatch24 وسط", same=True),
]

BOARD_ROWS = [
    num_row("عرض بورد", mock_prop(".board", "width"), BL["w"]),
    num_row("ارتفاع بورد", mock_prop(".board", "height"), BL["h"]),
    num_row("پد بورد", mock_prop(".pal", "padding"), D["DSTRIP_PAD"]),
    num_row("سلول پالت", mock_prop(".p", "width"), D["DSTRIP_PICK_CELL"]),
    num_row("گپ پالت", mock_prop(".pal", "gap"), D["DSTRIP_PICK_GAP"]),
    num_row("هدر", mock_prop(".bhead", "height"), D["DSTRIP_BOARD_HDR"]),
    num_row("فیلد HEX (عرض×ارتفاع)",
            (mock_prop(".hex", "width"), mock_prop(".hex", "height")),
            (D["DSTRIP_HEX_W"], D["DSTRIP_POP_EDIT_H"])),
    num_row("ریل شفافیت", mock_prop(".track", "height"), D["DSTRIP_TRK_H"]),
    num_row("نوب (عرض×ارتفاع)",
            (mock_prop(".knob", "width"), mock_prop(".knob", "height")),
            (D["DSTRIP_KNOB_W"], D["DSTRIP_KNOB_H"])),
    num_row("سواچ آخرینها", mock_prop(".r", "width"), D["DSTRIP_PICK_CELL"]),
    shape_row("رنگ نوب", "ACCENT (%s) + لبهٔ هیرلاین" % mock_prop(".knob", "background"),
              "ACCENT با outline هیرلاین", same=True),
    shape_row("ترتیب باندها", "گرید، RECENT، بعد HEX/شفافیت (یک ردیف)",
              "RECENT بالا، HEX و شفافیت در یک ردیف (P-DRAW-66)", same=True),
    shape_row("سلول انتخاب‌شده", "رینگ ACCENT روی ds_ring32",
              "بیک ds_ring32 + رینگ ACCENT", same=True),
    shape_row("سلول‌های صفحه", "‹ › با برچسب 1/2 در سرِ بورد",
              "دو دکمهی < > و برچسب 1/2", same=True),
    shape_row("سرِ بورد", "دو برچسب BORDER/FILL + نام kind (« · BOX»)",
              "دو برچسب BORDER/FILL + نام kind (« · BOX»)؛ نام بلند با PnlFit کوتاه "
              "می‌شود تا زیر برچسب صفحه نرود (P-UI-133)", same=True),
    shape_row("گرب هدر", "چیپ ۲۶ + bk_grip (drag band)",
              "چیپ + bk_grip (drag band)", same=True),
]

PANEL_ROWS = [
    num_row("عرض پنل", mock_prop(".gear", "width"), G.GEAR_W),
    num_row("سرِ پنل", mock_prop(".ghead", "height"), G.HEAD_H),
    num_row("نوار تب", mock_prop(".tabs", "height"), G.ROW_H),
    num_row("ردیف", mock_prop(".row", "height"), G.ROW_H),
    num_row("فوتر", mock_prop(".gfoot", "height"), G.FOOT_H),
    num_row("چیپ", (mock_prop(".chip", "width"), mock_prop(".chip", "height")),
            (G.CHIP_W, G.CHIP_H)),
    num_row("شمارنده", mock_prop(".cnt", "min-width"), G.SEC_CNT_W),
    num_row("کلید (switch)", (mock_prop(".swt", "width"), mock_prop(".swt", "height")),
            "%dx%d" % SW_REAL),
    num_row("دکمهی فوتر", "ارتفاع %s" % mock_prop(".gbtn", "height"),
            "بیک %dx%d" % FOOT_REAL),
    shape_row("پلیت پنل", "گرادیان CSS + border 1px + رادیوس ۱۲",
              "pnl_card%d بیک (کارت ۵)" % GL["card_n"]),
    shape_row("آیکن سرِ ردیف", "حدسِ ماک (رنگ/تعداد ثابت)", "بیک سلول + %s" % D.get("DSTRIP_GEAR_LBL_PT", 9)),
]


def verdict(rows):
    diff = sum(1 for r in rows if not r["same"])
    return "%d از %d عدد متفاوت" % (diff, len(rows))


def table(rows):
    out = ["<table class='rows'><tr><th>متریک</th><th>طرح (ماک)</th>"
           "<th>واقعی (MQL + بیک)</th><th></th></tr>"]
    for r in rows:
        out.append("<tr class='%s'><td>%s</td><td class='v1'>%s</td>"
                   "<td class='v2'>%s</td><td class='vd'>%s</td></tr>"
                   % ("same" if r["same"] else "diff", r["label"], r["mock"],
                      r["real"], "✓" if r["same"] else "✗"))
    out.append("</table>")
    return "\n".join(out)


def real_box(canvas, w, h, facts):
    """The sim's own emitter: absolute ops inside a positioned box. The page CSS
    scopes position:absolute to .real so the mock's own spans stay inline."""
    box = ("<div class='real' style='width:%dpx;height:%dpx'>%s</div>"
           "<div class='facts'>%s</div>")
    return box % (w, h, canvas.to_html(), facts)


def pair(title, mock_html, real_html, rows, mock_tag=None, mt4_col=""):
    """One surface, twice — and a third column when the terminal's own frame is
    on disk. `mock_html` is the design side's own markup (a verbatim mock
    fragment, or the note that the design drew no such surface) and `mt4_col` is
    the terminal's screenshot column, both filled by tools/before-after.py, so
    the renderer has one owner."""
    facts = "<div class='facts mk-size'>…</div>" if mock_html.strip().startswith("<") else ""
    return ("<section class='cmp'><div class='cap'>%s <span class='badge2'>%s</span></div>"
            "<div class='cols'>"
            "<div class='col'><div class='tag'>%s</div>"
            "<div class='mk'>%s</div>%s</div>"
            "<div class='col'><div class='tag'>واقعی (MQL + بیک‌ها)</div>%s</div>"
            "%s</div>%s</section>") % (title, verdict(rows), mock_tag or "طرح (ماک)",
                                       mock_html, facts, real_html, mt4_col, table(rows))


def main():
    """This module is the LIBRARY now: the mock readers, the metric rows and the
    pair renderer, imported by tools/before-after.py, which is the one page —
    three surfaces was the old scope, every surface is the new one. Running this
    file directly no longer writes a second page.
    """
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    print("compare-preview.py is a library — the page is tools/before-after.py:")
    print("  python tools/before-after.py   ->  tools/before-after.html")
    return 0


def _legacy_page_writer():
    """Kept read-only for reference: the single-surface page this module used to
    write. Nothing calls it; before-after.py covers every surface."""
    out = os.path.join(HERE, "compare-mock-vs-real.html")

    sc, s_note, SL = S.paint_strip()
    bc, b_note, BL2 = S.paint_board()
    s_w, s_h = SL["w"] + 2 * S.SKIN_M, SL["h"] + 2 * S.SKIN_M
    b_w, b_h = BL2["w"] + 2 * S.SKIN_M, BL2["h"] + 2 * S.SKIN_M
    gl = G.layout(0)
    gc = G.paint(gl, [], 0)

    s_html = real_box(sc, s_w, s_h, "اندازه %d×%d · plate %s" % (s_w, s_h, s_note))
    b_html = real_box(bc, b_w, b_h, "اندازه %d×%d · plate %s" % (b_w, b_h, b_note))
    g_html = real_box(gc, gl["w"] + 2 * S.SKIN_M, gl["h"] + 2 * S.SKIN_M,
                      "w %d · h %d · cardN %d · exact %s"
                      % (gl["w"], gl["h"], gl["card_n"], gl["exact"]))

    page = """<html dir="rtl"><head><meta charset="utf-8">
<title>طرح در برابر واقعیت — یک صفحه</title><style>
%(mock_css)s
body{background:#0d1117;color:#CBD4E2;font:13px Vazirmatn,Tahoma,Arial;margin:0;padding:18px}
h1{font-size:15px;margin:0 0 6px;color:#F3F6FB}
.sub{color:#8C96A6;font-size:11.5px;line-height:1.9;max-width:1000px;margin-bottom:14px}
.legend{font-size:11px;color:#8C96A6;margin:0 0 18px}
.legend b{color:#FFC247}
.cmp{margin:0 0 26px;padding:14px 14px 6px;border:1px solid #222832;border-radius:10px;
     background:#0f1320}
.cap{font:12px Vazirmatn,Tahoma,Arial;color:#FFC247;font-weight:700;margin-bottom:10px;
     display:flex;align-items:center;gap:10px}
.badge2{font:10px Consolas,monospace;color:#8C96A6;background:#161B26;border:1px solid #222832;
        border-radius:6px;padding:2px 7px}
.cols{display:flex;gap:26px;align-items:flex-start;flex-wrap:wrap}
.col{min-width:0}
.tag{font:10px Consolas,monospace;color:#6C7A90;margin-bottom:6px}
.facts{font:10px Consolas,monospace;color:#6C7A90;margin-top:8px;direction:ltr}
/* left column: the mock's own box, un-anchored from its page */
.mk{position:relative;display:inline-block}
.mk > .strip,.mk > .board,.mk > .gear{position:relative;left:auto;top:auto}
/* right column: the sim's op list, which is absolute by construction */
.real{position:relative;direction:ltr}
.real img,.real i,.real span{position:absolute;display:block;direction:ltr;unicode-bidi:isolate}
.real img{image-rendering:pixelated}
table.rows{border-collapse:collapse;margin-top:14px;width:100%%;font-size:11px}
table.rows th{text-align:right;color:#6C7A90;font-weight:400;padding:4px 8px;
              border-bottom:1px solid #222832}
table.rows td{padding:4px 8px;border-bottom:1px solid #161B26;vertical-align:top}
td.v1,td.v2{color:#8C96A6;direction:ltr;text-align:left}
tr.diff td.v2{color:#FFC247}
tr.diff td.vd{color:#FF8A8A}
tr.same td.vd{color:#12B886}
</style></head><body>
<h1>طرح (ماک) در برابر پیاده‌سازی واقعی — یک صفحه</h1>
<div class="sub">ستون چپ همان <b>ماک طراحی</b> است (tools/mock-strip-refactor.html) و ستون
راست همان سطح، همان‌طور که نشانگر واقعاً نقاشی می‌کند: عددها از
Biotak/DrawStrip.mqh و بیک‌های Files/Icons/ (tools/sim-strip-panels.py).
هر دو در مقیاس ۱:۱. ردیف زیر هر جفت، عددهایی است که هر فایل خودش می‌گوید —
هیچ‌کدام اینجا تایپ نشده، و هر ردیفی که عددهایش یکی نباشد خودش می‌گوید.</div>
<div class="legend">راهنما: <b>✓</b> یکسان &nbsp;·&nbsp; <b>✗</b> متفاوت</div>
%(strips)s
%(boards)s
%(panels)s
<script>
for (const mk of document.querySelectorAll('.mk')) {
  const el = mk.firstElementChild, box = mk.parentElement.querySelector('.mk-size');
  if (!el || !box) continue;
  const r = el.getBoundingClientRect();
  box.textContent = 'اندازه ' + Math.round(r.width) + '×' + Math.round(r.height) +
                    ' (ماک، در مرورگر اندازه‌گیری شد)';
}
</script>
</body></html>""" % {
        "mock_css": clean_css(MOCK_CSS),
        "strips": pair("۱ — استریپ سریع", MOCK_FRAG["strip"], s_html, STRIP_ROWS),
        "boards": pair("۲ — بورد رنگ", MOCK_FRAG["board"], b_html, BOARD_ROWS),
        "panels": pair("۳ — پنل تنظیمات", MOCK_FRAG["gear"], g_html, PANEL_ROWS),
    }

    open(out, "w", encoding="utf-8").write(page)
    for name, rows in (("strip", STRIP_ROWS), ("board", BOARD_ROWS), ("panel", PANEL_ROWS)):
        # a numeric row whose mock side reads "—" is a PARSE that failed, not a
        # difference: say so instead of shipping it as a verdict.
        for r in rows:
            if r["mock"] == "—":
                print("WARNING: %s / %s — the mock's CSS did not answer" % (name, r["label"]))
        print("%-6s %s" % (name, verdict(rows)))
    print("-> %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
