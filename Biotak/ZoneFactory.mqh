  //+------------------------------------------------------------------+
//|                                                   ZoneFactory.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                          Factory Pattern for Zone Creation       |
//+------------------------------------------------------------------+
#ifndef ZONE_FACTORY_MQH
#define ZONE_FACTORY_MQH
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#include "ConstantsAndEnums.mqh"

#include "ObjectCache.mqh"

//+------------------------------------------------------------------+
//| Zone Factory - Centralized Zone Creation                         |
//|        Zone -             Zone                                   |
//|                                                                  |
//| BENEFITS:                                                        |
//| - Single point of zone creation (DRY)                           |
//| - Consistent validation                                          |
//| - Easy to extend with new zone types                            |
//| - Testable in isolation                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Zone Creation Request                                            |
//|              Zone                                                |
//+------------------------------------------------------------------+
struct SZoneCreationRequest {
    string name;              // Zone name
    double topPrice;          // Top boundary
    double bottomPrice;       // Bottom boundary
    color zoneColor;          // Zone color
    int transparency;         // Transparency (0-100)
    bool filled;              // Draw the BAND (the filled rectangle)
    // P-UI-62: the EDGE is its own half of the picture, not a consequence of `filled`.
    // It used to be exactly `!filled`, which made two states out of three possible
    // pictures and left the third one (band AND edge) unrepresentable - so the card's
    // BORDER / BORDER WIDTH rows could only ever affect the empty state.
    bool outline;             // Draw the EDGE (three border segments)
    int borderStyle;          // Rectangle border line style (STYLE_SOLID/DASH/DOT/...)
    int borderWidth;          // Rectangle border width (1-5)
    datetime startTime;       // Start time (optional, 0 = auto)
    datetime endTime;         // End time (optional, 0 = auto)
};

//+------------------------------------------------------------------+
//| Zone Creation Result                                             |
//|            Zone                                                  |
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
//| Create/update a single box border segment (OBJ_TREND)            |
//|                                                                  |
//| EMPTY boxes are drawn as border segments instead of an           |
//| OBJ_RECTANGLE with OBJPROP_FILL=false, because some MT4 builds   |
//| render the rectangle filled regardless of the FILL flag.         |
//| Border segments guarantee a hollow box on every build.           |
//+------------------------------------------------------------------+
bool CreateOrUpdateZoneBorder(const string name,
                              const datetime t1, const double p1,
                              const datetime t2, const double p2,
                              const color clr, const int style, const int width,
                              const bool rayRight)
{
    // Cache-based change detection (same pattern as other zone objects)
    SObjectCacheEntry cachedEntry;
    bool hasCached = CacheGetObject(name, cachedEntry);
    bool objectExists = false;
    if(hasCached && cachedEntry.exists) {
        objectExists = (ObjectFind(0, name) >= 0);
        if(!objectExists) {
            CacheRemoveObject(name);
            hasCached = false;
        }
    } else {
        objectExists = (ObjectFind(0, name) >= 0);
    }
    
    // Migrate non-TREND leftovers (e.g. old rectangles with same name)
    if(objectExists) {
        int objType = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
        if(objType != OBJ_TREND) {
            ObjectDelete(0, name);
            CacheRemoveObject(name);
            objectExists = false;
            hasCached = false;
        }
    }
    
    if(!objectExists) {
        if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) return false;
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_CHART_ZONE);   // P-UI-31
        CacheUpdateZone(name, p1, p2, t1, t2, clr, true, style, width);
        return true;
    }
    
    bool geometryChanged = (!hasCached || cachedEntry.lastPrice != p1 || cachedEntry.lastPrice2 != p2 ||
                            cachedEntry.lastTime1 != t1 || cachedEntry.lastTime2 != t2);
    if(geometryChanged) {
        ObjectMove(0, name, 0, t1, p1);
        ObjectMove(0, name, 1, t2, p2);
    }
    bool visualChanged = (!hasCached || cachedEntry.lastColor != clr ||
                          cachedEntry.lastStyle != style || cachedEntry.lastWidth != width);
    if(visualChanged) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
    }
    CacheUpdateZone(name, p1, p2, t1, t2, clr, true, style, width);
    return true;
}

