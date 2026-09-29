#!/usr/bin/env python3
"""
icon-sheet.py — EVERY bake the strip paints, at 1:1 and at 4x, with the numbers
that decide whether it reads: its own size, the seat it lands in, and the air
around it.

  python tools/icon-sheet.py             -> tools/icon-sheet.html
  python tools/icon-sheet.py out.html    -> that file

The list is not typed here: it is the icon ops of the surfaces this repo's sims
already paint (tools/sim-strip-panels.py for the quick row of every kind, the
colour board and the settings panel; tools/sim-gear-panel.py for the four tabs).
So the sheet answers "which bake is actually shown, where, and how big" from the
same mirrors the gates read — a bake the strip never paints does not appear, and
one it paints cannot hide.

Why it exists: MT4 crops a bitmap label at its NATIVE size and never scales it
(DrawStripFaceZ centres it in the seat), so a 24px glyph in a 32px cell leaves
4px of air on every side and a 15px glyph leaves 8. That ratio, not taste, is
what makes a cell read at chart zoom — and it is a number the sheet prints.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S = load("simstrip", os.path.join(HERE, "sim-strip-panels.py"))
G, mt4 = S.G, S.mt4


def surfaces():
    """(label, canvas) for every surface the strip owns — the icon ops' source."""
    out = []
    for k in S.KINDS:
        cells = S.strip_cells(k, {}, border=S.KIND_BORDER, fill=S.KIND_FILL)
        c, _n, _L = S.paint_strip(cells, S.kind_name(k) + " 1",
                                  act_on=[False] * S.ACT_N, pick_open=False)
        out.append(("row · %s" % k, c))
    c, _n, _L = S.paint_strip()                    # the box frame (picker + gear open)
    out.append(("row · DK_RECT (picker+gear open)", c))
    bc, _n, _L = S.paint_board()
    out.append(("colour board", bc))
    for tab in range(4):
        L = G.layout(tab)
        out.append(("panel · tab %d %s" % (tab + 1, G.TABS[tab]), G.paint(L, [], tab)))
    fb = S.gear_for("DK_FIBO")
    out.append(("panel · DK_FIBO tab 1", fb.paint(fb.layout(0), [], 0)))
    return out


def collect():
    """{bake: {(seat, canvas-kind): count}} and {bake: [where it is painted]}.

    A bake's SEAT is the cell it is centred in, and DrawStripFaceZ centres it as
    `x+(w-pw)/2, y+(h-ph)/2` — the op itself records the ART's size at its placed
    corner, so the seat is only known at the call. `S.face` is the one call the
    strip's painter goes through, so it is wrapped and asked; the panel (G) calls
    c.img with the slice rect it means, and there the rect IS the seat.
    """
    seats, where = {}, {}
    calls = []
    orig = S.face

    def rec(c, res, x, y, w, h, z=1):
        calls.append((res, w, h, "cell"))
        return orig(c, res, x, y, w, h, z)

    S.face = rec
    try:
        surfaces_list = surfaces()
    finally:
        S.face = orig
    for res, w, h, kind in calls:
        seats.setdefault(res, {})
        seats[res][(w, h, kind)] = seats[res].get((w, h, kind), 0) + 1
    for label, c in surfaces_list:
        for op in c.ops:
            if op[0] != "img" or op[1] is None:
                continue
            name, w, h = op[1], op[4], op[5]
            if name in seats:
                where.setdefault(name, set()).add("%s @%dx%d" % (label, w, h))
                continue                     # a cell the strip placed (above)
            seats.setdefault(name, {})
            seats[name][(w, h, "slice")] = seats[name].get((w, h, "slice"), 0) + 1
            where.setdefault(name, set()).add("%s @%dx%d slice" % (label, w, h))
    return seats, where


def family(name):
    p = name.split("_")[0]
    return {"ds": "1 · the plate's 9-slice", "pnl": "2 · panel cards & chips",
            "gl": "3 · glyphs (gl_*)", "bk": "4 · strip glyphs (bk_*)",
            "dsg": "2 · panel cards & chips"}.get(p, "9 · other")


def native(name):
    try:
        w, h, _px = mt4.read_bmp(os.path.join(mt4.ICONS, name))
        return w, h
    except Exception:
        return None


def visible(path):
    """(w, h) of the NON-TRANSPARENT pixels — the size the eye gets.

    A glyph bake may carry a transparent frame (glyphSkin pads by GLYPH_PAD), so
    the FILE's size and the ART's size are different questions: the air that
    decides whether a cell reads is the air around what is painted, not around
    the bitmap's edge.
    """
    try:
        w, h, rgba = mt4.read_bmp(path)
    except Exception:
        return None
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if rgba[row + x * 4 + 3]:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    if x1 < 0:
        return (0, 0)
    return (x1 - x0 + 1, y1 - y0 + 1)


ROOT = os.path.dirname(HERE)
BEFORE = os.path.join(ROOT, "build-logs", "before", "Files", "Icons")
_BEFORE = {}


