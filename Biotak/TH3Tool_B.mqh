// TH3Tool_B.mqh - TH3Tool.mqh split 2026-09-29: exact lines 1353-2798, byte-identical, zero renames.
#ifndef TH3_TOOL_B_MQH
#define TH3_TOOL_B_MQH

//+------------------------------------------------------------------+
//| Auto-Select Best Frequency for Current AB=CD Pattern            |
//|                     AB=CD                  |
//+------------------------------------------------------------------+
bool AutoSelectBestFrequency(string patternName)
{
    //          A  B  C     
    string lineAB = patternName + "_Line_AB";
    string lineBC = patternName + "_Line_BC";
    
    if(ObjectFind(0, lineAB) < 0 || ObjectFind(0, lineBC) < 0) {
        Print("==================== Pattern not found: ", patternName);
        return false;
    }
    
    datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
    double pA = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 0);
    datetime tB = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 1);
    double pB = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 1);
    datetime tC = (datetime)ObjectGetInteger(0, lineBC, OBJPROP_TIME, 1);
    double pC = ObjectGetDouble(0, lineBC, OBJPROP_PRICE, 1);
    
    // CRITICAL FIX: Validate all retrieved values
    if(tA <= 0 || tB <= 0 || tC <= 0 || pA <= 0 || pB <= 0 || pC <= 0) {
        Print("==================== Invalid pattern data");
        return false;
    }
    
    // For auto-select, we don't have X point stored in pattern
    // Estimate X based on typical wave pattern structure
    //               X           
    //    X                  
    
    //             AB
    int barA = iBarShift(NULL, 0, tA);
    int barB = iBarShift(NULL, 0, tB);
    int AB_Bars = barA - barB; // A     B  
    if(AB_Bars < 1) AB_Bars = 1;
    
    //       X:           A (          
    int barX = barA + AB_Bars; // X     A
    datetime tX = iTime(NULL, 0, barX);
    
    //       
    if(tX <= 0 || tX >= tA) {
        // fallback:           AB
        tX = tA - (tB - tA);
        if(tX <= 0) tX = tA - 3600; //   1    
    }
    
    //      X          
    //       AB=CD     X    A       B    D      
    bool isABBullish = (pB > pA);
    double AB_Distance = MathAbs(pB - pA);
    double pX;
    
    if(isABBullish) {
        //   AB       (A          
        //   XA           (X           )
        //     X     A  
        pX = pA + (AB_Distance * 0.618); //   XA     61.8%   AB (Fibonacci)
    } else {
        //   AB         (A           )
        //   XA         (X          
        //     X       A  
        pX = pA - (AB_Distance * 0.618); //   XA     61.8%   AB
    }
    
    //       X                  
    if(pX <= 0) {
        if(isABBullish) {
            pX = pA + (AB_Distance * 0.5); // fallback: 50%   AB
        } else {
            pX = pA - (AB_Distance * 0.5);
        }
    }
    
    //                 A      (    
    if(pX <= 0) pX = pA;
    
    //            (  4    
    //   X             A     3          
    FrequencySearchResult results[];
    ArrayResize(results, 0); // Initialize array
    
    bool hasValidX = (MathAbs(pX - pA) > MathAbs(pB - pA) * 0.1); // X     10% AB   A      
    
    int resultCount;
    if(hasValidX) {
        //       4    
        resultCount = FindOptimalFrequencyForABCD(tX, pX, tA, pA, tB, pB, tC, pC, results, 5.0);
    } else {
        //          X (      AB    BC)
        //        X = A        pattern quality      
        resultCount = FindOptimalFrequencyForABCD(tA, pA, tA, pA, tB, pB, tC, pC, results, 5.0);
        
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== X point estimation not reliable, using simplified analysis");
        #endif
    }
    
    if(resultCount == 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== No suitable frequency found (error > 5%)");
        #endif
        return false;
    }
    
    //              
    double pipSize = GetCachedPipSize();
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    Print("==================== FREQUENCY SEARCH RESULTS");
    Print("Pattern: ", patternName);
    Print("AB Distance: ", DoubleToString(MathAbs(pB - pA), Digits), " (", 
          DoubleToString(MathAbs(pB - pA) / pipSize, 1), " pips)");
    Print("========================================");
    Print("==================== BEST MATCH:");
    Print("   Frequency: ", DoubleToString(results[0].frequency, 3), "% (Index: ", results[0].frequencyIndex, ")");
    Print("   Target: Step ", results[0].targetStep, " | Error: ", DoubleToString(results[0].errorPercent, 3), "% (", DoubleToString(results[0].errorPips, 1), " pips)");
    Print("   Speed: ", DoubleToString(results[0].gannAngle, 2), "x | Consistency: ", DoubleToString(results[0].angleWeight * 100, 1), "%");
    Print("   Time Symmetry: ", DoubleToString(results[0].timeSymmetry * 100, 1), "% | Total Score: ", DoubleToString(results[0].totalScore, 2));
    Print("========================================");
    Print("==================== TOP 10 ALTERNATIVES:");
    #endif
    
    int displayCount = MathMin(10, resultCount);
    for(int i = 0; i < displayCount; i++)
    {
        #ifdef ENABLE_DEBUG_LOGS
        Print(StringFormat("%d. %.3f%% ==================== Step %d | Err: %.2f%% (%.1f pips) | Speed: %.2fx | Score: %.2f",
              i + 1,
              results[i].frequency,
              results[i].targetStep,
              results[i].errorPercent,
              results[i].errorPips,
              results[i].gannAngle,
              results[i].totalScore));
        #endif
    }
    #ifdef ENABLE_DEBUG_LOGS
    Print("========================================");
    #endif
    
    //           
    double bestFreq = results[0].frequency;
    int bestIndex = results[0].frequencyIndex;
    
    //      
    g_th3FreqOverride = bestFreq;
    g_th3FreqIndex = bestIndex;
    
    //     GlobalVariable
    // PERFORMANCE: Use cached ChartID string
    string chartIdStr = GetCachedChartIdStr();
    string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
    string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
    GlobalVariableSet(freqGvarName, bestFreq);
    GlobalVariableSet(indexGvarName, bestIndex);
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== Frequency applied successfully");
    #endif
    
    // Update frequency label
    UpdateTH3FrequencyLabel(bestFreq);
    
    return true;
}


