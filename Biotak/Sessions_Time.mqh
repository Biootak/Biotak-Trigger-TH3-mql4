//+------------------------------------------------------------------+
//|                                              Sessions_Time.mqh   |
//|                    Copyright 2026, Biotak Project                |
//|                                                                  |
//|  P-SESS-01/02/03 — THE SESSION TIMEZONE ENGINE.                   |
//|                                                                  |
//|  WHY THIS FILE EXISTS: every MT4 session box in the wild runs a   |
//|  FIXED offset, and a fixed offset silently misplaces every box in |
//|  the two or three weeks each year when one region is on DST and   |
//|  its counterpart is not (US switches the 2nd Sunday of March, EU  |
//|  only the last; November mirrors it). MEASURED for an EET broker  |
//|  (base +2/+3, EU rule): NY 09:30 is 15:30 server from Mar 8 to    |
//|  Mar 29, then 16:30 — a fixed-offset tool prints 16:30 for all    |
//|  six weeks and the box is an hour wrong exactly when it matters.  |
//|                                                                  |
//|  THE MODEL — three clocks, resolved per INSTANT, never per config:|
//|    * SERVER  = the broker's own clock (TimeCurrent).              |
//|    * UTC     = the pivot; every DST transition below is declared  |
//|                as a UTC instant, so the resolution has no         |
//|                chicken-and-egg.                                   |
//|    * ZONE    = where a session's wall clock lives: the broker     |
//|                clock (auto, live delta) or a named region whose   |
//|                DST rule is hard-coded (EU / US / Southern / none).|
//|                                                                  |
//|  RULES (gated, see tools/check-regressions.js P-SESS):            |
//|    P-SESS-01  EU: last Sunday of March 01:00 UTC -> +1h;          |
//|               last Sunday of October 01:00 UTC -> +0h.            |
//|    P-SESS-02  US: 2nd Sunday of March 07:00 UTC -> +1h;           |
//|               1st Sunday of November 06:00 UTC -> +0h.            |
//|    P-SESS-03  Southern (Sydney): 1st Sunday of October 16:00 UTC  |
//|               -> +1h; 1st Sunday of April 16:00 UTC -> +0h         |
//|               (both are 02:00/03:00 local, spelled as UTC).       |
//|                                                                  |
//|  PURE MATH: no chart, no objects, no project includes — the       |
//|  golden vectors live in tests/Biotak_Sessions_Time_Test.mq4       |
//|  (STANDALONE, so a shared bug cannot make both sides green).     |
//+------------------------------------------------------------------+
#ifndef SESSIONS_TIME_MQH
#define SESSIONS_TIME_MQH

#define SESS_DAY_SEC   86400
#define SESS_HOUR_SEC  3600
#define SESS_MIN_SEC   60

//--- day mask: bit 0 = Monday ... bit 6 = Sunday (ISO order, big-endian week)
#define SESS_DAYS_WEEKDAYS 0x1F
#define SESS_DAYS_ALL      0x7F

enum ENUM_SESS_ZONE
{
   SZ_AUTO_SERVER = 0,   // follow the broker's own clock (live delta)
   SZ_UTC         = 1,   // the pivot
   SZ_TOKYO       = 2,   // +9, no DST (Japan dropped it 1952)
   SZ_LONDON      = 3,   // +0/+1 EU rule
   SZ_FRANKFURT   = 4,   // +1/+2 EU rule
   SZ_NEWYORK     = 5,   // -5/-4 US rule
   SZ_CHICAGO     = 6,   // -6/-5 US rule
   SZ_SYDNEY      = 7,   // +10/+11 southern rule
   SZ_DUBAI       = 8,   // +4, no DST
   SZ_ISTANBUL    = 9,   // +3, no DST (fixed since 2016)
   SZ_CUSTOM      = 10   // fixed minute offset carried by the slot
};

enum ENUM_SESS_DST
{
   SDST_NONE  = 0,
   SDST_EU    = 1,
   SDST_US    = 2,
   SDST_SOUTH = 3
};

//+------------------------------------------------------------------+
//| Zone descriptors                                                  |
//+------------------------------------------------------------------+
string SessZoneTag(const int zone)
{
   switch(zone)
   {
      case SZ_AUTO_SERVER: return "SVR";
      case SZ_UTC:         return "UTC";
      case SZ_TOKYO:       return "TYO";
      case SZ_LONDON:      return "LDN";
      case SZ_FRANKFURT:   return "FRA";
      case SZ_NEWYORK:     return "NY";
      case SZ_CHICAGO:     return "CHI";
      case SZ_SYDNEY:      return "SYD";
      case SZ_DUBAI:       return "DXB";
      case SZ_ISTANBUL:    return "IST";
      case SZ_CUSTOM:      return "CUS";
   }
   return "?";
}

