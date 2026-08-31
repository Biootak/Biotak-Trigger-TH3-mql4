   //+------------------------------------------------------------------+
//|                                                      TH3Tool.mqh |
//|                     TH3 Structure Tool (Proprietary Logic)       |
//|                     Supports: Steps Mode & AB=CD Pattern Mode    |
//+------------------------------------------------------------------+
#ifndef TH3_TOOL_MQH
#define TH3_TOOL_MQH
#property strict

// Constants for magic numbers
#ifndef ABCD_MIN_DISTANCE_POINTS
#define ABCD_MIN_DISTANCE_POINTS 10
#endif
#ifndef ABCD_DEBOUNCE_MS
#define ABCD_DEBOUNCE_MS 300
#endif
#define ABCD_LABEL_OFFSET_PIPS 15.0
#define ABCD_MAX_PRICE_MULTIPLIER 10.0
#define ABCD_COLLINEARITY_THRESHOLD 0.0001

#define TH3_PATTERN_PREFIX_LEN  13

// Drawing constants (from MT5)
#define TH3_ARROW_CODE          159
#define TH3_POINT_WIDTH         3
#define TH3_POINT_ZORDER        10
#define TH3_TARGET_COUNT        4
#define TH3_TARGET_LINE_WIDTH   2
#define TH3_BAR_EXTENSION       100
#define TH3_SNAP_THRESHOLD_PIPS 5.0
#define TH3_MIN_BASENAME_LEN    20
#define TH3_MAX_TARGETS         7


// TH3 modular architecture: model + pure math + store + controller
#include "TH3\TH3Types.mqh"
#include "TH3\TH3Math.mqh"
#include "TH3\TH3PatternStore.mqh"
#include "TH3\TH3Controller.mqh"
#include "TH3\TH3Renderer.mqh"

// Registry state for fast TH3 bulk updates (avoids chart-wide scans)
static string g_th3PatternRegistry[];
static int    g_th3PatternRegistryCount = 0;

//+------------------------------------------------------------------+
//| Pattern Registry System (ported from MT5)                         |
//+------------------------------------------------------------------+
string ExtractPatternBaseName(const string objName)
{
    if(StringFind(objName, TH3_PATTERN_PREFIX) != 0) return "";
    string suffixes[] = {
        TH3_SUFFIX_LINE_AB, TH3_SUFFIX_LINE_BC, TH3_SUFFIX_TARGET,
        TH3_SUFFIX_POINT, TH3_SUFFIX_LABEL, TH3_SUFFIX_INFO, TH3_SUFFIX_ZONE
    };
    string baseName = objName;
    for(int s = 0; s < ArraySize(suffixes); s++) {
        int pos = StringFind(baseName, suffixes[s]);
        if(pos > 0) { baseName = StringSubstr(baseName, 0, pos); break; }
    }
    if(StringFind(baseName, TH3_PATTERN_PREFIX) != 0 || StringLen(baseName) < TH3_MIN_BASENAME_LEN)
        return "";
    return baseName;
}

int FindTH3PatternRegistryIndex(const string baseName)
{
    for(int i = 0; i < g_th3PatternRegistryCount; i++) {
        if(g_th3PatternRegistry[i] == baseName) return i;
    }
    return -1;
}

void RegisterTH3Pattern(const string baseName)
{
    if(baseName == "") return;
    if(FindTH3PatternRegistryIndex(baseName) >= 0) return;
    int newCount = g_th3PatternRegistryCount + 1;
    ArrayResize(g_th3PatternRegistry, newCount, 16);
    g_th3PatternRegistry[g_th3PatternRegistryCount] = baseName;
    g_th3PatternRegistryCount = newCount;
}

void UnregisterTH3Pattern(const string baseName)
{
    int idx = FindTH3PatternRegistryIndex(baseName);
    if(idx < 0) return;
    for(int i = idx; i < g_th3PatternRegistryCount - 1; i++) {
        g_th3PatternRegistry[i] = g_th3PatternRegistry[i + 1];
    }
    g_th3PatternRegistryCount--;
    if(g_th3PatternRegistryCount <= 0) {
        g_th3PatternRegistryCount = 0;
        ArrayResize(g_th3PatternRegistry, 0);
    } else {
        ArrayResize(g_th3PatternRegistry, g_th3PatternRegistryCount);
    }
}

void RebuildTH3RegistryFromChart()
{
    g_th3PatternRegistryCount = 0;
    ArrayResize(g_th3PatternRegistry, 0);
    int totalObjects = ObjectsTotal();
    for(int i = 0; i < totalObjects; i++) {
        string name = ObjectName(i);
        if(StringFind(name, TH3_PATTERN_PREFIX) != 0) continue;
        string baseName = ExtractPatternBaseName(name);
        if(baseName == "") {
            int underscorePos = StringFind(name, "_", TH3_PATTERN_PREFIX_LEN);
            baseName = (underscorePos > TH3_PATTERN_PREFIX_LEN)
                       ? StringSubstr(name, 0, underscorePos)
                       : name;
        }
        RegisterTH3Pattern(baseName);
    }
}

void BuildPatternNamesFromRegistry(string &patternNames[], int &patternCount)
{
    patternCount = 0;
    ArrayResize(patternNames, g_th3PatternRegistryCount);
    for(int i = 0; i < g_th3PatternRegistryCount; i++) {
        string baseName = g_th3PatternRegistry[i];
        if(baseName == "") continue;
        string lineAB = baseName + TH3_SUFFIX_LINE_AB;
        string lineBC = baseName + TH3_SUFFIX_LINE_BC;
        if(ObjectFind(lineAB) < 0 || ObjectFind(lineBC) < 0) {
            UnregisterTH3Pattern(baseName);
            i--;
            continue;
        }
        patternNames[patternCount++] = baseName;
    }
    if(patternCount < ArraySize(patternNames)) {
        ArrayResize(patternNames, patternCount);
    }
}

//+------------------------------------------------------------------+
//| Compute safe Y position for TH3 info label                       |
//| Accounts for ATR labels + all possible stacked mode labels       |
//+------------------------------------------------------------------+
int GetABCDInfoSafeYDistance()
{
    int y = inpABCDInfoYDistance;

    bool topCorner = (inpABCDInfoCorner == CORNER_LEFT_UPPER || inpABCDInfoCorner == CORNER_RIGHT_UPPER);
    if(!topCorner) return y;

    // ATR/TH label stack currently lives at top-left when label corner is LEFT_TOP.
    if(inpLabelCornerPosition == LABEL_CORNER_LEFT_TOP && inpABCDInfoCorner == CORNER_LEFT_UPPER) {
        int stackedTopY = inpLabelsMarginTop + g_modeLabelYOffset + inpSectionGap;
        if(y < stackedTopY) y = stackedTopY;
    }

    // Push below ALL stacked mode labels + lock label
    if(inpModeLabelCorner == inpABCDInfoCorner) {
        int modeBlockHeight = GetModeLabelBlockHeight();
        int modeBottomY;
        if(modeBlockHeight > 0)
            modeBottomY = inpModeLabelYDistance + g_modeLabelYOffset + modeBlockHeight + 4;
        else
            modeBottomY = inpModeLabelYDistance + g_modeLabelYOffset + (inpModeLabelFontSize + 6) + 4;

        if(g_timeframeLocked) {
            modeBottomY += (inpModeLabelFontSize + 6);
        }
        if(y < modeBottomY) y = modeBottomY;
    }

    return y;
}

//+------------------------------------------------------------------+
//| Reposition all ABCD info labels (lightweight   Y update only)    |
//| Call after g_modeLabelYOffset changes to prevent overlap         |
//+------------------------------------------------------------------+
void RepositionABCDInfoLabels()
{
    if(!inpEnableTH3Tool) return;
    // PERF: Use pattern store instead of ObjectsTotal loop over all chart objects
    int safeY = GetABCDInfoSafeYDistance();
    int patCount = TH3PatternStoreCount();
    for(int i = 0; i < patCount; i++) {
        string infoName = g_th3Patterns.items[i].name + TH3_SUFFIX_INFO;
        if(ObjectFind(0, infoName) >= 0)
            ObjectSetInteger(0, infoName, OBJPROP_YDISTANCE, safeY);
    }
}

