//+------------------------------------------------------------------+
//|                                             RuntimeSettings.mqh  |
//|  SINGLE OWNER of the runtime-editable settings.                  |
//|                                                                  |
//|  The indicator has two ways to configure the same settings:      |
//|    1. MT4 Inputs dialog  ->  the real `input` variables declared |
//|       in PropertiesAndInputs.mqh (groups 01..18).                |
//|    2. Settings panels    ->  live edits on the chart.            |
//|                                                                  |
//|  Runtime-editable settings therefore keep a runtime copy (g_*)   |
//|  plus a macro redirection (#define inpX gX) so that ALL modules  |
//|  compiled after this file read the runtime copy — never the raw  |
//|  input variable (which the panels cannot update).                |
//|                                                                  |
//|  Ownership & lifecycle:                                          |
//|    · input declarations ......... PropertiesAndInputs.mqh        |
//|    · runtime copies + redirection  THIS FILE (RuntimeSettings)   |
//|    · seeding from the inputs .... RuntimeSettingsInit() called   |
//|      first thing in OnInitHandler — the MT4 Inputs dialog values |
//|      are copied into the runtime copies at attach time.          |
//|    · persisted overrides ........ RuntimeSettings(Load|Save)     |
//|      Overrides (OV_* chart-scoped GVs) re-applied on top after  |
//|      seeding; panels/hotkeys edit the runtime copies live.       |
//|                                                                  |
//|  Include order (both entry .mq4 files):                          |
//|    PropertiesAndInputs.mqh  (declares the real inputs)           |
//|    ... core/validation modules ...                               |
//|    RuntimeSettings.mqh      (THIS FILE — mirrors + #defines)     |
//|    GlobalVariables.mqh      (runtime indicator state)            |
//|    ... all consumers read inpX == runtime copy ...               |
//|                                                                  |
//|  NOTE: the seeding body below is written BEFORE the #define      |
//|  block on purpose — only there are the real input names still    |
//|  reachable (macros would rewrite them into no-op self-assigns).  |
//+------------------------------------------------------------------+
#ifndef RUNTIME_SETTINGS_MQH
#define RUNTIME_SETTINGS_MQH
#property strict

//==============================================================================
// RUNTIME COPIES OF THE PANEL-EDITABLE INPUTS
// Seeded from PropertiesAndInputs.mqh on attach (RuntimeSettingsInit), then
// overridden live by the settings panels / persisted OV_ overrides.
//==============================================================================
static bool g_useDynamicTradingDay = true;                       // [01] inpUseDynamicTradingDay
static bool g_basePriceThresholdEnabled = true;                  // [01] inpBasePriceThresholdEnabled
static double g_basePriceThresholdPercent = 0.066;               // [01] inpBasePriceThresholdPercent
static int g_maxLevels = 144;                                    // [01] inpMaxLevels
static bool g_triggerLevelsEnabled = true;                       // [09.3] inpShowTrigger (+ hotkey toggle state)
static int g_triggerWidth = 1;                                   // [08.1] inpTriggerWidth (legacy — pipeline lines use g_line* [08.4])
static ENUM_LINE_STYLE g_triggerStyle = STYLE_DOT;               // [08.1] inpTriggerStyle (legacy — pipeline lines use g_line* [08.4])
static color g_triggerColor = clrBlack;                          // [08.1] inpTriggerColor (trigger ZONE fill)
// [08.4] UNIFIED LINES — the SINGLE appearance store for ALL pipeline
// lines (trigger-subdivision AND structure-interval lines). The T switch
// (g_triggerLevelsEnabled) gates ONLY the trigger zones, never these.
static int g_lineWidth = 1;                                      // [08.4] inpLineWidth
static ENUM_LINE_STYLE g_lineStyle = STYLE_DOT;                  // [08.4] inpLineStyle
static color g_lineColor = clrBlack;                             // [08.4] inpLineColor
static int g_lineTransparency = 50;                              // [08.4] inpLineTransparency
// [08.5] BASE BOX BORDER — the committed box look (border only, never
// filled — like MT4's own rectangle). Edited from the Base Box card (12).
static color g_boxBorderColor = C'255,171,0';                    // [08.5] inpBoxBorderColor
static ENUM_LINE_STYLE g_boxBorderStyle = STYLE_SOLID;           // [08.5] inpBoxBorderStyle
static int g_boxBorderWidth = 2;                                 // [08.5] inpBoxBorderWidth
static int g_boxBorderTransparency = 0;                          // [08.5] palette TR (default solid)
static int g_bkTargetR = 2;                                      // [08.5] inpBKTargetR (TP = Entry + R x N)
static color g_bkEntryColor = C'30,144,255';                     // [08.5] inpBKEntryColor
static color g_bkStopColor = C'220,50,50';                       // [08.5] inpBKStopColor
static color g_bkTargetColor = C'46,139,87';                     // [08.5] inpBKTargetColor
static int g_bkShowInfo = 0;                                     // [08.5] inpBKShowInfo (0=Auto-hide, 1=Always show)
// [08.5] BASE BOX FILL + USER TEXT — TV-parity 2026-09-07 (Style/Text tabs).
// Fill default transparency = 100 (invisible) so pre-fill charts stay
// pixel-identical hollow boxes until the user touches FILL.
static color g_boxFillColor = C'255,171,0';                    // [08.5] inpBoxFillColor
static int g_boxFillTransparency = 100;                        // [08.5] palette TR (default invisible)
static color g_bkTextColor = C'255,255,255';                   // [08.5] inpBKTextColor
static int g_bkTextSize = 10;                                  // [08.5] inpBKTextSize (TV default 10)
static bool g_bkBold = false;                                  // [08.5] inpBKBold
static bool g_bkItalic = false;                                // [08.5] inpBKItalic
static int g_bkAlign = 2;                                      // [08.5] inpBKAlign (0=Left,1=Center,2=Right)
static int g_bkVAlign = 1;                                     // [08.5] inpBKVAlign (0=Top,1=Inside,2=Bottom)
static color g_triggerLabelColor = clrBlack;                     // [09.3] inpTriggerLabelColor
static int g_triggerTransparency = 50;                           // [09.3] inpTriggerTransparency
static int g_ssLevelWidth = 1;                                   // [04] inpSSLevelWidth
static ENUM_LINE_STYLE g_ssLevelStyle = STYLE_DOT;               // [04] inpSSLevelStyle
static color g_ssLevelColor = clrGoldenrod;                      // [04] inpSSLevelColor
static int g_ssTransparency = 0;                                 // palette TR (default solid)
static int g_lsLevelWidth = 1;                                   // [04] inpLSLevelWidth
static ENUM_LINE_STYLE g_lsLevelStyle = STYLE_DOT;               // [04] inpLSLevelStyle
static color g_lsLevelColor = clrOrange;                         // [04] inpLSLevelColor
static int g_lsTransparency = 0;                                 // palette TR (default solid)
static bool g_lsFirst = true;                                    // [04] inpLSFirst
static ENUM_STEP_CALCULATION_MODE g_stepCalculationMode = TH_STEP; // [01] inpStepCalculationMode
static bool g_showLines = true;                                  // [03] inpShowLines
static bool g_showTHLevels = true;                               // [03] inpShowTHLevels
static bool g_showStructure = true;                              // [09.1] inpShowStructure
static bool g_showStructureL1 = true;                            // [09.2] inpShowStructureL1
static bool g_showStructureL2 = true;                            // [09.2] inpShowStructureL2
static bool g_showStructureL3 = true;                            // [09.2] inpShowStructureL3
static bool g_showStructureL4 = true;                            // [09.2] inpShowStructureL4
static bool g_showStructureL5 = true;                            // [09.2] inpShowStructureL5
static bool g_showMidpointLine = true;                           // [03] inpShowMidpointLine
static bool g_showMidZones = true;                               // [07.1] inpShowMidZones
static ENUM_ZONE_STYLE g_midZoneStyle = ZONE_STYLE_BOX_FILLED;   // [07.1] inpMidZoneStyle
static int g_midZoneTransparency = 50;                           // [07.2] inpMidZoneTransparency
static double g_midZoneHeightPercent = 33.0;                     // [07.2] inpMidZoneHeightPercent
static ENUM_LINE_STYLE g_midZoneBorderStyle = STYLE_SOLID;       // [07.2] inpMidZoneBorderStyle
static int g_midZoneBorderWidth = 1;                             // [07.2] inpMidZoneBorderWidth
static bool g_showPipDistanceLabels = true;                      // [03] inpShowPipDistanceLabels
static bool g_showATRLabels = false;                             // [03] inpShowATRLabels
static bool g_showATRTargets = true;                             // [03] inpShowATRTargets
static bool g_showATRTradeLabels = true;                         // [03] inpShowATRTradeLabels
static bool g_showATRTradeSLLabels = true;                       // [03] inpShowATRTradeSLLabels
static bool g_showATRTradeTPLabels = true;                       // [03] inpShowATRTradeTPLabels
static int g_atrLabelRowGap = 10;                                // [03] inpATRTradeLabelRowGap
static bool g_showTHLabels = false;                              // [03] inpShowTHLabels
static bool g_showFractalTHs = false;                            // [03] inpShowFractalTHs
static bool g_showStandardTHs = false;                           // [03] inpShowStandardTHs
static bool g_showTHTargets = true;                              // [03] inpShowTHTargets
static int g_thLabelsMarginBottom = 40;                          // [13] inpTHLabelsMarginBottom
static bool g_enableTH3Tool = true;                              // [14] inpEnableTH3Tool
static ENUM_TH3_DRAWING_MODE g_th3DrawingMode = TH3_MODE_ABCD;  // [14] inpTH3DrawingMode
static double g_th3BaseStepPercent = 28.125;                     // [14] inpTH3BaseStepPercent
static int g_th3Width = 1;                                       // [14] inpTH3Width
static ENUM_LINE_STYLE g_th3Style = STYLE_SOLID;                 // [14] inpTH3Style
static color g_th3Color = clrDarkBlue;                           // [14] inpTH3Color
static color g_th3PipTextColor = clrDarkBlue;                    // [14] inpTH3PipTextColor
static bool g_showTH3Labels = true;                              // [14] inpShowTH3Labels
static int g_customPriceLevelWidth = 1;                          // [02] inpCustomPriceLevelWidth
static color g_customPriceLevelColor = clrDodgerBlue;            // [02] inpCustomPriceLevelColor
static int g_customPriceTransparency = 0;                        // palette TR (default solid)
static bool g_enableMagnet = true;                               // [02] inpEnableMagnet
static int g_magnetSensitivityPips = 10;                         // [02] inpMagnetSensitivityPips
static ENUM_FACTOR_MODE g_factorMode = FACTOR_MODE_AUTO;         // [06] inpFactorMode
static ENUM_FACTOR_DISPLAY_MODE g_factorDisplayMode = FACTOR_DISPLAY_DIRECT; // [06] inpFactorDisplayMode
static ENUM_FACTOR_AUTO_BASIS g_factorAutoBasis = FACTOR_BASIS_CONTROL;      // [06] inpFactorAutoBasis
static double g_factorValue = 50.0;                              // [06] inpFactorValue
static color g_factorLevelColor = C'0,100,0';                    // [06] inpFactorLevelColor
static int g_factorTransparency = 0;                             // palette TR (default solid)
static ENUM_LINE_STYLE g_factorLevelStyle = STYLE_DOT;           // [06] inpFactorLevelStyle
static int g_factorLevelWidth = 1;                               // [06] inpFactorLevelWidth
// [05] STYLE / COMBO STEP — runtime mirrors so the Step card's inline Combo
// section can edit them live (same rails as every other mirror: FF_ defaults,
// OV_ persistence, Q-reset). Consumers read inpComboX == these copies.
static ENUM_COMBO_MODE g_comboMode = COMBO_MODE_PRESET;           // [05] inpComboMode
static ENUM_COMBO_PRESET g_comboPreset = COMBO_PRESET_BALANCED_MEDIUM; // [05] inpComboPreset
static ENUM_COMBO_TIMEFRAME_TYPE g_comboComp1TF = COMBO_TF_PATTERN;    // [05] inpComboComp1TF
static ENUM_COMBO_STEP_TYPE g_comboComp1Step = COMBO_STEP_TH;     // [05] inpComboComp1Step
static ENUM_COMBO_OPERATION g_comboOp1 = COMBO_OP_AVERAGE;        // [05] inpComboOp1
static bool g_comboComp2Enabled = true;                           // [05] inpComboComp2Enabled
static ENUM_COMBO_TIMEFRAME_TYPE g_comboComp2TF = COMBO_TF_TRIGGER;    // [05] inpComboComp2TF
static ENUM_COMBO_STEP_TYPE g_comboComp2Step = COMBO_STEP_TH;     // [05] inpComboComp2Step

