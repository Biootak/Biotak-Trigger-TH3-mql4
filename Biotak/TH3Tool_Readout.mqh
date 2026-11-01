// TH3Tool_Readout.mqh — P-LM-26 (2026-11-01): split out of TH3Tool_B by P-SIZE-1500
// (that file crossed the 1500-line ceiling the day the seat test landed). The two
// blocks below are byte-identical moves with zero renames: the SEAT's own two tests
// and the readout's two clock hooks. Included by TH3Tool.mqh right after TH3Tool_B,
// so `LEG_INFO_*`, `g_leg*` and `LegMeasurePlateHide` are all declared above them.
#ifndef TH3_TOOL_READOUT_MQH
#define TH3_TOOL_READOUT_MQH

// ── the plate's whole lifecycle (P-SIZE-1500 split, byte-identical bodies) ──
void LegMeasurePlateHide(const int idx)
{
    if(idx < 0 || idx >= g_legCount) return;
    g_legPlateUp[idx] = false;
    g_legPaused[idx]  = false;   // P-LM-26b: the pause dies with the plate it belonged to
    g_legRemainMs[idx] = 0;
    LegInfoBoxDelete(g_legBase[idx]);
}
// ── P-LM-09: the visit's end ───────────────────────────────────────
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
        if(g_legPaused[i]) continue;                            // P-LM-26b: the cursor owns the clock
        if(TickDeadlinePending(g_legShownUntil[i])) continue;   // the visit is still running
        LegMeasurePlateHide(i);
    }
}

// P-LM-26 (2026-11-01) — THE PLATE MAY NOT COVER THE LEG IT MEASURES.
//
// MEASURED (his own frame, 16:03): a leg running down into the newest bars has its tip at
// the window's edge, so "past the tip" is clamped onto the head — and P-LM-24's MIRROR put
// the plate back ALONG the leg, squarely on the candles the leg was drawn to measure. The
// tip test could not see it: the rectangle was clear of the tip's 8 px and on the line.
// So the walk asks the SEGMENT too. A seat that touches the leg's own two anchors is not a
// seat, however far it is from the tip.
// COST: at most len/8 point tests, and only where a placement is already being made (a
// draw, a click, the follower on CHART_CHANGE) — never per frame, never per tick.
bool LegInfoCoversSeg(const int bx, const int by, const int bw, const int bh,
                      const int x0, const int y0, const int x1, const int y1)
{
    int dx = x1 - x0, dy = y1 - y0;
    int steps = (int)(MathMax(MathAbs(dx), MathAbs(dy)) / 8);
    if(steps < 1) steps = 1;
    for(int s = 0; s <= steps; s++)
    {
        int px = x0 + (int)MathRound((double)dx * s / steps);
        int py = y0 + (int)MathRound((double)dy * s / steps);
        if(px >= bx - LEG_INFO_CLEAR && px <= bx + bw + LEG_INFO_CLEAR &&
           py >= by - LEG_INFO_CLEAR && py <= by + bh + LEG_INFO_CLEAR) return true;
    }
    return false;
}
// ONE question, both tests: a seat is clear when it covers neither the head nor the line.
bool LegInfoSeatClear(const int bx, const int by, const int bw, const int bh,
                      const int tipX, const int tipY,
                      const int x0, const int y0, const int x1, const int y1)
{
    return (!LegInfoCoversTip(bx, by, bw, bh, tipX, tipY) &&
            !LegInfoCoversSeg(bx, by, bw, bh, x0, y0, x1, y1));
}

