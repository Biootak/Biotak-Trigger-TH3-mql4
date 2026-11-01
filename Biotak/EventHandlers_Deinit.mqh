// EventHandlers_Deinit.mqh - the TEARDOWN owner, split out of EventHandlers_Calc.mqh
// on 2026-10-31 (P-SIZE-1500: that file reached 1579 lines against a 1500 ceiling).
// Lines 1-384 of the old file, byte-identical, zero renames: the custom-price
// cleanup pair and OnDeinitHandler with its P-PERF-49 ledger.
#ifndef EVENT_HANDLERS_DEINIT_MQH
#define EVENT_HANDLERS_DEINIT_MQH


// Helper function to clean up custom price selection objects
void CleanupCustomPriceObjects(bool resetGlobalVars = false, bool forceDelete = false)
{
    // No need to delete vertical line as it's not created anymore
    
    // Only delete the horizontal line if we're in the initial selection mode or if forceDelete is true
    if (g_waitingForCustomPriceClick || forceDelete) {
        ObjectDelete(0, g_customPriceHorizontalLineName);
        g_customPriceLineCreated = false;
    }
    
    g_waitingForCustomPriceClick = false;
    
    // If resetGlobalVars is true, also delete the global variable and reset keyboard override
    if (resetGlobalVars) {
        // P-UI-56: each key has ONE owner now - the chart-scoped pair through
        // `CustomPriceForgetPlacement` - and the older SYMBOL-scoped pair is purged
        // here too, which is now the only place left in the repo that names it.
        CustomPriceForgetPlacement();
        GlobalVariableDel(CustomPriceLegacyGVName());
        GlobalVariableDel(CustomPriceLegacyOverrideGVName());
        // P-UI-98: the step override is the placement's property — the ladder it
        // re-scaled was anchored on that placement, so both leave together.
        StepOverrideFactorReset();
        // P-UI-98d: the markers and the armed/set state are the placement's too.
        ObjectDelete(0, g_cpMarkerName);
        CacheRemoveObject(g_cpMarkerName);
        ObjectDelete(0, S1MarkName(1));
        CacheRemoveObject(S1MarkName(1));
        ObjectDelete(0, S1MarkName(-1));
        CacheRemoveObject(S1MarkName(-1));
        // P-UI-98d v2: the ride channel re-projects from these stashes — a stale
        // price would resurrect a red handle over a mode that owns no ladder.
        g_s1MarkAbovePrice = 0.0;
        g_s1MarkBelowPrice = 0.0;
        g_cpLineArmed = true;
        g_s1LinesArmed = true;
        // P-UI-98g: the reveal latch is the placement's too — the next placement
        // is born armed-but-hidden, and nothing of this one may leak into it.
        g_cpHandleShown = false;
        g_s1HandleShown = false;
        g_cpSetPending = "";  g_cpSetPendingMs = 0;
        g_s1SetPending = "";  g_s1SetPendingMs = 0;
        // P-UI-98m: no re-arm candidate survives a teardown either.
        g_cpClickArmed = false;  g_cpClickY = 0;
        g_customTHStartPrice = 0.0;
        g_thStartPointType = inpTHStartPointType;
        g_customPriceKeyboardOverride = false; // Reset keyboard override flag
    }
}

//+------------------------------------------------------------------+
//| P-UI-45 - ONE OWNER for "leave custom-price mode".               |
//|                                                                  |
//| The ESC key carried this sequence inline, and the ring's PIN item had NO way |
//| to reach it at all: its press only ever RE-ARMED (the line was deleted and   |
//| re-created at the market price), so the pin could be switched ON and never   |
//| OFF and the only exit was the keyboard. Two surfaces asking the same question |
//| get one answer: the line goes, the override GVar is dropped, and the TH start |
//| point returns to the Input default.                                          |
//+------------------------------------------------------------------+
void DeactivateCustomPriceMode(const string src)
{
    // P-UI-56: the keys all belong to the owners above - `CleanupCustomPriceObjects`
    // forgets this chart's placement (price + flag) and purges the legacy pair; the
    // redundant flag write that used to sit here named the symbol-scoped key.
    CleanupCustomPriceObjects(true, true);   // line + placement keys + start point + flag
    g_thStartPointType = inpTHStartPointType;
    g_customPriceKeyboardOverride = false;
    g_forceClearOnNextDraw = true;
    g_redrawTHLevelsNeeded = true;
    RedrawAllObjects(true);   // P-PERF-34: in a chart event this is owed to a frame
    _LOG_GATE_D Print("[D][GEN] Custom price mode OFF (", src,
                      ") - TH start point returned to the Input default");
}

