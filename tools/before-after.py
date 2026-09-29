#!/usr/bin/env python3
"""
before-after.py — EVERY surface of the strip, twice: the DESIGN (the mock) and
the REAL render, side by side, at 1:1.

  python tools/before-after.py              -> tools/before-after.html
  python tools/before-after.py out.html     -> that file

The two sides, and where each one comes from:

  BEFORE  tools/mock-strip-refactor.html — the design's own CSS and markup,
          read out of that file (never redrawn here). Where the design drew no
          such surface, the side says so instead of inventing one.
  AFTER   tools/sim-strip-panels.py + tools/sim-gear-panel.py — the surfaces as
          the indicator paints them: DSTRIP_* out of Biotak/DrawStrip.mqh, the
          per-kind cell list out of DrawStripAllSlotAt/DrawStripIconRes, and the
          real bakes out of Files/Icons/.

Coverage — the point of this page:

  §1  the quick row for EVERY kind the toolbar defines (15), not only the box;
  §2  the colour board;
  §3  the settings panel, ALL FOUR tabs (the design drew one panel, so the other
      three say that and carry the code's numbers);
  §4  the same panel for a kind that is NOT a box, because the panel asks the
      caps — a fibo's tabs are not a box's.

The numbers under each pair come OUT of the two files: the mock's own CSS on the
left, the MQL's defines and parse tables on the right. Nothing here is typed by
hand, and a row whose numbers disagree says so.

This supersedes tools/compare-preview.py's page: same idea, every surface, one
generator (it is imported below, so the mock readers and the tables have ONE
owner).
"""
import glob
import importlib.util
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


C = load("cmpmod", os.path.join(HERE, "compare-preview.py"))
S, G, mt4 = C.S, C.G, C.mt4
num_row, shape_row = C.num_row, C.shape_row

# ══════════════════════════════════════════════════════════════════════════
# THE THIRD COLUMN — THE TERMINAL'S OWN PIXELS.
#
# tests/Biotak_StripShot_Test.mq4 paints each state with the REAL paint path and
# writes StripShot_<tag>.png into <MQL4>\Files. This page cannot run the terminal,
# so the column is filled by the file it left behind: found -> copied beside this
# page (the preview server serves tools/) and shown; missing -> the page says so
# and names the harness, instead of showing the sim twice and calling it proof.
# ══════════════════════════════════════════════════════════════════════════
SHOT_DIR = os.path.join(HERE, "mt4-shots")


def sync_shots():
    base = os.path.join(os.environ.get("APPDATA", ""), "MetaQuotes", "Terminal")
    found = {}
    for p in glob.glob(os.path.join(base, "*", "MQL4", "Files", "StripShot_*.png")):
        tag = os.path.basename(p)[len("StripShot_"):-len(".png")]
        found[tag] = p
    if found:
        os.makedirs(SHOT_DIR, exist_ok=True)
        for tag, p in found.items():
            shutil.copyfile(p, os.path.join(SHOT_DIR, tag + ".png"))
    return {t: ("mt4-shots/%s.png" % t) for t in found}


SHOTS = sync_shots()


def shot_col(tag, note=""):
    """The MT4 column for one surface tag, or the sentence saying why it is empty."""
    if tag in SHOTS:
        return ("<div class='col'><div class='tag'>متاتریدر — اسکرین‌شات واقعی</div>"
                "<img class='shot' src='%s'>"
                "<div class='facts'>tests/Biotak_StripShot_Test.mq4 → %s</div></div>"
                % (SHOTS[tag], os.path.basename(SHOTS[tag])))
    return ("<div class='col'><div class='tag'>متاتریدر — اسکرین‌شات واقعی</div>"
            "<div class='nonote'>گرفته نشده: تستر <b>tests/Biotak_StripShot_Test.mq4</b> "
            "را روی چارت بینداز؛ هر حالت یک PNG در <b>MQL4\\Files</b> می‌نویسد و "
            "صفحه‌ی بعدی این ستون را خودش پر می‌کند.<br>وسوسه‌ی این اسلات: %s</div></div>"
            % (tag + (" — " + note if note else "")))


# ── the design's row, read out of the mock's own markup ─────────────────────
def _cells(segment):
    """Every `<div class="cell…">…</div>` in one segment, as its inner HTML.

    A cell's own close is its LAST `</div>`: the colour seat and the icon cells
    carry a `<span>` inside, so a non-greedy `(.*?)</div>` reads the span's close
    as the cell's and the count comes out one instead of six.
    """
    out = []
    for chunk in segment.split('<div class="cell')[1:]:
        _head, _gt, body = chunk.partition(">")
        out.append(body.rsplit("</div>", 1)[0])
    return out


