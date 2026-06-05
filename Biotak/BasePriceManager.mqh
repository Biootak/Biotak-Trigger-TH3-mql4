  //+------------------------------------------------------------------+
//| BasePriceManager.mqh                                              |
//| Base Price Management with 30-minute block updates                |
//| Matches MotiveWave/Java implementation exactly                    |
//+------------------------------------------------------------------+

#property strict

#include "BasePriceHistoryManager.mqh"
#include "MarketHoursDetector.mqh"
#include "DynamicTradingDayDetector.mqh"

// Constants
#define BLOCK_MINUTES 30                                 // 30-minute blocks
// NOTE: M1_THRESHOLD_PERCENT is now configurable via inpBasePriceThresholdPercent input
// Default value: 0.066% (matches Java implementation)
#define SANITY_CHECK_THRESHOLD_PERCENT 10.0              // 10% threshold for restored price validation



// HISTORY FORMAT VERSION: Increment this when timezone logic changes
// This will trigger automatic cleanup of old history files with incorrect timestamps
// Version History:
// - v1: Original format with Server Time
// - v2: GMT format (times stored in GMT/UTC)
// - v3: GMT format + Block boundary update timing fix (no more 13:59, 14:29 entries)
// - v4: GMT format + Start from 00:00 GMT (not 00:00 Server Time)
#define HISTORY_FORMAT_VERSION 4                         // v4: GMT + Correct start of day

//+------------------------------------------------------------------+
//| Debug: Print recent M30 bars                                     |
//+------------------------------------------------------------------+
#ifdef ENABLE_DEBUG_LOGS
void PrintRecentM30Bars(int count = 5)
{
    Print("[BasePriceManager] ====================");
    Print("[BasePriceManager]    RECENT M30 BARS (Last ", count, " completed bars)                     ");
    Print("[BasePriceManager] ====================");
    
    for(int i = 1; i <= count; i++)  // Start from 1 (skip current incomplete bar)
    {
        datetime barTime = iTime(Symbol(), PERIOD_M30, i);
        double barClose = iClose(Symbol(), PERIOD_M30, i);
        
        if(barTime == 0) continue;  // Skip if bar doesn't exist
        
        // FIXED: Use centralized conversion function
        datetime barTimeGMT = ConvertServerToGMT(barTime);
        
        Print("[BasePriceManager]    Bar ", i, ":");
        Print("[BasePriceManager]      Server Time: ", TimeToString(barTime, TIME_DATE|TIME_MINUTES));
        Print("[BasePriceManager]      GMT Time:    ", TimeToString(barTimeGMT, TIME_DATE|TIME_MINUTES));
        Print("[BasePriceManager]      Close:       ", DoubleToString(barClose, Digits));
    }
    
    Print("[BasePriceManager] ====================");
}
#else
#define PrintRecentM30Bars(count)
#endif

//+------------------------------------------------------------------+
//| Base Price State Structure (per symbol)                          |
//| Each symbol/chart maintains its own independent state            |
//+------------------------------------------------------------------+
struct BasePriceState
{
    string symbol;                                       // Symbol name (e.g., "EURUSD")
    double basePriceCached;                              // Current base price
    datetime lastProcessedBlockTimestamp;                // Last processed 30-min block
    double referenceM1Power;                             // M1 power of last accepted base price
    string basePriceHistory[];                           // Today's history entries
    int historyCount;                                    // Number of history entries
    int lastHistoryDay;                                  // Track which day's history we have
    int lastHistoryYear;                                 // Track which year's history we have
    bool systemInitialized;                              // Track if system has been initialized
    datetime lastAccessTime;                             // Last time this state was accessed (for LRU eviction)
};

// Global array to store state for each symbol
static BasePriceState g_symbolStates[];
static int g_symbolStateCount = 0;

//+------------------------------------------------------------------+
//| CONSTANTS - Buffer Overflow Prevention                           |
//+------------------------------------------------------------------+
#define MAX_SYMBOL_STATES 100              // Maximum symbols to track
#define SYMBOL_STATE_LRU_THRESHOLD 50      // Trigger LRU eviction above this count
#define SYMBOL_STATE_INACTIVE_HOURS 24     // Only evict states inactive for 24+ hours
#define LOCK_TIMEOUT_SECONDS 2             // Stale lock timeout
#define LOCK_MAX_ATTEMPTS 5                // Maximum lock acquisition attempts
#define LOCK_RETRY_DELAY_MS 20             // Delay between lock attempts

// Cached symbol state index (performance: 50+ calls/tick   1 call/tick)
static int _g_cachedStateIdx = -1;
static string _g_cachedStateSymbol = "";

