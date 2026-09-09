//+------------------------------------------------------------------+
//|                                        TradePlanFormulas.mqh     |
//|                                                                  |
//| Trade-plan formulas (TRex right-side block) - SINGLE SOURCE OF   |
//| TRUTH. Reverse-engineered from the professor's TRex screenshots   |
//| (XAUUSD, all 8 timeframes, 2026-09-08/09) - see R-TRADEPLAN.     |
//|                                                                  |
//| UNIFIED FORMULA (confirmed all 8 TFs, 2026-09-09):               |
//|   SL(TF) = 1.20 × Eng(StructureTF)                               |
//|   Eng(TF)  = CompositeATR(TriggerOf(TF))   -- strip ATR, ×1      |
//|   Hunter   = round(8/3 × Eng)                                     |
//|   Structure = 2 ladder steps UP (mirrors Trigger 2 steps down);  |
//|   W1/MN chain to the D1 macro (their structure is MN, but macro   |
//|   caps to D1 SL = 1.2 × Eng(MN)).                                |
//|                                                                  |
//| Diagonal theorem (observed, not a recipe):                        |
//|   SB1(TF) == Hunter(StructureTF) -- both equal SL × 20/9.        |
//|                                                                  |
//| Symbol independence: every value derives from ATR (market data)   |
//| converted with the symbol-aware GetCachedPipSize(). No symbol-    |
//| specific constant lives here.                                     |
//|                                                                  |
//| LAYER: include AFTER ATRCalculations.mqh (uses GetATRForTimeframe |
//| and CalculateWeightedATR) and AFTER PerformanceOptimizations.mqh  |
//| (GetCachedPipSize). No includes here.                             |
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
// This constant holds for ALL timeframes (M1..MN) — no per-TF table.
// Verified on all 8 TFs, XAUUSD 2026-09-09.
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
// Calls CalculateWeightedATR (ATRCalculations.mqh) which uses iATR shift=1.
// Kept for niche callers; Eng always uses TradePlanSessionEng now.
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
// SESSION ENG — the professor's stable Eng formula (reverse-engineered Sep-9-2026
// from 8 XAUUSD screenshots, confirmed all 8 TFs with ≤1 pip rounding error):
//
//   Eng(TF) = iATR(triggerTF, TF_min / triggerTF_min, 1) / pip
//
// This is a single-bar Wilder ATR whose PERIOD = the number of trigger-TF candles
// that compose one bar of the chart TF.  Examples:
//   M1  trig=M1  period= 1/1= 1  → iATR(M1,  1,1)  ← M1 range
//   M5  trig=M1  period= 5/1= 5  → iATR(M1,  5,1)  ← 5-bar M1 ATR
//   M15 trig=M1  period=15/1=15  → iATR(M1, 15,1)
//   H1  trig=M5  period=60/5=12  → iATR(M5, 12,1)
//   H4  trig=M15 period=240/15=16 → iATR(M15,16,1)
//   D1  trig=H1  period=1440/60=24 → iATR(H1,24,1)
//   W1  trig=H4  period=10080/240=42 → iATR(H4,42,1)
//   MN  trig=D1  period=43200/1440=30 → iATR(D1,30,1)
//
// Why this is stable: iATR(triggerTF, N, shift=1) is frozen on the last CLOSED
// bar of triggerTF — it does NOT change until a new triggerTF bar closes.
// On H1 charts that is every 5 minutes; on D1 charts every hour. Much smoother
// than a live composite weighted ATR (which updates every tick).
//
// Diagonal identity (theorem, observed, not a recipe):
//   SL(TF) = 1.2 × Eng(StructureTF) = 1.2 × 1.2 × Eng(TF) = 1.44 × Eng(TF)
//   → SB1(TF) = Hunter(StructureTF), SB1 = SL×20/9 (unchanged).
// ─────────────────────────────────────────────────────────────────────────────
double TradePlanSessionEng(const int tfMinutes, int &trigMinOut)
{
   int cm      = TradePlanLadderMinutes(TradePlanLadderIndex(tfMinutes));
   trigMinOut  = TradePlanTriggerMinutes(cm);
   int trigMin = trigMinOut;
   if(trigMin <= 0) trigMin = 1;

   double pip = GetCachedPipSize();
   if(IsZero(pip, EPSILON_PRICE)) return 0.0;

   int period = cm / trigMin;          // e.g. H1/M5 = 60/5 = 12
   if(period < 1) period = 1;

   ENUM_TIMEFRAMES trigTF = (ENUM_TIMEFRAMES)trigMin;
   double v = iATR(Symbol(), trigTF, period, 1);
   return (v == EMPTY_VALUE || v <= 0.0) ? 0.0 : v / pip;
}

