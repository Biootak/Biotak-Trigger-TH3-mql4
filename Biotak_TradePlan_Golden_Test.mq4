//+------------------------------------------------------------------+
//|                              Biotak_TradePlan_Golden_Test.mq4    |
//|                                  Copyright 2026, Biotak Project  |
//|                                                                  |
//|  Golden + live regression test for the TRex trade-plan chain.     |
//|                                                                  |
//|  STANDALONE ON PURPOSE: this script re-implements the published   |
//|  formula chain from scratch (no project includes), so it can      |
//|  never "pass" just because it shares a bug with the EA.           |
//|                                                                  |
//|  PART A - static golden vectors: the professor's XAUUSD table     |
//|           (Sep-9-2026, live, all 8 TFs) must fall out of the      |
//|           chain when his Eng ladder is fed in.                    |
//|                                                                  |
//|  PART B - live wiring check on the attached symbol, mirroring the  |
//|           ONE Eng formula (R-ENGPARITY, 2026-09-10, R-ENGONE):     |
//|           Eng(TF) = TR_own(TF) / 4.266666, plus two symbol-free    |
//|           invariants the professor's ladder satisfies:             |
//|           (1) Eng(M1) != Eng(M5) != Eng(M15) — the 2026-09-09       |
//|               08:24 regression collapsed them onto one per-trigger  |
//|               composite (EURUSD printed 1.04/1.04);               |
//|           (2) the parity ladder climbs monotonically M15..MN        |
//|               (his XAUUSD ladder 16.5 < 39.9 < 87.8 < 252 < 600    |
//|               < 983).                                              |
//|                                                                  |
//|  Usage: attach to any chart (XAUUSD M1 preferred), read the       |
//|         Experts tab. Every line is prefixed [TPGOLD].             |
//+------------------------------------------------------------------+
#property strict
#property copyright "Biotak Project"
#property description "Golden test for the TRex trade-plan formulas (8 TFs)"

#define LADDER 8

//--- ladder: M1 M5 M15 H1 H4 D1 W1 MN (minutes)
int LadMinutes(const int i)
{
   switch(i)
   {
      case 0: return 1;
      case 1: return 5;
      case 2: return 15;
      case 3: return 60;
      case 4: return 240;
      case 5: return 1440;
      case 6: return 10080;
      case 7: return 43200;
   }
   return 1;
}

string LadName(const int i)
{
   switch(i)
   {
      case 0: return "M1";
      case 1: return "M5";
      case 2: return "M15";
      case 3: return "H1";
      case 4: return "H4";
      case 5: return "D1";
      case 6: return "W1";
      case 7: return "MN";
   }
   return "??";
}

//--- trigger = 2 rungs down (floor M1); structure = 2 rungs up (cap MN)
int TrigIndex(const int i) { int t = i - 2; return (t < 0 ? 0 : t); }
int StrIndex (const int i) { int s = i + 2; return (s > LADDER - 1 ? LADDER - 1 : s); }

int RInt(const double x) { return (int)MathRound(x); }

//--- pip rule mirrors GetCachedPipSize(): gold 0.1, JPY 0.01, 5-digit FX 0.0001
double PipLocal()
{
   int    d  = (int)MarketInfo(Symbol(), MODE_DIGITS);
   double pt = MarketInfo(Symbol(), MODE_POINT);
   if(d == 2 || d == 3 || d == 5) return pt * 10.0;
   return pt;
}

