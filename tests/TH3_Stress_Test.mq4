//+------------------------------------------------------------------+
//| TH3_Stress_Test.mq4                                              |
//|                                                                  |
//| THE INDICATOR UNDER THE WORST CASES IT CAN BE HANDED.            |
//|                                                                  |
//| WHY THIS EXISTS. The user's order (2026-11-01): «کلا اندیکاتور   |
//| تست کن تحت شدیدترین چیزا با تست ها نباید هنگ یا قاطی یا بهم     |
//| ریخته بشه» and «با دکمه کنترل میخوام کپی بکنم ایطوری میشه از این |
//| نوع مشکلات باعث هنگی میشه اصلاً نباید باشه». Every other gate   |
//| in this repo asks a static question of the SOURCES. Nothing here  |
//| asked the terminal: how much does one event cost when the chart   |
//| is carrying 400 objects, when a gesture makes 400 of them in a    |
//| second, when a bulk purge deletes them again? A stall is a RUNTIME |
//| number, and the live frame of the reported hang ends on           |
//|   [gest] id=7 t=189875156 xy=0,0 nm="Rectangle 37658" ours=0      |
//| with nothing after it — the census says the copy reached us and    |
//| cannot say what we did next. This harness is that missing number,  |
//| taken without waiting for a hang.                                 |
//|                                                                  |
//| WHAT IT PROVES, IN ONE RUN:                                       |
//|   S1 create-single   one foreign create through the real handler   |
//|   S2 create-storm    400 creates, priced at 50 / 200 / 400 objects |
//|                      — the O(N²) test: a per-event chart walk      |
//|                      shows up here as ms growing WITH the chart    |
//|   S3 ctrl-copy       the reported gesture: select, drag, copy,     |
//|                      create, click — each stage timed, and the     |
//|                      copy's look + the source's selection checked  |
//|   S4 grab-door       the one heavy branch a create can reach       |
//|                      (CustomPriceForeignDrawSeen → forced          |
//|                      RedrawAllObjects) priced against the same     |
//|                      create with the door shut                     |
//|   S5 delete-storm    300 deletes of our own namespace, through the |
//|                      router, with and without P-UI-21's window     |
//|   S6 strip-cycle     open the strip on a drawing and close it ×20  |
//|   S7 move-storm      300 mouse-moves, the highest-rate event there |
//|   S8 attach-walk     DrawInkMemoInit: the whole-chart walk at the  |
//|                      size S2 left the chart                        |
//|   S9 history-file    a clean day-file rewrite, a FORCED refusal and  |
//|                      the pump's drain of it — the number that used   |
//|                      to be a Sleep(100) retry on the tick path       |
//|   S10 copy-storm     the reported gesture TEN TIMES IN A ROW, each   |
//|                      copy becoming the next source — the shape the   |
//|                      user repeats on a chart that already carries    |
//|                      the strip and a few hundred objects             |
//|   S4b grab-door storm the one heavy create branch × 20 creates: a    |
//|                      held grab base + a burst is the runaway shape   |
//|                                                                  |
//| HOW TO RUN: drag onto any chart with at least ~60 bars, with the  |
//| drawing strip CLOSED and no settings panel open (it shares those   |
//| objects with a live indicator and refuses instead of fighting it). |
//| THE ONE COMMAND IS THE BUILD:                                     |
//|   compile-th3.ps1 -Stress -RestartTerminal                        |
//| compiles this unit, deploys it into the instance's Scripts\, writes|
//| build-logs\th3-stress.ini, restarts MT4 on it, waits for the      |
//| `THStress.done` marker and prints every [STRESS] line as a verdict |
//| (fail>0 fails the build). Lines go to the Experts tab and, per     |
//| line, to the flushed diag file: read them with                     |
//| `python tools/diag-live.py` (AGENTS.md law 3 — the journal is a    |
//| cache and dies with a killed terminal).                            |
//|                                                                  |
//| SIDE EFFECTS: creates THStress_* drawings and THLevels_Stress_*   |
//| children and deletes every one of them again; opens and closes the |
//| strip; runs one forced repaint in S4. It never deletes an object   |
//| it did not name.                                                   |
//+------------------------------------------------------------------+
#property strict
#property description "Drives the real event chain under the worst loads and prices every action"

