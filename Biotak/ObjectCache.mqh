  #ifndef OBJECT_CACHE_MQH
#define OBJECT_CACHE_MQH

#property copyright "Biotak"
#property strict

struct SObjectCacheEntry {
    string name;           // Object name
    double lastPrice;      // Last known price (for lines/zones - Price 1)
    double lastPrice2;     // Last known price 2 (for zones)
    datetime lastTime1;    // Last known time 1 (for zones)
    datetime lastTime2;    // Last known time 2 (for zones)
    color lastColor;       // Last known color
    int lastStyle;         // Last known line style
    int lastWidth;         // Last known line width
    string lastText;       // Last known text (for labels)
    bool lastFilled;       // Last known fill state (for zones)
    // P-UI-62: the zone picture is TWO bits, not one. "Filled" is the BAND and
    // "outline" is the edge drawn beside it (three border segments), and the two
    // are independent: FILLED = band only, EMPTY = edge only, OUTLINED = both. A
    // single `lastFilled` bit cannot tell FILLED from OUTLINED, so the picture had
    // no way to say "the band is unchanged but the edge is not" and the edge was
    // never drawn (or never removed) when only that half moved.
    bool lastOutline;      // Last known outline (edge segments) state (for zones)
    // P-UI-62: `exists` is what makes a slot LIVE, and every walk that ACTS on the
    // chart must read it. It is false for two honest reasons: the entry was validated
    // away (CacheValidate proved the name gone), or it describes a picture that owns
    // NO object under this very name - the zone edge-only picture, whose zone name
    // holds nothing and whose three segments are the whole zone. An occupied-but-dead
    // slot is not "an object": a walk that writes to it pays a terminal call for a
    // name the chart does not have, and the write silently does nothing. Use
    // `CacheSlotIsLive(i)` in every enumeration.
    bool exists;           // True if object exists on chart
    datetime lastUpdate;   // Last update timestamp
    // P-PERF-02 visibility/write guards (see VisibilityManager.mqh):
    // lastTfMask = the OBJPROP_TIMEFRAMES mask we were the last to WRITE,
    // tfEpoch    = the visibility epoch it was written under (0 = never).
    // Together they make "re-assert this object's mask" free when nothing
    // changed — the single biggest syscall source in the level pipeline.
    long lastTfMask;
    int  tfEpoch;
    string lastTooltip;    // Last known tooltip (string writes are the next most frequent)
};

// Hash-based cache configuration
#define CACHE_HASH_BUCKETS 32768 // Power of 2 for fast modulo
#define CACHE_MAX_PROBE 32       // Maximum linear probing attempts

// Hash bucket structure
struct SObjectCacheSlot {
    string name;
    SObjectCacheEntry entry;
    bool occupied;
    bool deleted;         // Tombstone sentinel for linear probing
    datetime lastAccess;  // For LRU eviction
};

// Global hash-based cache
static SObjectCacheSlot g_objectCacheHash[CACHE_HASH_BUCKETS];

// P-UI-62: the ONE question every cache walk asks before it touches the chart -
// "does this slot describe an object the chart actually carries?". See the note on
// SObjectCacheEntry.exists for why a live slot and an occupied slot are not the same
// thing, and why writing through the difference is not an error the terminal reports.
bool CacheSlotIsLive(const int idx) {
    return (idx >= 0 && idx < CACHE_HASH_BUCKETS &&
            g_objectCacheHash[idx].occupied && g_objectCacheHash[idx].entry.exists);
}
static bool g_objectCacheHashInitialized = false;
static int g_objectCacheSize = 0;

// PERF: O(1) LRU eviction tracking
static int g_lruMinIdx = -1;
static datetime g_lruMinTime = 0;

// PERF: Cached TimeCurrent() - refreshed once per redraw frame
static datetime g_cacheFrameTime = 0;

void CacheRefreshFrameTime() {
    g_cacheFrameTime = TimeCurrent();
}

datetime CacheGetFrameTime() {
    if(g_cacheFrameTime == 0) g_cacheFrameTime = TimeCurrent();
    return g_cacheFrameTime;
}

// Maximum cache size (about 73% load factor of 32768 buckets)
#define MAX_CACHE_SIZE 24000

int HashObjectName(const string name) {
    uint hash = 5381;
    int len = StringLen(name);
    for(int i = 0; i < len; i++) {
        hash = ((hash << 5) + hash) + (uint)StringGetCharacter(name, i);
    }
    return (int)(hash % (uint)CACHE_HASH_BUCKETS);
}

