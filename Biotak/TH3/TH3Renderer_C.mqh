// TH3Renderer_C.mqh - TH3Renderer.mqh split 2026-09-29: exact lines 2356-2488, byte-identical, zero renames.
#ifndef TH3_RENDERER_C_MQH
#define TH3_RENDERER_C_MQH

void TH3PivotMarkersUpdate()
{
    if(!inpTH3AutoPivots) { TH3PivotMarkersClear(); return; }

    // throttle: once per new chart bar, or every 5 s at most
    static datetime s_lastBar = 0;
    static uint     s_lastMs  = 0;
    static int      s_lastTF  = -1;
    datetime barTime = iTime(NULL, 0, 0);
    uint nowMs = GetTickCount();
    if(barTime == s_lastBar && s_lastBar != 0 && s_lastTF == Period() &&
       (nowMs - s_lastMs) < 5000 && s_lastMs != 0) return;
    s_lastBar = barTime; s_lastMs = nowMs; s_lastTF = Period();

    TH3PivotSix chartP[], structP[];
    ArrayResize(chartP, TH3_P6_MAX_PIVOTS);
    ArrayResize(structP, TH3_P6_MAX_PIVOTS);
    int nc = 0, ns = 0, stf = 0;
    TH3PivotsRead(chartP, structP, nc, ns, stf);

    TH3PivotMarkersClear();   // bulk teardown of our own namespace, then redraw
    // P-TH3-P6b (2026-09-19): the marker must CLEAR the candle and SAY its side.
    // 0.35 of an average candle sat on the wick - a dot you could lose against
    // the bar's own ink (the user's report). The offset is now ~one candle, and
    // the shape carries the direction: a DOWN triangle hangs above an H pivot,
    // an UP triangle sits below an L pivot - high or low reads at a glance,
    // without consulting the price.
    double offset = TH3AvgCandleSize() * 0.90;
    double minOff = 12 * GetCachedPipSize();
    if(offset < minOff) offset = minOff;

    int drawn = 0;
    for(int i = 0; i < nc && drawn < TH3_P6_MAX_PIVOTS; i++)
    {
        if(!chartP[i].valid || chartP[i].base) continue;
        string nm = TH3_P6_PREFIX + "C" + IntegerToString((long)chartP[i].time);
        double p  = chartP[i].price + (chartP[i].isHigh ? offset : -offset);
        if(ObjectCreate(0, nm, OBJ_ARROW, 0, chartP[i].time, p))
        {
            // shared (p. 50): the structure TF owns this pivot — its ink.
            color wantClr = chartP[i].shared ? TH3InkForChart(clrGold)
                                             : TH3InkForChart(clrAqua);
            ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, chartP[i].isHigh ? 218 : 217);
            ObjectSetInteger(0, nm, OBJPROP_COLOR, wantClr);
            ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, nm, OBJPROP_BACK, true);
            ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
            drawn++;
        }
    }
    for(int j = 0; j < ns && drawn < 2 * TH3_P6_MAX_PIVOTS; j++)
    {
        if(!structP[j].valid || structP[j].base) continue;
        string nm = TH3_P6_PREFIX + "S" + IntegerToString((long)structP[j].time);
        double p  = structP[j].price + (structP[j].isHigh ? offset : -offset);
        if(ObjectCreate(0, nm, OBJ_ARROW, 0, structP[j].time, p))
        {
            ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, structP[j].isHigh ? 218 : 217);
            ObjectSetInteger(0, nm, OBJPROP_COLOR, TH3InkForChart(clrOrangeRed));
            ObjectSetInteger(0, nm, OBJPROP_WIDTH, 3);
            ObjectSetInteger(0, nm, OBJPROP_BACK, true);
            ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
            drawn++;
        }
    }
    if(drawn > 0) ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| P-TH3-STEP-04 (2026-09-19) — THE FORWARD PASS. The proof in      |
