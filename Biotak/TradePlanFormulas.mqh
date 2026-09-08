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
//| GetATRForTimeframe / GetEffectiveTimeframe) and AFTER             |
//| PerformanceOptimizations.mqh (GetCachedPipSize). No includes      |
//| here - the entry .mq4 composes the graph bottom-up.               |
//+------------------------------------------------------------------+
#ifndef TRADE_PLAN_FORMULAS_MQH
#define TRADE_PLAN_FORMULAS_MQH

#property strict

// Plan multiples: SL/TP = base * (6, 14, 30, 62) = 2 * (3, 7, 15, 31),
// the same doubling family as the top-strip TH * (3, 7, 15).
#define TRADEPLAN_SL_MULT   6.0
#define TRADEPLAN_TP1_MULT 14.0
#define TRADEPLAN_TP2_MULT 30.0
#define TRADEPLAN_TP3_MULT 62.0
// Hunter = 8/3 * Eng (exact on every screenshot, up to rounding).
#define TRADEPLAN_HUNTER_NUM 8.0
#define TRADEPLAN_HUNTER_DEN 3.0
// StrBond leg 2 = 190/3 * base = TP3 + 4/3 * base.
#define TRADEPLAN_SB2_NUM  190.0
#define TRADEPLAN_SB2_DEN    3.0
// W1 fallback (no 2-above TF): StrBond leg 1 = 32 * base.
#define TRADEPLAN_W1_SB1_MULT 32.0
// Plan engine never looks above D1 (professor trades <= D1;
// MN/W1/D1 charts all show the daily plan).
#define TRADEPLAN_MAX_PLAN_MINUTES 1440

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

// Plan engine TF: chart TF capped at D1.
int TradePlanBaseMinutes(const int chartMinutes)
{
   int m = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   if(m > TRADEPLAN_MAX_PLAN_MINUTES) m = TRADEPLAN_MAX_PLAN_MINUTES;
   return m;
}

// Steps back for the Eng trigger + its odd multiplier (1 / 3 / 5).
// Same ladder as GetTriggerDurationSeconds (two steps down, M1 floor).
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

// Two ladder steps above, or -1 when missing (W1 / MN top out).
int TradePlanUpperMinutes(const int chartMinutes)
{
   int up = TradePlanLadderIndex(chartMinutes) + 2;
   if(up > 7) return -1;
   return TradePlanLadderMinutes(up);
}

int TradePlanRound(const double x) { return (int)MathRound(x); }

// ATR of a ladder TF, in symbol pips. 0 when not ready.
double TradePlanATRPips(const int tfMinutes)
{
   double pip = GetCachedPipSize();
   if(IsZero(pip, EPSILON_PRICE)) return 0.0;
   double atr = GetATRForTimeframe(tfMinutes);
   if(atr <= 0.0 || atr == EMPTY_VALUE) return 0.0;
   return atr / pip;
}

//+------------------------------------------------------------------+
//| Trade-plan value set for one chart TF.                            |
//+------------------------------------------------------------------+
struct STradePlan
{
   bool   valid;
   int    chartMin;    // floored chart TF
   int    planMin;     // engine TF for SL/TP + StrBond leg 2
   int    trigMin;     // engine TF for Eng
   double basePips;    // plan ATR, pips, unrounded
   double engTrue;     // Eng, pips, unrounded (Hunter derives from THIS)
   int    sl, tp1, tp2, tp3;
   int    hunter, eng;
   int    sb1, sb2;
};

// Eng engine: odd multiplier x trigger-TF ATR (verified on all 8 TFs).
void TradePlanEngTrue(const int chartMinutes, double &engTrueOut, int &trigMinOut)
{
   int back = TradePlanTriggerBack(chartMinutes);
   trigMinOut = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes) - back);
   engTrueOut = (2 * back + 1) * TradePlanATRPips(trigMinOut);
}