//==============================================================================
// FACTORY DEFAULTS — the raw Inputs-dialog values as attached, captured in
// RuntimeSettingsInit BEFORE the #define block below rewrites every inpX into
// its runtime copy. Reset actions (panel Reset button via PnlDefVal, and the
// Q hotkey "Reset All Overrides") must restore these captured values — reading
// inpX there would silently read the CURRENT runtime copy (a no-op).
//==============================================================================
enum FactorySetting
{
   FF_MAX_LEVELS,          // inpMaxLevels
   FF_TRIGGER_WIDTH,       // inpTriggerWidth (legacy)
   FF_TRIGGER_STYLE,       // inpTriggerStyle (legacy)
   FF_TRIGGER_TRANSPARENCY,// inpTriggerTransparency
   FF_TRIGGER_SHOW,        // inpShowTrigger
   FF_LINE_WIDTH,          // inpLineWidth
   FF_LINE_STYLE,          // inpLineStyle
   FF_LINE_TRANSPARENCY,   // inpLineTransparency
   FF_SHOW_LINES,          // inpShowLines
   FF_SHOW_MIDZONES,       // inpShowMidZones
   FF_MIDZONE_STYLE,       // inpMidZoneStyle
   FF_MIDZONE_TRANSPARENCY,// inpMidZoneTransparency
   FF_MIDZONE_HEIGHT,      // inpMidZoneHeightPercent
   FF_MIDZONE_BORDER_STYLE,// inpMidZoneBorderStyle
   FF_MIDZONE_BORDER_WIDTH,// inpMidZoneBorderWidth
   FF_LS_FIRST,            // inpLSFirst
   FF_SHOW_MIDPOINT,       // inpShowMidpointLine
   FF_SHOW_ATR,            // inpShowATRLabels
   FF_ATR_TARGETS,         // inpShowATRTargets
   FF_ATR_TRADE,           // inpShowATRTradeLabels
   FF_ATR_TRADE_SL,        // inpShowATRTradeSLLabels
   FF_ATR_TRADE_TP,        // inpShowATRTradeTPLabels
   FF_PIP_LABELS,          // inpShowPipDistanceLabels
   FF_ATR_ROW_GAP,         // inpATRTradeLabelRowGap
   FF_SHOW_TH_LABELS,      // inpShowTHLabels
   FF_TH_FRACTAL,          // inpShowFractalTHs
   FF_TH_STANDARD,         // inpShowStandardTHs
   FF_TH_TARGETS,          // inpShowTHTargets
   FF_TH_MARGIN_BOTTOM,    // inpTHLabelsMarginBottom
   FF_ENABLE_TH3,          // inpEnableTH3Tool
   FF_TH3_DRAW_MODE,       // inpTH3DrawingMode
   FF_TH3_BASE_STEP,       // inpTH3BaseStepPercent
   FF_TH3_WIDTH,           // inpTH3Width
   FF_TH3_STYLE,           // inpTH3Style
   FF_TH3_SHOW_LABELS,     // inpShowTH3Labels
   FF_CUSTOM_WIDTH,        // inpCustomPriceLevelWidth
   FF_ENABLE_MAGNET,       // inpEnableMagnet
   FF_MAGNET_SENS,         // inpMagnetSensitivityPips
   FF_STEP_CALC_MODE,      // inpStepCalculationMode
   FF_FACTOR_MODE,         // inpFactorMode
   FF_FACTOR_DISPLAY,      // inpFactorDisplayMode
   FF_FACTOR_BASIS,        // inpFactorAutoBasis
   FF_FACTOR_VALUE,        // inpFactorValue
   FF_FACTOR_WIDTH,        // inpFactorLevelWidth
   FF_FACTOR_STYLE,        // inpFactorLevelStyle
   FF_SHOW_STRUCTURE,      // inpShowStructure
   FF_SHOW_STRUCTURE_L1,   // inpShowStructureL1
   FF_SHOW_STRUCTURE_L2,   // inpShowStructureL2
   FF_SHOW_STRUCTURE_L3,   // inpShowStructureL3
   FF_SHOW_STRUCTURE_L4,   // inpShowStructureL4
   FF_SHOW_STRUCTURE_L5,   // inpShowStructureL5
   FF_COMBO_MODE,        // inpComboMode
   FF_COMBO_PRESET,      // inpComboPreset
   FF_COMBO_C1TF,        // inpComboComp1TF
   FF_COMBO_C1STEP,      // inpComboComp1Step
   FF_COMBO_OP1,         // inpComboOp1
   FF_COMBO_C2ON,        // inpComboComp2Enabled
   FF_COMBO_C2TF,        // inpComboComp2TF
   FF_COMBO_C2STEP,      // inpComboComp2Step
   FF_BOX_WIDTH,         // inpBoxBorderWidth
   FF_BOX_STYLE,         // inpBoxBorderStyle
   FF_BOX_TRANSPARENCY,  // palette TR (default solid, no input)
   FF_BK_TARGET_R,       // inpBKTargetR
   FF_BK_ENTRY,          // inpBKEntryColor
   FF_BK_SL,             // inpBKStopColor
   FF_BK_TP,             // inpBKTargetColor
   FF_BK_SHOW_INFO,      // inpBKShowInfo
   FF_BOX_FILL,          // inpBoxFillColor
   FF_BOX_FILL_TR,       // fill transparency (default invisible, no input)
   FF_BK_TEXT,           // inpBKTextColor
   FF_BK_TEXT_SIZE,      // inpBKTextSize
   FF_BK_BOLD,           // inpBKBold
   FF_BK_ITALIC,         // inpBKItalic
   FF_BK_ALIGN,          // inpBKAlign
   FF_BK_VALIGN,         // inpBKVAlign
   FF_COUNT
};
static double g_factoryDefaults[FF_COUNT];

