#ifndef CONSTANTS_AND_ENUMS_MQH
#define CONSTANTS_AND_ENUMS_MQH

#define MAX_LINES 10

// Object naming constants (for cleanup)
#define TH3_PATTERN_PREFIX      "ABCD_Pattern_"
#define TH3_TEMP_PREFIX         "ABCD_Temp_"
#define TH3_TEMP_LINE_PREFIX    "ABCD_Temp_Line_"
#define CACHE_TIMEOUT 60

// Performance & Safety Constants
#define MAX_SAFE_LEVELS 2000          // Maximum safe number of levels per side
#define MAX_SAFE_OBJECTS 5000         // Warning threshold for total objects
#define CRITICAL_OBJECT_LIMIT 50000   // Critical threshold (MT4 limit ~64K)
#define CPU_WARNING_MS 50             // Warning if OnCalculate takes >50ms
#define CPU_CRITICAL_MS 200           // Critical if OnCalculate takes >200ms

// Array Safety Constants (GOLD FIX v3)
#define MAX_PREFIX_COUNT 50           // Maximum number of object prefixes (with safety margin)
#define OBJECT_COUNT_INCREASE_THRESHOLD 100  // Trigger cleanup if objects increased by 100
#define REDRAW_THROTTLE_SECONDS 10    // Minimum 10 seconds between redraws
#define CLEANUP_INTERVAL_SECONDS 300  // 5 minutes between periodic cleanups
#define CHART_CHANGE_THROTTLE_MS 100  // Throttle CHARTEVENT_CHART_CHANGE bursts (ms)
#define DOUBLE_CLICK_THRESHOLD_MS 300 // Double-click detection window (ms)

// Division Safety Constants (GOLD FIX v3)
#define MIN_SAFE_DIVISIONS 0.001      // Minimum divisions to prevent precision loss
#define MAX_SAFE_FACTOR 10000.0       // Maximum factor value to prevent overflow

// Visibility Constants for OBJPROP_TIMEFRAMES (visual align MT5)
// Used by VisibilityManager for hide/show without deletion
#ifndef OBJ_ALL_PERIODS
#define OBJ_ALL_PERIODS 0xFFFFFFFF  // Show on all timeframes
#endif
#ifndef OBJ_NO_PERIODS
#define OBJ_NO_PERIODS 0            // Hide on all timeframes
#endif

// ØªØ¹Ø±ÛŒÙ Ø«Ø§Ø¨Øªâ€ŒÙ‡Ø§ÛŒ Ù…ÙˆØ±Ø¯ Ù†ÛŒØ§Ø² Ø¨Ø±Ø§ÛŒ ØªÙ†Ø¸ÛŒÙ… Ø®ØµÙˆØµÛŒØ§Øª Ø¢Ø¨Ø¬Ú©Øªâ€ŒÙ‡Ø§
#ifndef OBJPROP_BOLD
#define OBJPROP_BOLD 5
#endif

const string FRACTAL_TIMEFRAMES[] = {
    "M1", "M4", "M16", "H1+M4", "H4+M16", "H17+M4",
    "D2+H20+M16", "D11+H9+M4", "D45+H12+M16"
};
// FRACTAL_SHORT_NAMES (visual align MT5 — used for compact label rendering)
const string FRACTAL_SHORT_NAMES[] = {
    "M1", "M4", "M16", "H1.4", "H4.16", "H17.4",
    "D2.20.16", "D11.9.4", "D45.12.16"
};
// Adjusted by factor 1.0415625 so H17+M4 (1024min) = 66.66% instead of 64%
// These percentages MUST match MotiveWave Constants.java FRACTAL_PERCENTAGES
const double MODIFIED_FRACTAL_PERCENTAGES[] = {
    0.0208,   // M1: 2.08%
    0.0417,   // M4: 4.17%
    0.0833,   // M16: 8.33%
    0.1666,   // H1+M4: 16.66%
    0.3333,   // H4+M16: 33.33%
    0.6666,   // H17+M4: 66.66% âœ“
    1.3332,   // D2+H20+M16: 133.32%
    2.6664,   // D11+H9+M4: 266.64%
    5.3328    // D45+H12+M16: 533.28%
};
const color FRACTAL_COLORS[] = {
    clrBlack, clrBlack, clrBlack, clrBlue, clrRed,
    clrRed, clrGreen, clrBlack, clrBlack
};
const string STANDARD_TIMEFRAMES[] = {"D1", "W1", "MN1"};
const int STANDARD_MINUTES[] = {1440, 10080, 43200};
const color STANDARD_COLORS[] = {clrBlue, clrBlue, clrBlue};

enum ENUM_TH_START_POINT_TYPE {
    TH_START_POINT_MIDPOINT = 0,      // Midpoint
    TH_START_POINT_HISTORICAL_HIGH = 1, // Historical High
    TH_START_POINT_HISTORICAL_LOW = 2,  // Historical Low
    TH_START_POINT_CUSTOM_PRICE = 3    // Custom Price
};

