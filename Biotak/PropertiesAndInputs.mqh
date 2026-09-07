  #ifndef PROPERTIES_AND_INPUTS_MQH
#define PROPERTIES_AND_INPUTS_MQH

#property copyright "  Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link "@biotak"
#property version "3.10"
#property strict
#property indicator_chart_window
#property description "Version 3.10 - GOLD: Post-Audit - All Critical Issues Fixed"

#include "ConstantsAndEnums.mqh"

//==============================================================================
// VISUAL ALIGNMENT NOTE:
// All defaults below match MT5 PropertiesAndInputs.mqh so the chart output is
// visually identical between MT4 and MT5. MT4-specific inputs that do not exist
// in MT5 (inpCalculationBasis, inpInitialX/Y, inpLabelSpacing) are kept for
// backward compatibility with existing MT4 users' saved settings. The single
// inpMaxLevels input is the source for the number of levels on both sides and
// is used consistently by drawing and alert checks.

input group "01) CALCULATION - MODE & CORE"
input string S3 = "[01] CALCULATION / MODE & CORE";
input int inpMaxLevels = 144;                                    // Max Levels per side (single source)
input ENUM_STEP_CALCULATION_MODE inpStepCalculationMode = TH_STEP;
input ENUM_CALCULATION_BASIS inpCalculationBasis = CALC_BASIS_TH; // MT4-only: kept for compat
input ENUM_APPLIED_PRICE inpTHPriceType = PRICE_CLOSE;
input bool inpUseDynamicTradingDay = true;
input bool inpBasePriceThresholdEnabled = true;
input double inpBasePriceThresholdPercent = 0.066;
input ENUM_ADAPTIVE_MODE inpAdaptiveMode = ADAPTIVE_FRACTAL;      // Adaptive Mode (v3.11: default changed to FRACTAL)
input double inpAdaptiveBlendRatio = 0.5;                        // Adaptive Blend Ratio
input int inpAdaptiveSmoothingPeriod = 10;                       // Adaptive Smoothing (v3.11: reduced to 10 for better response)
input ENUM_FRACTAL_JUMP_STRATEGY inpFractalJumpStrategy = JUMP_AGGRESSIVE; // Fractal Jump Strategy

input group "02) BASE PRICE - ANCHOR"
input string S4 = "[02] BASE PRICE / ANCHOR";
input ENUM_TH_START_POINT_TYPE inpTHStartPointType = TH_START_POINT_PREVIOUS_CLOSE;
input double inpCustomTHStartPrice = 0.0;          // Custom Start Price
input color inpCustomPriceLevelColor = clrDodgerBlue; // Custom Line Color
input int inpCustomPriceLevelWidth = 1;            // Custom Line Width
input bool inpEnableMagnet = true;                 // Enable Magnet
input int inpMagnetSensitivityPips = 10;           // Magnet Sensitivity (pips)

input group "03) DISPLAY - VISIBILITY"
input string S1 = "[03] DISPLAY / VISIBILITY";
input bool inpShowLines = false;              // Show level lines (default OFF — zones/structure only)
input bool inpShowTHLevels = true;
input bool inpShowTHLabels = false;
input bool inpShowTHTargets = true;              // Show TH Targets
input bool inpShowPipDistanceLabels = true;
input bool inpShowMidpointLine = true;
input bool inpShowTimeframeInLabels = true;
input bool inpShowFractalTHs = false;
input bool inpShowStandardTHs = false;
input bool inpShowATRLabels = false;              // Show ATR Labels
input bool inpShowATRTargets = true;             // Show ATR Targets
input bool inpShowATRTradeLabels = true;         // Master switch for ATR trade labels
input bool inpShowATRTradeSLLabels = true;       // Show SL/HuntSL/EngSL labels
input bool inpShowATRTradeTPLabels = true;       // Show TP1/TP2/TP3 labels
input int inpATRTradeLabelRowGap = 10;           // Compact vertical gap between ATR trade rows

input group "04) STYLE - SS/LS STEP"
input string S6 = "[04] STYLE / SS-LS STEP";
input bool inpLSFirst = true; // Default SS/LS order; double-click Custom Price for a quick override
input color inpSSLevelColor = clrGoldenrod;
input color inpLSLevelColor = clrOrange;
input ENUM_LINE_STYLE inpSSLevelStyle = STYLE_DOT;
input ENUM_LINE_STYLE inpLSLevelStyle = STYLE_DOT;
input int inpSSLevelWidth = 1;
input int inpLSLevelWidth = 1;

