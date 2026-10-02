// EventHandlers_Objects.mqh - EventHandlers split 2026-09-29: exact lines 2946-4270 of EventHandlers.mqh, byte-identical, zero renames.
#ifndef EVENT_HANDLERS_OBJECTS_MQH
#define EVENT_HANDLERS_OBJECTS_MQH


//+------------------------------------------------------------------+
//| OnCalculate Handler (matching MT5: tick throttle + cache inv.)   |
//+------------------------------------------------------------------+
//==============================================================================
// P-PERF-04 EVENT BUDGET — measure the paths the user FEELS
//
// P-PERF-02/03 instrumented the TICK path, which is why its fixes were real but
// incomplete: the complaints that survived were about INTERACTION — working
// with the chart, with the panel, and switching timeframe. None of those paths
// had a single line of measurement, so they could only be guessed at. These two
// helpers turn the next report into a named phase too. They log AT MOST one
// line per 2 s and only when the budget was blown, so the fast path pays one
// GetTickCount subtraction.
//==============================================================================
#define P_P4_EVENT_WARN_MS  40    // one chart event (chart handler + UI handler)
#define P_P4_INIT_WARN_MS   150   // attach / timeframe switch (OnInit+OnDeinit)
#define P_P4_MOVE_WARN_MS   20    // P-PERF-15: one cursor-move pass (ring + panel + hold)
#define P_P4_CLICK_WARN_MS  20    // P-PERF-26: one object-click pass (button + panel + apply)
static uint s_p4LogGateMs = 0;

// P-PERF-26: THE LEDGER WAS UNREADABLE, AND THAT COST A WHOLE CYCLE.
//
// Every perf line printed the raw chart-event id, so the reader had to REMEMBER
// what "id=1" meant. The project's own record shows the price of guessing: the
// 485-578 ms spikes were filed as "the cursor-move path" (P-PERF-15/16 notes),
// and the fix was aimed at hover work - while the constant is actually
// CHARTEVENT_OBJECT_CLICK. Measured, not recalled: the MQL4 compiler itself was
// asked (case-value collision probe) and reports
//   KEYDOWN=0 OBJECT_CLICK=1 OBJECT_DRAG=2 OBJECT_ENDEDIT=3 CLICK=4
//   OBJECT_DELETE=6 CHART_CHANGE=9 MOUSE_MOVE=10
// so id=1 is a BUTTON PRESS on the ring/panel - i.e. exactly the
// "toggling a switch takes half a second" the user reports - and no id=10 line
// exists because hover work is cheap. The ledger now prints the name next to
// the number, so the next report cannot be mis-read.
string P4EventName(const int id)
{
    if(id == CHARTEVENT_KEYDOWN)        return "KEYDOWN";
    if(id == CHARTEVENT_OBJECT_CLICK)   return "OBJ_CLICK";
    if(id == CHARTEVENT_OBJECT_DRAG)    return "OBJ_DRAG";
    if(id == CHARTEVENT_OBJECT_ENDEDIT) return "OBJ_ENDEDIT";
    if(id == CHARTEVENT_CLICK)          return "CLICK";
    if(id == CHARTEVENT_OBJECT_DELETE)  return "OBJ_DELETE";
    if(id == CHARTEVENT_CHART_CHANGE)   return "CHART_CHANGE";
    if(id == CHARTEVENT_MOUSE_MOVE)     return "MOUSE_MOVE";
    return "UNKNOWN";
}

void P4ReportSlow(const string what, const uint ms, const uint budget)
{
    if(ms < budget) return;
    uint now = GetTickCount();
    if(s_p4LogGateMs != 0 && now - s_p4LogGateMs < 2000) return;
    s_p4LogGateMs = now;
    _LOG_GATE_W Print("[W][PERF] ", what, " took ", (int)ms, "ms (budget ", (int)budget, "ms)");
}

string P4MsTag(const uint ms) { return IntegerToString((int)ms); }

//==============================================================================
// P-PERF-32 — ONE OWNER FOR THE STRUCTURE SWITCHES (card 11 rows 1-6)
//
// The master / L1-L5 switches change NO geometry (the level SET is
// switch-invariant; they only choose zone colours), yet they rode
// REFRESH_BUFFERS into a full RedrawAllObjects: geometry-key miss,
// whole-family recompute and re-assert, overrides flush — inside the click.
// On a weak PC the press felt dead. So the switch never reaches the render:
// the owner sets the state, persists the OV_ key (P-UI-02: REFRESH_NONE rows
// must save explicitly), repaints the recoloured zones via
// StructureRecolourWalk, and forces the discrete-action repaint. Steady
// frames skip on the unchanged signature; the geometry key keeps the switch
// terms, so any LATER real render recomputes with live switches and the
// walk can never desync it. idx: 0 = master, 1-5 = L1-L5.
//
// The settle step is shared with the batch (P-UI-66): a group press defers the
// walk + repaint to the end of the batch so one press still costs ONE of each.
//==============================================================================
static int s_structSwitchBatch = 0;   // >0 = a group press owns the settle

void StructureSwitchSettle(const uint p32t, const int idx, const bool visible)
{
   RuntimeSettingsSaveOverridesThrottled();
   int touched = StructureRecolourWalk();
   P4ReportSlow("structure toggle [idx=" + IntegerToString(idx) +
                " on=" + IntegerToString(visible ? 1 : 0) +
                " touched=" + IntegerToString(touched) +
                " cache=" + IntegerToString(CacheGetSize()) + "]",
                GetTickCount() - p32t, P_P4_MOVE_WARN_MS);
   RepaintForDiscreteAction();
}
void SetStructureVisible(const int idx, const bool visible)
{
   uint p32t = GetTickCount();
   if(idx <= 0)      g_showStructure = visible;
   else if(idx == 1) g_showStructureL1 = visible;
   else if(idx == 2) g_showStructureL2 = visible;
   else if(idx == 3) g_showStructureL3 = visible;
   else if(idx == 4) g_showStructureL4 = visible;
   else              g_showStructureL5 = visible;
   // P-UI-66: a GROUP press (the dual row's ALL cell) writes several switches in
   // ONE event. Every write must land - state, persisted OV_ key - but the walk
   // and the repaint are per PASS, not per switch: five switches meant five
   // recolour walks and five forced repaints for one press, which is the cost
   // P-PERF-32 exists to remove. The panel opens the batch, this owner defers,
   // and the batch's owner closes it ONCE.
   if(s_structSwitchBatch > 0) return;
   StructureSwitchSettle(p32t, idx, visible);
}

void StructureSwitchBatchBegin()
{
   s_structSwitchBatch++;
}

//--- close the batch: one persist, ONE recolour walk, one repaint - and the
//--- walk is unconditional (it reads the live flags, not this press's list), so
//--- any subset of switches is settled by it.
void StructureSwitchBatchEnd()
{
   if(s_structSwitchBatch > 0) s_structSwitchBatch--;
   if(s_structSwitchBatch > 0) return;
   StructureSwitchSettle(GetTickCount(), -1, false);
}

//==============================================================================
// P-PERF-32b — THE TRIGGER SWITCH PAINTS IN ITS OWN EVENT (one owner).
//
// The same shape as SetStructureVisible above, for the family whose feedback
// used to be the RENDER's: the state, the persisted key, the family's own mask
// walk (`TriggerFamilyWalk` — the family answers to a mask now, see RenderZones'
// OFF branch) and the discrete repaint. «سطوح تریگر دیر خاموش و روشن میشه» is
// exactly what the old shape produced: the press raised `g_redrawTHLevelsNeeded`
// and the pixels waited for a heavy frame — on a weak PC a visibly dead press.
//
// THREE CALLERS, ONE OWNER: the T hotkey, the ring's TRIGGER light and the
// card's SHOW row (BiotakPanels_Apply, case 0 row 3). They used to keep three
// copies of the state write; none of them may keep a copy of the walk.
//
// `g_redrawTHLevelsNeeded` still goes up, and it is not a leftover: it is what
// BUILDS the family when the chart carries none yet (a fresh attach starts with
// the overlay OFF, so the first ON has nothing to un-mask). The frame then
// re-asserts the same masks through the same writer and changes no pixel —
// `[P-KEY] T settled … ms=` is that reconciliation, on the record.
//
// Cost: one bounded cache walk per press (guarded masks; ZERO writes when the
// family is already right) + one ChartRedraw, both stated by the applied line.
//==============================================================================
void SetTriggerLevelsVisible(const bool on)
{
   uint t32b = GetTickCount();
   g_triggerLevelsEnabled = on;   // P-UI-93: one writer for the restored state
   GlobalVariableSet("Biotak_TriggerLevels_" + GetCachedChartIdStr(), on ? 1.0 : 0.0);
   int seen = 0;
   int written = TriggerFamilyWalk(on, seen);
   g_redrawTHLevelsNeeded = true;   // P-PERF-21: a re-render, never a clear
   // P-PERF-32b: `bands=0` on the way ON means the chart carries no band to
   // un-mask - a family the render has not materialised (a fresh attach, mid zones
   // were off, a wipe). The walk cannot invent geometry, so the build is OWED here:
   // without it the press would paint nothing and wait for the next tick or the
   // 250 ms timer (P-KEY-01's own defect), with it the pump runs the frame in THIS
   // event. It is the one press that still pays a render, and it can only be the
   // first one.
   if(on && seen == 0)
      ScheduleHeavyFrame("trigger-build");
   RepaintForDiscreteAction();      // P-PERF-24: the press paints NOW
   // P-KEY-PROBE — PRESS → PAINTED, the number the latency report is judged by.
   // `bands=` is the family the walk decided and `masks=` what the chart actually
   // paid for; `bands=0` says the render still has to build it (the one slow
   // direction left, and it can only happen once per attach).
   Print("[P-KEY] T applied on=", (on ? 1 : 0),
         " ms=", (int)(GetTickCount() - t32b),
         " bands=", seen, " masks=", written);
}

