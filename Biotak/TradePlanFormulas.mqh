//+------------------------------------------------------------------+
//|                                        TradePlanFormulas.mqh     |
//|                                                                  |
//| Trade-plan formulas (TRex right-side block) - SINGLE SOURCE OF   |
//| TRUTH. Reverse-engineered from the professor's TRex screenshots   |
//| (XAUUSD, all 8 timeframes, 2026-09-08) - see R-TRADEPLAN.         |
//|                                                                  |
//| Symbol independence: every value derives from ATR (market data)   |
//| converted with the symbol-aware GetCachedPipSize() (gold / JPY /  |
//| 5-digit / 4-digit all handled there). NO symbol-specific          |
//| constant lives here - the same code is correct on every pair.     |
//|                                                                  |
//| LAYER: Calculation - include AFTER ATRCalculations.mqh (uses      |
//| GetATRForTimeframe) and AFTER                                     |
//| PerformanceOptimizations.mqh (GetCachedPipSize). No includes      |
//| here - the entry .mq4 composes the graph bottom-up.               |
//+------------------------------------------------------------------+
#ifndef TRADE_PLAN_FORMULAS_MQH
#define TRADE_PLAN_FORMULAS_MQH

#property strict

// Base-SL multiplier per (ladder) TF - professor's table (spec 2026-09-09).
// H1 rides Control (1.75), H4 rides LS (2.0); D1 and above share the daily
// macro leg (1.107 x D1 ATR: 1.107 x 1066 = 1180.06, observed). M30 and
// exotic TFs floor to M15 via the ladder.
// FLAG (forward-validation pending): 1.75 x same-bar H1 strip (176) = 308
// vs observed SL 303. Either SL freezes per chart bar (bar-open input
// ~173.1 reproduces 303 exactly - supported: SL/TP/SB static 27min in one
// bar while Eng/Hunter tracked the live trigger strip) or the H1 leg needs
// refit. See TradePlanComputeLive.
#define TRADEPLAN_SLM_M1   1.50
#define TRADEPLAN_SLM_M5   1.20
#define TRADEPLAN_SLM_M15  1.35
#define TRADEPLAN_SLM_H1   1.75
#define TRADEPLAN_SLM_H4   2.00
#define TRADEPLAN_SLM_D1   1.107
// TP legs ride UNROUNDED SL (rounding the rounded SL breaks TP3 by 2:
// 303*31/3 = 3131 vs observed 3129).
#define TRADEPLAN_TP1_NUM   7.0
#define TRADEPLAN_TP1_DEN   3.0
#define TRADEPLAN_TP2_MULT  5.0
#define TRADEPLAN_TP3_NUM  31.0
#define TRADEPLAN_TP3_DEN   3.0
// Hunter = 8/3 * Eng (exact on both verified blocks, up to rounding).
#define TRADEPLAN_HUNTER_NUM 8.0
#define TRADEPLAN_HUNTER_DEN 3.0
// Eng = trigger-TF SL / 1.2 == trigger strip ATR (the M5 1.2 cancels:
// H1 Eng = 1.2*ATR_M5/1.2; verified 43 == 43 on XAUUSD/H1).
#define TRADEPLAN_ENG_DEN  1.20
// StrBond from unrounded SL: Base = 95/9 * SL, Width = 20/9 * SL.
#define TRADEPLAN_SBB_NUM   95.0
#define TRADEPLAN_SBB_DEN    9.0
#define TRADEPLAN_SBW_NUM   20.0
#define TRADEPLAN_SBW_DEN    9.0
// W1 first leg rides SL * 16/3 (16/3 * 1179.6 = 6291.2 -> 6291 row).
#define TRADEPLAN_SBW1_NUM  16.0
#define TRADEPLAN_SBW1_DEN   3.0
// D1 and above share the daily macro plan (spec + D1 chain 1066->1180).
// Supersedes the per-TF W1/MN uncapping: W1/MN charts show the macro SL/TP
// with their own StrBond legs (see Compute).
#define TRADEPLAN_MACRO_MINUTES 1440

//+------------------------------------------------------------------+
//| Ladder position (floors exotic minutes down to the ladder).       |
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
   for(int i = 0; i < 8; i++)
   {
      if(TradePlanLadderMinutes(i) <= minutes) best = i;
      else break;
   }
   return best;
}

// Plan engine TF: chart TF with the daily macro cap (D1/W1/MN charts all
// run the D1 macro SL/TP; W1/MN keep their own StrBond legs in Compute).
int TradePlanBaseMinutes(const int chartMinutes)
{
   int m = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   if(m > TRADEPLAN_MACRO_MINUTES) m = TRADEPLAN_MACRO_MINUTES;
   return m;
}