// EXACTLY the indicator's include chain (Biotak Trigger TH3.mq4) — a harness
// compiles the real production modules, never a hand-picked subset.
#include "..\Biotak\BuildConfig.mqh"
#include "..\Biotak\MathConstants.mqh"
#include "..\Biotak\Logger.mqh"
#ifndef BUILD_LITE
#include "..\Biotak\Profiler.mqh"
#endif
#include "..\Biotak\PropertiesAndInputs.mqh"
#include "..\Biotak\ConstantsAndEnums.mqh"
#include "..\Biotak\ProjectConstants.mqh"
#include "..\Biotak\InputValidator.mqh"
#include "..\Biotak\FloatingPointHelper.mqh"
#include "..\Biotak\ObjectCountManager.mqh"
#include "..\Biotak\PerformanceOptimizations.mqh"
#include "..\Biotak\InputValidationEnhanced.mqh"
#include "..\Biotak\RuntimeSettings.mqh"
#include "..\Biotak\GlobalVariables.mqh"
#include "..\Biotak\UtilityFunctions.mqh"
#include "..\Biotak\BaseKnotTool.mqh"
#include "..\Biotak\HRayTool.mqh"
#include "..\Biotak\PathTool.mqh"
#include "..\Biotak\CalculationCache.mqh"
#include "..\Biotak\ZoneFactory.mqh"
#include "..\Biotak\ZoneConfig.mqh"
#include "..\Biotak\ZoneConstants.mqh"
#include "..\Biotak\ObjectCache.mqh"
#include "..\Biotak\PropertyChangeDetector.mqh"
#include "..\Biotak\VisibilityManager.mqh"
#include "..\Biotak\TimeframeFunctions.mqh"
#include "..\Biotak\FractalTimeframes.mqh"
#include "..\Biotak\StandardTimeframes.mqh"
#include "..\Biotak\THCalculations.mqh"
#include "..\Biotak\ATRCalculations.mqh"
#include "..\Biotak\TradePlanFormulas.mqh"
#include "..\Biotak\AdaptiveScaling.mqh"
#include "..\Biotak\BasePriceManager.mqh"
#ifndef BUILD_LITE
#include "..\Biotak\WaveAnalysis.mqh"
#include "..\Biotak\FrequencyOptimizer.mqh"
#include "..\Biotak\TH3Tool.mqh"
#endif
#include "..\Biotak\ObjectFunctions.mqh"
#include "..\Biotak\DrawToolbar.mqh"
#include "..\Biotak\CardMetrics.mqh"
#include "..\Biotak\DrawStrip.mqh"
#include "..\Biotak\ExtendedDrawingFunctions.mqh"
#include "..\Biotak\ComboEngine.mqh"
#include "..\Biotak\FactorMode.mqh"
#include "..\Biotak\LevelPipeline.mqh"
#include "..\Biotak\ModeDefinitions.mqh"
#include "..\Biotak\LabelFunctions.mqh"
#include "..\Biotak\AlertFunctions.mqh"
#include "..\Biotak\HistoricalDataFunctions.mqh"
#include "..\Biotak\Sessions_Time.mqh"
#include "..\Biotak\Sessions_Model.mqh"
#include "..\Biotak\Sessions_Draw.mqh"
#include "..\Biotak\EventHandlers.mqh"
#include "..\Biotak\HTFCandles.mqh"
#include "..\Biotak\BiotakKit.mqh"
#include "..\Biotak\BiotakMenu.mqh"
#include "..\Biotak\BiotakPanels.mqh"

//--- THE BUDGETS. `WARN` is the number the live ledger already uses for one
//--- event (P_P4_EVENT_WARN_MS); `HANG` is the point where the user's screen
//--- stops answering and says "Not Responding" — a single action that crosses
//--- it is reported as HANG, not as slow.
#define STRESS_WARN_MS   40
#define STRESS_HANG_MS   2000
#define STRESS_FOREIGN   400
#define STRESS_OURS      300
#define STRESS_MOVES     300

int  g_stFail = 0;
int  g_stWarn = 0;
long g_stUs = 0;      // the µs clock of the action being measured (long: 2^32 µs is 71 min)

void StW(const string line)
{
   Print("[STRESS] ", line);
#ifndef BUILD_LITE
   DrawStripDiagEmit("[STRESS] " + line);
#endif
}

