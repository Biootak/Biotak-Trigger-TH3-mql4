//+------------------------------------------------------------------+
//|                                      ProjectConstants.mqh        |
//|                     Centralized Constants - PLATINUM VERSION     |
//|                     Ø«Ø§Ø¨Øªâ€ŒÙ‡Ø§ÛŒ Ù…ØªÙ…Ø±Ú©Ø² - Ù†Ø³Ø®Ù‡ Ù¾Ù„Ø§ØªÛŒÙ†ÛŒÙˆÙ…              |
//|                                                                  |
//| BENEFITS:                                                        |
//| - Single source of truth for all constants                      |
//| - Easy to maintain and update                                   |
//| - No magic numbers in code                                      |
//| - Self-documenting with clear names                             |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| TH3 Binary Subdivision Frequency System                          |
//| Theory: Every real number in [0,100] has exact representation    |
//| as n/2^k × 100%. At depth=6: freq = index × (100/64) = i×1.5625 |
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

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// PERCENTAGE CONSTANTS
// Ø«Ø§Ø¨Øªâ€ŒÙ‡Ø§ÛŒ Ø¯Ø±ØµØ¯ÛŒ
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int MIN_TRANSPARENCY_PERCENT = 0;
const int MAX_TRANSPARENCY_PERCENT = 100;
const int DEFAULT_TRANSPARENCY_PERCENT = 50;

const double MIN_ZONE_HEIGHT_PERCENT = 0.01;    // 1%
const double MAX_ZONE_HEIGHT_PERCENT = 1.0;     // 100%
const double DEFAULT_ZONE_HEIGHT_PERCENT = 0.125; // 12.5%

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// MULTIPLIERS & FACTORS
// Ø¶Ø±Ø§ÛŒØ¨ Ùˆ ÙØ§Ú©ØªÙˆØ±Ù‡Ø§
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int ZONE_EXTENSION_MULTIPLIER = 10000;    // Ø¨Ø±Ø§ÛŒ Ù…Ø­Ø§Ø³Ø¨Ù‡ endTime
const int ALPHA_SCALE_FACTOR = 255;             // Ø¨Ø±Ø§ÛŒ Ù…Ø­Ø§Ø³Ø¨Ù‡ alpha channel
const int PERCENTAGE_TO_DECIMAL = 100;          // ØªØ¨Ø¯ÛŒÙ„ Ø¯Ø±ØµØ¯ Ø¨Ù‡ Ø§Ø¹Ø´Ø§Ø±

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// PERFORMANCE CONSTANTS
// Ø«Ø§Ø¨Øªâ€ŒÙ‡Ø§ÛŒ Ø¹Ù…Ù„Ú©Ø±Ø¯ÛŒ
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int CACHE_LOG_INTERVAL = 100;             // ÙØ§ØµÙ„Ù‡ Ù„Ø§Ú¯ cache hits
const int ZONE_EXTENSION_PERIODS = 100;         // ØªØ¹Ø¯Ø§Ø¯ Ø¯ÙˆØ±Ù‡â€ŒÙ‡Ø§ÛŒ Ú¯Ø³ØªØ±Ø´ zone
const int MAX_ZONES_PER_CHART = 500;            // Ø­Ø¯Ø§Ú©Ø«Ø± ØªØ¹Ø¯Ø§Ø¯ zone Ø¯Ø± Ú†Ø§Ø±Øª
const int OBJECT_CACHE_SIZE = 1000;             // Ø§Ù†Ø¯Ø§Ø²Ù‡ Ú©Ø´ Ø§Ø´ÛŒØ§Ø¡

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// LIMITS & THRESHOLDS
// Ù…Ø­Ø¯ÙˆØ¯ÛŒØªâ€ŒÙ‡Ø§ Ùˆ Ø¢Ø³ØªØ§Ù†Ù‡â€ŒÙ‡Ø§
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int MAX_MOVEMENT_CANDLES = 10000;         // Ø­Ø¯Ø§Ú©Ø«Ø± Ú©Ù†Ø¯Ù„â€ŒÙ‡Ø§ÛŒ Ø­Ø±Ú©Øª
const int MAX_REST_CANDLES = 1000;              // Ø­Ø¯Ø§Ú©Ø«Ø± Ú©Ù†Ø¯Ù„â€ŒÙ‡Ø§ÛŒ Ø§Ø³ØªØ±Ø§Ø­Øª
const int MAX_LEARNING_DATA_SIZE = 10000;       // Ø­Ø¯Ø§Ú©Ø«Ø± Ø§Ù†Ø¯Ø§Ø²Ù‡ Ø¯Ø§Ø¯Ù‡â€ŒÙ‡Ø§ÛŒ ÛŒØ§Ø¯Ú¯ÛŒØ±ÛŒ

