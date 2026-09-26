   //+------------------------------------------------------------------+
//| Event Handlers - Version 3.10 GOLD                              |
//| Security & Performance Audit Complete                           |
//+------------------------------------------------------------------+
#ifndef EVENT_HANDLERS_MQH
#define EVENT_HANDLERS_MQH
#property strict

//==============================================================================
// P-PERF-38c — ONE-TIME MIGRATION OFF THE TIMEFRAME-NAMED SCHEME
//
// P-PERF-38 made the level-object prefix timeframe-free, so a chart that had
// been drawn by an older build still holds one whole namespace per timeframe it
// ever visited (`THLevels_H1_*`, `THLevels_M15_*`, ...). The old teardown swept
// all eleven of those on EVERY timeframe switch - eleven full-chart prefix scans
// for objects that, after this migration, do not exist at all.
//
// So the sweep is not deleted; it is MOVED OUT OF THE SWITCH and gated on a
// per-chart stamp. It runs exactly once per chart, ever. Steady state: one
// GlobalVariableCheck. That is the difference between "cleanup that scales with
// how often you press H1" and "cleanup that happens once".
void MigrateTimeframeNamedObjects()
{
   // P-PERF-38f: the stamp has ONE owner (GlobalVariables), shared with the label
   // sweep that must stop doing this work on every timeframe switch.
   string stamp = NameSchemeStampName();
   if(LegacyNameSchemeMigrated()) return;   // this chart is already migrated

   // Every string GetCurrentTimeframe() can return, plus the two legacy
   // spellings ("MN" from ClearAllLabels, "UNKNOWN" for a CUSTOM period).
   static string s_tfNs[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN", "MN1", "UNKNOWN"};
   g_suppressDeleteEvents = true;
   int removed = 0;
   for(int n = 0; n < ArraySize(s_tfNs); n++)
      removed += ObjectsDeleteAll(0, inpObjectPrefix + "_" + s_tfNs[n] + "_");
   // The ATR/TH label families also exist WITHOUT a TF namespace
   // (`inpObjectPrefix + "ATR_*" / "TH_*"`), and the legacy shared-pattern ones
   // carry `inpObjectPrefix + "SharedPattern_"`.
   removed += ObjectsDeleteAll(0, inpObjectPrefix + "ATR_");
   removed += ObjectsDeleteAll(0, inpObjectPrefix + "TH_");
   removed += ObjectsDeleteAll(0, inpObjectPrefix + "SharedPattern_");
   g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
   g_suppressDeleteEvents = false;
   InvalidateObjectCountCache();
   GlobalVariableSet(stamp, 1.0);
   // Named, once, only when it actually did something - so the log shows the
   // upgrade happened and never repeats.
   if(removed > 0)
      _LOG_GATE_I Print("[I][GEN] P-PERF-38 migration: removed ", removed,
                        " legacy timeframe-named object(s) - this runs once per chart");
}

//==============================================================================
// P-PERF-38d — TOPOLOGY ADOPTION ACROSS MT4'S FORCED RELOAD
//
// P-PERF-38 named the level family without the timeframe and P-PERF-38b stopped
// the teardown from deleting it. On their own those two are NOT enough, and the
// reason is subtle: a chart period change makes MT4 unload and RELOAD the
// indicator, so the new instance starts with an EMPTY stored signature
// (`s_lastLevelSig == ""`). The first comparison is therefore trivially true ->
// `levelTopologyChanged` -> `shouldClearLevels` -> a full `ClearAllLevels` of the
// whole family, immediately followed by the staged rebuild that creates it all
// again. That delete+create pair IS the "changing the timeframe recomputes and
// redraws my levels" the user reports, and it survived the naming fix because
// nothing carried the fact that the chart is already drawn.
//
// So the new instance is TOLD. At teardown an ordinary timeframe change writes
// ONE per-chart fingerprint of the inputs that decide WHICH objects may exist
// (the naming scheme, the mode, and the other structure-defining inputs) — never
// the prices, which genuinely do change per timeframe. At init that fingerprint
// is compared, and on a match the first pass adopts the previous instance's
// topology: no wipe, no staging restart, and the timeframe change reduces to a
// single in-place property pass. The prices are still re-derived (`thValue`
// comes from `GetTimeframeTH()`), but they now arrive through the RENDER
// signature, which re-asserts in place, instead of through the NAME, which
// forced a destroy-and-build.
//
// Conservative by construction: no stamp (a first attach, an older build, a
// chart the indicator was just REMOVEd from) means no adoption, i.e. exactly the
// old behaviour. A wrong "same" can only ever skip a wipe, and a skipped wipe is
// safe here because every object the render does not produce is still swept by
// CleanupSurplusPipeline and the label generation sweep — both run on every
// render.
#define NAME_SCHEME_ID 40

string AdoptionStampName() { return "Biotak_AdoptTopology_" + GetCachedChartIdStr(); }

// The topology stamp is a CLAIM (written at teardown, compared at init) that the
// objects already on the chart are still correct: on a match the first pass
// ADOPTS them, so a timeframe switch is one in-place property pass instead of a
// wipe and a staged rebuild. It names every input that decides WHICH NAMES may
// exist — naming scheme, mode, level count, start-point type, LS-first, harmonic
// pair — because a name mismatch is never repaired in place (a mode change renames
// the whole family). P-LEVEL-FOREIGN-02 — the PRICES left the stamp: a stale price
// is repaired by `SweepForeignLadderObjects()` (LevelPipeline) on the one frame the
// ladder PITCH changed (measured: 250-300 ms teardown + four 60-95 ms frames per
// switch on MT5, ~30 ms on MT4). NAME_SCHEME_ID 39 -> 40 refuses every stamp a
// previous build wrote.
int AdoptionFingerprint()
{
   int fp = NAME_SCHEME_ID;
   fp = fp * 31 + (int)GetCurrentStepMode();
   fp = fp * 31 + inpMaxLevels;
   fp = fp * 31 + (int)g_thStartPointType;
   fp = fp * 31 + (inpLSFirst ? 1 : 0);
#ifndef BUILD_LITE
   fp = fp * 31 + (inpEnableHarmonicPattern ? 1 : 0);
   fp = fp * 31 + (int)MathRound(inpHarmonicRatio * 1000.0);
#endif
   // P-LEVEL-FOREIGN-02: and NOT the prices - the note above this function is
   // the whole argument. A price that moved is repaired IN PLACE by the pitch
   // sweep; a NAME that moved is not, which is the only distinction that
   // belongs in a stamp.
   return fp;
}

// Written by the teardown of a timeframe switch: the objects are staying on the
// chart, so the next instance is allowed to adopt them.
void SaveTopologyAdoptionStamp()
{
   GlobalVariableSet(AdoptionStampName(), (double)AdoptionFingerprint());
}

// Called by every teardown path that really deletes the family. Without the
// stamp the next instance wipes and rebuilds, which is the correct answer when
// the objects are genuinely gone.
void ClearTopologyAdoptionStamp()
{
   string n = AdoptionStampName();
   if(GlobalVariableCheck(n)) GlobalVariableDel(n);
}

// Resolved ONCE per instance, at the end of OnInitHandler — after the custom-
// price restore has had its say about `g_thStartPointType`, which is one of the
// fingerprint's inputs. The VALUE itself lives in GlobalVariables.mqh: the
// pipeline's ladder sweep reads it too, and LevelPipeline.mqh is included
// BEFORE this file (entry lines 93 and 99), where MQL4 has no forward reference
// for a global.

void ResolveTopologyAdoption()
{
   g_adoptPreviousTopology = false;
   string n = AdoptionStampName();
   if(!GlobalVariableCheck(n)) return;                  // first attach / old build
   g_adoptPreviousTopology = ((int)GlobalVariableGet(n) == AdoptionFingerprint());
   if(g_adoptPreviousTopology)
      _LOG_GATE_I Print("[I][GEN] P-PERF-38d: level topology adopted from the previous "
                        "instance - timeframe switch updates in place (no wipe, no rebuild)");
}

//==============================================================================
// P-UI-56 — the custom-price SOURCE has ONE owner and ONE precedence. The whole
// level family is anchored on `GetMidpointPrice(g_thStartPointType)` ->
// `g_customTHStartPrice`, and it was resolved by TWO copies of the same
// three-branch chain (here and in RedrawAllObjects) carrying two defects that only
// a used chart shows: (1) the persisted placement was keyed per SYMBOL, so two
// charts of one symbol shared one price; (2) the INPUT silently outranked and
// OVERWROTE the placement keys. ONE owner answers "what is the custom price of
// THIS chart?": the user's own chart-keyed placement BEATS the static input, and
// the input is only the seed when the chart has no placement of its own — it never
// writes the placement keys (so the OFF paths still return to the input).
//==============================================================================
string CustomPriceGVName()         { return "Biotak_CustomPrice_" + GetCachedChartIdStr(); }
string CustomPriceOverrideGVName() { return "Biotak_CustomPriceOverride_" + GetCachedChartIdStr(); }
// The PREVIOUS scheme's keys (symbol-scoped). Read once, ONLY to adopt a price an
// older build left behind; never written again (only purged on REASON_REMOVE).
string CustomPriceLegacyGVName()         { return "Biotak_CustomPrice_" + GetCachedSymbol(); }
string CustomPriceLegacyOverrideGVName() { return "Biotak_CustomPriceOverride_" + GetCachedSymbol(); }

void CustomPriceMigrateLegacyKeys()
{
    static bool s_migrationDone = false;
    if(s_migrationDone) return;
    s_migrationDone = true;                                  // one probe per instance, never per frame
    if(GlobalVariableCheck(CustomPriceGVName())) return;     // this chart owns a price already
    string legacy = CustomPriceLegacyGVName();
    if(!GlobalVariableCheck(legacy)) return;
    double legacyPrice = GlobalVariableGet(legacy);
    if(!(legacyPrice > 0.0) || !MathIsValidNumber(legacyPrice)) return;
    // Is the legacy price a USER PLACEMENT or an input-seeded copy? It matters:
    // a placement must outrank the input, an input seed must not. Provable from the
    // old writers - only ONE of them wrote the price key from a non-user source,
    // and that one (the init/frame INPUT branch) wrote `inpCustomTHStartPrice`
    // itself. So: with the input unset the legacy price can only be a placement;
    // with the input set, the legacy override flag is the only trustworthy witness.
    string legacyFlag = CustomPriceLegacyOverrideGVName();
    bool legacyOverride = GlobalVariableCheck(legacyFlag) ? (GlobalVariableGet(legacyFlag) != 0.0) : false;
    bool legacyIsPlacement = legacyOverride || !(inpCustomTHStartPrice > 0.0);
    GlobalVariableSet(CustomPriceGVName(), legacyPrice);
    GlobalVariableSet(CustomPriceOverrideGVName(), legacyIsPlacement ? 1.0 : 0.0);
    _LOG_GATE_I Print("[I][GEN] P-UI-56: adopted the symbol-scoped custom price ",
                      DoubleToString(legacyPrice, Digits), " as this chart's own (",
                      legacyIsPlacement ? "placement" : "input seed", ")");
}

// ONE writer for "the user placed / moved the line on THIS chart".
void CustomPricePersistPlacement(const double price)
{
    if(!(price > 0.0) || !MathIsValidNumber(price)) return;
    GlobalVariableSet(CustomPriceGVName(), price);
    GlobalVariableSet(CustomPriceOverrideGVName(), 1.0);
}

// ONE writer for "this chart has no placement of its own" (the OFF paths).
void CustomPriceForgetPlacement()
{
    GlobalVariableDel(CustomPriceGVName());
    GlobalVariableSet(CustomPriceOverrideGVName(), 0.0);
}

// The resolver's result. Ints, not an enum: both call sites are ABOVE this block
// in the translation unit, and MQL4 type resolution is positional.
#define CPSRC_NONE   0   // no placement and no input price → not the custom-price start point
#define CPSRC_PLACED 1   // the user's own price on this chart (wins over the input)
#define CPSRC_INPUT  2   // the Input's seed price (the "default state")

int CustomPriceResolveSource(double &priceOut, bool &overrideFlagOut)
{
    priceOut = 0.0;
    overrideFlagOut = false;
    CustomPriceMigrateLegacyKeys();

    string priceKey = CustomPriceGVName();
    string flagKey  = CustomPriceOverrideGVName();
    double placed = GlobalVariableCheck(priceKey) ? GlobalVariableGet(priceKey) : 0.0;
    bool   placedFlag = GlobalVariableCheck(flagKey) ? (GlobalVariableGet(flagKey) != 0.0) : false;
    if(placed > 0.0 && MathIsValidNumber(placed)) {
        // The flag only decides WHO WINS (this chart's placement or the Input) - the
        // stored price is honoured either way, exactly like the old chain, whose
        // branch 1 and branch 3 restored the SAME price and differed only by that
        // flag. Keeping that asymmetry is what lets a parameter change put the start
        // point back on the Input default while the price survives for later.
        if(placedFlag) {
            priceOut = placed;
            overrideFlagOut = true;
            return CPSRC_PLACED;
        }
        if(inpCustomTHStartPrice > 0.0 && MathIsValidNumber(inpCustomTHStartPrice)) {
            priceOut = inpCustomTHStartPrice;
            return CPSRC_INPUT;
        }
        priceOut = placed;
        return CPSRC_PLACED;
    }
    if(inpCustomTHStartPrice > 0.0 && MathIsValidNumber(inpCustomTHStartPrice)) {
        priceOut = inpCustomTHStartPrice;
        return CPSRC_INPUT;
    }
    return CPSRC_NONE;
}

int OnInitHandler() {
    // P-PERF-38c: the one-time legacy sweep must land before the first render, so
    // a chart drawn by an older build cannot blend two naming schemes.
    MigrateTimeframeNamedObjects();
    // P-PERF-10: phase ledger for the init path (see g_pInitMs* in GlobalVariables).
    uint pInitTick = GetTickCount();
    // Seed runtime settings from the real MT4 Inputs-dialog values FIRST:
    // every inpX read from here on is the runtime copy (see RuntimeSettings.mqh).
    RuntimeSettingsInit();
#ifdef BUILD_LITE
    Print("[BUILD] TH3 ", TH3_BUILD_TAG, " LITE");
#else
    Print("[BUILD] TH3 ", TH3_BUILD_TAG, " FULL");
#endif
    InitializeGlobalCache();
    LoggerSetLevel(inpLogLevel);
    // P-UI-90: resolve "what is the user's view pair on THIS chart?" before any
    // owner can take the lock, and heal a chart an older build left locked (see
    // the block note in GlobalVariables.mqh). Two chart reads + three GVar reads.
    ChartViewLockInit();
    // P-PERF-02: a fresh instance knows nothing about the visibility masks the
    // previous one left on the chart (and re-attach / TF switch reuses the same
    // chart objects), so every guarded mask write must land once. The
    // hide-once state starts clean for the same reason.
    BumpTfEpoch();
    ResetHideAllState();
    // P-PERF-07: a fresh instance can see objects the previous one left on the
    // chart (re-attach / TF switch reuses the same chart), so the previous
    // instance's "this name is absent" facts are not trustworthy yet.
    CacheAbsentResetAll();

    // Restore hidden state
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    bool shouldBeHidden = RestoreBoolGlobalVar(gvar_name, false);
    DEBUG_PRINTF("OnInit: shouldBeHidden=", shouldBeHidden);

    string chartIdStr = GetCachedChartIdStr();
    datetime initNow = TimeCurrent();

    // Timeframe-switch debounce: detect recent TF change (within 20s)
    string tfSwitchStampGvar = "Biotak_LastTFSwitch_" + chartIdStr;
    bool recentTimeframeSwitch = false;
    if(GlobalVariableCheck(tfSwitchStampGvar)) {
        datetime lastTFSwitch = (datetime)GlobalVariableGet(tfSwitchStampGvar);
        if(initNow > 0 && lastTFSwitch > 0 && (initNow - lastTFSwitch) <= 20)
            recentTimeframeSwitch = true;
    }

    // Restore toggle states (early, before validation)
    g_triggerLevelsEnabled = RestoreBoolGlobalVar("Biotak_TriggerLevels_" + chartIdStr, inpShowTrigger);
    g_linesVisible = RestoreBoolGlobalVar("Biotak_LinesVisible_" + chartIdStr, inpShowLines);

    // Restore ATR labels visibility (Default to OFF on first load)
    g_atrLabelsVisible = RestoreBoolGlobalVar("Biotak_ATRLabels_" + chartIdStr, false);

    // Restore TH labels mode (Default OFF: 0=OFF, 1=FRACTAL, 2=STANDARD exclusive)
    string thLabelsGvarName = "Biotak_THLabels_" + chartIdStr;
    if(GlobalVariableCheck(thLabelsGvarName)) {
        double gvarValue = GlobalVariableGet(thLabelsGvarName);
        bool isZero = MathAbs(gvarValue - 0.0) < EPSILON_GENERAL;
        bool isOne = MathAbs(gvarValue - 1.0) < EPSILON_GENERAL;
        bool isTwo = MathAbs(gvarValue - 2.0) < EPSILON_GENERAL;
        bool isThree = MathAbs(gvarValue - 3.0) < EPSILON_GENERAL;
        if(isZero || isOne || isTwo || isThree) {
            g_thLabelsMode = (int)gvarValue;
            if(g_thLabelsMode == 3) g_thLabelsMode = 2; // legacy BOTH -> STANDARD
            SyncTHFlagsFromMode();   // flags follow the restored mode
        } else {
            _LOG_GATE_E Print("[E][GEN] OnInit: Corrupted TH labels state (", DoubleToString(gvarValue, 10), "), resetting");
            g_thLabelsMode = 0; // Default to OFF
            GlobalVariableSet(thLabelsGvarName, 0.0);
            g_thLabelsVisible = false;
        }
    } else {
        // First attach: honor the Inputs-dialog TH flags, default ON is STANDARD.
        g_thLabelsMode = THModeFromFlags();
        if(g_showTHLabels && g_thLabelsMode == 0) g_thLabelsMode = 2;
        SyncTHFlagsFromMode();
    }

    //+------------------------------------------------------------------+
    //| P-UI-119 (2026-09-25) — THE LEVEL AND ZONE FAMILIES START OFF,    |
    //| ONCE PER CHART (user order «سطوح هم پیش فرض خاموش باشه»).           |
    //|                                                                  |
    //| The INPUTS default every one of them off now, but the states     |
    //| restored just above are PER CHART — so a chart that ever had a   |
    //| family on keeps it on for ever, and the new default would never  |
    //| be visible to anyone who has used the chart before. A default is |
    //| only real when it is applied to what is ALREADY stored, so this  |
    //| runs once per chart (the stamp idiom the timeframe-name migration|
    //| above uses) and then never again: from the next attach on the    |
    //| saved state is the user's own again.                             |
    //|                                                                  |
    //| What it covers — the level/zone families the loader above reads   |
    //| KEYS for: the trigger ladder, the hand-drawn level LINES           |
    //| (`inpShowLines`' own label), the TH labels and the mid-zone band  |
    //| (whose key spelling belongs to RuntimeSettings, so the asking is   |
    //| delegated — one owner per key). The ATR/trade LABEL blocks are    |
    //| not levels and are left exactly as the user set them.             |
    //+------------------------------------------------------------------+
    string levelsOffStamp = "Biotak_LevelsOffDefault_" + chartIdStr;
    if(!GlobalVariableCheck(levelsOffStamp)) {
        GlobalVariableDel("Biotak_TriggerLevels_" + chartIdStr);
        GlobalVariableDel("Biotak_LinesVisible_"  + chartIdStr);
        GlobalVariableDel("Biotak_THLabels_"      + chartIdStr);
        MidZonesStateForget();          // the mid-zone band's own key (RuntimeSettings owner)
        g_triggerLevelsEnabled = false; // ...and the runtime copies, so THIS attach is clean too
        g_linesVisible         = false;
        g_thLabelsMode         = 0;
        SyncTHFlagsFromMode();          // the TH flag mirrors follow the single source of truth
        g_showMidZones         = false;
        GlobalVariableSet(levelsOffStamp, 1.0);
    }

    int validationResult = ValidateInputs();
    if(validationResult != INIT_SUCCEEDED) return validationResult;
    g_pInitMsSettings = GetTickCount() - pInitTick;   // P-PERF-10
    pInitTick = GetTickCount();

    ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
    // P-UI-127 (2026-09-25): THE CREATE CHANNEL IS SUBSCRIBED AT LAST. MT4 sends
    // no CHARTEVENT_OBJECT_CREATE until this flag is set, and the handler's whole
    // `if(id == CHARTEVENT_OBJECT_CREATE)` branch (P-UI-100b's "this gesture is a
    // DRAW, not a grab" and P-DRAW-01's `DrawStyleApplyOnCreate`) had therefore
    // never run in any build: `s_drawNotGrab`'s only writer is unreachable without
    // it. The branch's own cost is one prefix test per foreign create, which is
    // exactly what the flag limits it to — our own objects never reach it.
    ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);
    ChartSetInteger(0, CHART_SHOW_GRID, false);
    // 250 ms cadence (not 1 s): hold-to-open polling + hint pumps stay
    // responsive on tick-less charts (weekends). Every OnTimer callee is
    // time-gated / change-guarded / idempotent, so 4 Hz is free.
    EventSetMillisecondTimer(250);
    CheckArraySizes();

    // Deferred init: skip heavy historical load on recent TF switch
    bool deferHeavyInit = recentTimeframeSwitch;
    if(!deferHeavyInit) {
        if(!UpdateHistoricalValues()) {
            // P-MT5-01b (2026-09-16): A NOT-YET-LOADED HISTORY IS A DEFERRAL, NOT A FATAL.
            //
            // This used to `return INIT_FAILED`. That aborts the whole
            // initialisation, so the terminal renders an indicator that never
            // draws anything - and the live MT5 log carries precisely that
            // abort 17 times in one day, as "[E][GEN] OnInit:
            // UpdateHistoricalValues failed. Error: 4401"
            // (ERR_HISTORY_NOT_FOUND), on the symbols whose top timeframe the
            // terminal had not built yet (SPXUSD-ECN H1 among them).
            //
            // MT4 CANNOT REACH THIS BRANCH: its series are resident, so iBars()
            // never answers 0. The MT4-observable behaviour is therefore "init
            // succeeds and the levels appear", and that is what MT5 must show
            // too. So rather than invent a recovery path, fall through to the
            // deferral the recent-TF-switch branch beside it already uses:
            // g_initialized stays false, and RedrawAllObjects - which tests
            // exactly that flag - retries this call every frame, logs that it is
            // retrying, and draws the moment the data lands.
            //
            // The warning is rate-limited so a genuinely unavailable symbol
            // cannot flood Experts; a re-request is issued by
            // UpdateHistoricalValues itself (P-MT5-01b), so the retry converges
            // instead of polling a series nobody asked for.
            static uint s_lastHistInitWarnMs = 0;
            uint histInitNowMs = GetTickCount();
            if(histInitNowMs - s_lastHistInitWarnMs > 30000) {
                _LOG_GATE_W Print("[W][GEN] OnInit: historical data not ready (err ",
                                  GetLastError(), ") - deferring; the redraw path retries");
                s_lastHistInitWarnMs = histInitNowMs;
            }
            g_initialized = false;
        } else {
            g_initialized = true;
        }
    } else {
        g_initialized = false;
    }
    g_calculatedOnce = false;
    InitializeAdaptiveScaling();

    g_dailyClosePriceForTH = GetPriceForPreviousDay(inpTHPriceType);
    if(g_dailyClosePriceForTH == EMPTY_VALUE || !MathIsValidNumber(g_dailyClosePriceForTH) || g_dailyClosePriceForTH <= 0) {
        // P-MT5-01b (2026-09-16): DEFER, DO NOT ABORT.
        //
        // GetPriceForPreviousDay now answers EMPTY_VALUE while the D1 series has
        // never been readable (MT5 synthesises it on demand; see the guard in
        // HistoricalDataFunctions.mqh), because the alternative was worse: it
        // used to return a stamped 0 for a full day, which made the TH base
        // price - and therefore the whole level family - zero.
        //
        // Returning INIT_FAILED here would just move the failure, so this takes
        // the same deferral the history branch above takes: g_initialized stays
        // false, RedrawAllObjects retries, and the first redraw frame runs
        // UpdateBasePrice() (its 30-minute gate is empty on a fresh instance,
        // so it fires immediately and fills g_basePriceCached), which is what
        // GetBasePriceForTH() reads. No new recovery path - the one that already
        // exists is simply no longer bypassed by an aborted init.
        //
        // The wider test (non-finite, negative, zero) is the P-UI-57 discipline:
        // a NaN is neither > 0 nor < 0, so a strict `== EMPTY_VALUE` would let
        // it through and it would become the anchor of every level.
        g_dailyClosePriceForTH = 0.0;
        g_initialized = false;
        static uint s_lastPrevDayWarnMs = 0;
        uint prevDayNowMs = GetTickCount();
        if(prevDayNowMs - s_lastPrevDayWarnMs > 30000) {
            _LOG_GATE_W Print("[W][GEN] OnInit: previous-day prices not ready (D1 series still loading) - deferring");
            s_lastPrevDayWarnMs = prevDayNowMs;
        }
    }
    g_pInitMsHistory = GetTickCount() - pInitTick;   // P-PERF-10
    pInitTick = GetTickCount();

    // P-UI-56: no local GVar names here any more - the custom-price source (and its
    // keys) have ONE owner in this file (see the P-UI-56 block above), and the
    // resolution below asks it instead of re-implementing the chain.
    int digits = Digits;

    // Validate custom price input
    double validatedCustomPrice = inpCustomTHStartPrice;
    // P-UI-57: a non-finite input price is not "negative" and not "too large" —
    // every comparison against NaN is false, so it would sail through both checks
    // below and become the anchor of the whole level family.
    if(!MathIsValidNumber(validatedCustomPrice)) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (not a number)");
        validatedCustomPrice = 0.0;
    }
    if(validatedCustomPrice < 0.0) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (negative): ", validatedCustomPrice);
        validatedCustomPrice = 0.0;
    }
    if(validatedCustomPrice > 1000000.0) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (too large): ", validatedCustomPrice);
        validatedCustomPrice = 0.0;
    }

    // P-UI-56: the source of the drawing price is resolved by ONE owner, shared
    // with the per-frame path (`RedrawAllObjects`): THIS chart's placement first,
    // the Input's seed second, nothing third - and the Input NEVER writes the
    // placement keys, so a price the user dragged can no longer be replaced by the
    // value in the Inputs dialog on the next attach.
    //
    // The old init chain also wrote `GlobalVariableSet(gvarName, input)` in its
    // input branch while the per-symbol keys were shared by every chart of the
    // symbol - the mechanism behind "each time the levels go somewhere else".
    double srcPrice = 0.0;
    bool   srcOverride = false;
    int    srcKind = CustomPriceResolveSource(srcPrice, srcOverride);
    g_customPriceKeyboardOverride = srcOverride;
    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][GEN] === Custom Price Debug (OnInit) ===");
    Print("[D][GEN] inpCustomTHStartPrice: ", inpCustomTHStartPrice, " validated: ", validatedCustomPrice);
    Print("[D][GEN] resolved price: ", srcPrice, " kind: ", srcKind);
    #endif
    if(srcKind != CPSRC_NONE) {
        g_customTHStartPrice = srcPrice;
        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
        _LOG_GATE_I Print("[I][GEN] OnInit: custom price source=",
                          (srcKind == CPSRC_PLACED ? "this chart's placement" : "Input seed"),
                          " at ", DoubleToString(g_customTHStartPrice, digits));
        CreateCustomPriceLine(g_customTHStartPrice, digits);
    } else {
        g_customTHStartPrice = 0.0;
        g_thStartPointType = inpTHStartPointType;
        g_customPriceKeyboardOverride = false;
        CustomPriceForgetPlacement();
        DEBUG_PRINT("OnInit: Using default mode (no custom price)");
    }

    g_redrawTHLevelsNeeded = true;

    // Base price init debounce: skip if recently initialized during TF switch
    string baseInitStampGvar = "Biotak_BaseInit_" + chartIdStr;
    bool shouldInitBasePrice = true;
    if(deferHeavyInit && GlobalVariableCheck(baseInitStampGvar)) {
        datetime lastBaseInit = (datetime)GlobalVariableGet(baseInitStampGvar);
        if(initNow > 0 && lastBaseInit > 0 && (initNow - lastBaseInit) <= 120)
            shouldInitBasePrice = false;
    }
    if(shouldInitBasePrice) {
        InitializeBasePriceSystem();
        if(initNow > 0) GlobalVariableSet(baseInitStampGvar, (double)initNow);
    } else {
        g_systemInitialized = false;
    }
    g_pInitMsBase = GetTickCount() - pInitTick;   // P-PERF-10
    pInitTick = GetTickCount();

    // Restore timeframe lock state
    string lockFlagName = "Biotak_LockTF_" + chartIdStr;
    if(GlobalVariableCheck(lockFlagName)) {
        g_timeframeLocked = (bool)GlobalVariableGet(lockFlagName);
    }
    string lockPeriodName = "Biotak_LockTFPeriod_" + chartIdStr;
    if(GlobalVariableCheck(lockPeriodName)) {
        // R-TF-UNIT: this value outlives the process that wrote it. An MT5 build
        // from before the unit fix persisted an ENUM_TIMEFRAMES constant here
        // (16385 for H1), which would restore as a lock on a timeframe that does
        // not exist - the badge reading "16385" and every `tf == Period()` test
        // failing. CompatMinutes() normalises whatever is on disk to minutes, so
        // the upgrade is invisible to the user.
        g_lockedPeriod = CompatMinutes((int)GlobalVariableGet(lockPeriodName));
    }

    // VIEWLOCK-OFF: view-lock restore retired —
    //string viewFlagName = "Biotak_ViewLock_" + chartIdStr;
    //if(GlobalVariableCheck(viewFlagName)) {
    //    g_viewLockEnabled = (GlobalVariableGet(viewFlagName) > 0.5);
    //}
    //if(GlobalVariableCheck("Biotak_ViewAnchorT_" + chartIdStr)) {
    //    g_viewAnchorTime = (datetime)GlobalVariableGet("Biotak_ViewAnchorT_" + chartIdStr);
    //    g_viewAnchorMin = GlobalVariableGet("Biotak_ViewAnchorMin_" + chartIdStr);
    //    g_viewAnchorMax = GlobalVariableGet("Biotak_ViewAnchorMax_" + chartIdStr);
    //}
    //if(g_viewLockEnabled) {
    //    if(recentTimeframeSwitch && g_viewAnchorTime > 0) g_viewRestorePending = true;
    //    else { ViewLockCapture(); ViewAnchorLineEnsure(); }   // fresh attach: anchor = current view
    //}

    // STEPOVERRIDE-OFF: one-time migration — the retired override key becomes
    // the single base mode. (If the chart ALSO has an OV_ SM panel value, that
    // loads later in RuntimeSettingsLoadOverrides and wins — it is the newer
    // explicit choice.) The key is deleted and never read again.
    string stepModeGvarName = "Biotak_StepMode_" + chartIdStr;
    if(GlobalVariableCheck(stepModeGvarName)) {
        int migratedMode = (int)GlobalVariableGet(stepModeGvarName);
        if(migratedMode >= 0 && migratedMode <= 3) {
            g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)migratedMode;
        } else {
            _LOG_GATE_W Print("[W][GEN] OnInit: Corrupted StepMode (", migratedMode, "), resetting.");
        }
        GlobalVariableDel(stepModeGvarName);
    }

    // Restore SS/LS sequence origin selected from the Custom Price menu
    // (0 = SS first, 1 = LS first, any other value = use input).
    // P-UI-67: the restore ADOPTS the persisted answer, through the owners - the
    // read happens first because the clear (which owns the key) deletes it, and an
    // absent or corrupt key must end as "the input answers", never as a bare
    // `= -1` that leaves the persisted value behind for the next attach to read.
    string sslsFirstGvarName = "Biotak_SSLSFirst_" + chartIdStr;
    bool sslsKeyPresent = GlobalVariableCheck(sslsFirstGvarName);
    int restoredSSLSFirst = sslsKeyPresent ? (int)GlobalVariableGet(sslsFirstGvarName) : -1;
    SSLSOrderOverrideClear();
    if(restoredSSLSFirst == 0 || restoredSSLSFirst == 1)
        SSLSOrderOverrideSet(restoredSSLSFirst);

    // Restore factor with validation (0 < val <= MAX_SAFE_FACTOR)
    string factorGvarName = "Biotak_Factor_" + chartIdStr;
    if(GlobalVariableCheck(factorGvarName)) {
        double val = GlobalVariableGet(factorGvarName);
        if(val > 0 && val <= MAX_SAFE_FACTOR) {
            g_factorValueOverride = val;
        } else {
            _LOG_GATE_E Print("[E][GEN] OnInit: Invalid Factor (", val, "), resetting.");
            GlobalVariableDel(factorGvarName);
            g_factorValueOverride = 0.0;
        }
    } else {
        g_factorValueOverride = 0.0;
    }
    // Manual mode factor clamping
    if(inpFactorMode == FACTOR_MODE_MANUAL) {
        if(inpFactorValue <= 0 || inpFactorValue > MAX_SAFE_FACTOR) {
            _LOG_GATE_E Print("[E][GEN] OnInit: Invalid inpFactorValue (", inpFactorValue, "), clamping to 50.0");
            g_factorValueOverride = 50.0;
        }
    }

    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    // Restore TH3 frequency with dynamic max validation (binary subdivision)
    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
    if(GlobalVariableCheck(freqGvarName)) {
        double restoredFreq = GlobalVariableGet(freqGvarName);
        double maxFreq = GetFrequencyByIndex(MAX_TH3_FREQ_INDEX);
        if(restoredFreq > 0 && restoredFreq <= maxFreq) {
            g_th3FreqOverride = restoredFreq;
        } else {
            g_th3FreqOverride = 0;
            GlobalVariableDel(freqGvarName);
        }
    }
    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
    if(GlobalVariableCheck(indexGvarName)) {
        int restoredIndex = (int)GlobalVariableGet(indexGvarName);
        if(restoredIndex >= MIN_TH3_FREQ_INDEX && restoredIndex <= MAX_TH3_FREQ_INDEX) {
            g_th3FreqIndex = restoredIndex;
        } else {
            g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
            GlobalVariableDel(indexGvarName);
        }
    }
    // Binary subdivision migration: sync index with saved frequency (old GM -> binary)
    if(g_th3FreqOverride > 0) {
        double expectedFreq = GetFrequencyByIndex(g_th3FreqIndex);
        if(MathAbs(expectedFreq - g_th3FreqOverride) > 0.01) {
            g_th3FreqIndex = FindNearestFreqIndex(g_th3FreqOverride);
            g_th3FreqOverride = GetFrequencyByIndex(g_th3FreqIndex);
            GlobalVariableSet(freqGvarName, g_th3FreqOverride);
            GlobalVariableSet(indexGvarName, (double)g_th3FreqIndex);
            _LOG_GATE_I Print("[I][GEN] OnInit: TH3 Freq migrated to binary subdivision: idx=", g_th3FreqIndex,
                              " freq=", DoubleToString(g_th3FreqOverride, 4));
        }
    }
