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

//--- HTF CANDLE GEOMETRY (P-UI-68)
// A candle's SHAPE is three settings, not a drawing detail: how much of its
// period the BODY fills (SHADOW GAP), how wide the SHADOW box is relative to
// that body (SHADOW WIDTH) and the thinnest the shadow may ever get in pixels
// (SHADOW MIN, the old WICK WIDTH row — a floor, because a percentage width
// collapses to nothing on a zoomed-out chart). All three are RANGED, so a
// corrupt persisted value (a stale GV, a hand-edited one, a NaN) can never
// reach the geometry: see HTFCandleGeometry's clamp.
#define HTF_GAP_PCT_MIN     0
#define HTF_GAP_PCT_MAX     40
#define HTF_SHADOW_PCT_MIN  6
#define HTF_SHADOW_PCT_MAX  100
#define HTF_BODY_MAX_SHARE  0.80   // the gap may never eat more than 80% of a period

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
static color  g_HTFWickColor = clrNONE;   // P-UI-68: NONE = follow the candle's colour
static color  g_HTFBorderColor = clrNONE;
static int    g_HTFOpacity = 30;
static bool   g_HTFShowWicks = true;
static int    g_HTFWickWidth = 1;      // SHADOW MIN — pixel floor of the shadow box
static int    g_HTFGapPct = 8;         // free space between two candle bodies (%)
static int    g_HTFShadowPct = 30;     // shadow box width, % of the body
static int    g_HTFBorderWidth = 1;
static int    g_HTFBoxMode = HTF_BOX_HOLLOW;
static bool   g_HTFShowBody = true;

// Default inputs
static int    InpHTFMaxBars = 200;
static int    InpHTFAutoMode = HTF_AUTO_FRACTAL;
static int    InpHTFTimeframe = PERIOD_H4;
static color  InpHTFBullColor = C'66,200,155';
static color  InpHTFBearColor = C'255,100,124';
static color  InpHTFWickColor = clrNONE;   // P-UI-68: NONE = follow the candle's colour
static color  InpHTFBorderColor = clrNONE;
static int    InpHTFOpacity = 30;
static bool   InpHTFShowWicks = true;
static int    InpHTFWickWidth = 1;     // SHADOW MIN — pixel floor of the shadow box
static int    InpHTFGapPct = 8;        // SHADOW GAP default
static int    InpHTFShadowPct = 30;    // SHADOW WIDTH default
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
//| THE SHADOW'S X — the middle of the body AS THE TERMINAL DRAWS IT. |
//|                                                                  |
//| WHY (ot + nt) / 2 IS WRONG. MT4 maps a time to an x by finding    |
//| the two chart bars that BRACKET it and interpolating inside that  |
//| one slot (that is how a trend line typed as 12:30 lands between   |
//| the 12:00 and 13:00 bars). A CLOSED MARKET HAS NO BARS: the whole  |
//| weekend between Friday's close and Monday's open collapses into    |
//| ONE slot, exactly like any other single bar. Halving the CALENDAR  |
//| span therefore does not halve the DRAWN span — the calendar middle |
//| of a W1 candle (Thursday 12:00) sits ~3.5 trading days from the    |
//| left edge and only ~1.7 plus that one weekend slot from the right, |
//| i.e. roughly 70% across: the shadow is off-centre and the candle    |
//| reads lopsided. Measured on an H1 24/5 series: a W1 candle's shadow |
//| sat at 70%, the last D1 bar of the week at 97%, its H4 bar at 87% —  |
//| and a normal H4/D1 candle at exactly 50%, which is why only the      |
//| HIGH timeframes looked wrong (they are where a market gap falls      |
//| inside one candle; the same happens inside MN when a holiday does).  |
//|                                                                  |
//| The middle is therefore computed where it is DRAWN: in chart-bar   |
//| index space, where equal index distance IS equal pixel distance.   |
//| Index convention: 0 = bar 0, +1 per bar OLDER (further left), and  |
//| a negative index is a time newer than bar 0 (the forming candle's  |
//| scheduled close, which the terminal lays out at the last slot's    |
//| pitch). Fractional indices are exact both ways: the same fraction  |
//| the terminal computes from the time is the fraction we convert back|
//| to a time, so the shadow lands on the pixel centre and, on a       |
//| wickless-in-that-spot candle, nothing moves at all.                |
//|                                                                  |
//| Reads: one iBarShift + one iTime per DISTINCT time, memoised for   |
//| two slots — a history bar's `nt` is the previous bar's `ot`, so a  |
//| full pass converts each boundary once instead of twice (~3 series   |
//| reads per bar, same family as the loop's own iHigh/iLow/iOpen/iClose|
//| and only on a pass that already decided to draw; P-PERF-08's rule    |
//| is about CHART-PROPERTY reads inside the blend, which this is not).  |
//|                                                                  |
//| The memo is valid for ONE geometry snapshot, and something that     |
//| changes the snapshot changes EVERY index — a closed bar shifts them |
//| all by one, a timeframe switch rebuilds them — so the pass heads    |
//| (DrawHTFCandles, UpdateHTFFormingCandle) reset it: a memo may only   |
//| be believed inside the pass that built it.                          |
//+------------------------------------------------------------------+
#define HTF_MID_MEMO 2
static datetime s_midT[HTF_MID_MEMO];
static double   s_midIdx[HTF_MID_MEMO];
static int      s_midNext = 0;

