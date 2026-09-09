//+------------------------------------------------------------------+
//|                                        TradePlanFormulas.mqh     |
//|                                                                  |
//| Trade-plan formulas (TRex right-side block) - SINGLE SOURCE OF   |
//| TRUTH. Reverse-engineered from the professor's TRex screenshots   |
//| (XAUUSD all 8 TFs Sep-4 + Sep-9-2026, confirmed live).           |
//|                                                                  |
//| UNIFIED FORMULA (all 8 TFs, confirmed Sep-9-2026):               |
//|   SL(TF) = round(1.20 × Eng(StructureTF))                        |
//|   Eng(TF) = iATR(triggerTF, TF_min/trig_min, 1) / pip            |
//|   Hunter  = round(8/3 × Eng)                                     |
//|   Structure = 2 ladder rungs UP; Trigger = 2 rungs DOWN.         |
//|                                                                  |
//| Verified Sep-9-2026 XAUUSD (live screenshots, all 8 TFs):        |
//|   M1: 1.2×Eng(M15=17)=20.4→20 ✓                                 |
//|   M5: 1.2×Eng(H1=40)=48 ✓                                       |
//|   M15: 1.2×Eng(H4=88)=105.6→105 ✓                               |
//|   H1: 1.2×Eng(D1=252)=302.4→303 ✓                               |
//|   H4: 1.2×Eng(W1=600)=720 ✓                                     |
//|   D1/W1/MN: 1.2×Eng(MN=983)=1179.6→1180 ✓                      |
//|                                                                  |
//| Symbol independence: all values derive from ATR (market data)    |
//| converted with GetCachedPipSize(). No symbol-specific constants.  |
//|                                                                  |
//| LAYER: include AFTER ATRCalculations.mqh (CalculateWeightedATR)  |
//| and AFTER PerformanceOptimizations.mqh (GetCachedPipSize).       |
//+------------------------------------------------------------------+
#ifndef TRADE_PLAN_FORMULAS_MQH
#define TRADE_PLAN_FORMULAS_MQH

#property strict

// TP ratios (ride UNROUNDED slTrue — rounding the rounded SL breaks TP3
// by 2: 303*31/3=3131 vs observed 3129).
#define TRADEPLAN_TP1_NUM   7.0
#define TRADEPLAN_TP1_DEN   3.0
#define TRADEPLAN_TP2_MULT  5.0
#define TRADEPLAN_TP3_NUM  31.0
#define TRADEPLAN_TP3_DEN   3.0

// Unified SL coefficient: SL = 1.20 × Eng(StructureTF).
// One constant for ALL timeframes — confirmed Sep-9-2026 live XAUUSD.
#define TRADEPLAN_SL_COEFF  1.20

// Hunter = 8/3 × Eng (unrounded Eng input).
#define TRADEPLAN_HUNTER_NUM 8.0
#define TRADEPLAN_HUNTER_DEN 3.0

// StrBond: Base = 95/9 × SL, Width = 20/9 × SL.
// M1–D1 show "Width -- Base"; W1: "16/3*SL -- Base"; MN: "(Base+Width) -- Base"
// where MN first leg = sum of the ROUNDED legs (12451+2621=15072, not 15073).
#define TRADEPLAN_SBB_NUM   95.0
#define TRADEPLAN_SBB_DEN    9.0
#define TRADEPLAN_SBW_NUM   20.0
#define TRADEPLAN_SBW_DEN    9.0
#define TRADEPLAN_SBW1_NUM  16.0
#define TRADEPLAN_SBW1_DEN   3.0

// Ladder size (8 rungs: M1 M5 M15 H1 H4 D1 W1 MN).
#define TRADEPLAN_LADDER_SIZE 8

//+------------------------------------------------------------------+
//| Ladder helpers                                                    |
//+------------------------------------------------------------------+
int TradePlanLadderMinutes(const int i)
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

int TradePlanLadderIndex(const int minutes)
{
   int best = 0;
   for(int i = 0; i < TRADEPLAN_LADDER_SIZE; i++)
   {
      if(TradePlanLadderMinutes(i) <= minutes) best = i;
      else break;
   }
   return best;
}

// Trigger TF: 2 rungs down, clamped to rung 0 (M1).
int TradePlanTriggerMinutes(const int chartMinutes)
{
   int idx = TradePlanLadderIndex(chartMinutes);
   int trigIdx = idx - 2;
   if(trigIdx < 0) trigIdx = 0;
   return TradePlanLadderMinutes(trigIdx);
}

// Structure TF: 2 rungs up, clamped to rung 7 (MN).
int TradePlanStructureMinutes(const int chartMinutes)
{
   int idx = TradePlanLadderIndex(chartMinutes);
   int strIdx = idx + 2;
   if(strIdx >= TRADEPLAN_LADDER_SIZE) strIdx = TRADEPLAN_LADDER_SIZE - 1;
   return TradePlanLadderMinutes(strIdx);
}

int TradePlanRound(const double x) { return (int)MathRound(x); }

