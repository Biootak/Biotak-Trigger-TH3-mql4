// Labels_A.mqh - LabelFunctions.mqh split 2026-09-29: exact lines 3-1403, byte-identical, zero renames.
#ifndef LABELS_A_MQH
#define LABELS_A_MQH


#property strict

// P-BUILD-02 (2026-09-16) — THIS FILE'S OWN DEPENDENCY, DECLARED HERE.
//
// The label layer takes the trade plan's legs as `STradePlan&` (P-BK-50: the
// box/card rows print the plan's own risk, hunter and targets), and that type is
// declared in TradePlanFormulas.mqh. Both entries happen to include that module
// EARLIER, so the dependency stayed implicit — and every harness that mirrors the
// entry's include list without that one line failed with
// `error 116: 'STradePlan' - declaration without type` (three of them did: Sync
// Compare, ComboRender, ModeLabel). A module declares what it uses, like
// ComboEngine and CalculationCache already do; the include guard makes this a
// no-op in the entries, where the module is already in.
#include "TradePlanFormulas.mqh"

bool DrawMainLevels(const string prefix) {
    // Skip drawing High/Low lines when Custom Price mode is active
    // In Custom Price mode, user defines their own reference point
    if(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) {
        // Delete existing High/Low lines if they exist. P-LBL-12 (2026-10-17):
        // the two `_PipsLabel` purges stay although nothing creates them any
        // more - a chart that ran an older build still carries the objects, and
        // this is one of the sweeps that clears them.
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
    // P-LBL-12 (2026-10-17): the High line's pip-distance label block stood
    // here (`inpShowPipDistanceLabels` -> CreatePipDistanceLabel). The labels
    // are retired; nothing replaces it - the line is the whole surface.
    
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
    // P-LBL-12 (2026-10-17): the Low line's pip-distance label block stood
    // here, twin of the High one above - retired with it.
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
    // P-UI-85 — THE CHART TEXT LAYER OWNS ITS RUNG (P-UI-31's ladder).
    //
    // Everything this family draws is TEXT a human reads: the ATR columns, the
    // TH columns, the bottom-right trade card and the countdown tag — and the
    // ladder file has always declared exactly that rung for it
    // (`Z_CHART_LABEL 100`, "price/level labels, view anchor, countdown tag").
    // The family simply never WROTE it, so every one of these labels sat at
    // ObjectCreate's default ZORDER 0 — the same rung the chart's own art uses
    // (zones 0, level lines 1, box fills/edges 50-61) — and the winner was
    // decided by CREATION ORDER plus whatever a given MT4 build does with
    // OBJPROP_BACK (some builds flatten a rectangle whose FILL=false anyway —
    // the same build quirk the zone code already documents). A drawn HTF candle
    // or a zone edge could therefore sit on top of the ATR text, which is what
    // the report's screenshot shows (white theme: a candle body over the
    // top-left `M1:`/steps labels). Writing the rung here — the ONE funnel every
    // label piece already passes through (CreateATRLabelSimple, the ATR trade
    // pieces and CreateTRexPiece) — makes the order PROVABLE instead of
    // incidental: text 100 is above every chart-space art rung and every box
    // pill (<= 61), and still far below the ring menu (1004+) and the cards
    // (1480+), which stay on top where the user asked for them.
    //
    // COST: one ObjectSetInteger on the CREATE path only, because that is the
    // only place this function runs — the label family is recreated after every
    // ClearAllLabels (relayout, TF switch, re-attach), so no steady-state frame
    // pays for it.
    ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_CHART_LABEL);   // P-UI-31 ladder
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
    // P-PERF-38g: these three are this pass's output (the per-TF ATR columns).
    LblMark(mainObjName);
    LblMark(stepsObjName);
    if(inpShowATRTargets) LblMark(targetsObjName);
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
    // P-UI-42: the three lines are centred on the column's WIDEST line, and the
    // widths are the MEASURED ones (CalculateTextWidth) - the same numbers the
    // caller used to reserve the column, instead of a second per-character
    // factor (0.6 here vs the 0.7 the reservation used) that disagreed with both
    // the measurement and the drawn text.
    int mainTextWidth = (int)CalculateTextWidth(mainText);
    int stepsTextWidth = (int)CalculateTextWidth(stepsText);
    int mainOffset = (stepsTextWidth - mainTextWidth) / 2;
    if(mainOffset < 0) mainOffset = 0;
    
    ObjectSetInteger(0, mainObjName, OBJPROP_XDISTANCE, labelXDistance + mainOffset);
    ObjectSetInteger(0, stepsObjName, OBJPROP_XDISTANCE, labelXDistance);
    
    if(inpShowATRTargets && ObjectFind(0, targetsObjName) >= 0) {
        int targetsTextWidth = (int)CalculateTextWidth(targetsText);
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
//+------------------------------------------------------------------+
//| P-PERF-38g (2026-09-29): ONE PRODUCED-LIST SWEEP FOR THE `LBL_`    |
//| NAMESPACE — the fix ClearAllLabels' own comment asked for.         |
//|                                                                    |
//| The bulk `ObjectsDeleteAll(prefix+"LBL_")` walked the WHOLE chart  |
//| object list on every label pass, so every label was deleted and    |
//| re-created on every pass: the 47 ms `clear=` in the relayout       |
//| ledger, and the blink the user sees on a timeframe switch.         |
//|                                                                    |
//| Shape: the pass OPENS a window at the clear site, every label      |
//| CREATOR records the name it just wrote (`LblMark`), and the window |
//| CLOSES after the last display call (`LblSweepEnd`). The sweep then  |
//| deletes exactly the names it wrote LAST pass and did not write now |
//| — the per-timeframe rows of the previous TF, and nothing else.     |
//|                                                                    |
//| Two fences, both deliberate:                              |
//|  * `LblMark` outside an open window is DROPPED, so a label built   |
//|    by a path that is not this pass can never enter either registry,|
//|    and is therefore never deleted by this sweep. The fence's own   |
//|    example used to be the level render's pip labels              |
//|    (`CreatePipDistanceLabel`, retired by P-LBL-12, 2026-10-17) —  |
//|    the guarantee is what mattered and it is unchanged.            |
//|  * a nested `LblSweepBegin` (a display function that clears on its |
//|    own way out) does NOT rotate again and does NOT drop the marks  |
//|    already made this pass.                                        |
//+------------------------------------------------------------------+
string s_lblProducedNow[];
string s_lblProducedPrev[];
int    s_lblNowN  = 0;
int    s_lblPrevN = 0;
bool   s_lblPassOpen = false;
// P-PERF-38g: the FIRST pass of an instance has no `prev` to diff against, so a
// stale per-TF label left by a previous attach (a crash, a chart whose switch
// never ran an OnDeinit) would survive forever. That one pass keeps the old
// bulk delete, at the SAME point in the pass it always ran (the window opener,
// before the displays), so the first frame is byte-identical to before and
// every later pass is the sweep.
bool   s_lblFirstPass = true;

void LblMark(const string name) {
    if(!s_lblPassOpen || StringLen(name) <= 0) return;
    for(int i = 0; i < s_lblNowN; i++) if(s_lblProducedNow[i] == name) return;
    int cap = ArraySize(s_lblProducedNow);
    if(s_lblNowN >= cap) ArrayResize(s_lblProducedNow, s_lblNowN + 16);
    s_lblProducedNow[s_lblNowN] = name;
    s_lblNowN++;
}

void LblSweepBegin(const string objectPrefix) {
    if(s_lblPassOpen) return;   // nested clear inside the same pass: keep the marks
    if(s_lblFirstPass) {
        s_lblFirstPass = false;
        ObjectsDeleteAll(0, objectPrefix + "LBL_");
    }
    s_lblPrevN = s_lblNowN;
    if(s_lblPrevN > ArraySize(s_lblProducedPrev)) ArrayResize(s_lblProducedPrev, s_lblPrevN);
    for(int i = 0; i < s_lblPrevN; i++) s_lblProducedPrev[i] = s_lblProducedNow[i];
    s_lblNowN = 0;
    s_lblPassOpen = true;
}

// Deletes the names written LAST pass that this pass did not write. A name that
// exists on the chart but was never produced by a pass is NOT this sweep's
// business (see the fence above), and a name this pass produced but that the
// chart does not hold yet costs one ObjectFind.
void LblSweepEnd(const string objectPrefix) {
    if(!s_lblPassOpen) return;
    s_lblPassOpen = false;
    string labelPrefix = objectPrefix + "LBL_";
    int deleted = 0;
    string deletedNames = "";
    for(int i = 0; i < s_lblPrevN; i++) {
        string nm = s_lblProducedPrev[i];
        if(StringFind(nm, labelPrefix) != 0) continue;
        bool producedNow = false;
        for(int j = 0; j < s_lblNowN; j++) {
            if(s_lblProducedNow[j] == nm) { producedNow = true; break; }
        }
        if(producedNow) continue;
        if(ObjectFind(0, nm) < 0) continue;
        // P-UI-21: a delete fires CHARTEVENT_OBJECT_DELETE, same suppression as
        // the clear it replaces, so a label sweep never flags a level redraw.
        g_suppressDeleteEvents = true;
        if(ObjectDelete(0, nm)) {
            deleted++;
            if(deleted <= 4) deletedNames = deletedNames + " " + nm;
        }
        g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
        g_suppressDeleteEvents = false;
    }
    s_lblPrevN = 0;
    if(deleted > 0) Print("[W][PERF] labels sweep: produced=", s_lblNowN, " deleted=", deleted, " of", deletedNames);
}

void ClearAllLabels(const string objectPrefix) {
    // P-UI-21: suppress window — every bulk below deletes inpObjectPrefix*
    // names, and unsuppressed each fires CHARTEVENT_OBJECT_DELETE ->
    // CacheRemoveObject + g_redrawTHLevelsNeeded (a label clear must never
    // flag a full level redraw).
    g_suppressDeleteEvents = true;
    // 1. P-PERF-38g: ARM THE SWEEP, DO NOT BULK DELETE.
    //
    // Was: `ObjectsDeleteAll(0, objectPrefix + "LBL_")` — a kernel walk of the
    // whole chart object list on EVERY label pass, which is why every label
    // blinked (deleted here, re-created by the displays below). The sweep that
    // replaces it deletes only what the LAST pass produced and THIS pass did
    // not, so a steady-state pass deletes nothing and a timeframe switch still
    // loses the previous TF's rows — the exact behaviour the bulk delete was
    // there for.
    LblSweepBegin(objectPrefix);

    // P-PERF-38f: THE LEGACY NAMESPACES ARE THE MIGRATION'S JOB, AND ITS ALONE.
    //
    // What follows deletes the `_LBL_` ghosts of the OLD
    // timeframe-in-the-name scheme. It used to run once per draw generation,
    // i.e. on EVERY timeframe switch — 11 ObjectsDeleteAll() calls, each a
    // kernel walk of the WHOLE chart object list, to clear names that
    // P-PERF-38 made uncreatable and that P-PERF-38c's one-time per-chart
    // migration already removes. The migration's prefix set is a SUPERSET of
    // this loop's ({M1,M5,M15,M30,H1,H4,D1,W1,MN,MN1,UNKNOWN} vs
    // {M1,M5,M15,M30,H1,H4,D1,W1,MN}, same base) and it runs at init, before the
    // first render — so on every chart this loop is either redundant or already
    // done.
    //
    // It is kept, not deleted, because it is the only thing that covers the
    // `inpObjectPrefix + "TF*"` spelling, which the migration does not; and it is
    // keyed on the SAME one-time stamp as the migration rather than on the
    // draw generation, so it costs one GlobalVariableCheck in steady state
    // instead of 11 full-chart walks per switch. Two owners of one migration is
    // how the two drift apart, so the stamp lives in GlobalVariables.
    //
    // M30 below is a CHART-TIMEFRAME namespace (a chart can sit on M30), NOT the
    // retired M30 ATR column — never drop it, or the `_M30_LBL_` ghosts of an
    // old chart survive every clear.
    if(!LegacyNameSchemeMigrated())
    {
        static string s_tfSuffixes[] = {"M1","M5","M15","M30","H1","H4","D1","W1","MN"};
        string basePrefix = inpObjectPrefix + "_";
        for(int j = 0; j < ArraySize(s_tfSuffixes); j++) {
            string tfLblPrefix = basePrefix + s_tfSuffixes[j];
            ObjectsDeleteAll(0, tfLblPrefix + "_LBL_");
        }

        // (b) Delete objectPrefix + "TF*" labels (legacy)
        ObjectsDeleteAll(0, objectPrefix + "TF");
    }
    g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
    g_suppressDeleteEvents = false;
}

// R-TRADEPLAN: trade-plan math lives ONLY in TradePlanFormulas.mqh.
// This file renders its values - never recompute coefficients here.

// P-UI-70d: the row's FONT is a parameter, exactly like `CreateTRexPiece`'s — the
// string this row is CENTRED on is measured at `L.fontSize`, so the size it is
// DRAWN at must come from the same owner (it used to call SetLabelFont(), the
// SHARED grid `inpFontSize`: measured at one size, painted at another).
bool CreateATRTradePiece(const string name, const string text, const color textColor,
                         const int fontSize, const int xPos, const int yPos) {
    LblMark(name);   // P-PERF-38g: produced by this pass, even if every write below is skipped
    if(ObjectFind(0, name) < 0) {
        if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;
    }
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    ObjectSetString(0, name, OBJPROP_FONT, inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, MathMax(4, fontSize));
    InitATRChartLabel(name, CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(8, xPos));
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(8, yPos));
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES,
                     IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    return true;
}


// The card's row text owners moved to Labels_Countdown.mqh — that file is the split owner
// for Labels_A's face strings (P-SIZE-SPLIT-LBL). The names below are unchanged.

//+------------------------------------------------------------------+
//| Bottom-right trade card geometry - ONE owner (P-LBL-06/07/08)    |
//| The card is THREE rows, bottom to top: the blue `#TP1..TP4` row,  |
//| the red `TRex / Trigger / Pricicle / Classic` row and the       |
//| `TR|ex` brand with its live-spread superscript. Every row's Y    |
//| AND X comes from here.                                           |
//|                                                                  |
//| Y: one PITCH between every pair, growing upward off the row that  |
//|    owns `inpLabelsMarginBottom` (2026-09-14 user: "why are these   |
//|    so far apart"). The first version stacked em+gap+rows*pitch,   |
//|    which left a DOUBLE gap under the Hunter row and a single one  |
//|    above it - a card where only one seam looks wrong.             |
//| X: every row is CENTRED on the widest row's axis (user: "TRex     |
//|    should be in the middle"), because all three pieces are        |
//|    ANCHOR_RIGHT_LOWER: x = rightEdge + (cardW - w)/2 puts every    |
//|    row's centre on `rightEdge + cardW/2`. Widths are MEASURED     |
//|    (PnlRawTextW over the raw-em owner), never guessed: the old    |
//|    brand pair placed `TR` at `2.0 * brandSize * 0.7` px, which is |
//|    ~2 px short of `ex` at 96 DPI and ~12 px short at 144 DPI - the |
//|    letters read as one blob (user: "why is TRex stuck together"). |
//| The row count is the INPUT (`inpTrexStampGapRows`), clamped twice: |
//| the user bound, then the chart's own height, so no input can park  |
//| the card off the top edge. The same three-input story owns the     |
//| card's HEIGHT off the floor: `inpLabelsMarginBottom` (its floor,    |
//| 8 px by default - 2026-09-14 user: "it sits too far from the        |
//| bottom"), the row count and the seam, each with its own named bound.|
//| Both clamps are named constants so the  |
//| audit can read them instead of trusting a comment.                |
//+------------------------------------------------------------------+
struct STrexCardLayout {
   bool showTP, showSL;           // which rows this pass actually DRAWS
   int yTrade, yHunter, yBrand;   // bottom distances (-1 = that row is not drawn)
   int xTrade, xHunter, xBrand;   // distances from the chart's RIGHT edge
   int xEx, xTR, xSp, ySp;        // the `TR|ex` pair + its spread superscript
   int xATR, yATR, atrSize;       // ATR superscript above the `TR` half + its font size
   int fontSize, brandSize;       // the two measured point sizes
   int cardW;                     // the width every drawn row is centred on
   int rows;                      // blank rows actually granted (after clamps)
};

void TRexTradeCardLayout(const STradePlan &plan, STrexCardLayout &L)
{
   // P-UI-70d: the card's OWN row font. `inpATRTradeLabelFontSize` is 0 by
   // default, which means "follow the shared grid size" — i.e. the shipped look
   // is byte-identical — and any positive value scales THIS CARD ONLY (the
   // label columns keep reading `inpFontSize`). The brand stays a fixed 6 pt
   // above the rows, so the card's proportion is preserved at every size.
   int fs = (inpATRTradeLabelFontSize > 0) ? inpATRTradeLabelFontSize : inpFontSize;
   if(fs < 1) fs = 1;                     // a 0/negative input has no em box
   int brandSize = fs + 6;
   int atrSize   = fs + 2;                // P-UI-148: ONE owner — the height budget below and the paint both read it
   int em      = PnlRawLineH(fs);        if(em < 1) em = 1;
   int brandEm = PnlRawLineH(brandSize); if(brandEm < 1) brandEm = 1;
   // The card's OWN seam (P-LBL-09): `inpATRTradeLabelRowGap` is the input that
   // names the ATR trade rows, and it used to be dead - the card read the
   // shared column `inpLabelRowGap`, so the corner card inherited the grid's
   // spacing and read as stretched. Clamped by hand: the input is applied raw
   // at init (an input of 0 or -5 must not collapse or invert the stack), and
   // the bound is named so the audit reads it instead of trusting this comment.
   int gap     = inpATRTradeLabelRowGap;
   if(gap < 0) gap = 0;
   if(gap > TREX_CARD_MAX_ROW_GAP) gap = TREX_CARD_MAX_ROW_GAP;
   int pitch   = em + gap;                // ONE pitch from the lowest row upward

   // WHICH rows this pass draws. These four names are the runtime copies (the
   // settings layer macro-redirects `inpShowATRTrade*` to `g_showATRTrade*`), so
   // the ATR card's TRADE PLAN ROWS switches move the card for real - and the
   // card must therefore reflow, not leave a hole (P-LBL-09).
   bool want = inpShowATRTradeLabels;
   L.showTP = (want && inpShowATRTradeTPLabels);
   L.showSL = (want && inpShowATRTradeSLLabels);

   // Measured widths (the drawn strings come from the same two owners). Only the
   // rows that are DRAWN take part: hiding the wide `#SL/TP` row must re-centre
   // the remaining ones, not keep the card on an axis nothing occupies.
   int wTR     = PnlRawTextW("TR", brandSize);
   int wEx     = PnlRawTextW("ex", brandSize);
   int wBrand  = wTR + wEx;
   int wHunter = PnlRawTextW(TradePlanLegsText(plan), fs);
   int wTP     = PnlRawTextW(TradePlanTPRowText(plan), fs);
   int cardW = MathMax(wBrand, MathMax(L.showTP ? wTP : 0, L.showSL ? wHunter : 0));
   //--- P-UI-187 (2026-10-20): the card had a HEIGHT budget and no WIDTH budget.
   //--- The card grows LEFT from the chart's right edge and the leg row grew
   //--- (P-TP4: 47 characters - ~230px at 8pt/96dpi), so on a narrow chart it ran
   //--- off the chart's left side. The chart's own box is the budget now, and a row
   //--- that does not fit is DROPPED - never clipped: half a number is a wrong one.
   int rightEdge = MathMax(8, inpLabelsMarginLeft);
   int chartW = GetCachedChartWidth();
   int availW = (chartW > 0) ? MathMax(60, chartW - rightEdge - 8) : 0;
   if(availW > 0)
   {
      if(L.showSL && wHunter > availW) L.showSL = false;
      if(L.showTP && wTP > availW) L.showTP = false;
      wHunter = L.showSL ? wHunter : 0;
      wTP = L.showTP ? wTP : 0;
      cardW = MathMax(wBrand, MathMax(wTP, wHunter));
   }
   if(cardW < 1) cardW = 1;

   int rows = inpTrexStampGapRows;
   if(rows < 0) rows = 0;                        // a negative count would collide
   if(rows > TREX_CARD_MAX_GAP_ROWS) rows = TREX_CARD_MAX_GAP_ROWS;
   // The card's distance from the chart's BOTTOM edge: its OWN input
   // (`inpLabelsMarginBottom`, group 13 - the label columns use
   // `inpTHLabelsMarginBottom`, so this one is the card's alone). Clamped by
   // hand because the input is applied raw at init: 0 or -5 would push the rows
   // through the floor, and a mistyped 5000 would park the card mid-screen.
   int bottom = LabelFloorMargin();
   // The card is 1 (brand) + 0..2 (the two optional rows) tall, so the height
   // budget counts exactly what is drawn: rows <= room/pitch - (drawn - 1).
   // P-UI-148: the card's TOP is the superscript line, not the wordmark — reserve
   // what is really drawn (the raised line is the part that reaches the ceiling).
   int cardTop = brandEm + TREX_BRAND_GAP_SUPER_TOP + PnlRawLineH(atrSize);
   int drawn = 1 + (L.showTP ? 1 : 0) + (L.showSL ? 1 : 0);
   int chartH = GetCachedChartHeight();          // 100 ms cache; <= 0 = unknown
   if(chartH > 0)
   {
      int maxRows = (chartH - TREX_CARD_TOP_PAD - cardTop - bottom) / pitch - (drawn - 1);
      if(maxRows < 0) maxRows = 0;
      if(rows > maxRows) rows = maxRows;
   }

   // PACKED, never fixed slots (P-LBL-09, user: "when one is switched off the
   // others must take its place, so the structure does not break"): the lowest
   // DRAWN row sits on the bottom margin (plus the requested blank rows) and
   // every drawn row above it is exactly one pitch higher. A hidden row does not
   // reserve its slot, so the card below it slides down into that place instead
   // of leaving a hole above the chart's floor.
   int y = bottom + rows * pitch;
   L.yTrade  = -1;
   L.yHunter = -1;
   if(L.showTP) { L.yTrade  = y; y += pitch; }
   if(L.showSL) { L.yHunter = y; y += pitch; }
   L.yBrand = y;                            // the brand is the card's top row

   L.fontSize  = fs;
   L.brandSize = brandSize;
   L.rows      = rows;
   L.cardW     = cardW;

   L.xTrade  = rightEdge + (cardW - wTP) / 2;
   L.xHunter = rightEdge + (cardW - wHunter) / 2;
   L.xBrand  = rightEdge + (cardW - wBrand) / 2;
   L.xEx     = L.xBrand;                 // the pair's right end is the row's edge
   L.xTR     = L.xEx + wEx;              // measured: exactly 0 px of overlap
   // P-UI-147: the superscripts get AIR (live user: «این وسطش خلی چسبیده یکم از
   // هم فاصله بگیره»). The spread clears `TR` by a named gap; the ATR clears the
   // wordmark's right edge by a named gap instead of riding 6 px inside the
   // `ex` box. Both gaps are named in ConstantsAndEnums.mqh — the numbers now
   // read as pieces over the wordmark, and the wordmark keeps its own 0 px.
   L.xSp     = L.xTR + wTR + TREX_BRAND_GAP_SPREAD;   // spread moves to the left of `TR`
   // P-UI-147/148 (2026-10-13): the brand band's own AIR, both axes (the live user
   // pointed at it twice). The two superscripts clear the wordmark by named gaps
   // (ConstantsAndEnums) and the line stands TREX_BRAND_GAP_SUPER_TOP above the
   // wordmark's box - it used to sit 4 px INSIDE it, which was the glue.
   L.ySp     = L.yBrand + brandEm + TREX_BRAND_GAP_SUPER_TOP;
   L.atrSize = atrSize;                 // ATR superscript: 2 pt above the row font, below brandSize
   L.xATR    = L.xEx - TREX_BRAND_GAP_ATR;            // ATR clears the wordmark's right edge
   L.yATR    = L.ySp;                    // same cap-line height as the spread
   // BKCORNER-ON (2026-10-20): the base note no longer rides this column — its slot is the
   // family's top-left, pushed by LabelPushBaseNoteSlotTop. The old bottom-right push is
   // retired here (the function is kept as the one-line restore).
}

bool CreateATRTradeLabel(const string objectPrefix, const STradePlan &plan,
                         const STrexCardLayout &L)
{
   // Bottom-right card (R-TRADEPLAN): the blue row
   //   #TP1+<t1>  #TP2+<t2>  #TP3+<t3>  #TP4+<t4>
   // is the BOTTOM of the card whose geometry TRexTradeCardLayout owns.
   // The old top row of this block (`Close in : <countdown>`, red) now rides
   // the LIVE PRICE instead (CreateLivePriceCountdown, 2026-09-11 user
   // request). Same object name, so visibility + cleanup wiring is unchanged.
   string tpName = objectPrefix + "ATR_Trade_Current_TPRow";

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

   if(L.showTP) {
       if(!CreateATRTradePiece(tpName, TradePlanTPRowText(plan), inpATRTradeRowColor, L.fontSize, L.xTrade, L.yTrade)) return false;
   }
   else {
       // PRESENCE == THE SWITCH (P-LBL-09). The relayout path wipes LBL_ before
       // this runs, but the 2 s live pump does not: without this delete a row
       // switched off mid-session keeps drawing at the Y the PACKED stack no
       // longer reserves for it - the "structure broke" report.
       ObjectDelete(0, tpName);
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
bool DisplayTradePlanTopRows(const string labelPrefix, const STradePlan &plan,
                             const STrexCardLayout &L)
{
   // ONE owner for this row's POSITION and its PRESENCE (P-LBL-09): the caller
   // computed the card once, so a row switched off is never placed - and the
   // object is removed here rather than at the call site, so no caller can
   // forget the off-case and leave the row hanging over the chart.
   if(!L.showSL) {
      ObjectDelete(0, labelPrefix + "TREX_Hunter");
      ObjectDelete(0, labelPrefix + "TREX_StrBond");
      return true;
   }
   if(!CreateTRexPiece(labelPrefix + "TREX_Hunter", TradePlanLegsText(plan),
                       inpATRTradeHunterColor, L.fontSize, L.xHunter, L.yHunter)) return false;
   return true;
}

//+------------------------------------------------------------------+
//| TRex brand piece: `TR` (blue) + `ex` (red) + the pair's LIVE     |
//| structure-TF fill superscript (live structure bar range, pips).   |
//| The small number is the structure bar's fill - never a version and |
//| never a TH value (the v0.5 daily-TH row is retired in 3.x; the   |
//| green Persian caption row was retired 2026-09-14, P-LBL-06).     |
//| Both pieces are the TOP of the bottom-right trade card            |
//| (P-LBL-07/08): their Y AND X come from TRexTradeCardLayout(), the  |
//| ONE owner of that geometry - never re-derived here.                |
//+------------------------------------------------------------------+
bool CreateTRexPiece(const string name, const string text, const color textColor,
                     const int fontSize, const int xPos, const int yPos,
                     const string fontName = "") {
    LblMark(name);   // P-PERF-38g: produced by this pass
    if(ObjectFind(0, name) < 0) {
        if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;
    }
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
    // Empty fontName = default indicator font (inpFontName). A piece that
    // needs a non-Latin family must pass it explicitly: "Arial Bold" is not a
    // real family name, so MT4 would fall back to a font with no Arabic
    // coverage (P-LBL-02). Nothing on the chart needs that any more - the
    // caption that did is retired (P-LBL-06) - but the knob stays for the
    // next non-ASCII row instead of being silently re-derived.
    ObjectSetString(0, name, OBJPROP_FONT,
                    StringLen(fontName) > 0 ? fontName : inpFontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    // Bottom-right, like CreateATRTradePiece (P-LBL-07): the stamp stacks
    // ABOVE the trade row off one shared anchor and can never overlap it.
    InitATRChartLabel(name, CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, MathMax(8, xPos));
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, MathMax(8, yPos));
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES,
                     IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    return true;
}

// P-PERF-53: last painted title-block state. DisplayTRexTitleBlock compares
// first: a still 2 s pass (same fill, same inks, same seats) costs reads
// only instead of 27 same-value writes.
static string s_trxPrefix = "";
static string s_trxSpText = "";
static string s_trxATRText = "";
static color s_trxTR = clrNONE, s_trxEX = clrNONE, s_trxSP = clrNONE;
static int s_trxFS = -1, s_trxBS = -1;
static int s_trxXSp = 0, s_trxYSp = 0, s_trxXTR = 0, s_trxXEx = 0, s_trxYBrand = 0;
static int s_trxXATR = 0, s_trxYATR = 0, s_trxATRSize = -1;
static bool s_trxInit = false;
bool DisplayTRexTitleBlock(const string labelPrefix, const STrexCardLayout &L,
                           const int structureMinutes) {
    string spName  = labelPrefix + "TREX_Spread";
    string capName = labelPrefix + "TREX_Caption";   // RETIRED (P-LBL-06) - purge only
    string trName  = labelPrefix + "TREX_TR";
    string exName  = labelPrefix + "TREX_EX";
    string atrName = labelPrefix + "TREX_ATR";
    // P-PERF-38g: MARKED BEFORE THE P-PERF-53 CLEAN-SKIP BELOW, on purpose.
    //
    // The skip is the whole point of P-PERF-53 (a still 2 s pass costs reads),
    // so it returns TRUE without calling a single CreateTRexPiece — and a mark
    // placed at the create call would then count those three names as "not
    // produced this pass" and the sweep would DELETE them, recreate them next
    // pass, and delete them again: a permanent 3-object flicker at the exact
    // triple this card owns (measured live: `labels sweep: produced=3
    // deleted=3` once a second). A clean-skip PASS IS A PASS THAT OWNS THE
    // NAMES — it decided the objects are already correct. That decision is
    // where ownership is recorded, never the write.
    LblMark(spName);
    LblMark(trName);
    LblMark(exName);
    LblMark(atrName);

    // P-LBL-06 (2026-09-14, user request: "that Persian text should go"): the
    // green Persian caption row is RETIRED from the chart. The name is still
    // purged so a chart painted by an older build loses it for good, but only
    // ONCE per chart family: this function also runs from the 2 s live pump,
    // and an unconditional ObjectDelete would be a kernel call every 2 s for
    // an object that can only ever exist on the first pass.
    static string s_trexCapPurged = "";
    if(s_trexCapPurged != labelPrefix) {
        s_trexCapPurged = labelPrefix;
        ObjectDelete(0, capName);
    }

    if(IsIndicatorHidden()) {
        ObjectSetInteger(0, spName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, trName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, exName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        ObjectSetInteger(0, atrName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        return true;
    }

    // Superscript = live STRUCTURE-TF range in pips + % of current-TF ATR ("260.0 (85.3%)").
    // The structure TF is the one THIS CARD's plan is built on (P-TP4-RUNG, one rung
    // up: M5->M15, M15->H1, H1->H4) and the range is that TF's LIVE (forming) bar,
    // shift 0. GetStructureTimeframe() is the 16x/4-rung basis and is NOT this card's
    // structure: on M5 it read H4 and printed 129.2p (H4) / 400.9% where the card's
    // M15 was the structure. TREX_Spread is legacy.
    string spText = "--";
    double pip = GetCachedPipSize();
    double atrVal = GetATRForTimeframe(Period());
    if(!IsZero(pip, EPSILON_PRICE)) {
        ENUM_TIMEFRAMES stf = CompatTF(structureMinutes);
        double hi = iHigh(NULL, stf, 0), lo = iLow(NULL, stf, 0), rng = hi - lo;
        if(hi > 0 && lo > 0 && hi >= lo)
            spText = DoubleToString(rng / pip, 1) + (atrVal > 0.0 && atrVal != EMPTY_VALUE ? " (" + DoubleToString(rng / atrVal * 100.0, 1) + "%)" : "");
    }
    // ATR superscript above `TR`: current-TF weighted ATR in pips, 1 decimal.
    string atrText = "--";
    if(!IsZero(pip, EPSILON_PRICE)) {
        if(atrVal > 0 && atrVal != EMPTY_VALUE)
            atrText = DoubleToString(NormalizeDouble(atrVal / pip, 1), 1);
    }
    // Every position below comes from the ONE card owner (computed once per pass
    // by the caller): it knows the row pitch, the centring axis and the MEASURED
    // width of `ex` - the piece order here (`sp`, `TR`, `ex`) is the only thing
    // this function still decides.
    if(s_trxInit && s_trxPrefix == labelPrefix
       && s_trxSpText == spText && s_trxATRText == atrText
       && s_trxTR == inpATRTradeTRColor && s_trxEX == inpATRTradeExColor && s_trxSP == inpATRTradeSpreadColor
       && s_trxFS == L.fontSize && s_trxBS == L.brandSize
       && s_trxXSp == L.xSp && s_trxYSp == L.ySp
       && s_trxXTR == L.xTR && s_trxXEx == L.xEx && s_trxYBrand == L.yBrand
       && s_trxXATR == L.xATR && s_trxYATR == L.yATR && s_trxATRSize == L.atrSize
       && ObjectFind(0, spName) >= 0 && ObjectFind(0, trName) >= 0 && ObjectFind(0, exName) >= 0
       && ObjectFind(0, atrName) >= 0)
       return true;
    s_trxInit = true;
    s_trxPrefix = labelPrefix; s_trxSpText = spText; s_trxATRText = atrText;
    s_trxTR = inpATRTradeTRColor; s_trxEX = inpATRTradeExColor; s_trxSP = inpATRTradeSpreadColor;
    s_trxFS = L.fontSize; s_trxBS = L.brandSize;
    s_trxXSp = L.xSp; s_trxYSp = L.ySp; s_trxXTR = L.xTR; s_trxXEx = L.xEx; s_trxYBrand = L.yBrand;
    s_trxXATR = L.xATR; s_trxYATR = L.yATR; s_trxATRSize = L.atrSize;
    // P-UI-70d: every colour of this card is a setting now (the ATR card's CARD
    // COLORS row / the group-13 inputs), so the five literals that used to live
    // here are gone: they are the ONE reason "personalise the TRex SL/TP" was
    // impossible. Defaults are the same five values, so the shipped look is
    // unchanged; a pick reaches the chart through the label relayout
    // (PaletteApplyColor sets g_labelsRelayoutNeeded).
    if(!CreateTRexPiece(spName, spText, inpATRTradeSpreadColor, L.fontSize, L.xSp, L.ySp)) return false;
    // The caption piece (and its one-shot Tahoma/P-LBL-02 diagnostic) is gone
    // with the row: non-ASCII charter text must still be built from ushort codes,
    // but nothing on the chart needs an Arabic-capable family any more - every
    // remaining piece is pure ASCII and rides the default indicator font.
    if(!CreateTRexPiece(trName, "TR", inpATRTradeTRColor, L.brandSize, L.xTR, L.yBrand)) return false;
    if(!CreateTRexPiece(exName, "ex", inpATRTradeExColor, L.brandSize, L.xEx, L.yBrand)) return false;
    if(!CreateTRexPiece(atrName, atrText, inpATRTradeSpreadColor, L.atrSize, L.xATR, L.yATR)) return false;
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
    // Column colors are the shared STANDARD_COLORS owner (same TF order).
    int tfMinutes[] = {1, 5, 15, 60, 240, 1440, 10080, 43200};
    
    bool isVerticalLayout = (inpLabelArrangement == LABEL_ARRANGEMENT_VERTICAL);
    int rowSpacing = inpLabelRowGap;
    int horizontalPadding = inpLabelColumnGap;
    int startXPos = inpLabelsMarginLeft;
    int lineGap = rowSpacing;
    int singleLineHeight = inpFontSize + lineGap;
    // P-UI-43 (2026-09-13, "the ATR labels drifted away from the ceiling"): the ATR block is the
    // ONLY top-side section of a pass, so it OPENS the top side and therefore owns
    // `inpLabelsMarginTop`. The position used to be `margin + g_currentLabelYOffset`,
    // i.e. it trusted the stacking state a previous pass left behind - and with a
    // stale offset the whole block landed one section-slot lower (3 rows x
    // (fontSize + rowGap) + inpSectionGap = 108px at the defaults), which reads as
    // "the ATR labels drifted away from the ceiling". Nothing below loses its place:
    // the increment at the end of this function still feeds every later top-side
    // consumer (`g_modeLabelYOffset` -> the overlay labels). Cost: one int write.
    g_currentLabelYOffset = 0;
    int titleYPos = inpLabelsMarginTop + g_currentLabelYOffset;
    int startYPos = isVerticalLayout ? (titleYPos + singleLineHeight) : titleYPos;
    int sectionGap = inpSectionGap;
    
    string titleObjName = labelPrefix + "ATR_Title";
    LblMark(titleObjName);   // P-PERF-38g
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
    int maxWidth = LabelRowMaxWidth(startXPos);   // P-UI-94: one owner, never negative
    int lineHeight = GetLabelLineHeight(inpShowATRTargets, rowSpacing);
    
    int renderedCount = 0;
    for(int i = 0; i < ArraySize(timeframes); i++) {
        double atrValue = GetATRForTimeframe(tfMinutes[i]);
        if(atrValue <= 0 || atrValue == EMPTY_VALUE) continue;
        
        double atrPoints = atrValue / point;
        double atrPips = NormalizeDouble(atrValue / pipSize, 1);
        color labelColor = STANDARD_COLORS[i];
    
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
            if(maxWidth > 0 && currentXPos + labelWidth + xStep > maxWidth) {   // P-UI-94
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
    // P-UI-84 (2026-09-14, user: «این trex sl , tp جدا از atr خاموش و روشن بشه
    // الان atr روش تاثیر میزاره»): THE CARD ANSWERS TO ITS OWN MASTER AND TO
    // NOTHING ELSE. Until this row every gate that decided the card ALSO ANDed
    // `g_atrLabelsVisible` — the ATR OVERVIEW switch (the ring's `ATR` tile, the
    // label card's `ATR LABELS` row 4, the A hotkey) — so switching the per-TF
    // ATR columns off took the whole trade plan with them, and the two read as
    // one control in all but name. The card is a TRADE PLAN (brand + Hunter SL
    // row + #SL/#TP row); its own switches (`inpShowATRTradeLabels` and the two
    // row flags below, the label card's TRADE PLAN ROWS band) are the ONLY thing
    // that may remove it. The ATR overview gate stays where it belongs: inside
    // DisplayATRLabels, over the ATR columns it actually owns.
    // BKCORNER-ON (2026-10-20): the base note's slot is the family's top-left, pushed by
    // LabelPushBaseNoteSlotTop — this column no longer owns it.
    if(!inpShowATRTradeLabels) {
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
        ObjectDelete(0, labelPrefix + "TREX_ATR");
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

    // ONE card layout per pass (P-LBL-09): the margins, the row pitch, the
    // drawn-row set and the centring axis are read inside the owner, and all
    // three writers below only PLACE what it laid out. That is also the whole
    // cost story: the layout is measured twice per pass at most (this path and
    // the live pump), never once per row and never per tick.
    STrexCardLayout L;
    TRexTradeCardLayout(plan, L);
    CreateATRTradeLabel(labelPrefix, plan, L);
    DisplayTRexTitleBlock(labelPrefix, L, plan.strMin);
    DisplayTradePlanTopRows(labelPrefix, plan, L);
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

//+------------------------------------------------------------------+
//| P-TP4-WITNESS (2026-10-19) — ONE witness line per chart bar      |
//|                                                                  |
//| Why this exists: every comparison in this session stalled on     |
//| reading a 12-pixel card out of a screenshot, and a card is not   |
//| evidence we can compute with. This writes the plan's EXACT       |
//| numbers to the per-symbol auto file the moment a new chart bar   |
//| opens, so the card never has to be read by eye again.            |
//|                                                                  |
//| Cost: one FileOpen + a few lines + FileClose per chart BAR, not  |
//| per tick, not per 2 s pass. No Print — P-LOG-01 keeps the label  |
//| pump silent, and this path stays silent too; the file is the     |
//| only sink. FILE_WRITE truncates by design (P-LOG-02: the file    |
//| always holds the LATEST dump of that symbol).                    |
//|                                                                  |
//| P-TP4-WITNESS-FILE: its OWN file, not tradeplan-auto-<SYM>.log.  |
//| That one is the on-demand X dump and it truncates on open, so    |
//| sharing a name meant the next bar silently ate a dump the user   |
//| had just asked for. Two sinks, two files, neither clobbers the   |
//| other.                                                           |
//+------------------------------------------------------------------+
datetime s_tpWitnessBar = 0;

string TradePlanWitnessFileName()
{
    return("tradeplan-witness-" + Symbol() + ".log");
}

void TradePlanWitness(const STradePlan &plan)
{
    if(!plan.valid) return;
    datetime bar0 = iTime(Symbol(), Period(), 0);
    if(bar0 == 0 || bar0 == s_tpWitnessBar) return;   // one line set per bar
    s_tpWitnessBar = bar0;

    int h = FileOpen(TradePlanWitnessFileName(), FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(h == INVALID_HANDLE) return;

    FileWriteString(h, "P-TP4-WITNESS  build " + TH3_SRC_SHORT +
                       "  compiled " +
                       TimeToString(__DATETIME__, TIME_DATE | TIME_MINUTES) + "\r\n");
    FileWriteString(h, StringFormat("symbol=%s tf=%s bar0=%s  chartMin=%d strMin=%d\r\n",
                                    Symbol(), GetCurrentTimeframe(),
                                    TimeToString(bar0, TIME_DATE | TIME_MINUTES),
                                    plan.chartMin, plan.strMin));
    FileWriteString(h, StringFormat("ATR own=%.4f str=%.4f  (pips; Eng = own/%.6f)\r\n",
                                    plan.ownPips, plan.basePips, TRADEPLAN_ENG_DIVISOR));
    FileWriteString(h, StringFormat("engTrue=%.6f eng=%.1f hunter=%.1f pricicle=%d classic=%d\r\n",
                                    plan.engTrue, plan.eng, plan.hunter,
                                    plan.pricicle, plan.classic));
    FileWriteString(h, StringFormat("slTrue=%.6f sl=%d tp1=%d tp2=%d tp3=%d tp4=%d sb1=%d sb2=%d\r\n",
                                    plan.slTrue, plan.sl, plan.tp1, plan.tp2,
                                    plan.tp3, plan.tp4, plan.sb1, plan.sb2));
    FileClose(h);
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
        // P-PERF-05: the s-legs ride the bulk-copy engine (ONE CopyHigh/Low/Close
        // per timeframe instead of ~4 series calls per bar x 425 bars x 9
        // timeframes). Identical numbers - the diagnostic just stops costing
        // more than the thing it measures.
        double sLegs[];
        TrexSMALegsBatch(tf, qpers, sLegs);
        for(int g = 0; g < 10; g++)
        {
            double u = (g < ArraySize(sLegs)) ? sLegs[g] : 0.0;
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
              + " | " + DoubleToString(p.eng, 1)
              + " | " + DoubleToString(p.hunter, 1)
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
          + "  TRex=" + DoubleToString(plan.eng, 1)
          + "  Trigger=" + DoubleToString(plan.hunter, 1)
          + "  Pricicle=" + IntegerToString(plan.pricicle)
          + "  Classic=" + IntegerToString(plan.classic));
    TpxLine("[TRADEPLAN]   SL=" + IntegerToString(plan.sl)
          + "  TP1=" + IntegerToString(plan.tp1)
          + "  TP2=" + IntegerToString(plan.tp2)
          + "  TP3=" + IntegerToString(plan.tp3)
          + "  TP4=" + IntegerToString(plan.tp4));
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
    // P-TP4-STAMP: which binary wrote this file. Without it a dump can be read
    // against the wrong build and every conclusion drawn from it is worthless -
    // that is exactly what happened on NZDUSD (a correct 22:12 card was judged
    // against source edited afterwards). TH3_SRC_SHORT is generated by
    // tools/gen-build-hash.js over every .mq4/.mqh, so a mismatch here means the
    // terminal is still running an older .ex4 and needs a chart re-attach.
    TpxLine("[DUMP] build " + TH3_SRC_SHORT + "  files=" + IntegerToString(TH3_SRC_FILES)
            + "  " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)
            + "  broker-time");

    // Rounding-integrity guard (TradePlanSelfCheck) — the engine computes and
    // displays on the SAME doubles, so this only fires on a real formula/wiring
    // regression. Skipped under the alt formulas: their Hunter leg is TR/1.66666
    // by design and does not satisfy the 8/3×Eng identity.
    if(!inpUseAltTradeFormulas)
    {
        if(TradePlanSelfCheck(plan))
            TpxLine("[SELFCHECK] OK  - every displayed leg on its engine value (SL/TP/SB to half a pip, Eng/Hunter to half of their 0.1)");
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
      if(s_cdDirty) ThrottledChartRedraw();
   }

    // P-UI-84: the card's OWN master, never the ATR overview (see
    // DisplayATRTradeLabels). `IsIndicatorHidden()` stays — the F-hide must
    // still park this pump with the rest of the chart.
    if(!inpShowATRTradeLabels || IsIndicatorHidden()) return;
    static uint s_lastMs = 0;
    if(nowMs - s_lastMs < 2000) return;
    s_lastMs = nowMs;
    // P-PERF-50: the prefix string was built on EVERY tick+timer call and then
    // thrown away by the 2 s gate above — same "string before the gate" waste
    // as the per-event ledger. Built here, it runs once per 2 s pass.
    string labelPrefix = GetLevelObjectPrefix() + "LBL_";
    STradePlan plan;
    if(!TradePlanComputeLive(Period(), plan)) return;
    // P-TP4-WITNESS: exact numbers to the per-symbol file, once per chart bar.
    TradePlanWitness(plan);
    // ONE card layout for BOTH branches below (P-LBL-09): the drawn-row set and
    // the measured centring axis do not depend on which branch runs, so the
    // steady state costs exactly the same 4 text measurements as the full pass
    // and nothing more. Never compute it per row and never per tick.
    STrexCardLayout L;
    TRexTradeCardLayout(plan, L);
    // Display only — this path NEVER prints (user decision 2026-09-10: logs
    // only on demand via the X hotkey). The numeric sig still picks the full
    // vs cheap in-place label path; pixels identical either way.
    // %.1f on the two 0.1-pip legs: a change that only moves a decimal (0.3 -> 0.4)
    // MUST re-key the signature, or the card would keep the previous number.
    // P-TP4: TP4 / Pricicle / Classic ride it too — a leg the signature does not
    // carry is a leg the card never repaints.
    string sig = StringFormat("%d|%d|%d|%d|%d|%.1f|%.1f|%d|%d|%d|%d",
                              plan.sl, plan.tp1, plan.tp2, plan.tp3, plan.tp4,
                              plan.hunter, plan.eng, plan.sb1, plan.sb2,
                              plan.pricicle, plan.classic);
    static string s_sig = "";
    if(sig != s_sig)
    {
       s_sig = sig;

    // Auto-log OUR numbers (user decision 2026-09-10: our log flows on its
    // own, change-guarded + throttled — the professor's side arrives via
    // screenshots and is paired offline by timestamp).
    // P-PERF-48 / P-LOG-01 (2026-09-16): THIS BLOCK NOW OBEYS THE LOG LEVEL.
    //
    // It used to run unconditionally, here, on the label pump. The cost is not
    // hypothetical and it is measured: over one day the live MT5 interaction
    // ledger put the LABEL phase at avg 22.7 ms / MAX 625 ms per frame against
    // levels 10.3/94 and overlay 4.3/78 - labels are the dominant term of the
    // whole OnCalculate budget, and inside their pump sat (a) a FileOpen with
    // FILE_WRITE - which TRUNCATES MQL5/Files/tradeplan-auto-<symbol>.log, so
    // "paired offline by timestamp" was never actually possible - (b) four
    // Print lines, and (c) every 3 s the full 8-TF snapshot: 12 more lines and
    // ~250 number->string conversions, on the thread that owns the pixels.
    //
    // The block 30 lines above already declares this path "Display only - this
    // path NEVER prints (user decision 2026-09-10: logs only on demand via the
    // X hotkey)". Two comments, two answers; the code now agrees with that one.
    //
    // NOTHING IS LOST. The identical dump is one hotkey away (X ->
    // TradePlanDumpNow, which emits [DUMP]+row+snapshot+legs atomically), and
    // raising inpLogLevel to DEBUG/INFO brings this auto log straight back for
    // offline pairing. The gate is the same runtime check the logger macros use,
    // so there is exactly one rule for "may a hot path print" in the project.
    if(g_runtimeLogLevel <= LOG_LEVEL_INFO)
    {
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
    } // end log-level gate (P-LOG-01)

    CreateATRTradeLabel(labelPrefix, plan, L);
    DisplayTRexTitleBlock(labelPrefix, L, plan.strMin);
    DisplayTradePlanTopRows(labelPrefix, plan, L);
    } // numeric change: full block above
    else
    {
       // Steady state: numerics frozen — only the 1-second countdown and the
       // live structure-fill superscript are refreshed. All three writers upsert in place, so an
       // unchanged row costs a compare and no write; the Hunter writer runs here
       // too because it owns its row's EXISTENCE - a switch flipped while the
       // numbers were frozen must still remove the row (P-LBL-09).
       CreateATRTradeLabel(labelPrefix, plan, L);
       DisplayTRexTitleBlock(labelPrefix, L, plan.strMin);
       DisplayTradePlanTopRows(labelPrefix, plan, L);
    }
    ThrottledChartRedraw();
}

#endif // LABELS_A_MQH

