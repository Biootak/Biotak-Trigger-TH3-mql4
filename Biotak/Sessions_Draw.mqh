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
//--- P-SESS-39b: how many BODIES the last full paint of THIS instance declared.
//--- The absence probe may only call a chart "lost" when this instance really put
//--- bodies on it: a chart past its history (or a holiday window) legitimately paints
//--- zero, and a probe that cannot tell those apart would repaint it every 3 s.
static int      s_sessBodiesPainted = 0;
//--- P-SESS-40 (2026-10-31) — A COLD PASS IS NOT A RETIRED WINDOW.
//--- A timeframe switch reloads the series, and `SessHiLoFor` answers false for a
//--- window whose end is older than the deepest READABLE bar (P-SESS-31). The
//--- paint used to `continue` past such a window, so it was not declared — and
//--- the sweep then DELETED the box the previous instance had drawn, before the
//--- pass marked the family built. The result was a partial family that nothing
//--- would repaint until a setting changed: «یک جا حذف و رسم الکی». So a pass that
//--- skipped any started window is INCOMPLETE: it declares what it can, keeps the
//--- rest (the previous look, law 4), and skips its sweep. One warm retry follows.
static uint     s_sessWarmAt = 0;
static bool     s_sessWarmDone = false;
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
//--- P-SESS-35 (2026-10-31): THE HEALTHY-BLOCK QUESTION MUST NAME A BLOCK THE PAINT
//--- ACTUALLY WROTE. MEASURED on the live diag file: `[P-SESS] strip heal="…ST0_0"`
//--- and `[drawstrip] DELFLUSH` repeated on EVERY frame — the strip was wiped and
//--- rebuilt ~20 objects per tick. The heal asked `ST<slot0>_0`, i.e. run 0's name,
//--- but run 0 is the EARLIEST window and it is clipped away on every chart that has
//--- history (`s0 < leftT` → `e0 <= s0` → `continue`), so that object never exists:
//--- the family could never read healthy and the tick rebuilt it forever. The name
//--- below is the first block the last pass WROTE (empty when the pass wrote none).
static string   s_sessStripHealNm = "";

//+------------------------------------------------------------------+
//| Names + primitives                                                |
//+------------------------------------------------------------------+
string SessWindowName(const int slot, const int stamp, const string tail)
{
   return inpObjectPrefix + SESS_TAG + IntegerToString(slot) + "_" + IntegerToString(stamp) + "_" + tail;
}

//+------------------------------------------------------------------+
//| P-SESS-28 (2026-10-30) — THE FILL'S FADE IS THE HOUSE FADE.        |
//|                                                                   |
//| «شفافیت روی فیل رنگ‌ها درستی نیست، زیاد نمیشه … بقیه کدها رو بخون    |
//| قبلا پیاده‌سازی کردیم اینو».                                       |
//|                                                                   |
//| MEASURED from his own screenshot (22:16): the card read 47 %, the   |
//| witness read ink=53 and the pixels read 53 % ink — the row, the     |
//| value and the paint agreed, and the box was STILL a slab. The       |
//| reason is the CURVE, not the value: the rest of the product fades   |
//| a band with the stronger, squared fade (ZoneFactory                 |
//| `GetZoneRenderColor`: `tVis = 100 - (100-t)^2/100`, the trigger      |
//| family's mapping), so 47 % there keeps ~28 % ink while the sessions |
//| family kept a linear 53 % — the same knob, half the effect.         |
//|                                                                   |
//| SessFillVisInk is that ONE owner here: visible ink = ink^2 / 100.    |
//| The shipped tint (14 % visible) is ink 38, so the ROW's factory is  |
//| 62 % transparency and the picture is unchanged; his saved 53 now    |
//| paints 28 % (a real fade), and ink < 10 paints NO fill at all —      |
//| the box degrades to its four-edge hollow body, so the candles show  |
//| at the top of the range instead of a background-coloured slab.      |
//+------------------------------------------------------------------+
int SessFillVisInk()
{
   int ink = (int)MathMax(0, MathMin(100, g_sessFill));
   return (ink * ink) / 100;      // the house curve (P-UI-131m / ZoneFactory)
}

