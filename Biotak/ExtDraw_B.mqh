// ExtDraw_B.mqh - ExtendedDrawingFunctions.mqh split 2026-09-29: exact lines 1382-2316, byte-identical, zero renames.
#ifndef EXT_DRAW_B_MQH
#define EXT_DRAW_B_MQH

//+------------------------------------------------------------------+
//| Get highest structure level for a given step                     |
//|                                                                 |
//|                                                                  |
//| Returns the highest level (1-5) that this step belongs to       |
//| Returns 0 if step is not a structure level (i.e., trigger)      |
//|                                                                  |
//| EXAMPLES with Base=4:                                            |
//| Step 4:  Returns 1 (L1 only)                                    |
//| Step 8:  Returns 1 (L1 only)                                    |
//| Step 16: Returns 2 (L2, not L1)                                 |
//| Step 64: Returns 3 (L3, not L2 or L1)                           |
//| Step 5:  Returns 0 (Trigger, not Structure)                     |
//|                                                                  |
//| SECURITY: Full input validation with safe defaults              |
//|                                                                  |
//| @param step The step number to check                            |
//| @param intervals Array of structure intervals [L1, L2, L3, L4, L5] |
//| @return Highest level (1-5) or 0 if trigger/invalid             |
//+------------------------------------------------------------------+
int GetHighestStructureLevel(const int step, const int &intervals[]) {
    // SECURITY: Validate inputs
    if(step == 0) return 0; // Midpoint is not a structure level
    
    int absStep = MathAbs(step);
    if(absStep <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   GetHighestStructureLevel: Invalid step=", step);
        #endif
        return 0;
    }
    
    // SECURITY: Validate array size
    int arraySize = ArraySize(intervals);
    if(arraySize != 5) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetHighestStructureLevel: Invalid intervals array size=", arraySize, " (expected 5)");
        #endif
        return 0;
    }
    
    // SECURITY: Validate intervals are positive and in ascending order
    for(int i = 0; i < 5; i++) {
        if(intervals[i] <= 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("  GetHighestStructureLevel: Invalid interval[", i, "]=", intervals[i]);
            #endif
            return 0;
        }
        // Check ascending order (L2 > L1, L3 > L2, etc.)
        if(i > 0 && intervals[i] <= intervals[i-1]) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("  GetHighestStructureLevel: Intervals not in ascending order at index ", i);
            #endif
            return 0;
        }
    }
    
    // Check from highest to lowest (L5   L4   L3   L2   L1)
    // Use absStep to handle both positive and negative steps
    if(absStep % intervals[4] == 0) return 5;
    if(absStep % intervals[3] == 0) return 4;
    if(absStep % intervals[2] == 0) return 3;
    if(absStep % intervals[1] == 0) return 2;
    if(absStep % intervals[0] == 0) return 1;
    
    return 0; // Trigger level
}

//+------------------------------------------------------------------+
//| Get path/style for level based on step count                    |
//| Matches Java's getPathForLevel (line 130)                       |
//| Returns true if level should be drawn with output parameters    |
//| Uses configurable base multiplier to calculate Structure levels |
//| OPTIMIZED VERSION: Takes triggerEnabled as parameter            |
//+------------------------------------------------------------------+
bool GetPathForLevelOptimized(const int stepCount, color &outColor, ENUM_LINE_STYLE &outStyle, int &outWidth, const bool triggerEnabled) {
    // First check structure levels (matching Java getPathForLevel line 131-136)
    if(inpShowStructure) {
        // Get validated base multiplier (auto-corrects if invalid)
        int baseMultiplier = GetValidatedBaseMultiplier();
        
        // Get cached intervals (recalculates only if base changed)
        int intervals[];
        GetCachedIntervals(baseMultiplier, intervals);
        
        // Check from highest to lowest level to ensure priority
        // (e.g., step 16 with base=4 is both L2 and multiple of L1, but L2 takes priority)
        
        // Level 5: base^5
        if(intervals[4] > 0 && stepCount % intervals[4] == 0 && inpShowStructureL5) {
            outColor = inpStructureL5Color;
            outStyle = inpStructureL5Style;
            outWidth = inpStructureL5Width;
            return true;
        }
        
        // Level 4: base^4
        if(intervals[3] > 0 && stepCount % intervals[3] == 0 && inpShowStructureL4) {
            outColor = inpStructureL4Color;
            outStyle = inpStructureL4Style;
            outWidth = inpStructureL4Width;
            return true;
        }
        
        // Level 3: base^3
        if(intervals[2] > 0 && stepCount % intervals[2] == 0 && inpShowStructureL3) {
            outColor = inpStructureL3Color;
            outStyle = inpStructureL3Style;
            outWidth = inpStructureL3Width;
            return true;
        }
        
        // Level 2: base^2
        if(intervals[1] > 0 && stepCount % intervals[1] == 0 && inpShowStructureL2) {
            outColor = inpStructureL2Color;
            outStyle = inpStructureL2Style;
            outWidth = inpStructureL2Width;
            return true;
        }
        
        // Level 1: base^1
        if(intervals[0] > 0 && stepCount % intervals[0] == 0 && inpShowStructureL1) {
            outColor = inpStructureL1Color;
            outStyle = inpStructureL1Style;
            outWidth = inpStructureL1Width;
            return true;
        }
    }
    
    // Structure levels NEVER fall back to the trigger styling when the trigger
    // overlay is toggled - that coupling restyled these lines on every T press.
    // If no structure level matches, the caller falls back to the mode's own
    // styling (config.fallback / config.midpoint), independent of triggerEnabled.
    return false;
}