#endif

    InitializeATRCache();

    // ATR warmup debounce: skip if recently warmed up (within 90s)
    if(inpShowATRLabels && !shouldBeHidden) {
        datetime nowWarmup = TimeCurrent();
        string warmupGvar = "Biotak_ATRWarmup_" + chartIdStr;
        datetime lastWarmup = 0;
        if(GlobalVariableCheck(warmupGvar)) {
            lastWarmup = (datetime)GlobalVariableGet(warmupGvar);
        }
        if(lastWarmup <= 0 || nowWarmup <= 0 || (nowWarmup - lastWarmup) > 90) {
            WarmupATRMultiTFCache();
            if(nowWarmup > 0) GlobalVariableSet(warmupGvar, (double)nowWarmup);
        }
    }

    g_pInitMsAtr = GetTickCount() - pInitTick;   // P-PERF-10 (ATR cache init + warmup)

    PrintBuildInfo();

    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    // P-LM-04: a leg measurement drawn by an older build carries loose labels and
    // no plate; its readout is recomputed into today's box here — the same slot,
    // and the same rule, as the pattern restore below: legacy chart objects take
    // the current build's shape before the first render. It runs AFTER the ATR
    // warmup above on purpose: at attach a TF whose history is not loaded yet gives
    // no ATR, and the sweep refuses to write a box built on a guessed one.
    LegMeasureUpgradeLegacy();
    // P-TH3-D4h: legacy chart objects repaint with the current build first;
    // only when nothing was restored does the settings-change flag matter.
    int th3Restored = TH3RestorePatternsFromChart();
    // Check if TH3 objects need update (after settings change)
    string th3UpdateFlag = "Biotak_TH3_NeedsUpdate_" + chartIdStr;
    if(GlobalVariableCheck(th3UpdateFlag) && GlobalVariableGet(th3UpdateFlag) > 0) {
        if(th3Restored <= 0) UpdateAllTH3Objects();
        GlobalVariableDel(th3UpdateFlag);
    }
#endif

    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][GEN] OnInit complete: deferred=", deferHeavyInit, " hidden=", shouldBeHidden);
    #endif

    // Hidden state: set flags (objects created later in OnCalculate/RedrawAllObjects)
    if(shouldBeHidden) {
        g_redrawTHLevelsNeeded = false;
    } else {
        g_redrawTHLevelsNeeded = true;
    }

    #ifdef ENABLE_ASSERTIONS
    FactorModeSanityCheck();
    #endif

    // P-PERF-38d: LAST thing before the first frame — every fingerprint input
    // (mode, max levels, start point, LS-first, harmonic) is final by now.
    ResolveTopologyAdoption();

    // P-DRAW-01/02 (2026-09-22): the drawing toolbar's own two tables — the
    // per-kind style memory and the preset slots (the built-in suggestions the
    // user overwrites). Seeded once per instance, before any drawing can exist.
    DrawStyleInit();
    DrawPresetsInit();
    DrawPresetsLoad();   // P-DRAW-05: the user's own templates survive the session

    return INIT_SUCCEEDED;
}

// Helper function to create custom price horizontal line (DRY)
//
// P-UI-48: THE LINE IS ALWAYS GRABBABLE. "Why doesn't it move like it used
// to?" - because P-UI-45 answered the interference report by making a SETTLED
// line non-SELECTABLE, and the drag IS that flag. The interference was never
// selectability; it was a SELECTION THAT OUTLIVED ITS GESTURE:
//
//   * MT4 moves the SELECTED object on every later drag ANYWHERE on the chart,
//     so a line that stayed SELECTED was dragged along with the panel cards and
//     the BaseKnot boxes and kept re-anchoring the TH start price behind the
//     user's back;
//   * the old code wrote OBJPROP_SELECTED = true at creation, so this was the
//     line's state BEFORE any gesture of its own.
//
// So the flag pair is now: SELECTABLE true, ALWAYS (this is the movement), and
// SELECTED false, ALWAYS - MT4 selects the line ITSELF on the press that means
// to grab it (that is the moment the live-drag path polls for), and the
// selection it makes is dropped again on button-up (see
// ClearCustomPriceSelection + g_customPriceNativeDrag). Pre-selecting only ever
// enabled the hijack, and never selecting leaves the line as inert as it was
// before - both wrong. One wording for the tooltip too: every state of the line
// can be dragged and confirmed now, so a "PIN button to move" text would be a
// lie in the one place the user reads it.
bool CreateCustomPriceLine(double price, int digits,
                           string tooltipSuffix = "Drag to adjust, Double-click to confirm")
{
    if(ObjectFind(0, g_customPriceHorizontalLineName) < 0) {
        if(!ObjectCreate(0, g_customPriceHorizontalLineName, OBJ_HLINE, 0, 0, price)) {
            _LOG_GATE_E Print("[E][GEN] Failed to create custom price line. Error: ", GetLastError());
            g_customPriceLineCreated = false;
            return false;
        }
    } else {
        ObjectSetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, price);
    }
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_COLOR, GetCustomPriceRenderColor());
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_WIDTH, inpCustomPriceLevelWidth);
    // P-UI-98d: SELECTABLE follows the ARMED/SET state now — an armed line
    // drags (this IS the movement, P-UI-48), a set line is inert so no gesture
    // of any other object can steal it. The transitions go through the ONE
    // owner (CustomPriceLineOwnArm); this writer only re-asserts the state.
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, g_cpLineArmed);
    // P-UI-98p: the line is NEVER painted - the green circle is the placement
    // (user order: «خط ابی کاستوم پرایس لازم نیست همین دایره سبز کفایت
    // میکنه»). The object stays (the drag math, the grab test and the ladder
    // anchor all read it), only its picture goes. Skipped mid-gesture like
    // the selection above (P-BK-15); the transitions re-assert below.
    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&
       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    // P-UI-45/P-UI-50: never LEAVE a selection in place - a line saved into the chart
    // profile arrives SELECTED, and MT4 then moves it along with every LATER gesture
    // anywhere on the chart (the interference P-UI-45 removed) - but never write it
    // while a gesture is live. This creator is reached from the click that confirms
    // the price, and that click can arrive while the button is still DOWN: a write on
    // the object MT4 is dragging cancels that drag (P-BK-15), which is the "the drag
    // is cut off very quickly" report. So it is a compare-and-write, skipped for the
    // whole duration of a gesture: one guarded read per call, and this creator only
    // runs on init / restore / mode change, never per frame.
    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&
       (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED))
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, Z_CHART_LABEL);   // P-UI-31
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP,
                  "[PIN] Custom Price: " + DoubleToString(price, digits) + " | " + tooltipSuffix);
    g_customPriceLineCreated = true;
    CustomPriceMarkerSync();   // P-UI-98d: the green dot rides the line's own writer
    return true;
}

// P-UI-48: the ONE owner of "drop the line's selection". MT4 selects a
// SELECTABLE object on the press that grabs it, and a selection that SURVIVES
// its gesture lets MT4 drag the line along with every later drag anywhere on the
// chart - the interference P-UI-45 removed by removing the movement. It is
// called from the button-up latch (the grab/click is over) AND from the UI press
// path (the press belonged to a panel or the ring, so the terminal's selection
// of the line must not outlive it). Guarded by the read: a no-op costs one
// ObjectGetInteger, and the write happens once per gesture.
void ClearCustomPriceSelection()
{
    if(!g_customPriceLineCreated) return;
    if(!(bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED)) return;
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);
}

//==============================================================================
// P-UI-98d — THE ARMED/SET MODEL OF THE TWO HAND-SET LINES, AND THEIR MARKERS.
//
// User order: «خط کاستوم پرایس و خط step اول وقتی بعد جابجایی روش کلیک شد ست
// نهایی بشه و با دبل کلیک فعال بشه؛ تا زمانی که ست نهایی نشده آزادنه درگ بشه»
// and the marker order: «نشانهٔ رنگی (خط کاستوم سبز، step اول قرمز)، یک نشانه
// باشه که خیلی مزاحم هم نباشه» + «وقتی لاین ها رو خاموش میکنم نشان ها هم نباشه».
//
// ARMED: the line answers MT4's own drag, and ONE small dot at the chart's
// right edge marks it (green for the custom price line, red for the step-1
// handles; time-0 anchoring — the pip labels' own — so it follows the market
// with no per-bar write). SET: the line is inert — nothing can grab it, which
// is also the "dragging other objects must not steal it" half — and the dot is
// DELETED, not masked, so no other mask writer can resurrect it. A single
// click sets; a double-click re-arms. The single click waits out the
// double-click window in the pending slot (the sweep commits it), so the first
// click of a double never sets first.
//
// The markers obey the LINES switch (g_linesVisible) and the hide-all state —
// «فقط لاین ها» — and are re-owned by the same passes that already run (the
// render for the step-1 dots, this sync for the custom line's).
// P-UI-98g (2026-09-22): they also obey the REVEAL latch — «فقط وقتی روش کلیک
// کردیم دایره ها بیاد برای درگ کردن» — so an armed-but-unasked line keeps its
// circle parked.
//==============================================================================
void CustomPriceMarkerSync()
{
    // P-UI-98m: in SET state the green circle is the only marker
    // (double-click the row to re-arm), so it shows WITHOUT the 98g reveal
    // latch; ARMED keeps the latch (a fresh placement is born ARMED-but-HIDDEN,
    // and an armed-but-unasked line shows nothing).
    // P-UI-98o: the green circle ignores the LINES switch - it marks the
    // custom price placement itself, not the line family, so L hides the
    // lines and the red circles but never it (hide-all still does).
    // P-UI-98p: the line itself is never painted at all - the circle below
    // is the whole face of the placement.
    // P-UI-98q: and the circle shows whenever the placement is live - ARMED
    // and SET, with no reveal latch and no LINES switch. A fresh placement
    // therefore shows its circle the moment custom price turns on, and it
    // stays through every toggle. The 98g latch survives only as the armed
    // click-flow state (first click asks, second commits). Hide-all still
    // hides it.
    bool show = g_customPriceLineCreated &&
                !IsIndicatorHidden() &&
                g_thStartPointType == TH_START_POINT_CUSTOM_PRICE;
    if(!show)
    {
        HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
        return;
    }
    double price = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(!(price > 0.0) || !MathIsValidNumber(price))
    {
        HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
        return;
    }
    // the circular drag handle, centred on the line at the screen's middle
    HandsetHandleAt(g_cpMarkerName, price, CP_HANDLE_RES);
    // P-UI-98p: the line is never painted, so its circle carries the hover
    // text in both states. Guarded: one string compare, a write only on drift.
    {
        static string s_cpMarkTip = "";
        string tip = g_cpLineArmed
            ? "Custom price: drag the green circle - click to commit, double-click re-arms"
            : "Custom price (set) - double-click to re-activate";
        if(s_cpMarkTip != tip)
        {
            s_cpMarkTip = tip;
            ObjectSetString(0, g_cpMarkerName, OBJPROP_TOOLTIP, tip);
        }
    }
}

// P-UI-98d v2: the ride channel. A pan, a zoom or a window resize moves the
// price scale under the handles — the same stream the leg meter's discs ride
// (P-LM-16b): every MOUSE_MOVE / CHART_CHANGE re-projects, guarded (a still
// chart costs reads only, a write lands only on drift). The step-1 prices are
// the render's own answers, stashed by the face owner — and OUTSIDE the
// custom-price mode the stash is a stale answer, so the red handles park (a
// resurrected handle over a mode that no longer owns a ladder is the bug).
void HandsetMarkersRide()
{
    CustomPriceMarkerSync();
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE)
    {
        HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
        HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
        return;
    }
    // P-UI-98e: the icon belongs to the ARMED pair: the price stash now also
    // carries a SET handle's address (the click contract needs it), so the ride
    // is what must not resurrect an icon over a line nothing can grab.
    // P-UI-98l: and the ride obeys the LINES switch and the hide-all state
    // like every other marker owner (CustomPriceMarkerSync, the face owner) -
    // without these terms the L key parked the circles through the render and
    // the very next mouse move put them back («لاین خاموش میکنم دایره هاش
    // میمونه»).
    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0 && g_linesVisible && !IsIndicatorHidden())
        HandsetHandleAt(S1MarkName(1), g_s1MarkAbovePrice, S1_HANDLE_RES);
    else
        HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkBelowPrice > 0.0 && g_linesVisible && !IsIndicatorHidden())
        HandsetHandleAt(S1MarkName(-1), g_s1MarkBelowPrice, S1_HANDLE_RES);
    else
        HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
}

// P-UI-98e: A FRESH PLACEMENT IS BORN ARMED. The activation (the C key, the ring
// PIN) deletes the line and creates a new one at the screen's middle; the
// armed/set state is per PLACEMENT (P-UI-98d), so the new one must wake
// draggable even when the user had SET the previous line — otherwise the very
// first gesture on the fresh line is refused, and «قابل درگ کردن نیستش» returns
// for a second reason (the state, not the drag channel). ONE owner, called by
// both activation paths, so the two can never disagree about what "fresh" means.
void HandsetPlacementArm()
{
    g_cpLineArmed  = true;
    g_s1LinesArmed = true;
    g_cpSetPending = "";   g_cpSetPendingMs = 0;
    g_s1SetPending = "";   g_s1SetPendingMs = 0;
    // P-UI-98m: no re-arm candidate survives into a fresh placement.
    g_cpClickArmed = false;   g_cpClickY = 0;
    // P-UI-98g: a fresh placement is born ARMED but HIDDEN - the circles are the
    // answer to a click, and nothing has been clicked yet. The tooltip says so.
    g_cpHandleShown = false;
    g_s1HandleShown = false;
}

// The ONE owner of an armed/set TRANSITION of the custom price line. Guarded
// writes: never mid-gesture (P-BK-15), never on drift.
void CustomPriceLineOwnArm(const bool armed)
{
    // P-UI-101 (2026-09-22): A LOCKED LINE NEVER ARMS. The lock's promise is
    // «nothing moves it until I say so», and every way of grabbing this line runs
    // through this flag — the claim asks it first (P-UI-98d), the creator
    // publishes it as SELECTABLE, the double-click re-arm sets it. So the lock is
    // enforced HERE, in the one owner of the state, and not in a copy of the test
    // at each of those three places. (`want`, not `armed`: the parameter is const
    // by this function's own signature, and a lock is a REFUSAL, not a rewrite of
    // what the caller asked for.)
    bool want = (armed && !g_customPriceLocked);
    g_cpLineArmed = want;
    g_cpSetPending = "";
    g_cpSetPendingMs = 0;
    if(!g_customPriceLineCreated) return;
    if(g_customPriceLineDragging || g_customPriceNativeDrag) return;
    if((bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE) != want)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, want);
    if(!want) ClearCustomPriceSelection();
    // P-UI-98p: the mask is re-asserted, never lifted - the line is never
    // painted (see the creator), the green circle is the placement.
    if(ObjectFind(0, g_customPriceHorizontalLineName) >= 0 &&
       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    UpdateCustomPriceTooltip();   // the wording follows the state
    CustomPriceMarkerSync();
}

// P-UI-101 (2026-09-22) — THE PLACEMENT'S OWN LOCK, ONE OWNER.
//
// User order: «روی خط کاستوم پرایس که هولد کردم پنل تنظیماتش بازه بشه و بشه از
// اونجا قفلش کرد». The lock is not the armed/set state (P-UI-98d): SET is one
// click away from being undone (a double-click re-arms it), while the lock is
// released only from the panel. It is persisted with the placement, because the
// placement survives a re-attach and a lock that did not would be a lie after
// every recompile.
//
// The transition writes through the state owners, never around them: the armed
// owner (which is also the ONE enforcement point — see its own note) and the
// tooltip. A locked line is inert exactly like a SET one, so every law this
// project already measured for SET — no claim, no selection, no carry, no ride
// along with any foreign gesture — holds for it unchanged.
void CustomPriceLineOwnLock(const bool locked)
{
    if(g_customPriceLocked == locked) return;   // never write a state you would not change
    g_customPriceLocked = locked;
    CustomPriceLineOwnArm(!locked);             // locked = inert · unlocked = draggable again
    RuntimeSettingsSaveOverridesThrottled();    // the placement's lock outlives the session
}

//==============================================================================
// P-UI-98m — RE-ARMING A MASKED (SET) CUSTOM PRICE LINE (2026-09-22).
//
// User order: «وقتی سلکت نیس فقط همون دایره سبز بمونه ... خطو نشون نده».
// A masked line fires no OBJECT_CLICK, so the line's own click contract (which
// lives on that event) cannot wake it. The press edge still sees the row -
// CustomPriceGrabAt reads the object, masked or not - so the SET click is one
// owner reached from three edges, the step-1 shape: our own press/release
// pair on the mouse stream, the button-up finalize below (a motionless
// release emits no MOUSE_MOVE, P-BK-03), and the green circle's own
// OBJECT_CLICK. One physical click can reach it twice; a 60 ms twin guard
// drops the second. A single click here is a no-op (already set) and only a
// double re-arms, so no sweep slot is needed - the first click of a double
// can never commit anything.
//==============================================================================
void CustomPriceRearmClickAt()
{
    if(g_cpLineArmed) return;   // armed clicks belong to the line's own contract
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return;
    if(!g_customPriceLineCreated || ObjectFind(0, g_customPriceHorizontalLineName) < 0)
    {
        g_cpClickArmed = false;
        return;
    }
    uint now = GetTickCount();
    if(g_cpClickHandledMs != 0 && now - g_cpClickHandledMs < 60) return;   // the same click's twin event
    g_cpClickHandledMs = now;
    bool dbl = (g_cpClickLastMs != 0 && now - g_cpClickLastMs < DOUBLE_CLICK_THRESHOLD_MS);
    g_cpClickLastMs = now;
    if(!dbl) return;
    CustomPriceLineOwnArm(true);
    g_cpHandleShown = true;
    CustomPriceMarkerSync();
    ThrottledChartRedraw();
}

// The button-up that carries no move (P-BK-03): a motionless press/release on
// the SET line's row is a click, and only a double of those re-arms.
void CustomPriceRearmFinalize()
{
    if(!UILeftButtonUp()) return;   // the press's own echo (P-UI-73): keep the row for the real release
    if(!g_cpClickArmed) return;
    g_cpClickArmed = false;
    CustomPriceRearmClickAt();
}

// The double-click window's own sweeper: a single click that stayed single
// commits the SET here. Skipped while ANY handset gesture is live — the click
// that opened a drag must not set the line under the user's hand.
void HandsetClickSweep()
{
    uint now = GetTickCount();
    // P-UI-98h: a COMMIT happens with the button FREE. Both click transports
    // can arrive on the PRESS, so a pending slot may be waiting while the user
    // is still holding - the probe keeps it pending instead of committing a
    // SET under a hand that has not let go yet (and may still drag).
    if(g_cpSetPendingMs != 0 && now - g_cpSetPendingMs >= DOUBLE_CLICK_THRESHOLD_MS
       && UILeftButtonUp())
    {
        g_cpSetPendingMs = 0;
        g_cpSetPending = "";
        if(g_cpLineArmed)
        {
            CustomPriceLineOwnArm(false);
            g_cpHandleShown = false;   // P-UI-98g: SET takes the green circle away
            CustomPriceMarkerSync();
        }
    }
    if(g_s1SetPendingMs != 0 && now - g_s1SetPendingMs >= DOUBLE_CLICK_THRESHOLD_MS
       && UILeftButtonUp())
    {
        g_s1SetPendingMs = 0;
        g_s1SetPending = "";
        if(g_s1LinesArmed && !g_s1DragLive)
        {
            g_s1LinesArmed = false;   // SET: the factor stays, the ladder keeps the step
            g_s1HandleShown = false;  // P-UI-98g: nothing points at a set line
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);   // the face owner re-owns selectability + parks the dot
        }
    }
}

//==============================================================================
// P-UI-53 — THE DRAG OWNS THE VIEW UNTIL THE RELEASE.
//
// Reported: "while dragging, the chart behind scrolls/pans and the drag breaks -
// lock or prepare the chart during the drag". The line's movement is MT4's own
// native object drag; the chart underneath stays live, so a gesture that wanders
// past the line - and CHART_MOUSE_SCROLL is ENABLED BY DEFAULT - pans the view.
// The price scale then slides under the cursor and MT4 answers the pan by moving
// the dragged object against a rebased price: the line jumps, the drag dies, or
// it never engages at all. BaseKnot already lives with this and solved it
// (`BaseKnotLockChart` + P-BK-14 "the drag owns the view until release"), with RAW
// Chart* calls so the Lite build compiles without the UI module. This is the same
// lock, same shape, for the line, in the same domain layer.
//
// P-UI-90 (2026-09-15) superseded the fourth bullet's "remembers what the user
// had" and the sentence that closed this block: the capture moved to ONE owner,
// because four private copies of it (this one, BaseKnot's, the panels' and the
// watchdog's) read the props while somebody ELSE held the lock and recorded our
// own `false` as the user's - so the last release wrote `false` back and the
// chart stayed scroll-locked until re-attach, and after Remove too. The lock's
// SHAPE is unchanged: the grab takes it, every throttled step re-asserts it, the
// button-up hands it back, the watchdog heals a release that never arrived, and
// OnDeinit releases it for EVERY reason. Only the bookkeeping moved.
//
// Four owners keep it honest:
//   * the GRAB takes it (once per gesture; `ChartViewLockAcquire` remembers what
//     the user had, and only at the moment NO owner holds the lock);
//   * every throttled drag step RE-ASSERTS it - read-guarded, a write only on
//     drift, because third writers (a panel closing, a watchdog restore, a
//     template reset) can flip the props back while the button is still down;
//   * the BUTTON-UP releases it (`ChartViewLockRelease` restores the user's pair,
//     and only on the LAST release - never a blind true);
//   * a watchdog heals a release that never arrived (off-window release, lost
//     focus): the P-BK-03 trap - no mouse move, so no release event either.
// CHART_AUTOSCROLL is held down too while we own the view: a tick sliding the
// scale mid-drag moves the line with it (BaseKnot makes the same call).
// OnDeinit releases it for EVERY reason (`ChartViewLockForceRelease` is the net),
// so a stale lock can never outlive the instance.
//==============================================================================
static bool s_cpChartLocked = false;
// P-UI-90: this owner no longer SAVES the scroll / context-menu pair. Its own
// capture could be taken while the Base/Knot tool (or the panels) already held
// the lock, so it recorded OUR `false` as "what the user had" and wrote it back
// on release - one of the four writers behind the chart that stayed scroll-locked
// for the life of the terminal. `ChartViewLock*` (GlobalVariables) is the single
// owner of that capture/restore now; AUTOSCROLL stays here because nothing else
// ratchets it (both writers only restore what they saw).
static bool s_cpAutoWas     = true;
static uint s_cpLockActMs   = 0;       // last activity of the owning gesture

