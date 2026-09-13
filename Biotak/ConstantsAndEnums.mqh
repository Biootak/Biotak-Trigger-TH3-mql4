   #ifndef CONSTANTS_AND_ENUMS_MQH
#define CONSTANTS_AND_ENUMS_MQH

#define MAX_LINES 10

// Object naming constants (for cleanup)
#define TH3_PATTERN_PREFIX      "ABCD_Pattern_"
#define TH3_TEMP_PREFIX         "ABCD_Temp_"
#define TH3_TEMP_LINE_PREFIX    "ABCD_Temp_Line_"
#define CACHE_TIMEOUT 60

// ══════════════════════════════════════════════════════════════════════════
// Z LADDER — the ONE owner of every OBJPROP_ZORDER in the project (P-UI-31)
//
// MT4 keeps the SCREEN-SPACE objects (OBJ_LABEL / OBJ_BUTTON / OBJ_BITMAP_LABEL
// / OBJ_EDIT / OBJ_RECTANGLE_LABEL) in one list and paints them in ZORDER
// order; an equal ZORDER falls back to creation order. The same property IS the
// click priority: "when objects are placed one atop another, only one of them
// with the highest priority will receive the CHARTEVENT_CLICK event"
// (docs.mql4.com — Object Properties). Both readings want the same thing here,
// so there is one ladder:
//
//     THE SETTINGS CARD OWNS THE TOP. Nothing the indicator draws may sit over a
//     card, and a click anywhere on a card must reach the card — never the orb,
//     never a hover tip, never a floating box badge. (P-UI-11 is the same rule
//     one level down: a row's caption must not be buried by its own control.)
//
// Three consequences that are NOT obvious:
//   1. The ring menu AND its hover tip sit BELOW the card: the menu is what
//      opens a card, so the card is always the newest surface (the tip is also
//      disarmed while g_UIPanelOpen — see BiotakMenu CircTipOnMove).
//   2. CHART_FOREGROUND is what lifts the panel over the CANDLES
//      (PnlLockForeground); ZORDER alone never raises an object over the bars.
//   3. Never invent a literal at a call site — add a name here, or the audit
//      in tools/zorder-audit.py fails and the ordering stops being provable.
// ══════════════════════════════════════════════════════════════════════════

// ── chart content: zones, level lines, tool dots, boxes — the floor
#define Z_CHART_ZONE     0      // zone bodies/borders, Trigger level lines
#define Z_CHART_LINE     1      // Factor level lines (drawn above their zone)
#define Z_CHART_TOOL    10      // TH3 tool dots
#define Z_BOX_RAY       50      // Base/Knot rays
#define Z_BOX_FILL      55      // box fill layer + drag handle
#define Z_BOX_EDGE      56      // box border edges
#define Z_BOX_INFO      60      // box info text
#define Z_BOX_TEXT      61      // box user text
#define Z_CHART_LABEL  100      // price/level labels, view anchor, countdown tag

// ── Base/Knot floating pills — over the chart, UNDER the settings card
#define Z_BOX_HINT    1400      // the wide floating hint
#define Z_BOX_BADGE   1410      // the small box badge

// ── the mini Base Box strip (item 13) — its own drawing family, still under
//    the full card 12 that it opens
#define Z_STRIP       1440      // bk_strip.bmp, the toolbar body
#define Z_STRIP_ICON  1441      // strip slot glyphs
#define Z_STRIP_OVER  1442      // strip popover chevrons

// ── the ring menu — the card covers it (consequence 1 above)
#define Z_MENU_PANEL    1004    // sub-menu panel chrome
#define Z_MENU_DOT      1005    // sub-menu title dot
#define Z_MENU_ITEM     1010    // ring/Tools item faces
#define Z_MENU_ICON     1011    // item glyphs
#define Z_MENU_BADGE    1012    // item badge bodies + captions
#define Z_MENU_BADGE_TX 1013    // badge ink
#define Z_MENU_PAGER    1014    // grid pager
#define Z_MENU_ORB      1200    // the TRex orb (was 2000 — ABOVE the card)
#define Z_MENU_TIP_BG   1300    // hover tip body
#define Z_MENU_TIP      1302    // hover tip caption/header

