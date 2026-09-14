#!/usr/bin/env python3
"""write-budget-audit - the gate behind P-PERF-02 (chart writes per frame).

WHY. In MT4 every `ObjectSet*` marks the chart dirty, so the terminal repaints a
chart whose repaint cost grows with the number of objects the indicator created
(~1000-2500 here). Work that is O(levels) or O(objects) per frame is therefore
not "a bit slow": it is the difference between a smooth chart and a slideshow on
a weak PC.

The fix (P-PERF-02) is one rule applied everywhere:

    never touch a chart object unless the value you would write differs from
    the value already there.

This gate locks in the four places where the rule is load-bearing:

  1. VISIBILITY  OBJPROP_TIMEFRAMES has exactly ONE guarded owner
                 (`ApplyTfMaskGuarded` in `Biotak/VisibilityManager.mqh`) and the
                 per-frame pipeline helpers go through it instead of writing
                 masks straight to the chart.
  2. GENERATION  every path that WIPES our objects (bulk clears, emergency
                 cleanup, cache reset) bumps `MarkDrawGeneration()`, because the
                 level render is skipped when its geometry signature is
                 unchanged - which is only sound while the objects that
                 signature produced are still on the chart.
  3. SIGNATURE   the level render in `RedrawAllObjects` is gated by that
                 geometry signature (an unchanged frame does no per-level work
                 at all), and the signature carries the generation.
  4. TEARDOWN    `DeleteAllIndicatorObjects` tears down with bulk kernel calls
                 (one `ObjectsDeleteAll` per namespace), never with an MQL loop
                 that walks every chart object and deletes ours one by one -
                 that loop was the timeframe-switch freeze.

Usage:  python tools/write-budget-audit.py [--quiet] [--selftest]
Exit 0 = the budget holds, 1 = a per-frame write (or an O(n) teardown) is back.
"""

import os
import re
import sys

QUIET = "--quiet" in sys.argv or "--selftest" in sys.argv
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

VIS = "Biotak/VisibilityManager.mqh"
OBJCACHE = "Biotak/ObjectCache.mqh"
PIPELINE = "Biotak/LevelPipeline.mqh"
EVENTS = "Biotak/EventHandlers.mqh"
HTF = "Biotak/HTFCandles.mqh"
PANELS = "Biotak/BiotakPanels.mqh"
GLOBALS = "Biotak/GlobalVariables.mqh"

FAILURES = []


def read(rel, overrides=None):
    if overrides and rel in overrides:
        return overrides[rel]
    with open(os.path.join(ROOT, rel), "r", encoding="utf-8-sig", errors="replace") as fh:
        return fh.read()


def fail(check, msg):
    FAILURES.append((check, msg))
    if not QUIET:
        print("  FAIL [%s] %s" % (check, msg))


def ok(check, msg):
    if not QUIET:
        print("  ok   [%s] %s" % (check, msg))


def fn_body(src, signature):
    """Return the text of a function: from its signature through the brace that
    closes it. Braces are counted from the signature itself, because this
    project writes both `void f(...) {` and `void f(...)\n{`.
    Strings/comments are ignored so a brace inside a literal cannot shift the
    depth."""
    i = src.find(signature)
    if i < 0:
        return None
    depth = 0
    in_str = False
    in_line_comment = False
    k = i
    while k < len(src):
        ch = src[k]
        nxt = src[k + 1] if k + 1 < len(src) else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
        elif in_str:
            if ch == "\\":
                k += 1
            elif ch == '"':
                in_str = False
        elif ch == "/" and nxt == "/":
            in_line_comment = True
            k += 1
        elif ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return src[i:k + 1]
        k += 1
    return src[i:]


# ---------------------------------------------------------------------------
# 1. VISIBILITY - one guarded owner, and the per-frame callers use it
# ---------------------------------------------------------------------------
def check_visibility(o):
    vis = read(VIS, o)
    owners = len(re.findall(r"\bbool\s+ApplyTfMaskGuarded\s*\(", vis))
    if owners != 1:
        fail("visibility", "ApplyTfMaskGuarded must be defined exactly once (found %d)" % owners)
    else:
        ok("visibility", "ApplyTfMaskGuarded is the single mask owner")

    # The owner itself is the ONLY place allowed a raw mask write, and it must
    # compare BOTH the stored value and the epoch before skipping.
    body = fn_body(vis, "bool ApplyTfMaskGuarded(") or ""
    if "CacheGetTfMask" not in body or "haveMask == mask" not in body or "haveEpoch == g_tfEpoch" not in body:
        fail("visibility", "the guard must skip only on (value AND epoch) match")
    else:
        ok("visibility", "the guard skips on value+epoch, never on the value alone")
    if "ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, mask)" not in body:
        fail("visibility", "the guard must be the writer of OBJPROP_TIMEFRAMES")

    # The two per-frame pipeline helpers (called for every line, label and zone).
    pipe = read(PIPELINE, o)
    for name in ("void SetPipelineObjectTimeframesIfExists(", "void SetPipelineZoneVisibility("):
        short = name.split("(")[0].strip()
        b = fn_body(pipe, name) or ""
        # Either it is the guarded writer itself or it delegates to the guarded
        # helper (SetPipelineZoneVisibility forwards its per-object calls).
        routed = ("ApplyTfMaskGuarded" in b) or ("SetPipelineObjectTimeframesIfExists" in b)
        if not routed:
            fail("visibility", "%s must route through the guarded mask writer" % short)
        elif re.search(r"ObjectSetInteger\(0,\s*[^,]+,\s*OBJPROP_TIMEFRAMES", b):
            fail("visibility", "%s still writes OBJPROP_TIMEFRAMES directly" % short)
        else:
            ok("visibility", "%s -> guarded" % short)

    # Bulk writers must tell the guard the truth (bump the epoch or drop the
    # stored masks), otherwise a guarded write can skip a mask they changed.
    labels = read("Biotak/LabelFunctions.mqh", o)
    for name in ("void SetATRLabelsVisibility(", "void SetTHLabelsVisibility("):
        b = fn_body(labels, name) or ""
        if "CacheForgetTfMasks(" not in b:
            fail("visibility", "%s writes masks outside the guard - it must call CacheForgetTfMasks" % name.split("(")[0].strip())
        else:
            ok("visibility", "%s drops the stale masks it overrides" % name.split("(")[0].strip())


# ---------------------------------------------------------------------------
# 2. GENERATION - every wipe invalidates the render's signature
# ---------------------------------------------------------------------------
def check_generation(o):
    g = read(GLOBALS, o)
    if "void MarkDrawGeneration()" not in g:
        fail("generation", "MarkDrawGeneration() must live in GlobalVariables.mqh")
    else:
        ok("generation", "MarkDrawGeneration() is the single generation owner")

    ev = read(EVENTS, o)
    wipers = [
        (ev, "void DeleteAllIndicatorObjects(", EVENTS),
        (ev, "void ClearAllLevels(", EVENTS),
        (ev, "void EmergencyCleanupIndicatorObjects(", EVENTS),
        (read(OBJCACHE, o), "void CacheClear()", OBJCACHE),
    ]
    for src, name, rel in wipers:
        b = fn_body(src, name) or ""
        if "MarkDrawGeneration()" not in b:
            fail("generation", "%s in %s wipes objects but never bumps the generation" % (name.split("(")[0].strip(), rel))
        else:
            ok("generation", "%s invalidates the render" % name.split("(")[0].strip())