input group "05) STYLE - COMBO STEP"
input string S8 = "[05] STYLE / COMBO STEP";
input ENUM_COMBO_MODE inpComboMode = COMBO_MODE_PRESET;
input ENUM_COMBO_PRESET inpComboPreset = COMBO_PRESET_BALANCED_MEDIUM;
input color inpComboLevelColor = clrMagenta;
input ENUM_LINE_STYLE inpComboLevelStyle = STYLE_DOT;
input int inpComboLevelWidth = 1;
input ENUM_COMBO_TIMEFRAME_TYPE inpComboComp1TF = COMBO_TF_PATTERN; // Advanced: Component 1 timeframe
input ENUM_COMBO_STEP_TYPE inpComboComp1Step = COMBO_STEP_TH;       // Advanced: Component 1 step
input ENUM_COMBO_OPERATION inpComboOp1 = COMBO_OP_AVERAGE;          // Advanced: operation
input bool inpComboComp2Enabled = true;                             // Advanced: enable Component 2
input ENUM_COMBO_TIMEFRAME_TYPE inpComboComp2TF = COMBO_TF_TRIGGER; // Advanced: Component 2 timeframe
input ENUM_COMBO_STEP_TYPE inpComboComp2Step = COMBO_STEP_TH;       // Advanced: Component 2 step
input bool inpComboContinuousFractal = false; // Exact continuous fractal levels for Trigger/Sub (fixes M30 collapse). Default = legacy nearest-standard-TF mapping.

input group "06) STYLE - FACTOR STEP"
input string S9 = "[06] STYLE / FACTOR STEP";
input ENUM_FACTOR_MODE inpFactorMode = FACTOR_MODE_AUTO;
input ENUM_FACTOR_DISPLAY_MODE inpFactorDisplayMode = FACTOR_DISPLAY_DIRECT; // DIRECT = Step Size, CLASSIC = Factor Value
input ENUM_FACTOR_AUTO_BASIS inpFactorAutoBasis = FACTOR_BASIS_CONTROL;
input double inpFactorValue = 50.0;
input double inpFactorAdjustStep = 0.1;
input color inpFactorLevelColor = C'0,100,0';
input ENUM_LINE_STYLE inpFactorLevelStyle = STYLE_DOT;
input int inpFactorLevelWidth = 1;

#ifndef BUILD_LITE
input group "06.1) FACTOR - HARMONIC"
input string S11 = "[06.1] FACTOR / HARMONIC";
input bool inpEnableHarmonicPattern = false;
input double inpHarmonicRatio = 1.333;
input color inpHarmonicBaseColor = C'0,0,128';
input color inpHarmonicLargeColor = C'220,20,60';
input int inpHarmonicBaseWidth = 1;
input int inpHarmonicLargeWidth = 2;
#endif

input group "07) ZONES - MID"
input string S10 = "[07] ZONES / MID";
input group "07.1) ZONES - ENABLE & TYPE"
input string S10a = "[07.1] ZONES / ENABLE & TYPE";
input bool inpShowMidZones = true;
input ENUM_ZONE_STYLE inpMidZoneStyle = ZONE_STYLE_BOX_FILLED;
input group "07.2) ZONES - VISUAL DENSITY"
input string S10b = "[07.2] ZONES / VISUAL DENSITY";
input int inpMidZoneTransparency = 50;
input double inpMidZoneHeightPercent = 33.0;
input ENUM_LINE_STYLE inpMidZoneBorderStyle = STYLE_SOLID; // Box border line style (Solid/Dash/Dot/...)
input int inpMidZoneBorderWidth = 1;                       // Box border width (1-5)

input group "08) LEVEL STYLE - LINES (ALL)"
input string S16 = "[08] LEVEL STYLE / LINES";
input group "08.1) LINES - BASE & TRIGGER"
input string S15b = "[08.1] LINES / BASE & TRIGGER";
input ENUM_LINE_STYLE inpTHLineStyle = STYLE_DOT;  // Base Line Style
input color inpTriggerColor = clrBlack;            // Trigger Zone Color
input ENUM_LINE_STYLE inpTriggerStyle = STYLE_DOT; // (legacy) Trigger Line Style — lines moved to [08.4]
input int inpTriggerWidth = 1;                     // (legacy) Trigger Line Width — lines moved to [08.4]

