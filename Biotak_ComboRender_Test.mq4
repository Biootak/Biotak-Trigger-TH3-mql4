//+------------------------------------------------------------------+
//| Biotak_ComboRender_Test.mq4                                      |
//| Live verification of the Combo step calculations.                |
//|                                                                  |
//| Uses the EXACT production functions (ComboEngine +               |
//| GetStepSizeForBasisType), so it tests the real code path.        |
//|                                                                  |
//| HOW TO RUN: drag this script onto any chart, then open the       |
//| "Experts" tab (or Tools > Experts log) and read the [COMBOTEST]  |
//| lines.                                                           |
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
// TH3TOOL-OFF (tool retired — commented out, not deleted):
// #include "Biotak\TH3Tool.mqh"
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

//+------------------------------------------------------------------+
//| Assertion helper                                                 |
//+------------------------------------------------------------------+
void ComboAssert(const string label, const bool ok)
{
    if(ok) { g_testPass++; Print("[COMBOTEST] PASS: ", label); }
    else   { g_testFail++; Print("[COMBOTEST] FAIL: ", label); }
}

bool ComboNear(const double a, const double b)
{
    return MathAbs(a - b) <= 0.0000001 * MathMax(1.0, MathAbs(b));
}

//+------------------------------------------------------------------+
//| Print one spec: component steps + combined result                |
//+------------------------------------------------------------------+
void PrintComboResult(const string label, const SComboSpec &spec, const double basePrice)
{
    double steps[MAX_COMBO_COMPONENTS];
    ArrayInitialize(steps, 0);
    string comps = "";
    for(int i = 0; i < spec.compCount && i < MAX_COMBO_COMPONENTS; i++)
    {
        steps[i] = ComputeComboComponentStep(basePrice, spec.comps[i]);
        comps += StringFormat(" [%s/%s=%.6f]",
                              EnumToString(spec.comps[i].tf),
                              EnumToString(spec.comps[i].step),
                              steps[i]);
    }
    double result = ComputeComboStep(spec, basePrice);
    Print("[COMBOTEST] ", label, " => ", DoubleToString(result, Digits),
          comps, "  op=", EnumToString(spec.operation));
}

//+------------------------------------------------------------------+
//| Verify one preset: recompute the expected fold from the same     |
//| component steps and compare with the engine result.              |
//+------------------------------------------------------------------+
void TestPreset(const ENUM_COMBO_PRESET preset, const string name, const double basePrice)
{
    SComboSpec spec = GetComboPresetSpec(preset);
    double steps[MAX_COMBO_COMPONENTS];
    ArrayInitialize(steps, 0);
    for(int i = 0; i < spec.compCount && i < MAX_COMBO_COMPONENTS; i++)
        steps[i] = ComputeComboComponentStep(basePrice, spec.comps[i]);

    double actual = ComputeComboStep(spec, basePrice);

    double expected = 0;
    if(spec.compCount == 1)
        expected = steps[0];
    else if(spec.compCount == 3)
    {
        double s1 = steps[0], s2 = steps[1], s3 = steps[2];
        if(spec.operation == COMBO_OP_MIN)      expected = MathMin(s1, MathMin(s2, s3));
        else if(spec.operation == COMBO_OP_MAX) expected = MathMax(s1, MathMax(s2, s3));
        else                                    expected = (s1 + s2 + s3) / 3.0;
    }
    else
        expected = ApplyComboOperation(steps[0], steps[1], spec.operation, 0.5, 0.5);

    bool allPositive = (steps[0] > 0);
    for(int i = 1; i < spec.compCount; i++)
        if(steps[i] <= 0) allPositive = false;

    Print("[COMBOTEST] --- ", name, " ---");
    Print("[COMBOTEST]   components=", spec.compCount, "  op=", EnumToString(spec.operation));
    for(int i = 0; i < spec.compCount; i++)
        Print("[COMBOTEST]   comp[", i, "] ", EnumToString(spec.comps[i].tf), "/",
              EnumToString(spec.comps[i].step), " = ", DoubleToString(steps[i], Digits));
    Print("[COMBOTEST]   engine=", DoubleToString(actual, Digits),
          "  expected=", DoubleToString(expected, Digits));

    ComboAssert(name + " component steps > 0", allPositive);
    ComboAssert(name + " engine == expected fold", ComboNear(actual, expected));
}

