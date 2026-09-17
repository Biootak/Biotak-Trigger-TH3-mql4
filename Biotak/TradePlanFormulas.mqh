//+------------------------------------------------------------------+
//|                                        TradePlanFormulas.mqh     |
//|                                                                  |
//| Trade-plan formulas (TRex right-side block) - SINGLE SOURCE OF   |
//| TRUTH. Reverse-engineered from the professor's TRex screenshots   |
//| (XAUUSD all 8 TFs Sep-4 + Sep-9-2026, confirmed live).           |
//|                                                                  |
//| UNIFIED FORMULA (all 8 TFs, confirmed Sep-9-2026):               |
//|   SL(TF) = round(1.20 × Eng(StructureTF))                        |
//|   Eng(TF) = TR_composite(OWN TF) / 4.266666  (R-ENGPARITY,       |
//|             constant TRADEPLAN_ENG_DIVISOR — ONE formula, no input)|
//|   Hunter  = round(8/3 × Eng)                                     |
//|   Structure = 2 ladder rungs UP; Trigger = 2 rungs DOWN.         |
//|                                                                  |
//|   Evidence (2026-09-10 evening rig, tools/eng_own_window.js):     |
//|   Eng is a LONG-HORIZON measure per chart TF, not a short trigger |
//|   window. The divisor reproduces all six of his SL-derived        |
//|   XAUUSD legs {M15 16.515, H1 39.854, H4 87.766, D1 252.338,      |
//|   W1 600, MN 982.978} within {+13,+4,-4,+2,-3,-10}% and keeps     |
//|   Eng(M1)!=Eng(M5)!=Eng(M15) (P-TRADEPLAN-02). The legacy         |
//|   iATR(triggerTF, TF_min/trig_min, 1)/pip (a ONE-chart-bar window,| 
//|   -39% on W1, -33% on D1, -50% on EURUSD W1) is RETIRED by user   |
//|   decision 2026-09-10 (R-ENGONE): one formula only.              |
//|                                                                  |
//|   ALT experimental path (opt-in inpUseAltTradeFormulas, default   |
//|   OFF): SL = TR(chart)*1.66666, Eng = TR/4.266666, Hunt =        |
//|   TR/1.66666 — TP/SB still derive from slTrue.                   |
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

// Eng divisor (R-ENGPARITY 2026-09-10): Eng(TF) = TR_composite(own TF) / this.
// 64/15 — hard-coded by user decision (2026-09-10): NO input knob, one formula.
#define TRADEPLAN_ENG_DIVISOR  4.266666

// EXPERIMENTAL alt formulas (opt-in via inpUseAltTradeFormulas, user
// 2026-09-10): chart-TF based, uniform everywhere — SL = TR*1.66666,
// Eng = TR/4.266666, Hunt = TR/1.66666. Default OFF. TP/SB keep deriving
// from slTrue ("rest uniform").
#define TRADEPLAN_ALT_SL_MULT  1.66666
#define TRADEPLAN_ALT_ENG_DEN  4.266666
#define TRADEPLAN_ALT_HUNT_DEN 1.66666

// Hunter = 8/3 × Eng (unrounded Eng input).
// Eng and Hunter — the two legs a KNOT is measured with — carry ONE DECIMAL
// (USER 2026-09-16: «engsl , huntsl تا یک رقم اعشار پشتیبانی بکنه»); SL/TP/SB
// stay whole pips, so the professor's verified integers and the Eng parity that
// produces them are untouched. TradePlanRound1 owns that precision.
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

// ─────────────────────────────────────────────────────────────────────────────
// EngSL / HuntSL PRECISION — ONE DECIMAL (user 2026-09-16).
// W H Y: a whole-pip round turns a real low-TF size into 0. On EURUSD the M1
// composite is ~1.4 pips, so Eng = 1.4/4.266666 = 0.34 -> round -> 0, and 0 is
// the pump's word for "no EngSL pushed for this TF": the knot then sizes itself
// by the box' own height instead of by the plan. One decimal keeps the size the
// plan actually published (0.3), which is small but real and checkable.
// W H A T   S T A Y S: SL/TP1..TP3/SB are WHOLE pips by construction — they are
// the numbers verified against the professor's screenshots (XAUUSD 20/48/105/
// 303/720/1180, EURUSD M1 SL=2), and Eng is still TR_composite/4.266666 with no
// floor, no TH and no cap. Only the ROUNDING of the two knot legs changed.
// 0 stays the ABSENCE value: a TF the pump never pushed keeps it, and the box
// keeps saying so (BaseKnotEntryWhy / BaseKnotRiskTag).
double TradePlanRound1(const double x) { return MathRound(x * 10.0) / 10.0; }