enum ENUM_LINE_OBJECT_TYPE {
    LINE_OBJECT_HORIZONTAL_LINE = 0,
    LINE_OBJECT_RAY_LINE = 1
};

enum ENUM_LABEL_CORNER_POSITION {
    LABEL_CORNER_LEFT_TOP = 0,
    LABEL_CORNER_LEFT_BOTTOM = 1
};

enum ENUM_LABEL_ARRANGEMENT {
    LABEL_ARRANGEMENT_VERTICAL = 0,
    LABEL_ARRANGEMENT_HORIZONTAL = 1
};

// Step calculation modes (matching MotiveWave implementation exactly)
// E_STEP removed - TP is now a standalone mode (like Java version)
enum ENUM_STEP_CALCULATION_MODE {
    TH_STEP = 0,        // Traditional TH step mode
    SS_LS_STEP = 1,     // Short Step / Long Step alternating mode
    COMBO_STEP = 2,     // Combo Step mode (customizable: Component1 + Component2)
    FACTOR_STEP = 3     // Factor Step mode (divides High-Low range by Factor × 2)
};

// Factor calculation mode (Auto vs Manual)
enum ENUM_FACTOR_MODE {
    FACTOR_MODE_AUTO = 0,    // Auto (based on TH)
    FACTOR_MODE_MANUAL = 1   // Manual (user-defined)
};

//+------------------------------------------------------------------+
//| Factor Auto Basis - What to base the auto calculation on         |
//| Ù…Ø¨Ù†Ø§ÛŒ Ù…Ø­Ø§Ø³Ø¨Ù‡ Ø®ÙˆØ¯Ú©Ø§Ø± Factor                                       |
//|                                                                  |
//| CONTROL: Average of SS and LS (THÃ—1.75) - Balanced [DEFAULT]    |
//| SS: Short Step (THÃ—1.5) - Closer levels, more lines             |
//| LS: Long Step (THÃ—2.0) - Wider levels, fewer lines              |
//| TH: Pure TH (THÃ—1.0) - Standard spacing                         |
//| TRIGGER: Current timeframe TH - Responsive to current TF        |
//| PATTERN: 4x timeframe TH - Medium-term structure                |
//| STRUCTURE: 16x timeframe TH - Long-term structure               |
//| COMBO: Average of 2 components - Custom mix like Combo Mode     |
//+------------------------------------------------------------------+
enum ENUM_FACTOR_AUTO_BASIS {
    FACTOR_BASIS_CONTROL = 0,      // Control: (SS+LS)/2 = THÃ—1.75 [Balanced]
    FACTOR_BASIS_SS = 1,           // Short Step: THÃ—1.5 (More levels)
    FACTOR_BASIS_LS = 2,           // Long Step: THÃ—2.0 (Fewer levels)
    FACTOR_BASIS_TH = 3,           // Pure TH: THÃ—1.0 (Standard)
    FACTOR_BASIS_TRIGGER = 4,      // Trigger: Current TF (Responsive)
    FACTOR_BASIS_PATTERN = 5,      // Pattern: 4x TF (Medium-term)
    FACTOR_BASIS_STRUCTURE = 6,    // Structure: 16x TF (Long-term)
    FACTOR_BASIS_COMBO = 7         // Combo: Average of 2 components (Custom)
};

//+------------------------------------------------------------------+
//| Structure Base Multiplier - Valid range 2-9                      |
//| Ø¶Ø±ÛŒØ¨ Ù¾Ø§ÛŒÙ‡ Ø³Ø§Ø®ØªØ§Ø± - Ù…Ø­Ø¯ÙˆØ¯Ù‡ Ù…Ø¹ØªØ¨Ø± Û² ØªØ§ Û¹                          |
//|                                                                  |
//| Defines the hierarchical structure levels:                      |
//| L1 = base^1, L2 = base^2, L3 = base^3, L4 = base^4, L5 = base^5|
//|                                                                  |
//| Example with base=3: L1=3, L2=9, L3=27, L4=81, L5=243          |
//| Example with base=4: L1=4, L2=16, L3=64, L4=256, L5=1024       |
//|                                                                  |
//| NOTE: Value 1 is INVALID because all levels become identical    |
//| (1^1 = 1^2 = 1^3 = 1^4 = 1^5 = 1)                              |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_BASE_MULTIPLIER {
    BASE_MULTIPLIER_2 = 2,   // Base 2: L1=2, L2=4, L3=8, L4=16, L5=32
    BASE_MULTIPLIER_3 = 3,   // Base 3: L1=3, L2=9, L3=27, L4=81, L5=243 [DEFAULT]
    BASE_MULTIPLIER_4 = 4,   // Base 4: L1=4, L2=16, L3=64, L4=256, L5=1024
    BASE_MULTIPLIER_5 = 5,   // Base 5: L1=5, L2=25, L3=125, L4=625, L5=3125
    BASE_MULTIPLIER_6 = 6,   // Base 6: L1=6, L2=36, L3=216, L4=1296, L5=7776
    BASE_MULTIPLIER_7 = 7,   // Base 7: L1=7, L2=49, L3=343, L4=2401, L5=16807
    BASE_MULTIPLIER_8 = 8,   // Base 8: L1=8, L2=64, L3=512, L4=4096, L5=32768
    BASE_MULTIPLIER_9 = 9    // Base 9: L1=9, L2=81, L3=729, L4=6561, L5=59049
};

