// LevelPipe_B.mqh - LevelPipeline.mqh split 2026-09-29: exact lines 1439-2181, byte-identical, zero renames.
#ifndef LEVEL_PIPE_B_MQH
#define LEVEL_PIPE_B_MQH

//+------------------------------------------------------------------+
//| BUILD MODE CONFIG: Create config from current input parameters   |
//+------------------------------------------------------------------+
SModeConfig BuildModeConfig(const string objectPrefix, const string modeName)
{
    SModeConfig cfg;
    cfg.modeName = modeName;
    cfg.objectPrefix = objectPrefix;
    
    // Read zone settings from unified zone config
    SUnifiedZoneConfig zoneConfig = GetUnifiedZoneConfig();
    cfg.zonesEnabled = zoneConfig.enabled;
    cfg.zoneTransparency = zoneConfig.transparency;
    cfg.zoneHeightPercent = zoneConfig.heightPercent;
    
    // GOLD FIX: Factor mode steps are defined differently in user's mind (or original logic)
    // If it looks double, we apply a 0.5 scaling factor specifically for Factor modes.
    if(modeName == "Factor" || modeName == "Factor_Harmonic") {
        cfg.zoneHeightPercent *= 0.5;
    }
    
    cfg.zoneDefaultColor = zoneConfig.defaultColor;
    cfg.zoneStyle = zoneConfig.style;
    
    // Default rendering flags
    cfg.useObjPropBack = false;
    cfg.zOrder = Z_CHART_ZONE;   // P-UI-31: mode configs override (Factor -> Z_CHART_LINE)
    cfg.hideLineWhenTriggerOnly = false;
    cfg.useStepFilter = true;
    
    // Defaults for fallback colors (overridden per mode)
    cfg.fallbackColor = clrDodgerBlue;
    cfg.fallbackStyle = STYLE_DOT;
    cfg.fallbackWidth = 1;
    cfg.fallbackColor2 = clrDodgerBlue;
    cfg.fallbackStyle2 = STYLE_DOT;
    cfg.fallbackWidth2 = 1;
    cfg.midpointColor = clrDodgerBlue;
    cfg.midpointStyle = STYLE_DOT;
    cfg.midpointWidth = 1;
    
    // Price boundaries
    bool isCustomPrice = (g_thStartPointType == TH_START_POINT_CUSTOM_PRICE);
    cfg.boundByHistorical = !isCustomPrice;
    cfg.maxPrice = isCustomPrice ? 0 : g_highestHigh;
    cfg.minPrice = isCustomPrice ? 0 : g_lowestLow;
    
    return cfg;
}

//+------------------------------------------------------------------+
//| ASYMMETRIC REACH: split the budget toward the live price. Centred /  |
//| invalid live reads an even split; total never exceeds the budget.    |
//+------------------------------------------------------------------+
void LevelSplitCounts(const int Nin, int &above, int &below)
{
    int N = Nin;
    if(N > MAX_SAFE_LEVELS) N = MAX_SAFE_LEVELS;
    if(N < 1) N = 1;
    int total = MathMin(N * 2, LVL_TOTAL_BUDGET);
    above = N; below = N;
    if(total < N * 2) { above = total / 2; below = total - above; }
    double center = GetMidpointPrice(g_thStartPointType);
    double step = NaturalFirstStep() * StepOverrideFactor();
    double bid = MarketInfo(GetCachedSymbol(), MODE_BID);
    double ask = MarketInfo(GetCachedSymbol(), MODE_ASK);
    double live = (bid > 0.0 && ask > 0.0) ? (bid + ask) * 0.5 : bid;
    if(!(MathIsValidNumber(center) && center > 0.0 && MathIsValidNumber(step) && step > 0.0 && live > 0.0)) return;
    int offLvls = (int)MathCeil(MathAbs(live - center) / step);
    if(offLvls <= LVL_SPLIT_MARGIN) return;
    int minCtx = MathMax(1, total / LVL_SPLIT_CTXDIV);
    if(total < minCtx * 2) return;
    int toward = MathMin(N + offLvls, total - minCtx);
    if(live >= center) { above = toward; below = total - toward; }
    else               { below = toward; above = total - toward; }
    if(above < 1) above = 1;
    if(below < 1) below = 1;
    static int s_wA = -1, s_wB = -1;
    if(above != s_wA || below != s_wB) { s_wA = above; s_wB = below; Print("[LVL] split N=", N, " above=", above, " below=", below); }
}

