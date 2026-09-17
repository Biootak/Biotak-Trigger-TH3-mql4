#!/usr/bin/env python3
"""probe-budget-audit - the gate behind P-PERF-07/08/09/10.

WHY. P-PERF-02 made per-frame chart WRITES conditional, which is why the fixes
that came before it were real: an unchanged value costs no `ObjectSet*`. What it
did not make conditional is how the guard DISCOVERS whether an object is there.
Those lookups are the remaining per-frame, per-level terminal traffic, and they
are invisible in the write counts:

  1. NEGATIVE EXISTENCE (P-PERF-07)
     `SetPipelineObjectTimeframesIfExists` probes the chart with `ObjectFind`
     whenever the main cache does not know the name. A CULLED level is never
     created, so it can never enter the main cache: its line, its pip label and
     its seven zone sub-objects (base/_Top/_Bottom/_B_*) were probed on EVERY
     heavy frame, forever. At inpMaxLevels=144 that is up to ~2.6k terminal
     probes per frame, each scanning a chart holding thousands of objects, i.e.
     the cost grew as O(culled levels x chart objects) - the quadratic term the
     live log shows as 1.8-4.2 s frames. The fix is a negative table consulted
     BEFORE the probe, marked on the miss, and dropped whenever the chart and
     the cache are wiped together (CacheClear) or a fresh instance attaches
     (OnInitHandler), because those are the only moments an object we own can
     appear without going through the cache.

  2. ONE BACKGROUND READ (P-PERF-08)
     `BlendWithBackground` is the opacity emulator every HTF body/wick/border
     goes through, and it read CHART_COLOR_BACKGROUND from the terminal BEFORE
     consulting its own cache - so the cache could never save a syscall. A full
     HTF draw blends 3-4 colours per bar (up to ~240 bars). The read now lives
     in ONE function that a draw pass calls once.

  3. COMBO SUMMARY GUARD (P-PERF-09)
     The step-mode label's breakdown is a chain of component-step computations
     plus a DoubleToString per component. Nothing about it is time-dependent,
     yet OnTimer rebuilt it 4x/s and RefreshUIPerTick at tick rate.

  4. INIT PHASE LEDGER (P-PERF-10)
     The live log reports OnInit at 3.2-4.1 s with every tick-ledger phase at
     zero, i.e. the seconds are in code nothing brackets. The init path must
     report its own phases, or the next session is back to guessing.

  5. SELF-DESCRIBING HISTORY + ONE DAY FRAME (P-PERF-11)
     With the phases in place the log named the owner: base=3797 ms inside one
     OnInit of 3828 ms. That phase guessed a file's format from its contents
     ("any entry with hour >= 22:00 is yesterday's data") - which a full
     00:xx..23:xx session always satisfies - so every init deleted its own
     valid file and rebuilt the day from M30 data. The file now stamps its own
     format on line 1 and the caller compares versions. The same investigation
     found the day-window scan comparing SERVER bar times against a GMT cutoff,
     which is what kept writing block labels past the current GMT block.
     These two are one bug seen from two sides, so they are checked together.

  6. DELETE PATHS (P-PERF-13/14/15)
     With the loop gone the log named the next three costs: `OnDeinit reason=4
     took 297ms` on every timeframe switch, `chart event id=1 [indicator=0
     ui=485..578]` on cursor movement, and a steady `ui=46/47` on every move.
     Reading those paths found the same shape three times - work that asks the
     terminal about things that are not there, on a chart that carries thousands
     of our own objects: CleanupSurplusObjects walks seven name families every
     full frame for six misses each (and a zone family asks seven names per
     index), CreateZone probed its two legacy sub-objects BEFORE the
     "nothing changed" early return, and DeleteHTFCandles walked every
     rectangle and every trend on the chart to find the few of its own. That
     last one runs on OnDeinit, i.e. every timeframe switch. Two of the three
     are fixed here (absent-table consult + bulk prefix delete, the documented
     ObjectsDeleteAll(chart, prefix) form), and the third is the P-PERF-15
     ledgers so the next cycle is aimed by measurement again.

  7. THE UI HOT PATH (P-PERF-16/17)
     The pair budget line said the UI half owned the cursor-move stall but not
     which part of it. `CircItemAt`/`ToolsItemAt`/`CircPointOnMenu` each ask
     `CircLayout`/`SubPlaceItem` per item, those read the chart size straight
     from the terminal, and `CircLayout` also ran a full-ring sin/cos fit - so
     one hit test cost 16-40 terminal reads and O(RING^2) trigonometry, on every
     move. And `CircTipHide` DELETED the tooltip and force-repainted instead of
     parking it, while visibility was probed with ObjectFind per move. None of
     that shows up in a write count (delete+create cancels; ChartRedraw is not a
     write). Checks: one cached metrics owner, a memoised fit, both drag-rate
     panel readers on that same owner, a parked tip, and state-not-probe
     visibility.

  8. THE STAGED REBUILD'S FOUR-FOLD MATH (P-PERF-18)
     P-PERF-06 splits a post-wipe rebuild into four frames to cap the per-frame
     syscalls - but every frame called ExecutePipeline again, so
     CalculateLevels -> Classify -> BuildZonesAndLines re-ran with identical
     inputs. The gate requires a geometry cache consulted BEFORE the math, keyed
     on every input the three stages read, remembering its result, dropping on
     empty - and PROVING the structure-interval table (the key used to assert
     ArraySize(g_cachedIntervals), which is the constant 5).

  9. THE BASE-PRICE STATE BEHIND A GLOBAL-VARIABLE LOCK (P-PERF-19/20)
     Seen in the newest log: `baseInit breakdown: file=0ms migrate=312ms
     rebuild=0ms cleanup=47ms (fileStamp=5 entries=48)`. A STAMPED file that
     needs no migration still spent 312 ms in the load window; and the seven
     legacy access macros (`g_basePriceCached`, `g_historyCount`, ...) expand to
     `GetSymbolStateIndex()`, which is not a lookup but a MUTEX built out of
     terminal global variables (~9 GV syscalls per call), used in ~115 places
     including loop CONDITIONS. `GetCachedSymbolStateIndex()` already existed,
     was maintained, and had NO CALLERS. Checks: all seven macros read through
     the cached resolver, that resolver is guarded on symbol + live range and
     counts its misses, no per-entry accessor locks, no loop condition resolves
     the macro, the load window names dedup/fmt/save/restore, and the history
     file is written only when its content would actually differ.

Usage:  python tools/probe-budget-audit.py [--quiet] [--selftest] [--sites]
Exit 0 = the probe budget holds, 1 = an unguarded per-level probe is back.
"""

import glob
import os
import re
import sys

QUIET = "--quiet" in sys.argv or "--selftest" in sys.argv
SITES = "--sites" in sys.argv
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OBJCACHE = "Biotak/ObjectCache.mqh"
BASEPRICE = "Biotak/BasePriceManager.mqh"
VISIBILITY = "Biotak/VisibilityManager.mqh"
PIPELINE = "Biotak/LevelPipeline.mqh"
ZONEFACTORY = "Biotak/ZoneFactory.mqh"
PANELS = "Biotak/BiotakPanels.mqh"
MENU = "Biotak/BiotakMenu.mqh"
RUNTIME = "Biotak/RuntimeSettings.mqh"
EVENTS = "Biotak/EventHandlers.mqh"
HTF = "Biotak/HTFCandles.mqh"
COMBO = "Biotak/ComboEngine.mqh"
GLOBALS = "Biotak/GlobalVariables.mqh"
HISTMGR = "Biotak/BasePriceHistoryManager.mqh"
BASEMGR = "Biotak/BasePriceManager.mqh"
KIT = "Biotak/BiotakKit.mqh"
UTIL = "Biotak/UtilityFunctions.mqh"
DYNDET = "Biotak/DynamicTradingDayDetector.mqh"
EXTDRAW = "Biotak/ExtendedDrawingFunctions.mqh"
OBJFUN = "Biotak/ObjectFunctions.mqh"
PERFOPT = "Biotak/PerformanceOptimizations.mqh"
LABEL = "Biotak/LabelFunctions.mqh"
BASEKNOT = "Biotak/BaseKnotTool.mqh"
FULL = "Biotak Trigger TH3.mq4"
LITE = "Biotak Trigger TH3 Lite.mq4"

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


def strip_comments(src):
    """Full-line comments only - the audits' own commentary trips naive greps."""
    out = []
    for line in src.splitlines():
        s = line.strip()
        if s.startswith("//") or s.startswith("*") or s.startswith("/*"):
            continue
        out.append(line)
    return "\n".join(out)


def fn_body(src, signature):
    """Body of a function, by brace balance from its definition."""
    i = src.find(signature)
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


def fn_code(src, signature):
    """A function body WITHOUT its commentary.

    P-PERF-47/P-PERF-02: the prose in this tree quotes the very calls it
    explains - CacheClear's own note names `MarkDrawGeneration()`, the ladder
    sweep's names `doomed[nd++]` - so a substring gate answered by a comment is
    a gate that stays green while the code it guards is deleted. (The negative
    controls found exactly that: four seeds patched the code away and no check
    noticed.) Every body this audit judges for a CALL must go through here.
    """
    return strip_comments(fn_body(src, signature) or "")


# ---------------------------------------------------------------------------
# 1. negative existence cache
# ---------------------------------------------------------------------------
def check_negative_cache(o):
    cache = read(OBJCACHE, o)
    pipe = strip_comments(read(PIPELINE, o))
    events = read(EVENTS, o)

    for name in ("CacheAbsentResetAll", "CacheIsAbsentKnown", "CacheMarkAbsent"):
        if ("void %s(" % name) not in cache and ("bool %s(" % name) not in cache:
            fail("negative-cache", "%s is gone from ObjectCache.mqh" % name)
            return
    ok("negative-cache", "the absent table is defined (mark / query / reset)")

    body = fn_body(pipe, "void SetPipelineObjectTimeframesIfExists(")
    if not body:
        fail("negative-cache", "SetPipelineObjectTimeframesIfExists is gone")
        return

    probe = body.find("ObjectFind(0, name)")
    query = body.find("CacheIsAbsentKnown(name)")
    mark = body.find("CacheMarkAbsent(name)")
    if query < 0:
        fail("negative-cache", "the ObjectFind fallback runs without consulting the absent table")
    elif probe >= 0 and query > probe:
        fail("negative-cache", "the absent table is consulted AFTER the probe (useless)")
    else:
        ok("negative-cache", "the absent table is consulted before the ObjectFind fallback")
    if mark < 0:
        fail("negative-cache", "a proven-absent name is never recorded, so every frame re-probes")
    else:
        ok("negative-cache", "a proven-absent name is recorded")

    # A mark is only believable inside the very render that proved it, so every
    # droppable path either bumps the generation (CacheClear, which wipes the
    # chart and the cache together) or frees the stamps (a fresh instance, which
    # re-attaches onto a chart the previous one drew on).
    body = fn_code(cache, "void CacheClear()")
    if "MarkDrawGeneration();" not in body:
        fail("negative-cache", "CacheClear does not bump the generation: a mark outlives the chart it was proved on")
    else:
        ok("negative-cache", "CacheClear bumps the generation, so the marks die with the wipe")

    body = fn_body(events, "int OnInitHandler()")
    if not body or "CacheAbsentResetAll()" not in body:
        fail("negative-cache", "OnInitHandler does not drop the marks (re-attach reuses the chart)")
    else:
        ok("negative-cache", "OnInitHandler drops the marks")

    for fn, label in (("bool CacheIsAbsentKnown(const string name)", "CacheIsAbsentKnown"),
                      ("void CacheMarkAbsent(const string name)", "CacheMarkAbsent")):
        body = fn_body(cache, fn)
        if not body or "g_drawGeneration" not in body:
            fail("negative-cache", "%s is not scoped to the draw generation: a stale mark is believed" % label)
            return
    ok("negative-cache", "marks are generation-scoped (a stale stamp reads as a free slot)")

    reset = fn_body(cache, "void CacheAbsentResetAll()")
    if not reset or "g_absentStamp[i] = 0" not in reset:
        fail("negative-cache", "CacheAbsentResetAll does not free the stamps")
    elif "g_absentName[" in reset:
        fail("negative-cache", "CacheAbsentResetAll touches the name strings: invalidation costs O(table) string work")
    else:
        ok("negative-cache", "invalidation touches only the int stamps (no string work)")

    if SITES:
        m = re.search(r"void CacheMarkAbsent\(const string name\) \{", cache)
        if m:
            print("      CacheMarkAbsent @ ObjectCache.mqh:%d"
                  % (cache[:m.start()].count("\n") + 1))


# ---------------------------------------------------------------------------
# 2. one background read per HTF draw
# ---------------------------------------------------------------------------
def check_blend_background(o):
    htf = strip_comments(read(HTF, o))

    blend = fn_body(htf, "color BlendWithBackground(")
    if not blend:
        fail("blend", "BlendWithBackground is gone")
        return
    if "ChartGetInteger" in blend:
        fail("blend", "BlendWithBackground reads the chart background per call again")
    else:
        ok("blend", "BlendWithBackground performs no terminal read")

    refresh = fn_body(htf, "void HTFRefreshBlendBackground()")
    if not refresh or "CHART_COLOR_BACKGROUND" not in refresh:
        fail("blend", "no single owner reads CHART_COLOR_BACKGROUND")
        return
    if len(re.findall(r"CHART_COLOR_BACKGROUND", htf)) != 1:
        fail("blend", "CHART_COLOR_BACKGROUND is read from more than one place")
    else:
        ok("blend", "one owner reads CHART_COLOR_BACKGROUND")

    if "HTFRefreshBlendBackground()" not in htf.split("void HTFRefreshBlendBackground()", 1)[1].split("color BlendWithBackground(")[0]:
        pass  # definition site is excluded by construction; call sites checked below
    draws = len(re.findall(r"^\s*HTFRefreshBlendBackground\(\);", htf, re.M))
    # one definition-less call per draw entry point (forming candle, history draw, init seed)
    if draws < 3:
        fail("blend", "a draw pass does not refresh the cached background (%d call sites)" % draws)
    else:
        ok("blend", "each HTF draw pass refreshes it once (%d call sites)" % draws)


# ---------------------------------------------------------------------------
# 3. combo summary change guard
# ---------------------------------------------------------------------------
def check_combo_guard(o):
    combo = strip_comments(read(COMBO, o))
    body = fn_body(combo, "void RefreshComboLabelExtraInfo()")
    if not body:
        fail("combo-guard", "RefreshComboLabelExtraInfo is gone")
        return
    # The guard must be a real early return keyed on remembered inputs, not
    # just a function that happens to contain a `return`.
    guard = re.search(r"if\s*\((?=[^)]*s_last)[^)]*\)\s*\{?\s*return;", body, re.S)
    if not guard:
        fail("combo-guard", "the summary is rebuilt unconditionally again (4x/s + tick rate)")
    else:
        ok("combo-guard", "the summary is rebuilt only when an input moved")
    if "ComboSpecSignature(" not in combo:
        fail("combo-guard", "no spec signature: a spec change would be missed")
    else:
        ok("combo-guard", "the guard covers the combo spec, not just the base price")


# ---------------------------------------------------------------------------
# 4. init phase ledger
# ---------------------------------------------------------------------------
def check_init_ledger(o):
    globals_src = read(GLOBALS, o)
    events = strip_comments(read(EVENTS, o))

    for g in ("g_pInitMsSettings", "g_pInitMsHistory", "g_pInitMsBase", "g_pInitMsAtr"):
        if g not in globals_src:
            fail("init-ledger", "%s is gone: init phases are unattributed again" % g)
            return
    ok("init-ledger", "the four init phases have ledger slots")

    body = fn_body(events, "int OnInitHandler()")
    if not body:
        fail("init-ledger", "OnInitHandler is gone")
        return
    for g in ("g_pInitMsSettings", "g_pInitMsHistory", "g_pInitMsBase", "g_pInitMsAtr"):
        if g not in body:
            fail("init-ledger", "OnInitHandler never stamps %s" % g)
            return
    ok("init-ledger", "OnInitHandler stamps all four phases")

    if "string P4InitLedgerTag(" not in events:
        fail("init-ledger", "no report helper: the numbers never reach the log")
        return
    for entry in (FULL, LITE):
        src = strip_comments(read(entry, o))
        if "P4InitLedgerTag(" not in src:
            fail("init-ledger", "%s reports OnInit without the phase tag" % entry)
            return
    ok("init-ledger", "both entries report the phases")


# ---------------------------------------------------------------------------
# 5. self-describing history files + a consistent day frame (P-PERF-11)
# ---------------------------------------------------------------------------
def check_history_format(o):
    hist = strip_comments(read(HISTMGR, o))
    base = strip_comments(read(BASEMGR, o))
    dyn = strip_comments(read(DYNDET, o))

    # The retired guess is the whole bug: a full session (00:xx .. 23:xx) always
    # contains a 22:xx block, so "any entry >= 22:00 = legacy" deleted a valid
    # file on EVERY init and rebuilt the day from M30 data.
    if re.search(r"hour\s*>=\s*22", base):
        fail("history-format", "the '>=22:00 = yesterday' guess is back: it deletes a valid file on every init")
    else:
        ok("history-format", "the >=22:00 heuristic is retired")
    if "g_loadedHistoryFormat != HISTORY_FORMAT_VERSION" not in base:
        fail("history-format", "the migration decision is not a version compare")
    else:
        ok("history-format", "the migration decision compares the file's own stamp")

    if 'HISTORY_STAMP_PREFIX "#FMT="' not in hist:
        fail("history-format", "the stamp prefix owner is gone")
        return
    ok("history-format", "one owner defines the stamp prefix")

    save = fn_body(hist, "bool SaveBasePriceHistory(")
    if not save or "HistoryFileStampLine()" not in save:
        fail("history-format", "SaveBasePriceHistory writes no stamp: every fresh file reads as legacy")
    else:
        ok("history-format", "SaveBasePriceHistory stamps line 1")

    load = fn_body(hist, "int LoadBasePriceHistory(")
    if not load:
        fail("history-format", "LoadBasePriceHistory is gone")
        return
    if "StringGetCharacter(line, 0) == '#'" not in load:
        fail("history-format", "the loader reads the stamp as a data entry")
    elif "g_loadedHistoryFormat =" not in load or "HISTORY_STAMP_PREFIX" not in load:
        fail("history-format", "the loader neither strips nor reports the stamp")
    else:
        ok("history-format", "the loader strips the stamp and reports its version")

    append = fn_body(hist, "bool AppendBasePriceHistoryEntry(")
    if not append or "HistoryFileStampedVersion(filePath)" not in append:
        fail("history-format", "the append path can create an unstamped file: the next load rebuilds the day")
    else:
        ok("history-format", "the append path stamps a file it is the first to write")

    # The parse itself, on the two shapes the real files take. A stamped file
    # must report the current version; a legacy line (or a bad stamp) must
    # report 0, i.e. "migrate me once".
    def stamped_version(first_line):
        s = first_line.strip()
        if not s.startswith("#FMT="):
            return 0
        tail = s[len("#FMT="):]
        if "|" in tail:
            tail = tail.split("|", 1)[0]
        return int(tail) if tail.isdigit() else 0

    model = (("#FMT=5|GMT", 5), ("#FMT=4|GMT", 4), ("#FMT=|GMT", 0),
             ("00:28|4421.32|4422.98 (+0.00)|OK D=0.038%|91.99|91.99|91.96", 0))
    for line, want in model:
        got = stamped_version(line)
        if got != want:
            fail("history-format", "the stamp parse reads %r as %d, expected %d" % (line, got, want))
            return
    ok("history-format", "stamped -> current, legacy -> migrate once, on every real shape")

    # Same bug, other half: the bar scan must not mix the server frame with the
    # GMT frame, and must hand the caller GMT.
    body = fn_body(dyn, "datetime FindCurrentSessionStart(int timeframe = PERIOD_M1)")
    if not body:
        fail("day-frame", "FindCurrentSessionStart is gone")
        return
    if "serverNow = TimeCurrent()" not in body:
        fail("day-frame", "the bar scan is not anchored to the server frame bar times live in")
    elif "twentyFourHoursAgo = serverNow" not in body:
        fail("day-frame", "the 24h window compares server bar times against a GMT cutoff")
    elif "DtddServerToGMT(" not in body:
        fail("day-frame", "the session start is handed back in the server frame (caller converts it again)")
    else:
        ok("day-frame", "the bar scan is server-frame and the result is converted to GMT")


# ---------------------------------------------------------------------------
# 6. delete paths: never ask the terminal about a name already proved missing,
#    never scan the whole chart, never probe a zone that did not change (P-PERF-13/14)
# ---------------------------------------------------------------------------
def check_delete_paths(o):
    cache = strip_comments(read(OBJCACHE, o))
    zonef = strip_comments(read(ZONEFACTORY, o))
    htf = strip_comments(read(HTF, o))
    events = strip_comments(read(EVENTS, o))
    panels = strip_comments(read(PANELS, o))

    body = fn_body(cache, "bool DeleteIndicatorObjectManaged(const string name, const bool verifyChartObject = false)")
    if not body:
        fail("delete-path", "DeleteIndicatorObjectManaged is gone")
        return
    absent = body.find("CacheIsAbsentKnown(name)")
    probe = body.find("ObjectFind(0, name)")
    mark = body.find("CacheMarkAbsent(name)")
    if absent < 0:
        fail("delete-path", "a delete probes a name the absent table already proved missing")
    elif probe >= 0 and absent > probe:
        fail("delete-path", "the absent table is consulted AFTER the probe (useless)")
    else:
        ok("delete-path", "a delete skips the terminal call for a name proved absent")
    if mark < 0:
        fail("delete-path", "the miss is not recorded, so the same name is probed every frame")
    else:
        ok("delete-path", "a proved miss is recorded (the surplus walk becomes O(1))")

    # CreateZone: the legacy sub-object probes must sit AFTER the unchanged-skip,
    # otherwise a settled chart pays one ObjectFind per zone per frame.
    body = fn_body(zonef, "SZoneCreationResult CreateZone(")
    if not body:
        fail("delete-path", "CreateZone is gone")
        return
    early = body.find("return result; // Skip everything!")
    legacy = body.find('DeleteIndicatorObjectManaged(request.name + "_Top")')
    if early < 0:
        fail("delete-path", "the unchanged-zone early return is gone: every frame rewrites every zone")
    elif legacy < 0:
        fail("delete-path", "the legacy sub-object migration is gone (stale _Top/_Bottom would survive)")
    elif legacy < early:
        fail("delete-path", "the legacy probes run BEFORE the unchanged-skip: a probe per zone per frame")
    else:
        ok("delete-path", "an unchanged zone performs no delete probe at all")

    # DeleteHTFCandles: bulk prefix delete, not two full-chart walks.
    body = fn_body(htf, "void DeleteHTFCandles()")
    if not body:
        fail("delete-path", "DeleteHTFCandles is gone")
        return
    code = strip_comments(body)
    if "ObjectsTotal" in code or "ObjectName(" in code:
        fail("delete-path", "DeleteHTFCandles walks every rectangle/trend on the chart again")
    elif "ObjectsDeleteAll(0, g_HTFPrefix)" not in code:
        fail("delete-path", "DeleteHTFCandles does not use the bulk prefix delete")
    else:
        ok("delete-path", "DeleteHTFCandles is one bulk prefix delete")
    if re.search(r"if\(g_HTFDrawnCount\s*<=\s*0\s*&&\s*!HTFAnyBoxesExist\(\)\)\s*return;", code) is None:
        fail("delete-path", "no O(1) guard: the HTF-steady-state delete still fires every pass")
    else:
        ok("delete-path", "the HTF steady state costs no terminal call (bookkeeping + name probe)")
    if htf.find("bool HTFAnyBoxesExist()\n{") > htf.find("void DeleteHTFCandles()\n{"):
        fail("delete-path", "HTFAnyBoxesExist is defined after its caller (MQL4: warning 46, no prototype)")
    else:
        ok("delete-path", "the probe is defined above its caller (no forward declaration needed)")

    # P-PERF-15: the two remaining unnamed hot spots have their own ledger.
    body = fn_body(read(FULL, o), "void OnDeinit(const int reason)")
    if not body:
        fail("phase-ledger", "OnDeinit is gone from the entry")
    elif not all(("%s = GetTickCount()" % k) in body
                 for k in ("p15Pnl", "p15Menu", "p15Htf", "p15Save", "p15Cleanup", "p15Handler")):
        fail("phase-ledger", "OnDeinit still reports one number: a ~300 ms teardown stays unattributed")
    elif "OnDeinit breakdown" not in body:
        fail("phase-ledger", "the OnDeinit phases are timed but never reported")
    else:
        ok("phase-ledger", "OnDeinit names its six phases when it blows the budget")

    body = fn_body(panels, "void HandleUIChartEvent(")
    if not body:
        fail("phase-ledger", "HandleUIChartEvent is gone from the panel layer")
    else:
        move = body.find("CHARTEVENT_MOUSE_MOVE")
        if move < 0:
            fail("phase-ledger", "the panel layer no longer handles cursor moves (that is where the log says they cost 47-578 ms)")
        elif not all(("%s = GetTickCount()" % k) in body for k in ("p15ring", "p15panel", "p15hold")):
            fail("phase-ledger", "the cursor-move path is not split into its three owners")
        elif "mouse move breakdown" not in body or "P_P4_MOVE_WARN_MS" not in body:
            fail("phase-ledger", "the move phases are timed but never reported")
        else:
            ok("phase-ledger", "cursor moves name ring/panel/hold when they blow the budget")
    if "P_P4_MOVE_WARN_MS" not in events:
        fail("phase-ledger", "no move budget constant is defined next to the event budgets")
    else:
        ok("phase-ledger", "the move budget sits with the other P-PERF-04 budgets")


# ---------------------------------------------------------------------------
# 7. the cursor-move hot path: cached layout metrics, a parked tooltip, no
#    terminal read or full repaint per item (P-PERF-16/17)
# ---------------------------------------------------------------------------
def check_ui_hot_path(o):
    menu = strip_comments(read(MENU, o))
    panels = strip_comments(read(PANELS, o))

    metrics = fn_body(menu, "void CircUIMetrics(int &cw, int &ch)")
    if not metrics:
        fail("ui-hot-path", "no cached chart-metrics reader: every hit-test item re-reads the size")
        return
    if "CHART_WIDTH_IN_PIXELS" not in metrics or "CHART_HEIGHT_IN_PIXELS" not in metrics:
        fail("ui-hot-path", "the metrics reader does not read the chart rect")
    else:
        ok("ui-hot-path", "one reader owns the chart rect")
    if "CircUIMetricsInvalidate" not in menu:
        fail("ui-hot-path", "the metrics cache has no invalidation entry point")
    else:
        ok("ui-hot-path", "the cache has an invalidation entry point")

    # The per-item layout must not touch the terminal at all.
    layout = fn_body(menu, "void CircLayout(const int i, int &x, int &y)")
    if not layout or "CircUIMetrics(cw, ch)" not in layout:
        fail("ui-hot-path", "CircLayout does not use the cached metrics")
    elif "ChartGetInteger" in layout:
        fail("ui-hot-path", "CircLayout reads the chart size per item again (RING_COUNT reads per move)")
    else:
        ok("ui-hot-path", "CircLayout is terminal-free (one hit test = zero reads per item)")
    rect = fn_body(menu, "void SubChartRect(int &cw, int &ch, int &ox, int &oy)")
    if not rect or "CircUIMetrics(cw, ch)" not in rect or "ChartGetInteger" in (rect or ""):
        fail("ui-hot-path", "SubChartRect (per sub-menu tile) still asks the terminal for the chart size")
    else:
        ok("ui-hot-path", "SubChartRect is terminal-free too")

    # The two drag-rate readers (a strip follows the cursor, a dragged panel
    # clamps on every move event) must use the same owner - the P-PERF-16 rule
    # is "one reader owns the chart rect", not "the menu's reader owns it".
    for fname, why in (("void PnlClampSpot(const int item, const int dx, const int dy, int &ndx, int &ndy)",
                        "a dragged panel re-reads the chart rect per move event"),
                       ("void BkStripFollow()",
                        "the strip re-reads the chart rect on every follow frame")):
        who = fname.split("(")[0].replace("void ", "")
        fb = fn_body(panels, fname)
        if not fb:
            fail("ui-hot-path", "%s is gone" % who)
        elif "ChartGetInteger" in fb:
            fail("ui-hot-path", "%s still asks the terminal for the size: %s" % (who, why))
        elif "CircUIMetrics(cw, ch)" not in fb:
            fail("ui-hot-path", "%s does not use the shared metrics owner: %s" % (who, why))
        else:
            ok("ui-hot-path", "%s shares the metrics owner" % who)

    fit = fn_body(menu, "double CircFitRadius(const int cw, const int ch, const int ox, const int oy)")
    if not fit or "cw == s_fitCw" not in fit or "s_fitR" not in fit:
        fail("ui-hot-path", "the ring radius fit is recomputed per item again (O(N^2) trigonometry per move)")
    else:
        ok("ui-hot-path", "the radius fit is memoised on (cw,ch,ox,oy)")

    # The tooltip must be parked, not deleted, and its visibility must be state.
    hide = fn_body(menu, "void CircTipHide()")
    if not hide:
        fail("ui-hot-path", "CircTipHide is gone")
    elif "ObjectDelete" in hide or "ChartRedraw()" in hide:
        fail("ui-hot-path", "hiding the tip deletes objects and/or forces a full repaint again")
    elif "CircTipPark()" not in hide:
        fail("ui-hot-path", "the tip is not parked: the next hover re-creates it")
    else:
        ok("ui-hot-path", "hiding the tip parks it (no object churn, no forced repaint)")
    park = fn_body(menu, "void CircTipPark()")
    if not park or "CIRC_HIDE_POS" not in park:
        fail("ui-hot-path", "the tip park does not use the CIRC_HIDE_POS idiom")
    else:
        ok("ui-hot-path", "the tip parks with the same idiom as the Tools fan")
    if "ObjectFind(0, CircTipBg())" in fn_body(menu, "void CircTipOnMove(const int mx, const int my, const bool leftDown)") or \
       "ObjectFind(0, CircTipBg())" in fn_body(menu, "void CircTipShow(const int feat, const int ax, const int ay)"):
        fail("ui-hot-path", "tip visibility is probed on the chart again (a terminal call per move)")
    else:
        ok("ui-hot-path", "tip visibility is the state variable, not an ObjectFind per move")
    show = fn_body(menu, "void CircTipShow(const int feat, const int ax, const int ay)")
    if show and "ChartRedraw()" in show:
        fail("ui-hot-path", "showing the tip forces a full repaint (the property writes already dirtied it)")
    else:
        ok("ui-hot-path", "showing the tip forces no repaint")

    # Invalidation must be wired to the two events that can change the size.
    if "CircUIMetricsInvalidate();" not in fn_body(panels, "void HandleUIChartEvent("):
        fail("ui-hot-path", "a chart-change (resize/DPI) does not invalidate the metrics")
    else:
        ok("ui-hot-path", "the chart-change event invalidates the metrics")
    timer = fn_body(read(FULL, o), "void OnTimer()")
    if not timer or "CircUIMetricsInvalidate();" not in timer:
        fail("ui-hot-path", "no timer safety refresh: a missed resize would strand the cache")
    else:
        ok("ui-hot-path", "the 250 ms timer carries the safety refresh")


# ---------------------------------------------------------------------------
# 8. the staged rebuild computes the geometry ONCE, not once per family
#    (P-PERF-18)
# ---------------------------------------------------------------------------
def check_geometry_cache(o):
    pipe = strip_comments(read(PIPELINE, o))
    body = fn_body(pipe, "SPipelineResult ExecutePipeline(")
    if not body:
        fail("geometry-cache", "ExecutePipeline is gone")
        return
    if "PipelineGeometryKey(" not in body or "geoKey == s_geoKey" not in body:
        fail("geometry-cache", "the four staged frames recompute Calculate/Classify/Build again (4x the math per switch)")
    else:
        ok("geometry-cache", "the pipeline consults a geometry cache before the math")
    hit = body.find("geoKey == s_geoKey")
    calc = body.find("CalculateLevels(")
    if calc < 0:
        fail("geometry-cache", "no level calculation at all?")
    elif hit < 0 or calc < hit:
        fail("geometry-cache", "the math runs before the cache check (the cache can never save anything)")
    else:
        ok("geometry-cache", "the math lives on the miss side of the cache")
    if "s_geoValid = true;" not in body:
        fail("geometry-cache", "a built geometry is never remembered")
    else:
        ok("geometry-cache", "a built geometry is remembered for the other families")
    if "s_geoValid = false;   // never serve" not in body:
        fail("geometry-cache", "an empty result can leave a stale geometry cached")
    else:
        ok("geometry-cache", "an empty result drops the cache")

    key = fn_body(pipe, "string PipelineGeometryKey(")
    if not key:
        fail("geometry-cache", "no key builder: the cache has nothing to compare")
        return
    must = (("vpTop", "a scroll would serve geometry culled for the old viewport"),
            ("vpBottom", "a scroll would serve geometry culled for the old viewport"),
            ("centerPrice", "a moved base price would serve the old levels"),
            ("maxLevelsAbove", "a level-count edit would serve the old range"),
            ("g_customPriceLineDragging", "the custom-price drag re-culls while it moves"))
    for need, why in must:
        if need not in key:
            fail("geometry-cache", "the key ignores %s: %s" % (need, why))
            return
    ok("geometry-cache", "the key covers viewport, price, limits and live appearance")

    # P-PERF-23b — the term this check used to REQUIRE, and why the requirement
    # was wrong. An earlier cycle put g_linesVisible in the key with the stated
    # reason "a line toggle mid-rebuild would paint pre-toggle colours". Nothing
    # in CalculateLevels/Classify/Build reads it: the switch is a paint-time MASK
    # (RenderTriggerLines' lineTf, ObjectFunctions) and the live value is read
    # there on every frame. So the term only threw the built lists away and
    # recomputed byte-identical ones on every L press / SHOW LINES row - the
    # "recompute half" of "toggling my levels is slow". A signature may only
    # name inputs its own stages read.
    key_all = fn_body(pipe, "string PipelineGeometryKey(")
    if "g_linesVisible" in key_all:
        fail("geometry-cache", "the geometry key keys on g_linesVisible: no pipeline stage reads it, so a line toggle recomputes identical geometry")
        return
    ok("geometry-cache", "the geometry key names only inputs the pipeline stages read")

    # ClassifyLevels() -> GetHighestStructureLevel() reads g_cachedIntervals. That
    # table is a pure function of the validated base multiplier, but the key must
    # PROVE it rather than assert a constant: the old term was
    # ArraySize(g_cachedIntervals) == 5, which can never change.
    if "ArraySize(g_cachedIntervals)" in key:
        fail("geometry-cache", "the key asserts ArraySize(g_cachedIntervals) (always 5) instead of the interval VALUES ClassifyLevels reads")
        return
    if "g_cachedIntervals[" not in key:
        fail("geometry-cache", "the structure-interval table is not in the key: a future derivation change would serve stale structure levels")
        return
    ok("geometry-cache", "the structure-interval table is proved, not asserted")


