//+------------------------------------------------------------------+
//|                                        HTFCandles_Draw.mqh       |
//|                                                                  |
//| P-HTF-SPLIT (2026-09-30): the overlay's OBJECT owner — the chart  |
//| rectangle upsert, the card cull, the prune, the look probe and    |
//| the draw passes that spend them. Part 2 of 3; see                 |
//| HTFCandles_Geom.mqh for the split's map and the include order.     |
//+------------------------------------------------------------------+
#ifndef HTF_CANDLES_DRAW_MQH
#define HTF_CANDLES_DRAW_MQH

//+------------------------------------------------------------------+
//| Upsert rectangle object on chart                                 |
//|                                                                  |
//| P-PERF-02: the 10 unconditional property writes became "write     |
//| only what changed" — the cache stores the geometry/visuals we last |
//| wrote, so an unchanged candle costs ONE ObjectFind and nothing     |
//| else while a live forming candle writes only its 1-3 moved values. |
//+------------------------------------------------------------------+
void HTFRectUpsert(const string name, const datetime t1, const double p1,
                   const datetime t2, const double p2,
                   const color clr, const int width,
                   const bool fill, const bool back)
{
   bool onChart = (ObjectFind(0, name) >= 0);
   if(!onChart)
   {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
      CacheUpdateZone(name, p1, p2, t1, t2, clr, fill, 0, width);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_FILL, fill);
      ObjectSetInteger(0, name, OBJPROP_BACK, back);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      return;
   }

   SObjectCacheEntry e;
   bool known = CacheGetObject(name, e) && e.exists;
   if(known) {
      if(e.lastTime1 != t1)   ObjectSetInteger(0, name, OBJPROP_TIME1, t1);
      if(e.lastPrice != p1)   ObjectSetDouble(0, name, OBJPROP_PRICE1, p1);
      if(e.lastTime2 != t2)   ObjectSetInteger(0, name, OBJPROP_TIME2, t2);
      if(e.lastPrice2 != p2)  ObjectSetDouble(0, name, OBJPROP_PRICE2, p2);
      if(e.lastColor != clr)  ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      if(e.lastWidth != width) ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      if(e.lastFilled != fill) ObjectSetInteger(0, name, OBJPROP_FILL, fill);
   } else {
      // First sight of an object we did not create (template reload, another
      // chart of the same id): re-assert the whole look once.
      //
      // TYPE FENCE: a name in our namespace is a RECTANGLE by construction, but
      // an older build drew the HTF shadow as an OBJ_TREND, and a template can
      // carry one into this instance. Writing rectangle properties onto a trend
      // line would leave a thin line where a shadow box belongs — for the life
      // of the chart, because the name never changes. Rebuild it instead. ONE
      // read on a path that already writes ten properties, and it cannot be
      // reached for an object this instance created (the cache would know it).
      if(ObjectGetInteger(0, name, OBJPROP_TYPE) != OBJ_RECTANGLE)
      {
         ObjectDelete(0, name);
         if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
      }
      ObjectSetInteger(0, name, OBJPROP_TIME1, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE1, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME2, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_FILL, fill);
      ObjectSetInteger(0, name, OBJPROP_BACK, back);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   CacheUpdateZone(name, p1, p2, t1, t2, clr, fill, 0, width);
}