const double MAX_PRICE_DEVIATION = 2.0;         // Ø­Ø¯Ø§Ú©Ø«Ø± Ø§Ù†Ø­Ø±Ø§Ù Ù‚ÛŒÙ…Øª (200%)
const double MAX_ZONE_HEIGHT_PERCENT_LIMIT = 1.0; // Ù…Ø­Ø¯ÙˆØ¯ÛŒØª Ø§Ø±ØªÙØ§Ø¹ zone

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// FREQUENCY CALCULATION
// Ù…Ø­Ø§Ø³Ø¨Ø§Øª ÙØ±Ú©Ø§Ù†Ø³
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int FREQUENCY_BASE = 100;                 // Ø¨Ø±Ø§ÛŒ Step N: frequency = 100/N

// Step-specific frequencies
const double FREQUENCY_STEP_3 = 33.333;         // 100/3
const double FREQUENCY_STEP_5 = 20.0;           // 100/5
const double FREQUENCY_STEP_7 = 14.286;         // 100/7

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// CONSOLIDATION THRESHOLDS
// Ø¢Ø³ØªØ§Ù†Ù‡â€ŒÙ‡Ø§ÛŒ consolidation
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const double CONSOLIDATION_VERY_LOW = 0.6;      // 60% - Ø§Ù†Ø±Ú˜ÛŒ Ø®ÛŒÙ„ÛŒ Ú©Ù…
const double CONSOLIDATION_LOW = 1.0;           // 100% - Ø§Ù†Ø±Ú˜ÛŒ Ú©Ø§ÙÛŒ
const double CONSOLIDATION_MEDIUM = 1.5;        // 150% - Ø§Ù†Ø±Ú˜ÛŒ Ø²ÛŒØ§Ø¯

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// PATTERN DETECTION THRESHOLDS
// Ø¢Ø³ØªØ§Ù†Ù‡â€ŒÙ‡Ø§ÛŒ ØªØ´Ø®ÛŒØµ Ø§Ù„Ú¯Ùˆ
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const double GANN_ANGLE_STRONG_IMPULSIVE = 75.0;    // Ø²Ø§ÙˆÛŒÙ‡ Gann Ø¨Ø±Ø§ÛŒ Ø§Ù„Ú¯ÙˆÛŒ Ù‚ÙˆÛŒ
const double GANN_ANGLE_MEDIUM_IMPULSIVE = 50.0;   // Ø²Ø§ÙˆÛŒÙ‡ Gann Ø¨Ø±Ø§ÛŒ Ø§Ù„Ú¯ÙˆÛŒ Ù…ØªÙˆØ³Ø·
const double CONSOLIDATION_IMPULSIVE_MAX = 0.1;    // Ø­Ø¯Ø§Ú©Ø«Ø± consolidation Ø¨Ø±Ø§ÛŒ impulsive (10%)
const double TIME_SYMMETRY_GOOD = 0.8;             // ØªÙ‚Ø§Ø±Ù† Ø²Ù…Ø§Ù†ÛŒ Ø®ÙˆØ¨ (80%)

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// LOGGING INTERVALS
// ÙÙˆØ§ØµÙ„ Ù„Ø§Ú¯â€ŒÚ¯Ø°Ø§Ø±ÛŒ
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int TEST_ARRAY_SIZE = 100;                // Ø§Ù†Ø¯Ø§Ø²Ù‡ Ø¢Ø±Ø§ÛŒÙ‡ ØªØ³Øª
const int TEST_OVERFLOW_COUNT = 100;            // ØªØ¹Ø¯Ø§Ø¯ overflow Ø¯Ø± ØªØ³Øª
const int LABEL_OFFSET_MAX_PIPS = 100;          // Ø­Ø¯Ø§Ú©Ø«Ø± offset Ù„ÛŒØ¨Ù„ (pips)
const int PATTERN_BARS_PADDING = 100;           // padding Ø¨Ø±Ø§ÛŒ Ù†Ù…Ø§ÛŒØ´ Ø§Ù„Ú¯Ùˆ

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// TIME CONSTANTS
// Ø«Ø§Ø¨Øªâ€ŒÙ‡Ø§ÛŒ Ø²Ù…Ø§Ù†ÛŒ
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int SECONDS_PER_MINUTE = 60;
const int SECONDS_PER_HOUR = 3600;
const int SECONDS_PER_DAY = 86400;
const int SECONDS_PER_MONTH = 2592000;          // 30 days

