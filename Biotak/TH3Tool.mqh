   //+------------------------------------------------------------------+
//|                                                      TH3Tool.mqh |
//|                     TH3 Structure Tool (Proprietary Logic)       |
//|                     Supports: Steps Mode & AB=CD Pattern Mode    |
//+------------------------------------------------------------------+
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

// Global state for TH3 Tool Drawing Mode
bool g_th3ToolEnabled = false;
bool g_isDrawingTH3 = false;
bool g_isDraggingTH3 = false;
string g_currentDrawingObject = "";
int g_th3DraggingHandle = -1;
string g_th3DraggingObject = "";

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

double SnapToOHLC(datetime barTime, double price, double pipSize)
{
    if(pipSize <= 0) pipSize = GetCachedPipSize();
    if(pipSize <= 0) return price;
    int barIndex = iBarShift(Symbol(), Period(), barTime);
    if(barIndex < 0) return price;
    double ohlc[4];
    ohlc[0] = iHigh(Symbol(), 0, barIndex);
    ohlc[1] = iLow(Symbol(), 0, barIndex);
    ohlc[2] = iClose(Symbol(), 0, barIndex);
    ohlc[3] = iOpen(Symbol(), 0, barIndex);
    double minDist = DBL_MAX;
    double snapped = price;
    for(int i = 0; i < 4; i++) {
        double dist = MathAbs(price - ohlc[i]) / pipSize;
        if(dist < minDist) {
            minDist = dist;
            snapped = ohlc[i];
        }
    }
    return (minDist <= TH3_SNAP_THRESHOLD_PIPS) ? snapped : price;
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
    int safeY = GetABCDInfoSafeYDistance();
    int totalObjects = ObjectsTotal(0, -1, -1);
    for(int i = 0; i < totalObjects; i++) {
        string name = ObjectName(0, i);
        if(StringFind(name, TH3_PATTERN_PREFIX) == 0 &&
           StringFind(name, TH3_SUFFIX_INFO) > 0) {
            ObjectSetInteger(0, name, OBJPROP_YDISTANCE, safeY);
        }
    }
}

//+------------------------------------------------------------------+
//| Get Cached Daily ATR (Performance Optimization)                 |
//|              ATR                   Cache (                                  )                  |
//| Caches ATR for current bar to avoid repeated calculations       |
//+------------------------------------------------------------------+
double GetCachedDailyATR()
{
    static double cachedATR = 0;
    static int cachedBar = -1;
    
    int currentBar = iBars(NULL, PERIOD_D1);  // MQL4:   2  
    
    //             ATR            
    if(currentBar != cachedBar || IsZero(cachedATR, EPSILON_PRICE)) {
        double atrValue = iATR(NULL, PERIOD_D1, 14, 0);
        cachedBar = currentBar;
        
        // CRITICAL FIX: Check for EMPTY_VALUE which iATR returns on error
        // Also check for invalid values using epsilon comparison
        double pipSize = GetCachedPipSize();
        double minATR = pipSize * 10;  // Minimum 10 pips
        if(atrValue == EMPTY_VALUE || IsZero(atrValue, EPSILON_PRICE) || atrValue < minATR) {
            // Fallback: Calculate average range manually
            double avgRange = 0;
            int validBars = 0;
            for(int i = 1; i <= 20; i++) {
                double high = iHigh(NULL, PERIOD_D1, i);
                double low = iLow(NULL, PERIOD_D1, i);
                // Validate OHLC data
                if(high != EMPTY_VALUE && low != EMPTY_VALUE && high > low) {
                    avgRange += (high - low);
                    validBars++;
                }
            }
            cachedATR = (validBars > 0) ? (avgRange / validBars) : pipSize * 100;  // Default to 100 pips
        } else {
            cachedATR = atrValue;
        }
    }
    
    return cachedATR;
}

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
    
    //                                
    // Step 5      (     50%)
    // Step 3    7     25%         
    double weightedFreq = (GetFrequencyByIndex(bestIndices[0]) * 0.25) +
                          (GetFrequencyByIndex(bestIndices[1]) * 0.50) +
                          (GetFrequencyByIndex(bestIndices[2]) * 0.25);
    
    //                               
    int bestDefaultIdx = FindNearestFreqIndex(weightedFreq);
    double bestDefault = GetFrequencyByIndex(bestDefaultIdx);
    
    Print("==================== RECOMMENDED DEFAULT FREQUENCY:");
    Print("  Weighted Average: ", DoubleToString(weightedFreq, 3), "%");
    Print("  Best Match: ", DoubleToString(bestDefault, 3), "% (Index: ", bestDefaultIdx, ")");
    Print("========================================");
    
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
struct WaveAnalysis {
    // Wave lengths (price)
    double XA_Distance;
    double AB_Distance;
    double BC_Distance;
    
    // Wave durations (time)
    int XA_Minutes;
    int AB_Minutes;
    int BC_Minutes;
    
    // Wave speeds (pips per minute)
    double XA_Speed;
    double AB_Speed;
    double BC_Speed;
    
    // Wave angles (Gann angles in degrees)
    double XA_Angle;
    double AB_Angle;
    double BC_Angle;
    
    // Wave ratios
    double AB_XA_Ratio;      // AB/XA (Fibonacci: 0.382, 0.5, 0.618, 0.786, 1.0, 1.272, 1.618)
    double BC_AB_Ratio;      // BC/AB
    
    // Time ratios
    double AB_XA_TimeRatio;  //    AB /    XA
    double BC_AB_TimeRatio;  //    BC /    AB
    
    // Speed ratios
    double AB_XA_SpeedRatio; //   AB /   XA
    double BC_AB_SpeedRatio; //   BC /   AB
    
    // Acceleration (            )
    double XA_to_AB_Acceleration;  //     XA   AB (pips/min 
    double AB_to_BC_Acceleration;  //     AB   BC (pips/min 
    
    // Strength levels (    leg)
    double XA_RawStrength;       //     XA (pips/min)
    double AB_RawStrength;       //     AB
    double BC_RawStrength;       //     BC
    double XA_WeightedStrength;  //         XA (     
    double AB_WeightedStrength;  //         AB
    double BC_WeightedStrength;  //         BC
    double XA_RelativeStrength;  //       XA (      ATR)
    double AB_RelativeStrength;  //       AB
    double BC_RelativeStrength;  //       BC
    
    // Pattern characteristics
    bool isImpulsive;        //      impulsive   (       
    bool isCorrectional;     //      correctional   ( 
    double avgSpeed;         //             
    double speedConsistency; //     (0-1  1 =    
    double timeSymmetry;     //        BC   AB (0-1  1 =     
};