// P-PERF-10: named-phase report for the INIT path (attach / TF switch). The
// tick ledger cannot attribute OnInit's 3.2-4.1 s — it measures a frame, not
// the init sequence — so the entry passes its two halves and OnInitHandler
// leaves the four domain phases in globals.
string P4InitLedgerTag(const uint indMs, const uint uiMs)
{
    return " [ind=" + IntegerToString((int)indMs) +
           " ui=" + IntegerToString((int)uiMs) +
           " settings=" + IntegerToString((int)g_pInitMsSettings) +
           " hist=" + IntegerToString((int)g_pInitMsHistory) +
           " base=" + IntegerToString((int)g_pInitMsBase) +
           " atr=" + IntegerToString((int)g_pInitMsAtr) + "]";
}

//+------------------------------------------------------------------+
//| P-BK-46 — THE KNOT'S OWN EngSL: THE ASK / PUSH PAIR (one owner).   |
//|                                                                   |
//| The Base/Knot trade is measured in EngSL of the knot's OWN TF     |
//| (its base class), and EngSL is TRADE-PLAN MATH — TradePlanFormulas,
//| which sits ABOVE BaseKnotTool (the layer law, the same one P-BK-29's
//| movement step obeys). So the tool is never asked to read it here:  |
//| it SAYS which TFs its live boxes call their own, this layer       |
//| computes exactly those (TradePlanEngOf — the number the TRex       |
//| card's Eng.SL row shows, rounded to the same whole pips) and       |
//| pushes the pairs back, where the domain stores them and rebuilds   |
//| a knot's stop / target the moment one really moved.               |
//|                                                                   |
//| One ask per pump round (500 ms), no boxes = one TF (this chart's,  |
//| which is what the sizing preview uses), and every value comes from |
//| the SAME multi-TF ATR cache the strip and the trade block read, so |
//| a warm chart pays cache hits and compares.                        |
//|                                                                   |
//| P-BK-50 (2026-09-15) — THE PLAN'S TARGET LEGS RIDE THE SAME CALL.  |
//| One plan per TF answers BOTH numbers a knot draws: the risk        |
//| (`plan.eng` = EngSL, the very number the TRex card's Eng.SL row   |
//| prints: one decimal since P-TRADEPLAN-DEC, 2026-09-16) and the    |
//| targets (`plan.tp1..3` — the very numbers the corner row prints as  |
//| `#TP1+n #TP2+n #TP3+n`). So the box can never disagree with that    |
//| row about a target, and the tool is never asked to read ATR.       |
//|                                                                   |
//| P-BK-51 (2026-09-15) — AND SO DOES THE HUNTER LEG. The user's own   |
//| rule («و برای گره etr میشه به اندازه huntsl محل ورود») sizes an     |
//| ETR/CTR/OTR entry by ONE HuntSL, so `plan.hunter` — the leg the     |
//| TRex card prints as `Hunter SL:` — is pushed per TF beside EngSL.   |
//| The ask list grew with it: the ENTRY is read on the knot's own TF |
//| and the STOP on the node TYPE'S own time (P-BK-83 — one rung above |
//| the class for ETR, two for CTR, three for OTR), so that rung is    |
//| asked for as well                                                  |
//| (BaseKnotEngNeeds walks each box' own TF AND its measure TF).       |
//+------------------------------------------------------------------+
void BaseKnotEngPump()
{
   int      mins[BK_ENG_ROW_MAX];
   datetime anchors[BK_ENG_ROW_MAX];   // P-BK-79: the bar each row is read at (0 = the live row)
   double   pips[BK_ENG_ROW_MAX];
   double   hunts[BK_ENG_ROW_MAX];   // P-BK-51: HuntSL, the second measure a knot draws with
   double   tp1[BK_ENG_ROW_MAX];
   double   tp2[BK_ENG_ROW_MAX];
   double   tp3[BK_ENG_ROW_MAX];
   double   ab[BK_ENG_ROW_MAX];      // P-BK-92: that TF's TH points in PRICE units
   ArrayInitialize(ab, 0.0);      // explicit: the push below reads it for every `mins`
   int n = BaseKnotEngNeeds(mins, anchors);
   for(int i = 0; i < n && i < BK_ENG_ROW_MAX; i++)
   {
      // P-BK-50: ONE plan call feeds all four pushes (it computes the strip ATRs
      // this loop used to ask for), and a plan that is not warm pushes ZEROES — the
      // absence the tool then reports instead of drawing a guessed level.
      // P-BK-79: AND AT THE ROW'S OWN ANCHOR. `anchors[i]` is the box' `storyT` — the bar
      // its story ended on — so the ATRs, the EngSL, the Hunter leg and the three targets
      // are the ones THAT bar's market gave, not today's drifted ones («با گذشت زمان ممکن
      // 40 بشه یا 10 بشه»). 0 stays the live row the sizing preview asks for.
      STradePlan plan;
      if(!TradePlanCompute(mins[i], plan, anchors[i]))
      {
         pips[i] = 0.0; hunts[i] = 0.0; tp1[i] = 0.0; tp2[i] = 0.0; tp3[i] = 0.0;
         ab[i]   = 0.0;
         continue;
      }
      // P-TRADEPLAN-DEC (2026-09-16): the pushed risk is the CARD'S OWN NUMBER —
      // `plan.eng`, one decimal — not a second rounding of `engTrue`, so the box and the
      // `Eng.SL` row it is checked against cannot drift apart. A sub-pip size survives
      // the push (EURUSD M1: 0.3); only a TF the plan has no value for pushes 0, which
      // stays the tool's word for "never pushed" (BaseKnotEngPips).
      pips[i] = (plan.eng > 0.0 ? plan.eng : 0.0);
      // P-BK-51: HUNTSL RIDES THE SAME ROW — the very leg the TRex card prints as
      // `Hunter SL:`, which is what an ETR/CTR/OTR knot's entry waits for.
      hunts[i] = (plan.hunter > 0.0 ? plan.hunter : 0.0);   // P-TRADEPLAN-DEC: 0.1 pip, same rule
      tp1[i]  = (plan.tp1 > 0 ? (double)plan.tp1 : 0.0);
      tp2[i]  = (plan.tp2 > 0 ? (double)plan.tp2 : 0.0);
      tp3[i]  = (plan.tp3 > 0 ? (double)plan.tp3 : 0.0);
      // P-BK-75: AND THE SAME PLAN CARRIES THE MOVEMENT ABILITY. `plan.ownPips` is
      // THIS TF's composite ATR (TradePlanStripPips -> CalculateWeightedATR, the very
      // number the strip and the trade block read), so the knot's type is decided by
      // the SAME ATR the rest of the chart is drawn with — not a second reading that
      // could drift from it. Pips -> price here, because the knot's box is in prices.
      // P-BK-79: at THIS ROW'S anchor, so `plan.ownPips` is the anchored composite — the
      // same number the row's own EngSL was divided out of, and the number the box' type
      // is read against (BaseKnotAbilityGet at the same anchor).
      // P-BK-92: THE RUNG'S OWN TH CARRIES THE MOVEMENT ABILITY (P-BK-75's ATR
      // rule below, reversed per user: type + step read TH, plan stays ATR).
      ab[i] = THAbilityPrice(mins[i], anchors[i]);
   }
   BaseKnotEngPush(mins, anchors, pips, hunts, tp1, tp2, tp3, n);
   // P-BK-92: P-BK-75's block below now hands TH per TF (reversed per user).
   // P-BK-75 — THE NODE'S TYPE IS ITS HEIGHT AGAINST THE MOVEMENT ABILITIES OF ITS OWN
   // TF (user: «به جای th از atr استفاده بشه»), so the pump hands ONE number per TF in —
   // that TF's ATR — exactly as it already hands EngSL in: one row per TF the boxes
   // asked for, off the SAME `mins` list, so the ask and the answer cannot disagree
   // about which TFs a box draws with. The RATIOS (0.25 / 0.50 / 1.00) live in the
   // tool's own table, never here: a second place that halved an ATR would be a second
   // owner of the rule. A TF whose ATR is not warm pushes 0, which BaseKnotAbilityGet
   // reads as an ABSENCE: the type stays BK_NODE_NONE and the tooltip says so.
   // P-BK-79: one row per (TF, anchor) — the same list, the same keys.
   BaseKnotAbilityReset();
   for(int i = 0; i < n && i < BK_ENG_ROW_MAX; i++)
      BaseKnotAbilityPush(mins[i], anchors[i], ab[i]);
}

