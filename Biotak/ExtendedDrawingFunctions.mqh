  //+------------------------------------------------------------------+
//|                                   ExtendedDrawingFunctions.mqh   |
//+------------------------------------------------------------------+
#ifndef EXTENDED_DRAWING_FUNCTIONS_MQH
#define EXTENDED_DRAWING_FUNCTIONS_MQH

#property copyright "  Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link "@biotak"
#property strict

#include "Logger.mqh"
#include "TimeframeFunctions.mqh"
#include "MathConstants.mqh"
#include "UnifiedZoneSystem.mqh"
#include "ZoneTrackingHelpers.mqh"
#include "DrawingPipeline.mqh" // Drawing & Zone rendering pipeline

// Note: CalculateFactorStepSize has been moved to THCalculations.mqh

//+------------------------------------------------------------------+
//| Helper functions (ported from MT5)                                |
//+------------------------------------------------------------------+
void CleanupSurplusObjects(const string prefix, int startIdx, int maxConsecutiveMiss = 6, const string suffix = "") {
    if(g_customPriceLineDragging && StringFind(prefix, "_Zone_") >= 0) return;
    int misses = 0;
    bool zoneFamily = (suffix == "" && StringFind(prefix, "_Zone_") >= 0);
    for(int idx = startIdx; misses < maxConsecutiveMiss; idx++) {
        string name = prefix + IntegerToString(idx) + suffix;
        bool deleted = zoneFamily ? DeleteManagedZoneObjects(name, true)
                                  : DeleteIndicatorObjectManaged(name, true);
        if(deleted) {
            misses = 0;
        } else {
            misses++;
        }
    }
}

bool CreateOrUpdateHLine(const string name, double price, 
                          color clr, ENUM_LINE_STYLE style, int width,
                          const string tooltip,
                          const bool visibilityAsLine = true) {
    SObjectCacheEntry cachedEntry;
    bool hasCached = CacheGetObject(name, cachedEntry);
    bool objectExists = false;
    if(hasCached && cachedEntry.exists) {
        objectExists = (ObjectFind(0, name) >= 0);
        if(!objectExists) {
            CacheRemoveObject(name);
            hasCached = false;
        }
    } else {
        objectExists = (ObjectFind(0, name) >= 0);
    }
    
    if(!objectExists) {
        if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) {
            return false;
        }
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
        ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
        CacheAddObject(name, price, clr, style, width);
        ApplyVisibilityState(name, visibilityAsLine);
        return true;
    } else {
        double normPrice = NormalizeDouble(price, Digits);
        if(!hasCached || MathAbs(hasCached ? cachedEntry.lastPrice - normPrice : 1.0) > GetCachedPoint() * 0.1) {
            ObjectSetDouble(0, name, OBJPROP_PRICE, normPrice);
        }
        if(!hasCached || cachedEntry.lastColor != clr) {
            ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        }
        if(!hasCached || cachedEntry.lastStyle != (int)style) {
            ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        }
        if(!hasCached || cachedEntry.lastWidth != width) {
            ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        }
        CacheUpdateObject(name, normPrice, clr, style, width);
        ApplyVisibilityStateIfUnchangedSkip(name, visibilityAsLine);
        return false;
    }
}

void GetViewportBounds(double &vpTop, double &vpBottom) {
    static double s_vpTop = 0;
    static double s_vpBottom = 0;
    static double s_lastChartMax = 0;
    static double s_lastChartMin = 0;

    double vpChartMax = ChartGetDouble(0, CHART_PRICE_MAX);
    double vpChartMin = ChartGetDouble(0, CHART_PRICE_MIN);
    double point = GetCachedPoint();

    if(vpChartMax > 0 && vpChartMin > 0 && vpChartMax > vpChartMin) {
        if(s_vpTop > 0 &&
           MathAbs(vpChartMax - s_lastChartMax) <= point &&
           MathAbs(vpChartMin - s_lastChartMin) <= point) {
            vpTop = s_vpTop;
            vpBottom = s_vpBottom;
            return;
        }

        double vpRange = (vpChartMax - vpChartMin) * 0.5;
        vpTop = vpChartMax + vpRange;
        vpBottom = vpChartMin - vpRange;
        s_vpTop = vpTop;
        s_vpBottom = vpBottom;
        s_lastChartMax = vpChartMax;
        s_lastChartMin = vpChartMin;
        return;
    }

    if(s_vpTop > 0 && s_vpBottom > 0 && s_vpTop > s_vpBottom) {
        vpTop = s_vpTop;
        vpBottom = s_vpBottom;
        return;
    }

    double anchor = g_currentPrice;
    if(anchor <= 0 && g_dailyClosePriceForTH > 0 && g_dailyClosePriceForTH != EMPTY_VALUE)
        anchor = g_dailyClosePriceForTH;
    if(anchor <= 0) anchor = Bid;
    if(anchor <= 0 && g_highestHigh > 0 && g_lowestLow > 0)
        anchor = (g_highestHigh + g_lowestLow) * 0.5;
    if(anchor <= 0) anchor = 1.0;

    double fallbackRange = 0.0;
    if(g_highestHigh > 0 && g_lowestLow > 0 && g_highestHigh > g_lowestLow)
        fallbackRange = g_highestHigh - g_lowestLow;
    if(fallbackRange <= point * 100.0)
        fallbackRange = MathMax(anchor * 0.05, point * 1000.0);

    vpTop = anchor + fallbackRange;
    vpBottom = MathMax(anchor - fallbackRange, point);
    s_vpTop = vpTop;
    s_vpBottom = vpBottom;
    s_lastChartMax = 0;
    s_lastChartMin = 0;
}

bool ValidateComboParam(bool isInvalid, const string paramName, const string paramValue, const string context = "PRESET MODE") {
    if(!isInvalid) return true;
    _LOG_GATE_E Print("[E][DRAW] CalculateComboStepSize: Invalid ", paramName, "=", paramValue);
    Alert("[WARN] ", context, " ERROR\n\nInvalid ", paramName, " configuration!\nPreset: ", EnumToString(inpComboPreset));
    return false;
}

//+------------------------------------------------------------------+
//| Create Factor Mid Zone - REFACTORED to use Unified System        |
//|       Zone Factor - Refactor        Unified System               |
//|                                                                  |
//| ARCHITECTURE: Now uses UnifiedZoneSystem for consistency         |
//|       :         UnifiedZoneSystem                               |
//| FIXED: Respects Hide state when creating zones                  |
//|                                                                  |
//| @param zoneName Unique name for the zone object                 |
//| @param upperPrice Top boundary of the zone                      |
//| @param lowerPrice Bottom boundary of the zone                   |
//| @param zoneColor Color of the zone                              |
//| @param zoneStyle Style (Lines/Filled/Empty/Hidden)              |
//| @param transparency Transparency (0-100, 0=opaque, 100=invisible)|
//| @return true if zone created successfully, false otherwise      |
//+------------------------------------------------------------------+
bool CreateFactorMidZone(const string zoneName, 
                         const double upperPrice,
                         const double lowerPrice,
                         const color zoneColor,
                         const ENUM_ZONE_STYLE zoneStyle,
                         const int transparency)
{
    //                                                                
    // PHASE 1: HANDLE SPECIAL STYLES
    //                                                                
    
    // STYLE: HIDDEN - Delete and return
    if(zoneStyle == FACTOR_ZONE_HIDDEN) {
        DeleteManagedZoneObjects(zoneName, true);
        return true;
    }
    
    //                                                                
    // PHASE 2: USE UNIFIED SYSTEM FOR BOX STYLES
    //                                                                
    
    // For FILLED and EMPTY styles, use Unified System
    SUnifiedZoneConfig config;
    config.enabled = true;
    config.transparency = transparency;
    config.heightPercent = 1.0; // Factor zones use full height (not percentage)
    config.separateStructureTrigger = false;
    config.defaultColor = zoneColor;
    config.borderStyle = inpMidZoneBorderStyle;
    config.borderWidth = inpMidZoneBorderWidth;
    
    // Calculate midpoint (for unified system)
    double midPoint = (upperPrice + lowerPrice) / 2.0;
    double halfHeight = (upperPrice - lowerPrice) / 2.0;
    
    // Create zone using unified system
    SZoneCreationRequest request;
    request.name = zoneName;
    request.topPrice = upperPrice;
    request.bottomPrice = lowerPrice;
    request.zoneColor = zoneColor;
    request.transparency = transparency;
    request.filled = (zoneStyle == FACTOR_ZONE_BOX_FILLED);
    request.borderStyle = config.borderStyle;
    request.borderWidth = config.borderWidth;
    request.startTime = 0;  // Auto-calculate
    request.endTime = 0;    // Auto-calculate
    
    SZoneCreationResult result = CreateZone(request);
    
    // PERF FIX: Use cached IsIndicatorHidden() — avoids GlobalVariableCheck/Get syscalls
    if(result.success && IsIndicatorHidden()) {
        ObjectSetInteger(0, zoneName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        // Empty-box border segments (BOX_EMPTY style)
        ObjectSetInteger(0, zoneName + "_B_Top", OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, zoneName + "_B_Bottom", OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, zoneName + "_B_Left", OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    }
    
    return result.success;
}

//+------------------------------------------------------------------+
//| Create/update a zone boundary SEGMENT (bounded like the box, not |
//| a full-width HLINE) so LINES style matches the box edges exactly.|
//| Uses the zone cache for change detection.                        |
//+------------------------------------------------------------------+
bool CreateOrUpdateZoneBoundary(const string name, const double price,
                                 const datetime startTime, const datetime endTime,
                                 const color clr, const int style, const int width,
                                 const string tooltip)
{
    SObjectCacheEntry cachedEntry;
    bool hasCached = CacheGetObject(name, cachedEntry);
    bool objectExists = false;
    if(hasCached && cachedEntry.exists) {
        objectExists = (ObjectFind(0, name) >= 0);
        if(!objectExists) {
            CacheRemoveObject(name);
            hasCached = false;
        }
    } else {
        objectExists = (ObjectFind(0, name) >= 0);
    }
    
    // Migrate old full-width HLINE leftovers to bounded segments
    if(objectExists) {
        int objType = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
        if(objType != OBJ_TREND) {
            ObjectDelete(0, name);
            CacheRemoveObject(name);
            objectExists = false;
            hasCached = false;
        }
    }
    
    double normPrice = NormalizeDouble(price, Digits);
    if(!objectExists) {
        if(!ObjectCreate(0, name, OBJ_TREND, 0, startTime, normPrice, endTime, normPrice)) {
            return false;
        }
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
        CacheUpdateZone(name, normPrice, normPrice, startTime, endTime, clr, true, style, width);
        // FIX: Zone boundary lines follow the L key (zone visibility)
        ApplyVisibilityState(name, true);
        return true;
    }
    
    bool geometryChanged = (!hasCached || cachedEntry.lastPrice != normPrice ||
                            cachedEntry.lastTime1 != startTime || cachedEntry.lastTime2 != endTime);
    if(geometryChanged) {
        ObjectMove(0, name, 0, startTime, normPrice);
        ObjectMove(0, name, 1, endTime, normPrice);
    }
    bool visualChanged = (!hasCached || cachedEntry.lastColor != clr ||
                          cachedEntry.lastStyle != style || cachedEntry.lastWidth != width);
    if(visualChanged) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    }
    CacheUpdateZone(name, normPrice, normPrice, startTime, endTime, clr, true, style, width);
    // FIX: Zone boundary lines follow the L key (zone visibility)
    ApplyVisibilityStateIfUnchangedSkip(name, true);
    return false;
}

//+------------------------------------------------------------------+
//| Create Factor Mid Zone - LINES STYLE                             |
//| Boundary lines match the box exactly: same time span, same       |
//| blended color, configurable border style/width.                  |
//+------------------------------------------------------------------+
bool CreateFactorMidZone_LinesStyle(const string zoneName,
                                    const double upperPrice,
                                    const double lowerPrice,
                                    const color zoneColor,
                                    const int transparency)
{
    // Validate inputs
    if(StringLen(zoneName) == 0) return false;
    if(upperPrice <= 0 || lowerPrice <= 0) return false;
    if(upperPrice <= lowerPrice) return false;
    
    string lineTop = zoneName + "_Top";
    string lineBottom = zoneName + "_Bottom";

    DeleteIndicatorObjectManaged(zoneName);

    // Same time span as the box (matches CreateZone geometry)
    int safeBars = Bars;
    datetime currentTime = (safeBars > 0) ? Time[0] : TimeCurrent();
    if(currentTime <= 0) currentTime = TimeCurrent();
    datetime startTime = (safeBars > 0) ? Time[safeBars - 1] : currentTime;
    if(startTime <= 0) startTime = currentTime;
    // PERF FIX: Use cached PeriodSeconds — same value for entire timeframe session
    datetime endTime = currentTime + GetCachedPeriodSecondsGlobal() * ZONE_EXTENSION_PERIODS;
    
    // Blend color with background (same visual as the box)
    color lineColor = GetZoneRenderColor(zoneColor, transparency);

    CreateOrUpdateZoneBoundary(lineTop, upperPrice, startTime, endTime,
                               lineColor, inpMidZoneBorderStyle, inpMidZoneBorderWidth,
                               zoneName + " top");
    CreateOrUpdateZoneBoundary(lineBottom, lowerPrice, startTime, endTime,
                               lineColor, inpMidZoneBorderStyle, inpMidZoneBorderWidth,
                               zoneName + " bottom");

    return (ObjectFind(0, lineTop) >= 0 && ObjectFind(0, lineBottom) >= 0);
}



//+------------------------------------------------------------------+
//| Get default Factor value from Control step size                  |
//|                                      Control                      |
//| Simple Formula: Step = Range / Factor                            |
//| We want: Step = Control = (SS + LS) / 2 = TH * 1.75              |
//| So: TH * 1.75 = Range / Factor                                   |
//| Therefore: Factor = Range / (TH * 1.75)                          |
//|                                                                  |
//| NOW SUPPORTS MULTIPLE BASIS TYPES:                               |
//| - Control, SS, LS, TH, Trigger, Pattern, Structure, Combo       |
//+------------------------------------------------------------------+
double GetDefaultFactorValue(const double basePrice) {
    // Validate input
    if(basePrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Invalid base price (", basePrice, "), using fallback");
        #endif
        return 50.0;  // Fallback
    }
    
    // Validate historical range
    if(g_highestHigh <= 0 || g_lowestLow <= 0 || g_highestHigh <= g_lowestLow) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Invalid historical range, using fallback");
        #endif
        return 50.0;  // Fallback
    }
    
    // Calculate range
    double range = g_highestHigh - g_lowestLow;
    if(range <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Invalid range (", range, "), using fallback");
        #endif
        return 50.0;
    }
    
    // Get step size based on selected basis
    double stepSize = GetStepSizeForFactorBasis(basePrice, inpFactorAutoBasis);
    if(stepSize <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Invalid step size, using fallback");
        #endif
        return 50.0;
    }
    
    // CRITICAL: Check for potential division overflow BEFORE calculation
    // GOLD REVERT: Re-added * 2.0 as requested to maintain Factor/Step relationship
    double denominator = stepSize * 2.0;
    if(denominator <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Invalid denominator, using fallback");
        #endif
        return 50.0;
    }
    
    // Additional safety: Check if division will produce reasonable result
    double minDenominator = range / 10000.0;
    if(denominator < minDenominator) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Step size too small (", DoubleToString(stepSize, 8), 
              "), would produce factor > 10000, clamping to 1000");
        #endif
        return 1000.0;
    }
    
    // Calculate Factor: Factor = Range / StepSize
    double factor = range / denominator;
    
    // Range validation with intelligent clamping
    if(factor > 10000) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Factor too large (", DoubleToString(factor, 2), 
              "), clamping to 1000 for usability");
        #endif
        factor = 1000.0;
    } else if(factor < 0.01) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetDefaultFactorValue: Factor too small (", DoubleToString(factor, 4), 
              "), clamping to 1.0 for usability");
        #endif
        factor = 1.0;
    }
    
    // Return value with 2 decimal places, minimum 0.01, maximum 10000
    double result = NormalizeDouble(MathMax(0.01, MathMin(10000, factor)), 2);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("GetDefaultFactorValue: Basis=", EnumToString(inpFactorAutoBasis),
          ", basePrice=", DoubleToString(basePrice, Digits), 
          ", Range=", DoubleToString(range, Digits),
          ", StepSize=", DoubleToString(stepSize, Digits),
          ", Factor=", DoubleToString(result, 2));
    #endif
    
    return result;
}