//+------------------------------------------------------------------+
//| Get index of state for current symbol (or create new)            |
//| CRITICAL FIX: Buffer overflow prevention + Enhanced mutex        |
//+------------------------------------------------------------------+
int GetSymbolStateIndex()
{
    string currentSymbol = Symbol();
    
    //                                                                
    // CRITICAL FIX #1: Buffer Overflow Prevention
    //                                                                
    if(g_symbolStateCount < 0) {
        Print("  CRITICAL: Corrupted symbol state count (", g_symbolStateCount, ")");
        g_symbolStateCount = 0;
        ArrayResize(g_symbolStates, 0);
        return -1;
    }
    
    if(g_symbolStateCount >= MAX_SYMBOL_STATES) {
        Print("  CRITICAL: Symbol state limit reached (", MAX_SYMBOL_STATES, ")");
        Print("   Cannot track more symbols. Consider increasing MAX_SYMBOL_STATES.");
        return -1;
    }
    
    //                                                                
    // CRITICAL FIX #2: Enhanced Lock with Stale Detection
    //                                                                
    string lockName = "Biotak_StateAccess_Lock_" + currentSymbol;
    string lockTimeName = lockName + "_Time";
    
    // Check for stale lock
    if(GlobalVariableCheck(lockTimeName)) {
        datetime lockTime = (datetime)GlobalVariableGet(lockTimeName);
        if(TimeCurrent() - lockTime > LOCK_TIMEOUT_SECONDS) {
            Print("   Stale lock detected (", TimeCurrent() - lockTime, "s old), forcing release");
            GlobalVariableDel(lockName);
            GlobalVariableDel(lockTimeName);
        }
    }
    
    // Try to acquire lock
    bool lockAcquired = false;
    for(int attempt = 0; attempt < LOCK_MAX_ATTEMPTS; attempt++)
    {
        if(!GlobalVariableCheck(lockName))
        {
            GlobalVariableSet(lockName, 1.0);
            GlobalVariableSet(lockTimeName, (double)TimeCurrent());
            GlobalVariableTemp(lockName);
            GlobalVariableTemp(lockTimeName);
            lockAcquired = true;
            break;
        }
        Sleep(LOCK_RETRY_DELAY_MS);
    }
    
    if(!lockAcquired)
    {
        Print("  CRITICAL: GetSymbolStateIndex failed to acquire lock after ", LOCK_MAX_ATTEMPTS, " attempts");
        Print("   Symbol: ", currentSymbol, " - Aborting to prevent race condition");
        return -1; // CRITICAL FIX: Return error instead of proceeding
    }
    
    //                                                                
    // CRITICAL FIX #3: Bounds-Checked Search
    //                                                                
    int resultIndex = -1;
    int arraySize = ArraySize(g_symbolStates);
    
    // Validate array size matches count
    if(arraySize != g_symbolStateCount) {
        Print("   WARNING: Array size mismatch (size=", arraySize, ", count=", g_symbolStateCount, ")");
        g_symbolStateCount = arraySize; // Sync
    }
    
    for(int i = 0; i < g_symbolStateCount && i < arraySize; i++)
    {
        if(g_symbolStates[i].symbol == currentSymbol)
        {
            resultIndex = i;
            break;
        }
    }
    
    // Release lock
    GlobalVariableDel(lockName);
    GlobalVariableDel(lockTimeName);
    
    if(resultIndex >= 0)
    {
        return resultIndex;
    }
    
    //                                                                
    // CRITICAL FIX #4: Safe State Creation with Bounds Check
    //                                                                
    if(g_symbolStateCount >= MAX_SYMBOL_STATES) {
        Print("  Cannot create new state - limit reached");
        return -1;
    }
    
    // Create new state for this symbol
    int newIndex = g_symbolStateCount;
    
    // Safe resize with validation
    if(ArrayResize(g_symbolStates, newIndex + 1) != newIndex + 1) {
        Print("  CRITICAL: Failed to resize symbol states array");
        return -1;
    }
    
    // Initialize new state
    g_symbolStates[newIndex].symbol = currentSymbol;
    g_symbolStates[newIndex].basePriceCached = 0.0;
    g_symbolStates[newIndex].lastProcessedBlockTimestamp = 0;
    g_symbolStates[newIndex].referenceM1Power = 0.0;
    ArrayResize(g_symbolStates[newIndex].basePriceHistory, 0);
    g_symbolStates[newIndex].historyCount = 0;
    g_symbolStates[newIndex].lastHistoryDay = 0;
    g_symbolStates[newIndex].lastHistoryYear = 0;
    g_symbolStates[newIndex].systemInitialized = false;
    
    g_symbolStateCount++;
    
    Print("  Created new state for symbol: ", currentSymbol, " (Index: ", newIndex, ")");
    return newIndex;
    ArrayResize(g_symbolStates, g_symbolStateCount + 1);
    g_symbolStates[g_symbolStateCount].symbol = currentSymbol;
    g_symbolStates[g_symbolStateCount].basePriceCached = EMPTY_VALUE;
    g_symbolStates[g_symbolStateCount].lastProcessedBlockTimestamp = 0;  // Used for log deduplication
    g_symbolStates[g_symbolStateCount].referenceM1Power = 0.0;
    ArrayResize(g_symbolStates[g_symbolStateCount].basePriceHistory, 0);
    g_symbolStates[g_symbolStateCount].historyCount = 0;
    g_symbolStates[g_symbolStateCount].lastHistoryDay = -1;
    g_symbolStates[g_symbolStateCount].lastHistoryYear = -1;
    g_symbolStates[g_symbolStateCount].systemInitialized = false;
    
    DEBUG_PRINTF("Created new state for symbol: ", currentSymbol);
    
    g_symbolStateCount++;
    return g_symbolStateCount - 1;
}

