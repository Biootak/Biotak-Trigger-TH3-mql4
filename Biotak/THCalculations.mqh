//+------------------------------------------------------------------+
//|                                           THCalculations.mqh     |
//+------------------------------------------------------------------+
#property copyright "© Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link      "@biotak"
#property strict

// Include centralized math constants
#include "MathConstants.mqh"
// Include calculation cache for performance optimization
#include "CalculationCache.mqh"

//+------------------------------------------------------------------+
//| DEPRECATED: These functions are kept for backward compatibility  |
//| Use simple multipliers instead:                                  |
//| - Short Step (SS) = structureTH * 1.5                           |
//| - Long Step (LS) = structureTH * 2.0                            |
//|                                                                  |
//| Note: When Pattern = 0.5 * Structure, the structural formulas   |
//| simplify to the same result as simple multipliers:              |
//| - SS = (2*S) - P = (2*S) - (0.5*S) = 1.5*S                     |
//| - LS = (3*S) - (2*P) = (3*S) - (2*0.5*S) = 2.0*S              |
//+------------------------------------------------------------------+

// Deprecated functions removed - use simple multipliers instead:
// - Short Step (SS) = structureTH * 1.5
// - Long Step (LS) = structureTH * 2.0

// GOLD FIX #3: Enhanced epsilon-based validation with proper floating-point comparison
// Note: EPSILON constants are defined in FloatingPointHelper.mqh
#ifndef MAX_SAFE_PRICE
#define MAX_SAFE_PRICE 1000000.0
#endif
#ifndef MAX_SAFE_PERCENTAGE
#define MAX_SAFE_PERCENTAGE 1000.0
#endif

double CalculateTH(const double price, const int digits, const double percentage) {
    // Use epsilon for floating-point comparison
    if(price < EPSILON_PRICE || percentage < EPSILON_PERCENTAGE) {
        Print("❌ CalculateTH: Invalid input - price=", DoubleToString(price, 10),
              ", percentage=", DoubleToString(percentage, 10));
        return 0;
    }
    
    // SECURITY: Prevent overflow with proper bounds
    if(price > MAX_SAFE_PRICE) {
        Print("❌ CalculateTH: Price too large (", DoubleToString(price, 5), "), exceeds MAX_SAFE_PRICE");
        return 0;
    }
    
    // VALIDATION: Digits range check
    if(digits < 0 || digits > 8) {
        Print("❌ CalculateTH: Invalid digits (", digits, "), must be 0-8");
        return 0;
    }
    
    // VALIDATION: Percentage range with hard limit
    if(percentage > MAX_SAFE_PERCENTAGE) {
        Print("❌ CalculateTH: Percentage too large (", DoubleToString(percentage, 3),
              "%), exceeds MAX_SAFE_PERCENTAGE");
        return 0;
    }
    
    // OPTIMIZATION: Check calculation cache before performing arithmetic
    double cachedResult = GetCachedTHCalculation(price, percentage, digits);
    if(cachedResult > 0) {
        return cachedResult;
    }
    
    // Normalize values for calculation
    double normalizedPrice = NormalizeDouble(price, digits);
    double normalizedPercentage = NormalizeDouble(percentage, 6);
    
    // Formula matching MotiveWave EXACTLY:
    // thStepPriceUnits = (basePrice * percentage) / 100.0
    double result = (normalizedPrice * normalizedPercentage) / 100.0;
    
    // Store result in cache for future use
    StoreTHCalculation(price, percentage, digits, result);
    return result;
}

double CalculateTHPoints(const double price, const int digits, const double percentage) {
    if(price <= 0 || percentage <= 0) return 0;
    
    // Use IsZero for float comparison instead of == 0.0
    static double s_pointValue = 0.0;
    if(IsZero(s_pointValue, EPSILON_PRICE)) s_pointValue = GetCachedPoint();
    if(IsZero(s_pointValue, EPSILON_PRICE)) return 0;
    
    // محاسبه با دقت کامل (بدون NormalizeDouble برای تطابق با MotiveWave)
    double thStepPriceUnits = (price * percentage) / 100.0;
    return thStepPriceUnits <= 0 ? 0 : (thStepPriceUnits / s_pointValue);
}

double GetTimeframeTH() {
    return CalculateTimeframeTH(GetFractalTimeframeForCurrent());
}