//+------------------------------------------------------------------+
//| Update All TH3 Objects (when frequency changes)                 |
//|       TH3 (                               |
//+------------------------------------------------------------------+
void UpdateAllTH3Objects() {
    int updatedCount = 0;
    
    // PERF: Use pattern store — avoids ObjectsTotal(OBJ_TREND) loop + multiple ObjectGet calls
    int patCount = TH3PatternStoreCount();
    // P-TH3-PERF-04 (2026-09-19): NOTHING TO REPAINT = NOTHING TO DO. The old
    // path walked an empty loop and still ended in ThrottledChartRedraw(), so a
    // settings press on a chart with no patterns paid a full chart repaint for
    // zero objects. This is the same early-out the Tools ring toggle needs,
    // because it calls this on every press.
    if(patCount <= 0) return;
    for(int i = 0; i < patCount; i++) {
        string patName = g_th3Patterns.items[i].name;
        datetime tA = g_th3Patterns.items[i].A.time; double pA = g_th3Patterns.items[i].A.price;
        datetime tB = g_th3Patterns.items[i].B.time; double pB = g_th3Patterns.items[i].B.price;
        datetime tC = g_th3Patterns.items[i].C.time; double pC = g_th3Patterns.items[i].C.price;
        datetime tD = g_th3Patterns.items[i].D.time; double pD = g_th3Patterns.items[i].D.price;
        
        if(tA > 0 && tB > 0 && tC > 0 && pA > 0 && pB > 0 && pC > 0) {
            DrawABCDPattern(patName, tA, pA, tB, pB, tC, pC, tD, pD);   // P-TH3-PB-OFF: no drawn base
            updatedCount++;
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    if(updatedCount > 0) {
        Print("==================== Updated ", updatedCount, " AB=CD patterns with frequency: ", 
              DoubleToString(GetCurrentTH3Frequency(), 3), "%");
    }
    #endif
    
    // P-TH3-INFO-06c: every ladder refresh also heals caption visibility (the
    // verify pass) — a redraw rewrites families it touches, this covers what
    // happened between redraws. Guarded moves only, then the one repaint.
    RepositionABCDInfoLabels();
    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| P-TH3-D4h — RESTORE ON ATTACH. Chart objects outlive the in-     |
//| memory store: after a remove/re-add the patterns sit on the chart |
//| drawn by the OLD build (no ray, no LP token, MP:idle) and        |
//| UpdateAllTH3Objects walks an EMPTY store, so nothing ever        |
//| repaints them — every reload looks like "the fix did nothing".   |
//| This reads each registered base's own anchors (Line_AB, Line_BC, |
//| Line_CD else _Point_D; tD=0 falls back to the AB=CD rule inside  |
//| the draw+build, same as a fresh completion), re-registers the    |
//| model and redraws with the CURRENT code. Active is set BEFORE    |
//| the draws (the CompletePattern rule) so the newest pattern's     |
//| mother overlay paints on the first pass. Returns the count.      |
//+------------------------------------------------------------------+
int TH3RestorePatternsFromChart()
{
    RebuildTH3RegistryFromChart();
    if(g_th3PatternRegistryCount <= 0) return 0;
    string bases[];
    ArrayResize(bases, g_th3PatternRegistryCount);
    int nb = 0;
    for(int r = 0; r < g_th3PatternRegistryCount; r++)
    {
        string base = g_th3PatternRegistry[r];
        // P-TH3-INFO-06b (2026-09-21): a base with no lines is NOT a pattern —
        // and its caption family would outlive it as a dark empty plate (the
        // top-left box: plate without rows). The reposition orphan-sweep only
        // visits the STORE, which this base never reaches, so the family dies
        // HERE, through its one owner. Display-only objects: the next redraw
        // of a real pattern recreates everything it needs.
        if(ObjectFind(0, base + "_Line_AB") < 0) { TH3InfoFamilyDelete(base); continue; }
        if(ObjectFind(0, base + "_Line_BC") < 0) { TH3InfoFamilyDelete(base); continue; }
        bases[nb++] = base;
    }
    if(nb <= 0) return 0;
    ArrayResize(bases, nb);
    if(g_activeABCDPattern == "")
        SetActiveABCDPattern(bases[nb - 1]);   // newest enumeration, before draws
    int done = 0;
    for(int k = 0; k < nb; k++)
    {
        string base = bases[k];
        datetime tA = (datetime)ObjectGetInteger(0, base + "_Line_AB", OBJPROP_TIME, 0);
        double pA = ObjectGetDouble(0, base + "_Line_AB", OBJPROP_PRICE, 0);
        datetime tB = (datetime)ObjectGetInteger(0, base + "_Line_AB", OBJPROP_TIME, 1);
        double pB = ObjectGetDouble(0, base + "_Line_AB", OBJPROP_PRICE, 1);
        datetime tC = (datetime)ObjectGetInteger(0, base + "_Line_BC", OBJPROP_TIME, 1);
        double pC = ObjectGetDouble(0, base + "_Line_BC", OBJPROP_PRICE, 1);
        datetime tD = 0; double pD = 0;
        if(ObjectFind(0, base + "_Line_CD") >= 0) {
            tD = (datetime)ObjectGetInteger(0, base + "_Line_CD", OBJPROP_TIME, 1);
            pD = ObjectGetDouble(0, base + "_Line_CD", OBJPROP_PRICE, 1);
        } else if(ObjectFind(0, base + "_Point_D") >= 0) {
            tD = (datetime)ObjectGetInteger(0, base + "_Point_D", OBJPROP_TIME, 0);
            pD = ObjectGetDouble(0, base + "_Point_D", OBJPROP_PRICE, 0);
        }
        if(tA <= 0 || tB <= 0 || tC <= 0 || pA <= 0 || pB <= 0 || pC <= 0)
        {
            // P-TH3-INFO-06b: unmeasurable anchors, same orphan rule as above.
            TH3InfoFamilyDelete(base);
            continue;
        }
        // P-TH3-PB-OFF: no drawn base survives anything — Path 1 is hand-typed.
        DrawABCDPattern(base, tA, pA, tB, pB, tC, pC, tD, pD);
        TH3RegisterPattern(base, tA, pA, tB, pB, tC, pC, tD, pD);
        done++;
    }
    if(done > 0) Print("TH3: restored ", done, " pattern(s) from chart with current build");
    // P-TH3-INFO-06b: the attach moment is the other place orphans are born
    // (previous builds' families on a re-added chart) — sweep once, here.
    TH3InfoOrphanPlateSweep();
    ThrottledChartRedraw();
    return done;
}

//+------------------------------------------------------------------+
//| Register/refresh a pattern model in the store (called after      |
//| DrawABCDPattern so the in-memory model stays in sync).           |
//+------------------------------------------------------------------+
void TH3RegisterPattern(const string name, datetime tA, double pA,
                        datetime tB, double pB, datetime tC, double pC,
                        datetime tD = 0, double pD = 0)
{
    TH3Pattern model;
    if(TH3PatternBuild(name, tA, pA, tB, pB, tC, pC, tD, pD, model)) {
        model.frequency = g_th3FreqOverride;
        // P-TH3-PB-OFF: nothing to preserve — the drawn base is retired and a
        // rebuild must never resurrect one (Path 1 is hand-typed).
        TH3PatternStoreAdd(model);
    }
}

//+------------------------------------------------------------------+
// ══════════════════════════════════════════════════════════════════
//  LEG MEASURE TOOL — drag-to-draw (TradingView style)
//  • arm با key P یا ring icon
//  • left press → نقطه start ثبت (step=1=dragging)
//  • drag → preview trendline موقت آپدیت
//  • left release → تردلاین نهایی رسم، session تموم
//  • right-click یا ESC → cancel
//  • info box: پلیت تیرهٔ سه‌خطی — H1/H4/D1 pct + همان ATR در پیپ، خط ۳ TF/TF-ATR/Leg%
//    (اندازه‌گیری‌شده، P-LM-01؛ و follower که با اسکرول/زوم جعبه را روی لگ نگه می‌دارد)
//  • جعبه یک VISITOR است (P-LM-09): ۴ ثانیه روی چارت می‌ماند و بعد خودش پاک می‌شود؛
//    یک کلیک روی خانوادهٔ لگ آن را ۴ ثانیهٔ دیگر برمی‌گرداند
//  • جای جعبه (P-LM-09): امتدادِ خودِ خط — از نوک جلوتر، در راستای لگ — و همیشه
//    بیرونِ کندل‌ها؛ اسلات‌های بیرونیِ ناحیهٔ قیمت (سقف/کف) فقط fallback آن‌اند
//  • the finished leg is a MEASUREMENT only (P-TH3-PB-OFF 2026-09-21: the
//    old coupling that stored it as the active pattern's pivot base is
//    retired — the base is hand-typed in the panel, never dragged)
//
//  P-LM-11 (2026-09-20): خط لگ یک TRENDLINE سفارشی است — هیچ جزئش native
//  draggable نیست. دو دستهٔ دایره‌ای (مثل تریدینگ‌ویو) سرِ هر دو سرِ خط + یک
//  دستهٔ وسط، همه OBJ_ELLIPSE با شعاعِ پیکسلی — از هر جهت دقیقاً وسطِ نقطه،
//  در هر زوم. درگ هم CUSTOM است: mousedown با hit-test خودمان، و در هر
//  MOUSE_MOVE همهٔ اجزا در یک پاس بازنویسی می‌شوند — پس هیچ جزئی از خط عقب
//  نمی‌ماند (گزارش کاربر: «الان خط جابجا میشه ولی اون دایره دیرتر میچسبه»).
//
//  Object naming:
//    LM_<ts>_Line   — trendline نهایی (SELECTABLE=true از P-LM-17؛ منوی خود MT4
//                     — Properties و Delete — همان‌طور که بقیهٔ آبجکت‌ها جواب می‌دهد)
//    LM_<ts>_H1/_H2 — دستهٔ دایره‌ای دو سر (P-LM-11)؛ _H1 شروع، _H2 نوک
//    LM_<ts>_Mid    — دستهٔ وسط (hollow) — گرفتنش کل خط را جابجا می‌کند
//    LM_<ts>_Box    — پلیت تیرهٔ readout (P-LM-01) — مهمانِ ۴ ثانیه‌ای (P-LM-09)
//    LM_<ts>_Info.._Info3 — سه خط داخل پلیت
//    LM_prev_Line   — preview موقت (حذف بعد از release)
//    (_Dot و _Arrow و LM_prev_Arrow نام‌های بازنشسته‌اند — P-LM-11/12 آن‌ها را
//     sweep می‌کند؛ پیکان با تصمیم کاربر حذف شد: «پیکان نباشه سرش هر دو سر
//     دایره باشه مثل این» — P-LM-12)
//
//  ویرایش یک اندازه‌گیری (P-LM-11): گرفتن _H1/_H2 سرِ آن را جابجا می‌کند؛
//  گرفتن خود خط یا _Mid کل لگ را؛ release همان لحظهٔ commit است. راست‌کلیک
//  حین درگ، درگ را به جای اولش برمی‌گرداند. حذف و تنظیمات (P-LM-17): مثل
//  بقیهٔ آبجکت‌ها — کلیک = انتخاب بومی، راست‌کلیک = منوی خود MT4 (Properties
//  و Delete)، Delete = حذف، Ctrl+B = لیست. رنگ لگ خودکار است: صعودی سبز،
//  نزولی قرمز (P-LM-17).
// ══════════════════════════════════════════════════════════════════

struct LegMeasureSession
{
    bool     active;
    int      step;       // 0=armed/idle, 1=dragging (mouse held)
    datetime t1;
    double   p1;
};

LegMeasureSession g_legSess;
static bool s_legLastLeft = false;   // edge-detect left button

// ══════════════════════════════════════════════════════════════════
//  THE BOXED READOUT (P-LM-01) — and its follower (P-LM-02)
//
//  The reference leg meter prints its three lines INSIDE a dark plate with
//  a hairline border, on a white chart and on a dark one alike: the plate
//  is a FIXED ink, so the readout never depends on the chart's own theme.
//  That is what is reproduced here, on top of the project's own rules:
//
//  * the plate's SIZE is MEASURED off the very strings it carries
//    (`PnlRawTextW` / `PnlRawLineH`, the chart label family's grid — the same
//    measurement the BaseKnot note plate uses), never guessed;
//  * the plate is created BEFORE its ink, so MT4's own tie-break (equal
//    ZORDER -> creation order) always paints the three lines on top of it;
//  * a screen object does not follow the chart by itself (P-BK-86) and the
//    leg's own trendline carries the anchors, so the follower re-projects the
//    box from those anchors on every layout change. The three lines are
//    CACHED per measurement, because re-projecting must never re-read three
//    ATRs (the arithmetic runs once, in LegMeasureDraw);
//  * every write is change-guarded (P-PERF-02): a box already in place costs
//    a handful of reads and not one ObjectSet*.
// ══════════════════════════════════════════════════════════════════
// ── P-LM-05 (RETIRED BY P-LM-12) — THE LEG'S OWN INK ─────────────────
// P-LM-05 drew the leg as a line ENDS-IN-AN-ARROW: a filled OBJ_TRIANGLE head
// built in screen pixels along the leg, because MT4 has no OBJ_ARROWED_LINE and
// a Wingdings glyph can only point up or down. P-LM-12 (2026-09-20, user:
// «پیکان نباشه سرش هر دو سر دایره باشه مثل این») retired the head: the drawing
// is the reference's PLAIN line wearing a ring at each end and the hollow mid
// one — the direction reads off the line itself. The triangle projection, its
// defines and the shape owner (LegArrowAt) are gone; `_Arrow` survives only as
// a retired name the migration and the delete paths sweep.
// P-LM-11: the TradingView handles. The reference draws a RING at each end of the
// line and a smaller hollow one at its middle; ours are OBJ_ELLIPSE with the
// radius measured in SCREEN pixels (see LegHandleAt), so they are the same circles
// on every zoom and sit EXACTLY on the anchor from every direction — the old
// OBJ_ARROW dot (a Wingdings glyph anchored at its cell's corner, 1px wide) is
// what the user's «وسط باشه دقیقا از هر جهت» retired.
#define LEG_HANDLE_R      6   // px: an endpoint handle's grab radius (the 15px icon)
#define LEG_HANDLE_MID_R  4   // px: the midpoint handle's grab radius (the 11px icon)
#define LEG_HIT_SLOP      3   // px: grab tolerance beyond a handle / the segment
// P-LM-19 (2026-09-21): the CANVAS CENTRE OFFSET is not the grab radius. The
// baked rasters are 15px (ends) and 11px (mid) and their discs are centred at
// canvas pixel 7 and 5 — gen-th3-icons.js centres every shape on (16,16) of a
// 32-unit field, so the pixel whose centre maps to 16 is outSize/2 - 1. Placing
// the icon at `x - LEG_HANDLE_R` (the grab radius, 6) landed the visual centre
// one pixel PAST the anchor, which is what «دقیقا وسط نیست» and a mid dot that
// sat beside the line on a slope were. The grab radii above are hit-test
// business; the placement offsets below are geometry.
#define LEG_HANDLE_HALF      7   // the 15px canvas's centre offset
#define LEG_HANDLE_MID_HALF  5   // the 11px canvas's centre offset
// P-LM-20 (2026-09-21): the handles paint ABOVE the leg's own line. MT4 ties
// equal ZORDER to creation order, and the line is created BEFORE its handles in
// every path that draws the family — so a line widened to 3 for the selection
// face (P-LM-18) paints OVER the discs that sit on its own ends, halving them
// visually. That is half of «موقع سلکت دایره‌ها بهم میریزه»: the dots were
// always there, the line ate them. An explicit ZORDER above the line's own makes
// the three discs read as part of ONE drawing at every width.
// P-LM-20: the discs' rung is Z_CHART_LEG_HANDLE (the Z ladder's own name for
// it - ConstantsAndEnums.mqh, right above Z_CHART_TOOL). It is not a private
// constant beside the tool: the ladder is the one place a paint order is read
// from, and a rung named outside it is a rung no audit can place.
// P-LM-17/19: the ink is DIRECTIONAL. The user's own colours (2026-09-21:
// «لگ نزول قرمز و لگ صعودی آبی پررنگ»): a STRONG BLUE up leg, a RED down one.
// Both are saturated mid-tone with the icons' white halo, so they read on white
// AND black charts; like LEG_INK before them they deliberately do NOT pass
// TH3InkForChart (the icons are baked; a theme-flipped line under fixed icons
// would lie).
#define LEG_BULL_INK   C'31,95,255'    // an up leg: early price below late price
#define LEG_BEAR_INK   C'224,64,64'    // a down leg
#define LEG_HANDLE_UP_RES      "::Files\\Icons\\leg_handle_up.bmp"
#define LEG_HANDLE_UP_MID_RES  "::Files\\Icons\\leg_handle_up_mid.bmp"
#define LEG_HANDLE_DN_RES      "::Files\\Icons\\leg_handle_dn.bmp"
#define LEG_HANDLE_DN_MID_RES  "::Files\\Icons\\leg_handle_dn_mid.bmp"
// P-LM-18 (2026-09-21, user: «حالت سلکتش با سلکت نبودنش اصلا متوجه نمیشیم همش
// یک شکله متر لگ»): the line is SELECTABLE (P-LM-17) but a selected leg looked
// exactly like a resting one — MT4's own anchor squares hide UNDER our baked
// icons. The selection now has a face of its own: the three handles swap to
// the HOLLOW pair (transparent centre vs the solid dot) and the line widens
// one notch. The ONE reader of the native selection is LegMeasureSelected();
// every writer below asks it in the event it is already running in, so there
// is no extra channel and nothing to lag.
#define LEG_HANDLE_UP_SEL_RES      "::Files\\Icons\\leg_handle_up_sel.bmp"
#define LEG_HANDLE_UP_MID_SEL_RES  "::Files\\Icons\\leg_handle_up_mid_sel.bmp"
#define LEG_HANDLE_DN_SEL_RES      "::Files\\Icons\\leg_handle_dn_sel.bmp"
#define LEG_HANDLE_DN_MID_SEL_RES  "::Files\\Icons\\leg_handle_dn_mid_sel.bmp"
#define LEG_LINE_W      2   // the resting line's width
#define LEG_LINE_W_SEL  3   // selected: one notch wider, same DIRECTION ink
// P-LM-06: ONE ink for every leg — the reference's own violet, which is also the
// project's palette violet (#7C5CFF). The old two-colour scheme (aqua up /
// magenta down) said the same thing twice the moment the head started pointing
// ALONG the leg, and the reference shows the direction is read off the head. It is
// deliberately NOT run through TH3InkForChart: half of its carriers are OUR own
// dark plate (the readout's third line), where a theme-flipped ink would be the
// one thing this tool cannot be — unreadable; and the violet reads on both a white
// and a black chart as it is.
#define LEG_INK        TH3RO_ACCENT

// P-TH3-INFO-04 (2026-09-20): the plate's INK, its PADDING and its ROW GRID are
// not declared here any more. The leg meter's box and the AB=CD caption draw the
// SAME readout — one tool, one visual language — so the ink table lives with the
// ink owner (`TH3RO_*` / `TH3ReadoutInk`, TH3Controller.mqh) and the plate's
// layout and writers with the plate owner (`TH3RO_*`, TH3Renderer.mqh). Two
// tables of the same numbers is exactly how the two readouts would drift apart.
// What is genuinely the LEG's own stays here: its row count, and where its box
// sits relative to the leg.
#define LEG_INFO_LINES      3
#define LEG_INFO_FONT_PT    TH3RO_FONT_PT      // the reference box's own text size
#define LEG_INFO_GAP        40                 // px between the leg's tip and the plate —
                                               // P-LM-17: near the head, a step farther so
                                               // the candles under it stay visible.
                                               // P-LM-19 (2026-09-21): widened from 26 —
                                               // the plate read as resting ON the leg's
                                               // head instead of beside it, so the head's
                                               // own handle and the candles at the tip
                                               // were crowded behind it
#define LEG_INFO_MARGIN     4                  // the plate never touches the window frame
// P-LM-23 (2026-09-21, user: «این لیبل اطلاعات همیشه سر نوک دوم باشه و با
// مقدار فاصله که نوک پیوت دیده بشه ... که کندل ها رو نگیره»): the plate has
// ONE place — past the SECOND tip along the leg, LEG_INFO_GAP away, so the
// tip and its handle stay visible and the plate reads as the label of the
// head. The seven-slot walk (P-LM-07/09) is retired: it put the plate wherever
// was clear, and on the user's chart that was up-left of the tip, ON the
// candles — a plate that moves around is a plate nobody can find, and the
// anti-jump memory only existed because the walk could jump. LIFETIME is
// unchanged (P-LM-09): the plate stays LEG_INFO_SHOW_MS, swept by the Full
// entry's timer, and a click on the line starts another visit.
#define LEG_INFO_SLOT_LINE  6   // past the tip, along the leg — the plate's only place
#define LEG_INFO_PARK_X     (-10000)           // leg off-window: park the box outside it
// P-LM-09: how long a visit lasts. Four seconds is long enough to read three rows and
// short enough that the plate is not furniture the candles have to live with; the
// click that starts another visit is the leg's own line.
#define LEG_INFO_SHOW_MS    4000               // ms a plate stays on the chart
#define LEG_INFO_MAX        24                 // measurements the follower tracks

int LegInfoLineH() { return TH3ROLineH(LEG_INFO_FONT_PT); }
int LegInfoRowH()  { return TH3RORowH(LEG_INFO_FONT_PT); }
int LegInfoBoxH()  { return TH3ROPlateH(LEG_INFO_LINES, LEG_INFO_FONT_PT); }

// ── P-LM-17 — DELETION IS NATIVE AGAIN ───────────────────────────────
// P-LM-11 made the family non-selectable to own the drag, and delete then had
// to be re-invented twice (a double-click, then an armed right-click) — and
// the user rejected both: «حذف مثل بقیه باشه», «چرا مثل بقیه ابجکت ها این
// تنظیماتش نمیاد». The resolution: the LINE is SELECTABLE again — MT4's own
// selection, right-click menu (Properties AND Delete) and keyboard Delete all
// answer it, and the object list still cascades through OBJECT_DELETE. The
// native drag this reintroduces is harmless BY CONSTRUCTION: our edit owner
// writes the anchors on every held move, and writing a natively-dragged
// object CANCELS its drag (the measured MT4 fact) — the family's one-pass
// drag takes over within one event, so nothing races. The red-arm and the
// context-menu hold of P-LM-15/16 are retired with the gestures they served.

// The follower's registry: the base name of every drawn measurement plus the
// TEXT and ink its box carries, so a scroll only re-projects what is already
// computed. Sized, never resized (MQL4 arrays of strings are not cheap).
string g_legBase[LEG_INFO_MAX];
string g_legTxt[LEG_INFO_MAX][LEG_INFO_LINES];
color  g_legAccent[LEG_INFO_MAX];
// P-LM-09: is this plate ON the chart right now, and when does its visit END? The
// deadline is a stamp in the future, asked through the project's ONE wrap-safe owner
// (`TickDeadlinePending`, GlobalVariables — the [tick-wrap] gate forbids the absolute
// comparison), so the 49.7-day wrap is not a case the arithmetic can get wrong. A
// measurement whose plate is down costs the follower one bool test and nothing else.
bool   g_legPlateUp[LEG_INFO_MAX];
uint   g_legShownUntil[LEG_INFO_MAX];
int    g_legCount = 0;

// The registry is keyed by the measurement's base name and walked far more often than
// it is appended to (-1 = never seen), so the lookup has ONE owner and everyone asks it.
int LegMeasureIndex(const string base)
{
    for(int i = 0; i < g_legCount; i++)
        if(g_legBase[i] == base) return i;
    return -1;
}

// ── change-guarded writers (P-PERF-02) ─────────────────────────────
// The readout's writers are the PLATE owner's now: TH3ROSetXy / TH3ROSetWh /
// TH3RORowAt live in TH3Renderer.mqh, shared with the AB=CD caption, so the two
// readouts cannot drift apart. They carry the same guards (P-PERF-02), so a leg
// meter already in place still costs a handful of reads and not one ObjectSet*.

// ── guarded two-anchor writer: a chart-space anchor moves only if it moved ──
// (P-PERF-02: MT4 repaints on every ObjectSet*, and MT4 cancels a NATIVE drag
// when its object is written — so a writer that does not know better must be
// able to be called on a leg the user is holding.)
void LegAnchorWrite(const string nm, const int idx, const datetime t, const double p)
{
    if(ObjectFind(0, nm) < 0) return;
    if((datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, idx) != t ||
       ObjectGetDouble(0, nm, OBJPROP_PRICE, idx) != p)
        ObjectMove(0, nm, idx, t, p);
}

// ── P-LM-11/13/14 — ONE HANDLE ───────────────────────────────────────
// The handle is a BAKED ICON (OBJ_BITMAP_LABEL — P-LM-14, the user's call:
// «از ایکون بساز براش»). Chart-space shapes cannot draw it: MT4 does not
// interpolate a time coordinate inside its own bar, so the ±rpx ellipse drew
// as a hairline (P-LM-13) and a one-bar-wide box still drew as a sliver. The
// ring is now the 13px / 9px raster pair gen-th3-icons.js bakes (violet core,
// white halo — legible on white AND black charts), positioned in SCREEN pixels
// with its CENTRE exactly on the projected anchor. The same projection the
// follower reads positions it, so the rings move with the line in one pass.
#define LEG_HANDLE_PARK    (-100)   // anchor off-window: park the icon outside it

// The SCREEN writer — one icon, its CENTRE on this exact pixel. Every handle
// comes through here, so the family's dots cannot be anywhere but ON the line
// (P-LM-16: «کاملا هارمونیک... جایی پرتی نره»): the same projection the drag
// and the follower read positions them, in the same pass, from the same
// anchors — there is no second geometry to keep in sync.
void LegHandleAtXY(const string hn, const int x, const int y,
                   const int half, const string bmp)
{
    if(ObjectFind(0, hn) < 0)
    {
        if(!ObjectCreate(0, hn, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
        ObjectSetInteger(0, hn, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, hn, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, hn, OBJPROP_HIDDEN,     true);
        ObjectSetInteger(0, hn, OBJPROP_BACK,       false);
        ObjectSetInteger(0, hn, OBJPROP_ZORDER,     Z_CHART_LEG_HANDLE);  // P-LM-20
    }
    if(ObjectFind(0, hn) < 0) return;
    // P-LM-20: the rung is re-asserted on EVERY pass, UNGUARDED: a leg the
    // pre-ZORDER build drew keeps its default 0 until something lifts it, and a
    // line widened for the selection face paints over its own discs at 0. The
    // rung is not read back - the zorder audit bans OBJPROP_ZORDER reads in
    // product code (a diagnostic, not a product question, P-UI-31's rule), and
    // the write is the same constant on the same object every pass anyway.
    ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_CHART_LEG_HANDLE);
    // the BMPFILE re-push forces MT4 to re-decode the bitmap — change-guarded,
    // so the re-decode happens only on the arm/disarm swap (P-LM-15)
    if((string)ObjectGetString(0, hn, OBJPROP_BMPFILE, 0) != bmp)
    {
        ObjectSetString(0, hn, OBJPROP_BMPFILE, 0, bmp);
        ObjectSetString(0, hn, OBJPROP_BMPFILE, 1, bmp);
    }
    if(x <= LEG_HANDLE_PARK)
    {
        // the anchor is off-window: park, never guess a screen position
        if((int)ObjectGetInteger(0, hn, OBJPROP_XDISTANCE) != LEG_HANDLE_PARK)
            ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, LEG_HANDLE_PARK);
        return;
    }
    int nx = x - half, ny = y - half;    // the icon's CENTRE sits on the anchor
    if((int)ObjectGetInteger(0, hn, OBJPROP_XDISTANCE) != nx)
        ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, nx);
    if((int)ObjectGetInteger(0, hn, OBJPROP_YDISTANCE) != ny)
        ObjectSetInteger(0, hn, OBJPROP_YDISTANCE, ny);
}

// A chart-anchored handle: project, then screen-place.
void LegHandleAt(const string hn, const datetime t, const double p,
                 const int half, const string bmp)
{
    int x = 0, y = 0;
    if(!ChartTimePriceToXY(0, 0, t, p, x, y))
        LegHandleAtXY(hn, LEG_HANDLE_PARK, LEG_HANDLE_PARK, half, bmp);
    else
        LegHandleAtXY(hn, x, y, half, bmp);
}

// P-LM-18: the ONE reader of MT4's native selection on a leg's line. Every
// selected-state writer (the handle icons, the line width) asks this instead of
// keeping a second opinion — the terminal owns the flag, so a cached copy of it
// would be the lie that made the two states look alike in the first place.
bool LegMeasureSelected(const string base)
{
    string ln = base + "_Line";
    return ObjectFind(0, ln) >= 0 &&
           ObjectGetInteger(0, ln, OBJPROP_SELECTED) != 0;
}

// The width the line should wear RIGHT NOW — resting or selected (P-LM-18).
int LegMeasureLineWidth(const string base)
{
    return LegMeasureSelected(base) ? LEG_LINE_W_SEL : LEG_LINE_W;
}

// P-LM-20 (2026-09-21): the selection face, redrawn ATOMICALLY.
// The user: «موقع سلکت دایره‌ها بهم مریزه چرا اینا جز از یک چیز باید باشن و به
// هیچ وجه در هیچ سناریویی نباید بهم بریزن». They broke apart because the face
// was assembled from PIECES read at different moments: the width came from one
// guarded write, the three rasters from another, and a native click changed the
// selection BETWEEN them — so the line widened while the discs still wore the
// resting bitmaps, or the discs swapped while the line kept its resting width.
// Each piece was correct alone; the family never agreed.
//
// This is the ONE pass that answers a selection change. It reads the terminal's
// own flag ONCE, then writes the line's width and all three discs from that one
// answer in the same call — and it also feeds the anchors back through the ONE
// ink writer (`LegMeasureInk`), so the line, its width and its discs are
// re-projected as one drawing and no channel can leave a part of it behind.
// `LegMeasureEditMouse` calls it on its selection edge; the ride and follow
// channels call the same writer, so a selection that arrives by any other path
// (the object list, a keyboard Delete that missed, a script) still lands whole.
void LegMeasureSelectionRepaint(const string base)
{
    string ln = base + "_Line";
    if(ObjectFind(0, ln) < 0) return;
    datetime t1 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME,  0);
    double   p1 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 0);
    datetime t2 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME,  1);
    double   p2 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 1);
    color    ink = (color)ObjectGetInteger(0, ln, OBJPROP_COLOR);
    // ONE ink pass: line (width included, P-LM-18) + the three discs, and the
    // ZORDER that keeps the discs above the widened line (P-LM-20).
    LegMeasureInk(base, t1, p1, t2, p2, ink, false);
}

