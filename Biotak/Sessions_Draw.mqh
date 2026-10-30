//+------------------------------------------------------------------+
//|                                              Sessions_Draw.mqh   |
//|                    Copyright 2026, Biotak Project                |
//|                                                                  |
//|  P-SESS — THE SESSION RENDERER (chart objects only; no UI reads,  |
//|  no Pnl*/menu calls — compiles in BOTH entries, P-BUILD-01).      |
//|                                                                  |
//|  WHAT IT PAINTS, per enabled slot:                                |
//|    boxes + tag labels  for the last g_sessHistDays zone days      |
//|    H/L lines + price labels + range caption  on the live window   |
//|      (or the nearest completed one when today has not opened yet) |
//|    prior H/L as dotted levels carried across the live window      |
//|      (g_sessPrior, default off)                                   |
//|    ghost outlines for the next g_sessFutDays upcoming windows     |
//|    overlap rectangles  for today's intersecting windows           |
//|    one countdown text at the next boundary (engine, per instant)  |
//|                                                                  |
//|  CADENCE — the coop pump drives SessionsTick every 250 ms:        |
//|    * idle            : a hash compare, a day compare and one      |
//|                        high/low compare per live slot — no writes |
//|    * new day         : full wipe + repaint                        |
//|    * settings change : full wipe + repaint (hash)                 |
//|    * open/close flip : full wipe + repaint (+ alert, if enabled)  |
//|    * otherwise       : extend the live H/L in place               |
//|  TIME-FRAME-FREE NAMES (date-keyed, no period in the name), so a  |
//|  TF switch keeps every box; REASON_REMOVE sweeps them with the    |
//|  instance (one inpObjectPrefix wipe, EventHandlers_Tail).         |
//|                                                                  |
//|  DEPENDENCIES (all precede this file): Sessions_Model,            |
//|  Runtime_A (g_sess*), GlobalVariables (IsIndicatorHidden),        |
//|  Util_A (ThrottledChartRedraw).                                   |
//+------------------------------------------------------------------+
#ifndef SESSIONS_DRAW_MQH
#define SESSIONS_DRAW_MQH

#include "Sessions_Model.mqh"

#define SESS_TAG         "SESS_"
#define SESS_FONT        "Arial"
#define SESS_PT_LBL      7     // box tags + ghosts
#define SESS_PT_PRICE    7     // H/L + range + countdown
#define SESS_FILL_ALPHA  86    // % of the fill ink given up to the background (P-SESS-14: only the FACTORY value now — the painter reads g_sessFill = 100-this)
#define SESS_PAST_ALPHA  45    // past windows: ink given up — the live box keeps it (P-SESS-06)
#define SESS_GHOST_ALPHA 62
#define SESS_PRIOR_ALPHA 55
#define SESS_MID_ALPHA   45
#define SESS_X_ALPHA     70
#define SESS_TV_ALPHA    35    // P-SESS-18: the TV levels are read, not stared at — dimmer than the box
#define SESS_CD_COLOR    C'205,208,218'

//--- renderer state (this file's own; nothing outside reads it)
static bool     s_sessBuilt = false;
static long     s_sessHash = 0;
static int      s_sessDay = 0;
static bool     s_sessAlertSeeded = false;
static bool     s_sessWasOpen[SESS_SLOTS];

//--- per-slot live-window cache (the tick's extend path)
static bool     s_sessLiveValid[SESS_SLOTS];
static int      s_sessLiveStamp[SESS_SLOTS];
static datetime s_sessLiveS[SESS_SLOTS];
static datetime s_sessLiveE[SESS_SLOTS];
static datetime s_sessLiveBar[SESS_SLOTS];   // P-SESS-11: the bar the cached H/L was last synced on
static double   s_sessLiveHi[SESS_SLOTS];
static double   s_sessLiveLo[SESS_SLOTS];

//--- countdown cache (boundary recomputes at a rebuild; text at ~1 Hz)
static datetime s_sessCdNext = 0;
static int      s_sessCdSlot = -1;
static bool     s_sessCdIsOpen = false;
static string   s_sessCdText = "";
static uint     s_sessCdMs = 0;

//--- P-SESS-19 — THE STRIP (TradingView's "Show Sessions Divider"). The runs are
//--- collected by the paint that already walks every window; the blocks are laid
//--- out in WINDOW pixels by SessStripTick, and only when the view moved.
#define SESS_STRIP_MAX   64     // windows the strip can hold (4 slots x 16)
#define SESS_STRIP_H     4      // px tall
#define SESS_STRIP_Y     8      // px above the pane's bottom edge
#define SESS_STRIP_GAP   2      // px between two runs
static int      s_sessStripN = 0;
static int      s_sessStripSlot[SESS_STRIP_MAX];
static datetime s_sessStripS[SESS_STRIP_MAX];
static datetime s_sessStripE[SESS_STRIP_MAX];
static bool     s_sessStripDirty = true;
static long     s_sessStripSig = 0;

//+------------------------------------------------------------------+
//| Names + primitives                                                |
//+------------------------------------------------------------------+
string SessWindowName(const int slot, const int stamp, const string tail)
{
   return inpObjectPrefix + SESS_TAG + IntegerToString(slot) + "_" + IntegerToString(stamp) + "_" + tail;
}

color SessBlend(const color base, const int alphaPct)
{
   int a = (int)MathMax(0, MathMin(100, alphaPct));
   if(a <= 0) return base;
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int fr = ((int)base) & 0xFF, fg = (((int)base) >> 8) & 0xFF, fb = (((int)base) >> 16) & 0xFF;
   int br = ((int)bg) & 0xFF, bgg = (((int)bg) >> 8) & 0xFF, bb = (((int)bg) >> 16) & 0xFF;
   int r = (fr * (100 - a) + br * a) / 100;
   int g = (fg * (100 - a) + bgg * a) / 100;
   int b = (fb * (100 - a) + bb * a) / 100;
   return (color)(r | (g << 8) | (b << 16));
}

