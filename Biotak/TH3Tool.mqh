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

// Object naming constants (from MT5)
#define TH3_PATTERN_PREFIX      "ABCD_Pattern_"
#define TH3_TEMP_PREFIX         "ABCD_Temp_"
#define TH3_TEMP_LINE_PREFIX    "ABCD_Temp_Line_"
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
//| Reposition all ABCD info labels (lightweight ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â Y update only)    |
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
//| ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Âª ATR ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Cache (ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯)                  |
//| Caches ATR for current bar to avoid repeated calculations       |
//+------------------------------------------------------------------+
double GetCachedDailyATR()
{
    static double cachedATR = 0;
    static int cachedBar = -1;
    
    int currentBar = iBars(NULL, PERIOD_D1);  // MQL4: Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â· 2 Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
    
    // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¶ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ATR ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â 
    if(currentBar != cachedBar || IsZero(cachedATR, EPSILON_PRICE)) {
        double atrValue = iATR(NULL, PERIOD_D1, 14, 0);
        cachedBar = currentBar;
        
        // CRITICAL FIX: Check for EMPTY_VALUE which iATR returns on error
        // Also check for invalid values using epsilon comparison
        if(atrValue == EMPTY_VALUE || IsZero(atrValue, EPSILON_PRICE) || atrValue < Point * 10) {
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
            cachedATR = (validBars > 0) ? (avgRange / validBars) : Point * 100;
        } else {
            cachedATR = atrValue;
        }
    }
    
    return cachedATR;
}

//+------------------------------------------------------------------+
//| Set active AB=CD pattern (for info label display)               |
//| ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ AB=CD (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ info label)                    |
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
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…â€™ Active AB=CD pattern: ", patternName);
    #endif
}

//+------------------------------------------------------------------+
//| Calculate Optimal Default Frequency                             |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶                                    |
//| Analyzes all frequencies to find best default for Steps 3,5,7   |
//+------------------------------------------------------------------+
double CalculateOptimalDefaultFrequency()
{
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶Ãƒâ€ºÃ…â€™:
    // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¡ D ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Step N Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯:
    // frequency = 100 / N
    // 
    // Step 3: 100/3 = 33.333%
    // Step 5: 100/5 = 20.0%
    // Step 7: 100/7 = 14.286%
    
    // ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¬Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±
    double idealFrequencies[3];
    idealFrequencies[0] = 100.0 / 3.0;  // 33.333% for Step 3
    idealFrequencies[1] = 100.0 / 5.0;  // 20.0% for Step 5
    idealFrequencies[2] = 100.0 / 7.0;  // 14.286% for Step 7
    
    int bestIndices[3] = {-1, -1, -1};
    double minErrors[3] = {1000000.0, 1000000.0, 1000000.0};
    
    // Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦
    for(int i = 0; i < 3; i++)
    {
        int bestIdx = FindNearestFreqIndex(idealFrequencies[i]);
        double minError = MathAbs(GetFrequencyByIndex(bestIdx) - idealFrequencies[i]);
        
        bestIndices[i] = bestIdx;
        minErrors[i] = minError;
    }
    
    // Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  OPTIMAL DEFAULT FREQUENCY ANALYSIS");
    Print("========================================");
    Print("Step 3 (Ideal: 33.333%):");
    Print("  ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Closest: ", DoubleToString(GetFrequencyByIndex(bestIndices[0]), 3), 
          "% (Index: ", bestIndices[0], ", Error: ", DoubleToString(minErrors[0], 3), "%)");
    Print("Step 5 (Ideal: 20.0%):");
    Print("  ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Closest: ", DoubleToString(GetFrequencyByIndex(bestIndices[1]), 3), 
          "% (Index: ", bestIndices[1], ", Error: ", DoubleToString(minErrors[1], 3), "%)");
    Print("Step 7 (Ideal: 14.286%):");
    Print("  ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Closest: ", DoubleToString(GetFrequencyByIndex(bestIndices[2]), 3), 
          "% (Index: ", bestIndices[2], ", Error: ", DoubleToString(minErrors[2], 3), "%)");
    Print("========================================");
    
    // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³: Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦
    // Step 5 Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª (Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  50%)
    // Step 3 Ãƒâ„¢Ã‹â€  7 Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ 25% Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
    double weightedFreq = (GetFrequencyByIndex(bestIndices[0]) * 0.25) +
                          (GetFrequencyByIndex(bestIndices[1]) * 0.50) +
                          (GetFrequencyByIndex(bestIndices[2]) * 0.25);
    
    // Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±
    int bestDefaultIdx = FindNearestFreqIndex(weightedFreq);
    double bestDefault = GetFrequencyByIndex(bestDefaultIdx);
    
    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ RECOMMENDED DEFAULT FREQUENCY:");
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
//| ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ (XAÃƒËœÃ…â€™ ABÃƒËœÃ…â€™ BC)                                 |
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
    double AB_XA_TimeRatio;  // ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â  AB / ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â  XA
    double BC_AB_TimeRatio;  // ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â  BC / ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â  AB
    
    // Speed ratios
    double AB_XA_SpeedRatio; // ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª AB / ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª XA
    double BC_AB_SpeedRatio; // ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª BC / ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª AB
    
    // Acceleration (ÃƒËœÃ‚ÂªÃƒËœÃ‚ÂºÃƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â± ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â·Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â )
    double XA_to_AB_Acceleration;  // ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² XA ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ AB (pips/minÃƒâ€šÃ‚Â²)
    double AB_to_BC_Acceleration;  // ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ BC (pips/minÃƒâ€šÃ‚Â²)
    
    // Strength levels (Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± leg)
    double XA_RawStrength;       // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ XA (pips/min)
    double AB_RawStrength;       // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ AB
    double BC_RawStrength;       // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ BC
    double XA_WeightedStrength;  // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± XA (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡)
    double AB_WeightedStrength;  // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± AB
    double BC_WeightedStrength;  // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± BC
    double XA_RelativeStrength;  // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ XA (Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ATR)
    double AB_RelativeStrength;  // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ AB
    double BC_RelativeStrength;  // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ BC
    
    // Pattern characteristics
    bool isImpulsive;        // ÃƒËœÃ‚Â¢Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€  impulsive ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª (Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™)
    bool isCorrectional;     // ÃƒËœÃ‚Â¢Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€  correctional ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª (ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­)
    double avgSpeed;         // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬
    double speedConsistency; // ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª (0-1ÃƒËœÃ…â€™ 1 = ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾)
    double timeSymmetry;     // ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ BC ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ AB (0-1ÃƒËœÃ…â€™ 1 = ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾)
};

