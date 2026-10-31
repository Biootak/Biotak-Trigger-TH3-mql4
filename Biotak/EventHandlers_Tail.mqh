// EventHandlers_Tail.mqh - EventHandlers split 2026-09-29: exact lines 5821-6294 of EventHandlers.mqh, byte-identical, zero renames.
#ifndef EVENT_HANDLERS_TAIL_MQH
#define EVENT_HANDLERS_TAIL_MQH


//+------------------------------------------------------------------+
//| Functions ported from MT5 EventHandlers                           |
//+------------------------------------------------------------------+

// Cache invalidation flags (from MT5)
enum ECacheInvalidationFlags {
    CACHE_INV_NONE = 0,
    CACHE_INV_TIMEFRAME = 1,
    CACHE_INV_NEW_BAR = 2,
    CACHE_INV_CUSTOM_PRICE = 4
};

// Robust hotkey matcher: compares both key code (lparam) and key text (sparam)
//--- P-UI-185 (2026-10-20): the hotkey is ONE key, and it is compared as ONE key.
//--- The matcher used the FIRST CHARACTER only, so a two-character hotkey
//--- ("Ctrl+T") answered as plain T - and the terminal's key stream carries ONE
//--- virtual key, so a modifier spelling can never be delivered. Two inputs
//--- sharing a key leave the second one dead (the branches are plain ifs: first
//--- match wins). The matcher now answers the WHOLE string, and the conflict is
//--- NAMED once at the attach (HotkeyAudit below).
bool IsHotkeyPressed(const long lparam, const string sparam, const string hotkey) {
    if(StringLen(hotkey) <= 0) return false;
    string k = hotkey;
    StringToUpper(k);
    if(StringLen(k) != 1) return false;   // not one key: the terminal cannot deliver it
    int code = (int)StringGetCharacter(k, 0);
    if((int)lparam == code) return true;
    if(StringLen(sparam) > 0) {
        string sp = sparam;
        StringToUpper(sp);
        if((int)StringGetCharacter(sp, 0) == code) return true;
    }
    return false;
}

//--- P-UI-185: the hotkeys are ONE key each, and a conflict is named. A hotkey
//--- longer than one character can never be delivered (the key stream carries ONE
//--- virtual key), and two inputs sharing a key leave the second one dead. The
//--- audit runs ONCE per attach and says which key is shared by what - so the
//--- user is not left with a key that does nothing.
#ifndef BUILD_LITE
void HotkeyWitness(const string line) { DrawStripDiagEmit("[keys] " + line); }
#else
void HotkeyWitness(const string line) { Print("[keys] " + line); }
#endif
void HotkeyAudit()
{
   string keys[16], names[16];
   int n = 0;
   keys[n] = inpHideKey;         names[n] = "Hide/Show all";   n++;
   keys[n] = inpLinesToggleKey;  names[n] = "Level lines";      n++;
   keys[n] = inpLockKey;         names[n] = "Timeframe lock";   n++;
   keys[n] = inpCustomPriceKey;  names[n] = "Custom price";     n++;
   keys[n] = inpTriggerLevelsKey;names[n] = "Trigger levels";   n++;
   keys[n] = inpStepModeKey;     names[n] = "Step mode";        n++;
#ifndef BUILD_LITE
   // TH3TOOL-OFF (2026-10-24): the V key no longer arms anything, so the conflict
   // table must not advertise it either — a registered-but-dead key is the same
   // lie as a ring button that draws nothing.
   //keys[n] = inpTH3ToolKey;      names[n] = "TH3 tool";         n++;
   keys[n] = inpHTFKey;          names[n] = "HTF candles";      n++;
#endif
   keys[n] = inpATRLabelsKey;    names[n] = "ATR labels";       n++;
   keys[n] = inpTHLabelsKey;     names[n] = "TH labels";        n++;
   keys[n] = inpShowStatusKey;   names[n] = "Show status";      n++;
   keys[n] = inpResetKey;        names[n] = "Reset overrides";  n++;
   keys[n] = inpLogDumpKey;      names[n] = "Log dump";         n++;
   keys[n] = inpCountdownKey;    names[n] = "Countdown tag";    n++;
   for(int i = 0; i < n; i++)
   {
      string k = keys[i];
      StringToUpper(k);
      if(StringLen(k) != 1)
      {
         HotkeyWitness(names[i] + " key=\"" + keys[i] + "\" is not ONE key - the terminal delivers one virtual key, so this shortcut never fires");
         continue;
      }
      for(int j = i + 1; j < n; j++)
      {
         string k2 = keys[j];
         StringToUpper(k2);
         if(k2 != k) continue;
         HotkeyWitness("hotkey \"" + k + "\" is bound twice: " + names[i] + " and " + names[j] +
                       " - the second one never answers");
      }
   }
}

