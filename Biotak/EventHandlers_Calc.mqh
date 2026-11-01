// EventHandlers_Calc.mqh - EventHandlers split 2026-09-29: exact lines 1497-2945 of EventHandlers.mqh, byte-identical, zero renames.
// 2026-10-31 (P-SIZE-1500): the teardown owner moved to EventHandlers_Deinit.mqh and is
// included HERE, at the same point in the unit, so every definition keeps its order.
#ifndef EVENT_HANDLERS_CALC_MQH
#define EVENT_HANDLERS_CALC_MQH

#include "EventHandlers_Deinit.mqh"


//+------------------------------------------------------------------+
//| Clear all level objects from all modes (OPTIMIZED + SAFE)       |
//|                                        |
//| CRITICAL FIX: Added error handling and retry logic              |
//+------------------------------------------------------------------+
//| Clear all level objects from all modes (OPTIMIZED + SAFE)       |
//| Uses suffix registries for maintainable bulk deletion           |
//+------------------------------------------------------------------+
void ClearAllLevels(const string objectPrefix, bool clearZones = true)
{
    if(StringLen(objectPrefix) == 0) return;

    #ifdef ENABLE_DEBUG_LOGS
    static datetime s_lastClearLog = 0;
    if(TimeCurrent() - s_lastClearLog > 5) {
        Print("[D][GEN] [MT4] [CLEAN] CLEARING ALL LEVELS with prefix: ", objectPrefix);
        s_lastClearLog = TimeCurrent();
    }
    #endif

    // PERF: Use ObjectsDeleteAll with prefix+suffix for native bulk deletion.
    // Each ObjectsDeleteAll is a single native call that matches by prefix internally.
    static string ZONE_SUFFIXES[];
    static string LEVEL_SUFFIXES[];
    static string LEGACY_SUFFIXES[];
    static bool s_suffixInit = false;
    if(!s_suffixInit) {
        int zoneCount = 0;
        int levelCount = 0;
        GetAllZoneSuffixes(ZONE_SUFFIXES, zoneCount);
        GetAllLevelSuffixes(LEVEL_SUFFIXES, levelCount);

        // Legacy suffixes for backward compatibility
        ArrayResize(LEGACY_SUFFIXES, 16);
        int k = 0;
        LEGACY_SUFFIXES[k++] = "SharedPattern_";
        LEGACY_SUFFIXES[k++] = "TH_Level_";
        LEGACY_SUFFIXES[k++] = "S_";
        LEGACY_SUFFIXES[k++] = "TriggerTH_Up_";
        LEGACY_SUFFIXES[k++] = "TriggerTH_Down_";
        LEGACY_SUFFIXES[k++] = "StructureLevel1_Up_";
        LEGACY_SUFFIXES[k++] = "StructureLevel1_Down_";
        LEGACY_SUFFIXES[k++] = "StructureLevel2_Up_";
        LEGACY_SUFFIXES[k++] = "StructureLevel2_Down_";
        LEGACY_SUFFIXES[k++] = "StructureLevel3_Up_";
        LEGACY_SUFFIXES[k++] = "StructureLevel3_Down_";
        LEGACY_SUFFIXES[k++] = "StructureLevel4_Up_";
        LEGACY_SUFFIXES[k++] = "StructureLevel4_Down_";
        LEGACY_SUFFIXES[k++] = "StructureLevel5_Up_";
        LEGACY_SUFFIXES[k++] = "StructureLevel5_Down_";
        LEGACY_SUFFIXES[k++] = "Mid";
        s_suffixInit = true;
    }

    g_suppressDeleteEvents = true;
    int totalDeleted = 0;

    // Delete zone objects (only if clearZones is true)
    if(clearZones) {
        for(int z = 0; z < ArraySize(ZONE_SUFFIXES); z++) {
            totalDeleted += ObjectsDeleteAll(0, objectPrefix + ZONE_SUFFIXES[z]);
        }
    }

    // Delete level objects (pipeline suffixes)
    for(int s = 0; s < ArraySize(LEVEL_SUFFIXES); s++) {
        totalDeleted += ObjectsDeleteAll(0, objectPrefix + LEVEL_SUFFIXES[s]);
    }

    // Delete legacy objects
    for(int l = 0; l < ArraySize(LEGACY_SUFFIXES); l++) {
        if(!clearZones && LEGACY_SUFFIXES[l] == "TH_Level_") continue;
        totalDeleted += ObjectsDeleteAll(0, objectPrefix + LEGACY_SUFFIXES[l]);
    }

    g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
    g_suppressDeleteEvents = false;
    MarkDrawGeneration();   // P-PERF-02: what we rendered is gone from the chart

    #ifdef ENABLE_DEBUG_LOGS
    if(totalDeleted > 0) {
        Print("[D][GEN] ClearAllLevels PERF: Deleted ", totalDeleted, " objects via bulk delete");
    }
    #endif

    // PERF: Invalidate matching cache entries (early-exit scan using occupied count)
    if(g_objectCacheSize > 0) {
        int prefixLen = StringLen(objectPrefix);
        ushort prefixFirstChar = StringGetCharacter(objectPrefix, 0);
        int invalidated = 0;
        int visited = 0;
        int snapshot = g_objectCacheSize; // stable snapshot before mutations
        for(int i = 0; i < CACHE_HASH_BUCKETS && visited < snapshot; i++) {
            if(!g_objectCacheHash[i].occupied) continue;
            visited++;
            if(StringGetCharacter(g_objectCacheHash[i].name, 0) != prefixFirstChar) continue;
            if(StringLen(g_objectCacheHash[i].name) >= prefixLen &&
               StringSubstr(g_objectCacheHash[i].name, 0, prefixLen) == objectPrefix) {
                g_objectCacheHash[i].name = "";
                g_objectCacheHash[i].occupied = false;
                g_objectCacheHash[i].deleted = true;
                g_objectCacheHash[i].lastAccess = 0;
                g_objectCacheSize--;
                invalidated++;
            }
        }
    }

    InvalidateObjectCountCache();
}

