  #ifndef VISIBILITY_MANAGER_MQH
#define VISIBILITY_MANAGER_MQH

#property strict

#include "GlobalVariables.mqh"
#include "ConstantsAndEnums.mqh"

static bool g_linesVisibleCached = true;
static uint g_linesVisibleCacheTime = 0;
static const int LINES_VISIBLE_CACHE_TTL_MS = 100;

bool GetCachedLinesVisible()
{
    uint now = GetTickCount();
    if((int)(now - g_linesVisibleCacheTime) > LINES_VISIBLE_CACHE_TTL_MS) {
        g_linesVisibleCached = g_linesVisible;
        g_linesVisibleCacheTime = now;
    }
    return g_linesVisibleCached;
}

void UpdateLinesVisibleCache(bool visible)
{
    g_linesVisibleCached = visible;
    g_linesVisibleCacheTime = GetTickCount();
}

void InvalidateLinesVisibleCache() { g_linesVisibleCacheTime = 0; }

void InvalidateAllVisibilityCaches()
{
    InvalidateLinesVisibleCache();
}

void SetObjectVisibility(const string name, const bool visible)
{
    if(ObjectFind(0, name) < 0) return;
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

void SetAllTHObjectsVisibility(const bool visible)
{
    static bool s_lastAllTHVisible = true;
    static bool s_allTHInit = false;
    if(s_allTHInit && s_lastAllTHVisible == visible) return;
    s_allTHInit = true;
    s_lastAllTHVisible = visible;

    long timeframes = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    // PERF FIX: Early-exit loop based on occupied count — avoids scanning
    // all 32768 buckets when only a small number of objects are cached.
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++) {
        if(g_objectCacheHash[i].occupied) {
            ObjectSetInteger(0, g_objectCacheHash[i].name, OBJPROP_TIMEFRAMES, timeframes);
            visited++;
        }
    }
}

void SetAllLineObjectsVisibility(const bool visible)
{
    static bool s_lastAllLineVisible = true;
    static bool s_allLineInit = false;
    if(s_allLineInit && s_lastAllLineVisible == visible) return;
    s_allLineInit = true;
    s_lastAllLineVisible = visible;

    long timeframes = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    // PERF FIX: Early-exit loop based on occupied count
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++) {
        if(g_objectCacheHash[i].occupied) {
            visited++;
            int objType = (int)ObjectGetInteger(0, g_objectCacheHash[i].name, OBJPROP_TYPE);
            if(objType == OBJ_HLINE || objType == OBJ_TREND) {
                ObjectSetInteger(0, g_objectCacheHash[i].name, OBJPROP_TIMEFRAMES, timeframes);
            }
        }
    }
}

// Per-frame visibility state tracking
static bool g_frameVisibilityLines = true;
static bool g_frameVisibilityNonLines = true;
static bool g_prevFrameVisibilityLines = true;
static bool g_prevFrameVisibilityNonLines = true;
static bool g_visibilityChangedThisFrame = true;
static int g_visibilityFrameCounter = 0;

void CacheRefreshVisibilityState()
{
    g_visibilityFrameCounter++;
    bool hidden = IsIndicatorHidden();
    g_frameVisibilityNonLines = !hidden;
    g_frameVisibilityLines = !hidden && GetCachedLinesVisible();
    
    g_visibilityChangedThisFrame = (g_frameVisibilityLines != g_prevFrameVisibilityLines) ||
                                    (g_frameVisibilityNonLines != g_prevFrameVisibilityNonLines);
    g_prevFrameVisibilityLines = g_frameVisibilityLines;
    g_prevFrameVisibilityNonLines = g_frameVisibilityNonLines;
}

void ApplyVisibilityState(const string name, const bool isLine)
{
    long tf = (isLine ? g_frameVisibilityLines : g_frameVisibilityNonLines) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tf);
}

void ApplyVisibilityStateIfUnchangedSkip(const string name, const bool isLine)
{
    if(!g_visibilityChangedThisFrame && (g_visibilityFrameCounter % 10) != 0) return;
    long tf = (isLine ? g_frameVisibilityLines : g_frameVisibilityNonLines) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tf);
}

#endif // VISIBILITY_MANAGER_MQH