def ensure_before():
    """The committed bakes, beside the working tree's — the icon change's own
    BEFORE column. `git archive HEAD` into the gitignored build dir, once."""
    if os.path.isdir(BEFORE) and os.listdir(BEFORE):
        return True
    os.makedirs(BEFORE, exist_ok=True)
    import subprocess
    cmd = 'git archive HEAD Files/Icons | tar -x -C "%s"' % os.path.join(ROOT, "build-logs", "before")
    return subprocess.run(cmd, shell=True, cwd=ROOT).returncode == 0


def before_art(name):
    """(data-URI, w, h) of the HEAD bake, or None when HEAD has no such file."""
    if name not in _BEFORE:
        p = os.path.join(BEFORE, name)
        if not os.path.exists(p):
            _BEFORE[name] = None
        else:
            import base64
            w, h, rgba = mt4.read_bmp(p)
            _BEFORE[name] = ("data:image/png;base64,"
                             + base64.b64encode(mt4.png(w, h, rgba)).decode(), w, h)
    return _BEFORE[name]


def tile(name, scale):
    return ("<img src='%s' style='width:%dpx;height:%dpx;image-rendering:pixelated'>"
            % (mt4.uri(name)[0], (native(name) or (0, 0))[0] * scale,
               (native(name) or (0, 0))[1] * scale))


