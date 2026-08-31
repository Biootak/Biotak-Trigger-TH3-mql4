  //+------------------------------------------------------------------+
//|                                      EnhancedLogging.mqh         |
//|                     Professional Logging System                  |
//|                                                                   |
//|                                                                  |
//| FEATURES:                                                        |
//| - Multiple log levels (ERROR, WARN, INFO, DEBUG, DIAGNOSTIC)    |
//| - Automatic context (symbol, time, timeframe)                   |
//| - Module-based filtering                                        |
//| - Performance-optimized (minimal overhead)                      |
//| - Thread-safe (MT4 single-threaded, but future-proof)          |
//+------------------------------------------------------------------+
#ifndef ENHANCED_LOGGING_MQH
#define ENHANCED_LOGGING_MQH
#property strict

//                                                                
// LOG LEVELS
//         
//                                                                
enum ENUM_LOG_LEVEL {
    LOG_LEVEL_ERROR = 0,        //          
    LOG_LEVEL_WARNING = 1,      //       +        
    LOG_LEVEL_INFO = 2,         //       +         +        
    LOG_LEVEL_DEBUG = 3,        //     +      
    LOG_LEVEL_DIAGNOSTIC = 4    //     +        (         )
};

//                                                                
// GLOBAL CONFIGURATION
//               
//                                                                
static ENUM_LOG_LEVEL g_currentLogLevel = LOG_LEVEL_INFO;
static bool g_logTimestamp = true;
static bool g_logSymbol = true;
static bool g_logTimeframe = true;
static bool g_logThreadId = false;  //           

// Module filtering (empty = all modules)
static string g_enabledModules = "";  //     : "ZoneFactory,BasePriceManager"

//                                                                
// LOG STATISTICS
//         
//                                                                
struct LogStatistics {
    int errorCount;
    int warningCount;
    int infoCount;
    int debugCount;
    int diagnosticCount;
    datetime lastLogTime;
};

static LogStatistics g_logStats;

//                                                                
// CONFIGURATION FUNCTIONS
//              
//                                                                

//+------------------------------------------------------------------+
//| Set Log Level                                                    |
//|                                                                  |
//+------------------------------------------------------------------+
void SetLogLevel(ENUM_LOG_LEVEL level)
{
    g_currentLogLevel = level;
    
    string levelName = "";
    switch(level) {
        case LOG_LEVEL_ERROR:      levelName = "ERROR"; break;
        case LOG_LEVEL_WARNING:    levelName = "WARNING"; break;
        case LOG_LEVEL_INFO:       levelName = "INFO"; break;
        case LOG_LEVEL_DEBUG:      levelName = "DEBUG"; break;
        case LOG_LEVEL_DIAGNOSTIC: levelName = "DIAGNOSTIC"; break;
    }
    
    Print("[EnhancedLogging] Log level set to: ", levelName);
}

//+------------------------------------------------------------------+
//| Enable Module Logging                                            |
//|                                                                  |
//+------------------------------------------------------------------+
void EnableModuleLogging(string modules)
{
    g_enabledModules = modules;
    
    if(StringLen(modules) == 0) {
        Print("[EnhancedLogging] All modules enabled");
    } else {
        Print("[EnhancedLogging] Enabled modules: ", modules);
    }
}

//+------------------------------------------------------------------+
//| Check if Module is Enabled                                       |
//|                                                                  |
//+------------------------------------------------------------------+
bool IsModuleEnabled(string module)
{
    // If no filter, all modules enabled
    if(StringLen(g_enabledModules) == 0) return true;
    
    // Check if module is in enabled list
    return (StringFind(g_enabledModules, module) >= 0);
}

//                                                                
// CORE LOGGING FUNCTION
//                    
//                                                                

