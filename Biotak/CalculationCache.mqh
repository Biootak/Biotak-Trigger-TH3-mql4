#ifndef CALCULATION_CACHE_MQH
#define CALCULATION_CACHE_MQH

#property copyright "Biotak"
#property strict
#include "FloatingPointHelper.mqh"
#include "MathConstants.mqh"

struct STHCacheEntry {
    double basePrice;
    double percentage;
    int digits;
    double result;
    datetime lastUpdate;
    bool valid;
};

struct SFactorCacheEntry {
    double highPrice;
    double lowPrice;
    double factorValue;
    int historicalPeriods;
    int period;
    double stepSize;
    datetime lastUpdate;
    bool valid;
};

struct STimeframeCacheEntry {
    int period;
    string fractalTimeframe;
    double percentage;
    int periodSeconds;
    datetime lastUpdate;
    bool valid;
};

struct SGeometryCacheEntry {
    double topPrice;
    double bottomPrice;
    int extensionMultiplier;
    int historicalPeriods;
    datetime startTime;
    datetime endTime;
    datetime lastUpdate;
    bool valid;
};

struct SExtensionMultiplierCacheEntry {
    int period;
    int periodSeconds;
    double multiplier;
    datetime lastUpdate;
    bool valid;
};

static STHCacheEntry g_thCalcCache;
static SFactorCacheEntry g_factorCache;
static STimeframeCacheEntry g_timeframeCache;
static SGeometryCacheEntry g_geometryCache;
static SExtensionMultiplierCacheEntry g_extensionMultiplierCache;
static int g_calcCachedPeriod = -1;
static int g_cachedPeriodSeconds = -1;
static datetime g_cachedPeriodSecondsUpdate = 0;

double GetCachedTHCalculation(double basePrice, double percentage, int digits) {
    if(!g_thCalcCache.valid) {
        return 0.0;
    }
    double normalizedPrice = NormalizeDouble(basePrice, digits);
    double normalizedPercentage = NormalizeDouble(percentage, 6);
    double priceEpsilon = GetDynamicEpsilonForPrice(normalizedPrice);
    bool priceMatch = MathAbs(normalizedPrice - g_thCalcCache.basePrice) < priceEpsilon;
    bool percentageMatch = MathAbs(normalizedPercentage - g_thCalcCache.percentage) < EPSILON_PERCENTAGE;
    bool digitsMatch = (digits == g_thCalcCache.digits);
    if(priceMatch && percentageMatch && digitsMatch) {
        #ifdef ENABLE_DEBUG_LOGS
        static int s_thCacheHits = 0;
        s_thCacheHits++;
        if(s_thCacheHits % 100 == 0) {
            Print("[I][SYNC] TH Cache Hit #", s_thCacheHits);
        }
        #endif
        return g_thCalcCache.result;
    }
    return 0.0;
}

void StoreTHCalculation(double basePrice, double percentage, int digits, double result) {
    g_thCalcCache.basePrice = NormalizeDouble(basePrice, digits);
    g_thCalcCache.percentage = NormalizeDouble(percentage, 6);
    g_thCalcCache.digits = digits;
    g_thCalcCache.result = result;
    g_thCalcCache.lastUpdate = TimeCurrent();
    g_thCalcCache.valid = true;
}

void InvalidateTHCache() {
    g_thCalcCache.valid = false;
    g_thCalcCache.basePrice = 0.0;
    g_thCalcCache.percentage = 0.0;
    g_thCalcCache.digits = -1;
    g_thCalcCache.result = 0.0;
    g_thCalcCache.lastUpdate = 0;
    _LOG_GATE_E Print("[E][SYNC] TH Cache Invalidated");
}

double GetCachedFactorStepSize(double highPrice, double lowPrice, double factor) {
    if(!g_factorCache.valid) {
        return 0.0;
    }
    double priceTolerance = highPrice * EPSILON_PRICE_SCALE;
    bool rangeMatch = (MathAbs(highPrice - g_factorCache.highPrice) < priceTolerance) && 
                      (MathAbs(lowPrice - g_factorCache.lowPrice) < priceTolerance);
    bool factorMatch = MathAbs(factor - g_factorCache.factorValue) < 0.001;
    if(rangeMatch && factorMatch && g_factorCache.stepSize > 0) {
        #ifdef ENABLE_DEBUG_LOGS
        static int s_factorCacheHits = 0;
        s_factorCacheHits++;
        if(s_factorCacheHits % 50 == 0) {
            Print("[I][SYNC] Factor Cache Hit #", s_factorCacheHits);
        }
        #endif
        return g_factorCache.stepSize;
    }
    return 0.0;
}

