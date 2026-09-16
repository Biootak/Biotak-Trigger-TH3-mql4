  //+------------------------------------------------------------------+
//|                                                  BuildConfig.mqh |
//|                        Build Configuration for Debug/Production  |
//+------------------------------------------------------------------+
#ifndef BUILD_CONFIG_MQH
#define BUILD_CONFIG_MQH
#property copyright "  Biotak"
#property strict

//+------------------------------------------------------------------+
//| BUILD MODE SWITCH                                                |
//|                                                                  |
//|                                                                  |
//|   PRODUCTION: Comment out DEBUG_BUILD (default)                  |
//|   DEBUG:      Uncomment DEBUG_BUILD                              |
//|                                                                  |
//+------------------------------------------------------------------+

//                                                                   
//           DEBUG                          :
//                                                                   
//#define DEBUG_BUILD

//                                                                   


//                                                                   
//           LITE (                      )                  :
//                                                                   
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
#define INDICATOR_VERSION "3.10"

//+------------------------------------------------------------------+
//| Print build info on init                                         |
//+------------------------------------------------------------------+
void PrintBuildInfo()
{
    Print("====================");
    Print("   ", BUILD_MODE_EMOJI, " Biotak Trigger TH3 - Version ", INDICATOR_VERSION);
    Print("   Build Mode: ", BUILD_MODE_STR, " (", LITE_MODE_STR, ")");
    Print("   Compiled: ", __DATE__);
    #ifdef BUILD_LITE
    Print("     LITE VERSION - Performance optimized (Core features only)");
    #else
    Print("      FULL VERSION - All advanced features enabled");
    #endif
    #ifdef DEBUG_BUILD
    Print("      DEBUG BUILD - Not for production use!");
    Print("   Features: Logs, Assertions ENABLED");
    #else
    Print("     PRODUCTION BUILD - Optimized for performance");
    #endif
    Print("====================");
}

//+------------------------------------------------------------------+
//| R-TF-UNIT  -  ONE unit for "a timeframe", everywhere             |
//|                                                                  |
//| The shared source is written in the MQL4 model, in which a       |
//| timeframe value IS its own length in minutes:                    |
//|                                                                  |
//|     MT4    Period()   -> 60 on H1                                |
//|            PERIOD_H1  -> 60      (the enum IS the minute count)  |
//|            PERIOD_W1  -> 10080                                   |
//|                                                                  |
//| MQL5 broke that equivalence. Its enum values are unrelated to    |
//| minutes, and Period() returns one of them:                       |
//|                                                                  |
//|     MT5    Period()   -> 16385 on H1                             |
//|            PERIOD_H1  -> 16385                                   |
//|            PERIOD_W1  -> 32769                                   |
//|                                                                  |
//| Every shared line that treats either of those as minutes is      |
//| therefore correct on MT4 and silently wrong on MT5 - a class of  |
//| bug that never announces itself, because 16385 is still a        |
//| perfectly good integer.                                          |
//|                                                                  |
//| THE RULE. These two functions are its entire surface:            |
//|                                                                  |
//|   * a timeframe value in the shared source is ALWAYS minutes;    |
//|   * Period() and GetCachedPeriod() yield minutes;                |
//|   * PERIOD_* constants appear ONLY where an ENUM_TIMEFRAMES is   |
//|     genuinely required;                                          |
//|   * minutes -> ENUM_TIMEFRAMES happens once, at the point of     |
//|     use, through CompatTF().                                     |
//|                                                                  |
//| On MT4 both accessors are identities, so every call site keeps    |
//| meaning exactly what it always meant. On MT5 the shim also       |
//| redefines Period() itself to return minutes, which is what makes |
//| the ~60 existing "Period() as minutes" call sites correct without |
//| being edited at all (see MT5Compat/MQL5Compat.mqh).              |
//+------------------------------------------------------------------+
#ifdef __MQL5__

