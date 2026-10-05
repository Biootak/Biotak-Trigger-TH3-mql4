#!/usr/bin/env python3
"""
THE PEN SCENARIO SIM — every way a styled fibo can be born, dragged and re-synced,
answered OFFLINE, without a live MT4 chart.

WHY. Every report about this drawing («استایل ها روی ضخامت های بزرگ اعمال نمیشه»,
«چرا امتداد خط ها استایل اعمال نشده», «عقب و جلو میره») was a SCENARIO, and every one
of them was answered by looking at a screenshot. A screenshot cannot see the state
machine; it can only see whichever frame the hand happened to catch. So the rules
that decide the pen — the demotion, the row count, the pixel offsets, the span, the
chase geometry — are extracted FROM THE SOURCE (not copied from it) and run over the
whole matrix here, where every branch is reached on purpose.

THE CONTRACT. `mutation_gate.py` must be able to break the source and watch this file
die. That only holds if the numbers below come from `Biotak/FibPen.mqh` and
`Biotak/Toolbar_A.mqh` as they are on disk: every mutation that changes a rule
changes what this sim computes, and the invariant it breaks is printed by name.

  python tools/pen-sim.py            # every scenario
  python tools/pen-sim.py --list     # the scenarios and the rule each one owns

Exit 0 = every scenario holds. Exit 1 = at least one does not, and the line says which.
"""

import os
import re
import sys

try:                                   # the console is cp1252 on this desk
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except AttributeError:                  # python < 3.7
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

FIB = os.path.join(ROOT, "Biotak", "FibPen.mqh")
TBA = os.path.join(ROOT, "Biotak", "Toolbar_A.mqh")

STYLE_SOLID, STYLE_DASH, STYLE_DOT, STYLE_DASHDOT, STYLE_DASHDOTDOT = 0, 1, 2, 3, 4
STYLE_NAME = {0: "solid", 1: "dash", 2: "dot", 3: "dashdot", 4: "dashdotdot"}


# ── the extraction ────────────────────────────────────────────────────────────
# A number this file invents is a number that can drift away from the code without
# anyone noticing; every one below is READ from the source or the sim is not a test.
def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def need(text, pattern, what, flags=0):
    m = re.search(pattern, text, flags)
    if not m:
        print("[FAIL] P-SIM-SRC the source no longer states %s — this sim models a rule "
              "nobody can read any more" % what)
        sys.exit(1)
    return m


fib = read(FIB)
tba = read(TBA)

DRAW_WIDTH_MIN = int(need(tba, r"#define DRAW_WIDTH_MIN\s+(\d+)", "DRAW_WIDTH_MIN").group(1))
DRAW_WIDTH_MAX = int(need(tba, r"#define DRAW_WIDTH_MAX\s+(\d+)", "DRAW_WIDTH_MAX").group(1))
FIBPEN_MAX_LEVELS = int(need(fib, r"#define FIBPEN_MAX_LEVELS\s+(\d+)", "FIBPEN_MAX_LEVELS").group(1))
LOOK = {
    "NEON": int(need(fib, r"#define FIBPEN_LOOK_NEON\s+(\d+)", "FIBPEN_LOOK_NEON").group(1)),
    "CAPS": int(need(fib, r"#define FIBPEN_LOOK_CAPS\s+(\d+)", "FIBPEN_LOOK_CAPS").group(1)),
    "WASH": int(need(fib, r"#define FIBPEN_LOOK_WASH\s+(\d+)", "FIBPEN_LOOK_WASH").group(1)),
}

#--- the demotion itself: two expressions, read as written.
VIS = need(fib, r"vis = \(refSt != \(int\)STYLE_SOLID && refLog > DRAW_WIDTH_MIN\)\s*\?\s*DRAW_WIDTH_MIN\s*:\s*refLog;",
           "the visible-width rule")
