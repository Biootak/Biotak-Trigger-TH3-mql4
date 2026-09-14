"""slice-card-skins — turn ONE baked wide card skin into a STRETCHABLE body.

WHY THIS EXISTS (P-UI-71b)
-------------------------
The card's background is a baked 32-bit bitmap (`pnl_cardW{n}.bmp`), and an
OBJ_BITMAP_LABEL renders at its native size — the panel cannot stretch it. So
the height of a wide card was pinned to the tallest skin that had been baked:

    PNL_WIDE_ROWS_MAX 12      (pnl_cardW1..W12 exist)
    card 2   needs 13 pair-lines  ->  42 px of the card had NO background
    card 12  needs 19 pair-lines  -> 294 px (seven lines!) had NONE

and every row below the skin drew straight on the chart: the user's "the colour
row can be pulled off the panel and clicking it does nothing" is that missing
body (the cells are painted, the card behind them is not).

The fix is not more baked sizes (W12 is already 1.6 MB; W13..W19 would add
~25 MB to a 47 MB asset dir). It is to make the body COMPOSABLE: the skin is a
flat 3-stop gradient at a fixed width, so ONE header cap + ONE repeated line
band + ONE footer cap covers every height exactly, on the 42 px row grid.

The pieces are SLICED from an existing skin rather than re-drawn, so the pixels
are the generator's own (no second implementation of the radius, the border, the
shadow or the hairline can drift from it).

    skin rows            piece                 covers (card-local)
    [0, 70)              pnl_cardWtop.bmp      -14 .. 56   (margin + header)
    [70+6r, 70+7r)       pnl_cardWmid.bmp      one line band, 42 px tall
    [H-62, H)            pnl_cardWbot.bmp      the footer + bottom margin
    [H-62-26, H-62)      pnl_cardWfade.bmp     the 26 px fade wash `.fade`

The tile is taken from the MIDDLE line band, not the first: the body is flat,
so the tile's own tone is what the whole body shows, and the middle of the baked
ramp is the tone that keeps the top and bottom caps' blend smallest.

The fade is its own overlay (the `.f` skins differ from the plain ones ONLY in
that band — asserted below), so `f` and non-`f` cards share the same three
pieces and no `W{n}f` skin has to be baked either.

    python tools/slice-card-skins.py            # write the pieces + verify
    python tools/slice-card-skins.py --check    # verify only (the gate)
"""

import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "Files", "Icons")

# --- geometry, mirrored from Biotak/BiotakPanels.mqh + tools/gen-th3-icons.js
PNL_HEAD_H = 56
PNL_ROW_H = 42
PNL_FOOT_H = 48
PNL_MARGIN = 14
PNL_WIDE_WEL = 624
FADE_BAND = 26

SOURCE = "pnl_cardW12.bmp"       # any fully-baked wide skin (has the footer cap)
SOURCE_FADE = "pnl_cardW12f.bmp"  # the same skin with the fade wash baked in

TOP_H = PNL_MARGIN + PNL_HEAD_H          # 70 — margin + header
MID_H = PNL_ROW_H                        # 42 — one line band, on the row grid
# the tile's own band: line 6 of a 12-line skin (the ramp's midpoint)
MID_FROM = TOP_H + 6 * MID_H
BOT_H = PNL_FOOT_H + PNL_MARGIN          # 62 — footer + bottom margin
WIDTH = PNL_WIDE_WEL + 2 * PNL_MARGIN    # 652

