  //+------------------------------------------------------------------+
//|                                   DynamicTradingDayDetector.mqh |
//|                                                                  |
//|  Dynamic Trading Day Detection from actual market data          |
//|                                                                |
//+------------------------------------------------------------------+
#property copyright "Biotak"
#property strict

//+------------------------------------------------------------------+
//| Find current session start by detecting gaps in data             |
//+------------------------------------------------------------------+
datetime FindCurrentSessionStart(int timeframe = PERIOD_M1)
{
    datetime currentTime = TimeGMT();
    
    // Search backwards to find last gap (market close)
    int barsToCheck = 7 * 24 * 60; // 7 days of M1 bars
    int gapThresholdMinutes = 120; // 2 hours
    
    for(int i = 1; i < barsToCheck && i < iBars(Symbol(), timeframe); i++)
    {
        datetime currentBarTime = iTime(Symbol(), timeframe, i);
        datetime previousBarTime = iTime(Symbol(), timeframe, i - 1);
        
        // Check if we've gone too far back
        if(currentTime - currentBarTime > 7 * 24 * 60 * 60)
            break;
        
        // Calculate gap in minutes
        // i is older bar, i-1 is newer bar
        int gapMinutes = (int)((previousBarTime - currentBarTime) / 60);
        
        // If gap is larger than threshold, this is likely market close/open
        if(gapMinutes > gapThresholdMinutes)
        {
            #ifdef ENABLE_DEBUG_LOGS
            Print("[DynamicDetector] Found gap of ", gapMinutes, " minutes at ", 
                  TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES));
            #endif
            return currentBarTime;
        }
    }
    
    // No gap found, use 24-hour window
    datetime twentyFourHoursAgo = currentTime - (24 * 60 * 60);
    
    for(int i = iBars(Symbol(), timeframe) - 1; i >= 0; i--)
    {
        datetime barTime = iTime(Symbol(), timeframe, i);
        if(barTime >= twentyFourHoursAgo)
        {
            #ifdef ENABLE_DEBUG_LOGS
            Print("[DynamicDetector] Using 24-hour window start: ", 
                  TimeToString(barTime, TIME_DATE|TIME_MINUTES));
            #endif
            return barTime;
        }
    }
    
    // Fallback to default
    return GetStartOfTradingDay(Symbol(), currentTime);
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
