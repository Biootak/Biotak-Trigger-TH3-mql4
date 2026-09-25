  #ifndef FRACTAL_TIMEFRAMES_MQH
#define FRACTAL_TIMEFRAMES_MQH
#property strict

string GetBaseFractalTimeframeForCurrent() {
    string currentTimeframe=GetCurrentTimeframe();
    if(currentTimeframe=="M1") return "M1";
    if(currentTimeframe=="M5") return "M4";
    if(currentTimeframe=="M15"||currentTimeframe=="M30") return "M16";
    if(currentTimeframe=="H1") return "H1+M4";
    if(currentTimeframe=="H4") return "H4+M16";
    if(currentTimeframe=="D1") return "H17+M4";
    if(currentTimeframe=="W1") return "D11+H9+M4";
    if(currentTimeframe=="MN1") return "D45+H12+M16";
    return "M1";
}

//==============================================================================
// P-TH-01 (2026-09-18) — THE TH PERCENTAGE KNOB. The calculation percentage must be
// adjustable for research, live from the panel, and the REST must not be touched
// («بقیه دست نمیخوره روابطه به جایی 66 دیگه چیزها میاد»).
// WHERE: there is no single "TH percentage" — `MODIFIED_FRACTAL_PERCENTAGES`
// (ConstantsAndEnums) is a nine-rung table read by the chart's own TF
// (`GetBaseFractalTimeframeForCurrent`; on D1 that rung is H17+M4 = 66.66%), and
// `CalculateTHPoints` does `(price * percentage) / 100.0`.
// WHAT THE KNOB IS: ONE ratio applied to EVERY rung, so 66.66 -> 75 on D1 makes the
// ladder 2.34/4.69/9.38/18.75/37.5/75/150/300/600 and every x2 relationship survives
// (Pattern one rung down stays half, Trigger still a quarter) — moving ONE rung would
// have been a different, silently broken feature.
// NOT SCALED, deliberately: AdaptiveScaling's JUMP_AGGRESSIVE walk and
// FrequencyOptimizer's reference scores read the RAW table as a measuring stick, not
// the drawn ladder (TH3Math's copy is retired with TH3TOOL-OFF).
// NOT A BUG: the knob also scales the theoreticalTH AdaptiveScaling divides the ATR by,
// so the displayed ATR/TH ratio moves with it (the TRUE ratio) — but not
// `g_fractalShift` on the default path. 0 = OFF = the professor's table, byte for byte.
//==============================================================================

//--- the professor's table, RAW. The ONE reader of the array, so a future
//--- caller cannot accidentally scale twice.
double FractalPercentRaw(const int index)
{
    int n = ArraySize(MODIFIED_FRACTAL_PERCENTAGES);
    if(index < 0 || index >= n) return 0.0;
    return MODIFIED_FRACTAL_PERCENTAGES[index];
}

//--- rung index of a fractal timeframe NAME, or -1. Same lookup the resolvers
//--- below do inline; here so the scale has one source for "my own rung".
int FractalRungIndex(const string timeframe)
{
    int n = ArraySize(FRACTAL_TIMEFRAMES);
    for(int i = 0; i < n; i++) {
        if(FRACTAL_TIMEFRAMES[i] == timeframe) return i;
    }
    return -1;
}

//--- the knob as ONE ratio. 1.0 = OFF (the professor's table untouched).
double FractalPercentScale()
{
    // P-UI-57: NaN <= 0.0 is false, so a non-finite override fell through and
    // poisoned every rung. Finite gate first; 0 = OFF (professor's table).
    if(!MathIsValidNumber(g_thPercentOverride) || g_thPercentOverride <= 0.0) return 1.0;
    int baseIdx = FractalRungIndex(GetBaseFractalTimeframeForCurrent());
    if(baseIdx < 0) return 1.0;
    double base = FractalPercentRaw(baseIdx);
    if(base <= 0.0) return 1.0;
    return g_thPercentOverride / base;
}

//--- the professor's table x the knob's ratio: the ONE reader every
//--- DRAWING and LABEL path must use (THCalculations, FractalTimeframes'
//--- own two resolvers, LabelFunctions' TH strip).
double FractalPercentScaled(const int index)
{
    return FractalPercentRaw(index) * FractalPercentScale();
}

string ApplyFractalShift(const string timeframeStr) {
    int shift = g_fractalShift;
    if(shift <= 0) return timeframeStr;
    
    // Find index of timeframeStr
    int baseIdx = -1;
    int arraySize = ArraySize(FRACTAL_TIMEFRAMES);
    for(int i = 0; i < arraySize; i++) {
        if(FRACTAL_TIMEFRAMES[i] == timeframeStr) {
            baseIdx = i;
            break;
        }
    }
    
    if(baseIdx == -1) return timeframeStr;
    
    // Apply shift and clamp to array bounds
    int targetIdx = MathMin(arraySize - 1, baseIdx + shift);
    return FRACTAL_TIMEFRAMES[targetIdx];
}

