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
    ApplyTfMaskGuarded(name, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
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
            visited++;
            if(!CacheSlotIsLive(i)) continue;   // P-UI-62: nothing under this name
            ObjectSetInteger(0, g_objectCacheHash[i].name, OBJPROP_TIMEFRAMES, timeframes);
        }
    }
    // P-PERF-02: written OUTSIDE the guard → every stored mask is now stale.
    BumpTfEpoch();
}

//+------------------------------------------------------------------+
//| P-PERF-31: NAME-BASED LINE TEST + CACHE-WALK HIDE/SHOW (weak PCs)|
//|                                                                  |
//| WHY (measured, docs.mql4.com/objects/objectcreate): ObjectCreate |
//| /ObjectFind/ObjectGet* are chart-queue calls — a read waits for  |
//| the queue, so with thousands of objects every per-object probe is |
//| a synchronous roundtrip. The F key walked EVERY object ON THE     |
//| CHART (ObjectsTotal + ObjectName per object, foreign indicators   |
//| included) and the L key probed OBJPROP_TYPE once per cached      |
//| object (~2000 probes per press on a full chart). A weak PC pays   |
//| thousands of roundtrips per keypress; the press after feels dead  |
//| until the next tick paints it.                                   |
//|                                                                  |
//| The object cache already holds every object we created (lines via |
//| CacheUpdateObject, zones via CacheUpdateZone, labels via          |
//| CacheUpdateLabel), so the toggle walks occupied slots only,       |
//| bounded by g_objectCacheSize, with ZERO ObjectName calls. The     |
//| line filter is name-based (LevelPipeline naming: lines are        |
//| <mode>_Above_/_Below_/_Midpoint_, zones carry _Zone_, pip labels  |
//| append _Label) — zero OBJPROP_TYPE probes for decided families.   |
//| Anything the names cannot decide (Factor_High/Low, HTF wicks, ATR |
//| trade lines) falls back to exactly ONE type probe: the old        |
//| behavior, preserved bit-for-bit. exclusions are spelled out here  |
//| (never IsZoneBoxBorderObject: it lives in EventHandlers, included |
//| AFTER this file — P-ARCH-02). Raw writes + the existing epoch     |
//| bump stay: these walks run once per transition (memoised callers),|
//| so guard probes would only add MQL work to writes that are all    |
//| needed anyway.                                                    |
//+------------------------------------------------------------------+
// Decided WITHOUT touching the terminal: true = level line, false =
// decided non-line. Unknown families are NOT decided here — the single
// probe lives in VisibilityIsLineObject below.
bool VisibilityNameDecidesLine(const string nm, bool &isLine)
{
    if(StringFind(nm, "_BK_") >= 0)      { isLine = false; return true; }
    if(StringFind(nm, "_B_Top") >= 0)    { isLine = false; return true; }
    if(StringFind(nm, "_B_Bottom") >= 0) { isLine = false; return true; }
    if(StringFind(nm, "_B_Left") >= 0)   { isLine = false; return true; }
    if(StringFind(nm, "_B_Right") >= 0)  { isLine = false; return true; }
    if(StringFind(nm, "_Zone_") >= 0)    { isLine = false; return true; }
    int nlen = StringLen(nm);
    if(nlen >= 6 && StringSubstr(nm, nlen - 6, 6) == "_Label") { isLine = false; return true; }
    if(StringFind(nm, "_Above_") >= 0)    { isLine = true; return true; }
    if(StringFind(nm, "_Below_") >= 0)    { isLine = true; return true; }
    if(StringFind(nm, "_Midpoint_") >= 0) { isLine = true; return true; }
    if(StringFind(nm, "_Level_") >= 0)    { isLine = true; return true; }
    return false;
}

// The L/F line question with the old exact semantics: name-decided
// families cost zero terminal calls, unknown families pay one probe.
bool VisibilityIsLineObject(const string nm)
{
    bool decided = false;
    if(VisibilityNameDecidesLine(nm, decided)) return decided;
    int objType = (int)ObjectGetInteger(0, nm, OBJPROP_TYPE);
    return (objType == OBJ_HLINE || objType == OBJ_TREND);
}

