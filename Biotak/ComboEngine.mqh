//+------------------------------------------------------------------+
//|                                                ComboEngine.mqh   |
//|                                  Copyright 2026, Biotak Project  |
//|              Pure Combo Step Engine + Preset Data Table          |
//|                                                                  |
//| ARCHITECTURE:                                                     |
//|   - SComboSpec describes WHAT to compute (1..N components + op)  |
//|   - ComputeComboStep is a pure function: step = f(spec, price)   |
//|   - Presets are data rows, not duplicated switch code            |
//|   - GetActiveComboSpec() is the only place that reads inputs     |
//|                                                                  |
//| Semantics are IDENTICAL to the legacy CalculateComboStepSize():  |
//|   1 component -> that step                                       |
//|   3 components -> min / max / average                            |
//|   2 components -> ApplyComboOperation (0.5 / 0.5 weights)        |
//+------------------------------------------------------------------+
#ifndef COMBO_ENGINE_MQH
#define COMBO_ENGINE_MQH
#property copyright "Copyright 2026, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#include "ConstantsAndEnums.mqh"
#include "PropertiesAndInputs.mqh"
#include "THVolNorm.mqh"

// Maximum number of combo components a spec can hold (scalable)
#define MAX_COMBO_COMPONENTS 4

//+------------------------------------------------------------------+
//| One combo component: timeframe type + step type + weight         |
//+------------------------------------------------------------------+
struct SComboComponent {
    ENUM_COMBO_TIMEFRAME_TYPE tf;
    ENUM_COMBO_STEP_TYPE      step;
    double                    weight;
};

//+------------------------------------------------------------------+
//| A complete combo specification: 1..MAX components + an operation |
//+------------------------------------------------------------------+
struct SComboSpec {
    SComboComponent      comps[MAX_COMBO_COMPONENTS];
    int                  compCount;
    ENUM_COMBO_OPERATION operation;
};

//+------------------------------------------------------------------+
//| Component initializer helper (keeps preset rows short)           |
//+------------------------------------------------------------------+
void SetComboComponent(SComboComponent &comp,
                       const ENUM_COMBO_TIMEFRAME_TYPE tf,
                       const ENUM_COMBO_STEP_TYPE step,
                       const double weight = 1.0)
{
    comp.tf = tf;
    comp.step = step;
    comp.weight = weight;
}

//+------------------------------------------------------------------+
//| Sub-minute fractal TH% for a combo component.                   |
//| On M1/M5 charts the classic timeframe mapping clamps Sub/Trigger |
//| to M1, so every component collapses to the same TH% (2.08%).    |
//| Extrapolate the fractal TH% below 1 minute instead, so combo    |
//| steps stay differentiated and correct.                          |
//| Fractal law: level k has minutes = 4^k and TH% = 2.08% * 2^k,   |
//| so below 1 minute TH% = M1% * sqrt(minutes).                    |
//| Returns 0 when the component maps to a standard timeframe (the  |
//| legacy GetTimeframeByType() path handles it unchanged). This is |
//| used for CALCULATION only - never shown in TH labels.           |
//+------------------------------------------------------------------+
double GetComboComponentTHPercentageEx(const ENUM_COMBO_TIMEFRAME_TYPE tf, const bool continuous)
{
    int currentMinutes = Period();
    if(currentMinutes <= 0) return 0;

    // Only the "below" components (Sub = /16, Trigger = /4) can land in
    // a sub-minute or inter-level gap. Pattern/Structure always map to
    // the deliberate standard fractal table - never extrapolated.
    double minutes = 0.0;
    switch(tf)
    {
        case COMBO_TF_SUB:       minutes = currentMinutes / 16.0; break;
        case COMBO_TF_TRIGGER:   minutes = currentMinutes / 4.0;  break;
        case COMBO_TF_PATTERN:
        case COMBO_TF_STRUCTURE:
        default:                 return 0.0;
    }

    double baseM1 = GetTimeframeTHForPeriod(PERIOD_M1);
    if(baseM1 <= 0) return 0.0;

    // OPT-IN continuous mode: exact continuous fractal levels for
    // Trigger/Sub at ANY minutes. Fixes the M30 collapse (Trigger=7.5min
    // and Pattern=M30 both rounded to M16=8.33%) and keeps every level
    // exact. TH% = M1% * sqrt(minutes) is the same law as the standard
    // table (M1=2.08, M4=4.16, M16=8.32, ...).
    if(continuous)
        return baseM1 * MathSqrt(minutes);

    // Default: only sub-minute components need extrapolation (on M1/M5
    // charts the legacy mapping clamped them to M1). Anything at or
    // above 1 minute keeps the exact legacy standard-TF mapping.
    if(minutes >= 1.0) return 0.0;

    return baseM1 * MathSqrt(minutes);
}

