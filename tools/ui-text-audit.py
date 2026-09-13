#!/usr/bin/env python3
"""ui-text-audit - the gate behind P-UI-34 (one text metrics owner for the WHOLE UI).

P-UI-30 fixed how the SETTINGS CARDS measure a caption, but the metric owner was
written inside `BiotakPanels.mqh` - and in every entry (.mq4) the ring menu, its
hover tooltip, the Tools sub-menu and the BaseKnot hint are included BEFORE the
panels. So the surfaces with the TIGHTEST boxes were the ones that could not use
it, and they kept three defects the cards no longer had:

  * raw point sizes (`ObjectSetInteger(..., OBJPROP_FONTSIZE, 9)`) - MT4 sizes a
    font at the TERMINAL's DPI, so at 125% those captions draw 25% wider than
    the design and the ring tooltip's hints line measured 284px inside a 270px
    inner width (5% past the border at 125%, 26% at 150%);
  * widths GUESSED with `5 * StringLen(s)` at four sites of the Tools sub-menu
    (counter + "page/total" caption, create + move), so the counter drifted
    toward the panel edge and the pager text sat off-centre;
  * a second line placed by a magic `y + 26` instead of the title's own line
    box (which collides at 200% DPI).

Checks (source only, no terminal), plus a negative control per check:

  1. OWNER      `PnlDpi/PnlPt/PnlLineH/PnlAdvUnits/PnlTextW/PnlFit` are defined
                exactly ONCE, in `Biotak/UtilityFunctions.mqh` (the first UI
                module every surface includes).
  2. POINT SIZE no numeric literal in `OBJPROP_FONTSIZE` inside the UI chrome
                modules - a nominal size must flow through `PnlPt` (variables
                that carry a USER setting stay allowed).
  3. NO GUESSES no `N * StringLen(...)` width estimate in the UI modules.
  4. TIP FITS   every ring tooltip's title and hints (with the LONGEST status
                substituted) fit the tip's inner width at 96/120/144 dpi, the two
                lines stacked fit the tip's height, `CIRC_TIP_INNER` is the
                formula it claims to be, and the code CLIPS through `PnlFit` and
                places the second line through `PnlLineH`.
  5. READOUT    the sub-menu counter / pager caption x comes from
                `SubReadoutX` / `SubPagerTxtX` (create AND move).

The width model is NOT re-implemented here: the advance table, `PnlPt` rounding
and `PnlFit` live in `tools/panel-mt4-sim.py`, which is imported so the two can
never disagree.

Usage:  python tools/ui-text-audit.py [--quiet] [--selftest]
Exit 0 = clean, 1 = a surface is measuring text by hand again.
"""

import importlib.util
import os
import re
import sys

QUIET = "--quiet" in sys.argv or "--selftest" in sys.argv
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OWNER = "Biotak/UtilityFunctions.mqh"
OWNER_FUNCS = ("PnlDpi", "PnlPt", "PnlLineH", "PnlAdvUnits", "PnlTextW", "PnlFit")
# The modules whose captions sit in a FIXED box (the ones a wrong width breaks).
CHROME = ("Biotak/BiotakPanels.mqh", "Biotak/BiotakMenu.mqh", "Biotak/BaseKnotTool.mqh")
# Free chart labels / retired modules: a size literal here cannot overflow a box.
ALLOW_FONTSIZE = {
    "Biotak/ExtendedDrawingFunctions.mqh": "domain chart labels (no chrome box)",
    "Biotak/TH3/TH3Controller.mqh": "TH3 tool is retired (TH3TOOL-OFF)",
    "Biotak/TH3/TH3Renderer.mqh": "TH3 tool is retired (TH3TOOL-OFF)",
}
MENU = "Biotak/BiotakMenu.mqh"
DPIS = (96, 120, 144)


def note(*a):
    if not QUIET:
        print(*a)


def path(*p):
    return os.path.join(ROOT, *p)


def read(rel):
    with open(path(rel), "rb") as fh:
        return fh.read().decode("utf-8", "replace").replace("\r\n", "\n")


def load_sim():
    """The width model - one copy, in the proof tool."""
    spec = importlib.util.spec_from_file_location("panel_mt4_sim", path("tools/panel-mt4-sim.py"))
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["panel-mt4-sim.py"]           # keep its CLI parsing out of the way
    try:
        spec.loader.exec_module(mod)
    finally:
        sys.argv = argv
    return mod


def defines(src, name):
    m = re.search(r"(?m)^#define\s+%s\s+([0-9]+)\s*(?://.*)?$" % re.escape(name), src)
    return int(m.group(1)) if m else None