void InitializeObjectCacheHash() {
    if(g_objectCacheHashInitialized) return;
    // PERF FIX: MQL4 static struct arrays are zero-initialized at program load,
    // so empty string ("") == default for string, false == default for bool,
    // 0 == default for datetime/int.  A single scalar reset of size + sentinels
    // is all that's needed — eliminates the 32768-iteration loop on first call.
    g_objectCacheHashInitialized = true;
    g_objectCacheSize = 0;
    g_lruMinIdx = -1;
    g_lruMinTime = 0;
    _LOG_GATE_I Print("[I][SYNC] Object Cache Hash Initialized (", CACHE_HASH_BUCKETS, " buckets)");
}

int CacheFindIndex(const string name) {
    if(!g_objectCacheHashInitialized) InitializeObjectCacheHash();
    int slot = HashObjectName(name);
    
    for(int probe = 0; probe < CACHE_MAX_PROBE; probe++) {
        int idx = (slot + probe) % CACHE_HASH_BUCKETS;
        if(!g_objectCacheHash[idx].occupied && !g_objectCacheHash[idx].deleted) {
            return -1;  // Empty slot - object not in cache
        }
        
        // Skip tombstone slots
        if(g_objectCacheHash[idx].deleted && !g_objectCacheHash[idx].occupied)
            continue;
        if(g_objectCacheHash[idx].name == name) {
            g_objectCacheHash[idx].lastAccess = CacheGetFrameTime();
            return idx;
        }
    }
    
    return -1;
}

void EvictLRUEntry() {
    if(g_objectCacheSize == 0) return;
    
    // O(1) fast path
    if(g_lruMinIdx >= 0 && g_lruMinIdx < CACHE_HASH_BUCKETS &&
       g_objectCacheHash[g_lruMinIdx].occupied) {
        int lruIdx = g_lruMinIdx;
        _LOG_GATE_D Print("[D][SYNC] [DEL] Evicting LRU cache entry (O(1)): '", g_objectCacheHash[lruIdx].name, "'");
        g_objectCacheHash[lruIdx].name = "";
        g_objectCacheHash[lruIdx].occupied = false;
        g_objectCacheHash[lruIdx].deleted = true;
        g_objectCacheHash[lruIdx].lastAccess = 0;
        g_objectCacheSize--;
        g_lruMinIdx = -1;
        g_lruMinTime = 0;
        return;
    }
    
    // Fallback: Full scan (but using occupied count to exit early)
    int lruIdx = -1;
    datetime oldestAccess = CacheGetFrameTime() + 86400;
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++) {
        if(g_objectCacheHash[i].occupied) {
            visited++;
            if(g_objectCacheHash[i].lastAccess < oldestAccess) {
                oldestAccess = g_objectCacheHash[i].lastAccess;
                lruIdx = i;
            }
        }
    }
    if(lruIdx >= 0) {
        _LOG_GATE_D Print("[D][SYNC] [DEL] Evicting LRU cache entry: '", g_objectCacheHash[lruIdx].name, "'");
        g_objectCacheHash[lruIdx].name = "";
        g_objectCacheHash[lruIdx].occupied = false;
        g_objectCacheHash[lruIdx].deleted = true;
        g_objectCacheHash[lruIdx].lastAccess = 0;
        g_objectCacheSize--;
        g_lruMinIdx = -1;
        g_lruMinTime = 0;
    }
}

void CacheAddObject(const string name, const double price, 
                    const color clr, const int style, const int width) {
    if(!g_objectCacheHashInitialized) InitializeObjectCacheHash();
    
    int idx = CacheFindIndex(name);
    if(idx >= 0) {
        g_objectCacheHash[idx].entry.lastPrice = price;
        g_objectCacheHash[idx].entry.lastColor = clr;
        g_objectCacheHash[idx].entry.lastStyle = style;
        g_objectCacheHash[idx].entry.lastWidth = width;
        g_objectCacheHash[idx].entry.exists = true;
        g_objectCacheHash[idx].entry.lastUpdate = CacheGetFrameTime();
        g_objectCacheHash[idx].lastAccess = CacheGetFrameTime();
        return;
    }
    
    if(g_objectCacheSize >= MAX_CACHE_SIZE) {
        EvictLRUEntry();
    }
    
    int slot = HashObjectName(name);
    // P-PERF-02: bound the insert probe exactly like the lookup does. A
    // full-table scan (32768 iterations) never finds a slot the lookup could
    // not reach anyway; on a saturated table we evict once and retry below.
    for(int probe = 0; probe < CACHE_MAX_PROBE; probe++) {
        int insertIdx = (slot + probe) % CACHE_HASH_BUCKETS;
        if(!g_objectCacheHash[insertIdx].occupied || g_objectCacheHash[insertIdx].deleted) {
            g_objectCacheHash[insertIdx].name = name;
            g_objectCacheHash[insertIdx].entry.name = name;
            g_objectCacheHash[insertIdx].entry.lastPrice = price;
            g_objectCacheHash[insertIdx].entry.lastColor = clr;
            g_objectCacheHash[insertIdx].entry.lastStyle = style;
            g_objectCacheHash[insertIdx].entry.lastWidth = width;
            g_objectCacheHash[insertIdx].entry.exists = true;
            g_objectCacheHash[insertIdx].entry.lastUpdate = CacheGetFrameTime();
            // P-PERF-02: a recycled slot must not inherit the previous tenant's
            // visibility/tooltip guards — a fresh name always re-asserts once.
            g_objectCacheHash[insertIdx].entry.lastTfMask = 0;
            g_objectCacheHash[insertIdx].entry.tfEpoch = 0;
            g_objectCacheHash[insertIdx].entry.lastTooltip = "";
            g_objectCacheHash[insertIdx].occupied = true;
            g_objectCacheHash[insertIdx].deleted = false;
            g_objectCacheHash[insertIdx].lastAccess = CacheGetFrameTime();
            g_objectCacheSize++;
            datetime insertTime = g_objectCacheHash[insertIdx].lastAccess;
            if(g_lruMinIdx < 0 || insertTime < g_lruMinTime) {
                g_lruMinIdx = insertIdx;
                g_lruMinTime = insertTime;
            }
            return;
        }
    }
    
    _LOG_GATE_W Print("[W][SYNC] Object cache collision - forcing LRU eviction");
    EvictLRUEntry();
    CacheAddObject(name, price, clr, style, width);
}

