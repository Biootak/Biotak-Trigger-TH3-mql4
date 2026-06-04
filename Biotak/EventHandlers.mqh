//+------------------------------------------------------------------+
//| Event Handlers - Version 3.09 GOLD                              |
//| Security & Performance Audit Complete                           |
//+------------------------------------------------------------------+
#property strict

int OnInitHandler() {
    InitializeGlobalCache();
    LoggerSetLevel(inpLogLevel);

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
            g_thLabelsVisible = (g_thLabelsMode != 0);
        } else {
            _LOG_GATE_E Print("[E][GEN] OnInit: Corrupted TH labels state (", DoubleToString(gvarValue, 10), "), resetting");
            g_thLabelsMode = 0; // Default to OFF
            GlobalVariableSet(thLabelsGvarName, 0.0);
            g_thLabelsVisible = false;
        }
    } else {
        g_thLabelsMode = 0; // Default to OFF
        g_thLabelsVisible = false;
    }

    int validationResult = ValidateInputs();
    if(validationResult != INIT_SUCCEEDED) return validationResult;

    ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
    ChartSetInteger(0, CHART_SHOW_GRID, false);
    EventSetTimer(1);
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

    string symbolName = GetCachedSymbol();
    string gvarName = "Biotak_CustomPrice_" + symbolName;
    string overrideFlagName = "Biotak_CustomPriceOverride_" + symbolName;
    int digits = Digits;

    // Validate custom price input
    double validatedCustomPrice = inpCustomTHStartPrice;
    if(validatedCustomPrice < 0.0) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (negative): ", validatedCustomPrice);
        validatedCustomPrice = 0.0;
    }
    if(validatedCustomPrice > 1000000.0) {
        _LOG_GATE_E Print("[E][GEN] OnInit: Invalid custom price (too large): ", validatedCustomPrice);
        validatedCustomPrice = 0.0;
    }

    // Restore keyboard override flag
    g_customPriceKeyboardOverride = GlobalVariableCheck(overrideFlagName) ? (bool)GlobalVariableGet(overrideFlagName) : false;
    double savedPrice = GlobalVariableCheck(gvarName) ? GlobalVariableGet(gvarName) : 0.0;

    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][GEN] === Custom Price Debug (OnInit) ===");
    Print("[D][GEN] inpCustomTHStartPrice: ", inpCustomTHStartPrice);
    Print("[D][GEN] savedPrice: ", savedPrice);
    Print("[D][GEN] override: ", g_customPriceKeyboardOverride);
    #endif

    if(g_customPriceKeyboardOverride && savedPrice > 0.0) {
        g_customTHStartPrice = savedPrice;
        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
        DEBUG_PRINTF("OnInit: Using keyboard/drag price (override): ", DoubleToString(g_customTHStartPrice, digits));
        CreateCustomPriceLine(g_customTHStartPrice, digits);
    } else if(validatedCustomPrice > 0.0) {
        g_customTHStartPrice = validatedCustomPrice;
        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
        g_customPriceKeyboardOverride = false;
        GlobalVariableSet(gvarName, g_customTHStartPrice);
        GlobalVariableSet(overrideFlagName, 0.0);
        GlobalVariableTemp(gvarName);
        GlobalVariableTemp(overrideFlagName);
        DEBUG_PRINTF("OnInit: Using custom price from settings: ", DoubleToString(g_customTHStartPrice, digits));
        CreateCustomPriceLine(g_customTHStartPrice, digits);
    } else if(savedPrice > 0.0) {
        g_customTHStartPrice = savedPrice;
        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
        _LOG_GATE_I Print("[I][GEN] OnInit: Restored custom price from GlobalVariable: ", DoubleToString(g_customTHStartPrice, digits));
        CreateCustomPriceLine(g_customTHStartPrice, digits);
    } else {
        g_customTHStartPrice = 0.0;
        g_thStartPointType = inpTHStartPointType;
        g_customPriceKeyboardOverride = false;
        GlobalVariableDel(gvarName);
        GlobalVariableDel(overrideFlagName);
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

    // Restore timeframe lock state
    string lockFlagName = "Biotak_LockTF_" + chartIdStr;
    if(GlobalVariableCheck(lockFlagName)) {
        g_timeframeLocked = (bool)GlobalVariableGet(lockFlagName);
        GlobalVariableTemp(lockFlagName);
    }
    string lockPeriodName = "Biotak_LockTFPeriod_" + chartIdStr;
    if(GlobalVariableCheck(lockPeriodName)) {
        g_lockedPeriod = (int)GlobalVariableGet(lockPeriodName);
        GlobalVariableTemp(lockPeriodName);
    }

    // Restore step mode with range validation (0..5)
    string stepModeGvarName = "Biotak_StepMode_" + chartIdStr;
    if(GlobalVariableCheck(stepModeGvarName)) {
        int tempMode = (int)GlobalVariableGet(stepModeGvarName);
        if(tempMode >= 0 && tempMode <= 5) {
            g_stepModeOverride = tempMode;
        } else {
            _LOG_GATE_W Print("[W][GEN] OnInit: Corrupted StepMode (", tempMode, "), resetting.");
            GlobalVariableDel(stepModeGvarName);
            g_stepModeOverride = -1;
        }
        GlobalVariableTemp(stepModeGvarName);
    }

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
        GlobalVariableTemp(factorGvarName);
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
        GlobalVariableTemp(freqGvarName);
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
        GlobalVariableTemp(indexGvarName);
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

    UpdateLockStatusLabel();
    PrintBuildInfo();

    // Check if TH3 objects need update (after settings change)
    string th3UpdateFlag = "Biotak_TH3_NeedsUpdate_" + chartIdStr;
    if(GlobalVariableCheck(th3UpdateFlag) && GlobalVariableGet(th3UpdateFlag) > 0) {
        UpdateAllTH3Objects();
        GlobalVariableDel(th3UpdateFlag);
    }

    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][GEN] OnInit complete: deferred=", deferHeavyInit, " hidden=", shouldBeHidden);
    #endif

    // Hidden state: set flags (objects created later in OnCalculate/RedrawAllObjects)
    if(shouldBeHidden) {
        g_redrawTHLevelsNeeded = false;
    } else {
        g_redrawTHLevelsNeeded = true;
    }

    return INIT_SUCCEEDED;
}

// Helper function to create custom price horizontal line (DRY)
bool CreateCustomPriceLine(double price, int digits, bool selected = false, 
                           string tooltipSuffix = "Drag to adjust")
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
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_COLOR, inpCustomPriceLevelColor);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_WIDTH, inpCustomPriceLevelWidth);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, selected);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, 100);
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, 
                  "[PIN] Custom Price: " + DoubleToString(price, digits) + " | " + tooltipSuffix);
    g_customPriceLineCreated = true;
    return true;
}

