//+------------------------------------------------------------------+
//|                                                    LogLevels.mqh |
//|                                  GOLD VERSION: Unified Logging   |
//|                                  Centralized Log Level Management|
//+------------------------------------------------------------------+
#property copyright "© Biotak - GOLD Version v3"
#property strict

#ifndef LOG_LEVELS_MQH
#define LOG_LEVELS_MQH

//+------------------------------------------------------------------+
//| Log Levels (Priority Order)                                      |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL {
    LOG_LEVEL_NONE = 0,      // No logging
    LOG_LEVEL_ERROR = 1,     // Only errors
    LOG_LEVEL_WARNING = 2,   // Errors + warnings
    LOG_LEVEL_INFO = 3,      // Errors + warnings + info
    LOG_LEVEL_DEBUG = 4      // All messages (verbose)
};

// Global log level setting
#ifdef ENABLE_DEBUG_LOGS
    static ENUM_LOG_LEVEL g_currentLogLevel = LOG_LEVEL_DEBUG;
#else
    static ENUM_LOG_LEVEL g_currentLogLevel = LOG_LEVEL_WARNING;
#endif

//+------------------------------------------------------------------+
//| Set Current Log Level                                            |
//+------------------------------------------------------------------+
void SetLogLevel(ENUM_LOG_LEVEL level) {
    g_currentLogLevel = level;
}

//+------------------------------------------------------------------+
//| Get Current Log Level                                            |
//+------------------------------------------------------------------+
ENUM_LOG_LEVEL GetLogLevel() {
    return g_currentLogLevel;
}

//+------------------------------------------------------------------+
//| Log Functions with Level Filtering                               |
//+------------------------------------------------------------------+

// Log Error (always shown unless LOG_LEVEL_NONE)
void LogError(string message) {
    if(g_currentLogLevel >= LOG_LEVEL_ERROR) {
        Print("❌ ERROR: ", message);
    }
}

// Log Warning
void LogWarning(string message) {
    if(g_currentLogLevel >= LOG_LEVEL_WARNING) {
        Print("⚠️ WARNING: ", message);
    }
}

// Log Info
void LogInfo(string message) {
    if(g_currentLogLevel >= LOG_LEVEL_INFO) {
        Print("ℹ️ INFO: ", message);
    }
}

// Log Debug (verbose)
void LogDebug(string message) {
    if(g_currentLogLevel >= LOG_LEVEL_DEBUG) {
        Print("🔍 DEBUG: ", message);
    }
}

#endif // LOG_LEVELS_MQH
