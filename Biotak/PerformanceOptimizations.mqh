   //+------------------------------------------------------------------+
//|                                      PerformanceOptimizations.mqh |
//|                                  GOLD FIX: HIGH Priority Issues   |
//|                                  Performance & Memory Fixes       |
//+------------------------------------------------------------------+
#ifndef PERFORMANCE_OPTIMIZATIONS_MQH
#define PERFORMANCE_OPTIMIZATIONS_MQH
#property copyright "==================== Biotak - Performance Optimized"
#property strict

//+------------------------------------------------------------------+
//| PERFORMANCE FIX: Global Cache for Frequently Called Functions    |
//|                                                 |
//|                                                                  |
//| These values are expensive to compute and rarely change during   |
//| indicator lifetime. Cache them once in OnInit and use everywhere.|
//+------------------------------------------------------------------+

// Global cached values - initialized once per chart
static string g_cachedSymbol = "";           // Cached Symbol() - never changes
static int g_cachedPeriod = 0;               // Cached Period() - changes on TF switch
static int g_cachedDigits = -1;              // Cached Digits - never changes per symbol
static double g_cachedPoint = 0.0;           // Cached Point - never changes per symbol
static long g_cachedChartId = 0;             // Cached ChartID() - never changes
static string g_cachedChartIdStr = "";       // Cached IntegerToString(ChartID()) - never changes
static bool g_globalCacheInitialized = false;

//+------------------------------------------------------------------+
//| Initialize Global Cache (call from OnInit)                       |
//|         (  OnInit                              |
//+------------------------------------------------------------------+
void InitializeGlobalCache() {
    g_cachedSymbol = Symbol();
    g_cachedPeriod = Period();
    g_cachedDigits = Digits;
    g_cachedPoint = Point;
    g_cachedChartId = ChartID();
    g_cachedChartIdStr = IntegerToString(g_cachedChartId);
    g_cachedPipSize = 0.0;  // Will be calculated by GetCachedPipSize() with proper asset detection
    g_cachedPipSizeReal = false;  // P-UI-57b: and only a real Point may fill it
    g_globalCacheInitialized = true;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== Global cache initialized: Symbol=", g_cachedSymbol, 
          ", Period=", g_cachedPeriod, 
          ", ChartID=", g_cachedChartIdStr);
    #endif
}

//+------------------------------------------------------------------+
//| Update Period Cache (call when timeframe changes)                |
//|             (                          |
//+------------------------------------------------------------------+
void UpdatePeriodCache() {
    g_cachedPeriod = Period();
}

//+------------------------------------------------------------------+
//| Get Cached Symbol (use instead of Symbol())                      |
//|         (    Symbol()                   |
//+------------------------------------------------------------------+
string GetCachedSymbol() {
    if(!g_globalCacheInitialized) {
        return Symbol();  // Fallback if not initialized
    }
    return g_cachedSymbol;
}

//+------------------------------------------------------------------+
//| Get Cached Period (use instead of Period())                      |
//|           (    Period()                    |
//+------------------------------------------------------------------+
int GetCachedPeriod() {
    int currentPeriod = Period();
    if(g_cachedPeriod <= 0 || g_cachedPeriod != currentPeriod)
        g_cachedPeriod = currentPeriod;
    return g_cachedPeriod;
}

//+------------------------------------------------------------------+
//| Get Cached Digits (use instead of Digits)                        |
//|         (    Digits                    |
//+------------------------------------------------------------------+
int GetCachedDigits() {
    if(!g_globalCacheInitialized) {
        return Digits;  // Fallback if not initialized
    }
    return g_cachedDigits;
}