const int MUTEX_STALE_TIMEOUT_SECONDS = 2;      // timeout Ø¨Ø±Ø§ÛŒ stale mutex
const int MUTEX_RETRY_ATTEMPTS = 10;            // ØªØ¹Ø¯Ø§Ø¯ ØªÙ„Ø§Ø´ Ø¨Ø±Ø§ÛŒ Ú¯Ø±ÙØªÙ† mutex
const int MUTEX_RETRY_DELAY_MS = 10;            // ØªØ£Ø®ÛŒØ± Ø¨ÛŒÙ† ØªÙ„Ø§Ø´â€ŒÙ‡Ø§ (Ù…ÛŒÙ„ÛŒâ€ŒØ«Ø§Ù†ÛŒÙ‡)

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// ARRAY SIZES
// Ø§Ù†Ø¯Ø§Ø²Ù‡â€ŒÙ‡Ø§ÛŒ Ø¢Ø±Ø§ÛŒÙ‡
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int DEFAULT_ARRAY_SIZE = 10;
const int SMALL_ARRAY_SIZE = 50;
const int MEDIUM_ARRAY_SIZE = 100;
const int LARGE_ARRAY_SIZE = 500;

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// VALIDATION CONSTANTS
// Ø«Ø§Ø¨Øªâ€ŒÙ‡Ø§ÛŒ Ø§Ø¹ØªØ¨Ø§Ø±Ø³Ù†Ø¬ÛŒ
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const double MIN_PRICE_VALUE = 0.00001;         // Ø­Ø¯Ø§Ù‚Ù„ Ù‚ÛŒÙ…Øª Ù…Ø¹ØªØ¨Ø±
const double MAX_PRICE_MULTIPLIER = 1000000.0;  // Ø­Ø¯Ø§Ú©Ø«Ø± Ø¶Ø±ÛŒØ¨ Ù‚ÛŒÙ…Øª
const int MIN_BARS_REQUIRED = 1;                // Ø­Ø¯Ø§Ù‚Ù„ ØªØ¹Ø¯Ø§Ø¯ Ú©Ù†Ø¯Ù„ Ù…ÙˆØ±Ø¯ Ù†ÛŒØ§Ø²
const int MAX_BARS_LOOKBACK = 10000;            // Ø­Ø¯Ø§Ú©Ø«Ø± lookback

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// ERROR CODES (Centralized)
// Ú©Ø¯Ù‡Ø§ÛŒ Ø®Ø·Ø§ (Ù…ØªÙ…Ø±Ú©Ø²)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
const int ERROR_CODE_SUCCESS = 0;
const int ERROR_CODE_INVALID_INPUT = -1;
const int ERROR_CODE_MEMORY_LIMIT = -2;
const int ERROR_CODE_FILE_OPERATION = -3;
const int ERROR_CODE_STATE_CONFLICT = -4;
const int ERROR_CODE_OVERFLOW = -5;

