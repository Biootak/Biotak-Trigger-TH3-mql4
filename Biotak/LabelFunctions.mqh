  #ifndef LABEL_FUNCTIONS_MQH
#define LABEL_FUNCTIONS_MQH

#property strict

bool DrawMainLevels(const string prefix) {
    // Skip drawing High/Low lines when Custom Price mode is active
    // In Custom Price mode, user defines their own reference point
    if(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) {
        // Delete existing High/Low lines if they exist
        ObjectDelete(0, prefix + "High");
        ObjectDelete(0, prefix + "High_PipsLabel");
        ObjectDelete(0, prefix + "Low");
        ObjectDelete(0, prefix + "Low_PipsLabel");
        return true;
    }
    
    // OPTIMIZATION: Cache tooltip strings and only recalculate if prices changed
    static double s_lastHighPrice = 0;
    static double s_lastLowPrice = 0;
    static string s_cachedHighTooltip = "";
    static string s_cachedLowTooltip = "";
    
    // High line
    string highTooltip;
    if(s_lastHighPrice != g_highestHigh) {
        highTooltip = inpHighLineTooltip + ": " + DoubleToString(g_highestHigh, Digits);
        double pipsToHigh = CalculatePipsDistance(g_highestHigh, g_currentPrice);
        highTooltip = highTooltip + ", Distance: +/- " + DoubleToString(pipsToHigh, 1) + " pips";
        s_cachedHighTooltip = highTooltip;
        s_lastHighPrice = g_highestHigh;
    } else {
        highTooltip = s_cachedHighTooltip;
    }
    if(!CreateTHLineObject(prefix+"High",g_highestHigh,inpHighColor,inpHighStyle,inpHighWidth,highTooltip, inpTHLineObjectType, false)) return false;
    if(inpShowPipDistanceLabels) {
        double pipsToHigh = CalculatePipsDistance(g_highestHigh, g_currentPrice);
        CreatePipDistanceLabel(prefix+"High_PipsLabel", g_highestHigh, pipsToHigh, inpHighColor);
    }
    
    // Low line
    string lowTooltip;
    if(s_lastLowPrice != g_lowestLow) {
        lowTooltip = inpLowLineTooltip + ": " + DoubleToString(g_lowestLow, Digits);
        double pipsToLow = CalculatePipsDistance(g_lowestLow, g_currentPrice);
        lowTooltip = lowTooltip + ", Distance: +/- " + DoubleToString(pipsToLow, 1) + " pips";
        s_cachedLowTooltip = lowTooltip;
        s_lastLowPrice = g_lowestLow;
    } else {
        lowTooltip = s_cachedLowTooltip;
    }
    if(!CreateTHLineObject(prefix+"Low",g_lowestLow,inpLowColor,inpLowStyle,inpLowWidth,lowTooltip, inpTHLineObjectType, false)) return false;
    if(inpShowPipDistanceLabels) {
        double pipsToLow = CalculatePipsDistance(g_lowestLow, g_currentPrice);
        CreatePipDistanceLabel(prefix+"Low_PipsLabel", g_lowestLow, pipsToLow, inpLowColor);
    }
    return true;
}

void SetLabelFont(const string name) {
    ObjectSetString(0, name, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, inpFontSize);
}

//+------------------------------------------------------------------+
//| ATR label helpers (ported from MT5)                               |
//+------------------------------------------------------------------+
void InitATRChartLabel(const string name, ENUM_BASE_CORNER corner, ENUM_ANCHOR_POINT anchor) {
    ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
}

string GetBaseTimeframeName(const string fullName) {
    int plusPos = StringFind(fullName, "+");
    if(plusPos > 0) {
        return StringSubstr(fullName, 0, plusPos);
    }
    return fullName;
}

bool CreateATRLabelSimple(const string objectPrefix, const string timeframeName, const double atrValuePoints, const int xPos, const int yPos, const color textColor, const int horizontalSpacing, const int verticalSpacing) {
    double point = GetCachedPoint();
    double pipSize = GetCachedPipSize();
    if(IsZero(point, EPSILON_PRICE) || IsZero(pipSize, EPSILON_PRICE)) return false;
    double atrPips = NormalizeDouble((atrValuePoints * point) / pipSize, 1);
    double shortStepPips = NormalizeDouble(atrPips * 1.5, 1);
    double longStepPips = NormalizeDouble(atrPips * 2.0, 1);
    double midStepPips = NormalizeDouble((shortStepPips + longStepPips) / 2.0, 1);
    double target3x = MathFloor(atrPips * 3.0);
    double target5x = MathFloor(atrPips * 5.0);
    double target15x = MathFloor(atrPips * 15.0);
    string mainObjName = StringFormat("%sATR_%s", objectPrefix, timeframeName);
    string stepsObjName = StringFormat("%sATR_Steps_%s", objectPrefix, timeframeName);
    string targetsObjName = StringFormat("%sATR_Targets_%s", objectPrefix, timeframeName);
    if(!inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
        ObjectDelete(0, targetsObjName);
    }
    string targetsText = StringFormat("%.0f - %.0f - %.0f", target3x, target5x, target15x);
    string mainText = StringFormat("%s: %.1f", timeframeName, atrPips);
    string stepsText = StringFormat("(%.1f - %.1f - %.1f)", shortStepPips, midStepPips, longStepPips);

    // PERF: Only update text/color if changed (using Cache)
    string cachedText;
    color cachedColor;
    bool exists = CacheGetLabel(mainObjName, cachedText, cachedColor);
    
    bool mainCreated = false;
    bool stepsCreated = false;
    bool targetsCreated = false;

    // Creation path - ensure objects exist
    if (ObjectFind(0, mainObjName) < 0) {
        if (!ObjectCreate(0, mainObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, mainObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        mainCreated = true;
    }
    if (ObjectFind(0, stepsObjName) < 0) {
        if (!ObjectCreate(0, stepsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, stepsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        stepsCreated = true;
    }
    if (inpShowATRTargets && ObjectFind(0, targetsObjName) < 0) {
        if (!ObjectCreate(0, targetsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, targetsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        targetsCreated = true;
    }

    // CRITICAL FIX: If any object was just created, force updates even if cache says they match
    bool textChanged = mainCreated || stepsCreated || targetsCreated || !exists || (cachedText != mainText);
    bool colorChanged = mainCreated || stepsCreated || targetsCreated || !exists || (cachedColor != textColor);

    if(textChanged) {
        ObjectSetString(0, mainObjName, OBJPROP_TEXT, mainText);
        ObjectSetString(0, stepsObjName, OBJPROP_TEXT, stepsText);
        if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
            ObjectSetString(0, targetsObjName, OBJPROP_TEXT, targetsText);
        }
        CacheUpdateLabel(mainObjName, mainText, textColor);
    }
    
    if(colorChanged) {
        ObjectSetInteger(0, mainObjName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(0, stepsObjName, OBJPROP_COLOR, textColor);
        if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
            ObjectSetInteger(0, targetsObjName, OBJPROP_COLOR, textColor);
        }
        CacheUpdateLabel(mainObjName, mainText, textColor);
    }

    if(mainCreated) SetLabelFont(mainObjName);
    if(stepsCreated) SetLabelFont(stepsObjName);
    if(targetsCreated) SetLabelFont(targetsObjName);
    
    ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER;
    ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
    
    if(mainCreated) InitATRChartLabel(mainObjName, corner, anchor);
    if(stepsCreated) InitATRChartLabel(stepsObjName, corner, anchor);
    if(targetsCreated) InitATRChartLabel(targetsObjName, corner, anchor);

    int baseY = MathAbs(yPos);
    int lineGap = inpLabelRowGap;
    int singleLineHeight = inpFontSize + lineGap;
    
    if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
        ObjectSetInteger(0, targetsObjName, OBJPROP_YDISTANCE, baseY);
        ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight);
        ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight * 2);
    } else {
        ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY);
        ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight);
    }

    int labelXDistance = MathAbs(xPos);
    int mainTextWidth = (int)(StringLen(mainText) * inpFontSize * 0.6);
    int stepsTextWidth = (int)(StringLen(stepsText) * inpFontSize * 0.6);
    int mainOffset = (stepsTextWidth - mainTextWidth) / 2;
    if(mainOffset < 0) mainOffset = 0;
    
    ObjectSetInteger(0, mainObjName, OBJPROP_XDISTANCE, labelXDistance + mainOffset);
    ObjectSetInteger(0, stepsObjName, OBJPROP_XDISTANCE, labelXDistance);
    
    if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
        int targetsTextWidth = (int)(StringLen(targetsText) * inpFontSize * 0.6);
        int targetsOffset = (mainTextWidth - targetsTextWidth) / 2 + mainOffset;
        if(targetsOffset < 0) targetsOffset = 0;
        ObjectSetInteger(0, targetsObjName, OBJPROP_XDISTANCE, labelXDistance + targetsOffset);
    }
    
    if(IsIndicatorHidden()) {
        if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    } else {
        if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    return true;
}