//+------------------------------------------------------------------+
//| P-PERF-18: the identity of a built geometry.                     |
//|                                                                  |
//| Every input the three pure stages read is folded in, so a change  |
//| in ANY of them misses the cache and rebuilds for real:           |
//|   - center price + step sizes   (a tick that moved the base price)|
//|   - the cull window             (a scroll or a zoom)             |
//|   - mode / classify / lsFirst / max levels / trigger switch      |
//|   - every zone and fallback colour/style field of SModeConfig    |
//|   - the custom-price drag flag  (the drag path re-culls)         |
//| Doubles are quantised with DoubleToString(...,8) so a sub-point  |
//| wobble cannot masquerade as a new geometry, and the string is     |
//| built once per frame - microseconds against the thousands of      |
//| level computations it can save.                                  |
//+------------------------------------------------------------------+
string PipelineGeometryKey(const SModeConfig &config,
                           const double centerPrice,
                           const double &stepSizes[],
                           const int stepSizeCount,
                           const ENUM_LEVEL_STEP_MODE stepMode,
                           const ENUM_CLASSIFY_MODE classifyMode,
                           const bool lsFirst,
                           const int maxLevelsAbove,
                           const int maxLevelsBelow,
                           const double vpTop,
                           const double vpBottom,
                           const int baseMultiplier)
{
    string key = config.modeName + "|" + config.objectPrefix;
    key += "|" + DoubleToString(centerPrice, 8);
    key += "|" + IntegerToString(stepSizeCount) + "," + IntegerToString((int)stepMode);
    for(int s = 0; s < stepSizeCount; s++) key += "," + DoubleToString(stepSizes[s], 8);
    key += "|" + IntegerToString((int)classifyMode) + IntegerToString(lsFirst ? 1 : 0);
    key += "|" + IntegerToString(maxLevelsAbove) + "," + IntegerToString(maxLevelsBelow);
    key += "|" + DoubleToString(vpTop, 8) + "," + DoubleToString(vpBottom, 8);
    // P-PERF-21: `triggerEnabled` used to sit here, and it was a FALSE
    // dependency. The trigger overlay owns exactly ONE family - the trigger
    // zones - and that decision lives in RenderZones (`zones[i].isTrigger &&
    // !triggerEnabled`), which reads the LIVE flag at paint time. Nothing that
    // BUILDS this geometry reads it: CalculateLevels does not touch it,
    // BuildZonesAndLines does not touch it, and the two classify-time helpers
    // that take it as a parameter (`GetPathForLevelOptimized`,
    // `GetZoneColorForLevel`) never look at it. So a T press threw away the
    // whole geometry and recomputed byte-identical lists - the recompute half
    // of "the trigger toggle redraws all my levels".
    key += "|" + IntegerToString(baseMultiplier);
    key += "|" + IntegerToString(config.zonesEnabled ? 1 : 0) + "," + IntegerToString((int)config.zoneStyle);
    key += "," + IntegerToString(config.zoneTransparency) + "," + DoubleToString(config.zoneHeightPercent, 6);
    key += "," + IntegerToString((int)config.zoneDefaultColor);
    key += "|" + IntegerToString(config.useObjPropBack ? 1 : 0) + "," + IntegerToString(config.zOrder);
    key += "," + IntegerToString(config.useStepFilter ? 1 : 0);
    key += "," + IntegerToString(config.boundByHistorical ? 1 : 0);
    key += "," + DoubleToString(config.maxPrice, 8) + "," + DoubleToString(config.minPrice, 8);
    key += "|" + IntegerToString((int)config.fallbackColor) + "," + IntegerToString((int)config.fallbackStyle);
    key += "," + IntegerToString(config.fallbackWidth);
    key += "," + IntegerToString((int)config.fallbackColor2) + "," + IntegerToString((int)config.fallbackStyle2);
    key += "," + IntegerToString(config.fallbackWidth2);
    key += "," + IntegerToString((int)config.midpointColor) + "," + IntegerToString((int)config.midpointStyle);
    key += "," + IntegerToString(config.midpointWidth);
    // P-PERF-21b: the ZONE COLOURS are part of what this geometry carries
    // (ClassifyLevels stores zoneColor per level, read from PipelineBandBaseColor),
    // yet none of THOSE inputs were in the key: a structure-tier colour, a tier's
    // show flag, the zones switch or the trigger colour could change while the key
    // stayed equal and the cached zones would keep painting the old colour. The
    // staleness was invisible because every one of those edits also changes
    // levelSig and therefore wipes - but the cache must not RELY on a different
    // guard to be correct.
    // P-UI-131m: the trigger term is the RAW `g_triggerColor` the geometry stores.
    // It used to be `GetTriggerRenderColor()`, which put the trigger TRANSPARENCY
    // in the key and so made every step of that slider a full family recompute -
    // a PAINT input read as geometry, the mistake P-UI-66 removed from the lines.
    key += "|zc" + IntegerToString(inpShowMidZones ? 1 : 0)
              + IntegerToString(inpShowStructure ? 1 : 0)
              + IntegerToString(inpShowStructureL1 ? 1 : 0) + IntegerToString(inpShowStructureL2 ? 1 : 0)
              + IntegerToString(inpShowStructureL3 ? 1 : 0) + IntegerToString(inpShowStructureL4 ? 1 : 0)
              + IntegerToString(inpShowStructureL5 ? 1 : 0)
              + "," + IntegerToString((int)inpStructureL1Color) + IntegerToString((int)inpStructureL2Color)
              + IntegerToString((int)inpStructureL3Color) + IntegerToString((int)inpStructureL4Color)
              + IntegerToString((int)inpStructureL5Color)
              + "," + IntegerToString((int)g_triggerColor);
    key += "|" + IntegerToString(g_customPriceLineDragging ? 1 : 0);
    // P-UI-66 - THE LINE LOOK IS NOT GEOMETRY, SO IT IS NOT A KEY TERM.
    //
    // This slot used to carry `g_lineColor` and `g_lineTransparency` as a
    // workaround for a stale read: ClassifyLevels() copies the live look into
    // `classified[]`, BuildZonesAndLines() copies it on into `lines[]`, and the
    // PAINT read it back out of that array. A look edit therefore only reached
    // the chart when this key MISSED - and only the two inputs that happened to
    // be listed here could ever miss it. WIDTH and STYLE were not listed, so on
    // the Lines card ("ONE STYLE FOR ALL LINES") the colour row and the
    // transparency slider moved the chart while the width slider and the style
    // dropdown did NOTHING until an unrelated edit rebuilt the geometry.
    //
    // Naming all four inputs here would have been the wrong repair: every width
    // drag would then throw the whole level family away (CalculateLevels +
    // Classify + Build) on the weak PC this project is written for. The owner is
    // fixed instead - RenderTriggerLines reads the live look, exactly as
    // RenderZones already reads the BAND/EDGE border live - so **no look input
    // belongs in this key at all**, and leaving one out can no longer make a
    // control dead. The gate that holds this: probe-budget-audit `look-live`.
    // P-PERF-23b: `g_linesVisible` used to sit here, described as "ClassifyLevels()
    // reads the LIVE line appearance and the L toggle". That was FALSE: no stage
    // of this pipeline reads it. grep says it has exactly two consumers in the
    // whole file - the RenderTriggerLines paint line (`long lineTf = ...
    // !g_linesVisible ...`, plus ObjectFunctions) and this key. The L switch and
    // the panels' SHOW LINES row are a MASK decision taken at paint time, so the
    // term turned every visibility flip into a full recompute of
    // CalculateLevels/Classify/Build that produced byte-identical lists, and
    // then the paint re-read the live flag anyway. Removed: the picture still
    // follows the switch (the mask writer owns it), the math no longer restarts.
    // ClassifyLevels() -> GetHighestStructureLevel() reads the structure-interval
    // table (g_cachedIntervals). That table is a pure function of the VALIDATED
    // base multiplier (already in the key), but the key names its five values
    // directly, so a future change to how the table is derived cannot silently
    // serve structure levels computed against the old table. (The term here used
    // to be ArraySize(g_cachedIntervals), the constant 5 - it asserted a
    // property instead of proving it.)
    key += "|iv";
    for(int iv = 0; iv < 5; iv++) key += "," + IntegerToString(g_cachedIntervals[iv]);
    return key;
}