# ---------------------------------------------------------------------------
# 3. SIGNATURE - the level render is gated, and the gate carries the generation
# ---------------------------------------------------------------------------
def check_signature(o):
    ev = read(EVENTS, o)
    b = fn_body(ev, "void RedrawAllObjects(") or ""
    if "frameSig" not in b:
        fail("signature", "RedrawAllObjects must build a geometry signature (frameSig)")
        return
    if "IntegerToString(g_drawGeneration)" not in b:
        fail("signature", "the geometry signature must include g_drawGeneration")
    else:
        ok("signature", "signature carries the draw generation")
    # The gate is NAMED so its terms are auditable, and it must carry all three:
    #   shouldClearLevels  - the topology signature says the level set changed
    #   geometryChanged    - the render signature says the picture changed
    #   g_renderAllNeeded  - a USER edit arrived through applyRefreshFlags
    #
    # P-PERF-30: the third one is not optional. frameSig only enumerates the
    # inputs it derives geometry from, while the paint reads MORE live globals
    # (structure switches, line look, mid-zone border, trigger transparency, the
    # midpoint line, custom-price look). Using the geometry signature to veto the
    # PAINT turned every input it omitted into a control that did nothing until a
    # timeframe switch - the reported "it only applies when I change timeframe".
    m = re.search(r"bool mustRender\s*=\s*\(([^;]*)\);", b)
    if not m:
        fail("signature", "the level render gate must be named (mustRender) so its terms can be audited")
        return
    terms = m.group(1)
    for need in ("shouldClearLevels", "geometryChanged", "g_renderAllNeeded"):
        if need not in terms:
            fail("signature", "the render gate dropped %s: a user edit it cannot see would paint nothing until a timeframe switch" % need)
            return
    # P-PERF-06: the staged form appends `&& g_buildStage != BUILD_STAGE_BLOCK`
    # (the BLOCK stage draws nothing itself - the labels block is its family),
    # so the gate accepts a trailing condition.
    if not re.search(r"if\s*\(\s*mustRender\s*&&", b):
        fail("signature", "DrawLevelsBasedOnMode must sit behind mustRender")
    elif "s_lastFrameCore = frameCore; g_renderAllNeeded = false; }" not in b:
        fail("signature", "the stage-0 seal does not consume the user-edit escalation: every frame would re-assert the whole family")
    else:
        ok("signature", "the render gate is the recompute signature plus the user-edit escalation")
    # The levels-off branch must invalidate the stored signature.
    if "s_lastFrameSig = \"\";" not in b:
        fail("signature", "turning levels off must invalidate the stored signature")
    else:
        ok("signature", "levels-off invalidates the signature")
    # Idle frames must not ask for a chart repaint.
    calc = fn_body(ev, "int OnCalculateHandler(") or ""
    if not re.search(r"if\s*\(\s*g_lastRedrawDidWork\s*\)", calc):
        fail("signature", "OnCalculateHandler must only repaint when the frame drew (g_lastRedrawDidWork)")
    elif "g_lastRedrawDidWork = true;" not in b:
        fail("signature", "RedrawAllObjects must set g_lastRedrawDidWork when it really draws")
    else:
        ok("signature", "idle frames stop asking for a chart repaint")


# ---------------------------------------------------------------------------
# 4. TEARDOWN - bulk kernel calls instead of an O(all objects) MQL loop
# ---------------------------------------------------------------------------
def check_teardown(o):
    ev = read(EVENTS, o)
    b = fn_body(ev, "void DeleteAllIndicatorObjects(") or ""
    if "ObjectsDeleteAll(0, inpObjectPrefix" not in b:
        fail("teardown", "DeleteAllIndicatorObjects must bulk-delete by namespace")
    elif re.search(r"for\s*\([^)]*ObjectsTotal", b) or re.search(r"for\b[\s\S]*?ObjectDelete\(0, objName", b):
        fail("teardown", "DeleteAllIndicatorObjects is back to an O(all chart objects) MQL loop")
    else:
        ok("teardown", "teardown is O(namespaces) kernel calls")
    if "_BK_" not in b:
        fail("teardown", "the shallow teardown must be explicit about preserving the Base/Knot layer")

    # Hide-all is a transition, not a per-frame action.
    body = fn_body(ev, "bool HideAllTHObjects()") or ""
    if "g_hideAllApplied" not in body:
        fail("teardown", "HideAllTHObjects must run once per hide transition")
    else:
        ok("teardown", "hide-all runs once per transition")
    resets = len(re.findall(r"ResetHideAllState\(\)", ev))
    if resets < 4:
        fail("teardown", "ResetHideAllState() must be called from every show/init/deinit path (found %d)" % resets)
    else:
        ok("teardown", "hide-all state is re-armed on show/init/deinit (%d sites)" % resets)


# ---------------------------------------------------------------------------
# 5. HTF - budget checked before the series reads
# ---------------------------------------------------------------------------
def check_htf(o):
    htf = read(HTF, o)
    b = fn_body(htf, "bool UpdateHTFFormingCandle()") or ""
    gate = "(formNow - g_HTFFormWriteMs) < HTF_FORM_MS"
    if gate not in b:
        fail("htf", "UpdateHTFFormingCandle must respect the write budget (HTF_FORM_MS)")
        return
    budget = b.find(gate)
    first_read = min([b.find(s) for s in ("iOpen(_Symbol", "iHigh(_Symbol", "iClose(_Symbol", "iLow(_Symbol")
                    if b.find(s) >= 0] or [-1])
    if first_read >= 0 and budget > first_read:
        fail("htf", "the budget must be checked BEFORE the OHLC series reads")
    else:
        ok("htf", "a throttled tick costs one iTime and nothing else")
    if "HTFViewportBarTarget" not in htf:
        fail("htf", "the HTF history must be capped to the viewport")
    else:
        ok("htf", "HTF history is viewport-capped")


# ---------------------------------------------------------------------------
# 5b. HTF LOOK - a setting written at CREATE must be re-written when it CHANGES
#
# WHY. Every HTF object is UPSERTED, never re-created: the same wick/rectangle is
# found again on the next pass and only the properties that differ are written.
# That makes a look property set ONLY in the create branch WRITE-ONCE - and a
# write-once look is a slider that lies. Reported as "the shadows are still thin
# and the setting does not apply": the HTF card's WICK WIDTH slider moved,
# g_HTFWickWidth changed, REFRESH_HTF drew everything again, and every existing
# wick kept the 1 px it was born with, while its counterpart (the body rectangle)
# obeyed the same slider instantly. The asymmetry is the tell: an upsert that
# re-compares its colour but not its width never re-asserts half its look.
#
# The gate asserts the SHAPE of the fix rather than a list of names: for every
# property an upsert writes from a LIVE value (a setting global or a function
# parameter - never a literal like STYLE_SOLID or BACK=true, which never change
# for a given object name), the update branch must carry a GUARDED write of that
# same property. Losing the guard is caught too, so the fix cannot decay into
# "write it every frame", which is the budget this file exists to protect.
# ---------------------------------------------------------------------------
LOOK_PROPS = ("COLOR", "WIDTH", "STYLE", "FILL")


def _live_props(create_body, params):
    """Look properties the create branch writes from a value that can CHANGE:
    a setting global or one of the function's own parameters."""
    props = set()
    for m in re.finditer(r"ObjectSet\w+\(0,\s*name,\s*OBJPROP_(\w+)\s*,\s*([^;]*?)\);", create_body):
        prop, val = m.group(1), m.group(2).strip()
        if prop not in LOOK_PROPS:
            continue
        if "g_" in val or val in params:
            props.add(prop)
    return props


def _guarded(update_body, prop):
    """A write of `prop` that sits behind a comparison (the P-PERF-02 rule)."""
    return re.search(r"if\s*\([^)]*!=[^)]*\)\s*ObjectSet\w+\(0,\s*name,\s*OBJPROP_"
                     + prop + r"\b", update_body)


def check_htf_look(o):
    htf = read(HTF, o)
    # P-UI-68: the shadow is a FILLED RECTANGLE now, so the wick's own upsert is
    # gone — every HTF object (body, shadow, border pair) goes through this one
    # upsert, which keeps the create/update split the rule is about.
    upserts = [("HTFRectUpsert", "void HTFRectUpsert(")]
    for short, sig in upserts:
        body = fn_body(htf, sig) or ""
        if not body:
            fail("htf-look", "%s is gone (this gate reads it)" % short)
            continue
        create_at = body.find("if(!onChart)")
        update_at = body.find("if(known)")
        create = brace_block(body, create_at) if create_at >= 0 else None
        update = brace_block(body, update_at) if update_at >= 0 else None
        if not create or not update:
            fail("htf-look", "%s must keep its create/update split, or a setting can be written once and "
                             "never re-asserted" % short)
            continue
        params = set(re.findall(r"\b(?:string|datetime|double|color|int|bool)\s+(\w+)",
                                body[:body.find("{")]))
        live = _live_props(create, params)
        if not live:
            fail("htf-look", "%s no longer writes any live look property at create - the parse "
                             "lost its anchor" % short)
            continue
        dropped = sorted(p for p in live if not _guarded(update, p))
        if dropped:
            fail("htf-look", "%s writes %s at CREATE but never re-compares it on UPDATE: that "
                             "setting is write-once - moving its slider changes nothing on an "
                             "object that already exists" % (short, "/".join(dropped)))
        else:
            ok("htf-look", "%s re-asserts every live look it can change (%s)"
                           % (short, "/".join(sorted(live))))


