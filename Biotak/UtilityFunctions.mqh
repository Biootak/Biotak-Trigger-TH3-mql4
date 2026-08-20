  //+------------------------------------------------------------------+
//|                                            UtilityFunctions.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                                      General Utility Functions   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

// CRITICAL: Include guard to prevent duplicate symbols
#ifndef UTILITY_FUNCTIONS_MQH
#define UTILITY_FUNCTIONS_MQH

// Include ZoneFactory for centralized zone creation
#include "ZoneFactory.mqh"

//+------------------------------------------------------------------+
//| Get Symbol Point (Cached)                                        |
//+------------------------------------------------------------------+
double GetSymbolPoint() {
    static double point = 0;
    if(point == 0) {
        // Use MODE_POINT which is the standard tick size for the symbol
        // This is equivalent to Point() built-in function
        point = MarketInfo(Symbol(), MODE_POINT);
        
        // For most forex pairs, MODE_POINT and MODE_TICKSIZE are the same
        // But to be absolutely sure, we use MODE_POINT which matches Java's tickSize
        if(point == 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("GetSymbolPoint: Failed to get point value for symbol ", Symbol());
            #endif
            return 0;
        }
    }
    return point;
}

double GetArrayMax(const double &array[]) {
    int size=ArraySize(array);
    if(size<=0) return EMPTY_VALUE;
    double maxValue=array[0];
    for(int i=1; i<size; i++) if(array[i]>maxValue) maxValue=array[i];
    return maxValue;
}

double GetArrayMin(const double &array[]) {
    int size=ArraySize(array);
    if(size<=0) return EMPTY_VALUE;
    double minValue=array[0];
    for(int i=1; i<size; i++) if(array[i]<minValue) minValue=array[i];
    return minValue;
}

void CheckArraySizes() {
    // OPTIMIZATION: Use smarter initial sizing based on actual needs
    // Cache arrays: size based on number of fractal timeframes + buffer
    int optimalCacheSize = ArraySize(FRACTAL_TIMEFRAMES) + ArraySize(STANDARD_TIMEFRAMES) + 5;
    
    // g_thCache removed - matching MT5

    // Stored THs: size based on actual timeframe count
    if(ArraySize(g_storedTHs) <= 0) {
        ArrayResize(g_storedTHs, optimalCacheSize);
    }

    // Label positions: size based on actual timeframe count
    if(ArraySize(g_labelPositions) <= 0) {
        ArrayResize(g_labelPositions, optimalCacheSize);
    }
}

//+------------------------------------------------------------------+
//| Calculate pips distance between two prices                       |
//| Note: Uses g_currentPrice which is Close of last completed bar  |
//| OPTIMIZED: Uses cached PipSize value via GetCachedPipSize()     |
//+------------------------------------------------------------------+
double CalculatePipsDistance(const double price1, const double price2) {
    double pipSize = GetCachedPipSize();
    if(IsZero(pipSize, EPSILON_PRICE)) return 0.0;
    return NormalizeDouble(MathAbs(price1 - price2) / pipSize, 1);
}

//+------------------------------------------------------------------+
//| Format tooltip with distance in pips                            |
//+------------------------------------------------------------------+
string FormatTooltipWithDistance(const string baseTooltip, const double priceLevel) {
    double pips = CalculatePipsDistance(priceLevel, g_currentPrice);
    return baseTooltip + ", Distance: +/- " + DoubleToString(pips, 1) + " pips";
}

// PERF: Overload accepting pre-computed pips to avoid redundant CalculatePipsDistance
string FormatTooltipWithDistanceFast(const string baseTooltip, const double precomputedPips) {
    return baseTooltip + ", Distance: +/- " + DoubleToString(precomputedPips, 1) + " pips";
}