// Helper functions for array access (to avoid macro expansion issues)
string GetHistoryEntry(int index)
{
    int stateIdx = GetSymbolStateIndex();
    if(index >= 0 && index < g_symbolStates[stateIdx].historyCount)
    {
        return g_symbolStates[stateIdx].basePriceHistory[index];
    }
    return "";
}

void SetHistoryEntry(int index, string value)
{
    int stateIdx = GetSymbolStateIndex();
    if(index >= 0 && index < ArraySize(g_symbolStates[stateIdx].basePriceHistory))
    {
        g_symbolStates[stateIdx].basePriceHistory[index] = value;
    }
}

void ResizeHistory(int newSize)
{
    int stateIdx = GetSymbolStateIndex();
    ArrayResize(g_symbolStates[stateIdx].basePriceHistory, newSize);
}

void GetHistoryArray(string &output[])
{
    int stateIdx = GetSymbolStateIndex();
    int count = g_symbolStates[stateIdx].historyCount;
    ArrayResize(output, count);
    for(int i = 0; i < count; i++)
    {
        output[i] = g_symbolStates[stateIdx].basePriceHistory[i];
    }
}

void SetHistoryArray(string &inputArray[], int count)
{
    int stateIdx = GetSymbolStateIndex();
    ArrayResize(g_symbolStates[stateIdx].basePriceHistory, count);
    for(int i = 0; i < count; i++)
    {
        g_symbolStates[stateIdx].basePriceHistory[i] = inputArray[i];
    }
    g_symbolStates[stateIdx].historyCount = count;
}

// Legacy global variables for backward compatibility (now use GetSymbolStateIndex())
// These are kept as macros that redirect to symbol-specific state
#define g_basePriceCached (g_symbolStates[GetSymbolStateIndex()].basePriceCached)
#define g_lastProcessedBlockTimestamp (g_symbolStates[GetSymbolStateIndex()].lastProcessedBlockTimestamp)
#define g_referenceM1Power (g_symbolStates[GetSymbolStateIndex()].referenceM1Power)
#define g_historyCount (g_symbolStates[GetSymbolStateIndex()].historyCount)
#define g_lastHistoryDay (g_symbolStates[GetSymbolStateIndex()].lastHistoryDay)
#define g_lastHistoryYear (g_symbolStates[GetSymbolStateIndex()].lastHistoryYear)
#define g_systemInitialized (g_symbolStates[GetSymbolStateIndex()].systemInitialized)

//+------------------------------------------------------------------+
//| Validate restored base price against current market conditions   |
//| Returns true if price is valid, false if should be rejected      |
//+------------------------------------------------------------------+
bool ValidateRestoredBasePrice(const double restoredPrice, const double currentBid, double &validatedPrice)
{
    // Handle edge case: invalid restored price
    if(restoredPrice <= 0.0)
    {
        DEBUG_PRINT("[BasePriceManager] ValidateRestoredBasePrice() - ERROR: Invalid restored price, using bid");
        validatedPrice = currentBid;
        return false;
    }
    
    // Handle edge case: invalid bid price
    if(currentBid <= 0.0)
    {
        DEBUG_PRINT("[BasePriceManager] ValidateRestoredBasePrice() - ERROR: Invalid bid, using restored price");
        validatedPrice = restoredPrice;
        return true;
    }
    
    // Calculate percentage difference
    double percentDiff = MathAbs((restoredPrice - currentBid) / currentBid) * 100.0;
    
    // Check if within acceptable range
    if(percentDiff <= SANITY_CHECK_THRESHOLD_PERCENT)
    {
        // ACCEPT: Restored price is reasonable
        validatedPrice = restoredPrice;
        DEBUG_PRINTF2("[BasePriceManager] ValidateRestoredBasePrice() -   ACCEPTED (diff=", DoubleToString(percentDiff, 2), "%)");
        return true;
    }
    else
    {
        // REJECT: Restored price is stale/invalid
        validatedPrice = currentBid;
        DEBUG_PRINTF5("[BasePriceManager] ValidateRestoredBasePrice() -    REJECTED (diff=", DoubleToString(percentDiff, 2), "% > ", DoubleToString(SANITY_CHECK_THRESHOLD_PERCENT, 1), "%), using bid", "");
        return false;
    }
}

