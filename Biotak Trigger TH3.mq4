  //+------------------------------------------------------------------+
//|                                           Biotak Trigger TH3.mq4 |
//+------------------------------------------------------------------+
#property copyright "Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link      "@biotak"
#property version   "3.12"
#property strict
#property indicator_chart_window
#property description "Biotak Trigger TH3 v3.12 - Freeware, not for sale."
#property description "Trigger/TH/TH3 levels, HTF candles, hand drawings. By Biotak."

//                                                                    
// BUILD CONFIG - Must be first include!
//                      BuildConfig.mqh               
//                                                                    
#include "Biotak\BuildConfig.mqh"

#include "Biotak\MathConstants.mqh"
#include "Biotak\Logger.mqh"

#ifndef BUILD_LITE
#include "Biotak\Profiler.mqh"
#endif

#include "Biotak\PropertiesAndInputs.mqh"
#include "Biotak\ConstantsAndEnums.mqh"
#include "Biotak\ProjectConstants.mqh"
#include "Biotak\InputValidator.mqh"

//                                                                    
// Security & Performance Foundations (must precede GlobalVariables)
//                                                                    
#include "Biotak\FloatingPointHelper.mqh"
#include "Biotak\ObjectCountManager.mqh"
#include "Biotak\PerformanceOptimizations.mqh"
#include "Biotak\InputValidationEnhanced.mqh"

//                                                                    
// RUNTIME SETTINGS - single owner of panel-editable setting mirrors.
// MUST follow PropertiesAndInputs.mqh (input declarations) and precede
// GlobalVariables.mqh + all consumers (redirection #defines start here).
//                                                                    
#include "Biotak\RuntimeSettings.mqh"

#include "Biotak\GlobalVariables.mqh"

#include "Biotak\UtilityFunctions.mqh"

// Base / Knot Measurement Tool (two-click base box + Entry/SL/TP).
// Included here (before EventHandlers/menu) so both Full and Lite compile:
// Lite has no ring menu but keeps drag/delete/badge handling alive.
#include "Biotak\BaseKnotTool.mqh"
// P-HR-01: Horizontal Ray (Tools cell → 1 click places; same layer, same rule).
#include "Biotak\HRayTool.mqh"
#include "Biotak\PathTool.mqh"

//                                                                    
// Cache & Object Management Systems
//                                                                    
#include "Biotak\CalculationCache.mqh"
#include "Biotak\ZoneFactory.mqh"
#include "Biotak\ZoneConfig.mqh"       // single owner of zone settings
#include "Biotak\ZoneConstants.mqh"

#include "Biotak\ObjectCache.mqh"
#include "Biotak\PropertyChangeDetector.mqh"
#include "Biotak\VisibilityManager.mqh"

//                                                                    
// Timeframe & Calculation Modules
//                                                                    
#include "Biotak\TimeframeFunctions.mqh"
#include "Biotak\FractalTimeframes.mqh"
#include "Biotak\StandardTimeframes.mqh"

#include "Biotak\THCalculations.mqh"
#include "Biotak\ATRCalculations.mqh"
#include "Biotak\TradePlanFormulas.mqh"   // single source of trade-plan math (R-TRADEPLAN)
#include "Biotak\AdaptiveScaling.mqh"
#include "Biotak\BasePriceManager.mqh"

#ifndef BUILD_LITE
#include "Biotak\WaveAnalysis.mqh"
#include "Biotak\FrequencyOptimizer.mqh"
// TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF — the TH3 tool is LIVE again.
#include "Biotak\TH3Tool.mqh"
#endif

//                                                                    
// Drawing & Rendering Pipeline
//                                                                    
#include "Biotak\ObjectFunctions.mqh"
// P-DRAW-01: the user's OWN drawings (fib, trend, hline, channel, box, …) and
// the style memory behind their toolbar. Above EventHandlers/BiotakPanels so
// both halves can ask it (the strip lives in the panels, the create hook in the
// event handlers).
#include "Biotak\DrawToolbar.mqh"
// P-DRAW-116: the CARD SURFACE'S OWN NUMBER TABLE, as a standalone header. BiotakPanels
// owns these names and re-includes this itself, so the cards are byte-identical — the
// only change is that it now sits ABOVE the strip. DrawStrip is include 99 and
// BiotakPanels is 118, so the strip's settings panel could never reach a `PNL_*` name
// and could only retype the value (DSTRIP_GEAR_W 312 = PNL_WEL 312, and five more).
// One table, two readers: from here the panel and the cards CANNOT drift.
#include "Biotak\CardMetrics.mqh"
// P-DRAW-08: the floating strip the drawings' hold opens. Full only — it is a
// screen surface, and Lite owns none (P-BUILD-01).
#include "Biotak\DrawStrip.mqh"
#include "Biotak\ExtendedDrawingFunctions.mqh"
#include "Biotak\ComboEngine.mqh"
#include "Biotak\FactorMode.mqh"
#include "Biotak\LevelPipeline.mqh"
#include "Biotak\ModeDefinitions.mqh"