int CompatPeriodMinutes() { return PeriodSeconds(PERIOD_CURRENT) / 60; }

// Minutes -> ENUM_TIMEFRAMES, deliberately forgiving: a value that is ALREADY
// a valid enum constant passes through unchanged, so a site that crosses the
// boundary twice - or crosses a value that never left the enum side - cannot be
// corrupted by the extra hop. That forgiveness is the safety net for the whole
// refactor: an unconverted call site still lands on the right timeframe.
//
// The two scales cannot collide. Values 1..30 are IDENTICAL on both platforms
// (MQL5's PERIOD_M1..PERIOD_M30 really are 1..30), and above that the minute
// ladder (60, 120, ... 43200) and the enum ladder (16385 ... 49153) are
// disjoint, so membership in one is proof of absence from the other.
ENUM_TIMEFRAMES CompatTF(const int v)
{
   switch(v)
   {
      case PERIOD_M1:  case PERIOD_M2:  case PERIOD_M3:  case PERIOD_M4:
      case PERIOD_M5:  case PERIOD_M6:  case PERIOD_M10: case PERIOD_M12:
      case PERIOD_M15: case PERIOD_M20: case PERIOD_M30:
      case PERIOD_H1:  case PERIOD_H2:  case PERIOD_H3:  case PERIOD_H4:
      case PERIOD_H6:  case PERIOD_H8:  case PERIOD_H12:
      case PERIOD_D1:  case PERIOD_W1:  case PERIOD_MN1:
         return (ENUM_TIMEFRAMES)v;        // already an enum constant
   }

   switch(v)                              // otherwise it is a minute count
   {
      case 1:     return PERIOD_M1;
      case 2:     return PERIOD_M2;
      case 3:     return PERIOD_M3;
      case 4:     return PERIOD_M4;
      case 5:     return PERIOD_M5;
      case 6:     return PERIOD_M6;
      case 10:    return PERIOD_M10;
      case 12:    return PERIOD_M12;
      case 15:    return PERIOD_M15;
      case 20:    return PERIOD_M20;
      case 30:    return PERIOD_M30;
      case 60:    return PERIOD_H1;
      case 120:   return PERIOD_H2;
      case 180:   return PERIOD_H3;
      case 240:   return PERIOD_H4;
      case 360:   return PERIOD_H6;
      case 480:   return PERIOD_H8;
      case 720:   return PERIOD_H12;
      case 1440:  return PERIOD_D1;
      case 10080: return PERIOD_W1;
      case 43200: return PERIOD_MN1;
   }
   return PERIOD_CURRENT;                  // unknown length: let the terminal decide
}

// Normalise a timeframe value of UNKNOWN provenance to minutes. Needed wherever
// the value outlives the process that wrote it - the timeframe lock is persisted
// in a terminal global variable, so a build that stored an ENUM_TIMEFRAMES
// constant (the MT5 behaviour before R-TF-UNIT) is still on disk after the
// upgrade and would restore as "16385" instead of H1. Reading it through here
// makes the migration invisible.
int CompatMinutes(const int v)
{
   if(v <= 0) return 0;
   if(v <= 30) return v;                            // M1..M30: both scales agree
   // Asking the terminal whether v is a valid enum constant is the one place
   // where casting an unknown int to an enum is the point rather than a bug.
   int secs = PeriodSeconds((ENUM_TIMEFRAMES)v);    // tf-unit-audit:allow
   if(secs > 0) return secs / 60;
   return (v <= 43200) ? v : 0;                     // else minutes; reject nonsense
}

#else   // __MQL4__ - both are identities; this model needs no translation

int CompatPeriodMinutes() { return Period(); }
ENUM_TIMEFRAMES CompatTF(const int v) { return (ENUM_TIMEFRAMES)v; }
int CompatMinutes(const int v) { return v; }   // MT4 values are minutes already

#endif

#endif // BUILD_CONFIG_MQH