//+------------------------------------------------------------------+
//| Initialize base price system                                     |
//| Loads history from file if available                             |
//+------------------------------------------------------------------+
void InitializeBasePriceSystem()
{
    // CHECK HISTORY FORMAT VERSION: Auto-cleanup if timezone logic changed
    if(!CheckHistoryFormatVersion(HISTORY_FORMAT_VERSION))
    {
        #ifdef ENABLE_DEBUG_LOGS
        Print("====================");
        Print("      HISTORY FORMAT UPGRADE DETECTED                           ");
        Print("   Cleaning up old history files with incorrect timestamps...   ");
        Print("====================");
        #endif
        
        DeleteAllHistoryFiles();
        UpdateHistoryFormatVersion(HISTORY_FORMAT_VERSION);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("====================");
        Print("     History cleanup complete. Will rebuild from M30 data.     ");
        Print("====================");
        #endif
    }
    
    // CRITICAL: Use GMT/UTC time to match Java implementation
    datetime gmtTime = TimeGMT();
    datetime serverTime = TimeCurrent();
    
    MqlDateTime dtGMT, dtServer;
    TimeToStruct(gmtTime, dtGMT);
    TimeToStruct(serverTime, dtServer);
    
    // FIXED: Calculate timezone offset as Server - GMT for correct conversion
    // If server is GMT-2 (behind): offset = -7200 (negative)
    // If server is GMT+2 (ahead): offset = +7200 (positive)
    // To convert Server GMT: serverTime - offset
    // To convert GMT Server: gmtTime + offset
    int timezoneOffsetSeconds = (int)(serverTime - gmtTime);
    int timezoneOffsetHours = timezoneOffsetSeconds / 3600;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] ====================");
    Print("[BasePriceManager]    TIMEZONE INFORMATION                                          ");
    Print("[BasePriceManager] ====================");
    Print("[BasePriceManager]    Server Time: ", TimeToString(serverTime, TIME_DATE|TIME_MINUTES));
    Print("[BasePriceManager]    GMT Time:    ", TimeToString(gmtTime, TIME_DATE|TIME_MINUTES));
    Print("[BasePriceManager]    Offset:      Server = GMT", (timezoneOffsetHours >= 0 ? "+" : ""), timezoneOffsetHours, " hours");
    Print("[BasePriceManager]    Day (Server): ", dtServer.day_of_year + 1);
    Print("[BasePriceManager]    Day (GMT):    ", dtGMT.day_of_year + 1);
    Print("[BasePriceManager] ====================");
    #endif
    
    // Debug: Show recent M30 bars
    PrintRecentM30Bars(5);
    
    int year = dtGMT.year;
    // CRITICAL: MQL4 day_of_year is 0-based, but Java uses 1-based
    // Add 1 to match Java implementation
    int dayOfYear = dtGMT.day_of_year + 1;
    
    // Verify file integrity before loading
    if(!VerifyHistoryFileIntegrity(year, dayOfYear))
    {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] InitializeBasePriceSystem() - File integrity check failed, attempting repair...");
        #endif
        int repairedCount = RepairHistoryFile(year, dayOfYear);
        if(repairedCount < 0)
        {
            #ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager] InitializeBasePriceSystem() - Repair failed, starting fresh");
            #endif
        }
    }
    
    // Load history from file
    DEBUG_PRINTF2("[BasePriceManager] InitializeBasePriceSystem() - Loading history for year=", IntegerToString(year), ", dayOfYear=" + IntegerToString(dayOfYear));
    string tempHistory[];
    int loadedCount = LoadBasePriceHistory(year, dayOfYear, tempHistory);
    
    // Check if loaded history needs migration (old format with Server Time instead of GMT)
    // Look for ANY entry with time >= 22:00 which indicates yesterday's data
    bool needsMigration = false;
    if(loadedCount > 0)
    {
        #ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] Checking ", loadedCount, " entries for migration...");
        #endif
        
        // Check all entries for times >= 22:00 (yesterday's data)
        for(int i = 0; i < loadedCount; i++)
        {
            string entry = tempHistory[i];
            string parts[];
            int partCount = StringSplit(entry, '|', parts);
            
            if(partCount >= 1)
            {
                string timeStr = parts[0];
                
                // Extract hour from time string (format: "HH:mm")
                string hourStr = StringSubstr(timeStr, 0, 2);
                int hour = (int)StringToInteger(hourStr);
                
                // If any entry is >= 22:00, it's from yesterday
                if(hour >= 22)
                {
                    needsMigration = true;
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("[BasePriceManager]   Migration needed: Found entry at ", timeStr, " (yesterday's data)");
                    #endif
                    break;  // No need to check more
                }
            }
        }
        
        #ifdef ENABLE_DEBUG_LOGS
        if(!needsMigration)
        {
            Print("[BasePriceManager]   No migration needed: All entries are from today");
        }
        #endif
    }
    
    if(needsMigration && loadedCount > 0)
    {
        #ifdef ENABLE_DEBUG_LOGS
        Print("====================");
        Print("      MIGRATION DETECTED - OLD FORMAT WITH SERVER TIME          ");
        Print("   Deleting old file and rebuilding with GMT format...          ");
        Print("====================");
        #endif
        
        // Delete old file
        string filePath = GetHistoryFilePath(year, dayOfYear);
        if(FileDelete(filePath))
        {
            #ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager]   Old history file deleted successfully");
            #endif
        }
        else
        {
            #ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager]    Could not delete old file (error: ", GetLastError(), ")");
            #endif
        }
        
        // Clear loaded data
        loadedCount = 0;
        ArrayResize(tempHistory, 0);
    }
    
    SetHistoryArray(tempHistory, loadedCount);
    g_historyCount = loadedCount;
    g_lastHistoryDay = dayOfYear;
    g_lastHistoryYear = year;
    DEBUG_PRINTF("[BasePriceManager] InitializeBasePriceSystem() - Loaded ", IntegerToString(loadedCount) + " entries");
    
    if(loadedCount > 0)
    {
        // Get history array for processing
        string workingHistory[];
        GetHistoryArray(workingHistory);
        
        // Deduplicate loaded history
        int newCount = DeduplicateHistory(workingHistory, g_historyCount);
        bool needsSave = (newCount != g_historyCount);
        g_historyCount = newCount;
        
        // Migrate old format entries
        int migratedCount = MigrateToNewFormat(workingHistory, g_historyCount);
        if(migratedCount > 0)
        {
            needsSave = true;
        }
        
        // Update history array
        SetHistoryArray(workingHistory, g_historyCount);
        
        // Save cleaned history back to file if changes were made
        if(needsSave)
        {
            SaveBasePriceHistory(year, dayOfYear, workingHistory, g_historyCount);
        }
        
        // Extract base price from last entry
        if(g_historyCount > 0)
        {
            string lastEntry = GetHistoryEntry(g_historyCount - 1);
            string parts[];
            int partCount = StringSplit(lastEntry, '|', parts);
            
            if(partCount >= 3)
            {
                // Extract refPrice (field 2, format: "price ( change)")
                string refPriceStr = parts[2];
                int spacePos = StringFind(refPriceStr, " ");
                if(spacePos > 0)
                {
                    refPriceStr = StringSubstr(refPriceStr, 0, spacePos);
                }
                
                double restoredPrice = StringToDouble(refPriceStr);
                double currentBid = Bid;
                
                // SANITY CHECK: Validate restored price against current market conditions
                double validatedPrice = 0.0;
                bool isValid = ValidateRestoredBasePrice(restoredPrice, currentBid, validatedPrice);
                
                // Use validated price (either restored or current bid)
                g_basePriceCached = validatedPrice;
                g_referenceM1Power = CalculateM1PowerForBasePrice(g_basePriceCached);
                
                // Log detailed info only on first initialization
                #ifdef ENABLE_DEBUG_LOGS
                if(!g_systemInitialized)
                {
                    Print("====================");
                    if(isValid)
                    {
                        Print("     BASE PRICE RESTORED: ", DoubleToString(g_basePriceCached, Digits), " | M1: ", DoubleToString(g_referenceM1Power, 5));
                    }
                    else
                    {
                        Print("      STALE PRICE REJECTED: ", DoubleToString(restoredPrice, Digits), "   ", DoubleToString(g_basePriceCached, Digits));
                    }
                    Print("====================");
                }
                #endif
            }
        }
        else
        {
            // No history entries - initialize from current bid
            double currentBid = Bid;
            if(currentBid > 0.0)
            {
                g_basePriceCached = currentBid;
                g_referenceM1Power = CalculateM1PowerForBasePrice(g_basePriceCached);
                
                #ifdef ENABLE_DEBUG_LOGS
                if(!g_systemInitialized)
                {
                    Print("====================");
                    Print("      BASE PRICE INIT: ", DoubleToString(g_basePriceCached, Digits), " | M1: ", DoubleToString(g_referenceM1Power, 5));
                    Print("====================");
                }
                #endif
            }
        }
    }
    else
    {
        // No history file - initialize from current bid
        double currentBid = Bid;
        if(currentBid > 0.0)
        {
            g_basePriceCached = currentBid;
            g_referenceM1Power = CalculateM1PowerForBasePrice(g_basePriceCached);
            
            #ifdef ENABLE_DEBUG_LOGS
            if(!g_systemInitialized)
            {
                Print("====================");
                Print("      BASE PRICE INIT (First Run): ", DoubleToString(g_basePriceCached, Digits), " | M1: ", DoubleToString(g_referenceM1Power, 5));
                Print("====================");
            }
            #endif
        }
    }
    
    // Cleanup old history files and temp files (only on first init)
    if(!g_systemInitialized)
    {
        CleanupTemporaryFiles();
        CleanupOldHistory(DEFAULT_DAYS_TO_KEEP);
        
        // Print and save history table on first initialization
        #ifdef ENABLE_DEBUG_LOGS
        if(g_historyCount > 0)
        {
            Print("====================");
            Print("   CHART REOPENED - RESTORING TODAY'S BASE PRICE                ");
            Print("   Date: Day ", dayOfYear, " of Year ", year);
            Print("   Base Price: ", DoubleToString(g_basePriceCached, Digits));
            Print("   Total Entries: ", g_historyCount);
            Print("====================");
            PrintBasePriceHistory();
            SaveBasePriceHistoryToFile();
        }
        else
        {
            Print("====================");
            Print("      FIRST RUN TODAY - REBUILDING HISTORY FROM START OF DAY    ");
            Print("   Current time: ", TimeToString(gmtTime, TIME_DATE|TIME_MINUTES));
            Print("====================");
        }
        #endif
            
        // Rebuild history from start of day (like Java) - always run regardless of debug mode
        if(g_historyCount == 0)
        {
            RebuildHistoryFromStartOfDay();
            
            // Print rebuilt history
            #ifdef ENABLE_DEBUG_LOGS
            if(g_historyCount > 0)
            {
                Print("====================");
                Print("     HISTORY REBUILT SUCCESSFULLY                              ");
                Print("   Total Entries: ", g_historyCount);
                Print("   Base Price: ", DoubleToString(g_basePriceCached, Digits));
                Print("====================");
                PrintBasePriceHistory();
                SaveBasePriceHistoryToFile();
            }
            #endif
        }
    }
    
    g_systemInitialized = true;
}