//+------------------------------------------------------------------+
//| Delete all indicator objects (DRY helper for OnDeinit)           |
//+------------------------------------------------------------------+
void DeleteAllIndicatorObjects(bool deepCleanup = false) {
    if(StringLen(inpObjectPrefix) == 0) return;   // empty prefix matches everything

    // P-UI-21: ONE suppress window around every bulk below — an unsuppressed
    // delete fires CHARTEVENT_OBJECT_DELETE per object -> CacheRemoveObject +
    // a forced level redraw for each one (the old per-object loop paid that
    // MQL cost ~1000 times on a TF switch; a bulk call pays one bool check).
    g_suppressDeleteEvents = true;

    if(deepCleanup) {
        ObjectsDeleteAll(0, inpObjectPrefix);   // REASON_REMOVE: wipe everything incl. Base/Knot
    } else {
        // P-BK-01: TF-switch / parameter rebuilds must NOT wipe the user's
        // Base/Knot drawings — they are an independent layer that survives
        // (registry rebuilds from the box anchors via BaseKnotLazyInit).
        //
        // P-PERF-02: this used to be an MQL loop over EVERY chart object doing
        // ObjectName + StringSubstr + ObjectDelete per hit — ~1000 kernel
        // ObjectDelete calls plus 1000 object-list index rebuilds, i.e. the
        // timeframe-switch freeze. Every object this indicator owns carries the
        // chart-timeframe namespace `inpObjectPrefix + "_" + <TF> + "_"` (levels,
        // zones, labels, trade block, ATR/TH columns), and the Base/Knot layer
        // is named `inpObjectPrefix + "_BK_" + id` — so it can NEVER start with
        // a TF namespace. One native prefix call per namespace therefore
        // removes exactly the same set, in ~10 kernel calls instead of ~1000.
        // P-PERF-38: THE LEVEL FAMILY LIVES IN ONE TIMEFRAME-FREE NAMESPACE NOW,
        // so the whole family goes in ONE kernel call. This function is reached
        // ONLY from paths that really mean "throw the level family away"
        // (REASON_REMOVE, REASON_PARAMETERS, a lost/shared chart) - a
        // REASON_CHARTCHANGE timeout deliberately no longer calls it at all,
        // which is the whole point of P-PERF-38b: a switch changes the PRICES,
        // and prices are updated in place, not rebuilt.
        ObjectsDeleteAll(0, GetLevelObjectPrefix());
        // Legacy sweep, for a chart that has not yet run the one-time migration
        // (normally a no-op here, and never repeated once the stamp is set):
        // no old timeframe namespace may survive a parameter rebuild.
        static string s_tfNs[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN", "MN1", "UNKNOWN"};
        for(int n = 0; n < ArraySize(s_tfNs); n++)
            ObjectsDeleteAll(0, inpObjectPrefix + "_" + s_tfNs[n] + "_");
        // The ATR/TH label families also exist WITHOUT a TF namespace
        // (`inpObjectPrefix + "ATR_*" / "TH_*"`), and the legacy shared-pattern
        // ones carry `inpObjectPrefix + "SharedPattern_"`.
        ObjectsDeleteAll(0, inpObjectPrefix + "ATR_");
        ObjectsDeleteAll(0, inpObjectPrefix + "TH_");
        ObjectsDeleteAll(0, inpObjectPrefix + "SharedPattern_");
    }
    // Retired P-FREE witness pair (removed 2026-10-05): fixed names match no
    // namespace, so the wipe above never saw them — delete explicitly once, here,
    // so a remove-and-re-add deploy (the only deploy) leaves no orphan behind.
    ObjectDelete(0, "Biotak_FreeSym_Label");
    ObjectDelete(0, "Biotak_FreeMark_Label");

    g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
    g_suppressDeleteEvents = false;
    // Every cached entry now names a deleted object: drop them so the next
    // frame re-creates through ObjectCreate instead of set-ing into the void.
    CacheClear();
    InvalidateObjectCountCache();
    MarkDrawGeneration();   // P-PERF-02: the chart no longer holds this render
}

void EmergencyCleanupIndicatorObjects(const string indicatorPrefix)
{
    if(StringLen(indicatorPrefix) == 0) return;
    int total = ObjectsTotal(0, -1, -1);
    int prefixLen = StringLen(indicatorPrefix);
    int deleted = 0;
    for(int i = total - 1; i >= 0; i--) {
        string objName = ObjectName(0, i);
        if(objName == "") continue;
        if(StringLen(objName) < prefixLen) continue;
        if(StringSubstr(objName, 0, prefixLen) != indicatorPrefix) continue;
        if(StringFind(objName, "_BK_") >= 0) continue;   // P-BK-01: user drawings have no expiry
        CacheRemoveObject(objName);
        g_suppressDeleteEvents = true;
        g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
        if(ObjectDelete(0, objName)) deleted++;
        g_suppressDeleteEvents = false;
    }
    _LOG_GATE_I Print("[I][GEN] Emergency cleanup deleted=", deleted,
                      " | before=", total, " | after=", ObjectsTotal(0, -1, -1));
    InvalidateObjectCountCache();
    MarkDrawGeneration();   // P-PERF-02
}

void ApplyCacheInvalidation(const int invalidationFlags,
                            const int previousPeriod,
                            const int currentPeriod,
                            const double previousCustomPrice,
                            const double currentCustomPrice)
{
    if((invalidationFlags & CACHE_INV_TIMEFRAME) != 0) {
        UpdatePeriodCache();
        InvalidateTimeframeDependentCaches();
        // P-PERF-38d: a timeframe change on an instance that ADOPTED the family
        // does not need a wipe — the level set is the same family, only the
        // prices differ, and the render signature re-asserts those in place.
        // Everything else here still runs, so the geometry IS recomputed; what
        // is skipped is the delete-and-rebuild, which the user experiences as
        // "my levels were redrawn from scratch".
        if(!g_adoptPreviousTopology) g_forceClearOnNextDraw = true;
        g_redrawTHLevelsNeeded = true;
        g_calculatedOnce = false;
        g_labelsRelayoutNeeded = true;
        InvalidateATRCache();
        _LOG_GATE_I Print("[I][GEN] Timeframe changed: ", previousPeriod, " -> ", currentPeriod);
    }
    if((invalidationFlags & CACHE_INV_NEW_BAR) != 0) {
        InvalidateFactorCache();
    }
    if((invalidationFlags & CACHE_INV_CUSTOM_PRICE) != 0) {
        InvalidateTHCache();
        _LOG_GATE_I Print("[I][GEN] Custom price changed: ", DoubleToString(previousCustomPrice, Digits),
                          " -> ", DoubleToString(currentCustomPrice, Digits));
    }
}

void LogRedrawDecision(const bool isNewBar,
                       const bool timeframeChanged,
                       const bool customPriceChanged,
                       const bool gRedrawNeeded,
                       const bool forceClear,
                       const bool significantPriceChange,
                       const bool tickThrottled)
{
    #ifdef ENABLE_DEBUG_LOGS
    static datetime s_lastRedrawDecisionLog = 0;
    datetime now = TimeCurrent();
    if(now - s_lastRedrawDecisionLog < 5) return;
    if(isNewBar || timeframeChanged || customPriceChanged || gRedrawNeeded || forceClear || significantPriceChange) {
        Print("[D][GEN] Redraw decision | newBar=", isNewBar,
              " tfChanged=", timeframeChanged,
              " customChanged=", customPriceChanged,
              " redrawFlag=", gRedrawNeeded,
              " forceClear=", forceClear,
              " sigPrice=", significantPriceChange,
              " throttled=", tickThrottled);
        s_lastRedrawDecisionLog = now;
    }
    #endif
}

//+------------------------------------------------------------------+
//| Periodic cleanup outside redraw path (timer-driven)              |
//+------------------------------------------------------------------+
void RunIncrementalObjectCleanup()
{
    if(g_customPriceLineDragging) return;
    datetime currentTime = TimeGMT();
    if(currentTime - g_lastObjectCleanup <= CLEANUP_INTERVAL_SECONDS) return;

    TH3_PROF_START(ObjectCleanup);
    int currentObjectCount = ObjectsTotal(0, -1, -1);

    if(currentObjectCount > g_objectCountLast + OBJECT_COUNT_INCREASE_THRESHOLD) {
        datetime cutoffTime = currentTime - 3600;
        string objectPrefix = GetLevelObjectPrefix();
        int currentPrefixLen = StringLen(objectPrefix);
        string indicatorPrefix = inpObjectPrefix;
        int indicatorPrefixLen = StringLen(indicatorPrefix);

        static int s_cleanupCursor = -1;
        int maxCleanupItems = MathMin(currentObjectCount, 300);
        if(s_cleanupCursor < 0 || s_cleanupCursor >= currentObjectCount) {
            s_cleanupCursor = currentObjectCount - 1;
        }

        int processed = 0;
        int i = s_cleanupCursor;
        for(; i >= 0 && processed < maxCleanupItems; i--, processed++) {
            string objName = ObjectName(0, i);
            if(objName == "") continue;

            bool isOurs = false;
            if(StringLen(objName) >= indicatorPrefixLen && StringSubstr(objName, 0, indicatorPrefixLen) == indicatorPrefix) isOurs = true;
            if(!isOurs) continue;
            if(StringFind(objName, "_BK_") >= 0) continue;   // P-BK-01: never emergency-wipe user drawings
            if(StringFind(objName, "_HRAY_") >= 0) continue;   // P-HR-05: rays are their own layer, same law
            //--- P-SESS-43 (2026-10-31) — THE SESSION FAMILY IS SELF-OWNED, AND THIS PASS
            //--- WAS DELETING IT. The rule below is "everything under inpObjectPrefix that
            //--- is not the level family and is older than an hour is garbage" — and a
            //--- session box's own anchor IS its session start, so EVERY box older than
            //--- one hour (the live one included, once it has run an hour) was deleted on
            //--- the next timer pass and re-created by the next paint. MEASURED on the
            //--- live chart after a restart: `attach pre=100 … init menu n=100` and then
            //--- the first paint `preexist=0`, i.e. the family existed at the end of OnInit
            //--- and was gone before the first tick painted. That is the flicker and the
            //--- "حذف و رسم" report: two writers, one family. The family declares and
            //--- sweeps itself (P-SESS-37), so this pass has no opinion about it — the
            //--- same exemption `_BK_`, `_HRAY_` and `TH3_Structure_` already carry.
            if(StringFind(objName, indicatorPrefix + SESS_TAG) == 0) continue;   // P-SESS-43

            if(StringFind(objName, "TH3_Structure_") == 0) continue;
            if(StringLen(objName) >= currentPrefixLen && StringSubstr(objName, 0, currentPrefixLen) == objectPrefix) continue;

            datetime objTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME);
            if(objTime > 0 && objTime < cutoffTime) {
                CacheRemoveObject(objName);
                g_suppressDeleteEvents = true;
                g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
                ObjectDelete(0, objName);
                g_suppressDeleteEvents = false;
            }
        }

        if(i < 0) s_cleanupCursor = currentObjectCount - 1;
        else s_cleanupCursor = i;
    }

    g_objectCountLast = currentObjectCount;
    g_lastObjectCleanup = currentTime;
    TH3_PROF_END(ObjectCleanup);
}