//--- P-STRESS-1: THE MARKER IS THE ORACLE, the journal is the record. MT4 buffers
//--- the Experts journal in RAM (P-DRAW-126), so a finished run can sit minutes
//--- behind — and a *reader that waits on it* reports a hang that never happened.
//--- `compile-th3.ps1 -Stress` waits on THIS file (the terminal's own file API),
//--- exactly as the strip shot waits on `StripShot.done` (P-SHOT-1).
#define STRESS_DONE_MARKER "THStress.done"
void StDone(const string verdict)
{
   StW("DONE: " + verdict);
   int h = FileOpen(STRESS_DONE_MARKER, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) { StW("DONE-MARKER REFUSED err=" + IntegerToString(GetLastError())); return; }
   FileWrite(h, (StringFind(verdict, "SKIP") == 0 ? verdict : ("DONE " + verdict)));
   FileClose(h);
}

void StBegin() { g_stUs = (long)GetMicrosecondCount(); }

// µs since the action started by StBegin() — as an INTEGER µs count. The
// division is integer on purpose: `… / 10000 * 10 / 100` is ms with one decimal
// and no double, so no 300 µs action is rounded away. The casts are spelled
// because MQL4 answers this clock as an unsigned value.
long StUs() { return ((long)GetMicrosecondCount() - g_stUs); }
double StEnd() { return (double)(StUs() / 10000 * 10) / 100.0; }

// One scenario's verdict line. `worst` is the single most expensive action in
// the batch — a batch of 400 cheap ones is not a hang, but one of them being
// 900 ms is the defect.
void StReport(const string name, const int n, const double worst, const double total,
              const string extra)
{
   string verdict = "OK";
   if(worst >= STRESS_HANG_MS)      { verdict = "HANG"; g_stFail++; }
   else if(worst >= STRESS_WARN_MS) { verdict = "SLOW"; g_stWarn++; }
   StW(name + " n=" + IntegerToString(n) +
       " worst_ms=" + DoubleToString(worst, 1) +
       " total_ms=" + DoubleToString(total, 1) +
       " objs=" + IntegerToString(ObjectsTotal(0, -1, -1)) +
       (extra == "" ? "" : (" " + extra)) +
       " verdict=" + verdict);
}

//--- THE TERMINAL'S BEAT, STOOD IN FOR. A script has no OnTimer, so the harness calls
//--- the pump the indicator's timer would (P-COPY-DEFER). `settle` waits out the copy
//--- ring's own quiet window (COPY_STYLE_QUIET_MS) so a burst is not read as "never
//--- styled" — the real terminal spends that wait between two events, the harness has to
//--- spend it here. Returns the pump's own cost, which is where the styling now lands.
double StDrain(const int settleMs)
{
   if(DrawStyleCopyQueuePending() <= 0) return 0.0;
   if(settleMs > 0) Sleep(settleMs);
   StBegin();
   int guard = 0;
   while(DrawStyleCopyQueuePending() > 0 && guard < 128) { CoopPump(); guard++; }
   return StEnd();
}

int PfxCountStress(const string pfx)
{
   int n = 0, pl = StringLen(pfx);
   if(pl == 0) return 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringLen(nm) >= pl && StringSubstr(nm, 0, pl) == pfx) n++;
   }
   return n;
}

void SweepStress()
{
   int total = ObjectsTotal(0, -1, -1);
   int gone = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, "THStress_") == 0 || StringFind(nm, "THLevels_Stress_") == 0)
      {
         ObjectDelete(0, nm);
         gone++;
         if((gone % 100) == 0) StW("SWEEP gone=" + IntegerToString(gone) + " of " + IntegerToString(total));
      }
   }
}

// One rectangle of our own making, at a seat no live drawing occupies.
bool MakeRect(const string nm, const int rung)
{
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   datetime t1 = Time[40 + rung];
   datetime t2 = Time[10 + rung];
   double p1 = High[40 + rung];
   double p2 = Low[10 + rung];
   if(t1 == 0 || t2 == 0 || p1 <= 0 || p2 <= 0) return false;
   return ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
}

