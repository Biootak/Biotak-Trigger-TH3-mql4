// Labels_B.mqh - LabelFunctions.mqh split 2026-09-29: exact lines 1404-2072, byte-identical, zero renames.
#ifndef LABELS_B_MQH
#define LABELS_B_MQH

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
    // P-UI-84: the card is NOT part of `shouldShow` (the ATR overview). It owns
    // its master switch and answers to that one alone, so an `ATR` tile press,
    // the label card's `ATR LABELS` row or the A key can never mask the trade
    // plan away. `IsIndicatorHidden()` is the ONE term it still shares with the
    // ATR block, because that is the whole-indicator F-hide, not a layer choice.
    bool cardOn = (inpShowATRTradeLabels && !IsIndicatorHidden());
    long tradeTF = cardOn ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long slTF = (tradeTF == OBJ_ALL_PERIODS && inpShowATRTradeSLLabels) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long tpTF = (tradeTF == OBJ_ALL_PERIODS && inpShowATRTradeTPLabels) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_ATR", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_SLRow", OBJPROP_TIMEFRAMES, slTF);
    ObjectSetInteger(0, uniquePrefix + "ATR_Trade_Current_TPRow", OBJPROP_TIMEFRAMES, tpTF);
    // The countdown left this block (own switch since 2026-09-11) — only its
    // retired name is purged here so charts from older builds lose it for good.
    ObjectDelete(0, uniquePrefix + LIVE_COUNTDOWN_LEGACY_NAME);
    ObjectSetInteger(0, uniquePrefix + "TREX_Spread", OBJPROP_TIMEFRAMES, tradeTF);
    // The caption is RETIRED (P-LBL-06): no mask to write, only a purge so a
    // chart painted by an older build loses the row on the next relayout.
    ObjectDelete(0, uniquePrefix + "TREX_Caption");
    ObjectSetInteger(0, uniquePrefix + "TREX_TR", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_EX", OBJPROP_TIMEFRAMES, tradeTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_Hunter", OBJPROP_TIMEFRAMES, slTF);
    ObjectSetInteger(0, uniquePrefix + "TREX_StrBond", OBJPROP_TIMEFRAMES, slTF);

    // P-PERF-02: the masks above were written OUTSIDE the visibility guard, so
    // the guard's memory for these names is now stale — drop it, or a later
    // guarded write could skip a mask this function just changed.
    CacheForgetTfMasks(uniquePrefix);
}

