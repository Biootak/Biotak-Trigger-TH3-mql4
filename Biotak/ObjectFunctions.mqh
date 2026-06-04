#property strict

bool CreateTHLineObject(const string name, const double price, const color lineColor, const ENUM_LINE_STYLE style, const int width, const string tooltip, ENUM_LINE_OBJECT_TYPE lineObjectType, bool isSelectable = false) {
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #1: Check object count BEFORE creation
    // ═══════════════════════════════════════════════════════════════
    if(!CanCreateObject()) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateTHLineObject: Object limit reached, cannot create '", name, "'");
        #endif
        return false;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #2: Validate object name
    // ═══════════════════════════════════════════════════════════════
    if(StringLen(name) == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateTHLineObject: Empty object name");
        #endif
        return false;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #3: Validate price using FloatingPointHelper
    // ═══════════════════════════════════════════════════════════════
    if(!IsValidPrice(price)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreateTHLineObject: Invalid price (", price, ") for '", name, "'");
        #endif
        return false;
    }
    
    // OPTIMIZATION: Check if object exists first, only update properties instead of recreate
    double normalizedPrice = NormalizePrice(price);
    datetime currentTime = TimeCurrent();
    datetime futureTime = currentTime + PeriodSeconds(Period()) * 10000;
    int objectType = (lineObjectType == LINE_OBJECT_RAY_LINE) ? OBJ_TREND : OBJ_HLINE;
    
    // Check if object already exists
    bool objectExists = (ObjectFind(0, name) >= 0);
    
    if(!objectExists) {
        // Create new object
        if(!ObjectCreate(0, name, objectType, 0, currentTime, normalizedPrice, (objectType == OBJ_TREND ? futureTime : 0), normalizedPrice)) {
            #ifdef ENABLE_DEBUG_LOGS
            int error = GetLastError();
            Print("❌ CreateTHLineObject: Failed to create '", name, "', error=", error);
            #endif
            return false;
        }
    } else {
        // Object exists - just update price
        // OPTIMIZATION: Only update if price actually changed (reduces terminal calls)
        double currentObjPrice = ObjectGetDouble(0, name, OBJPROP_PRICE);
        if(MathAbs(currentObjPrice - normalizedPrice) > Point * 0.1) {
            if(!ObjectSetDouble(0, name, OBJPROP_PRICE, normalizedPrice)) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("⚠️ CreateTHLineObject: Failed to update price for '", name, "'");
                #endif
            }
        }
    }
    
    // Set properties (always, whether new or existing)
    ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, isSelectable);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    
    // CRITICAL FIX: Respect BOTH Hide state (F key) AND Lines visibility (L key)
    // PERFORMANCE: Use cached ChartID string
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    bool isHidden = GlobalVariableCheck(gvar_name) && (bool)GlobalVariableGet(gvar_name);
    
    if(isHidden || !g_linesVisible) {
        ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    } else {
        ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    
    return true;
}

bool CreatePipDistanceLabel(const string name, const double price, const double pips, const color textColor, const string levelInfo = "") {
    if(!inpShowPipDistanceLabels) return true;
    
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #1: Check object count BEFORE creation
    // ═══════════════════════════════════════════════════════════════
    if(!CanCreateObject()) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreatePipDistanceLabel: Object limit reached, cannot create '", name, "'");
        #endif
        return false;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX #2: Validate inputs
    // ═══════════════════════════════════════════════════════════════
    if(StringLen(name) == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreatePipDistanceLabel: Empty label name");
        #endif
        return false;
    }
    
    if(!IsValidPrice(price)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("❌ CreatePipDistanceLabel: Invalid price (", price, ")");
        #endif
        return false;
    }
    
    if(!ObjectCreate(0, name, OBJ_TEXT, 0, 0, price)) {
        ObjectDelete(0, name);
        if(!ObjectCreate(0, name, OBJ_TEXT, 0, 0, price)) {
            #ifdef ENABLE_DEBUG_LOGS
            int error = GetLastError();
            Print("❌ CreatePipDistanceLabel: Failed to create '", name, "', error=", error);
            #endif
            return false;
        }
    }
    
    // Format: "M1 +3 | 45.2 pips" or just "45.2 pips" if no levelInfo
    string labelText;
    if(StringLen(levelInfo) > 0) {
        labelText = StringFormat("%s | %.1f", levelInfo, pips);
    } else {
        labelText = StringFormat("%.1f pips", pips);
    }
    
    ObjectSetString(0, name, OBJPROP_TEXT, labelText);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    ObjectSetString(0, name, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, inpFontSize);
    // Visual align MT5: Use ANCHOR_LEFT (not ANCHOR_LEFT_UPPER) and don't set explicit
    // X/YDISTANCE — these match MT5's default behavior and keep label positioning consistent.
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    
    // CRITICAL FIX: Respect Hide state (F key)
    // PERFORMANCE: Use cached ChartID string
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    bool isHidden = GlobalVariableCheck(gvar_name) && (bool)GlobalVariableGet(gvar_name);
    
    if(isHidden) {
        ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    } else {
        ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    
    return true;
}
