//+------------------------------------------------------------------+
//|                                              ModeDefinitions.mqh |
//|                                  Copyright 2026, Biotak Project  |
//|                     Centralized Drawing Mode Definitions         |
//+------------------------------------------------------------------+
#ifndef MODE_DEFINITIONS_MQH
#define MODE_DEFINITIONS_MQH

#include "ConstantsAndEnums.mqh"
#include "LevelPipeline.mqh"
#include "THCalculations.mqh"
#include "PropertiesAndInputs.mqh"

//+------------------------------------------------------------------+
//| MODE DEFINITION: Complete parameters for a drawing mode          |
//+------------------------------------------------------------------+
struct SModeDefinition {
    ENUM_STEP_CALCULATION_MODE mode;
    SModeConfig config;
    double stepSizes[2]; // Fixed size for simplicity in MT4
    int stepSizeCount;
    ENUM_LEVEL_STEP_MODE stepMode;
    ENUM_CLASSIFY_MODE classifyMode;
    bool lsFirst;
    bool success;
};

//+------------------------------------------------------------------+
//| MODE CONFIG BUILDERS: Centralized configuration logic            |
//+------------------------------------------------------------------+

SModeConfig BuildSSLSConfig(const string objectPrefix)
{
    SModeConfig cfg = BuildModeConfig(objectPrefix, "SSLS");
    cfg.fallbackColor = inpSSLevelColor;
    cfg.fallbackStyle = inpSSLevelStyle;
    cfg.fallbackWidth = inpSSLevelWidth;
    cfg.fallbackColor2 = inpLSLevelColor;
    cfg.fallbackStyle2 = inpLSLevelStyle;
    cfg.fallbackWidth2 = inpLSLevelWidth;
    cfg.midpointColor = inpLSLevelColor;
    cfg.midpointStyle = inpLSLevelStyle;
    cfg.midpointWidth = inpLSLevelWidth;
    return cfg;
}

SModeConfig BuildMConfig(const string objectPrefix)
{
    SModeConfig cfg = BuildModeConfig(objectPrefix, "M");
    cfg.midpointColor = inpMLevelColor;
    cfg.midpointStyle = inpMLevelStyle;
    cfg.midpointWidth = inpMLevelWidth;
    return cfg;
}

SModeConfig BuildMEqualConfig(const string objectPrefix)
{
    SModeConfig cfg = BuildModeConfig(objectPrefix, "MEq");
    cfg.useStepFilter = false;
    cfg.midpointColor = inpMLevelColor;
    cfg.midpointStyle = inpMLevelStyle;
    cfg.midpointWidth = inpMLevelWidth;
    cfg.fallbackColor = inpStructureL1Color;
    cfg.fallbackStyle = inpStructureL1Style;
    cfg.fallbackWidth = inpStructureL1Width;
    return cfg;
}

SModeConfig BuildTPConfig(const string objectPrefix)
{
    return BuildModeConfig(objectPrefix, "TP");
}

SModeConfig BuildComboConfig(const string objectPrefix)
{
    return BuildModeConfig(objectPrefix, "Combo");
}

SModeConfig BuildFactorConfig(const string objectPrefix)
{
    SModeConfig cfg = BuildModeConfig(objectPrefix, "Factor");
    cfg.useObjPropBack = true;
    cfg.zOrder = 1;
    cfg.hideLineWhenTriggerOnly = false;
    cfg.fallbackColor = inpFactorLevelColor;
    cfg.fallbackStyle = inpFactorLevelStyle;
    cfg.fallbackWidth = inpFactorLevelWidth;
    cfg.midpointColor = inpFactorLevelColor;
    cfg.midpointStyle = inpFactorLevelStyle;
    cfg.midpointWidth = inpFactorLevelWidth;
    return cfg;
}

SModeConfig BuildFactorHarmonicConfig(const string objectPrefix)
{
    SModeConfig cfg = BuildModeConfig(objectPrefix, "Factor_Harmonic");
    cfg.useObjPropBack = true;
    cfg.hideLineWhenTriggerOnly = false;
    cfg.fallbackColor = inpFactorLevelColor;
    cfg.fallbackStyle = inpFactorLevelStyle;
    cfg.fallbackWidth = inpFactorLevelWidth;
    cfg.midpointColor = inpFactorLevelColor;
    cfg.midpointStyle = inpFactorLevelStyle;
    cfg.midpointWidth = inpFactorLevelWidth;
    return cfg;
}

SModeConfig BuildTHConfig(const string objectPrefix)
{
    SModeConfig cfg = BuildModeConfig(objectPrefix, "TH_Level");
    cfg.fallbackColor = inpCLevelColor;
    cfg.fallbackStyle = inpCLevelStyle;
    cfg.fallbackWidth = inpCLevelWidth;
    cfg.midpointColor = inpTriggerColor;
    cfg.midpointStyle = inpTriggerStyle;
    cfg.midpointWidth = inpTriggerWidth;
    return cfg;
}