//+------------------------------------------------------------------+
//| Get midpoint price based on start point type                    |
//+------------------------------------------------------------------+
double GetMidpointPrice(ENUM_TH_START_POINT_TYPE startPointType) {
    switch(startPointType) {
        case TH_START_POINT_HISTORICAL_HIGH:
            return g_highestHigh;
        case TH_START_POINT_HISTORICAL_LOW:
            return g_lowestLow;
        case TH_START_POINT_CUSTOM_PRICE:
        {
            double customPrice = (g_customTHStartPrice > 0.0) ? g_customTHStartPrice : inpCustomTHStartPrice;
            return (customPrice > 0.0) ? customPrice : (g_highestHigh + g_lowestLow) / 2.0;
        }
        case TH_START_POINT_PREVIOUS_CLOSE:
        {
            // Previous day close (D1 bar 1). Static daily cache so the
            // per-second label refresh stays cheap. (GetPriceForPreviousDay
            // lives in a later include, so this uses the built-in iClose.)
            static datetime s_prevCloseUpdate = 0;
            static double   s_prevClose = 0;
            datetime now = TimeCurrent();
            if(s_prevCloseUpdate == 0 || now - s_prevCloseUpdate >= 86400 || s_prevClose <= 0) {
                s_prevClose = iClose(Symbol(), PERIOD_D1, 1);
                s_prevCloseUpdate = now;
            }
            return (s_prevClose > 0 && s_prevClose != EMPTY_VALUE) ? s_prevClose : Bid;
        }
        case TH_START_POINT_MIDPOINT:
        default:
            return (g_highestHigh + g_lowestLow) / 2.0;
    }
}

//+------------------------------------------------------------------+
//| Get current step calculation mode (respects keyboard override)  |
//| Supports modes 0-3: TH, SS/LS, Combo, Factor                    |
//+------------------------------------------------------------------+
ENUM_STEP_CALCULATION_MODE GetCurrentStepMode() {
    // If user has overridden via keyboard, use that
    // Range 0-3 includes FACTOR_STEP (mode 3)
    if(g_stepModeOverride >= 0 && g_stepModeOverride <= 3) {
        return (ENUM_STEP_CALCULATION_MODE)g_stepModeOverride;
    }
    // Otherwise use input parameter
    return inpStepCalculationMode;
}

//+------------------------------------------------------------------+
//| Get step mode display name for UI                               |
//+------------------------------------------------------------------+
string GetStepModeName(ENUM_STEP_CALCULATION_MODE mode) {
    switch(mode) {
        case TH_STEP:           return "S";      // Structure step (was TH - renamed to avoid confusion with TH/ATR basis)
        case SS_LS_STEP:        return "SS/LS";
        case COMBO_STEP:        return "Combo";
        case FACTOR_STEP:       return "F";      // Factor step mode
        default:                return "Unknown";
    }
}

// (Removed: legacy GetComboPresetName / GetSharedComponentValue / GetSharedComponentName -
//  dead code referencing the old combo component system. Combo names/values now live in
//  ComboEngine.mqh; preset display is handled by EnumToString.)

//+------------------------------------------------------------------+
//| Clear all temporary mode labels (call before showing new one)   |
//|              label          (                         )         |
//+------------------------------------------------------------------+
void ClearAllModeLabels() {
    // Reset expiry timestamps so deleted labels are not re-cleared
    // or counted in stacking rows afterwards.
    if(ObjectFind(0, g_stepModeLabelName) >= 0) {
        ObjectDelete(0, g_stepModeLabelName);
    }
    g_stepModeLabelCreateTime = 0;
    if(ObjectFind(0, g_factorLabelName) >= 0) {
        ObjectDelete(0, g_factorLabelName);
    }
    g_factorLabelCreateTime = 0;
#ifndef BUILD_LITE
    if(ObjectFind(0, g_th3FreqLabelName) >= 0) {
        ObjectDelete(0, g_th3FreqLabelName);
    }
    g_th3FreqLabelCreateTime = 0;
#endif
    // Lock status is a persistent status while TF is locked - keep it visible.
    if(!g_timeframeLocked) {
        if(ObjectFind(0, g_lockStatusLabelName) >= 0) {
            ObjectDelete(0, g_lockStatusLabelName);
        }
        g_lockStatusLabelCreateTime = 0;
    }
}

//+------------------------------------------------------------------+
//| Get primary step price for current mode                          |
//+------------------------------------------------------------------+
double GetCurrentModePrimaryStepPrice(ENUM_STEP_CALCULATION_MODE mode)
{
    int digits = GetCachedDigits();
    double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    if(basePrice <= 0) return 0.0;

    double timeframePercentage = GetTimeframeTH();
    double thValue = CalculateTH(basePrice, digits, timeframePercentage);
    if(thValue <= 0) return 0.0;
    thValue = GetAdaptedStepSize(thValue);

    switch(mode)
    {
        case TH_STEP:
            return thValue;

        case FACTOR_STEP:
            // Centralized: handles DIRECT (step semantics) and CLASSIC (factor semantics)
            return GetFactorModePrimaryStepPrice(basePrice);

        case SS_LS_STEP:
        {
            double structureValue, patternValue, triggerValue;
            CalculateFractalValues(thValue, structureValue, patternValue, triggerValue);
            return structureValue * 1.5; // SS_MULTIPLIER = 1.5
        }

        case COMBO_STEP:
            return CalculateComboStepSize(basePrice);

        default:
            return thValue;
    }
}