double FactoryDefault(const int f)
{
   if(f < 0 || f >= FF_COUNT) return 0.0;
   return g_factoryDefaults[f];
}

//==============================================================================
// SEEDING — copies the real MT4 Inputs-dialog values into the runtime copies.
// MUST stay above the #define block: down there the input names are rewritten
// by the macros and an assignment like `g_maxLevels = inpMaxLevels;` would
// silently become `g_maxLevels = g_maxLevels;` (a no-op). Called first thing
// in OnInitHandler so every consumer sees the attached settings.
//==============================================================================
void RuntimeSettingsInit()
{
   // ── FACTORY DEFAULTS (capture FIRST — below this function the #define
   //    block rewrites every inpX into its runtime copy) ──
   g_factoryDefaults[FF_MAX_LEVELS]          = inpMaxLevels;
   g_factoryDefaults[FF_TRIGGER_WIDTH]       = inpTriggerWidth;
   g_factoryDefaults[FF_TRIGGER_STYLE]       = inpTriggerStyle;
   g_factoryDefaults[FF_TRIGGER_TRANSPARENCY]= inpTriggerTransparency;
   g_factoryDefaults[FF_TRIGGER_SHOW]        = inpShowTrigger;
   g_factoryDefaults[FF_LINE_WIDTH]          = inpLineWidth;
   g_factoryDefaults[FF_LINE_STYLE]          = inpLineStyle;
   g_factoryDefaults[FF_LINE_TRANSPARENCY]   = inpLineTransparency;
   g_factoryDefaults[FF_SHOW_LINES]          = inpShowLines;
   g_factoryDefaults[FF_SHOW_MIDZONES]       = inpShowMidZones;
   g_factoryDefaults[FF_MIDZONE_STYLE]       = inpMidZoneStyle;
   g_factoryDefaults[FF_MIDZONE_TRANSPARENCY]= inpMidZoneTransparency;
   g_factoryDefaults[FF_MIDZONE_HEIGHT]      = inpMidZoneHeightPercent;
   g_factoryDefaults[FF_MIDZONE_BORDER_STYLE]= inpMidZoneBorderStyle;
   g_factoryDefaults[FF_MIDZONE_BORDER_WIDTH]= inpMidZoneBorderWidth;
   g_factoryDefaults[FF_LS_FIRST]            = inpLSFirst;
   g_factoryDefaults[FF_SHOW_MIDPOINT]       = inpShowMidpointLine;
   g_factoryDefaults[FF_SHOW_ATR]            = inpShowATRLabels;
   g_factoryDefaults[FF_ATR_TARGETS]         = inpShowATRTargets;
   g_factoryDefaults[FF_ATR_TRADE]           = inpShowATRTradeLabels;
   g_factoryDefaults[FF_ATR_TRADE_SL]        = inpShowATRTradeSLLabels;
   g_factoryDefaults[FF_ATR_TRADE_TP]        = inpShowATRTradeTPLabels;
   g_factoryDefaults[FF_PIP_LABELS]          = inpShowPipDistanceLabels;
   g_factoryDefaults[FF_ATR_ROW_GAP]         = inpATRTradeLabelRowGap;
   g_factoryDefaults[FF_SHOW_TH_LABELS]      = inpShowTHLabels;
   g_factoryDefaults[FF_TH_FRACTAL]          = inpShowFractalTHs;
   g_factoryDefaults[FF_TH_STANDARD]         = inpShowStandardTHs;
   g_factoryDefaults[FF_TH_TARGETS]          = inpShowTHTargets;
   g_factoryDefaults[FF_TH_MARGIN_BOTTOM]    = inpTHLabelsMarginBottom;
#ifndef BUILD_LITE
    // TH3TOOL-OFF: inputs retired — mirrors keep their static defaults:
    //g_factoryDefaults[FF_ENABLE_TH3]          = inpEnableTH3Tool;
    //g_factoryDefaults[FF_TH3_DRAW_MODE]       = inpTH3DrawingMode;
    //g_factoryDefaults[FF_TH3_BASE_STEP]       = inpTH3BaseStepPercent;
    //g_factoryDefaults[FF_TH3_WIDTH]           = inpTH3Width;
    //g_factoryDefaults[FF_TH3_STYLE]           = inpTH3Style;
    //g_factoryDefaults[FF_TH3_SHOW_LABELS]     = inpShowTH3Labels;
#else
   // Lite: TH3 inputs don't exist; factory = the same static defaults the
   // runtime copies keep (no input seeding happens in Lite for TH3).
   g_factoryDefaults[FF_ENABLE_TH3]          = true;
   g_factoryDefaults[FF_TH3_DRAW_MODE]       = TH3_MODE_ABCD;
   g_factoryDefaults[FF_TH3_BASE_STEP]       = 28.125;
   g_factoryDefaults[FF_TH3_WIDTH]           = 1;
   g_factoryDefaults[FF_TH3_STYLE]           = STYLE_SOLID;
   g_factoryDefaults[FF_TH3_SHOW_LABELS]     = true;
#endif
   g_factoryDefaults[FF_CUSTOM_WIDTH]        = inpCustomPriceLevelWidth;
   g_factoryDefaults[FF_ENABLE_MAGNET]       = inpEnableMagnet;
   g_factoryDefaults[FF_MAGNET_SENS]         = inpMagnetSensitivityPips;
   g_factoryDefaults[FF_STEP_CALC_MODE]      = inpStepCalculationMode;
   g_factoryDefaults[FF_FACTOR_MODE]         = inpFactorMode;
   g_factoryDefaults[FF_FACTOR_DISPLAY]      = inpFactorDisplayMode;
   g_factoryDefaults[FF_FACTOR_BASIS]        = inpFactorAutoBasis;
   g_factoryDefaults[FF_FACTOR_VALUE]        = inpFactorValue;
   g_factoryDefaults[FF_FACTOR_WIDTH]        = inpFactorLevelWidth;
   g_factoryDefaults[FF_FACTOR_STYLE]        = inpFactorLevelStyle;
   g_factoryDefaults[FF_SHOW_STRUCTURE]      = inpShowStructure;
   g_factoryDefaults[FF_SHOW_STRUCTURE_L1]   = inpShowStructureL1;
   g_factoryDefaults[FF_SHOW_STRUCTURE_L2]   = inpShowStructureL2;
   g_factoryDefaults[FF_SHOW_STRUCTURE_L3]   = inpShowStructureL3;
   g_factoryDefaults[FF_SHOW_STRUCTURE_L4]   = inpShowStructureL4;
   g_factoryDefaults[FF_SHOW_STRUCTURE_L5]   = inpShowStructureL5;
   g_factoryDefaults[FF_COMBO_MODE]           = inpComboMode;
   g_factoryDefaults[FF_COMBO_PRESET]         = inpComboPreset;
   g_factoryDefaults[FF_COMBO_C1TF]           = inpComboComp1TF;
   g_factoryDefaults[FF_COMBO_C1STEP]         = inpComboComp1Step;
   g_factoryDefaults[FF_COMBO_OP1]            = inpComboOp1;
   g_factoryDefaults[FF_COMBO_C2ON]           = inpComboComp2Enabled;
   g_factoryDefaults[FF_COMBO_C2TF]           = inpComboComp2TF;
   g_factoryDefaults[FF_COMBO_C2STEP]         = inpComboComp2Step;
   g_factoryDefaults[FF_BOX_WIDTH]           = inpBoxBorderWidth;
   g_factoryDefaults[FF_BOX_STYLE]           = inpBoxBorderStyle;
   g_factoryDefaults[FF_BOX_TRANSPARENCY]    = 0;
   g_factoryDefaults[FF_BK_TARGET_R]         = inpBKTargetR;
   g_factoryDefaults[FF_BK_ENTRY]            = inpBKEntryColor;
   g_factoryDefaults[FF_BK_SL]               = inpBKStopColor;
   g_factoryDefaults[FF_BK_TP]               = inpBKTargetColor;
   g_factoryDefaults[FF_BK_SHOW_INFO]        = inpBKShowInfo;
   g_factoryDefaults[FF_BOX_FILL]            = inpBoxFillColor;
   g_factoryDefaults[FF_BOX_FILL_TR]         = 100;
   g_factoryDefaults[FF_BK_TEXT]             = inpBKTextColor;
   g_factoryDefaults[FF_BK_TEXT_SIZE]        = inpBKTextSize;
   g_factoryDefaults[FF_BK_BOLD]             = inpBKBold;
   g_factoryDefaults[FF_BK_ITALIC]           = inpBKItalic;
   g_factoryDefaults[FF_BK_ALIGN]            = inpBKAlign;
   g_factoryDefaults[FF_BK_VALIGN]           = inpBKVAlign;

   // [01] CALCULATION / MODE & CORE
   g_useDynamicTradingDay = inpUseDynamicTradingDay;
   g_basePriceThresholdEnabled = inpBasePriceThresholdEnabled;
   g_basePriceThresholdPercent = inpBasePriceThresholdPercent;
   g_maxLevels = inpMaxLevels;
   g_stepCalculationMode = inpStepCalculationMode;

   // [02] BASE PRICE / ANCHOR (custom line + magnet)
   g_customPriceLevelWidth = inpCustomPriceLevelWidth;
   g_customPriceLevelColor = inpCustomPriceLevelColor;
   g_enableMagnet = inpEnableMagnet;
   g_magnetSensitivityPips = inpMagnetSensitivityPips;

   // [03] DISPLAY / VISIBILITY
   g_showLines = inpShowLines;
   g_showTHLevels = inpShowTHLevels;
   g_showTHLabels = inpShowTHLabels;
   g_showTHTargets = inpShowTHTargets;
   g_showPipDistanceLabels = inpShowPipDistanceLabels;
   g_showMidpointLine = inpShowMidpointLine;
   g_showFractalTHs = inpShowFractalTHs;
   g_showStandardTHs = inpShowStandardTHs;
   g_showATRLabels = inpShowATRLabels;
   g_showATRTargets = inpShowATRTargets;
   g_showATRTradeLabels = inpShowATRTradeLabels;
   g_showATRTradeSLLabels = inpShowATRTradeSLLabels;
   g_showATRTradeTPLabels = inpShowATRTradeTPLabels;
   g_atrLabelRowGap = inpATRTradeLabelRowGap;

   // [04] STYLE / SS-LS STEP
   g_lsFirst = inpLSFirst;
   g_ssLevelColor = inpSSLevelColor;
   g_ssLevelStyle = inpSSLevelStyle;
   g_ssLevelWidth = inpSSLevelWidth;
   g_lsLevelColor = inpLSLevelColor;
   g_lsLevelStyle = inpLSLevelStyle;
   g_lsLevelWidth = inpLSLevelWidth;

   // [06] STYLE / FACTOR STEP
   g_factorMode = inpFactorMode;
   g_factorDisplayMode = inpFactorDisplayMode;
   g_factorAutoBasis = inpFactorAutoBasis;
   g_factorValue = inpFactorValue;
   g_factorLevelColor = inpFactorLevelColor;
   g_factorLevelStyle = inpFactorLevelStyle;
   g_factorLevelWidth = inpFactorLevelWidth;

   // [05] STYLE / COMBO STEP
   g_comboMode = inpComboMode;
   g_comboPreset = inpComboPreset;
   g_comboComp1TF = inpComboComp1TF;
   g_comboComp1Step = inpComboComp1Step;
   g_comboOp1 = inpComboOp1;
   g_comboComp2Enabled = inpComboComp2Enabled;
   g_comboComp2TF = inpComboComp2TF;
   g_comboComp2Step = inpComboComp2Step;

   // [07] ZONES / MID
   g_showMidZones = inpShowMidZones;
   g_midZoneStyle = inpMidZoneStyle;
   g_midZoneTransparency = inpMidZoneTransparency;
   g_midZoneHeightPercent = inpMidZoneHeightPercent;
   g_midZoneBorderStyle = inpMidZoneBorderStyle;
   g_midZoneBorderWidth = inpMidZoneBorderWidth;

   // [08] LEVEL STYLE / LINES + [09] VISIBILITY / STRUCTURE & TRIGGER
   g_showStructure = inpShowStructure;
   g_showStructureL1 = inpShowStructureL1;
   g_showStructureL2 = inpShowStructureL2;
   g_showStructureL3 = inpShowStructureL3;
   g_showStructureL4 = inpShowStructureL4;
   g_showStructureL5 = inpShowStructureL5;
   g_triggerLevelsEnabled = inpShowTrigger;
   g_triggerTransparency = inpTriggerTransparency;
   g_triggerColor = inpTriggerColor;
   g_triggerStyle = inpTriggerStyle;
   g_triggerWidth = inpTriggerWidth;
   g_triggerLabelColor = inpTriggerLabelColor;
   g_lineWidth = inpLineWidth;
   g_lineStyle = inpLineStyle;
   g_lineColor = inpLineColor;
   g_lineTransparency = inpLineTransparency;
   g_boxBorderWidth = inpBoxBorderWidth;
   g_boxBorderStyle = inpBoxBorderStyle;
   g_boxBorderColor = inpBoxBorderColor;
   g_boxBorderTransparency = 0;
   g_bkTargetR = inpBKTargetR;
   g_bkEntryColor = inpBKEntryColor;
   g_bkStopColor = inpBKStopColor;
   g_bkTargetColor = inpBKTargetColor;
   g_bkShowInfo = inpBKShowInfo;
   g_boxFillColor = inpBoxFillColor;
   g_boxFillTransparency = 100;
   g_bkTextColor = inpBKTextColor;
   g_bkTextSize = inpBKTextSize;
   g_bkBold = inpBKBold;
   g_bkItalic = inpBKItalic;
   g_bkAlign = inpBKAlign;
   g_bkVAlign = inpBKVAlign;

   // [13] ADVANCED / LABEL LAYOUT
   g_thLabelsMarginBottom = inpTHLabelsMarginBottom;

#ifndef BUILD_LITE
    // TH3TOOL-OFF: inputs retired — mirrors keep their static defaults:
    // [14] TH3 TOOL
    //g_enableTH3Tool = inpEnableTH3Tool;
    //g_th3DrawingMode = inpTH3DrawingMode;
    //g_th3BaseStepPercent = inpTH3BaseStepPercent;
    //g_th3Width = inpTH3Width;
    //g_th3Style = inpTH3Style;
    //g_th3Color = inpTH3Color;
    //g_th3PipTextColor = inpTH3PipTextColor;
    //g_showTH3Labels = inpShowTH3Labels;
#endif
}