def mock_row_parts():
    """(value cells, chrome cells) of the mock's strip row.

    The mock splits its row with two `.sep` divs: [grip · badge] | values |
    chrome. Counting them here is what makes "the design drew six" a fact of the
    mock file rather than a number in this one.
    """
    frag = C.MOCK_FRAG["strip"]
    parts = frag.split('<div class="sep"></div>')
    mid = parts[1] if len(parts) > 2 else frag
    chrome = parts[2] if len(parts) > 2 else ""
    return _cells(mid), _cells(chrome)


MOCK_VAL, MOCK_CHROME = mock_row_parts()
MOCK_CELLS = len(MOCK_VAL)


def _glyph_of(cell_html):
    m = re.search(r'<span class="ico">(.*?)</span>', cell_html, re.S)
    if m:
        return m.group(1).strip()
    if 'class="sw' in cell_html or "sw half" in cell_html:
        return "رنگ"
    if cell_html.strip():
        return cell_html.strip()
    return "—"


MOCK_GLYPHS = " · ".join(_glyph_of(c) for c in MOCK_VAL)


# ══════════════════════════════════════════════════════════════════════════
# §1 — THE QUICK ROW, EVERY KIND
# ══════════════════════════════════════════════════════════════════════════
SHARED_LAYOUT_ROWS = ("ارتفاع سلول", "گپ سلول", "پد پلیت", "جداکننده (عرض×ارتفاع)")


def kind_names(k):
    merged, slots, _all = S.strip_slots(k)
    return merged, [S.SLOT_NAME.get(s, "LEVELS" if s == S.SLOT_LEVELS else "?")
                    for s in slots]


def kind_table(k):
    _merged, names = kind_names(k)
    rows = [num_row("سلول‌های مقدار", MOCK_CELLS, len(names)),
            num_row("سلول‌های دستور (more/gear/pin/del)", len(MOCK_CHROME), S.ACT_N)]
    rows += [r for r in C.STRIP_ROWS if r["label"] in SHARED_LAYOUT_ROWS]
    rows.append(shape_row("سلول‌های این kind", "معادل ندارد (طرح یک ردیف کشید)",
                          " · ".join(names)))
    return rows


def design_note(k):
    merged, names = kind_names(k)
    return ("<div class='nonote'>طرح، یک ردیف کشید: <b>%d سلول مقدار</b> «%s» "
            "و %d سلول دستور.<br>ردیفِ این kind از کد: <b style='color:#FFC247'>%d</b> سلول — %s%s"
            "</div>"
            % (MOCK_CELLS, MOCK_GLYPHS, len(MOCK_CHROME), len(names),
               " · ".join(names),
               " · رنگ ادغام‌شده (رینگ=بوردر، مرکز=داخل)" if merged else ""))


def real_kind(k, pick_open=False, act_on=None, name=None):
    cells = S.strip_cells(k, {}, border=S.KIND_BORDER, fill=S.KIND_FILL)
    c, note, L = S.paint_strip(cells, name or (S.kind_name(k) + " 1"),
                               act_on=[False] * S.ACT_N if act_on is None else act_on,
                               pick_open=pick_open)
    w, h = L["w"] + 2 * S.SKIN_M, L["h"] + 2 * S.SKIN_M
    return C.real_box(c, w, h, "اندازه %d×%d · plate %s" % (w, h, note))


def section_kinds():
    out = ["<h1 style='margin-top:24px'>۱ — استریپ سریع: ردیفِ هر kind</h1>",
           "<div class='sub'>ردیف اول، ردیفِ باکس است: طراحی و رندر در یک حالت "
           "(بورد رنگ باز، پنل باز، fill روشن) — همان فریمی که ماک کشیده. چهارده "
           "kind بعدی همان ردیف‌اند با سلول‌های خودشان؛ ستون طرح برای آن‌ها می‌گوید "
           "طرح چه کشیده و کد برای این kind چه می‌سازد.</div>"]

    box_cells = S.strip_cells("DK_RECT")            # the mock's frame, verbatim
    c, note, L = S.paint_strip(box_cells)
    w, h = L["w"] + 2 * S.SKIN_M, L["h"] + 2 * S.SKIN_M
    out.append(C.pair("باکس (DK_RECT) — همان فریم ماک", C.MOCK_FRAG["strip"],
                      C.real_box(c, w, h, "اندازه %d×%d · plate %s" % (w, h, note)),
                      C.STRIP_ROWS, mt4_col=shot_col("row")))

    for k in S.KINDS:
        if k == "DK_RECT":
            continue
        rows = kind_table(k)
        out.append(C.pair("%s (%s)" % (S.kind_name(k), k), design_note(k),
                          real_kind(k), rows,
                          mock_tag="طرح (ماک) — برای این kind چیزی نکشید",
                          mt4_col=shot_col(k)))
    return "\n".join(out)