//+------------------------------------------------------------------+
//| Do any HTF boxes exist? Probes bars 0..2 across every name shape |
//| the core can create (body / BOTH variants / wicks). Sampling three|
//| bars keeps it correct when bodies are off or a forming doji has   |
//| no wicks — a single ObjectFind(prefix+"0") would miss those and   |
//| force a full 200-bar redraw every second.                        |
//|                                                                  |
//| P-PERF-14: defined HERE, above DeleteHTFCandles(), because that   |
//| function's steady-state guard needs it and MQL4 has no clean      |
//| forward declaration (a bare prototype compiles as warning 46).    |
//+------------------------------------------------------------------+
bool HTFAnyBoxesExist()
{
   if(StringLen(g_HTFPrefix) == 0) return false;
   for(int i = 0; i < 3; i++)
   {
      string id = IntegerToString(i);
      if(ObjectFind(0, g_HTFPrefix + id) >= 0) return true;
      if(ObjectFind(0, g_HTFPrefix + id + "_F") >= 0) return true;
      if(ObjectFind(0, g_HTFPrefix + "WU" + id) >= 0) return true;
      if(ObjectFind(0, g_HTFPrefix + "WL" + id) >= 0) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| P-UI-98r — HTF CANDLES STAY BEHIND OPEN UI (card, palette).       |
//|                                                                  |
//| Reported with a screenshot: hollow HTF boxes paint OVER the open  |
//| settings card. The Z ladder cannot fix this: MT4 keeps            |
//| SCREEN-SPACE objects (the panel skins) in one list painted in     |
//| ZORDER order, while CHART objects (these rectangles) paint in     |
//| their own pass - a chart rectangle with BACK=false lands over a   |
//| screen skin at ANY rung (the hollow mode needs BACK=false to stay |
//| over the M5 candles, so flipping BACK would sink the whole family |
//| behind the price it overlays). What CAN put a chart object behind |
//| an opaque card is absence: a masked box paints nowhere, which is  |
//| pixel-identical to "behind" under an opaque surface.              |
//|                                                                  |
//| So an open card/palette masks the boxes it covers, by NAME, from  |
//| the published screen rects (PnlPublishCover - this module is      |
//| included BEFORE BiotakPanels, so the rects cross on shared        |
//| globals, the g_UIPanelOpen precedent). Geometry comes from the    |
//| object cache the upsert already maintains - no terminal reads per  |
//| box, no geometry recompute. Masked names are TRACKED, so the      |
//| release path unmasks exactly what the cull masked (never a naive  |
//| ALL that would resurrect a family F-hide put away: the target is  |
//| hidden ? NO : ALL). Anything the cull cannot prove - no card,     |
//| HTF off, nothing drawn, an unprojectable window - fails OPEN      |
//| (hands off, old behaviour).                                       |
//+------------------------------------------------------------------+
static string s_htfCulled[];
static int    s_htfCulledN = 0;

bool HTFCullHas(const string name)
{
   for(int i = 0; i < s_htfCulledN; i++)
      if(s_htfCulled[i] == name) return true;
   return false;
}

void HTFCullTrack(const string name)
{
   if(HTFCullHas(name)) return;
   ArrayResize(s_htfCulled, s_htfCulledN + 1);
   s_htfCulled[s_htfCulledN] = name;
   s_htfCulledN++;
}

void HTFCullUntrack(const string name)
{
   for(int i = 0; i < s_htfCulledN; i++)
   {
      if(s_htfCulled[i] != name) continue;
      s_htfCulled[i] = s_htfCulled[s_htfCulledN - 1];
      s_htfCulledN--;
      ArrayResize(s_htfCulled, s_htfCulledN);
      return;
   }
}

void HTFCullForget(const string name) { HTFCullUntrack(name); }

// P-HTF-KEY — ONE composer for an HTF box's mask. The toggle, the F mute and
// the panel cover share one visibility bit each; every writer (toggle walk,
// cull cover/release) asks here, so no path can resurrect a box another put
// away (paint and hit-test agree because nothing else writes the mask).
long HTFBoxMask(const bool covered)
{
    if(!g_UI.showHTF || IsIndicatorHidden()) return OBJ_NO_PERIODS;
    return covered ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
}

// P-HTF-PROBE (2026-09-30): the cull is the ONE place in this module that can hide
// an already-drawn box WITHOUT deleting it (`OBJ_TIMEFRAMES = OBJ_NO_PERIODS` on the
// names a published card rect covers), and a hidden box looks exactly like "the
// shadow vanished". So the tracked count is on the record whenever it moves - one
// int compare in the steady state.
void HTFProbeCull()
{
   static int s_lastTracked = -1;
   if(s_htfCulledN == s_lastTracked) return;
   s_lastTracked = s_htfCulledN;
   Print("[P-HTF] cull masked=", s_htfCulledN, " panelOpen=", (g_UIPanelOpen ? 1 : 0),
         " drawn=", g_HTFDrawnCount);
}

// One published rect to a chart window. False = unusable (fail open).
bool HTFCullRectWindow(const int rx, const int ry, const int rw, const int rh,
                       datetime &t1, datetime &t2, double &pHi, double &pLo)
{
   t1 = 0; t2 = 0; pHi = 0.0; pLo = 0.0;
   if(rx < 0 || rw <= 0 || rh <= 0) return false;
   int swA = 0, swB = 0;
   datetime ta = 0, tb = 0;
   double pa = 0.0, pb = 0.0;
   if(!ChartXYToTimePrice(0, rx, ry, swA, ta, pa)) return false;
   if(!ChartXYToTimePrice(0, rx + rw, ry + rh, swB, tb, pb)) return false;
   t1 = (ta < tb ? ta : tb);
   t2 = (ta < tb ? tb : ta);
   pHi = (pa > pb ? pa : pb);
   pLo = (pa > pb ? pb : pa);
   return ((t2 > t1) && (pHi > pLo));
}

//+------------------------------------------------------------------+
//| Delete HTF objects for history indices [from,to) — used to prune |
//| only the trailing tail after an in-place redraw shrinks, instead  |
//| of a full delete+recreate (no flicker, no drag-freeze).          |
//|                                                                  |
//| P-PERF-47: DEFINED HERE, above DeleteHTFCandles(), for the same   |
//| reason HTFAnyBoxesExist is (P-PERF-14 above): that function now   |
//| uses it, and MQL4 has no clean forward declaration (a bare        |
//| prototype compiles as warning 46).                                |
//+------------------------------------------------------------------+
void HTFDeleteIndices(const int from, const int to)
{
   if(StringLen(g_HTFPrefix) == 0 || to <= from) return;
   for(int i = from; i < to; i++)
   {
      string id = IntegerToString(i);
      ObjectDelete(0, g_HTFPrefix + id);
      ObjectDelete(0, g_HTFPrefix + id + "_F");
      ObjectDelete(0, g_HTFPrefix + id + "_B");
      ObjectDelete(0, g_HTFPrefix + "WU" + id);
      ObjectDelete(0, g_HTFPrefix + "WL" + id);
      // P-UI-98r: a pruned box leaves the card-cull set with it - a tracked
      // name that no longer exists must not linger (its release write would
      // fail silent, and the slot is a lie the next refresh would keep).
      HTFCullForget(g_HTFPrefix + id);
      HTFCullForget(g_HTFPrefix + id + "_F");
      HTFCullForget(g_HTFPrefix + id + "_B");
      HTFCullForget(g_HTFPrefix + "WU" + id);
      HTFCullForget(g_HTFPrefix + "WL" + id);
   }
}

// The cull pass. Reads-only while healthy: two projections per open surface,
// cache probes per box, a terminal write only for a box that FLIPS state.
void HTFCardCullRefresh()
{
   if(StringLen(g_HTFPrefix) == 0 || g_HTFDrawnCount <= 0) { HTFCullRelease(); return; }
   if(!g_UIPanelOpen) { HTFCullRelease(); return; }   // no cover possible: tracked set is stale
   if(!g_UI.showHTF) return;   // toggle masks own the boxes; registry stays for ON
   datetime t1A = 0, t2A = 0, t1B = 0, t2B = 0;
   double pHiA = 0.0, pLoA = 0.0, pHiB = 0.0, pLoB = 0.0;
   bool winA = HTFCullRectWindow(g_UIPanelRX, g_UIPanelRY, g_UIPanelRW, g_UIPanelRH,
                                 t1A, t2A, pHiA, pLoA);
   bool winB = HTFCullRectWindow(g_UIPPalRX, g_UIPPalRY, g_UIPPalRW, g_UIPPalRH,
                                 t1B, t2B, pHiB, pLoB);
   if(!winA && !winB)
   {
      HTFCullRelease();
      return;
   }
   for(int i = 0; i < g_HTFDrawnCount; i++)
   {
      string id = IntegerToString(i);
      string nm[5];
      nm[0] = g_HTFPrefix + id;
      nm[1] = g_HTFPrefix + id + "_F";
      nm[2] = g_HTFPrefix + id + "_B";
      nm[3] = g_HTFPrefix + "WU" + id;
      nm[4] = g_HTFPrefix + "WL" + id;
      for(int k = 0; k < 5; k++)
      {
         SObjectCacheEntry e;
         if(!CacheGetObject(nm[k], e) || !e.exists) { HTFCullUntrack(nm[k]); continue; }
         datetime bt1 = (e.lastTime1 < e.lastTime2 ? e.lastTime1 : e.lastTime2);
         datetime bt2 = (e.lastTime1 < e.lastTime2 ? e.lastTime2 : e.lastTime1);
         double bHi = (e.lastPrice > e.lastPrice2 ? e.lastPrice : e.lastPrice2);
         double bLo = (e.lastPrice > e.lastPrice2 ? e.lastPrice2 : e.lastPrice);
         bool cover = false;
         if(winA && bt1 <= t2A && bt2 >= t1A && bLo <= pHiA && bHi >= pLoA) cover = true;
         if(!cover && winB && bt1 <= t2B && bt2 >= t1B && bLo <= pHiB && bHi >= pLoB) cover = true;
         bool tracked = HTFCullHas(nm[k]);
         if(cover && !tracked)
         {
            ObjectSetInteger(0, nm[k], OBJPROP_TIMEFRAMES, HTFBoxMask(true));
            HTFCullTrack(nm[k]);
         }
         else if(!cover && tracked)
         {
            ObjectSetInteger(0, nm[k], OBJPROP_TIMEFRAMES, HTFBoxMask(false));
            HTFCullUntrack(nm[k]);
         }
      }
   }
   HTFProbeCull();   // P-HTF-PROBE: the count AFTER this pass's masks/releases
}

// Give back exactly what the cull took (open-order callers only).
void HTFCullRelease()
{
   if(s_htfCulledN <= 0) return;
   for(int i = 0; i < s_htfCulledN; i++)
      ObjectSetInteger(0, s_htfCulled[i], OBJPROP_TIMEFRAMES, HTFBoxMask(false));
   ArrayResize(s_htfCulled, 0);
   s_htfCulledN = 0;
   HTFProbeCull();   // P-HTF-PROBE: the mask count is back to 0
}

//+------------------------------------------------------------------+
//| Delete all HTF candle objects                                    |
//| Empty-prefix guard: StringFind(name,"")==0 matches EVERY object — |
//| without this, a call before InitializeHTFCandles would wipe other|
//| indicators' rectangles/trends off the chart.                     |
//+------------------------------------------------------------------+
void DeleteHTFCandles()
{
   if(StringLen(g_HTFPrefix) == 0) return;

   // P-PERF-14: ONE bulk prefix delete replaces two full-chart walks.
   //
   // The old shape asked the terminal for the TOTAL of every OBJ_RECTANGLE and
   // then of every OBJ_TREND on the chart, and called ObjectName() once per
   // object to reject the ones that are not ours. That chart legitimately
   // carries thousands of OUR OWN zone rectangles, so the walk was O(chart
   // objects) - and it ran on the OnDeinit path (every timeframe switch, which
   // the log measures at ~300 ms) and on EVERY steady-state HTF early-out
   // ("HTF off" / "HTF <= chart TF").
   //
   // ObjectsDeleteAll(chart_id, prefix) is the documented bulk form
   // (docs.mql4.com/objects/objectsdeleteall) and matches exactly the same set:
   // both loops tested "name starts with g_HTFPrefix" - the trend loop only
   // appended "W" to the prefix, and every wick name carries it - so one call
   // is equivalent, with the scan left inside the terminal instead of paying an
   // inter-module call per object.
   //
   // The steady state costs nothing: the owner's own bookkeeping must say
   // something was drawn, or an O(1) name probe must disagree (bars 0..2 cover
   // every shape and every variant the core creates, and a draw always starts
   // at index 0 - so "nothing at 0..2" cannot hide a tail).
   if(g_HTFDrawnCount <= 0 && !HTFAnyBoxesExist()) return;

   // P-PERF-47: NAME-BASED DELETE FOR THE FAMILY WE CAN ACCOUNT FOR; THE PREFIX
   // WIPE IS KEPT ONLY AS THE NET.
   //
   // The single bulk call above was not cheap, and the teardown ledger said so:
   //   [W][PERF] OnDeinit breakdown: pnl=… menu=0ms htf=219ms save=0ms …
   // on EVERY timeframe switch, against an MT4 teardown that never once exceeded
   // the 150 ms budget in a whole trading day.
   //
   // The reason is the SHAPE of the cost. `ObjectsDeleteAll(chart, prefix)` walks
   // the WHOLE chart object list and removes every match, so its bill scales with
   // the CHART — and this indicator fills the chart with the level family. The WORK,
   // though, is bounded by the HTF family, which is one to two orders of magnitude
   // smaller: a few dozen candles carrying exactly five names each. The live MT5
   // probe prices the two sides: a prefix scan pays ~85 us per chart object, while a
   // name probe on a name we drew costs ~52 us — so keying the delete on the family
   // instead of on the chart is a large win, and it gets larger the fuller the chart.
   //
   // WHY AN INDEX-KEYED DELETE IS CORRECT *HERE* — this is the one family where the
   // index and the price move together, so it does not repeat the R-LEVEL-NAME
   // mistake. `i` is the i-th HTF bar: `DrawHTFCandleCore` builds every name from it
   // (`string wickId = IntegerToString(i);` and the body names `g_HTFPrefix +
   // IntegerToString(i)`), so the same `i` always means the same candle and the same
   // five names. There is no context that could re-point it at a different price.
   //
   // The net is what keeps this honest. `g_HTFDrawnCount` is the drawer's own
   // bookkeeping, so a chart it cannot account for — a stale prefix, an interrupted
   // draw, a template that carried our names — still gets the unconditional wipe,
   // and the wipe is reached whenever the 4-probe question says anything is left.
   // The probe set is a sound superset of "something of ours survives": in
   // HTF_BOX_BOTH mode `_F` is created whenever `_B` is (see the `baseName + "_F"`
   // / `baseName + "_B"` pair in DrawHTFCandleCore), so the four names checked cover
   // all three box modes plus both wicks.
   if(g_HTFDrawnCount > 0)
   {
      HTFDeleteIndices(0, g_HTFDrawnCount);
      g_HTFDrawnCount = 0;
      if(!HTFAnyBoxesExist()) return;   // family fully accounted for — no wipe
   }

   ObjectsDeleteAll(0, g_HTFPrefix);
   g_HTFDrawnCount = 0;   // nothing of ours is on the chart any more
}

// P-PERF-47: the SINGLE definition of HTFDeleteIndices now lives ABOVE this
// function (beside HTFAnyBoxesExist), because DeleteHTFCandles calls it and MQL4
// has no clean forward declaration — a bare prototype compiles as warning 46, the
// same trap the P-PERF-14 note above records. Do not re-add a copy here.

//+------------------------------------------------------------------+
//| P-HTF-PROBE (2026-09-30, Touch rule 5)                           |
//|                                                                  |
//| The report is a LOOK: the shadow is drawn and then gone, and the  |
//| body carries a border but no fill. Both are decided by THREE      |
//| numbers - BOX (hollow/filled/both), SHOW WICKS and SHOW BODY -    |
//| and the look can only move when one of them moves: `isTrigger`-   |
//| style guesses are what this project refuses. So the probe names    |
//| the resolved triple at the moments it can change (init, every     |
//| card row write, every draw pass) and stays SILENT when it has     |
//| not. Zero steady-state cost: three compares and one int.          |
//+------------------------------------------------------------------+
void HTFProbeSettings(const string why)
{
   static int  s_lastMode  = -1;
   static bool s_lastWicks = false;
   static bool s_lastBody  = false;
   if(s_lastMode == g_HTFBoxMode && s_lastWicks == g_HTFShowWicks && s_lastBody == g_HTFShowBody)
      return;
   s_lastMode  = g_HTFBoxMode;
   s_lastWicks = g_HTFShowWicks;
   s_lastBody  = g_HTFShowBody;
   Print("[P-HTF] ", why, " mode=", g_HTFBoxMode, " wicks=", (g_HTFShowWicks ? 1 : 0),
         " body=", (g_HTFShowBody ? 1 : 0), " shadow%=", g_HTFShadowPct,
         " gap%=", g_HTFGapPct, " opacity=", g_HTFOpacity, " drawn=", g_HTFDrawnCount,
         " hidden=", (IsIndicatorHidden() ? 1 : 0));
}

//+------------------------------------------------------------------+
//| THE SHADOW BOX (P-UI-68)                                         |
//|                                                                  |
//| A wick used to be an OBJ_TREND of g_HTFWickWidth px. The request  |
//| is a BOX — the shape of the screenshot — so the shadow is now a   |
//| FILLED RECTANGLE whose x span is owned by HTFCandleGeometry (a    |
//| share of the candle, centred on the body) and whose look is        |
//| re-asserted, never written once, by the same guarded upsert the   |
//| body uses. Steady state = one ObjectFind per box per pass and zero |
//| terminal writes; a look that changes (colour, fill, width) is      |
//| re-compared and re-written (the P-UI-66 lesson: a write-once look  |
//| is a slider that lies).                                            |
//|                                                                   |
//| The width argument stays 1: the fill and the border share one      |
//| colour, so a border could only fatten the box. Thickness is a      |
//| GEOMETRY question — SHADOW WIDTH (%) floored by SHADOW MIN (px) —  |
//| and it is answered in one place, HTFCandleGeometry.                |
//|                                                                   |
//| OBJPROP_BACK stays TRUE, exactly like the old wick: the shadow is  |
//| a wash UNDER the price action, never above the terminal's candles, |
//| the level lines or the indicator's own overlays (Z-ORDER rule).    |
//+------------------------------------------------------------------+
void HTFShadowBox(const string name, const datetime tL, const double p1,
                  const datetime tR, const double p2, const color clr)
{
   HTFRectUpsert(name, tL, p1, tR, p2, clr, 1, true, true);
}

//+------------------------------------------------------------------+
//| Draw HTF Candle Core                                             |
//+------------------------------------------------------------------+
void DrawHTFCandleCore(const int i, const datetime ot, const datetime nt,
                       const double hi, const double lo,
                       const double op, const double cl)
{
   // P-HTF-PROBE: name the look the very draw pass that rebuilds it is using.
   HTFProbeSettings("draw");
   double bodyHi = g_HTFShowWicks ? MathMax(op, cl) : hi;
   double bodyLo = g_HTFShowWicks ? MathMin(op, cl) : lo;

   // ONE geometry for the whole candle: where the body starts and ends (the
   // SHADOW GAP inset) and where the shadow box sits (a share of the candle,
   // centred on the DRAWN middle). Nothing below recomputes an x by hand, so a
   // calendar midpoint cannot creep back into one of the three objects while
   // the others use the drawn one.
   //
   // P-HTF-SLOT: on a rung wider than the window the two edges are the SLOT
   // grid's (HTFRefreshSlotMetrics) — the shape law below is the SAME one, so a
   // slotted candle is the rung's own candle, only narrower. Copies, not the
   // arguments: the true `ot` is the candle's identity for the live-edge cache.
   datetime otSlot = ot, ntSlot = nt;
   HTFSlotTimes(i, otSlot, ntSlot);
   SHTFCandleGeom gm = HTFCandleGeometry(otSlot, ntSlot);

   double opct = g_HTFOpacity / 100.0;
   color candleClr = BlendWithBackground(cl >= op ? g_HTFBullColor : g_HTFBearColor, opct);
   // WICK COLOR = NONE means "follow the candle", the same contract BORDER
   // COLOR already had (clrNONE -> the body's own colour). It is what makes a
   // shadow box look like the reference: one colour per candle, direction
   // included, without a second colour setting to keep in sync.
   color wickClr   = (g_HTFWickColor == clrNONE)
                     ? candleClr
                     : BlendWithBackground(g_HTFWickColor, opct);
   color borderClr = (g_HTFBorderColor == clrNONE)
                     ? candleClr
                     : BlendWithBackground(g_HTFBorderColor, opct);

   string wickId = IntegerToString(i);
   if(!g_HTFShowWicks)
   {
      ObjectDelete(0, g_HTFPrefix + "WU" + wickId);
      ObjectDelete(0, g_HTFPrefix + "WL" + wickId);
   }
   else
   {
      // Both shadows come from the SAME box columns, so they stay vertically
      // aligned with each other and centred on the body whatever the weekend
      // (or a holiday) does to the calendar inside the period.
      string upName = g_HTFPrefix + "WU" + wickId;
      string dnName = g_HTFPrefix + "WL" + wickId;
      if(hi > bodyHi) HTFShadowBox(upName, gm.shadowL, bodyHi, gm.shadowR, hi, wickClr);
      else            ObjectDelete(0, upName);
      if(lo < bodyLo) HTFShadowBox(dnName, gm.shadowL, lo, gm.shadowR, bodyLo, wickClr);
      else            ObjectDelete(0, dnName);
   }

   string baseName = g_HTFPrefix + IntegerToString(i);
   if(!g_HTFShowBody)
   {
      ObjectDelete(0, baseName);
      ObjectDelete(0, baseName + "_F");
      ObjectDelete(0, baseName + "_B");
      return;
   }
   const color bodyBase = (cl >= op) ? g_HTFBullColor : g_HTFBearColor;

   if(g_HTFBoxMode == HTF_BOX_FILLED)
   {
      HTFRectUpsert(baseName, gm.bodyL, bodyHi, gm.bodyR, bodyLo,
                    BlendWithBackground(bodyBase, HTF_FILL_STRONG), 1, true, true);
   }
   else if(g_HTFBoxMode == HTF_BOX_BOTH)
   {
      HTFRectUpsert(baseName + "_F", gm.bodyL, bodyHi, gm.bodyR, bodyLo,
                    BlendWithBackground(bodyBase, HTF_FILL_FAINT), 1, true, true);
      HTFRectUpsert(baseName + "_B", gm.bodyL, bodyHi, gm.bodyR, bodyLo,
                    borderClr, g_HTFBorderWidth, false, false);
   }
   else
   {
      HTFRectUpsert(baseName, gm.bodyL, bodyHi, gm.bodyR, bodyLo,
                    borderClr, g_HTFBorderWidth, false, false);
   }
}

//+------------------------------------------------------------------+
//| Update only the forming HTF candle (intra-bar updates)            |
//+------------------------------------------------------------------+
bool UpdateHTFFormingCandle()
{
   if(!g_UI.showHTF || Bars < 2) return false;
   int tf = ResolveHTFPeriod();
   // P-HTF-TOP: `>=` — a rung equal to the chart TF draws (the monthly overlay on
   // a monthly chart IS the structure rung there); only a rung BELOW it is nothing.
   if(tf <= 0 || tf < (int)Period()) return false;

   // P-HTF-SYN: a 6M/12M rung has no terminal series, and its bar's open is calendar
   // arithmetic (free) — so the throttle check below still runs BEFORE any read,
   // exactly as it does for a real rung's one iTime.
   bool syn = HTFTfIsSynthetic(tf);
   datetime ot = syn ? HTFSynBarOpen(tf, 0) : iTime(_Symbol, tf, 0);
   if(ot <= 0) return false;

   // P-PERF-02 write budget: a live candle is redrawn at most every
   // HTF_FORM_MS — checked BEFORE the remaining four series reads, so a
   // throttled tick costs one iTime and nothing else. A NEW BAR (open time
   // moved) is a structural change and always draws now. Returning early
   // leaves the live-edge cache untouched, so the deferred update lands on
   // the very next call.
   uint formNow = GetTickCount();
   bool formNewBar = (ot != g_HTFLastFormOpen);
   if(!formNewBar && g_HTFFormWriteMs != 0 && (formNow - g_HTFFormWriteMs) < HTF_FORM_MS)
      return false;

   double op = 0.0, cl = 0.0, hi = 0.0, lo = 0.0;
   if(syn)
   {
      // The live bucket's OHLC is the aggregate of its own MN1 months (the newest
      // of which is the current month), so the live candle grows with the bucket.
      if(!HTFSynOHLC(tf, ot, op, hi, lo, cl)) return false;
   }
   else
   {
      op = iOpen(_Symbol, tf, 0); cl = iClose(_Symbol, tf, 0);
      hi = iHigh(_Symbol, tf, 0); lo = iLow(_Symbol, tf, 0);
      if(hi <= 0 || lo <= 0) return false;
   }

   if(!formNewBar &&
      op == g_HTFLastFormO && hi == g_HTFLastFormH &&
      lo == g_HTFLastFormL && cl == g_HTFLastFormC) return false;

   g_HTFFormWriteMs = formNow;

   g_HTFLastFormOpen = ot;
   g_HTFLastFormO = op; g_HTFLastFormH = hi;
   g_HTFLastFormL = lo; g_HTFLastFormC = cl;

   HTFMidMemoReset();             // its own snapshot: a bar may have closed since the last pass
   HTFRefreshBlendBackground();   // P-PERF-08: once per draw pass, not once per colour
   HTFRefreshPixelMetrics();      // P-UI-68: the shadow's pixel floor needs the zoom once
   HTFRefreshSlotMetrics(tf);     // P-HTF-SLOT: the SAME pitch the history pass lays out
   DrawHTFCandleCore(0, ot, HTFBarCloseTime(ot, tf), hi, lo, op, cl);
   return true;
}

//+------------------------------------------------------------------+
//| Redraw all historical HTF candles (IN-PLACE, no flicker)         |
//| Returns bars drawn (>=0), or -1 when HTF history is not ready yet|
//| (weak PC / fresh TF-switch) so the caller retries later instead  |
//| of leaving an empty chart. Same-index objects are upserted in    |
//| place — only a shrunken tail is pruned and only a box/shape flip |
//| wipes all (slider drags recolor without delete+recreate churn).  |
//+------------------------------------------------------------------+
// How many HTF bars does the CURRENT viewport actually need? Everything
// further left than the visible range + headroom cannot be seen.
int HTFViewportBarTarget()
{
   int want = InpHTFMaxBars;
   int htf = ResolveHTFPeriod();
   int chartTf = (int)Period();
   // P-HTF-TOP: `>=` — on the chart's own rung the pitch is exactly one bar, so the
   // viewport cap must still run (ratio 1) instead of falling back to the flat 200.
   if(htf >= chartTf && chartTf > 0)
   {
      int firstVis = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0);
      int visBars  = (int)ChartGetInteger(0, CHART_VISIBLE_BARS, 0);
      if(firstVis < 0) firstVis = 0;
      if(visBars < 1)  visBars = 1;
      // P-HTF-SLOT: a slotted rung's pitch is the SLOT, not the calendar ratio —
      // the cap must count the bars a candle ACTUALLY occupies, or the strip
      // would be asked for candles the window cannot even hold. The two numbers
      // are equal on every rung that is not slotted (s_HTFSlot = 0), so nothing
      // else moves.
      double ratio = (s_HTFSlot > 0.0) ? s_HTFSlot : (double)htf / (double)chartTf;
      int need = (int)MathCeil((double)(firstVis + visBars) / ratio) + 2;
      if(need < HTF_CULL_MIN) need = HTF_CULL_MIN;
      if(need < want) want = need;
   }
   if(want < 1) want = 1;
   return want;
}

// Is the drawn set out of step with the viewport? Throttled: two
// ChartGetInteger calls, but a tick storm must not call HTFViewportBarTarget
// 30 times a second (the 1 s probe and the chart-change hook are enough).
#define HTF_RANGE_MS 100
static double s_HTFSlotDrawn = 0.0;   // the pitch the boxes on the chart were laid out with
bool HTFRangeStale()
{
   if(g_HTFDrawnCount <= 0) return false;
   static uint s_rangeMs = 0;
   uint nowMs = GetTickCount();
   if(s_rangeMs != 0 && nowMs - s_rangeMs < HTF_RANGE_MS) return false;
   s_rangeMs = nowMs;
   // P-HTF-SLOT: the pitch is VIEWPORT-shaped, so this throttled probe is where a
   // zoom re-pitches a slotted strip — and a moved pitch IS a stale range (the
   // boxes still stand on the old grid). The refresh costs the one
   // CHART_VISIBLE_BARS read the target below pays anyway, and the compare is
   // free; both are zero on a rung that is not slotted.
   HTFRefreshSlotMetrics(ResolveHTFPeriod());
   if(s_HTFSlot != s_HTFSlotDrawn) return true;
   int viewTarget = HTFViewportBarTarget();
   return (viewTarget > g_HTFDrawnCount || viewTarget + HTF_CULL_HYST < g_HTFDrawnCount);
}

int DrawHTFCandles()
{
   static int s_prevCount = 0;
   if(!g_UI.showHTF || Bars < 2) { DeleteHTFCandles(); s_prevCount = 0; return 0; }
   int tf = ResolveHTFPeriod();
   // P-HTF-TOP: the same `>=` as the forming candle and the ensure probe — one
   // rule, three sites, so the overlay cannot draw history while hiding the live
   // candle (or the reverse) on the chart's own rung.
   if(tf <= 0 || tf < (int)Period()) { DeleteHTFCandles(); s_prevCount = 0; return 0; }
   HTFMidMemoReset();             // one geometry snapshot per pass — see the memo
   HTFRefreshBlendBackground();   // P-PERF-08: one background read for the whole pass
   HTFRefreshPixelMetrics();      // P-UI-68: one zoom read for the whole pass too
   HTFRefreshSlotMetrics(tf);     // P-HTF-SLOT: the pitch both the target and the grid read
   bool syn = HTFTfIsSynthetic(tf);   // P-HTF-SYN: 6M/12M are built from MN1
   int total = syn ? HTFSynBarCount(tf) : iBars(_Symbol, tf);
   if(total <= 0) return -1;
   datetime ot0 = syn ? HTFSynBarOpen(tf, 0) : iTime(_Symbol, tf, 0);
   if(ot0 <= 0) return -1;
   int count = MathMin(InpHTFMaxBars, total);

   static int s_lastBoxMode = -1;
   static bool s_lastShowBodyBox = false;
   if(s_lastBoxMode != g_HTFBoxMode || s_lastShowBodyBox != g_HTFShowBody)
   {
      DeleteHTFCandles();
      s_prevCount = 0;
      s_lastBoxMode = g_HTFBoxMode;
      s_lastShowBodyBox = g_HTFShowBody;
   }

   // P-PERF-02 viewport cap (hysteresis keeps a zoom-out/zoom-in see-saw from
   // re-creating bars it just pruned).
   int viewTarget = HTFViewportBarTarget();
   if(count > viewTarget) count = MathMin(count, viewTarget + HTF_CULL_HYST);

   // P-HTF-SLOT: a slotted strip can only place the candles the loaded history
   // reaches — HTFChartTimeAt clamps an index past the oldest bar onto that bar,
   // and that clamp is exactly the pile-up (several candles on one slot) the
   // pitch exists to avoid. One divide, no reads: the grid is anchored at bar 0.
   if(s_HTFSlot > 0.0)
   {
      int fit = (int)MathFloor((double)(Bars - 1) / s_HTFSlot);
      if(fit < 1) fit = 1;
      if(count > fit) count = fit;
   }

   // P-PERF-02/47: `count` is the drawer's OWN bookkeeping (the cull loops it, the
   // prune diffs it, the viewport probe compares it, DeleteHTFCandles accounts for
   // it), so it is set AFTER the box-mode flip — whose DeleteHTFCandles() zeroes
   // it. Until 2026-09-30 this assignment stood above the flip, so every BOX flip
   // left `drawn=0` with `count` boxes on the chart: the cull went blind (it
   // returns on drawn<=0), the range probe answered "not stale" forever after, and
   // only the next HTF bar healed it.
   g_HTFDrawnCount = count;

   for(int i = 0; i < count; i++)
   {
      datetime ot = syn ? HTFSynBarOpen(tf, i) : iTime(_Symbol, tf, i);
      // A synthetic bar's close IS its bucket's next boundary (the buckets are
      // contiguous calendar blocks), so there is no `i - 1` bar to read there.
      datetime nt = (syn || i == 0) ? HTFBarCloseTime(ot, tf) : iTime(_Symbol, tf, i - 1);
      if(ot <= 0 || nt <= ot)
      {
         if(i == 0) return -1;
         continue;
      }
      double hi = 0.0, lo = 0.0, op = 0.0, cl = 0.0;
      if(syn)
      {
         if(!HTFSynOHLC(tf, ot, op, hi, lo, cl))
         {
            if(i == 0) return -1;
            continue;
         }
      }
      else
      {
         hi = iHigh(_Symbol, tf, i); lo = iLow(_Symbol, tf, i);
         op = iOpen(_Symbol, tf, i); cl = iClose(_Symbol, tf, i);
         if(hi <= 0 || lo <= 0)
         {
            if(i == 0) return -1;
            continue;
         }
      }

      DrawHTFCandleCore(i, ot, nt, hi, lo, op, cl);
      if(i == 0)
      {
         g_HTFLastFormOpen = ot;
         g_HTFLastFormO = op; g_HTFLastFormH = hi;
         g_HTFLastFormL = lo; g_HTFLastFormC = cl;
      }
   }
   HTFDeleteIndices(count, s_prevCount);
   s_prevCount = count;
   s_HTFSlotDrawn = s_HTFSlot;   // P-HTF-SLOT: the pitch these boxes stand on
   // P-UI-98r: a draw while a card is open births boxes unmasked - cull the
   // fresh set at once (slider drags redraw continuously; the timer net would
   // leave a 250 ms flicker under the hand).
   HTFCardCullRefresh();
   return count;
}

//+------------------------------------------------------------------+
//| Full refresh of HTF candles (returns bars drawn, -1 = not ready) |
//+------------------------------------------------------------------+
int RefreshHTFCandles()
{
   g_HTFLastFormOpen = 0;
   return DrawHTFCandles();
}

//+------------------------------------------------------------------+
//| SELF-HEALING FULL DRAW — HTF boxes must survive timeframe switches|
//| without a manual off/on toggle, even on slow PCs. Why: MT4 fires  |
//| OnDeinit(REASON_CHARTCHANGE) on every TF switch and our OnDeinit  |
//| deletes ALL HTF objects, while OnInit only re-resolves g_HTFPeriod|
//| and draws nothing; the per-tick updater only maintains the forming|
//| candle (index 0), so history boxes 1..N never come back. Worse,   |
//| right after a switch the HTF history often isn't loaded yet       |
//| (iBars==0 — takes seconds longer on weak PCs), so even a one-shot |
//| draw at init would silently draw nothing and never retry.         |
//| Runs from RefreshUIPerTick (every tick + 1s timer, so it retries  |
//| with zero ticks too). Steady-state cost is O(1): int compares per |
//| tick; the existence probe runs at most once/sec, and the full     |
//| draw fires only on TF change / new HTF bar / missing boxes.       |
//+------------------------------------------------------------------+
#define HTF_ENSURE_RETRY_MS 1000
void HTFEnsureDrawn()
{
   if(!g_UI.showHTF || StringLen(g_HTFPrefix) == 0) return;

   int tf = ResolveHTFPeriod();   // auto mode follows the CURRENT chart TF
   static int s_lastDrawnTf = -1; // TF of the boxes on chart (-1=none yet, 0=hidden-by-design)
   static datetime s_drawnBar0 = 0; // forming-bar open time as last fully drawn

   // A rung strictly below the chart TF (a manual D1 on a monthly chart, or tf==0
   // from an empty resolve): make sure no stale boxes linger, once. tf == chart TF
   // is a REAL rung now (P-HTF-TOP) and draws below.
   if(tf < (int)Period())
   {
      if(s_lastDrawnTf != 0)
      {
         DeleteHTFCandles();
         s_lastDrawnTf = 0;
         s_drawnBar0 = 0;
      }
      return;
   }

    // P-PERF-06: while the level pipeline is staging its post-wipe rebuild
    // (attach / TF switch / topology toggle), the forming candle already ticks
    // via UpdateHTFFormingCandle — the HISTORY bulk (up to ~240 bars x 5
    // series reads + creates) waits for stage 0 so the switch stays
    // interactive. The probe clock below keeps running, so the deferred draw
    // lands on the first pass after the rebuild seals.
    if(g_buildStage != 0) return;

    // Keep the engine period in sync (normally already fresh from OnInit).
    g_HTFPeriod = tf;

   // Runs AFTER UpdateHTFFormingCandle in RefreshUIPerTick, so the live-edge
   // cache is fresh: a changed open time means a new HTF bar rolled and the
   // index-based history shifted — full redraw, no extra iTime call.
   uint now = GetTickCount();
   static uint s_lastProbe = 0;
   bool need = false;
   if(tf != s_lastDrawnTf) need = true;
   else if(g_HTFLastFormOpen != s_drawnBar0) need = true;
   else if(now - s_lastProbe >= HTF_ENSURE_RETRY_MS)
   {
      // Steady state: probe existence at most once per second (template
      // change or manual deletion while the toggle is still ON).
      s_lastProbe = now;
      if(!HTFAnyBoxesExist()) need = true;
   }
   // P-PERF-02 viewport cap: the user scrolled/zoomed into a range the drawn
   // set does not cover (or left a whole block of history behind). Own
   // throttle — see HTFRangeStale.
   if(!need && HTFRangeStale()) need = true;
   if(!need) return;
   if(s_lastProbe != 0 && now - s_lastProbe < HTF_ENSURE_RETRY_MS && tf != s_lastDrawnTf)
      return;   // TF just changed: redraw at most once/sec (first run is immediate)

   // Weak-PC guard: HTF history may still be loading after a TF switch.
   // Draw only when data is really ready; otherwise keep the old state so
   // a later tick/timer retries automatically — no toggle needed.
   // P-HTF-SYN aware: a synthetic rung is ready when the MN1 history carries at
   // least one FULL bucket of it — asking the terminal for a 6M/12M series would
   // always answer "not ready" and the overlay would never draw at all.
   int readyBars = HTFTfIsSynthetic(tf) ? HTFSynBarCount(tf) : iBars(_Symbol, tf);
   if(Bars < 2 || readyBars <= 0 ||
      (!HTFTfIsSynthetic(tf) && iTime(_Symbol, tf, 0) <= 0))
   {
      s_lastProbe = now;
      return;
   }

   if(RefreshHTFCandles() < 0) { s_lastProbe = now; return; }
   s_lastDrawnTf = tf;
   s_drawnBar0 = g_HTFLastFormOpen;
   s_lastProbe = now;
   // (P-PERF-02) Range changes are already handled above; nothing else to do.
   // PERF: shared 100 ms throttle (UtilityFunctions.mqh) instead of a raw
   // redraw — a full HTF draw usually lands on the same tick as the level
   // pipeline paint, so they coalesce into one. Same pixels, ≤100 ms later.
   ThrottledChartRedraw();
}

// P-HTF-KEY — the toggle walk: masking, not deleting. OFF hides the family in
// place (guarded flips only); ON unmasks it — instant both ways, no history
// re-read, rapid-press safe. First ON with no family builds once, like before.
void HTFApplyVisibleMasks()
{
   if(StringLen(g_HTFPrefix) == 0) return;
   if(g_UI.showHTF && !HTFAnyBoxesExist()) { RefreshHTFCandles(); return; }
   for(int i = 0; i < g_HTFDrawnCount; i++)
   {
      string id = IntegerToString(i);
      string nm[5];
      nm[0] = g_HTFPrefix + id;
      nm[1] = g_HTFPrefix + id + "_F";
      nm[2] = g_HTFPrefix + id + "_B";
      nm[3] = g_HTFPrefix + "WU" + id;
      nm[4] = g_HTFPrefix + "WL" + id;
      for(int k = 0; k < 5; k++)
      {
         if(ObjectFind(0, nm[k]) < 0) continue;
         long want = HTFBoxMask(HTFCullHas(nm[k]));
         if((long)ObjectGetInteger(0, nm[k], OBJPROP_TIMEFRAMES) != want)
            ObjectSetInteger(0, nm[k], OBJPROP_TIMEFRAMES, want);
      }
   }
}

#endif // HTF_CANDLES_DRAW_MQH
