#!/usr/bin/env python3
"""DEPRECATED - do NOT use for the shipped icon set.

This script renders flat Feather-style glyphs as 24-bit BMPs with the panel
background baked in (NO alpha channel). Running it (or convert_icons_24bit.py)
on Files/Icons produced the "flat square tile" look and destroyed the alpha
of the premium gold set (see AGENTS.md -> R-ICONS / P-ICONS-01).

The canonical icon sources are the 32-bit BGRA generators:
    tools/gen-icons.ps1  (ring glyphs, circ, orb, badge, yy, knobs, switches)
    tools/gen-cards.ps1  (panel card surfaces)
Keep Files/Icons/*.bmp as 32-bit with alpha - MT4 shows them correctly because
BiotakMenu.mqh / BiotakPanels.mqh embed them via #resource.

Kept only for experiments. Usage:  python gen_icons.py
"""
import math
import os
import struct

SS = 4                    # supersampling factor per axis
BG = (0x10, 0x14, 0x1B)   # panel background baked under the icon
ON = (0x2D, 0xD4, 0xA7)   # neon green
OFF = (0x7D, 0x87, 0x98)  # gray

# ----------------------------------------------------------------------------
# tiny vector rasterizer: geometry is a list of subpaths;
# each subpath = list of (x, y) points in a 24x24 design box.
# ----------------------------------------------------------------------------

def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    if L2 == 0:
        dx, dy = px - ax, py - ay
    else:
        t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / L2))
        dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return math.hypot(dx, dy)


def stroke_coverage(paths, w, h, width, samples=None):
    """Anti-aliased coverage of stroked polylines over an SSx supersample grid."""
    cov = [[0.0] * w for _ in range(h)]
    n = SS * SS
    for iy in range(h):
        for ix in range(w):
            hit = 0
            for sy in range(SS):
                for sx in range(SS):
                    px = ix + (sx + 0.5) / SS
                    py = iy + (sy + 0.5) / SS
                    d = math.inf
                    for pts in paths:
                        for i in range(len(pts) - 1):
                            d = min(d, seg_dist(px, py, *pts[i], *pts[i + 1]))
                    if d <= width / 2:
                        hit += 1
            cov[iy][ix] = hit / n
    return cov