//+------------------------------------------------------------------+
//| Get step size based on Factor Auto Basis selection               |
//|                                                                  |
//| GOLD VERSION: Complete validation and error handling             |
//+------------------------------------------------------------------+
double GetStepSizeForFactorBasis(const double basePrice, const ENUM_FACTOR_AUTO_BASIS basis) {
    // CRITICAL: Validate base price
    if(basePrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepSizeForFactorBasis: Invalid basePrice=", basePrice);
        #endif
        return 0;
    }
    
    double stepSize = 0;
    
    switch(basis) {
        case FACTOR_BASIS_CONTROL:
            // Control = (SS + LS) / 2 = TH   1.75
            stepSize = GetStepSizeForBasisType(basePrice, 1.75, PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_SS:
            // Short Step = TH   1.5
            stepSize = GetStepSizeForBasisType(basePrice, 1.5, PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_LS:
            // Long Step = TH   2.0
            stepSize = GetStepSizeForBasisType(basePrice, 2.0, PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_TH:
            // Pure TH = TH   1.0
            stepSize = GetStepSizeForBasisType(basePrice, 1.0, PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_TRIGGER:
            // Trigger TH (current timeframe) - same as TH
            stepSize = GetStepSizeForBasisType(basePrice, 1.0, PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_PATTERN:
            // Pattern TH (4x timeframe)
            stepSize = GetStepSizeForBasisType(basePrice, 1.0, GetPatternTimeframe());
            break;
            
        case FACTOR_BASIS_STRUCTURE:
            // Structure TH (16x timeframe)
            stepSize = GetStepSizeForBasisType(basePrice, 1.0, GetStructureTimeframe());
            break;
            
        case FACTOR_BASIS_COMBO:
            // Combo (average of 2 components, like Combo Mode)
            stepSize = CalculateComboStepSize(basePrice);
            break;
            
        default:
            #ifdef ENABLE_DEBUG_LOGS
            Print("   GetStepSizeForFactorBasis: Unknown basis=", basis, ", using Control");
            #endif
            // Fallback to Control
            stepSize = GetStepSizeForBasisType(basePrice, 1.75, PERIOD_CURRENT);
            break;
    }
    
    // CRITICAL: Validate result
    if(stepSize <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepSizeForFactorBasis: Failed to calculate step for basis=", 
              EnumToString(basis));
        #endif
        return 0;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  GetStepSizeForFactorBasis: Basis=", EnumToString(basis), 
          ", Step=", DoubleToString(stepSize, Digits));
    #endif
    
    return stepSize;
}

//+------------------------------------------------------------------+
//| Get step size for specific multiplier and timeframe              |
//|                                                                  |
//| FIXED: Comprehensive error handling and validation               |
//+------------------------------------------------------------------+
double GetStepSizeForBasisType(const double basePrice, const double multiplier, 
                                const ENUM_TIMEFRAMES timeframe) {
    // Standard path: TH% comes from the timeframe lookup.
    double thPercentage = GetTimeframeTHForPeriod(timeframe);
    return GetStepSizeForBasisTypeFromTH(basePrice, multiplier, thPercentage);
}

//+------------------------------------------------------------------+
//| Step size directly from a TH percentage (no timeframe lookup).  |
//| Used by the Combo engine for sub-minute fractal components that |
//| have no standard ENUM_TIMEFRAMES representation.                |
//+------------------------------------------------------------------+
double GetStepSizeForBasisTypeFromTH(const double basePrice, const double multiplier,
                                     const double thPercentage) {
    // CRITICAL: Validate inputs
    if(basePrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepSizeForBasisType: Invalid basePrice=", basePrice);
        #endif
        return 0;
    }
    
    if(multiplier <= 0 || multiplier > 10.0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepSizeForBasisType: Invalid multiplier=", multiplier);
        #endif
        return 0;
    }
    
    if(thPercentage <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepSizeForBasisType: Invalid TH%=", thPercentage);
        #endif
        return 0;
    }
    
    // Calculate TH in price units
    double thPriceUnits = (basePrice * thPercentage) / 100.0;
    if(thPriceUnits <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepSizeForBasisType: Invalid TH price units=", thPriceUnits);
        #endif
        return 0;
    }
    
    // Apply multiplier (1.0=TH, 1.333333=4/3, 1.5=SS, 1.75=Control, 2.0=LS)
    double stepSize = thPriceUnits * multiplier;
    
    // GOLD FIX: Comprehensive validation
    // 1. Check for zero or negative (should never happen, but safety first)
    if(stepSize <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepSizeForBasisType: Zero or negative stepSize=", stepSize);
        #endif
        return 0;
    }
    
    // 2. Check for unreasonably large step (> 50% of basePrice)
    // This would indicate a calculation error or extreme parameters
    if(stepSize > basePrice * 0.5) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetStepSizeForBasisType: Suspiciously large stepSize=", stepSize, 
              " (> 50% of basePrice=", basePrice, ")");
        Print("   TH%=", DoubleToString(thPercentage, 4), ", Mult=", multiplier);
        #endif
        // Don't return 0, just log warning - this might be valid for extreme cases
    }
    
    // 3. Check for unreasonably small step (< 0.0001% of basePrice)
    // This would indicate precision issues
    double minReasonableStep = basePrice * 0.000001;  // 0.0001%
    if(stepSize < minReasonableStep) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetStepSizeForBasisType: Suspiciously small stepSize=", stepSize, 
              " (< 0.0001% of basePrice=", basePrice, ")");
        #endif
        // Don't return 0, just log warning
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  GetStepSizeForBasisType: TF=", timeframe, ", Mult=", multiplier, 
          ", TH%=", DoubleToString(thPercentage, 4), ", Step=", DoubleToString(stepSize, Digits));
    #endif
    
    return stepSize;
}

//+------------------------------------------------------------------+
//| Calculate Triple Combo Step Size (3 components)                  |
//|                           (3         )                           |
//|                                                                  |
//| Used for Triple presets: Balanced, Conservative, Aggressive     |
//|                                                                  |
//| @param basePrice Base price for TH calculation (must be > 0)    |
//| @param tf1 First timeframe type                                 |
//| @param step1 First step type                                    |
//| @param tf2 Second timeframe type                                |
//| @param step2 Second step type                                   |
//| @param tf3 Third timeframe type                                 |
//| @param step3 Third step type                                    |
//| @param operation Operation to apply (Average, Min, Max only)   |
//| @return Calculated triple combo step size (> 0), or 0 on error |
//+------------------------------------------------------------------+
double CalculateComboStepSize(const double basePrice) {
    // DELEGATES to the pure ComboEngine (ComboEngine.mqh). The legacy
    // GetComboConfiguration() switch was replaced by the preset data
    // table in the engine - behavior is identical.
    return GetComboStepSize(basePrice);
}

// (Removed: legacy Smart Combo Calculator helpers - see ComboEngine.mqh)



//+------------------------------------------------------------------+
//| Helper function to check if Trigger Levels should be shown      |
//| Runtime toggle (hotkey T) can override input parameter          |
//+------------------------------------------------------------------+
bool IsTriggerLevelsEnabled() {
    return g_triggerLevelsEnabled;
}

//+------------------------------------------------------------------+
//| Get current timeframe as fractal string                          |
//|                                                                  |
//+------------------------------------------------------------------+
string GetCurrentFractalTimeframe() {
    int minutes = Period();
    
    // Map standard timeframes to fractal strings
    if(minutes == 1) return "M1";
    else if(minutes == 5) return "M4";  // Closest
    else if(minutes == 15) return "M16"; // Closest
    else if(minutes == 30) return "M16"; // Closest
    else if(minutes == 60) return "H1+M4";
    else if(minutes == 240) return "H4+M16";
    else if(minutes == 1440) return "D2+H20+M16"; // Closest
    else if(minutes == 10080) return "D11+H9+M4"; // Closest
    else if(minutes == 43200) return "D45+H12+M16"; // Closest
    else return "M1"; // Fallback
}

//+------------------------------------------------------------------+
//| Get TH percentage for specific timeframe period                  |
//|             TH                                                   |
//| FIXED: No recursion, proper error handling                       |
//+------------------------------------------------------------------+
double GetTimeframeTHForPeriod(const ENUM_TIMEFRAMES period) {
    // CRITICAL FIX: Handle PERIOD_CURRENT without recursion
    if(period == PERIOD_CURRENT || period == 0) {
        string currentFractal = GetCurrentFractalTimeframe();
        // Apply Fractal Jump shift if active
        string shiftedFractal = ApplyFractalShift(currentFractal);
        double th = CalculateTimeframeTH(shiftedFractal);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("GetTimeframeTHForPeriod: CURRENT (", Period(), "min) -> ", 
              shiftedFractal, " = ", DoubleToString(th, 4), "%");
        #endif
        
        return th;
    }
    
    // Convert period to fractal timeframe string
    string timeframeStr = "";
    
    // GOLD FIX: Handle all timeframes including Monthly
    // PeriodSeconds() may return 0 for some timeframes, so use direct mapping
    int minutes = 0;
    
    switch(period) {
        case PERIOD_M1:  minutes = 1; break;
        case PERIOD_M5:  minutes = 5; break;
        case PERIOD_M15: minutes = 15; break;
        case PERIOD_M30: minutes = 30; break;
        case PERIOD_H1:  minutes = 60; break;
        case PERIOD_H4:  minutes = 240; break;
        case PERIOD_D1:  minutes = 1440; break;
        case PERIOD_W1:  minutes = 10080; break;
        case PERIOD_MN1: minutes = 43200; break;
        default: {
            // Fallback: try PeriodSeconds
            int seconds = PeriodSeconds(period);
            if(seconds > 0) {
                minutes = seconds / 60;
            } else {
                #ifdef ENABLE_DEBUG_LOGS
                Print("   GetTimeframeTHForPeriod: Unknown period=", period, ", using D45+H12+M16");
                #endif
                return CalculateTimeframeTH(ApplyFractalShift("D45+H12+M16"));
            }
            break;
        }
    }
    
    // Map minutes to fractal timeframe string
    if(minutes == 1) timeframeStr = "M1";
    else if(minutes <= 5) timeframeStr = "M4";
    else if(minutes <= 15) timeframeStr = "M16";
    else if(minutes <= 30) timeframeStr = "M16";
    else if(minutes <= 60) timeframeStr = "H1+M4";
    else if(minutes <= 240) timeframeStr = "H4+M16";
    else if(minutes <= 1440) timeframeStr = "D2+H20+M16";
    else if(minutes <= 10080) timeframeStr = "D11+H9+M4";
    else timeframeStr = "D45+H12+M16";
    
    // Apply Fractal Jump shift if active
    string shiftedTF = ApplyFractalShift(timeframeStr);
    
    // Calculate TH for the timeframe
    double th = CalculateTimeframeTH(shiftedTF);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("GetTimeframeTHForPeriod: ", period, " (", minutes, "min) -> ", 
          shiftedTF, " = ", DoubleToString(th, 4), "%");
    #endif
    
    return th;
}

//+------------------------------------------------------------------+
//| Get Sub timeframe (1/4 current - faster than current)            |
//|                  Sub (1/4      -                )                |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetSubTimeframe() {
    int currentMinutes = Period();
    int subMinutes = currentMinutes / 4;
    
    // SAFETY: Minimum is M1
    if(subMinutes < 1) subMinutes = 1;
    
    // Map to closest standard timeframe
    ENUM_TIMEFRAMES result;
    if(subMinutes <= 1) result = PERIOD_M1;
    else if(subMinutes <= 5) result = PERIOD_M5;
    else if(subMinutes <= 15) result = PERIOD_M15;
    else if(subMinutes <= 30) result = PERIOD_M30;
    else if(subMinutes <= 60) result = PERIOD_H1;
    else if(subMinutes <= 360) result = PERIOD_H4;   // Fix: 360min (D1/4) -> H4
    else if(subMinutes <= 1440) result = PERIOD_D1;
    else if(subMinutes <= 4320) result = PERIOD_D1;  // Fix: 2520min (W1/4) -> D1
    else if(subMinutes <= 10080) result = PERIOD_W1;
    else if(subMinutes <= 20000) result = PERIOD_W1; // Fix: 10800min (MN1/4) -> W1
    else result = PERIOD_MN1;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("GetSubTimeframe: Current=", currentMinutes, "min, Sub=", 
          subMinutes, "min ( 4) -> ", result);
    #endif
    
    return result;
}

//+------------------------------------------------------------------+
//| Get timeframe based on type                                       |
//|                                                                   |
//| GOLD FIX: Added validation and error logging                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTimeframeByType(const ENUM_COMBO_TIMEFRAME_TYPE tfType) {
    // CRITICAL: Validate input
    if(tfType < COMBO_TF_SUB || tfType > COMBO_TF_STRUCTURE) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetTimeframeByType: Invalid tfType=", tfType, ", using current period");
        #endif
        return (ENUM_TIMEFRAMES)Period();  // GOLD FIX: Use Period() instead of PERIOD_CURRENT (0)
    }
    
    ENUM_TIMEFRAMES result;
    
    switch(tfType) {
        case COMBO_TF_SUB:
            // User Request: Sub = 2 Fractals Lower (Current / 16)
            {
                int currentMinutes = Period();
                int subMinutes = currentMinutes / 16;
                if(subMinutes < 1) subMinutes = 1;
                
                // Map to closest standard timeframe (Reusing GetSubTimeframe logic style)
                if(subMinutes <= 1) result = PERIOD_M1;
                else if(subMinutes <= 5) result = PERIOD_M5;
                else if(subMinutes <= 15) result = PERIOD_M15;
                else if(subMinutes <= 30) result = PERIOD_M30;
                else if(subMinutes <= 60) result = PERIOD_H1;
                else if(subMinutes <= 360) result = PERIOD_H4;
                else if(subMinutes <= 1440) result = PERIOD_D1;
                else if(subMinutes <= 10080) result = PERIOD_W1;
                else result = PERIOD_MN1;
            }
            break;

        case COMBO_TF_TRIGGER:
            // User Request: Trigger = 1 Fractal Lower (Current / 4)
            result = GetSubTimeframe();
            break;

        case COMBO_TF_PATTERN:
            // User Request: Pattern = Current Timeframe
            result = (ENUM_TIMEFRAMES)Period();
            break;

        case COMBO_TF_STRUCTURE:
            // User Request: Structure = 1 Fractal Higher (Current * 4)
            result = GetPatternTimeframe();
            break;

        default:
            #ifdef ENABLE_DEBUG_LOGS
            Print("   GetTimeframeByType: Unexpected tfType=", tfType, ", using current period");
            #endif
            result = (ENUM_TIMEFRAMES)Period();
            break;
    }
    
    // SAFETY: Validate result
    if(result <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetTimeframeByType: Invalid result=", result, " for tfType=", tfType);
        #endif
        return (ENUM_TIMEFRAMES)Period();  // GOLD FIX: Use Period() instead of PERIOD_CURRENT (0)
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Get step multiplier based on step type                           |
//|                                                                  |
//| GOLD FIX: Added validation and error logging                     |
//+------------------------------------------------------------------+
double GetStepMultiplier(const ENUM_COMBO_STEP_TYPE stepType) {
    // CRITICAL: Validate input
    if(stepType < COMBO_STEP_TH || stepType > COMBO_STEP_RATIO_4_3) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepMultiplier: Invalid stepType=", stepType, ", using 1.0 (TH)");
        #endif
        return 1.0;
    }
    
    double multiplier;
    
    switch(stepType) {
        case COMBO_STEP_TH:
            multiplier = 1.0;   // TH
            break;
        case COMBO_STEP_SS:
            multiplier = 1.5;   // SS
            break;
        case COMBO_STEP_LS:
            multiplier = 2.0;   // LS
            break;
        case COMBO_STEP_RATIO_4_3:
            multiplier = 4.0 / 3.0; // LS / SS ratio
            break;
        default:
            #ifdef ENABLE_DEBUG_LOGS
            Print("   GetStepMultiplier: Unexpected stepType=", stepType, ", using 1.0 (TH)");
            #endif
            multiplier = 1.0;
            break;
    }
    
    // SAFETY: Validate result (should always be valid, but double-check)
    if(multiplier <= 0 || multiplier > 10.0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetStepMultiplier: Invalid multiplier=", multiplier, " for stepType=", stepType);
        #endif
        return 1.0;
    }
    
    return multiplier;
}