int OnCalculateHandler(const int rates_total, const int prev_calculated, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], const long &volume[], const int &spread[]) {
    static uint s_lastCPUTime = 0;
    static int s_cpuWarningCount = 0;
    uint startTime = GetTickCount();

    // P-UI-98d: the click's double-click window commits here too — a click that
    // never moves the mouse again still sets its line (two stamp compares).
    HandsetClickSweep();

    if(IsIndicatorHidden())
    {
        return(rates_total);
    }

    // PERF: Cache Bid/Ask once per tick (moved after hidden check)
    CacheTickPrices();

#ifdef BUILD_LITE
    // P-BK-13: Lite has no RefreshKitOnBar pump — heal BK boxes (direction
    // auto-follow + fill/edge/TP) from the tick path, same 500 ms cadence
    // Full gets from RefreshUIPerTick. Domain-only, Lite-safe.
    static uint s_bkLitePumpMs = 0;
    {
       uint bkNow = GetTickCount();
       // P-BK-29/47: the Full pump (BiotakKit) pushes the movement step for the
       // note's break story (the type is the node's length and needs no size);
       // TH is below BaseKnotTool (THCalculations, P-BK-92, was ATR), so Lite —
       // which has no RefreshOnBar — hands the same TH points in from its tick pump.
       // P-BK-46: and the same pump hands the knots' EngSL risk in (BaseKnotEngPump).
       if(bkNow - s_bkLitePumpMs >= 500) { s_bkLitePumpMs = bkNow; BaseKnotStepPush(THAbilityPrice(Period(), 0)); BaseKnotEngPump(); BaseKnotSyncBadges(); TradePlanLiveTick(); }
    }
#endif

    // P-UI-53: the drag lock's watchdog. Steady state: one bool read per tick; the
    // KEYSTATE probe and the restore run only while a gesture still holds the lock.
    CustomPriceDragHealStale();
    // P-UI-98j: the step-1 pair's own net - a stashed handle whose object
    // vanished behind our back (suppressed delete event) is re-created on the
    // next frame. Throttled inside, reads-only while healthy.
    Step1HandleHealMissing();

    // P-TH3-P6: the six-condition pivot markers (self-throttled to a new bar
    // or 5 s; the scan underneath is cached per new bar of its own TF).
    // UI half only — Lite compiles no renderer (P-BUILD-01).
#ifndef BUILD_LITE
    TH3PivotMarkersUpdate();
    TH3HitPivotForward();   // P-TH3-STEP-04: the active pattern's ladder follows its own reaction
#endif

    static uint s_lastTickMs = 0;
    static double s_lastPrice = 0;
    static datetime s_lastBarTime = 0;
    static int s_lastPeriod = -1;
    static double s_lastCustomPrice = 0;

    uint nowMs = GetTickCount();
    double currentPrice = (rates_total > 0) ? close[rates_total-1] : 0;
    datetime currentBarTime = (rates_total > 0) ? time[rates_total-1] : (datetime)0;
    int currentPeriod = Period();
    double currentCustomPrice = g_customTHStartPrice;

    double priceChangePercent = 0;
    if(s_lastPrice > 0 && currentPrice > 0) {
        priceChangePercent = MathAbs((currentPrice - s_lastPrice) / s_lastPrice) * 100.0;
    }
    bool significantPriceChange = (priceChangePercent > 0.1);
    bool barsChanged = (currentBarTime != s_lastBarTime && s_lastBarTime != 0);
    bool isNewBar = barsChanged;
    bool timeframeChanged = (currentPeriod != s_lastPeriod && s_lastPeriod != -1);
    bool customPriceChanged = false;
    if(g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) {
        customPriceChanged = (MathAbs(currentCustomPrice - s_lastCustomPrice) > EPSILON_PRICE);
    }

    // Tick throttle: skip redundant ticks within 50ms
    bool tickThrottled = (nowMs - s_lastTickMs < 50 && s_lastTickMs != 0);

    // Cache invalidation flags
    int invalidationFlags = CACHE_INV_NONE;
    if(timeframeChanged) invalidationFlags |= CACHE_INV_TIMEFRAME;
    if(barsChanged) invalidationFlags |= CACHE_INV_NEW_BAR;
    if(customPriceChanged) invalidationFlags |= CACHE_INV_CUSTOM_PRICE;
    if(invalidationFlags != CACHE_INV_NONE) {
        ApplyCacheInvalidation(invalidationFlags, s_lastPeriod, currentPeriod, s_lastCustomPrice, currentCustomPrice);
    }

    // VIEWLOCK-OFF:
    //if(g_viewRestorePending) {
    //    if(ViewLockRestore()) g_viewRestorePending = false;
    //}

    if(rates_total > 0)
    {
        // FIX: If not fully initialized, don't throttle redraws to ensure levels appear as soon as data is ready
        if(tickThrottled && !isNewBar && !g_redrawTHLevelsNeeded && g_initialized &&
           !g_forceClearOnNextDraw && !significantPriceChange &&
           !timeframeChanged && !customPriceChanged) {
            return rates_total;
        }

        LogRedrawDecision(isNewBar, timeframeChanged, customPriceChanged,
                          g_redrawTHLevelsNeeded, g_forceClearOnNextDraw,
                          significantPriceChange, tickThrottled);

        s_lastTickMs = nowMs;
        s_lastPrice = currentPrice;
        s_lastBarTime = currentBarTime;
        s_lastPeriod = currentPeriod;
        s_lastCustomPrice = currentCustomPrice;

        // P-PERF-49b: name the two spans OUTSIDE RedrawAllObjects() as well, so
        // `rest` narrows to "inside RedrawAllObjects but after the overlay slot"
        // instead of hiding the pre-work (price/invalidation/decisions, which on
        // a timeframe switch is ApplyCacheInvalidation's WIPE) together with the
        // post-work (ChartRedraw + the object-count check) in one anonymous pile.
        g_p3MsPre = GetTickCount() - startTime;
        TH3_PROF_START(RedrawCall);
        RedrawAllObjects(g_redrawTHLevelsNeeded || g_forceClearOnNextDraw);
        TH3_PROF_END(RedrawCall);

        // P-PERF-02: ChartRedraw after RedrawAllObjects — but ONLY when that
        // frame actually painted. The idle frames (nothing pending) used to ask
        // the terminal for a full chart repaint at tick rate anyway.
        uint afterRedrawMs = GetTickCount();
        if(g_lastRedrawDidWork) {
            g_lastRedrawDidWork = false;
            ThrottledChartRedraw();
        }
        g_p3MsPost = GetTickCount() - afterRedrawMs;

        if(barsChanged || s_lastBarTime == 0) {
            // PERF: Use cached object count
            int totalObjects = GetCurrentObjectCount();
            if(totalObjects > MAX_SAFE_OBJECTS && totalObjects < CRITICAL_OBJECT_LIMIT) {
                #ifdef ENABLE_DEBUG_LOGS
                if(s_cpuWarningCount % 10 == 0) {
                    Print("[W][GEN] Performance Warning: ", totalObjects, " objects on chart (recommended max: ", MAX_SAFE_OBJECTS, ")");
                    Print("[D][GEN] [CLEAN] Consider reducing inpMaxLevels for better performance");
                }
                #endif
                s_cpuWarningCount++;
            }
            else if(totalObjects >= CRITICAL_OBJECT_LIMIT) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("[E][GEN] [CRIT] CRITICAL: ", totalObjects, " objects approaching MT4 limit (64000)!");
                Print("[D][GEN] [CLEAN] EMERGENCY: Using indicator-scoped cleanup...");
                #endif
                EmergencyCleanupIndicatorObjects(inpObjectPrefix);
            }
        }
    }

    uint elapsed = GetTickCount() - startTime;
    if(elapsed > CPU_WARNING_MS) {
        // P-PERF-03: name the phase. The ledger costs a few int adds per frame
        // and turns "it is slow somewhere" into "levels took 1780 of 1797 ms".
        // P-PERF-49 (2026-09-16): THE LEDGER CAN NO LONGER LIE.
        //
        // The six slots are successive deltas of ONE GetTickCount() clock, all
        // taken inside RedrawAllObjects(), which itself runs inside the span
        // `elapsed` measures - so their sum is always <= elapsed, and the
        // difference is work the ledger never named. That difference was not
        // small. Today's live MT5 log carried a 94 ms frame as
        // "[levels=16 labels=0 ...]" with 78 ms owned by NOBODY, and every
        // other slot read 0 on 191 of 191 frames - because a phase shorter than
        // one 15.625 ms tick is invisible to this clock, not free.
        //
        // `rest` is what makes those two facts visible instead of silent: either
        // a named phase owns the frame's time, or `rest` does. An un-instrumented
        // tail can no longer hide behind a zero - including the code after the
        // overlay slot (custom-price / start-point work), which was never billed
        // to any slot at all. Integer math on a string that was being built
        // anyway, and a pure addition, so every existing reader still matches.
        uint phaseSum = g_p3MsBase + g_p3MsAtr + g_p3MsHistory +
                        g_p3MsLevels + g_p3MsLabels + g_p3MsOverlay +
                        g_p3MsPre + g_p3MsPost;
        uint restMs = (elapsed > phaseSum) ? (elapsed - phaseSum) : 0;
        string phase = " [base=" + IntegerToString((int)g_p3MsBase) +
                       " atr=" + IntegerToString((int)g_p3MsAtr) +
                       " hist=" + IntegerToString((int)g_p3MsHistory) +
                       " levels=" + IntegerToString((int)g_p3MsLevels) +
                       " labels=" + IntegerToString((int)g_p3MsLabels) +
                       " overlay=" + IntegerToString((int)g_p3MsOverlay) +
                       " pre=" + IntegerToString((int)g_p3MsPre) +
                       " post=" + IntegerToString((int)g_p3MsPost) +
                       " rest=" + IntegerToString((int)restMs) + "]";
        if(elapsed > CPU_CRITICAL_MS) {
            _LOG_GATE_E Print("[E][GEN] [CRIT] CRITICAL CPU: OnCalculate took ", elapsed, "ms!", phase, " Reduce inpMaxTHLevels!");
        }
        else if(s_lastCPUTime == 0 || GetTickCount() - s_lastCPUTime > 60000) {
            _LOG_GATE_W Print("[W][GEN] CPU Warning: OnCalculate took ", elapsed, "ms (threshold: ", CPU_WARNING_MS, "ms)", phase);
            s_lastCPUTime = GetTickCount();
        }
    }

    return rates_total;
}

//+------------------------------------------------------------------+
//| Apply Lines Visibility State to All Line Objects                 |
//|                                              |
//|                                                                  |
//| Called after RedrawAllObjects to ensure g_linesVisible is       |
//| respected for all line objects (HLINE and TREND)                 |

//+------------------------------------------------------------------+
//| Empty-box border segments (_B_Top/_B_Bottom/_B_Left) are part of |
//| the zone BOX, not lines - the L key and line visibility must not |
//| toggle them (same behavior as the filled box rectangle).         |
//+------------------------------------------------------------------+
// P-PERF-23c: _B_Right was MISSING here while the L switch's cache walk
// (SetAllLineObjectsVisibility, VisibilityManager) excluded ALL FOUR. Two owners
// of the same question disagreed, so the F switch's show branch treated the
// right border segment as a level LINE: with lines hidden it hid that edge of
// the empty box and left the other three - a box with a side missing, straight
// out of "the indicator hides parts of my chart for no reason". The four
// segments are one family (the box), and no visibility switch owns them.
bool IsZoneBoxBorderObject(const string name)
{
    if(StringFind(name, "_B_Top") >= 0)    return true;
    if(StringFind(name, "_B_Bottom") >= 0) return true;
    if(StringFind(name, "_B_Left") >= 0)   return true;
    if(StringFind(name, "_B_Right") >= 0)  return true;
    return false;
}

