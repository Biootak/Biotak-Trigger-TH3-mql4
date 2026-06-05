  //+------------------------------------------------------------------+
//| BasePriceHistoryManager.mqh                                       |
//| Persistent storage for base price history                         |
//| Matches Java BasePriceHistoryManager.java implementation         |
//+------------------------------------------------------------------+
#property strict

// Constants for history file management
#define HISTORY_DIR ".biotak\\history\\"
#define HISTORY_FILE_PREFIX "base_price_history_"
#define HISTORY_FILE_EXT ".txt"
#define HISTORY_VERSION_FILE ".biotak\\history\\.version"
#define DEFAULT_DAYS_TO_KEEP 30
#define MAX_FILE_SIZE_KB 1024  // 1MB max file size for safety

//+------------------------------------------------------------------+
//| Debug logging helper - only prints in DEBUG build                |
//| NOTE: Use #ifdef ENABLE_DEBUG_LOGS directly for multi-arg logs   |
//+------------------------------------------------------------------+

// Helper function for history logging - checks HISTORY_LOG_ENABLED at runtime
// This allows variadic Print() calls while still being controlled by build mode
#ifdef ENABLE_DEBUG_LOGS
#define HISTORY_PRINT Print
#else
// Define as a macro that ignores arguments to ensure strings are stripped
// Note: This only works if HISTORY_PRINT is called like a function
// MQL4 doesn't fully support variadic macros in older versions, but if the compiler supports it:
// #define HISTORY_PRINT(msg, ...) 
// Since we can't rely on variadic macros, we use if(0) but ensuring string stripping is compiler dependent.
// The safest way for string stripping is to NOT include the code.
// But we can't easily replace variadic usage with #ifdef blocks everywhere.
// So we stick to if(0) Print but optimize the macro to be explicit.
#define HISTORY_PRINT if(0) Print
#endif

//+------------------------------------------------------------------+
//| Get history file path for a specific date and symbol             |
//| Format: .biotak/history/base_price_history_SYMBOL_YYYY_DDD.txt   |
//+------------------------------------------------------------------+
// GOLD FIX #9: Comprehensive filename sanitization
string SanitizeSymbolForFilename(const string symbol) {
    string safe = symbol;
    
    // Remove path traversal attempts
    StringReplace(safe, "..", "");
    StringReplace(safe, "/", "");
    StringReplace(safe, "\\", "");
    StringReplace(safe, ":", "");
    
    // Remove null bytes and control characters
    StringReplace(safe, "\0", "");
    StringReplace(safe, "\n", "");
    StringReplace(safe, "\r", "");
    StringReplace(safe, "\t", "");
    
    // Remove pipe and other dangerous characters
    StringReplace(safe, "|", "");
    StringReplace(safe, "<", "");
    StringReplace(safe, ">", "");
    StringReplace(safe, "\"", "");
    StringReplace(safe, "*", "");
    StringReplace(safe, "?", "");
    
    // Ensure not empty after sanitization
    if(StringLen(safe) == 0) {
        safe = "UNKNOWN";
    }
    
    return safe;
}

string GetHistoryFilePath(int year, int dayOfYear)
{
    // GOLD FIX #9: Use comprehensive sanitization
    string symbol = SanitizeSymbolForFilename(Symbol());
    
    // Format: base_price_history_EURUSD_2024_325.txt
    string filename = StringFormat("%s%s_%d_%03d%s", 
                                    HISTORY_FILE_PREFIX,
                                    symbol,
                                    year, 
                                    dayOfYear, 
                                    HISTORY_FILE_EXT);
    
    // Full path: .biotak/history/base_price_history_EURUSD_2024_325.txt
    string fullPath = HISTORY_DIR + filename;
    
    return fullPath;
}

