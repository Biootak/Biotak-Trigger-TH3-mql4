#ifndef HTF_CANDLES_MQH
#define HTF_CANDLES_MQH

#property strict

#define HTF_PREFIX_BASE "BiotakHTF_"
static string g_HTFPrefix;

#define HTF_FILL_STRONG 0.70
#define HTF_FILL_FAINT  0.25

#define MIN_OPACITY_PCT 0
#define MAX_OPACITY_PCT 100
#define MIN_WIDTH 1
#define MAX_WIDTH 5

// HTF box modes
#define HTF_BOX_HOLLOW 0
#define HTF_BOX_FILLED 1
#define HTF_BOX_BOTH   2

// HTF timeframe selection modes (panels read these factory defaults)
#define HTF_AUTO_FRACTAL 0
#define HTF_AUTO_FIXED   1

// Color blending cache
#define BLEND_CACHE_SIZE 8

struct ColorBlendCache {
   color bgColor;
   color fgColor;
   double opacity;
   color result;
};
static ColorBlendCache g_BlendCache[BLEND_CACHE_SIZE];

// Runtime settings
static int    g_HTFPeriod = PERIOD_H4;
static bool   g_HTFIsAuto = true;
static color  g_HTFBullColor = C'66,200,155';
static color  g_HTFBearColor = C'255,100,124';
static color  g_HTFWickColor = C'150,155,165';
static color  g_HTFBorderColor = clrNONE;
static int    g_HTFOpacity = 30;
static bool   g_HTFShowWicks = true;
static int    g_HTFWickWidth = 1;
static int    g_HTFBorderWidth = 1;
static int    g_HTFBoxMode = HTF_BOX_HOLLOW;
static bool   g_HTFShowBody = true;

// Default inputs
static int    InpHTFMaxBars = 200;
static int    InpHTFAutoMode = HTF_AUTO_FRACTAL;
static int    InpHTFTimeframe = PERIOD_H4;
static color  InpHTFBullColor = C'66,200,155';
static color  InpHTFBearColor = C'255,100,124';
static color  InpHTFWickColor = C'150,155,165';
static color  InpHTFBorderColor = clrNONE;
static int    InpHTFOpacity = 30;
static bool   InpHTFShowWicks = true;
static int    InpHTFWickWidth = 1;
static int    InpHTFBorderWidth = 1;
static int    InpHTFBoxMode = HTF_BOX_HOLLOW;
static bool   InpHTFShowBody = true;

//--- Live-edge cache: OHLC + open time of the forming HTF candle as last drawn
static datetime g_HTFLastFormOpen = 0;
static double   g_HTFLastFormO = 0, g_HTFLastFormH = 0, g_HTFLastFormL = 0, g_HTFLastFormC = 0;

//==============================================================================
// DRAW / WRITE BUDGET + VIEWPORT CAP (P-PERF-02)
//
// (a) BUDGET: the forming HTF candle used to rewrite its 3 objects on EVERY
//     price change — i.e. on every tick — and every write marks the chart
//     dirty, so the terminal repainted the whole chart at tick rate just to
//     move one wick a few pixels. ~6 updates/second are visually identical to
//     60 and cost ~10x less; a NEW BAR always draws immediately.
// (b) CAP: nothing left of the viewport is visible, but a full 200-bar HTF
//     history is up to 600 rectangle/trend objects that every pan, zoom and
//     repaint still pays for. Draw the visible range + headroom, keep the
//     tail pruned through the existing HTFDeleteIndices path.
//==============================================================================
#define HTF_FORM_MS    150   // min gap between forming-candle writes (ms)
#define HTF_CULL_HYST  40    // extra bars kept beyond the visible range
#define HTF_CULL_MIN   20    // never draw fewer than this many HTF bars

static uint g_HTFFormWriteMs = 0;   // last forming-candle WRITE (0 = none yet)
static int  g_HTFDrawnCount  = 0;   // HTF bars currently on the chart

//+------------------------------------------------------------------+
//| Extract RGB components from color                                |
//+------------------------------------------------------------------+
void ExtractRGB(const color clr, int &r, int &g, int &b)
{
   r = (clr & 0x0000FF);
   g = (clr & 0x00FF00) >> 8;
   b = (clr & 0xFF0000) >> 16;
}