//| Helper function to hide all TH objects (DRY)                     |
//|                                                                  |
//| Centralized hide logic to avoid code duplication                 |
//| Used by: OnInit, RedrawAllObjects, F key handler                 |
//| COVERS: TH levels, labels, zones, mode labels, custom price      |
//+------------------------------------------------------------------+
void HideAllTHObjects()
{
    int total = ObjectsTotal(0, -1, -1);
    int hiddenCount = 0;
    string cachedPrefix = inpObjectPrefix;
    int prefixLen = StringLen(cachedPrefix);
    // PERF: Pre-compute constants outside loop
    long noPeriodsVal = OBJ_NO_PERIODS;
    ushort prefixFirstChar = StringGetCharacter(cachedPrefix, 0);
    for(int i = total - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, -1);
        // PERF: Quick first-char rejection before expensive string comparison
        if(StringGetCharacter(objName, 0) != prefixFirstChar) continue;
        if(StringLen(objName) >= prefixLen && StringSubstr(objName, 0, prefixLen) == cachedPrefix)
        {
            ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, noPeriodsVal);
            hiddenCount++;
        }
    }
    // PERF: Batch special label hide - ObjectSetInteger is no-op if object doesn't exist
    ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    if(g_customPriceLineCreated)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    // NOTE: ABCD pattern objects are NOT hidden by F key
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
        // OPTIMIZATION: Use Symbol() directly here since this is cleanup code (not in a loop)
        string symbolName = GetCachedSymbol();
        string gvarName = "Biotak_CustomPrice_" + symbolName;
        string overrideFlagName = "Biotak_CustomPriceOverride_" + symbolName;
        // Direct delete (safe if not found)
        GlobalVariableDel(gvarName);

        if(GlobalVariableCheck(overrideFlagName)) {
            GlobalVariableDel(overrideFlagName);
        }
        g_customTHStartPrice = 0.0;
        g_thStartPointType = inpTHStartPointType;
        g_customPriceKeyboardOverride = false; // Reset keyboard override flag
    }
}