void CacheRemoveObject(const string name) {
    int idx = CacheFindIndex(name);
    if(idx < 0) {
        return;
    }
    
    g_objectCacheHash[idx].name = "";
    g_objectCacheHash[idx].occupied = false;
    g_objectCacheHash[idx].deleted = true;
    g_objectCacheHash[idx].lastAccess = 0;
    g_objectCacheSize--;
    _LOG_GATE_D Print("[D][SYNC] [DEL] Removed object from cache (size now: ", g_objectCacheSize, ")");
}

bool DeleteIndicatorObjectManaged(const string name, const bool verifyChartObject = false)
{
    if(StringLen(name) == 0) return false;

    // P-PERF-13: a name PROVEN absent on this chart for the current generation
    // cannot need deleting, so the terminal is not asked. The delete paths are
    // the heaviest callers of this probe: CleanupSurplusObjects() walks SEVEN
    // name families on every full frame (two zone families, the center family,
    // two line families, two label families) and each walk keeps going for
    // maxConsecutiveMiss (6) misses, and a zone family asks about 7 names per
    // index (base/_Top/_Bottom/_B_*). Same invariant as P-PERF-07: the mark is
    // only believed inside the generation that proved it, and a name that gets
    // created later enters the MAIN cache, which is consulted first - so a mark
    // is shadowed automatically and never needs an explicit invalidation.
    //
    // P-UI-62: that last sentence was a CLAIM, not the code - the mark was read
    // FIRST, so it decided even when the main cache held a real entry for the name
    // and the delete of a LIVE object was silently refused. It is true now: the
    // main cache is read first, and only a name the cache cannot vouch for is
    // allowed to be short-circuited by the mark. Reachable through the zone
    // pictures - the band's own name is probed and marked while the picture has no
    // band - and through anything else that ever clears the cache without bumping
    // the generation. One lookup, done once, in the order the comment states.
    int cacheIdx = CacheFindIndex(name);
    bool inCache = (cacheIdx >= 0 && g_objectCacheHash[cacheIdx].entry.exists);
    if(!inCache && CacheIsAbsentKnown(name)) return false;

    bool existsOnChart = false;

    if(inCache || verifyChartObject) {
        existsOnChart = (ObjectFind(0, name) >= 0);
        // The probe just PROVED the name is not on the chart: record it, so the
        // identical miss on the next frame costs one hash lookup instead of a
        // terminal call. This is what turns the surplus walk into O(1).
        if(!existsOnChart) CacheMarkAbsent(name);
    }

    if(inCache || existsOnChart) {
        CacheRemoveObject(name);
    }

    if(!existsOnChart) return inCache;

    g_suppressDeleteEvents = true;
    g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
    bool deleted = ObjectDelete(0, name);
    g_suppressDeleteEvents = false;
    return deleted;
}