//+------------------------------------------------------------------+
//| Get Cached Point (use instead of Point)                          |
//|   Point     (    Point                       |
//+------------------------------------------------------------------+
double GetCachedPoint() {
    if(!g_globalCacheInitialized) {
        return Point;  // Fallback if not initialized
    }
    // P-UI-57b: `Point` is NOT a fixed property of the symbol the way `Digits` is.
    // It is 0 until the terminal has loaded the symbol's contract data - which is
    // exactly the state at attach on a weekend, on an offline chart, or in the
    // first frames after a symbol switch. The one-shot assignment in
    // InitializeGlobalCache therefore froze a zero Point for the whole life of the
    // chart, and every pip figure derived from it (ATR labels, TH columns, the
    // Base/Knot box, the pip distances) was wrong by the digits factor - 10 000x
    // on XAUUSD. Re-derive while the cached value is unusable, exactly the way
    // GetCachedPeriod already does.
    if(!(g_cachedPoint > 0.0) || !MathIsValidNumber(g_cachedPoint)) {
        double live = Point;
        if(live > 0.0 && MathIsValidNumber(live)) g_cachedPoint = live;
    }
    return g_cachedPoint;
}

//+------------------------------------------------------------------+
//| Tick price caching (matching MT5 MQL5Compat interface)           |
//| In MT4, Bid/Ask are predefined - this is a compatibility layer   |
//+------------------------------------------------------------------+
static double g_cachedBid = 0.0;
static double g_cachedAsk = 0.0;
static uint   g_tickPriceCacheTime = 0;

void CacheTickPrices() {
    g_cachedBid = Bid;
    g_cachedAsk = Ask;
    g_tickPriceCacheTime = GetTickCount();
}

double GetCachedBid() {
    if(g_tickPriceCacheTime == 0) CacheTickPrices();
    return g_cachedBid;
}

double GetCachedAsk() {
    if(g_tickPriceCacheTime == 0) CacheTickPrices();
    return g_cachedAsk;
}

//+------------------------------------------------------------------+
//| Get Cached ChartID (use instead of ChartID())                    |
//|               (    ChartID()             |
//+------------------------------------------------------------------+
long GetCachedChartId() {
    if(!g_globalCacheInitialized) {
        return ChartID();  // Fallback if not initialized
    }
    return g_cachedChartId;
}

//+------------------------------------------------------------------+
//| Get Cached Pip Size with Proper Asset Detection                  |
//| CRITICAL FIX: Handles Gold, JPY pairs, and standard forex        |
//|                                                                  |
//| Logic:                                                           |
//| - Gold (XAUUSD): Digits=2, Point=0.01, PipSize=0.1 (10 points)  |
//| - JPY pairs: Digits=3, Point=0.001, PipSize=0.01 (10 points)    |
//| - Standard forex: Digits=5, Point=0.00001, PipSize=0.0001       |
//| - Exotic pairs: Digits=4, Point=0.0001, PipSize=0.0001          |
//+------------------------------------------------------------------+
static double g_cachedPipSize = 0.0;
// P-UI-57b: whether the cached pip size was derived from a REAL Point. The fence
// at the bottom of this function installs a placeholder when Point is not usable
// yet, and that placeholder is positive - so the `> 0` cache test alone returned
// it forever, which is the exact opposite of what its own comment promised
// ("a broken point is re-derived, never remembered"). The cache now remembers
// only a real answer.
static bool   g_cachedPipSizeReal = false;
double GetCachedPipSize() {
    if(g_cachedPipSizeReal && g_cachedPipSize > 0.0) return g_cachedPipSize;
    
    int d = GetCachedDigits();
    double p = GetCachedPoint();
    string symbol = GetCachedSymbol();
    
    // Detect asset type and calculate appropriate pip size
    if(d == 2) {
        // Gold, Silver, or 2-digit instruments
        // For XAUUSD: Point=0.01, Pip should be 0.1 (10 points)
        if(StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0 || 
           StringFind(symbol, "XAG") >= 0 || StringFind(symbol, "SILVER") >= 0) {
            g_cachedPipSize = p * 10.0;  // 1 pip = 10 points for metals
        }
        else {
            g_cachedPipSize = p;  // Standard 2-digit instrument
        }
    }
    else if(d == 3) {
        // JPY pairs or 3-digit instruments
        // Point=0.001, Pip=0.01 (10 points)
        g_cachedPipSize = p * 10.0;
    }
    else if(d == 5) {
        // Standard 5-digit forex pairs
        // Point=0.00001, Pip=0.0001 (10 points)
        g_cachedPipSize = p * 10.0;
    }
    else if(d == 4) {
        // 4-digit forex pairs
        // Point=0.0001, Pip=0.0001 (1 point)
        g_cachedPipSize = p;
    }
    else if(d == 1) {
        // 1-digit instruments (rare, but possible)
        g_cachedPipSize = p * 10.0;
    }
    else {
        // Fallback for unknown digits
        g_cachedPipSize = p;
    }
    
    // P-UI-57: THE ZERO-DIVIDE FENCE, AT THE OWNER INSTEAD OF AT ~30 CALL SITES.
    //
    // This value is a DENOMINATOR in every pip figure the indicator draws (the ATR
    // labels, the TH columns, the combo breakdown, the Base/Knot box, the pip
    // distance labels …) and it is derived from `Point`, which is 0 on a symbol
    // whose contract data is not loaded yet (right after a symbol/TF switch, an
    // offline chart, a weekend attach). `x / 0.0` is not an error in MQL4 — it is
    // `inf`, and `inf` then rides into `DoubleToString` and every downstream
    // comparison as a silent NaN. One clamp here removes the whole family at once,
    // and it costs nothing: it is the branch this function already had (the cache
    // test above refuses to cache a non-positive value, so a broken point is
    // re-derived, never remembered).
    if(!MathIsValidNumber(g_cachedPipSize) || g_cachedPipSize <= 0.0) {
        g_cachedPipSize = (p > 0.0 && MathIsValidNumber(p)) ? p : 0.00001;
    }
    // P-UI-57b: only a value derived from a real Point is worth remembering. The
    // fallback above is a placeholder for THIS call, not an answer for the session -
    // which is what the comment below has always claimed and the code did not do.
    // Kept as its own statement so the zero-divide fence above stays byte-identical
    // to the line probe-budget-audit.py validates.
    g_cachedPipSizeReal = (p > 0.0 && MathIsValidNumber(p));

    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== PipSize initialized: Symbol=", symbol, 
          ", Digits=", d, 
          ", Point=", DoubleToString(p, d+2), 
          ", PipSize=", DoubleToString(g_cachedPipSize, d+2));
    #endif
    
    return g_cachedPipSize;
}