//+------------------------------------------------------------------+
//| S1 + S2 — the create path, once and then as a storm               |
//+------------------------------------------------------------------+
void SCreate()
{
   long zero = 0; double zd = 0.0;
   string nm = "THStress_Box_A";
   StW("S1 step=begin");
   if(!MakeRect(nm, 0)) { StW("S1 SKIP: the terminal refused a rectangle"); return; }
   StW("S1 step=mk");

   //--- S1: twenty creates of ONE name, the reported gesture's shape. The create event
   //--- only queues the name (P-COPY-DEFER); the style runs on the pump's beat, so BOTH
   //--- halves are priced — the event and the drain the terminal would run next.
   double worst = 0, total = 0, worstDrain = 0;
   for(int i = 0; i < 20; i++)
   {
      ObjectDelete(0, nm);
      MakeRect(nm, 0);
      StBegin();
      OnChartEventHandler(CHARTEVENT_OBJECT_CREATE, zero, zd, nm);
      double ms = StEnd();
      double dms = StDrain(0);
      total += ms;
      if(ms > worst) worst = ms;
      if(dms > worstDrain) worstDrain = dms;
   }
   StReport("S1 create-single", 20, worst, total,
            " drain_worst=" + DoubleToString(worstDrain, 1));

   //--- S2: the storm. Every object is foreign to our prefix, so every one of
   //--- them runs the full create branch — and the chart grows under each, so a
   //--- stage that walks the whole chart prices itself HERE. `at=` carries the
   //--- worst action measured at three chart sizes; a flat column is O(1), a
   //--- growing one is the walk (the only shape that turns N copies into a hang).
   double w50 = 0, w200 = 0, w400 = 0;
   worst = 0; total = 0;
   int made = 0;
   for(int k = 1; k <= STRESS_FOREIGN; k++)
   {
      string nmk = "THStress_S2_" + IntegerToString(k);
      if(!MakeRect(nmk, k % 20)) break;
      made++;
      StBegin();
      OnChartEventHandler(CHARTEVENT_OBJECT_CREATE, zero, zd, nmk);
      double ms = StEnd();
      total += ms;
      if(ms > worst) worst = ms;
      if(made == 50)  w50  = ms;
      if(made == 200) w200 = ms;
      if(made == 400) w400 = ms;
   }
   StReport("S2 create-storm", made, worst, total,
            " at50=" + DoubleToString(w50, 1) +
            " at200=" + DoubleToString(w200, 1) +
            " at400=" + DoubleToString(w400, 1));
   //--- S2b — THE DRAIN THE STORM LEFT OWED. The create is a ring write now, so the
   //--- number that matters moved here: the pump must empty a 64-name burst in slices,
   //--- not in one breath. A burst that measures ~0 ms at create and 400 ms in one
   //--- pump call is the freeze one layer down.
   int    owed    = DrawStyleCopyQueuePending();
   double drainMs = StDrain(500);
   StReport("S2b create-storm drain", owed, drainMs, drainMs,
            " armed=" + IntegerToString(DrawStyleCopyQueueArmed() ? 1 : 0));
   StW("S2 step=sweep");
   SweepStress();
   StW("S2 step=done");
}

//+------------------------------------------------------------------+
//| S3 — the reported gesture, stage by stage                         |
//+------------------------------------------------------------------+
void SCtrlCopy()
{
   long zero = 0; double zd = 0.0;
   string src = "THStress_Box_A";
   string dst = "THStress_Box_B";
   StW("S3 step=src");
   if(!MakeRect(src, 0)) { StW("S3 SKIP: the terminal refused a rectangle"); return; }
   StW("S3 step=props");

   // the KIND's memory, worn the way a styled drawing wears it: the strip's own
   // writer learns the memory (`DrawSlotWrite`), so the copy's expected ink is the
   // product's promise ("a fresh drawing of this kind wears the kind's memory")
   // and not a number this harness invented beside it.
   ObjectSetInteger(0, src, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, src, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, src, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, src, OBJPROP_SELECTED, true);
   DrawSlotWrite(src, DRAW_SLOT_COLOR, (double)(int)clrDodgerBlue);
   StW("S3 step=ink");
   DrawSlotWrite(src, DRAW_SLOT_WIDTH, 2.0);
   StW("S3 step=width");

   color   wantClr = (color)ObjectGetInteger(0, src, OBJPROP_COLOR);
   int     wantW   = (int)ObjectGetInteger(0, src, OBJPROP_WIDTH);

   //--- the terminal's own order for a Ctrl+drag copy: a drag of the source, the
   //--- copy's create, then the click that lands on it. Each stage priced alone.
   StBegin(); OnChartEventHandler(CHARTEVENT_OBJECT_DRAG, zero, zd, src);
   double msDrag = StEnd();
   StW("S3 step=drag");

   MakeRect(dst, 2);
   // the copy is born in the terminal's FACTORY look — that is the point of the
   // report «چرا رنگش پیش‌فرض که میکشم سفید هستش»: our branch must dress it.
   StBegin(); OnChartEventHandler(CHARTEVENT_OBJECT_CREATE, zero, zd, dst);
   double msCreate = StEnd();
   double msDrain = StDrain(500);   // P-COPY-DEFER: the style lands on the terminal's next beat
   StW("S3 step=create");

   StBegin(); OnChartEventHandler(CHARTEVENT_OBJECT_CLICK, zero, zd, dst);
   double msClick = StEnd();
   StW("S3 step=click");

   color gotClr = (color)ObjectGetInteger(0, dst, OBJPROP_COLOR);
   int   gotW   = (int)ObjectGetInteger(0, dst, OBJPROP_WIDTH);
   bool  srcSel = (ObjectGetInteger(0, src, OBJPROP_SELECTED) == 1);

   double worst = msDrag;
   if(msCreate > worst) worst = msCreate;
   if(msDrain  > worst) worst = msDrain;
   if(msClick  > worst) worst = msClick;
   StReport("S3 ctrl-copy", 3, worst, msDrag + msCreate + msDrain + msClick,
            " drag=" + DoubleToString(msDrag, 1) +
            " create=" + DoubleToString(msCreate, 1) +
            " drain=" + DoubleToString(msDrain, 1) +
            " click=" + DoubleToString(msClick, 1));
   StW("S3 look copy=" + ColorToString(gotClr) + " src=" + ColorToString(wantClr) +
       " w=" + IntegerToString(gotW) + "/" + IntegerToString(wantW) +
       " src_selected=" + (srcSel ? "1" : "0") +
       " verdict=" + ((gotClr == wantClr && gotW == wantW) ? "OK" : "MIXED"));
   if(!(gotClr == wantClr && gotW == wantW)) g_stFail++;
   SweepStress();
}