//+------------------------------------------------------------------+
//| FACTORY: Get definition for a specific mode                      |
//+------------------------------------------------------------------+
SModeDefinition GetModeDefinition(
    const ENUM_STEP_CALCULATION_MODE mode,
    const string objectPrefix,
    SCommonStepData &data,
    const double dailyClosePrice)
{
    SModeDefinition def;
    def.mode = mode;
    def.success = false;
    def.stepSizeCount = 0;
    def.stepMode = LEVEL_STEP_UNIFORM;
    def.classifyMode = CLASSIFY_STANDARD;
    def.lsFirst = false;
    
    switch(mode) {
        case SS_LS_STEP:
        {
            def.config = BuildSSLSConfig(objectPrefix);
            def.stepSizes[0] = data.shortStep;
            def.stepSizes[1] = data.longStep;
            def.stepSizeCount = 2;
            def.stepMode = LEVEL_STEP_CUMULATIVE;
            def.classifyMode = CLASSIFY_ALTERNATING;
            def.lsFirst = inpLSFirst;
            def.success = true;
            break;
        }
            
        case M_STEP:
        {
            double controlValue = CalculateControlValue(data.shortStep, data.longStep);
            if(inpMStepBasisType == MSTEP_BASIS_C_BASED) {
                def.config = BuildMConfig(objectPrefix);
                def.stepSizes[0] = controlValue;
                def.stepSizeCount = 1;
                def.stepMode = LEVEL_STEP_UNIFORM;
                def.classifyMode = CLASSIFY_MMODE;
            } else {
                def.config = BuildMEqualConfig(objectPrefix);
                double mDistance = CalculateMDistance(controlValue);
                def.stepSizes[0] = mDistance;
                def.stepSizeCount = 1;
                def.stepMode = LEVEL_STEP_UNIFORM;
                def.classifyMode = CLASSIFY_STANDARD;
            }
            def.success = true;
            break;
        }
        
        case TP_STEP:
        {
            def.config = BuildTPConfig(objectPrefix);
            double eValue = CalculateEStep(data.thValue);
            double tpValue = CalculateTPStep(eValue);
            def.stepSizes[0] = tpValue;
            def.stepSizeCount = 1;
            def.stepMode = LEVEL_STEP_UNIFORM;
            def.classifyMode = CLASSIFY_STANDARD;
            def.success = true;
            break;
        }
            
        case COMBO_STEP:
        {
            double comboStep = CalculateComboStepSize(dailyClosePrice);
            if(comboStep > 0) {
                def.config = BuildComboConfig(objectPrefix);
                def.stepSizes[0] = comboStep;
                def.stepSizeCount = 1;
                def.stepMode = LEVEL_STEP_UNIFORM;
                def.classifyMode = CLASSIFY_STANDARD;
                def.success = true;
            }
            break;
        }
        
        case FACTOR_STEP:
        {
            double factorValue;
            if(g_factorValueOverride > 0) factorValue = g_factorValueOverride;
            else if(inpFactorMode == FACTOR_MODE_MANUAL) factorValue = inpFactorValue;
            else factorValue = GetDefaultFactorValue(dailyClosePrice);
            
            factorValue = NormalizeDouble(MathMax(0.01, MathMin(10000, factorValue)), 2);
            UpdateFactorLabel(factorValue);
            
#ifndef BUILD_LITE
            if(inpEnableHarmonicPattern) {
                def.config = BuildFactorHarmonicConfig(objectPrefix);
                double baseStep = CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
                if(baseStep > 0) {
                    def.stepSizes[0] = baseStep;
                    def.stepSizes[1] = baseStep * inpHarmonicRatio;
                    def.stepSizeCount = 2;
                    def.stepMode = LEVEL_STEP_CUMULATIVE;
                    def.classifyMode = CLASSIFY_STANDARD;
                    def.success = true;
                }
            } else {
#endif
                def.config = BuildFactorConfig(objectPrefix);
                double factorStep = CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
                if(factorStep > 0) {
                    def.stepSizes[0] = factorStep;
                    def.stepSizeCount = 1;
                    def.stepMode = LEVEL_STEP_UNIFORM;
                    def.classifyMode = CLASSIFY_STANDARD;
                    def.success = true;
                }
#ifndef BUILD_LITE
            }
#endif
            break;
        }
        
        case TH_STEP:
        default:
        {
            def.config = BuildTHConfig(objectPrefix);
            def.stepSizes[0] = data.thValue;
            def.stepSizeCount = 1;
            def.stepMode = LEVEL_STEP_UNIFORM;
            def.classifyMode = CLASSIFY_STANDARD;
            def.success = true;
            break;
        }
    }
    
    return def;
}

#endif // MODE_DEFINITIONS_MQH
