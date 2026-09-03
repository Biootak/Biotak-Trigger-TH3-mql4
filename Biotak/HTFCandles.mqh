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

   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0);
   if(bg == 0) bg = clrBlack;

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
//+------------------------------------------------------------------+
void HTFRectUpsert(const string name, const datetime t1, const double p1,
                   const datetime t2, const double p2,
                   const color clr, const int width,
                   const bool fill, const bool back)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
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

//+------------------------------------------------------------------+
//| Delete all HTF candle objects                                    |
//+------------------------------------------------------------------+
void DeleteHTFCandles()
{
   int total = ObjectsTotal(0, 0, OBJ_RECTANGLE);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_RECTANGLE);
      if(StringFind(name, g_HTFPrefix) == 0) ObjectDelete(0, name);
   }
   int totalTr = ObjectsTotal(0, 0, OBJ_TREND);
   for(int i = totalTr - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_TREND);
      if(StringFind(name, g_HTFPrefix + "W") == 0) ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Draw a single wick segment                                       |
//+------------------------------------------------------------------+
void DrawHTFWickSegment(const string name, const datetime t,
                        const double p1, const double p2, const color clr)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t, p1, t, p2);
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
   int tf = g_HTFPeriod;
   if(tf <= Period()) return false;

   datetime ot = iTime(_Symbol, tf, 0);
   if(ot <= 0) return false;
   double op = iOpen(_Symbol, tf, 0), cl = iClose(_Symbol, tf, 0);
   double hi = iHigh(_Symbol, tf, 0),  lo = iLow(_Symbol, tf, 0);
   if(hi <= 0 || lo <= 0) return false;

   if(ot == g_HTFLastFormOpen &&
      op == g_HTFLastFormO && hi == g_HTFLastFormH &&
      lo == g_HTFLastFormL && cl == g_HTFLastFormC) return false;

   g_HTFLastFormOpen = ot;
   g_HTFLastFormO = op; g_HTFLastFormH = hi;
   g_HTFLastFormL = lo; g_HTFLastFormC = cl;

   DrawHTFCandleCore(0, ot, HTFBarCloseTime(ot, tf), hi, lo, op, cl);
   return true;
}

//+------------------------------------------------------------------+
//| Redraw all historical HTF candles                                |
//+------------------------------------------------------------------+
void DrawHTFCandles()
{
   if(!g_UI.showHTF || Bars < 2) { DeleteHTFCandles(); return; }
   int tf = g_HTFPeriod;
   if(tf <= Period()) { DeleteHTFCandles(); return; }
   int total = iBars(_Symbol, tf);
   if(total <= 0) return;
   int count = MathMin(InpHTFMaxBars, total);

   static int s_lastBoxMode = -1;
   static bool s_lastShowBodyBox = false;
   if(s_lastBoxMode != g_HTFBoxMode || s_lastShowBodyBox != g_HTFShowBody)
   {
      DeleteHTFCandles();
      s_lastBoxMode = g_HTFBoxMode;
      s_lastShowBodyBox = g_HTFShowBody;
   }
   for(int i = 0; i < count; i++)
   {
      datetime ot = iTime(_Symbol, tf, i);
      datetime nt = (i == 0) ? HTFBarCloseTime(ot, tf) : iTime(_Symbol, tf, i - 1);
      if(ot <= 0 || nt <= ot) continue;
      double hi = iHigh(_Symbol, tf, i), lo = iLow(_Symbol, tf, i);
      double op = iOpen(_Symbol, tf, i), cl = iClose(_Symbol, tf, i);
      if(hi <= 0 || lo <= 0) continue;

      DrawHTFCandleCore(i, ot, nt, hi, lo, op, cl);
   }
}

//+------------------------------------------------------------------+
//| Full refresh of HTF candles                                      |
//+------------------------------------------------------------------+
void RefreshHTFCandles()
{
   DeleteHTFCandles();
   DrawHTFCandles();
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
   
   g_HTFPeriod = ResolveHTFPeriod();
}

//+------------------------------------------------------------------+
//| Save HTF Candles Settings                                        |
//+------------------------------------------------------------------+
void SaveHTFCandlesSettings()
{
   string chartIdStr = GetCachedChartIdStr();
   string prefix = "Biotak_HTF_" + chartIdStr + "_";
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
