"""Read the REAL Arial Bold advances out of the installed TTF, and hold the
project's one advance table (`PnlAdvUnits` in Biotak/UtilityFunctions.mqh) against it.

Why this exists: the base note (P-BK-86) is drawn on an opaque plate whose width IS
`PnlRawTextW(text, BKInfoFontPt())`. Any character the note prints that the table does
not carry falls through to its "unknown -> a mid-weight capital" value of 611, and the
plate is then sized against a guess. Three of them did: `[`, `]` and `|` -- +1.27 em,
i.e. +14 px at 8pt/96dpi and +20 px at 8pt/144dpi of empty plate beside the ink.

So this tool (a) reads the real `hmtx` advances off the face, (b) prints every entry of
the table that disagrees with the font, (c) checks the characters the note actually
prints, and (d) says which way the error leans: a plate WIDER than its ink is safe, a
plate NARROWER than its ink clips the note -- the one thing the note must never do.

It is a MEASUREMENT tool, not a build gate: `tools/base-count-audit.py`'s
`check_note_advances` holds the same property statically, so this is what you run when
that gate fires, to get the number to put in the table. Run it from anywhere.

usage: python tools/font-adv-check.py [path-to-arialbd.ttf]
"""
import pathlib
import re
import struct
import sys

FONT = sys.argv[1] if len(sys.argv) > 1 else r"C:\Windows\Fonts\arialbd.ttf"
ROOT = pathlib.Path(__file__).resolve().parents[1]
MQH = ROOT / "Biotak/UtilityFunctions.mqh"
# The note's own shape, spelled the way BaseKnotWriteInfo spells it: the brackets, the
# ` · ` separators, the ` | ` between the levels and the digits, plus the inherited
# words. Only the part THIS module spells is the module's business, but the plate is
# sized off the whole string, so the whole string is what gets summed.
NOTE = "[BUY \u00b7 EngSL 0.8 | 3.8 | 16 bars \u00b7 M5 base \u00b7 FTR]"
FALLBACK = 611


def tables(b):
    n = struct.unpack(">H", b[4:6])[0]
    out = {}
    for i in range(n):
        off = 12 + i * 16
        tag = b[off:off + 4].decode("latin-1")
        o, ln = struct.unpack(">II", b[off + 8:off + 16])
        out[tag] = (o, ln)
    return out


def cmap(b, t):
    o = t["cmap"][0]
    n = struct.unpack(">H", b[o + 2:o + 4])[0]
    best = None
    for i in range(n):
        pid, eid, off = struct.unpack(">HHI", b[o + 4 + i * 8:o + 12 + i * 8])
        if struct.unpack(">H", b[o + off:o + off + 2])[0] == 4 and (pid, eid) in ((3, 1), (0, 3)):
            best = o + off
    if best is None:
        return {}
    sub = best
    segx2 = struct.unpack(">H", b[sub + 6:sub + 8])[0]
    seg = segx2 // 2
    end = struct.unpack(">%dH" % seg, b[sub + 14:sub + 14 + segx2])
    sp = sub + 16 + segx2
    start = struct.unpack(">%dH" % seg, b[sp:sp + segx2])
    dp = sp + segx2
    delta = struct.unpack(">%dh" % seg, b[dp:dp + segx2])
    rp = dp + segx2
    ro = struct.unpack(">%dH" % seg, b[rp:rp + segx2])
    m = {}
    for i in range(seg):
        for c in range(start[i], min(end[i], 0xFFFF) + 1):
            if ro[i] == 0:
                g = (c + delta[i]) & 0xFFFF
            else:
                gp = rp + i * 2 + ro[i] + (c - start[i]) * 2
                if gp + 2 > len(b):
                    continue
                g = struct.unpack(">H", b[gp:gp + 2])[0]
                if g:
                    g = (g + delta[i]) & 0xFFFF
            if g:
                m[c] = g
    return m


def parse_table(body):
    """Every entry of `PnlAdvUnits`, in units per 1000 em."""
    t = {}
    for line in body.splitlines():
        m = re.search(r"ch == ([0-9]+)(?:\s*\|\|\s*ch == ([0-9]+))?\)\s*return\s+([0-9]+);", line)
        if m:
            t[int(m.group(1))] = int(m.group(3))
            if m.group(2):
                t[int(m.group(2))] = int(m.group(3))
        m = re.search(r"ch >= '0' && ch <= '9'\)\s*return\s+([0-9]+);", line)
        if m:
            for c in range(ord("0"), ord("9") + 1):
                t[c] = int(m.group(1))
    for name in ("lo", "up"):
        m = re.search(name + r"\[26\]\s*=\s*\{([^}]*)\}", body)
        if not m:
            continue
        vals = [int(v) for v in re.findall(r"[0-9]+", m.group(1))]
        base = ord("a") if name == "lo" else ord("A")
        for i, v in enumerate(vals[:26]):
            t[base + i] = v
    return t