//+------------------------------------------------------------------+
//| ONE box door, TWO build-proof bodies (P-SESS-05).                 |
//|                                                                  |
//| A rectangle cannot be trusted to stay hollow: some MT4 builds     |
//| paint it filled whatever FILL says — ZoneFactory.mqh:143 already  |
//| pays this exact law (EMPTY boxes there are four border segments), |
//| and MEASURED on the reporting chart every session box shipped as  |
//| a solid saturated slab for it. So HOLLOW here is four border      |
//| SEGMENTS — guaranteed hollow on every build — and only the        |
//| FILLED style is a real rectangle, with its fill CLAIMED (FILL     |
//| written true, an explicit BGCOLOR), never assumed.                |
//+------------------------------------------------------------------+
void SessEdge(const string nm, const datetime t1, const double p1, const datetime t2, const double p2,
              const color clr, const int width, const ENUM_LINE_STYLE style, const string tip)
{
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_RAY, false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);   // the body sits behind the candles
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
   ObjectMove(0, nm, 0, t1, p1);
   ObjectMove(0, nm, 1, t2, p2);
}

void SessRect(const string nm, const datetime t1, const double p1, const datetime t2, const double p2,
              const color borderC, const color fillC, const int width, const ENUM_LINE_STYLE style,
              const string tip)
{
   if(fillC == clrNONE)
   {
      SessEdge(nm + "ET", t1, p1, t2, p1, borderC, width, style, tip);
      SessEdge(nm + "EB", t1, p2, t2, p2, borderC, width, style, tip);
      SessEdge(nm + "EL", t1, p1, t1, p2, borderC, width, style, tip);
      SessEdge(nm + "ER", t2, p1, t2, p2, borderC, width, style, tip);
      return;
   }
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, borderC);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, fillC);
   ObjectSetInteger(0, nm, OBJPROP_FILL, true);   // a fill is written, never assumed
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
   ObjectMove(0, nm, 0, t1, p1);
   ObjectMove(0, nm, 1, t2, p2);
}

void SessLine(const string nm, const datetime t1, const double p1, const datetime t2, const double p2,
              const color clr, const int width, const ENUM_LINE_STYLE style, const string tip)
{
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_RAY, false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, style);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
   ObjectMove(0, nm, 0, t1, p1);
   ObjectMove(0, nm, 1, t2, p2);
}

void SessText(const string nm, const datetime t, const double p, const string txt,
              const color clr, const int pt, const ENUM_ANCHOR_POINT anchor, const string tip)
{
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, nm, OBJPROP_TEXT, txt);
   ObjectSetString(0, nm, OBJPROP_FONT, SESS_FONT);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, pt);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, tip);
   ObjectMove(0, nm, 0, t, p);
}

//+------------------------------------------------------------------+
//| Bar-scan high/low of one UTC span (skips windows with no bars —   |
//| a holiday or beyond-history window degrades to NO object, never   |
//| to a fake one).                                                   |
//+------------------------------------------------------------------+
bool SessHiLoFor(datetime t1, const datetime t2, double &hi, double &lo)
{
   hi = 0.0; lo = 0.0;
   if(t2 <= t1) return false;
   int bars = iBars(NULL, 0);
   if(bars <= 0) return false;
   //--- P-SESS-09: iBarShift(clamp) answers the OLDEST bar for a time before the
   //--- loaded history, so a window older than the series painted the oldest
   //--- bar's high/low as its own. Wholly-before-history = NO object (this file's
   //--- promise); partially-before = scan the part the chart really carries.
   datetime oldestT = iTime(NULL, 0, bars - 1);
   if(oldestT <= 0) return false;
   if(t2 <= oldestT) return false;
   datetime from = (t1 < oldestT) ? oldestT : t1;   // partial coverage: scan what the chart carries
   int i1 = iBarShift(NULL, 0, from, false);
   //--- P-SESS-10: the window's END is exclusive — the bar that OPENS at t2 is the
   //--- next window's first bar, and counting it inflated every past H/L by one bar.
   int i2 = iBarShift(NULL, 0, t2 - 1, false);
   if(i1 < 0 || i2 < 0) return false;
   if(i1 > bars - 1) i1 = bars - 1;
   if(i2 > i1) i2 = i1;
   int count = i1 - i2 + 1;
   if(count < 1) return false;
   int iH = iHighest(NULL, 0, MODE_HIGH, count, i2);
   int iL = iLowest(NULL, 0, MODE_LOW, count, i2);
   if(iH < 0 || iL < 0) return false;
   hi = iHigh(NULL, 0, iH);
   lo = iLow(NULL, 0, iL);
   return (hi > 0.0 && lo > 0.0);
}

//+------------------------------------------------------------------+
//| P-SESS-18 — THE TRADINGVIEW LEVELS, in ONE pass.                  |
//|                                                                   |
//| TradingView's Sessions draws four price lines beside the box: the |
//| MIDPOINT (50 % of the window's range), the MEAN (its average       |
//| price), the VWAP (volume weighted) and the TRENDLINE (the least    |
//| squares line through its closes). MT4 has no per-bar plot, so the  |
//| same four numbers become four objects, and every one of them is    |
//| answered by a SINGLE walk of the window's bars — the walk the H/L  |
//| scan already owns. A rebuild therefore costs one loop, not four,   |
//| and a still frame costs nothing at all (nothing is written until   |
//| the numbers change).                                              |
//+------------------------------------------------------------------+
struct SessTvStat
{
   bool     ok;
   double   mid;      // (hi + lo) / 2
   double   mean;     // average typical price
   double   vwap;     // sum(tp*v) / sum(v)
   datetime t0, t1;   // the trendline's two bar times (oldest .. newest)
   double   y0, y1;   // its two prices
};