// Composite ATR of a specific TF in symbol pips. Returns 0 when not ready.
// Calls CalculateWeightedATR (ATRCalculations.mqh) — the Trex SMA composite
// (weights 1/1/2/3/5/8 over periods 5/10/21/66/132/264, W1/MN overrides;
// P-ATR-02), shift=1 on every leg. Same source the strip display uses.
//
// P-BK-79 (2026-09-17): `anchor` IS THE BAR THE PLAN IS READ AT. 0 (the default, and
// every caller that does not pass one) = the LIVE read, byte-identical to before. A
// datetime = P-BK-79's as-of read, so a knot's EngSL/HuntSL/SL/TP are the ones the
// market showed when the knot happened instead of the ones it shows now — the user's
// own report («atr … با گذشت زمان ممکن 40 بشه یا 10 بشه»).
double TradePlanStripPips(const int tfMinutes, const datetime anchor = 0)
{
   double pip = GetCachedPipSize();
   if(IsZero(pip, EPSILON_PRICE)) return 0.0;
   ENUM_TIMEFRAMES tf = CompatTF(tfMinutes);
   double atr = (anchor > 0 ? CalculateWeightedATRAt(tf, anchor) : CalculateWeightedATR(tf));
   if(atr <= 0.0 || atr == EMPTY_VALUE) return 0.0;
   return atr / pip;
}

// ─────────────────────────────────────────────────────────────────────────────
// ENG — ONE formula (R-ENGPARITY, user decision 2026-09-10, R-ENGONE):
//   Eng(TF) = TR_composite(OWN TF) / TRADEPLAN_ENG_DIVISOR
//   Long-horizon by construction (the composite is a 5..264-bar blend) and
//   per-chart-TF, so Eng(M1) != Eng(M5) != Eng(M15) — the constraint the
//   2026-09-09 fix (P-TRADEPLAN-02) was built on. No selector, no legacy
//   path: the old iATR(triggerTF, TF_min/trig_min, 1)/pip (a one-chart-bar
//   window that matched gold only through XAUUSD's persistent vol, and missed
//   W1/D1 by -39%/-33%, EURUSD W1 by -50%) is retired — see git history and
//   P-ATR-05 if it ever needs to come back.
//
//   Trigger ladder (kept for labels only): M1←M1 M5←M1 M15←M1 H1←M5
//   H4←M15 D1←H1 W1←H4 MN←D1
// ─────────────────────────────────────────────────────────────────────────────
double TradePlanEngTrue(const int chartMinutes, int &trigMinOut, const datetime anchor = 0)
{
   int cm = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   trigMinOut = TradePlanTriggerMinutes(cm);

   double tr = TradePlanStripPips(cm, anchor);      // own-TF composite TR
   return (tr > 0.0) ? tr / TRADEPLAN_ENG_DIVISOR : 0.0;
}

// EngOf(TF): Eng of any TF (used by SL engine for the structure TF).
double TradePlanEngOf(const int tfMinutes, const datetime anchor = 0)
{
   int dummy = 0;
   return TradePlanEngTrue(tfMinutes, dummy, anchor);
}

// Legacy alias.
double TradePlanCompositeEngOf(const int tfMinutes, const datetime anchor = 0)
{
   return TradePlanEngOf(tfMinutes, anchor);
}

// SL = 1.20 × Eng(StructureTF). Unrounded. 0 when not ready.
// W1/MN structure clamps to MN; Eng(MN) = TR_composite(MN)/divisor (parity,
// R-ENGPARITY) naturally produces the macro SL — no special cap needed.
double TradePlanSLTrue(const int chartMinutes, const datetime anchor = 0)
{
   int strMin = TradePlanStructureMinutes(chartMinutes);
   double engStr = TradePlanEngOf(strMin, anchor);
   if(engStr <= 0.0) return 0.0;
   return TRADEPLAN_SL_COEFF * engStr;
}

// HuntSL in PIPS at 0.1 precision. The input stays the UNROUNDED Eng, so the diagonal
// theorem SB_Width(TF) == Hunter(StructureTF) keeps holding (both sides round 8/3 × the
// same engStr double).
double TradePlanHunterFromEng(const double engTrue)
{
   return TradePlanRound1(TRADEPLAN_HUNTER_NUM * engTrue / TRADEPLAN_HUNTER_DEN);
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
   double hunter, eng; // EngSL / HuntSL: 0.1 pip precision (TradePlanRound1)
   int    sb1, sb2;    // StrBond display legs (group layout, see below)
};

// MASTER IDENTITY (diagonal theorem, observed Sep-9-2026):
//   round(SB1(TF)) == round(Hunter(StructureTF)) == round(SL × 20/9)
// Because: 1.20 × 20/9 = 8/3, so both sides round the same double (Hunter keeps a
// decimal now, SB stays whole — the identity is checked on the WHOLE pip).
// Observed: H1 SB1 673 == D1 Hunter 673; M5 SB1 109 == H1 Hunter 109.