//+------------------------------------------------------------------+
//| Apply operation on two values (GOLD VERSION)                     |
//|                           (          )                           |
//|                                                                  |
//| @param value1 First value (must be > 0)                         |
//| @param value2 Second value (must be > 0)                        |
//| @param operation Operation type to apply                        |
//| @param weight1 Weight for value1 (0.0-1.0, for WEIGHTED only)   |
//| @param weight2 Weight for value2 (0.0-1.0, for WEIGHTED only)   |
//| @return Result of operation (> 0), or 0 on error                |
//|                                                                  |
//| FIXES:                                                           |
//| - Normalized weighted operation (handles any weight sum)        |
//| - Comprehensive validation                                      |
//| - Better error messages                                         |
//+------------------------------------------------------------------+
double ApplyComboOperation(const double value1, const double value2, 
                           const ENUM_COMBO_OPERATION operation,
                           const double weight1 = 0.5, const double weight2 = 0.5) {
    //                                                                
    // CRITICAL INPUT VALIDATION
    //                                                                
    
    if(value1 <= 0 || value2 <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ApplyComboOperation: Invalid values - v1=", value1, ", v2=", value2);
        #endif
        return 0;
    }
    
    double result = 0;
    
    //                                                                
    // APPLY OPERATION
    //                                                                
    
    switch(operation) {
        case COMBO_OP_AVERAGE:
            // Average: (A + B) / 2
            result = (value1 + value2) / 2.0;
            break;
            
        case COMBO_OP_ADD:
            // Add: A + B
            result = value1 + value2;
            break;
            
        case COMBO_OP_SUBTRACT: {
            // Subtract: |A - B| (absolute value to avoid negative)
            result = MathAbs(value1 - value2);
            
            // GOLD FIX:                         (< 1% of average)                               
            //                                        
            double avgValue = (value1 + value2) / 2.0;
            double minThreshold = avgValue * 0.01;  //   1% of average (dynamic threshold)
            
            if(result < minThreshold) {
                result = avgValue;  //   Use average when difference is negligible
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ApplyComboOperation: Subtract result too small (", 
                      DoubleToString(result, Digits), " < ", DoubleToString(minThreshold, Digits), 
                      "), using average=", DoubleToString(avgValue, Digits));
                #endif
            }
            break;
        }
            
        case COMBO_OP_MULTIPLY: {
            // Multiply: A   B
            result = value1 * value2;
            
            // GOLD FIX: Check for overflow using dynamic threshold
            // If result is more than 100x larger than both inputs, it's suspicious
            double maxInput = MathMax(value1, value2);
            double overflowThreshold = maxInput * 100.0;
            
            if(result > overflowThreshold) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ApplyComboOperation: Multiply overflow detected");
                Print("   v1=", DoubleToString(value1, Digits), 
                      ", v2=", DoubleToString(value2, Digits), 
                      ", result=", DoubleToString(result, Digits), 
                      " > threshold=", DoubleToString(overflowThreshold, Digits));
                Print("   Clamping to max input=", DoubleToString(maxInput, Digits));
                #endif
                result = maxInput;
            }
            break;
        }
            
        case COMBO_OP_MIN:
            // Minimum: min(A, B)
            result = MathMin(value1, value2);
            break;
            
        case COMBO_OP_MAX:
            // Maximum: max(A, B)
            result = MathMax(value1, value2);
            break;
            
        case COMBO_OP_WEIGHTED: {
            // Weighted: (A W1 + B W2) / (W1+W2)
            // CRITICAL FIX: Normalize weights to handle any sum
            
            // Validate weights
            if(weight1 < 0 || weight2 < 0) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("  ApplyComboOperation: Negative weights - w1=", weight1, ", w2=", weight2);
                #endif
                // Fallback to average
                result = (value1 + value2) / 2.0;
                break;
            }
            
            // Calculate weight sum
            double weightSum = weight1 + weight2;
            
            // CRITICAL: Check for zero sum
            if(weightSum <= 0) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("  ApplyComboOperation: Zero weight sum - w1=", weight1, ", w2=", weight2);
                #endif
                // Fallback to average
                result = (value1 + value2) / 2.0;
                break;
            }
            
            // GOLD VERSION: Normalized weighted average
            // Works correctly regardless of weight sum
            result = (value1 * weight1 + value2 * weight2) / weightSum;
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("  ApplyComboOperation: Weighted - w1=", weight1, ", w2=", weight2, 
                  ", sum=", weightSum, ", normalized result=", result);
            #endif
            break;
        }
            
        default:
            #ifdef ENABLE_DEBUG_LOGS
            Print("  ApplyComboOperation: Unknown operation=", operation);
            #endif
            // Fallback to average
            result = (value1 + value2) / 2.0;
            break;
    }
    
    //                                                                
    // FINAL VALIDATION
    //                                                                
    
    if(result <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ApplyComboOperation: Invalid result=", result, 
              " for op=", EnumToString(operation));
        #endif
        return 0;
    }
    
    // GOLD FIX: Sanity check based on operation type
    // Different operations have different reasonable bounds
    double maxInput = MathMax(value1, value2);
    double minInput = MathMin(value1, value2);
    bool isSuspicious = false;
    
    switch(operation) {
        case COMBO_OP_ADD:
            // ADD: result should be sum of inputs (already checked in MULTIPLY overflow)
            // Maximum reasonable: 2x larger input (if both are equal)
            if(result > maxInput * 2.5) {
                isSuspicious = true;
            }
            break;
            
        case COMBO_OP_MULTIPLY:
            // MULTIPLY: already checked above, but double-check
            if(result > maxInput * 100) {
                isSuspicious = true;
            }
            break;
            
        case COMBO_OP_AVERAGE:
        case COMBO_OP_WEIGHTED:
            // AVERAGE/WEIGHTED: result should be between min and max
            if(result < minInput * 0.5 || result > maxInput * 1.5) {
                isSuspicious = true;
            }
            break;
            
        case COMBO_OP_SUBTRACT:
            // SUBTRACT: result should be <= max input
            if(result > maxInput) {
                isSuspicious = true;
            }
            break;
            
        case COMBO_OP_MIN:
            // MIN: result should equal min input
            if(result != minInput) {
                isSuspicious = true;
            }
            break;
            
        case COMBO_OP_MAX:
            // MAX: result should equal max input
            if(result != maxInput) {
                isSuspicious = true;
            }
            break;
    }
    
    if(isSuspicious) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   ApplyComboOperation: Suspicious result detected");
        Print("   Operation=", EnumToString(operation));
        Print("   v1=", DoubleToString(value1, Digits), 
              ", v2=", DoubleToString(value2, Digits));
        Print("   Result=", DoubleToString(result, Digits), 
              " (min=", DoubleToString(minInput, Digits), 
              ", max=", DoubleToString(maxInput, Digits), ")");
        Print("   Using fallback: average");
        #endif
        // Fallback to average for safety
        result = (value1 + value2) / 2.0;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  ApplyComboOperation: v1=", DoubleToString(value1, Digits), 
          ", v2=", DoubleToString(value2, Digits), 
          ", op=", EnumToString(operation), 
          ", result=", DoubleToString(result, Digits));
    #endif
    
    return result;
}

ENUM_TIMEFRAMES GetPatternTimeframe() {
    int currentMinutes = Period();
    int patternMinutes = currentMinutes * 4;
    
    // SAFETY: Clamp to valid range
    if(patternMinutes > 43200) patternMinutes = 43200; // Max = MN1
    
    // Map to closest standard timeframe
    ENUM_TIMEFRAMES result;
    if(patternMinutes <= 1) result = PERIOD_M1;
    else if(patternMinutes <= 5) result = PERIOD_M5;
    else if(patternMinutes <= 15) result = PERIOD_M15;
    else if(patternMinutes <= 30) result = PERIOD_M30;
    else if(patternMinutes <= 60) result = PERIOD_H1;
    else if(patternMinutes <= 240) result = PERIOD_H4;
    else if(patternMinutes <= 1440) result = PERIOD_D1;
    else if(patternMinutes <= 10080) result = PERIOD_W1;
    else result = PERIOD_MN1;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("GetPatternTimeframe: Current=", currentMinutes, "min, Pattern=", 
          patternMinutes, "min (4x) -> ", result);
    #endif
    
    return result;
}

//+------------------------------------------------------------------+
//| Get Structure timeframe (16x current)                            |
//|                  Structure (16           )                       |
//| FIXED: Proper bounds checking and logging                        |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetStructureTimeframe() {
    int currentMinutes = Period();
    int structureMinutes = currentMinutes * 16;
    
    // SAFETY: Clamp to valid range
    if(structureMinutes > 43200) structureMinutes = 43200; // Max = MN1
    
    // Map to closest standard timeframe
    ENUM_TIMEFRAMES result;
    if(structureMinutes <= 1) result = PERIOD_M1;
    else if(structureMinutes <= 5) result = PERIOD_M5;
    else if(structureMinutes <= 15) result = PERIOD_M15;
    else if(structureMinutes <= 30) result = PERIOD_M30;
    else if(structureMinutes <= 60) result = PERIOD_H1;
    else if(structureMinutes <= 240) result = PERIOD_H4;
    else if(structureMinutes <= 1440) result = PERIOD_D1;
    else if(structureMinutes <= 10080) result = PERIOD_W1;
    else result = PERIOD_MN1;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("GetStructureTimeframe: Current=", currentMinutes, "min, Structure=", 
          structureMinutes, "min (16x) -> ", result);
    #endif
    
    return result;
}

//+------------------------------------------------------------------+
//| Calculate Structure level interval based on base multiplier     |
//|                                                                 |
//|                                                                  |
//| EXAMPLES:                                                        |
//| Base=2: L1=2, L2=4, L3=8, L4=16, L5=32                          |
//| Base=3: L1=3, L2=9, L3=27, L4=81, L5=243                        |
//| Base=4: L1=4, L2=16, L3=64, L4=256, L5=1024                     |
//|                                                                  |
//| USAGE:                                                           |
//| Check from HIGHEST to LOWEST level for proper hierarchy:        |
//| if(step % L5 == 0)   Level 5                                    |
//| else if(step % L4 == 0)   Level 4                               |
//| else if(step % L3 == 0)   Level 3                               |
//| else if(step % L2 == 0)   Level 2                               |
//| else if(step % L1 == 0)   Level 1                               |
//| else   Trigger                                                   |
//+------------------------------------------------------------------+
int CalculateStructureInterval(const int baseMultiplier, const int level) {
    // Defensive checks for invalid inputs
    if(baseMultiplier < 2 || baseMultiplier > 9) {
        Print("   Invalid base multiplier: ", baseMultiplier, " (must be 2-9)");
        return 0;
    }
    
    if(level < 1 || level > 5) {
        Print("   Invalid level: ", level, " (must be 1-5)");
        return 0;
    }
    
    // FRACTAL formula: base   2^(level-1) instead of base^level
    // This preserves the fractal 2  ratio: L(n+1)/L(n) = 2
    // And ensures all L1-L5 are always reachable within maxLevels
    return baseMultiplier * (int)MathPow(2, level - 1);
}

//+------------------------------------------------------------------+
//| Get validated base multiplier with auto-correction               |
//|                                                                 |
//|                                                                  |
//| This function ensures baseMultiplier is always in valid range    |
//| If invalid value is detected, auto-corrects to default (3)      |
//|                                                                  |
//| @return Valid base multiplier (2-9, default: 3)                 |
//+------------------------------------------------------------------+
int GetValidatedBaseMultiplier() {
    int baseMultiplier = (int)inpStructureBase;
    
    // AUTO-CORRECTION: Ensure value is in valid range (2-9)
    if(baseMultiplier < 2 || baseMultiplier > 9) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetValidatedBaseMultiplier: Invalid value ", baseMultiplier, 
              " detected, auto-correcting to default: 3");
        #endif
        return 3; // Default fallback
    }
    
    return baseMultiplier;
}

//+------------------------------------------------------------------+
//| Helper function to determine if a step should be drawn          |
//| Matches Java's shouldDrawStep (line 231)                        |
//| OPTIMIZED: Takes triggerEnabled as parameter to avoid repeated calls |
//+------------------------------------------------------------------+
bool ShouldDrawStepOptimized(const int step, const bool triggerEnabled, const int baseMultiplier) {
    // Java logic (line 231-233): if trigger enabled, draw all; else draw only multiples of base
    if(triggerEnabled) return true;
    
    // SAFETY: Validate baseMultiplier before using in modulo operation
    int validatedMultiplier = baseMultiplier;
    if(validatedMultiplier < 2 || validatedMultiplier > 9) {
        validatedMultiplier = 3; // Fallback to default
    }
    
    return (step % validatedMultiplier == 0);
}

//+------------------------------------------------------------------+
//| Legacy wrapper for backward compatibility                       |
//| Use ShouldDrawStepOptimized in loops for better performance     |
//+------------------------------------------------------------------+
bool ShouldDrawStep(const int step) {
    // Java logic (line 231-233): if trigger enabled, draw all; else draw only multiples of base
    if(IsTriggerLevelsEnabled()) return true;
    
    // Use validated base multiplier (auto-corrects if invalid)
    int baseMultiplier = GetValidatedBaseMultiplier();
    
    return (step % baseMultiplier == 0);
}

//+------------------------------------------------------------------+
//| Cache for structure intervals to avoid repeated MathPow() calls |
//|                                                   MathPow       |
//+------------------------------------------------------------------+
static int g_cachedBaseMultiplier = -1;
static int g_cachedIntervals[5]; // L1-L5

//+------------------------------------------------------------------+
//| Get cached structure intervals for the given base multiplier    |
//| Recalculates only if base multiplier changes                    |
//| AUTO-CORRECTS invalid baseMultiplier to default (3)             |
//|                                                                  |
//| FIXED: Returns intervals in REVERSE priority order              |
//| This ensures proper hierarchy checking (L5   L4   L3   L2   L1) |
//+------------------------------------------------------------------+
void GetCachedIntervals(const int baseMultiplier, int &intervals[]) {
    // SAFETY: Validate baseMultiplier before caching
    int validatedMultiplier = baseMultiplier;
    if(validatedMultiplier < 2 || validatedMultiplier > 9) {
        validatedMultiplier = 3; // Auto-correct to default
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetCachedIntervals: Invalid base ", baseMultiplier, 
              " auto-corrected to ", validatedMultiplier);
        #endif
    }
    
    if(g_cachedBaseMultiplier != validatedMultiplier) {
        // Recalculate intervals with validated multiplier
        for(int i = 0; i < 5; i++) {
            g_cachedIntervals[i] = CalculateStructureInterval(validatedMultiplier, i + 1);
        }
        g_cachedBaseMultiplier = validatedMultiplier;
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("   Structure intervals calculated for base ", validatedMultiplier, 
              ": L1=", g_cachedIntervals[0], ", L2=", g_cachedIntervals[1], 
              ", L3=", g_cachedIntervals[2], ", L4=", g_cachedIntervals[3], 
              ", L5=", g_cachedIntervals[4]);
        #endif
    }
    
    // Copy to output array — resize only when needed
    if(ArraySize(intervals) != 5) ArrayResize(intervals, 5);
    intervals[0] = g_cachedIntervals[0];
    intervals[1] = g_cachedIntervals[1];
    intervals[2] = g_cachedIntervals[2];
    intervals[3] = g_cachedIntervals[3];
    intervals[4] = g_cachedIntervals[4];
}

//+------------------------------------------------------------------+
//| Get highest structure level for a given step                     |
//|                                                                 |
//|                                                                  |
//| Returns the highest level (1-5) that this step belongs to       |
//| Returns 0 if step is not a structure level (i.e., trigger)      |
//|                                                                  |
//| EXAMPLES with Base=4:                                            |
//| Step 4:  Returns 1 (L1 only)                                    |
//| Step 8:  Returns 1 (L1 only)                                    |
//| Step 16: Returns 2 (L2, not L1)                                 |
//| Step 64: Returns 3 (L3, not L2 or L1)                           |
//| Step 5:  Returns 0 (Trigger, not Structure)                     |
//|                                                                  |
//| SECURITY: Full input validation with safe defaults              |
//|                                                                  |
//| @param step The step number to check                            |
//| @param intervals Array of structure intervals [L1, L2, L3, L4, L5] |
//| @return Highest level (1-5) or 0 if trigger/invalid             |
//+------------------------------------------------------------------+
int GetHighestStructureLevel(const int step, const int &intervals[]) {
    // SECURITY: Validate inputs
    if(step == 0) return 0; // Midpoint is not a structure level
    
    int absStep = MathAbs(step);
    if(absStep <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetHighestStructureLevel: Invalid step=", step);
        #endif
        return 0;
    }
    
    // SECURITY: Validate array size
    int arraySize = ArraySize(intervals);
    if(arraySize != 5) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetHighestStructureLevel: Invalid intervals array size=", arraySize, " (expected 5)");
        #endif
        return 0;
    }
    
    // SECURITY: Validate intervals are positive and in ascending order
    for(int i = 0; i < 5; i++) {
        if(intervals[i] <= 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("  GetHighestStructureLevel: Invalid interval[", i, "]=", intervals[i]);
            #endif
            return 0;
        }
        // Check ascending order (L2 > L1, L3 > L2, etc.)
        if(i > 0 && intervals[i] <= intervals[i-1]) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("  GetHighestStructureLevel: Intervals not in ascending order at index ", i);
            #endif
            return 0;
        }
    }
    
    // Check from highest to lowest (L5   L4   L3   L2   L1)
    // Use absStep to handle both positive and negative steps
    if(absStep % intervals[4] == 0) return 5;
    if(absStep % intervals[3] == 0) return 4;
    if(absStep % intervals[2] == 0) return 3;
    if(absStep % intervals[1] == 0) return 2;
    if(absStep % intervals[0] == 0) return 1;
    
    return 0; // Trigger level
}

