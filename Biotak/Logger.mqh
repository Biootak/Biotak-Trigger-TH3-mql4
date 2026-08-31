  #ifndef LOGGER_MQH
#define LOGGER_MQH

#property strict

//+------------------------------------------------------------------+
//| Unified Professional Logger for Biotak Trigger TH3               |
//|                                                                  |
//| Features:                                                        |
//| - 6 log levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL          |
//| - Compile-time elimination of TRACE/DEBUG in production          |
//| - Runtime level filtering via input parameter                    |
//| - Rate-limiting to prevent log spam (per-category throttle)      |
//| - Automatic function name + line number in debug builds          |
//| - Category tagging for easy filtering in Experts log             |
//| - Backward-compatible with existing macro system                 |
//+------------------------------------------------------------------+

//--- Log Level Enum (available as input parameter)
enum ENUM_LOG_LEVEL
{
    LOG_LEVEL_TRACE  = 0,  // TRACE - Most verbose (hot-path details)
    LOG_LEVEL_DEBUG  = 1,  // DEBUG - Development diagnostics
    LOG_LEVEL_INFO   = 2,  // INFO  - Important state changes
    LOG_LEVEL_WARN   = 3,  // WARN  - Potential issues
    LOG_LEVEL_ERROR  = 4,  // ERROR - Recoverable errors
    LOG_LEVEL_FATAL  = 5,  // FATAL - Unrecoverable errors
    LOG_LEVEL_OFF    = 6   // OFF   - Disable all logging
};

//--- Log Category Enum (for filtering by subsystem)
enum ENUM_LOG_CATEGORY
{
    LOG_CAT_GENERAL  = 0,
    LOG_CAT_ATR      = 1,
    LOG_CAT_TH       = 2,
    LOG_CAT_LABELS   = 3,
    LOG_CAT_LINES    = 4,
    LOG_CAT_KEYS     = 5,
    LOG_CAT_ZONES    = 6,
    LOG_CAT_PERF     = 7,
    LOG_CAT_SYNC     = 8,
    LOG_CAT_DRAW     = 9,
    LOG_CAT_DATA     = 10,
    LOG_CAT_PIN      = 11,   // Custom Price
    LOG_CAT_TH3      = 12,   // TH3 Tool
    LOG_CAT_ALERT    = 13,
    LOG_CAT_INIT     = 14,
    LOG_CAT_CLEAN    = 15
};

//--- Rate-limiting constants
#define LOG_RATE_LIMIT_SLOTS   32
#define LOG_RATE_LIMIT_MS     1000   // Min interval between identical logs (ms)

//--- Rate-limiting state
struct SLogRateSlot
{
    uint   lastLogTime;
    string lastKey;       // category + level + truncated message hash
    int    suppressedCount;
    bool   used;
};

static SLogRateSlot g_logRateSlots[LOG_RATE_LIMIT_SLOTS];
static bool g_logRateInitialized = false;

//+------------------------------------------------------------------+
//| Initialize rate-limiter slots                                    |
//+------------------------------------------------------------------+
void LogRateInit()
{
    if(g_logRateInitialized) return;
    for(int i = 0; i < LOG_RATE_LIMIT_SLOTS; i++)
    {
        g_logRateSlots[i].lastLogTime = 0;
        g_logRateSlots[i].lastKey = "";
        g_logRateSlots[i].suppressedCount = 0;
        g_logRateSlots[i].used = false;
    }
    g_logRateInitialized = true;
}