# ══════════════════════════════════════════════════════════════════════════
# §2 — THE COLOUR BOARD
# ══════════════════════════════════════════════════════════════════════════
def section_board():
    bc, b_note, BL = S.paint_board()
    w, h = BL["w"] + 2 * S.SKIN_M, BL["h"] + 2 * S.SKIN_M
    return "\n".join([
        "<h1 style='margin-top:24px'>۲ — بورد رنگ</h1>",
        "<div class='sub'>کارتِ مستقل رنگ: هر دو طرف در همان حالت (صفحه ۱، "
        "خانه‌ی اول انتخاب‌شده، شفافیت ۷۲٪).</div>",
        C.pair("بورد رنگ (پوپ‌اور اسلات رنگ)", C.MOCK_FRAG["board"],
               C.real_box(bc, w, h, "اندازه %d×%d · plate %s" % (w, h, b_note)),
               C.BOARD_ROWS, mt4_col=shot_col("board"))])


# ══════════════════════════════════════════════════════════════════════════
# §3/§4 — THE SETTINGS PANEL, ALL FOUR TABS, AND FOR A NON-BOX KIND
# ══════════════════════════════════════════════════════════════════════════
def tab_table(L):
    """The panel numbers both sides state: the mock's CSS on the left, the code
    on the right. Rows the design never stated are NOT rows here — they belong in
    the pair's facts line, not in a verdict about two numbers disagreeing."""
    return [num_row("عرض پنل", C.mock_prop(".gear", "width"), L["w"]),
            num_row("ردیف", C.mock_prop(".row", "height"), G.ROW_H),
            num_row("سرِ پنل", C.mock_prop(".ghead", "height"), G.HEAD_H),
            num_row("فوتر", C.mock_prop(".gfoot", "height"), G.FOOT_H),
            num_row("نوار تب", C.mock_prop(".tabs", "height"), G.ROW_H)]


def panel_box(mod, kind, tab, mock_html, rows, title, mock_tag=None, shot_tag=None):
    L = mod.layout(tab)
    c = mod.paint(L, [], tab)
    w, h = L["w"] + 2 * S.SKIN_M, L["h"] + 2 * S.SKIN_M
    facts = ("w %d · h %d · cardN %d · exact %s · plate %s · ردیف‌ها %d"
             % (L["w"], L["h"], L["card_n"], L["exact"],
                "bake" if L["exact"] else "composed W", len(L["blocks"])))
    return C.pair(title, mock_html, C.real_box(c, w, h, facts), rows, mock_tag,
                  shot_col(shot_tag) if shot_tag else ""), L


def section_panel():
    out = ["<h1 style='margin-top:24px'>۳ — پنل تنظیمات: هر چهار تب</h1>",
           "<div class='sub'>ماک یک پنل کشید (تب Paint). سه تب دیگر همان زبان "
           "بصری را دارند با محتوای خودشان، پس ستون طرح برای آن‌ها می‌گوید طرح "
           "چیزی نکشیده و عددهای کد را می‌آورد. هر تب، اندازه‌ی پلیت خودش را دارد: "
           "قانون کارت‌ها ۵۶ + 42n + 48.</div>"]
    for tab in range(4):
        L = G.layout(tab)
        mock = C.MOCK_FRAG["gear"] if tab == 0 else \
            ("<div class='nonote'>طرح فقط یک پنل کشید (تب <b>Paint</b>): همان سرِ ۵۶، "
             "نوار تب ۴۲، ردیف‌های ۴۲ و فوتر ۴۸ — زبان بصری یکی است، محتوا نه.<br>"
             "این تب از کد: <b style='color:#FFC247'>%d</b> ردیف محتوا، "
             "ارتفاع <b>%d</b>، پلیت <b>%s</b>.</div>"
             % (len(L["blocks"]), L["h"], "bake pnl_card%d" % L["card_n"]
                if L["exact"] else "composed W"))
        p, L = panel_box(G, "DK_RECT", tab,
                         mock, tab_table(L),
                         "تب %d — %s" % (tab + 1, G.TABS[tab]),
                         mock_tag="طرح (ماک)" if tab == 0 else
                         "طرح (ماک) — این تب را نکشید",
                         shot_tag="panel_%s" % ["paint", "style", "look", "row"][tab])
        out.append(p)

    out.append("<h1 style='margin-top:24px'>۴ — پنل برای یک kind غیر باکس (فایبو)</h1>"
               "<div class='sub'>محتوای پنل از DrawKindCaps می‌آید، پس تب‌های یک "
               "فایبو تب‌های یک باکس نیستند. تنها چیزی که عوض شده SIM_KIND است.</div>")
    fb = S.gear_for("DK_FIBO")
    p, _L = panel_box(fb, "DK_FIBO", 0,
                      "<div class='nonote'>طرح، پنلِ باکس را کشید. همان پنل برای "
                      "فایبو، با ردیف‌های خودش (سطح‌ها، رنگ سطح، تعداد) — "
                      "چون کد از caps می‌پرسد.</div>",
                      tab_table(fb.layout(0)), "فایبو (DK_FIBO) — تب ۱ (Paint)",
                      mock_tag="طرح (ماک) — فقط زبان بصری", shot_tag="fibo_paint")
    out.append(p)
    return "\n".join(out)


