  #property strict

#ifndef OBJECT_FUNCTIONS_MQH
#define OBJECT_FUNCTIONS_MQH

//==============================================================================
// P-PERF-38 / P-PERF-38e — ONE LEVEL-OBJECT PREFIX, AND IT DOES NOT NAME THE
// TIMEFRAME (and the create path must therefore ADOPT what it finds)
//
// P-PERF-38e, see CreateTHLineObject: keeping the family across a timeframe
// switch means the reloaded instance meets objects its empty cache has never
// seen, and MT4 refuses ObjectCreate for a name that already exists. This file
// is the one place whose existence decision comes from the cache instead of a
// chart probe, so it is the one place that had to learn to adopt.
//
// The prefix was `inpObjectPrefix + "_" + <TF> + "_"` and it was built at
// FOURTEEN call sites. Two consequences, and both of them are the reported
// "changing the timeframe recomputes and redraws my levels":
//
//   1. A timeframe switch RENAMED every object the level family owns. The old
//      namespace had to be deleted and the new one created from scratch - ~900
//      deletes + ~900 creates, on a switch that only changes the PRICES. MT4
//      forces a deinit+init on a chart period change, so the objects also had to
//      survive that teardown to be reusable at all (see OnDeinitHandler).
//   2. Fourteen builders of one name is fourteen chances to disagree, and one
//      disagreement is an orphaned object no cleanup can reach - every suffix
//      list in ClearAllLevels/DeleteAllIndicatorObjects is prefix-scoped.
//
// So the prefix has ONE owner and it is timeframe-free. The timeframe still
// changes the picture - `GetTimeframeTH()` feeds `thValue`, so the level prices
// genuinely differ per timeframe - but it now changes the picture through the
// SIGNATURE, which re-renders IN PLACE, instead of through the NAME, which
// forced a rebuild.
//
// Collision check for the chosen namespace (`inpObjectPrefix + "_"` = "THLevels_"):
//   Base/Knot  -> "Biotak_BK_"          (hard-coded, never this prefix)
//   ATR/TH     -> "THLevelsATR_" / "THLevelsTH_"  (no underscore separator)
//   patterns   -> "THLevelsSharedPattern_"        (no underscore separator)
//   HTF        -> "Biotak_HTF_<id>_"             (separate namespace)
// so the ONE bulk delete that targets it (DeleteAllIndicatorObjects) removes the
// level family and nothing else.
string GetLevelObjectPrefix()
{
   return inpObjectPrefix + "_";
}
bool CreateTHLineObject(const string name, const double price, const color lineColor, const ENUM_LINE_STYLE style, const int width, const string tooltip, ENUM_LINE_OBJECT_TYPE lineObjectType, bool isSelectable = false) {
    //                                                                
    // CRITICAL FIX #1: Check object count BEFORE creation
    //                                                                
    if(!CanCreateObject()) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateTHLineObject: Object limit reached, cannot create '", name, "'");
        #endif
        return false;
    }
    
    //                                                                
    // CRITICAL FIX #2: Validate object name
    //                                                                
    if(StringLen(name) == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateTHLineObject: Empty object name");
        #endif
        return false;
    }
    
    //                                                                
    // CRITICAL FIX #3: Validate price using FloatingPointHelper
    //                                                                
    if(!IsValidPrice(price)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreateTHLineObject: Invalid price (", price, ") for '", name, "'");
        #endif
        return false;
    }
    
    // OPTIMIZATION: Check if object exists first, only update properties instead of recreate
    double normalizedPrice = NormalizePrice(price);
    datetime currentTime = CacheGetFrameTime();
    if(currentTime == 0) currentTime = TimeCurrent();
    // PERF FIX: Cache PeriodSeconds(Period()) - it's constant per bar
    static int s_cachedPeriodSecs = 0;
    static int s_cachedPeriodForSecs = 0;
    int curPeriod = GetCachedPeriod();
    if(s_cachedPeriodForSecs != curPeriod || s_cachedPeriodSecs == 0) {
        s_cachedPeriodSecs = PeriodSeconds(curPeriod);
        s_cachedPeriodForSecs = curPeriod;
    }
    datetime futureTime = currentTime + s_cachedPeriodSecs * 10000;
    int objectType = (lineObjectType == LINE_OBJECT_RAY_LINE) ? OBJ_TREND : OBJ_HLINE;
    
    // Check if object already exists in cache
    SObjectCacheEntry cachedEntry;
    bool objectExistsInCache = CacheGetObject(name, cachedEntry);
    if(objectExistsInCache && cachedEntry.exists && ObjectFind(0, name) < 0) {
        CacheRemoveObject(name);
        objectExistsInCache = false;
    }
    
    if(!objectExistsInCache) {
        // Create new object
        if(!ObjectCreate(0, name, objectType, 0, currentTime, normalizedPrice, (objectType == OBJ_TREND ? futureTime : 0), normalizedPrice)) {
            // P-PERF-38e — ADOPT AN OBJECT THE CACHE HAS NEVER SEEN.
            //
            // MT4 refuses ObjectCreate for a name that already exists (error
            // 4200, docs.mql4.com/objects/objectcreate), and this site is the
            // one creation path in the level/label families that decides
            // existence from the CACHE rather than from the chart (ZoneRenderer,
            // ZoneFactory, CreateLevelLine, CreatePipDistanceLabel and the rest
            // all probe ObjectFind first, so they were already safe).
            //
            // That was invisible until P-PERF-38b/38d made the level family
            // SURVIVE a timeframe switch: the reloaded instance's cache starts
            // EMPTY while the chart still holds the objects, so the first
            // render of every adopted instance met this branch. Treating the
            // refusal as a hard failure was doubly wrong — the line kept the
            // PREVIOUS timeframe's price, and the `return false` abandoned the
            // caller's remaining family (the High/Low pair and their pip
            // labels).
            //
            // So an object that is on the chart but not in the cache is ADOPTED:
            // its price is written for THIS timeframe, and the guarded writes
            // below run unconditionally once (there is no cached state to
            // compare against) before CacheUpdateObject records the real values,
            // so every later frame is fully guarded again. Cost: one ObjectFind
            // per adopted object, on the adopted frame only.
            if(ObjectFind(0, name) < 0) {
                #ifdef ENABLE_DEBUG_LOGS
                int error = GetLastError();
                Print("  CreateTHLineObject: Failed to create '", name, "', error=", error);
                #endif
                return false;
            }
            ObjectSetDouble(0, name, OBJPROP_PRICE, normalizedPrice);
        }
    } else {
        // Object exists - just update price if changed
        if(MathAbs(cachedEntry.lastPrice - normalizedPrice) > GetCachedPoint() * 0.1) {
            if(!ObjectSetDouble(0, name, OBJPROP_PRICE, normalizedPrice)) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("   CreateTHLineObject: Failed to update price for '", name, "'");
                #endif
            }
        }
    }
    
    // Set properties only if they changed
    if(!objectExistsInCache || cachedEntry.lastColor != lineColor)
        ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
    
    if(!objectExistsInCache || cachedEntry.lastStyle != (int)style)
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    
    if(!objectExistsInCache || cachedEntry.lastWidth != width)
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    
    // TOOLTIP PERF (P-PERF-02): a tooltip write is a string write AND a chart
    // dirty mark. This runs per line per heavy frame, so it must be guarded
    // like every other property: compare against the string we last wrote.
    string haveTip = "";
    if(!CacheGetTooltip(name, haveTip) || haveTip != tooltip)
    {
        ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
        CacheSetTooltip(name, tooltip);
    }
    
    if(!objectExistsInCache) {
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, isSelectable);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
    }
    
    // Update cache
    CacheUpdateObject(name, normalizedPrice, lineColor, (int)style, width);
    
    // CRITICAL FIX: Respect BOTH Hide state (F key) AND Lines visibility (L key)
    // PERFORMANCE: Use TTL-cached IsIndicatorHidden() instead of GlobalVariableGet
    // P-PERF-02: guarded write (the mask repeats on every heavy frame).
    bool isHidden = IsIndicatorHidden();
    ApplyTfMaskGuarded(name, (isHidden || !g_linesVisible) ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    
    return true;
}