// Composite ATR of a specific TF in symbol pips. Returns 0 when not ready.
// Calls CalculateWeightedATR (ATRCalculations.mqh) — 6-period Wilder weighted
// average, shift=1 on every period leg, stable and not tick-volatile.
double TradePlanStripPips(const int tfMinutes)
{
   double pip = GetCachedPipSize();
   if(IsZero(pip, EPSILON_PRICE)) return 0.0;
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)tfMinutes;
   double atr = CalculateWeightedATR(tf);
   if(atr <= 0.0 || atr == EMPTY_VALUE) return 0.0;
   return atr / pip;
}

// ─────────────────────────────────────────────────────────────────────────────
// ENG = CompositeATR(triggerTF)
//
// Eng(TF) = TradePlanStripPips(TriggerOf(TF))
//         = weighted-avg iATR(shift=1) of 6 periods on the TRIGGER timeframe.
//
// This is the same value shown in the ATR top bar for the trigger TF —
// stable (weighted average, not a single-bar range), and the same number
// that the professor's indicator shows as Eng.SL for each chart TF.
//
// Trigger TF mapping (2 rungs down, clamped to M1):
//   M1  → M1   M5  → M1   M15 → M1
//   H1  → M5   H4  → M15  D1  → H1   W1  → H4   MN  → D1
// ─────────────────────────────────────────────────────────────────────────────
double TradePlanEngTrue(const int chartMinutes, int &trigMinOut)
{
   int cm     = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   trigMinOut = TradePlanTriggerMinutes(cm);
   return TradePlanStripPips(trigMinOut);
}

// EngOf(TF): Eng of any TF (used by SL engine for the structure TF).
double TradePlanEngOf(const int tfMinutes)
{
   int dummy = 0;
   return TradePlanEngTrue(tfMinutes, dummy);
}

// Legacy alias.
double TradePlanCompositeEngOf(const int tfMinutes)
{
   return TradePlanEngOf(tfMinutes);
}

// SL = 1.20 × SessionEng(StructureTF). Unrounded. 0 when not ready.
// W1/MN structure clamps to MN; SessionEng(MN)=iATR(D1,30,1)/pip naturally
// produces the macro SL — no special cap needed.
double TradePlanSLTrue(const int chartMinutes)
{
   int strMin = TradePlanStructureMinutes(chartMinutes);
   double engStr = TradePlanEngOf(strMin);
   if(engStr <= 0.0) return 0.0;
   return TRADEPLAN_SL_COEFF * engStr;
}

int TradePlanHunterFromEng(const double engTrue)
{
   return TradePlanRound(TRADEPLAN_HUNTER_NUM * engTrue / TRADEPLAN_HUNTER_DEN);
}

//+------------------------------------------------------------------+
//| Trade-plan value set for one chart TF.                            |
//+------------------------------------------------------------------+
struct STradePlan
{
   bool   valid;
   int    chartMin;    // floored chart TF (ladder rung)
   int    strMin;      // structure TF (2 rungs up)
   int    trigMin;     // trigger TF for Eng (2 rungs down from chart)
   double basePips;    // Eng(StructureTF) — the input to SL
   double ownPips;     // chart-TF composite ATR (info/display only)
   double slTrue;      // unrounded SL = 1.2 × basePips — EVERY leg from THIS
   double engTrue;     // unrounded Eng (Hunter derives from THIS)
   int    sl, tp1, tp2, tp3;
   int    hunter, eng;
   int    sb1, sb2;    // StrBond display legs (group layout, see below)
};

// MASTER IDENTITY (diagonal theorem, observed Sep-9-2026):
//   SB1(TF) == Hunter(StructureTF) == SL × 20/9
// Because: 1.20 × 20/9 = 8/3, so both sides round the same double.
// Observed: H1 SB1 673 == D1 Hunter 673; M5 SB1 109 == H1 Hunter 109.

