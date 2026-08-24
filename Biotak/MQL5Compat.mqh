//+------------------------------------------------------------------+
//|                                                  MQL5Compat.mqh |
//|              MQL4 → MQL5 Compatibility Layer                     |
//|              Provides MQL4 functions/variables for MQL5          |
//+------------------------------------------------------------------+
#ifndef MQL5_COMPAT_MQH
#define MQL5_COMPAT_MQH

//+------------------------------------------------------------------+
//| Bid / Ask predefined variables (MQL4 → MQL5)                    |
//| در MQL4 این متغیرها مستقیم در دسترس هستند                        |
//| در MQL5 باید از SymbolInfoDouble استفاده شود                      |
//+------------------------------------------------------------------+
#define Bid SymbolInfoDouble(_Symbol, SYMBOL_BID)
#define Ask SymbolInfoDouble(_Symbol, SYMBOL_ASK)

//+------------------------------------------------------------------+
//| Digits / Point predefined variables (MQL4 → MQL5)               |
//| در MQL4: Digits و Point مستقیم در دسترس هستند                    |
//| در MQL5: باید از _Digits و _Point استفاده شود                     |
//+------------------------------------------------------------------+
#define Digits _Digits
#define Point  _Point

//+------------------------------------------------------------------+
//| MarketInfo() compatibility (MQL4 → MQL5)                         |
//| در MQL4: MarketInfo(symbol, MODE_POINT) و غیره                   |
//| در MQL5: SymbolInfoDouble/Integer                                |
//+------------------------------------------------------------------+
// MQL4 MarketInfo mode constants
#define MODE_POINT          16
#define MODE_DIGITS         12
#define MODE_SPREAD         13
#define MODE_TICKSIZE       18
#define MODE_TICKVALUE      17
#define MODE_SWAPLONG       19
#define MODE_SWAPSHORT      20
#define MODE_STOPLEVEL      14
#define MODE_LOTSIZE        15
#define MODE_MINLOT         23
#define MODE_LOTSTEP        24
#define MODE_MAXLOT         25
#define MODE_MARGINREQUIRED 37
#define MODE_BID            9
#define MODE_ASK            10
#define MODE_TIME           5
#define MODE_LOW            1
#define MODE_HIGH           2
#define MODE_FREEZELEVEL    33