# ---------------------------------------------------------------------------
# 5c. HTF GEOMETRY - one owner for the candle's SHAPE (P-UI-68)
#
# WHY. The candle's shape is four times (body L/R, shadow L/R) and every one of
# them used to be computed where it was used: the body was the whole period, the
# shadow was a 1 px trend line in the CALENDAR middle. The user's screenshot asks
# for a shape instead — a shadow BOX, centred, and a gap between neighbouring
# candles — which makes "where does this edge sit" a real computation that must
# have exactly one answer. The regression this gate exists for is the one that
# already happened once: the calendar middle of a W1/MN candle (a weekend inside
# one candle) is ~70% across, so a shadow computed from the calendar is visibly
# off-centre on exactly the high timeframes, and a gap/share measured in calendar
# seconds is visibly fatter on exactly them too.
#
# The gate asserts the SHAPE, not a list of lines:
#   (a) DrawHTFCandleCore derives the whole candle from ONE call and computes no
#       edge of its own (no calendar midpoint, no chart-time conversion);
#   (b) the old second owner (HTFBodyMidTime) does not exist;
#   (c) the geometry maps through the chart-INDEX bridge, so equal index distance
#       is equal pixel distance;
#   (d) it is NaN-fenced and CLAMPED (both settings, the shadow against the body);
#   (e) the shadow is a filled RECTANGLE — an OBJ_TREND wick may not come back;
#   (f) every geometry key the saver writes is deleted by the cleanup owner, and
#       the loader clamps what it reads (a GV is not user input).
# ---------------------------------------------------------------------------
def check_htf_geometry(o):
    htf = read(HTF, o)
    core = fn_body(htf, "void DrawHTFCandleCore(") or ""
    geom = fn_body(htf, "SHTFCandleGeom HTFCandleGeometry(") or ""
    if not core or not geom:
        fail("htf-geometry", "DrawHTFCandleCore / HTFCandleGeometry are gone (this gate reads them)")
        return

    # (a) one call, no hand-computed edge in the core
    if core.count("HTFCandleGeometry(") != 1:
        fail("htf-geometry", "DrawHTFCandleCore must derive the candle from exactly ONE "
                             "HTFCandleGeometry() call (found %d)" % core.count("HTFCandleGeometry("))
    elif "(nt - ot)" in core or "HTFChartTimeAt" in core:
        fail("htf-geometry", "DrawHTFCandleCore computes an edge itself (calendar span or chart "
                             "time) instead of using the geometry owner")
    else:
        ok("htf-geometry", "the candle's four edges come from one owner")

    # (b) no second owner of the middle
    if "HTFBodyMidTime" in htf:
        fail("htf-geometry", "HTFBodyMidTime is back: the mid is HTFCandleGeometry's alone")
    else:
        ok("htf-geometry", "the drawn middle has one owner")

    # (c) the index bridge
    if "HTFChartIndexAt(" not in geom or "HTFChartTimeAt(" not in geom:
        fail("htf-geometry", "the geometry must map through the chart-index bridge "
                             "(HTFChartIndexAt -> HTFChartTimeAt), or a weekend inside the period "
                             "skews every high timeframe")
    else:
        ok("htf-geometry", "edges are measured where they are drawn (index space)")

    # (d) fences
    missing = [n for n in ("MathIsValidNumber(iL)", "MathIsValidNumber(iR)",
                           "HTF_GAP_PCT_MAX", "HTF_SHADOW_PCT_MAX",
                           "if(halfShadow > bodyHalf) halfShadow = bodyHalf;",
                           "if(halfShadow * 2.0 < 1.0) halfShadow = 0.5;")
               if n not in geom]
    if missing:
        fail("htf-geometry", "the geometry lost a fence: %s (a NaN or an out-of-range setting "
                             "would reach ObjectSetDouble)" % ", ".join(missing))
    else:
        ok("htf-geometry", "both settings clamped, NaN-fenced, the shadow bounded by the body")

    # (e) the shape: a filled rectangle, never the retired trend-line wick
    box = fn_body(htf, "void HTFShadowBox(") or ""
    # the retired type shows up in prose here (the P-UI-68 notes and the delete
    # path's history), so the rule is about a CREATE, not a mention
    if re.search(r"ObjectCreate\([^;]*OBJ_TREND", htf):
        fail("htf-geometry", "an OBJ_TREND is being created again in the HTF engine: the shadow "
                             "is a BOX")
    elif "OBJ_RECTANGLE" not in htf:
        fail("htf-geometry", "no rectangle creation left in the HTF engine")
    elif "HTFRectUpsert(name, tL, p1, tR, p2, clr," not in box or "true, true)" not in box:
        fail("htf-geometry", "HTFShadowBox must draw the shadow through the guarded upsert as a "
                             "FILLED background box")
    elif "OBJPROP_TYPE" not in htf:
        fail("htf-geometry", "the upsert lost its TYPE FENCE: an old OBJ_TREND wick carried in by a "
                             "template would be re-asserted as a rectangle and stay a line forever")
    else:
        ok("htf-geometry", "the shadow is a filled rectangle behind the price action")

    # (f) persistence: every key the saver writes is deleted by the cleanup
    save = fn_body(htf, "void SaveHTFCandlesSettings(") or ""
    clean = fn_body(htf, "void CleanupHTFCandlesGVs(") or ""
    keys = re.findall(r'GlobalVariableSet\(prefix \+ "(\w+)"', save)
    if not keys:
        fail("htf-geometry", "SaveHTFCandlesSettings no longer writes any key - the parse lost its anchor")
        return
    orphan = [k for k in keys if 'GlobalVariableDel(prefix + "%s")' % k not in clean]
    if orphan:
        fail("htf-geometry", "HTF key(s) %s are saved but never deleted: a removed indicator leaves "
                             "them on the chart id forever (P-UI-60)" % ", ".join(orphan))
    else:
        ok("htf-geometry", "every saved geometry key has its cleanup owner (%d)" % len(keys))

    # (g) the card's slider range and the engine's clamp are ONE contract. The row
    # definitions live in the panel source and the bounds in the engine's, so the
    # numbers appear twice by necessity - which is exactly why a gate has to read
    # both. A slider that can reach past the clamp is a control that lies at its far
    # end; a clamp narrower than the slider is a setting the user cannot use.
    panel = read(PANELS, o)
    bounds = dict(re.findall(r"#define (HTF_(?:GAP|SHADOW)_PCT_(?:MIN|MAX))\s+(\d+)", htf))
    rows = {m[0]: (m[1], m[2]) for m in re.findall(
        r'label="(SHADOW WIDTH|SHADOW GAP)";\s*unit="%";\s*minV=(\d+);\s*maxV=(\d+);', panel)}
    want = {"SHADOW WIDTH": ("HTF_SHADOW_PCT_MIN", "HTF_SHADOW_PCT_MAX"),
            "SHADOW GAP": ("HTF_GAP_PCT_MIN", "HTF_GAP_PCT_MAX")}
    for label, (lo, hi) in want.items():
        got = rows.get(label)
        if got is None:
            fail("htf-geometry", "the HTF card no longer renders the %s row (this gate reads it)" % label)
        elif lo not in bounds or hi not in bounds:
            fail("htf-geometry", "%s is no longer declared in the engine" % label)
        elif (int(got[0]), int(got[1])) != (int(bounds[lo]), int(bounds[hi])):
            fail("htf-geometry", "%s: the slider allows %s..%s while the engine clamps %s..%s - "
                                 "the row and the clamp must be the same range"
                                 % (label, got[0], got[1], bounds[lo], bounds[hi]))
        else:
            ok("htf-geometry", "%s slider range == the engine clamp (%s..%s)"
                               % (label, got[0], got[1]))

    load = fn_body(htf, "void InitializeHTFCandles(") or ""
    for key, lo, hi in (("GapPct", "HTF_GAP_PCT_MIN", "HTF_GAP_PCT_MAX"),
                        ("ShadowPct", "HTF_SHADOW_PCT_MIN", "HTF_SHADOW_PCT_MAX")):
        at = load.find('GlobalVariableCheck(prefix + "%s")' % key)
        block = load[at:at + 400] if at >= 0 else ""
        if at < 0 or lo not in block or hi not in block:
            fail("htf-geometry", "%s must be CLAMPED when it is loaded: a persisted value from "
                                 "another build is not user input" % key)
        else:
            ok("htf-geometry", "%s is clamped on the way in" % key)


# ---------------------------------------------------------------------------
# 6. MODEL - the guard's write count (the promise, not the shape)
# ---------------------------------------------------------------------------
def model_writes(desired, epoch_bumps):
    """Mirror of ApplyTfMaskGuarded: writes == real ObjectSetInteger calls."""
    epoch = 1
    stored = {}
    writes = 0
    bump_at = set(epoch_bumps)
    for i, (name, mask) in enumerate(desired):
        if i in bump_at:
            epoch += 1
        got = stored.get(name)
        if got is not None and got[0] == epoch and got[1] == mask:
            continue                      # skipped: pixels already match
        writes += 1
        stored[name] = (epoch, mask)
    return writes