bool CustomPriceDragLocked() { return s_cpChartLocked; }

void CustomPriceDragLockOn()
{
    if(!s_cpChartLocked)
    {
        s_cpAutoWas   = (ChartGetInteger(0, CHART_AUTOSCROLL) != 0);
        s_cpChartLocked = true;
        ChartViewLockAcquire();   // P-UI-90: scroll + context menu have ONE owner
    }
    else ChartViewLockAssert();
    if(s_cpAutoWas && (ChartGetInteger(0, CHART_AUTOSCROLL) != 0))
        ChartSetInteger(0, CHART_AUTOSCROLL, false);
    // P-UI-106 (2026-09-23): CHART_CONTEXT_MENU is a stub on this build
    // (CTXMENU-OFF) - writing it costs a repaint for zero effect, so it is
    // not written any more.
    s_cpLockActMs = GetTickCount();
}

void CustomPriceDragReassertLock()
{
    if(!s_cpChartLocked) return;
    s_cpLockActMs = GetTickCount();
    ChartViewLockAssert();   // P-UI-90: read-guarded, one owner for scroll + ctx
    if(s_cpAutoWas && ChartGetInteger(0, CHART_AUTOSCROLL) != 0)
    { ChartSetInteger(0, CHART_AUTOSCROLL, false); }
    // P-UI-106: stub write retired (see CustomPriceDragLockOn above).
}

void CustomPriceDragLockOff()
{
    if(!s_cpChartLocked) return;
    ChartViewLockRelease();   // P-UI-90: hands the view back only when NO owner is left
    if(s_cpAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, true);
    s_cpChartLocked = false;
}

// The P-BK-03 net (shape: BaseKnotSyncBadges' own stale-drag heal): a press whose
// release emits NO mouse move cannot be ended by the gesture path, so the lock (and
// the gesture flags) are healed here once the button is provably up and nothing has
// moved for 1.5 s. Cost in steady state: the caller reads one bool; the KEYSTATE
// probe runs only while a lock is actually held.
void CustomPriceDragHealStale()
{
    if(!s_cpChartLocked) return;
    if(GetTickCount() - s_cpLockActMs <= 1500) return;                     // a live drag keeps producing events
    if(!UILeftButtonUp()) return;             // still holding the button (one owner, P-UI-73)
    CustomPriceDragLockOff();
    g_customPriceLineDragging = false;
    g_customPriceDragOwn = false;
    // P-UI-98: a step-1 gesture whose release never arrived heals the same way —
    // the flags drop and the handle's selection goes (a stuck g_s1DragLive would
    // pin the handle's price forever, since the render skips its writes while the
    // flag is up). No forced frame here: the owed-frame machinery and the next
    // natural frame re-assert the picture.
    if(g_s1DragLive)
    {
        g_s1DragLive = false;
        // P-UI-98e: the carry's own state heals with the gesture's flags - a
        // live g_s1OwnActive on a healed drag would keep the held-move pass
        // reading a cursor that is no longer dragging anything. P-UI-98f: it is
        // the SAME owner the settle uses - this path used to leave the echo
        // stamp's base and the press baseline behind, and the next gesture read
        // them as its own.
        Step1GestureStateClear();
        // P-UI-98e: the borrow heals with the gesture - the face owner's next
        // frame writes the truthful flag (armed means grabbable).
        g_s1OwnBorrowed = false;
        // and a press whose release was lost is a GESTURE, never a click: the
        // candidate dies here so no later CHARTEVENT_CLICK can SET the line the
        // user had been dragging.
        g_s1ClickRow = "";
        string s1HealName = g_s1DragName;
        g_s1DragName = "";
        if(s1HealName != "" && (bool)ObjectGetInteger(0, s1HealName, OBJPROP_SELECTED))
            ObjectSetInteger(0, s1HealName, OBJPROP_SELECTED, false);
    }
}

//==============================================================================
// P-UI-98j — THE STEP-1 PAIR HEALS ITSELF (2026-09-22).
//
// Reported: «بعضی وقتا این خطش ناپدید میشه step و دیگه نمیشه جابجاش کرد ...
// تایم بالا میریم دوباره درست میشه». The shape is exact: a stashed handle
// whose OBJECT is gone. The stash - and the red circle riding it - survives,
// the claim refuses (ObjectFind < 0, P-UI-98e), and nothing re-creates the
// line: steady-state frames are sealed by the geometry signature (the levels
// block only runs on `g_redrawTHLevelsNeeded || g_buildStage != 0`), and the
// external-delete self-heal in OnChartEventHandler only fires when the delete
// event is NOT suppressed - a delete landing inside our own 250 ms
// post-delete suppression window is ignored, the cache keeps vouching for a
// name the chart no longer carries, and the picture stays wrong until
// something unrelated rebuilds (a TF switch does it for real: OnInit bumps
// the epoch, resets the absent table and rebuilds the whole family).
//
// The net is this function, called from the tick path beside
// CustomPriceDragHealStale (throttled to S1_HEAL_MS; reads-only while
// healthy): in custom-price mode, armed, same-TF stash, no live gesture and
// no rebuild in flight, a stashed handle whose price sits inside the RAW
// visible window but whose object is gone arms the delete branch's own two
// lines (redraw flag + generation bump) - an in-place re-assert, never a
// wipe. The raw window (not the ±25% cull window) is the proof the line must
// be painted: anything on screen is inside every cull window by construction
// (P-PERF-04's margin covers the hysteresis band), so a correctly culled
// off-screen line can never trip it, and a line the build legitimately
// dropped has no stash to trip it with.
//==============================================================================
#define S1_HEAL_MS 2000
void Step1HandleHealMissing()
{
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return;
    if(!g_s1LinesArmed || g_s1DragLive) return;
    if(IsIndicatorHidden() || !g_linesVisible) return;
    if(g_s1MarkPeriod != Period()) return;
    if(g_buildStage != 0 || g_forceClearOnNextDraw) return;
    static uint s_s1HealLastMs = 0;
    uint now = GetTickCount();
    if(s_s1HealLastMs != 0 && now - s_s1HealLastMs < S1_HEAL_MS) return;
    s_s1HealLastMs = now;
    double wMax = WindowPriceMax();
    double wMin = WindowPriceMin();
    if(!(wMax > wMin)) return;   // no window known: do not guess
    bool missing = false;
    if(g_s1MarkAboveName != "" && g_s1MarkAbovePrice >= wMin && g_s1MarkAbovePrice <= wMax &&
       ObjectFind(0, g_s1MarkAboveName) < 0)
        missing = true;
    if(!missing && g_s1MarkBelowName != "" && g_s1MarkBelowPrice >= wMin && g_s1MarkBelowPrice <= wMax &&
       ObjectFind(0, g_s1MarkBelowName) < 0)
        missing = true;
    if(!missing) return;
    // A stashed handle the chart should paint but does not carry: the stored
    // geometry no longer describes the chart, so the next frame rebuilds for
    // real and the render re-creates it in place. No wipe - a wipe answers a
    // topology change, never a hole.
    g_redrawTHLevelsNeeded = true;
    MarkDrawGeneration();
}

// P-UI-49: the ONE owner of the line's drag TOOLTIP TEXT. It used to be written
// in the drag handler itself, i.e. on EVERY step of a native drag - and MT4
// CANCELS an in-progress native drag when the dragged object is rewritten
// mid-gesture (P-BK-15's rule, learned on the BaseKnot box: the pump "snapped
// the box back to the drag start"; the level-family follow obeys it too -
// "never a full Sync per step, its style/tooltip rewrites lagged children behind
// the native BOX"). While the line was created pre-SELECTED the movement came
// from the SELECTION (MT4 moves every selected object on each mouse-move), so
// that write was invisible; the moment P-UI-45/48 moved the movement onto the
// PER-OBJECT native drag it cancelled the very gesture it was decorating and the
// line stopped following the cursor - the reported "the custom price line cannot
// be dragged". So the line is written ONCE per gesture, from the release, and
// NOTHING touches it while the button is down. Cost: fewer writes than before
// (one per gesture instead of one per drag step), no per-frame work.
void UpdateCustomPriceTooltip()
{
    if(!g_customPriceLineCreated) return;
    // P-UI-98g: the wording follows the state the user is actually in — an armed
    // line whose handle is not up yet asks for the click that brings it up.
    string text = g_waitingForCustomPriceClick
                  ? "Current price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Double-click to confirm"
                  : (g_cpLineArmed
                     ? (g_cpHandleShown
                        ? "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Drag the green handle, click to commit"
                        : "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Click it to bring up the green handle")
                     : "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Set. Double-click to re-arm");
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, text);
}

// P-UI-49c: the gesture's own bookkeeping. `s_ownGrabPrice` is the line's price
// when the grab started and `s_ownLastWrite` the last price WE wrote; they are
// what tells a working native drag (the terminal's price moves on its own - we
// then touch nothing, P-BK-15) from a frozen one (it does not - we carry it).
static double s_ownGrabPrice = 0.0;
static double s_ownLastWrite = 0.0;

// P-UI-100b (2026-09-22): THE DRAW THAT LOOKED LIKE A GRAB.
//
// A press that lands ON the custom price line is claimed by us and P-UI-49d
// hands the movement to the terminal - correct for a GRAB, wrong for a DRAW: with
// MT4's fib tool armed, the same press starts a fib and the line we just selected
// is carried to the fib's other end («وقتی فیو یا باکس از همون محل میکشم کاستوم
// پرایس جابجا میشه»). At the press the two are indistinguishable, so the answer
// is the OUTCOME, and the outcome is an OBJECT: a gesture of ours never CREATES
// one, and the terminal's own drawing tools always do. Two witnesses, both fed by
// the one detector in OnChartEventHandler:
//   * `s_cpForeignDrawUntil` — the WINDOW a foreign create opens. The claim asks
//     it at the press edge: a draw that was already under way (MT4 creates a
//     drawn object on the press) is refused before it can move anything at all.
//   * `s_drawNotGrab`     — THIS GESTURE is a draw, not a grab. Set only while a
//     claim of ours is live; it stands the carry down and the release puts the
//     line back. ONE flag for BOTH hand-set lines: a claim of the step-1 pair and
//     a claim of the custom price line are mutually exclusive (one cursor, one
//     gesture — the step claim runs first and the other yields), so there is never
//     a second gesture for it to describe, and each settle clears it.
static uint s_cpForeignDrawUntil = 0;   // the deadline a foreign create opens
static bool s_drawNotGrab      = false;  // the live gesture turned out to be a draw
#define CP_DRAW_WITNESS_MS 600       // how long a foreign create disqualifies a claim

// P-UI-55: THE PRESS LATCH FOR OUR OWN CARRY, IN PIXELS.
//
// Reported with two screenshots: "I CLICK the line - I did not move it - and every
// level lands somewhere else: 1.15697 becomes 1.15705." Eight points on a 5-digit
// chart is ~1.6 px, which is the hit tolerance itself. The carry used to be
// ABSOLUTE TO THE CURSOR and it engaged on ANY button-down mouse move after the
// press edge, so the one-pixel jitter of a CLICK was enough to hand the line the
// cursor's price: the press had landed ~2 px off the line (exactly what
// CustomPriceGrabAt tolerates as "on the line") and that offset was copied onto the
// PRICE. The user did not move anything on purpose, yet the line's price changed -
// and every level, which is derived from that price, moved with it. A price that
// changes without the user moving something is the "the levels are not reliable"
// bug, so the carry is fenced by the two rules the BaseKnot box already uses:
//   * SLOP: only a gesture that has actually TRAVELLED may drive the line, and an
//     HLINE can only be moved along Y - so a click's jitter can never pass, and a
//     click is honest: the price does not change at all.
//   * DELTA from the press latch, never absolute-to-cursor: the press offset is
//     preserved (the line follows the mouse exactly like MT4's own drag does) and
//     the movement can never snap the line onto the cursor.
static int    s_ownGrabX = 0;             // cursor pixel at the grab
static int    s_ownGrabY = 0;
static double s_ownGrabCursorPrice = 0.0; // price under that pixel at the grab
#define CP_DRAG_SLOP 3                    // px of vertical travel before it is a DRAG (P-UI-96: was 6; 6px ate precise nudges on coarse charts, clicks still filter via !pressEdge + jitter < 3px)
// P-UI-99-OFF (2026-09-21, user order): CP_HOLD_MS / CP_HOLD_MOVE (the 500 ms
// hold-to-arm beat, P-UI-97) are retired — the line's claim is immediate, the
// select/deselect pair carries the comfort instead. Restore is a git revert of
// the claim block, not a rewrite.

// P-UI-49c/P-UI-50: did the press at (x,y) land on the line? ONE conversion, the
// one already proven to work in this codebase (ChartXYToTimePrice - the panels and
// the carry below use it), never one per move: the answer only decides WHO owns the
// gesture. The first version converted the LINE to a pixel with
// ChartTimePriceToXY(0, 0, 0, ...) and MT4 REFUSES that call with time = 0, so the hit
// test could never fire at all (zero "grab hit-test" lines in a whole session of
// drags) and the drag lived or died by the terminal's own pick-up. Now the cursor's
// price is compared against the line's, with the tolerance expressed in PIXELS
// through the very price-per-pixel the chart is drawn at: the line as drawn plus a
// few pixels, i.e. what the terminal itself uses - a normal press grabs the line, a
// press clearly away still pans the chart.
bool CustomPriceGrabAt(const int x, const int y)
{
    if(!g_customPriceLineCreated) return false;
    double linePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(linePrice <= 0) return false;
    int subW = 0; datetime cursorT = 0; double priceAtCursor = 0.0;
    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, priceAtCursor)) return false;
    int heightPx = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    double span = WindowPriceMax() - WindowPriceMin();
    if(heightPx <= 0 || span <= 0) return false;
    // P-UI-98q: the tolerance covers the visible affordance - the 19 px green
    // circle, not the unpainted line under it.
    int tolPx = (int)inpCustomPriceLevelWidth + 4 + (CP_HANDLE_HALF - HANDSET_HANDLE_HALF);
    if(tolPx < 5) tolPx = 5;
    double tolPrice = span * ((double)tolPx / (double)heightPx);
    return (MathAbs(linePrice - priceAtCursor) <= tolPrice);
}

//| Helper function to hide all TH objects (DRY)                     |
//|                                                                  |
//| Centralized hide logic to avoid code duplication                 |
//| Used by: OnInit, RedrawAllObjects, F key handler                 |
//| COVERS: TH levels, labels, zones, mode labels, custom price      |
//+------------------------------------------------------------------+
// P-PERF-02: hide is a STATE, not a per-frame action. RedrawAllObjects calls
// HideAllTHObjects() from its hidden early-exit on every heavy frame, so the
// old code walked every chart object and wrote a mask on every hit for as long
// as the indicator stayed hidden (the whole point of the F key). Nothing can
// re-show those objects while we are hidden, so the pass runs once per hide
// transition; ResetHideAllState() re-arms it from every path that can show
// objects again (F key show branch, OnInit, OnDeinit).
static bool g_hideAllApplied = false;

void ResetHideAllState() { g_hideAllApplied = false; }

void HideAllTHObjectsPass()
{
    // P-PERF-31: the walk lives in the visibility owner and follows the
    // object cache (only our objects, zero ObjectName calls over foreign
    // chart objects, zero type probes — hiding needs no classification).
    // A fresh instance with a cold cache falls back to one legacy chart
    // scan for the previous instance's leftovers; steady state never scans.
    VisibilityHideAllCached();
    // PERF: Batch special label hide - ObjectSetInteger is no-op if object doesn't exist
    long noPeriodsVal = OBJ_NO_PERIODS;
    ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
#endif
    ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    if(g_customPriceLineCreated)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    // P-UI-98d: the handset handles hide with everything else (F key). They are
    // screen-pixel BITMAP_LABELs — no TF mask applies — so they PARK off-window;
    // the next sync (ride channel / face owner) re-places them on the show path.
    HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
    HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
    HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
    // NOTE: ABCD pattern objects are NOT hidden by F key
}

// Returns true when this call performed the (once per transition) pass.
bool HideAllTHObjects()
{
    if(g_hideAllApplied) return false;
    g_hideAllApplied = true;
    HideAllTHObjectsPass();
    // Written outside the visibility guard → invalidate every stored mask.
    BumpTfEpoch();
    return true;
}

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
    TH3PivotMarkersClear();     // P-TH3-P6: our chart namespace leaves with us (UI half — P-BUILD-01)
#endif
    BaseKnotOnDeinit(reason);   // P-BK-02: never leave scroll locked / ghost preview behind
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
        ObjectsDeleteAll(0, "TH3_MP_");            // P-TH3-P6e: mother-pivot overlay (own prefix)
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

        // Delete TH labels
        ObjectDelete(0, inpObjectPrefix + "TH_Title");
        for(int i = 0; i < ArraySize(tfLabels); i++) {
            ObjectDelete(0, inpObjectPrefix + "TH_" + tfLabels[i]);
            ObjectDelete(0, inpObjectPrefix + "TH_Steps_" + tfLabels[i]);
            ObjectDelete(0, inpObjectPrefix + "TH_Targets_" + tfLabels[i]);
        }

        string symbolName = GetCachedSymbol();
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