WaveAnalysis AnalyzeThreeWaves(datetime tX, double pX, datetime tA, double pA,
                                datetime tB, double pB, datetime tC, double pC)
{
    WaveAnalysis analysis;
    double pipSize = (Digits == 3 || Digits == 5) ? Point * 10 : Point;
    
    // SECURITY: Validate time ordering (X < A < B < C)
    if(!(tX < tA && tA < tB && tB < tC)) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ AnalyzeThreeWaves: Invalid time ordering (X < A < B < C required)");
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
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â·Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ (Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª)
    analysis.XA_Distance = MathAbs(pA - pX);
    analysis.AB_Distance = MathAbs(pB - pA);
    analysis.BC_Distance = MathAbs(pC - pB);
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¯ÃƒËœÃ‚Âª ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ (ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Â¡)
    analysis.XA_Minutes = (int)((tA - tX) / 60);
    analysis.AB_Minutes = (int)((tB - tA) / 60);
    analysis.BC_Minutes = (int)((tC - tB) / 60);
    
    // ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚ÂµÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â±
    if(analysis.XA_Minutes <= 0) analysis.XA_Minutes = 1;
    if(analysis.AB_Minutes <= 0) analysis.AB_Minutes = 1;
    if(analysis.BC_Minutes <= 0) analysis.BC_Minutes = 1;
    
    // CRITICAL FIX: Validate division operands with epsilon check
    if(MathAbs(analysis.AB_Minutes) < 0.001) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ CalculateWaveAnalysis: AB_Minutes too small (", analysis.AB_Minutes, "), cannot calculate speed");
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
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Gann (Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡)
    analysis.XA_Angle = CalculateWaveAngle(tX, pX, tA, pA);
    analysis.AB_Angle = CalculateWaveAngle(tA, pA, tB, pB);
    analysis.BC_Angle = CalculateWaveAngle(tB, pB, tC, pC);
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª
    analysis.AB_XA_Ratio = (analysis.XA_Distance > 0) ? (analysis.AB_Distance / analysis.XA_Distance) : 1.0;
    analysis.BC_AB_Ratio = (analysis.AB_Distance > 0) ? (analysis.BC_Distance / analysis.AB_Distance) : 1.0;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â 
    analysis.AB_XA_TimeRatio = (double)analysis.AB_Minutes / analysis.XA_Minutes;
    analysis.BC_AB_TimeRatio = (double)analysis.BC_Minutes / analysis.AB_Minutes;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª
    analysis.AB_XA_SpeedRatio = (analysis.XA_Speed > 0) ? (analysis.AB_Speed / analysis.XA_Speed) : 1.0;
    analysis.BC_AB_SpeedRatio = (analysis.AB_Speed > 0) ? (analysis.BC_Speed / analysis.AB_Speed) : 1.0;
    
    // ========================================
    // ÃƒÂ°Ã…Â¸Ã…Â¡Ã¢â€šÂ¬ ACCELERATION ANALYSIS (ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ - ÃƒËœÃ‚ÂªÃƒËœÃ‚ÂºÃƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â± ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª)
    // ========================================
    // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾: Acceleration = ÃƒÅ½Ã¢â‚¬ÂVelocity ÃƒÆ’Ã‚Â· ÃƒÅ½Ã¢â‚¬ÂTime
    // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹: Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ (a = ÃƒÅ½Ã¢â‚¬Âv / ÃƒÅ½Ã¢â‚¬Ât)
    
    // ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² XA ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ AB
    double velocityChange_XA_AB = analysis.AB_Speed - analysis.XA_Speed;
    analysis.XA_to_AB_Acceleration = velocityChange_XA_AB / MathMax(analysis.AB_Minutes, 1);
    
    // ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ BC
    double velocityChange_AB_BC = analysis.BC_Speed - analysis.AB_Speed;
    analysis.AB_to_BC_Acceleration = velocityChange_AB_BC / MathMax(analysis.BC_Minutes, 1);
    
    // SECURITY: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ NaN
    if(analysis.XA_to_AB_Acceleration != analysis.XA_to_AB_Acceleration) analysis.XA_to_AB_Acceleration = 0;
    if(analysis.AB_to_BC_Acceleration != analysis.AB_to_BC_Acceleration) analysis.AB_to_BC_Acceleration = 0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã…Â¡Ã¢â€šÂ¬ ACCELERATION ANALYSIS:");
    Print("   XAÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢AB: ", DoubleToString(analysis.XA_to_AB_Acceleration, 4), " pips/minÃƒâ€šÃ‚Â²");
    if(analysis.XA_to_AB_Acceleration > 0.001) {
        Print("      ÃƒÂ¢Ã‚Â¬Ã¢â‚¬Â ÃƒÂ¯Ã‚Â¸Ã‚Â ACCELERATING: Speed increasing (getting stronger)");
    } else if(analysis.XA_to_AB_Acceleration < -0.001) {
        Print("      ÃƒÂ¢Ã‚Â¬Ã¢â‚¬Â¡ÃƒÂ¯Ã‚Â¸Ã‚Â DECELERATING: Speed decreasing (getting weaker)");
    } else {
        Print("      ÃƒÂ¢Ã…Â¾Ã‚Â¡ÃƒÂ¯Ã‚Â¸Ã‚Â CONSTANT: Speed stable");
    }
    
    Print("   ABÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢BC: ", DoubleToString(analysis.AB_to_BC_Acceleration, 4), " pips/minÃƒâ€šÃ‚Â²");
    if(analysis.AB_to_BC_Acceleration > 0.001) {
        Print("      ÃƒÂ¢Ã‚Â¬Ã¢â‚¬Â ÃƒÂ¯Ã‚Â¸Ã‚Â ACCELERATING: Correction speeding up");
    } else if(analysis.AB_to_BC_Acceleration < -0.001) {
        Print("      ÃƒÂ¢Ã‚Â¬Ã¢â‚¬Â¡ÃƒÂ¯Ã‚Â¸Ã‚Â DECELERATING: Correction slowing down");
    } else {
        Print("      ÃƒÂ¢Ã…Â¾Ã‚Â¡ÃƒÂ¯Ã‚Â¸Ã‚Â CONSTANT: Correction speed stable");
    }
    Print("========================================");
    #endif
    
    // ========================================
    // ÃƒÂ°Ã…Â¸Ã¢â‚¬â„¢Ã‚Âª LEG STRENGTH ANALYSIS (ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± leg)
    // ========================================
    // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾: Velocity = Distance ÃƒÆ’Ã‚Â· Time (pips/min)
    // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹: Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ…â€™ TradingView Time-Price Velocity
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ (Raw Strength) = Velocity
    analysis.XA_RawStrength = (analysis.XA_Distance / pipSize) / MathMax(analysis.XA_Minutes, 1);
    analysis.AB_RawStrength = (analysis.AB_Distance / pipSize) / MathMax(analysis.AB_Minutes, 1);
    analysis.BC_RawStrength = (analysis.BC_Distance / pipSize) / MathMax(analysis.BC_Minutes, 1);
    
    // SECURITY: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ NaN
    if(analysis.XA_RawStrength != analysis.XA_RawStrength) analysis.XA_RawStrength = 0;
    if(analysis.AB_RawStrength != analysis.AB_RawStrength) analysis.AB_RawStrength = 0;
    if(analysis.BC_RawStrength != analysis.BC_RawStrength) analysis.BC_RawStrength = 0;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± (Weighted Strength)
    // Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡: ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± = Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
    // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾: Weighted = Raw ÃƒÆ’Ã¢â‚¬â€ sin(angle)
    double angleWeight_XA = MathSin(analysis.XA_Angle * M_PI / 180.0);  // 0-1
    double angleWeight_AB = MathSin(analysis.AB_Angle * M_PI / 180.0);
    double angleWeight_BC = MathSin(analysis.BC_Angle * M_PI / 180.0);
    
    analysis.XA_WeightedStrength = analysis.XA_RawStrength * angleWeight_XA;
    analysis.AB_WeightedStrength = analysis.AB_RawStrength * angleWeight_AB;
    analysis.BC_WeightedStrength = analysis.BC_RawStrength * angleWeight_BC;
    
    // SECURITY: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ NaN
    if(analysis.XA_WeightedStrength != analysis.XA_WeightedStrength) analysis.XA_WeightedStrength = 0;
    if(analysis.AB_WeightedStrength != analysis.AB_WeightedStrength) analysis.AB_WeightedStrength = 0;
    if(analysis.BC_WeightedStrength != analysis.BC_WeightedStrength) analysis.BC_WeightedStrength = 0;
    
    // ========================================
    // OPTIMIZATION: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ATR ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â¯
    // ========================================
    double dailyATR = GetCachedDailyATR();
    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0;  // ATR per minute
    
    if(referenceSpeed <= 0) referenceSpeed = 0.1;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ (Relative Strength)
    // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ATR ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™
    // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾: Relative = Weighted ÃƒÆ’Ã‚Â· (ATR per minute)
    // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹: TradingView ATR Normalization
    analysis.XA_RelativeStrength = analysis.XA_WeightedStrength / referenceSpeed;
    analysis.AB_RelativeStrength = analysis.AB_WeightedStrength / referenceSpeed;
    analysis.BC_RelativeStrength = analysis.BC_WeightedStrength / referenceSpeed;
    
    // SECURITY: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ NaN
    if(analysis.XA_RelativeStrength != analysis.XA_RelativeStrength) analysis.XA_RelativeStrength = 0;
    if(analysis.AB_RelativeStrength != analysis.AB_RelativeStrength) analysis.AB_RelativeStrength = 0;
    if(analysis.BC_RelativeStrength != analysis.BC_RelativeStrength) analysis.BC_RelativeStrength = 0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬â„¢Ã‚Âª LEG STRENGTH ANALYSIS:");
    Print("   XA: Raw=", DoubleToString(analysis.XA_RawStrength, 2), 
          " | Weighted=", DoubleToString(analysis.XA_WeightedStrength, 2),
          " | Relative=", DoubleToString(analysis.XA_RelativeStrength, 2), "x ATR");
    Print("   AB: Raw=", DoubleToString(analysis.AB_RawStrength, 2), 
          " | Weighted=", DoubleToString(analysis.AB_WeightedStrength, 2),
          " | Relative=", DoubleToString(analysis.AB_RelativeStrength, 2), "x ATR");
    Print("   BC: Raw=", DoubleToString(analysis.BC_RawStrength, 2), 
          " | Weighted=", DoubleToString(analysis.BC_WeightedStrength, 2),
          " | Relative=", DoubleToString(analysis.BC_RelativeStrength, 2), "x ATR");
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â´ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âµ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  leg
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
    
    Print("   ÃƒÂ°Ã…Â¸Ã‚ÂÃ¢â‚¬Â  Strongest Leg: ", strongestLeg, " (", DoubleToString(maxStrength, 2), "x ATR)");
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â´ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âµ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª
    if(maxStrength > 3.0) {
        Print("   ÃƒÂ¢Ã…Â¡Ã‚Â¡ VERY STRONG: Explosive movement detected");
    } else if(maxStrength > 2.0) {
        Print("   ÃƒÂ°Ã…Â¸Ã¢â‚¬â„¢Ã‚Âª STRONG: Powerful movement");
    } else if(maxStrength > 1.0) {
        Print("   ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ MODERATE: Normal strength");
    } else {
        Print("   ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â WEAK: Low momentum");
    }
    Print("========================================");
    #endif
    
    // ========================================
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â´ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âµ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€  (ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² referenceSpeed)
    // ========================================
    // Impulsive: Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¹ (ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§)
    // Correctional: Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â Ãƒâ„¢Ã‹â€  ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ (ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â )
    analysis.avgSpeed = (analysis.XA_Speed + analysis.AB_Speed + analysis.BC_Speed) / 3.0;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª (ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â­ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚Â Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
    // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾: StdDev = ÃƒÂ¢Ã‹â€ Ã…Â¡(ÃƒÅ½Ã‚Â£(x - mean)Ãƒâ€šÃ‚Â² / n)
    double speedVariance = MathPow(analysis.XA_Speed - analysis.avgSpeed, 2) +
                          MathPow(analysis.AB_Speed - analysis.avgSpeed, 2) +
                          MathPow(analysis.BC_Speed - analysis.avgSpeed, 2);
    double speedStdDev = MathSqrt(speedVariance / 3.0);
    analysis.speedConsistency = (analysis.avgSpeed > 0) ? (1.0 - MathMin(speedStdDev / analysis.avgSpeed, 1.0)) : 0.5;
    
    // SECURITY: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ NaN
    if(analysis.speedConsistency != analysis.speedConsistency) analysis.speedConsistency = 0.5;
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â´ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âµ impulsive vs correctional (ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² referenceSpeed)
    double avgSpeedRatio = analysis.avgSpeed / referenceSpeed;
    analysis.isImpulsive = (avgSpeedRatio > 1.2);      // ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² 120% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
    analysis.isCorrectional = (avgSpeedRatio < 0.8);   // ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² 80% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ (Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡)
    analysis.timeSymmetry = CalculateTimeSymmetry(tA, tB, tC);
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Calculate Wave Angle (Gann Angle)                               |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ (ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Gann)                                    |
//| Returns: Angle in degrees (0-90)                                |
//| Logic: angle = atan(price_change / time_change)                 |
//+------------------------------------------------------------------+
double CalculateWaveAngle(datetime tStart, double pStart, datetime tEnd, double pEnd)
{
    // SECURITY: Validate inputs
    if(tEnd <= tStart) {
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CalculateWaveAngle: Invalid time range");
        return 0;
    }
    if(pStart <= 0 || pEnd <= 0) {
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CalculateWaveAngle: Invalid prices");
        return 0;
    }
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒËœÃ‚ÂºÃƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â 
    double priceChange = MathAbs(pEnd - pStart);
    int timeChangeMinutes = (int)((tEnd - tStart) / 60);
    if(timeChangeMinutes <= 0) timeChangeMinutes = 1;
    
    // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™: Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â¾
    double pipSize = (Digits == 3 || Digits == 5) ? Point * 10 : Point;
    double priceInPips = priceChange / pipSize;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ (degrees)
    // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™: 1 pip per minute = 45 degrees (Gann 1ÃƒÆ’Ã¢â‚¬â€1)
    // OPTIMIZATION: Use cached ATR instead of repeated iATR() calls
    double dailyATR = GetCachedDailyATR();
    if(dailyATR <= 0 || dailyATR < Point * 10) {
        double avgRange = 0;
        for(int i = 1; i <= 20; i++) {
            avgRange += (iHigh(NULL, PERIOD_D1, i) - iLow(NULL, PERIOD_D1, i));
        }
        dailyATR = avgRange / 20.0;
    }
    
    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0; // pips per minute
    if(referenceSpeed <= 0) referenceSpeed = 0.1;
    
    // ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™
    double actualSpeed = priceInPips / timeChangeMinutes;
    
    // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª (1.0 = 45 degrees)
    double speedRatio = actualSpeed / referenceSpeed;
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡
    // speedRatio = 0 ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ 0Ãƒâ€šÃ‚Â°
    // speedRatio = 1 ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ 45Ãƒâ€šÃ‚Â° (Gann 1ÃƒÆ’Ã¢â‚¬â€1)
    // speedRatio = 2 ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ 63.43Ãƒâ€šÃ‚Â° (Gann 2ÃƒÆ’Ã¢â‚¬â€1)
    // speedRatio = 3 ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ 71.57Ãƒâ€šÃ‚Â° (Gann 3ÃƒÆ’Ã¢â‚¬â€1)
    // speedRatio ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã‹â€ Ã…Â¾ ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ 90Ãƒâ€šÃ‚Â°
    double angle = MathArctan(speedRatio) * 180.0 / M_PI;
    
    // SECURITY: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ NaN
    if(angle != angle) angle = 0;  // NaN check
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ 0-90
    if(angle < 0) angle = 0;
    if(angle > 90) angle = 90;
    
    return angle;
}

//+------------------------------------------------------------------+
//| Calculate Required Rest Candles Based on Angle                  |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡            |
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
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    // CRITICAL FIX #1: Validate movementCandles to prevent overflow
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    if(movementCandles < 0) {
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CalculateRequiredRestCandles: Negative movementCandles (", 
              movementCandles, "), setting to 0");
        movementCandles = 0;
    }
    if(movementCandles > MAX_MOVEMENT_CANDLES) {
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CalculateRequiredRestCandles: movementCandles too large (", 
              movementCandles, "), clamping to ", MAX_MOVEMENT_CANDLES);
        movementCandles = MAX_MOVEMENT_CANDLES;
    }
    
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    // CRITICAL FIX #2: Validate angle
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    if(angle < 0) angle = 0;
    if(angle > 90) angle = 90;
    
    int restCandles = 0;
    
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    // CRITICAL FIX #3: Safe calculation with overflow checks
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    if(angle >= ANGLE_SPIKE_THRESHOLD) {
        // Spike (80-90Ãƒâ€šÃ‚Â°): ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
        double temp = movementCandles * 0.1;
        if(temp > INT_MAX - REST_SPIKE_BASE) {
            restCandles = REST_SPIKE_MAX;
        } else {
            restCandles = REST_SPIKE_BASE + (int)temp;
            if(restCandles > REST_SPIKE_MAX) restCandles = REST_SPIKE_MAX;
        }
    }
    else if(angle >= ANGLE_STRONG_THRESHOLD) {
        // Strong (55-80Ãƒâ€šÃ‚Â°): ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
        double temp = movementCandles * 0.15;
        if(temp > INT_MAX - REST_STRONG_BASE) {
            restCandles = REST_STRONG_MAX;
        } else {
            restCandles = REST_STRONG_BASE + (int)temp;
            if(restCandles > REST_STRONG_MAX) restCandles = REST_STRONG_MAX;
        }
    }
    else if(angle >= ANGLE_BALANCED_THRESHOLD) {
        // Balanced (40-55Ãƒâ€šÃ‚Â°): Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ (Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© Gann 1ÃƒÆ’Ã¢â‚¬â€1)
        double temp = movementCandles * 0.2;
        if(temp > INT_MAX - REST_BALANCED_BASE) {
            restCandles = REST_BALANCED_MAX;
        } else {
            restCandles = REST_BALANCED_BASE + (int)temp;
            if(restCandles > REST_BALANCED_MAX) restCandles = REST_BALANCED_MAX;
        }
    }
    else if(angle >= ANGLE_SLOW_THRESHOLD) {
        // Slow (25-40Ãƒâ€šÃ‚Â°): ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
        double temp = movementCandles * 0.25;
        if(temp > INT_MAX - REST_SLOW_BASE) {
            restCandles = REST_SLOW_MAX;
        } else {
            restCandles = REST_SLOW_BASE + (int)temp;
            if(restCandles > REST_SLOW_MAX) restCandles = REST_SLOW_MAX;
        }
    }
    else {
        // Very Slow (< 25Ãƒâ€šÃ‚Â°): ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
        double temp = movementCandles * 0.3;
        if(temp > INT_MAX - REST_VERY_SLOW_BASE) {
            restCandles = REST_VERY_SLOW_MAX;
        } else {
            restCandles = REST_VERY_SLOW_BASE + (int)temp;
            if(restCandles > REST_VERY_SLOW_MAX) restCandles = REST_VERY_SLOW_MAX;
        }
    }
    
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    // CRITICAL FIX #4: Final validation
    // ÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚ÂÃƒÂ¢Ã¢â‚¬Â¢Ã‚Â
    if(restCandles < 0) restCandles = 0;
    if(restCandles > MAX_REST_CANDLES) {
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CalculateRequiredRestCandles: Result too large (", restCandles, 
              "), clamping to ", MAX_REST_CANDLES);
        restCandles = MAX_REST_CANDLES;
    }
    
    return restCandles;
}

//+------------------------------------------------------------------+
//| Determine Reference Timeframe Based on Wave Size                |
//| ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬                          |
//| Returns: TH percentage for reference timeframe                  |
//| Logic: Wave size (in TH units) determines structure timeframe   |
//+------------------------------------------------------------------+
double DetermineReferenceTimeframe(double waveDistance, double currentTH)
{
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯ TH
    double waveSizeInTH = (currentTH > 0) ? (waveDistance / currentTH) : 0;
    
    // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â : Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ 3 ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± TH Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â³ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¹ = waveSizeInTH / 3
    
    // Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾
    double targetTHMultiplier = waveSizeInTH / 3.0;
    
    // ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¬Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ MODIFIED_FRACTAL_PERCENTAGES
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
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨ Consolidation - Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¡ (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Gann)             |
//| Considers: angle, rest candles, energy buildup                  |
//| OPTIMIZED: Uses pre-calculated wave analysis                    |
//+------------------------------------------------------------------+
double CalculateConsolidationFactor(datetime tA, datetime tB, datetime tC, 
                                     WaveAnalysis &waves)
{
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 1: ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
    // ========================================
    double angleAB = waves.AB_Angle;  // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² struct ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 2: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ AB Ãƒâ„¢Ã‹â€  BC
    // ========================================
    int barA = iBarShift(NULL, 0, tA);
    int barB = iBarShift(NULL, 0, tB);
    int barC = iBarShift(NULL, 0, tC);
    
    int AB_Candles = MathAbs(barA - barB);
    int BC_Candles = MathAbs(barB - barC);
    
    if(AB_Candles < 1) AB_Candles = 1;
    if(BC_Candles < 1) BC_Candles = 1;
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 3: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²
    // ========================================
    int requiredRestCandles = CalculateRequiredRestCandles(angleAB, AB_Candles);
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 4: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²
    // ========================================
    double restRatio = (double)BC_Candles / requiredRestCandles;
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 5: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨ consolidation
    // ========================================
    double consolidationFactor = 0.0;
    
    if(restRatio < 0.3) {
        // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ (< 30% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²)
        // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒÅ¡Ã‹Å“Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ breakout Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™
        consolidationFactor = 0.9;
    }
    else if(restRatio < 0.6) {
        // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ (30-60% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²)
        // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒÅ¡Ã‹Å“Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â· ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
        consolidationFactor = 0.7;
    }
    else if(restRatio < 1.0) {
        // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ (60-100% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²)
        // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒÅ¡Ã‹Å“Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
        consolidationFactor = 0.4;
    }
    else if(restRatio < 1.5) {
        // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ (100-150% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²)
        // ÃƒËœÃ‚Â­ÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™
        consolidationFactor = 0.1;
    }
    else {
        // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ (> 150% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²)
        // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒÅ¡Ã‹Å“Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
        consolidationFactor = 0.0;
    }
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 6: ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡
    // ========================================
    // ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ consolidation ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
    if(angleAB >= 80) {
        consolidationFactor *= 1.3; // Spike: +30%
    }
    else if(angleAB >= 55) {
        consolidationFactor *= 1.15; // Strong: +15%
    }
    // else: Normal
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ 0-1
    if(consolidationFactor > 1.0) consolidationFactor = 1.0;
    if(consolidationFactor < 0.0) consolidationFactor = 0.0;
    
    return consolidationFactor;
}

//+------------------------------------------------------------------+
//| Calculate Optimal Frequency from Wave Analysis                  |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬                                |
//| Integrates: speed, consolidation, consistency, Fibonacci        |
//+------------------------------------------------------------------+
double CalculateFrequencyFromWaves(WaveAnalysis &waves)
{
    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒÅ¡Ã‹Å“Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬:
    // 1. ÃƒËœÃ‚Â´ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ (Step 5 = 20%)
    // 2. ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€  (Impulsive/Correctional)
    // 3. ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡ (Gann-inspired)
    // 4. ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª
    // 5. ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Fibonacci
    
    double baseFrequency = 20.0; // Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Step 5
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 1: ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ 
    // ========================================
    if(waves.isImpulsive) {
        baseFrequency *= 1.3; // ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ 30% ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™
    }
    else if(waves.isCorrectional) {
        baseFrequency *= 0.7; // ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ 30% ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â
    }
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 2: ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª (Gann-inspired)
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ATR
    // OPTIMIZATION: Use cached ATR instead of repeated iATR() calls
    double dailyATR = GetCachedDailyATR();
    double pipSize = (Digits == 3 || Digits == 5) ? Point * 10 : Point;
    
    if(dailyATR <= 0 || dailyATR < Point * 10) {
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
    
    // ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª (Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¡ Gann)
    double speedWeight = 1.0;
    if(avgSpeedRatio >= 3.0) {
        speedWeight = 1.5; // ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¹
    }
    else if(avgSpeedRatio >= 2.0) {
        speedWeight = 1.3; // ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¹ (Gann 2ÃƒÆ’Ã¢â‚¬â€1)
    }
    else if(avgSpeedRatio >= 1.5) {
        speedWeight = 1.15; // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¹ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¹
    }
    else if(avgSpeedRatio >= 0.8 && avgSpeedRatio <= 1.2) {
        speedWeight = 1.0; // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ (Gann 1ÃƒÆ’Ã¢â‚¬â€1)
    }
    else if(avgSpeedRatio >= 0.5) {
        speedWeight = 0.85; // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¹ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ (Gann 1ÃƒÆ’Ã¢â‚¬â€2)
    }
    else if(avgSpeedRatio >= 0.33) {
        speedWeight = 0.7; // ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
    }
    else {
        speedWeight = 0.6; // ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
    }
    
    baseFrequency *= speedWeight;
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 3: ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª
    // ========================================
    // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒËœÃ‚Â«ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦
    double consistencyFactor = 0.8 + (waves.speedConsistency * 0.4); // 0.8 ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ 1.2
    baseFrequency *= consistencyFactor;
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 4: ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª AB/XA (Fibonacci)
    // ========================================
    // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Fibonacci ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
    double fibRatios[7] = {0.382, 0.5, 0.618, 0.786, 1.0, 1.272, 1.618};
    double minFibDiff = 1000.0;
    
    for(int i = 0; i < 7; i++) {
        double diff = MathAbs(waves.AB_XA_Ratio - fibRatios[i]);
        if(diff < minFibDiff) minFibDiff = diff;
    }
    
    // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Fibonacci ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯ (< 0.1)ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
    if(minFibDiff < 0.1) {
        baseFrequency *= 1.1; // ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ 10%
    }
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 5: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±
    // ========================================
    if(baseFrequency < 3.125) baseFrequency = 3.125;
    if(baseFrequency > 120.0) baseFrequency = 120.0; // Extended to 120%
    
    return baseFrequency;
}
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª ÃƒËœÃ‚Â­ÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Âª (ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Gann) - ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡              |
//| Returns: Speed ratio relative to reference (1.0 = balanced)     |
//| > 1.0 = Fast move, < 1.0 = Slow move                           |
//+------------------------------------------------------------------+
double CalculateMovementSpeed(datetime tA, double pA, datetime tB, double pB)
{
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒËœÃ‚ÂºÃƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â 
    double priceChange = MathAbs(pB - pA);
    int timeChangeMinutes = (int)((tB - tA) / 60); // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Â¡
    
    if(timeChangeMinutes <= 0) return 1.0; // Default to balanced
    
    // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™: Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â¾
    double pipSize = (Digits == 3 || Digits == 5) ? Point * 10 : Point;
    double priceInPips = priceChange / pipSize;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª: Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â¾ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Â¡
    double speed = priceInPips / timeChangeMinutes;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¹ (benchmark) ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ATR
    double dailyATR = GetCachedDailyATR();  // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² cache
    
    double dailyATRInPips = dailyATR / pipSize;
    
    // ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¹: ATR ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± 1440 ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Â¡ (Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²)
    double referenceSpeed = dailyATRInPips / 1440.0;
    
    // FIX: ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚ÂµÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â 
    if(referenceSpeed <= 0) referenceSpeed = 0.1; // ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¹
    
    // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª: ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ / ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¹
    double speedRatio = speed / referenceSpeed;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ (0.1 ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ 10)
    if(speedRatio < 0.1) speedRatio = 0.1;
    if(speedRatio > 10.0) speedRatio = 10.0;
    
    return speedRatio;
}

//+------------------------------------------------------------------+
//| Calculate Time Symmetry Factor                                  |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  AB Ãƒâ„¢Ã‹â€  BC                             |
//| Perfect symmetry (AB time = BC time) = 1.0                      |
//+------------------------------------------------------------------+
double CalculateTimeSymmetry(datetime tA, datetime tB, datetime tC)
{
    int timeAB = (int)((tB - tA) / 60); // ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Â¡
    int timeBC = (int)((tC - tB) / 60); // ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Â¡
    
    if(timeAB <= 0 || timeBC <= 0) return 1.0;
    
    // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â : Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒÅ¡Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ 1ÃƒËœÃ…â€™ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
    // CRITICAL FIX: Validate division operands
    double ratio = 0;
    if(timeAB > 0 && timeBC > 0) {
        ratio = (timeAB > timeBC) ? ((double)timeBC / timeAB) : ((double)timeAB / timeBC);
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CalculateTimeSymmetry: Invalid time values - AB=", timeAB, ", BC=", timeBC);
        #endif
    }
    
    return ratio;
}

//+------------------------------------------------------------------+
//| Frequency Search Result Structure                               |
//| ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â®ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¬Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³                                      |
//+------------------------------------------------------------------+
struct FrequencySearchResult {
    double frequency;        // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³
    int frequencyIndex;      // ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡
    int targetStep;          // ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚Â (3ÃƒËœÃ…â€™ 5ÃƒËœÃ…â€™ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ 7)
    double errorPercent;     // ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚ÂµÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§
    double calculatedD;      // Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ D
    double targetPrice;      // Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚Â (Step N)
    double errorPips;        // ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â¾
    double gannAngle;        // ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Gann Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ AB
    double angleWeight;      // ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡
    double timeSymmetry;     // ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ AB/BC
    double totalScore;       // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾ (ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± = ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±)
};

//+------------------------------------------------------------------+
//| Analyze Harmonic Properties (Scientific Analysis)               |
//| ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‹Å“ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© (ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™)                           |
//| Returns: Detailed analysis of harmonic ratios                   |
//+------------------------------------------------------------------+
void AnalyzeHarmonicProperties(WaveAnalysis &waves)
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Âµ HARMONIC ANALYSIS (SCIENTIFIC)");
    Print("========================================");
    
    // ========================================
    // 1. HARMONIC MEAN ANALYSIS
    // ========================================
    if(waves.XA_Speed > 0 && waves.AB_Speed > 0 && waves.BC_Speed > 0) {
        double recipSum = (1.0/waves.XA_Speed) + (1.0/waves.AB_Speed) + (1.0/waves.BC_Speed);
        double harmonicMean = 3.0 / recipSum;
        double arithmeticMean = (waves.XA_Speed + waves.AB_Speed + waves.BC_Speed) / 3.0;
        double geometricMean = MathPow(waves.XA_Speed * waves.AB_Speed * waves.BC_Speed, 1.0/3.0);
        
        Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  PYTHAGOREAN MEANS:");
        Print("   Harmonic Mean:   ", DoubleToString(harmonicMean, 2), " pips/min");
        Print("   Geometric Mean:  ", DoubleToString(geometricMean, 2), " pips/min");
        Print("   Arithmetic Mean: ", DoubleToString(arithmeticMean, 2), " pips/min");
        Print("   Relationship: HM ÃƒÂ¢Ã¢â‚¬Â°Ã‚Â¤ GM ÃƒÂ¢Ã¢â‚¬Â°Ã‚Â¤ AM ", 
              (harmonicMean <= geometricMean && geometricMean <= arithmeticMean) ? "ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦" : "ÃƒÂ¢Ã‚ÂÃ…â€™");
        
        double meanRatio = harmonicMean / arithmeticMean;
        Print("   HM/AM Ratio: ", DoubleToString(meanRatio, 3));
        if(meanRatio > 0.9) {
            Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ EXCELLENT: Very consistent speeds");
        } else if(meanRatio > 0.8) {
            Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ GOOD: Moderately consistent speeds");
        } else if(meanRatio > 0.7) {
            Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â FAIR: Some speed variation");
        } else {
            Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã‚ÂÃ…â€™ POOR: High speed variation");
        }
    }
    
    // ========================================
    // 2. GOLDEN RATIO ANALYSIS (PHI)
    // ========================================
    double phi = 1.618033988749;
    double phiInverse = 0.618033988749;
    
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â GOLDEN RATIO (ÃƒÂÃ¢â‚¬Â  = 1.618):");
    
    // AB/XA ratio
    double phiDev_AB_XA = MathAbs(waves.AB_XA_Ratio - phiInverse);
    Print("   AB/XA = ", DoubleToString(waves.AB_XA_Ratio, 3));
    if(phiDev_AB_XA < 0.05) {
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã…â€œÃ‚Â¨ GOLDEN RATIO (0.618) detected! Deviation: ", 
              DoubleToString(phiDev_AB_XA * 100, 1), "%");
    } else {
        double phiDev_ext = MathAbs(waves.AB_XA_Ratio - phi);
        if(phiDev_ext < 0.08) {
            Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã…â€œÃ‚Â¨ PHI EXTENSION (1.618) detected! Deviation: ", 
                  DoubleToString(phiDev_ext * 100, 1), "%");
        } else {
            Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ No Golden Ratio (deviation: ", DoubleToString(phiDev_AB_XA * 100, 1), "%)");
        }
    }
    
    // BC/AB ratio
    double phiDev_BC_AB = MathAbs(waves.BC_AB_Ratio - phiInverse);
    Print("   BC/AB = ", DoubleToString(waves.BC_AB_Ratio, 3));
    if(phiDev_BC_AB < 0.05) {
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒÂ¢Ã…â€œÃ‚Â¨ GOLDEN RATIO (0.618) detected! Deviation: ", 
              DoubleToString(phiDev_BC_AB * 100, 1), "%");
    } else {
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ No Golden Ratio (deviation: ", DoubleToString(phiDev_BC_AB * 100, 1), "%)");
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
    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ HARMONIC QUALITY: ", harmonicScore, "/2");
    if(harmonicScore == 2) {
        Print("   ÃƒÂ¢Ã‚Â­Ã‚ÂÃƒÂ¢Ã‚Â­Ã‚Â EXCELLENT: Strong harmonic properties");
    } else if(harmonicScore == 1) {
        Print("   ÃƒÂ¢Ã‚Â­Ã‚Â GOOD: Some harmonic properties");
    } else {
        Print("   ÃƒÂ¢Ã…Â¾Ã‚Â¡ÃƒÂ¯Ã‚Â¸Ã‚Â NORMAL: No special harmonic properties");
    }
    Print("========================================");
    #endif
}