void SessTvFor(const datetime t1, const datetime t2, SessTvStat &o)
{
   o.ok = false; o.mid = 0.0; o.mean = 0.0; o.vwap = 0.0;
   o.t0 = 0; o.t1 = 0; o.y0 = 0.0; o.y1 = 0.0;
   if(t2 <= t1) return;
   int bars = iBars(NULL, 0);
   if(bars <= 0) return;
   datetime oldestT = iTime(NULL, 0, bars - 1);
   if(oldestT <= 0 || t2 <= oldestT) return;      // P-SESS-09: wholly before history = no object
   datetime from = (t1 < oldestT) ? oldestT : t1;
   int i1 = iBarShift(NULL, 0, from, false);      // the window's OLDEST bar (largest index)
   int i2 = iBarShift(NULL, 0, t2 - 1, false);    // its NEWEST bar (P-SESS-10: the end is exclusive)
   if(i1 < 0 || i2 < 0) return;
   if(i1 > bars - 1) i1 = bars - 1;
   if(i2 > i1) i2 = i1;
   if(i1 < 0 || i2 < 0 || i2 > i1) return;
   double hi = 0.0, lo = 0.0, sum = 0.0, pv = 0.0, vv = 0.0;
   double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
   int n = 0;
   for(int i = i2; i <= i1; i++)
   {
      double h = iHigh(NULL, 0, i);
      double l = iLow(NULL, 0, i);
      double c = iClose(NULL, 0, i);
      if(h <= 0.0 || l <= 0.0 || c <= 0.0) continue;
      double tp = (h + l + c) / 3.0;
      double v  = (double)iVolume(NULL, 0, i);
      if(v < 0.0) v = 0.0;
      if(n == 0 || h > hi) hi = h;
      if(n == 0 || l < lo) lo = l;
      double x = (double)(i1 - i);                // 0 at the window's own first bar
      sum += tp;  pv += tp * v;  vv += v;
      sx += x; sy += c; sxx += x * x; sxy += x * c;
      n++;
   }
   if(n < 1 || hi <= 0.0 || lo <= 0.0) return;
   o.mid  = (hi + lo) / 2.0;
   o.mean = sum / (double)n;
   o.vwap = (vv > 0.0) ? (pv / vv) : o.mean;      // no volume on that feed: the mean IS the honest stand-in
   double den = (double)n * sxx - sx * sx;
   double b = (den != 0.0) ? (((double)n * sxy - sx * sy) / den) : 0.0;
   double a = (sy - b * sx) / (double)n;
   o.t0 = iTime(NULL, 0, i1);
   o.t1 = iTime(NULL, 0, i2);
   o.y0 = a;
   o.y1 = a + b * (double)(i1 - i2);
   o.ok = (o.t0 > 0 && o.t1 > 0);
}

//--- which of the four the dropdown asks for (0 = off, 5 = all)
int SessTvMask()
{
   if(g_sessTv <= 0) return 0;
   if(g_sessTv >= 5) return 1 | 2 | 4 | 8;
   if(g_sessTv == 1) return 1;   // midpoint
   if(g_sessTv == 2) return 2;   // mean
   if(g_sessTv == 3) return 4;   // vwap
   return 8;                     // trendline
}

//--- the four objects of ONE window. `paint` false = move only (the live path).
void SessTvPaint(const int sl, const int stamp, const datetime sU, const datetime eU,
                 const datetime rEnd, const color base, const string tip)
{
   int mask = SessTvMask();
   if(mask == 0) return;
   SessTvStat st;
   SessTvFor(sU, rEnd, st);
   if(!st.ok) return;
   color ink = SessBlend(base, SESS_TV_ALPHA);
   if((mask & 1) != 0)
      SessLine(SessWindowName(sl, stamp, "TVM"), sU, st.mid, eU, st.mid, ink, 1, STYLE_DOT, tip + " · midpoint");
   if((mask & 2) != 0)
      SessLine(SessWindowName(sl, stamp, "TVE"), sU, st.mean, eU, st.mean, ink, 1, STYLE_DASH, tip + " · mean");
   if((mask & 4) != 0)
      SessLine(SessWindowName(sl, stamp, "TVW"), sU, st.vwap, eU, st.vwap, ink, 1, STYLE_SOLID, tip + " · vwap");
   if((mask & 8) != 0)
      SessEdge(SessWindowName(sl, stamp, "TVT"), st.t0, st.y0, st.t1, st.y1, ink, 1, STYLE_SOLID, tip + " · trendline");
}


//+------------------------------------------------------------------+
//| The one purge: every SESS_ object of this instance. Called at the |
//| top of every repaint (stale objects cannot survive a settings or  |
//| day change) and when master/hide turns it off.                    |
//+------------------------------------------------------------------+
void SessWipe()
{
   if(StringLen(inpObjectPrefix) == 0) return;
   ObjectsDeleteAll(0, inpObjectPrefix + SESS_TAG, -1, -1);
}

//--- rebuild trigger: settings, slots, master, hide, and the CHART'S OWN
//--- TIMEFRAME. P-UI-173 (2026-10-20): the session high/low is SCANNED from
//--- the chart's bars (SessHiLoFor), so the family's numbers ARE timeframe
//--- derived: a switch left the PAST windows' labels on the old timeframe's
//--- bars and the live window's number on the old scan plus the new bar. The
//--- switch is a handoff for this family too - the rebuild below IS its handoff
//--- (its own wipe-and-repaint, not the level family's staged one).
long SessViewHash()
{
   long h = 1181783497276652981;
   h = h * 31 + (long)Period();
   h = h * 31 + (g_sessMaster ? 1 : 0);
   h = h * 31 + (IsIndicatorHidden() ? 1 : 0);
   h = h * 31 + (long)g_sessHistDays;
   h = h * 31 + (long)g_sessFutDays;
   h = h * 31 + (g_sessHlLines ? 1 : 0);
   h = h * 31 + (g_sessHlLabels ? 1 : 0);
   h = h * 31 + (g_sessRangeText ? 1 : 0);
   h = h * 31 + (g_sessPrior ? 1 : 0);
   h = h * 31 + (g_sessOverlap ? 1 : 0);
   h = h * 31 + (g_sessCountdown ? 1 : 0);
   h = h * 31 + (g_sessAlerts ? 1 : 0);
   h = h * 31 + (long)g_sessFill;    // P-SESS-14: the fill knob rebuilds like every other setting
   h = h * 31 + (long)g_sessTv;      // P-SESS-18: the four TV levels
   h = h * 31 + (g_sessStrip ? 1 : 0);   // P-SESS-19: the bottom strip
   for(int i = 0; i < SESS_SLOTS; i++)
      h = h * 31 + (long)g_sessSlot[i];
   return h;
}