//| Get adaptive level counts (matching MT5: simple single inpMaxLevels) |
//+------------------------------------------------------------------+
void GetAdaptiveLevelCounts(int &maxAbove, int &maxBelow)
{
    maxAbove = inpMaxLevels;
    maxBelow = inpMaxLevels;
    if(maxAbove > MAX_SAFE_LEVELS) maxAbove = MAX_SAFE_LEVELS;
    if(maxBelow > MAX_SAFE_LEVELS) maxBelow = MAX_SAFE_LEVELS;
    if(maxAbove < 1) maxAbove = 1;
    if(maxBelow < 1) maxBelow = 1;
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

    if(dailyClosePrice == s_lastDailyClose &&
       currentTF == s_lastTF &&
       g_thStartPointType == s_lastStartPointType &&
       (g_thStartPointType != TH_START_POINT_CUSTOM_PRICE || g_customTHStartPrice == s_lastCustomPrice) &&
       inpMaxLevels == s_lastMaxAbove &&
       inpMaxLevels == s_lastMaxBelow &&
       MathAbs(currentScalingFactor - s_lastScalingFactor) < EPSILON_GENERAL &&
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
    data.thValue = GetAdaptedStepSize(data.thValue);

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
    s_lastMaxAbove = inpMaxLevels;
    s_lastMaxBelow = inpMaxLevels;
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

bool HeavyFramePending() { return g_heavyFramePending; }

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
        if(s_lastForcedRedrawMs != 0 && nowMs - s_lastForcedRedrawMs < 20) return;
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
    bool hasPendingWork = (force_redraw || g_labelsRelayoutNeeded || g_redrawTHLevelsNeeded || historicalRefreshDue || basePriceBoundary || g_buildStage != 0 || g_heavyFramePending);
    
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

    string s_cachedSymbol = GetCachedSymbol();
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
        g_redrawTHLevelsNeeded = true;
        g_calculatedOnce = false;
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
            g_thStartPointType = inpTHStartPointType;
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
        frameCore = levelSig + levelLookSig + "|" +
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
                          DoubleToString(vpTop, s_cachedDigits) + "|" +
                          DoubleToString(vpBottom, s_cachedDigits) + "|" +
                          IntegerToString(IsIndicatorHidden() ? 1 : 0) +
                          IntegerToString(IsTriggerLevelsEnabled() ? 1 : 0) +
                          IntegerToString(g_customPriceLineDragging ? 1 : 0) +
                          IntegerToString(inpShowPipDistanceLabels ? 1 : 0);
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
            // Advance the rebuild; the LABELS stage only arms the labels block
            // below (it is stage 4 of the same sequence).
            if(g_buildStage == BUILD_STAGE_LINES)            g_buildStage = BUILD_STAGE_ZONES;
            else if(g_buildStage == BUILD_STAGE_ZONES)       g_buildStage = BUILD_STAGE_LABELS;
            else if(g_buildStage == BUILD_STAGE_LABELS) { g_buildStage = BUILD_STAGE_BLOCK; g_labelsRelayoutNeeded = true; }
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
    CheckAlerts(objectPrefix, g_currentPrice);
    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| OnCalculate Handler (matching MT5: tick throttle + cache inv.)   |
//+------------------------------------------------------------------+
//==============================================================================
// P-PERF-04 EVENT BUDGET — measure the paths the user FEELS
//
// P-PERF-02/03 instrumented the TICK path, which is why its fixes were real but
// incomplete: the complaints that survived were about INTERACTION — working
// with the chart, with the panel, and switching timeframe. None of those paths
// had a single line of measurement, so they could only be guessed at. These two
// helpers turn the next report into a named phase too. They log AT MOST one
// line per 2 s and only when the budget was blown, so the fast path pays one
// GetTickCount subtraction.
//==============================================================================
#define P_P4_EVENT_WARN_MS  40    // one chart event (chart handler + UI handler)
#define P_P4_INIT_WARN_MS   150   // attach / timeframe switch (OnInit+OnDeinit)
#define P_P4_MOVE_WARN_MS   20    // P-PERF-15: one cursor-move pass (ring + panel + hold)
#define P_P4_CLICK_WARN_MS  20    // P-PERF-26: one object-click pass (button + panel + apply)
static uint s_p4LogGateMs = 0;

// P-PERF-26: THE LEDGER WAS UNREADABLE, AND THAT COST A WHOLE CYCLE.
//
// Every perf line printed the raw chart-event id, so the reader had to REMEMBER
// what "id=1" meant. The project's own record shows the price of guessing: the
// 485-578 ms spikes were filed as "the cursor-move path" (P-PERF-15/16 notes),
// and the fix was aimed at hover work - while the constant is actually
// CHARTEVENT_OBJECT_CLICK. Measured, not recalled: the MQL4 compiler itself was
// asked (case-value collision probe) and reports
//   KEYDOWN=0 OBJECT_CLICK=1 OBJECT_DRAG=2 OBJECT_ENDEDIT=3 CLICK=4
//   OBJECT_DELETE=6 CHART_CHANGE=9 MOUSE_MOVE=10
// so id=1 is a BUTTON PRESS on the ring/panel - i.e. exactly the
// "toggling a switch takes half a second" the user reports - and no id=10 line
// exists because hover work is cheap. The ledger now prints the name next to
// the number, so the next report cannot be mis-read.
string P4EventName(const int id)
{
    if(id == CHARTEVENT_KEYDOWN)        return "KEYDOWN";
    if(id == CHARTEVENT_OBJECT_CLICK)   return "OBJ_CLICK";
    if(id == CHARTEVENT_OBJECT_DRAG)    return "OBJ_DRAG";
    if(id == CHARTEVENT_OBJECT_ENDEDIT) return "OBJ_ENDEDIT";
    if(id == CHARTEVENT_CLICK)          return "CLICK";
    if(id == CHARTEVENT_OBJECT_DELETE)  return "OBJ_DELETE";
    if(id == CHARTEVENT_CHART_CHANGE)   return "CHART_CHANGE";
    if(id == CHARTEVENT_MOUSE_MOVE)     return "MOUSE_MOVE";
    return "UNKNOWN";
}

void P4ReportSlow(const string what, const uint ms, const uint budget)
{
    if(ms < budget) return;
    uint now = GetTickCount();
    if(s_p4LogGateMs != 0 && now - s_p4LogGateMs < 2000) return;
    s_p4LogGateMs = now;
    _LOG_GATE_W Print("[W][PERF] ", what, " took ", (int)ms, "ms (budget ", (int)budget, "ms)");
}

string P4MsTag(const uint ms) { return IntegerToString((int)ms); }

//==============================================================================
// P-PERF-32 — ONE OWNER FOR THE STRUCTURE SWITCHES (card 11 rows 1-6)
//
// The master / L1-L5 switches change NO geometry (the level SET is
// switch-invariant; they only choose zone colours), yet they rode
// REFRESH_BUFFERS into a full RedrawAllObjects: geometry-key miss,
// whole-family recompute and re-assert, overrides flush — inside the click.
// On a weak PC the press felt dead. So the switch never reaches the render:
// the owner sets the state, persists the OV_ key (P-UI-02: REFRESH_NONE rows
// must save explicitly), repaints the recoloured zones via
// StructureRecolourWalk, and forces the discrete-action repaint. Steady
// frames skip on the unchanged signature; the geometry key keeps the switch
// terms, so any LATER real render recomputes with live switches and the
// walk can never desync it. idx: 0 = master, 1-5 = L1-L5.
//
// The settle step is shared with the batch (P-UI-66): a group press defers the
// walk + repaint to the end of the batch so one press still costs ONE of each.
//==============================================================================
static int s_structSwitchBatch = 0;   // >0 = a group press owns the settle

void StructureSwitchSettle(const uint p32t, const int idx, const bool visible)
{
   RuntimeSettingsSaveOverridesThrottled();
   int touched = StructureRecolourWalk();
   P4ReportSlow("structure toggle [idx=" + IntegerToString(idx) +
                " on=" + IntegerToString(visible ? 1 : 0) +
                " touched=" + IntegerToString(touched) +
                " cache=" + IntegerToString(CacheGetSize()) + "]",
                GetTickCount() - p32t, P_P4_MOVE_WARN_MS);
   RepaintForDiscreteAction();
}
void SetStructureVisible(const int idx, const bool visible)
{
   uint p32t = GetTickCount();
   if(idx <= 0)      g_showStructure = visible;
   else if(idx == 1) g_showStructureL1 = visible;
   else if(idx == 2) g_showStructureL2 = visible;
   else if(idx == 3) g_showStructureL3 = visible;
   else if(idx == 4) g_showStructureL4 = visible;
   else              g_showStructureL5 = visible;
   // P-UI-66: a GROUP press (the dual row's ALL cell) writes several switches in
   // ONE event. Every write must land - state, persisted OV_ key - but the walk
   // and the repaint are per PASS, not per switch: five switches meant five
   // recolour walks and five forced repaints for one press, which is the cost
   // P-PERF-32 exists to remove. The panel opens the batch, this owner defers,
   // and the batch's owner closes it ONCE.
   if(s_structSwitchBatch > 0) return;
   StructureSwitchSettle(p32t, idx, visible);
}

void StructureSwitchBatchBegin()
{
   s_structSwitchBatch++;
}

//--- close the batch: one persist, ONE recolour walk, one repaint - and the
//--- walk is unconditional (it reads the live flags, not this press's list), so
//--- any subset of switches is settled by it.
void StructureSwitchBatchEnd()
{
   if(s_structSwitchBatch > 0) s_structSwitchBatch--;
   if(s_structSwitchBatch > 0) return;
   StructureSwitchSettle(GetTickCount(), -1, false);
}

// P-PERF-10: named-phase report for the INIT path (attach / TF switch). The
// tick ledger cannot attribute OnInit's 3.2-4.1 s — it measures a frame, not
// the init sequence — so the entry passes its two halves and OnInitHandler
// leaves the four domain phases in globals.
string P4InitLedgerTag(const uint indMs, const uint uiMs)
{
    return " [ind=" + IntegerToString((int)indMs) +
           " ui=" + IntegerToString((int)uiMs) +
           " settings=" + IntegerToString((int)g_pInitMsSettings) +
           " hist=" + IntegerToString((int)g_pInitMsHistory) +
           " base=" + IntegerToString((int)g_pInitMsBase) +
           " atr=" + IntegerToString((int)g_pInitMsAtr) + "]";
}

//+------------------------------------------------------------------+
//| P-BK-46 — THE KNOT'S OWN EngSL: THE ASK / PUSH PAIR (one owner).   |
//|                                                                   |
//| The Base/Knot trade is measured in EngSL of the knot's OWN TF     |
//| (its base class), and EngSL is TRADE-PLAN MATH — TradePlanFormulas,
//| which sits ABOVE BaseKnotTool (the layer law, the same one P-BK-29's
//| movement step obeys). So the tool is never asked to read it here:  |
//| it SAYS which TFs its live boxes call their own, this layer       |
//| computes exactly those (TradePlanEngOf — the number the TRex       |
//| card's Eng.SL row shows, rounded to the same whole pips) and       |
//| pushes the pairs back, where the domain stores them and rebuilds   |
//| a knot's stop / target the moment one really moved.               |
//|                                                                   |
//| One ask per pump round (500 ms), no boxes = one TF (this chart's,  |
//| which is what the sizing preview uses), and every value comes from |
//| the SAME multi-TF ATR cache the strip and the trade block read, so |
//| a warm chart pays cache hits and compares.                        |
//|                                                                   |
//| P-BK-50 (2026-09-15) — THE PLAN'S TARGET LEGS RIDE THE SAME CALL.  |
//| One plan per TF answers BOTH numbers a knot draws: the risk        |
//| (`plan.eng` = EngSL, the very number the TRex card's Eng.SL row   |
//| prints: one decimal since P-TRADEPLAN-DEC, 2026-09-16) and the    |
//| targets (`plan.tp1..3` — the very numbers the corner row prints as  |
//| `#TP1+n #TP2+n #TP3+n`). So the box can never disagree with that    |
//| row about a target, and the tool is never asked to read ATR.       |
//|                                                                   |
//| P-BK-51 (2026-09-15) — AND SO DOES THE HUNTER LEG. The user's own   |
//| rule («و برای گره etr میشه به اندازه huntsl محل ورود») sizes an     |
//| ETR/CTR/OTR entry by ONE HuntSL, so `plan.hunter` — the leg the     |
//| TRex card prints as `Hunter SL:` — is pushed per TF beside EngSL.   |
//| The ask list grew with it: the ENTRY is read on the knot's own TF |
//| and the STOP on the node TYPE'S own time (P-BK-83 — one rung above |
//| the class for ETR, two for CTR, three for OTR), so that rung is    |
//| asked for as well                                                  |
//| (BaseKnotEngNeeds walks each box' own TF AND its measure TF).       |
//+------------------------------------------------------------------+
void BaseKnotEngPump()
{
   int      mins[BK_ENG_ROW_MAX];
   datetime anchors[BK_ENG_ROW_MAX];   // P-BK-79: the bar each row is read at (0 = the live row)
   double   pips[BK_ENG_ROW_MAX];
   double   hunts[BK_ENG_ROW_MAX];   // P-BK-51: HuntSL, the second measure a knot draws with
   double   tp1[BK_ENG_ROW_MAX];
   double   tp2[BK_ENG_ROW_MAX];
   double   tp3[BK_ENG_ROW_MAX];
   double   ab[BK_ENG_ROW_MAX];      // P-BK-92: that TF's TH points in PRICE units
   ArrayInitialize(ab, 0.0);      // explicit: the push below reads it for every `mins`
   int n = BaseKnotEngNeeds(mins, anchors);
   for(int i = 0; i < n && i < BK_ENG_ROW_MAX; i++)
   {
      // P-BK-50: ONE plan call feeds all four pushes (it computes the strip ATRs
      // this loop used to ask for), and a plan that is not warm pushes ZEROES — the
      // absence the tool then reports instead of drawing a guessed level.
      // P-BK-79: AND AT THE ROW'S OWN ANCHOR. `anchors[i]` is the box' `storyT` — the bar
      // its story ended on — so the ATRs, the EngSL, the Hunter leg and the three targets
      // are the ones THAT bar's market gave, not today's drifted ones («با گذشت زمان ممکن
      // 40 بشه یا 10 بشه»). 0 stays the live row the sizing preview asks for.
      STradePlan plan;
      if(!TradePlanCompute(mins[i], plan, anchors[i]))
      {
         pips[i] = 0.0; hunts[i] = 0.0; tp1[i] = 0.0; tp2[i] = 0.0; tp3[i] = 0.0;
         ab[i]   = 0.0;
         continue;
      }
      // P-TRADEPLAN-DEC (2026-09-16): the pushed risk is the CARD'S OWN NUMBER —
      // `plan.eng`, one decimal — not a second rounding of `engTrue`, so the box and the
      // `Eng.SL` row it is checked against cannot drift apart. A sub-pip size survives
      // the push (EURUSD M1: 0.3); only a TF the plan has no value for pushes 0, which
      // stays the tool's word for "never pushed" (BaseKnotEngPips).
      pips[i] = (plan.eng > 0.0 ? plan.eng : 0.0);
      // P-BK-51: HUNTSL RIDES THE SAME ROW — the very leg the TRex card prints as
      // `Hunter SL:`, which is what an ETR/CTR/OTR knot's entry waits for.
      hunts[i] = (plan.hunter > 0.0 ? plan.hunter : 0.0);   // P-TRADEPLAN-DEC: 0.1 pip, same rule
      tp1[i]  = (plan.tp1 > 0 ? (double)plan.tp1 : 0.0);
      tp2[i]  = (plan.tp2 > 0 ? (double)plan.tp2 : 0.0);
      tp3[i]  = (plan.tp3 > 0 ? (double)plan.tp3 : 0.0);
      // P-BK-75: AND THE SAME PLAN CARRIES THE MOVEMENT ABILITY. `plan.ownPips` is
      // THIS TF's composite ATR (TradePlanStripPips -> CalculateWeightedATR, the very
      // number the strip and the trade block read), so the knot's type is decided by
      // the SAME ATR the rest of the chart is drawn with — not a second reading that
      // could drift from it. Pips -> price here, because the knot's box is in prices.
      // P-BK-79: at THIS ROW'S anchor, so `plan.ownPips` is the anchored composite — the
      // same number the row's own EngSL was divided out of, and the number the box' type
      // is read against (BaseKnotAbilityGet at the same anchor).
      // P-BK-92: THE RUNG'S OWN TH CARRIES THE MOVEMENT ABILITY (P-BK-75's ATR
      // rule below, reversed per user: type + step read TH, plan stays ATR).
      ab[i] = THAbilityPrice(mins[i], anchors[i]);
   }
   BaseKnotEngPush(mins, anchors, pips, hunts, tp1, tp2, tp3, n);
   // P-BK-92: P-BK-75's block below now hands TH per TF (reversed per user).
   // P-BK-75 — THE NODE'S TYPE IS ITS HEIGHT AGAINST THE MOVEMENT ABILITIES OF ITS OWN
   // TF (user: «به جای th از atr استفاده بشه»), so the pump hands ONE number per TF in —
   // that TF's ATR — exactly as it already hands EngSL in: one row per TF the boxes
   // asked for, off the SAME `mins` list, so the ask and the answer cannot disagree
   // about which TFs a box draws with. The RATIOS (0.25 / 0.50 / 1.00) live in the
   // tool's own table, never here: a second place that halved an ATR would be a second
   // owner of the rule. A TF whose ATR is not warm pushes 0, which BaseKnotAbilityGet
   // reads as an ABSENCE: the type stays BK_NODE_NONE and the tooltip says so.
   // P-BK-79: one row per (TF, anchor) — the same list, the same keys.
   BaseKnotAbilityReset();
   for(int i = 0; i < n && i < BK_ENG_ROW_MAX; i++)
      BaseKnotAbilityPush(mins[i], anchors[i], ab[i]);
}

int OnCalculateHandler(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
    static uint s_lastCPUTime = 0;
    static int s_cpuWarningCount = 0;
    uint startTime = GetTickCount();

    // P-UI-98d: the click's double-click window commits here too — a click that
    // never moves the mouse again still sets its line (two stamp compares).
    HandsetClickSweep();

    if(IsIndicatorHidden())
    {
        return(rates_total);
    }

    // PERF: Cache Bid/Ask once per tick (moved after hidden check)
    CacheTickPrices();

#ifdef BUILD_LITE
    // P-BK-13: Lite has no RefreshKitOnBar pump — heal BK boxes (direction
    // auto-follow + fill/edge/TP) from the tick path, same 500 ms cadence
    // Full gets from RefreshUIPerTick. Domain-only, Lite-safe.
    static uint s_bkLitePumpMs = 0;
    {
       uint bkNow = GetTickCount();
       // P-BK-29/47: the Full pump (BiotakKit) pushes the movement step for the
       // note's break story (the type is the node's length and needs no size);
       // TH is below BaseKnotTool (THCalculations, P-BK-92, was ATR), so Lite —
       // which has no RefreshOnBar — hands the same TH points in from its tick pump.
       // P-BK-46: and the same pump hands the knots' EngSL risk in (BaseKnotEngPump).
       if(bkNow - s_bkLitePumpMs >= 500) { s_bkLitePumpMs = bkNow; BaseKnotStepPush(THAbilityPrice(Period(), 0)); BaseKnotEngPump(); BaseKnotSyncBadges(); TradePlanLiveTick(); }
    }
#endif

    // P-UI-53: the drag lock's watchdog. Steady state: one bool read per tick; the
    // KEYSTATE probe and the restore run only while a gesture still holds the lock.
    CustomPriceDragHealStale();
    // P-UI-98j: the step-1 pair's own net - a stashed handle whose object
    // vanished behind our back (suppressed delete event) is re-created on the
    // next frame. Throttled inside, reads-only while healthy.
    Step1HandleHealMissing();

    // P-TH3-P6: the six-condition pivot markers (self-throttled to a new bar
    // or 5 s; the scan underneath is cached per new bar of its own TF).
    // UI half only — Lite compiles no renderer (P-BUILD-01).
#ifndef BUILD_LITE
    TH3PivotMarkersUpdate();
    TH3HitPivotForward();   // P-TH3-STEP-04: the active pattern's ladder follows its own reaction
#endif

    static uint s_lastTickMs = 0;
    static double s_lastPrice = 0;
    static datetime s_lastBarTime = 0;
    static int s_lastPeriod = -1;
    static double s_lastCustomPrice = 0;

    uint nowMs = GetTickCount();
    double currentPrice = (rates_total > 0) ? close[rates_total-1] : 0;
    datetime currentBarTime = (rates_total > 0) ? time[rates_total-1] : (datetime)0;
    int currentPeriod = Period();
    double currentCustomPrice = g_customTHStartPrice;

    double priceChangePercent = 0;
    if(s_lastPrice > 0 && currentPrice > 0) {
        priceChangePercent = MathAbs((currentPrice - s_lastPrice) / s_lastPrice) * 100.0;
    }
    bool significantPriceChange = (priceChangePercent > 0.1);
    bool barsChanged = (currentBarTime != s_lastBarTime && s_lastBarTime != 0);
    bool isNewBar = barsChanged;
    bool timeframeChanged = (currentPeriod != s_lastPeriod && s_lastPeriod != -1);
    bool customPriceChanged = false;
    if(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) {
        customPriceChanged = (MathAbs(currentCustomPrice - s_lastCustomPrice) > EPSILON_PRICE);
    }

    // Tick throttle: skip redundant ticks within 50ms
    bool tickThrottled = (nowMs - s_lastTickMs < 50 && s_lastTickMs != 0);

    // Cache invalidation flags
    int invalidationFlags = CACHE_INV_NONE;
    if(timeframeChanged) invalidationFlags |= CACHE_INV_TIMEFRAME;
    if(barsChanged) invalidationFlags |= CACHE_INV_NEW_BAR;
    if(customPriceChanged) invalidationFlags |= CACHE_INV_CUSTOM_PRICE;
    if(invalidationFlags != CACHE_INV_NONE) {
        ApplyCacheInvalidation(invalidationFlags, s_lastPeriod, currentPeriod, s_lastCustomPrice, currentCustomPrice);
    }

    // VIEWLOCK-OFF:
    //if(g_viewRestorePending) {
    //    if(ViewLockRestore()) g_viewRestorePending = false;
    //}

    if(rates_total > 0)
    {
        // FIX: If not fully initialized, don't throttle redraws to ensure levels appear as soon as data is ready
        if(tickThrottled && !isNewBar && !g_redrawTHLevelsNeeded && g_initialized &&
           !g_forceClearOnNextDraw && !significantPriceChange &&
           !timeframeChanged && !customPriceChanged) {
            return rates_total;
        }

        LogRedrawDecision(isNewBar, timeframeChanged, customPriceChanged,
                          g_redrawTHLevelsNeeded, g_forceClearOnNextDraw,
                          significantPriceChange, tickThrottled);

        s_lastTickMs = nowMs;
        s_lastPrice = currentPrice;
        s_lastBarTime = currentBarTime;
        s_lastPeriod = currentPeriod;
        s_lastCustomPrice = currentCustomPrice;

        // P-PERF-49b: name the two spans OUTSIDE RedrawAllObjects() as well, so
        // `rest` narrows to "inside RedrawAllObjects but after the overlay slot"
        // instead of hiding the pre-work (price/invalidation/decisions, which on
        // a timeframe switch is ApplyCacheInvalidation's WIPE) together with the
        // post-work (ChartRedraw + the object-count check) in one anonymous pile.
        g_p3MsPre = GetTickCount() - startTime;
        TH3_PROF_START(RedrawCall);
        RedrawAllObjects(g_redrawTHLevelsNeeded || g_forceClearOnNextDraw);
        TH3_PROF_END(RedrawCall);

        // P-PERF-02: ChartRedraw after RedrawAllObjects — but ONLY when that
        // frame actually painted. The idle frames (nothing pending) used to ask
        // the terminal for a full chart repaint at tick rate anyway.
        uint afterRedrawMs = GetTickCount();
        if(g_lastRedrawDidWork) {
            g_lastRedrawDidWork = false;
            ThrottledChartRedraw();
        }
        g_p3MsPost = GetTickCount() - afterRedrawMs;

        if(barsChanged || s_lastBarTime == 0) {
            // PERF: Use cached object count
            int totalObjects = GetCurrentObjectCount();
            if(totalObjects > MAX_SAFE_OBJECTS && totalObjects < CRITICAL_OBJECT_LIMIT) {
                #ifdef ENABLE_DEBUG_LOGS
                if(s_cpuWarningCount % 10 == 0) {
                    Print("[W][GEN] Performance Warning: ", totalObjects, " objects on chart (recommended max: ", MAX_SAFE_OBJECTS, ")");
                    Print("[D][GEN] [CLEAN] Consider reducing inpMaxLevels for better performance");
                }
                #endif
                s_cpuWarningCount++;
            }
            else if(totalObjects >= CRITICAL_OBJECT_LIMIT) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("[E][GEN] [CRIT] CRITICAL: ", totalObjects, " objects approaching MT4 limit (64000)!");
                Print("[D][GEN] [CLEAN] EMERGENCY: Using indicator-scoped cleanup...");
                #endif
                EmergencyCleanupIndicatorObjects(inpObjectPrefix);
            }
        }
    }

    uint elapsed = GetTickCount() - startTime;
    if(elapsed > CPU_WARNING_MS) {
        // P-PERF-03: name the phase. The ledger costs a few int adds per frame
        // and turns "it is slow somewhere" into "levels took 1780 of 1797 ms".
        // P-PERF-49 (2026-09-16): THE LEDGER CAN NO LONGER LIE.
        //
        // The six slots are successive deltas of ONE GetTickCount() clock, all
        // taken inside RedrawAllObjects(), which itself runs inside the span
        // `elapsed` measures - so their sum is always <= elapsed, and the
        // difference is work the ledger never named. That difference was not
        // small. Today's live MT5 log carried a 94 ms frame as
        // "[levels=16 labels=0 ...]" with 78 ms owned by NOBODY, and every
        // other slot read 0 on 191 of 191 frames - because a phase shorter than
        // one 15.625 ms tick is invisible to this clock, not free.
        //
        // `rest` is what makes those two facts visible instead of silent: either
        // a named phase owns the frame's time, or `rest` does. An un-instrumented
        // tail can no longer hide behind a zero - including the code after the
        // overlay slot (custom-price / start-point work), which was never billed
        // to any slot at all. Integer math on a string that was being built
        // anyway, and a pure addition, so every existing reader still matches.
        uint phaseSum = g_p3MsBase + g_p3MsAtr + g_p3MsHistory +
                        g_p3MsLevels + g_p3MsLabels + g_p3MsOverlay +
                        g_p3MsPre + g_p3MsPost;
        uint restMs = (elapsed > phaseSum) ? (elapsed - phaseSum) : 0;
        string phase = " [base=" + IntegerToString((int)g_p3MsBase) +
                       " atr=" + IntegerToString((int)g_p3MsAtr) +
                       " hist=" + IntegerToString((int)g_p3MsHistory) +
                       " levels=" + IntegerToString((int)g_p3MsLevels) +
                       " labels=" + IntegerToString((int)g_p3MsLabels) +
                       " overlay=" + IntegerToString((int)g_p3MsOverlay) +
                       " pre=" + IntegerToString((int)g_p3MsPre) +
                       " post=" + IntegerToString((int)g_p3MsPost) +
                       " rest=" + IntegerToString((int)restMs) + "]";
        if(elapsed > CPU_CRITICAL_MS) {
            _LOG_GATE_E Print("[E][GEN] [CRIT] CRITICAL CPU: OnCalculate took ", elapsed, "ms!", phase, " Reduce inpMaxTHLevels!");
        }
        else if(s_lastCPUTime == 0 || GetTickCount() - s_lastCPUTime > 60000) {
            _LOG_GATE_W Print("[W][GEN] CPU Warning: OnCalculate took ", elapsed, "ms (threshold: ", CPU_WARNING_MS, "ms)", phase);
            s_lastCPUTime = GetTickCount();
        }
    }

    return rates_total;
}

//+------------------------------------------------------------------+
//| Apply Lines Visibility State to All Line Objects                 |
//|                                              |
//|                                                                  |
//| Called after RedrawAllObjects to ensure g_linesVisible is       |
//| respected for all line objects (HLINE and TREND)                 |

//+------------------------------------------------------------------+
//| Empty-box border segments (_B_Top/_B_Bottom/_B_Left) are part of |
//| the zone BOX, not lines - the L key and line visibility must not |
//| toggle them (same behavior as the filled box rectangle).         |
//+------------------------------------------------------------------+
// P-PERF-23c: _B_Right was MISSING here while the L switch's cache walk
// (SetAllLineObjectsVisibility, VisibilityManager) excluded ALL FOUR. Two owners
// of the same question disagreed, so the F switch's show branch treated the
// right border segment as a level LINE: with lines hidden it hid that edge of
// the empty box and left the other three - a box with a side missing, straight
// out of "the indicator hides parts of my chart for no reason". The four
// segments are one family (the box), and no visibility switch owns them.
bool IsZoneBoxBorderObject(const string name)
{
    if(StringFind(name, "_B_Top") >= 0)    return true;
    if(StringFind(name, "_B_Bottom") >= 0) return true;
    if(StringFind(name, "_B_Left") >= 0)   return true;
    if(StringFind(name, "_B_Right") >= 0)  return true;
    return false;
}

//==============================================================================
// P-UI-61 — the drag has ONE anchor writer and ONE frame owner. Reported: the
// custom-price drag lags and the released line rebuilds the ladder elsewhere —
// both halves were one defect, because `g_customTHStartPrice` (the value the whole
// ladder derives from) was written INSIDE the redraw throttle: every event in the
// 50 ms window was DROPPED, not deferred (line ~30 Hz, anchor 20 Hz), and the
// CARRY channel never persisted, so the release re-resolved from a key older than
// the gesture and overwrote the anchor with it. Rules now:
//   * `CustomPriceDragAnchorSet(price)` — the only writer of the anchor during a
//     gesture, persisting through the P-UI-56 writer (steady state: one compare);
//   * `CustomPriceDragFrame(force)` — the only caller of the heavy pass from the
//     drag, so both channels share ONE budget; a refused frame is OWED.
//   * the release settles from the OBJECT (the one value MT4 keeps exact).
//==============================================================================
static bool s_cpDragFrameOwed = false;

bool CustomPriceDragAnchorSet(const double price)
{
    if(!MathIsValidNumber(price) || price <= 0.0) return false;
    if(MathAbs(price - g_customTHStartPrice) <= _Point * 0.5) return false;
    g_customTHStartPrice = price;
    g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
    g_customPriceKeyboardOverride = true;
    // P-UI-56: the same ONE writer as every other placement path. Persisting here
    // is what makes the resolver agree with the anchor instead of re-anchoring the
    // release to an older key.
    CustomPricePersistPlacement(price);
    g_redrawTHLevelsNeeded = true;
    return true;
}

void CustomPriceDragFrame(const bool force)
{
    s_cpDragFrameOwed = true;                    // owed until this call really paints
    uint nowMs = GetTickCount();
    if(!force && nowMs - g_lastDragRedrawTime <= DRAG_REDRAW_THROTTLE_MS) return;
    // P-UI-53: re-assert the view lock on the same budget (read-guarded: three
    // reads, a write only on drift).
    CustomPriceDragReassertLock();
    RedrawAllObjects(true);
    ThrottledChartRedraw();
    g_lastDragRedrawTime = nowMs;
    s_cpDragFrameOwed = false;
}

bool CustomPriceDragFrameOwed() { return s_cpDragFrameOwed; }

//==============================================================================
// P-UI-100 (2026-09-22) — THE POLICY THAT KEEPS A HAND-SET LINE OUT OF SOMEBODY
// ELSE'S GESTURE.
//
// The law, the primitives and the cost live in UtilityFunctions
// (HandLinesSelectionGuard / HandLineDropSelection / HandLinesRestorePrice).
// What belongs HERE is the part only the gesture state can answer: which of the
// two lines a live gesture of ours is holding, and what to do when a claimed
// gesture turns out to be a DRAW.
//
// The section sits HERE, after the drag-frame and the anchor writers, because
// the restore re-asserts exactly what the settle does — the number, the anchor,
// the marker, the frame — and every one of those writers must already be
// declared.
//==============================================================================

// P-UI-100b: THE ONE WRITER of "the line goes back where the grab found it".
// The order is the settle's own: the price, the anchor it is persisted under,
// the selection the draw's own claim left on it, the marker that shows it, and
// the forced frame that repaints the ladder derived from it.
void CustomPriceRestoreGrabPrice()
{
    if(!g_customPriceLineCreated) return;
    if(!(s_ownGrabPrice > 0.0) || !MathIsValidNumber(s_ownGrabPrice)) return;
    HandLinesRestorePrice(g_customPriceHorizontalLineName, s_ownGrabPrice);
    g_customTHStartPrice = s_ownGrabPrice;
    CustomPriceDragAnchorSet(s_ownGrabPrice);
    HandLineDropSelection(g_customPriceHorizontalLineName);   // the draw's own selection goes
    CustomPriceMarkerSync();
    CustomPriceDragFrame(true);
}

// P-UI-100b: the detector's answer, called for EVERY foreign object the terminal
// creates (the OBJECT_CREATE branch of OnChartEventHandler owns the name test
// that decides "foreign").
//
// Two timings, both real (which one a build uses is the terminal's business):
//   * the object exists from the PRESS -> the stamp is set before the first move,
//     and the claim's own test refuses the gesture: nothing moves, nothing to undo;
//   * the object appears at the RELEASE -> the gesture is already claimed, so it
//     is marked a DRAW: the carry stands down from here and the release restores
//     the price the grab found.
void CustomPriceForeignDrawSeen()
{
    s_cpForeignDrawUntil = GetTickCount() + CP_DRAW_WITNESS_MS;
    if(g_customPriceLineDragging)
    {
        s_drawNotGrab = true;   // the live gesture is a draw, not a grab
        return;
    }
    // The create landed AFTER our release: the gesture is over, so the restore
    // runs here instead. Guarded by the grab's own price — nothing clears it
    // until the next claim — and by "no gesture of ours is live".
    if(s_ownGrabPrice > 0.0 && !g_s1DragLive && !g_s1OwnActive)
        CustomPriceRestoreGrabPrice();
}

// P-UI-100: THE NET UNDER EVERY PATH WE DO NOT SEE.
//
// The guard has a call site at every gesture START this indicator can observe,
// but the terminal performs gestures whose events another layer consumes whole
// (the box tool's draw session returns before the custom-price block — see
// P-UI-100's note in BaseKnotTool), so the invariant also needs an owner that
// does not depend on any event reaching us. This is it: the 250 ms timer.
//
// The button gate is deliberate and conservative (`UILeftButtonUp`: BOTH
// conventions must agree the button is free — P-UI-73's rule for the same probe).
// A press we did not see belongs to somebody else's gesture, and the selection it
// made is theirs to end; the first timer after the release heals it. A gesture of
// OURS is never healed either way: the guard skips the lines its own gesture
// holds, so a live drag cannot lose its selection to the net (P-BK-15).
void HandLinesSelectionNet()
{
    if(!UILeftButtonUp()) return;
    HandLinesSelectionGuard();
    // P-UI-100c: and the same net asks the second half of the invariant — the
    // line must sit on the anchor the ladder is drawn from. Gated by the same
    // "no button is down" witness, so it can never touch a live drag; a line
    // that really drifted is put back within one 250 ms beat.
    HandLineHealToAnchor();
}

//==============================================================================
// P-UI-98 — THE FIRST STEP IS DRAGGABLE (custom-price mode). Requested: the custom
// line AND step 1 selectable / draggable / deselectable (only step 1), the chosen
// step carrying to the other timeframes at the same ratios.
// THE HANDLE: the trigger line ONE STEP from the custom price line, picked by
// GEOMETRY at render time (`Step1HandlePick`), never by rung number — `_Above_1` /
// `_Below_2`, since the below rung-1 line lands exactly ON the custom line (98f).
// THE MATH: F = |dragged - start| / the mode's natural first step, ONE MULTIPLIER
// on the factory's own stepSizes, CHART-SCOPED so every TF re-scales by the same F
// and the ratios the course defines survive.
// THE GESTURE: MT4's own OBJECT_DRAG, sharing the custom-price drag's ONE frame
// budget and view lock; never write the dragged line's own price mid-gesture
// (P-BK-15); the release settles with one forced frame and DROPS MT4's selection
// (P-UI-45); a motionless release is healed by `CustomPriceDragHealStale`.
// OFF: resets with the placement (R key) and on REASON_REMOVE.
//==============================================================================
bool   Step1DragLive()  { return g_s1DragLive; }
string Step1DragName()  { return g_s1DragName; }
static double s_s1GrabPrice = 0.0;   // the handle's price at the claim (the echo stamp's base)
static bool   s_s1GrabNamed = false;
static string s_s1GrabName  = "";
// P-UI-98f: the handle's DISTANCE from the custom price line and the factor in
// force at the press. They are the gesture's own baseline: the drag scales F by
// how far the handle travelled RELATIVE to the distance it was grabbed at, so a
// touch that moves nothing can never rescale anything - whatever the ladder's
// mode, the drawn pair sits at `k * F * step`, and in the SS/LS and Factor modes
// `k` is not exactly 1, so the absolute reading (|dragged - start| / natural)
// would snap F a few percent the instant the hand closed.
static double s_s1GrabDist   = 0.0;
static double s_s1GrabFactor = 0.0;
// P-UI-98f: the line's price as of the PREVIOUS held event. It is what tells a
// live terminal drag from a dead one (see Step1HandleOwnDragMove's stand-down).
static double s_s1SeenPrice  = 0.0;

// THE gesture's own state, cleared in ONE place (P-UI-98f). TWO paths end a
// gesture - the settle and the stale-drag heal - and for a while only one of
// them cleared the statics, so a gesture healed by the net left the echo stamp's
// base, the press baseline and the seen-price behind: the NEXT gesture skipped
// its own capture (`s_s1GrabNamed` still true for the same name) and every
// release was stamped against a price from a gesture that was already over. One
// owner, both callers.
void Step1GestureStateClear()
{
    g_s1OwnActive = false;
    g_s1OwnLastWrite = 0.0;
    g_s1OwnGrabPrice = 0.0;
    g_s1OwnGrabCursorPrice = 0.0;
    s_s1GrabPrice = 0.0;
    s_s1GrabNamed = false;
    s_s1GrabName = "";
    s_s1GrabDist = 0.0;
    s_s1GrabFactor = 0.0;
    s_s1SeenPrice = 0.0;
}

// The handle match. P-UI-98f: the handle is the line ONE STEP from the custom
// price line (picked by geometry in LevelPipeline's Step1HandlePick), which is
// `_Above_1` above but `_Below_2` below — the below side's rung-1 line is the
// zone boundary drawn ON the custom price line. A suffix test cannot name that
// pair, so the ONE owner of the answer is the render's own stash: the face
// owner wrote both names when it wrote both faces, and the gesture, the drag
// channel and the click contract all ask that stash. The side is answered the
// same way (`Step1LineIsAbove`), never by parsing a name.
bool Step1LineIsDragHandle(const string name)
{
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return false;
    if(name == "") return false;
    if(g_s1MarkPeriod != Period()) return false;   // another TF's pair is not this one
    return (name == g_s1MarkAboveName || name == g_s1MarkBelowName);
}

// Which side of the custom price line does the handle sit on? The stash names
// the line; the rendered direction is what the name was stashed under.
bool Step1LineIsAbove(const string name)
{
    return (g_s1MarkAboveName != "" && name == g_s1MarkAboveName);
}

// The OBJECT_DRAG channel. Runs on every step of MT4's native drag.
void Step1LineDragApply(const string name)
{
    // First event of a gesture: the view is the gesture's until the release
    // (idempotent — a live custom-price lock is re-asserted, never re-captured).
    if(!g_s1DragLive)
    {
        g_s1DragLive = true;
        g_s1DragName = name;
        CustomPriceDragLockOn();
    }
    s_cpLockActMs = GetTickCount();   // the heal's activity stamp is the gesture's

    // P-UI-100b: the gesture is still OURS (the settle and the guard must keep
    // treating it as such), but it is a DRAW: the ladder must not re-step with it.
    if(s_drawNotGrab) return;

    double start = GetMidpointPrice(g_thStartPointType);
    double natural = NaturalFirstStep();
    double dragged = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
    if(!(start > 0.0) || !(natural > 0.0) || !(dragged > 0.0) ||
       !MathIsValidNumber(start) || !MathIsValidNumber(dragged))
        return;
    if(!s_s1GrabNamed || s_s1GrabName != name)   // the echo stamp's base: price AT the claim
    {
        s_s1GrabPrice = dragged;
        s_s1GrabName = name;
        s_s1GrabNamed = true;
        // the gesture's baseline (P-UI-98f), taken on the line's resting price
        s_s1GrabDist = MathAbs(dragged - start);
        s_s1GrabFactor = StepOverrideFactor();
    }

    // P-UI-98f: the side comes from the stash, never from the name's tail — the
    // below handle is `_Below_2` (see Step1LineIsDragHandle). And the distance
    // read off the custom price line is the STEP the ladder wears: every drawn
    // trigger line sits a whole number of steps from it (`start + k*step`
    // above, `start - k*step` below), so `newFirst` is F x natural at rest and
    // a no-move touch can never rescale anything.
    bool above = Step1LineIsAbove(name);
    double newFirst = above ? (dragged - start) : (start - dragged);
    // the handle icon rides its own drag (the render skips the dragged line, so
    // the stash is stale until settle — the drag channel IS the live answer)
    if(above)
    {
        g_s1MarkAbovePrice = dragged;
        HandsetHandleAt(S1MarkName(1), dragged, S1_HANDLE_RES);
    }
    else
    {
        g_s1MarkBelowPrice = dragged;
        HandsetHandleAt(S1MarkName(-1), dragged, S1_HANDLE_RES);
    }
    // The wrong side (dragged across the start) or a sub-point step is not a
    // small step, it is no step — ignore it; the release frame snaps the line
    // back to the step the ladder actually wears.
    if(newFirst < _Point) return;

    // THE STEP THE HAND IS DRAWING. Relative to the grab whenever the gesture
    // carries a baseline (both our own carry and a native drag: the baseline is
    // taken on the first event of either), so the handle keeps its own offset
    // from the custom price line and the ladder scales with the hand exactly.
    // With no baseline (a degenerate grab ON the line) the absolute reading is
    // the fallback, and it is the same number in the uniform modes: the handle
    // sits at `F * natural` there, so `newFirst / natural` IS the factor the
    // drop position asks for.
    double candidate = (s_s1GrabDist > 0.0 && s_s1GrabFactor > 0.0)
                       ? (s_s1GrabFactor * (newFirst / s_s1GrabDist))
                       : (newFirst / natural);
    if(!MathIsValidNumber(candidate)) return;
    if(MathAbs(candidate - StepOverrideFactor()) <= 0.0005) return;   // dead band: half a permille
    StepOverrideFactorSet(candidate);
    // P-UI-98e: THE F ACTUALLY CHANGED, SO THE LADDER IS STALE. The levels block
    // is gated on this flag (`if (inpShowTHLevels && (g_redrawTHLevelsNeeded ||
    // g_buildStage != 0))`), and the custom price line's own live follow sets it
    // on every anchor change (`CustomPriceDragAnchorSet`) - without it here the
    // frame ran, the signature said "geometry changed", and the level family was
    // still skipped: the ladder only caught up on the next unrelated frame, i.e.
    // the step-1 drag did NOT move the other levels in the moment.
    g_redrawTHLevelsNeeded = true;
    CustomPriceDragFrame(false);   // the shared 50 ms budget; the refused frame is owed
}

// P-UI-98e / P-LM-21: THE DRAGGABLE FLAG IS BORROWED, AND RETURNED. The terminal
// re-arms its own per-object drag on every paint while SELECTABLE sits on the
// line, so a gesture that owns the movement must take the flag off for its whole
// length - and give it back on BOTH exits, or the line stays deaf afterwards.
// Guarded: one read, a write only on drift.
void Step1DragSelectable(const string name, const bool on)
{
    if(name == "") return;
    if(ObjectFind(0, name) < 0) return;
    if((bool)ObjectGetInteger(0, name, OBJPROP_SELECTABLE) != on)
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, on);
}