//+------------------------------------------------------------------+
//| Convert Server Time to GMT Time                                  |
//| CENTRALIZED: All timezone conversions use this function          |
//+------------------------------------------------------------------+
datetime ConvertServerToGMT(const datetime serverTime)
{
    // Calculate offset: Server - GMT
    // If server is GMT-2 (behind): offset = -7200 (negative)
    // If server is GMT+2 (ahead): offset = +7200 (positive)
    datetime gmtNow = TimeGMT();
    datetime serverNow = TimeCurrent();
    int timezoneOffsetSeconds = (int)(serverNow - gmtNow);
    
    // Convert Server GMT: SUBTRACT offset
    // If GMT+2: serverTime - 7200 = serverTime - 2 hours  
    // If GMT-2: serverTime - (-7200) = serverTime + 2 hours  
    datetime gmtTime = serverTime - timezoneOffsetSeconds;
    
    // CRITICAL: Ensure seconds are zero to prevent rounding issues
    MqlDateTime dt;
    TimeToStruct(gmtTime, dt);
    dt.sec = 0;
    gmtTime = StructToTime(dt);
    
    return gmtTime;
}

//+------------------------------------------------------------------+
//| Convert GMT Time to Server Time                                  |
//| CENTRALIZED: All timezone conversions use this function          |
//+------------------------------------------------------------------+
datetime ConvertGMTToServer(const datetime gmtTime)
{
    // Calculate offset: Server - GMT
    datetime gmtNow = TimeGMT();
    datetime serverNow = TimeCurrent();
    int timezoneOffsetSeconds = (int)(serverNow - gmtNow);
    
    // Convert GMT Server: ADD offset
    // If GMT+2: gmtTime + 7200 = gmtTime + 2 hours  
    // If GMT-2: gmtTime + (-7200) = gmtTime - 2 hours  
    datetime serverTime = gmtTime + timezoneOffsetSeconds;
    
    // CRITICAL: Ensure seconds are zero
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);
    dt.sec = 0;
    serverTime = StructToTime(dt);
    
    return serverTime;
}