// Trigger-TF mapping for Eng (two ladder steps down, M1 floor).
// Same ladder as GetTriggerDurationSeconds. Mapping only - Eng itself
// is 1x the strip ATR, no odd multiplier.
int TradePlanTriggerBack(const int chartMinutes)
{
   int back = TradePlanLadderIndex(chartMinutes);
   if(back > 2) back = 2;
   return back;
}

int TradePlanTriggerMinutes(const int chartMinutes)
{
   int i = TradePlanLadderIndex(chartMinutes);
   return TradePlanLadderMinutes(i - TradePlanTriggerBack(chartMinutes));
}

int TradePlanRound(const double x) { return (int)MathRound(x); }

// SL multiplier for ladder minutes (M30/exotics arrive pre-floored;
// anything >= D1 is the macro leg).
double TradePlanSLMult(const int tfMinutes)
{
   switch(tfMinutes)
   {
      case 1:   return TRADEPLAN_SLM_M1;
      case 5:   return TRADEPLAN_SLM_M5;
      case 15:  return TRADEPLAN_SLM_M15;
      case 60:  return TRADEPLAN_SLM_H1;
      case 240: return TRADEPLAN_SLM_H4;
      default:  return TRADEPLAN_SLM_D1;
   }
}

// Bottom-strip (composite) ATR in symbol pips. 0 when not ready.
double TradePlanStripPips(const int tfMinutes)
{
   double pip = GetCachedPipSize();
   if(IsZero(pip, EPSILON_PRICE)) return 0.0;
   double atr = GetATRForTimeframe(tfMinutes);
   if(atr <= 0.0 || atr == EMPTY_VALUE) return 0.0;
   return atr / pip;
}

// Unrounded base SL in pips for ladder minutes (macro-capped ATR, per-TF
// multiplier). 0 when not ready.
double TradePlanSLTrue(const int tfMinutes)
{
   int m = TradePlanLadderMinutes(TradePlanLadderIndex(tfMinutes));
   int useM = (m > TRADEPLAN_MACRO_MINUTES ? TRADEPLAN_MACRO_MINUTES : m);
   double a = TradePlanStripPips(useM);
   if(a <= 0.0) return 0.0;
   return TradePlanSLMult(m) * a;
}

//+------------------------------------------------------------------+
//| Trade-plan value set for one chart TF.                            |
//+------------------------------------------------------------------+
struct STradePlan
{
   bool   valid;
   int    chartMin;    // floored chart TF
   int    planMin;     // engine TF for SL/TP (macro-capped at D1)
   int    trigMin;     // engine TF for Eng
   double basePips;    // plan-TF strip ATR, pips, unrounded
   double ownPips;     // chart-TF strip ATR, pips, unrounded (info only)
   double slTrue;      // unrounded base SL - EVERY leg derives from THIS
   double engTrue;     // Eng, pips, unrounded (Hunter derives from THIS)
   int    sl, tp1, tp2, tp3;
   int    hunter, eng;
   int    sb1, sb2;    // display legs (group layout, see Compute)
};

// Eng engine: trigger-TF SL / 1.2 (spec). The trigger leg's own 1.2
// cancels on M5, so H1 Eng == M5 strip ATR (verified 43 == 43).
void TradePlanEngTrue(const int chartMinutes, double &engTrueOut, int &trigMinOut)
{
   int back = TradePlanTriggerBack(chartMinutes);
   trigMinOut = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes) - back);
   double slTrig = TradePlanSLTrue(trigMinOut);
   engTrueOut = (slTrig > 0.0 ? slTrig / TRADEPLAN_ENG_DEN : 0.0);
}

int TradePlanHunterFromEng(const double engTrue)
{
   return TradePlanRound(TRADEPLAN_HUNTER_NUM * engTrue / TRADEPLAN_HUNTER_DEN);
}

// MASTER IDENTITY (professor's diagonal link, observed XAUUSD/H1 2026-09-09):
// SB1(chart) == Hunter(structure(chart)) holds EXACTLY here (same double,
// same round): SB1 = 20/9*SL(T) while Hunter(struct) = 8/3*Eng(struct) =
// 8/3*SL(trig(struct))/1.2, and trig(struct(T)) == T on M1..D1 (2-down undoes
// 2-up; W1/MN share the macro SL). Likewise SL(T) == 1.2*Eng(struct(T)) is a
// THEOREM of this code, not a computation recipe - written as one it is
// circular (SL(M1) = ... = SL(M1)), so the exogenous input stays the strip
// ATRs. Observed: H1 SB1 673 == D1 Hunter 673; H1 Hunter 109 == M5 SB1 109.

