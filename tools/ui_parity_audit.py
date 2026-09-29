#!/usr/bin/env python3
"""
UI PARITY AUDIT — offline. Compares the settings panel's own chrome against the
reference cards' chrome, seat by seat, and names every divergence with file:line.

WHY OFFLINE. A chart only exists inside a running terminal, so "does the panel
look right" was being answered by a screenshot the user had to take and describe.
Every number the two surfaces use, though, is a LITERAL in the source — so the
part of the question that can be settled without a terminal is settled here, once,
for the whole file, on every run.

It does not replace looking. It replaces ARGUING: a divergence is a number on both
sides, not an opinion about which one is right.

USAGE:  python tools/ui_parity_audit.py
        python tools/ui_parity_audit.py --verbose
"""

import re
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PANELS = os.path.join(ROOT, "Biotak", "BiotakPanels.mqh")
STRIP = os.path.join(ROOT, "Biotak", "DrawStrip.mqh")


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.readlines()


def define(path, name):
    """The value of `#define NAME ...`, and the line it lives on."""
    pat = re.compile(r"^\s*#define\s+" + re.escape(name) + r"\s+(.+?)\s*(?://.*)?$")
    for i, line in enumerate(read(path), 1):
        m = pat.match(line)
        if m:
            return m.group(1).strip(), i
    return None, None


def expr(path, name, subs=None, depth=6):
    """Resolve a #define chain to an int (or None). `subs` overrides names."""
    subs = subs or {}
    if name in subs:
        return subs[name]
    val, _ = define(path, name)
    if val is None:
        return None
    val = val.split("//")[0].strip()
    try:
        return int(eval(val, {"__builtins__": {}}, dict(subs)))
    except Exception:
        pass
    if depth <= 0:
        return None
    # expand identifiers
    env = dict(subs)
    for ident in set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", val)):
        if ident.isdigit():
            continue
        sub_val, _ = define(path, ident)
        if sub_val is not None:
            r = expr(path, ident, env, depth - 1)
            if r is not None:
                env[ident] = r
    try:
        return int(eval(val, {"__builtins__": {}}, env))
    except Exception:
        return None


def find_uses(path, patterns, within=None):
    """(lineno, text) for every line matching any regex, optionally inside a span."""
    out = []
    lines = read(path)
    lo, hi = within or (1, len(lines))
    for i in range(lo - 1, min(hi, len(lines))):
        for p in patterns:
            if re.search(p, lines[i]):
                out.append((i + 1, lines[i].rstrip()))
                break
    return out


def span_of(path, start_pat, end_pat):
    lines = read(path)
    lo = hi = None
    for i, line in enumerate(lines, 1):
        if lo is None and re.search(start_pat, line):
            lo = i
        elif lo is not None and re.search(end_pat, line):
            hi = i
            break
    return (lo, hi) if lo and hi else (1, len(lines))


# ── the reference surface, straight from the card's own constants ──────────────
CARD = "Biotak/BiotakPanels.mqh"