//+------------------------------------------------------------------+
//| Test an advanced (manual) spec                                    |
//+------------------------------------------------------------------+
void TestAdvancedSpec(const string name, const SComboSpec &spec, const double basePrice)
{
    double steps[MAX_COMBO_COMPONENTS];
    ArrayInitialize(steps, 0);
    for(int i = 0; i < spec.compCount && i < MAX_COMBO_COMPONENTS; i++)
        steps[i] = ComputeComboComponentStep(basePrice, spec.comps[i]);

    double actual = ComputeComboStep(spec, basePrice);

    // Expected must mirror the engine's count-based branches EXACTLY:
    // 1 comp -> step, 3 comps -> min/max/avg, 2 comps -> pairwise fold
    double expected = 0;
    if(spec.compCount == 1)
        expected = steps[0];
    else if(spec.compCount == 3)
    {
        double s1 = steps[0], s2 = steps[1], s3 = steps[2];
        if(spec.operation == COMBO_OP_MIN)      expected = MathMin(s1, MathMin(s2, s3));
        else if(spec.operation == COMBO_OP_MAX) expected = MathMax(s1, MathMax(s2, s3));
        else                                    expected = (s1 + s2 + s3) / 3.0;
    }
    else
        expected = ApplyComboOperation(steps[0], steps[1], spec.operation, 0.5, 0.5);

    Print("[COMBOTEST] --- Advanced: ", name, " ---");
    Print("[COMBOTEST]   engine=", DoubleToString(actual, Digits),
          "  expected=", DoubleToString(expected, Digits));

    ComboAssert("Advanced '" + name + "' engine == expected", ComboNear(actual, expected));
}