WaveAnalysis AnalyzeThreeWaves(datetime tX, double pX, datetime tA, double pA,
                                datetime tB, double pB, datetime tC, double pC)
{
    WaveAnalysis analysis;
    double pipSize = GetCachedPipSize();
    
    // SECURITY: Validate time ordering (X < A < B < C)
    if(!(tX < tA && tA < tB && tB < tC)) {
        Print("==================== AnalyzeThreeWaves: Invalid time ordering (X < A < B < C required)");
        Print("   tX=", TimeToString(tX), ", tA=", TimeToString(tA), ", tB=", TimeToString(tB), ", tC=", TimeToString(tC));
        // Return default values
        analysis.XA_Distance = 0;
        analysis.AB_Distance = 0;
        analysis.BC_Distance = 0;
        analysis.XA_Minutes = 1;
        analysis.AB_Minutes = 1;
        analysis.BC_Minutes = 1;
        analysis.XA_Speed = 0;
        analysis.AB_Speed = 0;
        analysis.BC_Speed = 0;
        analysis.XA_Angle = 0;
        analysis.AB_Angle = 0;
        analysis.BC_Angle = 0;
        analysis.AB_XA_Ratio = 1;
        analysis.BC_AB_Ratio = 1;
        analysis.AB_XA_TimeRatio = 1;
        analysis.BC_AB_TimeRatio = 1;
        analysis.AB_XA_SpeedRatio = 1;
        analysis.BC_AB_SpeedRatio = 1;
        analysis.isImpulsive = false;
        analysis.isCorrectional = false;
        analysis.avgSpeed = 0;
        analysis.speedConsistency = 0;
        analysis.timeSymmetry = 0;
        return analysis;
    }
    
    //           ( 
    analysis.XA_Distance = MathAbs(pA - pX);
    analysis.AB_Distance = MathAbs(pB - pA);
    analysis.BC_Distance = MathAbs(pC - pB);
    
    //            ( 
    analysis.XA_Minutes = (int)((tA - tX) / 60);
    analysis.AB_Minutes = (int)((tB - tA) / 60);
    analysis.BC_Minutes = (int)((tC - tB) / 60);
    
    //            
    if(analysis.XA_Minutes <= 0) analysis.XA_Minutes = 1;
    if(analysis.AB_Minutes <= 0) analysis.AB_Minutes = 1;
    if(analysis.BC_Minutes <= 0) analysis.BC_Minutes = 1;
    
    // CRITICAL FIX: Validate division operands with epsilon check
    if(MathAbs(analysis.AB_Minutes) < 0.001) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== CalculateWaveAnalysis: AB_Minutes too small (", analysis.AB_Minutes, "), cannot calculate speed");
        #endif
        analysis.AB_Speed = 0;
    } else {
        analysis.AB_Speed = (analysis.AB_Distance / pipSize) / analysis.AB_Minutes;
    }
    
    if(MathAbs(analysis.XA_Minutes) < 0.001) {
        analysis.XA_Speed = 0;
    } else {
        analysis.XA_Speed = (analysis.XA_Distance / pipSize) / analysis.XA_Minutes;
    }
    
    if(MathAbs(analysis.BC_Minutes) < 0.001) {
        analysis.BC_Speed = 0;
    } else {
        analysis.BC_Speed = (analysis.BC_Distance / pipSize) / analysis.BC_Minutes;
    }
    
    //       Gann (     
    analysis.XA_Angle = CalculateWaveAngle(tX, pX, tA, pA);
    analysis.AB_Angle = CalculateWaveAngle(tA, pA, tB, pB);
    analysis.BC_Angle = CalculateWaveAngle(tB, pB, tC, pC);
    
    //        
    analysis.AB_XA_Ratio = (analysis.XA_Distance > 0) ? (analysis.AB_Distance / analysis.XA_Distance) : 1.0;
    analysis.BC_AB_Ratio = (analysis.AB_Distance > 0) ? (analysis.BC_Distance / analysis.AB_Distance) : 1.0;
    
    //         
    analysis.AB_XA_TimeRatio = (double)analysis.AB_Minutes / analysis.XA_Minutes;
    analysis.BC_AB_TimeRatio = (double)analysis.BC_Minutes / analysis.AB_Minutes;
    
    //        
    analysis.AB_XA_SpeedRatio = (analysis.XA_Speed > 0) ? (analysis.AB_Speed / analysis.XA_Speed) : 1.0;
    analysis.BC_AB_SpeedRatio = (analysis.AB_Speed > 0) ? (analysis.BC_Speed / analysis.AB_Speed) : 1.0;
    
    // ========================================
    //   ACCELERATION ANALYSIS (  -    
    // ========================================
    //     Acceleration =      
    //           (a =   /  
    
    //     XA   AB
    double velocityChange_XA_AB = analysis.AB_Speed - analysis.XA_Speed;
    analysis.XA_to_AB_Acceleration = velocityChange_XA_AB / MathMax(analysis.AB_Minutes, 1);
    
    //     AB   BC
    double velocityChange_AB_BC = analysis.BC_Speed - analysis.AB_Speed;
    analysis.AB_to_BC_Acceleration = velocityChange_AB_BC / MathMax(analysis.BC_Minutes, 1);
    
    // SECURITY:   NaN
    if(analysis.XA_to_AB_Acceleration != analysis.XA_to_AB_Acceleration) analysis.XA_to_AB_Acceleration = 0;
    if(analysis.AB_to_BC_Acceleration != analysis.AB_to_BC_Acceleration) analysis.AB_to_BC_Acceleration = 0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== ACCELERATION ANALYSIS:");
    Print("   XA====================AB: ", DoubleToString(analysis.XA_to_AB_Acceleration, 4), " pips/min====================");
    if(analysis.XA_to_AB_Acceleration > 0.001) {
        Print("      ==================== ACCELERATING: Speed increasing (getting stronger)");
    } else if(analysis.XA_to_AB_Acceleration < -0.001) {
        Print("      ==================== DECELERATING: Speed decreasing (getting weaker)");
    } else {
        Print("      ==================== CONSTANT: Speed stable");
    }
    
    Print("   AB====================BC: ", DoubleToString(analysis.AB_to_BC_Acceleration, 4), " pips/min====================");
    if(analysis.AB_to_BC_Acceleration > 0.001) {
        Print("      ==================== ACCELERATING: Correction speeding up");
    } else if(analysis.AB_to_BC_Acceleration < -0.001) {
        Print("      ==================== DECELERATING: Correction slowing down");
    } else {
        Print("      ==================== CONSTANT: Correction speed stable");
    }
    Print("========================================");
    #endif
    
    // ========================================
    //   LEG STRENGTH ANALYSIS (      leg)
    // ========================================
    //     Velocity = Distance   Time (pips/min)
    //               TradingView Time-Price Velocity
    
    //       (Raw Strength) = Velocity
    analysis.XA_RawStrength = (analysis.XA_Distance / pipSize) / MathMax(analysis.XA_Minutes, 1);
    analysis.AB_RawStrength = (analysis.AB_Distance / pipSize) / MathMax(analysis.AB_Minutes, 1);
    analysis.BC_RawStrength = (analysis.BC_Distance / pipSize) / MathMax(analysis.BC_Minutes, 1);
    
    // SECURITY:   NaN
    if(analysis.XA_RawStrength != analysis.XA_RawStrength) analysis.XA_RawStrength = 0;
    if(analysis.AB_RawStrength != analysis.AB_RawStrength) analysis.AB_RawStrength = 0;
    if(analysis.BC_RawStrength != analysis.BC_RawStrength) analysis.BC_RawStrength = 0;
    
    //           (Weighted Strength)
    //                    =    
    //     Weighted = Raw   sin(angle)
    double angleWeight_XA = MathSin(analysis.XA_Angle * M_PI / 180.0);  // 0-1
    double angleWeight_AB = MathSin(analysis.AB_Angle * M_PI / 180.0);
    double angleWeight_BC = MathSin(analysis.BC_Angle * M_PI / 180.0);
    
    analysis.XA_WeightedStrength = analysis.XA_RawStrength * angleWeight_XA;
    analysis.AB_WeightedStrength = analysis.AB_RawStrength * angleWeight_AB;
    analysis.BC_WeightedStrength = analysis.BC_RawStrength * angleWeight_BC;
    
    // SECURITY:   NaN
    if(analysis.XA_WeightedStrength != analysis.XA_WeightedStrength) analysis.XA_WeightedStrength = 0;
    if(analysis.AB_WeightedStrength != analysis.AB_WeightedStrength) analysis.AB_WeightedStrength = 0;
    if(analysis.BC_WeightedStrength != analysis.BC_WeightedStrength) analysis.BC_WeightedStrength = 0;
    
    // ========================================
    // OPTIMIZATION:     ATR      
    // ========================================
    double dailyATR = GetCachedDailyATR();
    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0;  // ATR per minute
    
    if(referenceSpeed <= 0) referenceSpeed = 0.1;
    
    //         (Relative Strength)
    //     ATR            
    //     Relative = Weighted   (ATR per minute)
    //     TradingView ATR Normalization
    analysis.XA_RelativeStrength = analysis.XA_WeightedStrength / referenceSpeed;
    analysis.AB_RelativeStrength = analysis.AB_WeightedStrength / referenceSpeed;
    analysis.BC_RelativeStrength = analysis.BC_WeightedStrength / referenceSpeed;
    
    // SECURITY:   NaN
    if(analysis.XA_RelativeStrength != analysis.XA_RelativeStrength) analysis.XA_RelativeStrength = 0;
    if(analysis.AB_RelativeStrength != analysis.AB_RelativeStrength) analysis.AB_RelativeStrength = 0;
    if(analysis.BC_RelativeStrength != analysis.BC_RelativeStrength) analysis.BC_RelativeStrength = 0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== LEG STRENGTH ANALYSIS:");
    Print("   XA: Raw=", DoubleToString(analysis.XA_RawStrength, 2), 
          " | Weighted=", DoubleToString(analysis.XA_WeightedStrength, 2),
          " | Relative=", DoubleToString(analysis.XA_RelativeStrength, 2), "x ATR");
    Print("   AB: Raw=", DoubleToString(analysis.AB_RawStrength, 2), 
          " | Weighted=", DoubleToString(analysis.AB_WeightedStrength, 2),
          " | Relative=", DoubleToString(analysis.AB_RelativeStrength, 2), "x ATR");
    Print("   BC: Raw=", DoubleToString(analysis.BC_RawStrength, 2), 
          " | Weighted=", DoubleToString(analysis.BC_WeightedStrength, 2),
          " | Relative=", DoubleToString(analysis.BC_RelativeStrength, 2), "x ATR");
    
    //        leg
    string strongestLeg = "XA";
    double maxStrength = analysis.XA_RelativeStrength;
    if(analysis.AB_RelativeStrength > maxStrength) {
        strongestLeg = "AB";
        maxStrength = analysis.AB_RelativeStrength;
    }
    if(analysis.BC_RelativeStrength > maxStrength) {
        strongestLeg = "BC";
        maxStrength = analysis.BC_RelativeStrength;
    }
    
    Print("   ==================== Strongest Leg: ", strongestLeg, " (", DoubleToString(maxStrength, 2), "x ATR)");
    
    //          
    if(maxStrength > 3.0) {
        Print("   ==================== VERY STRONG: Explosive movement detected");
    } else if(maxStrength > 2.0) {
        Print("   ==================== STRONG: Powerful movement");
    } else if(maxStrength > 1.0) {
        Print("   ==================== MODERATE: Normal strength");
    } else {
        Print("   ==================== WEAK: Low momentum");
    }
    Print("========================================");
    #endif
    
    // ========================================
    //            (      referenceSpeed)
    // ========================================
    // Impulsive:              (   
    // Correctional:              (    )
    analysis.avgSpeed = (analysis.XA_Speed + analysis.AB_Speed + analysis.BC_Speed) / 3.0;
    
    //       (           
    //     StdDev =     - mean)  / n)
    double speedVariance = MathPow(analysis.XA_Speed - analysis.avgSpeed, 2) +
                          MathPow(analysis.AB_Speed - analysis.avgSpeed, 2) +
                          MathPow(analysis.BC_Speed - analysis.avgSpeed, 2);
    double speedStdDev = MathSqrt(speedVariance / 3.0);
    analysis.speedConsistency = (analysis.avgSpeed > 0) ? (1.0 - MathMin(speedStdDev / analysis.avgSpeed, 1.0)) : 0.5;
    
    // SECURITY:   NaN
    if(analysis.speedConsistency != analysis.speedConsistency) analysis.speedConsistency = 0.5;
    
    //   impulsive vs correctional (      referenceSpeed)
    double avgSpeedRatio = analysis.avgSpeed / referenceSpeed;
    analysis.isImpulsive = (avgSpeedRatio > 1.2);      //       120%     
    analysis.isCorrectional = (avgSpeedRatio < 0.8);   //       80%     
    
    //          (     
    analysis.timeSymmetry = CalculateTimeSymmetry(tA, tB, tC);
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Calculate Wave Angle (Gann Angle)                               |
//|           (    Gann)                                    |
//| Returns: Angle in degrees (0-90)                                |
//| Logic: angle = atan(price_change / time_change)                 |
//+------------------------------------------------------------------+
double CalculateWaveAngle(datetime tStart, double pStart, datetime tEnd, double pEnd)
{
    // SECURITY: Validate inputs
    if(tEnd <= tStart) {
        Print("==================== CalculateWaveAngle: Invalid time range");
        return 0;
    }
    if(pStart <= 0 || pEnd <= 0) {
        Print("==================== CalculateWaveAngle: Invalid prices");
        return 0;
    }
    
    //            
    double priceChange = MathAbs(pEnd - pStart);
    int timeChangeMinutes = (int)((tEnd - tStart) / 60);
    if(timeChangeMinutes <= 0) timeChangeMinutes = 1;
    
    //          
    double pipSize = GetCachedPipSize();
    double priceInPips = priceChange / pipSize;
    
    //       (degrees)
    //     1 pip per minute = 45 degrees (Gann 1 
    // OPTIMIZATION: Use cached ATR instead of repeated iATR() calls
    double dailyATR = GetCachedDailyATR();
    double minATR = pipSize * 10;  // Minimum 10 pips worth of ATR
    if(dailyATR <= 0 || dailyATR < minATR) {
        double avgRange = 0;
        for(int i = 1; i <= 20; i++) {
            avgRange += (iHigh(NULL, PERIOD_D1, i) - iLow(NULL, PERIOD_D1, i));
        }
        dailyATR = avgRange / 20.0;
    }
    
    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0; // pips per minute
    if(referenceSpeed <= 0) referenceSpeed = 0.1;
    
    //      
    double actualSpeed = priceInPips / timeChangeMinutes;
    
    //       (1.0 = 45 degrees)
    double speedRatio = actualSpeed / referenceSpeed;
    
    //        
    // speedRatio = 0     0 
    // speedRatio = 1     45  (Gann 1 
    // speedRatio = 2     63.43  (Gann 2 
    // speedRatio = 3     71.57  (Gann 3 
    // speedRatio             90 
    double angle = MathArctan(speedRatio) * 180.0 / M_PI;
    
    // SECURITY:   NaN
    if(angle != angle) angle = 0;  // NaN check
    
    //            0-90
    if(angle < 0) angle = 0;
    if(angle > 90) angle = 90;
    
    return angle;
}