bool DeleteManagedZoneObjects(const string zoneName, const bool verifyChartObjects = false)
{
    if(StringLen(zoneName) == 0) return false;

    bool foundAny = false;
    if(DeleteIndicatorObjectManaged(zoneName, verifyChartObjects))
        foundAny = true;
    if(DeleteIndicatorObjectManaged(zoneName + "_Top", verifyChartObjects))
        foundAny = true;
    if(DeleteIndicatorObjectManaged(zoneName + "_Bottom", verifyChartObjects))
        foundAny = true;
    // Empty-box border segments (drawn instead of OBJ_RECTANGLE for BOX_EMPTY)
    if(DeleteIndicatorObjectManaged(zoneName + "_B_Top", verifyChartObjects))
        foundAny = true;
    if(DeleteIndicatorObjectManaged(zoneName + "_B_Bottom", verifyChartObjects))
        foundAny = true;
    if(DeleteIndicatorObjectManaged(zoneName + "_B_Left", verifyChartObjects))
        foundAny = true;
    if(DeleteIndicatorObjectManaged(zoneName + "_B_Right", verifyChartObjects))
        foundAny = true;
    return foundAny;
}

void CacheClear() {
    // P-PERF-47: THE GENERATION BUMP IS NOT CONDITIONAL ON OCCUPANCY.
    //
    // MarkDrawGeneration() used to sit at the very END of this function, behind
    // two early returns (`!initialized` and `size == 0`). The bump means "the
    // chart no longer holds what we rendered" — a fact about the CHART, not
    // about this table. So a caller that wiped the family and then called
    // CacheClear() to invalidate the render signature got NOTHING whenever the
    // cache happened to be empty (a fresh instance, or a family that was never
    // cached at all — ClearFactorLevels is exactly that shape), and the next
    // frame compared against a stale geometry signature and SKIPPED the render.
    // The picture then stayed wrong until something unrelated moved. That is the
    // "cache is not invalidated on time" half of the report; the fix is to make
    // the invalidation unconditional, which is what every caller already assumes.
    //
    // Cost: one increment on a cold path (OnDeinit, a mode change, a deep
    // rebuild). It is deliberately BEFORE the guards, because the guards are
    // about the table and this is about the chart.
    MarkDrawGeneration();
    if(!g_objectCacheHashInitialized) return;
    if(g_objectCacheSize == 0) return;
    // PERF FIX: Walk only occupied slots (tracked by g_objectCacheSize) via a
    // single forward scan and reset them, then reset counters.  This avoids
    // touching all 32768 buckets when only a small number are in use.
    int cleared = 0;
    int target = g_objectCacheSize;
    for(int i = 0; i < CACHE_HASH_BUCKETS && cleared < target; i++)
    {
        if(g_objectCacheHash[i].occupied || g_objectCacheHash[i].deleted)
        {
            // P-PERF-02: count BEFORE clearing (the old order tested the flag
            // after setting it false, so the early-exit never fired and every
            // CacheClear walked all 32768 buckets).
            if(g_objectCacheHash[i].occupied) cleared++;
            g_objectCacheHash[i].name = "";
            g_objectCacheHash[i].occupied = false;
            g_objectCacheHash[i].deleted = false;
            g_objectCacheHash[i].lastAccess = 0;
        }
    }
    g_objectCacheSize = 0;
    g_lruMinIdx = -1;
    g_lruMinTime = 0;
    _LOG_GATE_I Print("[I][SYNC] Object cache cleared");
    // P-PERF-02 / P-PERF-47: the generation bump that belongs with this wipe is
    // issued ONCE, at the TOP of the function (see the note there) — not here,
    // where the two early returns above would skip it.
}

bool CacheObjectExists(const string name) {
    int idx = CacheFindIndex(name);
    if(idx < 0) {
        return false;
    }
    return g_objectCacheHash[idx].entry.exists;
}