void HTFMidMemoReset()
{
   for(int k = 0; k < HTF_MID_MEMO; k++) { s_midT[k] = 0; s_midIdx[k] = 0.0; }
   s_midNext = 0;
}

double HTFChartIndexAt(const datetime t)
{
   for(int k = 0; k < HTF_MID_MEMO; k++)
      if(t != 0 && s_midT[k] == t) return s_midIdx[k];

   int p = Period();
   double idx;
   int i = iBarShift(_Symbol, p, t, false);
   if(i < 0)
   {
      datetime t0 = iTime(_Symbol, p, 0);
      datetime t1 = iTime(_Symbol, p, 1);
      if(t0 > 0 && t > t0)
      {
         // Newer than the last bar: extend at the last slot's pitch, the way
         // the terminal lays out a future time.
         idx = (t1 > 0 && t0 > t1) ? -(double)(t - t0) / (double)(t0 - t1) : 0;
      }
      else
      {
         idx = Bars - 1;      // older than the oldest loaded bar
      }
   }
   else if(i == 0)
   {
      idx = 0;
   }
   else
   {
      datetime ti = iTime(_Symbol, p, i);      // bar that OPENS the slot holding t
      datetime tj = iTime(_Symbol, p, i - 1);  // the slot's other edge (one bar newer)
      idx = (ti > 0 && tj > ti) ? (double)i - (double)(t - ti) / (double)(tj - ti) : (double)i;
   }

   s_midT[s_midNext]  = t;
   s_midIdx[s_midNext] = idx;
   s_midNext = (s_midNext + 1) % HTF_MID_MEMO;
   return idx;
}

datetime HTFChartTimeAt(const double idx)
{
   int p = Period();
   datetime t0 = iTime(_Symbol, p, 0);
   if(idx <= 0)
   {
      datetime t1 = iTime(_Symbol, p, 1);
      if(t0 <= 0) return 0;
      if(t1 <= 0 || t0 <= t1) return t0;
      return t0 + (datetime)MathRound((-idx) * (double)(t0 - t1));
   }
   int i = (int)MathCeil(idx);
   if(i > Bars - 1) i = Bars - 1;
   if(i < 1) return t0;
   datetime ti = iTime(_Symbol, p, i);
   datetime tj = iTime(_Symbol, p, i - 1);
   if(ti <= 0 || tj <= ti) return ti;
   double f = (double)i - idx;                 // 0 at bar i, 1 at bar i-1
   return ti + (datetime)MathRound(f * (double)(tj - ti));
}