// ── the settings cards: 1480..1542 is ONE ladder in paint order
#define Z_PANEL_CARD   1480     // card skin (shadow fringe + body)
#define Z_PANEL_TOPBAR 1481     // .card::before accent bar
#define Z_PANEL_ACT    1484     // active-row wash
#define Z_PANEL_BAND   1486     // section band
#define Z_PANEL_SEP    1490     // row separators
#define Z_PANEL_HAIR   1495     // header hairline
#define Z_PANEL_BASE   1500     // covers + click targets (a button stays under its skin)
#define Z_PANEL_SKIN   1501     // skins over their own click target
#define Z_PANEL_CHIP   1502     // chip faces, dots, counters, value chip
#define Z_PANEL_INK    1503     // glyph ink, chevrons, keycap ink
#define Z_PANEL_GLYPH  1504     // row glyph ink
#define Z_PANEL_GLOSS  1505     // track gloss
#define Z_PANEL_SW     1506     // switch face
#define Z_PANEL_EDIT   1508     // OBJ_EDIT text field
#define Z_PANEL_KNOB   1512     // slider knob
#define Z_PANEL_TEXT   1520     // every caption
#define Z_PANEL_CTL    1540     // buttons/labels ON a control
#define Z_PANEL_MARK   1542     // active marks (tab underline, glass sheens)

// ── popovers, then the palette: the only things allowed over a card
#define Z_PANEL_DD_SH   1558    // dropdown shadow
#define Z_PANEL_DD_BG   1560    // dropdown body
#define Z_PANEL_DD_SEL  1566    // dropdown selected row
#define Z_PANEL_DD_LBL  1568    // dropdown captions
#define Z_PANEL_DD_ICO  1574    // dropdown glyphs
#define Z_PANEL_POP     1600    // palette card
#define Z_PANEL_POP_BG  1601    // palette body + mixer
#define Z_PANEL_POP_CTL 1602    // palette tabs/fields
#define Z_PANEL_POP_FG  1603    // palette knobs/ink
#define Z_PANEL_TOP     1650    // reserved: a full-card overlay, if one is ever added

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

// Live bar-close countdown tag (beside the live candle, at the live price).
// It is its OWN layer since 2026-09-11 (own switch/color/size/gap) and the
// name is deliberately free of "ATR_": the periodic object janitor in
// EventHandlers hides every object whose name contains "ATR_" while the ATR
// labels are off, and this tag must survive that.
#define LIVE_COUNTDOWN_NAME "CloseIn_Tag"
// Older builds drew the same tag as "...ATR_Trade_Current_CloseIn" (first a
// corner row, then candle text) — every path that used to own that name now
// just purges it so old charts lose it for good.
#define LIVE_COUNTDOWN_LEGACY_NAME "ATR_Trade_Current_CloseIn"

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

//                         
#ifndef OBJPROP_BOLD
#define OBJPROP_BOLD 5
#endif

const string FRACTAL_TIMEFRAMES[] = {
    "M1", "M4", "M16", "H1+M4", "H4+M16", "H17+M4",
    "D2+H20+M16", "D11+H9+M4", "D45+H12+M16"
};
// FRACTAL_SHORT_NAMES (visual align MT5     used for compact label rendering)
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
    0.6666,   // H17+M4: 66.66%  
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
    TH_START_POINT_MIDPOINT = 0,      // Midpoint (historical H+L / 2)
    TH_START_POINT_HISTORICAL_HIGH = 1, // Historical High
    TH_START_POINT_HISTORICAL_LOW = 2,  // Historical Low
    TH_START_POINT_CUSTOM_PRICE = 3,    // Custom Price
    TH_START_POINT_PREVIOUS_CLOSE = 4   // Previous Day Close
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
    FACTOR_STEP = 3     // Factor Step mode (divides High-Low range by Factor    2)
};