// P-LM-16b — THE DOTS RIDE THE CHART THROUGH EVERY CHANNEL THE CHART MOVES IN.
// The icons are screen objects; a chart-anchored ring cannot exist (P-LM-13/14),
// so being "part of the line" is this module's JOB: the same anchors, projected
// by the same owner, rewritten on the same events the chart itself answers —
//   * CHARTEVENT_CHART_CHANGE (wheel, keys, auto-scroll) — via LegMeasureFollowAll;
//   * CHARTEVENT_MOUSE_MOVE (a drag-pan's OWN stream — the case the user's
//     screenshot caught: the line panned and the dots stayed behind);
//   * the Full entry's 250 ms timer as the net.
// COST (P-PERF-02): guarded writes — a chart that did not move costs a couple
// of projections and not one ObjectSet*; a moving chart pays exactly the
// reposition its movement asks for, in the very event that moved it.
// P-LM-18: the selection FACE rides these same channels — a native click that
// selects the line is answered within the next MOUSE_MOVE/timer pass, which
// re-swaps the handle icons and re-widths the line; a deselection undoes both.
void LegMeasureRideChart()
{
    for(int i = 0; i < g_legCount; i++)
    {
        string ln = g_legBase[i] + "_Line";
        if(ObjectFind(0, ln) < 0) continue;
        // P-LM-20: the selection face is painted ATOMICALLY. The terminal's own
        // flag is read here, and any CHANGE answers the whole family in ONE ink
        // pass (line width + the three discs + their ZORDER), so no event can
        // leave a part of the face in the state it replaced — the discs can never
        // disagree with the line again («به هیچ وجه در هیچ سناریویی نباید بهم
        // بریزن»). A UNCHANGED selection still rides the chart through the
        // guarded writers below, because that is what re-projects the dots.
        bool selNow = LegMeasureSelected(g_legBase[i]);
        if(LegMeasureSelShadowMoved(g_legBase[i], selNow))
        {
            LegMeasureSelectionRepaint(g_legBase[i]);
            continue;                 // the repaint re-projected the dots already
        }
        int w = LegMeasureLineWidth(g_legBase[i]);
        if((int)ObjectGetInteger(0, ln, OBJPROP_WIDTH) != w)
            ObjectSetInteger(0, ln, OBJPROP_WIDTH, w);
        LegMeasureHandles(g_legBase[i],
                          (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0),
                          ObjectGetDouble(0, ln, OBJPROP_PRICE, 0),
                          (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1),
                          ObjectGetDouble(0, ln, OBJPROP_PRICE, 1),
                          (color)ObjectGetInteger(0, ln, OBJPROP_COLOR));
    }
}

