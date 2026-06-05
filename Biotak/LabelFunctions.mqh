  #ifndef LABEL_FUNCTIONS_MQH
#define LABEL_FUNCTIONS_MQH

#property strict

bool DrawMainLevels(const string prefix) {
    // Skip drawing High/Low lines when Custom Price mode is active
    // In Custom Price mode, user defines their own reference point
    if(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) {
        // Delete existing High/Low lines if they exist
        ObjectDelete(0, prefix + "High");
        ObjectDelete(0, prefix + "High_PipsLabel");
        ObjectDelete(0, prefix + "Low");
        ObjectDelete(0, prefix + "Low_PipsLabel");
        return true;
    }
    
    // OPTIMIZATION: Cache tooltip strings and only recalculate if prices changed
    static double s_lastHighPrice = 0;
    static double s_lastLowPrice = 0;
    static string s_cachedHighTooltip = "";
    static string s_cachedLowTooltip = "";
    
    // High line
    string highTooltip;
    if(s_lastHighPrice != g_highestHigh) {
        highTooltip = inpHighLineTooltip + ": " + DoubleToString(g_highestHigh, Digits);
        double pipsToHigh = CalculatePipsDistance(g_highestHigh, g_currentPrice);
        highTooltip = highTooltip + ", Distance: +/- " + DoubleToString(pipsToHigh, 1) + " pips";
        s_cachedHighTooltip = highTooltip;
        s_lastHighPrice = g_highestHigh;
    } else {
        highTooltip = s_cachedHighTooltip;
    }
    if(!CreateTHLineObject(prefix+"High",g_highestHigh,inpHighColor,inpHighStyle,inpHighWidth,highTooltip, inpTHLineObjectType, false)) return false;
    if(inpShowPipDistanceLabels) {
        double pipsToHigh = CalculatePipsDistance(g_highestHigh, g_currentPrice);
        CreatePipDistanceLabel(prefix+"High_PipsLabel", g_highestHigh, pipsToHigh, inpHighColor);
    }
    
    // Low line
    string lowTooltip;
    if(s_lastLowPrice != g_lowestLow) {
        lowTooltip = inpLowLineTooltip + ": " + DoubleToString(g_lowestLow, Digits);
        double pipsToLow = CalculatePipsDistance(g_lowestLow, g_currentPrice);
        lowTooltip = lowTooltip + ", Distance: +/- " + DoubleToString(pipsToLow, 1) + " pips";
        s_cachedLowTooltip = lowTooltip;
        s_lastLowPrice = g_lowestLow;
    } else {
        lowTooltip = s_cachedLowTooltip;
    }
    if(!CreateTHLineObject(prefix+"Low",g_lowestLow,inpLowColor,inpLowStyle,inpLowWidth,lowTooltip, inpTHLineObjectType, false)) return false;
    if(inpShowPipDistanceLabels) {
        double pipsToLow = CalculatePipsDistance(g_lowestLow, g_currentPrice);
        CreatePipDistanceLabel(prefix+"Low_PipsLabel", g_lowestLow, pipsToLow, inpLowColor);
    }
    return true;
}