bool SessFillVisible()
{
   return (SessFillVisInk() > 0);   // ink < 10 is nothing: the hollow body draws
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
//| P-SESS-27 (2026-10-30) — THE STRIP IS THE COMPACT MODE.           |
//|                                                                   |
//| «وقتی استریپ روشن هستش دیگه خوده باکس‌ها نباشه … مزیت استریپ این   |
//| هستش که جمع و جور هستش، دیگه باکس لازم نباشه بکشه».               |
//|                                                                   |
//| The bottom strip already answers "which session, when" in window   |
//| pixels, so a chart with STRIP on carries the SAME information      |
//| twice — the boxes add nothing but ink over the candles. ONE owner  |
//| answers both painters (the full paint and the live extend), so a   |
//| box can never survive by being moved instead of created. Lines,    |
//| labels, the range caption, the countdown, the overlaps' PARENTS     |
//| and the strip itself are untouched: STRIP is a switch on the       |
//| BODIES, not on the family (every other row keeps its meaning).     |
//| P-SESS-27b: the BODY's own caption rides this switch too — a       |
//| floating "TYO/LDN/NY/SYD" over the candles is exactly the clutter  |
//| the compact mode is asked to remove (measured on his chart: the    |
//| boxes were gone and the four tags were still there).                |
//+------------------------------------------------------------------+
bool SessBoxBodiesWanted()
{
   return !g_sessStrip;   // strip on = compact: the strip marks the window, no body
}

//+------------------------------------------------------------------+
//| P-SESS-30 (2026-10-30) — A TIMEFRAME SWITCH IS A VIEW CHANGE, NOT |
//| A SETTINGS CHANGE.                                                |
//|                                                                   |
//| «الان بعضی وقت‌ها وقتی باکس‌ها نیستش، وقتی تایم عوض میکنم        |
//| [آپدیت نمیشه] … کمترین محاسبات الکی و حذف و رسم».                |
//|                                                                   |
//| MEASURED in the code: `SessViewHash` carried `Period()`, so every |
//| TF switch wiped and re-declared the WHOLE family (a 20-window     |
//| wipe + 20 H/L scans) even in the compact mode where nothing but   |
//| the strip is on the chart — while the STRIP's own signature      |
//| (`first*131+vis`, `*131+wpx`) did NOT change with the period, so  |
//| the one thing that had to move was the one thing that did not.    |
//|                                                                   |
//| The two questions are separated: SessNeedsBars() says whether any |
//| painted number is read off the chart's bars (bodies, H/L, range,  |
//| prior, overlap, countdown, TV levels). A TF switch rebuilds only  |
//| when that is true; otherwise it marks the STRIP dirty and re-lays  |
//| it in PIXELS — one pass over the runs, zero deletes.             |
//+------------------------------------------------------------------+
bool SessNeedsBars()
{
   return (SessBoxBodiesWanted() || g_sessHlLines || g_sessHlLabels || g_sessRangeText ||
           g_sessPrior || g_sessOverlap || g_sessCountdown || g_sessTv > 0);
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
//--- P-SESS-37: the four primitives below are the file's only ObjectCreate sites, so
//--- each of them DECLARES the name it writes. The list itself is defined further down
//--- (it needs SESS_TAG and the prefix). No forward declaration is written: MQL4
//--- resolves a function defined LATER IN THE SAME COMPILATION UNIT, and a bare
//--- prototype only earns the compiler's «no #import declaration» warning (P-BUILD-11).

void SessEdge(const string nm, const datetime t1, const double p1, const datetime t2, const double p2,
              const color clr, const int width, const ENUM_LINE_STYLE style, const string tip)
{
   SessDeclare(nm);   // P-SESS-37: this name is being written — the sweep must leave it
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
   SessDeclare(nm);   // P-SESS-37: the FILLED box is a rectangle under `nm` itself
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
   SessDeclare(nm);   // P-SESS-37
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
   SessDeclare(nm);   // P-SESS-37
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
//+------------------------------------------------------------------+
//| P-SESS-31 (2026-10-30) — THE DEEPEST BAR THE CHART CAN REALLY READ. |
//|                                                                   |
//| iTime() answers 0 for a slot whose timeseries has not been built    |
//| yet, even while iBars() still counts the bar. That is the state of  |
//| the first paints after an attach or a terminal restart, while the   |
//| oldest end is still syncing, and asking ONLY slot `bars-1` turned   |
//| it into "there is no history at all": every window failed its scan, |
//| the paint declared just the live box, and the family looked healthy |
//| while every past box was gone. So probe upward for a slot that HAS  |
//| a stamp, in growing steps (8,16,32,...) — bounded at 20 reads and   |
//| paid ONLY on that cold path. The answer is deliberately              |
//| conservative: it is the first readable slot, never deeper than what  |
//| the scan can prove, so a window older than it is still skipped       |
//| instead of being priced from its tail bars and drawn short.          |
//|                                                                      |
//| ONE file, both entries: the MQL5 tree carries this same line, so     |
//| module-report.py sees one arithmetic on both sides.                  |
//+------------------------------------------------------------------+
datetime SessHistFloor()
{
   int bars = iBars(NULL, 0);
   if(bars <= 0) return 0;
   datetime f = iTime(NULL, 0, bars - 1);
   if(f > 0) return f;
   int idx = bars - 1;
   int step = 8;
   for(int p = 0; p < 20 && idx > 0; p++)
   {
      idx -= step;
      if(idx < 0) idx = 0;
      f = iTime(NULL, 0, idx);
      if(f > 0) return f;
      step *= 2;
   }
   return 0;
}

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
   datetime oldestT = SessHistFloor();            // P-SESS-31: the deepest READABLE bar (iTime() is 0 while a series syncs)
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
   datetime oldestT = SessHistFloor();            // P-SESS-31: the deepest READABLE bar (iTime() is 0 while a series syncs)
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
   //--- P-SESS-30: NO `Period()` term. A TF switch is answered by the tick's own
   //--- `tfChanged` (rebuild only when SessNeedsBars, otherwise one strip re-lay),
   //--- so the compact chart costs zero deletes on a switch instead of a wipe.
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
//| P-SESS-37 (2026-10-31) — A PAINT NEVER WIPES. IT DECLARES, THEN  |
//| REMOVES ONLY WHAT IT DID NOT DECLARE.                            |
//|                                                                   |
//| «وقتی تایم عوض میکنم حذف میشه … نباید حذف و رسم الکی بشه».      |
//|                                                                   |
//| MT4 answers a period change with a deinit+init, so the NEW        |
//| instance starts with `s_sessBuilt=false` and `s_sessHash=0` —     |
//| while the OBJECTS are untouched on the chart. MEASURED            |
//| 2026-10-31 10:24:31: the fresh instance printed                   |
//| `[P-SESS] tick master=1 hidden=0 bars=14130 tf=15 built=0`, then  |
//| `[P-SESS] paint` + 20 `win` lines + `bodies=20 tags=20` — the     |
//| first tick wiped and re-declared the whole family for a switch    |
//| that changes no name. P-SESS-30's own door                        |
//| (`tfChanged && SessNeedsBars`) could never answer it, because     |
//| `!s_sessBuilt` had already fired.                                 |
//|                                                                   |
//| The answer is not a smarter wipe, it is NO wipe: the paint DECLARES |
//| every name it writes and then deletes only the names it did NOT     |
//| declare. That is the same job the wipe was doing — removing what a  |
//| settings or day change left behind — done by a set difference       |
//| instead of a blanket delete, so an unchanged family costs ZERO      |
//| deletes and no path can ever delete a name it is about to paint.    |
//|                                                                   |
//| The declaration is COMPLETE BY CONSTRUCTION, not by a second list: |
//| every session object in this file is born in one of FOUR           |
//| primitives (`SessEdge`, `SessRect`, `SessLine`, `SessText` — the   |
//| file's only `ObjectCreate` sites), so each one records its own     |
//| name as it writes it. A new tail cannot forget to register.        |
//|                                                                   |
//| The STRIP is excluded: it is laid out in WINDOW pixels by          |
//| `SessStripTick` against the current view, owns its own prefix and  |
//| its own sweep, and the paint declares none of its blocks.          |
//+------------------------------------------------------------------+
//--- THE DECLARED LIST. `s_sessCollect` is raised only while a paint is running, so
//--- the live extend (which calls the same primitives on a new bar) never pollutes it.
#define SESS_DECL_MAX 1024
static bool   s_sessCollect = false;
static string s_sessDeclared[SESS_DECL_MAX];
static int    s_sessDeclaredN = 0;

void SessDeclare(const string nm)
{
   if(!s_sessCollect) return;
   if(StringLen(nm) == 0) return;
   if(s_sessDeclaredN >= SESS_DECL_MAX) return;
   s_sessDeclared[s_sessDeclaredN] = nm;
   s_sessDeclaredN++;
}

bool SessWasDeclared(const string nm)
{
   for(int i = 0; i < s_sessDeclaredN; i++)
      if(s_sessDeclared[i] == nm) return true;
   return false;
}

//--- P-SESS-38 (2026-10-31) — THE NUMBER THAT SAYS WHO DELETED THEM.
//--- A switch is deinit+init, so the first paint of the new instance can measure
//--- what the CHART still held the instant it woke up: `preexist`. If preexist ==
//--- declared, nothing was ever taken off the chart and the switch is invisible.
//--- If preexist == 0, the TERMINAL unloaded the family during the reload and no
//--- MQL4 line can prevent it — that is a different defect with a different fix.
//--- One walk per paint (a paint is rare), zero writes.
int SessFamilyCount()
{
   string pfx = inpObjectPrefix + SESS_TAG;
   string stripPfx = pfx + "ST";
   int n = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, pfx) != 0) continue;
      if(StringFind(nm, stripPfx) == 0) continue;
      n++;
   }
   return n;
}

