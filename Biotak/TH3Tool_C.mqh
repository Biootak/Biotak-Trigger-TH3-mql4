// TH3Tool_C.mqh - TH3Tool.mqh split 2026-09-29: exact lines 2799-4226, byte-identical, zero renames.
#ifndef TH3_TOOL_C_MQH
#define TH3_TOOL_C_MQH

// (The virtual selection and its Delete-key route retired with P-LM-17: the
// line is MT4-selectable again, so the terminal's own Delete answers it and
// the OBJECT_DELETE cascade sweeps the family.)

// P-LM-13 — the MOTIONLESS click's release. A press/release without movement
// emits NO MOUSE_MOVE at all (an MT4 fact the gesture layer already works
// around with its poll shadow — the same fact bit the draw session's edge
// detector). But the click STILL fires CHARTEVENT_CLICK on button-up, so THIS
// is where a still press ends. Without it the drag state stuck live forever:
// the view lock stayed held (the chart stopped scrolling), the plate hung, and
// the Delete key found no selection — the user's «چرا نمیشه حذفش کرد».
void LegMeasureClickFinalize()
{
    if(s_legDragMode == 0) return;
    if(s_legDragMoved) return;      // a real drag ends on its MOUSE_MOVE release
    LegMeasureDragEnd();            // a still press WAS a click: end it as one
}

// P-LM-20 (2026-09-21): the terminal's OWN selection event.
// A still click on a selectable line fires CHARTEVENT_OBJECT_CLICK — NOT a mouse
// move — so the selection CHANGES between two of our ride passes and the face
// assembled from pieces disagreed with itself: the line widened on the next pass
// while the discs still wore the resting rasters. The user saw the discs
// «به هم بریزن». This is the event that answers it: the terminal tells us WHICH
// object it selected, and the family is repainted atomically from the flag the
// terminal itself just wrote. A click on ANYTHING else deselects our line the
// same way, and this is the only path that sees THAT too (a click on empty chart
// fires the event with a name we do not own, and the line's flag clears).
// Returns true when the click was one of ours, so the router knows it is served.
bool LegMeasureOnObjectClick(const string objName)
{
    if(StringFind(objName, TH3_LEG_PREFIX) != 0) return false;
    int len = StringLen(objName);
    if(len < 6 || StringSubstr(objName, len - 5) != "_Line") return false;
    string base = StringSubstr(objName, 0, len - 5);
    LegMeasureSelectionRepaint(base);   // ONE pass: line + the three discs
    return true;
}

// THE EDIT OWNER — every MOUSE_MOVE the chart reports passes here (Full only).
// The button's edge detector is updated FIRST on EVERY event (a motionless
// click emits no MOUSE_MOVE on release, so a detector updated only on some
// paths misses the rise of the next press — P-LM-13). COST (P-PERF-02): with
// no drag live and the tool disarmed this is two bool tests; the hit-test runs
// on the PRESS EDGE only; and while a drag IS live the per-move pass rewrites
// the family it owns — that write IS the feature, and it is change-guarded, so
// a mouse event that moved nothing costs reads only.
bool LegMeasureEditMouse(const int mx, const int my, const string buttons)
{
    // P-LM-16b: the dots ride the chart in the pan's own event — BEFORE any
    // gate, because a drag-pan fires MOUSE_MOVE while no gesture of ours is
    // live (guarded writes: a still chart costs reads only)
    LegMeasureRideChart();

    bool leftDown  = (StringFind(buttons, "1") >= 0);
    bool rightDown = (StringFind(buttons, "2") >= 0);
    bool pressed   = (leftDown && !s_legEditLeft);   // the rising edge, ONE detector
    s_legEditLeft  = leftDown;                       // ... updated on EVERY event

    // P-LM-13: a press while a gesture is still "live" means its release never
    // arrived (a motionless click emits no MOUSE_MOVE). Close it FIRST — the
    // new press must never be spent continuing a stale drag.
    if(s_legDragMode != 0 && pressed) LegMeasureDragEnd();

    // ── a drag is live: this event is ours, whatever else the chart is doing ──
    if(s_legDragMode != 0)
    {
        if(rightDown) { LegMeasureDragAbort(); return true; }
        if(!leftDown) { LegMeasureDragEnd();   return true; }   // release = final
        ChartViewLockAssert();         // P-BK-14: re-assert every step (P-UI-90)
        // P-LM-21: from the FIRST held move on, MT4's native drag has no claim on
        // this line. The terminal armed it at the press (the line is SELECTABLE,
        // P-LM-17) and moves the trendline on its own paint schedule, while the
        // three discs are separate bitmaps it knows nothing about — the line
        // slides out from under them and the family comes apart mid-drag
        // («دایره ها از خط جدا میشه»). Turning the flag off ONCE the gesture is a
        // drag cancels the armed drag, and the ink pass below is then the ONLY
        // writer of the line's anchors, so line and discs land together every
        // event. A STILL press never reaches here, so a click never borrows the
        // flag — the terminal's own selection (P-LM-20) answers it untouched.
        LegMeasureDragSelectable(s_legDragBase, false);
        int subWin; datetime curT; double curP;
        if(ChartXYToTimePrice(0, mx, my, subWin, curT, curP))
        {
            if(!s_legDragMoved &&
               (MathAbs(mx - s_legPressX) > 2 || MathAbs(my - s_legPressY) > 2))
                s_legDragMoved = true;   // pixels, not ticks: a still hand is a click
            if(s_legDragMoved) LegMeasureDragApply(curT, curP);
        }
        return true;
    }

    // not ours while the draw session is armed (its press starts a NEW leg) or
    // while any other modal gesture holds the chart (P-UI-90)
    if(g_legSess.active)    return false;
    if(ChartViewLockHeld()) return false;

if(pressed)
     {
         string base; int mode;
         if(!LegMeasureHitTest(mx, my, base, mode))
             return false;                    // the press belongs to the chart
         //--- P-UI-144 (2026-10-02): THE HAND IS OURS TO GIVE — the same question the
         //--- path, the ray and the box ask (the arbiter owns it, GlobalVariables.mqh):
         //--- a drawing that is not already TAKEN cannot be taken. The leg carries its
         //--- endpoints AND its three handles, and taking it on the first touch is what
         //--- let a stroke of the terminal's own tool walk away with it. The first press
         //--- TAKES the leg (its plate and handles light up, no anchor moves); the second
         //--- carries it. DECIDED, not detected — three measurements closed that road.
         if(!GestureTakeAllowed(base))
         {
            GestureTakeNote(base);
            LegMeasurePlateShow(base);
            return true;
         }
         // the press is ours: snapshot what the press found, take the view, and
         // bring the readout along for the ride
         string ln = base + "_Line";
        s_legDragBase  = base;
        s_legDragMode  = mode;
        s_legDragMoved = false;
        Print("[LM] carry base=", base, " mode=", IntegerToString(mode), " why=", GestureTakeWhy());   // P-UI-144: the carry's own half of the proof
        s_legSnapT1 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0);
        s_legSnapP1 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 0);
        s_legSnapT2 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1);
        s_legSnapP2 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 1);
        int subWin;
        if(!ChartXYToTimePrice(0, mx, my, subWin, s_legPressT, s_legPressP))
        {
            s_legDragMode = 0; s_legDragBase = "";       // the cursor is off-chart
            return false;
        }
        s_legPressX = mx; s_legPressY = my;
        ChartViewLockAcquire();          // P-UI-90: the drag owns scroll + ctx
        LegMeasurePlateShow(base);       // the readout rides the drag (and re-arms)
        return true;
    }

    return false;
}

// The preview's own teardown, in ONE place: the dashes leave here on every exit
// from the draw gesture (release, cancel, ESC). `_prev_Arrow` is a retired name
// (P-LM-12 swept the head) kept in the sweep so a preview mid-gesture from an
// older build cannot outlive this one.
void LegPreviewClear()
{
    ObjectDelete(0, "LM_prev_Line");
    ObjectDelete(0, "LM_prev_Arrow");   // retired name (P-LM-12)
}