//+------------------------------------------------------------------+
//| Get path/style for level based on step count                    |
//| Matches Java's getPathForLevel (line 130)                       |
//| Returns true if level should be drawn with output parameters    |
//| Uses configurable base multiplier to calculate Structure levels |
//| OPTIMIZED VERSION: Takes triggerEnabled as parameter            |
//+------------------------------------------------------------------+
bool GetPathForLevelOptimized(const int stepCount, color &outColor, ENUM_LINE_STYLE &outStyle, int &outWidth, const bool triggerEnabled) {
    // First check structure levels (matching Java getPathForLevel line 131-136)
    if(inpShowStructure) {
        // Get validated base multiplier (auto-corrects if invalid)
        int baseMultiplier = GetValidatedBaseMultiplier();
        
        // Get cached intervals (recalculates only if base changed)
        int intervals[];
        GetCachedIntervals(baseMultiplier, intervals);
        
        // Check from highest to lowest level to ensure priority
        // (e.g., step 16 with base=4 is both L2 and multiple of L1, but L2 takes priority)
        
        // Level 5: base^5
        if(intervals[4] > 0 && stepCount % intervals[4] == 0 && inpShowStructureL5) {
            outColor = inpStructureL5Color;
            outStyle = inpStructureL5Style;
            outWidth = inpStructureL5Width;
            return true;
        }
        
        // Level 4: base^4
        if(intervals[3] > 0 && stepCount % intervals[3] == 0 && inpShowStructureL4) {
            outColor = inpStructureL4Color;
            outStyle = inpStructureL4Style;
            outWidth = inpStructureL4Width;
            return true;
        }
        
        // Level 3: base^3
        if(intervals[2] > 0 && stepCount % intervals[2] == 0 && inpShowStructureL3) {
            outColor = inpStructureL3Color;
            outStyle = inpStructureL3Style;
            outWidth = inpStructureL3Width;
            return true;
        }
        
        // Level 2: base^2
        if(intervals[1] > 0 && stepCount % intervals[1] == 0 && inpShowStructureL2) {
            outColor = inpStructureL2Color;
            outStyle = inpStructureL2Style;
            outWidth = inpStructureL2Width;
            return true;
        }
        
        // Level 1: base^1
        if(intervals[0] > 0 && stepCount % intervals[0] == 0 && inpShowStructureL1) {
            outColor = inpStructureL1Color;
            outStyle = inpStructureL1Style;
            outWidth = inpStructureL1Width;
            return true;
        }
    }
    
    // If Trigger lines are enabled, all steps use trigger path (matching Java line 139-140)
    if(triggerEnabled) {
        outColor = GetTriggerRenderColor();
        outStyle = inpTriggerStyle;
        outWidth = inpTriggerWidth;
        return true;
    }
    
    // Don't draw anything if neither structure nor trigger lines are enabled (matching Java line 143)
    return false;
}

//+------------------------------------------------------------------+
//| Get Zone Color for level (uses CURRENT level's color)           |
//|            Zone          (                              )        |
//|                                                                  |
//| Logic: Zone uses SAME logic as level drawing                    |
//|     : Zone                                                      |
//|                                                                  |
//| Priority: Structure (L5>L4>L3>L2>L1) > Trigger > Mode Color     |
//|       :         (L5>L4>L3>L2>L1) >       >     Mode              |
//|                                                                  |
//| @param currentStep Current step number (must be > 0)            |
//| @param triggerEnabled Whether trigger levels are enabled        |
//| @param baseMultiplier Base multiplier for structure levels      |
//| @return Zone color (clrNONE = use mode's default color)         |
//+------------------------------------------------------------------+
color GetZoneColorForLevel(const int currentStep, const bool triggerEnabled, const int baseMultiplier) {
    // VALIDATION: Check if zones are enabled
    if(!inpShowMidZones) return clrNONE;
    
    // VALIDATION: Ensure currentStep is valid (avoid division by zero issues)
    if(currentStep <= 0) return clrNONE;
    
    // PRIORITY 1: Check structure levels first (L5 > L4 > L3 > L2 > L1)
    //         :                               
    if(inpShowStructure) {
        // VALIDATION: Ensure baseMultiplier is valid before using it
        // Use GetValidatedBaseMultiplier for consistency
        int validatedMultiplier = baseMultiplier;
        if(validatedMultiplier < 2 || validatedMultiplier > 9) {
            validatedMultiplier = GetValidatedBaseMultiplier(); // Use central validation
        }
        
        // OPTIMIZATION: Use cached intervals (recalculates only if base changed)
        int intervals[];
        GetCachedIntervals(validatedMultiplier, intervals);
        
        // Check from highest to lowest level (same as GetPathForLevelOptimized)
        // SAFETY: Check intervals[i] > 0 to avoid division by zero
        if(intervals[4] > 0 && currentStep % intervals[4] == 0 && inpShowStructureL5) {
            return inpStructureL5Color;
        }
        if(intervals[3] > 0 && currentStep % intervals[3] == 0 && inpShowStructureL4) {
            return inpStructureL4Color;
        }
        if(intervals[2] > 0 && currentStep % intervals[2] == 0 && inpShowStructureL3) {
            return inpStructureL3Color;
        }
        if(intervals[1] > 0 && currentStep % intervals[1] == 0 && inpShowStructureL2) {
            return inpStructureL2Color;
        }
        if(intervals[0] > 0 && currentStep % intervals[0] == 0 && inpShowStructureL1) {
            return inpStructureL1Color;
        }
    }
    
    // PRIORITY 2: If Trigger is enabled, DON'T use trigger color for zones
    //         :     Trigger                  Trigger      zone            
    // Zones should ONLY be drawn between structure levels, not trigger levels
    // Zone                 structure levels             trigger levels
    
    // PRIORITY 3: Fallback to mode's default color
    //         :                        mode
    return clrNONE;  // Signal to use level's own color (SS/LS/M/TP)
}


//+------------------------------------------------------------------+
//| Draw SS/LS levels with alternating pattern                      |
//+------------------------------------------------------------------+
void DrawSSLSLevels(const string objectPrefix, const double midpointPrice, 
                    const double ssValue, const double lsValue, const bool lsFirst,
                    const int maxLevelsAbove = 0, const int maxLevelsBelow = 0)
{
    if(ssValue <= 0 || lsValue <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("DrawSSLSLevels: Invalid SS/LS values");
        #endif
        return;
    }
    
    // Note: ClearAllLevels is called in DrawLevelsBasedOnMode before this function
    
    //                                                                
    // CLEANUP OLD ZONES
    //                         
    //                                                                
    if(inpShowMidZones) {
        ObjectsDeleteAll(0, objectPrefix + "SSLS_Zone_", -1, -1);
    }
    
    double stepDistances[2];
    stepDistances[0] = lsFirst ? lsValue : ssValue;  // First step
    stepDistances[1] = lsFirst ? ssValue : lsValue;  // Second step
    
    // CRITICAL FIX: Calculate average step size for consistent zone height
    double avgStepSize = (ssValue + lsValue) / 2.0;
    
    int effectiveMaxAbove = (maxLevelsAbove > 0) ? maxLevelsAbove : inpMaxLevels;
    int effectiveMaxBelow = (maxLevelsBelow > 0) ? maxLevelsBelow : inpMaxLevels;
    
    // OPTIMIZATION: Cache frequently called values BEFORE the loop
    bool triggerEnabled = IsTriggerLevelsEnabled();
    bool structureEnabled = inpShowStructure;
    int baseMultiplier = GetValidatedBaseMultiplier(); // Use central validation
    bool checkCustomPrice = (g_thStartPointType != TH_START_POINT_CUSTOM_PRICE);
    
    // Draw level at midpoint (step 0)
    color midpointColor = clrNONE;
    ENUM_LINE_STYLE midpointStyle = STYLE_SOLID;
    int midpointWidth = 1;
    if(GetPathForLevelOptimized(0, midpointColor, midpointStyle, midpointWidth, triggerEnabled)) {
        // Use structure/trigger path if available
    } else {
        // Use LS color for midpoint as it's the starting point
        midpointColor = inpLSLevelColor;
        midpointStyle = inpLSLevelStyle;
        midpointWidth = inpLSLevelWidth;
    }
    
    string midpointName = objectPrefix + "SSLS_Midpoint_0";
    if(ObjectFind(0, midpointName) < 0) {
        ObjectCreate(0, midpointName, OBJ_HLINE, 0, 0, midpointPrice);
    }
    ObjectSetInteger(0, midpointName, OBJPROP_COLOR, midpointColor);
    ObjectSetInteger(0, midpointName, OBJPROP_STYLE, midpointStyle);
    ObjectSetInteger(0, midpointName, OBJPROP_WIDTH, midpointWidth);
    ObjectSetInteger(0, midpointName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, midpointName, OBJPROP_SELECTED, false);
    ObjectSetDouble(0, midpointName, OBJPROP_PRICE, midpointPrice);
    ObjectSetString(0, midpointName, OBJPROP_TOOLTIP, 
                   "Midpoint (Start) - " + DoubleToString(midpointPrice, Digits));
    
    int drawnAbove = 0;
    int logicalStep = 0;
    double cumulative = 0;
    int zoneCountAbove = 0;  // Track zones drawn above
    
    // Initialize zone tracking with validation (Gold Version)
    double lastStructurePriceAbove, lastTriggerPriceAbove, lastFallbackPriceAbove;
    if(!InitializeZoneTracking(midpointPrice, lastStructurePriceAbove, 
                               lastTriggerPriceAbove, lastFallbackPriceAbove)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  DrawSSLSLevels: Failed to initialize zone tracking (Above)");
        #endif
        return;  // Abort if initialization failed
    }
    
    // SECURITY FIX: Add iteration limit to prevent infinite loops
    int maxIterations = effectiveMaxAbove * 2;  // Safety margin
    int iterations = 0;
    
    while(drawnAbove < effectiveMaxAbove && iterations < maxIterations) {
        iterations++;
        double dist = stepDistances[logicalStep % 2];
        cumulative += dist;
        logicalStep++;
        
        double priceLevel = midpointPrice + cumulative;
        
        // LOG FIRST LEVEL for debugging (GUARDED - compile-time)
        #ifdef ENABLE_DEBUG_LOGS
        if(logicalStep == 1) {
            Print("========== MT4 FIRST LEVEL DEBUG ==========");
            Print("Anchor (midpoint): ", DoubleToString(midpointPrice, 10));
            Print("Step distance (LS): ", DoubleToString(dist, 10));
            Print("First level price: ", DoubleToString(priceLevel, 10));
            Print("Formula: ", DoubleToString(midpointPrice, 10), " + ", DoubleToString(dist, 10), " = ", DoubleToString(priceLevel, 10));
            Print("===========================================");
            Print("   MT4 FIRST LEVEL: ", DoubleToString(priceLevel, 10), " (LS=", DoubleToString(dist, 10), ")");
        }
        #endif
        
        // Check if we exceeded the highest high (only in non-Custom Price modes)
        // In Custom Price Mode, we draw exactly the requested number of levels
        if(checkCustomPrice) {
            if(priceLevel > g_highestHigh) break;
        }
        
        // Check if this step should be drawn (matching Java shouldDrawStep line 184)
        // OPTIMIZATION: Use ShouldDrawStepOptimized with cached values
        if(structureEnabled || triggerEnabled) {
            if(!ShouldDrawStepOptimized(logicalStep, triggerEnabled, baseMultiplier)) {
                continue;
            }
        } else {
            // Neither structure nor trigger enabled - draw every baseMultiplier-th step
            if(logicalStep % baseMultiplier != 0) {
                continue;
            }
        }
        
        // Get path for this level (matching Java getPathForLevel line 187)
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        bool isSS = ((logicalStep % 2 == 0) == lsFirst); // Determine if SS or LS
        
        // OPTIMIZATION: Use GetPathForLevelOptimized with cached triggerEnabled
        if(!GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
            // Fall back to SS/LS specific paths when structure/trigger disabled (Java line 189-191)
            levelColor = isSS ? inpSSLevelColor : inpLSLevelColor;
            levelStyle = isSS ? inpSSLevelStyle : inpLSLevelStyle;
            levelWidth = isSS ? inpSSLevelWidth : inpLSLevelWidth;
        }
        
        string levelName = objectPrefix + "SSLS_Above_" + IntegerToString(logicalStep);
        
        // Create the level line
        if(ObjectFind(0, levelName) < 0) {
            ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, priceLevel);
        }
        
        ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
        ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
        ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);  // Make non-selectable
        ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);    // Ensure not selected
        ObjectSetDouble(0, levelName, OBJPROP_PRICE, priceLevel);
        ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
                       (isSS ? "SS " : "LS ") + IntegerToString(logicalStep) + 
                       " (" + DoubleToString(priceLevel, Digits) + ")");
        
        drawnAbove++;
        
        //                                                            
        // DRAW MID-RANGE ZONE (AFTER drawing this level)
        //                  (                  )
        // 
        // UNIFIED APPROACH: Use CreateZoneWithSmartFallback
        //               :    CreateZoneWithSmartFallback           
        //                                                            
        if(inpShowMidZones) {
            // Determine if this is a structure level
            bool isStructureLevel = false;
            if(structureEnabled) {
                int intervals[];
                GetCachedIntervals(baseMultiplier, intervals);
                
                for(int j = 0; j < 5; j++) {
                    if(intervals[j] > 0 && logicalStep % intervals[j] == 0) {
                        isStructureLevel = true;
                        break;
                    }
                }
            }
            
            string zoneName = objectPrefix + "SSLS_Zone_Above_" + IntegerToString(logicalStep);
            
            // CRITICAL FIX: Pass avgStepSize for consistent zone height
            // CRITICAL FIX: Use separate tracking variables (matching Factor Mode)
            if(CreateZoneWithSmartFallback(zoneName, priceLevel, isStructureLevel, levelColor,
                                          structureEnabled, triggerEnabled,
                                          lastStructurePriceAbove, lastTriggerPriceAbove, lastFallbackPriceAbove,
                                          avgStepSize)) {  // Pass average step size
                zoneCountAbove++;
            }
        }
        
        // Note: lastStructurePriceAbove, lastTriggerPriceAbove, lastFallbackPriceAbove
        // are updated inside CreateZoneWithSmartFallback
    }
    
    // Draw levels below midpoint
    int drawnBelow = 0;
    logicalStep = 0;
    cumulative = 0;
    int zoneCountBelow = 0;  // Track zones drawn below
    
    // Initialize zone tracking with validation (Gold Version)
    double lastStructurePriceBelow, lastTriggerPriceBelow, lastFallbackPriceBelow;
    if(!InitializeZoneTracking(midpointPrice, lastStructurePriceBelow, 
                               lastTriggerPriceBelow, lastFallbackPriceBelow)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  DrawSSLSLevels: Failed to initialize zone tracking (Below)");
        #endif
        return;  // Abort if initialization failed
    }
    
    // SECURITY FIX: Add iteration limit to prevent infinite loops
    maxIterations = effectiveMaxBelow * 2;  // Safety margin
    iterations = 0;
    
    while(drawnBelow < effectiveMaxBelow && iterations < maxIterations) {
        iterations++;
        double dist = stepDistances[logicalStep % 2];
        cumulative += dist;
        logicalStep++;
        
        double priceLevel = midpointPrice - cumulative;
        
        // Check if we went below the lowest low (only in non-Custom Price modes)
        // In Custom Price Mode, we draw exactly the requested number of levels
        if(checkCustomPrice) {
            if(priceLevel < g_lowestLow) break;
        }
        
        // Check if this step should be drawn (matching Java shouldDrawStep line 210)
        // OPTIMIZATION: Use ShouldDrawStepOptimized with cached values
        if(structureEnabled || triggerEnabled) {
            if(!ShouldDrawStepOptimized(logicalStep, triggerEnabled, baseMultiplier)) {
                continue;
            }
        } else {
            // Neither structure nor trigger enabled - draw every baseMultiplier-th step
            if(logicalStep % baseMultiplier != 0) {
                continue;
            }
        }
        
        // Get path for this level (matching Java getPathForLevel line 213)
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        bool isSS = ((logicalStep % 2 == 0) == lsFirst); // Determine if SS or LS
        
        // OPTIMIZATION: Use GetPathForLevelOptimized with cached triggerEnabled
        if(!GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
            // Fall back to SS/LS specific paths when structure/trigger disabled (Java line 215-216)
            levelColor = isSS ? inpSSLevelColor : inpLSLevelColor;
            levelStyle = isSS ? inpSSLevelStyle : inpLSLevelStyle;
            levelWidth = isSS ? inpSSLevelWidth : inpLSLevelWidth;
        }
        
        string levelName = objectPrefix + "SSLS_Below_" + IntegerToString(logicalStep);
        
        // Create the level line
        if(ObjectFind(0, levelName) < 0) {
            ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, priceLevel);
        }
        
        ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
        ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
        ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);  // Make non-selectable
        ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);    // Ensure not selected
        ObjectSetDouble(0, levelName, OBJPROP_PRICE, priceLevel);
        ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
                       (isSS ? "SS " : "LS ") + IntegerToString(logicalStep) + 
                       " (" + DoubleToString(priceLevel, Digits) + ")");
        
        drawnBelow++;
        
        //                                                            
        // DRAW MID-RANGE ZONE (AFTER drawing this level)
        //                  (                  )
        // 
        // UNIFIED APPROACH: Use CreateZoneWithSmartFallback
        //               :    CreateZoneWithSmartFallback           
        //                                                            
        if(inpShowMidZones) {
            // Determine if this is a structure level
            bool isStructureLevel = false;
            if(structureEnabled) {
                int intervals[];
                GetCachedIntervals(baseMultiplier, intervals);
                
                for(int j = 0; j < 5; j++) {
                    if(intervals[j] > 0 && logicalStep % intervals[j] == 0) {
                        isStructureLevel = true;
                        break;
                    }
                }
            }
            
            string zoneName = objectPrefix + "SSLS_Zone_Below_" + IntegerToString(logicalStep);
            
            // CRITICAL FIX: Pass avgStepSize for consistent zone height
            // CRITICAL FIX: Use separate tracking variables (matching Factor Mode)
            if(CreateZoneWithSmartFallback(zoneName, priceLevel, isStructureLevel, levelColor,
                                          structureEnabled, triggerEnabled,
                                          lastStructurePriceBelow, lastTriggerPriceBelow, lastFallbackPriceBelow,
                                          avgStepSize)) {  // Pass average step size
                zoneCountBelow++;
            }
        }
        
        // Note: lastStructurePriceBelow, lastTriggerPriceBelow, lastFallbackPriceBelow
        // are updated inside CreateZoneWithSmartFallback
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    if(inpShowMidZones) {
        Print("  DrawSSLSLevels: Drew ", zoneCountAbove, " zones above, ", 
              zoneCountBelow, " zones below");
    }
    #endif
}

