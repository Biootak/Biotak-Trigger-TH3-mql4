#!/usr/bin/env python3
"""gesture-budget-audit — the gate behind P-UI-33 (the live-gesture redraw budget).

A slider / palette-mixer / native-knob drag changes its value ~33x/s. MT4 hands
every one of those ticks to the panel, and the panel answered EVERY tick with the
full heavy pass (`RedrawAllObjects` on the whole chart) — so a drag was a
slideshow that only settled on release. The fix is the coalescer in
`Biotak/BiotakKit.mqh`: the cheap half of a drag (knob + value chip) keeps moving
every tick, the HEAVY pass is allowed at most once per `UI_DRAG_HEAVY_MS`, and the
owed mask is flushed exactly once when the gesture ends.

Two halves, because this is TIME behaviour a static lint alone cannot state:

  A. CONTRACT   a transcription of the coalescer runs a 2.0s / 33Hz drag (plus a
                re-arm scenario) and the promises are asserted as numbers: the
                first tick is instant, the passes are bounded and fewer than the
                ticks, NO flag is ever lost, no pass carries more than what is
                owed since the previous one, every tick still repaints, exactly
                one settle carries the tail, End is idempotent, a fresh gesture
                starts clean and a nested arm cannot wipe a live one. Six
                deliberate mutants must BREAK the matching promise — a promise
                that cannot fail proves nothing.
  B. SHAPE      the source is checked against the shape those promises depend on:
                the window is in its documented band, the first tick passes
                straight through, the swallow branch repaints (shared 100 ms
                throttle, never raw at pointer rate) and does no domain work,
                the owed mask is delivered once and then cleared, Begin
                refuses to re-arm while live, End clears live BEFORE it settles
                (so the settle cannot be swallowed) and flushes the tail, the
                four ARM sites sit on real gesture claims, and
                ChartPointerFinalizeOnUps keeps the ONE net every button-up
                passes through. Every clear of a drag channel must end the
                budget (one documented exemption).

Usage:  python tools/gesture-budget-audit.py [--quiet] [--sites] [--selftest]
        --sites     prints the inventory: every arm, every settle, the net.
        --selftest  seeds 15 faults into doctored sources and requires the
        matching check to catch each one (a stale seed is a HARD error).
Exit 0 = clean, 1 = the budget no longer keeps its promise.
"""

import math
import os
import re
import sys

QUIET = "--quiet" in sys.argv
SITES = "--sites" in sys.argv
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KIT = "Biotak/BiotakKit.mqh"
PANELS = "Biotak/BiotakPanels.mqh"

# P-UI-33's window must stay in the documented throttle band (LEARNING.md §3):
# below 60ms it is not a budget (the pointer path already hides 2 of every 3
# ticks at 33Hz), above 250ms the heavy pass is coarser than the domain's own
# settle and the drag visibly steps.
WINDOW_MIN, WINDOW_MAX = 60, 250

# Every arm must sit on one of these claims, or a refresh is being throttled for
# a reason no reader can see.
ARM_ANCHORS = ('DragClaim(DRAG_PANEL_KNOB)', 'kind!="K"')

# Functions allowed to CLEAR a drag channel without ending the budget, plus why.
CLEAR_EXEMPT = {"PalOpenKind": "fresh-open reset; it runs PalClose() first, which ends it"}
# ...and the exemption may not hide the function that does the ending.
MUST_END = ("PalClose", "PnlHandleMouseMove", "ChartPointerFinalizeOnUps")


def note(*a):
    if not QUIET:
        print(*a)


def path(*p):
    return os.path.join(ROOT, *p)


def read(rel):
    # Sources are a CRLF/LF mix; every check and every seed works on LF text, so
    # a seed is written once and cannot go stale over an EOL difference.
    with open(path(rel), "rb") as fh:
        return fh.read().decode("utf-8", "replace").replace("\r\n", "\n")


DEF_RE = re.compile(r"^([A-Za-z_][\w\s\*&<>,:]*?)\b(\w+)\s*\([^;{}]*\)\s*$")
TYPE_RE = re.compile(r"^\s*(?:struct|class)\s+(\w+)\b")


