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
// P-TH-01 (2026-09-18) — THE TH PERCENTAGE KNOB.
//
// User: «این درصد محاسبات هم th هم بشه تنظیم کرد برای تحقیقات لازم دارمش الان
// 66 درصد قیمت جاری هستش فکر کنم یا نه یک نگاه بکن» — and then, fixing the
// shape: «مثلا 66 درصد هستم من ساشد 100 بزارم شاید 75 درصد بزارم» (one free
// percentage, live from the panel) with the limit «بقیه دست نمیخوره روابطه به
// جایی 66 دیگه چیزها میاد» (the rest must not be touched — the relationships
// hang off the 66).
//
// WHERE THE NUMBER COMES FROM, FOR THE RECORD. There is no single "TH
// percentage" in this program: `MODIFIED_FRACTAL_PERCENTAGES`
// (ConstantsAndEnums.mqh:230) is a nine-rung table and the rung a chart reads
// is chosen by its own TF (`GetBaseFractalTimeframeForCurrent` above) — on D1
// that rung is H17+M4 = 66.66%. `CalculateTHPoints` then does
// `(price * percentage) / 100.0`, so the TH really is ~66% of the price. The
// user's reading was right; what was missing was a way to move it.
//
// WHAT THE KNOB IS ALLOWED TO BE. It is read as "the percentage for THIS
// chart's own rung" and becomes ONE ratio, which EVERY rung is multiplied by.
// 66.66 -> 75 on D1 makes the ladder 2.34/4.69/9.38/18.75/37.5/75/150/300/600:
// every x2 relationship the ladder is built on survives, so Pattern (one rung
// DOWN) is still half the Structure step and Trigger (two rungs down) still a
// quarter — which is exactly the «روابطه به جایی» the user forbade breaking.
// Replacing ONE rung would have been a different, silently broken feature.
//
// WHAT IS DELIBERATELY *NOT* SCALED — this is the user's «بقیه دست نمیخوره»,
// spelled out so a later reader does not "fix" it:
//   * AdaptiveScaling.mqh:172 (JUMP_AGGRESSIVE) walks the RAW table to answer
//     "which rung of the professor's ladder reaches the ATR". That is a
//     MEASURING STICK, not the drawn ladder; moving it would silently re-pick
//     `g_fractalShift` (and with it the Structure TF and the whole zone
//     hierarchy) every time the research knob moved, which is precisely the
//     confound the user is trying to avoid.
//   * FrequencyOptimizer.mqh:574 scores a measured frequency against the
//     professor's reference percentages — same reasoning.
//   * TH3/TH3Math.mqh (TH3TOOL-OFF) keeps its own copy and is retired.
//
// ONE CONSEQUENCE THAT IS NOT A BUG, so nobody "fixes" it: `GetBaseTimeframeTH()`
// resolves through `CalculateTimeframeTH`, so the knob also scales the
// `theoreticalTH` that AdaptiveScaling.mqh:93 divides the ATR by — i.e. the
// displayed ATR/TH ratio (`g_atrScalingFactor`) moves with the knob. That is the
// TRUE ratio (the TH really did change). It does NOT move `g_fractalShift` on
// the DEFAULT path (ADAPTIVE_FRACTAL + JUMP_AGGRESSIVE): that shift comes from
// the raw-table walk above, which is deliberately unscaled. Only the
// non-default JUMP_CONSERVATIVE branch derives its shift from the ratio.
//
// 0 (the factory default) = OFF = 1.0 = the professor's table byte for byte.
// There is no drift at rest: the ratio is exactly 1.0 and `x * 1.0` is
// bit-identical to `x` for every finite x.
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
    if(g_thPercentOverride <= 0.0) return 1.0;
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

