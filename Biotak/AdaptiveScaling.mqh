//+------------------------------------------------------------------+
//|                                            AdaptiveScaling.mqh   |
//|                                                                  |
//| ATR-Based Volatility Adaptive Scaling for Biotak Trigger TH3    |
//|                                                                  |
//| Normalizes TH-based level spacing to match real market           |
//| volatility using Weighted ATR, while preserving the fractal      |
//| 2× ratio between consecutive structure levels.                   |
//|                                                                  |
//| Three modes:                                                     |
//| FIXED: No adaptation (original behavior)                         |
//| ATR_ADAPTIVE: Full ATR normalization (scalingFactor = ATR/TH)   |
//| BLENDED: Weighted mix (α × ATR + (1-α) × TH)                   |
//|                                                                  |
//| Smoothing: EMA on scaling factor, updated on bar close only.    |
//+------------------------------------------------------------------+
#property copyright "© Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link      "@biotak"

#property strict

#ifndef ADAPTIVE_SCALING_MQH
#define ADAPTIVE_SCALING_MQH

//+------------------------------------------------------------------+
//| Adaptive Scaling State Variables                                  |
//+------------------------------------------------------------------+
static double g_atrScalingFactor = 1.0;         // Current raw ATR/TH ratio
static double g_smoothedScalingFactor = 1.0;     // EMA-smoothed scaling factor
static int    g_lastScalingBarCount = -1;         // Bar count at last update
static bool   g_scalingInitialized = false;       // First-time initialization flag
static double g_lastRawATR = 0.0;                 // Last ATR value (for debug)
static double g_lastTheoreticalTH = 0.0;          // Last theoretical TH (for debug)

//+------------------------------------------------------------------+
//| Initialize Adaptive Scaling System                               |
//| Must be called from OnInit                                       |
//+------------------------------------------------------------------+
void InitializeAdaptiveScaling() {
    g_atrScalingFactor = 1.0;
    g_smoothedScalingFactor = 1.0;
    g_lastScalingBarCount = -1;
    g_scalingInitialized = false;
    g_lastRawATR = 0.0;
    g_lastTheoreticalTH = 0.0;
}

//+------------------------------------------------------------------+
//| Calculate EMA Alpha from period                                  |
//| α = 2 / (period + 1)                                            |
//+------------------------------------------------------------------+
double GetEMAAlpha(const int period) {
    int safePeriod = MathMax(1, period);
    return 2.0 / (safePeriod + 1.0);
}