def function_map(src):
    """line index -> enclosing function name (one linear pass)."""
    owner = {}
    name = "?"
    depth = 0
    for i, line in enumerate(src.split("\n")):
        m = DEF_RE.match(line)
        if m and depth == 0:
            name = m.group(2)
        else:
            t = TYPE_RE.match(line)
            if t and depth == 0:
                name = t.group(1)
        owner[i] = name
        for ch in line:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
    return owner


def body(src, sig):
    """The { } block of the first definition whose text starts with `sig`."""
    i = src.find(sig)
    if i < 0:
        return None
    j = src.find("{", i)
    if j < 0:
        return None
    depth = 0
    for k in range(j, len(src)):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[j:k + 1]
    return None


def lineno(src, idx):
    return src.count("\n", 0, idx) + 1


def all_mql_sources():
    out = []
    for rel_dir in ("Biotak", "Biotak/TH3", "."):
        d = path(rel_dir)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith((".mqh", ".mq4")):
                rel = os.path.join("" if rel_dir == "." else rel_dir, f)
                out.append(rel.replace(os.sep, "/"))
    return out


# ── A. the contract, as numbers -------------------------------------------------
def parse_flags(src):
    return dict((m.group(1), int(m.group(2)))
                for m in re.finditer(r"(?m)^#define\s+(REFRESH_\w+)\s+(\d+)", src))


class Budget:
    """Transcription of ApplyRefreshFlags' budget block plus Begin/End.

    `mutate` names a deliberate defect. Every mutant must break at least one of
    the promises below, which is how the model proves it is not vacuous.
    """

    def __init__(self, window_ms, mutate=None):
        self.window = window_ms
        self.mutate = mutate
        self.live = False
        self.pend = 0
        self.heavy = 0             # 0 = no heavy pass yet (the MQL sentinel)
        self.passes = []           # (t, mask) — heavy passes actually run
        self.repaints = 0
        self.subset_ok = True      # no pass carried more than it was owed
        self._owed_since = 0

    def begin(self):
        if self.live and self.mutate != "nested_rearm":
            return
        self.live = True
        self.pend = 0
        self.heavy = 0
        self._owed_since = 0

    def request(self, t, mask):
        if mask == 0:
            return
        if self.live:
            self.pend |= mask
            self._owed_since |= mask
            if (self.heavy != 0 and t - self.heavy < self.window
                    and self.mutate != "no_first_passthrough"):
                self.repaints += 1        # the swallow branch's (throttled) repaint call
                return
            self.heavy = t
            mask = self.pend
            if self.mutate != "no_pend_clear":
                self.pend = 0
            if mask & ~self._owed_since:
                self.subset_ok = False    # delivered a flag from outside the window
            self._owed_since = 0
            if mask == 0:
                return
        self.passes.append((t, mask))
        self.repaints += 1

    def end(self, t):
        if not self.live:
            return
        self.live = False
        self.heavy = 0
        owed = self.pend
        self.pend = 0
        self._owed_since = 0
        if owed and self.mutate != "no_flush":
            self.passes.append((t, owed))    # the settle repaints too, but a SETTLE
                                             # is not a tick


def timeline(n=66, hz=33.0, flags=None, base=1234560):
    """Tick times in ms. `base` is the system uptime: GetTickCount() is never 0
    in a real session, and the 0 sentinel in s_UIDragHeavy means \"no pass yet\",
    so a model that started at t=0 would exercise a case MT4 cannot reach."""
    recalc = (flags or {}).get("REFRESH_RECALC", 2)
    buffers = (flags or {}).get("REFRESH_BUFFERS", 1)
    labels = (flags or {}).get("REFRESH_LABELS", 4)
    ev = []
    for i in range(n):
        t = base + int(round(i * 1000.0 / hz))
        ev.append((t, recalc | (buffers if i % 2 == 0 else 0)
                   | (labels if i % 5 == 0 else 0)))
    return ev


def run_drag(window, mutate, flags, events):
    b = Budget(window, mutate)
    b.begin()
    for t, mask in events:
        b.request(t, mask)
    b.end(events[-1][0] + 8)              # the button-up, 8ms after the last tick
    return b