//+------------------------------------------------------------------+
//| THE FULL PAINT — wipe, then declare every window the settings     |
//| admit. Windows are ordered by kk (oldest .. newest), so the       |
//| started block is a prefix and the ghosts are its tail.            |
//+------------------------------------------------------------------+
void SessPaintAll(const datetime now, const int bkr)
{
   SessWipe();
   SessStripWipe();          // P-SESS-19: the strip is part of the same family sweep
   s_sessStripN = 0;
   s_sessStripDirty = true;  // the tick below re-lays it against the current view
   s_sessCdNext = 0;
   s_sessCdSlot = -1;
   s_sessCdIsOpen = false;
   s_sessCdText = "";
   s_sessCdMs = 0;
   for(int z = 0; z < SESS_SLOTS; z++)
   {
      s_sessLiveValid[z] = false;
      s_sessLiveBar[z] = 0;
   }

   datetime noon = SessServerNoon();
   //--- P-SESS-15 WITNESS (the flushed channel, never `Print` — P-DRAW-126):
   //--- one header per paint names the frame the boxes are measured in. Every
   //--- edge below is a SERVER instant (P-SESS-13), so these numbers compare
   //--- straight against the chart's own axis, and the zone law that built them
   //--- is on the same line.
#ifndef BUILD_LITE
   //--- P-SESS-13/15 WITNESS (the flushed channel, never `Print` — P-DRAW-126).
   //--- MEASURED 2026-10-30 15:43 on the live chart: bkr=55 minutes while the
   //--- broker is GMT+2, so every edge landed at :54 instead of on the hour.
   //--- The delta is `TimeCurrent() - TimeGMT()` — TimeGMT() is the PC's own
   //--- UTC, so a skewed PC clock poisons the whole frame. The line now carries
   //--- both clocks and the raw seconds, which is the only way to tell a wrong
   //--- clock from a wrong conversion: raw==3300 && (srv-gmt)==3300 means the
   //--- machine, raw!=… means the code.
   DrawStripDiagEmit(StringFormat("[P-SESS] paint bkr=%d dst=%d noon=%s srv=%s gmt=%s raw=%d held=%d tv=%d strip=%d",
                                  bkr, g_sessDst ? 1 : 0, TimeToString(noon, TIME_DATE|TIME_MINUTES),
                                  TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  TimeToString(TimeGMT(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  (int)(TimeCurrent() - TimeGMT()), SessModelDeltaHeldCount(),
                                  g_sessTv, g_sessStrip ? 1 : 0));
#endif
   SessWindow wins[];
   ArrayResize(wins, 96);
   int n = 0;

   //--- today's windows across slots (for the overlap pass); static = the
   //--- compiler's own zero-init, and the loop below re-arms every entry each
   //--- paint (locals here would draw warning 60 on every guarded read)
   static bool     ovOk[SESS_SLOTS];
   static datetime ovS0[SESS_SLOTS], ovE0[SESS_SLOTS];
   static double   ovHi[SESS_SLOTS], ovLo[SESS_SLOTS];
   static color    ovColor[SESS_SLOTS];
   static bool     bandSet[SESS_SLOTS];
   static double   bandHi[SESS_SLOTS], bandLo[SESS_SLOTS];
   for(int z0 = 0; z0 < SESS_SLOTS; z0++)
   { ovOk[z0] = false; bandSet[z0] = false; bandHi[z0] = 0; bandLo[z0] = 0; ovColor[z0] = clrNONE; }

   for(int sl = 0; sl < SESS_SLOTS; sl++)
   {
      SessSlot s;
      SessSlotGet(sl, s);
      if(!s.enabled) continue;
      color base = SessColorOf(s.col);
      int n0 = n;
      SessCollectSlot(sl, s, -g_sessHistDays, g_sessFutDays, noon, bkr, wins, n);

      //--- price scan (past: full window · live: up to now)
      for(int w = n0; w < n; w++)
      {
         datetime rEnd = (wins[w].eU <= now) ? wins[w].eU : now;
         if(rEnd <= wins[w].sU) continue;
         wins[w].hasPrice = SessHiLoFor(wins[w].sU, rEnd, wins[w].hi, wins[w].lo);
      }
      //--- a just-opened window on a bar-less stretch degrades to bar 0
      for(int w = n0; w < n; w++)
      {
         if(wins[w].hasPrice) continue;                                  // P-SESS-07
         if(SessWindowState(wins[w], now) != SESS_WS_LIVE) continue;     // P-SESS-07: the STATE names the live window
         double h0 = iHigh(NULL, 0, 0), l0 = iLow(NULL, 0, 0);
         if(h0 > 0.0 && l0 > 0.0)
         {
            wins[w].hi = h0; wins[w].lo = l0; wins[w].hasPrice = true;
         }
      }

      int sCnt = 0;   // started prefix
      while(n0 + sCnt < n && wins[n0 + sCnt].sU <= now) sCnt++;

      //--- boxes + tags (started windows), recording the nearest band
      for(int w = n0; w < n0 + sCnt; w++)
      {
         if(!wins[w].hasPrice) continue;
         bandSet[sl] = true; bandHi[sl] = wins[w].hi; bandLo[sl] = wins[w].lo;
         string tip = SessWindowTip(s, wins[w].sU, wins[w].hi, wins[w].lo, true);
         string nmB = SessWindowName(sl, wins[w].stamp, "B");
         bool wLive = (SessWindowState(wins[w], now) == SESS_WS_LIVE);   // P-SESS-06
         color ink = wLive ? base : SessBlend(base, SESS_PAST_ALPHA);    // live keeps the ink, past fades
         int bW = wLive ? 2 : 1;                                         // the live box is bold
         color fillC = (s.style == SESS_STYLE_FILLED) ? SessBlend(base, 100 - g_sessFill) : clrNONE;   // P-SESS-14: the fill the user asked for (14 == the shipped tint)
#ifndef BUILD_LITE
         //--- P-SESS-15: the box's own edges, read back from what was PAINTED.
         DrawStripDiagEmit(StringFormat("[P-SESS] win slot=%d stamp=%d sU=%s eU=%s hi=%.3f lo=%.3f live=%d",
                                        sl, wins[w].stamp, TimeToString(wins[w].sU, TIME_DATE|TIME_MINUTES),
                                        TimeToString(wins[w].eU, TIME_DATE|TIME_MINUTES),
                                        wins[w].hi, wins[w].lo, wLive ? 1 : 0));
#endif
         SessRect(nmB, wins[w].sU, wins[w].hi, wins[w].eU, wins[w].lo, ink, fillC, bW, STYLE_SOLID, tip);
         SessText(nmB + "L", wins[w].sU, wins[w].hi, SessZoneTag(s.zone), ink, SESS_PT_LBL,
                  ANCHOR_LEFT_LOWER, tip);   // P-SESS-22: the name sits ABOVE the box (TradingView's range label), never on the candles
         //--- P-SESS-18: the four TradingView levels for THIS window — midpoint,
         //--- mean, vwap and the regression trendline — one bar walk for all four.
         {
            datetime tvEnd = (wins[w].eU <= now) ? wins[w].eU : now;
            SessTvPaint(sl, wins[w].stamp, wins[w].sU, wins[w].eU, tvEnd, base, tip);
         }
         //--- P-SESS-19: the strip's own run list (one block per window, laid out
         //--- in PIXELS by the tick against whatever view the chart carries now)
         if(g_sessStrip && s_sessStripN < SESS_STRIP_MAX)
         {
            s_sessStripSlot[s_sessStripN] = sl;
            s_sessStripS[s_sessStripN] = wins[w].sU;
            s_sessStripE[s_sessStripN] = wins[w].eU;
            s_sessStripN++;
         }
         if(s.style == SESS_STYLE_MID && SessWindowState(wins[w], now) == SESS_WS_LIVE)   // P-SESS-07
         {
            double mid = (wins[w].hi + wins[w].lo) / 2.0;
            SessLine(nmB + "M", wins[w].sU, mid, wins[w].eU, mid, SessBlend(base, SESS_MID_ALPHA),
                     1, STYLE_DOT, tip + " · mid");
         }
         if(SessWindowState(wins[w], now) == SESS_WS_LIVE)   // P-SESS-07: no day-index gate on a live window
         {
            ovOk[sl] = true;
            ovS0[sl] = wins[w].sU; ovE0[sl] = wins[w].eU;
            ovHi[sl] = wins[w].hi; ovLo[sl] = wins[w].lo;
            ovColor[sl] = base;
         }
      }

      //--- the live (or nearest completed) window owns lines/labels/range
      int wLin = -1;
      for(int w = n0 + sCnt - 1; w >= n0; w--)
      {
         if(wins[w].hasPrice) { wLin = w; break; }
      }
      if(wLin >= 0)
      {
         bool wLinLive = (SessWindowState(wins[wLin], now) == SESS_WS_LIVE);   // P-SESS-06/07
         //--- the live cache belongs to the WINDOW, not to the H/L lines:
         //--- the box extends per tick even when the lines are off
         if(wLinLive)
         {
            s_sessLiveValid[sl] = true;
            s_sessLiveStamp[sl] = wins[wLin].stamp;
            s_sessLiveS[sl] = wins[wLin].sU;
            s_sessLiveE[sl] = wins[wLin].eU;
            s_sessLiveHi[sl] = wins[wLin].hi;
            s_sessLiveLo[sl] = wins[wLin].lo;
            s_sessLiveBar[sl] = iTime(NULL, 0, 0);   // P-SESS-11
         }
         string tipL = SessWindowTip(s, wins[wLin].sU, wins[wLin].hi, wins[wLin].lo, true);
         if(g_sessHlLines)
         {
            int lw = wLinLive ? 2 : 1;   // P-SESS-06: the live window's H/L is bold with its box
            string nmHI = SessWindowName(sl, wins[wLin].stamp, "HI");
            SessLine(nmHI,      wins[wLin].sU, wins[wLin].hi, wins[wLin].eU, wins[wLin].hi, base, lw, STYLE_SOLID, tipL);
            SessLine(SessWindowName(sl, wins[wLin].stamp, "LO"),
                     wins[wLin].sU, wins[wLin].lo, wins[wLin].eU, wins[wLin].lo, base, lw, STYLE_SOLID, tipL);
         }
         if(g_sessHlLabels)
         {
            SessText(SessWindowName(sl, wins[wLin].stamp, "HIL"), SessLabelAnchor(wins[wLin].eU, now), wins[wLin].hi,
                     DoubleToString(wins[wLin].hi, _Digits), base, SESS_PT_PRICE, ANCHOR_RIGHT_LOWER, tipL);
            SessText(SessWindowName(sl, wins[wLin].stamp, "LOL"), SessLabelAnchor(wins[wLin].eU, now), wins[wLin].lo,
                     DoubleToString(wins[wLin].lo, _Digits), base, SESS_PT_PRICE, ANCHOR_RIGHT_UPPER, tipL);
         }
         if(g_sessRangeText)
            SessText(SessWindowName(sl, wins[wLin].stamp, "R"), SessLabelAnchor(wins[wLin].eU, now), wins[wLin].lo,
                     IntegerToString(SessPipsIn(wins[wLin].hi, wins[wLin].lo)) + "p",
                     SessBlend(base, SESS_MID_ALPHA), SESS_PT_PRICE, ANCHOR_RIGHT_LOWER,
                     "range of the session · pips");
         //--- prior H/L carried across this window (g_sessPrior)
         if(g_sessPrior && wLin > n0)
         {
            for(int w = wLin - 1; w >= n0; w--)
            {
               if(!wins[w].hasPrice) continue;
               string nmP = SessWindowName(sl, wins[wLin].stamp, "PHI");
               SessLine(nmP, wins[wLin].sU, wins[w].hi, wins[wLin].eU, wins[w].hi,
                        SessBlend(base, SESS_PRIOR_ALPHA), 1, STYLE_DOT, tipL + " · prior high");
               SessLine(SessWindowName(sl, wins[wLin].stamp, "PLO"),
                        wins[wLin].sU, wins[w].lo, wins[wLin].eU, wins[w].lo,
                        SessBlend(base, SESS_PRIOR_ALPHA), 1, STYLE_DOT, tipL + " · prior low");
               break;
            }
         }
      }

      //--- ghosts: the next unstarted windows (nearest first), wearing
      //--- the nearest known band — the honest answer to "where will it sit"
      int gN = (int)MathMin(n - (n0 + sCnt), g_sessFutDays);
      for(int gi = 0; gi < gN; gi++)
      {
         int w = n0 + sCnt + gi;
         if(!bandSet[sl]) break;
         string nmF = SessWindowName(sl, wins[w].stamp, "F");
         string tipF = SessZoneLabel(s.zone) + " " + SessHhMmFromMin(s.startMin) + "-"
                     + SessHhMmFromMin(s.endMin) + " · upcoming";
         SessRect(nmF, wins[w].sU, bandHi[sl], wins[w].eU, bandLo[sl],
                  SessBlend(base, SESS_GHOST_ALPHA), clrNONE, 1, STYLE_DOT, tipF);
         //--- P-SESS-08: the tag tail must NOT be "L" here — `_F` + `L` spells `_FL`,
         //--- the fill-child suffix (FILLCHILD_SUFFIX, Toolbar_A), so the strip's
         //--- orphan sweep deleted every ghost tag 2 s after it was painted (log
         //--- witness: ORPHAN drop="THLevelsSESS_2_20261021_FL"). "T" is the tag.
         SessText(nmF + "T", wins[w].sU, bandHi[sl],
                  SessZoneTag(s.zone) + " " + SessHhMmFromMin(s.startMin),
                  SessBlend(base, SESS_GHOST_ALPHA), SESS_PT_LBL, ANCHOR_LEFT_UPPER, tipF);
      }

      //--- countdown candidate: the nearest boundary of this slot
      if(g_sessCountdown)
      {
         bool isOpen = false;
         datetime b = SessSlotNextBoundary(s, now, bkr, isOpen);
         if(b > 0 && (s_sessCdNext == 0 || b < s_sessCdNext))
         {
            s_sessCdNext = b;
            s_sessCdSlot = sl;
            s_sessCdIsOpen = isOpen;
         }
      }
   }

   //--- overlaps of today's live windows (pairwise)
   if(g_sessOverlap)
   {
      for(int a = 0; a < SESS_SLOTS; a++)
      {
         if(!ovOk[a]) continue;
         for(int b = a + 1; b < SESS_SLOTS; b++)
         {
            if(!ovOk[b]) continue;
            datetime t1 = (ovS0[a] > ovS0[b]) ? ovS0[a] : ovS0[b];
            datetime t2 = (ovE0[a] < ovE0[b]) ? ovE0[a] : ovE0[b];
            if(t2 <= t1) continue;
            double hi = MathMin(ovHi[a], ovHi[b]);
            double lo = MathMax(ovLo[a], ovLo[b]);
            if(hi <= lo) continue;
            string nmX = inpObjectPrefix + SESS_TAG + "X_" + IntegerToString(a) + "_" + IntegerToString(b);
            SessRect(nmX, t1, hi, t2, lo, SessBlend(ovColor[a], SESS_X_ALPHA), clrNONE,
                     1, STYLE_DOT, "overlap");
         }
      }
   }

   //--- the countdown object
   if(g_sessCountdown && s_sessCdNext > 0 && s_sessCdSlot >= 0)
   {
      SessSlot cs;
      SessSlotGet(s_sessCdSlot, cs);
      double cdP = 0.0;
      if(bandSet[s_sessCdSlot]) cdP = (bandHi[s_sessCdSlot] + bandLo[s_sessCdSlot]) / 2.0;
      else
      {
         double fh = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, (int)MathMin(120, iBars(NULL, 0)), 0));
         if(fh > 0.0) cdP = fh * 0.995;
      }
      string nmC = inpObjectPrefix + SESS_TAG + "CDN";
      string nmU = SessZoneLabel(cs.zone);
      StringToUpper(nmU);
      s_sessCdText = nmU + (s_sessCdIsOpen ? " close " : " open ") + SessFmtDur((int)(s_sessCdNext - now));
      if(cdP > 0.0)
         SessText(nmC, SessLabelAnchor(s_sessCdNext, now), cdP, s_sessCdText, SESS_CD_COLOR, SESS_PT_PRICE,
                  ANCHOR_LEFT_LOWER, "next session boundary");
   }
}