//+------------------------------------------------------------------+
//| Calculate M1 power for a given base price                        |
//+------------------------------------------------------------------+
double CalculateM1PowerForBasePrice(const double basePrice)
{
    if(basePrice <= 0) return 0.0;
    
    // M1 percentage relative to current timeframe (matching Java FRACTAL_PERCENTAGES)
    // For M1: 0.0208 (2.08%), for M4: 0.0417 (4.17%), etc.
    double m1Percent = 0.0208;  // M1 is always 2.08% regardless of current timeframe
    
    // Calculate M1 power (matching Java: basePrice * percentage)
    double powerM1 = basePrice * m1Percent;
    
    return powerM1;
}

//+------------------------------------------------------------------+
//| Find last M1 candle within a 30-minute block                     |
//| Returns bar index of last M1 candle in block, or -1 if not found |
//| This function is used for history rebuild from M1 data           |
//+------------------------------------------------------------------+
int FindLastM1CandleInBlock(const datetime blockStart, const datetime blockEnd)
{
    // Get total M1 bars available
    int totalM1Bars = iBars(Symbol(), PERIOD_M1);
    if(totalM1Bars <= 0)
    {
#ifdef ENABLE_DEBUG_LOGS
        Print("[BasePriceManager] FindLastM1CandleInBlock() - No M1 bars available");
#endif
        return -1;
    }
    
    // Limit search to last 1000 bars for performance (covers ~16 hours)
    int searchLimit = MathMin(totalM1Bars, 1000);
    
    int lastBarIdx = -1;
    datetime lastBarTime = 0;
    
    // Search from bar 0 (most recent) backwards
    for(int i = 0; i < searchLimit; i++)
    {
        datetime barTime = iTime(Symbol(), PERIOD_M1, i);
        
        // Check if this bar is within the block range
        // blockStart is inclusive, blockEnd is exclusive
        if(barTime >= blockStart && barTime < blockEnd)
        {
            // Keep track of the bar with the latest time (closest to blockEnd)
            if(lastBarIdx == -1 || barTime > lastBarTime)
            {
                lastBarIdx = i;
                lastBarTime = barTime;
            }
        }
        
        // Early exit: if we've passed the block start, no need to continue
        if(barTime < blockStart)
        {
            break;
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    if(lastBarIdx != -1)
    {
        Print("[BasePriceManager] FindLastM1CandleInBlock() - Found M1 bar #", lastBarIdx, 
              " at ", TimeToString(lastBarTime, TIME_DATE|TIME_MINUTES),
              " in block [", TimeToString(blockStart, TIME_MINUTES), "-",
              TimeToString(blockEnd, TIME_MINUTES), "]");
    }
    else
    {
        Print("[BasePriceManager] FindLastM1CandleInBlock() - No M1 bar found in block [",
              TimeToString(blockStart, TIME_MINUTES), "-",
              TimeToString(blockEnd, TIME_MINUTES), "]");
    }
    #endif
    
    return lastBarIdx;
}

//+------------------------------------------------------------------+
//| Merge existing and rebuilt history lists                         |
//| Removes duplicates (existing entries take precedence)            |
//| Sorts by time (oldest first)                                     |
//+------------------------------------------------------------------+
void MergeHistoryLists(const string &existingHistory[], const int existingCount,
                       const string &rebuiltHistory[], const int rebuiltCount,
                       string &mergedHistory[], int &mergedCount)
{
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] MergeHistoryLists() - Merging ", existingCount, " existing + ", rebuiltCount, " rebuilt entries");
#endif
    
    // GOLD FIX: Enhanced buffer overflow prevention with safety margin
    int maxSize = existingCount + rebuiltCount;
    
    // CRITICAL: Add 10% safety margin to prevent edge cases
    int safeMaxSize = (int)(maxSize * 1.1) + 10;
    
    string timeBlocks[];
    string entries[];
    int totalEntries = 0;
    
    // Validate array sizes before allocation
    if(safeMaxSize <= 0 || safeMaxSize > 10000) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  MergeHistoryLists: Invalid array size: ", safeMaxSize);
        #endif
        ArrayResize(mergedHistory, 0);
        mergedCount = 0;
        return;
    }
    
    ArrayResize(timeBlocks, safeMaxSize);
    ArrayResize(entries, safeMaxSize);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("   MergeHistoryLists: Allocated ", safeMaxSize, " slots (", maxSize, " + safety margin)");
    #endif
    
    // Add existing entries first (they take precedence)
    for(int i = 0; i < existingCount; i++)
    {
        string entry = existingHistory[i];
        if(StringLen(entry) == 0) continue;
        
        // Extract time block (first field before |)
        int pipePos = StringFind(entry, "|");
        if(pipePos <= 0) continue;
        
        string timeBlock = StringSubstr(entry, 0, pipePos);
        
        // Check if we already have this time block
        bool exists = false;
        for(int j = 0; j < totalEntries; j++)
        {
            if(timeBlocks[j] == timeBlock)
            {
                exists = true;
                break;
            }
        }
        
        if(!exists)
        {
            // CRITICAL: Double-check bounds before adding
            if(totalEntries >= safeMaxSize) {
                Print("  MergeHistoryLists: Buffer overflow prevented at ", totalEntries, " entries");
                break;
            }
            
            // Additional validation: Check array size
            if(totalEntries >= ArraySize(timeBlocks) || totalEntries >= ArraySize(entries)) {
                Print("  MergeHistoryLists: Array size mismatch detected");
                break;
            }
            
            timeBlocks[totalEntries] = timeBlock;
            entries[totalEntries] = entry;
            totalEntries++;
        }
    }
    
    // Add rebuilt entries only if time block doesn't exist
    for(int i = 0; i < rebuiltCount; i++)
    {
        string entry = rebuiltHistory[i];
        if(StringLen(entry) == 0) continue;
        
        // Extract time block
        int pipePos = StringFind(entry, "|");
        if(pipePos <= 0) continue;
        
        string timeBlock = StringSubstr(entry, 0, pipePos);
        
        // Check if we already have this time block
        bool exists = false;
        for(int j = 0; j < totalEntries; j++)
        {
            if(timeBlocks[j] == timeBlock)
            {
                exists = true;
                break;
            }
        }
        
        if(!exists)
        {
            // CRITICAL: Double-check bounds before adding
            if(totalEntries >= safeMaxSize) {
                Print("  MergeHistoryLists: Buffer overflow prevented (rebuilt) at ", totalEntries, " entries");
                break;
            }
            
            // Additional validation: Check array size
            if(totalEntries >= ArraySize(timeBlocks) || totalEntries >= ArraySize(entries)) {
                Print("  MergeHistoryLists: Array size mismatch detected (rebuilt)");
                break;
            }
            
            timeBlocks[totalEntries] = timeBlock;
            entries[totalEntries] = entry;
            totalEntries++;
        }
        else
        {
#ifdef ENABLE_DEBUG_LOGS
            Print("[BasePriceManager] MergeHistoryLists() - Skipping duplicate time block: ", timeBlock);
#endif
        }
    }
    
    // Sort entries by time (simple bubble sort)
    for(int i = 0; i < totalEntries - 1; i++)
    {
        for(int j = i + 1; j < totalEntries; j++)
        {
            if(timeBlocks[i] > timeBlocks[j])
            {
                // Swap
                string tempTime = timeBlocks[i];
                string tempEntry = entries[i];
                timeBlocks[i] = timeBlocks[j];
                entries[i] = entries[j];
                timeBlocks[j] = tempTime;
                entries[j] = tempEntry;
            }
        }
    }
    
    // Copy to output array
    ArrayResize(mergedHistory, totalEntries);
    for(int i = 0; i < totalEntries; i++)
    {
        mergedHistory[i] = entries[i];
    }
    mergedCount = totalEntries;
    
#ifdef ENABLE_DEBUG_LOGS
    Print("[BasePriceManager] MergeHistoryLists() - Merged result: ", mergedCount, " total entries");
#endif
}



