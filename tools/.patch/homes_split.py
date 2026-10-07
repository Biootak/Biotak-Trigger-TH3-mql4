#!/usr/bin/env python3
"""P-SIZE-1500 / contract 7: BiotakMenu_A.mqh is 1532 lines and a file over the
ceiling never grows. The seam it already has is THE HOMES: the place of the three
placeable surfaces, one owner. Cut lines 735..887 into Biotak/BiotakHomes.mqh and
include it ABOVE BiotakMenu_A.mqh -- MQL4 resolves a call top-down, and every
reader of a home (LoadUIPlaces, SaveUIStates, the orb's release, the chip's drag)
lives below the cut."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
a_path = root / "Biotak" / "BiotakMenu_A.mqh"
h_path = root / "Biotak" / "BiotakHomes.mqh"

src = a_path.read_text(encoding="utf-8", newline="")
lines = src.split("\n")
print("lines before:", len(lines))

START = 735  # 1-based: the P-UI-118 comment block for CircDefaultMenuPos
END = 887    # 1-based: the closing brace of GVHomeLoadFrac
first = lines[START - 1]
last = lines[END - 1]
assert first.startswith("//+"), repr(first)
assert last == "}", repr(last)
assert "CircDefaultMenuPos" in "\n".join(lines[START - 1:END])
assert "GVHomeLoadFrac" in "\n".join(lines[START - 1:END])

block = lines[START - 1:END]

header = [
    "// BiotakHomes.mqh - the PLACE of the three placeable surfaces, split out of",
    "// BiotakMenu_A.mqh on 2026-10-05 because that file reached 1532 lines and",
    "// contract 7 says a file over the 1500-line ceiling never grows (P-SIZE-1500):",
    "// touch it = split it by owner. This IS that owner - one home per surface, the",
    "// fraction it is stored as, and the one default when there is no home at all.",
    "//",
    "// MUST be included ABOVE BiotakMenu_A.mqh: MQL4 resolves a call top-down, and",
    "// every reader of a home (LoadUIPlaces, SaveUIStates, the orb's release, the",
    "// chip's drag) lives below the cut, so a half included under them is error 168.",
    "#ifndef BIOTAK_HOMES_MQH",
    "#define BIOTAK_HOMES_MQH",
    "",
]
footer = ["", "#endif // BIOTAK_HOMES_MQH", ""]
h_path.write_text("\n".join(header + block + footer), encoding="utf-8", newline="")
print("wrote BiotakHomes.mqh:", len(header) + len(block) + len(footer), "lines")

rest = lines[:START - 1] + lines[END:]
out = "\n".join(rest)

inc = '#include "BiotakHomes.mqh"'
old = '#include "HTFCandles.mqh"'
assert out.count(old) == 1
out = out.replace(old, old + "\n" + inc, 1)
assert out.count(inc) == 1

a_path.write_text(out, encoding="utf-8", newline="")
print("lines after:", len(out.split("\n")))