//| Get adaptive level counts: the split leans toward the live price.     |
//+------------------------------------------------------------------+
void GetAdaptiveLevelCounts(int &maxAbove, int &maxBelow)
{
    LevelSplitCounts(inpMaxLevels, maxAbove, maxBelow);
}
//| Calculate common values used across all step modes              |
//| TH-based only (ATR basis removed, matching MT5)                |
//+------------------------------------------------------------------+
bool CalculateCommonStepData(const double dailyClosePrice, SCommonStepData &data)
{
    // P-UI-57: NaN/Inf are rejected, zero and negative keep their old meaning (some
    // modes derive their step from somewhere else, so "not positive" must not become
    // "refuse to draw"). `MathIsValidNumber` is the ONLY test that can see NaN —
    // every `<= 0` guard in this file is blind to it, which is how a poisoned base
    // price used to become a chart full of NaN levels.
    if(!MathIsValidNumber(dailyClosePrice)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[E][GEN] CalculateCommonStepData: Invalid (not a number) daily close price");
        #endif
        return false;
    }
    if(dailyClosePrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[E][GEN] CalculateCommonStepData: Invalid daily close price");
        #endif
        return false;
    }

    // OPTIMIZATION: Cache calculation results
    static SCommonStepData s_cachedData;
    static double s_lastDailyClose = 0;
    static string s_lastTF = "";
    static int s_lastStartPointType = -1;
    static double s_lastCustomPrice = 0;
    static int s_lastMaxAbove = 0;
    static int s_lastMaxBelow = 0;
    static double s_lastScalingFactor = 1.0;
    static double s_lastHighestHigh = EMPTY_VALUE;
    static double s_lastLowestLow = EMPTY_VALUE;

    string currentTF = GetFractalTimeframeForCurrent();
    double currentScalingFactor = GetCurrentScalingFactor();
    double volV = THVolNormDrawnV(inpTHVolNorm, THVolNormTFForFractalRung(FractalRungIndex(GetFractalTimeframeForCurrent())), GetTimeframeTH());   // P-TH-VOLNORM-TICK: block-adopted V, 1.0 when OFF

    // The split leans with live, so the cache keys on the computed split.
    int chkA = 0, chkB = 0; GetAdaptiveLevelCounts(chkA, chkB);
    if(dailyClosePrice == s_lastDailyClose &&
       currentTF == s_lastTF &&
       g_thStartPointType == s_lastStartPointType &&
       (g_thStartPointType != TH_START_POINT_CUSTOM_PRICE || g_customTHStartPrice == s_lastCustomPrice) &&
        chkA == s_lastMaxAbove &&
        chkB == s_lastMaxBelow &&
        MathAbs(currentScalingFactor - s_lastScalingFactor) < EPSILON_GENERAL && !THVolNormLevelChanged(volV) &&
        MathAbs(g_highestHigh - s_lastHighestHigh) < EPSILON_PRICE &&
       MathAbs(g_lowestLow - s_lastLowestLow) < EPSILON_PRICE &&
       s_lastDailyClose != 0) {
        data = s_cachedData;
        return true;
    }

    // OPTIMIZATION: Use global Digits instead of MarketInfo call
    int digits = Digits;

    // TH-based step calculations
    double timeframePercentage = GetTimeframeTH();
    data.thValue = CalculateTH(dailyClosePrice, digits, timeframePercentage);

    // Apply ATR Adaptive Scaling to TH value
    // This preserves the fractal 2x ratio since the same factor scales all levels uniformly
    data.thValue = GetAdaptedStepSize(data.thValue) * (volV == 1.0 ? 1.0 : volV);   // P-TH-VOLNORM-TICK: OFF = no-op

    CalculateFractalValues(data.thValue, data.structureValue, data.patternValue, data.triggerValue);

    // P-UI-57: the four step numbers are what every level price this frame derives
    // from, so they are validated ONCE here, at their owner, instead of at each
    // consumer (there are dozens and every one of them assumed a finite input).
    // Rejection is limited to what arithmetic cannot reason about — zero and
    // negative keep the behaviour they always had (some modes derive their step from
    // elsewhere, and Factor must not stop drawing because TH came out small).
    if(!MathIsValidNumber(data.thValue) || !MathIsValidNumber(data.structureValue) ||
       !MathIsValidNumber(data.patternValue) || !MathIsValidNumber(data.triggerValue)) {
        _LOG_GATE_W Print("[W][GEN] CalculateCommonStepData: non-finite step values rejected (th=",
                          DoubleToString(data.thValue, 8), " struct=", DoubleToString(data.structureValue, 8),
                          " pattern=", DoubleToString(data.patternValue, 8),
                          " trigger=", DoubleToString(data.triggerValue, 8), ")");
        return false;
    }

    #ifdef ENABLE_DEBUG_LOGS
    static datetime s_lastTHDebugLogTime = 0;
    datetime currentDebugTime = TimeCurrent();
    if(currentDebugTime - s_lastTHDebugLogTime > 300) {
        Print("[D][GEN] ========== MT4 TH_BASIS CALCULATION ==========");
        Print("[D][GEN] Calculation Basis: TH (Theoretical)");
        Print("[D][GEN] Base Price (dailyClosePrice): ", DoubleToString(dailyClosePrice, 10));
        Print("[D][GEN] Timeframe Percentage: ", DoubleToString(timeframePercentage, 10));
        Print("[D][GEN] TH Value (price units): ", DoubleToString(data.thValue, 10));
        Print("[D][GEN] Structure Value: ", DoubleToString(data.structureValue, 10));
        Print("[D][GEN] Pattern Value: ", DoubleToString(data.patternValue, 10));
        Print("[D][GEN] Trigger Value: ", DoubleToString(data.triggerValue, 10));
        Print("[D][GEN] SS (1.5 x Structure): ", DoubleToString(data.structureValue * 1.5, 10));
        Print("[D][GEN] LS (2.0 x Structure): ", DoubleToString(data.structureValue * 2.0, 10));
        Print("[D][GEN] ==============================================");
        s_lastTHDebugLogTime = currentDebugTime;
    }
    #endif

    // Calculate SS/LS values using simple multipliers (in PRICE units)
    data.shortStep = data.structureValue * 1.5;
    data.longStep = data.structureValue * 2.0;

    // NO point size conversion needed - values are already in price units
    data.pointSize = 1.0;  // Not used anymore

    // Get midpoint price using utility function
    data.midpointPrice = GetMidpointPrice(g_thStartPointType);

    // Validate midpoint price
    if(!MathIsValidNumber(data.midpointPrice) || data.midpointPrice <= 0 || data.midpointPrice == EMPTY_VALUE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[E][GEN] ERROR: Invalid midpoint price! g_highestHigh=", g_highestHigh, ", g_lowestLow=", g_lowestLow);
        #endif
        return false;
    }

    // Get adaptive level counts
    GetAdaptiveLevelCounts(data.maxLevelsAbove, data.maxLevelsBelow);

    // Update cache
    s_cachedData = data;
    s_lastDailyClose = dailyClosePrice;
    s_lastTF = currentTF;
    s_lastStartPointType = g_thStartPointType;
    s_lastCustomPrice = g_customTHStartPrice;
    s_lastMaxAbove = data.maxLevelsAbove;
    s_lastMaxBelow = data.maxLevelsBelow;
    s_lastScalingFactor = currentScalingFactor;
    s_lastHighestHigh = g_highestHigh;
    s_lastLowestLow = g_lowestLow;

    return true;
}

//+------------------------------------------------------------------+
//| Wrapper function to handle different step calculation modes     |
//| REFACTORED: Uses centralized ModeDefinitions factory             |
//+------------------------------------------------------------------+
void DrawLevelsBasedOnMode(const string objectPrefix, const double dailyClosePrice,
                           const double vpTop, const double vpBottom, const int buildStage)
{
    // Draw based on selected mode (respects keyboard override)
    ENUM_STEP_CALCULATION_MODE currentMode = GetCurrentStepMode();
    SCommonStepData data;
    if(!CalculateCommonStepData(dailyClosePrice, data)) return;

    // Use the modular Mode Factory
    SModeDefinition def = GetModeDefinition(currentMode, objectPrefix, data, dailyClosePrice);

    if(def.success) {
        // P-UI-98: THE CUSTOM-PRICE STEP OVERRIDE. The natural first step is
        // noted F-free straight off the factory's own sizes (the drag math's
        // denominator — no second copy of the per-mode first-step logic), then
        // ONE factor multiplies every step this mode carries: the SS/LS pair
        // keeps its 1.5:2.0 ratio, the Factor harmonic pair its ratio, and the
        // ladder on another timeframe is the same factor over THAT TF's natural
        // steps. F == 1.0 costs one compare.
        double s1Factor = StepOverrideFactor();
        int s1FirstIdx = (def.stepMode == LEVEL_STEP_CUMULATIVE &&
                          def.stepSizeCount > 1 && def.lsFirst) ? 1 : 0;
        NaturalFirstStepNote(def.stepSizes[s1FirstIdx]);
        if(s1Factor != 1.0) {
            for(int s1i = 0; s1i < def.stepSizeCount; s1i++)
                def.stepSizes[s1i] *= s1Factor;
        }
        // Convert static array to dynamic for ExecutePipeline compatibility
        double sizes[];
        ArrayResize(sizes, def.stepSizeCount);
        for(int i = 0; i < def.stepSizeCount; i++) {
            sizes[i] = def.stepSizes[i];
        }

        ExecutePipeline(def.config, data.midpointPrice, sizes, def.stepSizeCount,
                       def.stepMode, def.classifyMode, def.lsFirst,
                       data.maxLevelsAbove, data.maxLevelsBelow,
                       vpTop, vpBottom, buildStage);
        
        ArrayFree(sizes);
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[E][DRAW] DrawLevelsBasedOnMode: Failed to get mode definition for ", EnumToString(currentMode));
        #endif
    }
}

// DEPRECATED: Old helper functions removed
// Base price history is now managed by BasePriceManager.mqh
// Use PrintBasePriceHistory() from BasePriceManager instead