//+------------------------------------------------------------------+
//| Create Zone with Full Validation - GOLD VERSION v3 FINAL         |
//|      Zone                    -            v3                     |
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
    
    //                                                                
    // PHASE 1: VALIDATION (Fail Fast)
    //                                                                
    
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
        Print("   CreateZone: Transparency clamped from ", originalTransparency, " to 0");
        #endif
    }
    if(clampedTransparency > 100) {
        clampedTransparency = 100;
        #ifdef ENABLE_DEBUG_LOGS
        Print("   CreateZone: Transparency clamped from ", originalTransparency, " to 100");
        #endif
    }
    
    // Validate/clamp border style and width (defensive - callers pass inputs)
    int borderStyle = request.borderStyle;
    if(borderStyle < STYLE_SOLID || borderStyle > STYLE_DASHDOTDOT) borderStyle = STYLE_SOLID;
    int borderWidth = request.borderWidth;
    if(borderWidth < 1 || borderWidth > 5) borderWidth = 1;
    
    //                                                                
    // PHASE 2: TIME CALCULATION (Optimized - No slow GlobalVariables)
    //                                                                
    
    int safeBars = Bars;
    datetime currentTime = (safeBars > 0) ? Time[0] : TimeCurrent();
    if(currentTime <= 0) currentTime = TimeCurrent();
    
    datetime startTime = request.startTime;
    datetime endTime = request.endTime;
    
    // Auto-calculate times if not provided
    if(startTime == 0) {
        if(safeBars < 1) {
            result.errorMessage = "Not enough bars for zone creation";
            result.errorCode = ERR_ZONE_RENDER_FAILED;
            return result;
        }
        
        int startIndex = safeBars - 1;
        startTime = Time[startIndex];
        
        if(startTime <= 0) {
            result.errorMessage = StringFormat("Invalid Time[%d]", startIndex);
            result.errorCode = ERR_ZONE_RENDER_FAILED;
            return result;
        }
    }
    
    if(endTime == 0) {
        // PERF FIX: Use cached PeriodSeconds — same value for entire timeframe session
        int periodSeconds = GetCachedPeriodSecondsGlobal();
        if(periodSeconds <= 0) {
            result.success = false;
            result.errorCode = ERR_ZONE_INVALID_CONFIG;
            result.errorMessage = "Invalid timeframe period";
            return result;
        }
        endTime = currentTime + periodSeconds * ZONE_EXTENSION_PERIODS;
    }
    
    // Validate time range
    if(startTime <= 0 || endTime <= startTime) {
        result.errorMessage = StringFormat("Invalid time range: Start=%s, End=%s",
                                          TimeToString(startTime),
                                          TimeToString(endTime));
        result.errorCode = ERR_ZONE_RENDER_FAILED;
        return result;
    }
    
    //                                                                
    // PHASE 3: CALCULATE FINAL COLOR & CHECK CACHE
    //                                                                
    
    color finalColor = GetZoneRenderColor(request.zoneColor, clampedTransparency);
    // Transparency applies to the fill (FILLED) AND the border (EMPTY), so the
    // empty-box outline fades exactly like the filled-box color.
    color borderColor = finalColor;

    // P-UI-62: THE PICTURE IS RESOLVED BEFORE ANY DRAWING PATH.
    //
    // The EMPTY picture used to return from ABOVE this read, and that early return IS
    // the reported «Empty درست کار نمیکند»: switching FILLED -> EMPTY drew the three
    // edge segments and left the FILLED RECTANGLE exactly where it was, because the
    // migration meant to remove it (PHASE 3.5) sat BELOW the return and was therefore
    // unreachable in the one picture that needs it. The picture is read once here, and
    // every path below is a consequence of it.
    //
    // A cached entry whose `exists` is false is a PROOF that this zone owns NO
    // rectangle (the edge-only picture: its three segments are the whole zone), so the
    // band path must not probe the chart for it - the P-PERF-07 rule, applied to the
    // cache instead of the absent table. Without it, the band-less pictures paid three
    // ObjectFind probes per zone per render, forever.
    SObjectCacheEntry cache;
    bool inCache = CacheGetObject(request.name, cache);
    bool entrySaysBand = (inCache && cache.exists);
    bool objectExists = false;
    if(inCache && cache.exists) {
        objectExists = (ObjectFind(0, request.name) >= 0);
        if(!objectExists) {
            CacheRemoveObject(request.name);
            inCache = false;
            entrySaysBand = false;
        }
    } else if(!inCache) {
        objectExists = (ObjectFind(0, request.name) >= 0);
        entrySaysBand = objectExists;
    }
    // A picture of the SAME KIND with nothing changed costs zero terminal calls - and
    // that now covers the band-less pictures too. A KIND change is exactly when
    // leftovers can exist, so it is also what the migration below hangs on.
    bool kindChanged = (!inCache) || (entrySaysBand != request.filled) ||
                       (cache.lastOutline != request.outline);
    if(inCache && !kindChanged) {
        // Check if anything actually changed
        bool geometryChanged = (cache.lastPrice != request.topPrice || cache.lastPrice2 != request.bottomPrice ||
                               cache.lastTime1 != startTime || cache.lastTime2 != endTime);
        bool visualChanged = (cache.lastColor != borderColor || cache.lastFilled != request.filled ||
                             cache.lastStyle != borderStyle || cache.lastWidth != borderWidth);
        
        if(!geometryChanged && !visualChanged) {
            result.success = true;
            return result; // Skip everything!
        }
    }
    
    //                                                                
    // PHASE 3.5: MODE MIGRATION (FILLED <-> EMPTY)                     
    //                                                                
    // Some MT4 builds render OBJ_RECTANGLE filled even with
    // OBJPROP_FILL=false, so EMPTY boxes are drawn as border segments
    // (guaranteed hollow). Keep the chart clean when switching styles.
    // P-PERF-13b: this is the migration that used to run on EVERY render of the
    // zone; it now runs only when the zone is really being (re)built.

    // A legacy sub-object pair from the pre-BOX-06 shape - two terminal probes
    // that are worth nothing on a settled chart. Cache-only (no verify): the
    // cache plus the proven-absent table already answer for our own names.
    DeleteIndicatorObjectManaged(request.name + "_Top");
    DeleteIndicatorObjectManaged(request.name + "_Bottom");

    // P-UI-62: BOTH HALVES, and only when the KIND changed - which is the only moment
    // a leftover can exist. The old shape was `if(!filled) remove the band; else remove
    // the edge`, i.e. it could not express OUTLINED at all (both halves wanted) and it
    // asked the chart with a raw ObjectFind for the edge half. Both are cache-first now
    // (P-PERF-13's rule), so a settled chart pays nothing here.
    if(kindChanged)
    {
        // The BAND half: FILLED/OUTLINED own it, so an edge-only picture must not
        // leave one behind.
        if(!request.filled) {
            DeleteIndicatorObjectManaged(request.name, true);
            CacheRemoveObject(request.name);
            objectExists = false;
        }
        // The EDGE half: EMPTY/OUTLINED own it, so a band-only picture must not leave
        // it behind.
        if(!request.outline) {
            DeleteIndicatorObjectManaged(request.name + "_B_Top");
            DeleteIndicatorObjectManaged(request.name + "_B_Bottom");
            DeleteIndicatorObjectManaged(request.name + "_B_Left");
            DeleteIndicatorObjectManaged(request.name + "_B_Right");
        }
    }    //                                                               
    // PHASE 4: THE BAND (the fill half of the picture)
    //                                                               
    
    // P-UI-62: THE BAND IS (RE)CREATED BEFORE ITS EDGE - THE ORDER IS THE PICTURE.
    //
    // MT4 paints objects of equal ZORDER in CREATION order (the model the Z ladder and
    // zorder-audit are built on), and a band and its own edge deliberately SHARE
    // Z_CHART_ZONE because both are the same thing to every other layer. So whichever
    // half is CREATED last paints on top - and the edge has to win: it is the visible
    // line the card's BORDER / BORDER WIDTH rows style, and a band created after it
    // covers it, which makes OUTLINED indistinguishable from FILLED. Hence the band's
    // rectangle HERE, and the edge further down. The audit asserts this order, because
    // swapping the two blocks is a silent regression, not a visible compile error.
    if(request.filled && !objectExists) {
        if(!ObjectCreate(0, request.name, OBJ_RECTANGLE, 0, startTime, request.topPrice, endTime, request.bottomPrice)) {
            int error = GetLastError();
            result.errorMessage = StringFormat("Failed to create zone '%s': MT4 Error %d", request.name, error);
            result.errorCode = error;
            return result;
        }
        // P-PERF-07's rule running the other way: a name that IS created must clear the
        // negative mark an earlier probe left on it. The edge-only picture really does
        // probe this name and really does find nothing (the band path reads that as
        // proof of absence), so without this line a later delete of a LIVE band would
        // be refused by `CacheIsAbsentKnown` and the rectangle would be left behind.
        CacheForgetAbsent(request.name);
    }
    else if(request.filled) {
        // Update geometry ONLY if changed
        bool geometryChanged = !inCache || (cache.lastPrice != request.topPrice || cache.lastPrice2 != request.bottomPrice ||
                                           cache.lastTime1 != startTime || cache.lastTime2 != endTime);
        if(geometryChanged) {
            ObjectSetDouble(0, request.name, OBJPROP_PRICE1, request.topPrice);
            ObjectSetDouble(0, request.name, OBJPROP_PRICE2, request.bottomPrice);
            ObjectSetInteger(0, request.name, OBJPROP_TIME1, startTime);
            ObjectSetInteger(0, request.name, OBJPROP_TIME2, endTime);
        }
    }
    
    // Apply the BAND's visual properties ONLY if changed - and only for a band
    // (PHASE 4's second half: the half that exists is the half that gets styled).
    bool visualChanged = request.filled &&
                         (!inCache || (cache.lastColor != borderColor || cache.lastFilled != request.filled ||
                                       cache.lastStyle != borderStyle || cache.lastWidth != borderWidth));
    if(visualChanged) {
        ObjectSetInteger(0, request.name, OBJPROP_COLOR, borderColor);
        ObjectSetInteger(0, request.name, OBJPROP_BACK, true);
        ObjectSetInteger(0, request.name, OBJPROP_FILL, request.filled);
        // Border line style/width (solid, dashed, dotted, ... hollow box support)
        ObjectSetInteger(0, request.name, OBJPROP_STYLE, borderStyle);
        ObjectSetInteger(0, request.name, OBJPROP_WIDTH, borderWidth);
        ObjectSetInteger(0, request.name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, request.name, OBJPROP_RAY_RIGHT, true);
        ObjectSetInteger(0, request.name, OBJPROP_ZORDER, Z_CHART_ZONE);   // P-UI-31
    }
    
    // P-UI-62: PHASE 5 - THE EDGE (the outline half of the picture) - AFTER the band,
    // so that it paints on top of it (see the creation-order note above).
    //
    // Three segments rather than one hollow rectangle, because OBJ_RECTANGLE ignores
    // OBJPROP_STYLE/WIDTH: a band has no stylable line of its own, which is exactly why
    // the card's BORDER and BORDER WIDTH rows could do nothing until now. Drawn whenever
    // the picture asks for an edge - EMPTY (edge only) and OUTLINED (band AND edge) -
    // and never otherwise; the migration above has already removed the other half
    // whenever this picture does not own it.
    if(request.outline) {
        bool okEdge = true;
        if(!CreateOrUpdateZoneBorder(request.name + "_B_Top",
                                     startTime, request.topPrice, endTime, request.topPrice,
                                     borderColor, borderStyle, borderWidth, true)) okEdge = false;
        if(!CreateOrUpdateZoneBorder(request.name + "_B_Bottom",
                                     startTime, request.bottomPrice, endTime, request.bottomPrice,
                                     borderColor, borderStyle, borderWidth, true)) okEdge = false;
        if(!CreateOrUpdateZoneBorder(request.name + "_B_Left",
                                     startTime, request.bottomPrice, startTime, request.topPrice,
                                     borderColor, borderStyle, borderWidth, false)) okEdge = false;
        if(!okEdge) {
            result.errorMessage = "Failed to draw the zone edge: " + request.name;
            result.errorCode = ERR_ZONE_RENDER_FAILED;
        }
    }
    
    // Update cache - the picture this zone now carries, INCLUDING whether it owns a
    // rectangle at all (P-UI-62). An edge-only zone caches `exists = false`, which the
    // band path above reads as a PROOF of absence instead of probing for it.
    CacheUpdateZone(request.name, request.topPrice, request.bottomPrice, startTime, endTime, borderColor,
                    request.filled, borderStyle, borderWidth, request.outline, request.filled);
    
    result.success = true;
    return result;
}