// Full computation. Uses ONLY strip ATR + pip size: correct on every symbol.
// All legs derive from unrounded slTrue (never from rounded ints).
bool TradePlanCompute(const int chartMinutes, STradePlan &p)
{
   p.valid    = false;
   p.chartMin = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   p.planMin  = TradePlanBaseMinutes(p.chartMin);
   p.trigMin  = TradePlanTriggerMinutes(p.chartMin);
   p.basePips = 0.0; p.ownPips = 0.0; p.slTrue = 0.0; p.engTrue = 0.0;
   p.sl = 0; p.tp1 = 0; p.tp2 = 0; p.tp3 = 0;
   p.hunter = 0; p.eng = 0; p.sb1 = 0; p.sb2 = 0;

   p.basePips = TradePlanStripPips(p.planMin);
   if(p.basePips <= 0.0) return false;
   p.slTrue = TradePlanSLMult(p.chartMin) * p.basePips;
   if(p.slTrue <= 0.0) return false;
   p.sl  = TradePlanRound(p.slTrue);
   p.tp1 = TradePlanRound(p.slTrue * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN);
   p.tp2 = TradePlanRound(p.slTrue * TRADEPLAN_TP2_MULT);
   p.tp3 = TradePlanRound(p.slTrue * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN);

   double eT = 0.0; int tM = 0;
   TradePlanEngTrue(p.chartMin, eT, tM);
   if(eT <= 0.0) return false;
   p.engTrue = eT;
   p.eng     = TradePlanRound(eT);
   p.hunter  = TradePlanHunterFromEng(eT);

   // StrBond display legs (spec groups). Base/Width ride unrounded SL;
   // the MN first leg sums the ROUNDED legs (12451 + 2621 = 15072, not the
   // rounded unrounded sum 15073).
   int bBase  = TradePlanRound(p.slTrue * TRADEPLAN_SBB_NUM / TRADEPLAN_SBB_DEN);
   int bWidth = TradePlanRound(p.slTrue * TRADEPLAN_SBW_NUM / TRADEPLAN_SBW_DEN);
   if(p.chartMin >= 43200)      { p.sb2 = bBase; p.sb1 = bBase + bWidth; }
   else if(p.chartMin >= 10080) { p.sb2 = bBase; p.sb1 = TradePlanRound(p.slTrue * TRADEPLAN_SBW1_NUM / TRADEPLAN_SBW1_DEN); }
   else                         { p.sb2 = bBase; p.sb1 = bWidth; }

   // Info only (never a leg engine now).
   p.ownPips = TradePlanStripPips(p.chartMin);

   p.valid = true;
   return true;
}

// Rounding-integrity self-check (symbol-free): every displayed int must
// sit within half a pip of its unrounded engine value. Catches wiring
// regressions on ANY symbol without knowing the market numbers in advance.
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
   if(p.chartMin >= 43200)      { if(MathAbs(p.sb1 - (MathRound(bBase) + MathRound(bWidth))) > 0.5001) return false; }
   else if(p.chartMin >= 10080) { if(MathAbs(p.sb1 - p.slTrue * TRADEPLAN_SBW1_NUM / TRADEPLAN_SBW1_DEN) > 0.5001) return false; }
   else                         { if(MathAbs(p.sb1 - bWidth) > 0.5001) return false; }
   return true;
}

// Slow/fast split with per-bar freeze (professor behavior, observed):
// SL/TP/SB held STATIC 27 minutes inside one H1 bar while Eng/Hunter
// tracked the live trigger strip tick-by-tick. So slow legs recompute
// only on a new chart bar; fast legs stay live every call. Key includes
// symbol+period, so TF switches and symbol changes recompute at once.
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
      p.sl = s_tpFzSL; p.tp1 = s_tpFzTP1; p.tp2 = s_tpFzTP2; p.tp3 = s_tpFzTP3;
      p.sb1 = s_tpFzSB1; p.sb2 = s_tpFzSB2; p.slTrue = s_tpFzSLTrue;
   }
   else
   {
      s_tpFzKey = key;
      s_tpFzSL = p.sl; s_tpFzTP1 = p.tp1; s_tpFzTP2 = p.tp2; s_tpFzTP3 = p.tp3;
      s_tpFzSB1 = p.sb1; s_tpFzSB2 = p.sb2; s_tpFzSLTrue = p.slTrue;
   }
   return true;
}

#endif // TRADE_PLAN_FORMULAS_MQH