//+------------------------------------------------------------------+
//| The live extend: one compare per live slot; writes only when the  |
//| session really printed a new extreme.                             |
//+------------------------------------------------------------------+
void SessLiveRepaint(const int sl)
{
   SessSlot s;
   SessSlotGet(sl, s);
   string nmB = SessWindowName(sl, s_sessLiveStamp[sl], "B");
   //--- the body follows its OWN kind (P-SESS-05): 2 moves for the filled
   //--- rectangle, 8 for the hollow four-edge frame — and only when the
   //--- session really printed a new extreme (the caller's compare)
   if(s.style == SESS_STYLE_FILLED)
   {
      ObjectMove(0, nmB, 0, s_sessLiveS[sl], s_sessLiveHi[sl]);
      ObjectMove(0, nmB, 1, s_sessLiveE[sl], s_sessLiveLo[sl]);
   }
   else
   {
      ObjectMove(0, nmB + "ET", 0, s_sessLiveS[sl], s_sessLiveHi[sl]);
      ObjectMove(0, nmB + "ET", 1, s_sessLiveE[sl], s_sessLiveHi[sl]);
      ObjectMove(0, nmB + "EB", 0, s_sessLiveS[sl], s_sessLiveLo[sl]);
      ObjectMove(0, nmB + "EB", 1, s_sessLiveE[sl], s_sessLiveLo[sl]);
      ObjectMove(0, nmB + "EL", 0, s_sessLiveS[sl], s_sessLiveHi[sl]);
      ObjectMove(0, nmB + "EL", 1, s_sessLiveS[sl], s_sessLiveLo[sl]);
      ObjectMove(0, nmB + "ER", 0, s_sessLiveE[sl], s_sessLiveHi[sl]);
      ObjectMove(0, nmB + "ER", 1, s_sessLiveE[sl], s_sessLiveLo[sl]);
   }
   if(g_sessHlLines)
   {
      string nmHI = SessWindowName(sl, s_sessLiveStamp[sl], "HI");
      ObjectMove(0, nmHI, 0, s_sessLiveS[sl], s_sessLiveHi[sl]);
      ObjectMove(0, nmHI, 1, s_sessLiveE[sl], s_sessLiveHi[sl]);
      string nmLO = SessWindowName(sl, s_sessLiveStamp[sl], "LO");
      ObjectMove(0, nmLO, 0, s_sessLiveS[sl], s_sessLiveLo[sl]);
      ObjectMove(0, nmLO, 1, s_sessLiveE[sl], s_sessLiveLo[sl]);
   }
   if(g_sessHlLabels)
   {
      ObjectSetString(0, SessWindowName(sl, s_sessLiveStamp[sl], "HIL"), OBJPROP_TEXT,
                      DoubleToString(s_sessLiveHi[sl], _Digits));
      ObjectMove(0, SessWindowName(sl, s_sessLiveStamp[sl], "HIL"), 0, SessLabelAnchor(s_sessLiveE[sl], TimeCurrent()), s_sessLiveHi[sl]);
      ObjectSetString(0, SessWindowName(sl, s_sessLiveStamp[sl], "LOL"), OBJPROP_TEXT,
                      DoubleToString(s_sessLiveLo[sl], _Digits));
      ObjectMove(0, SessWindowName(sl, s_sessLiveStamp[sl], "LOL"), 0, SessLabelAnchor(s_sessLiveE[sl], TimeCurrent()), s_sessLiveLo[sl]);
   }
   if(g_sessRangeText)
   {
      ObjectSetString(0, SessWindowName(sl, s_sessLiveStamp[sl], "R"), OBJPROP_TEXT,
                      IntegerToString(SessPipsIn(s_sessLiveHi[sl], s_sessLiveLo[sl])) + "p");
      ObjectMove(0, SessWindowName(sl, s_sessLiveStamp[sl], "R"), 0, SessLabelAnchor(s_sessLiveE[sl], TimeCurrent()), s_sessLiveLo[sl]);
   }
   ThrottledChartRedraw();
}