//+------------------------------------------------------------------+
//| UNIFIED PIPELINE EXECUTOR                                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-LEVEL-FOREIGN-01 — A NAME IS NOT A PLACE                       |
//|                                                                  |
//| THE DEFECT THIS CLOSES                                           |
//|                                                                  |
//| A level object is named by its LOGICAL STEP INDEX (`_Above_7`),   |
//| but its PRICE is a function of the geometry: the anchor, the step |
//| sizes and the mode. The index therefore survives a change that    |
//| moves every price, and NOTHING in the project could tell the two  |
//| apart:                                                           |
//|                                                                  |
//|   * RenderTriggerLines() creates or updates a line only when it   |
//|     is inside the viewport; every other object merely gets a mask |
//|     (OBJ_NO_PERIODS). Out of view, a price is never corrected.    |
//|   * CleanupSurplusPipeline() sweeps by STEP INDEX, from           |
//|     `maxStep + 1` upward - and the previous geometry's `_Above_7` |
//|     and this one's `_Above_7` are the same index. The sweep sees  |
//|     a name it expects and stops. It cannot see a foreign object.  |
//|                                                                  |
//| So an object written by a previous geometry keeps its name, keeps |
//| its index, keeps its price, and is never removed. The live chart  |
//| showed the result: `_Above_1..9` at 2.41 pips (M1) interleaved    |
//| with `_Above_10..43` at 9.65 pips (H1), including near-duplicate  |
//| PAIRS 0.06-0.16 pips apart - one member from each geometry, which |
//| a single build can never emit (BuildZonesAndLines drops a level   |
//| that fails to advance, so a duplicate proves two builds).         |
//|                                                                  |
//| WHAT THIS DOES                                                    |
//|                                                                  |
//| When the LADDER ITSELF changes (the step signature: mode, count,  |
//| the sizes - i.e. a timeframe switch, a mode change, an ATR-scaling |
//| regime change), walk the freshly built lists and delete any object |
//| whose CACHED price disagrees with the price this geometry gives   |
//| its step index. The cache stores the price we last wrote, so the  |
//| comparison costs one hash probe and no terminal read; only a      |
//| genuine mismatch costs a delete. The render that follows re-creates |
//| whatever is inside the viewport, so the family ends up exactly the |
//| current geometry - and the objects that are gone are the ones the |
//| current geometry never owned.                                     |
//|                                                                  |
//| WHY ONLY ON A LADDER CHANGE                                       |
//|                                                                  |
//| A centre-only move (a price-anchored start point ticking) shifts  |
//| the whole ladder coherently: anything that enters the viewport is |
//| corrected by the render, and anything else is masked, not visible. |
//| The corruption that reaches the SCREEN comes from a change of     |
//| PITCH - two different step sizes coexisting - so that is the gate. |
//| It makes the pass rare (a switch, not a tick) and keeps the cost  |
//| bounded on the weak PC this project is written for.               |
//|                                                                  |
//| THE COLD-CACHE CORNER, STATED HONESTLY                            |
//|                                                                  |
//| On a timeframe switch the teardown clears the object cache, so a  |
//| fresh instance's cache holds nothing to compare and this pass     |
//| finds nothing. That corner is NOT covered here - it is covered by |
//| AdoptionFingerprint(), which now folds in the timeframe and the   |
//| anchor so the kept family is never ADOPTED when its prices are    |
//| stale (see P-LEVEL-FOREIGN-01 there). This function is the net    |
//| for the WARM-cache case: a ladder change inside one instance.     |
//+------------------------------------------------------------------+
int SweepForeignLevelObjects(const SModeConfig &config,
                             const STriggerLine &lines[],
                             const int lineCount,
                             const SZoneDefinition &zones[],
                             const int zoneCount)
{
   const double tol = GetCachedPoint() * 0.1;
   int removed = 0;

    for(int i = 0; i < lineCount; i++)
    {
       // P-UI-98k: the render skips the live-dragged handle (it must never
       // rewrite a line the hand is holding, P-BK-15) - so this sweep must
       // not delete it either. Every step-1 drag changes the pitch (F), so
       // this pass runs on the drag's own frames and the cache still holds
       // the pre-drag price: without this term the sweep deletes the very
       // line being dragged, the render refuses to re-create it while the
       // gesture is live, the factor math reads 0 and freezes (no write, no
       // redraw flag), and the settle's forced frame is gated off - the
       // handle stays missing until an unrelated rebuild. The above handle
       // never blinks because it is deleted AND re-created in the same
       // frame; only the dragged one (here: the below handle) vanishes.
       bool s1SkipSweep = (g_s1DragLive && g_s1DragName != "" &&
                           lines[i].name == g_s1DragName);
       // The line and its pip-distance label share one price and one owner.
       for(int pass = 0; pass < 2; pass++)
       {
          if(s1SkipSweep) continue;
          string nm = (pass == 0) ? lines[i].name : (lines[i].name + "_Label");
         SObjectCacheEntry e;
         if(!CacheGetObject(nm, e)) continue;   // cold cache: nothing to compare
         if(!e.exists) continue;                // dead slot: no object under this name
         if(MathAbs(e.lastPrice - lines[i].price) <= tol) continue;   // ours
         if(DeleteIndicatorObjectManaged(nm, true)) removed++;
      }
   }

   for(int i = 0; i < zoneCount; i++)
   {
      SObjectCacheEntry e;
      if(!CacheGetObject(zones[i].name, e)) continue;
      if(!e.exists) continue;
      if(MathAbs(e.lastPrice - zones[i].midPrice) <= tol) continue;
      if(DeleteManagedZoneObjects(zones[i].name, true)) removed++;
   }

   return removed;
}