# ---------------------------------------------------------------------------
# 9. the per-symbol base-price state is NOT behind a global-variable lock on the
#    read path (P-PERF-19), its sub-phases are named (P-PERF-19b), and the
#    history file is only written when its content would change (P-PERF-20)
# ---------------------------------------------------------------------------
def check_base_price_state(o):
    src = strip_comments(read(BASEPRICE, o))

    # (a) Which resolver do the seven legacy access macros bind to?
    legacy = ("g_basePriceCached", "g_lastProcessedBlockTimestamp", "g_referenceM1Power",
              "g_historyCount", "g_lastHistoryDay", "g_lastHistoryYear", "g_systemInitialized")
    for name in legacy:
        m = re.search(r"#define\s+%s\s+\(([^\n]*)\)" % name, src)
        if not m:
            fail("base-price-state", "the %s access macro is gone" % name)
            return
        target = m.group(1)
        if "GetCachedSymbolStateIndex()" not in target:
            fail("base-price-state", "%s expands to %s - the UNCACHED resolver, i.e. a global-variable lock per read" % (name, target.strip()))
            return
        if "GetSymbolStateIndex()" in target:
            fail("base-price-state", "%s still reaches the locking resolver (GetCachedSymbolStateIndex must wrap it)" % name)
            return
    ok("base-price-state", "all seven legacy access macros read through the cached resolver")

    # (b) The cached resolver must be a cache: symbol guard + live-range guard + miss count.
    cached = fn_body(src, "int GetCachedSymbolStateIndex()")
    if not cached:
        fail("base-price-state", "GetCachedSymbolStateIndex is gone")
        return
    for need, why in (("_g_cachedStateSymbol == sym", "a symbol change would serve the other symbol's state"),
                      ("_g_cachedStateIdx < g_symbolStateCount", "an evicted slot would be served"),
                      ("GetSymbolStateIndex()", "there is no miss path at all"),
                      ("g_stateResolveLockedCalls", "the locked path is not counted: the fix cannot be proven from the log")):
        if need not in cached:
            fail("base-price-state", "the cached resolver lacks %s: %s" % (need, why))
            return
    ok("base-price-state", "the cached resolver is guarded on the symbol, the live range, and counts its misses")

    # (c) The five array accessors are called INSIDE loops - they must not lock.
    for helper in ("string GetHistoryEntry(int index)", "void SetHistoryEntry(int index, string value)",
                   "void ResizeHistory(int newSize)", "void GetHistoryArray(string &output[])",
                   "void SetHistoryArray(string &inputArray[], int count)"):
        body = fn_body(src, helper)
        if not body:
            fail("base-price-state", "%s is gone" % helper.split("(")[0])
            return
        if "GetSymbolStateIndex()" in body and "GetCachedSymbolStateIndex()" not in body:
            fail("base-price-state", "%s takes the lock although it is called per entry" % helper.split("(")[0])
            return
    ok("base-price-state", "every per-entry accessor uses the cached resolver")

    # (d) No macro in a loop CONDITION: one lock per iteration is the trap.
    loop = re.search(r"for\s*\([^;]*;[^;]*<\s*g_historyCount\s*;", src)
    if loop:
        fail("base-price-state", "a loop condition still resolves g_historyCount per iteration (one lock per entry)")
        return
    ok("base-price-state", "no loop condition resolves the macro per iteration")

    # (e) P-PERF-19b: the "load" window must name its own owner. The report is a
    # multi-line Print, so read a window rather than the first line.
    at = src.find("baseInit breakdown")
    if at < 0:
        fail("base-price-state", "the baseInit breakdown line is gone")
        return
    text = src[at:at + 700]
    for need in ("load=", "dedup=", "fmt=", "save=", "restore=", "symbolStateLocked="):
        if need not in text:
            fail("base-price-state", "the breakdown line cannot name the load window (missing %s): 312 ms stays a black box" % need)
            return
    ok("base-price-state", "the load window names dedup/fmt/save/restore and reports the locked-resolver cost")

    # (f) P-PERF-20: never rewrite the history file unless the bytes would change.
    if "HistoryContentDiffers" not in src:
        fail("history-write", "no content comparison: an unchanged history file can be rewritten on every init")
        return
    save = fn_body(src, "void InitializeBasePriceSystem()")
    guard = save.find("HistoryContentDiffers(")
    writer = save.find("SaveBasePriceHistory(")
    if guard < 0 or writer < 0 or guard > writer:
        fail("history-write", "the content guard does not sit before the write")
        return
    ok("history-write", "the history file is written only when its content would differ")


# ---------------------------------------------------------------------------
# 10. FAMILY ISOLATION - one switch, one family (P-PERF-21/22)
#
# The user's report: "why do the levels keep getting deleted and drawn again, and
# why does turning Trigger on affect the STRUCTURE levels - they should not touch
# each other". Both were real and both were the same shape: a switch that owns one
# family was wired into a GLOBAL repair path.
#
#   * The trigger overlay changes the picture and nothing else. CalculateLevels
#     never reads it, BuildZonesAndLines never reads it, and the two classify
#     helpers that accept it as a parameter (GetPathForLevelOptimized,
#     GetZoneColorForLevel) never look at it - so it was in the geometry key and
#     in the TOPOLOGY signature for no reason, and a T press therefore wiped
#     every level, zone and label and rebuilt the pipeline in four staged frames.
#     It belongs in the RENDER signature (cheap re-render), never the topology
#     one, and never in the geometry key.
#   * The L switch walked the WHOLE chart (ObjectsTotal(0,-1,-1) + ObjectName +
#     ObjectGetInteger per object) to write one visibility mask per line.
#     SetAllLineObjectsVisibility() - the object-cache walk that does exactly
#     this, with this hotkey's own exclusions - already existed and had no
#     callers. Same defect class as the P-PERF-19 cache.
# ---------------------------------------------------------------------------
def check_family_isolation(o):
    events = strip_comments(read(EVENTS, o))
    pipe = strip_comments(read(PIPELINE, o))
    vis = strip_comments(read(VISIBILITY, o))

    # (a) the trigger flag must not be a topology input
    lvl = fn_body(events, "void RedrawAllObjects(bool force_redraw=false)")
    if not lvl:
        fail("family-isolation", "RedrawAllObjects is gone")
        return
    sig = lvl[lvl.find("string levelSig"):lvl.find("bool levelTopologyChanged")]
    # P-PERF-25: the render signature is now the frame CORE plus the line mask,
    # so the slice starts at the core (the mask term would only add noise here).
    frame = lvl[lvl.find("frameCore = levelSig"):lvl.find("bool geometryChanged")]
    if not sig or not frame:
        fail("family-isolation", "the two signatures are gone")
        return
    if "IsTriggerLevelsEnabled()" in sig:
        fail("family-isolation", "the trigger overlay is back in the TOPOLOGY signature: a T press deletes every level again")
        return
    if "IsTriggerLevelsEnabled()" not in frame:
        fail("family-isolation", "the trigger overlay is not in the RENDER signature: toggling it would paint nothing")
        return
    ok("family-isolation", "the trigger overlay is a render input, not a topology input")

    # (b) no trigger-toggle site may raise the force-clear flag
    offenders = []
    for rel, text in ((EVENTS, events), (MENU, strip_comments(read(MENU, o))),
                      (PANELS, strip_comments(read(PANELS, o)))):
        for m in re.finditer(r"g_triggerLevelsEnabled\s*=", text):
            window = text[m.start():m.start() + 900]
            if "g_forceClearOnNextDraw" in window:
                offenders.append(rel)
    if offenders:
        fail("family-isolation", "a trigger-toggle site still force-clears (%s): the structure levels are deleted for a zones-only change" % ", ".join(sorted(set(offenders))))
        return
    ok("family-isolation", "no trigger-toggle site force-clears the chart")

    # (c) the flag must not be a geometry input either
    key = fn_body(pipe, "string PipelineGeometryKey(")
    if not key:
        fail("family-isolation", "PipelineGeometryKey is gone")
        return
    if "triggerEnabled" in key:
        fail("family-isolation", "the geometry key still keys on triggerEnabled: a T press throws away and recomputes identical geometry")
        return
    call = re.search(r"PipelineGeometryKey\((.*?)\);", fn_body(pipe, "SPipelineResult ExecutePipeline("), re.S)
    if not call:
        fail("family-isolation", "the key builder is never called")
        return
    if "triggerEnabled" in call.group(1):
        fail("family-isolation", "ExecutePipeline still passes triggerEnabled into the key builder")
        return
    ok("family-isolation", "the geometry cache does not depend on the trigger overlay")

    # (d) the zone colours the geometry CARRIES must be in the key (P-PERF-21b)
    for need, why in (("inpShowStructure", "the structure show switch changes zone colours"),
                      ("inpStructureL5Color", "an L5 colour edit would serve the old zone colour"),
                      ("inpShowStructureL1", "an L1 show toggle changes which zones get a colour"),
                      ("inpShowMidZones", "the zones switch decides whether a zone exists"),
                      ("GetTriggerRenderColor()", "the trigger fallback colour is stored per zone")):
        if need not in key:
            fail("family-isolation", "the geometry key still misses %s: %s" % (need, why))
            return
    ok("family-isolation", "the key proves the zone colours it stores")

    # (e) the L switch must not walk the chart, and the mask write must live in
    # ONE owner every entry point calls.
    #
    # This check used to look for SetAllLineObjectsVisibility INSIDE the hotkey
    # block, and that was the bug in disguise: the mask write lived in ONE
    # CALLER, so the two panel SHOW LINES rows and the factory reset changed the
    # flag, the mirror and the persisted key and stopped there. The P-PERF-25
    # render skip then proved "nothing the renderer produces changed" and painted
    # nothing - the switch only took effect on a timeframe switch, which rebuilds
    # the chart from scratch. The invariant is the owner, not the call site.
    lk = events
    owner = fn_body(lk, "void SetLinesVisible(")
    if not owner or "SetAllLineObjectsVisibility(" not in owner:
        fail("family-isolation", "the line-visibility owner (SetLinesVisible) is gone, or it no longer writes the object mask")
        return
    at = lk.find("inpLinesToggleKey")
    if at < 0:
        fail("family-isolation", "the L hotkey is gone")
        return
    seg = lk[at:at + 1600]
    if "SetLinesVisible(" not in seg:
        fail("family-isolation", "the L switch does not use the mask owner (SetLinesVisible)")
        return
    # Every OTHER mutation of the flag must go through the owner too, or it is a
    # control that changes state without changing the chart. Only the init-time
    # restore may assign it directly (it runs before any object exists).
    stripped = lk.replace(owner, "")
    for rel, text in ((EVENTS, stripped),
                      (MENU, strip_comments(read(MENU, o))),
                      (PANELS, strip_comments(read(PANELS, o)))):
        for m in re.finditer(r"^.*g_linesVisible\s*=\s*(?!=).*$", text, re.M):
            if "RestoreBoolGlobalVar" in m.group(0):
                continue   # init-time restore, not a user switch
            fail("family-isolation", "%s writes g_linesVisible outside the mask owner, so the state changes and the chart does not: %s" % (rel, m.group(0).strip()[:70]))
            return
    ok("family-isolation", "every line-visibility entry point writes the mask through one owner")
    for banned, why in (("ObjectsTotal(0, -1, -1)", "it enumerates every object on the chart"),
                        ("ObjectName(0,", "it asks the terminal for every object's name")):
        if banned in seg:
            fail("family-isolation", "the L switch still scans the whole chart: %s" % why)
            return
    ok("family-isolation", "the L switch repairs our own cached lines instead of scanning the chart")

    # (f) the cache walk must keep the L hotkey's exclusions
    walk = fn_body(vis, "void SetAllLineObjectsVisibility(const bool visible)")
    if not walk:
        fail("family-isolation", "SetAllLineObjectsVisibility is gone")
        return
    for need, why in (("_B_Top", "the empty-box borders belong to the F switch, not L"),
                      ("_BK_", "P-BK-01: trade rays are never level lines"),
                      ("g_objectCacheSize", "it must iterate the cache, not the chart")):
        if need not in walk:
            fail("family-isolation", "the line-visibility walk lost %s: %s" % (need, why))
            return
    # P-PERF-31: the line-type proof may live in the walk itself (an OBJ_HLINE
    # literal) or in the shared classifier the walk calls — but it must exist
    # somewhere on the path, or zones/labels/HTF would flip with the lines.
    tester = fn_body(vis, "bool VisibilityIsLineObject(const string nm)")
    if "OBJ_HLINE" in walk:
        ok("family-isolation", "the line-visibility walk keeps the L switch's own exclusions")
    elif "VisibilityIsLineObject" in walk and tester and "OBJ_HLINE" in tester:
        ok("family-isolation", "the line-visibility walk keeps the L switch's own exclusions (via the shared line test)")
    else:
        fail("family-isolation", "the line-visibility walk lost OBJ_HLINE: zone/level lines are OBJ_HLINE")
        return

    # (g) P-PERF-23c: the two owners of "is this a box border?" must agree. The
    # F show path (VisibilityShowAllCached via VisibilityIsLineObject) and the
    # L walk spell the same four segments out as IsZoneBoxBorderObject().
    # They once disagreed about _B_Right, so hiding lines left
    # one edge of an empty box hidden - a box with a side missing.
    helper = fn_body(events, "bool IsZoneBoxBorderObject(const string name)")
    if not helper:
        fail("family-isolation", "IsZoneBoxBorderObject is gone while the F switch still asks it")
        return
    missing = [seg for seg in ("_B_Top", "_B_Bottom", "_B_Left", "_B_Right") if seg not in helper]
    if missing:
        fail("family-isolation", "IsZoneBoxBorderObject misses %s, which the L walk excludes: the F show branch hides a box edge as if it were a line" % ", ".join(missing))
        return
    ok("family-isolation", "both box-border owners name all four segments")

    # (h) P-PERF-41: A FAMILY SWITCH IS A MASK, NOT A DESTRUCTION.
    #
    # P-PERF-36 answered "zones off left every zone on the chart" by making the
    # CLEANUP run in the OFF state too - i.e. by deleting the family. That is
    # correct about the symptom and wrong about the fix: the OFF state then cost
    # ~7 deletes per zone and the ON state ~7 writes plus a create per zone, for
    # a switch that moves no price, which is why the report came back as "why is
    # turning the levels on/off so slow" and then "it doesn't turn on/off like
    # the F button".
    #
    # The invariant now has four parts, and each one is a way the old shape
    # could come back:
    #   1. RenderZones must HIDE the whole family when the switch is off.
    #   2. That OFF branch may not be reached only after the zone list is walked
    #      (the list is empty when the switch is off - that WAS the bug).
    #   3. No render path may delete a zone to express "not visible".
    #   4. Cleanup may still never be guarded by the flag that turns the family
    #      off, and the retired Factor path keeps its unconditional sweep.
    zones = fn_body(pipe, "void RenderZones(")
    if not zones:
        fail("family-isolation", "RenderZones is gone")
        return
    hideCall = "if(!config.zonesEnabled) { HideAllZoneFamilyObjects(); return; }"
    if hideCall not in zones:
        fail("family-isolation",
             "the zone family switch is not a hide branch: turning zones OFF "
             "either deletes the family or leaves it painted")
        return
    if zones.find("for(int i = 0; i < zoneCount; i++)") < zones.find(hideCall):
        fail("family-isolation", "the OFF branch sits AFTER the zone loop: the list is empty when zones are off, so it never runs")
        return
    trig = zones.find("if(zones[i].isTrigger && !triggerEnabled)")
    if trig < 0:
        fail("family-isolation", "the trigger-zone gate is gone from RenderZones")
        return
    # ... and the trigger overlay's own branch must still SKIP the band, not fall
    # through to the create call. (It deletes on purpose - see the note there:
    # a trigger band is indistinguishable from a structure band by name, so
    # "hide it" would force the F show path to blink it back for a frame.)
    # The window ends at the branch's OWN closing brace: a `continue;` sitting
    # after it belongs to the next statement and would keep this check green while
    # the band fell through to the create call.
    trigEnd = zones.find("}", trig)
    if trigEnd < 0 or "continue;" not in zones[trig:trigEnd]:
        fail("family-isolation", "the trigger-off branch no longer skips the band: a hidden family would be repainted")
        return
    # The mask owner itself: one cache walk, `_Zone_` family, BK excluded, and the
    # write goes through the guarded writer (an unguarded ObjectSetInteger here
    # would be the write-churn defect this project fought all cycle). It lives in
    # VisibilityManager beside every other OBJPROP_TIMEFRAMES owner, because the
    # F show path writes the same masks and the two must not drift apart.
    walk = fn_body(vis, "int HideAllZoneFamilyObjects()")
    if not walk:
        fail("family-isolation", "HideAllZoneFamilyObjects is gone from VisibilityManager: the family-off state has no owner")
        return
    for need, why in (("g_objectCacheHash", "it must be a cache walk, not an index walk over names that may not exist"),
                      ('StringFind(nm, "_Zone_") < 0', 'it must cover the whole zone family'),
                      ('StringFind(nm, "_BK_") >= 0', 'the Base/Knot layer is independent (P-BK-01)'),
                      ("ApplyTfMaskGuarded", "the mask write must stay behind the P-PERF-02 guard"),
                      ("VisibilityZoneMask", "the ONE visibility predicate the F path shares")):
        if need not in walk:
            fail("family-isolation", "HideAllZoneFamilyObjects lost %s: %s" % (need, why))
            return
    if "HideZoneFamilyLegacyScan" not in walk:
        fail("family-isolation",
             "the family walk has no cold-cache fallback: after a timeframe switch the "
             "cache is empty but the family is still on the chart, so nothing would hide it")
        return
    # P-PERF-41e: NO STATE LATCH ABOVE THE WALK. This function has exactly one
    # caller (the render's `!zonesEnabled` branch), so `zonesVisible` is CONSTANT
    # here - a guard keyed on it (plus hidden/lines/epoch, none of which move in an
    # off->on->off cycle, because the ON render writes masks through the guarded
    # writer and that by design does not bump the epoch) can never see the
    # transition. It latched the walk off after the FIRST off press, so press 1
    # hid the zones and every later press left them up: the reported "it doesn't
    # turn on/off properly". The sound guard is per OBJECT (ApplyTfMaskGuarded),
    # which compares against the mask last written for that name.
    iWalk = walk.find("for(int i = 0;")
    if iWalk < 0:
        fail("family-isolation", "HideAllZoneFamilyObjects has no cache walk")
        return
    if "return" in walk[:iWalk]:
        fail("family-isolation",
             "a state latch sits above the zone-family walk: with a constant input it "
             "cannot detect a transition, so after the first OFF press every later "
             "press leaves the family on the chart")
        return
    if "s_last" in walk:
        fail("family-isolation", "the zone-family walk keeps a state latch again instead of relying on the per-object guard")
        return
    # ... and it takes NO boolean parameter: a constant passed in as an argument
    # reads like a variable to compare against, which is how the latch above was
    # originally justified.
    if "int HideAllZoneFamilyObjects(const bool" in vis:
        fail("family-isolation", "the family-off walk takes a visibility argument again: the only caller always passes the same value")
        return
    # ... and the F show path must ASK the zone switch. This is the second half of
    # the report: F resurrected the family the Zones & Levels switch had just
    # turned off, because the show branch had no input for it.
    show = fn_body(vis, "int VisibilityShowAllCached(const bool atrShouldShow")
    if not show:
        fail("family-isolation", "VisibilityShowAllCached is gone")
        return
    if "zonesVisible" not in show or 'StringFind(nm, "_Zone_") >= 0' not in show:
        fail("family-isolation",
             "the F show path is not zone-aware again: an F press would repaint every "
             "zone rectangle as visible even when the family is switched off")
        return
    if "VisibilityZoneMask" not in show:
        fail("family-isolation", "the F show path decides the zone mask itself instead of asking the shared predicate")
        return
    ev_text = strip_comments(read(EVENTS, o))
    if "VisibilityShowAllCached(atrShouldShowF, inpShowATRTargets," not in ev_text:
        fail("family-isolation", "the F key no longer calls the show owner")
        return
    if "inpShowMidZones" not in ev_text[ev_text.find("VisibilityShowAllCached(atrShouldShowF"):][:240]:
        fail("family-isolation", "the F key does not pass the zone switch to the show owner")
        return
    cleaner = fn_body(pipe, "void CleanupSurplusPipeline(")
    if not cleaner:
        fail("family-isolation", "CleanupSurplusPipeline is gone - nothing removes stale zones")
        return
    if 'if(config.zonesEnabled)' in cleaner and '_Zone_' in cleaner:
        fail("family-isolation", "the zone cleanup is guarded by zonesEnabled again: the OFF state now belongs to the mask walk, not to a delete")
        return
    if "const int zoneCleanupFrom = maxLogicalStep + 1;" not in cleaner:
        fail("family-isolation", "the cleanup no longer walks past the newest logical step in both states")
        return
    # the same inverse guard must not survive in the retired Factor path: the
    # three sibling families beside it are already unconditional, so an `if`
    # around this one is the defect re-planted, not a style choice.
    extdraw = strip_comments(read(EXTDRAW, o))
    if 'if(inpShowMidZones) ObjectsDeleteAll(0, objectPrefix + "Factor_Zone_", -1, -1);' in extdraw:
        fail("family-isolation", "the retired Factor path still skips its zone cleanup while the zones are OFF")
        return
    if 'ObjectsDeleteAll(0, objectPrefix + "Factor_Zone_", -1, -1);' not in extdraw:
        fail("family-isolation", "the retired Factor path lost its zone cleanup entirely")
        return
    ok("family-isolation", "the zone/level switches mask the family; only cleanup destroys")

    # (h2) P-PERF-41: ONE RING ITEM = ONE SWITCH, AND NO CROSS-EFFECTS.
    #
    # The "Zones & Levels" item sits on a card with two rows (MID ZONES and SHOW
    # LINES) that have their own controls. A version of this item that moved BOTH
    # layers was written and reverted, because a press then switched ON a layer
    # the user had switched OFF (zones on + lines off -> press -> lines back on).
    # A control that silently changes another control's state is a behaviour bug,
    # and it is what this check exists to prevent from being re-introduced: the
    # light, the badge, the tooltip and the click must all speak about
    # `g_showMidZones` and about nothing else.
    menu = strip_comments(read(MENU, o))
    if "ZonesAndLevelsMasterOn" in menu:
        fail("family-isolation",
             "a ring 'master' over both visibility layers is back: it can switch on a "
             "layer the user switched off")
        return
    for fn, sig, want in (("the light", "bool CircFeatureOn(const int i)",
                           "if(i == CIR_ZONES)           return g_showMidZones;"),
                          ("the badge", "string CircBadgeText(const int i)",
                           'if(i == CIR_ZONES)           return g_showMidZones ? "On" : "";'),
                          ("the tooltip", "string CircTooltipStatus(const int i)",
                           'if(i == CIR_ZONES)             return g_showMidZones ? "ON" : "OFF";')):
        body = fn_body(menu, sig)
        if not body or want not in body:
            fail("family-isolation", "%s for the Zones & Levels item no longer reads exactly the zone switch" % fn)
            return
    click = fn_body(menu, "int HandleButtonClick(const string clickedObject)")
    if not click:
        fail("family-isolation", "HandleButtonClick is gone")
        return
    iZ = click.find("else if(feat == CIR_ZONES)")
    iNext = click.find("else if(feat ==", iZ + 1) if iZ >= 0 else -1
    if iZ < 0 or iNext < 0:
        fail("family-isolation", "the CIR_ZONES ring branch is gone (or is no longer an else-if chain)")
        return
    branch = click[iZ:iNext]
    if "g_showMidZones = !g_showMidZones;" not in branch:
        fail("family-isolation", "the Zones & Levels press no longer flips the zone switch")
        return
    for bad, why in (("SetLinesVisible", "the SHOW LINES row and the L key own the line switch"),
                     ("g_linesVisible", "the line state is not this item's to move"),
                     ("g_showLines", "the line state is not this item's to move"),
                     ("SetAllLineObjectsVisibility", "a mask belongs to the switch that owns it"),
                     ("DeleteManagedZoneObjects", "a visibility switch must not destroy objects"),
                     ("ObjectsDeleteAll", "a visibility switch must not destroy objects")):
        if bad in branch:
            fail("family-isolation", "the Zones & Levels press touches %s: %s" % (bad, why))
            return
    ok("family-isolation", "the ring item moves its own switch and only its own")

    # (i) P-PERF-35b: the pump's priority is CHEAP-FIRST and it cannot be the job
    # ID order. HEAVY_FRAME is id 1, so iterating ids ran the rebuild first, let it
    # claim the slice and left the sweep jobs owed - which the live log named:
    # "coop job=obj-cleanup waited=265ms ran=0ms". A rebuild that starves the
    # housekeeping it depends on is the defect, so the order is asserted, not the
    # enum values.
    ev2 = strip_comments(read(EVENTS, o))
    pump = fn_body(ev2, "void CoopPump()")
    if not pump:
        fail("family-isolation", "CoopPump disappeared while the timer still owes jobs")
        return
    if "int coopOrder[COOP_JOB_COUNT - 1]" not in pump:
        fail("family-isolation", "the pump iterates job ids: the heavy frame (id 1) starves the sweeps")
        return
    if "int job = coopOrder[oi];" not in pump:
        fail("family-isolation", "the pump declares a priority order and then does not use it")
        return
    tail = pump.split("int coopOrder", 1)[1].split("}", 1)[0]
    if tail.index("COOP_JOB_HEAVY_FRAME") < tail.index("COOP_JOB_STATUS_TEXT"):
        fail("family-isolation", "the heavy frame is scheduled BEFORE the sweep jobs")
        return
    ok("family-isolation", "the pump runs the cheap sweeps first and the rebuild on the leftover slice")


# ---------------------------------------------------------------------------
# 11. TOGGLE PATH (P-PERF-23/24/26) — turning a level family on or off must be
#     "flip the mask and paint", never "delete the chart and rebuild it", and
#     the switch's own cost must be a named line in the log.
# ---------------------------------------------------------------------------
def check_toggle_path(o):
    events = strip_comments(read(EVENTS, o))
    pipe = strip_comments(read(PIPELINE, o))
    kit = strip_comments(read(KIT, o))
    util = strip_comments(read(UTIL, o))
    panels = strip_comments(read(PANELS, o))
    full = strip_comments(read(FULL, o))
    lite = strip_comments(read(LITE, o))

    lvl = fn_body(events, "void RedrawAllObjects(bool force_redraw=false)")
    if not lvl:
        fail("toggle-path", "RedrawAllObjects is gone")
        return
    # The slices are exact: topology ends where the appearance block begins, so
    # a term cannot hide in the overlap.
    iTop, iLook, iEnd = (lvl.find("string levelSig"), lvl.find("string levelLookSig"),
                         lvl.find("bool levelTopologyChanged"))
    topo = lvl[iTop:iLook] if 0 <= iTop <= iLook else ""
    look = lvl[iLook:iEnd] if 0 <= iLook <= iEnd else ""
    frame = lvl[lvl.find("frameCore = levelSig"):lvl.find("bool geometryChanged")]
    if not topo or not frame or not look:
        fail("toggle-path", "the topology / appearance / render signatures are gone")
        return

    # (a) a visibility or appearance switch must not reach the WIPE
    for need, why in (("inpShowMidZones", "the MID ZONES switch only decides whether zones are painted"),
                      ("inpMidZoneStyle", "a zone style edit changes no level prices"),
                      ("inpMidZoneTransparency", "a transparency edit changes no level prices"),
                      ("inpMidZoneHeightPercent", "a height edit changes no level prices")):
        if need in topo:
            fail("toggle-path", "%s is back in the TOPOLOGY signature: %s, yet it deletes and rebuilds every level" % (need, why))
            return
    ok("toggle-path", "no visibility/appearance input can trigger ClearAllLevels")

    # (b) ... they must still be in the RENDER signature, or the edit paints nothing
    for need in ("levelLookSig", "inpShowMidZones", "inpMidZoneStyle",
                 "inpMidZoneTransparency", "inpMidZoneHeightPercent"):
        if need not in look:
            fail("toggle-path", "the appearance signature lost %s: the edit would compute geometry and never paint it" % need)
            return
    if "levelLookSig" not in frame:
        fail("toggle-path", "the appearance signature is not part of frameSig: an appearance edit would never repaint")
        return
    ok("toggle-path", "appearance inputs live in the render signature")

    # (c) the geometry key may not carry the line-visibility MASK
    if "g_linesVisible" in fn_body(pipe, "string PipelineGeometryKey("):
        fail("toggle-path", "the L / SHOW LINES toggle still throws the geometry away")
        return
    ok("toggle-path", "the line mask is a paint decision, not a geometry input")

    # (d) ONE owner for "a discrete action paints now"
    helper = fn_body(util, "void RepaintForDiscreteAction()")
    if not helper or "ThrottledChartRedraw(true)" not in helper:
        fail("toggle-path", "RepaintForDiscreteAction does not force the repaint: the throttled call drops the feedback inside its 100 ms window")
        return
    for rel, text in ((KIT, kit),):
        body = fn_body(text, "void ApplyRefreshFlags(const int flags)")
        if not body or "RepaintForDiscreteAction()" not in body:
            fail("toggle-path", "the refresh dispatcher still ends in the throttled repaint (%s)" % rel)
            return
    # Anchor on each switch's OWN report site, not on the hotkey dispatch: the
    # keyboard handler keeps both switches in one block, so a window big enough
    # for the F block also swallows the L block and can never see the loss.
    lsite = events.find('P4ReportSlow("lines toggle (L)')
    fsite = events.find('P4ReportSlow("hide-all toggle (F)')
    if lsite < 0 or fsite < 0:
        fail("toggle-path", "a visibility switch reports nothing")
        return
    if fsite > lsite:
        fail("toggle-path", "the two switch reports are out of order (the slices would overlap)")
        return
    # F owns the span between its own report and the L switch's report; L owns
    # the short span after its report. Exact spans, so neither can hide in the
    # other's window.
    if "RepaintForDiscreteAction()" not in events[fsite:lsite]:
        fail("toggle-path", "the F switch does not use the discrete repaint owner")
        return
    if "RepaintForDiscreteAction()" not in events[lsite:lsite + 900]:
        fail("toggle-path", "the L switch still ends in the throttled repaint")
        return
    ok("toggle-path", "every discrete visibility switch paints through one owner")

    # (d2) P-PERF-25: the mask term stays OUT of the frame core, and a pure
    #      visibility flip therefore provably skips the whole-family render.
    iCore, iSig = lvl.find("frameCore = levelSig"), lvl.find("frameSig = frameCore")
    core = lvl[iCore:iSig] if 0 <= iCore < iSig else ""
    if not core:
        fail("toggle-path", "the frame core is gone: a visibility flip can no longer be told apart from a real change")
        return
    if "g_linesVisible" in core:
        fail("toggle-path", "the line mask is back inside the frame CORE: every visibility flip counts as picture change again")
        return
    if "g_linesVisible" not in lvl[iSig:iSig + 200]:
        fail("toggle-path", "the line mask left the render signature: the switch would paint nothing")
        return
    for need, why in (("bool visOnly = (!shouldClearLevels && g_buildStage == 0 &&",
                       "a wipe or a staging frame must never take the skip"),
                      ("else if(visOnly)", "a skipped render must still seal the signature")):
        if need not in lvl:
            fail("toggle-path", "%s (%s)" % (need, why))
            return
    # The skip must be honoured by the RENDER CONDITION itself. Asserting the
    # bare text "!visOnly)" is not enough: the P-PERF-30 escalation term
    # `(g_renderAllNeeded && !visOnly)` contains it too, so dropping the veto
    # from the render gate would leave the check green while every mask flip
    # re-rendered the whole family.
    mrender = re.search(r"if\s*\(\s*mustRender\s*&&[^\n{]*", lvl)
    if not mrender or "!visOnly" not in mrender.group(0):
        fail("toggle-path", "the render condition must honour the mask skip (mustRender && ... && !visOnly)")
        return
    ok("toggle-path", "a line-visibility flip is a mask write, not a render")

    # (d3) P-PERF-32: structure switches (card 11) recolour, never recompute.
    # The level SET is switch-invariant (the switches only choose zone
    # colours), so the toggle must not raise a render flag — that would miss
    # the geometry key and rebuild the whole family inside the click. All six
    # rows go through the recolour owner; the walk reads the same live colour
    # inputs ClassifyLevels stores.
    at11 = panels.find("STRUCTURE sub-card")
    if at11 < 0:
        fail("toggle-path", "card 11 (STRUCTURE) is gone")
        return
    end11 = panels.find("break;", at11)
    if end11 < 0:
        fail("toggle-path", "card 11 never ends")
        return
    seg11 = panels[at11:end11]
    for idx in range(6):
        if "SetStructureVisible(%d," % idx not in seg11:
            fail("toggle-path", "card 11 row %d bypasses the structure recolour owner" % (idx + 1))
            return
    if "REFRESH_BUFFERS" in seg11 or "REFRESH_ALL" in seg11 or "REFRESH_RECALC" in seg11:
        fail("toggle-path", "card 11 still raises a render flag: the toggle recomputes instead of recolouring")
        return
    walk32 = fn_body(pipe, "int StructureRecolourWalk(")
    if not walk32:
        fail("toggle-path", "StructureRecolourWalk is gone")
        return
    for need, why in (("GetZoneColorForLevel", "the walk must store what ClassifyLevels stores"),
                      ("GetTriggerRenderColor", "the clrNONE fallback is part of the stored colour"),
                      ("GetZoneRenderColor", "the chart holds the blended colour, not the raw one"),
                      ("CacheGetColor", "the walk must compare from the cache, never probe the chart"),
                      ("g_objectCacheSize", "the walk must iterate the cache, not the chart")):
        if need not in walk32:
            fail("toggle-path", "the recolour walk lost %s: %s" % (need, why))
            return
    # P-UI-66: the settle step (persist + recolour walk + forced repaint) moved
    # into `StructureSwitchSettle`, because a GROUP press (the dual row's ALL cell)
    # writes five switches in one event: each write must land, but the walk and the
    # repaint belong to the PASS. So the owner must still settle through that one
    # function, and it must DEFER while a group press holds the batch - five walks
    # and five forced repaints for one press is exactly what P-PERF-32 removed.
    owner32 = fn_body(events, "void SetStructureVisible(const int idx, const bool visible)")
    if not owner32 or "StructureSwitchSettle(" not in owner32:
        fail("toggle-path", "the structure owner no longer routes to the recolour settle")
        return
    if "s_structSwitchBatch" not in owner32:
        fail("toggle-path",
             "the structure owner stopped deferring to the group batch: five switches in "
             "one event cost five recolour walks and five forced repaints")
        return
    settle32 = fn_body(events, "void StructureSwitchSettle(")
    if not settle32 or "StructureRecolourWalk()" not in settle32 \
       or "RepaintForDiscreteAction()" not in settle32:
        fail("toggle-path", "the structure owner no longer recolours and repaints")
        return
    closer32 = fn_body(events, "void StructureSwitchBatchEnd()")
    if not closer32 or "StructureSwitchSettle(" not in closer32:
        fail("toggle-path",
             "the group batch never settles: a group press would leave the chart on the "
             "pre-press colours until an unrelated repaint")
        return
    ok("toggle-path", "structure switches recolour through one owner, never recompute")

    # (e) the switch's own cost is measurable AND the ledger is readable
    name = fn_body(events, "string P4EventName(const int id)")
    if not name:
        fail("toggle-path", "P4EventName is gone: the log is back to raw ids nobody can read")
        return
    for need, why in (("CHARTEVENT_OBJECT_CLICK", "id=1 is the press that toggles a switch"),
                      ("CHARTEVENT_MOUSE_MOVE", "id=10 is the cursor")):
        if need not in name:
            fail("toggle-path", "the event-name map cannot name %s: %s" % (need, why))
            return
    if "P4EventName(id)" not in full or "P4EventName(id)" not in lite:
        fail("toggle-path", "an entry point still logs the raw event id")
        return
    if "P_P4_CLICK_WARN_MS" not in events:
        fail("toggle-path", "the click path has no budget of its own")
        return
    click = fn_body(panels, "void HandleUIChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)")
    if not click or "click breakdown" not in click:
        fail("toggle-path", "a press is still an unattributed number (\"the UI half owns it\")")
        return
    # P-PERF-26b: three phases say WHERE the time went; only the control NAME says
    # WHICH press to reproduce. The 531 ms apply had no target until this term
    # existed, so a breakdown without a name is an incomplete measurement, not a
    # style preference.
    if "control=\", sparam" not in click:
        fail("toggle-path", "the click breakdown does not name the control it timed")
        return
    if "P4ReportSlow(\"lines toggle" not in events:
        fail("toggle-path", "the L switch reports no cost of its own")
        return
    ok("toggle-path", "a press and a switch each name their own cost")