// Legacy full-chart scan for the attach corner ONLY: a fresh instance
// starts with an empty cache on a chart that still carries the previous
// instance's objects, so the cache walk would touch nothing. Every
// CacheClear in prod accompanies a chart delete, so mid-session the cache
// always covers the chart — this scan never runs in steady state.
void VisibilityHideAllLegacyScan()
{
    int total = ObjectsTotal(0, -1, -1);
    string cachedPrefix = inpObjectPrefix;
    int prefixLen = StringLen(cachedPrefix);
    ushort prefixFirstChar = StringGetCharacter(cachedPrefix, 0);
    long noPeriodsVal = OBJ_NO_PERIODS;
    for(int i = total - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, -1);
        if(StringGetCharacter(objName, 0) != prefixFirstChar) continue;
        if(StringLen(objName) >= prefixLen && StringSubstr(objName, 0, prefixLen) == cachedPrefix)
        {
            if(StringFind(objName, "_BK_") >= 0) continue;   // P-BK-01
            ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, noPeriodsVal);
        }
    }
}

//+------------------------------------------------------------------+
// P-PERF-41 - ONE OWNER FOR "MAY THIS MID-ZONE OBJECT BE PAINTED?"
//
// The mid-zone family is switched by `g_showMidZones`. Two other owners also
// write OBJPROP_TIMEFRAMES on the same objects - the F key (hide/show all) and
// the L key (line mask) - and before this the F show path had NO notion of the
// zone switch at all: it repainted every non-line object OBJ_ALL_PERIODS, zone
// rectangles included. So "zones off" survived exactly until the next F press.
// That disagreement is the second half of the report "it doesn't turn on/off
// properly, not like F": the two controls were answering different questions.
//
// The predicate lives here, above every caller, so the show path, the family
// walk and the per-zone render writer (LevelPipeline) cannot drift apart.
//+------------------------------------------------------------------+

// A pipeline zone's boundary line is `_Top`/`_Bottom`; the empty-box border
// segments (_B_Top/_B_Bottom/_B_Left/_B_Right) follow the BOX, not L. Both are
// inside the `_Zone_` family, so the walk has to tell them apart.
bool IsZoneBoundaryLineName(const string nm)
{
    if(StringFind(nm, "_B_") >= 0) return false;   // box border: follows the box
    int n = StringLen(nm);
    if(n > 4 && StringSubstr(nm, n - 4, 4) == "_Top")    return true;
    if(n > 7 && StringSubstr(nm, n - 7, 7) == "_Bottom") return true;
    return false;
}

// The whole visibility decision for one zone object, in one place: the family
// switch, then the boundary-line switch, then the F (hide-all) mask.
long VisibilityZoneMask(const string nm, const bool zonesVisible, const bool linesVisible)
{
    if(!zonesVisible) return OBJ_NO_PERIODS;
    if(IsZoneBoundaryLineName(nm) && !linesVisible) return OBJ_NO_PERIODS;
    return IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
}