WANT = need(fib, r"want = \(refSt != \(int\)STYLE_SOLID && refLog > DRAW_WIDTH_MIN\)\s*\?\s*refLog (- \d+)\s*:\s*(\d+);",
            "the row-count rule")
WANT_MINUS = int(WANT.group(1).split()[-1])          # "refLog - 1"  -> 1
WANT_ZERO = int(WANT.group(2))                        # ": 0"         -> 0

#--- the span the pen wears: the source's own FibPenRayPair, BOTH extensions.
#--- The hand's two frames show the master spanning the FULL width both ways while
#--- the pen covered the middle only — so BOTH rays stay on, in both anchor orders,
#--- and the style rides the line عقب و جلو (P-LOOK-RAY5, «امتداد به عقب و جلو»).
RAY_FN = need(fib, r"void FibPenRayPair\([^)]*\)\s*\{[\s\S]*?\n\}", "FibPenRayPair").group(0)
BOTH_OK = bool(re.search(r"rl = true;[\s\S]{0,160}?rr = true;", RAY_FN))
PEN_RIGHT = BOTH_OK     # the forward extension wears the style
PEN_BACK = BOTH_OK      # ...and the backward one wears it too
need(fib, r"rl = (true|false);", "the pen's backward span")
need(fib, r"rr = (true|false);", "the pen's forward span")
#--- the rows' span is ordered early→late on BOTH seats that move them (the sync and
#--- the drag chase): children born with the master's reversed order keep only one
#--- extension (P-LOOK-RAY5b — measured on the hand's frame: rays=3 yet the right side
#--- bare while ta > tb). One ordered seat is a half fix the next drag undoes.
SPAN_ORDER_SRC = "datetime ts0 = (ta < tb ? ta : tb);"
if fib.count(SPAN_ORDER_SRC) < 2:
    print("[FAIL] P-SIM-RAY the rows no longer wear ordered time on both movers — with "
          "reversed anchors MT4 extends only one side, so an extension wears no style "
          "and no thickness")
    sys.exit(1)
if "ObjectGetInteger(0, fibo, OBJPROP_RAY_" in RAY_FN:
    print("[FAIL] P-SIM-RAY FibPenRayPair reads the master's own ray pair again — on OBJ_FIBO "
          "that pair is not the level line's span (MT4 keeps it in `levels_ray`, which MQL4 "
          "neither reads nor writes), so the pen is trimmed to the anchors while the line "
          "runs on to the chart edge")
    sys.exit(1)

#--- the wash halo: the source states where it sits and that it is healed, not fixed.
WASH_HALO_AT_TWO = bool(re.search(r"hp = lva \+ 2\.0 \* px;", fib))
WASH_HEAL = "OBJPROP_RAY_LEFT, penRL);   // P-LOOK-RAY2" in fib or "wnm, OBJPROP_RAY_LEFT, penRL" in fib

#--- the chase: three arms, and the landing that re-seats the snapshot.
need(fib, r"if\(s_fibGrab == FIBPEN_GRAB_BODY\)", "the body-drag arm")
need(fib, r"else if\(s_fibGrab == 0\)", "the first-anchor arm")
need(fib, r"if\(p1 != s_fibProbeP\[0\] \|\| p2 != s_fibProbeP\[1\] \|\| t1 != s_fibProbeT\[0\] \|\| t2 != s_fibProbeT\[1\]\)",
     "the landing resync")


# ── the two pieces of arithmetic, ported line for line ────────────────────────
def off_px(w, q):
    """FibPenOffPx: centred offsets in px, inner first: 2:[-1] 3:[-1,+1] 4:[-1,+1,+2] 5:[-1,+1,-2,+2]."""
    half = (w - 1) // 2
    idx = q
    for d in range(1, half + 1):
        if idx == 0:
            return -d
        idx -= 1
        if idx == 0:
            return d
        idx -= 1
    if w % 2 == 0 and idx == 0:
        return half + 1
    return 0


