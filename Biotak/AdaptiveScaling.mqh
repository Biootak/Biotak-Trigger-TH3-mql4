  //+------------------------------------------------------------------+
//|                                            AdaptiveScaling.mqh   |
//|                                                                  |
//| ATR-Based Volatility Adaptive Scaling for Biotak Trigger TH3    |
//|                                                                  |
//| Normalizes TH-based level spacing to match real market           |
//| volatility using Weighted ATR, while preserving the fractal      |
//| 2  ratio between consecutive structure levels.                   |
//|                                                                  |
//| Three modes:                                                     |
//| FIXED: No adaptation (original behavior)                         |
//| ATR_ADAPTIVE: Full ATR normalization (scalingFactor = ATR/TH)   |
//| BLENDED: Weighted mix (    ATR + (1- )   TH)                   |
//|                                                                  |
//| Smoothing: EMA on scaling factor, updated on bar close only.    |
//+------------------------------------------------------------------+
#property copyright "  Formula by Professor Saeed Khakestar, Indicator by Biotak."
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
//|   = 2 / (period + 1)                                            |
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
    
    // Get theoretical TH for current timeframe (un-adapted base TH)
    double timeframePercentage = GetBaseTimeframeTH();
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
    // GOLD FIX: Use Wilder's based weighted ATR for better stability and standard compliance
    double weightedATR = CalculateWeightedATRForTimeframe((ENUM_TIMEFRAMES)GetEffectiveTimeframe());
    if(weightedATR <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[W][ADAPT] UpdateATRScalingFactor: ATR=0, keeping previous scaling factor");
        #endif
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
        // EMA: smoothed = prev * (1 - alpha) + raw * alpha
        g_smoothedScalingFactor = g_smoothedScalingFactor * (1.0 - alpha) + rawFactor * alpha;
    }
    
    // Clamp smoothed result too
    g_smoothedScalingFactor = MathMax(MIN_SCALING_FACTOR, MathMin(MAX_SCALING_FACTOR, g_smoothedScalingFactor));
    
    // UPDATE FRACTAL SHIFT (Global State)
    if(inpAdaptiveMode == ADAPTIVE_FRACTAL) {
        // TWO STRATEGIES: Conservative vs Aggressive
        
        if(inpFractalJumpStrategy == JUMP_AGGRESSIVE) {
            // AGGRESSIVE STRATEGY: Jump to higher levels earlier
            // Better for sharp volatile pairs (JPY, GBP, etc.)
            //
            // Logic:
            // - If ratio <= 1.2: Shift = 0 (no jump)
            // - If ratio <= 2.3: Shift = 1 (jump 1 level) 
            // - If ratio <= 4.5: Shift = 2 (jump 2 levels)
            // - If ratio >  4.5: Shift = 3 (jump 3 levels, max)
            //
            // Why? When ratio is 2.3x-2.8x, it's closer to 4x than 2x,
            // so we jump to level 2 to get wider spacing between levels.
            
            if(g_smoothedScalingFactor <= 1.2) {
                g_fractalShift = 0;
            } else if(g_smoothedScalingFactor <= 2.3) {
                g_fractalShift = 1;
            } else if(g_smoothedScalingFactor <= 4.5) {
                g_fractalShift = 2;
            } else {
                g_fractalShift = 3;
            }
        } else {
            // CONSERVATIVE STRATEGY: Original log2-based jumping
            // Better for smoother transitions
            //
            // Uses log2 with small bias (0.1) for rounding
            // Example: 2.8x → log2(2.8) = 1.48 → 1.48 + 0.1 = 1.58 → round = 2
            
            if(g_smoothedScalingFactor <= 1.2) {
                g_fractalShift = 0;
            } else {
                g_fractalShift = (int)MathRound((MathLog(g_smoothedScalingFactor) / MathLog(2.0)) + 0.1);
                if(g_fractalShift < 0) g_fractalShift = 0;
                if(g_fractalShift > 3) g_fractalShift = 3;
            }
        }
        
        #ifdef ENABLE_DEBUG_LOGS
        static int s_lastShift = -1;
        if(s_lastShift != g_fractalShift) {
            string strategy = (inpFractalJumpStrategy == JUMP_AGGRESSIVE) ? "AGGRESSIVE" : "CONSERVATIVE";
            Print("==================== [FRACTAL JUMP] Shift changed: ", s_lastShift, " → ", g_fractalShift,
                  " | Ratio: ", DoubleToString(g_smoothedScalingFactor, 2), "x",
                  " | Strategy: ", strategy);
            s_lastShift = g_fractalShift;
        }
        #endif
    } else {
        g_fractalShift = 0;
    }
    
    g_lastScalingBarCount = currentBars;
    
    #ifdef ENABLE_DEBUG_LOGS
    static datetime s_lastAdaptLog = 0;
    datetime now = TimeCurrent();
    if(now - s_lastAdaptLog > 60) {  // Log every 1 minute
        string tfStr = GetFractalTimeframeForCurrent();
        Print("[D][ADAPT] Ratio (ATR/TH_base): ", DoubleToString(g_smoothedScalingFactor, 2), 
              " | Shift: ", g_fractalShift, 
              " | Current TF: ", tfStr);
        s_lastAdaptLog = now;
    }
    #endif
    
    return true;
}

//+------------------------------------------------------------------+
//| Get fractal level shift based on ATR/TH ratio                    |
//| Only used in ADAPTIVE_FRACTAL mode                               |
//+------------------------------------------------------------------+
int GetFractalShift() {
    return g_fractalShift;
}

//+------------------------------------------------------------------+
//| Get Adapted Step Size                                            |
//|                                                                  |
//| Applies the appropriate scaling to a step size based on the     |
//| selected adaptive mode. Preserves fractal 2  ratio because     |
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
            // Full ATR adaptation: stepSize   scalingFactor
            return originalStepSize * factor;
        }
        
        case ADAPTIVE_BLENDED:
        {
            // Blended: interpolate between original and ATR-adapted
            // result = original * (1 - blendRatio) + (original * scalingFactor) * blendRatio
            // Simplified: result = original * ((1 - blendRatio) + scalingFactor * blendRatio)
            double blendRatio = MathMax(0.0, MathMin(1.0, inpAdaptiveBlendRatio));
            double blendedFactor = (1.0 - blendRatio) + factor * blendRatio;
            return originalStepSize * blendedFactor;
        }
        
        case ADAPTIVE_FRACTAL:
        {
            // Fractal Jump is handled at the timeframe selection level
            // so we don't apply another multiplier here.
            return originalStepSize;
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