//+------------------------------------------------------------------+
//| S10 — the reported gesture, ten times, copy after copy             |
//|                                                                    |
//| A hand does not copy once: it drags the copy, then the copy of the |
//| copy, on a chart that already carries the strip. Each gesture is   |
//| priced as ONE action (create + the click that lands on it), because|
//| that is what the interface thread must answer. `wrong_ink` is the  |
//| "بهم ریخته" half: a copy that comes out in the terminal's factory  |
//| look instead of the kind's memory.                                |
//+------------------------------------------------------------------+
void SCopyStorm()
{
   long zero = 0; double zd = 0.0;
   string  src = "THStress_Box_A";
   if(!MakeRect(src, 0)) { StW("S10 SKIP: the terminal refused a rectangle"); return; }

   // learn the kind's memory through the product's own writer, exactly as S3 does
   color  want = clrDodgerBlue;
   ObjectSetInteger(0, src, OBJPROP_COLOR, want);
   ObjectSetInteger(0, src, OBJPROP_SELECTABLE, true);
   DrawSlotWrite(src, DRAW_SLOT_COLOR, (double)(int)want);

   double worst = 0, total = 0;
   int n = 0, wrongInk = 0, selected = 0;
   for(int i = 1; i <= 10; i++)
   {
      string dst = "THStress_S10_" + IntegerToString(i);
      StBegin();
      MakeRect(dst, i % 20);
      OnChartEventHandler(CHARTEVENT_OBJECT_CREATE, zero, zd, dst);
      OnChartEventHandler(CHARTEVENT_OBJECT_CLICK, zero, zd, dst);
      double dms = StDrain(0);   // the beat the terminal would spend styling it
      double ms = StEnd() + dms;
      total += ms;
      if(ms > worst) worst = ms;
      n++;
      if((color)ObjectGetInteger(0, dst, OBJPROP_COLOR) != want) wrongInk++;
      if(ObjectFind(0, dst) >= 0 && ObjectGetInteger(0, dst, OBJPROP_SELECTED) == 1) selected++;
      src = dst;   // the copy becomes the next source, the way a hand repeats it
   }
   StReport("S10 copy-storm", n, worst, total,
            " wrong_ink=" + IntegerToString(wrongInk) +
            " selected=" + IntegerToString(selected));
   if(wrongInk > 0) { g_stFail++; StW("S10 verdict=MIXED a copy did not wear the kind's ink"); }
   SweepStress();
}