//+------------------------------------------------------------------+
//| Input-driven wrapper (see GetComboComponentTHPercentageEx).      |
//+------------------------------------------------------------------+
double GetComboComponentTHPercentage(const ENUM_COMBO_TIMEFRAME_TYPE tf)
{
    return GetComboComponentTHPercentageEx(tf, inpComboContinuousFractal);
}

//+------------------------------------------------------------------+
//| P-TH-VOLNORM-COMBO (2026-10-16, «این نرمال سازی مثل بقیه موده در  |
//| مود کامبو کار نمیکنه سطوح درست نیست»): the TH/SS-LS ladders wear  |
//| the block V (EventHandlers_Calc:550) and every TH label column    |
//| wears its own rung's V (Labels_B:374/474), but the combo engine   |
//| read the RAW table - so combo levels sat off the normalized ones. |
//| A component now wears the V of the rung its OWN pct IS: the pair  |
//| (measurement TF, rung pct) is exactly the identity the label      |
//| columns and THAbilityPriceNorm already use - no second rung map,  |
//| no new constant. An extrapolated pct (sub-minute / continuous)    |
//| has no table row, so it takes the nearest rung in log-span        |
//| (level k = 4^k minutes - the law this ladder is built on).        |
//| OFF answers 1.0 before any read: byte-identical numbers.          |
//+------------------------------------------------------------------+
double ComboComponentVolNorm(const double pct)
{
    if(!inpTHVolNorm || !(pct > 0.0)) return 1.0;

    int nR = ArraySize(FRACTAL_TIMEFRAMES);
    if(nR <= 0) return 1.0;

    // The rung whose pct IS this number (the table is the one owner).
    int idx = -1;
    for(int r = 0; r < nR; r++)
    {
        double rp = FractalPercentScaled(r);
        if(rp > 0.0 && MathAbs(rp - pct) <= rp * 1e-6) { idx = r; break; }
    }

    if(idx < 0)
    {
        // Extrapolated pct: minutes = (pct / M1%)^2 (fractal law), then
        // the nearest rung by log-distance to its 4^k span.
        double m1 = FractalPercentScaled(0);
        if(!(m1 > 0.0)) return 1.0;
        double minutes = pct / m1;
        minutes *= minutes;
        if(!(minutes > 0.0)) return 1.0;
        double best = 0.0;
        for(int r2 = 0; r2 < nR; r2++)
        {
            double d = MathAbs(MathLog(minutes / MathPow(4.0, r2)));
            if(idx < 0 || d < best) { best = d; idx = r2; }
        }
    }

    if(idx < 0) return 1.0;
    int tfMin = THVolNormTFForFractalRung(idx);
    if(tfMin <= 0) return 1.0;
    return THVolNormDrawnV(inpTHVolNorm, tfMin, FractalPercentScaled(idx));
}

//+------------------------------------------------------------------+
//| PURE: compute the step size for a single component               |
//+------------------------------------------------------------------+
double ComputeComboComponentStep(const double basePrice, const SComboComponent &comp)
{
    if(basePrice <= 0) return 0;
    double multiplier = GetStepMultiplier(comp.step);

    // Sub-minute fractal resolution: compute the step straight from
    // the extrapolated TH% (calculation only - TH labels unchanged).
    double thPercent = GetComboComponentTHPercentage(comp.tf);
    if(thPercent > 0)
        return GetStepSizeForBasisTypeFromTH(basePrice, multiplier, thPercent) *
               ComboComponentVolNorm(thPercent);   // P-TH-VOLNORM-COMBO

    ENUM_TIMEFRAMES timeframe = GetTimeframeByType(comp.tf);
    return GetStepSizeForBasisType(basePrice, multiplier, timeframe) *
           ComboComponentVolNorm(GetTimeframeTHForPeriod(timeframe));   // P-TH-VOLNORM-COMBO
}