def code_only(src):
    """Drop full-line comments: the audit reads DOCUMENTATION and RETIRED code
    (both use the same call shapes) and must not report them as live sites."""
    out = []
    for line in src.split("\n"):
        out.append("" if line.lstrip().startswith("//") else line)
    return "\n".join(out)


def body(src, sig):
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


# ── 1. the owner is singular and lives low enough ──────────────────────────────
def check_owner(sources):
    fails = []
    facts = {}
    for fn in OWNER_FUNCS:
        where = [rel for rel, s in sources.items()
                 if re.search(r"(?m)^(?:int|string|double)\s+%s\s*\(" % fn, s)]
        facts[fn] = where
        if where != [OWNER]:
            fails.append("%s() must be defined exactly once, in %s (found: %s)"
                         % (fn, OWNER, ", ".join(where) or "nowhere"))
    if defines(sources.get(OWNER, ""), "PNL_PT_MIN") is None:
        fails.append("PNL_PT_MIN is no longer declared in %s" % OWNER)
    textw = body(sources.get(OWNER, ""), "int PnlTextW(const string s,const int nominalPt)")
    if not textw or "PnlLineH(" not in textw:
        fails.append("PnlTextW must measure with PnlLineH (one owner for the em box)")
    return fails, facts


# ── 2/3. no raw point sizes, no width guesses in the chrome ────────────────────
def check_literals(sources):
    fails = []
    sites = 0
    for rel in CHROME:
        src = code_only(sources[rel])
        for m in re.finditer(r"OBJPROP_FONTSIZE\s*,\s*([^)\s;]+)", src):
            arg = m.group(1)
            sites += 1
            if re.match(r"^\d", arg):
                fails.append("%s:%d passes a raw point size (%s) - it must be PnlPt(nominal)"
                             % (rel, src.count("\n", 0, m.start()) + 1, arg))
        # a GUESSED width: `5 * StringLen(s)` (P-UI-30's forbidden estimate). Match it
        # as a multiplication on a StringLen CALL, not on a literal length.
        for m in re.finditer(r"(?<![A-Za-z0-9_])(\d+)\s*\*\s*StringLen\(\s*[A-Za-z_]", src):
            fails.append("%s:%d estimates a caption width with `%s * StringLen` again - "
                         "use PnlTextW (P-UI-30)"
                         % (rel, src.count("\n", 0, m.start()) + 1, m.group(1)))
    for rel, why in ALLOW_FONTSIZE.items():
        if rel not in sources:
            continue
        for m in re.finditer(r"OBJPROP_FONTSIZE\s*,\s*(\d+)", sources[rel]):
            note("  allowed: %s:%d raw size %s (%s)"
                 % (rel, sources[rel].count("\n", 0, m.start()) + 1, m.group(1), why))
    return fails, sites


# ── 4/5. the two surfaces that had the tightest boxes ─────────────────────────
def tooltip_texts(menu):
    """Every tooltip's (title, hints) with the LONGEST status substituted."""
    code = code_only(menu)
    tb = body(code, "string CircItemTooltip(const int i)")
    if tb is None:
        return [], []
    lits = re.findall(r'"([^"]*)"', body(code, "string CircTooltipStatus(const int i)") or "")
    status = max(lits, key=len) if lits else "ON"
    worst = status + " \u00b7 H1"          # the HTF status appends " \u00b7 <TF>"
    out = []
    for r in re.findall(r"return\s+([^;]+);", tb):
        parts = re.findall(r'"([^"]*)"', r)
        if not parts:
            continue
        text = parts[0] + (worst if "CircTooltipStatus" in r else "")
        if len(parts) > 1 and "CircTooltipStatus" in r:
            text += parts[1]
        out.append(text.replace("\\n", "\n"))
    return out, worst