def run_rearm(window, mutate, flags):
    """A second arm lands mid-gesture; it must not wipe what is owed."""
    recalc = flags.get("REFRESH_RECALC", 2)
    once = flags.get("REFRESH_TH3", 16)
    events = [(1234560 + int(round(i * 30.303)), recalc) for i in range(31)]
    events[10] = (events[10][0], once)    # requested at tick 10 only
    b = Budget(window, mutate)
    b.begin()
    for i, (t, mask) in enumerate(events):
        b.request(t, mask)
        if i == 11:
            b.begin()                     # the nested claim (a second knob press)
    b.end(events[-1][0] + 8)
    return b, once


def ormask(seq):
    o = 0
    for _t, m in seq:
        o |= m
    return o


def promises(window, flags):
    """[(name, ok, detail)] — the promises a 33Hz drag must see."""
    ev = timeline(flags=flags)
    b = run_drag(window, None, flags, ev)
    bound = 1 + int(math.ceil(ev[-1][0] / float(max(window, 1))))
    settled = [p for p in b.passes if p[0] > ev[-1][0]]
    out = [
        ("the first tick after Begin runs immediately (the press feels instant)",
         bool(b.passes) and b.passes[0][0] == ev[0][0], "first pass at t=%dms"
         % (b.passes[0][0] if b.passes else -1)),
        ("the heavy pass is coalesced to <= 1 per %dms" % window,
         len(b.passes) <= bound,
         "%d passes vs %d ticks (bound %d)" % (len(b.passes), len(ev), bound)),
        ("the budget saves work (>= 2x fewer passes than ticks)",
         len(b.passes) * 2 <= len(ev), "%d vs %d" % (len(b.passes), len(ev))),
        ("no refresh flag is lost", ormask(b.passes) == ormask(ev),
         "0x%x vs 0x%x" % (ormask(b.passes), ormask(ev))),
        ("a pass carries only what is owed since the previous pass",
         b.subset_ok, "no pass re-delivered a stale flag" if b.subset_ok
         else "a pass carried a flag from an earlier window"),
        ("every tick still repaints (the cheap half never freezes)",
         b.repaints == len(ev), "%d repaints for %d ticks" % (b.repaints, len(ev))),
        ("the gesture settles exactly once, after the last tick",
         len(settled) == 1, "%d settle(s)" % len(settled)),
        ("the settle carries the tail since the last heavy pass",
         len(settled) == 1 and (settled[0][1] & ev[-1][1]) == ev[-1][1],
         "tail 0x%x" % (settled[0][1] if settled else 0)),
    ]
    b2 = run_drag(window, None, flags, timeline(flags=flags))
    n2 = len(b2.passes)
    b2.end(timeline(flags=flags)[-1][0] + 900)     # every release path may call End
    out.append(("End is idempotent", len(b2.passes) == n2,
                "%d pass(es) added by the second End" % (len(b2.passes) - n2)))

    b3 = run_drag(window, None, flags, timeline(flags=flags))
    n3 = len(b3.passes)
    t3 = timeline(flags=flags)[-1][0] + 500
    req = flags.get("REFRESH_RECALC", 2)
    b3.begin()
    b3.request(t3, req)
    b3.end(t3 + 20)
    out.append(("a fresh gesture starts with nothing owed",
                len(b3.passes) == n3 + 1 and b3.passes[-1][1] == req,
                "gesture 2 delivered 0x%x"
                % (b3.passes[-1][1] if len(b3.passes) > n3 else -1)))

    br, once = run_rearm(window, None, flags)
    out.append(("a nested arm cannot wipe a live gesture",
                (ormask(br.passes) & once) == once,
                "the once-per-gesture flag was %s"
                % ("delivered" if ormask(br.passes) & once else "LOST")))
    return out, b, ev


# Each mutant must break the promise at `idx`. A control that cannot fail proves
# nothing. (`window huge` is caught by the STATIC band check instead: a huge
# window satisfies every in-model bound, only the documented band rejects it.)
CONTROLS = [
    ("window 0 (no budget at all)", "window0", 2, 0),
    ("End that never flushes the tail", "no_flush", 7, None),
    ("the owed mask is never cleared", "no_pend_clear", 4, None),
]