//+------------------------------------------------------------------+
//| Get Zone Color for level (uses CURRENT level's color)           |
//|            Zone          (                              )        |
//|                                                                  |
//| Logic: Zone uses SAME logic as level drawing                    |
//|     : Zone                                                      |
//|                                                                  |
//| Priority: Structure (L5>L4>L3>L2>L1) > Trigger > Mode Color     |
//|       :         (L5>L4>L3>L2>L1) >       >     Mode              |
//|                                                                  |
//| @param currentStep Current step number (must be > 0)            |
//| @param triggerEnabled Whether trigger levels are enabled        |
//| @param baseMultiplier Base multiplier for structure levels      |
//| @return Zone color (clrNONE = use mode's default color)         |
//+------------------------------------------------------------------+
color GetZoneColorForLevel(const int currentStep, const bool triggerEnabled, const int baseMultiplier) {
    // VALIDATION: Check if zones are enabled
    if(!inpShowMidZones) return clrNONE;
    
    // VALIDATION: Ensure currentStep is valid (avoid division by zero issues)
    if(currentStep <= 0) return clrNONE;
    
    // PRIORITY 1: Check structure levels first (L5 > L4 > L3 > L2 > L1)
    //         :                               
    if(inpShowStructure) {
        // VALIDATION: Ensure baseMultiplier is valid before using it
        // Use GetValidatedBaseMultiplier for consistency
        int validatedMultiplier = baseMultiplier;
        if(validatedMultiplier < 2 || validatedMultiplier > 9) {
            validatedMultiplier = GetValidatedBaseMultiplier(); // Use central validation
        }
        
        // OPTIMIZATION: Use cached intervals (recalculates only if base changed)
        int intervals[];
        GetCachedIntervals(validatedMultiplier, intervals);
        
        // Check from highest to lowest level (same as GetPathForLevelOptimized)
        // SAFETY: Check intervals[i] > 0 to avoid division by zero
        if(intervals[4] > 0 && currentStep % intervals[4] == 0 && inpShowStructureL5) {
            return inpStructureL5Color;
        }
        if(intervals[3] > 0 && currentStep % intervals[3] == 0 && inpShowStructureL4) {
            return inpStructureL4Color;
        }
        if(intervals[2] > 0 && currentStep % intervals[2] == 0 && inpShowStructureL3) {
            return inpStructureL3Color;
        }
        if(intervals[1] > 0 && currentStep % intervals[1] == 0 && inpShowStructureL2) {
            return inpStructureL2Color;
        }
        if(intervals[0] > 0 && currentStep % intervals[0] == 0 && inpShowStructureL1) {
            return inpStructureL1Color;
        }
    }
    
    // PRIORITY 2: If Trigger is enabled, DON'T use trigger color for zones
    //         :     Trigger                  Trigger      zone            
    // Zones should ONLY be drawn between structure levels, not trigger levels
    // Zone                 structure levels             trigger levels
    
    // PRIORITY 3: Fallback to mode's default color
    //         :                        mode
    return clrNONE;  // Signal to use level's own color (SS/LS/M/TP)
}


//+------------------------------------------------------------------+
//| Draw SS/LS levels with alternating pattern                      |
//+------------------------------------------------------------------+
bool DrawUnifiedLevel(
    const string levelName,
    const double price,
    const int logicalStep,
    const bool triggerEnabled,
    const bool structureEnabled,
    const int baseMultiplier,
    const color fallbackColor,
    const ENUM_LINE_STYLE fallbackStyle,
    const int fallbackWidth,
    const string tooltip)
{
    // Get path for this level - check Structure first, then Trigger
    color levelColor;
    ENUM_LINE_STYLE levelStyle;
    int levelWidth;
    
    if(GetPathForLevelOptimized(logicalStep, levelColor, levelStyle, levelWidth, triggerEnabled)) {
        // Got path from structure levels
    } else if(triggerEnabled) {
        // NOTE (unified-LINES split): the live pipeline (LevelPipeline.mqh)
        // no longer calls this helper — ALL lines share the [08.4] settings.
        // Kept coherent here in case a future caller revives it.
        levelColor = GetLineRenderColor();
        levelStyle = inpLineStyle;
        levelWidth = inpLineWidth;
    } else {
        // Use fallback color (mode-specific)
        levelColor = fallbackColor;
        levelStyle = fallbackStyle;
        levelWidth = fallbackWidth;
    }
    
    // Create or update the level line
    if(ObjectFind(0, levelName) < 0) {
        if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, price)) {
            return false;
        }
    }
    
    ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
    ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
    ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
    ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
    ObjectSetDouble(0, levelName, OBJPROP_PRICE, price);
    ObjectSetString(0, levelName, OBJPROP_TOOLTIP, tooltip);
    
    return true;
}

