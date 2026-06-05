  //+------------------------------------------------------------------+
//|                                                ZoneConstants.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                                    Global Constants & Settings   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

// CRITICAL: Include guard to prevent duplicate symbols
#ifndef ZONE_CONSTANTS_MQH
#define ZONE_CONSTANTS_MQH

//+------------------------------------------------------------------+
//| GLOBAL CONSTANTS: Zone Drawing Configuration                     |
//|            :                                                     |
//+------------------------------------------------------------------+

// Performance Constants (unique to ZoneConstants   duplicates removed, see ProjectConstants.mqh)
const int VALIDATION_CACHE_TTL = 60;           //                          (     )
const int CACHE_CLEANUP_INTERVAL = 300;        //       cleanup    (5      )
const int MAX_ALPHA_VALUE = 255;               //                        transparency
const int MIN_ALPHA_VALUE = 0;                 //                 

// Safety Limits (unique   duplicates removed, see ProjectConstants.mqh)
const double MIN_STEP_SIZE_RATIO = 0.000001;   //                              

// Error Codes
const int ERR_ZONE_NONE = 0;
const int ERR_ZONE_INVALID_ARRAY = 1;
const int ERR_ZONE_INVALID_STEP = 2;
const int ERR_ZONE_INVALID_CONFIG = 3;
const int ERR_ZONE_RENDER_FAILED = 4;
const int ERR_ZONE_MEMORY_LIMIT = 5;
const int ERR_ZONE_ARRAY_MISMATCH = 6;

// Debug Flags
#ifdef ENABLE_DEBUG_LOGS
    #define ZONE_DEBUG_VALIDATION true
    #define ZONE_DEBUG_CALCULATION true
    #define ZONE_DEBUG_RENDERING true
    #define ZONE_DEBUG_PERFORMANCE true
#else
    #define ZONE_DEBUG_VALIDATION false
    #define ZONE_DEBUG_CALCULATION false
    #define ZONE_DEBUG_RENDERING false
    #define ZONE_DEBUG_PERFORMANCE false
#endif

//+------------------------------------------------------------------+
//| STRUCTURE: Performance Metrics                                    |
//|       :                                                          |
//+------------------------------------------------------------------+
struct SZonePerformanceMetrics {
    int totalZonesCreated;
    int totalZonesUpdated;
    int totalZonesFailed;
    int totalValidationCalls;
    int totalRenderCalls;
    double avgValidationTime;
    double avgRenderTime;
    datetime lastResetTime;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES: Performance Tracking                           |
//|               :                                                  |
//+------------------------------------------------------------------+
static SZonePerformanceMetrics g_zoneMetrics;
// NOTE: SObjectCacheEntry and g_objectCache moved to ObjectCache.mqh
static datetime g_lastCacheCleanup = 0;

// Market Price Cache (                              )
static double g_cachedMarketPrice = 0;
static datetime g_cachedMarketPriceTime = 0;
static int g_cachedMarketPriceTTL = 1; // 1      

//+------------------------------------------------------------------+
//| Initialize Performance Metrics                                    |
//|                                                                  |
//+------------------------------------------------------------------+
void InitializeZoneMetrics() {
    g_zoneMetrics.totalZonesCreated = 0;
    g_zoneMetrics.totalZonesUpdated = 0;
    g_zoneMetrics.totalZonesFailed = 0;
    g_zoneMetrics.totalValidationCalls = 0;
    g_zoneMetrics.totalRenderCalls = 0;
    g_zoneMetrics.avgValidationTime = 0;
    g_zoneMetrics.avgRenderTime = 0;
    g_zoneMetrics.lastResetTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Reset Performance Metrics                                         |
//|                                                                   |
//+------------------------------------------------------------------+
void ResetZoneMetrics() {
    InitializeZoneMetrics();
}

//+------------------------------------------------------------------+
//| Get Performance Metrics                                           |
//|                                                                   |
//+------------------------------------------------------------------+
SZonePerformanceMetrics GetZoneMetrics() {
    return g_zoneMetrics;
}

//+------------------------------------------------------------------+
//| Print Performance Report                                          |
//|                                                                   |
//+------------------------------------------------------------------+
void PrintZonePerformanceReport() {
    #ifdef ENABLE_DEBUG_LOGS
    Print("====================");
    Print("   Zone Drawing Performance Report");
    Print("====================");
    Print("  Zones Created: ", g_zoneMetrics.totalZonesCreated);
    Print("   Zones Updated: ", g_zoneMetrics.totalZonesUpdated);
    Print("  Zones Failed: ", g_zoneMetrics.totalZonesFailed);
    Print("   Validation Calls: ", g_zoneMetrics.totalValidationCalls);
    Print("   Render Calls: ", g_zoneMetrics.totalRenderCalls);
    Print("   Avg Validation Time: ", DoubleToString(g_zoneMetrics.avgValidationTime, 2), " ms");
    Print("   Avg Render Time: ", DoubleToString(g_zoneMetrics.avgRenderTime, 2), " ms");
    Print("   Last Reset: ", TimeToString(g_zoneMetrics.lastResetTime));
    Print("====================");
    #endif
}

//+------------------------------------------------------------------+
//| Cleanup Zone System (     OnDeinit)                              |
//|                                                                  |
//+------------------------------------------------------------------+
void CleanupZoneSystem() {
    // Reset metrics
    g_zoneMetrics.totalZonesCreated = 0;
    g_zoneMetrics.totalZonesUpdated = 0;
    g_zoneMetrics.totalZonesFailed = 0;
    g_zoneMetrics.totalValidationCalls = 0;
    g_zoneMetrics.totalRenderCalls = 0;
    g_zoneMetrics.avgValidationTime = 0;
    g_zoneMetrics.avgRenderTime = 0;
    
    // Clear cache (object cache now in ObjectCache.mqh)
    g_lastCacheCleanup = 0;
    
    // Clear market price cache
    g_cachedMarketPrice = 0;
    g_cachedMarketPriceTime = 0;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  CleanupZoneSystem: System cleaned up successfully");
    #endif
}

//+------------------------------------------------------------------+
//| Get Cached Market Price (   TTL)                                 |
//|                                                                  |
//+------------------------------------------------------------------+
double GetCachedMarketPrice() {
    datetime currentTime = TimeCurrent();
    
    //                
    if(g_cachedMarketPriceTime > 0 && 
       (currentTime - g_cachedMarketPriceTime) < g_cachedMarketPriceTTL) {
        return g_cachedMarketPrice;
    }
    
    // CRITICAL: Cache Bid/Ask to avoid race condition
    double cachedBid = Bid;
    double cachedAsk = Ask;
    
    //                     
    g_cachedMarketPrice = (cachedBid + cachedAsk) / 2.0;
    g_cachedMarketPriceTime = currentTime;
    
    return g_cachedMarketPrice;
}

//+------------------------------------------------------------------+
//| Cleanup Object Cache (                )                          |
//|                                                                   |
//+------------------------------------------------------------------+
void CleanupObjectCache() {
    // Object cache now managed by ObjectCache.mqh (hash-based)
    g_lastCacheCleanup = TimeCurrent();
}

#endif // ZONE_CONSTANTS_MQH
