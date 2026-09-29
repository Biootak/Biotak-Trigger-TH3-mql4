// BasePrice_B.mqh - BasePriceManager.mqh split 2026-09-29: exact lines 1228-2113, byte-identical, zero renames.
#ifndef BASE_PRICE_B_MQH
#define BASE_PRICE_B_MQH

//+------------------------------------------------------------------+
//| Update base price every 30 minutes                               |
//| Returns true if base price was updated, false otherwise          |
//+------------------------------------------------------------------+
bool UpdateBasePrice()
{
    // CRITICAL: Use Server Time to match M30 bars
    // M30 bars in MT4 use server time, not GMT
    datetime currentTime = TimeCurrent();
    
    // CRITICAL FIX: Only update at the START of each 30-minute block
    // Check if current minute is 00 or 30 (start of block)
    int currentMinute = TimeMinute(currentTime);
    if(currentMinute != 0 && currentMinute != 30)
    {
        // Not at block boundary - skip update
        return false;
    }
    
    // Calculate current 30-minute block start time
    int totalMinutes = TimeMinute(currentTime) + TimeHour(currentTime) * 60;
    int blockNumber = totalMinutes / BLOCK_MINUTES;
    int blockStartMinutes = blockNumber * BLOCK_MINUTES;
    int blockStartHour = blockStartMinutes / 60;
    int blockStartMinute = blockStartMinutes % 60;
    
    // Create datetime for current block start
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    dt.hour = blockStartHour;
    dt.min = blockStartMinute;
    dt.sec = 0;
    datetime currentBlockStart = StructToTime(dt);
    
    // Calculate previous block start (30 minutes before)
    datetime previousBlockStart = currentBlockStart - BLOCK_MINUTES * 60;
    
    // FIXED: Use centralized conversion to GMT
    datetime previousBlockStartGMT = ConvertServerToGMT(previousBlockStart);
    
    // DUPLICATE FIX: Check if entry already exists for this block (use GMT time)
    string blockTimeStr = TimeToString(previousBlockStartGMT, TIME_MINUTES);
    if(HistoryEntryExists(blockTimeStr))
    {
        // Only log once per block to avoid spam
        if(g_lastProcessedBlockTimestamp != previousBlockStart)
        {
#ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager] UpdateBasePrice() - Entry already exists for block ", blockTimeStr, " (GMT), skipping");
#endif
            g_lastProcessedBlockTimestamp = previousBlockStart;
        }
        return false;
    }
    
    // Check if we need to reset history for a new day
    TimeToStruct(currentTime, dt);
    int currentDayOfYear = dt.day_of_year + 1;  // Convert from 0-based to 1-based
    if(currentDayOfYear != g_lastHistoryDay || dt.year != g_lastHistoryYear)
    {
        // New day - reset history
#ifdef ENABLE_DEBUG_LOGS
        Print("====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
        Print("      NEW DAY DETECTED - RESETTING BASE PRICE HISTORY            ");
#endif
#ifdef ENABLE_DEBUG_LOGS
        Print("====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
        Print("   Old Date: ", g_lastHistoryYear, "/", g_lastHistoryDay);
#endif
#ifdef ENABLE_DEBUG_LOGS
        Print("   New Date: ", dt.year, "/", currentDayOfYear);
#endif
#ifdef ENABLE_DEBUG_LOGS
        Print("   Action: Clearing all history and resetting base price");
#endif
#ifdef ENABLE_DEBUG_LOGS
        Print("====================");
#endif
        
        ResizeHistory(0);
        g_historyCount = 0;
        g_lastHistoryDay = currentDayOfYear;
        g_lastHistoryYear = dt.year;
        g_basePriceCached = EMPTY_VALUE;
        g_referenceM1Power = 0.0;
    }
    
    // CRITICAL: Use M30 timeframe to get the exact 30-minute close price
    // Strategy: Use the most recent COMPLETED M30 bar
    // Bar 0 is current (incomplete), Bar 1 is last completed
    
    int m30BarIdx = 1;  // Last completed M30 bar
    datetime m30BarTime = iTime(Symbol(), PERIOD_M30, m30BarIdx);
    double newBasePrice = iClose(Symbol(), PERIOD_M30, m30BarIdx);
    
    // Validate bar exists
    if(m30BarTime == 0)
    {
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] UpdateBasePrice() - ERROR: No M30 bar available");
#endif
        return false;
    }
    
    // Validate price
    if(newBasePrice <= 0.0)
    {
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] UpdateBasePrice() - ERROR: Invalid M30 close price: ", newBasePrice);
#endif
        return false;
    }
    
    // FIXED: Convert M30 bar time to GMT for comparison using centralized function
    datetime m30BarTimeGMT = ConvertServerToGMT(m30BarTime);
    
    // Calculate timezone offset for display purposes
    datetime gmtNow = TimeGMT();
    datetime serverNow = TimeCurrent();
    int timezoneOffsetHours = (int)((serverNow - gmtNow) / 3600);
    
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] ====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager]    M30 BAR DETAILS                                               ");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] ====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager]    Bar Index:        ", m30BarIdx);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager]    Server Time:      ", TimeToString(m30BarTime, TIME_DATE|TIME_MINUTES));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager]    GMT Time:         ", TimeToString(m30BarTimeGMT, TIME_DATE|TIME_MINUTES));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager]    Expected Block:   ", TimeToString(previousBlockStartGMT, TIME_DATE|TIME_MINUTES), " (GMT)");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager]    Close Price:      ", DoubleToString(newBasePrice, Digits));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager]    Timezone Offset:  GMT", (timezoneOffsetHours >= 0 ? "+" : ""), timezoneOffsetHours, " hours");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] ====================");
#endif
    
    // Check if this is first update of the day
    if(g_basePriceCached == EMPTY_VALUE || g_basePriceCached == 0.0)
    {
        // INITIAL assignment
        g_basePriceCached = newBasePrice;
        g_referenceM1Power = CalculateM1PowerForBasePrice(newBasePrice);
        
        // For INIT: status is "-", refM1=0 (shown as "-"), M1Old=value, M1New=0 (shown as "-")
        AddBasePriceHistoryEntry(m30BarTime, newBasePrice, newBasePrice, 
                                 "-", 0.0, 0.0, g_referenceM1Power);
        
#ifdef ENABLE_DEBUG_LOGS
        Print("INIT: Base price ", DoubleToString(newBasePrice, Digits), " | M1: ", DoubleToString(g_referenceM1Power, 5));
#endif
        return true;
    }
    
    // Calculate M1 power delta for gating
    double oldPowerM1 = g_referenceM1Power;
    double newPowerM1 = CalculateM1PowerForBasePrice(newBasePrice);
    
    double deltaAbsPct = 0.0;
    if(oldPowerM1 != 0.0 && MathAbs(oldPowerM1) > 0.0000001)
    {
        deltaAbsPct = MathAbs(newPowerM1 - oldPowerM1) / MathAbs(oldPowerM1) * 100.0;
    }
    else
    {
        deltaAbsPct = 999.99;
    }
    
    // Apply M1 power gating logic
    // Use configurable threshold (default: 0.066% to match Java)
    double thresholdPercent = inpBasePriceThresholdEnabled ? inpBasePriceThresholdPercent : 0.0;
    if(deltaAbsPct >= thresholdPercent)
    {
        // ACCEPT: Update base price
        double oldBasePrice = g_basePriceCached;
        g_basePriceCached = newBasePrice;
        g_referenceM1Power = newPowerM1;
        
        string okStatus = StringFormat("OK D=%.3f%%", deltaAbsPct);
        // Pass server time - AddBasePriceHistoryEntry will convert to GMT
        AddBasePriceHistoryEntry(m30BarTime, newBasePrice, newBasePrice, 
                                 okStatus, deltaAbsPct, oldPowerM1, newPowerM1);
        
#ifdef ENABLE_DEBUG_LOGS
        Print("OK: Base price updated to ", DoubleToString(newBasePrice, Digits), 
              " (D=", DoubleToString(deltaAbsPct, 3), "%)");
#endif
        
        // Save history table to file after update
        SaveBasePriceHistoryToFile();
        
        return true;
    }
    else
    {
        // REJECT: Keep old base price
        
        string skipStatus = StringFormat("SKIP D=%.3f%%", deltaAbsPct);
        // Pass server time - AddBasePriceHistoryEntry will convert to GMT
        AddBasePriceHistoryEntry(m30BarTime, newBasePrice, g_basePriceCached, 
                                 skipStatus, deltaAbsPct, oldPowerM1, newPowerM1);
        
#ifdef ENABLE_DEBUG_LOGS
        Print("SKIP: Base price unchanged at ", DoubleToString(g_basePriceCached, Digits),
              " (D=", DoubleToString(deltaAbsPct, 3), "%)");
#endif
        
        // Save history table to file after skip
        SaveBasePriceHistoryToFile();
        
        return false;
    }
}