// Lightweight label-only redraw (no level recalculation)
void RedrawLabelsOnly() {
    if(IsIndicatorHidden()) return;
    datetime currentTime = TimeGMT();
    string objectPrefix = GetLevelObjectPrefix();

    // P-PERF-49 (2026-09-16) - P-PERF-28b NAMED THIS FUNCTION'S PRICE AND NOTHING
    // INSIDE IT. The live MT5 log charged a chart resize 188/390/954 ms to
    // `labels=`, i.e. to this one call, which is seven steps: the clear, the ATR
    // overview, the TH block, the trade-plan block, the countdown, the overlay
    // reposition and the terminal repaint. `labels=954ms` therefore named a
    // FUNCTION where every other ledger here names a STEP, and the next action
    // could only be a guess between seven candidates.
    //
    // FIVE TIMERS, ONE PER CANDIDATE THAT CAN BE BIG, and the repaint folded into
    // the last one because it is the tail by construction. The getters run only on
    // this path (a relayout is a resize/stage event, never a tick), so the cost is
    // five GetTickCount() reads against a call that is already hundreds of ms.
    uint p49t = GetTickCount();
    uint p49clear = 0, p49atr = 0, p49th = 0, p49trade = 0;

    // CRITICAL: Reset stacking offsets and clear old labels
    g_currentLabelYOffset = 0;
    g_currentLabelYOffsetBottom = 0;
    ClearAllLabels(objectPrefix);
    p49clear = GetTickCount() - p49t; p49t = GetTickCount();

    if(g_atrLabelsVisible) {
        DisplayATRLabels(objectPrefix);
    }
    p49atr = GetTickCount() - p49t; p49t = GetTickCount();

    bool showFractal = (g_thLabelsMode == 1);
    bool showStandard = (g_thLabelsMode == 2);
    if(g_thLabelsMode != 0 && g_dailyClosePriceForTH != EMPTY_VALUE && g_dailyClosePriceForTH > 0.0) {
        if(showFractal)  DisplayFractalTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
        if(showStandard) DisplayStandardTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
    }
    p49th = GetTickCount() - p49t; p49t = GetTickCount();

    DisplayATRTradeLabels(objectPrefix);   // P-UI-84: own master, not the ATR overview
    p49trade = GetTickCount() - p49t; p49t = GetTickCount();

    RefreshLiveCountdown();   // own switch — survives the ATR labels being off
    // P-PERF-38g: same window, same closer as the tick path (EventHandlers_Calc):
    // a relayout re-asserts every label it still owns and deletes the rest —
    // never the whole namespace. The `clear=` in the ledger below now measures
    // the window opening, not a full-chart ObjectsDeleteAll walk.
    LblSweepEnd(objectPrefix);
    g_modeLabelYOffset = g_currentLabelYOffset;
    RepositionAllOverlayLabels();
    LabelPushBaseNoteSlotTop();   // BKCORNER-ON: the note's slot, after the mode rows' offset is known
    ThrottledChartRedraw();
    uint p49tail = GetTickCount() - p49t;

    // Same gate and the same shape as every other ledger here: nothing is printed
    // while the relayout is cheap. Read the ms as tick-quantized (n x 15.625); a
    // step listed as 0 ms spent under one tick, which is the answer that matters
    // when the total is hundreds.
    if(p49clear + p49atr + p49th + p49trade + p49tail >= COOP_WARN_MS)
        _LOG_GATE_W Print("[W][PERF] labels relayout: clear=", (int)p49clear, "ms atr=", (int)p49atr,
              "ms th=", (int)p49th, "ms trade=", (int)p49trade,
              "ms tail=", (int)p49tail, "ms (count+repo+paint)");
}