//+------------------------------------------------------------------+
//| THE CHAIN (single source of truth, mirrored from the master doc)  |
//|   slRaw = 1.20 * Eng(StructureTF)          <- UNROUNDED           |
//|   SL    = round(slRaw)                                            |
//|   TP1/TP2/TP3 = round(slRaw * 7/3, 5, 31/3)  <- from slRaw        |
//|   Hunter = round(Eng(own) * 8/3)             <- from raw Eng      |
//|   Base   = round(slRaw * 95/9)  Width = round(slRaw * 20/9)       |
//|   display: M1..D1 "Width -- Base" | W1 "round(slRaw*16/3) -- Base"|
//|            MN "(Base+Width) -- Base"  <- sum of the ROUNDED legs  |
//+------------------------------------------------------------------+
void Chain(const double engOwn, const double engStr, const int rung,
           int &eng, int &hunter, int &sl,
           int &tp1, int &tp2, int &tp3, int &sb1, int &sb2)
{
   double slRaw = 1.20 * engStr;

   eng    = RInt(engOwn);
   hunter = RInt(engOwn * 8.0 / 3.0);

   sl  = RInt(slRaw);
   tp1 = RInt(slRaw * 7.0  / 3.0);
   tp2 = RInt(slRaw * 5.0);
   tp3 = RInt(slRaw * 31.0 / 3.0);

   int base  = RInt(slRaw * 95.0 / 9.0);
   int width = RInt(slRaw * 20.0 / 9.0);

   sb2 = base;
   if(rung == 7)      sb1 = base + width;                 // MN
   else if(rung == 6) sb1 = RInt(slRaw * 16.0 / 3.0);      // W1
   else               sb1 = width;                         // M1..D1
}

//+------------------------------------------------------------------+
//| GOLDEN DATA - professor XAUUSD Sep-9-2026 (live screenshots)      |
//|                                                                  |
//| GEng = his UNROUNDED Eng ladder, solved back out of the rounded   |
//| cells (every one of SL/TP1/TP2/TP3/Hunter/Base/Width pins a       |
//| half-unit window; the intersection is what is stored here):       |
//|   M15 16.492..16.539 | H1 39.829..39.879 | H4 87.750..87.782      |
//|   D1 252.321..252.355 | W1 599.961..600.039 | MN 982.944..983.013 |
//+------------------------------------------------------------------+
double GEng [LADDER] = { 3.800, 7.900, 16.515, 39.854, 87.766, 252.338, 600.000, 982.978 };
int    GEngI[LADDER] = {     4,     8,     17,     40,     88,     252,     600,     983 };
int    GHunt[LADDER] = {    10,    21,     44,    106,    234,     673,    1600,    2621 };
int    GSL  [LADDER] = {    20,    48,    105,    303,    720,    1180,    1180,    1180 };
int    GTP1 [LADDER] = {    46,   112,    246,    707,   1680,    2752,    2752,    2752 };
int    GTP2 [LADDER] = {    99,   239,    527,   1514,   3600,    5898,    5898,    5898 };
int    GTP3 [LADDER] = {   205,   494,   1089,   3129,   7440,   12189,   12189,   12189 };
int    GSB1 [LADDER] = {    44,   106,    234,    673,   1600,    2621,    6291,   15072 };
int    GSB2 [LADDER] = {   209,   505,   1111,   3196,   7600,   12451,   12451,   12451 };
// M15 is the only row whose own cells disagree by 0.04 pip (TP3 needs
// slRaw >= 105.339, his Base=1111 needs slRaw <= 105.300) - live tick timing
// between the frozen SB leg and the TP legs. Tolerance 1 unit on that row only.
int    GTol [LADDER] = {     0,     0,      1,      0,      0,       0,       0,       0 };

int g_fail = 0;

void Chk(const string tf, const string leg, const int got, const int want, const int tol)
{
   if(MathAbs(got - want) <= tol) return;
   g_fail++;
   Print(StringFormat("[TPGOLD] FAIL %-3s %-6s got %d expected %d (tol %d)",
                      tf, leg, got, want, tol));
}

//+------------------------------------------------------------------+
//| PARITY ENG MIRROR (R-ENGPARITY): Eng(TF) = TR_composite(own)/divisor|
//| Re-implemented from scratch (same weights/periods as the engine, so |
//| a drift in EITHER side shows up as a mismatch in the printed row).  |
//+------------------------------------------------------------------+
#define ENG_DIVISOR 4.266666
#define ATR_LEGS    6

int g_legPeriod[ATR_LEGS] = {  5, 10,  21,  66, 132, 264};
int g_legWeight[ATR_LEGS] = {  1,  1,   2,   3,   5,   8};