//+------------------------------------------------------------------+
//| Get Cached Daily ATR (Performance Optimization)                 |
//|              ATR                   Cache (                                  )                  |
//| Caches ATR for current bar to avoid repeated calculations       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Set active AB=CD pattern (for info label display)               |
//|          AB=CD (      info label)                    |
//+------------------------------------------------------------------+
void SetActiveABCDPattern(string patternName)
{
    if(g_activeABCDPattern == patternName) return; // Already active
    
    // Hide old pattern's info label
    if(g_activeABCDPattern != "") {
        string oldInfoLabel = g_activeABCDPattern + "_Info";
        if(ObjectFind(0, oldInfoLabel) >= 0) {
            ObjectSetInteger(0, oldInfoLabel, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        }
    }
    
    // Set new active pattern
    g_activeABCDPattern = patternName;
    
    // Show new pattern's info label
    if(patternName != "") {
        string newInfoLabel = patternName + "_Info";
        if(ObjectFind(0, newInfoLabel) >= 0) {
            ObjectSetInteger(0, newInfoLabel, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        }
    }
    
    ChartRedraw();
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== Active AB=CD pattern: ", patternName);
    #endif
}

//+------------------------------------------------------------------+
//| Calculate Optimal Default Frequency                             |
//|                                               |
//| Analyzes all frequencies to find best default for Steps 3,5,7   |
//+------------------------------------------------------------------+
double CalculateOptimalDefaultFrequency()
{
    //    
    //       D     Step N    
    // frequency = 100 / N
    // 
    // Step 3: 100/3 = 33.333%
    // Step 5: 100/5 = 20.0%
    // Step 7: 100/7 = 14.286%
    
    //                    
    double idealFrequencies[3];
    idealFrequencies[0] = 100.0 / 3.0;  // 33.333% for Step 3
    idealFrequencies[1] = 100.0 / 5.0;  // 20.0% for Step 5
    idealFrequencies[2] = 100.0 / 7.0;  // 14.286% for Step 7
    
    int bestIndices[3] = {-1, -1, -1};
    double minErrors[3] = {1000000.0, 1000000.0, 1000000.0};
    
    //                    
    for(int i = 0; i < 3; i++)
    {
        int bestIdx = FindNearestFreqIndex(idealFrequencies[i]);
        double minError = MathAbs(GetFrequencyByIndex(bestIdx) - idealFrequencies[i]);
        
        bestIndices[i] = bestIdx;
        minErrors[i] = minError;
    }
    
    //          
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== OPTIMAL DEFAULT FREQUENCY ANALYSIS");
    Print("========================================");
    Print("Step 3 (Ideal: 33.333%):");
    Print("  ==================== Closest: ", DoubleToString(GetFrequencyByIndex(bestIndices[0]), 3), 
          "% (Index: ", bestIndices[0], ", Error: ", DoubleToString(minErrors[0], 3), "%)");
    Print("Step 5 (Ideal: 20.0%):");
    Print("  ==================== Closest: ", DoubleToString(GetFrequencyByIndex(bestIndices[1]), 3), 
          "% (Index: ", bestIndices[1], ", Error: ", DoubleToString(minErrors[1], 3), "%)");
    Print("Step 7 (Ideal: 14.286%):");
    Print("  ==================== Closest: ", DoubleToString(GetFrequencyByIndex(bestIndices[2]), 3), 
          "% (Index: ", bestIndices[2], ", Error: ", DoubleToString(minErrors[2], 3), "%)");
    Print("========================================");
    #endif
    
    //                                
    // Step 5      (     50%)
    // Step 3    7     25%         
    double weightedFreq = (GetFrequencyByIndex(bestIndices[0]) * 0.25) +
                          (GetFrequencyByIndex(bestIndices[1]) * 0.50) +
                          (GetFrequencyByIndex(bestIndices[2]) * 0.25);
    
    //                               
    int bestDefaultIdx = FindNearestFreqIndex(weightedFreq);
    double bestDefault = GetFrequencyByIndex(bestDefaultIdx);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== RECOMMENDED DEFAULT FREQUENCY:");
    Print("  Weighted Average: ", DoubleToString(weightedFreq, 3), "%");
    Print("  Best Match: ", DoubleToString(bestDefault, 3), "% (Index: ", bestDefaultIdx, ")");
    Print("========================================");
    #endif
    
    return bestDefault;
}

//+------------------------------------------------------------------+
//| Get Current TH3 Frequency (with override support)               |
//+------------------------------------------------------------------+
double GetCurrentTH3Frequency() {
    if(g_th3FreqOverride > 0.0) return g_th3FreqOverride;
    
    // Validate input parameter (extended to 120%)
    if(inpTH3BaseStepPercent > 0.0 && inpTH3BaseStepPercent <= 120.0) {
        return inpTH3BaseStepPercent;
    }
    
    // Fallback to safe default
    return 28.125;
}

//+------------------------------------------------------------------+
//| Analyze Three-Wave Pattern (XA, AB, BC)                         |
//|             (XA  AB  BC)                                 |
//| Returns comprehensive wave analysis for frequency selection     |
//+------------------------------------------------------------------+
//|           (    Gann)                                    |
//| Returns: Angle in degrees (0-90)                                |
//| Logic: angle = atan(price_change / time_change)                 |
//+------------------------------------------------------------------+
//| Calculate Optimal Frequency from Wave Analysis                  |
//|                                                  |
//| Integrates: speed, consolidation, consistency, Fibonacci        |
//+------------------------------------------------------------------+
double CalculateFrequencyFromWaves(WaveAnalysis &waves)
{
    //                    
    // 1.             (Step 5 = 20%)
    // 2.                  (Impulsive/Correctional)
    // 3.             (Gann-inspired)
    // 4.            
    // 5.             Fibonacci
    
    double baseFrequency = 20.0; //     Step 5
    
    // ========================================
    //   1:                 
    // ========================================
    if(waves.isImpulsive) {
        baseFrequency *= 1.3; //   30%          
    }
    else if(waves.isCorrectional) {
        baseFrequency *= 0.7; //   30%        
    }
    
    // ========================================
    //   2:             (Gann-inspired)
    // ========================================
    //               ATR
    // OPTIMIZATION: Use cached ATR instead of repeated iATR() calls
    double dailyATR = GetCachedDailyATR();
    double pipSize = GetCachedPipSize();
    double minATR = pipSize * 10;  // Minimum 10 pips worth of ATR
    
    if(dailyATR <= 0 || dailyATR < minATR) {
        double avgRange = 0;
        for(int i = 1; i <= 20; i++) {
            avgRange += (iHigh(NULL, PERIOD_D1, i) - iLow(NULL, PERIOD_D1, i));
        }
        dailyATR = avgRange / 20.0;
    }
    
    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0;
    if(referenceSpeed <= 0) referenceSpeed = 0.1;
    
    double avgSpeedRatio = waves.avgSpeed / referenceSpeed;
    
    //             (    Gann)
    double speedWeight = 1.0;
    if(avgSpeedRatio >= 3.0) {
        speedWeight = 1.5; //    
    }
    else if(avgSpeedRatio >= 2.0) {
        speedWeight = 1.3; //   (Gann 2 
    }
    else if(avgSpeedRatio >= 1.5) {
        speedWeight = 1.15; //      
    }
    else if(avgSpeedRatio >= 0.8 && avgSpeedRatio <= 1.2) {
        speedWeight = 1.0; //   (Gann 1 
    }
    else if(avgSpeedRatio >= 0.5) {
        speedWeight = 0.85; //         (Gann 1 
    }
    else if(avgSpeedRatio >= 0.33) {
        speedWeight = 0.7; //    
    }
    else {
        speedWeight = 0.6; //      
    }
    
    baseFrequency *= speedWeight;
    
    // ========================================
    //   3:            
    // ========================================
    //                  
    double consistencyFactor = 0.8 + (waves.speedConsistency * 0.4); // 0.8   1.2
    baseFrequency *= consistencyFactor;
    
    // ========================================
    //   4:             AB/XA (Fibonacci)
    // ========================================
    //             Fibonacci           
    double fibRatios[7] = {0.382, 0.5, 0.618, 0.786, 1.0, 1.272, 1.618};
    double minFibDiff = 1000.0;
    
    for(int i = 0; i < 7; i++) {
        double diff = MathAbs(waves.AB_XA_Ratio - fibRatios[i]);
        if(diff < minFibDiff) minFibDiff = diff;
    }
    
    //         Fibonacci   (< 0.1)     
    if(minFibDiff < 0.1) {
        baseFrequency *= 1.1; //   10%
    }
    
    // ========================================
    //   5:             
    // ========================================
    if(baseFrequency < 3.125) baseFrequency = 3.125;
    if(baseFrequency > 120.0) baseFrequency = 120.0; // Extended to 120%
    
    return baseFrequency;
}
//|           (    Gann) -                  |
//| Returns: Speed ratio relative to reference (1.0 = balanced)     |
//| > 1.0 = Fast move, < 1.0 = Slow move                           |
//+------------------------------------------------------------------+
//| Analyze Harmonic Properties (Scientific Analysis)               |
//|             (                              |
//| Returns: Detailed analysis of harmonic ratios                   |
//+------------------------------------------------------------------+
void AnalyzeHarmonicProperties(WaveAnalysis &waves)
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== HARMONIC ANALYSIS (SCIENTIFIC)");
    Print("========================================");
    
    // ========================================
    // 1. HARMONIC MEAN ANALYSIS
    // ========================================
    if(waves.XA_Speed > 0 && waves.AB_Speed > 0 && waves.BC_Speed > 0) {
        double recipSum = (1.0/waves.XA_Speed) + (1.0/waves.AB_Speed) + (1.0/waves.BC_Speed);
        double harmonicMean = 3.0 / recipSum;
        double arithmeticMean = (waves.XA_Speed + waves.AB_Speed + waves.BC_Speed) / 3.0;
        double geometricMean = MathPow(waves.XA_Speed * waves.AB_Speed * waves.BC_Speed, 1.0/3.0);
        
        Print("==================== PYTHAGOREAN MEANS:");
        Print("   Harmonic Mean:   ", DoubleToString(harmonicMean, 2), " pips/min");
        Print("   Geometric Mean:  ", DoubleToString(geometricMean, 2), " pips/min");
        Print("   Arithmetic Mean: ", DoubleToString(arithmeticMean, 2), " pips/min");
        Print("   Relationship: HM ==================== GM ==================== AM ", 
              (harmonicMean <= geometricMean && geometricMean <= arithmeticMean) ? "====================" : "====================");
        
        double meanRatio = harmonicMean / arithmeticMean;
        Print("   HM/AM Ratio: ", DoubleToString(meanRatio, 3));
        if(meanRatio > 0.9) {
            Print("   ==================== ==================== EXCELLENT: Very consistent speeds");
        } else if(meanRatio > 0.8) {
            Print("   ==================== ==================== GOOD: Moderately consistent speeds");
        } else if(meanRatio > 0.7) {
            Print("   ==================== ==================== FAIR: Some speed variation");
        } else {
            Print("   ==================== ==================== POOR: High speed variation");
        }
    }
    
    // ========================================
    // 2. GOLDEN RATIO ANALYSIS (PHI)
    // ========================================
    double phi = 1.618033988749;
    double phiInverse = 0.618033988749;
    
    Print("==================== GOLDEN RATIO (==================== = 1.618):");
    
    // AB/XA ratio
    double phiDev_AB_XA = MathAbs(waves.AB_XA_Ratio - phiInverse);
    Print("   AB/XA = ", DoubleToString(waves.AB_XA_Ratio, 3));
    if(phiDev_AB_XA < 0.05) {
        Print("   ==================== ==================== GOLDEN RATIO (0.618) detected! Deviation: ", 
              DoubleToString(phiDev_AB_XA * 100, 1), "%");
    } else {
        double phiDev_ext = MathAbs(waves.AB_XA_Ratio - phi);
        if(phiDev_ext < 0.08) {
            Print("   ==================== ==================== PHI EXTENSION (1.618) detected! Deviation: ", 
                  DoubleToString(phiDev_ext * 100, 1), "%");
        } else {
            Print("   ==================== No Golden Ratio (deviation: ", DoubleToString(phiDev_AB_XA * 100, 1), "%)");
        }
    }
    
    // BC/AB ratio
    double phiDev_BC_AB = MathAbs(waves.BC_AB_Ratio - phiInverse);
    Print("   BC/AB = ", DoubleToString(waves.BC_AB_Ratio, 3));
    if(phiDev_BC_AB < 0.05) {
        Print("   ==================== ==================== GOLDEN RATIO (0.618) detected! Deviation: ", 
              DoubleToString(phiDev_BC_AB * 100, 1), "%");
    } else {
        Print("   ==================== No Golden Ratio (deviation: ", DoubleToString(phiDev_BC_AB * 100, 1), "%)");
    }
    
    // ========================================
    // 3. SUMMARY
    // ========================================
    int harmonicScore = 0;
    if(waves.XA_Speed > 0 && waves.AB_Speed > 0 && waves.BC_Speed > 0) {
        double recipSum = (1.0/waves.XA_Speed) + (1.0/waves.AB_Speed) + (1.0/waves.BC_Speed);
        double harmonicMean = 3.0 / recipSum;
        double arithmeticMean = (waves.XA_Speed + waves.AB_Speed + waves.BC_Speed) / 3.0;
        double meanRatio = harmonicMean / arithmeticMean;
        if(meanRatio > 0.9) harmonicScore++;
    }
    
    if(phiDev_AB_XA < 0.05 || phiDev_BC_AB < 0.05) harmonicScore++;
    
    Print("========================================");
    Print("==================== HARMONIC QUALITY: ", harmonicScore, "/2");
    if(harmonicScore == 2) {
        Print("   ==================== EXCELLENT: Strong harmonic properties");
    } else if(harmonicScore == 1) {
        Print("   ==================== GOOD: Some harmonic properties");
    } else {
        Print("   ==================== NORMAL: No special harmonic properties");
    }
    Print("========================================");
    #endif
}

//+------------------------------------------------------------------+
//| Calculate Frequency Error for AB=CD Pattern                     |
//|              AB=CD                              |
//| Returns: Error percentage (0 = perfect match)                   |
//| CRITICAL FIX: Added division by zero protection                 |
//+------------------------------------------------------------------+
//| Find Optimal Frequency for XABCD Pattern - COMPLETE ANALYSIS    |
//|                  XABCD -                |
//| Multi-factor scoring: error, wave analysis, Fibonacci, symmetry |
//+------------------------------------------------------------------+
int FindOptimalFrequencyForABCD(datetime tX, double pX, datetime tA, double pA, 
                                datetime tB, double pB, datetime tC, double pC,
                                FrequencySearchResult &results[],
                                double maxErrorPercent = 5.0)
{
    //        
    ArrayResize(results, 0);
    
    double AB_Distance = MathAbs(pB - pA);
    if(AB_Distance <= 0) return 0;
    
    double pipSize = GetCachedPipSize();
    
    // ========================================
    //   1:         (Wave Analysis)
    // ========================================
    WaveAnalysis waves = AnalyzeThreeWaves(tX, pX, tA, pA, tB, pB, tC, pC);
    
    //             ( 
    AnalyzeHarmonicProperties(waves);
    
    //                    
    double suggestedFreq = CalculateFrequencyFromWaves(waves);
    
    //              
    double speedRatio = CalculateMovementSpeed(tA, pA, tB, pB);
    double timeSymmetry = waves.timeSymmetry;  //             struct
    
    //         Fibonacci
    double fibDeviation = CalculateFibonacciDeviation(waves.AB_XA_Ratio);
    
    //     Consolidation (          breakout)
    double consolidationFactor = CalculateConsolidationFactor(tA, tB, tC, waves);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== COMPLETE WAVE ANALYSIS (X-A-B-C):");
    Print("   Wave Distances: XA=", DoubleToString(waves.XA_Distance/pipSize, 1), 
          " | AB=", DoubleToString(waves.AB_Distance/pipSize, 1),
          " | BC=", DoubleToString(waves.BC_Distance/pipSize, 1), " pips");
    Print("   Wave Speeds: XA=", DoubleToString(waves.XA_Speed, 2), 
          " | AB=", DoubleToString(waves.AB_Speed, 2),
          " | BC=", DoubleToString(waves.BC_Speed, 2), " pips/min");
    Print("   AB/XA Ratio: ", DoubleToString(waves.AB_XA_Ratio, 3), 
          " (Fib Dev: ", DoubleToString(fibDeviation, 3), ")");
    Print("   Speed Consistency: ", DoubleToString(waves.speedConsistency * 100, 1), "%");
    Print("   Time Symmetry: ", DoubleToString(timeSymmetry * 100, 1), "%");
    Print("   Consolidation Factor: ", DoubleToString(consolidationFactor * 100, 1), "% (Energy buildup)");
    Print("   Pattern Type: ", waves.isImpulsive ? "Impulsive" : (waves.isCorrectional ? "Correctional" : "Balanced"));
    Print("   Suggested Frequency: ", DoubleToString(suggestedFreq, 3), "%");
    Print("   Speed Ratio: ", DoubleToString(speedRatio, 2), "x");
    
    //         
    if(waves.speedConsistency < 0.5) {
        Print("   ==================== WARNING: Low speed consistency - results may be unreliable");
    } else if(waves.speedConsistency < 0.7) {
        Print("   ==================== CAUTION: Moderate speed consistency");
    } else {
        Print("   ==================== Good speed consistency");
    }
    
    //     consolidation  
    if(consolidationFactor > 0.7) {
        Print("   ==================== HIGH CONSOLIDATION: Expect strong breakout - using larger steps");
    } else if(consolidationFactor > 0.4) {
        Print("   ==================== MODERATE CONSOLIDATION: Some energy buildup detected");
    }
    
    Print("========================================");
    #endif
    
    // ========================================
    //   2:           (Advanced Harmonic Analysis)
    // ========================================
    //         Gann         (  struct)
    double gannAngle = waves.AB_Angle;
    
    //       BC/AB        
    double bcToAbRatio = 0.0;
    if(waves.AB_Distance > 0) {
        bcToAbRatio = waves.BC_Distance / waves.AB_Distance;
    }
    
    // ========================================
    //   HARMONIC PATTERN RECOGNITION (Gartley, Bat, Butterfly, Crab)
    // ========================================
    //         Fibonacci    
    string harmonicPattern = "NONE";
    double harmonicConfidence = 0.0;
    double prz_Frequency = 0.0;  // Potential Reversal Zone frequency
    
    // Gartley Pattern: AB/XA = 0.618, BC/AB = 0.382-0.886, CD = 1.272 extension of BC
    if(waves.AB_XA_Ratio >= 0.580 && waves.AB_XA_Ratio <= 0.660) {
        if(bcToAbRatio >= 0.382 && bcToAbRatio <= 0.886) {
            harmonicPattern = "GARTLEY";
            harmonicConfidence = 0.786;  // 78.6% retracement point
            prz_Frequency = 28.0 + (bcToAbRatio * 30.0);  // 28-58% range
        }
    }
    // Bat Pattern: AB/XA = 0.382-0.500, BC/AB = 0.382-0.886, CD = 1.618-2.618 extension
    else if(waves.AB_XA_Ratio >= 0.382 && waves.AB_XA_Ratio <= 0.500) {
        if(bcToAbRatio >= 0.382 && bcToAbRatio <= 0.886) {
            harmonicPattern = "BAT";
            harmonicConfidence = 0.886;  // 88.6% retracement point
            prz_Frequency = 35.0 + (bcToAbRatio * 25.0);  // 35-60% range
        }
    }
    // Butterfly Pattern: AB/XA = 0.786, BC/AB = 0.382-0.886, CD = 1.618-2.24 extension
    else if(waves.AB_XA_Ratio >= 0.750 && waves.AB_XA_Ratio <= 0.820) {
        if(bcToAbRatio >= 0.382 && bcToAbRatio <= 0.886) {
            harmonicPattern = "BUTTERFLY";
            harmonicConfidence = 1.272;  // 127.2% extension
            prz_Frequency = 45.0 + (bcToAbRatio * 35.0);  // 45-80% range
        }
    }
    // Crab Pattern: AB/XA = 0.382-0.618, BC/AB = 0.382-0.886, CD = 2.24-3.618 extension
    else if(waves.AB_XA_Ratio >= 0.382 && waves.AB_XA_Ratio <= 0.618) {
        if(bcToAbRatio >= 0.382 && bcToAbRatio <= 0.886) {
            harmonicPattern = "CRAB";
            harmonicConfidence = 1.618;  // 161.8% extension
            prz_Frequency = 50.0 + (bcToAbRatio * 40.0);  // 50-90% range
        }
    }
    
    // ========================================
    //   ANDREWS PITCHFORK MEDIAN LINE ANALYSIS
    // ========================================
    //        80%:   80%             (Median Line)  
    //       Median Line         
    double medianPrice = (pX + pA + pB) / 3.0;  // Median of X, A, B
    double currentDistanceFromMedian = MathAbs(pC - medianPrice);
    double maxDistanceFromMedian = MathMax(MathAbs(pA - medianPrice), MathAbs(pB - medianPrice));
    
    double medianLineDeviation = 0.0;
    if(maxDistanceFromMedian > 0) {
        medianLineDeviation = currentDistanceFromMedian / maxDistanceFromMedian;
    }
    
    //             Median   (>80%)           
    bool strongMedianLinePull = (medianLineDeviation > 0.8);
    bool moderateMedianLinePull = (medianLineDeviation > 0.5 && medianLineDeviation <= 0.8);
    
    //                 Median Line
    double medianLineFrequency = 0.0;
    if(strongMedianLinePull) {
        //           Median                        
        medianLineFrequency = 55.0 + (medianLineDeviation * 30.0);  // 55-85% range
    } else if(moderateMedianLinePull) {
        //             Median                      
        medianLineFrequency = 35.0 + (medianLineDeviation * 30.0);  // 35-65% range
    }
    
    // ========================================
    //   AB=CD PATTERN VALIDATION
    // ========================================
    //        AB=CD: BC   61.8% retracement   AB  
    //              CD   127.2% extension   BC  
    bool isValidABCD = false;
    double abcdScore = 0.0;
    
    //   BC retracement (      0.618  
    double bcRetracementError = MathAbs(bcToAbRatio - 0.618);
    if(bcRetracementError < 0.15) {  //      
        isValidABCD = true;
        abcdScore = 1.0 - (bcRetracementError / 0.15);  // 0-1 score
    }
    
    //         Impulsive           
    bool isStrongImpulsive = (gannAngle > 75.0 && consolidationFactor < 0.1);
    bool isMediumImpulsive = (gannAngle >= 50.0 && gannAngle <= 75.0 && consolidationFactor < 0.1);
    bool hasDeepRetracement = (bcToAbRatio > 0.7);
    bool hasGoodTimeSymmetry = (timeSymmetry > 0.8);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== ADVANCED HARMONIC & PITCHFORK ANALYSIS:");
    Print("========================================");
    
    // Harmonic Pattern Detection
    if(harmonicPattern != "NONE") {
        Print("==================== HARMONIC PATTERN: ", harmonicPattern);
        Print("   AB/XA Ratio: ", DoubleToString(waves.AB_XA_Ratio, 3));
        Print("   BC/AB Ratio: ", DoubleToString(bcToAbRatio, 3));
        Print("   Confidence Level: ", DoubleToString(harmonicConfidence, 3));
        Print("   PRZ Frequency: ", DoubleToString(prz_Frequency, 1), "%");
        Print("   ==================== Using harmonic-based frequency selection");
    }
    
    // Median Line Analysis
    Print("==================== ANDREWS PITCHFORK (Median Line):");
    Print("   Median Price: ", DoubleToString(medianPrice, Digits));
    Print("   Distance from Median: ", DoubleToString(medianLineDeviation * 100, 1), "%");
    if(strongMedianLinePull) {
        Print("   ==================== STRONG PULL: Price far from median (>80%)");
        Print("   ==================== Expect strong reversal to median");
        Print("   ==================== Median Frequency: ", DoubleToString(medianLineFrequency, 1), "%");
    } else if(moderateMedianLinePull) {
        Print("   ==================== MODERATE PULL: Price moderately far (50-80%)");
        Print("   ==================== Median Frequency: ", DoubleToString(medianLineFrequency, 1), "%");
    } else {
        Print("   ==================== Near Median: Price close to equilibrium");
    }
    
    // AB=CD Validation
    Print("==================== AB=CD PATTERN VALIDATION:");
    Print("   BC Retracement: ", DoubleToString(bcToAbRatio, 3), " (Target: 0.618)");
    Print("   Error: ", DoubleToString(bcRetracementError, 3));
    if(isValidABCD) {
        Print("   ==================== VALID AB=CD: Score ", DoubleToString(abcdScore * 100, 1), "%");
        Print("   ==================== Using AB=CD frequency rules");
    } else {
        Print("   ==================== Not a classic AB=CD pattern");
    }
    
    Print("========================================");
    
    // Original Impulsive Pattern Detection
    if(isStrongImpulsive) {
        Print("==================== STRONG IMPULSIVE PATTERN DETECTED:");
        Print("   Gann Angle: ", DoubleToString(gannAngle, 2), "==================== (>75====================)");
        Print("   Consolidation: ", DoubleToString(consolidationFactor * 100, 1), "% (<10%)");
        Print("   BC/AB Ratio: ", DoubleToString(bcToAbRatio, 3));
        if(hasDeepRetracement) {
            Print("   Deep Retracement: YES - Expect strong continuation");
        }
        Print("   ==================== Adjusting scoring: Prefer higher frequencies (50-70% range)");
        Print("   ==================== Reducing penalties for low consistency and time symmetry");
    }
    else if(isMediumImpulsive) {
        Print("==================== MEDIUM IMPULSIVE PATTERN DETECTED:");
        Print("   Gann Angle: ", DoubleToString(gannAngle, 2), "==================== (50-75====================)");
        Print("   Consolidation: ", DoubleToString(consolidationFactor * 100, 1), "% (<10%)");
        Print("   BC/AB Ratio: ", DoubleToString(bcToAbRatio, 3));
        Print("   Time Symmetry: ", DoubleToString(timeSymmetry * 100, 1), "%");
        if(hasGoodTimeSymmetry) {
            Print("   Good Time Symmetry: Pattern is reliable");
        }
        Print("   ==================== Adjusting scoring: Prefer frequencies (35-50% range)");
        Print("   ==================== Reducing penalties for low consistency");
    }
    Print("========================================");
    #endif
    
    // ========================================
    //   3:                 
    // ========================================
    int targetSteps[10] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    int primarySteps[3] = {3, 5, 7}; //     
    
    //       Impulsive               2-3-4    
    if(isStrongImpulsive) {
        primarySteps[0] = 2;
        primarySteps[1] = 3;
        primarySteps[2] = 4;
    }
    //       Impulsive               2-3-5    
    else if(isMediumImpulsive) {
        primarySteps[0] = 2;
        primarySteps[1] = 3;
        primarySteps[2] = 5;
    }
    
    // ========================================
    //   4:         candidate
    // ========================================
    bool candidateFreqs[MAX_TH3_FREQ_INDEX + 1]; // Binary subdivision indices
    ArrayInitialize(candidateFreqs, false);
    
    //     1:           (100/N)
    for(int stepIdx = 0; stepIdx < 3; stepIdx++)
    {
        int targetStep = primarySteps[stepIdx];
        double idealFreq = 100.0 / targetStep;
        
        int closestIdx = FindNearestFreqIndex(idealFreq);
        
        // Mark        
        int startIdx = MathMax(MIN_TH3_FREQ_INDEX, closestIdx - 5);
        int endIdx = MathMin(MAX_TH3_FREQ_INDEX, closestIdx + 5);
        
        for(int i = startIdx; i <= endIdx; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    
    //     2:           (suggested frequency)
    if(suggestedFreq > 0 && suggestedFreq <= 100.0)
    {
        int closestIdx = FindNearestFreqIndex(suggestedFreq);
        
        // Mark         suggested frequency
        int startIdx = MathMax(MIN_TH3_FREQ_INDEX, closestIdx - 3);
        int endIdx = MathMin(MAX_TH3_FREQ_INDEX, closestIdx + 3);
        
        for(int i = startIdx; i <= endIdx; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    
    //     3:       Impulsive         50-70%          
    if(isStrongImpulsive) {
        int impStart = FindNearestFreqIndex(50.0);
        int impEnd = FindNearestFreqIndex(70.0);
        for(int i = impStart; i <= impEnd; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    //     4:       Impulsive         35-50%          
    else if(isMediumImpulsive) {
        int medStart = FindNearestFreqIndex(35.0);
        int medEnd = FindNearestFreqIndex(50.0);
        for(int i = medStart; i <= medEnd; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    
    // ========================================
    //   5:             
    // ========================================
    for(int freqIdx = MIN_TH3_FREQ_INDEX; freqIdx <= MAX_TH3_FREQ_INDEX; freqIdx++)
    {
        if(!candidateFreqs[freqIdx]) continue;
        
        double testFreq = GetFrequencyByIndex(freqIdx);
        
        for(int stepIdx = 0; stepIdx < 10; stepIdx++)
        {
            int testStep = targetSteps[stepIdx];
            double calcD, targetPrice;
            
            double errorPercent = CalculateFrequencyError(pA, pB, pC, testFreq, 
                                                          testStep, calcD, targetPrice);
            
            // ========================================
            //         (Multi-factor Scoring)
            //                
            // ========================================
            
            //            
            // Hardcoded weights (ML LearnedWeights removed)
            double w_step5Priority = 1.5;
            double w_step3_7Priority = 1.2;
            double w_step1Priority = 0.8;
            double w_errorWeight = 1.0;
            double w_speedConsistencyWeight = 1.0;
            double w_timeSymmetryWeight = 1.0;
            double w_fibonacciWeight = 1.0;
            double w_freqDeviationWeight = 0.5;
            double w_consolidationWeight = 0.8;
            double w_stepPriorityWeight = 1.0;
            
            // 1.       Step (          
            double stepPriority = 1.0;
            if(testStep == 5) {
                stepPriority = w_step5Priority;  //    
            } else if(testStep == 3 || testStep == 7) {
                stepPriority = w_step3_7Priority;  //    
            } else if(testStep == 1) {
                stepPriority = w_step1Priority;  //    
            }
            
            // 2.     (          
            double errorScore = errorPercent * w_errorWeight;
            
            // 3.     (          
            //   =     (1 - consistency)   20
            //       Impulsive            penalty    
            double speedConsistencyWeight = w_speedConsistencyWeight;
            if(isStrongImpulsive) {
                speedConsistencyWeight *= 0.3;  //   70% penalty
            }
            else if(isMediumImpulsive) {
                speedConsistencyWeight *= 0.5;  //   50% penalty
            }
            double speedScore = (1.0 - waves.speedConsistency) * 20.0 * speedConsistencyWeight;
            
            // 4.        (          
            //   =     (1 - symmetry)   100
            //       Impulsive       penalty    
            //                             
            double timeSymmetryWeight = w_timeSymmetryWeight;
            if(isStrongImpulsive && hasDeepRetracement) {
                timeSymmetryWeight *= 0.2;  //   80% penalty
            }
            else if(isMediumImpulsive && hasGoodTimeSymmetry) {
                timeSymmetryWeight *= 0.5;  //   50% penalty (       =       
            }
            double timeScore = (1.0 - timeSymmetry) * 100.0 * timeSymmetryWeight;
            
            // 5.       Fibonacci (          
            //   =  
            double fibScore = fibDeviation * 100.0 * w_fibonacciWeight;
            
            // 6.     suggested frequency (          
            double freqDeviation = 0.0;
            if(suggestedFreq > 0) {
                freqDeviation = MathAbs(testFreq - suggestedFreq) / suggestedFreq;
            }
            double freqScore = freqDeviation * 100.0 * w_freqDeviationWeight;
            
            // 7. Consolidation factor (          
            //   consolidation           (         
            //           penalty   
            double consolidationPenalty = 0.0;
            if(consolidationFactor > 0.3) {
                //           suggested   penalty  
                if(testFreq < suggestedFreq) {
                    double freqRatio = testFreq / suggestedFreq;
                    consolidationPenalty = (1.0 - freqRatio) * consolidationFactor * 100.0 * w_consolidationWeight;
                }
            }
            
            // 8.       Step Priority (          
            //                     
            double stepPriorityScore = stepPriority * w_stepPriorityWeight;
            
            // 9.                       Impulsive
            double impulsiveBonus = 0.0;
            if(isStrongImpulsive) {
                //             50-70%             (    =  
                if(testFreq >= 50.0 && testFreq <= 70.0) {
                    impulsiveBonus = -50.0;  //             =    
                }
                //              penalty  
                else if(testFreq < 30.0) {
                    impulsiveBonus = 100.0;  // penalty         
                }
            }
            else if(isMediumImpulsive) {
                //             35-50%            
                if(testFreq >= 35.0 && testFreq <= 50.0) {
                    impulsiveBonus = -30.0;  //            
                }
                //              penalty  
                else if(testFreq < 25.0) {
                    impulsiveBonus = 80.0;  // penalty         
                }
                //                           
                if(hasGoodTimeSymmetry && testFreq >= 40.0 && testFreq <= 45.0) {
                    impulsiveBonus -= 20.0;  //                   
                }
            }
            
            // ========================================
            // 10.   HARMONIC PATTERN BONUS (NEW)
            // ========================================
            double harmonicBonus = 0.0;
            if(harmonicPattern != "NONE" && prz_Frequency > 0) {
                //           PRZ            
                double przDeviation = MathAbs(testFreq - prz_Frequency) / prz_Frequency;
                if(przDeviation < 0.15) {  //   tolerance
                    harmonicBonus = -40.0 * (1.0 - przDeviation / 0.15);  // Max -40 bonus
                    
                    //                    
                    if(harmonicPattern == "CRAB") harmonicBonus *= 1.3;  // Crab =     
                    else if(harmonicPattern == "BUTTERFLY") harmonicBonus *= 1.2;
                    else if(harmonicPattern == "BAT") harmonicBonus *= 1.1;
                }
            }
            
            // ========================================
            // 11.   MEDIAN LINE BONUS (NEW)
            // ========================================
            double medianLineBonus = 0.0;
            if(medianLineFrequency > 0) {
                //           Median Line Frequency            
                double medianDeviation = MathAbs(testFreq - medianLineFrequency) / medianLineFrequency;
                if(medianDeviation < 0.20) {  //   tolerance
                    if(strongMedianLinePull) {
                        //           Median                
                        medianLineBonus = -35.0 * (1.0 - medianDeviation / 0.20);  // Max -35 bonus
                    } else if(moderateMedianLinePull) {
                        //             Median                
                        medianLineBonus = -20.0 * (1.0 - medianDeviation / 0.20);  // Max -20 bonus
                    }
                }
            }
            
            // ========================================
            // 12.   AB=CD VALIDATION BONUS (NEW)
            // ========================================
            double abcdBonus = 0.0;
            if(isValidABCD) {
                //     AB=CD                   score
                //             25-45%   (  AB=CD)
                if(testFreq >= 25.0 && testFreq <= 45.0) {
                    abcdBonus = -30.0 * abcdScore;  // Max -30 bonus
                    
                    //                 38.2%   (Fibonacci 0.382)
                    if(testFreq >= 36.0 && testFreq <= 40.0) {
                        abcdBonus -= 15.0;  // Extra -15 bonus
                    }
                }
            }
            
            // ========================================
            // 13.   ACCELERATION FACTOR (NEW - HIGH PRIORITY)
            // ========================================
            double accelerationScore = 0.0;
            
            //     =                      breakout    
            if(waves.AB_to_BC_Acceleration > 0.001) {
                //                
                double accelRatio = MathMin(waves.AB_to_BC_Acceleration / 0.01, 1.0);
                accelerationScore = -20.0 * accelRatio;  // Max -20 bonus
            }
            //       =                      breakout  
            else if(waves.AB_to_BC_Acceleration < -0.001) {
                double accelRatio = MathMin(MathAbs(waves.AB_to_BC_Acceleration) / 0.01, 1.0);
                accelerationScore = 20.0 * accelRatio;  // Max +20 penalty
            }
            
            // ========================================
            // 14.   RELATIVE STRENGTH FACTOR (NEW - HIGH PRIORITY)
            // ========================================
            double strengthScore = 0.0;
            
            //     BC
            if(waves.BC_RelativeStrength > 2.0) {
                // BC               D    
                strengthScore = -25.0;
            } else if(waves.BC_RelativeStrength < 1.0) {
                // BC           D  
                strengthScore = 25.0;
            }
            
            //       BC   AB (momentum change)
            double strengthRatio = waves.BC_RelativeStrength / MathMax(waves.AB_RelativeStrength, 0.1);
            if(strengthRatio > 1.2) {
                // BC       AB     momentum      
                strengthScore -= 15.0;
            } else if(strengthRatio < 0.8) {
                // BC     AB     momentum      
                strengthScore += 15.0;
            }
            
            // ========================================
            // 15.   CONFIDENCE SCORE SYSTEM (NEW - CRITICAL)
            // ========================================
            double confidence = 100.0;
            
            //   confidence          
            if(waves.speedConsistency < 0.5) confidence -= 30.0;  //     
            if(timeSymmetry < 0.6) confidence -= 20.0;  //      
            if(fibDeviation > 0.15) confidence -= 15.0;  //       Fibonacci
            if(errorPercent > 3.0) confidence -= 25.0;  //    
            
            //   confidence      
            if(harmonicPattern != "NONE") confidence += 15.0;  //          
            if(isValidABCD) confidence += 10.0;  // AB=CD  
            if(waves.BC_RelativeStrength > 2.0) confidence += 10.0;  //    
            if(MathAbs(waves.AB_to_BC_Acceleration) < 0.001) confidence += 5.0;  //    
            
            //          0-100
            if(confidence < 0) confidence = 0;
            if(confidence > 100) confidence = 100;
            
            // penalty   confidence   
            double confidencePenalty = 0.0;
            if(confidence < 50.0) {
                confidencePenalty = 50.0 * (1.0 - confidence / 50.0);  // Max +50 penalty
            }
            
            // ========================================
            // 16.   HARMONIC MEAN CONSISTENCY (SCIENTIFIC - PYTHAGOREAN)
            // ========================================
            //     Harmonic Mean        
            //                   
            double harmonicMeanScore = 0.0;
            
            if(waves.XA_Speed > 0 && waves.AB_Speed > 0 && waves.BC_Speed > 0) {
                //   Harmonic Mean
                double recipSum = (1.0/waves.XA_Speed) + (1.0/waves.AB_Speed) + (1.0/waves.BC_Speed);
                double harmonicMean = 3.0 / recipSum;
                
                //   Arithmetic Mean
                double arithmeticMean = (waves.XA_Speed + waves.AB_Speed + waves.BC_Speed) / 3.0;
                
                //     Harmonic   Arithmetic
                //       1.0                      
                double meanRatio = harmonicMean / arithmeticMean;
                
                //               (meanRatio > 0.9)
                if(meanRatio > 0.9) {
                    harmonicMeanScore = -15.0 * ((meanRatio - 0.9) / 0.1);  // Max -15 bonus
                }
                // penalty        (meanRatio < 0.7)
                else if(meanRatio < 0.7) {
                    harmonicMeanScore = 15.0 * ((0.7 - meanRatio) / 0.3);  // Max +15 penalty
                }
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   Harmonic Mean: ", DoubleToString(harmonicMean, 2), " pips/min");
                Print("   Arithmetic Mean: ", DoubleToString(arithmeticMean, 2), " pips/min");
                Print("   Ratio: ", DoubleToString(meanRatio, 3), 
                      " (", meanRatio > 0.9 ? "==================== Consistent" : (meanRatio < 0.7 ? "==================== Inconsistent" : "==================== Moderate"), ")");
                #endif
            }
            
            // ========================================
            // 17.   PHI RATIO BONUS (SCIENTIFIC - GOLDEN RATIO)
            // ========================================
            //           (   = 0.618)          
            //   Self-Fulfilling Prophecy (                    
            //       (300                
            double phiRatioScore = 0.0;
            
            double phi = 1.618033988749;
            double phiInverse = 0.618033988749;
            
            //   AB/XA       0.618
            double phiDeviation_AB_XA = MathAbs(waves.AB_XA_Ratio - phiInverse);
            if(phiDeviation_AB_XA < 0.05) {  //   tolerance
                //                    
                phiRatioScore -= 20.0 * (1.0 - phiDeviation_AB_XA / 0.05);  // Max -20 bonus
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ==================== Golden Ratio detected in AB/XA: ", DoubleToString(waves.AB_XA_Ratio, 3));
                #endif
            }
            
            //   BC/AB       0.618
            double phiDeviation_BC_AB = MathAbs(waves.BC_AB_Ratio - phiInverse);
            if(phiDeviation_BC_AB < 0.05) {  //   tolerance
                phiRatioScore -= 15.0 * (1.0 - phiDeviation_BC_AB / 0.05);  // Max -15 bonus
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ==================== Golden Ratio detected in BC/AB: ", DoubleToString(waves.BC_AB_Ratio, 3));
                #endif
            }
            
            //   AB/XA       1.618 (  )
            double phiDeviation_AB_XA_ext = MathAbs(waves.AB_XA_Ratio - phi);
            if(phiDeviation_AB_XA_ext < 0.08) {  //   tolerance (      extension)
                phiRatioScore -= 12.0 * (1.0 - phiDeviation_AB_XA_ext / 0.08);  // Max -12 bonus
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ==================== Phi Extension detected in AB/XA: ", DoubleToString(waves.AB_XA_Ratio, 3));
                #endif
            }
            
            //     (  =  
            //           2        
            double totalScore = (errorScore + speedScore + timeScore + fibScore + freqScore + consolidationPenalty) 
                              * stepPriority * (1.0 + stepPriorityScore) 
                              + impulsiveBonus + harmonicBonus + medianLineBonus + abcdBonus
                              + accelerationScore + strengthScore + confidencePenalty
                              + harmonicMeanScore + phiRatioScore;  //     2        
            
            //      
            int size = ArraySize(results);
            ArrayResize(results, size + 1);
            
            results[size].frequency = testFreq;
            results[size].frequencyIndex = freqIdx;
            results[size].targetStep = testStep;
            results[size].errorPercent = errorPercent;
            results[size].calculatedD = calcD;
            results[size].targetPrice = targetPrice;
            results[size].errorPips = MathAbs(calcD - targetPrice) / pipSize;
            results[size].gannAngle = speedRatio;
            results[size].angleWeight = waves.speedConsistency;
            results[size].timeSymmetry = timeSymmetry;
            results[size].totalScore = totalScore;
        }
    }
    
    // ========================================
    //   6:          
    // ========================================
    int resultCount = ArraySize(results);
    for(int i = 0; i < resultCount - 1; i++)
    {
        int minIdx = i;
        for(int j = i + 1; j < resultCount; j++)
        {
            if(results[j].totalScore < results[minIdx].totalScore)
            {
                minIdx = j;
            }
        }
        
        if(minIdx != i)
        {
            FrequencySearchResult temp = results[i];
            results[i] = results[minIdx];
            results[minIdx] = temp;
        }
    }
    
    // ========================================
    //   7:         
    // ========================================
    int goodResults = 0;
    for(int i = 0; i < resultCount; i++)
    {
        if(results[i].errorPercent <= maxErrorPercent)
        {
            goodResults++;
        }
        else
        {
            break;
        }
    }
    
    if(goodResults > 0)
    {
        ArrayResize(results, goodResults);
        return goodResults;
    }
    else
    {
        //                threshold      
        //    10             
        int keepCount = MathMin(10, resultCount);
        ArrayResize(results, keepCount);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== No results with error < ", maxErrorPercent, "%, keeping best ", keepCount, " results");
        #endif
        
        return keepCount;
    }
}

//+------------------------------------------------------------------+
//| Auto-Select Best Frequency for Current AB=CD Pattern            |
//|                     AB=CD                  |
//+------------------------------------------------------------------+
bool AutoSelectBestFrequency(string patternName)
{
    //          A  B  C     
    string lineAB = patternName + "_Line_AB";
    string lineBC = patternName + "_Line_BC";
    
    if(ObjectFind(0, lineAB) < 0 || ObjectFind(0, lineBC) < 0) {
        Print("==================== Pattern not found: ", patternName);
        return false;
    }
    
    datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
    double pA = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 0);
    datetime tB = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 1);
    double pB = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 1);
    datetime tC = (datetime)ObjectGetInteger(0, lineBC, OBJPROP_TIME, 1);
    double pC = ObjectGetDouble(0, lineBC, OBJPROP_PRICE, 1);
    
    // CRITICAL FIX: Validate all retrieved values
    if(tA <= 0 || tB <= 0 || tC <= 0 || pA <= 0 || pB <= 0 || pC <= 0) {
        Print("==================== Invalid pattern data");
        return false;
    }
    
    // For auto-select, we don't have X point stored in pattern
    // Estimate X based on typical wave pattern structure
    //               X           
    //    X                  
    
    //             AB
    int barA = iBarShift(NULL, 0, tA);
    int barB = iBarShift(NULL, 0, tB);
    int AB_Bars = barA - barB; // A     B  
    if(AB_Bars < 1) AB_Bars = 1;
    
    //       X:           A (          
    int barX = barA + AB_Bars; // X     A
    datetime tX = iTime(NULL, 0, barX);
    
    //       
    if(tX <= 0 || tX >= tA) {
        // fallback:           AB
        tX = tA - (tB - tA);
        if(tX <= 0) tX = tA - 3600; //   1    
    }
    
    //      X          
    //       AB=CD     X    A       B    D      
    bool isABBullish = (pB > pA);
    double AB_Distance = MathAbs(pB - pA);
    double pX;
    
    if(isABBullish) {
        //   AB       (A          
        //   XA           (X           )
        //     X     A  
        pX = pA + (AB_Distance * 0.618); //   XA     61.8%   AB (Fibonacci)
    } else {
        //   AB         (A           )
        //   XA         (X          
        //     X       A  
        pX = pA - (AB_Distance * 0.618); //   XA     61.8%   AB
    }
    
    //       X                  
    if(pX <= 0) {
        if(isABBullish) {
            pX = pA + (AB_Distance * 0.5); // fallback: 50%   AB
        } else {
            pX = pA - (AB_Distance * 0.5);
        }
    }
    
    //                 A      (    
    if(pX <= 0) pX = pA;
    
    //            (  4    
    //   X             A     3          
    FrequencySearchResult results[];
    ArrayResize(results, 0); // Initialize array
    
    bool hasValidX = (MathAbs(pX - pA) > MathAbs(pB - pA) * 0.1); // X     10% AB   A      
    
    int resultCount;
    if(hasValidX) {
        //       4    
        resultCount = FindOptimalFrequencyForABCD(tX, pX, tA, pA, tB, pB, tC, pC, results, 5.0);
    } else {
        //          X (      AB    BC)
        //        X = A        pattern quality      
        resultCount = FindOptimalFrequencyForABCD(tA, pA, tA, pA, tB, pB, tC, pC, results, 5.0);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== X point estimation not reliable, using simplified analysis");
        #endif
    }
    
    if(resultCount == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== No suitable frequency found (error > 5%)");
        #endif
        return false;
    }
    
    //              
    double pipSize = GetCachedPipSize();
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== FREQUENCY SEARCH RESULTS");
    Print("Pattern: ", patternName);
    Print("AB Distance: ", DoubleToString(MathAbs(pB - pA), Digits), " (", 
          DoubleToString(MathAbs(pB - pA) / pipSize, 1), " pips)");
    Print("========================================");
    Print("==================== BEST MATCH:");
    Print("   Frequency: ", DoubleToString(results[0].frequency, 3), "% (Index: ", results[0].frequencyIndex, ")");
    Print("   Target: Step ", results[0].targetStep, " | Error: ", DoubleToString(results[0].errorPercent, 3), "% (", DoubleToString(results[0].errorPips, 1), " pips)");
    Print("   Speed: ", DoubleToString(results[0].gannAngle, 2), "x | Consistency: ", DoubleToString(results[0].angleWeight * 100, 1), "%");
    Print("   Time Symmetry: ", DoubleToString(results[0].timeSymmetry * 100, 1), "% | Total Score: ", DoubleToString(results[0].totalScore, 2));
    Print("========================================");
    Print("==================== TOP 10 ALTERNATIVES:");
    #endif
    
    int displayCount = MathMin(10, resultCount);
    for(int i = 0; i < displayCount; i++)
    {
        #ifdef ENABLE_DEBUG_LOGS
        Print(StringFormat("%d. %.3f%% ==================== Step %d | Err: %.2f%% (%.1f pips) | Speed: %.2fx | Score: %.2f",
              i + 1,
              results[i].frequency,
              results[i].targetStep,
              results[i].errorPercent,
              results[i].errorPips,
              results[i].gannAngle,
              results[i].totalScore));
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    #endif
    
    //           
    double bestFreq = results[0].frequency;
    int bestIndex = results[0].frequencyIndex;
    
    //      
    g_th3FreqOverride = bestFreq;
    g_th3FreqIndex = bestIndex;
    
    //     GlobalVariable
    // PERFORMANCE: Use cached ChartID string
    string chartIdStr = GetCachedChartIdStr();
    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
    GlobalVariableSet(freqGvarName, bestFreq);
    GlobalVariableSet(indexGvarName, bestIndex);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== Frequency applied successfully");
    #endif
    
    // Update frequency label
    UpdateTH3FrequencyLabel(bestFreq);
    
    return true;
}


//+------------------------------------------------------------------+
//| Update All TH3 Objects (when frequency changes)                 |
//|       TH3 (                               |
//+------------------------------------------------------------------+
void UpdateAllTH3Objects() {
    int updatedCount = 0;
    
    // PERF: Use pattern store — avoids ObjectsTotal(OBJ_TREND) loop + multiple ObjectGet calls
    int patCount = TH3PatternStoreCount();
    for(int i = 0; i < patCount; i++) {
        string patName = g_th3Patterns.items[i].name;
        datetime tA = g_th3Patterns.items[i].A.time; double pA = g_th3Patterns.items[i].A.price;
        datetime tB = g_th3Patterns.items[i].B.time; double pB = g_th3Patterns.items[i].B.price;
        datetime tC = g_th3Patterns.items[i].C.time; double pC = g_th3Patterns.items[i].C.price;
        
        if(tA > 0 && tB > 0 && tC > 0 && pA > 0 && pB > 0 && pC > 0) {
            DrawABCDPattern(patName, tA, pA, tB, pB, tC, pC);
            updatedCount++;
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    if(updatedCount > 0) {
        Print("==================== Updated ", updatedCount, " AB=CD patterns with frequency: ", 
              DoubleToString(GetCurrentTH3Frequency(), 3), "%");
    }
    #endif
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Register/refresh a pattern model in the store (called after      |
//| DrawABCDPattern so the in-memory model stays in sync).           |
//+------------------------------------------------------------------+
void TH3RegisterPattern(const string name, datetime tA, double pA,
                        datetime tB, double pB, datetime tC, double pC)
{
    TH3Pattern model;
    datetime tX = 0;
    double pX = 0;
    if(TH3PatternStoreGet(name, model)) {
        tX = model.X.time;
        pX = model.X.price;
    }
    if(TH3PatternBuild(name, tX, pX, tA, pA, tB, pB, tC, pC, model)) {
        model.frequency = g_th3FreqOverride;
        TH3PatternStoreAdd(model);
    }
}

//+------------------------------------------------------------------+
//| Complete a drawing session: auto-select frequency, draw the      |
//| pattern, register the model, clean up preview objects.           |
//+------------------------------------------------------------------+
void TH3CompletePattern()
{
    datetime tX, tA, tB, tC;
    double pX, pA, pB, pC;
    if(!TH3SessionGetPoint(0, tX, pX)) return;
    if(!TH3SessionGetPoint(1, tA, pA)) return;
    if(!TH3SessionGetPoint(2, tB, pB)) return;
    if(!TH3SessionGetPoint(3, tC, pC)) return;

    // AUTO-SEARCH: optimal frequency for this pattern (3-wave analysis)
    FrequencySearchResult searchResults[];
    WaveAnalysis waves;
    double consolidationFactor;
    int resultCount = FindOptimalFrequencyForABCD_WithLearningData(
        tX, pX, tA, pA, tB, pB, tC, pC,
        searchResults, waves, consolidationFactor, 5.0);

    if(resultCount > 0) {
        g_th3FreqOverride = searchResults[0].frequency;
        g_th3FreqIndex = searchResults[0].frequencyIndex;

        string chartIdStr = GetCachedChartIdStr();
        string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
        string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
        GlobalVariableSet(freqGvarName, g_th3FreqOverride);
        GlobalVariableSet(indexGvarName, g_th3FreqIndex);
    }

    string patternName = "ABCD_Pattern_" + IntegerToString((long)GetTickCount());
    DrawABCDPattern(patternName, tA, pA, tB, pB, tC, pC);

    // Register the full model (including X) in the store
    TH3Pattern model;
    if(TH3PatternBuild(patternName, tX, pX, tA, pA, tB, pB, tC, pC, model)) {
        model.frequency = g_th3FreqOverride;
        TH3PatternStoreAdd(model);
    }

    SetActiveABCDPattern(patternName);
    TH3PreviewClear();
    UpdateTH3FrequencyLabel(g_th3FreqOverride);
    ChartRedraw();
    Print("TH3: AB=CD pattern created: ", patternName);
}

//+------------------------------------------------------------------+
//| Unified mouse/key event dispatcher for the TH3 drawing tool.     |
//| State lives in TH3DrawingSession (TH3Controller.mqh) - no more   |
//| scattered g_abcd* globals.                                       |
//+------------------------------------------------------------------+
void OnABCDMouseEvent(int id, long lparam, double dparam, string sparam) {
    // ---- Mouse move: right-click cancel, left-click placement ----
    if(id == CHARTEVENT_MOUSE_MOVE) {
        int mouseState = (int)StringToInteger(sparam);
        bool rightButtonDown = (mouseState & 2) == 2;
        bool leftButtonDown = (mouseState & 1) == 1;

        if(rightButtonDown && TH3SessionActive()) {
            TH3SessionCancel();
            return;
        }

        static bool s_lastLeftButtonState = false;
        if(TH3SessionActive() && leftButtonDown && !s_lastLeftButtonState) {
            s_lastLeftButtonState = true;

            uint currentTime = GetTickCount();
            if(currentTime - g_th3Session.lastClickTime < ABCD_DEBOUNCE_MS) return;
            g_th3Session.lastClickTime = currentTime;

            int subWindow;
            datetime clickTime;
            double clickPrice;
            if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, clickTime, clickPrice)) return;

            TH3SessionAddPoint(clickTime, clickPrice);
            if(g_th3Session.state == TH3_SESSION_COMPLETE) {
                TH3CompletePattern();
            }
        }
        else if(!leftButtonDown && s_lastLeftButtonState) {
            s_lastLeftButtonState = false;
        }

        // LIVE PREVIEW: project the next point under the cursor
        if(TH3SessionActive()) {
            int subWindow;
            datetime hoverTime;
            double hoverPrice;
            if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, hoverTime, hoverPrice)) {
                TH3SessionSetHover(hoverTime, hoverPrice);
                TH3PreviewUpdateHover(hoverTime, hoverPrice);
            }
        }
        return;
    }

    // ---- CHARTEVENT_CLICK fallback ----
    if(id == CHARTEVENT_CLICK && TH3SessionActive()) {
        uint currentTime = GetTickCount();
        if(currentTime - g_th3Session.lastClickTime < ABCD_DEBOUNCE_MS) return;
        g_th3Session.lastClickTime = currentTime;

        int subWindow;
        datetime clickTime;
        double clickPrice;
        if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, clickTime, clickPrice)) return;

        TH3SessionAddPoint(clickTime, clickPrice);
        if(g_th3Session.state == TH3_SESSION_COMPLETE) {
            TH3CompletePattern();
        }
        return;
    }

    // ---- Drag points A/B/C with smart OHLC snapping ----
    if(id == CHARTEVENT_OBJECT_DRAG) {
        if(StringFind(sparam, "ABCD_Pattern_") == 0 && StringFind(sparam, "_Point_") > 0) {
            int pointPos = StringFind(sparam, "_Point_");
            string baseName = StringSubstr(sparam, 0, pointPos);
            string pointName = StringSubstr(sparam, pointPos + 7);

            if(pointName != "A" && pointName != "B" && pointName != "C") return;
            SetActiveABCDPattern(baseName);

            // SMART MAGNET: snap to nearest OHLC within 5 pips
            string draggedPoint = baseName + "_Point_" + pointName;
            datetime newTime = (datetime)ObjectGetInteger(0, draggedPoint, OBJPROP_TIME, 0);
            double newPrice = ObjectGetDouble(0, draggedPoint, OBJPROP_PRICE, 0);

            int barIndex = iBarShift(NULL, 0, newTime);
            if(barIndex >= 0) {
                double high = iHigh(NULL, 0, barIndex);
                double low = iLow(NULL, 0, barIndex);
                double open = iOpen(NULL, 0, barIndex);
                double close = iClose(NULL, 0, barIndex);

                double pipSize = GetCachedPipSize();
                double distToHigh = MathAbs(newPrice - high) / pipSize;
                double distToLow = MathAbs(newPrice - low) / pipSize;
                double distToOpen = MathAbs(newPrice - open) / pipSize;
                double distToClose = MathAbs(newPrice - close) / pipSize;

                double snapThreshold = 5.0;
                double minDist = MathMin(MathMin(distToHigh, distToLow), MathMin(distToOpen, distToClose));

                if(minDist <= snapThreshold) {
                    if(minDist == distToHigh)       newPrice = high;
                    else if(minDist == distToLow)   newPrice = low;
                    else if(minDist == distToClose) newPrice = close;
                    else if(minDist == distToOpen)  newPrice = open;
                    ObjectSetDouble(0, draggedPoint, OBJPROP_PRICE, newPrice);
                }
            }

            string lineAB = baseName + "_Line_AB";
            string lineBC = baseName + "_Line_BC";
            if(ObjectFind(0, lineAB) < 0 || ObjectFind(0, lineBC) < 0) return;

            datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
            double pA = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 0);
            datetime tB = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 1);
            double pB = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 1);
            datetime tC = (datetime)ObjectGetInteger(0, lineBC, OBJPROP_TIME, 1);
            double pC = ObjectGetDouble(0, lineBC, OBJPROP_PRICE, 1);

            if(pointName == "A")       { tA = newTime; pA = newPrice; }
            else if(pointName == "B")  { tB = newTime; pB = newPrice; }
            else if(pointName == "C")  { tC = newTime; pC = newPrice; }

            DrawABCDPattern(baseName, tA, pA, tB, pB, tC, pC);
            TH3RegisterPattern(baseName, tA, pA, tB, pB, tC, pC);
        }
        return;
    }

    // ---- Pattern deletion: full object cleanup + store unregister ----
    if(id == CHARTEVENT_OBJECT_DELETE) {
        if(StringFind(sparam, "ABCD_Pattern_") == 0) {
            string baseName = sparam;
            string suffixes[7];
            suffixes[0] = TH3_SUFFIX_LINE_AB;
            suffixes[1] = TH3_SUFFIX_LINE_BC;
            suffixes[2] = TH3_SUFFIX_TARGET;
            suffixes[3] = TH3_SUFFIX_POINT;
            suffixes[4] = TH3_SUFFIX_LABEL;
            suffixes[5] = TH3_SUFFIX_INFO;
            suffixes[6] = TH3_SUFFIX_ZONE;

            for(int s = 0; s < ArraySize(suffixes); s++) {
                int pos = StringFind(baseName, suffixes[s]);
                if(pos > 0) {
                    baseName = StringSubstr(baseName, 0, pos);
                    break;
                }
            }

            if(StringFind(baseName, "ABCD_Pattern_") != 0 || StringLen(baseName) < 20) return;

            // 1. Drag points + labels
            string pointNames[3] = {"A", "B", "C"};
            for(int i = 0; i < 3; i++) {
                ObjectDelete(0, baseName + "_Point_" + pointNames[i]);
                ObjectDelete(0, baseName + "_Label_" + pointNames[i]);
            }
            // 2. Lines
            ObjectDelete(0, baseName + "_Line_AB");
            ObjectDelete(0, baseName + "_Line_BC");
            // 3. Info label
            ObjectDelete(0, baseName + "_Info");
            // 4. Targets + zones
            for(int i = 1; i <= 7; i++) {
                ObjectDelete(0, baseName + "_Target_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_ZoneUpper_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_ZoneLower_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_Zone_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_Zone_" + IntegerToString(i) + "_B_Top");
                ObjectDelete(0, baseName + "_Zone_" + IntegerToString(i) + "_B_Bottom");
                ObjectDelete(0, baseName + "_Zone_" + IntegerToString(i) + "_B_Left");
            }
            // 5. Temp objects
            ObjectDelete(0, baseName + "_Temp_X");
            ObjectDelete(0, baseName + "_Temp_A");
            ObjectDelete(0, baseName + "_Temp_B");
            ObjectDelete(0, baseName + "_Temp_C");
            ObjectDelete(0, baseName + "_Temp_Line_XA");
            ObjectDelete(0, baseName + "_Temp_Line_AB");
            ObjectDelete(0, baseName + "_Temp_Line_BC");

            // 6. Active pattern + store
            if(g_activeABCDPattern == baseName) {
                SetActiveABCDPattern("");
            }
            TH3PatternStoreRemove(baseName);

            ChartRedraw();
        }
    }
}

//+------------------------------------------------------------------+
//| Toggle TH3 Tool (V key) - start/cancel drawing session           |
//+------------------------------------------------------------------+
void ToggleTH3Tool() {
    if(!inpEnableTH3Tool) return;

    if(inpTH3DrawingMode == TH3_MODE_ABCD) {
        if(!TH3SessionActive()) {
            TH3SessionStart();
        } else {
            TH3SessionCancel();
        }
    }
}



//+------------------------------------------------------------------+
//| Cycle TH3 Frequency (Keys 3 and 4)                              |
//|         TH3 (  3    4)                                 |
//+------------------------------------------------------------------+
void CycleTH3Frequency() {
    if(g_th3FreqIndex < MIN_TH3_FREQ_INDEX || g_th3FreqIndex > MAX_TH3_FREQ_INDEX) {
        g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
    }
    
    g_th3FreqIndex++;
    if(g_th3FreqIndex > MAX_TH3_FREQ_INDEX)
        g_th3FreqIndex = MIN_TH3_FREQ_INDEX;
    g_th3FreqOverride = GetFrequencyByIndex(g_th3FreqIndex);
    
    // ========================================
    
    UpdateAllTH3Objects();
    
    // Update frequency label
    UpdateTH3FrequencyLabel(g_th3FreqOverride);
    
    Print("==================== TH3 Frequency: ", DoubleToString(g_th3FreqOverride, 3), "%");
}

void DecrementTH3Frequency() {
    if(g_th3FreqIndex < MIN_TH3_FREQ_INDEX || g_th3FreqIndex > MAX_TH3_FREQ_INDEX) {
        g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
    }
    
    g_th3FreqIndex--;
    if(g_th3FreqIndex < MIN_TH3_FREQ_INDEX)
        g_th3FreqIndex = MAX_TH3_FREQ_INDEX;
    g_th3FreqOverride = GetFrequencyByIndex(g_th3FreqIndex);
    
    // ========================================
    
    UpdateAllTH3Objects();
    
    // Update frequency label
    UpdateTH3FrequencyLabel(g_th3FreqOverride);
    
    Print("==================== TH3 Frequency: ", DoubleToString(g_th3FreqOverride, 3), "%");
}


//+------------------------------------------------------------------+
//| Find Optimal Frequency with Learning Data                        |
//|                                        |
//| Returns: result count + fills waves and consolidation params    |
//+------------------------------------------------------------------+
int FindOptimalFrequencyForABCD_WithLearningData(
    datetime tX, double pX, datetime tA, double pA,
    datetime tB, double pB, datetime tC, double pC,
    FrequencySearchResult &results[],
    WaveAnalysis &waves_out,
    double &consolidationFactor_out,
    double maxErrorPercent = 5.0)
{
    //        
    ArrayResize(results, 0);
    
    double AB_Distance = MathAbs(pB - pA);
    if(AB_Distance <= 0) return 0;
    
    //      
    waves_out = AnalyzeThreeWaves(tX, pX, tA, pA, tB, pB, tC, pC);
    
    //   consolidation (    waves    
    consolidationFactor_out = CalculateConsolidationFactor(tA, tB, tC, waves_out);
    
    //          
    int resultCount = FindOptimalFrequencyForABCD(tX, pX, tA, pA, tB, pB, tC, pC, results, maxErrorPercent);
    
    return resultCount;
}

#endif // TH3_TOOL_MQH

