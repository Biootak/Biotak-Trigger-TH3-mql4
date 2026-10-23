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


def read_unit(path):
    """(origin, lineno, text) following #include "..." in place, like the compiler."""
    out = []
    seen = set()

    def walk(p):
        p = os.path.normpath(p)
        if p in seen:
            return
        seen.add(p)
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            return
        base = os.path.dirname(p)
        for i, ln in enumerate(lines, 1):
            m = re.match(r'\s*#include\s+"([^"]+)"', ln)
            if m:
                cand = os.path.normpath(os.path.join(base, m.group(1).replace("\\", os.sep)))
                if os.path.exists(cand):
                    walk(cand)
                continue
            out.append((p, i, ln))

    walk(os.path.normpath(path))
    return out


def define(path, name):
    """The value of `#define NAME ...`, and the file:line it lives on."""
    pat = re.compile(r"^\s*#define\s+" + re.escape(name) + r"\s+(.+?)\s*(?://.*)?$")
    for origin, ln, line in read_unit(path):
        m = pat.match(line)
        if m:
            return m.group(1).strip(), "%s:%d" % (os.path.basename(origin), ln)
    return None, None


def expr(path, name, subs=None, depth=6):
    """Resolve a #define chain to an int (or None). `subs` overrides names.

    P-UI-149 (2026-10-13) — THE ALIAS'S OWN HOME IS THE CARD UNIT. The strip's own
    chrome is written as an ALIAS of the cards' constants on purpose (P-DRAW-116):
    `DrawStrip_Head.mqh` carries `#define DSTRIP_GEAR_ROW_H  PNL_ROW_H`,
    `..._HEAD_H  PNL_HEAD_H`, `..._PAD  PNL_PAD_X`, `..._FOOT_H  PNL_FOOT_H`,
    `..._LBL_PT  PNL_PT_LBL` — and every `PNL_*` lives in `CardMetrics.mqh`, which
    reaches the strip only through `BiotakPanels_State.mqh`, i.e. NOT through
    `DrawStrip.mqh` (whose includes are the `DrawStrip_*.mqh` family alone). So the
    panel side resolved to `None` and five seats were reported as DIFF when they were
    simply never read — the two surfaces really are one number. Resolving an unknown
    identifier in the card unit is the honest fix: it is the alias's declared home.
    """
    subs = subs or {}
    if name in subs:
        return subs[name]
    val, _ = define(path, name)
    origin = path
    if val is None and path != CARD:
        val, _ = define(CARD, name)
        origin = CARD
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
        sub_val, _ = define(origin, ident)
        if sub_val is None and origin != CARD:
            sub_val, _ = define(CARD, ident)   # P-UI-149: the alias's own home
        if sub_val is not None:
            r = expr(origin, ident, env, depth - 1)
            if r is not None:
                env[ident] = r
    try:
        return int(eval(val, {"__builtins__": {}}, env))
    except Exception:
        return None


def find_uses(path, patterns, within=None):
    """(file:line, text) for every line matching any regex."""
    out = []
    for origin, ln, line in read_unit(path):
        for p in patterns:
            if re.search(p, line):
                out.append(("%s:%d" % (os.path.basename(origin), ln), line.rstrip()))
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
    ("section pt",            "PNL_PT_SEC",                 "DSTRIP_SEC_PT",          "band caption size"),
    ("section count w",       "PNL_SEC_CNT_W",              "DSTRIP_SEC_CNT_W",       "the .cnt pill"),
    # P-UI-214 (2026-10-22): these two compared the card's NAME against a bare literal,
    # so they could only ever report drift after it had happened — the same asymmetry
    # P-UI-153 fixed for the close button. Both seats now have a strip-layer name
    # (include 99 cannot read BiotakPanels_State), and the paint reads that name.
    ("switch w",              "PNL_SW_W",                   "DSTRIP_GEAR_SW_W",       ".sw pill width"),
    ("switch h",              "PNL_SW_H",                   "DSTRIP_GEAR_SW_H",       ".sw pill height"),
    ("chip vis",              "PNL_CHIP_VIS",               "DSTRIP_CARD_CHIP_VIS",   "row glyph"),
    ("chip top in row",       "PNL_CHIP_Y",                 "DSTRIP_CARD_CHIP_Y",     "glyph seat"),
    ("label top in row",      "PNL_LBL_Y",                  "DSTRIP_CARD_LBL_Y",      "label seat"),
    # P-UI-153 (2026-10-13): the panel side was the bare literal "26", so this seat
    # compared a NUMBER against a NAME and could only ever report drift after it had
    # happened. It now reads `DSTRIP_GEAR_XW` — the strip's one owner for the gear
    # panel's close seat, declared in DrawStrip_Head.mqh and read by the paint, the
    # hit test and the carry — so the comparison is name-to-name and a rename that
    # breaks the alias fails here instead of on a chart.
    ("close button",          "PNL_XBTN_VIS",               "DSTRIP_GEAR_XW",         "header .x"),
    # P-UI-216 (2026-10-22) — THE MARK ROWS SAID "30 / 13 / 7" AND THE STRIP PAINTS 44.
    # Three rows compared the cards' DISC (30 at +13, 7 of glow) against their own
    # literals, while the gear head paints the CANVAS — 44x44 at `+16-7, +13-7` — so the
    # gate reported "ok" on a seat the panel does not use at that size, and the six
    # literals that produced 44 (`9,6,44,23,20,56`) were the ones P-DRAW-80 had to fix
    # by hand. One row now compares what is actually painted, name to name.
    ("mark canvas",           "PNL_MARK_VIS + 2*PNL_MARK_PAD", "DSTRIP_MARK_CANVAS",  "the .mark art's box"),
    ("glyph canvas",          "PNL_GLYPH_CANVAS",           "DSTRIP_MARK_GLYPH",      "mark/close glyph"),
    ("foot button w floor",   "PNL_BTN_W",                  "DSTRIP_GEAR_FOOT_BW",    "footer button"),
    # P-UI-216: "foot button pad" ("8") is RETIRED, not renamed. The strip's 8 is the air
    # inside its own text-measured width (`MathMax(FOOT_BW, 32 + textW + 8)`); the cards'
    # `PNL_BTN_PAD` is the glow margin baked around the SKIN. Same digit, two questions —
    # the parity claim was a coincidence, and a row that cannot be wrong is not a check.
    # P-UI-149 (2026-10-13) — THE DUPLICATE ROW IS GONE. A "tab row height" entry sat
    # here as `("PNL_ROW_H", "DSTRIP_GEAR_ROW_H")` — the SAME pair as "row pitch" three
    # rows up — so one comparison was counted twice and every report read "6 seat(s)
    # differ" when five seats had been asked. It was also stale in name: the horizontal
    # tab row is RETIRED (P-DRAW-117, DrawStrip_Head.mqh:324 — the groups are 42px rows
    # on the cards' own grid now, and `DSTRIP_TAB_H` no longer exists), so there is no
    # separate tab-row height left to compare. Re-adding a seat means adding a pair that
    # is genuinely not in this table.
]