//==============================================================================
// P-UI-61 — the drag has ONE anchor writer and ONE frame owner. Reported: the
// custom-price drag lags and the released line rebuilds the ladder elsewhere —
// both halves were one defect, because `g_customTHStartPrice` (the value the whole
// ladder derives from) was written INSIDE the redraw throttle: every event in the
// 50 ms window was DROPPED, not deferred (line ~30 Hz, anchor 20 Hz), and the
// CARRY channel never persisted, so the release re-resolved from a key older than
// the gesture and overwrote the anchor with it. Rules now:
//   * `CustomPriceDragAnchorSet(price)` — the only writer of the anchor during a
//     gesture, persisting through the P-UI-56 writer (steady state: one compare);
//   * `CustomPriceDragFrame(force)` — the only caller of the heavy pass from the
//     drag, so both channels share ONE budget; a refused frame is OWED.
//   * the release settles from the OBJECT (the one value MT4 keeps exact).
//==============================================================================
static bool s_cpDragFrameOwed = false;

bool CustomPriceDragAnchorSet(const double price)
{
    if(!MathIsValidNumber(price) || price <= 0.0) return false;
    if(MathAbs(price - g_customTHStartPrice) <= _Point * 0.5) return false;
    g_customTHStartPrice = price;
    g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
    g_customPriceKeyboardOverride = true;
    // P-UI-56: the same ONE writer as every other placement path. Persisting here
    // is what makes the resolver agree with the anchor instead of re-anchoring the
    // release to an older key.
    CustomPricePersistPlacement(price);
    g_redrawTHLevelsNeeded = true;
    return true;
}

void CustomPriceDragFrame(const bool force)
{
    s_cpDragFrameOwed = true;                    // owed until this call really paints
    uint nowMs = GetTickCount();
    bool ranFrame = (force || nowMs - g_lastDragRedrawTime > DRAG_REDRAW_THROTTLE_MS);
    uint t0 = nowMs;
    if(ranFrame)
    {
        // P-UI-53: re-assert the view lock on the same budget (read-guarded: three
        // reads, a write only on drift).
        CustomPriceDragReassertLock();
        RedrawAllObjects(true);
        ThrottledChartRedraw();
        g_lastDragRedrawTime = nowMs;
        s_cpDragFrameOwed = false;
    }
#ifndef BUILD_LITE
    // P-UI-152 (2026-10-02) — THE SHARED DRAG FRAME, PRICED. User order: «هنوز هم
    // مثل خود خط کاستوم پرایس ریل تایم واقعی نشده ... به دقت بررسی کن». This is
    // the ONE function both hand-set gestures pace their pixels with, so it is the
    // only place the two can be compared: `who=` names the channel, `run=0` is a
    // frame the 50 ms budget refused (the cheap path), `ms=` is what the frame
    // that DID run cost, and `lv=` is the LEVELS phase of the ledger it filled
    // (P-PERF-03) — i.e. whether the price is the family re-derivation or the rest
    // of the frame. One bounded line per 25 ms of a live gesture, on the FLUSHED
    // channel (AGENTS.md: a witness IS the flushed file; the journal is a buffer,
    // P-DRAW-126). Read the pair as: the drag's own cadence is the gap between two
    // lines, and "real time" is that gap being the mouse's own, not the frame's.
    if(g_s1DragLive || g_customPriceLineDragging)
    {
        static uint s_dfWitMs = 0;
        uint dfNow = GetTickCount();
        if(dfNow - s_dfWitMs >= 25)
        {
            s_dfWitMs = dfNow;
            DrawStripDiagEmit("[drag] who=" + (g_s1DragLive ? "s1" : "cp") +
                              " run=" + IntegerToString(ranFrame ? 1 : 0) +
                              " ms=" + IntegerToString((int)(dfNow - t0)) +
                              " lv=" + IntegerToString((int)g_p3MsLevels) +
                              " t=" + IntegerToString((int)dfNow));
        }
    }
#endif
}

bool CustomPriceDragFrameOwed() { return s_cpDragFrameOwed; }

//==============================================================================
// P-UI-100 (2026-09-22) — THE POLICY THAT KEEPS A HAND-SET LINE OUT OF SOMEBODY
// ELSE'S GESTURE.
//
// The law, the primitives and the cost live in UtilityFunctions
// (HandLinesSelectionGuard / HandLineDropSelection / HandLinesRestorePrice).
// What belongs HERE is the part only the gesture state can answer: which of the
// two lines a live gesture of ours is holding, and what to do when a claimed
// gesture turns out to be a DRAW.
//
// The section sits HERE, after the drag-frame and the anchor writers, because
// the restore re-asserts exactly what the settle does — the number, the anchor,
// the marker, the frame — and every one of those writers must already be
// declared.
//==============================================================================

// P-UI-100b: THE ONE WRITER of "the line goes back where the grab found it".
// The order is the settle's own: the price, the anchor it is persisted under,
// the selection the draw's own claim left on it, the marker that shows it, and
// the forced frame that repaints the ladder derived from it.
void CustomPriceRestoreGrabPrice()
{
    if(!g_customPriceLineCreated) return;
    if(!(s_ownGrabPrice > 0.0) || !MathIsValidNumber(s_ownGrabPrice)) return;
    HandLinesRestorePrice(g_customPriceHorizontalLineName, s_ownGrabPrice);
    g_customTHStartPrice = s_ownGrabPrice;
    CustomPriceDragAnchorSet(s_ownGrabPrice);
    HandLineDropSelection(g_customPriceHorizontalLineName);   // the draw's own selection goes
    CustomPriceMarkerSync();
    CustomPriceDragFrame(true);
}

// P-UI-100b: the detector's answer, called for EVERY foreign object the terminal
// creates (the OBJECT_CREATE branch of OnChartEventHandler owns the name test
// that decides "foreign").
//
// Two timings, both real (which one a build uses is the terminal's business):
//   * the object exists from the PRESS -> the stamp is set before the first move,
//     and the claim's own test refuses the gesture: nothing moves, nothing to undo;
//   * the object appears at the RELEASE -> the gesture is already claimed, so it
//     is marked a DRAW: the carry stands down from here and the release restores
//     the price the grab found.
void CustomPriceForeignDrawSeen()
{
    s_cpForeignDrawUntil = GetTickCount() + CP_DRAW_WITNESS_MS;
    if(g_customPriceLineDragging)
    {
        s_drawNotGrab = true;   // the live gesture is a draw, not a grab
        return;
    }
    // The create landed AFTER our release: the gesture is over, so the restore
    // runs here instead. Guarded by the grab's own price — nothing clears it
    // until the next claim — and by "no gesture of ours is live".
    if(s_ownGrabPrice > 0.0 && !g_s1DragLive && !g_s1OwnActive)
        CustomPriceRestoreGrabPrice();
}

// P-UI-100: THE NET UNDER EVERY PATH WE DO NOT SEE.
//
// The guard has a call site at every gesture START this indicator can observe,
// but the terminal performs gestures whose events another layer consumes whole
// (the box tool's draw session returns before the custom-price block — see
// P-UI-100's note in BaseKnotTool), so the invariant also needs an owner that
// does not depend on any event reaching us. This is it: the 250 ms timer.
//
// The button gate is deliberate and conservative (`UILeftButtonUp`: BOTH
// conventions must agree the button is free — P-UI-73's rule for the same probe).
// A press we did not see belongs to somebody else's gesture, and the selection it
// made is theirs to end; the first timer after the release heals it. A gesture of
// OURS is never healed either way: the guard skips the lines its own gesture
// holds, so a live drag cannot lose its selection to the net (P-BK-15).
void HandLinesSelectionNet()
{
    if(!UILeftButtonUp()) return;
    HandLinesSelectionGuard();
    // P-UI-100c: and the same net asks the second half of the invariant — the
    // line must sit on the anchor the ladder is drawn from. Gated by the same
    // "no button is down" witness, so it can never touch a live drag; a line
    // that really drifted is put back within one 250 ms beat.
    HandLineHealToAnchor();
}

//==============================================================================
// P-UI-98 — THE FIRST STEP IS DRAGGABLE (custom-price mode). Requested: the custom
// line AND step 1 selectable / draggable / deselectable (only step 1), the chosen
// step carrying to the other timeframes at the same ratios.
// THE HANDLE: the trigger line ONE STEP from the custom price line, picked by
// GEOMETRY at render time (`Step1HandlePick`), never by rung number — `_Above_1` /
// `_Below_2`, since the below rung-1 line lands exactly ON the custom line (98f).
// THE MATH: F = |dragged - start| / the mode's natural first step, ONE MULTIPLIER
// on the factory's own stepSizes, CHART-SCOPED so every TF re-scales by the same F
// and the ratios the course defines survive.
// THE GESTURE: MT4's own OBJECT_DRAG, sharing the custom-price drag's ONE frame
// budget and view lock; never write the dragged line's own price mid-gesture
// (P-BK-15); the release settles with one forced frame and DROPS MT4's selection
// (P-UI-45); a motionless release is healed by `CustomPriceDragHealStale`.
// OFF: resets with the placement (R key) and on REASON_REMOVE.
//==============================================================================
static double s_s1GrabPrice = 0.0;   // the handle's price at the claim (the echo stamp's base)
static bool   s_s1GrabNamed = false;
static string s_s1GrabName  = "";
// P-UI-98f: the handle's DISTANCE from the custom price line and the factor in
// force at the press. They are the gesture's own baseline: the drag scales F by
// how far the handle travelled RELATIVE to the distance it was grabbed at, so a
// touch that moves nothing can never rescale anything - whatever the ladder's
// mode, the drawn pair sits at `k * F * step`, and in the SS/LS and Factor modes
// `k` is not exactly 1, so the absolute reading (|dragged - start| / natural)
// would snap F a few percent the instant the hand closed.
static double s_s1GrabDist   = 0.0;
static double s_s1GrabFactor = 0.0;
// P-UI-98f: the line's price as of the PREVIOUS held event. It is what tells a
// live terminal drag from a dead one (see Step1HandleOwnDragMove's stand-down).
static double s_s1SeenPrice  = 0.0;

// THE gesture's own state, cleared in ONE place (P-UI-98f). TWO paths end a
// gesture - the settle and the stale-drag heal - and for a while only one of
// them cleared the statics, so a gesture healed by the net left the echo stamp's
// base, the press baseline and the seen-price behind: the NEXT gesture skipped
// its own capture (`s_s1GrabNamed` still true for the same name) and every
// release was stamped against a price from a gesture that was already over. One
// owner, both callers.
void Step1GestureStateClear()
{
    g_s1OwnActive = false;
    g_s1OwnLastWrite = 0.0;
    g_s1OwnGrabPrice = 0.0;
    g_s1OwnGrabCursorPrice = 0.0;
    s_s1GrabPrice = 0.0;
    s_s1GrabNamed = false;
    s_s1GrabName = "";
    s_s1GrabDist = 0.0;
    s_s1GrabFactor = 0.0;
    s_s1SeenPrice = 0.0;
}