//==============================================================================
// MACRO REDIRECTIONS — every module compiled AFTER this file that reads an
// `inpX` setting actually reads its runtime copy (gX), which the settings
// panels can edit live. Modules compiled BEFORE this file (PropertiesAndInputs
// itself, InputValidator, ...) keep reading the real input variables — exactly
// what validators want.
//==============================================================================
#define inpUseDynamicTradingDay g_useDynamicTradingDay
#define inpBasePriceThresholdEnabled g_basePriceThresholdEnabled
#define inpBasePriceThresholdPercent g_basePriceThresholdPercent
#define inpMaxLevels g_maxLevels
#define inpShowTrigger g_triggerLevelsEnabled
#define inpShowLines g_showLines
#define inpShowTHLevels g_showTHLevels
#define inpShowStructure g_showStructure
#define inpShowStructureL1 g_showStructureL1
#define inpShowStructureL2 g_showStructureL2
#define inpShowStructureL3 g_showStructureL3
#define inpShowStructureL4 g_showStructureL4
#define inpShowStructureL5 g_showStructureL5
#define inpShowMidpointLine g_showMidpointLine
#define inpShowMidZones g_showMidZones
#define inpMidZoneStyle g_midZoneStyle
#define inpMidZoneTransparency g_midZoneTransparency
#define inpMidZoneHeightPercent g_midZoneHeightPercent
#define inpMidZoneBorderStyle g_midZoneBorderStyle
#define inpMidZoneBorderWidth g_midZoneBorderWidth
#define inpShowPipDistanceLabels g_showPipDistanceLabels
#define inpTriggerWidth g_triggerWidth
#define inpTriggerStyle g_triggerStyle
#define inpTriggerColor g_triggerColor
#define inpTriggerLabelColor g_triggerLabelColor
#define inpTriggerTransparency g_triggerTransparency
#define inpLineWidth g_lineWidth
#define inpLineStyle g_lineStyle
#define inpLineColor g_lineColor
#define inpLineTransparency g_lineTransparency
#define inpBoxBorderColor g_boxBorderColor
#define inpBoxBorderStyle g_boxBorderStyle
#define inpBoxBorderWidth g_boxBorderWidth
#define inpBKTargetR g_bkTargetR
#define inpBKEntryColor g_bkEntryColor
#define inpBKStopColor g_bkStopColor
#define inpBKTargetColor g_bkTargetColor
#define inpBKShowInfo g_bkShowInfo
#define inpBoxFillColor g_boxFillColor
#define inpBKTextColor g_bkTextColor
#define inpBKTextSize g_bkTextSize
#define inpBKBold g_bkBold
#define inpBKItalic g_bkItalic
#define inpBKAlign g_bkAlign
#define inpBKVAlign g_bkVAlign
#define inpSSLevelWidth g_ssLevelWidth
#define inpSSLevelStyle g_ssLevelStyle
#define inpSSLevelColor g_ssLevelColor
#define inpLSLevelWidth g_lsLevelWidth
#define inpLSLevelStyle g_lsLevelStyle
#define inpLSLevelColor g_lsLevelColor
#define inpLSFirst g_lsFirst
#define inpStepCalculationMode g_stepCalculationMode
#define inpShowATRLabels g_showATRLabels
#define inpShowATRTargets g_showATRTargets
#define inpShowATRTradeLabels g_showATRTradeLabels
#define inpShowATRTradeSLLabels g_showATRTradeSLLabels
#define inpShowATRTradeTPLabels g_showATRTradeTPLabels
#define inpATRTradeLabelRowGap g_atrLabelRowGap
#define inpShowTHLabels g_showTHLabels
#define inpShowFractalTHs g_showFractalTHs
#define inpShowStandardTHs g_showStandardTHs
#define inpShowTHTargets g_showTHTargets
#define inpTHLabelsMarginBottom g_thLabelsMarginBottom
#define inpEnableTH3Tool g_enableTH3Tool
#define inpTH3DrawingMode g_th3DrawingMode
#define inpTH3BaseStepPercent g_th3BaseStepPercent
#define inpTH3Width g_th3Width
#define inpTH3Style g_th3Style
#define inpTH3Color g_th3Color
#define inpTH3PipTextColor g_th3PipTextColor
#define inpShowTH3Labels g_showTH3Labels
#define inpCustomPriceLevelWidth g_customPriceLevelWidth
#define inpCustomPriceLevelColor g_customPriceLevelColor
#define inpEnableMagnet g_enableMagnet
#define inpMagnetSensitivityPips g_magnetSensitivityPips
#define inpFactorMode g_factorMode
#define inpFactorDisplayMode g_factorDisplayMode
#define inpFactorAutoBasis g_factorAutoBasis
#define inpFactorValue g_factorValue
#define inpFactorLevelColor g_factorLevelColor
#define inpFactorLevelStyle g_factorLevelStyle
#define inpFactorLevelWidth g_factorLevelWidth
#define inpComboMode g_comboMode
#define inpComboPreset g_comboPreset
#define inpComboComp1TF g_comboComp1TF
#define inpComboComp1Step g_comboComp1Step
#define inpComboOp1 g_comboOp1
#define inpComboComp2Enabled g_comboComp2Enabled
#define inpComboComp2TF g_comboComp2TF
#define inpComboComp2Step g_comboComp2Step