def check_model():
    objects = [("L%d" % i, -1) for i in range(300)]      # 300 lines, hidden
    frames = objects * 5                                  # five identical frames
    identical = model_writes(frames, [])
    if identical != len(objects):
        fail("model", "5 identical frames must write once per object (got %d)" % identical)
    else:
        ok("model", "5 identical frames -> %d writes instead of %d" % (identical, len(frames)))

    toggled = model_writes([("L%d" % i, 1) for i in range(300)], [])  # L key shows all
    if toggled != 300:
        fail("model", "a visibility toggle must land once per object (got %d)" % toggled)
    else:
        ok("model", "a toggle re-asserts exactly once per object")

    bumped = model_writes([("L%d" % i, 1) for i in range(300)], [150])
    if bumped != 300:
        fail("model", "an epoch bump must not turn into per-frame writes (got %d)" % bumped)
    else:
        ok("model", "an epoch bump costs one pass, not a per-frame spray")

    # Regression shape: the OLD code wrote every object on every frame.
    if not QUIET:
        print("  ok   [model] before/after on 300 objects x 5 frames: %d -> %d" % (1500, identical))


# ---------------------------------------------------------------------------
# 7. BOUNDARY - the :00/:30 base-price block is an EDGE, not a whole minute
# ---------------------------------------------------------------------------
def brace_block(src, start):
    """Text of the brace group beginning at the first `{` at/after `start`."""
    i = src.find("{", start)
    if i < 0:
        return None
    depth = 0
    k = i
    while k < len(src):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                return src[i:k + 1]
        k += 1
    return src[i:]


def check_boundary(o):
    ev = read(EVENTS, o)
    b = fn_body(ev, "void RedrawAllObjects(") or ""
    if re.search(r"basePriceBoundary\s*=\s*\(\s*(?:currentServerMinute|TimeMinute\()[\s\S]{0,80}?==\s*0\s*\|\|", b):
        fail("boundary", "the base-price boundary is a whole minute again (240 full passes/hour)")
        return
    cand = re.search(r"bool\s+boundaryCandidate\s*=\s*\(\s*onBoundaryMinute\s*&&\s*boundaryBlock\s*!=\s*s_lastBoundaryBlock\s*\)\s*;", b)
    flags = re.findall(r"basePriceBoundary\s*=\s*boundaryCandidate\s*;", b)
    commit = re.findall(r"if\s*\(\s*boundaryCandidate\s*\)\s*s_lastBoundaryBlock\s*=\s*boundaryBlock\s*;", b)
    if not cand or len(flags) != 1 or len(commit) != 1:
        fail("boundary", "the block must be armed as a candidate, consumed once, and committed past "
                         "every gate (candidate=%d flag=%d commit=%d)" % (1 if cand else 0, len(flags), len(commit)))
        return
    # The commit has to sit AFTER the gates: a block recorded before them can be
    # swallowed by the millisecond gate and never run its base-price work.
    gate = b.find("if(!hasPendingWork)")
    if gate < 0 or b.find("if(boundaryCandidate) s_lastBoundaryBlock = boundaryBlock;") < gate:
        fail("boundary", "the block must be committed after the hasPendingWork/gate returns, not before")
    else:
        ok("boundary", "the 30-minute boundary is edge-triggered (one pass per block)")


# ---------------------------------------------------------------------------
# 8. BULK SERIES - no per-bar iTime()/iBars() walk on the heavy paths
# ---------------------------------------------------------------------------
def check_bulk_series(o):
    det = read("Biotak/DynamicTradingDayDetector.mqh", o)
    b = fn_body(det, "datetime FindCurrentSessionStart(") or ""
    if not b:
        fail("series", "FindCurrentSessionStart is gone")
    elif re.search(r"iTime\s*\(", b):
        fail("series", "FindCurrentSessionStart walks bars with iTime() again (20k-48k series reads)")
    elif "DetectFetchBarTimes(" not in b:
        fail("series", "FindCurrentSessionStart must read bar times in one bulk CopyTime")
    else:
        ok("series", "session-start detection is one bulk CopyTime + a memory scan")
    if "s_cachedStart" not in b:
        fail("series", "FindCurrentSessionStart must memoise its per-day answer")

    bpm = read("Biotak/BasePriceManager.mqh", o)
    blk = fn_body(bpm, "int FindLastM1CandleInBlock(") or ""
    if "CopyTime(" not in blk:
        fail("series", "FindLastM1CandleInBlock must fetch the block window in one CopyTime")
    else:
        ok("series", "M1 block lookup is one windowed CopyTime")


# ---------------------------------------------------------------------------
# 9. ALERTS - the check scans the render's own price list, not the chart
# ---------------------------------------------------------------------------
def check_alerts(o):
    al = read("Biotak/AlertFunctions.mqh", o)
    b = fn_body(al, "void CheckAlerts(") or ""
    if not b:
        fail("alerts", "CheckAlerts is gone")
    elif re.search(r"ObjectFind\s*\(", b) or re.search(r"ObjectGetDouble\s*\(", b):
        fail("alerts", "CheckAlerts walks the chart again (~2 x inpMaxLevels syscalls per frame)")
    elif "g_alertLevels" not in b:
        fail("alerts", "CheckAlerts must scan the cached level prices")
    else:
        ok("alerts", "the alert check is a pure in-memory scan")
    g = read(GLOBALS, o)
    if "void AlertCacheReset(" not in g or "void AlertCacheAdd(" not in g:
        fail("alerts", "the alert level cache owner must live in GlobalVariables.mqh")
    pipe = read(PIPELINE, o)
    if fn_body(pipe, "void RenderTriggerLines(") and "AlertCacheAdd(" not in (fn_body(pipe, "void RenderTriggerLines(") or ""):
        fail("alerts", "RenderTriggerLines must record every level it prices")
    else:
        ok("alerts", "the render records the levels the alert check reads")


# ---------------------------------------------------------------------------
# 10. LABEL CLEAR / WARMUP - no 11-way kernel sweep, no 8-TF stall
# ---------------------------------------------------------------------------
def check_lazy_group(o):
    lf = read("Biotak/LabelFunctions.mqh", o)
    b = fn_body(lf, "void ClearAllLabels(") or ""
    # P-PERF-38f: the sweep used to run once per DRAW GENERATION, i.e. on every
    # timeframe switch - 11 full-chart prefix walks to clear names that the
    # timeframe-free scheme (P-PERF-38) can no longer create and that the one-time
    # per-chart migration (P-PERF-38c) already removes, whose prefix set is a
    # superset of this loop's. The correct cadence is therefore the migration's,
    # not the generation's: the assertion moved with the fix instead of freezing
    # the defect.
    if "if(!LegacyNameSchemeMigrated())" not in b:
        fail("clear", "ClearAllLabels must gate the cross-TF sweep on the one-time migration stamp")
    else:
        ok("clear", "the cross-TF label sweep runs once per chart, on the migration's own stamp")

    atr = read("Biotak/ATRCalculations.mqh", o)
    w = fn_body(atr, "void WarmupATRMultiTFCache(") or ""
    if re.search(r"for\s*\([^)]*\)\s*\{[^}]*GetATRForTimeframe", w):
        fail("warmup", "the ATR warmup computes every timeframe in one init again")
    elif "WarmupATRStep(" not in w:
        fail("warmup", "the ATR warmup must drain one timeframe per pass")
    else:
        ok("warmup", "the ATR warmup is amortised across tick/timer passes")
    kit = read("Biotak/BiotakKit.mqh", o)
    if "WarmupATRStep()" not in kit:
        fail("warmup", "nothing pumps the warmup queue (RefreshUIPerTick must call WarmupATRStep)")
    else:
        ok("warmup", "RefreshUIPerTick drains the warmup queue")


