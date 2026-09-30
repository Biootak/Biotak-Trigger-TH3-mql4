//+------------------------------------------------------------------+
//|                                        HTFCandles_Geom.mqh      |
//|                                                                  |
//| P-HTF-SPLIT (2026-09-30): the overlay was ONE 1519-line file —    |
//| the contract's ceiling is 1500 — and it carried four owners.      |
//| HTFCandles.mqh is the HUB now and includes three parts, same      |
//| public names, same output, byte-identical geometry:              |
//|                                                                  |
//|   HTFCandles_Geom.mqh      THIS file: state, the TF ladder, the   |
//|                            index map and the candle's SHAPE       |
//|   HTFCandles_Draw.mqh      the chart's objects: upsert, cull,     |
//|                            prune, the draw passes                 |
//|   HTFCandles_Life.mqh      birth (init), the saved keys, cleanup  |
//|                                                                  |
//| Include order IS ownership (MQL4 has no forward declaration), so  |
//| the hub includes Geom -> Draw -> Life: the order these           |
//| declarations stood in when they were one file.                    |
//+------------------------------------------------------------------+
#ifndef HTF_CANDLES_GEOM_MQH
#define HTF_CANDLES_GEOM_MQH

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

// P-UI-92: the TIMEFRAME dropdown has two KINDS of entry. STRUCTURE/PATTERN
// are DYNAMIC — they follow the chart TF, so a TF switch moves the overlay —
// and FIXED is a period the user picked by name. The panel maps option index
// -> mode, this file owns what each rung MEANS, and nothing else may answer
// that question (the two names mirror the Factor card's BASIS entries).
#define HTF_TF_STRUCTURE 0   // 16x current TF — the shipped "Auto" (two fractal steps up)
#define HTF_TF_PATTERN   1   //  4x current TF — one fractal step up
#define HTF_TF_FIXED     2   // g_HTFPeriod, straight off the dropdown's ladder

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
static int    g_HTFPeriod = 240;   // R-TF-UNIT: minutes (H4), not PERIOD_H4
static int    g_HTFTfMode = HTF_TF_STRUCTURE;   // P-UI-92: was the bool g_HTFIsAuto
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
static int    InpHTFTimeframe = 240;   // R-TF-UNIT: minutes (H4), not PERIOD_H4
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
//| SNAP a raw minute count to the nearest standard timeframe.        |
//|                                                                  |
//| WHY THIS REPLACED A 9-CASE SWITCH (P-UI-92). The overlay needs TWO|
//| rungs of the SAME ladder now — STRUCTURE (16x) and PATTERN (4x) —   |
//| and a second hand-written case table is the P-ARCH-01 duplicate     |
//| waiting to drift from the first. One table, one rule, both rungs    |
//| read it. The retired switch's answers are reproduced EXACTLY (M1   |
//| M15, M5 H1, M15 H4, M30 H4, H1 D1, H4 W1, D1 MN1, W1 MN1) and the |
//| PATTERN column is the same rule one step lower (M1 M5, M5 M15, M15 |
//| H1, M30 H1, H1 H4, H4 D1, D1 W1, W1 MN1). NEAREST, not ceiling:    |
//| `GetStructureTimeframe()`/`GetPatternTimeframe()` in               |
//| ExtendedDrawingFunctions.mqh round UP (16x M1 = 16 → M30, 16x M5 = |
//| 80 → H4), which is their own contract for the Factor card's BASIS  |
//| — NOT this overlay's, whose rung has been nearest-snapped since    |
//| P-HTF-01. Ties (nothing is closer) resolve DOWN, so a rung can     |
//| never jump over its own neighbour: M30 x4 = 120 sits exactly       |
//| between H1 and H4 → H1, one step up, not H4 (the 8x structure rung)|.
//| Nothing above MN1 has a candidate, so MN1 itself is returned and   |
//| the callers' `> Period()` gate does the hiding.                    |
//+------------------------------------------------------------------+
int HTFSnapTf(const int mins)
{
   // R-TF-UNIT: the ladder is in MINUTES, which is what `mins` is - and what
   // every caller compares the result against (`rung > Period()`,
   // `tf <= Period()`, `g_HTFPeriod`). On MT4 the PERIOD_* constants held these
   // same numbers, so writing them as constants read as minutes by accident.
   // On MT5 they hold 1/5/15/30/16385/16388/16408/32769/49153, so every rung
   // above M30 was snapped against a nonsense distance: an H1 chart asked for a
   // 960-minute rung and got MN1 instead of H4, and the overlay then hid itself
   // behind the `rung > Period()` gate. Written as minutes the ladder means on
   // MT5 exactly what it has always meant on MT4.
   static int ladder[9] = {1, 5, 15, 30, 60, 240, 1440, 10080, 43200};
   if(mins <= ladder[0]) return ladder[0];
   int    best  = ladder[8];
   double bestD = 1e18;
   for(int i = 0; i < 9; i++)
   {
      double d = MathAbs(MathLog((double)mins / (double)ladder[i]));
      if(d < bestD) { bestD = d; best = ladder[i]; }   // strict < : ties go DOWN
   }
   return best;
}