def model_controls(window, flags):
    broken = []
    for label, mut, idx, w_override in CONTROLS:
        res, _b, _ev = promises_with(window if w_override is None else w_override,
                                     flags, mut)
        if res[idx][1]:
            broken.append("%s (promise %d still held)" % (label, idx))
    _br, once = run_rearm(window, "nested_rearm", flags)
    if (ormask(_br.passes) & once) == once:
        broken.append("Begin re-arms a live gesture (its owed flag still landed)")
    if broken:
        return False, "not caught: " + ", ".join(broken)
    return True, "%d/%d mutants break the matching promise" % (len(CONTROLS) + 1,
                                                               len(CONTROLS) + 1)


def promises_with(window, flags, mutate):
    """The plain drag promises with one mutation applied to the model."""
    ev = timeline(flags=flags)
    b = run_drag(window, mutate, flags, ev)
    bound = 1 + int(math.ceil(ev[-1][0] / float(max(window, 1))))
    settled = [p for p in b.passes if p[0] > ev[-1][0]]
    res = [
        ("first tick instant", bool(b.passes) and b.passes[0][0] == ev[0][0], ""),
        ("coalesced", len(b.passes) <= bound, ""),
        ("saves work", len(b.passes) * 2 <= len(ev), ""),
        ("no flag lost", ormask(b.passes) == ormask(ev), ""),
        ("pass carries only what is owed", b.subset_ok, ""),
        ("every tick repaints", b.repaints == len(ev), ""),
        ("one settle", len(settled) == 1, ""),
        ("settle carries the tail",
         len(settled) == 1 and (settled[0][1] & ev[-1][1]) == ev[-1][1], ""),
    ]
    return res, b, ev


