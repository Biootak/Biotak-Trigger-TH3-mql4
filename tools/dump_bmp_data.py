#!/usr/bin/env python3
"""Dump every BMP in Files/Icons into icons_bmp_data.js and refresh the
inline BMP_DATA blob embedded in icons_final_check.html.

Usage:  python tools/dump_bmp_data.py
"""
import glob
import json
import os
import re
import struct


def read_bmp(path):
    data = open(path, 'rb').read()
    if data[:2] != b'BM':
        return None
    off = struct.unpack('<I', data[10:14])[0]
    w, h = struct.unpack('<ii', data[18:26])
    bpp, comp = struct.unpack('<HH', data[28:32])
    if bpp != 24 or comp != 0:
        print(f'  skip (not 24-bit): {path}')
        return None
    bottom_up = h > 0
    height = abs(h)
    row = ((w * 3 + 3) // 4) * 4
    px = []
    for yy in range(height):
        src_y = (height - 1 - yy) if bottom_up else yy
        roff = off + src_y * row
        line = []
        for xx in range(w):
            b, g, r = data[roff + xx * 3: roff + xx * 3 + 3]
            line.append((r << 16) | (g << 8) | b)
        px.append(line)
    return {'w': w, 'h': height, 'px': px}


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icons = os.path.join(root, 'Files', 'Icons')
    out = {}
    for f in sorted(glob.glob(os.path.join(icons, '*.bmp'))):
        icon = read_bmp(f)
        if icon:
            out[os.path.basename(f)] = icon
    blob = json.dumps(out, separators=(',', ':'))

    js_path = os.path.join(root, 'icons_bmp_data.js')
    with open(js_path, 'w', newline='\n') as fh:
        fh.write('const BMP_DATA=' + blob + ';\n')
    print(f'wrote {js_path} ({len(out)} icons, {os.path.getsize(js_path)} bytes)')

    html_path = os.path.join(root, 'icons_final_check.html')
    html = open(html_path, encoding='utf-8').read()
    new_html, n = re.subn(
        r'const BMP_DATA=\{.*?\};',
        lambda m: 'const BMP_DATA=' + blob + ';',
        html, count=1, flags=re.S)
    if n:
        with open(html_path, 'w', encoding='utf-8', newline='') as fh:
            fh.write(new_html)
        print(f'patched {html_path}')


if __name__ == '__main__':
    main()