// Harmonic Ratio validation constants
#define MIN_HARMONIC_RATIO 1.01   // Ø­Ø¯Ø§Ù‚Ù„ 1% ØªÙØ§ÙˆØª (meaningful alternation)
#define MAX_HARMONIC_RATIO 2.0    // Ø­Ø¯Ø§Ú©Ø«Ø± 2x (maximum variation)
#define DEFAULT_HARMONIC_RATIO 1.333  // Golden-like ratio (4/3)

//+------------------------------------------------------------------+
//| Mean Type Selection (for aggregates and quick test)              |
//| Ø§Ù†ØªØ®Ø§Ø¨ Ù†ÙˆØ¹ Ù…ÛŒØ§Ù†Ú¯ÛŒÙ† (Ø¨Ø±Ø§ÛŒ aggregates Ùˆ ØªØ³Øª Ø³Ø±ÛŒØ¹)                 |
//+------------------------------------------------------------------+
enum ENUM_MEAN_TYPE {
    MEAN_ARITHMETIC = 0,    // Arithmetic Mean: (A + B + ...) / n
    MEAN_GEOMETRIC = 1,     // Geometric Mean: â¿âˆš(A Ã— B Ã— ...)
    MEAN_HARMONIC = 2       // Harmonic Mean: n / (1/A + 1/B + ...)
};

// NOTE: ENUM_QUICK_TEST_MODE removed - not used anywhere
// Quick Test is controlled by ENUM_COMBO_MODE instead

//+------------------------------------------------------------------+
//| Quick Test Presets (Simplified Component Selection)              |
//| Presetâ€ŒÙ‡Ø§ÛŒ ØªØ³Øª Ø³Ø±ÛŒØ¹ (Ø§Ù†ØªØ®Ø§Ø¨ Ø³Ø§Ø¯Ù‡ components)                     |
//|                                                                  |
//| NOTE: CUSTOM removed - use Advanced mode for full control       |
//+------------------------------------------------------------------+
enum ENUM_QUICK_TEST_PRESET {
    QUICK_PRESET_TRIGGER_PATTERN = 0,       // Trigger + Pattern (2 TF)
    QUICK_PRESET_ALL_4TF = 1,               // Sub + Trigger + Pattern + Structure (4 TF)
    QUICK_PRESET_TRIGGER_PATTERN_STRUCTURE = 2,  // Trigger + Pattern + Structure (3 TF)
    QUICK_PRESET_PATTERN_STRUCTURE = 3,     // Pattern + Structure (2 TF)
    QUICK_PRESET_TRIGGER_ONLY = 4           // Trigger only (1 TF)
};

// SS/LS basis type
enum ENUM_SSLS_BASIS_TYPE {
    SSLS_BASIS_STRUCTURE = 0,   // Based on Structure TH
    SSLS_BASIS_PATTERN = 1,     // Based on Pattern TH
    SSLS_BASIS_TRIGGER = 2      // Based on Trigger TH
};

//+------------------------------------------------------------------+
//| Calculation Basis (matching Java CalculationBasis enum)          |
//| Ù…Ø¨Ù†Ø§ÛŒ Ù…Ø­Ø§Ø³Ø¨Ø§Øª (Ù…Ø·Ø§Ø¨Ù‚ Ø¨Ø§ Ø¬Ø§ÙˆØ§)                                    |
//|                                                                  |
//| TH_BASIS - Ù…Ø­Ø§Ø³Ø¨Ø§Øª Ø¨Ø± Ø§Ø³Ø§Ø³ TH (Ø¯Ø±ØµØ¯ Ù‚ÛŒÙ…Øª Ã— âˆšØ¯Ù‚ÛŒÙ‚Ù‡)               |
//| ATR_BASIS - Ù…Ø­Ø§Ø³Ø¨Ø§Øª Ø¨Ø± Ø§Ø³Ø§Ø³ ATR ÙˆØ§Ù‚Ø¹ÛŒ (Weighted ATR)             |
//+------------------------------------------------------------------+
enum ENUM_CALCULATION_BASIS {
    CALC_BASIS_TH = 0,          // TH-Based (Theoretical) - Ù¾ÛŒØ´â€ŒÙØ±Ø¶
    CALC_BASIS_ATR = 1          // ATR-Based (Actual) - ÙˆØ§Ù‚Ø¹ÛŒ
};

