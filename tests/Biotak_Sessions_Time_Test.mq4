//+------------------------------------------------------------------+
//|                              Biotak_Sessions_Time_Test.mq4        |
//|                                  Copyright 2026, Biotak Project   |
//|                                                                  |
//|  STANDALONE golden test for the session timezone engine           |
//|  (Biotak/Sessions_Time.mqh — P-SESS-01/02/03).                    |
//|                                                                  |
//|  WHY STANDALONE: the vectors below were computed BY HAND from the |
//|  statutory rules (EU: last Sundays Mar/Oct 01:00 UTC; US: 2nd Sun |
//|  Mar 07:00 UTC / 1st Sun Nov 06:00 UTC; Sydney: 1st Sun Oct/Apr   |
//|  16:00 UTC) for 2026. The test shares NO code with the engine     |
//|  beyond the engine itself, so a rule flipped in the engine fails  |
//|  the numbers no matter how self-consistent the file looks.        |
//|                                                                  |
//|  THE HEADLINE VECTOR IS THE DIVERGENCE WINDOW: Mar 8 - Mar 29     |
//|  2026 the US is on DST while the EU is not, so an EET broker      |
//|  (+2/+3, EU rule) shows NY 09:30 as 15:30 server for those weeks  |
//|  and 16:30 after — a fixed-offset tool prints 16:30 for all six.  |
//|                                                                  |
//|  Usage: attach to an empty intraday chart, read Experts.          |
//|         Every line is prefixed [SESSTEST].                        |
//+------------------------------------------------------------------+
#property strict
#property copyright "Biotak Project"
#property description "Golden test for the session timezone engine (P-SESS)"

#include "..\Biotak\Sessions_Time.mqh"

int g_pass = 0;
int g_fail = 0;

//--- hand-spelled constructor: shares nothing with the engine
datetime DT(const int y, const int mo, const int d, const int hh, const int mn)
{
   MqlDateTime dt;
   dt.year = y; dt.mon = mo; dt.day = d;
   dt.hour = hh; dt.min = mn; dt.sec = 0;
   return StructToTime(dt);
}

void Ck(const string label, const bool ok)
{
   if(ok) { g_pass++; Print("[SESSTEST] PASS ", label); }
   else   { g_fail++; Print("[SESSTEST] FAIL ", label); }
}

void CkDt(const string label, const datetime got, const datetime want)
{
   bool ok = ((int)got == (int)want);
   if(ok) { g_pass++; Print("[SESSTEST] PASS ", label); }
   else
   {
      g_fail++;
      Print("[SESSTEST] FAIL ", label,
            " got=", TimeToString(got, TIME_DATE|TIME_MINUTES),
            " want=", TimeToString(want, TIME_DATE|TIME_MINUTES));
   }
}

void CkI(const string label, const int got, const int want)
{
   bool ok = (got == want);
   if(ok) { g_pass++; Print("[SESSTEST] PASS ", label); }
   else   { g_fail++; Print("[SESSTEST] FAIL ", label, " got=", got, " want=", want); }
}