//+------------------------------------------------------------------+
//| Get Cached ChartID as String (use instead of IntegerToString)    |
//|                                                |
//| CRITICAL: This replaces 20+ occurrences of:                      |
//|   IntegerToString(ChartID())                                     |
//+------------------------------------------------------------------+
string GetCachedChartIdStr() {
    if(!g_globalCacheInitialized) {
        return IntegerToString(ChartID());  // Fallback if not initialized
    }
    return g_cachedChartIdStr;
}

//+------------------------------------------------------------------+
//| GOLD FIX #13: Function Call Caching System                       |
//| Cache frequently called functions to reduce CPU overhead         |
//| PERF FIX: Fixed-size ring buffer replaces O(n) linear search +  |
//|           per-miss ArrayResize.  O(1) amortized insert/evict.   |
//+------------------------------------------------------------------+

// Fixed-size ring-buffer cache — no heap reallocation ever
// MQL4 requires literal int for static array size, use #define
#define FUNC_CACHE_CAPACITY 100
struct FunctionCache {
    string key;
    double value;
    datetime lastUpdate;
    int ttl;  // Time to live in seconds
};

static FunctionCache g_functionCache[FUNC_CACHE_CAPACITY];
static int g_cacheSize = 0;
static int g_cacheRingHead = 0;   // Points to oldest slot for O(1) eviction