// Smart Combo Component Selection (Unified)
// Ø§Ù†ØªØ®Ø§Ø¨ Ù‡ÙˆØ´Ù…Ù†Ø¯ Ø§Ø¬Ø²Ø§ÛŒ ØªØ±Ú©ÛŒØ¨ÛŒ (ÛŒÚ©Ù¾Ø§Ø±Ú†Ù‡)
enum ENUM_COMBO_COMPONENT_ITEM {
    // Sub Components (Fastest - 1/4x)
    COMP_SUB_TH = 0,            // Sub TH
    COMP_SUB_SS = 1,            // Sub SS
    COMP_SUB_LS = 2,            // Sub LS
    
    // Trigger Components (Current - 1x)
    COMP_TRIGGER_TH = 3,        // Trigger TH
    COMP_TRIGGER_SS = 4,        // Trigger SS
    COMP_TRIGGER_LS = 5,        // Trigger LS
    
    // Pattern Components (Medium - 4x)
    COMP_PATTERN_TH = 6,        // Pattern TH
    COMP_PATTERN_SS = 7,        // Pattern SS
    COMP_PATTERN_LS = 8,        // Pattern LS
    
    // Structure Components (Slow - 16x)
    COMP_STRUCTURE_TH = 9,      // Structure TH
    COMP_STRUCTURE_SS = 10,     // Structure SS
    COMP_STRUCTURE_LS = 11,     // Structure LS
    
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // AGGREGATE COMPONENTS (Ù…ÛŒØ§Ù†Ú¯ÛŒÙ†â€ŒÙ‡Ø§ÛŒ ØªØ±Ú©ÛŒØ¨ÛŒ)
    // These calculate the mean of TH, SS, LS for a timeframe
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    COMP_SUB_MEAN = 12,         // Sub Mean: (Sub_TH + Sub_SS + Sub_LS) / 3
    COMP_TRIGGER_MEAN = 13,     // Trigger Mean: (Trigger_TH + Trigger_SS + Trigger_LS) / 3
    COMP_PATTERN_MEAN = 14,     // Pattern Mean: (Pattern_TH + Pattern_SS + Pattern_LS) / 3
    COMP_STRUCTURE_MEAN = 15,   // Structure Mean: (Structure_TH + Structure_SS + Structure_LS) / 3
    
    // Special
    COMP_IGNORE = 16            // Ignore (None)
};

//+------------------------------------------------------------------+
//| Combo Operators for Calculator Mode (Manual)                     |
//| Ø¹Ù…Ù„Ú¯Ø±Ù‡Ø§ÛŒ ØªØ±Ú©ÛŒØ¨ÛŒ Ø¨Ø±Ø§ÛŒ Ø­Ø§Ù„Øª Ù…Ø§Ø´ÛŒÙ† Ø­Ø³Ø§Ø¨ (Ø¯Ø³ØªÛŒ)                      |
//|                                                                  |
//| BINARY OPERATORS (2 operands): OP_PLUS to OP_HARMONIC_MEAN      |
//| N-ARY OPERATORS (all components): OP_GEOMETRIC_MEAN_ALL to end  |
//|                                                                  |
//| USAGE EXAMPLE (N-ARY):                                           |
//| Component 1: Trigger SS                                          |
//| Operator 1: Geometric Mean (All)  â† Collects ALL components     |
//| Component 2: Pattern LS                                          |
//| Operator 2: [Ignored]                                            |
//| Component 3: Structure TH                                        |
//| Operator 3: [Ignored]                                            |
//| Component 4: Ignore                                              |
//| Result: Â³âˆš(Trigger_SS Ã— Pattern_LS Ã— Structure_TH)              |
//+------------------------------------------------------------------+
enum ENUM_COMBO_OPERATOR {
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // BINARY OPERATORS (Ø¹Ù…Ù„Ú¯Ø±Ù‡Ø§ÛŒ Ø¯ÙˆØªØ§ÛŒÛŒ) - Work on 2 values
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    OP_PLUS = 0,                // Plus: A + B
    OP_MINUS = 1,               // Minus: A - B
    OP_MULTIPLY = 2,            // Multiply: A Ã— B
    OP_DIVIDE = 3,              // Divide: A Ã· B
    OP_AVERAGE = 4,             // Arithmetic Mean: (A + B) / 2
    OP_GEOMETRIC_MEAN = 5,      // Geometric Mean: âˆš(A Ã— B)
    OP_HARMONIC_MEAN = 6,       // Harmonic Mean: 2AB / (A + B)
    
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // N-ARY OPERATORS (Ø¹Ù…Ù„Ú¯Ø±Ù‡Ø§ÛŒ Ú†Ù†Ø¯ØªØ§ÛŒÛŒ) - Work on ALL active components
    // When used as Operator 1, collects ALL non-IGNORE components
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    OP_GEOMETRIC_MEAN_ALL = 7,  // Geometric Mean (All): â¿âˆš(C1 Ã— C2 Ã— ... Ã— Cn)
    OP_ARITHMETIC_MEAN_ALL = 8, // Arithmetic Mean (All): (C1 + C2 + ... + Cn) / n
    OP_HARMONIC_MEAN_ALL = 9,   // Harmonic Mean (All): n / (1/C1 + 1/C2 + ... + 1/Cn)
    OP_MIN_ALL = 10,            // Minimum (All): min(C1, C2, ..., Cn)
    OP_MAX_ALL = 11,            // Maximum (All): max(C1, C2, ..., Cn)
    
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // SPECIAL
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    OP_NONE = 12                // None (End Chain)
};