//+------------------------------------------------------------------+
//| Load history for a specific date                                 |
//| Returns number of entries loaded                                 |
//| Includes retry logic and validation                              |
//+------------------------------------------------------------------+
int LoadBasePriceHistory(int year, int dayOfYear, string &history[])
{
    string filePath = GetHistoryFilePath(year, dayOfYear);
    
    // Retry logic for file locking (max 3 attempts with 100ms delay)
    int maxRetries = 3;
    int retryDelay = 100;
    
    // GOLD FIX #6: Declare fileHandle outside loop for proper cleanup
    int fileHandle = INVALID_HANDLE;
    bool fileOpened = false;
    
    for(int attempt = 0; attempt < maxRetries; attempt++)
    {
        // GOLD FIX #6: Enhanced file handle management with guaranteed cleanup
        fileHandle = FileOpen(filePath, FILE_READ | FILE_TXT | FILE_ANSI);
        fileOpened = (fileHandle != INVALID_HANDLE);
        
        if(!fileOpened)
        {
            int errorCode = GetLastError();
            
            // Check if file doesn't exist (normal for first run)
            if(errorCode == 4103 || errorCode == 5019)  // ERR_CANNOT_OPEN_FILE or file not found
            {
                if(attempt == 0)
                {
                    HISTORY_PRINT("[BasePriceHistoryManager] LoadHistory: No history file found for ", year, "/", dayOfYear);
                }
                ArrayResize(history, 0);
                return 0;
            }
            
            // File might be locked - retry
            if(attempt < maxRetries - 1)
            {
                HISTORY_PRINT("[BasePriceHistoryManager] LoadHistory: File locked (error ", errorCode, "), retrying...");
                Sleep(retryDelay);
                continue;
            }
            else
            {
                HISTORY_PRINT("[BasePriceHistoryManager] LoadHistory: ERROR - Failed to open file after ", maxRetries, " attempts");
                ArrayResize(history, 0);
                return 0;
            }
        }
        
        // Read all lines from file
        int count = 0;
        ArrayResize(history, 0);
        int emptyLines = 0;
        int invalidLines = 0;
        
        while(!FileIsEnding(fileHandle))
        {
            string line = FileReadString(fileHandle);
            
            // Trim whitespace
            line = StringTrimLeft(line);
            line = StringTrimRight(line);
            
            if(StringLen(line) == 0)
            {
                emptyLines++;
                continue;
            }
            
            // Basic validation: should contain at least one pipe character
            if(StringFind(line, "|") == -1)
            {
                invalidLines++;
                HISTORY_PRINT("[BasePriceHistoryManager] LoadHistory: WARNING - Invalid line format: ", line);
                continue;
            }
            
            ArrayResize(history, count + 1);
            history[count] = line;
            count++;
        }
        
        // CRITICAL: Guaranteed file handle cleanup
        if(fileHandle != INVALID_HANDLE) {
            FileClose(fileHandle);
            fileHandle = INVALID_HANDLE;
        }
        
        if(attempt > 0)
        {
            HISTORY_PRINT("[BasePriceHistoryManager] LoadHistory: Success after ", attempt + 1, " attempts");
        }
        
        HISTORY_PRINT("[BasePriceHistoryManager] LoadHistory: Loaded ", count, " valid entries from ", filePath);
        if(emptyLines > 0 || invalidLines > 0)
        {
            HISTORY_PRINT("[BasePriceHistoryManager] LoadHistory: Skipped ", emptyLines, " empty lines and ", invalidLines, " invalid lines");
        }
        
        return count;
    }
    
    // GOLD FIX #6: Ensure cleanup even on unexpected exit
    if(fileHandle != INVALID_HANDLE) {
        FileClose(fileHandle);
    }
    
    ArrayResize(history, 0);
    return 0;
}