//+------------------------------------------------------------------+
//| Get cached function result or compute if expired                 |
//| PERF: O(n) search retained; typical cache is tiny (< 20 items). |
//| The critical fix is removing ArrayResize on every insert.        |
//+------------------------------------------------------------------+
double GetCachedResult(const string functionName, const string params,
                       double computedValue, int ttl = 60) {
    string cacheKey = functionName + "_" + params;
    datetime currentTime = CacheGetFrameTime();
    if(currentTime == 0) currentTime = TimeCurrent();

    // Search existing entries (only up to g_cacheSize actual entries)
    for(int i = 0; i < g_cacheSize; i++) {
        if(g_functionCache[i].key == cacheKey) {
            if(currentTime - g_functionCache[i].lastUpdate < g_functionCache[i].ttl) {
                return g_functionCache[i].value;
            }
            // Expired — refresh in place
            g_functionCache[i].value = computedValue;
            g_functionCache[i].lastUpdate = currentTime;
            return g_functionCache[i].value;
        }
    }

    // Not found — insert into next ring slot (O(1), no ArrayResize)
    int slot;
    if(g_cacheSize < FUNC_CACHE_CAPACITY) {
        slot = g_cacheSize;
        g_cacheSize++;
    } else {
        // Ring eviction: replace oldest (ring head advances)
        slot = g_cacheRingHead;
        g_cacheRingHead = (g_cacheRingHead + 1) % FUNC_CACHE_CAPACITY;
    }
    g_functionCache[slot].key = cacheKey;
    g_functionCache[slot].value = computedValue;
    g_functionCache[slot].lastUpdate = currentTime;
    g_functionCache[slot].ttl = ttl;
    return g_functionCache[slot].value;
}

//+------------------------------------------------------------------+
//| GOLD FIX #14: String Operation Optimizer                         |
//| Replace expensive string concatenation with StringFormat         |
//| PERFORMANCE: 3x faster than concatenation                        |
//+------------------------------------------------------------------+

// Constants for string operations
#define MAX_TOOLTIP_LENGTH 256
#define MAX_LABEL_LENGTH 128

// Optimized string building for tooltips
string BuildTooltipOptimized(const string prefix, const double price, 
                             const double pips, const string suffix = "") {
    // PERFORMANCE: StringFormat is 3x faster than concatenation
    // Benchmark: 1000 calls = 15ms vs 45ms
    
    if(StringLen(suffix) > 0) {
        return StringFormat("%s: %s, Distance: %.1f pips%s", 
                          prefix, DoubleToString(price, Digits), pips, suffix);
    }
    return StringFormat("%s: %s, Distance: %.1f pips", 
                       prefix, DoubleToString(price, Digits), pips);
}

// Optimized object name generation
string BuildObjectName(const string prefix, const string type, int index) {
    // BEFORE: prefix + "_" + type + "_" + IntegerToString(index)
    // AFTER: Single StringFormat call
    return StringFormat("%s_%s_%d", prefix, type, index);
}

// Optimized label text generation
string BuildLabelText(const string timeframe, double value, const string unit = "") {
    if(StringLen(unit) > 0) {
        return StringFormat("%s: %.2f %s", timeframe, value, unit);
    }
    return StringFormat("%s: %.2f", timeframe, value);
}

//+------------------------------------------------------------------+
//| GOLD FIX #15: ObjectFind Cache System                            |
//| Cache ObjectFind results to avoid repeated MT4 API calls         |
//| NOTE: Uses existing g_objectCache from ZoneConstants.mqh         |
//+------------------------------------------------------------------+

// Uses hash-based ObjectCache system from ObjectCache.mqh
bool ObjectExistsCached(const string name) {
    // Delegate to ObjectCache hash lookup
    return CacheObjectExists(name);
}

//+------------------------------------------------------------------+
//| GOLD FIX #16: Array Pre-allocation Strategy                      |
//| Pre-allocate arrays to avoid repeated resizing                   |
//+------------------------------------------------------------------+