//+------------------------------------------------------------------+
//| Rebuild history from start of day using M1 candles               |
//| Uses FindLastM1CandleInBlock() and MergeHistoryLists()           |
//| Implements design from mt4-base-price-history-rebuild spec       |
//+------------------------------------------------------------------+
void RebuildHistoryFromStartOfDay()
{
#ifdef ENABLE_DEBUG_LOGS
    Print("====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   REBUILD HISTORY FROM START OF DAY                            ");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("====================");
#endif
    
    // CRITICAL: Find start of trading day
    // Strategy: Dynamic Detection   Market Type Default
    datetime gmtTime = TimeGMT();
    datetime serverTime = TimeCurrent();
    datetime startOfDayGMT;
    
    // Try dynamic detection first (recommended)
    bool useDynamic = inpUseDynamicTradingDay;
    
    if(useDynamic)
    {
        // Use dynamic detection from data gaps
        startOfDayGMT = FindCurrentSessionStart(PERIOD_M1);
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] Using DYNAMIC detection: Trading day starts at ", 
              TimeToString(startOfDayGMT, TIME_DATE|TIME_MINUTES));
#endif
    }
    else
    {
        // Use market type default (Forex/Metals: 22:00, Others: 00:00)
        int startHour = GetTradingDayStartHour(Symbol());
        ENUM_MARKET_TYPE marketType = DetectMarketType(Symbol());
        
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] Symbol: ", Symbol(), " | Market Type: ", GetMarketTypeName(marketType), 
              " | Trading day starts at: ", startHour, ":00 GMT");