// The release. Called from the button-up mouse-move latch (the same branch that
// settles the custom-price line) and from the stale-drag heal.
void Step1DragSettle()
{
    if(!g_s1DragLive) return;
    g_s1DragLive = false;
    string name = g_s1DragName;
    g_s1DragName = "";
    // P-UI-98e: the borrowed flag goes back exactly as the pair's own state wants
    // it - armed and in custom-price mode means grabbable again (and the forced
    // frame below re-owns it anyway); otherwise the face owner's next frame parks
    // the pair.
    if(g_s1OwnBorrowed)
    {
        g_s1OwnBorrowed = false;
        Step1DragSelectable(name, g_s1LinesArmed &&
                                  g_thStartPointType == TH_START_POINT_CUSTOM_PRICE);
    }
    // P-UI-98d: stamp the echo only when the gesture MOVED the handle — a
    // jitter-click's phantom gesture must not block its own commit click.
    double settled = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
    bool s1Moved = (settled > 0.0 && s_s1GrabNamed && name == s_s1GrabName &&
                    MathAbs(settled - s_s1GrabPrice) > _Point * 0.5);
    if(s1Moved)
        g_s1JustDraggedMs = GetTickCount();
    // P-UI-98h: a gesture that MOVED the line is a drag by definition, never a
    // click: the deferred SET a press echo armed dies with it, or the sweeper
    // commits it the moment the button comes up and the handle goes inert right
    // after a working drag («دیگه نمیشه درگش کرد»). The native channel
    // (OBJECT_DRAG) reaches here too - the claim's own cancel cannot, because
    // that gesture never claimed.
    if(s1Moved) { g_s1SetPending = ""; g_s1SetPendingMs = 0; }
    // P-UI-100b (2026-09-22): A DRAW SETTLES BACK, exactly as the custom price line
    // does. The handle's price is put back where the claim found it and the step
    // factor the press was made under is re-asserted, so a fib or a box drawn from
    // a rung-1 line leaves the ladder exactly as the user had it — the two lines
    // answer one law, not two.
    if(s_drawNotGrab)
    {
        s_drawNotGrab = false;
        if(s_s1GrabNamed && s_s1GrabName == name && s_s1GrabPrice > 0.0)
            HandLinesRestorePrice(name, s_s1GrabPrice);
        if(s_s1GrabFactor > 0.0 && MathAbs(s_s1GrabFactor - StepOverrideFactor()) > 0.0005)
        {
            StepOverrideFactorSet(s_s1GrabFactor);
            g_redrawTHLevelsNeeded = true;
        }
        CustomPriceDragFrame(true);
    }
    // P-UI-98e/98f: the carry's own state goes with the gesture - a stale
    // g_s1OwnActive would keep the held-move pass running for a drag that is
    // over, and a stale g_s1OwnLastWrite / grab base would make the next grab
    // compare and scale against a price this gesture wrote. ONE owner clears it,
    // and it runs AFTER the echo stamp (which reads the grab base it clears).
    Step1GestureStateClear();
    CustomPriceDragFrame(true);   // the gesture's last pixel is painted from the final F
    CustomPriceDragLockOff();     // the view is the user's again (idempotent)
    // P-UI-45: drop the selection the grab left behind — a SELECTED line is
    // moved by MT4 on every later drag anywhere on the chart. Guarded write.
    if(name != "" && (bool)ObjectGetInteger(0, name, OBJPROP_SELECTED))
        ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
}

//==============================================================================
// P-UI-98e — THE STEP-1 HANDLE CARRIES ITSELF (2026-09-22).
//
// Reported: «الان step اول در هر تایم که درش هستیم قابل درگ کردن نیستش ... در هر
// تایم همون اولین step که رسم میشه قابل درگ و مثل خط کاستوم ریل تایم باشه بدون
// بار اضافی». The P-UI-98 gesture handed the movement to MT4's OWN per-object
// drag (the line's SELECTABLE flag plus OBJECT_DRAG), and that is the half the
// custom price line ALREADY stopped trusting: P-UI-49c's finding — "MT4's
// per-object native drag needs the terminal to grab the object first and several
// builds never engage it at all" — is exactly why the line carries itself. So
// the handle now wears the SAME channel, with the same numbers (the tolerance,
// CP_DRAG_SLOP, the absolute-off-the-grab carry, the frozen stand-down that
// keeps our write off a live terminal drag, P-BK-15): the drag no longer depends
// on a terminal behaviour the project has already measured as unreliable.
//
// The math, the icon and the frame budget are the P-UI-98 owners
// (`Step1LineDragApply` + `CustomPriceDragFrame`), reused, never duplicated —
// this block only decides WHO moves the line and by HOW MUCH. The native channel
// stays live beside it (the frozen test stands our writes down the moment the
// terminal moves the line itself), so whichever of the two the build supports,
// the handle follows the hand.
//
// Cost: on a PRESS EDGE one conversion plus two compares, and while the gesture
// is live the carry's own three reads. The steady state — no gesture — is the
// one `g_s1OwnActive` compare on a mouse move, inside the block the custom price
// line already runs.
//==============================================================================

// Is the press ON a rung-1 handle? The render's own stash answers (the two
// prices and names the face owner already had in hand), so the test never walks
// the chart. The tolerance is the custom price line's own: the line as DRAWN
// plus a few pixels, which is what the terminal itself uses. P-UI-98e: the test
// does NOT ask the armed state — the CLICK contract reaches a SET handle through
// it (that is how a double-click re-arms one), while the DRAG's claim below asks
// `g_s1LinesArmed` itself.
bool Step1HandleUnderCursor(const int x, const int y, string &handleName)
{
    handleName = "";
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return false;
    if(g_s1MarkPeriod != Period()) return false;   // P-UI-98e: THIS tf's step 1 only
    if(!g_linesVisible || IsIndicatorHidden()) return false;
    if(g_s1MarkAboveName == "" && g_s1MarkBelowName == "") return false;
    int heightPx = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    double span = WindowPriceMax() - WindowPriceMin();
    if(heightPx <= 0 || !(span > 0.0)) return false;
    // P-UI-98h: the AFFORDANCE is the 15 px circle the hand grabs (its half is
    // 7 px), not the 1 px line under it. The old gate (width + 4 = 5 px)
    // rejected a press on the icon's own rim, and the press edge has already
    // carried the cursor a few px past the press point by the time this test
    // runs - «راحت درگ نمیشه کردنش». The custom price line still wins any
    // tie (its claim runs first, `!onCustomLine`), so the wider rim cannot
    // steal that gesture.
    int tolPx = HANDSET_HANDLE_HALF + (int)inpCustomPriceLevelWidth + 3;
    if(tolPx < 10) tolPx = 10;
    double tolPrice = span * ((double)tolPx / (double)heightPx);
    int subW = 0; datetime cursorT = 0; double priceAtCursor = 0.0;
    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, priceAtCursor)) return false;
    // the NEAREST armed row wins: a press between the two rung-1 lines must
    // belong to the one the user sees under the hand
    double bestDist = tolPrice;
    if(g_s1MarkAboveName != "" && g_s1MarkAbovePrice > 0.0 &&
       MathAbs(g_s1MarkAbovePrice - priceAtCursor) <= bestDist)
    {
        bestDist = MathAbs(g_s1MarkAbovePrice - priceAtCursor);
        handleName = g_s1MarkAboveName;
    }
    if(g_s1MarkBelowName != "" && g_s1MarkBelowPrice > 0.0 &&
       MathAbs(g_s1MarkBelowPrice - priceAtCursor) <= bestDist)
        handleName = g_s1MarkBelowName;
    return (handleName != "");
}

//==============================================================================
// P-UI-98i — THE STEP-1 HANDLE DRAGS LIKE THE CUSTOM PRICE LINE (2026-09-22).
//
// Reported: «همون step درگ میشه ... روان درگ نمیشه هی قطع میشه». Three
// asymmetries with the custom-price channel made the handle harder to grab
// and easier to lose mid-gesture than the line beside it:
//
// (1) NEAREST WINS, not custom-always-wins. The old press-edge gate refused
// the handle whenever the cursor was ALSO on the custom price line
// (`!onCustomLine`), so on a coarse chart - where one step is a few pixels -
// a press aimed at the red handle always dragged the green line instead.
// Both rows answer now and the nearer price wins the gesture (an exact tie
// stays with the line, the placement's anchor); the loser yields through the
// same single terms as before (`s1Claimed` below, this gate here).
//
// (2) A MISSED PRESS EDGE STILL CLAIMS. The edge is seen on the first MOVE
// after the press, so a press whose first move never arrived here (a release
// off-chart leaves the shared `s_dragDownSeen` latch set) had no edge to arm
// on and the handle was dead until some unrelated click reset the latch -
// while the custom-price claim beside it recovered through MT4's own
// selection (`terminalGrab && atLineNow`). A SELECTED handle with the cursor
// really on its row claims the same way now.
//
// (3) A NATIVE-ONLY DRAG IS ADOPTED. When MT4's own per-object drag moves the
// line first (no own claim yet), `g_s1DragLive` is up through the OBJECT_DRAG
// channel but `g_s1OwnActive` is not - and that gesture then lived or died by
// OBJECT_DRAG alone (the P-UI-49c builds where it stutters cut the drag).
// The held pass adopts such a gesture into our own carry (same latch, same
// borrow, same relative math), so both channels drive it from then on.
//==============================================================================

// Is the press at (x,y) nearer to the step-1 row `s1Row` than to the custom
// price line? Press-edge only (one conversion per gesture). An exact tie -
// within half a point - stays with the line: it is the placement's anchor,
// and the old rule must remain the answer there.
bool Step1NearerThanCustom(const int x, const int y, const string s1Row)
{
    if(s1Row == "" || !g_customPriceLineCreated) return false;
    int subW = 0; datetime cursorT = 0; double cursorPrice = 0.0;
    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, cursorPrice)) return false;
    if(!(cursorPrice > 0.0) || !MathIsValidNumber(cursorPrice)) return false;
    double linePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(!(linePrice > 0.0) || !MathIsValidNumber(linePrice)) return false;
    double s1Price = 0.0;
    if(s1Row == g_s1MarkAboveName) s1Price = g_s1MarkAbovePrice;
    else if(s1Row == g_s1MarkBelowName) s1Price = g_s1MarkBelowPrice;
    else return false;
    if(!(s1Price > 0.0) || !MathIsValidNumber(s1Price)) return false;
    return (MathAbs(s1Price - cursorPrice) + _Point * 0.5 < MathAbs(linePrice - cursorPrice));
}

// The press-edge claim. TRUE means this gesture belongs to the handle - the
// caller must then leave the custom price line's own claim alone (one cursor,
// one gesture). The view lock, the selection face and the grab price are taken
// here, in that order, and the grab price is recorded BEFORE any write: it is
// the settle's echo stamp base (a drag release must not set the line it moved).
bool Step1HandleOwnClaim(const string handle, const int x, const int y)
{
    if(handle == "") return false;
    if(!g_s1LinesArmed) return false;      // a SET handle is inert: nothing may grab it
    if(ObjectFind(0, handle) < 0) return false;
    double linePrice = ObjectGetDouble(0, handle, OBJPROP_PRICE, 0);
    if(!(linePrice > 0.0) || !MathIsValidNumber(linePrice)) return false;
    g_s1DragLive = true;
    g_s1DragName = handle;
    // P-UI-98g: a hand on the line IS the request for its handle - the circles
    // appear while the gesture runs (and stay after it), so a drag started on a
    // line the user never clicked does not look like nothing happened.
    g_s1HandleShown = true;
    g_s1OwnActive = true;
    // P-UI-98h: a hand on the line CANCELS any pending SET - the press echo of
    // THIS press may have armed one (OBJECT_CLICK arrives on the press), and
    // the sweeper would commit it the moment the button comes up, i.e. right
    // after a drag that worked («دیگه درگ نمیشه»).
    g_s1SetPending = "";
    g_s1SetPendingMs = 0;
    g_s1OwnGrabY = y;
    g_s1OwnGrabPrice = linePrice;
    g_s1OwnLastWrite = 0.0;
    g_s1OwnGrabCursorPrice = 0.0;
    s_s1SeenPrice = linePrice;      // P-UI-98f: the gesture's first reference price
    {
        int gW = 0; datetime gT = 0;
        if(!ChartXYToTimePrice(0, x, y, gW, gT, g_s1OwnGrabCursorPrice))
            g_s1OwnGrabCursorPrice = 0.0;
    }
    // THE BORROW HAPPENS HERE, BEFORE ANY WRITE (P-LM-21's rule, at the earliest
    // moment the gesture is provably ours): the terminal arms its own per-object
    // drag at the PRESS and re-arms it on every paint while SELECTABLE sits on the
    // object, so a gesture that means to own the movement must take the flag off
    // first or the two drags fight - «سریع قطع میشه».
    g_s1OwnBorrowed = true;
    Step1DragSelectable(handle, false);
    // the face: MT4's own selection is what a grabbed line looks like. Written
    // ONLY when the terminal did not already select it - a property write on the
    // object it is dragging cancels that drag (P-BK-15) - and the carry below
    // then owns the movement, exactly as it does on the custom price line.
    if(!(bool)ObjectGetInteger(0, handle, OBJPROP_SELECTED))
        ObjectSetInteger(0, handle, OBJPROP_SELECTED, true);
    CustomPriceDragLockOn();        // the view is the gesture's until the release
    Step1LineDragApply(handle);     // the ONE math owner, and the baseline of the echo test
    return true;
}

// The held pass: our own carry, then the P-UI-98 owner for the factor, the icon
// and the frame. `wishPrice` is the grab price plus the cursor's TRAVEL since
// the grab (never the cursor's own price), so the press offset survives, the
// line can never snap onto the cursor, and a click's jitter - below CP_DRAG_SLOP
// - opens no door at all: a click stays a click.
void Step1HandleOwnDragMove(const int x, const int y)
{
    if(!g_s1OwnActive || g_s1DragName == "") return;
    if(ObjectFind(0, g_s1DragName) < 0) { Step1DragSettle(); return; }   // gone under the hand
    // P-UI-100b (2026-09-22): AND THE HANDLE STANDS DOWN FOR A DRAW TOO. The step-1
    // claim runs BEFORE the custom-price claim at the press edge, so a fib or a box
    // drawn from a rung-1 line is claimed by THIS channel - and the carry would move
    // the handle and re-step the whole ladder with it. The gesture is left alone
    // (its own settle still runs at the release and puts the handle back); only the
    // writes stop.
    if(s_drawNotGrab) return;
    double current = ObjectGetDouble(0, g_s1DragName, OBJPROP_PRICE, 0);
    if(!(current > 0.0) || !MathIsValidNumber(current)) return;
    // P-UI-98i: the press latch is retried, never frozen. The grab cursor price
    // is taken once at the claim; when that conversion failed the carry's gate
    // below could never open and - with the draggable flag borrowed - NO channel
    // moved the line at all. One conversion per held event until it lands.
    if(!(g_s1OwnGrabCursorPrice > 0.0))
    {
        int rW = 0; datetime rT = 0; double rP = 0.0;
        if(ChartXYToTimePrice(0, x, y, rW, rT, rP) && rP > 0.0 &&
           MathIsValidNumber(rP))
            g_s1OwnGrabCursorPrice = rP;
    }
    if(MathAbs(y - g_s1OwnGrabY) >= CP_DRAG_SLOP && g_s1OwnGrabCursorPrice > 0.0)
    {
        // (the draggable flag was already borrowed at the CLAIM, before any write:
        // P-LM-21, and earlier than the first travel, so nothing re-arms behind
        // us - see Step1HandleOwnClaim.)
        // THE TERMINAL OWNS THE MOVEMENT WHILE IT IS MOVING (P-UI-98f). A write on
        // the object MT4 is dragging cancels that drag (P-BK-15), so our carry
        // stands down then - but "the price differs from our last write" is NOT
        // the same question, and reading it as one froze the gesture: the borrow
        // takes SELECTABLE off at the claim, MT4's armed drag ends on its next
        // paint, and a price it moved ONCE before that left `current != ref` for
        // the rest of the gesture with nobody moving anything - the hand kept
        // dragging, the line stood still. So the stand-down asks the price to
        // have changed since the PREVIOUS held event: live terminal, hands off;
        // price at rest, the carry takes over (and a write lands only when the
        // cursor really moved, below).
        double ref = (g_s1OwnLastWrite > 0.0) ? g_s1OwnLastWrite : g_s1OwnGrabPrice;
        bool terminalLive = (MathAbs(current - ref) >= _Point * 0.5) &&
                            (MathAbs(current - s_s1SeenPrice) >= _Point * 0.5);
        s_s1SeenPrice = current;
        if(!terminalLive)
        {
            int subW = 0; datetime curT = 0; double cursorPrice = 0.0;
            if(ChartXYToTimePrice(0, x, y, subW, curT, cursorPrice) && cursorPrice > 0.0)
            {
                double wishPrice = g_s1OwnGrabPrice + (cursorPrice - g_s1OwnGrabCursorPrice);
                if(wishPrice > 0.0 && MathAbs(wishPrice - current) > _Point * 0.5)
                {
                    ObjectSetDouble(0, g_s1DragName, OBJPROP_PRICE, wishPrice);
                    g_s1OwnLastWrite = wishPrice;
                    s_s1SeenPrice = wishPrice;   // we are the last mover
                }
            }
        }
    }
    Step1LineDragApply(g_s1DragName);   // the factor, the icon, the shared frame budget
}

//==============================================================================
// P-UI-98e — THE CLICK CONTRACT, AND WHY IT CANNOT LIVE ON ONE EVENT.
//
// User order: «خط کاستوم پرایس و خط step اول وقتی بعد جابجایی روش کلیک شد ست
// نهایی بشه و با دبل کلیک فعال بشه تا زمانی که ست نهایی نشده آزادانه درگ بشه».
// The handle's click used to arrive ONLY through MT4's own `OBJECT_CLICK` on the
// HLINE — the very hit test whose failure is why the drag needed an own channel
// (`P-UI-49c`), and a 15 px bitmap icon sits exactly where the user clicks. Two
// more measured MT4 facts narrow the door further: a motionless press/release
// emits no MOUSE_MOVE at all (P-BK-03, the leg meter's P-LM-13 trap), so the
// release latch can miss a still click entirely. So the click is ONE owner —
// `Step1HandleClickAt` — reached from THREE edges:
//   * our own press/release pair on the mouse stream (row + travel, below),
//   * `Step1ClickFinalize` from `CHARTEVENT_CLICK` (the button-up that carries
//     no move), and
//   * MT4's own `OBJECT_CLICK`, kept as the third opinion it always was.
// A physical click can reach that owner twice; the FIRST call answers and its
// twin is dropped inside one short window, so a double-click can never be read
// as two singles (or a single as a double) because of the transport.
//==============================================================================
// (the contract's state lives in GlobalVariables — the heal above has to consume
// a lost press, and it is defined a hundred lines before this block.)

// THE click. `name` is the rung-1 line the click landed on; the armed state is
// read as it is NOW, so a click on a SET handle is the double-click that wakes it.
void Step1HandleClickAt(const string name)
{
    if(name == "") return;
    uint now = GetTickCount();
    if(g_s1ClickHandledMs != 0 && now - g_s1ClickHandledMs < 60) return;   // the same click's twin event
    g_s1ClickHandledMs = now;
    bool dbl = (g_s1ClickLastMs != 0 && now - g_s1ClickLastMs < DOUBLE_CLICK_THRESHOLD_MS);
    g_s1ClickLastMs = now;
    if(dbl)
    {
        // the second click CANCELS the pending SET and wakes a set handle — the
        // user's «با دبل کلیک فعال بشه ... و ست نهایی بشه» pair, in one place
        g_s1SetPending = "";
        g_s1SetPendingMs = 0;
        if(!g_s1LinesArmed)
        {
            g_s1LinesArmed = true;   // re-armed: draggable again, the red handle back
            g_s1HandleShown = true;  // P-UI-98g: and revealed, like the green one
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);  // the face owner re-owns the pair + icon
        }
        return;
    }
    // P-UI-98g: THE FIRST CLICK SHOWS THE RED CIRCLES. The pair is armed from the
    // placement on (armed = the line answers a grab), but its icon is the answer
    // to a click — «فقط وقتی روش کلیک کردیم دایره ها بیاد برای درگ کردن» — and
    // that click must not be spent setting a line the user has not touched yet.
    if(!g_s1HandleShown)
    {
        g_s1HandleShown = true;
        if(g_s1LinesArmed && !g_s1DragLive)
        {
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);   // the face owner places the two circles
        }
        return;
    }
    // a click that is the ECHO of a drag release sets nothing (the stamp the
    // settle writes), so a gesture the user DRAGGED never commits under the hand
    // P-UI-98h: never arm the SET while a gesture is live - OBJECT_CLICK is
    // delivered on the PRESS, so this line is reached with the hand already
    // holding the line, and the sweeper would commit it the moment the button
    // comes up, i.e. right after a drag that worked.
    if(g_s1LinesArmed && !g_s1DragLive && now - g_s1JustDraggedMs > 350)
    {
        g_s1SetPending = name;
        g_s1SetPendingMs = now;      // HandsetClickSweep commits it past the double window
    }
}

// The candidate the PRESS EDGE recorded, answered at the button-up that carries
// no move (a motionless release emits no MOUSE_MOVE, P-BK-03). One candidate at a
// time: the row is consumed here, so a click can only be spent once.
//
// P-UI-98e: THIS IS ALSO THE GESTURE'S OWN END. The button-up mouse-move is the
// click path's sibling, and when it never arrives (the same P-BK-03 fact) the
// gesture stayed LIVE: the render kept skipping the line's writes, the borrowed
// draggable flag stayed off, and BOTH hand-set claims refused the next press until
// the 1.5 s heal — «جابجا میشه بعد دیگه نمیشه درگش کرد». So the finalize settles a
// live gesture first, and only asks the click question afterwards - and a gesture
// that WROTE a price is a drag by definition, never a click.
void Step1ClickFinalize()
{
    // P-UI-98h: A CLICK CAN BE DELIVERED ON THE PRESS - the measured MT4 fact
    // this codebase already knows from the panels (P-UI-49b / P-UI-73: «one of
    // those two is delivered on the PRESS that grabs a selectable object ...
    // the drag engaged and died immediately ... which is why it feels
    // random»). Every line below CONSUMES the row and reads the gesture as
    // over, so running it on that press echo settled the gesture the very
    // press had just claimed - the handle stopped following mid-drag - and,
    // because the gesture has not travelled a point yet, armed its deferred
    // SET against the line still under the hand: ~300 ms later the sweeper
    // committed it and no claim could start any more («هی قطع میشه موقع درگ
    // کردن», «راحت درگ نمیشه کردنش»). The witness is the project's ONE
    // button probe (P-UI-73): button still DOWN = this is the press's own
    // echo - touch NOTHING, and keep the row armed for the real release (the
    // button-up mouse move, or the click that follows it).
    if(!UILeftButtonUp()) return;
    string row = g_s1ClickRow;
    g_s1ClickRow = "";
    if(g_s1DragLive)
    {
        bool wrote = (g_s1OwnLastWrite > 0.0);
        Step1DragSettle();          // the release the mouse stream never delivered
        if(row == "" || wrote) return;
    }
    if(row == "") return;
    Step1HandleClickAt(row);
}