//+------------------------------------------------------------------+
//| P-PERF-08: ONE chart-background read per HTF draw pass.           |
//|                                                                  |
//| WHY: BlendWithBackground() is the opacity emulator every HTF body, |
//| wick and border goes through, and it read CHART_COLOR_BACKGROUND   |
//| from the terminal on EVERY call — BEFORE consulting its own cache,  |
//| so the cache could never save a single syscall. DrawHTFCandleCore   |
//| blends 3 colours per bar (candle, wick, border) and the BOX_BOTH    |
//| mode one more, so a full HTF history draw (up to ~240 bars) issued   |
//| 700-1000 terminal reads for a colour that cannot change unless the   |
//| user edits chart properties. They landed in the same frame as the    |
//| domain's level repaint, which is exactly the window that overflowed. |
//|                                                                      |
//| The background is now read once at the head of each draw pass (and    |
//| lazily if anything else asks for it), so a draw is both cheaper and   |
//| internally consistent: one value, not one value per bar.              |
//+------------------------------------------------------------------+
static color g_HTFBlendBg = clrNONE;

void HTFRefreshBlendBackground()
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0);
   if(bg == 0) bg = clrBlack;
   g_HTFBlendBg = bg;
}

color HTFBlendBackgroundColor()
{
   if(g_HTFBlendBg == clrNONE) HTFRefreshBlendBackground();
   return g_HTFBlendBg;
}

//+------------------------------------------------------------------+
//| Blend color with chart background (simulate opacity)             |
//+------------------------------------------------------------------+
color BlendWithBackground(const color fg, const double opacity)
{
   static bool s_initialized = false;
   if(!s_initialized)
   {
      for(int i = 0; i < BLEND_CACHE_SIZE; i++)
      {
         g_BlendCache[i].bgColor  = clrNONE;
         g_BlendCache[i].fgColor  = clrNONE;
         g_BlendCache[i].opacity  = -1.0;
         g_BlendCache[i].result   = clrNONE;
      }
      s_initialized = true;
   }

   color bg = HTFBlendBackgroundColor();   // P-PERF-08: cached, one read per draw pass

   for(int i = 0; i < BLEND_CACHE_SIZE; i++)
   {
      if(g_BlendCache[i].bgColor == bg &&
         g_BlendCache[i].fgColor == fg &&
         g_BlendCache[i].opacity == opacity)
         return g_BlendCache[i].result;
   }

   int r_fg, g_fg, b_fg, r_bg, g_bg, b_bg;
   ExtractRGB(fg, r_fg, g_fg, b_fg);
   ExtractRGB(bg, r_bg, g_bg, b_bg);

   double a = MathMax(0.0, MathMin(1.0, opacity));
   int r = (int)MathRound(r_fg * a + r_bg * (1.0 - a));
   int g = (int)MathRound(g_fg * a + g_bg * (1.0 - a));
   int b = (int)MathRound(b_fg * a + b_bg * (1.0 - a));

   r = MathMax(0, MathMin(255, r));
   g = MathMax(0, MathMin(255, g));
   b = MathMax(0, MathMin(255, b));

   color res = (color)(r | (g << 8) | (b << 16));

   static int s_nextCacheSlot = 0;
   g_BlendCache[s_nextCacheSlot].bgColor  = bg;
   g_BlendCache[s_nextCacheSlot].fgColor  = fg;
   g_BlendCache[s_nextCacheSlot].opacity  = opacity;
   g_BlendCache[s_nextCacheSlot].result   = res;

   s_nextCacheSlot = (s_nextCacheSlot + 1) % BLEND_CACHE_SIZE;
   return res;
}

