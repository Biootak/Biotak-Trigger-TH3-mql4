//+------------------------------------------------------------------+
//|                                           FactorMode.mqh         |
//|             Centralized Factor Step Mode Logic                   |
//|                                                                  |
//| SINGLE SOURCE OF TRUTH for:                                     |
//|   - Factor <-> Step relationship (Step = Range / (Factor * 2))  |
//|   - Auto basis step calculation (all 8 bases)                   |
//|   - DIRECT / CLASSIC input semantics                            |
//|                                                                  |
//| All drawing, label, status and hotkey paths must consume these  |
//| functions instead of re-implementing the formulas inline.       |
//+------------------------------------------------------------------+
#ifndef FACTOR_MODE_MQH
#define FACTOR_MODE_MQH

//+------------------------------------------------------------------+
//| Basis multiplier table - derived from adapted current-TF TH     |
//|                                                                  |
//|   CONTROL = (SS + LS) / 2 = 1.75 * TH  [Balanced, default]      |
//|   SS      = Short Step            = 1.5  * TH                   |
//|   LS      = Long Step             = 2.0  * TH                   |
//|   TH      = Pure TH               = 1.0  * TH                   |
//|   TRIGGER = Current TF TH         = 1.0  * TH                   |
//|                                                                  |
//| PATTERN / STRUCTURE / COMBO are computed separately (they use   |
//| their own timeframes / combo configuration).                    |
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
    return 1.5; // Fallback = SS (matches legacy default branch)
}

//+------------------------------------------------------------------+
//| Historical range used by Factor mode                             |
//+------------------------------------------------------------------+
double GetFactorRange()
{
    if(g_highestHigh > 0 && g_lowestLow > 0 && g_highestHigh > g_lowestLow)
        return g_highestHigh - g_lowestLow;
    return 0.0;
}

//+------------------------------------------------------------------+
//| Factor from step:  Factor = Range / (Step * 2)                  |
//| (Inverse of CalculateFactorStepSize - pure round-trip pair)     |
//+------------------------------------------------------------------+
double CalculateFactorFromStep(const double range, const double step)
{
    if(range <= 0 || step <= 0) return 0.0;
    return range / (step * 2.0);
}

//+------------------------------------------------------------------+
//| UNIFIED AUTO step size for a basis - SINGLE SOURCE OF TRUTH     |
//|                                                                  |
//| Mirrors the reference logic used by GetModeDefinition:          |
//|   - CONTROL/SS/LS/TH/TRIGGER: adapted current-TF TH * multiplier|
//|     (equivalent to data.thValue / shortStep / longStep family,  |
//|      since data.thValue is itself the adapted current-TF TH)    |
//|   - PATTERN:   adapted TH of the Pattern (4x) timeframe         |
//|   - STRUCTURE: adapted TH of the Structure (16x) timeframe      |
//|   - COMBO:     combo step size from current combo config        |
//+------------------------------------------------------------------+
double GetFactorModeAutoStepSize(const double basePrice, const ENUM_FACTOR_AUTO_BASIS basis)
{
    if(basePrice <= 0) return 0.0;
    int digits = GetCachedDigits();

    // Bases derived from adapted current-TF TH
    if(basis == FACTOR_BASIS_CONTROL || basis == FACTOR_BASIS_SS ||
       basis == FACTOR_BASIS_LS     || basis == FACTOR_BASIS_TH ||
       basis == FACTOR_BASIS_TRIGGER) {
        double thVal = CalculateTH(basePrice, digits, GetTimeframeTH());
        if(thVal <= 0) return 0.0;
        thVal = GetAdaptedStepSize(thVal);
        if(thVal <= 0) return 0.0;
        return thVal * GetFactorBasisMultiplier(basis);
    }

    if(basis == FACTOR_BASIS_PATTERN) {
        double patPct = GetPatternTH();
        if(patPct <= 0) patPct = GetTimeframeTH() * 4.0;
        double step = CalculateTH(basePrice, digits, patPct);
        if(step <= 0) return 0.0;
        return GetAdaptedStepSize(step);
    }

    if(basis == FACTOR_BASIS_STRUCTURE) {
        string strTF = GetStructureTimeframeForCurrent();
        double strPct = CalculateTimeframeTH(strTF);
        if(strPct <= 0) strPct = GetTimeframeTH() * 16.0;
        double step = CalculateTH(basePrice, digits, strPct);
        if(step <= 0) return 0.0;
        return GetAdaptedStepSize(step);
    }

    if(basis == FACTOR_BASIS_COMBO) {
        return CalculateComboStepSize(basePrice);
    }

    // Unknown basis: fall back to SS
    return GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_SS);
}