double MarketInfo(string symbol, int mode) {
    switch(mode) {
        case MODE_POINT:          return SymbolInfoDouble(symbol, SYMBOL_POINT);
        case MODE_DIGITS:         return (double)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        case MODE_SPREAD:         return (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
        case MODE_TICKSIZE:       return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        case MODE_TICKVALUE:      return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        case MODE_SWAPLONG:       return SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG);
        case MODE_SWAPSHORT:      return SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT);
        case MODE_STOPLEVEL:      return (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        case MODE_LOTSIZE:        return SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        case MODE_MINLOT:         return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        case MODE_LOTSTEP:        return SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        case MODE_MAXLOT:         return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        case MODE_MARGINREQUIRED: return SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
        case MODE_BID:            return SymbolInfoDouble(symbol, SYMBOL_BID);
        case MODE_ASK:            return SymbolInfoDouble(symbol, SYMBOL_ASK);
        case MODE_TIME:           return (double)SymbolInfoInteger(symbol, SYMBOL_TIME);
        case MODE_LOW:            return SymbolInfoDouble(symbol, SYMBOL_LASTLOW);
        case MODE_HIGH:           return SymbolInfoDouble(symbol, SYMBOL_LASTHIGH);
        case MODE_FREEZELEVEL:    return (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
        default:                  return 0.0;
    }
}

// NOTE: iBarShift() is now built-in in MQL5 (newer builds)
// No custom implementation needed

//+------------------------------------------------------------------+
//| Time decomposition functions (MQL4 → MQL5)                      |
//| در MQL4 این توابع مستقیم وجود دارند                               |
//| در MQL5 باید از MqlDateTime استفاده شود                           |
//+------------------------------------------------------------------+
int TimeHour(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return dt.hour;
}

int TimeMinute(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return dt.min;
}

int TimeSeconds(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return dt.sec;
}

int TimeDay(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return dt.day;
}

int TimeMonth(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return dt.mon;
}

int TimeYear(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return dt.year;
}

int TimeDayOfWeek(datetime time) {
    MqlDateTime dt;
    TimeToStruct(time, dt);
    return dt.day_of_week;
}

//+------------------------------------------------------------------+
//| PeriodMinutes() - Get current period in minutes                  |
//| در MQL4 مقدار Period() برابر دقیقه بود                            |
//| در MQL5 مقدار Period() یک ENUM_TIMEFRAMES است                     |
//| (مثلاً PERIOD_H1 = 16385 و نه 60)                                 |
//+------------------------------------------------------------------+
int PeriodMinutes(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(tf == PERIOD_CURRENT || tf == 0) tf = (ENUM_TIMEFRAMES)GetCachedPeriod();
    return PeriodSeconds(tf) / 60;
}

//+------------------------------------------------------------------+
//| iATR compatibility (MQL4 4-param → MQL5 handle-based)            |
//| PERFORMANCE: Multi-slot handle cache (up to 16 param combos).   |
//| Avoids create/destroy on every call when alternating periods.    |
//+------------------------------------------------------------------+
#define ATR_CACHE_SIZE 16

struct ATRHandleCacheEntry {
    int handle;
    string symbol;
    ENUM_TIMEFRAMES tf;
    int period;
};

ATRHandleCacheEntry g_atrHandleCache[];
int g_atrHandleCacheCount = 0;
bool g_atrHandleCacheInitialized = false;

void InitATRCache() {
    if(!g_atrHandleCacheInitialized) {
        ArrayResize(g_atrHandleCache, ATR_CACHE_SIZE);
        for(int i = 0; i < ATR_CACHE_SIZE; i++) {
            g_atrHandleCache[i].handle = INVALID_HANDLE;
            g_atrHandleCache[i].symbol = "";
            g_atrHandleCache[i].tf = PERIOD_CURRENT;
            g_atrHandleCache[i].period = 0;
        }
        g_atrHandleCacheInitialized = true;
    }
}

double iATRMQL4(string symbol, ENUM_TIMEFRAMES timeframe, int atr_period, int shift) {
    if(symbol == NULL || symbol == "") symbol = _Symbol;
    
    InitATRCache();
    
    // Search existing cache entries
    int handle = INVALID_HANDLE;
    for(int i = 0; i < g_atrHandleCacheCount; i++) {
        if(g_atrHandleCache[i].symbol == symbol &&
           g_atrHandleCache[i].tf == timeframe &&
           g_atrHandleCache[i].period == atr_period) {
            handle = g_atrHandleCache[i].handle;
            break;
        }
    }
    
    // Cache miss — create new handle
    if(handle == INVALID_HANDLE) {
        handle = iATR(symbol, timeframe, atr_period);
        if(handle == INVALID_HANDLE) {
            PrintFormat("iATRMQL4: Failed to create ATR handle for %s/%s/%d", 
                        symbol, EnumToString(timeframe), atr_period);
            return 0.0;
        }
        
        // Store in cache (round-robin eviction when full)
        static int g_atrEvictSlot = 0; // Round-robin eviction cursor
        int slot = g_atrHandleCacheCount;
        if(slot >= ATR_CACHE_SIZE) {
            // Round-robin eviction: cycle through all slots fairly
            slot = g_atrEvictSlot;
            if(g_atrHandleCache[slot].handle != INVALID_HANDLE)
                IndicatorRelease(g_atrHandleCache[slot].handle);
            g_atrEvictSlot = (g_atrEvictSlot + 1) % ATR_CACHE_SIZE;
        } else {
            g_atrHandleCacheCount++;
        }
        g_atrHandleCache[slot].handle = handle;
        g_atrHandleCache[slot].symbol = symbol;
        g_atrHandleCache[slot].tf = timeframe;
        g_atrHandleCache[slot].period = atr_period;
    }
    
    double buffer[];
    ArraySetAsSeries(buffer, true);
    
    int copied = CopyBuffer(handle, 0, shift, 1, buffer);
    if(copied <= 0) {
        return 0.0;
    }
    
    return buffer[0];
}

// Call this from OnDeinit to release ALL cached ATR handles
void ReleaseATRHandle() {
    for(int i = 0; i < g_atrHandleCacheCount; i++) {
        if(g_atrHandleCache[i].handle != INVALID_HANDLE) {
            IndicatorRelease(g_atrHandleCache[i].handle);
            g_atrHandleCache[i].handle = INVALID_HANDLE;
        }
    }
    g_atrHandleCacheCount = 0;
}

//+------------------------------------------------------------------+
//| WindowFirstVisibleBar / WindowBarsPerChart compatibility         |
//| (if used in the codebase)                                        |
//+------------------------------------------------------------------+
int WindowFirstVisibleBar() {
    return (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
}

int WindowBarsPerChart() {
    return (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
}

//+------------------------------------------------------------------+
//| ObjectSetText compatibility (MQL4 → MQL5)                        |
//| MQL4: ObjectSetText(name, text, font_size, font_name, color)    |
//| MQL5: Use ObjectSetString/Integer individually                    |
//+------------------------------------------------------------------+
bool ObjectSetText(string name, string text, int font_size = 0, string font_name = "", color text_color = clrNONE) {
    bool result = ObjectSetString(0, name, OBJPROP_TEXT, text);
    if(font_size > 0)
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    if(font_name != "")
        ObjectSetString(0, name, OBJPROP_FONT, font_name);
    if(text_color != clrNONE)
        ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
    return result;
}

//+------------------------------------------------------------------+
//| ObjectsTotal compatibility (MQL4 → MQL5)                         |
//| MQL4: ObjectsTotal() - returns total objects on chart            |
//| MQL5: ObjectsTotal(chart_id, sub_window, type) - more parameters |
//| Note: Removed wrapper to avoid ambiguity - use explicit params   |
//+------------------------------------------------------------------+
// Wrapper removed - use ::ObjectsTotal(0, -1, -1) directly in MT5

//+------------------------------------------------------------------+
//| ObjectName compatibility (MQL4 → MQL5)                           |
//| MQL4: ObjectName(index) - returns object name by index           |
//| MQL5: ObjectName(chart_id, index, sub_window, type)              |
//| Note: Removed wrapper to avoid ambiguity - use explicit params   |
//+------------------------------------------------------------------+
// Wrapper removed - use ::ObjectName(0, index, -1, -1) directly in MT5

#endif // MQL5_COMPAT_MQH