//+------------------------------------------------------------------+
//| Save history for a specific date                                 |
//| Overwrites existing file with atomic write (temp file + rename)  |
//| Includes retry logic for file locking issues                     |
//+------------------------------------------------------------------+
bool SaveBasePriceHistory(int year, int dayOfYear, const string &history[], int count)
{
    string filePath = GetHistoryFilePath(year, dayOfYear);
    string tempPath = filePath + ".tmp";
    
    // Retry logic for file locking (max 3 attempts with 100ms delay)
    int maxRetries = 3;
    int retryDelay = 100;  // milliseconds
    
    for(int attempt = 0; attempt < maxRetries; attempt++)
    {
        // Step 1: Write to temporary file
        int fileHandle = FileOpen(tempPath, FILE_WRITE | FILE_TXT | FILE_ANSI);
        
        if(fileHandle == INVALID_HANDLE)
        {
            int errorCode = GetLastError();
            if(attempt < maxRetries - 1)
            {
                HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: Temp file locked (error ", errorCode, "), retrying...");
                Sleep(retryDelay);
                continue;
            }
            else
            {
                HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: ERROR - Failed to create temp file after ", maxRetries, " attempts");
                return false;
            }
        }
        
        // Write each entry as a line with error checking
        bool writeSuccess = true;
        for(int i = 0; i < count; i++)
        {
            // CRITICAL FIX: Check write operation success
            if(!FileWriteString(fileHandle, history[i] + "\n"))
            {
                int writeError = GetLastError();
                HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: ERROR - Write failed at entry ", i, ", error=", writeError);
                writeSuccess = false;
                break;
            }
        }
        
        FileClose(fileHandle);
        
        // If write failed, cleanup and retry
        if(!writeSuccess)
        {
            FileDelete(tempPath);
            if(attempt < maxRetries - 1)
            {
                HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: Write failed, retrying...");
                Sleep(retryDelay);
                continue;
            }
            else
            {
                HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: ERROR - Write failed after ", maxRetries, " attempts");
                return false;
            }
        }
        
        // Step 2: Delete old file if exists
        if(FileIsExist(filePath))
        {
            if(!FileDelete(filePath))
            {
                int deleteError = GetLastError();
                if(attempt < maxRetries - 1)
                {
                    HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: Failed to delete old file (error ", deleteError, "), retrying...");
                    FileDelete(tempPath);  // Clean up temp file
                    Sleep(retryDelay);
                    continue;
                }
                else
                {
                    HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: WARNING - Could not delete old file, keeping temp file");
                    // Continue anyway - temp file has the data
                }
            }
        }
        
        // Step 3: Rename temp file to final name
        if(!FileMove(tempPath, 0, filePath, FILE_REWRITE))
        {
            int moveError = GetLastError();
            if(attempt < maxRetries - 1)
            {
                HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: Failed to rename temp file (error ", moveError, "), retrying...");
                Sleep(retryDelay);
                continue;
            }
            else
            {
                HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: ERROR - Failed to rename temp file after ", maxRetries, " attempts");
                return false;
            }
        }
        
        // Success
        if(attempt > 0)
        {
            HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: Success after ", attempt + 1, " attempts");
        }
        
        HISTORY_PRINT("[BasePriceHistoryManager] SaveHistory: Saved ", count, " history entries to ", filePath);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Append a single entry to history file                            |
//| More efficient than loading, modifying, and saving entire list   |
//| Includes retry logic for file locking issues                     |
//+------------------------------------------------------------------+
bool AppendBasePriceHistoryEntry(int year, int dayOfYear, const string entry)
{
    string filePath = GetHistoryFilePath(year, dayOfYear);
    
    // Retry logic for file locking (max 3 attempts with 100ms delay)
    int maxRetries = 3;
    int retryDelay = 100;  // milliseconds
    
    for(int attempt = 0; attempt < maxRetries; attempt++)
    {
        // Open file for appending
        int fileHandle = FileOpen(filePath, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
        
        if(fileHandle != INVALID_HANDLE)
        {
            // Seek to end of file
            FileSeek(fileHandle, 0, SEEK_END);
            
            // Append entry with newline
            FileWriteString(fileHandle, entry + "\n");
            
            FileClose(fileHandle);
            
            if(attempt > 0)
            {
                HISTORY_PRINT("[BasePriceHistoryManager] AppendEntry: Success after ", attempt + 1, " attempts");
            }
            
            return true;
        }
        
        // File locked or error - wait and retry
        int errorCode = GetLastError();
        if(attempt < maxRetries - 1)
        {
            HISTORY_PRINT("[BasePriceHistoryManager] AppendEntry: File locked (error ", errorCode, "), retrying in ", retryDelay, "ms...");
            Sleep(retryDelay);
        }
        else
        {
            HISTORY_PRINT("[BasePriceHistoryManager] AppendEntry: ERROR - Failed after ", maxRetries, " attempts. Error: ", errorCode);
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Remove duplicate entries from history                            |
//| Keeps only the last entry for each time block                    |
//| Returns new count after deduplication                            |
//+------------------------------------------------------------------+
int DeduplicateHistory(string &history[], int count)
{
    if(count <= 1) return count;  // No duplicates possible
    
    // Use a simple approach: track unique time blocks
    string uniqueTimeBlocks[];
    string uniqueEntries[];
    int uniqueCount = 0;
    
    ArrayResize(uniqueTimeBlocks, 0);
    ArrayResize(uniqueEntries, 0);
    
    // Process each entry
    for(int i = 0; i < count; i++)
    {
        // Extract time block (first field before "|")
        int pipePos = StringFind(history[i], "|");
        if(pipePos == -1) continue;  // Invalid entry
        
        string timeBlock = StringSubstr(history[i], 0, pipePos);
        
        // Check if this time block already exists
        bool found = false;
        int foundIndex = -1;
        
        for(int j = 0; j < uniqueCount; j++)
        {
            if(uniqueTimeBlocks[j] == timeBlock)
            {
                found = true;
                foundIndex = j;
                break;
            }
        }
        
        if(found)
        {
            // Replace existing entry (last-wins strategy)
            uniqueEntries[foundIndex] = history[i];
        }
        else
        {
            // Add new entry
            ArrayResize(uniqueTimeBlocks, uniqueCount + 1);
            ArrayResize(uniqueEntries, uniqueCount + 1);
            uniqueTimeBlocks[uniqueCount] = timeBlock;
            uniqueEntries[uniqueCount] = history[i];
            uniqueCount++;
        }
    }
    
    // Check if duplicates were found
    int duplicatesRemoved = count - uniqueCount;
    if(duplicatesRemoved > 0)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] DeduplicateHistory: WARNING - Removed ", duplicatesRemoved, " duplicate entries");
    }
    
    // Copy unique entries back to history array
    ArrayResize(history, uniqueCount);
    for(int i = 0; i < uniqueCount; i++)
    {
        history[i] = uniqueEntries[i];
    }
    
    return uniqueCount;
}

//+------------------------------------------------------------------+
//| Verify file integrity and size                                   |
//| Returns true if file is valid, false otherwise                   |
//+------------------------------------------------------------------+
bool VerifyHistoryFileIntegrity(int year, int dayOfYear)
{
    string filePath = GetHistoryFilePath(year, dayOfYear);
    
    if(!FileIsExist(filePath))
    {
        return true;  // Non-existent file is not an error
    }
    
    // Check file size
    int fileHandle = FileOpen(filePath, FILE_READ | FILE_BIN);
    if(fileHandle == INVALID_HANDLE)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] VerifyIntegrity: Cannot open file for size check");
        return false;
    }
    
    int fileSize = (int)FileSize(fileHandle);
    FileClose(fileHandle);
    
    // Check if file is too large (possible corruption)
    if(fileSize > MAX_FILE_SIZE_KB * 1024)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] VerifyIntegrity: WARNING - File too large (", fileSize, " bytes), possible corruption");
        return false;
    }
    
    // Check if file is empty
    if(fileSize == 0)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] VerifyIntegrity: WARNING - File is empty");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Repair corrupted history file                                    |