//| A zone exists as ONE band plus up to six NAMED sub-objects — `_Top`,
//| `_Bottom` (the boundary lines) and `_B_Top`/`_B_Bottom`/`_B_Left`/
//| `_B_Right` (the empty-box border segments) — and `DeleteManaged- |
//| ZoneObjects()` removes the whole set from the BAND's name. So the   |
//| walk has to act on the band only, or one foreign zone would be     |
//| deleted six times over.
bool ZoneNameIsBand(const string nm)
{
    int n = StringLen(nm);
    if(n > 4 && StringSubstr(nm, n - 4, 4) == "_Top")    return false;   // also _B_Top
    if(n > 7 && StringSubstr(nm, n - 7, 7) == "_Bottom") return false;   // also _B_Bottom
    if(n > 5 && StringSubstr(nm, n - 5, 5) == "_Left")   return false;   // also _B_Left
    if(n > 6 && StringSubstr(nm, n - 6, 6) == "_Right")  return false;   // also _B_Right
    return true;
}

//+------------------------------------------------------------------+
//| P-LEVEL-FOREIGN-02 — THE OTHER HALF OF THE FOREIGN-OBJECT SWEEP.  |
//|                                                                  |
//| `SweepForeignLevelObjects()` above can only judge the names the    |
//| new ladder PRODUCES: it walks the built lists and asks the cache   |
//| whether the object under each name is still at the built price.    |
//| An object whose STEP INDEX the new ladder does not produce at all  |
//| is never in those lists, so nothing ever asked about it - and that |
//| is exactly why the family could carry a foreign pitch (the        |
//| reported `_Above_1..9` at 2.41 pips beside `_Above_10..43` at     |
//| 9.65). THAT hole is what put `Period()` into the adoption          |
//| fingerprint, and the fingerprint is what made every timeframe      |
//| switch wipe and rebuild the level family.                          |
//|                                                                  |
//| This walks the CHART instead - once, on the frame the ladder PITCH |
//| changed, which is the only moment the two pitches can be told      |
//| apart - and deletes every family object whose tail step is above   |
//| the newest one. Names carry the step and the ladder produces a     |
//| CONTIGUOUS 1..maxStep range (the same range `CleanupSurplus-        |
//| Pipeline` walks from maxStep + 1), so "step > maxStep" is exact:   |
//|                                                                  |
//|   * an index <= maxStep is produced by this ladder, so the render  |
//|     owns it and re-asserts its price IN PLACE;                    |
//|   * an index >  maxStep cannot be produced by this ladder at any   |
//|     price, so it can only be a survivor of another pitch.          |
//|                                                                  |
//| Called only when the family was HANDED OVER (`g_adoptPrevious-     |
//| Topology`), never after a wipe: a wiped chart has nothing foreign  |
//| on it, and this is a whole-chart walk.                             |
//|                                                                  |
//| The names are COLLECTED first and deleted afterwards, because a     |
//| delete renumbers the terminal's object-list indices - deleting     |
//| inside the walk would step over the next object.                   |
//+------------------------------------------------------------------+
// Is this chart name one of the names the build JUST produced?  The produced
// list is small (the culled ladder: tens of entries) and the walk only asks
// about names the family test already accepted, so a linear scan is the right
// shape here - and it is EXACT, which is the whole point (see below).
bool ProducedLadderName(const string nm, const string &produced[], const int producedCount)
{
    for(int p = 0; p < producedCount; p++)
        if(produced[p] == nm) return true;
    return false;
}

// Only a name that looks like OUR family is judged. `_BK_` is the user's
// Base/Knot layer (P-BK-01: it has no expiry whichever build made it).
bool LadderFamilyName(const string nm, const string fam)
{
    if(StringLen(nm) <= StringLen(fam)) return false;
    if(StringSubstr(nm, 0, StringLen(fam)) != fam) return false;
    if(StringFind(nm, "_BK_") >= 0) return false;
    return true;
}

// Zone sub-objects are paid for by their band's name, so a band that survives
// carries its borders with it and a band that goes takes them with it.
bool LadderNameIsZoneBand(const string nm)
{
    return (StringFind(nm, "_Zone_") >= 0) && ZoneNameIsBand(nm);
}

//+------------------------------------------------------------------+
//| P-PERF-32b — THE TRIGGER FAMILY'S OWN MASK WALK.                  |
//|                                                                   |
//| THE DEFECT IT CLOSES: «سطوح تریگر دیر خاموش و روشن میشه» — the     |
//| T hotkey, the ring's TRIGGER light and the card's SHOW row all     |
//| flipped `g_triggerLevelsEnabled` and then asked the RENDER for     |
//| the pixels, so the picture waited for a whole heavy frame (and the |
//| render had to rebuild a family the OFF press had deleted). The     |
//| structure switches (card 11, P-PERF-32) have painted in their own  |
//| event since they were fixed — state, a walk over the objects that  |
//| own the property, one discrete repaint — and the frame is never    |
//| the owner of the feedback. This is that technique for the family   |
//| whose property IS its mask.                                        |
//|                                                                   |
//| ONE OWNER FOR THE PROPERTY: the walk writes through                |
//| `SetPipelineZoneVisibility` — the render's own writer — so which   |
//| objects a zone is made of, and which of them L owns, is spelled    |
//| once. This walk only decides WHICH cached `_Zone_` names are       |
//| trigger bands: the ladder's own classification                     |
//| (`GetHighestStructureLevel(step, g_cachedIntervals) <= 0`, the     |
//| same test ClassifyLevels and StructureRecolourWalk use), read      |
//| from the name's step (sub-objects included: their band decides).   |
//|                                                                   |
//| BOUNDED BY THE CACHE, like every sibling walk: one hash probe per  |
//| occupied slot, zero ObjectName calls, zero type probes, and a      |
//| guarded mask write that is FREE when that object is already right. |
//| `seen` = the trigger bands the walk found (0 says the chart does   |
//| not carry the family yet, which is the one case that still needs a |
//| render to build it), return = the masks that really reached the    |
//| chart. Both numbers are printed by the press that paid for them.   |
//+------------------------------------------------------------------+
int TriggerFamilyWalk(const bool on, int &seen)
{
    seen = 0;
    int written = 0;
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++)
    {
        if(!g_objectCacheHash[i].occupied) continue;
        visited++;
        if(!CacheSlotIsLive(i)) continue;         // P-UI-62: liveness is the permission to touch
        const string nm = g_objectCacheHash[i].name;
        if(StringFind(nm, "_Zone_") < 0) continue;         // lines/labels/HTF
        if(StringFind(nm, "_Zone_Center_") >= 0) continue; // mode colour, not a ladder band
        if(StringFind(nm, "_BK_") >= 0) continue;          // independent layer (P-BK-01)
        if(!ZoneNameIsBand(nm)) continue;                   // a sub-object: its band decides
        int step = StructureZoneStepFromName(nm);
        if(step <= 0) continue;
        if(GetHighestStructureLevel(step, g_cachedIntervals) > 0) continue;   // a structure tier
        seen++;
        written += SetPipelineZoneVisibility(nm, on);
    }
    return written;
}