def check_persist_write_shape(o):
    """P-PERF-27 - the teardown must not rewrite what is already on disk.

    The live log measured a 172 ms teardown as save=78 ms cleanup=63 ms, i.e.
    82% of it spent re-writing persisted keys and flushing the terminal's WHOLE
    global-variable table (docs.mql4.com/globals/globalvariablesflush: "forcibly
    saves contents of all global variables to a disk") for a chart nobody had
    edited. These are the invariants that keep the guard honest: every override
    write goes through the shadow, the flush only runs when something really
    changed, the shadow is primed from the load pass, and - the one that makes
    the whole scheme safe - anything that DELETES the keys invalidates every
    shadow that still claims they exist.
    """
    runtime = strip_comments(read(RUNTIME, o))
    menu = strip_comments(read(MENU, o))
    panels = strip_comments(read(PANELS, o))
    htf = strip_comments(read(HTF, o))

    save = fn_body(runtime, "void RuntimeSettingsSaveOverrides()")
    if not save:
        fail("persist-write-shape", "RuntimeSettingsSaveOverrides is gone")
        return
    if "GlobalVariableSet(p + " in save:
        fail("persist-write-shape", "an override still writes straight to the terminal: every key must go through the shadow or an unedited teardown pays ~100 writes again")
        return
    if "RSSetNext(p + " not in save:
        fail("persist-write-shape", "the override pass no longer writes through the shadow")
        return
    ok("persist-write-shape", "every persisted override goes through the write shadow")

    commit = fn_body(runtime, "void RSShadowCommit()")
    if not commit or "if(!s_rsDirty) return;" not in commit:
        fail("persist-write-shape", "the disk flush is unguarded: an unchanged pass would still serialise the terminal's whole global-variable table")
        return
    if "GVFlushRequest();" not in commit or "RSShadowCommit()" not in save:
        fail("persist-write-shape", "the override pass no longer asks for the disk copy through the one owner")
        return
    ok("persist-write-shape", "the disk copy is asked for only by a pass that really wrote")

    # P-PERF-44: the flush has ONE owner. The teardown runs FOUR savers and three
    # of them used to call GlobalVariablesFlush themselves - which is exactly how
    # a `save=125ms` phase could sit next to `writes=0/106 flushed=0`: the field
    # counted one block while two others paid a terminal-wide disk serialisation
    # nobody had to change a setting for.
    flush = fn_body(runtime, "bool GVFlushCommit()")
    if not flush or "GlobalVariablesFlush()" not in flush or "if(!s_gvFlushOwed) return false;" not in flush:
        fail("persist-flush-owner", "the single flush owner GVFlushCommit is gone, or is no longer gated on the request flag")
        return
    sites = []
    for sub in ("Biotak", ""):
        for ext in ("mqh", "mq4"):
            for p in sorted(glob.glob(os.path.join(ROOT, sub, "*." + ext))):
                rel = os.path.relpath(p, ROOT).replace("\\", "/")
                sites += [rel] * strip_comments(read(rel, o)).count("GlobalVariablesFlush()")
    if len(sites) != 1 or sites[0] != RUNTIME:
        fail("persist-flush-owner", "%d `GlobalVariablesFlush()` call site(s) (%s): every saver must ASK (GVFlushRequest) and the teardown must pay ONE terminal-wide serialisation"
             % (len(sites), ", ".join(sorted(set(sites))) or "none"))
        return
    for rel, text, block in ((MENU, menu, "GV_BLOCK_UI"), (PANELS, panels, "GV_BLOCK_PALETTE"),
                             (HTF, htf, "GV_BLOCK_HTF")):
        if "GVFlushRequest();" not in text or block not in text:
            fail("persist-flush-owner", "%s does not route its own disk copy through the one owner" % rel)
            return
    ok("persist-flush-owner", "one GlobalVariablesFlush call site in the project, shared by all four saver blocks")

    # P-PERF-44: priming is a BLOCK property, not the override table's privilege.
    # A block whose shadow learns its first value inside the TEARDOWN pays that
    # teardown - the palette and the UI-state blocks did exactly that.
    prime = fn_body(runtime, "void RuntimeSettingsPrimeOverrideShadow()")
    load = fn_body(runtime, "void RuntimeSettingsLoadOverrides()")
    if not prime or "GVShadowDryRun(true);" not in prime or not load \
            or "RuntimeSettingsPrimeOverrideShadow();" not in load:
        fail("persist-write-shape", "the override shadow is not primed in dry-run from its load pass")
        return
    for rel, text, sig, call, fn, host in (
            (MENU, menu, "void PrimeUIStatesShadow()", "PrimeUIStatesShadow();",
             "SaveUIStates(false);", "void InitializeUIStates()"),
            (PANELS, panels, "void PrimePalRecentShadow()", "PrimePalRecentShadow();",
             "SavePalRecent();", "void LoadPalRecent()"),
            (HTF, htf, "void HTFPrimeCandleSettings()", "HTFPrimeCandleSettings();",
             "SaveHTFCandlesSettings();", "void InitializeHTFCandles()")):
        pbody = fn_body(text, sig)
        hbody = fn_body(text, host)
        if not pbody or "GVShadowDryRun(true);" not in pbody or fn not in pbody:
            fail("persist-write-shape", "%s does not prime its shadow by replaying its own write order in dry-run (%s)" % (sig, rel))
            return
        if not hbody or call not in hbody:
            fail("persist-write-shape", "%s is never called from its load pass (%s)" % (sig, host))
            return
    ok("persist-write-shape", "every saver block is primed from its own load pass, never from the teardown")

    # The load-bearing one: a shadow is only valid while the keys exist.
    inv = fn_body(runtime, "void GVShadowsInvalidate()")
    clear = fn_body(menu, "void ClearAllGVs()")
    if not inv or not clear:
        fail("persist-write-shape", "the shadow-invalidation owner or ClearAllGVs is gone")
        return
    if "s_rsShadowKnown[i] = false;" not in inv:
        fail("persist-write-shape", "invalidation does not drop the override shadow")
        return
    if "GVShadowsInvalidate();" not in clear:
        fail("persist-write-shape", "ClearAllGVs deletes the keys without invalidating the shadows: the next save would compare against deleted keys and skip the writes that restore them")
        return
    ok("persist-write-shape", "deleting the keys invalidates every shadow that claims they exist")

    # The other THREE owners of the same teardown window: guarded, and - the rule
    # that keeps the ledger honest - reporting BEFORE their own early return, so a
    # no-op pass cannot leave the previous teardown's numbers standing.
    for rel, text, sig, guard, total in (
            (MENU, menu, "void SaveUIStates(const bool flushNow = false)",
             "if(uiChanged == 0) return;", "GV_BLOCK_UI"),
            (PANELS, panels, "void SavePalRecent()",
             "if(palChanged == 0) return;", "GV_BLOCK_PALETTE"),
            (HTF, htf, "void SaveHTFCandlesSettings()",
             "if(htfChanged == 0) return;", "GV_BLOCK_HTF")):
        body = fn_body(text, sig)
        if not body:
            fail("persist-write-shape", "%s is gone" % sig)
            return
        if guard not in body or "GVSlotChanged" not in body:
            fail("persist-write-shape", "%s in %s still writes and flushes unconditionally on every timeframe switch" % (sig, rel))
            return
        report = "GVLedgerReport(%s" % total
        if report not in body or body.index(report) > body.index(guard):
            fail("persist-write-shape", "%s reports its writes only AFTER it may have returned: a no-op pass would keep the last teardown's numbers" % sig)
            return
    ok("persist-write-shape", "all four teardown writers are change-guarded and name their own writes")


def check_chart_change_prime(o):
    """P-PERF-28 - the first chart-change of an instance must not redraw everything.

    The CHART_CHANGE branch compares the live viewport against a snapshot that
    starts at 0/-1, so on the FIRST event of every instance `visibleMin - 0` is
    unconditionally larger than one point and `viewportChanged` is TRUE by
    construction. That ran a full RedrawAllObjects(false) inside the event on
    every attach and timeframe switch. The log names it, 53 times in one day:

      [W][PERF] chart event id=9 [indicator=3375 ui=0] took 3375ms (budget 40ms)
      ... 3750 / 3938 / 3766 / 3734 / 4063 ms in the same session

    Nothing had changed - the instance's own initial draw already covers the
    viewport it is looking at.
    """
    events = strip_comments(read(EVENTS, o))
    body = fn_body(events, "void OnChartEventHandler(")
    if not body:
        fail("chart-change-prime", "OnChartEventHandler is gone")
        return
    i = body.find("if(id == CHARTEVENT_CHART_CHANGE)")
    if i < 0:
        fail("chart-change-prime", "the CHART_CHANGE branch is gone")
        return
    j = body.find("CHARTEVENT_CLICK", i)
    branch = body[i:j if j > i else len(body)]

    if "if(!s_ccPrimed)" not in branch:
        fail("chart-change-prime", "the zero-initialised snapshot is back: the first chart-change of every instance forces a full RedrawAllObjects inside the event")
        return
    if "viewportChanged = false;" not in branch:
        fail("chart-change-prime", "the prime block does not clear the first-run false positive")
        return
    ok("chart-change-prime", "the first chart-change of an instance is not a viewport change")

    if "chart change breakdown" not in branch:
        fail("chart-change-prime", "the branch that owned the biggest stall in the log has no sub-ledger: its remaining cost can only be guessed")
        return
    ok("chart-change-prime", "the chart-change branch names its own cost")


def check_perf49_ledgers(o):
    """P-PERF-49 — A LEDGER FIELD MUST NAME A STEP, NOT A FUNCTION.

    The MT4-vs-MT5 reconciliation of 2026-09-16 (docs/CACHE-LIFECYCLE-PERF47_FA.md
    in the MT5 mirror) left three numbers that named a whole FUNCTION where every
    other field in this project's ledgers names a step - and each one was the
    biggest number on its own line:

      * `chart change breakdown: redraw=0ms labels=390ms tail=3016ms` on the very
        event that took 3485 ms: the tail is RefreshLiveCountdown() +
        ThrottledChartRedraw(), i.e. the split ended exactly where the stall was;
      * `labels=390/954ms` - the whole of RedrawLabelsOnly(), which is seven steps;
      * `handler=78ms` (p90 313 ms, on MT5, against ZERO MT4 budget violations) -
        the whole of OnDeinitHandler(), which is seven independent promises.

    A number without an owner is not actionable - the project's own rule - so all
    three are split, and this group is what stops the split being folded back into
    the function it was taken out of. `redraw=` additionally reads the render's own
    P-PERF-03 phase counters, because that is the pass it just paid for: a scroll's
    328 ms must read as a step (levels/labels/overlay/...), not as a function.
    """
    events = strip_comments(read(EVENTS, o))
    body = fn_body(events, "void OnChartEventHandler(")
    if not body:
        fail("perf49", "OnChartEventHandler is gone")
        return
    i = body.find("if(id == CHARTEVENT_CHART_CHANGE)")
    if i < 0:
        fail("perf49", "the CHART_CHANGE branch is gone")
        return
    j = body.find("CHARTEVENT_CLICK", i)
    branch = body[i:j if j > i else len(body)]
    for need, why in (
            ("uint p28count = GetTickCount()",
             "the chart-change tail is measured as one number again: tail=3016ms of a "
             "3485ms event cannot be told from the 2.14us ChartRedraw (P-PERF-49)"),
            ("ms [count=",
             "the countdown is no longer separated from the repaint in the line that "
             "reports them (P-PERF-49)"),
            (" render[levels=",
             "redraw= no longer names the render pass it paid for: a scroll's 328ms "
             "reads as a function instead of a step (P-PERF-49)")):
        if need not in branch:
            fail("perf49", why)
            return
    ok("perf49", "the chart-change branch splits its tail and names the render pass")

    rl = fn_body(events, "void RedrawLabelsOnly()")
    if not rl:
        fail("perf49", "RedrawLabelsOnly is gone")
        return
    if "labels relayout" not in rl:
        fail("perf49", "RedrawLabelsOnly lost its phase ledger: labels=390/954ms names a "
                       "function again instead of the step that spent it (P-PERF-49)")
        return
    for need in ("p49clear", "p49atr", "p49th", "p49trade"):
        if need not in rl:
            fail("perf49", "the labels relayout ledger dropped the %s phase (P-PERF-49)" % need)
            return
    ok("perf49", "the labels relayout names its five phases")

    d = fn_body(events, "void OnDeinitHandler(const int reason)")
    if not d:
        fail("perf49", "OnDeinitHandler is gone")
        return
    if "deinit handler breakdown" not in d:
        fail("perf49", "the teardown handler lost its phase ledger: handler=78ms (p90 313ms "
                       "on MT5) names a function again (P-PERF-49)")
        return
    for need in ("p49knot", "p49atr", "p49names", "p49branch"):
        if need not in d:
            fail("perf49", "the deinit handler ledger dropped the %s phase (P-PERF-49)" % need)
            return
    ok("perf49", "the deinit handler names its six phases")


def check_name_scheme(o):
    """P-PERF-38 — ONE level-object prefix, and it does not name the timeframe.

    A timeframe switch must not rename the objects: renaming is what forced
    "delete ~900 + create ~900" on a switch that only changes the PRICES. The
    timeframe still changes the picture (GetTimeframeTH -> thValue), but it does
    so through the SIGNATURE, which re-renders in place.
    """
    objfun = strip_comments(read(OBJFUN, o))
    events = strip_comments(read(EVENTS, o))
    label = strip_comments(read(LABEL, o))

    # (a) the owner exists and is timeframe-free
    owner = fn_body(objfun, "string GetLevelObjectPrefix()")
    if not owner:
        fail("name-scheme", "GetLevelObjectPrefix is gone: the prefix has no owner again")
        return
    if "GetCurrentTimeframe" in owner:
        fail("name-scheme", "the level prefix names the timeframe again: a switch renames every object")
        return
    if 'return inpObjectPrefix + "_";' not in owner:
        fail("name-scheme", "the level prefix is no longer inpObjectPrefix + \"_\" (collision check must be redone)")
        return
    ok("name-scheme", "one timeframe-free owner for the level-object prefix")

    # (b) no site may build a TF-named prefix any more. The only surviving
    # occurrences are the two LEGACY sweeps (the one-time migration and the
    # parameter-rebuild fallback), both keyed on s_tfNs, never on the live TF.
    tf_prefix_sites = []
    for rel in (EVENTS, LABEL, MENU, PANELS, PIPELINE, EXTDRAW, UTIL, KIT):
        src = strip_comments(read(rel, o))
        if 'inpObjectPrefix + "_" + GetCurrentTimeframe() + "_"' in src:
            tf_prefix_sites.append(rel)
        if "inpObjectPrefix+\"_\"+GetCurrentTimeframe()+\"_\"" in src:
            tf_prefix_sites.append(rel)
    if tf_prefix_sites:
        fail("name-scheme", "%s still builds a timeframe-named object prefix" % ", ".join(sorted(set(tf_prefix_sites))))
        return
    legacy = events.count('inpObjectPrefix + "_" + s_tfNs[n] + "_"')
    if legacy < 2:
        fail("name-scheme", "the legacy namespace sweep is gone: an upgraded chart would keep its old TF objects forever")
        return
    ok("name-scheme", "the only TF-named prefixes left are the two legacy sweeps")

    # (c) the switch must not delete the family. This is the half that makes the
    # in-place update possible at all: MT4 forces deinit+init on a period change,
    # so if the teardown deletes, the new instance can only re-create.
    d = fn_body(events, "void OnDeinitHandler(const int reason)")
    if not d:
        fail("name-scheme", "OnDeinitHandler is gone")
        return
    # The branch must be its OWN `else if` - the file also mentions
    # REASON_CHARTCHANGE earlier (the TF-switch timestamp save), so the split has
    # to be anchored on the branch header, not on the enum name.
    if "else if(reason == REASON_CHARTCHANGE)" not in d:
        fail("name-scheme", "the teardown no longer distinguishes REASON_CHARTCHANGE: it deletes the family on every switch")
        return
    cc = d.split("else if(reason == REASON_CHARTCHANGE)", 1)[1].split("\n    else", 1)[0]
    if "DeleteAllIndicatorObjects" in cc:
        fail("name-scheme", "a timeframe switch still deletes the level family it just built")
        return
    ok("name-scheme", "a timeframe switch keeps the level family for an in-place update")

    # (d) the migration is one-time, not per switch.
    mig = fn_body(events, "void MigrateTimeframeNamedObjects()")
    if not mig:
        fail("name-scheme", "the one-time legacy migration is gone")
        return
    # P-PERF-38f: the guard moved to the shared owner (`LegacyNameSchemeMigrated`,
    # GlobalVariables) so the migration and the label sweep cannot drift apart.
    if "LegacyNameSchemeMigrated()) return;" not in mig or "GlobalVariableSet(stamp, 1.0)" not in mig:
        fail("name-scheme", "the migration is not stamp-guarded: it would rescan 11 namespaces on every switch")
        return
    init = fn_body(events, "int OnInitHandler()")
    if not init or "MigrateTimeframeNamedObjects()" not in init:
        fail("name-scheme", "the migration is not run at init, so an upgraded chart blends two naming schemes")
        return
    ok("name-scheme", "the legacy sweep runs once per chart, not once per switch")

    # (e) P-PERF-38e: keeping the family across a switch means the reloaded
    # instance MEETS objects its own empty cache has never seen, and MT4 refuses
    # ObjectCreate for a name that already exists (error 4200). Every other
    # creation site in the level/label families probes ObjectFind first this is
    # the one cache-first creator, so it is the one that must ADOPT instead of
    # treating "already there" as a hard failure (which froze the line at the
    # PREVIOUS timeframe's price and abandoned the caller's remaining family).
    create = fn_body(objfun, "bool CreateTHLineObject(")
    if not create:
        fail("name-scheme", "CreateTHLineObject is gone")
        return
    parts = create.split("if(!ObjectCreate(0, name, objectType", 1)
    if len(parts) < 2:
        fail("name-scheme", "CreateTHLineObject no longer creates the object it is handed")
        return
    body = parts[1]
    if "if(ObjectFind(0, name) < 0) {" not in body:
        fail("name-scheme",
             "the cache-first creator treats \"already on the chart\" as a hard failure: "
             "an adopted object keeps the previous timeframe's price")
        return
    adopt = body.split("if(ObjectFind(0, name) < 0) {", 1)[1]
    if "return false;" not in adopt.split("}\n", 1)[0]:
        fail("name-scheme", "the already-exists probe no longer distinguishes a real create failure")
        return
    if "ObjectSetDouble(0, name, OBJPROP_PRICE, normalizedPrice);" not in body:
        fail("name-scheme", "an adopted object never gets its price written for the new timeframe")
        return
    ok("name-scheme", "the cache-first creator adopts an object the chart already holds instead of failing")

    # (f) P-PERF-38f: the LEGACY namespaces are the one-time migration's job, gated
    # on ONE shared stamp. The label half of that sweep used to run once per draw
    # generation, i.e. on every timeframe switch — 11 full-chart prefix walks to
    # clear names the timeframe-free scheme cannot create and the migration
    # already removes.
    globals_src = strip_comments(read(GLOBALS, o))
    lab = fn_body(label, "void ClearAllLabels(")
    if not lab:
        fail("name-scheme", "ClearAllLabels is gone")
        return
    if "if(!LegacyNameSchemeMigrated())" not in lab:
        fail("name-scheme",
             "the legacy label sweep is not gated on the one-time migration stamp: "
             "11 full-chart walks come back on every timeframe switch")
        return
    if 'ObjectsDeleteAll(0, tfLblPrefix + "_LBL_");' not in lab:
        fail("name-scheme", "the legacy label coverage is gone: an upgraded chart keeps its old _LBL_ ghosts")
        return
    if "s_lastLabelClearGen" in lab:
        fail("name-scheme", "the legacy label sweep is keyed on the draw generation again (once per switch, not once per chart)")
        return
    if '"Biotak_NameScheme_"' in label or '"Biotak_NameScheme_"' in events:
        fail("name-scheme", "the migration stamp has a second owner: the two gates will drift apart")
        return
    if "string NameSchemeStampName()" not in globals_src or \
       "bool LegacyNameSchemeMigrated()" not in globals_src:
        fail("name-scheme", "the migration stamp has no single owner in GlobalVariables")
        return
    mig2 = fn_body(events, "void MigrateTimeframeNamedObjects()")
    if not mig2 or "NameSchemeStampName()" not in mig2:
        fail("name-scheme", "the migration builds its own stamp name instead of using the owner")
        return
    ok("name-scheme", "the legacy namespaces have one owner and one one-time gate, not a per-switch sweep")


def check_topology_adoption(o):
    """P-PERF-38d — the forced reload must be TOLD the chart is already drawn.

    MT4 unloads and RELOADS the indicator on a chart period change, so the new
    instance starts with an empty stored signature. Without a handoff the first
    comparison is trivially "changed" and the family it just kept is wiped and
    rebuilt - the delete+create the user reads as "the timeframe switch
    recomputes and redraws my levels".
    """
    events = strip_comments(read(EVENTS, o))

    # (a) the handoff has owners at all
    for sig in ("string AdoptionStampName()", "int AdoptionFingerprint()",
                "void SaveTopologyAdoptionStamp()", "void ClearTopologyAdoptionStamp()",
                "void ResolveTopologyAdoption()"):
        if not fn_body(events, sig):
            fail("topology-adoption", "%s is gone: the reload has no handoff again" % sig)
            return

    # (b) the fingerprint must name every input that decides WHICH objects exist
    fp = fn_body(events, "int AdoptionFingerprint()")
    for term, why in (("NAME_SCHEME_ID", "the naming scheme id"),
                      ("GetCurrentStepMode()", "the mode"),
                      ("inpMaxLevels", "the level count"),
                      ("g_thStartPointType", "the start point"),
                      ("inpLSFirst", "the LS-first flag"),
                      ("inpEnableHarmonicPattern", "the harmonic enable")):
        if term not in fp:
            fail("topology-adoption",
                 "the adoption fingerprint no longer names %s: a change there could adopt a stale family" % why)
            return
    ok("topology-adoption", "the fingerprint covers every input that decides which objects may exist")

    # (c) the switch writes the stamp; every teardown that really deletes clears it
    d = fn_body(events, "void OnDeinitHandler(const int reason)")
    if not d:
        fail("topology-adoption", "OnDeinitHandler is gone")
        return
    if "else if(reason == REASON_CHARTCHANGE)" not in d:
        fail("topology-adoption", "the teardown no longer distinguishes REASON_CHARTCHANGE")
        return
    cc = d.split("else if(reason == REASON_CHARTCHANGE)", 1)[1].split("\n    else", 1)[0]
    if "SaveTopologyAdoptionStamp();" not in cc:
        fail("topology-adoption", "a timeframe switch no longer tells the next instance the family is still there")
        return
    if d.count("ClearTopologyAdoptionStamp();") < 3:
        fail("topology-adoption", "a teardown that really deletes the family still leaves the adoption stamp behind")
        return
    ok("topology-adoption", "the stamp is written only while keeping the family, and cleared by every deleting teardown")

    # (d) the timeframe invalidation must not force the wipe it no longer needs
    inv = fn_body(events, "void ApplyCacheInvalidation(")
    if not inv:
        fail("topology-adoption", "ApplyCacheInvalidation is gone")
        return
    if "CACHE_INV_TIMEFRAME) != 0" not in inv:
        fail("topology-adoption", "the timeframe invalidation branch is gone")
        return
    tf = inv.split("CACHE_INV_TIMEFRAME) != 0", 1)[1].split("CACHE_INV_NEW_BAR")[0]
    if "if(!g_adoptPreviousTopology) g_forceClearOnNextDraw = true;" not in tf:
        fail("topology-adoption",
             "a timeframe change force-clears again: the family the teardown kept is wiped and rebuilt")
        return
    ok("topology-adoption", "a timeframe change on an adopted instance recomputes without wiping")

    # (e) and the first pass must actually use the handoff
    if 'if(s_lastLevelSig == "" && g_adoptPreviousTopology) s_lastLevelSig = levelSig;' not in events:
        fail("topology-adoption", "the adopted instance still starts with an empty stored signature: the wipe comes back")
        return
    ok("topology-adoption", "the first pass of an adopting instance seeds the stored topology, so nothing is cleared")

    # (f) resolved once, with the state the fingerprint reads already final
    init = fn_body(events, "int OnInitHandler()")
    if not init or "ResolveTopologyAdoption();" not in init:
        fail("topology-adoption", "the adoption is never resolved, so every timeframe switch wipes and rebuilds")
        return
    before = init.split("ResolveTopologyAdoption();", 1)[0]
    after = init.split("ResolveTopologyAdoption();", 1)[1]
    if "g_thStartPointType = inpTHStartPointType;" not in before:
        fail("topology-adoption", "the adoption is resolved before the start point is restored: the fingerprint would use a default")
        return
    if "g_thStartPointType =" in after:
        fail("topology-adoption", "the start point is restored after the adoption is resolved: the fingerprint would mismatch")
        return
    ok("topology-adoption", "the adoption is resolved once, after every fingerprint input is final")


def check_level_foreign_02(o):
    """P-LEVEL-FOREIGN-02 — a stale PRICE is repaired, never a reason to WIPE.

    Reported: «در هر تعویض تایم فریم حذف و دوباره ساخته میشه سطوح» — every
    timeframe switch deletes the level family and builds it again.

    The wipe was the answer P-LEVEL-FOREIGN-01 gave to "the kept objects are
    priced for another timeframe": the adoption fingerprint folded in the
    period, the scaling factor and the daily-close anchor, so a switch could
    NEVER adopt, `ApplyCacheInvalidation` force-cleared the family, and the four
    frame staged rebuild re-created it. That is one shared source, so it was
    true on both platforms — only the price differed (MT4 ~30 ms, MT5 250-300 ms
    of teardown plus four 60-95 ms frames), which is why the user reads it as an
    MT5 defect and sees nothing on MT4.

    The cheap answer is a reconciliation, and BOTH halves must exist before the
    fingerprint may drop the prices:
      * the render re-asserts every name the new ladder PRODUCES, in place, on
        the objects already on the chart (the cache-first creator updates),
      * `SweepForeignLadderObjects` deletes every chart object of the family
        whose NAME the build did not just produce — the half
        `SweepForeignLevelObjects` can never see, because its lists only ever
        name the produced ones.

    The reported symptom when only the first half existed:
    «سطوحی که باید نمایش بده نمایش نمیده، و سطوحی که توی دید نیست رو نمایش
    میده» — a kept object stays VISIBLE outside the window while the produced
    set is attacked from the other side. An index-bound sweep cannot fix that
    (`maxStep` is a window quantity, and the numbering is not the name space),
    so the pass must ask the ONLY exact question: is this name one the build
    just produced? Those lists are in hand at the call site.
    """
    events = strip_comments(read(EVENTS, o))
    pipeline = strip_comments(read(PIPELINE, o))

    # (a) the fingerprint names NAMES, not prices
    fp = fn_body(events, "int AdoptionFingerprint()")
    if not fp:
        fail("level-foreign", "AdoptionFingerprint is gone")
        return
    for term, why in (("Period()", "the chart period"),
                      ("GetCurrentScalingFactor", "the ATR scaling factor"),
                      ("g_dailyClosePriceForTH", "the daily-close anchor")):
        if term in fp:
            fail("level-foreign",
                 "the adoption fingerprint names %s again: a timeframe switch wipes "
                 "the level family and rebuilds it instead of correcting it" % why)
            return
    ok("level-foreign", "the fingerprint names NAMES, not prices: a moved price is repaired, not refused")

    # (b) the reconciliation walks the CHART and asks the EXACT question: is this
    #     name one the build just produced?  Those lists are passed in.
    body = fn_code(pipeline, "int SweepForeignLadderObjects(")
    if not body:
        fail("level-foreign",
             "SweepForeignLadderObjects is gone: nothing deletes the family objects the "
             "new ladder does not produce, and stale ones stay VISIBLE outside the window")
        return
    # ... and it receives them, so the ONLY question it can ask is the exact one
    # (`fn_body` starts after the parameter list, so the signature is read here).
    sigAt = pipeline.find("int SweepForeignLadderObjects(")
    sig = pipeline[sigAt:sigAt + 400] if sigAt >= 0 else ""
    for term, why in (("const STriggerLine &lines[]", "the produced lines"),
                      ("const SZoneDefinition &zones[]", "the produced zones"),
                      ("const double vpTop", "the cull window")):
        if term not in sig:
            fail("level-foreign",
                 "the reconciliation does not receive %s: it cannot know what the build "
                 "produced, so it can only guess by index" % why)
            return
    if "ObjectName(0, i, -1, -1)" not in body or "ObjectsTotal(0, -1, -1)" not in body:
        fail("level-foreign",
             "the reconciliation no longer walks the chart: it can only judge the names the build produced")
        return
    if "if(!(vpTop > vpBottom) || vpBottom <= 0) return 0;" not in body:
        fail("level-foreign",
             "the reconciliation judges the family with an unusable cull window: the "
             "delete-everything-then-rebuild flash on attach comes back")
        return
    if "if(lineCount <= 0) return 0;" not in body:
        fail("level-foreign",
             "a build that produced nothing still reconciles: the whole family is deleted on a bad frame")
        return
    # `fn_code`'s own lesson, one step further: the family has TWO collection sites (the
    # zone-band branch and the general path), so a SUBSTRING test on either promise is
    # satisfied by the SURVIVOR while the other site deletes the live ladder or renumbers
    # the list mid-walk (both negative controls sat here unanswered until now). The two
    # promises are asserted as BALANCES instead: one exact-question guard per COLLECT
    # site (an append to `doomed`), and no delete fed the walk's own name.
    guards = body.count("if(ProducedLadderName(nm, produced, pc)) continue;")
    collects = len(re.findall(r"ArrayResize\(doomed, nd \+ 1\);[ \t]*\n[ \t]*doomed\[nd\+\+\] = nm;",
                              body))
    if guards < 1 or collects != guards:
        fail("level-foreign",
             "the reconciliation stopped asking the exact question at EVERY collection site "
             "(%d guard(s) for %d collect site(s)): a produced name can be deleted, and the "
             "switch deletes the ladder it just built" % (guards, collects))
        return
    if re.search(r"Delete\w+\(nm", body) or \
       "DeleteIndicatorObjectManaged(doomed[d], true)" not in body:
        fail("level-foreign",
             "the reconciliation deletes while it walks: a delete renumbers the object "
             "list, so the next survivor is stepped over")
        return
    if "bool LadderNameIsZoneBand(" not in pipeline or \
       'if(StringFind(nm, "_Zone_") >= 0) continue;' not in body:
        fail("level-foreign",
             "the walk acts on a zone's border sub-objects as if they were bands: one "
             "stale zone is deleted six times over and the family is counted wrong")
        return
    ok("level-foreign", "the reconciliation walks the chart and keeps exactly the produced names")

    # (c) it runs once, on the pitch-change frame, and only on a HANDOFF
    if pipeline.count("SweepForeignLadderObjects(config, lines, result.lineCount") != 1:
        fail("level-foreign", "the reconciliation is not called exactly once from the pitch-change frame")
        return
    pitch = pipeline.find("SweepForeignLevelObjects(config, lines, result.lineCount")
    call = pipeline.find("SweepForeignLadderObjects(config, lines, result.lineCount")
    guard = pipeline.find("if(g_adoptPreviousTopology && !s_foreignSweepDone)")
    if pitch < 0 or call < pitch:
        fail("level-foreign", "the reconciliation left the frame that detects the pitch change")
        return
    if guard < 0 or guard > call:
        fail("level-foreign",
             "the reconciliation is not gated on the handoff: a wiped chart gets a whole-chart walk")
        return
    consume = pipeline.find("s_foreignSweepDone = true;")
    if consume < 0 or consume > call:
        fail("level-foreign",
             "the reconciliation is not consumed once per instance: a whole-chart walk "
             "becomes a tax on every intraday pitch drift")
        return
    ok("level-foreign", "the reconciliation runs once, on the pitch-change frame of a handed-over family")


def check_event_settle(o):
    """P-PERF-40 — an event must settle the frame it owed, in the same event.

    P-PERF-34 made a forced frame inside an event SCHEDULED rather than executed
    (its body measured 531 ms and froze the press). That left the user's edit owed
    to the 250 ms timer, and the live log measured the result:

        [W][PERF] owed frame (chart-event) waited=46..266ms body=0ms clear=0

    i.e. a press was acknowledged by a repaint of the OLD picture and the real
    frame landed up to a timer cadence later — the "فسفس". The drain lives at the
    event ENTRY POINTS because that is the one place covering both handlers (and
    paths added later), and its cost is measured and counted, because a drain that
    hides its own work would be the very defect this fixes, one level up.
    """
    for rel in (FULL, LITE):
        src = strip_comments(read(rel, o))
        if "g_inChartEvent = false;" not in src:
            fail("event-settle", "%s no longer scopes the event window" % rel)
            return
        after = src.split("g_inChartEvent = false;", 1)[1]
        if "P4ReportSlow(" not in after:
            fail("event-settle", "%s no longer reports the event cost" % rel)
            return
        head, report = after.split("P4ReportSlow(", 1)
        if "CoopPump();" not in head:
            fail("event-settle",
                 "%s schedules the frame but never drains it: the edit waits for the timer" % rel)
            return
        if "settle=" not in report:
            fail("event-settle",
                 "%s drains a frame without reporting its cost: the ledger would hide it" % rel)
            return
        ok("event-settle", "%s settles the frame its own event owed, and reports the cost" % rel)

    # The drain only works because it runs the frame in the one form the event
    # guard admits: the guard refuses force_redraw inside an event, so the pump
    # must call the frame with force_redraw = FALSE.
    pump = fn_body(strip_comments(read(EVENTS, o)), "void CoopPump()")
    if not pump:
        fail("event-settle", "the coop pump is gone: nothing owns owed work")
        return
    if "RedrawAllObjects(false)" not in pump:
        fail("event-settle",
             "the drain no longer runs the frame with force_redraw = FALSE: the event guard refuses it")
        return
    ok("event-settle", "the drain runs the frame in the form the event guard admits")