void OnStart()
{
   //--- 2026 switch instants: hand-read from a calendar
   CkDt("P-SESS-01 EU start 2026 = Mar 29 01:00Z",  SessEuStartUtc(2026),    DT(2026,3,29,1,0));
   CkDt("P-SESS-01 EU end   2026 = Oct 25 01:00Z",  SessEuEndUtc(2026),      DT(2026,10,25,1,0));
   CkDt("P-SESS-02 US start 2026 = Mar  8 07:00Z",  SessUsStartUtc(2026),    DT(2026,3,8,7,0));
   CkDt("P-SESS-02 US end   2026 = Nov  1 06:00Z",  SessUsEndUtc(2026),      DT(2026,11,1,6,0));
   CkDt("P-SESS-03 SYD start 2026 = Oct  3 16:00Z", SessSouthStartUtc(2026), DT(2026,10,3,16,0));
   CkDt("P-SESS-03 SYD end   2026 = Apr  4 16:00Z", SessSouthEndUtc(2026),   DT(2026,4,4,16,0));

   //--- offsets at the edges (the second before / after each switch)
   CkI("LDN off Mar 29 00:30Z = 0",   SessZoneOffMinAt(SZ_LONDON, 0, DT(2026,3,29,0,30)), 0);
   CkI("LDN off Mar 29 01:30Z = +60", SessZoneOffMinAt(SZ_LONDON, 0, DT(2026,3,29,1,30)), 60);
   CkI("LDN off Oct 25 00:30Z = +60", SessZoneOffMinAt(SZ_LONDON, 0, DT(2026,10,25,0,30)), 60);
   CkI("LDN off Oct 25 01:30Z = 0",   SessZoneOffMinAt(SZ_LONDON, 0, DT(2026,10,25,1,30)), 0);
   CkI("NY  off Mar  8 06:30Z = -300", SessZoneOffMinAt(SZ_NEWYORK, 0, DT(2026,3,8,6,30)), -300);
   CkI("NY  off Mar  8 07:30Z = -240", SessZoneOffMinAt(SZ_NEWYORK, 0, DT(2026,3,8,7,30)), -240);
   CkI("NY  off Nov  1 05:30Z = -240", SessZoneOffMinAt(SZ_NEWYORK, 0, DT(2026,11,1,5,30)), -240);
   CkI("NY  off Nov  1 06:30Z = -300", SessZoneOffMinAt(SZ_NEWYORK, 0, DT(2026,11,1,6,30)), -300);
   CkI("SYD off Jan 15 = +660",        SessZoneOffMinAt(SZ_SYDNEY, 0, DT(2026,1,15,12,0)), 660);
   CkI("SYD off Jun 15 = +600",        SessZoneOffMinAt(SZ_SYDNEY, 0, DT(2026,6,15,12,0)), 600);
   CkI("SYD off Apr  4 15:59Z = +660", SessZoneOffMinAt(SZ_SYDNEY, 0, DT(2026,4,4,15,59)), 660);
   CkI("SYD off Apr  4 16:01Z = +600", SessZoneOffMinAt(SZ_SYDNEY, 0, DT(2026,4,4,16,1)), 600);

   //--- THE DIVERGENCE WINDOW: EET broker (+2 base, EU rule), NY 09:30 wall
   datetime ny1 = SessWallTsToUtc(DT(2026,3,16,9,30), SZ_NEWYORK, 0, false, 120, SDST_EU, 0);
   CkDt("NY 09:30 on Mar 16 -> 13:30Z", ny1, DT(2026,3,16,13,30));
   CkI("EET off at Mar 16 = +120 (EU not on DST yet)",
       SessBrokerOffMinAt(false, 120, SDST_EU, 0, ny1), 120);
   CkDt("NY open shows 15:30 server in the gap",
       SessUtcToWallTs(ny1, SZ_AUTO_SERVER, 0, false, 120, SDST_EU, 0), DT(2026,3,16,15,30));
   datetime ny2 = SessWallTsToUtc(DT(2026,4,1,9,30), SZ_NEWYORK, 0, false, 120, SDST_EU, 0);
   CkDt("NY 09:30 on Apr  1 -> 13:30Z", ny2, DT(2026,4,1,13,30));
   CkI("EET off at Apr 1 = +180", SessBrokerOffMinAt(false, 120, SDST_EU, 0, ny2), 180);
   CkDt("NY open shows 16:30 server after the gap",
       SessUtcToWallTs(ny2, SZ_AUTO_SERVER, 0, false, 120, SDST_EU, 0), DT(2026,4,1,16,30));

   //--- London stability on an EET broker: 10:00 server both sides of the gap
   CkDt("LDN 08:00 Mar 16 -> 08:00Z (GMT)",
       SessWallTsToUtc(DT(2026,3,16,8,0), SZ_LONDON, 0, false, 120, SDST_EU, 0), DT(2026,3,16,8,0));
   CkDt("LDN 08:00 Apr  1 -> 07:00Z (BST)",
       SessWallTsToUtc(DT(2026,4,1,8,0), SZ_LONDON, 0, false, 120, SDST_EU, 0), DT(2026,4,1,7,0));

   //--- fixed-offset broker with NO broker DST: London DRIFTS one hour
   CkDt("LDN 08:00 Jan 15 on +3-no-DST -> 08:00Z",
       SessWallTsToUtc(DT(2026,1,15,8,0), SZ_LONDON, 0, false, 180, SDST_NONE, 0), DT(2026,1,15,8,0));
   CkDt("LDN 08:00 Jul 15 on +3-no-DST -> 07:00Z",
       SessWallTsToUtc(DT(2026,7,15,8,0), SZ_LONDON, 0, false, 180, SDST_NONE, 0), DT(2026,7,15,7,0));

   //--- DST INSIDE the session: NY 09:30 on Nov 1 2026 is already EST
   CkDt("NY 09:30 Nov 1 -> 14:30Z (switch happened 06:00Z)",
       SessWallTsToUtc(DT(2026,11,1,9,30), SZ_NEWYORK, 0, false, 120, SDST_EU, 0), DT(2026,11,1,14,30));
   CkDt("LDN 08:00 Mar 29 -> 07:00Z (switch happened 01:00Z)",
       SessWallTsToUtc(DT(2026,3,29,8,0), SZ_LONDON, 0, false, 120, SDST_EU, 0), DT(2026,3,29,7,0));

   //--- overnight window (22:00-06:00 UTC): the tail names the START day
   int ds; datetime sU, eU;
   bool in = SessWindowAt(DT(2026,6,11,2,0), 22*60, 6*60, SESS_DAYS_ALL,
                          SZ_UTC, 0, false, 120, SDST_EU, 0, ds, sU, eU);
   Ck("overnight 02:00Z is inside", in);
   CkI("overnight dayStamp = Jun 10", ds, 20260610);
   CkDt("overnight start = Jun 10 22:00Z", sU, DT(2026,6,10,22,0));
   CkDt("overnight end   = Jun 11 06:00Z", eU, DT(2026,6,11,6,0));
   in = SessWindowAt(DT(2026,6,11,7,0), 22*60, 6*60, SESS_DAYS_ALL,
                     SZ_UTC, 0, false, 120, SDST_EU, 0, ds, sU, eU);
   Ck("07:00Z is outside the overnight window", !in);

   //--- the week mask lives in the ZONE's weekday: Tokyo Mon 09:00 JST
   in = SessWindowAt(DT(2026,6,8,3,0), 9*60, 18*60, SESS_DAYS_WEEKDAYS,
                     SZ_TOKYO, 0, false, 120, SDST_EU, 0, ds, sU, eU);
   Ck("Tokyo Monday 12:00 JST is inside (weekday mask)", in);
   CkI("Tokyo dayStamp = Jun 8", ds, 20260608);
   CkDt("Tokyo start = Jun 8 00:00Z (09:00 JST)", sU, DT(2026,6,8,0,0));
   in = SessWindowAt(DT(2026,6,13,3,0), 9*60, 18*60, SESS_DAYS_WEEKDAYS,
                     SZ_TOKYO, 0, false, 120, SDST_EU, 0, ds, sU, eU);
   Ck("Tokyo Saturday 12:00 JST is outside (weekday mask)", !in);

   //--- next boundary: weekday 09:00-17:00 UTC
   bool isOpen;
   datetime b = SessNextBoundaryUtc(DT(2026,6,10,12,0), 9*60, 17*60, SESS_DAYS_WEEKDAYS,
                                    SZ_UTC, 0, false, 120, SDST_EU, 0, isOpen);
   Ck("Wed noon is open", isOpen);
   CkDt("next boundary = Wed 17:00Z", b, DT(2026,6,10,17,0));
   b = SessNextBoundaryUtc(DT(2026,6,13,12,0), 9*60, 17*60, SESS_DAYS_WEEKDAYS,
                           SZ_UTC, 0, false, 120, SDST_EU, 0, isOpen);
   Ck("Saturday noon is closed", !isOpen);
   CkDt("next open = Monday 09:00Z", b, DT(2026,6,15,9,0));

   //--- mask bit order is ISO: Mon=bit0 ... Sun=bit6
   CkI("mask bit Monday = 0", SessMaskBitOfDow(1), 0);
   CkI("mask bit Sunday = 6", SessMaskBitOfDow(0), 6);
   CkI("mask bit Saturday = 5", SessMaskBitOfDow(6), 5);

   //--- AUTO broker mode: the live delta wins over the declared base
   CkI("AUTO off = live delta", SessBrokerOffMinAt(true, 120, SDST_EU, 195, DT(2026,1,15,8,0)), 195);

   Print("[SESSTEST] RESULT: ", g_pass, " pass / ", g_fail, " fail");
   if(g_fail == 0) Alert("[SESSTEST] ALL PASS (", g_pass, ")");
   else            Alert("[SESSTEST] FAILURES: ", g_fail);
}
