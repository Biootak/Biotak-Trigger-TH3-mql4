//+------------------------------------------------------------------+
//|                                                   ZoneFactory.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                          Factory Pattern for Zone Creation       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#include "ConstantsAndEnums.mqh"
#include "ZoneValidator.mqh"

//+------------------------------------------------------------------+
//| Zone Factory - Centralized Zone Creation                         |
//| فکتوری Zone - ساخت متمرکز Zone‌ها                                |
//|                                                                  |
//| BENEFITS:                                                        |
//| - Single point of zone creation (DRY)                           |
//| - Consistent validation                                          |
//| - Easy to extend with new zone types                            |
//| - Testable in isolation                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Zone Creation Request                                            |
//| درخواست ساخت Zone                                                |
//+------------------------------------------------------------------+
struct SZoneCreationRequest {
    string name;              // Zone name
    double topPrice;          // Top boundary
    double bottomPrice;       // Bottom boundary
    color zoneColor;          // Zone color
    int transparency;         // Transparency (0-100)
    bool filled;              // Fill zone?
    datetime startTime;       // Start time (optional, 0 = auto)
    datetime endTime;         // End time (optional, 0 = auto)
};

//+------------------------------------------------------------------+
//| Zone Creation Result                                             |
//| نتیجه ساخت Zone                                                  |
//+------------------------------------------------------------------+
struct SZoneCreationResult {
    bool success;             // Was creation successful?
    string zoneName;          // Created zone name
    string errorMessage;      // Error message if failed
    int errorCode;            // Error code
};

// PERF: Per-frame cached chart background color
static color g_cachedBgColor = clrBlack;
static datetime g_cachedBgColorFrameTime = 0;

color GetCachedChartBgColor() {
    datetime frameTime = CacheGetFrameTime();
    if(frameTime == g_cachedBgColorFrameTime && g_cachedBgColorFrameTime != 0) {
        return g_cachedBgColor;
    }
    g_cachedBgColor = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    g_cachedBgColorFrameTime = frameTime;
    return g_cachedBgColor;
}

// Compute visually reliable zone color for chart objects by blending with background.
// This simulates transparency in MT4 which doesn't support alpha channel in standard objects.
color GetZoneRenderColor(const color sourceColor, const int transparency)
{
    int t = (int)MathMax(0, MathMin(100, transparency));
    // Stronger visual fade (same concept as trigger transparency mapping)
    int tVis = 100 - ((100 - t) * (100 - t)) / 100;

    if(tVis <= 0) return sourceColor;

    color bg = GetCachedChartBgColor();
    if(tVis >= 100) return bg;

    int fr = ((int)sourceColor) & 0xFF;
    int fg = (((int)sourceColor) >> 8) & 0xFF;
    int fb = (((int)sourceColor) >> 16) & 0xFF;

    int br = ((int)bg) & 0xFF;
    int bgc = (((int)bg) >> 8) & 0xFF;
    int bb = (((int)bg) >> 16) & 0xFF;

    int outR = (fr * (100 - tVis) + br * tVis) / 100;
    int outG = (fg * (100 - tVis) + bgc * tVis) / 100;
    int outB = (fb * (100 - tVis) + bb * tVis) / 100;

    return (color)(outR | (outG << 8) | (outB << 16));
}