void VisibilityShowAllLegacyScan(const bool atrShouldShow, const bool showAtrTargets,
                                 const bool triggersEnabled, const bool linesVisible,
                                 const bool zonesVisible)
{
    int total = ObjectsTotal(0, -1, -1);
    string cachedPrefix = inpObjectPrefix;
    int prefixLen = StringLen(cachedPrefix);
    ushort prefixFirstChar = StringGetCharacter(cachedPrefix, 0);
    for(int i = total - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i, -1, -1);
        if(StringGetCharacter(objName, 0) != prefixFirstChar) continue;
        if(StringLen(objName) >= prefixLen && StringSubstr(objName, 0, prefixLen) == cachedPrefix)
        {
            if(StringFind(objName, "_BK_") >= 0) continue;   // P-BK-01: Base/Knot layer ignores F
            // P-PERF-41: the zone family answers to its own switch FIRST - the
            // rectangle is not a "line", so the lines branch below would have
            // shown it no matter what the zone switch said.
            if(StringFind(objName, "_Zone_") >= 0)
            {
                ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES,
                                 VisibilityZoneMask(objName, zonesVisible, linesVisible));
                continue;
            }
            bool isATRObject = (StringFind(objName, "ATR_") >= 0);
            if(isATRObject) {
                if(!atrShouldShow) {
                    ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                } else {
                    if(StringFind(objName, "ATR_Targets_") >= 0 && !showAtrTargets)
                        ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                    else
                        ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                }
                continue;
            }
            bool isTriggerObject = (StringFind(objName, "TriggerTH_Up_") >= 0 ||
                                    StringFind(objName, "TriggerTH_Down_") >= 0);
            if(isTriggerObject && !triggersEnabled)
            {
                ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            }
            else if(!linesVisible)
            {
                int objType = (int)ObjectGetInteger(0, objName, OBJPROP_TYPE);
                // Box borders are spelled out (P-ARCH-02: IsZoneBoxBorderObject
                // lives in EventHandlers, above this file).
                bool isBoxBorder = (StringFind(objName, "_B_Top") >= 0 ||
                                    StringFind(objName, "_B_Bottom") >= 0 ||
                                    StringFind(objName, "_B_Left") >= 0 ||
                                    StringFind(objName, "_B_Right") >= 0);
                if((objType == OBJ_HLINE || objType == OBJ_TREND) && !isBoxBorder)
                {
                    ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                }
                else
                {
                    ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                }
            }
            else
            {
                ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
            }
        }
    }
}

// F-hide over the cache: no ObjectName calls, no type probes (hiding needs
// no classification). Returns writes issued, or -1 when the legacy scan ran.
int VisibilityHideAllCached()
{
    if(g_objectCacheSize == 0) { VisibilityHideAllLegacyScan(); return -1; }
    int touched = 0;
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++)
    {
        if(!g_objectCacheHash[i].occupied) continue;
        visited++;
        // P-UI-62: occupancy bounds the scan, LIVENESS is the permission to touch the
        // chart. A dead slot (a name this chart does not carry - see
        // SObjectCacheEntry.exists) would otherwise cost one terminal write that does
        // nothing, and the walks below write on every full frame.
        if(!CacheSlotIsLive(i)) continue;
        const string nm = g_objectCacheHash[i].name;
        if(StringFind(nm, "_BK_") >= 0) continue;   // P-BK-01
        ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        touched++;
    }
    return touched;
}