//+------------------------------------------------------------------+
//| S4 — the one heavy branch a create can reach                      |
//+------------------------------------------------------------------+
void SGrabDoor()
{
   long zero = 0; double zd = 0.0;
   string nm = "THStress_Box_A";
   if(!MakeRect(nm, 0)) { StW("S4 SKIP: the terminal refused a rectangle"); return; }

   // the door shut: no grab reference held → CustomPriceForeignDrawSeen() only
   // stamps a window.
   s_ownGrabPrice = 0.0;
   StBegin(); OnChartEventHandler(CHARTEVENT_OBJECT_CREATE, zero, zd, nm);
   double shut = StEnd();

   // the door open: a held grab reference makes the SAME create call
   // CustomPriceRestoreGrabPrice() → CustomPriceDragFrame(true) → a forced
   // RedrawAllObjects(true) INSIDE the event. This is the number that decides
   // whether a copy can cost a whole ladder rebuild.
   s_ownGrabPrice = (double)ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
   if(s_ownGrabPrice <= 0) s_ownGrabPrice = Close[1];
   StBegin(); OnChartEventHandler(CHARTEVENT_OBJECT_CREATE, zero, zd, nm);
   double open = StEnd();
   s_ownGrabPrice = 0.0;   // the harness never leaves a grab held

   StW("S4 grab-door shut_ms=" + DoubleToString(shut, 1) +
       " open_ms=" + DoubleToString(open, 1) +
       " ratio=" + DoubleToString(shut > 0 ? open / shut : 0, 1) +
       " pend=" + IntegerToString(CustomPriceGrabPending() ? 1 : 0));
   if(open >= STRESS_HANG_MS) { g_stFail++; StW("S4 verdict=HANG a create repainted the ladder for 2 s+"); }
   else if(open >= STRESS_WARN_MS) { g_stWarn++; StW("S4 verdict=SLOW"); }
   else StW("S4 verdict=OK");
   SweepStress();
}

//+------------------------------------------------------------------+
//| S4b — THE SAME DOOR, TWENTY TIMES: the runaway shape               |
//|                                                                    |
//| One create through the heavy branch is a slow frame. A BURST of    |
//| them is the freeze: the terminal delivers one create per object it |
//| made, and every one of them asks for the whole ladder again. The   |
//| question this answers is not "is the door heavy" (S4) but "is it    |
//| re-entered by the objects the redraw itself creates".              |
//+------------------------------------------------------------------+
void SGrabDoorStorm()
{
   long zero = 0; double zd = 0.0;
   string nm = "THStress_Box_A";
   if(!MakeRect(nm, 0)) { StW("S4b SKIP: the terminal refused a rectangle"); return; }

   s_ownGrabPrice = (double)ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
   if(s_ownGrabPrice <= 0) s_ownGrabPrice = Close[1];
   double worst = 0, total = 0;
   int made = 0;
   for(int k = 1; k <= 20; k++)
   {
      string nmk = "THStress_S4b_" + IntegerToString(k);
      if(!MakeRect(nmk, k % 20)) break;
      made++;
      StBegin();
      OnChartEventHandler(CHARTEVENT_OBJECT_CREATE, zero, zd, nmk);
      double ms = StEnd();
      total += ms;
      if(ms > worst) worst = ms;
   }
   s_ownGrabPrice = 0.0;   // the harness never leaves a grab held
   double drainMs = StDrain(500);
   StReport("S4b grab-door storm", made, worst, total + drainMs,
            " pend=" + IntegerToString(CustomPriceGrabPending() ? 1 : 0) +
            " drain=" + DoubleToString(drainMs, 1));
   SweepStress();
}