//| STRUCTURE rung — the shipped "Auto": 16x, two fractal steps up    |
int ResolveAutoHTFPeriod() { return HTFSnapTf((int)Period() * 16); }

//| PATTERN rung — one fractal step up (4x)                          |
int ResolvePatternHTFPeriod() { return HTFSnapTf((int)Period() * 4); }

//| Is the dropdown on a DYNAMIC entry (one that follows the chart)?  |
bool HTFTfIsDynamic() { return (g_HTFTfMode <= HTF_TF_PATTERN); }

//| The rung itself, UNGATED (what the badge mirrors).                |
int HTFResolveRung()
{
   return (g_HTFTfMode == HTF_TF_PATTERN) ? ResolvePatternHTFPeriod()
                                          : ResolveAutoHTFPeriod();
}

//| Mode name, for the ring tooltip ("ON · Pattern · H4").            |
string HTFTfModeName()
{
   if(g_HTFTfMode == HTF_TF_PATTERN)   return "Pattern";
   if(g_HTFTfMode == HTF_TF_STRUCTURE) return "Structure";
   return "";   // fixed TF: the badge's own label already names it
}

//+------------------------------------------------------------------+
//| Effective HTF period: a DYNAMIC rung is recomputed from the       |
//| chart TF every call (that is what makes a TF switch move it —     |
//| P-HTF-02), a FIXED one is the user's period, and nothing above the|
//| chart TF exists so the overlay hides ("").                        |
//+------------------------------------------------------------------+
int ResolveHTFPeriod()
{
   if(!HTFTfIsDynamic()) return g_HTFPeriod;
   int rung = HTFResolveRung();
   if(rung > (int)Period()) return rung;
   return 0;   // MN1: nothing above → HTF hidden
}