#endif
        
        MqlDateTime dtGMT;
        TimeToStruct(gmtTime, dtGMT);
        
        // Calculate start of trading day
        dtGMT.hour = startHour;
        dtGMT.min = 0;
        dtGMT.sec = 0;
        startOfDayGMT = StructToTime(dtGMT);
        
        // If start hour is 22:00 and current time is before 22:00,
        // we need to go back to previous day's 22:00
        if(startHour == 22 && gmtTime < startOfDayGMT)
        {
            startOfDayGMT -= 24 * 60 * 60; // Go back one day
#ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager] Adjusted start time to previous day (before 22:00)");
#endif
        }
        
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] Using MARKET TYPE default: Trading day starts at ", 
              TimeToString(startOfDayGMT, TIME_DATE|TIME_MINUTES));
#endif
    }
    
    // Convert to Server Time for M30 bar access
    datetime startOfDayServer = ConvertGMTToServer(startOfDayGMT);
    
    // Calculate current 30-min block start (GMT)
    MqlDateTime dtGMT;
    TimeToStruct(gmtTime, dtGMT);
    int blockMinute = (dtGMT.min / 30) * 30;
    dtGMT.min = blockMinute;
    dtGMT.sec = 0;
    datetime currentBlockStartGMT = StructToTime(dtGMT);
    
    // Convert to Server Time for M30 bar access
    datetime currentBlockStartServer = ConvertGMTToServer(currentBlockStartGMT);
    
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] Start of day (Server): ", TimeToString(startOfDayServer, TIME_DATE|TIME_MINUTES));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] Start of day (GMT): ", TimeToString(startOfDayGMT, TIME_DATE|TIME_MINUTES));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] Current block (Server): ", TimeToString(currentBlockStartServer, TIME_DATE|TIME_MINUTES));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] Current block (GMT): ", TimeToString(currentBlockStartGMT, TIME_DATE|TIME_MINUTES));
#endif
    
    // Calculate number of completed 30-minute blocks (in Server Time)
    int totalMinutes = (int)((currentBlockStartServer - startOfDayServer) / 60);
    int totalBlocks = totalMinutes / 30;
    
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] Total completed blocks to rebuild: ", totalBlocks);
#endif
    
    // Store existing history for merge
    string existingHistory[];
    int existingCount = g_historyCount;
    GetHistoryArray(existingHistory);
    
    // Build rebuilt history
    string rebuiltHistory[];
    int rebuiltCount = 0;
    ArrayResize(rebuiltHistory, totalBlocks);
    
    // Track rebuild statistics
    int successCount = 0;
    int skipCount = 0;
    int missingDataCount = 0;
    
    // Track M1 power reference for validation
    double rebuildReferencePrice = 0.0;
    double rebuildReferenceM1 = 0.0;
    bool isFirstEntry = true;
    
    // Loop through all 30-minute blocks from day start to current (Server Time)
    for(int blockNum = 0; blockNum < totalBlocks; blockNum++)
    {
        // Calculate block start and end times (Server Time)
        datetime blockStartServer = startOfDayServer + (blockNum * 30 * 60);
        datetime blockEndServer = blockStartServer + (30 * 60);
        
        // Convert to GMT for storage
        datetime blockStartGMT = ConvertServerToGMT(blockStartServer);
        
        string blockTimeStr = TimeToString(blockStartGMT, TIME_MINUTES);
        
        // Check if entry already exists in existing history (skip if exists)
        if(HistoryEntryExists(blockTimeStr))
        {
#ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager] Block ", blockTimeStr, " already exists, skipping");
#endif
            continue;
        }
        
        // Use M30 timeframe to get exact 30-minute close price
        // blockStartServer is in server time, perfect for iBarShift
        int m30BarIdx = iBarShift(Symbol(), PERIOD_M30, blockStartServer, false);
        
        if(m30BarIdx == -1)
        {
            // No M30 data available for this block
#ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager]    No M30 data for block ", blockTimeStr, 
                  " (GMT), Server: ", TimeToString(blockStartServer, TIME_MINUTES));
#endif
            missingDataCount++;
            continue;
        }
        
        // Get M30 candle close price
        double closePrice = iClose(Symbol(), PERIOD_M30, m30BarIdx);
        
        // Validate M30 candle price
        if(closePrice <= 0.0)
        {
#ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager]    Invalid M30 candle price for block ", blockTimeStr, ": ", closePrice);
#endif
            missingDataCount++;
            continue;
        }
        
        // Verify the M30 bar (for debugging)
        datetime m30BarTime = iTime(Symbol(), PERIOD_M30, m30BarIdx);
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] Block ", blockTimeStr, 
              " | M30 Bar: ", TimeToString(m30BarTime, TIME_MINUTES),
              " | Close: ", DoubleToString(closePrice, Digits));