// TradePlanEngTrue: display Eng — now identical to SessionEng for all TFs.
// (Previous version had a composite-ATR path for M15+ which diverged from the
// professor's values. Now one formula covers all 8 rungs.)
double TradePlanEngTrue(const int chartMinutes, int &trigMinOut)
{
   return TradePlanSessionEng(chartMinutes, trigMinOut);
}

// EngOf(TF): session Eng of any TF (used by SL engine for the structure TF).
// Replaces TradePlanCompositeEngOf which used composite-weighted ATR.
double TradePlanEngOf(const int tfMinutes)
{
   int dummy = 0;
   return TradePlanSessionEng(tfMinutes, dummy);
}

// Legacy alias kept for callers that may still reference the old name.
double TradePlanCompositeEngOf(const int tfMinutes)
{
   return TradePlanEngOf(tfMinutes);
}

// SL = 1.20 × SessionEng(StructureTF). Unrounded. 0 when not ready.
// W1/MN: structure clamps to MN; SessionEng(MN)=iATR(D1,30,1)/pip naturally
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
   double ownPips;     // chart-TF strip ATR (info only)
   double slTrue;      // unrounded SL — EVERY leg derives from THIS
   double engTrue;     // unrounded Eng (Hunter derives from THIS)
   int    sl, tp1, tp2, tp3;
   int    hunter, eng;
   int    sb1, sb2;    // StrBond display legs (group layout, see below)
};

// MASTER IDENTITY (theorem, not a recipe):
//   SB1(chart) == Hunter(StructureTF) == SL × 20/9
// Proof: SB1 = round(SL×20/9) = round(1.2×Eng(Str)×20/9)
//        Hunter(Str) = round(8/3 × Eng(Str) × 1.2 / 1.2) 
//        Both equal round(1.2 × Eng(Str) × 20/9) — same double, same round.
// Observed: H1 SB1 673 == D1 Hunter 673; M5 SB1 109 == H1 Hunter 109.

// Full computation. Uses ONLY strip ATR + pip size: correct on every symbol.
// All TP/Hunter/SB legs derive from unrounded slTrue / engTrue.
bool TradePlanCompute(const int chartMinutes, STradePlan &p)
{
   p.valid    = false;
   p.chartMin = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   p.strMin   = TradePlanStructureMinutes(p.chartMin);

   p.basePips = 0.0; p.ownPips = 0.0; p.slTrue = 0.0; p.engTrue = 0.0;
   p.sl = 0; p.tp1 = 0; p.tp2 = 0; p.tp3 = 0;
   p.hunter = 0; p.eng = 0; p.sb1 = 0; p.sb2 = 0;

   // --- SL from Structure (always composite ATR, never the short M1/M5 Eng) ---
   p.basePips = TradePlanCompositeEngOf(p.strMin); // composite ATR of structure's trigger
   if(p.basePips <= 0.0) return false;
   p.slTrue = TRADEPLAN_SL_COEFF * p.basePips;
   if(p.slTrue <= 0.0) return false;

   p.sl  = TradePlanRound(p.slTrue);
   p.tp1 = TradePlanRound(p.slTrue * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN);
   p.tp2 = TradePlanRound(p.slTrue * TRADEPLAN_TP2_MULT);
   p.tp3 = TradePlanRound(p.slTrue * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN);

   // --- Eng / Hunter (chart's own trigger, not structure's trigger) ---
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

   // Own strip ATR (composite, for reference — not used as a leg engine).
   // Session Eng (professor's formula) is already in p.engTrue.
   p.ownPips = TradePlanStripPips(p.chartMin);

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