//+------------------------------------------------------------------+
//| Draw M levels based on Control ladder                           |
//+------------------------------------------------------------------+
//| UNIFIED HELPER: Draw Single Level with Unified Logic             |
//|                  :                                               |
//|                                                                  |
//| This function encapsulates the common logic used by all modes   |
//|                                                                  |
//+------------------------------------------------------------------+
bool DrawUnifiedLevel(
    const string levelName,
    const double price,
    const int logicalStep,
    const bool triggerEnabled,
    const bool structureEnabled,
    const int baseMultiplier,
    const color fallbackColor,
    const ENUM_LINE_STYLE fallbackStyle,
    const int fallbackWidth,
    const string tooltip)
{
    // Get path for this level - check Structure first, then Trigger
    color levelColor;
    ENUM_LINE_STYLE levelStyle;
    int levelWidth;
    
    if(GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
        // Got path from structure levels
    } else if(triggerEnabled) {
        // Use Trigger color (unified across all modes)
        levelColor = inpTriggerColor;
        levelStyle = inpTriggerStyle;
        levelWidth = inpTriggerWidth;
    } else {
        // Use fallback color (mode-specific)
        levelColor = fallbackColor;
        levelStyle = fallbackStyle;
        levelWidth = fallbackWidth;
    }
    
    // Create or update the level line
    if(ObjectFind(0, levelName) < 0) {
        if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, price)) {
            return false;
        }
    }
    
    ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
    ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
    ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
    ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
    ObjectSetDouble(0, levelName, OBJPROP_PRICE, price);
    ObjectSetString(0, levelName, OBJPROP_TOOLTIP, tooltip);
    
    return true;
}

//+------------------------------------------------------------------+
//| UNIFIED HELPER: Draw Single Zone with Unified Logic              |
//|                  :                                               |
//+------------------------------------------------------------------+
bool DrawUnifiedZone(
    const string zoneName,
    const double currentPrice,
    const int logicalStep,
    const bool triggerEnabled,
    const bool structureEnabled,
    const int baseMultiplier,
    const color levelColor,
    double &lastDrawnPrice,
    double &lastTriggerPrice)
{
    if(!inpShowMidZones) return false;
    
    // Check if current level is a structure level
    bool isCurrentStructure = false;
    if(structureEnabled) {
        int intervals[];
        GetCachedIntervals(baseMultiplier, intervals);
        
        for(int j = 0; j < 5; j++) {
            if(intervals[j] > 0 && logicalStep % intervals[j] == 0) {
                isCurrentStructure = true;
                break;
            }
        }
    }
    
    // Use unified zone creation
    return CreateZoneWithSmartFallback(zoneName, currentPrice, isCurrentStructure, levelColor,
                                      structureEnabled, triggerEnabled,
                                      lastDrawnPrice, lastTriggerPrice, lastDrawnPrice);
}

//+------------------------------------------------------------------+
//| Draw Factor boundary lines (Historical High/Low reference)       |
//| Draw Factor boundary lines (Historical High/Low reference)       |
//|               High/Low             Factor mode                    |
//+------------------------------------------------------------------+
void DrawFactorBoundaryLines(const string objectPrefix, const double highPrice, 
                              const double lowPrice, const double factor, const double stepSize)
{
    // Skip drawing High/Low lines when Custom Price mode is active
    // In Custom Price mode, user defines their own reference point (like other modes)
    if(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) {
        // Delete existing High/Low lines and labels if they exist
        ObjectDelete(0, objectPrefix + "Factor_High");
        ObjectDelete(0, objectPrefix + "Factor_Low");
        ObjectDelete(0, objectPrefix + "Factor_High_Label");
        ObjectDelete(0, objectPrefix + "Factor_Low_Label");
        return;
    }
    
    // Calculate pip size for tooltip
    double pipSize = GetCachedPipSize();
    double rangePips = (highPrice - lowPrice) / pipSize;
    double stepPips = stepSize / pipSize;
    
    // ========== Draw Historical HIGH line ==========
    string highLineName = objectPrefix + "Factor_High";
    if(ObjectFind(0, highLineName) < 0) {
        ObjectCreate(0, highLineName, OBJ_HLINE, 0, 0, highPrice);
    }
    ObjectSetDouble(0, highLineName, OBJPROP_PRICE, highPrice);
    ObjectSetInteger(0, highLineName, OBJPROP_COLOR, inpHighColor);
    ObjectSetInteger(0, highLineName, OBJPROP_STYLE, inpHighStyle);
    ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, inpHighWidth);
    ObjectSetInteger(0, highLineName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, highLineName, OBJPROP_SELECTED, false);
    ObjectSetString(0, highLineName, OBJPROP_TOOLTIP, 
        StringFormat("Historical HIGH | %s | Range: %.0f pips", 
            DoubleToString(highPrice, Digits), rangePips));
    
    // ========== Draw Historical LOW line ==========
    string lowLineName = objectPrefix + "Factor_Low";
    if(ObjectFind(0, lowLineName) < 0) {
        ObjectCreate(0, lowLineName, OBJ_HLINE, 0, 0, lowPrice);
    }
    ObjectSetDouble(0, lowLineName, OBJPROP_PRICE, lowPrice);
    ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, inpLowColor);
    ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, inpLowStyle);
    ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, inpLowWidth);
    ObjectSetInteger(0, lowLineName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, lowLineName, OBJPROP_SELECTED, false);
    ObjectSetString(0, lowLineName, OBJPROP_TOOLTIP, 
        StringFormat("Historical LOW | %s | Range: %.0f pips", 
            DoubleToString(lowPrice, Digits), rangePips));
    
    // ========== Draw HIGH label ==========
    string highLabelName = objectPrefix + "Factor_High_Label";
    datetime _lblTime1 = CacheGetFrameTime();
    if(ObjectFind(0, highLabelName) < 0) {
        ObjectCreate(0, highLabelName, OBJ_TEXT, 0, _lblTime1, highPrice);
    }
    ObjectSetDouble(0, highLabelName, OBJPROP_PRICE, highPrice);
    ObjectSetInteger(0, highLabelName, OBJPROP_TIME, _lblTime1);
    ObjectSetInteger(0, highLabelName, OBJPROP_COLOR, inpHighColor);
    ObjectSetInteger(0, highLabelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, highLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
    ObjectSetString(0, highLabelName, OBJPROP_FONT, "Arial");
    ObjectSetString(0, highLabelName, OBJPROP_TEXT,
        StringFormat("  HIGH %s | Range: %.0f pips | F=%.2f | Step: %.1f pips",
            DoubleToString(highPrice, Digits), rangePips, factor, stepPips));
    ObjectSetInteger(0, highLabelName, OBJPROP_SELECTABLE, false);
    
    // ========== Draw LOW label ==========
    string lowLabelName = objectPrefix + "Factor_Low_Label";
    if(ObjectFind(0, lowLabelName) < 0) {
        ObjectCreate(0, lowLabelName, OBJ_TEXT, 0, _lblTime1, lowPrice);
    }
    ObjectSetDouble(0, lowLabelName, OBJPROP_PRICE, lowPrice);
    ObjectSetInteger(0, lowLabelName, OBJPROP_TIME, _lblTime1);
    ObjectSetInteger(0, lowLabelName, OBJPROP_COLOR, inpLowColor);
    ObjectSetInteger(0, lowLabelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, lowLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetString(0, lowLabelName, OBJPROP_FONT, "Arial");
    ObjectSetString(0, lowLabelName, OBJPROP_TEXT, 
        StringFormat("  LOW %s | Range: %.0f pips | F=%.2f | Step: %.1f pips", 
            DoubleToString(lowPrice, Digits), rangePips, factor, stepPips));
    ObjectSetInteger(0, lowLabelName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw Factor levels with perfect equal spacing (aligned)          |
//|                                             (        )            |
//| Ensures all spacing is equal including at chart boundaries       |
//+------------------------------------------------------------------+
//| Draw Factor Levels with Harmonic Alternating Pattern             |
//|                                                                   |
//| Alternates between Base Step ( 2) and Large Step ( ratio)        |
//| Creates macro symmetry with micro variation                       |
#ifndef BUILD_LITE
//+------------------------------------------------------------------+
void DrawFactorLevelsHarmonic(const string objectPrefix, const double highPrice, 
                              const double lowPrice, const double factor, 
                              const double baseStepSize, const double harmonicRatio)
{
    //                                                                
    // CRITICAL INPUT VALIDATION
    //                                                                
    
    // Validate object prefix
    if(StringLen(objectPrefix) == 0) {
        Print("  DrawFactorLevelsHarmonic: Empty object prefix");
        return;
    }
    
    // Validate price range
    if(highPrice <= 0 || lowPrice <= 0) {
        Print("  DrawFactorLevelsHarmonic: Invalid prices - High=", highPrice, ", Low=", lowPrice);
        return;
    }
    if(highPrice <= lowPrice) {
        Print("  DrawFactorLevelsHarmonic: Invalid range - High must be > Low");
        return;
    }
    
    // Validate base step size
    if(baseStepSize <= 0) {
        Print("  DrawFactorLevelsHarmonic: Invalid base step size: ", baseStepSize);
        return;
    }
    
    // CRITICAL: Validate harmonic ratio with strict bounds
    if(harmonicRatio < MIN_HARMONIC_RATIO) {
        Print("  DrawFactorLevelsHarmonic: Ratio too small (", harmonicRatio, 
              ") - must be >= ", MIN_HARMONIC_RATIO, " for meaningful alternation");
        return;
    }
    if(harmonicRatio > MAX_HARMONIC_RATIO) {
        Print("  DrawFactorLevelsHarmonic: Ratio too large (", harmonicRatio, 
              ") - must be <= ", MAX_HARMONIC_RATIO);
        return;
    }
    
    //                                                                
    // CLEANUP OLD OBJECTS (prevent visual clutter)
    //                                                                
    
    // Delete old harmonic objects before drawing new ones
    ObjectsDeleteAll(0, objectPrefix + "Factor_Mid_", -1, -1);
    ObjectsDeleteAll(0, objectPrefix + "Factor_Up_", -1, -1);
    ObjectsDeleteAll(0, objectPrefix + "Factor_Down_", -1, -1);
    
    //                                                                
    // CALCULATE STEP SIZES
    //                                                                
    
    // Calculate large step size
    double largeStepSize = baseStepSize * harmonicRatio;
    
    // Validate large step doesn't exceed range
    double range = highPrice - lowPrice;
    if(largeStepSize > range) {
        Print("   DrawFactorLevelsHarmonic: Large step (", largeStepSize, 
              ") exceeds range (", range, ") - adjusting");
        largeStepSize = range * 0.5;  // Max 50% of range
    }
    
    // Calculate midpoint (center of range)
    double midpoint = NormalizeDouble((highPrice + lowPrice) / 2.0, Digits);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawFactorLevelsHarmonic ====================");
    Print("High=", highPrice, ", Low=", lowPrice, ", Range=", range);
    Print("Midpoint=", midpoint, ", Factor=", factor);
    Print("BaseStep=", baseStepSize, ", LargeStep=", largeStepSize);
    Print("Ratio=", harmonicRatio, " (", DoubleToString((harmonicRatio - 1.0) * 100, 1), "% larger)");
    #endif
    
    //                                                                
    // DRAW MIDPOINT LEVEL
    //                                                                
    
    string midName = objectPrefix + "Factor_Mid_0";
    if(ObjectFind(0, midName) < 0) {
        if(!ObjectCreate(0, midName, OBJ_HLINE, 0, 0, midpoint)) {
            Print("  Failed to create midpoint level. Error: ", GetLastError());
            return;
        }
    }
    
    ObjectSetDouble(0, midName, OBJPROP_PRICE, midpoint);
    ObjectSetInteger(0, midName, OBJPROP_COLOR, C'255,140,0');  // DarkOrange - visible on Lavender
    ObjectSetInteger(0, midName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, midName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, midName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, midName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, midName, OBJPROP_BACK, false);
    ObjectSetString(0, midName, OBJPROP_TOOLTIP, 
        StringFormat("   Harmonic Center | %s | F=%.2f | R=%.3f", 
            DoubleToString(midpoint, Digits), factor, harmonicRatio));
    
    //                                                                
    // PREPARE PATTERN ARRAY (optimization)
    //                                                                
    
    // Pattern: [baseStep, largeStep, baseStep, largeStep, ...]
    double stepPattern[2];
    stepPattern[0] = baseStepSize;   // Smaller step ( 2)
    stepPattern[1] = largeStepSize;  // Larger step ( ratio)
    
    //                                                                
    // CALCULATE MAX LEVELS (with safety limits)
    //                                                                
    
    // Calculate approximate max levels per side
    double halfRange = range / 2.0;
    double avgStep = (baseStepSize + largeStepSize) / 2.0;
    int maxLevelsPerSide = (int)MathCeil(halfRange / avgStep);
    
    // Safety limit to prevent infinite loops or MT4 hang
    const int MAX_HARMONIC_LEVELS = 2500;
    if(maxLevelsPerSide > MAX_HARMONIC_LEVELS) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   Clamping levels from ", maxLevelsPerSide, " to ", MAX_HARMONIC_LEVELS);
        #endif
        maxLevelsPerSide = MAX_HARMONIC_LEVELS;
    }
    
    // Additional safety: minimum step size check
    if(baseStepSize < Point * 2) {
        Print("  DrawFactorLevelsHarmonic: Base step too small (", baseStepSize, 
              ") - must be >= ", Point * 2);
        return;
    }
    
    //                                                                
    // CACHE TRIGGER STATE (optimization)
    //                                                                
    
    bool triggerEnabled = IsTriggerLevelsEnabled();
    bool structureEnabled = inpShowStructure;
    int baseMultiplier = GetValidatedBaseMultiplier(); // Use central validation
    
    //                                                                
    // DRAW LEVELS ABOVE MIDPOINT
    //                                                                
    
    double cumulative = 0;
    int levelsAbove = 0;
    int iterationCount = 0;  // Safety counter
    
    for(int i = 0; i < maxLevelsPerSide && iterationCount < MAX_HARMONIC_LEVELS * 2; i++, iterationCount++) {
        // Get step size for this iteration (alternating pattern)
        double step = stepPattern[i % 2];
        cumulative += step;
        double priceLevel = midpoint + cumulative;
        
        // CRITICAL: Stop if we exceed high price
        if(priceLevel > highPrice) {
            #ifdef ENABLE_DEBUG_LOGS
            if(i == 0) Print("   First level above midpoint exceeds high - step too large");
            #endif
            break;
        }
        
        // Normalize price
        priceLevel = NormalizeDouble(priceLevel, Digits);
        
        // Determine if this is base or large step
        bool isBase = (i % 2 == 0);
        
        //                                                                
        // PRIORITY SYSTEM FOR COLORS AND STYLES
        //                                                                
        // PRIORITY 1: Harmonic Pattern (always takes precedence)
        //   - Preserves alternating rhythm
        //   - No filtering (all levels drawn)
        // PRIORITY 2: Structure/Trigger (if Harmonic disabled)
        //   - Applies filtering based on baseMultiplier
        // PRIORITY 3: Default Factor colors
        //                                                                
        
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        bool shouldDraw = true;  // Default: draw all levels
        
        int logicalStep = i + 1;  // Step count for Structure levels
        
        // PRIORITY 1: Harmonic colors always take precedence
        levelColor = isBase ? inpHarmonicBaseColor : inpHarmonicLargeColor;
        levelStyle = inpFactorLevelStyle;
        levelWidth = isBase ? inpHarmonicBaseWidth : inpHarmonicLargeWidth;
        
        // NO FILTERING in Harmonic Mode - draw all levels to preserve pattern
        // (Structure/Trigger filtering would break the alternating rhythm)
        
        // Create level name
        string levelName = objectPrefix + "Factor_Up_" + IntegerToString(i + 1);
        
        // Create or update level
        if(ObjectFind(0, levelName) < 0) {
            if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, priceLevel)) {
                Print("   Failed to create level above ", i + 1, ". Error: ", GetLastError());
                continue;
            }
        }
        
        ObjectSetDouble(0, levelName, OBJPROP_PRICE, priceLevel);
        ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
        ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
        ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
        ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
            StringFormat("%s Step %d | %s | F=%.2f |  =%.1f", 
                (isBase ? "   Base" : "   Large"), i + 1, 
                DoubleToString(priceLevel, Digits), factor, step / Point));
        
        levelsAbove++;
    }
    
    //                                                                
    // DRAW LEVELS BELOW MIDPOINT
    //                                                                
    
    cumulative = 0;
    int levelsBelow = 0;
    iterationCount = 0;  // Reset safety counter
    
    for(int i = 0; i < maxLevelsPerSide && iterationCount < MAX_HARMONIC_LEVELS * 2; i++, iterationCount++) {
        double step = stepPattern[i % 2];
        cumulative += step;
        double priceLevel = midpoint - cumulative;
        
        // CRITICAL: Stop if we go below low price
        if(priceLevel < lowPrice) {
            #ifdef ENABLE_DEBUG_LOGS
            if(i == 0) Print("   First level below midpoint goes below low - step too large");
            #endif
            break;
        }
        
        // Normalize price
        priceLevel = NormalizeDouble(priceLevel, Digits);
        
        bool isBase = (i % 2 == 0);
        
        //                                                                
        // PRIORITY SYSTEM FOR COLORS AND STYLES (same as above)
        //                                                                
        
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        
        int logicalStep = i + 1;
        
        // PRIORITY 1: Harmonic colors always take precedence
        levelColor = isBase ? inpHarmonicBaseColor : inpHarmonicLargeColor;
        levelStyle = inpFactorLevelStyle;
        levelWidth = isBase ? inpHarmonicBaseWidth : inpHarmonicLargeWidth;
        
        // NO FILTERING in Harmonic Mode - draw all levels to preserve pattern
        
        string levelName = objectPrefix + "Factor_Down_" + IntegerToString(i + 1);
        
        if(ObjectFind(0, levelName) < 0) {
            if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, priceLevel)) {
                Print("   Failed to create level below ", i + 1, ". Error: ", GetLastError());
                continue;
            }
        }
        
        ObjectSetDouble(0, levelName, OBJPROP_PRICE, priceLevel);
        ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
        ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
        ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
        ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
            StringFormat("%s Step %d | %s | F=%.2f |  =%.1f", 
                (isBase ? "   Base" : "   Large"), i + 1, 
                DoubleToString(priceLevel, Digits), factor, step / Point));
        
        levelsBelow++;
    }
    
    //                                                                
    // FINAL REPORT
    //                                                                
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  DrawFactorLevelsHarmonic: Drew ", levelsAbove, " levels above, ", 
          levelsBelow, " levels below midpoint");
    Print("Total: ", (levelsAbove + levelsBelow + 1), " levels (including midpoint)");
    #endif
}
#endif