// The handle match. P-UI-98f: the handle is the line ONE STEP from the custom
// price line (picked by geometry in LevelPipeline's Step1HandlePick), which is
// `_Above_1` above but `_Below_2` below — the below side's rung-1 line is the
// zone boundary drawn ON the custom price line. A suffix test cannot name that
// pair, so the ONE owner of the answer is the render's own stash: the face
// owner wrote both names when it wrote both faces, and the gesture, the drag
// channel and the click contract all ask that stash. The side is answered the
// same way (`Step1LineIsAbove`), never by parsing a name.
bool Step1LineIsDragHandle(const string name)
{
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return false;
    if(name == "") return false;
    if(g_s1MarkPeriod != Period()) return false;   // another TF's pair is not this one
    return (name == g_s1MarkAboveName || name == g_s1MarkBelowName);
}

// Which side of the custom price line does the handle sit on? The stash names
// the line; the rendered direction is what the name was stashed under.
bool Step1LineIsAbove(const string name)
{
    return (g_s1MarkAboveName != "" && name == g_s1MarkAboveName);
}

// The OBJECT_DRAG channel. Runs on every step of MT4's native drag.
void Step1LineDragApply(const string name)
{
    // First event of a gesture: the view is the gesture's until the release
    // (idempotent — a live custom-price lock is re-asserted, never re-captured).
    if(!g_s1DragLive)
    {
        g_s1DragLive = true;
        g_s1DragName = name;
        CustomPriceDragLockOn();
    }
    s_cpLockActMs = GetTickCount();   // the heal's activity stamp is the gesture's

    // P-UI-100b: the gesture is still OURS (the settle and the guard must keep
    // treating it as such), but it is a DRAW: the ladder must not re-step with it.
    if(s_drawNotGrab) return;

    double start = GetMidpointPrice(g_thStartPointType);
    double natural = NaturalFirstStep();
    double dragged = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
    if(!(start > 0.0) || !(natural > 0.0) || !(dragged > 0.0) ||
       !MathIsValidNumber(start) || !MathIsValidNumber(dragged))
        return;
    if(!s_s1GrabNamed || s_s1GrabName != name)   // the echo stamp's base: price AT the claim
    {
        s_s1GrabPrice = dragged;
        s_s1GrabName = name;
        s_s1GrabNamed = true;
        // the gesture's baseline (P-UI-98f), taken on the line's resting price
        s_s1GrabDist = MathAbs(dragged - start);
        s_s1GrabFactor = StepOverrideFactor();
    }

    // P-UI-98f: the side comes from the stash, never from the name's tail — the
    // below handle is `_Below_2` (see Step1LineIsDragHandle). And the distance
    // read off the custom price line is the STEP the ladder wears: every drawn
    // trigger line sits a whole number of steps from it (`start + k*step`
    // above, `start - k*step` below), so `newFirst` is F x natural at rest and
    // a no-move touch can never rescale anything.
    bool above = Step1LineIsAbove(name);
    double newFirst = above ? (dragged - start) : (start - dragged);
    // the handle icon rides its own drag (the render skips the dragged line, so
    // the stash is stale until settle — the drag channel IS the live answer)
    if(above)
    {
        g_s1MarkAbovePrice = dragged;
        HandsetHandleAt(S1MarkName(1), dragged, S1_HANDLE_RES);
    }
    else
    {
        g_s1MarkBelowPrice = dragged;
        HandsetHandleAt(S1MarkName(-1), dragged, S1_HANDLE_RES);
    }
    // The wrong side (dragged across the start) or a sub-point step is not a
    // small step, it is no step — ignore it; the release frame snaps the line
    // back to the step the ladder actually wears.
    if(newFirst < _Point) return;

    // THE STEP THE HAND IS DRAWING. Relative to the grab whenever the gesture
    // carries a baseline (both our own carry and a native drag: the baseline is
    // taken on the first event of either), so the handle keeps its own offset
    // from the custom price line and the ladder scales with the hand exactly.
    // With no baseline (a degenerate grab ON the line) the absolute reading is
    // the fallback, and it is the same number in the uniform modes: the handle
    // sits at `F * natural` there, so `newFirst / natural` IS the factor the
    // drop position asks for.
    double candidate = (s_s1GrabDist > 0.0 && s_s1GrabFactor > 0.0)
                       ? (s_s1GrabFactor * (newFirst / s_s1GrabDist))
                       : (newFirst / natural);
    if(!MathIsValidNumber(candidate)) return;
    if(MathAbs(candidate - StepOverrideFactor()) <= 0.0005) return;   // dead band: half a permille
    StepOverrideFactorSet(candidate);
    // P-UI-98e: THE F ACTUALLY CHANGED, SO THE LADDER IS STALE. The levels block
    // is gated on this flag (`if (inpShowTHLevels && (g_redrawTHLevelsNeeded ||
    // g_buildStage != 0))`), and the custom price line's own live follow sets it
    // on every anchor change (`CustomPriceDragAnchorSet`) - without it here the
    // frame ran, the signature said "geometry changed", and the level family was
    // still skipped: the ladder only caught up on the next unrelated frame, i.e.
    // the step-1 drag did NOT move the other levels in the moment.
    g_redrawTHLevelsNeeded = true;
    CustomPriceDragFrame(false);   // the shared 50 ms budget; the refused frame is owed
#ifndef BUILD_LITE
    const bool paid = !CustomPriceDragFrameOwed();   // this very event's frame, or one owed
    // P-UI-150: THE DRAG'S OWN WITNESS, on the FLUSHED channel — AGENTS.md: "a witness
    // IS the flushed file", because MT4's journal is a RAM buffer and a Print answers
    // «nothing happened» long after the hand moved (P-DRAW-126). One bounded line per
    // 25 ms of a live gesture, and only when the factor really changed (the dead band
    // above returns first), so the next report is a number instead of an impression:
    // the factor the hand drew, the side, WHO owns the movement (our carry or the
    // terminal's own drag), and whether this event PAID the shared frame or owes it.
    // "ladder follows the hand" then reads as: a run of these lines with paid=1.
    {
        static uint s_s1WitMs = 0;
        uint s1w = GetTickCount();
        if(s1w - s_s1WitMs >= 25)
        {
            s_s1WitMs = s1w;
            DrawStripDiagEmit("[s1] drag f=" + DoubleToString(candidate, 5) +
                              " side=" + (above ? "above" : "below") +
                              " own=" + IntegerToString(g_s1OwnActive ? 1 : 0) +
                              " paid=" + IntegerToString(paid ? 1 : 0) +
                              " owed=" + IntegerToString(CustomPriceDragFrameOwed() ? 1 : 0));
        }
    }
#endif
}

// P-UI-98e / P-LM-21: THE DRAGGABLE FLAG IS BORROWED, AND RETURNED. The terminal
// re-arms its own per-object drag on every paint while SELECTABLE sits on the
// line, so a gesture that owns the movement must take the flag off for its whole
// length - and give it back on BOTH exits, or the line stays deaf afterwards.
// Guarded: one read, a write only on drift.
void Step1DragSelectable(const string name, const bool on)
{
    if(name == "") return;
    if(ObjectFind(0, name) < 0) return;
    if((bool)ObjectGetInteger(0, name, OBJPROP_SELECTABLE) != on)
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, on);
}

// The release. Called from the button-up mouse-move latch (the same branch that
// settles the custom-price line) and from the stale-drag heal.
void Step1DragSettle()
{
    if(!g_s1DragLive) return;
    g_s1DragLive = false;
    string name = g_s1DragName;
    g_s1DragName = "";
    // P-UI-98e: the borrowed flag goes back exactly as the pair's own state wants
    // it - armed and in custom-price mode means grabbable again (and the forced
    // frame below re-owns it anyway); otherwise the face owner's next frame parks
    // the pair.
    if(g_s1OwnBorrowed)
    {
        g_s1OwnBorrowed = false;
        Step1DragSelectable(name, g_s1LinesArmed &&
                                  g_thStartPointType == TH_START_POINT_CUSTOM_PRICE);
    }
    // P-UI-98d: stamp the echo only when the gesture MOVED the handle — a
    // jitter-click's phantom gesture must not block its own commit click.
    double settled = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
    bool s1Moved = (settled > 0.0 && s_s1GrabNamed && name == s_s1GrabName &&
                    MathAbs(settled - s_s1GrabPrice) > _Point * 0.5);
    if(s1Moved)
        g_s1JustDraggedMs = GetTickCount();
    // P-UI-98h: a gesture that MOVED the line is a drag by definition, never a
    // click: the deferred SET a press echo armed dies with it, or the sweeper
    // commits it the moment the button comes up and the handle goes inert right
    // after a working drag («دیگه نمیشه درگش کرد»). The native channel
    // (OBJECT_DRAG) reaches here too - the claim's own cancel cannot, because
    // that gesture never claimed.
    if(s1Moved) { g_s1SetPending = ""; g_s1SetPendingMs = 0; }
    // P-UI-100b (2026-09-22): A DRAW SETTLES BACK, exactly as the custom price line
    // does. The handle's price is put back where the claim found it and the step
    // factor the press was made under is re-asserted, so a fib or a box drawn from
    // a rung-1 line leaves the ladder exactly as the user had it — the two lines
    // answer one law, not two.
    if(s_drawNotGrab)
    {
        s_drawNotGrab = false;
        if(s_s1GrabNamed && s_s1GrabName == name && s_s1GrabPrice > 0.0)
            HandLinesRestorePrice(name, s_s1GrabPrice);
        if(s_s1GrabFactor > 0.0 && MathAbs(s_s1GrabFactor - StepOverrideFactor()) > 0.0005)
        {
            StepOverrideFactorSet(s_s1GrabFactor);
            g_redrawTHLevelsNeeded = true;
        }
        CustomPriceDragFrame(true);
    }
    // P-UI-98e/98f: the carry's own state goes with the gesture - a stale
    // g_s1OwnActive would keep the held-move pass running for a drag that is
    // over, and a stale g_s1OwnLastWrite / grab base would make the next grab
    // compare and scale against a price this gesture wrote. ONE owner clears it,
    // and it runs AFTER the echo stamp (which reads the grab base it clears).
    Step1GestureStateClear();
    CustomPriceDragFrame(true);   // the gesture's last pixel is painted from the final F
    CustomPriceDragLockOff();     // the view is the user's again (idempotent)
    // P-UI-45: drop the selection the grab left behind — a SELECTED line is
    // moved by MT4 on every later drag anywhere on the chart. Guarded write.
    if(name != "" && (bool)ObjectGetInteger(0, name, OBJPROP_SELECTED))
        ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
}