//+------------------------------------------------------------------+
//| P-PERF-07: NEGATIVE EXISTENCE CACHE                              |
//|                                                                  |
//| WHY THIS EXISTS (measured, not guessed):                         |
//| SetPipelineObjectTimeframesIfExists() guards a mask WRITE, but     |
//| its fallback for a name the main cache does not know is a bare     |
//| ObjectFind(). Every CULLED level pays that probe on EVERY heavy    |
//| frame — 1 for its line, 1 for its pip label, and 7 for its zone    |
//| (SetPipelineZoneVisibility probes base/_Top/_Bottom/_B_Top/        |
//| _B_Bottom/_B_Left/_B_Right). A culled level was never created, so   |
//| it can never enter the main cache, so the probe can never be        |
//| skipped: with inpMaxLevels=144 (288 levels) the render issued up to  |
//| ~2,600 terminal object probes per frame, every frame, forever —      |
//| and each probe scans a chart that carries thousands of objects, so   |
//| the cost grew as O(culled levels x chart objects). That quadratic    |
//| term is what the live log shows as 1797/1921/3438/4250 ms frames.    |
//|                                                                  |
//| The table holds names PROVEN absent on this chart for the current    |
//| build generation. A name that later gets created is registered in    |
//| the MAIN cache, which is consulted FIRST, so an absent mark is       |
//| shadowed automatically and never needs an explicit invalidation.      |
//| SCOPING IS THE DRAW GENERATION ITSELF — and that is the whole invalidation |
//| story, with no reset call and no sweep to get wrong. Every mark records the |
//| `g_drawGeneration` it was proved under (the project's ONE generation owner  |
//| in GlobalVariables.mqh, which every wipe already bumps via                 |
//| MarkDrawGeneration), and a slot whose stamp is not the CURRENT generation is |
//| read as free. So a mark can only be believed inside the very render that     |
//| proved it:                                                    |
//|   - a wipe / TF switch / topology toggle bumps the generation  → all marks   |
//|     are stale at once (O(1), no table walk),                                |
//|   - a fresh instance starts with zeroed statics                               |
//|     → an attach can never inherit the previous instance's facts,             |
//|   - a name that gets created enters the MAIN cache, which is consulted FIRST  |
//|     → its own real entry shadows any mark.                                   |
//| The residual case the table cannot see is a template loaded mid-session that  |
//| carries objects with our exact names: bounded to CULLED names (outside the    |
//| viewport + cull margin, i.e. off-screen) and self-healing, because reaching  |
//| one with the viewport puts the level back on the normal render path - and a   |
//| generation bump on any of our deletes drops the whole table anyway.           |
//+------------------------------------------------------------------+
#define CACHE_ABSENT_BUCKETS 8192   // the live name population is ~2-4k (7 zone
                                    // sub-names x ~289 zones + the culled level set),
                                    // so a smaller table ran near a 100% load factor
                                    // and the 8-probe window started missing - and a
                                    // missed mark silently falls back to the old
                                    // per-frame probe.
#define CACHE_ABSENT_PROBE   8
static string g_absentName[CACHE_ABSENT_BUCKETS];
static int    g_absentStamp[CACHE_ABSENT_BUCKETS];   // g_drawGeneration the mark was proved under

int CacheAbsentBucket(const string name) {
    uint hash = 5381;
    int len = StringLen(name);
    for(int i = 0; i < len; i++)
        hash = ((hash << 5) + hash) + (uint)StringGetCharacter(name, i);
    return (int)(hash % (uint)CACHE_ABSENT_BUCKETS);
}

bool CacheIsAbsentKnown(const string name) {
    int slot = CacheAbsentBucket(name);
    for(int probe = 0; probe < CACHE_ABSENT_PROBE; probe++) {
        int idx = (slot + probe) % CACHE_ABSENT_BUCKETS;
        if(g_absentStamp[idx] != g_drawGeneration) return false;  // stale/empty slot ends the chain
        if(g_absentName[idx] == name) return true;
    }
    return false;
}

void CacheMarkAbsent(const string name) {
    int slot = CacheAbsentBucket(name);
    int free = -1;
    for(int probe = 0; probe < CACHE_ABSENT_PROBE; probe++) {
        int idx = (slot + probe) % CACHE_ABSENT_BUCKETS;
        if(g_absentStamp[idx] != g_drawGeneration) { free = idx; break; }
        if(g_absentName[idx] == name) return;   // already marked
    }
    // No free slot in the probe window: reuse the window's first slot. A dropped
    // mark can only cost one extra probe later, never a wrong answer.
    if(free < 0) free = slot;
    g_absentName[free] = name;
    g_absentStamp[free] = g_drawGeneration;
}

void CacheForgetAbsent(const string name) {
    int slot = CacheAbsentBucket(name);
    for(int probe = 0; probe < CACHE_ABSENT_PROBE; probe++) {
        int idx = (slot + probe) % CACHE_ABSENT_BUCKETS;
        if(g_absentStamp[idx] != g_drawGeneration) return;
        if(g_absentName[idx] == name) { g_absentStamp[idx] = 0; return; }
    }
}

// P-PERF-07: called once per OnInit, because a re-attach / TF switch reuses the
// chart the previous instance drew on. The table is already generation-scoped,
// so no stale mark can be believed even without this - the reset exists so the
// claim does not depend on the two statics (g_absentStamp and g_drawGeneration)
// staying in step, and it costs one 8 kB int wipe on an init-only path.
// 0 is never a live generation (g_drawGeneration starts at 1), so a zeroed
// stamp reads as a free slot - no name strings have to be touched.
void CacheAbsentResetAll() {
    for(int i = 0; i < CACHE_ABSENT_BUCKETS; i++) g_absentStamp[i] = 0;
}

bool CacheGetObject(const string name, SObjectCacheEntry &entry) {
    int idx = CacheFindIndex(name);
    if(idx < 0) {
        return false;
    }
    
    entry = g_objectCacheHash[idx].entry;
    return true;
}