//+------------------------------------------------------------------+
//| Check if a log message should be rate-limited                    |
//| Returns true if message should be PRINTED, false if suppressed   |
//+------------------------------------------------------------------+
bool LogRateCheck(const string rateKey)
{
    LogRateInit();
    uint now = GetTickCount();
    
    // Find existing slot or oldest unused slot
    int existingSlot = -1;
    int oldestSlot = 0;
    uint oldestTime = UINT_MAX;
    
    for(int i = 0; i < LOG_RATE_LIMIT_SLOTS; i++)
    {
        if(g_logRateSlots[i].used && g_logRateSlots[i].lastKey == rateKey)
        {
            existingSlot = i;
            break;
        }
        if(!g_logRateSlots[i].used || g_logRateSlots[i].lastLogTime < oldestTime)
        {
            oldestTime = g_logRateSlots[i].used ? g_logRateSlots[i].lastLogTime : 0;
            oldestSlot = i;
        }
    }
    
    if(existingSlot >= 0)
    {
        // Existing: check if enough time passed
        uint elapsed = now - g_logRateSlots[existingSlot].lastLogTime;
        if(elapsed < LOG_RATE_LIMIT_MS)
        {
            g_logRateSlots[existingSlot].suppressedCount++;
            return false;  // Suppress
        }
        // Enough time passed - allow and reset
        g_logRateSlots[existingSlot].lastLogTime = now;
        g_logRateSlots[existingSlot].suppressedCount = 0;
        return true;
    }
    
    // New entry: use oldest slot
    g_logRateSlots[oldestSlot].used = true;
    g_logRateSlots[oldestSlot].lastKey = rateKey;
    g_logRateSlots[oldestSlot].lastLogTime = now;
    g_logRateSlots[oldestSlot].suppressedCount = 0;
    return true;
}

//+------------------------------------------------------------------+
//| Category name lookup                                             |
//+------------------------------------------------------------------+
string LogCategoryName(const ENUM_LOG_CATEGORY cat)
{
    switch(cat)
    {
        case LOG_CAT_GENERAL: return "GEN";
        case LOG_CAT_ATR:     return "ATR";
        case LOG_CAT_TH:      return "TH";
        case LOG_CAT_LABELS:  return "LBL";
        case LOG_CAT_LINES:   return "LINE";
        case LOG_CAT_KEYS:    return "KEY";
        case LOG_CAT_ZONES:   return "ZONE";
        case LOG_CAT_PERF:    return "PERF";
        case LOG_CAT_SYNC:    return "SYNC";
        case LOG_CAT_DRAW:    return "DRAW";
        case LOG_CAT_DATA:    return "DATA";
        case LOG_CAT_PIN:     return "PIN";
        case LOG_CAT_TH3:     return "TH3";
        case LOG_CAT_ALERT:   return "ALRT";
        case LOG_CAT_INIT:    return "INIT";
        case LOG_CAT_CLEAN:   return "CLN";
        default:              return "???";
    }
}

//+------------------------------------------------------------------+
//| Level name lookup                                                |
//+------------------------------------------------------------------+
string LogLevelName(const ENUM_LOG_LEVEL level)
{
    switch(level)
    {
        case LOG_LEVEL_TRACE: return "TRACE";
        case LOG_LEVEL_DEBUG: return "DEBUG";
        case LOG_LEVEL_INFO:  return "INFO";
        case LOG_LEVEL_WARN:  return "WARN";
        case LOG_LEVEL_ERROR: return "ERROR";
        case LOG_LEVEL_FATAL: return "FATAL";
        default:              return "?????";
    }
}

//+------------------------------------------------------------------+
//| Core log function - all macros funnel through this               |
//+------------------------------------------------------------------+
void LogMessage(const ENUM_LOG_LEVEL level,
                const ENUM_LOG_CATEGORY category,
                const string message,
                const string funcName = "",
                const int lineNum = 0)
{
    // Build rate-limit key from category + level
    string rateKey = StringFormat("%d_%d_%s", (int)category, (int)level, StringSubstr(message, 0, 40));
    
    // Rate-limit TRACE and DEBUG levels (they can be very chatty)
    if(level <= LOG_LEVEL_DEBUG)
    {
        if(!LogRateCheck(rateKey)) return;
    }
    
    // Format: [LEVEL][CAT] message  or  [LEVEL][CAT] FuncName:Line | message
    string prefix = StringFormat("[%s][%s] ", LogLevelName(level), LogCategoryName(category));
    
    string location = "";
    if(funcName != "" && lineNum > 0)
        location = StringFormat("%s:%d | ", funcName, lineNum);
    else if(funcName != "")
        location = funcName + " | ";
    
    Print(prefix, location, message);
    
    // FATAL: Also trigger alert for critical issues
    if(level == LOG_LEVEL_FATAL)
    {
        Alert("FATAL: ", message);
    }
}