//+------------------------------------------------------------------+
//| Clear all labels to prevent ghosting or overlaps                |
//+------------------------------------------------------------------+
void ClearAllLabels(const string objectPrefix) {
    // P-UI-21: suppress window — every bulk below deletes inpObjectPrefix*
    // names, and unsuppressed each fires CHARTEVENT_OBJECT_DELETE ->
    // CacheRemoveObject + g_redrawTHLevelsNeeded (a label clear must never
    // flag a full level redraw).
    g_suppressDeleteEvents = true;
    // 1. Delete all labels with the standard LBL_ prefix via native bulk delete
    string labelPrefix = objectPrefix + "LBL_";
    ObjectsDeleteAll(0, labelPrefix);

    // PERF FIX: Replace two O(n) manual loops with two native ObjectsDeleteAll prefix calls.
    // ObjectsDeleteAll is a single kernel call — dramatically faster than ObjectsTotal + loop.
    //
    // Old logic wanted to delete any object that:
    //  (a) starts with inpObjectPrefix + "_" AND contains "_LBL_"
    //  (b) starts with objectPrefix + "TF"
    //
    // The LBL_ sub-prefix already covers (a): every LBL_ object name that was
    // created by any TF variant of this indicator starts with inpObjectPrefix.
    // So deleting all inpObjectPrefix + "_*_LBL_*" reduces to deleting every
    // variant prefix + "LBL_" combination.
    //
    // Walk through all known TF suffixes and bulk-delete their LBL_ namespace.
    // This is O(k) API calls (k = number of known TF strings, ~9) instead of
    // O(total chart objects) per frame.
    // M30 here is a CHART-TIMEFRAME namespace (a chart can sit on M30), NOT the
    // retired M30 ATR column — never drop it, or the `_M30_LBL_` ghosts of an
    // old chart survive every clear.
    static string s_tfSuffixes[] = {"M1","M5","M15","M30","H1","H4","D1","W1","MN"};
    string basePrefix = inpObjectPrefix + "_";
    for(int j = 0; j < ArraySize(s_tfSuffixes); j++) {
        string tfLblPrefix = basePrefix + s_tfSuffixes[j];
        ObjectsDeleteAll(0, tfLblPrefix + "_LBL_");
    }
    
    // (b) Delete objectPrefix + "TF*" labels (legacy)
    ObjectsDeleteAll(0, objectPrefix + "TF");
    g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
    g_suppressDeleteEvents = false;
}

// R-TRADEPLAN: trade-plan math lives ONLY in TradePlanFormulas.mqh.
// This file renders its values - never recompute coefficients here.

bool CreateATRTradePiece(const string name, const string text, const color textColor,
                         const int xPos, const int yPos) {
    if(ObjectFind(0, name) < 0) {
        if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;
    }
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    SetLabelFont(name);
    InitATRChartLabel(name, CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(8, xPos));
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(8, yPos));
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES,
                     IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    return true;
}

// Countdown to the current chart bar close. Default = the long corner form
// ("Close in : 22d 12h 32m 13s"); compact = the live-candle tag form with no
// prefix and no spaces ("22d12h32m13s"). Units below the leading non-zero one
// are skipped either way (H1 shows "17m 51s" / "17m51s").
string TradePlanCloseInText(const bool compact = false)
{
   datetime bt = iTime(Symbol(), Period(), 0);
   if(bt <= 0) return compact ? "--" : "Close in : --";
   long left = (long)(bt + PeriodSeconds() - TimeCurrent());
   if(left < 0) left = 0;
   long d = left / 86400; left -= d * 86400;
   long h = left / 3600;  left -= h * 3600;
   long m = left / 60;
   long s = left - m * 60;
   string sep = compact ? "" : " ";
   string t = "";
   if(d > 0) t = t + IntegerToString(d) + "d" + sep;
   if(d > 0 || h > 0) t = t + IntegerToString(h) + "h" + sep;
   if(d > 0 || h > 0 || m > 0) t = t + IntegerToString(m) + "m" + sep;
   t = t + IntegerToString(s) + "s";
   return compact ? t : ("Close in : " + t);
}

//+------------------------------------------------------------------+
//| Live countdown tag — its OWN layer (2026-09-11, user request):     |
//| own switch (inpShowLiveCountdown), own color/size/gap, and a name  |
//| deliberately free of "ATR_" so the periodic object janitor (which  |
//| hides every "ATR_" object while the ATR block is off) never eats   |
//| it. Turn the ATR labels off and the countdown stays.               |
//+------------------------------------------------------------------+
string LiveCountdownObjName()
{
   return inpObjectPrefix + "_" + GetCurrentTimeframe() + "_" + "LBL_" + LIVE_COUNTDOWN_NAME;
}

bool LiveCountdownEnabled()
{
   return (inpShowLiveCountdown && !IsIndicatorHidden());
}

// Paints the tag when its own switch is on, removes it (plus the retired
// "...ATR_Trade_Current_CloseIn" of older builds) when it is off.
void RefreshLiveCountdown()
{
   string nm = LiveCountdownObjName();
   if(!LiveCountdownEnabled())
   {
      ObjectDelete(0, nm);
      ObjectDelete(0, inpObjectPrefix + "_" + GetCurrentTimeframe() + "_" + "LBL_" + LIVE_COUNTDOWN_LEGACY_NAME);
      g_cdTagValid = false;
      return;
   }
   CreateLivePriceCountdown(nm);
}

// Chart click router: is this point on the tag's last painted rect?
bool LiveCountdownPointInside(const int mx, const int my)
{
   if(!g_cdTagValid || !LiveCountdownEnabled()) return false;
   int h = (g_cdTagH > 0) ? g_cdTagH : (inpFontSize + 4);
   return (mx >= g_cdTagX - 2 && mx <= g_cdTagX + g_cdTagW + 2 &&
           my >= g_cdTagY - 2 && my <= g_cdTagY + h + 2);
}

//+------------------------------------------------------------------+
//| Bar-close countdown tag beside the LIVE CANDLE, at the LIVE PRICE.|
//| Both axes are derived in pixels every refresh: Y from               |
//| ChartTimePriceToXY(quote) (quote = bid/ask mid) so the text sits on |
//| the level the terminal's price lines are drawn at, X from the live |
//| bar's right edge + a few px, so the tag hugs the candle and moves   |
//| with it as the price runs. When the right side runs out of room it  |
//| flips to the candle's left instead of sliding under the price       |
//| scale. Cost per call = 2-3 ChartTimePriceToXY + a handful of         |
//| property sets, cheap enough for the 1 Hz path in TradePlanLiveTick  |
//| (P-PERF-01) and for the scroll/zoom hook.                           |
//+------------------------------------------------------------------+
bool CreateLivePriceCountdown(const string name)
{
   // Own switch only — never the ATR block's flags (that is the whole point).
   if(!LiveCountdownEnabled())
   {
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      g_cdTagValid = false;
      return false;
   }

   double point = GetCachedPoint();
   if(IsZero(point, EPSILON_PRICE)) return false;
   datetime bt = iTime(Symbol(), Period(), 0);
   if(bt <= 0) return false;

   // The quote the tag rides: the bid/ask mid, so it sits exactly on the level
   // the terminal's own price lines are drawn at. Bar close covers the very
   // first ticks of a chart, before a quote exists.
   double bid = MarketInfo(GetCachedSymbol(), MODE_BID);
   double ask = MarketInfo(GetCachedSymbol(), MODE_ASK);
   double price = 0.0;
   if(bid > 0.0 && ask > 0.0) price = (bid + ask) / 2.0;
   else if(bid > 0.0)         price = bid;
   else                       price = iClose(Symbol(), Period(), 0);
   if(price <= 0.0) return false;

   // Bar-0 pixel X (its LEFT edge) + the quote's pixel Y. A chart scrolled
   // away from the live bar has no candle to sit next to, so park the tag
   // rather than draw it at a made-up level — the next refresh brings it back.
   int barX = 0, priceY = 0;
   if(!ChartTimePriceToXY(0, 0, bt, price, barX, priceY)) barX = -1;
   if(barX < 0 || priceY < 0)
   {
      if(ObjectFind(0, name) >= 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      g_cdTagValid = false;   // no stale rect for the click hit-test
      return false;
   }

   // Bar width in pixels comes from the previous bar's X, so the gap scales
   // with the zoom instead of being a fixed guess.
   int prevX = 0, prevY = 0;
   int barPx = 8;   // safe default for a chart that cannot resolve bar 1
   if(ChartTimePriceToXY(0, 0, bt - PeriodSeconds(), price, prevX, prevY) && barX > prevX)
      barPx = barX - prevX;

   string text = TradePlanCloseInText(true);
   // Own size (0 = follow the shared label size) — resolved BEFORE measuring:
   // the width estimate is cached for inpFontSize, so scale it to the
   // RENDERED size (P-UI-26/F17), or the edge-flip and click rect drift.
   int fsz = (inpCountdownFontSize > 0) ? inpCountdownFontSize : inpFontSize;
   if(fsz <= 0) fsz = 8;
   int tagW = (int)(CalculateTextWidth(text) * fsz / MathMax(1, inpFontSize));
   // Hand-clamped on purpose: ClampInt() lives in BiotakKit.mqh, which this
   // file (included earlier) cannot see in the Lite build (P-ARCH-02).
   int gap = inpCountdownGapPx;                     // "یک کم فاصله"
   if(gap < 0) gap = 0;
   if(gap > 40) gap = 40;
   int x    = barX + barPx + gap;                   // just off the candle's right
   int cw   = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   // The right margin the corner labels already live in is the boundary the tag
   // may not cross (beyond it sits the price scale).
   int rightLimit = (cw > 0) ? (cw - MathMax(8, inpLabelsMarginLeft)) : 0;
   if(cw > 0 && x + tagW > rightLimit)
   {
      x = barX - tagW - gap;                      // no room right → hug its left
      if(x < 4) x = 4;
   }

   // Earlier builds drew this same name in the corner and on the candle as an
   // OBJ_TEXT; a same-name ObjectCreate of another type does not replace the
   // old object, so retire it first.
   if(ObjectFind(0, name) >= 0 && ObjectType(name) != OBJ_LABEL)
      ObjectDelete(0, name);
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;
      ObjectSetString(0, name, OBJPROP_TEXT, "");   // no default "Label" text
   }

   // Own color. Center the row on the quote level (Y is measured from the
   // top edge here); clamp the bottom too so the tag never sinks under the
   // date scale when price hugs the chart's lower edge (P-UI-26/L4).
   int chTag = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(chTag <= 0) chTag = 1080;
   int xLeft = MathMax(4, x);
   int yTop = MathMax(2, MathMin(priceY - fsz / 2, chTag - (fsz + 2) - 20));

   SetLabelFont(name);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fsz);   // own size over the shared one
   InitATRChartLabel(name, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, inpCountdownColor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xLeft);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yTop);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

   // Remember the painted rect: the chart click router hit-tests it to open the
   // settings card. The object itself stays UNSELECTABLE so it can never be
   // grabbed/dragged by accident.
   g_cdTagX = xLeft; g_cdTagY = yTop; g_cdTagW = tagW; g_cdTagH = fsz + 2;
   g_cdTagValid = true;
   return true;
}