// A measurement's THREE handles: the reference's ring at each end and the small
// one at the middle. The middle one is not decoration — grabbing it (or the
// line itself) moves the WHOLE leg (P-LM-11) — and it sits at the line's EXACT
// geometric midpoint, projected to pixels (P-LM-16: a chart-space midpoint
// snaps to a bar open and lands OFF the line's middle — the user's «جایی پرتی
// نره»; the pixel midpoint cannot). The icons wear the leg's DIRECTION colour
// (P-LM-17): the green pair on an up leg, the red pair on a down one.
// P-LM-18: the SELECTED face — when the line carries MT4's own selection the
// solid dots swap to the hollow pair, so a selected leg reads at a glance
// («حالت سلکتش با سلکت نبودنش ... یک شکله»).
void LegMeasureHandles(const string base, const datetime t1, const double p1,
                       const datetime t2, const double p2, const color ink)
{
    bool up  = (ink == LEG_BULL_INK);
    bool sel = LegMeasureSelected(base);
    string bmpH = up ? (sel ? LEG_HANDLE_UP_SEL_RES     : LEG_HANDLE_UP_RES)
                     : (sel ? LEG_HANDLE_DN_SEL_RES     : LEG_HANDLE_DN_RES);
    string bmpM = up ? (sel ? LEG_HANDLE_UP_MID_SEL_RES : LEG_HANDLE_UP_MID_RES)
                     : (sel ? LEG_HANDLE_DN_MID_SEL_RES : LEG_HANDLE_DN_MID_RES);
    LegHandleAt(base + "_H1", t1, p1, LEG_HANDLE_HALF, bmpH);
    LegHandleAt(base + "_H2", t2, p2, LEG_HANDLE_HALF, bmpH);
    int sx, sy, tx, ty;
    if(ChartTimePriceToXY(0, 0, t1, p1, sx, sy) &&
       ChartTimePriceToXY(0, 0, t2, p2, tx, ty))
        // P-LM-19: EXACTLY the midpoint — the pixel midpoint of the two projected
        // ends, no bar snapping (a chart-space midpoint lands on a bar OPEN and
        // off the line's middle on any slope: «جایی پرتی نره»). Rounding to the
        // nearest pixel keeps the dot inside one pixel of the true half on every
        // slope, and the 11px canvas's own centre offset is what sits it ON the
        // line rather than beside it.
        LegHandleAtXY(base + "_Mid",
                      (int)MathRound(((double)sx + (double)tx) * 0.5),
                      (int)MathRound(((double)sy + (double)ty) * 0.5),
                      LEG_HANDLE_MID_HALF, bmpM);
    else
        LegHandleAtXY(base + "_Mid", LEG_HANDLE_PARK, LEG_HANDLE_PARK, LEG_HANDLE_MID_HALF, bmpM);
}