void SetTHLabelsVisibility(const string objectPrefix, const int mode) {
    bool shouldShow = ((mode != 0) && !IsIndicatorHidden());
    long tf = shouldShow ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;

    ObjectSetInteger(0, objectPrefix + "TH_Title", OBJPROP_TIMEFRAMES, tf);

    bool showFractal = (mode == 1);
    bool showStandard = (mode == 2);

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

    // P-PERF-02: masks written outside the guard → drop the stored memory
    // (see SetATRLabelsVisibility).
    CacheForgetTfMasks(objectPrefix + "TH_");
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
    
    // P-UI-42: measured widths, not a per-character factor (see
    // CalculateTextWidth) - the centring uses the same numbers the column
    // reservation does, so every line is centred on the widest ONE.
    int mainTextWidth = (int)CalculateTextWidth(mainText);
    int stepsTextWidth = (int)CalculateTextWidth(stepsText);
    int mainOffset = (stepsTextWidth - mainTextWidth) / 2;
    if(mainOffset < 0) mainOffset = 0;
    
    int targetsOffset = 0;
    if(inpShowTHTargets) {
        int targetsTextWidth = (int)CalculateTextWidth(targetsText);
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
    if(!g_thLabelsVisible || g_thLabelsMode != 1) return;
    // P-UI-43: the shown section opens the bottom side and owns the margin.
    // Modes are exclusive now, so each block resets the stack when it paints.
    g_currentLabelYOffsetBottom = 0;
    
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
    int maxWidth = LabelRowMaxWidth(startXPos);   // P-UI-94: one owner, never negative
    int lineHeight = GetLabelLineHeight(inpShowTHTargets, rowSpacing);

    int _nFrac = ArraySize(FRACTAL_TIMEFRAMES);
    int painted = 0;   // P-UI-43: columns this section really painted (slot booking)
    for(int i = 0; i < _nFrac; i++) {
        string timeframeName = FRACTAL_TIMEFRAMES[i];
        // P-TH-01: SCALED — the strip is the DISPLAY of the ladder that gets
        // drawn, so it must show the knob's numbers, never the raw table's.
        // A strip that disagreed with the lines would be the one way the user
        // could not tell whether the knob did anything.
        double percentage = FractalPercentScaled(i);
        double thPoints = CalculateTHPoints(dailyPriceForTH, digits, percentage);
        // P-UI-52: pips through the ONE owner (`GetCachedPipSize()`), never the
        // hard-coded `point * 10`: on a 2-digit index/crypto symbol a pip is one
        // point, so the old constant printed every figure in this column 10x
        // smaller than the ATR/combo/BaseKnot pip figures of the SAME symbol.
        // `thPoints` is a point count (price / point), so the pip value is
        // thPoints * point / pipSize - one cached getter, same cost as the
        // constant it replaces, with the old result as the zero-pip fallback.
        double pipNow = GetCachedPipSize();
        double thPips10 = (pipNow > 0) ? thPoints * GetCachedPoint() / pipNow : thPoints / 10.0;
        
        color labelColor = FRACTAL_COLORS[i];
        string mainText = inpShowTimeframeInLabels ? StringFormat("%s: %.1f", GetBaseTimeframeName(timeframeName), thPips10) : DoubleToString(thPips10, 1);
        string stepsText = StringFormat("(%.1f - %.1f - %.1f)", thPips10 * 1.5, thPips10 * 1.75, thPips10 * 2.0);
        string targetsText = StringFormat("%.0f - %.0f - %.0f", MathFloor(thPips10 * 3.0), MathFloor(thPips10 * 5.0), MathFloor(thPips10 * 15.0));
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowTHTargets);

        if(isVerticalLayout) {
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            painted++;
            currentYPos += lineHeight;
        } else {
            if(maxWidth > 0 && currentXPos + labelWidth + xStep > maxWidth) {   // P-UI-94
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            painted++;
            currentXPos += labelWidth + xStep;
        }
    }

    // P-UI-43: a section owns a slot in the bottom stack ONLY when it painted a
    // column. This increment used to run unconditionally, so a section whose every
    // CreateTHLabel failed (chart object limit / transient create failure) still
    // booked a full slot - 3 rows x (fontSize + rowGap) + inpSectionGap = 108px at
    // the defaults - and pushed the NEXT section that far off its margin: a gap
    // with nothing above it. DisplayATRLabels has always been guarded this way
    // (renderedCount > 0); this is the same rule on the TH side. The else branch
    // names the event once (change-gated) so the next report is a log line.
    if(painted > 0)
        g_currentLabelYOffsetBottom += (currentYPos - startYPos) + lineHeight + sectionGap;
    else
    {
        static uint s_lastEmptySectionLog = 0;
        uint emptyMs = GetTickCount();
        if(emptyMs - s_lastEmptySectionLog > 60000)
        {
            s_lastEmptySectionLog = emptyMs;
            Print("[I][LBL] P-UI-43 TH section painted 0 columns - its stack slot is skipped");
        }
    }
}

void DisplayStandardTHs(const string objectPrefix, const double dailyPriceForTH, const datetime currentTime) {
    if(!g_thLabelsVisible || g_thLabelsMode != 2) return;
    // Exclusive mode: the shown block owns the bottom margin, no stacking.
    g_currentLabelYOffsetBottom = 0;

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
    // Exclusive mode: only one block paints, the title Y is set here.
    ObjectSetInteger(0, thTitleObjName, OBJPROP_YDISTANCE, titleYPos + (inpShowTHTargets ? singleLineHeight * 2 : singleLineHeight));

    int titleWidth = (int)CalculateTextWidth("TH:");
    int labelStartX = GetLabelStartX(startXPos, titleWidth, horizontalPadding, isVerticalLayout);
    int currentXPos = labelStartX;
    int currentYPos = startYPos;
    int xStep = horizontalPadding;
    int maxWidth = LabelRowMaxWidth(startXPos);   // P-UI-94: one owner, never negative
    int lineHeight = GetLabelLineHeight(inpShowTHTargets, rowSpacing);

    int _nStd = ArraySize(STANDARD_TIMEFRAMES);
    int painted = 0;   // P-UI-43: columns this section really painted (slot booking)
    for(int i = 0; i < _nStd; i++) {
        string timeframeName = STANDARD_TIMEFRAMES[i];
        double percentage = CalculateStandardPercentage(STANDARD_MINUTES[i]);
        double thPoints = CalculateTHPoints(dailyPriceForTH, digits, percentage);
        // P-UI-52: same owner as the fractal column above - see the note there.
        double pipNow = GetCachedPipSize();
        double thPips10 = (pipNow > 0) ? thPoints * GetCachedPoint() / pipNow : thPoints / 10.0;
        
        color labelColor = STANDARD_COLORS[i];
        string mainText = inpShowTimeframeInLabels ? StringFormat("%s: %.1f", timeframeName, thPips10) : DoubleToString(thPips10, 1);
        string stepsText = StringFormat("(%.1f - %.1f - %.1f)", thPips10 * 1.5, thPips10 * 1.75, thPips10 * 2.0);
        string targetsText = StringFormat("%.0f - %.0f - %.0f", MathFloor(thPips10 * 3.0), MathFloor(thPips10 * 5.0), MathFloor(thPips10 * 15.0));
        int labelWidth = GetLabelBlockWidth(mainText, stepsText, targetsText, inpShowTHTargets);

        if(isVerticalLayout) {
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            painted++;
            currentYPos += lineHeight;
        } else {
            if(maxWidth > 0 && currentXPos + labelWidth + xStep > maxWidth) {   // P-UI-94
                currentXPos = labelStartX;
                currentYPos += lineHeight;
            }
            if(!CreateTHLabel(labelPrefix, timeframeName, thPoints, currentXPos, currentYPos, labelColor, xStep, rowSpacing)) continue;
            painted++;
            currentXPos += labelWidth + xStep;
        }
    }

    // P-UI-43: a section owns a slot in the bottom stack ONLY when it painted a
    // column. This increment used to run unconditionally, so a section whose every
    // CreateTHLabel failed (chart object limit / transient create failure) still
    // booked a full slot - 3 rows x (fontSize + rowGap) + inpSectionGap = 108px at
    // the defaults - and pushed the NEXT section that far off its margin: a gap
    // with nothing above it. DisplayATRLabels has always been guarded this way
    // (renderedCount > 0); this is the same rule on the TH side. The else branch
    // names the event once (change-gated) so the next report is a log line.
    if(painted > 0)
        g_currentLabelYOffsetBottom += (currentYPos - startYPos) + lineHeight + sectionGap;
    else
    {
        static uint s_lastEmptySectionLog = 0;
        uint emptyMs = GetTickCount();
        if(emptyMs - s_lastEmptySectionLog > 60000)
        {
            s_lastEmptySectionLog = emptyMs;
            Print("[I][LBL] P-UI-43 TH section painted 0 columns - its stack slot is skipped");
        }
    }
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

//+------------------------------------------------------------------+
//| P-UI-42: how wide will MT4 draw this caption?                     |
//|                                                                  |
//| This used to be a per-character GUESS - `len * 0.7 * inpFontSize` |
//| plus a fudge for digits - and it is what made the ATR/TH columns  |
//| come out with uneven gaps while `inpLabelColumnGap` says one      |
//| number. Two errors sat in it:                                     |
//|   1. it ignored the GLYPH MIX: in Arial Bold a dot or space is    |
//|      .278em and a `W` is .944em, so two captions of equal length  |
//|      are NOT equally wide, yet the guess spent .7em on every       |
//|      character - "(211.1 - 246.3 - 281.4)" was over-reserved by   |
//|      ~15% while a digit-only caption was under-reserved;          |
//|   2. it ignored the TERMINAL's DPI, and MT4 sizes a label font at  |
//|      px = pt * dpi / 72 (the P-UI-30 trap, fixed for the cards):   |
//|      the guess is a coin toss that lands differently on every      |
//|      display and every caption.                                   |
//|                                                                  |
//| The measurement now comes from the ONE metrics owner              |
//| (`PnlRawTextW` in UtilityFunctions.mqh): the same Arial Bold       |
//| advance table and the same cached terminal DPI the settings cards  |
//| already measure with. The RAW entry point is the honest one here   |
//| because these labels pass `inpFontSize` to MT4 unchanged (no       |
//| PnlPt), unlike the panels.                                         |
//|                                                                  |
//| ONLY the measurement changed. The layout algorithm, the            |
//| arrangement, `inpLabelColumnGap`/`inpLabelRowGap`/the margins, the |
//| centering formulae and every object write are exactly as they      |
//| were - and so is the cost: the call count is unchanged (~25-30      |
//| measurements per relayout, a few hundred table lookups, noise next |
//| to the ObjectSet* calls that follow them).                         |
//+------------------------------------------------------------------+
double CalculateTextWidth(string text) {
    return (double)PnlRawTextW(text, inpFontSize);
}

//+------------------------------------------------------------------+
//| P-BK-58 — THE BASE NOTE'S SLOT IN THE FAMILY'S COLUMN.           |
//|                                                                  |
//| The Base Box card's INFO row grew a third rung ("Corner",         |
//| `BK_NOTE_CHART`): the base note stops riding the box and becomes  |
//| a READOUT in this column, next to the ATR/TH columns and the       |
//| TRex trade card. The rung is the user's choice («بین «چسبیده به     |
//| باکس» و «گوشهٔ ثابت» یکی را انتخاب کند»), never an automatic       |
//| switch, and the note's TEXT does not change with it.              |
//|                                                                  |
//| WHERE IT SITS: one row ABOVE whatever this column already stacked |
//| at its floor — the trade card's brand row when the card is drawn  |
//| (its layout pushes that slot), the floor itself when the card is  |
//| off or its plan is cold (the caller's fallback below). `stackEm`  |
//| = 0 means "nothing is stacked": the note then TAKES the floor row |
//| instead of floating a pitch above an empty column.                |
//|                                                                  |
//| THE SLOT IS PUSHED, not read: every margin, pitch and clamp here  |
//| belongs to this module (the label column's own settings), and     |
//| BaseKnotTool sits BELOW it — so it is told the corner, the x and  |
//| the y, and it never reads `inpLabelsMargin*` or the card's layout.|
//+------------------------------------------------------------------+
// The column's floor: `inpLabelsMarginBottom`, clamped by hand (the inputs are applied raw at
// init, so a 0 or a -5 must not push a row through the floor, and a mistyped 5000 must not park
// one mid-screen). ONE owner: the trade card's layout and the note's fallback slot both read it,
// so the two rows can never disagree about where the column ends.
int LabelFloorMargin()
{
   int bottom = inpLabelsMarginBottom;
   if(bottom < 0) bottom = 0;
   if(bottom > TREX_CARD_MAX_MARGIN_BOTTOM) bottom = TREX_CARD_MAX_MARGIN_BOTTOM;
   return bottom;
}
void LabelPushBaseNoteSlot(const int stackY, const int stackEm)
{
   int gap = inpATRTradeLabelRowGap;
   if(gap < 0) gap = 0;
   if(gap > TREX_CARD_MAX_ROW_GAP) gap = TREX_CARD_MAX_ROW_GAP;
   int y = stackY + (stackEm > 0 ? stackEm + gap : 0);
   if(y < 8) y = 8;
   BaseKnotCornerSlotPush(CORNER_RIGHT_LOWER, MathMax(8, inpLabelsMarginLeft), y);
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

// ══════════════════════════════════════════════════════════════════════
// P-UI-94 (2026-09-16) — A LAYOUT BOUND IS NEVER DERIVED FROM A SIZE
// WE DO NOT HAVE.
//
// The three bottom/top column sections (ATR, fractal TH, standard TH)
// each asked `GetCachedChartWidth() - startXPos * 2` for the width a
// row may use before it wraps, and that cache answers 0 when the
// chart's size is not known yet (a fresh attach, a minimized window, a
// `ChartGetInteger` that failed). The expression then went NEGATIVE -
// e.g. `-66` at the default left margin of 33 - and the wrap test
// `currentXPos + labelWidth + xStep > maxWidth` was TRUE for EVERY
// column. So the whole block laid itself out ONE COLUMN PER ROW: a
// 13-column ATR block 13 rows tall, its own section slot measured from
// that (so the next section was pushed ~13 line heights down), and the
// chart covered by columns that were never meant to stack - until the
// next relayout, which is one frame away on a ticking chart and much
// further away on a quiet one.
//
// THE RULE, in ONE owner (three call sites, one answer): an UNKNOWN
// width is "no bound", never "zero width". `0` is the sentinel and the
// wrap test must ask for it explicitly (`maxWidth > 0 && ...`), which
// also keeps the known-size arithmetic byte-for-byte what it was: a
// real chart wraps at exactly the same column as before. A chart that
// really IS narrow still wraps - it answers > 0.
// ══════════════════════════════════════════════════════════════════════
int LabelRowMaxWidth(const int startXPos) {
    int cw = GetCachedChartWidth();      // 100 ms cache; <= 0 = UNKNOWN
    if(cw <= 0) return 0;                // 0 = no bound (the wrap test no-ops)
    int usable = cw - startXPos * 2;
    return (usable > 0) ? usable : 0;    // a known-but-tiny chart still wraps
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



#endif // LABELS_B_MQH