bool CreateATRTradeLabel(const string objectPrefix, const STradePlan &plan,
                         const int xPos, const int yPos)
{
   // Bottom-right block (R-TRADEPLAN): one right-aligned row —
   //   #SL:-<sl> #TP1+<t1> #TP2+<t2> #TP3+<t3>     (blue)
   // The old top row of this block (`Close in : <countdown>`, red) now rides
   // the LIVE PRICE in the same right column instead (CreateLivePriceCountdown,
   // 2026-09-11 user request). Same object name, so visibility + cleanup
   // wiring is unchanged.
   string tpName = objectPrefix + "ATR_Trade_Current_TPRow";

   string tpText = StringFormat("#SL:-%d #TP1+%d #TP2+%d #TP3+%d",
                                plan.sl, plan.tp1, plan.tp2, plan.tp3);

    // PERF: the two "Current" pieces below are upserted in place by
    // CreateATRTradePiece (create-if-missing + set), so wiping the Current_
    // namespace here only deletes what we recreate two lines later
    // (flicker + a kernel call every 2 s from the live pump). Retired
    // layouts are purged once per prefix instead — same end state.
    static string s_purgedPfx = "";
    if(s_purgedPfx != objectPrefix)
    {
       s_purgedPfx = objectPrefix;
       ObjectDelete(0, objectPrefix + "ATR_Trade_Current_ATR");
       ObjectDelete(0, objectPrefix + "ATR_Trade_Current_SLRow");
       ObjectDelete(0, objectPrefix + "ATR_Trade_" + PeriodToString(plan.chartMin));
       ObjectDelete(0, objectPrefix + "ATR_Trade_" + PeriodToString(plan.chartMin) + "_Targets");
       ObjectDelete(0, objectPrefix + "ATR_Trade_" + PeriodToString(plan.chartMin) + "_Stops");
       ObjectDelete(0, objectPrefix + "ATR_Trade_Formula");
    }

   bool showTP = (inpShowATRTradeLabels && inpShowATRTradeTPLabels);
   int rightMargin  = MathMax(8, MathAbs(xPos));
   int bottomMargin = MathMax(8, MathAbs(yPos));

   if(showTP) {
       // Single row now, so it right-aligns straight on the block edge.
       if(!CreateATRTradePiece(tpName, tpText, clrBlue, rightMargin, bottomMargin)) return false;
   }
   // The countdown is its own layer (own switch/color/size/gap) — repaint it
   // from here too, but NEVER through this block's show flags.
   RefreshLiveCountdown();
   return true;
}

// Top-right Hunter row, below the TRex stamp (R-TRADEPLAN).
// R-STBOND (2026-09-10, user decision): the Str Bond row is RETIRED from the
// chart — SB1 ≈ TP1 (20/9 vs 7/3 of slRaw) and SB2 ≈ TP3 (95/9 vs 31/3), so it
// read as a duplicate. The engine sb1/sb2 values stay (log + golden test still
// pair them against the professor's screenshots); only the on-chart text is
// gone. Delete/visibility paths for TREX_StrBond stay as purge for old charts.
bool DisplayTradePlanTopRows(const string labelPrefix, const STradePlan &plan)
{
   int fontSize  = inpFontSize;
   int brandSize = inpFontSize + 6;
   int rightMargin = MathMax(8, inpLabelsMarginLeft);
   int yBrand  = MathMax(8, inpLabelsMarginTop);
   int yCap    = yBrand + brandSize + inpLabelRowGap;
   int yHunter = yCap + fontSize + inpLabelRowGap;
   string hText = StringFormat("Hunter SL: %d Eng.SL: %d", plan.hunter, plan.eng);
   if(!CreateTRexPiece(labelPrefix + "TREX_Hunter", hText, clrRed, fontSize, rightMargin, yHunter)) return false;
   return true;
}

//+------------------------------------------------------------------+
//| TRex title stamp (top-right): brand + live spread + caption      |
//| Screenshot order: TR|ex with spread superscript / caption (the    |
//| small number is the pair's live spread in pips - NOT a version   |
//| and not a TH value; v0.5's daily-TH value row is retired in 3.x). |
//| Caption = price-behavior tagline, built from codes below - never |
//| a literal, see P-LBL-01).                                         |
//+------------------------------------------------------------------+
string TRexCaptionText() {
    ushort cap[20];
    cap[0]=0x0631; cap[1]=0x0641; cap[2]=0x062A; cap[3]=0x0627; cap[4]=0x0631;
    cap[5]=0x0634; cap[6]=0x0646; cap[7]=0x0627; cap[8]=0x0633; cap[9]=0x06CC;
    cap[10]=0x0020;
    cap[11]=0x062D; cap[12]=0x0631; cap[13]=0x06A9; cap[14]=0x062A;
    cap[15]=0x0020;
    cap[16]=0x0642; cap[17]=0x06CC; cap[18]=0x0645; cap[19]=0x062A;
    string s = "";
    for(int k = 0; k < 20; k++) s = s + " ";
    for(int i = 0; i < 20; i++) StringSetCharacter(s, i, cap[i]);
    return s;
}

bool CreateTRexPiece(const string name, const string text, const color textColor,
                     const int fontSize, const int xPos, const int yPos,
                     const string fontName = "") {
    if(ObjectFind(0, name) < 0) {
        if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;
    }
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    // Empty fontName = default indicator font. The caption passes "Tahoma"
    // explicitly: "Arial Bold" (inpFontName) is not a real family and MT4
    // falls back to a font without Arabic glyphs ("????").
    ObjectSetString(0, name, OBJPROP_FONT,
                    StringLen(fontName) > 0 ? fontName : inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    InitATRChartLabel(name, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(8, xPos));
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(0, yPos));
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES,
                     IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    return true;
}