// Factor calculation mode (Auto vs Manual)
enum ENUM_FACTOR_MODE {
    FACTOR_MODE_AUTO = 0,    // Auto (based on TH)
    FACTOR_MODE_MANUAL = 1   // Manual (user-defined)
};

//+------------------------------------------------------------------+
//| Factor Display Mode - How factor value is shown and operation    |
//|                                                                  |
//| CLASSIC: Traditional mode - number is Factor, Step is calculated |
//|   Input: Factor number  →  Step = Range / (Factor × 2)         |
//|   Display: "F: 50.00 | Step: 12.5 pips"                         |
//|                                                                  |
//| DIRECT: New mode - number IS the Step Size, Factor is internal   |
//|   Input: Step Size  →  Factor = Range / (Step × 2) (internal)   |
//|   Display: "Step: 12.5 pips | F: 50.00"                         |
//+------------------------------------------------------------------+
enum ENUM_FACTOR_DISPLAY_MODE {
    FACTOR_DISPLAY_CLASSIC = 0,  // Classic: Factor number (current behavior)
    FACTOR_DISPLAY_DIRECT = 1    // Direct: Step Size is the primary value
};

//+------------------------------------------------------------------+
//| Factor Auto Basis - What to base the auto calculation on         |
//|           Factor                                       |
//|                                                                  |
//| CONTROL: Average of SS and LS (TH  - Balanced [DEFAULT]    |
//| SS: Short Step (TH  - Closer levels, more lines             |
//| LS: Long Step (TH  - Wider levels, fewer lines              |
//| TH: Pure TH (TH  - Standard spacing                         |
//| TRIGGER: Current timeframe TH - Responsive to current TF        |
//| PATTERN: 4x timeframe TH - Medium-term structure                |
//| STRUCTURE: 16x timeframe TH - Long-term structure               |
//| COMBO: Average of 2 components - Custom mix like Combo Mode     |
//+------------------------------------------------------------------+
enum ENUM_FACTOR_AUTO_BASIS {
    FACTOR_BASIS_CONTROL = 0,      // Control: (SS+LS)/2 = TH  [Balanced]
    FACTOR_BASIS_SS = 1,           // Short Step: TH  (More levels)
    FACTOR_BASIS_LS = 2,           // Long Step: TH  (Fewer levels)
    FACTOR_BASIS_TH = 3,           // Pure TH: TH  (Standard)
    FACTOR_BASIS_TRIGGER = 4,      // Trigger: Current TF (Responsive)
    FACTOR_BASIS_PATTERN = 5,      // Pattern: 4x TF (Medium-term)
    FACTOR_BASIS_STRUCTURE = 6,    // Structure: 16x TF (Long-term)
    FACTOR_BASIS_COMBO = 7         // Combo: Average of 2 components (Custom)
};

//+------------------------------------------------------------------+
//| Basis multiplier table - SINGLE SOURCE OF TRUTH (one table).     |
//| Derived from adapted current-TF TH:                              |
//|   CONTROL = (SS + LS) / 2 = 1.75 * TH  [Balanced, default]      |
//|   SS      = Short Step            = 1.5  * TH                   |
//|   LS      = Long Step             = 2.0  * TH                   |
//|   TH      = Pure TH               = 1.0  * TH                   |
//|   TRIGGER = Current TF TH         = 1.0  * TH                   |
//|                                                                  |
//| Lives here (next to the enum) so BOTH the raw path               |
//| (ExtendedDrawingFunctions.GetStepSizeForFactorBasis) and the      |
//| adapted path (FactorMode.GetFactorModeAutoStepSize) consume the   |
//| same numbers - adapted-vs-raw semantics of each path untouched.   |
//| PATTERN / STRUCTURE / COMBO use their own TF/config (no entry).  |
//+------------------------------------------------------------------+
struct SBasisMultiplierDef {
    ENUM_FACTOR_AUTO_BASIS basis;
    double                 multiplier;
};