//+------------------------------------------------------------------+
//| Calculate Required Rest Candles Based on Angle                  |
//|                                      |
//| Returns: Number of candles needed for rest/correction           |
//| CRITICAL FIX: Complete integer overflow protection               |
//+------------------------------------------------------------------+

// Constants for angle thresholds (no magic numbers)
#define ANGLE_SPIKE_THRESHOLD 80.0
#define ANGLE_STRONG_THRESHOLD 55.0
#define ANGLE_BALANCED_THRESHOLD 40.0
#define ANGLE_SLOW_THRESHOLD 25.0

#define REST_SPIKE_BASE 3
#define REST_SPIKE_MAX 4
#define REST_STRONG_BASE 7
#define REST_STRONG_MAX 9
#define REST_BALANCED_BASE 15
#define REST_BALANCED_MAX 17
#define REST_SLOW_BASE 26
#define REST_SLOW_MAX 33
#define REST_VERY_SLOW_BASE 33
#define REST_VERY_SLOW_MAX 50

#define MAX_MOVEMENT_CANDLES 10000
#define MAX_REST_CANDLES 1000

int CalculateRequiredRestCandles(double angle, int movementCandles)
{
    //  
    // CRITICAL FIX #1: Validate movementCandles to prevent overflow
    //  
    if(movementCandles < 0) {
        Print("==================== CalculateRequiredRestCandles: Negative movementCandles (", 
              movementCandles, "), setting to 0");
        movementCandles = 0;
    }
    if(movementCandles > MAX_MOVEMENT_CANDLES) {
        Print("==================== CalculateRequiredRestCandles: movementCandles too large (", 
              movementCandles, "), clamping to ", MAX_MOVEMENT_CANDLES);
        movementCandles = MAX_MOVEMENT_CANDLES;
    }
    
    //  
    // CRITICAL FIX #2: Validate angle
    //  
    if(angle < 0) angle = 0;
    if(angle > 90) angle = 90;
    
    int restCandles = 0;
    
    //  
    // CRITICAL FIX #3: Safe calculation with overflow checks
    //  
    if(angle >= ANGLE_SPIKE_THRESHOLD) {
        // Spike (80-90       
        double temp = movementCandles * 0.1;
        if(temp > INT_MAX - REST_SPIKE_BASE) {
            restCandles = REST_SPIKE_MAX;
        } else {
            restCandles = REST_SPIKE_BASE + (int)temp;
            if(restCandles > REST_SPIKE_MAX) restCandles = REST_SPIKE_MAX;
        }
    }
    else if(angle >= ANGLE_STRONG_THRESHOLD) {
        // Strong (55-80     
        double temp = movementCandles * 0.15;
        if(temp > INT_MAX - REST_STRONG_BASE) {
            restCandles = REST_STRONG_MAX;
        } else {
            restCandles = REST_STRONG_BASE + (int)temp;
            if(restCandles > REST_STRONG_MAX) restCandles = REST_STRONG_MAX;
        }
    }
    else if(angle >= ANGLE_BALANCED_THRESHOLD) {
        // Balanced (40-55    (    Gann 1 
        double temp = movementCandles * 0.2;
        if(temp > INT_MAX - REST_BALANCED_BASE) {
            restCandles = REST_BALANCED_MAX;
        } else {
            restCandles = REST_BALANCED_BASE + (int)temp;
            if(restCandles > REST_BALANCED_MAX) restCandles = REST_BALANCED_MAX;
        }
    }
    else if(angle >= ANGLE_SLOW_THRESHOLD) {
        // Slow (25-40     
        double temp = movementCandles * 0.25;
        if(temp > INT_MAX - REST_SLOW_BASE) {
            restCandles = REST_SLOW_MAX;
        } else {
            restCandles = REST_SLOW_BASE + (int)temp;
            if(restCandles > REST_SLOW_MAX) restCandles = REST_SLOW_MAX;
        }
    }
    else {
        // Very Slow (< 25       
        double temp = movementCandles * 0.3;
        if(temp > INT_MAX - REST_VERY_SLOW_BASE) {
            restCandles = REST_VERY_SLOW_MAX;
        } else {
            restCandles = REST_VERY_SLOW_BASE + (int)temp;
            if(restCandles > REST_VERY_SLOW_MAX) restCandles = REST_VERY_SLOW_MAX;
        }
    }
    
    //  
    // CRITICAL FIX #4: Final validation
    //  
    if(restCandles < 0) restCandles = 0;
    if(restCandles > MAX_REST_CANDLES) {
        Print("==================== CalculateRequiredRestCandles: Result too large (", restCandles, 
              "), clamping to ", MAX_REST_CANDLES);
        restCandles = MAX_REST_CANDLES;
    }
    
    return restCandles;
}

//+------------------------------------------------------------------+
//| Determine Reference Timeframe Based on Wave Size                |
//|                                             |
//| Returns: TH percentage for reference timeframe                  |
//| Logic: Wave size (in TH units) determines structure timeframe   |
//+------------------------------------------------------------------+
double DetermineReferenceTimeframe(double waveDistance, double currentTH)
{
    //                 TH
    double waveSizeInTH = (currentTH > 0) ? (waveDistance / currentTH) : 0;
    
    //       :         3   TH      
    //       = waveSizeInTH / 3
    
    //                  
    double targetTHMultiplier = waveSizeInTH / 3.0;
    
    //        MODIFIED_FRACTAL_PERCENTAGES
    int arraySize = ArraySize(MODIFIED_FRACTAL_PERCENTAGES);
    double closestTH = MODIFIED_FRACTAL_PERCENTAGES[0];
    double minDiff = 1000000.0;
    
    for(int i = 0; i < arraySize; i++) {
        double testTH = MODIFIED_FRACTAL_PERCENTAGES[i];
        double diff = MathAbs(testTH - (currentTH * targetTHMultiplier));
        
        if(diff < minDiff) {
            minDiff = diff;
            closestTH = testTH;
        }
    }
    
    return closestTH;
}

//+------------------------------------------------------------------+
//| Calculate Consolidation Factor - ADVANCED (Gann-based)          |
//|     Consolidation -   (    Gann)             |
//| Considers: angle, rest candles, energy buildup                  |
//| OPTIMIZED: Uses pre-calculated wave analysis                    |
//+------------------------------------------------------------------+
double CalculateConsolidationFactor(datetime tA, datetime tB, datetime tC, 
                                     WaveAnalysis &waves)
{
    // ========================================
    //   1:            
    // ========================================
    double angleAB = waves.AB_Angle;  //   struct      
    
    // ========================================
    //   2:         AB    BC
    // ========================================
    int barA = iBarShift(NULL, 0, tA);
    int barB = iBarShift(NULL, 0, tB);
    int barC = iBarShift(NULL, 0, tC);
    
    int AB_Candles = MathAbs(barA - barB);
    int BC_Candles = MathAbs(barB - barC);
    
    if(AB_Candles < 1) AB_Candles = 1;
    if(BC_Candles < 1) BC_Candles = 1;
    
    // ========================================
    //   3:                
    // ========================================
    int requiredRestCandles = CalculateRequiredRestCandles(angleAB, AB_Candles);
    
    // ========================================
    //   4:                      
    // ========================================
    double restRatio = (double)BC_Candles / requiredRestCandles;
    
    // ========================================
    //   5:     consolidation
    // ========================================
    double consolidationFactor = 0.0;
    
    if(restRatio < 0.3) {
        //       (< 30%        
        //               breakout    
        consolidationFactor = 0.9;
    }
    else if(restRatio < 0.6) {
        //     (30-60%        
        //            
        consolidationFactor = 0.7;
    }
    else if(restRatio < 1.0) {
        //           (60-100%        
        //          
        consolidationFactor = 0.4;
    }
    else if(restRatio < 1.5) {
        //     (100-150%        
        //    
        consolidationFactor = 0.1;
    }
    else {
        //     (> 150%        
        //        
        consolidationFactor = 0.0;
    }
    
    // ========================================
    //   6:            
    // ========================================
    //                           consolidation  
    if(angleAB >= 80) {
        consolidationFactor *= 1.3; // Spike: +30%
    }
    else if(angleAB >= 55) {
        consolidationFactor *= 1.15; // Strong: +15%
    }
    // else: Normal
    
    //            0-1
    if(consolidationFactor > 1.0) consolidationFactor = 1.0;
    if(consolidationFactor < 0.0) consolidationFactor = 0.0;
    
    return consolidationFactor;
}

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
double CalculateMovementSpeed(datetime tA, double pA, datetime tB, double pB)
{
    //            
    double priceChange = MathAbs(pB - pA);
    int timeChangeMinutes = (int)((tB - tA) / 60); //      
    
    if(timeChangeMinutes <= 0) return 1.0; // Default to balanced
    
    //          
    double pipSize = GetCachedPipSize();
    double priceInPips = priceChange / pipSize;
    
    //          
    double speed = priceInPips / timeChangeMinutes;
    
    //       (benchmark)     ATR
    double dailyATR = GetCachedDailyATR();  //     cache
    
    double dailyATRInPips = dailyATR / pipSize;
    
    //     ATR           1440   (     
    double referenceSpeed = dailyATRInPips / 1440.0;
    
    // FIX:                         
    if(referenceSpeed <= 0) referenceSpeed = 0.1; //      
    
    //             /    
    double speedRatio = speed / referenceSpeed;
    
    //                    (0.1   10)
    if(speedRatio < 0.1) speedRatio = 0.1;
    if(speedRatio > 10.0) speedRatio = 10.0;
    
    return speedRatio;
}