//+------------------------------------------------------------------+
//| P-UI-93 — ONE OWNER FOR THE WHOLE F TRANSITION.                    |
//|                                                                    |
//| The F key used to own this body inline, which is exactly why no     |
//| other surface could reach it: the panel's family rows had no way to  |
//| release the mute, so a press on a row that read OFF painted nothing  |
//| and snapped straight back. It is a function now, and the hotkey is   |
//| a short caller.                                                      |
//|                                                                    |
//| `hide` is the TARGET state, never a delta. The caller reads          |
//| IsIndicatorHidden() and inverts, so the state keeps exactly ONE      |
//| writer (SetIndicatorHiddenState) and ONE reader (IsIndicatorHidden) - |
//| the two cannot drift, which is what «همه رو هماهنگ کن» asks for.      |
//|                                                                    |
//| Returns the touched count from the show branch (-2 on the hide       |
//| branch, -1 when the cold-cache legacy scan ran) so the caller can    |
//| still log the P-PERF-31 provenance.                                  |
//+------------------------------------------------------------------+
int ApplyHideAllState(const bool hide)
{
    // P-PERF-26: the whole/level visibility switch is the action the user
    // repeats most, so its cost gets its own named line.
    // P-PERF-31: both directions now walk the object cache (plus the
    // cache size, which proves which path ran: cold-cache legacy scan
    // only right after attach).
    uint p26F = GetTickCount();
    // P-PERF-31: -2 = hide branch, -1 = cold-cache legacy scan,
    // >=0 = cache-walk writes issued by the show branch.
    int p31Touched = -2;
    // P-UI-93: the state write belongs to its ONE owner (GlobalVariables,
    // beside the reader). This used to be three inline lines that also
    // sanitised a corrupt gvar - the sanitiser moved with it.
    SetIndicatorHiddenState(hide);

    if(hide)
    {
        LOG_I(LOG_CAT_KEYS, "F key: Hiding all objects");
        // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
        // Cancel ABCD drawing session if active
        if(TH3SessionActive()) {
            TH3SessionCancel();
        }
#endif
        HideAllTHObjects();
        CleanupCustomPriceObjects(false, true);
        g_redrawTHLevelsNeeded = false;
    }
    else
    {
        LOG_I(LOG_CAT_KEYS, "F key: Showing all objects");
        // P-PERF-02: objects are visible again, so the once-per-
        // transition hide pass must be armed for the next F press.
        ResetHideAllState();
        // P-PERF-31: same decision tree the chart scan always had (ATR
        // state, trigger state, lines state), now over the object
        // cache — zero ObjectName calls, probes only for families the
        // names cannot decide. Legacy scan only on a cold cache.
        // P-PERF-41: the zone family switch is the FIFTH input. Without it
        // this branch repainted every zone rectangle OBJ_ALL_PERIODS - i.e.
        // an F press resurrected the exact family the Zones & Levels
        // switch had just turned off, and the two controls disagreed.
        //
        // P-UI-93: the families NOT named here are not a gap - the engine
        // re-asserts them on the very next frame, because each family's own
        // writer already carries `IsIndicatorHidden()` as one of its terms
        // (LabelFunctions / LevelPipeline / ObjectFunctions / UtilityFunctions
        // all read it), and this branch sets g_redrawTHLevelsNeeded below.
        // That shared term is also the answer to «چرا روی بقیه لیبلها تاثیر
        // میزاره»: the F mute is the ONE master the labels, the zones and the
        // level writer all answer to, by design.
        bool atrShouldShowF = (g_atrLabelsVisible && inpShowATRLabels);
        int shownTouched = VisibilityShowAllCached(atrShouldShowF, inpShowATRTargets,
                                                   g_triggerLevelsEnabled, g_linesVisible,
                                                   inpShowMidZones);
        p31Touched = shownTouched;
        // Restore label visibility
        ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
        ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
#endif
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        // P-UI-98p: no custom-line restore - the line is never painted (the
        // green circle is the placement), so the F cycle must not resurrect it
        // in any state.

        g_redrawTHLevelsNeeded = true;
        // Re-apply label visibility consistently
        string objectPrefixLocal = GetLevelObjectPrefix();
        SetATRLabelsVisibility(objectPrefixLocal, (g_atrLabelsVisible && inpShowATRLabels));
        SetTHLabelsVisibility(objectPrefixLocal, (inpShowTHLabels ? g_thLabelsMode : 0));
    }
    // P-PERF-02: masks written directly above → every stored mask is now
    // stale; the guarded writers must re-assert once on the next frame.
    BumpTfEpoch();
    g_redrawTHLevelsNeeded = true;
    P4ReportSlow("hide-all toggle (F) [hidden=" + (hide ? "1" : "0") +
                 " touched=" + IntegerToString(p31Touched) +
                 " cache=" + IntegerToString(CacheGetSize()) + "]",
                 GetTickCount() - p26F, P_P4_INIT_WARN_MS);
    return p31Touched;
}

//+------------------------------------------------------------------+
//| P-UI-93 — THE ONE WAY A CONTROL SURFACE RELEASES THE F MUTE.      |
//|                                                                   |
//| The F key and every family light / family row now answer the SAME  |
//| question (is this family painted?), so a press on a control that   |
//| READS OFF while the chart is muted has exactly one honest meaning: |
//| show me this again. Writing the family switch alone would change   |
//| nothing the user can see - the family is stored ON and would paint |
//| the moment the mute went - and the control would snap straight     |
//| back to OFF.                                                       |
//|                                                                   |
//| Both surfaces call this, never a copy of it: the ring's four       |
//| family items (BiotakMenu) and the panel's gated rows (BiotakPanels)|
//| are both included ABOVE this point in the entry, so this is the    |
//| lowest module that can own the transition for both. One walk, one  |
//| cache refresh, one forced frame.                                   |
//+------------------------------------------------------------------+
void ReleaseIndicatorMute()
{
    ApplyHideAllState(false);
    // A press repaints only its OWN control (P-UI-40's asymmetry), but the
    // mute sits on every family light and on every gated row of the open card.
    RequestUISync();
    // The walk wrote object masks directly, and the caller's own flags can be
    // REFRESH_NONE (the structure rows are exactly that), so the frame is
    // forced here - the same owner the F caller uses.
    RepaintForDiscreteAction();
}


void OnChartEventHandler(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // P-UI-114 (2026-09-23): right-click era deleted — terminal menu untouched,
    // strip opens on a LEFT hold (DrawStripHoldStep/PollAt in DrawStrip.mqh).

    // Base / Knot tool FIRST: while armed it owns every mouse gesture (no
    // chart-click leak into custom-price/TH3/panels), and committed boxes own
    // their badge/drag/delete events in every state.
    if(BaseKnotOnChartEvent(id, lparam, dparam, sparam)) return;

    // P-UI-100b (2026-09-22): THE DETECTOR OF "A FOREIGN OBJECT JUST APPEARED".
    //
    // A gesture of ours never creates a chart object; the terminal's own drawing
    // tools (a fib, a rectangle, a trend line) always do. An object that is NOT
    // ours, appearing while a hand-set line's gesture is live, is therefore the
    // one proof that the press which started it was a DRAW and not a grab — the
    // question the press edge itself cannot answer («وقتی فیو یا باکس از همون محل
    // میکشم کاستوم پرایس جابجا میشه»). The policy is CustomPriceForeignDrawSeen;
    // this branch owns the name test, beside the delete branch's own.
    //
    // Cost: ONE event, and events of this kind arrive when the user draws
    // something — never per tick, never per frame. Our own creates are filtered
    // out by the prefix, which is also what keeps them from being read as the
    // user's (the same test the delete branch below needs).
    if(id == CHARTEVENT_OBJECT_CREATE && sparam != "")
    {
        int createPrefixLen = StringLen(inpObjectPrefix);
        bool createdByUs = (createPrefixLen > 0 && StringLen(sparam) >= createPrefixLen &&
                            StringSubstr(sparam, 0, createPrefixLen) == inpObjectPrefix);
        if(!createdByUs)
        {
            // P-DRAW-01 (2026-09-22): AND THE USER'S OWN DRAWING IS STYLED THE
            // MOMENT IT EXISTS. This is the other half of «آخرین تغییرات ذخیره
            // بشه»: every edit the drawing toolbar makes is remembered per KIND,
            // and a fresh object of that kind wears the memory here — before the
            // user can see it in the terminal's own look. A kind the user has
            // never styled is left exactly as MT4 drew it (the memory answers
            // "untouched"), and the indicator's own objects never reach this
            // branch (the prefix test above is the same one the delete branch
            // below uses).
            DrawStyleApplyOnCreate(sparam);
            CustomPriceForeignDrawSeen();
        }
    }

    // P-TICKWRAP: the window is asked through its owner, never compared against
    // GetTickCount() directly — an absolute compare stays true forever after the
    // 49.7-day counter wrap, and then EVERY delete would be ignored for the rest of
    // the cycle (see TickDeadlinePending in GlobalVariables).
    bool suppressDeleteEvent = g_suppressDeleteEvents || TickDeadlinePending(g_suppressDeleteEventsUntilMs);
    if(id == CHARTEVENT_OBJECT_DELETE && !suppressDeleteEvent) {
        string indicatorPrefix = inpObjectPrefix;
        int prefixLen = StringLen(indicatorPrefix);
        // P-BK-01: Base/Knot deletes are owned by BaseKnotTool (cascade/heal) —
        // they must not flag a level redraw or pollute the object cache.
        if(prefixLen > 0 && StringLen(sparam) >= prefixLen && StringSubstr(sparam, 0, prefixLen) == indicatorPrefix &&
           StringFind(sparam, "_BK_") < 0) {
            CacheRemoveObject(sparam);
            g_redrawTHLevelsNeeded = true;
            // P-PERF-02: a level vanished behind our back — the stored geometry
            // signature no longer describes the chart, so the next frame must
            // rebuild for real (this is the self-heal the per-object ObjectFind
            // used to provide on every frame).
            MarkDrawGeneration();
        }
    }
    // P-UI-98j: EVEN A SUPPRESSED DELETE IS VERIFIED FOR THE STEP-1 PAIR. Our
    // own bulk deletes never name a live handle (the surplus sweep starts past
    // it, the foreign sweep runs on handoff with a fresh stash), so a stashed
    // handle name that is really gone is an external delete that fell inside
    // the 250 ms window - and ignoring it is exactly the stuck-missing line
    // («ناپدید میشه ... دیگه نمیشه جابجاش کرد»). One probe, then the same two
    // lines as above; a live gesture is left to the settle (it owns recovery).
    else if(id == CHARTEVENT_OBJECT_DELETE && suppressDeleteEvent && sparam != "" &&
            !g_s1DragLive && g_thStartPointType == TH_START_POINT_CUSTOM_PRICE &&
            g_s1MarkPeriod == Period() &&
            (sparam == g_s1MarkAboveName || sparam == g_s1MarkBelowName) &&
            ObjectFind(0, sparam) < 0)
    {
        CacheRemoveObject(sparam);
        g_redrawTHLevelsNeeded = true;
        MarkDrawGeneration();
    }

    // VIEWLOCK-OFF:
    //if(id == CHARTEVENT_OBJECT_DELETE && !suppressDeleteEvent && sparam == g_viewAnchorLineName && g_viewLockEnabled) {
    //    ViewLockSetEnabled(false);
    //    ThrottledChartRedraw();
    //    return;
    //}

    if(id == CHARTEVENT_KEYDOWN)
    {
#ifndef BUILD_LITE
        // Hex edit box owns the keyboard (palette color field): A-F are valid
        // hex digits, so every letter hotkey below must stay silent while the
        // user types. ESC/ENTER still reach the palette via HandleUIChartEvent.
        // Same for the Base Box TEXT field (TV-parity 2026-09-07 — any letter
        // is valid box text).
        if(g_PalHexFocus || g_BkTextFocus) return;
#endif
        // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
        // Backspace = undo last TH3 drawing point (X, A, B, C placement)
        if((int)lparam == 8 && TH3SessionActive()) {
            TH3SessionUndo();
            return;
        }
#endif

        //
        // F key   Hide/Show All Objects (fast visibility toggle)
        //

        if(IsHotkeyPressed(lparam, sparam, inpHideKey))
        {
            // P-UI-93: the whole transition moved into ONE owner
            // (`ApplyHideAllState`, above the handler), because the panel's
            // family rows had no other way to reach it - that was half of
            // «این دکمه های با پنل هماهنگ نیستش».
            //
            // The target state is READ from the mute's own reader and
            // inverted, never re-derived from the raw GlobalVariable here:
            // exactly one writer (SetIndicatorHiddenState) and one reader
            // (IsIndicatorHidden) exist, so they cannot drift.
            ApplyHideAllState(!IsIndicatorHidden());
            // P-UI-93: the panel's visibility rows DISPLAY this mute
            // (PnlCurrentSet), and this file is compiled before the panel, so
            // the repaint has to be asked for - exactly what the L / A / D /
            // T / S / E hotkeys already do. Without this the rows keep
            // claiming their family is painted while the chart is blank.
            RequestUISync();
            // P-PERF-24: one owner for "a discrete action paints now" - it
            // forces the repaint even while hidden, which is what the old bare
            // ChartRedraw() here was working around.
            RepaintForDiscreteAction();
            return;
        }

        //  
        // L key   Toggle Lines Visibility (all LINE objects - not boxes)
        //  
        if(IsHotkeyPressed(lparam, sparam, inpLinesToggleKey))
        {
            // P-PERF-29: the switch's state, mirror, cache, persisted key and
            // object MASK all live in one owner now - the panel rows and the
            // factory reset used to raise the flag WITHOUT writing the mask,
            // which the P-PERF-25 skip then trusted and painted nothing.
            bool p26want = !g_linesVisible;
            // P-PERF-22: this was a full-chart walk - ObjectsTotal(0,-1,-1) then
            // ObjectName + ObjectGetInteger for EVERY object on the chart, ours
            // or not, plus one TIMEFRAMES write per line whether or not the mask
            // changed. The same repair already existed, correct, in
            // VisibilityManager (SetAllLineObjectsVisibility): it walks the
            // OBJECT CACHE - only our own objects, no ObjectName calls - and it
            // keeps this hotkey's exclusions (F-key border segments, _BK_
            // trade rays). It had no callers; it does now. It also bumps the
            // P-PERF-02 epoch itself, so the guards re-assert once.
            // P-PERF-26: the switch's own cost is measured, not guessed - on the
            // old shape a bare press had no line of its own (the event ledger
            // reports the whole event and the mask walk is the only work here).
            uint p26t = GetTickCount();
            SetLinesVisible(p26want, true);
            // P-UI-40: the ZONES card's SHOW LINES row and the LINES card display
            // this switch, and this path cannot repaint them (panel file comes
            // later). Ask the UI layer — the row reads the live flag, only its
            // IMAGE is stale.
            RequestUISync();
            P4ReportSlow("lines toggle (L) [lines=" + (g_linesVisible ? "1" : "0") + "]",
                         GetTickCount() - p26t, P_P4_MOVE_WARN_MS);
            LOG_I(LOG_CAT_LINES, "Lines " + (g_linesVisible ? "VISIBLE" : "HIDDEN"));
            // P-PERF-24: a key press is one event - paint it now instead of
            // waiting for the next tick to pass the 100 ms throttle.
            RepaintForDiscreteAction();
            return;
        }

        //  
        // C key   Set Custom Price
        //  
        if(IsHotkeyPressed(lparam, sparam, inpCustomPriceKey))
        {
            g_waitingForCustomPriceClick = true;
            g_customPriceKeyboardOverride = true;
            _LOG_GATE_D Print("[D][GEN] Press anywhere on the chart to set custom TH start price");
            ObjectDelete(0, g_customPriceHorizontalLineName);
            g_customPriceLineCreated = false;
            // P-UI-98d v2: the line is born at the vertical middle of the VISIBLE
            // chart — wherever the user has scrolled («هر جایی که کاربر هست وسط
            // صفحه ظاهر بشه») — the market's last price is only the fallback.
            double currentPrice = ScreenMiddlePrice();
            if(!(currentPrice > 0.0))
                currentPrice = iClose(_Symbol, CompatTF(GetCachedPeriod()), 0);
            g_customTHStartPrice = currentPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            HandsetPlacementArm();   // P-UI-98e: the fresh line and its handles wake draggable
            // P-UI-56: ONE writer for the placement pair (this chart's price + flag).
            CustomPricePersistPlacement(currentPrice);
            // P-UI-48: ONE creator. This block used to write the line's whole
            // property set by hand - the fifth copy of it in the file, and the
            // place a stale OBJPROP_SELECTED had survived longest.
            if(!CreateCustomPriceLine(currentPrice, Digits)) return;
            HandsetMarkersRide();   // the green handle is born with its line
            g_redrawTHLevelsNeeded = true;
            _LOG_GATE_D Print("[D][GEN] [PIN] Custom price set to: ", DoubleToString(currentPrice, Digits), " - Drag to adjust.");
            ThrottledChartRedraw();
            return;
        }

        //  
        // ESC key   Cancel Custom Price
        //  
        if(lparam == 27)
        {
            // P-UI-56: the active test reads THIS CHART's key (the resolver's own
            // owner). Reading the old symbol-scoped key would have made ESC a no-op
            // on a chart whose placement lives under the chart-scoped name.
            bool customPriceActive = GlobalVariableCheck(CustomPriceGVName());
            if(g_waitingForCustomPriceClick || customPriceActive || g_customPriceKeyboardOverride)
            {
                // P-UI-45: the sequence itself lives in ONE owner - the ring's PIN
                // item's OFF press runs the very same one.
                DeactivateCustomPriceMode("ESC");
                ThrottledChartRedraw();
                return;
            }
        }

        //  
        // T key   Toggle Trigger Zones (overlay only — unified lines are
        //         unaffected; line visibility belongs to the L key)
        //
        if(IsHotkeyPressed(lparam, sparam, inpTriggerLevelsKey))
        {
            g_triggerLevelsEnabled = !g_triggerLevelsEnabled;
            RequestUISync();   // P-UI-40: the TRIGGER card's SHOW row + the ring badge
            string triggerGvarName = "Biotak_TriggerLevels_" + GetCachedChartIdStr();
            GlobalVariableSet(triggerGvarName, g_triggerLevelsEnabled);
            if(g_triggerLevelsEnabled) {
                LOG_I(LOG_CAT_KEYS, "Trigger Zones: ON");
            } else {
                LOG_I(LOG_CAT_KEYS, "Trigger Zones: OFF");
            }
            // P-PERF-21: NO force-clear. The overlay owns ONE family - the
            // trigger zones - and RenderZones applies the live flag itself, so
            // this is a re-render, never a wipe: structure lines, zones and
            // labels are not deleted and re-materialised, and the geometry cache
            // (which no longer keys on the flag) answers with the identical
            // lists instead of recomputing them.
            g_redrawTHLevelsNeeded = true;
            if(!g_customPriceLineDragging)
                RedrawAllObjects(true);
            ThrottledChartRedraw();
            return;
        }

        //  
        // A key   Toggle ATR Labels
        //  
        if(IsHotkeyPressed(lparam, sparam, inpATRLabelsKey))
        {
            string atrGvarNameKey = "Biotak_ATRLabels_" + GetCachedChartIdStr();
            g_atrLabelsVisible = !g_atrLabelsVisible;
            RequestUISync();   // P-UI-40: the ATR card's own rows show this switch
            g_showATRLabels = g_atrLabelsVisible;   // keep the ATR card mirror in sync
            GlobalVariableSet(atrGvarNameKey, g_atrLabelsVisible ? 1.0 : 0.0);
            
            string objectPrefix = GetLevelObjectPrefix();
            SetATRLabelsVisibility(objectPrefix, g_atrLabelsVisible); 
            g_labelsRelayoutNeeded = true;
            RedrawLabelsOnly();
            LOG_I(LOG_CAT_LABELS, "ATR Labels " + (g_atrLabelsVisible ? "VISIBLE" : "HIDDEN"));
            ThrottledChartRedraw();
            return;
        }

        //  
        // S key   Cycle TH Labels Mode
        //  
        //
        // D key   Toggle the bar-close countdown tag. Its OWN switch: the ATR
        //         labels key (A) must never take the countdown away, and this
        //         one never touches the ATR block (2026-09-11, user request).
        //  
        if(IsHotkeyPressed(lparam, sparam, inpCountdownKey))
        {
            g_showLiveCountdown = !g_showLiveCountdown;
            RequestUISync();   // P-UI-40: COUNTDOWN card row 0 shows this switch
            RuntimeSettingsSaveOverridesThrottled();   // OV_ CD/CDC/CDS/CDG
            RefreshLiveCountdown();
            LOG_I(LOG_CAT_LABELS, "Countdown tag " + (g_showLiveCountdown ? "VISIBLE" : "HIDDEN"));
            ThrottledChartRedraw();
            return;
        }

        if(IsHotkeyPressed(lparam, sparam, inpTHLabelsKey))
        {
            string thGvar = "Biotak_THLabels_" + GetCachedChartIdStr();
            
            // Cycle exclusive: ON -> OFF (remembers), OFF -> remembered ON (default STANDARD).
            if(g_thLabelsMode != 0) {
                g_thLabelsMode = 0;
            }
            else {
                g_thLabelsMode = g_thLastOnMode;
                if(g_thLabelsMode == 0) g_thLabelsMode = 2;
            }

            g_thLabelsVisible = (g_thLabelsMode != 0);
            RequestUISync();   // P-UI-40: the TH LABELS card cycles on this mode
            SyncTHFlagsFromMode();   // flags follow the mode → card never disagrees
            GlobalVariableSet(thGvar, (double)g_thLabelsMode);
            
            string objectPrefix = GetLevelObjectPrefix();
            SetTHLabelsVisibility(objectPrefix, g_thLabelsMode);
            g_labelsRelayoutNeeded = true;
            RedrawLabelsOnly();
            string logMsg = "TH Labels mode=" + IntegerToString(g_thLabelsMode) + " (0=OFF,1=FRACTAL,2=STANDARD)";
            LOG_I(LOG_CAT_LABELS, logMsg);
            ThrottledChartRedraw();
            return;
        }

        //
        // V key   Toggle TH3 Tool — TH3TOOL-ON (2026-09-19): restored.
        //
#ifndef BUILD_LITE
        if(IsHotkeyPressed(lparam, sparam, inpTH3ToolKey))
        {
            ToggleTH3Tool();
            ThrottledChartRedraw();
            return;
        }
#endif

        //
        // P key   Arm the leg meter (a measurement only).
        // P-TH3-PB-OFF (2026-09-21): the old coupling that stored a dragged leg
        // on the active pattern as its pivot base is retired — the base is
        // hand-typed in the TH3 TOOL card (`inpTH3PivotBasePips`), never drawn.
        //
#ifndef BUILD_LITE
        if((int)lparam == 80)   // 'P' — toggle Leg Measure session (same as ring CIR_LEG)
        {
            LegMeasureToggle();
            ThrottledChartRedraw();
            return;
        }
#endif

        //
        // B key   Arm/cancel the TH3 base mark: two clicks pin the base height
        // (P-TH3-PB-UI) — no drag, so scrolling between the clicks stays free.
        //
#ifndef BUILD_LITE
        if((int)lparam == 66)   // 'B' — arm/cancel the base mark
        {
            TH3BaseMarkToggle();
            ThrottledChartRedraw();
            return;
        }
#endif

        // E key   Cycle Step Mode (TH → SS-LS → Combo → Factor → TH).
        // Single mode: E writes the base directly — same value the Tools
        // ring item and the panel STEP MODE row write. GetCurrentStepMode()
        // just returns it.
        if(IsHotkeyPressed(lparam, sparam, inpStepModeKey))
        {
            RequestUISync();   // P-UI-40: the STEP card's mode row + the ring badge
            g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)(((int)GetCurrentStepMode() + 1) % 4);
            GlobalVariableDel("Biotak_StepMode_" + GetCachedChartIdStr());   // purge retired override key
            RuntimeSettingsSaveOverridesThrottled();   // persist OV_ SM now (E bypasses ApplyRefreshFlags)
            LOG_IP1(LOG_CAT_KEYS, "Step Mode changed to: ", GetStepModeName(GetCurrentStepMode()));
            g_forceClearOnNextDraw = true;
            g_redrawTHLevelsNeeded = true;
            g_calculatedOnce = false;
            RedrawAllObjects(true);
            RefreshComboLabelExtraInfo();
            UpdateStepModeLabel();
            ThrottledChartRedraw();
            return;
        }

        //  
        // 1/2 keys   Adjust Factor (always active)
        //  
        if(lparam == '1') { AdjustFactorValue(-1); return; }
        else if(lparam == '2') { AdjustFactorValue(+1); return; }

        //
        // 3/4 keys   Adjust TH3 Frequency — TH3TOOL-ON (2026-09-19): restored.
        //
#ifndef BUILD_LITE
        else if(lparam == '3') { DecrementTH3Frequency(); return; }
        else if(lparam == '4') { CycleTH3Frequency(); return; }
#endif

        //  
        // W key   Show Current Status
        //  
        if(IsHotkeyPressed(lparam, sparam, inpShowStatusKey))
        {
            RefreshComboLabelExtraInfo();
            ShowAllStatusLabels();
            ThrottledChartRedraw();
            return;
        }

        //  
        // R key   Reset All Overrides
        //  
        if(IsHotkeyPressed(lparam, sparam, inpResetKey))
        {
            // STEPOVERRIDE-OFF: single Step Mode — Q resets the base + levels
            // to factory, like the panel Reset does.
            g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)(int)FactoryDefault(FF_STEP_CALC_MODE);
            g_maxLevels = (int)FactoryDefault(FF_MAX_LEVELS);
            g_comboMode = (ENUM_COMBO_MODE)(int)FactoryDefault(FF_COMBO_MODE);
            g_comboPreset = (ENUM_COMBO_PRESET)(int)FactoryDefault(FF_COMBO_PRESET);
            g_comboComp1TF = (ENUM_COMBO_TIMEFRAME_TYPE)(int)FactoryDefault(FF_COMBO_C1TF);
            g_comboComp1Step = (ENUM_COMBO_STEP_TYPE)(int)FactoryDefault(FF_COMBO_C1STEP);
            g_comboOp1 = (ENUM_COMBO_OPERATION)(int)FactoryDefault(FF_COMBO_OP1);
            g_comboComp2Enabled = (FactoryDefault(FF_COMBO_C2ON) > 0.5);
            g_comboComp2TF = (ENUM_COMBO_TIMEFRAME_TYPE)(int)FactoryDefault(FF_COMBO_C2TF);
            g_comboComp2Step = (ENUM_COMBO_STEP_TYPE)(int)FactoryDefault(FF_COMBO_C2STEP);
            g_factorValueOverride = 0;
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            g_th3FreqOverride = 0;
            g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
#endif
            g_timeframeLocked = false;
            g_lockedPeriod = 0;
            // inpX is the runtime copy after the RuntimeSettings #defines —
            // restoring from the captured factory defaults instead (reading
            // inpX here is a self-assign no-op that kept the current values).
            g_triggerLevelsEnabled = (FactoryDefault(FF_TRIGGER_SHOW) > 0.5);
            // P-PERF-29: same owner as the hotkey and the panel rows, so the
            // restore writes the mask too (it used to leave the objects as they
            // were, which only a timeframe switch repaired).
            SetLinesVisible(FactoryDefault(FF_SHOW_LINES) > 0.5, false);
            InvalidateAllVisibilityCaches();
            g_atrLabelsVisible = (FactoryDefault(FF_SHOW_ATR) > 0.5);
            g_showLiveCountdown = (FactoryDefault(FF_SHOW_COUNTDOWN) > 0.5);
            g_countdownColor = (color)(int)FactoryDefault(FF_COUNTDOWN_COLOR);
            g_countdownFontSize = (int)FactoryDefault(FF_COUNTDOWN_SIZE);
            g_countdownGapPx = (int)FactoryDefault(FF_COUNTDOWN_GAP);
            RefreshLiveCountdown();
            g_thLabelsMode = (FactoryDefault(FF_SHOW_TH_LABELS) > 0.5) ? 2 : 0; // Default STANDARD if enabled
            g_thLabelsVisible = (g_thLabelsMode != 0);
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            if(inpEnableTH3Tool) {
                UpdateAllTH3Objects();
            }
#endif
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            // Cancel any active ABCD drawing session
            if(TH3SessionActive()) {
                TH3SessionCancel();
            }
#endif
            g_customPriceKeyboardOverride = false;
            g_thStartPointType = inpTHStartPointType;
            g_customTHStartPrice = inpCustomTHStartPrice;
            string chartIdStr = GetCachedChartIdStr();
            string symbolName = GetCachedSymbol();
            GlobalVariableDel("Biotak_StepMode_" + chartIdStr);
            // P-UI-67: the reset drops the override through its owner (state + key),
            // so the panel's SS/LS ORDER switch is the answer again.
            SSLSOrderOverrideClear();
            // P-UI-40: the reset key rewrites nearly every displayed state, so
            // the whole UI layer (ring states, badges, the open card) must be
            // told once. This is also how the reset path already behaved when it
            // was reached from the panel (PnlResetItem does exactly this pair).
            RequestUISync();
            GlobalVariableDel("Biotak_Factor_" + chartIdStr);
            GlobalVariableDel("Biotak_LockTF_" + chartIdStr);
            GlobalVariableDel("Biotak_LockTFPeriod_" + chartIdStr);
            // VIEWLOCK-OFF: if(g_viewLockEnabled) ViewLockSetEnabled(false);
            GlobalVariableDel("Biotak_ViewLock_" + chartIdStr);   // VIEWLOCK-OFF: purge only
            GlobalVariableDel("Biotak_ViewAnchorT_" + chartIdStr);
            GlobalVariableDel("Biotak_ViewAnchorMin_" + chartIdStr);
            GlobalVariableDel("Biotak_ViewAnchorMax_" + chartIdStr);
            GlobalVariableDel("Biotak_TriggerLevels_" + chartIdStr);
            GlobalVariableDel("Biotak_LinesVisible_" + chartIdStr);
            GlobalVariableDel("Biotak_ATRLabels_" + chartIdStr);
            GlobalVariableDel("Biotak_THLabels_" + chartIdStr);
            // P-UI-56: the Q reset drops THIS CHART's placement (both keys) through
            // their owner; the Input seed needs no key at all (the resolver reads it
            // directly), so the old "seed the price key from the Input" write is gone
            // - it was the same key that made an Input-seeded chart look like a
            // placement on the chart that shares its symbol.
            CustomPriceForgetPlacement();
            // P-UI-98: the reset returns the step to the mode's own answer too.
            StepOverrideFactorReset();
            // P-UI-98d: the hand-set lines wake ARMED again and their markers go
            // (the redraw below re-creates what the fresh state wants).
            g_cpLineArmed = true;
            g_s1LinesArmed = true;
            g_s1MarkAbovePrice = 0.0;
            g_s1MarkBelowPrice = 0.0;
            ObjectDelete(0, g_cpMarkerName);      CacheRemoveObject(g_cpMarkerName);
            ObjectDelete(0, S1MarkName(1));       CacheRemoveObject(S1MarkName(1));
            ObjectDelete(0, S1MarkName(-1));      CacheRemoveObject(S1MarkName(-1));
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            GlobalVariableDel("Biotak_TH3Freq_" + chartIdStr);
            GlobalVariableDel("Biotak_TH3FreqIdx_" + chartIdStr);
#endif
            if(inpCustomTHStartPrice > 0.0) {
                CreateCustomPriceLine(inpCustomTHStartPrice, Digits);
            } else {
                ObjectDelete(0, g_customPriceHorizontalLineName);
                g_customPriceLineCreated = false;
            }
            UpdateLockStatusLabel();
            Comment("\n\n        [ RESET ]");
            g_resetCommentCreateTime = GetTickCount();
            LOG_I(LOG_CAT_KEYS, "Reset: All overrides cleared");
            ClearAllModeLabels();
            EventSetMillisecondTimer(250);   // keep 250 ms cadence (see OnInit)
            g_forceClearOnNextDraw = true;
            g_calculatedOnce = false;
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            ThrottledChartRedraw();
            return;
        }

        //
        // X key   On-demand diagnostic dump ([TRADEPLAN]+[SNAP]+[ATRLEGS]+[PROF*])
        //         No background auto-logging — this key is the only writer.
        //
        if(IsHotkeyPressed(lparam, sparam, inpLogDumpKey))
        {
            TradePlanDumpNow();
            return;
        }

        //
        // K key   Toggle Timeframe Lock
        //  
        if(IsHotkeyPressed(lparam, sparam, inpLockKey))
        {
            bool hadCustomPrice = (ObjectFind(0, g_customPriceHorizontalLineName) >= 0);
            double savedCustomPrice = hadCustomPrice ? ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0) : 0;
            // P-BK-17: the old raw ObjectsDeleteAll(0, inpObjectPrefix) wiped
            // the user's Base/Knot boxes too — and the registry rebuilds from
            // box anchors, so deleted boxes never came back. Guarded loop like
            // DeleteAllIndicatorObjects(false) (inlined: that fn is defined
            // below this caller — P-ARCH-02).
            g_suppressDeleteEvents = true;
            if(StringLen(inpObjectPrefix) > 0) {
               int lkTotal = ObjectsTotal(0, -1, -1);
               int lkPlen = StringLen(inpObjectPrefix);
               for(int lki = lkTotal - 1; lki >= 0; lki--) {
                  string lkName = ObjectName(0, lki, -1, -1);
                  if(StringLen(lkName) < lkPlen) continue;
                  if(StringSubstr(lkName, 0, lkPlen) != inpObjectPrefix) continue;
                  if(StringFind(lkName, "_BK_") >= 0) continue;
                  ObjectDelete(0, lkName);
               }
            }
            g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
            g_suppressDeleteEvents = false;
            g_timeframeLocked = !g_timeframeLocked;
            RequestUISync();   // P-UI-40: the lock badge is derived from this state
            if(g_timeframeLocked)
            {
                g_lockedPeriod = GetCachedPeriod();
                LOG_I(LOG_CAT_KEYS, "Timeframe LOCKED to: " + GetCurrentTimeframe());
                _LOG_GATE_D Print("[D][GEN] [LOCK] Timeframe locked to: ", GetCurrentTimeframe());
            }
            else
            {
                LOG_I(LOG_CAT_KEYS, "Timeframe UNLOCKED - following chart: " + GetCurrentTimeframe());
                _LOG_GATE_D Print("[D][GEN] [UNLOCK] Timeframe unlocked - now following chart timeframe: ", GetCurrentTimeframe());
            }
            UpdateLockStatusLabel();
            string lockChartIdStr = GetCachedChartIdStr();
            string lockFlagName = "Biotak_LockTF_" + lockChartIdStr;
            GlobalVariableSet(lockFlagName, g_timeframeLocked);
            string lockPeriodName = "Biotak_LockTFPeriod_" + lockChartIdStr;
            GlobalVariableSet(lockPeriodName, g_lockedPeriod);
            g_forceClearOnNextDraw = true;
            g_calculatedOnce = false;
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            if(hadCustomPrice && savedCustomPrice > 0) {
                g_customTHStartPrice = savedCustomPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
                // P-UI-48: the owner, not another hand-written property set.
                CreateCustomPriceLine(savedCustomPrice, Digits);
            }
            ThrottledChartRedraw();
            return;
        }

        // VIEWLOCK-OFF: V key (View Lock) retired —
        //if(IsHotkeyPressed(lparam, sparam, inpViewLockKey))
        //{
        //    ViewLockSetEnabled(!g_viewLockEnabled);
        //    LOG_I(LOG_CAT_KEYS, "View Lock " + (g_viewLockEnabled ? "ON - view follows across timeframes" : "OFF - chart behaves normally"));
        //    ThrottledChartRedraw();
        //    return;
        //}
    } // end CHARTEVENT_KEYDOWN

    //
    // Leg Measure MOUSE_MOVE routing — drag-to-draw, runs before ABCD.
    // MOUSE_MOVE is needed so we get left-button press/hold/release edges.
    // P-TH3-PERF-07: CHART_EVENT_MOUSE_MOVE is chart-scoped and shared with
    // the ring, panels and BaseKnot — its ONE writer is OnInitHandler.
    // LegMeasure piggybacks on the existing MOUSE_MOVE stream; no extra flag write.
    //
    // P-UI-98e: a MOTIONLESS press/release emits no MOUSE_MOVE (P-BK-03), so a
    // still click on a step-1 handle would never reach the release latch — the
    // leg meter's own P-LM-13 trap, on the hand-set lines. The click DOES fire
    // CHARTEVENT_CLICK on button-up, and it is the only edge that sees this case.
    //
    if(id == CHARTEVENT_CLICK) Step1ClickFinalize();
    if(id == CHARTEVENT_CLICK) CustomPriceRearmFinalize();   // P-UI-98m: the still click on a SET line