//+------------------------------------------------------------------+
//| PURE: combine 1..N component steps with the spec operation       |
//| Semantics identical to the legacy engine.                        |
//+------------------------------------------------------------------+
double ComputeComboStep(const SComboSpec &spec, const double basePrice)
{
    if(basePrice <= 0) return 0;
    int count = spec.compCount;
    if(count < 1 || count > MAX_COMBO_COMPONENTS) return 0;
    
    double steps[MAX_COMBO_COMPONENTS];
    ArrayInitialize(steps, 0);
    for(int i = 0; i < count; i++)
        steps[i] = ComputeComboComponentStep(basePrice, spec.comps[i]);
    
    // Single component: no operation applied
    if(count == 1) return steps[0];
    
    // Triple: min / max / average (legacy behavior)
    if(count == 3)
    {
        double s1 = steps[0], s2 = steps[1], s3 = steps[2];
        if(spec.operation == COMBO_OP_MIN) return MathMin(s1, MathMin(s2, s3));
        if(spec.operation == COMBO_OP_MAX) return MathMax(s1, MathMax(s2, s3));
        return (s1 + s2 + s3) / 3.0;
    }
    
    // Two (or more) components: fold pairwise with the same weights the
    // legacy engine used for the dual case (0.5 / 0.5).
    double result = steps[0];
    for(int i = 1; i < count; i++)
        result = ApplyComboOperation(result, steps[i], spec.operation, 0.5, 0.5);
    return result;
}

//+------------------------------------------------------------------+
//| PRESET DATA TABLE: one row per preset. Adding a new preset is    |
//| adding one case of pure assignments - no logic duplication.      |
//| Mirrors the legacy GetComboConfiguration() switch, plus the      |
//| single-component SS, 4/3 and 5/3 ratio presets.                   |
//+------------------------------------------------------------------+
SComboSpec GetComboPresetSpec(const ENUM_COMBO_PRESET preset)
{
    SComboSpec spec;
    SetComboComponent(spec.comps[0], COMBO_TF_PATTERN, COMBO_STEP_TH);
    SetComboComponent(spec.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_TH);
    SetComboComponent(spec.comps[2], COMBO_TF_TRIGGER, COMBO_STEP_TH);
    SetComboComponent(spec.comps[3], COMBO_TF_TRIGGER, COMBO_STEP_TH);
    spec.compCount = 2;
    spec.operation = COMBO_OP_AVERAGE;
    
    switch(preset)
    {
        case COMBO_PRESET_BALANCED_MEDIUM:
            SetComboComponent(spec.comps[0], COMBO_TF_PATTERN, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_TH);
            spec.compCount = 2; spec.operation = COMBO_OP_AVERAGE;
            break;
        case COMBO_PRESET_BALANCED_LONG:
            SetComboComponent(spec.comps[0], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_PATTERN, COMBO_STEP_TH);
            spec.compCount = 2; spec.operation = COMBO_OP_AVERAGE;
            break;
        case COMBO_PRESET_BALANCED_TRIPLE:
            SetComboComponent(spec.comps[0], COMBO_TF_TRIGGER, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_PATTERN, COMBO_STEP_TH);
            SetComboComponent(spec.comps[2], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
            spec.compCount = 3; spec.operation = COMBO_OP_AVERAGE;
            break;
        case COMBO_PRESET_CONSERVATIVE:
            SetComboComponent(spec.comps[0], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_PATTERN, COMBO_STEP_TH);
            spec.compCount = 2; spec.operation = COMBO_OP_MAX;
            break;
        case COMBO_PRESET_AGGRESSIVE:
            SetComboComponent(spec.comps[0], COMBO_TF_TRIGGER, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_SUB, COMBO_STEP_TH);
            spec.compCount = 2; spec.operation = COMBO_OP_MIN;
            break;
        case COMBO_PRESET_TREND_FILTER:
            SetComboComponent(spec.comps[0], COMBO_TF_STRUCTURE, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_SUB, COMBO_STEP_TH);
            spec.compCount = 2; spec.operation = COMBO_OP_SUBTRACT;
            break;
        case COMBO_PRESET_SS:
            // One component: current timeframe (Pattern) with Short Step.
            // ComputeComboStep returns this component unchanged, so the
            // center-to-center spacing matches the standalone SS mode.
            SetComboComponent(spec.comps[0], COMBO_TF_PATTERN, COMBO_STEP_SS);
            spec.compCount = 1; spec.operation = COMBO_OP_AVERAGE;
            break;
        case COMBO_PRESET_RATIO_4_3:
            // Uniform blended ratio: TH * (LS / SS) = TH * 4/3.
            SetComboComponent(spec.comps[0], COMBO_TF_PATTERN, COMBO_STEP_RATIO_4_3);
            spec.compCount = 1; spec.operation = COMBO_OP_AVERAGE;
            break;
        case COMBO_PRESET_RATIO_5_3:
            // Uniform blended ratio: TH * 5/3.
            SetComboComponent(spec.comps[0], COMBO_TF_PATTERN, COMBO_STEP_RATIO_5_3);
            spec.compCount = 1; spec.operation = COMBO_OP_AVERAGE;
            break;
        default:
            SetComboComponent(spec.comps[0], COMBO_TF_PATTERN, COMBO_STEP_TH);
            SetComboComponent(spec.comps[1], COMBO_TF_TRIGGER, COMBO_STEP_TH);
            spec.compCount = 2; spec.operation = COMBO_OP_AVERAGE;
            break;
    }
    
    return spec;
}

//+------------------------------------------------------------------+
//| INPUT ADAPTER: the only place that reads combo inputs.           |
//| Returns the active spec for the current settings.                |
//+------------------------------------------------------------------+
SComboSpec GetActiveComboSpec()
{
    if(inpComboMode == COMBO_MODE_ADVANCED)
    {
        // Advanced mode reads explicit TF/Step inputs directly - no packed
        // encoding, no casts. The operation uses ENUM_COMBO_OPERATION, so
        // the selected dropdown value means exactly what it computes.
        SComboSpec spec;
        SetComboComponent(spec.comps[0], inpComboComp1TF, inpComboComp1Step);
        if(inpComboComp2Enabled)
        {
            SetComboComponent(spec.comps[1], inpComboComp2TF, inpComboComp2Step);
            spec.compCount = 2;
        }
        else
        {
            spec.compCount = 1;
        }
        spec.operation = inpComboOp1;
        return spec;
    }
    
    return GetComboPresetSpec(inpComboPreset);
}

//+------------------------------------------------------------------+
//| PUBLIC ENTRY: combo step size for the current settings           |
//+------------------------------------------------------------------+
double GetComboStepSize(const double basePrice)
{
    if(basePrice <= 0) return 0;
    
    SComboSpec spec = GetActiveComboSpec();
    double result = ComputeComboStep(spec, basePrice);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][COMBO] Combo Step [", EnumToString(inpComboMode), "]: ", DoubleToString(result, Digits));
    #endif
    
    return result;
}