//+------------------------------------------------------------------+
//| P-LEVEL-FOREIGN-02 — EXACTLY THE PRODUCED SET, OR NOTHING.        |
//|                                                                  |
//| Reported (after the P-PERF-38d handoff landed): «سطوح که باید   |
//| نمایش بده نمایش نمیده، و سطوحی که توی دید نیست رو نمایش میده   |
//| — برعکس» — the family near the price is not drawn while objects  |
//| far outside the window are.                                       |
//|                                                                  |
//| That is ONE structural defect with two faces. The family on the   |
//| chart must be EXACTLY the set the current build produces; nothing |
//| enforced it, so the kept objects of a former geometry (a wider    |
//| window, another pitch, another timeframe) could stay VISIBLE       |
//| outside the window while the produced set could be attacked from   |
//| the other side. The previous attempt at this walked the indices    |
//| from `maxStep + 1` upward, which is only right when the numbering  |
//| is contiguous AND `${fam}` ... `maxStep` is a window/geometry     |
//| quantity, not a name-space bound.                                 |
//|                                                                  |
//| So the question this pass asks is the only exact one: "is this     |
//| chart name one of the names the build just produced?" - and the    |
//| answer is available for free, because the build is standing in     |
//| this very call with `lines[]` and `zones[]` in hand.               |
//|                                                                  |
//| Two faces it closes, in one pass:                                  |
//|   * a survivor the build does not produce is DELETED (whatever its |
//|     index, pitch or price) - the far visible objects go;           |
//|   * a name the build DOES produce is left alone, so the render     |
//|     re-asserts it in place (the cache-first creator updates an      |
//|     existing object) - which is what makes the handoff cheaper      |
//|     than the wipe it replaced.                                     |
//|                                                                  |
//| NOTHING is deleted when the window is not usable (`vpTop >         |
//| vpBottom > 0`) or the build produced nothing: an unusable window   |
//| means the produced set is not trustworthy, and the next real pass  |
//| re-derives it and re-creates whatever is missing. A delete-every-  |
//| thing-then-rebuild flash on an attach is exactly the class of bug  |
//| this project refuses to trade a flicker for.                        |
//+------------------------------------------------------------------+
int SweepForeignLadderObjects(const SModeConfig &config,
                              const STriggerLine &lines[],
                              const int lineCount,
                              const SZoneDefinition &zones[],
                              const int zoneCount,
                              const double vpTop,
                              const double vpBottom)
{
    if(!(vpTop > vpBottom) || vpBottom <= 0) return 0;   // unusable window: no judgement
    if(lineCount <= 0) return 0;                        // nothing produced: nothing to say

    // What this build owns, by NAME (labels included: a line and its pip label
    // are one decision, and RenderTriggerLines writes both).
    string produced[];
    int pc = 0;
    ArrayResize(produced, lineCount * 2 + zoneCount);
    for(int l = 0; l < lineCount; l++)
    {
        produced[pc++] = lines[l].name;
        produced[pc++] = lines[l].name + "_Label";
    }
    for(int z = 0; z < zoneCount; z++)
        produced[pc++] = zones[z].name;

    const string fam = config.objectPrefix + config.modeName + "_";
    const int total = ObjectsTotal(0, -1, -1);
    string doomed[];
    int nd = 0;

    for(int i = total - 1; i >= 0; i--)
    {
        const string nm = ObjectName(0, i, -1, -1);
        if(!LadderFamilyName(nm, fam)) continue;

        if(LadderNameIsZoneBand(nm))
        {
            if(ProducedLadderName(nm, produced, pc)) continue;
            ArrayResize(doomed, nd + 1);
            doomed[nd++] = nm;
            continue;
        }
        if(StringFind(nm, "_Zone_") >= 0) continue;   // a border sub-object: its band decides

        if(ProducedLadderName(nm, produced, pc)) continue;
        ArrayResize(doomed, nd + 1);
        doomed[nd++] = nm;
    }

    if(nd == 0) return 0;

    g_suppressDeleteEvents = true;
    int removed = 0;
    for(int d = 0; d < nd; d++)
    {
        if(StringFind(doomed[d], "_Zone_") >= 0)
        {
            if(DeleteManagedZoneObjects(doomed[d], true)) removed++;
        }
        else if(DeleteIndicatorObjectManaged(doomed[d], true)) removed++;
    }
    g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
    g_suppressDeleteEvents = false;
    return removed;
}