bool CreatePipDistanceLabel(const string name, const double price, const double pips, const color textColor, const string levelInfo = "") {
    if(!inpShowPipDistanceLabels) return true;
    
    //                                                                
    // CRITICAL FIX #1: Check object count BEFORE creation
    //                                                                
    if(!CanCreateObject()) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreatePipDistanceLabel: Object limit reached, cannot create '", name, "'");
        #endif
        return false;
    }
    
    //                                                                
    // CRITICAL FIX #2: Validate inputs
    //                                                                
    if(StringLen(name) == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreatePipDistanceLabel: Empty label name");
        #endif
        return false;
    }
    
    if(!IsValidPrice(price)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  CreatePipDistanceLabel: Invalid price (", price, ")");
        #endif
        return false;
    }

    // Format: "M1 +3 | 45.2 pips" or just "45.2 pips" if no levelInfo
    string labelText;
    if(StringLen(levelInfo) > 0) {
        labelText = StringFormat("%s | %.1f", levelInfo, pips);
    } else {
        labelText = StringFormat("%.1f pips", pips);
    }

    string cachedText;
    color cachedColor;
    bool hasCachedLabel = CacheGetLabel(name, cachedText, cachedColor);
    bool objectExists = false;
    if(hasCachedLabel) {
        objectExists = (ObjectFind(0, name) >= 0);
        if(!objectExists) {
            CacheRemoveObject(name);
            hasCachedLabel = false;
        }
    } else {
        objectExists = (ObjectFind(0, name) >= 0);
    }

    if(!objectExists) {
        if(!ObjectCreate(0, name, OBJ_TEXT, 0, 0, price)) {
            #ifdef ENABLE_DEBUG_LOGS
            int error = GetLastError();
            Print("  CreatePipDistanceLabel: Failed to create '", name, "', error=", error);
            #endif
            return false;
        }
        ObjectSetString(0, name, OBJPROP_TEXT, labelText);
        ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
        ObjectSetString(0, name, OBJPROP_FONT, inpFontName);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, inpFontSize);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
    } else {
        if(!hasCachedLabel || cachedText != labelText)
            ObjectSetString(0, name, OBJPROP_TEXT, labelText);
        if(!hasCachedLabel || cachedColor != textColor)
            ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
        // P-PERF-02: the pip-distance label follows a level that is stable for
        // minutes, but this write used to land on EVERY heavy frame. Compare
        // against the cached price first (a label's price IS cached).
        double havePrice = 0.0;
        if(!CacheGetPrice(name, havePrice) || MathAbs(havePrice - price) > GetCachedPoint() * 0.1)
            ObjectSetDouble(0, name, OBJPROP_PRICE, price);
    }

    CacheUpdateLabel(name, labelText, textColor);
    CacheSetPrice(name, price);
    ApplyVisibilityStateIfUnchangedSkip(name, false);

    return true;
}

#endif // OBJECT_FUNCTIONS_MQH