// Mirrors TrexSMALeg: plain TR mean over `period` bars at shift 1, with the
// newest-bar quirk (bar 1's own close is its "previous" close).
double SmaLeg(const int tfMin, const int period)
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)tfMin;
   double trSum = 0.0;
   for(int i = 0; i < period; i++)
   {
      double h     = iHigh (Symbol(), tf, 1 + i);
      double l     = iLow  (Symbol(), tf, 1 + i);
      double cPrev = (i == 0) ? iClose(Symbol(), tf, 1 + i)
                              : iClose(Symbol(), tf, 1 + i + 1);
      double tr    = MathMax(h - l, MathMax(MathAbs(h - cPrev), MathAbs(l - cPrev)));
      trSum += tr;
   }
   return trSum / (double)period;
}

// Mirrors CalculateWeightedATR + CalculateATRBatchTrex (W1/MN overrides).
double CompositeTR(const int tfMin)
{
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)tfMin;
   int nb = iBars(Symbol(), tf);
   if(nb <= 10) return 0.0;

   if(tfMin == 43200)   // MN override: iATR(MN,30,1)
   {
      if(nb <= 31) return 0.0;
      double m = iATR(Symbol(), tf, 30, 1);
      return (m == EMPTY_VALUE || m <= 0.0) ? 0.0 : m;
   }
   if(tfMin == 10080)   // W1 override: iATR(W1,55,1)
   {
      if(nb <= 56) return 0.0;
      double w = iATR(Symbol(), tf, 55, 1);
      return (w == EMPTY_VALUE || w <= 0.0) ? 0.0 : w;
   }

   double sum = 0.0;
   int    tw  = 0;
   for(int i = 0; i < ATR_LEGS; i++)
   {
      if(nb <= g_legPeriod[i] + 1) continue;
      double v = SmaLeg(tfMin, g_legPeriod[i]);
      if(v <= 0.0) continue;
      sum += v * g_legWeight[i];
      tw  += g_legWeight[i];
   }
   return (tw > 0) ? sum / (double)tw : 0.0;
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("[TPGOLD] ================ TRex trade-plan golden test ================");

   //================================================================
   // PART A - static golden vectors
   //================================================================
   int eng, hunter, sl, tp1, tp2, tp3, sb1, sb2;
   int rowsOK = 0;

   Print("[TPGOLD] PART A | professor XAUUSD Sep-9-2026 replay");
   Print("[TPGOLD] TF  | Eng Hunter |   SL   TP1   TP2    TP3 |   SB1    SB2");

   for(int i = 0; i < LADDER; i++)
   {
      int before = g_fail;
      Chain(GEng[i], GEng[StrIndex(i)], i, eng, hunter, sl, tp1, tp2, tp3, sb1, sb2);

      Print(StringFormat("[TPGOLD] %-3s | %3d %6d | %4d %5d %5d %6d | %5d %6d",
                         LadName(i), eng, hunter, sl, tp1, tp2, tp3, sb1, sb2));

      Chk(LadName(i), "Eng",    eng,    GEngI[i], 0);
      Chk(LadName(i), "Hunter", hunter, GHunt[i], 0);
      Chk(LadName(i), "SL",     sl,     GSL  [i], 0);
      Chk(LadName(i), "TP1",    tp1,    GTP1 [i], GTol[i]);
      Chk(LadName(i), "TP2",    tp2,    GTP2 [i], GTol[i]);
      Chk(LadName(i), "TP3",    tp3,    GTP3 [i], GTol[i]);
      Chk(LadName(i), "SB1",    sb1,    GSB1 [i], GTol[i]);
      Chk(LadName(i), "SB2",    sb2,    GSB2 [i], GTol[i]);

      if(g_fail == before) rowsOK++;
   }
   Print(StringFormat("[TPGOLD] PART A rows clean: %d/%d", rowsOK, LADDER));

   //--- diagonal theorem: SB_Width(TF) == Hunter(StructureTF)
   for(int i = 0; i < 6; i++)   // M1..D1 show Width as SB1
   {
      double slRaw = 1.20 * GEng[StrIndex(i)];
      int width    = RInt(slRaw * 20.0 / 9.0);
      int huntStr  = RInt(GEng[StrIndex(i)] * 8.0 / 3.0);
      if(width != huntStr)
      {
         g_fail++;
         Print(StringFormat("[TPGOLD] FAIL diagonal %s: Width %d != Hunter(%s) %d",
                            LadName(i), width, LadName(StrIndex(i)), huntStr));
      }
   }

   //================================================================
   // PART B - live wiring on the attached symbol
   //================================================================
   double pip = PipLocal();
   Print(StringFormat("[TPGOLD] PART B | %s pip=%.5f digits=%d divisor=%.6f",
                      Symbol(), pip, (int)MarketInfo(Symbol(), MODE_DIGITS), ENG_DIVISOR));

   double trOwn [LADDER] = {0, 0, 0, 0, 0, 0, 0, 0};
   double engPar[LADDER] = {0, 0, 0, 0, 0, 0, 0, 0};  // Eng = TR_own / divisor (the engine's ONLY Eng, R-ENGONE)

   for(int i = 0; i < LADDER; i++)
   {
      trOwn[i]  = CompositeTR(LadMinutes(i)) / pip;
      engPar[i] = (trOwn[i] > 0.0) ? trOwn[i] / ENG_DIVISOR : 0.0;

      Print(StringFormat("[TPGOLD] %-3s | TRown %9.2f | Eng %8.3f -> %d",
                         LadName(i), trOwn[i], engPar[i], RInt(engPar[i])));
   }

   //--- regression detector 1: M1/M5/M15 must stay DISTINCT
   bool ready = (engPar[0] > 0.0 && engPar[1] > 0.0 && engPar[2] > 0.0);
   if(!ready)
      Print("[TPGOLD] WARN M1/M5/M15 history not ready - distinctness check skipped");
   else if(engPar[0] == engPar[1] || engPar[1] == engPar[2] || engPar[0] == engPar[2])
   {
      g_fail++;
      Print("[TPGOLD] FAIL Eng(M1)/Eng(M5)/Eng(M15) are NOT distinct -> Eng collapsed onto one "
            "per-trigger number again (2026-09-09 08:24 regression). Professor shows 4 / 8 / 17.");
   }
   else
      Print("[TPGOLD] OK   Eng(M1)/Eng(M5)/Eng(M15) distinct (per-own-TF composite)");

   //--- regression detector 2: parity ladder must climb M15..MN
   for(int i = 2; i < LADDER - 1; i++)
   {
      if(engPar[i] <= 0.0 || engPar[i + 1] <= 0.0) continue;
      if(engPar[i + 1] < engPar[i])
      {
         g_fail++;
         Print(StringFormat("[TPGOLD] FAIL parity ladder not monotone: %s %.3f >= %s %.3f "
                            "(professor: 16.5 < 39.9 < 87.8 < 252 < 600 < 983 on XAUUSD)",
                            LadName(i), engPar[i], LadName(i + 1), engPar[i + 1]));
      }
   }

   //--- full live plan table for eyeballing against the screenshots
   Print("[TPGOLD] live plan | TF  | Eng Hunter |   SL   TP1   TP2    TP3 |   SB1    SB2");
   for(int i = 0; i < LADDER; i++)
   {
      if(engPar[i] <= 0.0 || engPar[StrIndex(i)] <= 0.0) continue;
      Chain(engPar[i], engPar[StrIndex(i)], i, eng, hunter, sl, tp1, tp2, tp3, sb1, sb2);
      Print(StringFormat("[TPGOLD] live      | %-3s | %3d %6d | %4d %5d %5d %6d | %5d %6d",
                         LadName(i), eng, hunter, sl, tp1, tp2, tp3, sb1, sb2));
   }

   if(g_fail == 0) Print("[TPGOLD] RESULT: PASS - chain matches the professor and the wiring is sane.");
   else            Print(StringFormat("[TPGOLD] RESULT: FAIL - %d check(s) broken.", g_fail));
}
//+------------------------------------------------------------------+