SPipelineResult ExecutePipeline(
    const SModeConfig &config,
    const double centerPrice,
    const double &stepSizes[],
    const int stepSizeCount,
    const ENUM_LEVEL_STEP_MODE stepMode,
    const ENUM_CLASSIFY_MODE classifyMode,
    const bool lsFirst,
    const int maxLevelsAbove,
    const int maxLevelsBelow,
    const double vpTop,
    const double vpBottom,
    const int buildStage)
{
    SPipelineResult result;
    result.zoneCount = 0;
    result.lineCount = 0;
    result.success = false;
    result.errorMessage = "";
    
    if(centerPrice <= 0) {
        result.errorMessage = "Invalid center price";
        return result;
    }
    for(int s = 0; s < stepSizeCount; s++) {
        if(stepSizes[s] <= 0) {
            result.errorMessage = "Invalid step size";
            return result;
        }
    }
    
    bool triggerEnabled = IsTriggerLevelsEnabled();
    int baseMultiplier = GetValidatedBaseMultiplier();
    // P-PERF-06: the cull window arrives from the caller (RedrawAllObjects owns
    // the hysteretic window AND the staging snapshot — deriving it here a
    // second time could split staged families across two viewports).

    double fixedZoneStepSize = 0.0;
    if(config.modeName == "SSLS" && stepSizeCount > 1)
        fixedZoneStepSize = MathMin(stepSizes[0], stepSizes[1]);

    SZoneDefinition zones[];
    STriggerLine lines[];
    int maxStep = 0;

    //                                                                
    // P-PERF-18: THE STAGED REBUILD WAS RE-COMPUTING THE SAME MATH    
    //                                                                
    // P-PERF-06 splits a post-wipe rebuild (attach / TF switch /       
    // topology toggle) into four frames - lines, zones, labels, block  
    // - and every one of those frames called this function again, so   
    // CalculateLevels -> ClassifyLevels/Alternating -> BuildZonesAnd-  
    // Lines ran FOUR times with IDENTICAL inputs: on the weakest        
    // machine that is four times the level arithmetic and four times   
    // four times the label strings, for one switch. This is the         
    // "compute it once, at the right moment" rule (LEARNING §16): the   
    // staged frames are by construction "same geometry, another          
    // family", so the built lists are remembered under a key made of    
    // every input the three stages read. A tick that moves the base     
    // price, a scroll that moves the cull window, an input edit, or a   
    // mode switch changes the key and the math runs again - the cache   
    // can only ever answer for an unchanged geometry.                   
    //                                                                
    string geoKey = PipelineGeometryKey(config, centerPrice, stepSizes, stepSizeCount,
                                       stepMode, classifyMode, lsFirst, maxLevelsAbove,
                                       maxLevelsBelow, vpTop, vpBottom,
                                       baseMultiplier);
    static string s_geoKey = "";
    static bool   s_geoValid = false;
    static SZoneDefinition s_geoZones[];
    static STriggerLine    s_geoLines[];
    static int    s_geoZoneCount = 0;
    static int    s_geoLineCount = 0;
    static int    s_geoMaxStep = 0;
    // P-LEVEL-FOREIGN-01: the ladder signature the foreign-object sweep last ran
    // against. "" means "never run" - the first real build always sweeps, which
    // is what cleans a chart that a previous instance left a foreign pitch on.
    static string s_lastStepSig = "";
    // P-LEVEL-FOREIGN-02: the chart walk below runs at most ONCE per instance.
    // The handoff is a per-instance event (the first real build of the new
    // instance is the frame after the switch), while a later intraday pitch
    // drift is not - and a whole-chart walk is ~26 ms on a chart carrying 800
    // objects, so it may not become a tax on every step-size refresh. Nothing
    // regresses by stopping there: before this sweep existed NO index was ever
    // swept on a drift either, and the price sweep plus the 6-miss index walk
    // still run on every pitch change.
    static bool s_foreignSweepDone = false;

    if(s_geoValid && geoKey == s_geoKey) {
        // Same geometry, another family: copy the built lists, skip the math.
        ArrayResize(zones, s_geoZoneCount);
        for(int z = 0; z < s_geoZoneCount; z++) zones[z] = s_geoZones[z];
        ArrayResize(lines, s_geoLineCount);
        for(int l = 0; l < s_geoLineCount; l++) lines[l] = s_geoLines[l];
        result.zoneCount = s_geoZoneCount;
        result.lineCount = s_geoLineCount;
        maxStep = s_geoMaxStep;
    }
    else {
        // Stage 1: Calculate (unified)
        SCalculatedLevel rawLevels[];
        int rawCount = CalculateLevels(centerPrice, stepSizes, stepSizeCount, stepMode,
                                        lsFirst, maxLevelsAbove, maxLevelsBelow,
                                        config.boundByHistorical, config.maxPrice, config.minPrice,
                                        rawLevels, maxStep);
        if(rawCount == 0) {
            result.errorMessage = "No levels calculated";
            s_geoValid = false;   // never serve a geometry for a config that produced none
            return result;
        }

        // Stage 2: Classify (mode-specific variant)
        SLevelClassified classified[];
        int classifiedCount = 0;
        switch(classifyMode) {
            case CLASSIFY_ALTERNATING:
                classifiedCount = ClassifyLevelsAlternating(rawLevels, rawCount, config,
                                                            triggerEnabled, baseMultiplier, lsFirst,
                                                            classified);
                break;
            default: // CLASSIFY_STANDARD
                classifiedCount = ClassifyLevels(rawLevels, rawCount, config,
                                                  triggerEnabled, baseMultiplier, classified);
                break;
        }

        // Stages 3+4: Build zones and lines (merged   single pass)
        BuildZonesAndLines(classified, classifiedCount, config, vpTop, vpBottom,
                           fixedZoneStepSize, zones, result.zoneCount, lines, result.lineCount);

        // Remember the result for the other families of this same rebuild.
        ArrayResize(s_geoZones, result.zoneCount);
        for(int zc = 0; zc < result.zoneCount; zc++) s_geoZones[zc] = zones[zc];
        ArrayResize(s_geoLines, result.lineCount);
        for(int lc = 0; lc < result.lineCount; lc++) s_geoLines[lc] = lines[lc];
        s_geoZoneCount = result.zoneCount;
        s_geoLineCount = result.lineCount;
        s_geoMaxStep = maxStep;
        s_geoKey = geoKey;
        s_geoValid = true;

        // P-LEVEL-FOREIGN-01: the ladder itself moved (a timeframe switch, a mode
        // change, an ATR-scaling regime change), so objects written by the
        // previous pitch are still on the chart with valid names and valid step
        // indices - and no sweep in the project could recognise them. This is the
        // one moment they can be identified: against the lists just built. Runs
        // BEFORE the render below, which re-creates whatever is in the viewport.
        {
            string stepSig = IntegerToString((int)stepMode) + "," + IntegerToString(stepSizeCount);
            for(int ss = 0; ss < stepSizeCount; ss++) stepSig += "," + DoubleToString(stepSizes[ss], 8);
            // P-UI-153 (2026-10-02) — A HAND MID-DRAG DOES NOT SWEEP THE PITCH.
            //
            // User order: «هنوز هم مثل خود خط کاستوم پرایس ریل تایم واقعی نشده ...
            // برای اون نقاط قرمز معماری شئ کپی کن». MEASURED FIRST, on the flushed
            // channel, by pricing the ONE frame owner both hand-set gestures share
            // (P-UI-152's `[drag]` witness):
            //   the custom price LINE drag  ->  ms=0..16,  lv=0..16
            //   the step-1 handle drag      ->  ms=172..203, lv == ms, on EVERY step
            // So the whole cost of a step-1 step is the LEVELS phase, and this pass
            // is why: the handle's drag changes the STEP SIZES, `stepSig` therefore
            // changes on every held event, and this block runs on every one of them.
            // It then finds the cache's `lastPrice` for the SAME name disagreeing
            // with the new pitch (the family has just moved) and DELETES those
            // objects - so the render that follows re-CREATES a whole family per
            // step (ObjectDelete + ObjectCreate + every property) instead of
            // re-pricing it in place. The custom price line's drag never trips this
            // pass: it moves the CENTRE, the step sizes and `stepSig` are untouched,
            // and its frames are the render alone (16 ms). THAT is the architecture
            // the user asked to copy, and this is the half of it the handle lacked.
            //
            // The pass's own reason to exist is "the ladder ITSELF moved": a
            // timeframe switch, a mode change, an ATR-scaling regime change - the
            // moments in which nothing else can name the objects a previous pitch
            // left behind. A hand on the handle is none of those: the same names are
            // about to be re-asserted at the new pitch by the render line below, and
            // whatever the new ladder no longer produces is removed by
            // `CleanupSurplusPipeline`, which already throttles itself to 250 ms for
            // a live gesture for exactly this reason.
            //
            // So the pass is DEFERRED, never dropped: `s_lastStepSig` is left stale
            // on purpose while a gesture is live, and the release's own forced frame
            // (both drag flags are down by then) sweeps ONCE against the final pitch
            // - the frame that can afford it. This also retires the P-UI-98k hazard
            // at its source: the pass that could delete the very line under the hand
            // no longer runs under the hand at all.
            if(stepSig != s_lastStepSig && !g_s1DragLive && !g_customPriceLineDragging)
            {
                s_lastStepSig = stepSig;
                int swept = SweepForeignLevelObjects(config, lines, result.lineCount,
                                                     zones, result.zoneCount);
                if(swept > 0)
                    _LOG_GATE_I Print("[I][GEN] P-LEVEL-FOREIGN-01: swept ", swept,
                                      " level object(s) left by a previous step geometry");
                // P-LEVEL-FOREIGN-02: and the names that sweep cannot reach - the
                // ones the new ladder does not produce AT ALL, which its own lists
                // can never name. This is what lets a timeframe switch UPDATE the
                // family in place (the render re-asserts every produced name, this
                // deletes the rest) instead of wiping and rebuilding it, and it is
                // only meaningful after a HANDOFF: a wiped chart holds nothing to
                // find, and this is a whole-chart walk.
                if(g_adoptPreviousTopology && !s_foreignSweepDone)
                {
                    s_foreignSweepDone = true;   // this frame IS the handoff
                    int stale = SweepForeignLadderObjects(config, lines, result.lineCount,
                                                          zones, result.zoneCount,
                                                          vpTop, vpBottom);
                    if(stale > 0)
                        _LOG_GATE_W Print("[W][GEN] P-LEVEL-FOREIGN-02: deleted ", stale,
                                          " ladder object(s) this build does not produce ",
                                          "(handoff, family=", config.modeName, ")");
                }
            }
        }
    }
    
    // Stage 5: Render and cleanup.
    // P-PERF-06 STAGED RENDER: the math above (Calculate/Classify/Build) is
    // pure CPU (~ms) and re-runs every stage; only ONE object family is
    // materialised per frame, so a post-wipe build lands as four ~2k-call
    // frames instead of one ~8k-call freeze. buildStage 0 (or anything
    // unexpected) is the full legacy render — steady frames always take it.
    if(buildStage == BUILD_STAGE_LINES) {
        RenderTriggerLines(lines, result.lineCount, config, true, false, vpTop, vpBottom);
    } else if(buildStage == BUILD_STAGE_ZONES) {
        RenderZones(zones, result.zoneCount, config, vpTop, vpBottom);
    } else if(buildStage == BUILD_STAGE_LABELS) {
        RenderTriggerLines(lines, result.lineCount, config, false, true, vpTop, vpBottom);
        // PERF: maxStep already known from CalculateLevels output (no extra O(n) scan needed)
        CleanupSurplusPipeline(config, maxStep);
    } else {
        RenderZones(zones, result.zoneCount, config, vpTop, vpBottom);
        RenderTriggerLines(lines, result.lineCount, config, true, true, vpTop, vpBottom);

        // PERF: maxStep already known from CalculateLevels output (no extra O(n) scan needed)
        CleanupSurplusPipeline(config, maxStep);
    }
    
    // ══════════════════════════════════════════════════════════════════════
    // P-VIEW-04 (2026-09-29) — THE "MIDDLE BAND IS EMPTY" CENSUS, ONE LINE,
    // ONE NUMBER PER STAGE. Reported by the user with a screenshot (EURUSD M15,
    // price 1.139): the family was drawn from 1.15185 up to 1.17630 and two rungs
    // at the bottom (1.11520 / 1.11250), while the whole band between them — nine
    // rungs on the SAME pitch — was absent. A hole in the MIDDLE cannot be explained
    // by a count limit at either end, so the loss is somewhere in the chain
    //   ladder -> classified -> BuildZonesAndLines -> RenderTriggerLines -> object
    // and this line says WHERE, once, with numbers:
    //   lines=<built>  nearAbove/nearBelow = the closest built line to the centre on
    //   each side (a build whose nearest above is 3 pitches away IS the hole, said
    //   numerically), pitch=maxStep, span=[lo..hi] of the built list, then the two
    //   object-level answers that separate the two remaining causes:
    //     absent=<n>  the name is in `lines[]` but NO object holds it   -> deleted/
    //                 name collision (a sweep, a duplicate logicalStep);
    //     hidden=<n>  the object exists but its mask is not ALL_PERIODS -> a mask
    //                 writer owns it (F / L / a per-TF rule).
    // A still picture prints nothing: the guard is the shape itself, so this costs
    // one string compare per rebuild and one line of log per SHAPE change.
    {
        static string s_lastViewCensus = "";
        string shape = IntegerToString(result.lineCount) + ":" + IntegerToString(result.zoneCount) + ":" +
                       DoubleToString(vpTop - vpBottom, GetCachedDigits());
        if(shape != s_lastViewCensus)
        {
            s_lastViewCensus = shape;
            double lo = 0.0, hi = 0.0;
            double nearAbove = 0.0, nearBelow = 0.0;
            int absent = 0;
            long rawMask = 0, maskMin = 0, maskMax = 0;
            for(int ci = 0; ci < result.lineCount; ci++)
            {
                double p = lines[ci].price;
                if(lo == 0.0 || p < lo) lo = p;
                if(p > hi) hi = p;
                if(p > centerPrice && (nearAbove == 0.0 || p < nearAbove)) nearAbove = p;
                if(p < centerPrice && (nearBelow == 0.0 || p > nearBelow)) nearBelow = p;
                if(ObjectFind(0, lines[ci].name) < 0) absent++;
                else
                {
                    // P-VIEW-04b: the mask is compared against OBJ_NO_PERIODS and the
                    // RAW value is carried out with it. `!= OBJ_ALL_PERIODS` was a
                    // WRONG test and it said `hidden=288` of 288 lines on a chart that
                    // visibly paints its levels: MT4 stores "every timeframe" as a
                    // 32-bit -1, while the constant's own value can be read as
                    // 0xFFFFFFFF, so a signed-long compare calls every VISIBLE object
                    // hidden. OBJ_NO_PERIODS is 0 on both sides of that edge.
                    // P-VIEW-04c: NOT `hidden++`. The census must not depend on
                    // OBJ_NO_PERIODS vs OBJ_ALL_PERIODS being distinct numbers in this
                    // compiler: measured `rawMask=-1` on every level of a chart that
                    // paints them, while the counter built on `== OBJ_NO_PERIODS`
                    // called all of them hidden — i.e. the two constants share the
                    // value -1 here and the comparison proves nothing. The FACT is the
                    // range of the raw masks across the family: `maskMin=maskMax=-1`
                    // means every level carries the same mask the painter wrote.
                    long m = (long)ObjectGetInteger(0, lines[ci].name, OBJPROP_TIMEFRAMES);
                    if(ci == 0) { rawMask = m; maskMin = m; maskMax = m; }
                    if(m < maskMin) maskMin = m;
                    if(m > maskMax) maskMax = m;
                }
            }
            Print("[P-VIEW] stage=census lines=", result.lineCount, " zones=", result.zoneCount,
                  " pitch=", DoubleToString(maxStep, GetCachedDigits()),
                  " centre=", DoubleToString(centerPrice, GetCachedDigits()),
                  " nearAbove=", DoubleToString(nearAbove, GetCachedDigits()),
                  " nearBelow=", DoubleToString(nearBelow, GetCachedDigits()),
                  " span=", DoubleToString(lo, GetCachedDigits()), "..", DoubleToString(hi, GetCachedDigits()),
                  " absent=", absent, " mask=", (int)maskMin, "..", (int)maskMax,
                  " win=", DoubleToString(vpBottom, GetCachedDigits()), "..", DoubleToString(vpTop, GetCachedDigits()),
                  " stage=", buildStage);
        }
    }

    result.success = true;
    return result;
}