bool CacheGetLabel(const string name, string &text, color &clr) {
    int idx = CacheFindIndex(name);
    if(idx < 0) {
        return false;
    }
    
    text = g_objectCacheHash[idx].entry.lastText;
    clr = g_objectCacheHash[idx].entry.lastColor;
    return g_objectCacheHash[idx].entry.exists;
}

void CacheUpdateObject(const string name, const double price, 
                       const color clr, const int style, const int width) {
    int idx = CacheFindIndex(name);
    if(idx < 0) {
        CacheAddObject(name, price, clr, style, width);
        return;
    }
    
    g_objectCacheHash[idx].entry.lastPrice = price;
    g_objectCacheHash[idx].entry.lastColor = clr;
    g_objectCacheHash[idx].entry.lastStyle = style;
    g_objectCacheHash[idx].entry.lastWidth = width;
    g_objectCacheHash[idx].entry.exists = true;
    g_objectCacheHash[idx].entry.lastUpdate = CacheGetFrameTime();
    g_objectCacheHash[idx].lastAccess = CacheGetFrameTime();
}

// P-UI-62: `outline` is the second picture bit (see SObjectCacheEntry.lastOutline).
// `existsOnChart` lets a zone cache a picture it draws with NO rectangle of its own
// (EMPTY: the zone name holds nothing and its three border segments are the zone) -
// such an entry is then a PROOF OF ABSENCE for that name, exactly like the P-PERF-07
// absent table, so the rectangle path must not probe the chart for it.
void CacheUpdateZone(const string name, const double price1, const double price2,
                      const datetime time1, const datetime time2,
                      const color clr, const bool filled,
                      const int style, const int width,
                      const bool outline = false, const bool existsOnChart = true) {
    int idx = CacheFindIndex(name);
    if(idx < 0) {
        if(!g_objectCacheHashInitialized) InitializeObjectCacheHash();
        if(g_objectCacheSize >= MAX_CACHE_SIZE) EvictLRUEntry();
        
        int slot = HashObjectName(name);
        for(int probe = 0; probe < CACHE_MAX_PROBE; probe++) {
            int insertIdx = (slot + probe) % CACHE_HASH_BUCKETS;
            if(!g_objectCacheHash[insertIdx].occupied || g_objectCacheHash[insertIdx].deleted) {
                g_objectCacheHash[insertIdx].name = name;
                g_objectCacheHash[insertIdx].entry.name = name;
                g_objectCacheHash[insertIdx].entry.lastPrice = price1;
                g_objectCacheHash[insertIdx].entry.lastPrice2 = price2;
                g_objectCacheHash[insertIdx].entry.lastTime1 = time1;
                g_objectCacheHash[insertIdx].entry.lastTime2 = time2;
                g_objectCacheHash[insertIdx].entry.lastColor = clr;
                g_objectCacheHash[insertIdx].entry.lastFilled = filled;
                g_objectCacheHash[insertIdx].entry.lastOutline = outline;
                g_objectCacheHash[insertIdx].entry.lastStyle = style;
                g_objectCacheHash[insertIdx].entry.lastWidth = width;
                g_objectCacheHash[insertIdx].entry.exists = existsOnChart;
                g_objectCacheHash[insertIdx].entry.lastUpdate = CacheGetFrameTime();
                // P-PERF-02: fresh tenant → no inherited visibility guard.
                g_objectCacheHash[insertIdx].entry.lastTfMask = 0;
                g_objectCacheHash[insertIdx].entry.tfEpoch = 0;
                g_objectCacheHash[insertIdx].entry.lastTooltip = "";
                g_objectCacheHash[insertIdx].occupied = true;
                g_objectCacheHash[insertIdx].deleted = false;
                g_objectCacheHash[insertIdx].lastAccess = CacheGetFrameTime();
                g_objectCacheSize++;
                return;
            }
        }
        return;
    }
    
    g_objectCacheHash[idx].entry.lastPrice = price1;
    g_objectCacheHash[idx].entry.lastPrice2 = price2;
    g_objectCacheHash[idx].entry.lastTime1 = time1;
    g_objectCacheHash[idx].entry.lastTime2 = time2;
    g_objectCacheHash[idx].entry.lastColor = clr;
    g_objectCacheHash[idx].entry.lastFilled = filled;
    g_objectCacheHash[idx].entry.lastOutline = outline;
    g_objectCacheHash[idx].entry.lastStyle = style;
    g_objectCacheHash[idx].entry.lastWidth = width;
    g_objectCacheHash[idx].entry.exists = existsOnChart;
    g_objectCacheHash[idx].entry.lastUpdate = CacheGetFrameTime();
    g_objectCacheHash[idx].lastAccess = CacheGetFrameTime();
}

