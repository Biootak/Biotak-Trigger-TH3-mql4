//+------------------------------------------------------------------+
//|                                             Sessions_Model.mqh   |
//|                    Copyright 2026, Biotak Project                |
//|                                                                  |
//|  P-SESS — THE SESSION MODEL. Slot configs (packed codec), the     |
//|  factory presets, the zone-day window enumeration and the house    |
//|  colour table. No objects, no UI reads — the renderer asks, this   |
//|  module answers.                                                   |
//|                                                                  |
//|  WHY PACKED: a slot is 8 fields and the persistence layer is the   |
//|  terminal's own GlobalVariable table (doubles only). ONE double    |
//|  per slot, bit-packed under the 53-bit mantissa:                   |
//|    zone 4 · customOff+720 11 · start 11 · end 11 · days 7 ·        |
//|    style 2 · colour 3 · enable 1  =  50 bits.                      |
//|  A==0 decodes to the factory preset: a chart that never touched a  |
//|  slot IS the preset — no init pass, no migration stamp.            |
//|                                                                  |
//|  DEPENDENCIES (all included BEFORE this file in both entries):     |
//|    Sessions_Time.mqh  — the pure DST engine (P-SESS-01/02/03)      |
//|    Runtime_A.mqh      — g_sess* mirrors + SESS_SLOTS/SESS_* bounds |
//|    BasePrice_A.mqh    — ConvertServerToGMT, the single live        |
//|                         server<->GMT owner (never a second probe)  |
//+------------------------------------------------------------------+
#ifndef SESSIONS_MODEL_MQH
#define SESSIONS_MODEL_MQH

#include "Sessions_Time.mqh"

#define SESS_STYLE_FILLED  0
#define SESS_STYLE_OUTLINE 1
#define SESS_STYLE_MID     2

#define SESS_CUSTOM_OFF_LO (-720)   // -12:00, the western extreme worth offering
#define SESS_CUSTOM_OFF_HI (840)    // +14:00

//--- 8 curated session inks (mid-tone, legible over dark and light charts).
//--- The editor's colour chips are 3-bit indices into THIS table, so the
//--- look can be retuned without moving a persisted bit.
//--- P-SESS-06 (2026-10-17): the MUTED table — steel blue / muted gold / sage
//--- ship as the trio; the live/past ink split lives in Sessions_Draw.mqh.
color SessColorOf(const int idx)
{
   switch(idx)
   {
      case 0: return C'70,120,190';    // blue — steel (P-SESS-06 muted table)
      case 1: return C'196,138,64';    // amber — muted gold
      case 2: return C'88,166,128';    // green — sage
      case 3: return C'150,112,190';   // violet
      case 4: return C'212,106,92';    // coral
      case 5: return C'62,178,198';    // cyan
      case 6: return C'198,90,140';    // magenta
      case 7: return C'120,144,156';   // grey-blue
   }
   return clrSilver;
}

//--- the same table's names — the editor's colour chips say WHAT a click will
//--- pick (the tooltip), so a name and a face come from one owner.
string SessColorName(const int idx)
{
   switch(idx)
   {
      case 0: return "Blue";
      case 1: return "Amber";
      case 2: return "Green";
      case 3: return "Violet";
      case 4: return "Coral";
      case 5: return "Cyan";
      case 6: return "Magenta";
      case 7: return "Grey-blue";
   }
   return "Silver";
}

//--- one session slot (the editor edits exactly this)
struct SessSlot
{
   int  zone;
   int  customMin;
   int  startMin;
   int  endMin;
   int  days;
   int  style;
   int  col;
   bool enabled;
};

//--- one computed window (renderer input; price fields filled by the scan)
struct SessWindow
{
   int      slot;
   int      kk;       // day offset from the server-noon anchor (-fut..+hist)
   int      stamp;    // ZONE-day yyyymmdd — the object-name key
   datetime sU;       // UTC edges
   datetime eU;
   double   hi;
   double   lo;
   bool     hasPrice;
};