//+------------------------------------------------------------------+
//| SUFFIX REGISTRY: Centralized suffix tracking                     |
//|                                                                  |
//| All mode suffixes registered in one place.                       |
//| Adding a new mode = add one entry here.                          |
//+------------------------------------------------------------------+
struct SModeSuffixEntry {
    string zoneSuffix;      // e.g., "SSLS_Zone_"
    string levelAbove;      // e.g., "SSLS_Above_"
    string levelBelow;      // e.g., "SSLS_Below_"
    string midpoint;        // e.g., "SSLS_Midpoint_"
    string zoneCenter;      // e.g., "SSLS_Zone_Center_"   zone on midpoint/anchor level
};

// GetAll registered mode suffixes   used by ClearAllLevels and DeleteAllIndicatorObjects
void GetAllModeSuffixes(SModeSuffixEntry &entries[], int &count)
{
    static string modeNames[] = {"SSLS", "Combo", "Factor", "Factor_Harmonic", "TH_Level"};
    count = ArraySize(modeNames);
    ArrayResize(entries, count);
    
    for(int i = 0; i < count; i++) {
        entries[i].zoneSuffix = modeNames[i] + "_Zone_";
        entries[i].levelAbove = modeNames[i] + "_Above_";
        entries[i].levelBelow = modeNames[i] + "_Below_";
        entries[i].midpoint = modeNames[i] + "_Midpoint_";
        entries[i].zoneCenter = modeNames[i] + "_Zone_Center_";
        
        // Manual overrides for non-standard legacy suffixes
        if(modeNames[i] == "Factor") entries[i].midpoint = "Factor_Center_";
        if(modeNames[i] == "Factor_Harmonic") entries[i].midpoint = "Factor_Harmonic_Center_";
    }
}