const SBasisMultiplierDef FACTOR_BASIS_MULTIPLIERS[] = {
    {FACTOR_BASIS_CONTROL, 1.75},
    {FACTOR_BASIS_SS,      1.5},
    {FACTOR_BASIS_LS,      2.0},
    {FACTOR_BASIS_TH,      1.0},
    {FACTOR_BASIS_TRIGGER, 1.0}
};

//+------------------------------------------------------------------+
//| Get multiplier for a current-TF based basis                      |
//+------------------------------------------------------------------+
double GetFactorBasisMultiplier(const ENUM_FACTOR_AUTO_BASIS basis)
{
    int n = ArraySize(FACTOR_BASIS_MULTIPLIERS);
    for(int i = 0; i < n; i++) {
        if(FACTOR_BASIS_MULTIPLIERS[i].basis == basis)
            return FACTOR_BASIS_MULTIPLIERS[i].multiplier;
    }
    return 1.5; // Fallback = SS (unreachable for the 8 known bases)
}

//+------------------------------------------------------------------+
//| Structure Base Multiplier - Valid range 2-9                      |
//|        -                                            |
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
#define MIN_HARMONIC_RATIO 1.01   //   1%   (meaningful alternation)
#define MAX_HARMONIC_RATIO 2.0    //   2x (maximum variation)
#define DEFAULT_HARMONIC_RATIO 1.333  // Golden-like ratio (4/3)

// NOTE: ENUM_QUICK_TEST_MODE / ENUM_MEAN_TYPE removed - not used
// Quick Test is controlled by ENUM_COMBO_MODE instead

//+------------------------------------------------------------------+
//| Quick Test Presets (Simplified Component Selection)              |
//| Preset        (      components)                     |
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
//|         (                                          |
//|                                                                  |
//| TH_BASIS -        TH (                        |
//| ATR_BASIS -        ATR    (Weighted ATR)             |
//+------------------------------------------------------------------+
enum ENUM_CALCULATION_BASIS {
    CALC_BASIS_TH = 0,          // TH-Based (Theoretical) -   
    CALC_BASIS_ATR = 1          // ATR-Based (Actual) -   
};

// Combo components are now explicit (ENUM_COMBO_TIMEFRAME_TYPE + ENUM_COMBO_STEP_TYPE)
// and the operation enum is ENUM_COMBO_OPERATION - geometric/mean operators removed.

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
//|      Combo   Factor Auto Basis                  |
//+------------------------------------------------------------------+
enum ENUM_COMBO_OPERATION {
    COMBO_OP_AVERAGE = 0,       // Average: (A + B) / 2 [Default]
    COMBO_OP_ADD = 1,           // Add: A + B
    COMBO_OP_SUBTRACT = 2,      // Subtract: A - B (or |A - B|)
    COMBO_OP_MULTIPLY = 3,      // Multiply: A   B
    COMBO_OP_MIN = 4,           // Minimum: min(A, B) or min(A, B, C)
    COMBO_OP_MAX = 5,           // Maximum: max(A, B) or max(A, B, C)
    COMBO_OP_WEIGHTED = 6       // Weighted: A  + B  (W1+W2=1)
};