void StoreFactorStepSize(double highPrice, double lowPrice, double factor, 
                         int historicalPeriods, int period, double stepSize) {
    g_factorCache.highPrice = highPrice;
    g_factorCache.lowPrice = lowPrice;
    g_factorCache.factorValue = factor;
    g_factorCache.historicalPeriods = historicalPeriods;
    g_factorCache.period = period;
    g_factorCache.stepSize = stepSize;
    g_factorCache.lastUpdate = TimeCurrent();
    g_factorCache.valid = true;
}

void InvalidateFactorCache() {
    g_factorCache.valid = false;
    g_factorCache.highPrice = 0.0;
    g_factorCache.lowPrice = 0.0;
    g_factorCache.factorValue = 0.0;
    g_factorCache.historicalPeriods = -1;
    g_factorCache.period = 0;
    g_factorCache.stepSize = 0.0;
    g_factorCache.lastUpdate = 0;
    _LOG_GATE_E Print("[E][SYNC] Factor Cache Invalidated");
}

string GetCachedFractalTimeframe(int period) {
    if(!g_timeframeCache.valid || g_timeframeCache.period != period) {
        return "";
    }
    return g_timeframeCache.fractalTimeframe;
}

double GetCachedFractalPercentage(int period) {
    if(!g_timeframeCache.valid || g_timeframeCache.period != period) {
        return 0.0;
    }
    return g_timeframeCache.percentage;
}

void StoreTimeframeConversion(int period, string fractalTimeframe, 
                              double percentage, int periodSeconds) {
    g_timeframeCache.period = period;
    g_timeframeCache.fractalTimeframe = fractalTimeframe;
    g_timeframeCache.percentage = percentage;
    g_timeframeCache.periodSeconds = periodSeconds;
    g_timeframeCache.lastUpdate = TimeCurrent();
    g_timeframeCache.valid = true;
}

void InvalidateTimeframeCache() {
    g_timeframeCache.valid = false;
    g_timeframeCache.period = -1;
    g_timeframeCache.fractalTimeframe = "";
    g_timeframeCache.percentage = 0.0;
    g_timeframeCache.periodSeconds = -1;
    g_timeframeCache.lastUpdate = 0;
    _LOG_GATE_E Print("[E][SYNC] Timeframe Cache Invalidated");
}

int GetCachedPeriodSeconds(int period) {
    if(g_calcCachedPeriod != period || g_cachedPeriodSeconds < 0) {
        return -1;
    }
    return g_cachedPeriodSeconds;
}

void StorePeriodSeconds(int period, int periodSeconds) {
    g_calcCachedPeriod = period;
    g_cachedPeriodSeconds = periodSeconds;
    g_cachedPeriodSecondsUpdate = TimeCurrent();
    _LOG_GATE_I Print("[I][SYNC] PeriodSeconds Cached: Period=", period, ", Seconds=", periodSeconds);
}

void InvalidatePeriodSecondsCache() {
    g_calcCachedPeriod = -1;
    g_cachedPeriodSeconds = -1;
    g_cachedPeriodSecondsUpdate = 0;
    _LOG_GATE_E Print("[E][SYNC] PeriodSeconds Cache Invalidated");
}

bool GetCachedZoneGeometry(double topPrice, double bottomPrice, 
                           int extensionMultiplier, int historicalPeriods,
                           datetime &startTime, datetime &endTime) {
    if(!g_geometryCache.valid) {
        return false;
    }
    double priceEpsilon = GetDynamicEpsilonForPrice(topPrice);
    bool pricesMatch = (MathAbs(topPrice - g_geometryCache.topPrice) < priceEpsilon) &&
                       (MathAbs(bottomPrice - g_geometryCache.bottomPrice) < priceEpsilon);
    bool paramsMatch = (extensionMultiplier == g_geometryCache.extensionMultiplier) &&
                       (historicalPeriods == g_geometryCache.historicalPeriods);
    if(pricesMatch && paramsMatch) {
        startTime = g_geometryCache.startTime;
        endTime = g_geometryCache.endTime;
        #ifdef ENABLE_DEBUG_LOGS
        static int s_geometryCacheHits = 0;
        s_geometryCacheHits++;
        if(s_geometryCacheHits % 50 == 0) {
            Print("[I][SYNC] Geometry Cache Hit #", s_geometryCacheHits);
        }
        #endif
        return true;
    }
    return false;
}