//==============================================================================
// P-UI-98e — THE STEP-1 HANDLE CARRIES ITSELF (2026-09-22).
//
// Reported: «الان step اول در هر تایم که درش هستیم قابل درگ کردن نیستش ... در هر
// تایم همون اولین step که رسم میشه قابل درگ و مثل خط کاستوم ریل تایم باشه بدون
// بار اضافی». The P-UI-98 gesture handed the movement to MT4's OWN per-object
// drag (the line's SELECTABLE flag plus OBJECT_DRAG), and that is the half the
// custom price line ALREADY stopped trusting: P-UI-49c's finding — "MT4's
// per-object native drag needs the terminal to grab the object first and several
// builds never engage it at all" — is exactly why the line carries itself. So
// the handle now wears the SAME channel, with the same numbers (the tolerance,
// CP_DRAG_SLOP, the absolute-off-the-grab carry, the frozen stand-down that
// keeps our write off a live terminal drag, P-BK-15): the drag no longer depends
// on a terminal behaviour the project has already measured as unreliable.
//
// The math, the icon and the frame budget are the P-UI-98 owners
// (`Step1LineDragApply` + `CustomPriceDragFrame`), reused, never duplicated —
// this block only decides WHO moves the line and by HOW MUCH. The native channel
// stays live beside it (the frozen test stands our writes down the moment the
// terminal moves the line itself), so whichever of the two the build supports,
// the handle follows the hand.
//
// Cost: on a PRESS EDGE one conversion plus two compares, and while the gesture
// is live the carry's own three reads. The steady state — no gesture — is the
// one `g_s1OwnActive` compare on a mouse move, inside the block the custom price
// line already runs.
//==============================================================================

//==============================================================================
// P-UI-148 (2026-10-02) — THE ROW THE HAND SEES IS THE LINE'S OWN PRICE.
//
// Reported: «وقتی هر کدوم از قرمزها رو درگ میکنم ریل تایم سطوح مثل خود خط
// کاستوم جابجا نمیشه و وقتی درگ رها بشه سطوح میاد». The ladder followed the hand
// per held event only when OUR carry owned the gesture; every other route (the
// press edge that was missed, the native-only drag waiting to be adopted) asked
// `Step1HandleUnderCursor`, and that test measured the cursor against the price
// the RENDER last stashed. During a drag the render is one THROTTLED frame behind
// the hand (50 ms, DRAG_REDRAW_THROTTLE_MS) and on a native-only gesture it is the
// ONLY writer of the stash - so within a frame or two the row test answered about
// a price the line had already left, the recovery and the adoption both refused,
// and the gesture lived on the terminal's own sparse reports until the release
// (which is why the ladder arrived all at once at the end).
//
// The fix is a READER: the stash still owns WHICH line is the handle (the whole
// point of P-UI-98f - never a name tail), but the PRICE the test compares against
// is the line object's own `OBJPROP_PRICE`, the one value the terminal keeps
// exact - the same reading P-UI-61 settled the custom price line from. The stash
// is the fallback for the one case it exists for: a handle whose object is
// missing (P-UI-98j's net re-creates it; the test must not invent a price).
//
// Cost: on the press edge / adoption / recovery only - never a steady frame -
// two ObjectFind + two ObjectGetDouble, and zero writes. Nothing the render
// produced changes; the test just stops reading a stale copy of it.
//==============================================================================
// The price of the row `name` as the chart really carries it.
double Step1HandleRowPrice(const string name, const double stash)
{
    if(name == "") return 0.0;
    if(ObjectFind(0, name) < 0) return stash;   // object gone: the stash is all we have
    double live = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
    if(!(live > 0.0) || !MathIsValidNumber(live)) return stash;
    return live;
}

// Is the press ON a rung-1 handle? The render's own stash answers WHICH line is
// the handle (the two names the face owner already had in hand), so the test never
// walks the chart. The tolerance is the custom price line's own: the line as DRAWN
// plus a few pixels, which is what the terminal itself uses. P-UI-98e: the test
// does NOT ask the armed state — the CLICK contract reaches a SET handle through
// it (that is how a double-click re-arms one), while the DRAG's claim below asks
// `g_s1LinesArmed` itself. P-UI-148: the two PRICES are the lines' own.
bool Step1HandleUnderCursor(const int x, const int y, string &handleName)
{
    handleName = "";
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return false;
    if(g_s1MarkPeriod != Period()) return false;   // P-UI-98e: THIS tf's step 1 only
    if(!g_linesVisible || IsIndicatorHidden()) return false;
    if(g_s1MarkAboveName == "" && g_s1MarkBelowName == "") return false;
    int heightPx = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    double span = WindowPriceMax() - WindowPriceMin();
    if(heightPx <= 0 || !(span > 0.0)) return false;
    // P-UI-98h: the AFFORDANCE is the 15 px circle the hand grabs (its half is
    // 7 px), not the 1 px line under it. The old gate (width + 4 = 5 px)
    // rejected a press on the icon's own rim, and the press edge has already
    // carried the cursor a few px past the press point by the time this test
    // runs - «راحت درگ نمیشه کردنش». The custom price line still wins any
    // tie (its claim runs first, `!onCustomLine`), so the wider rim cannot
    // steal that gesture.
    int tolPx = HANDSET_HANDLE_HALF + (int)inpCustomPriceLevelWidth + 3;
    if(tolPx < 10) tolPx = 10;
    double tolPrice = span * ((double)tolPx / (double)heightPx);
    int subW = 0; datetime cursorT = 0; double priceAtCursor = 0.0;
    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, priceAtCursor)) return false;
    // the NEAREST armed row wins: a press between the two rung-1 lines must
    // belong to the one the user sees under the hand. P-UI-148: each row's own
    // price, read from the object, so a hand mid-drag is never measured against
    // the frame the render has not painted yet.
    double bestDist = tolPrice;
    double aboveRow = Step1HandleRowPrice(g_s1MarkAboveName, g_s1MarkAbovePrice);
    double belowRow = Step1HandleRowPrice(g_s1MarkBelowName, g_s1MarkBelowPrice);
    if(g_s1MarkAboveName != "" && aboveRow > 0.0 &&
       MathAbs(aboveRow - priceAtCursor) <= bestDist)
    {
        bestDist = MathAbs(aboveRow - priceAtCursor);
        handleName = g_s1MarkAboveName;
    }
    if(g_s1MarkBelowName != "" && belowRow > 0.0 &&
       MathAbs(belowRow - priceAtCursor) <= bestDist)
        handleName = g_s1MarkBelowName;
    return (handleName != "");
}

//==============================================================================
// P-UI-98i — THE STEP-1 HANDLE DRAGS LIKE THE CUSTOM PRICE LINE (2026-09-22).
//
// Reported: «همون step درگ میشه ... روان درگ نمیشه هی قطع میشه». Three
// asymmetries with the custom-price channel made the handle harder to grab
// and easier to lose mid-gesture than the line beside it:
//
// (1) NEAREST WINS, not custom-always-wins. The old press-edge gate refused
// the handle whenever the cursor was ALSO on the custom price line
// (`!onCustomLine`), so on a coarse chart - where one step is a few pixels -
// a press aimed at the red handle always dragged the green line instead.
// Both rows answer now and the nearer price wins the gesture (an exact tie
// stays with the line, the placement's anchor); the loser yields through the
// same single terms as before (`s1Claimed` below, this gate here).
//
// (2) A MISSED PRESS EDGE STILL CLAIMS. The edge is seen on the first MOVE
// after the press, so a press whose first move never arrived here (a release
// off-chart leaves the shared `s_dragDownSeen` latch set) had no edge to arm
// on and the handle was dead until some unrelated click reset the latch -
// while the custom-price claim beside it recovered through MT4's own
// selection (`terminalGrab && atLineNow`). A SELECTED handle with the cursor
// really on its row claims the same way now.
//
// (3) A NATIVE-ONLY DRAG IS ADOPTED. When MT4's own per-object drag moves the
// line first (no own claim yet), `g_s1DragLive` is up through the OBJECT_DRAG
// channel but `g_s1OwnActive` is not - and that gesture then lived or died by
// OBJECT_DRAG alone (the P-UI-49c builds where it stutters cut the drag).
// The held pass adopts such a gesture into our own carry (same latch, same
// borrow, same relative math), so both channels drive it from then on.
//==============================================================================

// Is the press at (x,y) nearer to the step-1 row `s1Row` than to the custom
// price line? Press-edge only (one conversion per gesture). An exact tie -
// within half a point - stays with the line: it is the placement's anchor,
// and the old rule must remain the answer there.
bool Step1NearerThanCustom(const int x, const int y, const string s1Row)
{
    if(s1Row == "" || !g_customPriceLineCreated) return false;
    int subW = 0; datetime cursorT = 0; double cursorPrice = 0.0;
    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, cursorPrice)) return false;
    if(!(cursorPrice > 0.0) || !MathIsValidNumber(cursorPrice)) return false;
    double linePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(!(linePrice > 0.0) || !MathIsValidNumber(linePrice)) return false;
    double s1Price = 0.0;
    // P-UI-148: the row's OWN price, like every other reader of the pair. A stale
    // stash in this comparison mis-assigns the gesture (the press aimed at the red
    // circle takes the green line instead, and the handle then never gets carried);
    // the objects are the one copy the drag itself keeps current.
    if(s1Row == g_s1MarkAboveName) s1Price = Step1HandleRowPrice(g_s1MarkAboveName, g_s1MarkAbovePrice);
    else if(s1Row == g_s1MarkBelowName) s1Price = Step1HandleRowPrice(g_s1MarkBelowName, g_s1MarkBelowPrice);
    else return false;
    if(!(s1Price > 0.0) || !MathIsValidNumber(s1Price)) return false;
    return (MathAbs(s1Price - cursorPrice) + _Point * 0.5 < MathAbs(linePrice - cursorPrice));
}

