//+------------------------------------------------------------------+
//|                                          UnifiedZoneSystem.mqh   |
//|                                  Copyright 2025, Biotak Project  |
//|                    Unified Zone Creation for ALL Modes           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

// CRITICAL: Include guard to prevent duplicate symbols
#ifndef UNIFIED_ZONE_SYSTEM_MQH
#define UNIFIED_ZONE_SYSTEM_MQH

#include "ZoneFactory.mqh"

// CONSTANTS: Zone configuration defaults
#define DEFAULT_ZONE_HEIGHT_PERCENT 0.125  // 12.5% of step (6.25% each side)
#define MIN_ZONE_HEIGHT_PERCENT 0.01       // Minimum 1%
#define MAX_ZONE_HEIGHT_PERCENT 1.0        // Maximum 100%

//+------------------------------------------------------------------+
//| UNIFIED ZONE CONFIGURATION                                        |
//| تنظیمات یکپارچه Zone برای تمام مودها                             |
//|                                                                  |
//| این struct تمام تنظیمات zone را برای همه مودها مدیریت می‌کند    |
//+------------------------------------------------------------------+
struct SUnifiedZoneConfig {
    bool enabled;                    // آیا zone ها فعال هستند؟
    int transparency;                // شفافیت (0-100)
    double heightPercent;            // درصد ارتفاع zone نسبت به step (0.0-1.0)
    bool separateStructureTrigger;   // آیا structure و trigger جدا باشند؟
    color defaultColor;              // رنگ پیش‌فرض
    ENUM_ZONE_STYLE style;    // استایل zone (Lines/Filled/Empty/Hidden)
};

//+------------------------------------------------------------------+
//| CREATE ZONE BETWEEN TWO LEVELS - UNIFIED METHOD                  |
//| ساخت Zone بین دو سطح - متد یکپارچه برای تمام مودها              |
//|                                                                  |
//| این تابع واحد برای تمام مودها استفاده می‌شود:                   |
//| - M Mode, SS/LS Mode, Factor Mode, TP Mode, etc.                |
//|                                                                  |
//| @param zoneName نام یکتای zone                                   |
//| @param prevLevelPrice قیمت سطح قبلی                              |
//| @param currentLevelPrice قیمت سطح فعلی                           |
//| @param config تنظیمات zone                                       |
//| @param levelColor رنگ سطح (برای zone استفاده می‌شود)            |
//| @return true اگر موفق، false اگر ناموفق                          |
//+------------------------------------------------------------------+
bool CreateUnifiedZone(const string zoneName,
                       const double prevLevelPrice,
                       const double currentLevelPrice,
                       const SUnifiedZoneConfig &config,
                       const color levelColor)
{
    // ═══════════════════════════════════════════════════════════════
    // PHASE 1: VALIDATION (Fail Fast)
    // ═══════════════════════════════════════════════════════════════
    
    // Check if zones are enabled
    if(!config.enabled) {
        return true; // Not an error, just disabled
    }
    
    // Check style: HIDDEN
    if(config.style == FACTOR_ZONE_HIDDEN) {
        // Delete zone if exists
        if(ObjectFind(0, zoneName) >= 0) ObjectDelete(0, zoneName);
        return true; // Not an error, just hidden
    }
    
    // Validate zone name
    if(StringLen(zoneName) == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateUnifiedZone: Empty zone name");
        #endif
        return false;
    }
    
    // Validate prices
    if(prevLevelPrice <= 0 || currentLevelPrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateUnifiedZone: Invalid prices - Prev=", DoubleToString(prevLevelPrice, Digits),
              ", Current=", DoubleToString(currentLevelPrice, Digits));
        #endif
        return false;
    }
    
    // Check if prices are equal (no zone needed)
    if(prevLevelPrice == currentLevelPrice) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ CreateUnifiedZone: Prices are equal - no zone needed");
        #endif
        return true; // Not an error
    }
    
    // Validate height percent
    if(config.heightPercent < MIN_ZONE_HEIGHT_PERCENT || config.heightPercent > MAX_ZONE_HEIGHT_PERCENT) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateUnifiedZone: Invalid height percent: ", config.heightPercent,
              " (must be between ", MIN_ZONE_HEIGHT_PERCENT, " and ", MAX_ZONE_HEIGHT_PERCENT, ")");
        #endif
        return false;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 2: CALCULATE ZONE GEOMETRY
    // ═══════════════════════════════════════════════════════════════
    
    // Calculate step size (distance between levels)
    double stepSize = MathAbs(currentLevelPrice - prevLevelPrice);
    
    // Validate step size
    if(stepSize <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateUnifiedZone: Invalid step size: ", stepSize);
        #endif
        return false;
    }
    
    // Calculate zone height (percentage of step size)
    double zoneHeight = stepSize * config.heightPercent * 0.5; // 0.5 because ±height
    
    // Calculate midpoint between two levels
    double midPoint = (prevLevelPrice + currentLevelPrice) / 2.0;
    
    // Calculate zone boundaries
    double upperPrice = NormalizeDouble(midPoint + zoneHeight, Digits);
    double lowerPrice = NormalizeDouble(midPoint - zoneHeight, Digits);
    
    // Validate zone boundaries
    if(upperPrice <= lowerPrice) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateUnifiedZone: Invalid zone boundaries - Upper=", DoubleToString(upperPrice, Digits),
              ", Lower=", DoubleToString(lowerPrice, Digits));
        #endif
        return false;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 3: HANDLE LINES STYLE (Special Case)
    // ═══════════════════════════════════════════════════════════════
    
    if(config.style == FACTOR_ZONE_LINES) {
        // Use special lines-only implementation
        return CreateFactorMidZone_LinesStyle(zoneName, upperPrice, lowerPrice,
                                              (levelColor == clrNONE) ? config.defaultColor : levelColor,
                                              config.transparency);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // PHASE 4: DELEGATE TO ZONE FACTORY (Box Styles)
    // ═══════════════════════════════════════════════════════════════
    
    SZoneCreationRequest request;
    request.name = zoneName;
    request.topPrice = upperPrice;
    request.bottomPrice = lowerPrice;
    request.zoneColor = (levelColor == clrNONE) ? config.defaultColor : levelColor;
    request.transparency = config.transparency;
    request.filled = (config.style == FACTOR_ZONE_BOX_FILLED);
    request.startTime = 0;  // Auto-calculate
    request.endTime = 0;    // Auto-calculate
    
    SZoneCreationResult result = CreateZone(request);
    
    if(!result.success) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateUnifiedZone: Factory failed for '", zoneName, "' - ", result.errorMessage,
              " (Code: ", result.errorCode, ")");
        #endif
        return false;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ CreateUnifiedZone: Created/Updated '", zoneName, "' [",
          DoubleToString(lowerPrice, Digits), " - ", DoubleToString(upperPrice, Digits), "]");
    #endif
    
    return true;
}