void StoreZoneGeometry(double topPrice, double bottomPrice, 
                       int extensionMultiplier, int historicalPeriods,
                       datetime startTime, datetime endTime) {
    g_geometryCache.topPrice = topPrice;
    g_geometryCache.bottomPrice = bottomPrice;
    g_geometryCache.extensionMultiplier = extensionMultiplier;
    g_geometryCache.historicalPeriods = historicalPeriods;
    g_geometryCache.startTime = startTime;
    g_geometryCache.endTime = endTime;
    g_geometryCache.lastUpdate = TimeCurrent();
    g_geometryCache.valid = true;
}

void InvalidateGeometryCache() {
    g_geometryCache.valid = false;
    g_geometryCache.topPrice = 0.0;
    g_geometryCache.bottomPrice = 0.0;
    g_geometryCache.extensionMultiplier = 0;
    g_geometryCache.historicalPeriods = -1;
    g_geometryCache.startTime = 0;
    g_geometryCache.endTime = 0;
    g_geometryCache.lastUpdate = 0;
    _LOG_GATE_E Print("[E][SYNC] Geometry Cache Invalidated");
}

double GetCachedExtensionMultiplier(int period, int periodSeconds) {
    if(!g_extensionMultiplierCache.valid || 
       g_extensionMultiplierCache.period != period ||
       g_extensionMultiplierCache.periodSeconds != periodSeconds) {
        return 0.0;
    }
    #ifdef ENABLE_DEBUG_LOGS
    static int s_extensionCacheHits = 0;
    s_extensionCacheHits++;
    if(s_extensionCacheHits % 50 == 0) {
        Print("[I][SYNC] Extension Multiplier Cache Hit #", s_extensionCacheHits);
    }
    #endif
    return g_extensionMultiplierCache.multiplier;
}

void StoreExtensionMultiplier(int period, int periodSeconds, double multiplier) {
    g_extensionMultiplierCache.period = period;
    g_extensionMultiplierCache.periodSeconds = periodSeconds;
    g_extensionMultiplierCache.multiplier = multiplier;
    g_extensionMultiplierCache.lastUpdate = TimeCurrent();
    g_extensionMultiplierCache.valid = true;
}

void InvalidateExtensionMultiplierCache() {
    g_extensionMultiplierCache.valid = false;
    g_extensionMultiplierCache.period = -1;
    g_extensionMultiplierCache.periodSeconds = -1;
    g_extensionMultiplierCache.multiplier = 0.0;
    g_extensionMultiplierCache.lastUpdate = 0;
    _LOG_GATE_E Print("[E][SYNC] Extension Multiplier Cache Invalidated");
}

void InvalidateTimeframeDependentCaches() {
    InvalidateTHCache();
    InvalidateFactorCache();
    InvalidateTimeframeCache();
    InvalidatePeriodSecondsCache();
    InvalidateGeometryCache();
    InvalidateExtensionMultiplierCache();
    _LOG_GATE_E Print("[E][SYNC] Timeframe-Dependent Caches Invalidated");
}

void InvalidateSettingsDependentCaches() {
    InvalidateFactorCache();
    InvalidateGeometryCache();
    _LOG_GATE_E Print("[E][SYNC] Settings-Dependent Caches Invalidated");
}

string GetCacheStatusSummary() {
    string status = "Cache Status:\n";
    status += "  TH Cache: " + (g_thCalcCache.valid ? "VALID" : "INVALID") + "\n";
    status += "  Factor Cache: " + (g_factorCache.valid ? "VALID" : "INVALID") + "\n";
    status += "  Timeframe Cache: " + (g_timeframeCache.valid ? "VALID" : "INVALID") + "\n";
    status += "  PeriodSeconds Cache: " + (g_cachedPeriodSeconds >= 0 ? "VALID" : "INVALID") + "\n";
    status += "  Geometry Cache: " + (g_geometryCache.valid ? "VALID" : "INVALID") + "\n";
    status += "  Extension Multiplier Cache: " + (g_extensionMultiplierCache.valid ? "VALID" : "INVALID");
    return status;
}

void PrintCacheDiagnostics() {
    #ifdef ENABLE_DEBUG_LOGS
    Print("[D][SYNC] === CALCULATION CACHE DIAGNOSTICS ===");
    Print("[D][SYNC] ", GetCacheStatusSummary());
    Print("[D][SYNC] === END DIAGNOSTICS ===");
    #endif
}

#endif // CALCULATION_CACHE_MQH