// ── P-LM-04 / P-LM-06 / P-LM-12 — NORMALISE THE LEG-MEASURE NAMESPACE ──
// Every measurement on this chart is brought up to today's tool, once per attach,
// from what the chart itself carries: no stamp is kept anywhere, because the test
// IS the drawing.
//
// Two things happen, in this order, and neither of them moves a drawing:
//   1. INK (P-LM-06/11/12). The line is re-inked and re-owned SELECTABLE
//      (P-LM-17: the re-own lives in the refresh branch of LegMeasureInk, so a
//      line the non-selectable era drew reaches MT4's own gestures again) and
//      the handle rings are built at the anchors the line already holds; the
//      retired `_Dot` glyph and `_Arrow` head are swept. A family drawn before
//      any of these rules existed wears today's shape, and only this pass can tell.
//   2. THE BOX (P-LM-04). A family without a plate gets the readout recomputed and
//      the plate + its three lines built at the leg's own tip.
// It runs from OnInitHandler, beside the pattern restore and AFTER the ATR warmup:
// a TF whose history is not loaded yet yields no ATR, and a box built on a guessed
// one would carry that guess for the rest of its life (P-LM-07).
#define LEG_MIGRATE_MAX 64
void LegMeasureUpgradeLegacy()
{
    // pass 1 — COLLECT FIRST, WRITE SECOND: the walk must not run while the family
    // it is walking is being created and deleted underneath it.
    string bases[LEG_MIGRATE_MAX];
    int n = 0;
    for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0 && n < LEG_MIGRATE_MAX; i--)
    {
        string nm = ObjectName(0, i, -1, -1);
        if(StringFind(nm, TH3_LEG_PREFIX) != 0) continue;
        int len = StringLen(nm);
        if(len < 6 || StringSubstr(nm, len - 5) != "_Line") continue;
        bases[n] = StringSubstr(nm, 0, len - 5);
        n++;
    }

    int boxed = 0, reinked = 0, deferred = 0;
    for(int i = 0; i < n; i++)
    {
        string ln = bases[i] + "_Line";
        datetime t1 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0);
        double   p1 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 0);
        datetime t2 = (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1);
        double   p2 = ObjectGetDouble(0, ln, OBJPROP_PRICE, 1);
        if(t1 == 0 || t2 == 0) continue;   // not a two-anchor line: not ours to guess

        string txt[];
        color  accent;
        int    ownerTF = 0;
        bool   trusted = true;
        LegMeasureReadout(t1, p1, t2, p2, txt, accent, ownerTF, trusted);
        if(!trusted)
        {
            // the TF history is not loaded yet: a box printed now would carry a
            // guessed ATR for the rest of its life. Leave the family alone - the
            // next attach (history by then) normalises it.
            deferred++;
            continue;
        }
        if((color)ObjectGetInteger(0, ln, OBJPROP_COLOR) != accent) reinked++;

        // P-LM-11/12/14: the dot, the head and YESTERDAY'S ELLIPSE handles are
        // retired hardware — MT4 cannot re-type an object, so each goes before
        // today's baked-icon handle can be created at the same name.
        ObjectDelete(0, bases[i] + "_Dot");
        ObjectDelete(0, bases[i] + "_Arrow");
        if(ObjectFind(0, bases[i] + "_H1") >= 0 &&
           ObjectType(bases[i] + "_H1") != OBJ_BITMAP_LABEL)
            ObjectDelete(0, bases[i] + "_H1");
        if(ObjectFind(0, bases[i] + "_H2") >= 0 &&
           ObjectType(bases[i] + "_H2") != OBJ_BITMAP_LABEL)
            ObjectDelete(0, bases[i] + "_H2");
        if(ObjectFind(0, bases[i] + "_Mid") >= 0 &&
           ObjectType(bases[i] + "_Mid") != OBJ_BITMAP_LABEL)
            ObjectDelete(0, bases[i] + "_Mid");
        LegMeasureInk(bases[i], t1, p1, t2, p2, accent, true);
        LegMeasureTrack(bases[i], txt, accent);

        if(ObjectFind(0, bases[i] + "_Box") >= 0) continue;   // its box is already today's

        // MT4 ties equal ZORDER by CREATION ORDER, and a legacy label is older
        // than the plate this pass is about to create — left in place, the plate
        // would be painted OVER its own ink. So the readout's three lines are
        // dropped and rebuilt with the plate: they are our own text, and every
        // character of it is being recomputed here anyway.
        ObjectDelete(0, bases[i] + "_Info");
        ObjectDelete(0, bases[i] + "_Info2");
        ObjectDelete(0, bases[i] + "_Info3");

        // P-LM-09: the plate is placed (and its 4 s started) by the SAME owner the click
        // uses, from the two anchors this pass already read — the tip alone is no longer
        // enough to place it, because the plate continues the LINE.
        if(LegMeasureBoxFromAnchors(bases[i], t1, p1, t2, p2, true))
            boxed++;
    }

    // ONE summary line per attach instead of one per measurement: the previous
    // spelling logged every family every attach, which is noise on a chart that is
    // already normalised (and the reason a stale count is easy to misread).
    if(boxed > 0 || reinked > 0)
        Print("TH3: leg measures normalised (P-LM-04/06): boxed=", boxed,
              " re-inked=", reinked);
    if(deferred > 0)
        Print("TH3: leg measure normalise deferred, no ATR yet (P-LM-07): ", deferred);
}

bool LegMeasureSessionActive() { return g_legSess.active; }

// P-LM-11: the view-lock WATCHDOG must see this tool's two gestures — the armed
// draw session and a live edit drag — as OWNERSHIP, or `ChartScrollReconcile`
// (OnTimer, every 250 ms) reads their lock as a leak, hard-releases it MID-DRAG,
// and the chart pans under the hand (the user's «موقع کشیدن صفحه اسکرول میشه
// نمیزاره درست کشیده بشه»). The exact blind spot P-BK-62 was for BaseKnot: the
// lock exists, the intent list simply did not name its owner.
bool LegMeasureViewOwned() { return g_legSess.active || (s_legDragMode != 0); }

// P-TH3-PB-OFF (2026-09-21): TH3BaseViewOwned retired with the stage-5 base
// drag — the base is hand-typed, so no gesture of it can hold the view.
// Its BiotakPanels.mqh term in ChartLockIntended is retired with it.

void LegMeasureToggle()
{
    if(g_legSess.active) {
        g_legSess.active = false;
        g_legSess.step   = 0;
        s_legLastLeft    = false;
        LegPreviewClear();        // P-LM-10: the dashes and the preview head together
        ChartViewLockRelease();   // P-UI-90: release the shared scroll/ctx lock
} else {
         GestureTakeRelease();   // P-UI-144: a NEW leg is never gated by the last one
         g_legSess.active = true;
        g_legSess.step   = 0;
        s_legLastLeft    = false;
        // P-TH3-PB-UI: one gesture at a time — the leg takes the clicks.
        if(s_th3BaseMarkArmed) TH3BaseMarkCancel("leg meter");
        ChartViewLockAcquire();   // P-UI-90: take the shared scroll/ctx lock
    }
}

// ── P-LM-08 — DELETING ONE MEASUREMENT (and its box with it) ──────────
// P-LM-17 made the LINE selectable again, so the terminal's OWN gestures are
// back: right-click → Delete, select + keyboard Delete, and the object list
// (Ctrl+B). Every one of them deletes the LINE and fires
// CHARTEVENT_OBJECT_DELETE, and the rest of the family (the two direction
// icons, the mid handle, the plate and its three lines) is removed with it
// here — which is what stops the box from being left behind as a ghost.
void LegMeasureDelete(const string base)
{
    ObjectDelete(0, base + "_Line");
    ObjectDelete(0, base + "_H1");       // P-LM-11: the ring at the start
    ObjectDelete(0, base + "_H2");       // ... and at the tip
    ObjectDelete(0, base + "_Mid");      // ... and the mid handle
    ObjectDelete(0, base + "_Dot");      // retired names, swept for a deferred
    ObjectDelete(0, base + "_Arrow");    // migration (P-LM-11/12)
    LegInfoBoxDelete(base);           // P-LM-09: the plate's four objects have ONE owner
    for(int i = 0; i < g_legCount; i++)
    {
        if(g_legBase[i] != base) continue;
        LegMeasureForget(i);          // the follower must stop looking for it
        break;
    }
    LegMeasureSelShadowForget(base);  // P-LM-20: its painted state goes with it
    if(s_legDragBase == base) { s_legDragBase = ""; s_legDragMode = 0; }   // no ghost drag
    Print("TH3: leg measure deleted (P-LM-08): ", base);
    ThrottledChartRedraw();
}

// The terminal reports the deletion of a leg's line (the object list is the one
// native path left). Returns true when it was ours.
bool LegMeasureOnObjectDelete(const string objName)
{
    // P-UI-21's own window, asked through the same two questions the main delete
    // handler asks: our bulk wipes (a removal, a rebuild) fire these events too, and
    // a cascade there would print one line per measurement into a teardown log.
    if(g_suppressDeleteEvents || TickDeadlinePending(g_suppressDeleteEventsUntilMs)) return false;
    if(StringFind(objName, TH3_LEG_PREFIX) != 0) return false;
    int len = StringLen(objName);
    if(len < 6 || StringSubstr(objName, len - 5) != "_Line") return false;
    // ONLY the line cascades: the terminal reports every object WE remove as one of
    // these events too, so a `_Box`/`_Info` member must never re-enter the delete.
    LegMeasureDelete(StringSubstr(objName, 0, len - 5));
    return true;
}

// ── P-LM-07 — THE ATR MEMO (no re-reading a number that did not move) ───
// The readout wants FOUR ATRs: H1, H4, D1 and the owner TF. ATR(14) on a
// COMPLETED bar changes only when that timeframe's own bar count changes, so the
// answer is memoised per TF for the life of its bar: the first measurement pays
// for the reads and every later one — including the whole attach-time migration —
// is a struct read of a value already computed. A chart carrying twenty
// measurements therefore never pays twenty times for three numbers that did not
// move. A TF with no history yet is NOT memoised: it answers 0, the caller treats
// that as "not a reading" (see `trusted` below), and the next pass tries again.
// ── P-LM-19 — THE ATR IS THE LABELS' OWN COMPOSITE, not a second opinion ──
// The user: «برای ATR محاسبه لگ‌ها از همون ATRهای ترکیبی که استفاده کردیم و در
// لیبل‌ها هست استفاده بشه و از چیز جدیدی استفاده نشه». The readout's four ATRs
// were a plain Wilder iATR(14) — a DIFFERENT volatility ruler from the one the
// strip, the knots and the trade-plan labels all read (`CalculateWeightedATR`, the
// Trex SMA composite: weights 1/1/2/3/5/8 over periods 5/10/21/66/132/264, P-ATR-02).
// Two rulers in one tool is how a leg reads 268% of "ATR" in the box while the
// label on the same chart reports a different ATR for the same TF.
//
// COST — the LEAST the question allows. `CalculateWeightedATR` already owns its
// own multi-TF TTL cache (bar-count break + trigger-duration TTL, ATRCalculations),
// and the trade-plan labels ALREADY pay for H1/H4/D1 reads on their own change-gated
// schedule. A leg now reads the SAME cached numbers, so on a chart whose labels are
// current the readout is a struct fetch per TF and not one Wilder pass. The
// per-leg memo table this function used to keep is gone: it was a second cache in
// front of the first, and the first is already keyed by "did this TF's bar move".
// A TF whose history is not loaded yet answers 0, which `LegMeasureReadout` treats
// as "not a reading" (`trusted`), and the next pass tries again.
double LegAtr14(const int tf)
{
    double a = CalculateWeightedATR(CompatTF(tf));
    if(a <= 0.0 || a == EMPTY_VALUE) return 0.0;   // no history for this TF: not a reading
    return a;
}