//+------------------------------------------------------------------+
//| Enhanced Log Message with Context                                |
//|                     context                                     |
//+------------------------------------------------------------------+
void LogMessage(ENUM_LOG_LEVEL level, string module, string message)
{
    // Skip if below current log level
    if(level > g_currentLogLevel) return;
    
    // Skip if module not enabled
    if(!IsModuleEnabled(module)) return;
    
    // Update statistics — use frame-time cache to avoid per-call TimeCurrent() syscall
    g_logStats.lastLogTime = CacheGetFrameTime();
    switch(level) {
        case LOG_LEVEL_ERROR:      g_logStats.errorCount++; break;
        case LOG_LEVEL_WARNING:    g_logStats.warningCount++; break;
        case LOG_LEVEL_INFO:       g_logStats.infoCount++; break;
        case LOG_LEVEL_DEBUG:      g_logStats.debugCount++; break;
        case LOG_LEVEL_DIAGNOSTIC: g_logStats.diagnosticCount++; break;
    }
    
    // Build log message
    string logMsg = "";
    
    // Level prefix with emoji
    switch(level) {
        case LOG_LEVEL_ERROR:      logMsg += "  ERROR  "; break;
        case LOG_LEVEL_WARNING:    logMsg += "   WARN   "; break;
        case LOG_LEVEL_INFO:       logMsg += "   INFO   "; break;
        case LOG_LEVEL_DEBUG:      logMsg += "   DEBUG  "; break;
        case LOG_LEVEL_DIAGNOSTIC: logMsg += "   DIAG   "; break;
    }
    
    // Context
    string context = "[" + module + "]";
    
    if(g_logSymbol) {
        context += " [" + Symbol() + "]";
    }
    
    if(g_logTimeframe) {
        context += " [TF:" + IntegerToString(Period()) + "]";
    }
    
    if(g_logTimestamp) {
        context += " [" + TimeToString(CacheGetFrameTime(), TIME_DATE|TIME_SECONDS) + "]";
    }
    
    logMsg += context + " " + message;
    
    // Print to terminal
    Print(logMsg);
}

//                                                                
// CONVENIENCE MACROS
//               
//                                                                

#define LOG_ERROR(module, msg)   LogMessage(LOG_LEVEL_ERROR, module, msg)
#define LOG_WARN(module, msg)    LogMessage(LOG_LEVEL_WARNING, module, msg)
#define LOG_INFO(module, msg)    LogMessage(LOG_LEVEL_INFO, module, msg)
#define LOG_DEBUG(module, msg)   LogMessage(LOG_LEVEL_DEBUG, module, msg)
#define LOG_DIAG(module, msg)    LogMessage(LOG_LEVEL_DIAGNOSTIC, module, msg)

// Formatted logging
#define LOG_ERROR_FMT(module, fmt, ...) LogMessage(LOG_LEVEL_ERROR, module, StringFormat(fmt, __VA_ARGS__))
#define LOG_WARN_FMT(module, fmt, ...)  LogMessage(LOG_LEVEL_WARNING, module, StringFormat(fmt, __VA_ARGS__))
#define LOG_INFO_FMT(module, fmt, ...)  LogMessage(LOG_LEVEL_INFO, module, StringFormat(fmt, __VA_ARGS__))
#define LOG_DEBUG_FMT(module, fmt, ...) LogMessage(LOG_LEVEL_DEBUG, module, StringFormat(fmt, __VA_ARGS__))
#define LOG_DIAG_FMT(module, fmt, ...)  LogMessage(LOG_LEVEL_DIAGNOSTIC, module, StringFormat(fmt, __VA_ARGS__))

//                                                                
// SPECIALIZED LOGGING FUNCTIONS
//                      
//                                                                

//+------------------------------------------------------------------+
//| Log Function Entry (for debugging)                              |
//|                  (          )                                   |
//+------------------------------------------------------------------+
void LogFunctionEntry(string module, string functionName, string params = "")
{
    if(g_currentLogLevel < LOG_LEVEL_DEBUG) return;
    
    string msg = "  " + functionName + "()";
    if(StringLen(params) > 0) {
        msg += " | Params: " + params;
    }
    
    LogMessage(LOG_LEVEL_DEBUG, module, msg);
}

//+------------------------------------------------------------------+
//| Log Function Exit (for debugging)                               |
//|                  (          )                                   |
//+------------------------------------------------------------------+
void LogFunctionExit(string module, string functionName, string result = "")
{
    if(g_currentLogLevel < LOG_LEVEL_DEBUG) return;
    
    string msg = "  " + functionName + "()";
    if(StringLen(result) > 0) {
        msg += " | Result: " + result;
    }
    
    LogMessage(LOG_LEVEL_DEBUG, module, msg);
}