//+------------------------------------------------------------------+
//| P-UI-68 (2026-09-14): ONE OWNER FOR THE CANDLE'S SHAPE.           |
//|                                                                  |
//| The request was a screenshot: the candle's SHADOW is a small      |
//| FILLED BOX centred on the body — not a 1 px trend line — and the  |
//| body does not run edge to edge: neighbouring candles keep a gap    |
//| so two same-coloured bodies can never fuse into one blob. Both      |
//| numbers are SETTINGS (SHADOW GAP %, SHADOW WIDTH % of the body),    |
//| and both are fractions of the candle AS DRAWN.                     |
//|                                                                  |
//| WHY THE INDEX SPACE AND NOT THE CALENDAR. MT4 maps a time to an x  |
//| by bracketing it between two chart bars and interpolating inside    |
//| that one slot (that is how a trend line typed as 12:30 lands        |
//| between the 12:00 and 13:00 bars). A CLOSED MARKET HAS NO BARS: the  |
//| whole weekend between Friday's close and Monday's open collapses     |
//| into ONE slot, exactly like any other single bar. So "half the       |
//| calendar span" is NOT "half the drawn span": a W1 candle's calendar   |
//| middle lands ~70% across (measured on an H1 24/5 series: W1 70%, the  |
//| last D1 bar 97%, its H4 87% — while a normal H4/D1 candle sits at     |
//| exactly 50%, which is why only the HIGH timeframes ever looked        |
//| lopsided). The same trap applies to a gap or a shadow share measured  |
//| in calendar seconds: MN1/W1/D1 would get a shadow that is visibly      |
//| fatter (or thinner) than every other timeframe's.                    |
//|                                                                  |
//| So every edge is computed where it is DRAWN — in chart-bar index      |
//| space, where equal index distance IS equal pixel distance — and       |
//| converted back with HTFChartTimeAt. Index convention: 0 = bar 0,      |
//| +1 per bar OLDER (further left), negative = newer than bar 0.         |
//|                                                                      |
//| COST: two iBarShift + a handful of iTime per candle, all memoised      |
//| (HTF_MID_MEMO) for one geometry snapshot, and the pass heads reset     |
//| it — the same budget profile the mid-time fix already shipped. A       |
//| CANDLE THAT IS NOT DRAWING COSTS NOTHING: this function is only        |
//| reached from DrawHTFCandleCore.                                       |
//|                                                                       |
//| FRAGILITY FENCES (every one of them a real chart, not a hypothesis):  |
//|  * non-finite index (a NaN from a broken series) -> the calendar       |
//|    fallback below, so a candle can never be drawn from a NaN geometry; |
//|  * a period thinner than two chart bars (a fresh TF switch with three  |
//|    bars loaded, M1 charts) -> no inset, no narrower shadow: the        |
//|    calendar form, i.e. exactly the pre-P-UI-68 look;                   |
//|  * a collapsed round trip (both edges map to the same instant) -> the  |
//|    share is recomputed in calendar seconds, so the shadow is still     |
//|    drawn instead of silently vanishing;                               |
//|  * both settings are CLAMPED to their ranges here, not only at the UI  |
//|    edge, because a persisted GV from another build is not input.       |
//+------------------------------------------------------------------+
struct SHTFCandleGeom
{
   datetime bodyL, bodyR;      // body edges (period inset by SHADOW GAP)
   datetime shadowL, shadowR;  // shadow box edges (centred on the body)
};

//--- pass-scoped chart zoom, read at most twice per draw pass. The shadow's
//    pixel FLOOR is the one place a pixel quantity is needed, and 1 bar of
//    index space is not 1 px — CHART_VISIBLE_BARS is how many bars fit on the
//    chart, so CW/VB is the px pitch. Approximate by design (it ignores the
//    right-margin shift): it is a visibility floor, not geometry, and the
//    clamp below still bounds it by the body.
static double s_HTFPxPerBar = 0.0;

void HTFRefreshPixelMetrics()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int vb = (int)ChartGetInteger(0, CHART_VISIBLE_BARS, 0);
   s_HTFPxPerBar = (cw > 0 && vb > 0) ? (double)cw / (double)vb : 0.0;
   if(!MathIsValidNumber(s_HTFPxPerBar)) s_HTFPxPerBar = 0.0;
}