//+------------------------------------------------------------------+
//| S5 — the delete storm, with and without P-UI-21's window          |
//+------------------------------------------------------------------+
void SDeleteStorm()
{
   long zero = 0; double zd = 0.0;
   SweepStress();

   //--- the storm UNSUPPRESSED: every delete of our own namespace that arrives
   //--- outside the window is read as a foreign delete (P-DEL-PROBE) and asks a
   //--- full levels redraw. That is the cost P-DEL-BULK closes for a bulk purge.
   for(int i = 1; i <= STRESS_OURS; i++)
      ObjectCreate(0, "THLevels_Stress_" + IntegerToString(i), OBJ_TREND, 0,
                   Time[30], High[30], Time[10], Low[10]);
   int made = PfxCountStress("THLevels_Stress_");
   g_suppressDeleteEvents = false;
   g_suppressDeleteEventsUntilMs = 0;
   double worst = 0, total = 0;
   for(int i = 1; i <= made; i++)
   {
      string nm = "THLevels_Stress_" + IntegerToString(i);
      ObjectDelete(0, nm);
      StBegin();
      OnChartEventHandler(CHARTEVENT_OBJECT_DELETE, zero, zd, nm);
      double ms = StEnd();
      total += ms;
      if(ms > worst) worst = ms;
   }
   StReport("S5 delete-open", made, worst, total, "");

   //--- the same storm WITH the window armed: the router must answer nothing.
   for(int i = 1; i <= made; i++)
      ObjectCreate(0, "THLevels_Stress_" + IntegerToString(i), OBJ_TREND, 0,
                   Time[30], High[30], Time[10], Low[10]);
   g_suppressDeleteEvents = true;
   worst = 0; total = 0;
   for(int i = 1; i <= made; i++)
   {
      string nm = "THLevels_Stress_" + IntegerToString(i);
      ObjectDelete(0, nm);
      StBegin();
      OnChartEventHandler(CHARTEVENT_OBJECT_DELETE, zero, zd, nm);
      double ms = StEnd();
      total += ms;
      if(ms > worst) worst = ms;
   }
   g_suppressDeleteEvents = false;
   g_suppressDeleteEventsUntilMs = 0;
   StReport("S5 delete-suppressed", made, worst, total, "");

   //--- and the real bulk purge, once: what a DeleteHTFCandles() costs on a chart
   //--- that carries whatever the live session left on it. It arms P-UI-21's window
   //--- INSIDE itself and closes it at both of its exits (P-DEL-BULK), so the
   //--- witness is the object count it took away, not the flag after it returns.
   int htfBefore = ObjectsTotal(0, -1, -1);
   StBegin();
   DeleteHTFCandles();
   double purgeMs = StEnd();
   int htfAfter = ObjectsTotal(0, -1, -1);
   StReport("S5 htf-purge", 1, purgeMs, purgeMs,
            " chart_objs=" + IntegerToString(htfBefore) + "->" + IntegerToString(htfAfter));
   SweepStress();
}

//+------------------------------------------------------------------+
//| S6 — the strip's own open/close, twenty times                     |
//+------------------------------------------------------------------+
void SStripCycle()
{
   string nm = "THStress_Box_A";
   if(!MakeRect(nm, 0)) { StW("S6 SKIP: the terminal refused a rectangle"); return; }
   double worst = 0, total = 0;
   int n = 0;
   for(int i = 0; i < 20; i++)
   {
      StBegin();
      bool ok = DrawStripOpenAt(nm, 120, 120);
      DrawStripPaint();
      DrawStripClose();
      double ms = StEnd();
      n++;
      total += ms;
      if(ms > worst) worst = ms;
      if(!ok) break;
   }
   StReport("S6 strip-cycle", n, worst, total,
            " left_open=" + IntegerToString(s_dsOpen ? 1 : 0));
   SweepStress();
}

//+------------------------------------------------------------------+
//| S7 — the highest-rate event there is                              |
//+------------------------------------------------------------------+
void SMoveStorm()
{
   long lx = 0; double ly = 0;
   double worst = 0, total = 0;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw < 80) cw = 800;
   if(ch < 80) ch = 500;
   string off = "0";   // no button down: a hover, never a press
   for(int i = 0; i < STRESS_MOVES; i++)
   {
      lx = (i * 7) % cw;
      ly = (i * 11) % ch;
      StBegin();
      OnChartEventHandler(CHARTEVENT_MOUSE_MOVE, lx, ly, off);
      double ms = StEnd();
      total += ms;
      if(ms > worst) worst = ms;
   }
   StReport("S7 move-storm", STRESS_MOVES, worst, total, "");
}

//+------------------------------------------------------------------+
//| S8 — the whole-chart walk the attach makes                        |
//+------------------------------------------------------------------+
void SAttachWalk()
{
   for(int k = 1; k <= STRESS_FOREIGN; k++)
      MakeRect("THStress_S8_" + IntegerToString(k), k % 20);
   StBegin();
   DrawInkMemoInit();
   double ms = StEnd();
   StReport("S8 attach-walk", PfxCountStress("THStress_S8_"), ms, ms, "");
   SweepStress();
}