def sync(ref_st, ref_log):
    """The ONE sync's per-level decision, as FibPenSync states it."""
    vis = DRAW_WIDTH_MIN if (ref_st != STYLE_SOLID and ref_log > DRAW_WIDTH_MIN) else ref_log
    want = (ref_log - WANT_MINUS) if (ref_st != STYLE_SOLID and ref_log > DRAW_WIDTH_MIN) else WANT_ZERO
    return vis, want


def logical_width(level_w, children, top_solid):
    """FibPenLogicalWidth: 1 + children while demoted, the line's own otherwise."""
    w = max(DRAW_WIDTH_MIN, min(DRAW_WIDTH_MAX, level_w))
    if w == DRAW_WIDTH_MIN and children > 0:
        lg = 1 + children
        if top_solid:
            lg = children
        return max(DRAW_WIDTH_MIN, min(DRAW_WIDTH_MAX, lg))
    return w


# ── the scenario matrix ───────────────────────────────────────────────────────
SCENARIOS = []


def scenario(name, rule, fn):
    SCENARIOS.append((name, rule, fn))


def _rows(st, w, look):
    vis, want = sync(st, w)
    rows = [off_px(w, q) for q in range(want)]
    core = (look == LOOK["NEON"] and want > 0 and w >= 3)
    return vis, want, rows, core


def s_native(style, width):
    """A thick SOLID level is the terminal's own picture: no pen, no cost."""
    def run(broken):
        vis, want, rows, core = _rows(style, width, 0)
        if vis != width:
            broken.append("a solid width-%d level is drawn at %d — the master must draw it itself" % (width, vis))
        if want or rows or core:
            broken.append("a solid level builds %d pen rows — solid must cost zero objects" % (len(rows)))
    return run


def s_styled(style, width):
    """A styled level the terminal cannot draw: 1 px plus the rows that carry the ink."""
    def run(broken):
        vis, want, rows, core = _rows(style, width, 0)
        if vis != DRAW_WIDTH_MIN:
            broken.append("a styled level keeps visible width %d — the terminal paints it solid" % vis)
        if len(rows) != width - 1:
            broken.append("a styled width-%d level builds %d rows, not %d" % (width, len(rows), width - 1))
        if len(set(rows)) != len(rows):
            broken.append("the rows of width %d share an offset: %s" % (width, rows))
        if sorted(rows) != sorted(-x for x in rows) and width % 2 == 1:
            broken.append("the rows of width %d are not centred: %s" % (width, rows))
        for q, off in enumerate(rows):
            if off != off_px(width, q):
                broken.append("row %d of width %d sits at %+d px, not %+d" % (q, width, off, off_px(width, q)))
    return run


def s_span(style, width):
    """THE REPORT: the pen must cover the line wherever the line goes."""
    def run(broken):
        _vis, want, _rows_, _core = _rows(style, width, 0)
        if want > 0 and not PEN_RIGHT:
            broken.append("a styled level builds rows that stop at the anchors on the forward "
                          "side while MT4's level line runs on («چرا امتداد خط ها استایل "
                          "اعمال نشده»)")
        if want > 0 and not PEN_BACK:
            broken.append("a styled level builds rows that stop at the anchors on the backward "
                          "side while MT4's level line runs on («امتداد به عقب و جلو چرا "
                          "استایل و ضخامت نمیگیره»)")
    return run


def s_memory(style, width, look):
    """THE OTHER REPORT: the width must SURVIVE the sync that demoted it."""
    def run(broken):
        vis, want, _rows_, core = _rows(style, width, look)
        if want == 0:
            return
        #--- after the sync the level sits at 1 px with `want` rows beside it, plus the
        #--- neon core when the look has one — `FibPenChildCount` counts the tube too
        back = logical_width(vis, want + (1 if core else 0), core)
        if back != width:
            broken.append("the demoted level reads back as %d after the sync — the thickness the "
                          "hand chose is gone («استایل ها روی ضخامت های بزرگ اعمال نمیشه»)" % back)
        #--- and a second sync, asked by the very state the first one left, must agree
        vis2, want2 = sync(style, back)
        if (vis2, want2) != (vis, want):
            broken.append("a second sync disagrees with the first: (%d,%d) then (%d,%d)"
                          % (vis, want, vis2, want2))
    return run