//+------------------------------------------------------------------+
//| Calculate Frequency Error for AB=CD Pattern                     |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  AB=CD                              |
//| Returns: Error percentage (0 = perfect match)                   |
//| CRITICAL FIX: Added division by zero protection                 |
//+------------------------------------------------------------------+
double CalculateFrequencyError(double pA, double pB, double pC, 
                               double frequency, int targetStep,
                               double &calculatedD, double &targetPrice)
{
    // SECURITY: Validate AB distance to prevent division by zero
    double AB_Distance = MathAbs(pB - pA);
    double minDistance = Point * 10; // Minimum 10 pips
    
    if(AB_Distance < minDistance) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ CalculateFrequencyError: AB distance too small (", 
              DoubleToString(AB_Distance, Digits), ") - minimum ", 
              DoubleToString(minDistance, Digits), " required");
        calculatedD = 0.0;
        targetPrice = 0.0;
        return 999.99; // Invalid error
    }
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡
    // baseUnit = AB ÃƒÆ’Ã¢â‚¬â€ (frequency / 100) Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ TH ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
    bool isBullish = (pB > pA);
    double baseUnit = AB_Distance * (frequency / 100.0);
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ D ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â  AB=CD
    // ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  AB=CD: Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ CD ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ AB ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    double pD;
    if(isBullish) {
        pD = pC + AB_Distance;
    } else {
        pD = pC - AB_Distance;
    }
    calculatedD = pD;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚Â (Step N ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² C)
    // Step N = C + (N ÃƒÆ’Ã¢â‚¬â€ baseUnit)
    double stepPrice;
    if(isBullish) {
        stepPrice = pC + (targetStep * baseUnit);
    } else {
        stepPrice = pC - (targetStep * baseUnit);
    }
    targetPrice = stepPrice;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§: Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  D Ãƒâ„¢Ã‹â€  Step N
    // ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂµÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚ÂµÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    double error = MathAbs(pD - stepPrice);
    
    // CRITICAL FIX: Validate division operand
    double errorPercent = 0;
    if(MathAbs(AB_Distance) > 0.000001) {
        errorPercent = (error / AB_Distance) * 100.0;
    } else {
        #ifdef ENABLE_DEBUG_LOGS
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CalculateFrequencyError: AB_Distance too small (", AB_Distance, ")");
        #endif
    }
    
    return errorPercent;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Deviation                                   |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â­ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Fibonacci                             |