void CacheUpdateLabel(const string name, const string text, const color clr) {
    int idx = CacheFindIndex(name);
    if(idx < 0) {
        if(!g_objectCacheHashInitialized) InitializeObjectCacheHash();
        if(g_objectCacheSize >= MAX_CACHE_SIZE) EvictLRUEntry();
        
        int slot = HashObjectName(name);
        // P-PERF-02: bounded probe (see CacheAddObject).
        for(int probe = 0; probe < CACHE_MAX_PROBE; probe++) {
            int insertIdx = (slot + probe) % CACHE_HASH_BUCKETS;
            if(!g_objectCacheHash[insertIdx].occupied || g_objectCacheHash[insertIdx].deleted) {
                g_objectCacheHash[insertIdx].name = name;
                g_objectCacheHash[insertIdx].entry.name = name;
                g_objectCacheHash[insertIdx].entry.lastText = text;
                g_objectCacheHash[insertIdx].entry.lastColor = clr;
                g_objectCacheHash[insertIdx].entry.exists = true;
                g_objectCacheHash[insertIdx].entry.lastUpdate = CacheGetFrameTime();
                // P-PERF-02: fresh tenant → no inherited visibility guard.
                g_objectCacheHash[insertIdx].entry.lastTfMask = 0;
                g_objectCacheHash[insertIdx].entry.tfEpoch = 0;
                g_objectCacheHash[insertIdx].entry.lastTooltip = "";
                g_objectCacheHash[insertIdx].occupied = true;
                g_objectCacheHash[insertIdx].deleted = false;
                g_objectCacheHash[insertIdx].lastAccess = CacheGetFrameTime();
                g_objectCacheSize++;
                return;
            }
        }
        return;
    }
    
    g_objectCacheHash[idx].entry.lastText = text;
    g_objectCacheHash[idx].entry.lastColor = clr;
    g_objectCacheHash[idx].entry.exists = true;
    g_objectCacheHash[idx].entry.lastUpdate = CacheGetFrameTime();
    g_objectCacheHash[idx].lastAccess = CacheGetFrameTime();
}//+------------------------------------------------------------------+
//| NARROW ACCESSORS (P-PERF-02)                                     |
//| The guarded hot paths need exactly ONE field, but copying a        |
//| SObjectCacheEntry drags three strings through memory on every call.|
//| These read/write the slot in place — no struct copy, one hash probe.|
//+------------------------------------------------------------------+
bool CacheGetTfMask(const string name, long &mask, int &epoch)
{
    int idx = CacheFindIndex(name);
    if(idx < 0) return false;
    mask  = g_objectCacheHash[idx].entry.lastTfMask;
    epoch = g_objectCacheHash[idx].entry.tfEpoch;
    return true;
}

void CacheSetTfMask(const string name, const long mask, const int epoch)
{
    int idx = CacheFindIndex(name);
    if(idx < 0)
    {
        // Unknown object: remember it cheaply so the NEXT frame is guarded.
        CacheAddObject(name, 0.0, clrNONE, 0, 0);
        idx = CacheFindIndex(name);
        if(idx < 0) return;
    }
    g_objectCacheHash[idx].entry.lastTfMask = mask;
    g_objectCacheHash[idx].entry.tfEpoch = epoch;
}

// P-PERF-32: narrow colour accessors for the structure recolour walk
// (LevelPipeline). The walk compares the live structure colour against the
// blended colour the render stored, per object, with zero terminal calls —
// a struct copy per object would drag three strings through memory for a
// pure colour compare.
bool CacheGetColor(const string name, color &clr)
{
    int idx = CacheFindIndex(name);
    if(idx < 0) return false;
    clr = g_objectCacheHash[idx].entry.lastColor;
    return true;
}

void CacheSetColor(const string name, const color clr)
{
    int idx = CacheFindIndex(name);
    if(idx < 0) return;   // the walk never creates entries, it only repaints
    g_objectCacheHash[idx].entry.lastColor = clr;
}

bool CacheGetTooltip(const string name, string &tip)
{
    int idx = CacheFindIndex(name);
    if(idx < 0) return false;
    tip = g_objectCacheHash[idx].entry.lastTooltip;
    return true;
}

void CacheSetTooltip(const string name, const string tip)
{
    int idx = CacheFindIndex(name);
    if(idx < 0) return;
    g_objectCacheHash[idx].entry.lastTooltip = tip;
}

