//+------------------------------------------------------------------+
//|                                                  BuildConfig.mqh |
//|                        Build Configuration for Debug/Production  |
//+------------------------------------------------------------------+
#property copyright "© Biotak"
#property strict

//+------------------------------------------------------------------+
//| BUILD MODE SWITCH                                                |
//| ═══════════════════════════════════════════════════════════════  |
//|                                                                  |
//|   PRODUCTION: Comment out DEBUG_BUILD (default)                  |
//|   DEBUG:      Uncomment DEBUG_BUILD                              |
//|                                                                  |
//+------------------------------------------------------------------+

// ══════════════════════════════════════════════════════════════════
// برای حالت DEBUG این خط رو از کامنت دربیار:
// ══════════════════════════════════════════════════════════════════
//#define DEBUG_BUILD

// ══════════════════════════════════════════════════════════════════


// ══════════════════════════════════════════════════════════════════
// برای حالت LITE (حذف ویژگی‌های غیرضروری) این خط رو فعال کن:
// ══════════════════════════════════════════════════════════════════
//#define BUILD_LITE

//+------------------------------------------------------------------+
//| Automatic flag setup - DO NOT MODIFY BELOW                       |
//+------------------------------------------------------------------+
#ifdef BUILD_LITE
    #define LITE_MODE_STR "LITE"
    // Disable profiler in Lite mode
    #define TH3_PROF_START(tag)
    #define TH3_PROF_END(tag)
#else
    #define LITE_MODE_STR "FULL"
#endif

#ifdef DEBUG_BUILD
    #define ENABLE_DEBUG_LOGS
    // Performance logs disabled permanently
    #define ENABLE_VERBOSE_ERRORS
    #define ENABLE_ASSERTIONS
    #define BUILD_MODE_STR "DEBUG"
    #define BUILD_MODE_EMOJI "[D]"
#else
    #define BUILD_MODE_STR "PRODUCTION"
    #define BUILD_MODE_EMOJI "[P]"
#endif

//+------------------------------------------------------------------+
//| Debug Macros - Zero overhead in Production                       |
//+------------------------------------------------------------------+

#ifdef ENABLE_DEBUG_LOGS
    #define DEBUG_PRINT(msg) Print("[DEBUG] ", msg)
    #define DEBUG_PRINTF(msg, p1) Print("[DEBUG] ", msg, p1)
    #define DEBUG_PRINTF2(msg, p1, p2) Print("[DEBUG] ", msg, p1, p2)
    #define DEBUG_PRINTF3(msg, p1, p2, p3) Print("[DEBUG] ", msg, p1, p2, p3)
    #define DEBUG_PRINTF4(msg, p1, p2, p3, p4) Print("[DEBUG] ", msg, p1, p2, p3, p4)
    #define DEBUG_PRINTF5(msg, p1, p2, p3, p4, p5) Print("[DEBUG] ", msg, p1, p2, p3, p4, p5)
    // History manager logs - variadic style using Print directly
    #define HISTORY_LOG_ENABLED 1
#else
    #define DEBUG_PRINT(msg)
    #define DEBUG_PRINTF(msg, p1)
    #define DEBUG_PRINTF2(msg, p1, p2)
    #define DEBUG_PRINTF3(msg, p1, p2, p3)
    #define DEBUG_PRINTF4(msg, p1, p2, p3, p4)
    #define DEBUG_PRINTF5(msg, p1, p2, p3, p4, p5)
    // History manager logs disabled in production
    #define HISTORY_LOG_ENABLED 0
#endif

// Performance macros - Removed for size optimization
#define PERF_START()
#define PERF_END(name)

#ifdef ENABLE_VERBOSE_ERRORS
    #define ERROR_PRINT(msg) Print("[ERROR] ", __FUNCTION__, " - ", msg)
    #define WARN_PRINT(msg) Print("[WARN] ", __FUNCTION__, " - ", msg)
#else
    #define ERROR_PRINT(msg) Print("[ERROR] ", msg)
    #define WARN_PRINT(msg)
#endif

#ifdef ENABLE_ASSERTIONS
    #define ASSERT(condition, msg) if(!(condition)) { Print("[ASSERT FAILED] ", __FUNCTION__, " - ", msg); }
    #define ASSERT_PRICE(price) ASSERT(price > 0 && price < 1000000, "Invalid price")
#else
    #define ASSERT(condition, msg)
    #define ASSERT_PRICE(price)
#endif

//+------------------------------------------------------------------+
//| ATR Logging Macros                                               |
//+------------------------------------------------------------------+
#ifdef ENABLE_DEBUG_LOGS
    #define ATR_PRINT(msg) Print("[ATR] ", msg)
    #define ATR_PRINTF(msg, p1) Print("[ATR] ", msg, p1)
    #define ATR_PRINTF2(msg, p1, p2) Print("[ATR] ", msg, p1, p2)
    #define ATR_PRINTF3(msg, p1, p2, p3) Print("[ATR] ", msg, p1, p2, p3)
#else
    #define ATR_PRINT(msg)
    #define ATR_PRINTF(msg, p1)
    #define ATR_PRINTF2(msg, p1, p2)
    #define ATR_PRINTF3(msg, p1, p2, p3)
#endif

//+------------------------------------------------------------------+
//| Version info                                                     |
//+------------------------------------------------------------------+
#define INDICATOR_VERSION "3.05"

//+------------------------------------------------------------------+
//| Print build info on init                                         |
//+------------------------------------------------------------------+
void PrintBuildInfo()
{
    Print("╔═══════════════════════════════════════════════════════════════╗");
    Print("║  ", BUILD_MODE_EMOJI, " Biotak Trigger TH3 - Version ", INDICATOR_VERSION);
    Print("║  Build Mode: ", BUILD_MODE_STR, " (", LITE_MODE_STR, ")");
    Print("║  Compiled: ", __DATE__);
    #ifdef BUILD_LITE
    Print("║  ⚡ LITE VERSION - Performance optimized (Core features only)");
    #else
    Print("║  💎 FULL VERSION - All advanced features enabled");
    #endif
    #ifdef DEBUG_BUILD
    Print("║  ⚠️ DEBUG BUILD - Not for production use!");
    Print("║  Features: Logs, Assertions ENABLED");
    #else
    Print("║  ✅ PRODUCTION BUILD - Optimized for performance");
    #endif
    Print("╚═══════════════════════════════════════════════════════════════╝");
}