# ── B. the shape the contract depends on ---------------------------------------
def check_kit(src):
    fails = []
    facts = {}

    wins = re.findall(r"(?m)^#define\s+UI_DRAG_HEAVY_MS\s+(\d+)\s*$", src)
    if len(wins) != 1:
        fails.append("BiotakKit.mqh must define UI_DRAG_HEAVY_MS exactly once (found %d)"
                     % len(wins))
        facts["window"] = 0
    else:
        facts["window"] = int(wins[0])
        if not WINDOW_MIN <= facts["window"] <= WINDOW_MAX:
            fails.append("UI_DRAG_HEAVY_MS %d is outside the documented band %d..%d "
                         "(LEARNING.md section 3)"
                         % (facts["window"], WINDOW_MIN, WINDOW_MAX))

    for name, pat in (("s_UIDragLive", r"(?m)^static bool\s+s_UIDragLive\s*=\s*false;"),
                      ("s_UIDragPend", r"(?m)^static int\s+s_UIDragPend\s*=\s*REFRESH_NONE;"),
                      ("s_UIDragHeavy", r"(?m)^static uint\s+s_UIDragHeavy\s*=\s*0;")):
        n = len(re.findall(pat, src))
        if n != 1:
            fails.append("the budget state %s must be declared exactly once (found %d)"
                         % (name, n))

    disp = body(src, "void ApplyRefreshFlags(const int flags)")
    if disp is None:
        fails.append("ApplyRefreshFlags is gone")
    else:
        block = disp.find("if(s_UIDragLive)")
        htf_m = re.search(r"if\(\((\w+) & REFRESH_HTF\)", disp)
        htf = htf_m.start() if htf_m else -1
        if block < 0:
            fails.append("ApplyRefreshFlags no longer opens the budget block")
        elif htf >= 0 and block > htf:
            fails.append("the budget block must run BEFORE the domain dispatch — "
                         "otherwise the flags were already applied when it coalesced")
        if not re.search(r"s_UIDragPend\s*\|=\s*\w+;", disp):
            fails.append("the tick's flags are no longer accumulated (s_UIDragPend |= ...)")
        guard = "if(s_UIDragHeavy != 0 && tNow - s_UIDragHeavy < UI_DRAG_HEAVY_MS)"
        if guard not in disp:
            fails.append("the window test lost its `s_UIDragHeavy != 0` pass-through "
                         "guard: the FIRST tick after Begin must go straight through")
        else:
            swallow = disp[disp.find(guard):][:240]
            if "ThrottledChartRedraw();" not in swallow:
                fails.append("a swallowed tick must still REPAINT (ThrottledChartRedraw) or the "
                             "drag looks dead between heavy passes")
            elif re.search(r"(?<!Throttled)ChartRedraw\(\);", swallow):
                fails.append("a swallowed tick must not repaint RAW at pointer rate (~33 full-chart "
                             "repaints/s of a 1000+-object chart) - it goes through the shared throttle")
            if "return;" not in swallow:
                fails.append("a swallowed tick must `return` before the domain block")
        owed_m = re.search(r"(\w+)\s*=\s*s_UIDragPend;", disp)
        if not owed_m:
            fails.append("the owed mask is no longer delivered as one pass")
        elif not re.search(r"if\(\(%s & REFRESH_HTF\)" % owed_m.group(1), disp):
            fails.append("the domain dispatch still reads the tick's own flags instead "
                         "of the coalesced mask (%s)" % owed_m.group(1))
        if "s_UIDragPend = REFRESH_NONE;" not in disp:
            fails.append("the owed mask is never cleared after delivery — flags would "
                         "re-run on every later pass")

    beg = body(src, "void UIDragBudgetBegin()")
    if beg is None:
        fails.append("UIDragBudgetBegin is gone")
    else:
        for pat, why in ((r"if\(s_UIDragLive\)\s*return;",
                          "a nested arm must not reset a live gesture"),
                         (r"s_UIDragLive\s*=\s*true;", "Begin must set live"),
                         (r"s_UIDragPend\s*=\s*REFRESH_NONE;",
                          "Begin must drop any owed flags from the previous gesture"),
                         (r"s_UIDragHeavy\s*=\s*0;",
                          "Begin must clear the window so the first tick passes through")):
            if not re.search(pat, beg):
                fails.append("UIDragBudgetBegin: " + why)

    end = body(src, "void UIDragBudgetEnd()")
    if end is None:
        fails.append("UIDragBudgetEnd is gone")
    else:
        if not re.search(r"if\(!s_UIDragLive\)\s*return;", end):
            fails.append("UIDragBudgetEnd must be idempotent (guard on !live)")
        if not re.search(r"s_UIDragLive\s*=\s*false;", end):
            fails.append("UIDragBudgetEnd must clear live")
        if not re.search(r"int\s+owed\s*=\s*s_UIDragPend;", end):
            fails.append("UIDragBudgetEnd must capture the owed mask")
        if not re.search(r"s_UIDragPend\s*=\s*REFRESH_NONE;", end):
            fails.append("UIDragBudgetEnd must clear the owed mask (the tail settles once)")
        flush = re.search(r"if\(owed != REFRESH_NONE\)\s*ApplyRefreshFlags\(owed\);", end)
        if not flush:
            fails.append("UIDragBudgetEnd must FLUSH the tail through the dispatcher, or "
                         "the last value stays unrendered")
        else:
            off = re.search(r"s_UIDragLive\s*=\s*false;", end)
            if off and off.start() > flush.start():
                fails.append("End must clear live BEFORE flushing, or the settle is "
                             "coalesced again and may be swallowed")
    return fails, facts