int TradePlanHunterFromEng(const double engTrue)
{
   return TradePlanRound(TRADEPLAN_HUNTER_NUM * engTrue / TRADEPLAN_HUNTER_DEN);
}

// Full computation. Uses ONLY ATR + pip size: correct on every symbol.
bool TradePlanCompute(const int chartMinutes, STradePlan &p)
{
   p.valid    = false;
   p.chartMin = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   p.planMin  = TradePlanBaseMinutes(p.chartMin);
   p.trigMin  = TradePlanTriggerMinutes(p.chartMin);
   p.basePips = 0.0; p.engTrue = 0.0;
   p.sl = 0; p.tp1 = 0; p.tp2 = 0; p.tp3 = 0;
   p.hunter = 0; p.eng = 0; p.sb1 = 0; p.sb2 = 0;

   p.basePips = TradePlanATRPips(p.planMin);
   if(p.basePips <= 0.0) return false;
   p.sl  = TradePlanRound(TRADEPLAN_SL_MULT  * p.basePips);
   p.tp1 = TradePlanRound(TRADEPLAN_TP1_MULT * p.basePips);
   p.tp2 = TradePlanRound(TRADEPLAN_TP2_MULT * p.basePips);
   p.tp3 = TradePlanRound(TRADEPLAN_TP3_MULT * p.basePips);

   double eT = 0.0; int tM = 0;
   TradePlanEngTrue(p.chartMin, eT, tM);
   if(eT <= 0.0) return false;
   p.engTrue = eT;
   p.eng     = TradePlanRound(eT);
   p.hunter  = TradePlanHunterFromEng(eT);

   p.sb2 = TradePlanRound(TRADEPLAN_SB2_NUM * p.basePips / TRADEPLAN_SB2_DEN);

   int up = TradePlanUpperMinutes(p.chartMin);
   if(up > 0)
   {
      double eU = 0.0; int tU = 0;
      TradePlanEngTrue(up, eU, tU);
      if(eU <= 0.0) return false;
      p.sb1 = TradePlanHunterFromEng(eU);
   }
   else if(p.chartMin >= 43200)
      p.sb1 = p.sb2 + p.hunter;                        // MN fallback (observed)
   else
      p.sb1 = TradePlanRound(TRADEPLAN_W1_SB1_MULT * p.basePips); // W1 fallback (observed)

   p.valid = true;
   return true;
}

// Rounding-integrity self-check (symbol-free): every displayed int must
// sit within half a pip of its engine value. Catches wiring regressions
// on ANY symbol without knowing the market numbers in advance.
bool TradePlanSelfCheck(const STradePlan &p)
{
   if(!p.valid) return false;
   if(MathAbs(p.sl  - TRADEPLAN_SL_MULT  * p.basePips) > 0.5001) return false;
   if(MathAbs(p.tp1 - TRADEPLAN_TP1_MULT * p.basePips) > 0.5001) return false;
   if(MathAbs(p.tp2 - TRADEPLAN_TP2_MULT * p.basePips) > 0.5001) return false;
   if(MathAbs(p.tp3 - TRADEPLAN_TP3_MULT * p.basePips) > 0.5001) return false;
   if(MathAbs(p.eng - p.engTrue) > 0.5001) return false;
   if(MathAbs(p.hunter - TRADEPLAN_HUNTER_NUM * p.engTrue / TRADEPLAN_HUNTER_DEN) > 0.5001) return false;
   if(MathAbs(p.sb2 - TRADEPLAN_SB2_NUM * p.basePips / TRADEPLAN_SB2_DEN) > 0.5001) return false;
   if(TradePlanUpperMinutes(p.chartMin) < 0)
   {
      if(p.chartMin >= 43200)
      {
         if(p.sb1 != p.sb2 + p.hunter) return false;
      }
      else if(MathAbs(p.sb1 - TRADEPLAN_W1_SB1_MULT * p.basePips) > 0.5001) return false;
   }
   return true;
}

#endif // TRADE_PLAN_FORMULAS_MQH