//+------------------------------------------------------------------+
//| OnDeinit Handler - cleanup and state persistence (matching MT5)  |
//+------------------------------------------------------------------+
void OnDeinitHandler(const int reason) {
    DEBUG_PRINT("Starting cleanup");
    // Save TF-switch timestamp for deferred init debounce
    if(reason == REASON_CHARTCHANGE || reason == REASON_PARAMETERS) {
        string tfSwitchStampGvar = "Biotak_LastTFSwitch_" + GetCachedChartIdStr();
        datetime nowSwitch = TimeCurrent();
        if(nowSwitch > 0) GlobalVariableSet(tfSwitchStampGvar, (double)nowSwitch);
    }

    ReleaseATRHandle();
    EventKillTimer();

    // PERF: ObjectDelete is safe to call on non-existent objects (returns false, no error)
    // Eliminates ObjectFind syscalls
    ObjectDelete(0, g_stepModeLabelName);
    ObjectDelete(0, g_factorLabelName);
    ObjectDelete(0, g_th3FreqLabelName);
    ObjectDelete(0, g_lockStatusLabelName);
    ObjectDelete(0, g_customPriceHorizontalLineName);

    if(reason == REASON_REMOVE)
    {
        DEBUG_PRINT("Indicator removed - cleaning all GlobalVariables");
        CleanupAllGlobalVariables();
        DeleteAllIndicatorObjects(true);
        ObjectsDeleteAll(0, "TH3_Structure_");
        ObjectsDeleteAll(0, TH3_PATTERN_PREFIX);  // Clean up AB=CD pattern objects
        ObjectsDeleteAll(0, TH3_TEMP_PREFIX);     // Clean up any temp drawing objects
    }
    else if(reason == REASON_PARAMETERS)
    {
        // Clear all ATR and TH labels to apply new settings
        string currentTFStr = IntegerToString(GetCachedPeriod());
        string uniquePrefix = inpObjectPrefix + "TF" + currentTFStr + "_";
        string tfLabels[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN1"};

        // Delete ATR labels
        ObjectDelete(0, uniquePrefix + "ATR_Title");
        for(int i = 0; i < ArraySize(tfLabels); i++) {
            ObjectDelete(0, uniquePrefix + "ATR_" + tfLabels[i]);
            ObjectDelete(0, uniquePrefix + "ATR_Steps_" + tfLabels[i]);
            ObjectDelete(0, uniquePrefix + "ATR_Targets_" + tfLabels[i]);
        }

        // Delete TH labels
        ObjectDelete(0, inpObjectPrefix + "TH_Title");
        for(int i = 0; i < ArraySize(tfLabels); i++) {
            ObjectDelete(0, inpObjectPrefix + "TH_" + tfLabels[i]);
            ObjectDelete(0, inpObjectPrefix + "TH_Steps_" + tfLabels[i]);
            ObjectDelete(0, inpObjectPrefix + "TH_Targets_" + tfLabels[i]);
        }

        string symbolName = GetCachedSymbol();
        string chartIdStrLocal = GetCachedChartIdStr();
        string overrideFlagName = "Biotak_CustomPriceOverride_" + symbolName;
        GlobalVariableSet(overrideFlagName, 0.0);
        string factorGvarName = "Biotak_Factor_" + chartIdStrLocal;
        GlobalVariableDel(factorGvarName);
        g_factorValueOverride = 0.0;
        string linesGvarName = "Biotak_LinesVisible_" + chartIdStrLocal;
        GlobalVariableDel(linesGvarName);
        // ATR labels hotkey override should not survive parameter changes
        string atrLabelsGvarName = "Biotak_ATRLabels_" + chartIdStrLocal;
        GlobalVariableDel(atrLabelsGvarName);
        // TH labels hotkey override should not survive parameter changes
        string thLabelsGvarNameLocal = "Biotak_THLabels_" + chartIdStrLocal;
        GlobalVariableDel(thLabelsGvarNameLocal);
        string th3UpdateFlag = "Biotak_TH3_NeedsUpdate_" + chartIdStrLocal;
        GlobalVariableSet(th3UpdateFlag, 1.0);
        GlobalVariableTemp(th3UpdateFlag);
        DEBUG_PRINT("OnDeinit (REASON_PARAMETERS) - reset overrides");
        DeleteAllIndicatorObjects(false);
    }
    else
    {
        DEBUG_PRINTF("OnDeinit (reason=", reason);
        DeleteAllIndicatorObjects(false);
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
//| Ù¾Ø§Ú© Ú©Ø±Ø¯Ù† ØªÙ…Ø§Ù… Ø³Ø·ÙˆØ­ Ø§Ø² Ù‡Ù…Ù‡ Ù…ÙˆØ¯Ù‡Ø§ Ø¨Ø±Ø§ÛŒ Ø¬Ù„ÙˆÚ¯ÛŒØ±ÛŒ Ø§Ø² ØªØ¯Ø§Ø®Ù„           |
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
        ArrayResize(LEGACY_SUFFIXES, 18);
        int k = 0;
        LEGACY_SUFFIXES[k++] = "MLabel_";
        LEGACY_SUFFIXES[k++] = "MEqLabel_";
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

    g_suppressDeleteEvents = false;

    #ifdef ENABLE_DEBUG_LOGS
    if(totalDeleted > 0) {
        Print("[D][GEN] ClearAllLevels PERF: Deleted ", totalDeleted, " objects via bulk delete");
    }
    #endif

    // PERF: Invalidate matching cache entries
    if(g_objectCacheSize > 0) {
        int prefixLen = StringLen(objectPrefix);
        int invalidated = 0;
        for(int i = 0; i < CACHE_HASH_BUCKETS; i++) {
            if(!g_objectCacheHash[i].occupied) continue;
            if(StringGetCharacter(g_objectCacheHash[i].name, 0) != StringGetCharacter(objectPrefix, 0)) continue;
            if(StringLen(g_objectCacheHash[i].name) >= prefixLen &&
               StringSubstr(g_objectCacheHash[i].name, 0, prefixLen) == objectPrefix) {
                g_objectCacheHash[i].name = "";
                g_objectCacheHash[i].occupied = false;
                g_objectCacheHash[i].deleted = true;
                g_objectCacheHash[i].lastAccess = 0;
                g_objectCacheSize--;
                invalidated++;
                if(g_objectCacheSize == 0) break;
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
//+------------------------------------------------------------------+
//| Helper structure to hold common calculation values              |
//| All values are in PRICE units (matching MotiveWave)             |
//+------------------------------------------------------------------+
struct StepCalculationData {
    double thValue;              // TH value in PRICE units
    double structureValue;       // Structure value in PRICE units
    double patternValue;         // Pattern value in PRICE units
    double triggerValue;         // Trigger value in PRICE units
    double shortStep;            // SS = 1.5 * Structure (PRICE units)
    double longStep;             // LS = 2.0 * Structure (PRICE units)
    double pointSize;            // DEPRECATED: No longer used (set to 1.0)
    double midpointPrice;        // Start point price
    int maxLevelsAbove;          // Adaptive max levels above
    int maxLevelsBelow;          // Adaptive max levels below
};

//| Calculate common values used across all step modes              |
//| TH-based only (ATR basis removed, matching MT5)                |
//+------------------------------------------------------------------+
bool CalculateCommonStepData(const double dailyClosePrice, StepCalculationData &data)
{
    if(dailyClosePrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[E][GEN] CalculateCommonStepData: Invalid daily close price");
        #endif
        return false;
    }

    // OPTIMIZATION: Cache calculation results
    static StepCalculationData s_cachedData;
    static double s_lastDailyClose = 0;
    static string s_lastTF = "";
    static int s_lastStartPointType = -1;
    static double s_lastCustomPrice = 0;
    static int s_lastMaxAbove = 0;
    static int s_lastMaxBelow = 0;
    static double s_lastScalingFactor = 1.0;

    string currentTF = GetFractalTimeframeForCurrent();
    double currentScalingFactor = GetCurrentScalingFactor();

    if(dailyClosePrice == s_lastDailyClose &&
       currentTF == s_lastTF &&
       g_thStartPointType == s_lastStartPointType &&
       (g_thStartPointType != TH_START_POINT_CUSTOM_PRICE || g_customTHStartPrice == s_lastCustomPrice) &&
       inpMaxLevels == s_lastMaxAbove &&
       inpMaxLevels == s_lastMaxBelow &&
       MathAbs(currentScalingFactor - s_lastScalingFactor) < EPSILON_GENERAL &&
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
    if(data.midpointPrice <= 0 || data.midpointPrice == EMPTY_VALUE) {
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

    return true;
}

//+------------------------------------------------------------------+
//| Wrapper function to handle different step calculation modes     |
//+------------------------------------------------------------------+
void DrawLevelsBasedOnMode(const string objectPrefix, const double dailyClosePrice)
{
    // Clear all existing levels from all modes to prevent overlapping
    ClearAllLevels(objectPrefix);
    
    // Draw based on selected mode (respects keyboard override)
    ENUM_STEP_CALCULATION_MODE currentMode = GetCurrentStepMode();
    StepCalculationData data;
    if(!CalculateCommonStepData(dailyClosePrice, data)) return;
    
    double stepSizes[];
    ArrayResize(stepSizes, 2);

    switch(currentMode) {
        case SS_LS_STEP:
        {
            SModeConfig cfg = BuildSSLSConfig(objectPrefix);
            stepSizes[0] = data.shortStep;
            stepSizes[1] = data.longStep;
            ExecutePipeline(cfg, data.midpointPrice, stepSizes, 2,
                           LEVEL_STEP_CUMULATIVE, CLASSIFY_ALTERNATING, inpLSFirst,
                           data.maxLevelsAbove, data.maxLevelsBelow);
            break;
        }
        
        case M_STEP:
        {
            double controlValue = CalculateControlValue(data.shortStep, data.longStep);
            if(inpMStepBasisType == MSTEP_BASIS_C_BASED) {
                SModeConfig cfg = BuildMConfig(objectPrefix);
                stepSizes[0] = controlValue;
                ExecutePipeline(cfg, data.midpointPrice, stepSizes, 1,
                               LEVEL_STEP_UNIFORM, CLASSIFY_MMODE, false,
                               data.maxLevelsAbove, data.maxLevelsBelow);
            } else {
                SModeConfig cfg = BuildMEqualConfig(objectPrefix);
                double mDistance = CalculateMDistance(controlValue);
                stepSizes[0] = mDistance;
                ExecutePipeline(cfg, data.midpointPrice, stepSizes, 1,
                               LEVEL_STEP_UNIFORM, CLASSIFY_STANDARD, false,
                               data.maxLevelsAbove, data.maxLevelsBelow);
            }
            break;
        }
        
        case TP_STEP:
        {
            SModeConfig cfg = BuildTPConfig(objectPrefix);
            double eValue = CalculateEStep(data.thValue);
            double tpValue = CalculateTPStep(eValue);
            stepSizes[0] = tpValue;
            ExecutePipeline(cfg, data.midpointPrice, stepSizes, 1,
                           LEVEL_STEP_UNIFORM, CLASSIFY_STANDARD, false,
                           data.maxLevelsAbove, data.maxLevelsBelow);
            break;
        }
        
        case COMBO_STEP:
        {
            double comboStep = CalculateComboStepSize(dailyClosePrice);
            if(comboStep <= 0) return;
            
            SModeConfig cfg = BuildComboConfig(objectPrefix);
            stepSizes[0] = comboStep;
            ExecutePipeline(cfg, data.midpointPrice, stepSizes, 1,
                           LEVEL_STEP_UNIFORM, CLASSIFY_STANDARD, false,
                           data.maxLevelsAbove, data.maxLevelsBelow);
            break;
        }
        
        case FACTOR_STEP:
        {
            double factorValue;
            if(g_factorValueOverride > 0) factorValue = g_factorValueOverride;
            else if(inpFactorMode == FACTOR_MODE_MANUAL) factorValue = inpFactorValue;
            else factorValue = GetDefaultFactorValue(dailyClosePrice);
            
            factorValue = NormalizeDouble(MathMax(0.01, MathMin(10000, factorValue)), 2);
            UpdateFactorLabel(factorValue);
            
            if(inpEnableHarmonicPattern) {
                SModeConfig cfg = BuildFactorHarmonicConfig(objectPrefix);
                double baseStep = CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
                if(baseStep <= 0) return;
                
                stepSizes[0] = baseStep;
                stepSizes[1] = baseStep * inpHarmonicRatio;
                ExecutePipeline(cfg, data.midpointPrice, stepSizes, 2,
                               LEVEL_STEP_CUMULATIVE, CLASSIFY_STANDARD, false,
                               data.maxLevelsAbove, data.maxLevelsBelow);
            } else {
                SModeConfig cfg = BuildFactorConfig(objectPrefix);
                double factorStep = CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
                if(factorStep <= 0) return;
                
                stepSizes[0] = factorStep;
                ExecutePipeline(cfg, data.midpointPrice, stepSizes, 1,
                               LEVEL_STEP_UNIFORM, CLASSIFY_STANDARD, false,
                               data.maxLevelsAbove, data.maxLevelsBelow);
            }
            break;
        }
        
        case TH_STEP:
        default:
        {
            SModeConfig cfg = BuildTHConfig(objectPrefix);
            stepSizes[0] = data.thValue;
            ExecutePipeline(cfg, data.midpointPrice, stepSizes, 1,
                           LEVEL_STEP_UNIFORM, CLASSIFY_STANDARD, false,
                           data.maxLevelsAbove, data.maxLevelsBelow);
            break;
        }
    }
}

// DEPRECATED: Old helper functions removed
// Base price history is now managed by BasePriceManager.mqh
// Use PrintBasePriceHistory() from BasePriceManager instead

void RedrawAllObjects(bool force_redraw=false)
{
    // PERF: Soft millisecond guard for burst calls (independent from second-based gate)
    static uint s_lastRedrawAttemptMs = 0;
    static uint s_lastForcedRedrawMs = 0;
    uint nowMs = GetTickCount();

    // PERF: Coalesce event-burst forced redraws (very small window, keeps behavior intact)
    if(force_redraw) {
        if(s_lastForcedRedrawMs != 0 && nowMs - s_lastForcedRedrawMs < 20) return;
        s_lastForcedRedrawMs = nowMs;
    }

    // PERF: Refresh cached frame time once â€” eliminates ~2000+ TimeCurrent() syscalls in cache ops
    CacheRefreshFrameTime();
    // PERF: Cache visibility state once per frame â€” skips ~800 ObjectSetInteger calls when unchanged
    CacheRefreshVisibilityState();
    datetime currentTime = TimeGMT();

    // PERF: Idle fast-path â€” when no work is pending, skip expensive UpdateBasePrice/ATR path.
    bool customPriceLineExists = g_customPriceLineCreated;
    bool historicalRefreshDue = (currentTime - g_lastHistoricalUpdate >= 3600 || !g_initialized);
    int currentServerMinute = TimeMinute(CacheGetFrameTime());
    bool basePriceBoundary = (currentServerMinute == 0 || currentServerMinute == 30);
    bool hasPendingWork = (force_redraw || g_labelsRelayoutNeeded || g_redrawTHLevelsNeeded || historicalRefreshDue || basePriceBoundary);
    if(!hasPendingWork) {
        if(nowMs - s_lastRedrawAttemptMs < 35) return;
        s_lastRedrawAttemptMs = nowMs;
        return;
    }

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
    
    // Update ATR Adaptive Scaling factor (only recalculates on new bar close)
    UpdateATRScalingFactor(thBasePrice, s_cachedDigits);
    
    static double s_lastDrawnBasePrice = 0.0;
    bool basePriceChanged = (MathAbs(thBasePrice - s_lastDrawnBasePrice) > s_cachedPoint);
    if(basePriceChanged) {
        s_lastDrawnBasePrice = thBasePrice;
        g_redrawTHLevelsNeeded = true;
    }

    // PERF: Use tracked bool instead of ObjectFind MT5 syscall (~0.5ms saved per frame)
    bool canSkipByState = (!force_redraw && !g_labelsRelayoutNeeded && !basePriceChanged && !g_redrawTHLevelsNeeded && g_initialized);
    if(canSkipByState) {
        // Existing second-level gate (may be zero by config)
        if(currentTime - g_lastCalculation < REDRAW_THROTTLE_SECONDS) return;
        // Additional soft guard for immediate burst calls when second-level throttle is disabled
        if(nowMs - s_lastRedrawAttemptMs < 35) return;
    }
    s_lastRedrawAttemptMs = nowMs;
    g_lastCalculation = currentTime;

    // PERF: Cache objectPrefix - only rebuild when timeframe actually changes
    static string s_cachedObjectPrefix = "";
    static string s_cachedTimeframeStr = "";
    string currentTFStr = GetCurrentTimeframe();
    if(currentTFStr != s_cachedTimeframeStr) {
        s_cachedTimeframeStr = currentTFStr;
        s_cachedObjectPrefix = inpObjectPrefix + "_" + currentTFStr + "_";
    }
    string objectPrefix = s_cachedObjectPrefix;

    static string s_lastPrefix = "";
    if(s_lastPrefix != "" && s_lastPrefix != objectPrefix) {
        ClearAllLevels(s_lastPrefix);
        InvalidateTimeframeDependentCaches();
        InvalidateATRCache();
    }
    s_lastPrefix = objectPrefix;

    #ifdef ENABLE_DEBUG_LOGS
    static datetime s_lastDebugLog = 0;
    if(TimeGMT() - s_lastDebugLog > 60) {
        Print("[D][GEN] [MT4 DEBUG] RedrawAllObjects executing - Bid: ", DoubleToString(Bid, Digits));
        s_lastDebugLog = TimeGMT();
    }
    #endif

    g_dailyClosePriceForTH = thBasePrice;

    // PERFORMANCE: Use cached historical values
    if(currentTime - g_lastHistoricalUpdate >= 3600 || !g_initialized)
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
    }

    // Early exit when hidden - skip all drawing
    if(IsIndicatorHidden()) {
        HideAllTHObjects();
        return;
    }

    DrawMainLevels(objectPrefix);

    bool needLabels = (!g_calculatedOnce) || g_labelsRelayoutNeeded;
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
        TH3_PROF_END(Labels);

        if(!g_calculatedOnce && inpShowTHLevels) g_redrawTHLevelsNeeded = true;
        g_calculatedOnce = true;
        g_labelsRelayoutNeeded = false;
    }

    // FIX: Snapshot final Y offset so mode/lock/factor labels always appear below all data labels
    // Move outside needLabels block to ensure overlay labels are always correctly positioned
    g_modeLabelYOffset = g_currentLabelYOffset;
    RepositionAllOverlayLabels();

    g_dailyClosePriceForTH = thBasePrice;

    string gvarName = "Biotak_CustomPrice_" + s_cachedSymbol;
    string overrideFlagName = "Biotak_CustomPriceOverride_" + s_cachedSymbol;
    bool lineExists = customPriceLineExists;
    double currentLinePrice = lineExists ? ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0) : 0.0;

    if(!g_customPriceLineDragging) {
        bool hasGlobalVar = GlobalVariableCheck(gvarName);
        double savedPrice = hasGlobalVar ? GlobalVariableGet(gvarName) : 0.0;
        
        if(g_customPriceKeyboardOverride && savedPrice > 0.0) {
            if(MathAbs(g_customTHStartPrice - savedPrice) > s_cachedPoint * 0.1) {
                g_customTHStartPrice = savedPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            }
            if(!lineExists) {
                CreateCustomPriceLine(g_customTHStartPrice, s_cachedDigits, false, "Drag to adjust (live update)");
            }
        } else if(inpCustomTHStartPrice > 0.0) {
            if(MathAbs(g_customTHStartPrice - inpCustomTHStartPrice) > s_cachedPoint * 0.1) {
                g_customTHStartPrice = inpCustomTHStartPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
                GlobalVariableSet(gvarName, g_customTHStartPrice);
                if(!lineExists) {
                    CreateCustomPriceLine(g_customTHStartPrice, s_cachedDigits, false, "Drag to adjust (live update)");
                } else {
                    ObjectSetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, g_customTHStartPrice);
                    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, 
                                  "[PIN] Custom Price: " + DoubleToString(g_customTHStartPrice, s_cachedDigits) + " | Drag to adjust (live update)");
                }
                g_redrawTHLevelsNeeded = true;
            }
        } else if(hasGlobalVar && savedPrice > 0.0) {
            if(MathAbs(g_customTHStartPrice - savedPrice) > s_cachedPoint * 0.1) {
                g_customTHStartPrice = savedPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            }
            if(!lineExists) {
                if(CreateCustomPriceLine(g_customTHStartPrice, s_cachedDigits, false, "Drag to adjust (live update)")) {
                    _LOG_GATE_I Print("[I][GEN] Custom price line restored at: ", DoubleToString(g_customTHStartPrice, s_cachedDigits));
                }
            }
        } else {
            g_thStartPointType = inpTHStartPointType;
            g_customTHStartPrice = 0.0;
        }
    }
    
    if (inpShowTHLevels && g_redrawTHLevelsNeeded)
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
        string levelSig = objectPrefix + "|" +
                          IntegerToString((int)modeNow) + "|" +
                          IntegerToString(inpMaxLevels) + "|" +
                          IntegerToString((int)g_thStartPointType) + "|" +
                          IntegerToString(inpLSFirst ? 1 : 0) + "|" +
                          IntegerToString(inpEnableHarmonicPattern ? 1 : 0) + "|" +
                          DoubleToString(inpHarmonicRatio, 3) + "|" +
                          IntegerToString((int)inpMStepBasisType);
        bool levelTopologyChanged = (levelSig != s_lastLevelSig);
        bool shouldClearLevels = g_forceClearOnNextDraw || levelTopologyChanged;

        if(shouldClearLevels) {
            TH3_PROF_START(LevelsClear);
            ClearAllLevels(objectPrefix, !skipZones);
            TH3_PROF_END(LevelsClear);
        }
        TH3_PROF_START(LevelsDrawByMode);
        DrawLevelsBasedOnMode(objectPrefix, g_dailyClosePriceForTH);
        TH3_PROF_END(LevelsDrawByMode);
        s_lastLevelSig = levelSig;
        TH3_PROF_END(Levels);
        g_redrawTHLevelsNeeded = false;
    }
    else if (!inpShowTHLevels && g_redrawTHLevelsNeeded)
    {
        ClearAllLevels(objectPrefix);
        g_redrawTHLevelsNeeded = false;
    }

    CheckAlerts(objectPrefix, g_currentPrice);
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnCalculate Handler (matching MT5: tick throttle + cache inv.)   |
//+------------------------------------------------------------------+
int OnCalculateHandler(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
    static uint s_lastCPUTime = 0;
    static int s_cpuWarningCount = 0;
    uint startTime = GetTickCount();

    // PERF: Cache Bid/Ask once per tick
    CacheTickPrices();

    if(IsIndicatorHidden())
    {
        return(rates_total);
    }

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

        // FIX: ChartRedraw after RedrawAllObjects
        ThrottledChartRedraw();

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
        if(elapsed > CPU_CRITICAL_MS) {
            _LOG_GATE_E Print("[E][GEN] [CRIT] CRITICAL CPU: OnCalculate took ", elapsed, "ms! Reduce inpMaxTHLevels!");
        }
        else if(s_lastCPUTime == 0 || GetTickCount() - s_lastCPUTime > 60000) {
            _LOG_GATE_W Print("[W][GEN] CPU Warning: OnCalculate took ", elapsed, "ms (threshold: ", CPU_WARNING_MS, "ms)");
            s_lastCPUTime = GetTickCount();
        }
    }

    return rates_total;
}

//+------------------------------------------------------------------+
//| Apply Lines Visibility State to All Line Objects                 |
//| Ø§Ø¹Ù…Ø§Ù„ ÙˆØ¶Ø¹ÛŒØª Ù†Ù…Ø§ÛŒØ´ Ø®Ø·ÙˆØ· Ø¨Ù‡ Ù‡Ù…Ù‡ Ø§Ø´ÛŒØ§Ø¡ Ø®Ø·                          |
//|                                                                  |
//| Called after RedrawAllObjects to ensure g_linesVisible is       |
//| respected for all line objects (HLINE and TREND)                 |

void OnChartEventHandler(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN)
    {
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // F key â€” Hide/Show All Objects (fast visibility toggle)
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpHideKey))
        {
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
                // Cancel ABCD drawing mode if active
                if(g_abcdDrawing) {
                    g_abcdDrawing = false;
                    g_abcdPointCount = 0;
                    g_suppressDeleteEvents = true;
                    ObjectsDeleteAll(0, TH3_TEMP_PREFIX);
                    ObjectsDeleteAll(0, TH3_TEMP_LINE_PREFIX);
                    g_suppressDeleteEvents = false;
                    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
                    Comment("");
                }
                HideAllTHObjects();
                CleanupCustomPriceObjects(false, true);
                g_redrawTHLevelsNeeded = false;
            }
            else
            {
                LOG_I(LOG_CAT_KEYS, "F key: Showing all objects");
                // Fast show: toggle visibility instead of delete+recreate
                int total = ObjectsTotal(0, -1, -1);
                string cachedPrefixF = inpObjectPrefix;
                int prefixLenF = StringLen(cachedPrefixF);
                ushort prefixFirstCharF = StringGetCharacter(cachedPrefixF, 0);
                for(int i = total - 1; i >= 0; i--)
                {
                    string objName = ObjectName(0, i, -1, -1);
                    if(StringGetCharacter(objName, 0) != prefixFirstCharF) continue;
                    if(StringLen(objName) >= prefixLenF && StringSubstr(objName, 0, prefixLenF) == cachedPrefixF)
                    {
                        // Keep ATR objects hidden if ATR labels are disabled
                        bool isATRObject = (StringFind(objName, "ATR_") >= 0);
                        if(isATRObject) {
                            bool atrShouldShow = (g_atrLabelsVisible && inpShowATRLabels);
                            if(!atrShouldShow) {
                                ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                            } else {
                                if(StringFind(objName, "ATR_Targets_") >= 0 && !inpShowATRTargets)
                                    ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                                else
                                    ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                            }
                            continue;
                        }
                        // Keep trigger objects hidden if triggers are disabled
                        bool isTriggerObject = (StringFind(objName, "TriggerTH_Up_") >= 0 || 
                                                StringFind(objName, "TriggerTH_Down_") >= 0);
                        if(isTriggerObject && !g_triggerLevelsEnabled)
                        {
                            ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                        }
                        else if(!g_linesVisible)
                        {
                            int objType = (int)ObjectGetInteger(0, objName, OBJPROP_TYPE);
                            if(objType == OBJ_HLINE || objType == OBJ_TREND)
                            {
                                ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                            }
                            else
                            {
                                ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                            }
                        }
                        else
                        {
                            ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                        }
                    }
                }
                // Restore label visibility
                ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                // Restore custom price line if active
                if(g_customPriceKeyboardOverride && g_customPriceLineCreated)
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

                g_redrawTHLevelsNeeded = true;
                // Re-apply label visibility consistently
                string objectPrefixLocal = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_";
                SetATRLabelsVisibility(objectPrefixLocal, (g_atrLabelsVisible && inpShowATRLabels));
                SetTHLabelsVisibility(objectPrefixLocal, (inpShowTHLabels ? g_thLabelsMode : 0));
            }
            // Direct ChartRedraw for F key (ThrottledChartRedraw skips when hidden)
            ChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // L key â€” Toggle Lines Visibility
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpLinesToggleKey))
        {
            g_linesVisible = !g_linesVisible;
            UpdateLinesVisibleCache(g_linesVisible);
            string gvar_name = "Biotak_LinesVisible_" + GetCachedChartIdStr();
            GlobalVariableSet(gvar_name, g_linesVisible ? 1.0 : 0.0);
            int total = ObjectsTotal(0, -1, -1);
            string cachedPrefixL = inpObjectPrefix;
            int prefixLenL = StringLen(cachedPrefixL);
            ushort prefixFirstCharL = StringGetCharacter(cachedPrefixL, 0);
            for(int i = 0; i < total; i++)
            {
                string objName = ObjectName(0, i, -1, -1);
                if(StringGetCharacter(objName, 0) != prefixFirstCharL) continue;
                if(StringLen(objName) >= prefixLenL && StringSubstr(objName, 0, prefixLenL) == cachedPrefixL)
                {
                    int objType = (int)ObjectGetInteger(0, objName, OBJPROP_TYPE);
                    if(objType == OBJ_HLINE || objType == OBJ_TREND)
                    {
                        if(g_linesVisible)
                            ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                        else
                            ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                    }
                }
            }
            LOG_I(LOG_CAT_LINES, "Lines " + (g_linesVisible ? "VISIBLE" : "HIDDEN"));
            ThrottledChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // C key â€” Set Custom Price
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpCustomPriceKey))
        {
            g_waitingForCustomPriceClick = true;
            g_customPriceKeyboardOverride = true;
            string overrideFlagName = "Biotak_CustomPriceOverride_" + GetCachedSymbol();
            GlobalVariableSet(overrideFlagName, 1.0);
            _LOG_GATE_D Print("[D][GEN] Press anywhere on the chart to set custom TH start price");
            ObjectDelete(0, g_customPriceHorizontalLineName);
            g_customPriceLineCreated = false;
            double currentPrice = iClose(_Symbol, (ENUM_TIMEFRAMES)GetCachedPeriod(), 0);
            g_customTHStartPrice = currentPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            string gvarName = "Biotak_CustomPrice_" + GetCachedSymbol();
            GlobalVariableSet(gvarName, currentPrice);
            if(!ObjectCreate(0, g_customPriceHorizontalLineName, OBJ_HLINE, 0, 0, currentPrice)) {
                _LOG_GATE_E Print("[E][GEN] Failed to create custom price horizontal line. Error: ", GetLastError());
                return;
            }
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_COLOR, inpCustomPriceLevelColor);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_WIDTH, inpCustomPriceLevelWidth);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, 100);
            ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, 
                          "[PIN] Custom Price: " + DoubleToString(currentPrice, Digits) + " | Drag to adjust, Double-click to confirm");
            g_customPriceLineCreated = true;
            g_redrawTHLevelsNeeded = true;
            _LOG_GATE_D Print("[D][GEN] [PIN] Custom price set to: ", DoubleToString(currentPrice, Digits), " - Drag to adjust.");
            ThrottledChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // ESC key â€” Cancel Custom Price
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(lparam == 27)
        {
            string symbolName = GetCachedSymbol();
            string gvarName = "Biotak_CustomPrice_" + symbolName;
            string overrideFlagName = "Biotak_CustomPriceOverride_" + symbolName;
            bool customPriceActive = GlobalVariableCheck(gvarName);
            if(g_waitingForCustomPriceClick || customPriceActive || g_customPriceKeyboardOverride)
            {
                CleanupCustomPriceObjects(true, true);
                g_thStartPointType = inpTHStartPointType;
                g_customPriceKeyboardOverride = false;
                GlobalVariableSet(overrideFlagName, 0.0);
                g_forceClearOnNextDraw = true;
                g_redrawTHLevelsNeeded = true;
                RedrawAllObjects(true);
                _LOG_GATE_D Print("[D][GEN] Custom price mode cancelled - returned to Input Parameter setting");
                ThrottledChartRedraw();
                return;
            }
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // T key â€” Toggle Trigger Levels
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpTriggerLevelsKey))
        {
            g_triggerLevelsEnabled = !g_triggerLevelsEnabled;
            string triggerGvarName = "Biotak_TriggerLevels_" + GetCachedChartIdStr();
            GlobalVariableSet(triggerGvarName, g_triggerLevelsEnabled);
            if(g_triggerLevelsEnabled) {
                LOG_I(LOG_CAT_KEYS, "Trigger Levels: ON");
            } else {
                LOG_I(LOG_CAT_KEYS, "Trigger Levels: OFF");
            }
            g_forceClearOnNextDraw = true;
            g_redrawTHLevelsNeeded = true;
            if(!g_customPriceLineDragging)
                RedrawAllObjects(true);
            ThrottledChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // A key â€” Toggle ATR Labels
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpATRLabelsKey))
        {
            string atrGvarNameKey = "Biotak_ATRLabels_" + GetCachedChartIdStr();
            g_atrLabelsVisible = !g_atrLabelsVisible;
            GlobalVariableSet(atrGvarNameKey, g_atrLabelsVisible ? 1.0 : 0.0);
            
            string objectPrefix = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_";
            SetATRLabelsVisibility(objectPrefix, g_atrLabelsVisible); 
            g_labelsRelayoutNeeded = true;
            RedrawLabelsOnly();
            LOG_I(LOG_CAT_LABELS, "ATR Labels " + (g_atrLabelsVisible ? "VISIBLE" : "HIDDEN"));
            ThrottledChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // S key â€” Cycle TH Labels Mode
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            GlobalVariableSet(thGvar, (double)g_thLabelsMode);
            
            string objectPrefix = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_";
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

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // P key â€” Toggle TH3 Tool
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpTH3ToolKey))
        {
            ToggleTH3Tool();
            ThrottledChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // E key â€” Cycle Step Mode
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpStepModeKey))
        {
            ENUM_STEP_CALCULATION_MODE currentMode = GetCurrentStepMode();
            ENUM_STEP_CALCULATION_MODE newMode = (ENUM_STEP_CALCULATION_MODE)(((int)currentMode + 1) % 6);
            g_stepModeOverride = (int)newMode;
            string stepModeGvarName = "Biotak_StepMode_" + GetCachedChartIdStr();
            GlobalVariableSet(stepModeGvarName, g_stepModeOverride);
            LOG_IP1(LOG_CAT_KEYS, "Step Mode changed to: ", IntegerToString(g_stepModeOverride));
            g_forceClearOnNextDraw = true;
            g_redrawTHLevelsNeeded = true;
            g_calculatedOnce = false;
            RedrawAllObjects(true);
            UpdateStepModeLabel();
            ThrottledChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // 1/2 keys â€” Adjust Factor (always active)
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(lparam == '1') { AdjustFactorValue(-1); return; }
        else if(lparam == '2') { AdjustFactorValue(+1); return; }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // 3/4 keys â€” Adjust TH3 Frequency
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        else if(lparam == '3') { DecrementTH3Frequency(); return; }
        else if(lparam == '4') { CycleTH3Frequency(); return; }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // R key â€” Reset All Overrides
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpResetKey))
        {
            g_stepModeOverride = -1;
            g_factorValueOverride = 0;
            g_th3FreqOverride = 0;
            g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
            g_timeframeLocked = false;
            g_lockedPeriod = 0;
            g_triggerLevelsEnabled = inpShowTrigger;
            g_linesVisible = inpShowLines;
            InvalidateAllVisibilityCaches();
            g_atrLabelsVisible = inpShowATRLabels;
            g_thLabelsMode = inpShowTHLabels ? 1 : 0; // Default to FRACTAL if enabled
            g_thLabelsVisible = (g_thLabelsMode != 0);
            if(inpEnableTH3Tool) {
                UpdateAllTH3Objects();
            }
            // Cancel any active ABCD drawing
            if(g_abcdDrawing) {
                g_abcdDrawing = false;
                g_abcdPointCount = 0;
                g_suppressDeleteEvents = true;
                ObjectsDeleteAll(0, TH3_TEMP_PREFIX);
                ObjectsDeleteAll(0, TH3_TEMP_LINE_PREFIX);
                g_suppressDeleteEvents = false;
            }
            g_customPriceKeyboardOverride = false;
            g_thStartPointType = inpTHStartPointType;
            g_customTHStartPrice = inpCustomTHStartPrice;
            string chartIdStr = GetCachedChartIdStr();
            string symbolName = GetCachedSymbol();
            GlobalVariableDel("Biotak_StepMode_" + chartIdStr);
            GlobalVariableDel("Biotak_Factor_" + chartIdStr);
            GlobalVariableDel("Biotak_LockTF_" + chartIdStr);
            GlobalVariableDel("Biotak_LockTFPeriod_" + chartIdStr);
            GlobalVariableDel("Biotak_TriggerLevels_" + chartIdStr);
            GlobalVariableDel("Biotak_LinesVisible_" + chartIdStr);
            GlobalVariableDel("Biotak_ATRLabels_" + chartIdStr);
            GlobalVariableDel("Biotak_THLabels_" + chartIdStr);
            GlobalVariableDel("Biotak_CustomPriceOverride_" + symbolName);
            GlobalVariableDel("Biotak_TH3Freq_" + chartIdStr);
            GlobalVariableDel("Biotak_TH3FreqIdx_" + chartIdStr);
            if(inpCustomTHStartPrice > 0.0) {
                GlobalVariableSet("Biotak_CustomPrice_" + symbolName, inpCustomTHStartPrice);
                CreateCustomPriceLine(inpCustomTHStartPrice, Digits);
            } else {
                if(GlobalVariableCheck("Biotak_CustomPrice_" + symbolName)) GlobalVariableDel("Biotak_CustomPrice_" + symbolName);
                ObjectDelete(0, g_customPriceHorizontalLineName);
                g_customPriceLineCreated = false;
            }
            UpdateLockStatusLabel();
            Comment("\n\n        [ RESET ]");
            g_resetCommentCreateTime = GetTickCount();
            LOG_I(LOG_CAT_KEYS, "Reset: All overrides cleared");
            ClearAllModeLabels();
            EventSetTimer(1);
            g_forceClearOnNextDraw = true;
            g_calculatedOnce = false;
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            ThrottledChartRedraw();
            return;
        }

        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // K key â€” Toggle Timeframe Lock
        // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        if(IsHotkeyPressed(lparam, sparam, inpLockKey))
        {
            bool hadCustomPrice = (ObjectFind(0, g_customPriceHorizontalLineName) >= 0);
            double savedCustomPrice = hadCustomPrice ? ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0) : 0;
            g_suppressDeleteEvents = true;
            ObjectsDeleteAll(0, inpObjectPrefix);
            g_suppressDeleteEvents = false;
            g_timeframeLocked = !g_timeframeLocked;
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
                if(ObjectCreate(0, g_customPriceHorizontalLineName, OBJ_HLINE, 0, 0, savedCustomPrice)) {
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_COLOR, inpCustomPriceLevelColor);
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_STYLE, STYLE_SOLID);
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_WIDTH, inpCustomPriceLevelWidth);
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);
                    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, 100);
                    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, 
                                  "[PIN] Custom Price: " + DoubleToString(savedCustomPrice, Digits) + " | Drag to adjust (live update)");
                    g_customPriceLineCreated = true;
                }
            }
            ThrottledChartRedraw();
            return;
        }
    } // end CHARTEVENT_KEYDOWN

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // ABCD Mouse Event Routing
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if(g_abcdDrawing || 
       id == CHARTEVENT_OBJECT_DRAG || 
       id == CHARTEVENT_OBJECT_DELETE ||
       id == CHARTEVENT_MOUSE_MOVE) {
        OnABCDMouseEvent(id, lparam, dparam, sparam);
        if(g_abcdDrawing && id == CHARTEVENT_CLICK) {
            return;
        }
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // CHARTEVENT_CHART_CHANGE â€” Layout/Resize/Scroll/Zoom
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if(id == CHARTEVENT_CHART_CHANGE) {
        if(IsIndicatorHidden()) return;
        static uint s_lastLayoutMs = 0;
        static int s_lastW = -1;
        static int s_lastH = -1;
        static double s_lastVisibleMin = 0;
        static double s_lastVisibleMax = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastLayoutMs < CHART_CHANGE_THROTTLE_MS) return;

        int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
        int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
        bool sizeChanged = (w != s_lastW || h != s_lastH);
        
        double visibleMin = ChartGetDouble(0, CHART_PRICE_MIN);
        double visibleMax = ChartGetDouble(0, CHART_PRICE_MAX);
        bool viewportChanged = (MathAbs(visibleMin - s_lastVisibleMin) > GetCachedPoint() ||
                                MathAbs(visibleMax - s_lastVisibleMax) > GetCachedPoint());
        
        if(!sizeChanged && !viewportChanged) return;
        
        s_lastW = w;
        s_lastH = h;
        s_lastVisibleMin = visibleMin;
        s_lastVisibleMax = visibleMax;
        s_lastLayoutMs = nowMs;

        if(sizeChanged) g_labelsRelayoutNeeded = true;
        if(sizeChanged) RedrawLabelsOnly();
        ThrottledChartRedraw();
        return;
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // CHARTEVENT_CLICK â€” Custom Price Click
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
            if(!ObjectCreate(0, g_customPriceHorizontalLineName, OBJ_HLINE, 0, 0, clickedPrice)) {
                _LOG_GATE_E Print("[E][GEN] Failed to create custom price horizontal line. Error: ", GetLastError());
                return;
            }
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_COLOR, inpCustomPriceLevelColor);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_WIDTH, inpCustomPriceLevelWidth);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, 100);
            ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, "[PIN] Custom Price Line - Drag to adjust, Double-click to confirm");
            g_customPriceLineCreated = true;
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
                string symbolName = GetCachedSymbol();
                string gvarName = "Biotak_CustomPrice_" + symbolName;
                string overrideFlagName = "Biotak_CustomPriceOverride_" + symbolName;
                GlobalVariableSet(gvarName, selectedPrice);
                GlobalVariableSet(overrideFlagName, 1.0);
                ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, "[PIN] Custom Price: " + DoubleToString(selectedPrice, Digits) + " | Drag to adjust (live update)");
                ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);
                g_customPriceLineCreated = true;
                g_redrawTHLevelsNeeded = true;
                RedrawAllObjects(true);
                _LOG_GATE_I Print("[I][GEN] Custom Price Mode activated! Using ", inpMaxLevels, " levels above/below price: ", DoubleToString(selectedPrice, Digits));
            }
        }
        ThrottledChartRedraw();
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // CHARTEVENT_OBJECT_CLICK â€” Custom Price Line / ABCD Pattern
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_customPriceHorizontalLineName)
    {
        uint currentTickCount = GetTickCount();
        bool isDoubleClick = (currentTickCount - g_lastClickTickCount < DOUBLE_CLICK_THRESHOLD_MS);
        g_lastClickTickCount = currentTickCount;
        if (isDoubleClick)
        {
            g_waitingForCustomPriceClick = false;
            g_customPriceKeyboardOverride = true;
            double selectedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
            g_customTHStartPrice = selectedPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            string symbolName = GetCachedSymbol();
            string gvarName = "Biotak_CustomPrice_" + symbolName;
            string overrideFlagName = "Biotak_CustomPriceOverride_" + symbolName;
            GlobalVariableSet(gvarName, selectedPrice);
            GlobalVariableSet(overrideFlagName, 1.0);
            ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, "[PIN] Custom Price: " + DoubleToString(selectedPrice, Digits) + " | Drag to adjust (live update)");
            ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, true);
            g_customPriceLineCreated = true;
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            _LOG_GATE_I Print("[I][GEN] Custom Price Mode activated! Using ", inpMaxLevels, " levels above/below price: ", DoubleToString(selectedPrice, Digits));
        }
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // CHARTEVENT_MOUSE_MOVE â€” Custom Price Drag Detection
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if(id == CHARTEVENT_MOUSE_MOVE && g_customPriceLineCreated)
    {
        int mouseFlags = (int)StringToInteger(sparam);
        bool leftButtonDown = (mouseFlags & 1) != 0;
        if(leftButtonDown)
        {
            bool lineSelected = (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED);
            if(lineSelected)
            {
                g_customPriceLineDragging = true;
                double currentLinePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                if(currentLinePrice > 0 && MathAbs(currentLinePrice - g_customTHStartPrice) > _Point * 0.5)
                {
                    uint nowMs = GetTickCount();
                    if(nowMs - g_lastDragRedrawTime > DRAG_REDRAW_THROTTLE_MS)
                    {
                        g_customTHStartPrice = currentLinePrice;
                        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
                        g_redrawTHLevelsNeeded = true;
                        RedrawAllObjects(true);
                        ThrottledChartRedraw();
                        g_lastDragRedrawTime = nowMs;
                    }
                }
            }
        }
        else
        {
            if(g_customPriceLineDragging) {
                g_customPriceLineDragging = false;
                g_forceClearOnNextDraw = true;
                g_redrawTHLevelsNeeded = true;
                RedrawAllObjects(true);
                ThrottledChartRedraw();
            }
        }
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // CHARTEVENT_OBJECT_DRAG â€” Custom Price Line Drag End
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_customPriceHorizontalLineName)
    {
        g_customPriceLineDragging = false;
        double draggedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
        g_customTHStartPrice = draggedPrice;
        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
        g_customPriceKeyboardOverride = true;
        string symbolName = GetCachedSymbol();
        string gvarName = "Biotak_CustomPrice_" + symbolName;
        string overrideFlagName = "Biotak_CustomPriceOverride_" + symbolName;
        GlobalVariableSet(gvarName, draggedPrice);
        GlobalVariableSet(overrideFlagName, 1.0);
        if (g_waitingForCustomPriceClick) {
            string tooltip = "Current price: " + DoubleToString(draggedPrice, Digits) + " - Double-click to confirm";
            ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, tooltip);
        } else {
            string tooltip = "Custom TH start price: " + DoubleToString(draggedPrice, Digits) + " - Drag to adjust";
            ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, tooltip);
            _LOG_GATE_D Print("[D][GEN] Custom TH start price updated to: ", DoubleToString(draggedPrice, Digits));
        }
        g_forceClearOnNextDraw = true;
        g_redrawTHLevelsNeeded = true;
        RedrawAllObjects(true);
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // CHARTEVENT_OBJECT_CLICK â€” ABCD Pattern Selection
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        else
        {
            SetActiveABCDPattern("");
        }
    }
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
    ObjectsDeleteAll(0, inpObjectPrefix);
    if(!deepCleanup) return;
    SModeSuffixEntry entries[];
    int entryCount = 0;
    GetAllModeSuffixes(entries, entryCount);
    for(int i = 0; i < entryCount; i++) {
        ObjectsDeleteAll(0, inpObjectPrefix + entries[i].zoneSuffix);
        ObjectsDeleteAll(0, inpObjectPrefix + entries[i].zoneCenter);
        ObjectsDeleteAll(0, inpObjectPrefix + entries[i].levelAbove);
        ObjectsDeleteAll(0, inpObjectPrefix + entries[i].levelBelow);
        ObjectsDeleteAll(0, inpObjectPrefix + entries[i].midpoint);
    }
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
        CacheRemoveObject(objName);
        g_suppressDeleteEvents = true;
        if(ObjectDelete(0, objName)) deleted++;
        g_suppressDeleteEvents = false;
    }
    _LOG_GATE_I Print("[I][GEN] Emergency cleanup deleted=", deleted,
                      " | before=", total, " | after=", ObjectsTotal(0, -1, -1));
    InvalidateObjectCountCache();
}

