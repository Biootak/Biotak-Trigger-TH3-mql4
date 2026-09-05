  #ifndef GLOBAL_VARIABLES_MQH
#define GLOBAL_VARIABLES_MQH

// Core State
static double g_highestHigh = EMPTY_VALUE;
static double g_lowestLow = EMPTY_VALUE;
static double g_currentPrice = 0.0;
static datetime g_lastCalculation = 0;
static datetime g_lastHistoricalUpdate = 0;
static bool g_initialized = false;
static bool g_calculatedOnce = false;
static bool g_labelsRelayoutNeeded = false;
static double g_dailyClosePriceForTH = EMPTY_VALUE;
bool g_redrawTHLevelsNeeded = true;
bool g_forceClearOnNextDraw = false;
// g_viewportOnlyRedraw removed   scroll no longer triggers level redraw
int g_currentLabelYOffset = 0;       // Cumulative Y offset for stacking top label sections (ATR)
int g_currentLabelYOffsetBottom = 0;  // Cumulative Y offset for stacking bottom label sections (TH)
int g_modeLabelYOffset = 0;           // Final Y offset after all labels rendered
static bool g_redrawNeeded = true;

// Performance Tracking
static int g_objectCountLast = 0;
static datetime g_lastObjectCleanup = 0;

// Custom Price Selection
static bool g_waitingForCustomPriceClick = false;
static string g_customPriceHorizontalLineName = "CustomPriceHorizontalLine";
static bool g_customPriceLineCreated = false;
static double g_customTHStartPrice = 0.0;
static ENUM_TH_START_POINT_TYPE g_thStartPointType = TH_START_POINT_PREVIOUS_CLOSE;
static uint g_lastClickTickCount = 0;
static bool g_customPriceLineDragging = false;
static double g_lastCustomPriceLinePos = 0.0;
static bool g_customPriceKeyboardOverride = false;

// Toggle States (hotkey-controlled)
// NOTE: g_triggerLevelsEnabled moved to RuntimeSettings.mqh — it is the runtime
// copy of inpShowTrigger (seeded at attach) and doubles as the hotkey toggle.
static bool g_linesVisible = true;
static bool g_atrLabelsVisible = true;
static bool g_thLabelsVisible = true;
static int  g_thLabelsMode = 0; // 0=OFF, 1=FRACTAL, 2=STANDARD, 3=BOTH

//--- TH labels single source of truth: g_thLabelsMode drives the drawing and
//    the hotkey cycle; the flag mirrors (g_showTHLabels / g_showFractalTHs /
//    g_showStandardTHs in RuntimeSettings) are derived FROM it so the settings
//    card can never disagree with what is actually drawn. Call SyncTHFlagsFromMode()
//    after ANY change to g_thLabelsMode.
int THModeFromFlags()
{
   if(g_showFractalTHs && g_showStandardTHs) return 3;
   if(g_showFractalTHs)                      return 1;
   if(g_showStandardTHs)                     return 2;
   return 0;
}

void SyncTHFlagsFromMode()
{
   g_thLabelsVisible    = (g_thLabelsMode != 0);
   g_showTHLabels       = (g_thLabelsMode != 0);
   g_showFractalTHs     = (g_thLabelsMode == 1 || g_thLabelsMode == 3);
   g_showStandardTHs    = (g_thLabelsMode == 2 || g_thLabelsMode == 3);
}
// STEPOVERRIDE-OFF (2026-09-05, user decision): single Step Mode — the override
// layer is retired. E / Tools-ring / panel all write g_stepCalculationMode now.
// static int g_stepModeOverride = -1;        // -1 = Auto (follow CALC MODE), 0-3 = force TH/SS-LS/Combo/Factor
static int g_sslsFirstOverride = -1;       // -1 = use inpLSFirst, 0 = SS first, 1 = LS first
static double g_factorValueOverride = 0;   // 0 = use input, >0 = override
static int g_factorColorOverride = -1;     // -1 = use input
#ifndef BUILD_LITE
static double g_th3FreqOverride = 0;       // 0 = use input, >0 = override
static int    g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX; // Binary subdivision index
#endif

// Alert Tracking
static datetime g_lastAlertTime = 0;
static string g_lastAlertLevel = "";