def tile_before(name, scale):
    art = before_art(name)
    if art is None:
        return "—"
    return ("<img src='%s' style='width:%dpx;height:%dpx;image-rendering:pixelated'>"
            % (art[0], art[1] * scale, art[2] * scale))


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") \
        else os.path.join(HERE, "icon-sheet.html")

    seats, where = collect()
    ensure_before()
    rows = []
    holes = []
    tight = []
    grew = []
    for name in sorted(seats):
        nat = native(name)
        if nat is None:
            holes.append(name)
            continue
        nw, nh = nat
        art = before_art(name)
        if art is not None and (art[1], art[2]) != (nw, nh):
            grew.append((name, art[1], nw))
        for (sw, sh, kind), n in sorted(seats[name].items()):
            if kind == "slice":
                rows.append(dict(name=name, fam=family(name), nw=nw, nh=nh,
                                 sw=sw, sh=sh, air=None, n=n, kind=kind,
                                 where=" · ".join(sorted(where[name]))))
                continue
            vis = visible(os.path.join(mt4.ICONS, name)) or (nw, nh)
            # the glyph's LONGEST side against the seat: a padlock is tall and
            # thin, a half-fill is wide and short, and neither is a small glyph.
            pct = int(round(100.0 * max(vis) / max(sw, sh))) if sw and sh else 0
            rows.append(dict(name=name, fam=family(name), nw=nw, nh=nh,
                             vw=vis[0], vh=vis[1], sw=sw, sh=sh, pct=pct, n=n, kind=kind,
                             where=" · ".join(sorted(where[name]))))
            # a cell whose art fills (almost) nothing is the one that reads as
            # a smudge at chart zoom — the number, not a judgement.
            if sw == sh == 32 and max(vis) <= 22:
                tight.append((name, vis[0], vis[1], pct))

    rows.sort(key=lambda r: (r["fam"], r.get("pct", 999), r["name"]))
    body = []
    fam = None
    for r in rows:
        if r["fam"] != fam:
            fam = r["fam"]
            body.append("<h2>%s</h2><table><tr><th>بیک</th>"
                        "<th class='grp'>قبل (HEAD)</th><th class='grp'>قبل ۴×</th>"
                        "<th class='grp'>بعد ۱:۱</th><th>بعد ۴×</th>"
                        "<th>اندازه (قبل → بعد)</th><th>صندلی</th>"
                        "<th>ارتفاع دیده / سلول</th>"
                        "<th>رنگ‌زنی</th><th>کجا</th></tr>" % fam)
        bart = before_art(r["name"])
        if bart is None:
            bsize, b1, b4 = "—", "—", "—"
            changed = False
        else:
            changed = (bart[1], bart[2]) != (r["nw"], r["nh"])
            # `<span dir=ltr>`: in an RTL cell the browser reverses the visual
            # order of "15 → 22" and the row then reads as if the art shrank.
            bsize = ("<span dir='ltr'>%d → %d</span>" % (bart[1], r["vw"])) if "vw" in r \
                else ("<span dir='ltr'>%d×%d → %d×%d</span>"
                      % (bart[1], bart[2], r["nw"], r["nh"])) if bart else "—"
            b1, b4 = tile_before(r["name"], 1), tile_before(r["name"], 4)
        cls = " class='chg'" if changed else ""
        if "pct" not in r:                         # a 9-slice piece, not a cell
            body.append("<tr%s><td class='nm'>%s</td><td>%s</td><td>%s</td>"
                        "<td>%s</td><td>%s</td><td>%s</td><td>%dx%d slice</td><td>—</td>"
                        "<td>%d</td><td class='wh'>%s</td></tr>"
                        % (cls, r["name"], b1, b4, tile(r["name"], 1), tile(r["name"], 4),
                           bsize, r["sw"], r["sh"], r["n"], r["where"]))
            continue
        pct_ink = "#FF8A8A" if r["pct"] <= 45 else ("#FFC247" if r["pct"] <= 70 else "#12B886")
        body.append("<tr%s><td class='nm'>%s</td><td>%s</td><td>%s</td>"
                    "<td>%s</td><td>%s</td><td>%s</td>"
                    "<td><span dir='ltr'>%d×%d · %d×%d</span></td>"
                    "<td style='color:%s'>%d%%</td><td>%d</td><td class='wh'>%s</td></tr>"
                    % (cls, r["name"], b1, b4, tile(r["name"], 1), tile(r["name"], 4),
                       bsize, r["nw"], r["nh"], r["vw"], r["vh"], pct_ink, r["pct"],
                       r["n"], r["where"]))
    body.append("</table>")

    page = """<html dir="rtl"><head><meta charset="utf-8">
<title>بیک‌های استریپ — ورق آیکن</title><style>
body{background:#0f1320;color:#CBD4E2;font:12px Vazirmatn,Tahoma,Arial;margin:0;padding:18px}
h1{font-size:15px;color:#F3F6FB;margin:0 0 6px}
h2{font-size:12.5px;color:#FFC247;margin:22px 0 8px}
.sub{color:#8C96A6;font-size:11.5px;line-height:1.9;max-width:1000px;margin-bottom:8px}
table{border-collapse:collapse;font-size:11px}
th{text-align:right;color:#6C7A90;font-weight:400;padding:4px 8px;border-bottom:1px solid #222832}
td{padding:4px 8px;border-bottom:1px solid #161B26;vertical-align:middle}
td.nm{font:11px Consolas,monospace;color:#CBD4E2;direction:ltr}
td.wh{font:9px Consolas,monospace;color:#5c6a80;direction:ltr;max-width:420px}
td img{display:block;background:#171C25;border-radius:4px}
.note{font-size:11px;color:#8C96A6;line-height:1.9;margin:10px 0 0}
.note b{color:#FF8A8A}
tr.chg td{background:#1a1408}
tr.chg td.nm{color:#FFC247}
th.grp{color:#8C96A6}
</style></head><body>
<h1>ورق بیک‌های استریپ — هر آیکنی که نوار واقعاً می‌کشد</h1>
<div class="sub">
هر ردیف یک بیکِ واقعی از Files/Icons/ است: ستون ۱:۱ در اندازه‌ی خودش، ستون ۴× برای دیدن
پیکسل‌ها، و سه عددی که تصمیم می‌گیرد در چارت خوانا هست یا نه — اندازه‌ی خودِ بیک، صندلی
(سلولی که در آن می‌نشیند) و <b>هوا</b> = (صندلی − بیک) ÷ ۲ که MT4 دور آیکن می‌گذارد، چون
بیت‌مپ را در اندازه‌ی خودش می‌کشد و هرگز مقیاس نمی‌کند (DrawStripFaceZ).
فهرست از خودِ سیم‌ها می‌آید: هر بیکی که این نوار می‌کشد اینجاست و هر بیکی که نمی‌کشد نیست.
</div>
<div class="note">ستون آخرِ عددها ارتفاعِ <b>دیده‌شده</b> (کادر غیرشفاف) به ارتفاع سلول است:
زیر ۴۵٪ آیکن در سلول گم می‌شود، بالای ۷۰٪ درست می‌نشیند. ستون <b style='color:#FFC247'>قبل (HEAD)</b> همان بیکِ
کامیت‌شده است (git archive HEAD) و ستون بعد همان فایل روی دیسک؛ ردیفی که اندازه‌اش
عوض شده، پس‌زمینه‌ی کهربایی دارد.</div>
<div class="note">%s</div>
%s
</body></html>""" % (
        "بیک‌های گمشده (رنگ‌زنی صندلی بدون فایل): <b>%s</b>" % ", ".join(holes)
        if holes else "همه‌ی بیک‌های رنگ‌شده روی دیسک هستند.",
        "\n".join(body))

    open(out, "w", encoding="utf-8").write(page)
    print("bakes painted: %d (%d distinct)" % (sum(r["n"] for r in rows), len(rows)))
    print("families: %s" % ", ".join(sorted({r["fam"] for r in rows})))
    print("cells whose VISIBLE art is <= 22px tall in a 32px seat: %d" % len(tight))
    for n, vw, vh, pct in sorted(tight, key=lambda t: t[3]):
        print("   %-22s visible %dx%d  %d%% of the cell" % (n, vw, vh, pct))
    print("bakes resized since HEAD: %d" % len(grew))
    for n, b, a in grew:
        print("   %-24s %2dpx -> %2dpx" % (n, b, a))
    print("missing bakes: %s" % (holes or "none"))
    print("-> %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
