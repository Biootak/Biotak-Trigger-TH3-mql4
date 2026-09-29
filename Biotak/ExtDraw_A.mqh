// ExtDraw_A.mqh - ExtendedDrawingFunctions.mqh split 2026-09-29: exact lines 6-1381, byte-identical, zero renames.
#ifndef EXT_DRAW_A_MQH
#define EXT_DRAW_A_MQH


#property copyright "  Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link "@biotak"
#property strict

#include "Logger.mqh"
#include "TimeframeFunctions.mqh"
#include "MathConstants.mqh"
// Zone settings come from ZoneConfig.mqh (single owner); the legacy zone
// engines (UnifiedZoneSystem/ZoneTrackingHelpers/DrawingPipeline) were
// removed 2026-09-07 (dead, never included in any build).

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

// P-PERF-04: viewport cull geometry. MARGIN must be > HYSTERESIS (see below).
#define P_P4_VP_MARGIN_PCT     0.25
#define P_P4_VP_HYSTERESIS_PCT 0.20
#define P_P4_FALLBACK_RANGE_PCT 0.02   // +-2% around price when no range is known
#define P_P4_MIN_ZONE_PX        2      // thinner than this, a zone fill is noise

void GetViewportBounds(double &vpTop, double &vpBottom) {
    static double s_vpTop = 0;
    static double s_vpBottom = 0;
    static double s_lastChartMax = 0;
    static double s_lastChartMin = 0;

    double vpChartMax = ChartGetDouble(0, CHART_PRICE_MAX);
    double vpChartMin = ChartGetDouble(0, CHART_PRICE_MIN);
    double point = GetCachedPoint();

    if(vpChartMax > 0 && vpChartMin > 0 && vpChartMax > vpChartMin) {
        double visibleRange = vpChartMax - vpChartMin;

        // P-PERF-04 HYSTERESIS: the cull window is what the level render's
        // geometry signature is built from, so recomputing it for a 1-point
        // price nudge made EVERY pan pixel a full ~300-level re-render (the
        // "lag while working with the chart" complaint). Only re-derive once
        // the visible window has really moved or resized.
        double hysteresis = visibleRange * P_P4_VP_HYSTERESIS_PCT;
        if(hysteresis < point * 10.0) hysteresis = point * 10.0;
        if(s_vpTop > 0 &&
           MathAbs(vpChartMax - s_lastChartMax) <= hysteresis &&
           MathAbs(vpChartMin - s_lastChartMin) <= hysteresis) {
            vpTop = s_vpTop;
            vpBottom = s_vpBottom;
            return;
        }

        // P-PERF-04 MARGIN: the margin MUST cover the hysteresis band or a pan
        // that never triggered a recompute could push a level off the cache and
        // leave a visible level undrawn. 25% margin vs 20% hysteresis keeps a
        // 5% (tens of pixels) safety band, and still culls far more than the
        // old +-50% margin did — and every culled level is a level line, a
        // label and a full-width zone box that no longer has to be repainted.
        double vpMargin = visibleRange * P_P4_VP_MARGIN_PCT;
        vpTop = vpChartMax + vpMargin;
        vpBottom = vpChartMin - vpMargin;
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

    // P-PERF-04 OBJECT-EXPLOSION GUARD. This branch means the chart could not
    // report a visible price range at all — startup, a minimized window, or the
    // first frame right after a timeframe switch, exactly when the namespace was
    // just wiped and the next render repopulates it. Falling back to the FULL
    // historical range here marks EVERY level "inViewport", so the pipeline
    // created the entire level set (lines + pip labels + full-width zone boxes,
    // hundreds of objects) in one frame — and nothing ever removed the ones that
    // then sat off-screen forever, because culling only HIDES. Every later
    // repaint then walked that population. Bound the window instead: only levels
    // near the current price can be drawn, and the real range takes over on the
    // next frame.
    double fallbackRange = MathMax(anchor * P_P4_FALLBACK_RANGE_PCT, point * 1000.0);

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
//| @param zoneStyle Style (Filled/Empty/Outlined - P-UI-62: the    |
//|                  "Hidden" slot is retired, visibility is the    |
//|                  MID ZONES master switch's question)             |
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
    
    // P-UI-62: there is no HIDDEN style any more. "Are zones drawn at all?" is the MID
    // ZONES master switch's question (the zone family mask), and a second owner for it
    // is the defect this cycle removes - see ENUM_ZONE_STYLE. Slot 2 is OUTLINED.
    
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
    SZoneCreationRequest request = ZoneRequestNew();   // P-UI-131h
    request.name = zoneName;
    request.topPrice = upperPrice;
    request.bottomPrice = lowerPrice;
    request.zoneColor = zoneColor;
    request.transparency = transparency;
    // P-UI-63: the edge fades on its own - the Factor bands answer to the same two rows
    // the mid zones do (the card is titled "MID ZONES", the bands are the same family).
    request.borderTransparency = inpMidZoneBorderTransparency;
    // P-UI-131h: the Factor bands answer to the same two half-surfaces the mid zones do.
    request.borderTopColor = inpZoneEdgeTopColor;
    request.borderBottomColor = inpZoneEdgeBottomColor;
    request.borderTopTransparency = inpZoneEdgeTopTransparency;
    request.borderBottomTransparency = inpZoneEdgeBottomTransparency;
    // P-UI-62: the band and its edge are independent halves of the picture.
    request.filled  = (zoneStyle != FACTOR_ZONE_BOX_EMPTY);
    request.outline = (zoneStyle != FACTOR_ZONE_BOX_FILLED);
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
    
    // NOTE: multipliers come from the single table in ConstantsAndEnums.mqh
    // (GetFactorBasisMultiplier) - same numbers the adapted FactorMode path
    // uses. This raw path keeps its own pipeline (no adaptation) on purpose.
    switch(basis) {
        case FACTOR_BASIS_CONTROL:
            // Control = (SS + LS) / 2 = TH x 1.75
            stepSize = GetStepSizeForBasisType(basePrice, GetFactorBasisMultiplier(FACTOR_BASIS_CONTROL), PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_SS:
            // Short Step = TH x 1.5
            stepSize = GetStepSizeForBasisType(basePrice, GetFactorBasisMultiplier(FACTOR_BASIS_SS), PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_LS:
            // Long Step = TH x 2.0
            stepSize = GetStepSizeForBasisType(basePrice, GetFactorBasisMultiplier(FACTOR_BASIS_LS), PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_TH:
            // Pure TH = TH x 1.0
            stepSize = GetStepSizeForBasisType(basePrice, GetFactorBasisMultiplier(FACTOR_BASIS_TH), PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_TRIGGER:
            // Trigger TH (current timeframe) - same as TH
            stepSize = GetStepSizeForBasisType(basePrice, GetFactorBasisMultiplier(FACTOR_BASIS_TRIGGER), PERIOD_CURRENT);
            break;
            
        case FACTOR_BASIS_PATTERN:
            // Pattern TH (4x timeframe) - own TF, no table entry (x1.0)
            stepSize = GetStepSizeForBasisType(basePrice, 1.0, GetPatternTimeframe());
            break;
            
        case FACTOR_BASIS_STRUCTURE:
            // Structure TH (16x timeframe) - own TF, no table entry (x1.0)
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
            // Fallback to Control (x1.75) - legacy behavior preserved
            stepSize = GetStepSizeForBasisType(basePrice, GetFactorBasisMultiplier(FACTOR_BASIS_CONTROL), PERIOD_CURRENT);
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
        return CompatTF(Period());  // GOLD FIX: Use Period() instead of PERIOD_CURRENT (0)
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
            result = CompatTF(Period());
            break;

        case COMBO_TF_STRUCTURE:
            // User Request: Structure = 1 Fractal Higher (Current * 4)
            result = GetPatternTimeframe();
            break;

        default:
            #ifdef ENABLE_DEBUG_LOGS
            Print("   GetTimeframeByType: Unexpected tfType=", tfType, ", using current period");
            #endif
            result = CompatTF(Period());
            break;
    }
    
    // SAFETY: Validate result
    if(result <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetTimeframeByType: Invalid result=", result, " for tfType=", tfType);
        #endif
        return CompatTF(Period());  // GOLD FIX: Use Period() instead of PERIOD_CURRENT (0)
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

#endif // EXT_DRAW_A_MQH