# ---------------------------------------------------------------------------
# 12. ATR COMPOSITE - one bulk copy per series, never ~4 reads per bar
#
# P-PERF-05: the composite is the biggest single-frame cost in the live MT4 log
# (`[W][PERF] chart event id=9` 3.7-4.1 s after every attach / timeframe switch,
# and the one ledger frame that named a phase said base=2281 of 2296 ms). The
# rule: the legs read ARRAYS from one bulk copy per series, the orientation is
# PROVEN from the copied timestamps before the first read, and the scalar
# per-bar leg survives only as the parity fallback (a cold/unsynchronised series
# may change a leg's cost, never its value). A regression here is invisible on
# screen and only shows up as a frozen chart on every timeframe switch, so it
# needs a gate rather than a comment.
# ---------------------------------------------------------------------------
def check_atr_bulk(o):
    atr = read("Biotak/ATRCalculations.mqh", o)
    b = fn_body(atr, "void CalculateATRBatchTrex(") or ""
    if not b:
        fail("atr", "CalculateATRBatchTrex is gone")
    elif "TrexSMALegsBatch(" not in b:
        fail("atr", "the composite must go through the bulk-copy leg engine")
    elif re.search(r"TrexSMALeg\s*\(|iHigh\s*\(|iLow\s*\(|iClose\s*\(", b):
        fail("atr", "the composite reads the series bar by bar again "
                    "(~2000 calls inside one frame)")
    else:
        ok("atr", "the composite legs come from the bulk-copy leg engine")

    l = fn_body(atr, "void TrexSMALegsBatch(") or ""
    if not l:
        fail("atr", "the bulk-copy leg engine is gone")
    else:
        want = ("CopyHigh(", "CopyLow(", "CopyClose(", "CopyTime(")
        missing = [c[:-1] for c in want if c not in l]
        if missing:
            fail("atr", "the leg engine must copy High/Low/Close/Time in one call each "
                        "(missing: %s)" % ", ".join(missing))
        elif "TrexBatchOrient(" not in l:
            fail("atr", "the leg engine must PROVE the copy orientation before reading it")
        elif "TrexSMALeg(" not in l:
            fail("atr", "the scalar leg must stay as the parity fallback - a cold series "
                        "cannot silently zero a leg")
        elif re.search(r"iHigh\s*\(|iLow\s*\(|iClose\s*\(", l):
            fail("atr", "the leg engine reads the series per bar on its fast path")
        else:
            ok("atr", "one bulk copy per series, orientation proven, scalar fallback kept")

    t = fn_body(atr, "bool TrexBatchOrient(") or ""
    if not t:
        fail("atr", "the orientation guard is gone (the window can be read backwards)")
    elif "ArraySetAsSeries(" not in t:
        fail("atr", "orientation must be normalised, not assumed (Copy* semantics differ)")
    elif not (re.search(r"timeArr\[0\]\s*==\s*newest", t) and
              re.search(r"timeArr\[need - 1\]\s*==\s*newest", t)):
        fail("atr", "orientation must be decided by BOTH copied series endpoints as exact "
                    "timestamps, not a price epsilon")
    else:
        ok("atr", "orientation is proven from exact timestamps before any leg reads it")

    lf = read("Biotak/LabelFunctions.mqh", o)
    legs = fn_body(lf, "void TradePlanLogLegs(") or ""
    if not legs:
        fail("atr", "the [ATRLEGS] diagnostic is gone")
    elif "TrexSMALegsBatch(" not in legs:
        fail("atr", "the [ATRLEGS] dump reads its 90 legs bar by bar again (the biggest "
                    "series-read consumer in the program)")
    else:
        ok("atr", "the [ATRLEGS] diagnostic rides the same bulk engine")

    # Model: the composite window (498 bars) x ~4 series calls per bar becomes 4.
    bars = 5 + 10 + 21 + 66 + 132 + 264
    before, after = bars * 4, 4
    if before / after < 100:
        fail("atr", "the model no longer shows the 100x reduction")
    else:
        ok("atr", "model: one composite window costs %d -> %d series calls (%.0fx)"
                  % (before, after, before / after))


# ---------------------------------------------------------------------------
# 11. INTERACTION - chart work, panel work, attach/TF-switch
#
# These are the paths the user FEELS. The promises: the viewport cull is
# pixel-honest and hysteretic (so panning is not a re-render per pixel), an
# unknown viewport can never mark the whole level set "in view", a zone thinner
# than a couple of pixels is not painted, a panel move coalesces, and both the
# event path and the reinit path are measured instead of guessed at.
# ---------------------------------------------------------------------------
def check_interaction(o):
    ext = read("Biotak/ExtendedDrawingFunctions.mqh", o)
    margin = re.search(r"#define\s+P_P4_VP_MARGIN_PCT\s+([0-9.]+)", ext)
    hyster = re.search(r"#define\s+P_P4_VP_HYSTERESIS_PCT\s+([0-9.]+)", ext)
    if not margin or not hyster:
        fail("interaction", "the viewport margin/hysteresis pair must be named constants")
    else:
        m, h = float(margin.group(1)), float(hyster.group(1))
        if m >= 0.5:
            fail("interaction", "viewport margin %.2f is not tighter than the old +-50%%" % m)
        elif m <= h:
            fail("interaction", "margin %.2f must EXCEED hysteresis %.2f or a pan that "
                                "never recomputed the window can leave a level undrawn" % (m, h))
        else:
            ok("interaction", "viewport margin %.2f > hysteresis %.2f (< the old 0.50)" % (m, h))

    b = fn_body(ext, "void GetViewportBounds(") or ""
    if not re.search(r"double\s+hysteresis\s*=\s*visibleRange\s*\*\s*P_P4_VP_HYSTERESIS_PCT\s*;", b):
        fail("interaction", "GetViewportBounds must keep its cached window until the view really moved")
    else:
        ok("interaction", "a pan pixel no longer re-derives the cull window")
    if re.search(r"fallbackRange\s*=\s*g_highestHigh\s*-\s*g_lowestLow", b):
        fail("interaction", "the unknown-viewport fallback is the FULL historical range again "
                            "(that marks every level in view and builds the whole set)")
    elif "P_P4_FALLBACK_RANGE_PCT" not in b:
        fail("interaction", "the unknown-viewport fallback must be bounded around price")
    else:
        ok("interaction", "an unknown viewport can no longer populate the whole level set")

    pipe = read(PIPELINE, o)
    z = fn_body(pipe, "void RenderZones(") or ""
    if not re.search(r"p4PxPerPrice\s*>\s*0\.0\s*&&\s*\(\s*zones\[i\]\.renderTop\s*-\s*zones\[i\]\.renderBottom\s*\)\s*\*\s*p4PxPerPrice\s*<\s*P_P4_MIN_ZONE_PX", z):
        fail("interaction", "RenderZones must skip full-width fills thinner than P_P4_MIN_ZONE_PX")
    else:
        ok("interaction", "sub-pixel zone fills are not painted")

    # P-UI-75b: the coalescer moved OUT of the mouse handler and into the batch
    # owner both entries call (`PnlDragStep`) - and it is no longer a hard 30 Hz
    # rate but the drag's own MEASURED window, so a weak machine converges to the
    # frame rate it can hold while a fast one keeps the card glued to the cursor.
    # The batch pays for exactly ONE frame (`DragFrameRedraw`, which also counts
    # for the tick throttle so the tick cannot repaint the same picture again).
    pnl = read("Biotak/BiotakPanels.mqh", o)
    mv = fn_body(pnl, "void PnlHandleMouseMove(") or ""
    step = fn_body(pnl, "void PnlDragStep(") or ""
    poll = fn_body(pnl, "void PnlDragPoll(") or ""
    if not re.search(r"PnlDragStep\(\s*mx\s*,\s*my\s*\)", mv):
        fail("interaction", "the panel move drag must enter through its ONE batch owner")
    elif not re.search(r"now\s*-\s*s_PnlMoveTick\s*<\s*\(uint\)s_PnlMoveFrameMs", step):
        fail("interaction", "the panel move drag must coalesce its coordinate batch "
                            "through the ADAPTIVE window, not a hard rate")
    elif not re.search(r"PnlMoveBy\([^;]*\);[\s\S]{0,900}?DragFrameRedraw\(\);", step):
        fail("interaction", "the panel move must pay for ONE frame per applied batch, "
                            "not repaint per mouse tick or behind the cursor")
    elif not re.search(r"s_PnlMoveFrameMs\s*\*\s*3\s*\+\s*cost\)\s*/\s*4", step):
        fail("interaction", "the drag's frame window must converge on the MEASURED batch cost")
    elif "PnlDragStep(g_LastUIX, g_LastUIY)" not in poll:
        fail("interaction", "the polled shadow must step through the same batch owner")
    else:
        ok("interaction", "a panel move coalesces through one adaptive batch owner, "
                          "and each batch pays for one frame")

    missing = []
    for entry in ("Biotak Trigger TH3.mq4", "Biotak Trigger TH3 Lite.mq4"):
        src = read(entry, o)
        for fn in ("void OnChartEvent(", "int OnInit(", "void OnDeinit("):
            body = fn_body(src, fn) or ""
            # a real call at statement position — a commented-out one must not count
            if not re.search(r"^\s*P4ReportSlow\(", body, re.MULTILINE):
                missing.append("%s %s" % (os.path.basename(entry), fn.strip()))
    if missing:
        fail("interaction", "unmeasured paths (overruns stay guesses): " + ", ".join(missing))
    else:
        ok("interaction", "chart-event and reinit overruns are measured in both entries")