//+------------------------------------------------------------------+
//| Convenience overloads with 1-4 extra parameters                  |
//+------------------------------------------------------------------+
void LogMessageP1(const ENUM_LOG_LEVEL level, const ENUM_LOG_CATEGORY category,
                  const string msg, const string p1,
                  const string funcName = "", const int lineNum = 0)
{
    LogMessage(level, category, msg + p1, funcName, lineNum);
}

void LogMessageP2(const ENUM_LOG_LEVEL level, const ENUM_LOG_CATEGORY category,
                  const string msg, const string p1, const string p2,
                  const string funcName = "", const int lineNum = 0)
{
    LogMessage(level, category, msg + p1 + p2, funcName, lineNum);
}

void LogMessageP3(const ENUM_LOG_LEVEL level, const ENUM_LOG_CATEGORY category,
                  const string msg, const string p1, const string p2, const string p3,
                  const string funcName = "", const int lineNum = 0)
{
    LogMessage(level, category, msg + p1 + p2 + p3, funcName, lineNum);
}

void LogMessageP4(const ENUM_LOG_LEVEL level, const ENUM_LOG_CATEGORY category,
                  const string msg, const string p1, const string p2, const string p3, const string p4,
                  const string funcName = "", const int lineNum = 0)
{
    LogMessage(level, category, msg + p1 + p2 + p3 + p4, funcName, lineNum);
}

//+------------------------------------------------------------------+
//| MACRO SYSTEM                                                     |
//|                                                                  |
//| In DEBUG_BUILD: All levels active, with __FUNCTION__ + __LINE__  |
//| In PRODUCTION:  TRACE/DEBUG are compiled out completely           |
//|                 INFO+ are active with runtime level check         |
//+------------------------------------------------------------------+

// --- Helper: Runtime level gate (for INFO+ in production)
// This is set from input parameter in OnInit via LoggerSetLevel()
static ENUM_LOG_LEVEL g_runtimeLogLevel = LOG_LEVEL_INFO;

void LoggerSetLevel(const ENUM_LOG_LEVEL level) { g_runtimeLogLevel = level; }
ENUM_LOG_LEVEL LoggerGetLevel() { return g_runtimeLogLevel; }

//+------------------------------------------------------------------+
//| Compile-time macros                                              |
//+------------------------------------------------------------------+

#ifdef DEBUG_BUILD

    // TRACE
    #define LOG_T(cat, msg)              LogMessage(LOG_LEVEL_TRACE, cat, msg, __FUNCTION__, __LINE__)
    #define LOG_TP1(cat, msg, p1)        LogMessageP1(LOG_LEVEL_TRACE, cat, msg, p1, __FUNCTION__, __LINE__)
    #define LOG_TP2(cat, msg, p1, p2)    LogMessageP2(LOG_LEVEL_TRACE, cat, msg, p1, p2, __FUNCTION__, __LINE__)
    #define LOG_TP3(cat, msg, p1, p2, p3) LogMessageP3(LOG_LEVEL_TRACE, cat, msg, p1, p2, p3, __FUNCTION__, __LINE__)
    
    // DEBUG
    #define LOG_D(cat, msg)              LogMessage(LOG_LEVEL_DEBUG, cat, msg, __FUNCTION__, __LINE__)
    #define LOG_DP1(cat, msg, p1)        LogMessageP1(LOG_LEVEL_DEBUG, cat, msg, p1, __FUNCTION__, __LINE__)
    #define LOG_DP2(cat, msg, p1, p2)    LogMessageP2(LOG_LEVEL_DEBUG, cat, msg, p1, p2, __FUNCTION__, __LINE__)
    #define LOG_DP3(cat, msg, p1, p2, p3) LogMessageP3(LOG_LEVEL_DEBUG, cat, msg, p1, p2, p3, __FUNCTION__, __LINE__)

    // INFO
    #define LOG_I(cat, msg)              LogMessage(LOG_LEVEL_INFO, cat, msg, __FUNCTION__, __LINE__)
    #define LOG_IP1(cat, msg, p1)        LogMessageP1(LOG_LEVEL_INFO, cat, msg, p1, __FUNCTION__, __LINE__)
    #define LOG_IP2(cat, msg, p1, p2)    LogMessageP2(LOG_LEVEL_INFO, cat, msg, p1, p2, __FUNCTION__, __LINE__)
    #define LOG_IP3(cat, msg, p1, p2, p3) LogMessageP3(LOG_LEVEL_INFO, cat, msg, p1, p2, p3, __FUNCTION__, __LINE__)

    // WARN
    #define LOG_W(cat, msg)              LogMessage(LOG_LEVEL_WARN, cat, msg, __FUNCTION__, __LINE__)
    #define LOG_WP1(cat, msg, p1)        LogMessageP1(LOG_LEVEL_WARN, cat, msg, p1, __FUNCTION__, __LINE__)
    #define LOG_WP2(cat, msg, p1, p2)    LogMessageP2(LOG_LEVEL_WARN, cat, msg, p1, p2, __FUNCTION__, __LINE__)

    // ERROR
    #define LOG_E(cat, msg)              LogMessage(LOG_LEVEL_ERROR, cat, msg, __FUNCTION__, __LINE__)
    #define LOG_EP1(cat, msg, p1)        LogMessageP1(LOG_LEVEL_ERROR, cat, msg, p1, __FUNCTION__, __LINE__)
    #define LOG_EP2(cat, msg, p1, p2)    LogMessageP2(LOG_LEVEL_ERROR, cat, msg, p1, p2, __FUNCTION__, __LINE__)
    #define LOG_EP3(cat, msg, p1, p2, p3) LogMessageP3(LOG_LEVEL_ERROR, cat, msg, p1, p2, p3, __FUNCTION__, __LINE__)

    // FATAL
    #define LOG_F(cat, msg)              LogMessage(LOG_LEVEL_FATAL, cat, msg, __FUNCTION__, __LINE__)
    #define LOG_FP1(cat, msg, p1)        LogMessageP1(LOG_LEVEL_FATAL, cat, msg, p1, __FUNCTION__, __LINE__)