// ── the leg's whole ink — ONE owner for a fresh measurement, a drag step and the
//    migration. P-LM-17: the line is SELECTABLE — MT4's own selection, its
//    right-click menu (Properties, Delete) and its keyboard Delete answer it
//    («حذف مثل بقیه», «تنظیماتش مثل بقیه بیاد»). The native drag it allows is
//    dead on arrival: the drag step below writes the anchors on every held move
//    and a write cancels a native drag — the family's one-pass drag takes over
//    within one event, so nothing races and nothing lags.
void LegMeasureInk(const string base, const datetime t1, const double p1,
                   const datetime t2, const double p2, const color ink, const bool create)
{
    string ln = base + "_Line";
    if(create && ObjectFind(0, ln) < 0)
    {
        if(ObjectCreate(0, ln, OBJ_TREND, 0, t1, p1, t2, p2))
        {
            ObjectSetInteger(0, ln, OBJPROP_STYLE,      STYLE_SOLID);
            ObjectSetInteger(0, ln, OBJPROP_WIDTH,      LEG_LINE_W);
            ObjectSetInteger(0, ln, OBJPROP_RAY_LEFT,   false);
            ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT,  false);
            // P-LM-17: selectable=true — the native selection is what makes the
            // terminal's own gestures (right-click Properties/Delete, keyboard
            // Delete) answer this family like any other object.
            ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, ln, OBJPROP_BACK,       false);
        }
    }
    if(ObjectFind(0, ln) >= 0)
    {
        // P-LM-17: the re-own lives HERE, not only in the create branch — a leg
        // the pre-P-LM-17 build drew (the non-selectable era, P-LM-11) survives
        // the migration through this refresh path, and a line left
        // SELECTABLE=false never reaches MT4's right-click menu, so its
        // Properties/Delete never come («مثل بقیه آبجکت ها دکمه دیلیچ نمیاد»).
        // Guarded: a selectable line costs one read. P-LM-21: NOT while our own
        // drag owns this leg — the drag turned the flag OFF so MT4's native drag
        // cannot move the line out from under its discs, and re-owning it here
        // would re-arm that drag in the very pass that is replacing it. Every
        // other leg still re-owns; the drag is a single-base gesture.
        bool dragOwnsThis = (s_legDragMode != 0 && s_legDragBase == base);
        if(!dragOwnsThis && !ObjectGetInteger(0, ln, OBJPROP_SELECTABLE))
            ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, true);
        if(dragOwnsThis)
        {
            // P-LM-21 (cont.): the drag's suppression is idempotent from here
            // too — this pass runs on the drag's own moves, so it keeps the flag
            // off even if something else (a settings redraw, the follower)
            // routed through this writer mid-gesture.
            if((bool)ObjectGetInteger(0, ln, OBJPROP_SELECTABLE))
                ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
        }

        LegAnchorWrite(ln, 0, t1, p1);
        LegAnchorWrite(ln, 1, t2, p2);
        if((color)ObjectGetInteger(0, ln, OBJPROP_COLOR) != ink)
            ObjectSetInteger(0, ln, OBJPROP_COLOR, ink);
        // P-LM-18: the width follows the selection in the SAME pass — a drag
        // that starts on a selected leg keeps the wider line the whole way.
        int w = LegMeasureLineWidth(base);
        if((int)ObjectGetInteger(0, ln, OBJPROP_WIDTH) != w)
            ObjectSetInteger(0, ln, OBJPROP_WIDTH, w);
    }

    // the handles: a ring at each end and the mid one (P-LM-11/14, baked icons,
    // P-LM-17: direction-coloured) — and nothing else: P-LM-12 retired the head
    LegMeasureHandles(base, t1, p1, t2, p2, ink);
}

// ── the plate's own top-left corner: ONE owner for the writer and the follower ──
// P-LM-23: the plate has ONE place — past the SECOND tip along the leg,
// LEG_INFO_GAP away. (P-LM-07/09's candle-aware seven-slot walk is retired: it
// put the plate wherever was clear, and on the user's chart that was ON the
// candles up-left of the tip.) The follower runs on CHART_CHANGE only: a chart
// that did not move re-projects nothing at all.

// The bars a rectangle's pixel X-span turns into: the index of the bar under each
// edge (both edges included — a bar's own width can reach into the rectangle) and
// that strip's ceiling and floor in PRICE, out of the same single pass.
// The plate's ONE rectangle for a plate of `bw` x `bh` on the SECOND tip at
// (tipX, tipY): past the tip ALONG the leg (P-LM-23), LEG_INFO_GAP away, so the
// tip and its handle are never under the box. `dirX`/`dirY` is the leg's own
// direction in pixels (tip minus start) — what makes the plate the continuation
// of the line rather than a box near it. X is clamped into the window here; Y
// is fitted by LegInfoClampY before the plate is ever drawn.
void LegInfoSlotRect(const int tipX, const int tipY,
                     const int dirX, const int dirY,
                     const int bw, const int bh, const int cw, int &bx, int &by)
{
    // past the tip ALONG the leg. The box is offset by its own half-extent
    // MEASURED ON THE LEG, so the edge facing the tip keeps the gap on EVERY
    // slope: offsetting the centre by the gap alone would swallow the head on a
    // steep leg and drift off the line on a flat one. A degenerate direction (a
    // leg with no length on screen) has no line to continue, so it stays centred
    // over the tip, clear of it.
    bx = tipX - bw / 2;
    by = tipY - LEG_INFO_GAP - bh;
    double len = MathSqrt((double)dirX * dirX + (double)dirY * dirY);
    if(len >= 1.0)
    {
        double ux = dirX / len, uy = dirY / len;
        double reach = (MathAbs(ux) * bw + MathAbs(uy) * bh) * 0.5;
        double cx = tipX + ux * (LEG_INFO_GAP + reach);
        double cy = tipY + uy * (LEG_INFO_GAP + reach);
        bx = (int)MathRound(cx - bw / 2.0);
        by = (int)MathRound(cy - bh / 2.0);
    }

    if(cw > 0) {
        int right = cw - LEG_INFO_MARGIN;
        if(bx + bw > right) bx = right - bw;
        if(bx < LEG_INFO_MARGIN) bx = LEG_INFO_MARGIN;
    }
}