//| Attempts to recover valid entries from corrupted file            |
//+------------------------------------------------------------------+
int RepairHistoryFile(int year, int dayOfYear)
{
    HISTORY_PRINT("[BasePriceHistoryManager] RepairHistoryFile: Attempting to repair file for ", year, "/", dayOfYear);
    
    string filePath = GetHistoryFilePath(year, dayOfYear);
    string backupPath = filePath + ".backup";
    
    // Create backup
    if(FileIsExist(filePath))
    {
        if(FileIsExist(backupPath))
        {
            FileDelete(backupPath);
        }
        
        if(!FileMove(filePath, 0, backupPath, 0))
        {
            HISTORY_PRINT("[BasePriceHistoryManager] RepairHistoryFile: ERROR - Cannot create backup");
            return -1;
        }
    }
    
    // Try to load from backup
    string history[];
    int count = 0;
    
    int fileHandle = FileOpen(backupPath, FILE_READ | FILE_TXT | FILE_ANSI);
    if(fileHandle == INVALID_HANDLE)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] RepairHistoryFile: ERROR - Cannot open backup file");
        return -1;
    }
    
    // Read and validate each line
    while(!FileIsEnding(fileHandle))
    {
        string line = FileReadString(fileHandle);
        line = StringTrimLeft(line);
        line = StringTrimRight(line);
        
        if(StringLen(line) > 0 && StringFind(line, "|") > 0)
        {
            ArrayResize(history, count + 1);
            history[count] = line;
            count++;
        }
    }
    
    FileClose(fileHandle);
    
    // Save repaired history
    if(count > 0)
    {
        bool saved = SaveBasePriceHistory(year, dayOfYear, history, count);
        if(saved)
        {
            HISTORY_PRINT("[BasePriceHistoryManager] RepairHistoryFile: Successfully recovered ", count, " entries");
            return count;
        }
    }
    
    HISTORY_PRINT("[BasePriceHistoryManager] RepairHistoryFile: ERROR - Could not recover any entries");
    return -1;
}