#else // PRODUCTION BUILD

    // TRACE & DEBUG - completely compiled out (zero overhead)
    #define LOG_T(cat, msg)
    #define LOG_TP1(cat, msg, p1)
    #define LOG_TP2(cat, msg, p1, p2)
    #define LOG_TP3(cat, msg, p1, p2, p3)
    
    #define LOG_D(cat, msg)
    #define LOG_DP1(cat, msg, p1)
    #define LOG_DP2(cat, msg, p1, p2)
    #define LOG_DP3(cat, msg, p1, p2, p3)

    // INFO+ - active in production with runtime level check
    #define LOG_I(cat, msg)              if(g_runtimeLogLevel <= LOG_LEVEL_INFO) LogMessage(LOG_LEVEL_INFO, cat, msg)
    #define LOG_IP1(cat, msg, p1)        if(g_runtimeLogLevel <= LOG_LEVEL_INFO) LogMessageP1(LOG_LEVEL_INFO, cat, msg, p1)
    #define LOG_IP2(cat, msg, p1, p2)    if(g_runtimeLogLevel <= LOG_LEVEL_INFO) LogMessageP2(LOG_LEVEL_INFO, cat, msg, p1, p2)
    #define LOG_IP3(cat, msg, p1, p2, p3) if(g_runtimeLogLevel <= LOG_LEVEL_INFO) LogMessageP3(LOG_LEVEL_INFO, cat, msg, p1, p2, p3)

    #define LOG_W(cat, msg)              if(g_runtimeLogLevel <= LOG_LEVEL_WARN) LogMessage(LOG_LEVEL_WARN, cat, msg)
    #define LOG_WP1(cat, msg, p1)        if(g_runtimeLogLevel <= LOG_LEVEL_WARN) LogMessageP1(LOG_LEVEL_WARN, cat, msg, p1)
    #define LOG_WP2(cat, msg, p1, p2)    if(g_runtimeLogLevel <= LOG_LEVEL_WARN) LogMessageP2(LOG_LEVEL_WARN, cat, msg, p1, p2)

    #define LOG_E(cat, msg)              if(g_runtimeLogLevel <= LOG_LEVEL_ERROR) LogMessage(LOG_LEVEL_ERROR, cat, msg)
    #define LOG_EP1(cat, msg, p1)        if(g_runtimeLogLevel <= LOG_LEVEL_ERROR) LogMessageP1(LOG_LEVEL_ERROR, cat, msg, p1)
    #define LOG_EP2(cat, msg, p1, p2)    if(g_runtimeLogLevel <= LOG_LEVEL_ERROR) LogMessageP2(LOG_LEVEL_ERROR, cat, msg, p1, p2)
    #define LOG_EP3(cat, msg, p1, p2, p3) if(g_runtimeLogLevel <= LOG_LEVEL_ERROR) LogMessageP3(LOG_LEVEL_ERROR, cat, msg, p1, p2, p3)

    #define LOG_F(cat, msg)              LogMessage(LOG_LEVEL_FATAL, cat, msg)
    #define LOG_FP1(cat, msg, p1)        LogMessageP1(LOG_LEVEL_FATAL, cat, msg, p1)