#endif
        
        // Calculate M1 power for this candle
        double newM1Power = CalculateM1PowerForBasePrice(closePrice);
        
        // Handle first entry
        if(isFirstEntry)
        {
            rebuildReferencePrice = closePrice;
            rebuildReferenceM1 = newM1Power;
            
            // Format: time|30minPrice|refPrice (INITIAL)|status|refM1|M1Old|M1New
            // For INIT: refM1=-, M1Old=value, M1New=-
            string entry = StringFormat("%s|%.5f|%.5f (INITIAL)|-|-|%.5f|-",
                                       blockTimeStr, closePrice, closePrice, newM1Power);
            
            rebuiltHistory[rebuiltCount] = entry;
            rebuiltCount++;
            successCount++;
            isFirstEntry = false;
            
#ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager] INIT: ", blockTimeStr, " | Price: ", DoubleToString(closePrice, Digits));
#endif
            continue;
        }
        
        // Calculate M1 power delta
        double deltaAbsPct = 0.0;
        if(rebuildReferenceM1 != 0.0 && MathAbs(rebuildReferenceM1) > 0.0000001)
        {
            deltaAbsPct = MathAbs(newM1Power - rebuildReferenceM1) / MathAbs(rebuildReferenceM1) * 100.0;
        }
        else
        {
            deltaAbsPct = 999.99;
        }
        
        // Apply sanity check validation (10% threshold)
        double validatedPrice = 0.0;
        bool isValid = ValidateRestoredBasePrice(closePrice, rebuildReferencePrice, validatedPrice);
        
        string status;
        double refPrice;
        double oldM1 = rebuildReferenceM1;
        
        // Use configurable threshold (default: 0.066% to match Java)
        double thresholdPercent = inpBasePriceThresholdEnabled ? inpBasePriceThresholdPercent : 0.0;
        if(isValid && deltaAbsPct >= thresholdPercent)
        {
            // ACCEPT: Update base price
            status = StringFormat("OK D=%.3f%%", deltaAbsPct);
            refPrice = closePrice;
            rebuildReferencePrice = closePrice;
            rebuildReferenceM1 = newM1Power;
            successCount++;
        }
        else
        {
            // SKIP: Keep old base price
            if(!isValid)
            {
                status = StringFormat("SKIP ?=%.3f%%", deltaAbsPct);
            }
            else
            {
                status = StringFormat("SKIP D=%.3f%%", deltaAbsPct);
            }
            refPrice = rebuildReferencePrice;
            skipCount++;
        }
        
        double priceChange = refPrice - rebuildReferencePrice;
        // Use 5 decimal places for prices to match Java precision
        string entry = StringFormat("%s|%.5f|%.5f (%+.5f)|%s|%.5f|%.5f|%.5f",
                                   blockTimeStr, closePrice, refPrice, priceChange,
                                   status, rebuildReferenceM1, oldM1, newM1Power);
        
        rebuiltHistory[rebuiltCount] = entry;
        rebuiltCount++;
        
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] ", status, ": ", blockTimeStr, " | Price: ", DoubleToString(closePrice, Digits));
#endif
    }
    
