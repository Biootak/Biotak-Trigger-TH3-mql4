  #ifndef HISTORICAL_DATA_FUNCTIONS_MQH
#define HISTORICAL_DATA_FUNCTIONS_MQH

#property strict

bool UpdateHistoricalValues() {
    // We fetch the full historical data ONLY ONCE during initialization
    if (g_initialized) return true;

    // OPTIMIZATION: Use dynamic arrays and ensure cleanup
    double highArray[], lowArray[];
    
    // To ensure Historical High/Low remains consistent across different timeframes,
    // we use PERIOD_MN1 when PERIOD_CURRENT is selected, because PERIOD_CURRENT
    // yields different history lengths for different timeframes (e.g. M1 vs D1).
    ENUM_TIMEFRAMES effectiveTimeframe = inpHistoricalTimeframe;
    if (effectiveTimeframe == PERIOD_CURRENT && inpHistoricalPeriods == 0) {
        effectiveTimeframe = PERIOD_MN1;
    }
    
    // MT4 approach: User has full control via input parameters
    // inpHistoricalPeriods = 0 means use all available bars
    // Otherwise use the specified number of periods
    int totalBars = inpHistoricalPeriods == 0 ? 
                   iBars(Symbol(), effectiveTimeframe) : 
                   inpHistoricalPeriods;
    
    // P-MT5-01b (2026-09-16): ASK FOR THE SERIES BEFORE CONCLUDING IT IS EMPTY.
    //
    // `iBars()` READS a series; it does not BUILD one. MT4 keeps every timeframe
    // resident, so the read above always answers and this file never has to
    // think about it. MT5 synthesises a higher timeframe on demand, so the first
    // read answers 0 - and because the guard below then returns false, this
    // function never issued the request that would have made the series exist.
    // The terminal-side proof is in the live log: "[E][GEN] OnInit:
    // UpdateHistoricalValues failed. Error: 4401" (ERR_HISTORY_NOT_FOUND)
    // 17 times in one day, on exactly the symbols whose top timeframe the
    // terminal had not built (SPXUSD-ECN H1 among them).
    //
    // A Copy* call is the documented way to REQUEST history from the server, so
    // issue a real one and re-ask. MT4's meaning is preserved exactly: it
    // already holds the data, so the second read simply repeats the first and
    // the code path costs one integer compare.
    if(totalBars <= 0 && inpHistoricalPeriods == 0) {
        double kickHigh[], kickLow[];
        ArraySetAsSeries(kickHigh, true);
        ArraySetAsSeries(kickLow, true);
        if(CopyHigh(Symbol(), effectiveTimeframe, 0, 1, kickHigh) > 0)
            CopyLow(Symbol(), effectiveTimeframe, 0, 1, kickLow);
        totalBars = iBars(Symbol(), effectiveTimeframe);
    }

    if(totalBars <= 0) {
        // FIX: Don't just fail, log that we're waiting for data
        static uint s_lastBarsWarningMs = 0;
        uint _nowMs = GetTickCount();
        if(_nowMs - s_lastBarsWarningMs > 30000) {
            Print("UpdateHistoricalValues: Waiting for historical data (", EnumToString(effectiveTimeframe), ")...");
            s_lastBarsWarningMs = _nowMs;
        }
        return false;
    }

    // Resize arrays
    if(ArrayResize(highArray, totalBars) != totalBars || ArrayResize(lowArray, totalBars) != totalBars) {
        Print("UpdateHistoricalValues: Failed to resize arrays. Error: ", GetLastError());
        ArrayFree(highArray);
        ArrayFree(lowArray);
        return false;
    }

    // Use single error check for data copying
    int copiedHigh = CopyHigh(Symbol(), effectiveTimeframe, 0, totalBars, highArray);
    int copiedLow = CopyLow(Symbol(), effectiveTimeframe, 0, totalBars, lowArray);
    
    if(copiedHigh <= 0 || copiedLow <= 0) {
        Print("UpdateHistoricalValues: Failed to copy data. High=", copiedHigh, ", Low=", copiedLow);
        ArrayFree(highArray);
        ArrayFree(lowArray);
        return false;
    }

    // P-UI-57e: TRIM TO WHAT WAS ACTUALLY COPIED BEFORE MEASURING.
    //
    // ArrayResize zero-fills, so when the terminal holds fewer bars than
    // `inpHistoricalPeriods` asked for, the tail of these two arrays is a run of
    // zeros. ArrayMinimum then returned that padding, `g_lowestLow` came back as 0,
    // and the `<= 0` test below failed - permanently, because CopyHigh can never
    // return more bars than the terminal actually has. The Historical High/Low
    // lines therefore never appeared for any inpHistoricalPeriods larger than the
    // available history, and not at all in the first frames after attach.
    // Measure the copied prefix, never the padding.
    int usable = MathMin(copiedHigh, copiedLow);
    if(ArrayResize(highArray, usable) != usable || ArrayResize(lowArray, usable) != usable) {
        Print("UpdateHistoricalValues: Failed to trim arrays. Error: ", GetLastError());
        ArrayFree(highArray);
        ArrayFree(lowArray);
        return false;
    }

    // Optimize max/min calculation
    g_highestHigh = highArray[ArrayMaximum(highArray)];
    g_lowestLow = lowArray[ArrayMinimum(lowArray)];
    
    // MEMORY CLEANUP: Free temporary arrays immediately after use
    ArrayFree(highArray);
    ArrayFree(lowArray);
    
    if(g_highestHigh <= 0 || g_lowestLow <= 0) {
        Print("UpdateHistoricalValues: Invalid high/low values");
        return false;
    }
    
    g_lastHistoricalUpdate = CacheGetFrameTime();
    // g_thCache removed - matching MT5
    
    return true;
}