def check_tip(menu, sim):
    fails = []
    facts = {}
    w = defines(menu, "CIRC_TIP_W")
    h = defines(menu, "CIRC_TIP_H")
    px_ = defines(menu, "CIRC_TIP_PAD_X")
    py = defines(menu, "CIRC_TIP_PAD_Y")
    gap = defines(menu, "CIRC_TIP_GAP")
    pt_t = defines(menu, "CIRC_TIP_PT_T")
    pt_h = defines(menu, "CIRC_TIP_PT_H")
    if None in (w, h, px_, py, gap, pt_t, pt_h):
        return ["the tip's metrics are not fully declared (W/H/PAD_X/PAD_Y/GAP/PT_T/PT_H)"], {}
    facts.update(dict(w=w, h=h, padx=px_, pady=py, gap=gap, pt_t=pt_t, pt_h=pt_h))

    inner = re.search(r"(?m)^#define\s+CIRC_TIP_INNER\s+(.+)$", menu)
    got = inner.group(1).strip() if inner else ""
    got = got[1:-1].strip() if got.startswith("(") and got.endswith(")") else got
    want = "CIRC_TIP_W - 2 * CIRC_TIP_PAD_X"
    if got != want:
        fails.append("CIRC_TIP_INNER must be `%s` (it is the width every clip uses)" % want)
    inner_px = w - 2 * px_

    split = body(menu, "void CircTipSplit(const string full, string &title, string &hints)")
    if split is None:
        fails.append("CircTipSplit is gone - the tip no longer has one split+clip owner")
    else:
        if split.count("PnlFit(") < 2:
            fails.append("CircTipSplit must clip BOTH lines through PnlFit (a raw line "
                         "overflows the tip at >=125%% DPI)")

    show = body(menu, "void CircTipShow(const int feat, const int ax, const int ay)")
    if show is None:
        fails.append("CircTipShow is gone")
    elif "PnlLineH(CIRC_TIP_PT_T)" not in show:
        fails.append("the hints line's y must come from PnlLineH(CIRC_TIP_PT_T), not a "
                     "magic pixel offset (the two lines collide at 200%% otherwise)")

    tips, status = tooltip_texts(menu)
    facts["status"] = status
    facts["tips"] = len(tips)
    if not tips:
        fails.append("no tooltip text could be read out of CircItemTooltip")
    worst = []
    for dpi in DPIS:
        sim.DPI = dpi
        line_h_t = sim.dpi_pt(pt_t) * dpi / 72.0
        line_h_h = sim.dpi_pt(pt_h) * dpi / 72.0
        stacked = py + line_h_t + gap + line_h_h + py
        if stacked > h:
            fails.append("the tip's two lines need %.1fpx of a %dpx box at %ddpi"
                         % (stacked, h, dpi))
        for text in tips:
            nl = text.find("\n")
            title = text if nl < 0 else text[:nl]
            hints = "" if nl < 0 else text[nl + 1:]
            for label, s in (("title", title), ("hints", hints)):
                tw = sim.text_w(s, pt_t if label == "title" else pt_h)
                worst.append(tw)
                if tw > inner_px:
                    fails.append("at %ddpi the %s of a tooltip needs %dpx but only %dpx "
                                 "are inside the box: %r (status %r)"
                                 % (dpi, label, tw, inner_px, s[:46], status))
    facts["worst_px"] = max(worst) if worst else 0
    facts["inner_px"] = inner_px
    return fails, facts


def check_readout(menu):
    fails = []
    for fn in ("SubReadoutX", "SubPagerTxtX"):
        b = body(menu, "int %s(" % fn)
        if b is None:
            fails.append("%s() is gone - the sub-menu readout is measured by hand again" % fn)
        elif "PnlTextW(" not in b:
            fails.append("%s() must measure with PnlTextW" % fn)
    for site, owner in (("SubPanelCnt()", "SubReadoutX"),
                        ("SubPagerTxt()", "SubPagerTxtX")):
        uses = len(re.findall(r"%s\s*\(" % owner, menu)) - 1     # minus the definition
        if uses < 2:
            fails.append("%s must place the caption in BOTH paths (create + move); found %d use(s)"
                         % (owner, uses))
    if "OBJPROP_FONTSIZE, 10)" in menu or "Z_MENU_BADGE);" not in menu:
        pass
    return fails, {}


# ── main -----------------------------------------------------------------------
def main():
    sim = load_sim()
    sources = dict((rel, read(rel)) for rel in
                   set(list(CHROME) + [OWNER, MENU] + list(ALLOW_FONTSIZE)))
    fails = []

    f1, facts = check_owner(sources)
    fails += f1
    f2, sites = check_literals(sources)
    fails += f2
    f4, tip = check_tip(sources[MENU], sim)
    fails += f4
    f5, _ = check_readout(sources[MENU])
    fails += f5

    note("owner: %s (%s defined once each)" % (OWNER, ", ".join(OWNER_FUNCS)))
    note("point sizes: %d site(s), all through the owner" % sites)
    if tip:
        note("tip: %dx%d, inner %dpx, worst caption %dpx at %d/%d/%d dpi, %d tooltip(s), "
             "worst status %r"
             % (tip["w"], tip["h"], tip["inner_px"], tip["worst_px"], *DPIS,
                tip["tips"], tip["status"]))
    if fails:
        print("")
        for f in fails:
            print("FAIL: " + f)
        print("\n%d problem(s) - a UI surface is measuring text by hand again." % len(fails))
        return 1
    print("ui-text audit: clean - one metrics owner in %s, every chrome caption "
          "measured, the ring tooltip still fits" % OWNER)
    return 0