//+------------------------------------------------------------------+
//| Resolve Auto HTF Timeframe (Fractal mode: two steps up)          |
//+------------------------------------------------------------------+
int ResolveAutoHTFPeriod()
{
   switch(Period())
   {
      case PERIOD_M1:  return PERIOD_M15;   // 1m  *16 = 16m  → M15
      case PERIOD_M5:  return PERIOD_H1;    // 5m  *16 = 80m  → H1
      case PERIOD_M15: return PERIOD_H4;    // 15m *16 = 240m → H4 (exact)
      case PERIOD_M30: return PERIOD_H4;    // 30m *16 = 480m → H4
      case PERIOD_H1:  return PERIOD_D1;    // 1h  *16 = 16h  → D1
      case PERIOD_H4:  return PERIOD_W1;    // 4h  *16 = 64h  → W1
      case PERIOD_D1:  return PERIOD_MN1;   // 1d  *16 = 16d  → MN1
      case PERIOD_W1:  return PERIOD_MN1;   // 1w  *16 → MN1 (highest available)
      default:         return 0;            // MN1: nothing above → hidden
   }
}

//+------------------------------------------------------------------+
//| Effective HTF period honoring Auto/Manual mode                    |
//+------------------------------------------------------------------+
int ResolveHTFPeriod()
{
   if(g_HTFIsAuto)
   {
      int autoTf = ResolveAutoHTFPeriod();
      if(autoTf > (int)Period()) return autoTf;
      return 0;   // MN1: nothing above → HTF hidden
   }
   return g_HTFPeriod;
}

//+------------------------------------------------------------------+
//| Scheduled close time of the HTF bar that opened at `ot`.          |
//+------------------------------------------------------------------+
datetime HTFBarCloseTime(const datetime ot, const int tf)
{
   if(tf == PERIOD_MN1)
   {
      int y = TimeYear(ot), m = TimeMonth(ot) + 1;
      if(m > 12) { m = 1; y++; }
      return StringToTime(StringFormat("%04d.%02d.01 00:00", y, m));
   }
   return ot + tf * 60;   // tf is minutes
}

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

   ObjectsDeleteAll(0, g_HTFPrefix);
   g_HTFDrawnCount = 0;   // nothing of ours is on the chart any more
}

//+------------------------------------------------------------------+
//| Delete HTF objects for history indices [from,to) — used to prune |
//| only the trailing tail after an in-place redraw shrinks, instead |
//| of a full delete+recreate (no flicker, no drag-freeze).          |
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
   }
}

//+------------------------------------------------------------------+
//| Draw a single wick segment                                       |
//+------------------------------------------------------------------+
void DrawHTFWickSegment(const string name, const datetime t,
                        const double p1, const double p2, const color clr)
{
   // P-PERF-02: same write-only-what-changed rule as HTFRectUpsert (a wick is
   // a trend line whose two prices move with the live candle).
   bool onChart = (ObjectFind(0, name) >= 0);
   if(!onChart)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t, p1, t, p2)) return;
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, g_HTFWickWidth);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      CacheUpdateZone(name, p1, p2, t, t, clr, false, (int)STYLE_SOLID, g_HTFWickWidth);
      return;
   }

   SObjectCacheEntry e;
   bool known = CacheGetObject(name, e) && e.exists;
   if(known) {
      if(e.lastTime1 != t)  ObjectSetInteger(0, name, OBJPROP_TIME1, t);
      if(e.lastTime2 != t)  ObjectSetInteger(0, name, OBJPROP_TIME2, t);
      if(e.lastPrice != p1) ObjectSetDouble(0, name, OBJPROP_PRICE1, p1);
      if(e.lastPrice2 != p2) ObjectSetDouble(0, name, OBJPROP_PRICE2, p2);
      if(e.lastColor != clr) ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   } else {
      ObjectSetInteger(0, name, OBJPROP_TIME1, t);
      ObjectSetDouble(0, name, OBJPROP_PRICE1, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME2, t);
      ObjectSetDouble(0, name, OBJPROP_PRICE2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, g_HTFWickWidth);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   CacheUpdateZone(name, p1, p2, t, t, clr, false, (int)STYLE_SOLID, g_HTFWickWidth);
}