void DrawTHLevels(const string objectPrefix, const double dailyClosePrice) {
    if(dailyClosePrice <= 0) {
        Print("DrawTHLevels: Invalid daily close price");
        return;
    }
    
    // OPTIMIZATION: Use centralized cached values from PerformanceOptimizations.mqh
    double s_cachedPointValue = GetCachedPoint();
    int s_cachedDigits = GetCachedDigits();
    string s_cachedSymbol = GetCachedSymbol();
    
    string prefix=objectPrefix+"TH_Level_";
    // Note: ClearAllLevels is called in DrawLevelsBasedOnMode before this function
    double timeframePercentage=GetTimeframeTH();
    string structureTimeframe = GetStructureTimeframeForCurrent();
    double structureTFPercentage=CalculateTimeframeTH(structureTimeframe);
    if(structureTFPercentage <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("DrawTHLevels: Invalid structure timeframe percentage");
        #endif
        return;
    }
    double structureMultipliers[] = {1.0, 2.0, 4.0, 8.0, 16.0};
    double structurePercentages[];
    // PERFORMANCE: Cache ArraySize before loop
    int structureMultipliersCount = ArraySize(structureMultipliers);
    if(ArrayResize(structurePercentages, structureMultipliersCount) != structureMultipliersCount) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("DrawTHLevels: Failed to resize structurePercentages array");
        #endif
        return;
    }
    for(int i=0; i<structureMultipliersCount; i++) {
        structurePercentages[i] = structureTFPercentage * structureMultipliers[i];
        if(structurePercentages[i] <= 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("DrawTHLevels: Invalid structure percentage at index ", i);
            #endif
            return;
        }
    }
    if(timeframePercentage<=0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("DrawTHLevels: Invalid timeframe percentage");
        #endif
        return;
    }
    
    // Use cached values instead of recalculating
    int digits = s_cachedDigits;
    if(digits < 0 || digits > 8) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("DrawTHLevels: Invalid digits value: ", digits);
        #endif
        return;
    }
    double thStepSizePoints=CalculateTHPoints(dailyClosePrice,digits,timeframePercentage);
    double structureTFTHStepSizePoints=CalculateTHPoints(dailyClosePrice,digits,structurePercentages[0]);
    double doubleStructureTFTHStepSizePoints=CalculateTHPoints(dailyClosePrice,digits,structurePercentages[1]);
    double tripleStructureTFTHStepSizePoints=CalculateTHPoints(dailyClosePrice,digits,structurePercentages[2]);
    double quadrupleStructureTFTHStepSizePoints=CalculateTHPoints(dailyClosePrice,digits,structurePercentages[3]);
    double quintupleStructureTFTHStepSizePoints=CalculateTHPoints(dailyClosePrice,digits,structurePercentages[4]);
    if (thStepSizePoints <= 0 || structureTFTHStepSizePoints <= 0 || doubleStructureTFTHStepSizePoints <= 0) return;
    
    //                                                                    
    // FIX: Use configurable Base Multiplier instead of hardcoded values
    // Matches Java implementation in LevelDrawer.java (getPathForStep)
    //                                                                    
    int baseMultiplier = GetValidatedBaseMultiplier(); // Use central validation
    
    // Get cached intervals for the base multiplier (base^1, base^2, base^3, base^4, base^5)
    int intervals[];
    GetCachedIntervals(baseMultiplier, intervals);
    
    // GOLD FIX #11: Array bounds checking - get size for safe access
    int intervalSize = ArraySize(intervals);
    if(intervalSize == 0) {
        Print("  DrawTHLevels: Empty intervals array, cannot draw structure levels");
        return;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("   DrawTHLevels using Base Multiplier: ", baseMultiplier,
          "   L1=", intervals[0], ", L2=", intervals[1], ", L3=", intervals[2],
          ", L4=", intervals[3], ", L5=", intervals[4]);
    #endif
    //                                                                    
    
    // Get midpoint price using utility function
    double midpointPrice = GetMidpointPrice(g_thStartPointType);
    double pointValue = s_cachedPointValue;
    
    if(inpShowMidpointLine) {
        string lineNameMid=prefix+"Mid";
        string tooltipMid=StringFormat("Trigger TH Midpoint Level (%s)",DoubleToString(midpointPrice,Digits));
        double pipsToMid = CalculatePipsDistance(midpointPrice, g_currentPrice);
        tooltipMid = FormatTooltipWithDistance(tooltipMid, midpointPrice);
        CreateTHLineObject(lineNameMid,midpointPrice,inpTriggerColor,inpTriggerStyle,inpTriggerWidth,tooltipMid, inpTHLineObjectType, false);
        string cachedTFForMid = GetFractalTimeframeForCurrent();
        string midLevelInfo = StringFormat("%s Mid", GetShortTimeframeName(cachedTFForMid));
        if(inpShowPipDistanceLabels) CreatePipDistanceLabel(prefix+"Mid_PipsLabel", midpointPrice, pipsToMid, inpTriggerColor, midLevelInfo);
    }
    // OPTIMIZATION: Cache IsTriggerLevelsEnabled() result BEFORE the loops
    bool triggerEnabled = IsTriggerLevelsEnabled();
    
    //                                                                
    // ZONE SUPPORT: Cleanup old zones
    //          Zone:         zone          
    //                                                                
    if(inpShowMidZones) {
        ObjectsDeleteAll(0, prefix + "Zone_", -1, -1);
    }
    
    if (triggerEnabled || inpShowStructure) {
        // Get adaptive level counts based on start point type
        int maxLevelsAbove = 0;
        int maxLevelsBelow = 0;
        GetAdaptiveLevelCounts(maxLevelsAbove, maxLevelsBelow);
        
        // Determine if we should check historical high/low bounds
        // Custom Price mode: Only respect level count, ignore historical bounds
        // Historical modes (High/Low/Midpoint): Respect both level count AND historical bounds
        bool checkHistoricalBounds = (g_thStartPointType != TH_START_POINT_CUSTOM_PRICE);
        
        // OPTIMIZATION: Cache GetFractalTimeframeForCurrent() and related values BEFORE the loops
        string cachedCurrentTF = GetFractalTimeframeForCurrent();
        double cachedPatternTH = GetLowerTimeframeTH(cachedCurrentTF, 1);
        double cachedTriggerTH = GetLowerTimeframeTH(cachedCurrentTF, 2);
        double cachedLongStep = timeframePercentage * 2.0;
        double cachedShortStep = timeframePercentage * 1.5;
        
        //                                                                
        // ZONE SUPPORT: Tracking variables for Structure/Trigger separation
        //          Zone:                              Structure/Trigger
        //                                                                
        double lastDrawnPriceAbove = midpointPrice;  // Track last structure level
        double lastTriggerPriceAbove = 0;            // Track last trigger level
        int zoneCountAbove = 0;
        
        double priceLevelAbove = midpointPrice + (thStepSizePoints * pointValue);
        // NO NormalizeDouble - keep full precision to match MotiveWave
        int stepCountAbove = 1;
        int levelCountAbove = 0;
        
        // Loop condition: Custom Price = only count, Historical = count AND bounds
        while ((checkHistoricalBounds ? (priceLevelAbove <= g_highestHigh) : true) && levelCountAbove < maxLevelsAbove) {
            string lineNameAbove, tooltipAbove, levelInfoAbove;
            color lineColor;
            ENUM_LINE_STYLE lineStyle = inpTHLineStyle;
            int lineWidth;
            double percentageTooltip = 0.0;
            string shortCurrentTF = GetShortTimeframeName(cachedCurrentTF);
            
            // Build overlap info for this step
            string overlapLevels = GetOverlapLevelsInfo(stepCountAbove, intervals);
            string overlapTFs = GetOverlapTimeframesInfo(stepCountAbove, intervals);
            
            // FIX: Use dynamic intervals from Base Multiplier instead of hardcoded values
            // Check from highest to lowest level for priority (matching Java getPathForStep)
            if (intervals[4] > 0 && stepCountAbove % intervals[4] == 0 && inpShowStructure && inpShowStructureL5) {
                string tfL5 = GetShortTimeframeName(GetTimeframeForStructureLevel(5));
                lineNameAbove = prefix + "StructureLevel5_Up_" + IntegerToString(stepCountAbove / intervals[4]);
                tooltipAbove = StringFormat("[%s] %s +%d | Price: %s | TH: %.1f pips", overlapTFs, overlapLevels, stepCountAbove / intervals[4], DoubleToString(priceLevelAbove, Digits), quintupleStructureTFTHStepSizePoints / 10.0);
                levelInfoAbove = StringFormat("%s %s +%d", overlapTFs, overlapLevels, stepCountAbove / intervals[4]);
                lineColor = inpStructureL5Color;
                lineStyle = inpStructureL5Style;
                lineWidth = inpStructureL5Width;
                percentageTooltip = structurePercentages[4];
            } else if (intervalSize > 3 && intervals[3] > 0 && stepCountAbove % intervals[3] == 0 && inpShowStructure && inpShowStructureL4) {
                lineNameAbove = prefix + "StructureLevel4_Up_" + IntegerToString(stepCountAbove / intervals[3]);
                tooltipAbove = StringFormat("[%s] %s +%d | Price: %s | TH: %.1f pips", overlapTFs, overlapLevels, stepCountAbove / intervals[3], DoubleToString(priceLevelAbove, Digits), quadrupleStructureTFTHStepSizePoints / 10.0);
                levelInfoAbove = StringFormat("%s %s +%d", overlapTFs, overlapLevels, stepCountAbove / intervals[3]);
                lineColor = inpStructureL4Color;
                lineStyle = inpStructureL4Style;
                lineWidth = inpStructureL4Width;
                percentageTooltip = structurePercentages[3];
            } else if (intervalSize > 2 && intervals[2] > 0 && stepCountAbove % intervals[2] == 0 && inpShowStructure && inpShowStructureL3) {
                lineNameAbove = prefix + "StructureLevel3_Up_" + IntegerToString(stepCountAbove / intervals[2]);
                tooltipAbove = StringFormat("[%s] %s +%d | Price: %s | TH: %.1f pips", overlapTFs, overlapLevels, stepCountAbove / intervals[2], DoubleToString(priceLevelAbove, Digits), tripleStructureTFTHStepSizePoints / 10.0);
                levelInfoAbove = StringFormat("%s %s +%d", overlapTFs, overlapLevels, stepCountAbove / intervals[2]);
                lineColor = inpStructureL3Color;
                lineStyle = inpStructureL3Style;
                lineWidth = inpStructureL3Width;
                percentageTooltip = structurePercentages[2];
            } else if (intervalSize > 1 && intervals[1] > 0 && stepCountAbove % intervals[1] == 0 && inpShowStructure && inpShowStructureL2) {
                lineNameAbove = prefix + "StructureLevel2_Up_" + IntegerToString(stepCountAbove / intervals[1]);
                tooltipAbove = StringFormat("[%s] %s +%d | Price: %s | TH: %.1f pips", overlapTFs, overlapLevels, stepCountAbove / intervals[1], DoubleToString(priceLevelAbove, Digits), doubleStructureTFTHStepSizePoints / 10.0);
                levelInfoAbove = StringFormat("%s %s +%d", overlapTFs, overlapLevels, stepCountAbove / intervals[1]);
                lineColor = inpStructureL2Color;
                lineStyle = inpStructureL2Style;
                lineWidth = inpStructureL2Width;
                percentageTooltip = structurePercentages[1];
            } else if (intervalSize > 0 && intervals[0] > 0 && stepCountAbove % intervals[0] == 0 && inpShowStructure && inpShowStructureL1) {
                lineNameAbove = prefix + "StructureLevel1_Up_" + IntegerToString(stepCountAbove / intervals[0]);
                tooltipAbove = StringFormat("[%s] %s +%d | Price: %s | TH: %.1f pips", overlapTFs, overlapLevels, stepCountAbove / intervals[0], DoubleToString(priceLevelAbove, Digits), structureTFTHStepSizePoints / 10.0);
                levelInfoAbove = StringFormat("%s %s +%d", overlapTFs, overlapLevels, stepCountAbove / intervals[0]);
                lineColor = inpStructureL1Color;
                lineStyle = inpStructureL1Style;
                lineWidth = inpStructureL1Width;
                percentageTooltip = structurePercentages[0];
            } else if (triggerEnabled) {
                // OPTIMIZATION: Use cached values instead of calling functions inside loop
                // Use simple multipliers: SS = 1.5 * Structure, LS = 2.0 * Structure
                lineNameAbove = prefix + "TriggerTH_Up_" + IntegerToString(stepCountAbove);
                tooltipAbove = StringFormat("[%s] +%d | Price: %s | L: %.1f, S: %.1f pips",
                    shortCurrentTF, stepCountAbove, DoubleToString(priceLevelAbove, Digits),
                    cachedLongStep * thStepSizePoints / 10.0,
                    cachedShortStep * thStepSizePoints / 10.0);
                levelInfoAbove = StringFormat("%s +%d", shortCurrentTF, stepCountAbove);
                lineColor = inpTriggerColor;
                lineStyle = inpTriggerStyle;
                lineWidth = inpTriggerWidth;
                percentageTooltip = timeframePercentage;
            } else {
                priceLevelAbove += (thStepSizePoints * pointValue);
                // NO NormalizeDouble - keep full precision to match MotiveWave
                stepCountAbove++;
                continue;
            }
            
            double pipsToLevelAbove = CalculatePipsDistance(priceLevelAbove, g_currentPrice);
            tooltipAbove = FormatTooltipWithDistance(tooltipAbove, priceLevelAbove);
            CreateTHLineObject(lineNameAbove, priceLevelAbove, lineColor, lineStyle, lineWidth, tooltipAbove, inpTHLineObjectType, false);
            if(inpShowPipDistanceLabels) CreatePipDistanceLabel(lineNameAbove+"_PipsLabel", priceLevelAbove, pipsToLevelAbove, lineColor, levelInfoAbove);
            
            //                                                            
            // ZONE SUPPORT: Create zone between levels
            //          Zone:      zone         
            // 
            // UNIFIED APPROACH: Use CreateZoneWithSmartFallback
            //               :    CreateZoneWithSmartFallback           
            // GOLD VERSION: Uses GetHighestStructureLevel for clean logic
            // CRITICAL FIX: Pass fixed step size for consistent zone height
            //                                                            
            if(inpShowMidZones) {
                // GOLD FIX: Use centralized function instead of repeated else-if
                int highestLevel = GetHighestStructureLevel(stepCountAbove, intervals);
                bool isStructureLevel = (highestLevel > 0 && inpShowStructure);
                
                string zoneName = prefix + "Zone_Above_" + IntegerToString(stepCountAbove);
                
                // CRITICAL FIX: Calculate fixed step size (matching M/SS/LS/Factor modes)
                double fixedStepSize = thStepSizePoints * pointValue;
                
                // Use unified smart fallback function
                // Note: We pass lastDrawnPriceAbove as both structure and fallback tracker
                // because in TH mode, when neither is enabled, we still want to track the last drawn price
                if(CreateZoneWithSmartFallback(zoneName, priceLevelAbove, isStructureLevel, lineColor,
                                              inpShowStructure, triggerEnabled,
                                              lastDrawnPriceAbove, lastTriggerPriceAbove, lastDrawnPriceAbove,
                                              fixedStepSize)) {  // Pass fixed step size
                    zoneCountAbove++;
                }
            }
            
            priceLevelAbove += (thStepSizePoints * pointValue);
            // NO NormalizeDouble - keep full precision to match MotiveWave
            stepCountAbove++;
            levelCountAbove++;
        }
        
        //                                                                
        // ZONE SUPPORT: Tracking variables for levels below
        //          Zone:                                
        //                                                                
        double lastDrawnPriceBelow = midpointPrice;  // Track last structure level
        double lastTriggerPriceBelow = 0;            // Track last trigger level
        int zoneCountBelow = 0;
        
        double priceLevelBelow = midpointPrice - (thStepSizePoints * pointValue);
        // NO NormalizeDouble - keep full precision to match MotiveWave
        int stepCountBelow = 1;
        int levelCountBelow = 0;
        
        // Loop condition: Custom Price = only count, Historical = count AND bounds
        while ((checkHistoricalBounds ? (priceLevelBelow >= g_lowestLow) : true) && levelCountBelow < maxLevelsBelow) {
            string lineNameBelow, tooltipBelow, levelInfoBelow;
            color lineColor;
            ENUM_LINE_STYLE lineStyle = inpTHLineStyle;
            int lineWidth;
            double percentageTooltip = 0.0;
            string shortCurrentTFBelow = GetShortTimeframeName(cachedCurrentTF);
            
            // Build overlap info for this step
            string overlapLevelsBelow = GetOverlapLevelsInfo(stepCountBelow, intervals);
            string overlapTFsBelow = GetOverlapTimeframesInfo(stepCountBelow, intervals);
            
            // FIX: Use dynamic intervals from Base Multiplier instead of hardcoded values
            // Check from highest to lowest level for priority (matching Java getPathForStep)
            if (intervals[4] > 0 && stepCountBelow % intervals[4] == 0 && inpShowStructure && inpShowStructureL5) {
                lineNameBelow = prefix + "StructureLevel5_Down_" + IntegerToString(stepCountBelow / intervals[4]);
                tooltipBelow = StringFormat("[%s] %s -%d | Price: %s | TH: %.1f pips", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[4], DoubleToString(priceLevelBelow, Digits), quintupleStructureTFTHStepSizePoints / 10.0);
                levelInfoBelow = StringFormat("%s %s -%d", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[4]);
                lineColor = inpStructureL5Color;
                lineStyle = inpStructureL5Style;
                lineWidth = inpStructureL5Width;
                percentageTooltip = structurePercentages[4];
            } else if (intervals[3] > 0 && stepCountBelow % intervals[3] == 0 && inpShowStructure && inpShowStructureL4) {
                lineNameBelow = prefix + "StructureLevel4_Down_" + IntegerToString(stepCountBelow / intervals[3]);
                tooltipBelow = StringFormat("[%s] %s -%d | Price: %s | TH: %.1f pips", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[3], DoubleToString(priceLevelBelow, Digits), quadrupleStructureTFTHStepSizePoints / 10.0);
                levelInfoBelow = StringFormat("%s %s -%d", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[3]);
                lineColor = inpStructureL4Color;
                lineStyle = inpStructureL4Style;
                lineWidth = inpStructureL4Width;
                percentageTooltip = structurePercentages[3];
            } else if (intervals[2] > 0 && stepCountBelow % intervals[2] == 0 && inpShowStructure && inpShowStructureL3) {
                lineNameBelow = prefix + "StructureLevel3_Down_" + IntegerToString(stepCountBelow / intervals[2]);
                tooltipBelow = StringFormat("[%s] %s -%d | Price: %s | TH: %.1f pips", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[2], DoubleToString(priceLevelBelow, Digits), tripleStructureTFTHStepSizePoints / 10.0);
                levelInfoBelow = StringFormat("%s %s -%d", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[2]);
                lineColor = inpStructureL3Color;
                lineStyle = inpStructureL3Style;
                lineWidth = inpStructureL3Width;
                percentageTooltip = structurePercentages[2];
            } else if (intervals[1] > 0 && stepCountBelow % intervals[1] == 0 && inpShowStructure && inpShowStructureL2) {
                lineNameBelow = prefix + "StructureLevel2_Down_" + IntegerToString(stepCountBelow / intervals[1]);
                tooltipBelow = StringFormat("[%s] %s -%d | Price: %s | TH: %.1f pips", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[1], DoubleToString(priceLevelBelow, Digits), doubleStructureTFTHStepSizePoints / 10.0);
                levelInfoBelow = StringFormat("%s %s -%d", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[1]);
                lineColor = inpStructureL2Color;
                lineStyle = inpStructureL2Style;
                lineWidth = inpStructureL2Width;
                percentageTooltip = structurePercentages[1];
            } else if (intervals[0] > 0 && stepCountBelow % intervals[0] == 0 && inpShowStructure && inpShowStructureL1) {
                lineNameBelow = prefix + "StructureLevel1_Down_" + IntegerToString(stepCountBelow / intervals[0]);
                tooltipBelow = StringFormat("[%s] %s -%d | Price: %s | TH: %.1f pips", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[0], DoubleToString(priceLevelBelow, Digits), structureTFTHStepSizePoints / 10.0);
                levelInfoBelow = StringFormat("%s %s -%d", overlapTFsBelow, overlapLevelsBelow, stepCountBelow / intervals[0]);
                lineColor = inpStructureL1Color;
                lineStyle = inpStructureL1Style;
                lineWidth = inpStructureL1Width;
                percentageTooltip = structurePercentages[0];
            } else if (triggerEnabled) {
                // OPTIMIZATION: Use cached values instead of calling functions inside loop
                lineNameBelow = prefix + "TriggerTH_Down_" + IntegerToString(stepCountBelow);
                // Use simple multipliers: SS = 1.5 * Structure, LS = 2.0 * Structure
                tooltipBelow = StringFormat("[%s] -%d | Price: %s | L: %.1f, S: %.1f pips",
                    shortCurrentTFBelow, stepCountBelow, DoubleToString(priceLevelBelow, Digits),
                    cachedLongStep * thStepSizePoints / 10.0,
                    cachedShortStep * thStepSizePoints / 10.0);
                levelInfoBelow = StringFormat("%s -%d", shortCurrentTFBelow, stepCountBelow);
                lineColor = inpTriggerColor;
                lineStyle = inpTriggerStyle;
                lineWidth = inpTriggerWidth;
                percentageTooltip = timeframePercentage;
            } else {
                priceLevelBelow -= (thStepSizePoints * pointValue);
                // NO NormalizeDouble - keep full precision to match MotiveWave
                stepCountBelow++;
                continue;
            }
            
            // OPTIMIZATION: Use cached pointValue instead of Point() inside loop
            double pipsToLevelBelow = NormalizeDouble(MathAbs(priceLevelBelow - g_currentPrice) / pointValue / 10.0, 1);
            tooltipBelow = StringFormat("%s | Dist: %.1f pips", tooltipBelow, pipsToLevelBelow);
            CreateTHLineObject(lineNameBelow, priceLevelBelow, lineColor, lineStyle, lineWidth, tooltipBelow, inpTHLineObjectType, false);
            if(inpShowPipDistanceLabels) CreatePipDistanceLabel(lineNameBelow+"_PipsLabel", priceLevelBelow, pipsToLevelBelow, lineColor, levelInfoBelow);
            
            //                                                            
            // ZONE SUPPORT: Create zone between levels
            //          Zone:      zone         
            // 
            // UNIFIED APPROACH: Use CreateZoneWithSmartFallback
            //               :    CreateZoneWithSmartFallback           
            // GOLD VERSION: Uses GetHighestStructureLevel for clean logic
            // CRITICAL FIX: Pass fixed step size for consistent zone height
            //                                                            
            if(inpShowMidZones) {
                // GOLD FIX: Use centralized function instead of repeated else-if
                int highestLevel = GetHighestStructureLevel(stepCountBelow, intervals);
                bool isStructureLevel = (highestLevel > 0 && inpShowStructure);
                
                string zoneName = prefix + "Zone_Below_" + IntegerToString(stepCountBelow);
                
                // CRITICAL FIX: Calculate fixed step size (matching M/SS/LS/Factor modes)
                double fixedStepSize = thStepSizePoints * pointValue;
                
                // Use unified smart fallback function
                if(CreateZoneWithSmartFallback(zoneName, priceLevelBelow, isStructureLevel, lineColor,
                                              inpShowStructure, triggerEnabled,
                                              lastDrawnPriceBelow, lastTriggerPriceBelow, lastDrawnPriceBelow,
                                              fixedStepSize)) {  // Pass fixed step size
                    zoneCountBelow++;
                }
            }
            
            priceLevelBelow -= (thStepSizePoints * pointValue);
            // NO NormalizeDouble - keep full precision to match MotiveWave
            stepCountBelow++;
            levelCountBelow++;
        }
        
        #ifdef ENABLE_DEBUG_LOGS
        if(inpShowMidZones) {
            Print("  DrawTHLevels: Drew ", zoneCountAbove, " zones above, ", 
                  zoneCountBelow, " zones below");
        }
        #endif
    }
}