// ── P-LM-22 (2026-09-21) — THE LEG'S OWN TIMEFRAME: the 240-360% band ─
// The course's own ruler for "which TF does this leg belong to" (PDF pp. 74,
// 106): a leg IS three ATRs of its own TF — the readout's line 1 already
// prints the leg as a share of H1/H4/D1, and the owner is the TF that reads
// 240%..360%. `trusted` is in/out and only ever CLEARS: a TF with no history
// yet cannot be judged, so the walk stops on the last judged TF and the
// readout's contract is unchanged (a readout built on a guessed 1.0 is still
// a lie the migration refuses to write).
#define TH3_LEG_TF_LO   2.40
#define TH3_LEG_TF_HI   3.60
#define TH3_LEG_TF_MID  3.00
int TH3LegOwnerTF(const double legSize, bool &trusted)
{
    int start = Period();
    if(start <= 0) start = 60;
    if(legSize <= 0) return start;   // degenerate leg: no band to judge
    int tf = start;
    int visited[8]; ArrayInitialize(visited, 0); int nVis = 0;   // 0 never
    // equals a chain step: only slots below nVis are ever read
    int bestTF = start; double bestErr = -1.0;
    for(int w = 0; w < 8; w++)
    {
        double a = LegAtr14(tf);          // P-LM-19: the labels' own composite
        if(a <= 0) { trusted = false; break; }
        double r = legSize / a;
        double err = MathAbs(r - TH3_LEG_TF_MID);
        if(bestErr < 0 || err < bestErr) { bestErr = err; bestTF = tf; }
        if(r >= TH3_LEG_TF_LO && r <= TH3_LEG_TF_HI) return tf;
        // outside the band the reading names the direction itself: above it
        // the leg belongs higher, below it lower — one chain step at a time
        int nxt = (r > TH3_LEG_TF_HI) ? TH3FractalStepTF(tf, 1)
                                      : TH3FractalStepTF(tf, -1);
        if(nxt == tf) break;              // chain end: keep the bracket
        bool seen = false;
        for(int v = 0; v < nVis; v++) if(visited[v] == nxt) { seen = true; break; }
        if(seen) break;                   // straddle oscillates: keep the best
        if(nVis < 8) { visited[nVis] = tf; nVis++; }
        tf = nxt;
    }
    return bestTF;
}

// ── THE READOUT ITSELF — ONE owner (P-LM-03) ────────────────────────
// The box's three lines and the leg's own ink, from nothing but the leg's two
// anchors. A fresh measurement (LegMeasureDraw) and one drawn by an OLDER build
// (LegMeasureUpgradeLegacy) both come through here, so the two can never print
// two different readings of the same leg.
//   Line 1: H1: 589% | H4: 268% | D1: 95%     the leg as a share of that TF's ATR
//   Line 2: H1: 208  | H4: 388  | D1: 1899    ... and that ATR itself, in pips
//   Line 3: TF H4 | ATR 387.7 | Leg 268%       the owner TF and its own pair
// Line 3's Leg is the course's own verdict: in the normal case it reads
// 240%..360% (P-LM-22), checkable against line 1's columns — the TF whose
// column sits in that band is the TF line 3 names.
// P-LM-19: every ATR here is the SAME composite the trade-plan labels read
// (`CalculateWeightedATR` via `LegAtr14`) — one ruler for the box and the strip,
// and the readout costs a cached fetch per TF instead of its own Wilder pass.
// `trusted` says whether EVERY ATR it used was real: a readout built on a guessed
// 1.0 is a lie, and the migration (which runs at attach, when history may not be
// loaded yet) refuses to write one.
void LegMeasureReadout(const datetime t1, const double p1,
                       const datetime t2, const double p2,
                       string &txt[], color &accent, int &ownerTF, bool &trusted)
{
    double pip = GetCachedPipSize();
    if(pip <= 0) pip = Point;
    double legSize = MathAbs(p2 - p1);
    trusted = true;

    // the three reference TFs (H1=60, H4=240, D1=1440) whatever the CHART's TF
    // is: these three columns ARE the box's layout
    int    refTFs[3];  refTFs[0]=60; refTFs[1]=240; refTFs[2]=1440;
    double atrRef[3];  atrRef[0]=1;  atrRef[1]=1;   atrRef[2]=1;
    double pctRef[3];  pctRef[0]=0;  pctRef[1]=0;   pctRef[2]=0;
    double pipRef[3];  pipRef[0]=0;  pipRef[1]=0;   pipRef[2]=0;
    for(int i = 0; i < 3; i++) {
        double a = LegAtr14(refTFs[i]);       // P-LM-07: memoised per TF per its own bar
        if(a > 0) atrRef[i] = a;
        else      trusted  = false;          // no history for this TF: not a reading
        pctRef[i] = legSize / atrRef[i] * 100.0;
        pipRef[i] = atrRef[i] / pip;
    }

    // P-LM-22: the owner TF is WALKED by size, not counted by bars. The old
    // rule (TH3ClosedOwnerTF's bar count — the closed step's grid gate,
    // P-TH3-STEP-08/10) could badge a slow small leg D1 while line 1 read it
    // at 140% of H4; the box contradicted itself in its own three lines.
    ownerTF = TH3LegOwnerTF(legSize, trusted);
    double atrOwner = LegAtr14(ownerTF);      // P-LM-07
    if(atrOwner <= 0) { atrOwner = 1; trusted = false; }

    // P-LM-17: the ink is the leg's OWN DIRECTION, automatically — the price at
    // the later bar above the earlier bar's is an up leg (green), below is a
    // down leg (red). ONE owner (P-LM-03): the line, the icons and the readout
    // all wear this answer, and the migration asks the same function.
    double pEarly = (t1 < t2) ? p1 : p2;
    double pLate  = (t1 < t2) ? p2 : p1;
    accent = (pLate >= pEarly) ? LEG_BULL_INK : LEG_BEAR_INK;

    ArrayResize(txt, LEG_INFO_LINES);
    txt[0] = StringFormat("H1: %d%% | H4: %d%% | D1: %d%%",
                          (int)MathRound(pctRef[0]),
                          (int)MathRound(pctRef[1]),
                          (int)MathRound(pctRef[2]));
    txt[1] = StringFormat("H1: %d | H4: %d | D1: %d",
                          (int)MathRound(pipRef[0]),
                          (int)MathRound(pipRef[1]),
                          (int)MathRound(pipRef[2]));
    txt[2] = StringFormat("TF %s | ATR %.1f | Leg %d%%",
                          TH3TfName(ownerTF),
                          atrOwner / pip,
                          (int)MathRound(legSize / atrOwner * 100.0));
}

// Draw the finished trendline + info box for one leg measurement.
// ts   = unique timestamp string for object names
// Returns the object base name ("LM_<ts>")
string LegMeasureDraw(datetime t1, double p1, datetime t2, double p2)
{
    // P-LM-01b: the base carries a tick stamp as well as the second, so two
    // measurements drawn inside one second are two measurements, not one box
    // that silently jumps from the older leg to the newer one.
    string base = TH3_LEG_PREFIX + IntegerToString((int)TimeCurrent()) +
                  "_" + IntegerToString((int)(GetTickCount() % 100000));

    // P-LM-03: the readout has ONE owner — the line, the arrow and the box all
    // wear the answer it gives (and the retired-style migration asks the same
    // function, so two generations of the tool can never print two readings of
    // one leg).
    string legTxt[];
    color  lnCol;
    int    ownerTF = 0;
    bool   trusted = true;      // a live chart has the history: the box is printed as read
    LegMeasureReadout(t1, p1, t2, p2, legTxt, lnCol, ownerTF, trusted);

    // ── the leg's ink: line + start dot + the head that points ALONG it (P-LM-05) ──
    LegMeasureInk(base, t1, p1, t2, p2, lnCol, true);

    // ── The box — the reference's 3-line readout (P-LM-01); the text itself has
    //    its ONE owner in LegMeasureReadout above.
    LegMeasureTrack(base, legTxt, lnCol);   // the follower's cache holds the TEXT...
    LegMeasurePlateShow(base);              // ...and the plate owner places it (P-LM-09)

    // P-TH3-PB-OFF (2026-09-21): the finished leg is a measurement only — the
    // old coupling that stored it on the active pattern as pivotBaseTop/Bottom
    // and re-drew the ladder is retired with the drawn base.
    return base;
}