// Y only — X was settled with the slot. A screen object has no chart to clip it, so
// the plate is fitted back into the window before it is ever judged.
void LegInfoClampY(const int ch, const int bh, int &by)
{
    if(ch <= 0) return;
    if(by < LEG_INFO_MARGIN) by = LEG_INFO_MARGIN;
    else if(by + bh > ch - LEG_INFO_MARGIN)
        by = (int)MathMax((double)LEG_INFO_MARGIN, (double)(ch - LEG_INFO_MARGIN - bh));
}

// P-LM-24 (2026-09-25) — THE PLATE MUST NEVER END UP ON THE TIP IT LABELS.
//
// P-LM-23 gave the plate ONE place (past the second tip, LEG_INFO_GAP away)
// and P-LM-19 widened that gap for exactly one reason: the head, its handle
// and the candles at the tip have to stay readable. But BOTH ways of fitting
// the plate into the window can undo it, and the common chart is where they
// meet: the leg runs into the newest bars, which IS the window's edge.
//   * the X clamp — `bx = right - bw` slides the plate back over the tip (a
//     200 px plate reaches the tip whenever the head is in the last 200 px);
//   * the Y clamp — near the top edge `by = MARGIN` puts the plate's own rows
//     on the tip's pixel row;
// and because it is the FIXED direction that gets clamped, the plate lands on
// the head with its gap still nominally honoured.
//
// So the place is chosen, not clamped: the preferred side first, then the
// MIRROR of it across the tip (the same gap on the far side of the head, so a
// head at the right edge is labelled from its left), then the two placements
// beside the tip's row. Same purity as P-LM-23 — every candidate is a function
// of the anchors, so the follower re-projects the same rectangle and a scroll
// still cannot move it anywhere else. If the window cannot hold the plate clear
// of the tip at all (a plate wider/taller than the chart), the preferred
// placement stands: the documented floor.
#define LEG_INFO_CLEAR  8   // px around the tip the plate may not cover (the
                            // tip handle's own half + a hair, P-UI-98d)

bool LegInfoCoversTip(const int bx, const int by, const int bw, const int bh,
                      const int tipX, const int tipY)
{
    return (tipX >= bx - LEG_INFO_CLEAR && tipX <= bx + bw + LEG_INFO_CLEAR &&
            tipY >= by - LEG_INFO_CLEAR && tipY <= by + bh + LEG_INFO_CLEAR);
}

void LegInfoBoxTop(const int tipX, const int tipY, const int dirX, const int dirY,
                   const int bw, const int bh, int &bx, int &by)
{
    int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
    int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

    LegInfoSlotRect(tipX, tipY, dirX, dirY, bw, bh, cw, bx, by);   // 1. past the tip
    LegInfoClampY(ch, bh, by);
    if(!LegInfoCoversTip(bx, by, bw, bh, tipX, tipY)) return;

    int mx = 0, my = 0;
    LegInfoSlotRect(tipX, tipY, -dirX, -dirY, bw, bh, cw, mx, my); // 2. the far side
    LegInfoClampY(ch, bh, my);
    if(!LegInfoCoversTip(mx, my, bw, bh, tipX, tipY)) { bx = mx; by = my; return; }

    // 3./4. the clamped X of the preferred side (inside the window by
    // construction, so it keeps LEG_INFO_MARGIN) with the block moved above /
    // below the tip's own row — the same gap, spent on the other axis.
    int keepX = bx;
    int above = tipY - LEG_INFO_GAP - bh;
    if(above >= LEG_INFO_MARGIN)
    {
        by = above;
        if(!LegInfoCoversTip(keepX, by, bw, bh, tipX, tipY)) { bx = keepX; return; }
    }
    int below = tipY + LEG_INFO_GAP;
    if(ch <= 0 || below + bh <= ch - LEG_INFO_MARGIN)
    {
        by = below;
        if(!LegInfoCoversTip(keepX, by, bw, bh, tipX, tipY)) { bx = keepX; return; }
    }

    // 5. the floor: no placement is clear of the tip — take P-LM-23's own answer.
    LegInfoSlotRect(tipX, tipY, dirX, dirY, bw, bh, cw, bx, by);
    LegInfoClampY(ch, bh, by);
}

// Draw — or re-place — ONE measurement's box: the plate first, then its ink.
// `create` is FALSE for the follower, which only ever re-projects an existing box.
// P-TH3-INFO-04: the box is drawn by the SHARED readout owner — the plate and
// its rows are TH3ROPlateAt/TH3RORowAt, the very calls the AB=CD caption makes,
// so the two surfaces are the same readout by construction and not by convention.
// What stays HERE is the leg's own geometry: where the box sits relative to the
// tip (LegInfoBoxTop — P-LM-23: past the SECOND tip along the leg, always) and
// how big it must be to hold its three lines.
void LegInfoBoxPlace(const string base, const int tipX, const int tipY,
                     const int dirX, const int dirY,
                     string &txt[], const bool create)
{
    string plate = base + "_Box";
    string lbs[LEG_INFO_LINES];
    lbs[0] = base + "_Info";
    lbs[1] = base + "_Info2";
    lbs[2] = base + "_Info3";

    // the plate's width = the WIDEST line it carries, measured by the plate owner
    int bw = TH3ROPlateW(txt, LEG_INFO_LINES, LEG_INFO_FONT_PT);
    int bh = LegInfoBoxH();
    int bx, by;
    // P-LM-23: one place — past the second tip along the leg. Nothing is asked
    // and nothing is remembered: the same anchors project the same box.
    LegInfoBoxTop(tipX, tipY, dirX, dirY, bw, bh, bx, by);

    TH3ROPlateAt(plate, CORNER_LEFT_UPPER, bx, by, bw, bh, create,
                 "Leg measure readout (P-LM-01): the leg as a share of each TF's own ATR "
                 "- line 3 names the TF that reads 240-360% (P-LM-22)");

    int rowH = LegInfoRowH();
    for(int i = 0; i < LEG_INFO_LINES; i++)
        TH3RORowAt(lbs[i], txt[i], CORNER_LEFT_UPPER,
                   bx + TH3RO_PAD_X, by + TH3RO_PAD_Y + i * rowH,
                   LEG_INFO_FONT_PT, i, LEG_INFO_LINES, create);
}

// The leg itself scrolled out of the window: an off-window X parks the plate AND
// its ink together, so the box can never be read as belonging to whatever price
// area happens to be under it. One write per object, only on the crossing.
void LegInfoBoxPark(const string base)
{
    string nm[LEG_INFO_LINES + 1];
    nm[0] = base + "_Box";
    nm[1] = base + "_Info";
    nm[2] = base + "_Info2";
    nm[3] = base + "_Info3";
    for(int i = 0; i <= LEG_INFO_LINES; i++)
    {
        if(ObjectFind(0, nm[i]) < 0) continue;
        if((int)ObjectGetInteger(0, nm[i], OBJPROP_XDISTANCE) != LEG_INFO_PARK_X)
            ObjectSetInteger(0, nm[i], OBJPROP_XDISTANCE, LEG_INFO_PARK_X);
    }
}

// ── P-LM-09 — THE PLATE'S WHOLE LIFECYCLE (show / hide / expire) ──────
// The plate is the family's only part that is not the measurement itself: the line,
// the dot and the head are the drawing, the box is a READOUT of it. So the readout is
// a visitor — it arrives with the measurement (and with a click on it), and it leaves
// on its own. Deleting is the honest verb here: the registry keeps the TEXT, so the
// next visit re-measures nothing and re-places nothing the chart has not moved.
void LegInfoBoxDelete(const string base)
{
    ObjectDelete(0, base + "_Box");
    ObjectDelete(0, base + "_Info");
    ObjectDelete(0, base + "_Info2");
    ObjectDelete(0, base + "_Info3");
}

// Where the plate goes, from the leg's own two anchors — the ONE owner for it. The
// fresh draw, the attach-time migration, the follower and the click that calls the
// plate back all come through here, so a plate can never be positioned from a tip the
// line has already left. `create` is FALSE for the follower (it re-projects a plate
// that exists and must never resurrect one that has finished its visit).
bool LegMeasureBoxFromAnchors(const string base, const datetime t1, const double p1,
                              const datetime t2, const double p2, const bool create)
{
    int idx = LegMeasureIndex(base);
    if(idx < 0) return false;             // untracked: there is no text to print
    int sx = 0, sy = 0, tx = 0, ty = 0;
    if(!ChartTimePriceToXY(0, 0, t1, p1, sx, sy) ||
       !ChartTimePriceToXY(0, 0, t2, p2, tx, ty))
    {
        LegInfoBoxPark(base);             // the leg is off-window: park, never guess
        return false;
    }
    string txt[LEG_INFO_LINES];
    for(int k = 0; k < LEG_INFO_LINES; k++) txt[k] = g_legTxt[idx][k];
    // P-LM-09: the direction is the leg's own (tip minus start) — that is what makes
    // the plate the CONTINUATION of the line instead of a box that happens to be near it.
    LegInfoBoxPlace(base, tx, ty, tx - sx, ty - sy, txt, create);
    return true;
}

// The same thing for a caller that does not already hold the anchors (the click).
bool LegMeasureBoxFromLine(const string base, const bool create)
{
    string ln = base + "_Line";
    if(ObjectFind(0, ln) < 0) return false;
    return LegMeasureBoxFromAnchors(base,
        (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0),
        ObjectGetDouble(0, ln, OBJPROP_PRICE, 0),
        (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1),
        ObjectGetDouble(0, ln, OBJPROP_PRICE, 1), create);
}

void LegMeasurePlateHide(const int idx)
{
    if(idx < 0 || idx >= g_legCount) return;
    g_legPlateUp[idx] = false;
    LegInfoBoxDelete(g_legBase[idx]);
}