//+------------------------------------------------------------------+
//| Calculate Time Symmetry Factor                                  |
//|               AB    BC                             |
//| Perfect symmetry (AB time = BC time) = 1.0                      |
//+------------------------------------------------------------------+
double CalculateTimeSymmetry(datetime tA, datetime tB, datetime tC)
{
    int timeAB = (int)((tB - tA) / 60); //  
    int timeBC = (int)((tC - tB) / 60); //  
    
    if(timeAB <= 0 || timeBC <= 0) return 1.0;
    
    //       :             1      
    // CRITICAL FIX: Validate division operands
    double ratio = 0;
    if(timeAB > 0 && timeBC > 0) {
        ratio = (timeAB > timeBC) ? ((double)timeBC / timeAB) : ((double)timeAB / timeBC);
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== CalculateTimeSymmetry: Invalid time values - AB=", timeAB, ", BC=", timeBC);
        #endif
    }
    
    return ratio;
}

//+------------------------------------------------------------------+
//| Frequency Search Result Structure                               |
//|                                                    |
//+------------------------------------------------------------------+
struct FrequencySearchResult {
    double frequency;        //    
    int frequencyIndex;      //        
    int targetStep;          //     (3  5    7)
    double errorPercent;     //    
    double calculatedD;      //       D
    double targetPrice;      //     (Step N)
    double errorPips;        //      
    double gannAngle;        //     Gann     AB
    double angleWeight;      //            
    double timeSymmetry;     //        AB/BC
    double totalScore;       //     (  =  
};

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
double CalculateFrequencyError(double pA, double pB, double pC, 
                               double frequency, int targetStep,
                               double &calculatedD, double &targetPrice)
{
    // SECURITY: Validate AB distance to prevent division by zero
    double AB_Distance = MathAbs(pB - pA);
    double pipSize = GetCachedPipSize();
    double minDistance = pipSize * 10; // Minimum 10 pips
    
    if(AB_Distance < minDistance) {
        Print("==================== CalculateFrequencyError: AB distance too small (", 
              DoubleToString(AB_Distance, Digits), ") - minimum ", 
              DoubleToString(minDistance, Digits), " required");
        calculatedD = 0.0;
        targetPrice = 0.0;
        return 999.99; // Invalid error
    }
    
    //      
    // baseUnit = AB   (frequency / 100)   TH  
    bool isBullish = (pB > pA);
    double baseUnit = AB_Distance * (frequency / 100.0);
    
    //   D            AB=CD
    //      AB=CD:   CD       AB  
    double pD;
    if(isBullish) {
        pD = pC + AB_Distance;
    } else {
        pD = pC - AB_Distance;
    }
    calculatedD = pD;
    
    //       (Step N   C)
    // Step N = C + (N   baseUnit)
    double stepPrice;
    if(isBullish) {
        stepPrice = pC + (targetStep * baseUnit);
    } else {
        stepPrice = pC - (targetStep * baseUnit);
    }
    targetPrice = stepPrice;
    
    //          D    Step N
    //             AB        
    double error = MathAbs(pD - stepPrice);
    
    // CRITICAL FIX: Validate division operand
    double errorPercent = 0;
    if(MathAbs(AB_Distance) > 0.000001) {
        errorPercent = (error / AB_Distance) * 100.0;
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== CalculateFrequencyError: AB_Distance too small (", AB_Distance, ")");
        #endif
    }
    
    return errorPercent;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Deviation                                   |
//|             Fibonacci                             |
//| Returns: Minimum deviation from standard Fibonacci ratios       |
//+------------------------------------------------------------------+
double CalculateFibonacciDeviation(double ratio)
{
    //         Fibonacci
    double fibRatios[9] = {0.236, 0.382, 0.5, 0.618, 0.786, 1.0, 1.272, 1.618, 2.618};
    
    double minDeviation = 1000.0;
    for(int i = 0; i < 9; i++) {
        double deviation = MathAbs(ratio - fibRatios[i]);
        if(deviation < minDeviation) {
            minDeviation = deviation;
        }
    }
    
    return minDeviation;
}

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
        Print("==================== No suitable frequency found (error > 5%)");
        return false;
    }
    
    //              
    double pipSize = GetCachedPipSize();
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
    
    int displayCount = MathMin(10, resultCount);
    for(int i = 0; i < displayCount; i++)
    {
        Print(StringFormat("%d. %.3f%% ==================== Step %d | Err: %.2f%% (%.1f pips) | Speed: %.2fx | Score: %.2f",
              i + 1,
              results[i].frequency,
              results[i].targetStep,
              results[i].errorPercent,
              results[i].errorPips,
              results[i].gannAngle,
              results[i].totalScore));
    }
    Print("========================================");
    
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
    
    Print("==================== Frequency applied successfully");
    
    // Update frequency label
    UpdateTH3FrequencyLabel(bestFreq);
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate AB=CD Point D (with 9-level validation)               |
//|       D       9                                |
//| Rule: AB distance = CD distance (equal price movement)          |
//+------------------------------------------------------------------+
bool CalculateABCDPointD(datetime tA, double pA, datetime tB, double pB,
                         datetime tC, double pC, datetime &tD, double &pD)
{
    // 1. Validate input times
    if(tA <= 0 || tB <= 0 || tC <= 0) {
        Print("==================== AB=CD Error: Invalid time inputs");
        return false;
    }
    
    // 2. Validate input prices
    if(pA <= 0 || pB <= 0 || pC <= 0) {
        Print("==================== AB=CD Error: Invalid price inputs");
        return false;
    }
    
    // 3. Time ordering: A < B < C
    if(!(tA < tB && tB < tC)) {
        Print("==================== AB=CD Error: Time ordering violated (A < B < C required)");
        return false;
    }
    
    // 4. Minimum distance check (prevent micro-patterns)
    double AB_Distance = MathAbs(pB - pA);
    double BC_Distance = MathAbs(pC - pB);
    double minDistance = Point * ABCD_MIN_DISTANCE_POINTS;
    
    if(AB_Distance < minDistance) {
        Print("==================== AB=CD Error: AB distance too small (min: ", minDistance, ")");
        return false;
    }
    
    // RELAXED: BC can be any size (user might be adjusting)
    // BC               (               
    
    // 5. Pattern direction validation (RELAXED - allow any C position)
    //          (  - C            
    bool isBullish = (pB > pA); // A to B is upward
    
    // REMOVED: Retracement check - C can be anywhere
    //         retracement - C            
    // This allows user to freely adjust C without pattern deletion
    //            C                         
    
    // 6. Calculate D using AB=CD rule
    double CD_Distance = AB_Distance; // Equal distance
    
    if(isBullish) {
        pD = pC + CD_Distance; // Bullish: D above C
    } else {
        pD = pC - CD_Distance; // Bearish: D below C
    }
    
    // 7. Calculate D time (proportional to BC time)
    int BC_Bars = iBarShift(NULL, 0, tB) - iBarShift(NULL, 0, tC);
    if(BC_Bars < 1) BC_Bars = 1;
    
    int CD_Bars = BC_Bars; // Same time proportion
    int barD = iBarShift(NULL, 0, tC) - CD_Bars;
    if(barD < 0) barD = 0;
    
    tD = iTime(NULL, 0, barD);
    if(tD <= 0) tD = tC + (tC - tB); // Fallback
    
    // 8. Collinearity check (REMOVED - too restrictive)
    //     collinearity     -                
    // User should be free to place points anywhere
    //                           
    
    // 9. Final validation: D price must be reasonable (RELAXED)
    //           D         (   
    if(pD <= 0) {
        Print("==================== AB=CD Error: Calculated D price is zero or negative");
        return false;
    }
    
    // RELAXED: Allow any D price (even if far from current price)
    //     D             (               
    
    return true;
}