# states that a panel row or a ring badge DISPLAYS (the rows read them live, so
# only the IMAGE can go stale — which is what this group is about)
#
# P-UI-40b: TWO card rows were missing from this list, and both hid a real
# stale-image bug of exactly the shape this group exists to catch —
#   * `g_UI.showHTF`   -> the HTF card's SHOW row (`PnlCurrentSet` case 6 row 0),
#                         written by the ring's CIR_HTF item;
#   * `g_stepCalculationMode` -> the STEP card's mode row (case 9 row 0),
#                         written by the E key AND by the tools sub-menu's
#                         STEP item (the same control on two surfaces).
# A gallery of the ring/tools writes that a CARD shows, so an item added later
# cannot repeat it: every state named here is read by a `PnlCurrentSet` row.
UI_DISPLAYED = ("g_linesVisible", "g_triggerLevelsEnabled", "g_atrLabelsVisible",
                "g_thLabelsMode", "g_showLiveCountdown", "g_timeframeLocked",
                "g_showMidZones", "g_UI.showHTF", "g_stepCalculationMode")


def _branches(src, marker):
    """Per-branch chunks of a handler, split at each marker occurrence."""
    parts = src.split(marker)
    return parts[1:] if len(parts) > 1 else []


def _silent_branches(chunks, with_lines_owner=False, states=None):
    """Branches that WRITE a displayed state without asking the UI to repaint.

    A bare substring search is not enough and the F key proves it: its branch
    PASSES `g_linesVisible` into VisibilityShowAllCached as an argument, which is
    a read. Only an assignment (or the one owner call that exists for the line
    mask) counts as a write.

    `states` defaults to the hand list `UI_DISPLAYED`, but the rule is also run
    against `_card_displayed_states()` below - the set derived from
    `PnlCurrentSet` itself (P-UI-40b: a state nobody listed cannot be required to
    ask, which is how two real rows stayed silent).
    """
    states = UI_DISPLAYED if states is None else states
    out = []
    for chunk in chunks:
        writes = [v for v in states
                  if re.search(r"\b" + re.escape(v) + r"\s*=(?!=)", chunk)]
        if with_lines_owner and "SetLinesVisible(p26want" in chunk:
            writes.append("SetLinesVisible")
        if writes and "RequestUISync()" not in chunk:
            head = chunk.lstrip()[:26].split(")")[0]
            out.append(head)
    return sorted(set(out))


def _card_displayed_states(panels):
    """Every `g_*`/`g_UI.*` state a settings card row DISPLAYS.

    Read from `PnlCurrentSet` - the one function every row reads - so the list
    cannot drift from the cards: a row that starts showing a new state enters the
    rule below by itself. Local variables are `item`/`row`/`mode` (no `g_`
    prefix), and the row helpers (`PnlStepSectionCurrent`, `BkSecCurrent`, ...)
    are functions, so neither pollutes the set.
    """
    body = fn_body(strip_comments(panels), "double PnlCurrentSet(")
    if not body:
        return set()
    return set(re.findall(r"\bg_UI\.[A-Za-z_]+|\bg_[A-Za-z_]+", body))


def check_ui_sync(o):
    """P-UI-40 — a writer that cannot repaint must ASK the UI to.

    Panel rows read LIVE globals, so a value can never disagree between the
    keyboard and the panel. The IMAGE can: a switch is an OBJ_BITMAP_LABEL whose
    bitmap is only replaced by a paint pass, and every writer inside the panel
    file repaints its own row after a press while the panel file is included
    AFTER EventHandlers — where every hotkey lives. A hotkey therefore changed
    the state, the chart obeyed, and an open card kept showing the previous
    switch position until it was reopened. This group locks the request/drain
    pair that closes that asymmetry.
    """
    g = strip_comments(read(GLOBALS, o))
    for sig in ("void RequestUISync()", "bool UISyncRequested()", "void UISyncConsume()"):
        if not fn_body(g, sig):
            fail("ui-sync", "%s is gone: a writer that cannot repaint has no way to ask" % sig)
            return
    panels = strip_comments(read(PANELS, o))
    drain = fn_body(panels, "void UISyncDrain()")
    if not drain:
        fail("ui-sync", "UISyncDrain is gone: requests are raised and never drained")
        return
    at = drain.find("UISyncConsume()")
    if at < 0 or at > drain.find("PnlSyncOpenCard()"):
        fail("ui-sync", "the drain must consume the request BEFORE it repaints (two drains cost one repaint)")
        return
    for term, why in (("UpdateCircularItemStates()", "the ring's item states"),
                      ("UpdateCircularBadges()", "the ring's badges"),
                      ("PnlSyncOpenCard()", "the open card's rows")):
        if term not in drain:
            fail("ui-sync", "the drain no longer repairs %s" % why)
            return
    ok("ui-sync", "the drain consumes the request, then repairs the ring and the open card")

    card = fn_body(panels, "void PnlSyncOpenCard()")
    if not card:
        fail("ui-sync", "PnlSyncOpenCard is gone")
        return
    if "PnlUpdateRow(" not in card:
        fail("ui-sync", "the card repair no longer repaints the rows")
        return
    if "g_PnlOpen < 0) return;" not in card:
        fail("ui-sync", "the card repair must no-op when no card is open")
        return
    if "BkMiniRefresh()" not in card:
        fail("ui-sync", "item 13 is one toolbar, not rows: the strip keeps its own owner (BkMiniRefresh)")
        return
    ok("ui-sync", "the card repair walks the open card's rows and leaves the strip to its owner")

    # The Step card is the one case a row repaint cannot serve: a mode change
    # RESHAPES it (each mode's rows live below the segments), so its own
    # change-guarded rebuild stays the owner and must not be dropped.
    step = fn_body(panels, "void PnlSyncOpenStepRow()")
    if not step or "if(g_PnlOpen == 9) PnlOpen(9);" not in step:
        fail("ui-sync", "the Step card's reshape owner is gone: a row repaint cannot reshape a card")
        return
    ok("ui-sync", "the one reshaping card keeps its own rebuild owner")

    # Every HOTKEY that writes a displayed state must ask.
    hk = fn_body(strip_comments(read(EVENTS, o)), "void OnChartEventHandler(")
    if not hk:
        fail("ui-sync", "OnChartEventHandler is gone")
        return
    silent = _silent_branches(_branches(hk, "IsHotkeyPressed(lparam, sparam, "), True)
    if silent:
        fail("ui-sync",
             "these hotkeys change state the panel displays but never ask it to repaint: %s" % ", ".join(silent))
        return
    ok("ui-sync", "every hotkey that writes a displayed state asks the UI to repaint")

    # ... and every RING branch too: the ring repaints itself, an open card it
    # cannot reach (this file is included before the panel's).
    ring = fn_body(strip_comments(read(MENU, o)), "int HandleButtonClick(")
    if not ring:
        fail("ui-sync", "HandleButtonClick is gone")
        return
    silent = _silent_branches(_branches(ring, "feat == CIR_"))
    if silent:
        fail("ui-sync",
             "these ring branches change state an open card displays but never ask it to repaint: %s" % ", ".join(silent))
        return
    ok("ui-sync", "every ring branch that writes a card-displayed state asks the UI to repaint")

    # ... and the SAME rule against the list DERIVED from the cards (P-UI-40b):
    # UI_DISPLAYED is a hand transcription, and a row displaying a state nobody
    # wrote down is exactly what stayed silent for the HTF SHOW and STEP mode
    # rows. This half needs no list to be maintained: it reads what PnlCurrentSet
    # returns today and requires the same request from any branch that writes it.
    displayed = _card_displayed_states(panels)
    if len(displayed) < 20:
        fail("ui-sync",
             "PnlCurrentSet no longer parses (%d states): the derived-row rule lost its input"
             % len(displayed))
        return
    silent = _silent_branches(_branches(hk, "IsHotkeyPressed(lparam, sparam, "),
                              False, displayed)
    silent += _silent_branches(_branches(ring, "feat == CIR_"), False, displayed)
    if silent:
        fail("ui-sync",
             "a card row displays a state these writers change without asking to repaint: %s"
             % ", ".join(sorted(set(silent))))
        return
    ok("ui-sync", "every writer of a state a card ROW returns (%d derived) asks to repaint"
       % len(displayed))

    # The event tail drains it (same event = key and panel land together) and
    # reports it; the tick net catches anything that misses the tail.
    full = strip_comments(read(FULL, o))
    if "g_inChartEvent = false;" not in full or "P4ReportSlow(" not in full.split("g_inChartEvent = false;", 1)[1]:
        fail("ui-sync", "the event tail is not the shape this check expects")
        return
    head, report = full.split("g_inChartEvent = false;", 1)[1].split("P4ReportSlow(", 1)
    if "UISyncDrain();" not in head:
        fail("ui-sync", "the event tail does not drain the UI request: a hotkey's panel follows a tick later")
        return
    if "panels=" not in report:
        fail("ui-sync", "the drain is not in the event budget: it would hide its own cost")
        return
    kit = fn_body(panels, "void RefreshKitOnBar()")
    if not kit or "UISyncDrain();" not in kit:
        fail("ui-sync", "RefreshKitOnBar no longer drains: a path that misses the event tail never settles")
        return
    ok("ui-sync", "the event tail drains and reports it, and the tick net catches the rest")


def check_longpress_latch(o):
    """P-UI-40c - the long-press latch belongs to ONE gesture and dies with it.

    `g_LongPressFired` exists so the release-click of a hold that ALREADY opened a
    card does not also toggle the item. It was cleared in two places: the arming
    pass (a fresh press on an item) and the two `if(g_LongPressFired)` guards in
    `HandleButtonClick`. The SUPPRESSED release paths (`UISuppressNextClick` was
    armed by the very hold that fired, and every `UIShouldSuppressClick()` return
    in `BiotakPanels` happens BEFORE `HandleButtonClick`) never reach those
    guards, so the latch outlived its gesture - and the next click that reached
    `HandleButtonClick` with no arming pass first was EATEN. A motionless click
    emits no `CHARTEVENT_MOUSE_MOVE` (P-BK-03's trap), so that is a plain click:
    the control looks dead once, the P-UI-01 symptom.

    The three invariants this group locks, all of them decisions already made:
      * ONE owner clears the whole latch - and it runs on the release the
        suppression window already classified as this gesture's;
      * a click arriving AFTER the window still meets both guards (the latch is
        genuinely needed there: the user may hold for seconds);
      * the button-up net (`ChartPointerFinalizeOnUps`) must NOT clear the fired
        flag, because it runs BEFORE the click that owns it.
    """
    menu = strip_comments(read(MENU, o))
    owner = fn_body(menu, "void UILongPressLatchClear()")
    if not owner:
        fail("longpress-latch", "UILongPressLatchClear is gone: the latch has no owner")
        return
    if "g_LongPressFired" not in owner or "g_LongPressItem" not in owner:
        fail("longpress-latch",
             "the owner no longer clears the whole latch (fired flag + armed item)")
        return
    ok("longpress-latch", "one owner clears the fired flag and the armed item together")

    panels = strip_comments(read(PANELS, o))
    sites = re.findall(r"if\(UIShouldSuppressClick\(\)\)[^\n]*", panels)
    if len(sites) < 2:
        fail("longpress-latch",
             "the suppressed release paths are gone: this check lost its anchor")
        return
    silent = [s for s in sites if "UILongPressLatchClear()" not in s]
    if silent:
        fail("longpress-latch",
             "a suppressed release skips HandleButtonClick without clearing the latch: "
             "that release's own latch then eats the NEXT click")
        return
    ok("longpress-latch", "every suppressed release clears the latch with its gesture")

    ring = fn_body(menu, "int HandleButtonClick(")
    if not ring:
        fail("longpress-latch", "HandleButtonClick is gone")
        return
    guards = re.findall(r"if\s*\(g_LongPressFired\)\s*\{[^}]*\}", ring, re.S)
    if len(guards) < 2:
        fail("longpress-latch",
             "HandleButtonClick lost a g_LongPressFired guard: a release after the "
             "suppression window would toggle the item it just opened a card for")
        return
    ok("longpress-latch", "both surfaces still eat the release that arrives late (ring + tools)")

    final = fn_body(panels, "void ChartPointerFinalizeOnUps()")
    if not final:
        fail("longpress-latch", "ChartPointerFinalizeOnUps is gone")
        return
    if "g_LongPressFired" in final:
        fail("longpress-latch",
             "the button-up net clears the fired latch: every button-up would release it "
             "before the click that owns it")
        return
    ok("longpress-latch", "the latch survives button-up, so only its own release consumes it")


def check_click_claim(o):
    """P-UI-65 - the click claim belongs to ONE gesture and is taken once.

    `UISuppressNextClick()` means "the button-up that ends THIS gesture is already
    spent". Its identity used to be a wall-clock deadline (`GetTickCount() + 350`),
    which failed in both directions and is why the same button works one time and
    not the next:

      * LEAK - the deadline is armed at PRESS time (nearly every arm site) and the
        release is the event it must eat. Hold the button longer than the window
        and the claim is dead before its own release, so the release runs
        HandleButtonClick / PnlHandleClick on a control whose press already acted.
        How long a press takes is the user's choice - the failure is random by
        construction.
      * OVER-EATING - the consumer never cleared the deadline, so one release
        consumed the time test and the REMAINDER of the window ate the NEXT genuine
        click: "press close, nothing happens, press again and it works". P-UI-40c
        fixed exactly this shape for the long-press latch; the window around it was
        left behind.

    The invariants here are the ones the fix decided, so a later edit cannot
    quietly re-add a clock: the arm binds the claim to the LIVE PRESS (its sequence
    number) instead of a deadline, the consumer TAKES it once and then echoes for
    the one release that MT4 can deliver as two events, a new press owns its own
    click, and a fresh attach starts with no claim at all.
    """
    menu = strip_comments(read(MENU, o))
    arm = fn_body(menu, "void UISuppressNextClick()")
    if not arm:
        fail("click-claim", "UISuppressNextClick is gone: the release has no claim owner")
        return
    armed = re.search(r"s_uiClickClaim\s*=\s*true", arm)
    missing = [t for t in ("g_MouseWasDown", "g_UIPressSeq")
               if t not in arm]
    if not armed:
        missing.append("s_uiClickClaim = true")
    if missing:
        fail("click-claim",
             "the arm stops binding the claim to its gesture (%s): a press longer than "
             "any window leaks its own release" % ", ".join(missing))
        return
    ok("click-claim", "the claim is armed against the live press, not against a clock")

    take = fn_body(menu, "bool UIShouldSuppressClick()")
    if not take:
        fail("click-claim", "UIShouldSuppressClick is gone: nothing consumes the claim")
        return
    if "s_uiClickClaim = false" not in take:
        fail("click-claim",
             "the consumer stops clearing the claim: the rest of the window eats the "
             "NEXT click (the P-UI-01 symptom)")
        return
    if "g_UIClickSuppressUntil" in take:
        fail("click-claim", "the wall-clock deadline is back: a claim then outlives its release")
        return
    if "if(s_uiClickClaimDown && s_uiClickClaimSeq != g_UIPressSeq)" not in take:
        fail("click-claim",
             "a press-time claim is no longer bounded by its own press: it can be spent "
             "on a later, unrelated click")
        return
    if "if(s_uiReleaseEchoMs != 0 && (int)(nowMs - s_uiReleaseEchoMs) < 0) return true;" not in take:
        fail("click-claim",
             "the twin-event echo is gone: one release can arrive as both CHARTEVENT_CLICK "
             "and CHARTEVENT_OBJECT_CLICK, and the second one would act")
        return
    if "if(!s_uiClickClaimDown && (int)(nowMs - s_uiClickClaimMs) >= 0)" not in take:
        fail("click-claim",
             "the release-armed form lost its TTL: a claim with no press to bind to then "
             "waits forever")
        return
    if "UI_UP_CLAIM_TTL_MS" not in arm:
        fail("click-claim", "the release-armed form is armed without its TTL")
        return
    ok("click-claim", "the claim is taken once, echoed for its twin event, and bounded")

    press = fn_body(menu, "bool MousePressStart(const bool leftDown)")
    if not press or "if(pressStart) g_UIPressSeq++;" not in press:
        fail("click-claim",
             "the press sequence no longer advances on the rising edge: nothing can tell "
             "an old claim from this gesture's")
        return
    ok("click-claim", "one press = one identity, so a stale claim dies with its own gesture")

    reset = fn_body(menu, "void UIReleaseClaimReset()")
    if not reset:
        fail("click-claim", "UIReleaseClaimReset is gone: claim state would cross an attach")
        return
    if "if(g_MouseWasDown) return;" not in reset:
        fail("click-claim",
             "the reset can drop a live gesture's claim: a menu re-created mid-press would "
             "un-suppress its own release")
        return
    if "if(s_uiReleaseEchoMs != 0 && (int)(GetTickCount() - s_uiReleaseEchoMs) < 0) return;" not in reset:
        fail("click-claim",
             "the reset fires mid-release: CreateMenu is reachable from HandleButtonClick, "
             "so it would drop the echo of the release that is still arriving")
        return
    if "g_UIPressSeq" not in reset:
        fail("click-claim", "the reset leaves the press counter behind")
        return
    entry = fn_body(menu, "void CreateMenu()")
    if not entry or "UIReleaseClaimReset();" not in entry:
        fail("click-claim",
             "the claim is not reset on the one UI entry point every attach runs "
             "(CreateMenu): the first click of a fresh instance can be eaten")
        return
    ok("click-claim", "a fresh attach starts with no claim, and a live press keeps its own")


INPUTS = "Biotak/PropertiesAndInputs.mqh"
# The panel and the settings layer are where a control is DEFINED, not where its
# effect lands: a global only they mention is a global nobody consumes.
SKIP_CONSUMERS = (PANELS, RUNTIME, INPUTS, "Biotak/InputValidator.mqh")
# A branch may also owe its effect to a REQUEST flag - those are read by the
# render loop, so counting them would excuse a row that changes nothing else.
REQUEST_ONLY = ("g_redrawTHLevelsNeeded", "g_labelsRelayoutNeeded",
                "g_forceClearOnNextDraw", "g_renderAllNeeded")
# State that only the PANEL renders: its consumer is the card rebuilding itself
# (`PnlApplyOption` -> `PnlOpen`), which no other module can witness. Listed by
# hand ON PURPOSE - one name, named here, so a dead CHART control cannot hide.
UI_LOCAL = ("g_BkTab",)


def _apply_rows(src):
    """PnlApplySet -> {(item, settingRow): branch source}.

    MQL4 semantics, not a guess: a row is answered by the FIRST condition that
    names it (a chain condition may name several, e.g. `row==1 || row==2`), and
    an `else` tail owns every row its case did not name. A condition that is not
    a literal set of rows (the Step card's `PnlStepMaxLevelsRow()`) is dropped:
    this check measures the rows it can REACH, never the ones it has to guess.
    """
    body = fn_body(src, "int PnlApplySet(")
    if not body:
        return None
    out = {}
    for cm in re.finditer(r"\n\s+case (\d+):", body):
        item = int(cm.group(1))
        nxt = re.search(r"\n\s+case \d+:", body[cm.end():])
        block = body[cm.end(): cm.end() + (nxt.start() if nxt else len(body))]
        nl = block.find("\n")
        if nl >= 0:
            block = block[nl + 1:]            # the rest of the `case N:` line is a comment
        # walk the if/else-if/else chain CLAUSE BY CLAUSE: `else if(row==..)` is a
        # boundary, `else { ... }` closes the chain, and an `else` that starts no
        # clause (an inner `if(row==1) x; else y;` INSIDE one row's body) is not a
        # boundary - splitting there would cut a row in half and blame the wrong
        # half for its writes.
        tail = None
        for cl in re.split(r"\n\s*else\s+(?=if\s*\(\s*row\s*==|\{)", block):
            m = re.match(r"\s*if\s*\(\s*row\s*==\s*([^)]+)\)", cl)
            if not m:
                if cl.strip().startswith("{"):
                    tail = cl                 # a bare `else { ... }` closes the chain
                continue
            cond = m.group(1)
            if "(" in cond:
                continue                      # a computed row (Step card) - not measurable
            rows = [int(n) for n in re.findall(r"\d+", cond)]
            for r in rows:
                out[(item, r)] = cl
        if tail is not None:
            for r in range(0, 32):
                if (item, r) not in out:
                    out[(item, r)] = tail
    return out


def _code_only(src):
    """Code with EVERY comment gone - full lines AND trailing ones.

    The shared `strip_comments` deliberately keeps trailing comments (other checks
    match on them), but a name mentioned in prose is not a consumer: the enum line
    `FF_ENABLE_MAGNET,   // inpEnableMagnet` alone would make the magnet look alive.
    """
    out = []
    for line in src.splitlines():
        s = line.strip()
        if s.startswith("//") or s.startswith("*") or s.startswith("/*"):
            continue
        i = line.find("//")
        if i >= 0:
            line = line[:i]
        out.append(line)
    return "\n".join(out)


def _row_clauses(block):
    """{rowNumber: clause}` for one `if(row==N) / else` chain (MQL4 semantics)."""
    out = {}
    tail = None
    for cl in re.split(r"\n\s*else\s+(?=if\s*\(\s*row\s*==|\{)", block):
        m = re.match(r"\s*if\s*\(\s*row\s*==\s*([^)]+)\)", cl)
        if not m:
            if cl.strip().startswith("{"):
                tail = cl
            continue
        cond = m.group(1)
        if "(" in cond:
            continue
        for r in [int(n) for n in re.findall(r"\d+", cond)]:
            out[r] = cl
    if tail is not None:
        for r in range(0, 32):
            out.setdefault(r, tail)
    return out


def _setting_kinds(src):
    """{(item, setting row): kind} from PnlSetDef - a COLOR/NAV/TEXT row is not a
    control: PnlApplySet returns before the switch for those, so its branch can
    never run and must not be measured as if the user could press it."""
    body = fn_body(src, "void PnlSetDef(")
    if not body:
        return {}
    kinds = {}
    for cl in re.split(r"\n\s*else\s+(?=if\s*\(\s*item\s*==|\{)", body):
        m = re.search(r"if\s*\(\s*item\s*==\s*(\d+)\s*\)", cl)
        if not m:
            continue
        item = int(m.group(1))
        for row, rcl in _row_clauses(cl[m.end():]).items():
            k = re.search(r"kind\s*=\s*(\d+)", rcl)
            kinds[(item, row)] = int(k.group(1)) if k else 0
    return kinds


def _reachable_settings(src):
    """(item, setting row) pairs some display row actually RENDERS."""
    reach = set()
    for m in re.finditer(r"PnlSpecAdd\(\s*(\d+)\s*,\s*PNL_K_\w+\s*,\s*(-?\d+)\s*,\s*(\d+)", src):
        item, s0, n = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if s0 < 0:
            continue
        for k in range(max(1, n)):
            reach.add((item, s0 + k))
    return reach


def check_live_control(o):
    """P-UI-46/47 - a control the card RENDERS must move state somebody reads.

    Two reports, one day apart, and the same question underneath: *is the thing
    this row writes read by anybody?* The user's words were "the button does not
    work". Four rows answered NO - their feature had been retired (or the setting
    moved) while the card kept drawing the row:
      * Zones & Levels / MIDPOINT - the midpoint LINE is deleted every render by
        the pipeline's own legacy cleanup, so the switch wrote `g_showMidpointLine`
        and changed nothing;
      * Custom Price / MAGNET + MAGNET SENS - snapping was retired by user
        decision twice (BKMAGNET-OFF 2026-09-06 for the DRAW-time snap,
        BKMAGNET2-OFF 2026-09-15 for the ADJUST-time snap P-BK-21 had added):
        the engine is comments, so the flags have no reader at all. Both rows
        left this family the day the engine was commented - and the specimen
        below (re-render the retired row) is the fault again, exactly as in
        P-UI-47 (see the seeds below);
      * ATR Labels / ROW GAP - the label layout reads the INPUT `inpLabelRowGap`,
        not the runtime copy this slider wrote.
    And card 3's source rows (1/2) re-derived the mode from the very mirrors they
    were about to write, so the LAST lit source could never be switched off
    (P-UI-44 fixed row 0, this closes rows 1/2).

    Invariants:
      (a) for every REACHABLE setting row, at least one global its branch writes
          is READ outside the panel/settings layer - or the branch calls an owner
          that lives outside it (a request-to-repaint flag is not an effect, and
          neither is a save);
      (b) a TH source row writes the MODE from its own new value - it may never
          read the mode back out of the mirrors it just changed;
      (c) a row whose press changes what ANOTHER surface displays asks the UI
          layer to repaint in the same event.
    """
    panels = _code_only(read(PANELS, o))
    runtime = _code_only(read(RUNTIME, o))
    reach = _reachable_settings(panels)
    rows = _apply_rows(panels)

    # every source the indicator is built from, discovered (not listed): a new
    # module must be able to answer this check without editing it. Indexed ONCE
    # per run (name -> the files that INTERROGATE it) so a 140-seed selftest does
    # not re-scan 70 files per seed.
    token = re.compile(r"\b(?:g_|inp)[A-Za-z0-9_]+\b")
    lhs = re.compile(r"^\s*([A-Za-z_]\w*)\s*=(?!=)")
    owners = set()                                # functions DEFINED outside the UI layer
    reads_in = {}
    _sources = {}
    for sub in ("Biotak", ""):
        for ext in ("mqh", "mq4"):
            for p in sorted(glob.glob(os.path.join(ROOT, sub, "*." + ext))):
                rel = os.path.relpath(p, ROOT).replace("\\", "/")
                _sources[rel] = _code_only(read(rel, o))
    for rel, src in _sources.items():
        if rel not in SKIP_CONSUMERS:
            # a column-0 `Type Name(` is a DEFINITION. A call to a function the
            # UI layer itself owns (a save, a repaint request) is not an effect.
            owners.update(re.findall(r"(?m)^[A-Za-z_]\w*\s+([A-Za-z_]\w*)\s*\(", src))
            for line in src.splitlines():
                names = token.findall(line)
                if not names:
                    continue
                m = lhs.match(line)
                for nm in names:
                    if m and m.group(1) == nm:
                        continue                     # written here, not read
                    reads_in.setdefault(nm, set()).add(rel)
    # the settings layer's own plumbing (definition / load / save) is not a read.
    # NOTE the LOAD line `g_x = inp_x;` names BOTH sides, so it must be dropped
    # whole: treating its alias as a read is exactly what would hide a control
    # whose flag is only ever loaded and saved.
    for line in runtime.splitlines():
        names = token.findall(line)
        if not names:
            continue
        s = line.strip()
        if s.startswith("static") or s.startswith("#define"):
            continue
        if "RSSetNext(" in line or "GlobalVariableCheck(p +" in line \
           or "GlobalVariableGet(p +" in line:
            continue
        if re.match(r"^g_\w+\s*=\s*(inp\w+|Clamp\w*\(.*GlobalVariableGet)", s):
            continue
        if re.match(r"^g_factoryDefaults\[", s):
            continue                          # captures the INPUT, not the runtime copy
        m = lhs.match(line)
        for nm in names:
            if m and m.group(1) == nm:
                continue
            reads_in.setdefault(nm, set()).add(RUNTIME)
    if len(_sources) < 30:
        fail("live-control", "only %d sources found: this check is not looking at the project"
             % len(_sources))
        return
    if not reach or not rows:
        fail("live-control", "the display spec or PnlApplySet is unreadable: this check "
                             "can no longer see what a card renders")
        return
    ok("live-control", "%d rendered settings against %d writer branches"
       % (len(reach), len(rows)))

    alias = {m.group(2): m.group(1) for m in re.finditer(r"#define\s+(inp\w+)\s+(g_\w+)", runtime)}

    def is_read_elsewhere(name):
        """A READ of this global (or of its inp alias) outside the panel/settings
        layer. "Read" = appears on a line that does not assign it."""
        for nm in ({name} | ({alias[name]} if name in alias else set())):
            if reads_in.get(nm):
                return True
        return False

    kinds = _setting_kinds(panels)
    dead = []
    for key in sorted(reach):
        if kinds.get(key, 0) in (4, 5, 6, 7):
            continue                              # colour / nav / text / band: not a control
        seg = rows.get(key)
        if seg is None:
            continue
        written = {g for g in re.findall(r"\b(g_\w+)\s*=", seg)
                   if g not in REQUEST_ONLY and g != "flags"}
        if not written:
            continue                              # delegates to an owner / no state of its own
        live = [g for g in written if is_read_elsewhere(g)]
        if not live:
            # ...or the branch HANDS the state to an owner that lives outside the
            # UI layer (`SetLinesVisible(g_showLines, true)`). A call that merely
            # takes the new VALUE (`ClampInt((int)MathRound(v),1,60)`) or nothing at
            # all (a save) is not an effect - that is exactly how a dead slider
            # looked alive.
            for g in written:
                for m in re.finditer(r"\b(\w+)\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)", seg):
                    if m.group(1) in owners and re.search(r"\b%s\b" % re.escape(g), m.group(2)):
                        live.append(g)
                        break
                if live:
                    break
        if not live and not any(g in UI_LOCAL for g in written):
            dead.append("item %d row %d -> %s" % (key[0], key[1], ", ".join(sorted(written))))
    if dead:
        fail("live-control",
             "%d rendered control(s) write state NOBODY reads - pressing them can only "
             "move their own switch: %s" % (len(dead), "; ".join(dead)))
        return
    ok("live-control", "every rendered control moves state that is read elsewhere")

    # (b) the TH source rows: the mode comes from the press, never from the mirrors
    src = rows.get((3, 1), "")
    if not src or "g_thLabelsMode" not in src:
        fail("live-control", "card 3's source-row branch is gone: this check lost its anchor")
        return
    if "THModeFromFlags()" not in src:
        fail("live-control", "the TH source rows no longer derive the mode from their own write")
        return
    if re.search(r"if\s*\(\s*g_showTHLabels\s*&&", src):
        fail("live-control",
             "a TH source row re-derives the mode from the mirrors it is about to write: "
             "switching the LAST lit source OFF re-lights it (the reported one-way switch)")
        return
    if "SyncTHFlagsFromMode()" not in src or "SetTHLabelsVisibility(" not in src:
        fail("live-control", "the TH source row stopped applying the mode it wrote")
        return
    # (c) that same press re-derives the MASTER (row 0) the card displays
    if src.count("RequestUISync()") < 1:
        fail("live-control",
             "the TH source rows change the master row another surface displays but never "
             "ask the UI layer to repaint it (P-UI-40's asymmetry)")
        return
    ok("live-control", "a TH source row writes the mode both ways and repaints the master")