void ApplyCacheInvalidation(const int invalidationFlags,
                            const int previousPeriod,
                            const int currentPeriod,
                            const double previousCustomPrice,
                            const double currentCustomPrice)
{
    if((invalidationFlags & CACHE_INV_TIMEFRAME) != 0) {
        InvalidateTimeframeDependentCaches();
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
        string objectPrefix = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_";
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

            if(StringFind(objName, "TH3_Structure_") == 0) continue;
            if(StringLen(objName) >= currentPrefixLen && StringSubstr(objName, 0, currentPrefixLen) == objectPrefix) continue;

            datetime objTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME);
            if(objTime > 0 && objTime < cutoffTime) {
                CacheRemoveObject(objName);
                g_suppressDeleteEvents = true;
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
    string objectPrefix = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_";

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
    g_modeLabelYOffset = g_currentLabelYOffset;
    RepositionAllOverlayLabels();
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| HELPER: Adjust factor value by step (+1 = increase, -1 = decrease)|
//+------------------------------------------------------------------+
void AdjustFactorValue(int direction)
{
    double currentFactor = g_factorValueOverride;
    if(currentFactor <= 0) {
        if(inpFactorMode == FACTOR_MODE_MANUAL && inpFactorValue > 0) {
            currentFactor = inpFactorValue;
        } else {
            currentFactor = GetDefaultFactorValue(g_dailyClosePriceForTH);
            if(currentFactor <= 0 || currentFactor > MAX_FACTOR_VALUE) {
                _LOG_GATE_E Print("[E][GEN] Factor adjust: Invalid factor, using ", DEFAULT_FACTOR_FALLBACK);
                currentFactor = DEFAULT_FACTOR_FALLBACK;
            }
        }
    }
    double step = (inpFactorAdjustStep > 0) ? inpFactorAdjustStep : DEFAULT_FACTOR_ADJUST_STEP;
    double newFactor = NormalizeDouble(currentFactor + step * direction, 2);
    if(newFactor < MIN_FACTOR_VALUE) newFactor = MIN_FACTOR_VALUE;
    if(newFactor > MAX_FACTOR_VALUE) newFactor = MAX_FACTOR_VALUE;
    g_factorValueOverride = newFactor;
    string factorGvarName = "Biotak_Factor_" + GetCachedChartIdStr();
    if(!GlobalVariableSet(factorGvarName, g_factorValueOverride)) {
        _LOG_GATE_E Print("[E][GEN] WARNING: Failed to persist Factor value to GlobalVariable");
    }
    g_forceClearOnNextDraw = true;
    g_redrawTHLevelsNeeded = true;
    RedrawAllObjects(true);
    UpdateFactorLabel(newFactor);
    ThrottledChartRedraw();
}