// Timeframe Lock (keyboard-only since 2026-09-04: no menu item, no card)
static bool g_timeframeLocked = false;
static int g_lockedPeriod = 0;
// VIEWLOCK-OFF (2026-09-05, user decision): View Lock retired — the state +
// core fns below are kept compiling DORMANT (same pattern as TH3TOOL-OFF
// remnants) so the feature restores by uncommenting the VIEWLOCK-OFF call
// sites. Nothing sets g_viewLockEnabled anymore — it stays false forever.
// View Lock — keep the same chart view (bar position + price range) when the
// user switches timeframes. Toggled from the ring menu (VLOCK slot), the
// View Lock card, or the V hotkey. Anchor = first-visible-bar time + visible
// price min/max, captured on scroll/zoom (CHARTEVENT_CHART_CHANGE), at
// enable time, and persisted at the TF-switch handoff (OnDeinit
// REASON_CHARTCHANGE → OnInit → first OnCalculate restores).
static bool g_viewLockEnabled = false;
static datetime g_viewAnchorTime = 0;
static double g_viewAnchorMin = 0.0;
static double g_viewAnchorMax = 0.0;
static bool g_viewRestorePending = false;
// Anchor handle: draggable vertical line showing the locked view's time.
// Created/moved only by ViewAnchorLineEnsure(); deleting it turns the lock off.
static string g_viewAnchorLineName = "Biotak_ViewAnchor_Line";
static string g_lockStatusLabelName = "Biotak_LockStatus_Label";
static string g_stepModeLabelName = "Biotak_StepMode_Label";

// Combo calc breakdown text for the step-mode label. Filled by
// RefreshComboLabelExtraInfo() in ComboEngine.mqh (included AFTER the
// label builder, so it communicates through this global instead of a
// forward declaration - MQL4 treats bare prototypes as #imports).
string g_comboLabelExtraInfo = "";
static string g_factorLabelName = "Biotak_Factor_Label";
#ifndef BUILD_LITE
static string g_th3FreqLabelName = "Biotak_TH3Freq_Label";
#endif

// Independent label expiry timestamps (tick count)
static uint g_stepModeLabelCreateTime = 0;
static uint g_factorLabelCreateTime = 0;
#ifndef BUILD_LITE
static uint g_th3FreqLabelCreateTime = 0;
#endif
static uint g_lockStatusLabelCreateTime = 0;
static uint g_resetCommentCreateTime = 0;  // For "[ RESET ]" comment auto-clear

// ChartRedraw Throttling
static uint g_lastChartRedrawTime = 0;
#define CHART_REDRAW_THROTTLE_MS 100
static uint g_lastDragRedrawTime = 0;
#define DRAG_REDRAW_THROTTLE_MS 50

// Suppression flag: prevents CHARTEVENT_OBJECT_DELETE cascade during programmatic deletions
static bool g_suppressDeleteEvents = false;
static uint g_suppressDeleteEventsUntilMs = 0;

#ifndef BUILD_LITE
// AB=CD drawing state now lives in TH3DrawingSession (TH3Controller.mqh)
static string g_activeABCDPattern = "";

// Frequency Optimizer Result (last auto-find result for info label)
FrequencyResult g_lastFreqResult;

// Frequency History Ring Buffer   last FREQ_HISTORY_SIZE patterns
FrequencyHistoryEntry g_freqHistory[FREQ_HISTORY_SIZE];
int g_freqHistoryCount = 0;   // Total entries added (for < FREQ_HISTORY_SIZE check)
int g_freqHistoryHead  = 0;   // Next write position (wraps around)
#endif

// TH Storage
struct TimeframeTH {
    string timeframeName;
    double thValue;
};
TimeframeTH g_storedTHs[];

// Label Positioning
struct LabelPosition {
    string name;
    int xPos;
    int yPos;
};
LabelPosition g_labelPositions[];

//+------------------------------------------------------------------+
//| Hidden State Cache (TTL-based, matching MT5)                     |
//+------------------------------------------------------------------+
bool g_isHiddenCached = false;
uint g_isHiddenCacheTime = 0;

void RefreshIsHiddenCache() {
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    if(!GlobalVariableCheck(gvar_name))
        g_isHiddenCached = false;
    else
        g_isHiddenCached = (bool)GlobalVariableGet(gvar_name);
    g_isHiddenCacheTime = GetTickCount();
}

bool IsIndicatorHidden() {
    uint now = GetTickCount();
    if(now - g_isHiddenCacheTime > HIDDEN_CACHE_TTL_MS)
        RefreshIsHiddenCache();
    return g_isHiddenCached;
}

