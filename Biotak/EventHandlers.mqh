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
#define NAME_SCHEME_ID 38

string AdoptionStampName() { return "Biotak_AdoptTopology_" + GetCachedChartIdStr(); }

// The fingerprint packs the inputs that decide which NAMES may exist, built from
// small integers so it is EXACT — no string hashing and therefore no collisions
// to reason about.
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
// fingerprint's inputs.
bool g_adoptPreviousTopology = false;

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
// P-UI-56 — THE CUSTOM-PRICE *SOURCE* HAS ONE OWNER AND ONE PRECEDENCE
//
// Reported: «چرا سطوح سرجای خودشون نیستن، هر دفعه یک جایی دیگه میره … حتماً
// نگاه کن منبع رسم قیمت چطوریه». The whole level family is anchored on
// `GetMidpointPrice(g_thStartPointType)` → `g_customTHStartPrice`
// (`CalculateCommonStepData` → `data.midpointPrice` → `ExecutePipeline`), so this
// ONE value decides where every level sits. It was resolved by TWO copies of the
// same three-branch chain — here in OnInitHandler and again in
// `RedrawAllObjects` (the frame path) — and the chain had two defects that only
// show on a chart that is actually used:
//
//  (1) THE PERSISTED PLACEMENT WAS PER *SYMBOL*, NOT PER CHART. The keys were
//      "Biotak_CustomPrice_<SYMBOL>" / "…Override_<SYMBOL>" while every other
//      per-chart state in this project is keyed by the CHART id (visibility,
//      drag locks, the hide flag, the topology stamp). Two charts of the same
//      symbol therefore shared ONE price: placing or dragging the line on one
//      chart moved the ladder of the other on its very next frame, and turning
//      it off on one turned it off on the other. The user runs five charts of
//      two symbols — this is the reported "each time it goes somewhere else".
//
//  (2) THE INPUT SILENTLY OUTRANKED — AND OVERWROTE — THE PLACEMENT KEYS. With
//      `inpCustomTHStartPrice > 0` and the override flag false, the frame path
//      took the INPUT branch and wrote `GlobalVariableSet(priceKey, <input>)`:
//      the price the user had dragged to was destroyed, so a later placement
//      gesture (a new press sets the flag) inherited the INPUT's price, not the
//      user's. The flag is false on every fresh instance whose override GVar is
//      0/absent (another chart turned it off, the GVars were cleared, a
//      REASON_REMOVE purge ran, …).
//
// ONE owner now answers "what is the custom price of THIS chart?" for both call
// sites, and the rule is: the user's own placement (chart-scoped price + its
// flag, written by every placement path through `CustomPricePersistPlacement`)
// BEATS the static input, and the input is only the seed used when this chart has
// no placement of its own — it never writes the placement keys (which is also why
// the input's price still IS the "default state" the OFF paths return to, exactly
// as before: OFF deletes the placement keys and the input speaks again).
//
// Cost: unchanged steady state — the same two GVar probes the frame path already
// did, one compare more; the legacy (symbol-scoped) probe runs ONCE per instance;
// the parsing is no longer duplicated, so the two copies can never drift again.
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

    // Restore TH labels mode (Default to OFF on first load: 0=OFF, 1=FRACTAL, 2=STANDARD, 3=BOTH)
    string thLabelsGvarName = "Biotak_THLabels_" + chartIdStr;
    if(GlobalVariableCheck(thLabelsGvarName)) {
        double gvarValue = GlobalVariableGet(thLabelsGvarName);
        bool isZero = MathAbs(gvarValue - 0.0) < EPSILON_GENERAL;
        bool isOne = MathAbs(gvarValue - 1.0) < EPSILON_GENERAL;
        bool isTwo = MathAbs(gvarValue - 2.0) < EPSILON_GENERAL;
        bool isThree = MathAbs(gvarValue - 3.0) < EPSILON_GENERAL;
        if(isZero || isOne || isTwo || isThree) {
            g_thLabelsMode = (int)gvarValue;
            SyncTHFlagsFromMode();   // flags follow the restored mode
        } else {
            _LOG_GATE_E Print("[E][GEN] OnInit: Corrupted TH labels state (", DoubleToString(gvarValue, 10), "), resetting");
            g_thLabelsMode = 0; // Default to OFF
            GlobalVariableSet(thLabelsGvarName, 0.0);
            g_thLabelsVisible = false;
        }
    } else {
        // First attach: honor the Inputs-dialog TH flags (master ON → FRACTAL
        // when no specific flag is set) instead of forcing OFF.
        g_thLabelsMode = THModeFromFlags();
        if(g_showTHLabels && g_thLabelsMode == 0) g_thLabelsMode = 1;
        SyncTHFlagsFromMode();
    }

    int validationResult = ValidateInputs();
    if(validationResult != INIT_SUCCEEDED) return validationResult;
    g_pInitMsSettings = GetTickCount() - pInitTick;   // P-PERF-10
    pInitTick = GetTickCount();

    ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
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
            _LOG_GATE_E Print("[E][GEN] OnInit: UpdateHistoricalValues failed. Error: ", GetLastError());
            return INIT_FAILED;
        }
        g_initialized = true;
    } else {
        g_initialized = false;
    }
    g_calculatedOnce = false;
    InitializeAdaptiveScaling();

    g_dailyClosePriceForTH = GetPriceForPreviousDay(inpTHPriceType);
    if(g_dailyClosePriceForTH == EMPTY_VALUE) {
        _LOG_GATE_E Print("[E][GEN] OnInit: GetPriceForPreviousDay failed, returning INIT_FAILED.");
        return INIT_FAILED;
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
        g_lockedPeriod = (int)GlobalVariableGet(lockPeriodName);
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

    // TH3TOOL-OFF: frequency restore retired with the tool —
    //#ifndef BUILD_LITE
    //    // Restore TH3 frequency with dynamic max validation (binary subdivision)
    //    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
    //    if(GlobalVariableCheck(freqGvarName)) {
    //        double restoredFreq = GlobalVariableGet(freqGvarName);
    //        double maxFreq = GetFrequencyByIndex(MAX_TH3_FREQ_INDEX);
    //        if(restoredFreq > 0 && restoredFreq <= maxFreq) {
    //            g_th3FreqOverride = restoredFreq;
    //        } else {
    //            g_th3FreqOverride = 0;
    //            GlobalVariableDel(freqGvarName);
    //        }
    //    }
    //    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
    //    if(GlobalVariableCheck(indexGvarName)) {
    //        int restoredIndex = (int)GlobalVariableGet(indexGvarName);
    //        if(restoredIndex >= MIN_TH3_FREQ_INDEX && restoredIndex <= MAX_TH3_FREQ_INDEX) {
    //            g_th3FreqIndex = restoredIndex;
    //        } else {
    //            g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
    //            GlobalVariableDel(indexGvarName);
    //        }
    //    }
    //    // Binary subdivision migration: sync index with saved frequency (old GM -> binary)
    //    if(g_th3FreqOverride > 0) {
    //        double expectedFreq = GetFrequencyByIndex(g_th3FreqIndex);
    //        if(MathAbs(expectedFreq - g_th3FreqOverride) > 0.01) {
    //            g_th3FreqIndex = FindNearestFreqIndex(g_th3FreqOverride);
    //            g_th3FreqOverride = GetFrequencyByIndex(g_th3FreqIndex);
    //            GlobalVariableSet(freqGvarName, g_th3FreqOverride);
    //            GlobalVariableSet(indexGvarName, (double)g_th3FreqIndex);
    //            _LOG_GATE_I Print("[I][GEN] OnInit: TH3 Freq migrated to binary subdivision: idx=", g_th3FreqIndex,
    //                              " freq=", DoubleToString(g_th3FreqOverride, 4));
    //        }
    //    }
    //#endif

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

    // TH3TOOL-OFF:
    //#ifndef BUILD_LITE
    //    // Check if TH3 objects need update (after settings change)
    //    string th3UpdateFlag = "Biotak_TH3_NeedsUpdate_" + chartIdStr;
    //    if(GlobalVariableCheck(th3UpdateFlag) && GlobalVariableGet(th3UpdateFlag) > 0) {
    //        UpdateAllTH3Objects();
    //        GlobalVariableDel(th3UpdateFlag);
    //    }
    //#endif

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
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);   // P-UI-48: this IS the drag
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
// Four owners keep it honest:
//   * the GRAB takes it (once per gesture, and it remembers what the user had);
//   * every throttled drag step RE-ASSERTS it - read-guarded, a write only on
//     drift, because third writers (a panel closing, a watchdog restore, a
//     template reset) can flip the props back while the button is still down;
//   * the BUTTON-UP releases it (restoring what the user had, never a blind true);
//   * a watchdog heals a release that never arrived (off-window release, lost
//     focus): the P-BK-03 trap - no mouse move, so no release event either.
// CHART_AUTOSCROLL is held down too while we own the view: a tick sliding the
// scale mid-drag moves the line with it (BaseKnot makes the same call).
// OnDeinit releases it for EVERY reason, so a stale lock can never outlive the
// instance, and `g_cpTouched` records that this instance ever changed the props.
//==============================================================================
static bool s_cpChartLocked = false;
static bool g_cpTouched     = false;   // OnDeinit must restore, whatever happens
static bool s_cpScrollWas   = true;
static bool s_cpCtxWas      = true;
static bool s_cpAutoWas     = true;
static uint s_cpLockActMs   = 0;       // last activity of the owning gesture