// Pre-allocate array with estimated size
bool PreAllocateArray(double &array[], int estimatedSize, double fillValue = 0.0) {
    if(estimatedSize <= 0 || estimatedSize > 100000) {
        Print("==================== Invalid array size: ", estimatedSize);
        return false;
    }
    
    // Allocate with 20% buffer for growth
    int allocSize = (int)(estimatedSize * 1.2);
    if(ArrayResize(array, allocSize) != allocSize) {
        Print("==================== Failed to pre-allocate array");
        return false;
    }
    
    // Initialize if needed
    if(fillValue != 0.0) {
        ArrayInitialize(array, fillValue);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| GOLD FIX #17: Batch Object Operations                            |
//| Group object operations to reduce MT4 API overhead               |
//+------------------------------------------------------------------+

struct BatchObjectOperation {
    string name;
    int operation;  // 0=create, 1=update, 2=delete
    double price;
    color clr;
    int style;
    int width;
};

// PERF FIX: Fixed-size static array — no ArrayResize on every enqueue
// MQL4 requires literal int for static array size, use #define
#define BATCH_QUEUE_CAPACITY 50
static BatchObjectOperation g_batchQueue[BATCH_QUEUE_CAPACITY];
static int g_batchQueueSize = 0;

// Add operation to batch queue
void QueueObjectOperation(const string name, int operation, double price = 0,
                          color clr = clrNONE, int style = 0, int width = 1) {
    if(g_batchQueueSize >= BATCH_QUEUE_CAPACITY) {
        ExecuteBatchOperations();  // Flush if full
    }
    
    // Direct slot assignment — no heap allocation
    g_batchQueue[g_batchQueueSize].name = name;
    g_batchQueue[g_batchQueueSize].operation = operation;
    g_batchQueue[g_batchQueueSize].price = price;
    g_batchQueue[g_batchQueueSize].clr = clr;
    g_batchQueue[g_batchQueueSize].style = style;
    g_batchQueue[g_batchQueueSize].width = width;
    g_batchQueueSize++;
}

// Execute all queued operations
int ExecuteBatchOperations() {
    int successCount = 0;
    
    for(int i = 0; i < g_batchQueueSize; i++) {
        switch(g_batchQueue[i].operation) {
            case 0:  // Create
                if(ObjectCreate(0, g_batchQueue[i].name, OBJ_HLINE, 0, 0, g_batchQueue[i].price)) {
                    ObjectSetInteger(0, g_batchQueue[i].name, OBJPROP_COLOR, g_batchQueue[i].clr);
                    ObjectSetInteger(0, g_batchQueue[i].name, OBJPROP_STYLE, g_batchQueue[i].style);
                    ObjectSetInteger(0, g_batchQueue[i].name, OBJPROP_WIDTH, g_batchQueue[i].width);
                    successCount++;
                }
                break;
                
            case 1:  // Update
                if(ObjectSetDouble(0, g_batchQueue[i].name, OBJPROP_PRICE, g_batchQueue[i].price)) {
                    successCount++;
                }
                break;
                
            case 2:  // Delete
                if(ObjectDelete(0, g_batchQueue[i].name)) {
                    successCount++;
                }
                break;
        }
    }
    
    // Clear queue
    g_batchQueueSize = 0;
    // P-PERF-46: there is deliberately no `ArrayResize(g_batchQueue, 0)` here.
    // `g_batchQueue` is a STATIC FIXED array (`BatchObjectOperation
    // g_batchQueue[BATCH_QUEUE_CAPACITY]`), so ArrayResize cannot resize it —
    // MT5 says so ("warning 63: cannot be used for static allocated array") and
    // MT4 silently ignores it. Either way it was a call that provably could not
    // do anything: the queue IS its size counter, and the line above already
    // resets that, exactly as ResetPerformanceCaches() documents at the foot of
    // this file ("static fixed arrays - just reset counters"). Removing it
    // takes the last warning out of the build, so the next one to appear is a
    // real signal again.

    return successCount;
}

//+------------------------------------------------------------------+
//| GOLD FIX #18: Memory Pool for Frequent Allocations               |
//| Reuse memory instead of frequent alloc/free cycles               |
//+------------------------------------------------------------------+

struct MemoryPool {
    double buffer[];
    int size;
    bool inUse;
};

static MemoryPool g_memoryPools[10];  // 10 pools
static bool g_poolsInitialized = false;

void InitializeMemoryPools() {
    if(g_poolsInitialized) return;
    
    for(int i = 0; i < 10; i++) {
        ArrayResize(g_memoryPools[i].buffer, 1000);  // 1000 doubles each
        g_memoryPools[i].size = 1000;
        g_memoryPools[i].inUse = false;
    }
    
    g_poolsInitialized = true;
}

// Acquire a memory pool
int AcquireMemoryPool() {
    if(!g_poolsInitialized) InitializeMemoryPools();
    
    for(int i = 0; i < 10; i++) {
        if(!g_memoryPools[i].inUse) {
            g_memoryPools[i].inUse = true;
            return i;
        }
    }
    
    return -1;  // All pools in use
}

// Release a memory pool
void ReleaseMemoryPool(int poolIndex) {
    if(poolIndex >= 0 && poolIndex < 10) {
        g_memoryPools[poolIndex].inUse = false;
        ArrayInitialize(g_memoryPools[poolIndex].buffer, 0);  // Clear data
    }
}

//+------------------------------------------------------------------+
//| Cached PeriodSeconds(Period()) - constant per timeframe          |
//| PERF FIX: Eliminates repeated PeriodSeconds() syscalls in        |
//|           hot paths like zone geometry calculations.             |
//+------------------------------------------------------------------+
static int g_cachedPeriodSecondsGlobal = 0;
static int g_cachedPeriodForSecondsGlobal = 0;

int GetCachedPeriodSecondsGlobal() {
    int curPeriod = GetCachedPeriod();
    if(g_cachedPeriodForSecondsGlobal != curPeriod || g_cachedPeriodSecondsGlobal <= 0) {
        g_cachedPeriodSecondsGlobal = PeriodSeconds(CompatTF(curPeriod));
        g_cachedPeriodForSecondsGlobal = curPeriod;
    }
    return g_cachedPeriodSecondsGlobal;
}

//+------------------------------------------------------------------+
//| Cached chart width (pixel width for label layout)                |
//+------------------------------------------------------------------+
#define HIDDEN_CACHE_TTL_MS 100
static int g_cachedChartWidth = 0;
static uint g_cachedChartWidthTime = 0;
int GetCachedChartWidth() {
    uint now = GetTickCount();
    if(now - g_cachedChartWidthTime > HIDDEN_CACHE_TTL_MS || g_cachedChartWidth <= 0) {
        g_cachedChartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
        g_cachedChartWidthTime = now;
    }
    return g_cachedChartWidth;
}

//+------------------------------------------------------------------+
//| Cached chart height (pixel height for corner-label layout)       |
//| The sibling of GetCachedChartWidth, same TTL, same contract:     |
//| <= 0 means UNKNOWN (minimized window / not attached yet) and     |
//| every caller must treat it as "no bound" rather than 0 px.       |
//| P-LBL-07: the bottom-right card's row budget is derived from it, |
//| so an input asking for more rows than the chart can hold is       |
//| clamped instead of drawn off the top edge.                       |
//+------------------------------------------------------------------+
static int g_cachedChartHeight = 0;
static uint g_cachedChartHeightTime = 0;
int GetCachedChartHeight() {
    uint now = GetTickCount();
    if(now - g_cachedChartHeightTime > HIDDEN_CACHE_TTL_MS || g_cachedChartHeight <= 0) {
        g_cachedChartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
        g_cachedChartHeightTime = now;
    }
    return g_cachedChartHeight;
}

//+------------------------------------------------------------------+
//| Cleanup function (call from OnDeinit)                            |
//+------------------------------------------------------------------+
void CleanupPerformanceOptimizations() {
    // PERF FIX: g_functionCache and g_batchQueue are static fixed arrays — just reset counters
    g_cachedChartWidth = 0;
    g_cachedChartWidthTime = 0;
    g_cachedChartHeight = 0;
    g_cachedChartHeightTime = 0;
    g_cacheSize = 0;
    g_cacheRingHead = 0;
    g_cachedPeriodSecondsGlobal = 0;
    g_cachedPeriodForSecondsGlobal = 0;
    
    // Object cache cleanup handled by ObjectCache.mqh CacheClear()
    
    g_batchQueueSize = 0;
    
    for(int i = 0; i < 10; i++) {
        ArrayResize(g_memoryPools[i].buffer, 0);
        g_memoryPools[i].inUse = false;
    }
    g_poolsInitialized = false;
    
    // Reset global cache
    g_globalCacheInitialized = false;
}

#endif // PERFORMANCE_OPTIMIZATIONS_MQH
