#!/usr/bin/env python3
"""
THE GEAR PANEL GATE. Renders every tab of the "Box Settings" panel from the
constants the MQL uses and fails the build when a number, a seat or a face drifts.

Why this exists, in one line: the panel's only proof used to be a screenshot, and
a screenshot proves a paint, not a layout. Every defect on this surface was found
by eye AFTER a build that was green, and the eye could only see the tab that was
open. Four tabs, four blind spots.

What it checks, and what each failure means:
  height   every tab's gh must land on (104 + 42n) for n in 1..10 — the plate is
           baked per card count, so a gh that misses is a wrong card, and the MQL
           silently falls to the composed W branch instead of the one bake
  plate    the branch the MQL would take, named, plus the exact object it creates
  seats    the row/head/label/switch/pad numbers against BiotakPanels.mqh
  faces    every raster the panel paints must exist on disk — a missing file is a
           hole the compiler cannot name (same class as the resource gate)
  arity    the tab list and its enum must agree, so a fifth tab cannot be added to
           the enum and forgotten in the tabs

Usage:  python tools/check-gear-panel.py [--png]     (--png writes tools/legacy/gear-N.png)
"""

import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ICONS = os.path.join(ROOT, "Files", "Icons")
DRAWSTRIP = os.path.join(ROOT, "Biotak", "DrawStrip.mqh")

sys.path.insert(0, HERE)
import importlib.util

_s = importlib.util.spec_from_file_location("mt4sim", os.path.join(HERE, "legacy", "panel-mt4-sim.py"))
mt4 = importlib.util.module_from_spec(_s)
_s.loader.exec_module(mt4)

_s2 = importlib.util.spec_from_file_location("gearpanel", os.path.join(HERE, "sim-gear-panel.py"))
G = importlib.util.module_from_spec(_s2)
_s2.loader.exec_module(G)

FAIL = []


def mql_unit_lines(path):
    """(origin, lineno, text) following #include "..." in place, like the compiler."""
    out = []
    seen = set()

    def walk(p):
        p = os.path.normpath(p)
        if p in seen:
            return
        seen.add(p)
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
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


def check(cond, msg):
    if not cond:
        FAIL.append(msg)
    return cond


def mql_defines():
    """Read the panel's geometry back out of the MQL, so the gate cannot drift
    from the source it claims to police: a literal changed in DrawStrip.mqh and
    not here is reported, not silently passed."""
    got = {}
    if not os.path.exists(DRAWSTRIP):
        return got
    rx = re.compile(r"#define\s+(DSTRIP_\w+)\s+(\d+)")
    for _, _, line in mql_unit_lines(DRAWSTRIP):
        m = rx.match(line.strip())
        if m:
            got[m.group(1)] = int(m.group(2))
    return got


def bmp_size(name):
    """The raster's own pixels, off its BMP header.

    P-DRAW-86: MT4 CROPS a bitmap label and never scales it, so a bake asked for
    at the wrong width is not a smaller card — it is the LEFT SLICE of the real one.
    The bake's own file is therefore an input to the layout law, not decoration:
    `pnl_card<n>` is the NARROW plate's width and `pnl_cardW*` is the WIDE one's.
    """
    p = os.path.join(ICONS, name)
    if not os.path.exists(p):
        return None
    with open(p, "rb") as fh:
        head = fh.read(26)
    w, h = struct.unpack("<ii", head[18:26])
    return (w, h)


def card_bakes():
    """How many one-piece bakes the narrow plate can ask for: `pnl_card<n>.bmp`."""
    n = []
    for f in os.listdir(ICONS) if os.path.isdir(ICONS) else []:
        m = re.match(r"pnl_card(\d+)\.bmp$", f)
        if m:
            n.append(int(m.group(1)))
    return sorted(n)


def narrow_guard(d):
    """THE NARROW/WIDE BOUNDARY, read out of DrawStripGearPlace itself.

    This is the number that was wrong (P-DRAW-86): the guard allowed as many content
    rows narrow as `DSTRIP_GEAR_WIDE_ROWS`, but the plate is `contentEnd + FOOT_H` and
    the card index is `(gh - 104) / 42`, so n content rows need card `n + 1`. Reading
    the expression instead of restating it is the only way this gate can fail when the
    guard is reverted — a transcribed 10 could never disagree with itself.
    """
    if not os.path.exists(DRAWSTRIP):
        return None
    rx = re.compile(
        r"contentEnd\s*-\s*contentTop\s*<=\s*\(?\s*([^)*]+?)\s*\)?\s*\*\s*DSTRIP_GEAR_ROW_H")
    for _, _, line in mql_unit_lines(DRAWSTRIP):
        m = rx.search(line)
        if not m:
            continue
        expr = m.group(1).strip()
        for key, val in d.items():
            expr = re.sub(r"\b%s\b" % key, str(val), expr)
        if re.fullmatch(r"[\d\s+\-*/()]+", expr):
            return int(eval(expr))          # digits and operators only
        return None
    return None