SHTFCandleGeom HTFCandleGeometry(const datetime ot, const datetime nt)
{
   SHTFCandleGeom g;
   // The calendar form is ALWAYS the fallback: it is what the candle looked
   // like before this change (body edge to edge, shadow in the calendar
   // middle), so every fence below degrades to the previous look rather than
   // to something new.
   g.bodyL = ot;
   g.bodyR = nt;
   g.shadowL = ot + (datetime)((nt - ot) / 2);
   g.shadowR = g.shadowL;
   if(ot <= 0 || nt <= ot) return g;

   int gapPct = (int)MathMax(HTF_GAP_PCT_MIN, MathMin(HTF_GAP_PCT_MAX, g_HTFGapPct));
   int shPct  = (int)MathMax(HTF_SHADOW_PCT_MIN, MathMin(HTF_SHADOW_PCT_MAX, g_HTFShadowPct));
   int floorPx = (int)MathMax(MIN_WIDTH, MathMin(MAX_WIDTH, g_HTFWickWidth));

   double iL = HTFChartIndexAt(ot);
   double iR = HTFChartIndexAt(nt);
   if(!MathIsValidNumber(iL) || !MathIsValidNumber(iR)) return g;   // NaN fence
   double span = iL - iR;
   if(span < 2.0) return g;                 // thinner than two chart bars

   double half = span / 2.0;
   double gap = span * (double)gapPct / 200.0;      // half of the gap, each side
   if(gap > half * HTF_BODY_MAX_SHARE) gap = half * HTF_BODY_MAX_SHARE;
   g.bodyL = HTFChartTimeAt(iL - gap);
   g.bodyR = HTFChartTimeAt(iR + gap);
   if(g.bodyL <= ot || g.bodyL >= nt) g.bodyL = ot;      // never trust the map
   if(g.bodyR >= nt || g.bodyR <= ot) g.bodyR = nt;
   if(g.bodyR <= g.bodyL) { g.bodyL = ot; g.bodyR = nt; }

   // The shadow: a share of the CANDLE (so it is proportional to what is on
   // screen), at least `floorPx` pixels thick when the zoom can be measured,
   // never wider than the body it sits on, and never below one chart bar.
   double halfShadow = span * (double)shPct / 200.0;
   if(s_HTFPxPerBar > 0.0)
   {
      double floorHalf = (double)floorPx / (2.0 * s_HTFPxPerBar);
      if(halfShadow < floorHalf) halfShadow = floorHalf;
   }
   double bodyHalf = ((iL - iR) - 2.0 * gap) / 2.0;
   if(bodyHalf <= 0.0) bodyHalf = half;
   if(halfShadow > bodyHalf) halfShadow = bodyHalf;
   if(halfShadow * 2.0 < 1.0) halfShadow = 0.5;    // never thinner than one bar

   double mid = (iL + iR) / 2.0;       // the middle AS DRAWN (P-UI-68's fix)
   g.shadowL = HTFChartTimeAt(mid + halfShadow);
   g.shadowR = HTFChartTimeAt(mid - halfShadow);
   if(g.shadowR <= g.shadowL || g.shadowL >= nt || g.shadowR <= ot)
   {
      // Degenerate round trip / the box fell outside the period: fall back to
      // the calendar share, so a shadow is always drawn.
      datetime halfCal = (datetime)((nt - ot) * (double)shPct / 200);
      if(halfCal < 1) halfCal = 1;
      g.shadowL = ot + (datetime)((nt - ot) / 2) + halfCal;
      g.shadowR = ot + (datetime)((nt - ot) / 2) - halfCal;
      if(g.shadowR < ot) g.shadowR = ot;
      if(g.shadowL > nt) g.shadowL = nt;
   }
   if(g.shadowL > nt) g.shadowL = nt;
   if(g.shadowR < ot) g.shadowR = ot;
   return g;
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
//| THE SHADOW BOX (P-UI-68)                                         |
//|                                                                  |
//| A wick used to be an OBJ_TREND of g_HTFWickWidth px. The request  |
//| is a BOX — the shape of the screenshot — so the shadow is now a   |
//| FILLED RECTANGLE whose x span is owned by HTFCandleGeometry (a    |
//| share of the candle, centred on the body) and whose look is        |
//| re-asserted, never written once, by the same guarded upsert the    |
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
   double bodyHi = g_HTFShowWicks ? MathMax(op, cl) : hi;
   double bodyLo = g_HTFShowWicks ? MathMin(op, cl) : lo;

   // ONE geometry for the whole candle: where the body starts and ends (the
   // SHADOW GAP inset) and where the shadow box sits (a share of the candle,
   // centred on the DRAWN middle). Nothing below recomputes an x by hand, so a
   // calendar midpoint cannot creep back into one of the three objects while
   // the others use the drawn one.
   SHTFCandleGeom gm = HTFCandleGeometry(ot, nt);

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

   HTFMidMemoReset();             // its own snapshot: a bar may have closed since the last pass
   HTFRefreshBlendBackground();   // P-PERF-08: once per draw pass, not once per colour
   HTFRefreshPixelMetrics();      // P-UI-68: the shadow's pixel floor needs the zoom once
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
   HTFMidMemoReset();             // one geometry snapshot per pass — see the memo
   HTFRefreshBlendBackground();   // P-PERF-08: one background read for the whole pass
   HTFRefreshPixelMetrics();      // P-UI-68: one zoom read for the whole pass too
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
   g_HTFGapPct = InpHTFGapPct;
   g_HTFShadowPct = InpHTFShadowPct;
   HTFRefreshPixelMetrics();   // the panel can open before the first draw pass
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
   // P-UI-68: the two geometry numbers are CLAMPED on the way in, not merely at
   // the UI edge — a chart saved by another build, or by a future one with a
   // wider range, must never be able to inject a gap that eats the body.
   if(GlobalVariableCheck(prefix + "GapPct"))
      g_HTFGapPct = (int)MathMax(HTF_GAP_PCT_MIN, MathMin(HTF_GAP_PCT_MAX, (int)GlobalVariableGet(prefix + "GapPct")));
   if(GlobalVariableCheck(prefix + "ShadowPct"))
      g_HTFShadowPct = (int)MathMax(HTF_SHADOW_PCT_MIN, MathMin(HTF_SHADOW_PCT_MAX, (int)GlobalVariableGet(prefix + "ShadowPct")));
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
   GlobalVariableSet(prefix + "GapPct",      (double)g_HTFGapPct);
   GlobalVariableSet(prefix + "ShadowPct",   (double)g_HTFShadowPct);
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
   GlobalVariableDel(prefix + "GapPct");
   GlobalVariableDel(prefix + "ShadowPct");
   GlobalVariableDel(prefix + "BorderWidth");
   GlobalVariableDel(prefix + "BoxMode");
   GlobalVariableDel(prefix + "ShowBody");
}

#endif // HTF_CANDLES_MQH