//+------------------------------------------------------------------+
//| Draw AB=CD Pattern with TH3-style Steps                         |
//|      AB=CD     TH3                                    |
//| User provides A, B, C     System calculates D                      |
//| Targets (Step1/3/5/7) start from C (not D)                       |
//+------------------------------------------------------------------+
void DrawABCDPattern(string mainObjName, datetime tA, double pA, datetime tB, double pB,
                     datetime tC, double pC)
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawABCDPattern called | Name: ", mainObjName);
    Print("   A: ", TimeToString(tA), " @ ", DoubleToString(pA, Digits));
    Print("   B: ", TimeToString(tB), " @ ", DoubleToString(pB, Digits));
    Print("   C: ", TimeToString(tC), " @ ", DoubleToString(pC, Digits));
    #endif
    
    datetime tD;
    double pD;
    
    if(!CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== CalculateABCDPointD failed - cleaning up temp objects");
        #endif
        
        // Cleanup partial objects
        string pointNames[4] = {"A", "B", "C", "D"};
        for(int i = 0; i < 4; i++) {
            ObjectDelete(0, mainObjName + "_Point_" + pointNames[i]);
            ObjectDelete(0, mainObjName + "_Label_" + pointNames[i]);
        }
        ObjectDelete(0, mainObjName + "_Line_AB");
        ObjectDelete(0, mainObjName + "_Line_BC");
        ObjectDelete(0, mainObjName + "_Info");
        return;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== Point D calculated: ", TimeToString(tD), " @ ", DoubleToString(pD, Digits));
    #endif
    
    double AB_Distance = MathAbs(pB - pA);
    bool isBullish = (pB > pA);
    double frequency = GetCurrentTH3Frequency();
    double baseUnit = AB_Distance * (frequency / 100.0);
    
    double pipSize = GetCachedPipSize();
    
    // DYNAMIC OFFSET: Calculate based on candle size for better positioning
    // Offset                          
    double labelOffset;
    
    if(inpABCDLabelOffsetPercent > 0) {
        // User-defined offset percentage
        double avgCandleSize = 0;
        int lookback = 20; //      20      
        for(int k = 0; k < lookback; k++) {
            avgCandleSize += (iHigh(NULL, 0, k) - iLow(NULL, 0, k));
        }
        avgCandleSize /= lookback;
        
        // Use user-defined percentage of average candle size
        labelOffset = avgCandleSize * (inpABCDLabelOffsetPercent / 100.0);
        
        // Minimum offset: 3 pips (prevent labels too close)
        double minOffset = 3.0 * pipSize;
        if(labelOffset < minOffset) labelOffset = minOffset;
        
        // Maximum offset: 100 pips (prevent labels too far)
        double maxOffset = 100.0 * pipSize;
        if(labelOffset > maxOffset) labelOffset = maxOffset;
    } else {
        // Auto mode: Use fixed 15 pips (legacy behavior)
        labelOffset = 15.0 * pipSize;
    }
    
    // Draw points A, B, C, D with smart label positioning
    string pointNames[4];
    pointNames[0] = "A";
    pointNames[1] = "B";
    pointNames[2] = "C";
    pointNames[3] = "D";
    
    datetime pointTimes[4];
    pointTimes[0] = tA;
    pointTimes[1] = tB;
    pointTimes[2] = tC;
    pointTimes[3] = tD;
    
    double pointPrices[4];
    pointPrices[0] = pA;
    pointPrices[1] = pB;
    pointPrices[2] = pC;
    pointPrices[3] = pD;
    
    // Draw visible drag points for A, B, C (small circles with smart positioning)
    //            A  B  C (                   
    for(int i = 0; i < 3; i++) {
        string pointName = mainObjName + "_Point_" + pointNames[i];
        
        // SMART POSITIONING: Place point above/below candle based on price level
        //                     /              
        int barIndex = iBarShift(NULL, 0, pointTimes[i]);
        double pointPrice = pointPrices[i];
        
        if(barIndex >= 0) {
            double high = iHigh(NULL, 0, barIndex);
            double low = iLow(NULL, 0, barIndex);
            double mid = (high + low) / 2.0;
            
            // Determine if point is at top or bottom of candle
            //                         
            bool isAtTop = (pointPrice >= mid);
            
            // Offset point slightly outside candle for visibility
            //                           
            double offset = (high - low) * 0.15; // 15% of candle range
            double minOffset = pipSize * 10;  // Minimum 10 pips
            if(offset < minOffset) offset = minOffset; // Minimum offset
            
            if(isAtTop) {
                // Point at top - place above high
                pointPrice = high + offset;
            } else {
                // Point at bottom - place below low
                pointPrice = low - offset;
            }
        }
        
        // OPTIMIZED: Use small circle (ARROWCODE 159) - visible and draggable
        //             -          
        if(ObjectFind(0, pointName) < 0) {
            if(!ObjectCreate(0, pointName, OBJ_ARROW, 0, pointTimes[i], pointPrices[i])) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== Failed to create point ", pointNames[i], " | Error: ", GetLastError());
                #endif
            } else {
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== Created point ", pointNames[i], " at ", TimeToString(pointTimes[i]), " @ ", DoubleToString(pointPrices[i], Digits));
                #endif
            }
            
            // CRITICAL: Visible circle with smart positioning
            ObjectSetInteger(0, pointName, OBJPROP_COLOR, inpABCDPointColor);
            ObjectSetInteger(0, pointName, OBJPROP_ARROWCODE, 159); // Small filled circle
            ObjectSetInteger(0, pointName, OBJPROP_WIDTH, 3); // Medium size for easy clicking
            ObjectSetInteger(0, pointName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, pointName, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, pointName, OBJPROP_BACK, false); // Draw on top
            ObjectSetInteger(0, pointName, OBJPROP_ZORDER, 10); // High priority
            ObjectSetString(0, pointName, OBJPROP_TOOLTIP, "==================== Point " + pointNames[i] + " | Drag to adjust");
        } else {
            // Update existing point position
            ObjectMove(0, pointName, 0, pointTimes[i], pointPrices[i]);
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Updated existing point ", pointNames[i]);
            #endif
        }
        
        // Smart label positioning relative to candle High/Low
        //                   High/Low    
        if(inpABCDShowLabels) {
            string labelName = mainObjName + "_Label_" + pointNames[i];
            double labelPrice = pointPrices[i];
            ENUM_ANCHOR_POINT anchor = ANCHOR_CENTER;
            
            // Get candle High/Low for this point
            int labelBarIndex = iBarShift(NULL, 0, pointTimes[i]);
            double candleHigh = (labelBarIndex >= 0) ? iHigh(NULL, 0, labelBarIndex) : pointPrices[i];
            double candleLow = (labelBarIndex >= 0) ? iLow(NULL, 0, labelBarIndex) : pointPrices[i];
            
            // Position label relative to candle High/Low (not point price)
            //              High/Low     (         
            if(i == 0 || i == 2) { // A or C (swing lows in bullish, swing highs in bearish)
                if(isBullish) {
                    // A/C are lows - place label below candle low
                    labelPrice = candleLow - labelOffset;
                    anchor = ANCHOR_UPPER;
                } else {
                    // A/C are highs - place label above candle high
                    labelPrice = candleHigh + labelOffset;
                    anchor = ANCHOR_LOWER;
                }
            } else { // B or D (swing highs in bullish, swing lows in bearish)
                if(isBullish) {
                    // B/D are highs - place label above candle high
                    labelPrice = candleHigh + labelOffset;
                    anchor = ANCHOR_LOWER;
                } else {
                    // B/D are lows - place label below candle low
                    labelPrice = candleLow - labelOffset;
                    anchor = ANCHOR_UPPER;
                }
            }
            
            if(ObjectFind(0, labelName) < 0) {
                if(!ObjectCreate(0, labelName, OBJ_TEXT, 0, pointTimes[i], labelPrice)) {
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("==================== Failed to create label ", pointNames[i], " | Error: ", GetLastError());
                    #endif
                } else {
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("==================== Created label ", pointNames[i]);
                    #endif
                }
                ObjectSetString(0, labelName, OBJPROP_TEXT, pointNames[i]);
                ObjectSetInteger(0, labelName, OBJPROP_COLOR, inpABCDPointColor);
                ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
                ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
                ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, anchor);
                ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
            } else {
                ObjectMove(0, labelName, 0, pointTimes[i], labelPrice);
                ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, anchor);
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== Updated existing label ", pointNames[i]);
                #endif
            }
        }
    }
    
    // Draw line AB (solid)
    string lineAB = mainObjName + "_Line_AB";
    if(ObjectFind(0, lineAB) < 0) {
        if(!ObjectCreate(0, lineAB, OBJ_TREND, 0, tA, pA, tB, pB)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Failed to create Line AB | Error: ", GetLastError());
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Created Line AB");
            #endif
        }
        ObjectSetInteger(0, lineAB, OBJPROP_COLOR, inpABCDLineColor);
        ObjectSetInteger(0, lineAB, OBJPROP_WIDTH, inpABCDWidth);
        ObjectSetInteger(0, lineAB, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, lineAB, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, lineAB, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, lineAB, OBJPROP_BACK, false);
    } else {
        ObjectMove(0, lineAB, 0, tA, pA);
        ObjectMove(0, lineAB, 1, tB, pB);
    }
    
    // Draw line BC (dotted)
    string lineBC = mainObjName + "_Line_BC";
    if(ObjectFind(0, lineBC) < 0) {
        if(!ObjectCreate(0, lineBC, OBJ_TREND, 0, tB, pB, tC, pC)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Failed to create Line BC | Error: ", GetLastError());
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Created Line BC");
            #endif
        }
        ObjectSetInteger(0, lineBC, OBJPROP_COLOR, clrGray);
        ObjectSetInteger(0, lineBC, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, lineBC, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, lineBC, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, lineBC, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, lineBC, OBJPROP_BACK, true);
    } else {
        ObjectMove(0, lineBC, 0, tB, pB);
        ObjectMove(0, lineBC, 1, tC, pC);
    }
    
    // Draw TH3-style targets (Step1, Step3, Step5, Step7) from C
    string targetNames[4] = {"Step1", "Step3", "Step5", "Step7"};
    color targetColors[4] = {clrDodgerBlue, clrOrangeRed, clrLimeGreen, clrGold};
    double targetLevels[4];
    
    if(isBullish) {
        targetLevels[0] = pC + (1.0 * baseUnit);
        targetLevels[1] = pC + (3.0 * baseUnit);
        targetLevels[2] = pC + (5.0 * baseUnit);
        targetLevels[3] = pC + (7.0 * baseUnit);
    } else {
        targetLevels[0] = pC - (1.0 * baseUnit);
        targetLevels[1] = pC - (3.0 * baseUnit);
        targetLevels[2] = pC - (5.0 * baseUnit);
        targetLevels[3] = pC - (7.0 * baseUnit);
    }
    
    double targetPips[4];
    for(int i = 0; i < 4; i++) {
        targetPips[i] = MathAbs(baseUnit * (i*2 + 1)) / pipSize;
    }
    
    datetime startTime = tC;
    int barShift = iBarShift(NULL, 0, startTime);
    datetime endTime = iTime(NULL, 0, MathMax(0, barShift - 100));
    
    // GOLD VERSION: Use configurable zone height from input parameter
    // Convert from percentage (1-100) to decimal (0.01-1.0)
    double zoneHeightPercent = inpTH3ZoneHeightPercent / 100.0;
    
    // Validate and clamp
    if(zoneHeightPercent < 0.01) zoneHeightPercent = 0.01;
    if(zoneHeightPercent > 1.0) zoneHeightPercent = 1.0;
    
    double zoneHalfWidth = baseUnit * zoneHeightPercent;
    
    for(int i = 0; i < 4; i++) {
        string lineName = mainObjName + "_Target_" + IntegerToString(i+1);
        double centerPrice = targetLevels[i];
        double upperZone = centerPrice + zoneHalfWidth;
        double lowerZone = centerPrice - zoneHalfWidth;
        color zoneColor = (inpTH3ZoneColor == clrNONE) ? targetColors[i] : inpTH3ZoneColor;
        
        if(ObjectFind(0, lineName) < 0) {
            ObjectCreate(0, lineName, OBJ_FIBO, 0, startTime, centerPrice, endTime, centerPrice);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, targetColors[i]);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELCOLOR, targetColors[i]);
            ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELWIDTH, 2);
            ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
            ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELS, 1);
            ObjectSetDouble(0, lineName, OBJPROP_LEVELVALUE, 0, 0.0);
            
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN) {
                double zonePips = (zoneHalfWidth * 2.0) / pipSize;
                string labelText = StringFormat("%s (%.1f) ====================%.1f", targetNames[i], targetPips[i], zonePips/2.0);
                ObjectSetString(0, lineName, OBJPROP_LEVELTEXT, 0, labelText);
            }
        } else {
            // CRITICAL FIX: Update position AND label text when frequency changes
            ObjectMove(0, lineName, 0, startTime, centerPrice);
            ObjectMove(0, lineName, 1, endTime, centerPrice);
            
            // Update label text with new pip values
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN) {
                double zonePips = (zoneHalfWidth * 2.0) / pipSize;
                string labelText = StringFormat("%s (%.1f) ====================%.1f", targetNames[i], targetPips[i], zonePips/2.0);
                ObjectSetString(0, lineName, OBJPROP_LEVELTEXT, 0, labelText);
            }
        }
        
        // Zone lines
        string zoneUpperName = mainObjName + "_ZoneUpper_" + IntegerToString(i+1);
        string zoneLowerName = mainObjName + "_ZoneLower_" + IntegerToString(i+1);
        
        if(inpTH3ZoneStyle == TH3_ZONE_LINES) {
            if(ObjectFind(0, zoneUpperName) < 0) {
                ObjectCreate(0, zoneUpperName, OBJ_TREND, 0, startTime, upperZone, endTime, upperZone);
                ObjectSetInteger(0, zoneUpperName, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, zoneUpperName, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
                ObjectSetInteger(0, zoneUpperName, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, zoneUpperName, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
                ObjectSetInteger(0, zoneUpperName, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, zoneUpperName, OBJPROP_BACK, true);
            } else {
                ObjectMove(0, zoneUpperName, 0, startTime, upperZone);
                ObjectMove(0, zoneUpperName, 1, endTime, upperZone);
            }
            
            if(ObjectFind(0, zoneLowerName) < 0) {
                ObjectCreate(0, zoneLowerName, OBJ_TREND, 0, startTime, lowerZone, endTime, lowerZone);
                ObjectSetInteger(0, zoneLowerName, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, zoneLowerName, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
                ObjectSetInteger(0, zoneLowerName, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, zoneLowerName, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
                ObjectSetInteger(0, zoneLowerName, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, zoneLowerName, OBJPROP_BACK, true);
            } else {
                ObjectMove(0, zoneLowerName, 0, startTime, lowerZone);
                ObjectMove(0, zoneLowerName, 1, endTime, lowerZone);
            }
        }
    }
    
    // Info label (corner-based positioning - configurable)
    //     (        -      
    // VISIBILITY: Only shown for active pattern
    //         :                 
    double pips_AB = AB_Distance / pipSize;
    double pips_BC = MathAbs(pC - pB) / pipSize;
    
    string infoText = StringFormat("AB=CD | AB:%.1f | BC:%.1f | Freq:%.1f%%", 
                                   pips_AB, pips_BC, frequency);
    
    string infoLabel = mainObjName + "_Info";
    
    // Determine visibility based on active pattern
    //                     
    bool isActive = (g_activeABCDPattern == mainObjName);
    
    if(ObjectFind(0, infoLabel) < 0) {
        ObjectCreate(0, infoLabel, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, infoLabel, OBJPROP_CORNER, inpABCDInfoCorner);
        ObjectSetInteger(0, infoLabel, OBJPROP_XDISTANCE, inpABCDInfoXDistance);
        ObjectSetInteger(0, infoLabel, OBJPROP_YDISTANCE, inpABCDInfoYDistance);
        ObjectSetString(0, infoLabel, OBJPROP_TEXT, infoText);
        ObjectSetInteger(0, infoLabel, OBJPROP_COLOR, inpABCDInfoColor);
        ObjectSetInteger(0, infoLabel, OBJPROP_FONTSIZE, inpABCDInfoFontSize);
        ObjectSetString(0, infoLabel, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, infoLabel, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, infoLabel, OBJPROP_HIDDEN, true);
        
        // Set visibility based on active state
        ObjectSetInteger(0, infoLabel, OBJPROP_TIMEFRAMES, isActive ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
    } else {
        // Update text and visibility
        ObjectSetString(0, infoLabel, OBJPROP_TEXT, infoText);
        ObjectSetInteger(0, infoLabel, OBJPROP_CORNER, inpABCDInfoCorner);
        ObjectSetInteger(0, infoLabel, OBJPROP_XDISTANCE, inpABCDInfoXDistance);
        ObjectSetInteger(0, infoLabel, OBJPROP_YDISTANCE, inpABCDInfoYDistance);
        ObjectSetInteger(0, infoLabel, OBJPROP_COLOR, inpABCDInfoColor);
        ObjectSetInteger(0, infoLabel, OBJPROP_FONTSIZE, inpABCDInfoFontSize);
        
        // Update visibility based on active state
        ObjectSetInteger(0, infoLabel, OBJPROP_TIMEFRAMES, isActive ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawABCDPattern completed | Pattern: ", mainObjName);
    Print("   Objects: Points(3:A,B,C) + Labels(3) + Lines(2) + Targets(4) + Zones(8) + Info(1)");
    Print("   Note: Point D not shown - target levels indicate D zone");
    #endif
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update All TH3 Objects (when frequency changes)                 |
//|       TH3 (                               |
//+------------------------------------------------------------------+
void UpdateAllTH3Objects() {
    int updatedCount = 0;
    
    // Update AB=CD patterns
    int totalTrend = ObjectsTotal(0, -1, OBJ_TREND);
    for(int i = 0; i < totalTrend; i++) {
        string name = ObjectName(0, i, -1, OBJ_TREND);
        
        // Find AB=CD pattern main line (Line_AB)
        if(StringFind(name, "ABCD_Pattern_") == 0 && StringFind(name, "_Line_AB") > 0) {
            string baseName = StringSubstr(name, 0, StringFind(name, "_Line_AB"));
            
            // Get points A, B, C from line endpoints
            string lineAB = baseName + "_Line_AB";
            string lineBC = baseName + "_Line_BC";
            
            if(ObjectFind(0, lineAB) < 0 || ObjectFind(0, lineBC) < 0) continue;
            
            datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
            double pA = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 0);
            datetime tB = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 1);
            double pB = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 1);
            datetime tC = (datetime)ObjectGetInteger(0, lineBC, OBJPROP_TIME, 1);
            double pC = ObjectGetDouble(0, lineBC, OBJPROP_PRICE, 1);
            
            int lastError = GetLastError();
            if(lastError != 0) {
                ResetLastError(); // CRITICAL FIX: Clear error for next iteration
                continue;
            }
            
            if(tA > 0 && tB > 0 && tC > 0 && pA > 0 && pB > 0 && pC > 0) {
                // Redraw entire AB=CD pattern with new frequency
                DrawABCDPattern(baseName, tA, pA, tB, pB, tC, pC);
                updatedCount++;
            }
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
//| Handle AB=CD Mouse Events (3-point click workflow)              |
//|             AB=CD (  3                       |
//+------------------------------------------------------------------+
void OnABCDMouseEvent(int id, long lparam, double dparam, string sparam) {
    // Handle right-click cancel
    if(id == CHARTEVENT_MOUSE_MOVE) {
        int mouseState = (int)StringToInteger(sparam);
        bool rightButtonDown = (mouseState & 2) == 2;
        bool leftButtonDown = (mouseState & 1) == 1;
        
        if(rightButtonDown && g_abcdDrawing) {
            g_abcdDrawing = false;
            g_abcdPointCount = 0;
            
            ObjectDelete(0, "ABCD_Temp_X");
            ObjectDelete(0, "ABCD_Temp_A");
            ObjectDelete(0, "ABCD_Temp_B");
            ObjectDelete(0, "ABCD_Temp_C");
            ObjectDelete(0, "ABCD_Temp_Line_XA");
            ObjectDelete(0, "ABCD_Temp_Line_AB");
            ObjectDelete(0, "ABCD_Temp_Line_BC");
            
            ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
            ChartRedraw();
            Print("==================== AB=CD creation cancelled");
            return;
        }
        
        // ALTERNATIVE CLICK DETECTION: Use mouse button state change
        // This is more reliable than CHARTEVENT_CLICK in MT4
        static bool s_lastLeftButtonState = false;
        
        if(g_abcdDrawing && leftButtonDown && !s_lastLeftButtonState) {
            // Left button just pressed (rising edge detection)
            s_lastLeftButtonState = true;
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Left button pressed via MOUSE_MOVE | lparam=", lparam, " dparam=", dparam);
            #endif
            
            // Debounce check
            uint currentTime = GetTickCount();
            if(currentTime - g_abcdLastClickTime < ABCD_DEBOUNCE_MS) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== Click debounced (too fast)");
                #endif
                return;
            }
            g_abcdLastClickTime = currentTime;
            
            // Get click coordinates
            double mx = (double)lparam;
            double my = (double)dparam;
            
            int subWindow;
            datetime clickTime;
            double clickPrice;
            if(!ChartXYToTimePrice(0, (int)mx, (int)my, subWindow, clickTime, clickPrice)) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== ChartXYToTimePrice failed | mx=", mx, " my=", my);
                #endif
                return;
            }
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Click detected | time=", TimeToString(clickTime), " price=", DoubleToString(clickPrice, Digits), " | pointCount=", g_abcdPointCount);
            #endif
            
            // Place point based on current count (4 points: X, A, B, C)
            if(g_abcdPointCount == 0) {
                g_abcdTimeX = clickTime;
                g_abcdPriceX = clickPrice;
                g_abcdPointCount = 1;
                
                ObjectCreate(0, "ABCD_Temp_X", OBJ_TEXT, 0, clickTime, clickPrice);
                ObjectSetString(0, "ABCD_Temp_X", OBJPROP_TEXT, "X");
                ObjectSetInteger(0, "ABCD_Temp_X", OBJPROP_COLOR, clrYellow);
                ObjectSetInteger(0, "ABCD_Temp_X", OBJPROP_FONTSIZE, 10);
                ChartRedraw();
                Print("==================== Point X placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
            }
            else if(g_abcdPointCount == 1) {
                g_abcdTimeA = clickTime;
                g_abcdPriceA = clickPrice;
                g_abcdPointCount = 2;
                
                ObjectCreate(0, "ABCD_Temp_A", OBJ_TEXT, 0, clickTime, clickPrice);
                ObjectSetString(0, "ABCD_Temp_A", OBJPROP_TEXT, "A");
                ObjectSetInteger(0, "ABCD_Temp_A", OBJPROP_COLOR, clrYellow);
                ObjectSetInteger(0, "ABCD_Temp_A", OBJPROP_FONTSIZE, 10);
                
                ObjectCreate(0, "ABCD_Temp_Line_XA", OBJ_TREND, 0, g_abcdTimeX, g_abcdPriceX, g_abcdTimeA, g_abcdPriceA);
                ObjectSetInteger(0, "ABCD_Temp_Line_XA", OBJPROP_COLOR, clrYellow);
                ObjectSetInteger(0, "ABCD_Temp_Line_XA", OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, "ABCD_Temp_Line_XA", OBJPROP_RAY_RIGHT, false);
                ChartRedraw();
                Print("==================== Point A placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
            }
            else if(g_abcdPointCount == 2) {
                g_abcdTimeB = clickTime;
                g_abcdPriceB = clickPrice;
                g_abcdPointCount = 3;
                
                ObjectCreate(0, "ABCD_Temp_B", OBJ_TEXT, 0, clickTime, clickPrice);
                ObjectSetString(0, "ABCD_Temp_B", OBJPROP_TEXT, "B");
                ObjectSetInteger(0, "ABCD_Temp_B", OBJPROP_COLOR, clrYellow);
                ObjectSetInteger(0, "ABCD_Temp_B", OBJPROP_FONTSIZE, 10);
                
                ObjectCreate(0, "ABCD_Temp_Line_AB", OBJ_TREND, 0, g_abcdTimeA, g_abcdPriceA, g_abcdTimeB, g_abcdPriceB);
                ObjectSetInteger(0, "ABCD_Temp_Line_AB", OBJPROP_COLOR, clrYellow);
                ObjectSetInteger(0, "ABCD_Temp_Line_AB", OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, "ABCD_Temp_Line_AB", OBJPROP_RAY_RIGHT, false);
                ChartRedraw();
                Print("==================== Point B placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
            }
            else if(g_abcdPointCount == 3) {
                g_abcdTimeC = clickTime;
                g_abcdPriceC = clickPrice;
                
                Print("==================== Point C placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
                
                //   AUTO-SEARCH: Find optimal frequency for this pattern (with 3-wave analysis)
                //                             (    3    
                FrequencySearchResult searchResults[];
                WaveAnalysis waves;
                double consolidationFactor;
                
                int resultCount = FindOptimalFrequencyForABCD_WithLearningData(
                    g_abcdTimeX, g_abcdPriceX,
                    g_abcdTimeA, g_abcdPriceA, 
                    g_abcdTimeB, g_abcdPriceB,
                    g_abcdTimeC, g_abcdPriceC,
                    searchResults,
                    waves,
                    consolidationFactor,
                    5.0);
                
                if(resultCount > 0) {
                    //         
                    g_th3FreqOverride = searchResults[0].frequency;
                    g_th3FreqIndex = searchResults[0].frequencyIndex;
                    
                    //     GlobalVariable
                    // PERFORMANCE: Use cached ChartID string
                    string chartIdStr = GetCachedChartIdStr();
                    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
                    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
                    GlobalVariableSet(freqGvarName, g_th3FreqOverride);
                    GlobalVariableSet(indexGvarName, g_th3FreqIndex);
                    
                    Print("========================================");
                    Print("==================== AUTO-SELECTED FREQUENCY");
                    Print("========================================");
                    Print("Best: ", DoubleToString(searchResults[0].frequency, 3), "% ==================== Step ", searchResults[0].targetStep);
                    Print("Error: ", DoubleToString(searchResults[0].errorPercent, 3), "% (", DoubleToString(searchResults[0].errorPips, 1), " pips)");
                    Print("Speed: ", DoubleToString(searchResults[0].gannAngle, 2), "x | Consistency: ", DoubleToString(searchResults[0].angleWeight * 100, 1), "%");
                    Print("Time Sym: ", DoubleToString(searchResults[0].timeSymmetry * 100, 1), "% | Score: ", DoubleToString(searchResults[0].totalScore, 2));
                    Print("========================================");
                    Print("==================== TOP 5 ALTERNATIVES:");
                    for(int i = 0; i < MathMin(5, resultCount); i++) {
                        Print(StringFormat("%d. %.3f%% ==================== Step %d | Err: %.2f%% | Speed: %.2fx | Score: %.2f",
                              i + 1,
                              searchResults[i].frequency,
                              searchResults[i].targetStep,
                              searchResults[i].errorPercent,
                              searchResults[i].gannAngle,
                              searchResults[i].totalScore));
                    }
                    Print("========================================");
                }
                
                string patternName = "ABCD_Pattern_" + IntegerToString((long)GetTickCount());
                DrawABCDPattern(patternName, g_abcdTimeA, g_abcdPriceA, g_abcdTimeB, g_abcdPriceB, g_abcdTimeC, g_abcdPriceC);
                
                // Set as active pattern
                SetActiveABCDPattern(patternName);
                
                // ========================================
                
                ObjectDelete(0, "ABCD_Temp_X");
                ObjectDelete(0, "ABCD_Temp_A");
                ObjectDelete(0, "ABCD_Temp_B");
                ObjectDelete(0, "ABCD_Temp_C");
                ObjectDelete(0, "ABCD_Temp_Line_XA");
                ObjectDelete(0, "ABCD_Temp_Line_AB");
                ObjectDelete(0, "ABCD_Temp_Line_BC");
                
                g_abcdDrawing = false;
                g_abcdPointCount = 0;
                ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
                
                // Update frequency label
                UpdateTH3FrequencyLabel(g_th3FreqOverride);
                
                ChartRedraw();
                Print("==================== AB=CD pattern created: ", patternName);
            }
        }
        else if(!leftButtonDown && s_lastLeftButtonState) {
            // Left button released
            s_lastLeftButtonState = false;
        }
        
        return;
    }
    
    // Handle left-click to place points (fallback for CHARTEVENT_CLICK)
    if(id == CHARTEVENT_CLICK && g_abcdDrawing) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== CHARTEVENT_CLICK received | lparam=", lparam, " dparam=", dparam, " sparam=", sparam, " | g_abcdPointCount=", g_abcdPointCount);
        #endif
        
        uint currentTime = GetTickCount();
        if(currentTime - g_abcdLastClickTime < ABCD_DEBOUNCE_MS) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Click debounced (too fast)");
            #endif
            return;
        }
        g_abcdLastClickTime = currentTime;
        
        double mx = (double)lparam;
        double my = (double)dparam;
        
        int subWindow;
        datetime clickTime;
        double clickPrice;
        if(!ChartXYToTimePrice(0, (int)mx, (int)my, subWindow, clickTime, clickPrice)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== ChartXYToTimePrice failed | mx=", mx, " my=", my);
            #endif
            return;
        }
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== ChartXYToTimePrice success | time=", TimeToString(clickTime), " price=", DoubleToString(clickPrice, Digits));
        #endif
        
        if(g_abcdPointCount == 0) {
            g_abcdTimeX = clickTime;
            g_abcdPriceX = clickPrice;
            g_abcdPointCount = 1;
            
            ObjectCreate(0, "ABCD_Temp_X", OBJ_TEXT, 0, clickTime, clickPrice);
            ObjectSetString(0, "ABCD_Temp_X", OBJPROP_TEXT, "X");
            ObjectSetInteger(0, "ABCD_Temp_X", OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, "ABCD_Temp_X", OBJPROP_FONTSIZE, 10);
            ChartRedraw();
            Print("==================== Point X placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
        }
        else if(g_abcdPointCount == 1) {
            g_abcdTimeA = clickTime;
            g_abcdPriceA = clickPrice;
            g_abcdPointCount = 2;
            
            ObjectCreate(0, "ABCD_Temp_A", OBJ_TEXT, 0, clickTime, clickPrice);
            ObjectSetString(0, "ABCD_Temp_A", OBJPROP_TEXT, "A");
            ObjectSetInteger(0, "ABCD_Temp_A", OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, "ABCD_Temp_A", OBJPROP_FONTSIZE, 10);
            
            ObjectCreate(0, "ABCD_Temp_Line_XA", OBJ_TREND, 0, g_abcdTimeX, g_abcdPriceX, g_abcdTimeA, g_abcdPriceA);
            ObjectSetInteger(0, "ABCD_Temp_Line_XA", OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, "ABCD_Temp_Line_XA", OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, "ABCD_Temp_Line_XA", OBJPROP_RAY_RIGHT, false);
            ChartRedraw();
            Print("==================== Point A placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
        }
        else if(g_abcdPointCount == 2) {
            g_abcdTimeB = clickTime;
            g_abcdPriceB = clickPrice;
            g_abcdPointCount = 3;
            
            ObjectCreate(0, "ABCD_Temp_B", OBJ_TEXT, 0, clickTime, clickPrice);
            ObjectSetString(0, "ABCD_Temp_B", OBJPROP_TEXT, "B");
            ObjectSetInteger(0, "ABCD_Temp_B", OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, "ABCD_Temp_B", OBJPROP_FONTSIZE, 10);
            
            ObjectCreate(0, "ABCD_Temp_Line_AB", OBJ_TREND, 0, g_abcdTimeA, g_abcdPriceA, g_abcdTimeB, g_abcdPriceB);
            ObjectSetInteger(0, "ABCD_Temp_Line_AB", OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, "ABCD_Temp_Line_AB", OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, "ABCD_Temp_Line_AB", OBJPROP_RAY_RIGHT, false);
            ChartRedraw();
            Print("==================== Point B placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
        }
        else if(g_abcdPointCount == 3) {
            g_abcdTimeC = clickTime;
            g_abcdPriceC = clickPrice;
            
            Print("==================== Point C placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
            
            string patternName = "ABCD_Pattern_" + IntegerToString((long)GetTickCount());
            DrawABCDPattern(patternName, g_abcdTimeA, g_abcdPriceA, g_abcdTimeB, g_abcdPriceB, g_abcdTimeC, g_abcdPriceC);
            
            // Set as active pattern
            SetActiveABCDPattern(patternName);
            
            ObjectDelete(0, "ABCD_Temp_X");
            ObjectDelete(0, "ABCD_Temp_A");
            ObjectDelete(0, "ABCD_Temp_B");
            ObjectDelete(0, "ABCD_Temp_C");
            ObjectDelete(0, "ABCD_Temp_Line_XA");
            ObjectDelete(0, "ABCD_Temp_Line_AB");
            ObjectDelete(0, "ABCD_Temp_Line_BC");
            
            g_abcdDrawing = false;
            g_abcdPointCount = 0;
            ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
            ChartRedraw();
            Print("==================== AB=CD pattern created: ", patternName);
        }
    }
    
    // Handle drag events for A, B, C points with smart magnet effect
    //          A  B  C              
    if(id == CHARTEVENT_OBJECT_DRAG) {
        if(StringFind(sparam, "ABCD_Pattern_") == 0 && StringFind(sparam, "_Point_") > 0) {
            // Extract pattern name and point
            int pointPos = StringFind(sparam, "_Point_");
            string baseName = StringSubstr(sparam, 0, pointPos);
            string pointName = StringSubstr(sparam, pointPos + 7);
            
            // Only A, B, C are draggable
            if(pointName != "A" && pointName != "B" && pointName != "C") return;
            
            // CRITICAL: Set this pattern as active when user drags it
            //       drag                  
            SetActiveABCDPattern(baseName);
            
            // SMART MAGNET: Snap to nearest candle high/low with threshold
            //                  high/low          
            string draggedPoint = baseName + "_Point_" + pointName;
            datetime newTime = (datetime)ObjectGetInteger(0, draggedPoint, OBJPROP_TIME, 0);
            double newPrice = ObjectGetDouble(0, draggedPoint, OBJPROP_PRICE, 0);
            
            int barIndex = iBarShift(NULL, 0, newTime);
            if(barIndex >= 0) {
                double high = iHigh(NULL, 0, barIndex);
                double low = iLow(NULL, 0, barIndex);
                double open = iOpen(NULL, 0, barIndex);
                double close = iClose(NULL, 0, barIndex);
                
                // Calculate distances in pips
                double pipSize = GetCachedPipSize();
                double distToHigh = MathAbs(newPrice - high) / pipSize;
                double distToLow = MathAbs(newPrice - low) / pipSize;
                double distToOpen = MathAbs(newPrice - open) / pipSize;
                double distToClose = MathAbs(newPrice - close) / pipSize;
                
                // THRESHOLD: Only snap if within 5 pips (industry standard)
                //               5     snap  
                double snapThreshold = 5.0;
                
                // Find closest level within threshold
                double minDist = MathMin(MathMin(distToHigh, distToLow), MathMin(distToOpen, distToClose));
                
                if(minDist <= snapThreshold) {
                    // PRIORITY: High/Low > Open/Close (more significant levels)
                    //       High/Low > Open/Close (     
                    if(minDist == distToHigh) {
                        newPrice = high;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("==================== Snapped to HIGH (", DoubleToString(minDist, 1), " pips)");
                        #endif
                    } else if(minDist == distToLow) {
                        newPrice = low;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("==================== Snapped to LOW (", DoubleToString(minDist, 1), " pips)");
                        #endif
                    } else if(minDist == distToClose) {
                        newPrice = close;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("==================== Snapped to CLOSE (", DoubleToString(minDist, 1), " pips)");
                        #endif
                    } else if(minDist == distToOpen) {
                        newPrice = open;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("==================== Snapped to OPEN (", DoubleToString(minDist, 1), " pips)");
                        #endif
                    }
                    
                    // Update point with snapped price
                    ObjectSetDouble(0, draggedPoint, OBJPROP_PRICE, newPrice);
                }
                // else: No snap - user has precise control beyond threshold
            }
            
            // Get updated positions
            string lineAB = baseName + "_Line_AB";
            string lineBC = baseName + "_Line_BC";
            
            if(ObjectFind(0, lineAB) < 0 || ObjectFind(0, lineBC) < 0) return;
            
            datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
            double pA = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 0);
            
            // Validate after each ObjectGet (CRITICAL FIX: prevent crash)
            if(ObjectFind(0, lineAB) < 0) return;
            
            datetime tB = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 1);
            double pB = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 1);
            
            if(ObjectFind(0, lineBC) < 0) return;
            
            datetime tC = (datetime)ObjectGetInteger(0, lineBC, OBJPROP_TIME, 1);
            double pC = ObjectGetDouble(0, lineBC, OBJPROP_PRICE, 1);
            
            // Update point position from drag
            if(pointName == "A") {
                tA = newTime;
                pA = newPrice;
            } else if(pointName == "B") {
                tB = newTime;
                pB = newPrice;
            } else if(pointName == "C") {
                tC = newTime;
                pC = newPrice;
            }
            
            // Redraw pattern with updated points (includes wave analysis)
            DrawABCDPattern(baseName, tA, pA, tB, pB, tC, pC);
        }
    }
    
    // Handle pattern deletion (only when main objects are deleted, not drag points)
    //        (                            )
    if(id == CHARTEVENT_OBJECT_DELETE) {
        // Check if any ABCD pattern object is deleted
        //                      ABCD    
        if(StringFind(sparam, "ABCD_Pattern_") == 0) {
            
            // Extract base name from deleted object
            string baseName = sparam;
            
            // CRITICAL FIX: Safe string parsing - find pattern base name
            //              
            int underscorePos = -1;
            
            // Try different suffixes to extract base name (using constants)
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
            
            // Verify this is a valid pattern base name (should be ABCD_Pattern_XXXXXXXX)
            if(StringFind(baseName, "ABCD_Pattern_") != 0 || StringLen(baseName) < 20) {
                // Not a valid pattern base name, ignore
                return;
            }
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Deleting AB=CD pattern: ", baseName);
            Print("   Triggered by object: ", sparam);
            #endif
            
            // ========================================
            // COMPREHENSIVE CLEANUP: Delete ALL related objects
            //              
            // ========================================
            
            // 1. Delete drag points (A, B, C) and labels
            string pointNames[3] = {"A", "B", "C"};
            for(int i = 0; i < 3; i++) {
                ObjectDelete(0, baseName + "_Point_" + pointNames[i]);
                ObjectDelete(0, baseName + "_Label_" + pointNames[i]);
            }
            
            // 2. Delete lines
            ObjectDelete(0, baseName + "_Line_AB");
            ObjectDelete(0, baseName + "_Line_BC");
            
            // 3. Delete info label
            ObjectDelete(0, baseName + "_Info");
            
            // 4. Delete all target levels (Step1-7) and zones
            //                   
            for(int i = 1; i <= 7; i++) {
                ObjectDelete(0, baseName + "_Target_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_ZoneUpper_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_ZoneLower_" + IntegerToString(i));
            }
            
            // 5. Delete any temporary objects
            //        
            ObjectDelete(0, baseName + "_Temp_X");
            ObjectDelete(0, baseName + "_Temp_A");
            ObjectDelete(0, baseName + "_Temp_B");
            ObjectDelete(0, baseName + "_Temp_C");
            ObjectDelete(0, baseName + "_Temp_Line_XA");
            ObjectDelete(0, baseName + "_Temp_Line_AB");
            ObjectDelete(0, baseName + "_Temp_Line_BC");
            
            // 6. Clear active pattern if this was the active one
            //                     
            if(g_activeABCDPattern == baseName) {
                SetActiveABCDPattern("");
            }
            
            // ========================================
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Pattern cleanup complete: ", baseName);
            #endif
            
            ChartRedraw();
        }
    }
}

//| Toggle TH3 Tool (V key)                                         |
//|  /       TH3 (  V)                            |
//+------------------------------------------------------------------+
void ToggleTH3Tool() {
    if(!inpEnableTH3Tool) return;
    
    if(inpTH3DrawingMode == TH3_MODE_ABCD) {
        // AB=CD mode: Start 3-point input
        if(!g_abcdDrawing) {
            g_abcdDrawing = true;
            g_abcdPointCount = 0;
            g_abcdLastClickTime = 0;
            ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
            Print("==================== AB=CD Mode: Click 4 points (X, A, B, C). Right-click to cancel.");
        } else {
            // Cancel current drawing
            g_abcdDrawing = false;
            g_abcdPointCount = 0;
            ObjectDelete(0, "ABCD_Temp_X");
            ObjectDelete(0, "ABCD_Temp_A");
            ObjectDelete(0, "ABCD_Temp_B");
            ObjectDelete(0, "ABCD_Temp_C");
            ObjectDelete(0, "ABCD_Temp_Line_XA");
            ObjectDelete(0, "ABCD_Temp_Line_AB");
            ObjectDelete(0, "ABCD_Temp_Line_BC");
            ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
            ChartRedraw();
            Print("==================== AB=CD creation cancelled");
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