def check_custom_price_mode(o):
    """P-UI-45/48 - the custom price line has ONE creator, ONE exit owner and ONE
    selection owner, and it is ALWAYS grabbable.

    Three reported defects, one shape: a state that outlives the gesture that set it.
      * The ring's PIN item could switch the custom price ON and never OFF - every
        press re-armed (delete the line, re-create it at the market price), so the
        only exit was the ESC key; the ESC branch carried that exit INLINE, so the
        button could not reach it even in principle.
      * The line was created SELECTABLE **and** SELECTED. MT4 moves the SELECTED
        object on EVERY later drag anywhere on the chart, so a settled line fought
        the panels, the cards and the BaseKnot boxes and kept re-anchoring the TH
        start price behind the user's back.
      * P-UI-45 answered that by making a SETTLED line non-SELECTABLE - and
        SELECTABLE is the drag itself, so the user's next report was "it used to
        move". The interference was never selectability; it was the selection that
        outlived its gesture (the old code wrote `SELECTED = true` at creation, so
        the line was in that state BEFORE any gesture of its own).

    The invariants, all of them decisions already made:
      * ONE owner leaves the mode (line + GVars + the Input default start point) and
        BOTH the ESC key and the button's OFF press route through it;
      * the button moves the mode in BOTH directions;
      * ONE creator writes the pair - SELECTABLE **true** (the drag) and SELECTED
        **false** - and no other site writes either flag;
      * ONE owner drops the selection, called from both gesture-end triggers (the
        button-up mouse move, which never arrives on a motionless release, and the
        click finalizer) and from the UI press guard, so a press a panel or the
        ring owns cannot leave MT4 holding the line;
      * the clear never runs MID-drag (that event is continuous while the user is
        holding the line, and the drag is what selects it).
      * P-UI-51: nothing writes to the line while a gesture is live. The not-ours
        press DEFERS its clear (its hit test runs on the first move and only
        matches the terminal's own grab by accident), the carry holds off on the
        press edge's own move (where the frozen test is meaningless by
        construction), and the line's continuous drag event never resets the
        gesture flag that the press edge and the button-up own.
    """
    events = strip_comments(read(EVENTS, o))
    menu = strip_comments(read(MENU, o))

    owner = fn_body(events, "void DeactivateCustomPriceMode(")
    if not owner:
        fail("custom-price-mode",
             "DeactivateCustomPriceMode is gone: the mode has no owner to leave through")
        return
    for need, why in (("CleanupCustomPriceObjects(true, true)", "the line and its GVars"),
                      ("g_thStartPointType = inpTHStartPointType", "the Input default start point"),
                      ("g_customPriceKeyboardOverride = false", "the keyboard override")):
        if need not in owner:
            fail("custom-price-mode",
                 "the exit owner no longer restores %s: an exit that forgets half its "
                 "state leaves the next attach in the old mode" % why)
            return
    ok("custom-price-mode", "one owner turns the mode off (line + GVars + Input default)")

    if 'DeactivateCustomPriceMode("ESC")' not in events:
        fail("custom-price-mode",
             "the ESC key no longer routes through the owner: two exits drift apart")
        return
    ok("custom-price-mode", "the ESC key is that same owner, not a copy of it")

    branch = fn_body(menu, "if(tfeat == CIR_PIN)")
    if not branch:
        fail("custom-price-mode", "the PIN branch is gone: this check lost its anchor")
        return
    if "DeactivateCustomPriceMode(" not in branch:
        fail("custom-price-mode",
             "the PIN button only ARMS again: it can be switched ON and never OFF (the "
             "reported bug) and the only exit is the keyboard")
        return
    if "g_waitingForCustomPriceClick = true;" not in branch:
        fail("custom-price-mode", "the PIN button lost its ON direction")
        return
    ok("custom-price-mode", "the PIN button moves the mode in BOTH directions")

    helper = fn_body(_code_only(events), "bool CreateCustomPriceLine(")
    if not helper:
        fail("custom-price-mode", "CreateCustomPriceLine is gone")
        return
    if "OBJPROP_SELECTABLE, true" not in helper:
        fail("custom-price-mode",
             "the creator no longer makes the line GRABBABLE: SELECTABLE is the drag itself, "
             "and a line nothing can grab is the regression this group now locks - the "
             "reported interference was a SELECTION that outlived its gesture, not "
             "selectability")
        return
    if "OBJPROP_SELECTED, false" not in helper:
        fail("custom-price-mode",
             "the creator pre-selects the line: MT4 then moves it on EVERY later drag, "
             "which is the interference this cycle removes")
        return
    ok("custom-price-mode", "the creator makes the line always grabbable, never pre-SELECTED")

    # P-UI-50: the creator's own clear must be a COMPARE-AND-WRITE that stands down
    # for the whole duration of a gesture. It is reached from the click that confirms
    # the price, and that click can arrive while the button is still DOWN: an
    # unconditional write there rewrites the object MT4 is dragging and cancels the
    # drag (P-BK-15) - which is the "the drag is cut off very quickly" report.
    if not re.search(r"if\(!g_customPriceLineDragging && !g_customPriceNativeDrag &&[^;]*?"
                     r"ObjectSetInteger\(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false\);",
                     helper, re.S):
        fail("custom-price-mode",
             "the creator clears a live selection again: it must skip the write while a gesture "
             "owns the line (g_customPriceLineDragging / g_customPriceNativeDrag), or the "
             "confirming click rewrites the object MT4 is dragging and cancels that drag "
             "(P-BK-15)")
        return

    # ONE creator and ONE clear owner. The property set used to exist FIVE times
    # (the C key, the chart click, the TF-lock restore, the ring PIN and the
    # helper) and every copy was a chance to leave the stale selection behind -
    # which is how it survived a fix that had already been reasoned about.
    code_ev = _code_only(events)
    if len(re.findall(r"OBJPROP_SELECTABLE", code_ev)) != 1:
        fail("custom-price-mode",
             "the line's SELECTABLE flag is written in more than one place: one creator, or "
             "the copies drift apart")
        return
    # P-UI-49d: SELECTED *true* may exist in exactly ONE place - the user's own
    # grab. git is explicit about this one: the drag was never a per-object
    # native drag, the line was created SELECTED and MT4 moves the SELECTED
    # object on each mouse move (3a288fb removed that write and nothing replaced
    # the movement - the line stopped moving and still does). A CREATION or
    # RESTORE site that selects the line is the P-UI-45 interference: MT4 then
    # moves it with every later drag anywhere on the chart.
    grabs = re.findall(r"ObjectSetInteger\(0,\s*g_customPriceHorizontalLineName,\s*OBJPROP_SELECTED,\s*true\);",
                       code_ev)
    if len(grabs) != 1:
        fail("custom-price-mode",
             "expected exactly ONE `OBJPROP_SELECTED, true` - the grab on the press edge that "
             "lands on the line - and found %d. Selecting it at creation/restore is the "
             "interference (MT4 moves a SELECTED object with every later drag), and selecting "
             "it nowhere is the regression: nothing moves the line at all" % len(grabs))
        return
    mm = fn_body(code_ev, "if(id == CHARTEVENT_MOUSE_MOVE && g_customPriceLineCreated)") or ""
    if "OBJPROP_SELECTED, true" not in mm:
        fail("custom-price-mode",
             "the SELECTED, true write left the mouse-move press edge: the line is only "
             "selected from somewhere that is not the user's own grab")
        return
    # P-UI-51: a press the hit test did NOT recognize must DEFER the clear, never
    # write it inline. That test runs on the first MOVE after the press - already a
    # few pixels away from it and further the faster the drag starts - so it can
    # miss a press the TERMINAL did pick up; and the clear only ever writes while
    # OBJPROP_SELECTED is true, i.e. exactly when the terminal is holding the line.
    # Writing it there dropped MT4's own selection out of the drag that same press
    # had just started: "the drag state is cut off very quickly".
    not_ours = re.search(r"else if\(pressEdge\)\s*\{(.*?)\n\s*\}", mm, re.S)
    if not not_ours:
        fail("custom-price-mode",
             "the mouse-move press edge lost its not-ours branch: a press that starts somebody "
             "else's gesture leaves the line SELECTED through it, and MT4 moves every selected "
             "object with that drag (the reported interference)")
        return
    if "ClearCustomPriceSelection();" in not_ours.group(1):
        fail("custom-price-mode",
             "a press the hit test did not recognize clears the line's selection INLINE again: "
             "that write only ever fires while the terminal IS holding the line (the clear "
             "owner's guarded read), so it drops MT4's own selection out of the drag that same "
             "press started - arm g_customPriceNativeDrag and let the button-up drain it")
        return
    if "g_customPriceNativeDrag = true;" not in not_ours.group(1):
        fail("custom-price-mode",
             "the not-ours press no longer defers the clear either: the line then stays SELECTED "
             "through the foreign gesture (pan/box/ring/card) and MT4 moves it with that drag")
        return
    if "CustomPriceGrabAt(" not in code_ev or "g_customPriceDragOwn = true;" not in code_ev:
        fail("custom-price-mode",
             "the gesture lost its own grab and carry: a press the terminal never grabs must "
             "still move the line (own hit test + absolute cursor carry, P-BK-16's shape)")
        return
    # P-UI-51: and that carry must hold off on the press edge's OWN move - the one
    # event where the line's price equals the grab price by definition, so the
    # frozen test cannot tell an engaged terminal drag from a frozen one.
    # P-UI-51/P-UI-55: the carry's fence, in one place - it must skip the press
    # edge's own move (where the frozen test is meaningless), require real TRAVEL,
    # and have a valid press latch to move FROM.
    if "if(g_customPriceDragOwn && !pressEdge && pastSlop && currentLinePrice > 0 &&" not in mm \
       or "s_ownGrabY = (int)dparam;" not in mm:
        fail("custom-price-mode",
             "the carry lost its fence: it must skip the press edge (a write on the object MT4 "
             "just grabbed cancels that drag, P-BK-15), require travel past CP_DRAG_SLOP (the "
             "one-pixel jitter of a CLICK otherwise writes the line's price, so a click moves "
             "every level) and own a press latch")
        return
    if "double wishPrice = s_ownGrabPrice + (cursorPrice - s_ownGrabCursorPrice);" not in mm:
        fail("custom-price-mode",
             "the carry is absolute-to-cursor again: it copies the press TOLERANCE offset onto "
             "the PRICE, so a gesture that was not aimed at the line snaps it onto the cursor "
             "and the levels jump under the user ('I clicked and the levels landed elsewhere'); "
             "move the grab price by the cursor's TRAVEL instead - the BaseKnot box's rule")
        return
    # P-UI-53: the gesture OWNS THE VIEW. A live chart scroll / context menu / autoscroll
    # under a native object drag slides the price scale, and MT4 answers that by moving
    # the dragged line against a rebased price - the jump/die the drag report describes.
    # One taker (the grab), one re-assert per throttled step on BOTH event channels, one
    # release on the button-up move, out-of-band heal for the release that never arrives.
    if "CustomPriceDragLockOn();" not in mm or "CustomPriceDragLockOff();" not in mm:
        fail("custom-price-mode",
             "the drag no longer takes / hands back the view lock: the chart pans under the "
             "dragged line and the line is moved against the rebased price scale")
        return
    # (`od` is bound further down this check; the drag handler's own body is needed
    # here to prove the SECOND event channel re-asserts too.)
    dragb = fn_body(code_ev, "if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_customPriceHorizontalLineName)") or ""
    # P-UI-61: the re-assert and the frame are ONE owner's job now, and both event
    # channels reach them through it - so the two channels cannot drift apart, and a
    # third writer (a closing panel, a watchdog restore, a template reset) still
    # cannot flip the props back while the button is down (P-BK-14's rule, on the line).
    frame_owner = fn_body(code_ev, "void CustomPriceDragFrame(")
    if not frame_owner or "CustomPriceDragReassertLock();" not in frame_owner:
        fail("custom-price-mode",
             "the drag's frame owner is gone or no longer re-asserts the view lock: the chart "
             "pans under the dragged line and the line is moved against the rebased scale")
        return
    if code_ev.count("CustomPriceDragReassertLock();") != 1:
        fail("custom-price-mode",
             "the view lock has more than one re-assert site again: one gesture, two event "
             "channels, one lock - a second site is a second budget")
        return
    # `mm` legitimately holds the live-follow frame plus the two release-settle paths;
    # the invariant is that NEITHER channel reaches the heavy pass directly, and that the
    # native-drag channel (which has no other frame caller) goes through the owner once.
    if mm.count("CustomPriceDragFrame(") < 1 or dragb.count("CustomPriceDragFrame(") != 1 or \
       "RedrawAllObjects(" in (mm + dragb):
        fail("custom-price-mode",
             "an event channel calls the heavy pass directly again instead of going through "
             "the drag's ONE frame owner: two budgets on one stamp, and the channel that "
             "skips the owner is the one whose frame gets dropped")
        return
    # P-UI-54: the RELEASE may not wipe. MT4 selects the line on the press that
    # clicks it, so this gesture also runs for a plain CLICK - and a wipe is
    # ClearAllLevels + the four-frame staged rebuild of the whole family. The
    # release must ask whether the gesture MOVED anything and settle in place.
    if "g_forceClearOnNextDraw = true;" in mm:
        fail("custom-price-mode",
             "the drag release force-clears again: MT4 selects the line on the press that "
             "CLICKS it, so every click the user makes runs ClearAllLevels + the staged "
             "rebuild of the whole family - the reported flicker. A wipe answers a TOPOLOGY "
             "change (start-point type / mode / timeframe), never a price")
        return
    if "bool movedByGesture" not in mm or "if(movedByGesture)" not in mm:
        fail("custom-price-mode",
             "the release no longer asks whether the gesture moved the line: it settles "
             "unconditionally, which is either the click-flicker (a wipe) or a frame spent "
             "on a picture that never changed")
        return
    heal = fn_body(code_ev, "void CustomPriceDragHealStale()")
    calcb = fn_body(code_ev, "int OnCalculateHandler(")
    deinitb = fn_body(code_ev, "void OnDeinitHandler(")
    # P-UI-73: the probe is still required, but it must be THE OWNER's
    # (`UILeftButtonUp`, conservatively TRUE only when both MQL4 conventions
    # agree the button is free) - a local spelling is what the owner exists to
    # remove, and the heal is exactly the site where a wrong "up" reading tears a
    # live gesture down.
    if not heal or ("UILeftButtonUp()" not in heal and "TERMINAL_KEYSTATE_LEFT" not in heal):
        fail("custom-price-mode",
             "the stale-gesture heal is gone or lost its button probe: a release that emits no "
             "mouse move (off-window, lost focus - the P-BK-03 trap) then leaves the chart "
             "locked until the next attach")
        return
    if "TERMINAL_KEYSTATE_LEFT" in heal:
        fail("custom-price-mode",
             "the stale-gesture heal probes TERMINAL_KEYSTATE_LEFT by itself again: the two "
             "MQL4 readings (`<0` vs bit 0) disagree, so a local probe can report \"up\" in "
             "the middle of a live drag and tear the gesture down - ask UILeftButtonUp() "
             "(P-UI-73)")
        return
    if "CustomPriceDragHealStale();" not in (calcb or "") \
       or "CustomPriceDragLockOff();" not in (deinitb or ""):
        fail("custom-price-mode",
             "the lock lost its watchdog or its OnDeinit release: a chart left with scroll "
             "disabled is the reported 'the chart is locked'")
        return
    if len(re.findall(r"OBJPROP_SELECTED, false", code_ev)) != 2:
        fail("custom-price-mode",
             "the SELECTED flag is not the creator/clear-owner pair (expected exactly two "
             "writes, both false)")
        return

    # P-UI-50: the grab's hit test must use a conversion MT4 actually performs.
    # `ChartTimePriceToXY(0, 0, 0, ...)` is refused with time = 0, so the first
    # version of this test could never fire - zero "grab hit-test" grabs in a whole
    # session of drags - and the drag lived or died by the terminal's own pick-up.
    grab_at = fn_body(code_ev, "bool CustomPriceGrabAt(")
    if not grab_at:
        fail("custom-price-mode", "CustomPriceGrabAt is gone: this check lost its anchor")
        return
    if "ChartXYToTimePrice(" not in grab_at or "inpCustomPriceLevelWidth" not in grab_at:
        fail("custom-price-mode",
             "the grab hit test no longer converts the cursor (ChartXYToTimePrice) or lost its "
             "pixel tolerance: the terminal does not always pick the line up on the press "
             "(P-BK-16), so a hit test that cannot fire leaves the whole drag to that pick-up")
        return
    if "ChartTimePriceToXY(0, 0, 0" in code_ev:
        fail("custom-price-mode",
             "a conversion with time = 0 is back: MT4 refuses ChartTimePriceToXY with an empty "
             "time, so the test that depends on it silently never fires")
        return

    clear = fn_body(code_ev, "void ClearCustomPriceSelection()")
    if not clear or "g_customPriceLineCreated) return" not in clear \
       or "OBJPROP_SELECTED)" not in clear or "OBJPROP_SELECTED, false" not in clear:
        fail("custom-price-mode",
             "ClearCustomPriceSelection is gone or lost its guarded read / its write: the "
             "selection has no single owner to die in")
        return
    ok("custom-price-mode", "one creator writes the pair, one owner clears the selection")

    # The arming must sit in the line's OWN two handlers (the click that may have
    # selected it, and its native drag); a bare count would also be satisfied by
    # new arming sites elsewhere, and a dropped trigger has to keep failing.
    oc = fn_body(events, "if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_customPriceHorizontalLineName)")
    od = fn_body(events, "if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_customPriceHorizontalLineName)")
    armed = bool(oc) and bool(od) and "g_customPriceNativeDrag = true;" in oc \
            and "g_customPriceNativeDrag = true;" in od
    cleared = re.search(r"if\(g_customPriceNativeDrag\)\s*\{[^}]*\}", events, re.S)
    if not armed or not cleared or "g_customPriceNativeDrag = false;" not in cleared.group(0) \
       or "ClearCustomPriceSelection();" not in cleared.group(0):
        fail("custom-price-mode",
             "the gesture's selection is not dropped on button-up (armed in the native drag AND "
             "in the click handler, cleared once through the owner): a SELECTED line is moved "
             "by MT4 on every later drag")
        return
    # P-UI-51: the gesture flag is owned by the press edge and the button-up, never
    # by this CONTINUOUS event. Clearing it here re-armed the carry's reference on
    # every step of the drag (see the carry check above), which is how our own
    # writes ended up in the middle of MT4's own drag. Two writers of one gesture
    # flag is the shape that produced this whole cycle.
    if "g_customPriceLineDragging = false;" in od:
        fail("custom-price-mode",
             "the line's own drag handler resets the gesture flag again: this event is "
             "CONTINUOUS while MT4 drags the line, so the mouse-move grab block re-runs and "
             "re-arms the carry's reference on every step - its frozen test then compares the "
             "price with itself, always passes, and rewrites the object MT4 is dragging, "
             "which P-BK-15 answers by cancelling that drag")
        return
    panels = strip_comments(read(PANELS, o))
    # P-UI-49b: the finalizer must DEFER (arm the latch), never clear inline. It
    # is reached from CHARTEVENT_CLICK / CHARTEVENT_OBJECT_CLICK, and one of the
    # two arrives on the PRESS that grabs a selectable object - a write here
    # drops the terminal's selection out of the drag that same press started
    # ("the drag state is cut off very quickly"), and the domain's own click
    # handler had just deferred the same clear in that very event.
    fin = fn_body(panels, "void ChartPointerFinalizeOnUps()") or ""
    if "ClearCustomPriceSelection();" in fin:
        fail("custom-price-mode",
             "the button-up finalizer clears the line's selection INLINE again: it is reached "
             "from the same click event the domain handler defers for, so on the press that "
             "grabs the line the write drops MT4's own selection out of the drag it just "
             "started - arm g_customPriceNativeDrag instead")
        return
    if "g_customPriceNativeDrag = true;" not in fin:
        fail("custom-price-mode",
             "the finalizer no longer defers the clear either: a motionless release emits no "
             "mouse move, so the button-up that ends a grab must still arm the latch")
        return
    if "if(pressStart && g_DragOwner != DRAG_NONE) ClearCustomPriceSelection();" not in panels:
        fail("custom-price-mode",
             "the UI press guard is gone: a press a panel or the ring owns can leave MT4 "
             "holding the line, which is the interference the user reported")
        return
    # The fourth trigger: MT4 gives the BaseKnot boxes their drag the SAME way
    # (SELECTABLE is the box handle) and moves EVERY selected object, so a box
    # drag must drop the line's selection - and the line's own drag must be
    # excluded by name, because that selection is what drives the live update.
    drag = fn_body(panels, "if(id == CHARTEVENT_OBJECT_DRAG)")
    if not drag or "if(sparam != g_customPriceHorizontalLineName) ClearCustomPriceSelection();" not in drag:
        fail("custom-price-mode",
             "a native drag of somebody else's object no longer clears the line's selection: "
             "dragging a BaseKnot box then moves the line with it (MT4 drags every selected "
             "object), which is the interference the user reported")
        return
    # P-UI-49: the line's OWN drag handler must not WRITE to the line. That
    # handler runs on EVERY step of a native drag, and MT4 cancels an
    # in-progress native drag when the dragged object is rewritten mid-gesture
    # (P-BK-15, learned on the BaseKnot box) - the tooltip write that used to
    # sit there cancelled the very gesture it was decorating, which is why the
    # line stopped following the cursor once the movement moved from the
    # SELECTION onto this drag. The tooltip has ONE owner and it is called from
    # the release, where the button is already up.
    own = fn_body(code_ev,
                  "if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_customPriceHorizontalLineName)")
    if not own:
        fail("custom-price-mode",
             "the line's own drag handler is gone: this check lost its anchor")
        return
    if re.search(r"ObjectSet(?:Integer|Double|String)\(0,\s*g_customPriceHorizontalLineName", own):
        fail("custom-price-mode",
             "the line is written from inside its own drag handler: MT4 cancels an "
             "in-progress native drag when the dragged object is rewritten mid-gesture "
             "(P-BK-15), so the line stops following the cursor - the reported "
             "'cannot be dragged'")
        return
    tip = fn_body(code_ev, "void UpdateCustomPriceTooltip()")
    if not tip or "OBJPROP_TOOLTIP" not in tip or "g_customPriceHorizontalLineName" not in tip:
        fail("custom-price-mode",
             "the drag tooltip text lost its one owner (UpdateCustomPriceTooltip must be "
             "the only writer of the line's tooltip)")
        return
    mov = fn_body(code_ev, "if(id == CHARTEVENT_MOUSE_MOVE && g_customPriceLineCreated)")
    if code_ev.count("UpdateCustomPriceTooltip();") != 1 or not mov \
       or "UpdateCustomPriceTooltip();" not in mov:
        fail("custom-price-mode",
             "the tooltip is no longer written from the RELEASE path: it must have exactly "
             "one caller, inside the button-up branch of the drag's own mouse-move handler")
        return
    ok("custom-price-mode",
       "the selection dies on button-up, on a UI press, and under any foreign native drag; "
       "the dragged line is never written to (P-BK-15)")


def check_drag_anchor(o):
    """P-UI-61 - THE DRAG'S ANCHOR IS STATE, NOT WORK: IT MAY NOT SIT INSIDE THE THROTTLE.

    Reported: «درگ خط کاستوم پرایس روان نیست و لگ داره، و وقتی خط را رها میکنم سطوح از
    یک جای دیگه رسم میشن، همون سطوح نیستن».

    One defect, two symptoms. The whole ladder is derived from one value
    (`g_customTHStartPrice` -> `GetMidpointPrice` -> `midpointPrice`), and the drag
    wrote it INSIDE its redraw gate:

        if(nowMs - g_lastDragRedrawTime > DRAG_REDRAW_THROTTLE_MS)
        { g_customTHStartPrice = currentLinePrice; RedrawAllObjects(true); ... }

    so the LINE kept up with the cursor (MT4 moves it, our carry writes it) while the
    ANCHOR advanced at the window's rate: the ladder trailed the line by an amount
    that depended on when the release happened, and every event inside a window was
    DROPPED rather than owed. At the release the disagreement became a rebuild from
    the wrong price: the frame re-resolves the source from the PERSISTED key, and the
    carry channel never persisted, so that key held a PRE-GESTURE price and the
    frame's `priceMoved` branch overwrote the gesture's result with it - the ladder
    was drawn neither under the line nor where the picture had been.

    The invariants, all of them decisions rather than details:
      * the anchor has ONE writer during a gesture, it persists through the P-UI-56
        writer (so the resolver can never disagree with it), and a price that did not
        move costs one compare and nothing else;
      * the heavy pass has ONE caller from the drag, and the throttle lives INSIDE it
        (a refused frame is owed, never silently dropped);
      * no assignment to the anchor may sit inside a throttle gate again;
      * the release settles from the OBJECT - the one value MT4 keeps exact - through
        the same owner, and forces the frame, while a click that moved nothing still
        owes nothing (P-UI-54).
    """
    code_ev = _code_only(read(EVENTS, o))
    owner = fn_body(code_ev, "bool CustomPriceDragAnchorSet(")
    if not owner:
        fail("drag-anchor", "CustomPriceDragAnchorSet is gone: the drag's anchor has no owner again")
        return
    if "g_customTHStartPrice = price;" not in owner:
        fail("drag-anchor", "the drag-anchor owner no longer writes the anchor it is named for")
        return
    if "CustomPricePersistPlacement(" not in owner:
        fail("drag-anchor",
             "the drag-anchor owner does not persist: the frame's resolver then reads a key "
             "older than the anchor and RE-ANCHORS the settle to it - the whole ladder is "
             "rebuilt at a price the cursor was never at (the reported jump on release)")
        return
    mm = fn_body(code_ev, "if(id == CHARTEVENT_MOUSE_MOVE && g_customPriceLineCreated)") or ""
    dragb = fn_body(code_ev, "if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_customPriceHorizontalLineName)") or ""
    handlers = mm + "\n" + dragb
    if handlers.count("g_customTHStartPrice =") != 0:
        fail("drag-anchor",
             "a drag handler writes the anchor itself again: that is how the value sat inside "
             "the redraw gate, and the ladder then trails the line by a whole window")
        return
    if mm.count("CustomPriceDragAnchorSet(") != 2 or dragb.count("CustomPriceDragAnchorSet(") != 1:
        fail("drag-anchor",
             "one of the two event channels stopped routing its anchor through the owner (the "
             "mouse-move channel has the live follow AND the release settle), so its price can "
             "lag - or persist - on a different schedule than the other")
        return
    ok("drag-anchor", "the anchor has one writer, it persists with the value, and both channels use it")

    # The throttle is a FRAME budget, never a state gate, and it belongs to one owner.
    owner_frame = fn_body(code_ev, "void CustomPriceDragFrame(")
    if not owner_frame or "DRAG_REDRAW_THROTTLE_MS" not in owner_frame:
        fail("drag-anchor",
             "the drag's frame budget is gone from the frame owner: the two channels run "
             "their own heavy passes again")
        return
    if code_ev.count("g_lastDragRedrawTime") != 2:
        fail("drag-anchor",
             "the drag's frame stamp is touched outside its one owner (expected exactly the "
             "compare and the store inside CustomPriceDragFrame)")
        return
    if re.findall(r"DRAG_REDRAW_THROTTLE_MS[^\n]*\n[^\n]*RedrawAllObjects\(", code_ev):
        fail("drag-anchor",
             "a heavy pass is gated on DRAG_REDRAW_THROTTLE_MS outside the frame owner again: "
             "a refused frame is then DROPPED instead of owed, and the release settles from a "
             "price the gesture has already left behind")
        return
    ok("drag-anchor", "the frame budget lives in one owner, and no frame is dropped on a throttled step")

    if "double settledPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);" not in mm:
        fail("drag-anchor",
             "the release no longer reads the line's own price: it settles from our throttled "
             "copy instead, which is the price the gesture had already left behind")
        return
    # The MOVED branch must force (the picture that is on screen must be the last one the
    # gesture produced, whatever the window did) - matched structurally, because
    # `_code_only` has already stripped the trailing comment that reads it out loud.
    if not re.search(r"if\(movedByGesture\)[^}]*CustomPriceDragFrame\(true\)", mm, re.S):
        fail("drag-anchor",
             "the release does not FORCE the frame from the moved branch: the gesture's last "
             "pixel is then only painted if the 50 ms window happened to be open, which is the "
             "reported 'the levels land somewhere else when I let go'")
        return
    if "CustomPriceDragFrameOwed()" not in mm:
        fail("drag-anchor",
             "the release no longer settles a frame the throttle refused: a refused frame is "
             "owed work, and nothing else would paint it before the next tick")
        return
    ok("drag-anchor", "the release settles from the object, forces the frame, and still owes a click nothing")


def check_custom_price_source(o):
    """P-UI-56/57/58 - the custom-price SOURCE, the NaN fence and the zone gap.

    Reported: «چرا سطوح سرجای خودشون نیستن، هر دفعه یک جایی دیگه میره … حتماً نگاه
    کن منبع رسم قیمت چطوریه». Every level of every mode is anchored on
    `GetMidpointPrice(g_thStartPointType)` → `g_customTHStartPrice`, so that value
    IS the drawing source, and it had two defects that only show on a chart in use:
      * the placement was persisted under the SYMBOL instead of the CHART, so every
        chart of one symbol shared ONE price - a gesture on one moved the ladder of
        the others (the user runs five charts over two symbols);
      * the frame path's Input branch WROTE the placement keys, so a price the user
        had dragged to was replaced by the Input's value.
    The chain also existed twice (init + frame), i.e. two copies to keep in step.

    The invariants, all of them decisions already made:
      * ONE owner names the keys, and the live pair is CHART-scoped;
      * ONE resolver answers "what is the custom price of this chart?" for BOTH
        call sites, and no site outside the owner names a key;
      * every placement path persists through the ONE writer;
      * a non-finite value cannot enter the level arithmetic (`<= 0` is NaN-blind),
        can not become a pip DENOMINATOR, and cannot let a zone band reach the line
        family it sits beside (P-UI-58's minimum gap).
    """
    events = _code_only(read(EVENTS, o))
    menu = _code_only(read(MENU, o))

    start = events.find("string CustomPriceGVName()")
    end = events.find("    return CPSRC_NONE;\n}")
    if start < 0 or end < 0:
        fail("custom-price-source",
             "the P-UI-56 owner block is gone: the drawing price has no owner again")
        return
    owner = events[start:end]
    outside = events[:start] + events[end:]

    if '"Biotak_CustomPrice_" + GetCachedChartIdStr()' not in owner:
        fail("custom-price-source",
             "the live price key is no longer CHART-scoped: every chart of a symbol then "
             "shares one custom price, and touching one moves the levels of the others")
        return
    if '"Biotak_CustomPriceOverride_" + GetCachedSymbol()' not in owner:
        fail("custom-price-source",
             "the legacy symbol-scoped keys are no longer named: a chart drawn by an older "
             "build would silently lose the price it had placed (no migration)")
        return
    for key in ('"Biotak_CustomPrice_', '"Biotak_CustomPriceOverride_'):
        if key in outside:
            fail("custom-price-source",
                 "a custom-price key is named outside the owner (%s): that is a second "
                 "writer of the drawing price, and the copies drift" % key)
            return
    if '"Biotak_CustomPrice_' in menu or '"Biotak_CustomPriceOverride_' in menu:
        fail("custom-price-source",
             "the ring's PIN item builds a custom-price key by hand again: the placement "
             "must go through the one writer (chart-scoped keys)")
        return
    ok("custom-price-source", "one owner names the keys, and the live pair is chart-scoped")

    if events.count("CustomPriceResolveSource(") != 3:
        fail("custom-price-source",
             "the source is not resolved by exactly ONE function called from the TWO known "
             "sites (definition + init + frame): a third copy of the precedence chain is "
             "how init and the frame path disagreed about the same chart")
        return
    if "if(g_customPriceKeyboardOverride && savedPrice > 0.0)" in events:
        fail("custom-price-source",
             "the old inline three-branch chain is back next to the resolver: two "
             "precedences for one value")
        return
    ok("custom-price-source", "one resolver answers for both call sites (init + frame)")

    if events.count("CustomPricePersistPlacement(") != 5:
        fail("custom-price-source",
             "a placement path stopped persisting through the ONE writer (expected the "
             "definition + 4 call sites: C key, chart-click confirm, line double-click, drag)")
        return
    if menu.count("CustomPricePersistPlacement(") != 1:
        fail("custom-price-source",
             "the ring's PIN press no longer persists through the ONE writer")
        return
    ok("custom-price-source", "every placement path persists through the one writer")

    levels = fn_body(read(PIPELINE, o), "int CalculateLevels(")
    if not levels or "MathIsValidNumber(centerPrice)" not in levels or \
       "MathIsValidNumber(stepSizes[s])" not in levels:
        fail("custom-price-source",
             "CalculateLevels lost its NaN fence: `<= 0` cannot see NaN (every comparison "
             "against it is false), so one poisoned price becomes a chart full of NaN levels")
        return
    common = fn_body(read(EVENTS, o), "bool CalculateCommonStepData(")
    if not common or "MathIsValidNumber(dailyClosePrice)" not in common or \
       common.count("MathIsValidNumber(data.") < 4:
        fail("custom-price-source",
             "CalculateCommonStepData stopped validating the base price / step values: the "
             "frame then derives every level from a non-finite number")
        return
    pip = fn_body(read(PERFOPT, o), "double GetCachedPipSize()")
    if not pip or "g_cachedPipSize = (p > 0.0 && MathIsValidNumber(p)) ? p : 0.00001;" not in pip:
        fail("custom-price-source",
             "GetCachedPipSize lost its zero-divide fence: pip size is a DENOMINATOR in every "
             "pip figure, and Point is 0 on a symbol whose data is not loaded yet")
        return
    ok("custom-price-source", "NaN / zero-divide fenced at the three numeric owners")

    builder = fn_body(read(PIPELINE, o), "void BuildZonesAndLines(")
    if not builder or builder.count("ClampZoneHalfHeight(") != 1 or \
       "double zoneHeight = zoneStepSize * config.zoneHeightPercent * 0.5;" in builder:
        fail("custom-price-source",
             "a zone band is built without the minimum-gap clamp: a band whose half-height "
             "reaches half the interval touches (and then swallows) the line it sits beside")
        return
    # P-UI-59: ONE of the two intervals is not enough. A zone has a midpoint line on
    # BOTH of its sides and in SS/LS mode those intervals differ (the steps alternate
    # short/long), so a band clamped by the long side still reaches the short side's
    # line: at 100% height the band half is `ss/2` and the ss line is exactly `ss/2`
    # away - on the band edge, i.e. rendered inside it. Both build branches therefore
    # pass the interval they sit in AND the one beyond the level.
    # The two build branches must BOTH pass the interval they sit in AND the one
    # beyond the level - an argument of 0 ("no neighbour") is the one-sided clamp
    # wearing the new name, so the arguments are matched, not the call.
    if builder.count("ClampZoneHalfHeightBoth(") != 2 or \
       "stepSize, stepAbove);" not in builder or "stepBelow, stepSize);" not in builder:
        fail("custom-price-source",
             "a zone band is clamped by only ONE of its two intervals again: in SS/LS the "
             "band then reaches the midpoint line of its shorter side and swallows it")
        return
    ok("custom-price-source", "every zone band keeps a minimum gap from the line family")


def check_edge_look(o):
    """P-UI-63/64 - two transparencies with two owners, and the edge IS the boundary.

    Reported: «شفافیت خط و زون بشه جدا از هم تعیین کرد بهترین راهکار چیه که شلوغ هم نشه»
    and «در حالت ترکیب خطوط از هم جدا نباشه و همون لبه زون باشه، در حالت ترکیب خطوط
    سایز 5 باشن پیش فرض که دیده بشه».

    The BAND and its EDGE were blended with ONE number (`borderColor = finalColor`), so
    a crisp outline over a faded band was unrepresentable. The fix adds no card and no
    sub-card - the edge already had two rows (BORDER / BORDER WIDTH) in GEOMETRY, so its
    transparency is the third row of the same trio, next to them.

    Invariants:
      * each half of the picture has exactly ONE transparency owner (the card's
        TRANSPARENCY row for the band, BORDER TRANSPARENCY for the edge), saved and
        loaded under its own key;
      * the BAND is painted with `finalColor` and the EDGE with `borderColor` - the two
        values used to be the same, which is why the mix-up was invisible;
      * the edge is drawn ON the band's own boundary (same times and prices, ray-right
        like the rectangle) - there is no second, separately placed "line" for a zone;
      * a picture that DRAWS an edge never inherits the edge-less 1px default.
    """
    constants = _code_only(read("Biotak/ConstantsAndEnums.mqh", o))
    factory = _code_only(read(ZONEFACTORY, o))
    pipeline = _code_only(read(PIPELINE, o))
    extdraw = _code_only(read(EXTDRAW, o))
    util = _code_only(read(UTIL, o))
    unified = _code_only(read("Biotak/UnifiedZoneSystem.mqh", o))
    zoneread = _code_only(read("Biotak/ZoneRenderer.mqh", o))
    panels = _code_only(read(PANELS, o))
    runtime = _code_only(read(RUNTIME, o))

    if "g_midZoneBorderTransparency" not in runtime or \
       "#define inpMidZoneBorderTransparency g_midZoneBorderTransparency" not in runtime:
        fail("edge-look",
             "the edge has no transparency of its own again: one number for both halves "
             "is exactly what made the line and the zone impossible to set apart")
        return
    if 'RSSetNext(p + "ZBT", g_midZoneBorderTransparency);' not in runtime or \
       'GlobalVariableCheck(p + "ZBT")' not in runtime:
        fail("edge-look",
             "the edge's transparency is not persisted under its own key: the row would "
             "look live and be forgotten by the next attach")
        return
    ok("edge-look", "each half of the picture owns its transparency (own key, own row)")

    if "if(request.borderTransparency >= 0 && request.borderTransparency <= 100)" not in factory or \
       "edgeTransparency = request.borderTransparency;" not in factory:
        fail("edge-look",
             "the edge stopped blending with its own value: the band's number is being "
             "used for both halves again")
        return
    if "ObjectSetInteger(0, request.name, OBJPROP_COLOR, finalColor);" not in factory or \
       "ObjectSetInteger(0, request.name, OBJPROP_COLOR, borderColor);" in factory:
        fail("edge-look",
             "the BAND is painted with the EDGE's colour (they used to be the same value, "
             "so the mix-up was invisible - now it would paint the wrong one)")
        return
    if "cache.lastColor != finalColor" not in factory:
        fail("edge-look",
             "the band's change detection compares against the edge's colour: the band "
             "then never repaints when its ownrow moves")
        return
    ok("edge-look", "the band is painted and cached with its own blend, the edge with its")

    for where, src in (("the pipeline", pipeline), ("the Factor path", extdraw),
                       ("CreateGenericMidZone", util)):
        if "request.borderTransparency = inpMidZoneBorderTransparency;" not in src:
            fail("edge-look",
                 "%s no longer sets the edge's transparency: the field is read from a stack "
                 "struct, so the value would be whatever the stack held" % where)
            return
    if unified.count("request.borderTransparency = -1;") != 2 or \
       zoneread.count("request.borderTransparency = -1;") != 1:
        fail("edge-look",
             "a retired module left the edge's transparency unset instead of stating the "
             "fallback: a struct on the stack must never be trusted to be zeroed")
        return
    top = "startTime, request.topPrice, endTime, request.topPrice,"
    bottom = "startTime, request.bottomPrice, endTime, request.bottomPrice,"
    left = "startTime, request.bottomPrice, startTime, request.topPrice,"
    if factory.count(top) != 1 or factory.count(bottom) != 1 or factory.count(left) != 1 or \
       "ObjectSetInteger(0, request.name, OBJPROP_RAY_RIGHT, true);" not in factory:
        fail("edge-look",
             "the edge is not drawn on the band's own boundary any more (same times and "
             "prices, ray-right like the rectangle): any offset makes it a second, "
             "separately placed line - «خطوط از هم جدا نباشه و همون لبه زون باشه»")
        return
    ok("edge-look", "the edge is the zone's own boundary, and every producer sets its value")

    if "#define MIDZONE_EDGE_VISIBLE_WIDTH 5" not in constants:
        fail("edge-look",
             "the visible width for an edge picture is gone or is not 5: a 1px line under "
             "a translucent band is half-covered by it, so the combined picture reads as "
             "the filled one")
        return
    if "if(newPicture != ZONE_STYLE_BOX_FILLED && g_midZoneBorderWidth <= 1)" not in panels or \
       "g_midZoneBorderWidth = MIDZONE_EDGE_VISIBLE_WIDTH;" not in panels:
        fail("edge-look",
             "picking a picture that DRAWS an edge no longer brings a visible width: the "
             "user picks the combined picture and sees no line, which is the report this "
             "rule answers")
        return
    if 'label="BORDER TRANSPARENCY"' not in panels or \
       "g_midZoneBorderTransparency=ClampInt((int)MathRound(v),0,100)" not in panels:
        fail("edge-look",
             "the edge's transparency row or its writer is missing: «شلوغ نشه» was a "
             "constraint on the PLACEMENT (beside BORDER / BORDER WIDTH), not a reason "
             "to leave the control out")
        return
    ok("edge-look", "a picture with an edge arrives visible, and the row that owns it exists")


