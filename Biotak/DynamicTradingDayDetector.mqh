  //+------------------------------------------------------------------+
//|                                   DynamicTradingDayDetector.mqh |
//|                                                                  |
//|  Dynamic Trading Day Detection from actual market data          |
//|                                                                |
//+------------------------------------------------------------------+
#ifndef DYNAMIC_TRADING_DAY_DETECTOR_MQH
#define DYNAMIC_TRADING_DAY_DETECTOR_MQH
#property copyright "Biotak"
#property strict

//+------------------------------------------------------------------+
//| P-PERF-03: bulk bar-time fetch + overlap-safe chronology probe    |
//|                                                                  |
//| The old scan called iTime() TWICE per bar over up to 10,080 bars |
//| and, when no gap was found, walked the whole history again from  |
//| the oldest bar (~29k bars on XAUUSD M1) — 20,000-48,000 series   |
//| reads inside ONE OnCalculate, which is the 1.8-3.0 s "CRITICAL   |
//| CPU" freeze in the live log. One CopyTime() replaces the whole   |
//| walk; the array is then scanned in memory for free.               |
//+------------------------------------------------------------------+
bool DetectFetchBarTimes(const int timeframe, const int count, datetime &times[], int &got)
{
    got = 0;
    if(count <= 0) return false;
    if(ArrayResize(times, count) != count) return false;
    got = CopyTime(Symbol(), (ENUM_TIMEFRAMES)timeframe, 0, count, times);
    if(got <= 0) return false;
    // MT4 may hand the array back either way round; normalise to OLDEST FIRST
    // so the callers below never depend on terminal array convention.
    if(got > 1 && times[0] > times[got - 1])
    {
        datetime tmp;
        for(int a = 0, b = got - 1; a < b; a++, b--)
        {
            tmp = times[a]; times[a] = times[b]; times[b] = tmp;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Server -> GMT, local to this module.                             |
//| Declared here because ConvertServerToGMT() lives in              |
//| BasePriceManager.mqh, which is included AFTER this file.         |
//+------------------------------------------------------------------+
datetime DtddServerToGMT(const datetime serverTime)
{
    int offsetSeconds = (int)(TimeCurrent() - TimeGMT());
    MqlDateTime dt;
    TimeToStruct(serverTime - offsetSeconds, dt);
    dt.sec = 0;
    return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Find current session start by detecting gaps in data             |
//|                                                                  |
//| P-PERF-03: ONE bulk CopyTime + in-memory scan (was 2x iTime per  |
//| bar), and the result is memoised per (symbol, timeframe, day) so |
//| repeated calls in the same session are free.                     |
//|                                                                  |
//| P-PERF-11c: THE FRAME MUST BE CONSISTENT. Bar times from         |
//| iTime()/CopyTime() live in the SERVER frame; TimeGMT() does not. |
//| The version above compared the two directly ("first bar at/after  |
//| now-24h", with now taken from TimeGMT()), so every cutoff was     |
//| shifted by the whole server<->GMT offset and the session start   |
//| found was a SERVER instant handed back as if it were GMT - which |
//| the caller then converted a second time. The file on disk shows  |
//| the result: block labels running hours past the current GMT       |
//| block (22:xx / 23:xx blocks written at 17:xx GMT), which is also |
//| what made the retired ">=22:00 means legacy" guess fire on every  |
//| init. Scan in the server frame; hand back GMT.                   |
//+------------------------------------------------------------------+
datetime FindCurrentSessionStart(int timeframe = PERIOD_M1)
{
    datetime gmtNow    = TimeGMT();
    datetime serverNow = TimeCurrent();   // the frame bar times actually use

    // PERF: the answer only changes when the trading day changes. Cache it.
    static string   s_cachedSym = "";
    static int      s_cachedTf = -1;
    static datetime s_cachedDay = 0;
    static datetime s_cachedStart = 0;
    datetime today = (datetime)((long)gmtNow - ((long)gmtNow % 86400));
    string sym = Symbol();
    if(s_cachedDay == today && s_cachedTf == timeframe && s_cachedSym == sym && s_cachedStart > 0)
        return s_cachedStart;

    // Search backwards to find last gap (market close)
    int gapThresholdMinutes = 120; // 2 hours
    int haveBars = iBars(Symbol(), timeframe);
    if(haveBars < 2)
        return GetStartOfTradingDay(Symbol(), gmtNow);

    // 7 days of M1 bars is the most the gap search ever looked at; never ask
    // for more than the terminal actually holds.
    int want = MathMin(7 * 24 * 60, haveBars);
    datetime times[];
    int got = 0;
    datetime resultServer = 0;

    if(DetectFetchBarTimes(timeframe, want, times, got))
    {
        datetime oldestAllowed = serverNow - (datetime)(7 * 24 * 60 * 60);
        // OLDEST FIRST: walk backwards from the newest bar to the past.
        for(int i = got - 1; i >= 1; i--)
        {
            datetime newerBar = times[i];
            datetime olderBar = times[i - 1];
            if(newerBar < oldestAllowed) break;

            int gapMinutes = (int)((newerBar - olderBar) / 60);
            if(gapMinutes > gapThresholdMinutes)
            {
                resultServer = olderBar;
                #ifdef ENABLE_DEBUG_LOGS
                Print("[DynamicDetector] Found gap of ", gapMinutes, " minutes at ",
                      TimeToString(olderBar, TIME_DATE|TIME_MINUTES));
                #endif
                break;
            }
        }

        // No gap found: use the 24-hour window (first bar at/after the cutoff,
        // both sides of the comparison in the server frame).
        if(resultServer == 0)
        {
            datetime twentyFourHoursAgo = serverNow - (datetime)(24 * 60 * 60);
            for(int i = 0; i < got; i++)
            {
                if(times[i] >= twentyFourHoursAgo) { resultServer = times[i]; break; }
            }
            #ifdef ENABLE_DEBUG_LOGS
            if(resultServer > 0)
                Print("[DynamicDetector] Using 24-hour window start: ",
                      TimeToString(resultServer, TIME_DATE|TIME_MINUTES));
            #endif
        }
        ArrayFree(times);
    }

    // Convert to GMT for the caller, or fall back to the market-type default
    // (computed directly in GMT, so no conversion is involved).
    datetime result = 0;
    if(resultServer > 0) result = DtddServerToGMT(resultServer);
    else                 result = GetStartOfTradingDay(Symbol(), gmtNow);

    s_cachedSym   = sym;
    s_cachedTf    = timeframe;
    s_cachedDay   = today;
    s_cachedStart = result;
    return result;
}

//+------------------------------------------------------------------+
//| Check if market is currently open                                |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
    datetime currentTime = TimeGMT();
    datetime lastBarTime = iTime(Symbol(), PERIOD_M1, 0);
    
    // Check if we have recent data (within last 5 minutes)
    int timeSinceLastBar = (int)(currentTime - lastBarTime);
    
    return (timeSinceLastBar < 5 * 60);
}

//+------------------------------------------------------------------+
//| Get session statistics for debugging                             |
//+------------------------------------------------------------------+
string GetSessionStatistics()
{
    datetime currentTime = TimeGMT();
    datetime sessionStart = FindCurrentSessionStart();
    bool marketOpen = IsMarketOpen();
    
    int totalBars = iBars(Symbol(), PERIOD_M1);
    
    // CRITICAL FIX: Validate totalBars before using as array index
    if(totalBars <= 0) {
        return "No M1 bar data available";
    }
    
    datetime firstBarTime = iTime(Symbol(), PERIOD_M1, totalBars - 1);
    datetime lastBarTime = iTime(Symbol(), PERIOD_M1, 0);
    
    // Calculate 30-min blocks
    int totalMinutes = (int)((currentTime - sessionStart) / 60);
    int totalBlocks = totalMinutes / 30;
    
    string stats = "\n";
    stats += "====================\n";
    stats += "   TRADING SESSION STATISTICS                                   \n";
    stats += "====================\n";
    stats += "   Current Time:        " + TimeToString(currentTime, TIME_DATE|TIME_SECONDS) + "                     \n";
    stats += "   Session Start:       " + TimeToString(sessionStart, TIME_DATE|TIME_SECONDS) + "                     \n";
    stats += "   First Bar:           " + TimeToString(firstBarTime, TIME_DATE|TIME_SECONDS) + "                     \n";
    stats += "   Last Bar:            " + TimeToString(lastBarTime, TIME_DATE|TIME_SECONDS) + "                     \n";
    stats += "   Total M1 Bars:       " + IntegerToString(totalBars) + "                                    \n";
    stats += "   30-Min Blocks:       " + IntegerToString(totalBlocks) + "                                    \n";
    stats += "   Market Status:       " + (marketOpen ? "OPEN" : "CLOSED") + "                                    \n";
    stats += "====================\n";
    
    return stats;
}

//+------------------------------------------------------------------+
//| Get all 30-minute blocks for current session                     |
//+------------------------------------------------------------------+
void GetAllBlocksForCurrentSession(datetime &blocks[], datetime currentTime)
{
    datetime sessionStart = FindCurrentSessionStart();
    
    // Round down to nearest 30-minute boundary
    MqlDateTime dt;
    TimeToStruct(sessionStart, dt);
    int minute = dt.min;
    int roundedMinute = (minute / 30) * 30;
    dt.min = roundedMinute;
    dt.sec = 0;
    datetime blockTime = StructToTime(dt);
    
    // Generate blocks up to current time
    ArrayResize(blocks, 0);
    while(blockTime <= currentTime)
    {
        int size = ArraySize(blocks);
        ArrayResize(blocks, size + 1);
        blocks[size] = blockTime;
        blockTime += 30 * 60;
    }
}

#endif // DYNAMIC_TRADING_DAY_DETECTOR_MQH