// Get all zone suffixes as a flat array (for ClearAllLevels compatibility)
void GetAllZoneSuffixes(string &suffixes[], int &count)
{
    SModeSuffixEntry entries[];
    int entryCount = 0;
    GetAllModeSuffixes(entries, entryCount);
    
    // Each mode has 2 zone suffix families: zoneSuffix (Above/Below) + zoneCenter
    count = entryCount * 2;
    ArrayResize(suffixes, count);
    int idx = 0;
    for(int i = 0; i < entryCount; i++) {
        suffixes[idx++] = entries[i].zoneSuffix;
        suffixes[idx++] = entries[i].zoneCenter;
    }
    count = idx;
}

// Get all level suffixes as a flat array (for ClearAllLevels compatibility)
void GetAllLevelSuffixes(string &suffixes[], int &count)
{
    SModeSuffixEntry entries[];
    int entryCount = 0;
    GetAllModeSuffixes(entries, entryCount);
    
    // Each mode has 3 level suffixes (above, below, midpoint)
    // Plus legacy suffixes for backward compatibility
    count = entryCount * 3;
    ArrayResize(suffixes, count);
    int idx = 0;
    for(int i = 0; i < entryCount; i++) {
        suffixes[idx++] = entries[i].levelAbove;
        suffixes[idx++] = entries[i].levelBelow;
        suffixes[idx++] = entries[i].midpoint;
    }
    count = idx;
}

#endif // LEVEL_PIPE_B_MQH