//+------------------------------------------------------------------+
//| OnDeinit Handler - cleanup and state persistence (matching MT5)  |
//+------------------------------------------------------------------+
// P-PERF-49: the gate of the teardown-handler ledger below. It carries the same
// 40 ms the coop ledger calls COOP_WARN_MS, and it is spelled again here for the
// one reason this project keeps re-learning (P-PERF-14, twice): MQL4 has no
// forward declaration for a macro, and COOP_WARN_MS is #defined ~650 lines BELOW
// OnDeinitHandler - a use above its own #define is `error 256: undeclared
// identifier`, measured, not guessed. When the ledger constants are collected
// into one early block this name folds back into COOP_WARN_MS; until then the
// value is the same number with the meaning written next to it.
#define P49_DEINIT_WARN_MS 40

void OnDeinitHandler(const int reason) {
    // P-ARCH-03b (2026-10-31) — THIS FUNCTION IS THE ONE THAT DELETES, AND A UNIT THAT
    // WAS REFUSED AT INIT DELETES NOTHING.
    //
    // The refusal above (P-ARCH-03) lands before the first piece of chart work and
    // says exactly why: "a unit that will not load must not delete a live unit's
    // objects". MT4 then calls OnDeinit(REASON_INITFAILED) on that same refused unit,
    // and this function used to fall through to its generic `else` branch — which
    // deletes `inpObjectPrefix + "_"`, the whole level family of the LIVE unit. The
    // objects were not this instance's to delete: it had created none.
    //
    // Everything else below is the same story: `ObjectsDeleteAll(0, "LM_prev_")` is a
    // FIXED name, TH3PivotMarkersClear sweeps a chart-wide prefix, and
    // CleanupCustomPriceObjects deletes the hand-set line — all of them belong to
    // whoever IS attached. A refused unit owns no timer, no ATR handle, no scroll
    // lock, no objects, so there is nothing here it must do. Return before any of it.
    if(reason == REASON_INITFAILED) return;
    DEBUG_PRINT("Starting cleanup");
    // P-PERF-49 (2026-09-16) - THE TEARDOWN'S SECOND-LARGEST ITEM HAD NO OWNER.
    //
    // The live MT5 ledger (151 teardowns in one day, against ZERO budget
    // violations on MT4) charges `handler=` a median of 78 ms and a p90 of 313 ms,
    // and the field named a FUNCTION where every other field in that line names a
    // STEP. This function is seven independent promises - release the scroll/view
    // locks, stamp the switch, release the ATR handle, kill the timer, delete the
    // named singletons, run the reason branch, tear the managers down - and each
    // one is a different suspect (a handle release and a prefix sweep are not the
    // same animal on MT5).
    //
    // Five fields, cut where the ownership actually changes, so the next report
    // is "atr=78" instead of "handler=78, somewhere in here". `stamp=` is the
    // GlobalVariableSet behind the TF-switch debounce: it is a TERMINAL write
    // (0.128 us) and would be invisible, but it is a WRITE, and every other write
    // in this project has a field.
    //
    // Read the ms as tick-quantized (GetTickCount steps in ~15.6 ms, so every
    // number is n x 15.625): the split's job is to pick the OWNER, and an owner
    // above one tick is exactly the size class this ledger exists for.
    uint p49t = GetTickCount();
    uint p49knot = 0, p49locks = 0, p49stamp = 0, p49atr = 0, p49names = 0, p49branch = 0;
    // P-PERF-02: after this teardown the chart holds none of our masks, so the
    // next instance must re-assert every one of them, and the once-per-
    // transition hide pass is re-armed.
    ResetHideAllState();
    BumpTfEpoch();
#ifndef BUILD_LITE
    TH3PivotMarkersClear();     // P-TH3-P6: our chart namespace leaves with us (UI half - P-BUILD-01)
    ObjectsDeleteAll(0, "LM_prev_");   // P-MT4-LEGPREVIEW: a FIXED name, outside inpObjectPrefix AND TH3_LEG_PREFIX (the sweep below) — a cancelled draw (TF switch / params / chart close) left the dashed line for good; MT5 twin = P-MT5-LEGPREVIEW
#endif
    BaseKnotOnDeinit(reason);   // P-BK-02: never leave scroll locked / ghost preview behind
    HRayOnDeinit(reason); PathOnDeinit(reason);   // P-HR-01 / P-UI-136: never leave a stuck arm behind
    p49knot = GetTickCount() - p49t; p49t = GetTickCount();
    CustomPriceDragLockOff();   // P-UI-53: same rule for the custom-price drag lock
    // P-UI-90: THE NET, for EVERY deinit reason. Whatever the counters of the
    // owners above believe (a release that never arrived, a panel unlock that
    // was clamped away, a leaked orb claim), the chart gets the USER's captured
    // view pair back - which is why removing the indicator can no longer leave a
    // scroll-locked chart behind. A no-op costs two reads.
    ChartViewLockForceRelease();
    p49locks = GetTickCount() - p49t; p49t = GetTickCount();
    // Save TF-switch timestamp for deferred init debounce
    if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS) {
        string tfSwitchStampGvar = "Biotak_LastTFSwitch_" + GetCachedChartIdStr();
        datetime nowSwitch = TimeCurrent();
        if(nowSwitch > 0) GlobalVariableSet(tfSwitchStampGvar, (double)nowSwitch);
    }
    // VIEWLOCK-OFF:
    //if(reason == REASON_CHARTCHANGE && g_viewLockEnabled) {
    //    ViewLockCapture();
    //}

    p49stamp = GetTickCount() - p49t; p49t = GetTickCount();
    ReleaseATRHandle();
    EventKillTimer();
    p49atr = GetTickCount() - p49t; p49t = GetTickCount();

    // PERF: ObjectDelete is safe to call on non-existent objects (returns false, no error)
    // Eliminates ObjectFind syscalls
    ObjectDelete(0, g_stepModeLabelName);
    ObjectDelete(0, g_factorLabelName);
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    ObjectDelete(0, g_th3FreqLabelName);
#endif
    ObjectDelete(0, g_lockStatusLabelName);
    ObjectDelete(0, g_customPriceHorizontalLineName);
    // P-UI-98d: the handset markers leave with their lines
    ObjectDelete(0, g_cpMarkerName);
    ObjectDelete(0, S1MarkName(1));
    ObjectDelete(0, S1MarkName(-1));
    ObjectDelete(0, g_viewAnchorLineName);   // VIEWLOCK-OFF: purge only — the lock itself is retired
    p49names = GetTickCount() - p49t; p49t = GetTickCount();

    if(reason == REASON_REMOVE)
    {
        DEBUG_PRINT("Indicator removed - cleaning all GlobalVariables");
        // P-PERF-38d: the objects go with the removal, so the next attach must
        // NOT adopt a chart this instance emptied.
        ClearTopologyAdoptionStamp();
        // P-UI-60: the naming-migration stamp answers "does THIS chart still carry
        // objects named by the retired timeframe-in-the-name scheme?". The removal
        // deletes every object of that family, so the answer must be forgotten with
        // them - exactly the rule the adoption stamp above already follows (the
        // `topology-adoption` gate enforces it for that one). Left behind, it was a
        // `Biotak_NameScheme_<chartId>` global variable held for the LIFETIME OF THE
        // TERMINAL for every chart id the terminal had ever shown, and nothing ever
        // removed those (the chart id of a closed chart never returns). The price is
        // the one-time 11-prefix sweep running again on a RE-ATTACH of the same
        // chart - once per attach, never on a timeframe switch (a switch is
        // REASON_CHARTCHANGE and keeps the stamp).
        GlobalVariableDel(NameSchemeStampName());
        CleanupAllGlobalVariables();
        DeleteAllIndicatorObjects(true);
        ObjectsDeleteAll(0, "TH3_Structure_");
#ifndef BUILD_LITE
        ObjectsDeleteAll(0, TH3_PATTERN_PREFIX);  // Clean up AB=CD pattern objects
        ObjectsDeleteAll(0, "TH3_BASE_");          // P-TH3-BASE-01: the nested-base overlay (own prefix)
        ObjectsDeleteAll(0, "TH3_MP_");            // P-TH3-BASE-01: the same overlay under its OLD prefix — a chart drawn by a previous build must not keep a second zone
        ObjectsDeleteAll(0, TH3_TEMP_PREFIX);     // Clean up any temp drawing objects
        // P-LM-01c: the leg-measure family (line + arrow + plate + its 3 lines)
        // rides its own namespace, so removing the indicator removes all six
        // objects of every measurement instead of leaving the boxes behind.
        ObjectsDeleteAll(0, TH3_LEG_PREFIX);
#endif
    }
    else if(reason == REASON_PARAMETERS)
    {
        // Clear all ATR and TH labels to apply new settings
        string uniquePrefix = GetLevelObjectPrefix();
        // No M30 here: the M30 ATR column is retired (2026-09-11) and every
        // object this loop targets carries inpObjectPrefix, so the
        // DeleteAllIndicatorObjects(false) at the end of this branch sweeps any
        // M30 leftovers from old charts anyway.
        string tfLabels[] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1", "MN1"};

        // Delete ATR labels (P-UI-21: suppress window — every delete below
        // touches inpObjectPrefix* names; unsuppressed each fires
        // CHARTEVENT_OBJECT_DELETE -> CacheRemoveObject + a forced redraw
        // flag. DeleteAllIndicatorObjects(false) at the end of this branch
        // closes the window with UntilMs+false.)
        g_suppressDeleteEvents = true;
        ObjectDelete(0, uniquePrefix + "ATR_Title");
        for(int i = 0; i < ArraySize(tfLabels); i++) {
            ObjectDelete(0, uniquePrefix + "ATR_" + tfLabels[i]);
            ObjectDelete(0, uniquePrefix + "ATR_Steps_" + tfLabels[i]);
            ObjectDelete(0, uniquePrefix + "ATR_Targets_" + tfLabels[i]);
        }
        // P-UI-21: these carry no TF suffix — inside the loop above the same
        // objects were deleted 8x. Hoisted: delete once.
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_Targets");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_SL");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_HuntSL");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_EngSL");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP1");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP2");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP3");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_SL_Text");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_SL_Value");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_HuntSL_Text");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_HuntSL_Value");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_EngSL_Text");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_EngSL_Value");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP1_Text");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP1_Value");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP2_Text");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP2_Value");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP3_Text");
        ObjectDelete(0, uniquePrefix + "ATR_Trade_Current_TP3_Value");
        // Screenshot 3-row block + top-center TRex stamp (LBL_-prefixed names).
        string lblPfx = uniquePrefix + "LBL_";
        ObjectDelete(0, lblPfx + "ATR_Trade_Current_ATR");
        ObjectDelete(0, lblPfx + "ATR_Trade_Current_SLRow");
        ObjectDelete(0, lblPfx + "ATR_Trade_Current_TPRow");
        ObjectDelete(0, lblPfx + "TREX_Spread");
        ObjectDelete(0, lblPfx + "TREX_Caption");
        ObjectDelete(0, lblPfx + "TREX_TR");
        ObjectDelete(0, lblPfx + "TREX_EX");
        ObjectDelete(0, lblPfx + "TREX_ATR");

        // Delete TH labels
        ObjectDelete(0, inpObjectPrefix + "TH_Title");
        for(int i = 0; i < ArraySize(tfLabels); i++) {
            ObjectDelete(0, inpObjectPrefix + "TH_" + tfLabels[i]);
            ObjectDelete(0, inpObjectPrefix + "TH_Steps_" + tfLabels[i]);
            ObjectDelete(0, inpObjectPrefix + "TH_Targets_" + tfLabels[i]);
        }

        string chartIdStrLocal = GetCachedChartIdStr();
        // P-UI-56: a parameter change returns the start point to the Input default by
        // clearing the FLAG (the resolver then prefers the Input seed). The PRICE key
        // is deliberately kept, exactly as before - this path never deleted it, and
        // with no Input seed the resolver still honours it.
        GlobalVariableSet(CustomPriceOverrideGVName(), 0.0);
        string factorGvarName = "Biotak_Factor_" + chartIdStrLocal;
        GlobalVariableDel(factorGvarName);
        g_factorValueOverride = 0.0;
        // FIX: Keep hotkey toggle state across parameter changes so a settings
        // update does not undo the user's toggles (L=lines, A=ATR labels, S=TH
        // labels). The gvars are restored in OnInit; use the R key to reset all
        // overrides back to the input defaults.