//==============================================================================
// PERSISTED OVERRIDES — panel edits survive re-attach through chart-scoped
// GlobalVariables (prefix + "OV_"). The prefix is chart/symbol-scoped and is
// configured by the UI (BiotakMenu) via RuntimeSettingsSetPersistPrefix();
// when it is empty (e.g. Lite build, no panels) save/load are no-ops.
//==============================================================================
static string g_settingsGVPrefix = "";

void RuntimeSettingsSetPersistPrefix(const string prefix)
{
   g_settingsGVPrefix = prefix;
}

int ClampSettingInt(const int v, const int lo, const int hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

void RuntimeSettingsSaveOverrides()
{
   if(StringLen(g_settingsGVPrefix) == 0) return;
   string p = g_settingsGVPrefix + "OV_";
   GlobalVariableSet(p + "ML",  g_maxLevels);
   GlobalVariableSet(p + "TW",  g_triggerWidth);
   GlobalVariableSet(p + "TS",  g_triggerStyle);
   GlobalVariableSet(p + "TC",  g_triggerColor);
   GlobalVariableSet(p + "TL",  g_triggerLabelColor);
   GlobalVariableSet(p + "TT",  g_triggerTransparency);
   GlobalVariableSet(p + "LNW", g_lineWidth);
   GlobalVariableSet(p + "LNS", g_lineStyle);
   GlobalVariableSet(p + "LNC", g_lineColor);
   GlobalVariableSet(p + "LNT", g_lineTransparency);
   GlobalVariableSet(p + "BXW", g_boxBorderWidth);
   GlobalVariableSet(p + "BXS", g_boxBorderStyle);
   GlobalVariableSet(p + "BXC", g_boxBorderColor);
   GlobalVariableSet(p + "BXT", g_boxBorderTransparency);
   GlobalVariableSet(p + "BXR", g_bkTargetR);
   GlobalVariableSet(p + "BXE", g_bkEntryColor);
   GlobalVariableSet(p + "BXL", g_bkStopColor);
   GlobalVariableSet(p + "BXG", g_bkTargetColor);
   GlobalVariableSet(p + "BXI", g_bkShowInfo);
   GlobalVariableSet(p + "BXF", g_boxFillColor);
   GlobalVariableSet(p + "BXFT", g_boxFillTransparency);
   GlobalVariableSet(p + "BXTX", g_bkTextColor);
   GlobalVariableSet(p + "BXTS", g_bkTextSize);
   GlobalVariableSet(p + "BXBO", g_bkBold ? 1 : 0);
   GlobalVariableSet(p + "BXIT", g_bkItalic ? 1 : 0);
   GlobalVariableSet(p + "BXAL", g_bkAlign);
   GlobalVariableSet(p + "BXVA", g_bkVAlign);
   GlobalVariableSet(p + "SW",  g_ssLevelWidth);
   GlobalVariableSet(p + "SS",  g_ssLevelStyle);
   GlobalVariableSet(p + "SC",  g_ssLevelColor);
   GlobalVariableSet(p + "SST", g_ssTransparency);
   GlobalVariableSet(p + "LW",  g_lsLevelWidth);
   GlobalVariableSet(p + "LS",  g_lsLevelStyle);
   GlobalVariableSet(p + "LC",  g_lsLevelColor);
   GlobalVariableSet(p + "LST", g_lsTransparency);
   GlobalVariableSet(p + "LF",  g_lsFirst ? 1 : 0);
   GlobalVariableSet(p + "SM",  g_stepCalculationMode);
   GlobalVariableSet(p + "SL",  g_showLines ? 1 : 0);
   GlobalVariableSet(p + "ST",  g_showTHLevels ? 1 : 0);
   GlobalVariableSet(p + "SR",  g_showStructure ? 1 : 0);
   GlobalVariableSet(p + "S1",  g_showStructureL1 ? 1 : 0);
   GlobalVariableSet(p + "S2",  g_showStructureL2 ? 1 : 0);
   GlobalVariableSet(p + "S3",  g_showStructureL3 ? 1 : 0);
   GlobalVariableSet(p + "S4",  g_showStructureL4 ? 1 : 0);
   GlobalVariableSet(p + "S5",  g_showStructureL5 ? 1 : 0);
   GlobalVariableSet(p + "MP",  g_showMidpointLine ? 1 : 0);
   GlobalVariableSet(p + "ZO",  g_showMidZones ? 1 : 0);
   GlobalVariableSet(p + "MZ",  g_midZoneStyle);
   GlobalVariableSet(p + "ZT",  g_midZoneTransparency);
   GlobalVariableSet(p + "ZH",  g_midZoneHeightPercent);
   GlobalVariableSet(p + "ZB",  g_midZoneBorderStyle);
   GlobalVariableSet(p + "ZW",  g_midZoneBorderWidth);
   GlobalVariableSet(p + "PD",  g_showPipDistanceLabels ? 1 : 0);
   GlobalVariableSet(p + "AL",  g_showATRLabels ? 1 : 0);
   GlobalVariableSet(p + "A1",  g_showATRTargets ? 1 : 0);
   GlobalVariableSet(p + "A2",  g_showATRTradeLabels ? 1 : 0);
   GlobalVariableSet(p + "A3",  g_showATRTradeSLLabels ? 1 : 0);
   GlobalVariableSet(p + "A4",  g_showATRTradeTPLabels ? 1 : 0);
   GlobalVariableSet(p + "AG",  g_atrLabelRowGap);
   GlobalVariableSet(p + "TH",  g_showTHLabels ? 1 : 0);
   GlobalVariableSet(p + "TF",  g_showFractalTHs ? 1 : 0);
   GlobalVariableSet(p + "TS2", g_showStandardTHs ? 1 : 0);
   GlobalVariableSet(p + "TG",  g_showTHTargets ? 1 : 0);
   GlobalVariableSet(p + "TB",  g_thLabelsMarginBottom);
   GlobalVariableSet(p + "E3",  g_enableTH3Tool ? 1 : 0);
   GlobalVariableSet(p + "D3",  g_th3DrawingMode);
   GlobalVariableSet(p + "B3",  g_th3BaseStepPercent);
   GlobalVariableSet(p + "W3",  g_th3Width);
   GlobalVariableSet(p + "Y3",  g_th3Style);
   GlobalVariableSet(p + "C3",  g_th3Color);
   GlobalVariableSet(p + "P3",  g_th3PipTextColor);
   GlobalVariableSet(p + "L3",  g_showTH3Labels ? 1 : 0);
   GlobalVariableSet(p + "CW",  g_customPriceLevelWidth);
   GlobalVariableSet(p + "CC",  g_customPriceLevelColor);
   GlobalVariableSet(p + "CPT", g_customPriceTransparency);
   GlobalVariableSet(p + "MG",  g_enableMagnet ? 1 : 0);
   GlobalVariableSet(p + "MP2", g_magnetSensitivityPips);
   GlobalVariableSet(p + "FM",  g_factorMode);
   GlobalVariableSet(p + "FD",  g_factorDisplayMode);
   GlobalVariableSet(p + "FB",  g_factorAutoBasis);
   GlobalVariableSet(p + "FV",  g_factorValue);
   GlobalVariableSet(p + "FC",  g_factorLevelColor);
   GlobalVariableSet(p + "FCT", g_factorTransparency);
   GlobalVariableSet(p + "FY",  g_factorLevelStyle);
   GlobalVariableSet(p + "FW",  g_factorLevelWidth);
   GlobalVariableSet(p + "CM",  g_comboMode);
   GlobalVariableSet(p + "CP",  g_comboPreset);
   GlobalVariableSet(p + "C1T", g_comboComp1TF);
   GlobalVariableSet(p + "C1S", g_comboComp1Step);
   GlobalVariableSet(p + "CO1", g_comboOp1);
   GlobalVariableSet(p + "C2E", g_comboComp2Enabled ? 1 : 0);
   GlobalVariableSet(p + "C2T", g_comboComp2TF);
   GlobalVariableSet(p + "C2S", g_comboComp2Step);
   GlobalVariablesFlush();
}

void RuntimeSettingsLoadOverrides()
{
   if(StringLen(g_settingsGVPrefix) == 0) return;
   string p = g_settingsGVPrefix + "OV_";
   if(GlobalVariableCheck(p + "ML"))  g_maxLevels = ClampSettingInt((int)GlobalVariableGet(p + "ML"), 1, 500);
   if(GlobalVariableCheck(p + "TW"))  g_triggerWidth = ClampSettingInt((int)GlobalVariableGet(p + "TW"), 1, 5);
   if(GlobalVariableCheck(p + "TS"))  g_triggerStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "TS"), 0, 4);
   if(GlobalVariableCheck(p + "TC"))  g_triggerColor = (color)(int)GlobalVariableGet(p + "TC");
   if(GlobalVariableCheck(p + "TL"))  g_triggerLabelColor = (color)(int)GlobalVariableGet(p + "TL");
   if(GlobalVariableCheck(p + "TT"))  g_triggerTransparency = ClampSettingInt((int)GlobalVariableGet(p + "TT"), 0, 100);
   // [08.4] unified lines — upgrade path: charts customized under the old
   // layout (line look stored in TW/TS/TC/TT) carry their look over when the
   // new LNW/LNS/LNC/LNT keys are absent. g_trigger* above already holds the
   // persisted-or-seeded trigger values at this point.
   if(GlobalVariableCheck(p + "LNW")) g_lineWidth = ClampSettingInt((int)GlobalVariableGet(p + "LNW"), 1, 5);
   else if(GlobalVariableCheck(p + "TW")) g_lineWidth = ClampSettingInt((int)GlobalVariableGet(p + "TW"), 1, 5);
   if(GlobalVariableCheck(p + "LNS")) g_lineStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "LNS"), 0, 4);
   else if(GlobalVariableCheck(p + "TS")) g_lineStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "TS"), 0, 4);
   if(GlobalVariableCheck(p + "LNC")) g_lineColor = (color)(int)GlobalVariableGet(p + "LNC");
   else if(GlobalVariableCheck(p + "TC")) g_lineColor = (color)(int)GlobalVariableGet(p + "TC");
   if(GlobalVariableCheck(p + "LNT")) g_lineTransparency = ClampSettingInt((int)GlobalVariableGet(p + "LNT"), 0, 100);
   else if(GlobalVariableCheck(p + "TT")) g_lineTransparency = ClampSettingInt((int)GlobalVariableGet(p + "TT"), 0, 100);
   // [08.5] base box border (new keys — no legacy layout to upgrade from)
   if(GlobalVariableCheck(p + "BXW")) g_boxBorderWidth = ClampSettingInt((int)GlobalVariableGet(p + "BXW"), 1, 5);
   if(GlobalVariableCheck(p + "BXS")) g_boxBorderStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "BXS"), 0, 4);
   if(GlobalVariableCheck(p + "BXC")) g_boxBorderColor = (color)(int)GlobalVariableGet(p + "BXC");
   if(GlobalVariableCheck(p + "BXT")) g_boxBorderTransparency = ClampSettingInt((int)GlobalVariableGet(p + "BXT"), 0, 100);
   if(GlobalVariableCheck(p + "BXR")) g_bkTargetR = ClampSettingInt((int)GlobalVariableGet(p + "BXR"), 1, 4);
   if(GlobalVariableCheck(p + "BXE")) g_bkEntryColor = (color)(int)GlobalVariableGet(p + "BXE");
   if(GlobalVariableCheck(p + "BXL")) g_bkStopColor = (color)(int)GlobalVariableGet(p + "BXL");
   if(GlobalVariableCheck(p + "BXG")) g_bkTargetColor = (color)(int)GlobalVariableGet(p + "BXG");
   if(GlobalVariableCheck(p + "BXI")) g_bkShowInfo = ClampSettingInt((int)GlobalVariableGet(p + "BXI"), 0, 1);
   if(GlobalVariableCheck(p + "BXF")) g_boxFillColor = (color)(int)GlobalVariableGet(p + "BXF");
   if(GlobalVariableCheck(p + "BXFT")) g_boxFillTransparency = ClampSettingInt((int)GlobalVariableGet(p + "BXFT"), 0, 100);
   if(GlobalVariableCheck(p + "BXTX")) g_bkTextColor = (color)(int)GlobalVariableGet(p + "BXTX");
   if(GlobalVariableCheck(p + "BXTS")) g_bkTextSize = ClampSettingInt((int)GlobalVariableGet(p + "BXTS"), 8, 24);
   if(GlobalVariableCheck(p + "BXBO")) g_bkBold = (GlobalVariableGet(p + "BXBO") > 0.5);
   if(GlobalVariableCheck(p + "BXIT")) g_bkItalic = (GlobalVariableGet(p + "BXIT") > 0.5);
   if(GlobalVariableCheck(p + "BXAL")) g_bkAlign = ClampSettingInt((int)GlobalVariableGet(p + "BXAL"), 0, 2);
   if(GlobalVariableCheck(p + "BXVA")) g_bkVAlign = ClampSettingInt((int)GlobalVariableGet(p + "BXVA"), 0, 2);
   if(GlobalVariableCheck(p + "SW"))  g_ssLevelWidth = ClampSettingInt((int)GlobalVariableGet(p + "SW"), 1, 5);
   if(GlobalVariableCheck(p + "SS"))  g_ssLevelStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "SS"), 0, 4);
   if(GlobalVariableCheck(p + "SC"))  g_ssLevelColor = (color)(int)GlobalVariableGet(p + "SC");
   if(GlobalVariableCheck(p + "SST")) g_ssTransparency = ClampSettingInt((int)GlobalVariableGet(p + "SST"), 0, 100);
   if(GlobalVariableCheck(p + "LW"))  g_lsLevelWidth = ClampSettingInt((int)GlobalVariableGet(p + "LW"), 1, 5);
   if(GlobalVariableCheck(p + "LS"))  g_lsLevelStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "LS"), 0, 4);
   if(GlobalVariableCheck(p + "LC"))  g_lsLevelColor = (color)(int)GlobalVariableGet(p + "LC");
   if(GlobalVariableCheck(p + "LST")) g_lsTransparency = ClampSettingInt((int)GlobalVariableGet(p + "LST"), 0, 100);
   if(GlobalVariableCheck(p + "LF"))  g_lsFirst = (GlobalVariableGet(p + "LF") > 0.5);
   if(GlobalVariableCheck(p + "SM"))  g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)ClampSettingInt((int)GlobalVariableGet(p + "SM"), 0, 3);
   if(GlobalVariableCheck(p + "SL"))  g_showLines = (GlobalVariableGet(p + "SL") > 0.5);
   if(GlobalVariableCheck(p + "ST"))  g_showTHLevels = (GlobalVariableGet(p + "ST") > 0.5);
   if(GlobalVariableCheck(p + "SR"))  g_showStructure = (GlobalVariableGet(p + "SR") > 0.5);
   if(GlobalVariableCheck(p + "S1"))  g_showStructureL1 = (GlobalVariableGet(p + "S1") > 0.5);
   if(GlobalVariableCheck(p + "S2"))  g_showStructureL2 = (GlobalVariableGet(p + "S2") > 0.5);
   if(GlobalVariableCheck(p + "S3"))  g_showStructureL3 = (GlobalVariableGet(p + "S3") > 0.5);
   if(GlobalVariableCheck(p + "S4"))  g_showStructureL4 = (GlobalVariableGet(p + "S4") > 0.5);
   if(GlobalVariableCheck(p + "S5"))  g_showStructureL5 = (GlobalVariableGet(p + "S5") > 0.5);
   if(GlobalVariableCheck(p + "MP"))  g_showMidpointLine = (GlobalVariableGet(p + "MP") > 0.5);
   if(GlobalVariableCheck(p + "ZO"))  g_showMidZones = (GlobalVariableGet(p + "ZO") > 0.5);
   if(GlobalVariableCheck(p + "MZ"))  g_midZoneStyle = (ENUM_ZONE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "MZ"), 0, 2);
   if(GlobalVariableCheck(p + "ZT"))  g_midZoneTransparency = ClampSettingInt((int)GlobalVariableGet(p + "ZT"), 0, 100);
   if(GlobalVariableCheck(p + "ZH"))  g_midZoneHeightPercent = ClampSettingInt((int)GlobalVariableGet(p + "ZH"), 1, 100);
   if(GlobalVariableCheck(p + "ZB"))  g_midZoneBorderStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "ZB"), 0, 4);
   if(GlobalVariableCheck(p + "ZW"))  g_midZoneBorderWidth = ClampSettingInt((int)GlobalVariableGet(p + "ZW"), 1, 5);
   if(GlobalVariableCheck(p + "PD"))  g_showPipDistanceLabels = (GlobalVariableGet(p + "PD") > 0.5);
   if(GlobalVariableCheck(p + "AL"))  g_showATRLabels = (GlobalVariableGet(p + "AL") > 0.5);
   if(GlobalVariableCheck(p + "A1"))  g_showATRTargets = (GlobalVariableGet(p + "A1") > 0.5);
   if(GlobalVariableCheck(p + "A2"))  g_showATRTradeLabels = (GlobalVariableGet(p + "A2") > 0.5);
   if(GlobalVariableCheck(p + "A3"))  g_showATRTradeSLLabels = (GlobalVariableGet(p + "A3") > 0.5);
   if(GlobalVariableCheck(p + "A4"))  g_showATRTradeTPLabels = (GlobalVariableGet(p + "A4") > 0.5);
   if(GlobalVariableCheck(p + "AG"))  g_atrLabelRowGap = ClampSettingInt((int)GlobalVariableGet(p + "AG"), 1, 60);
   if(GlobalVariableCheck(p + "TH"))  g_showTHLabels = (GlobalVariableGet(p + "TH") > 0.5);
   if(GlobalVariableCheck(p + "TF"))  g_showFractalTHs = (GlobalVariableGet(p + "TF") > 0.5);
   if(GlobalVariableCheck(p + "TS2")) g_showStandardTHs = (GlobalVariableGet(p + "TS2") > 0.5);
   if(GlobalVariableCheck(p + "TG"))  g_showTHTargets = (GlobalVariableGet(p + "TG") > 0.5);
   if(GlobalVariableCheck(p + "TB"))  g_thLabelsMarginBottom = ClampSettingInt((int)GlobalVariableGet(p + "TB"), 10, 200);
   if(GlobalVariableCheck(p + "E3"))  g_enableTH3Tool = (GlobalVariableGet(p + "E3") > 0.5);
   if(GlobalVariableCheck(p + "D3"))  g_th3DrawingMode = (ENUM_TH3_DRAWING_MODE)ClampSettingInt((int)GlobalVariableGet(p + "D3"), 0, 1);
   if(GlobalVariableCheck(p + "B3"))  g_th3BaseStepPercent = MathMax(0.5, GlobalVariableGet(p + "B3"));
   if(GlobalVariableCheck(p + "W3"))  g_th3Width = ClampSettingInt((int)GlobalVariableGet(p + "W3"), 1, 5);
   if(GlobalVariableCheck(p + "Y3"))  g_th3Style = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "Y3"), 0, 4);
   if(GlobalVariableCheck(p + "C3"))  g_th3Color = (color)(int)GlobalVariableGet(p + "C3");
   if(GlobalVariableCheck(p + "P3"))  g_th3PipTextColor = (color)(int)GlobalVariableGet(p + "P3");
   if(GlobalVariableCheck(p + "L3"))  g_showTH3Labels = (GlobalVariableGet(p + "L3") > 0.5);
   if(GlobalVariableCheck(p + "CW"))  g_customPriceLevelWidth = ClampSettingInt((int)GlobalVariableGet(p + "CW"), 1, 5);
   if(GlobalVariableCheck(p + "CC"))  g_customPriceLevelColor = (color)(int)GlobalVariableGet(p + "CC");
   if(GlobalVariableCheck(p + "CPT")) g_customPriceTransparency = ClampSettingInt((int)GlobalVariableGet(p + "CPT"), 0, 100);
   if(GlobalVariableCheck(p + "MG"))  g_enableMagnet = (GlobalVariableGet(p + "MG") > 0.5);
   if(GlobalVariableCheck(p + "MP2")) g_magnetSensitivityPips = ClampSettingInt((int)GlobalVariableGet(p + "MP2"), 0, 100);
   if(GlobalVariableCheck(p + "FM"))  g_factorMode = (ENUM_FACTOR_MODE)ClampSettingInt((int)GlobalVariableGet(p + "FM"), 0, 1);
   if(GlobalVariableCheck(p + "FD"))  g_factorDisplayMode = (ENUM_FACTOR_DISPLAY_MODE)ClampSettingInt((int)GlobalVariableGet(p + "FD"), 0, 1);
   if(GlobalVariableCheck(p + "FB"))  g_factorAutoBasis = (ENUM_FACTOR_AUTO_BASIS)ClampSettingInt((int)GlobalVariableGet(p + "FB"), 0, 7);
   if(GlobalVariableCheck(p + "FV"))  g_factorValue = MathMax(0.0, GlobalVariableGet(p + "FV"));
   if(GlobalVariableCheck(p + "FC"))  g_factorLevelColor = (color)(int)GlobalVariableGet(p + "FC");
   if(GlobalVariableCheck(p + "FCT")) g_factorTransparency = ClampSettingInt((int)GlobalVariableGet(p + "FCT"), 0, 100);
   if(GlobalVariableCheck(p + "FY"))  g_factorLevelStyle = (ENUM_LINE_STYLE)ClampSettingInt((int)GlobalVariableGet(p + "FY"), 0, 4);
   if(GlobalVariableCheck(p + "FW"))  g_factorLevelWidth = ClampSettingInt((int)GlobalVariableGet(p + "FW"), 1, 5);
   if(GlobalVariableCheck(p + "CM"))  g_comboMode = (ENUM_COMBO_MODE)ClampSettingInt((int)GlobalVariableGet(p + "CM"), 0, 1);
   if(GlobalVariableCheck(p + "CP"))  g_comboPreset = (ENUM_COMBO_PRESET)ClampSettingInt((int)GlobalVariableGet(p + "CP"), 0, 7);
   if(GlobalVariableCheck(p + "C1T")) g_comboComp1TF = (ENUM_COMBO_TIMEFRAME_TYPE)ClampSettingInt((int)GlobalVariableGet(p + "C1T"), 0, 3);
   if(GlobalVariableCheck(p + "C1S")) g_comboComp1Step = (ENUM_COMBO_STEP_TYPE)ClampSettingInt((int)GlobalVariableGet(p + "C1S"), 0, 3);
   if(GlobalVariableCheck(p + "CO1")) g_comboOp1 = (ENUM_COMBO_OPERATION)ClampSettingInt((int)GlobalVariableGet(p + "CO1"), 0, 6);
   if(GlobalVariableCheck(p + "C2E")) g_comboComp2Enabled = (GlobalVariableGet(p + "C2E") > 0.5);
   if(GlobalVariableCheck(p + "C2T")) g_comboComp2TF = (ENUM_COMBO_TIMEFRAME_TYPE)ClampSettingInt((int)GlobalVariableGet(p + "C2T"), 0, 3);
   if(GlobalVariableCheck(p + "C2S")) g_comboComp2Step = (ENUM_COMBO_STEP_TYPE)ClampSettingInt((int)GlobalVariableGet(p + "C2S"), 0, 3);
}

