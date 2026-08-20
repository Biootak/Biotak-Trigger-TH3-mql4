//+------------------------------------------------------------------+
//| Biotak_ModeLabel_Test.mq4                                        |
//| Live verification of the step-mode label in ALL step modes.      |
//|                                                                  |
//| Verifies:                                                        |
//|   1. The "B:" (base price) part NEVER shows 0, even with the     |
//|      broken default config (Custom Price start + no price set).  |
//|   2. Combo mode shows the compact calculation breakdown on the   |
//|      same label, e.g. "avg(PatTH12.1p,TrigTH6.1p)".              |
//|   3. All 4 step modes produce a sane label.                      |
//|   4. The pure breakdown builder is correct for every preset and  |
//|      for hand-built advanced specs.                              |
//|                                                                  |
//| HOW TO RUN: drag onto any chart with live quotes, open the       |
//| "Experts" tab, look for [MODETEST] lines.                        |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

// Same include chain as the indicator - the test runs the real code
#include "Biotak\BuildConfig.mqh"
#include "Biotak\MathConstants.mqh"
#include "Biotak\Logger.mqh"
#include "Biotak\Profiler.mqh"
#include "Biotak\PropertiesAndInputs.mqh"
#include "Biotak\ConstantsAndEnums.mqh"
#include "Biotak\ProjectConstants.mqh"
#include "Biotak\InputValidator.mqh"
#include "Biotak\FloatingPointHelper.mqh"
#include "Biotak\ObjectCountManager.mqh"
#include "Biotak\PerformanceOptimizations.mqh"
#include "Biotak\InputValidationEnhanced.mqh"
#include "Biotak\GlobalVariables.mqh"
#include "Biotak\UtilityFunctions.mqh"
#include "Biotak\CalculationCache.mqh"
#include "Biotak\ZoneFactory.mqh"
#include "Biotak\ZoneValidator.mqh"
#include "Biotak\ZoneConstants.mqh"
#include "Biotak\ObjectCache.mqh"
#include "Biotak\PropertyChangeDetector.mqh"
#include "Biotak\VisibilityManager.mqh"
#include "Biotak\TimeframeFunctions.mqh"
#include "Biotak\FractalTimeframes.mqh"
#include "Biotak\StandardTimeframes.mqh"
#include "Biotak\THCalculations.mqh"
#include "Biotak\ATRCalculations.mqh"
#include "Biotak\AdaptiveScaling.mqh"
#include "Biotak\BasePriceManager.mqh"
#ifndef BUILD_LITE
#include "Biotak\WaveAnalysis.mqh"
#include "Biotak\FrequencyOptimizer.mqh"
#include "Biotak\TH3Tool.mqh"
#endif
#include "Biotak\ObjectFunctions.mqh"
#include "Biotak\ExtendedDrawingFunctions.mqh"
#include "Biotak\ComboEngine.mqh"
#include "Biotak\FactorMode.mqh"
#include "Biotak\LevelPipeline.mqh"
#include "Biotak\ModeDefinitions.mqh"
#include "Biotak\LabelFunctions.mqh"
#include "Biotak\AlertFunctions.mqh"
#include "Biotak\HistoricalDataFunctions.mqh"
#include "Biotak\EventHandlers.mqh"

int    g_testPass = 0;
int    g_testFail = 0;

void ModeAssert(const string label, const bool ok)
{
    if(ok) { g_testPass++; Print("[MODETEST] PASS: ", label); }
    else   { g_testFail++; Print("[MODETEST] FAIL: ", label); }
}