//| Returns: Minimum deviation from standard Fibonacci ratios       |
//+------------------------------------------------------------------+
double CalculateFibonacciDeviation(double ratio)
{
    // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯ Fibonacci
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
//| Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  XABCD - ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾            |
//| Multi-factor scoring: error, wave analysis, Fibonacci, symmetry |
//+------------------------------------------------------------------+
int FindOptimalFrequencyForABCD(datetime tX, double pX, datetime tA, double pA, 
                                datetime tB, double pB, datetime tC, double pC,
                                FrequencySearchResult &results[],
                                double maxErrorPercent = 5.0)
{
    // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬
    ArrayResize(results, 0);
    
    double AB_Distance = MathAbs(pB - pA);
    if(AB_Distance <= 0) return 0;
    
    double pipSize = (Digits == 3 || Digits == 5) ? Point * 10 : Point;
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 1: ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ (Wave Analysis)
    // ========================================
    WaveAnalysis waves = AnalyzeThreeWaves(tX, pX, tA, pA, tB, pB, tC, pC);
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‹Å“ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© (ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™)
    AnalyzeHarmonicProperties(waves);
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬
    double suggestedFreq = CalculateFrequencyFromWaves(waves);
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™
    double speedRatio = CalculateMovementSpeed(tA, pA, tB, pB);
    double timeSymmetry = waves.timeSymmetry;  // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± struct
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â­ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Fibonacci
    double fibDeviation = CalculateFibonacciDeviation(waves.AB_XA_Ratio);
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨ Consolidation (ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒÅ¡Ã‹Å“Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ breakout)
    double consolidationFactor = CalculateConsolidationFactor(tA, tB, tC, waves);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â COMPLETE WAVE ANALYSIS (X-A-B-C):");
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
    
    // Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ÃƒËœÃ‚Âª Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
    if(waves.speedConsistency < 0.5) {
        Print("   ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â WARNING: Low speed consistency - results may be unreliable");
    } else if(waves.speedConsistency < 0.7) {
        Print("   ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â CAUTION: Moderate speed consistency");
    } else {
        Print("   ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Good speed consistency");
    }
    
    // Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ consolidation ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§
    if(consolidationFactor > 0.7) {
        Print("   ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â¥ HIGH CONSOLIDATION: Expect strong breakout - using larger steps");
    } else if(consolidationFactor > 0.4) {
        Print("   ÃƒÂ¢Ã…Â¡Ã‚Â¡ MODERATE CONSOLIDATION: Some energy buildup detected");
    }
    
    Print("========================================");
    #endif
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 2: ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© (Advanced Harmonic Analysis)
    // ========================================
    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Gann ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¹ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ (ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² struct)
    double gannAngle = waves.AB_Angle;
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª BC/AB ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â´ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âµ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­
    double bcToAbRatio = 0.0;
    if(waves.AB_Distance > 0) {
        bcToAbRatio = waves.BC_Distance / waves.AB_Distance;
    }
    
    // ========================================
    // ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ HARMONIC PATTERN RECOGNITION (Gartley, Bat, Butterfly, Crab)
    // ========================================
    // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Fibonacci ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯
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
    // ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â ANDREWS PITCHFORK MEDIAN LINE ANALYSIS
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â  80%: Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª 80% Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â· Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ (Median Line) ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Median Line ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â´ÃƒËœÃ‚Âª
    double medianPrice = (pX + pA + pB) / 3.0;  // Median of X, A, B
    double currentDistanceFromMedian = MathAbs(pC - medianPrice);
    double maxDistanceFromMedian = MathMax(MathAbs(pA - medianPrice), MathAbs(pB - medianPrice));
    
    double medianLineDeviation = 0.0;
    if(maxDistanceFromMedian > 0) {
        medianLineDeviation = currentDistanceFromMedian / maxDistanceFromMedian;
    }
    
    // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Median ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (>80%)ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â´ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
    bool strongMedianLinePull = (medianLineDeviation > 0.8);
    bool moderateMedianLinePull = (medianLineDeviation > 0.5 && medianLineDeviation <= 0.8);
    
    // ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Median Line
    double medianLineFrequency = 0.0;
    if(strongMedianLinePull) {
        // Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Median ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¸ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â´ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
        medianLineFrequency = 55.0 + (medianLineDeviation * 30.0);  // 55-85% range
    } else if(moderateMedianLinePull) {
        // Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â· ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Median ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â´ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â· ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·
        medianLineFrequency = 35.0 + (medianLineDeviation * 30.0);  // 35-65% range
    }
    
    // ========================================
    // ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ AB=CD PATTERN VALIDATION
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â  AB=CD: BC ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ 61.8% retracement ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    //              CD ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ 127.2% extension ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² BC ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    bool isValidABCD = false;
    double abcdScore = 0.0;
    
    // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ BC retracement (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© 0.618 ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡)
    double bcRetracementError = MathAbs(bcToAbRatio - 0.618);
    if(bcRetracementError < 0.15) {  // ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ Ãƒâ€šÃ‚Â±15%
        isValidABCD = true;
        abcdScore = 1.0 - (bcRetracementError / 0.15);  // 0-1 score
    }
    
    // ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·
    bool isStrongImpulsive = (gannAngle > 75.0 && consolidationFactor < 0.1);
    bool isMediumImpulsive = (gannAngle >= 50.0 && gannAngle <= 75.0 && consolidationFactor < 0.1);
    bool hasDeepRetracement = (bcToAbRatio > 0.7);
    bool hasGoodTimeSymmetry = (timeSymmetry > 0.8);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ ADVANCED HARMONIC & PITCHFORK ANALYSIS:");
    Print("========================================");
    
    // Harmonic Pattern Detection
    if(harmonicPattern != "NONE") {
        Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  HARMONIC PATTERN: ", harmonicPattern);
        Print("   AB/XA Ratio: ", DoubleToString(waves.AB_XA_Ratio, 3));
        Print("   BC/AB Ratio: ", DoubleToString(bcToAbRatio, 3));
        Print("   Confidence Level: ", DoubleToString(harmonicConfidence, 3));
        Print("   PRZ Frequency: ", DoubleToString(prz_Frequency, 1), "%");
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Using harmonic-based frequency selection");
    }
    
    // Median Line Analysis
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â ANDREWS PITCHFORK (Median Line):");
    Print("   Median Price: ", DoubleToString(medianPrice, Digits));
    Print("   Distance from Median: ", DoubleToString(medianLineDeviation * 100, 1), "%");
    if(strongMedianLinePull) {
        Print("   ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ STRONG PULL: Price far from median (>80%)");
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Expect strong reversal to median");
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Median Frequency: ", DoubleToString(medianLineFrequency, 1), "%");
    } else if(moderateMedianLinePull) {
        Print("   ÃƒÂ¢Ã…Â¡Ã‚Â¡ MODERATE PULL: Price moderately far (50-80%)");
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Median Frequency: ", DoubleToString(medianLineFrequency, 1), "%");
    } else {
        Print("   ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Near Median: Price close to equilibrium");
    }
    
    // AB=CD Validation
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ AB=CD PATTERN VALIDATION:");
    Print("   BC Retracement: ", DoubleToString(bcToAbRatio, 3), " (Target: 0.618)");
    Print("   Error: ", DoubleToString(bcRetracementError, 3));
    if(isValidABCD) {
        Print("   ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ VALID AB=CD: Score ", DoubleToString(abcdScore * 100, 1), "%");
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Using AB=CD frequency rules");
    } else {
        Print("   ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â Not a classic AB=CD pattern");
    }
    
    Print("========================================");
    
    // Original Impulsive Pattern Detection
    if(isStrongImpulsive) {
        Print("ÃƒÂ°Ã…Â¸Ã…Â¡Ã¢â€šÂ¬ STRONG IMPULSIVE PATTERN DETECTED:");
        Print("   Gann Angle: ", DoubleToString(gannAngle, 2), "Ãƒâ€šÃ‚Â° (>75Ãƒâ€šÃ‚Â°)");
        Print("   Consolidation: ", DoubleToString(consolidationFactor * 100, 1), "% (<10%)");
        Print("   BC/AB Ratio: ", DoubleToString(bcToAbRatio, 3));
        if(hasDeepRetracement) {
            Print("   Deep Retracement: YES - Expect strong continuation");
        }
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Adjusting scoring: Prefer higher frequencies (50-70% range)");
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Reducing penalties for low consistency and time symmetry");
    }
    else if(isMediumImpulsive) {
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â¡ MEDIUM IMPULSIVE PATTERN DETECTED:");
        Print("   Gann Angle: ", DoubleToString(gannAngle, 2), "Ãƒâ€šÃ‚Â° (50-75Ãƒâ€šÃ‚Â°)");
        Print("   Consolidation: ", DoubleToString(consolidationFactor * 100, 1), "% (<10%)");
        Print("   BC/AB Ratio: ", DoubleToString(bcToAbRatio, 3));
        Print("   Time Symmetry: ", DoubleToString(timeSymmetry * 100, 1), "%");
        if(hasGoodTimeSymmetry) {
            Print("   Good Time Symmetry: Pattern is reliable");
        }
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Adjusting scoring: Prefer frequencies (35-50% range)");
        Print("   ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Reducing penalties for low consistency");
    }
    Print("========================================");
    #endif
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 3: ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™
    // ========================================
    int targetSteps[10] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    int primarySteps[3] = {3, 5, 7}; // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§
    
    // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ 2-3-4 ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    if(isStrongImpulsive) {
        primarySteps[0] = 2;
        primarySteps[1] = 3;
        primarySteps[2] = 4;
    }
    // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ 2-3-5 ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    else if(isMediumImpulsive) {
        primarySteps[0] = 2;
        primarySteps[1] = 3;
        primarySteps[2] = 5;
    }
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 4: ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â¢Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ candidate
    // ========================================
    bool candidateFreqs[MAX_TH3_FREQ_INDEX + 1]; // Binary subdivision indices
    ArrayInitialize(candidateFreqs, false);
    
    // ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´ 1: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶Ãƒâ€ºÃ…â€™ (100/N)
    for(int stepIdx = 0; stepIdx < 3; stepIdx++)
    {
        int targetStep = primarySteps[stepIdx];
        double idealFreq = 100.0 / targetStep;
        
        int closestIdx = FindNearestFreqIndex(idealFreq);
        
        // Mark Ãƒâ€šÃ‚Â±5 Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â·ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚Â
        int startIdx = MathMax(MIN_TH3_FREQ_INDEX, closestIdx - 5);
        int endIdx = MathMin(MAX_TH3_FREQ_INDEX, closestIdx + 5);
        
        for(int i = startIdx; i <= endIdx; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    
    // ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´ 2: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ (suggested frequency)
    if(suggestedFreq > 0 && suggestedFreq <= 100.0)
    {
        int closestIdx = FindNearestFreqIndex(suggestedFreq);
        
        // Mark Ãƒâ€šÃ‚Â±3 Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â·ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚Â suggested frequency
        int startIdx = MathMax(MIN_TH3_FREQ_INDEX, closestIdx - 3);
        int endIdx = MathMin(MAX_TH3_FREQ_INDEX, closestIdx + 3);
        
        for(int i = startIdx; i <= endIdx; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    
    // ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´ 3: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ 50-70% ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â 
    if(isStrongImpulsive) {
        int impStart = FindNearestFreqIndex(50.0);
        int impEnd = FindNearestFreqIndex(70.0);
        for(int i = impStart; i <= impEnd; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    // ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´ 4: ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·ÃƒËœÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ 35-50% ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â 
    else if(isMediumImpulsive) {
        int medStart = FindNearestFreqIndex(35.0);
        int medEnd = FindNearestFreqIndex(50.0);
        for(int i = medStart; i <= medEnd; i++)
        {
            candidateFreqs[i] = true;
        }
    }
    
    // ========================================
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 5: ÃƒËœÃ‚ÂªÃƒËœÃ‚Â³ÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™
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
            // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ (Multi-factor Scoring)
            // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
            // ========================================
            
            // ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Âª Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
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
            
            // 1. ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª Step (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            double stepPriority = 1.0;
            if(testStep == 5) {
                stepPriority = w_step5Priority;  // Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
            } else if(testStep == 3 || testStep == 7) {
                stepPriority = w_step3_7Priority;  // Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
            } else if(testStep == 1) {
                stepPriority = w_step1Priority;  // Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
            }
            
            // 2. ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶Ãƒâ€ºÃ…â€™ (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            double errorScore = errorPercent * w_errorWeight;
            
            // 3. ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            // ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± = ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â³ (1 - consistency) ÃƒÆ’Ã¢â‚¬â€ 20
            // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·ÃƒËœÃ…â€™ penalty ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
            double speedConsistencyWeight = w_speedConsistencyWeight;
            if(isStrongImpulsive) {
                speedConsistencyWeight *= 0.3;  // ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ 70% penalty
            }
            else if(isMediumImpulsive) {
                speedConsistencyWeight *= 0.5;  // ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ 50% penalty
            }
            double speedScore = (1.0 - waves.speedConsistency) * 20.0 * speedConsistencyWeight;
            
            // 4. ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            // ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± = ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â³ (1 - symmetry) ÃƒÆ’Ã¢â‚¬â€ 100
            // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ…â€™ penalty ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
            // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â· ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¨ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
            double timeSymmetryWeight = w_timeSymmetryWeight;
            if(isStrongImpulsive && hasDeepRetracement) {
                timeSymmetryWeight *= 0.2;  // ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ 80% penalty
            }
            else if(isMediumImpulsive && hasGoodTimeSymmetry) {
                timeSymmetryWeight *= 0.5;  // ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ 50% penalty (ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¨ = ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯)
            }
            double timeScore = (1.0 - timeSymmetry) * 100.0 * timeSymmetryWeight;
            
            // 5. ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â­ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Fibonacci (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            // ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± = ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
            double fibScore = fibDeviation * 100.0 * w_fibonacciWeight;
            
            // 6. ÃƒËœÃ‚ÂªÃƒËœÃ‚Â·ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ suggested frequency (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            double freqDeviation = 0.0;
            if(suggestedFreq > 0) {
                freqDeviation = MathAbs(testFreq - suggestedFreq) / suggestedFreq;
            }
            double freqScore = freqDeviation * 100.0 * w_freqDeviationWeight;
            
            // 7. Consolidation factor (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± consolidation ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± (ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â²ÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±) ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â­ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
            // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â³ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± penalty Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â 
            double consolidationPenalty = 0.0;
            if(consolidationFactor > 0.3) {
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² suggested ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ penalty ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
                if(testFreq < suggestedFreq) {
                    double freqRatio = testFreq / suggestedFreq;
                    consolidationPenalty = (1.0 - freqRatio) * consolidationFactor * 100.0 * w_consolidationWeight;
                }
            }
            
            // 8. ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª Step Priority (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
            // ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â  ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡
            double stepPriorityScore = stepPriority * w_stepPriorityWeight;
            
            // 9. ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Impulsive
            double impulsiveBonus = 0.0;
            if(isStrongImpulsive) {
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ 50-70% ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ (ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± = ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±)
                if(testFreq >= 50.0 && testFreq <= 70.0) {
                    impulsiveBonus = -50.0;  // ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ = ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
                }
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ penalty ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
                else if(testFreq < 30.0) {
                    impulsiveBonus = 100.0;  // penalty ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
                }
            }
            else if(isMediumImpulsive) {
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ 35-50% ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
                if(testFreq >= 35.0 && testFreq <= 50.0) {
                    impulsiveBonus = -30.0;  // ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·
                }
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ penalty ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
                else if(testFreq < 25.0) {
                    impulsiveBonus = 80.0;  // penalty ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
                }
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
                if(hasGoodTimeSymmetry && testFreq >= 40.0 && testFreq <= 45.0) {
                    impulsiveBonus -= 20.0;  // ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¨
                }
            }
            
            // ========================================
            // 10. ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ HARMONIC PATTERN BONUS (NEW)
            // ========================================
            double harmonicBonus = 0.0;
            if(harmonicPattern != "NONE" && prz_Frequency > 0) {
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© PRZ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
                double przDeviation = MathAbs(testFreq - prz_Frequency) / prz_Frequency;
                if(przDeviation < 0.15) {  // Ãƒâ€šÃ‚Â±15% tolerance
                    harmonicBonus = -40.0 * (1.0 - przDeviation / 0.15);  // Max -40 bonus
                    
                    // ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
                    if(harmonicPattern == "CRAB") harmonicBonus *= 1.3;  // Crab = Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
                    else if(harmonicPattern == "BUTTERFLY") harmonicBonus *= 1.2;
                    else if(harmonicPattern == "BAT") harmonicBonus *= 1.1;
                }
            }
            
            // ========================================
            // 11. ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â MEDIAN LINE BONUS (NEW)
            // ========================================
            double medianLineBonus = 0.0;
            if(medianLineFrequency > 0) {
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© Median Line Frequency ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
                double medianDeviation = MathAbs(testFreq - medianLineFrequency) / medianLineFrequency;
                if(medianDeviation < 0.20) {  // Ãƒâ€šÃ‚Â±20% tolerance
                    if(strongMedianLinePull) {
                        // Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Median ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™
                        medianLineBonus = -35.0 * (1.0 - medianDeviation / 0.20);  // Max -35 bonus
                    } else if(moderateMedianLinePull) {
                        // Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â· ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Median ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·
                        medianLineBonus = -20.0 * (1.0 - medianDeviation / 0.20);  // Max -20 bonus
                    }
                }
            }
            
            // ========================================
            // 12. ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ AB=CD VALIDATION BONUS (NEW)
            // ========================================
            double abcdBonus = 0.0;
            if(isValidABCD) {
                // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ AB=CD Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ score
                // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ 25-45% ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© AB=CD)
                if(testFreq >= 25.0 && testFreq <= 45.0) {
                    abcdBonus = -30.0 * abcdScore;  // Max -30 bonus
                    
                    // ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© 38.2% ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (Fibonacci 0.382)
                    if(testFreq >= 36.0 && testFreq <= 40.0) {
                        abcdBonus -= 15.0;  // Extra -15 bonus
                    }
                }
            }
            
            // ========================================
            // 13. ÃƒÂ°Ã…Â¸Ã…Â¡Ã¢â€šÂ¬ ACCELERATION FACTOR (NEW - HIGH PRIORITY)
            // ========================================
            double accelerationScore = 0.0;
            
            // ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª = ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¸ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± breakout Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
            if(waves.AB_to_BC_Acceleration > 0.001) {
                // Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒÅ¡Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
                double accelRatio = MathMin(waves.AB_to_BC_Acceleration / 0.01, 1.0);
                accelerationScore = -20.0 * accelRatio;  // Max -20 bonus
            }
            // ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ = ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â­ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¸ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± breakout ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
            else if(waves.AB_to_BC_Acceleration < -0.001) {
                double accelRatio = MathMin(MathAbs(waves.AB_to_BC_Acceleration) / 0.01, 1.0);
                accelerationScore = 20.0 * accelRatio;  // Max +20 penalty
            }
            
            // ========================================
            // 14. ÃƒÂ°Ã…Â¸Ã¢â‚¬â„¢Ã‚Âª RELATIVE STRENGTH FACTOR (NEW - HIGH PRIORITY)
            // ========================================
            double strengthScore = 0.0;
            
            // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Å¡ BC
            if(waves.BC_RelativeStrength > 2.0) {
                // BC ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¸ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± D Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
                strengthScore = -25.0;
            } else if(waves.BC_RelativeStrength < 1.0) {
                // BC ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¸ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± D ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
                strengthScore = 25.0;
            }
            
            // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª BC ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ AB (momentum change)
            double strengthRatio = waves.BC_RelativeStrength / MathMax(waves.AB_RelativeStrength, 0.1);
            if(strengthRatio > 1.2) {
                // BC Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ momentum ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´
                strengthScore -= 15.0;
            } else if(strengthRatio < 0.8) {
                // BC ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚ÂÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ momentum ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´
                strengthScore += 15.0;
            }
            
            // ========================================
            // 15. ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ CONFIDENCE SCORE SYSTEM (NEW - CRITICAL)
            // ========================================
            double confidence = 100.0;
            
            // ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â´ confidence ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¶ÃƒËœÃ‚Â¹Ãƒâ„¢Ã‚Â
            if(waves.speedConsistency < 0.5) confidence -= 30.0;  // ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
            if(timeSymmetry < 0.6) confidence -= 20.0;  // ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
            if(fibDeviation > 0.15) confidence -= 15.0;  // ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Fibonacci
            if(errorPercent > 3.0) confidence -= 25.0;  // ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§
            
            // ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â²ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ confidence ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§
            if(harmonicPattern != "NONE") confidence += 15.0;  // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©
            if(isValidABCD) confidence += 10.0;  // AB=CD Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±
            if(waves.BC_RelativeStrength > 2.0) confidence += 10.0;  // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§
            if(MathAbs(waves.AB_to_BC_Acceleration) < 0.001) confidence += 5.0;  // ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â«ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª
            
            // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ 0-100
            if(confidence < 0) confidence = 0;
            if(confidence > 100) confidence = 100;
            
            // penalty ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ confidence Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â 
            double confidencePenalty = 0.0;
            if(confidence < 50.0) {
                confidencePenalty = 50.0 * (1.0 - confidence / 50.0);  // Max +50 penalty
            }
            
            // ========================================
            // 16. ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Âµ HARMONIC MEAN CONSISTENCY (SCIENTIFIC - PYTHAGOREAN)
            // ========================================
            // ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™: Harmonic Mean ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
            // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹: ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¶Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â«ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂºÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â±ÃƒËœÃ‚Â«ÃƒËœÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â 
            double harmonicMeanScore = 0.0;
            
            if(waves.XA_Speed > 0 && waves.AB_Speed > 0 && waves.BC_Speed > 0) {
                // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Harmonic Mean
                double recipSum = (1.0/waves.XA_Speed) + (1.0/waves.AB_Speed) + (1.0/waves.BC_Speed);
                double harmonicMean = 3.0 / recipSum;
                
                // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Arithmetic Mean
                double arithmeticMean = (waves.XA_Speed + waves.AB_Speed + waves.BC_Speed) / 3.0;
                
                // Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª Harmonic ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Arithmetic
                // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© 1.0 ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯ ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â«ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯
                double meanRatio = harmonicMean / arithmeticMean;
                
                // ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ (meanRatio > 0.9)
                if(meanRatio > 0.9) {
                    harmonicMeanScore = -15.0 * ((meanRatio - 0.9) / 0.1);  // Max -15 bonus
                }
                // penalty ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â«ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  (meanRatio < 0.7)
                else if(meanRatio < 0.7) {
                    harmonicMeanScore = 15.0 * ((0.7 - meanRatio) / 0.3);  // Max +15 penalty
                }
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   Harmonic Mean: ", DoubleToString(harmonicMean, 2), " pips/min");
                Print("   Arithmetic Mean: ", DoubleToString(arithmeticMean, 2), " pips/min");
                Print("   Ratio: ", DoubleToString(meanRatio, 3), 
                      " (", meanRatio > 0.9 ? "ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Consistent" : (meanRatio < 0.7 ? "ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â Inconsistent" : "ÃƒÂ¢Ã…Â¾Ã‚Â¡ÃƒÂ¯Ã‚Â¸Ã‚Â Moderate"), ")");
                #endif
            }
            
            // ========================================
            // 17. ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â PHI RATIO BONUS (SCIENTIFIC - GOLDEN RATIO)
            // ========================================
            // ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™: Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ (ÃƒÂÃ¢â‚¬Â  = 0.618) ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
            // ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾: Self-Fulfilling Prophecy (Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â¢Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯)
            // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹: ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â³ (300 Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯)ÃƒËœÃ…â€™ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¢Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™
            double phiRatioScore = 0.0;
            
            double phi = 1.618033988749;
            double phiInverse = 0.618033988749;
            
            // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ AB/XA Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ 0.618
            double phiDeviation_AB_XA = MathAbs(waves.AB_XA_Ratio - phiInverse);
            if(phiDeviation_AB_XA < 0.05) {  // Ãƒâ€šÃ‚Â±5% tolerance
                // Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒÅ¡Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±ÃƒËœÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
                phiRatioScore -= 20.0 * (1.0 - phiDeviation_AB_XA / 0.05);  // Max -20 bonus
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ÃƒÂ¢Ã…â€œÃ‚Â¨ Golden Ratio detected in AB/XA: ", DoubleToString(waves.AB_XA_Ratio, 3));
                #endif
            }
            
            // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ BC/AB Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ 0.618
            double phiDeviation_BC_AB = MathAbs(waves.BC_AB_Ratio - phiInverse);
            if(phiDeviation_BC_AB < 0.05) {  // Ãƒâ€šÃ‚Â±5% tolerance
                phiRatioScore -= 15.0 * (1.0 - phiDeviation_BC_AB / 0.05);  // Max -15 bonus
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ÃƒÂ¢Ã…â€œÃ‚Â¨ Golden Ratio detected in BC/AB: ", DoubleToString(waves.BC_AB_Ratio, 3));
                #endif
            }
            
            // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ AB/XA Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ 1.618 (ÃƒÂÃ¢â‚¬Â )
            double phiDeviation_AB_XA_ext = MathAbs(waves.AB_XA_Ratio - phi);
            if(phiDeviation_AB_XA_ext < 0.08) {  // Ãƒâ€šÃ‚Â±8% tolerance (ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ extension)
                phiRatioScore -= 12.0 * (1.0 - phiDeviation_AB_XA_ext / 0.08);  // Max -12 bonus
                
                #ifdef ENABLE_DEBUG_LOGS
                Print("   ÃƒÂ¢Ã…â€œÃ‚Â¨ Phi Extension detected in AB/XA: ", DoubleToString(waves.AB_XA_Ratio, 3));
                #endif
            }
            
            // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾ (ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± = ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±)
            // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ 2 Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯
            double totalScore = (errorScore + speedScore + timeScore + fibScore + freqScore + consolidationPenalty) 
                              * stepPriority * (1.0 + stepPriorityScore) 
                              + impulsiveBonus + harmonicBonus + medianLineBonus + abcdBonus
                              + accelerationScore + strengthScore + confidencePenalty
                              + harmonicMeanScore + phiRatioScore;  // ÃƒÂ¢Ã¢â‚¬Â Ã‚Â 2 Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯
            
            // ÃƒËœÃ‚Â°ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¡
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
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 6: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾
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
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ 7: Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬
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
        // Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â·ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² threshold Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯
        // ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  10 Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±
        int keepCount = MathMin(10, resultCount);
        ArrayResize(results, keepCount);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â No results with error < ", maxErrorPercent, "%, keeping best ", keepCount, " results");
        #endif
        
        return keepCount;
    }
}

//+------------------------------------------------------------------+
//| Auto-Select Best Frequency for Current AB=CD Pattern            |
//| ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  AB=CD Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™                |
//+------------------------------------------------------------------+
bool AutoSelectBestFrequency(string patternName)
{
    // Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â· AÃƒËœÃ…â€™ BÃƒËœÃ…â€™ C ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â 
    string lineAB = patternName + "_Line_AB";
    string lineBC = patternName + "_Line_BC";
    
    if(ObjectFind(0, lineAB) < 0 || ObjectFind(0, lineBC) < 0) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ Pattern not found: ", patternName);
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
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ Invalid pattern data");
        return false;
    }
    
    // For auto-select, we don't have X point stored in pattern
    // Estimate X based on typical wave pattern structure
    // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡ X ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â°ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  X ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â®ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ AB
    int barA = iBarShift(NULL, 0, tA);
    int barB = iBarShift(NULL, 0, tB);
    int AB_Bars = barA - barB; // A Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² B ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
    if(AB_Bars < 1) AB_Bars = 1;
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â  X: Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² A (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™)
    int barX = barA + AB_Bars; // X Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² A
    datetime tX = iTime(NULL, 0, barX);
    
    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â 
    if(tX <= 0 || tX >= tA) {
        // fallback: ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ AB
        tX = tA - (tB - tA);
        if(tX <= 0) tX = tA - 3600; // ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Å¾ 1 ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾
    }
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª X ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â®ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™
    // ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ AB=CD Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™: X Ãƒâ„¢Ã‹â€  A ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â·ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒËœÃ…â€™ B Ãƒâ„¢Ã‹â€  D ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â·ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â±
    bool isABBullish = (pB > pA);
    double AB_Distance = MathAbs(pB - pA);
    double pX;
    
    if(isABBullish) {
        // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± AB ÃƒËœÃ‚ÂµÃƒËœÃ‚Â¹Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª (AÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢B ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§)
        // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â³ XA ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (XÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢A ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â )
        // Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ X ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² A ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
        pX = pA + (AB_Distance * 0.618); // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶: XA ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ 61.8% ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB (Fibonacci)
    } else {
        // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± AB Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª (AÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢B ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â )
        // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â³ XA ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ ÃƒËœÃ‚ÂµÃƒËœÃ‚Â¹Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (XÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢A ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§)
        // Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ X Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² A ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
        pX = pA - (AB_Distance * 0.618); // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â¶: XA ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ 61.8% ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB
    }
    
    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª: X Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‚ÂÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    if(pX <= 0) {
        if(isABBullish) {
            pX = pA + (AB_Distance * 0.5); // fallback: 50% ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² AB
        } else {
            pX = pA - (AB_Distance * 0.5);
        }
    }
    
    // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â´ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª A ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â  (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Âª)
    if(pX <= 0) pX = pA;
    
    // ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¬Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ 4 Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡)
    // ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± X ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ A ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ 3 Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
    FrequencySearchResult results[];
    ArrayResize(results, 0); // Initialize array
    
    bool hasValidX = (MathAbs(pX - pA) > MathAbs(pB - pA) * 0.1); // X ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ„¢Ã¢â‚¬Å¾ 10% AB ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² A Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    
    int resultCount;
    if(hasValidX) {
        // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ 4 Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡
        resultCount = FindOptimalFrequencyForABCD(tX, pX, tA, pA, tB, pB, tC, pC, results, 5.0);
    } else {
        // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â  X (Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â· ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ AB Ãƒâ„¢Ã‹â€  BC)
        // ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚ÂªÃƒËœÃ…â€™ X = A Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã‹â€  pattern quality ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡
        resultCount = FindOptimalFrequencyForABCD(tA, pA, tA, pA, tB, pB, tC, pC, results, 5.0);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â X point estimation not reliable, using simplified analysis");
        #endif
    }
    
    if(resultCount == 0) {
        Print("ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â No suitable frequency found (error > 5%)");
        return false;
    }
    
    // Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Å¾
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â FREQUENCY SEARCH RESULTS");
    Print("Pattern: ", patternName);
    Print("AB Distance: ", DoubleToString(MathAbs(pB - pA), Digits), " (", 
          DoubleToString(MathAbs(pB - pA) / ((Digits == 3 || Digits == 5) ? Point * 10 : Point), 1), " pips)");
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ BEST MATCH:");
    Print("   Frequency: ", DoubleToString(results[0].frequency, 3), "% (Index: ", results[0].frequencyIndex, ")");
    Print("   Target: Step ", results[0].targetStep, " | Error: ", DoubleToString(results[0].errorPercent, 3), "% (", DoubleToString(results[0].errorPips, 1), " pips)");
    Print("   Speed: ", DoubleToString(results[0].gannAngle, 2), "x | Consistency: ", DoubleToString(results[0].angleWeight * 100, 1), "%");
    Print("   Time Symmetry: ", DoubleToString(results[0].timeSymmetry * 100, 1), "% | Total Score: ", DoubleToString(results[0].totalScore, 2));
    Print("========================================");
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  TOP 10 ALTERNATIVES:");
    
    int displayCount = MathMin(10, resultCount);
    for(int i = 0; i < displayCount; i++)
    {
        Print(StringFormat("%d. %.3f%% ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Step %d | Err: %.2f%% (%.1f pips) | Speed: %.2fx | Score: %.2f",
              i + 1,
              results[i].frequency,
              results[i].targetStep,
              results[i].errorPercent,
              results[i].errorPips,
              results[i].gannAngle,
              results[i].totalScore));
    }
    Print("========================================");
    
    // ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³
    double bestFreq = results[0].frequency;
    int bestIndex = results[0].frequencyIndex;
    
    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³
    g_th3FreqOverride = bestFreq;
    g_th3FreqIndex = bestIndex;
    
    // ÃƒËœÃ‚Â°ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± GlobalVariable
    // PERFORMANCE: Use cached ChartID string
    string chartIdStr = GetCachedChartIdStr();
    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
    GlobalVariableSet(freqGvarName, bestFreq);
    GlobalVariableSet(indexGvarName, bestIndex);
    GlobalVariableTemp(freqGvarName);
    GlobalVariableTemp(indexGvarName);
    
    Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Frequency applied successfully");
    
    // Update frequency label
    UpdateTH3FrequencyLabel(bestFreq);
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate AB=CD Point D (with 9-level validation)               |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡ D ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ 9 ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·ÃƒËœÃ‚Â­Ãƒâ€ºÃ…â€™                              |
//| Rule: AB distance = CD distance (equal price movement)          |
//+------------------------------------------------------------------+
bool CalculateABCDPointD(datetime tA, double pA, datetime tB, double pB,
                         datetime tC, double pC, datetime &tD, double &pD)
{
    // 1. Validate input times
    if(tA <= 0 || tB <= 0 || tC <= 0) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ AB=CD Error: Invalid time inputs");
        return false;
    }
    
    // 2. Validate input prices
    if(pA <= 0 || pB <= 0 || pC <= 0) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ AB=CD Error: Invalid price inputs");
        return false;
    }
    
    // 3. Time ordering: A < B < C
    if(!(tA < tB && tB < tC)) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ AB=CD Error: Time ordering violated (A < B < C required)");
        return false;
    }
    
    // 4. Minimum distance check (prevent micro-patterns)
    double AB_Distance = MathAbs(pB - pA);
    double BC_Distance = MathAbs(pC - pB);
    double minDistance = Point * ABCD_MIN_DISTANCE_POINTS;
    
    if(AB_Distance < minDistance) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ AB=CD Error: AB distance too small (min: ", minDistance, ")");
        return false;
    }
    
    // RELAXED: BC can be any size (user might be adjusting)
    // BC Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡)
    
    // 5. Pattern direction validation (RELAXED - allow any C position)
    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¬Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Âª Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  (ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ - C Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡)
    bool isBullish = (pB > pA); // A to B is upward
    
    // REMOVED: Retracement check - C can be anywhere
    // ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯: ÃƒÅ¡Ã¢â‚¬Â ÃƒÅ¡Ã‚Â© retracement - C Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    // This allows user to freely adjust C without pattern deletion
    // ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ C ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â 
    
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
    // ÃƒÅ¡Ã¢â‚¬Â ÃƒÅ¡Ã‚Â© collinearity ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯ - ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯
    // User should be free to place points anywhere
    // ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â· ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡
    
    // 9. Final validation: D price must be reasonable (RELAXED)
    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¬Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™: Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª D ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
    if(pD <= 0) {
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ AB=CD Error: Calculated D price is zero or negative");
        return false;
    }
    
    // RELAXED: Allow any D price (even if far from current price)
    // ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡: D Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚ÂªÃƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ (ÃƒËœÃ‚Â­ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡)
    
    return true;
}

