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
#define SESS_FILL_ALPHA  86    // % of the fill ink given up to the background
#define SESS_GHOST_ALPHA 62
#define SESS_PRIOR_ALPHA 55
#define SESS_MID_ALPHA   45
#define SESS_X_ALPHA     70
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
static double   s_sessLiveHi[SESS_SLOTS];
static double   s_sessLiveLo[SESS_SLOTS];

//--- countdown cache (boundary recomputes at a rebuild; text at ~1 Hz)
static datetime s_sessCdNext = 0;
static int      s_sessCdSlot = -1;
static bool     s_sessCdIsOpen = false;
static string   s_sessCdText = "";
static uint     s_sessCdMs = 0;

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

void SessRect(const string nm, const datetime t1, const double p1, const datetime t2, const double p2,
              const color borderC, const color fillC, const int width, const ENUM_LINE_STYLE style,
              const string tip)
{
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, borderC);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, fillC);
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
bool SessHiLoFor(const datetime t1, const datetime t2, double &hi, double &lo)
{
   hi = 0.0; lo = 0.0;
   if(t2 <= t1) return false;
   int bars = iBars(NULL, 0);
   if(bars <= 0) return false;
   int oldest = iBarShift(NULL, 0, t1, false);
   int newest = iBarShift(NULL, 0, t2, false);
   if(oldest < 0 || newest < 0) return false;
   if(oldest > bars - 1) oldest = bars - 1;
   if(newest > oldest) newest = oldest;
   int count = oldest - newest + 1;
   if(count < 1) return false;
   int iH = iHighest(NULL, 0, MODE_HIGH, count, newest);
   int iL = iLowest(NULL, 0, MODE_LOW, count, newest);
   if(iH < 0 || iL < 0) return false;
   hi = iHigh(NULL, 0, iH);
   lo = iLow(NULL, 0, iL);
   return (hi > 0.0 && lo > 0.0);
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

//--- rebuild trigger: settings, slots, master, hide (TF is NOT here:
//--- a timeframe switch must never repaint the family)
long SessViewHash()
{
   long h = 1181783497276652981;
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
   s_sessCdNext = 0;
   s_sessCdSlot = -1;
   s_sessCdIsOpen = false;
   s_sessCdText = "";
   s_sessCdMs = 0;
   for(int z = 0; z < SESS_SLOTS; z++)
      s_sessLiveValid[z] = false;

   datetime noon = SessServerNoon();
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
         if(wins[w].kk != 0 || wins[w].hasPrice) continue;
         if(SessWindowState(wins[w], now) != SESS_WS_LIVE) continue;
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
         color fillC = (s.style == SESS_STYLE_FILLED) ? SessBlend(base, SESS_FILL_ALPHA) : clrNONE;
         SessRect(nmB, wins[w].sU, wins[w].hi, wins[w].eU, wins[w].lo, base, fillC, 1, STYLE_SOLID, tip);
         SessText(nmB + "L", wins[w].sU, wins[w].hi, SessZoneTag(s.zone), base, SESS_PT_LBL,
                  ANCHOR_LEFT_UPPER, tip);
         if(s.style == SESS_STYLE_MID && wins[w].kk == 0)
         {
            double mid = (wins[w].hi + wins[w].lo) / 2.0;
            SessLine(nmB + "M", wins[w].sU, mid, wins[w].eU, mid, SessBlend(base, SESS_MID_ALPHA),
                     1, STYLE_DOT, tip + " · mid");
         }
         if(wins[w].kk == 0 && SessWindowState(wins[w], now) == SESS_WS_LIVE)
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
         //--- the live cache belongs to the WINDOW, not to the H/L lines:
         //--- the box extends per tick even when the lines are off
         if(wins[wLin].kk == 0 && SessWindowState(wins[wLin], now) == SESS_WS_LIVE)
         {
            s_sessLiveValid[sl] = true;
            s_sessLiveStamp[sl] = wins[wLin].stamp;
            s_sessLiveS[sl] = wins[wLin].sU;
            s_sessLiveE[sl] = wins[wLin].eU;
            s_sessLiveHi[sl] = wins[wLin].hi;
            s_sessLiveLo[sl] = wins[wLin].lo;
         }
         string tipL = SessWindowTip(s, wins[wLin].sU, wins[wLin].hi, wins[wLin].lo, true);
         if(g_sessHlLines)
         {
            string nmHI = SessWindowName(sl, wins[wLin].stamp, "HI");
            SessLine(nmHI,      wins[wLin].sU, wins[wLin].hi, wins[wLin].eU, wins[wLin].hi, base, 1, STYLE_SOLID, tipL);
            SessLine(SessWindowName(sl, wins[wLin].stamp, "LO"),
                     wins[wLin].sU, wins[wLin].lo, wins[wLin].eU, wins[wLin].lo, base, 1, STYLE_SOLID, tipL);
         }
         if(g_sessHlLabels)
         {
            SessText(SessWindowName(sl, wins[wLin].stamp, "HIL"), wins[wLin].eU, wins[wLin].hi,
                     DoubleToString(wins[wLin].hi, _Digits), base, SESS_PT_PRICE, ANCHOR_RIGHT_LOWER, tipL);
            SessText(SessWindowName(sl, wins[wLin].stamp, "LOL"), wins[wLin].eU, wins[wLin].lo,
                     DoubleToString(wins[wLin].lo, _Digits), base, SESS_PT_PRICE, ANCHOR_RIGHT_UPPER, tipL);
         }
         if(g_sessRangeText)
            SessText(SessWindowName(sl, wins[wLin].stamp, "R"), wins[wLin].eU, wins[wLin].lo,
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
         SessText(nmF + "L", wins[w].sU, bandHi[sl],
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
         SessText(nmC, s_sessCdNext, cdP, s_sessCdText, SESS_CD_COLOR, SESS_PT_PRICE,
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
   color base = SessColorOf(s.col);
   string nmB = SessWindowName(sl, s_sessLiveStamp[sl], "B");
   ObjectMove(0, nmB, 0, s_sessLiveS[sl], s_sessLiveHi[sl]);
   ObjectMove(0, nmB, 1, s_sessLiveE[sl], s_sessLiveLo[sl]);
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
      ObjectMove(0, SessWindowName(sl, s_sessLiveStamp[sl], "HIL"), 0, s_sessLiveE[sl], s_sessLiveHi[sl]);
      ObjectSetString(0, SessWindowName(sl, s_sessLiveStamp[sl], "LOL"), OBJPROP_TEXT,
                      DoubleToString(s_sessLiveLo[sl], _Digits));
      ObjectMove(0, SessWindowName(sl, s_sessLiveStamp[sl], "LOL"), 0, s_sessLiveE[sl], s_sessLiveLo[sl]);
   }
   if(g_sessRangeText)
   {
      ObjectSetString(0, SessWindowName(sl, s_sessLiveStamp[sl], "R"), OBJPROP_TEXT,
                      IntegerToString(SessPipsIn(s_sessLiveHi[sl], s_sessLiveLo[sl])) + "p");
      ObjectMove(0, SessWindowName(sl, s_sessLiveStamp[sl], "R"), 0, s_sessLiveE[sl], s_sessLiveLo[sl]);
   }
   ThrottledChartRedraw();
}

void SessLiveUpdate(const datetime now)
{
   for(int sl = 0; sl < SESS_SLOTS; sl++)
   {
      if(!s_sessLiveValid[sl]) continue;
      if(now < s_sessLiveS[sl] || now >= s_sessLiveE[sl]) continue;
      double h0 = iHigh(NULL, 0, 0);
      double l0 = iLow(NULL, 0, 0);
      if(h0 <= 0.0 || l0 <= 0.0) continue;
      if(h0 <= s_sessLiveHi[sl] && l0 >= s_sessLiveLo[sl]) continue;
      if(h0 > s_sessLiveHi[sl]) s_sessLiveHi[sl] = h0;
      if(l0 < s_sessLiveLo[sl]) s_sessLiveLo[sl] = l0;
      SessLiveRepaint(sl);
   }
}

//+------------------------------------------------------------------+
//| The tick (called from CoopPump's status job — 250 ms, both        |
//| entries). Order: want → state flips → rebuild-or-extend.          |
//+------------------------------------------------------------------+
void SessionsTick()
{
   if(StringLen(inpObjectPrefix) == 0) return;
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
         }
         ThrottledChartRedraw(true);
      }
      return;
   }

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
         int ds; datetime sU, eU;
         isOpen = SessWindowAt(now, s.startMin, s.endMin, s.days, s.zone, s.customMin,
                               true, 0, SDST_NONE, bkr, ds, sU, eU);
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
}

#endif // SESSIONS_DRAW_MQH
