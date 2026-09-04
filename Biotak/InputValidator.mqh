  //+------------------------------------------------------------------+
//|                                              InputValidator.mqh    |
//|                                                                  |
//| Logic for validating user input parameters                       |
//+------------------------------------------------------------------+
#ifndef INPUT_VALIDATOR_MQH
#define INPUT_VALIDATOR_MQH
#property copyright "  Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link      "@biotak"
#property strict

//+------------------------------------------------------------------+
//| Validate all input parameters                                    |
//| Returns INIT_SUCCEEDED or error code                             |
//+------------------------------------------------------------------+
int ValidateInputs()
{
    //                                                                
    // CRITICAL VALIDATIONS (Must Pass)
    //                                                                
    
    // 1. Base Price Threshold Percent (0.001-10.0) with epsilon check
    if(inpBasePriceThresholdPercent < 0.0001 || inpBasePriceThresholdPercent > 10.0) {
        Print("  ERROR: Base Price Threshold (", DoubleToString(inpBasePriceThresholdPercent, 3), ") out of range");
        Print("   Valid range: 0.0001 - 10.0 (epsilon-safe)");
        Print("   Recommended: 0.066 (default)");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // SECURITY: Additional check for extreme precision loss
    if(inpBasePriceThresholdPercent < 0.001) {
        Print("   WARNING: Base Price Threshold (", DoubleToString(inpBasePriceThresholdPercent, 6), ") is very small");
        Print("   May cause floating-point precision issues");
    }
    
    // 2. Harmonic Ratio (1.01-2.0)
#ifndef BUILD_LITE
    if(inpEnableHarmonicPattern) {
        if(inpHarmonicRatio < 1.01 || inpHarmonicRatio > 2.0) {
            Print("  ERROR: Harmonic Ratio (", DoubleToString(inpHarmonicRatio, 3), ") out of range");
            Print("   Valid range: 1.01 - 2.0");
            Print("   Recommended: 1.333 (Golden), 1.5 (Medium), 2.0 (Max)");
            return INIT_PARAMETERS_INCORRECT;
        }
    }
#endif
    
    // 3. Structure Base Multiplier (2-9)
    // NOTE: ENUM_STRUCTURE_BASE_MULTIPLIER enforces valid range at UI level
    // However, presets or programmatic changes might bypass this, so we auto-correct
    int baseMultiplier = (int)inpStructureBase;
    
    // AUTO-CORRECTION: If invalid value detected, auto-correct to default (3)
    if(baseMultiplier < 2 || baseMultiplier > 9) {
        Print("   WARNING: Structure Base Multiplier (", baseMultiplier, ") is invalid");
        Print("   Valid range: 2 - 9");
        Print("      AUTO-CORRECTING to default: 3");
        Print("   Reason: Value ", baseMultiplier, " would make structure levels meaningless");
        
        // Note: We cannot modify input parameter directly in MQL4
        // The validation functions will use fallback value (3) throughout the code
        // Indicator will continue to work with corrected value
        
        // DO NOT return error - let indicator work with auto-corrected value
        // All functions already have fallback logic: if(baseMultiplier < 2 || baseMultiplier > 9) baseMultiplier = 3;
    }
    
    // Success: Valid base multiplier or auto-corrected
    if(baseMultiplier >= 2 && baseMultiplier <= 9) {
        Print("  Structure Base Multiplier: ", baseMultiplier);
    }
    
    // 4. Font Size (1-100)
    if(inpFontSize <= 0 || inpFontSize > 100) {
        Print("  ERROR: Font Size (", inpFontSize, ") out of range");
        Print("   Valid range: 1 - 100");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 5. Line Widths (1-10)
    if(inpCustomPriceLevelWidth <= 0 || inpCustomPriceLevelWidth > 10) {
        Print("  ERROR: Custom Price Line Width (", inpCustomPriceLevelWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpHighWidth <= 0 || inpHighWidth > 10) {
        Print("  ERROR: High Line Width (", inpHighWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpLowWidth <= 0 || inpLowWidth > 10) {
        Print("  ERROR: Low Line Width (", inpLowWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpTriggerWidth <= 0 || inpTriggerWidth > 10) {
        Print("  ERROR: Trigger Level Width (", inpTriggerWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 6. Spacing Values (non-negative)
    if(inpInitialX < 0 || inpInitialY < 0) {
        Print("  ERROR: Initial position values must be non-negative");
        Print("   X: ", inpInitialX, ", Y: ", inpInitialY);
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpLabelSpacing < 0) {
        Print("  ERROR: Label spacing must be non-negative");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 7. Max Levels (positive; one input controls both sides and all modes)
    if(inpMaxLevels <= 0) {
        Print("  ERROR: Max Levels must be positive");
        Print("   Value: ", inpMaxLevels);
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 8. Label Width (positive)
    if(inpMaxLabelWidth <= 0) {
        Print("  ERROR: Max Label Width must be positive");
        Print("   Value: ", inpMaxLabelWidth);
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 9. TH3 Zone Transparency (0-100) — TH3TOOL-OFF: retired with the tool
    // TH3TOOL-OFF:
    //#ifndef BUILD_LITE
    //    if(inpTH3ZoneTransparency < 0 || inpTH3ZoneTransparency > 100) {
    //        Print("  ERROR: TH3 Zone Transparency (", inpTH3ZoneTransparency, ") out of range");
    //        Print("   Valid range: 0 - 100");
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //
    //    // 9.1 TH3 Zone Height Percent (1-100)
    //    if(inpTH3ZoneHeightPercent < 1.0 || inpTH3ZoneHeightPercent > 100.0) {
    //        Print("  ERROR: TH3 Zone Height Percent (", inpTH3ZoneHeightPercent, ") out of range");
    //        Print("   Valid range: 1.0 - 100.0");
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //#endif
    
    // 9.2 Mid-Zone Height Percent (1-100)
    if(inpMidZoneHeightPercent < 1.0 || inpMidZoneHeightPercent > 100.0) {
        Print("  ERROR: Mid-Zone Height Percent (", inpMidZoneHeightPercent, ") out of range");
        Print("   Valid range: 1.0 - 100.0");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 9.3 Mid-Zone Transparency (0-100)
    if(inpMidZoneTransparency < 0 || inpMidZoneTransparency > 100) {
        Print("  ERROR: Mid-Zone Transparency (", inpMidZoneTransparency, ") out of range");
        Print("   Valid range: 0 - 100");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 9.4 Mid-Zone Border Width (1-5)
    if(inpMidZoneBorderWidth < 1 || inpMidZoneBorderWidth > 5) {
        Print("  ERROR: Mid-Zone Border Width (", inpMidZoneBorderWidth, ") out of range");
        Print("   Valid range: 1 - 5");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // 9.5 Zone Styles (validated by ENUM at compile time)
    // inpMidZoneStyle, inpTH3ZoneStyle are validated by ENUM_ZONE_STYLE
    // No runtime validation needed - compiler enforces valid values
    
    // 10. Historical Periods (non-negative)
    if(inpHistoricalPeriods < 0) {
        Print("  ERROR: Historical Periods must be non-negative (0=Auto)");
        Print("   Value: ", inpHistoricalPeriods);
        return INIT_PARAMETERS_INCORRECT;
    }
    
    //                                                                
    // PERFORMANCE WARNINGS
    //                                                                
    
    // Safety: Limit max levels to prevent performance issues
    if(inpMaxLevels > MAX_SAFE_LEVELS) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   WARNING: inpMaxLevels (", inpMaxLevels, ") exceeds MAX_SAFE_LEVELS (", MAX_SAFE_LEVELS, ")");
        Print("   Please reduce inpMaxLevels to ", MAX_SAFE_LEVELS, " or less for optimal performance");
        #endif
    }
    
    //                                                                
    // HARMONIC PATTERN VALIDATIONS
    //                                                                
#ifndef BUILD_LITE
    if(inpEnableHarmonicPattern) {
        // Warning if ratio is too close to 1.0 (subtle alternation)
        if(inpHarmonicRatio < 1.05) {
            Print("   WARNING: Harmonic Ratio (", DoubleToString(inpHarmonicRatio, 3), 
                  ") is very close to 1.0");
            Print("   Alternation will be subtle. Consider using 1.333 or higher for clearer pattern");
        }
        
        // Validate Harmonic colors are different
        if(inpHarmonicBaseColor == inpHarmonicLargeColor) {
            Print("   WARNING: Base and Large step colors are identical");
            Print("   Consider using different colors for better visual distinction");
        }
        
        // Validate Harmonic widths
        if(inpHarmonicBaseWidth <= 0 || inpHarmonicBaseWidth > 10) {
            Print("  ERROR: Invalid Harmonic Base Width (", inpHarmonicBaseWidth, "). Must be between 1 and 10");
            return INIT_PARAMETERS_INCORRECT;
        }
        if(inpHarmonicLargeWidth <= 0 || inpHarmonicLargeWidth > 10) {
            Print("  ERROR: Invalid Harmonic Large Width (", inpHarmonicLargeWidth, "). Must be between 1 and 10");
            return INIT_PARAMETERS_INCORRECT;
        }
        
        // Conflict warnings
        if(inpTHStartPointType == TH_START_POINT_CUSTOM_PRICE) {
            Print("   WARNING: Harmonic Pattern with Custom Price Mode");
            Print("   Harmonic always uses Historical High/Low midpoint as center");
            Print("   Custom Price will be ignored in Harmonic Mode");
        }
        
        if(inpShowStructure || inpShowTrigger) {
            Print("   INFO: Harmonic Pattern Priority");
            Print("   Harmonic colors will override Structure/Trigger colors");
        }
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("  Harmonic Pattern Validation: PASSED");
        Print("   Ratio: ", DoubleToString(inpHarmonicRatio, 3));
        #endif
    }
#endif
    
    //                                                                
    // FACTOR STEP VALIDATIONS
    //                                                                
    
    //                                                                
    // FACTOR STEP VALIDATIONS
    //                                                                
    
    // SECURITY FIX: Validate factor value
    if(inpFactorValue < 0.01 || inpFactorValue > 10000) {
        Print("  ERROR: Factor Value (", DoubleToString(inpFactorValue, 2), ") out of range");
        Print("   Valid range: 0.01 - 10000");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // SECURITY FIX: Validate harmonic ratio
#ifndef BUILD_LITE
    if(inpEnableHarmonicPattern) {
        if(inpHarmonicRatio < 1.01 || inpHarmonicRatio > 2.0) {
            Print("  ERROR: Harmonic Ratio (", DoubleToString(inpHarmonicRatio, 3), ") out of range");
            Print("   Valid range: 1.01 - 2.0");
            Print("   Recommended: 1.333 (Golden), 1.5 (Medium), 2.0 (Max)");
            return INIT_PARAMETERS_INCORRECT;
        }
    }
#endif
    
    if(inpFactorAdjustStep <= 0 || inpFactorAdjustStep > 100) {
        Print("  ERROR: Factor Adjust Step (", DoubleToString(inpFactorAdjustStep, 2), ") out of range");
        Print("   Valid range: 0.01 - 100");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpFactorLevelWidth <= 0 || inpFactorLevelWidth > 10) {
        Print("  ERROR: Factor Level Width (", inpFactorLevelWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    //                                                                
    // STEP MODE VALIDATIONS
    //                                                                
    
    // SS/LS Step Mode
    if(inpSSLevelWidth <= 0 || inpSSLevelWidth > 10) {
        Print("  ERROR: SS Level Width (", inpSSLevelWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpLSLevelWidth <= 0 || inpLSLevelWidth > 10) {
        Print("  ERROR: LS Level Width (", inpLSLevelWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Combo Step Mode
    if(inpComboLevelWidth <= 0 || inpComboLevelWidth > 10) {
        Print("  ERROR: Combo Level Width (", inpComboLevelWidth, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // TH3TOOL-OFF: TH3 TOOL + AB=CD VALIDATIONS retired with the tool —
    // TH3TOOL-OFF:
    //#ifndef BUILD_LITE
    //    if(inpTH3BaseStepPercent < 0.1 || inpTH3BaseStepPercent > 120.0) {
    //        Print("  ERROR: TH3 Base Step Percent (", DoubleToString(inpTH3BaseStepPercent, 3), ") out of range");
    //        Print("   Valid range: 0.1 - 120.0 (extended range)");
    //        Print("   Recommended: 28.125 (default)");
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //    if(inpTH3Width <= 0 || inpTH3Width > 10) {
    //        Print("  ERROR: TH3 Level Width (", inpTH3Width, ") out of range");
    //        Print("   Valid range: 1 - 10");
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //    if(inpABCDWidth <= 0 || inpABCDWidth > 10) {
    //        Print("  ERROR: AB=CD Line Width (", inpABCDWidth, ") out of range");
    //        Print("   Valid range: 1 - 10");
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //    if(inpTH3ZoneBorderWidth <= 0 || inpTH3ZoneBorderWidth > 10) {
    //        Print("  ERROR: TH3 Zone Border Width (", inpTH3ZoneBorderWidth, ") out of range");
    //        Print("   Valid range: 1 - 10");
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //    if(inpABCDInfoFontSize <= 0 || inpABCDInfoFontSize > 100) {
    //        Print("  ERROR: AB=CD Info Font Size (", inpABCDInfoFontSize, ") out of range");
    //        Print("   Valid range: 1 - 100");
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //    if(inpABCDInfoXDistance < 0 || inpABCDInfoYDistance < 0) {
    //        Print("  ERROR: AB=CD Info position must be non-negative");
    //        Print("   X: ", inpABCDInfoXDistance, ", Y: ", inpABCDInfoYDistance);
    //        return INIT_PARAMETERS_INCORRECT;
    //    }
    //#endif
    
    //                                                                
    // STRUCTURE LEVEL VALIDATIONS
    //                                                                
    
    // Validate all 5 structure level widths
    if(inpStructureL1Width <= 0 || inpStructureL1Width > 10) {
        Print("  ERROR: Structure Level 1 Width (", inpStructureL1Width, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpStructureL2Width <= 0 || inpStructureL2Width > 10) {
        Print("  ERROR: Structure Level 2 Width (", inpStructureL2Width, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpStructureL3Width <= 0 || inpStructureL3Width > 10) {
        Print("  ERROR: Structure Level 3 Width (", inpStructureL3Width, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpStructureL4Width <= 0 || inpStructureL4Width > 10) {
        Print("  ERROR: Structure Level 4 Width (", inpStructureL4Width, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpStructureL5Width <= 0 || inpStructureL5Width > 10) {
        Print("  ERROR: Structure Level 5 Width (", inpStructureL5Width, ") out of range");
        Print("   Valid range: 1 - 10");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    //                                                                
    // MODE LABEL VALIDATIONS
    //                                                                
    
    if(inpModeLabelFontSize <= 0 || inpModeLabelFontSize > 100) {
        Print("  ERROR: Mode Label Font Size (", inpModeLabelFontSize, ") out of range");
        Print("   Valid range: 1 - 100");
        return INIT_PARAMETERS_INCORRECT;
    }
    if(inpModeLabelXDistance < 0 || inpModeLabelYDistance < 0) {
        Print("  ERROR: Mode Label position must be non-negative");
        Print("   X: ", inpModeLabelXDistance, ", Y: ", inpModeLabelYDistance);
        return INIT_PARAMETERS_INCORRECT;
    }
    
    //                                                                
    // COMBO MODE CONFIGURATION VALIDATION
    //                                                                
    
    if(!ValidateComboModeConfiguration()) return INIT_PARAMETERS_INCORRECT;
    
    //                                                                
    // SUCCESS
    //                                                                
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  All input validations passed successfully");
    #endif
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Validate Combo Mode Configuration and Print User Guidance        |
//|                    Combo Mode                                    |
//|                                                                  |
//| CRITICAL: This function provides user-visible guidance           |
//| Shows which settings are active/ignored based on selected mode   |
//+------------------------------------------------------------------+
// BUG FIX (Phase 1I): Return bool and validate enums instead of just logging.
// Also runs even when ENABLE_DEBUG_LOGS is off - critical validations must always run.
bool ValidateComboModeConfiguration() {
    // Validate inpComboMode is in valid range
    if(inpComboMode < COMBO_MODE_PRESET || inpComboMode > COMBO_MODE_ADVANCED) {
        Print("  ERROR: Invalid inpComboMode=", (int)inpComboMode,
                          " (valid range: ", (int)COMBO_MODE_PRESET, "..", (int)COMBO_MODE_ADVANCED, ")");
        return false;
    }
    // Validate inpComboPreset is in valid range
    if(inpComboPreset < COMBO_PRESET_BALANCED_MEDIUM || inpComboPreset > COMBO_PRESET_RATIO_4_3) {
        Print("  ERROR: Invalid inpComboPreset=", (int)inpComboPreset,
                          " (valid range: ", (int)COMBO_PRESET_BALANCED_MEDIUM, "..",
                          (int)COMBO_PRESET_RATIO_4_3, ")");
        return false;
    }

    #ifdef ENABLE_DEBUG_LOGS
    Print("====================");
    Print("   COMBO MODE CONFIGURATION VALIDATION");
    Print("====================");
    
    //
    // SHOW SELECTED MODE
    //
    string modeName = "";
    switch(inpComboMode) {
        case COMBO_MODE_PRESET: modeName = "Preset"; break;
        case COMBO_MODE_ADVANCED: modeName = "Advanced"; break;
        default: modeName = "UNKNOWN"; break;
    }
    
    Print("  SELECTED MODE: ", modeName);
    Print("====================");
    
    //
    // MODE-SPECIFIC VALIDATION AND GUIDANCE
    //
    
    if(inpComboMode == COMBO_MODE_PRESET) {
        Print("   ACTIVE SETTINGS (Preset Mode):");
        Print("     Selected Preset: ", EnumToString(inpComboPreset));
        Print("");
        Print("  IGNORED SETTINGS:");
        Print("     Advanced Mode settings (Topology, Components, Operators)");
        Print("");
        Print("    FLOW: Select Preset   Automatic calculation   Result");
        
    } else if(inpComboMode == COMBO_MODE_ADVANCED) {
        Print("   ACTIVE SETTINGS (Advanced Mode):");
        Print("     Component 1: ", EnumToString(inpComboComp1TF), " / ", EnumToString(inpComboComp1Step));
        Print("     Operation: ", EnumToString(inpComboOp1));
        if(inpComboComp2Enabled) {
            Print("     Component 2: ", EnumToString(inpComboComp2TF), " / ", EnumToString(inpComboComp2Step));
        }
        Print("");
        Print("  IGNORED SETTINGS:");
        Print("     Preset Mode settings (inpComboPreset)");
        Print("");
    }
    
    Print("====================");
    #endif
    return true;
}

#endif // INPUT_VALIDATOR_MQH