// F-show over the cache: same decision tree the full-chart loop always had
// (ATR state, trigger state, lines state), line test without probes.
int VisibilityShowAllCached(const bool atrShouldShow, const bool showAtrTargets,
                            const bool triggersEnabled, const bool linesVisible,
                            const bool zonesVisible)
{
    if(g_objectCacheSize == 0)
    {
        VisibilityShowAllLegacyScan(atrShouldShow, showAtrTargets, triggersEnabled, linesVisible,
                                    zonesVisible);
        return -1;
    }
    int touched = 0;
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++)
    {
        if(!g_objectCacheHash[i].occupied) continue;
        visited++;
        // P-UI-62: occupancy bounds the scan, LIVENESS is the permission to touch the
        // chart. A dead slot (a name this chart does not carry - see
        // SObjectCacheEntry.exists) would otherwise cost one terminal write that does
        // nothing, and the walks below write on every full frame.
        if(!CacheSlotIsLive(i)) continue;
        const string nm = g_objectCacheHash[i].name;
        if(StringFind(nm, "_BK_") >= 0) continue;   // P-BK-01: Base/Knot layer ignores F
        // P-PERF-41: the zone family answers to its OWN switch (and to L for its
        // boundary lines) - one predicate, shared with the family walk and the
        // render writer, so "zones off" cannot survive an F press again.
        if(StringFind(nm, "_Zone_") >= 0)
        {
            ApplyTfMaskGuarded(nm, VisibilityZoneMask(nm, zonesVisible, linesVisible));
            touched++;
            continue;
        }
        bool isATRObject = (StringFind(nm, "ATR_") >= 0);
        if(isATRObject) {
            if(!atrShouldShow) {
                ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            } else {
                if(StringFind(nm, "ATR_Targets_") >= 0 && !showAtrTargets)
                    ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                else
                    ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
            }
            touched++;
            continue;
        }
        bool isTriggerObject = (StringFind(nm, "TriggerTH_Up_") >= 0 ||
                                StringFind(nm, "TriggerTH_Down_") >= 0);
        if(isTriggerObject && !triggersEnabled)
        {
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        }
        else if(!linesVisible)
        {
            if(VisibilityIsLineObject(nm))
            {
                ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            }
            else
            {
                ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
            }
        }
        else
        {
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        }
        touched++;
    }
    return touched;
}
//|                                                                  |
//| The L hotkey did this instead:                                     |
//|                                                                    |
//|     int total = ObjectsTotal(0, -1, -1);                           |
//|     for(i = 0; i < total; i++) {                                   |
//|         string nm = ObjectName(0, i, -1, -1);   // ONE PER OBJECT  |
//|         ...ObjectGetInteger(...OBJPROP_TYPE)... // ONE PER OBJECT  |
//|         ObjectSetInteger(...OBJPROP_TIMEFRAMES, ...)               |
//|     }                                                              |
//|                                                                    |
//| i.e. two terminal calls for EVERY object on the chart (ours, other |
//| indicators', MT4's own) plus one WRITE per line whether or not the |
//| mask changed — on a chart that carries thousands of our own zone   |
//| rectangles and a few hundred level lines. That is the "with any    |
//| key everything on my chart is touched again" the user reports.     |
//|                                                                    |
//| This walk is the same repair done right: it iterates the OBJECT    |
//| CACHE (only objects WE created, bounded by g_objectCacheSize, zero  |
//| ObjectName calls), filters to the line types, and applies the exact |
//| same exclusions the hotkey had:                                     |
//|   - the empty-box border segments (_B_Top/_B_Bottom/_B_Left/Right)  |
//|     belong to the F switch, not to L;                                |
//|   - Base/Knot trade rays (`_BK_`) are never level lines (P-BK-01).   |
//| The exclusions are spelled out here rather than calling             |
//| IsZoneBoxBorderObject() because that lives in EventHandlers, which  |
//| is included AFTER this file (MQL4 has no clean forward declaration).|
//+------------------------------------------------------------------+
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
            if(!CacheSlotIsLive(i)) continue;                          // P-UI-62
            const string nm = g_objectCacheHash[i].name;
            if(StringFind(nm, "_BK_") >= 0) continue;                 // P-BK-01
            if(StringFind(nm, "_B_Top") >= 0) continue;               // F key's family
            if(StringFind(nm, "_B_Bottom") >= 0) continue;
            if(StringFind(nm, "_B_Left") >= 0) continue;
            if(StringFind(nm, "_B_Right") >= 0) continue;
            // P-PERF-31: name-decided families skip the OBJPROP_TYPE probe
            // (one synchronous chart-queue roundtrip each); unknown families
            // probe exactly once inside VisibilityIsLineObject.
            if(!VisibilityIsLineObject(nm)) continue;
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, timeframes);
        }
    }
    // P-PERF-02: written OUTSIDE the guard → every stored mask is now stale.
    BumpTfEpoch();
}

//==============================================================================
// VISIBILITY WRITE GUARD (P-PERF-02) — THE ONE OWNER of OBJPROP_TIMEFRAMES
//
// OBJPROP_TIMEFRAMES was the field this indicator wrote MOST and needed
// LEAST: every heavy frame re-asserted the mask of every line, label and zone
// it had ever created (hundreds of objects), and MT4 marks the chart dirty on
// each write, so the terminal repainted for a value that had not changed.
//
// The guard answers ONE question per object — "would this write change
// anything?" — with the value the cache says we last wrote plus a global
// EPOCH. Any change made outside this guard (the F/L keys, a bulk show/hide,
// a template load, a cache wipe) only has to bump the epoch: the next pass
// then re-asserts every mask exactly once and the steady state is free.
//==============================================================================
static int g_tfEpoch = 1;

int  GetTfEpoch() { return g_tfEpoch; }