//+------------------------------------------------------------------+
//| Calculator Topology (Architecture of Calculation)                |
//| Ù…Ø¹Ù…Ø§Ø±ÛŒ Ù…Ø­Ø§Ø³Ø¨Ø§Øª Ù…Ø§Ø´ÛŒÙ† Ø­Ø³Ø§Ø¨ (Ø³Ø§Ø®ØªØ§Ø± ÙØ±Ù…ÙˆÙ„)                         |
//+------------------------------------------------------------------+
enum ENUM_CALCULATOR_TOPOLOGY {
    TOPOLOGY_LINEAR = 0,        // Linear: ((A op B) op C) op D [Sequential]
    TOPOLOGY_DUAL_GROUP = 1     // Dual Group: (A op B) MainOp (C op D) [Structural]
};

//+------------------------------------------------------------------+
//| Helper structure to hold common calculation values              |
//| All values are in PRICE units (matching MotiveWave)             |
//+------------------------------------------------------------------+
struct SCommonStepData {
    double thValue;              // TH value in PRICE units
    double structureValue;       // Structure value in PRICE units
    double patternValue;         // Pattern value in PRICE units
    double triggerValue;         // Trigger value in PRICE units
    double shortStep;            // SS = 1.5 * Structure (PRICE units)
    double longStep;             // LS = 2.0 * Structure (PRICE units)
    double pointSize;            // DEPRECATED: No longer used (set to 1.0)
    double midpointPrice;        // Start point price
    int maxLevelsAbove;          // Adaptive max levels above
    int maxLevelsBelow;          // Adaptive max levels below
};

//+------------------------------------------------------------------+
//| Advanced Combo Operations for Factor Auto Basis                  |
//| Ø¹Ù…Ù„ÛŒØ§Øªâ€ŒÙ‡Ø§ÛŒ Ù¾ÛŒØ´Ø±ÙØªÙ‡ Combo Ø¨Ø±Ø§ÛŒ Factor Auto Basis                  |
//+------------------------------------------------------------------+
enum ENUM_COMBO_OPERATION {
    COMBO_OP_AVERAGE = 0,       // Average: (A + B) / 2 [Default]
    COMBO_OP_ADD = 1,           // Add: A + B
    COMBO_OP_SUBTRACT = 2,      // Subtract: A - B (or |A - B|)
    COMBO_OP_MULTIPLY = 3,      // Multiply: A Ã— B
    COMBO_OP_MIN = 4,           // Minimum: min(A, B) or min(A, B, C)
    COMBO_OP_MAX = 5,           // Maximum: max(A, B) or max(A, B, C)
    COMBO_OP_WEIGHTED = 6       // Weighted: AÃ—W1 + BÃ—W2 (W1+W2=1)
};

//+------------------------------------------------------------------+
//| Combo Mode Selection (Preset / Advanced)                         |
//| انتخاب حالت Combo (Preset / پیشرفته)                             |
//|                                                                  |
//| TWO INDEPENDENT MODES - Simplified and user-friendly             |
//|                                                                  |
//| PRESET: Quick select from ready-to-use combinations              |
//|   - 18 predefined combinations                                   |
//|   - Includes Quick Test options                                  |
//|   - Recommended for daily use                                    |
//|   Uses: inpComboPreset                                           |
//|                                                                  |
//| ADVANCED: Full manual control (For power users)                  |
//|   - Select topology (Linear/Dual Group)                          |
//|   - Select 4 components and 3 operators                          |
//|   - Maximum flexibility                                         |
//|   Uses: inpComboTopology, inpComboComp1-4, inpComboOp1-3        |
//+------------------------------------------------------------------+
enum ENUM_COMBO_MODE {
    COMBO_MODE_PRESET = 0,      // Preset Mode (Recommended)
    COMBO_MODE_ADVANCED = 1     // Advanced Mode (Full control)
};