//+------------------------------------------------------------------+
void DrawFactorLevelsAligned(const string objectPrefix, const double highPrice, 
                             const double lowPrice, const double factor, const double stepSize)
{
    // Comprehensive input validation
    if(StringLen(objectPrefix) == 0) {
        Print("DrawFactorLevelsAligned: Empty object prefix");
        return;
    }
    if(highPrice <= 0 || lowPrice <= 0) {
        Print("DrawFactorLevelsAligned: Invalid prices - High=", highPrice, ", Low=", lowPrice);
        return;
    }
    if(highPrice <= lowPrice) {
        Print("DrawFactorLevelsAligned: Invalid range - High (", highPrice, ") must be greater than Low (", lowPrice, ")");
        return;
    }
    if(stepSize <= 0) {
        Print("DrawFactorLevelsAligned: Invalid step size: ", stepSize);
        return;
    }
    
    // Determine drawing direction based on current price position
    // GOAL: Put any unequal gap at the FARTHER boundary from current price
    // 
    // LOGIC:
    // - Starting from HIGH and going DOWN   last level ends near LOW
    // - Starting from LOW and going UP   last level ends near HIGH
    // - The "gap" (if any) appears where we END, not where we START
    // 
    // Therefore:
    // - To put gap at LOW (bottom)   start from HIGH (top)
    // - To put gap at HIGH (top)   start from LOW (bottom)
    // 
    // User wants gap at FARTHER boundary:
    // - If price closer to HIGH   gap should be at LOW   start from HIGH
    // - If price closer to LOW   gap should be at HIGH   start from LOW
    // 
    // CONCLUSION: Start from the boundary that is FARTHER from current price
    
    double currentPrice = Bid;
    double distToHigh = MathAbs(currentPrice - highPrice);
    double distToLow = MathAbs(currentPrice - lowPrice);
    
    // Start from FARTHER boundary so gap ends up at FARTHER side
    bool startFromHigh = (distToHigh > distToLow);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("Factor Direction: Price=", DoubleToString(currentPrice, Digits),
          ", DistHigh=", DoubleToString(distToHigh, Digits),
          ", DistLow=", DoubleToString(distToLow, Digits),
          ", Start=", (startFromHigh ? "HIGH" : "LOW"));
    #endif
    
    // Calculate how many levels fit in the range
    // Formula: totalLevels = floor(range / stepSize)
    // Example: range=0.78, stepSize=0.09   totalLevels = floor(8.67) = 8
    // This means we can fit 8 steps in the range
    // Since loop starts at i=1, we draw levels at: boundary + 1*step, boundary + 2*step, ..., boundary + 8*step
    double range = highPrice - lowPrice;
    int totalLevels = (int)MathFloor(range / stepSize);
    
    if(totalLevels <= 1) {
        Print("DrawFactorLevelsAligned: Not enough space (totalLevels=", totalLevels, 
              ", range=", DoubleToString(range, Digits), 
              ", stepSize=", DoubleToString(stepSize, Digits), ")");
        return;
    }
    
    // NOTE: We do NOT subtract 1 here!
    // The loop starts from i=1 (not i=0), so first level is at (boundary + stepSize)
    // This naturally avoids drawing ON the boundary itself
    // If we subtract 1, we lose one valid level that could fit in the range
    
    // Safety: Limit max levels to prevent performance issues
    const int MAX_FACTOR_LEVELS = 5000;
    if(totalLevels > MAX_FACTOR_LEVELS) {
        Print("DrawFactorLevelsAligned: WARNING - Too many levels (", totalLevels, 
              "), clamping to ", MAX_FACTOR_LEVELS);
        totalLevels = MAX_FACTOR_LEVELS;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("DrawFactorLevelsAligned: High=", highPrice, ", Low=", lowPrice, 
          ", Factor=", factor, ", StepSize=", stepSize, ", TotalLevels=", totalLevels,
          ", StartFrom=", (startFromHigh ? "HIGH" : "LOW"));
    #endif
    
    // Draw levels starting from nearest boundary
    double startPrice = startFromHigh ? highPrice : lowPrice;
    double direction = startFromHigh ? -1.0 : 1.0;  // -1 = downward, +1 = upward
    
    //                                                                
    // CLEANUP OLD ZONES
    //                         
    //                                                                
    if(inpShowMidZones) {
        ObjectsDeleteAll(0, objectPrefix + "Factor_Zone_", -1, -1);
    }
    
    int levelsDrawn = 0;
    int zoneCount = 0;  // Track zones drawn
    
    //                                                                
    // CALCULATE halfStep and zoneHeight ONCE (DRY principle)
    //                                    
    // Zone height = 25% of halfStep (12.5% above + 12.5% below midpoint)
    //                                                                
    double halfStep = stepSize / 2.0;
    double zoneHeight = halfStep * 0.25;  // 25% of halfStep (12.5% each side)
    
    //                                                                
    // MAIN LOOP: Draw levels and zones
    //          :                     
    //                                                                
    for(int i = 1; i <= totalLevels; i++) {
        // Calculate price for this level (aligned to boundary)
        double levelPrice = startPrice + (direction * stepSize * i);
        
        // Validate level is within range
        if(levelPrice < lowPrice || levelPrice > highPrice) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   Level ", i, " outside range: ", DoubleToString(levelPrice, Digits));
            #endif
            continue;  // Skip levels outside range
        }
        
        // Normalize price to symbol's digits
        double normalizedPrice = NormalizeDouble(levelPrice, Digits);
        
        //                                                            
        // DRAW MID-RANGE ZONE (BEFORE this level)
        //                  (              )
        // 
        // LOGIC: Draw zone between previous boundary/level and current level
        // - For i=1: Zone between start boundary and first level
        // - For i>1: Zone between previous level and current level
        //                                                            
        if(inpShowMidZones) {
            // Determine previous price (boundary for i=1, previous level for i>1)
            double prevPrice = (i == 1) ? startPrice : (startPrice + (direction * stepSize * (i-1)));
            prevPrice = NormalizeDouble(prevPrice, Digits);
            
            // Calculate midpoint between previous and current
            double midPoint = (normalizedPrice + prevPrice) / 2.0;
            
            // Calculate zone boundaries ( 12.5% of halfStep from midpoint)
            double zoneTop = midPoint + zoneHeight;
            double zoneBottom = midPoint - zoneHeight;
            
            // Normalize zone boundaries
            zoneTop = NormalizeDouble(zoneTop, Digits);
            zoneBottom = NormalizeDouble(zoneBottom, Digits);
            
            // Validate zone is within chart range
            if(zoneTop <= highPrice && zoneBottom >= lowPrice) {
                // Draw zone with style support
                string zoneName = objectPrefix + "Factor_Zone_" + IntegerToString(i);
                if(CreateFactorMidZone(zoneName, zoneTop, zoneBottom, 
                                      inpFactorLevelColor,  // Use Factor level color
                                      inpMidZoneStyle,  // Use unified zone style
                                      inpMidZoneTransparency)) {
                    zoneCount++;
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("  Zone ", i, ": Between ", DoubleToString(prevPrice, Digits),
                          " and ", DoubleToString(normalizedPrice, Digits),
                          " | Mid=", DoubleToString(midPoint, Digits),
                          " | Height=", DoubleToString(zoneHeight, Digits),
                          " | Style=", EnumToString(inpMidZoneStyle));
                    #endif
                }
            }
        }
        
        //                                                            
        // DRAW FACTOR LEVEL LINE
        //                  
        // 
        // CRITICAL: Factor lines controlled by Trigger Levels (INVERTED)
        //    :      Factor      Trigger Levels               (     )
        // Logic: Trigger OFF   Factor lines VISIBLE
        //        Trigger ON    Factor lines HIDDEN
        //     :                    Factor                   
        //                         Factor             
        //                                                            
        
        // Create level name
        string levelName = objectPrefix + "Factor_" + IntegerToString(i);
        
        // Check if Factor lines should be shown (INVERTED: show when Trigger is OFF)
        bool shouldShowLine = !IsTriggerLevelsEnabled();
        
        // Check if object exists
        bool objectExists = (ObjectFind(0, levelName) >= 0);
        
        if(shouldShowLine) {
            // Trigger ON: Create or update level
            if(!objectExists) {
                if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, normalizedPrice)) {
                    Print("DrawFactorLevelsAligned: Failed to create level ", i, ", Error: ", GetLastError());
                    continue;
                }
            }
            
            // Set level properties
            ObjectSetDouble(0, levelName, OBJPROP_PRICE, normalizedPrice);
            ObjectSetInteger(0, levelName, OBJPROP_COLOR, inpFactorLevelColor);
            ObjectSetInteger(0, levelName, OBJPROP_STYLE, inpFactorLevelStyle);
            ObjectSetInteger(0, levelName, OBJPROP_WIDTH, inpFactorLevelWidth);
            ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
            ObjectSetInteger(0, levelName, OBJPROP_ZORDER, 1);  // Draw above zones
            ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);  // Show on all timeframes
            
            // Set tooltip
            ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
                StringFormat("Factor Level %d | %s | F=%.2f", 
                    i, DoubleToString(normalizedPrice, Digits), factor));
            
            levelsDrawn++;
        } else {
            // Trigger OFF: Hide level if it exists
            if(objectExists) {
                ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);  // Hide on all timeframes
            }
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  DrawFactorLevelsAligned: Drew ", levelsDrawn, " levels and ", zoneCount, " zones");
    Print("   halfStep=", DoubleToString(halfStep, Digits), 
          ", zoneHeight=", DoubleToString(zoneHeight, Digits), " (25% of halfStep = 12.5% each side)");
    #endif
}