void SetLabelFont(const string name) {
    ObjectSetString(0, name, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, inpFontSize);
}

//+------------------------------------------------------------------+
//| ATR label helpers (ported from MT5)                               |
//+------------------------------------------------------------------+
void InitATRChartLabel(const string name, ENUM_BASE_CORNER corner, ENUM_ANCHOR_POINT anchor) {
    ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

string GetBaseTimeframeName(const string fullName) {
    int plusPos = StringFind(fullName, "+");
    if(plusPos > 0) {
        return StringSubstr(fullName, 0, plusPos);
    }
    return fullName;
}

bool CreateATRLabelSimple(const string objectPrefix, const string timeframeName, const double atrValuePoints, const int xPos, const int yPos, const color textColor, const int horizontalSpacing, const int verticalSpacing) {
    double point = GetCachedPoint();
    double pipSize = GetCachedPipSize();
    if(IsZero(point, EPSILON_PRICE) || IsZero(pipSize, EPSILON_PRICE)) return false;
    double atrPips = NormalizeDouble((atrValuePoints * point) / pipSize, 1);
    double shortStepPips = NormalizeDouble(atrPips * 1.5, 1);
    double longStepPips = NormalizeDouble(atrPips * 2.0, 1);
    double midStepPips = NormalizeDouble((shortStepPips + longStepPips) / 2.0, 1);
    double target3x = MathFloor(atrPips * 3.0);
    double target5x = MathFloor(atrPips * 5.0);
    double target15x = MathFloor(atrPips * 15.0);
    string mainObjName = objectPrefix + "ATR_" + timeframeName;
    string stepsObjName = objectPrefix + "ATR_Steps_" + timeframeName;
    string targetsObjName = objectPrefix + "ATR_Targets_" + timeframeName;
    if(!inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
        ObjectDelete(0, targetsObjName);
    }
    string targetsText = DoubleToString(target3x, 0) + " - " + DoubleToString(target5x, 0) + " - " + DoubleToString(target15x, 0);
    string mainText = timeframeName + ": " + DoubleToString(atrPips, 1);
    string stepsText = "(" + DoubleToString(shortStepPips, 1) + " - " + DoubleToString(midStepPips, 1) + " - " + DoubleToString(longStepPips, 1) + ")";

    // PERF: Only update text/color if changed (using Cache)
    string cachedText;
    color cachedColor;
    bool exists = CacheGetLabel(mainObjName, cachedText, cachedColor);
    
    bool textChanged = !exists || (cachedText != mainText);
    bool colorChanged = !exists || (cachedColor != textColor);

    if(exists) {
        if(textChanged) {
            ObjectSetString(0, mainObjName, OBJPROP_TEXT, mainText);
            ObjectSetString(0, stepsObjName, OBJPROP_TEXT, stepsText);
            if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
                ObjectSetString(0, targetsObjName, OBJPROP_TEXT, targetsText);
            }
            CacheUpdateLabel(mainObjName, mainText, textColor);
        }
        if(colorChanged) {
            ObjectSetInteger(0, mainObjName, OBJPROP_COLOR, textColor);
            ObjectSetInteger(0, stepsObjName, OBJPROP_COLOR, textColor);
            if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
                ObjectSetInteger(0, targetsObjName, OBJPROP_COLOR, textColor);
            }
            CacheUpdateLabel(mainObjName, mainText, textColor);
        }
        int baseY = MathAbs(yPos);
        int singleLineHeight_u = inpFontSize + inpLabelRowGap;
        ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY);
        ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight_u);
        if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
            ObjectSetInteger(0, targetsObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight_u * 2);
        }
        int labelXDistance = MathAbs(xPos);
        int mainTextWidth = (int)(StringLen(mainText) * inpFontSize * 0.6);
        int stepsTextWidth = (int)(StringLen(stepsText) * inpFontSize * 0.6);
        int mainOffset = (stepsTextWidth - mainTextWidth) / 2;
        if(mainOffset < 0) mainOffset = 0;
        ObjectSetInteger(0, mainObjName, OBJPROP_XDISTANCE, labelXDistance + mainOffset);
        ObjectSetInteger(0, stepsObjName, OBJPROP_XDISTANCE, labelXDistance);
        if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
            int targetsTextWidth = (int)(StringLen(targetsText) * inpFontSize * 0.6);
            int targetsOffset = (mainTextWidth - targetsTextWidth) / 2 + mainOffset;
            if(targetsOffset < 0) targetsOffset = 0;
            ObjectSetInteger(0, targetsObjName, OBJPROP_XDISTANCE, labelXDistance + targetsOffset);
        }
        return true;
    }

    // Creation path
    if (ObjectFind(0, mainObjName) < 0) {
        if (!ObjectCreate(0, mainObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, mainObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    if (ObjectFind(0, stepsObjName) < 0) {
        if (!ObjectCreate(0, stepsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, stepsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    if (inpShowATRTargets && ObjectFind(0, targetsObjName) < 0) {
        if (!ObjectCreate(0, targetsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, targetsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    if(inpShowATRTargets) {
        ObjectSetString(0, targetsObjName, OBJPROP_TEXT, targetsText);
        ObjectSetInteger(0, targetsObjName, OBJPROP_COLOR, textColor);
        SetLabelFont(targetsObjName);
    }
    ObjectSetString(0, mainObjName, OBJPROP_TEXT, mainText);
    ObjectSetString(0, stepsObjName, OBJPROP_TEXT, stepsText);
    ObjectSetInteger(0, mainObjName, OBJPROP_COLOR, textColor);
    ObjectSetInteger(0, stepsObjName, OBJPROP_COLOR, textColor);
    SetLabelFont(mainObjName);
    SetLabelFont(stepsObjName);
    
    ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER;
    ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
    InitATRChartLabel(mainObjName, corner, anchor);
    InitATRChartLabel(stepsObjName, corner, anchor);
    if(inpShowATRTargets) {
        InitATRChartLabel(targetsObjName, corner, anchor);
    }
    int labelXDistance = MathAbs(xPos);
    int bottomPadding = 20;
    int lineGap = inpLabelRowGap;
    int singleLineHeight = inpFontSize + lineGap;
    int mainTextWidth = (int)(StringLen(mainText) * inpFontSize * 0.6);
    int stepsTextWidth = (int)(StringLen(stepsText) * inpFontSize * 0.6);
    int mainOffset = (stepsTextWidth - mainTextWidth) / 2;
    if(mainOffset < 0) mainOffset = 0;
    int targetsOffset = 0;
    if(inpShowATRTargets) {
        int targetsTextWidth = (int)(StringLen(targetsText) * inpFontSize * 0.6);
        targetsOffset = (mainTextWidth - targetsTextWidth) / 2 + mainOffset;
        if(targetsOffset < 0) targetsOffset = 0;
    }
    
    int baseY = MathAbs(yPos);
    ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY);
    ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight);
    if(inpShowATRTargets) {
        ObjectSetInteger(0, targetsObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight * 2);
    }
    if(inpShowATRTargets) {
        ObjectSetInteger(0, targetsObjName, OBJPROP_XDISTANCE, labelXDistance + targetsOffset);
    }
    ObjectSetInteger(0, mainObjName, OBJPROP_XDISTANCE, labelXDistance + mainOffset);
    ObjectSetInteger(0, stepsObjName, OBJPROP_XDISTANCE, labelXDistance);
    
    if(IsIndicatorHidden()) {
        if(inpShowATRTargets) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    } else {
        if(inpShowATRTargets) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    return true;
}

//+------------------------------------------------------------------+
//| Clear all labels to prevent ghosting or overlaps                |
//+------------------------------------------------------------------+
void ClearAllLabels(const string objectPrefix) {
    // 1. Delete all labels with the standard LBL_ prefix (New thorough way)
    string labelPrefix = objectPrefix + "LBL_";
    ObjectsDeleteAll(0, labelPrefix);
    
    // 2. Delete labels that might have different timeframe prefixes (cleanup old logic)
    int total = ObjectsTotal(0, -1, -1);
    string tfSearch = objectPrefix + "TF";
    int tfSearchLen = StringLen(tfSearch);
    
    for(int i = total - 1; i >= 0; i--) {
        string objName = ObjectName(0, i, -1, -1);
        if(StringSubstr(objName, 0, tfSearchLen) == tfSearch) {
            ObjectDelete(0, objName);
        }
    }
}

void DisplayATRLabels(const string objectPrefix) {
    if(!g_atrLabelsVisible) {
        ClearAllLabels(objectPrefix);
        return;
    }
    
    double point = GetCachedPoint();
    double pipSize = GetCachedPipSize();
    int digits = GetCachedDigits();
    if(IsZero(point, EPSILON_PRICE) || IsZero(pipSize, EPSILON_PRICE) || digits == 0) return;

    string labelPrefix = objectPrefix + "LBL_";
    string timeframes[] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1", "MN1"};
    int tfMinutes[] = {1, 5, 15, 60, 240, 1440, 10080, 43200};

    // Use TH colors for ATR
    color colors[] = {
        clrBlack,        // M1
        clrBlack,        // M5
        clrBlack,        // M15
        clrBlue,         // H1
        clrRed,          // H4
        clrGreen,        // D1
        clrBlack,        // W1
        clrBlack         // MN1
    };
    
    bool isVerticalLayout = (inpLabelArrangement == LABEL_ARRANGEMENT_VERTICAL);
    int rowSpacing = inpLabelRowGap;
    int horizontalPadding = inpLabelColumnGap;
    int startXPos = inpLabelsMarginLeft;
    int lineGap = rowSpacing;
    int singleLineHeight = inpFontSize + lineGap;
    int titleYPos = inpLabelsMarginTop + g_currentLabelYOffset;
    int startYPos = isVerticalLayout ? (titleYPos + singleLineHeight) : titleYPos;
    int sectionGap = inpSectionGap;
    
    string titleObjName = labelPrefix + "ATR_Title";
    if(ObjectFind(0, titleObjName) < 0) {
        ObjectCreate(0, titleObjName, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, titleObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    ObjectSetString(0, titleObjName, OBJPROP_TEXT, "ATR:");
    ObjectSetInteger(0, titleObjName, OBJPROP_COLOR, clrDarkBlue);
    ObjectSetString(0, titleObjName, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, titleObjName, OBJPROP_FONTSIZE, inpFontSize);
    ObjectSetInteger(0, titleObjName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, titleObjName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, titleObjName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, titleObjName, OBJPROP_HIDDEN, false);
    ObjectSetInteger(0, titleObjName, OBJPROP_XDISTANCE, inpLabelsMarginLeft);
    ObjectSetInteger(0, titleObjName, OBJPROP_YDISTANCE, titleYPos);
    ObjectSetInteger(0, titleObjName, OBJPROP_TIMEFRAMES, IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    
    int titleWidth = (int)CalculateTextWidth("ATR:");
    int labelStartX = GetLabelStartX(startXPos, titleWidth, horizontalPadding, isVerticalLayout);
    int currentXPos = labelStartX;
    int currentYPos = startYPos;
    int xStep = horizontalPadding;
    int maxWidth = GetCachedChartWidth() - startXPos * 2;
    int lineHeight = GetLabelLineHeight(inpShowATRTargets, rowSpacing);
    
    int renderedCount = 0;
    for(int i = 0; i < ArraySize(timeframes); i++) {
        double atrValue = GetATRForTimeframe(tfMinutes[i]);
        if(atrValue <= 0 || atrValue == EMPTY_VALUE) continue;
        
        double atrPoints = atrValue / point;
        double atrPips = NormalizeDouble(atrValue / pipSize, 1);
        color labelColor = colors[i];
    
        string mainText = inpShowTimeframeInLabels ?
            timeframes[i] + ": " + DoubleToString(atrPips, 1) :
            DoubleToString(atrPips, 1);
        string stepsText = "(" + DoubleToString(atrPips * 1.5, 1) + " - " + DoubleToString(atrPips * 1.75, 1) + " - " + DoubleToString(atrPips * 2.0, 1) + ")";
        string targetsText = DoubleToString(MathFloor(atrPips * 3.0), 0) + " - " + DoubleToString(MathFloor(atrPips * 5.0), 0) + " - " + DoubleToString(MathFloor(atrPips * 15.0), 0);
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowATRTargets);
    
        if(isVerticalLayout) {
            if(!CreateATRLabelSimple(labelPrefix, timeframes[i], atrPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentYPos += lineHeight;
        } else {
            if(currentXPos + labelWidth + xStep > maxWidth) {
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateATRLabelSimple(labelPrefix, timeframes[i], atrPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentXPos += labelWidth + xStep;
        }
        renderedCount++;
    }
    
    if(renderedCount > 0) {
        g_currentLabelYOffset += (currentYPos - startYPos) + lineHeight + sectionGap;
    }
}

void SetATRLabelsVisibility(const string objectPrefix, const bool visible) {
    string currentTFStr = IntegerToString(GetCachedPeriod());
    string uniquePrefix = objectPrefix + "TF" + currentTFStr + "_";
    string allTimeframes[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN1"};

    bool shouldShow = (visible && !IsIndicatorHidden());
    long tf = shouldShow ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;

    ObjectSetInteger(0, uniquePrefix + "ATR_Title", OBJPROP_TIMEFRAMES, tf);

    long targetsTF = (shouldShow && inpShowATRTargets) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    for(int i = 0; i < ArraySize(allTimeframes); i++) {
        string tfName = allTimeframes[i];
        ObjectSetInteger(0, uniquePrefix + "ATR_" + tfName, OBJPROP_TIMEFRAMES, tf);
        ObjectSetInteger(0, uniquePrefix + "ATR_Steps_" + tfName, OBJPROP_TIMEFRAMES, tf);
        ObjectSetInteger(0, uniquePrefix + "ATR_Targets_" + tfName, OBJPROP_TIMEFRAMES, targetsTF);
    }
}

void SetTHLabelsVisibility(const string objectPrefix, const int mode) {
    bool shouldShow = ((mode != 0) && !IsIndicatorHidden());
    long tf = shouldShow ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;

    ObjectSetInteger(0, objectPrefix + "TH_Title", OBJPROP_TIMEFRAMES, tf);

    bool showFractal = (mode == 1 || mode == 3);
    bool showStandard = (mode == 2 || mode == 3);

    long fractalTF = (shouldShow && showFractal) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long fractalTargetsTF = (shouldShow && showFractal && inpShowTHTargets) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    for(int i = 0; i < ArraySize(FRACTAL_TIMEFRAMES); i++) {
        string timeframeName = FRACTAL_TIMEFRAMES[i];
        ObjectSetInteger(0, objectPrefix + "TH_" + timeframeName, OBJPROP_TIMEFRAMES, fractalTF);
        ObjectSetInteger(0, objectPrefix + "TH_Steps_" + timeframeName, OBJPROP_TIMEFRAMES, fractalTF);
        ObjectSetInteger(0, objectPrefix + "TH_Targets_" + timeframeName, OBJPROP_TIMEFRAMES, fractalTargetsTF);
    }
    long standardTF = (shouldShow && showStandard) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long standardTargetsTF = (shouldShow && showStandard && inpShowTHTargets) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    for(int i = 0; i < ArraySize(STANDARD_TIMEFRAMES); i++) {
        string timeframeName = STANDARD_TIMEFRAMES[i];
        ObjectSetInteger(0, objectPrefix + "TH_" + timeframeName, OBJPROP_TIMEFRAMES, standardTF);
        ObjectSetInteger(0, objectPrefix + "TH_Steps_" + timeframeName, OBJPROP_TIMEFRAMES, standardTF);
        ObjectSetInteger(0, objectPrefix + "TH_Targets_" + timeframeName, OBJPROP_TIMEFRAMES, standardTargetsTF);
    }
}

//+------------------------------------------------------------------+
//| TH label helpers (ported from MT5)                               |
//+------------------------------------------------------------------+
bool CreateTHLabel(const string objectPrefix, const string timeframeName, const double thValuePoints, const int xPos, const int yPos, const color textColor, const int horizontalSpacing, const int verticalSpacing) {
    double point = GetCachedPoint();
    double pipSize = GetCachedPipSize();
    if(IsZero(point, EPSILON_PRICE) || IsZero(pipSize, EPSILON_PRICE)) return false;
    
    double thValuePips = NormalizeDouble((thValuePoints * point) / pipSize, 1);
    double shortStepPips = NormalizeDouble(thValuePips * SS_MULTIPLIER, 1);
    double longStepPips = NormalizeDouble(thValuePips * LS_MULTIPLIER, 1);
    double midStepPips = NormalizeDouble((shortStepPips + longStepPips) / 2.0, 1);
    double target3x = MathFloor(thValuePips * 3.0);
    double target5x = MathFloor(thValuePips * 5.0);
    double target15x = MathFloor(thValuePips * 15.0);
    
    string mainObjName = objectPrefix + "TH_" + timeframeName;
    string stepsObjName = objectPrefix + "TH_Steps_" + timeframeName;
    string targetsObjName = objectPrefix + "TH_Targets_" + timeframeName;
    
    bool mainCreated = false;
    bool stepsCreated = false;
    bool targetsCreated = false;
    
    if (ObjectFind(0, mainObjName) < 0) {
        if (!ObjectCreate(0, mainObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, mainObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        mainCreated = true;
    }
    if (ObjectFind(0, stepsObjName) < 0) {
        if (!ObjectCreate(0, stepsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, stepsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        stepsCreated = true;
    }
    if (inpShowTHTargets && ObjectFind(0, targetsObjName) < 0) {
        if (!ObjectCreate(0, targetsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, targetsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        targetsCreated = true;
    }
    
    if(!inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
        ObjectDelete(0, targetsObjName);
    }

    string mainText = GetBaseTimeframeName(timeframeName) + ": " + DoubleToString(thValuePips, 1);
    string stepsText = "(" + DoubleToString(shortStepPips, 1) + " - " + DoubleToString(midStepPips, 1) + " - " + DoubleToString(longStepPips, 1) + ")";
    string targetsText = DoubleToString(target3x, 0) + " - " + DoubleToString(target5x, 0) + " - " + DoubleToString(target15x, 0);
    
    // PERF: Only update text/color if changed (using Cache)
    string cachedText;
    color cachedColor;
    bool exists = CacheGetLabel(mainObjName, cachedText, cachedColor);
    
    bool textChanged = !exists || (cachedText != mainText);
    bool colorChanged = !exists || (cachedColor != textColor);
    
    if(textChanged) {
        ObjectSetString(0, mainObjName, OBJPROP_TEXT, mainText);
        ObjectSetString(0, stepsObjName, OBJPROP_TEXT, stepsText);
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
            ObjectSetString(0, targetsObjName, OBJPROP_TEXT, targetsText);
        }
        CacheUpdateLabel(mainObjName, mainText, textColor);
    }
    
    if(colorChanged) {
        ObjectSetInteger(0, mainObjName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(0, stepsObjName, OBJPROP_COLOR, textColor);
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
            ObjectSetInteger(0, targetsObjName, OBJPROP_COLOR, textColor);
        }
        CacheUpdateLabel(mainObjName, mainText, textColor);
    }
    
    if(mainCreated) SetLabelFont(mainObjName);
    if(stepsCreated) SetLabelFont(stepsObjName);
    if(targetsCreated) SetLabelFont(targetsObjName);
    
    ENUM_BASE_CORNER corner = CORNER_LEFT_LOWER;
    ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
    
    if(mainCreated) {
        ObjectSetInteger(0, mainObjName, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, mainObjName, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(0, mainObjName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, mainObjName, OBJPROP_HIDDEN, false);
    }
    if(stepsCreated) {
        ObjectSetInteger(0, stepsObjName, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, stepsObjName, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(0, stepsObjName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, stepsObjName, OBJPROP_HIDDEN, false);
    }
    if(targetsCreated) {
        ObjectSetInteger(0, targetsObjName, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, targetsObjName, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(0, targetsObjName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, targetsObjName, OBJPROP_HIDDEN, false);
    }
    
    int labelXDistance = MathAbs(xPos);
    int bottomPadding = 0;
    int lineGap = inpLabelRowGap;
    int singleLineHeight = inpFontSize + lineGap;
    
    int mainTextWidth = (int)(StringLen(mainText) * inpFontSize * FONT_CHAR_WIDTH_FACTOR);
    int stepsTextWidth = (int)(StringLen(stepsText) * inpFontSize * FONT_CHAR_WIDTH_FACTOR);
    int mainOffset = (stepsTextWidth - mainTextWidth) / 2;
    if(mainOffset < 0) mainOffset = 0;
    
    int targetsOffset = 0;
    if(inpShowTHTargets) {
        int targetsTextWidth = (int)(StringLen(targetsText) * inpFontSize * FONT_CHAR_WIDTH_FACTOR);
        targetsOffset = (mainTextWidth - targetsTextWidth) / 2 + mainOffset;
        if(targetsOffset < 0) targetsOffset = 0;
    }
    
    int baseY = MathAbs(yPos) + bottomPadding;
    if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
        ObjectSetInteger(0, targetsObjName, OBJPROP_YDISTANCE, baseY);
        ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight);
        ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight * 2);
        ObjectSetInteger(0, targetsObjName, OBJPROP_XDISTANCE, labelXDistance + targetsOffset);
    } else {
        ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY);
        ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight);
    }
    
    ObjectSetInteger(0, mainObjName, OBJPROP_XDISTANCE, labelXDistance + mainOffset);
    ObjectSetInteger(0, stepsObjName, OBJPROP_XDISTANCE, labelXDistance);
    
    // Respect Hide state (F key)
    if(IsIndicatorHidden()) {
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    } else {
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    
    return true;
}

void DisplayFractalTHs(const string objectPrefix, const double dailyPriceForTH, const datetime currentTime) {
    if(!g_thLabelsVisible || (g_thLabelsMode != 1 && g_thLabelsMode != 3)) return;
    
    double point = GetCachedPoint();
    int digits = GetCachedDigits();
    if(IsZero(point, EPSILON_PRICE) || digits == 0) return;

    string labelPrefix = objectPrefix + "LBL_";
    bool isVerticalLayout = (inpLabelArrangement == LABEL_ARRANGEMENT_VERTICAL);
    int rowSpacing = inpLabelRowGap;
    int horizontalPadding = inpLabelColumnGap;
    int startXPos = inpLabelsMarginLeft;
    int lineGap = rowSpacing;
    int singleLineHeight = inpFontSize + lineGap;
    int titleYPos = inpTHLabelsMarginBottom + g_currentLabelYOffsetBottom;
    int startYPos = isVerticalLayout ? (titleYPos + singleLineHeight) : titleYPos;
    int sectionGap = inpSectionGap;

    string thTitleObjName = labelPrefix + "TH_Title";
    if(ObjectFind(0, thTitleObjName) < 0) {
        ObjectCreate(0, thTitleObjName, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, thTitleObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    ObjectSetString(0, thTitleObjName, OBJPROP_TEXT, "TH:");
    ObjectSetInteger(0, thTitleObjName, OBJPROP_COLOR, clrDarkBlue);
    ObjectSetString(0, thTitleObjName, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_FONTSIZE, inpFontSize);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_HIDDEN, false);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_XDISTANCE, inpLabelsMarginLeft);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_YDISTANCE, titleYPos + (inpShowTHTargets ? singleLineHeight * 2 : singleLineHeight));
    ObjectSetInteger(0, thTitleObjName, OBJPROP_TIMEFRAMES, IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);

    int titleWidth = (int)CalculateTextWidth("TH:");
    int labelStartX = GetLabelStartX(startXPos, titleWidth, horizontalPadding, isVerticalLayout);
    int currentXPos = labelStartX;
    int currentYPos = startYPos;
    int xStep = horizontalPadding;
    int maxWidth = GetCachedChartWidth() - startXPos * 2;
    int lineHeight = GetLabelLineHeight(inpShowTHTargets, rowSpacing);

    for(int i = 0; i < ArraySize(FRACTAL_TIMEFRAMES); i++) {
        string timeframeName = FRACTAL_TIMEFRAMES[i];
        double percentage = MODIFIED_FRACTAL_PERCENTAGES[i];
        double thPoints = CalculateTHPoints(dailyPriceForTH, digits, percentage);
        
        color labelColor = FRACTAL_COLORS[i];
        string mainText = inpShowTimeframeInLabels ? GetBaseTimeframeName(timeframeName) + ": " + DoubleToString(thPoints / 10.0, 1) : DoubleToString(thPoints / 10.0, 1);
        string stepsText = "(" + DoubleToString(thPoints / 10.0 * 1.5, 1) + " - " + DoubleToString(thPoints / 10.0 * 1.75, 1) + " - " + DoubleToString(thPoints / 10.0 * 2.0, 1) + ")";
        string targetsText = DoubleToString(MathFloor(thPoints / 10.0 * 3.0), 0) + " - " + DoubleToString(MathFloor(thPoints / 10.0 * 5.0), 0) + " - " + DoubleToString(MathFloor(thPoints / 10.0 * 15.0), 0);
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowTHTargets);

        if(isVerticalLayout) {
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentYPos += lineHeight;
        } else {
            if(currentXPos + labelWidth + xStep > maxWidth) {
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentXPos += labelWidth + xStep;
        }
    }

    g_currentLabelYOffsetBottom += (currentYPos - startYPos) + lineHeight + sectionGap;
}

void DisplayStandardTHs(const string objectPrefix, const double dailyPriceForTH, const datetime currentTime) {
    if(!g_thLabelsVisible || (g_thLabelsMode != 2 && g_thLabelsMode != 3)) return;

    double point = GetCachedPoint();
    int digits = GetCachedDigits();
    if(IsZero(point, EPSILON_PRICE) || digits == 0) return;

    string labelPrefix = objectPrefix + "LBL_";
    bool isVerticalLayout = (inpLabelArrangement == LABEL_ARRANGEMENT_VERTICAL);
    int rowSpacing = inpLabelRowGap;
    int horizontalPadding = inpLabelColumnGap;
    int startXPos = inpLabelsMarginLeft;
    int lineGap = rowSpacing;
    int singleLineHeight = inpFontSize + lineGap;
    int titleYPos = inpTHLabelsMarginBottom + g_currentLabelYOffsetBottom;
    int startYPos = isVerticalLayout ? (titleYPos + singleLineHeight) : titleYPos;
    int sectionGap = inpSectionGap;

    string thTitleObjName = labelPrefix + "TH_Title";
    if(ObjectFind(0, thTitleObjName) < 0) {
        ObjectCreate(0, thTitleObjName, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, thTitleObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    // Title already set in DisplayFractalTHs if BOTH mode, but we update Y position here
    ObjectSetInteger(0, thTitleObjName, OBJPROP_YDISTANCE, titleYPos + (inpShowTHTargets ? singleLineHeight * 2 : singleLineHeight));

    int titleWidth = (int)CalculateTextWidth("TH:");
    int labelStartX = GetLabelStartX(startXPos, titleWidth, horizontalPadding, isVerticalLayout);
    int currentXPos = labelStartX;
    int currentYPos = startYPos;
    int xStep = horizontalPadding;
    int maxWidth = GetCachedChartWidth() - startXPos * 2;
    int lineHeight = GetLabelLineHeight(inpShowTHTargets, rowSpacing);

    for(int i = 0; i < ArraySize(STANDARD_TIMEFRAMES); i++) {
        string timeframeName = STANDARD_TIMEFRAMES[i];
        double percentage = CalculateStandardPercentage(STANDARD_MINUTES[i]);
        double thPoints = CalculateTHPoints(dailyPriceForTH, digits, percentage);
        
        color labelColor = STANDARD_COLORS[i];
        string mainText = inpShowTimeframeInLabels ? timeframeName + ": " + DoubleToString(thPoints / 10.0, 1) : DoubleToString(thPoints / 10.0, 1);
        string stepsText = "(" + DoubleToString(thPoints / 10.0 * 1.5, 1) + " - " + DoubleToString(thPoints / 10.0 * 1.75, 1) + " - " + DoubleToString(thPoints / 10.0 * 2.0, 1) + ")";
        string targetsText = DoubleToString(MathFloor(thPoints / 10.0 * 3.0), 0) + " - " + DoubleToString(MathFloor(thPoints / 10.0 * 5.0), 0) + " - " + DoubleToString(MathFloor(thPoints / 10.0 * 15.0), 0);
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowTHTargets);

        if(isVerticalLayout) {
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentYPos += lineHeight;
        } else {
            if(currentXPos + labelWidth + xStep > maxWidth) {
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentXPos += labelWidth + xStep;
        }
    }

    g_currentLabelYOffsetBottom += (currentYPos - startYPos) + lineHeight + sectionGap;
}

void StoreLabelPosition(const string name, const int xPos, const int yPos) {
    for(int i=0; i<ArraySize(g_labelPositions); i++) {
        if(g_labelPositions[i].name == name) {
            g_labelPositions[i].xPos = xPos;
            g_labelPositions[i].yPos = yPos;
            return;
        }
    }
    int size=ArraySize(g_labelPositions);
    if(ArrayResize(g_labelPositions,size+1)) {
        g_labelPositions[size].name=name;
        g_labelPositions[size].xPos=xPos;
        g_labelPositions[size].yPos=yPos;
    } else {
        Print("StoreLabelPosition: Failed to resize array");
    }
}

int GetStoredXPosition(const string name) {
    for(int i=0; i<ArraySize(g_labelPositions); i++) if(g_labelPositions[i].name==name) return g_labelPositions[i].xPos;
    return inpInitialX;
}

double CalculateTextWidth(string text) {
    static int lastFontSize = -1;
    static double charWidth = 0;
    static double plusAdd = 0;
    static double numAdd = 0;
    
    if(inpFontSize != lastFontSize) {
        lastFontSize = inpFontSize;
        charWidth = lastFontSize * 0.7;
        plusAdd = lastFontSize * 0.3;
        numAdd = lastFontSize * 0.2;
    }
    
    int len = StringLen(text);
    if(len == 0) return 0;
    
    bool hasPlus = false;
    bool hasNum = false;
    for(int i=0; i<len; i++) {
        ushort c = StringGetCharacter(text, i);
        if(c >= '0' && c <= '9') hasNum = true;
        else if(c == '+') hasPlus = true;
        if(hasPlus && hasNum) break;
    }
    
    return len * charWidth + (hasPlus ? plusAdd : 0) + (hasNum ? numAdd : 0);
}

//+------------------------------------------------------------------+
//| Label layout helpers (ported from MT5)                            |
//+------------------------------------------------------------------+
int GetLabelLineHeight(const bool showTargets, const int rowSpacing) {
    int lines = showTargets ? 3 : 2;
    return (inpFontSize + rowSpacing) * lines;
}

int GetLabelBlockWidth(const string mainText, const string stepsText, const string targetsText, const bool showTargets) {
    int maxW = (int)CalculateTextWidth(mainText);
    int stepsWidth = (int)CalculateTextWidth(stepsText);
    if(stepsWidth > maxW) maxW = stepsWidth;
    if(showTargets) {
        int targetsWidth = (int)CalculateTextWidth(targetsText);
        if(targetsWidth > maxW) maxW = targetsWidth;
    }
    return maxW;
}

int GetLabelStartX(const int baseX, const int titleWidth, const int padding, const bool isVertical) {
    int titleGap = MathMin(padding, 6);
    return isVertical ? baseX : baseX + titleWidth + titleGap;
}

int GetBottomTitleYOffset(const bool showTargets, const int rowSpacing) {
    int singleLineHeight = inpFontSize + rowSpacing;
    return showTargets ? singleLineHeight * 2 : singleLineHeight;
}

string StringRepeat(string str, int count) {
    string result = "";
    for(int i=0; i<count; i++) {
        result = result + str;
    }
    return result;
}


//+------------------------------------------------------------------+
//| Create/Update Timeframe Lock Status Label                        |
//| Shows lock status and timeframe when locked (small, left corner) |
//+------------------------------------------------------------------+
void UpdateLockStatusLabel()
{
    // Position: Top-left corner, very top
    int xDistance = 5;
    int yDistance = 5;
    
    if(g_timeframeLocked)
    {
        // Create or update label showing locked timeframe (no emoji - MT4 doesn't support)
        string lockText = "[LOCK:" + PeriodToString(g_lockedPeriod) + "]";
        
        if(ObjectFind(0, g_lockStatusLabelName) < 0)
        {
            if(!ObjectCreate(0, g_lockStatusLabelName, OBJ_LABEL, 0, 0, 0))
            {
                Print("Failed to create lock status label. Error: ", GetLastError());
                return;
            }
        }
        
        ObjectSetString(0, g_lockStatusLabelName, OBJPROP_TEXT, lockText);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_COLOR, clrGold);
        ObjectSetString(0, g_lockStatusLabelName, OBJPROP_FONT, inpFontName);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_XDISTANCE, xDistance);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_YDISTANCE, yDistance);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_HIDDEN, false);
        ObjectSetString(0, g_lockStatusLabelName, OBJPROP_TOOLTIP, "TF locked to " + PeriodToString(g_lockedPeriod) + " - Press " + inpLockKey + " to unlock");
    }
    else
    {
        // Delete label when unlocked
        if(ObjectFind(0, g_lockStatusLabelName) >= 0)
        {
            ObjectDelete(0, g_lockStatusLabelName);
        }
    }
}

//+------------------------------------------------------------------+
//| Convert period to readable string                                |
//+------------------------------------------------------------------+
string PeriodToString(int period)
{
    switch(period)
    {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN";
        default:         return "TF" + IntegerToString(period);
    }
}



#endif // LABEL_FUNCTIONS_MQH