void SessLiveUpdate(const datetime now)
{
   datetime bt = iTime(NULL, 0, 0);
   for(int sl = 0; sl < SESS_SLOTS; sl++)
   {
      if(!s_sessLiveValid[sl]) continue;
      if(now < s_sessLiveS[sl] || now >= s_sessLiveE[sl]) continue;
      //--- P-SESS-11: a bar that CLOSED unobserved (a slow tick, a sleep, a
      //--- reconnect) was never compared — its printed extreme is inside the
      //--- window but outside the cache. One scan of the window on the first
      //--- tick of a new bar answers every bar that passed; the bar-0 compare
      //--- below still carries the forming bar.
      bool newBar = (bt > 0 && s_sessLiveBar[sl] > 0 && bt != s_sessLiveBar[sl]);
      bool grew = false;
      if(newBar)
      {
         double hW = 0.0, lW = 0.0;
         datetime rEnd = (s_sessLiveE[sl] <= now) ? s_sessLiveE[sl] : now;
         if(SessHiLoFor(s_sessLiveS[sl], rEnd, hW, lW))
         {
            if(hW > s_sessLiveHi[sl]) { s_sessLiveHi[sl] = hW; grew = true; }
            if(lW < s_sessLiveLo[sl]) { s_sessLiveLo[sl] = lW; grew = true; }
         }
      }
      if(bt > 0) s_sessLiveBar[sl] = bt;
      //--- P-SESS-18: the live window's four TV levels move with it. One extra bar
      //--- walk per NEW BAR (never per tick) — the same cadence as the H/L rescan
      //--- above, which is the only reason a still frame stays free of writes.
      if(newBar)
      {
         SessSlot ts;
         SessSlotGet(sl, ts);
         SessTvPaint(sl, s_sessLiveStamp[sl], s_sessLiveS[sl], s_sessLiveE[sl], now,
                     SessColorOf(ts.col), "live");
      }
      double h0 = iHigh(NULL, 0, 0);      double l0 = iLow(NULL, 0, 0);
      if(h0 <= 0.0 || l0 <= 0.0) continue;
      if(h0 > s_sessLiveHi[sl]) { s_sessLiveHi[sl] = h0; grew = true; }
      if(l0 < s_sessLiveLo[sl]) { s_sessLiveLo[sl] = l0; grew = true; }
      if(grew) SessLiveRepaint(sl);   // a still frame still costs zero writes
   }
}