//+------------------------------------------------------------------+
//| Scheduled close time of the HTF bar that opened at `ot`.          |
//+------------------------------------------------------------------+
datetime HTFBarCloseTime(const datetime ot, const int tf)
{
   if(tf == 43200)   // R-TF-UNIT: MN1 in minutes; `tf` is a minute count
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
//| i.e. roughly 70% across: the shadow is off-centre and the candle   |
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
   int i = iBarShift(_Symbol, CompatTF(p), t, false);
   // P-UI-85 — A TIME NEWER THAN BAR 0 IS NEVER BELIEVED FROM iBarShift.
   //
   // `iBarShift(..., false)` answers with the NEAREST bar whenever the exact
   // time is not a bar open, and for a FUTURE time the nearest bar IS bar 0.
   // The forming HTF candle's scheduled close (`HTFBarCloseTime`, i.e. a time
   // that has not happened yet) therefore came back as index 0 and the candle
   // measured its period as "the elapsed bars" instead of ONE FULL SLOT: the
   // live candle was drawn over the elapsed part only — visibly narrower than
   // every closed candle beside it, which is the report («این کندل لایو اندازه
   // کندل مثل بقیه باشه که بفهم کجای کندل لایو هستیم»). The old code only
   // extrapolated in its `i < 0` branch, so the fix depended on the terminal's
   // dictionary (`-1` on some builds, `0` on others). Now the ANSWER cannot
   // decide it: `i <= 0` is resolved from the bar PITCH whenever the time is
   // newer than bar 0, which is exactly how the terminal itself lays out a
   // future time. One canonical form for "inside bar 0's slot" and for
   // "after it", so the live candle's slot — and therefore its body, its
   // shadow and its gap — measures one full period like every closed candle.
   //
   // COST: the historical path is byte-identical (i > 0 never enters here). The
   // live candle now costs two iTime + one divide instead of an iBarShift plus
   // the same two iTime — the hottest caller (`HTFChartIndexAt(nt)` on every
   // forming-candle update) gets CHEAPER, and the memo below still bounds the
   // conversion to one per distinct time per pass.
   if(i <= 0)
   {
      datetime t0 = iTime(_Symbol, p, 0);
      datetime t1 = iTime(_Symbol, p, 1);
      idx = (t0 > 0 && t1 > 0 && t0 > t1 && t > t0)
            ? -(double)(t - t0) / (double)(t0 - t1)
            : (i < 0 ? Bars - 1 : 0);   // -1 = older than the oldest loaded bar
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

//+------------------------------------------------------------------+
//| P-HTF-SLOT (2026-09-30) — THE HIGH RUNGS ARE DRAWN AT A READABLE  |
//| PITCH.                                                            |
//|                                                                  |
//| THE REPORT, in numbers. With W1 (10080) or MN1 (43200) selected   |
//| on a chart far below them, the overlay paints no candle at all:   |
//| one MN1 bar on an M5 chart is 43200/5 = 8640 chart bars, and a    |
//| ~300-bar window fits 3.5% of ONE candle. Its body's two edges and |
//| its shadow's two edges — all four sit outside the window, so the  |
//| screen carries only the horizontal strips of a box 28.8 windows   |
//| wide. That strip is the look the report calls "not real".         |
//|                                                                  |
//| THE TRICK. The VALUES stay real — iHigh/iLow/iOpen/iClose of the  |
//| terminal-built HTF series, i.e. the real weekly/monthly OHLC —    |
//| and the WIDTH becomes the chart's own zoom: a slot of              |
//| `visBars / HTF_SLOT_MIN_CANDLES` chart bars, so at least four      |
//| candles of the rung are on screen at any zoom. The grid is         |
//| anchored at the chart's right edge (index 0 = bar 0 = now), never  |
//| at the scheduled close: a future time is laid out in the right     |
//| margin, so anchoring there would move the whole strip off-screen.  |
//|                                                                  |
//| THE SHAPE IS NOT A SECOND LAW. The slot's two edges are times like |
//| any other — HTFCandleGeometry turns them into body/shadow/gap with |
//| the SAME gap%, shadow% and pixel floor the real rungs use, so a    |
//| slotted candle is the rung's own candle, only narrower.            |
//|                                                                  |
//| SCOPE — every rung that reads today stays byte-identical. The      |
//| decision is the CALENDAR ratio, taken BEFORE any series read:      |
//| `htf/chartTf <= slot` returns with the true geometry, and the true  |
//| drawn pitch is never WIDER than the calendar ratio (a week holds    |
//| 5 trading days, not 7), so that early return can only under-        |
//| compress — it can never slot a rung whose candles were readable.    |
//|                                                                  |
//| COST. One `ChartGetInteger(CHART_VISIBLE_BARS)` per call, and one   |
//| call per draw pass plus the 100 ms viewport probe that already owns  |
//| the zoom numbers: zero series reads, zero writes, no new walk. On a  |
//| slotted rung each candle's two synthetic edges cost one index round-  |
//| trip each (they are not series times, so the memo cannot serve them), |
//| bounded by the drawn count the viewport cap already states. A candle  |
//| that is not drawing costs nothing.                                   |
//|                                                                      |
//| WHAT THE USER SEES (honest, one line): price is real and the shape is |
//| the rung's own law; the x pitch is SCHEMATIC — equal slots, not equal  |
//| calendar months — and the strip is anchored to the live edge, so it    |
//| follows "now" rather than a panned-away window.                        |
//|                                                                       |
//| RETIRED (2026-09-30, kept per the request): until this change the      |
//| answer for exactly these rungs was HTFGeomCalendarShadow applied per   |
//| candle — two coordinates the terminal could not place inside the       |
//| window, clamped to the oldest loaded bar, which is what painted the     |
//| 28-window-wide strips. That function is no longer the answer for a      |
//| period wider than the window; it stays as the LAST fence (a non-finite  |
//| index, a degenerate round trip), because a fence may degrade to the     |
//| previous look but never to nothing (Touch rule 4).                      |
//+------------------------------------------------------------------+
#define HTF_SLOT_MIN_CANDLES 4   // the fewest candles that read as a sequence
static double s_HTFSlot   = 0.0;   // chart-bar index units per candle (0 = true geometry)
static int    s_HTFVisBars = 0;    // the zoom both the pitch and its probe read

// P-HTF-PROBE (2026-09-30, Touch rule 5): the pitch is the number this defect is
// judged by, so it is on the record whenever it MOVES (a zoom, a rung switch) and
// silent in the steady state — two compares and an int. `ratio` is the calendar
// pitch in chart bars: the measured report was htf=43200 chart=5 (ratio 8640)
// with vis~300, i.e. 28.8 windows per candle.
void HTFProbeSlot(const int htf)
{
   static double s_lastSlot = -1.0;
   static int    s_lastHtf  = -1;
   static int    s_lastVis  = -1;
   if(s_HTFSlot == s_lastSlot && htf == s_lastHtf && s_HTFVisBars == s_lastVis) return;
   s_lastSlot = s_HTFSlot;
   s_lastHtf  = htf;
   s_lastVis  = s_HTFVisBars;
   int chartTf = (int)Period();
   Print("[P-HTF] slot htf=", htf, " chart=", chartTf, " vis=", s_HTFVisBars,
         " ratio=", DoubleToString((chartTf > 0) ? (double)htf / (double)chartTf : 0.0, 1),
         " slot=", DoubleToString(s_HTFSlot, 1), " drawn=", g_HTFDrawnCount);
}

// Fill s_HTFSlot for this pass. 0 = true geometry (the rung's candles already fit
// the window at least HTF_SLOT_MIN_CANDLES times); > 0 = the slot pitch.
void HTFRefreshSlotMetrics(const int htf)
{
   s_HTFSlot = 0.0;
   int chartTf = (int)Period();
   s_HTFVisBars = (chartTf > 0) ? (int)ChartGetInteger(0, CHART_VISIBLE_BARS, 0) : 0;
   if(s_HTFVisBars < 2) s_HTFVisBars = 0;
   if(chartTf > 0 && htf > chartTf && s_HTFVisBars > 0)
   {
      double slot = (double)s_HTFVisBars / (double)HTF_SLOT_MIN_CANDLES;
      if(slot < 2.0) slot = 2.0;   // HTFCandleGeometry's own fence needs a two-bar span
      if((double)htf / (double)chartTf > slot) s_HTFSlot = slot;
   }
   HTFProbeSlot(htf);
}

// The candle's two edges on the slot grid. Index convention is HTFChartIndexAt's:
// 0 = bar 0, +1 per bar OLDER, so a candle's RIGHT edge is the smaller index and
// the newest candle (i = 0) owns the last `slot` bars. Callers pass COPIES of
// (ot, nt): the true `ot` is the candle's identity for the live-edge cache
// (g_HTFLastFormOpen) and may not be replaced by a synthetic time.
void HTFSlotTimes(const int i, datetime &ot, datetime &nt)
{
   if(s_HTFSlot <= 0.0) return;              // true geometry: untouched
   double right = (double)i * s_HTFSlot;
   ot = HTFChartTimeAt(right + s_HTFSlot);   // older edge (left on the chart)
   nt = HTFChartTimeAt(right);               // newer edge (right on the chart)
}

// The shadow's calendar-share fallback, ONE owner — the LAST fence, not an answer
// (see the RETIRED note above). Two paths need it: a span the index map cannot
// centre on (thinner than two chart bars — beyond loaded history, a fresh TF
// switch — or non-finite) and a degenerate index round trip. Both used to inline
// the same six lines; a third copy is how they drift apart again.
void HTFGeomCalendarShadow(SHTFCandleGeom &g, const datetime ot, const datetime nt,
                           const int shPct)
{
   datetime halfCal = (datetime)((nt - ot) * (double)shPct / 200);
   if(halfCal < 1) halfCal = 1;
   g.shadowL = ot + (datetime)((nt - ot) / 2) + halfCal;
   g.shadowR = ot + (datetime)((nt - ot) / 2) - halfCal;
   if(g.shadowR < ot) g.shadowR = ot;
   if(g.shadowL > nt) g.shadowL = nt;
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
   if(!MathIsValidNumber(iL) || !MathIsValidNumber(iR))
   {
      // No index map at all (broken series): the calendar share still draws a
      // real box. A zero-width rectangle is INVISIBLE — the old trend wick
      // never was — so no fence here may leave a point.
      HTFGeomCalendarShadow(g, ot, nt, shPct);
      return g;
   }
   double span = iL - iR;
   if(span < 2.0)
   {
      // Thinner than two chart bars: beyond loaded history (low-TF chart with
      // an HTF overlay, fresh TF switch) the whole span maps onto one slot and
      // no centred box exists. Same answer as above — a real box, not a point.
      //
      // P-HTF-SLOT: this is no longer the shape a high rung's candle takes — a
      // rung wider than the window arrives here with a SLOT-wide span (>= 2 by
      // construction) and never falls onto the calendar. What still reaches it
      // is a chart too young to carry even one slot of bars, where the previous
      // look is the honest degrade.
      HTFGeomCalendarShadow(g, ot, nt, shPct);
      return g;
   }

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
      HTFGeomCalendarShadow(g, ot, nt, shPct);
   }
   if(g.shadowL > nt) g.shadowL = nt;
   if(g.shadowR < ot) g.shadowR = ot;
   return g;
}

#endif // HTF_CANDLES_GEOM_MQH