#ifdef ENABLE_DEBUG_LOGS
    Print("====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   REBUILD STATISTICS                                            ");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Total Blocks: ", totalBlocks);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Success: ", successCount);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Skipped: ", skipCount);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Missing Data: ", missingDataCount);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Rebuilt Entries: ", rebuiltCount);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Existing Entries: ", existingCount);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("====================");
#endif
    
    // Merge existing and rebuilt history
    string mergedHistory[];
    int mergedCount = 0;
    MergeHistoryLists(existingHistory, existingCount, rebuiltHistory, rebuiltCount, mergedHistory, mergedCount);
    
    // Update global history
    SetHistoryArray(mergedHistory, mergedCount);
    g_historyCount = mergedCount;
    
    // Update cached values from last entry
    if(g_historyCount > 0)
    {
        g_basePriceCached = rebuildReferencePrice;
        g_referenceM1Power = rebuildReferenceM1;
    }
    
    // Save merged history to file
    MqlDateTime dtSave;
    TimeToStruct(TimeGMT(), dtSave);
    SaveBasePriceHistory(dtSave.year, dtSave.day_of_year + 1, mergedHistory, g_historyCount);
    
#ifdef ENABLE_DEBUG_LOGS
    Print("====================");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("     REBUILD COMPLETE                                           ");
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Total Entries: ", g_historyCount);
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   Base Price: ", DoubleToString(g_basePriceCached, Digits));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("   M1 Power: ", DoubleToString(g_referenceM1Power, 5));
#endif
#ifdef ENABLE_DEBUG_LOGS
    Print("====================");
