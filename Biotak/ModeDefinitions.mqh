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
    cfg.fallbackColor = clrDodgerBlue;
    cfg.fallbackStyle = STYLE_DOT;
    cfg.fallbackWidth = 1;
    cfg.midpointColor = GetTriggerRenderColor();
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
            double factorValue = 0;
            double directStepSize = 0;
            bool useDirect = (inpFactorDisplayMode == FACTOR_DISPLAY_DIRECT);
            
            // Get override value first if set
            double overrideFactor = g_factorValueOverride;
            
            if(useDirect) {
                // ============================================================
                // DIRECT MODE: The value IS the step size directly
                // Factor is calculated internally for display only
                // ============================================================
                if(overrideFactor > 0) {
                    // Override is used as step size directly
                    directStepSize = overrideFactor;
                } else if(inpFactorMode == FACTOR_MODE_MANUAL) {
                    // Manual: inpFactorValue IS the step size
                    directStepSize = inpFactorValue;
                } else {
                    // Auto: Get step size from the chosen basis
                    double range = g_highestHigh - g_lowestLow;
                    switch(inpFactorAutoBasis) {
                        case FACTOR_BASIS_SS:
                            directStepSize = data.shortStep;
                            break;
                        case FACTOR_BASIS_LS:
                            directStepSize = data.longStep;
                            break;
                        case FACTOR_BASIS_TH:
                            directStepSize = data.thValue;
                            break;
                        case FACTOR_BASIS_CONTROL:
                            directStepSize = (data.shortStep + data.longStep) / 2.0;
                            break;
                        case FACTOR_BASIS_TRIGGER:
                        {
                            double tfPercentage = GetTimeframeTH();
                            directStepSize = CalculateTH(dailyClosePrice, GetCachedDigits(), tfPercentage);
                            directStepSize = GetAdaptedStepSize(directStepSize);
                            break;
                        }
                        case FACTOR_BASIS_PATTERN:
                        {
                            double patPercentage = GetPatternTH();
                            if(patPercentage <= 0) patPercentage = GetTimeframeTH() * 4.0;
                            directStepSize = CalculateTH(dailyClosePrice, GetCachedDigits(), patPercentage);
                            directStepSize = GetAdaptedStepSize(directStepSize);
                            break;
                        }
                        case FACTOR_BASIS_STRUCTURE:
                        {
                            string strTF = GetStructureTimeframeForCurrent();
                            double strPercentage = CalculateTimeframeTH(strTF);
                            if(strPercentage <= 0) strPercentage = GetTimeframeTH() * 16.0;
                            directStepSize = CalculateTH(dailyClosePrice, GetCachedDigits(), strPercentage);
                            directStepSize = GetAdaptedStepSize(directStepSize);
                            break;
                        }
                        case FACTOR_BASIS_COMBO:
                            directStepSize = CalculateComboStepSize(dailyClosePrice);
                            break;
                        default:
                            directStepSize = data.shortStep;
                            break;
                    }
                    
                    // Validate step size
                    if(directStepSize <= 0) {
                        directStepSize = data.shortStep; // Fallback
                    }
                }
                
                // Calculate factor value for display: factor = range / (stepSize * 2)
                double range = g_highestHigh - g_lowestLow;
                if(range > 0 && directStepSize > 0) {
                    factorValue = range / (directStepSize * 2.0);
                } else {
                    factorValue = 50.0;
                }
                
            } else {
                // ============================================================
                // CLASSIC MODE (existing behavior): Factor is the primary value
                // ============================================================
                if(overrideFactor > 0) factorValue = overrideFactor;
                else if(inpFactorMode == FACTOR_MODE_MANUAL) factorValue = inpFactorValue;
                else { // Auto mode
                    if (inpFactorAutoBasis == FACTOR_BASIS_SS) {
                        double range = g_highestHigh - g_lowestLow;
                        double targetStep = data.shortStep;
                        if (range > 0 && targetStep > 0) {
                            factorValue = range / (targetStep * 2.0);
                        } else {
                            factorValue = 50.0;
                        }
                    } else if (inpFactorAutoBasis == FACTOR_BASIS_LS) {
                        double range = g_highestHigh - g_lowestLow;
                        double targetStep = data.longStep;
                        if (range > 0 && targetStep > 0) {
                            factorValue = range / (targetStep * 2.0);
                        } else {
                            factorValue = 50.0;
                        }
                    } else {
                        factorValue = GetDefaultFactorValue(dailyClosePrice);
                    }
                }
            }
            
            factorValue = NormalizeDouble(MathMax(0.01, MathMin(10000, factorValue)), 2);
            UpdateFactorLabel(factorValue, directStepSize);
            
#ifndef BUILD_LITE
            if(inpEnableHarmonicPattern) {
                def.config = BuildFactorHarmonicConfig(objectPrefix);
                // For DIRECT mode: baseStep = directStepSize (already in price units)
                // For CLASSIC mode: baseStep = CalculateFactorStepSize
                double baseStep = (useDirect && directStepSize > 0) ? 
                                   directStepSize : 
                                   CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
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
                // For DIRECT mode: factorStep = directStepSize (already in price units)
                // For CLASSIC mode: factorStep = CalculateFactorStepSize
                double factorStep = (useDirect && directStepSize > 0) ? 
                                     directStepSize : 
                                     CalculateFactorStepSize(g_highestHigh, g_lowestLow, factorValue);
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