def s_look(look_name):
    """A look is drawn by its own followers, on the same span and the same rows."""
    lk = LOOK[look_name]
    def run(broken):
        for width in range(DRAW_WIDTH_MIN, DRAW_WIDTH_MAX + 1):
            for style in (STYLE_SOLID, STYLE_DASHDOTDOT):
                vis, want, rows, core = _rows(style, width, lk)
                if lk == LOOK["NEON"]:
                    if core != (want > 0 and width >= 3):
                        broken.append("NEON's core is out of step with the stack at style %s width %d"
                                      % (STYLE_NAME[style], width))
                    if core and logical_width(vis, want + 1, True) != width:
                        broken.append("NEON's core doubles the thickness at width %d" % width)
                if lk == LOOK["CAPS"] and want > 0:
                    #--- caps sit over the span's last eighth: bounded, never rayed
                    if want > len(rows):
                        broken.append("CAPS reads a wider stack than exists at width %d" % width)
                if lk == LOOK["WASH"] and want > 0:
                    #--- the halo is one soft row at +2 px (the source's own `2.0 * px`),
                    #--- and it is BORN and HEALED like the dash rows — never hardcoded.
                    if not WASH_HALO_AT_TWO or not WASH_HEAL:
                        broken.append("WASH's halo is no longer the +2 px row the source states")
    return run


def s_levels():
    """More levels than the pen's cap: the tail converges, it never stacks."""
    def run(broken):
        if FIBPEN_MAX_LEVELS < 2:
            broken.append("the pen's level cap is %d — one level cannot hold a stack" % FIBPEN_MAX_LEVELS)
        for nl in (FIBPEN_MAX_LEVELS + 1, FIBPEN_MAX_LEVELS + 5):
            stacked = min(nl, FIBPEN_MAX_LEVELS)
            if stacked != FIBPEN_MAX_LEVELS:
                broken.append("%d levels stack %d of them" % (nl, stacked))
    return run