//+------------------------------------------------------------------+
//| Factory presets — the shipped world map. Three live sessions,     |
//| five parked ones: enabling a parked slot is one switch, never a   |
//| config job. Zone rules (DST) come from the engine, per instant.   |
//+------------------------------------------------------------------+
void SessSlotFactory(const int idx, SessSlot &s)
{
   s.zone = SZ_AUTO_SERVER; s.customMin = 0;
   s.startMin = 480; s.endMin = 1020; s.days = SESS_DAYS_WEEKDAYS;
   s.style = SESS_STYLE_OUTLINE; s.col = 0; s.enabled = false;   // P-SESS-05: hollow ships — some builds slab a rectangle whatever FILL/BGCOLOR say (ZoneFactory.mqh:143)
   switch(idx)
   {
      case 0: s.zone = SZ_TOKYO;     s.startMin = 540; s.endMin = 1080; s.col = 0; s.enabled = true;  break;
      case 1: s.zone = SZ_LONDON;    s.startMin = 480; s.endMin = 1020; s.col = 1; s.enabled = true;  break;
      case 2: s.zone = SZ_NEWYORK;   s.startMin = 480; s.endMin = 1020; s.col = 2; s.enabled = true;  break;
      case 3: s.zone = SZ_SYDNEY;    s.startMin = 420; s.endMin = 960;  s.col = 3; break;
      case 4: s.zone = SZ_FRANKFURT; s.startMin = 480; s.endMin = 1020; s.col = 4; break;
      case 5: s.zone = SZ_DUBAI;     s.startMin = 540; s.endMin = 1080; s.col = 5; break;
      case 6: s.zone = SZ_CHICAGO;   s.startMin = 480; s.endMin = 1020; s.col = 6; break;
      case 7: s.zone = SZ_CUSTOM;    s.startMin = 480; s.endMin = 1020; s.col = 7; break;
   }
}

//+------------------------------------------------------------------+
//| The codec (bit map above). Pack clamps first, so a value written  |
//| by a slider and the value the codec carries are one number.       |
//+------------------------------------------------------------------+
long SessSlotPack(const SessSlot &s)
{
   int zone  = (int)MathMax(0, MathMin(SZ_CUSTOM, s.zone));
   int coff  = (int)MathMax(SESS_CUSTOM_OFF_LO, MathMin(SESS_CUSTOM_OFF_HI, s.customMin)) - SESS_CUSTOM_OFF_LO;
   int st    = (int)MathMax(0, MathMin(1439, s.startMin));
   int en    = (int)MathMax(0, MathMin(1439, s.endMin));
   int days  = (int)MathMax(0, MathMin(127, s.days));
   int style = (int)MathMax(SESS_STYLE_FILLED, MathMin(SESS_STYLE_MID, s.style));
   int col   = (int)MathMax(0, MathMin(7, s.col));
   long L = 0;
   L |= (long)(zone & 0xF);
   L |= ((long)(coff & 0x7FF)) << 4;
   L |= ((long)(st   & 0x7FF)) << 15;
   L |= ((long)(en   & 0x7FF)) << 26;
   L |= ((long)(days & 0x7F))  << 37;
   L |= ((long)(style & 0x3))  << 44;
   L |= ((long)(col  & 0x7))   << 46;
   L |= ((long)(s.enabled ? 1 : 0)) << 49;
   return L;
}

void SessSlotUnpack(const long L, SessSlot &s)
{
   s.zone      = (int)MathMax(0, MathMin(SZ_CUSTOM, (int)(L & 0xF)));
   s.customMin = (int)((L >> 4) & 0x7FF) + SESS_CUSTOM_OFF_LO;
   s.startMin  = (int)MathMax(0, MathMin(1439, (int)((L >> 15) & 0x7FF)));
   s.endMin    = (int)MathMax(0, MathMin(1439, (int)((L >> 26) & 0x7FF)));
   s.days      = (int)MathMax(0, MathMin(127, (int)((L >> 37) & 0x7F)));
   s.style     = (int)MathMax(SESS_STYLE_FILLED, MathMin(SESS_STYLE_MID, (int)((L >> 44) & 0x3)));
   s.col       = (int)MathMax(0, MathMin(7, (int)((L >> 46) & 0x7)));
   s.enabled   = (((L >> 49) & 0x1) != 0);
}