//+------------------------------------------------------------------+
//| Draw AB=CD Pattern with TH3-style Steps                         |
//| ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  AB=CD ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ TH3                                    |
//| User provides A, B, C ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ System calculates D                      |
//| Targets (Step1/3/5/7) start from C (not D)                       |
//+------------------------------------------------------------------+
void DrawABCDPattern(string mainObjName, datetime tA, double pA, datetime tB, double pB,
                     datetime tC, double pC)
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¨ DrawABCDPattern called | Name: ", mainObjName);
    Print("   A: ", TimeToString(tA), " @ ", DoubleToString(pA, Digits));
    Print("   B: ", TimeToString(tB), " @ ", DoubleToString(pB, Digits));
    Print("   C: ", TimeToString(tC), " @ ", DoubleToString(pC, Digits));
    #endif
    
    datetime tD;
    double pD;
    
    if(!CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("ÃƒÂ¢Ã‚ÂÃ…â€™ CalculateABCDPointD failed - cleaning up temp objects");
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
    Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Point D calculated: ", TimeToString(tD), " @ ", DoubleToString(pD, Digits));
    #endif
    
    double AB_Distance = MathAbs(pB - pA);
    bool isBullish = (pB > pA);
    double frequency = GetCurrentTH3Frequency();
    double baseUnit = AB_Distance * (frequency / 100.0);
    
    double pipSize = (Digits == 3 || Digits == 5) ? Point * 10 : Point;
    
    // DYNAMIC OFFSET: Calculate based on candle size for better positioning
    // Offset ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©: Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±
    double labelOffset;
    
    if(inpABCDLabelOffsetPercent > 0) {
        // User-defined offset percentage
        double avgCandleSize = 0;
        int lookback = 20; // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  20 ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±
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
    // Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â· Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ AÃƒËœÃ…â€™ BÃƒËœÃ…â€™ C (ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã‹â€ ÃƒÅ¡Ã¢â‚¬Â ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯)
    for(int i = 0; i < 3; i++) {
        string pointName = mainObjName + "_Point_" + pointNames[i];
        
        // SMART POSITIONING: Place point above/below candle based on price level
        // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯: Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§/Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·ÃƒËœÃ‚Â­ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª
        int barIndex = iBarShift(NULL, 0, pointTimes[i]);
        double pointPrice = pointPrices[i];
        
        if(barIndex >= 0) {
            double high = iHigh(NULL, 0, barIndex);
            double low = iLow(NULL, 0, barIndex);
            double mid = (high + low) / 2.0;
            
            // Determine if point is at top or bottom of candle
            // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â´ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âµ ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â³ÃƒËœÃ‚Âª
            bool isAtTop = (pointPrice >= mid);
            
            // Offset point slightly outside candle for visibility
            // ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â®ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¬ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â´ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â 
            double offset = (high - low) * 0.15; // 15% of candle range
            if(offset < Point * 10) offset = Point * 10; // Minimum offset
            
            if(isAtTop) {
                // Point at top - place above high
                pointPrice = high + offset;
            } else {
                // Point at bottom - place below low
                pointPrice = low - offset;
            }
        }
        
        // OPTIMIZED: Use small circle (ARROWCODE 159) - visible and draggable
        // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã‹â€ ÃƒÅ¡Ã¢â‚¬Â ÃƒÅ¡Ã‚Â© - Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â´ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‹â€  ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â 
        if(ObjectFind(0, pointName) < 0) {
            if(!ObjectCreate(0, pointName, OBJ_ARROW, 0, pointTimes[i], pointPrices[i])) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to create point ", pointNames[i], " | Error: ", GetLastError());
                #endif
            } else {
                #ifdef ENABLE_DEBUG_LOGS
                Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Created point ", pointNames[i], " at ", TimeToString(pointTimes[i]), " @ ", DoubleToString(pointPrices[i], Digits));
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
            ObjectSetString(0, pointName, OBJPROP_TOOLTIP, "ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã‚Â Point " + pointNames[i] + " | Drag to adjust");
        } else {
            // Update existing point position
            ObjectMove(0, pointName, 0, pointTimes[i], pointPrices[i]);
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ Updated existing point ", pointNames[i]);
            #endif
        }
        
        // Smart label positioning relative to candle High/Low
        // Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ÃƒËœÃ‚ÂªÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ High/Low ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾
        if(inpABCDShowLabels) {
            string labelName = mainObjName + "_Label_" + pointNames[i];
            double labelPrice = pointPrices[i];
            ENUM_ANCHOR_POINT anchor = ANCHOR_CENTER;
            
            // Get candle High/Low for this point
            int labelBarIndex = iBarShift(NULL, 0, pointTimes[i]);
            double candleHigh = (labelBarIndex >= 0) ? iHigh(NULL, 0, labelBarIndex) : pointPrices[i];
            double candleLow = (labelBarIndex >= 0) ? iLow(NULL, 0, labelBarIndex) : pointPrices[i];
            
            // Position label relative to candle High/Low (not point price)
            // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨ÃƒËœÃ‚Âª ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ High/Low ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Å¾ (Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Å¡Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡)
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
                    Print("ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to create label ", pointNames[i], " | Error: ", GetLastError());
                    #endif
                } else {
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Created label ", pointNames[i]);
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
                Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ Updated existing label ", pointNames[i]);
                #endif
            }
        }
    }
    
    // Draw line AB (solid)
    string lineAB = mainObjName + "_Line_AB";
    if(ObjectFind(0, lineAB) < 0) {
        if(!ObjectCreate(0, lineAB, OBJ_TREND, 0, tA, pA, tB, pB)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to create Line AB | Error: ", GetLastError());
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Created Line AB");
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
            Print("ÃƒÂ¢Ã‚ÂÃ…â€™ Failed to create Line BC | Error: ", GetLastError());
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Created Line BC");
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
                string labelText = StringFormat("%s (%.1f) Ãƒâ€šÃ‚Â±%.1f", targetNames[i], targetPips[i], zonePips/2.0);
                ObjectSetString(0, lineName, OBJPROP_LEVELTEXT, 0, labelText);
            }
        } else {
            // CRITICAL FIX: Update position AND label text when frequency changes
            ObjectMove(0, lineName, 0, startTime, centerPrice);
            ObjectMove(0, lineName, 1, endTime, centerPrice);
            
            // Update label text with new pip values
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN) {
                double zonePips = (zoneHalfWidth * 2.0) / pipSize;
                string labelText = StringFormat("%s (%.1f) Ãƒâ€šÃ‚Â±%.1f", targetNames[i], targetPips[i], zonePips/2.0);
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
    // Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Å¾ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§ÃƒËœÃ‚Âª (Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ - Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¸Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¦)
    // VISIBILITY: Only shown for active pattern
    // Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â´ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â : Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â· ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
    double pips_AB = AB_Distance / pipSize;
    double pips_BC = MathAbs(pC - pB) / pipSize;
    
    string infoText = StringFormat("AB=CD | AB:%.1f | BC:%.1f | Freq:%.1f%%", 
                                   pips_AB, pips_BC, frequency);
    
    string infoLabel = mainObjName + "_Info";
    
    // Determine visibility based on active pattern
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¹Ãƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â´ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾
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
    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¨ DrawABCDPattern completed | Pattern: ", mainObjName);
    Print("   Objects: Points(3:A,B,C) + Labels(3) + Lines(2) + Targets(4) + Zones(8) + Info(1)");
    Print("   Note: Point D not shown - target levels indicate D zone");
    #endif
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update All TH3 Objects (when frequency changes)                 |
//| ÃƒËœÃ‚Â¢Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡ TH3 (Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚ÂªÃƒËœÃ‚ÂºÃƒâ€ºÃ…â€™Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â± Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡)                  |
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
        Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ Updated ", updatedCount, " AB=CD patterns with frequency: ", 
              DoubleToString(GetCurrentTH3Frequency(), 3), "%");
    }
    #endif
    
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Handle AB=CD Mouse Events (3-point click workflow)              |
//| Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ AB=CD (ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© 3 Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â·Ãƒâ„¢Ã¢â‚¬Â¡)                   |
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
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬â€œÃƒÂ¯Ã‚Â¸Ã‚Â AB=CD creation cancelled");
            return;
        }
        
        // ALTERNATIVE CLICK DETECTION: Use mouse button state change
        // This is more reliable than CHARTEVENT_CLICK in MT4
        static bool s_lastLeftButtonState = false;
        
        if(g_abcdDrawing && leftButtonDown && !s_lastLeftButtonState) {
            // Left button just pressed (rising edge detection)
            s_lastLeftButtonState = true;
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬â€œÃ‚Â±ÃƒÂ¯Ã‚Â¸Ã‚Â Left button pressed via MOUSE_MOVE | lparam=", lparam, " dparam=", dparam);
            #endif
            
            // Debounce check
            uint currentTime = GetTickCount();
            if(currentTime - g_abcdLastClickTime < ABCD_DEBOUNCE_MS) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("ÃƒÂ¢Ã‚ÂÃ‚Â±ÃƒÂ¯Ã‚Â¸Ã‚Â Click debounced (too fast)");
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
                Print("ÃƒÂ¢Ã‚ÂÃ…â€™ ChartXYToTimePrice failed | mx=", mx, " my=", my);
                #endif
                return;
            }
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Click detected | time=", TimeToString(clickTime), " price=", DoubleToString(clickPrice, Digits), " | pointCount=", g_abcdPointCount);
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
                Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point X placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
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
                Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point A placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
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
                Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point B placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
            }
            else if(g_abcdPointCount == 3) {
                g_abcdTimeC = clickTime;
                g_abcdPriceC = clickPrice;
                
                Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point C placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
                
                // ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â AUTO-SEARCH: Find optimal frequency for this pattern (with 3-wave analysis)
                // ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â¬Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±: Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  (ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ 3 Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬)
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
                    // ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¹Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³
                    g_th3FreqOverride = searchResults[0].frequency;
                    g_th3FreqIndex = searchResults[0].frequencyIndex;
                    
                    // ÃƒËœÃ‚Â°ÃƒËœÃ‚Â®Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â± GlobalVariable
                    // PERFORMANCE: Use cached ChartID string
                    string chartIdStr = GetCachedChartIdStr();
                    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
                    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
                    GlobalVariableSet(freqGvarName, g_th3FreqOverride);
                    GlobalVariableSet(indexGvarName, g_th3FreqIndex);
                    GlobalVariableTemp(freqGvarName);
                    GlobalVariableTemp(indexGvarName);
                    
                    Print("========================================");
                    Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ AUTO-SELECTED FREQUENCY");
                    Print("========================================");
                    Print("Best: ", DoubleToString(searchResults[0].frequency, 3), "% ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Step ", searchResults[0].targetStep);
                    Print("Error: ", DoubleToString(searchResults[0].errorPercent, 3), "% (", DoubleToString(searchResults[0].errorPips, 1), " pips)");
                    Print("Speed: ", DoubleToString(searchResults[0].gannAngle, 2), "x | Consistency: ", DoubleToString(searchResults[0].angleWeight * 100, 1), "%");
                    Print("Time Sym: ", DoubleToString(searchResults[0].timeSymmetry * 100, 1), "% | Score: ", DoubleToString(searchResults[0].totalScore, 2));
                    Print("========================================");
                    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  TOP 5 ALTERNATIVES:");
                    for(int i = 0; i < MathMin(5, resultCount); i++) {
                        Print(StringFormat("%d. %.3f%% ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢ Step %d | Err: %.2f%% | Speed: %.2fx | Score: %.2f",
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
                Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ AB=CD pattern created: ", patternName);
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
        Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ‚Â CHARTEVENT_CLICK received | lparam=", lparam, " dparam=", dparam, " sparam=", sparam, " | g_abcdPointCount=", g_abcdPointCount);
        #endif
        
        uint currentTime = GetTickCount();
        if(currentTime - g_abcdLastClickTime < ABCD_DEBOUNCE_MS) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ¢Ã‚ÂÃ‚Â±ÃƒÂ¯Ã‚Â¸Ã‚Â Click debounced (too fast)");
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
            Print("ÃƒÂ¢Ã‚ÂÃ…â€™ ChartXYToTimePrice failed | mx=", mx, " my=", my);
            #endif
            return;
        }
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ ChartXYToTimePrice success | time=", TimeToString(clickTime), " price=", DoubleToString(clickPrice, Digits));
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
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point X placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
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
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point A placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
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
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point B placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
        }
        else if(g_abcdPointCount == 3) {
            g_abcdTimeC = clickTime;
            g_abcdPriceC = clickPrice;
            
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Å“ Point C placed at ", TimeToString(clickTime), " price ", DoubleToString(clickPrice, Digits));
            
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
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ AB=CD pattern created: ", patternName);
        }
    }
    
    // Handle drag events for A, B, C points with smart magnet effect
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â· AÃƒËœÃ…â€™ BÃƒËœÃ…â€™ C ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â§Ãƒâ„¢Ã‚ÂÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯
    if(id == CHARTEVENT_OBJECT_DRAG) {
        if(StringFind(sparam, "ABCD_Pattern_") == 0 && StringFind(sparam, "_Point_") > 0) {
            // Extract pattern name and point
            int pointPos = StringFind(sparam, "_Point_");
            string baseName = StringSubstr(sparam, 0, pointPos);
            string pointName = StringSubstr(sparam, pointPos + 7);
            
            // Only A, B, C are draggable
            if(pointName != "A" && pointName != "B" && pointName != "C") return;
            
            // CRITICAL: Set this pattern as active when user drags it
            // Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â± drag Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â±Ãƒâ„¢Ã‹â€  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â 
            SetActiveABCDPattern(baseName);
            
            // SMART MAGNET: Snap to nearest candle high/low with threshold
            // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÅ¡Ã‚Â¯Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Âª Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â¯: ÃƒÅ¡Ã¢â‚¬Â ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ high/low Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â²ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒÅ¡Ã‚Â© ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡
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
                double pipSize = (Digits == 5 || Digits == 3) ? Point * 10 : Point;
                double distToHigh = MathAbs(newPrice - high) / pipSize;
                double distToLow = MathAbs(newPrice - low) / pipSize;
                double distToOpen = MathAbs(newPrice - open) / pipSize;
                double distToClose = MathAbs(newPrice - close) / pipSize;
                
                // THRESHOLD: Only snap if within 5 pips (industry standard)
                // ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡: Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â· ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚ÂªÃƒËœÃ‚Â± ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² 5 Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã‚Â¾ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡ snap Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â´Ãƒâ„¢Ã¢â‚¬Â¡
                double snapThreshold = 5.0;
                
                // Find closest level within threshold
                double minDist = MathMin(MathMin(distToHigh, distToLow), MathMin(distToOpen, distToClose));
                
                if(minDist <= snapThreshold) {
                    // PRIORITY: High/Low > Open/Close (more significant levels)
                    // ÃƒËœÃ‚Â§Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ„¢Ã‹â€ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª: High/Low > Open/Close (ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â­ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±)
                    if(minDist == distToHigh) {
                        newPrice = high;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â² Snapped to HIGH (", DoubleToString(minDist, 1), " pips)");
                        #endif
                    } else if(minDist == distToLow) {
                        newPrice = low;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â² Snapped to LOW (", DoubleToString(minDist, 1), " pips)");
                        #endif
                    } else if(minDist == distToClose) {
                        newPrice = close;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â² Snapped to CLOSE (", DoubleToString(minDist, 1), " pips)");
                        #endif
                    } else if(minDist == distToOpen) {
                        newPrice = open;
                        #ifdef ENABLE_DEBUG_LOGS
                        Print("ÃƒÂ°Ã…Â¸Ã‚Â§Ã‚Â² Snapped to OPEN (", DoubleToString(minDist, 1), " pips)");
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
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Âª ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  (Ãƒâ„¢Ã‚ÂÃƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â· Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚ÂªÃƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ…â€™ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â· Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â )
    if(id == CHARTEVENT_OBJECT_DELETE) {
        // Check if any ABCD pattern object is deleted
        // ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â±ÃƒËœÃ‚Â±ÃƒËœÃ‚Â³Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â¢Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â± ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¡ Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â· ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  ABCD ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡
        if(StringFind(sparam, "ABCD_Pattern_") == 0) {
            
            // Extract base name from deleted object
            string baseName = sparam;
            
            // CRITICAL FIX: Safe string parsing - find pattern base name
            // Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â 
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
            Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬â€Ã¢â‚¬ËœÃƒÂ¯Ã‚Â¸Ã‚Â Deleting AB=CD pattern: ", baseName);
            Print("   Triggered by object: ", sparam);
            #endif
            
            // ========================================
            // COMPREHENSIVE CLEANUP: Delete ALL related objects
            // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¬ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â¹: ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â Ãƒâ„¢Ã¢â‚¬Â¡Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡ Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¡
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
            // ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â ÃƒËœÃ‚ÂªÃƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â¦ ÃƒËœÃ‚Â³ÃƒËœÃ‚Â·Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â­ Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â¯Ãƒâ„¢Ã‚Â Ãƒâ„¢Ã‹â€  ÃƒËœÃ‚Â²Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§
            for(int i = 1; i <= 7; i++) {
                ObjectDelete(0, baseName + "_Target_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_ZoneUpper_" + IntegerToString(i));
                ObjectDelete(0, baseName + "_ZoneLower_" + IntegerToString(i));
            }
            
            // 5. Delete any temporary objects
            // ÃƒËœÃ‚Â­ÃƒËœÃ‚Â°Ãƒâ„¢Ã‚Â ÃƒËœÃ‚Â§ÃƒËœÃ‚Â´Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¡ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ Ãƒâ„¢Ã¢â‚¬Å¡ÃƒËœÃ‚Âª
            ObjectDelete(0, baseName + "_Temp_X");
            ObjectDelete(0, baseName + "_Temp_A");
            ObjectDelete(0, baseName + "_Temp_B");
            ObjectDelete(0, baseName + "_Temp_C");
            ObjectDelete(0, baseName + "_Temp_Line_XA");
            ObjectDelete(0, baseName + "_Temp_Line_AB");
            ObjectDelete(0, baseName + "_Temp_Line_BC");
            
            // 6. Clear active pattern if this was the active one
            // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â¯ÃƒËœÃ‚Â± ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒËœÃ‚Â¨Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¯
            if(g_activeABCDPattern == baseName) {
                SetActiveABCDPattern("");
            }
            
            // ========================================
            
            #ifdef ENABLE_DEBUG_LOGS
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬Â¦ Pattern cleanup complete: ", baseName);
            #endif
            
            ChartRedraw();
        }
    }
}

//| Toggle TH3 Tool (V key)                                         |
//| Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾/ÃƒËœÃ‚ÂºÃƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â¹ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â²ÃƒËœÃ‚Â§ÃƒËœÃ‚Â± TH3 (ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ V)                            |
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
            Print("ÃƒÂ°Ã…Â¸Ã…Â½Ã‚Â¯ AB=CD Mode: Click 4 points (X, A, B, C). Right-click to cancel.");
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
            Print("ÃƒÂ¢Ã…â€œÃ¢â‚¬â€œÃƒÂ¯Ã‚Â¸Ã‚Â AB=CD creation cancelled");
        }
    }
}

//+------------------------------------------------------------------+
//| Cycle TH3 Frequency (Keys 3 and 4)                              |
//| ÃƒÅ¡Ã¢â‚¬Â ÃƒËœÃ‚Â±ÃƒËœÃ‚Â®ÃƒËœÃ‚Â´ Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ TH3 (ÃƒÅ¡Ã‚Â©Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ 3 Ãƒâ„¢Ã‹â€  4)                                 |
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
    
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ TH3 Frequency: ", DoubleToString(g_th3FreqOverride, 3), "%");
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
    
    Print("ÃƒÂ°Ã…Â¸Ã¢â‚¬ÂÃ¢â‚¬Å¾ TH3 Frequency: ", DoubleToString(g_th3FreqOverride, 3), "%");
}


