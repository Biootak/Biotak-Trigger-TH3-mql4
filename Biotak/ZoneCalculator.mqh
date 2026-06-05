  //+------------------------------------------------------------------+
//|                                               ZoneCalculator.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                                Zone Geometry Calculations         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#include "ConstantsAndEnums.mqh"
#include "ZoneValidator.mqh"

//+------------------------------------------------------------------+
//| Helper: Check if Structure Level (FIXED: Proper hierarchy)      |
//|    :                   (         :                 )            |
//|                                                                  |
//| OLD LOGIC (WRONG):                                               |
//| Step 16 with Base=4   16%4=0   L1   AND 16%16=0   L2          |
//| This causes overlaps!                                            |
//|                                                                  |
//| NEW LOGIC (CORRECT):                                             |
//| Step 16 with Base=4   Highest level only = L2                   |
//| A step is Structure if it's divisible by base BUT NOT by base   |
//| unless it's also divisible by base , then it's higher level     |
//|                                                                  |
//| EXAMPLES with Base=4:                                            |
//| Step 4:  4%4=0, 4%16 0   Structure L1                           |
//| Step 8:  8%4=0, 8%16 0   Structure L1                           |
//| Step 12: 12%4=0, 12%16 0   Structure L1                         |
//| Step 16: 16%4=0, 16%16=0   Structure L2 (not L1)               |
//|                                                                  |
//| @param step The step number to check                            |
//| @param baseMult The power base multiplier (2-9)                 |
//| @return true if this step is ANY structure level                |
//+------------------------------------------------------------------+
bool IsStructureLevel(int step, int baseMult)
{
    if(baseMult <= 1) return true;
    
    // A step is Structure if it's divisible by the base
    // (The specific level L1-L5 is determined elsewhere)
    return (step % baseMult == 0);
}

