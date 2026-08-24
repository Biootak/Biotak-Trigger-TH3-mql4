//+------------------------------------------------------------------+
//|                                             MQ4Compatibility.mqh |
//| Small compatibility shims for the restored MT4 indicator source. |
//+------------------------------------------------------------------+
#ifndef BIOTAK_MQ4_COMPATIBILITY_MQH
#define BIOTAK_MQ4_COMPATIBILITY_MQH

// MT4 error code used by the indicator's GlobalVariableGet checks.
#ifndef ERR_GLOBALVARIABLE_NOT_FOUND
#define ERR_GLOBALVARIABLE_NOT_FOUND 4058
#endif

// GlobalVariables hidden-state cache refresh interval.
#ifndef HIDDEN_CACHE_TTL_MS
#define HIDDEN_CACHE_TTL_MS 500
#endif

// MT4 has no PeriodMinutes() helper in older terminal builds.
int PeriodMinutes(const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
{
    if(timeframe == PERIOD_CURRENT)
        return Period();
    return (int)timeframe;
}

// Keep the source readable where it intentionally mirrors the MT5 code.
double iATRMQL4(const string symbol,
                const ENUM_TIMEFRAMES timeframe,
                const int period,
                const int shift)
{
    return iATR(symbol, timeframe, period, shift);
}

// MT4's iATR is value-based and has no indicator handle to release.
void ReleaseATRHandle()
{
}

#endif // BIOTAK_MQ4_COMPATIBILITY_MQH