// Handle MOUSE_MOVE during LegMeasure session.
// sparam carries button flags: "1"=left held, "2"=right held (same encoding TH3Session uses).
// Returns true when a completed draw happened (release after drag).
bool LegMeasureMouseMove(int mx, int my, const string buttons)
{
    if(!g_legSess.active) return false;

    bool leftDown  = (StringFind(buttons, "1") >= 0);
    bool rightDown = (StringFind(buttons, "2") >= 0);

    // Right button → cancel
    if(rightDown) {
        LegMeasureToggle();
        return false;
    }

    int    subWin;
    datetime curT; double curP;
    if(!ChartXYToTimePrice(0, mx, my, subWin, curT, curP)) return false;

    // ── press edge: start drag ──
    if(leftDown && !s_legLastLeft) {
        s_legLastLeft    = true;
        g_legSess.t1     = curT;
        g_legSess.p1     = curP;
        g_legSess.step   = 1;
        return false;
    }

    // ── hold: update preview trendline ──
    // P-BK-14: re-assert the chart lock every step — a panel close or modal
    // card during the drag can flip CHART_MOUSE_SCROLL back on.
    if(leftDown && s_legLastLeft && g_legSess.step == 1) {
        ChartViewLockAssert();   // keep scroll+ctx off while button is down
        // P-UI-97's rule, one tool over: the preview wears the ink the committed
        // measurement will keep (P-LM-06). P-LM-19 (2026-09-21): that ink is the
        // DIRECTION the drag is heading right now — the preview answers «سبز یا
        // قرمز؟» before the release, from the same two prices the committed leg
        // will hold, so what the hand is drawing is what the eye is reading.
        color preCol = ((curP >= g_legSess.p1) ? LEG_BULL_INK : LEG_BEAR_INK);
        if(ObjectFind(0, "LM_prev_Line") < 0) {
            if(ObjectCreate(0, "LM_prev_Line", OBJ_TREND, 0,
                            g_legSess.t1, g_legSess.p1, curT, curP)) {
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_COLOR,     preCol);
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_STYLE,     STYLE_DASH);
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_WIDTH,     1);
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_RAY_LEFT,  false);
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_SELECTABLE,false);
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_BACK,      false);
            }
        } else {
            ObjectMove(0, "LM_prev_Line", 0, g_legSess.t1, g_legSess.p1);
            ObjectMove(0, "LM_prev_Line", 1, curT, curP);
            if((color)ObjectGetInteger(0,"LM_prev_Line",OBJPROP_COLOR) != preCol)
                ObjectSetInteger(0, "LM_prev_Line", OBJPROP_COLOR, preCol);
        }
        // P-LM-12: the preview is the dashed line and NOTHING else — the head
        // it used to wear was retired with the committed drawing's own head.
        return false;
    }

    // ── release edge: finalise ──
    if(!leftDown && s_legLastLeft && g_legSess.step == 1) {
        s_legLastLeft  = false;
        LegPreviewClear();        // P-LM-10: the dashes and the preview head together

        // Only draw if the user actually dragged (min 3 bars or 1 pip distance)
        double pip = GetCachedPipSize();
        if(pip <= 0) pip = Point;
        if(MathAbs(curP - g_legSess.p1) < pip && curT == g_legSess.t1) {
            // Too small — stay armed, let user try again
            g_legSess.step = 0;
            return false;
        }

        LegMeasureDraw(g_legSess.t1, g_legSess.p1, curT, curP);
        g_legSess.active = false;
        g_legSess.step   = 0;
        ChartViewLockRelease();   // P-UI-90: give scroll back on completion
        return true;
    }

    s_legLastLeft = leftDown;
    return false;
}

//+------------------------------------------------------------------+
//| Complete a drawing session: auto-select frequency, draw the      |
//| pattern, register the model, clean up preview objects.           |
//+------------------------------------------------------------------+
void TH3CompletePattern()
{
    datetime tA, tB, tC, tD;
    double pA, pB, pC, pD;
    if(!TH3SessionGetPoint(0, tA, pA)) return;
    if(!TH3SessionGetPoint(1, tB, pB)) return;
    if(!TH3SessionGetPoint(2, tC, pC)) return;
    if(!TH3SessionGetPoint(3, tD, pD)) return;

    // AUTO-SEARCH: optimal frequency for this pattern (3-wave analysis).
    // P-TH3-D4: the 3-wave analyzer still names its legs XA/AB/BC, so the
    // placed AB/BC/CD ride those slots (A->X, B->A, C->B, D->C). No new
    // math, just the mapping stated once.
    FrequencySearchResult searchResults[];
    WaveAnalysis waves;
    double consolidationFactor;
    int resultCount = FindOptimalFrequencyForABCD_WithLearningData(
        tA, pA, tB, pB, tC, pC, tD, pD,
        searchResults, waves, consolidationFactor, 5.0);

    if(resultCount > 0) {
        g_th3FreqOverride = searchResults[0].frequency;
        g_th3FreqIndex = searchResults[0].frequencyIndex;

        string chartIdStr = GetCachedChartIdStr();
        string freqGvarName = "Biotak_TH3Freq_" + chartIdStr;
        string indexGvarName = "Biotak_TH3FreqIdx_" + chartIdStr;
        GlobalVariableSet(freqGvarName, g_th3FreqOverride);
        GlobalVariableSet(indexGvarName, g_th3FreqIndex);
    }

    string patternName = "ABCD_Pattern_" + IntegerToString((long)GetTickCount());
    // P-TH3-D4: active FIRST, draw second. DrawABCDPattern gates the mother
    // overlay on mpActive, so drawing before SetActive minted every new
    // pattern with MP:idle on its first (and often only) paint.
    SetActiveABCDPattern(patternName);
    DrawABCDPattern(patternName, tA, pA, tB, pB, tC, pC, tD, pD);

    // Register the full model (A, B, C, D) in the store
    TH3Pattern model;
    if(TH3PatternBuild(patternName, tA, pA, tB, pB, tC, pC, tD, pD, model)) {
        model.frequency = g_th3FreqOverride;
        TH3PatternStoreAdd(model);
        // Log the arrangement, not just the geometry. Without this the drawn
        // pattern's coordinate is computed and then never seen, which is how the
        // axes stayed unmeasurable in the first place.
        Print("TH3: AB=CD pattern created: ", patternName, " | ",
              TH3SkeletonDescribe(model.skeleton));
    } else {
        Print("TH3: AB=CD pattern created: ", patternName, " | skeleton unavailable");
    }

    TH3PreviewClear();
    UpdateTH3FrequencyLabel(g_th3FreqOverride);
    // P-TH3-PB-OFF (2026-09-21): the session ENDS here — the 5th stage (drag
    // the pivot base) is retired; the base is hand-typed in the TH3 TOOL card
    // (`inpTH3PivotBasePips` -> TH3ManualBaseStep -> TH3LockedStep Path 1).
    g_th3Session.state = TH3_SESSION_IDLE;
    TH3HoverGuardReset();   // P-TH3-PERF-03
    ThrottledChartRedraw();
}

// P-TH3-PB-OFF (2026-09-21) — THE STAGE-5 BASE DRAG (UI half) RETIRED.
// TH3BaseDraftDraw / TH3BaseStageSkip / TH3BaseStageCommit / TH3BaseStageMouse
// lived here: press = one node edge, drag = rubber band, release = commit as
// Path 1 of TH3LockedStep (behind the SHIFT modifier, P-TH3-PB-DRAG). The base
// is hand-typed now (`inpTH3PivotBasePips`), so there is no gesture, no draft
// and no skip. History in git log.

//+------------------------------------------------------------------+
//| P-TH3-PB-UI (2026-09-21) — MARK THE BASE IN TWO CLICKS (key B).  |
//| Typing the number is exact but slow, and the retired press-drag   |
//| fought the terminal's own pan (P-TH3-PB-DRAG). Two clicks hold NO |
//| button, so scroll/pan stays free between them: B arms, click 1    |
//| pins one edge, scroll back as far as needed, click 2 pins the     |
//| other edge — the height lands in BASE PIPS (saved) and the ladder |
//| re-steps. Right-click or B cancels. A commit draws ONE persistent |
//| editor band (below): dragging its anchors IS the resize — native  |
//| MT4, nothing to chase. The panel row stays as the exact-typing    |
//| fallback; both write the same ONE number. One gesture at a time:  |
//| arming refuses while a draw or a leg session owns the clicks.     |
//+------------------------------------------------------------------+
#define TH3_BASE_EDITOR   "TH3_BaseEditor"
#define TH3_BASE_MARK_1   "TH3_BaseMark_1"

bool     s_th3BaseMarkArmed = false;
bool     s_th3BaseMarkHas1  = false;
datetime s_th3BaseMarkT1    = 0;
double   s_th3BaseMarkP1    = 0.0;
// P-TH3-PB-DRAG (2026-09-22): press-drag-release, MT4-native. The click-click
// fallback stays on the CLICK channel (a motionless press emits no move).
bool     s_bmDragDown  = false;   // press held inside an armed mark
bool     s_bmDragMoved = false;   // a held move was seen (else it is a click)
bool     s_bmEditorWas = false;   // a committed band stood before arming
datetime s_bmPrevT     = 0;       // preview dust gate: move only on change
double   s_bmPrevP     = 0.0;
bool     s_bmViewLockHeld = false;   // P-TH3-PB-LOCK: the press-drag owns scroll+ctx
// P-TH3-PB-DRAG-LOCK (2026-09-22): the BAND's own anchor drag owns the view
// too. MT4 fires CHARTEVENT_OBJECT_DRAG continuously while the user resizes
// the committed band, and the chart was panning under the hand because no
// owner held the lock — the press-drag path's `s_bmViewLockHeld` only covers
// the initial two-click / press-drag DRAW, not the resize. The lock is
// acquired on the FIRST drag event for the band and released on the next
// mouse-move that carries no button-down (a motionless release never emits
// MOUSE_MOVE, the P-BK-03 / P-LM-13 fact, so the release ride lives on the
// CHARTEVENT_CLICK that always arrives — see TH3BandDragViewRelease path).
bool     s_bandDragLive    = false;   // a band-anchor drag owns the view lock
string   s_bandDragName    = "";      // the band's own name (TH3_BaseEditor)
uint     s_bandDragMs      = 0;       // last OBJECT_DRAG seen (heartbeat)
bool     s_bandDragLockHeld = false;  // raw lock held by THIS gesture
// P-TH3-BAND-PRESS (2026-09-22): the press EDGE on the move stream, so the
// band's gesture owns the view from the press, not from the first
// OBJECT_DRAG — between the two the terminal had already begun the pan
// («چرا پشت قفل نیست اسکرولش»: aiming at the band's anchors at working zoom,
// a press that misses by a hair starts the chart scrolling under the hand).
bool     s_bandPressDown   = false;   // left button seen down on the move stream

bool TH3BaseMarkArmed() { return s_th3BaseMarkArmed; }