//+------------------------------------------------------------------+
//| HELPER: Adjust factor value by step (+1 = increase, -1 = decrease)|
//|                                                                  |
//| DIRECT MODE: g_factorValueOverride is a Step Size, adjust by pip|
//| CLASSIC MODE: g_factorValueOverride is a Factor number           |
//+------------------------------------------------------------------+
void AdjustFactorValue(int direction)
{
    bool useDirect = (inpFactorDisplayMode == FACTOR_DISPLAY_DIRECT);
    double currentVal = g_factorValueOverride;
    
    if(currentVal <= 0) {
        if(inpFactorMode == FACTOR_MODE_MANUAL && inpFactorValue > 0) {
            currentVal = inpFactorValue;
        } else if(useDirect) {
            // DIRECT MODE: default step from basis (single source, all 8 bases)
            double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
            currentVal = GetFactorModeAutoStepSize(basePrice, inpFactorAutoBasis);
            if(currentVal <= 0) currentVal = GetFactorModePrimaryStepPrice(basePrice); // Final fallback
        } else {
            // CLASSIC MODE: Get default Factor
            currentVal = GetDefaultFactorValue(g_dailyClosePriceForTH);
            if(currentVal <= 0 || currentVal > MAX_FACTOR_VALUE) {
                _LOG_GATE_E Print("[E][GEN] Factor adjust: Invalid factor, using ", DEFAULT_FACTOR_FALLBACK);
                currentVal = DEFAULT_FACTOR_FALLBACK;
            }
        }
    }
    
    double newVal;
    if(useDirect) {
        // DIRECT MODE: currentVal is Step Size in price units
        // Adjust by 10% of current value (or by 1 pip minimum)
        double pipSize = GetCachedPipSize();
        if(pipSize <= 0) pipSize = GetCachedPoint() * 10;
        double adjustBy = MathMax(currentVal * 0.1, pipSize);
        newVal = NormalizeDouble(currentVal + adjustBy * direction, GetCachedDigits());
        if(newVal < pipSize * 0.1) newVal = pipSize * 0.1;
        if(newVal > MAX_FACTOR_VALUE) newVal = MAX_FACTOR_VALUE;
    } else {
        // CLASSIC MODE: currentVal is Factor number
        double step = (inpFactorAdjustStep > 0) ? inpFactorAdjustStep : DEFAULT_FACTOR_ADJUST_STEP;
        newVal = NormalizeDouble(currentVal + step * direction, 2);
        if(newVal < MIN_FACTOR_VALUE) newVal = MIN_FACTOR_VALUE;
        if(newVal > MAX_FACTOR_VALUE) newVal = MAX_FACTOR_VALUE;
    }
    
    g_factorValueOverride = newVal;
    string factorGvarName = "Biotak_Factor_" + GetCachedChartIdStr();
    if(!GlobalVariableSet(factorGvarName, g_factorValueOverride)) {
        _LOG_GATE_E Print("[E][GEN] WARNING: Failed to persist Factor value to GlobalVariable");
    }
    g_forceClearOnNextDraw = true;
    g_redrawTHLevelsNeeded = true;
    RedrawAllObjects(true);
    // For DIRECT mode, derive the factor from the step (Step = Range / (Factor*2))
    // so the label shows a correct F value instead of 0.00.
    if(useDirect) {
        double factorForLabel = 0;
        if(g_highestHigh > 0 && g_lowestLow > 0 && g_highestHigh > g_lowestLow && newVal > 0) {
            factorForLabel = CalculateFactorFromStep(g_highestHigh - g_lowestLow, newVal);
        }
        UpdateFactorLabel(factorForLabel, newVal);
    } else {
        UpdateFactorLabel(newVal, 0);
    }
    ThrottledChartRedraw();
}