// Full computation. SL = 1.2 × Eng(StructureTF).
// All TP/Hunter/SB legs derive from unrounded slTrue / engTrue; Eng/Hunter keep ONE
// decimal (TradePlanRound1) while SL/TP/SB stay whole pips.
// P-BK-79: `anchor` (0 = live) is handed to EVERY measure this plan takes, so an as-of
// plan is the same plan read at another bar — never a mix of past and present.
bool TradePlanCompute(const int chartMinutes, STradePlan &p, const datetime anchor = 0)
{
   p.valid    = false;
   p.chartMin = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   p.strMin   = TradePlanStructureMinutes(p.chartMin);

   p.basePips = 0.0; p.ownPips = 0.0; p.slTrue = 0.0; p.engTrue = 0.0;
   p.sl = 0; p.tp1 = 0; p.tp2 = 0; p.tp3 = 0;
   p.hunter = 0.0; p.eng = 0.0; p.sb1 = 0; p.sb2 = 0;

   // Own strip ATR first: the alt path below derives EVERYTHING from it.
   p.ownPips = TradePlanStripPips(p.chartMin, anchor);

   bool altForm = (inpUseAltTradeFormulas && p.ownPips > 0.0);
   if(altForm)
   {
      // --- Alt experimental (opt-in): SL = TR*1.66666, Eng = TR/4.266666 ---
      // TP/SB below keep deriving from slTrue unchanged ("rest uniform").
      p.basePips = p.ownPips;   // base column shows the source, not structure Eng
      p.engTrue  = p.ownPips / TRADEPLAN_ALT_ENG_DEN;
      p.slTrue   = p.ownPips * TRADEPLAN_ALT_SL_MULT;
   }
   else
   {
      // --- SL = 1.20 × Eng(StructureTF) ---
      p.basePips = TradePlanEngOf(p.strMin, anchor);   // SessionEng of structure TF
      if(p.basePips <= 0.0) return false;
      p.slTrue = TRADEPLAN_SL_COEFF * p.basePips;
   }
   if(p.slTrue <= 0.0) return false;

   p.sl  = TradePlanRound(p.slTrue);
   p.tp1 = TradePlanRound(p.slTrue * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN);
   p.tp2 = TradePlanRound(p.slTrue * TRADEPLAN_TP2_MULT);
   p.tp3 = TradePlanRound(p.slTrue * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN);

   // --- Eng / Hunter (chart's own trigger TF) ---
   if(altForm)
   {
      // HuntSL = TR/1.66666 — independent leg, NOT 8/3×Eng (the alt triple
      // does not share the ladder's Hunter identity: 0.6/0.234375 = 2.56).
      p.trigMin  = TradePlanTriggerMinutes(p.chartMin);  // label only, no iATR call
      p.eng      = TradePlanRound1(p.engTrue);
      p.hunter   = TradePlanRound1(p.ownPips / TRADEPLAN_ALT_HUNT_DEN);
   }
   else
   {
      double eT = TradePlanEngTrue(p.chartMin, p.trigMin, anchor);
      if(eT <= 0.0) return false;
      p.engTrue = eT;
      p.eng     = TradePlanRound1(eT);
      p.hunter  = TradePlanHunterFromEng(eT);
   }

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

// Rounding-integrity self-check: every displayed leg must sit within half a
// STEP of its unrounded engine value (SL/TP/SB: half a pip; Eng/Hunter: half of
// their 0.1 pip). Symbol-free (catches wiring
// regressions on any symbol without knowing market numbers in advance).
bool TradePlanSelfCheck(const STradePlan &p)
{
   if(!p.valid) return false;
   if(MathAbs(p.sl  - p.slTrue) > 0.5001) return false;
   if(MathAbs(p.tp1 - p.slTrue * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN) > 0.5001) return false;
   if(MathAbs(p.tp2 - p.slTrue * TRADEPLAN_TP2_MULT) > 0.5001) return false;
   if(MathAbs(p.tp3 - p.slTrue * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN) > 0.5001) return false;
   if(MathAbs(p.eng - p.engTrue) > 0.0501) return false;   // 0.1 pip legs: half a step
   if(MathAbs(p.hunter - TRADEPLAN_HUNTER_NUM * p.engTrue / TRADEPLAN_HUNTER_DEN) > 0.0501) return false;
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

// P-BK-79: the freeze key carries the ANCHOR, or an as-of plan would be served the live
// plan's frozen legs (and vice versa) whenever the two share a bar and a symbol.
bool TradePlanComputeLive(const int chartMinutes, STradePlan &p, const datetime anchor = 0)
{
   if(!TradePlanCompute(chartMinutes, p, anchor)) return false;
   datetime bar0 = iTime(Symbol(), Period(), 0);
   string key = Symbol() + "|" + IntegerToString(Period()) + "|" + TimeToString(bar0) +
                "|" + IntegerToString((long)anchor);
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