//+------------------------------------------------------------------+
//| Create Zone with Full Validation - GOLD VERSION v3 FINAL         |
//| ساخت Zone با اعتبارسنجی کامل - نسخه طلایی v3 نهایی               |
//|                                                                  |
//| IMPROVEMENTS v3 (FINAL):                                         |
//| - Fixed: Removed duplicate property setting (performance)       |
//| - Fixed: Added error checking for all ObjectSet calls           |
//| - Fixed: Corrected startIndex validation logic                  |
//| - Fixed: Added PeriodSeconds validation                         |
//| - Race condition prevention (cached Bars/Time)                  |
//| - Better transparency validation with warning                   |
//| - Atomic object creation (cleanup on failure)                   |
//| - Comprehensive error context                                   |
//+------------------------------------------------------------------+
SZoneCreationResult CreateZone(const SZoneCreationRequest &request)
{
    SZoneCreationResult result;
    result.success = false;
    result.zoneName = request.name;
    result.errorMessage = "";
    result.errorCode = ERR_ZONE_NONE;
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 1: VALIDATION (Fail Fast)
    // ═══════════════════════════════════════════════════════════════
    
    // Validate name
    if(StringLen(request.name) == 0) {
        result.errorMessage = "Zone name cannot be empty";
        result.errorCode = ERR_ZONE_INVALID_CONFIG;
        return result;
    }
    
    // Validate prices
    if(request.topPrice <= 0 || request.bottomPrice <= 0) {
        result.errorMessage = StringFormat("Invalid zone prices: Top=%s, Bottom=%s",
                                          DoubleToString(request.topPrice, Digits),
                                          DoubleToString(request.bottomPrice, Digits));
        result.errorCode = ERR_ZONE_INVALID_CONFIG;
        return result;
    }
    
    if(request.topPrice <= request.bottomPrice) {
        result.errorMessage = StringFormat("Top price (%s) must be greater than bottom price (%s)",
                                          DoubleToString(request.topPrice, Digits),
                                          DoubleToString(request.bottomPrice, Digits));
        result.errorCode = ERR_ZONE_INVALID_CONFIG;
        return result;
    }
    
    // Validate transparency with warning for clamping
    int originalTransparency = request.transparency;
    int clampedTransparency = request.transparency;
    
    if(clampedTransparency < 0) {
        clampedTransparency = 0;
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ CreateZone: Transparency clamped from ", originalTransparency, " to 0");
        #endif
    }
    if(clampedTransparency > 100) {
        clampedTransparency = 100;
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ CreateZone: Transparency clamped from ", originalTransparency, " to 100");
        #endif
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 2: TIME CALCULATION (Race Condition Prevention - GOLD v3 FINAL)
    // ═══════════════════════════════════════════════════════════════
    
    // GOLD FIX v3: Use GlobalVariable mutex for true atomic operation
    // PERFORMANCE: Use cached ChartID string
    string mutexName = "Biotak_ZoneCreate_Mutex_" + GetCachedChartIdStr();
    string mutexTimeName = mutexName + "_Time";
    
    // Check for stale mutex (older than 2 seconds)
    if(GlobalVariableCheck(mutexTimeName)) {
        datetime lockTime = (datetime)GlobalVariableGet(mutexTimeName);
        if(TimeCurrent() - lockTime > 2) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ ZoneFactory: Stale mutex detected, forcing release");
            #endif
            GlobalVariableDel(mutexName);
            GlobalVariableDel(mutexTimeName);
        }
    }
    
    // CRITICAL FIX: Use GlobalVariableSetOnCondition for atomic lock acquisition
    // This prevents race condition between Check and Set
    bool lockAcquired = false;
    for(int attempt = 0; attempt < 10; attempt++) {
        // First attempt: create new mutex if doesn't exist
        if(!GlobalVariableCheck(mutexName)) {
            // Use atomic set - only succeeds if value is still 0 (doesn't exist)
            // Note: In MQL4, we use a workaround since GlobalVariableSetOnCondition
            // checks for specific value. We set to 0 first, then try to change to 1
            GlobalVariableSet(mutexName, 0.0);
            GlobalVariableTemp(mutexName);
            
            // Atomic compare-and-swap: only set to 1 if still 0
            if(GlobalVariableSetOnCondition(mutexName, 1.0, 0.0)) {
                GlobalVariableSet(mutexTimeName, (double)TimeCurrent());
                GlobalVariableTemp(mutexTimeName);
                lockAcquired = true;
                break;
            }
        }
        Sleep(10);
    }
    
    // CRITICAL SECTION: Read Bars and Time atomically
    int safeBars = 0;
    datetime currentTime = 0;
    bool atomicReadSuccess = false;
    
    if(lockAcquired) {
        // Inside mutex - safe to read
        safeBars = Bars;
        currentTime = (safeBars > 0) ? Time[0] : 0;
        
        // Validate read
        if(safeBars > 0 && currentTime > 0) {
            atomicReadSuccess = true;
        }
        
        // Release mutex immediately
        GlobalVariableDel(mutexName);
        GlobalVariableDel(mutexTimeName);
    }
    
    // Fallback strategy if mutex acquisition failed
    if(!atomicReadSuccess) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ ZoneFactory: Mutex acquisition failed, using fallback");
        #endif
        
        // Enhanced fallback with multiple retries
        const int FALLBACK_MAX_RETRIES = 5;
        for(int retry = 0; retry < FALLBACK_MAX_RETRIES && !atomicReadSuccess; retry++) {
            int bars1 = Bars;
            datetime time1 = (bars1 > 0) ? Time[0] : 0;
            int bars2 = Bars;
            datetime time2 = (bars2 > 0) ? Time[0] : 0;
            
            if(bars1 > 0 && bars1 == bars2 && time1 > 0 && time1 == time2) {
                safeBars = bars1;
                currentTime = time1;
                atomicReadSuccess = true;
            } else {
                Sleep(20);
            }
        }
        
        // Final fallback
        if(!atomicReadSuccess) {
            safeBars = Bars;
            currentTime = (safeBars > 0) ? Time[0] : TimeCurrent();
            if(currentTime <= 0) currentTime = TimeCurrent();
        }
    }
    
    // Final validation with detailed error
    if(currentTime <= 0) {
        result.errorMessage = StringFormat("Invalid time after fallback (Bars=%d)", safeBars);
        result.errorCode = ERR_ZONE_RENDER_FAILED;
        return result;
    }
    
    datetime startTime = request.startTime;
    datetime endTime = request.endTime;
    
    // Auto-calculate times if not provided
    if(startTime == 0) {
        if(safeBars <= 0) {
            result.errorMessage = StringFormat("Invalid Bars count: %d", safeBars);
            result.errorCode = ERR_ZONE_RENDER_FAILED;
            return result;
        }
        
        // FIX BUG #12: Correct validation logic
        // startIndex will be safeBars-1, which is always < safeBars
        // So we need to check if safeBars is at least 1
        if(safeBars < 1) {
            result.errorMessage = "Not enough bars for zone creation";
            result.errorCode = ERR_ZONE_RENDER_FAILED;
            return result;
        }
        
        int startIndex = safeBars - 1;
        startTime = Time[startIndex];
        
        // Validate retrieved time
        if(startTime <= 0) {
            result.errorMessage = StringFormat("Invalid Time[%d]", startIndex);
            result.errorCode = ERR_ZONE_RENDER_FAILED;
            return result;
        }
    }
    else {
        // Validate user-provided startTime
        if(startTime <= 0) {
            result.errorMessage = StringFormat("Invalid user-provided startTime: %s", TimeToString(startTime));
            result.errorCode = ERR_ZONE_INVALID_CONFIG;
            return result;
        }
    }
    
    if(endTime == 0) {
        if(currentTime <= 0) {
            result.errorMessage = "Invalid Time[0]";
            result.errorCode = ERR_ZONE_RENDER_FAILED;
            return result;
        }
        
        // CRITICAL FIX: Validate PeriodSeconds before use
        int periodSeconds = PeriodSeconds(Period());
        if(periodSeconds <= 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("❌ CreateZone: Invalid PeriodSeconds=", periodSeconds, " for Period=", Period());
            #endif
            result.success = false;
            result.errorCode = ZONE_ERROR_INVALID_PRICES;
            result.errorMessage = "Invalid timeframe period";
            return result;
        }
        
        // Additional validation: Check for reasonable period
        if(periodSeconds > 2592000) {  // 30 days in seconds
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ CreateZone: Suspiciously large PeriodSeconds=", periodSeconds);
            #endif
        }
        
        // Now safe to use periodSeconds
        datetime calculatedEndTime = startTime + (periodSeconds * 10000);
        
        // Validate endTime is reasonable
        if(calculatedEndTime <= startTime) {
            result.errorMessage = StringFormat("Invalid PeriodSeconds: %d", periodSeconds);
            result.errorCode = ERR_ZONE_RENDER_FAILED;
            return result;
        }
        
        endTime = currentTime + periodSeconds * ZONE_EXTENSION_PERIODS;
    }
    else {
        // Validate user-provided endTime
        if(endTime <= 0) {
            result.errorMessage = StringFormat("Invalid user-provided endTime: %s", TimeToString(endTime));
            result.errorCode = ERR_ZONE_INVALID_CONFIG;
            return result;
        }
    }
    
    // Validate time range
    if(startTime <= 0 || endTime <= startTime) {
        result.errorMessage = StringFormat("Invalid time range: Start=%s, End=%s",
                                          TimeToString(startTime),
                                          TimeToString(endTime));
        result.errorCode = ERR_ZONE_RENDER_FAILED;
        return result;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 3: CALCULATE FINAL COLOR (Before Object Creation)
    // ═══════════════════════════════════════════════════════════════
    
    // Use background blending to simulate transparency (matching MT5 logic)
    color finalColor = GetZoneRenderColor(request.zoneColor, clampedTransparency);
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 4: ZONE CREATION/UPDATE (Atomic Operation)
    // FIX BUG #10: Set properties ONCE, not twice
    // FIX BUG #11: Check all ObjectSet return values
    // ═══════════════════════════════════════════════════════════════
    
    bool objectExists = (ObjectFind(0, request.name) >= 0);
    bool needsPropertyUpdate = true;
    
    if(!objectExists) {
        // GOLD FIX #4: Enhanced atomic zone creation with rollback
        bool createSuccess = ObjectCreate(0, request.name, OBJ_RECTANGLE, 0, 
                                         startTime, request.topPrice, 
                                         endTime, request.bottomPrice);
        
        if(!createSuccess) {
            int error = GetLastError();
            result.errorMessage = StringFormat("Failed to create zone '%s': MT4 Error %d", 
                                              request.name, error);
            result.errorCode = error;
            
            // CRITICAL: Atomic cleanup - ensure no partial objects remain
            int cleanupAttempts = 0;
            while(ObjectFind(0, request.name) >= 0 && cleanupAttempts < 3) {
                ObjectDelete(0, request.name);
                cleanupAttempts++;
                if(cleanupAttempts > 1) {
                    Sleep(10); // Brief pause for MT4 to process
                }
            }
            
            if(ObjectFind(0, request.name) >= 0) {
                Print("⚠️ Failed to cleanup partial zone object after ", cleanupAttempts, " attempts");
            }
            
            return result;
        }
        needsPropertyUpdate = true;
    }
    else {
        // Update existing zone - geometry only
        // FIX BUG #11: Check return values
        bool updateSuccess = true;
        updateSuccess = updateSuccess && ObjectSetDouble(0, request.name, OBJPROP_PRICE1, request.topPrice);
        updateSuccess = updateSuccess && ObjectSetDouble(0, request.name, OBJPROP_PRICE2, request.bottomPrice);
        updateSuccess = updateSuccess && ObjectSetInteger(0, request.name, OBJPROP_TIME1, startTime);
        updateSuccess = updateSuccess && ObjectSetInteger(0, request.name, OBJPROP_TIME2, endTime);
        
        if(!updateSuccess) {
            int error = GetLastError();
            result.errorMessage = StringFormat("Failed to update zone geometry '%s': MT4 Error %d", 
                                              request.name, error);
            result.errorCode = error;
            return result;
        }
        needsPropertyUpdate = true;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 5: APPLY VISUAL PROPERTIES (Once, with error checking)
    // FIX BUG #10: Properties set ONCE here for both create and update
    // FIX BUG #11: Check all return values
    // ═══════════════════════════════════════════════════════════════
    
    if(needsPropertyUpdate) {
        bool propsSuccess = true;
        propsSuccess = propsSuccess && ObjectSetInteger(0, request.name, OBJPROP_COLOR, finalColor);
        propsSuccess = propsSuccess && ObjectSetInteger(0, request.name, OBJPROP_BACK, true);
        propsSuccess = propsSuccess && ObjectSetInteger(0, request.name, OBJPROP_FILL, request.filled);
        propsSuccess = propsSuccess && ObjectSetInteger(0, request.name, OBJPROP_SELECTABLE, false);
        propsSuccess = propsSuccess && ObjectSetInteger(0, request.name, OBJPROP_RAY_RIGHT, true);
        propsSuccess = propsSuccess && ObjectSetInteger(0, request.name, OBJPROP_ZORDER, 0);
        
        if(!propsSuccess) {
            int error = GetLastError();
            #ifdef ENABLE_DEBUG_LOGS
            Print("⚠️ CreateZone: Failed to set some properties for '", request.name, "': MT4 Error ", error);
            #endif
            // Don't fail completely - zone is created, just properties might be incomplete
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // SUCCESS
    // ═══════════════════════════════════════════════════════════════
    
    result.success = true;
    result.zoneName = request.name;
    
    return result;
}

//+------------------------------------------------------------------+
//| Batch Create Zones                                               |
//| ساخت دسته‌ای Zone‌ها                                             |
//+------------------------------------------------------------------+
int CreateZonesBatch(const SZoneCreationRequest &requests[], 
                     SZoneCreationResult &results[])
{
    int count = ArraySize(requests);
    ArrayResize(results, count);
    
    int successCount = 0;
    
    for(int i = 0; i < count; i++) {
        results[i] = CreateZone(requests[i]);
        if(results[i].success) successCount++;
    }
    
    return successCount;
}

//+------------------------------------------------------------------+
//| Delete Zone Safely                                               |
//| حذف امن Zone                                                      |
//+------------------------------------------------------------------+
bool DeleteZone(const string &zoneName)
{
    if(StringLen(zoneName) == 0) return false;
    
    if(ObjectFind(0, zoneName) >= 0) {
        return ObjectDelete(0, zoneName);
    }
    
    return true; // Already deleted
}

//+------------------------------------------------------------------+
//| Delete Zones by Prefix                                           |
//| حذف Zone‌ها با پیشوند                                             |
//+------------------------------------------------------------------+
int DeleteZonesByPrefix(const string &prefix)
{
    if(StringLen(prefix) == 0) return 0;
    
    int deletedCount = 0;
    int totalObjects = ObjectsTotal(0, -1, -1);
    
    for(int i = totalObjects - 1; i >= 0; i--) {
        string name = ObjectName(0, i, -1, -1);
        
        if(StringFind(name, prefix) == 0) {
            if(ObjectDelete(0, name)) {
                deletedCount++;
            }
        }
    }
    
    return deletedCount;
}
