  //+------------------------------------------------------------------+
//|                                      ProjectConstants.mqh        |
//|                     Centralized Constants - PLATINUM VERSION     |
//|                     Centralized Constants - Platinum Version     |
//|                                                                  |
//| BENEFITS:                                                        |
//| - Single source of truth for all constants                      |
//| - Easy to maintain and update                                   |
//| - No magic numbers in code                                      |
//| - Self-documenting with clear names                             |
//+------------------------------------------------------------------+
#ifndef PROJECT_CONSTANTS_MQH
#define PROJECT_CONSTANTS_MQH
#property strict

//+------------------------------------------------------------------+
//| TH3 Binary Subdivision Frequency System                          |
//| Theory: Every real number in [0,100] has exact representation    |
//| as n/2^k  100%. At depth=6: freq = index  (100/64) = i1.5625 |
//| This replaces the old GM-interpolated array (22 incorrect values)|
//+------------------------------------------------------------------+
const int    BINARY_SUBDIVISION_DEPTH = 6;              // 2^6 = 64 subdivisions per 100%
const double BINARY_SUBDIVISION_STEP  = 1.5625;         // 100.0 / 64 = 1.5625% per index
#define MIN_TH3_FREQ_INDEX        1              // 1.5625%
#define MAX_TH3_FREQ_INDEX        256            // 400.0% (extended range)
#define DEFAULT_TH3_FREQ_INDEX    18             // 28.125%

double GetFrequencyByIndex(int index) {
    return index * BINARY_SUBDIVISION_STEP;
}

int FindNearestFreqIndex(double freqPercent) {
    if(freqPercent <= 0) return MIN_TH3_FREQ_INDEX;
    int idx = (int)MathRound(freqPercent / BINARY_SUBDIVISION_STEP);
    if(idx < MIN_TH3_FREQ_INDEX) idx = MIN_TH3_FREQ_INDEX;
    if(idx > MAX_TH3_FREQ_INDEX) idx = MAX_TH3_FREQ_INDEX;
    return idx;
}

int GetBinaryDepthLevel(int index) {
    if(index <= 0) return 0;
    int depth = 0;
    while((index & 1) == 0) { depth++; index >>= 1; }
    return depth;
}

bool IsCleanBinaryLevel(int index, int minDepth) {
    return GetBinaryDepthLevel(index) >= minDepth;
}

// ABCD Pattern Constants
#define ABCD_MIN_DISTANCE_POINTS 10
#define ABCD_DEBOUNCE_MS 300

// Frequency History
#ifndef FREQ_HISTORY_SIZE
#define FREQ_HISTORY_SIZE 8
#endif
#define MIN_STEP1_PIPS 2.0

// ==============================================================================
// PERCENTAGE CONSTANTS
//  
// ==============================================================================
const int MIN_TRANSPARENCY_PERCENT = 0;
const int MAX_TRANSPARENCY_PERCENT = 100;
const int DEFAULT_TRANSPARENCY_PERCENT = 50;

const double MIN_ZONE_HEIGHT_PERCENT = 0.01;    // 1%
const double MAX_ZONE_HEIGHT_PERCENT = 1.0;     // 100%
const double DEFAULT_ZONE_HEIGHT_PERCENT = 0.125; // 12.5%

// ==============================================================================
// MULTIPLIERS & FACTORS
//   
// ==============================================================================
const int ZONE_EXTENSION_MULTIPLIER = 10000;    // For calculating endTime
const int ALPHA_SCALE_FACTOR = 255;             // For alpha channel calculation
const int PERCENTAGE_TO_DECIMAL = 100;          // Convert percent to decimal

// ==============================================================================
// PERFORMANCE CONSTANTS
//  
// ==============================================================================
const int CACHE_LOG_INTERVAL = 100;             // Cache hits log interval
const int ZONE_EXTENSION_PERIODS = 100;         // Number of periods to extend zone
const int MAX_ZONES_PER_CHART = 500;            // Maximum zones on chart
const int OBJECT_CACHE_SIZE = 1000;             // Object cache size