//--- throttled saver (panel/palette drags fire per mouse-move)
void RuntimeSettingsSaveOverridesThrottled()
{
   static uint s_LastSave = 0;
   uint now = GetTickCount();
   if(now - s_LastSave < 500) return;
   s_LastSave = now;
   RuntimeSettingsSaveOverrides();
}

//==============================================================================
// EFFECTIVE TRIGGER ZONE COLOR — input color blended toward the chart
// background by the transparency setting. Reads the RUNTIME copies so the
// panels' color/transparency edits reach the renderer immediately.
// NOTE: since the unified-LINES split this feeds ONLY the trigger zones;
// pipeline lines use GetLineRenderColor() below and never follow the T switch.
//==============================================================================
color GetTriggerRenderColor()
{
    static color s_cachedBase = clrNONE;
    static int s_cachedTransparency = -1;
    static color s_cachedBackground = clrNONE;
    static color s_cachedRenderColor = clrNONE;

    int t = (int)MathMax(0, MathMin(100, g_triggerTransparency));
    // Stronger visual fade for line objects:
    // 60 -> 84, 50 -> 75, 30 -> 51
    int tVis = 100 - ((100 - t) * (100 - t)) / 100;
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

    if(s_cachedBase == g_triggerColor && s_cachedTransparency == tVis && s_cachedBackground == bg) {
        return s_cachedRenderColor;
    }

    s_cachedBase = g_triggerColor;
    s_cachedTransparency = tVis;
    s_cachedBackground = bg;

    if(tVis <= 0) {
        s_cachedRenderColor = g_triggerColor;
        return s_cachedRenderColor;
    }

    if(tVis >= 100) {
        s_cachedRenderColor = bg;
        return s_cachedRenderColor;
    }

    int fr = ((int)g_triggerColor) & 0xFF;
    int fg = (((int)g_triggerColor) >> 8) & 0xFF;
    int fb = (((int)g_triggerColor) >> 16) & 0xFF;

    int br = ((int)bg) & 0xFF;
    int bgc = (((int)bg) >> 8) & 0xFF;
    int bb = (((int)bg) >> 16) & 0xFF;

    int outR = (fr * (100 - tVis) + br * tVis) / 100;
    int outG = (fg * (100 - tVis) + bgc * tVis) / 100;
    int outB = (fb * (100 - tVis) + bb * tVis) / 100;

    s_cachedRenderColor = (color)(outR | (outG << 8) | (outB << 16));
    return s_cachedRenderColor;
}