//+------------------------------------------------------------------+
//| Batch Create Zones                                               |
//|              Zone                                                |
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
//|         Zone                                                      |
//+------------------------------------------------------------------+
bool DeleteZone(const string &zoneName)
{
    if(StringLen(zoneName) == 0) return false;

    return DeleteManagedZoneObjects(zoneName, true);
}

//+------------------------------------------------------------------+
//| Delete Zones by Prefix                                           |
//|     Zone                                                          |
//+------------------------------------------------------------------+
int DeleteZonesByPrefix(const string &prefix)
{
    if(StringLen(prefix) == 0) return 0;
    
    // PERF FIX: Use ObjectsDeleteAll for the primary bulk delete (single MT4 syscall),
    // then follow up with the sub-object suffixes. This avoids an O(n) manual loop
    // that walks every chart object and calls ObjectFind per item.
    // Also clear the cache for matching entries the same way ClearAllLevels does.
    int deletedCount = 0;
    deletedCount += ObjectsDeleteAll(0, prefix);
    
    // Sub-objects created by CreateZone / CreateOrUpdateZoneBorder
    static string s_zoneSubs[] = {"_Top", "_Bottom", "_B_Top", "_B_Bottom", "_B_Left", "_B_Right"};
    // Note: these share the same prefix, so the ObjectsDeleteAll above already captured them.
    // The cache needs to be invalidated for these too.
    if(g_objectCacheSize > 0) {
        int prefixLen = StringLen(prefix);
        ushort prefixFirstChar = StringGetCharacter(prefix, 0);
        int visited = 0, snapshot = g_objectCacheSize;
        for(int i = 0; i < CACHE_HASH_BUCKETS && visited < snapshot; i++) {
            if(!g_objectCacheHash[i].occupied) continue;
            visited++;
            if(StringGetCharacter(g_objectCacheHash[i].name, 0) != prefixFirstChar) continue;
            if(StringLen(g_objectCacheHash[i].name) >= prefixLen &&
               StringSubstr(g_objectCacheHash[i].name, 0, prefixLen) == prefix) {
                g_objectCacheHash[i].name = "";
                g_objectCacheHash[i].occupied = false;
                g_objectCacheHash[i].deleted = true;
                g_objectCacheHash[i].lastAccess = 0;
                g_objectCacheSize--;
            }
        }
    }
    InvalidateObjectCountCache();
    return deletedCount;
}

#endif // ZONE_FACTORY_MQH