double CalculateTimeframeTH(const string timeframe) {
    // OPTIMIZATION: Check cache first for fractal percentage
    int currentPeriod = GetCachedPeriod();
    double cachedPercentage = GetCachedFractalPercentage(currentPeriod);
    if(cachedPercentage > 0) {
        return cachedPercentage;
    }
    
    // Cache miss - perform lookup
    int totalTimeframes = ArraySize(FRACTAL_TIMEFRAMES);
    
    // Use exact string comparison instead of StringFind
    // StringFind can cause false matches (e.g., "M1" matches "H1+M4")
    for(int i = 0; i < totalTimeframes; i++) {
        if(FRACTAL_TIMEFRAMES[i] == timeframe) {
            double percentage = MODIFIED_FRACTAL_PERCENTAGES[i];
            
            // Store in cache for future use
            int periodSeconds = PeriodSeconds((ENUM_TIMEFRAMES)currentPeriod);
            StoreTimeframeConversion(currentPeriod, timeframe, percentage, periodSeconds);
            return percentage;
        }
    }
    
    // Fallback: return 1.0% for unknown timeframes
    double fallbackPercentage = 1.0;
    int periodSeconds = PeriodSeconds((ENUM_TIMEFRAMES)currentPeriod);
    StoreTimeframeConversion(currentPeriod, timeframe, fallbackPercentage, periodSeconds);
    return fallbackPercentage;
}

//+------------------------------------------------------------------+
//| New calculation functions for extended step modes                |
//+------------------------------------------------------------------+

// [OK] FIXED: Removed duplicate constant definitions
// Constants are now in MathConstants.mqh:
// - SS_MULTIPLIER (1.5)
// - LS_MULTIPLIER (2.0)
// - ATR_FACTOR_M (3.0)

double CalculateShortStep(const double thValue) {
    return thValue * SS_MULTIPLIER;
}

double CalculateLongStep(const double thValue) {
    return thValue * LS_MULTIPLIER;
}

double CalculateEStep(const double thValue) {
    // Formula from EventHandlers.mqh: E = TH * E_MULTIPLIER
    return thValue * E_MULTIPLIER;
}

double CalculateTPStep(const double eValue) {
    // Formula from EventHandlers.mqh: TP = E * 3
    return eValue * 3.0;
}

double CalculateControlValue(const double shortStep, const double longStep) {
    // Logic deduced from typical Biotak patterns
    return shortStep;
}