#endif
}

//+------------------------------------------------------------------+
//| Get current base price for TH calculations                       |
//+------------------------------------------------------------------+
double GetBasePriceForTH()
{
    // If not initialized, use daily close as fallback
    if(g_basePriceCached == EMPTY_VALUE || g_basePriceCached == 0.0)
    {
        return g_dailyClosePriceForTH;
    }
    
    return g_basePriceCached;
}

//+------------------------------------------------------------------+
//| Print base price history table (matching Java format)            |
//+------------------------------------------------------------------+
#ifdef ENABLE_DEBUG_LOGS
void PrintBasePriceHistory()
{
    if(g_historyCount == 0)
    {
        Print("   Base Price History: No entries yet");
        return;
    }
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    
    Print("+---------------------------------------------------------------------------------------------------------------------+");
    Print("|     BASE PRICE HISTORY TODAY (All 30-min updates) - ", g_historyCount, " entries                                                    |");
    Print("+---------------------------------------------------------------------------------------------------------------------+");
    Print("|  Time  | 30-Min Price    | Ref Price (Used)      | Status/D%           | Ref M1     | M1 Old     | M1 New     |");
    Print("|        |                 |                       |                     |            |            |            |");
    Print("|  ----- | --------------- | --------------------- | ------------------- | ---------- | ---------- | ---------- |");

    // P-PERF-19c: hoisted (see the other loop sites) so a debug build cannot
    // re-resolve the symbol state once per row.
    int printCount = g_historyCount;
    for(int i = 0; i < printCount; i++)
    {
        string entry = GetHistoryEntry(i);
        string parts[];
        int partCount = StringSplit(entry, '|', parts);
        
        if(partCount >= 6)
        {
            string time = parts[0];
            string price30min = parts[1];
            string refPrice = parts[2];
            string status = parts[3];
            string m1Old = parts[4];
            string m1New = parts[5];
            
            StringReplace(m1Old, "M1:", "");
            StringReplace(m1New, "M1:", "");
            
            // Calculate Ref M1
            string refM1 = m1Old;
            if(i == 0)
            {
                refM1 = "-";
            }
            
            // Format with proper spacing
            string line = StringFormat("|  %s | %15s | %21s | %19s | %10s | %10s | %10s |",
                                      time,
                                      price30min,
                                      refPrice,
                                      status,
                                      refM1,
                                      m1Old,
                                      m1New);
            
            Print(line);
        }
    }
    
    Print("+---------------------------------------------------------------------------------------------------------------------+");
}
#else
#define PrintBasePriceHistory()
#endif