#ifndef BUILD_LITE
        string th3UpdateFlag = "Biotak_TH3_NeedsUpdate_" + chartIdStrLocal;
        GlobalVariableSet(th3UpdateFlag, 1.0);
#endif
        DEBUG_PRINT("OnDeinit (REASON_PARAMETERS) - applying settings (hotkey toggles preserved)");
        DeleteAllIndicatorObjects(false);
        // P-PERF-38d: same reason as REASON_REMOVE — this branch deletes the
        // whole family, so adoption would be a lie.
        ClearTopologyAdoptionStamp();
    }
    else if(reason == REASON_CHARTCHANGE)
    {
        // P-PERF-38b - A TIMEFRAME SWITCH MUST NOT THROW THE LEVEL FAMILY AWAY.
        //
        // MT4 forces a deinit+init on a chart period change (the live log shows
        // `uninit reason 3` = REASON_CHARTCHANGE dozens of times), so this branch
        // ran on EVERY switch and deleted the whole family - ~900 objects - which
        // the new instance then had to CREATE again from scratch, recomputing the
        // geometry on the way. That delete+create pair is the "levels are
        // recomputed and redrawn" the user sees, and it is not even necessary:
        // with the timeframe-free prefix the new instance finds the objects where
        // they are, adopts them through the cache (a cache miss costs one
        // ObjectFind and then takes the UPDATE path), and a timeframe switch
        // becomes one in-place property pass.
        //
        // Everything that genuinely must not survive is still handled: the entry
        // point's own OnDeinit deletes the panels, menu and HTF candles before
        // this function runs, and REASON_REMOVE still wipes everything deeply.
        //
        // P-PERF-38d: and the NEXT instance is told, with one fingerprint, that
        // the chart is already drawn by a compatible scheme — without that the
        // fresh instance's first pass sees an empty stored signature, takes the
        // topology-changed branch, and wipes the family it just kept.
        SaveTopologyAdoptionStamp();
        // P-VIEW-05: the OTHER side of the handshake, ungated. `preexist` here is
        // what the chart still holds the instant we leave; the next instance's
        // `probe=adopt preexist=` is what it holds when we come back. Equal numbers
        // = the family survived the reload (so any wipe is OURS); 577 -> 0 = the
        // terminal deleted it during the unload (so no adoption can be right and
        // the rebuild cost, not the wipe, is the thing to fix). One walk, once per
        // switch, and it is the number this whole report has been missing.
        Print("[P-VIEW] probe=handoff reason=", reason, " fp=", AdoptionFingerprint(),
              " preexist=", LevelFamilyObjectsOnChart(), " total=", ObjectsTotal(0, -1, -1));
        DEBUG_PRINTF2("OnDeinit (reason=", reason, " - level family KEPT for in-place update)");
    }
    else
    {
        DEBUG_PRINTF("OnDeinit (reason=", reason);
        DeleteAllIndicatorObjects(false);
        ClearTopologyAdoptionStamp();
    }

    p49branch = GetTickCount() - p49t; p49t = GetTickCount();
    CleanupCustomPriceObjects(false, true);
    // FIX: Force ChartRedraw after cleanup so deleted objects disappear immediately
    if(reason != REASON_REMOVE) ChartRedraw();
    Comment("");
    DEBUG_PRINT("Freeing arrays...");
    ArrayFree(g_storedTHs);
    ArrayFree(g_labelPositions);
    DEBUG_PRINT("Cleaning up managers...");
    CleanupBasePriceManager();
    CleanupATRCache();
    CleanupObjectCountManager();
    CleanupPerformanceOptimizations();
    CacheClear();
    g_initialized = false;
    g_calculatedOnce = false;
    g_redrawTHLevelsNeeded = true;
    g_highestHigh = EMPTY_VALUE;
    g_lowestLow = EMPTY_VALUE;
    g_currentPrice = 0.0;
    g_lastCalculation = 0;
    g_lastHistoricalUpdate = 0;
    g_dailyClosePriceForTH = EMPTY_VALUE;
    g_objectCountLast = 0;
    g_lastObjectCleanup = 0;
    // P-PERF-49: the split, printed only when the handover is actually slow - the
    // same gate and the same "no line while it is cheap" rule as every ledger here.
    uint p49rest = GetTickCount() - p49t;
    uint p49total = p49knot + p49locks + p49stamp + p49atr + p49names + p49branch + p49rest;
    if(p49total >= P49_DEINIT_WARN_MS)
        _LOG_GATE_W Print("[W][PERF] deinit handler breakdown: knot=", (int)p49knot,
              "ms locks=", (int)p49locks, "ms stamp=", (int)p49stamp,
              "ms atr=", (int)p49atr, "ms names=", (int)p49names,
              "ms branch=", (int)p49branch, "ms rest=", (int)p49rest,
              "ms total=", (int)p49total, "ms reason=", reason);
    DEBUG_PRINT("Cleanup completed successfully");
}

#endif // EVENT_HANDLERS_DEINIT_MQH