//==============================================================================
// EFFECTIVE UNIFIED LINE COLOR — [08.4] line color blended toward the chart
// background by the [08.4] line transparency. SINGLE appearance for ALL
// pipeline lines (trigger-subdivision + structure-interval). Independent of
// the trigger overlay switch (T gates only the trigger ZONES in RenderZones).
//==============================================================================
color GetLineRenderColor()
{
    static color s_cachedBase = clrNONE;
    static int s_cachedTransparency = -1;
    static color s_cachedBackground = clrNONE;
    static color s_cachedRenderColor = clrNONE;

    int t = (int)MathMax(0, MathMin(100, g_lineTransparency));
    // Stronger visual fade for line objects:
    // 60 -> 84, 50 -> 75, 30 -> 51
    int tVis = 100 - ((100 - t) * (100 - t)) / 100;
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

    if(s_cachedBase == g_lineColor && s_cachedTransparency == tVis && s_cachedBackground == bg) {
        return s_cachedRenderColor;
    }

    s_cachedBase = g_lineColor;
    s_cachedTransparency = tVis;
    s_cachedBackground = bg;

    if(tVis <= 0) {
        s_cachedRenderColor = g_lineColor;
        return s_cachedRenderColor;
    }

    if(tVis >= 100) {
        s_cachedRenderColor = bg;
        return s_cachedRenderColor;
    }

    int fr = ((int)g_lineColor) & 0xFF;
    int fg = (((int)g_lineColor) >> 8) & 0xFF;
    int fb = (((int)g_lineColor) >> 16) & 0xFF;

    int br = ((int)bg) & 0xFF;
    int bgc = (((int)bg) >> 8) & 0xFF;
    int bb = (((int)bg) >> 16) & 0xFF;

    int outR = (fr * (100 - tVis) + br * tVis) / 100;
    int outG = (fg * (100 - tVis) + bgc * tVis) / 100;
    int outB = (fb * (100 - tVis) + bb * tVis) / 100;

    s_cachedRenderColor = (color)(outR | (outG << 8) | (outB << 16));
    return s_cachedRenderColor;
}