// Invalidate every stored mask. Call it whenever visibility was changed by a
// writer that does NOT go through ApplyTfMaskGuarded (or when the objects we
// cached may no longer exist).
void BumpTfEpoch()
{
    g_tfEpoch++;
    if(g_tfEpoch <= 0) g_tfEpoch = 1;   // overflow guard
}

// Returns true only when a real ObjectSetInteger reached the chart.
bool ApplyTfMaskGuarded(const string name, const long mask)
{
    long haveMask = 0;
    int  haveEpoch = 0;
    if(CacheGetTfMask(name, haveMask, haveEpoch) &&
       haveEpoch == g_tfEpoch && haveMask == mask)
        return false;   // pixels already match — zero syscalls, zero repaint

    if(!ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, mask))
        return false;   // no such object: never remember a mask for nothing

    CacheSetTfMask(name, mask, g_tfEpoch);
    return true;
}

//==============================================================================
// P-PERF-41 - THE MID-ZONE FAMILY SWITCH IS A MASK, NOT A DESTRUCTION
//
// The family used to be turned off by DELETING it (the cleanup walk started at
// 0 when `zonesEnabled` was false) and turned back on by RE-CREATING it: ~7
// terminal calls per zone per direction - `CreateZone` plus seven mask writes,
// or seven `ObjectDelete` - for a switch that moves no price and no geometry.
// That is why "turning the levels/zones on and off" was slow, and why it felt
// different from the F key, which has always been a mask.
//
// A hidden object costs nothing to draw (MT4 culls it before rasterising) and
// the guarded writer makes a repeat call free, so the OFF state is now the SAME
// sort of change L makes: one mask per object. It also removes the whole class
// of "the delete walk missed an index" ghosts - this walk is driven by the
// OBJECT CACHE, so it names every zone object we ever created, with zero index
// assumptions and zero ObjectFind probes.
//==============================================================================

// The COLD-CACHE corner the cache walk cannot cover on its own: a timeframe
// switch CLEARS the object cache (OnDeinit -> CacheClear) but KEEPS the family
// on the chart, so the fresh instance's walk sees zero zone names while the old
// rectangles are still painted with the previous timeframe's prices. The F key
// answers the same corner with a chart scan; this does too, filtered to our
// prefix, and latched to the draw generation so a chart that genuinely holds no
// zones is not rescanned on every scroll or zoom. Objects the scan finds are
// adopted by ApplyTfMaskGuarded (it caches the name it just wrote), so the next
// frame is back on the O(1) walk.
int HideZoneFamilyLegacyScan()
{
    // The generation latch is sound, unlike the one P-PERF-41e removed: it is not
    // guessing at an input, it records "the chart scan for this draw generation is
    // already done". A wipe or a cache clear bumps the generation, and the names
    // the scan finds are ADOPTED by ApplyTfMaskGuarded, so a repeat scan is not
    // even reachable once the family is known.
    static int s_scannedGen = -1;
    if(s_scannedGen == g_drawGeneration) return 0;
    s_scannedGen = g_drawGeneration;

    const string pfx = inpObjectPrefix;
    const int    plen = StringLen(pfx);
    if(plen == 0) return 0;
    const bool linesOn = GetCachedLinesVisible();

    int touched = 0;
    int total = ObjectsTotal(0, -1, -1);
    for(int i = total - 1; i >= 0; i--)
    {
        const string nm = ObjectName(0, i, -1, -1);
        if(StringLen(nm) < plen || StringSubstr(nm, 0, plen) != pfx) continue;
        if(StringFind(nm, "_Zone_") < 0) continue;   // lines / labels / HTF
        if(StringFind(nm, "_BK_") >= 0) continue;    // independent layer (P-BK-01)
        if(ApplyTfMaskGuarded(nm, VisibilityZoneMask(nm, false, linesOn)))
            touched++;
    }
    return touched;
}