//==============================================================================
// P-PERF-35 - THE PUMP
//
// Cheap jobs first, the rebuild last. The sweep jobs cost a few milliseconds and
// must never be starved by a frame that ate the whole slice, while the rebuild
// only has to beat the next tick. The budget bounds how long ONE pump call may
// hold the terminal - and it is stated here plainly because the limit matters:
// this layer CANNOT split a single frame body. Splitting a rebuild is the staged
// pipeline's job (four families, four frames, BUILD_STAGE_GATE_MS apart). The
// budget orders and spaces work; it does not parallelise it, and nothing in MQL4
// can.
#define COOP_BUDGET_MS 12

// P-PERF-45e (2026-10-19): THE WAIT HALF IS THE TIMER'S OWN QUANTUM, NOT A STALL.
//
// MEASURED in two days of journal (20261018.log + 20261019.log): 325 coop lines,
// and 319 of them were ONE shape — `status-text` 200 and `label-expiry` 125, every
// one `waited=234..282ms ran=0ms stillOwed=0`. The other SIX were the real thing
// (`heavy-frame ran=125ms`). The timer is 250 ms (`EventSetMillisecondTimer(250)`,
// EventHandlers_Init.mqh:647) and the arms sit immediately before `CoopPump()` in
// the same tick (both entries, ~line 442), so the only way a job can wait a whole
// period is the slice check at this pump's foot breaking on the clock's own
// granule (`COOP_BUDGET_MS 12` against a ~15.6 ms GetTickCount step): ONE period
// is this pump's NORMAL deferral, so a 40 ms threshold warned on the design — 319
// lines that could not be told from a defect buried the six that were one. TWO
// periods = the job was skipped twice = the stall the line exists to name.
// `spent` keeps its 40 ms half: that half IS those six lines, untouched.
// The threshold is OWNED here, beside the slice it is read against, and the
// regression gate derives it against the timer's own period (P-PERF-45e).
#define COOP_WAIT_WARN_MS 500