//+------------------------------------------------------------------+
//| GET UNIFIED ZONE CONFIG FROM GLOBAL SETTINGS                     |
//| دریافت تنظیمات یکپارچه zone از تنظیمات global                    |
//|                                                                  |
//| این تابع تنظیمات zone را از input parameters می‌خواند            |
//| FIX BUG #16: Added validation for global variables               |
//| GOLD VERSION: Added style support for all modes                  |
//+------------------------------------------------------------------+
SUnifiedZoneConfig GetUnifiedZoneConfig()
{
    SUnifiedZoneConfig config;
    
    // FIX BUG #16: Validate global variables exist and have valid values
    // Read from global input parameters with safe defaults
    config.enabled = inpShowMidZones;
    
    // Validate and clamp transparency
    config.transparency = inpMidZoneTransparency;
    if(config.transparency < 0) config.transparency = 0;
    if(config.transparency > 100) config.transparency = 100;
    
    // GOLD VERSION: Use configurable zone height from input parameter
    // Convert from percentage (1-100) to decimal (0.01-1.0)
    double heightPercentInput = inpMidZoneHeightPercent / 100.0;
    
    // Validate and clamp height percent
    if(heightPercentInput < MIN_ZONE_HEIGHT_PERCENT) {
        heightPercentInput = MIN_ZONE_HEIGHT_PERCENT;
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ GetUnifiedZoneConfig: Zone height too small, clamped to ", 
              MIN_ZONE_HEIGHT_PERCENT * 100, "%");
        #endif
    }
    if(heightPercentInput > MAX_ZONE_HEIGHT_PERCENT) {
        heightPercentInput = MAX_ZONE_HEIGHT_PERCENT;
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ GetUnifiedZoneConfig: Zone height too large, clamped to ", 
              MAX_ZONE_HEIGHT_PERCENT * 100, "%");
        #endif
    }
    
    config.heightPercent = heightPercentInput;
    
    config.separateStructureTrigger = true;
    config.defaultColor = clrDarkGray;
    
    // GOLD VERSION: Add style support
    config.style = inpMidZoneStyle;
    
    return config;
}