//+------------------------------------------------------------------+
//| Update ATR Scaling Factor                                        |
//|                                                                  |
//| Called on each tick, but only recalculates when a new bar closes  |
//| (bar count changes). This prevents level jitter while            |
//| maintaining responsiveness.                                      |
//|                                                                  |
//| @param basePrice    Daily close price used for TH calculation   |
//| @param digits       Symbol digits (precision)                   |
//| @return true if scaling factor was updated                       |
//+------------------------------------------------------------------+
bool UpdateATRScalingFactor(const double basePrice, const int digits) {
    // FIXED mode: no scaling needed
    if(inpAdaptiveMode == ADAPTIVE_FIXED) {
        g_smoothedScalingFactor = 1.0;
        g_atrScalingFactor = 1.0;
        return false;
    }
    
    // Only update on new bar close (bar count change)
    int currentBars = iBars(GetCachedSymbol(), GetEffectiveTimeframe());
    if(g_scalingInitialized && currentBars == g_lastScalingBarCount) {
        return false; // No new bar, skip recalculation
    }
    
    // Validate base price
    if(basePrice < EPSILON_PRICE) {
        _LOG_GATE_E Print("[E][ADAPT] UpdateATRScalingFactor: Invalid base price=", DoubleToString(basePrice, 10));
        return false;
    }
    
    // Get theoretical TH for current timeframe
    double timeframePercentage = GetTimeframeTH();
    if(timeframePercentage <= 0) {
        _LOG_GATE_E Print("[E][ADAPT] UpdateATRScalingFactor: Invalid timeframe percentage=", DoubleToString(timeframePercentage, 10));
        return false;
    }
    
    double theoreticalTH = CalculateTH(basePrice, digits, timeframePercentage);
    if(theoreticalTH <= 0) {
        _LOG_GATE_E Print("[E][ADAPT] UpdateATRScalingFactor: Invalid theoretical TH=", DoubleToString(theoreticalTH, 10));
        return false;
    }
    
    // Get real ATR from existing weighted ATR system
    double weightedATR = CalculateWeightedATR();
    if(weightedATR <= 0) {
        _LOG_GATE_W Print("[W][ADAPT] UpdateATRScalingFactor: ATR=0, keeping previous scaling factor");
        return false;
    }
    
    // Calculate raw scaling factor: ATR / TH
    double rawFactor = SafeDivide(weightedATR, theoreticalTH, 1.0, EPSILON_PRICE);
    
    // Clamp to safe range to prevent extreme values
    rawFactor = MathMax(MIN_SCALING_FACTOR, MathMin(MAX_SCALING_FACTOR, rawFactor));
    
    // Store for debug
    g_lastRawATR = weightedATR;
    g_lastTheoreticalTH = theoreticalTH;
    g_atrScalingFactor = rawFactor;
    
    // Apply EMA smoothing
    int smoothingPeriod = MathMax(1, inpAdaptiveSmoothingPeriod);
    double alpha = GetEMAAlpha(smoothingPeriod);
    
    if(!g_scalingInitialized) {
        // First time: seed EMA with current raw value
        g_smoothedScalingFactor = rawFactor;
        g_scalingInitialized = true;
    } else {
        // EMA: smoothed = prev × (1 - α) + raw × α
        g_smoothedScalingFactor = g_smoothedScalingFactor * (1.0 - alpha) + rawFactor * alpha;
    }
    
    // Clamp smoothed result too
    g_smoothedScalingFactor = MathMax(MIN_SCALING_FACTOR, MathMin(MAX_SCALING_FACTOR, g_smoothedScalingFactor));
    
    g_lastScalingBarCount = currentBars;
    
    #ifdef ENABLE_DEBUG_LOGS
    static datetime s_lastAdaptLog = 0;
    datetime now = TimeCurrent();
    if(now - s_lastAdaptLog > 300) {  // Log every 5 minutes
        Print("[D][ADAPT] ========== ADAPTIVE SCALING UPDATE ==========");
        Print("[D][ADAPT] Mode: ", EnumToString(inpAdaptiveMode));
        Print("[D][ADAPT] ATR: ", DoubleToString(weightedATR, digits));
        Print("[D][ADAPT] Theoretical TH: ", DoubleToString(theoreticalTH, digits));
        Print("[D][ADAPT] Raw Factor (ATR/TH): ", DoubleToString(rawFactor, 4));
        Print("[D][ADAPT] Smoothed Factor: ", DoubleToString(g_smoothedScalingFactor, 4));
        Print("[D][ADAPT] EMA Alpha: ", DoubleToString(alpha, 4), " (period=", smoothingPeriod, ")");
        if(inpAdaptiveMode == ADAPTIVE_BLENDED)
            Print("[D][ADAPT] Blend Ratio: ", DoubleToString(inpAdaptiveBlendRatio, 2));
        Print("[D][ADAPT] ==============================================");
        s_lastAdaptLog = now;
    }
    #endif
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Adapted Step Size                                            |
//|                                                                  |
//| Applies the appropriate scaling to a step size based on the     |
//| selected adaptive mode. Preserves fractal 2× ratio because     |
//| the same scaling factor is applied to ALL levels uniformly.     |
//|                                                                  |
//| @param originalStepSize  The raw TH-based step size             |
//| @return Adapted step size matching real market volatility        |
//+------------------------------------------------------------------+
double GetAdaptedStepSize(const double originalStepSize) {
    // FIXED mode: return unchanged
    if(inpAdaptiveMode == ADAPTIVE_FIXED) {
        return originalStepSize;
    }
    
    // Validate input
    if(originalStepSize <= 0) return 0.0;
    
    // Use smoothed scaling factor
    double factor = g_smoothedScalingFactor;
    
    switch(inpAdaptiveMode) {
        case ADAPTIVE_ATR:
        {
            // Full ATR adaptation: stepSize × scalingFactor
            return originalStepSize * factor;
        }
        
        case ADAPTIVE_BLENDED:
        {
            // Blended: interpolate between original and ATR-adapted
            // result = original × (1 - blendRatio) + (original × scalingFactor) × blendRatio
            // Simplified: result = original × ((1 - blendRatio) + scalingFactor × blendRatio)
            double blendRatio = MathMax(0.0, MathMin(1.0, inpAdaptiveBlendRatio));
            double blendedFactor = (1.0 - blendRatio) + factor * blendRatio;
            return originalStepSize * blendedFactor;
        }
        
        default:
            return originalStepSize;
    }
}

//+------------------------------------------------------------------+
//| Get current scaling factor for info display                      |
//+------------------------------------------------------------------+
double GetCurrentScalingFactor() {
    return g_smoothedScalingFactor;
}

//+------------------------------------------------------------------+
//| Get raw (unsmoothed) scaling factor for info display              |
//+------------------------------------------------------------------+
double GetRawScalingFactor() {
    return g_atrScalingFactor;
}

//+------------------------------------------------------------------+
//| Check if adaptive scaling is active                              |
//+------------------------------------------------------------------+
bool IsAdaptiveScalingActive() {
    return (inpAdaptiveMode != ADAPTIVE_FIXED);
}

#endif
// ADAPTIVE_SCALING_MQH
