  #property strict

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
    datetime currentTime = TimeCurrent();
    datetime futureTime = currentTime + PeriodSeconds(Period()) * 10000;
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
            #ifdef ENABLE_DEBUG_LOGS
            int error = GetLastError();
            Print("  CreateTHLineObject: Failed to create '", name, "', error=", error);
            #endif
            return false;
        }
    } else {
        // Object exists - just update price if changed
        if(MathAbs(cachedEntry.lastPrice - normalizedPrice) > Point * 0.1) {
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
    
    // TOOLTIP PERF: String comparison is faster than syscall
    // Note: Tooltip isn't in SObjectCacheEntry, but we can assume if price/color/style/width didn't change, 
    // tooltip likely didn't change enough to matter, or we can just update it.
    // For now, let's just update it since it's a single string call.
    ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
    
    if(!objectExistsInCache) {
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, isSelectable);
        ObjectSetInteger(0, name, OBJPROP_BACK, false);
    }
    
    // Update cache
    CacheUpdateObject(name, normalizedPrice, lineColor, (int)style, width);
    
    // CRITICAL FIX: Respect BOTH Hide state (F key) AND Lines visibility (L key)
    // PERFORMANCE: Use TTL-cached IsIndicatorHidden() instead of GlobalVariableGet
    bool isHidden = IsIndicatorHidden();
    
    if(isHidden || !g_linesVisible) {
        ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    } else {
        ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    
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
        ObjectSetDouble(0, name, OBJPROP_PRICE, price);
    }

    CacheUpdateLabel(name, labelText, textColor);
    ApplyVisibilityStateIfUnchangedSkip(name, false);
    
    return true;
}