//+------------------------------------------------------------------+
//| P-SESS-19 — THE STRIP: TradingView's "Show Sessions Divider".     |
//|                                                                   |
//| TV marks the ACTIVE session along the BOTTOM of the chart and     |
//| marks where it begins. In Pine that is one `plotshape` per bar;   |
//| here it is ONE pixel block per contiguous run, pinned to the      |
//| chart window's bottom-left corner (CORNER_LEFT_LOWER) so it is    |
//| drawn in WINDOW pixels and can never cover a session box — the    |
//| box lives in price coordinates, the strip lives in the bottom     |
//| margin, so it never lands on a box (P-SESS-19).                   |
//|                                                                   |
//| COST: the runs are collected by the paint that already walks       |
//| every window; a block is written only when the VIEW changed       |
//| (scroll, zoom, resize), so a still frame costs zero writes.        |
//+------------------------------------------------------------------+

//--- ONE block of the strip, in window pixels (never in price)
void SessStripBlock(const string nm, const int x, const int w, const color c)
{
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, SESS_STRIP_Y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, (w < 2) ? 2 : w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, SESS_STRIP_H);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, "session strip");
}

void SessStripWipe()
{
   ObjectsDeleteAll(0, inpObjectPrefix + SESS_TAG + "ST", -1, -1);
}

//--- the visible window's own signature: scroll, zoom and resize all move it
long SessViewSig()
{
   long first = ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0);
   long vis   = ChartGetInteger(0, CHART_VISIBLE_BARS, 0);
   long wpx   = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   return (first * 131 + vis) * 131 + wpx;
}