// Cache previous day prices
double GetPriceForPreviousDay(ENUM_APPLIED_PRICE priceType) {
    static datetime lastUpdate = 0;
    static double cachedPrices[6] = {0};
    static bool   s_haveValidDay = false;
    
    datetime currentTime = TimeCurrent();
    if(currentTime-lastUpdate >= 86400 || lastUpdate==0) { // Update cache daily
        // P-MT5-01b (2026-09-16): NEVER PUBLISH, AND NEVER DATE-STAMP, A DAY
        // THAT DID NOT LOAD.
        //
        // In the old shape the four iClose/iOpen/iHigh/iLow reads wrote straight
        // into cachedPrices[] and `lastUpdate = currentTime` was stamped
        // unconditionally. On MT5 a higher timeframe is synthesised on demand, so
        // on a cold attach or right after a timeframe switch iClose(D1,1) can
        // legitimately answer 0 - and that 0 was then PUBLISHED and STAMPED, so
        // every call for the next 24 hours returned 0 regardless of what the
        // terminal later loaded. MT4 cannot do this: its D1 series is resident.
        //
        // The consequence is not cosmetic. g_dailyClosePriceForTH IS the TH base
        // price (`GetBasePriceForTH` falls back to it), so a 0 here becomes a 0
        // step, and BuildLevels rejects a non-positive centre - i.e. the level
        // family draws NOTHING. That is the "levels are broken" symptom, with a
        // 24-hour lifetime.
        //
        // So: read into locals, publish only a complete day, and return
        // EMPTY_VALUE while none has ever been published - WITHOUT touching
        // lastUpdate, so the very next call retries instead of serving stale
        // zeros. A later failed read keeps the previous good day (one day old for
        // at most a tick) rather than reverting to 0.
        double d1Close = iClose(Symbol(), PERIOD_D1, 1);
        double d1Open  = iOpen (Symbol(), PERIOD_D1, 1);
        double d1High  = iHigh (Symbol(), PERIOD_D1, 1);
        double d1Low   = iLow  (Symbol(), PERIOD_D1, 1);
        // Bar 1 must be a real bar: every field finite and strictly positive.
        // (A mid-build series answers 0 for all four, which is the case above.)
        if(d1Close > 0 && d1Open > 0 && d1High > 0 && d1Low > 0 &&
           MathIsValidNumber(d1Close) && MathIsValidNumber(d1Open) &&
           MathIsValidNumber(d1High) && MathIsValidNumber(d1Low) &&
           d1High >= d1Low)
        {
            cachedPrices[0]=d1Close;
            cachedPrices[1]=d1Open;
            cachedPrices[2]=d1High;
            cachedPrices[3]=d1Low;
            cachedPrices[4]=(d1High+d1Low)/2.0;
            cachedPrices[5]=(d1High+d1Low+d1Close)/3.0;
            s_haveValidDay = true;
            lastUpdate = currentTime;
        }
        else if(!s_haveValidDay)
        {
            return EMPTY_VALUE;   // never had a good day: say so, and retry next call
        }
    }
    
    switch((int)priceType) {
        case 1: return cachedPrices[1]; // Open
        case 2: return cachedPrices[2]; // High
        case 3: return cachedPrices[3]; // Low
        case 4: return cachedPrices[4]; // Median
        case 5: return cachedPrices[5]; // Typical
        case 0: default: return cachedPrices[0]; // Close
    }
    return EMPTY_VALUE;
}
#endif // HISTORICAL_DATA_FUNCTIONS_MQH
