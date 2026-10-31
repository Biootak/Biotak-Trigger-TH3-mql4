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
//|  P-SESS-13 — THE FRAME BOUNDARY (2026-10-30). MEASURED on a GMT+2   |
//|  broker (AMarkets, XAUUSD M15, 30 Oct 11:04 server): the LDN box    |
//|  was painted 08:00-17:00 CHART time where 10:00-19:00 is right, and |
//|  TYO/NY were the same 2 h early — the whole family sat exactly      |
//|  `server - UTC` to the left. The engine resolved the right UTC      |
//|  instant and this module handed it straight to ObjectMove, whose    |
//|  time axis IS the broker's clock (TimeCurrent/Time[]), so a UTC     |
//|  clock reading became a server wall time. Every instant this module |
//|  HANDS OUT is now the chart's own frame and every instant it TAKES  |
//|  is that same frame. Since P-SESS-20 that frame is the LEARNED      |
//|  broker delta (SessModelLiveDeltaMin, snapped to 30 min and held    |
//|  while the feed is frozen), spent through SessChartFrameOf /        |
//|  SessUtcFrameOf — never the raw (TimeCurrent - TimeGMT) pair, which |
//|  decays one second per second on a dead feed. The raw pair is read  |
//|  in exactly one place: the learn's own probe.                       |
//|                                                                   |
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
   // P-SESS-29 (2026-10-30) — EMPTY SHIPS («پیش‌فرض باکس‌ها فیل نداشته باشه»).
   // P-SESS-24 had shipped FILLED for its object COUNT (367 -> 145 on the reporting
   // chart); the user's verdict on that picture is that a washed slab over the
   // candles is not what a session chart should wear by default. The shipped body
   // is the four-edge hollow frame again, and the wash stays a style the STYLE row
   // can pick — where P-SESS-28 makes the TRANSPARENCY knob bite (visible ink =
   // ink^2/100). The flip ships with a ONE-SHOT migration (see
   // SessSlotsMigrateLegacy / OV_SSDV), or every chart that opened the card would
   // keep the slab for good.
   s.style = SESS_STYLE_OUTLINE; s.col = 0; s.enabled = false;
   switch(idx)
   {
      // P-SESS-16 (2026-10-30): THE FOUR SHIPPED PRESETS ARE THE CLASSIC TABLE, so a
      // fresh chart draws the same four windows a session chart everywhere draws.
      // P-SESS-26 (2026-10-30) — THE TABLE IS BABYPIPS', edge for edge
      // («ساعت‌ها را از اینترنت بگیر و درستش کن» +
      // https://www.babypips.com/tools/forex-market-hours):
      //   Tokyo   7:00 pm - 4:00 am ET  =  00:00-09:00Z  =  09:00-18:00 JST  (+9)
      //   London  3:00 am - 12:00 pm ET =  08:00-17:00Z  =  08:00-17:00 GMT  (+0)
      //   New York 8:00 am - 5:00 pm ET =  13:00-22:00Z  =  08:00-17:00 EDT-5 (-5)
      //   Sydney  5:00 pm - 2:00 am ET  =  22:00-07:00Z  =  08:00-17:00 AEST (+10)
      // Those are the LOCAL hours with ZONE LAW OFF (the standard-time table this
      // family is measured in), so each preset is written in its own city's clock
      // and the engine resolves the UTC edge. P-SESS-25 had London 07-16Z and New
      // York 13:30-20:00Z (TradingView's equity hours) — MEASURED on the live chart's
      // own flushed witness 2026-10-30 19:48 with bkr=120: `win slot=1 sU=09:00`
      // (07:00Z) and `slot=2 sU=15:30` (13:30Z), an hour and a half off the table
      // above. THE LOOK rides the same four: magenta (Tokyo), blue (London), coral
      // (New York), amber (Sydney) - nearest ink in the 8-table to the palette the
      // reference chart wears, and still four different chips.
      case 0: s.zone = SZ_TOKYO;     s.startMin = 540; s.endMin = 1080; s.col = 6; s.enabled = true;  break;   // P-SESS-26: 00:00-09:00Z
      case 1: s.zone = SZ_LONDON;    s.startMin = 480; s.endMin = 1020; s.col = 0; s.enabled = true;  break;   // P-SESS-26: 08:00-17:00Z (London 08-17 local, +0)
      case 2: s.zone = SZ_NEWYORK;   s.startMin = 480; s.endMin = 1020; s.col = 4; s.enabled = true;  break;   // P-SESS-26: 13:00-22:00Z (New York 08-17 local, -5)
      case 3: s.zone = SZ_SYDNEY;    s.startMin = 480; s.endMin = 1020; s.col = 1; s.enabled = true;  break;   // P-SESS-26: 22:00-07:00Z (Sydney 08-17 local, +10); ships ON (the user's ask - P-SESS-14)
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

//--- P-SESS-25 — ONE STYLE ROW, ALL SLOTS. The overview card asks "filled or
//--- empty" for the whole family (the editor still answers per slot); both write
//--- the SAME encoded field, so a later per-slot pick wins and nothing drifts.
void SessSetAllStyle(const int style)
{
   int st = (int)MathMax(SESS_STYLE_FILLED, MathMin(SESS_STYLE_OUTLINE, style));
   for(int i = 0; i < SESS_SLOTS; i++)
   {
      SessSlot s; SessSlotGet(i, s);
      s.style = st;
      SessSlotSet(i, s);
   }
}

//--- every ENABLED slot already wears `style` (the row's own read-back)
bool SessAllStyleIs(const int style)
{
   for(int i = 0; i < SESS_SLOTS; i++)
   {
      SessSlot s; SessSlotGet(i, s);
      if(s.enabled && s.style != style) return false;
   }
   return true;
}

//--- P-UI-RESET-ALL (2026-10-30): every slot back to the factory table.
//--- 0 IS the preset (SessSlotGet falls through to SessSlotFactory), so this
//--- is the ONE writer that says "no slot has been edited" — the same state a
//--- chart that never opened the sessions card is in. It is NOT a loop of
//--- SessSlotSet(preset): that would stamp today's factory values into the
//--- store, and a later preset change could no longer reach those charts.
void SessSlotsResetToFactory()
{
   for(int i = 0; i < SESS_SLOTS; i++) g_sessSlot[i] = 0.0;
   g_sessSlotsEdit = 0;
}

//+------------------------------------------------------------------+
//| P-SESS-16 (2026-10-30): A LEGACY PRESET IS NOT A CHOICE.           |
//| A saved slot that still carries the hours the OLD factory wrote    |
//| was never edited - it is the shipped default wearing a stamp, and  |
//| it keeps a chart on a table the build no longer ships. Those adopt |
//| the current preset once, at the first tick; any OTHER hours are    |
//| the user's and are left exactly as they are.                      |
//+------------------------------------------------------------------+
bool SessSlotIsLegacyPreset(const int idx, const SessSlot &s)
{
   if(idx > 3 || !s.enabled) return false;
   bool zoneOk = (idx == 0 && s.zone == SZ_TOKYO)  || (idx == 1 && s.zone == SZ_LONDON) ||
                 (idx == 2 && s.zone == SZ_NEWYORK) || (idx == 3 && s.zone == SZ_SYDNEY);
   if(!zoneOk) return false;
   SessSlot cur; SessSlotFactory(idx, cur);
   if(s.startMin == cur.startMin && s.endMin == cur.endMin) return false;   // already current
   // P-SESS-26: the OLD pairs, per slot — the table moved to babypips' window, and
   // a chart still wearing a previous build's hours was never edited (any other
   // hours are the user's). Tokyo never moved; London and New York moved back to
   // their own business day, and Sydney's pre-TV pair still migrates.
   if(idx == 0) return (s.startMin == 540 && s.endMin == 1080);             // Tokyo 09-18 local (never moved)
   if(idx == 1) return (s.startMin == 420 && s.endMin == 960);              // London 07-16 local (P-SESS-25's table)
   if(idx == 2) return (s.startMin == 510 && s.endMin == 900);              // New York 08:30-15:00 local (P-SESS-25's table)
   return (s.startMin == 420 && s.endMin == 960);                           // Sydney 07-16 local (pre-TV)
}

//+------------------------------------------------------------------+
//| P-SESS-29 (2026-10-30): THE OLD STYLE STAMP IS NOT A CHOICE.      |
//| A slot whose every field is the CURRENT factory's except a style   |
//| the PREVIOUS build shipped (FILLED) was never edited — it is the   |
//| default wearing that build. It adopts the factory body (OUTLINE)   |
//| ONCE. Any OTHER difference (hours, colour, days, zone, offset) is  |
//| the user's and is left exactly as it is.                          |
//|                                                                   |
//| THE ONCE IS STORED (`OV_SSDV` = 2), and that is the whole point:   |
//| a style-only migration that runs at every attach would also undo a |
//| FILLED the user picks AFTER the flip, because that slot is the     |
//| factory's every field again — the choice would never stick.        |
//+------------------------------------------------------------------+
bool SessSlotIsFilledStamp(const int idx, const SessSlot &s)
{
   if(idx > 3 || s.style != SESS_STYLE_FILLED) return false;
   SessSlot cur; SessSlotFactory(idx, cur);
   return (s.zone      == cur.zone   && s.customMin == cur.customMin &&
           s.startMin  == cur.startMin && s.endMin == cur.endMin    &&
           s.days      == cur.days   && s.col       == cur.col      &&
           s.enabled   == cur.enabled);
}

bool SessSlotsMigrateLegacy(double &slots[])
{
   bool changed = false;
   //--- P-SESS-29: the body flip runs ONCE PER CHART, stamped beside the slots.
   string kVer = g_settingsGVPrefix + "OV_SSDV";
   int ver = GlobalVariableCheck(kVer) ? (int)GlobalVariableGet(kVer) : 0;
   for(int i = 0; i < ArraySize(slots); i++)
   {
      long L = (long)slots[i];
      if(L == 0) continue;                       // 0 IS the preset already (SessSlotGet)
      SessSlot s; SessSlotUnpack(L, s);
      if(ver < 2 && SessSlotIsFilledStamp(i, s)) // P-SESS-29: the old FILLED stamp
      {
         SessSlot f; SessSlotFactory(i, f);
         slots[i] = (double)SessSlotPack(f);
         changed = true;
         continue;
      }
      if(!SessSlotIsLegacyPreset(i, s)) continue;
      SessSlot f2; SessSlotFactory(i, f2);
      slots[i] = (double)SessSlotPack(f2);
      changed = true;
   }
   if(ver < 2) GlobalVariableSet(kVer, 2.0);     // one write, once per chart
   return changed;
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
//|                                                                   |
//| P-SESS-17 (2026-10-30). MEASURED on the user's chart: bkr=55       |
//| minutes while the broker is GMT+2, so every box edge landed at    |
//| :54 instead of on the hour and the start of every session read    |
//| wrong. The frame is `TimeCurrent() - TimeGMT()`: TimeGMT() is the |
//| PC's UTC and keeps running, while TimeCurrent() is the SERVER's   |
//| last tick and FREEZES the moment the terminal loses the feed — the|
//| terminal's own log carries the instant:                           |
//|   14:37:16  '1973395': connect failed [Invalid account]           |
//| so from 14:37 local on, (srv - gmt) decayed one minute per minute |
//| (120 -> 55 by 15:43) and every session edge slid with it.         |
//| The delta is now LEARNED WHILE THE FEED IS LIVE (TimeCurrent       |
//| advancing) and HELD verbatim while it is frozen, and it is       |
//| snapped to the only grid a broker clock can sit on (30 minutes:   |
//| +2:00, +5:30, +9:30 ...), so a first read taken mid-outage lands  |
//| on :00 instead of :54 and never drifts again. The PC clock is NOT |
//| the suspect: measured 0 s skew against the internet's own clock   |
//| (2026-10-30 12:23 UTC).                                           |
//+------------------------------------------------------------------+
static int      s_sessDeltaMin = 0;        // the learned frame, minutes east of UTC
static bool     s_sessDeltaOk  = false;   // false until a LIVE read has landed
static datetime s_sessDeltaSeen = 0;      // the TimeCurrent() that read was taken on
static int      s_sessDeltaHeld = 0;      // consecutive paints answered from the hold
//--- P-SESS-21 (2026-10-30): THE LEARNED HOUR SURVIVES A RESTART.
//--- MEASURED 16:29: a build attached while the feed was dead learned the OUTAGE'S
//--- OWN DECAY (raw=449 s on a GMT+2 broker -> snapped 0) and held it forever, so
//--- every box painted two hours early and the next restart learned garbage again.
//--- The frame is now stored once, only when a LIVE read changed it, and adopted at
//--- attach as an UNVERIFIED frame: it is spent until a real tick lands, then the
//--- learn overwrites it. Key: <settings prefix>OV_SSBD (minutes east of UTC).
static bool     s_sessDeltaStoreRead = false;
static int      s_sessDeltaStored    = -999999;   // what the store already holds

//--- P-SESS-23: the frame's own answer for the witness — one short word that says
//--- WHICH door produced bkr, so "the boxes are 2 h early" is decidable from the log
//--- instead of argued: pin / store / live / hold / none.
static string   s_sessDeltaWhy = "none";

int SessModelLiveDeltaMin()
{
   //--- P-SESS-23 (2026-10-30): A PINNED HOUR OUTRANKS EVERY PROBE.
   //--- Card 15's BROKER UTC row is -13 = AUTO (learn) and -12..+14 = hours east of
   //--- UTC. MEASURED 16:53: the terminal lost its account at 14:37:09 and TimeCurrent()
   //--- froze at 13:07:09 while TimeGMT() walked on, so no probe on this machine can
   //--- see the true +2 before a login — and the user reads every box as an hour wrong.
   //--- The pin is the one door that does not need a live feed.
   if(g_sessSrvUtc >= -12 && g_sessSrvUtc <= 14)
   {
      s_sessDeltaHeld = 0;
      s_sessDeltaWhy  = "pin";
      return g_sessSrvUtc * 60;
   }
   if(TimeGMT() <= 0)
   {
      s_sessDeltaWhy = s_sessDeltaOk ? "store" : "none";
      return s_sessDeltaOk ? s_sessDeltaMin : 0;
   }
   datetime srv = TimeCurrent();
   //--- P-SESS-21: the store is consulted ONCE per attach, and only when nothing
   //--- has been learned yet. Adopting it also marks the read as SEEN, so the very
   //--- next call cannot mistake "no tick yet" for a live read and re-learn the
   //--- outage's decay over a good stored hour.
   if(!s_sessDeltaStoreRead)
   {
      s_sessDeltaStoreRead = true;
      string k0 = g_settingsGVPrefix + "OV_SSBD";
      if(!s_sessDeltaOk && GlobalVariableCheck(k0))
      {
         int v0 = (int)GlobalVariableGet(k0);
         if(v0 >= -12 * 60 && v0 <= 14 * 60)
         {
            s_sessDeltaMin  = v0;
            s_sessDeltaOk   = true;
            s_sessDeltaSeen = srv;       // stored is NOT seen: wait for a real tick
            s_sessDeltaStored = v0;
         }
      }
   }
   //--- P-SESS-25 (2026-10-30): A BROKER CLOCK IS A MULTIPLE OF 30 MINUTES.
   //--- The old rule accepted any plausible pair, so a DEAD feed — whose
   //--- TimeCurrent() stops while TimeGMT() keeps walking — handed the learn its own
   //--- outage decay and snapped it onto the grid: MEASURED 16:52, raw=-894 s on a
   //--- GMT+2 broker snapped to 0, and every window painted two hours early. A live
   //--- pair sits ON the grid (a broker's clock is exact to the second, NTP aside);
   //--- a frozen one drifts off it by the outage's own age. So the learn now asks
   //--- three questions and writes nothing unless all three answer: the terminal is
   //--- CONNECTED, the pair is ON the grid (|raw - nearest30| <= 2 min), and the
   //--- server clock ADVANCED since the last read. Anything else holds the store.
   datetime gmt = ConvertServerToGMT(srv);  // the project's one owner pair
   int d = (int)((srv - gmt) / 60);
   int nearest = (d >= 0) ? ((d + 15) / 30) * 30 : -(((-d) + 15) / 30) * 30;
   bool onGrid   = (MathAbs(d - nearest) <= 2);
   bool advanced = (srv > s_sessDeltaSeen);
   bool liveRead = (IsConnected() && onGrid && advanced);
   if(liveRead)
   {
      s_sessDeltaMin  = nearest;
      s_sessDeltaOk   = true;
      s_sessDeltaHeld = 0;
      s_sessDeltaWhy  = "live";
      //--- written only when a LIVE read CHANGED it: one compare, never a write
      //--- per frame, so a still chart still costs zero syscalls here.
      if(nearest != s_sessDeltaStored)
      {
         GlobalVariableSet(g_settingsGVPrefix + "OV_SSBD", (double)nearest);
         s_sessDeltaStored = nearest;
      }
   }
   else if(s_sessDeltaOk)
   {
      s_sessDeltaHeld++;                      // answered from the store, not from a probe
      s_sessDeltaWhy = "hold";
   }
   else
   {
      s_sessDeltaWhy = "none";                // never learned and nothing stored
   }
   s_sessDeltaSeen = srv;
   return s_sessDeltaOk ? s_sessDeltaMin : 0;
}

//--- the frame's own state, for the flushed witness (P-SESS-17): `held` counts
//--- the paints answered from the frozen-feed snapshot, so a box that sits at
//--- the wrong hour can be told from a box that is merely held still.
int  SessModelDeltaHeldCount() { return s_sessDeltaHeld; }

//--- P-SESS-23: which door answered `bkr` this frame: pin / store / live / hold / none.
string SessModelDeltaWhy() { return s_sessDeltaWhy; }

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
//--- P-SESS-15 (2026-10-30): WHICH OFFSET THE WINDOW IS MEASURED IN.
//--- Two conventions ship side by side, and the user picks one:
//---   g_sessDst ON  = the CITY's own clock (London 08:00-17:00 local, so
//---                   07:00-16:00Z while Europe is on BST).
//---   g_sessDst OFF = STANDARD time year-round, i.e. the classic FX table
//---                   (Tokyo 00-09Z, London 08-17Z, NY 13-22Z, Sydney
//---                   21-06Z) — what every session chart quotes.
//--- The engine stays PURE: "no DST" is spelled SZ_CUSTOM carrying the
//--- zone's own base offset, so its DST term is simply never asked for and
//--- the golden vectors (tests/Biotak_Sessions_Time_Test.mq4) are untouched.
int SessEffZone(const SessSlot &s, int &effCustom)
{
   effCustom = s.customMin;
   if(g_sessDst) return s.zone;                                  // the city's own clock
   if(s.zone == SZ_AUTO_SERVER || s.zone == SZ_UTC || s.zone == SZ_CUSTOM)
      return s.zone;                                             // a clock or an explicit offset: nothing to strip
   effCustom = SessZoneBaseMin(s.zone);                          // STANDARD time — no DST term
   return SZ_CUSTOM;
}

//+------------------------------------------------------------------+
//| P-SESS-20 (2026-10-30): THE CHART FRAME CANNOT DECAY.             |
//|                                                                   |
//| MEASURED 16:29 today: `[P-SESS] paint bkr=0 … srv=13:07:09         |
//| gmt=12:59:40 raw=449 held=1` and every Tokyo edge read `:07`. The  |
//| feed had been frozen since 14:37, so (TimeCurrent - TimeGMT) grew  |
//| one second per second while TimeCurrent stood still, and           |
//| ConvertGMTToServer() added that decay to every edge: the learned   |
//| frame (SessModelLiveDeltaMin, P-SESS-17) was held correctly and    |
//| then spent on top of a second, decaying copy of itself.            |
//|                                                                   |
//| These two are the only arithmetic the frame doors use. On a LIVE   |
//| feed they are identical to the owner pair (a broker clock is a     |
//| multiple of 30 minutes — the grid the learn snaps to), so nothing  |
//| moves on a healthy terminal; on a frozen one the last learned hour |
//| is kept instead of sliding. The RAW pair is read in exactly one    |
//| place, SessModelLiveDeltaMin's own probe, and nowhere else.        |
//+------------------------------------------------------------------+
datetime SessChartFrameOf(const datetime utc, const int bkrDeltaMin)
{
   return (datetime)((long)utc + (long)bkrDeltaMin * 60);
}

datetime SessUtcFrameOf(const datetime chart, const int bkrDeltaMin)
{
   return (datetime)((long)chart - (long)bkrDeltaMin * 60);
}

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
   int zOff = 0;
   int zZone = SessEffZone(s, zOff);                  // P-SESS-15
   sU = SessWallTsToUtc((datetime)wStart, zZone, zOff, true, 0, SDST_NONE, bkrDeltaMin);
   eU = SessWallTsToUtc((datetime)wEnd,   zZone, zOff, true, 0, SDST_NONE, bkrDeltaMin);
   //--- P-SESS-13: the edges leave this module in the CHART's frame (the
   //--- frame ObjectMove/iBarShift/TimeCurrent all speak). The stamp above
   //--- stays the ZONE day — it is the object-name key, not a coordinate.
   sU = SessChartFrameOf(sU, bkrDeltaMin);            // P-SESS-20: the LEARNED frame, never the raw pair
   eU = SessChartFrameOf(eU, bkrDeltaMin);
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
      int zOff2 = 0;                                  // P-SESS-15: the day is taken in the SAME offset as the window
      int zZone2 = SessEffZone(s, zOff2);
      datetime zoneWall = SessUtcToWallTs(ref, zZone2, zOff2, true, 0, SDST_NONE, bkrDeltaMin);
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
//| question): open or close, whichever comes first after `nowServer`.|
//| P-SESS-13: chart frame in, chart frame out — the engine is asked  |
//| in UTC, so the one conversion pair is spent here and nowhere else.|
//+------------------------------------------------------------------+
datetime SessSlotNextBoundary(const SessSlot &s, const datetime nowServer, const int bkrDeltaMin, bool &isOpen)
{
   int zOff = 0;                                      // P-SESS-15
   int zZone = SessEffZone(s, zOff);
   datetime b = SessNextBoundaryUtc(SessUtcFrameOf(nowServer, bkrDeltaMin), s.startMin, s.endMin, s.days,
                                    zZone, zOff, true, 0, SDST_NONE, bkrDeltaMin, isOpen);
   if(b <= 0) return b;
   return SessChartFrameOf(b, bkrDeltaMin);           // P-SESS-20
}

//+------------------------------------------------------------------+
//| Is one slot open NOW, asked in the chart's frame (P-SESS-13).     |
//| The alert flip in SessionsTick used to hand TimeCurrent() to a    |
//| UTC query, so a slot flipped `server - UTC` early. The frame now  |
//| belongs to this module: the caller never converts anything.       |
//+------------------------------------------------------------------+
bool SessSlotIsOpenNow(const SessSlot &s, const datetime nowServer, const int bkrDeltaMin)
{
   if(!s.enabled) return false;
   int ds; datetime sU, eU;
   int zOff = 0;                                      // P-SESS-15
   int zZone = SessEffZone(s, zOff);
   return SessWindowAt(SessUtcFrameOf(nowServer, bkrDeltaMin), s.startMin, s.endMin, s.days, zZone, zOff,
                       true, 0, SDST_NONE, bkrDeltaMin, ds, sU, eU);   // P-SESS-20
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