// The press-edge claim. TRUE means this gesture belongs to the handle - the
// caller must then leave the custom price line's own claim alone (one cursor,
// one gesture). The view lock, the selection face and the grab price are taken
// here, in that order, and the grab price is recorded BEFORE any write: it is
// the settle's echo stamp base (a drag release must not set the line it moved).
bool Step1HandleOwnClaim(const string handle, const int x, const int y)
{
    if(handle == "") return false;
    if(!g_s1LinesArmed) return false;      // a SET handle is inert: nothing may grab it
    if(ObjectFind(0, handle) < 0) return false;
    double linePrice = ObjectGetDouble(0, handle, OBJPROP_PRICE, 0);
    if(!(linePrice > 0.0) || !MathIsValidNumber(linePrice)) return false;
    g_s1DragLive = true;
    g_s1DragName = handle;
    // P-UI-98g: a hand on the line IS the request for its handle - the circles
    // appear while the gesture runs (and stay after it), so a drag started on a
    // line the user never clicked does not look like nothing happened.
    g_s1HandleShown = true;
    g_s1OwnActive = true;
    // P-UI-98h: a hand on the line CANCELS any pending SET - the press echo of
    // THIS press may have armed one (OBJECT_CLICK arrives on the press), and
    // the sweeper would commit it the moment the button comes up, i.e. right
    // after a drag that worked («دیگه درگ نمیشه»).
    g_s1SetPending = "";
    g_s1SetPendingMs = 0;
    g_s1OwnGrabY = y;
    g_s1OwnGrabPrice = linePrice;
    g_s1OwnLastWrite = 0.0;
    g_s1OwnGrabCursorPrice = 0.0;
    s_s1SeenPrice = linePrice;      // P-UI-98f: the gesture's first reference price
    {
        int gW = 0; datetime gT = 0;
        if(!ChartXYToTimePrice(0, x, y, gW, gT, g_s1OwnGrabCursorPrice))
            g_s1OwnGrabCursorPrice = 0.0;
    }
    // THE BORROW HAPPENS HERE, BEFORE ANY WRITE (P-LM-21's rule, at the earliest
    // moment the gesture is provably ours): the terminal arms its own per-object
    // drag at the PRESS and re-arms it on every paint while SELECTABLE sits on the
    // object, so a gesture that means to own the movement must take the flag off
    // first or the two drags fight - «سریع قطع میشه».
    g_s1OwnBorrowed = true;
    Step1DragSelectable(handle, false);
    // the face: MT4's own selection is what a grabbed line looks like. Written
    // ONLY when the terminal did not already select it - a property write on the
    // object it is dragging cancels that drag (P-BK-15) - and the carry below
    // then owns the movement, exactly as it does on the custom price line.
    if(!(bool)ObjectGetInteger(0, handle, OBJPROP_SELECTED))
        ObjectSetInteger(0, handle, OBJPROP_SELECTED, true);
    CustomPriceDragLockOn();        // the view is the gesture's until the release
    Step1LineDragApply(handle);     // the ONE math owner, and the baseline of the echo test
    return true;
}

// The held pass: our own carry, then the P-UI-98 owner for the factor, the icon
// and the frame. `wishPrice` is the grab price plus the cursor's TRAVEL since
// the grab (never the cursor's own price), so the press offset survives, the
// line can never snap onto the cursor, and a click's jitter - below CP_DRAG_SLOP
// - opens no door at all: a click stays a click.
void Step1HandleOwnDragMove(const int x, const int y)
{
    if(!g_s1OwnActive || g_s1DragName == "") return;
    if(ObjectFind(0, g_s1DragName) < 0) { Step1DragSettle(); return; }   // gone under the hand
    // P-UI-100b (2026-09-22): AND THE HANDLE STANDS DOWN FOR A DRAW TOO. The step-1
    // claim runs BEFORE the custom-price claim at the press edge, so a fib or a box
    // drawn from a rung-1 line is claimed by THIS channel - and the carry would move
    // the handle and re-step the whole ladder with it. The gesture is left alone
    // (its own settle still runs at the release and puts the handle back); only the
    // writes stop.
    if(s_drawNotGrab) return;
    double current = ObjectGetDouble(0, g_s1DragName, OBJPROP_PRICE, 0);
    if(!(current > 0.0) || !MathIsValidNumber(current)) return;
    // P-UI-98i: the press latch is retried, never frozen. The grab cursor price
    // is taken once at the claim; when that conversion failed the carry's gate
    // below could never open and - with the draggable flag borrowed - NO channel
    // moved the line at all. One conversion per held event until it lands.
    if(!(g_s1OwnGrabCursorPrice > 0.0))
    {
        int rW = 0; datetime rT = 0; double rP = 0.0;
        if(ChartXYToTimePrice(0, x, y, rW, rT, rP) && rP > 0.0 &&
           MathIsValidNumber(rP))
            g_s1OwnGrabCursorPrice = rP;
    }
    if(MathAbs(y - g_s1OwnGrabY) >= CP_DRAG_SLOP && g_s1OwnGrabCursorPrice > 0.0)
    {
        // (the draggable flag was already borrowed at the CLAIM, before any write:
        // P-LM-21, and earlier than the first travel, so nothing re-arms behind
        // us - see Step1HandleOwnClaim.)
        // THE TERMINAL OWNS THE MOVEMENT WHILE IT IS MOVING (P-UI-98f). A write on
        // the object MT4 is dragging cancels that drag (P-BK-15), so our carry
        // stands down then - but "the price differs from our last write" is NOT
        // the same question, and reading it as one froze the gesture: the borrow
        // takes SELECTABLE off at the claim, MT4's armed drag ends on its next
        // paint, and a price it moved ONCE before that left `current != ref` for
        // the rest of the gesture with nobody moving anything - the hand kept
        // dragging, the line stood still. So the stand-down asks the price to
        // have changed since the PREVIOUS held event: live terminal, hands off;
        // price at rest, the carry takes over (and a write lands only when the
        // cursor really moved, below).
        double ref = (g_s1OwnLastWrite > 0.0) ? g_s1OwnLastWrite : g_s1OwnGrabPrice;
        bool terminalLive = (MathAbs(current - ref) >= _Point * 0.5) &&
                            (MathAbs(current - s_s1SeenPrice) >= _Point * 0.5);
        s_s1SeenPrice = current;
        if(!terminalLive)
        {
            int subW = 0; datetime curT = 0; double cursorPrice = 0.0;
            if(ChartXYToTimePrice(0, x, y, subW, curT, cursorPrice) && cursorPrice > 0.0)
            {
                double wishPrice = g_s1OwnGrabPrice + (cursorPrice - g_s1OwnGrabCursorPrice);
                if(wishPrice > 0.0 && MathAbs(wishPrice - current) > _Point * 0.5)
                {
                    ObjectSetDouble(0, g_s1DragName, OBJPROP_PRICE, wishPrice);
                    g_s1OwnLastWrite = wishPrice;
                    s_s1SeenPrice = wishPrice;   // we are the last mover
                }
            }
        }
    }
    Step1LineDragApply(g_s1DragName);   // the factor, the icon, the shared frame budget
}

//==============================================================================
// P-UI-98e — THE CLICK CONTRACT, AND WHY IT CANNOT LIVE ON ONE EVENT.
//
// User order: «خط کاستوم پرایس و خط step اول وقتی بعد جابجایی روش کلیک شد ست
// نهایی بشه و با دبل کلیک فعال بشه تا زمانی که ست نهایی نشده آزادانه درگ بشه».
// The handle's click used to arrive ONLY through MT4's own `OBJECT_CLICK` on the
// HLINE — the very hit test whose failure is why the drag needed an own channel
// (`P-UI-49c`), and a 15 px bitmap icon sits exactly where the user clicks. Two
// more measured MT4 facts narrow the door further: a motionless press/release
// emits no MOUSE_MOVE at all (P-BK-03, the leg meter's P-LM-13 trap), so the
// release latch can miss a still click entirely. So the click is ONE owner —
// `Step1HandleClickAt` — reached from THREE edges:
//   * our own press/release pair on the mouse stream (row + travel, below),
//   * `Step1ClickFinalize` from `CHARTEVENT_CLICK` (the button-up that carries
//     no move), and
//   * MT4's own `OBJECT_CLICK`, kept as the third opinion it always was.
// A physical click can reach that owner twice; the FIRST call answers and its
// twin is dropped inside one short window, so a double-click can never be read
// as two singles (or a single as a double) because of the transport.
//==============================================================================
// (the contract's state lives in GlobalVariables — the heal above has to consume
// a lost press, and it is defined a hundred lines before this block.)

// THE click. `name` is the rung-1 line the click landed on; the armed state is
// read as it is NOW, so a click on a SET handle is the double-click that wakes it.
void Step1HandleClickAt(const string name)
{
    if(name == "") return;
    uint now = GetTickCount();
    if(g_s1ClickHandledMs != 0 && now - g_s1ClickHandledMs < 60) return;   // the same click's twin event
    g_s1ClickHandledMs = now;
    bool dbl = (g_s1ClickLastMs != 0 && now - g_s1ClickLastMs < DOUBLE_CLICK_THRESHOLD_MS);
    g_s1ClickLastMs = now;
    if(dbl)
    {
        // the second click CANCELS the pending SET and wakes a set handle — the
        // user's «با دبل کلیک فعال بشه ... و ست نهایی بشه» pair, in one place
        g_s1SetPending = "";
        g_s1SetPendingMs = 0;
        if(!g_s1LinesArmed)
        {
            g_s1LinesArmed = true;   // re-armed: draggable again, the red handle back
            g_s1HandleShown = true;  // P-UI-98g: and revealed, like the green one
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);  // the face owner re-owns the pair + icon
        }
        return;
    }
    // P-UI-98g: THE FIRST CLICK SHOWS THE RED CIRCLES. The pair is armed from the
    // placement on (armed = the line answers a grab), but its icon is the answer
    // to a click — «فقط وقتی روش کلیک کردیم دایره ها بیاد برای درگ کردن» — and
    // that click must not be spent setting a line the user has not touched yet.
    if(!g_s1HandleShown)
    {
        g_s1HandleShown = true;
        if(g_s1LinesArmed && !g_s1DragLive)
        {
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);   // the face owner places the two circles
        }
        return;
    }
    // a click that is the ECHO of a drag release sets nothing (the stamp the
    // settle writes), so a gesture the user DRAGGED never commits under the hand
    // P-UI-98h: never arm the SET while a gesture is live - OBJECT_CLICK is
    // delivered on the PRESS, so this line is reached with the hand already
    // holding the line, and the sweeper would commit it the moment the button
    // comes up, i.e. right after a drag that worked.
    if(g_s1LinesArmed && !g_s1DragLive && now - g_s1JustDraggedMs > 350)
    {
        g_s1SetPending = name;
        g_s1SetPendingMs = now;      // HandsetClickSweep commits it past the double window
    }
}