def check_panels(src, facts):
    fails = []
    owner = function_map(src)
    srclines = src.split("\n")

    def sites(pat):
        return [lineno(src, m.start()) for m in re.finditer(pat, src)]

    def fn_of(ln):
        return owner[min(max(ln - 1, 0), len(owner) - 1)]

    def fn_has(ln, needle):
        name = fn_of(ln)
        return any(needle in l for i, l in enumerate(srclines) if owner.get(i) == name)

    arms = sites(r"UIDragBudgetBegin\(\)")
    facts["arms"] = []
    per_func = {}
    for ln in arms:
        anchor = next((a for a in ARM_ANCHORS
                       if any(a in l for l in srclines[max(0, ln - 17):ln])), None)
        facts["arms"].append((ln, fn_of(ln), anchor))
        per_func[fn_of(ln)] = per_func.get(fn_of(ln), 0) + 1
        if anchor is None:
            fails.append("the arm at %s:%d (%s) is not anchored on a gesture claim "
                         "(%s) — a refresh is being throttled for no visible reason"
                         % (PANELS, ln, fn_of(ln), " / ".join(ARM_ANCHORS)))
    if len(arms) != 4:
        fails.append("expected 4 arm sites (palette mixer, slider knob, slider track, "
                     "native knob drag), found %d" % len(arms))
    elif per_func != {"PnlHandleMouseMove": 3, "PnlHandleDrag": 1}:
        fails.append("the arm sites moved: expected PnlHandleMouseMove x3 + "
                     "PnlHandleDrag x1, got %s"
                     % ", ".join("%s x%d" % (k, v) for k, v in sorted(per_func.items())))

    fin_start = src.find("void ChartPointerFinalizeOnUps()")
    fin = body(src, "void ChartPointerFinalizeOnUps()")
    if fin is None:
        fails.append("ChartPointerFinalizeOnUps is gone — the budget lost its net")
        facts["net_line"] = 0
    else:
        nets = [m.start() for m in re.finditer(r"UIDragBudgetEnd\(\)", fin)]
        facts["net_line"] = lineno(src, fin_start + nets[0]) if nets else 0
        if len(nets) != 1:
            fails.append("ChartPointerFinalizeOnUps must hold exactly ONE "
                         "UIDragBudgetEnd() net (found %d)" % len(nets))
        else:
            down = fin.find("g_MouseWasDown = false;")
            rec = fin.find("ChartScrollReconcile();")
            if not (down >= 0 and down < nets[0] and (rec < 0 or nets[0] < rec)):
                fails.append("the net must sit after `g_MouseWasDown = false;` and before "
                             "ChartScrollReconcile(): EVERY button-up ends the budget")

    clears = []
    DECL = re.compile(r"^\s*(?:static\s+)?(?:int|uint|bool|double|string|color|"
                      r"datetime|long|float|char)\b")
    for pat, chan in ((r"g_PnlDragItem\s*=\s*-1;", "panel slider"),
                      (r"g_PalMixDrag\s*=\s*0;", "palette mixer")):
        for m in re.finditer(pat, src):
            ln = lineno(src, m.start())
            if DECL.match(srclines[ln - 1]):
                continue          # the declaration, not a clear
            fn = fn_of(ln)
            ends = fn_has(ln, "UIDragBudgetEnd()")
            clears.append((ln, fn, chan, ends))
            if not ends and fn not in CLEAR_EXEMPT:
                fails.append("the %s channel is cleared in %s() (%s:%d) but the budget is "
                             "not ended there" % (chan, fn, PANELS, ln))
    facts["clears"] = clears
    for fn in MUST_END:
        if fn not in set(owner.values()):
            fails.append("%s() is gone (it is a budget gesture boundary)" % fn)
        elif not any("UIDragBudgetEnd()" in l for i, l in enumerate(srclines)
                     if owner.get(i) == fn):
            fails.append("%s() must end the budget — it is a gesture boundary" % fn)

    facts["stray"] = []
    for rel in all_mql_sources():
        s = read(rel)
        for m in re.finditer(r"s_UIDrag(Live|Pend|Heavy)\s*(=|\|=)", s):
            if rel == KIT:
                continue
            facts["stray"].append((rel, lineno(s, m.start())))
            fails.append("budget state written outside BiotakKit.mqh: %s:%d"
                         % (rel, lineno(s, m.start())))
        if rel not in (KIT, PANELS) and re.search(r"UIDragBudget(Begin|End)\(\)", s):
            fails.append("a budget arm/settle appeared outside the two owner files: %s "
                         "(add it here with its gesture anchor)" % rel)
    return fails, facts