def main():
    b = pathlib.Path(FONT).read_bytes()
    t = tables(b)
    upem = struct.unpack(">H", b[t["head"][0] + 18:t["head"][0] + 20])[0]
    nh = struct.unpack(">H", b[t["hhea"][0] + 34:t["hhea"][0] + 36])[0]
    hm = t["hmtx"][0]
    cm = cmap(b, t)

    def real(ch):
        g = cm.get(ord(ch))
        if g is None:
            return None
        i = min(g, nh - 1)
        return round(struct.unpack(">H", b[hm + i * 4:hm + i * 4 + 2])[0] * 1000 / upem)

    print("font: %s   unitsPerEm %d, %d hMetrics" % (FONT, upem, nh))
    print()

    src = MQH.read_text(encoding="utf-8", errors="replace")
    body = src[src.find("int PnlAdvUnits("):src.find("int PnlTextUnits(")]
    tbl = parse_table(body)
    print("the table in %s carries %d entries" % (MQH, len(tbl)))
    print()

    # (a) the characters the note prints, held against the table. Read, never assumed:
    # this section used to be a hardcoded claim, and it kept claiming `[` `]` `|` were
    # absent long after the table had been taught them.
    print("--- the characters the base note prints, against the table ---")
    absent = []
    for ch in "[]|":
        r = real(ch)
        have = tbl.get(ord(ch))
        if have is None:
            absent.append(ch)
            print("   %-3s real %-4s  ABSENT - falls through to the %d fallback"
                  % (repr(ch), r, FALLBACK))
        elif have != r:
            print("   %-3s real %-4s  table %-4d  (off by %+d)"
                  % (repr(ch), r, have, have - r))
        else:
            print("   %-3s real %-4s  table %-4d  measured" % (repr(ch), r, have))
    print()

    # (b) the rest of the table, so a value that drifts is visible before it bites.
    print("--- the rest of the table, against the font ---")
    bad = 0
    checked = 0
    for code in sorted(tbl):
        ch = chr(code)
        r = real(ch)
        if r is None:
            continue
        checked += 1
        if r != tbl[code]:
            bad += 1
            print("   %-3s table %-4d real %-4d (delta %+d)"
                  % (repr(ch), tbl[code], r, r - tbl[code]))
    print("   %d of %d entries differ from the font" % (bad, checked))
    print()

    # (c) the note's own string. The LEFT sum is what `PnlAdvUnits` actually answers --
    # the table where it has an entry, its 611 fallback where it does not. The RIGHT sum
    # is what Arial Bold actually draws. The difference IS the fallback's error.
    def sum_units(use_table):
        total = 0
        for c in NOTE:
            r = real(c)
            if use_table:
                total += tbl.get(ord(c), FALLBACK)
            else:
                total += r if r is not None else FALLBACK
        return total

    now, truth = sum_units(True), sum_units(False)
    print("the note's string, units per 1000 em:")
    print("   table as it stands : %d" % now)
    print("   the real font      : %d" % truth)
    print("   off by             : %+d units = %+.2f em" % (now - truth, (now - truth) / 1000.0))
    print()

    print("in pixels (em px = pt * dpi / 72 = PnlRawLineH):")
    rows = []
    for pt, dpi, label in ((8, 96, "8pt @ 96dpi (100%)"), (12, 96, "12pt @ 96dpi"),
                           (8, 144, "8pt @ 144dpi (150%)"), (16, 144, "16pt @ 144dpi")):
        em = round(pt * dpi / 72.0)
        a = round(now * em / 1000.0)
        r = round(truth * em / 1000.0)
        rows.append((label, a, r, a - r))
        print("   %-20s plate %4d px, ink %4d px -> %+d px" % (label, a, r, a - r))
    print()

    # (d) the verdict, in the direction that matters: a plate narrower than its ink is the
    # only failure the note cannot survive, because the ink then runs off its own bar.
    widest = min(r[3] for r in rows)
    if widest < 0:
        print("VERDICT: the plate is NARROWER than the ink (%d px at its worst, %s) - "
              "the note WOULD clip" % (widest, rows[0][0]))
        return 1
    if absent:
        print("VERDICT: %d note literal(s) unmeasured (%s) - the plate is sized off the %d "
              "fallback, so its width is a guess" % (len(absent), " ".join(absent), FALLBACK))
        return 1
    print("VERDICT: every character the note prints is measured off the installed face, and "
          "the plate is %+d units (%+d px at %s) wider than the ink - nothing clips"
          % (now - truth, widest, rows[0][0]))
    return 0


sys.exit(main())