//+------------------------------------------------------------------+
//| S9 — the file the tick path writes, priced (P-HANG-01)            |
//|                                                                  |
//| THE NUMBER THAT REPLACED THE WAIT. Before this card a refused     |
//| history open retried with Sleep(100) between attempts INSIDE the  |
//| function, on the interface thread: 200 ms per new 30-minute block  |
//| and up to a second at attach. Now one attempt arms an ask and the  |
//| pump rewrites the day once. So S9 prices all three: a clean write,  |
//| a FORCED refusal (a second handle on the day file), and the drain  |
//| that answers it. `refused_ms` over ~5 is the wait, come back.      |
//+------------------------------------------------------------------+
void SHistoryPath()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int y = dt.year, d = dt.day_of_year + 1;
   string arr[];
   GetHistoryArray(arr);
   int n = ArraySize(arr);
   if(n <= 0) { StW("S9 SKIP: the RAM history is empty on this chart"); return; }

   StBegin();
   bool wrote = SaveBasePriceHistory(y, d, arr, n);
   double saveMs = StEnd();

   string histPath = GetHistoryFilePath(y, d);
   int    hold     = FileOpen(histPath, FILE_WRITE | FILE_READ);
   bool   haveHold = (hold != INVALID_HANDLE);
   bool   refused  = false;
   bool   armed    = false;
   double armMs    = 0;
   if(haveHold)
   {
      StBegin();
      refused = !SaveBasePriceHistory(y, d, arr, n);
      armMs   = StEnd();
      armed   = BasePriceHistoryFlushPending();
      FileClose(hold);
   }

   double drainMs   = 0;
   int    stillOwed = -1;
   if(armed)
   {
      StBegin();
      CoopPump();
      drainMs   = StEnd();
      stillOwed = (BasePriceHistoryFlushPending() ? 1 : 0);
   }

   StW("S9 hist entries=" + IntegerToString(n) +
       " write=" + IntegerToString(wrote ? 1 : 0) + " save_ms=" + DoubleToString(saveMs, 1) +
       " hold=" + IntegerToString(haveHold ? 1 : 0) + " refused=" + IntegerToString(refused ? 1 : 0) +
       " refused_ms=" + DoubleToString(armMs, 1) + " armed=" + IntegerToString(armed ? 1 : 0) +
       " drain_ms=" + DoubleToString(drainMs, 1) + " still_owed=" + IntegerToString(stillOwed) +
       " deferred=" + IntegerToString((int)BasePriceHistoryDeferredN()));
   if(armMs > STRESS_WARN_MS || drainMs > STRESS_WARN_MS || saveMs > STRESS_WARN_MS)
   { g_stFail++; StW("S9 verdict=HANG the file path cost over 40 ms in one call - a wait is back"); }
   else if(armed && stillOwed == 1)
   { g_stWarn++; StW("S9 verdict=SLOW the pump did not answer the ask in its beat"); }
   else StW("S9 verdict=OK the refusal is late, never lost, and nobody waits");
}

//+------------------------------------------------------------------+
void OnStart()
{
   if(Bars < 60) { StW("SKIP: the chart has fewer than 60 bars"); StDone("SKIP: fewer than 60 bars"); return; }
   g_UI.btnPrefix = "BiotakMenuV2_" + IntegerToString(ChartID()) + "_";
   if(s_dsOpen || g_PnlOpen >= 0)
   {
      StW("SKIP: a live strip or settings panel is open — close it first (the objects are shared)");
      StDone("SKIP: a strip or panel is open");
      return;
   }
   StW("begin bars=" + IntegerToString(Bars) + " tf=" + IntegerToString(_Period) +
       " objs=" + IntegerToString(ObjectsTotal(0, -1, -1)) +
       " prefix=" + inpObjectPrefix);

   SCreate();
   SCtrlCopy();
   SCopyStorm();
   SGrabDoor();
   SGrabDoorStorm();
   SDeleteStorm();
   SStripCycle();
   SMoveStorm();
   SAttachWalk();
   SHistoryPath();

   ChartRedraw();
   int left = PfxCountStress("THStress_") + PfxCountStress("THLevels_Stress_");
   StW("RESULT fail=" + IntegerToString(g_stFail) + " slow=" + IntegerToString(g_stWarn) +
       " left=" + IntegerToString(left) +
       " objs=" + IntegerToString(ObjectsTotal(0, -1, -1)));
   // The one line that answers the user's question directly: a run with
   // fail=0 has no action over 2 s, and slow=0 none over the 40 ms the live
   // ledger already calls a stall.
   StDone("fail=" + IntegerToString(g_stFail) + " slow=" + IntegerToString(g_stWarn) +
          " left=" + IntegerToString(left));
}
//+------------------------------------------------------------------+