// P-PERF-02: drop the stored visibility masks of a whole name family. Used by
// the BULK visibility owners (ATR/TH label families, the F/L key passes) which
// write masks straight to the chart: without this the guard could believe a
// mask it wrote earlier is still on the chart and skip a needed write.
void CacheForgetTfMasks(const string prefix)
{
    if(StringLen(prefix) == 0 || g_objectCacheSize == 0) return;
    int prefixLen = StringLen(prefix);
    ushort firstChar = StringGetCharacter(prefix, 0);
    int visited = 0;
    int snapshot = g_objectCacheSize;   // stable snapshot: we do not add/remove here
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < snapshot; i++)
    {
        if(!g_objectCacheHash[i].occupied) continue;
        visited++;
        if(StringGetCharacter(g_objectCacheHash[i].name, 0) != firstChar) continue;
        if(StringLen(g_objectCacheHash[i].name) < prefixLen) continue;
        if(StringSubstr(g_objectCacheHash[i].name, 0, prefixLen) != prefix) continue;
        g_objectCacheHash[i].entry.tfEpoch = 0;   // "never written" → next write lands
    }
}

bool CacheGetPrice(const string name, double &price)
{
    int idx = CacheFindIndex(name);
    if(idx < 0) return false;
    price = g_objectCacheHash[idx].entry.lastPrice;
    return true;
}

void CacheSetPrice(const string name, const double price)
{
    int idx = CacheFindIndex(name);
    if(idx < 0)
    {
        CacheAddObject(name, price, clrNONE, 0, 0);
        return;
    }
    g_objectCacheHash[idx].entry.lastPrice = price;
    g_objectCacheHash[idx].entry.exists = true;
}

int CacheGetSize()
{
    return g_objectCacheSize;
}

void CacheRebuild() {
    CacheClear();

    // MT4: ObjectsTotal() with chart_id parameter
    int totalObjects = ObjectsTotal(0, -1, -1);

    // P-PERF-47: THE "OURS" TEST IS THE OBJECT PREFIX, NOT TWO HARD-CODED LETTERS.
    //
    // This filter used to be `name[0]=='T' && name[1]=='H'`. That is wrong in both
    // directions at once:
    //   - TOO NARROW: `inpObjectPrefix` is an INPUT (default "THLevels"), so a
    //     user who renames it to anything not starting with "TH" makes every
    //     rebuild cache NOTHING. It also misses the families that do not carry
    //     the level prefix at all (`BiotakHTF_<chartId>_<i>`), so a rebuild
    //     produced a cache that described only part of what is on the chart —
    //     and every uncached name then costs a fresh ObjectFind on every walk,
    //     which on MT5 is the most expensive primitive there is (~88 us for a
    //     miss, measured by MT5PrimitiveProbe).
    //   - TOO BROAD: a foreign object whose name happens to start with "TH"
    //     (another indicator's, or a template's) got cached as OURS, so the
    //     cache claimed liveness for a name this program must never write.
    //
    // The prefix test is the one the rest of the project already uses to answer
    // "is this ours?" and it cannot drift from the input that names the family.
    // The function has no live caller today (only the test harness drives it) —
    // which is exactly why the wrong filter survived: nothing exercised it.
    string ownPrefix = inpObjectPrefix;
    int ownPrefixLen = StringLen(ownPrefix);

    for(int i = 0; i < totalObjects; i++) {
        string objName = ObjectName(0, i);

        // Only cache objects that belong to this indicator's namespace.
        if(ownPrefixLen == 0 || StringLen(objName) < ownPrefixLen) continue;
        if(StringSubstr(objName, 0, ownPrefixLen) != ownPrefix) continue;
        {
            double price = ObjectGetDouble(0, objName, OBJPROP_PRICE);
            color clr = (color)ObjectGetInteger(0, objName, OBJPROP_COLOR);
            int style = (int)ObjectGetInteger(0, objName, OBJPROP_STYLE);
            int width = (int)ObjectGetInteger(0, objName, OBJPROP_WIDTH);
            
            CacheAddObject(objName, price, clr, style, width);
        }
    }
    
    _LOG_GATE_D Print("[D][SYNC] Object cache rebuilt: ", g_objectCacheSize, " objects cached from ", totalObjects, " total chart objects");
}

int CacheValidate() {
    if(!g_objectCacheHashInitialized) return 0;
    int invalidCount = 0;
    // PERF FIX: Early-exit based on occupied count — no need to scan beyond g_objectCacheSize hits
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++) {
        if(!g_objectCacheHash[i].occupied) continue;
        visited++;
        string objName = g_objectCacheHash[i].name;
        if(ObjectFind(0, objName) < 0) {
            g_objectCacheHash[i].entry.exists = false;
            invalidCount++;
        }
    }
    if(invalidCount > 0) {
        _LOG_GATE_E Print("[E][SYNC] Cache validation found ", invalidCount, " invalid entries out of ", g_objectCacheSize);
    }
    return invalidCount;
}

#endif // OBJECT_CACHE_MQH