//+------------------------------------------------------------------+
//| Log Performance Metric                                           |
//|                                                                  |
//+------------------------------------------------------------------+
void LogPerformance(string module, string operation, uint elapsedMs)
{
    if(g_currentLogLevel < LOG_LEVEL_DEBUG) return;
    
    string msg = "   " + operation + " took " + IntegerToString(elapsedMs) + " ms";
    
    // Warning if slow
    if(elapsedMs > 100) {
        LogMessage(LOG_LEVEL_WARNING, module, msg + " (SLOW!)");
    } else {
        LogMessage(LOG_LEVEL_DEBUG, module, msg);
    }
}

//+------------------------------------------------------------------+
//| Log Memory Usage                                                 |
//|                                                                  |
//+------------------------------------------------------------------+
void LogMemoryUsage(string module, string arrayName, int size)
{
    if(g_currentLogLevel < LOG_LEVEL_DEBUG) return;
    
    string msg = "   " + arrayName + " size: " + IntegerToString(size) + " elements";
    
    // Warning if large
    if(size > 1000) {
        LogMessage(LOG_LEVEL_WARNING, module, msg + " (LARGE!)");
    } else {
        LogMessage(LOG_LEVEL_DEBUG, module, msg);
    }
}

//                                                                
// STATISTICS & REPORTING
//                 
//                                                                

//+------------------------------------------------------------------+
//| Print Log Statistics                                             |
//|                                                                  |
//+------------------------------------------------------------------+
void PrintLogStatistics()
{
    Print("====================");
    Print("   LOGGING STATISTICS");
    Print("====================");
    Print("Errors: ", g_logStats.errorCount);
    Print("Warnings: ", g_logStats.warningCount);
    Print("Info: ", g_logStats.infoCount);
    Print("Debug: ", g_logStats.debugCount);
    Print("Diagnostic: ", g_logStats.diagnosticCount);
    Print("Last Log: ", TimeToString(g_logStats.lastLogTime, TIME_DATE|TIME_SECONDS));
    Print("====================");
}

//+------------------------------------------------------------------+
//| Reset Log Statistics                                             |
//|                                                                  |
//+------------------------------------------------------------------+
void ResetLogStatistics()
{
    g_logStats.errorCount = 0;
    g_logStats.warningCount = 0;
    g_logStats.infoCount = 0;
    g_logStats.debugCount = 0;
    g_logStats.diagnosticCount = 0;
    g_logStats.lastLogTime = 0;
    
    LOG_INFO("EnhancedLogging", "Statistics reset");
}

//+------------------------------------------------------------------+
//| Initialize Logging System                                        |
//|                                                                  |
//+------------------------------------------------------------------+
void InitializeLogging(ENUM_LOG_LEVEL level = LOG_LEVEL_INFO)
{
    SetLogLevel(level);
    ResetLogStatistics();
    
    LOG_INFO("EnhancedLogging", "Logging system initialized");
}

//                                                                
// USAGE EXAMPLES (        )
//                                                                

/*
// Example 1: Basic logging
LOG_INFO("MyModule", "Operation completed successfully");
LOG_ERROR("MyModule", "Failed to create object");

// Example 2: Formatted logging
LOG_INFO_FMT("MyModule", "Processed %d items in %d ms", count, elapsed);

// Example 3: Function tracing
void MyFunction(int param) {
    LogFunctionEntry("MyModule", "MyFunction", "param=" + IntegerToString(param));
    
    // ... function code ...
    
    LogFunctionExit("MyModule", "MyFunction", "success");
}

// Example 4: Performance logging
uint start = GetTickCount();
// ... operation ...
uint elapsed = GetTickCount() - start;
LogPerformance("MyModule", "Heavy calculation", elapsed);

// Example 5: Module filtering
EnableModuleLogging("ZoneFactory,BasePriceManager");  //                 
EnableModuleLogging("");  //             

// Example 6: Statistics
PrintLogStatistics();
*/

#endif // ENHANCED_LOGGING_MQH