//+------------------------------------------------------------------+
//| Combo Mode Selection (Preset / Advanced)                         |
//|                       Combo (Preset /               )                             |
//|                                                                  |
//| TWO INDEPENDENT MODES - Simplified and user-friendly             |
//|                                                                  |
//| PRESET: Quick select from the 8 ready-to-use combinations        |
//|   Uses: inpComboPreset                                           |
//|                                                                  |
//| ADVANCED: Manual control - two components (TF + Step each) and   |
//| one operation (ENUM_COMBO_OPERATION).                            |
//|   Uses: inpComboComp1TF/Step, inpComboOp1, inpComboComp2Enabled, |
//|         inpComboComp2TF/Step                                     |
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
//| Step Size Type (TH, SS, LS, 4/3 ratio)                            |
//+------------------------------------------------------------------+
enum ENUM_COMBO_STEP_TYPE {
    COMBO_STEP_TH = 0,          // TH: Base step (1.0  )
    COMBO_STEP_SS = 1,          // SS: Short step (1.5  )
    COMBO_STEP_LS = 2,          // LS: Long step (2.0  )
    COMBO_STEP_RATIO_4_3 = 3    // 4/3 ratio: TH * 1.333333...
};

//+------------------------------------------------------------------+
//| Preset Combinations - practical daily-use set (8 presets)        |
//|                                                                  |
//| DESIGN PRINCIPLE: keep only the commonly used combinations;      |
//| anything else can be built with Advanced Mode.                  |
//+------------------------------------------------------------------+
enum ENUM_COMBO_PRESET {
    COMBO_PRESET_BALANCED_MEDIUM = 0,   // (Pattern + Trigger) / 2 [Most Popular]
    COMBO_PRESET_BALANCED_LONG = 1,     // (Structure + Pattern) / 2
    COMBO_PRESET_BALANCED_TRIPLE = 2,   // (Trigger + Pattern + Structure) / 3
    COMBO_PRESET_CONSERVATIVE = 3,      // max(Structure, Pattern)
    COMBO_PRESET_AGGRESSIVE = 4,        // min(Trigger, Sub)
    COMBO_PRESET_TREND_FILTER = 5,      // Structure - Sub
    COMBO_PRESET_SS = 6,                 // Pattern / SS = same spacing as Short Step mode
    COMBO_PRESET_RATIO_4_3 = 7           // Pattern / (TH * 4/3) = TH * 1.333333...
};

// TH3 Label Position
//         label    TH3
enum ENUM_TH3_LABEL_POSITION {
    TH3_LABEL_START = 0,        // Start (Beginning of line)
    TH3_LABEL_MIDDLE = 1,       // Middle (Center of visible range)
    TH3_LABEL_END = 2,          // End (Right side - Default)
    TH3_LABEL_HIDDEN = 3        // Hidden (No labels)
};

// Unified Zone Display Style (Used by ALL modes)
//
// P-UI-62: THIS IS AN APPEARANCE AXIS, NOT A VISIBILITY AXIS.
//
// Slot 2 used to be `ZONE_STYLE_HIDDEN`, which DELETED the zone objects - a second
// mechanism for the question the MID ZONES master switch already owns ("are zones
// shown at all?"). Two owners for one question is how a user ends up with a card
// whose third pill fights the switch directly above it, and it is what the report
// names: «هیدن از همون دکمه بالا استفاده میشه دیگه».
//
// The three states are now three genuinely different PICTURES of the same band, and
// the two halves of a zone - the BAND and its EDGE - can be set independently:
//
//   FILLED   : band only            (filled = true,  outline = false)
//   EMPTY    : edge only            (filled = false, outline = true)
//   OUTLINED : band AND edge at once (filled = true,  outline = true)
//
// The edge half is not decoration: OBJ_RECTANGLE ignores OBJPROP_STYLE/WIDTH, so a
// FILLED band has no visible line to style - which is exactly why the BORDER and
// BORDER WIDTH rows of the card did nothing until now. The edge is drawn as its own
// object family and takes those settings.
enum ENUM_ZONE_STYLE {
    ZONE_STYLE_BOX_FILLED = 0,    // Filled (band only)
    ZONE_STYLE_BOX_EMPTY = 1,     // Empty (edge only, no band)
    ZONE_STYLE_BOX_OUTLINED = 2   // Outlined (band AND its edge)
};