//+------------------------------------------------------------------+
//| Migrate old format entries to new format                         |
//| Old: "HH:mm|price|status|oldM1|newM1" (5 fields)                 |
//| New: "HH:mm|30minPrice|refPrice|status|oldM1|newM1" (6 fields)   |
//| Returns number of entries migrated                               |
//+------------------------------------------------------------------+
int MigrateToNewFormat(string &history[], int count)
{
    int migratedCount = 0;
    
    for(int i = 0; i < count; i++)
    {
        // Count fields by counting pipe characters
        int fieldCount = 1;  // Start with 1 (first field before any pipe)
        for(int j = 0; j < StringLen(history[i]); j++)
        {
            if(StringGetCharacter(history[i], j) == '|')
            {
                fieldCount++;
            }
        }
        
        // Check if already in new format (6+ fields)
        if(fieldCount >= 6)
        {
            continue;  // Already in new format
        }
        
        // Old format with 5 fields: time|price|status|oldM1|newM1
        if(fieldCount == 5)
        {
            // Split entry into parts
            string parts[];
            int partCount = StringSplit(history[i], '|', parts);
            
            if(partCount >= 5)
            {
                string time = parts[0];
                string price = parts[1];
                string status = parts[2];
                string oldM1 = parts[3];
                string newM1 = parts[4];
                
                // For old format, both 30minPrice and refPrice are the same
                string newEntry = time + "|" + price + "|" + price + "|" + status + "|" + oldM1 + "|" + newM1;
                history[i] = newEntry;
                migratedCount++;
            }
        }
    }
    
    if(migratedCount > 0)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] MigrateToNewFormat: Migrated ", migratedCount, " entries from old format to new format");
    }
    
    return migratedCount;
}

//+------------------------------------------------------------------+
//| Convert year and day-of-year to datetime                         |
//| More accurate than using StructToTime with day_of_year           |
//+------------------------------------------------------------------+
datetime ConvertYearDayToDateTime(int year, int dayOfYear)
{
    // Create datetime for Jan 1 of the year
    MqlDateTime dt;
    dt.year = year;
    dt.mon = 1;
    dt.day = 1;
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    
    datetime jan1 = StructToTime(dt);
    
    // Add days (dayOfYear is 1-based, so subtract 1)
    datetime result = jan1 + ((dayOfYear - 1) * 24 * 60 * 60);
    
    return result;
}

