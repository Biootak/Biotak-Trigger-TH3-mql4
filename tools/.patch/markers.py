#!/usr/bin/env python3
# Which of the gate-required markers survive in the two Toolbar files?
import re

def load(p):
    return open(p, encoding="utf-8").read().replace("\r\n", "\n")

A = load("Biotak/Toolbar_A.mqh")
B = load("Biotak/Toolbar_B.mqh")

checks = [
    ("A", "DrawKindOf refuses a pen child", r"FibPenIsChild\(name\)\) return DK_NONE"),
    ("A", "the width slot reads the stack", r"FibPenLogicalWidth\(name, 0\)"),
    ("A", "levels+colour syncs the pen", r"void DrawLevelsSetColor\([\s\S]{0,400}?FibPenSync\(name, false\)"),
    ("A", "preview colour syncs the pen", r"bool DrawSlotPreviewColor\([\s\S]{0,400}?FibPenSync\(name, false\)"),
    ("A", "render restore syncs the pen", r"if\(changed\) FibPenSync\(name, false\)"),
    ("A", "the shared ink static", r"s_dkAnyClr"),
    ("B", "DRAW_LASTLOOK_SLOT", r"define DRAW_LASTLOOK_SLOT"),
    ("B", "DrawStylePackA", r"double DrawStylePackA"),
    ("B", "DrawStylePackB", r"double DrawStylePackB"),
    ("B", "DrawStyleUnpack", r"void DrawStyleUnpack"),
    ("B", "the save's last-look row", r"DRAW_LASTLOOK_SLOT"),
    ("B", "the slot writer saves", r"s_dkValid\[k\] = true;[\s\S]{0,400}?DrawPresetsSave\(\);"),
    ("B", "the create guard on the value", r"DRAW_CAP_COLOR\) != 0 && \(int\)want >= 0"),
    ("B", "the create falls back to the ink", r"if\(\(int\)want < 0\) want = s_dkAnyClr;"),
    ("B", "the STYLE slot sticks a look", r"FibPenLookSet\(name, lk\)"),
    ("B", "DRAW_SEL_MAX 1", r"#define\s+DRAW_SEL_MAX\s+1\b"),
    ("B", "DrawSelSnapshot", r"int DrawSelSnapshot\("),
    ("B", "DrawStyleApplyToKind skip", r'if\(nm == "" \|\| nm == fromName \|\| DrawIsIndicatorObject\(nm\)\) continue;'),
    ("B", "DrawStyleKindCount", r"int DrawStyleKindCount\("),
    ("B", "the look values 5..7 band (STYLE case)", r"if\(st > \(int\)STYLE_DASHDOTDOT\)"),
]

for who, what, rx in checks:
    t = A if who == "A" else B
    print(("OK   " if re.search(rx, t) else "MISS "), who, what)