//+------------------------------------------------------------------+
//| Sanitize Symbol Name (cached, matching MT5)                      |
//+------------------------------------------------------------------+
string SanitizeSymbolName(const string symbol) {
    // PERF: Cache result since symbol never changes during indicator lifetime
    static string s_cachedInput = "";
    static string s_cachedResult = "";
    if(symbol == s_cachedInput && s_cachedResult != "") return s_cachedResult;
    s_cachedInput = symbol;
    string safe = symbol;
    // Remove all unsafe characters via loop
    static const string unsafeChars[] = {"_","|",":","/","\\", " ",".","*","?","<",">","\"","'","-"};
    int numChars = ArraySize(unsafeChars);
    for(int i = 0; i < numChars; i++)
        StringReplace(safe, unsafeChars[i], "");
    if(StringLen(safe) == 0) safe = "UNKNOWN";
    if(StringLen(safe) > 50) safe = StringSubstr(safe, 0, 50);
    s_cachedResult = safe;
    return safe;
}

// Effective SS/LS sequence origin. The chart menu override takes priority
// over the input and survives a redraw/timeframe change.
bool GetEffectiveSSLSLongFirst()
{
    if(g_sslsFirstOverride == 0) return false;
    if(g_sslsFirstOverride == 1) return true;
    return inpLSFirst;
}

//+------------------------------------------------------------------+
//| Cleanup All GlobalVariables (array-based, matching MT5)          |
//+------------------------------------------------------------------+
//| VIEW LOCK core — VIEWLOCK-OFF: retired, kept dormant (see note above).|
//| Anchor (first-visible-bar time + visible price min/max) is       |
//| captured on scroll/zoom, at enable time, and at the TF-switch    |
//| handoff in OnDeinit(REASON_CHARTCHANGE); OnInit re-arms it and   |
//| the first OnCalculate restores it. Pure Chart*/GV calls only —  |
//| callable from anything included after this file.                 |
//+------------------------------------------------------------------+
string ViewLockGV(const string key)
{
    return "Biotak_" + key + "_" + GetCachedChartIdStr();
}

void ViewLockPersistAnchor()
{
    GlobalVariableSet(ViewLockGV("ViewAnchorT"), (double)g_viewAnchorTime);
    GlobalVariableSet(ViewLockGV("ViewAnchorMin"), g_viewAnchorMin);
    GlobalVariableSet(ViewLockGV("ViewAnchorMax"), g_viewAnchorMax);
}

void ViewLockCapture()
{
    int bars = Bars(_Symbol, (ENUM_TIMEFRAMES)Period());
    if(bars <= 0) return;
    int firstVisible = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
    if(firstVisible < 0 || firstVisible >= bars) return;
    datetime t = iTime(_Symbol, (ENUM_TIMEFRAMES)Period(), firstVisible);
    if(t <= 0) return;
    double mn = ChartGetDouble(0, CHART_PRICE_MIN);
    double mx = ChartGetDouble(0, CHART_PRICE_MAX);
    if(mx <= mn) return;
    g_viewAnchorTime = t;
    g_viewAnchorMin = mn;
    g_viewAnchorMax = mx;
    ViewLockPersistAnchor();
}

// Returns true when the pending restore is settled (applied or moot).
bool ViewLockRestore()
{
    if(g_viewAnchorTime <= 0 || g_viewAnchorMax <= g_viewAnchorMin) return true;
    if(Bars(_Symbol, 0) <= 5) return false;   // history not ready — retry next tick
    int sh = iBarShift(_Symbol, 0, g_viewAnchorTime, false);
    if(sh < 0) return false;                  // anchor not in history yet — retry
    ChartSetInteger(0, CHART_AUTOSCROLL, false);
    ResetLastError();
    bool ok = ChartSetInteger(0, CHART_FIRST_VISIBLE_BAR, sh);
    if(!ok || GetLastError() != 0)
    {
        // Fallback: relative navigate so the anchor bar lands at the left edge
        int cur = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
        ChartNavigate(0, CHART_CURRENT_POS, sh - cur);
    }
    ChartSetInteger(0, CHART_SCALEFIX, true);
    ChartSetDouble(0, CHART_FIXED_MAX, g_viewAnchorMax);
    ChartSetDouble(0, CHART_FIXED_MIN, g_viewAnchorMin);
    ViewAnchorLineEnsure();
    return true;
}

void ViewLockSetEnabled(const bool on)
{
    g_viewLockEnabled = on;
    GlobalVariableSet(ViewLockGV("ViewLock"), on ? 1.0 : 0.0);
    if(on)
    {
        ViewLockCapture();   // anchor = wherever the view is right now
        ViewAnchorLineEnsure();
    }
    else
    {
        ViewAnchorLineDelete();
        // Hand the chart back: auto-scroll + auto-scale like a plain chart
        ChartSetInteger(0, CHART_AUTOSCROLL, true);
        ChartSetInteger(0, CHART_SCALEFIX, false);
        g_viewRestorePending = false;
    }
}