// Full computation. SL = 1.2 × Eng(StructureTF).
// All TP/Hunter/SB legs derive from unrounded slTrue / engTrue.
bool TradePlanCompute(const int chartMinutes, STradePlan &p)
{
   p.valid    = false;
   p.chartMin = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   p.strMin   = TradePlanStructureMinutes(p.chartMin);

   p.basePips = 0.0; p.ownPips = 0.0; p.slTrue = 0.0; p.engTrue = 0.0;
   p.sl = 0; p.tp1 = 0; p.tp2 = 0; p.tp3 = 0;
   p.hunter = 0; p.eng = 0; p.sb1 = 0; p.sb2 = 0;

   // --- SL = 1.20 × Eng(StructureTF) ---
   p.basePips = TradePlanEngOf(p.strMin);   // SessionEng of structure TF
   if(p.basePips <= 0.0) return false;
   p.slTrue = TRADEPLAN_SL_COEFF * p.basePips;
   if(p.slTrue <= 0.0) return false;

   p.sl  = TradePlanRound(p.slTrue);
   p.tp1 = TradePlanRound(p.slTrue * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN);
   p.tp2 = TradePlanRound(p.slTrue * TRADEPLAN_TP2_MULT);
   p.tp3 = TradePlanRound(p.slTrue * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN);

   // Own strip ATR (composite, for reference/display — not the SL engine).
   p.ownPips = TradePlanStripPips(p.chartMin);

   // --- Eng / Hunter (chart's own trigger TF) ---
   double eT = TradePlanEngTrue(p.chartMin, p.trigMin);
   if(eT <= 0.0) return false;
   p.engTrue = eT;
   p.eng     = TradePlanRound(eT);
   p.hunter  = TradePlanHunterFromEng(eT);

   // --- StrBond display legs ---
   // Base and Width ride UNROUNDED slTrue; MN first leg is sum of rounded.
   int bBase  = TradePlanRound(p.slTrue * TRADEPLAN_SBB_NUM / TRADEPLAN_SBB_DEN);
   int bWidth = TradePlanRound(p.slTrue * TRADEPLAN_SBW_NUM / TRADEPLAN_SBW_DEN);
   if(p.chartMin >= 43200)       // MN: (Base+Width) -- Base
      { p.sb2 = bBase; p.sb1 = bBase + bWidth; }
   else if(p.chartMin >= 10080)  // W1: 16/3*SL -- Base
      { p.sb2 = bBase; p.sb1 = TradePlanRound(p.slTrue * TRADEPLAN_SBW1_NUM / TRADEPLAN_SBW1_DEN); }
   else                          // M1..D1: Width -- Base
      { p.sb2 = bBase; p.sb1 = bWidth; }

   p.valid = true;
   return true;
}

// Rounding-integrity self-check: every displayed int must sit within
// half a pip of its unrounded engine value. Symbol-free (catches wiring
// regressions on any symbol without knowing market numbers in advance).
bool TradePlanSelfCheck(const STradePlan &p)
{
   if(!p.valid) return false;
   if(MathAbs(p.sl  - p.slTrue) > 0.5001) return false;
   if(MathAbs(p.tp1 - p.slTrue * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN) > 0.5001) return false;
   if(MathAbs(p.tp2 - p.slTrue * TRADEPLAN_TP2_MULT) > 0.5001) return false;
   if(MathAbs(p.tp3 - p.slTrue * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN) > 0.5001) return false;
   if(MathAbs(p.eng - p.engTrue) > 0.5001) return false;
   if(MathAbs(p.hunter - TRADEPLAN_HUNTER_NUM * p.engTrue / TRADEPLAN_HUNTER_DEN) > 0.5001) return false;
   double bBase  = p.slTrue * TRADEPLAN_SBB_NUM / TRADEPLAN_SBB_DEN;
   double bWidth = p.slTrue * TRADEPLAN_SBW_NUM / TRADEPLAN_SBW_DEN;
   if(MathAbs(p.sb2 - bBase) > 0.5001) return false;
   if(p.chartMin >= 43200)
      { if(MathAbs(p.sb1 - ((int)MathRound(bBase) + (int)MathRound(bWidth))) > 0.5001) return false; }
   else if(p.chartMin >= 10080)
      { if(MathAbs(p.sb1 - p.slTrue * TRADEPLAN_SBW1_NUM / TRADEPLAN_SBW1_DEN) > 0.5001) return false; }
   else
      { if(MathAbs(p.sb1 - bWidth) > 0.5001) return false; }
   return true;
}

// Slow/fast split with per-bar freeze (professor behavior, observed):
// SL/TP/SB held STATIC inside one chart bar while Eng/Hunter track the
// live trigger strip tick-by-tick. So slow legs recompute only on a new
// chart bar; fast legs (Eng/Hunter) are always fresh. Key includes
// symbol+period so TF switches and symbol changes recompute at once.
string s_tpFzKey = "";
int s_tpFzSL = 0, s_tpFzTP1 = 0, s_tpFzTP2 = 0, s_tpFzTP3 = 0;
int s_tpFzSB1 = 0, s_tpFzSB2 = 0;
double s_tpFzSLTrue = 0.0;

bool TradePlanComputeLive(const int chartMinutes, STradePlan &p)
{
   if(!TradePlanCompute(chartMinutes, p)) return false;
   datetime bar0 = iTime(Symbol(), Period(), 0);
   string key = Symbol() + "|" + IntegerToString(Period()) + "|" + TimeToString(bar0);
   if(key == s_tpFzKey && s_tpFzKey != "")
   {
      // Restore frozen slow legs; keep live Eng/Hunter from fresh Compute.
      p.sl = s_tpFzSL; p.tp1 = s_tpFzTP1; p.tp2 = s_tpFzTP2; p.tp3 = s_tpFzTP3;
      p.sb1 = s_tpFzSB1; p.sb2 = s_tpFzSB2; p.slTrue = s_tpFzSLTrue;
   }
   else
   {
      s_tpFzKey    = key;
      s_tpFzSL     = p.sl;  s_tpFzTP1  = p.tp1; s_tpFzTP2  = p.tp2; s_tpFzTP3  = p.tp3;
      s_tpFzSB1    = p.sb1; s_tpFzSB2  = p.sb2; s_tpFzSLTrue = p.slTrue;
   }
   return true;
}

#endif // TRADE_PLAN_FORMULAS_MQH