//+------------------------------------------------------------------+
//| CREATE ZONE WITH TRACKING - FOR STRUCTURE/TRIGGER SEPARATION    |
//| ساخت Zone با ردیابی - برای جداسازی Structure/Trigger            |
//|                                                                  |
//| این تابع برای مودهایی که structure و trigger جدا دارند          |
//| (مثل M Mode, SS/LS Mode)                                         |
//|                                                                  |
//| FIX BUG #15: Removed unused prevPrice parameter                  |
//|                                                                  |
//| @param zoneName نام zone                                         |
//| @param currentPrice قیمت فعلی                                    |
//| @param isStructure آیا این zone برای structure است؟             |
//| @param levelColor رنگ سطح                                        |
//| @param lastStructurePrice آخرین قیمت structure (برای tracking)  |
//| @param lastTriggerPrice آخرین قیمت trigger (برای tracking)      |
//| @return true اگر موفق                                            |
//+------------------------------------------------------------------+
bool CreateZoneWithTracking(const string zoneName,
                            const double currentPrice,
                            const bool isStructure,
                            const color levelColor,
                            double &lastStructurePrice,
                            double &lastTriggerPrice)
{
    SUnifiedZoneConfig config = GetUnifiedZoneConfig();
    
    // Determine which "last price" to use based on structure/trigger
    double effectivePrevPrice = 0;
    
    if(isStructure) {
        effectivePrevPrice = lastStructurePrice;
        lastStructurePrice = currentPrice; // Update tracker
    }
    else {
        effectivePrevPrice = lastTriggerPrice;
        lastTriggerPrice = currentPrice; // Update tracker
    }
    
    // Only create zone if we have a previous price
    if(effectivePrevPrice <= 0) {
        return true; // Not an error, just first level
    }
    
    // Create zone using unified method
    return CreateUnifiedZone(zoneName, effectivePrevPrice, currentPrice, config, levelColor);
}

//+------------------------------------------------------------------+
//| CREATE SIMPLE ZONE - FOR MODES WITHOUT STRUCTURE/TRIGGER        |
//| ساخت Zone ساده - برای مودهای بدون Structure/Trigger             |
//|                                                                  |
//| این تابع برای مودهایی که structure/trigger ندارند               |
//| (مثل Factor Mode, M-Equal Mode)                                 |
//|                                                                  |
//| @param zoneName نام zone                                         |
//| @param prevPrice قیمت قبلی                                       |
//| @param currentPrice قیمت فعلی                                    |
//| @param levelColor رنگ سطح                                        |
//| @return true اگر موفق                                            |
//+------------------------------------------------------------------+
bool CreateSimpleZone(const string zoneName,
                      const double prevPrice,
                      const double currentPrice,
                      const color levelColor)
{
    SUnifiedZoneConfig config = GetUnifiedZoneConfig();
    return CreateUnifiedZone(zoneName, prevPrice, currentPrice, config, levelColor);
}