# ---------------------------------------------------------------------------
# 13. STAGING - a post-wipe rebuild lands one family per frame, never ~900
#     objects in one frame
#
# P-PERF-06: attach / TF switch / topology toggle used to materialise ~900
# chart objects synchronously (the multi-second freeze). The promises: the
# stage state has one owner, every wipe restarts the sequence, staging frames
# are pending work that always enter and never skip, the geometry signature
# seals only a complete render, the labels block is the last stage, the HTF
# history bulk waits for stage 0, the 250 ms timer pumps a tick-less chart,
# the panel move enumerates UI types instead of the whole chart, and the drag
# paths repaint through the throttle instead of raw.
# ---------------------------------------------------------------------------
def check_staging(o):
    g = read(GLOBALS, o)
    for const in ("BUILD_STAGE_LINES", "BUILD_STAGE_ZONES", "BUILD_STAGE_LABELS",
                  "BUILD_STAGE_BLOCK"):
        if const not in g:
            fail("staging", "the stage constant %s must live with the state owner" % const)
            return
    if "static int g_buildStage = 0;" not in g:
        fail("staging", "g_buildStage must live in GlobalVariables.mqh (HTFCandles includes it later)")
    else:
        ok("staging", "the rebuild stage has one owner in GlobalVariables.mqh")

    ev = read(EVENTS, o)
    b = fn_body(ev, "void RedrawAllObjects(") or ""
    if "g_buildStage = BUILD_STAGE_LINES;" not in b:
        fail("staging", "every wipe must restart the staged rebuild (stage LINES)")
    else:
        ok("staging", "a wipe restarts the rebuild at LINES")
    if not re.search(r"bool\s+hasPendingWork\s*=\s*\([^;]*\|\|\s*g_buildStage\s*!=\s*0", b):
        fail("staging", "staging frames must count as pending work (hasPendingWork)")
    else:
        ok("staging", "staging frames are pending work")
    if "g_redrawTHLevelsNeeded || g_buildStage != 0" not in b:
        fail("staging", "staging frames must enter the levels block (the stage flag carries liveness)")
    else:
        ok("staging", "staging frames always enter the levels block")
    if "g_initialized && g_buildStage == 0" not in b:
        fail("staging", "staging frames must never take the canSkipByState idle exit")
    else:
        ok("staging", "staging frames never skip")
    if "if(g_buildStage != 0) geometryChanged = true;" not in b:
        fail("staging", "staging frames must always build their family (geometryChanged)")
    else:
        ok("staging", "every staging frame builds its family")
    # P-PERF-25: the seal grew a second half (the frame core, so a
    # visibility-only frame can skip the render and still seal), so the check
    # asserts the GUARD plus both halves instead of one literal line.
    guard = b.find("if(g_buildStage == 0)")
    if "s_lastFrameSig = frameSig;" not in b or guard < 0:
        fail("staging", "a staged frame must not seal the geometry signature")
    elif "s_lastFrameSig = frameSig;" not in b[guard:guard + 200] or "s_lastFrameCore = frameCore;" not in b[guard:guard + 200]:
        fail("staging", "the geometry signature seal escaped its stage guard, or seals only half of itself")
    else:
        ok("staging", "the signature seals only a complete render")
    if "g_buildStage = BUILD_STAGE_ZONES;" not in b or \
       "g_buildStage = BUILD_STAGE_LABELS;" not in b or \
       "g_buildStage = BUILD_STAGE_BLOCK;" not in b:
        fail("staging", "the LINES -> ZONES -> LABELS -> BLOCK advance must be intact")
    else:
        ok("staging", "the stage advance covers all four families")
    if "g_buildStage == 0 || g_buildStage == BUILD_STAGE_BLOCK" not in b:
        fail("staging", "the labels block must be deferred to the BLOCK stage")
    else:
        ok("staging", "the labels block is the last rebuild stage")
    if "g_buildStage = 0;\n        s_lastFrameSig = frameSig;" not in b:
        fail("staging", "the BLOCK stage must seal the signature when the labels land")
    else:
        ok("staging", "the BLOCK stage seals the render")

    pipe = read(PIPELINE, o)
    ex = fn_body(pipe, "SPipelineResult ExecutePipeline(") or ""
    if "const int buildStage" not in ex:
        fail("staging", "ExecutePipeline must take the build stage (one family per frame)")
    elif "buildStage == BUILD_STAGE_LINES" not in ex or \
         "buildStage == BUILD_STAGE_ZONES" not in ex or \
         "buildStage == BUILD_STAGE_LABELS" not in ex:
        fail("staging", "ExecutePipeline must dispatch LINES / ZONES / LABELS separately")
    else:
        ok("staging", "the pipeline renders one family per stage")
    rtl = fn_body(pipe, "void RenderTriggerLines(") or ""
    if "const bool makeLines" not in rtl or "const bool makeLabels" not in rtl:
        fail("staging", "RenderTriggerLines must take makeLines/makeLabels (lines and labels stage apart)")
    elif "if(makeLines)" not in rtl or "if(makeLabels" not in rtl:
        fail("staging", "RenderTriggerLines must honour makeLines/makeLabels")
    else:
        ok("staging", "lines and pip labels stage apart")

    htf = read(HTF, o)
    htfb = fn_body(htf, "void HTFEnsureDrawn()") or ""
    if "if(g_buildStage != 0) return;" not in htfb:
        fail("staging", "the HTF history bulk must wait for stage 0 (the forming candle already ticks)")
    else:
        ok("staging", "the HTF history bulk waits out the rebuild")

    # P-PERF-35 — this block used to require "g_buildStage != 0" to appear IN
    # OnTimer, i.e. it asserted that the TIMER carried its own copy of the rebuild
    # condition. It did, and that copy is precisely what had to go: the timer also
    # had to know whether a frame was OWED (P-PERF-31), and a condition duplicated
    # across two owners drifts - which is how "advance the staging" and "run the
    # owed frame" would have disagreed. The invariant is now "the owner pumps, the
    # timer only OWES": OnTimer calls CoopPump() and never runs a frame itself,
    # while the pump alone carries both conditions. Keeping the old assertion would
    # have frozen the duplication in place.
    ev = read("Biotak/EventHandlers.mqh", o)
    pump = fn_body(ev, "void CoopPump()") or ""
    for entry in ("Biotak Trigger TH3.mq4", "Biotak Trigger TH3 Lite.mq4"):
        src = read(entry, o)
        body = fn_body(src, "void OnTimer()") or ""
        if "CoopPump()" not in body:
            fail("staging", "%s OnTimer must pump through the coop owner (tick-less charts)" % os.path.basename(entry))
        elif "RedrawAllObjects(" in body:
            fail("staging", "%s OnTimer runs a frame itself - two owners of the rebuild" % os.path.basename(entry))
        else:
            ok("staging", "%s OnTimer pumps through the one owner" % os.path.basename(entry))
    if "g_buildStage != 0" not in pump or "RedrawAllObjects(false)" not in pump:
        fail("staging", "CoopPump must advance a staging rebuild (it is owed while in flight)")
    elif "g_heavyFramePending" not in pump:
        fail("staging", "CoopPump must also drain an OWED frame, not only a staging rebuild")
    elif "g_initialized" not in pump:
        fail("staging", "CoopPump must still retry drawing before the first init")
    else:
        ok("staging", "the coop pump owns the staging rebuild and the owed frame together")

    # P-PERF-34 - a frame body must not be executable INLINE in a chart event, and
    # the deferral must not turn a live drag into a lag.
    if "g_inChartEvent" not in ev:
        fail("staging", "the frame body must know it is inside a chart event")
    elif "if(force_redraw && g_inChartEvent && !g_customPriceLineDragging)" not in ev:
        fail("staging", "a forced frame inside an event must be DEFERRED (and the live drag exempt)")
    elif "ScheduleHeavyFrame(\"chart-event\")" not in ev:
        fail("staging", "a deferred event frame must be SCHEDULED, not silently dropped")
    elif "g_buildStage != 0 || g_heavyFramePending" not in ev:
        fail("staging", "an owed frame must count as pending work (the gate must not skip it)")
    elif "&& !g_heavyFramePending" not in ev:
        fail("staging", "the state-skip gate must not swallow an owed frame")
    elif "if(g_heavyFramePending)      minWait = 0;" not in ev:
        fail("staging", "an owed frame must not wait out a housekeeping gate")
    else:
        ok("staging", "a forced frame inside a chart event is scheduled, never executed")

    for entry in ("Biotak Trigger TH3.mq4", "Biotak Trigger TH3 Lite.mq4"):
        src = read(entry, o)
        cb = fn_body(src, "void OnChartEvent(const int id,") or ""
        if "g_inChartEvent = true;" not in cb or "g_inChartEvent = false;" not in cb:
            fail("staging", "%s OnChartEvent must scope the deferral window" % os.path.basename(entry))
        else:
            ok("staging", "%s OnChartEvent scopes the deferral window" % os.path.basename(entry))

    pnl = read("Biotak/BiotakPanels.mqh", o)
    mv = fn_body(pnl, "void PnlMoveBy(") or ""
    if "ObjectsTotal(0, otype, -1)" not in mv:
        fail("staging", "PnlMoveBy must enumerate UI object types, not the whole chart")
    elif "ObjectsTotal(0, -1, -1)" in mv:
        fail("staging", "PnlMoveBy still scans every chart object per move tick")
    else:
        ok("staging", "a panel move touches UI-type objects only")

    # P-PERF-24 — this block used to require BOTH dispatcher repaints to be
    # throttled. That encoded P-PERF-06's fix (a second raw repaint doubled every
    # heavy pass) but it also froze the bug: a THROTTLED tail is silently DROPPED
    # when the user's press lands inside the 100 ms window, and the tick frame
    # that follows cannot paint it either (by then nothing is pending), so the
    # switch the user just pressed changes nothing until the market ticks. The
    # two repaint sites therefore have two different jobs:
    #   * inside s_UIDragLive  -> coalescing a DRAG stream -> must stay throttled
    #   * the tail             -> the FINAL delivery of ONE user action -> forced
    # Forcing is safe here for exactly one reason, and the block below proves it:
    # the dispatcher is only reachable from the UI modules, never from a tick.
    kit = read("Biotak/BiotakKit.mqh", o)
    if re.search(r"(?<!Throttled)ChartRedraw\(\);", kit):
        fail("staging", "ApplyRefreshFlags must repaint through an owner, never a bare ChartRedraw()")
    else:
        ok("staging", "no bare ChartRedraw in the refresh dispatcher")
    drag = fn_body(kit, "void ApplyRefreshFlags(const int flags)") or ""
    if not re.search(r"if\(s_UIDragLive\)[\s\S]{0,900}?ThrottledChartRedraw\(\);", drag):
        fail("staging", "the drag-coalescing repaint must stay throttled (a drag would repaint raw at ~33/s)")
    else:
        ok("staging", "the drag-coalescing repaint stays throttled")
    if drag.count("RepaintForDiscreteAction();") != 1:
        fail("staging", "the dispatcher tail must settle through exactly ONE discrete-action repaint (P-PERF-24)")
    else:
        ok("staging", "the dispatcher tail settles through the discrete-action owner")
    helper = fn_body(read("Biotak/UtilityFunctions.mqh", o), "void RepaintForDiscreteAction()") or ""
    if "ThrottledChartRedraw(true)" not in helper:
        fail("staging", "RepaintForDiscreteAction must FORCE the repaint, or a discrete switch's feedback is dropped")
    else:
        ok("staging", "the discrete-action owner forces the paint")
    for entry in ("Biotak/EventHandlers.mqh", "Biotak Trigger TH3.mq4", "Biotak Trigger TH3 Lite.mq4"):
        ui_src = read(entry, o)
        if "ApplyRefreshFlags(" in ui_src or "RefreshDisplay(" in ui_src:
            fail("staging", "%s calls the refresh dispatcher: a FORCED repaint reachable from a tick would hammer the terminal" % os.path.basename(entry))
            return
    ok("staging", "the forced-repaint dispatcher is UI-only (no tick can reach it)")
    live = fn_body(pnl, "void PalUpdateLive()") or ""
    if re.search(r"(?<!Throttled)ChartRedraw\(\);", live):
        fail("staging", "PalUpdateLive must repaint through the throttle (30 Hz mixer ticks)")
    elif "ThrottledChartRedraw();" not in live:
        fail("staging", "PalUpdateLive lost its repaint")
    else:
        ok("staging", "the palette mixer repaints through the throttle")

    # Model: four family frames instead of one ~900-object frame. The promise
    # is per-frame, not total: no single frame may carry more than ~40% of a
    # full build (lines 288 + zones 289 + pip labels 288 + label block ~100).
    fams = {"lines": 288, "zones": 289, "labels": 288, "block": 100}
    total = sum(fams.values())
    worst = max(fams.values())
    if worst / total > 0.4:
        fail("staging", "a stage carries %.0f%% of the build - split it further" % (100.0 * worst / total))
    else:
        ok("staging", "model: worst stage %d of %d objects (%.0f%%) instead of one %d-object frame"
                      % (worst, total, 100.0 * worst / total, total))