//+------------------------------------------------------------------+
//| Get ATR Info string for status display                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Base price (B) info for the status label.                        |
//| B is ALWAYS the step-calculation basis: the reference base price  |
//| (g_dailyClosePriceForTH, synced from GetBasePriceForTH on every   |
//| redraw) that CalculateTH / CalculateComboStepSize use to compute  |
//| the step sizes. It is NOT the level-drawing anchor - that is a    |
//| separate value shown as A: when it differs (see below).           |
//| Never displays 0: falls back to the live bid.                     |
//+------------------------------------------------------------------+
string GetBasePriceStatusInfo() {
    double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    if(basePrice <= 0) basePrice = Bid;
    if(basePrice <= 0) basePrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    return StringFormat(" | B: %.5f", basePrice);
}

//+------------------------------------------------------------------+
//| Anchor (drawing basis) info for the status label.                |
//| Levels are drawn AROUND GetMidpointPrice(g_thStartPointType):    |
//|   Custom Price -> the custom price; Midpoint -> (H+L)/2;         |
//|   Hist High/Low -> g_highestHigh / g_lowestLow.                  |
//| This is a separate value from the step-calculation basis (B).    |
//| Shown only when it differs from B, so the user can see what the  |
//| levels anchor to without cluttering the label.                   |
//+------------------------------------------------------------------+
string GetAnchorPriceStatusInfo() {
    double basis = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    if(basis <= 0) return "";

    double anchor = GetMidpointPrice(g_thStartPointType);
    if(anchor <= 0 || anchor == EMPTY_VALUE) return "";

    double point = GetCachedPoint();
    if(point <= 0) return "";

    // Hide when the anchor equals the calculation basis (avoids noise)
    if(MathAbs(anchor - basis) <= point * 0.1) return "";

    return StringFormat(" | A: %.5f", anchor);
}

// The combo calc breakdown is filled by RefreshComboLabelExtraInfo() in
// ComboEngine.mqh (included later) - see g_comboLabelExtraInfo global.
//
// Combo mode appends a compact "how it was computed" breakdown, e.g.
// "avg(PatTH12.1p,TrigTH6.1p)" so the user can verify the math.
string BuildUnifiedModeLabelText()
{
    ENUM_STEP_CALCULATION_MODE currentMode = GetCurrentStepMode();
    string modeName = GetStepModeName(currentMode);
    double pipSize = GetCachedPipSize();
    double stepPrice = GetCurrentModePrimaryStepPrice(currentMode);

    if(pipSize <= 0 || stepPrice <= 0) return "[ " + modeName + " ]";

    string calcInfo = "";
    if(currentMode == COMBO_STEP && g_comboLabelExtraInfo != "")
        calcInfo = " | " + g_comboLabelExtraInfo;

    return StringFormat("[ %s | S: %.1f%s%s%s ]", 
        modeName, stepPrice / pipSize, calcInfo,
        GetBasePriceStatusInfo(), GetAnchorPriceStatusInfo());
}