//+------------------------------------------------------------------+
//| Timeframe Types for Advanced Combo                               |
//+------------------------------------------------------------------+
enum ENUM_COMBO_TIMEFRAME_TYPE {
    COMBO_TF_SUB = 0,           // Sub: 1/4 current (faster)
    COMBO_TF_TRIGGER = 1,       // Trigger: Current timeframe
    COMBO_TF_PATTERN = 2,       // Pattern: 4x current
    COMBO_TF_STRUCTURE = 3      // Structure: 16x current
};

//+------------------------------------------------------------------+
//| Step Size Type (TH, SS, LS)                                      |
//+------------------------------------------------------------------+
enum ENUM_COMBO_STEP_TYPE {
    COMBO_STEP_TH = 0,          // TH: Base step (1.0×)
    COMBO_STEP_SS = 1,          // SS: Short step (1.5×)
    COMBO_STEP_LS = 2           // LS: Long step (2.0×)
};

//+------------------------------------------------------------------+
//| Combo Calculation Configuration Struct                           |
//| ساختار تنظیمات محاسبات ترکیبی                                    |
//+------------------------------------------------------------------+
struct SComboConfig {
    ENUM_COMBO_TIMEFRAME_TYPE tf1;
    ENUM_COMBO_STEP_TYPE      step1;
    ENUM_COMBO_TIMEFRAME_TYPE tf2;
    ENUM_COMBO_STEP_TYPE      step2;
    ENUM_COMBO_TIMEFRAME_TYPE tf3;
    ENUM_COMBO_STEP_TYPE      step3;
    ENUM_COMBO_OPERATION      operation;
    double                    weight1;
    double                    weight2;
    double                    weight3;
    int                       activeComponents;
    bool                      isTriple;
};

//+------------------------------------------------------------------+
//| Preset Combinations (Common Use Cases) - OPTIMIZED FOR UX        |
//|                                                                  |
//| DESIGN PRINCIPLE: 80/20 Rule - 18 presets cover 98% of needs    |
//|                                                                  |
//| IMPORTANT: COMBO_PRESET_LEGACY_ADD is the default for backward  |
//| compatibility with old Combo Step Mode (Component1 + Component2)|
//|                                                                  |
//| SIMPLIFIED UX: Quick Test presets (15-19) are exposed in the   |
//| same list as regular presets, eliminating the Quick Test sub-   |
//| mode dropdown. All Quick Test presets use TH step + Geometric   |
//| mean (the most popular default from the old Quick Test mode).   |
//+------------------------------------------------------------------+
enum ENUM_COMBO_PRESET {
    // ═══════════════════════════════════════════════════════════════
    // LEGACY (kept for backward compatibility)
    // ═══════════════════════════════════════════════════════════════
    COMBO_PRESET_LEGACY_ADD = 0,            // Legacy: Trigger SS + Pattern SS (ADD)

    // ═══════════════════════════════════════════════════════════════
    // BALANCED FAMILY
    // ═══════════════════════════════════════════════════════════════
    COMBO_PRESET_BALANCED_MEDIUM = 1,       // Balanced Medium: (Pattern + Trigger) / 2 [Most Popular]
    COMBO_PRESET_BALANCED_LONG = 2,         // Balanced Long: (Structure + Pattern) / 2
    COMBO_PRESET_BALANCED_TRIPLE = 3,       // Triple Balanced: (Trigger + Pattern + Structure) / 3
    COMBO_PRESET_BALANCED_MIN = 4,          // Balanced Min: min(Pattern, Trigger)

    // ═══════════════════════════════════════════════════════════════
    // CONSERVATIVE FAMILY
    // ═══════════════════════════════════════════════════════════════
    COMBO_PRESET_CONSERVATIVE = 5,          // Conservative: max(Structure, Pattern)
    COMBO_PRESET_ULTRA_CONSERVATIVE = 6,    // Ultra Conservative: Structure TH
    COMBO_PRESET_TRIPLE_CONSERVATIVE = 7,   // Triple Conservative: max(Trigger, Pattern, Structure)

    // ═══════════════════════════════════════════════════════════════
    // AGGRESSIVE FAMILY
    // ═══════════════════════════════════════════════════════════════
    COMBO_PRESET_AGGRESSIVE = 8,            // Aggressive: min(Pattern, Trigger)
    COMBO_PRESET_ULTRA_AGGRESSIVE = 9,      // Ultra Aggressive: min(Trigger, Sub)
    COMBO_PRESET_TRIPLE_AGGRESSIVE = 10,    // Triple Aggressive: min(Trigger, Pattern, Structure)

    // ═══════════════════════════════════════════════════════════════
    // SPECIAL
    // ═══════════════════════════════════════════════════════════════
    COMBO_PRESET_TREND_FILTER = 11,         // Trend Filter: Structure - Sub
    COMBO_PRESET_VOLATILITY_ADAPTIVE = 12,  // Volatility: (Structure + Sub) / 2