def check_zone_picture(o):
    """P-UI-62 - the zone picture is TWO bits, and a dead cache slot is not an object.

    Reported: «empy درست کار نمیکنه» and «به جای هیدن یک دکمه دیگه بزار … یک حالت دیگه
    بزا رکه هردو بشه تنظیم کرد هم خط و هر رنگ». Those are ONE defect. The style axis's
    third slot was HIDDEN - a second owner of the question the MID ZONES master switch
    already answers - and the picture itself was a single `filled` bit, so `filled ==
    false` had to mean both "edge only" and "no zones", the edge could not be drawn
    beside a band, and CreateZone's EMPTY path returned from ABOVE the read that would
    have removed the band:
      * FILLED -> EMPTY drew the three edge segments and left the rectangle in place;
      * the edge was never drawn (or never removed) when only that half moved;
      * BORDER / BORDER WIDTH had nothing to act on while the picture was FILLED,
        because OBJ_RECTANGLE ignores OBJPROP_STYLE/WIDTH.

    The invariants, all of them decisions already made:
      * slot 2 is a PICTURE (OUTLINED = band AND edge), never a visibility switch;
      * every producer sets BOTH bits, and the cache stores both plus whether the
        picture owns a rectangle under the zone's own name at all;
      * the band is created BEFORE its edge - an equal ZORDER paints in creation order,
        so the other order makes OUTLINED look exactly like FILLED;
      * a slot the cache cannot vouch for is never written to;
      * a layout that stored the retired HIDDEN value is translated ONCE.
    """
    constants = _code_only(read("Biotak/ConstantsAndEnums.mqh", o))
    cache = _code_only(read(OBJCACHE, o))
    factory = _code_only(read(ZONEFACTORY, o))
    pipeline = _code_only(read(PIPELINE, o))
    extdraw = _code_only(read(EXTDRAW, o))
    unified = _code_only(read("Biotak/UnifiedZoneSystem.mqh", o))
    visibility = _code_only(read(VISIBILITY, o))
    panels = _code_only(read(PANELS, o))
    runtime = _code_only(read(RUNTIME, o))

    if "ZONE_STYLE_BOX_OUTLINED = 2" not in constants:
        fail("zone-picture",
             "ENUM_ZONE_STYLE's third slot is not a picture any more: it must describe what "
             "the user SEES (band, edge, or both), because visibility belongs to the MID "
             "ZONES switch and a second owner for it is the reported defect")
        return
    owners = (("ConstantsAndEnums", constants), ("LevelPipeline", pipeline),
              ("ZoneFactory", factory), ("ExtendedDrawingFunctions", extdraw),
              ("UnifiedZoneSystem", unified), ("BiotakPanels", panels))
    for dead in ("ZONE_STYLE_HIDDEN", "TH3_ZONE_HIDDEN", "FACTOR_ZONE_HIDDEN"):
        for where, src in owners:
            if dead in src:
                fail("zone-picture",
                     "%s is back in %s: a style value that DELETES the zone family is a "
                     "second owner of \"are zones drawn?\", and it disagrees with the "
                     "switch directly above it in the card" % (dead, where))
                return
    ok("zone-picture", "slot 2 of the style axis is a picture, and the visibility alias is gone")

    if pipeline.count("zones[zIdx].filled  = (config.zoneStyle != ZONE_STYLE_BOX_EMPTY);") != 3 or \
       pipeline.count("zones[zIdx].outline = (config.zoneStyle != ZONE_STYLE_BOX_FILLED);") != 3:
        fail("zone-picture",
             "a zone definition is built from ONE bit again: each of the three build loops "
             "(midpoint + above + below) must set the band AND the edge, or a picture the "
             "card offers cannot be produced by the pipeline")
        return
    if "bool   outline;" not in pipeline or "request.outline = zones[i].outline;" not in pipeline:
        fail("zone-picture",
             "the second bit does not survive the trip from the definition to the drawing: "
             "the render then draws whatever the missing half defaults to")
        return
    if "bool outline;" not in factory or \
       "request.filled  = (zoneStyle != FACTOR_ZONE_BOX_EMPTY);" not in extdraw or \
       "request.outline = (zoneStyle != FACTOR_ZONE_BOX_FILLED);" not in extdraw:
        fail("zone-picture",
             "the request struct or the Factor producer still carries one bit: the Factor "
             "bands are the ones the user sees beside the mid zones")
        return
    if "request.filled  = (config.style != FACTOR_ZONE_BOX_EMPTY);" not in unified or \
       "request.outline = (config.style != FACTOR_ZONE_BOX_FILLED);" not in unified:
        fail("zone-picture",
             "the retired UnifiedZoneSystem producer still derives both halves from "
             "`style == FILLED`, so slot 2 would silently draw a band-only picture there")
        return
    ok("zone-picture", "every producer sets both halves of the picture")

    get = factory.find("bool inCache = CacheGetObject(request.name, cache);")
    skip = factory.find("if(!geometryChanged && !visualChanged) {")
    band = factory.find("ObjectCreate(0, request.name, OBJ_RECTANGLE")
    edge = factory.find('CreateOrUpdateZoneBorder(request.name + "_B_Top"')
    if min(get, skip, band, edge) < 0:
        fail("zone-picture",
             "CreateZone no longer reads the cache, returns early, creates the band and draws "
             "the edge in that order: the picture has to be resolved BEFORE any drawing path")
        return
    if not (get < skip < band < edge):
        fail("zone-picture",
             "CreateZone's order is wrong. The read must precede the early return (the EMPTY "
             "path used to return above it and left the band on the chart - the reported "
             "\"Empty does not work\"), and the band must be CREATED before its edge, "
             "because an equal ZORDER paints in creation order and the edge is the visible "
             "line: created first, it is covered by the band and OUTLINED looks like FILLED")
        return
    if "if(kindChanged)" not in factory or "cache.lastOutline != request.outline" not in factory:
        fail("zone-picture",
             "the migration is no longer gated on a KIND change of BOTH bits: on one bit "
             "FILLED and OUTLINED are the same state, so the edge half is never rebuilt")
        return
    if "DeleteIndicatorObjectManaged(request.name, true);" not in factory:
        fail("zone-picture",
             "an edge-only picture stopped removing the band it does not own (or vice versa): "
             "that leftover rectangle IS the reported Empty bug")
        return
    if "request.outline, request.filled);" not in factory:
        fail("zone-picture",
             "the cache no longer stores whether this picture owns a rectangle: the band path "
             "then probes the chart for a name that has none, on every frame, forever")
        return
    if factory.count("CacheForgetAbsent(request.name);") != 1:
        fail("zone-picture",
             "creating the band does not clear the negative mark the edge-only picture left on "
             "that name: `CacheIsAbsentKnown` then refuses a real delete and the rectangle is "
             "left behind - the same ghost, from the other direction")
        return
    ok("zone-picture",
       "the picture is resolved once, the band precedes its edge, and both halves migrate")

    if "bool CacheSlotIsLive(const int idx)" not in cache:
        fail("zone-picture",
             "the cache has no single answer for \"is this slot an object the chart carries?\": "
             "an occupied slot can describe a PICTURE (see SObjectCacheEntry.exists)")
        return
    if visibility.count("CacheSlotIsLive(i)") != 5:
        fail("zone-picture",
             "one of the FIVE visibility walks (all-TH hide/show, hide-all, show-all, the "
             "line family, the zone family) writes through a dead slot again: a mask write "
             "for a name the chart does not have is a terminal call that does nothing, on "
             "every full frame")
        return
    if "CacheSlotIsLive(i)" not in pipeline:
        fail("zone-picture",
             "the structure recolour walk repaints a dead slot again: the colour it finds "
             "there belongs to a PICTURE, not to an object")
        return
    if "if(!inCache && CacheIsAbsentKnown(name)) return false;" not in cache:
        fail("zone-picture",
             "the negative mark outranks a LIVE main-cache entry again: a name the chart "
             "really carries can then be refused by a mark proved while the picture had no "
             "band, and a live rectangle is never deleted")
        return
    ok("zone-picture", "a dead slot is never written to, and a live entry outranks a mark")

    if 'opts="Filled|Empty|Outlined"' not in panels:
        fail("zone-picture",
             "the ZONE STYLE row is not the three pictures any more (or still offers the "
             "retired visibility value): the row must set what is DRAWN, never whether the "
             "zone layer is drawn at all")
        return
    if 'if(ClampSettingInt((int)GlobalVariableGet(p + "MZ"), 0, 2) == 2)' not in runtime or \
       'g_showMidZones  = false;' not in runtime:
        fail("zone-picture",
             "a layout saved with the retired value is no longer adopted into the picture the "
             "user last saw: they would find their zones switched back on by the upgrade")
        return
    if 'GlobalVariableSet(p + "MZ", ZONE_STYLE_BOX_FILLED);' not in runtime or \
       'GlobalVariableSet(p + "ZO", 0.0);' not in runtime:
        fail("zone-picture",
             "the adopted value only exists in memory: a session that ends without a save "
             "reloads `MZ = 2` under the stamp and the migrated chart silently flips to "
             "OUTLINED")
        return
    if 'GlobalVariableSet(p + "MZ2", 1.0);' not in runtime or \
       '!GlobalVariableCheck(p + "MZ2")' not in runtime:
        fail("zone-picture",
             "the adoption is not stamped: 2 is a LEGAL value again (OUTLINED), so a user "
             "who deliberately picks it would be migrated a second time on the next start")
        return
    ok("zone-picture",
       "the card offers three pictures, and the retired value is adopted exactly once")


# The functions that run on the REMOVE teardown and are allowed to be counted as a
# delete owner. Every one of them is reached from `OnDeinit` through
# `CleanupUIStates` / `OnDeinitHandler` (see `check_delete_paths` for the order).
PURGE_OWNERS = (
    (GLOBALS, "void CleanupAllGlobalVariables()"),
    (MENU, "void ClearAllGVs()"),
    (MENU, "void CleanupUIStates("),
    (HTF, "void CleanupHTFCandlesGVs()"),
    (EVENTS, "void ClearTopologyAdoptionStamp()"),
    ("Biotak/BaseKnotTool.mqh", "void BaseKnotOnDeinit("),
)


def check_teardown_census(o):
    """P-UI-60 — NOTHING AN INSTANCE CREATED MAY OUTLIVE ITS REMOVAL.

    Reported: «پاکسازی درست انجام نمیشه … موقع حذف اندیکاتور تمام المانها باید پاک
    بشن و هیچی جا نمونه». A chart object is not the interesting half - MT4 drops an
    indicator's objects with it, and `check_delete_paths` already owns the    chart side. The half nothing watches is everything the indicator persists OUTSIDE the
    chart: the terminal's global-variable table, which survives the indicator, the chart
    AND the session. An orphan there is not cosmetic - the table is finite and a full
    one rejects new writes, which silently stops state persisting at all.

    The first real audit of this found exactly one family with no delete owner:
    the P-PERF-38c naming-migration stamp, written once per chart and never removed,
    i.e. one `Biotak_NameScheme_<chartId>` left in the terminal for the lifetime of
    the terminal for EVERY chart id the terminal had ever shown - including the ids
    of charts that no longer exist, which can never be looked up again. The gate is
    mechanical so the next one cannot hide: EVERY `Biotak_*` family literal in the
    sources must appear in the text of a teardown that runs on REASON_REMOVE, or be
    reachable through a delete owner defined in the same file (the accessor form,
    so the literal keeps its single owner instead of being spelled a second time).

    There is deliberately NO survivor list. A per-chart stamp must survive a
    timeframe switch - which is REASON_CHARTCHANGE, and the stamp is not touched
    there - but a REMOVAL empties the chart it describes, so nothing has a reason
    to outlive it. A family that needs an exemption is a design decision, and a
    design decision belongs in the check with its reason attached.
    """
    events = strip_comments(read(EVENTS, o))
    d = fn_body(events, "void OnDeinitHandler(const int reason)")
    if not d or "reason == REASON_REMOVE" not in d:
        fail("teardown-census", "OnDeinitHandler lost its REASON_REMOVE branch")
        return
    remove = d.split("reason == REASON_REMOVE", 1)[1].split("else if(reason == REASON_PARAMETERS", 1)[0]
    entry_od = fn_body(strip_comments(read(FULL, o)), "void OnDeinit(const int reason)")
    if not entry_od:
        fail("teardown-census", "the entry's OnDeinit is gone")
        return

    # A sweep that is merely DEFINED satisfies a census that only reads bodies, so
    # its call has to be reachable from the removal branch. The closure starts at
    # the removal branch (what runs on remove) plus the teardown that runs for EVERY
    # reason, and keeps pulling in the body of any owner whose call it can now see.
    reach = remove + "\n" + d + "\n" + entry_od
    purge = []
    pending = list(PURGE_OWNERS)
    while pending:
        progressed = False
        for item in list(pending):
            rel, sig = item
            name = sig.split("(")[0].split()[-1]
            if (name + "(") not in reach:
                continue
            body = fn_body(strip_comments(read(rel, o)), sig)
            if not body:
                fail("teardown-census",
                     "the delete owner %s is gone from %s: the families it swept are now "
                     "unreachable by any teardown" % (sig, rel))
                return
            pending.remove(item)
            purge.append(body)
            reach += "\n" + body
            progressed = True
        if not progressed:
            break
    if pending:
        fail("teardown-census",
             "these delete owners are never reached from the removal branch, so every family "
             "they sweep is left in the terminal's table: %s"
             % ", ".join(sorted(sig for _, sig in pending)))
        return
    purge_text = "\n".join(purge + [remove])

    families = {}
    for rel in sorted(glob.glob(os.path.join(ROOT, "Biotak", "**", "*.mqh"), recursive=True) +
                      glob.glob(os.path.join(ROOT, "*.mq4"))):
        rel = os.path.relpath(rel, ROOT).replace("\\", "/")
        for lit in re.findall(r'"(Biotak_[A-Za-z0-9]*_)"', read(rel, o)):
            families.setdefault('"%s"' % lit, set()).add(rel)
    if not families:
        fail("teardown-census", "no Biotak_* global-variable family found: the census is blind")
        return

    def _functions_naming(src, literal):
        """Functions whose body builds this literal (the accessor form)."""
        names = []
        for sig in re.findall(r'^(?:void|bool|int|double|string|long|datetime|color)\s+'
                              r'([A-Za-z0-9_]+)\s*\(', src, re.M):
            body = fn_body(src, sig + "(")
            if body and literal in body:
                names.append(sig)
        return names

    orphans = []
    for literal, files in sorted(families.items()):
        if literal in purge_text:
            continue
        reached = False
        for rel in files:
            for name in _functions_naming(strip_comments(read(rel, o)), literal):
                if (name + "()") in purge_text:
                    reached = True
                    break
            if reached:
                break
        if not reached:
            orphans.append("%s (%s)" % (literal, ",".join(sorted(files))))
    if orphans:
        fail("teardown-census",
             "%d global-variable family(ies) have no delete owner on the removal path, so "
             "they are held in the terminal's table for its whole lifetime: %s"
             % (len(orphans), "; ".join(orphans)))
        return
    ok("teardown-census",
       "every one of the %d Biotak_* global-variable families is deleted by a teardown "
       "that runs on removal" % len(families))


def check_look_live(o):
    """P-UI-66 - a LOOK edit must reach the PAINT, not only a cache key.

    `check_live_control` proves every reachable row writes a global somebody
    reads. That is necessary and NOT sufficient: a global read only by a cache
    key - or copied by a build stage into an array the paint reads back - is
    still a dead control in every frame the cache HITS. That is precisely the
    report "ONE STYLE does not work" (the Lines card):

      * `g_lineColor` / `g_lineTransparency` sat in `PipelineGeometryKey`, so the
        colour row and the transparency slider invalidated the geometry and the
        new look was rebuilt;
      * `g_lineWidth` / `g_lineStyle` did NOT, and the paint read
        `lines[i].lineWidth/lineStyle` - the BUILD's copy - so the width slider
        and the style dropdown changed nothing until an unrelated edit threw the
        whole level family away.

    The repair is an OWNER decision, not another key term: the look is a PAINT
    property, exactly as the zone BAND/EDGE border already was (`RenderZones`
    reads `inpMidZoneBorder*` live and no key names them). Naming all four inputs
    in the key would instead make every width drag recompute the level family on
    the weak PC this project is written for.

    Invariants:
      (a) `RenderTriggerLines` paints from the LIVE look and reads NO staged look
          field of `lines[]` - reintroducing one is the bug, not a style choice;
      (b) the geometry key names no line-look input: a look edit is not a
          geometry change, and naming one input while missing another IS the bug;
      (c) `GetLineRenderColor()` stays the colour owner and reads both inputs, so
          the rows that did work keep working;
      (d) the zone border stays a live read (regression guard: "fix" this one the
          wrong way - by pushing the border into the key - and the same class of
          dead control comes back for BORDER WIDTH / BORDER TRANSPARENCY).
    """
    pipe = strip_comments(read(PIPELINE, o))
    paint = fn_body(pipe, "void RenderTriggerLines(")
    key = fn_body(pipe, "string PipelineGeometryKey(")
    if paint is None or key is None:
        fail("look-live",
             "RenderTriggerLines / PipelineGeometryKey are gone: the line look has no "
             "paint owner to be live-read from")
        return

    stale = [t for t in ("lines[i].clr", "lines[i].lineStyle", "lines[i].lineWidth")
             if t in paint]
    if stale:
        fail("look-live",
             "the line paint reads the BUILD's copy of its own look (%s): the row that "
             "owns it only moves the chart when the geometry key happens to miss - a "
             "width slider that works one time in ten" % ", ".join(stale))
        return
    missing = [n for n in ("GetLineRenderColor()", "inpLineStyle", "inpLineWidth")
               if n not in paint]
    if missing:
        fail("look-live",
             "the line paint stopped reading the live look (%s): those Lines-card rows "
             "become dead controls again" % ", ".join(missing))
        return
    ok("look-live",
       "the line look is painted from the live owner, never from the build's copy")

    named = [t for t in ("g_lineColor", "g_lineTransparency", "g_lineWidth", "g_lineStyle")
             if t in key]
    if named:
        fail("look-live",
             "PipelineGeometryKey names the line look (%s): a look edit then rides the "
             "geometry cache, so every input the key forgets is a dead row - and the "
             "ones it remembers throw the level family away instead" % ", ".join(named))
        return
    ok("look-live", "the geometry key carries no look input, so no look edit can be cached out")

    rt = strip_comments(read(RUNTIME, o))
    clr = fn_body(rt, "color GetLineRenderColor()")
    if clr is None:
        fail("look-live", "GetLineRenderColor is gone: the Lines card's colour row has no reader")
        return
    lost = [n for n in ("g_lineColor", "g_lineTransparency") if n not in clr]
    if lost:
        fail("look-live",
             "the colour owner stopped reading %s: that row now only moves itself"
             % ", ".join(lost))
        return
    ok("look-live", "the colour owner still reads the colour AND its transparency")

    zones = fn_body(pipe, "void RenderZones(")
    if zones is None:
        fail("look-live", "RenderZones is gone: nothing owns the zone paint")
        return
    dead = [n for n in ("inpMidZoneBorderWidth", "inpMidZoneBorderTransparency",
                        "inpMidZoneBorderStyle") if n not in zones]
    if dead:
        fail("look-live",
             "the zone paint stopped reading %s live: the GEOMETRY rows BORDER / BORDER "
             "WIDTH / BORDER TRANSPARENCY become geometry-key dependants again"
             % ", ".join(dead))
        return
    ok("look-live", "the zone border is still a live read, so its three rows cannot be cached out")


def check_dual_all(o):
    """P-UI-66 - a synthetic "ALL" cell owns the GROUP, and its face says so.

    A dual row's `ext` cell ("ALL") has no setting of its own: its meaning IS what
    its press writes. It used to write the ROW's members only, so on card 11's
    `L5 | ALL` row - one member - it re-wrote L5: the design's master switch for
    the five LEVEL TOGGLES did not exist, and the pill's face mirrored L5 alone.
    That is the "same button twice" shape P-UI-62 removed from the zone picture,
    and it is half of the report "STRUCTURE L1-L5 does not work".

    Invariants:
      (a) the span has ONE owner (`PnlAllCellSpan`) that walks the row's BAND and
          only falls back to the row's own members when the band is not a
          contiguous set of settings; the press writes every setting of it;
      (b) the face comes from the SAME owner (`PnlAllCellOn`), so the pill can
          never disagree with what its press writes;
      (c) a group press costs ONE recolour walk and ONE repaint (the batch), and
          every row that renders an affected switch is refreshed - a face is part
          of the control.
    """
    panels = strip_comments(read(PANELS, o))
    span = fn_body(panels, "int PnlAllCellSpan(")
    face = fn_body(panels, "bool PnlAllCellOn(")
    if span is None or face is None:
        fail("dual-all",
             "PnlAllCellSpan / PnlAllCellOn are gone: the ALL cell has no span owner and "
             "no face owner")
        return
    if "PNL_K_SEC" not in span or "PnlRowMembers" not in span or "contiguous" not in span:
        fail("dual-all",
             "the ALL span stopped walking the row's BAND (or lost its contiguity guard): "
             "on a one-member row the cell degrades into a duplicate of that switch")
        return
    if "PnlCurrentSet(item,f+k)" not in face:
        fail("dual-all",
             "the ALL face stopped asking every member of the span: the pill lies about "
             "what the press will write")
        return
    ok("dual-all", "the ALL cell spans the band's members and its face mirrors all of them")

    press = fn_body(panels, "void PnlHandleMouseMove(")
    if press is None:
        fail("dual-all", "PnlHandleMouseMove is gone: the ALL cell has no press owner")
        return
    if "PnlAllCellSpan(dui,dur,af,ac)" not in press \
       or "PnlApplySet(dui,af+dq2,v)" not in press:
        fail("dual-all",
             "the ALL press writes this ROW's members again: the group the cell names is "
             "not the group it flips")
        return
    ok("dual-all", "the ALL press writes every setting the span names, once each")

    if "PnlAllCellOn(item,row)" not in fn_body(panels, "void PnlCreateRow("):
        fail("dual-all", "the dual renderer stopped using the span's face owner")
        return
    ok("dual-all", "the renderer paints the ALL face through the same owner")

    if "StructureSwitchBatchBegin" not in press or "StructureSwitchBatchEnd" not in press:
        fail("dual-all",
             "a group press is unbudgeted again: five switches = five recolour walks and "
             "five forced repaints for one press (what P-PERF-32 exists to prevent)")
        return
    ok("dual-all", "a group press costs one walk and one repaint")

    events = strip_comments(read(EVENTS, o))
    batch = fn_body(events, "void StructureSwitchBatchEnd()")
    if batch is None or "StructureSwitchSettle" not in batch:
        fail("dual-all",
             "the batch's close no longer settles the recolour: the group press would "
             "leave the chart painting the pre-press colours")
        return
    ok("dual-all", "the batch settles the recolour exactly once, through the owner")


def check_order_owner(o):
    """P-UI-67 - a row lives where its setting is read, and one answer has one winner.

    The user's report: «این LS FIRST … باید در مود SS/LS باشه اینجا چیکار میکنه».
    Two defects behind one row:

      * WRONG HOME - `def.lsFirst` is assigned in `ModeDefinitions` ONLY for
        `SS_LS_STEP`, so on the Zones & Levels card (the row's old home) the switch
        could not change one pixel in TH - the shipped default - or in Combo/Factor.
        It also named its own ON value ("LS FIRST"), which reads as a lie while the
        switch is OFF.
      * TWO OWNERS, THE WRONG ONE WINNING - the question "which of SS/LS comes
        first?" is answered by the chart prompt's per-chart OVERRIDE and by the
        panel's DEFAULT flag, and `GetEffectiveSSLSLongFirst` prefers the override.
        So pressing the switch while a stale override existed wrote `g_lsFirst` and
        changed nothing on the chart: a dead-looking row, the same "two owners
        disagree" shape P-UI-62 removed from the zone picture.

    Invariants:
      (a) the switch TAKES the question over (a press clears the per-chart override,
          so the chart follows the surface the user just touched);
      (b) the override's key has exactly ONE setter and ONE deleter, both inside the
          owner pair (`SSLSOrderOverrideSet` / `SSLSOrderOverrideClear`) - a bare
          `= -1` or a stray `GlobalVariableDel` leaves state and key disagreeing;
      (c) the row is rendered ONLY by the SS-LS section (a Zones-card display row
          for setting 8 would offer it in every step mode);
      (d) the caption has ONE owner: a literal spelling in either surface is how the
          two drift.
    """
    panels = _code_only(read(PANELS, o))
    events = _code_only(read(EVENTS, o))
    globalsrc = _code_only(read(GLOBALS, o))

    branch = fn_body(panels, "int PnlApplySet(const int item,const int row,const double v)")
    if branch is None:
        fail("order-owner", "PnlApplySet is gone: the SS/LS row has no press owner")
        return
    if "SSLSOrderOverrideClear()" not in branch:
        fail("order-owner",
             "the SS/LS ORDER press leaves the per-chart override alone: while one is "
             "set the switch writes the default and the chart does not move")
        return
    ok("order-owner", "the switch press takes the question over from the chart override")

    setter = fn_body(globalsrc, "void SSLSOrderOverrideSet(const int v)")
    clearer = fn_body(globalsrc, "void SSLSOrderOverrideClear()")
    if setter is None or clearer is None:
        fail("order-owner", "the SS/LS override owner pair is gone: state and key can drift")
        return
    if "GlobalVariableSet(" not in setter or "GlobalVariableDel(" not in clearer:
        fail("order-owner",
             "the override owners stopped writing/removing the persisted key: the answer "
             "would not survive an attach, or would survive the reset")
        return
    stray = []
    for rel, src in (("panels", panels), ("events", events)):
        for i, line in enumerate(src.splitlines(), 1):
            if "Biotak_SSLSFirst_" in line and "GlobalVariable" in line:
                stray.append("%s:%d" % (rel, i))
    if stray:
        fail("order-owner",
             "the override key is written outside its owner (%s): one owner per answer, "
             "or the two surfaces disagree silently" % ", ".join(stray))
        return
    ok("order-owner", "the override's key has exactly one setter and one deleter")

    if re.search(r"PnlSpecAdd\(\s*1\s*,\s*PNL_K_\w+\s*,\s*8\s*,", panels):
        fail("order-owner",
             "the SS/LS order row is back on the Zones & Levels card: that card exists in "
             "every step mode, and `def.lsFirst` is only assigned for SS-LS, so the row "
             "cannot move anything in the shipped TH mode")
        return
    if 'PnlSpecAdd(9, PNL_K_LEGACY, base, 1, "swap")' not in panels:
        fail("order-owner",
             "the Step card's SS-LS section no longer renders the SS/LS order row: the "
             "setting is now unreachable from the panel")
        return
    ok("order-owner", "the row is rendered only by the SS-LS section, where the setting is read")

    if panels.count("label=PNL_LBL_SSLS_ORDER") < 2:
        fail("order-owner",
             "a surface spells the caption itself instead of reading PNL_LBL_SSLS_ORDER: "
             "two spellings is how a switch ends up named after its own ON state")
        return
    if '"LS FIRST"' in panels:
        fail("order-owner", "the old state-naming caption (\"LS FIRST\") is back")
        return
    ok("order-owner", "one caption, two readers - the label names the question, not the answer")


# The list is assembled AFTER the last check's definition, below - a name the
# `CHECKS = [...]` line references must already exist when it runs.


def check_click_ownership(o):
    """THE RULE: a click on the UI never reaches the chart (P-UI-92 / P-UI-92b).

    The composer runs `OnChartEventHandler` (domain) BEFORE `HandleUIChartEvent`
    (UI) for the same event, so a press or release that landed on a panel used to
    be read as chart input, before the panel's own handler could object:

      * the armed Base/Knot tool committed a corner at the price hidden under the
        card (its CLICK fallback and its press both take the price from `dparam`),
      * its committed-box drag latch armed on a box behind the panel, so the next
        move dragged something the user could not even see,
      * the Custom Price pick consumed the same release as its starting price.

    Two halves, one rule, and BOTH must stay wired:
      WHERE - `UIPointerOverSurface` answers from the UI's own layout (exact, no
              time window) and every domain site that reads a pixel as chart
              input asks it;
      WHOSE - a gesture can begin off the UI (an orb drag, a card opened by a
              release) and still be the UI's, so the claim the UI publishes is
              peeked by the domain half through the mirror in GlobalVariables.
    """
    panels = strip_comments(read(PANELS, o))
    menu = strip_comments(read(MENU, o))
    glb = strip_comments(read(GLOBALS, o))
    events = strip_comments(read(EVENTS, o))
    bk = strip_comments(read(BASEKNOT, o))

    surf = fn_body(panels, "bool UIPointerOverSurface(const int mx,const int my)")
    if not surf:
        fail("click-ownership",
             "UIPointerOverSurface is gone: the domain half has no way to ask whose "
             "pixel it is reading")
        return
    for need in ("PnlPointInside(mx,my)", "BkMiniStripPointInside(mx,my)",
                 "LiveCountdownPointInside(mx,my)"):
        if need not in surf:
            fail("click-ownership",
                 "a visible UI surface stopped being claimed (%s): clicks on it bleed "
                 "into the chart behind it" % need)
            return
    hidden = "   if(g_UI.menuVisible)\n   {\n      int bx = 0, by = 0, bw = 0, bh = 0;"
    if hidden not in surf:
        fail("click-ownership",
             "the ring menu's pixels are claimed unconditionally: a HIDDEN menu would "
             "eat presses in a patch of chart the draw session still needs (P-BK-02)")
        return
    if "PnlComputeMenuBounds(bx,by,bw,bh);" not in surf:
        fail("click-ownership", "the menu's claimed rectangle is no longer measured")
        return
    ok("click-ownership",
       "the UI claims exactly the surfaces it has VISIBLE, measured from its own layout")

    # P-BK-65 re-anchored this gate: the latch's condition now leads with the gesture
    # guard (`!bkGripHeld &&`) so a mouse-channel press edge cannot re-latch a box that a
    # live chip drag already owns (a mid-drag baseline is the P-BK-25 trap). The UI test
    # still stands exactly where it did - one term later - and the anchor below proves it
    # is still the term that gates the time/price conversion, not a mention in passing.
    latch = ("!UIPointerOverSurface((int)lparam, (int)dparam) &&\n"
             "            ChartXYToTimePrice(0, (int)lparam, (int)dparam, ssw, sct, scp)")
    if latch not in bk:
        fail("click-ownership",
             "the box tool's press latch arms on a press that landed on a panel: the "
             "next move drags the box hidden behind the card")
        return
    swallow = "if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;"
    if bk.count(swallow) < 3:
        fail("click-ownership",
             "the box tool reads a UI pixel again (%d of 3 sites guarded: press, "
             "release, tap-commit): a corner is placed at the price hidden under the "
             "panel" % bk.count(swallow))
        return
    ok("click-ownership",
       "the box tool asks WHERE before it places a corner, drags a box or commits")

    if ("if(id == CHARTEVENT_CLICK && g_waitingForCustomPriceClick &&" not in events or
            "!UIPeekClickClaim() && !UIPointerOverSurface((int)lparam, (int)dparam)" not in events):
        fail("click-ownership",
             "the Custom Price pick takes any release as its price: a click on a card "
             "sets the origin from the price hidden under it")
        return
    if "pressEdge && !UIPointerOverSurface((int)lparam, (int)dparam) &&" not in events:
        fail("click-ownership",
             "the Custom Price line's press-edge grab ignores the UI: a press on a "
             "panel can grab the line through it")
        return
    ok("click-ownership",
       "the Custom Price pick asks WHERE and WHOSE before it reads `dparam` as a price")

    peek = fn_body(glb, "bool UIPeekClickClaim()")
    if not peek:
        fail("click-ownership", "UIPeekClickClaim is gone: the published claim has no reader")
        return
    if "g_uiClickClaimDown" not in peek or "g_uiClickClaimSeq == g_uiPressSeq" not in peek:
        fail("click-ownership",
             "the peek drops the press-bound half of the claim: a release after a long "
             "hold is classified differently by the two halves of one event")
        return
    if "(int)(GetTickCount() - g_uiClickClaimMs) >= 0" not in peek:
        fail("click-ownership",
             "the peek ignores the up-armed TTL: a claim with no press to bind to then "
             "waits forever and eats a genuine chart click")
        return
    ok("click-ownership", "the domain peeks the SAME three tests the UI half applies")

    pub = fn_body(menu, "void UIPublishClickClaim()")
    if not pub:
        fail("click-ownership", "UIPublishClickClaim is gone: the domain half is blind again")
        return
    for sig, why in (
            ("void UISuppressNextClick()", "arming a claim no longer publishes it"),
            ("bool UIShouldSuppressClick()", "taking a claim no longer publishes its echo"),
            ("void UIReleaseClaimReset()", "the reset leaves the mirror armed across an attach"),
            ("bool MousePressStart(const bool leftDown)",
             "the press counter is not published, so a stale claim cannot be retired for "
             "both halves at the same instant")):
        body = fn_body(menu, sig)
        if not body or "UIPublishClickClaim()" not in body:
            fail("click-ownership", why)
            return
    ok("click-ownership",
       "every transition of the claim publishes it, and the press edge retires it")

    writers = []
    for path in sorted(glob.glob(os.path.join(ROOT, "Biotak", "*.mqh"))):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if rel == GLOBALS:
            continue                     # the declaration itself
        if re.search(r"g_uiClickClaim(Live|Down|Seq|Ms)\s*=[^=]", strip_comments(read(rel, o))):
            writers.append(rel)
    if writers != ["Biotak/BiotakMenu.mqh"]:
        fail("click-ownership",
             "the published claim has %d owner(s) (%s): a second writer is how the "
             "mirror and the state machine start disagreeing - the state machine in "
             "BiotakMenu is the only writer, the domain only reads"
             % (len(writers), ", ".join(writers) or "none"))
        return
    ok("click-ownership",
       "one writer: the claim is published by the UI, read by the domain, never the reverse")


# The CHECKS list is assembled at the bottom of this file, after the last check's
# definition: a name the list references must already exist when it runs.


def _pp_lite_view(src):
    """(line, compiled_in_lite) per line: a conservative #ifdef BUILD_LITE walk.

    Only `#ifndef BUILD_LITE` proves a line is compiled OUT of Lite (the entry
    defines BUILD_LITE); `#ifdef BUILD_LITE` proves it is compiled IN. Any other
    condition is assumed COMPILED, so it can never excuse a call: the gate's job is
    to be sensitive on the family of names it tracks (the UI layer's own functions
    below), and a miss there is a broken build.
    """
    out = []
    stack = [True]
    for line in src.splitlines():
        s = line.strip()
        if s.startswith("#ifndef BUILD_LITE"):
            stack.append(False)
        elif s.startswith("#ifdef BUILD_LITE"):
            stack.append(True)
        elif s.startswith("#if"):
            stack.append(stack[-1])
        elif s.startswith("#else"):
            stack[-1] = not stack[-1]
        elif s.startswith("#endif") and len(stack) > 1:
            stack.pop()
        out.append((line, all(stack)))
    return out