string SessZoneLabel(const int zone)
{
   switch(zone)
   {
      case SZ_AUTO_SERVER: return "Server";
      case SZ_UTC:         return "UTC";
      case SZ_TOKYO:       return "Tokyo";
      case SZ_LONDON:      return "London";
      case SZ_FRANKFURT:   return "Frankfurt";
      case SZ_NEWYORK:     return "New York";
      case SZ_CHICAGO:     return "Chicago";
      case SZ_SYDNEY:      return "Sydney";
      case SZ_DUBAI:       return "Dubai";
      case SZ_ISTANBUL:    return "Istanbul";
      case SZ_CUSTOM:      return "Custom";
   }
   return "?";
}

//--- winter/base offset in minutes (before any DST term)
int SessZoneBaseMin(const int zone)
{
   switch(zone)
   {
      case SZ_AUTO_SERVER: return 0;      // resolved from the live broker delta
      case SZ_UTC:         return 0;
      case SZ_TOKYO:       return 540;
      case SZ_LONDON:      return 0;
      case SZ_FRANKFURT:   return 60;
      case SZ_NEWYORK:     return -300;
      case SZ_CHICAGO:     return -360;
      case SZ_SYDNEY:      return 600;
      case SZ_DUBAI:       return 240;
      case SZ_ISTANBUL:    return 180;
      case SZ_CUSTOM:      return 0;      // the slot's customMin carries it
   }
   return 0;
}

ENUM_SESS_DST SessZoneDstRule(const int zone)
{
   switch(zone)
   {
      case SZ_LONDON:
      case SZ_FRANKFURT:   return SDST_EU;
      case SZ_NEWYORK:
      case SZ_CHICAGO:     return SDST_US;
      case SZ_SYDNEY:      return SDST_SOUTH;
   }
   return SDST_NONE;
}

//+------------------------------------------------------------------+
//| Calendar primitives                                               |
//+------------------------------------------------------------------+
bool SessLeapYear(const int y)
{
   return ((y % 4 == 0 && y % 100 != 0) || (y % 400 == 0));
}