#include "Biotak\LabelFunctions.mqh"
#include "Biotak\AlertFunctions.mqh"
#include "Biotak\HistoricalDataFunctions.mqh"
#include "Biotak\EventHandlers.mqh"

//                                                                    
// UI MODULES — Circular Menu, Settings Panels & HTF Candles          
// (BiotakKit must precede BiotakMenu; HTFCandles precede the kit)  
//                                                                    
#include "Biotak\HTFCandles.mqh"
#include "Biotak\BiotakKit.mqh"
#include "Biotak\BiotakMenu.mqh"
#include "Biotak\BiotakPanels.mqh"

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // P-PERF-04: attach / timeframe switch budget (both halves are measured:
    // OnInitHandler is the indicator, the UI kit restores menu + panels).
    // P-PERF-10: this entry measures BOTH halves of the init budget (the
    // indicator handler and the UI kit) so the report can name which one owns
    // the attach/timeframe-switch stall instead of reporting one opaque total.
    // P-DRAW-120 (2026-10-01) — AN ATTACH OWNS A CHART THAT CARRIES NO PANEL.
    // P-DRAW-85 wrote `DrawStripSweepStale()` for exactly this ("no orphan survives a
    // reattach") and documented its ONE call as "from the entry's OnInit beside the
    // teardown's own `DrawStripClose()`" — but `git grep SweepStale HEAD` finds the
    // definition and NO call site: the sweep was never wired, so the promise the rule
    // makes has never been delivered. What that costs was measured on 2026-10-01
    // (EURUSD,M5, report «روی stroke که کلیک می‌کنم متن‌ها این‌طوری ناقص هست»): the
    // terminal holds every object of the open Stroke tab at its own seat with its own
    // ink (`TABCENSUS GR2T "50 % line":14865611 z=1442`, `GS0T "STROKE"` in
    // `MQL4\Logs\20261001.log`), while the screen paints 31 of those 104 objects — and
    // the last gear paint in that log is 14:37:08, before the 15:10:39 reload whose
    // statics (`s_dsOpen=false`, `s_dsGear=0`) answer nothing. A family the previous
    // instance left is REUSED (`DrawStripSkinBmp`/`DrawStripFaceZ`/`DrawStripLblAt`
    // decide "create or rewrite?" from `ObjectFind(0,nm) < 0` alone), so one half keeps
    // the older build's own layer and the other half never gets a second writer at all.
    // This is the destroy an attach can prove: at OnInit this instance has painted
    // nothing, so every `PnlDrawS_*` object on the chart is someone else's. One prefix
    // scan per ATTACH, never per frame.
#ifndef BUILD_LITE
    DrawStripSweepStale();