    // ═══════════════════════════════════════════════════════════════
    // ADVANCED REDIRECTS (full manual control)
    // ═══════════════════════════════════════════════════════════════
    COMBO_PRESET_MANUAL_DUAL = 13,          // Advanced Dual: User-defined (2 components) -> Advanced Mode
    COMBO_PRESET_MANUAL_TRIPLE = 14,        // Advanced Triple: User-defined (3 components) -> Advanced Mode

    // ═══════════════════════════════════════════════════════════════
    // QUICK TEST (merged from old COMBO_MODE_QUICK_TEST)
    // All use COMBO_STEP_TH and Geometric Mean for consistency.
    // ═══════════════════════════════════════════════════════════════
    COMBO_PRESET_QT_TRIGGER_PATTERN = 15,           // QT: Trigger + Pattern, Geo Mean
    COMBO_PRESET_QT_ALL_4TF = 16,                    // QT: Sub + Trigger + Pattern + Structure, Geo Mean
    COMBO_PRESET_QT_TRIGGER_PATTERN_STRUCTURE = 17,  // QT: Trigger + Pattern + Structure, Geo Mean
    COMBO_PRESET_QT_PATTERN_STRUCTURE = 18,          // QT: Pattern + Structure, Geo Mean
    COMBO_PRESET_QT_TRIGGER_ONLY = 19                // QT: Trigger only
};

// TH3 Label Position
// Ù…ÙˆÙ‚Ø¹ÛŒØª Ù†Ù…Ø§ÛŒØ´ label Ù‡Ø§ÛŒ TH3
enum ENUM_TH3_LABEL_POSITION {
    TH3_LABEL_START = 0,        // Start (Beginning of line)
    TH3_LABEL_MIDDLE = 1,       // Middle (Center of visible range)
    TH3_LABEL_END = 2,          // End (Right side - Default)
    TH3_LABEL_HIDDEN = 3        // Hidden (No labels)
};

// Unified Zone Display Style (Used by ALL modes)
// Ù†Ø­ÙˆÙ‡ Ù†Ù…Ø§ÛŒØ´ Zone Ù‡Ø§ (Ø¨Ø±Ø§ÛŒ ØªÙ…Ø§Ù… Ù…ÙˆØ¯Ù‡Ø§)
enum ENUM_ZONE_STYLE {
    ZONE_STYLE_LINES = 0,         // Lines Only (Two boundary lines)
    ZONE_STYLE_BOX_FILLED = 1,    // Filled Box (Rectangle with fill)
    ZONE_STYLE_BOX_EMPTY = 2,     // Empty Box (Rectangle outline only)
    ZONE_STYLE_HIDDEN = 3         // Hidden (No zones)
};

// Legacy aliases for backward compatibility
// Ù†Ø§Ù…â€ŒÙ‡Ø§ÛŒ Ù‚Ø¯ÛŒÙ…ÛŒ Ø¨Ø±Ø§ÛŒ Ø³Ø§Ø²Ú¯Ø§Ø±ÛŒ Ø¨Ø§ Ú©Ø¯ Ù‚Ø¨Ù„ÛŒ
#define ENUM_TH3_ZONE_STYLE ENUM_ZONE_STYLE
#define ENUM_FACTOR_ZONE_STYLE ENUM_ZONE_STYLE
#define TH3_ZONE_LINES ZONE_STYLE_LINES
#define TH3_ZONE_BOX_FILLED ZONE_STYLE_BOX_FILLED
#define TH3_ZONE_BOX_EMPTY ZONE_STYLE_BOX_EMPTY
#define TH3_ZONE_HIDDEN ZONE_STYLE_HIDDEN
#define FACTOR_ZONE_LINES ZONE_STYLE_LINES
#define FACTOR_ZONE_BOX_FILLED ZONE_STYLE_BOX_FILLED
#define FACTOR_ZONE_BOX_EMPTY ZONE_STYLE_BOX_EMPTY
#define FACTOR_ZONE_HIDDEN ZONE_STYLE_HIDDEN

// TH3 Drawing Mode
// Ø­Ø§Ù„Øª Ø±Ø³Ù… TH3 (Steps ÛŒØ§ AB=CD)
enum ENUM_TH3_DRAWING_MODE {
    TH3_MODE_STEPS = 0,         // Steps Mode (2-point drag)
    TH3_MODE_ABCD = 1           // AB=CD Mode (3-point click: A, B, C â†’ calculates D)
};

// NOTE: TH3_TEST_FREQUENCIES[] removed â€” replaced by Binary Subdivision Frequency System
// in ProjectConstants.mqh (runtime calculation via GetFrequencyByIndex())

//+------------------------------------------------------------------+
//| ENUM: Adaptive Scaling Mode                                      |
//| Ø­Ø§Ù„Øª Ù…Ù‚ÛŒØ§Ø³â€ŒØ¯Ù‡ÛŒ ØªØ·Ø¨ÛŒÙ‚ÛŒ                                             |
//+------------------------------------------------------------------+
enum ENUM_ADAPTIVE_MODE {
    ADAPTIVE_FIXED   = 0,    // Fixed (No Adaptation)
    ADAPTIVE_ATR     = 1,    // ATR Adaptive (Full)
    ADAPTIVE_BLENDED = 2     // Blended (Mix ATR + TH)
};