input group "08.2) LINES - STRUCTURE L1-L5"
input string S16b = "[08.2] LINES / STRUCTURE L1-L5";
input color inpStructureL1Color = C'100,149,237';     // L1 Line Color
input ENUM_LINE_STYLE inpStructureL1Style = STYLE_DOT; // L1 Line Style
input int inpStructureL1Width = 1;                    // L1 Line Width
input color inpStructureL2Color = C'60,179,113';      // L2 Line Color
input ENUM_LINE_STYLE inpStructureL2Style = STYLE_DOT; // L2 Line Style
input int inpStructureL2Width = 1;                    // L2 Line Width
input color inpStructureL3Color = C'138,43,226';      // L3 Line Color
input ENUM_LINE_STYLE inpStructureL3Style = STYLE_DOT; // L3 Line Style
input int inpStructureL3Width = 1;                    // L3 Line Width
input color inpStructureL4Color = C'255,140,0';       // L4 Line Color
input ENUM_LINE_STYLE inpStructureL4Style = STYLE_DOT; // L4 Line Style
input int inpStructureL4Width = 1;                    // L4 Line Width
input color inpStructureL5Color = C'205,92,92';       // L5 Line Color
input ENUM_LINE_STYLE inpStructureL5Style = STYLE_DOT; // L5 Line Style
input int inpStructureL5Width = 1;                    // L5 Line Width

input group "08.3) LINES - HIGH/LOW"
input string S14a = "[08.3] LINES / HIGH-LOW";
input color inpHighColor = C'220,20,60';  // High Line Color
input color inpLowColor = C'0,0,128';     // Low Line Color
input ENUM_LINE_STYLE inpHighStyle = STYLE_DASHDOT; // High Line Style
input ENUM_LINE_STYLE inpLowStyle = STYLE_DASHDOT;  // Low Line Style
input int inpHighWidth = 1;                         // High Line Width
input int inpLowWidth = 1;                          // Low Line Width

input group "08.4) LINES - UNIFIED"
input string S16d = "[08.4] LINES / UNIFIED";
input color inpLineColor = clrBlack;               // Lines Color (ALL pipeline lines)
input ENUM_LINE_STYLE inpLineStyle = STYLE_DOT;    // Lines Style (ALL pipeline lines)
input int inpLineWidth = 1;                        // Lines Width (ALL pipeline lines)
input int inpLineTransparency = 50;                // Lines Transparency (0=Solid, 100=Invisible)

input group "08.5) BASE BOX - BORDER"
input string S16e = "[08.5] BASE BOX / BORDER";
input color inpBoxBorderColor = C'255,171,0';            // Base Box Border Color (amber, no fill — like MT4)
input ENUM_LINE_STYLE inpBoxBorderStyle = STYLE_SOLID;   // Base Box Border Style
input int inpBoxBorderWidth = 2;                         // Base Box Border Width (1-5)
input int inpBKTargetR = 2;                              // Base Box Target R:R multiple (TP = Entry + R x N)
input color inpBKEntryColor = C'30,144,255';             // Base Box Entry Line Color (dodger blue)
input color inpBKStopColor = C'220,50,50';               // Base Box Stop Line Color (red)
input color inpBKTargetColor = C'46,139,87';             // Base Box Target Line Color (sea green)
input int inpBKShowInfo = 0;                             // Base Box Info Label: 0=Auto (hide after set), 1=Show
input color inpBoxFillColor = C'255,171,0';              // Base Box Fill Color (bucket — TV Style tab)
input color inpBKTextColor = C'255,255,255';             // Base Box Text Color (T button — TV Text tab)
input int inpBKTextSize = 10;                            // Base Box Text Size (TV default 10)
input bool inpBKBold = false;                            // Base Box Text Bold
input bool inpBKItalic = false;                          // Base Box Text Italic
input int inpBKAlign = 2;                                // Base Box Text Align: 0=Left, 1=Center, 2=Right (TV default Right)
input int inpBKVAlign = 1;                               // Base Box Text Vertical: 0=Top, 1=Inside, 2=Bottom (TV Text tab)

input group "09) VISIBILITY - STRUCTURE & TRIGGER"
input string S15 = "[09] VISIBILITY / STRUCTURE & TRIGGER";
input group "09.1) STRUCTURE - MASTER"
input string S16a = "[09.1] STRUCTURE / MASTER";
input bool inpShowStructure = true;                               // Show Structure
input ENUM_STRUCTURE_BASE_MULTIPLIER inpStructureBase = BASE_MULTIPLIER_2; // Structure Base