// Anchor handle — visible only while locked with a valid anchor. Repositioned
// by ensure (enable/restore/init); moved by the user via drag (drag-end
// handler commits the line time as the new anchor); deleting the line turns
// the lock off (handled in OnChartEvent, not here).
void ViewAnchorLineEnsure()
{
    if(!g_viewLockEnabled || g_viewAnchorTime <= 0)
    {
        ObjectDelete(0, g_viewAnchorLineName);
        return;
    }
    if(ObjectFind(0, g_viewAnchorLineName) < 0)
    {
        if(!ObjectCreate(0, g_viewAnchorLineName, OBJ_VLINE, 0, g_viewAnchorTime, 0)) return;
    }
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_TIME, 0, (long)g_viewAnchorTime);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_COLOR, C'255,171,0');
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_ZORDER, 100);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_BACK, false);
    ObjectSetString(0, g_viewAnchorLineName, OBJPROP_TOOLTIP,
                    "View anchor — drag to move the locked view · Del turns View Lock off");
}

void ViewAnchorLineDelete()
{
    ObjectDelete(0, g_viewAnchorLineName);
}

//+------------------------------------------------------------------+
void CleanupAllGlobalVariables() {
    string chartIdStr = GetCachedChartIdStr();
    string rawSymbolName = GetCachedSymbol();
    string sanitizedSymbolName = SanitizeSymbolName(rawSymbolName);
    string gvars[];
    ArrayResize(gvars, 24);
    gvars[0]  = "Biotak_isHidden_" + chartIdStr;
    gvars[1]  = "Biotak_CustomPrice_" + rawSymbolName;
    gvars[2]  = "Biotak_LockTF_" + chartIdStr;
    gvars[3]  = "Biotak_LockTFPeriod_" + chartIdStr;
    gvars[4]  = "Biotak_TriggerLevels_" + chartIdStr;
    gvars[5]  = "Biotak_CustomPriceOverride_" + rawSymbolName;
    gvars[6]  = "Biotak_StepMode_" + chartIdStr;
    gvars[7]  = "Biotak_Factor_" + chartIdStr;
    gvars[8]  = "Biotak_TH3Freq_" + chartIdStr;
    gvars[9]  = "Biotak_TH3FreqIdx_" + chartIdStr;
    gvars[10] = "Biotak_LinesVisible_" + chartIdStr;
    gvars[11] = "Biotak_ATRLabels_" + chartIdStr;
    gvars[12] = "Biotak_THLabels_" + chartIdStr;
    gvars[13] = "Biotak_LastTFSwitch_" + chartIdStr;
    gvars[14] = "Biotak_BaseInit_" + chartIdStr;
    gvars[15] = "Biotak_ATRWarmup_" + chartIdStr;
    gvars[16] = "Biotak_TH3_NeedsUpdate_" + chartIdStr;
    gvars[17] = "Biotak_SSLSFirst_" + chartIdStr;
    gvars[18] = "Biotak_CustomPrice_" + sanitizedSymbolName;
    gvars[19] = "Biotak_CustomPriceOverride_" + sanitizedSymbolName;
    gvars[20] = "Biotak_ViewLock_" + chartIdStr;
    gvars[21] = "Biotak_ViewAnchorT_" + chartIdStr;
    gvars[22] = "Biotak_ViewAnchorMin_" + chartIdStr;
    gvars[23] = "Biotak_ViewAnchorMax_" + chartIdStr;
    for(int i = 0; i < ArraySize(gvars); i++) {
        if(GlobalVariableCheck(gvars[i])) GlobalVariableDel(gvars[i]);
    }
}

//+------------------------------------------------------------------+
//| Restore Bool GlobalVar (epsilon-based, matching MT5)             |
//+------------------------------------------------------------------+
bool RestoreBoolGlobalVar(const string gvarName, bool defaultVal) {
    if(GlobalVariableCheck(gvarName)) {
        double gvarValue = GlobalVariableGet(gvarName);
        bool isZero = MathAbs(gvarValue - 0.0) < EPSILON_GENERAL;
        bool isOne  = MathAbs(gvarValue - 1.0) < EPSILON_GENERAL;
        if(isZero || isOne) {
            return isOne;
        } else {
            DEBUG_PRINTF2("OnInit: Corrupted state for ", gvarName, ", resetting");
            GlobalVariableSet(gvarName, defaultVal ? 1.0 : 0.0);
            return defaultVal;
        }
    }
    return defaultVal;
}

#endif // GLOBAL_VARIABLES_MQH