def check_lite_wall(o):
    """THE RULE: the LITE build compiles (P-BUILD-01).

    Lite is not a feature flag, it is a second ENTRY: it defines BUILD_LITE and
    includes the domain half (EventHandlers, BaseKnotTool, LabelFunctions, ...)
    but NOT the UI half (BiotakKit/BiotakMenu/BiotakPanels/HTFCandles). A shared
    module that calls a UI-only function therefore compiles in Full and breaks in
    Lite - and nothing in the verify list compiled Lite, so the break shipped.
    That is exactly how the first cut of P-UI-92 arrived: `error 168: function not
    defined` at six sites in two shared files, all of them green in Full.

    The rule, mechanically: every function/macro DEFINED outside the Lite file set
    must not be CALLED from inside it, unless the call sits in a `#ifndef
    BUILD_LITE` region (compiled out) or the name has a Lite stub - a definition
    in a Lite-included file, which is the project's `#ifdef BUILD_LITE` pattern
    (GlobalVariables carries the UIPointerOverSurface stub that way).
    """
    lite_files = []
    seen = set()

    def walk(rel):
        if rel in seen:
            return
        seen.add(rel)
        lite_files.append(rel)
        for line, live in _pp_lite_view(read(rel, o)):
            s = line.strip()
            if not live or not s.startswith("#include"):
                continue
            m = re.match(r'#include\s+"([^"]+)"', s)
            if not m:
                continue
            inc = m.group(1).replace("\\", "/")
            walk(inc if "/" in inc else "Biotak/" + inc)

    walk(LITE)
    if LITE not in lite_files:
        fail("lite-wall", "the Lite entry could not be read")
        return

    every = ["Biotak/" + os.path.basename(p)
             for p in sorted(glob.glob(os.path.join(ROOT, "Biotak", "*.mqh")))]
    ui_only = [f for f in every if f not in lite_files]
    if not ui_only:
        fail("lite-wall", "no module is UI-only: the Lite entry now includes the whole UI")
        return

    type_re = (r"(?:void|int|bool|double|string|long|datetime|uint|float|char|short|"
               r"ushort|color|unsigned\s+int)")
    def_re = re.compile(r"^\s*(?:static\s+)?(?:const\s+)?" + type_re + r"\s+(\w+)\s*\(",
                        re.M)
    macro_re = re.compile(r"^#define\s+(\w+)\s*\(", re.M)

    # SCOPE: the UI layer's own function families. Tracking every Full-only
    # definition instead would flag calls that resolve to an MQL4 builtin through a
    # compat shim (`MarketInfo`, `Close`), or to a debug-only macro; those are not
    # what this gate is about, and a false FAIL would make it noise. A UI surface
    # that the shared half must ask for always wears one of these prefixes.
    families = ("Pnl", "Circ", "Pal", "Bk", "Menu", "Sub", "HTF", "UI", "Tools")
    names = {}
    for rel in ui_only:
        src = strip_comments(read(rel, o))
        for m in list(def_re.finditer(src)) + list(macro_re.finditer(src)):
            if m.group(1).startswith(families):
                names.setdefault(m.group(1), rel)

    # What the Lite build itself DEFINES - region-filtered, because a definition
    # inside `#ifndef BUILD_LITE` is not there when Lite compiles (that is the
    # whole point of the P-UI-92c stub: it lives under `#ifdef BUILD_LITE`).
    provided = set()
    for rel in lite_files:
        for line, live in _pp_lite_view(strip_comments(read(rel, o))):
            if not live:
                continue
            provided.update(m.group(1) for m in def_re.finditer(line))
            provided.update(m.group(1) for m in macro_re.finditer(line))
    names = {k: v for k, v in names.items() if k not in provided}

    hits = []
    for rel in lite_files:
        if rel == LITE:
            continue
        for i, (line, live) in enumerate(_pp_lite_view(strip_comments(read(rel, o))), 1):
            if not live:
                continue
            for name, owner in names.items():
                if name in line and (name + "(") in line.replace(" ", ""):
                    hits.append((rel, i, name, owner))
    if hits:
        shown = ", ".join("%s:%d calls %s (%s)" % h for h in hits[:4])
        fail("lite-wall",
             "%d call(s) from the Lite file set into a Full-only definition: the Lite "
             "build must fail to compile. %s%s"
             % (len(hits), shown, " ..." if len(hits) > 4 else ""))
        return
    ok("lite-wall",
       "every call in the Lite file set resolves inside Lite (%d Full-only names guarded)"
       % len(names))


def check_tick_wrap(o):
    """THE RULE: a tick-count deadline is asked through its ONE owner (P-TICKWRAP).

    `GetTickCount()` wraps every ~49.7 days. `GetTickCount() <= deadline` is NOT the
    wrap-safe form: a deadline armed before the wrap is a huge number, so after the
    counter restarts near 0 the test stays TRUE for the rest of the cycle and the
    window never closes. The reader that used it gated the OBJECT_DELETE path
    (`g_suppressDeleteEventsUntilMs`, armed for 250 ms at ten sites) - a terminal
    left open that long would silently ignore every delete until the counter climbed
    past the stale deadline. The form that is correct is the SIGNED DIFFERENCE
    (`(int)(GetTickCount() - deadline) <= 0`, valid for any interval under 24 days),
    owned by `TickDeadlinePending` in GlobalVariables.
    """
    pats = (re.compile(r"GetTickCount\(\)\s*(<=|>=|<|>)"),
            re.compile(r"[\w\)\]]\s*(<=|>=|<|>)\s*GetTickCount\(\)"))
    hits = []
    for path in sorted(glob.glob(os.path.join(ROOT, "Biotak", "*.mqh"))):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        for i, line in enumerate(strip_comments(read(rel, o)).splitlines(), 1):
            if any(p.search(line) for p in pats):
                hits.append("%s:%d" % (rel, i))
    if hits:
        fail("tick-wrap",
             "%d absolute GetTickCount() comparison(s): a window armed before the "
             "49.7-day wrap never closes (ask TickDeadlinePending instead). %s"
             % (len(hits), ", ".join(hits[:4])))
        return
    ok("tick-wrap", "every tick deadline is asked through the wrap-safe owner")


CHECKS = [check_negative_cache, check_blend_background, check_combo_guard, check_init_ledger,
          check_history_format, check_delete_paths, check_ui_hot_path, check_geometry_cache,
          check_base_price_state, check_family_isolation, check_toggle_path,
          check_persist_write_shape, check_chart_change_prime, check_perf49_ledgers,
          check_name_scheme,
          check_topology_adoption, check_level_foreign_02, check_event_settle, check_ui_sync,
          check_longpress_latch, check_custom_price_mode, check_custom_price_source,
          check_live_control, check_teardown_census, check_drag_anchor,
          check_zone_picture, check_edge_look, check_click_claim,
          check_look_live, check_dual_all, check_order_owner, check_click_ownership,
          check_lite_wall, check_tick_wrap]


def run(overrides=None):
    del FAILURES[:]
    if not QUIET:
        print("probe-budget-audit (P-PERF-07/08/09/10/11)")
    for check in CHECKS:
        check(overrides)
    if FAILURES:
        if not QUIET:
            print("\nprobe budget: %d FAILURE(S)" % len(FAILURES))
        return 1
    if not QUIET:
        print("\nprobe budget: clean")
    return 0


