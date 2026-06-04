//+------------------------------------------------------------------+
//|                                                 ZoneRenderer.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                                    Zone Rendering & MT4 Objects  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#include "ConstantsAndEnums.mqh"
#include "ZoneConstants.mqh"
#include "GlobalVariables.mqh"  // برای دسترسی به g_linesVisible
#include "ZoneFactory.mqh"      // استفاده از Factory Pattern برای یکپارچگی

//+------------------------------------------------------------------+
//| Resolve Line Styles                                              |
//| تعیین استایل خطوط                                                |
//+------------------------------------------------------------------+
void ResolveLineStyles(
    const SLevelRawData &levels[],
    const SLevelClassification &classifications[],
    const SStyleConfig &config,
    const string objectPrefix,
    SLineRenderInfo &outLines[])
{
    int count = ArraySize(levels);
    
    // CRITICAL FIX: Validate array size before resize
    if(count <= 0 || count > MAX_SAFE_LEVELS) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ ResolveLineStyles: Invalid level count=", count);
        #endif
        ArrayResize(outLines, 0);
        return;
    }
    
    ArrayResize(outLines, count);
    
    // CRITICAL: بررسی خالی نبودن objectPrefix
    string safePrefix = (StringLen(objectPrefix) > 0) ? objectPrefix : "Zone_";
    
    // PERF FIX: Use centralized cached Digits from PerformanceOptimizations.mqh
    int cachedDigits = GetCachedDigits();
    
    for(int i = 0; i < count; i++) {
        outLines[i].isVisible = false;
        
        if(classifications[i].isActive) {
            // Line visibility controlled by config (which uses g_linesVisible)
            // نمایش خطوط توسط config کنترل می‌شه (که از g_linesVisible استفاده می‌کند)
            outLines[i].isVisible = config.globalShowLines;
            outLines[i].clr = classifications[i].levelColor;
            outLines[i].style = (ENUM_LINE_STYLE)classifications[i].style;
            outLines[i].width = classifications[i].width;
            
            // Generate name using StringFormat (3x faster than concatenation)
            string suffix = (levels[i].logicalStep >= 0) ? "Above_" : "Below_";
            if(levels[i].logicalStep == 0) suffix = "Midpoint_";
            int absStep = MathAbs(levels[i].logicalStep);
            
            outLines[i].name = StringFormat("%sLevel_%s%d", safePrefix, suffix, absStep);
            outLines[i].price = NormalizeDouble(levels[i].price, cachedDigits);
            outLines[i].tooltip = StringFormat("Level %d", levels[i].logicalStep);
            outLines[i].selectable = false;
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    int visibleCount = 0;
    for(int i = 0; i < count; i++) {
        if(outLines[i].isVisible) visibleCount++;
    }
    Print("✅ ResolveLineStyles: ", visibleCount, " visible lines");
    #endif
}

//+------------------------------------------------------------------+
//| Resolve Zone Styles                                              |
//| تعیین استایل زون‌ها                                              |
//+------------------------------------------------------------------+
void ResolveZoneStyles(
    const SLevelRawData &levels[],
    const SLevelClassification &classifications[],
    const SZoneGeometry &geometries[],
    const SStyleConfig &config,
    const string objectPrefix,
    SZoneRenderInfo &outZones[])
{
    int count = ArraySize(levels);
    int zoneCount = 0;
    ArrayResize(outZones, count); // Max possible
    
    // CRITICAL: بررسی خالی نبودن objectPrefix
    string safePrefix = (StringLen(objectPrefix) > 0) ? objectPrefix : "Zone_";
    
    // DIAGNOSTIC LOG: Start
    Print("═══════════════════════════════════════════════════════════");
    Print("🔍 ZONE STYLE RESOLUTION DIAGNOSTIC");
    Print("═══════════════════════════════════════════════════════════");
    Print("📋 Configuration:");
    Print("   Show Zones: ", config.showZones ? "TRUE" : "FALSE");
    Print("   Zone Transparency: ", config.zoneTransparency, "%");
    Print("   Object Prefix: ", safePrefix);
    Print("───────────────────────────────────────────────────────────");
    
    if(config.showZones) {
        Print("🎨 Zone Style Assignment:");
        
        for(int i = 0; i < count; i++) {
            if(geometries[i].isValid && classifications[i].isActive) {
                string suffix = (levels[i].logicalStep >= 0) ? "Above_" : "Below_";
                int absStep = MathAbs(levels[i].logicalStep);
                
                outZones[zoneCount].isVisible = true;
                outZones[zoneCount].name = StringFormat("%sZone_%s%d", safePrefix, suffix, absStep);
                outZones[zoneCount].clr = classifications[i].levelColor;
                outZones[zoneCount].transparency = config.zoneTransparency;
                outZones[zoneCount].filled = true;
                outZones[zoneCount].topPrice = geometries[i].topPrice;
                outZones[zoneCount].bottomPrice = geometries[i].bottomPrice;
                
                // DIAGNOSTIC LOG: Zone Style
                Print("✅ Zone ", zoneCount + 1, " [Level ", i, ", Step ", levels[i].logicalStep, "]:");
                Print("   Name: ", outZones[zoneCount].name);
                Print("   Color: ", ColorToString(outZones[zoneCount].clr));
                Print("   Top: ", DoubleToString(outZones[zoneCount].topPrice, Digits));
                Print("   Bottom: ", DoubleToString(outZones[zoneCount].bottomPrice, Digits));
                Print("   Type: ", classifications[i].isStructure ? "STRUCTURE" : "TRIGGER");
                
                zoneCount++;
            }
            else {
                if(!geometries[i].isValid) {
                    Print("⏭️ Level ", i, " [Step ", levels[i].logicalStep, "]: SKIPPED (Invalid Geometry)");
                }
                else if(!classifications[i].isActive) {
                    Print("⏭️ Level ", i, " [Step ", levels[i].logicalStep, "]: SKIPPED (Inactive)");
                }
            }
        }
    }
    else {
        Print("⚠️ Zone Display is DISABLED (config.showZones = false)");
    }
    
    ArrayResize(outZones, zoneCount);
    
    Print("───────────────────────────────────────────────────────────");
    Print("✅ ResolveZoneStyles Summary:");
    Print("   Zones Prepared for Rendering: ", zoneCount);
    Print("═══════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Render Zones (Optimized - Using ZoneFactory)                     |
//| رسم زون‌ها (بهینه‌شده - با استفاده از ZoneFactory)              |
//|                                                                  |
//| REFACTORED: Now uses ZoneFactory for consistency and DRY        |
//| REFACTOR شده: حالا از ZoneFactory برای یکپارچگی استفاده می‌کند  |
//| FIXED: Respects Hide state when rendering zones                 |
//+------------------------------------------------------------------+
void RenderZones(const SZoneRenderInfo &zones[])
{
    int count = ArraySize(zones);
    
    // CRITICAL: Enforce zone limit
    if(count > MAX_ZONES_PER_CHART) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("⚠️ RenderZones: Zone count (", count, ") exceeds limit (", MAX_ZONES_PER_CHART, ")");
        #endif
        count = MAX_ZONES_PER_CHART;
    }
    
    // CRITICAL FIX: Check if indicator is hidden
    // اگر اندیکاتور مخفی است، زون‌ها را رسم نکن
    // PERFORMANCE: Use cached ChartID string
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    bool isHidden = GlobalVariableCheck(gvar_name) && (bool)GlobalVariableGet(gvar_name);
    
    // Performance tracking
    int zonesCreated = 0;
    int zonesFailed = 0;
    
    // ═══════════════════════════════════════════════════════════════
    // BATCH RENDERING USING ZONE FACTORY
    // رسم دسته‌ای با استفاده از Zone Factory
    // ═══════════════════════════════════════════════════════════════
    
    for(int i = 0; i < count; i++) {
        if(!zones[i].isVisible) continue;
        
        // ═══════════════════════════════════════════════════════════
        // DELEGATE TO ZONE FACTORY (DRY Principle)
        // واگذاری به Zone Factory (اصل DRY)
        // ═══════════════════════════════════════════════════════════
        
        SZoneCreationRequest request;
        request.name = zones[i].name;
        request.topPrice = zones[i].topPrice;
        request.bottomPrice = zones[i].bottomPrice;
        request.zoneColor = zones[i].clr;
        request.transparency = zones[i].transparency;
        request.filled = zones[i].filled;
        request.startTime = 0;  // Auto-calculate by Factory
        request.endTime = 0;    // Auto-calculate by Factory
        
        SZoneCreationResult result = CreateZone(request);
        
        if(result.success) {
            zonesCreated++;
            
            // CRITICAL FIX: If indicator is hidden, hide the zone immediately
            // اگر اندیکاتور مخفی است، زون را فوراً مخفی کن
            if(isHidden) {
                ObjectSetInteger(0, zones[i].name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            }
        }
        else {
            zonesFailed++;
            #ifdef ENABLE_DEBUG_LOGS
            Print("❌ RenderZones: Factory failed for '", zones[i].name, "' - ", 
                  result.errorMessage, " (Code: ", result.errorCode, ")");
            #endif
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // UPDATE METRICS
    // به‌روزرسانی معیارها
    // Note: Factory handles both create and update internally
    // توجه: Factory هم create و هم update را داخلی مدیریت می‌کند
    // ═══════════════════════════════════════════════════════════════
    g_zoneMetrics.totalZonesCreated += zonesCreated;
    g_zoneMetrics.totalZonesFailed += zonesFailed;
    g_zoneMetrics.totalRenderCalls++;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ RenderZones (Factory): Processed=", zonesCreated, ", Failed=", zonesFailed, 
          ", Hidden=", (isHidden ? "YES" : "NO"));
    #endif
}

//+------------------------------------------------------------------+
//| Render Lines                                                      |
//| رسم خطوط                                                          |
//| FIXED: Respects Hide state and Lines visibility toggle          |
//+------------------------------------------------------------------+
void RenderLines(const SLineRenderInfo &lines[])
{
    int count = ArraySize(lines);
    int visibleCount = 0;
    
    // CRITICAL FIX: Check if indicator is hidden
    // اگر اندیکاتور مخفی است، خطوط را رسم نکن
    // PERFORMANCE: Use cached ChartID string
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    bool isHidden = GlobalVariableCheck(gvar_name) && (bool)GlobalVariableGet(gvar_name);
    
    // PERF FIX: Batch property updates to reduce API calls
    for(int i = 0; i < count; i++) {
        // Create or update line object
        bool objectExists = (ObjectFind(0, lines[i].name) >= 0);
        
        if(!objectExists) {
            if(!ObjectCreate(0, lines[i].name, OBJ_HLINE, 0, 0, lines[i].price)) {
                int error = GetLastError();
                #ifdef ENABLE_DEBUG_LOGS
                Print("❌ RenderLines: Failed to create line: ", lines[i].name,
                      ", Error: ", error);
                #endif
                
                // CRITICAL: Cleanup partial object before continue
                if(ObjectFind(0, lines[i].name) >= 0) {
                    ObjectDelete(0, lines[i].name);
                }
                continue;
            }
        }
        else {
            ObjectSetDouble(0, lines[i].name, OBJPROP_PRICE, lines[i].price);
        }
        
        // PERF FIX: Set visual properties in batch (reduces overhead)
        ObjectSetInteger(0, lines[i].name, OBJPROP_COLOR, lines[i].clr);
        ObjectSetInteger(0, lines[i].name, OBJPROP_STYLE, lines[i].style);
        ObjectSetInteger(0, lines[i].name, OBJPROP_WIDTH, lines[i].width);
        ObjectSetInteger(0, lines[i].name, OBJPROP_SELECTABLE, lines[i].selectable);
        ObjectSetInteger(0, lines[i].name, OBJPROP_BACK, false);
        ObjectSetString(0, lines[i].name, OBJPROP_TOOLTIP, lines[i].tooltip);
        
        // Control visibility via TIMEFRAMES property (hide/show without deleting)
        // کنترل نمایش از طریق TIMEFRAMES (مخفی/نمایش بدون حذف)
        // CRITICAL FIX: Respect both Hide state AND Lines visibility toggle
        if(isHidden || !lines[i].isVisible) {
            // Hidden by F key OR hidden by L key
            ObjectSetInteger(0, lines[i].name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        }
        else {
            ObjectSetInteger(0, lines[i].name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
            visibleCount++;
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ RenderLines: Rendered ", visibleCount, " visible lines out of ", count,
          ", Hidden=", (isHidden ? "YES" : "NO"));
    #endif
}

//+------------------------------------------------------------------+
//| Batch Render (Zones First, Then Lines)                           |
//| رسم دسته‌ای (ابتدا زون‌ها، سپس خطوط)                            |
//+------------------------------------------------------------------+
void RenderBatch(const SLineRenderInfo &lines[], const SZoneRenderInfo &zones[])
{
    // Render zones first (background layer)
    RenderZones(zones);
    
    // Render lines second (foreground layer)
    RenderLines(lines);
}

//+------------------------------------------------------------------+
//| Cleanup Objects by Prefix                                        |
//| پاک‌سازی اشیاء با پیشوند                                          |
//+------------------------------------------------------------------+
void CleanupZoneObjects(const string &prefix)
{
    ObjectsDeleteAll(0, prefix, -1, -1);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("✅ CleanupZoneObjects: Deleted all objects with prefix: ", prefix);
    #endif
}