// Visual Alignment Constants
const double FONT_CHAR_WIDTH_FACTOR = 0.6;

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// HELPER FUNCTIONS
// ØªÙˆØ§Ø¨Ø¹ Ú©Ù…Ú©ÛŒ
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

//+------------------------------------------------------------------+
//| Convert Percentage to Decimal                                    |
//| ØªØ¨Ø¯ÛŒÙ„ Ø¯Ø±ØµØ¯ Ø¨Ù‡ Ø§Ø¹Ø´Ø§Ø±                                              |
//+------------------------------------------------------------------+
double PercentToDecimal(double percent)
{
    return percent / PERCENTAGE_TO_DECIMAL;
}

//+------------------------------------------------------------------+
//| Convert Decimal to Percentage                                    |
//| ØªØ¨Ø¯ÛŒÙ„ Ø§Ø¹Ø´Ø§Ø± Ø¨Ù‡ Ø¯Ø±ØµØ¯                                              |
//+------------------------------------------------------------------+
double DecimalToPercent(double decimal)
{
    return decimal * PERCENTAGE_TO_DECIMAL;
}

//+------------------------------------------------------------------+
//| Calculate Alpha from Transparency                                |
//| Ù…Ø­Ø§Ø³Ø¨Ù‡ alpha Ø§Ø² transparency                                     |
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
//| Ø§Ø¹ØªØ¨Ø§Ø±Ø³Ù†Ø¬ÛŒ Ù…Ø­Ø¯ÙˆØ¯Ù‡ transparency                                   |
//+------------------------------------------------------------------+
bool IsValidTransparency(int transparency)
{
    return (transparency >= MIN_TRANSPARENCY_PERCENT && 
            transparency <= MAX_TRANSPARENCY_PERCENT);
}

//+------------------------------------------------------------------+
//| Validate Zone Height Percent                                     |
//| Ø§Ø¹ØªØ¨Ø§Ø±Ø³Ù†Ø¬ÛŒ Ø¯Ø±ØµØ¯ Ø§Ø±ØªÙØ§Ø¹ zone                                      |
//+------------------------------------------------------------------+
bool IsValidZoneHeightPercent(double heightPercent)
{
    return (heightPercent >= MIN_ZONE_HEIGHT_PERCENT && 
            heightPercent <= MAX_ZONE_HEIGHT_PERCENT);
}

//+------------------------------------------------------------------+
//| Get Frequency for Step                                           |
//| Ø¯Ø±ÛŒØ§ÙØª ÙØ±Ú©Ø§Ù†Ø³ Ø¨Ø±Ø§ÛŒ Ú¯Ø§Ù…                                           |
//+------------------------------------------------------------------+
double GetFrequencyForStep(int step)
{
    if(step <= 0) return 0.0;
    return (double)FREQUENCY_BASE / step;
}

// IsValidPrice is defined in FloatingPointHelper.mqh (with epsilon parameter)

//+------------------------------------------------------------------+
//| Print Constants Summary (Debug)                                  |
//| Ú†Ø§Ù¾ Ø®Ù„Ø§ØµÙ‡ Ø«Ø§Ø¨Øªâ€ŒÙ‡Ø§ (Ø¯ÛŒØ¨Ø§Ú¯)                                        |
//+------------------------------------------------------------------+
void PrintConstantsSummary()
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
    Print("ðŸ“‹ PROJECT CONSTANTS SUMMARY");
    Print("â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
    Print("Transparency Range: ", MIN_TRANSPARENCY_PERCENT, "-", MAX_TRANSPARENCY_PERCENT, "%");
    Print("Zone Height Range: ", DoubleToString(MIN_ZONE_HEIGHT_PERCENT * 100, 2), "-", 
          DoubleToString(MAX_ZONE_HEIGHT_PERCENT * 100, 2), "%");
    Print("Max Zones Per Chart: ", MAX_ZONES_PER_CHART);
    Print("Max Learning Data: ", MAX_LEARNING_DATA_SIZE);
    Print("Cache Log Interval: ", CACHE_LOG_INTERVAL);
    Print("â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•");
    #endif
}