// The candidate the PRESS EDGE recorded, answered at the button-up that carries
// no move (a motionless release emits no MOUSE_MOVE, P-BK-03). One candidate at a
// time: the row is consumed here, so a click can only be spent once.
//
// P-UI-98e: THIS IS ALSO THE GESTURE'S OWN END. The button-up mouse-move is the
// click path's sibling, and when it never arrives (the same P-BK-03 fact) the
// gesture stayed LIVE: the render kept skipping the line's writes, the borrowed
// draggable flag stayed off, and BOTH hand-set claims refused the next press until
// the 1.5 s heal — «جابجا میشه بعد دیگه نمیشه درگش کرد». So the finalize settles a
// live gesture first, and only asks the click question afterwards - and a gesture
// that WROTE a price is a drag by definition, never a click.
void Step1ClickFinalize()
{
    // P-UI-98h: A CLICK CAN BE DELIVERED ON THE PRESS - the measured MT4 fact
    // this codebase already knows from the panels (P-UI-49b / P-UI-73: «one of
    // those two is delivered on the PRESS that grabs a selectable object ...
    // the drag engaged and died immediately ... which is why it feels
    // random»). Every line below CONSUMES the row and reads the gesture as
    // over, so running it on that press echo settled the gesture the very
    // press had just claimed - the handle stopped following mid-drag - and,
    // because the gesture has not travelled a point yet, armed its deferred
    // SET against the line still under the hand: ~300 ms later the sweeper
    // committed it and no claim could start any more («هی قطع میشه موقع درگ
    // کردن», «راحت درگ نمیشه کردنش»). The witness is the project's ONE
    // button probe (P-UI-73): button still DOWN = this is the press's own
    // echo - touch NOTHING, and keep the row armed for the real release (the
    // button-up mouse move, or the click that follows it).
    if(!UILeftButtonUp()) return;
    string row = g_s1ClickRow;
    g_s1ClickRow = "";
    if(g_s1DragLive)
    {
        bool wrote = (g_s1OwnLastWrite > 0.0);
        Step1DragSettle();          // the release the mouse stream never delivered
        if(row == "" || wrote) return;
    }
    if(row == "") return;
    Step1HandleClickAt(row);
}

//+------------------------------------------------------------------+
//| P-UI-93 — ONE OWNER FOR THE WHOLE F TRANSITION.                    |
//|                                                                    |
//| The F key used to own this body inline, which is exactly why no     |
//| other surface could reach it: the panel's family rows had no way to  |
//| release the mute, so a press on a row that read OFF painted nothing  |
//| and snapped straight back. It is a function now, and the hotkey is   |
//| a short caller.                                                      |
//|                                                                    |
//| `hide` is the TARGET state, never a delta. The caller reads          |
//| IsIndicatorHidden() and inverts, so the state keeps exactly ONE      |
//| writer (SetIndicatorHiddenState) and ONE reader (IsIndicatorHidden) - |
//| the two cannot drift, which is what «همه رو هماهنگ کن» asks for.      |
//|                                                                    |
//| Returns the touched count from the show branch (-2 on the hide       |
//| branch, -1 when the cold-cache legacy scan ran) so the caller can    |
//| still log the P-PERF-31 provenance.                                  |
//+------------------------------------------------------------------+
int ApplyHideAllState(const bool hide)
{
    // P-PERF-26: the whole/level visibility switch is the action the user
    // repeats most, so its cost gets its own named line.
    // P-PERF-31: both directions now walk the object cache (plus the
    // cache size, which proves which path ran: cold-cache legacy scan
    // only right after attach).
    uint p26F = GetTickCount();
    // P-PERF-31: -2 = hide branch, -1 = cold-cache legacy scan,
    // >=0 = cache-walk writes issued by the show branch.
    int p31Touched = -2;
    // P-UI-93: the state write belongs to its ONE owner (GlobalVariables,
    // beside the reader). This used to be three inline lines that also
    // sanitised a corrupt gvar - the sanitiser moved with it.
    SetIndicatorHiddenState(hide);

    if(hide)
    {
        LOG_I(LOG_CAT_KEYS, "F key: Hiding all objects");
        // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
        // Cancel ABCD drawing session if active
        if(TH3SessionActive()) {
            TH3SessionCancel();
        }
#endif
        HideAllTHObjects();
        CleanupCustomPriceObjects(false, true);
        g_redrawTHLevelsNeeded = false;
    }
    else
    {
        LOG_I(LOG_CAT_KEYS, "F key: Showing all objects");
        // P-PERF-02: objects are visible again, so the once-per-
        // transition hide pass must be armed for the next F press.
        ResetHideAllState();
        // P-PERF-31: same decision tree the chart scan always had (ATR
        // state, trigger state, lines state), now over the object
        // cache — zero ObjectName calls, probes only for families the
        // names cannot decide. Legacy scan only on a cold cache.
        // P-PERF-41: the zone family switch is the FIFTH input. Without it
        // this branch repainted every zone rectangle OBJ_ALL_PERIODS - i.e.
        // an F press resurrected the exact family the Zones & Levels
        // switch had just turned off, and the two controls disagreed.
        //
        // P-UI-93: the families NOT named here are not a gap - the engine
        // re-asserts them on the very next frame, because each family's own
        // writer already carries `IsIndicatorHidden()` as one of its terms
        // (LabelFunctions / LevelPipeline / ObjectFunctions / UtilityFunctions
        // all read it), and this branch sets g_redrawTHLevelsNeeded below.
        // That shared term is also the answer to «چرا روی بقیه لیبلها تاثیر
        // میزاره»: the F mute is the ONE master the labels, the zones and the
        // level writer all answer to, by design.
        bool atrShouldShowF = (g_atrLabelsVisible && inpShowATRLabels);
        int shownTouched = VisibilityShowAllCached(atrShouldShowF, inpShowATRTargets,
                                                   g_triggerLevelsEnabled, g_linesVisible,
                                                   inpShowMidZones);
        p31Touched = shownTouched;
        // Restore label visibility
        ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
        ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
#endif
        ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        // P-UI-98p: no custom-line restore - the line is never painted (the
        // green circle is the placement), so the F cycle must not resurrect it
        // in any state.

        g_redrawTHLevelsNeeded = true;
        // Re-apply label visibility consistently
        string objectPrefixLocal = GetLevelObjectPrefix();
        SetATRLabelsVisibility(objectPrefixLocal, (g_atrLabelsVisible && inpShowATRLabels));
        SetTHLabelsVisibility(objectPrefixLocal, (inpShowTHLabels ? g_thLabelsMode : 0));
        // P-PERF-32b: and the TRIGGER family through its OWN owner. The walk above
        // cannot tell a trigger band from a structure band (the same `_Zone_`
        // names, and this branch's only zone input is the FAMILY switch), so it
        // would un-mask a family whose overlay is OFF. Asking the family's own walk
        // LAST, in this same event, closes that corner for every band the CACHE
        // knows — including bands outside this frame's culled list, which no render
        // would re-decide (P-VIEW-01's rule). The delete this replaced used to be
        // the only thing keeping that corner shut.
        int trigSeen = 0;
        TriggerFamilyWalk(g_triggerLevelsEnabled, trigSeen);
    }
    // P-PERF-02: masks written directly above → every stored mask is now
    // stale; the guarded writers must re-assert once on the next frame.
    BumpTfEpoch();
    g_redrawTHLevelsNeeded = true;
    P4ReportSlow("hide-all toggle (F) [hidden=" + (hide ? "1" : "0") +
                 " touched=" + IntegerToString(p31Touched) +
                 " cache=" + IntegerToString(CacheGetSize()) + "]",
                 GetTickCount() - p26F, P_P4_INIT_WARN_MS);
    return p31Touched;
}

//+------------------------------------------------------------------+
//| P-UI-93 — THE ONE WAY A CONTROL SURFACE RELEASES THE F MUTE.      |
//|                                                                   |
//| The F key and every family light / family row now answer the SAME  |
//| question (is this family painted?), so a press on a control that   |
//| READS OFF while the chart is muted has exactly one honest meaning: |
//| show me this again. Writing the family switch alone would change   |
//| nothing the user can see - the family is stored ON and would paint |
//| the moment the mute went - and the control would snap straight     |
//| back to OFF.                                                       |
//|                                                                   |
//| Both surfaces call this, never a copy of it: the ring's four       |
//| family items (BiotakMenu) and the panel's gated rows (BiotakPanels)|
//| are both included ABOVE this point in the entry, so this is the    |
//| lowest module that can own the transition for both. One walk, one  |
//| cache refresh, one forced frame.                                   |
//+------------------------------------------------------------------+
void ReleaseIndicatorMute()
{
    ApplyHideAllState(false);
    // A press repaints only its OWN control (P-UI-40's asymmetry), but the
    // mute sits on every family light and on every gated row of the open card.
    RequestUISync();
    // The walk wrote object masks directly, and the caller's own flags can be
    // REFRESH_NONE (the structure rows are exactly that), so the frame is
    // forced here - the same owner the F caller uses.
    RepaintForDiscreteAction();
}


#endif // EVENT_HANDLERS_OBJECTS_MQH