//+------------------------------------------------------------------+
//| Short name for a combo component timeframe type (label display)  |
//+------------------------------------------------------------------+
string GetComboTFShortName(const ENUM_COMBO_TIMEFRAME_TYPE tf)
{
    switch(tf)
    {
        case COMBO_TF_SUB:       return "Sub";
        case COMBO_TF_TRIGGER:   return "Trig";
        case COMBO_TF_PATTERN:   return "Pat";
        case COMBO_TF_STRUCTURE: return "Str";
        default:                 return "?";
    }
}

//+------------------------------------------------------------------+
//| Short name for a combo step type (label display)                 |
//+------------------------------------------------------------------+
string GetComboStepShortName(const ENUM_COMBO_STEP_TYPE step)
{
    switch(step)
    {
        case COMBO_STEP_TH: return "TH";
        case COMBO_STEP_SS: return "SS";
        case COMBO_STEP_LS:       return "LS";
        case COMBO_STEP_RATIO_4_3: return "4/3";
        case COMBO_STEP_RATIO_5_3: return "5/3";
        default:                   return "?";
    }
}

//+------------------------------------------------------------------+
//| Compact operator symbol for the label breakdown                  |
//+------------------------------------------------------------------+
string GetComboOpSymbol(const ENUM_COMBO_OPERATION op)
{
    switch(op)
    {
        case COMBO_OP_AVERAGE:  return "avg";
        case COMBO_OP_ADD:      return "+";
        case COMBO_OP_SUBTRACT: return "|-|";
        case COMBO_OP_MULTIPLY: return "x";
        case COMBO_OP_MIN:      return "min";
        case COMBO_OP_MAX:      return "max";
        case COMBO_OP_WEIGHTED: return "w";
        default:                return "?";
    }
}