#endif // DEBUG_BUILD

//+------------------------------------------------------------------+
//| Backward-compatibility bridge macros                             |
//| Maps old DEBUG_PRINT/ERROR_PRINT/WARN_PRINT to new logger       |
//+------------------------------------------------------------------+

#ifdef _LOGGER_OVERRIDE_LEGACY
    #undef DEBUG_PRINT
    #undef DEBUG_PRINTF
    #undef DEBUG_PRINTF2
    #undef DEBUG_PRINTF3
    #undef DEBUG_PRINTF4
    #undef DEBUG_PRINTF5
    #undef ATR_PRINT
    #undef ATR_PRINTF
    #undef ATR_PRINTF2
    #undef ATR_PRINTF3
    #undef ERROR_PRINT
    #undef WARN_PRINT

    #define DEBUG_PRINT(msg)                   LOG_D(LOG_CAT_GENERAL, msg)
    #define DEBUG_PRINTF(msg, p1)              LOG_DP1(LOG_CAT_GENERAL, msg, p1)
    #define DEBUG_PRINTF2(msg, p1, p2)         LOG_DP2(LOG_CAT_GENERAL, msg, p1, p2)
    #define DEBUG_PRINTF3(msg, p1, p2, p3)     LOG_DP3(LOG_CAT_GENERAL, msg, p1, p2, p3)
    #define DEBUG_PRINTF4(msg, p1, p2, p3, p4) LOG_D(LOG_CAT_GENERAL, msg)
    #define DEBUG_PRINTF5(msg, p1, p2, p3, p4, p5) LOG_D(LOG_CAT_GENERAL, msg)
    #define ATR_PRINT(msg)                     LOG_D(LOG_CAT_ATR, msg)
    #define ATR_PRINTF(msg, p1)                LOG_DP1(LOG_CAT_ATR, msg, p1)
    #define ATR_PRINTF2(msg, p1, p2)           LOG_DP2(LOG_CAT_ATR, msg, p1, p2)
    #define ATR_PRINTF3(msg, p1, p2, p3)       LOG_DP3(LOG_CAT_ATR, msg, p1, p2, p3)
    #define ERROR_PRINT(msg)                   LOG_E(LOG_CAT_GENERAL, msg)
    #define WARN_PRINT(msg)                    LOG_W(LOG_CAT_GENERAL, msg)
#endif // _LOGGER_OVERRIDE_LEGACY

//+------------------------------------------------------------------+
//| Print-Compatible Gate Macros                                     |
//|                                                                  |
//| For blocks with non-string Print() arguments where LOG_D etc.    |
//| cannot be used due to MQL4 lacking variadic macros.              |
//| Provides runtime level filtering + compile-time elimination.     |
//+------------------------------------------------------------------+
#ifdef ENABLE_DEBUG_LOGS
    #define _LOG_GATE_D if(g_runtimeLogLevel <= LOG_LEVEL_DEBUG)
    #define _LOG_GATE_I if(g_runtimeLogLevel <= LOG_LEVEL_INFO)
#else
    #define _LOG_GATE_D if(false)
    #define _LOG_GATE_I if(false)
#endif
// WARN and ERROR gates are always active (never eliminated)
#define _LOG_GATE_W if(g_runtimeLogLevel <= LOG_LEVEL_WARN)
#define _LOG_GATE_E if(g_runtimeLogLevel <= LOG_LEVEL_ERROR)

#endif // LOGGER_MQH