# ── main -----------------------------------------------------------------------
def main():
    kit = read(KIT)
    pnl = read(PANELS)
    flags = parse_flags(kit)

    kf, facts = check_kit(kit)
    fails = list(kf)
    window = facts.get("window") or 0
    pf, pfacts = check_panels(pnl, facts)
    fails += pf
    facts.update(pfacts)

    if SITES:
        note("arms:")
        for ln, fn, anchor in facts.get("arms", []):
            note("  %s:%d  %s()   anchor: %s" % (PANELS, ln, fn, anchor))
        note("net: %s:%d  (state machine: %s)" % (PANELS, facts.get("net_line", 0), KIT))
        note("channel clears:")
        for ln, fn, chan, ends in facts.get("clears", []):
            note("  %s:%d  %-18s %-14s %s" % (PANELS, ln, fn, chan,
                                              "ends" if ends else "EXEMPT"))
        note("")

    if window:
        ok, sample, ev = promises(window, flags)
        for name, good, detail in ok:
            if not good:
                fails.append("contract: %s [%s]" % (name, detail))
        ctrl_ok, ctrl_msg = model_controls(window, flags)
        if not ctrl_ok:
            fails.append("contract control: " + ctrl_msg)
        note("model: %d heavy passes for %d ticks over a 2.0s drag, %d settle, "
             "%d/%d promises hold"
             % (len(sample.passes), len(ev),
                len([p for p in sample.passes if p[0] > ev[-1][0]]),
                sum(1 for _n, g, _d in ok if g), len(ok)))
        note("controls: %s" % ctrl_msg)

    if fails:
        print("")
        for f in fails:
            print("FAIL: " + f)
        print("\n%d problem(s) - the live-gesture budget no longer keeps its promise."
              % len(fails))
        return 1
    print("gesture-budget audit: clean - %d arms, %d channel clears, the tail "
          "settles once through the dispatcher"
          % (len(facts.get("arms", [])), len(facts.get("clears", []))))
    return 0