bool CustomPriceDragLocked() { return s_cpChartLocked; }

void CustomPriceDragLockOn()
{
    if(!s_cpChartLocked)
    {
        s_cpScrollWas = (ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0);
        s_cpCtxWas    = (ChartGetInteger(0, CHART_CONTEXT_MENU) != 0);
        s_cpAutoWas   = (ChartGetInteger(0, CHART_AUTOSCROLL) != 0);
        s_cpChartLocked = true;
    }
    ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
    if(s_cpAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, false);
    ChartSetInteger(0, CHART_CONTEXT_MENU, false);   // the menu must not steal the gesture
    g_cpTouched = true;
    s_cpLockActMs = GetTickCount();
}

void CustomPriceDragReassertLock()
{
    if(!s_cpChartLocked) return;
    s_cpLockActMs = GetTickCount();
    if(ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0)
    { ChartSetInteger(0, CHART_MOUSE_SCROLL, false); g_cpTouched = true; }
    if(s_cpAutoWas && ChartGetInteger(0, CHART_AUTOSCROLL) != 0)
    { ChartSetInteger(0, CHART_AUTOSCROLL, false); g_cpTouched = true; }
    if(ChartGetInteger(0, CHART_CONTEXT_MENU) != 0)
    { ChartSetInteger(0, CHART_CONTEXT_MENU, false); g_cpTouched = true; }
}