//--- the strip's tick: zero writes while the view stands still
void SessStripTick()
{
   if(StringLen(inpObjectPrefix) == 0) return;
   if(!g_sessStrip || !g_sessMaster || IsIndicatorHidden())
   {
      if(s_sessStripN > 0 || s_sessStripDirty) { SessStripWipe(); s_sessStripN = 0; }
      s_sessStripDirty = false;
      return;
   }
   long sig = SessViewSig();
   if(!s_sessStripDirty && sig == s_sessStripSig) return;   // still frame: nothing to do
   s_sessStripSig = sig;
   s_sessStripDirty = false;
   SessStripWipe();
   if(s_sessStripN <= 0) return;

   //--- the chart's own left/right edges, in time
   int firstBar = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0);
   datetime leftT = (firstBar >= 0) ? iTime(NULL, 0, firstBar) : 0;
   datetime rightT = iTime(NULL, 0, 0);
   if(leftT <= 0 || rightT <= 0) return;
   if(TimeCurrent() > rightT) rightT = TimeCurrent();

   for(int i = 0; i < s_sessStripN; i++)
   {
      SessSlot s;
      SessSlotGet(s_sessStripSlot[i], s);
      datetime s0 = s_sessStripS[i];
      datetime e0 = s_sessStripE[i];
      if(s0 < leftT) s0 = leftT;
      if(e0 > rightT) e0 = rightT;
      if(e0 <= s0) continue;
      int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!ChartTimePriceToXY(0, 0, s0, bid, x1, y1)) continue;
      if(!ChartTimePriceToXY(0, 0, e0, bid, x2, y2)) continue;
      if(x2 < x1) { int tx = x1; x1 = x2; x2 = tx; }
      SessStripBlock(inpObjectPrefix + SESS_TAG + "ST" + IntegerToString(s_sessStripSlot[i]) + "_" + IntegerToString(i),
                     x1 + SESS_STRIP_GAP, (x2 - x1) - SESS_STRIP_GAP * 2, SessColorOf(s.col));
   }
}

//--- P-UI-172 (2026-10-20): an OBJ_TEXT is anchored at the PIXEL of its time, so
//--- a time in the FUTURE has no pixel inside the chart area: the live session's
//--- H/L labels, its range caption and the countdown were anchored at the window's
//--- END (in the future while the session runs) and simply never appeared - the
//--- switches looked dead exactly when the session was live. ONE owner for the
//--- anchor: the window's end, clipped to NOW.
datetime SessLabelAnchor(const datetime endT, const datetime now)
{
   if(endT > now) return now;
   return endT;
}

//+------------------------------------------------------------------+
//| The tick (called from CoopPump's status job — 250 ms, both        |
//| entries). Order: want → state flips → rebuild-or-extend.          |
//+------------------------------------------------------------------+
void SessionsTick()
{
   if(StringLen(inpObjectPrefix) == 0) return;
   //--- P-SESS-16: the shipped presets reach a chart that was drawn by an OLD
   //--- build. Once per attach, a slot still on the legacy hours adopts the
   //--- current preset and the adopted value is what gets saved.
   static bool s_sessLegacyDone = false;
   if(!s_sessLegacyDone) { s_sessLegacyDone = true; if(SessSlotsMigrateLegacy(g_sessSlot)) RuntimeSettingsSaveOverridesThrottled(); }
   bool want = (g_sessMaster && !IsIndicatorHidden());
   if(!want)
   {
      if(s_sessBuilt)
      {
         SessWipe();
         s_sessBuilt = false;
         s_sessHash = 0;
         s_sessDay = 0;
         s_sessAlertSeeded = false;
         s_sessCdNext = 0;
         s_sessCdText = "";
         for(int z = 0; z < SESS_SLOTS; z++)
         {
            s_sessWasOpen[z] = false;
            s_sessLiveValid[z] = false;
            s_sessLiveBar[z] = 0;
         }
         ThrottledChartRedraw(true);
      }
      SessStripTick();      // P-SESS-19: off/hidden = the strip goes with the boxes
      return;
   }

   //--- P-SESS-12: a TF switch / attach can run this tick before the chart's
   //--- bars are loaded. SessPaintAll wipes first, so a zero-bar pass left the
   //--- whole family blank and then stored the built hash — no retry until the
   //--- next day. Return without wiping; the next 250 ms tick tries again.
   if(iBars(NULL, 0) <= 0) return;

   datetime now = TimeCurrent();
   int bkr = SessModelLiveDeltaMin();
   long h = SessViewHash();
   int day = SessServerDayStamp();
   bool settingsChanged = (s_sessBuilt && h != s_sessHash);

   int  flippedSlot = -1;
   bool flippedOpen = false;
   for(int sl = 0; sl < SESS_SLOTS; sl++)
   {
      SessSlot s;
      SessSlotGet(sl, s);
      bool isOpen = false;
      if(s.enabled)
      {
         //--- P-SESS-13: `now` is the CHART's clock, so the query goes through
         //--- the model's frame door — never the UTC engine directly.
         isOpen = SessSlotIsOpenNow(s, now, bkr);
      }
      if(s_sessAlertSeeded && !settingsChanged && isOpen != s_sessWasOpen[sl])
      {
         flippedSlot = sl;
         flippedOpen = isOpen;
      }
      s_sessWasOpen[sl] = isOpen;
   }

   if(!s_sessBuilt || h != s_sessHash || day != s_sessDay || flippedSlot >= 0)
   {
      SessPaintAll(now, bkr);
      s_sessBuilt = true;
      s_sessHash = h;
      s_sessDay = day;
      s_sessAlertSeeded = true;
      if(flippedSlot >= 0 && g_sessAlerts)
      {
         SessSlot fs;
         SessSlotGet(flippedSlot, fs);
         Alert("TH3 Session: " + SessZoneLabel(fs.zone) + (flippedOpen ? " opened" : " closed")
               + " (" + SessHhMmFromMin(fs.startMin) + "-" + SessHhMmFromMin(fs.endMin) + ")");
      }
      ThrottledChartRedraw(true);
      SessStripTick();      // P-SESS-19: lay the strip on the view this paint saw
      return;
   }

   SessLiveUpdate(now);

   //--- countdown text refresh, ~1 Hz while a boundary is pending
   if(g_sessCountdown && s_sessCdNext > 0)
   {
      uint t = GetTickCount();
      if(t - s_sessCdMs >= 900)
      {
         s_sessCdMs = t;
         SessSlot cs;
         SessSlotGet(s_sessCdSlot, cs);
         string nmU = SessZoneLabel(cs.zone);
         StringToUpper(nmU);
         int left = (int)(s_sessCdNext - now);
         if(left < 0) left = 0;
         string txt = nmU + (s_sessCdIsOpen ? " close " : " open ") + SessFmtDur(left);
         if(txt != s_sessCdText)
         {
            s_sessCdText = txt;
            string nmC = inpObjectPrefix + SESS_TAG + "CDN";
            if(ObjectFind(0, nmC) >= 0)
               ObjectSetString(0, nmC, OBJPROP_TEXT, txt);
         }
      }
   }

   SessStripTick();      // P-SESS-19: one signature compare, zero writes while still
}

#endif // SESSIONS_DRAW_MQH