//+------------------------------------------------------------------+
//| Delete old history files (older than specified days)             |
//| Improved with better date parsing and symbol filtering           |
//+------------------------------------------------------------------+
void CleanupOldHistory(int daysToKeep = DEFAULT_DAYS_TO_KEEP)
{
    // Calculate cutoff time (use GMT for consistency)
    datetime cutoffTime = TimeGMT() - (daysToKeep * 24 * 60 * 60);
    
    // Get current symbol for filtering
    string currentSymbol = Symbol();
    StringReplace(currentSymbol, "/", "");
    StringReplace(currentSymbol, "\\", "");
    StringReplace(currentSymbol, ":", "");
    
    // Search for history files for current symbol only
    string searchPattern = HISTORY_DIR + HISTORY_FILE_PREFIX + currentSymbol + "_*" + HISTORY_FILE_EXT;
    string filename;
    int deletedCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    
    HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: Searching for files older than ", daysToKeep, " days...");
    HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: Pattern: ", searchPattern);
    
    // Find first file
    long searchHandle = FileFindFirst(searchPattern, filename);
    
    if(searchHandle == INVALID_HANDLE)
    {
        // No files found - this is normal
        HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: No history files found for ", currentSymbol);
        return;
    }
    
    // Check each file
    do
    {
        string fullPath = HISTORY_DIR + filename;
        
        // Parse filename: base_price_history_SYMBOL_YYYY_DDD.txt
        // Example: base_price_history_EURUSD_2024_325.txt
        
        // Find last two underscores (before year and day)
        int lastUnderscore = StringFind(filename, "_", StringLen(filename) - 8);  // _DDD.txt = 8 chars
        int secondLastUnderscore = StringFind(filename, "_", lastUnderscore - 5); // _YYYY = 5 chars
        
        if(lastUnderscore > 0 && secondLastUnderscore > 0)
        {
            // Extract year and day
            string yearStr = StringSubstr(filename, secondLastUnderscore + 1, lastUnderscore - secondLastUnderscore - 1);
            string dayStr = StringSubstr(filename, lastUnderscore + 1, 3);
            
            int fileYear = (int)StringToInteger(yearStr);
            int fileDay = (int)StringToInteger(dayStr);
            
            // Validate parsed values
            if(fileYear < 2020 || fileYear > 2100 || fileDay < 1 || fileDay > 366)
            {
                HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: WARNING - Invalid date in filename: ", filename);
                errorCount++;
                continue;
            }
            
            // Convert to datetime
            datetime fileTime = ConvertYearDayToDateTime(fileYear, fileDay);
            
            // Check if file is older than cutoff
            if(fileTime < cutoffTime)
            {
                HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: Deleting old file: ", filename, 
                      " (", TimeToString(fileTime, TIME_DATE), ")");
                
                // Try to delete with retry logic
                bool deleted = false;
                for(int retry = 0; retry < 3; retry++)
                {
                    if(FileDelete(fullPath))
                    {
                        deleted = true;
                        deletedCount++;
                        break;
                    }
                    else
                    {
                        int errorCode = GetLastError();
                        if(retry < 2)
                        {
                            HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: Delete failed (error ", errorCode, "), retrying...");
                            Sleep(100);
                        }
                        else
                        {
                            HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: WARNING - Failed to delete: ", fullPath, " (error ", errorCode, ")");
                            errorCount++;
                        }
                    }
                }
            }
            else
            {
                skippedCount++;
            }
        }
        else
        {
            HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: WARNING - Could not parse filename: ", filename);
            errorCount++;
        }
    }
    while(FileFindNext(searchHandle, filename));
    
    FileFindClose(searchHandle);
    
    // Summary
    HISTORY_PRINT("[BasePriceHistoryManager] CleanupOldHistory: Complete - Deleted: ", deletedCount, 
          ", Kept: ", skippedCount, ", Errors: ", errorCount);
}