//+------------------------------------------------------------------+
//| Classify Levels (Active/Inactive, Structure/Trigger)            |
//|                (    /               /     )                      |
//+------------------------------------------------------------------+
void ClassifyLevels(
    const SLevelRawData &levels[],
    const SStyleConfig &config,
    SLevelClassification &outClassifications[])
{
    int count = ArraySize(levels);
    ArrayResize(outClassifications, count);
    
    // OPTIMIZATION: Use centralized cached Digits from PerformanceOptimizations.mqh
    int s_cachedDigits = GetCachedDigits();
    
    // DIAGNOSTIC LOG: Configuration State
    Print("====================");
    Print("   ZONE CLASSIFICATION DIAGNOSTIC");
    Print("====================");
    Print("   Config State:");
    Print("   showStructure: ", config.showStructure ? "TRUE" : "FALSE");
    Print("   showTrigger: ", config.showTrigger ? "TRUE" : "FALSE");
    Print("   baseMultiplier: ", config.baseMultiplier);
    Print("   structColorL1: ", ColorToString(config.structColorL1));
    Print("   triggerColor: ", ColorToString(config.triggerColor));
    Print("====================");
    
    for(int i = 0; i < count; i++) {
        // Determine if Structure Level
        bool isStructure = (levels[i].logicalStep == 0) || 
                          IsStructureLevel(levels[i].logicalStep, config.baseMultiplier);
        
        outClassifications[i].isStructure = isStructure;
        
        // Determine if Active (should be included in calculations)
        bool isActive = false;
        color levelColor = clrNONE;
        int style = STYLE_SOLID;
        int width = 1;
        
        // GOLD FIX: For modes like TP/Combo where baseMultiplier=1,
        // ALL levels should be active (showStructure=true, all are structure)
        if(config.showStructure && isStructure) {
            isActive = true;
            levelColor = config.structColorL1;
            style = config.structStyleL1;
            width = config.structWidthL1;
        }
        else if(config.showTrigger && !isStructure) {
            isActive = true;
            levelColor = config.triggerColor;
            style = config.triggerStyle;
            width = config.triggerWidth;
        }
        
        // FALLBACK: If neither condition met but we have valid config,
        // use structure settings (for TP/Combo modes)
        if(!isActive && config.showStructure) {
            isActive = true;
            levelColor = config.structColorL1;
            style = config.structStyleL1;
            width = config.structWidthL1;
        }
        
        outClassifications[i].isActive = isActive;
        outClassifications[i].levelColor = levelColor;
        outClassifications[i].style = style;
        outClassifications[i].width = width;
        
        // DIAGNOSTIC LOG: Per-Level Classification
        if(isActive) {
            Print("   Level ", i, " [Step ", levels[i].logicalStep, "]:");
            Print("   Price: ", DoubleToString(levels[i].price, s_cachedDigits));
            Print("   Type: ", isStructure ? "STRUCTURE" : "TRIGGER");
            Print("   Color: ", ColorToString(levelColor));
            Print("   Active: ", isActive ? "YES" : "NO");
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    int activeCount = 0;
    int structureCount = 0;
    int triggerCount = 0;
    for(int i = 0; i < count; i++) {
        if(outClassifications[i].isActive) {
            activeCount++;
            if(outClassifications[i].isStructure) structureCount++;
            else triggerCount++;
        }
    }
    Print("====================");
    Print("  ClassifyLevels Summary:");
    Print("   Total Levels: ", count);
    Print("   Active Levels: ", activeCount);
    Print("   Structure Levels: ", structureCount);
    Print("   Trigger Levels: ", triggerCount);
    Print("====================");
    #endif
}

//+------------------------------------------------------------------+
//| Calculate Zone Geometries                                        |
//|                                                                  |
//| CRITICAL FIX: Array bounds validation                            |
//+------------------------------------------------------------------+
void CalculateZoneGeometries(
    const SLevelRawData &levels[],
    const SLevelClassification &classifications[],
    double zoneHeight,
    SZoneGeometry &outGeometries[])
{
    int count = ArraySize(levels);
    int classCount = ArraySize(classifications);
    
    // OPTIMIZATION: Use centralized cached Digits from PerformanceOptimizations.mqh
    int s_cachedDigits = GetCachedDigits();
    
    //                                                                
    // CRITICAL FIX: Array size validation
    //                                                                
    if(classCount != count) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CalculateZoneGeometries: Array size mismatch - levels=", count, 
              ", classifications=", classCount);
        #endif
        ArrayResize(outGeometries, 0);
        return;
    }
    
    // SECURITY: Validate count is within safe limits
    if(count <= 0 || count > MAX_SAFE_LEVELS) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CalculateZoneGeometries: Invalid level count=", count);
        #endif
        ArrayResize(outGeometries, 0);
        return;
    }
    
    ArrayResize(outGeometries, count);
    
    // DIAGNOSTIC LOG: Start
    Print("====================");
    Print("   ZONE GEOMETRY CALCULATION DIAGNOSTIC");
    Print("====================");
    Print("   Input Parameters:");
    Print("   Total Levels: ", count);
    Print("   Zone Height: ", DoubleToString(zoneHeight, s_cachedDigits));
    Print("====================");
    
    // GOLD FIX: Initialize ALL trackers (structure + trigger) with midpoint
    double lastStructurePriceAbove = -1;
    double lastStructurePriceBelow = -1;
    double lastTriggerPriceAbove = -1;
    double lastTriggerPriceBelow = -1;
    bool midpointFound = false;
    
    // Find and initialize with midpoint
    for(int i = 0; i < count; i++) {
        // CRITICAL FIX: Bounds check before access
        if(i >= count || i >= classCount) {
            Print("  Index out of bounds: i=", i, ", count=", count, ", classCount=", classCount);
            break;
        }
        
        if(levels[i].logicalStep == 0) {
            lastStructurePriceAbove = levels[i].price;
            lastStructurePriceBelow = levels[i].price;
            lastTriggerPriceAbove = levels[i].price;
            lastTriggerPriceBelow = levels[i].price;
            midpointFound = true;
            Print("   Midpoint Found at Index ", i, ": ", DoubleToString(levels[i].price, s_cachedDigits));
            break;
        }
    }
    
    // CRITICAL:            midpoint
    if(!midpointFound) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CalculateZoneGeometries: Midpoint not found in levels array");
        #endif
        ArrayResize(outGeometries, 0);
        return;
    }
    
    // Calculate Zone Geometries
    int validZoneCount = 0;
    
    Print("====================");
    Print("   Zone Calculation Process:");
    
    for(int i = 0; i < count; i++) {
        // CRITICAL FIX: Bounds check
        if(i >= count || i >= classCount) {
            Print("  Index out of bounds in loop: i=", i);
            break;
        }
        
        outGeometries[i].isValid = false;
        outGeometries[i].linkedLevelIndex = i;
        
        // Skip if level is not active
        if(!classifications[i].isActive) {
            Print("   Level ", i, " [Step ", levels[i].logicalStep, "]: SKIPPED (Inactive)");
            continue;
        }
        
        // Skip midpoint (no zone for midpoint itself)
        if(levels[i].logicalStep == 0) {
            Print("   Level ", i, " [Step 0]: SKIPPED (Midpoint - no zone)");
            continue;
        }
        
        // Determine Previous Price based on Structure/Trigger type
        double prevPrice = 0;
        bool canCalculate = false;
        bool isStructure = classifications[i].isStructure;
        
        if(levels[i].logicalStep > 0) {
            // Above midpoint
            if(isStructure) {
                if(lastStructurePriceAbove > 0) {
                    prevPrice = lastStructurePriceAbove;
                    canCalculate = true;
                }
                lastStructurePriceAbove = levels[i].price;
            }
            else {
                if(lastTriggerPriceAbove > 0) {
                    prevPrice = lastTriggerPriceAbove;
                    canCalculate = true;
                }
                lastTriggerPriceAbove = levels[i].price;
            }
        }
        else {
            // Below midpoint
            if(isStructure) {
                if(lastStructurePriceBelow > 0) {
                    prevPrice = lastStructurePriceBelow;
                    canCalculate = true;
                }
                lastStructurePriceBelow = levels[i].price;
            }
            else {
                if(lastTriggerPriceBelow > 0) {
                    prevPrice = lastTriggerPriceBelow;
                    canCalculate = true;
                }
                lastTriggerPriceBelow = levels[i].price;
            }
        }
        
        // Calculate Zone Boundaries
        if(canCalculate) {
            // Validate geometry before calculating
            SZoneValidationResult validation = 
                ValidateZoneGeometry(prevPrice, levels[i].price, zoneHeight);
            
            if(validation.isValid) {
                double midPoint = (prevPrice + levels[i].price) / 2.0;
                double topPrice = midPoint + zoneHeight;
                double bottomPrice = midPoint - zoneHeight;
                
                outGeometries[i].isValid = true;
                outGeometries[i].topPrice = NormalizeDouble(topPrice, s_cachedDigits);
                outGeometries[i].bottomPrice = NormalizeDouble(bottomPrice, s_cachedDigits);
                outGeometries[i].midPoint = NormalizeDouble(midPoint, s_cachedDigits);
                validZoneCount++;
                
                // DIAGNOSTIC LOG: Zone Created
                Print("  Zone ", validZoneCount, " [Level ", i, ", Step ", levels[i].logicalStep, "]:");
                Print("   Type: ", isStructure ? "STRUCTURE" : "TRIGGER");
                Print("   Between: ", DoubleToString(prevPrice, s_cachedDigits), "   ", DoubleToString(levels[i].price, s_cachedDigits));
                Print("   Zone Top: ", DoubleToString(topPrice, s_cachedDigits));
                Print("   Zone Mid: ", DoubleToString(midPoint, s_cachedDigits));
                Print("   Zone Bottom: ", DoubleToString(bottomPrice, s_cachedDigits));
                Print("   Color: ", ColorToString(classifications[i].levelColor));
            }
            else {
                Print("  Level ", i, " [Step ", levels[i].logicalStep, "]: Invalid Geometry - ", validation.errorMessage);
            }
        }
        else {
            Print("   Level ", i, " [Step ", levels[i].logicalStep, "]: Cannot Calculate (No Previous ", 
                  isStructure ? "Structure" : "Trigger", " Price)");
        }
    }
    
    Print("====================");
    Print("  CalculateZoneGeometries Summary:");
    Print("   Valid Zones Created: ", validZoneCount);
    Print("====================");
}