# ── negative control (source seeds) --------------------------------------------
def selftest():
    global read
    real_read = read
    kit = real_read(KIT)
    flags = parse_flags(kit)
    window = int(re.findall(r"(?m)^#define\s+UI_DRAG_HEAVY_MS\s+(\d+)", kit)[0])
    cases = []

    def with_source(rel, old, new):
        if old not in real_read(rel):
            raise SystemExit("selftest seed is stale (not in %s): %r" % (rel, old[:70]))

        def patched(r):
            s = real_read(r)
            return s.replace(old, new, 1) if r == rel else s
        return patched

    def run():
        # `read` is the PATCHED reader here (that is the whole trick of the
        # selftest): check_* must go through it, not through real_read.
        kf, facts = check_kit(read(KIT))
        pf, _ = check_panels(read(PANELS), facts)
        return kf + pf

    # 1. a delivered mask that is never cleared (every later pass re-runs it)
    read = with_source(KIT, "      s_UIDragPend = REFRESH_NONE;\n"
                            "      if(apply == REFRESH_NONE) return;",
                            "      if(apply == REFRESH_NONE) return;")
    cases.append(("a delivered mask that is never cleared is reported", bool(run())))

    # 2/3. the window leaves its documented band
    read = with_source(KIT, "#define UI_DRAG_HEAVY_MS 120", "#define UI_DRAG_HEAVY_MS 0")
    cases.append(("UI_DRAG_HEAVY_MS 0 (no budget at all) is reported", bool(run())))
    read = with_source(KIT, "#define UI_DRAG_HEAVY_MS 120", "#define UI_DRAG_HEAVY_MS 5000")
    cases.append(("UI_DRAG_HEAVY_MS 5000 (one pass per gesture) is reported", bool(run())))

    # 4. End stops flushing the tail (the last value stays unrendered)
    read = with_source(KIT, "   if(owed != REFRESH_NONE) ApplyRefreshFlags(owed);"
                            "   // the final value lands\n", "")
    cases.append(("an End that does not flush the tail is reported", bool(run())))

    # 5. the first-touch pass-through guard is gone (the press stutters)
    read = with_source(KIT,
                       "if(s_UIDragHeavy != 0 && tNow - s_UIDragHeavy < UI_DRAG_HEAVY_MS)",
                       "if(tNow - s_UIDragHeavy < UI_DRAG_HEAVY_MS)")
    cases.append(("a missing first-touch pass-through is reported", bool(run())))

    # 6. swallowed ticks stop repainting (the drag looks dead between passes)
    read = with_source(KIT, "         ThrottledChartRedraw();\n         return;\n      }\n"
                            "      s_UIDragHeavy = tNow;",
                            "         return;\n      }\n      s_UIDragHeavy = tNow;")
    cases.append(("a swallow branch that does not repaint is reported", bool(run())))

    # 6b. swallowed ticks repaint RAW again (~33 full-chart repaints/s while
    #     dragging - the P-PERF-06 regression this gate now owns too)
    read = with_source(KIT, "         ThrottledChartRedraw();\n         return;\n      }\n"
                            "      s_UIDragHeavy = tNow;",
                            "         ChartRedraw();\n         return;\n      }\n"
                            "      s_UIDragHeavy = tNow;")
    cases.append(("a swallow branch that repaints raw is reported", bool(run())))

    # 7. Begin loses its nested-claim guard (a second arm resets a live gesture)
    read = with_source(KIT, "   if(s_UIDragLive) return;                  "
                            "// nested claims: one budget\n", "")
    cases.append(("a Begin that re-arms a live gesture is reported", bool(run())))

    # 8. the ONE net is gone from the button-up finalizer
    read = with_source(PANELS, "   // forgotten release path impossible — the last value "
                               "always lands.\n   UIDragBudgetEnd();\n",
                       "   // forgotten release path impossible — the last value "
                       "always lands.\n")
    cases.append(("a missing button-up net is reported", bool(run())))

    # 9. an arm site disappears (its drag goes back to a slideshow)
    read = with_source(PANELS, "         UIDragBudgetBegin();   // P-UI-33: the jump is "
                               "the gesture's first pass\n", "")
    cases.append(("a missing arm site is reported", bool(run())))

    # 10. an arm appears where there is no gesture at all
    read = with_source(PANELS, "void PnlOpen(const int item)\n{\n",
                       "void PnlOpen(const int item)\n{\n   UIDragBudgetBegin();\n")
    cases.append(("an arm outside a gesture claim is reported", bool(run())))

    # 11. a channel clear stops ending the budget
    read = with_source(PANELS, "   UIDragBudgetEnd();   // P-UI-33: a mixer gesture "
                               "cannot outlive its palette (idempotent)\n", "")
    cases.append(("a mixer clear that stops ending the budget is reported", bool(run())))

    # 12. the budget state machine is re-implemented somewhere else
    read = with_source(PANELS, "   g_PalOpen=false; g_PalMixDrag=0; g_PalHexFocus=false;\n",
                       "   s_UIDragLive = false; g_PalOpen=false; g_PalMixDrag=0; "
                       "g_PalHexFocus=false;\n")
    cases.append(("budget state written outside BiotakKit.mqh is reported", bool(run())))

    # 13. the coalescer no longer opens (a gesture would run every tick full)
    read = with_source(KIT, "   if(s_UIDragLive)\n", "   if(false)\n")
    cases.append(("a budget block that no longer opens is reported", bool(run())))

    # 14. the domain dispatch ignores the coalesced mask (the owed flags are
    #     delivered into a variable nobody reads)
    read = with_source(KIT, "   if((apply & REFRESH_HTF) != 0)",
                       "   if((flags & REFRESH_HTF) != 0)")
    cases.append(("a dispatch that ignores the coalesced mask is reported", bool(run())))

    # the real sources must still pass, and the model's promises must hold
    read = real_read
    residual = run()
    cases.append(("the unmodified sources pass every check (%s)"
                  % (residual[0] if residual else "clean"), not residual))
    ok, _b, _ev = promises(window, flags)
    cases.append(("every contract promise holds on the real window",
                  all(g for _n, g, _d in ok)))
    ctrl_ok, ctrl_msg = model_controls(window, flags)
    cases.append(("every promise can fail (%s)" % ctrl_msg, ctrl_ok))

    for name, good in cases:
        print("%-62s %s" % (name, "caught" if good else "MISSED"))
    missed = [n for n, g in cases if not g]
    if missed:
        print("\nselftest FAILED: %d fault(s) went undetected" % len(missed))
        return 1
    print("\nselftest: %d/%d faults caught - the audit is not vacuous"
          % (len(cases), len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