def _resolve(path, e):
    """A seat expression -> int: a bare #define, or arithmetic over #defines.

    P-UI-216 (2026-10-22): the table could only hold a single name or a pure number,
    so a seat that is a SUM of two card constants ("the mark's canvas = disc + 2*glow")
    had to be written as its literal — the very thing these rows exist to stop. Every
    identifier is resolved through `expr()`, which already walks the alias chain.
    """
    if re.match(r"^[A-Z_][A-Z0-9_]*$", e):
        return expr(path, e)
    env = {}
    for ident in set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", e)):
        v = expr(path, ident)
        if v is None:
            return None
        env[ident] = v
    try:
        return int(eval(e, {"__builtins__": {}}, env))
    except Exception:
        return None


def main():
    verbose = "--verbose" in sys.argv
    print("UI PARITY AUDIT — panel chrome vs card chrome (offline)")
    print("=" * 78)

    bad = []
    for label, card_e, panel_e, note in SEATS:
        c = _resolve(CARD, card_e)
        p = _resolve(STRIP, panel_e)
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
        print(f"  [see ] panel label x (with chip)   card={row_lbl_x}  -> see {ln}")
        print(f"          {txt.strip()}")
    # P-UI-214 (2026-10-22): that seat is RESOLVABLE now — the panel reads ONE name
    # (`DSTRIP_CARD_LBL_DX` = chip + 8) instead of `22 + 8`, so the arithmetic is
    # compared here rather than left as a "still needs a chart" line.
    if p:
        panel_lbl_x = expr(STRIP, "DSTRIP_GEAR_PAD") + expr(STRIP, "DSTRIP_CARD_LBL_DX")
        mark = "ok  " if panel_lbl_x == row_lbl_x else "DIFF"
        print(f"  [{mark}] panel label x (resolved)   card={row_lbl_x}  panel={panel_lbl_x}   (PnlLabelX)")
        if panel_lbl_x != row_lbl_x:
            bad.append(("panel label x (with chip)", row_lbl_x, panel_lbl_x, "PnlLabelX"))

    # P-UI-214: the switch's RIGHT EDGE is the content box's right edge on both
    # surfaces — `PNL_SW_X = PNL_WEL - 2*PAD - PNL_SW_W` on the card and
    # `cw - DSTRIP_GEAR_SW_W` (cw = DSTRIP_GEAR_W - 2*PAD) on the panel. Two numbers
    # per side, both resolvable: the content width and the pill's own width.
    cw_card = expr(CARD, "PNL_WEL") - 2 * PAD
    cw_panel = expr(STRIP, "DSTRIP_GEAR_W") - 2 * expr(STRIP, "DSTRIP_GEAR_PAD")
    sw_w = expr(CARD, "PNL_SW_W")
    sw_w_panel = expr(STRIP, "DSTRIP_GEAR_SW_W")
    mark = "ok  " if (cw_card == cw_panel and sw_w == sw_w_panel) else "DIFF"
    print(f"  [{mark}] panel switch right edge   content={cw_card}  pill={sw_w}  (PNL_SW_X .. +PNL_SW_W)")
    if cw_card != cw_panel or sw_w != sw_w_panel:
        bad.append(("panel switch right edge", f"{cw_card}/{sw_w}", f"{cw_panel}/{sw_w_panel}", "PNL_SW_X"))

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
    print("All seats agree — the constants AND the two derived ones (P-UI-214 closed the last ??)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