// ── P-LM-26 / P-LM-26b — THE SAME CLOCK AS EVERY OTHER READOUT, AND IT REALLY STOPS ──
// The user: «برای همه باکس اطلاعات یک پارچه باشه» … then «موس روش هستش تایمرش متوقف نمی‌شه
// بعد که برداشتیم باید تایمرش از همون جا شروع بشه تا تموم بشه».
//
// MEASURED (why the first pass did not pause anything): renewing the deadline on every
// MOUSE_MOVE is not a pause. MT4 sends a move only while the HAND moves, so the instant the
// cursor rests on the card the renewals stop and the 2 s runs out under his eyes — the card
// left exactly when he started reading it. A pause is a STATE: on the enter edge the
// REMAINING time is remembered, `LegMeasureExpireSweep` skips a paused plate, and the clock
// resumes from that remainder on the leave edge. Nothing is renewed "to now", so leaving the
// card gives back the rest of the visit instead of restarting it.
//
// AND MT4'S OWN TOOLTIP LANDS ON THE CARD (his frame 16:36: a white `LM_…_Info2` box over the
// third row). The rows carry no description, so the terminal falls back to the object NAME and
// paints it under the cursor — which is exactly where the card is. `CHART_SHOW_OBJECT_DESCR`
// is chart-scoped and is the ONLY switch that suppresses it, so it is turned off for the
// duration of a read and put back the moment the read ends (the user's own chart property is
// never left changed: `s_roDescrPrev` holds what it was).
static string s_roWit      = "";     // the flushed witness' own last line (P-LOG-3, never Print)
static bool   s_roDescrOff = false;  // we turned the chart's object descriptions off
//--- P-DRAW-137 (2026-11-01) — THE VALUE IS THE USER'S, SO IT IS REMEMBERED, NOT ASSUMED.
//--- MEASURED: this comment claimed `s_roDescrPrev` held the previous value, and no such
//--- variable existed — every door out wrote a hard-coded `true`. His chart's own file
//--- says `descriptions=0`, and the text still appeared on a fibo: one hover over the leg
//--- card turned the switch ON for good, and from then every drawing's description was
//--- painted on the chart (the six `[CL…]` blocks of P-DRAW-136 came to light this way).
//--- Now the value is read at the off edge, kept in RAM and in a GlobalVariable (so a
//--- terminal killed mid-read gives it back at the next attach), and restored verbatim.
static bool   s_roDescrPrev = true;  // what the chart held before this read took the switch
string LegInfoDescrKey() { return "Biotak_DescrPrev_" + GetCachedChartIdStr(); }
void LegInfoDescrOff()
{
    if(s_roDescrOff) return;
    s_roDescrPrev = ((int)ChartGetInteger(0, CHART_SHOW_OBJECT_DESCR) != 0);
    s_roDescrOff  = true;
    GlobalVariableSet(LegInfoDescrKey(), s_roDescrPrev ? 1 : 0);
    ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, false);
}
// The chart property is the USER'S, so it is given back on every door out of a read: the
// pointer leaving, the plate being clicked away, and the mute/deinit sweep that takes the
// whole family (LegMeasureHideAll) — a removed indicator must not leave a chart property
// switched off behind it.
void LegInfoDescrRestore()
{
    if(!s_roDescrOff) return;
    ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, s_roDescrPrev);
    GlobalVariableDel(LegInfoDescrKey());
    s_roDescrOff = false;
    s_roWit = "";
}
// P-DRAW-137: a terminal killed between the off edge and the restore leaves the stamp
// behind — the next attach reads it and gives the chart back what the user had.
void LegInfoDescrRecover()
{
    string k = LegInfoDescrKey();
    if(!GlobalVariableCheck(k)) return;
    bool prev = (GlobalVariableGet(k) != 0);
    GlobalVariableDel(k);
    if(!prev) return;                       // it was OFF: its owner chose that, leave it alone
    if((int)ChartGetInteger(0, CHART_SHOW_OBJECT_DESCR) == 0)
        ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, true);
}
int  LegInfoHoverAt(const int mx, const int my)
{
    if(g_legCount <= 0) { LegInfoDescrRestore(); return 0; }
    int hits = 0;
    uint now = GetTickCount();
    for(int i = 0; i < g_legCount; i++)
    {
        if(!g_legPlateUp[i]) continue;
        string p = g_legBase[i] + "_Box";
        if(ObjectFind(0, p) < 0) continue;
        int x = (int)ObjectGetInteger(0, p, OBJPROP_XDISTANCE);
        int y = (int)ObjectGetInteger(0, p, OBJPROP_YDISTANCE);
        int w = (int)ObjectGetInteger(0, p, OBJPROP_XSIZE);
        int h = (int)ObjectGetInteger(0, p, OBJPROP_YSIZE);
        if(w <= 0 || h <= 0) continue;   // a plate nobody measured is not a target
        bool inside = (mx >= x && my >= y && mx <= x + w && my <= y + h);
        if(inside)
        {
            hits++;
            if(!g_legPaused[i])
            {
                int rem = (int)(g_legShownUntil[i] - now);
                if(rem < 0) rem = 0;                        // already spent: enter cannot revive it
                g_legRemainMs[i] = (uint)rem;
                g_legPaused[i]   = true;                    // the cursor owns the clock
                string wit = StringFormat("[P-LM-26] hover=1 idx=%d rect=%d,%d %dx%d cur=%d,%d remain=%d",
                                          i, x, y, w, h, mx, my, rem);
                if(wit != s_roWit) { s_roWit = wit; DrawStripDiagEmit(wit); }
            }
        }
        else if(g_legPaused[i])
        {
            // the leave edge: resume from what was left, never from a fresh 2 s
            g_legShownUntil[i] = now + g_legRemainMs[i];
            g_legPaused[i]     = false;
            string wit = StringFormat("[P-LM-26] hover=0 idx=%d remain=%u resumedAt=%u",
                                      i, g_legRemainMs[i], g_legShownUntil[i]);
            if(wit != s_roWit) { s_roWit = wit; DrawStripDiagEmit(wit); }
        }
    }
    // the tooltip that covers the card goes off while it is being read, and comes back after
    if(hits > 0 && !s_roDescrOff) LegInfoDescrOff();
    else if(hits == 0 && s_roDescrOff) LegInfoDescrRestore();
    return hits;
}
bool LegInfoClickAway(const int mx, const int my)
{
    if(g_legCount <= 0) return false;
    bool done = false;
    for(int i = 0; i < g_legCount; i++)
    {
        if(!g_legPlateUp[i]) continue;
        string p = g_legBase[i] + "_Box";
        bool on = false;
        if(ObjectFind(0, p) >= 0)
        {
            int x = (int)ObjectGetInteger(0, p, OBJPROP_XDISTANCE);
            int y = (int)ObjectGetInteger(0, p, OBJPROP_YDISTANCE);
            int w = (int)ObjectGetInteger(0, p, OBJPROP_XSIZE);
            int h = (int)ObjectGetInteger(0, p, OBJPROP_YSIZE);
            on = (w > 0 && h > 0 && mx >= x && my >= y && mx <= x + w && my <= y + h);
        }
        if(on) continue;
        LegMeasurePlateHide(i);   // the PAIR goes now, not at the next 250 ms sweep
        done = true;
    }
    if(done) LegInfoDescrRestore();   // a dead plate owns no chart property
    if(done) ChartRedraw();
    return done;
}

#endif // TH3_TOOL_READOUT_MQH