#ifndef BUILD_LITE
    if(id == CHARTEVENT_MOUSE_MOVE && LegMeasureSessionActive())
    {
        if(LegMeasureMouseMove((int)lparam, (int)dparam, sparam))
            ThrottledChartRedraw();
        // Do NOT return — ABCD also needs MOUSE_MOVE for its own hover preview.
    }

    // P-LM-11: the leg's EDIT owner. The family is not selectable any more — the
    // line, its two rings and its mid handle are OURS — so the drag is not a
    // native one the terminal reports, it is THIS pass: a press hit-tests the
    // family in screen pixels, and every held move rewrites the whole drawing
    // from the same anchors in the same event. Nothing follows anything, so
    // nothing can lag behind (the report P-LM-10 could only chase).
    if(id == CHARTEVENT_MOUSE_MOVE && LegMeasureEditMouse((int)lparam, (int)dparam, sparam))
        ThrottledChartRedraw();

    // P-LM-08/P-LM-11: the object list is the one native delete the family still
    // answers (nothing of it is selectable) — deleting the LINE there cascades to
    // the rings, the mid handle, the plate and its three lines here.
    if(id == CHARTEVENT_OBJECT_DELETE)
        LegMeasureOnObjectDelete(sparam);

    // P-LM-13: a MOTIONLESS press/release emits no MOUSE_MOVE on release (an MT4
    // fact), but the click still fires CHARTEVENT_CLICK on button-up — so this is
    // where a still press on the family ends. Without it the drag state stuck
    // live: the view lock stayed held, the plate hung, and the Delete key found
    // no selection («چرا نمیشه حذفش کرد»).
    if(id == CHARTEVENT_CLICK) LegMeasureClickFinalize();

    // P-LM-20: the terminal's OWN selection event. A still click on the (now
    // selectable, P-LM-17) line reports OBJECT_CLICK, not a mouse move — so the
    // selection changed between two of our ride passes and the face assembled
    // itself from pieces that disagreed (the line widened while the discs kept
    // the resting rasters: «موقع سلکت دایره‌ها بهم مریزه»). The terminal names
    // the object it selected; the family answers in ONE atomic repaint. A click
    // anywhere ELSE deselects the line, and this is the only handler that sees
    // that path too — a repaint per leg in the registry answers it (the ride
    // pass re-reads every flag, so a cleared selection is painted back).
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(LegMeasureOnObjectClick(sparam)) ThrottledChartRedraw();
        else LegMeasureRideChart();   // a click off the family: deselection lands whole
    }
#endif

    //
    // ABCD Mouse Event Routing — TH3TOOL-ON (2026-09-19): restored.
    // P-TH3-PB-UI: the armed base mark rides the same dispatcher (its CLICK
    // channel), so the router must wake for it even with no draw session.
#ifndef BUILD_LITE
    if(TH3SessionActive() ||
       TH3BaseMarkArmed() ||
       id == CHARTEVENT_OBJECT_DRAG ||
       id == CHARTEVENT_OBJECT_DELETE ||
       id == CHARTEVENT_MOUSE_MOVE) {
        OnABCDMouseEvent(id, lparam, dparam, sparam);
        if((TH3SessionActive() || TH3BaseMarkArmed()) && id == CHARTEVENT_CLICK) {
            return;
        }
    }