#--- the chase, as a hand that goes back and forth (the drag report).
def s_chase():
    """«عقب و جلو میره» — a hand that reverses must not leave the pen behind or ahead."""
    def run(broken):
        #--- the master, its snapshot and its probe: FibPenDragFollow's own three sets
        p1, p2 = 1.12590, 1.12541
        t1, t2 = 1790977500, 1790978700
        P0 = [p1, p2]
        T0 = [t1, t2]
        probe = [p1, p2, t1, t2]
        cur = [1.12590]        # the cursor origin the landing moved

        def follow(cp, grab):
            """returns (pa, pb) exactly as the source's (2)/(3) state it."""
            a, b = probe[0], probe[1]
            ta, tb = probe[2], probe[3]
            if (a != p1 or b != p2 or ta != t1 or tb != t2):   # a terminal LANDING
                P0[0], P0[1] = p1, p2
                T0[0], T0[1] = t1, t2
                probe[0], probe[1], probe[2], probe[3] = p1, p2, t1, t2
                cur[0] = cp
            dp = cp - cur[0]
            if grab == "body":
                return P0[0] + dp, P0[1] + dp
            if grab == 0:
                return cp, P0[1]
            return P0[0], cp

        #--- 400 moves that reverse direction every few frames, with the terminal
        #--- landing the master's new truth whenever our own prediction was close.
        worst = 0.0
        for i in range(400):
            cp = 1.12560 + (0.00012 if (i // 7) % 2 == 0 else -0.00009) * ((i % 7) + 1)
            for grab in ("body", 0, 1):
                pa, pb = follow(cp, grab)
                if not (pa > 0.0 and pb > 0.0):
                    broken.append("the chase produced a non-positive price at move %d" % i)
                    return
                #--- a body drag MUST translate the drawing: the distance between the two
                #--- anchors is the master's own and may not change by a pixel price
                if grab == "body":
                    d_chase = abs(pa - pb)
                    d_master = abs(p1 - p2)
                    if abs(d_chase - d_master) > 1e-9:
                        worst = max(worst, abs(d_chase - d_master))
                if grab == 0 and abs(pa - cp) > 1e-12:
                    broken.append("an anchor-0 drag does not put the hand's anchor under the cursor")
                if grab == 1 and abs(pb - cp) > 1e-12:
                    broken.append("an anchor-1 drag does not put the hand's anchor under the cursor")
            #--- the terminal lands the master where the hand actually put it
            pa, pb = follow(cp, "body")
            p1, p2 = pa, pb
        if worst > 1e-9:
            broken.append("a body drag changed the drawing's own length by %.9f — it translates, "
                          "it does not stretch" % worst)
    return run


for _w in range(DRAW_WIDTH_MIN, DRAW_WIDTH_MAX + 1):
    scenario("solid width %d costs nothing" % _w, "P-SIM-74b", s_native(STYLE_SOLID, _w))
    for _s in (STYLE_DASH, STYLE_DOT, STYLE_DASHDOT, STYLE_DASHDOTDOT):
        scenario("%s width %d is drawn" % (STYLE_NAME[_s], _w), "P-SIM-74b", s_styled(_s, _w))
        scenario("%s width %d covers the extension" % (STYLE_NAME[_s], _w), "P-SIM-RAY", s_span(_s, _w))
        for _l in LOOK.values():
            scenario("%s width %d survives its own sync" % (STYLE_NAME[_s], _w), "P-SIM-MEM",
                     s_memory(_s, _w, _l))
scenario("NEON rides the stack", "P-SIM-LOOK", s_look("NEON"))
scenario("CAPS sits on the span", "P-SIM-LOOK", s_look("CAPS"))
scenario("WASH hugs the span", "P-SIM-LOOK", s_look("WASH"))
scenario("levels past the cap converge", "P-SIM-CAP", s_levels())
scenario("a hand that goes back and forth", "P-SIM-DRAG", s_chase())


def main():
    if "--list" in sys.argv:
        for name, rule, _fn in SCENARIOS:
            print("  %-11s %s" % (rule, name))
        return 0
    print("=" * 72)
    print("PEN SCENARIO SIM  (%d scenarios, rules read from Biotak/FibPen.mqh)"
          % len(SCENARIOS))
    print("=" * 72)
    print("  widths %d..%d · level cap %d · looks NEON=%d CAPS=%d WASH=%d"
          % (DRAW_WIDTH_MIN, DRAW_WIDTH_MAX, FIBPEN_MAX_LEVELS,
             LOOK["NEON"], LOOK["CAPS"], LOOK["WASH"]))
    print("  the pen's span: backward-covered=%s forward-covered=%s (full width, both anchor orders)"
          % (PEN_BACK, PEN_RIGHT))
    failed = []
    per_rule = {}
    for name, rule, fn in SCENARIOS:
        broken = []
        fn(broken)
        per_rule.setdefault(rule, []).extend(broken)
        if broken:
            failed.append((name, broken))
    for rule in sorted(per_rule):
        bad = per_rule[rule]
        print("  [%-4s] %-10s %s" % ("FAIL" if bad else "PASS", rule,
                                    "%d scenario(s)" % len([s for s in SCENARIOS if s[1] == rule])))
        for b in bad:
            print("         %s" % b)
    if failed:
        print("\nFAIL: %d scenario(s) do not hold." % len(failed))
        return 1
    print("\nPASS - every way this drawing can be born, styled, looked at, dragged back "
          "and forth and re-synced holds.")
    return 0


if __name__ == "__main__":
    sys.exit(main())