//+------------------------------------------------------------------+
//| MAIN TEST                                                        |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("========================================================");
    Print("   MODE LABEL LIVE TEST (all step modes)");
    Print("   Symbol: ", Symbol(), "  Bid: ", DoubleToString(Bid, Digits),
          "  TF: ", EnumToString((ENUM_TIMEFRAMES)Period()));
    Print("========================================================");

    // ---------------------------------------------------------------
    // Save original globals (restored at the end). NOTE: input
    // variables are const in strict mode, so only globals are touched.
    // ---------------------------------------------------------------
    int  savedOverride    = g_stepModeOverride;
    int  savedStartType   = (int)g_thStartPointType;
    double savedCustomPrice = g_customTHStartPrice;

    double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    double pipSize   = GetCachedPipSize();
    Print("[MODETEST] basePrice=", DoubleToString(basePrice, Digits),
          "  pipSize=", DoubleToString(pipSize, Digits));

    // ---------------------------------------------------------------
    // 1. THE reported bug: Custom-Price start point with no price set.
    //    The B: part of the label must NOT show 0.
    // ---------------------------------------------------------------
    g_stepModeOverride = TH_STEP;
    g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
    g_customTHStartPrice = 0.0;
    RefreshComboLabelExtraInfo();
    {
        string label = BuildUnifiedModeLabelText();
        Print("[MODETEST] custom-price=0 label: ", label);
        ModeAssert("B: never 0.00000 when custom price is unset",
                   StringFind(label, "B: 0.00000") < 0);
        ModeAssert("label shows a base price", StringFind(label, "B: ") >= 0);
    }

    // ---------------------------------------------------------------
    // 1b. THE FIX: when a custom price IS set, B must still show the
    //     calculation basis (NOT the custom price), and the anchor
    //     must appear separately as A: = the custom price.
    // ---------------------------------------------------------------
    {
        double customPrice = Bid - 0.05;
        if(customPrice <= 0) customPrice = Bid * 0.9;
        g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
        g_customTHStartPrice = customPrice;
        RefreshComboLabelExtraInfo();
        string label = BuildUnifiedModeLabelText();
        Print("[MODETEST] custom-price set label: ", label);
        ModeAssert("B shows calc basis (not custom price)",
                   StringFind(label, "B: " + DoubleToString(customPrice, 5)) < 0);
        ModeAssert("A shows anchor (custom price)",
                   StringFind(label, "A: " + DoubleToString(customPrice, 5)) >= 0);
    }

    // ---------------------------------------------------------------
    // 1c. NEW default: Previous Day Close as the level-drawing anchor
    // ---------------------------------------------------------------
    {
        g_thStartPointType = TH_START_POINT_PREVIOUS_CLOSE;
        g_customTHStartPrice = 0.0;
        RefreshComboLabelExtraInfo();
        double prevClose = iClose(Symbol(), PERIOD_D1, 1);
        double anchor = GetMidpointPrice(g_thStartPointType);
        Print("[MODETEST] prev-close anchor: ", DoubleToString(anchor, Digits),
              "  D1 close[1]=", DoubleToString(prevClose, Digits));
        ModeAssert("GetMidpointPrice(PREVIOUS_CLOSE) == D1 close[1]",
                   MathAbs(anchor - prevClose) <= GetCachedPoint() * 0.1);
        string label = BuildUnifiedModeLabelText();
        Print("[MODETEST] prev-close label: ", label);
        ModeAssert("prev-close label B not zero", StringFind(label, "B: 0.00000") < 0);
    }

    // ---------------------------------------------------------------
    // 2. All 4 step modes: sane label + no zero B
    // ---------------------------------------------------------------
    g_thStartPointType = TH_START_POINT_MIDPOINT;
    g_customTHStartPrice = 0.0;
    for(int mode = 0; mode <= 3; mode++)
    {
        g_stepModeOverride = mode;
        RefreshComboLabelExtraInfo();
        string label = BuildUnifiedModeLabelText();
        string modeName = GetStepModeName((ENUM_STEP_CALCULATION_MODE)mode);
        Print("[MODETEST] mode ", mode, " (", modeName, "): ", label);
        ModeAssert("mode " + modeName + " label not empty", StringLen(label) > 0);
        ModeAssert("mode " + modeName + " B not zero", StringFind(label, "B: 0.00000") < 0);
    }

    // ---------------------------------------------------------------
    // 3. Live label in combo mode: breakdown must be present on the
    //    same label (uses the CURRENT combo inputs, whatever they are)
    // ---------------------------------------------------------------
    g_stepModeOverride = COMBO_STEP;
    RefreshComboLabelExtraInfo();
    {
        string label = BuildUnifiedModeLabelText();
        Print("[MODETEST] Combo label (current inputs): ", label);
        ModeAssert("Combo label not empty", StringLen(label) > 0);
        ModeAssert("Combo label has '=' (calc result shown)", StringFind(label, "=") >= 0);
        SComboSpec activeSpec = GetActiveComboSpec();
        if(activeSpec.compCount >= 2)
            ModeAssert("Combo label breakdown has parens", StringFind(label, "(") >= 0);
        else
            ModeAssert("Combo label breakdown is a single number", StringFind(label, "(") < 0);
        ModeAssert("Combo label B not zero", StringFind(label, "B: 0.00000") < 0);
    }

    // ---------------------------------------------------------------
    // 4. PURE builder - every preset: exact number-only format
    // ---------------------------------------------------------------
    for(int preset = 0; preset <= 5; preset++)
    {
        SComboSpec spec = GetComboPresetSpec((ENUM_COMBO_PRESET)preset);
        string text = BuildComboCalcSummaryTextForSpec(spec, basePrice);
        Print("[MODETEST] preset ", preset, " breakdown: ", text);

        double s[MAX_COMBO_COMPONENTS];
        ArrayInitialize(s, 0);
        for(int i = 0; i < spec.compCount; i++)
            s[i] = ComputeComboComponentStep(basePrice, spec.comps[i]) / pipSize;
        double res = ComputeComboStep(spec, basePrice) / pipSize;

        string expected;
        switch(preset)
        {
            case 0: // Balanced Medium: (Pat+Trig)/2
            case 1: // Balanced Long:   (Str+Pat)/2
                expected = StringFormat("(%.1f+%.1f)/2=%.1f", s[0], s[1], res);
                break;
            case 2: // Balanced Triple: (Trig+Pat+Str)/3
                expected = StringFormat("(%.1f+%.1f+%.1f)/3=%.1f", s[0], s[1], s[2], res);
                break;
            case 3: // Conservative: max(Str,Pat)
                expected = StringFormat("max(%.1f,%.1f)=%.1f", s[0], s[1], res);
                break;
            case 4: // Aggressive: min(Trig,Sub)
                expected = StringFormat("min(%.1f,%.1f)=%.1f", s[0], s[1], res);
                break;
            case 5: // Trend Filter: |Str-Sub|
                expected = StringFormat("|%.1f-%.1f|=%.1f", s[0], s[1], res);
                break;
            default:
                expected = "";
                break;
        }
        ModeAssert("preset " + IntegerToString(preset) + " exact format", text == expected);

        // No component-name letters in the breakdown (numbers only)
        bool lettersOnly = true;
        for(int i = 0; i < StringLen(text); i++)
        {
            int ch = StringGetChar(text, i);
            if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')) lettersOnly = false;
        }
        // min/max presets legitimately contain letters; avg/sub/add/mul must not
        if(preset == 3 || preset == 4)
            ModeAssert("preset " + IntegerToString(preset) + " uses min/max keyword",
                       StringFind(text, "min(") >= 0 || StringFind(text, "max(") >= 0);
        else
            ModeAssert("preset " + IntegerToString(preset) + " breakdown is numbers-only",
                       lettersOnly);
    }

    // ---------------------------------------------------------------
    // 5. PURE builder - hand-built advanced specs
    // ---------------------------------------------------------------
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_PATTERN, COMBO_STEP_TH);
        SetComboComponent(adv.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_SS);
        adv.compCount = 2; adv.operation = COMBO_OP_AVERAGE;
        string text = BuildComboCalcSummaryTextForSpec(adv, basePrice);
        double s0 = ComputeComboComponentStep(basePrice, adv.comps[0]) / pipSize;
        double s1 = ComputeComboComponentStep(basePrice, adv.comps[1]) / pipSize;
        double res = ComputeComboStep(adv, basePrice) / pipSize;
        string expected = StringFormat("(%.1f+%.1f)/2=%.1f", s0, s1, res);
        Print("[MODETEST] Advanced (Pat+Trig)/2: ", text);
        ModeAssert("Advanced avg exact format", text == expected);
    }
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
        adv.compCount = 1; adv.operation = COMBO_OP_AVERAGE;
        string text = BuildComboCalcSummaryTextForSpec(adv, basePrice);
        double s0 = ComputeComboComponentStep(basePrice, adv.comps[0]) / pipSize;
        string expected = StringFormat("%.1f", s0);
        Print("[MODETEST] Advanced single StrTH: ", text);
        ModeAssert("Advanced single is just the number", text == expected);
    }

    // ---------------------------------------------------------------
    // 6. Summary + restore
    // ---------------------------------------------------------------
    g_stepModeOverride   = savedOverride;
    g_thStartPointType   = (ENUM_TH_START_POINT_TYPE)savedStartType;
    g_customTHStartPrice = savedCustomPrice;
    RefreshComboLabelExtraInfo();

    Print("========================================================");
    Print("   MODE LABEL TEST SUMMARY: ", g_testPass, " passed, ", g_testFail, " failed");
    Print("========================================================");
    if(g_testFail > 0)
        Alert("MODETEST: " + IntegerToString(g_testFail) + " assertion(s) FAILED - check Experts log");
    else
        Alert("MODETEST: all " + IntegerToString(g_testPass) + " assertions PASSED");
}