// Legacy aliases for backward compatibility
//                      
#define ENUM_TH3_ZONE_STYLE ENUM_ZONE_STYLE
#define ENUM_FACTOR_ZONE_STYLE ENUM_ZONE_STYLE
#define TH3_ZONE_BOX_FILLED ZONE_STYLE_BOX_FILLED
#define TH3_ZONE_BOX_EMPTY ZONE_STYLE_BOX_EMPTY
#define TH3_ZONE_BOX_OUTLINED ZONE_STYLE_BOX_OUTLINED
#define FACTOR_ZONE_BOX_FILLED ZONE_STYLE_BOX_FILLED
#define FACTOR_ZONE_BOX_EMPTY ZONE_STYLE_BOX_EMPTY
#define FACTOR_ZONE_BOX_OUTLINED ZONE_STYLE_BOX_OUTLINED

// TH3 Drawing Mode
//     TH3 (Steps       AB=CD)
enum ENUM_TH3_DRAWING_MODE {
    TH3_MODE_STEPS = 0,         // Steps Mode (2-point drag)
    TH3_MODE_ABCD = 1           // AB=CD Mode (3-point click: A, B, C       calculates D)
};

// NOTE: TH3_TEST_FREQUENCIES[] removed   replaced by Binary Subdivision Frequency System
// in ProjectConstants.mqh (runtime calculation via GetFrequencyByIndex())

//+------------------------------------------------------------------+
//| ENUM: Adaptive Scaling Mode                                      |
//|                                                    |
//+------------------------------------------------------------------+
enum ENUM_ADAPTIVE_MODE {
    ADAPTIVE_FIXED   = 0,    // Fixed (No Adaptation)
    ADAPTIVE_ATR     = 1,    // ATR Adaptive (Full)
    ADAPTIVE_BLENDED = 2,    // Blended (Mix ATR + TH)
    ADAPTIVE_FRACTAL = 3     // Fractal Jump (Power of 2 steps based on ATR)
};

// Fractal Jump Strategy
enum ENUM_FRACTAL_JUMP_STRATEGY {
    JUMP_CONSERVATIVE = 0,   // Conservative (Original log2 with bias)
    JUMP_AGGRESSIVE   = 1    // Aggressive (Jump to higher levels earlier)
};

// Adaptive Scaling Constants
#define MIN_SCALING_FACTOR      0.1    // Minimum allowed scaling factor
#define MAX_SCALING_FACTOR      10.0   // Maximum allowed scaling factor
#define DEFAULT_SMOOTHING_PERIOD 20    // Default EMA smoothing period
#define DEFAULT_BLEND_RATIO     0.5    // Default blend ratio (50/50)

// Global State Variables for Adaptive Scaling
static int g_fractalShift = 0;          // Current fractal level shift (power of 2)

//+------------------------------------------------------------------+
//| TH3 Object Name Suffixes (Magic Numbers Elimination)            |
//|            TH3 (  Magic Numbers)                       |
//+------------------------------------------------------------------+
#define TH3_SUFFIX_LINE_AB "_Line_AB"
#define TH3_SUFFIX_LINE_BC "_Line_BC"
#define TH3_SUFFIX_TARGET  "_Target_"
#define TH3_SUFFIX_POINT   "_Point_"
#define TH3_SUFFIX_LABEL   "_Label_"
#define TH3_SUFFIX_INFO    "_Info"
#define TH3_SUFFIX_ZONE    "_Zone"

//  
// ZONE ERROR CODES (used by ZoneValidator / ZoneCalculator)
//  
#define ZONE_ERROR_NONE             0
#define ZONE_ERROR_INVALID_PRICES   1
#define ZONE_ERROR_EQUAL_PRICES     2
#define ZONE_ERROR_INVALID_HEIGHT   3
#define ZONE_ERROR_INVERTED_BOUNDS  4
#define ZONE_ERROR_OUT_OF_RANGE     5

//  
// PIPELINE STRUCTS (used by Zone system)
//  

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