//--- read a slot: the factory preset is the floor (A==0 IS the preset)
void SessSlotGet(const int idx, SessSlot &s)
{
   int i = (int)MathMax(0, MathMin(SESS_SLOTS - 1, idx));
   SessSlotFactory(i, s);
   long L = (long)g_sessSlot[i];
   if(L != 0) SessSlotUnpack(L, s);
}

//--- write a slot (persistence rides the OV_ shadow, never this call)
void SessSlotSet(const int idx, const SessSlot &s)
{
   int i = (int)MathMax(0, MathMin(SESS_SLOTS - 1, idx));
   g_sessSlot[i] = (double)SessSlotPack(s);
}

int SessEnabledCount()
{
   int n = 0;
   SessSlot s;
   for(int i = 0; i < SESS_SLOTS; i++)
   {
      SessSlotGet(i, s);
      if(s.enabled) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Live broker delta, through the project's single owner             |
//| (ConvertServerToGMT — the same relay the level engine uses).      |
//| Offline attach (TimeGMT()==0) answers 0: UTC is the honest        |
//| stand-in for a frozen chart.                                      |
//+------------------------------------------------------------------+
int SessModelLiveDeltaMin()
{
   if(TimeGMT() <= 0) return 0;
   datetime srv = TimeCurrent();
   datetime gmt = ConvertServerToGMT(srv);
   return (int)((srv - gmt) / 60);
}

//--- the server-calendar anchors: noon is the day's stable probe (a
//--- window can never straddle it: every offered zone sits within
//--- -6..+10, so noon maps strictly into one zone day per slot).
datetime SessServerNoon()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   d.hour = 12; d.min = 0; d.sec = 0;
   return StructToTime(d);
}

int SessServerDayStamp()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(), d);
   return d.year * 10000 + d.mon * 100 + d.day;
}

//+------------------------------------------------------------------+
//| One window from one ZONE day: the mask is tested in the zone's    |
//| own weekday (Tokyo Monday 09:00 is a Sunday-night server instant) |
//| and both edges convert per instant, so a window that falls on a   |
//| DST transition keeps its true length. Returns false when the zone |
//| day is not masked.                                                |
//+------------------------------------------------------------------+
bool SessSlotWindowForZoneDay(const SessSlot &s, const datetime zoneDayTs, const int bkrDeltaMin,
                              int &stamp, datetime &sU, datetime &eU)
{
   MqlDateTime d;
   TimeToStruct(zoneDayTs, d);
   int bit = SessMaskBitOfDow(d.day_of_week);
   if((s.days & (1 << bit)) == 0) return false;
   int wStart = (int)zoneDayTs + s.startMin * SESS_MIN_SEC;
   int wEnd   = (int)zoneDayTs + s.endMin   * SESS_MIN_SEC;
   if(s.endMin <= s.startMin) wEnd += SESS_DAY_SEC;   // overnight window
   stamp = d.year * 10000 + d.mon * 100 + d.day;
   sU = SessWallTsToUtc((datetime)wStart, s.zone, s.customMin, true, 0, SDST_NONE, bkrDeltaMin);
   eU = SessWallTsToUtc((datetime)wEnd,   s.zone, s.customMin, true, 0, SDST_NONE, bkrDeltaMin);
   return true;
}