//--- THE SWEEP — what the blanket wipe used to do, without the blanket. One walk of
//--- the chart, one test per session object: "did this paint write your name?". The
//--- names it did are left untouched; the rest are what a settings change or a day
//--- rollover left behind, and those are the only ones removed. Returns the count, so
//--- the frame can prove it instead of arguing about it.
int SessSweepSurplus()
{
   string pfx = inpObjectPrefix + SESS_TAG;
   string stripPfx = pfx + "ST";
   int deleted = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringLen(nm) == 0) continue;
      if(StringFind(nm, pfx) != 0) continue;
      if(StringFind(nm, stripPfx) == 0) continue;   // the strip owns its own family
      if(SessWasDeclared(nm)) continue;
      if(ObjectDelete(0, nm)) deleted++;
   }
   return deleted;
}

//+------------------------------------------------------------------+
//| THE FULL PAINT — declare every window the settings admit, then    |
//| sweep what it did NOT declare. Never a wipe (P-SESS-37).          |
//| Windows are ordered by kk (oldest .. newest), so the started      |
//| block is a prefix and the ghosts are its tail.                    |
//+------------------------------------------------------------------+
//--- P-SESS-40: returns TRUE only when every started window could be priced.
//--- The ONE caller reads it to schedule the single warm retry and, more
//--- importantly, an incomplete pass never sweeps (see the block at its end).
bool SessPaintAll(const datetime now, const int bkr)
{
   //--- P-SESS-37: NO WIPE. Open the declaration list; every primitive below records
   //--- the name it writes, and SessSweepSurplus() at the end removes only the names
   //--- this paint did NOT write. A timeframe switch, a settings change and a
   //--- re-attach all take this one path, and none of them can delete an object it is
   //--- about to re-paint — which is the whole defect (see the block above).
   s_sessCollect = true;
   s_sessDeclaredN = 0;
   int preexist = SessFamilyCount();   // P-SESS-38: what the chart still held on arrival
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
   //--- P-UI-221 (2026-10-30): `ink` is the number the boxes are ACTUALLY painted
   //--- with (100 - the card's TRANSPARENCY). MEASURED from the user's screenshot:
   //--- the chip read 39 % while the fill sat at 45, so the two numbers must ride
   //--- the same line or «شفافیت کار نمیکند» is decided by eye.
   DrawStripDiagEmit(StringFormat("[P-SESS] paint bkr=%d dst=%d ink=%d noon=%s srv=%s gmt=%s raw=%d held=%d tv=%d strip=%d",
                                  bkr, g_sessDst ? 1 : 0, g_sessFill, TimeToString(noon, TIME_DATE|TIME_MINUTES),
                                  TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  TimeToString(TimeGMT(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                                  (int)(TimeCurrent() - TimeGMT()), SessModelDeltaHeldCount(),
                                  g_sessTv, g_sessStrip ? 1 : 0));
#endif
   SessWindow wins[];
   ArrayResize(wins, 96);
   int n = 0;
   //--- P-SESS-27: how many BODIES and how many TAGS this paint really declared.
   //--- The counts are the proof that a compact (STRIP on) chart carries no box and
   //--- no floating name — the object list is not the screen, so the numbers ride
   //--- the flushed channel (law 3).
   int bDecl = 0;
   int tDecl = 0;
   int unpriced = 0;   // P-SESS-40: started windows this pass could not price (cold series)

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
         if(!wins[w].hasPrice)
         {
            unpriced++;   // P-SESS-40: unreadable history, NOT a retired window
            continue;
         }
         bandSet[sl] = true; bandHi[sl] = wins[w].hi; bandLo[sl] = wins[w].lo;
         string tip = SessWindowTip(s, wins[w].sU, wins[w].hi, wins[w].lo, true);
         string nmB = SessWindowName(sl, wins[w].stamp, "B");
         bool wLive = (SessWindowState(wins[w], now) == SESS_WS_LIVE);   // P-SESS-06
         color ink = wLive ? base : SessBlend(base, SESS_PAST_ALPHA);    // live keeps the ink, past fades
         int bW = wLive ? 2 : 1;                                         // the live box is bold
         color fillC = clrNONE;   // P-SESS-14/28: the fill the user asked for, faded by the HOUSE curve
         if(s.style == SESS_STYLE_FILLED && SessFillVisible())
            fillC = SessBlend(base, 100 - SessFillVisInk());
#ifndef BUILD_LITE
         //--- P-SESS-15: the box's own edges, read back from what was PAINTED.
         DrawStripDiagEmit(StringFormat("[P-SESS] win slot=%d stamp=%d sU=%s eU=%s hi=%.3f lo=%.3f live=%d",
                                        sl, wins[w].stamp, TimeToString(wins[w].sU, TIME_DATE|TIME_MINUTES),
                                        TimeToString(wins[w].eU, TIME_DATE|TIME_MINUTES),
                                        wins[w].hi, wins[w].lo, wLive ? 1 : 0));
#endif
         if(SessBoxBodiesWanted())   // P-SESS-27: with the strip on there is no body (the tag stays)
         {
            SessRect(nmB, wins[w].sU, wins[w].hi, wins[w].eU, wins[w].lo, ink, fillC, bW, STYLE_SOLID, tip);
            bDecl++;
         }
         if(SessBoxBodiesWanted())   // P-SESS-27b: the name IS the box's caption — «توی حالت استریپ این نوشته‌ها هم نباشه»
         {
            SessText(nmB + "L", wins[w].sU, wins[w].hi, SessZoneTag(s.zone), ink, SESS_PT_LBL,
                     ANCHOR_LEFT_LOWER, tip);   // P-SESS-22: the name sits ABOVE the box, never on the candles
            tDecl++;
         }
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
         if(SessBoxBodiesWanted())   // P-SESS-27: an upcoming window is a body too
            SessRect(nmF, wins[w].sU, bandHi[sl], wins[w].eU, bandLo[sl],
                     SessBlend(base, SESS_GHOST_ALPHA), clrNONE, 1, STYLE_DOT, tipF);
         //--- P-SESS-08: the tag tail must NOT be "L" here — `_F` + `L` spells `_FL`,
         //--- the fill-child suffix (FILLCHILD_SUFFIX, Toolbar_A), so the strip's
         //--- orphan sweep deleted every ghost tag 2 s after it was painted (log
         //--- witness: ORPHAN drop="THLevelsSESS_2_20261021_FL"). "T" is the tag.
         if(SessBoxBodiesWanted())   // P-SESS-27b: an upcoming window's caption belongs to its body
         {
            SessText(nmF + "T", wins[w].sU, bandHi[sl],
                     SessZoneTag(s.zone) + " " + SessHhMmFromMin(s.startMin),
                     SessBlend(base, SESS_GHOST_ALPHA), SESS_PT_LBL, ANCHOR_LEFT_UPPER, tipF);
            tDecl++;
         }
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
            if(SessBoxBodiesWanted())   // P-SESS-27: the overlap is a body as well
            {
               SessRect(nmX, t1, hi, t2, lo, SessBlend(ovColor[a], SESS_X_ALPHA), clrNONE,
                        1, STYLE_DOT, "overlap");
               bDecl++;
            }
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
      s_sessCdText = nmU + (s_sessCdIsOpen ? " close " : " open ") + SessFmtDur((int)(s_sessCdNext - now));      if(cdP > 0.0)
         SessText(nmC, SessLabelAnchor(s_sessCdNext, now), cdP, s_sessCdText, SESS_CD_COLOR, SESS_PT_PRICE,
                  ANCHOR_LEFT_LOWER, "next session boundary");
   }
#ifndef BUILD_LITE
   //--- P-SESS-27/28 witness: bodies actually declared, the strip's own state and
   //--- the ink the fill is painted with AFTER the house fade (P-SESS-28).
   DrawStripDiagEmit(StringFormat("[P-SESS] bodies=%d tags=%d strip=%d ink=%d vis=%d",
                                  bDecl, tDecl, g_sessStrip ? 1 : 0, g_sessFill, SessFillVisInk()));
#endif
   //--- P-SESS-37: the declaration is complete, so close it and remove exactly what
   //--- this paint did NOT write. On an unchanged family that set is EMPTY: the walk
   //--- runs, the test answers "declared" for every name, and the count prints 0 —
   //--- which is the number this defect was missing all along.
   s_sessCollect = false;
   s_sessBodiesPainted = bDecl;   // P-SESS-39b: the number the absence probe compares against
   //--- P-SESS-40: AN INCOMPLETE PASS MUST NOT SWEEP. A window the cold series
   //--- cannot price was not declared above, so the sweep would read it as retired
   //--- and delete a box that is still correct — and this pass then marks the
   //--- family built, so nothing repaints it later. Keeping the names is the
   //--- "degrade to the previous look" law: the old box stays exactly where the
   //--- last pass put it, and the one warm retry re-prices it.
   int swept = 0;
   if(unpriced <= 0) swept = SessSweepSurplus();
#ifndef BUILD_LITE
   if(unpriced > 0)
      DrawStripDiagEmit(StringFormat("[P-SESS] sweep skipped cold=%d preexist=%d declared=%d",
                                     unpriced, preexist, s_sessDeclaredN));
   //--- P-SESS-41: THE PASS ANSWERS FOR ITS OWN RESULT. `preexist` is what the chart
   //--- held on arrival and `declared` what the pass WROTE; `chart` is what the chart
   //--- really holds when the pass ends. declared == chart => every name this pass
   //--- wrote exists (a later disappearance is somebody else's delete). declared >
   //--- chart => the WRITES themselves failed, and no sweep can be blamed.
   DrawStripDiagEmit(StringFormat("[P-SESS] sweep preexist=%d declared=%d deleted=%d chart=%d",
                                  preexist, s_sessDeclaredN, swept, SessFamilyCount()));
#endif
   return (unpriced <= 0);
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
   //--- session really printed a new extreme (the caller's compare).
   //--- P-SESS-27: with the strip on there is no body to move — skipping the
   //--- moves is what keeps a compact chart at ZERO writes per new extreme.
   if(!SessBoxBodiesWanted())
   {
      // nothing to extend: the strip lays itself out from the window list
   }
   else if(s.style == SESS_STYLE_FILLED && SessFillVisible())
   {
      // P-SESS-28: the RECTANGLE body exists only while the fill does; at ink < 10
      // the paint made the four-edge hollow body instead, and these two moves for
      // a rect nobody created would be silent no-ops on the live window.
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

//--- P-SESS-37 (2026-10-31): THE STRIP IS NO LONGER WIPED EITHER. A block's name is
//--- `ST<slot>_<run>`, so a view change — and a timeframe switch is one — moves and
//--- resizes the SAME names; only the surplus (a run that stopped existing) is removed.
//--- The pass declares what it wrote, then sweeps the rest: zero deletes on a switch.
#define SESS_STRIP_WMAX SESS_STRIP_MAX
static string s_sessStripWritten[SESS_STRIP_WMAX];
static int    s_sessStripWrittenN = 0;

void SessStripSweep()
{
   string pfx = inpObjectPrefix + SESS_TAG + "ST";
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, pfx) != 0) continue;
      bool kept = false;
      for(int k = 0; k < s_sessStripWrittenN; k++)
         if(s_sessStripWritten[k] == nm) { kept = true; break; }
      if(!kept) ObjectDelete(0, nm);
   }
}

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
   //--- P-SESS-30: the PERIOD belongs in the signature. `first`/`vis` are bar
   //--- COUNTS, so M15 -> M5 keeps both numbers while every block's pixel seat
   //--- moves — the strip then read "still frame" and stayed on the old axis.
   return (((long)Period() * 131 + first) * 131 + vis) * 131 + wpx;
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
   if(!s_sessStripDirty && sig == s_sessStripSig)
   {
      //--- P-SESS-30b (2026-10-30): A STILL VIEW IS ONLY STILL IF ITS BLOCKS ARE
      //--- STILL THERE. MEASURED: «با وجود که روشن هستش ولِی اینطوری میشه» — the
      //--- switch is ON and the strip is not on the chart. A block family that a
      //--- sweep, a chart reload or a failed re-lay took can never come back
      //--- through this door, because the signature it compares never changes
      //--- again. ONE ObjectFind per tick while the view stands still (a READ, no
      //--- writes), and a healthy frame still costs zero paints.
      if(s_sessStripN <= 0) return;                       // nothing to draw: the family paint owns it
      string nm0 = s_sessStripHealNm;                      // P-SESS-35: the name the paint WROTE
      if(nm0 == "") return;                               // the last pass wrote no block (all runs clipped)
      if(ObjectFind(0, nm0) >= 0) return;                  // healthy: the first written block is there
      DrawStripDiagEmit("[P-SESS] strip heal=\"" + nm0 + "\" runs=" + IntegerToString(s_sessStripN));
   }
   //--- P-SESS-39 (2026-10-31) — READ THE CHART BEFORE THE SIGNATURE IS COMMITTED.
   //---
   //--- «وقتی تایم عوض می‌کنم حذف میشه … بعد از اون چرا آپدیت نمیشه که دوباره
   //--- رسم بشه». MEASURED in this order, not guessed: the signature was
   //--- committed, `dirty` cleared and the heal name emptied FIRST, and the
   //--- chart's time edges were read AFTER. A timeframe change reloads the
   //--- series, and `iTime()` answers 0 until it is built — the same fact
   //--- P-SESS-31 documents for the H/L scan — so the read failed and took
   //--- `{ SessStripSweep(); return; }`: the whole strip deleted by a pass that
   //--- had already recorded itself as laid out, with its heal name spent.
   //--- The next tick compared the SAME signature, skipped the layout, and the
   //--- still branch found `s_sessStripHealNm == ""` (cleared above) and
   //--- returned: the strip could never come back until the VIEW moved — which is
   //--- exactly the report.
   //---
   //--- So the edges are read FIRST and a cold chart costs NOTHING: the dirty
   //--- flag stays true, the signature stays stale, no block is written or
   //--- deleted, and the next tick retries. Only a chart that can answer the
   //--- edges may commit.
   int firstBar = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0);
   datetime leftT = (firstBar >= 0) ? iTime(NULL, 0, firstBar) : 0;
   datetime rightT = iTime(NULL, 0, 0);
   if(leftT <= 0 || rightT <= 0)
   {
      //--- the flushed witness of the cold pass (P-DRAW-126): the next report of
      //--- «حذف شد» is this line, not a reproduction round.
      DrawStripDiagEmit(StringFormat("[P-SESS] strip cold first=%d left=%s right=%s runs=%d",
                                     firstBar, TimeToString(leftT), TimeToString(rightT),
                                     s_sessStripN));
      return;   // retry next tick, touch nothing: the chart cannot answer yet
   }
   if(TimeCurrent() > rightT) rightT = TimeCurrent();

   s_sessStripSig = sig;
   s_sessStripDirty = false;
   s_sessStripHealNm = "";          // P-SESS-35: the next pass declares its first written block
   s_sessStripWrittenN = 0;         // P-SESS-37: and it DECLARES every block it writes
   if(s_sessStripN <= 0) { SessStripSweep(); return; }

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
      string nmB = inpObjectPrefix + SESS_TAG + "ST" + IntegerToString(s_sessStripSlot[i]) + "_" + IntegerToString(i);
      SessStripBlock(nmB, x1 + SESS_STRIP_GAP, (x2 - x1) - SESS_STRIP_GAP * 2, SessColorOf(s.col));
      if(s_sessStripHealNm == "") s_sessStripHealNm = nmB;   // P-SESS-35: the healthy-block witness
      if(s_sessStripWrittenN < SESS_STRIP_WMAX) { s_sessStripWritten[s_sessStripWrittenN] = nmB; s_sessStripWrittenN++; }
   }
   //--- P-SESS-37: the runs this pass did NOT write are the ones that stopped existing.
   //--- A view change that keeps the same runs — a timeframe switch included — removes
   //--- nothing, and the blocks are never taken off the chart to be put back.
   SessStripSweep();
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
   //--- P-SESS-36 (2026-10-31): A THROTTLED SWITCH IS AN OWED WRITE, NOT A LOST ONE.
   //--- The 250 ms tick spends any save a switch asked for inside the throttle's
   //--- window (the ring's sessions key did exactly that), so a click can never be
   //--- answered by the PREVIOUS value on the next attach. One bool test when
   //--- nothing is owed.
   RuntimeSettingsSaveDrain();
   //--- P-SESS-32 WITNESS (2026-10-31) — «سشن‌ها بعد از ریستارت نمی‌آیند» costs a
   //--- reproduction round every time, because the tick that DECIDES to paint said
   //--- nothing. ONE line per attach, through the flushed channel (P-DRAW-126): the
   //--- master as the RUNTIME holds it, the mute, the bar count, the timeframe and
   //--- the prefix the overrides were loaded under. A frame that never paints now
   //--- answers WHY instead of reading as "nothing happened".
   static bool s_sessTickSaid = false;
   if(!s_sessTickSaid)
   {
      s_sessTickSaid = true;
      DrawStripDiagEmit(StringFormat("[P-SESS] tick master=%d hidden=%d bars=%d tf=%d built=%d pfx=%s",
                                     g_sessMaster ? 1 : 0, IsIndicatorHidden() ? 1 : 0,
                                     iBars(NULL, 0), Period(), s_sessBuilt ? 1 : 0, g_settingsGVPrefix));
   }
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
   //--- bars are loaded. A zero-bar pass would declare nothing and then store the
   //--- built hash — no retry until the next day. Return without painting; the next
   //--- 250 ms tick tries again.
   if(iBars(NULL, 0) <= 0) return;

   datetime now = TimeCurrent();
   int bkr = SessModelLiveDeltaMin();
   long h = SessViewHash();
   int day = SessServerDayStamp();
   //--- P-SESS-30: the TF is tracked HERE, not inside the hash (see SessNeedsBars).
   static int s_sessTfSeen = 0;
   bool tfChanged = (s_sessTfSeen != Period());
   s_sessTfSeen = Period();
   if(tfChanged)
      s_sessStripDirty = true;   // the strip lives in PIXELS: one re-lay, whatever else changes
   bool settingsChanged = (s_sessBuilt && h != s_sessHash);
   //--- P-SESS-39b (2026-10-31) — THE CHART IS THE WITNESS (P-VIEW-05's law here).
   //--- `s_sessBuilt` is a claim made by THIS instance; the objects are the only
   //--- durable record of the family. MEASURED on the user's log: a chart whose
   //--- session family was gone read `total=167` (the level family alone) while
   //--- the instance still believed it was built — and the paint trigger below
   //--- answers only CHANGES (hash / day / tf), never ABSENCE. So a family taken
   //--- off a live chart stayed off until a setting moved. ONE walk per instance,
   //--- and only when bodies are expected (with the strip on, the family IS the
   //--- strip and owns its own heal): a chart that lost them is repainted once.
   static uint s_sessAbsenceMs = 0;
   if(s_sessBuilt && s_sessBodiesPainted > 0 && SessBoxBodiesWanted())
   {
      uint abNow = GetTickCount();
      if(abNow - s_sessAbsenceMs >= 3000)   // 1 walk / 3 s, only while bodies are on the chart
      {
         s_sessAbsenceMs = abNow;
         if(SessFamilyCount() <= 0)
         {
            s_sessBuilt = false;   // the paint below re-declares every name
            DrawStripDiagEmit("[P-SESS] absence family=0 painted=" + IntegerToString(s_sessBodiesPainted) + " -> repaint");
         }
      }
   }

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

   //--- P-SESS-30: a switch rebuilds only when a PAINTED NUMBER is read off the
   //--- bars; a compact chart (strip only) keeps every object it has and pays the
   //--- strip's one pass instead of a wipe + 20 scans.
   //--- P-SESS-37: and that rebuild is NO LONGER a wipe. `SessPaintAll` declares what
   //--- it writes and sweeps only what it did not, so the switch updates the 20 boxes
   //--- in place — the same names, the new timeframe's numbers, zero deletes.
   //--- P-SESS-40: THE ONE WARM RETRY. A pass that ran while the switched series
   //--- was still building priced only part of the family; the series settles within
   //--- a bar or two, so it is re-priced ONCE, 1.2 s later, and never again (the
   //--- flag is spent). A complete pass costs nothing here.
   if(s_sessWarmAt != 0 && GetTickCount() >= s_sessWarmAt)
   {
      s_sessWarmAt = 0;
      s_sessBuilt = false;   // fall into the paint below on this same tick
   }

   if(!s_sessBuilt || h != s_sessHash || day != s_sessDay || flippedSlot >= 0 ||
      (tfChanged && SessNeedsBars()))
   {
      bool complete = SessPaintAll(now, bkr);
      if(!complete && !s_sessWarmDone)
      {
         s_sessWarmDone = true;
         s_sessWarmAt = GetTickCount() + 1200;
      }
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
