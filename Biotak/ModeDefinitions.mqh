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
            // Single source of truth: compute step (for drawing) and
            // factor (for display) under the current settings.
            // NOTE: No label side-effects here - the drawing factory must
            // stay pure. Info labels are driven by hotkeys (E/W/1/2/3/4/G)
            // and refreshed in real time by RefreshVisibleStatusLabels().
            double factorValue = 0;
            double directStepSize = 0;
            ComputeFactorModeValues(dailyClosePrice, factorValue, directStepSize);
            
#ifndef BUILD_LITE
            if(inpEnableHarmonicPattern) {
                def.config = BuildFactorHarmonicConfig(objectPrefix);
                double baseStep = (directStepSize > 0) ? 
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
                double factorStep = (directStepSize > 0) ? 
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