// Apply the family switch to EVERY mid-zone object (box, boundary lines, box
// borders) in one cache walk. Returns the number of masks that reached the
// chart. Called from the render's OFF branch - see LevelPipeline P-PERF-41.
//------------------------------------------------------------------------------
// P-PERF-41e: NO STATE LATCH HERE - A GUARD WHOSE INPUT IS CONSTANT IS A LATCH.
//
// This function is called from exactly ONE place, the render's `!zonesEnabled`
// branch, so `zonesVisible` is ALWAYS false when it arrives. A guard keyed on it
// (`if(zonesVisible == last && hidden == last && lines == last && epoch == last)
// return 0;`) could therefore never observe the transition it claimed to detect,
// and it latched the walk off permanently after the first OFF press:
//
//   press 1  -> OFF: zones hidden                        (works)
//   press 2  -> ON : the render re-shows them through the guarded writer, which
//                    by design does NOT bump the epoch (a real mask change must
//                    stay free, so ApplyTfMaskGuarded only caches what it wrote)
//   press 3  -> OFF: key identical to press 1 -> `return 0` -> zones STAY VISIBLE
//
// ...and every later press repeats press 3. That is the reported "it doesn't
// turn on/off properly" - and it was introduced by the guard, not by the mask.
//
// The SOUND guard is the per-object one: ApplyTfMaskGuarded compares the mask we
// want against the mask we last WROTE FOR THAT OBJECT, which is exactly the right
// granularity - it is free when that object is already right, and it can never be
// blind to a transition because it does not summarise state at all. The walk is
// also the cheap half: while the family is off it costs one hash probe per cached
// name and ZERO terminal writes, where the ON render pays eight guarded calls per
// zone. So there is nothing to buy by summarising, and this is the one class of
// "optimisation" whose failure mode is a control that stops working.
//------------------------------------------------------------------------------
// No boolean parameter on purpose (P-PERF-41e). There is exactly ONE caller -
// the render's `if(!config.zonesEnabled)` branch - so "the family is off" is a
// constant here, and a constant passed in as a parameter is what invited the
// unsound latch described above: it LOOKS like a variable to compare against.
// Passing OBJ_NO_PERIODS' decision as the literal `false` at the point of use
// makes that mistake unwritable rather than merely gated.
int HideAllZoneFamilyObjects()
{
    const bool linesOn = GetCachedLinesVisible();
    int touched = 0;
    int seen = 0;
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++)
    {
        if(!g_objectCacheHash[i].occupied) continue;
        visited++;
        // P-UI-62: occupancy bounds the scan, LIVENESS is the permission to touch the
        // chart. A dead slot (a name this chart does not carry - see
        // SObjectCacheEntry.exists) would otherwise cost one terminal write that does
        // nothing, and the walks below write on every full frame.
        if(!CacheSlotIsLive(i)) continue;
        const string nm = g_objectCacheHash[i].name;
        if(StringLen(nm) == 0) continue;
        if(StringFind(nm, "_Zone_") < 0) continue;   // lines / labels / HTF
        if(StringFind(nm, "_BK_") >= 0) continue;    // independent layer (P-BK-01)
        seen++;
        if(ApplyTfMaskGuarded(nm, VisibilityZoneMask(nm, false, linesOn)))
            touched++;
    }
    // "The cache knows no zone name" is the only state in which a chart scan can
    // still find something the walk cannot see (see the note above).
    if(seen == 0) touched += HideZoneFamilyLegacyScan();
    return touched;
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
    // P-PERF-02: a frame-level flip invalidates every stored mask ONCE (the
    // old per-object "write every 10th frame" spray is gone).
    if(g_visibilityChangedThisFrame) BumpTfEpoch();
    g_prevFrameVisibilityLines = g_frameVisibilityLines;
    g_prevFrameVisibilityNonLines = g_frameVisibilityNonLines;
}

void ApplyVisibilityState(const string name, const bool isLine)
{
    long tf = (isLine ? g_frameVisibilityLines : g_frameVisibilityNonLines) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    ApplyTfMaskGuarded(name, tf);
}

void ApplyVisibilityStateIfUnchangedSkip(const string name, const bool isLine)
{
    long tf = (isLine ? g_frameVisibilityLines : g_frameVisibilityNonLines) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    ApplyTfMaskGuarded(name, tf);
}

#endif // VISIBILITY_MANAGER_MQH