// Show — or, on a click, show AGAIN: the visit starts over. The deadline is armed
// BEFORE the rebuild on purpose: a click on a leg whose TF history is not loaded yet
// must still not leave the plate half-built and the timer running.
void LegMeasurePlateShow(const string base)
{
    int idx = LegMeasureIndex(base);
    if(idx < 0) return;                   // never measured: nothing to show
    g_legShownUntil[idx] = GetTickCount() + LEG_INFO_SHOW_MS;   // a DEADLINE, asked via the owner
    g_legPlateUp[idx] = true;
    if(LegMeasureBoxFromLine(base, true))
        RepaintForDiscreteAction();       // P-PERF-24: a click is a DISCRETE action
}

// ── P-LM-09: the visit's end ─────────────────────────────────────────
// Called from the Full entry's OnTimer (250 ms), i.e. on a chart that may not have
// ticked at all — which is the point of putting the clock there: the box is a thing
// you glance at, not furniture the candles have to live with. The deadline is asked
// through the project's wrap-safe owner, never compared against GetTickCount()
// directly (P-PERF / [tick-wrap]). Cheap by construction: with no measurement on the
// chart this is one comparison, a plate already down costs one bool, and a plate that
// expires costs four deletes exactly once.
void LegMeasureExpireSweep()
{
    if(g_legCount <= 0) return;
    for(int i = 0; i < g_legCount; i++)
    {
        if(!g_legPlateUp[i]) continue;
        if(TickDeadlinePending(g_legShownUntil[i])) continue;   // the visit is still running
        LegMeasurePlateHide(i);
    }
}

// Remember one measurement's text/ink for the follower. Oldest first out when the
// registry is full: its box simply stops tracking (it is still drawn and readable).
void LegMeasureTrack(const string base, string &txt[], const color accent)
{
    int i = LegMeasureIndex(base);
    if(i >= 0)
    {
        for(int k = 0; k < LEG_INFO_LINES; k++) g_legTxt[i][k] = txt[k];
        g_legAccent[i] = accent;
        return;
    }
    if(g_legCount >= LEG_INFO_MAX) {
        for(int j = 1; j < LEG_INFO_MAX; j++) {
            g_legBase[j - 1] = g_legBase[j];
            for(int k = 0; k < LEG_INFO_LINES; k++) g_legTxt[j - 1][k] = g_legTxt[j][k];
            g_legAccent[j - 1]  = g_legAccent[j];
            g_legPlateUp[j - 1] = g_legPlateUp[j];
            g_legShownUntil[j - 1] = g_legShownUntil[j];
        }
        g_legCount = LEG_INFO_MAX - 1;
    }
    g_legBase[g_legCount] = base;
    for(int k = 0; k < LEG_INFO_LINES; k++) g_legTxt[g_legCount][k] = txt[k];
    g_legAccent[g_legCount] = accent;
    // P-LM-09: a freshly drawn measurement arrives with its plate up, and its 4 s
    // start here — the same deadline the click re-arms, so there is only one.
    g_legPlateUp[g_legCount]     = true;
    g_legShownUntil[g_legCount]  = GetTickCount() + LEG_INFO_SHOW_MS;
    g_legCount++;
}

void LegMeasureForget(const int idx)
{
    if(idx < 0 || idx >= g_legCount) return;
    for(int i = idx + 1; i < g_legCount; i++) {
        g_legBase[i - 1] = g_legBase[i];
        for(int k = 0; k < LEG_INFO_LINES; k++) g_legTxt[i - 1][k] = g_legTxt[i][k];
        g_legAccent[i - 1]  = g_legAccent[i];
        g_legPlateUp[i - 1] = g_legPlateUp[i];   // P-LM-09: the visit travels with its entry
        g_legShownUntil[i - 1] = g_legShownUntil[i];
    }
    g_legCount--;
}

// P-LM-02 — the follower. Called from the CHART_CHANGE branch, i.e. exactly where
// the chart itself answers "I moved": the anchors are read back off the leg's own
// trendline, so a scroll, a zoom, a resize and an auto-scroll on a new bar all land
// the box where the leg is. A leg the user deleted takes its box and ink with it.
void LegMeasureFollowAll()
{
    for(int i = 0; i < g_legCount; )
    {
        string base = g_legBase[i];
        string ln   = base + "_Line";
        if(ObjectFind(0, ln) < 0)
        {
            ObjectDelete(0, base + "_H1");    // P-LM-11: the handle family replaces the dot
            ObjectDelete(0, base + "_H2");
            ObjectDelete(0, base + "_Mid");
            ObjectDelete(0, base + "_Dot");   // retired names, swept for a pre-P-LM-11/12
            ObjectDelete(0, base + "_Arrow"); // chart whose migration was deferred (no ATR)
            ObjectDelete(0, base + "_Box");
            ObjectDelete(0, base + "_Info");
            ObjectDelete(0, base + "_Info2");
            ObjectDelete(0, base + "_Info3");
            LegMeasureForget(i);
            continue;                  // i now names the next measurement
        }
        datetime t1 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0);
        double   p1 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 0);
        datetime t2 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1);
        double   p2 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 1);

        // P-LM-11: the HANDLES follow (the ring at each end and the mid one) —
        // they are re-sized in SCREEN pixels through the same projection, so a
        // zoom would skew a ring built for the previous scale. (P-LM-10's dot
        // write and P-LM-05's head reshaping retired with the dot and the head
        // themselves — P-LM-12.)
        LegMeasureHandles(base, t1, p1, t2, p2, g_legAccent[i]);

        // P-LM-09: a plate that has finished its visit stays down. The follower exists
        // to keep what is ON SCREEN on the leg, so `create` is false here — a leg whose
        // readout expired is not silently re-opened by a scroll. The line and the rings
        // above are the drawing: they are re-projected either way.
        if(g_legPlateUp[i])
            LegMeasureBoxFromAnchors(base, t1, p1, t2, p2, false);
        i++;
    }
}

// ── P-LM-11 — THE DRAG IS OURS: ONE OWNER, ONE PASS, ZERO LAG ────────
// The report this replaces P-LM-10's answer to: «الان خط جابجا میشه ولی اون
// دایره دیرتر میچسبه». P-LM-10 followed a NATIVE drag from three channels, and
// the visible truth stayed: the terminal moves the line on its own paint
// schedule and every follower lands a frame or several later. No channel trick
// fixes that, because the race is between the terminal and us. So the race is
// REMOVED: nothing of a measurement is selectable any more, nobody natively
// drags it, and the drag below moves the WHOLE family — line, both rings, the
// mid handle, the head and the plate — from the same anchors in the same
// MOUSE_MOVE event. What moves together, stays together.
//
// The gates before a press is even considered (one bool/string test each):
//   * the leg tool is not ARMED — its own session owns the press (a new draw);
//   * the view lock is FREE (ChartViewLockHeld) — a panel, the menu, a BaseKnot
//     grab or any other modal gesture owns the pointer, and a leg must never
//     steal it (P-UI-90's one-owner rule, read not written).
static string s_legDragBase   = "";    // the measurement being dragged ("LM_<ts>")
static int    s_legDragMode   = 0;     // 0 none · 1 anchor A (_H1) · 2 anchor B (_H2) · 3 whole leg
static bool   s_legDragMoved  = false; // the press became a drag (a still press is a CLICK)
static datetime s_legSnapT1, s_legSnapT2;           // the anchors as the press found them —
static double   s_legSnapP1, s_legSnapP2;           // ... what a cancel puts back
static datetime s_legPressT;                        // the cursor, in chart space, at the press
static double   s_legPressP;
static int    s_legPressX = 0, s_legPressY = 0;     // ... and in pixels (the moved test)
static bool   s_legEditLeft      = false;           // edge-detect of the edit gesture
// P-LM-20: the selection the family LAST painted for, per measurement. MT4's own
// selection can change outside any event we see (the object list, a script, a
// keyboard Delete that cleared the chart), so this is a SHADOW of the terminal's
// flag, never an authority — its only job is to spot a CHANGE and answer it with
// one atomic repaint. Stale by construction is safe: the next pass re-reads the
// terminal and corrects it.
static string s_legShadowBase[LEG_INFO_MAX];
static bool   s_legSelState[LEG_INFO_MAX];
static int    s_legSelCount = 0;

// The shadow's ONE owner: remember what the family painted, return whether it
// moved. A base not yet shadowed answers `moved = true` so its first paint is an
// atomic one, and a deleted measurement is forgotten with the rest of its entry.
bool LegMeasureSelShadowMoved(const string base, const bool selNow)
{
    for(int i = 0; i < s_legSelCount; i++)
    {
        if(s_legShadowBase[i] != base) continue;
        if(s_legSelState[i] == selNow) return false;   // same state: no repaint needed
        s_legSelState[i] = selNow;                     // it moved: paint the new face
        return true;
    }
    if(s_legSelCount < LEG_INFO_MAX)
    {
        s_legShadowBase[s_legSelCount]  = base;
        s_legSelState[s_legSelCount] = selNow;
        s_legSelCount++;
    }
    return true;                       // never shadowed: paint it once, atomically
}

// P-LM-20: a measurement is gone — its selection shadow goes with it, so a
// re-created leg of the same stamp cannot inherit another leg's painted state.
void LegMeasureSelShadowForget(const string base)
{
    for(int i = 0; i < s_legSelCount; i++)
    {
        if(s_legShadowBase[i] != base) continue;
        for(int j = i + 1; j < s_legSelCount; j++)
        {
            s_legShadowBase[j - 1]  = s_legShadowBase[j];
            s_legSelState[j - 1] = s_legSelState[j];
        }
        s_legSelCount--;
        return;
    }
}