// ==============================================================================
// LIMITS & THRESHOLDS
//   
// ==============================================================================
const int MAX_MOVEMENT_CANDLES = 10000;         // Max movement candles
const int MAX_REST_CANDLES = 1000;              // Max rest candles
const int MAX_LEARNING_DATA_SIZE = 10000;       // Max learning data size

const double MAX_PRICE_DEVIATION = 2.0;         // Max price deviation (200%)
const double MAX_ZONE_HEIGHT_PERCENT_LIMIT = 1.0; // Zone height limit

// ==============================================================================
// FREQUENCY CALCULATION
//  
// ==============================================================================
const int FREQUENCY_BASE = 100;                 // For Step N: frequency = 100/N

// Step-specific frequencies
const double FREQUENCY_STEP_3 = 33.333;         // 100/3
const double FREQUENCY_STEP_5 = 20.0;           // 100/5
const double FREQUENCY_STEP_7 = 14.286;         // 100/7

// ==============================================================================
// CONSOLIDATION THRESHOLDS
//  Consolidation
// ==============================================================================
const double CONSOLIDATION_VERY_LOW = 0.6;      // 60% - Very low energy
const double CONSOLIDATION_LOW = 1.0;           // 100% - Sufficient energy
const double CONSOLIDATION_MEDIUM = 1.5;        // 150% - High energy

// ==============================================================================
// PATTERN DETECTION THRESHOLDS
//   
// ==============================================================================
const double GANN_ANGLE_STRONG_IMPULSIVE = 75.0;    // Gann angle for strong pattern
const double GANN_ANGLE_MEDIUM_IMPULSIVE = 50.0;   // Gann angle for medium pattern
const double CONSOLIDATION_IMPULSIVE_MAX = 0.1;    // Max consolidation for impulsive (10%)
const double TIME_SYMMETRY_GOOD = 0.8;             // Good time symmetry (80%)

// ==============================================================================
// LOGGING INTERVALS
//  
// ==============================================================================
const int TEST_ARRAY_SIZE = 100;                // Test array size
const int TEST_OVERFLOW_COUNT = 100;            // Overflow count in test
const int LABEL_OFFSET_MAX_PIPS = 100;          // Max label offset (pips)
const int PATTERN_BARS_PADDING = 100;           // Padding for pattern display

// ==============================================================================
// TIME CONSTANTS
//  
// ==============================================================================
const int SECONDS_PER_MINUTE = 60;
const int SECONDS_PER_HOUR = 3600;
const int SECONDS_PER_DAY = 86400;
const int SECONDS_PER_MONTH = 2592000;          // 30 days

const int MUTEX_STALE_TIMEOUT_SECONDS = 2;      // Mutex stale timeout
const int MUTEX_RETRY_ATTEMPTS = 10;            // Mutex retry attempts
const int MUTEX_RETRY_DELAY_MS = 10;            // Mutex retry delay (ms)

// ==============================================================================
// ARRAY SIZES
//  
// ==============================================================================
const int DEFAULT_ARRAY_SIZE = 10;
const int SMALL_ARRAY_SIZE = 50;
const int MEDIUM_ARRAY_SIZE = 100;
const int LARGE_ARRAY_SIZE = 500;

// ==============================================================================
// VALIDATION CONSTANTS
//  
// ==============================================================================
const double MIN_PRICE_VALUE = 0.00001;         // Min valid price
const double MAX_PRICE_MULTIPLIER = 1000000.0;  // Max price multiplier
const int MIN_BARS_REQUIRED = 1;                // Min required bars
const int MAX_BARS_LOOKBACK = 10000;            // Max lookback bars