//+------------------------------------------------------------------+
//| Check if history entry already exists for a time block           |
//| FIXED: More robust duplicate detection                           |
//+------------------------------------------------------------------+
bool HistoryEntryExists(const string blockTimeStr)
{
    if(StringLen(blockTimeStr) == 0) return false;
    
    for(int i = 0; i < g_historyCount; i++)
    {
        string entry = GetHistoryEntry(i);
        if(StringLen(entry) == 0) continue;
        
        // Extract time from entry (format: "HH:mm|...")
        int pipePos = StringFind(entry, "|");
        if(pipePos <= 0) continue;
        
        string entryTime = StringSubstr(entry, 0, pipePos);
        
        // Exact match on time string
        if(entryTime == blockTimeStr)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Add entry to base price history                                  |
//+------------------------------------------------------------------+
void AddBasePriceHistoryEntry(const datetime blockTime, const double thirtyMinPrice, 
                               const double refPrice, const string status, 
                               const double deltaPct, const double oldM1, const double newM1)
{
    // CRITICAL: Store time in GMT format (for consistency across platforms)
    // blockTime is in Server Time, convert to GMT
    datetime blockTimeGMT = ConvertServerToGMT(blockTime);
    
    // Format time string for history entry (GMT)
    string timeStr = TimeToString(blockTimeGMT, TIME_MINUTES);
    
    // Format ref price with change (use 5 decimal places to match Java)
    string refPriceStr;
    if(status == "-")
    {
        // INIT entry: use (INITIAL) format
        refPriceStr = StringFormat("%.5f (INITIAL)", refPrice);
    }
    else
    {
        // Normal entry: calculate change from current base price
        double priceChange = refPrice - g_basePriceCached;
        refPriceStr = StringFormat("%.5f (%+.5f)", refPrice, priceChange);
    }
    
    // Format: "HH:mm|30minPrice|refPrice ( change)|status|refM1|M1Old|M1New"
    // Use 5 decimal places for all numeric values to match Java precision
    string entry = StringFormat("%s|%.5f|%s|%s|%.5f|%.5f|%.5f",
                                 timeStr, thirtyMinPrice, refPriceStr,
                                 status, g_referenceM1Power, oldM1, newM1);
    
    // Check for duplicates
    if(!HistoryEntryExists(timeStr))
    {
        ResizeHistory(g_historyCount + 1);
        SetHistoryEntry(g_historyCount, entry);
        g_historyCount++;
        
#ifdef ENABLE_DEBUG_LOGS
        Print("   History: ", entry);
#endif
        
        // Persist to file
        MqlDateTime dt;
        TimeToStruct(blockTime, dt);
        int dayOfYear = dt.day_of_year + 1;  // Convert from 0-based to 1-based
        if(!AppendBasePriceHistoryEntry(dt.year, dayOfYear, entry))
        {
#ifdef ENABLE_DEBUG_LOGS
            Print("   WARNING: Failed to persist history entry to file");
#endif
        }
    }
    else
    {
#ifdef ENABLE_DEBUG_LOGS
        Print("   Skipping duplicate history entry for block ", timeStr);
#endif
    }
}

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
    
    for(int i = 0; i < g_historyCount; i++)
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
    for(int i = 0; i < g_historyCount; i++)
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
//| PERFORMANCE: Get Cached Symbol State Index                       |
//| Called 50+ times/tick -> now ONE call per tick via caching.       |
//+------------------------------------------------------------------+
int GetCachedSymbolStateIndex()
{
    string sym = Symbol();
    
    if(_g_cachedStateIdx >= 0 && _g_cachedStateSymbol == sym &&
       _g_cachedStateIdx < g_symbolStateCount)
    {
        return _g_cachedStateIdx;
    }
    
    _g_cachedStateIdx = GetSymbolStateIndex();
    _g_cachedStateSymbol = sym;
    return _g_cachedStateIdx;
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