//==============================================================================
// PER-TARGET TRANSPARENCY — every COLOR row's target is adjustable from the
// palette footer TR track / mixer (PaletteKindTransparency). Same visual
// fade curve as trigger/lines, same per-target static cache discipline:
// recompute ONLY when base, transparency or chart background changes, so
// per-frame draw calls cost one syscall + three integer compares.
// Stores default to 0 (solid) — existing charts look identical until the
// user touches TR. Persisted via OV_SST/LST/CPT/FCT (no migration: new keys).
//==============================================================================
int TransparencyVisual(const int t)
{
    int tc = (int)MathMax(0, MathMin(100, t));
    // Stronger visual fade for line objects: 60 -> 84, 50 -> 75, 30 -> 51
    return 100 - ((100 - tc) * (100 - tc)) / 100;
}

color BlendColorTowardsBG(const color base, const int tVis, const color bg)
{
    if(tVis <= 0) return base;
    if(tVis >= 100) return bg;
    int fr = ((int)base) & 0xFF;
    int fg = (((int)base) >> 8) & 0xFF;
    int fb = (((int)base) >> 16) & 0xFF;
    int br = ((int)bg) & 0xFF;
    int bgc = (((int)bg) >> 8) & 0xFF;
    int bb = (((int)bg) >> 16) & 0xFF;
    int outR = (fr * (100 - tVis) + br * tVis) / 100;
    int outG = (fg * (100 - tVis) + bgc * tVis) / 100;
    int outB = (fb * (100 - tVis) + bb * tVis) / 100;
    return (color)(outR | (outG << 8) | (outB << 16));
}

color GetSSRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_ssTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_ssLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_ssLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_ssLevelColor, tVis, bg);
    return s_out;
}

color GetLSRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_lsTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_lsLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_lsLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_lsLevelColor, tVis, bg);
    return s_out;
}

color GetCustomPriceRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_customPriceTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_customPriceLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_customPriceLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_customPriceLevelColor, tVis, bg);
    return s_out;
}

color GetFactorRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_factorTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_factorLevelColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_factorLevelColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_factorLevelColor, tVis, bg);
    return s_out;
}

color GetBoxBorderRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_boxBorderTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_boxBorderColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_boxBorderColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_boxBorderColor, tVis, bg);
    return s_out;
}

// EFFECTIVE BOX FILL — TV-parity 2026-09-07 (Style tab bucket). Same cache
// discipline as the border helper. 100% = chart background (invisible).
color GetBoxFillRenderColor()
{
    static color s_b = clrNONE; static int s_t = -1;
    static color s_bg = clrNONE; static color s_out = clrNONE;
    int tVis = TransparencyVisual(g_boxFillTransparency);
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_b == g_boxFillColor && s_t == tVis && s_bg == bg) return s_out;
    s_b = g_boxFillColor; s_t = tVis; s_bg = bg;
    s_out = BlendColorTowardsBG(g_boxFillColor, tVis, bg);
    return s_out;
}
// Fill visible on chart? (transparency < 100). The BOX rect is the fill layer:
// FILL true + fill color when visible, bg + FILL false when invisible (the old
// hollow look — pre-fill charts stay pixel-identical).
bool BoxFillVisible() { return (ClampSettingInt(g_boxFillTransparency, 0, 100) < 100); }

// EFFECTIVE USER-TEXT COLOR — factory white means Auto: pure-white text on a
// light chart is invisible, so it renders dark brown there (same luminance
// gate as the INFO label); any explicit pick (incl. white on dark) is honored
// untouched. Cached like the other render getters.
color GetBKTextRenderColor()
{
    static color s_c = clrNONE; static color s_bg = clrNONE; static color s_out = clrNONE;
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    if(s_c == g_bkTextColor && s_bg == bg) return s_out;
    s_c = g_bkTextColor; s_bg = bg;
    s_out = g_bkTextColor;
    if(g_bkTextColor == C'255,255,255')
    {
       int lum = ((((int)bg) & 0xFF) * 299 + ((((int)bg) >> 8) & 0xFF) * 587 +
                  ((((int)bg) >> 16) & 0xFF) * 114) / 1000;
       if(lum > 128) s_out = C'150,70,0';
    }
    return s_out;
}

// User-text font string from the Bold/Italic mirrors ("Arial" + suffixes).
string BKTextFont()
{
   string f = "Arial";
   if(g_bkBold && g_bkItalic) return f + " Bold Italic";
   if(g_bkBold) return f + " Bold";
   if(g_bkItalic) return f + " Italic";
   return f;
}

#endif // RUNTIME_SETTINGS_MQH