// P-TH3-PB-LOCK (2026-09-22) — the press-drag's view ownership, named for
// ChartLockIntended (the P-LM-11/P-BK-62 rule): without this term the 250 ms
// reconcile reads our lock as a LEAK and hands scroll back under the hand
// mid-drag — exactly the pan the lock exists to stop («اسکرول پشتش قفل
// باشه که راحت بتونم بکشم مثل بقیه»). ARMED-but-idle stays FREE on purpose:
// the two-click mode scrolls between its clicks (P-TH3-PB-UI).
bool TH3BaseMarkViewOwned() { return s_bmViewLockHeld; }

// ONE release per acquire: every end of the gesture funnels here — the move
// stream's release edge, a cancel (right-click/B/leg-meter/draw steal), and
// the CLICK that carries a release no move ever reported (P-LM-13).
void TH3BaseMarkViewRelease()
{
    if(!s_bmViewLockHeld) return;
    s_bmViewLockHeld = false;
    ChartViewLockRelease();
}

void TH3BaseMarkToggle()
{
    if(s_th3BaseMarkArmed) { TH3BaseMarkCancel("toggle"); return; }
    if(TH3SessionActive() || LegMeasureSessionActive()) return;   // clicks are owned; B waits its turn
    s_th3BaseMarkArmed = true;
    s_th3BaseMarkHas1  = false;
    s_bmDragDown = false; s_bmDragMoved = false;
    s_bmEditorWas = (ObjectFind(0, TH3_BASE_EDITOR) >= 0);
    s_bmPrevT = 0; s_bmPrevP = 0.0;
    Print("TH3: base mark armed - press-drag-release (or two clicks: edge 1, scroll, edge 2). Right-click cancels.");
}

void TH3BaseMarkCancel(const string why)
{
    s_th3BaseMarkArmed = false;
    s_th3BaseMarkHas1  = false;
    s_bmDragDown = false; s_bmDragMoved = false;
    TH3BaseMarkViewRelease();    // P-TH3-PB-LOCK: a cancel ends the drag's lock too
    ObjectDelete(0, TH3_BASE_MARK_1);
    // P-TH3-PB-DRAG: a cancelled drag leaves no ghost band -- a committed one
    // is re-projected around the panel value, a preview one is dropped.
    TH3BaseEditorSync();
    Print("TH3: base mark cancelled (", why, ")");
    ThrottledChartRedraw();
}

// The commit: two edges -> BASE PIPS (saved) -> editor band -> re-step.
void TH3BaseMarkCommit(const datetime t1, const double p1,
                       const datetime t2, const double p2)
{
    double pip = GetCachedPipSize();
    if(pip <= 0) pip = Point;
    double bpips = TH3BasePipsFromPrices(p1, p2, pip);
    if(bpips < 1.0) {
        Print("TH3: base mark ignored - edges less than 1 pip apart, click again.");
        return;   // stay armed on the SAME first edge
    }
    g_th3PivotBasePips = bpips;
    s_th3BaseMarkArmed = false;
    s_th3BaseMarkHas1  = false;
    s_bmDragDown = false; s_bmDragMoved = false;
    s_bmPrevT = 0; s_bmPrevP = 0.0;
    ObjectDelete(0, TH3_BASE_MARK_1);
    RuntimeSettingsSaveOverridesThrottled();   // OV_PBP now
    TH3BaseEditorShow(t1, p1, t2, p2);
    UpdateAllTH3Objects();   // re-steps every pattern (ends in a repaint)
    Print("TH3: base marked - ", DoubleToString(bpips, 1), " pips (BASE PIPS saved).");
}