input group "09.2) STRUCTURE - LEVEL TOGGLES & LABEL COLORS"
input string S16c = "[09.2] STRUCTURE / LEVEL TOGGLES & LABELS";
input bool inpShowStructureL1 = true;                 // L1 Show
input color inpStructureL1LabelColor = C'100,149,237'; // L1 Label Color
input bool inpShowStructureL2 = true;                 // L2 Show
input color inpStructureL2LabelColor = C'60,179,113'; // L2 Label Color
input bool inpShowStructureL3 = true;                 // L3 Show
input color inpStructureL3LabelColor = C'138,43,226'; // L3 Label Color
input bool inpShowStructureL4 = true;                 // L4 Show
input color inpStructureL4LabelColor = C'255,140,0';  // L4 Label Color
input bool inpShowStructureL5 = true;                 // L5 Show
input color inpStructureL5LabelColor = C'205,92,92';  // L5 Label Color

input group "09.3) TRIGGER - ENABLE & LABEL"
input string S15c = "[09.3] TRIGGER / ENABLE & LABEL";
input bool inpShowTrigger = false;       // Show Trigger Levels
input int inpTriggerTransparency = 50;   // Trigger Transparency (0=Solid, 100=Invisible)
input color inpTriggerLabelColor = clrBlack;     // Trigger Label Color

input group "10) HIGH/LOW - TOOLTIPS"
input string S14c = "[10] HIGH-LOW / TOOLTIPS";
input string inpHighLineTooltip = "Historical High"; // High Tooltip
input string inpLowLineTooltip = "Historical Low";   // Low Tooltip

input group "11) DISPLAY - TEXT & FONT"
input string S2 = "[11] DISPLAY / TEXT & FONT";
input string inpFontName = "Arial Bold";         // Font Name (matches MT5)
input int inpFontSize = 8;                       // Font Size

input group "12) DISPLAY - MODE LABEL"
input string S18 = "[12] DISPLAY / MODE LABEL";
input bool inpShowModeChangeLabel = true;
input int inpModeLabelDuration = 5;              // Label Duration (sec, 0=Permanent)
input ENUM_BASE_CORNER inpModeLabelCorner = CORNER_LEFT_UPPER;
input int inpModeLabelXDistance = 15;
input int inpModeLabelYDistance = 25;
input int inpModeLabelFontSize = 12;
input color inpModeLabelColor = clrDarkBlue;

input group "13) ADVANCED - LABEL LAYOUT"
input string S21 = "[13] ADVANCED / LABEL LAYOUT";
input int inpLabelsMarginTop = 30;        // Distance from top of chart
input int inpLabelsMarginLeft = 25;       // Distance from left edge
input int inpLabelsMarginBottom = 25;      // Distance from bottom of chart
input int inpTHLabelsMarginBottom = 40;   // TH labels distance from bottom (bottom-left)
input int inpLabelRowGap = 18;            // Vertical gap between rows
input int inpLabelColumnGap = 50;         // Horizontal gap between columns
input int inpSectionGap = 30;             // Gap between ATR and TH sections
input int inpMaxLabelWidth = 250;

// TH3TOOL-OFF: whole "14) TH3 TOOL" group retired with the tool (was #ifndef BUILD_LITE) —
//#ifndef BUILD_LITE
//input group "14) TH3 TOOL"
//input string S12 = "[14] TH3 TOOL";
//input bool inpEnableTH3Tool = true;
//input ENUM_TH3_DRAWING_MODE inpTH3DrawingMode = TH3_MODE_ABCD;
//input double inpTH3BaseStepPercent = 28.125;
//input color inpTH3Color = clrDarkBlue;            // Visual align MT5: was clrForestGreen
//input color inpTH3PipTextColor = clrDarkBlue;     // Visual align MT5: was clrNavy
//input ENUM_LINE_STYLE inpTH3Style = STYLE_SOLID;
//input int inpTH3Width = 1;
//input bool inpShowTH3Labels = true;
//input ENUM_TH3_LABEL_POSITION inpTH3LabelPosition = TH3_LABEL_END;
//input ENUM_ZONE_STYLE inpTH3ZoneStyle = ZONE_STYLE_BOX_FILLED;
//input color inpTH3ZoneColor = clrNONE;
//input int inpTH3ZoneTransparency = 50;
//input double inpTH3ZoneHeightPercent = 33.0;
//input ENUM_LINE_STYLE inpTH3ZoneBorderStyle = STYLE_DOT;
//input int inpTH3ZoneBorderWidth = 1;
//#endif