void CoopPump()
{
   uint sliceStart = GetTickCount();
   // P-PERF-35b: THE ORDER IS CHEAP-FIRST, AND THE JOB IDS ARE NOT THE ORDER.
   //
   // HEAVY_FRAME is id 1, so iterating the ids ran the REBUILD first: it could
   // claim the whole slice and leave the sweep jobs owed into the next timer
   // tick. The live log named it precisely - "coop job=obj-cleanup waited=265ms
   // ran=0ms" - the sweeps starved while the frame's own line stayed silent,
   // because it stayed under the 40 ms warn threshold even while it had eaten the
   // 12 ms budget. Cheap jobs first means the frame gets the LEFTOVER, never the
   // other way round, so the priority is spelled out and no longer implied by an
   // enum value.
   int coopOrder[COOP_JOB_COUNT - 1] = { COOP_JOB_OBJ_CLEANUP, COOP_JOB_LABEL_EXPIRY,
                                         COOP_JOB_STATUS_TEXT,  COOP_JOB_HEAVY_FRAME };

   // P-PERF-45: THE FRAME OUTRANKS THE SWEEPS WHILE IT IS THE PROGRESS-MAKER.
   //
   // Cheap-first is correct when the frame is just another job. It is wrong while
   // a staged rebuild is in flight, and the reason is the cadence: OnTimer owes
   // the three sweeps on EVERY tick, so a slice spent on them starves the frame
   // on every tick, not once. The frame is the only advancer of g_buildStage, so
   // the rebuild never seals, labels never draw (they need stage 0 or BLOCK) and
   // the HTF bulk pass never runs (it returns while g_buildStage != 0). The
   // user-visible symptom was "change the timeframe again and the next label
   // appears".
   //
   // Note what the budget actually is: GetTickCount() steps in ~15.6 ms
   // increments, so `>= COOP_BUDGET_MS` with a value of 12 asks "was a tick
   // boundary crossed?", not "did 12 ms of work happen" - a two-millisecond
   // sweep can spend the slice by landing across a boundary. Ordering is the
   // honest fix here, because ordering cannot be mis-calibrated the way a
   // constant can.
   //
   // The sweeps are idempotent and are owed again next tick, so postponing one
   // costs a tick. Postponing the frame costs the whole rebuild.
   const bool frameIsProgressMaker = (g_heavyFramePending || !g_initialized || g_buildStage != 0);
   if(frameIsProgressMaker)
   {
      for(int mv = COOP_JOB_COUNT - 2; mv > 0; mv--) coopOrder[mv] = coopOrder[mv - 1];
      coopOrder[0] = COOP_JOB_HEAVY_FRAME;
   }

   for(int oi = 0; oi < COOP_JOB_COUNT - 1; oi++)
   {
      int job = coopOrder[oi];
      bool owed = s_coopOwed[job];
      // The rebuild is owed BY DEFINITION while it is in flight or while the
      // system has not initialised yet: that work already exists, it is not a new
      // ask. Deciding it here keeps the timer from carrying its own copy of the
      // same condition - which is exactly how "advance the staging" and "run the
      // owed frame" would drift apart.
      if(job == COOP_JOB_HEAVY_FRAME && !owed &&
         (g_heavyFramePending || !g_initialized || g_buildStage != 0))
      {
         owed = true;
         s_coopOwedMs[job] = GetTickCount();
         // P-PERF-45c (2026-10-13): THE FLAG IS SET TOO, NOT ONLY THE CLOCK.
         //
         // MEASURED defect this closes: the live journal carried
         //   [W][PERF] coop job=heavy-frame waited=-16ms ran=16ms stillOwed=0
         //   ... waited=-31ms ran=31ms  ·  waited=-32ms ran=47ms  ·  waited=-47ms ran=47ms
         // A NEGATIVE wait is impossible by construction (`waited = t0 - owedMs`
         // with `t0 >= owedMs`), so the number was not a latency - it was a lie,
         // and a diagnostic that lies reads as "no defect" (the loop's own law).
         //
         // The cause: this branch set the CLOCK but left `s_coopOwed[job]` FALSE.
         // The frame it then runs re-arms itself (RedrawAllObjects' own
         // `ScheduleHeavyFrame`, the coalesce and chart-event guards), and that
         // re-arm only takes the clock when the flag is FALSE - so it overwrote
         // `s_coopOwedMs[job]` with a tick LATER than this iteration's `t0`, and
         // `t0 - owedMs` wrapped. Setting the flag keeps the invariant
         // `owed == true => the clock belongs to the ask that started this run`,
         // so the re-arm is a no-op and `waited` is the honest latency again.
         //
         // It also fixes the state itself: with the flag false, a frame that
         // re-armed was indistinguishable from one that had not, and the
         // `s_coopFrameStarved` counter at the slice check below could not see
         // the progress-maker it was counting.
         s_coopOwed[job] = true;
      }
      if(!owed) continue;

      uint t0 = GetTickCount();
      switch(job)
      {
         case COOP_JOB_OBJ_CLEANUP:
            RunIncrementalObjectCleanup();
            s_coopOwed[job] = false;
            break;
         case COOP_JOB_LABEL_EXPIRY:
            CheckAndClearExpiredLabels();
            s_coopOwed[job] = false;
            break;
         case COOP_JOB_STATUS_TEXT:
            RefreshVisibleStatusLabels();
            RefreshComboLabelExtraInfo();
            // P-SESS: the sessions family's one tick (engine query + chart
            // objects only; no UI reads, so Lite runs it too). Idle ticks
            // compare a hash and one high/low per open session - no writes.
            SessionsTick();
            s_coopOwed[job] = false;
            break;
         case COOP_JOB_HEAVY_FRAME:
            // The frame clears the pending flag itself, but ONLY once it really
            // ran - so a gate that refuses the pass leaves the job owed instead
            // of silently dropping the user's edit.
            RedrawAllObjects(false);
            s_coopFrameRuns++;
            if(!g_heavyFramePending) s_coopOwed[job] = false;
            break;
      }

      uint spent  = GetTickCount() - t0;
      uint waited = t0 - s_coopOwedMs[job];
      if(waited >= COOP_WAIT_WARN_MS || spent >= COOP_WARN_MS)
         _LOG_GATE_W Print("[W][PERF] coop job=", CoopJobName(job), " waited=", (int)waited,
                           "ms ran=", (int)spent, "ms stillOwed=", (CoopOwes(job) ? 1 : 0));

      // P-PERF-45b: a tick that ends with the progress-maker still owed IS the
      // starvation event this patch removes. With the reorder above the frame has
      // already had its turn, so this counts only the legitimate case where the
      // frame's own gate refused the pass. The number that used to read "once per
      // tick" must now read ~0 - that is the evidence, not the claim.
      if(GetTickCount() - sliceStart >= COOP_BUDGET_MS)   // this pump's slice is spent
      {
         if(job != COOP_JOB_HEAVY_FRAME && s_coopOwed[COOP_JOB_HEAVY_FRAME] && frameIsProgressMaker)
            s_coopFrameStarved++;
         break;
      }
   }
}

#endif // EVENT_HANDLERS_TAIL_MQH
