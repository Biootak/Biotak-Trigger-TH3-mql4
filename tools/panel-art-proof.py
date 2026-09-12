#!/usr/bin/env python3
"""Render the generated panel BMPs into an HTML proof sheet.

MT4 blits these bitmaps verbatim, so this page IS what the cards will show for
their chrome. Browsers ignore a BMP's alpha channel (they render BI_RGB 32bpp
as opaque), so every skin is re-encoded to PNG here first — a minimal PNG
writer, no Pillow needed (the managed Python is stdlib-only).

Usage: python tools/panel-art-proof.py [out.html]
"""
import base64
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "Files", "Icons")


def read_bmp(path):
    """32bpp BGRA BMP -> (w, h, RGBA bytes, top-down)."""
    d = open(path, "rb").read()
    off = struct.unpack_from("<I", d, 10)[0]
    w, h = struct.unpack_from("<ii", d, 18)
    bpp = struct.unpack_from("<H", d, 28)[0]
    if bpp != 32:
        raise ValueError("%s: expected 32bpp, got %d" % (path, bpp))
    top_down = h < 0
    h = abs(h)
    out = bytearray(w * h * 4)
    for y in range(h):
        src_y = y if top_down else (h - 1 - y)
        srow = off + src_y * w * 4
        drow = y * w * 4
        for x in range(w):
            b, g, r, a = d[srow + x * 4], d[srow + x * 4 + 1], d[srow + x * 4 + 2], d[srow + x * 4 + 3]
            out[drow + x * 4] = r
            out[drow + x * 4 + 1] = g
            out[drow + x * 4 + 2] = b
            out[drow + x * 4 + 3] = a
    return w, h, bytes(out)


def png(w, h, rgba):
    raw = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def uri(name):
    w, h, rgba = read_bmp(os.path.join(ICONS, name))
    return "data:image/png;base64," + base64.b64encode(png(w, h, rgba)).decode(), w, h


def tile(name, label, scale=1, bg="checker"):
    try:
        u, w, h = uri(name)
    except Exception as exc:                                    # noqa: BLE001
        return '<div class="t miss"><b>%s</b><span>%s</span></div>' % (label, exc)
    return ('<div class="t"><div class="cv %s" style="--s:%d">'
            '<img src="%s" width="%d" height="%d"></div>'
            '<b>%s</b><span>%s &middot; %dx%d</span></div>'
            % (bg, scale, u, w, h, label, name, w, h))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "panel_art_proof.html")
    A = ["gold", "jade", "cyan", "violet", "ember", "rose"]

    groups = [
        ("Card skins (incl. the baked soft shadow + .fade)", [
            ("pnl_card6.bmp", "6 rows"),
            ("pnl_card6f.bmp", "6 rows + .fade"),
        ]),
        ("Header chrome", [
            ("pnl_topbar_ember.bmp", ".card::before"),
            ("pnl_mark_ember.bmp", ".mark (ember)"),
            ("gl_wave_i_ember.bmp", ".mark ink"),
            ("pnl_hair_ember.bmp", ".hd::after"),
            ("pnl_keycap.bmp", ".key"),
            ("pnl_xbtn.bmp", ".x"),
            ("gl_x_m.bmp", ".x ink"),
        ]),
        ("Row chrome", [
            ("pnl_chip.bmp", ".gl off"),
            ("pnl_chip_ember.bmp", ".gl on"),
            ("gl_wave_m.bmp", "glyph muted"),
            ("gl_wave_i_ember.bmp", "glyph aInk"),
            ("pnl_sw_off.bmp", ".sw off"),
            ("pnl_sw_on_ember.bmp", ".sw on"),
            ("pnl_dsw_off.bmp", ".dual off"),
            ("pnl_dsw_on_ember.bmp", ".dual on"),
            ("pnl_vchip_ember.bmp", ".val.chip"),
            ("pnl_rail_ember.bmp", ".rail"),
            ("pnl_secdot_ember.bmp", ".row.sec dot"),
            ("pnl_cntchip.bmp", ".cnt"),
            ("pnl_add_ember.bmp", ".q.add"),
            ("pnl_chev_ember.bmp", ".dd .chev"),
            ("pnl_secband.bmp", ".row.sec band"),
            ("pnl_actbg_ember.bmp", ".row.act wash"),
            ("pnl_knob.bmp", "slider knob"),
        ]),
        ("Footer buttons", [
            ("pnl_btn_ghost.bmp", ".btn.ghost (Reset)"),
            ("pnl_btn_prim_ember.bmp", ".btn.primary (Done)"),
            ("gl_reset_m.bmp", "reset ink"),
            ("gl_check_i_ember.bmp", "check aInk"),
        ]),
        ("Accent ramps &mdash; mark chip + ON switch + primary button", [
            ("pnl_mark_%s.bmp" % a, a) for a in A
        ]),
    ]

    parts = []
    for title, items in groups:
        parts.append('<h2>%s</h2><div class="grid">' % title)
        for name, label in items:
            parts.append(tile(name, label))
        parts.append("</div>")

    html = """<!doctype html><meta charset="utf-8">
<title>Panel art proof &mdash; the BMPs MT4 blits</title>
<style>
 :root{--card:#1D222C;--bd:#2C3444;--title:#F3F6FB;--muted:#8C96A6}
 body{margin:0;padding:28px;background:#0E1116;color:var(--title);
      font:13px/1.5 Arial,Helvetica,sans-serif}
 h1{font-size:19px;margin:0 0 6px}
 .sub{color:var(--muted);font-size:12px;margin:0 0 26px;max-width:900px}
 h2{font-size:13px;letter-spacing:.6px;text-transform:uppercase;color:var(--muted);
    margin:30px 0 12px;border-top:1px solid #232A37;padding-top:14px}
 .grid{display:flex;flex-wrap:wrap;gap:14px;align-items:flex-start}
 .t{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:12px;
    min-width:104px;text-align:center}
 .cv{display:grid;place-items:center;margin-bottom:8px}
 .cv.checker{background-image:linear-gradient(45deg,#171C25 25%,transparent 25%),
   linear-gradient(-45deg,#171C25 25%,transparent 25%),
   linear-gradient(45deg,transparent 75%,#171C25 75%),
   linear-gradient(-45deg,transparent 75%,#171C25 75%);
   background-size:10px 10px;background-position:0 0,0 5px,5px -5px,-5px 0;
   background-color:#12161D;border-radius:6px;padding:6px}
 .cv img{image-rendering:pixelated;display:block}
 .t b{display:block;font-size:11px;font-weight:700}
 .t span{display:block;font-size:10px;color:var(--muted);margin-top:2px}
 .t.miss{border-color:#7a2b2b}
</style>
<h1>Panel art proof &mdash; the BMPs MetaTrader blits</h1>
<p class="sub">These are the <b>actual generated files</b> from <code>Files/Icons</code>,
re-encoded to PNG only because browsers ignore a BMP's alpha channel.
MetaEditor embeds them via <code>#resource</code> and MT4 draws them verbatim &mdash;
so this is the chrome the 13 cards render, with no MetaTrader involved.
The card skins carry the soft shadow, the gradient body and the hairlines baked in.</p>
@@TILES@@
""".replace("@@TILES@@", "".join(parts))

    open(out, "w", encoding="utf-8").write(html)
    print("wrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