# ---------------------------------------------------------------------------
# NEGATIVE CONTROL - every check must be able to fail
# ---------------------------------------------------------------------------
def selftest():
    global FAILURES
    base = {}
    for rel in (VIS, OBJCACHE, PIPELINE, EVENTS, HTF, GLOBALS, "Biotak/LabelFunctions.mqh",
                "Biotak/AlertFunctions.mqh", "Biotak/ATRCalculations.mqh",
                "Biotak/DynamicTradingDayDetector.mqh", "Biotak/BasePriceManager.mqh",
                "Biotak/BiotakKit.mqh", "Biotak/UtilityFunctions.mqh",
                "Biotak/ExtendedDrawingFunctions.mqh",
                "Biotak/BiotakPanels.mqh", "Biotak Trigger TH3.mq4",
                "Biotak Trigger TH3 Lite.mq4"):
        base[rel] = read(rel)

    faults = [
        ("visibility", VIS, "bool ApplyTfMaskGuarded(const string name, const long mask)\n{",
         "bool ApplyTfMaskGuarded2(const string name, const long mask)\n{"),
        ("visibility", PIPELINE, "      ApplyTfMaskGuarded(name, timeframes);",
         "      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, timeframes);"),
        ("visibility", "Biotak/LabelFunctions.mqh", "    CacheForgetTfMasks(uniquePrefix);", ""),
        ("generation", EVENTS, "    MarkDrawGeneration();   // P-PERF-02: the chart no longer holds this render", ""),
        ("signature", EVENTS, "if(mustRender && g_buildStage != BUILD_STAGE_BLOCK && !visOnly)", "if(true)"),
        ("signature", EVENTS, "if(g_buildStage == 0) { s_lastFrameSig = frameSig; s_lastFrameCore = frameCore; g_renderAllNeeded = false; }",
         "s_lastFrameSig = frameSig; s_lastFrameCore = frameCore;"),
        ("signature", EVENTS, "                           (g_renderAllNeeded && !visOnly));",
         "                           (false));"),
        ("signature", EVENTS, "s_lastFrameCore = frameCore; g_renderAllNeeded = false; }",
         "s_lastFrameCore = frameCore; }"),
        ("signature", EVENTS, "if(g_lastRedrawDidWork) {", "if(true) {"),
        ("teardown", EVENTS, "        for(int n = 0; n < ArraySize(s_tfNs); n++)",
         "        for(int n = 0; n < ObjectsTotal(0, -1, -1); n++)"),
        ("htf", HTF, "   if(!formNewBar && g_HTFFormWriteMs != 0 && (formNow - g_HTFFormWriteMs) < HTF_FORM_MS)",
         "   if(false)"),
        ("boundary", EVENTS, "    bool boundaryCandidate = (onBoundaryMinute && boundaryBlock != s_lastBoundaryBlock);",
         "    bool boundaryCandidate = onBoundaryMinute;"),
        ("series", "Biotak/DynamicTradingDayDetector.mqh",
         "    if(DetectFetchBarTimes(timeframe, want, times, got))",
         "    if(false)"),
        ("series", "Biotak/BasePriceManager.mqh",
         "    int copied = CopyTime(Symbol(), PERIOD_M1, blockStart, blockEnd - 1, blockTimes);",
         "    int copied = 0;"),
        ("alerts", "Biotak/AlertFunctions.mqh",
         "        bool reached = g_alertLevels[i].above ? (currentPrice >= level)",
         "        if(ObjectFind(0, g_alertLevels[i].name) < 0) continue; bool reached = g_alertLevels[i].above ? (currentPrice >= level)"),
        # P-PERF-38f: the seed follows the assertion - the sweep is ungated the
        # moment it stops asking the migration stamp (the old generation gate is
        # gone, so a seed anchored on it would be a stale seed).
        ("clear", "Biotak/LabelFunctions.mqh",
         "    if(!LegacyNameSchemeMigrated())",
         "    if(true)"),
        ("warmup", "Biotak/ATRCalculations.mqh",
         "    g_atrWarmupIdx = 0;\n    WarmupATRStep();   // first one now — the visible labels must not wait",
         "    for(int i = 0; i < ArraySize(g_atrWarmupQueue); i++) GetATRForTimeframe(g_atrWarmupQueue[i]);"),
        ("interaction", "Biotak/ExtendedDrawingFunctions.mqh",
         "#define P_P4_VP_HYSTERESIS_PCT 0.20",
         "#define P_P4_VP_HYSTERESIS_PCT 0.40"),          # margin can no longer cover it
        ("interaction", "Biotak/ExtendedDrawingFunctions.mqh",
         "        double hysteresis = visibleRange * P_P4_VP_HYSTERESIS_PCT;",
         "        double hysteresis = point;"),
        ("interaction", "Biotak/ExtendedDrawingFunctions.mqh",
         "    double fallbackRange = MathMax(anchor * P_P4_FALLBACK_RANGE_PCT, point * 1000.0);",
         "    double fallbackRange = g_highestHigh - g_lowestLow;"),
        ("interaction", PIPELINE, "        if(p4PxPerPrice > 0.0 &&", "        if(false &&"),
        ("interaction", "Biotak/BiotakPanels.mqh",
         "   if(s_PnlMoveTick != 0 && now - s_PnlMoveTick < (uint)s_PnlMoveFrameMs) return;",
         "   if(s_PnlMoveTick != 0 && now - s_PnlMoveTick < 0) return;"),
        ("interaction", "Biotak/BiotakPanels.mqh",
         "   DragFrameRedraw();    // the drag's own frame, once per applied batch",
         "   ;   // seed: the batch no longer pays for its frame"),
        ("interaction", "Biotak Trigger TH3.mq4", "    P4ReportSlow(\"OnDeinit reason=\"", "    //P4ReportSlow(\"OnDeinit reason=\""),
        ("atr", "Biotak/ATRCalculations.mqh",
         "    TrexSMALegsBatch(tf, periods, results);",
         "    for(int i = 0; i < 6; i++) { if(nb > periods[i] + 1) results[i] = TrexSMALeg(tf, periods[i], 1); }"),
        ("atr", "Biotak/ATRCalculations.mqh",
         "            batchOk = TrexBatchOrient(highArr, lowArr, closeArr, timeArr, need,",
         "            batchOk = true;"),
        ("atr", "Biotak/ATRCalculations.mqh",
         "    bool newestLast = (timeArr[need - 1] == newest);",
         "    bool newestLast = MathAbs(timeArr[need - 1] - (double)newest) < 0.5;"),
        ("atr", "Biotak/LabelFunctions.mqh",
         "        TrexSMALegsBatch(tf, qpers, sLegs);",
         "        // legs (removed)"),
        ("staging", EVENTS,
         "            g_buildStage = BUILD_STAGE_LINES;",
         "            g_buildStage = 0;"),
        ("staging", EVENTS,
         "bool hasPendingWork = (force_redraw || g_labelsRelayoutNeeded || g_redrawTHLevelsNeeded || historicalRefreshDue || basePriceBoundary || g_buildStage != 0 || g_heavyFramePending);",
         "bool hasPendingWork = (force_redraw || g_labelsRelayoutNeeded || g_redrawTHLevelsNeeded || historicalRefreshDue || basePriceBoundary || g_buildStage != 0);"),
        ("staging", EVENTS,
         "    if(force_redraw && g_inChartEvent && !g_customPriceLineDragging)",
         "    if(force_redraw && false)"),
        ("staging", EVENTS,
         "        if(g_heavyFramePending)      minWait = 0;",
         "        if(false)      minWait = 0;"),
        ("staging", EVENTS,
         " && (g_buildStage == 0 || g_buildStage == BUILD_STAGE_BLOCK);",
         ";"),
        ("staging", HTF,
         "   if(g_buildStage != 0) return;",
         "   if(false) return;"),
        ("staging", "Biotak Trigger TH3.mq4",
         "    CoopPump();",
         "    CoopPump_disabled();"),
        ("staging", "Biotak Trigger TH3.mq4",
         "  g_inChartEvent = true;",
         "  g_inChartEvent = false;   // seed: the deferral window never opens"),
        ("staging", "Biotak/BiotakPanels.mqh",
         "      int ttotal = ObjectsTotal(0, otype, -1);",
         "      int ttotal = ObjectsTotal(0, -1, -1);"),
        ("staging", "Biotak/BiotakKit.mqh",
         "         ThrottledChartRedraw();\n         return;",
         "         ChartRedraw();\n         return;"),
        ("staging", "Biotak/BiotakKit.mqh",
         "   RepaintForDiscreteAction();\n}",
         "   ;\n}"),
        ("staging", "Biotak/UtilityFunctions.mqh",
         "void RepaintForDiscreteAction() {\n    ThrottledChartRedraw(true);\n}",
         "void RepaintForDiscreteAction() {\n    ThrottledChartRedraw(false);\n}"),
        ("staging", "Biotak Trigger TH3.mq4",
         "    CoopPump();",
         "    CoopPump();\n    RedrawAllObjects(false);"),
        ("staging", "Biotak/BiotakPanels.mqh",
         "   // picks still land within 100 ms — imperceptible.\n   ThrottledChartRedraw();\n}",
         "   // picks still land within 100 ms — imperceptible.\n   ChartRedraw();\n}"),
        ("htf-look", HTF,
         "      if(e.lastWidth != width) ObjectSetInteger(0, name, OBJPROP_WIDTH, width);",
         "      // seed: the width is set at create and never re-asserted"),
        ("htf-geometry", HTF,
         "   SHTFCandleGeom gm = HTFCandleGeometry(ot, nt);",
         "   SHTFCandleGeom gm;\n   gm.bodyL = ot; gm.bodyR = nt;\n   gm.shadowL = gm.shadowR = ot + (datetime)((nt - ot) / 2);"),
        ("htf-geometry", HTF,
         "   if(halfShadow > bodyHalf) halfShadow = bodyHalf;",
         "   // seed: the shadow is unbounded"),
        ("htf-geometry", HTF,
         "   double iL = HTFChartIndexAt(ot);\n   double iR = HTFChartIndexAt(nt);",
         "   double iL = ot;\n   double iR = nt;"),
        ("htf-geometry", HTF,
         "   HTFRectUpsert(name, tL, p1, tR, p2, clr, 1, true, true);",
         "   ObjectCreate(0, name, OBJ_TREND, 0, tL, p1, tR, p2);"),
        ("htf-geometry", HTF,
         '   GlobalVariableDel(prefix + "GapPct");',
         "   // seed: the gap key is saved and never deleted"),
        ("htf-geometry", HTF,
         '      g_HTFShadowPct = (int)MathMax(HTF_SHADOW_PCT_MIN, MathMin(HTF_SHADOW_PCT_MAX, (int)GlobalVariableGet(prefix + "ShadowPct")));',
         '      g_HTFShadowPct = (int)GlobalVariableGet(prefix + "ShadowPct");'),
        ("htf-geometry", PANELS,
         'label="SHADOW GAP"; unit="%"; minV=0; maxV=40;',
         'label="SHADOW GAP"; unit="%"; minV=0; maxV=90;'),
    ]
    seeded = 0
    for check, rel, needle, repl in faults:
        if needle not in base[rel]:
            print("  FAIL [selftest] seed not found in %s: %r" % (rel, needle[:48]))
            sys.exit(1)
        overrides = {rel: base[rel].replace(needle, repl, 1)}
        before = list(FAILURES)
        ran = run(overrides)
        if not ran:
            # Name the seed: an uncaught fault must say WHICH mutation survived,
            # or the only way to find it is to read this list by hand.
            print("  FAIL [selftest] fault NOT caught (%s in %s): %r" % (check, rel, needle[:58]))
            sys.exit(1)
        FAILURES = before
        seeded += 1
    print("  selftest: %d seeded faults, all caught" % seeded)
    return True


def run(overrides=None):
    del FAILURES[:]
    check_visibility(overrides)
    check_generation(overrides)
    check_signature(overrides)
    check_teardown(overrides)
    check_htf(overrides)
    check_htf_look(overrides)
    check_htf_geometry(overrides)
    check_boundary(overrides)
    check_bulk_series(overrides)
    check_alerts(overrides)
    check_lazy_group(overrides)
    check_atr_bulk(overrides)
    check_interaction(overrides)
    check_staging(overrides)
    check_model()
    return list(FAILURES)


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
        sys.exit(0)
    if not QUIET:
        print("write-budget-audit (P-PERF-02)")
    bad = run()
    if bad:
        print("\n%d budget violation(s)." % len(bad))
        sys.exit(1)
    if not QUIET:
        print("\nchart write budget: clean")
    sys.exit(0)