//==============================================================================
// P-PERF-29 — ONE OWNER FOR THE LINE-VISIBILITY SWITCH
//
// `g_linesVisible` was mutated in four places and only ONE of them wrote the
// object mask: the L hotkey called SetAllLineObjectsVisibility, and the two
// panel rows (Zones & Levels card row 1, LINES card row 1) plus the factory
// reset set the flag, the mirror and the persisted key and stopped there.
//
// That was invisible while every frame re-asserted the whole level family, but
// P-PERF-25 made the render's SKIP provable: it runs only when
// `frameCore == s_lastFrameCore && frameSig != s_lastFrameSig`, i.e. when the
// mask term is provably the only difference — and then it does not render,
// because the mask owner is supposed to have already written it. With the mask
// never written, nothing changed, and the lines stayed put until a timeframe
// switch deleted and rebuilt the whole chart. That is the reported symptom:
// "the levels only turn on/off if I change the timeframe".
//
// So the mask write lives with the state, in one function every entry point
// calls, instead of in one caller. SetAllLineObjectsVisibility is memoised, so
// the extra call from the sites that already wrote the mask is free.
void SetLinesVisible(const bool visible, const bool persist)
{
   g_linesVisible = visible;
   g_showLines    = visible;   // the Zones card mirror stays in sync
   UpdateLinesVisibleCache(visible);
   if(persist)
      GlobalVariableSet("Biotak_LinesVisible_" + GetCachedChartIdStr(), visible ? 1.0 : 0.0);
    SetAllLineObjectsVisibility(visible);
    // P-UI-98n: the three handset circles follow the key SYNCHRONOUSLY. They
    // are screen objects (OBJ_BITMAP_LABEL): a TIMEFRAMES mask does not hide
    // them, so the walk above moves no circle - and leaving them to the next
    // render/mousemove was the lag («دیر پنهان میشن»). The ride re-projects
    // from the stash with every term (armed, reveal latch, mode, hide-all and
    // this very switch), guarded: a keypress costs reads plus at most three
    // writes, never a rebuild. It syncs the green dot first, so this one call
    // is the whole marker half of the switch.
    HandsetMarkersRide();
}

//==============================================================================
// P-PERF-30 — A USER EDIT IS NOT VETOED BY THE GEOMETRY SIGNATURE
//
// frameSig answers "did anything I DERIVE geometry from change?" — that is the
// right question for skipping the re-derivation, and it is why a steady frame
// costs nothing. But it was also being used to veto the PAINT, and the paint
// reads live globals that frameSig does not enumerate (structure switches,
// line style/width/transparency, mid-zone border, trigger transparency, the
// midpoint line, custom-price look ...). Any one of them omitted from the
// signature became a control that does nothing until a timeframe switch —
// the same defect class as the line mask above, and the same user report.
//
// So the two questions are separated: applyRefreshFlags answers "the user asked
// for a repaint" and raises this flag; the signature keeps answering "is the
// geometry stale". A user edit therefore always paints. It still costs ONE
// re-assert per edit, never per frame, because the flag is cleared by the
// completed render it caused.
static bool g_renderAllNeeded = false;

//==============================================================================
// P-PERF-34 — the EVENT path SCHEDULES the frame, it never runs it. The whole
// frame body used to run inline in OnChartEvent (live log: `[PERF] click
// breakdown: button=0ms panel=0ms apply=531ms` — all 531 ms is the refresh), and a
// block that long inside the event handler IS the freeze the user feels. The
// raised flags stay raised, the heavy frame is marked OWED and the frame loop runs
// it (next tick, or the 250 ms timer). The LIVE DRAG is deliberately exempt:
// deferring it would trade a freeze for a lag.
// P-PERF-35 — co-operative multitasking is MQL4's only thread substitute (one OS
// thread, no `async`; a DLL or the MQL5-only OpenCL pool are the escapes), so
// several jobs advance under a millisecond budget and one that does not finish is
// simply still owed. Single-flight: an already-owed job is never owed twice.
//==============================================================================
#define COOP_WARN_MS        40   // a scheduled frame or coop job slower than this is logged
#define BUILD_STAGE_GATE_MS 60   // P-PERF-34b: spacing between staged rebuild frames

#define COOP_JOB_NONE         0
#define COOP_JOB_HEAVY_FRAME  1
#define COOP_JOB_OBJ_CLEANUP  2
#define COOP_JOB_LABEL_EXPIRY 3
#define COOP_JOB_STATUS_TEXT  4
#define COOP_JOB_COUNT        5

// Set by OnChartEvent (both entry points) for the duration of one event, so the
// frame body can tell "the user is waiting on this event" from "a frame is due".
bool g_inChartEvent = false;

static bool   g_heavyFramePending = false;
static uint   s_heavyFrameAskMs   = 0;
static string g_heavyFrameWhy     = "";
static bool   s_coopOwed[COOP_JOB_COUNT];
static uint   s_coopOwedMs[COOP_JOB_COUNT];
static uint   s_coopRuns = 0;
// P-PERF-45 evidence. `runs` counts frames that actually executed; `starved`
// counts the ticks on which the slice would have been spent on a sweep while
// the frame was still owed - i.e. exactly the ticks the frame used to lose.
// Reported in OnDeinit so the before/after is a number, not an impression.
static uint   s_coopFrameRuns    = 0;
static uint   s_coopFrameStarved = 0;

// Mark a heavy frame owed. Single-flight: the FIRST ask owns the clock, so the
// logged wait is the latency of the press that started it, not of the last one.
void ScheduleHeavyFrame(const string why)
{
   if(!g_heavyFramePending) s_heavyFrameAskMs = GetTickCount();
   g_heavyFramePending = true;
   g_heavyFrameWhy     = why;
   if(!s_coopOwed[COOP_JOB_HEAVY_FRAME]) s_coopOwedMs[COOP_JOB_HEAVY_FRAME] = GetTickCount();
   s_coopOwed[COOP_JOB_HEAVY_FRAME] = true;
}

string CoopJobName(const int job)
{
   switch(job)
   {
      case COOP_JOB_HEAVY_FRAME:  return "heavy-frame";
      case COOP_JOB_OBJ_CLEANUP:  return "obj-cleanup";
      case COOP_JOB_LABEL_EXPIRY: return "label-expiry";
      case COOP_JOB_STATUS_TEXT:  return "status-text";
   }
   return "?";
}

void CoopOwe(const int job)
{
   if(job <= COOP_JOB_NONE || job >= COOP_JOB_COUNT) return;
   if(!s_coopOwed[job]) s_coopOwedMs[job] = GetTickCount();
   s_coopOwed[job] = true;
}

bool CoopOwes(const int job)
{
   if(job <= COOP_JOB_NONE || job >= COOP_JOB_COUNT) return false;
   return s_coopOwed[job];
}

// P-PERF-45 evidence accessors (see the counters above and the pump below).
uint CoopFrameRuns()    { return s_coopFrameRuns; }
uint CoopFrameStarved() { return s_coopFrameStarved; }