def point_in_poly(px, py, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def fill_coverage(polys, w, h, samples=None):
    cov = [[0.0] * w for _ in range(h)]
    n = SS * SS
    for iy in range(h):
        for ix in range(w):
            hit = 0
            for sy in range(SS):
                for sx in range(SS):
                    px = ix + (sx + 0.5) / SS
                    py = iy + (sy + 0.5) / SS
                    # even-odd rule across all subpaths
                    c = 0
                    for poly in polys:
                        if point_in_poly(px, py, poly):
                            c += 1
                    if c % 2 == 1:
                        hit += 1
            cov[iy][ix] = hit / n
    return cov


def scale_paths(paths, vw, vh, w, h, inset=1.5):
    """Map design box (vw x vh) onto the target (w x h) keeping aspect, centered."""
    s = min((w - 2 * inset) / vw, (h - 2 * inset) / vh)
    ox = (w - vw * s) / 2
    oy = (h - vh * s) / 2
    return [[(x * s + ox, y * s + oy) for (x, y) in path] for path in paths]


def circle_pts(cx, cy, r, seg=48):
    return [(cx + r * math.cos(2 * math.pi * i / seg),
             cy + r * math.sin(2 * math.pi * i / seg)) for i in range(seg + 1)]


def roundrect_pts(x, y, w, h, r, seg=8):
    pts = []
    for cx, cy, a0, a1 in ((x + w - r, y + r, -90, 0), (x + w - r, y + h - r, 0, 90),
                           (x + r, y + h - r, 90, 180), (x + r, y + r, 180, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + (a1 - a0) * i / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def arrow(pts):
    """Insert arrowhead as extra stroke subpath (given main polyline)."""
    return pts


# ----------------------------------------------------------------------------
# icon geometry in a 24x24 design box (or custom vw x vh)
# ----------------------------------------------------------------------------

def G_chk():
    box = roundrect_pts(3.5, 3.5, 17, 17, 5)
    mark = [(8.3, 12.3), (11.3, 15.3), (16.6, 9)]
    return [], [box, mark]

def G_zone():
    box = roundrect_pts(3, 8, 18, 8, 1.5)
    line = [(4, 14.5), (8.5, 10.5), (12, 13), (17, 9.5), (20, 11.5)]
    return [box], [line]

def G_dots():
    # filled dots of gently growing size - cleaner than stroked rings
    c1 = circle_pts(5, 16.5, 1.5)
    c2 = circle_pts(12, 12, 2.0)
    c3 = circle_pts(19, 7.5, 2.5)
    return [c1, c2, c3], []

def G_tl():
    line = [(3.5, 18.5), (10, 12), (14, 15), (20.5, 6.5)]
    head = [(15.5, 6), (20.5, 6.5), (20, 12)]
    return [], [line, head]

def G_box():
    cube = [(12, 2.5), (20.5, 7.3), (20.5, 16.7), (12, 21.5), (3.5, 16.7), (3.5, 7.3), (12, 2.5)]
    top = [(3.5, 7.3), (12, 12.1), (20.5, 7.3)]
    mid = [(12, 12.1), (12, 21.5)]
    return [], [cube, top, mid]

def G_htf():
    l1 = [(7, 3.5), (7, 20.5)]
    b1 = roundrect_pts(4.3, 9.5, 5.4, 7.5, 1)
    l2 = [(16.5, 5), (16.5, 19)]
    b2 = roundrect_pts(13.8, 8, 5.4, 8.5, 1)
    return [], [l1, b1, l2, b2]

def G_custom():
    segs = [
        [(4, 3), (4, 9.5)], [(4, 14.5), (4, 21)],
        [(12, 3), (12, 12)], [(12, 17), (12, 21)],
        [(20, 3), (20, 16.5)], [(20, 21), (20, 21.01)],
        [(1.5, 12), (6.5, 12)], [(9.5, 14.5), (14.5, 14.5)], [(17.5, 19), (22.5, 19)],
    ]
    return [], segs

def G_pin():
    head = roundrect_pts(8.2, 3.5, 7.6, 5, 1)
    stem = [(12, 8.5), (12, 14)]
    tip = [(9, 14), (15, 14)]
    needle = [(12, 14), (12, 20.5)]
    return [], [head, stem, tip, needle]

def G_tools():
    # simplified wrench: circle head with notch + handle
    head = circle_pts(8.5, 8.5, 4.2)
    notch = [(11.3, 11.3), (8.5, 8.5)]
    handle = [(11.5, 11.5), (20, 20)]
    jaw = [(17.5, 20.5), (20.5, 17.5)]
    return [], [head, notch, handle, jaw]

def G_circ():
    c1 = circle_pts(12, 12, 8.5)
    c2 = circle_pts(12, 12, 4.6)
    dot = circle_pts(12, 12, 1.4)
    return [dot], [c1, c2]

def G_step():
    line = [(3.5, 20), (8, 20), (8, 15.5), (12.5, 15.5), (12.5, 11), (17, 11), (17, 6.5), (20.5, 6.5)]
    return [], [line]

def G_factor():
    # "scale / multiply" glyph: side rails with outward arrows
    lbar = [(3.5, 7), (3.5, 17)]
    rbar = [(20.5, 7), (20.5, 17)]
    lshaft = [(11, 12), (6, 12)]
    lhead = [(8.5, 9.5), (5.5, 12), (8.5, 14.5)]
    rshaft = [(13, 12), (18, 12)]
    rhead = [(15.5, 9.5), (18.5, 12), (15.5, 14.5)]
    return [], [lbar, rbar, lshaft, lhead, rshaft, rhead]

def G_dial():  # knob / pnl_knob
    c = circle_pts(12, 12, 8.5)
    ptr = [(12, 12), (12, 6.2)]
    return [], [c, ptr]

def G_shield(mark=True):  # badge
    sh = [(12, 2.5), (19.5, 5.5), (19.5, 12), (12, 21.5), (4.5, 12), (4.5, 5.5), (12, 2.5)]
    if not mark:
        return [], [sh]
    m = [(8.5, 11.5), (11, 14), (15.5, 9.5)]
    return [], [sh, m]

def G_sw(vw=46, vh=24, on=False):
    track = roundrect_pts(2.5, 3.5, vw - 5, vh - 7, (vh - 7) / 2)
    kx = vw - 13 if on else 13
    knob = circle_pts(kx, vh / 2, 5.2)
    return [], [track, knob], kx

def G_swknob():
    c = circle_pts(12, 12, 7.5)
    return [], [c]


# registry: name -> list of (w, h, fn, vw, vh, stroke_w)
# NOTE: only files the indicator actually #resources are generated; the
# single-file variants (badge/knob/yy) double as their only on/off state.
def registry():
    reg = {}
    # single=True -> the indicator uses only ONE file for this glyph (the lit
    # style), so we must NOT emit <name>_off/_on pairs for it.
    def add(name, w, h, fn, vw=24, vh=24, single=False):
        reg[name] = (w, h, fn, vw, vh, STROKE_BY_W.get(w, 2.0), single)
    add('chk', 28, 28, G_chk)
    add('zone', 28, 28, G_zone)
    add('dots', 28, 28, G_dots)
    add('tl', 28, 28, G_tl)
    add('box', 28, 28, G_box)
    add('htf', 28, 28, G_htf)
    add('custom', 28, 28, G_custom)
    add('pin', 28, 28, G_pin)
    add('tools', 28, 28, G_tools)
    add('circ', 28, 28, G_circ)
    add('step', 28, 28, G_step)
    add('factor', 28, 28, G_factor)
    add('knob', 14, 14, G_dial, single=True)
    add('pnl_knob', 18, 18, G_dial, single=True)
    add('badge', 12, 12, G_shield, single=True)
    add('yy', 32, 32, None, single=True)   # text logo, special-cased
    return reg

SPECIALS = ['pnl_sw_on', 'pnl_sw_off']


# finer strokes for a more delicate look; tiny canvases need relatively
# thicker lines so they don't fade below 1 real px
STROKE_BY_W = {12: 1.45, 14: 1.55, 18: 1.7, 28: 1.75, 32: 2.1, 46: 2.1}


def render(w, h, fills, strokes, vw, vh, color, glow, inset=1.5, stroke_w=2.0):
    """Return (w x h) pixel list of (r,g,b) including glow."""
    scaled_f = scale_paths(fills, vw, vh, w, h, inset) if fills else []
    scaled_s = scale_paths(strokes, vw, vh, w, h, inset) if strokes else []
    f_cov = fill_coverage(scaled_f, w, h) if scaled_f else [[0.0] * w for _ in range(h)]
    s_cov = stroke_coverage(scaled_s, w, h, stroke_w) if scaled_s else [[0.0] * w for _ in range(h)]

    # merge coverages (max)
    cov = [[max(f_cov[y][x], s_cov[y][x]) for x in range(w)] for y in range(h)]

    # glow = blurred coverage (soft, wide, subtle)
    glow_cov = [[0.0] * w for _ in range(h)]
    if glow:
        R = 3
        for y in range(h):
            for x in range(w):
                acc = 0.0
                cnt = 0
                for dy in range(-R, R + 1):
                    for dx in range(-R, R + 1):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w:
                            acc += cov[yy][xx]
                            cnt += 1
                glow_cov[y][x] = min(1.0, acc / cnt * 0.9)

    px = []
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b = BG
            if glow:
                ga = glow_cov[y][x] * 0.22
                r = int(r + (color[0] - r) * ga)
                g = int(g + (color[1] - g) * ga)
                b = int(b + (color[2] - b) * ga)
            a = cov[y][x]
            r = int(r + (color[0] - r) * a)
            g = int(g + (color[1] - g) * a)
            b = int(b + (color[2] - b) * a)
            row.append((min(255, r), min(255, g), min(255, b)))
        px.append(row)
    return px


def render_text_yy(w, h, color, glow):
    """Render 'Yy' with a tiny 5x7 bitmap font style: use block letters."""
    # hand-drawn 'Yy' via strokes in 32x32
    y1 = [(7, 6), (12, 14), (17, 6)]
    y2 = [(12, 14), (12, 22)]
    yl = [(18.5, 12), (18.5, 17.5), (21.5, 19.5), (24.5, 17.5), (24.5, 12),
          (24.5, 17.5), (27.5, 19.5)]
    px = render(w, h, [], [y1, y2, yl], 32, 32, color, glow, inset=2.0, stroke_w=2.4)
    return px


def write_bmp(path, pixels):
    h = len(pixels)
    w = len(pixels[0])
    row24 = ((w * 3 + 3) // 4) * 4
    data = bytearray(54)
    data[0:2] = b'BM'
    struct.pack_into('<I', data, 2, 54 + row24 * h)
    struct.pack_into('<I', data, 10, 54)
    struct.pack_into('<I', data, 14, 40)
    struct.pack_into('<i', data, 18, w)
    struct.pack_into('<i', data, 22, h)  # bottom-up
    struct.pack_into('<H', data, 26, 1)
    struct.pack_into('<H', data, 28, 24)
    struct.pack_into('<I', data, 34, row24 * h)
    pad = b'\x00' * (row24 - w * 3)
    for y in range(h - 1, -1, -1):  # bottom-up
        for (r, g, b) in pixels[y]:
            data += bytes((b, g, r))
        data += pad
    with open(path, 'wb') as f:
        f.write(bytes(data))
    print(f'  wrote {path} ({w}x{h}, {len(data)} bytes)')


def main():
    out = os.path.join('Files', 'Icons')
    os.makedirs(out, exist_ok=True)
    reg = registry()
    print('Generating glyph icons...')
    for name, (w, h, fn, vw, vh, sw, single) in reg.items():
        if single:
            # one lit file only: knob.bmp / pnl_knob.bmp / badge.bmp / yy.bmp
            if fn is None:  # yy
                pixels = render_text_yy(w, h, ON, glow=True)
            elif name == 'badge':
                fills, strokes = G_shield(mark=False)
                pixels = render(w, h, fills, strokes, vw, vh, ON, glow=True,
                                stroke_w=sw, inset=1.8)
            else:
                fills, strokes = fn()
                pixels = render(w, h, fills, strokes, vw, vh, ON, glow=True,
                                stroke_w=sw)
            write_bmp(os.path.join(out, f'{name}.bmp'), pixels)
            continue
        for on in (False, True):
            color = ON if on else OFF
            fills, strokes = fn()
            pixels = render(w, h, fills, strokes, vw, vh, color, glow=on,
                            stroke_w=sw)
            write_bmp(os.path.join(out, f'{name}_{"on" if on else "off"}.bmp'), pixels)
    # pnl_sw on/off
    for on in (False, True):
        w, h = 46, 24
        fills, strokes, kx = G_sw(46, 24, on)
        pixels = render(w, h, fills, strokes, 46, 24, ON if on else OFF, glow=on,
                        stroke_w=STROKE_BY_W[46])
        write_bmp(os.path.join(out, f'pnl_sw_{"on" if on else "off"}.bmp'), pixels)
    # single-file resources used directly by the code are handled above
    print('Done.')


if __name__ == '__main__':
    main()