# ══════════════════════════════════════════════════════════════════════════
PAGE = """<html dir="rtl"><head><meta charset="utf-8">
<title>قبل ↔ بعد — هر سطح استریپ، دو بار</title><style>
%(mock_css)s
body{background:#0d1117;color:#CBD4E2;font:13px Vazirmatn,Tahoma,Arial;margin:0;padding:18px}
h1{font-size:15px;margin:0 0 6px;color:#F3F6FB}
.sub{color:#8C96A6;font-size:11.5px;line-height:1.9;max-width:1040px;margin-bottom:16px}
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
.nonote{max-width:430px;font-size:11.5px;line-height:1.9;color:#8C96A6;
        background:#12161D;border:1px dashed #333C4C;border-radius:8px;padding:10px 12px}
.nonote b{color:#CBD4E2}
.mk{position:relative;display:inline-block}
.mk > .strip,.mk > .board,.mk > .gear{position:relative;left:auto;top:auto}
.real{position:relative;direction:ltr}
.real img,.real i,.real span{position:absolute;display:block;direction:ltr;unicode-bidi:isolate}
.real img{image-rendering:pixelated}
img.shot{max-width:560px;border:1px solid #222832;border-radius:6px;background:#0f1320}
table.rows{border-collapse:collapse;margin-top:14px;width:100%%;font-size:11px}
table.rows th{text-align:right;color:#6C7A90;font-weight:400;padding:4px 8px;
              border-bottom:1px solid #222832}
table.rows td{padding:4px 8px;border-bottom:1px solid #161B26;vertical-align:top}
td.v1,td.v2{color:#8C96A6;direction:ltr;text-align:left}
tr.diff td.v2{color:#FFC247}
tr.diff td.vd{color:#FF8A8A}
tr.same td.vd{color:#12B886}
</style></head><body>
<h1>قبل ↔ بعد — هر سطحِ استریپ، دو بار، مقیاس ۱:۱</h1>
<div class="sub">
ستون <b>طرح</b> خودِ ماک است (tools/mock-strip-refactor.html) — CSS و مارکاپش خوانده
می‌شود، بازکشیده نمی‌شود. ستون <b>واقعی</b> همان سطح است که نشانگر می‌کشد: عددها از
Biotak/DrawStrip.mqh و DrawToolbar.mqh (tools/sim-strip-panels.py و sim-gear-panel.py)،
و هر پیکسلِ آیکن از بیکِ واقعی Files/Icons/.
زیر هر جفت، جدولی از عددهایی که هر طرف خودش می‌گوید: <b>✓</b> یکسان، <b>✗</b> متفاوت.
هر جایی که طرح آن سطح را نکشیده، ستون طرح نمی‌سازد — می‌گوید نکشیده و عدد کد را می‌آورد.
</div>
%(kinds)s
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
</body></html>"""


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") \
        else os.path.join(HERE, "before-after.html")

    page = PAGE % {
        "mock_css": C.clean_css(C.MOCK_CSS),
        "kinds": section_kinds(),
        "boards": section_board(),
        "panels": section_panel(),
    }
    open(out, "w", encoding="utf-8").write(page)

    bad = 0
    for r in C.STRIP_ROWS + C.BOARD_ROWS + C.PANEL_ROWS:
        if r["mock"] == "—":
            print("WARNING: %s — the mock's CSS did not answer" % r["label"])
            bad += 1
    print("mock value cells: %d (%s) · chrome cells: %d"
          % (MOCK_CELLS, MOCK_GLYPHS, len(MOCK_CHROME)))
    print("kinds  : %d rows" % len(S.KINDS))
    print("tabs   : %d" % 4)
    print("mock css parse holes: %d" % bad)
    if SHOTS:
        print("terminal shots: %d (%s)" % (len(SHOTS), " ".join(sorted(SHOTS))))
    else:
        print("terminal shots: none — run tests/Biotak_StripShot_Test.mq4 on a chart")
    print("-> %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