string GetFractalTimeframeForCurrent() {
    string baseTF = GetBaseFractalTimeframeForCurrent();
    return ApplyFractalShift(baseTF);
}

string GetStructureTimeframeForCurrent() {
    // OPTIMIZATION: Cache GetFractalTimeframeForCurrent() result before loop
    string currentFractalTF = GetFractalTimeframeForCurrent();
    int currentIndex = -1;
    int arraySize = ArraySize(FRACTAL_TIMEFRAMES);
    
    for(int i = 0; i < arraySize; i++) {
        if(FRACTAL_TIMEFRAMES[i] == currentFractalTF) {
            currentIndex = i;
            break;
        }
    }
    
    if(currentIndex != -1 && currentIndex + 2 < arraySize) {
        return FRACTAL_TIMEFRAMES[currentIndex + 2];
    }
    return "UNKNOWN";
}

string GetCorrespondingFractalTimeframe(const string standardTimeframe) {
    if(standardTimeframe=="D1") return "H17+M4";
    if(standardTimeframe=="W1") return "D11+H9+M4";
    if(standardTimeframe=="MN1") return "D45+H12+M16";
    return "";
}

double GetLowerTimeframeTH(const string currentTimeframe, int offset) {
    if(StringLen(currentTimeframe) == 0) {
        DEBUG_PRINT("GetLowerTimeframeTH - Error: Empty timeframe string");
        return EMPTY_VALUE;
    }
    if(offset < 0) {
        DEBUG_PRINTF("GetLowerTimeframeTH - Error: Invalid offset value: ", offset);
        return EMPTY_VALUE;
    }
    int arraySize = ArraySize(FRACTAL_TIMEFRAMES);
    int percentageArraySize = ArraySize(MODIFIED_FRACTAL_PERCENTAGES);
    if(arraySize <= 0 || percentageArraySize <= 0) {
        DEBUG_PRINTF2("GetLowerTimeframeTH - Error: Empty arrays - FRACTAL_TIMEFRAMES: ", IntegerToString(arraySize),
              ", MODIFIED_FRACTAL_PERCENTAGES: " + IntegerToString(percentageArraySize));
        return EMPTY_VALUE;
    }
    if(arraySize != percentageArraySize) {
        DEBUG_PRINTF2("GetLowerTimeframeTH - Error: Array size mismatch - FRACTAL_TIMEFRAMES: ", IntegerToString(arraySize),
              ", MODIFIED_FRACTAL_PERCENTAGES: " + IntegerToString(percentageArraySize));
        return EMPTY_VALUE;
    }
    // Debug: Print("GetLowerTimeframeTH - Looking for timeframe: ", currentTimeframe, " with offset: ", offset);
    int matchIndex = -1;
    for(int i=0; i<arraySize; i++) {
        if(FRACTAL_TIMEFRAMES[i] == currentTimeframe) {
            matchIndex = i;
            break;
        }
    }
    if(matchIndex == -1) {
        DEBUG_PRINTF("GetLowerTimeframeTH - Error: No matching timeframe found for: ", currentTimeframe);
        return EMPTY_VALUE;
    }
    int targetIndex = matchIndex - offset;
    if(targetIndex < 0 || targetIndex >= arraySize) {
        DEBUG_PRINTF3("GetLowerTimeframeTH - Error: Invalid target index. Index: ", IntegerToString(targetIndex),
              ", TF: " + currentTimeframe, ", Offset: " + IntegerToString(offset));
        return EMPTY_VALUE;
    }
    // P-TH-01: SCALED — this is Pattern/Trigger, the two rungs the user's
    // «روابطه به جایی» rule is about. `FractalPercentScaled` keeps them at
    // exactly half and a quarter of the Structure step whatever the knob says.
    double result = FractalPercentScaled(targetIndex);
    if(result <= 0.0) {
        DEBUG_PRINTF("GetLowerTimeframeTH - Warning: Zero or negative percentage at index ", targetIndex);
    }
    // Debug: Print("GetLowerTimeframeTH - Found at index ", matchIndex, " returning value: ", result);
    return result;
}

double GetPatternTH() {
    string currentTF = GetFractalTimeframeForCurrent();
    return GetLowerTimeframeTH(currentTF, 1);
}

double GetTriggerTH() {
    string currentTF = GetFractalTimeframeForCurrent();
    return GetLowerTimeframeTH(currentTF, 2);
}