//+------------------------------------------------------------------+
//| PURE: compact calculation summary for a given spec + base price. |
//| Shows the actual numbers of the calculation (component steps in   |
//| pips + final result), e.g.                                       |
//|   "(12.1+6.1)/2=13.6"   "max(24.2,12.1)=24.2"   "|24.2-3.1|=21.1" |
//| No component names - just the arithmetic so the user can verify  |
//| the math at a glance.                                            |
//+------------------------------------------------------------------+
string BuildComboCalcSummaryTextForSpec(const SComboSpec &spec, const double basePrice)
{
    if(basePrice <= 0) return "";

    double pipSize = GetCachedPipSize();
    if(pipSize <= 0) return "";

    int count = spec.compCount;
    if(count < 1 || count > MAX_COMBO_COMPONENTS) return "";

    double steps[MAX_COMBO_COMPONENTS];
    ArrayInitialize(steps, 0);
    for(int i = 0; i < count; i++)
    {
        steps[i] = ComputeComboComponentStep(basePrice, spec.comps[i]);
        if(steps[i] <= 0) return "";
    }

    // Single component: just the step number
    if(count == 1)
        return DoubleToString(steps[0] / pipSize, 1);

    // Final combined result (matches the label's S: value)
    double result = ComputeComboStep(spec, basePrice);
    if(result <= 0) return "";
    string resultStr = DoubleToString(result / pipSize, 1);

    // Two components: infix arithmetic reads best
    if(count == 2)
    {
        string a = DoubleToString(steps[0] / pipSize, 1);
        string b = DoubleToString(steps[1] / pipSize, 1);
        string text = "";
        switch(spec.operation)
        {
            case COMBO_OP_AVERAGE:  text = "(" + a + "+" + b + ")/2"; break;
            case COMBO_OP_ADD:      text = a + "+" + b; break;
            case COMBO_OP_SUBTRACT: text = "|" + a + "-" + b + "|"; break;
            case COMBO_OP_MULTIPLY: text = a + "x" + b; break;
            case COMBO_OP_MIN:      text = "min(" + a + "," + b + ")"; break;
            case COMBO_OP_MAX:      text = "max(" + a + "," + b + ")"; break;
            case COMBO_OP_WEIGHTED: text = "w(" + a + "," + b + ")"; break;
            default:                text = "?"; break;
        }
        return text + "=" + resultStr;
    }

    // 3+ components: AVERAGE as (a+b+c)/n, others as op(a,b,c)
    if(spec.operation == COMBO_OP_AVERAGE)
    {
        string sum = "";
        for(int i = 0; i < count; i++)
        {
            if(i > 0) sum += "+";
            sum += DoubleToString(steps[i] / pipSize, 1);
        }
        return "(" + sum + ")/" + IntegerToString(count) + "=" + resultStr;
    }

    string args = "";
    for(int i = 0; i < count; i++)
    {
        if(i > 0) args += ",";
        args += DoubleToString(steps[i] / pipSize, 1);
    }
    return GetComboOpSymbol(spec.operation) + "(" + args + ")=" + resultStr;
}

//+------------------------------------------------------------------+
//| Compact calculation summary for the step-mode label.             |
//| Uses the ACTIVE combo spec and the SAME base price as the        |
//| label's S: value, so the shown component steps multiply up to    |
//| the displayed result.                                            |
//+------------------------------------------------------------------+
string BuildComboCalcSummaryText()
{
    double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    if(basePrice <= 0) return "";
    return BuildComboCalcSummaryTextForSpec(GetActiveComboSpec(), basePrice);
}