void CustomPriceDragLockOff()
{
    if(!s_cpChartLocked) return;
    ChartSetInteger(0, CHART_MOUSE_SCROLL, s_cpScrollWas);
    ChartSetInteger(0, CHART_CONTEXT_MENU, s_cpCtxWas);
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
    string text = g_waitingForCustomPriceClick
                  ? "Current price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Double-click to confirm"
                  : "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Drag to adjust";
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, text);
}

// P-UI-49c: the gesture's own bookkeeping. `s_ownGrabPrice` is the line's price
// when the grab started and `s_ownLastWrite` the last price WE wrote; they are
// what tells a working native drag (the terminal's price moves on its own - we
// then touch nothing, P-BK-15) from a frozen one (it does not - we carry it).
static double s_ownGrabPrice = 0.0;
static double s_ownLastWrite = 0.0;

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
#define CP_DRAG_SLOP 6                    // px of vertical travel before it is a DRAG

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
    int tolPx = (int)inpCustomPriceLevelWidth + 4;
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
    // TH3TOOL-OFF:
    //#ifndef BUILD_LITE
    //    ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    //#endif
    ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    if(g_customPriceLineCreated)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, noPeriodsVal);
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
void OnDeinitHandler(const int reason) {
    DEBUG_PRINT("Starting cleanup");
    // P-PERF-02: after this teardown the chart holds none of our masks, so the
    // next instance must re-assert every one of them, and the once-per-
    // transition hide pass is re-armed.
    ResetHideAllState();
    BumpTfEpoch();
    BaseKnotOnDeinit(reason);   // P-BK-02: never leave scroll locked / ghost preview behind
    CustomPriceDragLockOff();   // P-UI-53: same rule for the custom-price drag lock
    g_cpTouched = false;
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

    ReleaseATRHandle();
    EventKillTimer();

    // PERF: ObjectDelete is safe to call on non-existent objects (returns false, no error)
    // Eliminates ObjectFind syscalls
    ObjectDelete(0, g_stepModeLabelName);
    ObjectDelete(0, g_factorLabelName);
    // TH3TOOL-OFF:
    //#ifndef BUILD_LITE
    //    ObjectDelete(0, g_th3FreqLabelName);
    //#endif
    ObjectDelete(0, g_lockStatusLabelName);
    ObjectDelete(0, g_customPriceHorizontalLineName);
    ObjectDelete(0, g_viewAnchorLineName);   // VIEWLOCK-OFF: purge only — the lock itself is retired

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
        ObjectsDeleteAll(0, TH3_TEMP_PREFIX);     // Clean up any temp drawing objects
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
// P-PERF-34 / P-PERF-35 - A SCHEDULED FRAME, AND THE CO-OPERATIVE PUMP
//
// P-PERF-34 - THE EVENT PATH SCHEDULES THE FRAME; IT DOES NOT RUN IT.
//
// applyRefreshFlags is the EVENT-path dispatcher: a click, a hotkey or a
// gesture end reaches it, never the tick. For every heavy flag group it called
// RedrawAllObjects(true), and `force_redraw` bypasses BOTH gates (the 20 ms
// coalescer below is the only guard) - so the WHOLE frame body ran INLINE
// inside OnChartEvent: base price, the ATR composite, UpdateHistoricalValues,
// DrawMainLevels, the label family (ClearAllLabels + four Display* passes),
// RepositionAllOverlayLabels and the custom-price block. The live log names the
// price exactly:
//
//   [PERF] click breakdown: button=0ms panel=0ms apply=531ms
//
// button and panel are ZERO - hit-testing is free and all 531 ms is the refresh
// body. A block that long inside the event handler IS the freeze the user feels,
// and it is the same defect class as the 3375 ms CHART_CHANGE frame: work
// charged to the event instead of to a frame.
//
// So the frame body is never executed inline in a chart event any more. The
// flags the callers already raised stay raised, a heavy frame is marked owed,
// and the frame loop runs it - the next tick, or the 250 ms timer that exists
// anyway to advance staged rebuilds. WHAT is rendered is unchanged; only WHERE
// the cost is charged.
//
// The LIVE DRAG is deliberately exempt: the custom-price drag re-anchors every
// throttled step and its synchronous pass is what makes the levels follow the
// line. Deferring that would trade a freeze for a lag, which is not a fix.
//
// P-PERF-35 - CO-OPERATIVE MULTITASKING: THE THREAD SUBSTITUTE MQL4 ALLOWS.
//
// MQL4 does not have threads. A program gets exactly ONE OS thread and one core:
// there is no `thread`, no `async`, no `Task`, and no in-language way to run two
// functions at the same time. MetaQuotes' own material is explicit that the
// terminal is multi-threaded while each individual program is not, and the only
// two escapes are a DLL (which CAN create an OS thread) and the OpenCL pool
// (MQL5-only). Claiming otherwise would be a lie dressed as an optimisation.
//
// What IS available, and what actually removes the lag, is CONCURRENCY: several
// independent jobs advanced under a millisecond budget, so no job can hold the
// terminal for its whole duration and a job that does not finish is simply still
// owed - nothing to unwind, nothing to re-request. This is the guarantee the
// staged level rebuild already gives (four frames, one family each); the pump
// generalises it so the rebuild, the object cleanup, the label-expiry sweep and
// the live text refresh stop competing for one timer slot that used to be spent
// entirely on whatever ran first.
//
// Single-flight is the other half: three fast presses used to schedule three
// full frames. A job that is already owed is not owed twice.
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

void RedrawAllObjects(bool force_redraw=false)
{
    // P-PERF-02: "this frame painted nothing" is the default; every real draw
    // below sets it, and OnCalculateHandler only spends a chart repaint when it
    // is set (see g_lastRedrawDidWork).
    g_lastRedrawDidWork = false;
    // P-PERF-03: reset the phase ledger for this frame (see the CPU report at
    // the end of OnCalculateHandler).
    g_p3MsBase = 0; g_p3MsAtr = 0; g_p3MsHistory = 0; g_p3MsLevels = 0; g_p3MsLabels = 0; g_p3MsOverlay = 0;
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
    if(force_redraw && g_inChartEvent && !g_customPriceLineDragging)
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
        bool showFractal = (g_thLabelsMode == 1 || g_thLabelsMode == 3);
        bool showStandard = (g_thLabelsMode == 2 || g_thLabelsMode == 3);
        if(g_thLabelsMode != 0 && showFractal)  DisplayFractalTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
        if(g_thLabelsMode != 0 && showStandard) DisplayStandardTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
        if(g_atrLabelsVisible) DisplayATRTradeLabels(objectPrefix);
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

int OnCalculateHandler(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
    static uint s_lastCPUTime = 0;
    static int s_cpuWarningCount = 0;
    uint startTime = GetTickCount();

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
       if(bkNow - s_bkLitePumpMs >= 500) { s_bkLitePumpMs = bkNow; BaseKnotSyncBadges(); TradePlanLiveTick(); }
    }
#endif

    // P-UI-53: the drag lock's watchdog. Steady state: one bool read per tick; the
    // KEYSTATE probe and the restore run only while a gesture still holds the lock.
    CustomPriceDragHealStale();

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

        TH3_PROF_START(RedrawCall);
        RedrawAllObjects(g_redrawTHLevelsNeeded || g_forceClearOnNextDraw);
        TH3_PROF_END(RedrawCall);

        // P-PERF-02: ChartRedraw after RedrawAllObjects — but ONLY when that
        // frame actually painted. The idle frames (nothing pending) used to ask
        // the terminal for a full chart repaint at tick rate anyway.
        if(g_lastRedrawDidWork) {
            g_lastRedrawDidWork = false;
            ThrottledChartRedraw();
        }

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
        string phase = " [base=" + IntegerToString((int)g_p3MsBase) +
                       " atr=" + IntegerToString((int)g_p3MsAtr) +
                       " hist=" + IntegerToString((int)g_p3MsHistory) +
                       " levels=" + IntegerToString((int)g_p3MsLevels) +
                       " labels=" + IntegerToString((int)g_p3MsLabels) +
                       " overlay=" + IntegerToString((int)g_p3MsOverlay) + "]";
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
// P-UI-61 — THE DRAG HAS ONE ANCHOR WRITER AND ONE FRAME OWNER
//
// Reported: «درگ خط کاستوم پرایس روان نیست و لگ داره، و وقتی خط را رها میکنم سطوح
// از یک جای دیگه رسم میشن، همون سطوح نیستن».
//
// Both halves were the same defect: the drag had THREE writers for ONE value,
// and the value the whole ladder is derived from (`g_customTHStartPrice` ->
// `GetMidpointPrice` -> `CalculateCommonStepData.midpointPrice`) was written
// INSIDE the redraw throttle:
//
//   if(nowMs - g_lastDragRedrawTime > DRAG_REDRAW_THROTTLE_MS)
//   {
//       g_customTHStartPrice = currentLinePrice;   // <- the anchor, throttled
//       RedrawAllObjects(true);
//       g_lastDragRedrawTime = nowMs;
//   }
//
// So every event inside the 50 ms window was DROPPED, not deferred: the LINE
// object kept up with the cursor (MT4 moves it natively, our carry writes it) at
// ~30 Hz while the ANCHOR advanced at 20 Hz, i.e. the ladder trailed the line by
// an amount that depended on where the window happened to fall - and nothing was
// owed, so the trailing error was silently lost on the last event before the
// button came up. That is the lag.
//
// The release then made it visible. `RedrawAllObjects` re-resolves the price from
// `CustomPriceResolveSource()` (P-UI-56), which reads the PERSISTED placement - and
// the CARRY channel never persisted (only the native-drag channel did), so the key
// held a price from before the gesture. The resolver's answer disagreed with the
// anchor, the frame's `priceMoved` branch OVERWROTE the anchor with the key's older
// value, and the ladder was rebuilt there: it matched neither the cursor nor the
// picture that was on screen a moment earlier. That is «از یک جای دیگه رسم میشن».
//
// The rules are the project's usual ones: ONE owner for the value, ONE owner for
// the frame, state always current, and a frame that was refused is OWED, never
// dropped.
//
//   * `CustomPriceDragAnchorSet(price)` is the only writer of the anchor during a
//     gesture, and it persists through the P-UI-56 writer so the key can never be
//     older than the anchor (that disagreement WAS the release jump). A price that
//     did not move costs one compare and returns - the steady state is free.
//   * `CustomPriceDragFrame(force)` is the only caller of the heavy pass from the
//     drag, so both event channels share ONE budget instead of each having its own
//     gate on the same stamp; a refused frame sets the owed flag.
//   * The release always settles from the OBJECT (the one value MT4 itself keeps
//     exact) and forces the frame, so the last pixel of the gesture is painted
//     from the current anchor. A click that moved nothing still owes nothing.
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


void OnChartEventHandler(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // Base / Knot tool FIRST: while armed it owns every mouse gesture (no
    // chart-click leak into custom-price/TH3/panels), and committed boxes own
    // their badge/drag/delete events in every state.
    if(BaseKnotOnChartEvent(id, lparam, dparam, sparam)) return;

    bool suppressDeleteEvent = g_suppressDeleteEvents || (g_suppressDeleteEventsUntilMs != 0 && GetTickCount() <= g_suppressDeleteEventsUntilMs);
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
        // TH3TOOL-OFF:
        //#ifndef BUILD_LITE
        //        // Backspace = undo last TH3 drawing point (X, A, B, C placement)
        //        if((int)lparam == 8 && TH3SessionActive()) {
        //            TH3SessionUndo();
        //            return;
        //        }
        //#endif

        //
        // F key   Hide/Show All Objects (fast visibility toggle)
        //

        if(IsHotkeyPressed(lparam, sparam, inpHideKey))
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
            string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
            double currentState = 0.0;
            if(GlobalVariableCheck(gvar_name)) {
                currentState = GlobalVariableGet(gvar_name);
                if(currentState != 0.0 && currentState != 1.0) {
                    currentState = 0.0;
                }
            }
            bool isBecomingHidden = (currentState == 0.0);
            if(!GlobalVariableSet(gvar_name, isBecomingHidden ? 1.0 : 0.0)) {
                LOG_W(LOG_CAT_KEYS, "F key: Failed to set GlobalVariable, Error: " + IntegerToString(GetLastError()));
            }
            RefreshIsHiddenCache();

            if(isBecomingHidden)
            {
                LOG_I(LOG_CAT_KEYS, "F key: Hiding all objects");
                // TH3TOOL-OFF:
                //#ifndef BUILD_LITE
                //                // Cancel ABCD drawing session if active
                //                if(TH3SessionActive()) {
                //                    TH3SessionCancel();
                //                }
                //#endif
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
                bool atrShouldShowF = (g_atrLabelsVisible && inpShowATRLabels);
                int shownTouched = VisibilityShowAllCached(atrShouldShowF, inpShowATRTargets,
                                                           g_triggerLevelsEnabled, g_linesVisible,
                                                           inpShowMidZones);
                p31Touched = shownTouched;
                // Restore label visibility
                ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                // TH3TOOL-OFF:
                //#ifndef BUILD_LITE
                //                ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                //#endif
                ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                // Restore custom price line if active
                if(g_customPriceKeyboardOverride && g_customPriceLineCreated)
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

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
            P4ReportSlow("hide-all toggle (F) [hidden=" + (isBecomingHidden ? "1" : "0") +
                         " touched=" + IntegerToString(p31Touched) +
                         " cache=" + IntegerToString(CacheGetSize()) + "]",
                         GetTickCount() - p26F, P_P4_INIT_WARN_MS);
            // P-PERF-24: one owner for "a discrete action paints now" - it forces
            // the repaint even while hidden, which is what the old bare
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
            double currentPrice = iClose(_Symbol, (ENUM_TIMEFRAMES)GetCachedPeriod(), 0);
            g_customTHStartPrice = currentPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            // P-UI-56: ONE writer for the placement pair (this chart's price + flag).
            CustomPricePersistPlacement(currentPrice);
            // P-UI-48: ONE creator. This block used to write the line's whole
            // property set by hand - the fifth copy of it in the file, and the
            // place a stale OBJPROP_SELECTED had survived longest.
            if(!CreateCustomPriceLine(currentPrice, Digits)) return;
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
            
            // Cycle: FRACTAL (1) -> BOTH (3) [if enabled] -> OFF (0)
            if(g_thLabelsMode == 1) {
                if(inpShowStandardTHs) g_thLabelsMode = 3;
                else g_thLabelsMode = 0;
            }
            else if(g_thLabelsMode == 3) {
                g_thLabelsMode = 0;
            }
            else {
                g_thLabelsMode = 1;
            }

            g_thLabelsVisible = (g_thLabelsMode != 0);
            RequestUISync();   // P-UI-40: the TH LABELS card cycles on this mode
            SyncTHFlagsFromMode();   // flags follow the mode → card never disagrees
            GlobalVariableSet(thGvar, (double)g_thLabelsMode);
            
            string objectPrefix = GetLevelObjectPrefix();
            SetTHLabelsVisibility(objectPrefix, g_thLabelsMode);
            g_labelsRelayoutNeeded = true;
            RedrawLabelsOnly();
            string logMsg = "TH Labels mode=" + IntegerToString(g_thLabelsMode) + " (0=OFF,1=FRACTAL";
            if(inpShowStandardTHs) logMsg += ",3=BOTH";
            logMsg += ")";
            LOG_I(LOG_CAT_LABELS, logMsg);
            ThrottledChartRedraw();
            return;
        }

        //
        // P key   Toggle TH3 Tool — TH3TOOL-OFF: retired with the tool
        //
        // TH3TOOL-OFF:
        //#ifndef BUILD_LITE
        //        if(IsHotkeyPressed(lparam, sparam, inpTH3ToolKey))
        //        {
        //            ToggleTH3Tool();
        //            ThrottledChartRedraw();
        //            return;
        //        }
        //#endif

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
        // 3/4 keys   Adjust TH3 Frequency — TH3TOOL-OFF: retired with the tool
        //
        // TH3TOOL-OFF:
        //#ifndef BUILD_LITE
        //        else if(lparam == '3') { DecrementTH3Frequency(); return; }
        //        else if(lparam == '4') { CycleTH3Frequency(); return; }
        //#endif

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
            // TH3TOOL-OFF:
            //#ifndef BUILD_LITE
            //            g_th3FreqOverride = 0;
            //            g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
            //#endif
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
            g_thLabelsMode = (FactoryDefault(FF_SHOW_TH_LABELS) > 0.5) ? 1 : 0; // Default to FRACTAL if enabled
            g_thLabelsVisible = (g_thLabelsMode != 0);
            // TH3TOOL-OFF:
            //#ifndef BUILD_LITE
            //            if(inpEnableTH3Tool) {
            //                UpdateAllTH3Objects();
            //            }
            //#endif
            // TH3TOOL-OFF:
            //#ifndef BUILD_LITE
            //            // Cancel any active ABCD drawing session
            //            if(TH3SessionActive()) {
            //                TH3SessionCancel();
            //            }
            //#endif
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
            // TH3TOOL-OFF:
            //#ifndef BUILD_LITE
            //            GlobalVariableDel("Biotak_TH3Freq_" + chartIdStr);
            //            GlobalVariableDel("Biotak_TH3FreqIdx_" + chartIdStr);
            //#endif
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
    // ABCD Mouse Event Routing — TH3TOOL-OFF: retired with the tool
    //
    // TH3TOOL-OFF:
    //#ifndef BUILD_LITE
    //    if(TH3SessionActive() ||
    //       id == CHARTEVENT_OBJECT_DRAG ||
    //       id == CHARTEVENT_OBJECT_DELETE ||
    //       id == CHARTEVENT_MOUSE_MOVE) {
    //        OnABCDMouseEvent(id, lparam, dparam, sparam);
    //        if(TH3SessionActive() && id == CHARTEVENT_CLICK) {
    //            return;
    //        }
    //    }
    //#endif

    //  
    // CHARTEVENT_CHART_CHANGE   Layout/Resize/Scroll/Zoom
    //  
    if(id == CHARTEVENT_CHART_CHANGE) {
        if(IsIndicatorHidden()) return;
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
        uint p28redraw = 0, p28labels = 0;
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
        ThrottledChartRedraw();
        if(p28redraw + p28labels + (GetTickCount() - p28t) >= P_P4_EVENT_WARN_MS)
            _LOG_GATE_W Print("[W][PERF] chart change breakdown: redraw=", (int)p28redraw,
                  "ms labels=", (int)p28labels, "ms tail=", (int)(GetTickCount() - p28t), "ms");
        return;
    }

    //  
    // CHARTEVENT_CLICK   Custom Price Click
    //  
    if(id == CHARTEVENT_CLICK && g_waitingForCustomPriceClick)
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
    }

    //  
    // CHARTEVENT_MOUSE_MOVE   Custom Price Drag Detection
    //  
    if(id == CHARTEVENT_MOUSE_MOVE && g_customPriceLineCreated)
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
        if(leftButtonDown)
        {
            if(!g_customPriceLineDragging)
            {
                // WHO owns this gesture: MT4 grabbed the line (SELECTABLE + the
                // terminal's own hit test), OR our press-edge hit test says the
                // press landed on it. The second term is what makes the drag
                // independent of the terminal's selection behaviour - the drag
                // must not disappear because a build/setting never selects the
                // object (the P-BK-16 reality, on the boxes).
                bool terminalGrab = (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED);
                if(terminalGrab || (pressEdge && CustomPriceGrabAt((int)lparam, (int)dparam)))
                {
                    g_customPriceLineDragging = true;
                    g_customPriceDragOwn = true;
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
                else if(pressEdge)
                {
                    // A press that is NOT ours starts somebody else's gesture
                    // (a pan, a box, the ring, a card): the line must not STAY
                    // SELECTED through it, or MT4 moves it with that drag -
                    // which is the interference this cycle started from.
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
                if(g_customPriceDragOwn && !pressEdge && pastSlop && currentLinePrice > 0 &&
                   s_ownGrabCursorPrice > 0)
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
                bool movedByGesture = (s_ownLastWrite > 0.0) ||
                                      MathAbs(g_customTHStartPrice - s_ownGrabPrice) > _Point * 0.5 ||
                                      (settledPrice > 0.0 &&
                                       MathAbs(settledPrice - s_ownGrabPrice) > _Point * 0.5);
                if(movedByGesture)
                {
                    CustomPriceDragAnchorSet(settledPrice);
                    CustomPriceDragFrame(true);   // force: the gesture's last pixel is always painted
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
    // CHARTEVENT_OBJECT_CLICK   ABCD Pattern Selection — TH3TOOL-OFF: retired with the tool
    //
    // TH3TOOL-OFF:
    //#ifndef BUILD_LITE
    //    if(id == CHARTEVENT_OBJECT_CLICK)
    //    {
    //        if(StringFind(sparam, "ABCD_Pattern_") == 0)
    //        {
    //            string patternName = "";
    //            int suffixPos = -1;
    //            if(StringFind(sparam, "_Point_") > 0) suffixPos = StringFind(sparam, "_Point_");
    //            else if(StringFind(sparam, "_Label_") > 0) suffixPos = StringFind(sparam, "_Label_");
    //            else if(StringFind(sparam, "_Line_") > 0) suffixPos = StringFind(sparam, "_Line_");
    //            else if(StringFind(sparam, "_Target_") > 0) suffixPos = StringFind(sparam, "_Target_");
    //            else if(StringFind(sparam, "_Zone") > 0) suffixPos = StringFind(sparam, "_Zone");
    //            if(suffixPos > 0) {
    //                patternName = StringSubstr(sparam, 0, suffixPos);
    //            } else {
    //                patternName = sparam;
    //            }
    //            if(patternName != "") {
    //                SetActiveABCDPattern(patternName);
    //            }
    //        }
    //        else
    //        {
    //            SetActiveABCDPattern("");
    //        }
    //    }
    //#endif
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

    // CRITICAL: Reset stacking offsets and clear old labels
    g_currentLabelYOffset = 0;
    g_currentLabelYOffsetBottom = 0;
    ClearAllLabels(objectPrefix);

    if(g_atrLabelsVisible) {
        DisplayATRLabels(objectPrefix);
    }

    bool showFractal = (g_thLabelsMode == 1 || g_thLabelsMode == 3);
    bool showStandard = (g_thLabelsMode == 2 || g_thLabelsMode == 3);
    if(g_thLabelsMode != 0 && g_dailyClosePriceForTH != EMPTY_VALUE && g_dailyClosePriceForTH > 0.0) {
        if(showFractal)  DisplayFractalTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
        if(showStandard) DisplayStandardTHs(objectPrefix, g_dailyClosePriceForTH, currentTime);
    }
    if(g_atrLabelsVisible) DisplayATRTradeLabels(objectPrefix);
    RefreshLiveCountdown();   // own switch — survives the ATR labels being off
    g_modeLabelYOffset = g_currentLabelYOffset;
    RepositionAllOverlayLabels();
    ThrottledChartRedraw();
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
            if(!g_heavyFramePending) s_coopOwed[job] = false;
            break;
      }

      uint spent  = GetTickCount() - t0;
      uint waited = t0 - s_coopOwedMs[job];
      if(waited >= COOP_WARN_MS || spent >= COOP_WARN_MS)
         _LOG_GATE_W Print("[W][PERF] coop job=", CoopJobName(job), " waited=", (int)waited,
                           "ms ran=", (int)spent, "ms stillOwed=", (CoopOwes(job) ? 1 : 0));

      if(GetTickCount() - sliceStart >= COOP_BUDGET_MS) break;   // this pump's slice is spent
   }
}

#endif // EVENT_HANDLERS_MQH