//+------------------------------------------------------------------+
//| CREATE ZONE WITH SMART FALLBACK - UNIFIED FOR ALL MODES         |
//| ساخت Zone با Fallback هوشمند - یکپارچه برای تمام مودها          |
//|                                                                  |
//| این تابع برای تمام مودها استفاده می‌شود و به صورت خودکار       |
//| تشخیص می‌دهد که آیا باید از Structure/Trigger tracking استفاده |
//| کند یا از fallback ساده.                                        |
//|                                                                  |
//| LOGIC:                                                           |
//| 1. اگر Structure فعال است و سطح Structure است → Structure zone |
//| 2. اگر Trigger فعال است و سطح Trigger است → Trigger zone      |
//| 3. در غیر این صورت → Fallback zone با رنگ سطح                  |
//|                                                                  |
//| CRITICAL FIX: Added fixedStepSize parameter for consistent zones|
//|                                                                  |
//| @param zoneName نام zone                                         |
//| @param currentPrice قیمت سطح فعلی                                |
//| @param isStructure آیا این سطح Structure است؟                   |
//| @param levelColor رنگ سطح                                        |
//| @param structureEnabled آیا Structure فعال است؟                 |
//| @param triggerEnabled آیا Trigger فعال است؟                     |
//| @param lastStructurePrice آخرین قیمت Structure (برای tracking)  |
//| @param lastTriggerPrice آخرین قیمت Trigger (برای tracking)      |
//| @param lastFallbackPrice آخرین قیمت Fallback (برای tracking)    |
//| @param fixedStepSize اندازه ثابت step (0=auto از فاصله)        |
//| @return true اگر موفق                                            |
//+------------------------------------------------------------------+
bool CreateZoneWithSmartFallback(const string zoneName,
                                 const double currentPrice,
                                 const bool isStructure,
                                 const color levelColor,
                                 const bool structureEnabled,
                                 const bool triggerEnabled,
                                 double &lastStructurePrice,
                                 double &lastTriggerPrice,
                                 double &lastFallbackPrice,
                                 const double fixedStepSize = 0)
{
    SUnifiedZoneConfig config = GetUnifiedZoneConfig();
    
    // Determine which tracking path to use
    double effectivePrevPrice = 0;
    bool shouldDraw = false;
    
    if(isStructure && structureEnabled) {
        // Structure zone path
        effectivePrevPrice = lastStructurePrice;
        shouldDraw = (lastStructurePrice > 0);
        lastStructurePrice = currentPrice;
    }
    else if(!isStructure && triggerEnabled) {
        // Trigger zone path
        effectivePrevPrice = lastTriggerPrice;
        shouldDraw = (lastTriggerPrice > 0);
        lastTriggerPrice = currentPrice;
    }
    else {
        // FALLBACK: Neither Structure nor Trigger enabled
        // Draw zone using level's own color
        effectivePrevPrice = lastFallbackPrice;
        shouldDraw = (lastFallbackPrice > 0);
        lastFallbackPrice = currentPrice;
    }
    
    // Only create zone if we have a previous price
    if(!shouldDraw || effectivePrevPrice <= 0) {
        return true; // Not an error, just first level
    }
    
    // CRITICAL FIX: Use fixed step size if provided
    if(fixedStepSize > 0) {
        // Calculate zone with fixed step size (for consistent height)
        double zoneHeight = fixedStepSize * config.heightPercent * 0.5;
        double midPoint = (effectivePrevPrice + currentPrice) / 2.0;
        double upperPrice = NormalizeDouble(midPoint + zoneHeight, Digits);
        double lowerPrice = NormalizeDouble(midPoint - zoneHeight, Digits);
        
        // Handle LINES style (special case)
        if(config.style == FACTOR_ZONE_LINES) {
            return CreateFactorMidZone_LinesStyle(zoneName, upperPrice, lowerPrice,
                                                  (levelColor == clrNONE) ? config.defaultColor : levelColor,
                                                  config.transparency);
        }
        
        // Handle HIDDEN style
        if(config.style == FACTOR_ZONE_HIDDEN) {
            if(ObjectFind(0, zoneName) >= 0) ObjectDelete(0, zoneName);
            return true;
        }
        
        // Handle BOX styles (Filled/Empty)
        SZoneCreationRequest request;
        request.name = zoneName;
        request.topPrice = upperPrice;
        request.bottomPrice = lowerPrice;
        request.zoneColor = (levelColor == clrNONE) ? config.defaultColor : levelColor;
        request.transparency = config.transparency;
        request.filled = (config.style == FACTOR_ZONE_BOX_FILLED);
        request.startTime = 0;
        request.endTime = 0;
        
        SZoneCreationResult result = CreateZone(request);
        return result.success;
    }
    
    // Original method: use distance between levels
    return CreateUnifiedZone(zoneName, effectivePrevPrice, currentPrice, config, levelColor);
}

//+------------------------------------------------------------------+
//| BATCH CREATE ZONES - FOR PERFORMANCE                             |
//| ساخت دسته‌ای Zone ها - برای بهینه‌سازی عملکرد                   |
//|                                                                  |
//| این تابع برای ساخت چندین zone به صورت batch استفاده می‌شود      |
//+------------------------------------------------------------------+
struct SZonePair {
    string name;
    double prevPrice;
    double currentPrice;
    color levelColor;
};

int CreateZonesBatch(const SZonePair &zones[], const SUnifiedZoneConfig &config)
{
    int count = ArraySize(zones);
    int successCount = 0;
    
    for(int i = 0; i < count; i++) {
        if(CreateUnifiedZone(zones[i].name, zones[i].prevPrice, zones[i].currentPrice,
                            config, zones[i].levelColor)) {
            successCount++;
        }
    }
    
    return successCount;
}

#endif // UNIFIED_ZONE_SYSTEM_MQH