bool DisplayTRexTitleBlock(const string labelPrefix) {
    string spName  = labelPrefix + "TREX_Spread";
    string capName = labelPrefix + "TREX_Caption";
    string trName  = labelPrefix + "TREX_TR";
    string exName  = labelPrefix + "TREX_EX";

    if(IsIndicatorHidden()) {
        ObjectSetInteger(0, spName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, capName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, trName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, exName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        return true;
    }

    // Superscript = live spread of the pair in pips, 1 decimal ("3.2" style).
    string spText = "--";
    double pip = GetCachedPipSize();
    if(!IsZero(pip, EPSILON_PRICE)) {
        double ask = MarketInfo(Symbol(), MODE_ASK);
        double bid = MarketInfo(Symbol(), MODE_BID);
        if(ask > 0 && bid > 0 && ask >= bid)
            spText = DoubleToString((ask - bid) / pip, 1);
    }
    string capText = TRexCaptionText();

    // Top-RIGHT stamp: every row flush-right to the same margin (xPos here is
    // the right-edge distance, like the bottom-right trade block).
    int fontSize  = inpFontSize;
    int brandSize = inpFontSize + 6;
    int rightMargin = MathMax(8, inpLabelsMarginLeft);
    int yBrand = MathMax(8, inpLabelsMarginTop);
    int yCap   = yBrand + brandSize + inpLabelRowGap;

    int xEx = rightMargin;
    int xTR = rightMargin + (int)(2.0 * brandSize * 0.7);
    // Spread superscript rides over the "ex" top-right (screenshot look).
    int xSp = rightMargin + 6;
    int ySp = yBrand - 6;
    if(ySp < 0) ySp = 0;

    if(!CreateTRexPiece(spName, spText, clrBlack, fontSize, xSp, ySp)) return false;
    if(!CreateTRexPiece(capName, capText, clrGreen, fontSize, rightMargin, yCap, "Tahoma")) return false;
    // P-LBL-02 follow-up: Tahoma ships with every Windows and covers Arabic -
    // the caption renders with no Persian font to download. One-shot Experts
    // log below proves string-vs-font root cause if ???? ever returns.
    static bool s_trexCapLogged = false;
    if(!s_trexCapLogged) {
        s_trexCapLogged = true;
        string backFont = "";
        ObjectGetString(0, capName, OBJPROP_FONT, 0, backFont);
        Print("TREX caption len=", StringLen(capText),
              " c0=", IntegerToString(StringGetCharacter(capText, 0)),
              " font=", backFont);
    }
    if(!CreateTRexPiece(trName, "TR", clrBlue, brandSize, xTR, yBrand)) return false;
    if(!CreateTRexPiece(exName, "ex", clrRed, brandSize, xEx, yBrand)) return false;
    return true;
}

void DisplayATRLabels(const string objectPrefix) {
    if(!g_atrLabelsVisible) {
        ClearAllLabels(objectPrefix);
        return;
    }
    // Trade-plan labels are independent from the optional ATR overview. When
    // the overview is off, still allow the compact active-TF plan to render.
    
    double point = GetCachedPoint();
    double pipSize = GetCachedPipSize();
    int digits = GetCachedDigits();
    if(IsZero(point, EPSILON_PRICE) || IsZero(pipSize, EPSILON_PRICE) || digits == 0) return;

    string labelPrefix = objectPrefix + "LBL_";
    // M30 retired from the overview (user decision 2026-09-11): the ladder we
    // trade and log is the 8 standard TFs (TradePlanLogAllTFs, ATR warm-up in
    // ATRCalculations.mqh, Biotak ATR Audit.mq4 all use the same 8). M30 was a
    // separate rendering of the same composite and only cluttered the row.
    // Stale M30 pieces are purged by ClearAllLabels() before every redraw.
    string timeframes[] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1", "MN1"};
    int tfMinutes[] = {1, 5, 15, 60, 240, 1440, 10080, 43200};

    // Use TH colors for ATR
    color colors[] = {
        clrBlack,        // M1
        clrBlack,        // M5
        clrBlack,        // M15
        clrBlue,         // H1
        clrRed,          // H4
        clrGreen,        // D1
        clrBlack,        // W1
        clrBlack         // MN1
    };
    
    bool isVerticalLayout = (inpLabelArrangement == LABEL_ARRANGEMENT_VERTICAL);
    int rowSpacing = inpLabelRowGap;
    int horizontalPadding = inpLabelColumnGap;
    int startXPos = inpLabelsMarginLeft;
    int lineGap = rowSpacing;
    int singleLineHeight = inpFontSize + lineGap;
    int titleYPos = inpLabelsMarginTop + g_currentLabelYOffset;
    int startYPos = isVerticalLayout ? (titleYPos + singleLineHeight) : titleYPos;
    int sectionGap = inpSectionGap;
    
    string titleObjName = labelPrefix + "ATR_Title";
    if(ObjectFind(0, titleObjName) < 0) {
        ObjectCreate(0, titleObjName, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, titleObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    ObjectSetString(0, titleObjName, OBJPROP_TEXT, "ATR:");
    ObjectSetInteger(0, titleObjName, OBJPROP_COLOR, clrDarkBlue);
    ObjectSetString(0, titleObjName, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, titleObjName, OBJPROP_FONTSIZE, inpFontSize);
    ObjectSetInteger(0, titleObjName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, titleObjName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, titleObjName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, titleObjName, OBJPROP_HIDDEN, false);
    ObjectSetInteger(0, titleObjName, OBJPROP_XDISTANCE, inpLabelsMarginLeft);
    ObjectSetInteger(0, titleObjName, OBJPROP_YDISTANCE, titleYPos);
    ObjectSetInteger(0, titleObjName, OBJPROP_TIMEFRAMES, IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    
    int titleWidth = (int)CalculateTextWidth("ATR:");
    int labelStartX = GetLabelStartX(startXPos, titleWidth, horizontalPadding, isVerticalLayout);
    int currentXPos = labelStartX;
    int currentYPos = startYPos;
    int xStep = horizontalPadding;
    int maxWidth = GetCachedChartWidth() - startXPos * 2;
    int lineHeight = GetLabelLineHeight(inpShowATRTargets, rowSpacing);
    
    int renderedCount = 0;
    for(int i = 0; i < ArraySize(timeframes); i++) {
        double atrValue = GetATRForTimeframe(tfMinutes[i]);
        if(atrValue <= 0 || atrValue == EMPTY_VALUE) continue;
        
        double atrPoints = atrValue / point;
        double atrPips = NormalizeDouble(atrValue / pipSize, 1);
        color labelColor = colors[i];
    
        string mainText = inpShowTimeframeInLabels ?
            StringFormat("%s: %.1f", timeframes[i], atrPips) :
            DoubleToString(atrPips, 1);
        string stepsText = StringFormat("(%.1f - %.1f - %.1f)", atrPips * 1.5, atrPips * 1.75, atrPips * 2.0);
        string targetsText = StringFormat("%.0f - %.0f - %.0f", MathFloor(atrPips * 3.0), MathFloor(atrPips * 5.0), MathFloor(atrPips * 15.0));
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowATRTargets);
    
        if(isVerticalLayout) {
            if(!CreateATRLabelSimple(labelPrefix, timeframes[i], atrPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentYPos += lineHeight;
        } else {
            if(currentXPos + labelWidth + xStep > maxWidth) {
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateATRLabelSimple(labelPrefix, timeframes[i], atrPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentXPos += labelWidth + xStep;
        }
        renderedCount++;
    }
    
    if(renderedCount > 0) {
        g_currentLabelYOffset += (currentYPos - startYPos) + lineHeight + sectionGap;
    }

}

void DisplayATRTradeLabels(const string objectPrefix) {
    string labelPrefix = objectPrefix + "LBL_";
    if(!inpShowATRTradeLabels || !g_atrLabelsVisible) {
        // Defensive wipe: the relayout callers clear LBL_ first, but a bare
        // toggle path may reach here without a prior clear.
        ObjectDelete(0, labelPrefix + "ATR_Trade_Current_ATR");
        ObjectDelete(0, labelPrefix + "ATR_Trade_Current_SLRow");
        ObjectDelete(0, labelPrefix + "ATR_Trade_Current_TPRow");
        ObjectDelete(0, labelPrefix + "ATR_Trade_Current_CloseIn");
        ObjectDelete(0, labelPrefix + "TREX_Spread");
        ObjectDelete(0, labelPrefix + "TREX_Caption");
        ObjectDelete(0, labelPrefix + "TREX_TR");
        ObjectDelete(0, labelPrefix + "TREX_EX");
        ObjectDelete(0, labelPrefix + "TREX_Hunter");
        ObjectDelete(0, labelPrefix + "TREX_StrBond");
        return;
    }

    // R-TRADEPLAN: one engine call feeds every right-side row.
    // Active chart TF only - the TF-lock (G key) pins levels/zones,
    // never the trade-plan block: each TF shows its own plan.
    // Live variant: slow legs (SL/TP/SB) freeze per chart bar like the
    // professor's block; Eng/Hunter stay live.
    STradePlan plan;
    if(!TradePlanComputeLive(Period(), plan)) return;

    // Both margins are distances from the right/bottom chart edges.
    CreateATRTradeLabel(labelPrefix, plan,
                       inpLabelsMarginLeft, inpLabelsMarginBottom);
    DisplayTRexTitleBlock(labelPrefix);
    if(inpShowATRTradeSLLabels)
        DisplayTradePlanTopRows(labelPrefix, plan);
    else {
        ObjectDelete(0, labelPrefix + "TREX_Hunter");
        ObjectDelete(0, labelPrefix + "TREX_StrBond");
    }
}

// Live trade-block pump (P-LBL-03 fix): the relayout path above repaints
// this block only on init/TF-switch/settings (needLabels gate), so without
// this the numbers sat frozen until the user switched TF. In-place text
// updates via the same create-or-update pieces (no clear), change-guarded
// paint, 2s throttle: no flicker, negligible CPU. Called per-tick+timer in
// Full (RefreshUIPerTick) and from the 500ms block in Lite.
// Full 8-TF snapshot for all ladder timeframes on the current symbol.
// Called from TradePlanDumpNow (X hotkey) and from the change-gated
// LiveTick branch (3 s throttle).
// Uses TradePlanCompute (not ComputeLive) so each TF gets its OWN fresh
// calculation (no bar-freeze cross-contamination between TFs).
// [ATRLEGS] diagnostic: raw Wilder legs behind the composite TR(own), for
// offline weight fitting without manual script runs (2026-09-10: future
// sessions fetch them from the log like [SNAP] — no user round-trip).
// Same 6 periods + shift=1 as CalculateATRBatchWilders (ATRCalculations.mqh),
// price units. Throttled 60 s (legs only move on bar rolls); rides the
// snapshot's numeric-change gate, so a frozen chart keeps its last — still
// valid — legs. Lite-safe: iBars/iATR only, no UI calls.
// EXTRA q-legs (2026-09-10): Wilder neighbors 26..60 for high-TF formula
// identification — W1/MN sit between standard periods, and only LIVE bars
// can place them (stale .hst is exact for MN windows, ±1 bar for W1).
// EXTRA s-legs: SAME periods via TrexSMALeg (professor's SMA family), so one
// fetch carries BOTH families live — no more stale-.hst forensics.

//+------------------------------------------------------------------+
//| Auto-export sink (2026-09-10, P-LOG-02)                           |
//| The terminal's own log-flusher can wedge for an hour+ (Experts tab|
//| live, MQL4\Logs file frozen) — so OUR numbers also go to a        |
//| per-symbol file this indicator owns: FileClose flushes to disk    |
//| immediately, no terminal writer involved. Overwrite mode: the file|
//| always holds the LATEST dump only. OUR lines only (pure ASCII) —  |
//| PROFATR text can carry non-ASCII captions (P-LBL-01), so the      |
//| professor's side stays Print-only. The caller change-gates, same  |
//| as the Print path — zero steady-state cost. Lite-safe (File* are  |
//| core MQL4, no UI symbols).                                        |
//+------------------------------------------------------------------+
int s_tpxHandle = INVALID_HANDLE;

string TradePlanExportFileName()
{
    return("tradeplan-auto-" + Symbol() + ".log");
}

// One line to BOTH sinks: Experts log (Print) + our auto file (when open).
void TpxLine(const string s)
{
    Print(s);
    if(s_tpxHandle != INVALID_HANDLE)
        FileWriteString(s_tpxHandle, s + "\n");
}

void TradePlanExportBegin()
{
    if(s_tpxHandle != INVALID_HANDLE)
    {
        FileClose(s_tpxHandle);
        s_tpxHandle = INVALID_HANDLE;
    }
    s_tpxHandle = FileOpen(TradePlanExportFileName(), FILE_WRITE | FILE_TXT | FILE_ANSI);
}

void TradePlanExportEnd()
{
    if(s_tpxHandle != INVALID_HANDLE)
    {
        FileClose(s_tpxHandle);
        s_tpxHandle = INVALID_HANDLE;
    }
}

void TradePlanLogLegs()
{
    int legMins[9]; string legNames[9];
    legMins[0]=1;     legNames[0]="M1";
    legMins[1]=5;     legNames[1]="M5";
    legMins[2]=15;    legNames[2]="M15";
    legMins[3]=30;    legNames[3]="M30";
    legMins[4]=60;    legNames[4]="H1";
    legMins[5]=240;   legNames[5]="H4";
    legMins[6]=1440;  legNames[6]="D1";
    legMins[7]=10080; legNames[7]="W1";
    legMins[8]=43200; legNames[8]="MN";
    int pers[6];
    pers[0]=5; pers[1]=10; pers[2]=21; pers[3]=66; pers[4]=132; pers[5]=264;
    int qpers[10];
    qpers[0]=26; qpers[1]=28; qpers[2]=30; qpers[3]=32; qpers[4]=34;
    qpers[5]=50; qpers[6]=52; qpers[7]=55; qpers[8]=58; qpers[9]=60;
    for(int i = 0; i < 9; i++)
    {
        ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)legMins[i];
        int nb = iBars(Symbol(), tf);
        string s = "[ATRLEGS] TF=" + legNames[i] + " bars=" + IntegerToString(nb);
        for(int k = 0; k < 6; k++)
        {
            double v = 0.0;
            if(nb > pers[k] + 1)
            {
                v = iATR(Symbol(), tf, pers[k], 1);
                if(v == EMPTY_VALUE || v <= 0.0) v = 0.0;
            }
            s = s + " p" + IntegerToString(pers[k]) + "=" + DoubleToString(v, Digits);
        }
        for(int q = 0; q < 10; q++)
        {
            double w = 0.0;
            if(nb > qpers[q] + 1)
            {
                w = iATR(Symbol(), tf, qpers[q], 1);
                if(w == EMPTY_VALUE || w <= 0.0) w = 0.0;
            }
            s = s + " q" + IntegerToString(qpers[q]) + "=" + DoubleToString(w, Digits);
        }
        for(int g = 0; g < 10; g++)
        {
            double u = 0.0;
            if(nb > qpers[g] + 1) u = TrexSMALeg(tf, qpers[g], 1);
            s = s + " s" + IntegerToString(qpers[g]) + "=" + DoubleToString(u, Digits);
        }
        TpxLine(s);
    }
}

// [PROFOBJ]/[PROFATR] — the professor's indicator values, read off ITS chart
// labels (no source available: .ex4 string literals are encrypted, a
// strings-scan finds nothing — don't retry it). MQL4 cannot see other
// charts' objects, so attach OUR indicator (Lite is enough, no menu
// clutter) to every chart his runs on; this reader dumps ITS labels next
// to ours with timestamps for offline pairing.
// Self-discovery, no hardcoded names: a full-chart scan collects foreign
// OBJ_LABEL/OBJ_TEXT (anything not ours, capped); the cached names are then
// re-read in place. Background auto-scanning is OFF (user decision
// 2026-09-10: logs only on demand) — pass force=true from TradePlanDumpNow
// (X hotkey) to scan+read immediately. Silent when he is absent.
// Lite-safe: Object*/String* + literal prefixes only — Full-only symbols
// (HTF/menu/panel) must NOT be referenced here.
#define PROFATR_DISCOVER_MS 3600000
#define PROFATR_READ_MS     60000
#define PROFATR_MAX_NAMES   40
#define PROFATR_MAX_SCAN    80

void TradePlanLogProfAtr(const bool force = false)
{
    static uint s_discMs = 0;
    static uint s_readMs = 0;
    static string s_names[PROFATR_MAX_NAMES];
    static int s_count = 0;
    uint nowMs = GetTickCount();
    // --- discovery: full-chart scan for foreign labels (hourly in
    // background, immediate when forced) ---
    if(force || s_discMs == 0 || nowMs - s_discMs >= PROFATR_DISCOVER_MS)
    {
        s_discMs = nowMs;
        s_count = 0;
        int total = ObjectsTotal(0, -1, -1);
        int kept = 0;
        for(int i = total - 1; i >= 0 && kept < PROFATR_MAX_SCAN; i--)
        {
            string nm = ObjectName(0, i);
            if(StringLen(nm) == 0) continue;
            // Ours? skip (literals only — see header comment).
            if(StringLen(inpObjectPrefix) > 0 && StringFind(nm, inpObjectPrefix) == 0) continue;
            if(StringFind(nm, "_BK_") >= 0) continue;
            if(StringFind(nm, "BiotakMenuV2_") == 0) continue;
            if(StringFind(nm, "Pnl") == 0) continue;
            if(StringFind(nm, "Pal_") == 0) continue;
            if(StringFind(nm, "BiotakHTF_") == 0) continue;
            int ty = (int)ObjectGetInteger(0, nm, OBJPROP_TYPE);
            if(ty != OBJ_LABEL && ty != OBJ_TEXT) continue;
            string tx = "";
            ObjectGetString(0, nm, OBJPROP_TEXT, 0, tx);
            if(StringLen(tx) > 120) tx = StringSubstr(tx, 0, 120);
            Print("[PROFOBJ] chart=" + GetCurrentTimeframe()
                  + " type=" + IntegerToString(ty)
                  + " name=" + nm + " text=" + tx);
            if(s_count < PROFATR_MAX_NAMES) { s_names[s_count] = nm; s_count++; }
            kept++;
        }
        s_readMs = 0;   // fresh names: read immediately below
    }
    // --- 60 s re-read of cached names (timestamped for offline pairing) ---
    if(s_count > 0 && (s_readMs == 0 || nowMs - s_readMs >= PROFATR_READ_MS))
    {
        s_readMs = nowMs;
        string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
        for(int j = 0; j < s_count; j++)
        {
            if(ObjectFind(0, s_names[j]) < 0) continue;  // rebuilt names heal at next hourly scan
            string tx2 = "";
            ObjectGetString(0, s_names[j], OBJPROP_TEXT, 0, tx2);
            Print("[PROFATR] " + ts + " chart=" + GetCurrentTimeframe()
                  + " name=" + s_names[j] + " text=" + tx2);
        }
    }
}

void TradePlanLogAllTFs()
{
    static int s_tfMins[8];
    static string s_tfNames[8];
    s_tfMins[0]=1;    s_tfNames[0]="M1";
    s_tfMins[1]=5;    s_tfNames[1]="M5";
    s_tfMins[2]=15;   s_tfNames[2]="M15";
    s_tfMins[3]=60;   s_tfNames[3]="H1";
    s_tfMins[4]=240;  s_tfNames[4]="H4";
    s_tfMins[5]=1440; s_tfNames[5]="D1";
    s_tfMins[6]=10080;s_tfNames[6]="W1";
    s_tfMins[7]=43200;s_tfNames[7]="MN";

    string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
    double pip = GetCachedPipSize();
    // engT = Eng the engine uses (TR_composite/TRADEPLAN_ENG_DIVISOR, R-ENGPARITY).
    TpxLine("[SNAP] ===== " + Symbol() + "  pipSize=" + DoubleToString(pip,5)
          + "  engDiv=" + DoubleToString(TRADEPLAN_ENG_DIVISOR, 6) + "  " + ts + " =====");
    TpxLine("[SNAP] TF  | TR(own) | engT   | Eng | Hunter | slTrue  | SL  | TP1 | TP2  | TP3  | SB1  | SB2  | base(strTrig)");

    for(int i = 0; i < 8; i++)
    {
        STradePlan p;
        bool ok = TradePlanCompute(s_tfMins[i], p);
        if(!ok)
        {
            TpxLine("[SNAP] " + s_tfNames[i] + " | NOT READY (basePips=0 or data missing)");
            continue;
        }
        // TR(own) = composite ATR of THIS TF (not used in SL, for reference)
        double trOwn = TradePlanStripPips(s_tfMins[i]);
        TpxLine("[SNAP] " + s_tfNames[i]
              + " | " + DoubleToString(trOwn, 2)
              + " | " + DoubleToString(p.engTrue, 2)
              + " | " + IntegerToString(p.eng)
              + " | " + IntegerToString(p.hunter)
              + " | " + DoubleToString(p.slTrue, 2)
              + " | " + IntegerToString(p.sl)
              + " | " + IntegerToString(p.tp1)
              + " | " + IntegerToString(p.tp2)
              + " | " + IntegerToString(p.tp3)
              + " | " + IntegerToString(p.sb1)
              + " | " + IntegerToString(p.sb2)
              + " | base=" + DoubleToString(p.basePips, 3)
              + " str=" + IntegerToString(p.strMin)
              + " trig=" + IntegerToString(p.trigMin));
    }
    TpxLine("[SNAP] ===== END =====");
    // Legs ride the snapshot path, throttled independently (60 s). No PROFATR
    // here — the professor's side is compared from screenshots (X still dumps
    // everything on demand when our Lite sits on his chart).
    static uint s_legsMs = 0;
    uint nowMsL = GetTickCount();
    if(nowMsL - s_legsMs >= 60000)
    {
        s_legsMs = nowMsL;
        TradePlanLogLegs();
    }
}

// [TRADEPLAN-LOG] per-chart row (single TF). Called from the on-demand dump
// (X hotkey) and from the change-gated LiveTick branch — every line goes
// through TpxLine (Experts log + auto-export file).
void TradePlanPrintRow(STradePlan &plan)
{
    string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
    TpxLine("[TRADEPLAN] " + Symbol() + " " + GetCurrentTimeframe() + " " + ts);
    TpxLine("[TRADEPLAN]   TR(own)=" + DoubleToString(plan.ownPips, 1)
          + "  Eng.SL=" + IntegerToString(plan.eng)
          + "  Hunter=" + IntegerToString(plan.hunter));
    TpxLine("[TRADEPLAN]   SL=" + IntegerToString(plan.sl)
          + "  TP1=" + IntegerToString(plan.tp1)
          + "  TP2=" + IntegerToString(plan.tp2)
          + "  TP3=" + IntegerToString(plan.tp3));
    TpxLine("[TRADEPLAN]   StrBond=" + IntegerToString(plan.sb1)
          + " - " + IntegerToString(plan.sb2));
    TpxLine("[TRADEPLAN]   slTrue=" + DoubleToString(plan.slTrue, 4)
          + "  engTrue=" + DoubleToString(plan.engTrue, 4)
          + "  basePips=" + DoubleToString(plan.basePips, 4));
    TpxLine("[TRADEPLAN]   chartMin=" + IntegerToString(plan.chartMin)
          + "  strMin=" + IntegerToString(plan.strMin)
          + "  trigMin=" + IntegerToString(plan.trigMin));
}

// On-demand full dump (X hotkey, TradePlanDumpNow's worker): per-chart row
// + 8-TF snapshot + raw legs + professor's labels — one timestamped set,
// then silence again. Lite-safe.
void TradePlanDumpNow()
{
    STradePlan plan;
    if(!TradePlanComputeLive(Period(), plan)) return;
    TradePlanExportBegin();
    TpxLine("[DUMP] ===== " + Symbol() + " " + GetCurrentTimeframe() + " =====");
    // Rounding-integrity guard (TradePlanSelfCheck) — the engine computes and
    // displays on the SAME doubles, so this only fires on a real formula/wiring
    // regression. Skipped under the alt formulas: their Hunter leg is TR/1.66666
    // by design and does not satisfy the 8/3×Eng identity.
    if(!inpUseAltTradeFormulas)
    {
        if(TradePlanSelfCheck(plan))
            TpxLine("[SELFCHECK] OK  - every displayed leg within 0.5 pip of its engine value");
        else
            TpxLine("[SELFCHECK] FAIL - a displayed leg is off its unrounded engine value; "
                    "check TradePlanCompute/SelfCheck on " + Symbol());
    }
    TradePlanPrintRow(plan);
    TradePlanLogAllTFs();
    TradePlanLogLegs();
    TradePlanLogProfAtr(true);
    TpxLine("[DUMP] ===== END =====");
    TradePlanExportEnd();
}

void TradePlanLiveTick()
{
    uint nowMs = GetTickCount();
    static uint s_lastCdMs = 0;

    // 1 Hz countdown tag — its OWN switch, so it runs BEFORE (and regardless
    // of) the ATR block gate below: turning the ATR labels off must not take
    // the countdown away. One pixel-Y read + a text-set is the cheapest
    // refresh there is, so this does not wake the 2 s trade-block pump
    // (P-PERF-01).
    if(nowMs - s_lastCdMs >= 1000)
    {
        s_lastCdMs = nowMs;
        RefreshLiveCountdown();
        ThrottledChartRedraw();
    }

    if(!inpShowATRTradeLabels || !g_atrLabelsVisible || IsIndicatorHidden()) return;
    static uint s_lastMs = 0;
    string labelPrefix = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_" + "LBL_";

    if(nowMs - s_lastMs < 2000) return;
    s_lastMs = nowMs;
    STradePlan plan;
    if(!TradePlanComputeLive(Period(), plan)) return;
    // Display only — this path NEVER prints (user decision 2026-09-10: logs
    // only on demand via the X hotkey). The numeric sig still picks the full
    // vs cheap in-place label path; pixels identical either way.
    string sig = StringFormat("%d|%d|%d|%d|%d|%d|%d|%d",
                              plan.sl, plan.tp1, plan.tp2, plan.tp3,
                              plan.hunter, plan.eng, plan.sb1, plan.sb2);
    static string s_sig = "";
    if(sig != s_sig)
    {
       s_sig = sig;

    // Auto-log OUR numbers (user decision 2026-09-10: our log flows on its
    // own, change-guarded + throttled — the professor's side arrives via
    // screenshots and is paired offline by timestamp).
    TradePlanExportBegin();
    TradePlanPrintRow(plan);

    // Full 8-TF snapshot — throttled to once per 3 s (independent of chart TF).
    static uint s_snapMs = 0;
    if(nowMs - s_snapMs >= 3000)
    {
        s_snapMs = nowMs;
        TradePlanLogAllTFs();
    }
    TradePlanExportEnd();

    CreateATRTradeLabel(labelPrefix, plan,
                        inpLabelsMarginLeft, inpLabelsMarginBottom);
    DisplayTRexTitleBlock(labelPrefix);
    if(inpShowATRTradeSLLabels)
        DisplayTradePlanTopRows(labelPrefix, plan);
    else {
        ObjectDelete(0, labelPrefix + "TREX_Hunter");
        ObjectDelete(0, labelPrefix + "TREX_StrBond");
    }
    } // numeric change: full block above
    else
    {
       // Steady state: numerics frozen — only the 1-second countdown and the
       // live-spread superscript move. Both pieces upsert in place (no
       // delete); TopRows text is identical, skipped.
       CreateATRTradeLabel(labelPrefix, plan,
                           inpLabelsMarginLeft, inpLabelsMarginBottom);
       DisplayTRexTitleBlock(labelPrefix);
    }
    ThrottledChartRedraw();
}

void SetATRLabelsVisibility(const string objectPrefix, const bool visible) {
    string uniquePrefix = objectPrefix + "LBL_";
    string allTimeframes[] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1", "MN1"};

    bool shouldShow = (visible && !IsIndicatorHidden());
    long tf = shouldShow ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;

    ObjectSetInteger(0, uniquePrefix + "ATR_Title", OBJPROP_TIMEFRAMES, tf);

    long targetsTF = (shouldShow && inpShowATRTargets) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    for(int i = 0; i < ArraySize(allTimeframes); i++) {
        string tfName = allTimeframes[i];
        ObjectSetInteger(0, uniquePrefix + "ATR_" + tfName, OBJPROP_TIMEFRAMES, tf);
        ObjectSetInteger(0, uniquePrefix + "ATR_Steps_" + tfName, OBJPROP_TIMEFRAMES, tf);
        ObjectSetInteger(0, uniquePrefix + "ATR_Targets_" + tfName, OBJPROP_TIMEFRAMES, targetsTF);
    }
    // Retired M30 ATR column (2026-09-11, see DisplayATRLabels): DELETED, not
    // hidden, so a chart painted by an older build is cleaned no matter which
    // toggle the user reaches for first. Names are in this chart-TF namespace
    // (same prefix DisplayATRLabels wrote them with); other TF namespaces are
    // swept by ClearAllLabels on their own redraw.
    ObjectDelete(0, uniquePrefix + "ATR_M30");
    ObjectDelete(0, uniquePrefix + "ATR_Steps_M30");
    ObjectDelete(0, uniquePrefix + "ATR_Targets_M30");
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_SL_Text", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_SL_Value", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_HuntSL_Text", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_HuntSL_Value", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_EngSL_Text", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_EngSL_Value", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TP1_Text", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TP1_Value", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TP2_Text", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TP2_Value", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TP3_Text", OBJPROP_TIMEFRAMES, tf);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TP3_Value", OBJPROP_TIMEFRAMES, tf);
    // R-TRADEPLAN block + TRex stamp (purge lines for the retired
    // 12-piece + ATR-row names above stay so old charts clean up).
    long tradeTF = (shouldShow && inpShowATRTradeLabels) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long slTF = (tradeTF == OBJ_ALL_PERIODS && inpShowATRTradeSLLabels) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long tpTF = (tradeTF == OBJ_ALL_PERIODS && inpShowATRTradeTPLabels) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_ATR", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_SLRow", OBJPROP_TIMEFRAMES, slTF);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TPRow", OBJPROP_TIMEFRAMES, tpTF);
    // The countdown left this block (own switch since 2026-09-11) — only its
    // retired name is purged here so charts from older builds lose it for good.
    ObjectDelete(0, uniquePrefix + LIVE_COUNTDOWN_LEGACY_NAME);
    ObjectSetInteger(0, uniquePrefix + "TREX_Spread", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_Caption", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_TR", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_EX", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_Hunter", OBJPROP_TIMEFRAMES, slTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_StrBond", OBJPROP_TIMEFRAMES, slTF);
}

void SetTHLabelsVisibility(const string objectPrefix, const int mode) {
    bool shouldShow = ((mode != 0) && !IsIndicatorHidden());
    long tf = shouldShow ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;

    ObjectSetInteger(0, objectPrefix + "TH_Title", OBJPROP_TIMEFRAMES, tf);

    bool showFractal = (mode == 1 || mode == 3);
    bool showStandard = (mode == 2 || mode == 3);

    long fractalTF = (shouldShow && showFractal) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long fractalTargetsTF = (shouldShow && showFractal && inpShowTHTargets) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    int _nFractal = ArraySize(FRACTAL_TIMEFRAMES);
    for(int i = 0; i < _nFractal; i++) {
        string timeframeName = FRACTAL_TIMEFRAMES[i];
        ObjectSetInteger(0, StringFormat("%sTH_%s", objectPrefix, timeframeName), OBJPROP_TIMEFRAMES, fractalTF);
        ObjectSetInteger(0, StringFormat("%sTH_Steps_%s", objectPrefix, timeframeName), OBJPROP_TIMEFRAMES, fractalTF);
        ObjectSetInteger(0, StringFormat("%sTH_Targets_%s", objectPrefix, timeframeName), OBJPROP_TIMEFRAMES, fractalTargetsTF);
    }
    long standardTF = (shouldShow && showStandard) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long standardTargetsTF = (shouldShow && showStandard && inpShowTHTargets) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    int _nStandard = ArraySize(STANDARD_TIMEFRAMES);
    for(int i = 0; i < _nStandard; i++) {
        string timeframeName = STANDARD_TIMEFRAMES[i];
        ObjectSetInteger(0, StringFormat("%sTH_%s", objectPrefix, timeframeName), OBJPROP_TIMEFRAMES, standardTF);
        ObjectSetInteger(0, StringFormat("%sTH_Steps_%s", objectPrefix, timeframeName), OBJPROP_TIMEFRAMES, standardTF);
        ObjectSetInteger(0, StringFormat("%sTH_Targets_%s", objectPrefix, timeframeName), OBJPROP_TIMEFRAMES, standardTargetsTF);
    }
}

//+------------------------------------------------------------------+
//| TH label helpers (ported from MT5)                               |
//+------------------------------------------------------------------+
bool CreateTHLabel(const string objectPrefix, const string timeframeName, const double thValuePoints, const int xPos, const int yPos, const color textColor, const int horizontalSpacing, const int verticalSpacing) {
    double point = GetCachedPoint();
    double pipSize = GetCachedPipSize();
    if(IsZero(point, EPSILON_PRICE) || IsZero(pipSize, EPSILON_PRICE)) return false;
    
    double thValuePips = NormalizeDouble((thValuePoints * point) / pipSize, 1);
    double shortStepPips = NormalizeDouble(thValuePips * SS_MULTIPLIER, 1);
    double longStepPips = NormalizeDouble(thValuePips * LS_MULTIPLIER, 1);
    double midStepPips = NormalizeDouble((shortStepPips + longStepPips) / 2.0, 1);
    double target3x = MathFloor(thValuePips * 3.0);
    double target5x = MathFloor(thValuePips * 5.0);
    double target15x = MathFloor(thValuePips * 15.0);
    
    string mainObjName = objectPrefix + "TH_" + timeframeName;
    string stepsObjName = objectPrefix + "TH_Steps_" + timeframeName;
    string targetsObjName = objectPrefix + "TH_Targets_" + timeframeName;
    
    bool mainCreated = false;
    bool stepsCreated = false;
    bool targetsCreated = false;
    
    if (ObjectFind(0, mainObjName) < 0) {
        if (!ObjectCreate(0, mainObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, mainObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        mainCreated = true;
    }
    if (ObjectFind(0, stepsObjName) < 0) {
        if (!ObjectCreate(0, stepsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, stepsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        stepsCreated = true;
    }
    if (inpShowTHTargets && ObjectFind(0, targetsObjName) < 0) {
        if (!ObjectCreate(0, targetsObjName, OBJ_LABEL, 0, 0, 0)) return false;
        ObjectSetString(0, targetsObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
        targetsCreated = true;
    }
    
    if(!inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
        ObjectDelete(0, targetsObjName);
    }

    string mainText = StringFormat("%s: %.1f", GetBaseTimeframeName(timeframeName), thValuePips);
    string stepsText = StringFormat("(%.1f - %.1f - %.1f)", shortStepPips, midStepPips, longStepPips);
    string targetsText = StringFormat("%.0f - %.0f - %.0f", target3x, target5x, target15x);
    
    // PERF: Only update text/color if changed (using Cache)
    string cachedText;
    color cachedColor;
    bool exists = CacheGetLabel(mainObjName, cachedText, cachedColor);
    
    // CRITICAL FIX: If any object was just created (mainCreated/stepsCreated/targetsCreated), 
    // we MUST force text/color updates even if cache says they match.
    bool textChanged = mainCreated || stepsCreated || targetsCreated || !exists || (cachedText != mainText);
    bool colorChanged = mainCreated || stepsCreated || targetsCreated || !exists || (cachedColor != textColor);
    
    if(textChanged) {
        ObjectSetString(0, mainObjName, OBJPROP_TEXT, mainText);
        ObjectSetString(0, stepsObjName, OBJPROP_TEXT, stepsText);
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
            ObjectSetString(0, targetsObjName, OBJPROP_TEXT, targetsText);
        }
        CacheUpdateLabel(mainObjName, mainText, textColor);
    }
    
    if(colorChanged) {
        ObjectSetInteger(0, mainObjName, OBJPROP_COLOR, textColor);
        ObjectSetInteger(0, stepsObjName, OBJPROP_COLOR, textColor);
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
            ObjectSetInteger(0, targetsObjName, OBJPROP_COLOR, textColor);
        }
        CacheUpdateLabel(mainObjName, mainText, textColor);
    }
    
    if(mainCreated) SetLabelFont(mainObjName);
    if(stepsCreated) SetLabelFont(stepsObjName);
    if(targetsCreated) SetLabelFont(targetsObjName);
    
    ENUM_BASE_CORNER corner = CORNER_LEFT_LOWER;
    ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
    
    if(mainCreated) {
        ObjectSetInteger(0, mainObjName, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, mainObjName, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(0, mainObjName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, mainObjName, OBJPROP_HIDDEN, false);
    }
    if(stepsCreated) {
        ObjectSetInteger(0, stepsObjName, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, stepsObjName, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(0, stepsObjName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, stepsObjName, OBJPROP_HIDDEN, false);
    }
    if(targetsCreated) {
        ObjectSetInteger(0, targetsObjName, OBJPROP_CORNER, corner);
        ObjectSetInteger(0, targetsObjName, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(0, targetsObjName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, targetsObjName, OBJPROP_HIDDEN, false);
    }
    
    int labelXDistance = MathAbs(xPos);
    int bottomPadding = 0;
    int lineGap = inpLabelRowGap;
    int singleLineHeight = inpFontSize + lineGap;
    
    int mainTextWidth = (int)(StringLen(mainText) * inpFontSize * FONT_CHAR_WIDTH_FACTOR);
    int stepsTextWidth = (int)(StringLen(stepsText) * inpFontSize * FONT_CHAR_WIDTH_FACTOR);
    int mainOffset = (stepsTextWidth - mainTextWidth) / 2;
    if(mainOffset < 0) mainOffset = 0;
    
    int targetsOffset = 0;
    if(inpShowTHTargets) {
        int targetsTextWidth = (int)(StringLen(targetsText) * inpFontSize * FONT_CHAR_WIDTH_FACTOR);
        targetsOffset = (mainTextWidth - targetsTextWidth) / 2 + mainOffset;
        if(targetsOffset < 0) targetsOffset = 0;
    }
    
    int baseY = MathAbs(yPos) + bottomPadding;
    if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) {
        ObjectSetInteger(0, targetsObjName, OBJPROP_YDISTANCE, baseY);
        ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight);
        ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight * 2);
        ObjectSetInteger(0, targetsObjName, OBJPROP_XDISTANCE, labelXDistance + targetsOffset);
    } else {
        ObjectSetInteger(0, stepsObjName, OBJPROP_YDISTANCE, baseY);
        ObjectSetInteger(0, mainObjName, OBJPROP_YDISTANCE, baseY + singleLineHeight);
    }
    
    ObjectSetInteger(0, mainObjName, OBJPROP_XDISTANCE, labelXDistance + mainOffset);
    ObjectSetInteger(0, stepsObjName, OBJPROP_XDISTANCE, labelXDistance);
    
    // Respect Hide state (F key)
    if(IsIndicatorHidden()) {
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    } else {
        if(inpShowTHTargets && ObjectFind(0, targetsObjName) >= 0) ObjectSetInteger(0, targetsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, mainObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, stepsObjName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    
    return true;
}

void DisplayFractalTHs(const string objectPrefix, const double dailyPriceForTH, const datetime currentTime) {
    if(!g_thLabelsVisible || (g_thLabelsMode != 1 && g_thLabelsMode != 3)) return;
    
    double point = GetCachedPoint();
    int digits = GetCachedDigits();
    if(IsZero(point, EPSILON_PRICE) || digits == 0) return;

    string labelPrefix = objectPrefix + "LBL_";
    bool isVerticalLayout = (inpLabelArrangement == LABEL_ARRANGEMENT_VERTICAL);
    int rowSpacing = inpLabelRowGap;
    int horizontalPadding = inpLabelColumnGap;
    int startXPos = inpLabelsMarginLeft;
    int lineGap = rowSpacing;
    int singleLineHeight = inpFontSize + lineGap;
    int titleYPos = inpTHLabelsMarginBottom + g_currentLabelYOffsetBottom;
    int startYPos = isVerticalLayout ? (titleYPos + singleLineHeight) : titleYPos;
    int sectionGap = inpSectionGap;

    string thTitleObjName = labelPrefix + "TH_Title";
    if(ObjectFind(0, thTitleObjName) < 0) {
        ObjectCreate(0, thTitleObjName, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, thTitleObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    ObjectSetString(0, thTitleObjName, OBJPROP_TEXT, "TH:");
    ObjectSetInteger(0, thTitleObjName, OBJPROP_COLOR, clrDarkBlue);
    ObjectSetString(0, thTitleObjName, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_FONTSIZE, inpFontSize);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_HIDDEN, false);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_XDISTANCE, inpLabelsMarginLeft);
    ObjectSetInteger(0, thTitleObjName, OBJPROP_YDISTANCE, titleYPos + (inpShowTHTargets ? singleLineHeight * 2 : singleLineHeight));
    ObjectSetInteger(0, thTitleObjName, OBJPROP_TIMEFRAMES, IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);

    int titleWidth = (int)CalculateTextWidth("TH:");
    int labelStartX = GetLabelStartX(startXPos, titleWidth, horizontalPadding, isVerticalLayout);
    int currentXPos = labelStartX;
    int currentYPos = startYPos;
    int xStep = horizontalPadding;
    int maxWidth = GetCachedChartWidth() - startXPos * 2;
    int lineHeight = GetLabelLineHeight(inpShowTHTargets, rowSpacing);

    int _nFrac = ArraySize(FRACTAL_TIMEFRAMES);
    for(int i = 0; i < _nFrac; i++) {
        string timeframeName = FRACTAL_TIMEFRAMES[i];
        double percentage = MODIFIED_FRACTAL_PERCENTAGES[i];
        double thPoints = CalculateTHPoints(dailyPriceForTH, digits, percentage);
        double thPips10 = thPoints / 10.0;
        
        color labelColor = FRACTAL_COLORS[i];
        string mainText = inpShowTimeframeInLabels ? StringFormat("%s: %.1f", GetBaseTimeframeName(timeframeName), thPips10) : DoubleToString(thPips10, 1);
        string stepsText = StringFormat("(%.1f - %.1f - %.1f)", thPips10 * 1.5, thPips10 * 1.75, thPips10 * 2.0);
        string targetsText = StringFormat("%.0f - %.0f - %.0f", MathFloor(thPips10 * 3.0), MathFloor(thPips10 * 5.0), MathFloor(thPips10 * 15.0));
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowTHTargets);

        if(isVerticalLayout) {
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentYPos += lineHeight;
        } else {
            if(currentXPos + labelWidth + xStep > maxWidth) {
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentXPos += labelWidth + xStep;
        }
    }

    g_currentLabelYOffsetBottom += (currentYPos - startYPos) + lineHeight + sectionGap;
}

void DisplayStandardTHs(const string objectPrefix, const double dailyPriceForTH, const datetime currentTime) {
    if(!g_thLabelsVisible || (g_thLabelsMode != 2 && g_thLabelsMode != 3)) return;

    double point = GetCachedPoint();
    int digits = GetCachedDigits();
    if(IsZero(point, EPSILON_PRICE) || digits == 0) return;

    string labelPrefix = objectPrefix + "LBL_";
    bool isVerticalLayout = (inpLabelArrangement == LABEL_ARRANGEMENT_VERTICAL);
    int rowSpacing = inpLabelRowGap;
    int horizontalPadding = inpLabelColumnGap;
    int startXPos = inpLabelsMarginLeft;
    int lineGap = rowSpacing;
    int singleLineHeight = inpFontSize + lineGap;
    int titleYPos = inpTHLabelsMarginBottom + g_currentLabelYOffsetBottom;
    int startYPos = isVerticalLayout ? (titleYPos + singleLineHeight) : titleYPos;
    int sectionGap = inpSectionGap;

    string thTitleObjName = labelPrefix + "TH_Title";
    if(ObjectFind(0, thTitleObjName) < 0) {
        ObjectCreate(0, thTitleObjName, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(0, thTitleObjName, OBJPROP_TEXT, ""); // Clear default "Label" text
    }
    // Title already set in DisplayFractalTHs if BOTH mode, but we update Y position here
    ObjectSetInteger(0, thTitleObjName, OBJPROP_YDISTANCE, titleYPos + (inpShowTHTargets ? singleLineHeight * 2 : singleLineHeight));

    int titleWidth = (int)CalculateTextWidth("TH:");
    int labelStartX = GetLabelStartX(startXPos, titleWidth, horizontalPadding, isVerticalLayout);
    int currentXPos = labelStartX;
    int currentYPos = startYPos;
    int xStep = horizontalPadding;
    int maxWidth = GetCachedChartWidth() - startXPos * 2;
    int lineHeight = GetLabelLineHeight(inpShowTHTargets, rowSpacing);

    int _nStd = ArraySize(STANDARD_TIMEFRAMES);
    for(int i = 0; i < _nStd; i++) {
        string timeframeName = STANDARD_TIMEFRAMES[i];
        double percentage = CalculateStandardPercentage(STANDARD_MINUTES[i]);
        double thPoints = CalculateTHPoints(dailyPriceForTH, digits, percentage);
        double thPips10 = thPoints / 10.0;
        
        color labelColor = STANDARD_COLORS[i];
        string mainText = inpShowTimeframeInLabels ? StringFormat("%s: %.1f", timeframeName, thPips10) : DoubleToString(thPips10, 1);
        string stepsText = StringFormat("(%.1f - %.1f - %.1f)", thPips10 * 1.5, thPips10 * 1.75, thPips10 * 2.0);
        string targetsText = StringFormat("%.0f - %.0f - %.0f", MathFloor(thPips10 * 3.0), MathFloor(thPips10 * 5.0), MathFloor(thPips10 * 15.0));
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowTHTargets);

        if(isVerticalLayout) {
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentYPos += lineHeight;
        } else {
            if(currentXPos + labelWidth + xStep > maxWidth) {
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            currentXPos += labelWidth + xStep;
        }
    }

    g_currentLabelYOffsetBottom += (currentYPos - startYPos) + lineHeight + sectionGap;
}

void StoreLabelPosition(const string name, const int xPos, const int yPos) {
    for(int i=0; i<ArraySize(g_labelPositions); i++) {
        if(g_labelPositions[i].name == name) {
            g_labelPositions[i].xPos = xPos;
            g_labelPositions[i].yPos = yPos;
            return;
        }
    }
    int size=ArraySize(g_labelPositions);
    if(ArrayResize(g_labelPositions,size+1)) {
        g_labelPositions[size].name=name;
        g_labelPositions[size].xPos=xPos;
        g_labelPositions[size].yPos=yPos;
    } else {
        Print("StoreLabelPosition: Failed to resize array");
    }
}

int GetStoredXPosition(const string name) {
    for(int i=0; i<ArraySize(g_labelPositions); i++) if(g_labelPositions[i].name==name) return g_labelPositions[i].xPos;
    return inpInitialX;
}

double CalculateTextWidth(string text) {
    static int lastFontSize = -1;
    static double charWidth = 0;
    static double plusAdd = 0;
    static double numAdd = 0;
    
    if(inpFontSize != lastFontSize) {
        lastFontSize = inpFontSize;
        charWidth = lastFontSize * 0.7;
        plusAdd = lastFontSize * 0.3;
        numAdd = lastFontSize * 0.2;
    }
    
    int len = StringLen(text);
    if(len == 0) return 0;
    
    bool hasPlus = false;
    bool hasNum = false;
    for(int i=0; i<len; i++) {
        ushort c = StringGetCharacter(text, i);
        if(c >= '0' && c <= '9') hasNum = true;
        else if(c == '+') hasPlus = true;
        if(hasPlus && hasNum) break;
    }
    
    return len * charWidth + (hasPlus ? plusAdd : 0) + (hasNum ? numAdd : 0);
}

//+------------------------------------------------------------------+
//| Label layout helpers (ported from MT5)                            |
//+------------------------------------------------------------------+
int GetLabelLineHeight(const bool showTargets, const int rowSpacing) {
    int lines = showTargets ? 3 : 2;
    return (inpFontSize + rowSpacing) * lines;
}

int GetLabelBlockWidth(const string mainText, const string stepsText, const string targetsText, const bool showTargets) {
    int maxW = (int)CalculateTextWidth(mainText);
    int stepsWidth = (int)CalculateTextWidth(stepsText);
    if(stepsWidth > maxW) maxW = stepsWidth;
    if(showTargets) {
        int targetsWidth = (int)CalculateTextWidth(targetsText);
        if(targetsWidth > maxW) maxW = targetsWidth;
    }
    return maxW;
}

int GetLabelStartX(const int baseX, const int titleWidth, const int padding, const bool isVertical) {
    int titleGap = MathMin(padding, 6);
    return isVertical ? baseX : baseX + titleWidth + titleGap;
}

int GetBottomTitleYOffset(const bool showTargets, const int rowSpacing) {
    int singleLineHeight = inpFontSize + rowSpacing;
    return showTargets ? singleLineHeight * 2 : singleLineHeight;
}

string StringRepeat(string str, int count) {
    string result = "";
    for(int i=0; i<count; i++) {
        result = result + str;
    }
    return result;
}


//+------------------------------------------------------------------+
//| Create/Update Timeframe Lock Status Label                        |
//| Shows lock status and timeframe when locked (integrated overlay) |
//+------------------------------------------------------------------+
void UpdateLockStatusLabel(bool updateTimestamp = true)
{
    if(!inpShowModeChangeLabel) return;
    if(IsIndicatorHidden()) return;
    
    // Only show if we are explicitly triggering a show (updateTimestamp=true) 
    // or if it's already visible (g_lockStatusLabelCreateTime > 0)
    if(!updateTimestamp && g_lockStatusLabelCreateTime == 0) return;
    
    if(g_timeframeLocked)
    {
        string lockText = "[ LOCK: " + PeriodToString(g_lockedPeriod) + " ]";
        
        if(ObjectFind(0, g_lockStatusLabelName) < 0)
        {
            if(!ObjectCreate(0, g_lockStatusLabelName, OBJ_LABEL, 0, 0, 0))
            {
                Print("Failed to create lock status label. Error: ", GetLastError());
                return;
            }
            g_lockStatusLabelCreateTime = GetTickCount();
        }
        
        SetLabelTextIfChanged(g_lockStatusLabelName, lockText);
        
        if(updateTimestamp) g_lockStatusLabelCreateTime = GetTickCount();
        ApplyModeLabelStyle(g_lockStatusLabelName, clrGold);
        
        ObjectSetString(0, g_lockStatusLabelName, OBJPROP_TOOLTIP, "TF locked to " + PeriodToString(g_lockedPeriod) + " - Press " + inpLockKey + " to unlock");
    }
    else
    {
        if(ObjectFind(0, g_lockStatusLabelName) >= 0)
        {
            ObjectDelete(0, g_lockStatusLabelName);
        }
        g_lockStatusLabelCreateTime = 0;
    }
}

//+------------------------------------------------------------------+
//| Convert period to readable string                                |
//+------------------------------------------------------------------+
string PeriodToString(int period)
{
    switch(period)
    {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN";
        default:         return "TF" + IntegerToString(period);
    }
}



#endif // LABEL_FUNCTIONS_MQH