// ==============================================================================
// ERROR CODES (Centralized)
//   ()
// ==============================================================================
const int ERROR_CODE_SUCCESS = 0;
const int ERROR_CODE_INVALID_INPUT = -1;
const int ERROR_CODE_MEMORY_LIMIT = -2;
const int ERROR_CODE_FILE_OPERATION = -3;
const int ERROR_CODE_STATE_CONFLICT = -4;
const int ERROR_CODE_OVERFLOW = -5;

// Visual Alignment Constants
const double FONT_CHAR_WIDTH_FACTOR = 0.6;

// ==============================================================================
// HELPER FUNCTIONS
//  
// ==============================================================================

//+------------------------------------------------------------------+
//| Convert Percentage to Decimal                                    |
//|                                                  |
//+------------------------------------------------------------------+
double PercentToDecimal(double percent)
{
    return percent / PERCENTAGE_TO_DECIMAL;
}

//+------------------------------------------------------------------+
//| Convert Decimal to Percentage                                    |
//|                                                  |
//+------------------------------------------------------------------+
double DecimalToPercent(double decimal)
{
    return decimal * PERCENTAGE_TO_DECIMAL;
}

//+------------------------------------------------------------------+
//| Calculate Alpha from Transparency                                |
//|  alpha  transparency                                     |
//+------------------------------------------------------------------+
int TransparencyToAlpha(int transparency)
{
    // Clamp transparency
    if(transparency < MIN_TRANSPARENCY_PERCENT) transparency = MIN_TRANSPARENCY_PERCENT;
    if(transparency > MAX_TRANSPARENCY_PERCENT) transparency = MAX_TRANSPARENCY_PERCENT;
    
    // Calculate alpha
    return (int)((MAX_TRANSPARENCY_PERCENT - transparency) * ALPHA_SCALE_FACTOR / PERCENTAGE_TO_DECIMAL);
}

//+------------------------------------------------------------------+
//| Validate Transparency Range                                      |
//|   transparency                                   |
//+------------------------------------------------------------------+
bool IsValidTransparency(int transparency)
{
    return (transparency >= MIN_TRANSPARENCY_PERCENT && 
            transparency <= MAX_TRANSPARENCY_PERCENT);
}

//+------------------------------------------------------------------+
//| Validate Zone Height Percent                                     |
//|    zone                                      |
//+------------------------------------------------------------------+
bool IsValidZoneHeightPercent(double heightPercent)
{
    return (heightPercent >= MIN_ZONE_HEIGHT_PERCENT && 
            heightPercent <= MAX_ZONE_HEIGHT_PERCENT);
}

//+------------------------------------------------------------------+
//| Get Frequency for Step                                           |
//|                                               |
//+------------------------------------------------------------------+
double GetFrequencyForStep(int step)
{
    if(step <= 0) return 0.0;
    return (double)FREQUENCY_BASE / step;
}

// IsValidPrice is defined in FloatingPointHelper.mqh (with epsilon parameter)

//+------------------------------------------------------------------+
//| Print Constants Summary (Debug)                                  |
//|    ()                                        |
//+------------------------------------------------------------------+
void PrintConstantsSummary()
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("=============================================================");
    Print(" PROJECT CONSTANTS SUMMARY");
    Print("=============================================================");
    Print("Transparency Range: ", MIN_TRANSPARENCY_PERCENT, "-", MAX_TRANSPARENCY_PERCENT, "%");
    Print("Zone Height Range: ", DoubleToString(MIN_ZONE_HEIGHT_PERCENT * 100, 2), "-", 
          DoubleToString(MAX_ZONE_HEIGHT_PERCENT * 100, 2), "%");
    Print("Max Zones Per Chart: ", MAX_ZONES_PER_CHART);
    Print("Max Learning Data: ", MAX_LEARNING_DATA_SIZE);
    Print("Cache Log Interval: ", CACHE_LOG_INTERVAL);
    Print("=============================================================");
    #endif
}

#endif // PROJECT_CONSTANTS_MQH