//+------------------------------------------------------------------+
//| Set label text only when it actually changed (PERF: avoids      |
//| pointless ObjectSetString syscalls on every tick/refresh)       |
//+------------------------------------------------------------------+
void SetLabelTextIfChanged(const string name, const string text) {
    if(ObjectFind(0, name) < 0) return;
    string currentText = ObjectGetString(0, name, OBJPROP_TEXT);
    if(currentText != text) ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Update step mode label on chart (configurable duration)         |
//| Updates text in place when already visible (no recreate churn,  |
//| no expiry timestamp reset) so real-time refresh stays cheap.    |
//+------------------------------------------------------------------+
void UpdateStepModeLabel(bool clearFirst = true) {
    if(!inpShowModeChangeLabel) return;
    
    if(clearFirst) ClearAllModeLabels();
    if(IsIndicatorHidden()) return;
    
    string labelText = BuildUnifiedModeLabelText();
    
    if(ObjectFind(0, g_stepModeLabelName) < 0) {
        if(!ObjectCreate(0, g_stepModeLabelName, OBJ_LABEL, 0, 0, 0)) return;
        // Timestamp set ONLY on creation so auto-hide still fires on schedule.
        g_stepModeLabelCreateTime = GetTickCount();
        ApplyModeLabelStyle(g_stepModeLabelName, inpModeLabelColor);
    }
    SetLabelTextIfChanged(g_stepModeLabelName, labelText);
}

//+------------------------------------------------------------------+
//| Update calculation basis label on chart (configurable duration) |
//| Uses Label object matching step mode label style                |
//| Shows both basis and current step mode: "ATR | SS/LS"           |
//| Duration: inpModeLabelDuration (0=permanent, >0=seconds)        |
//+------------------------------------------------------------------+
void UpdateBasisModeLabel(ENUM_CALCULATION_BASIS basis) {
    /* ATR basis removed - matching MT5 */
}

//+------------------------------------------------------------------+
//| Build the factor label text (shared by show + real-time refresh)|
//|                                                                  |
//| DIRECT MODE:  step size first  -> "[ Step: 12.5 | F: 50.00 ]"   |
//| CLASSIC MODE: factor first     -> "[ F: 50.00 | Step: 12.5 pips ]" |
//+------------------------------------------------------------------+
string BuildFactorLabelText(const double factorValue, const double stepSize) {
    double pipSize = GetCachedPipSize();
    if(stepSize > 0 && pipSize > 0) {
        double stepPips = stepSize / pipSize;
        if(inpFactorDisplayMode == FACTOR_DISPLAY_DIRECT) {
            // DIRECT MODE: Show Step first, Factor second
            return "[ Step: " + DoubleToString(stepPips, 1) + " | F: " + DoubleToString(factorValue, 2) + " ]";
        }
        // CLASSIC MODE: Show Factor first, Step second
        return "[ F: " + DoubleToString(factorValue, 2) + " | Step: " + DoubleToString(stepPips, 1) + " pips ]";
    }
    // Fallback: show only factor value
    return "[ F: " + DoubleToString(factorValue, 2) + " ]";
}

//+------------------------------------------------------------------+
//| Update Factor value label on chart (configurable duration)      |
//| Updates text in place when already visible (no recreate churn,  |
//| no expiry timestamp reset) so real-time refresh stays cheap.    |
//+------------------------------------------------------------------+
void UpdateFactorLabel(double factorValue, double directStepSize = 0, bool clearFirst = true) {
    // Check if mode label display is enabled
    if(!inpShowModeChangeLabel) return;
    
    // Clear ALL temporary labels first (prevents overlap)
    if(clearFirst) ClearAllModeLabels();
    
    // CRITICAL FIX: Don't show label if indicator is hidden
    if(IsIndicatorHidden()) return; // Don't show mode labels when hidden
    
    // Calculate step size for display
    double stepSize = directStepSize;
    if(stepSize <= 0) {
        // CLASSIC MODE: Calculate step from factor
        if(g_highestHigh > 0 && g_lowestLow > 0 && g_highestHigh > g_lowestLow) {
            stepSize = CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
        }
    }
    
    string labelText = BuildFactorLabelText(factorValue, stepSize);
    
    // GOLD FIX: Check if object exists before creating
    if(ObjectFind(0, g_factorLabelName) < 0) {
        if(!ObjectCreate(0, g_factorLabelName, OBJ_LABEL, 0, 0, 0)) return;
        // Timestamp set ONLY on creation so auto-hide still fires on schedule.
        g_factorLabelCreateTime = GetTickCount();
        ApplyModeLabelStyle(g_factorLabelName, inpFactorLevelColor);
    }
    
    SetLabelTextIfChanged(g_factorLabelName, labelText);
}

#ifndef BUILD_LITE
//+------------------------------------------------------------------+
//| Build TH3 Frequency label text (shared by show + real-time      |
//| refresh). The FIBO object scan is throttled (max once per 5s or |
//| when the frequency changed) so the per-second refresh stays     |
//| lightweight.                                                    |
//+------------------------------------------------------------------+
string BuildTH3FrequencyLabelText(const double frequency) {
    static uint s_lastStepInfoMs = 0;
    static double s_lastStepInfoFreq = -1;
    static string s_cachedStepInfo = "";
    uint nowMs = GetTickCount();
    bool freqChanged = (frequency != s_lastStepInfoFreq);
    if(freqChanged || nowMs - s_lastStepInfoMs >= 5000) {
        s_lastStepInfoMs = nowMs;
        s_lastStepInfoFreq = frequency;
        s_cachedStepInfo = "";
        
        // Try to find an active TH3 structure to calculate step info
        int total = ObjectsTotal(0, -1, OBJ_FIBO);
        for(int i = 0; i < total; i++) {
            string name = ObjectName(0, i, -1, OBJ_FIBO);
            
            if(StringFind(name, "TH3_Structure_") == 0 && 
               StringFind(name, "_Text") < 0 && 
               StringFind(name, "_Target") < 0) {
                
                // Get structure range
                datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
                double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
                datetime t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
                double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
                
                // CRITICAL FIX: Validate ObjectGet results
                if(t1 <= 0 || t2 <= 0 || p1 <= 0 || p2 <= 0) {
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("   GetStructureRangeFromTH3: Invalid object data for ", name);
                    #endif
                    continue;
                }
                
                if(t1 > 0 && t2 > 0 && p1 > 0 && p2 > 0) {
                    double rangePips = CalculatePipsDistance(p1, p2);
                    
                    // Calculate step size and count
                    double stepPips = rangePips * (frequency / 100.0);
                    if(stepPips > 0) {
                        double stepCount = rangePips / stepPips;
                        int fullSteps = (int)MathFloor(stepCount);
                        double remainder = stepCount - fullSteps;
                        
                        s_cachedStepInfo = StringFormat(" | Step: %.1f pips | Steps: %d + %.2f", 
                            stepPips, fullSteps, remainder);
                        break; // Use first found structure
                    }
                }
            }
        }
    }
    return "[ TH3 Freq: " + DoubleToString(frequency, 3) + "%" + s_cachedStepInfo + " ]";
}

//+------------------------------------------------------------------+
//| Update TH3 Frequency Label (configurable duration)              |
//+------------------------------------------------------------------+
void UpdateTH3FrequencyLabel(double frequency, bool clearFirst = true) {
    // Only show TH3 info when the TH3 tool is actually enabled
    if(!inpEnableTH3Tool) return;
    // Check if mode label display is enabled
    if(!inpShowModeChangeLabel) return;
    
    // Clear ALL temporary labels first (prevents overlap)
    if(clearFirst) ClearAllModeLabels();
    
    // CRITICAL FIX: Don't show label if indicator is hidden
    // PERFORMANCE: Use cached ChartID string
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    bool isHidden = GlobalVariableCheck(gvar_name) && (bool)GlobalVariableGet(gvar_name);
    if(isHidden) return; // Don't show mode labels when hidden
    
    string labelText = BuildTH3FrequencyLabelText(frequency);
    
    // GOLD FIX: Check if object exists before creating
    if(ObjectFind(0, g_th3FreqLabelName) < 0) {
        if(!ObjectCreate(0, g_th3FreqLabelName, OBJ_LABEL, 0, 0, 0)) return;
        // Timestamp set ONLY on creation so auto-hide still fires on schedule.
        g_th3FreqLabelCreateTime = GetTickCount();
        ApplyModeLabelStyle(g_th3FreqLabelName, inpModeLabelColor);
    }
    
    SetLabelTextIfChanged(g_th3FreqLabelName, labelText);
}
#endif


//+------------------------------------------------------------------+
//| Show all status labels without changing modes                    |
//+------------------------------------------------------------------+
void ShowAllStatusLabels() {
    ClearAllModeLabels();
    
    // Show every info label, stacked (non-destructive updates)
    UpdateStepModeLabel(false);
    
    // Factor info only applies in Factor mode - don't show it in other
    // modes (the values would be irrelevant to what is actually drawn).
    if(GetCurrentStepMode() == FACTOR_STEP) {
        double factorVal = 0;
        double stepVal = 0;
        double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
        ComputeFactorModeValues(basePrice, factorVal, stepVal);
        UpdateFactorLabel(factorVal, stepVal, false);
    }
#ifndef BUILD_LITE
    // TH3 frequency info belongs to the TH3 tool - only show it when the
    // tool is enabled (UpdateTH3FrequencyLabel also gates internally).
    if(inpEnableTH3Tool) {
        double freq = (g_th3FreqOverride > 0) ? g_th3FreqOverride : inpTH3BaseStepPercent;
        UpdateTH3FrequencyLabel(freq, false);
    }
#endif
    UpdateLockStatusLabel();
}

//+------------------------------------------------------------------+
//| Real-time refresh of currently visible info labels               |
//| Called from OnTimer (1s cadence). Updates text in place ONLY     |
//| when it changed - never recreates objects, never resets expiry   |
//| timestamps, so auto-hide and CPU usage stay correct.             |
//+------------------------------------------------------------------+
void RefreshVisibleStatusLabels() {
    if(!inpShowModeChangeLabel) return;
    if(IsIndicatorHidden()) return;
    
    // Step-mode label (mode + current step in pips)
    if(ObjectFind(0, g_stepModeLabelName) >= 0) {
        SetLabelTextIfChanged(g_stepModeLabelName, BuildUnifiedModeLabelText());
    }
    
    // Factor label (F + Step) - only relevant while in Factor mode
    if(GetCurrentStepMode() == FACTOR_STEP) {
        if(ObjectFind(0, g_factorLabelName) >= 0) {
            double factorVal = 0;
            double stepVal = 0;
            double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
            ComputeFactorModeValues(basePrice, factorVal, stepVal);
            SetLabelTextIfChanged(g_factorLabelName, BuildFactorLabelText(factorVal, stepVal));
        }
    } else {
        // Not in Factor mode: remove any lingering factor label
        if(ObjectFind(0, g_factorLabelName) >= 0) {
            ObjectDelete(0, g_factorLabelName);
            g_factorLabelCreateTime = 0;
        }
    }
    
#ifndef BUILD_LITE
    // TH3 frequency label (frequency + step info) - only when tool enabled
    if(inpEnableTH3Tool) {
        if(ObjectFind(0, g_th3FreqLabelName) >= 0) {
            double freq = (g_th3FreqOverride > 0) ? g_th3FreqOverride : inpTH3BaseStepPercent;
            SetLabelTextIfChanged(g_th3FreqLabelName, BuildTH3FrequencyLabelText(freq));
        }
    } else {
        // Tool disabled: remove any lingering TH3 label
        if(ObjectFind(0, g_th3FreqLabelName) >= 0) {
            ObjectDelete(0, g_th3FreqLabelName);
            g_th3FreqLabelCreateTime = 0;
        }
    }
#endif
}

//+------------------------------------------------------------------+
//| Create Mid-Range Zone (Generic function for all modes)          |
//|                  (                         )                     |
//| Logic: Draw zone with specified height around midpoint          |
//| Compatible with CreateFactorMidZone logic                        |
//| @param zoneName - Unique name for zone object                   |
//| @param prevPrice - Previous level price                         |
//| @param currentPrice - Current level price                       |
//| @param zoneHeight - Height of zone ( from midpoint)             |
//| @param zoneColor - Color of zone                                |
//| @param transparency - Transparency (0-100)                      |
//+------------------------------------------------------------------+
//| Create Generic Mid Zone - GOLD VERSION v2                        |
//|       Zone             -            v2                           |
//|                                                                  |
//| ARCHITECTURE: Delegates to ZoneFactory with comprehensive        |
//| validation, error handling, and NO unnecessary deletion          |
//|                                                                  |
//| IMPROVEMENTS v2:                                                 |
//| - REMOVED unnecessary object deletion (let factory handle it)   |
//| - Factory will UPDATE existing objects (more efficient)         |
//| - Better error messages with context                            |
//| - Consistent error handling                                     |
//+------------------------------------------------------------------+
bool CreateGenericMidZone(const string zoneName, const double prevPrice, const double currentPrice,
                          const double zoneHeight, const color zoneColor, const int transparency)
{
    //                                                                
    // PHASE 1: QUICK VALIDATION (Fail Fast)
    //                                                                
    if(StringLen(zoneName) == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Empty zone name");
        #endif
        return false;
    }
    
    if(prevPrice <= 0 || currentPrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Invalid prices - Prev=", DoubleToString(prevPrice, Digits), 
              ", Current=", DoubleToString(currentPrice, Digits));
        #endif
        return false;
    }
    
    if(prevPrice == currentPrice) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   CreateGenericMidZone: Prices are equal - no zone needed");
        #endif
        return false;
    }
    
    if(zoneHeight <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Invalid zone height: ", DoubleToString(zoneHeight, Digits));
        #endif
        return false;
    }
    
    //                                                                
    // PHASE 2: CALCULATE ZONE BOUNDARIES (Optimized)
    //                                                                
    
    // Calculate midpoint between previous and current
    double midPoint = (prevPrice + currentPrice) / 2.0;
    
    // Calculate zone boundaries ( zoneHeight from midpoint)
    // OPTIMIZATION: Single NormalizeDouble call per value
    double upperPrice = NormalizeDouble(midPoint + zoneHeight, Digits);
    double lowerPrice = NormalizeDouble(midPoint - zoneHeight, Digits);
    
    // Validate zone boundaries
    if(upperPrice <= lowerPrice) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Invalid zone boundaries - Upper=", DoubleToString(upperPrice, Digits), 
              ", Lower=", DoubleToString(lowerPrice, Digits));
        #endif
        return false;
    }
    
    //                                                                
    // PHASE 3: DELEGATE TO ZONE FACTORY (Centralized Creation)
    // OPTIMIZATION: Let factory handle update vs create decision
    //                                                                
    
    SZoneCreationRequest request;
    request.name = zoneName;
    request.topPrice = upperPrice;
    request.bottomPrice = lowerPrice;
    request.zoneColor = zoneColor;
    request.transparency = transparency;
    request.filled = true;
    request.borderStyle = inpMidZoneBorderStyle;
    request.borderWidth = inpMidZoneBorderWidth;
    request.startTime = 0;  // Auto-calculate
    request.endTime = 0;    // Auto-calculate
    
    SZoneCreationResult result = CreateZone(request);
    
    if(!result.success) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateGenericMidZone: Factory failed for '", zoneName, "' - ", result.errorMessage, 
              " (Code: ", result.errorCode, ")");
        #endif
        return false;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  CreateGenericMidZone: Created/Updated '", zoneName, "' [", 
          DoubleToString(lowerPrice, Digits), " - ", DoubleToString(upperPrice, Digits), "]");
    #endif
    
    return true;
}

