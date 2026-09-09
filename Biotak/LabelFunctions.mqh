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
    static string s_tfSuffixes[] = {"M1","M5","M15","M30","H1","H4","D1","W1","MN"};
    string basePrefix = inpObjectPrefix + "_";
    for(int j = 0; j < ArraySize(s_tfSuffixes); j++) {
        string tfLblPrefix = basePrefix + s_tfSuffixes[j];
        ObjectsDeleteAll(0, tfLblPrefix + "_LBL_");
    }
    
    // (b) Delete objectPrefix + "TF*" labels (legacy)
    ObjectsDeleteAll(0, objectPrefix + "TF");
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

// Countdown to the current chart bar close ("Close in : 22d 12h 32m 13s").
// Units below the leading non-zero one are skipped (H1 shows "17m 51s").
string TradePlanCloseInText()
{
   datetime bt = iTime(Symbol(), Period(), 0);
   if(bt <= 0) return "Close in : --";
   long left = (long)(bt + PeriodSeconds() - TimeCurrent());
   if(left < 0) left = 0;
   long d = left / 86400; left -= d * 86400;
   long h = left / 3600;  left -= h * 3600;
   long m = left / 60;
   long s = left - m * 60;
   string t = "";
   if(d > 0) t = t + IntegerToString(d) + "d ";
   if(d > 0 || h > 0) t = t + IntegerToString(h) + "h ";
   if(d > 0 || h > 0 || m > 0) t = t + IntegerToString(m) + "m ";
   t = t + IntegerToString(s) + "s";
   return "Close in : " + t;
}

bool CreateATRTradeLabel(const string objectPrefix, const STradePlan &plan,
                         const int xPos, const int yPos)
{
   // Screenshot bottom-right block (R-TRADEPLAN):
   //   Close in : <countdown>                      (red)
   //   #SL:-<sl> #TP1+<t1> #TP2+<t2> #TP3+<t3>     (blue, single row)
   string tpName = objectPrefix + "ATR_Trade_Current_TPRow";
   string ciName = objectPrefix + "ATR_Trade_Current_CloseIn";

   string tpText = StringFormat("#SL:-%d #TP1+%d #TP2+%d #TP3+%d",
                                plan.sl, plan.tp1, plan.tp2, plan.tp3);
   string ciText = TradePlanCloseInText();

   // Purge the retired layouts: every "Current" piece shares this prefix, so
   // one kernel call wipes legacy pieces (plus ours, recreated below).
   ObjectsDeleteAll(0, objectPrefix + "ATR_Trade_Current_");
   ObjectDelete(0, objectPrefix + "ATR_Trade_Current_ATR");
   ObjectDelete(0, objectPrefix + "ATR_Trade_Current_SLRow");
   ObjectDelete(0, objectPrefix + "ATR_Trade_" + PeriodToString(plan.chartMin));
   ObjectDelete(0, objectPrefix + "ATR_Trade_" + PeriodToString(plan.chartMin) + "_Targets");
   ObjectDelete(0, objectPrefix + "ATR_Trade_" + PeriodToString(plan.chartMin) + "_Stops");
   ObjectDelete(0, objectPrefix + "ATR_Trade_Formula");

   bool showTP = (inpShowATRTradeLabels && inpShowATRTradeTPLabels);
   int rightMargin  = MathMax(8, MathAbs(xPos));
   int bottomMargin = MathMax(8, MathAbs(yPos));
   int lineHeight   = inpFontSize + inpATRTradeLabelRowGap;

   // Center every visible row inside the block (block right edge stays fixed).
   double wTP = CalculateTextWidth(tpText);
   double wCI = CalculateTextWidth(ciText);
   double maxW = wTP;
   if(wCI > maxW) maxW = wCI;

   // Bottom-up stack: TP at the bottom, Close-in on top.
   int row = 0;
   if(showTP) {
       int xTP = rightMargin + (int)((maxW - wTP) / 2.0);
       if(!CreateATRTradePiece(tpName, tpText, clrBlue, xTP, bottomMargin + row * lineHeight)) return false;
       row++;
   }
   int xCI = rightMargin + (int)((maxW - wCI) / 2.0);
   if(!CreateATRTradePiece(ciName, ciText, clrRed, xCI, bottomMargin + row * lineHeight)) return false;
   return true;
}