//+------------------------------------------------------------------+
//| Draw Harmonic Factor levels FROM CENTER (supports Custom Price) |
//|          Harmonic Factor         (            Custom Price)      |
//| Alternates between base and large steps from center              |
//+------------------------------------------------------------------+
#ifndef BUILD_LITE
//+------------------------------------------------------------------+
//| Draw Factor Harmonic levels FROM CENTER                         |
//| Alternates between base and large steps from center              |
//| GOLD VERSION: With safety checks and performance optimization    |
//+------------------------------------------------------------------+
void DrawFactorLevelsHarmonicFromCenter(const string objectPrefix, const double centerPrice,
                                        const double highPrice, const double lowPrice,
                                        const double factor, const double baseStepSize,
                                        const double harmonicRatio,
                                        const int maxLevelsAbove, const int maxLevelsBelow)
{
    //                                                                
    // PHASE 1: INPUT VALIDATION (Security Layer)
    //                                                                
    if(StringLen(objectPrefix) == 0 || centerPrice <= 0 || highPrice <= 0 || lowPrice <= 0) {
        Print("  DrawFactorLevelsHarmonicFromCenter: Invalid inputs");
        return;
    }
    if(highPrice <= lowPrice) {
        Print("  DrawFactorLevelsHarmonicFromCenter: Invalid range - High must be > Low");
        return;
    }
    if(baseStepSize <= 0 || harmonicRatio < MIN_HARMONIC_RATIO || harmonicRatio > MAX_HARMONIC_RATIO) {
        Print("  DrawFactorLevelsHarmonicFromCenter: Invalid step or ratio");
        return;
    }
    if(maxLevelsAbove < 1 || maxLevelsBelow < 1) {
        Print("  DrawFactorLevelsHarmonicFromCenter: Invalid level counts");
        return;
    }
    
    //                                                                
    // PHASE 2: SAFETY CHECKS (Performance Protection)
    //                                                                
    
    // Calculate historical range and viewport
    double historicalRange = highPrice - lowPrice;
    double currentPrice = iClose(_Symbol, _Period, 0);
    // INCREASED: From 3x to 10x to allow more levels on lower timeframes
    double viewportTop = currentPrice + (historicalRange * 10.0);
    double viewportBottom = currentPrice - (historicalRange * 10.0);
    
    // SAFETY: Limit levels if center is far from viewport
    int safeMaxAbove = maxLevelsAbove;
    int safeMaxBelow = maxLevelsBelow;
    
    if(centerPrice > viewportTop || centerPrice < viewportBottom) {
        safeMaxAbove = (int)MathMin(maxLevelsAbove, 100);
        safeMaxBelow = (int)MathMin(maxLevelsBelow, 100);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("   Harmonic: Center outside viewport - limiting to ", safeMaxAbove, "/", safeMaxBelow);
        #endif
    }
    
    // Calculate large step
    double largeStepSize = baseStepSize * harmonicRatio;
    
    // CRITICAL FIX: Calculate average step size for consistent zone height
    double avgStepSize = (baseStepSize + largeStepSize) / 2.0;
    
    //                                                                
    // CLEANUP OLD OBJECTS (including zones)
    //                     (     zone   )
    //                                                                
    ObjectsDeleteAll(0, objectPrefix + "Factor_Harmonic_", -1, -1);
    if(inpShowMidZones) {
        ObjectsDeleteAll(0, objectPrefix + "Factor_Harmonic_Zone_", -1, -1);
    }
    
    bool shouldShowLine = !IsTriggerLevelsEnabled();
    int levelsDrawn = 0;
    int zoneCount = 0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("DrawFactorLevelsHarmonicFromCenter: Center=", DoubleToString(centerPrice, Digits),
          ", BaseStep=", DoubleToString(baseStepSize, Digits),
          ", LargeStep=", DoubleToString(largeStepSize, Digits),
          ", MaxAbove=", maxLevelsAbove, ", MaxBelow=", maxLevelsBelow);
    #endif
    
    // Draw center level
    string centerName = objectPrefix + "Factor_Harmonic_Center";
    double normalizedCenter = NormalizeDouble(centerPrice, Digits);
    
    if(shouldShowLine && ObjectFind(0, centerName) < 0) {
        if(ObjectCreate(0, centerName, OBJ_HLINE, 0, 0, normalizedCenter)) {
            ObjectSetInteger(0, centerName, OBJPROP_COLOR, C'255,140,0');  // DarkOrange
            ObjectSetInteger(0, centerName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, centerName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, centerName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, centerName, OBJPROP_BACK, false);
            ObjectSetInteger(0, centerName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
            ObjectSetString(0, centerName, OBJPROP_TOOLTIP,
                StringFormat("Harmonic Center | %s | F=%.2f | R=%.3f",
                    DoubleToString(normalizedCenter, Digits), factor, harmonicRatio));
            levelsDrawn++;
        }
    }
    
    // Draw levels above center (alternating pattern, respects maxLevelsAbove)
    // UNIFIED LOGIC: Uses M Mode color logic with Harmonic pattern
    double cumulative = 0;
    int levelsAboveCount = 0;
    
    // OPTIMIZATION: Cache frequently called values BEFORE the loop
    // OPTIMIZATION: Cache frequently called values BEFORE the loop
    bool triggerEnabled = IsTriggerLevelsEnabled();
    bool structureEnabled = inpShowStructure;
    int baseMultiplier = GetValidatedBaseMultiplier();
    
    // Initialize zone tracking with validation (Gold Version)
    double lastStructurePriceAbove, lastTriggerPriceAbove, lastFallbackPriceAbove;
    if(!InitializeZoneTracking(normalizedCenter, lastStructurePriceAbove, 
                               lastTriggerPriceAbove, lastFallbackPriceAbove)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  DrawFactorLevelsHarmonicFromCenter: Failed to initialize zone tracking (Above)");
        #endif
        return;  // Abort if initialization failed
    }
    
    for(int i = 0; i < safeMaxAbove; i++) {
        double step = (i % 2 == 0) ? baseStepSize : largeStepSize;
        cumulative += step;
        double priceLevel = centerPrice + cumulative;
        
        int logicalStep = i + 1;  // Harmonic uses sequential steps
        
        // Check if this step should be drawn (matching M Mode logic)
        // Note: Harmonic pattern is special, but still respects Structure/Trigger
        if(structureEnabled || triggerEnabled) {
            if(!ShouldDrawStepOptimized(logicalStep, triggerEnabled, baseMultiplier)) {
                continue;  // Skip this step but don't break the pattern
            }
        } else {
            // Neither structure nor trigger enabled - draw every baseMultiplier-th step
            if(logicalStep % baseMultiplier != 0) {
                continue;
            }
        }
        
        double normalizedPrice = NormalizeDouble(priceLevel, Digits);
        bool isBase = (i % 2 == 0);
        
        // Get path for this level - check Structure first, then Trigger (matching M Mode)
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        
        if(GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
            // Got path from structure levels
        } else if(triggerEnabled) {
            // Use Trigger color (matching M Mode exactly)
            levelColor = inpTriggerColor;
            levelStyle = inpTriggerStyle;
            levelWidth = inpTriggerWidth;
        } else {
            // Fallback to Harmonic colors
            levelColor = isBase ? inpHarmonicBaseColor : inpHarmonicLargeColor;
            levelStyle = inpFactorLevelStyle;
            levelWidth = isBase ? inpHarmonicBaseWidth : inpHarmonicLargeWidth;
        }
        
        string levelName = objectPrefix + "Factor_Harmonic_Above_" + IntegerToString(logicalStep);
        
        if(shouldShowLine && ObjectFind(0, levelName) < 0) {
            if(ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, normalizedPrice)) {
                ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
                ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
                ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
                ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
                ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetString(0, levelName, OBJPROP_TOOLTIP,
                    StringFormat("Harmonic +%d (%s) | %s | F=%.2f",
                        logicalStep, (isBase ? "Base" : "Large"), DoubleToString(normalizedPrice, Digits), factor));
                levelsDrawn++;
                levelsAboveCount++;
            }
        }
        
        // Draw zone (matching M Mode logic with CreateZoneWithSmartFallback)
        if(inpShowMidZones) {
            // Check if current level is a structure level
            bool isCurrentStructure = false;
            if(structureEnabled) {
                int intervals[];
                GetCachedIntervals(baseMultiplier, intervals);
                
                for(int j = 0; j < 5; j++) {
                    if(intervals[j] > 0 && logicalStep % intervals[j] == 0) {
                        isCurrentStructure = true;
                        break;
                    }
                }
            }
            
            string zoneName = objectPrefix + "Factor_Harmonic_Zone_Above_" + IntegerToString(logicalStep);
            // CRITICAL FIX: Pass avgStepSize for consistent zone height
            if(CreateZoneWithSmartFallback(zoneName, normalizedPrice, isCurrentStructure, levelColor,
                                          structureEnabled, triggerEnabled,
                                          lastStructurePriceAbove, lastTriggerPriceAbove, lastFallbackPriceAbove,
                                          avgStepSize)) {  // Pass average step size
                zoneCount++;
            }
        }
    }
    
    // Draw levels below center (alternating pattern, respects maxLevelsBelow)
    // UNIFIED LOGIC: Uses M Mode color logic with Harmonic pattern
    cumulative = 0;
    int levelsBelowCount = 0;
    
    // Initialize zone tracking with validation (Gold Version)
    double lastStructurePriceBelow, lastTriggerPriceBelow, lastFallbackPriceBelow;
    if(!InitializeZoneTracking(normalizedCenter, lastStructurePriceBelow, 
                               lastTriggerPriceBelow, lastFallbackPriceBelow)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  DrawFactorLevelsHarmonicFromCenter: Failed to initialize zone tracking (Below)");
        #endif
        return;  // Abort if initialization failed
    }
    
    for(int i = 0; i < safeMaxBelow; i++) {
        double step = (i % 2 == 0) ? baseStepSize : largeStepSize;
        cumulative += step;
        double priceLevel = centerPrice - cumulative;
        
        int logicalStep = i + 1;  // Harmonic uses sequential steps
        
        // Check if this step should be drawn (matching M Mode logic)
        if(structureEnabled || triggerEnabled) {
            if(!ShouldDrawStepOptimized(logicalStep, triggerEnabled, baseMultiplier)) {
                continue;  // Skip this step but don't break the pattern
            }
        } else {
            // Neither structure nor trigger enabled - draw every baseMultiplier-th step
            if(logicalStep % baseMultiplier != 0) {
                continue;
            }
        }
        
        double normalizedPrice = NormalizeDouble(priceLevel, Digits);
        bool isBase = (i % 2 == 0);
        
        // Get path for this level - check Structure first, then Trigger (matching M Mode)
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        
        if(GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
            // Got path from structure levels
        } else if(triggerEnabled) {
            // Use Trigger color (matching M Mode exactly)
            levelColor = inpTriggerColor;
            levelStyle = inpTriggerStyle;
            levelWidth = inpTriggerWidth;
        } else {
            // Fallback to Harmonic colors
            levelColor = isBase ? inpHarmonicBaseColor : inpHarmonicLargeColor;
            levelStyle = inpFactorLevelStyle;
            levelWidth = isBase ? inpHarmonicBaseWidth : inpHarmonicLargeWidth;
        }
        
        string levelName = objectPrefix + "Factor_Harmonic_Below_" + IntegerToString(logicalStep);
        
        if(shouldShowLine && ObjectFind(0, levelName) < 0) {
            if(ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, normalizedPrice)) {
                ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
                ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
                ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
                ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
                ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetString(0, levelName, OBJPROP_TOOLTIP,
                    StringFormat("Harmonic -%d (%s) | %s | F=%.2f",
                        logicalStep, (isBase ? "Base" : "Large"), DoubleToString(normalizedPrice, Digits), factor));
                levelsDrawn++;
                levelsBelowCount++;
            }
        }
        
        // Draw zone (matching M Mode logic with CreateZoneWithSmartFallback)
        if(inpShowMidZones) {
            // Check if current level is a structure level
            bool isCurrentStructure = false;
            if(structureEnabled) {
                int intervals[];
                GetCachedIntervals(baseMultiplier, intervals);
                
                for(int j = 0; j < 5; j++) {
                    if(intervals[j] > 0 && logicalStep % intervals[j] == 0) {
                        isCurrentStructure = true;
                        break;
                    }
                }
            }
            
            string zoneName = objectPrefix + "Factor_Harmonic_Zone_Below_" + IntegerToString(logicalStep);
            // CRITICAL FIX: Pass avgStepSize for consistent zone height
            if(CreateZoneWithSmartFallback(zoneName, normalizedPrice, isCurrentStructure, levelColor,
                                          structureEnabled, triggerEnabled,
                                          lastStructurePriceBelow, lastTriggerPriceBelow, lastFallbackPriceBelow,
                                          avgStepSize)) {  // Pass average step size
                zoneCount++;
            }
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  DrawFactorLevelsHarmonicFromCenter: Drew ", levelsDrawn, " levels and ", zoneCount, " zones");
    Print("   Above=", levelsAboveCount, "/", maxLevelsAbove,
          ", Below=", levelsBelowCount, "/", maxLevelsBelow);
    #endif
}
#endif

//+------------------------------------------------------------------+
//| Draw Factor levels FROM CENTER (supports Custom Price)          |
//|          Factor         (            Custom Price)               |
//| Draws levels upward and downward from center point               |
//| Like other modes (TH, SS/LS, M, TP), respects Custom Price      |
//| GOLD VERSION: With safety checks and performance optimization    |
//+------------------------------------------------------------------+
void DrawFactorLevelsFromCenter(const string objectPrefix, const double centerPrice,
                                const double highPrice, const double lowPrice,
                                const double factor, const double stepSize,
                                const int maxLevelsAbove, const int maxLevelsBelow)
{
    //                                                                
    // PHASE 1: INPUT VALIDATION (Security Layer)
    //                                                                
    if(StringLen(objectPrefix) == 0) {
        Print("  DrawFactorLevelsFromCenter: Empty object prefix");
        return;
    }
    if(centerPrice <= 0 || highPrice <= 0 || lowPrice <= 0) {
        Print("  DrawFactorLevelsFromCenter: Invalid prices - Center=", centerPrice, 
              ", High=", highPrice, ", Low=", lowPrice);
        return;
    }
    if(highPrice <= lowPrice) {
        Print("  DrawFactorLevelsFromCenter: Invalid range - High must be > Low");
        return;
    }
    if(stepSize <= 0) {
        Print("  DrawFactorLevelsFromCenter: Invalid step size: ", stepSize);
        return;
    }
    if(maxLevelsAbove < 1 || maxLevelsBelow < 1) {
        Print("  DrawFactorLevelsFromCenter: Invalid level counts");
        return;
    }
    
    //                                                                
    // PHASE 2: SAFETY CHECKS (Performance Protection)
    //                                                                
    
    // Use user-defined level counts directly
    int safeMaxAbove = maxLevelsAbove;
    int safeMaxBelow = maxLevelsBelow;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("DrawFactorLevelsFromCenter: Center=", DoubleToString(centerPrice, Digits),
          ", High=", DoubleToString(highPrice, Digits), 
          ", Low=", DoubleToString(lowPrice, Digits),
          ", StepSize=", DoubleToString(stepSize, Digits),
          ", MaxAbove=", safeMaxAbove, ", MaxBelow=", safeMaxBelow);
    #endif
    
    // Cleanup old zones
    if(inpShowMidZones) {
        ObjectsDeleteAll(0, objectPrefix + "Factor_Zone_", -1, -1);
    }
    
    //                                                                
    // ZONE HEIGHT CALCULATION (Unified Formula)
    //               Zone (             )
    // Formula: zoneHeight = stepSize * 0.25 * 0.5 = stepSize * 0.125
    // This means: 25% of step, split equally ( 12.5% each side of midpoint)
    //                                                                
    const double ZONE_HEIGHT_PERCENT = 0.25;  // 25% of step
    double zoneHeight = stepSize * ZONE_HEIGHT_PERCENT * 0.5;  //  12.5% each side
    
    int levelsDrawn = 0;
    int zoneCount = 0;
    bool shouldShowLine = !IsTriggerLevelsEnabled();  // Cache trigger state
    
    //                                                                
    // DRAW CENTER LEVEL (step 0)
    //              
    //                                                                
    string centerLevelName = objectPrefix + "Factor_Center";
    double normalizedCenter = NormalizeDouble(centerPrice, Digits);
    
    if(shouldShowLine) {
        if(ObjectFind(0, centerLevelName) < 0) {
            if(ObjectCreate(0, centerLevelName, OBJ_HLINE, 0, 0, normalizedCenter)) {
                ObjectSetInteger(0, centerLevelName, OBJPROP_COLOR, inpFactorLevelColor);
                ObjectSetInteger(0, centerLevelName, OBJPROP_STYLE, inpFactorLevelStyle);
                ObjectSetInteger(0, centerLevelName, OBJPROP_WIDTH, inpFactorLevelWidth);
                ObjectSetInteger(0, centerLevelName, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, centerLevelName, OBJPROP_BACK, false);
                ObjectSetInteger(0, centerLevelName, OBJPROP_ZORDER, 1);
                ObjectSetInteger(0, centerLevelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetString(0, centerLevelName, OBJPROP_TOOLTIP, 
                    StringFormat("Factor Center | %s | F=%.2f", 
                        DoubleToString(normalizedCenter, Digits), factor));
                levelsDrawn++;
            }
        }
    } else {
        if(ObjectFind(0, centerLevelName) >= 0) {
            ObjectSetInteger(0, centerLevelName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        }
    }
    
    //                                                                
    // DRAW LEVELS ABOVE CENTER (respects maxLevelsAbove)
    //                     (             maxLevelsAbove)
    // UNIFIED LOGIC: Matches M Mode exactly
    //                                                                
    
    // OPTIMIZATION: Cache frequently called values BEFORE the loop
    bool triggerEnabled = IsTriggerLevelsEnabled();
    bool structureEnabled = inpShowStructure;
    int baseMultiplier = GetValidatedBaseMultiplier();
    
    // Initialize zone tracking with validation (Gold Version)
    double lastStructurePriceAbove, lastTriggerPriceAbove, lastFallbackPriceAbove;
    if(!InitializeZoneTracking(normalizedCenter, lastStructurePriceAbove, 
                               lastTriggerPriceAbove, lastFallbackPriceAbove)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  DrawFactorLevelsFromCenter: Failed to initialize zone tracking (Above)");
        #endif
        return;  // Abort if initialization failed
    }
    
    int logicalStep = 1;
    int levelsAboveCount = 0;
    double prevPrice = normalizedCenter;
    
    // SAFETY: Use already calculated viewport boundaries (defined above)
    // currentPrice, historicalRange, viewportTop already declared
    
    // SECURITY FIX: Add iteration limit to prevent infinite loops
    int maxIterations = safeMaxAbove * 2;  // Safety margin
    int iterations = 0;
    
    while(levelsAboveCount < safeMaxAbove && iterations < maxIterations) {
        iterations++;
        double levelPrice = centerPrice + (stepSize * logicalStep);
        
        // Check if this step should be drawn (matching M Mode logic)
        if(structureEnabled || triggerEnabled) {
            if(!ShouldDrawStepOptimized(logicalStep, triggerEnabled, baseMultiplier)) {
                logicalStep++;
                continue;
            }
        } else {
            // Neither structure nor trigger enabled - draw every baseMultiplier-th step
            if(logicalStep % baseMultiplier != 0) {
                logicalStep++;
                continue;
            }
        }
        
        double normalizedPrice = NormalizeDouble(levelPrice, Digits);
        
        // Get path for this level - check Structure first, then Trigger (matching M Mode)
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        
        if(GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
            // Got path from structure levels
        } else if(triggerEnabled) {
            // Use Trigger color (matching M Mode exactly)
            levelColor = inpTriggerColor;
            levelStyle = inpTriggerStyle;
            levelWidth = inpTriggerWidth;
        } else {
            // Fallback to Factor color
            levelColor = inpFactorLevelColor;
            levelStyle = inpFactorLevelStyle;
            levelWidth = inpFactorLevelWidth;
        }
        
        // Draw zone between previous and current (matching M Mode logic)
        if(inpShowMidZones) {
            // Check if current level is a structure level
            bool isCurrentStructure = false;
            if(structureEnabled) {
                int intervals[];
                GetCachedIntervals(baseMultiplier, intervals);
                
                for(int j = 0; j < 5; j++) {
                    if(intervals[j] > 0 && logicalStep % intervals[j] == 0) {
                        isCurrentStructure = true;
                        break;
                    }
                }
            }
            
            string zoneName = objectPrefix + "Factor_Zone_Above_" + IntegerToString(logicalStep);
            // CRITICAL FIX: Pass stepSize for consistent zone height
            if(CreateZoneWithSmartFallback(zoneName, normalizedPrice, isCurrentStructure, levelColor,
                                          structureEnabled, triggerEnabled,
                                          lastStructurePriceAbove, lastTriggerPriceAbove, lastFallbackPriceAbove,
                                          stepSize)) {  // Pass fixed step size
                zoneCount++;
            }
        }
        
        // Draw level
        string levelName = objectPrefix + "Factor_Above_" + IntegerToString(logicalStep);
        if(shouldShowLine) {
            if(ObjectFind(0, levelName) < 0) {
                if(ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, normalizedPrice)) {
                    ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
                    ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
                    ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
                    ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
                    ObjectSetInteger(0, levelName, OBJPROP_ZORDER, 1);
                    ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                    ObjectSetString(0, levelName, OBJPROP_TOOLTIP,
                        StringFormat("Factor +%d | %s | F=%.2f",
                            logicalStep, DoubleToString(normalizedPrice, Digits), factor));
                    levelsDrawn++;
                }
            }
        } else {
            if(ObjectFind(0, levelName) >= 0) {
                ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            }
        }
        
        prevPrice = normalizedPrice;
        logicalStep++;
        levelsAboveCount++;
    }
    
    //                                                                
    //                                                                
    // DRAW LEVELS BELOW CENTER (respects maxLevelsBelow)
    //                     (             maxLevelsBelow)
    // UNIFIED LOGIC: Matches M Mode exactly
    //                                                                
    
    // Initialize zone tracking with validation (Gold Version)
    double lastStructurePriceBelow, lastTriggerPriceBelow, lastFallbackPriceBelow;
    if(!InitializeZoneTracking(normalizedCenter, lastStructurePriceBelow, 
                               lastTriggerPriceBelow, lastFallbackPriceBelow)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  DrawFactorLevelsFromCenter: Failed to initialize zone tracking (Below)");
        #endif
        return;  // Abort if initialization failed
    }
    
    logicalStep = 1;
    int levelsBelowCount = 0;
    prevPrice = normalizedCenter;
    
    // SAFETY: Use already calculated viewport boundary (viewportBottom defined above)
    
    // SECURITY FIX: Add iteration limit to prevent infinite loops
    maxIterations = safeMaxBelow * 2;  // Safety margin
    iterations = 0;
    
    while(levelsBelowCount < safeMaxBelow && iterations < maxIterations) {
        iterations++;
        double levelPrice = centerPrice - (stepSize * logicalStep);
        
        // Check if this step should be drawn (matching M Mode logic)
        if(structureEnabled || triggerEnabled) {
            if(!ShouldDrawStepOptimized(logicalStep, triggerEnabled, baseMultiplier)) {
                logicalStep++;
                continue;
            }
        } else {
            // Neither structure nor trigger enabled - draw every baseMultiplier-th step
            if(logicalStep % baseMultiplier != 0) {
                logicalStep++;
                continue;
            }
        }
        
        double normalizedPrice = NormalizeDouble(levelPrice, Digits);
        
        // Get path for this level - check Structure first, then Trigger (matching M Mode)
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        
        if(GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
            // Got path from structure levels
        } else if(triggerEnabled) {
            // Use Trigger color (matching M Mode exactly)
            levelColor = inpTriggerColor;
            levelStyle = inpTriggerStyle;
            levelWidth = inpTriggerWidth;
        } else {
            // Fallback to Factor color
            levelColor = inpFactorLevelColor;
            levelStyle = inpFactorLevelStyle;
            levelWidth = inpFactorLevelWidth;
        }
        
        // Draw zone between previous and current (matching M Mode logic)
        if(inpShowMidZones) {
            // Check if current level is a structure level
            bool isCurrentStructure = false;
            if(structureEnabled) {
                int intervals[];
                GetCachedIntervals(baseMultiplier, intervals);
                
                for(int j = 0; j < 5; j++) {
                    if(intervals[j] > 0 && logicalStep % intervals[j] == 0) {
                        isCurrentStructure = true;
                        break;
                    }
                }
            }
            
            string zoneName = objectPrefix + "Factor_Zone_Below_" + IntegerToString(logicalStep);
            // CRITICAL FIX: Pass stepSize for consistent zone height
            if(CreateZoneWithSmartFallback(zoneName, normalizedPrice, isCurrentStructure, levelColor,
                                          structureEnabled, triggerEnabled,
                                          lastStructurePriceBelow, lastTriggerPriceBelow, lastFallbackPriceBelow,
                                          stepSize)) {  // Pass fixed step size
                zoneCount++;
            }
        }
        
        // Draw level
        string levelName = objectPrefix + "Factor_Below_" + IntegerToString(logicalStep);
        if(shouldShowLine) {
            if(ObjectFind(0, levelName) < 0) {
                if(ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, normalizedPrice)) {
                    ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
                    ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
                    ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
                    ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
                    ObjectSetInteger(0, levelName, OBJPROP_ZORDER, 1);
                    ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                    ObjectSetString(0, levelName, OBJPROP_TOOLTIP,
                        StringFormat("Factor -%d | %s | F=%.2f",
                            logicalStep, DoubleToString(normalizedPrice, Digits), factor));
                    levelsDrawn++;
                }
            }
        } else {
            if(ObjectFind(0, levelName) >= 0) {
                ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            }
        }
        
        prevPrice = normalizedPrice;
        logicalStep++;
        levelsBelowCount++;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  DrawFactorLevelsFromCenter: Drew ", levelsDrawn, " levels and ", zoneCount, " zones");
    Print("   Center=", DoubleToString(normalizedCenter, Digits),
          ", Above=", levelsAboveCount, "/", maxLevelsAbove, 
          ", Below=", levelsBelowCount, "/", maxLevelsBelow);
    #endif
}

//+------------------------------------------------------------------+
//| DEPRECATED: Use DrawFactorLevelsAligned instead                 |
//| Draw Factor levels between Historical High and Low               |
//|                     High   Low                                   |
//| Divides the range into (Factor * 2) equal parts                   |
//| NOTE: This function is kept for backward compatibility only      |
//+------------------------------------------------------------------+

// Track last drawn level count for cleanup
static int s_lastFactorLevelCount = 0;

void DrawFactorLevels(const string objectPrefix, const double highPrice, 
                      const double lowPrice, const double factor)
{
    // Comprehensive input validation
    if(StringLen(objectPrefix) == 0) {
        Print("DrawFactorLevels: Empty object prefix");
        return;
    }
    if(highPrice <= 0 || lowPrice <= 0) {
        Print("DrawFactorLevels: Invalid prices - High=", highPrice, ", Low=", lowPrice);
        return;
    }
    if(highPrice <= lowPrice) {
        Print("DrawFactorLevels: Invalid range - High (", highPrice, ") must be greater than Low (", lowPrice, ")");
        return;
    }
    // Support 2 decimal places: minimum 0.01, maximum 10000
    if(factor < 0.01 || factor > 10000) {
        Print("DrawFactorLevels: Invalid factor (", DoubleToString(factor, 2), ") - must be 0.01-10000");
        return;
    }
    
    // Calculate step size
    double stepSize = CalculateFactorStepSize(highPrice, lowPrice, factor);
    if(stepSize <= 0) {
        Print("DrawFactorLevels: Invalid step size calculated");
        return;
    }
    
    // IMPROVED: Calculate exact number of levels that fit in the range
    // Instead of using Factor   2 - 1, we calculate how many complete steps fit
    double range = highPrice - lowPrice;
    int totalLevels = (int)MathFloor(range / stepSize) - 1;  // -1 to exclude boundaries
    
    if(totalLevels <= 0) {
        Print("DrawFactorLevels: No levels to draw (totalLevels=", totalLevels, 
              ", factor=", DoubleToString(factor, 2), ", stepSize=", stepSize, ")");
        return;
    }
    
    // Note: This ensures all levels are equally spaced
    // The last level might not reach exactly to High, but all steps are equal
    
    // CRITICAL: Prevent object overflow (MT4 limit ~64K objects)
    // Maximum safe levels per indicator: 5000 (leaves room for other objects)
    const int MAX_FACTOR_LEVELS = 5000;
    if(totalLevels > MAX_FACTOR_LEVELS) {
        Print("DrawFactorLevels: WARNING - Too many levels (", totalLevels, 
              "), clamping to ", MAX_FACTOR_LEVELS, " for safety");
        totalLevels = MAX_FACTOR_LEVELS;
    }
    
    // Get Point value safely for tooltip
    // Calculate pip size based on Digits (works for ALL symbols)
    // Calculate pip size correctly for all asset types
    // Uses centralized GetCachedPipSize() for proper Gold/JPY/Forex handling
    double pipSize = GetCachedPipSize();
    
    // Calculate range in pips (using correct pip size)
    double rangePips = (highPrice - lowPrice) / pipSize;
    double stepPips = stepSize / pipSize;
    
    // CLEANUP: Delete stale objects if level count decreased
    if(s_lastFactorLevelCount > totalLevels) {
        for(int i = totalLevels + 1; i <= s_lastFactorLevelCount; i++) {
            string staleName = objectPrefix + "Factor_" + IntegerToString(i);
            if(ObjectFind(0, staleName) >= 0) {
                ObjectDelete(0, staleName);
            }
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("DrawFactorLevels: High=", highPrice, ", Low=", lowPrice, ", Factor=", factor,
          ", StepSize=", stepSize, ", TotalLevels=", totalLevels);
    #endif
    
    // ========== Draw Historical HIGH line ==========
    string highLineName = objectPrefix + "Factor_High";
    if(ObjectFind(0, highLineName) < 0) {
        ObjectCreate(0, highLineName, OBJ_HLINE, 0, 0, highPrice);
    }
    ObjectSetDouble(0, highLineName, OBJPROP_PRICE, highPrice);
    ObjectSetInteger(0, highLineName, OBJPROP_COLOR, inpHighColor);
    ObjectSetInteger(0, highLineName, OBJPROP_STYLE, inpHighStyle);
    ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, inpHighWidth);
    ObjectSetInteger(0, highLineName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, highLineName, OBJPROP_SELECTED, false);
    ObjectSetString(0, highLineName, OBJPROP_TOOLTIP, 
        StringFormat("Historical HIGH | %s | Range: %.0f pips", 
            DoubleToString(highPrice, Digits), rangePips));
    
    // ========== Draw Historical LOW line ==========
    string lowLineName = objectPrefix + "Factor_Low";
    if(ObjectFind(0, lowLineName) < 0) {
        ObjectCreate(0, lowLineName, OBJ_HLINE, 0, 0, lowPrice);
    }
    ObjectSetDouble(0, lowLineName, OBJPROP_PRICE, lowPrice);
    ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, inpLowColor);
    ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, inpLowStyle);
    ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, inpLowWidth);
    ObjectSetInteger(0, lowLineName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, lowLineName, OBJPROP_SELECTED, false);
    ObjectSetString(0, lowLineName, OBJPROP_TOOLTIP, 
        StringFormat("Historical LOW | %s | Range: %.0f pips", 
            DoubleToString(lowPrice, Digits), rangePips));
    
    // ========== Draw HIGH label ==========
    string highLabelName = objectPrefix + "Factor_High_Label";
    datetime _lblTime2 = CacheGetFrameTime();
    if(ObjectFind(0, highLabelName) < 0) {
        ObjectCreate(0, highLabelName, OBJ_TEXT, 0, _lblTime2, highPrice);
    }
    ObjectSetDouble(0, highLabelName, OBJPROP_PRICE, highPrice);
    ObjectSetInteger(0, highLabelName, OBJPROP_TIME, _lblTime2);
    ObjectSetInteger(0, highLabelName, OBJPROP_COLOR, inpHighColor);
    ObjectSetInteger(0, highLabelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, highLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
    ObjectSetString(0, highLabelName, OBJPROP_FONT, "Arial");
    ObjectSetString(0, highLabelName, OBJPROP_TEXT,
        StringFormat("  HIGH %s | Range: %.0f pips | F=%.2f | Step: %.1f pips",
            DoubleToString(highPrice, Digits), rangePips, factor, stepPips));
    ObjectSetInteger(0, highLabelName, OBJPROP_SELECTABLE, false);
    
    // ========== Draw LOW label ==========
    string lowLabelName = objectPrefix + "Factor_Low_Label";
    if(ObjectFind(0, lowLabelName) < 0) {
        ObjectCreate(0, lowLabelName, OBJ_TEXT, 0, _lblTime2, lowPrice);
    }
    ObjectSetDouble(0, lowLabelName, OBJPROP_PRICE, lowPrice);
    ObjectSetInteger(0, lowLabelName, OBJPROP_TIME, _lblTime2);
    ObjectSetInteger(0, lowLabelName, OBJPROP_COLOR, inpLowColor);
    ObjectSetInteger(0, lowLabelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, lowLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetString(0, lowLabelName, OBJPROP_FONT, "Arial");
    ObjectSetString(0, lowLabelName, OBJPROP_TEXT, 
        StringFormat("  LOW %s | Range: %.0f pips | F=%.2f | Step: %.1f pips", 
            DoubleToString(lowPrice, Digits), rangePips, factor, stepPips));
    ObjectSetInteger(0, lowLabelName, OBJPROP_SELECTABLE, false);
    
    // Draw levels from nearest boundary (High or Low) towards the other
    // FIX: Start from whichever is closer to current price
    double currentPrice = Bid;
    double distanceToHigh = MathAbs(currentPrice - highPrice);
    double distanceToLow = MathAbs(currentPrice - lowPrice);
    
    // Determine starting point and direction
    bool startFromLow = (distanceToLow <= distanceToHigh);
    double startPrice = startFromLow ? lowPrice : highPrice;
    double endPrice = startFromLow ? highPrice : lowPrice;
    int direction = startFromLow ? 1 : -1;  // 1 = up, -1 = down
    
    // FIX: Use multiplication instead of accumulation to avoid floating point errors
    int levelNumber = 0;  // Start from 0 so first level is at startPrice + stepSize
    // FIX: Better bound calculation - use small epsilon relative to step size
    double epsilon = stepSize * 0.001;  // 0.1% of step size
    
    // SECURITY FIX: Add iteration limit to prevent infinite loops
    int maxIterations = totalLevels * 2;  // Safety margin
    int iterations = 0;
    
    while(levelNumber < totalLevels && iterations < maxIterations) {
        iterations++;
        levelNumber++;  // Increment first so we start from 1
        
        // FIX: Calculate price using multiplication (more accurate than accumulation)
        // This prevents floating point error accumulation
        double levelPrice = startPrice + (stepSize * levelNumber * direction);
        
        // Check bounds with proper tolerance
        if(startFromLow) {
            // Going up: check if we exceeded high
            if(levelPrice >= (highPrice - epsilon)) break;
        } else {
            // Going down: check if we went below low
            if(levelPrice <= (lowPrice + epsilon)) break;
        }
        
        string levelName = objectPrefix + "Factor_" + IntegerToString(levelNumber);
        
        // Normalize price for consistency
        double normalizedPrice = NormalizeDouble(levelPrice, Digits);
        
        // Create or update level
        bool objectExists = (ObjectFind(0, levelName) >= 0);
        
        if(!objectExists) {
            if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, normalizedPrice)) {
                Print("DrawFactorLevels: Failed to create level ", levelNumber, ", Error: ", GetLastError());
                levelNumber++;
                continue;
            }
            
            // Set properties only for new objects
            color levelColor = (g_factorColorOverride >= 0) ? (color)g_factorColorOverride : inpFactorLevelColor;
            ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
            ObjectSetInteger(0, levelName, OBJPROP_STYLE, inpFactorLevelStyle);
            ObjectSetInteger(0, levelName, OBJPROP_WIDTH, inpFactorLevelWidth);
            ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
            ObjectSetInteger(0, levelName, OBJPROP_HIDDEN, false);
        } else {
            // OPTIMIZATION: Only update price if it changed significantly
            double oldPrice = ObjectGetDouble(0, levelName, OBJPROP_PRICE);
            if(MathAbs(oldPrice - normalizedPrice) > Point * 0.1) {
                ObjectSetDouble(0, levelName, OBJPROP_PRICE, normalizedPrice);
            }
        }
        
        // Tooltip always updated (lightweight operation)
        string tooltip = StringFormat("Factor %d/%d | Price: %s | Step: %.1f pips", 
            levelNumber, totalLevels, 
            DoubleToString(normalizedPrice, Digits),
            stepPips);
        ObjectSetString(0, levelName, OBJPROP_TOOLTIP, tooltip);
        
        levelNumber++;
    }
    
    // Update last level count for next cleanup
    s_lastFactorLevelCount = levelNumber - 1;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("DrawFactorLevels: Drew ", s_lastFactorLevelCount, " levels");
    #endif
}

//+------------------------------------------------------------------+
//| Clear all Factor level objects                                    |
//|                                                                   |
//+------------------------------------------------------------------+
void ClearFactorLevels(const string objectPrefix)
{
    // PERF: single bulk-delete call replaces manual loop + individual deletes
    string factorPrefix = objectPrefix + "Factor_";
    ObjectsDeleteAll(0, factorPrefix);
    // Invalidate any object cache entries that matched
    CacheClear();
}

//+------------------------------------------------------------------+
//| Ensure intervals cache is populated (no array copy needed)       |
//| Thin wrapper over GetCachedIntervals' internal cache logic       |
//+------------------------------------------------------------------+
void EnsureIntervalsCache(const int baseMultiplier) {
    int validatedMultiplier = baseMultiplier;
    if(validatedMultiplier < 2 || validatedMultiplier > 9)
        validatedMultiplier = 3;
    if(g_cachedBaseMultiplier != validatedMultiplier) {
        for(int i = 0; i < 5; i++)
            g_cachedIntervals[i] = CalculateStructureInterval(validatedMultiplier, i + 1);
        g_cachedBaseMultiplier = validatedMultiplier;
    }
}

#endif // EXTENDED_DRAWING_FUNCTIONS_MQH