// Get percentage for a specific timeframe (matching MotiveWave implementation)
// P-TH-01: SCALED — this is the canonical rung -> percentage resolver. The
// value it returns is what `CalculateTHPoints` turns into the drawn TH, so the
// knob reaches the chart through here and through THCalculations' own copy of
// the same lookup (which has a cache; a knob change invalidates it, see
// `PnlApplySet` case 3).
double GetTimeframePercentage(const string timeframe) {
    int arraySize = ArraySize(FRACTAL_TIMEFRAMES);
    for(int i = 0; i < arraySize; i++) {
        if(FRACTAL_TIMEFRAMES[i] == timeframe) {
            return FractalPercentScaled(i);
        }
    }
    // Default fallback
    return 1.0;
}

// Convert long timeframe name to short format
// e.g., "H1+M4" -> "H1.4", "D2+H20+M16" -> "D2.20.16"
string GetShortTimeframeName(const string longTimeframeName) {
    // Simple timeframes - return as is
    if (longTimeframeName == "M1" || longTimeframeName == "M4" || longTimeframeName == "M16") {
        return longTimeframeName;
    }
    
    // Composite timeframes - convert to short format
    if (longTimeframeName == "H1+M4") return "H1.4";
    if (longTimeframeName == "H4+M16") return "H4.16";
    if (longTimeframeName == "H17+M4") return "H17.4";
    if (longTimeframeName == "D2+H20+M16") return "D2.20.16";
    if (longTimeframeName == "D11+H9+M4") return "D11.9.4";
    if (longTimeframeName == "D45+H12+M16") return "D45.12.16";
    
    // No match found - return original
    return longTimeframeName;
}

// Get timeframe name for a structure level (L1-L5)
// L1 = current fractal TF, L2 = one higher, etc.
string GetTimeframeForStructureLevel(int level) {
    if(level < 1 || level > 5) return "";
    
    string currentTF = GetFractalTimeframeForCurrent();
    int arraySize = ArraySize(FRACTAL_TIMEFRAMES);
    
    // CRITICAL FIX: Validate array is not empty
    if(arraySize <= 0) return currentTF;
    
    // Find current TF index
    int currentIndex = -1;
    for(int i = 0; i < arraySize; i++) {
        if(FRACTAL_TIMEFRAMES[i] == currentTF) {
            currentIndex = i;
            break;
        }
    }
    
    if(currentIndex < 0) return currentTF;
    
    // L1 = current TF, L2 = current + 1, etc.
    int targetIndex = currentIndex + (level - 1);
    
    // CRITICAL FIX: Clamp to valid range [0, arraySize-1]
    if(targetIndex < 0) targetIndex = 0;
    if(targetIndex >= arraySize) targetIndex = arraySize - 1;
    
    return FRACTAL_TIMEFRAMES[targetIndex];
}

// Helper function to build overlap info string for a step
// Returns string like "L2" for highest level only (FIXED: No more overlaps)
// CRITICAL FIX: Now uses GetHighestStructureLevel for proper hierarchy
string GetOverlapLevelsInfo(int step, const int &intervals[]) {
    // SECURITY: Validate inputs
    if(step == 0) return "Mid"; // Midpoint
    
    int arraySize = ArraySize(intervals);
    if(arraySize != 5) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetOverlapLevelsInfo: Invalid intervals array size=", arraySize);
        #endif
        return "";
    }
    
    // Get highest structure level (1-5) or 0 if trigger
    int highestLevel = GetHighestStructureLevel(step, intervals);
    
    if(highestLevel == 0) {
        return ""; // Trigger level - no structure info
    }
    
    // Return only the highest level (e.g., "L2" not "L1+L2")
    return "L" + IntegerToString(highestLevel);
}

// Helper function to build timeframe info for overlapping levels
// CRITICAL FIX: Now returns only the highest level's timeframe
string GetOverlapTimeframesInfo(int step, const int &intervals[]) {
    // SECURITY: Validate inputs
    if(step == 0) return GetShortTimeframeName(GetFractalTimeframeForCurrent()); // Midpoint
    
    int arraySize = ArraySize(intervals);
    if(arraySize != 5) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  GetOverlapTimeframesInfo: Invalid intervals array size=", arraySize);
        #endif
        return "";
    }
    
    // Get highest structure level (1-5) or 0 if trigger
    int highestLevel = GetHighestStructureLevel(step, intervals);
    
    if(highestLevel == 0) {
        // Trigger level - return current timeframe
        return GetShortTimeframeName(GetFractalTimeframeForCurrent());
    }
    
    // Return timeframe for the highest level only
    string tf = GetShortTimeframeName(GetTimeframeForStructureLevel(highestLevel));
    return tf;
}

#endif // FRACTAL_TIMEFRAMES_MQH