//| DrawABCDPattern can only fire when the reaction has ALREADY run  |
//| (drawn after the fact). A pattern drawn LIVE completes before    |
//| the reaction exists, so its ladder is drawn on the raw rung and  |
//| then goes stale forever: the chart shows the pre-reaction grid   |
//| while the info of a newer completion shows the proved step — the |
//| two numbers on one chart the user reported (Step:285.5 in the    |
//| header, a 36.5 ladder on the paper). This pass closes that gap:  |
//| on every new chart bar (the same throttle the markers ride) the  |
//| ACTIVE pattern's proof is re-measured, and when a proof exists   |
//| that the drawing does not yet carry — the tip moved, or the      |
//| reaction only just became provable — the pattern is re-drawn.    |//| The measure is pure and cached per bar inside the detector; the   |
//| re-draw runs at most once per bar and only for the one active    |
//| pattern. P-TH3-STEP-04e: the ARITHMETIC is the reaction's own     |
//| (step = |C-tip|/3, no pivot required — P-TH3-STEP-07), so a       |
//| proved step re-draws the ladder whether or not a six-condition    |
//| pivot sits on the tip; the pivot match still words the verdict.    |
//| What cannot vote is a DRIFTING forming bar: the tip must be a     |
//| closed local extreme, which the walk's two-bar offset guarantees.  |
//+------------------------------------------------------------------+
// P-TH3-D4: the forward pass measures from the placed D (tD,pD), not C.
// dirDown = D is a high (pD > pC); the closed seed reads B/C/D; the redraw
// carries the full A/B/C/D model.
void TH3HitPivotForward()
{
    if(g_activeABCDPattern == "") return;
    TH3Pattern pat;
    if(!TH3PatternStoreGet(g_activeABCDPattern, pat)) return;
    if(pat.D.time <= 0 || pat.D.price <= 0) return;
    if(pat.C.time <= 0 || pat.C.price <= 0) return;

    static string s_lastPat = "";
    static double s_lastStep = 0;
    static datetime s_lastTip = 0;

    double rung = TH3PatternStepRung();   // P-TH3-STEP-08: the pattern TF's own TH
    if(rung <= 0) return;
    bool dirDown = (pat.D.price > pat.C.price);
    TH3HitProof hp;
    // P-TH3-STEP-09: same closed seed the draw path votes against, so the
    // forward re-measure cannot adopt what the draw would refuse.
    double fwdStep = 0, fwdK = 0, fwdR = 0;
    double fwdRef = (TH3ClosedStepFromLegs(pat.B.price, pat.C.price, pat.D.price,
                                           fwdStep, fwdK, fwdR) ? fwdStep : 0.0);
    if(!TH3HitPivotMeasure(pat.D.time, pat.D.price, dirDown, rung, hp, fwdRef)) return;
    if(pat.name == s_lastPat && hp.tipTime == s_lastTip &&
       MathAbs(hp.step - s_lastStep) <= GetCachedPoint()) return;   // already carries it

    Print("TH3: forward proof - the active pattern's reaction reached its tip at ",
          DoubleToString(hp.tipPrice, Digits), " (",
          DoubleToString(MathAbs(pat.D.price - hp.tipPrice) / rung, 2),
          " rungs); re-drawing the ladder on the proved step of ",
          DoubleToString(hp.step / GetCachedPipSize(), 1), " pips (",
          DoubleToString(hp.step / rung, 2), " x rung)",
          (hp.hasPivot ? " - six-condition pivot at the tip" : " - no pivot at the tip"));
    s_lastPat = pat.name;
    s_lastStep = hp.step;
    s_lastTip = hp.tipTime;
    DrawABCDPattern(pat.name, pat.A.time, pat.A.price, pat.B.time, pat.B.price,
                    pat.C.time, pat.C.price, pat.D.time, pat.D.price);
}

#endif // TH3_RENDERER_C_MQH