//+------------------------------------------------------------------+
//| UNIFIED HELPER: Draw Single Zone with Unified Logic              |
//|                  :                                               |
//+------------------------------------------------------------------+
void DrawFactorBoundaryLines(const string objectPrefix, const double highPrice, 
                              const double lowPrice, const double factor, const double stepSize)
{
    // Skip drawing High/Low lines when Custom Price mode is active
    // In Custom Price mode, user defines their own reference point (like other modes)
    if(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) {
        // Delete existing High/Low lines and labels if they exist
        ObjectDelete(0, objectPrefix + "Factor_High");
        ObjectDelete(0, objectPrefix + "Factor_Low");
        ObjectDelete(0, objectPrefix + "Factor_High_Label");
        ObjectDelete(0, objectPrefix + "Factor_Low_Label");
        return;
    }
    
    // Calculate pip size for tooltip
    double pipSize = GetCachedPipSize();
    double rangePips = (highPrice - lowPrice) / pipSize;
    double stepPips = stepSize / pipSize;
    
    // ========== Draw Historical HIGH line ==========
    string highLineName = objectPrefix + "Factor_High";
    if(ObjectFind(0, highLineName) < 0) {
        ObjectCreate(0, highLineName, OBJ_HLINE, 0, 0, highPrice);
    }
    ObjectSetDouble(0, highLineName, OBJPROP_PRICE, highPrice);
    ObjectSetInteger(0, highLineName, OBJPROP_COLOR, inpHighColor);
    ObjectSetInteger(0, highLineName, OBJPROP_STYLE, inpHighStyle);
    ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, inpHighWidth);
    ObjectSetInteger(0, highLineName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, highLineName, OBJPROP_SELECTED, false);
    ObjectSetString(0, highLineName, OBJPROP_TOOLTIP, 
        StringFormat("Historical HIGH | %s | Range: %.0f pips", 
            DoubleToString(highPrice, Digits), rangePips));
    
    // ========== Draw Historical LOW line ==========
    string lowLineName = objectPrefix + "Factor_Low";
    if(ObjectFind(0, lowLineName) < 0) {
        ObjectCreate(0, lowLineName, OBJ_HLINE, 0, 0, lowPrice);
    }
    ObjectSetDouble(0, lowLineName, OBJPROP_PRICE, lowPrice);
    ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, inpLowColor);
    ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, inpLowStyle);
    ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, inpLowWidth);
    ObjectSetInteger(0, lowLineName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, lowLineName, OBJPROP_SELECTED, false);
    ObjectSetString(0, lowLineName, OBJPROP_TOOLTIP, 
        StringFormat("Historical LOW | %s | Range: %.0f pips", 
            DoubleToString(lowPrice, Digits), rangePips));
    
    // ========== Draw HIGH label ==========
    string highLabelName = objectPrefix + "Factor_High_Label";
    datetime _lblTime1 = CacheGetFrameTime();
    if(ObjectFind(0, highLabelName) < 0) {
        ObjectCreate(0, highLabelName, OBJ_TEXT, 0, _lblTime1, highPrice);
    }
    ObjectSetDouble(0, highLabelName, OBJPROP_PRICE, highPrice);
    ObjectSetInteger(0, highLabelName, OBJPROP_TIME, _lblTime1);
    ObjectSetInteger(0, highLabelName, OBJPROP_COLOR, inpHighColor);
    ObjectSetInteger(0, highLabelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, highLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
    ObjectSetString(0, highLabelName, OBJPROP_FONT, BioChromeFont(false));
    ObjectSetString(0, highLabelName, OBJPROP_TEXT,
        StringFormat("  HIGH %s | Range: %.0f pips | F=%.2f | Step: %.1f pips",
            DoubleToString(highPrice, Digits), rangePips, factor, stepPips));
    ObjectSetInteger(0, highLabelName, OBJPROP_SELECTABLE, false);
    
    // ========== Draw LOW label ==========
    string lowLabelName = objectPrefix + "Factor_Low_Label";
    if(ObjectFind(0, lowLabelName) < 0) {
        ObjectCreate(0, lowLabelName, OBJ_TEXT, 0, _lblTime1, lowPrice);
    }
    ObjectSetDouble(0, lowLabelName, OBJPROP_PRICE, lowPrice);
    ObjectSetInteger(0, lowLabelName, OBJPROP_TIME, _lblTime1);
    ObjectSetInteger(0, lowLabelName, OBJPROP_COLOR, inpLowColor);
    ObjectSetInteger(0, lowLabelName, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, lowLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetString(0, lowLabelName, OBJPROP_FONT, BioChromeFont(false));
    ObjectSetString(0, lowLabelName, OBJPROP_TEXT, 
        StringFormat("  LOW %s | Range: %.0f pips | F=%.2f | Step: %.1f pips", 
            DoubleToString(lowPrice, Digits), rangePips, factor, stepPips));
    ObjectSetInteger(0, lowLabelName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw Factor levels with perfect equal spacing (aligned)          |
//|                                             (        )            |
//| Ensures all spacing is equal including at chart boundaries       |
//+------------------------------------------------------------------+
//| Draw Factor Levels with Harmonic Alternating Pattern             |
//|                                                                   |
//| Alternates between Base Step ( 2) and Large Step ( ratio)        |
//| Creates macro symmetry with micro variation                       |
#ifndef BUILD_LITE
//+------------------------------------------------------------------+
void DrawFactorLevelsHarmonic(const string objectPrefix, const double highPrice, 
                              const double lowPrice, const double factor, 
                              const double baseStepSize, const double harmonicRatio)
{
    //                                                                
    // CRITICAL INPUT VALIDATION
    //                                                                
    
    // Validate object prefix
    if(StringLen(objectPrefix) == 0) {
        Print("  DrawFactorLevelsHarmonic: Empty object prefix");
        return;
    }
    
    // Validate price range
    if(highPrice <= 0 || lowPrice <= 0) {
        Print("  DrawFactorLevelsHarmonic: Invalid prices - High=", highPrice, ", Low=", lowPrice);
        return;
    }
    if(highPrice <= lowPrice) {
        Print("  DrawFactorLevelsHarmonic: Invalid range - High must be > Low");
        return;
    }
    
    // Validate base step size
    if(baseStepSize <= 0) {
        Print("  DrawFactorLevelsHarmonic: Invalid base step size: ", baseStepSize);
        return;
    }
    
    // CRITICAL: Validate harmonic ratio with strict bounds
    if(harmonicRatio < MIN_HARMONIC_RATIO) {
        Print("  DrawFactorLevelsHarmonic: Ratio too small (", harmonicRatio, 
              ") - must be >= ", MIN_HARMONIC_RATIO, " for meaningful alternation");
        return;
    }
    if(harmonicRatio > MAX_HARMONIC_RATIO) {
        Print("  DrawFactorLevelsHarmonic: Ratio too large (", harmonicRatio, 
              ") - must be <= ", MAX_HARMONIC_RATIO);
        return;
    }
    
    //                                                                
    // CLEANUP OLD OBJECTS (prevent visual clutter)
    //                                                                
    
    // Delete old harmonic objects before drawing new ones
    ObjectsDeleteAll(0, objectPrefix + "Factor_Mid_", -1, -1);
    ObjectsDeleteAll(0, objectPrefix + "Factor_Up_", -1, -1);
    ObjectsDeleteAll(0, objectPrefix + "Factor_Down_", -1, -1);
    
    //                                                                
    // CALCULATE STEP SIZES
    //                                                                
    
    // Calculate large step size
    double largeStepSize = baseStepSize * harmonicRatio;
    
    // Validate large step doesn't exceed range
    double range = highPrice - lowPrice;
    if(largeStepSize > range) {
        Print("   DrawFactorLevelsHarmonic: Large step (", largeStepSize, 
              ") exceeds range (", range, ") - adjusting");
        largeStepSize = range * 0.5;  // Max 50% of range
    }
    
    // Calculate midpoint (center of range)
    double midpoint = NormalizeDouble((highPrice + lowPrice) / 2.0, Digits);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawFactorLevelsHarmonic ====================");
    Print("High=", highPrice, ", Low=", lowPrice, ", Range=", range);
    Print("Midpoint=", midpoint, ", Factor=", factor);
    Print("BaseStep=", baseStepSize, ", LargeStep=", largeStepSize);
    Print("Ratio=", harmonicRatio, " (", DoubleToString((harmonicRatio - 1.0) * 100, 1), "% larger)");
    #endif
    
    //                                                                
    // DRAW MIDPOINT LEVEL
    //                                                                
    
    string midName = objectPrefix + "Factor_Mid_0";
    if(ObjectFind(0, midName) < 0) {
        if(!ObjectCreate(0, midName, OBJ_HLINE, 0, 0, midpoint)) {
            Print("  Failed to create midpoint level. Error: ", GetLastError());
            return;
        }
    }
    
    ObjectSetDouble(0, midName, OBJPROP_PRICE, midpoint);
    ObjectSetInteger(0, midName, OBJPROP_COLOR, C'255,140,0');  // DarkOrange - visible on Lavender
    ObjectSetInteger(0, midName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, midName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, midName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, midName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, midName, OBJPROP_BACK, false);
    ObjectSetString(0, midName, OBJPROP_TOOLTIP, 
        StringFormat("   Harmonic Center | %s | F=%.2f | R=%.3f", 
            DoubleToString(midpoint, Digits), factor, harmonicRatio));
    
    //                                                                
    // PREPARE PATTERN ARRAY (optimization)
    //                                                                
    
    // Pattern: [baseStep, largeStep, baseStep, largeStep, ...]
    double stepPattern[2];
    stepPattern[0] = baseStepSize;   // Smaller step ( 2)
    stepPattern[1] = largeStepSize;  // Larger step ( ratio)
    
    //                                                                
    // CALCULATE MAX LEVELS (with safety limits)
    //                                                                
    
    // Calculate approximate max levels per side
    double halfRange = range / 2.0;
    double avgStep = (baseStepSize + largeStepSize) / 2.0;
    int maxLevelsPerSide = (int)MathCeil(halfRange / avgStep);
    
    // Safety limit to prevent infinite loops or MT4 hang
    const int MAX_HARMONIC_LEVELS = 2500;
    if(maxLevelsPerSide > MAX_HARMONIC_LEVELS) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   Clamping levels from ", maxLevelsPerSide, " to ", MAX_HARMONIC_LEVELS);
        #endif
        maxLevelsPerSide = MAX_HARMONIC_LEVELS;
    }
    
    // Additional safety: minimum step size check
    if(baseStepSize < GetCachedPoint() * 2) {
        Print("  DrawFactorLevelsHarmonic: Base step too small (", baseStepSize, 
              ") - must be >= ", GetCachedPoint() * 2);
        return;
    }
    
    //                                                                
    // CACHE TRIGGER STATE (optimization)
    //                                                                
    
    bool triggerEnabled = IsTriggerLevelsEnabled();
    bool structureEnabled = inpShowStructure;
    int baseMultiplier = GetValidatedBaseMultiplier(); // Use central validation
    
    //                                                                
    // DRAW LEVELS ABOVE MIDPOINT
    //                                                                
    
    double cumulative = 0;
    int levelsAbove = 0;
    int iterationCount = 0;  // Safety counter
    
    for(int i = 0; i < maxLevelsPerSide && iterationCount < MAX_HARMONIC_LEVELS * 2; i++, iterationCount++) {
        // Get step size for this iteration (alternating pattern)
        double step = stepPattern[i % 2];
        cumulative += step;
        double priceLevel = midpoint + cumulative;
        
        // CRITICAL: Stop if we exceed high price
        if(priceLevel > highPrice) {
            #ifdef ENABLE_DEBUG_LOGS
            if(i == 0) Print("   First level above midpoint exceeds high - step too large");
            #endif
            break;
        }
        
        // Normalize price
        priceLevel = NormalizeDouble(priceLevel, Digits);
        
        // Determine if this is base or large step
        bool isBase = (i % 2 == 0);
        
        //                                                                
        // PRIORITY SYSTEM FOR COLORS AND STYLES
        //                                                                
        // PRIORITY 1: Harmonic Pattern (always takes precedence)
        //   - Preserves alternating rhythm
        //   - No filtering (all levels drawn)
        // PRIORITY 2: Structure/Trigger (if Harmonic disabled)
        //   - Applies filtering based on baseMultiplier
        // PRIORITY 3: Default Factor colors
        //                                                                
        
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        bool shouldDraw = true;  // Default: draw all levels
        
        int logicalStep = i + 1;  // Step count for Structure levels
        
        // PRIORITY 1: Harmonic colors always take precedence
        levelColor = isBase ? inpHarmonicBaseColor : inpHarmonicLargeColor;
        levelStyle = inpFactorLevelStyle;
        levelWidth = isBase ? inpHarmonicBaseWidth : inpHarmonicLargeWidth;
        
        // NO FILTERING in Harmonic Mode - draw all levels to preserve pattern
        // (Structure/Trigger filtering would break the alternating rhythm)
        
        // Create level name
        string levelName = objectPrefix + "Factor_Up_" + IntegerToString(i + 1);
        
        // Create or update level
        if(ObjectFind(0, levelName) < 0) {
            if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, priceLevel)) {
                Print("   Failed to create level above ", i + 1, ". Error: ", GetLastError());
                continue;
            }
        }
        
        ObjectSetDouble(0, levelName, OBJPROP_PRICE, priceLevel);
        ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
        ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
        ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
        ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
            StringFormat("%s Step %d | %s | F=%.2f |  =%.1f", 
                (isBase ? "   Base" : "   Large"), i + 1, 
                DoubleToString(priceLevel, Digits), factor, step / GetCachedPoint()));
        
        levelsAbove++;
    }
    
    //                                                                
    // DRAW LEVELS BELOW MIDPOINT
    //                                                                
    
    cumulative = 0;
    int levelsBelow = 0;
    iterationCount = 0;  // Reset safety counter
    
    for(int i = 0; i < maxLevelsPerSide && iterationCount < MAX_HARMONIC_LEVELS * 2; i++, iterationCount++) {
        double step = stepPattern[i % 2];
        cumulative += step;
        double priceLevel = midpoint - cumulative;
        
        // CRITICAL: Stop if we go below low price
        if(priceLevel < lowPrice) {
            #ifdef ENABLE_DEBUG_LOGS
            if(i == 0) Print("   First level below midpoint goes below low - step too large");
            #endif
            break;
        }
        
        // Normalize price
        priceLevel = NormalizeDouble(priceLevel, Digits);
        
        bool isBase = (i % 2 == 0);
        
        //                                                                
        // PRIORITY SYSTEM FOR COLORS AND STYLES (same as above)
        //                                                                
        
        color levelColor;
        ENUM_LINE_STYLE levelStyle;
        int levelWidth;
        
        int logicalStep = i + 1;
        
        // PRIORITY 1: Harmonic colors always take precedence
        levelColor = isBase ? inpHarmonicBaseColor : inpHarmonicLargeColor;
        levelStyle = inpFactorLevelStyle;
        levelWidth = isBase ? inpHarmonicBaseWidth : inpHarmonicLargeWidth;
        
        // NO FILTERING in Harmonic Mode - draw all levels to preserve pattern
        
        string levelName = objectPrefix + "Factor_Down_" + IntegerToString(i + 1);
        
        if(ObjectFind(0, levelName) < 0) {
            if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, priceLevel)) {
                Print("   Failed to create level below ", i + 1, ". Error: ", GetLastError());
                continue;
            }
        }
        
        ObjectSetDouble(0, levelName, OBJPROP_PRICE, priceLevel);
        ObjectSetInteger(0, levelName, OBJPROP_COLOR, levelColor);
        ObjectSetInteger(0, levelName, OBJPROP_STYLE, levelStyle);
        ObjectSetInteger(0, levelName, OBJPROP_WIDTH, levelWidth);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
        ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
        ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
            StringFormat("%s Step %d | %s | F=%.2f |  =%.1f", 
                (isBase ? "   Base" : "   Large"), i + 1, 
                DoubleToString(priceLevel, Digits), factor, step / GetCachedPoint()));
        
        levelsBelow++;
    }
    
    //                                                                
    // FINAL REPORT
    //                                                                
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  DrawFactorLevelsHarmonic: Drew ", levelsAbove, " levels above, ", 
          levelsBelow, " levels below midpoint");
    Print("Total: ", (levelsAbove + levelsBelow + 1), " levels (including midpoint)");
    #endif
}
#endif