# Each row: seat, the card's own expression (in PNL_/PNL_ terms), the panel's own
# expression (in DSTRIP_ terms), and why a difference matters.
SEATS = [
    # (label,                 card expr,                    panel expr,               note)
    ("row pitch",             "PNL_ROW_H",                  "DSTRIP_GEAR_ROW_H",      "the whole grid"),
    ("header height",         "PNL_HEAD_H",                 "DSTRIP_GEAR_HEAD_H",     "head band"),
    ("side pad",              "PNL_PAD_X",                  "DSTRIP_GEAR_PAD",        "every column"),
    ("foot height",           "PNL_FOOT_H",                 "DSTRIP_GEAR_FOOT_H",     "footer band"),
    ("label row gap",         "PNL_ROW_GAP",                "DSTRIP_ROW_GAP",         "label -> control"),
    ("row label pt",          "PNL_PT_LBL",                 "DSTRIP_GEAR_LBL_PT",     "label size"),
    ("section pt",            "PNL_PT_SEC",                 "7",                      "band caption size"),
    ("section count w",       "PNL_SEC_CNT_W",              "DSTRIP_SEC_CNT_W",       "the .cnt pill"),
    ("switch w",              "PNL_SW_W",                   "40",                     ".sw pill width"),
    ("switch h",              "PNL_SW_H",                   "22",                     ".sw pill height"),
    ("chip vis",              "PNL_CHIP_VIS",               "22",                     "row glyph"),
    ("chip top in row",       "PNL_CHIP_Y",                 "DSTRIP_CARD_CHIP_Y",     "glyph seat"),
    ("label top in row",      "PNL_LBL_Y",                  "DSTRIP_CARD_LBL_Y",      "label seat"),
    ("close button",          "PNL_XBTN_VIS",               "26",                     "header .x"),
    ("mark visible",          "PNL_MARK_VIS",               "30",                     ".mark disc"),
    ("mark y",                "PNL_MARK_Y",                 "13",                     ".mark seat"),
    ("mark pad",              "PNL_MARK_PAD",               "7",                      ".mark glow"),
    ("glyph canvas",          "PNL_GLYPH_CANVAS",           "15",                     "mark/close glyph"),
    ("foot button w floor",   "PNL_BTN_W",                  "DSTRIP_GEAR_FOOT_BW",    "footer button"),
    ("foot button pad",       "PNL_BTN_PAD",                "8",                      "footer skin pad"),
    ("tab row height",        "PNL_ROW_H",                  "DSTRIP_GEAR_ROW_H",      "the tab row itself"),
]


def main():
    verbose = "--verbose" in sys.argv
    print("UI PARITY AUDIT — panel chrome vs card chrome (offline)")
    print("=" * 78)

    bad = []
    for label, card_e, panel_e, note in SEATS:
        c = expr(CARD, card_e) if re.match(r"^[A-Z_][A-Z0-9_]*$", card_e) else eval(card_e, {"__builtins__": {}}, {})
        p = expr(STRIP, panel_e) if re.match(r"^[A-Z_][A-Z0-9_]*$", panel_e) else eval(panel_e, {"__builtins__": {}}, {})
        mark = "ok  " if c == p else "DIFF"
        if c != p:
            bad.append((label, c, p, note))
        print(f"  [{mark}] {label:<20} card={c!s:>6}  panel={p!s:>6}   ({note})")

    # ── the seats that are arithmetic, not a constant ────────────────────────────
    print("-" * 78)
    print("  derived seats")
    PAD = expr(CARD, "PNL_PAD_X")
    CHIP = expr(CARD, "PNL_CHIP_VIS")
    row_lbl_x = PAD + CHIP + 8                       # PnlLabelX, with a chip
    row_lbl_x_bare = PAD                             # PnlLabelX, no chip
    p = find_uses(STRIP, [r"DSTRIP_GEAR_PAD\s*\+\s*\(\s*res\s*=="])
    for ln, txt in p:
        print(f"  [??  ] panel label x (with chip)   card={row_lbl_x}  -> see {os.path.basename(STRIP)}:{ln}")
        print(f"          {txt.strip()}")

    sw_x_card = expr(CARD, "PNL_WEL") - 2 * PAD     # PNL_SW_X = PNL_WEL-2*PNL_PAD_X-... via defines
    sw_w = expr(CARD, "PNL_SW_W")
    print(f"  [??  ] panel switch right edge   card={sw_x_card}+{sw_w}  (PNL_SW_X .. +PNL_SW_W)")

    # ── the object-name namespaces, which are behaviour, not text ───────────────
    print("-" * 78)
    print("  object-name families")
    for label, pat in [("card", r'"BiotakMenuV2_\d+_Pnl'), ("strip", r'"PnlDrawS_')]:
        n = sum(1 for _ in find_uses(STRIP if label == "strip" else PANELS, [pat]))
        print(f"  {label:<8} {n} distinct prefix form(s)")

    print("=" * 78)
    if bad:
        print(f"{len(bad)} seat(s) differ. Each is a number on both sides — fix, do not eyeball:")
        for label, c, p, note in bad:
            print(f"   - {label}: card {c} vs panel {p}  ({note})")
        return 1
    print("All constant seats agree. The derived seats marked ?? still need a chart.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