//+------------------------------------------------------------------+
//| Enumerate a slot's windows for k = kFrom..kTo (negative = past     |
//| zone days, 0 = the zone day holding the server noon, positive =    |
//| future zone days). Arrays grow on demand; `n` is the in/out cursor.|
//+------------------------------------------------------------------+
void SessPushWindow(SessWindow &arr[], int &n, const int slot, const int kk, const int stamp,
                    const datetime sU, const datetime eU)
{
   if(n >= ArraySize(arr)) ArrayResize(arr, n + 16);
   arr[n].slot = slot;
   arr[n].kk = kk;
   arr[n].stamp = stamp;
   arr[n].sU = sU;
   arr[n].eU = eU;
   arr[n].hi = 0.0;
   arr[n].lo = 0.0;
   arr[n].hasPrice = false;
   n++;
}

void SessCollectSlot(const int slot, const SessSlot &s, const int kFrom, const int kTo,
                     const datetime serverNoon, const int bkrDeltaMin, SessWindow &arr[], int &n)
{
   for(int k = kFrom; k <= kTo; k++)
   {
      datetime ref = serverNoon + k * SESS_DAY_SEC;
      datetime zoneWall = SessUtcToWallTs(ref, s.zone, s.customMin, true, 0, SDST_NONE, bkrDeltaMin);
      MqlDateTime d;
      TimeToStruct(zoneWall, d);
      datetime zoneDay = SessUtcMake(d.year, d.mon, d.day, 0, 0);
      int stamp; datetime sU, eU;
      if(!SessSlotWindowForZoneDay(s, zoneDay, bkrDeltaMin, stamp, sU, eU)) continue;
      SessPushWindow(arr, n, slot, k, stamp, sU, eU);
   }
}

//+------------------------------------------------------------------+
//| The next boundary of one slot (engine door, the countdown's one   |
//| question): open or close, whichever comes first after `utc`.      |
//+------------------------------------------------------------------+
datetime SessSlotNextBoundary(const SessSlot &s, const datetime utc, const int bkrDeltaMin, bool &isOpen)
{
   return SessNextBoundaryUtc(utc, s.startMin, s.endMin, s.days, s.zone, s.customMin,
                              true, 0, SDST_NONE, bkrDeltaMin, isOpen);
}

//--- window state against `now`
#define SESS_WS_NONE   0
#define SESS_WS_PAST   1
#define SESS_WS_LIVE   2
#define SESS_WS_FUTURE 3
int SessWindowState(const SessWindow &w, const datetime now)
{
   if(now < w.sU) return SESS_WS_FUTURE;
   if(now >= w.eU) return SESS_WS_PAST;
   return SESS_WS_LIVE;
}

//+------------------------------------------------------------------+
//| Display helpers                                                   |
//+------------------------------------------------------------------+
string SessFmtDur(const int secs)
{
   if(secs <= 0) return "<1m";
   int m = secs / 60;
   if(m >= 60)
   {
      int h = m / 60;
      m = m % 60;
      if(m > 0) return StringFormat("%dh %dm", h, m);
      return StringFormat("%dh", h);
   }
   if(m >= 1) return StringFormat("%dm", m);
   return "<1m";
}

//--- pip distance of a range on THIS chart (pips, not points: 3/5-digit
//--- symbols carry an extra point digit the user never counts)
int SessPipsIn(const double hi, const double lo)
{
   double pts = (hi - lo) / _Point;
   if(_Digits == 3 || _Digits == 5) pts = pts / 10.0;
   return (int)MathRound(pts);
}

//--- a window's readable tooltip line: "Tokyo 09:00-18:00 · 2026-10-17"
string SessWindowTip(const SessSlot &s, const datetime sU, const double hi, const double lo, const bool hasPrice)
{
   MqlDateTime d;
   TimeToStruct(sU, d);
   string when = StringFormat("%04d-%02d-%02d", d.year, d.mon, d.day);
   string tip = SessZoneLabel(s.zone) + " " + SessHhMmFromMin(s.startMin) + "-" + SessHhMmFromMin(s.endMin)
              + " (" + when + ")";
   if(hasPrice)
      tip = tip + " · " + DoubleToString(hi, _Digits) + ".." + DoubleToString(lo, _Digits);
   return tip;
}

#endif // SESSIONS_MODEL_MQH