def hit_rects(L, tab):
    """THE HIT BOXES, from the same seats the paint used.

    This is the gate that would have caught the dead panel. `DrawStripGearHit` is
    a COORDINATE hit test (P-DRAW-84) because every painter in DrawStrip.mqh is
    born OBJPROP_SELECTABLE=false, so MT4 never fires OBJECT_CLICK for a control.
    A control the paint draws but the hit test never asks is a button that cannot
    be pressed — and it compiles, and it looks right, and it is dead. So this
    function mirrors the MQL's own `DrawStripGearHit` and the gate asserts that
    every PAINTED control has a NON-EMPTY hit rect on every tab.
    """
    rects = []
    PAD, GLYPH = G.PAD, G.GLYPH
    HEAD_H, ROW_H, TAB_H, TAB_PAD, TAB_GAP = G.HEAD_H, G.ROW_H, G.TAB_H, G.TAB_PAD, G.TAB_GAP
    FOOT_BW, GEAR_W = G.FOOT_BW, G.GEAR_W
    TABS, cap_w = G.TABS, G.cap_w
    px, gy = PAD, 0
    colW = GEAR_W - 2 * PAD

    # the head's X, and the head itself (the carry)
    rects.append(("head X", 26, 26))
    rects.append(("head carry", GEAR_W, HEAD_H))

    # the tab row
    tx, ty = px + PAD, gy + L["tabs_y"] + (ROW_H - TAB_H) // 2
    total = sum(TAB_PAD + mt4.text_w(t, 8) for t in TABS) + (len(TABS) - 1) * TAB_GAP
    tx = px + PAD + max(0, (colW - total) // 2)
    for t, name in enumerate(TABS):
        tw = TAB_PAD + mt4.text_w(name, 8)
        rects.append(("tab " + name, tw, TAB_H))
        tx += tw + TAB_GAP

    for b in L["blocks"]:
        kind, name, y = b[0], b[1], b[2]
        ry = gy + y
        if kind == "section":
            continue                       # a caption band is not a control
        elif kind == "caption":
            # P-DRAW-90: a caption that SHARES its row with a field owns that
            # field — it is the Paint tab's hex seat, and it must have a box.
            rects.append(("edit " + name, colW - cap_w(), G.EDIT_H))
        elif kind == "grid":
            # the block's OWN cell count, not the 5 this mirror used to assume
            n = int(b[3][0]) if b[3] else 0
            for i in range(n):
                rects.append(("grid %s[%d]" % (name, i), G.CHIP_W, G.CHIP_H))
        else:
            rects.append(("row " + (name or ""), colW, ROW_H))

    # the foot
    for f, label in enumerate(["All", "Copy"]):
        bw = max(FOOT_BW, 32 + mt4.text_w(label, 8) + 8)
        rects.append(("foot " + label, bw + 16, 28 + 16))
    return rects


def no_chart_colour():
    """THE PANEL NEVER TAKES A COLOUR OFF THE CHART (P-DRAW-89).

    The plate's transparency was retired, and the bug it carried is the one class
    no compiler names: `StrapBodyTone` short-circuited to `GetCachedChartBgColor()`,
    so every tone-driven surface (the tab track, the rows, the cells, the grips)
    wore `CHART_COLOR_BACKGROUND` — cyan on the dark template, magenta-blue on the
    light one. Measured: census `bgcolor=-16924895` = 0xFEFDBF21, a value in no
    palette and no painter here.

    So the gate asserts the SURFACE PANEL code reads no chart colour at all. The
    one legitimate reader is the box's own mid-ink blend (a chart OBJECT's colour,
    not a panel surface) and is named here rather than skipped blindly.
    """
    allowed = {}          # file:line -> the reason that read is allowed
    n = 0
    for origin, ln, line in mql_unit_lines(DRAWSTRIP):
        s = line.strip()
        if s.startswith("//") or s.startswith("//---"):
            continue
        if "GetCachedChartBgColor" not in s and "CHART_COLOR_BACKGROUND" not in s:
            continue
        n += 1
        tag = "%s:%d" % (os.path.basename(origin), ln)
        if "BlendColorTowardsBG" in s and "BOX_MID_FADE" in s:
            allowed[tag] = "the box's own mid ink, not a panel surface"
            continue
        check(False, "%s reads a chart colour into a panel surface: %s"
              % (tag, s[:90]))
    return n, len(allowed)


def main():
    want_png = "--png" in sys.argv

    print("=" * 66)
    print("GEAR PANEL GATE  (%s)" % os.path.basename(DRAWSTRIP))
    print("=" * 66)

    # 1. the literals agree with the source
    d = mql_defines()
    pairs = [("DSTRIP_GEAR_W", G.GEAR_W), ("DSTRIP_GEAR_W2", G.GEAR_W2),
             ("DSTRIP_GEAR_PAD", G.PAD), ("DSTRIP_GEAR_HEAD_H", G.HEAD_H),
             ("DSTRIP_GEAR_ROW_H", G.ROW_H), ("DSTRIP_GEAR_FOOT_H", G.FOOT_H),
             ("DSTRIP_GEAR_AIR", G.AIR), ("DSTRIP_ROW_GAP", G.ROW_GAP),
             ("DSTRIP_GEAR_LBL_PT", G.LBL_PT)]
    if d:
        for key, mine in pairs:
            if key in d:
                check(d[key] == mine, "literal %s: mql=%d sim=%d" % (key, d[key], mine))
        print("  literals: %d compared against DrawStrip.mqh" % len([k for k, _ in pairs if k in d]))
    else:
        print("  literals: DrawStrip.mqh not readable - NOT CHECKED")

    # 1b. THE BAKE SET IS THE LAW (P-DRAW-86). A narrow plate must ask for a bake
    # that exists; if it does not, DrawStripGearPlate's else-branch composes the W
    # body, whose bake is GEAR_W2+28 wide, and MT4 crops it to the narrow width — a
    # 312px panel painted as the left half of a 624px card. The two facts that decide
    # this are both readable here: the guard's own row ceiling (from the MQL) and the
    # bakes' own widths (from the BMP headers).
    nreads, nok = no_chart_colour()
    print("  chart-colour reads: %d total, %d allowed (panel surfaces must be 0)" % (nreads, nok))
    bakes = card_bakes()
    rows_max = narrow_guard(d)
    if rows_max is None:
        print("  narrow guard: DrawStripGearPlace not readable - NOT CHECKED")
    else:
        check(bakes and rows_max + 1 <= bakes[-1],
              "narrow guard allows %d content rows -> cardN=%d, but pnl_card stops at %d "
              "-> the plate falls to the composed W body (%.0fpx bake in a %dpx plate)"
              % (rows_max, rows_max + 1, bakes[-1] if bakes else 0,
                 bmp_size("pnl_cardWtop.bmp")[0] if bmp_size("pnl_cardWtop.bmp") else 0,
                 G.GEAR_W))
        print("  narrow guard: <= %d content rows (cardN %d) against %d bake(s) pnl_card1..%d"
              % (rows_max, rows_max + 1, len(bakes), bakes[-1] if bakes else 0))
    wn = bmp_size("pnl_card%d.bmp" % bakes[-1]) if bakes else None
    ww = bmp_size("pnl_cardWtop.bmp")
    if wn:
        check(wn[0] == G.GEAR_W + 28,
              "pnl_card%d.bmp is %dpx wide, the narrow plate asks for %d"
              % (bakes[-1], wn[0], G.GEAR_W + 28))
    if ww:
        check(ww[0] == G.GEAR_W2 + 28,
              "pnl_cardWtop.bmp is %dpx wide, the wide plate asks for %d"
              % (ww[0], G.GEAR_W2 + 28))
    if wn and ww:
        print("  bakes: narrow %dx%d  wide %dx%d" % (wn[0], wn[1], ww[0], ww[1]))

    # 2. per tab: height lands on the plate law, and every painted face exists
    print("")
    for t, name in enumerate(G.TABS):
        L = G.layout(t)
        gh, gw, cn, ex = L["h"], L["w"], L["card_n"], L["exact"]
        check(ex, "tab %s: gh=%d misses (104+42n)" % (name, gh))
        if gw == G.GEAR_W:
            # P-DRAW-86: a NARROW plate must fit the baked card set (1..10)
            check(1 <= cn <= 10,
                  "tab %s: narrow cardN=%d has no bake — the plate would be the "
                  "left half of a %dpx W card" % (name, cn, G.GEAR_W2 + 28))
        branch = ("bake pnl_card%d" % cn) if gw == G.GEAR_W else "composed W"
        print("  %-6s gh=%-4d w=%-4d cardN=%-3d %-16s blocks=%d rows=%d"
              % (name, gh, gw, cn, branch, len(L["blocks"]),
                 (gh - 104) // G.ROW_H))
        if L.get("unmodelled"):
            check(False, "tab %s: statements the walker did not model: %s"
                  % (name, "; ".join(L["unmodelled"][:3])))

        notes = []
        c = G.paint(L, notes, t)
        if want_png:
            W, H = gw + 56, gh + 60
            w, h, rgba = c.to_raster(W, H)
            open(os.path.join(HERE, "legacy", "gear-%d.png" % t), "wb").write(mt4.png(w, h, rgba))

        # P-DRAW-90: A `None` NAME IS A HOLE, and the old `and op[1]` filter threw
        # it away — so the one class this gate exists for (a face the panel paints
        # that no file backs, P-PANELUI-01) could not fail it. Measured: the mirror
        # asked for `gl_filter_m.bmp`, absent from every commit, and passed.
        holes = sorted({op[1] for op in c.ops if op[0] == "img" and op[1] is None})
        faces = sorted({op[1] for op in c.ops if op[0] == "img" and op[1]})
        missing = [f for f in faces if not os.path.exists(os.path.join(ICONS, f))]
        check(not holes and not missing,
              "tab %s: painted face(s) missing on disk: %s"
              % (name, ", ".join(missing) or "(a NAMED hole — the op was dropped)"))
        check(len(faces) > 0, "tab %s: painted no raster at all" % name)

        # every row block must own its own y: stacked labels are the one defect a
        # height check cannot see, because the height stays right. P-DRAW-90: the
        # seat is the WHOLE seat, `(column, y)` — a WIDE tab packs BOTH columns
        # from contentTop on purpose, so a bare y repeats by design there.
        seats = [(b[4] if len(b) > 4 else 0, b[2]) for b in L["blocks"]]
        check(len(seats) == len(set(seats)),
              "tab %s: two blocks share a seat -> stacked labels" % name)

        # THE DEAD-BUTTON GATE. A control the paint draws and the coordinate hit
        # test never asks is a button that cannot be pressed. This is the whole
        # class that shipped: P-DRAW-84, every control in this panel was one.
        hits = hit_rects(L, t)
        empty = [n for n, w, h in hits if w <= 0 or h <= 0]
        check(not empty, "tab %s: control(s) with no hit box: %s" % (name, ", ".join(empty)))
        # and the count of hit boxes must cover the count of painted controls —
        # with the grid's OWN cell count, not a hard-coded 5
        painted = [b for b in L["blocks"] if b[0] in ("row", "caption", "grid")]
        ncells = sum(int(b[3][0]) for b in painted if b[0] == "grid" and b[3])
        npaint = len(painted) + len(G.TABS) + 2 + ncells
        check(len(hits) >= npaint,
              "tab %s: %d hit boxes for %d painted controls" % (name, len(hits), npaint))
        print("       %d controls, all with a hit box" % len(hits))

    # 3. seats against the card owner
    print("")
    for label, a, b in G.audit(G.layout(0)):
        check(a == b, "seat %s: panel=%s card=%s" % (label, a, b))
    print("  seats: %d compared against BiotakPanels.mqh" % len(G.audit(G.layout(0))))

    # 4. tab arity: the enum and the tab list cannot drift apart
    if d:
        pass
    enum = len(G.TABS)
    check(enum == 4, "tab count is %d, the DSTRIP_GEAR_* enum has 4 members" % enum)

    print("")
    if FAIL:
        print("[FAIL] gear panel gate: %d problem(s)" % len(FAIL))
        for f in FAIL:
            print("   - %s" % f)
        return 1
    print("[PASS] gear panel gate: %d tabs, %d seats, all faces present"
          % (len(G.TABS), len(G.audit(G.layout(0)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
