  //+------------------------------------------------------------------+
//|                                              DrawingPipeline.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                                    Clean Architecture Pipeline   |
//+------------------------------------------------------------------+
#ifndef DRAWING_PIPELINE_MQH
#define DRAWING_PIPELINE_MQH

#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

// Include modules in dependency order
#include "ConstantsAndEnums.mqh"
#include "ZoneValidator.mqh"
#include "ZoneCalculator.mqh"
#include "ZoneRenderer.mqh"

//+------------------------------------------------------------------+
//| MAIN ORCHESTRATOR: Draw Levels and Zones                         |
//|                  :                                               |
//|                                                                  |
//| This function orchestrates the complete 5-phase pipeline         |
//|                     5                                            |
//+------------------------------------------------------------------+
void DrawLevelsAndZones(
    const SLevelRawData &levels[],
    double stepSize,
    const SStyleConfig &config,
    const string objectPrefix)
{
    //                                                                
    // PHASE 1: VALIDATION & PREPARATION
    //       1:                        
    //                                                                
    int count;
    double zoneHeight;
    
    if(!ValidateCompleteConfig(levels, stepSize, config, count, zoneHeight)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  DrawLevelsAndZones: Validation failed");
        #endif
        return;
    }
    
    //                                                                
    // PHASE 2: LEVEL CLASSIFICATION
    //       2:               
    //                                                                
    SLevelClassification classifications[];
    ClassifyLevels(levels, config, classifications);
    
    //                                                                
    // PHASE 3: ZONE GEOMETRY CALCULATION
    //       3:                    
    //                                                                
    SZoneGeometry geometries[];
    CalculateZoneGeometries(levels, classifications, zoneHeight, geometries);
    
    //                                                                
    // PHASE 4: STYLE RESOLUTION
    //       4:             
    //                                                                
    SLineRenderInfo lines[];
    SZoneRenderInfo zones[];
    
    ResolveLineStyles(levels, classifications, config, objectPrefix, lines);
    ResolveZoneStyles(levels, classifications, geometries, config, objectPrefix, zones);
    
    //                                                                
    // PHASE 5: BATCH RENDERING
    //       5:            
    //                                                                
    RenderBatch(lines, zones);
    
    // MEMORY FIX: Free arrays after use
    ArrayFree(lines);
    ArrayFree(zones);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  DrawLevelsAndZones: Pipeline completed successfully");
    #endif
}

//+------------------------------------------------------------------+
//| LEGACY SUPPORT: Calculate Linear Levels                          |
//|               :                                                  |
//+------------------------------------------------------------------+
void CalculateLinearLevels(double startPrice, double stepSize, 
                           int countAbove, int countBelow, 
                           double maxPriceLimit, double minPriceLimit,
                           bool ignoreLimits,
                           SLevelRawData &outLevels[])
{
    // Estimate max size to avoid frequent resizing
    int estimatedSize = countAbove + countBelow + 1;
    ArrayResize(outLevels, estimatedSize);
    
    int validCount = 0;
    
    // 1. Midpoint (Always included)
    outLevels[validCount].price = startPrice;
    outLevels[validCount].logicalStep = 0;
    outLevels[validCount].stepTypeIndex = 0;
    validCount++;
    
    // 2. Above (Ascending)
    for(int i = 1; i <= countAbove; i++) {
        double price = startPrice + (i * stepSize);
        
        // Safety Check: Stop if out of bounds (unless custom mode)
        if(!ignoreLimits && maxPriceLimit > 0 && price > maxPriceLimit) break;
        
        outLevels[validCount].price = price;
        outLevels[validCount].logicalStep = i;
        outLevels[validCount].stepTypeIndex = 0;
        validCount++;
    }
    
    // 3. Below (Descending)
    for(int i = 1; i <= countBelow; i++) {
        double price = startPrice - (i * stepSize);
        
        // CRITICAL: Never allow negative prices
        if(price <= 0) break;
        
        // Safety Check: Stop if out of bounds
        if(!ignoreLimits && minPriceLimit > 0 && price < minPriceLimit) break;
        
        outLevels[validCount].price = price;
        outLevels[validCount].logicalStep = -i;
        outLevels[validCount].stepTypeIndex = 0;
        validCount++;
    }
    
    // Resize to actual count
    ArrayResize(outLevels, validCount);
    
    // DIAGNOSTIC LOG
    Print("  CalculateLinearLevels: Generated ", validCount, " levels");
    Print("   Start Price: ", DoubleToString(startPrice, Digits));
    Print("   Step Size: ", DoubleToString(stepSize, Digits));
    Print("   Requested Above: ", countAbove, ", Generated: ", validCount - 1 - (validCount - 1 - countAbove));
    Print("   Requested Below: ", countBelow);
}

//+------------------------------------------------------------------+
//| LEGACY SUPPORT: Old Style Resolver (Deprecated)                  |
//|               :                       (         )                |
//|                                                                  |
//| NOTE: Use DrawLevelsAndZones() instead for new code              |
//|     :                 DrawLevelsAndZones()                      |
//+------------------------------------------------------------------+
void ResolveStylesLinear(const SLevelRawData &levels[], 
                        double stepSize,
                        const SStyleConfig &config,
                        const string objectPrefix,
                        SLineRenderInfo &outLines[],
                        SZoneRenderInfo &outZones[])
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("   ResolveStylesLinear: DEPRECATED - Use DrawLevelsAndZones() instead");
    #endif
    
    // Delegate to new pipeline
    DrawLevelsAndZones(levels, stepSize, config, objectPrefix);
    
    // For backward compatibility, populate output arrays
    int count = ArraySize(levels);
    ArrayResize(outLines, count);
    ArrayResize(outZones, 0); // Zones handled internally
}

//+------------------------------------------------------------------+
//| Cleanup Helper                                                    |
//|                                                                   |
//+------------------------------------------------------------------+
void Cleanup(string prefix) {
    CleanupZoneObjects(prefix);
}

#endif // DRAWING_PIPELINE_MQH