#endif

    uint p4i = GetTickCount();
    int result = OnInitHandler();
    uint p4ind = GetTickCount() - p4i;
    p4i = GetTickCount();
    if(result == INIT_SUCCEEDED)
    {
        // --- Circular menu / settings panels / HTF candles ---
        InitializeUIStates();      // menu + UI globals
        InitializeBiotakKit();   // panel state, colors, boxes, custom lines
        InitializeHTFCandles();    // HTF candle engine
        CreateMenu();              // orb + ring + tools
        // P-UI-114: right-click era deleted — terminal menu untouched, strip on
        // LEFT hold (DrawStrip.mqh).
        ChartRedraw();
    }
    uint p4ui = GetTickCount() - p4i;
    P4ReportSlow("OnInit (" + (result == INIT_SUCCEEDED ? "ok" : "fail") + ")" +
                 P4InitLedgerTag(p4ind, p4ui),
                 p4ind + p4ui, P_P4_INIT_WARN_MS);
    return result;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    uint p4d = GetTickCount();   // P-PERF-04: teardown budget (timeframe switch)
    // P-PERF-44: the ledger is read by the breakdown line below, so it is cleared
    // HERE - at the start of the transaction it describes, never inside a saver
    // (a saver that returns early would leave the previous teardown's numbers).
    GVLedgerResetAll();
    // --- UI teardown (before the base handler clears chart objects) ---
    // P-UI-21: close panels/palette/strip/dropdowns FIRST (flushes the
    // card-12 text edit + releases the modal chart lock) — otherwise
    // REASON_REMOVE leaves Pnl*/Pal_* ghosts behind, swept only at next attach.
    // P-PERF-15: the teardown budget line says the switch costs ~300 ms and
    // cannot say which of the six owners spent it, so each one is timed here.
    // Reported only when the total blows the budget, like every other ledger.
    uint p15t = p4d;
    uint p15Pnl, p15Menu, p15Htf, p15Save, p15Cleanup, p15Handler;
    PnlCloseAll();
    p15Pnl = GetTickCount() - p15t; p15t = GetTickCount();
    // P-DRAW-08: the drawing strip's own objects die with the instance — the
    // removal path owns them, so no PnlDrawS_* button survives a REASON_REMOVE
    // (the name was `Biotak_DS_*` in the note that first said this; the objects
    // have been `PnlDrawS_*` since birth — P-DRAW-73, catalogue 24).
    DrawStripClose();
    DeleteMenu();
    p15Menu = GetTickCount() - p15t; p15t = GetTickCount();
    DeleteHTFCandles();
    p15Htf = GetTickCount() - p15t; p15t = GetTickCount();
    SaveBiotakKit();
    p15Save = GetTickCount() - p15t; p15t = GetTickCount();
    CleanupUIStates(reason);
    p15Cleanup = GetTickCount() - p15t; p15t = GetTickCount();
    OnDeinitHandler(reason);
    p15Handler = GetTickCount() - p15t;
    uint p15total = GetTickCount() - p4d;
    P4ReportSlow("OnDeinit reason=" + IntegerToString(reason),
                 p15total, P_P4_INIT_WARN_MS);
    // P-PERF-37: save= was the biggest single item of an ordinary timeframe
    // switch and nothing said WHY. The write shadow's whole promise is that an
    // untouched session costs zero terminal calls and no disk flush, so the pass
    // now reports what it actually did - how many keys it wrote, how many it
    // proved were already on disk, whether the terminal-wide `GlobalVariablesFlush`
    // ran, and the NAMES of the first writers. A number without a cause is what
    // this project refuses to act on; this line is the cause.
    // P-PERF-44: EVERY saver reports now, not only the override pass. The line
    // that carried `save writes=0/106 flushed=0` next to a 125 ms phase was a
    // number without an owner: the palette and UI-state blocks wrote 13 + 6 keys
    // plus a terminal-wide flush that no field of this line could see, and the HTF
    // block wrote 15 more with no guard at all. `flush=` counts the disk copies
    // this teardown actually performed (ONE owner, GVFlushCommit, so 1 is the
    // ceiling however many saver blocks ran).
    if(p15total > P_P4_INIT_WARN_MS)
        _LOG_GATE_W Print("[W][PERF] OnDeinit breakdown: pnl=", (int)p15Pnl, "ms menu=", (int)p15Menu,
              "ms htf=", (int)p15Htf, "ms save=", (int)p15Save, "ms cleanup=", (int)p15Cleanup,
              "ms handler=", (int)p15Handler, "ms | ovr w=", RSSaveWrites(), "/",
              (RSSaveWrites() + RSSaveSkipped()),
              " pal w=", GVLedgerWrites(GV_BLOCK_PALETTE), "/",
              (GVLedgerWrites(GV_BLOCK_PALETTE) + GVLedgerSkipped(GV_BLOCK_PALETTE)),
              " ui w=", GVLedgerWrites(GV_BLOCK_UI), "/",
              (GVLedgerWrites(GV_BLOCK_UI) + GVLedgerSkipped(GV_BLOCK_UI)),
              " htf w=", GVLedgerWrites(GV_BLOCK_HTF), "/",
              (GVLedgerWrites(GV_BLOCK_HTF) + GVLedgerSkipped(GV_BLOCK_HTF)),
              " flush=", GVFlushRuns(),
              " first=", RSSaveNamed(0), ",", RSSaveNamed(1), ",", RSSaveNamed(2),
              // P-PERF-45 evidence: frames that actually ran, over the ticks that
              // ended with the frame still owed (the starvation count). `starved`
              // must read ~0 - a number tracking the frame count means the pump is
              // starving the progress-maker again.
              " | coop frame=", CoopFrameRuns(), "/", (CoopFrameRuns() + CoopFrameStarved()));
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &real_volume[],
                const int &spread[])
{
    int result = OnCalculateHandler(rates_total, prev_calculated, time, open, high, low, close, tick_volume, real_volume, spread);
    // --- UI kit: HTF forming-candle live update + new-bar redraw ---
    RefreshKitOnBar();
    return result;
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
  // P-PERF-04: name the phase behind an interaction hitch (indicator half vs
  // menu/panel half). Logs only when the pair blows the 40 ms budget.
  // P-PERF-34: scope the frame deferral to this window. A forced frame inside
  // an event is SCHEDULED, never executed - see the EventHandlers note. Setting
  // the flag here (not in the handlers) is what makes the guarantee hold for
  // every path they call, including ones added later.
  g_inChartEvent = true;
  uint p4t = GetTickCount();
  OnChartEventHandler(id,lparam,dparam,sparam);
  uint p4a = GetTickCount() - p4t;
  p4t = GetTickCount();
  // P-UI-114: the strip opens on a LEFT hold inside DrawStripOnEvent below.
  // --- Circular menu / settings panels / palette ---
  HandleUIChartEvent(id,lparam,dparam,sparam);
  // P-DRAW-08: the drawing strip's own buttons and its dismiss clicks. Its own
  // owner, its own objects — it shares no state with the panels.
  DrawStripOnEvent(id,lparam,dparam,sparam);
  // P-PAL-19 (2026-10-02) — THE ONE BRIDGE. DrawStrip is include 99 and the panels
  // are 124, and MQL4 needs a definition before its use, so the strip cannot call
  // `PalOpenDraw` itself: it leaves a REQUEST (DrawStripPalAsk) and this line — the
  // first place in the program that sees BOTH sides — performs the open. One
  // direction, one place, no forward declaration, and the strip has no knowledge of
  // the palette's existence beyond this handshake.
  int palAsk = DrawStripPalAsked();
  if(palAsk >= 0) PalOpenDraw(DrawStripPlateX(), DrawStripPlateY(), DrawStripPlateW());
  // P-PAL-20 (2026-10-02) — THE LEDGER, REWRITTEN WHOLE, EVERY EVENT, AND WRITTEN
  // LAST. This is the same bridge's second direction and it exists for one reason: a
  // colour pick is a release on TWO channels, `HandleUIChartEvent` serves the palette
  // first (above), and then the strip asks `DrawStripPointInside` about the release
  // PIXEL — a pixel on the popup, not on the plate — read false and closed the whole
  // strip (DrawStrip_Router:1113). The strip owns that popup, so its pixels are its
  // pixels. The strip cannot see `g_PalX/PalW()`; these lines are the only place that
  // can, and LAST is the whole discipline: the ledger answers for the chart as the
  // event LEFT it, so a popup closed above is already out of it.
  //
  // P-PAL-19f — AND THE REPAINT IS SPENT HERE, ONCE, AFTER the popup's route. The
  // apply owns a flag and nobody repaints from inside a gesture it does not own
  // (P-PERF-34's law, the same sentence the owed-frame comment below is built on).
  if(DrawStripPalRepaintTake()) { DrawStripPaint(); ChartRedraw(); }
  // P-PAL-19e — AND THE PALETTE CLOSES WITH ITS PARENT. A colour popup opened by
  // the STRIP belongs to the strip: when the strip goes (close, kind switch, deinit)
  // the popup must go with it, or it stays on the chart as a floater nobody owns
  // («همراه والدش بسته بشه»). One direction, same bridge.
  if(!DrawStripPalParentLive() && PalKindIsDrawing(g_PalKind)) PalClose();
  DrawStripSurfaceClear();
  if(g_PalOpen && PalKindIsDrawing(g_PalKind) && DrawStripPalTargetLive())
     DrawStripSurfacePublish(g_PalX, g_PalY, PalW(), PalH());
  uint p4b = GetTickCount() - p4t;
  g_inChartEvent = false;  // P-PERF-40: A USER ACTION SETTLES THE FRAME IT OWED — IN THE SAME EVENT.
  //
  // P-PERF-34 made a forced frame inside an event SCHEDULED instead of executed,
  // because the body it measured was 531 ms of rebuild and it froze the press
  // that asked for it. The edit was then left owed to the 250 ms timer, and the
  // live log measured what that costs:
  //
  //   [W][PERF] owed frame (chart-event) waited=46..266ms body=0ms stage=0 clear=0
  //
  // `waited` is the whole story — a press was answered between 0 and 266 ms
  // later, uniformly up to the timer's cadence — and `body=0ms` is worse than it
  // looks: by the time the timer ran the frame there was nothing left to draw,
  // because the discrete path had already repainted the OLD picture. So the
  // switch was acknowledged by a repaint that changed nothing and the real frame
  // arrived up to a quarter second afterwards. That is the "فسفس".
  //
  // The pump is the single owner of "run owed work": cheap sweeps first, the
  // frame on the leftover slice, budget-bounded (COOP_BUDGET_MS) so this cannot
  // become an unbounded in-event stall, and single-flight so three fast presses
  // are one frame. It runs the frame with force_redraw = FALSE, which is exactly
  // what keeps RedrawAllObjects' event guard meaningful — the guard still
  // protects every event-path caller that does NOT pump, and this is the one
  // place that has explicitly earned the pass.
  //
  // Cost when nothing is owed: four flag reads and a couple of GetTickCount.
  // It is therefore correct to call it on EVERY event, not just the discrete
  // ones — and that is deliberate, because the entry point is the only place that
  // covers the paths inside both handlers (and the ones added later).
  p4t = GetTickCount();
  CoopPump();
  uint p4c = GetTickCount() - p4t;
  // P-UI-40: AND THE PANEL FOLLOWS WHAT IT DOES NOT OWN.
  //
  // A hotkey changes state that an OPEN card displays, but the hotkeys live in
  // EventHandlers and the panel in a later file, so they cannot repaint it — the
  // rows read the live value, the switch IMAGE is a bitmap only a paint pass
  // replaces. Draining the request HERE (same event) means a key press and the
  // panel switch it drives land together; RefreshKitOnBar drains it too, as the
  // net for any path that does not pass through this tail.
  //
  // `panels=` is in the budget check for the same reason `settle=` is: a sync
  // that hides its cost would be the defect this cycle is fixing, one level up.
  p4t = GetTickCount();
  UISyncDrain();
  uint p4e = GetTickCount() - p4t;
  // P-PERF-26: the NAME next to the id - a ledger nobody can read without
  // recalling which number means what is how id=1 (OBJECT_CLICK) got filed as a
  // cursor-move for two cycles.
  // P-PERF-40: `settle=` is the frame this event drained, and it is IN the budget
  // check on purpose — a drain that hides its own cost from the ledger would be
  // the same defect this cycle is fixing, one level up.
   // P-PERF-50: the ledger message is ~15 string ops (P4EventName + six
   // IntegerToString + concatenations) and P4ReportSlow no-ops under budget —
   // so building it on EVERY event (a MOUSE_MOVE storm is hundreds/sec) was
   // pure garbage for the same silence. The total is hoisted first and the
   // message is built only when it will actually print: identical log lines,
   // zero steady-state strings. Same gate in the Lite entry.
   uint p4tot = p4a + p4b + p4c + p4e;
   if(p4tot >= P_P4_EVENT_WARN_MS)
      P4ReportSlow("chart event " + P4EventName(id) + "(id=" + IntegerToString(id) + ") [indicator=" +
               P4MsTag(p4a) + " ui=" + P4MsTag(p4b) + " settle=" + P4MsTag(p4c) +
               " panels=" + P4MsTag(p4e) + "]",
               p4tot, P_P4_EVENT_WARN_MS);
}