//+------------------------------------------------------------------+
//| Primary step price (price units) under current Factor settings  |
//|                                                                  |
//| DIRECT:  the value IS the step size                              |
//|   override > 0  -> override                                     |
//|   MANUAL        -> inpFactorValue                               |
//|   AUTO          -> unified auto step for selected basis          |
//|                                                                  |
//| CLASSIC: the value is a Factor number, step derived from it      |
//+------------------------------------------------------------------+
double GetFactorModePrimaryStepPrice(const double basePrice)
{
    bool useDirect = (inpFactorDisplayMode == FACTOR_DISPLAY_DIRECT);
    if(useDirect) {
        if(g_factorValueOverride > 0) return g_factorValueOverride;
        if(inpFactorMode == FACTOR_MODE_MANUAL) return inpFactorValue;
        return GetFactorModeAutoStepSize(basePrice, inpFactorAutoBasis);
    }

    // CLASSIC MODE
    double factorValue = (g_factorValueOverride > 0) ? g_factorValueOverride :
                         ((inpFactorMode == FACTOR_MODE_MANUAL) ? inpFactorValue : GetDefaultFactorValue(basePrice));
    return CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
}

//+------------------------------------------------------------------+
//| Compute BOTH factor (for display) and step (for drawing)        |
//| under the current settings. This is the single entry point used |
//| by mode definition, status labels and label formatting.         |
//+------------------------------------------------------------------+
void ComputeFactorModeValues(const double basePrice, double &factorValue, double &stepPrice)
{
    factorValue = 0;
    stepPrice = 0;
    double range = GetFactorRange();
    bool useDirect = (inpFactorDisplayMode == FACTOR_DISPLAY_DIRECT);

    if(useDirect) {
        stepPrice = GetFactorModePrimaryStepPrice(basePrice);
        factorValue = CalculateFactorFromStep(range, stepPrice);
        if(factorValue <= 0) factorValue = 50.0; // Fallback
    } else {
        if(g_factorValueOverride > 0) factorValue = g_factorValueOverride;
        else if(inpFactorMode == FACTOR_MODE_MANUAL) factorValue = inpFactorValue;
        else factorValue = GetDefaultFactorValue(basePrice);
        stepPrice = CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
    }

    factorValue = NormalizeDouble(MathMax(0.01, MathMin(10000, factorValue)), 2);
}

//+------------------------------------------------------------------+
//| DEBUG-ONLY invariant checks (round-trip + basis consistency)    |
//| Runs only in DEBUG builds (guarded by ENABLE_ASSERTIONS).       |
//+------------------------------------------------------------------+
void FactorModeSanityCheck()
{
#ifdef ENABLE_ASSERTIONS
    // Round-trip: Step = Range / (Factor*2)  ->  Factor = Range / (Step*2)
    double testHigh = 1.7;
    double testLow  = 0.1;
    double testRange = testHigh - testLow;
    double testFactor = 25.0;
    double testStep = CalculateFactorStepSize(testHigh, testLow, testFactor);
    if(testStep > 0) {
        double back = CalculateFactorFromStep(testRange, testStep);
        ASSERT(MathAbs(back - testFactor) < 0.01, "Factor/Step round-trip failed");
        ASSERT(MathAbs(testStep * 2.0 * testFactor - testRange) < testStep * 0.01, "Step*2*Factor != Range");
    }

    // Basis consistency on the current-TF family
    double basePrice = 1.1;
    double th = GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_TH);
    if(th > 0) {
        double ss    = GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_SS);
        double ls    = GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_LS);
        double ctrl  = GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_CONTROL);
        double trig  = GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_TRIGGER);
        ASSERT(MathAbs(ss - th * 1.5) < th * 0.001, "SS != 1.5*TH");
        ASSERT(MathAbs(ls - th * 2.0) < th * 0.001, "LS != 2.0*TH");
        ASSERT(MathAbs(ctrl - (ss + ls) / 2.0) < th * 0.001, "CONTROL != (SS+LS)/2");
        ASSERT(MathAbs(trig - th) < th * 0.001, "TRIGGER != TH");
        ASSERT(GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_PATTERN) > 0, "PATTERN step invalid");
        ASSERT(GetFactorModeAutoStepSize(basePrice, FACTOR_BASIS_STRUCTURE) > 0, "STRUCTURE step invalid");
    }
#endif
}

#endif // FACTOR_MODE_MQH