void RedrawAllObjects(bool force_redraw=false)
{
    // P-PERF-02: "this frame painted nothing" is the default; every real draw
    // below sets it, and OnCalculateHandler only spends a chart repaint when it
    // is set (see g_lastRedrawDidWork).
    g_lastRedrawDidWork = false;
    // P-PERF-03: reset the phase ledger for this frame (see the CPU report at
    // the end of OnCalculateHandler).
    g_p3MsBase = 0; g_p3MsAtr = 0; g_p3MsHistory = 0; g_p3MsLevels = 0; g_p3MsLabels = 0; g_p3MsOverlay = 0;
    g_p3MsPre = 0; g_p3MsPost = 0;   // P-PERF-49b: the two spans outside RedrawAllObjects()
    g_p3MsLastTick = GetTickCount();
    // PERF: Soft millisecond guard for burst calls (independent from second-based gate)
    static uint s_lastRedrawAttemptMs = 0;
    static uint s_lastForcedRedrawMs = 0;
    uint nowMs = GetTickCount();

    // PERF: Coalesce event-burst forced redraws (very small window, keeps behavior intact)
    if(force_redraw) {
        if(s_lastForcedRedrawMs != 0 && nowMs - s_lastForcedRedrawMs < 20)
        {
            // P-KEY-01 (2026-09-30) — A DROPPED TOGGLE STILL OWES ITS PAINT, IN THIS EVENT.
            //
            // This guard exists to coalesce a BURST of forced calls (a slider drag, a
            // held key), and it is right about the WORK: the caller raised its flags
            // before calling, so nothing is lost. What was wrong is the LATENCY - the
            // return skipped the deferral below as well, so no frame was owed and the
            // picture waited for the next tick or the 250 ms timer. On a quiet chart
            // that is a press that appears to do nothing until something else moves:
            // «سطوح تریگر دیر خاموش و روشن میشه».
            //
            // The levels flag is the ONE that is both raised by every toggle that can
            // land here AND a term of `hasPendingWork` further down - so the pump at
            // the end of THIS event is guaranteed to find real work and run the same
            // frame body, on the same raised flags, that the timer would have run
            // later. Cost: one flag read, two GetTickCount reads, and (only when it
            // defers) one bool - no pixel changes, and the ledger names this path:
            // `owed frame (coalesced)`. A burst that carries no flag (a drag) keeps
            // the old behaviour exactly.
            if(g_redrawTHLevelsNeeded) ScheduleHeavyFrame("coalesced");
            return;
        }
        s_lastForcedRedrawMs = nowMs;
    }

    // P-PERF-34: A FORCED FRAME INSIDE A CHART EVENT IS DEFERRED, NOT RUN.
    //
    // One guard covers every event-path caller - the dispatcher AND the eleven
    // discrete one-shot sites (ESC, mode key, factor key, reset, TF lock, custom
    // price confirm, drag release/end) - including any added later, which is the
    // point: the defect was never one call site, it was the whole event path
    // being allowed to run a frame body. The callers have already raised the
    // flags (g_forceClearOnNextDraw / g_redrawTHLevelsNeeded / g_renderAllNeeded),
    // so returning here loses nothing: the owed frame picks the same flags up.
    //
    // The drag is exempt on purpose (see the P-PERF-34 note above): a drag needs
    // the levels to follow the line, and trading a freeze for a lag is not a fix.
    // P-UI-98e: BOTH hand-set gestures are exempt, for the one reason P-PERF-34
    // already names - a drag needs the levels to follow the line, and trading a
    // freeze for a lag is not a fix. The step-1 handle's own carry made it a
    // second drag: deferring its frames is what reads as "the other levels do
    // not move with my hand" («مثل خط کاستوم پرایس ... بقیه سطوح هم جابجا بشن در
    // لحظه»).
    if(force_redraw && g_inChartEvent && !g_customPriceLineDragging && !g_s1DragLive)
    {
        ScheduleHeavyFrame("chart-event");
        return;
    }

    // PERF: Refresh cached frame time once   eliminates ~2000+ TimeCurrent() syscalls in cache ops
    CacheRefreshFrameTime();
    // PERF: Cache visibility state once per frame   skips ~800 ObjectSetInteger calls when unchanged
    CacheRefreshVisibilityState();
    datetime currentTime = TimeGMT();

    // PERF: Idle fast-path   when no work is pending, skip expensive UpdateBasePrice/ATR path.
    bool customPriceLineExists = g_customPriceLineCreated;
    
    // SMART CACHING FOR HISTORICAL HIGH/LOW:
    // Only force a full historical refresh if we're not initialized.
    // Otherwise, we dynamically check if the current price has broken the cached high/low.
    bool priceBrokeHistoricalRange = false;
    if(g_initialized && g_highestHigh > 0 && g_lowestLow > 0) {
        if(g_currentPrice > g_highestHigh) {
            g_highestHigh = g_currentPrice;
            priceBrokeHistoricalRange = true;
        } else if(g_currentPrice < g_lowestLow) {
            g_lowestLow = g_currentPrice;
            priceBrokeHistoricalRange = true;
        }
    }
    
    bool historicalRefreshDue = (!g_initialized || priceBrokeHistoricalRange);
    
    // P-PERF-03: the 30-minute base-price boundary is an EDGE, not a whole
    // minute. "server minute == 0 or 30" was TRUE for 120 of every 1800
    // seconds, so for two minutes out of every half hour this function ran
    // its whole redraw pass at the 500 ms gate (2 Hz) — and the live MT4 log
    // shows exactly that: every CPU-warning burst sits on a :00/:30 minute
    // (62 ms per pass on this machine, ~15 s of CPU per boundary per chart).
    // Only the FIRST frame of a block can need the boundary work, so remember
    // which block we already handled and let the rest of the minute go idle.
    const long P_P3_BLOCK_SECONDS = 30 * 60;
    datetime boundaryTs = CacheGetFrameTime();
    static long s_lastBoundaryBlock = -1;
    long boundaryBlock = (long)boundaryTs / P_P3_BLOCK_SECONDS;
    int boundaryMinute = TimeMinute(boundaryTs);
    bool onBoundaryMinute = (boundaryMinute == 0 || boundaryMinute == 30);
    // CANDIDATE only: the block is marked handled further down, PAST every
    // gate. Consuming it here would let the millisecond gate swallow the one
    // frame that carries the block's base-price work.
    bool boundaryCandidate = (onBoundaryMinute && boundaryBlock != s_lastBoundaryBlock);
    bool basePriceBoundary = boundaryCandidate;
    // P-PERF-06: a staging frame is pending work by definition — the next
    // family must land even when no flag says so.
    bool hasPendingWork = (force_redraw || g_labelsRelayoutNeeded || g_redrawTHLevelsNeeded || historicalRefreshDue || basePriceBoundary || g_buildStage != 0 || g_heavyFramePending); g_p3ArmMask = (force_redraw?1:0)|(g_labelsRelayoutNeeded?2:0)|(g_redrawTHLevelsNeeded?4:0)|(historicalRefreshDue?8:0)|(basePriceBoundary?16:0)|(g_buildStage!=0?32:0)|(g_heavyFramePending?64:0)|(g_renderAllNeeded?128:0)|(g_forceClearOnNextDraw?256:0);   // P-PERF-53: the same flags as a mask, ON the line that already reads them
    
    // PERFORMANCE FIX: Hard millisecond gate for ALL redraws (except forced UI events)
    // This prevents price vibrations from hammering the CPU
    if(!force_redraw) {
        // P-PERF-34b: an OWED frame and a rebuild IN FLIGHT are not housekeeping.
        // The 200 ms "levels" gate and the 500 ms housekeeping gate exist so that
        // price vibration cannot re-derive an unchanged picture. Applying them to
        // work the user already asked for is what made one switch cost >= 800 ms
        // (four staged families spaced 200 ms apart) and made a scheduled frame
        // wait out a whole gate before it could even start.
        uint minWait = 500;                              // 2 FPS housekeeping
        if(g_heavyFramePending)      minWait = 0;        // the press is owed NOW
        else if(g_buildStage != 0)   minWait = BUILD_STAGE_GATE_MS;
        else if(g_redrawTHLevelsNeeded) minWait = 200;   // 5 FPS for levels
        if(nowMs - s_lastRedrawAttemptMs < minWait) return;
    }

    if(!hasPendingWork) {
        s_lastRedrawAttemptMs = nowMs;
        return;   // boundaryCandidate stays armed for the next frame
    }

    // Past every gate: this frame WILL do the block's work, so mark the block
    // handled — one pass per 30-minute block instead of ~240.
    if(boundaryCandidate) s_lastBoundaryBlock = boundaryBlock;

    int s_cachedDigits = GetCachedDigits();
    double s_cachedPoint = GetCachedPoint();
    // PERF: Cache Bid/Ask once per redraw frame instead of ~10 SymbolInfoDouble syscalls
    CacheTickPrices();
    g_currentPrice = GetCachedBid();
    if(g_currentPrice <= 0) return;

    // PERF: Controlled lazy base-price init (for deferred TF-switch startup path)
    if(!g_systemInitialized) {
        static uint s_lastBaseInitAttemptMs = 0;
        if(s_lastBaseInitAttemptMs == 0 || nowMs - s_lastBaseInitAttemptMs > 3000) {
            s_lastBaseInitAttemptMs = nowMs;
            InitializeBasePriceSystem();
        }
    }

    // PERF: Gate base-price updates to 30-min boundaries instead of checking every redraw.
    static datetime s_nextBasePriceCheckServer = 0;
    datetime nowServerTs = CacheGetFrameTime();
    bool shouldCheckBasePrice = (s_nextBasePriceCheckServer <= 0 || nowServerTs >= s_nextBasePriceCheckServer);
    g_p3MsLastTick = GetTickCount();
    if(shouldCheckBasePrice) {
        TH3_PROF_START(BasePrice);
        UpdateBasePrice();
        TH3_PROF_END(BasePrice);

        MqlDateTime nextCheckDt;
        TimeToStruct(nowServerTs, nextCheckDt);
        if(nextCheckDt.min < 30) {
            nextCheckDt.min = 30;
        } else {
            nextCheckDt.hour++;
            nextCheckDt.min = 0;
        }
        nextCheckDt.sec = 0;
        // +1 second prevents repeat runs at the exact boundary timestamp.
        s_nextBasePriceCheckServer = StructToTime(nextCheckDt) + 1;
    }

    double thBasePrice = GetBasePriceForTH();
    if(thBasePrice <= 0 || thBasePrice == EMPTY_VALUE) {
        thBasePrice = g_dailyClosePriceForTH;
    }
    
    // P-PERF-05: the base-price block and the ATR composite are different
    // beasts (a history/file write vs ~2000 series reads) and shared ONE ledger
    // slot, which is why a 2.3 s frame only ever said "base". Named separately.
    g_p3MsBase = GetTickCount() - g_p3MsLastTick;   // base-price gate only
    g_p3MsLastTick = GetTickCount();

    // Update ATR Adaptive Scaling factor (reacts to ATR changes every 5 seconds)
    if(UpdateATRScalingFactor(thBasePrice, s_cachedDigits)) {
        g_redrawTHLevelsNeeded = true;
    }
    g_p3MsAtr = GetTickCount() - g_p3MsLastTick;    // ATR composite + scaling
    g_p3MsLastTick = GetTickCount();
    
    static double s_lastDrawnBasePrice = 0.0;
    bool basePriceChanged = (MathAbs(thBasePrice - s_lastDrawnBasePrice) > s_cachedPoint);
    if(basePriceChanged) {
        s_lastDrawnBasePrice = thBasePrice;
        g_redrawTHLevelsNeeded = true;
    }
    // PERF: Use tracked bool instead of ObjectFind MT5 syscall (~0.5ms saved per frame)
    // P-PERF-06: staging frames never skip — each one owns a family.
    bool canSkipByState = (!force_redraw && !g_labelsRelayoutNeeded && !basePriceChanged && !g_redrawTHLevelsNeeded && g_initialized && g_buildStage == 0 && !g_heavyFramePending);
    if(canSkipByState) {
        // Existing second-level gate (may be zero by config)
        if(currentTime - g_lastCalculation < REDRAW_THROTTLE_SECONDS) return;
        // Additional soft guard for immediate burst calls when second-level throttle is disabled
        if(nowMs - s_lastRedrawAttemptMs < 35) return;
    }
    s_lastRedrawAttemptMs = nowMs;
    g_lastCalculation = currentTime;

    // P-PERF-38: the prefix is a CONSTANT now (one owner, timeframe-free), so the
    // whole cache-with-invalidate-on-timeframe-change machinery is gone with the
    // rename it existed to serve. The `s_lastPrefix != objectPrefix` branch that
    // used to wipe the old namespace is gone too, and that is not a lost guard:
    // `inpObjectPrefix` is an INPUT, so any change to it forces a reinit (MT4
    // re-creates the indicator), which means the prefix can never change inside a
    // running instance - the branch was unreachable, and it was the very wipe the
    // timeframe switch was paying for.
    string objectPrefix = GetLevelObjectPrefix();

    #ifdef ENABLE_DEBUG_LOGS
    static datetime s_lastDebugLog = 0;
    if(TimeGMT() - s_lastDebugLog > 60) {
        Print("[D][GEN] [MT4 DEBUG] RedrawAllObjects executing - Bid: ", DoubleToString(Bid, Digits));
        s_lastDebugLog = TimeGMT();
    }
    #endif

    g_dailyClosePriceForTH = thBasePrice;

    // PERFORMANCE: Use SMART CACHING for historical values
    // We only fetch the full history ONCE (when not initialized).
    // If the price breaks the range, we don't need a full array lookup again;
    // we already dynamically updated g_highestHigh and g_lowestLow above!
    if(!g_initialized)
    {
        if(!UpdateHistoricalValues()) {
            // FIX: If historical data is not ready, don't return early if we already have a base price
            // This allows drawing levels even if full history isn't loaded yet
            _LOG_GATE_W Print("[W][GEN] RedrawAllObjects: UpdateHistoricalValues failed, retrying later...");
            // Keep g_initialized = false to trigger retry next frame
            if(!g_initialized && thBasePrice > 0) {
                // We have a base price, so we can at least try to draw something
                g_highestHigh = thBasePrice * 1.01;
                g_lowestLow = thBasePrice * 0.99;
            } else {
                return; 
            }
        } else {
            g_initialized = true;
            g_calculatedOnce = false;
            g_redrawTHLevelsNeeded = true;
        }
    } else if (priceBrokeHistoricalRange) {
        // Just trigger a redraw, values are already updated!
        // P-PERF-54: NO label wipe for a range extension. g_calculatedOnce=false
        // forced needLabels, i.e. ClearAllLabels + a full label rebuild (countdown
        // included) on every tick that printed a new extreme — the per-tick label
        // flash on trending symbols. No label path reads g_highestHigh/Low, so the
        // wipe rebuilt identical pixels; the levels redraw above still runs.
        g_redrawTHLevelsNeeded = true;
    }
    g_p3MsHistory = GetTickCount() - g_p3MsLastTick;
    g_p3MsLastTick = GetTickCount();

    // Early exit when hidden - skip all drawing
    if(IsIndicatorHidden()) {
        bool wasApplied = HideAllTHObjects();
        g_lastRedrawDidWork = wasApplied;   // the hide transition DID touch the chart
        // P-PERF-34: the owed frame is SETTLED here too. Hiding IS the work the
        // press asked for, and a flag left armed on this path would keep
        // hasPendingWork true and minWait at 0 for every later frame - turning a
        // deferred edit into a permanent zero-gate. The debt is paid, so it is
        // cleared, and the pump stops owing it.
        g_heavyFramePending = false;
        g_heavyFrameWhy     = "";
        s_coopOwed[COOP_JOB_HEAVY_FRAME] = false;
        return;
    }

    // From here on this frame is doing real work (labels and/or levels).
    g_lastRedrawDidWork = true;

    DrawMainLevels(objectPrefix);
    // P-PERF-03: the pipeline render above is the frame's heaviest phase.
    g_p3MsLevels = GetTickCount() - g_p3MsLastTick;
    g_p3MsLastTick = GetTickCount();

    // P-PERF-06: the ATR/TH/trade labels are stage 4 (BUILD_STAGE_BLOCK) —
    // earlier staging frames defer them; the flag stays armed meanwhile.
    bool needLabels = ((!g_calculatedOnce) || g_labelsRelayoutNeeded) && (g_buildStage == 0 || g_buildStage == BUILD_STAGE_BLOCK);
    if(needLabels)
    {
        if (g_dailyClosePriceForTH == EMPTY_VALUE)
        {
            g_dailyClosePriceForTH = thBasePrice;
        }
        
        // CRITICAL: Reset stacking offsets and clear old labels for clean layout
        g_currentLabelYOffset = 0;  // Reset top label stacking offset
        g_currentLabelYOffsetBottom = 0;  // Reset bottom label stacking offset
        // ══════════════════════════════════════════════════════════════════
        // P-PERF-38e (2026-09-29) — THE LABEL FAMILY, MEASURED, AND WHY THE CLEAR
        // BELOW IS **KEPT** (this is the note that stops the next reader from
        // writing the one-line "optimisation" I wrote and reverted in this session).
        //
        // MEASURED on a real timeframe switch (H1 -> M15, 23:56:26.726 `uninit
        // reason 3` -> .742 `initialized`): the LEVEL family no longer blinks — the
        // census prints `lines=288 zones=289 ... absent=0` 17 ms later, with no
        // `P-LEVEL-FOREIGN` sweep and no force-clear, because the adoption stamp did
        // its job. The labels are the visible remainder, and their cost is priced in
        // the same log: `[W][PERF] labels relayout: clear=47ms atr=0ms th=0ms
        // trade=0ms tail=0ms` — 100% of the relayout is this one clear.
        //
        // So the tempting edit is `if(!g_adoptPreviousTopology) ClearAllLabels(...)`,
        // and it is WRONG, for one reason that has to be written down: this call is a
        // BULK DELETE OF THE WHOLE `LBL_` NAMESPACE, and that namespace is not only
        // the level family's pip labels. The TH columns and the ATR block are
        // PER-TIMEFRAME (their ladder is `GetTimeframeTH()`), so on a switch their
        // NEW name set is not a superset of the old one — a skipped clear leaves the
        // previous timeframe's rows on the chart as GHOSTS that no later frame
        // re-decides, which is strictly worse than a blink (Touch rule 4: degrade to
        // the previous look, never to a leftover).
        //
        // The fix is therefore a FEATURE, not a line, and it is the same shape the
        // ladder already has: ONE produced-list sweep for the label namespace — the
        // pass records every `LBL_` name it wrote, and the sweep deletes exactly the
        // names it did not (the ladder's `SweepForeignLadderObjects` treats
        // `<line>_Label` as produced - since P-LBL-12 retired the pip labels,
        // that sweep was their one-time net). Only then may the clear go, and
        // the ledger: `clear=` must fall to 0 ms on a switch while `atr`/`th`/`trade` stay put.
        ClearAllLabels(objectPrefix);

        TH3_PROF_START(Labels);
        if(g_atrLabelsVisible) DisplayATRLabels(objectPrefix);
        bool showFractal = (g_thLabelsMode == 1);
        bool showStandard = (g_thLabelsMode == 2);
        if(g_thLabelsMode != 0 && showFractal)  DisplayFractalTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
        if(g_thLabelsMode != 0 && showStandard) DisplayStandardTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
        // P-UI-84: UNGATED. The trade card owns its master switch and self-wipes
        // (DisplayATRTradeLabels), so the ATR overview gate above it never
        // governed it - guarding the call here is exactly what made an `ATR`
        // press remove the trade plan and leave the clear's empty corner behind.
        DisplayATRTradeLabels(objectPrefix);
        // Own layer: repaint AFTER the clear so switching the ATR labels off
        // never removes the countdown (2026-09-11).
        RefreshLiveCountdown();
        // P-PERF-38g: CLOSE THE PRODUCED-LIST WINDOW. Everything between the
        // ClearAllLabels above and this line is "this pass's output"; the sweep
        // deletes only what the previous pass produced and this one did not.
        LblSweepEnd(objectPrefix);
        TH3_PROF_END(Labels);

        if(!g_calculatedOnce && inpShowTHLevels) g_redrawTHLevelsNeeded = true;
        g_calculatedOnce = true;
        g_labelsRelayoutNeeded = false;
    }

    g_p3MsLabels = GetTickCount() - g_p3MsLastTick;
    g_p3MsLastTick = GetTickCount();

    // FIX: Snapshot final Y offset so mode/lock/factor labels always appear below all data labels
    // Move outside needLabels block to ensure overlay labels are always correctly positioned
    g_modeLabelYOffset = g_currentLabelYOffset;
    RepositionAllOverlayLabels();
    LabelPushBaseNoteSlotTop();   // BKCORNER-ON: the note's slot, after the mode rows' offset is known
    g_p3MsOverlay = GetTickCount() - g_p3MsLastTick;   // DrawMainLevels + overlay reposition

    g_dailyClosePriceForTH = thBasePrice;

    // P-UI-56: ONE resolver for the drawing price (this chart's placement → Input
    // seed → nothing), shared with OnInitHandler. The three-branch chain that used
    // to live here read the SYMBOL-scoped keys (two charts of one symbol shared one
    // price, so the ladder of the chart the user was NOT working on moved too) and
    // its Input branch wrote the price key - the value the user had dragged to was
    // replaced by the Input's own, which is the reported "each time it goes
    // somewhere else". The Input branch now only seeds THIS frame's price.
    bool lineExists = customPriceLineExists;

    if(!g_customPriceLineDragging) {
        double srcPrice = 0.0;
        bool   srcOverride = false;
        int    srcKind = CustomPriceResolveSource(srcPrice, srcOverride);
        if(srcKind == CPSRC_NONE) {
            g_thStartPointType = (g_startPointOverride >= 0 && g_startPointOverride <= 4) ? (ENUM_TH_START_POINT_TYPE)g_startPointOverride : inpTHStartPointType;   // panel START POINT wins; -1 = dialog seed
            g_customTHStartPrice = 0.0;
        } else {
            bool priceMoved = (MathAbs(g_customTHStartPrice - srcPrice) > s_cachedPoint * 0.1);
            if(priceMoved) {
                g_customTHStartPrice = srcPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
                g_redrawTHLevelsNeeded = true;
            }
            if(!lineExists) {
                // P-UI-45: a restored line is SETTLED (inert) - see CreateCustomPriceLine.
                CreateCustomPriceLine(g_customTHStartPrice, s_cachedDigits);
            } else if(priceMoved && srcKind == CPSRC_INPUT) {
                // Only the Input seed may push the existing line to its price; a
                // placement line is already where the user left it (and a guarded
                // write only on a real move keeps the steady frame at zero writes,
                // R-PERF).
                ObjectSetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, g_customTHStartPrice);
                ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP,
                                "[PIN] Custom Price: " + DoubleToString(g_customTHStartPrice, s_cachedDigits) + " | PIN button to move");
            }
        }
    }

    // P-UI-98p: NEVER-PAINTED, enforced every frame. The creator and the
    // transition both skip mid-gesture (P-BK-15) - and a gesture flag stuck
    // set (a release off-chart leaves NativeDrag armed) births the next line
    // with the terminal default, VISIBLE. Whatever the leak, one guarded read
    // per frame re-masks on drift; a steady frame costs nothing. No gesture
    // gate: a masked line is never MT4-dragged, so there is no native drag
    // to cancel - and the mask is the correct state mid-gesture too.
    if(lineExists &&
       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    
    // P-PERF-02: geometry signature of the last rendered level frame. It lives
    // at function scope because BOTH branches below can invalidate it.
    static string s_lastFrameSig = "";
    // P-PERF-25: the same signature WITHOUT the line-visibility mask. Storing
    // the core separately is what lets a pure visibility flip be recognised as
    // "nothing the renderer produces has changed" (see below) instead of being
    // guessed at.
    static string s_lastFrameCore = "";
    // P-PERF-06: the CURRENT frame's signature, hoisted so the BLOCK-stage
    // seal after the labels block can store exactly what this frame computed.
    string frameSig = "";
    string frameCore = "";

    // P-PERF-06: staging frames always enter — the stage flag (not just
    // g_redrawTHLevelsNeeded) carries liveness between family frames.
    if (inpShowTHLevels && (g_redrawTHLevelsNeeded || g_buildStage != 0))
    {
        #ifdef ENABLE_DEBUG_LOGS
        static datetime s_lastLevelRedrawLog = 0;
        if(TimeCurrent() - s_lastLevelRedrawLog > 5) {
            Print("[D][GEN] [MT4] [DRAW] REDRAWING LEVELS | Base Price: ", DoubleToString(g_dailyClosePriceForTH, Digits),
                  " | Mode: ", GetStepModeName(GetCurrentStepMode()));
            s_lastLevelRedrawLog = TimeCurrent();
        }
        #endif

        bool skipZones = g_customPriceLineDragging;
        TH3_PROF_START(Levels);

        // PERF: Topology signature guard - clear only when structure-defining inputs changed.
        static string s_lastLevelSig = "";
        ENUM_STEP_CALCULATION_MODE modeNow = GetCurrentStepMode();
        // P-PERF-23: TOPOLOGY ONLY — every term here changes WHICH levels
        // exist (or which mode computes them). Anything that only changes how
        // they are painted belongs in levelLookSig / frameSig.
        string levelSig = objectPrefix + "|" +
                          IntegerToString((int)modeNow) + "|" +
                          IntegerToString(inpMaxLevels) + "|" +
                          IntegerToString((int)g_thStartPointType) + "|" +
                          IntegerToString(inpLSFirst ? 1 : 0) + "|" +
                          // P-PERF-21: IsTriggerLevelsEnabled() used to sit HERE,
                          // in the TOPOLOGY signature - so a T press looked like a
                          // structure-defining edit and took shouldClearLevels,
                          // wiping every level, zone and label and restarting the
                          // four-frame staged rebuild. The trigger overlay changes
                          // no geometry (see PipelineGeometryKey); it changes the
                          // PICTURE, so it belongs in frameSig below, where a
                          // change costs one render and zero deletes.
#ifndef BUILD_LITE
                          IntegerToString(inpEnableHarmonicPattern ? 1 : 0) + "|" +
                          DoubleToString(inpHarmonicRatio, 3) + "|";
#else
                          "|";
#endif
        // P-PERF-23: APPEARANCE — same LEVEL SET, different PICTURE.
        //
        // The four terms below used to live in `levelSig`, i.e. in the TOPOLOGY
        // signature, and that is the whole of "toggling my levels deletes and
        // redraws everything": any change to them made levelTopologyChanged
        // true, which took shouldClearLevels, which ran ClearAllLevels over the
        // WHOLE chart (every line, zone and label deleted) and restarted the
        // four-frame staged rebuild - for a switch that only decides whether the
        // mid zones are PAINTED. Nothing about which levels exist changed.
        //
        // They are still inputs to the build (GetUnifiedZoneConfig feeds them to
        // SModeConfig, and PipelineGeometryKey names them), so the geometry is
        // recomputed when they change - correctly - but the render signature
        // below carries them now, so the cost is one render and zero deletes.
        string levelLookSig = IntegerToString(inpShowMidZones ? 1 : 0) + "," +
                              IntegerToString((int)inpMidZoneStyle) + "," +
                              IntegerToString(inpMidZoneTransparency) + "," +
                              DoubleToString(inpMidZoneHeightPercent, 3);
        // P-PERF-38d: on the very first pass of an instance that ADOPTED the
        // previous instance's topology, the stored signature is not "unknown" —
        // it is the one the chart was last drawn with (`levelSig` itself, since
        // the fingerprint just proved every name-deciding input is unchanged).
        // Without this the comparison below is trivially true (fresh instance,
        // empty static) and the family is wiped on every timeframe switch.
        if(s_lastLevelSig == "" && g_adoptPreviousTopology) s_lastLevelSig = levelSig;
        bool levelTopologyChanged = (levelSig != s_lastLevelSig);
        bool shouldClearLevels = g_forceClearOnNextDraw || levelTopologyChanged;

        if(shouldClearLevels) {
            TH3_PROF_START(LevelsClear);
            ClearAllLevels(objectPrefix, !skipZones);
            TH3_PROF_END(LevelsClear);
        }

        // P-PERF-06: ANY wipe rebuilds in stages (attach, TF switch, topology
        // toggle, custom-price re-anchor — all of them materialise ~900
        // objects). Unconditional restart: a toggle that wipes mid-staging
        // must rebuild from stage 1, or the wiped families never come back.
        if(shouldClearLevels) {
            g_buildStage = BUILD_STAGE_LINES;
        }

        // P-PERF-02 GEOMETRY SIGNATURE — the algorithmic half of the fix.
        // The render below is a pure function of the values in this signature.
        // Every heavy frame that arrives with the flag set but NO input moved
        // (the 5 s ATR tick, a label relayout, any event that raised the flag
        // defensively) used to re-derive and re-assert all ~300 levels: two
        // ObjectFind per line plus ~10 hash probes per line/label, and the
        // resulting pixels were identical. With the signature the work happens
        // only when the picture really changes; a steady frame is ~15 string
        // compares and zero syscalls.
        double vpTop = 0, vpBottom = 0;
        GetViewportBounds(vpTop, vpBottom);
        // P-PERF-06: freeze the cull window for the whole staging sequence —
        // stages 2-4 render against the stage-1 snapshot so a pan mid-staging
        // cannot split families across two viewports.
        if(g_buildStage == BUILD_STAGE_LINES) {
            g_stageVpTop = vpTop;
            g_stageVpBottom = vpBottom;
        } else if(g_buildStage > BUILD_STAGE_LINES) {
            vpTop = g_stageVpTop;
            vpBottom = g_stageVpBottom;
        }
        // P-PERF-25: the mask term is kept OUT of the core so a line-visibility
        // flip is provably a visibility-only change.
        // Split in frameCore (never levelSig: a drift must re-render, not wipe).
        int spA = 0, spB = 0; GetAdaptiveLevelCounts(spA, spB);
        frameCore = levelSig + levelLookSig + "|" + IntegerToString(spA) + "," + IntegerToString(spB) + "|" +
                          IntegerToString(g_drawGeneration) + "|" +
                          DoubleToString(g_dailyClosePriceForTH, s_cachedDigits) + "|" +
                          // P-UI-52: THE ACTIVE START POINT IS GEOMETRY, NOT JUST ITS TYPE.
                          //
                          // The start point entered this signature only through its TYPE
                          // (`levelSig`, above) and through `g_dailyClosePriceForTH`. But in
                          // custom-price mode the pipeline's CENTER PRICE is
                          // `g_customTHStartPrice` itself (`GetMidpointPrice` -> `data.midpointPrice`
                          // -> `ExecutePipeline` -> `PipelineGeometryKey`'s `centerPrice`), so a
                          // dragged line moved every level while this signature stayed EQUAL:
                          // `geometryChanged` was false, `DrawLevelsBasedOnMode` was never
                          // called, and the family only caught up when the DRAG FLAG flipped -
                          // once when the gesture started and once when it ended. That is the
                          // reported "the other levels do not follow the line while I drag it"
                          // (the movement itself is the terminal's).
                          //
                          // Added ONLY when it is the active start point, so every other mode
                          // pays one compare and folds in the constant it always did (0.0), and
                          // the value is quantised with the chart's own digits - a sub-point
                          // wobble cannot masquerade as a new picture. Cost: one DoubleToString
                          // on a key that already builds four, on frames that were going to be
                          // built anyway (the drag path is throttled to 50 ms on BOTH channels).
                          DoubleToString(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE
                                         ? g_customTHStartPrice : 0.0, s_cachedDigits) + "|" +
                          DoubleToString(g_highestHigh, s_cachedDigits) + "|" +
                          DoubleToString(g_lowestLow, s_cachedDigits) + "|" +
                          DoubleToString(GetCurrentScalingFactor(), 8) + "|" +
                          // P-UI-98: the step override is GEOMETRY — it moves every
                          // level. A drag that changed F must never read as the same
                          // picture (the P-UI-52 trap with a new seat).
                          DoubleToString(StepOverrideFactor(), 6) + "|" +
                          // P-VIEW-02 (2026-09-29) — THE WINDOW IS NOT GEOMETRY, SO A
                          // PAN IS NOT A REBUILD. `vpTop|vpBottom` stood here and they
                          // are the cull window, which re-derives whenever the chart's
                          // visible range moves by P_P4_VP_HYSTERESIS_PCT (ExtDraw_A
                          // 105-125) — i.e. on a plain scroll or a live scale drift, with
                          // NO level geometry changing. Measured: one such re-derivation
                          // is a full family rebuild — ~300 levels re-derived, every line
                          // and label mask re-asserted, and ClearAllLabels() deleting and
                          // re-creating EVERY label on the chart, the trade card and the
                          // countdown included. That is the reported «همه چیز فیلکر میزنه»:
                          // the levels, the countdown and the TRex card blink together,
                          // because one window term dragged the whole picture through a
                          // delete-and-recreate pass. The cull is now decided PER FRAME
                          // in the render (P-VIEW-01: RenderTriggerLines/RenderZones take
                          // the window and never let it write a mask), so the picture is a
                          // pure function of the level geometry again — which is what this
                          // signature was for. Cost of the fix: two DoubleToString calls
                          // and two compares gone; steady frames untouched.
                          IntegerToString(IsIndicatorHidden() ? 1 : 0) +
                          IntegerToString(IsTriggerLevelsEnabled() ? 1 : 0) +
                          IntegerToString(g_customPriceLineDragging ? 1 : 0);
                          // P-LBL-12 (2026-10-17): term left with its consumer, row off card.
        frameSig = frameCore + "|" + IntegerToString(g_linesVisible ? 1 : 0);
        bool geometryChanged = (frameSig != s_lastFrameSig);
        // P-PERF-06: staging frames always build — each one owns its family.
        if(g_buildStage != 0) geometryChanged = true;

        // P-PERF-25: A LINE-VISIBILITY-ONLY CHANGE NEEDS NO RENDER.
        //
        // The L key and the SHOW LINES row flip a MASK. The mask owner
        // (SetAllLineObjectsVisibility, P-PERF-22) has already written it for
        // every line the cache knows, and any line created later reads the live
        // switch at creation - so re-deriving and re-asserting the whole level
        // family (~900 objects, one ObjectFind probe each) to change a mask is
        // pure repeated computation: the same inputs, the same objects, the
        // same pixels except for the mask the walk just wrote.
        //
        // It is provable, not assumed: with the mask kept out of frameCore, the
        // ONLY way `frameCore == s_lastFrameCore && frameSig != s_lastFrameSig`
        // can hold is that the mask term is the single difference. A wipe, a
        // staging frame and every real edit (price, viewport, scaling, mode,
        // generation) change the core and take the normal render path.
        bool visOnly = (!shouldClearLevels && g_buildStage == 0 &&
                        s_lastFrameCore != "" && frameCore == s_lastFrameCore &&
                        frameSig != s_lastFrameSig);

        // P-PERF-06: the BLOCK stage draws nothing itself — the labels block
        // below is its family. (A wipe in a BLOCK frame already restarted the
        // stage to LINES above, so skipping here can never orphan a wipe.)
        // P-PERF-30: `geometryChanged` alone is not the whole question - it only
        // knows about the inputs frameSig enumerates, and the paint reads more
        // than that. A user edit (applyRefreshFlags) never rides on it.
        bool mustRender = (shouldClearLevels || geometryChanged ||
                           (g_renderAllNeeded && !visOnly));
        if(mustRender && g_buildStage != BUILD_STAGE_BLOCK && !visOnly)
        {
            TH3_PROF_START(LevelsDrawByMode);
            DrawLevelsBasedOnMode(objectPrefix, g_dailyClosePriceForTH, vpTop, vpBottom, g_buildStage);
            TH3_PROF_END(LevelsDrawByMode);
            // P-PERF-06: the signature seals ONLY a complete render. A staged
            // frame stores nothing; the BLOCK stage seals it after the labels.
            if(g_buildStage == 0) { s_lastFrameSig = frameSig; s_lastFrameCore = frameCore; g_renderAllNeeded = false; }
            // Advance the rebuild; P-LBL-12 retired the old stage 3 (pip labels),
            // so ZONES arms the labels block on its BLOCK hand-off (stage 4).
            if(g_buildStage == BUILD_STAGE_LINES)            g_buildStage = BUILD_STAGE_ZONES;
            else if(g_buildStage == BUILD_STAGE_ZONES) { g_buildStage = BUILD_STAGE_BLOCK; g_labelsRelayoutNeeded = true; }
        }
        else if(visOnly)
        {
            // P-PERF-25: the skip is a COMPLETED render of the same picture, so
            // it seals exactly like one - otherwise the next steady frame would
            // see a changed signature and render after all.
            s_lastFrameSig  = frameSig;
            s_lastFrameCore = frameCore;
            // P-PERF-30: the mask owner already painted the only difference, so
            // the user edit this frame carried IS applied - consume it.
            g_renderAllNeeded = false;
        }
        s_lastLevelSig = levelSig;
        TH3_PROF_END(Levels);
        // P-PERF-49b (2026-09-16): BILL THE FAMILY RENDER TO THE SLOT THAT NAMES IT.
        //
        // `g_p3MsLevels` was sampled immediately after DrawMainLevels() - the cheap
        // half - so the render BELOW it (DrawLevelsBasedOnMode, ~900 objects) was
        // billed to NOBODY. The `rest` field this ledger just gained proved it on
        // its first live frame:
        //   [CRIT] OnCalculate took 3563ms! [levels=31 labels=313 overlay=62 rest=3157]
        // 88% of a 3.5 s frame unowned, and the unowned part WAS the level render.
        //
        // g_p3MsLastTick was advanced by the overlay sample just before this block,
        // so this difference is exactly this block's own cost - nothing above is
        // counted twice, and the sum can still never exceed the frame.
        g_p3MsLevels += GetTickCount() - g_p3MsLastTick;
        g_p3MsLastTick = GetTickCount();
        g_forceClearOnNextDraw = false;
        g_redrawTHLevelsNeeded = false;
    }
    else if (!inpShowTHLevels && (g_redrawTHLevelsNeeded || g_buildStage != 0))
    {
        ClearAllLevels(objectPrefix);
        // P-PERF-38d: the family is gone, so the adoption stamp must go with it
        // — otherwise a later timeframe switch would adopt a chart that holds
        // nothing and skip the one wipe that is genuinely required.
        ClearTopologyAdoptionStamp();
        // The levels are GONE from the chart, so the stored signature no
        // longer describes it — re-enabling the switch must redraw them.
        s_lastFrameSig = "";
        s_lastFrameCore = "";   // P-PERF-25: both halves are stale together
        g_buildStage = 0;   // P-PERF-06: a rebuild in flight has nothing to build into
        g_forceClearOnNextDraw = false;
        g_redrawTHLevelsNeeded = false;
    }

    // P-PERF-06: the labels block above just ran as the last rebuild stage
    // (needLabels is forced at BLOCK) — seal the signature so steady frames
    // skip again. When needLabels was deferred, the stage stays armed.
    // NOTE: this sits AFTER the levels block because frameSig/s_lastFrameSig
    // live there (define-before-use) and the levels block runs after needLabels.
    if(g_buildStage == BUILD_STAGE_BLOCK && (needLabels)) {
        g_buildStage = 0;
        s_lastFrameSig = frameSig;
        s_lastFrameCore = frameCore;   // P-PERF-25: seal both halves together
        g_renderAllNeeded = false;     // P-PERF-30: consumed by this staged render
    }

    // P-PERF-34: this pass carried the owed frame, so the debt is settled here -
    // the only place that actually ran the body. The ledger reports BOTH numbers
    // because they are different problems: `waited` is the latency the press paid
    // (the scheduling), `body` is the frame cost itself (the rendering).
    if(g_heavyFramePending)
    {
        int deferMs = (int)(GetTickCount() - s_heavyFrameAskMs);
        int bodyMs  = (int)(GetTickCount() - nowMs);
        if(deferMs >= COOP_WARN_MS || bodyMs >= COOP_WARN_MS)
           _LOG_GATE_W Print("[W][PERF] owed frame (", g_heavyFrameWhy, ") waited=", deferMs,
                             "ms body=", bodyMs, "ms stage=", g_buildStage,
                             " clear=", (g_forceClearOnNextDraw ? 1 : 0));
        g_heavyFramePending = false;
        g_heavyFrameWhy     = "";
        s_coopRuns++;
    }

    // P-KEY-PROBE: THE T TOGGLE'S RECONCILIATION FRAME.
    //
    // P-PERF-32b moved the PIXELS to the press's own event (SetTriggerLevelsVisible
    // prints `[P-KEY] T applied … ms=` the moment the family's masks are written),
    // so this line reports the OTHER half: the frame that re-asserts the family
    // afterwards. It must read like a cheap, idempotent pass - `hidden=`/`reached=`
    // are guarded masks and the bands update in place - and if it does not, the
    // toggle is again paying a rebuild it does not need. It prints for EVERY
    // toggled press, not only a slow one: "it feels slow" is answerable against a
    // number, and a press that settled inside one tick must be able to say so.
    if(g_triggerPressMs != 0)
    {
        // `levels=` and `labels=` are this frame's OWN phase ledger (P-PERF-03),
        // printed here so the split is one line instead of a second experiment:
        // if the reconciliation is slow, either the level render owns it (levels=)
        // or the scheduling/labels do - and the fix is only allowed to target one.
        Print("[P-KEY] T settled on=", g_triggerPressOn,
              " ms=", (int)(GetTickCount() - g_triggerPressMs),
              " levels=", (int)g_p3MsLevels, " labels=", (int)g_p3MsLabels,
              " hidden=", g_triggerPressHidden, " reached=", g_triggerPressReached);
        g_triggerPressMs = 0;
    }
    CheckAlerts(objectPrefix, g_currentPrice);
    ThrottledChartRedraw();
}
#endif // EVENT_HANDLERS_CALC_MQH