def read_bmp(path):
    """(w, h, rows) with rows top-down, each a bytes row of 4-byte pixels."""
    with open(path, "rb") as fh:
        blob = fh.read()
    if blob[:2] != b"BM":
        raise SystemExit("%s is not a BMP" % path)
    off = struct.unpack_from("<I", blob, 10)[0]
    _, w, h, planes, bpp = struct.unpack_from("<IiiHH", blob, 14)
    if bpp not in (24, 32):
        raise SystemExit("%s: unexpected %d bpp" % (path, bpp))
    if h < 0:                        # top-down
        h = -h
        rows = [blob[off + y * w * (bpp // 8): off + (y + 1) * w * (bpp // 8)]
                for y in range(h)]
    else:                            # bottom-up (what the generator writes)
        stride = ((w * bpp // 8) + 3) // 4 * 4
        rows = [blob[off + y * stride: off + y * stride + w * (bpp // 8)]
                for y in range(h)]
        rows.reverse()
    return w, h, bpp, rows


def write_bmp(path, w, h, bpp, rows):
    stride = ((w * bpp // 8) + 3) // 4 * 4
    pad = b"\x00" * (stride - w * (bpp // 8))
    body = b"".join(rows[y] + pad for y in range(h - 1, -1, -1))   # bottom-up
    hdr = b"BM" + struct.pack("<IHHI", 14 + 40 + len(body), 0, 0, 14 + 40)
    info = struct.pack("<IiiHHIIiiII", 40, w, h, 1, bpp, 0, len(body),
                       2835, 2835, 0, 0)
    with open(path, "wb") as fh:
        fh.write(hdr + info + body)


def build():
    src = os.path.join(ICONS, SOURCE)
    srcf = os.path.join(ICONS, SOURCE_FADE)
    if not os.path.exists(src):
        raise SystemExit("missing source skin: %s" % src)
    w, h, bpp, rows = read_bmp(src)
    if w != WIDTH:
        raise SystemExit("%s is %d px wide, expected %d" % (SOURCE, w, WIDTH))
    if h != PNL_HEAD_H + 12 * PNL_ROW_H + PNL_FOOT_H + 2 * PNL_MARGIN:
        raise SystemExit("%s is not a 12-pair-line wide skin (h=%d)" % (SOURCE, h))

    # 1. the geometry must tile: top + n*mid + bot == the whole skin, on the grid
    if TOP_H + 12 * MID_H + BOT_H != h:
        raise SystemExit("the three pieces do not tile a 12-line skin")

    # 2. the fade band must be the ONLY thing `f` adds
    wf, hf, _, rowsf = read_bmp(srcf)
    if (wf, hf) != (w, h):
        raise SystemExit("%s does not match %s" % (SOURCE_FADE, SOURCE))
    diff = [y for y in range(h) if rowsf[y] != rows[y]]
    fade0 = h - PNL_MARGIN - PNL_FOOT_H - FADE_BAND
    fade1 = h - PNL_MARGIN - PNL_FOOT_H
    # a SUBSET test, not equality: the wash's own top edge can land on the same
    # pixels as the plain skin (2 of the 26 rows here), and "f adds nothing but
    # the wash" is the invariant - not "f touches every row of the band".
    outside = [y for y in diff if not (fade0 <= y < fade1)]
    if not diff or outside:
        raise SystemExit("`%s` differs from `%s` outside the fade band "
                         "(rows %s, band is %d..%d)"
                         % (SOURCE_FADE, SOURCE, outside or "nowhere",
                            fade0, fade1 - 1))

    pieces = {
        "pnl_cardWtop.bmp": rows[0:TOP_H],
        "pnl_cardWmid.bmp": rows[MID_FROM:MID_FROM + MID_H],
        "pnl_cardWbot.bmp": rows[h - BOT_H:h],
        "pnl_cardWfade.bmp": rowsf[fade0:fade1],
    }

    # 3. prove the composition BEFORE writing: rebuild a 12-line body and
    # compare it with the skin it came from. A tiling error shows up here, not
    # as a transparent stripe on a user's chart.
    composed = pieces["pnl_cardWtop.bmp"] + pieces["pnl_cardWmid.bmp"] * 12 \
        + pieces["pnl_cardWbot.bmp"]
    if len(composed) != h:
        raise SystemExit("composed height %d != skin height %d"
                         % (len(composed), h))

    # The tiled body is FLATTER than the baked gradient (the tile is one band,
    # repeated), so byte equality is the wrong test. What must hold:
    #   (1) no HOLE - every pixel the skin paints opaque, the composition paints
    #       opaque too. A mis-tiled body shows up here as a transparent stripe,
    #       which is the only failure that matters on screen.
    #   (2) the tone stays inside the card's own ramp - a wrong piece (a footer
    #       in the middle, a whole-skin slice) would blow past it.
    holes = 0
    worst = 0
    for y in range(h):
        a, b = rows[y], composed[y]
        for x in range(PNL_MARGIN, WIDTH - PNL_MARGIN):
            o = x * 4
            if b[o + 3] < a[o + 3]:            # less opaque than the skin
                holes += 1
            for c in range(3):
                worst = max(worst, abs(b[o + c] - a[o + c]))
    if holes:
        raise SystemExit("the composed body leaves %d pixel(s) LESS OPAQUE than "
                         "the skin - a hole in the card" % holes)
    if worst > 12:
        raise SystemExit("the composed body drifts %d levels from the card's own "
                         "ramp - a piece is not a body slice" % worst)
    steps = worst

    for name, pix in pieces.items():
        write_bmp(os.path.join(ICONS, name), w, len(pix), bpp, pix)
    return pieces, h, steps


def main():
    pieces, h, steps = build()
    print("card-body pieces%s:" % (" (verified)" if "--check" in sys.argv
                                   else " (written)"))
    for name in sorted(pieces):
        print("  %-20s %4d rows" % (name, len(pieces[name])))
    print("  composition: top + 12*mid + bot == %d rows  (skin %d), no holes,"
          % (h, h))
    print("  worst channel drift from the baked ramp: %d/255 (the tiled band is "
          "flatter than the gradient; the panel draws its own separator on every "
          "row boundary, which is where a repeated tile seams)" % steps)
    return 0


if __name__ == "__main__":
    sys.exit(main())