// Top-right Hunter / StrBond rows, below the TRex stamp (R-TRADEPLAN).
// Same right-edge metrics as DisplayTRexTitleBlock so the stamp stays one block.
bool DisplayTradePlanTopRows(const string labelPrefix, const STradePlan &plan)
{
   int fontSize  = inpFontSize;
   int brandSize = inpFontSize + 6;
   int rightMargin = MathMax(8, inpLabelsMarginLeft);
   int yBrand  = MathMax(8, inpLabelsMarginTop);
   int yCap    = yBrand + brandSize + inpLabelRowGap;
   int yHunter = yCap + fontSize + inpLabelRowGap;
   int yBond   = yHunter + fontSize + inpLabelRowGap;
   string hText = StringFormat("Hunter SL: %d Eng.SL: %d", plan.hunter, plan.eng);
   string bText = StringFormat("Str Bond: %d - %d", plan.sb1, plan.sb2);
   if(!CreateTRexPiece(labelPrefix + "TREX_Hunter", hText, clrRed, fontSize, rightMargin, yHunter)) return false;
   if(!CreateTRexPiece(labelPrefix + "TREX_StrBond", bText, clrBlue, fontSize, rightMargin, yBond)) return false;
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
    string timeframes[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN1"};
    int tfMinutes[] = {1, 5, 15, 30, 60, 240, 1440, 10080, 43200};

    // Use TH colors for ATR
    color colors[] = {
        clrBlack,        // M1
        clrBlack,        // M5
        clrBlack,        // M15
        clrBlack,        // M30
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
void TradePlanLiveTick()
{
    if(!inpShowATRTradeLabels || !g_atrLabelsVisible || IsIndicatorHidden()) return;
    uint nowMs = GetTickCount();
    static uint s_lastMs = 0;
    if(nowMs - s_lastMs < 2000) return;
    s_lastMs = nowMs;
    STradePlan plan;
    if(!TradePlanComputeLive(Period(), plan)) return;
    string sig = StringFormat("%d|%d|%d|%d|%d|%d|%d|%d|%s",
                              plan.sl, plan.tp1, plan.tp2, plan.tp3,
                              plan.hunter, plan.eng, plan.sb1, plan.sb2,
                              TradePlanCloseInText());
    static string s_sig = "";
    if(sig == s_sig) return;
    s_sig = sig;

    // [TRADEPLAN-LOG] Write once per change to tradeplan_log.txt in MQL4\Files\.
    // Run tools/read_tradeplan_log.ps1 to copy it into the repo so the AI can read it.
    {
       int fh = FileOpen("tradeplan_log.txt",
                         FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI,
                         ',');
       if(fh != INVALID_HANDLE)
       {
          // Seek to end so we APPEND (FileOpen with FILE_WRITE truncates by default;
          // seek past end is the standard MQL4 append pattern).
          FileSeek(fh, 0, SEEK_END);

          string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS);
          FileWrite(fh, "=== TRADEPLAN [" + Symbol() + " " + GetCurrentTimeframe() + "] " + ts + " ===");
          FileWrite(fh, "  TR(own)=" + DoubleToString(plan.ownPips, 1)
                        + "  Eng.SL=" + IntegerToString(plan.eng)
                        + "  Hunter=" + IntegerToString(plan.hunter));
          FileWrite(fh, "  SL=" + IntegerToString(plan.sl)
                        + "  TP1=" + IntegerToString(plan.tp1)
                        + "  TP2=" + IntegerToString(plan.tp2)
                        + "  TP3=" + IntegerToString(plan.tp3));
          FileWrite(fh, "  StrBond=" + IntegerToString(plan.sb1)
                        + " - " + IntegerToString(plan.sb2));
          FileWrite(fh, "  slTrue=" + DoubleToString(plan.slTrue, 4)
                        + "  engTrue=" + DoubleToString(plan.engTrue, 4)
                        + "  basePips=" + DoubleToString(plan.basePips, 4));
          FileWrite(fh, "  chartMin=" + IntegerToString(plan.chartMin)
                        + "  strMin=" + IntegerToString(plan.strMin)
                        + "  trigMin=" + IntegerToString(plan.trigMin));
          FileWrite(fh, "---");
          FileClose(fh);
       }
    }

    string labelPrefix = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_" + "LBL_";
    CreateATRTradeLabel(labelPrefix, plan,
                        inpLabelsMarginLeft, inpLabelsMarginBottom);
    DisplayTRexTitleBlock(labelPrefix);
    if(inpShowATRTradeSLLabels)
        DisplayTradePlanTopRows(labelPrefix, plan);
    else {
        ObjectDelete(0, labelPrefix + "TREX_Hunter");
        ObjectDelete(0, labelPrefix + "TREX_StrBond");
    }
    ThrottledChartRedraw();
}

void SetATRLabelsVisibility(const string objectPrefix, const bool visible) {
    string uniquePrefix = objectPrefix + "LBL_";
    string allTimeframes[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", "MN1"};

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
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_CloseIn", OBJPROP_TIMEFRAMES, tradeTF);
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