//+------------------------------------------------------------------+
//| P-PERF-09: change guard for the combo summary rebuild.           |
//|                                                                  |
//| WHY: this string is a chain of component-step computations plus    |
//| one DoubleToString per component and a handful of concatenations,  |
//| and NOTHING about it is time-dependent — its only inputs are the   |
//| step mode, the active combo spec and the base price. It was        |
//| rebuilt unconditionally from OnTimer (4x/s) AND from               |
//| RefreshUIPerTick (tick rate, i.e. up to ~20x/s more), so a chart    |
//| in COMBO mode rebuilt an identical string ~100x/s for a label      |
//| whose text is only written when it really changed. The guard costs  |
//| one struct build + one int hash and drops the rebuild to "when an   |
//| input moved" (in practice twice per 30-minute base-price block).    |
//+------------------------------------------------------------------+
//--- P-BE-01 (2026-10-13) — THE SIGNATURE IS EXACT, NOT A 32-BIT FOLD.
//--- This used to return an `int` built as `sig = sig*31 + x` over up to
//--- MAX_COMBO_COMPONENTS x 3 fields, seeded with `operation*1000003 +
//--- compCount*7919` (~3.0e6 for operation 3). A signed 32-bit int wraps after
//--- about five multiplies, and MQL4 wraps SILENTLY, so the seed and the later
//--- fields can cancel: two DIFFERENT specs land on the same number,
//--- `RefreshComboLabelExtraInfo` takes its early return, and the combo
//--- breakdown label keeps serving the PREVIOUS spec's string. That is the one
//--- thing this guard must never do — its whole contract is "same inputs ->
//--- same string", which only holds if the key is injective.
//---
//--- The fields are joined as TEXT instead: exact for every spec, no collisions
//--- by construction. Cost is <=36 IntegerToString calls on a value the guard
//--- already avoids rebuilding (the pre-P-PERF-09 path rebuilt the whole summary
//--- ~100x/s), so the trade the guard makes is still the right one.
string ComboSpecSignature(const SComboSpec &spec)
{
    string sig = IntegerToString((int)spec.operation) + ":" + IntegerToString(spec.compCount);
    for(int i = 0; i < spec.compCount && i < MAX_COMBO_COMPONENTS; i++)
        sig = sig + "|" + IntegerToString((int)spec.comps[i].tf)
                  + "," + IntegerToString((int)spec.comps[i].step)
                  + "," + IntegerToString((int)MathRound(spec.comps[i].weight * 1000.0));
    return sig;
}

//+------------------------------------------------------------------+
//| Refresh the combo breakdown global consumed by the step-mode     |
//| label builder (UtilityFunctions.mqh, included earlier).          |
//| Call this whenever the step mode / combo inputs may have changed |
//| and before the label is (re)built.                               |
//| P-PERF-09: rebuilt only when one of its inputs actually moved.   |
//+------------------------------------------------------------------+
void RefreshComboLabelExtraInfo()
{
    static int    s_lastMode = -1;
    static double s_lastBase = -1.0;
    static string s_lastSig  = "";   // P-BE-01: the key is TEXT now (an int folded silently)

    int mode = (int)GetCurrentStepMode();
    if(mode != (int)COMBO_STEP)
    {
        // Leaving COMBO clears the breakdown once — the label builder reads
        // "" as "no breakdown", so a stale string would be the only bug here.
        if(g_comboLabelExtraInfo != "")
        {
            g_comboLabelExtraInfo = "";
            s_lastMode = mode; s_lastBase = -1.0; s_lastSig = "";
        }
        else if(s_lastMode != mode)
        {
            s_lastMode = mode; s_lastBase = -1.0; s_lastSig = "";
        }
        return;
    }

    double basePrice = (g_dailyClosePriceForTH > 0) ? g_dailyClosePriceForTH : Bid;
    SComboSpec spec = GetActiveComboSpec();
    string sig = ComboSpecSignature(spec);
    if(mode == s_lastMode && basePrice == s_lastBase && sig == s_lastSig)
        return;   // identical inputs -> identical string, nothing to rebuild

    if(basePrice <= 0)
        g_comboLabelExtraInfo = "";
    else
        g_comboLabelExtraInfo = BuildComboCalcSummaryTextForSpec(spec, basePrice);

    s_lastMode = mode; s_lastBase = basePrice; s_lastSig = sig;
}

//+------------------------------------------------------------------+
//| DEBUG: print the active spec (components + operation)            |
//+------------------------------------------------------------------+
void PrintComboSpec(const SComboSpec &spec)
{
    Print("  ComboSpec: ", spec.compCount, " component(s), op=", EnumToString(spec.operation));
    for(int i = 0; i < spec.compCount && i < MAX_COMBO_COMPONENTS; i++)
        Print("   comp[", i, "]: tf=", EnumToString(spec.comps[i].tf),
              " step=", EnumToString(spec.comps[i].step),
              " weight=", DoubleToString(spec.comps[i].weight, 2));
}

#endif // COMBO_ENGINE_MQH