# ---------------------------------------------------------------------------
# selftest: every check must catch its OWN mutant (a stale seed is a hard error)
# ---------------------------------------------------------------------------
def selftest():
    # A mutant of a BROKEN tree is caught by everything, so a selftest that never
    # checks its own baseline can report "all 225 caught" on a gate whose real run
    # is FAILING - the seeds would be certifying the failure as sensitivity.
    global QUIET
    quietWas = QUIET
    QUIET = True
    baseline = run()
    QUIET = quietWas
    if baseline != 0:
        print("  selftest REFUSED: the unmutated tree already FAILS - fix that first")
        return 1

    seeds = []

    def seed(label, rel, old, new):
        seeds.append((label, rel, old, new))

    # 1. the probe runs before the table is consulted
    seed("probe before table", PIPELINE,
         "if(CacheIsAbsentKnown(name)) return;",
         "if(false) return;")
    seed("miss not recorded", PIPELINE,
         "CacheMarkAbsent(name);",
         ";")
    # NOTE: read() opens in text mode, so seeds are written with LF even though
    # the MQL sources carry CRLF (they are normalised on read).
    # P-PERF-47 moved the bump to the TOP of CacheClear, ahead of the two early
    # returns that used to skip it. The seed follows the CODE, not the old line:
    # it is still "the bump is missing" that must be caught, whatever explains it.
    seed("CacheClear keeps marks", OBJCACHE,
         "    MarkDrawGeneration();\n    if(!g_objectCacheHashInitialized) return;",
         "    if(!g_objectCacheHashInitialized) return;")
    seed("OnInit keeps marks", EVENTS,
         "    CacheAbsentResetAll();",
         "")
    seed("reset stops freeing stamps", OBJCACHE,
         "    for(int i = 0; i < CACHE_ABSENT_BUCKETS; i++) g_absentStamp[i] = 0;",
         "")
    seed("mark not generation-scoped", OBJCACHE,
         "        if(g_absentStamp[idx] != g_drawGeneration) return false;  // stale/empty slot ends the chain",
         "        if(false) return false;")

    # 5. the history format is guessed again / the day frame is mixed again
    seed("hour>=22 guess returns", BASEMGR,
         "    bool needsMigration = (loadedCount > 0 && g_loadedHistoryFormat != HISTORY_FORMAT_VERSION);",
         "    bool needsMigration = false;\n"
         "    for(int i = 0; i < loadedCount; i++) { if(hour >= 22) needsMigration = true; }")
    seed("stamp not written", HISTMGR,
         "        FileWriteString(fileHandle, HistoryFileStampLine() + \"\\n\");",
         "")
    seed("loader reads the stamp as data", HISTMGR,
         "            if(StringGetCharacter(line, 0) == '#')",
         "            if(false)")
    seed("append can create an unstamped file", HISTMGR,
         "    if(HistoryFileStampedVersion(filePath) != HISTORY_FORMAT_VERSION)",
         "    if(false)")
    seed("day frame mixed again", DYNDET,
         "    datetime serverNow = TimeCurrent();   // the frame bar times actually use",
         "    datetime serverNow = gmtNow;")
    seed("session start not converted", DYNDET,
         "    if(resultServer > 0) result = DtddServerToGMT(resultServer);",
         "    if(resultServer > 0) result = resultServer;")

    # 6. the delete paths are wasteful again
    # P-UI-62: the absent check and the cache read swapped places (a live entry must be
    # believed first), so the seed anchors on the new order and the mutant is the ONE
    # shortcut removal that makes the delete probe a proved-absent name.
    seed("delete probes a proved-absent name", OBJCACHE,
         "    if(!inCache && CacheIsAbsentKnown(name)) return false;",
         "    if(false) return false;")
    seed("proved miss not recorded", OBJCACHE,
         "        if(!existsOnChart) CacheMarkAbsent(name);",
         "")
    seed("legacy probes back before the skip", ZONEFACTORY,
         "            result.success = true;\n            return result; // Skip everything!",
         "            DeleteIndicatorObjectManaged(request.name + \"_Top\");\n"
         "            result.success = true;\n            return result; // Skip everything!")
    seed("HTF delete walks the chart", HTF,
         "   ObjectsDeleteAll(0, g_HTFPrefix);",
         "   int totalF14 = ObjectsTotal(0, 0, OBJ_RECTANGLE);")
    seed("HTF delete loses its guard", HTF,
         "   if(g_HTFDrawnCount <= 0 && !HTFAnyBoxesExist()) return;",
         "")
    seed("OnDeinit loses its phases", FULL,
         "    p15Htf = GetTickCount() - p15t; p15t = GetTickCount();\n",
         "")
    seed("mouse move loses its phases", PANELS,
         "      uint p15ring = GetTickCount() - p15t; p15t = GetTickCount();\n",
         "")

    # 7. the UI hot path regresses to per-item terminal reads / object churn
    seed("layout reads the chart per item", MENU,
         "   CircUIMetrics(cw, ch);   // P-PERF-16: cached - no terminal read per item",
         "   cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);\n"
         "   ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);\n"
         "   if(cw <= 0) cw = 1920;\n   if(ch <= 0) ch = 1080;")
    seed("radius fit not memoised", MENU,
         "   if(s_fitR > 0.0 && cw == s_fitCw && ch == s_fitCh && ox == s_fitOx && oy == s_fitOy)",
         "   if(false)")
    seed("chart change stops invalidating", PANELS,
         "      CircUIMetricsInvalidate();\n      if(g_UI.menuVisible) UpdateCircularMenuPosition();",
         "      if(g_UI.menuVisible) UpdateCircularMenuPosition();")
    seed("timer stops refreshing metrics", FULL,
         "    CircUIMetricsInvalidate();\n\n    // FIX: If indicator is not yet fully initialized",
         "    // FIX: If indicator is not yet fully initialized")
    seed("drag path re-reads the rect", PANELS,
         "   // P-PERF-16: the drag path asks for the chart rect on every move event; the\n   // shared cached reader (BiotakMenu) owns it, and both invalidation points\n   // (CHART_CHANGE + the 250 ms timer) already exist.\n   int cw = 0, ch = 0;\n   CircUIMetrics(cw, ch);",
         "   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);\n   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);")
    seed("tip hidden by deleting objects", MENU,
         "   CircTipPark();\n}",
         "   ObjectDelete(0, CircTipBg());\n   ChartRedraw();\n}")
    seed("tip visibility probed per move", MENU,
         "   if(feat != -2 && feat == s_CircTipFeat) { s_TipPendFeat = -2; return; }",
         "   if(feat == s_CircTipFeat && ObjectFind(0, CircTipBg()) >= 0) { s_TipPendFeat = -2; return; }")

    # 8. the geometry cache is bypassed or keyed too loosely
    seed("geometry cache bypassed", PIPELINE,
         "    if(s_geoValid && geoKey == s_geoKey) {",
         "    if(false) {")
    seed("stale geometry kept", PIPELINE,
         "            s_geoValid = false;   // never serve a geometry for a config that produced none\n",
         "")
    seed("key drops the viewport", PIPELINE,
         "    key += \"|\" + DoubleToString(vpTop, 8) + \",\" + DoubleToString(vpBottom, 8);",
         "    key += \"|\";")
    seed("interval table not proved", PIPELINE,
         "    key += \"|iv\";\n    for(int iv = 0; iv < 5; iv++) key += \",\" + IntegerToString(g_cachedIntervals[iv]);",
         "    key += \",\" + IntegerToString(ArraySize(g_cachedIntervals));")

    # 9. the base-price state returns to the lock, the load ledger loses its
    #    owner, and the history file is written unconditionally (P-PERF-19/20)
    seed("access macro takes the lock again", BASEPRICE,
         "#define g_historyCount (g_symbolStates[GetCachedSymbolStateIndex()].historyCount)",
         "#define g_historyCount (g_symbolStates[GetSymbolStateIndex()].historyCount)")
    seed("cached resolver drops its guard", BASEPRICE,
         "    if(_g_cachedStateIdx >= 0 && _g_cachedStateSymbol == sym &&",
         "    if(false &&")
    seed("per-entry accessor takes the lock", BASEPRICE,
         "    // P-PERF-19: the five accessors below are called INSIDE loops (entry walks,\n"
         "    // series builders), so they must not take the global-variable lock either.\n"
         "    int stateIdx = GetCachedSymbolStateIndex();",
         "    int stateIdx = GetSymbolStateIndex();")
    seed("loop condition resolves the macro", BASEPRICE,
         "    int count = g_historyCount;\n    for(int i = 0; i < count; i++)",
         "    for(int i = 0; i < g_historyCount; i++)")
    seed("load window loses its owner", BASEPRICE,
         '              "ms load=", (int)g_pInitBaseMigrateMs,\n',
         "")
    seed("history file written unconditionally", BASEPRICE,
         "        if(needsSave && HistoryContentDiffers(workingHistory, tempHistory, histCount, loadedCount))",
         "        if(needsSave)")

    # 10. the families touch each other again (P-PERF-21/22)
    # NOTE (P-PERF-23): this seed used to anchor on the mid-zone appearance term
    # that lived in the TOPOLOGY string. That term moved out (it never belonged
    # there), so the seed anchors on the last surviving topology term instead.
    seed("trigger back in the topology signature", EVENTS,
         "                          IntegerToString(inpLSFirst ? 1 : 0) + \"|\" +",
         "                          IntegerToString(inpLSFirst ? 1 : 0) + \"|\" +\n"
         "                          IntegerToString(IsTriggerLevelsEnabled() ? 1 : 0) + \"|\" +")
    seed("trigger dropped from the render signature", EVENTS,
         "                          IntegerToString(IsTriggerLevelsEnabled() ? 1 : 0) +\n"
         "                          IntegerToString(g_customPriceLineDragging ? 1 : 0) +",
         "                          IntegerToString(g_customPriceLineDragging ? 1 : 0) +")
    seed("trigger toggle force-clears again", EVENTS,
         "            // P-PERF-21: NO force-clear. The overlay owns ONE family - the",
         "            g_forceClearOnNextDraw = true;   // P-PERF-21: NO force-clear. The overlay owns ONE family - the")
    seed("panel trigger row force-clears again", PANELS,
         "                            g_redrawTHLevelsNeeded=true;\n"
         "                            flags=REFRESH_BUFFERS; }",
         "                            g_forceClearOnNextDraw=true; g_redrawTHLevelsNeeded=true;\n"
         "                            flags=REFRESH_ALL; }")
    seed("geometry key keys on the trigger again", PIPELINE,
         "    key += \"|\" + IntegerToString(baseMultiplier);\n",
         "    key += \"|\" + IntegerToString(triggerEnabled ? 1 : 0) + \",\" + IntegerToString(baseMultiplier);\n")
    seed("key stops proving zone colours", PIPELINE,
         "    key += \"|zc\" + IntegerToString(inpShowMidZones ? 1 : 0)",
         "    key += \"|zc\" +")
    seed("L switch scans the chart again", EVENTS,
         "   SetAllLineObjectsVisibility(visible);",
         "   int total = ObjectsTotal(0, -1, -1);")
    seed("L switch bypasses the mask owner", EVENTS,
         "            SetLinesVisible(p26want, true);",
         "            g_linesVisible = p26want;")
    seed("panel row stops writing the mask", PANELS,
         "SetLinesVisible(g_showLines, true);",
         "g_linesVisible=g_showLines;")
    seed("line walk loses its exclusions", VISIBILITY,
         "            if(StringFind(nm, \"_B_Top\") >= 0) continue;               // F key's family\n",
         "")
    seed("line walk drops the shared line test", VISIBILITY,
         "            if(!VisibilityIsLineObject(nm)) continue;",
         "")
    seed("shared line test stops proving the type", VISIBILITY,
         "    return (objType == OBJ_HLINE || objType == OBJ_TREND);",
         "    return true;")
    seed("box-border owner loses a segment", EVENTS,
         '    if(StringFind(name, "_B_Right") >= 0)  return true;\n',
         "")
    # P-PERF-41 - the family switch went back to destroying the family. Four ways
    # to reintroduce it: the OFF state deletes again, the OFF state stops hiding
    # (P-PERF-36's own symptom), the hide branch sinks below the loop it must
    # precede, a per-zone trigger switch deletes its band, the walk loses its
    # cold-cache fallback, and cleanup is guarded again.
    seed("family switch deletes instead of hiding", PIPELINE,
         "    if(!config.zonesEnabled) { HideAllZoneFamilyObjects(); return; }",
         "    if(!config.zonesEnabled) {\n        CleanupSurplusObjects(config.objectPrefix + config.modeName + \"_Zone_Above_\", 0);\n        return;\n    }")
    seed("family switch stops hiding (P-PERF-36 returns)", PIPELINE,
         "    if(!config.zonesEnabled) { HideAllZoneFamilyObjects(); return; }",
         "    if(!config.zonesEnabled) return;")
    seed("hide branch sinks below the empty zone loop", PIPELINE,
         "    if(!config.zonesEnabled) { HideAllZoneFamilyObjects(); return; }",
         "    int __p41noop = 0;")
    seed("family-off walk takes a constant visibility argument", VISIBILITY,
         "int HideAllZoneFamilyObjects()\n{",
         "int HideAllZoneFamilyObjects(const bool zonesVisible)\n{")
    seed("F show path forgets the zone switch", VISIBILITY,
         '            ApplyTfMaskGuarded(nm, VisibilityZoneMask(nm, zonesVisible, linesVisible));',
         '            ApplyTfMaskGuarded(nm, OBJ_ALL_PERIODS);')
    seed("F show path decides the zone mask itself", VISIBILITY,
         "            ApplyTfMaskGuarded(nm, VisibilityZoneMask(nm, zonesVisible, linesVisible));",
         "            ApplyTfMaskGuarded(nm, linesVisible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);")
    seed("F key stops passing the zone switch", EVENTS,
         "                                                           g_triggerLevelsEnabled, g_linesVisible,\n"
         "                                                           inpShowMidZones);",
         "                                                           g_triggerLevelsEnabled, g_linesVisible,\n"
         "                                                           true);")
    seed("trigger-off branch stops skipping its band", PIPELINE,
         "        if(zones[i].isTrigger && !triggerEnabled) {\n"
         "            DeleteManagedZoneObjects(zones[i].name);\n"
         "            continue;\n",
         "        if(zones[i].isTrigger && !triggerEnabled) {\n"
         "            DeleteManagedZoneObjects(zones[i].name);\n")
    seed("family walk loses the cold-cache fallback", VISIBILITY,
         "    if(seen == 0) touched += HideZoneFamilyLegacyScan();",
         "    touched += 0;")
    # P-PERF-41e - the guard that latched the walk off after one press. It is the
    # defect most likely to be re-added "for performance", so it is planted back.
    seed("family walk re-grows a constant-input latch", VISIBILITY,
         "    int touched = 0;\n"
         "    int seen = 0;\n"
         "    int visited = 0;\n"
         "    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++)",
         "    static bool s_lastWalk = true;\n"
         "    if(s_lastWalk) return 0;\n"
         "    s_lastWalk = false;\n"
         "    int touched = 0;\n"
         "    int seen = 0;\n"
         "    int visited = 0;\n"
         "    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++)")
    seed("family walk stops using the guarded writer", VISIBILITY,
         "        seen++;\n"
         "        if(ApplyTfMaskGuarded(nm, VisibilityZoneMask(nm, false, linesOn)))",
         "        seen++;\n"
         "        if(ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS))")
    seed("zone cleanup guarded by the flag that turns zones off", PIPELINE,
         "    const int zoneCleanupFrom = maxLogicalStep + 1;",
         "    const int zoneCleanupFrom = config.zonesEnabled ? (maxLogicalStep + 1) : 0;")
    # the ring item: the reverted cross-effect, in each of its four shapes.
    seed("ring item becomes a master over both layers", MENU,
         "bool CircFeatureOn(const int i)\n{\n   if(i == CIR_ZONES)           return g_showMidZones;",
         "bool ZonesAndLevelsMasterOn() { return g_showMidZones && g_linesVisible; }\n"
         "bool CircFeatureOn(const int i)\n{\n   if(i == CIR_ZONES)           return ZonesAndLevelsMasterOn();")
    seed("ring light reads the line layer too", MENU,
         "   if(i == CIR_ZONES)           return g_showMidZones;",
         "   if(i == CIR_ZONES)           return g_showMidZones && g_linesVisible;")
    seed("ring badge reads the line layer too", MENU,
         '   if(i == CIR_ZONES)           return g_showMidZones ? "On" : "";',
         '   if(i == CIR_ZONES)           return (g_showMidZones && g_linesVisible) ? "On" : "";')
    seed("ring press also moves the line switch", MENU,
         "      g_showMidZones = !g_showMidZones;",
         "      g_showMidZones = !g_showMidZones;\n      SetLinesVisible(g_showMidZones, true);")
    seed("ring press deletes to hide", MENU,
         "      g_showMidZones = !g_showMidZones;",
         "      g_showMidZones = !g_showMidZones;\n      ObjectsDeleteAll(0, inpObjectPrefix);")
    # P-PERF-35b - the pump that ran the rebuild before the sweeps.
    seed("pump runs the heavy frame before the sweep jobs", EVENTS,
         "   int coopOrder[COOP_JOB_COUNT - 1] = { COOP_JOB_OBJ_CLEANUP, COOP_JOB_LABEL_EXPIRY,\n                                         COOP_JOB_STATUS_TEXT,  COOP_JOB_HEAVY_FRAME };",
         "   int coopOrder[COOP_JOB_COUNT - 1] = { COOP_JOB_HEAVY_FRAME, COOP_JOB_OBJ_CLEANUP,\n                                         COOP_JOB_LABEL_EXPIRY,  COOP_JOB_STATUS_TEXT };")
    seed("pump goes back to iterating the job ids", EVENTS,
         "      int job = coopOrder[oi];",
         "      int job = oi + 1;")
    # P-PERF-38 - the naming scheme. Four ways to lose the in-place update.
    seed("the level prefix names the timeframe again", OBJFUN,
         '   return inpObjectPrefix + "_";',
         '   return inpObjectPrefix + "_" + GetCurrentTimeframe() + "_";')
    seed("a call site rebuilds the TF-named prefix by hand", LABEL,
         "    string labelPrefix = GetLevelObjectPrefix() + \"LBL_\";",
         "    string labelPrefix = inpObjectPrefix + \"_\" + GetCurrentTimeframe() + \"_\" + \"LBL_\";")
    seed("the teardown deletes the family on a timeframe switch", EVENTS,
         "    else if(reason == REASON_CHARTCHANGE)",
         "    else if(false)")
    seed("the one-time migration loses its stamp", EVENTS,
         '   if(LegacyNameSchemeMigrated()) return;   // this chart is already migrated',
         "   if(false) return;")
    seed("dead factor path keeps the inverted zone-cleanup guard", EXTDRAW,
         '    ObjectsDeleteAll(0, objectPrefix + "Factor_Zone_", -1, -1);',
         '    if(inpShowMidZones) ObjectsDeleteAll(0, objectPrefix + "Factor_Zone_", -1, -1);')

    # 11. a visibility toggle deletes/rebuilds again, or loses its measurement
    #     (P-PERF-23/24/26)
    seed("appearance term back in the topology signature", EVENTS,
         "        string levelSig = objectPrefix + \"|\" +",
         "        string levelSig = objectPrefix + \"|\" + IntegerToString(inpShowMidZones ? 1 : 0) +")
    seed("appearance dropped from the render signature", EVENTS,
         "        frameCore = levelSig + levelLookSig + \"|\" +",
         "        frameCore = levelSig + \"|\" +")
    seed("line mask back in the geometry key", PIPELINE,
         "    key += \"|iv\";",
         "    key += \",\" + IntegerToString(g_linesVisible ? 1 : 0);\n    key += \"|iv\";")
    seed("discrete repaint stops forcing", UTIL,
         "void RepaintForDiscreteAction() {\n    ThrottledChartRedraw(true);\n}",
         "void RepaintForDiscreteAction() {\n    ThrottledChartRedraw(false);\n}")
    seed("dispatcher returns to the throttled repaint", KIT,
         "   RepaintForDiscreteAction();\n}",
         "   ThrottledChartRedraw();\n}")
    seed("F switch drops the repaint owner", EVENTS,
         "            RepaintForDiscreteAction();\n            return;\n        }",
         "            ChartRedraw();\n            return;\n        }")
    seed("L switch returns to the throttled repaint", EVENTS,
         "            // P-PERF-24: a key press is one event - paint it now instead of\n"
         "            // waiting for the next tick to pass the 100 ms throttle.\n"
         "            RepaintForDiscreteAction();",
         "            ThrottledChartRedraw();")
    seed("event names dropped from the ledger", EVENTS,
         "string P4EventName(const int id)",
         "string P4EventNameX(const int id)")
    seed("L switch reports no cost", EVENTS,
         'P4ReportSlow("lines toggle (L) [lines=',
         'P4ReportSlow("lines switch [lines=')
    seed("visibility flip renders the whole family again", EVENTS,
         "if(mustRender && g_buildStage != BUILD_STAGE_BLOCK && !visOnly)",
         "if(mustRender && g_buildStage != BUILD_STAGE_BLOCK)")
    seed("mask term back in the frame core", EVENTS,
         "                          IntegerToString(IsTriggerLevelsEnabled() ? 1 : 0) +\n"
         "                          IntegerToString(g_customPriceLineDragging ? 1 : 0) +\n"
         "                          IntegerToString(inpShowPipDistanceLabels ? 1 : 0);\n"
         "        frameSig = frameCore + \"|\" + IntegerToString(g_linesVisible ? 1 : 0);",
         "                          IntegerToString(g_linesVisible ? 1 : 0) +\n"
         "                          IntegerToString(IsTriggerLevelsEnabled() ? 1 : 0) +\n"
         "                          IntegerToString(g_customPriceLineDragging ? 1 : 0) +\n"
         "                          IntegerToString(inpShowPipDistanceLabels ? 1 : 0);\n"
         "        frameSig = frameCore + \"|\";")
    seed("the structure settle loses its recolour", EVENTS,
         "void StructureSwitchSettle(const uint p32t, const int idx, const bool visible)\n{\n   RuntimeSettingsSaveOverridesThrottled();\n   int touched = StructureRecolourWalk();",
         "void StructureSwitchSettle(const uint p32t, const int idx, const bool visible)\n{\n   RuntimeSettingsSaveOverridesThrottled();\n   int touched = 0;")
    seed("the group batch never settles", EVENTS,
         "   if(s_structSwitchBatch > 0) return;\n   StructureSwitchSettle(GetTickCount(), -1, false);",
         "   if(s_structSwitchBatch > 0) return;")
    seed("card 11 bypasses the recolour owner", PANELS,
         "         if(row==1)       { SetStructureVisible(0, (v>0.5)); flags=REFRESH_NONE; }",
         "         if(row==1)       { g_showStructure=(v>0.5); flags=REFRESH_BUFFERS; }")
    seed("recolour walk stops reading live colours", PIPELINE,
         "        color zc = GetZoneColorForLevel(step, trigOn, baseMult);",
         "        color zc = clrNONE;")
    seed("click path loses its breakdown", PANELS,
         '         _LOG_GATE_W Print("[W][PERF] click breakdown: button=", (int)p26btn, "ms panel=",\n'
         '               (int)p26pnl, "ms apply=", (int)p26apply, "ms control=", sparam);\n',
         "")
    # P-PERF-26b: the three phases said WHERE the time went but not WHICH control,
    # so a 531 ms press could not be reproduced. Drop the name and the line stops
    # naming its target - which is the regression this seed proves is caught.
    seed("click breakdown stops naming the control", PANELS,
         '"ms apply=", (int)p26apply, "ms control=", sparam);',
         '"ms apply=", (int)p26apply, "ms");')

    # 2. the syscall returns to the per-call blend
    seed("per-call background read", HTF,
         "   color bg = HTFBlendBackgroundColor();   // P-PERF-08: cached, one read per draw pass",
         "   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0);")
    seed("draw pass stops refreshing", HTF,
         "   HTFRefreshBlendBackground();   // P-PERF-08: once per draw pass, not once per colour",
         "")

    # 3. the guard is removed
    seed("combo guard removed", COMBO,
         "if(mode == s_lastMode && basePrice == s_lastBase && sig == s_lastSig)\n        return;",
         "")

    # 4. the ledger is dropped
    seed("phase stamp removed", EVENTS,
         "    g_pInitMsAtr = GetTickCount() - pInitTick;   // P-PERF-10 (ATR cache init + warmup)",
         "")
    seed("entry stops reporting", FULL,
         "P4InitLedgerTag(p4ind, p4ui),",
         "")

    # 7. the teardown writes what is already on disk again (P-PERF-27)
    seed("shadow bypassed", RUNTIME,
         "RSSetNext(p + ", "GlobalVariableSet(p + ")
    seed("flush unguarded", RUNTIME,
         "   if(!s_rsDirty) return;\n",
         "   if(false) return;\n")
    # P-PERF-44: the flush owner and the priming of the OTHER three blocks.
    seed("the flush grows a second owner", MENU,
         "   if(flushNow) { GVFlushRequest(); GVFlushCommit(); }",
         "   if(flushNow) { GlobalVariablesFlush(); GVFlushCommit(); }")
    seed("a saver stops priming from its load pass", PANELS,
         "   PrimePalRecentShadow();\n}",
         "}")
    seed("the ledger reports after the early return", MENU,
         "   GVLedgerReport(GV_BLOCK_UI, uiChanged, 6);\n",
         "")
    seed("a saver stops asking for the disk copy", HTF,
         "   GVFlushRequest();   // P-PERF-44 (2): ASK; the teardown's one commit pays for it",
         "   ;")
    seed("the HTF block loses its guard", HTF,
         "   if(htfChanged == 0) return;",
         "   if(false) return;")
    seed("shadow never primed", RUNTIME,
         "   RuntimeSettingsPrimeOverrideShadow();\n}",
         "}")
    seed("key deletion leaves the shadow stale", MENU,
         "   GVShadowsInvalidate();\n}",
         "}")
    seed("UI state unguarded again", MENU,
         "   if(uiChanged == 0) return;",
         "   if(false) return;")
    seed("palette unguarded again", PANELS,
         "   if(palChanged == 0) return;",
         "   if(false) return;")

    # 8. the first chart-change redraws everything again (P-PERF-28)
    seed("first chart-change redraws again", EVENTS,
         "        if(!s_ccPrimed)\n        {\n            s_ccPrimed = true;\n            viewportChanged = false;\n        }",
         "        ;")
    seed("chart-change breakdown dropped", EVENTS,
         '            _LOG_GATE_W Print("[W][PERF] chart change breakdown: redraw=", (int)p28redraw,\n',
         "")
    # P-PERF-49: each of the three new splits has a mutant that folds it back into
    # the function it was taken out of - the fault the group exists to catch.
    seed("chart-change tail folded back into one field", EVENTS,
         '        uint p28count = GetTickCount() - p28t;\n        p28t = GetTickCount();\n',
         '        // seed: the tail is one number again (RefreshLiveCountdown + repaint)\n')
    seed("render split dropped from the breakdown", EVENTS,
         '" render[levels="', '" render["')
    seed("labels relayout ledger dropped", EVENTS,
         '"[W][PERF] labels relayout:', '"[W][PERF] labels:')
    seed("deinit handler ledger dropped", EVENTS,
         '"[W][PERF] deinit handler breakdown:', '"[W][PERF] deinit:')

    # 12. keeping the family leaves the create path facing objects it did not
    #     make (P-PERF-38e)
    seed("already-on-chart treated as failure again", OBJFUN,
         "            if(ObjectFind(0, name) < 0) {",
         "            if(true) {")
    seed("adopted object keeps the old price", OBJFUN,
         "            ObjectSetDouble(0, name, OBJPROP_PRICE, normalizedPrice);\n",
         "")

    # 14. the legacy label sweep goes back to costing 11 walks per switch (P-PERF-38f)
    seed("legacy label sweep back on the generation", LABEL,
         "    if(!LegacyNameSchemeMigrated())\n",
         "    if(true)\n")
    seed("legacy label coverage dropped", LABEL,
         '            ObjectsDeleteAll(0, tfLblPrefix + "_LBL_");\n',
         "")
    seed("migration stamp gains a second owner", EVENTS,
         "   string stamp = NameSchemeStampName();",
         '   string stamp = "Biotak_NameScheme_" + GetCachedChartIdStr();')

    # 15. the keyboard and the panel fall out of step again (P-UI-40)
    seed("hotkey stops asking the UI", EVENTS,
         "            RequestUISync();   // P-UI-40: the TRIGGER card's SHOW row + the ring badge\n",
         "")
    seed("ring stops asking the UI", MENU,
         "      RequestUISync();   // P-UI-40: the Zones card's MID ZONES row shows this\n",
         "")
    seed("ring HTF item stops asking the UI", MENU,
         "      RequestUISync();   // P-UI-40b: the HTF card's SHOW row displays this flag\n",
         "")
    seed("tools STEP item stops asking the UI", MENU,
         "          RequestUISync();   // P-UI-40b: the STEP card's mode row displays this value\n",
         "")
    # P-UI-40b's second half: a NEW row that displays a state no writer asks about
    # must fail even though the hand list was never touched - this is the seed that
    # proves the derived-row rule has teeth of its own.
    seed("a row displays a state its writers never ask about", PANELS,
         "      case 8: if(row==0) return g_customPriceLevelWidth;\n",
         "      case 8: if(row==0) return g_customTHStartPrice;\n")
    # The anchor is the DRAIN's call, context included: R-KEYCAP added a SECOND
    # `PnlSyncOpenCard();` call site (the cap's own repaint), and a bare
    # `   PnlSyncOpenCard();` matched THAT one first - the seed then patched a
    # call no term of `check_ui_sync` asserts and "caught" nothing (the P-UI-81
    # lesson: a gate must read the SITE, never the first thing that looks like it).
    seed("drain stops repairing the card", PANELS,
         "   UpdateCircularBadges();\n   PnlSyncOpenCard();\n",
         "   UpdateCircularBadges();\n")
    seed("drain repaints before consuming", PANELS,
         "   UISyncConsume();\n",
         "")
    seed("event tail stops draining", FULL,
         "  UISyncDrain();\n  uint p4e = GetTickCount() - p4t;\n",
         "  uint p4e = 0;\n")
    seed("step card loses its reshape owner", PANELS,
         "   if(g_PnlOpen == 9) PnlOpen(9);\n",
         "")

    # 16. the long-press latch outlives its gesture again (P-UI-40c)
    seed("latch owner stops clearing the fired flag", MENU,
         "void UILongPressLatchClear()\n{\n   g_LongPressFired = false;\n",
         "void UILongPressLatchClear()\n{\n")
    seed("suppressed release forgets the latch", PANELS,
         "      if(UIShouldSuppressClick()) { UILongPressLatchClear(); return; }   // release after a drag/long-press\n",
         "      if(UIShouldSuppressClick()) return;   // release after a drag/long-press\n")
    seed("late release loses its guard", MENU,
         "   if(g_LongPressFired)\n   {\n      g_LongPressFired = false;\n",
         "   if(false)\n   {\n      g_LongPressFired = false;\n")
    seed("button-up net clears the fired latch", PANELS,
         "   g_MouseWasDown = false;\n",
         "   g_MouseWasDown = false;\n   g_LongPressFired = false;\n")

    # 13. an event stops settling the frame it owed (P-PERF-40)
    seed("event stops settling its frame", FULL,
         "  CoopPump();\n  uint p4c = GetTickCount() - p4t;\n",
         "  uint p4c = 0;\n")
    seed("lite event stops settling its frame", LITE,
         "  CoopPump();\n  uint p4c = GetTickCount() - p4t;\n",
         "  uint p4c = 0;\n")
    # P-PERF-40's seed follows its assertion: the tag it drops is the one the
    # check requires, and the line gained the P-UI-40 `panels=` term.
    seed("drain hides its own cost", FULL,
         '" settle=" + P4MsTag(p4c) +\n               " panels=" + P4MsTag(p4e) + "]",',
         '" panels=" + P4MsTag(p4e) + "]",')

    # 11. the forced reload forgets that the chart is already drawn (P-PERF-38d)
    seed("timeframe change force-clears again", EVENTS,
         "        if(!g_adoptPreviousTopology) g_forceClearOnNextDraw = true;",
         "        g_forceClearOnNextDraw = true;")
    seed("first pass starts with an empty signature again", EVENTS,
         '        if(s_lastLevelSig == "" && g_adoptPreviousTopology) s_lastLevelSig = levelSig;\n',
         "")
    seed("switch stops handing the family over", EVENTS,
         "        SaveTopologyAdoptionStamp();\n",
         "")
    seed("removal leaves the adoption stamp behind", EVENTS,
         "        // P-PERF-38d: the objects go with the removal, so the next attach must\n"
         "        // NOT adopt a chart this instance emptied.\n"
         "        ClearTopologyAdoptionStamp();\n",
         "")
    seed("fingerprint drops the level count", EVENTS,
         "   fp = fp * 31 + inpMaxLevels;\n",
         "")
    seed("adoption never resolved", EVENTS,
         "    ResolveTopologyAdoption();\n",
         "")

    # 11b. the stale PRICE is answered with a wipe again (P-LEVEL-FOREIGN-02)
    seed("the fingerprint names the period again", EVENTS,
         "int AdoptionFingerprint()\n{\n   int fp = NAME_SCHEME_ID;",
         "int AdoptionFingerprint()\n{\n   int fp = NAME_SCHEME_ID;\n"
         "   fp = fp * 31 + (int)Period();")
    seed("the fingerprint names the daily-close anchor again", EVENTS,
         "int AdoptionFingerprint()\n{\n   int fp = NAME_SCHEME_ID;",
         "int AdoptionFingerprint()\n{\n   int fp = NAME_SCHEME_ID;\n"
         "   fp = fp * 31 + (int)MathRound(g_dailyClosePriceForTH * 100000.0) % 1000003;")
    seed("the reconciliation stops walking the chart", PIPELINE,
         "        const string nm = ObjectName(0, i, -1, -1);",
         "        const string nm = \"\";")
    seed("the reconciliation deletes the live ladder too", PIPELINE,
         "        if(ProducedLadderName(nm, produced, pc)) continue;\n        ArrayResize(doomed, nd + 1);",
         "        ArrayResize(doomed, nd + 1);")
    seed("the reconciliation judges an unusable window", PIPELINE,
         "    if(!(vpTop > vpBottom) || vpBottom <= 0) return 0;   // unusable window: no judgement\n",
         "")
    seed("the reconciliation runs on an empty build", PIPELINE,
         "    if(lineCount <= 0) return 0;                        // nothing produced: nothing to say\n",
         "")
    seed("the index sweep runs on a wiped chart too", PIPELINE,
         "                if(g_adoptPreviousTopology && !s_foreignSweepDone)\n                {",
         "                if(true)\n                {")
    seed("the index sweep runs on every pitch drift", PIPELINE,
         "                if(g_adoptPreviousTopology && !s_foreignSweepDone)\n                {",
         "                if(g_adoptPreviousTopology)\n                {")
    seed("the sweep deletes while it walks", PIPELINE,
         "        ArrayResize(doomed, nd + 1);\n        doomed[nd++] = nm;",
         "        DeleteIndicatorObjectManaged(nm, true);")
    seed("the sweep treats a zone border as a band", PIPELINE,
         '        if(StringFind(nm, "_Zone_") >= 0) continue;   // a border sub-object: its band decides\n',
         "")

    # 17. the custom price line's ON/OFF + interaction state (P-UI-45)
    seed("PIN button stops moving the mode OFF", MENU,
         "            DeactivateCustomPriceMode(\"ring PIN\");\n",
         "")
    seed("ESC stops routing through the exit owner", EVENTS,
         "                DeactivateCustomPriceMode(\"ESC\");\n",
         "")
    seed("the line stops being grabbable (the movement regression)", EVENTS,
         "    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);   // P-UI-48: this IS the drag\n",
         "    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, false);\n")
    seed("a fifth hand-written copy of the property set returns", EVENTS,
         "            if(!CreateCustomPriceLine(currentPrice, Digits)) return;\n",
         "            if(!CreateCustomPriceLine(currentPrice, Digits)) return;\n"
         "            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);\n")
    seed("the clear owner loses its guarded read", EVENTS,
         "    if(!(bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED)) return;\n",
         "")
    seed("the button-up finalizer stops deferring the clear", PANELS,
         "   g_customPriceNativeDrag = true;\n",
         "")
    seed("the finalizer clears the selection inline again", PANELS,
         "   g_customPriceNativeDrag = true;\n",
         "   ClearCustomPriceSelection();\n   g_customPriceNativeDrag = true;\n")
    seed("the grab stops selecting the line", EVENTS,
         "                    if(!terminalGrab)\n"
         "                        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);\n",
         "")
    seed("a creation path pre-selects the line again", EVENTS,
         "        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);\n"
         "    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, Z_CHART_LABEL);   // P-UI-31\n",
         "        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);\n"
         "    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, Z_CHART_LABEL);   // P-UI-31\n")
    seed("the creator clears the selection mid-gesture again", EVENTS,
         "    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&\n"
         "       (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED))\n",
         "")
    seed("the grab hit test goes back to the conversion MT4 refuses", EVENTS,
         "    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, priceAtCursor)) return false;\n",
         "    if(!ChartTimePriceToXY(0, 0, 0, linePrice, x, y)) return false;\n")
    seed("a foreign press stops deferring the clear", EVENTS,
         "                    g_customPriceNativeDrag = true;\n                }\n",
         "                }\n")
    seed("a foreign press clears the selection inline again", EVENTS,
         "                    g_customPriceNativeDrag = true;\n                }\n",
         "                    ClearCustomPriceSelection();\n                }\n")
    seed("the carry writes on the press edge again", EVENTS,
         "                bool pastSlop = (MathAbs(cursorY - s_ownGrabY) >= CP_DRAG_SLOP);\n"
         "                if(g_customPriceDragOwn && !pressEdge && pastSlop && currentLinePrice > 0 &&\n",
         "                bool pastSlop = (MathAbs(cursorY - s_ownGrabY) >= CP_DRAG_SLOP);\n"
         "                if(g_customPriceDragOwn && pastSlop && currentLinePrice > 0 &&\n")
    seed("the carry loses its slop fence", EVENTS,
         "                if(g_customPriceDragOwn && !pressEdge && pastSlop && currentLinePrice > 0 &&\n",
         "                if(g_customPriceDragOwn && !pressEdge && currentLinePrice > 0 &&\n")
    seed("the carry snaps the line onto the cursor again", EVENTS,
         "                            double wishPrice = s_ownGrabPrice + (cursorPrice - s_ownGrabCursorPrice);\n",
         "                            double wishPrice = cursorPrice;\n")
    seed("the drag release wipes the levels again", EVENTS,
         "                bool movedByGesture = (s_ownLastWrite > 0.0) ||\n",
         "                g_forceClearOnNextDraw = true;\n"
         "                bool movedByGesture = (s_ownLastWrite > 0.0) ||\n")
    seed("the drag release settles whether or not anything moved", EVENTS,
         "                if(movedByGesture)\n",
         "                if(true)\n")
    seed("the drag stops taking the view lock", EVENTS,
         "                    CustomPriceDragLockOn();\n",
         "")
    # P-UI-61: the re-assert moved into the drag's frame owner, so the seed follows it.
    seed("the drag stops re-asserting the view lock", EVENTS,
         "    CustomPriceDragReassertLock();\n",
         "")
    seed("the stale-drag heal stops checking the button", EVENTS,
         "    if(!UILeftButtonUp()) return;             // still holding the button (one owner, P-UI-73)\n",
         "")
    seed("the stale-drag heal probes the button itself again", EVENTS,
         "    if(!UILeftButtonUp()) return;             // still holding the button (one owner, P-UI-73)\n",
         "    if((TerminalInfoInteger(TERMINAL_KEYSTATE_LEFT) & 1) != 0) return;\n")
    seed("the UI press guard is dropped", PANELS,
         "      if(pressStart && g_DragOwner != DRAG_NONE) ClearCustomPriceSelection();\n",
         "")
    seed("a BaseKnot box drag stops clearing the line's selection", PANELS,
         "      if(sparam != g_customPriceHorizontalLineName) ClearCustomPriceSelection();\n",
         "")
    seed("click handler stops arming the deferred clear", EVENTS,
         "        if(!isDoubleClick) g_customPriceNativeDrag = true;\n",
         "")
    seed("exit owner forgets the Input default", EVENTS,
         "    g_thStartPointType = inpTHStartPointType;\n    g_customPriceKeyboardOverride = false;\n",
         "    g_customPriceKeyboardOverride = false;\n")
    # P-UI-61: anchors on the native-drag channel's frame call - the `uint dragNowMs`
    # line it used to anchor on is gone, because the budget now lives in one owner.
    seed("the drag handler writes the line mid-drag again", EVENTS,
         "        if(anchorMoved) CustomPriceDragFrame(false);\n",
         "        ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, \"x\");\n"
         "        if(anchorMoved) CustomPriceDragFrame(false);\n")
    seed("the drag handler resets the gesture flag on every step", EVENTS,
         "        if(anchorMoved) CustomPriceDragFrame(false);\n",
         "        g_customPriceLineDragging = false;\n"
         "        if(anchorMoved) CustomPriceDragFrame(false);\n")
    seed("the drag tooltip stops being written at the release", EVENTS,
         "                UpdateCustomPriceTooltip();\n",
         "")

    # 18. a rendered control that moves nothing anybody reads (P-UI-46/47)
    # BKMAGNET2-OFF (2026-09-15): the ADJUST magnet P-BK-21 had added is
    # commented out again, so the two MAGNET rows are retired rows again and
    # the P-UI-47 specimen (re-render the retired row) is the fault again.
    # The engine MUST stay comments, not merely uncalled: the reader index is
    # textual, so a dormant-but-compiling `BaseKnotMagnetPrice` would count as
    # a reader and the re-added row would pass while moving nothing.
    # P-BK-61 (2026-09-16): THE TWO MAGNET SEEDS MOVED OUT OF THIS LIST, and the
    # reason is the check's own rule rather than a weakening of it. BKMAGNET2-OFF had
    # left both MAGNET rows hidden with NO reader at all, so re-rendering one was this
    # check's specimen ("a control whose press moves nothing"). The box' new HANDLE
    # magnet («با کنترل هم مگنت فعال میشه ... حرکت رو چسبوند به کندل های و لو که دقیق
    # باشه») reads `inpEnableMagnet` / `inpMagnetSensitivityPips` again — deliberately,
    # through ONE gated reader in BaseKnotTool (BaseKnotGripSnapPrice; the scoping is
    # asserted by panel-wiring-audit's `[bkmagnet]` group) — so a re-rendered row would
    # now move state that IS read elsewhere and can no longer be a specimen here.
    # What still proves this check is the MIDPOINT specimen below (P-LBL-09 moved it
    # there for exactly the same reason: that flag is still read by nobody). The rows
    # themselves stay HIDDEN, and `check_bkmagnet` fails loudly if one comes back —
    # which is the right place for that decision to be argued, not this seed.
    # P-LBL-09 (2026-09-14): the ATR card's ROW GAP row is no longer the dead one
    # - `g_atrLabelRowGap` became LIVE, because the bottom-right trade card's
    # layout now reads it. The seed moves to the still-dead MIDPOINT row of card
    # 1 (`g_showMidpointLine`: its line is deleted every render by the pipeline's
    # own legacy cleanup, and nothing outside the panel reads the flag).
    seed("a dead slider is rendered again", PANELS,
         "      PnlSpecAdd(1, PNL_K_LEGACY, 7, 1, \"contrast\");\n",
         "      PnlSpecAdd(1, PNL_K_LEGACY, 7, 1, \"contrast\");\n"
         "      PnlSpecAdd(1, PNL_K_LEGACY, 9, 1, \"line\");\n")
    seed("a TH source row reads its mode back from its own mirrors", PANELS,
         "            g_thLabelsMode=m1;\n",
         "            if(g_showTHLabels && m1==0) m1=1;\n"
         "            g_thLabelsMode=m1;\n")
    seed("a TH source press stops repainting the master row", PANELS,
         "            RequestUISync();\n            string opT2=",
         "            string opT2=")

    # 19. the custom-price SOURCE, the NaN fence and the zone gap (P-UI-56/57/58)
    seed("the frame path overwrites the placement with the Input again", EVENTS,
         "            bool priceMoved = (MathAbs(g_customTHStartPrice - srcPrice) > s_cachedPoint * 0.1);\n",
         "            GlobalVariableSet(\"Biotak_CustomPrice_\" + GetCachedChartIdStr(), srcPrice);\n"
         "            bool priceMoved = (MathAbs(g_customTHStartPrice - srcPrice) > s_cachedPoint * 0.1);\n")
    seed("the live price key goes back to the symbol scope", EVENTS,
         'string CustomPriceGVName()         { return "Biotak_CustomPrice_" + GetCachedChartIdStr(); }',
         'string CustomPriceGVName()         { return "Biotak_CustomPrice_" + GetCachedSymbol(); }')
    seed("a placement path bypasses the one writer", EVENTS,
         "                CustomPricePersistPlacement(selectedPrice);   // P-UI-56: one writer\n",
         "                GlobalVariableSet(\"Biotak_CustomPrice_\" + GetCachedChartIdStr(), selectedPrice);\n")
    seed("the centre price loses its NaN fence", PIPELINE,
         "if(!MathIsValidNumber(centerPrice) || centerPrice <= 0 || stepSizeCount < 1) return 0;",
         "if(centerPrice <= 0 || stepSizeCount < 1) return 0;")
    seed("a zone band stops being clamped to the line gap", PIPELINE,
         "        double zoneHeight = ClampZoneHalfHeight(zoneStepSize * config.zoneHeightPercent * 0.5,",
         "        double zoneHeight = (zoneStepSize * config.zoneHeightPercent * 0.5,")
    seed("the pip owner stops fencing zero", PERFOPT,
         "        g_cachedPipSize = (p > 0.0 && MathIsValidNumber(p)) ? p : 0.00001;\n",
         "")
    seed("a band is clamped by the interval on one side only again", PIPELINE,
         "            double zoneHeight = ClampZoneHalfHeightBoth(zoneStepSize * config.zoneHeightPercent * 0.5,\n"
         "                                                        stepSize, stepAbove);",
         "            double zoneHeight = ClampZoneHalfHeightBoth(zoneStepSize * config.zoneHeightPercent * 0.5,\n"
         "                                                        stepSize, 0.0);")

    # 20. nothing an instance created may outlive its removal (P-UI-60)
    seed("the naming-migration stamp stops being cleared on removal", EVENTS,
         "        GlobalVariableDel(NameSchemeStampName());\n",
         "")
    seed("a chart-scoped key drops out of the removal cleanup", GLOBALS,
         '    gvars[20] = "Biotak_ViewLock_" + chartIdStr;\n',
         "")
    seed("the removal stops sweeping the global-variable families", EVENTS,
         "        CleanupAllGlobalVariables();\n",
         "")

    # 21. the drag's anchor back inside the redraw gate, and the frame dropped
    #     instead of owed (P-UI-61)
    seed("the drag's anchor goes back inside the redraw gate", EVENTS,
         "                if(currentLinePrice > 0 && CustomPriceDragAnchorSet(currentLinePrice))\n"
         "                    CustomPriceDragFrame(false);\n",
         "                if(currentLinePrice > 0 &&\n"
         "                   MathAbs(currentLinePrice - g_customTHStartPrice) > _Point * 0.5)\n"
         "                {\n"
         "                    uint nowMs = GetTickCount();\n"
         "                    if(nowMs - g_lastDragRedrawTime > DRAG_REDRAW_THROTTLE_MS)\n"
         "                    {\n"
         "                        g_customTHStartPrice = currentLinePrice;\n"
         "                        RedrawAllObjects(true);\n"
         "                        g_lastDragRedrawTime = nowMs;\n"
         "                    }\n"
         "                }\n")
    seed("the drag-anchor owner stops persisting the value", EVENTS,
         "    CustomPricePersistPlacement(price);\n",
         "")
    seed("the release stops forcing the frame", EVENTS,
         "                    CustomPriceDragFrame(true);   // force: the gesture's last pixel is always painted\n",
         "                    CustomPriceDragFrame(false);\n")
    seed("a drag handler regains a throttle of its own", EVENTS,
         "                int cursorY = (int)dparam;\n",
         "                if(GetTickCount() - g_lastDragRedrawTime > DRAG_REDRAW_THROTTLE_MS)\n"
         "                    RedrawAllObjects(true);\n"
         "                int cursorY = (int)dparam;\n")
    seed("the native-drag channel bypasses the frame owner", EVENTS,
         "        if(anchorMoved) CustomPriceDragFrame(false);\n",
         "        if(anchorMoved) RedrawAllObjects(true);\n")

    # 22. the zone picture is one bit again, and a dead cache slot is an object again
    #     (P-UI-62)
    seed("the style axis owns visibility again", "Biotak/ConstantsAndEnums.mqh",
         "    ZONE_STYLE_BOX_OUTLINED = 2   // Outlined (band AND its edge)",
         "    ZONE_STYLE_HIDDEN = 2")
    seed("a build loop sets one half only", PIPELINE,
         "        zones[zIdx].outline = (config.zoneStyle != ZONE_STYLE_BOX_FILLED);    // P-UI-62\n",
         "")
    seed("the band is created after its edge", ZONEFACTORY,
         "    if(request.filled && !objectExists) {\n"
         "        if(!ObjectCreate(0, request.name, OBJ_RECTANGLE, 0, startTime, request.topPrice, endTime, request.bottomPrice)) {",
         "    if(request.filled && !objectExists) {\n"
         "        CreateOrUpdateZoneBorder(request.name + \"_B_Top\", startTime, request.topPrice, endTime, request.topPrice, borderColor, borderStyle, borderWidth, true);\n"
         "        if(!ObjectCreate(0, request.name, OBJ_RECTANGLE, 0, startTime, request.topPrice, endTime, request.bottomPrice)) {")
    seed("the kind change reads one bit", ZONEFACTORY,
         "    bool kindChanged = (!inCache) || (entrySaysBand != request.filled) ||\n"
         "                       (cache.lastOutline != request.outline);",
         "    bool kindChanged = (!inCache) || (entrySaysBand != request.filled);")
    seed("the edge-only picture keeps the band", ZONEFACTORY,
         "            DeleteIndicatorObjectManaged(request.name, true);\n",
         "")
    seed("the cache stops recording that a picture owns no rectangle", ZONEFACTORY,
         "                    request.filled, borderStyle, borderWidth, request.outline, request.filled);",
         "                    request.filled, borderStyle, borderWidth, request.outline, true);")
    seed("creating the band stops clearing the negative mark", ZONEFACTORY,
         "        CacheForgetAbsent(request.name);\n",
         "")
    seed("a visibility walk writes through a dead slot", VISIBILITY,
         "        if(!CacheSlotIsLive(i)) continue;\n",
         "")
    seed("the recolour walk repaints a dead slot", PIPELINE,
         "        if(!CacheSlotIsLive(i)) continue;\n",
         "")
    seed("the negative mark outranks a live entry again", OBJCACHE,
         "    if(!inCache && CacheIsAbsentKnown(name)) return false;",
         "    if(CacheIsAbsentKnown(name)) return false;")
    seed("the card offers the retired switch again", PANELS,
         'opts="Filled|Empty|Outlined"',
         'opts="Filled|Empty|Hidden"')
    seed("the retired value stops being adopted", RUNTIME,
         'if(ClampSettingInt((int)GlobalVariableGet(p + "MZ"), 0, 2) == 2)',
         "if(false)")
    seed("the adoption loses its stamp", RUNTIME,
         'GlobalVariableSet(p + "MZ2", 1.0);\n',
         "")
    seed("the adopted layout only lives in memory", RUNTIME,
         'GlobalVariableSet(p + "MZ", ZONE_STYLE_BOX_FILLED);\n',
         "")

    # 23. the two transparencies fall back into one, and the edge picture goes back to
    #     an invisible line (P-UI-63/64)
    seed("the edge fades with the band again", ZONEFACTORY,
         "    if(request.borderTransparency >= 0 && request.borderTransparency <= 100)",
         "    if(false)")
    seed("the band is painted with the edge's colour", ZONEFACTORY,
         "        ObjectSetInteger(0, request.name, OBJPROP_COLOR, finalColor);",
         "        ObjectSetInteger(0, request.name, OBJPROP_COLOR, borderColor);")
    seed("a producer drops the edge's transparency", PIPELINE,
         "            request.borderTransparency = inpMidZoneBorderTransparency;\n",
         "")
    seed("the edge is inset off the band's boundary", ZONEFACTORY,
         "                                     startTime, request.topPrice, endTime, request.topPrice,\n",
         "                                     startTime, request.topPrice, endTime, request.topPrice - _Point,\n")
    seed("the edge picture keeps the invisible default", PANELS,
         "                           if(newPicture != ZONE_STYLE_BOX_FILLED && g_midZoneBorderWidth <= 1)",
         "                           if(false)")
    seed("the visible width drifts", "Biotak/ConstantsAndEnums.mqh",
         "#define MIDZONE_EDGE_VISIBLE_WIDTH 5",
         "#define MIDZONE_EDGE_VISIBLE_WIDTH 1")
    seed("the edge transparency row loses its writer", PANELS,
         "         else if(row==7)  { g_midZoneBorderTransparency=ClampInt((int)MathRound(v),0,100); flags=REFRESH_BUFFERS; }\n",
         "")
    seed("the edge transparency stops being persisted", RUNTIME,
         '   RSSetNext(p + "ZBT", g_midZoneBorderTransparency);   // P-UI-63\n',
         "")

    # 24. the click claim goes back to a wall-clock window (P-UI-65)
    seed("the claim goes back to a wall-clock deadline", MENU,
         "   uint nowMs = GetTickCount();\n"
         "   // The second event of the release this hand just took - still this gesture's.\n"
         "   if(s_uiReleaseEchoMs != 0 && (int)(nowMs - s_uiReleaseEchoMs) < 0) return true;\n",
         "   return (GetTickCount() < s_uiClickClaimMs);\n")
    seed("the arm stops binding the claim to its press", MENU,
         "   s_uiClickClaimDown = g_MouseWasDown;\n"
         "   s_uiClickClaimSeq  = g_UIPressSeq;\n",
         "")
    seed("a press stops owning its own click", MENU,
         "   if(pressStart) g_UIPressSeq++;\n",
         "")
    seed("a press-time claim outlives its press", MENU,
         "   if(s_uiClickClaimDown && s_uiClickClaimSeq != g_UIPressSeq)\n",
         "")
    seed("the twin-event echo is dropped", MENU,
         "   if(s_uiReleaseEchoMs != 0 && (int)(nowMs - s_uiReleaseEchoMs) < 0) return true;\n",
         "")
    seed("the release-armed claim loses its TTL", MENU,
         "   if(!s_uiClickClaimDown && (int)(nowMs - s_uiClickClaimMs) >= 0)\n",
         "")
    seed("the claim state crosses an attach", MENU,
         "   UIReleaseClaimReset();\n   CircCreateOrb();",
         "   CircCreateOrb();")
    seed("the reset can drop a live gesture's claim", MENU,
         "void UIReleaseClaimReset()\n{\n   if(g_MouseWasDown) return;\n",
         "void UIReleaseClaimReset()\n{\n")
    seed("the reset fires mid-release", MENU,
         "   if(s_uiReleaseEchoMs != 0 && (int)(GetTickCount() - s_uiReleaseEchoMs) < 0) return;\n"
         "   s_uiClickClaim     = false;\n",
         "   s_uiClickClaim     = false;\n")

    # 25. P-UI-66 - the look goes back into the build's copy / the key (look-live)
    seed("the line paint reads the build's look again", PIPELINE,
         "            bool isNew = CreateOrUpdateHLine(lines[i].name, lines[i].price,\n"
         "                                              lineClr, lineStyle, lineWidth,",
         "            bool isNew = CreateOrUpdateHLine(lines[i].name, lines[i].price,\n"
         "                                              lines[i].clr, lines[i].lineStyle, lines[i].lineWidth,")
    seed("a line-look input goes back into the geometry key", PIPELINE,
         "    // P-UI-66 - THE LINE LOOK IS NOT GEOMETRY, SO IT IS NOT A KEY TERM.\n",
         "    // P-UI-66 - THE LINE LOOK IS NOT GEOMETRY, SO IT IS NOT A KEY TERM.\n"
         "    key += \"|\" + IntegerToString(g_lineStyle);\n")
    seed("the zone border stops being a live read", PIPELINE,
         "            request.borderTransparency = inpMidZoneBorderTransparency;",
         "            request.borderTransparency = 0;")

    # 26. P-UI-66 - the ALL cell degrades into a duplicate switch (dual-all)
    seed("the ALL face mirrors one member again", PANELS,
         "            on  = PnlAllCellOn(item,row);",
         "            on  = true;")
    seed("the ALL cell owns its own row again", PANELS,
         "            PnlAllCellSpan(dui,dur,af,ac);",
         "            int af=dn; int ac=1;")
    seed("the group press is unbudgeted again", PANELS,
         "            if(grouped) StructureSwitchBatchBegin();\n",
         "")

    # 27. P-UI-67 - the SS/LS order row: wrong home, two owners
    seed("the SS/LS row goes back to the Zones card", PANELS,
         "      // MIDPOINT-OFF (2026-09-13): the midpoint LINE is retired",
         "      PnlSpecAdd(1, PNL_K_LEGACY, 8, 1, \"swap\");\n"
         "      // MIDPOINT-OFF (2026-09-13): the midpoint LINE is retired")
    seed("the switch leaves a stale override standing", PANELS,
         "                            SSLSOrderOverrideClear();\n",
         "")
    seed("the override loses its persister", GLOBALS,
         "    GlobalVariableSet(\"Biotak_SSLSFirst_\" + GetCachedChartIdStr(), (double)v);\n",
         "")
    seed("a surface writes the override key directly", EVENTS,
         "    SSLSOrderOverrideClear();\n    if(restoredSSLSFirst == 0 || restoredSSLSFirst == 1)",
         "    g_sslsFirstOverride = -1;\n"
         "    GlobalVariableDel(\"Biotak_SSLSFirst_\" + chartIdStr);\n"
         "    if(restoredSSLSFirst == 0 || restoredSSLSFirst == 1)")
    seed("a surface spells the SS/LS caption itself", PANELS,
         "      kind=1; label=PNL_LBL_SSLS_ORDER;",
         "      kind=1; label=\"LS FIRST\";")

    # P-UI-92: a click on the UI must not reach the chart - one seed per way it could.
    seed("the hidden ring menu keeps claiming pixels", PANELS,
         "   if(g_UI.menuVisible)\n   {\n      int bx = 0, by = 0, bw = 0, bh = 0;",
         "   if(true)\n   {\n      int bx = 0, by = 0, bw = 0, bh = 0;")
    seed("the menu rect stops being measured", PANELS,
         "      PnlComputeMenuBounds(bx,by,bw,bh);\n",
         "")
    seed("the open card stops being claimed", PANELS,
         "   if(PnlPointInside(mx,my)) return true;",
         "   if(false) return true;")
    seed("the floating strip stops being claimed", PANELS,
         "   if(BkMiniStripPointInside(mx,my)) return true;",
         "   if(false) return true;")
    seed("the countdown tag stops being claimed", PANELS,
         "   if(LiveCountdownPointInside(mx,my)) return true;",
         "   if(false) return true;")
    #  (P-BK-65 re-anchored these two: the latch's UI term is now the second term of
    #  its condition, the first being the live-gesture guard)
    seed("the box drag latch arms from a press on the panel", BASEKNOT,
         "            !UIPointerOverSurface((int)lparam, (int)dparam) &&\n",
         "            true &&\n")
    seed("one box-tool site stops asking where the pixel is", BASEKNOT,
         "if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;",
         "if(false) return true;")
    seed("the custom-price pick ignores the published claim", EVENTS,
         "!UIPeekClickClaim() && !UIPointerOverSurface((int)lparam, (int)dparam)",
         "true")
    seed("the custom-price line can be grabbed through a panel", EVENTS,
         "pressEdge && !UIPointerOverSurface((int)lparam, (int)dparam) &&",
         "pressEdge &&")
    seed("a second writer publishes the claim", EVENTS,
         "    if(id == CHARTEVENT_CLICK && g_waitingForCustomPriceClick &&",
         "    g_uiClickClaimLive = false;\n"
         "    if(id == CHARTEVENT_CLICK && g_waitingForCustomPriceClick &&")
    seed("arming a claim stops publishing it", MENU,
         "   UIPublishClickClaim();   // P-UI-92b: the domain half of this gesture reads the mirror\n",
         "")
    seed("taking a claim stops publishing its echo", MENU,
         "   UIPublishClickClaim();\n   return true;\n",
         "   return true;\n")
    seed("the press edge stops retiring a stale claim", MENU,
         "   if(pressStart) UIPublishClickClaim();\n",
         "")
    seed("the peek drops the press-bound identity", GLOBALS,
         "   if(g_uiClickClaimDown) return (g_uiClickClaimSeq == g_uiPressSeq);",
         "   if(g_uiClickClaimDown) return true;")
    seed("the peek ignores the up-armed TTL", GLOBALS,
         "   if(g_uiClickClaimMs != 0 && (int)(GetTickCount() - g_uiClickClaimMs) >= 0) return false;",
         "   if(g_uiClickClaimMs != 0) return false;")

    # P-BUILD-01: the Lite entry must keep compiling - one seed per way it broke.
    seed("a shared module calls a UI-only function unguarded", BASEKNOT,
         "            !UIPointerOverSurface((int)lparam, (int)dparam) &&\n",
         "            PnlPointInside((int)lparam, (int)dparam) &&\n"
         "            !UIPointerOverSurface((int)lparam, (int)dparam) &&\n")
    seed("the shared call loses its Lite stub", GLOBALS,
         "bool UIPointerOverSurface(const int mx,const int my)\n{\n   return false;\n}\n#endif\n",
         "#endif\n")
    seed("the stub stops being compiled in Lite", GLOBALS,
         "#ifdef BUILD_LITE\n//+------------------------------------------------------------------+",
         "#ifndef BUILD_LITE\n//+------------------------------------------------------------------+")
    seed("the Custom Price pick calls the UI surface test directly", EVENTS,
         "!UIPeekClickClaim() && !UIPointerOverSurface((int)lparam, (int)dparam)",
         "!UIPeekClickClaim() && !PnlPointInside((int)lparam, (int)dparam)")

    # P-TICKWRAP: the deadline reader must ask its owner, not compare a clock.
    seed("a tick window is compared against the clock absolutely", EVENTS,
         "TickDeadlinePending(g_suppressDeleteEventsUntilMs)",
         "(g_suppressDeleteEventsUntilMs != 0 && GetTickCount() <= g_suppressDeleteEventsUntilMs)")

    caught = 0
    for label, rel, old, new in seeds:
        src = read(rel)
        if old not in src:
            print("  STALE SEED (hard error): %s @ %s" % (label, rel))
            return 1
        rc = run({rel: src.replace(old, new, 1)})
        if rc == 0:
            print("  MISSED: %s @ %s" % (label, rel))
        else:
            caught += 1
    if caught != len(seeds):
        print("  selftest: %d/%d faults caught" % (caught, len(seeds)))
        return 1
    print("  selftest: %d seeded faults, all caught" % caught)
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(run())