// Reconstructed CalculateSharedPatternStep
double CalculateSharedPatternStep(const double currentStructure, const double currentPattern,
                                 const double higherPatternStructure, const double higherPatternPattern) {
    #ifdef ENABLE_DEBUG_LOGS
    Print("CalculateSharedPatternStep: currentS=", currentStructure, 
          ", currentP=", currentPattern, ", higherS=", higherPatternStructure, 
          ", higherP=", higherPatternPattern);
    #endif
    
    // Return current SS only as fallback
    if(currentStructure > 0 && currentPattern > 0) {
        return (2 * currentStructure) - currentPattern;  // SS formula
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Factor Step Size                                        |
//| محاسبه اندازه گام فاکتور                                          |
//| Simple Formula: Step = (High - Low) / (Factor × 2)               |
//| CRITICAL FIX: Complete overflow and division-by-zero protection  |
//+------------------------------------------------------------------+

#ifndef MAX_FACTOR_VALUE
#define MAX_FACTOR_VALUE 10000.0
#endif
#ifndef MIN_FACTOR_VALUE
#define MIN_FACTOR_VALUE 0.01
#endif
#ifndef DEFAULT_FACTOR_FALLBACK
#define DEFAULT_FACTOR_FALLBACK 50.0
#endif
#ifndef DEFAULT_FACTOR_ADJUST_STEP
#define DEFAULT_FACTOR_ADJUST_STEP 0.1
#endif

double CalculateFactorStepSize(const double highPrice, const double lowPrice, const double factor) {
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #1: Validate prices with epsilon
    // ═══════════════════════════════════════════════════════════════
    if(highPrice < EPSILON_PRICE || lowPrice < EPSILON_PRICE) {
        Print("❌ CalculateFactorStepSize: Invalid prices - High=", DoubleToString(highPrice, Digits));
        return 0;
    }
    if(highPrice <= lowPrice) {
        Print("❌ CalculateFactorStepSize: Invalid range - High (", DoubleToString(highPrice, Digits));
        return 0;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #2: Validate range (prevent precision loss)
    // ═══════════════════════════════════════════════════════════════
    double range = highPrice - lowPrice;
    double minRange = GetCachedPoint() * 10; // At least 10 pips
    if(range < minRange) {
        Print("❌ CalculateFactorStepSize: Range too small (", DoubleToString(range, Digits));
        return 0;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #3: Validate factor BEFORE any calculation
    // ═══════════════════════════════════════════════════════════════
    if(factor < MIN_FACTOR_VALUE) {
        Print("❌ CalculateFactorStepSize: Factor too small (", DoubleToString(factor, 2));
        return 0;
    }
    if(factor > MAX_FACTOR_VALUE) {
        Print("❌ CalculateFactorStepSize: Factor too large (", DoubleToString(factor, 2));
        return 0;
    }
    
    // OPTIMIZATION: Check calculation cache before performing arithmetic
    double cachedResult = GetCachedFactorStepSize(highPrice, lowPrice, factor);
    if(cachedResult > 0) {
        return cachedResult;
    }

    // ═══════════════════════════════════════════════════════════════
    // Enhanced safe division with proper threshold
    // ═══════════════════════════════════════════════════════════════
    double divisions = factor * 2.0;
    
    // CRITICAL: Use MIN_SAFE_DIVISIONS instead of EPSILON_GENERAL
    // EPSILON_GENERAL (1e-9) is too small and can cause precision loss
    if(divisions < MIN_SAFE_DIVISIONS) {
        Print("❌ CalculateFactorStepSize: Divisions too small (", DoubleToString(divisions, 10));
        return 0;
    }
    
    // Validate divisions result for overflow
    if(divisions > 1000000.0) {
        Print("❌ CalculateFactorStepSize: Invalid divisions calculated (too large): ", divisions);
        return 0;
    }
    
    // Use SafeDivide from FloatingPointHelper for additional safety
    double stepSize = SafeDivide(range, divisions, 0.0, MIN_SAFE_DIVISIONS);
    
    // Validate SafeDivide result
    if(stepSize <= 0) {
        Print("❌ CalculateFactorStepSize: SafeDivide returned invalid result");
        return 0;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #6: Validate result is reasonable
    // ═══════════════════════════════════════════════════════════════
    if(stepSize <= 0) {
        Print("❌ CalculateFactorStepSize: Invalid step size result: ", stepSize);
        return 0;
    }
    if(stepSize < GetCachedPoint() * 0.1) {
        Print("❌ CalculateFactorStepSize: Step size too small (", stepSize, ") - would create too many levels");
        return 0;
    }
    if(stepSize > range) {
        Print("❌ CalculateFactorStepSize: Step size (", stepSize, ") exceeds range (", range, ")");
        return 0;
    }
    
    // Store result in cache for future use
    int currentPeriod = GetCachedPeriod();
    StoreFactorStepSize(highPrice, lowPrice, factor, inpHistoricalPeriods, currentPeriod, stepSize);
    return stepSize;
}

//+------------------------------------------------------------------+
//| Calculate Fractal Values (Structure, Pattern, Trigger) from TH  |
//| محاسبه مقادیر فراکتال (ساختار، الگو، تریگر) از TH               |
//+------------------------------------------------------------------+
void CalculateFractalValues(const double thValue, double &structureValue, double &patternValue, double &triggerValue) {
    // In TH Basis, Structure = TH
    structureValue = thValue;
    
    // Pattern = 0.5 * Structure
    patternValue = structureValue * 0.5;
    
    // Trigger = 0.25 * Structure (half of Pattern)
    triggerValue = structureValue * 0.25;
}

//+------------------------------------------------------------------+
//| Calculate M Distance based on Control Value                      |
//| محاسبه فاصله M بر اساس مقدار کنترل                               |
//+------------------------------------------------------------------+
double CalculateMDistance(const double controlValue) {
    // M Distance is Control Value divided by ATR_FACTOR_M (3.0)
    // If Control Value is SS (1.5 * Structure), then M Distance = 0.5 * Structure (Pattern)
    return controlValue / ATR_FACTOR_M;
}

//+------------------------------------------------------------------+
//| Calculate percentage for standard timeframe (from StandardTimeframes.mqh)
//+------------------------------------------------------------------+
double CalculateStandardPercentage(const int timeInMinutes) {
    if(timeInMinutes <= 0) return 0.0;
    // PERF: Cache results — input is always one of 3 fixed values (1440, 10080, 43200)
    // MathLog/MathPow are expensive, result is purely a function of timeInMinutes and never changes
    static int    s_cachedMinutes[3] = {0, 0, 0};
    static double s_cachedResults[3] = {0, 0, 0};
    static int    s_cachedCount = 0;
    for(int c = 0; c < s_cachedCount; c++) {
        if(s_cachedMinutes[c] == timeInMinutes) return s_cachedResults[c];
    }
    int baseTimeMinutes = 1;
    double basePercentage = 2.083;  // Adjusted so 1024min = 66.66%
    double result;
    if(timeInMinutes <= baseTimeMinutes) {
        result = basePercentage / 100.0;
    } else {
        double timeRatio = (double)timeInMinutes / baseTimeMinutes;
        double doublingFactor = MathLog(timeRatio) / MathLog(4.0);
        result = (basePercentage * MathPow(2.0, doublingFactor)) / 100.0;
    }
    // Store in cache if space available
    if(s_cachedCount < 3) {
        s_cachedMinutes[s_cachedCount] = timeInMinutes;
        s_cachedResults[s_cachedCount] = result;
        s_cachedCount++;
    }
    return result;
}