//+------------------------------------------------------------------+
//| Draw HTF Candle Core                                             |
//+------------------------------------------------------------------+
void DrawHTFCandleCore(const int i, const datetime ot, const datetime nt,
                       const double hi, const double lo,
                       const double op, const double cl)
{
   double bodyHi = g_HTFShowWicks ? MathMax(op, cl) : hi;
   double bodyLo = g_HTFShowWicks ? MathMin(op, cl) : lo;

   double opct = g_HTFOpacity / 100.0;
   color candleClr = BlendWithBackground(cl >= op ? g_HTFBullColor : g_HTFBearColor, opct);
   color wickClr   = BlendWithBackground(g_HTFWickColor, opct);
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
      datetime wt = ot + (datetime)((nt - ot) / 2);
      string upName = g_HTFPrefix + "WU" + wickId;
      string dnName = g_HTFPrefix + "WL" + wickId;
      if(hi > bodyHi) DrawHTFWickSegment(upName, wt, bodyHi, hi, wickClr);
      else            ObjectDelete(0, upName);
      if(lo < bodyLo) DrawHTFWickSegment(dnName, wt, lo, bodyLo, wickClr);
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
      HTFRectUpsert(baseName, ot, bodyHi, nt, bodyLo,
                    BlendWithBackground(bodyBase, HTF_FILL_STRONG), 1, true, true);
   }
   else if(g_HTFBoxMode == HTF_BOX_BOTH)
   {
      HTFRectUpsert(baseName + "_F", ot, bodyHi, nt, bodyLo,
                    BlendWithBackground(bodyBase, HTF_FILL_FAINT), 1, true, true);
      HTFRectUpsert(baseName + "_B", ot, bodyHi, nt, bodyLo,
                    borderClr, g_HTFBorderWidth, false, false);
   }
   else
   {
      HTFRectUpsert(baseName, ot, bodyHi, nt, bodyLo,
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
   if(tf <= 0 || tf <= Period()) return false;

   datetime ot = iTime(_Symbol, tf, 0);
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

   double op = iOpen(_Symbol, tf, 0), cl = iClose(_Symbol, tf, 0);
   double hi = iHigh(_Symbol, tf, 0),  lo = iLow(_Symbol, tf, 0);
   if(hi <= 0 || lo <= 0) return false;

   if(!formNewBar &&
      op == g_HTFLastFormO && hi == g_HTFLastFormH &&
      lo == g_HTFLastFormL && cl == g_HTFLastFormC) return false;

   g_HTFFormWriteMs = formNow;

   g_HTFLastFormOpen = ot;
   g_HTFLastFormO = op; g_HTFLastFormH = hi;
   g_HTFLastFormL = lo; g_HTFLastFormC = cl;

   HTFRefreshBlendBackground();   // P-PERF-08: once per draw pass, not once per colour
   DrawHTFCandleCore(0, ot, HTFBarCloseTime(ot, tf), hi, lo, op, cl);
   return true;
}

//+------------------------------------------------------------------+
//| Redraw all historical HTF candles (IN-PLACE, no flicker)         |
//| Returns bars drawn (>=0), or -1 when HTF history is not ready yet|
//| (weak PC / fresh TF-switch) so the caller retries later instead  |
//| of leaving an empty chart. Same-index objects are upserted in     |
//| place — only a shrunken tail is pruned and only a box/shape flip  |
//| wipes all (slider drags recolor without delete+recreate churn).  |
//+------------------------------------------------------------------+
// How many HTF bars does the CURRENT viewport actually need? Everything
// further left than the visible range + headroom cannot be seen.
int HTFViewportBarTarget()
{
   int want = InpHTFMaxBars;
   int htf = ResolveHTFPeriod();
   int chartTf = (int)Period();
   if(htf > chartTf && chartTf > 0)
   {
      int firstVis = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0);
      int visBars  = (int)ChartGetInteger(0, CHART_VISIBLE_BARS, 0);
      if(firstVis < 0) firstVis = 0;
      if(visBars < 1)  visBars = 1;
      double ratio = (double)htf / (double)chartTf;
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
bool HTFRangeStale()
{
   if(g_HTFDrawnCount <= 0) return false;
   static uint s_rangeMs = 0;
   uint nowMs = GetTickCount();
   if(s_rangeMs != 0 && nowMs - s_rangeMs < HTF_RANGE_MS) return false;
   s_rangeMs = nowMs;
   int viewTarget = HTFViewportBarTarget();
   return (viewTarget > g_HTFDrawnCount || viewTarget + HTF_CULL_HYST < g_HTFDrawnCount);
}

int DrawHTFCandles()
{
   static int s_prevCount = 0;
   if(!g_UI.showHTF || Bars < 2) { DeleteHTFCandles(); s_prevCount = 0; return 0; }
   int tf = ResolveHTFPeriod();
   if(tf <= 0 || tf <= Period()) { DeleteHTFCandles(); s_prevCount = 0; return 0; }
   HTFRefreshBlendBackground();   // P-PERF-08: one background read for the whole pass
   int total = iBars(_Symbol, tf);
   if(total <= 0) return -1;
   datetime ot0 = iTime(_Symbol, tf, 0);
   if(ot0 <= 0) return -1;
   int count = MathMin(InpHTFMaxBars, total);
   // P-PERF-02 viewport cap (hysteresis keeps a zoom-out/zoom-in see-saw from
   // re-creating bars it just pruned).
   int viewTarget = HTFViewportBarTarget();
   if(count > viewTarget) count = MathMin(count, viewTarget + HTF_CULL_HYST);
   g_HTFDrawnCount = count;

   static int s_lastBoxMode = -1;
   static bool s_lastShowBodyBox = false;
   if(s_lastBoxMode != g_HTFBoxMode || s_lastShowBodyBox != g_HTFShowBody)
   {
      DeleteHTFCandles();
      s_prevCount = 0;
      s_lastBoxMode = g_HTFBoxMode;
      s_lastShowBodyBox = g_HTFShowBody;
   }
   for(int i = 0; i < count; i++)
   {
      datetime ot = iTime(_Symbol, tf, i);
      datetime nt = (i == 0) ? HTFBarCloseTime(ot, tf) : iTime(_Symbol, tf, i - 1);
      if(ot <= 0 || nt <= ot)
      {
         if(i == 0) return -1;
         continue;
      }
      double hi = iHigh(_Symbol, tf, i), lo = iLow(_Symbol, tf, i);
      double op = iOpen(_Symbol, tf, i), cl = iClose(_Symbol, tf, i);
      if(hi <= 0 || lo <= 0)
      {
         if(i == 0) return -1;
         continue;
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

   // By design there is nothing above the chart TF (MN1 auto, or a manual
   // TF<=chart): make sure no stale boxes linger, once.
   if(tf <= (int)Period())   // covers tf==0 (auto on MN1) too
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
   if(Bars < 2 || iBars(_Symbol, tf) <= 0 || iTime(_Symbol, tf, 0) <= 0)
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

//+------------------------------------------------------------------+
//| Initialize HTF Candles                                           |
//+------------------------------------------------------------------+
void InitializeHTFCandles()
{
   g_HTFPrefix = HTF_PREFIX_BASE + IntegerToString(ChartID()) + "_";
   g_HTFBullColor = InpHTFBullColor;
   g_HTFBearColor = InpHTFBearColor;
   g_HTFWickColor = InpHTFWickColor;
   g_HTFBorderColor = InpHTFBorderColor;
   g_HTFOpacity = InpHTFOpacity;
   g_HTFShowWicks = InpHTFShowWicks;
   g_HTFWickWidth = InpHTFWickWidth;
   g_HTFBorderWidth = InpHTFBorderWidth;
   g_HTFBoxMode = InpHTFBoxMode;
   g_HTFShowBody = InpHTFShowBody;
   
   string chartIdStr = GetCachedChartIdStr();
   string prefix = "Biotak_HTF_" + chartIdStr + "_";

   g_HTFIsAuto = true;
   g_HTFPeriod = PERIOD_H4;
   if(GlobalVariableCheck(prefix + "IsAuto")) g_HTFIsAuto = (GlobalVariableGet(prefix + "IsAuto") > 0.5);
   if(GlobalVariableCheck(prefix + "Period"))
   {
      int savedTf = (int)GlobalVariableGet(prefix + "Period");
      if(savedTf > 0) g_HTFPeriod = savedTf;
   }

   if(GlobalVariableCheck(prefix + "BullColor"))   g_HTFBullColor   = (color)(int)GlobalVariableGet(prefix + "BullColor");
   if(GlobalVariableCheck(prefix + "BearColor"))   g_HTFBearColor   = (color)(int)GlobalVariableGet(prefix + "BearColor");
   if(GlobalVariableCheck(prefix + "WickColor"))   g_HTFWickColor   = (color)(int)GlobalVariableGet(prefix + "WickColor");
   if(GlobalVariableCheck(prefix + "BorderColor")) g_HTFBorderColor = (color)(int)GlobalVariableGet(prefix + "BorderColor");
   if(GlobalVariableCheck(prefix + "Opacity"))     g_HTFOpacity     = (int)GlobalVariableGet(prefix + "Opacity");
   if(GlobalVariableCheck(prefix + "ShowWicks"))   g_HTFShowWicks   = (GlobalVariableGet(prefix + "ShowWicks") > 0.5);
   if(GlobalVariableCheck(prefix + "WickWidth"))   g_HTFWickWidth   = (int)GlobalVariableGet(prefix + "WickWidth");
   if(GlobalVariableCheck(prefix + "BorderWidth")) g_HTFBorderWidth = (int)GlobalVariableGet(prefix + "BorderWidth");
   if(GlobalVariableCheck(prefix + "BoxMode"))     g_HTFBoxMode     = (int)GlobalVariableGet(prefix + "BoxMode");
   if(GlobalVariableCheck(prefix + "ShowBody"))    g_HTFShowBody    = (GlobalVariableGet(prefix + "ShowBody") > 0.5);

   if(g_HTFIsAuto) g_HTFPeriod = ResolveAutoHTFPeriod();
   else if(g_HTFPeriod <= 0) { g_HTFIsAuto = true; g_HTFPeriod = ResolveAutoHTFPeriod(); }

   g_HTFLastFormOpen = 0;
   g_HTFLastFormO = 0; g_HTFLastFormH = 0;
   g_HTFLastFormL = 0; g_HTFLastFormC = 0;
   HTFRefreshBlendBackground();   // P-PERF-08: seed the blend cache
}

//+------------------------------------------------------------------+
//| Save HTF Candles Settings                                        |
//+------------------------------------------------------------------+
void SaveHTFCandlesSettings()
{
   string chartIdStr = GetCachedChartIdStr();
   string prefix = "Biotak_HTF_" + chartIdStr + "_";
   GlobalVariableSet(prefix + "IsAuto",      g_HTFIsAuto ? 1.0 : 0.0);
   GlobalVariableSet(prefix + "Period",      (double)g_HTFPeriod);
   GlobalVariableSet(prefix + "BullColor",   (double)g_HTFBullColor);
   GlobalVariableSet(prefix + "BearColor",   (double)g_HTFBearColor);
   GlobalVariableSet(prefix + "WickColor",   (double)g_HTFWickColor);
   GlobalVariableSet(prefix + "BorderColor", (double)g_HTFBorderColor);
   GlobalVariableSet(prefix + "Opacity",     (double)g_HTFOpacity);
   GlobalVariableSet(prefix + "ShowWicks",   g_HTFShowWicks ? 1.0 : 0.0);
   GlobalVariableSet(prefix + "WickWidth",   (double)g_HTFWickWidth);
   GlobalVariableSet(prefix + "BorderWidth", (double)g_HTFBorderWidth);
   GlobalVariableSet(prefix + "BoxMode",     (double)g_HTFBoxMode);
   GlobalVariableSet(prefix + "ShowBody",    g_HTFShowBody ? 1.0 : 0.0);
}

//+------------------------------------------------------------------+
//| Cleanup HTF Candles GlobalVariables                              |
//+------------------------------------------------------------------+
void CleanupHTFCandlesGVs()
{
   string chartIdStr = GetCachedChartIdStr();
   string prefix = "Biotak_HTF_" + chartIdStr + "_";
   GlobalVariableDel(prefix + "IsAuto");
   GlobalVariableDel(prefix + "Period");
   GlobalVariableDel(prefix + "BullColor");
   GlobalVariableDel(prefix + "BearColor");
   GlobalVariableDel(prefix + "WickColor");
   GlobalVariableDel(prefix + "BorderColor");
   GlobalVariableDel(prefix + "Opacity");
   GlobalVariableDel(prefix + "ShowWicks");
   GlobalVariableDel(prefix + "WickWidth");
   GlobalVariableDel(prefix + "BorderWidth");
   GlobalVariableDel(prefix + "BoxMode");
   GlobalVariableDel(prefix + "ShowBody");
}

#endif // HTF_CANDLES_MQH