//+------------------------------------------------------------------+
void DrawFactorLevelsAligned(const string objectPrefix, const double highPrice, 
                             const double lowPrice, const double factor, const double stepSize)
{
    // Comprehensive input validation
    if(StringLen(objectPrefix) == 0) {
        Print("DrawFactorLevelsAligned: Empty object prefix");
        return;
    }
    if(highPrice <= 0 || lowPrice <= 0) {
        Print("DrawFactorLevelsAligned: Invalid prices - High=", highPrice, ", Low=", lowPrice);
        return;
    }
    if(highPrice <= lowPrice) {
        Print("DrawFactorLevelsAligned: Invalid range - High (", highPrice, ") must be greater than Low (", lowPrice, ")");
        return;
    }
    if(stepSize <= 0) {
        Print("DrawFactorLevelsAligned: Invalid step size: ", stepSize);
        return;
    }
    
    // Determine drawing direction based on current price position
    // GOAL: Put any unequal gap at the FARTHER boundary from current price
    // 
    // LOGIC:
    // - Starting from HIGH and going DOWN   last level ends near LOW
    // - Starting from LOW and going UP   last level ends near HIGH
    // - The "gap" (if any) appears where we END, not where we START
    // 
    // Therefore:
    // - To put gap at LOW (bottom)   start from HIGH (top)
    // - To put gap at HIGH (top)   start from LOW (bottom)
    // 
    // User wants gap at FARTHER boundary:
    // - If price closer to HIGH   gap should be at LOW   start from HIGH
    // - If price closer to LOW   gap should be at HIGH   start from LOW
    // 
    // CONCLUSION: Start from the boundary that is FARTHER from current price
    
    double currentPrice = Bid;
    double distToHigh = MathAbs(currentPrice - highPrice);
    double distToLow = MathAbs(currentPrice - lowPrice);
    
    // Start from FARTHER boundary so gap ends up at FARTHER side
    bool startFromHigh = (distToHigh > distToLow);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("Factor Direction: Price=", DoubleToString(currentPrice, Digits),
          ", DistHigh=", DoubleToString(distToHigh, Digits),
          ", DistLow=", DoubleToString(distToLow, Digits),
          ", Start=", (startFromHigh ? "HIGH" : "LOW"));
    #endif
    
    // Calculate how many levels fit in the range
    // Formula: totalLevels = floor(range / stepSize)
    // Example: range=0.78, stepSize=0.09   totalLevels = floor(8.67) = 8
    // This means we can fit 8 steps in the range
    // Since loop starts at i=1, we draw levels at: boundary + 1*step, boundary + 2*step, ..., boundary + 8*step
    double range = highPrice - lowPrice;
    int totalLevels = (int)MathFloor(range / stepSize);
    
    if(totalLevels <= 1) {
        Print("DrawFactorLevelsAligned: Not enough space (totalLevels=", totalLevels, 
              ", range=", DoubleToString(range, Digits), 
              ", stepSize=", DoubleToString(stepSize, Digits), ")");
        return;
    }
    
    // NOTE: We do NOT subtract 1 here!
    // The loop starts from i=1 (not i=0), so first level is at (boundary + stepSize)
    // This naturally avoids drawing ON the boundary itself
    // If we subtract 1, we lose one valid level that could fit in the range
    
    // Safety: Limit max levels to prevent performance issues
    const int MAX_FACTOR_LEVELS = 5000;
    if(totalLevels > MAX_FACTOR_LEVELS) {
        Print("DrawFactorLevelsAligned: WARNING - Too many levels (", totalLevels, 
              "), clamping to ", MAX_FACTOR_LEVELS);
        totalLevels = MAX_FACTOR_LEVELS;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("DrawFactorLevelsAligned: High=", highPrice, ", Low=", lowPrice, 
          ", Factor=", factor, ", StepSize=", stepSize, ", TotalLevels=", totalLevels,
          ", StartFrom=", (startFromHigh ? "HIGH" : "LOW"));
    #endif
    
    // Draw levels starting from nearest boundary
    double startPrice = startFromHigh ? highPrice : lowPrice;
    double direction = startFromHigh ? -1.0 : 1.0;  // -1 = downward, +1 = upward
    
    //                                                                
    // CLEANUP OLD ZONES
    //                         
    //                                                                
    // P-PERF-36: this was `if(inpShowMidZones)` - the same inverse guard the
    // live pipeline carried (see CleanupSurplusPipeline). A cleanup that only
    // runs while the feature is ON can never remove what the feature drew, so
    // switching the zones off left every zone on the chart. The three sibling
    // families below are already unconditional; this one now matches them.
    // NOTE: DrawFactorLevelsAligned has no callers today (the unified pipeline
    // owns Factor mode) - fixed anyway, because a wrong guard in dead code is a
    // landmine for whoever revives it.
    ObjectsDeleteAll(0, objectPrefix + "Factor_Zone_", -1, -1);
    
    int levelsDrawn = 0;
    int zoneCount = 0;  // Track zones drawn
    
    //                                                                
    // CALCULATE halfStep and zoneHeight ONCE (DRY principle)
    //                                    
    // Zone height = 25% of halfStep (12.5% above + 12.5% below midpoint)
    //                                                                
    double halfStep = stepSize / 2.0;
    double zoneHeight = halfStep * 0.25;  // 25% of halfStep (12.5% each side)
    
    //                                                                
    // MAIN LOOP: Draw levels and zones
    //          :                     
    //                                                                
    for(int i = 1; i <= totalLevels; i++) {
        // Calculate price for this level (aligned to boundary)
        double levelPrice = startPrice + (direction * stepSize * i);
        
        // Validate level is within range
        if(levelPrice < lowPrice || levelPrice > highPrice) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   Level ", i, " outside range: ", DoubleToString(levelPrice, Digits));
            #endif
            continue;  // Skip levels outside range
        }
        
        // Normalize price to symbol's digits
        double normalizedPrice = NormalizeDouble(levelPrice, Digits);
        
        //                                                            
        // DRAW MID-RANGE ZONE (BEFORE this level)
        //                  (              )
        // 
        // LOGIC: Draw zone between previous boundary/level and current level
        // - For i=1: Zone between start boundary and first level
        // - For i>1: Zone between previous level and current level
        //                                                            
        if(inpShowMidZones) {
            // Determine previous price (boundary for i=1, previous level for i>1)
            double prevPrice = (i == 1) ? startPrice : (startPrice + (direction * stepSize * (i-1)));
            prevPrice = NormalizeDouble(prevPrice, Digits);
            
            // Calculate midpoint between previous and current
            double midPoint = (normalizedPrice + prevPrice) / 2.0;
            
            // Calculate zone boundaries ( 12.5% of halfStep from midpoint)
            double zoneTop = midPoint + zoneHeight;
            double zoneBottom = midPoint - zoneHeight;
            
            // Normalize zone boundaries
            zoneTop = NormalizeDouble(zoneTop, Digits);
            zoneBottom = NormalizeDouble(zoneBottom, Digits);
            
            // Validate zone is within chart range
            if(zoneTop <= highPrice && zoneBottom >= lowPrice) {
                // Draw zone with style support
                string zoneName = objectPrefix + "Factor_Zone_" + IntegerToString(i);
                if(CreateFactorMidZone(zoneName, zoneTop, zoneBottom,
                                      inpFactorLevelColor,  // raw color: boxes follow midzone transparency (no double-blend; factor TR drives factor LINES via config)
                                      inpMidZoneStyle,  // Use unified zone style
                                      inpMidZoneTransparency)) {
                    zoneCount++;
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("  Zone ", i, ": Between ", DoubleToString(prevPrice, Digits),
                          " and ", DoubleToString(normalizedPrice, Digits),
                          " | Mid=", DoubleToString(midPoint, Digits),
                          " | Height=", DoubleToString(zoneHeight, Digits),
                          " | Style=", EnumToString(inpMidZoneStyle));
                    #endif
                }
            }
        }
        
        //
        // DRAW FACTOR LEVEL LINE
        //
        // RETIRED (unified-LINES split): this legacy helper is NOT called by
        // the live pipeline and its INVERTED trigger gating (show Factor
        // lines only when the trigger overlay is OFF) contradicts the current
        // rule — line visibility belongs to L / g_linesVisible alone, while
        // T gates only the trigger zones in RenderZones. Left untouched so a
        // future revival keeps the history visible; do NOT copy this pattern.
        //

        // Create level name
        string levelName = objectPrefix + "Factor_" + IntegerToString(i);
        
        // Check if Factor lines should be shown (INVERTED: show when Trigger is OFF)
        bool shouldShowLine = !IsTriggerLevelsEnabled();
        
        // Check if object exists
        bool objectExists = (ObjectFind(0, levelName) >= 0);
        
        if(shouldShowLine) {
            // Trigger ON: Create or update level
            if(!objectExists) {
                if(!ObjectCreate(0, levelName, OBJ_HLINE, 0, 0, normalizedPrice)) {
                    Print("DrawFactorLevelsAligned: Failed to create level ", i, ", Error: ", GetLastError());
                    continue;
                }
            }
            
            // Set level properties
            ObjectSetDouble(0, levelName, OBJPROP_PRICE, normalizedPrice);
            ObjectSetInteger(0, levelName, OBJPROP_COLOR, inpFactorLevelColor);
            ObjectSetInteger(0, levelName, OBJPROP_STYLE, inpFactorLevelStyle);
            ObjectSetInteger(0, levelName, OBJPROP_WIDTH, inpFactorLevelWidth);
            ObjectSetInteger(0, levelName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, levelName, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, levelName, OBJPROP_BACK, false);
            ObjectSetInteger(0, levelName, OBJPROP_ZORDER, Z_CHART_LINE);  // P-UI-31: above zones
            ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);  // Show on all timeframes
            
            // Set tooltip
            ObjectSetString(0, levelName, OBJPROP_TOOLTIP, 
                StringFormat("Factor Level %d | %s | F=%.2f", 
                    i, DoubleToString(normalizedPrice, Digits), factor));
            
            levelsDrawn++;
        } else {
            // Trigger OFF: Hide level if it exists
            if(objectExists) {
                ObjectSetInteger(0, levelName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);  // Hide on all timeframes
            }
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  DrawFactorLevelsAligned: Drew ", levelsDrawn, " levels and ", zoneCount, " zones");
    Print("   halfStep=", DoubleToString(halfStep, Digits), 
          ", zoneHeight=", DoubleToString(zoneHeight, Digits), " (25% of halfStep = 12.5% each side)");
    #endif
}

//+------------------------------------------------------------------+
//| Draw Harmonic Factor levels FROM CENTER (supports Custom Price) |
//|          Harmonic Factor         (            Custom Price)      |
//| Alternates between base and large steps from center              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Ensure intervals cache is populated (no array copy needed)       |
//| Thin wrapper over GetCachedIntervals' internal cache logic.      |
//| Shared with Lite — LevelPipeline.ClassifyLevels calls it.        |
//+------------------------------------------------------------------+
void EnsureIntervalsCache(const int baseMultiplier) {
    int validatedMultiplier = baseMultiplier;
    if(validatedMultiplier < 2 || validatedMultiplier > 9)
        validatedMultiplier = 3;
    if(g_cachedBaseMultiplier != validatedMultiplier) {
        for(int i = 0; i < 5; i++)
            g_cachedIntervals[i] = CalculateStructureInterval(validatedMultiplier, i + 1);
        g_cachedBaseMultiplier = validatedMultiplier;
    }
}

#ifndef BUILD_LITE
//+------------------------------------------------------------------+
//| Draw Factor Harmonic levels FROM CENTER                         |
//| Alternates between base and large steps from center              |
//| GOLD VERSION: With safety checks and performance optimization    |
//+------------------------------------------------------------------+
void ClearFactorLevels(const string objectPrefix)
{
    // PERF: single bulk-delete call replaces manual loop + individual deletes
    string factorPrefix = objectPrefix + "Factor_";
    ObjectsDeleteAll(0, factorPrefix);
    // Invalidate any object cache entries that matched
    CacheClear();
}

#endif // BUILD_LITE

#endif // EXT_DRAW_B_MQH