int SessDaysInMonth(const int y, const int m)
{
   int d[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
   if(m == 2 && SessLeapYear(y)) return 29;
   if(m < 1 || m > 12) return 30;
   return d[m-1];
}

//--- MQL4 day_of_week: 0 = Sunday ... 6 = Saturday. P-SESS mask bit:
//--- Monday = bit 0 ... Sunday = bit 6 (ISO order).
int SessMaskBitOfDow(const int mqlDow)
{
   return (mqlDow + 6) % 7;
}

datetime SessUtcMake(const int y, const int mo, const int d, const int hh, const int mn)
{
   MqlDateTime dt;
   dt.year = y; dt.mon = mo; dt.day = d;
   dt.hour = hh; dt.min = mn; dt.sec = 0;
   return StructToTime(dt);
}

//--- day_of_week of a plain calendar date (0 = Sunday)
int SessDowOf(const int y, const int mo, const int d)
{
   MqlDateTime dt;
   TimeToStruct(SessUtcMake(y, mo, d, 12, 0), dt);
   return dt.day_of_week;
}

//--- day-of-month of the n-th `dow` (0 = Sunday) in y/m, 0 if none
int SessNthDow(const int y, const int mo, const int dow, const int n)
{
   int f = 1 + ((dow - SessDowOf(y, mo, 1)) + 7) % 7;   // first dow in month
   int r = f + 7 * (n - 1);
   if(r > SessDaysInMonth(y, mo)) return 0;
   return r;
}

int SessLastDow(const int y, const int mo, const int dow)
{
   int r = SessNthDow(y, mo, dow, 5);
   if(r == 0) r = SessNthDow(y, mo, dow, 4);
   return r;
}

//+------------------------------------------------------------------+
//| DST transition instants — UTC, so resolution never needs a second |
//| opinion. P-SESS-01/02/03.                                          |
//+------------------------------------------------------------------+
datetime SessEuStartUtc(const int y)    { return SessUtcMake(y, 3,  SessLastDow(y, 3, 0),       1, 0); }
datetime SessEuEndUtc(const int y)      { return SessUtcMake(y, 10, SessLastDow(y, 10, 0),      1, 0); }
//--- US 02:00 local standard = 07:00 UTC (Mar). 02:00 local daylight =
//--- 06:00 UTC (Nov). Both are the statutory instants since 2007.
datetime SessUsStartUtc(const int y)    { return SessUtcMake(y, 3,  SessNthDow(y, 3, 0, 2),      7, 0); }
datetime SessUsEndUtc(const int y)      { return SessUtcMake(y, 11, SessNthDow(y, 11, 0, 1),     6, 0); }
//--- Sydney 02:00 AEST (= +10) -> 16:00 UTC the previous day; 03:00
//--- AEDT (= +11) -> 16:00 UTC the previous day.
datetime SessSouthStartUtc(const int y) { return SessUtcMake(y, 10, SessNthDow(y, 10, 0, 1), 16, 0) - SESS_DAY_SEC; }
datetime SessSouthEndUtc(const int y)   { return SessUtcMake(y, 4,  SessNthDow(y, 4, 0, 1),  16, 0) - SESS_DAY_SEC; }

bool SessDstActiveAt(const int rule, const datetime utc)
{
   if(rule == SDST_NONE) return false;
   MqlDateTime dt;
   TimeToStruct(utc, dt);
   int y = dt.year;
   if(rule == SDST_EU)
      return (utc >= SessEuStartUtc(y) && utc < SessEuEndUtc(y));
   if(rule == SDST_US)
      return (utc >= SessUsStartUtc(y) && utc < SessUsEndUtc(y));
   //--- SOUTHERN wraps the year end: Oct(y) .. Apr(y+1)
   return (utc >= SessSouthStartUtc(y) || utc < SessSouthEndUtc(y));
}

//+------------------------------------------------------------------+
//| Offsets                                                           |
//+------------------------------------------------------------------+
//--- minutes east of UTC for a NAMED zone (never AUTO_SERVER) at utc
int SessZoneOffMinAt(const int zone, const int customMin, const datetime utc)
{
   if(zone == SZ_CUSTOM) return customMin;
   int base = SessZoneBaseMin(zone);
   return base + (SessDstActiveAt(SessZoneDstRule(zone), utc) ? 60 : 0);
}

//--- minutes east of UTC for the BROKER clock at utc.
//--- AUTO : the live probe TimeCurrent()-TimeGMT() — the project's own
//---        single conversion owner (BasePrice_A ConvertServerToGMT).
//--- MANUAL: base + the declared regime (EU/US/none), history-correct.
int SessBrokerOffMinAt(const bool autoMode, const int baseMin, const int regime,
                       const int liveDeltaMin, const datetime utc)
{
   if(autoMode) return liveDeltaMin;
   return baseMin + (SessDstActiveAt(regime, utc) ? 60 : 0);
}

//--- the effective offset of a SLOT ZONE (auto broker zone answers the broker)
int SessEffOffMinAt(const int zone, const int customMin,
                    const bool bkrAuto, const int bkrBaseMin, const int bkrRegime,
                    const int liveDeltaMin, const datetime utc)
{
   if(zone == SZ_AUTO_SERVER)
      return SessBrokerOffMinAt(bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin, utc);
   return SessZoneOffMinAt(zone, customMin, utc);
}

int SessLiveBrokerDeltaMin()
{
   return (int)MathRound((double)(TimeCurrent() - TimeGMT()) / 60.0);
}

//+------------------------------------------------------------------+
//| Wall <-> UTC. A wall timestamp carries no zone info, so the       |
//| offset is resolved AT THE RESULTING INSTANT — two passes, because |
//| the guess can land on the far side of an imminent transition.     |
//+------------------------------------------------------------------+
datetime SessWallTsToUtc(const datetime wallTs, const int zone, const int customMin,
                         const bool bkrAuto, const int bkrBaseMin, const int bkrRegime,
                         const int liveDeltaMin)
{
   int guess = (zone == SZ_AUTO_SERVER)
              ? (bkrAuto ? liveDeltaMin : bkrBaseMin)
              : SessZoneBaseMin(zone);
   if(zone == SZ_CUSTOM) guess = customMin;
   datetime u1 = wallTs - guess * SESS_MIN_SEC;
   int off  = SessEffOffMinAt(zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin, u1);
   datetime u2 = wallTs - off * SESS_MIN_SEC;
   int off2 = SessEffOffMinAt(zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin, u2);
   if(off2 != off) u2 = wallTs - off2 * SESS_MIN_SEC;
   return u2;
}

datetime SessUtcToWallTs(const datetime utc, const int zone, const int customMin,
                         const bool bkrAuto, const int bkrBaseMin, const int bkrRegime,
                         const int liveDeltaMin)
{
   int off = SessEffOffMinAt(zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin, utc);
   return utc + off * SESS_MIN_SEC;
}

//+------------------------------------------------------------------+
//| THE WINDOW QUERY — the one door every renderer/alert uses.        |
//| Answers: is `utc` inside the slot's window, and which session-LOCAL|
//| day it belongs to (dayStamp yyyymmdd — the object-name key), plus  |
//| the window's UTC edges. Overnight windows (endMin <= startMin)     |
//| wrap into the next wall day AND are found through yesterday's      |
//| candidate, so a 22:00-06:00 window at 02:00 names the START day.   |
//| The day mask is tested in the ZONE's own weekday — Tokyo Monday    |
//| 09:00 is a Sunday-night server instant and must still match.       |
//+------------------------------------------------------------------+
bool SessWindowAt(const datetime utc,
                  const int startMin, const int endMin, const int daysMask,
                  const int zone, const int customMin,
                  const bool bkrAuto, const int bkrBaseMin, const int bkrRegime,
                  const int liveDeltaMin,
                  int &dayStamp, datetime &startUtc, datetime &endUtc)
{
   dayStamp = 0; startUtc = 0; endUtc = 0;
   datetime wall = SessUtcToWallTs(utc, zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin);
   MqlDateTime w;
   TimeToStruct(wall, w);
   int wallDateTs = (int)SessUtcMake(w.year, w.mon, w.day, 0, 0);

   for(int back = 0; back <= 1; back++)   // today, then yesterday (overnight tail)
   {
      datetime dayTs = (datetime)(wallDateTs - back * SESS_DAY_SEC);
      MqlDateTime d;
      TimeToStruct(dayTs, d);
      int bit = SessMaskBitOfDow(d.day_of_week);
      if((daysMask & (1 << bit)) == 0) continue;
      int wStart = (int)dayTs + startMin * SESS_MIN_SEC;
      int wEnd   = (int)dayTs + endMin   * SESS_MIN_SEC;
      if(endMin <= startMin) wEnd += SESS_DAY_SEC;          // overnight
      if((int)wall < wStart || (int)wall >= wEnd) continue;
      dayStamp = d.year * 10000 + d.mon * 100 + d.day;
      startUtc = SessWallTsToUtc((datetime)wStart, zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin);
      endUtc   = SessWallTsToUtc((datetime)wEnd,   zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| THE NEXT BOUNDARY — open or close, whichever comes first after    |
//| `utc` (the countdown's one question). isOpen answers the state    |
//| now; boundaryUtc the instant it changes. Walks the next 8 wall    |
//| days; a disabled weekday only skips its own open.                 |
//+------------------------------------------------------------------+
datetime SessNextBoundaryUtc(const datetime utc,
                             const int startMin, const int endMin, const int daysMask,
                             const int zone, const int customMin,
                             const bool bkrAuto, const int bkrBaseMin, const int bkrRegime,
                             const int liveDeltaMin,
                             bool &isOpen)
{
   int ds; datetime sU, eU;
   isOpen = SessWindowAt(utc, startMin, endMin, daysMask, zone, customMin,
                         bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin, ds, sU, eU);
   if(isOpen) return eU;

   datetime wall = SessUtcToWallTs(utc, zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin);
   MqlDateTime w;
   TimeToStruct(wall, w);
   datetime dayTs0 = SessUtcMake(w.year, w.mon, w.day, 0, 0);

   datetime best = 0;
   for(int i = 0; i <= 8; i++)
   {
      datetime dayTs = dayTs0 + i * SESS_DAY_SEC;
      MqlDateTime d;
      TimeToStruct(dayTs, d);
      int bit = SessMaskBitOfDow(d.day_of_week);
      if((daysMask & (1 << bit)) == 0) continue;
      datetime wStart = dayTs + startMin * SESS_MIN_SEC;
      datetime sUc = SessWallTsToUtc(wStart, zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin);
      if(sUc <= utc) continue;
      if(best == 0 || sUc < best) best = sUc;
      break;   // the first enabled day's open after utc wins
   }
   return best;
}

//+------------------------------------------------------------------+
//| Display helper: a "HH:MM" wall string in a zone                   |
//+------------------------------------------------------------------+
string SessHhMmInZone(const datetime utc, const int zone, const int customMin,
                      const bool bkrAuto, const int bkrBaseMin, const int bkrRegime,
                      const int liveDeltaMin)
{
   MqlDateTime d;
   TimeToStruct(SessUtcToWallTs(utc, zone, customMin, bkrAuto, bkrBaseMin, bkrRegime, liveDeltaMin), d);
   return StringFormat("%02d:%02d", d.hour, d.min);
}

string SessHhMmFromMin(const int minutes)
{
   int m = ((minutes % 1440) + 1440) % 1440;
   return StringFormat("%02d:%02d", m / 60, m % 60);
}

#endif // SESSIONS_TIME_MQH