//+------------------------------------------------------------------+
//| Save base price history to log file (matching Java format)       |
//+------------------------------------------------------------------+
#ifdef ENABLE_DEBUG_LOGS
void SaveBasePriceHistoryToFile()
{
    if(g_historyCount == 0) return;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    
    // Get current symbol and sanitize it for filename
    string symbol = Symbol();
    StringReplace(symbol, "/", "");  // Remove slashes (e.g., EUR/USD -> EURUSD)
    StringReplace(symbol, "\\", ""); // Remove backslashes
    StringReplace(symbol, ":", "");  // Remove colons
    
    // Include symbol in filename: base_price_history_log_EURUSD_2025_323.txt
    string filename = StringFormat("base_price_history_log_%s_%d_%03d.txt", symbol, dt.year, dt.day_of_year + 1);
    int fileHandle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
    
    if(fileHandle == INVALID_HANDLE)
    {
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] SaveHistoryToFile: ERROR - Failed to create log file");
#endif
        return;
    }
    
    // Header
    FileWriteString(fileHandle, "+---------------------------------------------------------------------------------------------------------------------+\n");
    FileWriteString(fileHandle, StringFormat("|  BASE PRICE HISTORY TODAY - %s (Day %d of %d) - %d entries                                          |\n", 
                                             TimeToString(TimeGMT(), TIME_DATE), dt.day_of_year + 1, dt.year, g_historyCount));
    FileWriteString(fileHandle, "+---------------------------------------------------------------------------------------------------------------------+\n");
    
    // Column headers
    FileWriteString(fileHandle, "|  Time  | 30-Min Price    | Ref Price (Used)      | Status/D%           | Ref M1     | M1 Old     | M1 New     |\n");
    FileWriteString(fileHandle, "|        |                 |                       |                     |            |            |            |\n");
    FileWriteString(fileHandle, "|  ----- | --------------- | --------------------- | ------------------- | ---------- | ---------- | ---------- |\n");
    
    // Data rows
    // P-PERF-19c: hoisted (see HistoryEntryExists) - the condition resolved the
    // symbol state per row.
    int rowCount = g_historyCount;
    for(int i = 0; i < rowCount; i++)
    {
        string entry = GetHistoryEntry(i);
        string parts[];
        int partCount = StringSplit(entry, '|', parts);
        
        if(partCount >= 6)
        {
            string time = parts[0];
            string price30min = parts[1];
            string refPrice = parts[2];
            string status = parts[3];
            string m1Old = parts[4];
            string m1New = parts[5];
            
            // Extract M1 values
            StringReplace(m1Old, "M1:", "");
            StringReplace(m1New, "M1:", "");
            
            // Calculate Ref M1 (current reference M1 power at time of this entry)
            string refM1 = m1Old;  // Use old M1 as reference
            if(i == 0)
            {
                refM1 = "-";  // First entry has no reference
            }
            
            // Format row with proper spacing (matching Java format)
            string line = StringFormat("|  %s | %15s | %21s | %19s | %10s | %10s | %10s |\n",
                                      time,
                                      price30min,
                                      refPrice,
                                      status,
                                      refM1,
                                      m1Old,
                                      m1New);
            
            FileWriteString(fileHandle, line);
        }
    }
    
    // Footer
    FileWriteString(fileHandle, "+---------------------------------------------------------------------------------------------------------------------+\n");
    FileWriteString(fileHandle, "\n");
    
    // Current State
    FileWriteString(fileHandle, "=== CURRENT STATE ===\n");
    FileWriteString(fileHandle, StringFormat("Current Base Price: %s\n", DoubleToString(g_basePriceCached, Digits)));
    FileWriteString(fileHandle, StringFormat("Current M1 Power: %s\n", DoubleToString(g_referenceM1Power, 5)));
    FileWriteString(fileHandle, StringFormat("Total Entries Today: %d\n", g_historyCount));
    FileWriteString(fileHandle, "\n");
    
    // Timezone Information
    datetime gmtNow = TimeGMT();
    datetime serverNow = TimeCurrent();
    // FIXED: Calculate offset as Server - GMT for correct conversion
    int timezoneOffsetSeconds = (int)(serverNow - gmtNow);
    int timezoneOffsetHours = timezoneOffsetSeconds / 3600;
    
    FileWriteString(fileHandle, "=== TIMEZONE INFORMATION ===\n");
    FileWriteString(fileHandle, StringFormat("Server Time: %s\n", TimeToString(serverNow, TIME_DATE|TIME_MINUTES)));
    FileWriteString(fileHandle, StringFormat("GMT Time: %s\n", TimeToString(gmtNow, TIME_DATE|TIME_MINUTES)));
    FileWriteString(fileHandle, StringFormat("Timezone Offset: GMT %s%d hours\n", (timezoneOffsetHours >= 0 ? "+" : ""), timezoneOffsetHours));
    FileWriteString(fileHandle, "\n");
    
    // Recent M30 Bars
    FileWriteString(fileHandle, "=== RECENT M30 BARS (Last 5 completed bars) ===\n");
    for(int i = 1; i <= 5; i++)
    {
        datetime barTime = iTime(Symbol(), PERIOD_M30, i);
        double barClose = iClose(Symbol(), PERIOD_M30, i);
        // FIXED: Use centralized conversion function
        datetime barTimeGMT = ConvertServerToGMT(barTime);
        
        if(barTime > 0)
        {
            FileWriteString(fileHandle, StringFormat("Bar %d:\n", i));
            FileWriteString(fileHandle, StringFormat("  Server Time: %s\n", TimeToString(barTime, TIME_DATE|TIME_MINUTES)));
            FileWriteString(fileHandle, StringFormat("  GMT Time: %s\n", TimeToString(barTimeGMT, TIME_DATE|TIME_MINUTES)));
            FileWriteString(fileHandle, StringFormat("  Close: %s\n", DoubleToString(barClose, Digits)));
        }
    }
    
    FileClose(fileHandle);
    
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] SaveHistoryToFile: Saved ", g_historyCount, " entries to ", filename);
#endif
}
#else
// Stub function when debug logs are disabled
void SaveBasePriceHistoryToFile()
{
    // Debug logs disabled - no operation
    return;
}
#endif