// TH3TOOL-OFF: whole "15) AB=CD" group retired with the tool (was #ifndef BUILD_LITE) —
//#ifndef BUILD_LITE
//input group "15) AB=CD"
//input string S13 = "[15] AB=CD";
//input bool inpABCDShowLabels = false;             // Visual align MT5: was true
//input color inpABCDPointColor = clrDarkBlue;      // Visual align MT5: was clrGold
//input double inpABCDLabelOffsetPercent = 20.0;
//input color inpABCDLineColor = clrDarkBlue;       // Visual align MT5: was clrDodgerBlue
//input int inpABCDWidth = 2;
//input bool inpABCDExtendCD = true;
//input ENUM_BASE_CORNER inpABCDInfoCorner = CORNER_LEFT_UPPER;
//input int inpABCDInfoXDistance = 10;
//input int inpABCDInfoYDistance = 20;
//input int inpABCDInfoFontSize = 9;
//input color inpABCDInfoColor = clrDarkBlue;       // Visual align MT5: was clrNavy
//#endif

input group "16) ALERTS"
input string S17 = "[16] ALERTS";
input bool inpEnableHighLowAlerts = false;        // High/Low Alerts
input bool inpEnableTHAlerts = false;             // TH Alerts
input bool inpEnableStructureTHAlerts = false;    // Structure Alerts
input bool inpAlertOnce = true;                   // Once Per Bar
input bool inpPlaySound = true;                   // Play Sound
input string inpAlertSoundFile = "alert.wav";    // Sound File
input bool inpSendNotification = false;           // Push Notification
input bool inpSendEmail = false;                  // Send Email

input group "17) HOTKEYS"
input string S19 = "[17] HOTKEYS";
input string inpHideKey = "F";
input string inpLinesToggleKey = "L";
input string inpLockKey = "G";
// VIEWLOCK-OFF: input string inpViewLockKey = "V";   // View Lock: keep this view across timeframes
input string inpCustomPriceKey = "C";
input string inpTriggerLevelsKey = "T";
input string inpStepModeKey = "E";
// TH3TOOL-OFF:
//#ifndef BUILD_LITE
//input string inpTH3ToolKey = "V";
//#endif
input string inpATRLabelsKey = "A";        // Toggle ATR labels on/off
input string inpTHLabelsKey = "S";          // Toggle TH labels on/off
input string inpShowStatusKey = "W";        // Show current mode status
input string inpResetKey = "Q";

input group "18) ADVANCED - OBJECTS"
input string S20 = "[18] ADVANCED / OBJECTS";
input string inpObjectPrefix = "THLevels";
input ENUM_LINE_OBJECT_TYPE inpTHLineObjectType = LINE_OBJECT_HORIZONTAL_LINE;
input ENUM_LABEL_CORNER_POSITION inpLabelCornerPosition = LABEL_CORNER_LEFT_TOP; // Visual align MT5: was LEFT_BOTTOM
input ENUM_LABEL_ARRANGEMENT inpLabelArrangement = LABEL_ARRANGEMENT_HORIZONTAL;
input int inpInitialX = 20;                 // MT4-only: kept for compat
input int inpInitialY = 10;                 // MT4-only: kept for compat
input int inpLabelSpacing = 18;             // MT4-only: kept for compat

input group "19) ADVANCED - HISTORY & LOG"
input string S22 = "[19] ADVANCED / HISTORY & LOG";
input ENUM_TIMEFRAMES inpHistoricalTimeframe = PERIOD_MN1;
input int inpHistoricalPeriods = 0;
input ENUM_LOG_LEVEL inpLogLevel = LOG_LEVEL_WARN;   // Minimum log level (TRACE=all, OFF=none)

//==============================================================================
// This module ONLY declares the user-facing `input` parameters.
// The panel-editable subset (SS/LS, trigger, factor, TH3, visibility ...) is
// mirrored into runtime copies in RuntimeSettings.mqh, which seeds them from
// these inputs at attach (RuntimeSettingsInit) — so both the MT4 Inputs dialog
// and the on-chart panels drive the same settings. Derived render helpers
// (e.g. GetTriggerRenderColor) also live in RuntimeSettings.mqh.
//==============================================================================

#endif // PROPERTIES_AND_INPUTS_MQH