//+------------------------------------------------------------------+
//| MAIN TEST                                                        |
//+------------------------------------------------------------------+
void OnStart()
{
    double basePrice = Close[0];
    if(basePrice <= 0) basePrice = 1.0;

    Print("========================================================");
    Print("   COMBO LIVE CALCULATION TEST");
    Print("   Base price : ", DoubleToString(basePrice, Digits));
    Print("   Chart TF   : ", EnumToString((ENUM_TIMEFRAMES)Period()));
    Print("========================================================");

    // ---------------------------------------------------------------
    // 0. Building blocks used by everything below
    // ---------------------------------------------------------------
    Print("[COMBOTEST] Step multipliers: TH=", DoubleToString(GetStepMultiplier(COMBO_STEP_TH), 2),
          " SS=", DoubleToString(GetStepMultiplier(COMBO_STEP_SS), 2),
          " LS=", DoubleToString(GetStepMultiplier(COMBO_STEP_LS), 2));
    Print("[COMBOTEST] TF mapping: SUB=", EnumToString(GetTimeframeByType(COMBO_TF_SUB)),
          " TRIGGER=", EnumToString(GetTimeframeByType(COMBO_TF_TRIGGER)),
          " PATTERN=", EnumToString(GetTimeframeByType(COMBO_TF_PATTERN)),
          " STRUCTURE=", EnumToString(GetTimeframeByType(COMBO_TF_STRUCTURE)));

    // ---------------------------------------------------------------
    // 0b. INDEPENDENT literals: TH% table + step primitive.
    //     Chart-independent (explicit periods, fixed price), so the
    //     numbers below were computed by hand from the source tables
    //     and must match the production functions exactly.
    // ---------------------------------------------------------------
    ComboAssert("TH% M1  == 2.08%",  ComboNear(GetTimeframeTHForPeriod(PERIOD_M1), 0.0208));
    ComboAssert("TH% M5  == 4.17%",  ComboNear(GetTimeframeTHForPeriod(PERIOD_M5), 0.0417));
    ComboAssert("TH% M15 == 8.33%",  ComboNear(GetTimeframeTHForPeriod(PERIOD_M15), 0.0833));
    ComboAssert("TH% M30 == 8.33%",  ComboNear(GetTimeframeTHForPeriod(PERIOD_M30), 0.0833));
    ComboAssert("TH% H1  == 16.66%", ComboNear(GetTimeframeTHForPeriod(PERIOD_H1), 0.1666));
    ComboAssert("TH% H4  == 33.33%", ComboNear(GetTimeframeTHForPeriod(PERIOD_H4), 0.3333));
    ComboAssert("TH% D1  == 133.32%", ComboNear(GetTimeframeTHForPeriod(PERIOD_D1), 1.3332));
    ComboAssert("TH% W1  == 266.64%", ComboNear(GetTimeframeTHForPeriod(PERIOD_W1), 2.6664));
    ComboAssert("TH% MN1 == 533.28%", ComboNear(GetTimeframeTHForPeriod(PERIOD_MN1), 5.3328));

    // Step primitive: step = price * TH% / 100 * multiplier  (hand-computed)
    ComboAssert("Step(1.085,TH,H1) == 0.00180761",
        ComboNear(GetStepSizeForBasisType(1.085, 1.0, PERIOD_H1), 0.00180761));
    ComboAssert("Step(1.085,SS,H1) == 0.002711415",
        ComboNear(GetStepSizeForBasisType(1.085, 1.5, PERIOD_H1), 0.002711415));
    ComboAssert("Step(1.085,TH,M15) == 0.000903805",
        ComboNear(GetStepSizeForBasisType(1.085, 1.0, PERIOD_M15), 0.000903805));
    ComboAssert("Step(1.085,LS,H4) == 0.00723261",
        ComboNear(GetStepSizeForBasisType(1.085, 2.0, PERIOD_H4), 0.00723261));

    // ---------------------------------------------------------------
    // 1. All 6 practical presets
    // ---------------------------------------------------------------
    TestPreset(COMBO_PRESET_BALANCED_MEDIUM,  "Balanced Medium", basePrice);
    TestPreset(COMBO_PRESET_BALANCED_LONG,    "Balanced Long",   basePrice);
    TestPreset(COMBO_PRESET_BALANCED_TRIPLE,  "Balanced Triple", basePrice);
    TestPreset(COMBO_PRESET_CONSERVATIVE,     "Conservative",    basePrice);
    TestPreset(COMBO_PRESET_AGGRESSIVE,       "Aggressive",      basePrice);
    TestPreset(COMBO_PRESET_TREND_FILTER,     "Trend Filter",    basePrice);

    // min <= avg <= max for the triple preset (relation check)
    {
        SComboSpec spec = GetComboPresetSpec(COMBO_PRESET_BALANCED_TRIPLE);
        double s1 = ComputeComboComponentStep(basePrice, spec.comps[0]);
        double s2 = ComputeComboComponentStep(basePrice, spec.comps[1]);
        double s3 = ComputeComboComponentStep(basePrice, spec.comps[2]);
        double mn = MathMin(s1, MathMin(s2, s3));
        double mx = MathMax(s1, MathMax(s2, s3));
        double avg = (s1 + s2 + s3) / 3.0;
        ComboAssert("Triple relation min <= avg <= max", mn <= avg && avg <= mx);
    }

    // ---------------------------------------------------------------
    // 2. Advanced-mode specs built directly (same path as the inputs)
    // ---------------------------------------------------------------
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_PATTERN, COMBO_STEP_TH);
        SetComboComponent(adv.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_SS);
        adv.compCount = 2; adv.operation = COMBO_OP_AVERAGE;
        TestAdvancedSpec("(PatternTH + TriggerSS) / 2", adv, basePrice);
    }
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_PATTERN, COMBO_STEP_TH);
        SetComboComponent(adv.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_SS);
        adv.compCount = 2; adv.operation = COMBO_OP_MIN;
        TestAdvancedSpec("min(PatternTH, TriggerSS)", adv, basePrice);
    }
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_PATTERN, COMBO_STEP_TH);
        SetComboComponent(adv.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_SS);
        adv.compCount = 2; adv.operation = COMBO_OP_MAX;
        TestAdvancedSpec("max(PatternTH, TriggerSS)", adv, basePrice);
    }
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
        SetComboComponent(adv.comps[1], COMBO_TF_SUB, COMBO_STEP_TH);
        adv.compCount = 2; adv.operation = COMBO_OP_SUBTRACT;
        TestAdvancedSpec("|StructureTH - SubTH|", adv, basePrice);
    }
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
        adv.compCount = 1; adv.operation = COMBO_OP_AVERAGE;
        TestAdvancedSpec("single StructureTH (1 component)", adv, basePrice);
    }
    {
        SComboSpec adv;
        SetComboComponent(adv.comps[0], COMBO_TF_TRIGGER, COMBO_STEP_TH);
        SetComboComponent(adv.comps[1], COMBO_TF_PATTERN, COMBO_STEP_TH);
        SetComboComponent(adv.comps[2], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
        adv.compCount = 3; adv.operation = COMBO_OP_AVERAGE;
        TestAdvancedSpec("triple average (T+P+S)/3", adv, basePrice);
    }

    // ---------------------------------------------------------------
    // 3. Operation unit checks on fixed values (pure function)
    // ---------------------------------------------------------------
    ComboAssert("AVERAGE(10,20) == 15",
        ComboNear(ApplyComboOperation(10.0, 20.0, COMBO_OP_AVERAGE), 15.0));
    ComboAssert("ADD(10,20) == 30",
        ComboNear(ApplyComboOperation(10.0, 20.0, COMBO_OP_ADD), 30.0));
    ComboAssert("SUBTRACT(30,10) == 20",
        ComboNear(ApplyComboOperation(30.0, 10.0, COMBO_OP_SUBTRACT), 20.0));
    ComboAssert("MULTIPLY(3,4) == 12",
        ComboNear(ApplyComboOperation(3.0, 4.0, COMBO_OP_MULTIPLY), 12.0));
    ComboAssert("MIN(10,20) == 10",
        ComboNear(ApplyComboOperation(10.0, 20.0, COMBO_OP_MIN), 10.0));
    ComboAssert("MAX(10,20) == 20",
        ComboNear(ApplyComboOperation(10.0, 20.0, COMBO_OP_MAX), 20.0));
    ComboAssert("WEIGHTED(10,20,0.25,0.75) == 17.5",
        ComboNear(ApplyComboOperation(10.0, 20.0, COMBO_OP_WEIGHTED, 0.25, 0.75), 17.5));

    // ---------------------------------------------------------------
    // 4. End-to-end: CalculateComboStepSize (the exact entry the
    //    indicator uses) must equal the engine with the active spec
    // ---------------------------------------------------------------
    {
        double e2e = CalculateComboStepSize(basePrice);
        double direct = ComputeComboStep(GetActiveComboSpec(), basePrice);
        Print("[COMBOTEST] End-to-end CalculateComboStepSize = ", DoubleToString(e2e, Digits),
              "  (active spec = ", (inpComboMode == COMBO_MODE_PRESET ? EnumToString(inpComboPreset) : "Advanced"), ")");
        ComboAssert("End-to-end == engine(active spec)", ComboNear(e2e, direct));
        ComboAssert("End-to-end step > 0", e2e > 0);
    }

    // ---------------------------------------------------------------
    // 6. Sub-minute fractal resolution (M1/M5/M15 charts)
    //    On M1/M5 the classic TF mapping clamps Sub/Trigger to M1, so
    //    every component collapses to the same TH% (2.08%). The engine
    //    now extrapolates the fractal TH% below 1 minute for the
    //    CALCULATION only - TH labels are never touched.
    // ---------------------------------------------------------------
    {
        int curMin = Period();
        double baseM1 = GetTimeframeTHForPeriod(PERIOD_M1); // 2.08% (shift-aware)

        // Standard-timeframe components must never use the extrapolation
        ComboAssert("Pattern TH% uses standard path (0)",
            GetComboComponentTHPercentage(COMBO_TF_PATTERN) == 0.0);
        ComboAssert("Structure TH% uses standard path (0)",
            GetComboComponentTHPercentage(COMBO_TF_STRUCTURE) == 0.0);

        if(curMin < 16)
        {
            // SUB = current/16 is sub-minute on M1/M5/M15 charts
            double subMin = curMin / 16.0;
            double subTH = GetComboComponentTHPercentage(COMBO_TF_SUB);
            double expectedSub = baseM1 * MathSqrt(subMin);
            Print("[COMBOTEST] Sub-minute: SUB minutes=", DoubleToString(subMin, 4),
                  " TH%=", DoubleToString(subTH, 4),
                  " expected=", DoubleToString(expectedSub, 4));
            ComboAssert("SUB extrapolated TH% = M1% * sqrt(minutes)",
                ComboNear(subTH, expectedSub));
        }
        else
        {
            ComboAssert("SUB on TF >= 16min uses standard path (0)",
                GetComboComponentTHPercentage(COMBO_TF_SUB) == 0.0);
        }

        // Continuous-mode (opt-in toggle) checks - pure Ex variant,
        // independent of the input value:
        {
            double trigMin = curMin / 4.0;
            double subMin = curMin / 16.0;
            ComboAssert("Continuous: TRIGGER = M1% * sqrt(cur/4)",
                ComboNear(GetComboComponentTHPercentageEx(COMBO_TF_TRIGGER, true),
                          baseM1 * MathSqrt(trigMin)));
            ComboAssert("Continuous: SUB = M1% * sqrt(cur/16)",
                ComboNear(GetComboComponentTHPercentageEx(COMBO_TF_SUB, true),
                          baseM1 * MathSqrt(subMin)));
            // Pattern/Structure never use the continuous path
            ComboAssert("Continuous: Pattern stays standard (0)",
                GetComboComponentTHPercentageEx(COMBO_TF_PATTERN, true) == 0.0);
            ComboAssert("Continuous: Structure stays standard (0)",
                GetComboComponentTHPercentageEx(COMBO_TF_STRUCTURE, true) == 0.0);
            // M30 collapse fix: with continuous ON, Trigger must differ from Pattern
            if(curMin == 30)
            {
                double trigC = GetComboComponentTHPercentageEx(COMBO_TF_TRIGGER, true);
                double patC = GetTimeframeTHForPeriod(PERIOD_M30);
                ComboAssert("M30: continuous Trigger != Pattern (collapse fixed)",
                    trigC > 0 && MathAbs(trigC - patC) > 0.001);
            }
            // Off-toggle default: Trigger at >= 1min keeps the standard path
            ComboAssert("Default: Trigger >= 1min uses standard path (0)",
                (trigMin >= 1.0)
                    ? (GetComboComponentTHPercentageEx(COMBO_TF_TRIGGER, false) == 0.0)
                    : (GetComboComponentTHPercentageEx(COMBO_TF_TRIGGER, false) > 0));
        }

        if(curMin < 4)
        {
            // TRIGGER = current/4 is sub-minute only on M1 charts
            double trigMin = curMin / 4.0;
            double trigTH = GetComboComponentTHPercentage(COMBO_TF_TRIGGER);
            double expectedTrig = baseM1 * MathSqrt(trigMin);
            Print("[COMBOTEST] Sub-minute: TRIGGER minutes=", DoubleToString(trigMin, 4),
                  " TH%=", DoubleToString(trigTH, 4),
                  " expected=", DoubleToString(expectedTrig, 4));
            ComboAssert("TRIGGER extrapolated TH% = M1% * sqrt(minutes)",
                ComboNear(trigTH, expectedTrig));

            // On M1 the four component steps must now be distinct
            SComboSpec spec;
            SetComboComponent(spec.comps[0], COMBO_TF_SUB, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_TH);
            SetComboComponent(spec.comps[2], COMBO_TF_PATTERN, COMBO_STEP_TH);
            SetComboComponent(spec.comps[3], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
            double s0 = ComputeComboComponentStep(basePrice, spec.comps[0]);
            double s1 = ComputeComboComponentStep(basePrice, spec.comps[1]);
            double s2 = ComputeComboComponentStep(basePrice, spec.comps[2]);
            double s3 = ComputeComboComponentStep(basePrice, spec.comps[3]);
            Print("[COMBOTEST] M1 sub-minute steps: Sub=", DoubleToString(s0, Digits),
                  " Trig=", DoubleToString(s1, Digits),
                  " Pat=", DoubleToString(s2, Digits),
                  " Str=", DoubleToString(s3, Digits));
            ComboAssert("M1: Sub < Trigger < Pattern < Structure",
                s0 > 0 && s0 < s1 && s1 < s2 && s2 < s3);
        }
        else if(curMin < 16)
        {
            // M5/M15: SUB is sub-minute; TRIGGER resolves to M1 (standard)
            double trigTH = GetComboComponentTHPercentage(COMBO_TF_TRIGGER);
            double subTH = GetComboComponentTHPercentage(COMBO_TF_SUB);
            ComboAssert("M5/M15: TRIGGER uses standard path (0)", trigTH == 0.0);
            ComboAssert("M5/M15: SUB extrapolated TH% < M1%", subTH > 0 && subTH < baseM1);
        }
    }

    // ---------------------------------------------------------------
    // 5. Summary
    // ---------------------------------------------------------------
    Print("========================================================");
    Print("   COMBO TEST SUMMARY: ", g_testPass, " passed, ", g_testFail, " failed");
    Print("========================================================");
    if(g_testFail > 0)
        Alert("COMBOTEST: " + IntegerToString(g_testFail) + " assertion(s) FAILED - check Experts log");
    else
        Alert("COMBOTEST: all " + IntegerToString(g_testPass) + " assertions PASSED");
}