//+------------------------------------------------------------------+
//| LRU Eviction: Remove least recently used symbol states           |
//+------------------------------------------------------------------+
void EvictLeastRecentlyUsedSymbolState()
{
    if(g_symbolStateCount <= 1) return;
    
    datetime currentTime = TimeCurrent();
    int oldestIndex = -1;
    datetime oldestTime = currentTime;
    
    for(int i = 0; i < g_symbolStateCount; i++)
    {
        if(g_symbolStates[i].lastAccessTime < oldestTime)
        {
            oldestTime = g_symbolStates[i].lastAccessTime;
            oldestIndex = i;
        }
    }
    
    if(oldestIndex < 0) return;
    
    if((currentTime - oldestTime) < SYMBOL_STATE_INACTIVE_HOURS * 3600)
    {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] EvictLRU: Oldest state only ", (int)(currentTime - oldestTime), "s old, skipping eviction");
        #endif
        return;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] EvictLRU: Removing symbol '", g_symbolStates[oldestIndex].symbol, "'");
    #endif
    
    ArrayFree(g_symbolStates[oldestIndex].basePriceHistory);
    
    for(int i = oldestIndex; i < g_symbolStateCount - 1; i++)
    {
        g_symbolStates[i] = g_symbolStates[i + 1];
    }
    
    g_symbolStateCount--;
    ArrayResize(g_symbolStates, g_symbolStateCount);
    
    _g_cachedStateIdx = -1;
    _g_cachedStateSymbol = "";
}

//+------------------------------------------------------------------+
//| PERF: Extract timeBlock key from a history entry (text before |) |
//+------------------------------------------------------------------+
string ExtractTimeBlock(const string &entry)
{
    int pipePos = StringFind(entry, "|");
    if(pipePos <= 0) return "";
    return StringSubstr(entry, 0, pipePos);
}

//+------------------------------------------------------------------+
//| Cleanup BasePriceManager resources                               |
//| Called from OnDeinitHandler to prevent memory leaks              |
//| GOLD FIX v3: Enhanced cleanup with proper array freeing          |
//+------------------------------------------------------------------+
void CleanupBasePriceManager()
{
    DEBUG_PRINTF("[BasePriceManager] CleanupBasePriceManager() - Freeing ", IntegerToString(g_symbolStateCount) + " symbol states");
    
    //                                                                
    // CRITICAL FIX: Free nested arrays within each state
    // This prevents memory leak when indicator is removed
    //                                                                
    for(int i = 0; i < g_symbolStateCount; i++)
    {
        if(ArraySize(g_symbolStates[i].basePriceHistory) > 0)
        {
            ArrayFree(g_symbolStates[i].basePriceHistory);
        }
    }
    
    // Free main state array
    if(g_symbolStateCount > 0)
    {
        ArrayFree(g_symbolStates);
        g_symbolStateCount = 0;
    }
    
    DEBUG_PRINT("[BasePriceManager] CleanupBasePriceManager() - Cleanup complete (memory leak fixed)");
}

#endif // BASE_PRICE_B_MQH