// Edge 1, shared by the click fallback and the drag press: snap like a
// placed pivot (P-TH3-P6), pin, show the "1" tag.
void TH3BaseMarkPinEdge1(datetime ct, double cp)
{
    if(inpTH3AutoPivots) TH3PivotSnap(ct, cp);
    s_th3BaseMarkT1 = ct; s_th3BaseMarkP1 = cp;
    s_th3BaseMarkHas1 = true;
    if(!ObjectMove(0, TH3_BASE_MARK_1, 0, ct, cp)) {
        if(ObjectCreate(0, TH3_BASE_MARK_1, OBJ_TEXT, 0, ct, cp)) {
            ObjectSetString(0, TH3_BASE_MARK_1, OBJPROP_TEXT, "1");
            ObjectSetInteger(0, TH3_BASE_MARK_1, OBJPROP_COLOR, TH3SessionPointInk());
            ObjectSetInteger(0, TH3_BASE_MARK_1, OBJPROP_FONTSIZE, 10);
            ObjectSetInteger(0, TH3_BASE_MARK_1, OBJPROP_SELECTABLE, false);
        }
    }
    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| P-TH3-PB-DRAG (2026-09-22) -- PRESS-DRAG-RELEASE, MT4-NATIVE.    |
//| B arms; press pins edge 1, held moves stretch a live preview     |
//| band (the committed editor itself), release commits edge 2.      |
//| A motionless press/release emits no move (P-LM-13), so pure      |
//| clicks never reach this path and stay on TH3BaseMarkClick.       |
//+------------------------------------------------------------------+
void TH3BaseMarkDragPress(const int mx, const int my)
{
    int subWin; datetime ct; double cp;
    if(!ChartXYToTimePrice(0, mx, my, subWin, ct, cp)) return;
    if(subWin != 0) return;   // the panel is not a base edge
    TH3BaseMarkPinEdge1(ct, cp);
    s_bmDragDown = true; s_bmDragMoved = false;
    s_bmPrevT = ct; s_bmPrevP = cp;
    s_bmViewLockHeld = true; ChartViewLockAcquire();   // P-TH3-PB-LOCK: the drag owns scroll+ctx
}

void TH3BaseMarkDragMove(const int mx, const int my)
{
    int subWin; datetime ct; double cp;
    if(!ChartXYToTimePrice(0, mx, my, subWin, ct, cp)) return;
    if(subWin != 0) return;
    ChartViewLockAssert();   // P-BK-14: a third writer can flip the props mid-gesture
    s_bmDragMoved = true;
    if(ct == s_bmPrevT && cp == s_bmPrevP) return;   // dust gate: move only on change
    s_bmPrevT = ct; s_bmPrevP = cp;
    TH3BaseEditorShow(s_th3BaseMarkT1, s_th3BaseMarkP1, ct, cp);
    ThrottledChartRedraw();
}

void TH3BaseMarkDragRelease(const int mx, const int my)
{
    s_bmDragDown = false;
    TH3BaseMarkViewRelease();    // P-TH3-PB-LOCK: button up, lock back — held or not
    if(!s_bmDragMoved) return;   // a click, not a drag: the CLICK channel owns it
    s_bmDragMoved = false;
    int subWin; datetime ct; double cp;
    if(!ChartXYToTimePrice(0, mx, my, subWin, ct, cp) || subWin != 0) return;
    if(inpTH3AutoPivots) TH3PivotSnap(ct, cp);
    TH3BaseMarkCommit(s_th3BaseMarkT1, s_th3BaseMarkP1, ct, cp);
}

void TH3BaseMarkClick(const int mx, const int my)
{
    int subWin; datetime ct; double cp;
    if(!ChartXYToTimePrice(0, mx, my, subWin, ct, cp)) return;
    // P-TH3-P6: an edge snaps exactly like a placed pivot, so the marked base
    // measures the same candles the detector read.
    if(!s_th3BaseMarkHas1) {
        TH3BaseMarkPinEdge1(ct, cp);
        return;
    }
    if(inpTH3AutoPivots) TH3PivotSnap(ct, cp);
    TH3BaseMarkCommit(s_th3BaseMarkT1, s_th3BaseMarkP1, ct, cp);
}

//+------------------------------------------------------------------+
//| P-TH3-PB-UI — THE EDITOR BAND: ONE OBJECT, NATIVE RESIZE.        |
//| The band visualises the ONE number (BASE PIPS) on the chart. Its |
//| anchors are native MT4: selecting it shows the terminal's own     |
//| squares, dragging one resizes, and OBJECT_DRAG recomputes the     |
//| number from the live anchors (writing everything EXCEPT the band  |
//| itself — writing a natively-dragged object cancels its drag, the  |
//| measured MT4 fact). Deleting the band = back to OFF (0). The      |
//| panel row re-projects the band around its own centre, so typing   |
//| never moves it somewhere else. Times are display only: only the   |
//| two PRICES feed the number.                                       |
//+------------------------------------------------------------------+
void TH3BaseEditorShow(const datetime t1, const double p1,
                       const datetime t2, const double p2)
{
    double top = MathMax(p1, p2), bot = MathMin(p1, p2);
    if(top - bot <= 0) return;
    // P-TH3-PERF-06: move-first — the write IS the existence test.
    if(!ObjectMove(0, TH3_BASE_EDITOR, 0, t1, top)) {
        if(!ObjectCreate(0, TH3_BASE_EDITOR, OBJ_RECTANGLE, 0, t1, top, t2, bot)) return;
        ObjectSetInteger(0, TH3_BASE_EDITOR, OBJPROP_COLOR, TH3InkForChart(inpTH3Color));
        ObjectSetInteger(0, TH3_BASE_EDITOR, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, TH3_BASE_EDITOR, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, TH3_BASE_EDITOR, OBJPROP_FILL, false);
        ObjectSetInteger(0, TH3_BASE_EDITOR, OBJPROP_BACK, false);
        ObjectSetInteger(0, TH3_BASE_EDITOR, OBJPROP_SELECTABLE, true);
        ObjectSetString(0, TH3_BASE_EDITOR, OBJPROP_TOOLTIP, "TH3 base - drag an anchor to resize (BASE PIPS follows)");
        ObjectMove(0, TH3_BASE_EDITOR, 1, t2, bot);
    } else {
        ObjectMove(0, TH3_BASE_EDITOR, 1, t2, bot);
    }
}

// A typed (or restored) number -> band. Keeps the band's own times and
// centre, applies the new height around them; builds the band when missing.
void TH3BaseEditorSync()
{
    if(g_th3PivotBasePips <= 0) { ObjectDelete(0, TH3_BASE_EDITOR); return; }
    double pip = GetCachedPipSize();
    if(pip <= 0) pip = Point;
    double h = g_th3PivotBasePips * pip;
    if(h <= 0) return;
    datetime t1 = 0, t2 = 0;
    double center = 0;
    if(ObjectFind(0, TH3_BASE_EDITOR) >= 0) {
        t1 = (datetime)ObjectGetInteger(0, TH3_BASE_EDITOR, OBJPROP_TIME, 0);
        double a = ObjectGetDouble(0, TH3_BASE_EDITOR, OBJPROP_PRICE, 0);
        t2 = (datetime)ObjectGetInteger(0, TH3_BASE_EDITOR, OBJPROP_TIME, 1);
        double b = ObjectGetDouble(0, TH3_BASE_EDITOR, OBJPROP_PRICE, 1);
        if(t1 <= 0 || t2 <= 0 || a <= 0 || b <= 0) return;
        center = 0.5 * (a + b);
    } else {
        // No band yet: park it on the active pattern's D, else the last bars.
        TH3Pattern pat;
        if(g_activeABCDPattern != "" && TH3PatternStoreGet(g_activeABCDPattern, pat)
           && pat.C.time > 0 && pat.D.time > 0 && pat.D.price > 0) {
            t1 = pat.C.time; t2 = pat.D.time; center = pat.D.price;
        } else {
            int lastBar = MathMax(0, Bars(NULL, 0) - 1);
            t2 = iTime(NULL, 0, 0);
            t1 = iTime(NULL, 0, MathMin(10, lastBar));
            center = iClose(NULL, 0, 0);
            if(center <= 0) center = Bid;
        }
        if(t1 <= 0 || t2 <= 0 || center <= 0) return;
    }
    TH3BaseEditorShow(t1, center + 0.5 * h, t2, center - 0.5 * h);
}

// Native resize: read the LIVE anchors (never write the band here) and let
// the number follow once it moved half a pip — a drag then re-steps without
// stuttering on dust.
// P-TH3-PB-DRAG-LOCK (2026-09-22): the BAND's own anchor drag owns the
// view-lock too. MT4 fires CHARTEVENT_OBJECT_DRAG continuously while the
// user resizes the committed band, and the chart was panning under the
// hand because no owner held the lock — the press-drag path's
// `s_bmViewLockHeld` only covers the initial two-click / press-drag DRAW,
// not the resize. The lock is acquired on the FIRST drag event for the band
// and released on the next mouse-move with no button-down (a motionless
// release never emits MOUSE_MOVE — the P-BK-03 / P-LM-13 fact — so the
// release ride lives on CHARTEVENT_CLICK and the timer net too).
void TH3BaseEditorOnDrag()
{
    if(ObjectFind(0, TH3_BASE_EDITOR) < 0) return;
    if(!s_bandDragLockHeld)
    {
        s_bandDragLive = true;
        s_bandDragName = TH3_BASE_EDITOR;
        s_bandDragMs = GetTickCount();
        s_bandDragLockHeld = true;
        ChartViewLockAcquire();
    }
    else
    {
        ChartViewLockAssert();   // P-BK-14: a third writer can flip the props mid-drag
        s_bandDragMs = GetTickCount();
    }
    double a = ObjectGetDouble(0, TH3_BASE_EDITOR, OBJPROP_PRICE, 0);
    double b = ObjectGetDouble(0, TH3_BASE_EDITOR, OBJPROP_PRICE, 1);
    double pip = GetCachedPipSize();
    if(pip <= 0) pip = Point;
    double bpips = TH3BasePipsFromPrices(a, b, pip);
    if(bpips <= 0) return;
    if(MathAbs(bpips - g_th3PivotBasePips) < 0.5) return;   // dust
    g_th3PivotBasePips = bpips;
    RuntimeSettingsSaveOverridesThrottled();   // OV_PBP now
    UpdateAllTH3Objects();
}

// THE release path for the band-anchor drag's own view-lock. One funnel for
// every end of the gesture: the OBJECT_DRAG idle heartbeat (the 250 ms
// watchdog tick path), a CHARTEVENT_CLICK on the band (button-up with no
// trailing MOUSE_MOVE — P-BK-03), the band's own delete
// (TH3BaseEditorOnDelete clears the drag latch too), and the button-up
// channel inside CHARTEVENT_MOUSE_MOVE.
void TH3BaseBandDragViewRelease()
{
    if(!s_bandDragLockHeld) return;
    s_bandDragLockHeld = false;
    s_bandDragLive = false;
    s_bandDragName = "";
    ChartViewLockRelease();
}

// Lock-ownership accessor for ChartLockIntended (BiotakPanels.mqh). Named
// so the 250 ms reconcile sees the band's gesture the same way the
// press-drag's own view lock, the custom-price drag, the leg meter, and
// BaseKnot each name their own (P-TH3-PB-DRAG-LOCK, the P-LM-11 / P-BK-62
// rule).
bool TH3BaseBandDragViewOwned() { return s_bandDragLockHeld; }

// P-TH3-BAND-PRESS (2026-09-22) — DID THIS PRESS LAND ON THE BAND?
// Screen-pixel hit test off the band's LIVE anchors, in the same shape
// BaseKnotTool's box hit test uses (one read-only ChartTimePriceToXY pair per
// corner). The band is OBJ_RECTANGLE with FILL=false, so MT4 itself only grabs
// its OUTLINE — the corridor below mirrors that: a press inside the hollow
// middle belongs to the chart (it must keep panning), a press on the outline
// or within TH3_BAND_HIT px of it belongs to the band, and the view lock is
// taken at that edge — before MT4 has decided what the gesture is.
#define TH3_BAND_HIT 6   // px of corridor around the band's outline

bool TH3BaseBandPressHit(const int mx, const int my)
{
    if(ObjectFind(0, TH3_BASE_EDITOR) < 0) return false;
    datetime t1 = (datetime)ObjectGetInteger(0, TH3_BASE_EDITOR, OBJPROP_TIME, 0);
    datetime t2 = (datetime)ObjectGetInteger(0, TH3_BASE_EDITOR, OBJPROP_TIME, 1);
    double p1 = ObjectGetDouble(0, TH3_BASE_EDITOR, OBJPROP_PRICE, 0);
    double p2 = ObjectGetDouble(0, TH3_BASE_EDITOR, OBJPROP_PRICE, 1);
    if(t1 <= 0 || t2 <= 0 || p1 <= 0 || p2 <= 0) return false;
    int x1, y1, x2, y2;
    if(!ChartTimePriceToXY(0, 0, t1, p1, x1, y1)) return false;
    if(!ChartTimePriceToXY(0, 0, t2, p2, x2, y2)) return false;
    int left = MathMin(x1, x2), right = MathMax(x1, x2);
    int top  = MathMin(y1, y2), bot   = MathMax(y1, y2);
    bool inOuter = (mx >= left - TH3_BAND_HIT && mx <= right + TH3_BAND_HIT
                    && my >= top - TH3_BAND_HIT && my <= bot + TH3_BAND_HIT);
    if(!inOuter) return false;
    bool inInner = (mx >= left + TH3_BAND_HIT && mx <= right - TH3_BAND_HIT
                    && my >= top + TH3_BAND_HIT && my <= bot - TH3_BAND_HIT);
    return !inInner;   // the outline corridor only — the hollow middle is the chart's
}

// Deleting the band = back to OFF. Only when it is REALLY gone: the sync
// above is move-first (never delete-then-create), so a missing band here is
// the user's own Delete, not ours.
void TH3BaseEditorOnDelete()
{
    // P-TH3-PB-DRAG-LOCK: the band is gone, so any in-flight drag is too —
    // hand the view back the moment we see its absence, or the lock leaks
    // until the 250 ms reconcile runs.
    if(s_bandDragLockHeld) {
        s_bandDragLockHeld = false;
        s_bandDragLive = false;
        s_bandDragName = "";
        ChartViewLockRelease();
    }
    if(ObjectFind(0, TH3_BASE_EDITOR) >= 0) return;
    if(g_th3PivotBasePips <= 0) return;
    g_th3PivotBasePips = 0.0;
    RuntimeSettingsSaveOverridesThrottled();
    UpdateAllTH3Objects();
    Print("TH3: base editor deleted - BASE PIPS back to OFF (pattern TF ATR).");
}

// Heartbeat net: a band-anchor drag that never emits a button-up MOUSE_MOVE
// (a stuck terminal, an off-chart release) keeps its lock until the next
// OBJECT_DRAG arrives — and if NONE arrives, the 250 ms tick path is the
// only thing that can heal it. Called from OnTimer (Full entry only).
void TH3BaseBandDragHeartbeat()
{
    if(!s_bandDragLockHeld) return;
    uint nowMs = GetTickCount();
    // 1.5 s of idle = dead drag. The custom-price and step-1 heals use the
    // same window (P-UI-98e / P-UI-98k precedent).
    if(nowMs - s_bandDragMs > 1500) {
        s_bandDragLockHeld = false;
        s_bandDragLive = false;
        s_bandDragName = "";
        ChartViewLockRelease();
    }
}

//+------------------------------------------------------------------+
//| Unified mouse/key event dispatcher for the TH3 drawing tool.     |
//| State lives in TH3DrawingSession (TH3Controller.mqh) - no more   |
//| scattered g_abcd* globals.                                       |
//+------------------------------------------------------------------+
void OnABCDMouseEvent(int id, long lparam, double dparam, string sparam) {
    // P-TH3-PERF-05 (2026-09-19) — IDLE MOVES COST NOTHING. The event router
    // hands this dispatcher EVERY chart mouse-move (it shares the channel with
    // the rest of the indicator), and the only thing a move can do here is
    // drive a session. With no session active the whole body is dead work, so
    // it is skipped before a single String/Integer parse. Drag/Delete still
    // reach the handlers below (a pattern can be dragged with no session).
    // P-TH3-PB-DRAG: an armed base mark rides this stream too (press/drag/
    // release); the CLICK channel below keeps the motionless clicks.
    // P-TH3-BAND-PRESS (2026-09-22): a LIVE band gesture rides the stream for
    // its button-up release (the branch below was written for exactly that
    // but this early-out returned before it ever ran — the lock then leaked
    // until the 1.5 s heartbeat), and a chart that CARRIES a band pays one
    // ObjectFind per move so the press edge can claim the view before the
    // terminal starts the pan. Idle charts with no band skip all of it.
    if(id == CHARTEVENT_MOUSE_MOVE && !TH3SessionActive() && !TH3BaseMarkArmed()
       && !s_bandDragLockHeld && ObjectFind(0, TH3_BASE_EDITOR) < 0) return;

    // ---- Mouse move: right-click cancel, left-click placement ----
    if(id == CHARTEVENT_MOUSE_MOVE) {
        int mouseState = (int)StringToInteger(sparam);
        bool rightButtonDown = (mouseState & 2) == 2;
        bool leftButtonDown = (mouseState & 1) == 1;

        // P-TH3-PB-OFF: no base stage — a right-click during PLACING cancels.
        // P-TH3-PB-UI: a right-click cancels an armed base mark too (scrolling
        // between its two clicks is always free — no button is ever held).
        if(rightButtonDown && TH3BaseMarkArmed()) {
            TH3BaseMarkCancel("right-click");
            return;
        }
        // P-TH3-BAND-PRESS (2026-09-22): the press edge ON the band takes the
        // view lock at the earliest moment the gesture is provably ours —
        // MT4 routes that same press into the band's native anchor/body drag,
        // and without the lock the chart panned under the hand during the
        // press-to-first-OBJECT_DRAG gap. A press inside the hollow middle is
        // not ours (the band has no fill); the chart keeps it. The release
        // edge below (the s_bandDragLockHeld branch) hands the view back on
        // the first move with no button-down.
        if(!TH3SessionActive() && !TH3BaseMarkArmed()) {
            if(leftButtonDown && !s_bandPressDown) {
                s_bandPressDown = true;
                if(!s_bandDragLockHeld
                   && TH3BaseBandPressHit((int)lparam, (int)dparam)) {
                    s_bandDragLive = true;
                    s_bandDragName = TH3_BASE_EDITOR;
                    s_bandDragMs = GetTickCount();
                    s_bandDragLockHeld = true;
                    ChartViewLockAcquire();
                }
            }
        }
        // The button mirror is UNCONDITIONAL: arming/cancelling B while the
        // button is already down must not eat the next press edge.
        if(!leftButtonDown && s_bandPressDown) s_bandPressDown = false;
        // P-TH3-PB-DRAG (2026-09-22): press-drag-release on the move stream.
        // A motionless press/release emits no move (P-LM-13), so pure clicks
        // fall through to the CLICK channel below untouched.
        if(TH3BaseMarkArmed() && !TH3SessionActive()) {
            if(leftButtonDown && !s_bmDragDown) TH3BaseMarkDragPress((int)lparam, (int)dparam);
            else if(leftButtonDown && s_bmDragDown) TH3BaseMarkDragMove((int)lparam, (int)dparam);
            else if(!leftButtonDown && s_bmDragDown) TH3BaseMarkDragRelease((int)lparam, (int)dparam);
        }
        // P-TH3-PB-DRAG-LOCK: the band's own anchor drag rides the move stream
        // for its release edge — a button-up with the cursor away from the
        // band emits no CHARTEVENT_CLICK on the band (the terminal's hit test
        // fails off the anchor), and CHARTEVENT_OBJECT_DRAG stops firing too.
        // The first MOUSE_MOVE with no button-down ends the gesture.
        if(s_bandDragLockHeld && !leftButtonDown) {
            s_bandDragLockHeld = false;
            s_bandDragLive = false;
            s_bandDragName = "";
            ChartViewLockRelease();
        }
        if(rightButtonDown && TH3SessionActive()) {
            TH3SessionCancel();
            return;
        }

        static bool s_lastLeftButtonState = false;
        if(g_th3Session.state == TH3_SESSION_PLACING && leftButtonDown && !s_lastLeftButtonState) {
            s_lastLeftButtonState = true;

            uint currentTime = GetTickCount();
            if(currentTime - g_th3Session.lastClickTime < ABCD_DEBOUNCE_MS) return;
            g_th3Session.lastClickTime = currentTime;

            int subWindow;
            datetime clickTime;
            double clickPrice;
            if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, clickTime, clickPrice)) return;

            // P-TH3-P6: the click lands ON the course's six-condition pivot
            // when one is within a bar — the drawn X/A/B/C then measure the
            // same candles the detector read (fractal consistency by construction).
            if(inpTH3AutoPivots) TH3PivotSnap(clickTime, clickPrice);

            TH3SessionAddPoint(clickTime, clickPrice);
            if(g_th3Session.state == TH3_SESSION_COMPLETE) {
                TH3CompletePattern();
            }
        }
        else if(!leftButtonDown && s_lastLeftButtonState) {
            s_lastLeftButtonState = false;
        }

        // LIVE PREVIEW: project the next point under the cursor
        if(g_th3Session.state == TH3_SESSION_PLACING) {
            int subWindow;
            datetime hoverTime;
            double hoverPrice;
            if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, hoverTime, hoverPrice)) {
                TH3SessionSetHover(hoverTime, hoverPrice);
                TH3PreviewUpdateHover(hoverTime, hoverPrice);
            }
        }
        return;
    }

    // ---- CHARTEVENT_CLICK fallback + the base mark's own channel ----
    // P-TH3-PB-UI: the mark mode clicks through here too (a motionless press
    // emits no MOUSE_MOVE — the P-LM-13 fact — so CLICK is the mode's whole
    // input, and the mode never needs the move stream at all).
    if(id == CHARTEVENT_CLICK && (TH3SessionActive() || TH3BaseMarkArmed())) {
        // The mark owns no session: when both somehow arm, the draw wins and
        // the mark waits (its toggle refuses while a session is active anyway).
        if(TH3BaseMarkArmed() && !TH3SessionActive()) {
            // P-TH3-PB-LOCK/P-LM-13: a release with no trailing move arrives
            // ONLY as this click — end the drag's lock and state here, or the
            // view stays locked (and s_bmDragDown stale) until a cancel.
            TH3BaseMarkViewRelease();
            s_bmDragDown = false; s_bmDragMoved = false;
            TH3BaseMarkClick((int)lparam, (int)dparam);
            return;
        }
        // P-TH3-PB-OFF: the BASE finalizer lived here (a motionless press emits
        // no MOUSE_MOVE) — retired with the stage; the click below places pivots.
        uint currentTime = GetTickCount();
        if(currentTime - g_th3Session.lastClickTime < ABCD_DEBOUNCE_MS) return;
        g_th3Session.lastClickTime = currentTime;

        int subWindow;
        datetime clickTime;
        double clickPrice;
        if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam, subWindow, clickTime, clickPrice)) return;

        // P-TH3-P6: same snap as the move channel's press edge — one rule for
        // both channels, so a click cannot land differently depending on which
        // one carried it.
        if(inpTH3AutoPivots) TH3PivotSnap(clickTime, clickPrice);

        TH3SessionAddPoint(clickTime, clickPrice);
        if(g_th3Session.state == TH3_SESSION_COMPLETE) {
            TH3CompletePattern();
        }
        return;
    }

    // ---- Drag points A/B/C with smart OHLC snapping ----
    if(id == CHARTEVENT_OBJECT_DRAG) {
        // P-UI-100 (2026-09-22): WHILE THIS TOOL DRAGS ITS OWN OBJECT, NO HAND-SET
        // LINE MAY STAY SELECTED. This drag is a chart drag like any other — MT4
        // moves every SELECTED object with it (P-UI-45/P-BK-26) — so a custom price
        // line (or a step-1 handle) left selected by an earlier gesture rides along
        // with the band or an ABCD point, and the whole ladder derived from its
        // price moves with it. The guard is the shared owner; it skips the lines a
        // live gesture of OURS is holding, so a band drag can never drop the
        // selection out of a hand-set line's own drag.
        HandLinesSelectionGuard();
        // P-TH3-PB-UI: the editor band's native resize — read the live anchors,
        // the number follows (never write the band mid-drag: writing a
        // natively-dragged object cancels its drag, the measured MT4 fact).
        if(sparam == TH3_BASE_EDITOR) { TH3BaseEditorOnDrag(); return; }
        if(StringFind(sparam, "ABCD_Pattern_") == 0 && StringFind(sparam, "_Point_") > 0) {
            int pointPos = StringFind(sparam, "_Point_");
            string baseName = StringSubstr(sparam, 0, pointPos);
            string pointName = StringSubstr(sparam, pointPos + 7);

            if(pointName != "A" && pointName != "B" && pointName != "C" && pointName != "D") return;
            SetActiveABCDPattern(baseName);

            // SMART MAGNET: snap to nearest OHLC within 5 pips
            string draggedPoint = baseName + "_Point_" + pointName;
            datetime newTime = (datetime)ObjectGetInteger(0, draggedPoint, OBJPROP_TIME, 0);
            double newPrice = ObjectGetDouble(0, draggedPoint, OBJPROP_PRICE, 0);

            int barIndex = iBarShift(NULL, 0, newTime);
            if(barIndex >= 0) {
                double high = iHigh(NULL, 0, barIndex);
                double low = iLow(NULL, 0, barIndex);
                double open = iOpen(NULL, 0, barIndex);
                double close = iClose(NULL, 0, barIndex);

                double pipSize = GetCachedPipSize();
                double distToHigh = MathAbs(newPrice - high) / pipSize;
                double distToLow = MathAbs(newPrice - low) / pipSize;
                double distToOpen = MathAbs(newPrice - open) / pipSize;
                double distToClose = MathAbs(newPrice - close) / pipSize;

                double snapThreshold = 5.0;
                double minDist = MathMin(MathMin(distToHigh, distToLow), MathMin(distToOpen, distToClose));

                if(minDist <= snapThreshold) {
                    if(minDist == distToHigh)       newPrice = high;
                    else if(minDist == distToLow)   newPrice = low;
                    else if(minDist == distToClose) newPrice = close;
                    else if(minDist == distToOpen)  newPrice = open;
                    ObjectSetDouble(0, draggedPoint, OBJPROP_PRICE, newPrice);
                }
            }

            string lineAB = baseName + "_Line_AB";
            string lineBC = baseName + "_Line_BC";
            string lineCD = baseName + "_Line_CD";
            if(ObjectFind(0, lineAB) < 0 || ObjectFind(0, lineBC) < 0) return;

            datetime tA = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 0);
            double pA = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 0);
            datetime tB = (datetime)ObjectGetInteger(0, lineAB, OBJPROP_TIME, 1);
            double pB = ObjectGetDouble(0, lineAB, OBJPROP_PRICE, 1);
            datetime tC = (datetime)ObjectGetInteger(0, lineBC, OBJPROP_TIME, 1);
            double pC = ObjectGetDouble(0, lineBC, OBJPROP_PRICE, 1);
            datetime tD = 0; double pD = 0;
            if(ObjectFind(0, lineCD) >= 0) {
                tD = (datetime)ObjectGetInteger(0, lineCD, OBJPROP_TIME, 1);
                pD = ObjectGetDouble(0, lineCD, OBJPROP_PRICE, 1);
            } else {
                string pointD = baseName + "_Point_D";
                if(ObjectFind(0, pointD) >= 0) {
                    tD = (datetime)ObjectGetInteger(0, pointD, OBJPROP_TIME, 0);
                    pD = ObjectGetDouble(0, pointD, OBJPROP_PRICE, 0);
                }
            }

            if(pointName == "A")       { tA = newTime; pA = newPrice; }
            else if(pointName == "B")  { tB = newTime; pB = newPrice; }
            else if(pointName == "C")  { tC = newTime; pC = newPrice; }
            else if(pointName == "D")  { tD = newTime; pD = newPrice; }

            // P-TH3-PB-OFF: a point drag re-anchors A/B/C/D and the step
            // re-derives from the legs + the hand-typed base — there is no
            // drawn base to carry along any more.
            DrawABCDPattern(baseName, tA, pA, tB, pB, tC, pC, tD, pD);
            TH3RegisterPattern(baseName, tA, pA, tB, pB, tC, pC, tD, pD);
        }
        // P-TH3-PB-OFF: no draggable _PBTop/_PBBottom pair ever existed (the
        // base was set through stage 5 / the leg meter, both retired), so a
        // drag of one has nothing to handle. The DELETE sweep below still
        // names them so legacy charts clean up.
        return;
    }

    // ---- Pattern deletion: full object cleanup + store unregister ----
    if(id == CHARTEVENT_OBJECT_DELETE) {
        // P-TH3-PB-UI: deleting the editor band switches the base OFF (0 =
        // the pattern TF's own ATR). The band is re-created, never
        // delete-then-created, by the sync — so a missing band here is the
        // user's own Delete.
        if(sparam == TH3_BASE_EDITOR) { TH3BaseEditorOnDelete(); return; }
        // P-TH3-DEL1 (2026-09-22) — DELETE BY PREFIX, NOT BY SUFFIX LIST.
        // The old cascade stripped one of seven known suffixes off the deleted
        // name: deleting _Line_CD, _Ray_D/_Ray_C, _CDLabel, _HitLine/_HitLabel,
        // _MPTick*, _LegPiv, _Temp_*, _Point_X, or any TH3_MP_* overlay member
        // (its own prefix never matched at all) extracted NO base and the whole
        // family stayed on the chart («حذفش میکنم همه شون حذف نمیشه»). Any
        // member reduces to the same base (TH3FamilyBaseOf: prefix + digits),
        // and ONE backward sweep kills every object wearing it — caption rows
        // and plate, targets, zones and borders, proof, temps, legacy PB names
        // and the overlay — whatever the deleted member was. Rare event, so one
        // sweep is the whole extra load; stray echoes (our own deletes queuing
        // behind us) exit on the guard: unregistered base with no anchors left.
        // P-TH3-DEL2 (2026-09-22) -- OUR OWN DROPS MUST NOT WIPE US.
        // The DEL1 sweep made EVERY member's delete cascade -- including the
        // drops our own draws queue behind them: a base commit re-steps every
        // pattern (UpdateAllTH3Objects), a redraw with no mother match drops
        // the TH3_MP_* overlay, and the queued OBJECT_DELETE used to wipe the
        // whole ABCD («وقتی بیس رو انتخاب میکنم abcd حذف میشه»). Now the
        // ANCHORS decide: points and leg lines intact + this second still
        // fresh from a draw = own maintenance, healed back off the store's
        // own anchors; anything else = a broken family, wiped whole.
        string baseName = TH3FamilyBaseOf(sparam);
        if(baseName == "") return;
        // Residue of a never-registered base is the restore path's own job.
        if(TH3PatternStoreFind(baseName) < 0) return;
        // P-TH3-DEL3 (2026-09-22) — THE CAPTION IS DISPLAY, NEVER A DELETE
        // TRIGGER. P-TH3-INFO-10 made the plate's VISIBILITY its existence, so
        // SetActiveABCDPattern/Verify/Draw drop plates as ROUTINE maintenance;
        // each drop queued an OBJECT_DELETE whose base reduced to the family,
        // the anchors were (correctly) alive, and the window below — closed the
        // moment the last draw ended — sent the sweep to WIPE a healthy ABCD.
        // Repro: clicking the base band deselects -> SetActive("") -> every
        // plate on the chart goes («وقتی بیس رو انتخاب میکنم abcd حذف میشه»).
        // Rows and plate are rebuilt by their own owners (the heal net,
        // P-TH3-INFO-11), so a HEALTHY family returns here on any caption drop.
        // The anchors test is not decoration: a family that is ALREADY broken
        // (P-TH3-RESTORE's orphan sweep drops exactly those captions) must still
        // die whole, and the caption rows are the objects that carry its delete
        // events — without this term broken leftovers would linger forever.
        if(TH3IsInfoLabelName(sparam) && TH3FamilyAnchorsAlive(baseName)) return;
        // P-TH3-DEL3: WALL clock. TimeCurrent only moves on ticks, so a drop
        // queued behind a multi-second redraw read the tick-time window as
        // closed on a live chart and wiped the family behind its own draw.
        // P-TH3-PB-DRAG-LOCK (2026-09-22): the window is 5 s, not 1 s. A
        // band-anchor resize can drag for several seconds (and the user's
        // hand keeps the OBJECT_DRAG stream busy while it does), and a single
        // MP_* drop queued mid-drag reads the 1 s window as already closed
        // on a slow chart and wipes a healthy ABCD — the report that survived
        // the DEL3 fix. 5 s is still well below a user-driven manual delete.
        if(TH3FamilyAnchorsAlive(baseName)
           && GetTickCount() - g_th3OwnDeleteMs <= 5000)
        {
            TH3Pattern patH;
            if(TH3PatternStoreGet(baseName, patH))
                DrawABCDPattern(baseName,
                                patH.A.time, patH.A.price,
                                patH.B.time, patH.B.price,
                                patH.C.time, patH.C.price,
                                patH.D.time, patH.D.price);
            return;
        }
        // A hand-broken family (or a deliberately deleted member): one
        // prefix sweep kills every object wearing the base, whatever the
        // deleted member was.
        {
            string delMP = "TH3_MP_" + baseName + "_";
            for(int k = ObjectsTotal(0, -1, -1) - 1; k >= 0; k--) {
                string onm = ObjectName(0, k, -1, -1);
                if(onm == baseName || StringFind(onm, baseName + "_") == 0
                   || StringFind(onm, delMP) == 0)
                    ObjectDelete(0, onm);
            }
            // P-TH3-INFO-01: the caption leaves through its family owner — the
            // sweep above already took the rows, this keeps the owner contract
            // (and the 8p mutant) honest on the delete path.
            TH3InfoFamilyDelete(baseName);
            if(g_activeABCDPattern == baseName) SetActiveABCDPattern("");
            TH3PatternStoreRemove(baseName);
            ThrottledChartRedraw();
        }
        return;
    }
}

//+------------------------------------------------------------------+
//| Toggle TH3 Tool (V key) - start/cancel drawing session           |
//|                                                                  |
//| P-UI-96 (2026-09-19) — `fromRingItem`: the ring item and the V key |
//| are the SAME toggle (one owner, two surfaces), but the ring needs  |
//| the one thing a keyboard toggle does not: the press that armed the |
//| session must not be spent as pivot X. It arrives here through        |
//| `TH3SessionStart(fromRingItem)` so the debounce that already exists |
//| rejects it. The default keeps the keyboard path exactly as it was.  |
//+------------------------------------------------------------------+
void ToggleTH3Tool(const bool fromRingItem = false) {
    if(!inpEnableTH3Tool) return;

    if(inpTH3DrawingMode == TH3_MODE_ABCD) {
        if(!TH3SessionActive()) {
            // P-TH3-PB-UI: one gesture at a time — a draw takes the clicks.
            if(s_th3BaseMarkArmed) TH3BaseMarkCancel("draw started");
            TH3SessionStart(fromRingItem);
        } else {
            TH3SessionCancel();
        }
    }
}


#endif // TH3_TOOL_C_MQH