#endif

    //  
    // CHARTEVENT_CHART_CHANGE   Layout/Resize/Scroll/Zoom
    //  
    if(id == CHARTEVENT_CHART_CHANGE) {
        if(IsIndicatorHidden()) return;
        HandsetMarkersRide();   // P-UI-98d v2: the handles ride every layout change
        static uint s_lastLayoutMs = 0;
        static int s_lastW = -1;
        static int s_lastH = -1;
        static double s_lastVisibleMin = 0;
        static double s_lastVisibleMax = 0;
        static bool s_ccPrimed = false;   // P-PERF-28
        uint nowMs = GetTickCount();
        if(nowMs - s_lastLayoutMs < CHART_CHANGE_THROTTLE_MS) return;

        int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
        int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
        bool sizeChanged = (w != s_lastW || h != s_lastH);
        
        double visibleMin = ChartGetDouble(0, CHART_PRICE_MIN);
        double visibleMax = ChartGetDouble(0, CHART_PRICE_MAX);
        bool viewportChanged = (MathAbs(visibleMin - s_lastVisibleMin) > GetCachedPoint() ||
                                MathAbs(visibleMax - s_lastVisibleMax) > GetCachedPoint());
        // P-PERF-28: on the FIRST chart-change of an instance the snapshot is
        // still at its zero value, so `visibleMin - 0` is always > one point and
        // `viewportChanged` was unconditionally TRUE. That ran a full
        // RedrawAllObjects(false) inside the event on every attach and every
        // timeframe switch — the live log charges it to the event as
        //   [W][PERF] chart event id=9 [indicator=3375 ui=0] took 3375ms
        // (and 3750/3938/3766/3734/4063 ms in the same session, 53 such events
        // in one day). Nothing had actually changed: this instance's own initial
        // draw already covers the viewport it is looking at. Prime the snapshot
        // from the live chart instead of from 0 and the first event is a no-op.
        if(!s_ccPrimed)
        {
            s_ccPrimed = true;
            viewportChanged = false;
        }
        
        if(!sizeChanged && !viewportChanged) return;
        
        s_lastW = w;
        s_lastH = h;
        s_lastVisibleMin = visibleMin;
        s_lastVisibleMax = visibleMax;
        s_lastLayoutMs = nowMs;
        // VIEWLOCK-OFF: if(g_viewLockEnabled) ViewLockCapture();

        // P-PERF-28b: this branch was the biggest single stall in the log yet
        // had no sub-ledger of its own, so the named owner can only be guessed.
        // Split it the way every other ledger here is split, and only print
        // when the branch blows the event budget.
        uint p28t = GetTickCount();
        uint p28redraw = 0, p28labels = 0, p28leg = 0;
        if(sizeChanged) g_labelsRelayoutNeeded = true;
        if(viewportChanged) {
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(false);
            p28redraw = GetTickCount() - p28t;
        } else if(sizeChanged) {
            RedrawLabelsOnly();
            p28labels = GetTickCount() - p28t;
        }
        p28t = GetTickCount();
        // The live-price countdown tag is positioned off the price scale, so a
        // scroll/zoom/resize invalidates its Y even with zero ticks (weekend
        // charts). Re-derive it here, AFTER the redraws above (a label clear
        // would otherwise eat it) — the label pipeline itself is 2 s gated, so
        // this hook is what keeps the tag glued during a drag-scroll. Own
        // switch: never gated by the ATR block (2026-09-11).
        RefreshLiveCountdown();
        uint p28count = GetTickCount() - p28t;
        p28t = GetTickCount();
        // P-LM-02: the leg-measure readouts are SCREEN objects, so the chart moving
        // under them does not move them — and this branch is the one place that
        // already answers "the chart moved" (scroll, zoom, resize, auto-scroll).
        // The projection is READ-GUARDED: a box already where it belongs costs a
        // handful of terminal reads and not one ObjectSet* (P-PERF-02).
#ifndef BUILD_LITE
        LegMeasureFollowAll();
#endif
        p28leg = GetTickCount() - p28t;
        p28t = GetTickCount();
        ThrottledChartRedraw();
        uint p28paint = GetTickCount() - p28t;
        if(p28redraw + p28labels + p28leg + p28count + p28paint >= P_P4_EVENT_WARN_MS)
        {
            // P-PERF-49 (2026-09-16) - `tail=` HAD NO OWNER, AND IT WAS THE WHOLE
            // STALL. The live MT5 log:
            //   chart change breakdown: redraw=0ms labels=390ms tail=3016ms
            //   chart event CHART_CHANGE(id=9) [indicator=3485 ...] took 3485ms
            // so P-PERF-28b's split ended exactly where the biggest number began:
            // the tail is RefreshLiveCountdown() + ThrottledChartRedraw(), and 3016
            // of the 3485 ms sat in whichever of those two it was. They are two
            // different problems - one rebuilds a label, the other asks the
            // TERMINAL to repaint a chart carrying 500-850 objects (ChartRedraw is
            // 2.14 us on an idle chart and is priced per OBJECT on a full one) - so
            // they get a field each. A number without a cause is what this project
            // refuses to act on.
            //
            // THE SECOND FIELD NAMES THE PASS `redraw=` PAID FOR: the per-phase
            // ledger P-PERF-03 already keeps (EventHandlers ~1745..2036) describes
            // the very RedrawAllObjects() call made nine lines above, so it is read
            // here instead of duplicated. On MT5 that is the difference between
            // "a scroll costs 328 ms" and "the LEVELS block of that pass is 328 ms".
            //
            // READ THE NUMBERS AS TICK-QUANTIZED: GetTickCount() steps in Windows'
            // ~15.6 ms tick, so every ms in this ledger is n x 15.625 (the day's
            // 694 lines carry 56 distinct values and they are exactly that set).
            // A phase under one tick reads 0 ms; the ordering is trustworthy, the
            // absolute value is +/- one tick. Anything finer needs
            // GetMicrosecondCount(), which is MT5-only - see the next step.
            string renderSplit = " render[levels=" + IntegerToString((int)g_p3MsLevels) +
                                 " labels=" + IntegerToString((int)g_p3MsLabels) +
                                 " overlay=" + IntegerToString((int)g_p3MsOverlay) +
                                 " base=" + IntegerToString((int)g_p3MsBase) +
                                 " atr=" + IntegerToString((int)g_p3MsAtr) +
                                 " hist=" + IntegerToString((int)g_p3MsHistory) + "]";
            _LOG_GATE_W Print("[W][PERF] chart change breakdown: redraw=", (int)p28redraw,
                  "ms labels=", (int)p28labels, "ms leg=", (int)p28leg,
                  "ms tail=", (int)(p28count + p28paint),
                  "ms [count=", (int)p28count, " paint=", (int)p28paint, "]", renderSplit);
        }
        return;
    }

    //  
    // CHARTEVENT_CLICK   Custom Price Click
    //  
    // P-UI-92: the pick mode's click must be a CHART click. CLICK carries the price
    // under the cursor, so a click on an open card/strip/menu used to set the custom
    // price origin from the price hidden under that control (and the panel's own
    // press was handled in the UI half of the same event, which runs after this one).
    // Two tests, one rule (see UIPointerOverSurface): WHERE the release landed, and
    // WHOSE release it is (a claim the UI published before this half ran).
    if(id == CHARTEVENT_CLICK && g_waitingForCustomPriceClick &&
       !UIPeekClickClaim() && !UIPointerOverSurface((int)lparam, (int)dparam))
    {
        if(StringFind(sparam, "r") >= 0)
        {
            CleanupCustomPriceObjects(true, true);
            _LOG_GATE_D Print("[D][GEN] Custom price setting cancelled (right-click)");
            ThrottledChartRedraw();
            return;
        }
        double clickedPrice = dparam;
        if(!g_customPriceLineCreated)
        {
            if(!CreateCustomPriceLine(clickedPrice, Digits)) return;
            _LOG_GATE_D Print("[D][GEN] [PIN] Drag the orange dotted line to adjust price. Double-click to confirm.");
        }
        else
        {
            uint currentTickCount = GetTickCount();
            bool isDoubleClick = (currentTickCount - g_lastClickTickCount < DOUBLE_CLICK_THRESHOLD_MS);
            g_lastClickTickCount = currentTickCount;
            if (isDoubleClick || !g_customPriceLineCreated)
            {
                g_waitingForCustomPriceClick = false;
                g_customPriceKeyboardOverride = true;
                double selectedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                g_customTHStartPrice = selectedPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
                CustomPricePersistPlacement(selectedPrice);   // P-UI-56: one writer
                // P-UI-98d: the confirm IS the placement's SET — the price is
                // final, the line goes inert, the double-click re-arms it. The
                // CREATE case (no line yet) stays armed: the fresh line must
                // drag freely until its own double-click confirms.
                if(g_customPriceLineCreated) g_cpLineArmed = false;
                // P-UI-45: settle - the line KEEPS its price and becomes inert again
                // (see CreateCustomPriceLine). Confirming must not leave it grabbed:
                // a selection outlives the gesture, and MT4 then drags the line on
                // every later drag anywhere on the chart.
                CreateCustomPriceLine(selectedPrice, Digits);
                g_redrawTHLevelsNeeded = true;
                RedrawAllObjects(true);
                _LOG_GATE_I Print("[I][GEN] Custom Price Mode activated! Using ", inpMaxLevels, " levels above/below price: ", DoubleToString(selectedPrice, Digits));
            }
        }
        ThrottledChartRedraw();
    }

    //  
    // CHARTEVENT_OBJECT_CLICK   Custom Price Line / ABCD Pattern
    //  
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_customPriceHorizontalLineName)
    {
        uint currentTickCount = GetTickCount();
        bool isDoubleClick = (currentTickCount - g_lastClickTickCount < DOUBLE_CLICK_THRESHOLD_MS);
        g_lastClickTickCount = currentTickCount;
        // P-UI-45: MT4 selects a selectable line on the press that grabs it, and a
        // SELECTED line is dragged by MT4 on every later drag anywhere on the chart.
        // Arm the deferred clear instead of writing the property HERE: this event
        // may arrive on the press, and clearing it then would drop the line out of
        // the very drag the user is starting.
        if(!isDoubleClick) g_customPriceNativeDrag = true;
        if (isDoubleClick)
        {
            // P-UI-98d: a SET line wakes on the double-click — silent, no
            // prompt: the SS/LS selector below belongs to a live line, and the
            // user's order names the double-click as the re-arm gesture.
            if(!g_cpLineArmed)
            {
                CustomPriceLineOwnArm(true);
                // P-UI-98g: re-armed AND revealed - the double-click is the user
                // asking for the handle back, so the circle comes with it.
                g_cpHandleShown = true;
                CustomPriceMarkerSync();
                ThrottledChartRedraw();
                return;
            }
            // A double-click on Custom Price is a fast SS/LS start selector.
            // The price remains unchanged; only the sequence origin changes.
            int selectedStart = MessageBox("SS/LS sequence start\n\nYes = LS first\nNo = SS first\nCancel = keep current",
                                           "Select SS/LS start", MB_YESNOCANCEL | MB_ICONQUESTION);
            // P-UI-67: the prompt is the per-chart OVERRIDE's owner (state + key in
            // one place, next to the getter that consults it). IDCANCEL keeps the
            // current answer, so it writes nothing.
            if(selectedStart == IDYES) SSLSOrderOverrideSet(1);
            else if(selectedStart == IDNO) SSLSOrderOverrideSet(0);
            g_waitingForCustomPriceClick = false;
            g_customPriceKeyboardOverride = true;
            double selectedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
            g_customTHStartPrice = selectedPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            CustomPricePersistPlacement(selectedPrice);   // P-UI-56: one writer
            // P-UI-45/P-UI-48: settle - the line KEEPS its price and stays
            // grabbable (same owner as the chart-click confirm above).
            CreateCustomPriceLine(selectedPrice, Digits);
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            _LOG_GATE_I Print("[I][GEN] Custom Price Mode activated! Using ", inpMaxLevels, " levels above/below price: ", DoubleToString(selectedPrice, Digits));
        }
        else if(g_cpLineArmed)
        {
            // P-UI-98g: THE FIRST CLICK SHOWS THE HANDLE. «فقط وقتی روش کلیک کردیم
            // دایره ها بیاد برای درگ کردن» — armed only means grabbable; the green
            // circle is painted once the user asks for it, and asking is this click.
            // It is not a SET: committing a line the user has not touched yet would
            // make the first click cost a double-click to undo.
            if(!g_cpHandleShown)
            {
                g_cpHandleShown = true;
                CustomPriceMarkerSync();
                ThrottledChartRedraw();
            }
            // P-UI-98d: a click on an ALREADY-SHOWN armed line is the SET candidate —
            // deferred past the double-click window (the sweep commits it), so the
            // first click of a double never sets first. A click that is the ECHO of
            // a drag release (the just-dragged stamp) sets nothing: the line drags
            // freely until the user deliberately clicks it.
            else if(currentTickCount - g_cpJustDraggedMs > 350)
            {
                g_cpSetPending = sparam;
                g_cpSetPendingMs = currentTickCount;
            }
        }
    }

    //
    // CHARTEVENT_OBJECT_CLICK   Step-1 handle: click = SET, double-click = re-arm
    //
    // P-UI-98d: the same contract the custom price line wears. While ARMED the
    // handle drags (the P-UI-98 OBJECT_DRAG channel recomputes the factor live);
    // a single click SETS it (the ladder keeps the dragged step, the handle
    // turns inert, the red dot goes); a double-click re-arms it. A click that is
    // the echo of a drag release sets nothing.
    if(id == CHARTEVENT_OBJECT_CLICK && Step1LineIsDragHandle(sparam))
        Step1HandleClickAt(sparam);   // P-UI-98e: the ONE click contract (the
                                      // terminal's own report is now one of three
                                      // edges; the dedupe drops its twin)

    // P-UI-98m: the green circle's own report - the third edge of the SET
    // line's re-arm contract (the masked line fires none itself). The 60 ms
    // twin guard inside drops the duplicate when the row pair already saw it.
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_cpMarkerName)
        CustomPriceRearmClickAt();

    //
    // CHARTEVENT_MOUSE_MOVE   Custom Price Drag Detection
    //
    // P-UI-98d: the double-click window's sweeper rides the mouse stream — the
    // cheapest always-on channel there is (two stamp compares when nothing is
    // pending). The tick path sweeps too, so a click that never moves again
    // still commits. And the handset handles ride the same stream (a pan moves
    // the price scale under them — the leg meter's own P-LM-16b answer).
    HandsetClickSweep();
    HandsetMarkersRide();
    // P-UI-98e: the step-1 handle's gesture walks the same stream as the
    // custom-price line's — and the custom-price line is not the only reason
    // this block exists any more: the handle is armed off the PLACEMENT, and a
    // chart that lost the line object must not lose the handle with it.
    if(id == CHARTEVENT_MOUSE_MOVE &&
       (g_customPriceLineCreated || g_thStartPointType == TH_START_POINT_CUSTOM_PRICE))
    {
        int mouseFlags = (int)StringToInteger(sparam);
        bool leftButtonDown = (mouseFlags & 1) != 0;
        // P-UI-49c: the press EDGE is the only moment a grab can start here. A
        // press that emits no mouse move is invisible (P-BK-03), so the edge is
        // seen on the first move after it - a few pixels from the press point,
        // which is what CustomPriceGrabAt's tolerance covers.
        static bool s_dragDownSeen = false;
        bool pressEdge = (leftButtonDown && !s_dragDownSeen);
        s_dragDownSeen = leftButtonDown;
        // P-UI-99 (2026-09-21): THE HOLD IS RETIRED — THE CLAIM IS IMMEDIATE.
        // User order: «اون هولد از خط کاستوم پرایس بردار به جاش سلکت و انسلاکت
        // شو درست کن که کاربر راحت باشه و همچنین کلیک شو بقیه ابجکت ها در حین
        // درگ کردن روش ندزده». The P-UI-97 hold-to-arm (a 500 ms beat the press
        // had to outlast before the drag engaged) is gone: a press on the line
        // claims the gesture the way every other chart object does. The comfort
        // the user asked for lives in the pair the hold used to stand between:
        //   * SELECT — the claim selects the line (P-UI-49d's guarded write), so
        //     a grab shows its face, and a plain click selects natively;
        //   * DESELECT — the selection is dropped at THIS gesture's button-up
        //     (the deferred latch below), and a STALE one is drained by arming
        //     the same latch on every foreign press - which is the "while I drag
        //     the other objects the line must not come along" half: a selection
        //     that outlived its gesture is what let MT4 move the line under
        //     another drag (P-UI-45), so the drain stays and fires on the same
        //     events it always did.
        // The foreign-drag discrimination is untouched (P-UI-92/P-UI-96): past
        // the press edge a terminal selection counts only with the cursor really
        // on the line, so a pan or a box drag started elsewhere is never claimed.
        if(leftButtonDown)
        {
            // P-UI-98e: our own step-1 carry, ONE pass per held event. It runs
            // before the claim below so a press that already belongs to the
            // handle is never re-claimed by the custom-price line (one cursor,
            // one gesture).
            if(g_s1OwnActive)
            {
                Step1HandleOwnDragMove((int)lparam, (int)dparam);
            }
            // P-UI-98i: A NATIVE-ONLY DRAG IS ADOPTED. MT4's own per-object drag
            // claimed the line first (the OBJECT_DRAG channel set `g_s1DragLive`
            // with our carry never armed), so this gesture lives or dies by
            // OBJECT_DRAG alone - and on the builds that stutter it (P-UI-49c)
            // that is the cut. With the cursor still on the dragged row the
            // gesture is adopted into our own carry (the claim re-latches the
            // grab at the CURRENT price, so the relative math cannot jump, and
            // the borrow ends the terminal's own loop per P-LM-21); from the
            // next held event both channels drive it. Never while the custom
            // price line owns the gesture (one cursor, one gesture).
            else if(g_s1DragLive && !g_s1OwnActive && !g_customPriceLineDragging)
            {
                string adoptRow = "";
                if(g_s1DragName != "" &&
                   Step1HandleUnderCursor((int)lparam, (int)dparam, adoptRow) &&
                   adoptRow == g_s1DragName)
                    Step1HandleOwnClaim(g_s1DragName, (int)lparam, (int)dparam);
                if(g_s1OwnActive)
                    Step1HandleOwnDragMove((int)lparam, (int)dparam);
            }
            else if(!g_customPriceLineDragging && !g_s1DragLive)
            {
                // P-UI-98e: the step-1 handle's claim comes FIRST at the press
                // edge — a press on its row belongs to it, and `s1Claimed` is the
                // one term the custom-price claim below yields to. The ROW is
                // recorded for the click contract whether or not the claim takes
                // it: the DRAG needs the armed state, the CLICK does not (a SET
                // handle is exactly what the double-click has to reach).
                // P-UI-98e: A PRESS ON THE CUSTOM PRICE LINE IS NOT OURS - with the
                // P-UI-98i reading: NEAREST WINS. The step-1 claim runs FIRST, so
                // without a yield the gesture the user aimed at the LINE re-steps
                // the ladder instead («میخوام خط کاستوم پرایس جابجا بکنم ... و step
                // جابجا میشن»). A press clearly on the line stays the line's; a
                // press nearer the handle's own row belongs to the handle even
                // when the line's tolerance also covers it (a coarse chart puts
                // both within a few pixels). An exact tie stays with the line.
                // The line's own grab test decides, and the CLICK contract reads
                // the same answer.
                bool onCustomLine = CustomPriceGrabAt((int)lparam, (int)dparam);
                string s1Row = "";
                bool s1Hit = (pressEdge &&
                              !UIPointerOverSurface((int)lparam, (int)dparam) &&
                              Step1HandleUnderCursor((int)lparam, (int)dparam, s1Row));
                bool s1OnRow = (s1Hit && (!onCustomLine ||
                                          Step1NearerThanCustom((int)lparam, (int)dparam, s1Row)));
                // P-UI-98i: A MISSED PRESS EDGE STILL CLAIMS. The edge above is
                // seen on the first MOVE after the press - a press whose first
                // move never arrived here (a release off-chart leaves the shared
                // latch set, so the next press has no edge) could never claim,
                // while the custom-price claim beside it recovers through MT4's
                // own selection. The terminal's pick-up is the second opinion
                // here too: a SELECTED handle with the cursor really on its row
                // is claimed past the edge (and the custom line keeps its own
                // priority - a press on it is never adopted).
                if(!s1OnRow && !pressEdge && g_s1LinesArmed && !onCustomLine &&
                   !UIPointerOverSurface((int)lparam, (int)dparam))
                {
                    string selRow = "";
                    if(Step1HandleUnderCursor((int)lparam, (int)dparam, selRow) &&
                       selRow != "" && ObjectFind(0, selRow) >= 0 &&
                       (bool)ObjectGetInteger(0, selRow, OBJPROP_SELECTED))
                    {
                        s1Row = selRow;
                        s1OnRow = true;
                    }
                }
                if(s1OnRow)
                {
                    g_s1ClickRow = s1Row;
                    g_s1ClickRowY = (int)dparam;
                }
                bool s1Claimed = (s1OnRow &&
                                  Step1HandleOwnClaim(s1Row, (int)lparam, (int)dparam));
                // WHO owns this gesture: MT4 grabbed the line (SELECTABLE + the
                // terminal's own hit test), OR our press-edge hit test says the
                // press landed on it. The second term is what makes the drag
                // independent of the terminal's selection behaviour - the drag
                // must not disappear because a build/setting never selects the
                // object (the P-BK-16 reality, on the boxes).
                bool terminalGrab = (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED);
                // P-UI-92: the pixel test guards the PIXEL hit test only. `terminalGrab`
                // is deliberately left alone: that is MT4's own selection, i.e. the
                // terminal already decided the press belongs to the line (and P-UI-45
                // exists precisely because a selection outlives its gesture).
                // P-UI-96: ... but a selection ALSO outlives into FOREIGN drags (a
                // click leaves the line selected; the drain only runs on a later
                // button-up move). Honouring `terminalGrab` with no position check
                // claimed every such drag for the line - it activated mid-pan/box
                // drag and rode along, and the gesture lock made the chart feel
                // stuck. So past the press edge a terminal grab counts only with
                // the cursor really on the line; the press edge itself keeps the
                // untested honour (MT4 just picked it for THIS press).
                bool atLineNow = false;
                if(terminalGrab && !pressEdge)
                    atLineNow = CustomPriceGrabAt((int)lparam, (int)dparam);
                bool pixelHit = (pressEdge && !UIPointerOverSurface((int)lparam, (int)dparam) &&
                                 CustomPriceGrabAt((int)lparam, (int)dparam));
                // P-UI-98m: the re-arm candidate for a SET (masked) line. The
                // armed claim below refuses a SET line, and a masked line fires
                // no OBJECT_CLICK - without this row nobody could wake it. The
                // DRAG needs the armed state, the CLICK does not (a SET line is
                // exactly what the double-click has to reach).
                if(pixelHit && !g_cpLineArmed)
                {
                    g_cpClickArmed = true;
                    g_cpClickY = (int)dparam;
                }
                // P-UI-98d: the claim asks the ARMED state first — a set line is
                // inert; nothing may grab it, not even our own pixel test.
                // P-UI-100b: AND IT ASKS WHETHER THE PRESS IS ALREADY A DRAW. A
                // foreign object that appeared inside the witness window means the
                // terminal is drawing something (its own tool owns this press),
                // and the pixel test cannot tell that from a grab: both are a press
                // on the line followed by a drag. Refusing here is what makes the
                // draw cost NOTHING — no claim, no selection, no carry, so the line
                // never moves and there is nothing to put back. The CLICK rows above
                // are deliberately NOT gated by it: a SET line's double-click to
                // re-arm is not a draw and must keep working.
                if(!s1Claimed && g_cpLineArmed && !TickDeadlinePending(s_cpForeignDrawUntil) &&
                   ((pressEdge && (terminalGrab || pixelHit)) || (terminalGrab && atLineNow)))
                {
                    g_customPriceLineDragging = true;
                    g_customPriceDragOwn = true;
                    // P-UI-98g: a hand on the LINE is the request for its circle —
                    // the same reading the step-1 claim uses (see there).
                    g_cpHandleShown = true;
                    CustomPriceMarkerSync();
                    s_ownLastWrite = 0.0;
                    s_ownGrabPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                    // P-UI-55: the press latch - ONE conversion per gesture, and only
                    // to define the base our own carry moves FROM.
                    s_ownGrabX = (int)lparam;
                    s_ownGrabY = (int)dparam;
                    s_ownGrabCursorPrice = 0.0;
                    {
                        int gW = 0; datetime gT = 0;
                        if(!ChartXYToTimePrice(0, s_ownGrabX, s_ownGrabY, gW, gT, s_ownGrabCursorPrice))
                            s_ownGrabCursorPrice = 0.0;
                    }
                    // P-UI-49d: THE OLD MECHANISM, restored under a guard. git
                    // says the drag was never ours: the old C-key/chart-click
                    // paths created the line `OBJPROP_SELECTED = true` and MT4
                    // moves the SELECTED object on each mouse move - that IS the
                    // movement the user remembers (commit 3a288fb removed that
                    // one write, and no per-object grab ever replaced it).
                    // Selecting here is safe where selecting at CREATION was not:
                    // the gesture is provably OURS (the press landed on the line),
                    // so MT4 has no foreign drag in flight to hijack, and the
                    // selection is dropped at this gesture's end through the same
                    // deferred latch. Written ONLY when the terminal did not
                    // already select it - a property write on an object MT4 is
                    // dragging cancels that drag (P-BK-15).
                    if(!terminalGrab)
                        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);
                    g_customPriceNativeDrag = true;   // owed clear at this gesture's button-up
                    // P-UI-53: and the GESTURE owns the view from here to the
                    // release - the chart behind the line must not pan under it.
                    CustomPriceDragLockOn();
                }
                else if(pressEdge || terminalGrab)
                {
                    // A press that is NOT ours starts somebody else's gesture
                    // (a pan, a box, the ring, a card): the line must not STAY
                    // SELECTED through it, or MT4 moves it with that drag -
                    // which is the interference this cycle started from.
                    // P-UI-96: `|| terminalGrab` - a stuck selection seen while
                    // the button is down arms the same drain even when the press
                    // edge was missed (release off-chart leaves s_dragDownSeen
                    // set, so the next press has no edge to arm on).
                    // P-UI-51: the clear is ARMED here, never WRITTEN. This hit
                    // test runs on the first MOVE after the press, already a few
                    // pixels away from it and further the faster the drag starts,
                    // so it can MISS a press the TERMINAL did pick up - and
                    // ClearCustomPriceSelection only ever writes while
                    // OBJPROP_SELECTED is true, i.e. exactly when the terminal is
                    // holding the line. Writing it then dropped MT4's own
                    // selection out of the drag that same press had just started:
                    // the gesture engaged and died on its first event - "the drag
                    // state is cut off very quickly", "it cannot be dragged".
                    // Deferring costs one bool store and keeps the promise: the
                    // latch is drained at the button-up by the one clear owner.
                    g_customPriceNativeDrag = true;
                    // P-UI-100 (2026-09-22): AND THE CLEAR IS ALSO WRITTEN HERE —
                    // everywhere it cannot touch a grab.
                    //
                    // Deferring is only needed for the one press that might BE a
                    // grab of this line (P-UI-51's lesson). Every other press —
                    // a pan, a panel, a box, MT4's own fib or rectangle drawn from
                    // somewhere else — has already been answered by the hit test
                    // above, and MT4 will carry the line through that whole gesture
                    // if it is still selected (the law P-UI-45/P-BK-26 measured).
                    // The witness is the SAME test the claim uses, with the same
                    // tolerance, and ours is the wider one (it covers the visible
                    // circle): a cursor that fails it is not a cursor MT4 picked
                    // the line up with, so the write cannot cancel anything.
                    bool onLineNow = (!UIPointerOverSurface((int)lparam, (int)dparam) &&
                                      CustomPriceGrabAt((int)lparam, (int)dparam));
                    if(!onLineNow) HandLinesSelectionGuard();
                }
            }
            if(g_customPriceLineDragging)
            {
                double currentLinePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                // P-UI-49c (P-BK-16's shape): while OUR gesture owns the line,
                // carry it - but ONLY while the terminal is NOT moving it: its
                // price still equals the grab price / our last write. A working
                // native drag keeps its price moving, this branch stands down and
                // the object is never rewritten mid-gesture (P-BK-15). Absolute
                // from the cursor (never incremental), so it converges exactly.
                // P-UI-51: the press edge's OWN move is the one event where the
                // frozen test below is meaningless - the line's price equals the
                // grab price by definition there, whether the terminal is about to
                // move it or never will. Writing on that event was the last way
                // our own carry could rewrite the object MT4 had just grabbed, so
                // the fallback starts one event later (a few ms; absolute from the
                // cursor, so it converges on the same price anyway).
                // P-UI-55: the slop fence and the delta. `cursorY` is compared with the
                // GRAB's pixel (Y only - an HLINE cannot be moved horizontally), so the
                // jitter of a click never opens this door; `wishPrice` is the grab price
                // plus the cursor's TRAVEL since the grab, never the cursor's price, so
                // the press offset survives and the line can never snap onto the cursor.
                int cursorY = (int)dparam;
                bool pastSlop = (MathAbs(cursorY - s_ownGrabY) >= CP_DRAG_SLOP);
                // P-UI-100b: AND THE CARRY STANDS DOWN THE MOMENT THE GESTURE IS
                // KNOWN TO BE A DRAW. `s_drawNotGrab` is set by the OBJECT_CREATE
                // detector when a foreign object appeared while this claim was live:
                // the terminal is drawing something, our press was its anchor, and
                // moving the line along with it is exactly the report. The release
                // then puts the line back (CustomPriceRestoreGrabPrice), so the
                // gesture ends with the price the user left behind either way.
                if(g_customPriceDragOwn && !pressEdge && pastSlop && !s_drawNotGrab &&
                   currentLinePrice > 0 && s_ownGrabCursorPrice > 0)
                {
                    double refPrice = (s_ownLastWrite > 0.0) ? s_ownLastWrite : s_ownGrabPrice;
                    if(MathAbs(currentLinePrice - refPrice) < _Point * 0.5)
                    {
                        int subW = 0; datetime curT = 0; double cursorPrice = 0.0;
                        if(ChartXYToTimePrice(0, (int)lparam, cursorY, subW, curT, cursorPrice) &&
                           cursorPrice > 0)
                        {
                            double wishPrice = s_ownGrabPrice + (cursorPrice - s_ownGrabCursorPrice);
                            if(wishPrice > 0 && MathAbs(wishPrice - currentLinePrice) > _Point * 0.5)
                            {
                                ObjectSetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, wishPrice);
                                s_ownLastWrite = wishPrice;
                                currentLinePrice = wishPrice;
                                CustomPriceMarkerSync();   // P-UI-98d: the dot rides the carry too
                            }
                        }
                    }
                }
                // P-UI-61: the STATE is no longer inside the frame's gate. The anchor
                // advances on EVERY event that moved the line - a lagging anchor is a
                // ladder drawn where the line is not - and only the FRAME is budgeted
                // (one owner, shared with the native-drag channel). A refused frame is
                // owed; the release and the next tick both pick the flag up.
                if(currentLinePrice > 0 && CustomPriceDragAnchorSet(currentLinePrice))
                    CustomPriceDragFrame(false);
            }
        }
        else
        {
            // P-UI-45/P-UI-48: the gesture is over - drop the selection a grab (or
            // a plain click on the line) left behind. A SELECTED line is moved by
            // MT4 on every LATER drag anywhere on the chart, which is what made it
            // fight the panels, the cards and the BaseKnot boxes. One bool read per
            // mouse-move; the clear runs once per gesture, through its one owner.
            // P-UI-99: the hold is gone — nothing to disarm here. The step-1
            // handle's gesture still ends at this latch: forced frame, deselect,
            // the view handed back. The custom-price flags below belong to a
            // different gesture and stay alone.
            // THE TRAVEL IS READ BEFORE THE SETTLE, and the settle clears the
            // carry's own write stamp - a gesture that wrote a price HAS travelled,
            // and asking after the settle would always answer "no".
            bool s1Wrote = (g_s1OwnLastWrite > 0.0);
            if(g_s1DragLive) Step1DragSettle();
            // P-UI-98e: the OTHER half of the click contract — the button-up that
            // ends a press which never TRAVELLED is a click on the handle, and the
            // row the press edge recorded names it. A press that travelled is a
            // drag (its settle already answered), and a motionless release that
            // emits no event here is caught by Step1ClickFinalize.
            if(g_s1ClickRow != "")
            {
                bool rowTravelled = s1Wrote ||
                                    (MathAbs((int)dparam - g_s1ClickRowY) >= CP_DRAG_SLOP);
                string row = g_s1ClickRow;
                g_s1ClickRow = "";
                if(!rowTravelled) Step1HandleClickAt(row);
            }
            // P-UI-98m: the SET line's own half - a press on its row that never
            // travelled is a click, and only a double of those re-arms (a single
            // is a no-op: already set). A motionless release emits no event
            // here and is caught by CustomPriceRearmFinalize instead.
            if(g_cpClickArmed)
            {
                bool cpTravelled = (MathAbs((int)dparam - g_cpClickY) >= CP_DRAG_SLOP);
                g_cpClickArmed = false;
                if(!cpTravelled) CustomPriceRearmClickAt();
            }
            if(g_customPriceNativeDrag)
            {
                g_customPriceNativeDrag = false;
                ClearCustomPriceSelection();
            }
            if(g_customPriceLineDragging) {
                g_customPriceLineDragging = false;
                g_customPriceDragOwn = false;
                // P-UI-53: the gesture is over - hand the view back EXACTLY as the
                // user had it (the props the lock saved at the grab).
                CustomPriceDragLockOff();
                // P-UI-54: A CLICK IS NOT A MOVE, AND A WIPE IS NOT A MOTION SIGNAL.
                //
                // Reported: "click the custom price line and every level is rebuilt
                // on the chart - it flickers". It was this branch: the settle raised
                // `g_forceClearOnNextDraw` UNCONDITIONALLY, and MT4 selects the line
                // on the press that clicks it, so our drag path engaged for a plain
                // CLICK as well - every single click therefore ran ClearAllLevels
                // (the whole family deleted) followed by the four-frame staged
                // rebuild of ~900 objects: the flicker, for a gesture that moved
                // NOTHING.
                //
                // The question the release must ask is "did this gesture move the
                // line?" - nothing else. If it did not, the picture on the chart is
                // already the one the user is looking at (the live follow re-asserted
                // it, and the geometry signature carries the start price since
                // P-UI-52), so the release owes no frame at all. If it did, the settle
                // is the in-place re-assert below - NOT a wipe: a wipe answers a
                // TOPOLOGY change (the start point's type, the mode, the timeframe),
                // never a price. That is also why the confirm paths keep theirs: they
                // really do change `g_thStartPointType`, which is in `levelSig`.
                // `s_ownGrabPrice` is the line's price when the gesture was grabbed
                // and `s_ownLastWrite` is set when WE carried it, so the test is exact
                // in both movement directions (the terminal's own drag and our carry).
                // P-UI-61: THE RELEASE SETTLES FROM THE OBJECT - the one value MT4
                // itself keeps exact - and it settles with a FRAME, never with a
                // re-anchor. `CustomPriceDragAnchorSet` is the only writer here and it
                // persists, so the frame's own resolver (P-UI-56) now answers with the
                // SAME price the anchor holds: its `priceMoved` branch can no longer
                // overwrite the gesture's result with an older key. That overwrite WAS
                // «وقتی خط را رها میکنم سطوح از یک جای دیگه رسم میشن» - the carry
                // channel never persisted, so the key held a pre-gesture price and the
                // settle rebuilt the whole ladder there.
                double settledPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                // P-UI-100b (2026-09-22): A DRAW IS NOT A DRAG, AND IT SETTLES BACK.
                //
                // This claim turned out to be the anchor of a DRAW the terminal was
                // performing (a fib, a rectangle — the OBJECT_CREATE detector saw the
                // object it made): the price under `settledPrice` is where the DRAW
                // ended, not where the user put the line, and every level derived from
                // it would move with it («کاستوم پرایس جابجا میشه»). The gesture is
                // rolled back to the price the grab found — the same number the claim
                // latched before it touched anything — through the one writer, which
                // re-anchors it, drops the selection the claim made and repaints.
                // The flag is cleared HERE, at the one place a claim ends, so a stale
                // one can never reach the next gesture.
                if(s_drawNotGrab)
                {
                    s_drawNotGrab = false;
                    CustomPriceRestoreGrabPrice();
                }
                else
                {
                bool movedByGesture = (s_ownLastWrite > 0.0) ||
                                      MathAbs(g_customTHStartPrice - s_ownGrabPrice) > _Point * 0.5 ||
                                      (settledPrice > 0.0 &&
                                       MathAbs(settledPrice - s_ownGrabPrice) > _Point * 0.5);
                if(movedByGesture)
                {
                    CustomPriceDragAnchorSet(settledPrice);
                    CustomPriceDragFrame(true);   // force: the gesture's last pixel is always painted
                    CustomPriceMarkerSync();      // P-UI-98d: the dot settles with the line
                    // P-UI-98d: stamp the echo — the OBJECT_CLICK MT4 reports at
                    // the end of this drag must not set the line the user just
                    // moved (the click that commits is a deliberate one later).
                    g_cpJustDraggedMs = GetTickCount();
                }
                else if(CustomPriceDragFrameOwed())
                {
                    // A click that moved nothing still owes nothing (P-UI-54), but a
                    // frame the throttle refused while the gesture was live is owed -
                    // and this is its last chance to be painted.
                    CustomPriceDragFrame(true);
                }
                // P-UI-49: the gesture is over - the button is UP, so NOW the
                // line may be written again. This is the release the tooltip is
                // owed to; nothing touches the line while it is being dragged.
                UpdateCustomPriceTooltip();
                }   // P-UI-100b: end of the "this gesture really moved the line" half
            }
        }
    }

    //  
    // CHARTEVENT_OBJECT_DRAG   Custom Price Line Drag End
    //  
    if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_customPriceHorizontalLineName)
    {
        // P-UI-51: THE GESTURE FLAG BELONGS TO THE PRESS EDGE AND THE RELEASE,
        // NEVER TO THIS EVENT.
        //
        // This event is CONTINUOUS while MT4 drags the line, and the handler used
        // to clear g_customPriceLineDragging on every step of it. The mouse-move
        // path reads that flag as "the grab is decided, this gesture is mine":
        // cleared per step, its grab block re-ran per step and RE-ARMED the
        // carry's reference (s_ownGrabPrice) to the line's CURRENT price - so the
        // frozen test that keeps our writes off a live terminal drag
        // (|linePrice - reference| < half a point, P-BK-16's shape) compared the
        // price with ITSELF, always passed, and handed the line a fresh
        // OBJPROP_PRICE in the middle of the very drag MT4 was performing. MT4
        // cancels an in-progress native drag when the dragged object is rewritten
        // mid-gesture (P-BK-15): the line snapped back to the drag start, which is
        // the reported "the drag state is cut off very quickly / it cannot be
        // dragged". Leaving the flag alone for the whole gesture is also what
        // makes the carry stand down the moment the terminal moves the line
        // itself - one write per fallback gesture instead of one per step.
        // P-UI-45: MT4 keeps the object SELECTED after a native drag. Clearing it
        // HERE would let go of the line under the user's hand (this event is
        // CONTINUOUS while dragging), so the clear is deferred to the first
        // button-up mouse move - see g_customPriceNativeDrag below.
        g_customPriceNativeDrag = true;
        double draggedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
        // P-UI-61: the anchor AND its persist are the one owner's now. The persist
        // used to live HERE only, which is exactly why the CARRY channel's key went
        // stale and the release re-anchored the ladder to it (the P-UI-56 writer is
        // still the only thing that writes the pair - one call, one place).
        bool anchorMoved = CustomPriceDragAnchorSet(draggedPrice);
        CustomPriceMarkerSync();   // P-UI-98d: the green dot follows the native drag (one guarded write)
        // P-UI-49: NO property write on the line HERE - the tooltip text is
        // written once at the release instead (UpdateCustomPriceTooltip). This
        // handler runs on EVERY step of a native drag, and MT4 cancels an
        // in-progress native drag when the dragged object is rewritten
        // mid-gesture (P-BK-15), so the tooltip write that used to sit here
        // cancelled the drag it was decorating: the line never followed the
        // cursor. Read-only + state, nothing on the object while the button is
        // down.
        if(!g_waitingForCustomPriceClick)
            _LOG_GATE_D Print("[D][GEN] Custom TH start price updated to: ", DoubleToString(draggedPrice, Digits));
        // P-UI-52: NO WIPE PER STEP - the live follow is an IN-PLACE re-assert.
        //
        // This handler used to raise `g_forceClearOnNextDraw` on every step of a
        // native drag, and that flag is the WIPE: `shouldClearLevels` calls
        // ClearAllLevels (every level, zone and label family deleted) and restarts
        // the four-frame staged rebuild. Per drag step that is hundreds of deletes
        // and re-creates for a picture that moved by one pixel - the family blinked
        // and lagged behind the line instead of following it, which is the cost the
        // report pays for "the levels do not move with the line". Nothing about a
        // move changes the TOPOLOGY, so the wipe is not needed to re-draw it: with
        // the start price now in the geometry signature the render re-derives the
        // levels and re-asserts the same object NAMES in place (no orphans - the
        // pipeline's own surplus pass owns the extras, already drag-throttled), and
        // the AUTHORITATIVE rebuild is the release: the button-up branch of the
        // drag's mouse-move handler raises the clear together with the frame, so
        // the settled picture is a full, staged, exact rebuild - the "settle at
        // the end" the report asks for, unchanged. Cost: strictly less work per
        // step (no wipe, no staged rebuild) and the same single frame per 50 ms.
        // P-UI-51: with the gesture flag alive for the whole drag (above), a forced
        // frame from here runs INLINE (the P-PERF-34 drag exemption) on EVERY step
        // MT4 reports. The live follow already spends that exemption from the
        // mouse-move path, so this channel shares its budget: one frame per window
        // across both channels - the cadence the drag already had, and strictly
        // less work than one frame per reported step.
        // P-UI-61: and that budget now has ONE owner, so a step whose anchor did not
        // move costs nothing at all instead of one more full pass.
        if(anchorMoved) CustomPriceDragFrame(false);
    }

    // P-UI-98: the step-1 handle's own drag channel. Continuous while MT4 moves
    // the line; each step recomputes the override factor and shares the ONE
    // frame budget (see the section above for the three P-BK-15 rules).
    if(id == CHARTEVENT_OBJECT_DRAG && Step1LineIsDragHandle(sparam))
        Step1LineDragApply(sparam);

    // VIEWLOCK-OFF: anchor-line drag retired —
    //if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_viewAnchorLineName && g_viewLockEnabled)
    //{
    //    datetime droppedTime = (datetime)ObjectGetInteger(0, g_viewAnchorLineName, OBJPROP_TIME, 0);
    //    if(droppedTime > 0 && droppedTime != g_viewAnchorTime)
    //    {
    //        g_viewAnchorTime = droppedTime;
    //        ViewLockPersistAnchor();
    //        if(ViewLockRestore()) g_viewRestorePending = false;
    //        else g_viewRestorePending = true;   // history not ready — retry next ticks
    //        ThrottledChartRedraw();
    //    }
    //    return;
    //}

    //
    // CHARTEVENT_OBJECT_CLICK   ABCD Pattern Selection — TH3TOOL-ON (2026-09-19): restored.
#ifndef BUILD_LITE
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(StringFind(sparam, "ABCD_Pattern_") == 0)
        {
            string patternName = "";
            int suffixPos = -1;
            if(StringFind(sparam, "_Point_") > 0) suffixPos = StringFind(sparam, "_Point_");
            else if(StringFind(sparam, "_Label_") > 0) suffixPos = StringFind(sparam, "_Label_");
            else if(StringFind(sparam, "_Line_") > 0) suffixPos = StringFind(sparam, "_Line_");
            else if(StringFind(sparam, "_Target_") > 0) suffixPos = StringFind(sparam, "_Target_");
            else if(StringFind(sparam, "_Zone") > 0) suffixPos = StringFind(sparam, "_Zone");
            if(suffixPos > 0) {
                patternName = StringSubstr(sparam, 0, suffixPos);
            } else {
                patternName = sparam;
            }
            if(patternName != "") {
                SetActiveABCDPattern(patternName);
            }
        }
        // P-TH3-BANDSEL (2026-09-22): the TH3 tool's OWN objects are not a
        // deselection. Clicking the base editor band — and the click echo that
        // follows EVERY band drag's button-up — fell in here, blanked the
        // active pattern, masked its ladder and dropped its caption plate, and
        // the next band re-step redraw kept them dark: the whole ABCD read as
        // deleted («بیس مبنا که میکشم ... باعث حذف abcd میشه»). The band, its
        // "1" tag, the P6 pivot triangles and the TH3_MP_ mother overlay are
        // the pattern's own tooling — a click on any of them is a no-op here.
        else if(StringFind(sparam, "TH3_") != 0)
        {
            SetActiveABCDPattern("");
        }
    }
#endif
}

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
bool IsHotkeyPressed(const long lparam, const string sparam, const string hotkey) {
    if(StringLen(hotkey) <= 0) return false;
    string k = hotkey;
    StringToUpper(k);
    int code = (int)StringGetCharacter(k, 0);
    if((int)lparam == code) return true;
    if(StringLen(sparam) > 0) {
        string sp = sparam;
        StringToUpper(sp);
        if((int)StringGetCharacter(sp, 0) == code) return true;
    }
    return false;
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
    g_modeLabelYOffset = g_currentLabelYOffset;
    RepositionAllOverlayLabels();
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
      if(waited >= COOP_WARN_MS || spent >= COOP_WARN_MS)
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

#endif // EVENT_HANDLERS_MQH