//+------------------------------------------------------------------+
//| Clean up temporary and backup files                              |
//| Removes .tmp and .backup files that may be left over             |
//+------------------------------------------------------------------+
void CleanupTemporaryFiles()
{
    string currentSymbol = Symbol();
    StringReplace(currentSymbol, "/", "");
    StringReplace(currentSymbol, "\\", "");
    StringReplace(currentSymbol, ":", "");
    
    // Search for temp files
    string searchPattern = HISTORY_DIR + HISTORY_FILE_PREFIX + currentSymbol + "_*.tmp";
    string filename;
    int deletedCount = 0;
    
    long searchHandle = FileFindFirst(searchPattern, filename);
    
    if(searchHandle != INVALID_HANDLE)
    {
        do
        {
            string fullPath = HISTORY_DIR + filename;
            if(FileDelete(fullPath))
            {
                deletedCount++;
                HISTORY_PRINT("[BasePriceHistoryManager] CleanupTemporaryFiles: Deleted temp file: ", filename);
            }
        }
        while(FileFindNext(searchHandle, filename));
        
        FileFindClose(searchHandle);
    }
    
    // Search for backup files
    searchPattern = HISTORY_DIR + HISTORY_FILE_PREFIX + currentSymbol + "_*.backup";
    searchHandle = FileFindFirst(searchPattern, filename);
    
    if(searchHandle != INVALID_HANDLE)
    {
        do
        {
            string fullPath = HISTORY_DIR + filename;
            if(FileDelete(fullPath))
            {
                deletedCount++;
                HISTORY_PRINT("[BasePriceHistoryManager] CleanupTemporaryFiles: Deleted backup file: ", filename);
            }
        }
        while(FileFindNext(searchHandle, filename));
        
        FileFindClose(searchHandle);
    }
    
    if(deletedCount > 0)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] CleanupTemporaryFiles: Cleaned up ", deletedCount, " temporary files");
    }
}


//+------------------------------------------------------------------+
//| Check and update history format version                          |
//| Returns true if version is current, false if cleanup needed      |
//+------------------------------------------------------------------+
bool CheckHistoryFormatVersion(int currentVersion)
{
    int fileHandle = FileOpen(HISTORY_VERSION_FILE, FILE_READ | FILE_TXT | FILE_ANSI);
    int storedVersion = 0;
    
    if(fileHandle != INVALID_HANDLE)
    {
        if(!FileIsEnding(fileHandle))
        {
            string versionStr = FileReadString(fileHandle);
            storedVersion = (int)StringToInteger(versionStr);
        }
        FileClose(fileHandle);
    }
    
    // If version doesn't match, cleanup is needed
    if(storedVersion != currentVersion)
    {
        HISTORY_PRINT("[BasePriceHistoryManager] History format version mismatch: stored=", storedVersion, ", current=", currentVersion);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update history format version file                               |
//+------------------------------------------------------------------+
void UpdateHistoryFormatVersion(int currentVersion)
{
    int fileHandle = FileOpen(HISTORY_VERSION_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
    
    if(fileHandle != INVALID_HANDLE)
    {
        FileWriteString(fileHandle, IntegerToString(currentVersion));
        FileClose(fileHandle);
        HISTORY_PRINT("[BasePriceHistoryManager] Updated history format version to: ", currentVersion);
    }
    else
    {
        HISTORY_PRINT("[BasePriceHistoryManager] ERROR: Failed to write version file");
    }
}

//+------------------------------------------------------------------+
//| Delete all history files for current symbol                      |
//| Used when format version changes                                 |
//+------------------------------------------------------------------+
void DeleteAllHistoryFiles()
{
    string currentSymbol = Symbol();
    StringReplace(currentSymbol, "/", "");
    StringReplace(currentSymbol, "\\", "");
    StringReplace(currentSymbol, ":", "");
    
    string searchPattern = HISTORY_DIR + HISTORY_FILE_PREFIX + currentSymbol + "_*" + HISTORY_FILE_EXT;
    string filename;
    int deletedCount = 0;
    
    HISTORY_PRINT("[BasePriceHistoryManager] Deleting all history files due to format version change...");
    
    long searchHandle = FileFindFirst(searchPattern, filename);
    
    if(searchHandle != INVALID_HANDLE)
    {
        do
        {
            string fullPath = HISTORY_DIR + filename;
            if(FileDelete(fullPath))
            {
                deletedCount++;
                HISTORY_PRINT("[BasePriceHistoryManager] Deleted: ", filename);
            }
        }
        while(FileFindNext(searchHandle, filename));
        
        FileFindClose(searchHandle);
    }
    
    HISTORY_PRINT("[BasePriceHistoryManager] Deleted ", deletedCount, " history files");
}