//+------------------------------------------------------------------+
//| Timer function - periodic housekeeping                           |
//+------------------------------------------------------------------+
void OnTimer()
{
    // P-UI-113-OFF (2026-09-23): no fast window — every tick is housekeeping.

    // P-PERF-16: the 250 ms safety refresh behind the cached UI metrics. Resizing
    // the chart also fires a chart-change event (which invalidates immediately);
    // this line covers a missed notification and costs two terminal reads per
    // quarter second instead of two per hit-test item.
    CircUIMetricsInvalidate();

    // FIX: If indicator is not yet fully initialized (e.g. waiting for history),
    // retry drawing periodically even without new ticks.
    // P-PERF-06: a staged post-wipe rebuild (attach / TF switch / topology
    // toggle) also advances here, so a tick-less chart still settles in ~1 s.
    // P-PERF-35: the coop pump owns the timer's heavy work. The sweep jobs are
    // OWED here - once per timer, exactly the cadence they had - and drained by
    // the pump under a millisecond slice, cheap jobs first and the owed frame
    // last. A job can therefore be delayed by the slice, but no job can hold the
    // terminal for its whole run, and the frame still advances on a tick-less
    // chart (the pump treats "rebuild in flight" as owed by definition).
    CoopOwe(COOP_JOB_OBJ_CLEANUP);
    CoopOwe(COOP_JOB_LABEL_EXPIRY);
    CoopOwe(COOP_JOB_STATUS_TEXT);
    CoopPump();
    UpdateFreeMark();   // P-FREE-03: corner witness rebirth (timer covers tick-less charts)

    // --- UI kit: HTF forming candle + new-bar redraw + chart-lock watchdog ---
    // (P-UI-40's UISyncDrain rides inside RefreshKitOnBar — one drain owner.)
    RefreshKitOnBar();
    ChartScrollReconcile();

    // P-LM-09: the leg meter's readout is a 4-second VISITOR, and this is its clock.
    // It belongs here and not in OnCalculate: a plate must expire on a chart that has
    // not ticked (a weekend, a dead symbol) exactly as on a busy one, and the timer is
    // the only thing already running when the market is asleep. The sweep is one
    // comparison while the tool has no measurement on the chart, and one bool per
    // measurement while it has; the four deletes of an expiry happen exactly once.
    // (P-LM-10's drag channel retired here with the native drag itself: P-LM-11's
    // edit owner moves the family in the mouse event, so there is nothing left
    // for a timer to chase.)
    LegMeasureExpireSweep();

    // P-LM-16b: the handles' third riding channel — the net under MOUSE_MOVE
    // (drag-pans) and CHART_CHANGE (wheel, keys, auto-scroll). Guarded writes:
    // a chart that has not moved costs one loop of reads and no ObjectSet*.
    LegMeasureRideChart();

    // P-UI-100 (2026-09-22): the selection net of the two hand-set lines — the
    // one owner that does not depend on any event reaching us. A selection that
    // outlived the gesture that made it is what lets MT4 drag the custom price
    // line (and the whole ladder derived from its price) along with somebody
    // else's fib or box («وقتی فیو یا باکس از همون محل میکشم کاستوم پرایس
    // جابجا میشه»). The 250 ms clock is the net under the layers whose events
    // are consumed whole (the box tool's draw session); the gesture starts
    // themselves clear it in their own event, so this is a floor, not the path.
    // Cost: one probe while the button is down, then three guarded reads.
    HandLinesSelectionNet();

    // P-TH3-INFO-11 (2026-09-22): the caption heal net - the active family's
    // one question every 250 ms (reads-only while healthy; one TH3CAP line
    // per action). Full entry only: Lite owns no caption UI (P-BUILD-01).
    TH3InfoCaptionHeal();

    // P-UI-98r: the net under the card-cull's event hooks (open/close/drag/
    // draw) - zoom, resize and forming-candle drift converge here within one
    // tick of the 250 ms clock. Closed / HTF-off / nothing drawn: three bool
    // reads and out.
    HTFCardCullRefresh();

    // P-TH3-PB-DRAG-LOCK (2026-09-22): the band's drag heartbeat - a stuck
    // terminal or an off-chart release leaves OBJECT_DRAG silent, and the
    // button-up MOUSE_MOVE never arrives; the 1.5 s idle here is the only
    // heal that does not need the terminal to cooperate.
    TH3BaseBandDragHeartbeat();

    // NOTE (2026-09-23, P-DRAW-18): `WindowPriceMax()/Min()` answer 0/0 during
    // OnInit - the chart window is not mapped yet (`run hi=0.00000 lo=0.00000` in
    // the terminal's log) - while a timer tick ~1 s later reads the real range
    // (`window hi=4410.70000 lo=4230.80000` on XAUUSD,H1). Anything needing the
    // visible window belongs HERE, never in OnInitHandler.
}
