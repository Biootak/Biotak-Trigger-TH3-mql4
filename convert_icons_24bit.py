#!/usr/bin/env python3
"""DEPRECATED - do NOT run on Files/Icons (see AGENTS.md -> R-ICONS / P-ICONS-01).

This script rewrites 32-bit BMPs in place as 24-bit, discarding the alpha
channel (it blends semi-transparent pixels onto black). That flattened the
premium gold icon set into opaque square tiles with black card corners.

MT4 DOES render 32-bit BGRA BMPs with alpha when they are embedded via
#resource and referenced as "::Files\\Icons\\*.bmp" (how BiotakMenu.mqh /
BiotakPanels.mqh load them). Keep the shipped BMPs 32-bit; regenerate with
tools/gen-icons.ps1 + tools/gen-cards.ps1 if they get mangled.

Kept only for reference.
"""
import glob
import os
import struct


def convert(path: str) -> bool:
    data = open(path, 'rb').read()
    if data[:2] != b'BM':
        print(f"  skip (not BMP): {path}")
        return False
    off_bits = struct.unpack('<I', data[10:14])[0]
    hdr_size = struct.unpack('<I', data[14:18])[0]
    w, h, planes, bpp = struct.unpack('<iiHH', data[18:30])
    comp = struct.unpack('<I', data[30:34])[0]
    if bpp == 24 and comp == 0:
        print(f"  already 24-bit: {path}")
        return False
    if bpp != 32 or comp != 0:
        print(f"  SKIP unsupported (bpp={bpp}, comp={comp}): {path}")
        return False

    # h > 0 => rows stored bottom-up; h < 0 => top-down
    bottom_up = h > 0
    height = abs(h)
    row32 = w * 4
    src = data[off_bits:off_bits + row32 * height]
    if len(src) < row32 * height:
        print(f"  SKIP truncated: {path}")
        return False

    out = bytearray(54)
    out[0:2] = b'BM'
    row24 = ((w * 3 + 3) // 4) * 4
    pixel_bytes = row24 * height
    struct.pack_into('<I', out, 2, 54 + pixel_bytes)   # bfSize
    struct.pack_into('<I', out, 10, 54)                # bfOffBits
    struct.pack_into('<I', out, 14, 40)                # biSize
    struct.pack_into('<i', out, 18, w)                 # biWidth
    struct.pack_into('<i', out, 22, h if bottom_up else -height)  # biHeight (keep orientation)
    struct.pack_into('<H', out, 26, 1)                 # biPlanes
    struct.pack_into('<H', out, 28, 24)                # biBitCount
    struct.pack_into('<I', out, 34, pixel_bytes)       # biSizeImage

    pad = b'\x00' * (row24 - w * 3)
    for row in range(height):
        roff = row * row32
        line = bytearray()
        for x in range(w):
            b, g, r, a = src[roff + x * 4: roff + x * 4 + 4]
            # blend over black so anti-aliased edges keep their shading
            line += bytes((
                b * a // 255,
                g * a // 255,
                r * a // 255,
            ))
        line += pad
        out += line

    with open(path, 'wb') as fh:
        fh.write(out)
    print(f"  converted 32->24 bit: {path} ({len(data)} -> {len(out)} bytes)")
    return True


def main() -> None:
    files = sorted(glob.glob(os.path.join('Files', 'Icons', '*.bmp')))
    print(f"Found {len(files)} BMP files")
    changed = sum(1 for f in files if convert(f))
    print(f"Converted: {changed}/{len(files)}")


if __name__ == '__main__':
    main()