//+------------------------------------------------------------------+
//| Throttled ChartRedraw() to prevent excessive CPU usage           |
//| GOLD FIX: Prevents rapid ChartRedraw calls in OnChartEvent      |
//+------------------------------------------------------------------+
void ThrottledChartRedraw(bool forceRedraw = false) {
    uint nowMs = GetTickCount();
    if(forceRedraw) {
        ChartRedraw();
        g_lastChartRedrawTime = nowMs;
        return;
    }
    if(IsIndicatorHidden()) return;
    if(nowMs - g_lastChartRedrawTime > CHART_REDRAW_THROTTLE_MS) {
        ChartRedraw();
        g_lastChartRedrawTime = nowMs;
    }
}

//+------------------------------------------------------------------+
//| Clear a single temporary label by name and reset its timestamp  |
//+------------------------------------------------------------------+
void ClearSingleModeLabel(const string labelName, uint &createTime) {
    if(ObjectFind(0, labelName) >= 0)
        ObjectDelete(0, labelName);
    createTime = 0;
}

//+------------------------------------------------------------------+
//| Check and clear expired labels (called from OnTimer)            |
//| Returns true if any labels remain (timer should continue)       |
//+------------------------------------------------------------------+
bool CheckAndClearExpiredLabels() {
    uint now = GetTickCount();
    uint durationMs = (uint)inpModeLabelDuration * 1000;
    bool anyRemaining = false;
    bool anyCleared = false;

    if(durationMs > 0) {
        if(g_stepModeLabelCreateTime > 0) {
            if((now - g_stepModeLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_stepModeLabelName, g_stepModeLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
        if(g_factorLabelCreateTime > 0) {
            if((now - g_factorLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_factorLabelName, g_factorLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
#ifndef BUILD_LITE
        if(g_th3FreqLabelCreateTime > 0) {
            if((now - g_th3FreqLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_th3FreqLabelName, g_th3FreqLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
#endif
        if(g_lockStatusLabelCreateTime > 0) {
            // Lock status is a persistent status: stays visible while locked.
            if(g_timeframeLocked) {
                anyRemaining = true;
            } else if((now - g_lockStatusLabelCreateTime) >= durationMs) {
                ClearSingleModeLabel(g_lockStatusLabelName, g_lockStatusLabelCreateTime);
                anyCleared = true;
            } else {
                anyRemaining = true;
            }
        }
    } else {
        bool labelsExist = (g_stepModeLabelCreateTime > 0 || g_factorLabelCreateTime > 0 || g_lockStatusLabelCreateTime > 0);
#ifndef BUILD_LITE
        labelsExist = labelsExist || (g_th3FreqLabelCreateTime > 0);
#endif
        if(labelsExist)
            RepositionAllOverlayLabels();
        anyRemaining = false;
    }

    if(g_resetCommentCreateTime > 0) {
        if((now - g_resetCommentCreateTime) >= 2000) {
            Comment("");
            g_resetCommentCreateTime = 0;
            anyCleared = true;
        } else {
            anyRemaining = true;
        }
    }

    if(anyCleared)
        RepositionAllOverlayLabels();

    return anyRemaining;
}

//+------------------------------------------------------------------+
//| Get Y row offset for a specific label type (stacked vertically) |
//+------------------------------------------------------------------+
int GetModeLabelRowOffset(const string labelName) {
    int rowHeight = inpModeLabelFontSize + 12;
    if(labelName == g_stepModeLabelName)  return 0;
    if(labelName == g_factorLabelName) {
        int row = 0;
        if(g_stepModeLabelCreateTime > 0) row++;
        return row * rowHeight;
    }
#ifndef BUILD_LITE
    if(labelName == g_th3FreqLabelName) {
        int row = 0;
        if(g_stepModeLabelCreateTime > 0) row++;
        if(g_factorLabelCreateTime > 0) row++;
        return row * rowHeight;
    }
#endif
    if(labelName == g_lockStatusLabelName) {
        int row = 0;
        if(g_stepModeLabelCreateTime > 0) row++;
        if(g_factorLabelCreateTime > 0) row++;
#ifndef BUILD_LITE
        if(g_th3FreqLabelCreateTime > 0) row++;
#endif
        return row * rowHeight;
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Get total height of ALL active mode labels (for stacking below) |
//+------------------------------------------------------------------+
int GetModeLabelBlockHeight() {
    int activeCount = 0;
    if(g_stepModeLabelCreateTime > 0) activeCount++;
    if(g_factorLabelCreateTime > 0) activeCount++;
#ifndef BUILD_LITE
    if(g_th3FreqLabelCreateTime > 0) activeCount++;
#endif
    if(g_lockStatusLabelCreateTime > 0) activeCount++;
    int rowHeight = inpModeLabelFontSize + 12;
    return activeCount * rowHeight;
}

//+------------------------------------------------------------------+
//| Apply standard style to an overlay mode label                   |
//+------------------------------------------------------------------+
void ApplyModeLabelStyle(const string name, const color textColor, const int yOffsetExtra = 0) {
    ObjectSetInteger(0, name, OBJPROP_CORNER, inpModeLabelCorner);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, inpModeLabelXDistance);
    int rowOffset = GetModeLabelRowOffset(name);
    
    int finalY = inpModeLabelYDistance + yOffsetExtra + rowOffset;
    
    // Smart stacking: Avoid overlapping with ATR (top) or TH (bottom) labels
    if(inpModeLabelCorner == CORNER_LEFT_UPPER || inpModeLabelCorner == CORNER_RIGHT_UPPER) {
        // Offset for top-aligned corners (below ATR labels)
        finalY += g_modeLabelYOffset + 45; 
    } else {
        // Offset for bottom-aligned corners (above TH labels)
        finalY += g_currentLabelYOffsetBottom + inpTHLabelsMarginBottom + 15;
    }
    
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, finalY);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetString(0, name, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, inpModeLabelFontSize);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Unified repositioning for ALL overlay labels                     |
//| Call after g_modeLabelYOffset changes to keep layout consistent  |
//+------------------------------------------------------------------+
void RepositionAllOverlayLabels() {
    if(ObjectFind(0, g_stepModeLabelName) >= 0)
        ApplyModeLabelStyle(g_stepModeLabelName, (color)ObjectGetInteger(0, g_stepModeLabelName, OBJPROP_COLOR));
    if(ObjectFind(0, g_factorLabelName) >= 0)
        ApplyModeLabelStyle(g_factorLabelName, (color)ObjectGetInteger(0, g_factorLabelName, OBJPROP_COLOR));
#ifndef BUILD_LITE
    if(ObjectFind(0, g_th3FreqLabelName) >= 0)
        ApplyModeLabelStyle(g_th3FreqLabelName, (color)ObjectGetInteger(0, g_th3FreqLabelName, OBJPROP_COLOR));
#endif
    if(ObjectFind(0, g_lockStatusLabelName) >= 0)
        ApplyModeLabelStyle(g_lockStatusLabelName, (color)ObjectGetInteger(0, g_lockStatusLabelName, OBJPROP_COLOR));

    UpdateLockStatusLabel(false);
#ifndef BUILD_LITE
    RepositionABCDInfoLabels();
#endif
}

#endif // UTILITY_FUNCTIONS_MQH