// Adaptive Scaling Constants
#define MIN_SCALING_FACTOR      0.1    // Minimum allowed scaling factor
#define MAX_SCALING_FACTOR      10.0   // Maximum allowed scaling factor
#define DEFAULT_SMOOTHING_PERIOD 20    // Default EMA smoothing period
#define DEFAULT_BLEND_RATIO     0.5    // Default blend ratio (50/50)

//+------------------------------------------------------------------+
//| TH3 Object Name Suffixes (Magic Numbers Elimination)            |
//| Ù¾Ø³ÙˆÙ†Ø¯Ù‡Ø§ÛŒ Ù†Ø§Ù… Ø§Ø´ÛŒØ§Ø¡ TH3 (Ø­Ø°Ù Magic Numbers)                       |
//+------------------------------------------------------------------+
#define TH3_SUFFIX_LINE_AB "_Line_AB"
#define TH3_SUFFIX_LINE_BC "_Line_BC"
#define TH3_SUFFIX_TARGET  "_Target_"
#define TH3_SUFFIX_POINT   "_Point_"
#define TH3_SUFFIX_LABEL   "_Label_"
#define TH3_SUFFIX_INFO    "_Info"
#define TH3_SUFFIX_ZONE    "_Zone"

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// ZONE ERROR CODES (used by ZoneValidator / ZoneCalculator)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
#define ZONE_ERROR_NONE             0
#define ZONE_ERROR_INVALID_PRICES   1
#define ZONE_ERROR_EQUAL_PRICES     2
#define ZONE_ERROR_INVALID_HEIGHT   3
#define ZONE_ERROR_INVERTED_BOUNDS  4
#define ZONE_ERROR_OUT_OF_RANGE     5

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// PIPELINE STRUCTS (used by Zone system)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

struct SLevelRawData {
    double price;
    int    logicalStep;
    int    stepTypeIndex;
};

struct SStyleConfig {
    double zoneHeightPercent;
    int    zoneTransparency;
    int    baseMultiplier;
    bool   showStructure;
    bool   showTrigger;
    bool   showZones;
    bool   globalShowLines;
    color  structColorL1;
    color  triggerColor;
    int    structStyleL1;
    int    structWidthL1;
    int    triggerStyle;
    int    triggerWidth;
};

struct SZoneValidationResult {
    bool   isValid;
    int    errorCode;
    string errorMessage;
};

struct SLevelClassification {
    bool   isStructure;
    bool   isActive;
    color  levelColor;
    int    style;
    int    width;
};

struct SZoneGeometry {
    bool   isValid;
    double topPrice;
    double bottomPrice;
    double midPoint;
    int    linkedLevelIndex;
};

struct SLineRenderInfo {
    bool           isVisible;
    color          clr;
    ENUM_LINE_STYLE style;
    int            width;
    string         name;
    double         price;
    string         tooltip;
    bool           selectable;
};

struct SZoneRenderInfo {
    bool   isVisible;
    string name;
    color  clr;
    int    transparency;
    bool   filled;
    double topPrice;
    double bottomPrice;
};

struct FrequencyResult {
    int       bestIndex;
    double    bestFrequency;
    double    totalScore;
    double    multiStepScore;
    double    patternScore;
    double    timeScore;
    double    sqrtScore;
    double    harmonicScore;
    double    historyScore;
    double    confidence;
    double    step1Price;
    double    step3Price;
    double    step5Price;
    double    step7Price;
    int       matchedSteps;
    string    matchLabel;
    string    patternType;
    int       matchWaveIndex;
    double    errorPips;
    bool      isValid;
    void Reset() {
        bestIndex = -1;
        bestFrequency = 0;
        totalScore = 0;
        multiStepScore = 0;
        patternScore = 0;
        timeScore = 0;
        sqrtScore = 0;
        harmonicScore = 0;
        historyScore = 0;
        confidence = 0;
        step1Price = 0;
        step3Price = 0;
        step5Price = 0;
        step7Price = 0;
        matchedSteps = 0;
        matchLabel = "";
        patternType = "";
        matchWaveIndex = -1;
        errorPips = 0;
        isValid = false;
    }
};

#define FREQ_HISTORY_SIZE 20

struct FrequencyHistoryEntry {
    FrequencyResult result;
    double    abDistance;
    double    ratioBC_AB;
    int       freqIndex;
    datetime  timestamp;
    bool      isUsed;
    void Reset() {
        result.Reset();
        abDistance = 0;
        ratioBC_AB = 0;
        freqIndex = -1;
        timestamp = 0;
        isUsed = false;
    }
};

#endif // CONSTANTS_AND_ENUMS_MQH