//+------------------------------------------------------------------+
//| Find Optimal Frequency with Learning Data                        |
//| Ãƒâ„¢Ã‚Â¾Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â±ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â  ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚ÂªÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â  Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚Â³ ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â§ ÃƒËœÃ‚Â¯ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ÃƒÂ¢Ã¢â€šÂ¬Ã…â€™Ãƒâ„¢Ã¢â‚¬Â¡ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯ÃƒÅ¡Ã‚Â¯Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â±Ãƒâ€ºÃ…â€™                      |
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
    // Ãƒâ„¢Ã‚Â¾ÃƒËœÃ‚Â§ÃƒÅ¡Ã‚Â©ÃƒËœÃ‚Â³ÃƒËœÃ‚Â§ÃƒËœÃ‚Â²Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚Â¢ÃƒËœÃ‚Â±ÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Â¡ Ãƒâ„¢Ã¢â‚¬Â ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§Ãƒâ€ºÃ…â€™ÃƒËœÃ‚Â¬
    ArrayResize(results, 0);
    
    double AB_Distance = MathAbs(pB - pA);
    if(AB_Distance <= 0) return 0;
    
    // ÃƒËœÃ‚ÂªÃƒËœÃ‚Â­Ãƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™Ãƒâ„¢Ã¢â‚¬Å¾ Ãƒâ„¢Ã¢â‚¬Â¦Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â¬
    waves_out = AnalyzeThreeWaves(tX, pX, tA, pA, tB, pB, tC, pC);
    
    // Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ consolidation (ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚ÂªÃƒâ„¢Ã‚ÂÃƒËœÃ‚Â§ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â§ÃƒËœÃ‚Â² waves Ãƒâ„¢Ã¢â‚¬Â¦ÃƒËœÃ‚Â­ÃƒËœÃ‚Â§ÃƒËœÃ‚Â³ÃƒËœÃ‚Â¨Ãƒâ„¢Ã¢â‚¬Â¡ ÃƒËœÃ‚Â´ÃƒËœÃ‚Â¯Ãƒâ„¢Ã¢â‚¬Â¡)
    consolidationFactor_out = CalculateConsolidationFactor(tA, tB, tC, waves_out);
    
    // Ãƒâ„¢Ã‚ÂÃƒËœÃ‚Â±ÃƒËœÃ‚Â§ÃƒËœÃ‚Â®Ãƒâ„¢Ã‹â€ ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Â Ãƒâ€ºÃ…â€™ ÃƒËœÃ‚ÂªÃƒËœÃ‚Â§ÃƒËœÃ‚Â¨ÃƒËœÃ‚Â¹ ÃƒËœÃ‚Â§ÃƒËœÃ‚ÂµÃƒâ„¢Ã¢â‚¬Å¾Ãƒâ€ºÃ…â€™
    int resultCount = FindOptimalFrequencyForABCD(tX, pX, tA, pA, tB, pB, tC, pC, results, maxErrorPercent);
    
    return resultCount;
}