// The hit-test: screen-space distance to each family's rings, mid handle and
// segment. The handles win over the body (they sit ON it), and the nearest leg
// wins when two overlap. Pure reads — it runs on the PRESS EDGE only.
bool LegMeasureHitTest(const int mx, const int my, string &base, int &mode)
{
    base = ""; mode = 0;
    int best = 0x7fff;
    for(int i = 0; i < g_legCount; i++)
    {
        string ln = g_legBase[i] + "_Line";
        if(ObjectFind(0, ln) < 0) continue;
        datetime t1 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0);
        double   p1 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 0);
        datetime t2 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1);
        double   p2 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 1);
        int sx, sy, tx, ty;
        if(!ChartTimePriceToXY(0, 0, t1, p1, sx, sy)) continue;
        if(!ChartTimePriceToXY(0, 0, t2, p2, tx, ty)) continue;
        double vx = (double)(tx - sx), vy = (double)(ty - sy);
        double len2 = vx * vx + vy * vy;
        double tt = 0.0;
        if(len2 >= 1.0)
        {
            tt = ((double)(mx - sx) * vx + (double)(my - sy) * vy) / len2;
            if(tt < 0.0) tt = 0.0;
            if(tt > 1.0) tt = 1.0;
        }
        int cx = (int)MathRound(sx + tt * vx), cy = (int)MathRound(sy + tt * vy);
        int dA = (int)MathSqrt((double)((mx - sx) * (mx - sx) + (my - sy) * (my - sy)));
        int dB = (int)MathSqrt((double)((mx - tx) * (mx - tx) + (my - ty) * (my - ty)));
        int mx0 = (int)MathRound(sx + vx * 0.5), my0 = (int)MathRound(sy + vy * 0.5);
        int dM = (int)MathSqrt((double)((mx - mx0) * (mx - mx0) + (my - my0) * (my - my0)));
        int dS = (int)MathSqrt((double)((mx - cx) * (mx - cx) + (my - cy) * (my - cy)));
        int m = 0, d = 0;
        if(dA <= LEG_HANDLE_R + LEG_HIT_SLOP)              { m = 1; d = dA; }
        else if(dB <= LEG_HANDLE_R + LEG_HIT_SLOP)         { m = 2; d = dB; }
        else if(dM <= LEG_HANDLE_MID_R + LEG_HIT_SLOP + 2) { m = 3; d = dM; }
        else if(dS <= 2 + LEG_HIT_SLOP)                    { m = 3; d = dS; }
        if(m != 0 && d < best) { best = d; base = g_legBase[i]; mode = m; }
    }
    return (mode != 0);
}

// P-LM-21 (2026-09-21): the drag must be the ONLY thing moving the line. The line
// is SELECTABLE (P-LM-17), so MT4 arms its OWN native drag on the press and moves
// the trendline on the terminal's own paint schedule — and the three discs are
// separate bitmap objects the terminal knows nothing about, so the line slides
// out from under them and the user sees the family come apart mid-drag
// («دایره ها از خط جدا میشه»). An anchor write cancels the armed native drag
// (the measured MT4 fact P-LM-17 leans on), but the terminal RE-ARMS it on the
// next paint for as long as the draggable flag sits on it — cancelling one step
// of a loop is not ending the loop. So the flag itself is turned OFF for the
// drag's duration: no native drag is ever armed, and `LegMeasureInk`'s one pass
// is the only writer, so the line and its discs are written as ONE drawing and
// cannot part. It is put back at every exit, so P-LM-17's native gestures
// (right-click Properties/Delete, keyboard Delete, the object list) answer the
// line again the moment the hand leaves it. Guarded, and armed only once a real
// drag has started: a still click never touches the flag, so the terminal's own
// click-selection is untouched (P-LM-20's face answers that, not this).
void LegMeasureDragSelectable(const string base, const bool draggable)
{
    string ln = base + "_Line";
    if(ObjectFind(0, ln) < 0) return;
    if((bool)ObjectGetInteger(0, ln, OBJPROP_SELECTABLE) == draggable) return;
    ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, draggable);
}

// One drag step: re-anchor the WHOLE family from the dragged anchor(s). This is
// what makes the drag inseparable — the same writer the fresh draw and the
// migration use (LegMeasureInk) rewrites line, handles and head from ONE pair
// of anchors in THIS event, and the plate follows from the same anchors.
void LegMeasureDragApply(const datetime curT, const double curP)
{
    string base = s_legDragBase;
    if(s_legDragMode == 0) return;
    if(ObjectFind(0, base + "_Line") < 0)
    {
        LegMeasureDragAbort();     // the line vanished under us (object list): let go
        return;
    }
    // P-LM-21: armed from the FIRST held move by LegMeasureEditMouse (the
    // gesture's own entry), so the drag owns the flag before any anchor is
    // written here. Idempotent and guarded: a move that did not change the flag
    // costs one read.
    LegMeasureDragSelectable(base, false);
    datetime nt1 = s_legSnapT1, nt2 = s_legSnapT2;
    double   np1 = s_legSnapP1, np2 = s_legSnapP2;
    if(s_legDragMode == 1)      { nt1 = curT; np1 = curP; }
    else if(s_legDragMode == 2) { nt2 = curT; np2 = curP; }
    else
    {
        // the whole leg: both anchors ride the cursor's travel since the press
        nt1 += (curT - s_legPressT); np1 += (curP - s_legPressP);
        nt2 += (curT - s_legPressT); np2 += (curP - s_legPressP);
    }
    // P-LM-19 (2026-09-21): the ink is the dragged leg's OWN direction, not the
    // fixed violet — a green leg stayed green only while nobody touched it. The
    // direction is read off the anchors this pass is about to write (the later
    // price above the earlier one is an up leg), so the line and the two handles
    // re-decide their colour on the same anchors they are re-anchored from. A leg
    // dragged PAST horizontal — the tip crossing under its own start — swaps its
    // colour live, which is the honest reading of the geometry it now has.
    color dragInk = ((nt2 >= nt1 ? np2 : np1) >= (nt2 >= nt1 ? np1 : np2))
                    ? LEG_BULL_INK : LEG_BEAR_INK;
    LegMeasureInk(base, nt1, np1, nt2, np2, dragInk, false);

    // the readout rides the drag LIVE — the numbers move with the hand. The ATR
    // composite is TTL-cached per TF (P-LM-19: the same owner the labels read, so
    // a bar that did not move is not re-read), and the visit's clock re-arms so a
    // long drag cannot expire the plate under the user's finger.
    int idx = LegMeasureIndex(base);
    if(idx >= 0 && g_legPlateUp[idx])
    {
        string txt[]; color acc; int otf; bool trusted;
        LegMeasureReadout(nt1, np1, nt2, np2, txt, acc, otf, trusted);
        if(trusted)
        {
            // P-LM-19: the accent the plate wears is the SAME direction answer the
            // line just drew — a readout whose colour disagrees with the leg it is
            // measuring is the old violet bug with a new seat.
            LegMeasureTrack(base, txt, dragInk);
            g_legShownUntil[idx] = GetTickCount() + LEG_INFO_SHOW_MS;
            LegMeasureBoxFromAnchors(base, nt1, np1, nt2, np2, false);
        }
    }
}

// Right-click (or the line vanishing) mid-drag: put the leg back EXACTLY where
// the press found it — the snapshot — and give the view back.
void LegMeasureDragAbort()
{
    if(s_legDragMode == 0) return;
    string base = s_legDragBase;
    s_legDragMode = 0;
    s_legDragBase = "";
    ChartViewLockRelease();           // P-UI-90: exactly one release per acquire
    if(ObjectFind(0, base + "_Line") >= 0)
    {
        // P-LM-21: the hand is off — the native gestures P-LM-17 promised answer
        // the line again. This restore runs on every abort path (the right-click
        // restore, the vanished-line let-go), so the flag cannot stay off behind
        // a gesture that ended.
        LegMeasureDragSelectable(base, true);
        // P-LM-19: the restored leg keeps its OWN direction ink — the snapshot was
        // of a coloured leg, and putting it back violet would repaint a cancelled
        // drag in a colour that leg never had.
        color abInk = ((s_legSnapT2 >= s_legSnapT1 ? s_legSnapP2 : s_legSnapP1) >=
                       (s_legSnapT2 >= s_legSnapT1 ? s_legSnapP1 : s_legSnapP2))
                      ? LEG_BULL_INK : LEG_BEAR_INK;
        LegMeasureInk(base, s_legSnapT1, s_legSnapP1, s_legSnapT2, s_legSnapP2,
                      abInk, false);
        int idx = LegMeasureIndex(base);
        if(idx >= 0 && g_legPlateUp[idx])
            LegMeasureBoxFromAnchors(base, s_legSnapT1, s_legSnapP1,
                                     s_legSnapT2, s_legSnapP2, false);
    }
}

// The release. A MOVED press commits where the finger is (the pass already wrote
// it); the readout's numbers are recomputed once from the final anchors, because
// the cache still carries the leg AS THE PRESS FOUND IT. A STILL press was a
// CLICK: the leg becomes the Delete key's target, the visit re-arms — and a
// second click inside the project's double-click window DELETES it (P-LM-08).
void LegMeasureDragEnd()
{
    if(s_legDragMode == 0) return;
    string base = s_legDragBase;
    s_legDragMode = 0;
    s_legDragBase = "";
    ChartViewLockRelease();           // P-UI-90: exactly one release per acquire
    string ln = base + "_Line";
    if(ObjectFind(0, ln) < 0) return;
    // P-LM-21: the drag owned the line's draggable flag for its duration; the
    // release gives it back, or P-LM-17's right-click menu and Delete go deaf on
    // every leg the user ever dragged.
    LegMeasureDragSelectable(base, true);

    if(!s_legDragMoved)
    {
        // a still click re-arms the readout (and MT4 has SELECTED the line —
        // its own gestures answer from here: P-LM-17)
        LegMeasurePlateShow(base);
        return;
    }

    datetime t1 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0);
    double   p1 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 0);
    datetime t2 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1);
    double   p2 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 1);
    string txt[]; color acc; int otf; bool trusted;
    LegMeasureReadout(t1, p1, t2, p2, txt, acc, otf, trusted);
    if(trusted) LegMeasureTrack(base, txt, acc);
    LegMeasurePlateShow(base);         // the visit re-arms on the FINAL numbers
}

#endif // TH3_TOOL_B_MQH