# ── negative control -----------------------------------------------------------
def selftest():
    global read
    real_read = read
    sim = load_sim()
    cases = []

    def with_source(rel, old, new, count=1):
        if real_read(rel).count(old) != count:
            raise SystemExit("selftest seed is stale (not in %s): %r" % (rel, old[:70]))

        def patched(r):
            s = real_read(r)
            return s.replace(old, new, count) if r == rel else s
        return patched

    def run():
        sources = dict((rel, read(rel)) for rel in
                       set(list(CHROME) + [OWNER, MENU] + list(ALLOW_FONTSIZE)))
        f = []
        f += check_owner(sources)[0]
        f += check_literals(sources)[0]
        f += check_tip(sources[MENU], sim)[0]
        f += check_readout(sources[MENU])[0]
        return f

    # 1. a second copy of the metrics owner (the drift this check exists for)
    read = with_source("Biotak/BiotakPanels.mqh",
                       "// \u2500\u2500 UI TEXT METRICS moved to Biotak/UtilityFunctions.mqh",
                       "int PnlPt(const int nominal) { return nominal; }\n"
                       "// \u2500\u2500 UI TEXT METRICS moved to Biotak/UtilityFunctions.mqh")
    cases.append(("a duplicated metrics owner is reported", bool(run())))

    # 2. a raw point size on a chrome surface
    read = with_source(MENU, "   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PnlPt(SUB_PT_PAGER));",
                       "   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);")
    cases.append(("a raw point size in the sub-menu is reported", bool(run())))

    # 3. a width guess (which also un-places the readout)
    read = with_source(MENU, "   return px + pw - SUB_GRID_PAD - PnlTextW(s, SUB_PT_READOUT);",
                       "   return px + pw - SUB_GRID_PAD - 5 * StringLen(s);")
    cases.append(("a `N * StringLen` width guess is reported", bool(run())))

    # 4a. one of the two tip lines stops being clipped
    read = with_source(MENU,
                       "   hints = PnlFit(nl >= 0 ? StringSubstr(full, nl + 1) : \"\", "
                       "CIRC_TIP_PT_H, CIRC_TIP_INNER);",
                       "   hints = (nl >= 0 ? StringSubstr(full, nl + 1) : \"\");")
    cases.append(("a tip line that is not clipped is reported", bool(run())))

    # 4b. the second line goes back to a magic offset
    read = with_source(MENU, "                    y + CIRC_TIP_PAD_Y + PnlLineH(CIRC_TIP_PT_T) + CIRC_TIP_GAP);",
                       "                    y + 26);")
    cases.append(("a magic second-line offset is reported", bool(run())))

    # 4c. the inner-width formula drifts from what the clip uses
    read = with_source(MENU, "#define CIRC_TIP_INNER  (CIRC_TIP_W - 2 * CIRC_TIP_PAD_X)",
                       "#define CIRC_TIP_INNER  (CIRC_TIP_W)")
    cases.append(("a CIRC_TIP_INNER that is not the clip's width is reported", bool(run())))

    # 4d. the box gets too short for its own two lines
    read = with_source(MENU, "#define CIRC_TIP_H   56", "#define CIRC_TIP_H   14")
    cases.append(("a tip box too short for its two lines is reported", bool(run())))

    # 5. the readout owner stops being used in one of the two paths
    read = with_source(MENU, "      ObjectSetInteger(0, SubPanelCnt(), OBJPROP_XDISTANCE, SubReadoutX(px, pw, cnt));",
                       "      ObjectSetInteger(0, SubPanelCnt(), OBJPROP_XDISTANCE,\n"
                       "                       px + pw - SUB_GRID_PAD - 5 * StringLen(cnt));")
    cases.append(("a readout placed by hand again is reported", bool(run())))

    read = real_read
    cases.append(("the unmodified sources pass every check", not run()))
    for name, good in cases:
        print("%-58s %s" % (name, "caught" if good else "MISSED"))
    missed = [n for n, g in cases if not g]
    if missed:
        print("\nselftest FAILED: %d fault(s) went undetected" % len(missed))
        return 1
    print("\nselftest: %d/%d faults caught - the audit is not vacuous"
          % (len(cases), len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
