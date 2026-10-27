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
//|   TP1..TP4 = round(slTrue × 7/3, 5, 31/3, 30)   (P-TP4, 4 targets)|
//|   Card legs: TRex=Eng, Trigger=Hunter, Pricicle=5×Eng,           |
//|              Classic=12×Eng                     (P-TP4)          |
//|                                                                  |
//|   Evidence (2026-09-10 evening rig, tools/research/eng_own_window.js):     |
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

// ─────────────────────────────────────────────────────────────────────────────
// P-TP4 (2026-10-19) — THE FOURTH TARGET, and the card's two extra legs.
//
// The master's card carries FOUR targets and FOUR legs:
//   `#TP1:+20  #TP2:+43  #TP3:+89  #TP4:+259`
//   `TRex: 4  Trigger: 10  Pricicle: 19  Classic: 46`
//
// THE LEGS — solved on TWO cards (EURUSD, his own numbers):
//   chart  Eng   1×     8/3×   5×     12×    | his card
//   H1     3.80  3.80   10.13  19.00  45.60  | 4   10   19   46
//   H4     7.27  7.27   19.39  36.33  87.20  | 7   19   36   87
// Eight cells, two unknowns, every one on its integer. So the four legs are
// ONE ruler (the chart's own Eng) times 1, 8/3, 5, 12:
//   TRex = Eng | Trigger = 8/3 × Eng | Pricicle = 5 × Eng | Classic = 12 × Eng
// A first reading (Pricicle = 20/9 × slTrue, Classic = 16/3 × slTrue) also hit
// the H1 card, and the H4 card KILLED it: it printed 86 / 207 where he shows
// 36 / 87. The legs hang off Eng, never off SL — that is what the second card
// proved, and it is why these constants are multipliers of Eng.
//
// THE TARGETS — CLOSED (2026-10-19 21:43, his NZDUSD H1 card).
//   His own ATR row on that chart reads H1 7.8 and H4 17.5. Two numbers in,
//   eight card cells out, every one on his integer:
//     Eng 7.8/4.266666 = 1.828 -> 1.8 / 4.9 / 9 / 22   (his 1.8 4.9 9 22)
//     SL  1.2 x 17.5/4.266666 = 4.921875
//       -> TP 11.48 / 24.61 / 50.86 / 147.66           (his 11 25 51 148)
//   So TP4 = 30 x slTrue is CONFIRMED, not fitted: it was the only cell the
//   EURUSD cards of 2026-10-19 could not settle (their TP4 are 52 and 99,
//   which do not follow 30x their own base — those two cards are excluded).
//   Pinned at zero tolerance in tests/Biotak_TradePlan_Golden_Test.mq4 PART D.
// ─────────────────────────────────────────────────────────────────────────────
#define TRADEPLAN_TP4_MULT  30.0
#define TRADEPLAN_PRICE_MULT    5.0    // Pricicle = 5 × Eng(chart)
#define TRADEPLAN_CLASSIC_MULT 12.0    // Classic  = 12 × Eng(chart)

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

// Structure TF: TRADEPLAN_STRUCT_RUNGS rungs up, clamped to rung 7 (MN).
//
// P-TP4-RUNG (2026-10-19) — ONE RUNG, NOT TWO. The master's Oct-2026 card
// (four targets) takes its base one rung up; his Sep-2026 card (three targets)
// took two. Measured on three of his own EURUSD cards, all four targets:
//   H1 : 1.2 × Eng(H4) 7.25 = 8.70 -> TP 20.3 / 43.5 / 89.9 / 261  vs his 20 / 43 / 90 / 260
//   M15: 1.2 × Eng(H1) 3.75 = 4.50 -> TP 10.5 / 22.5 / 46.5        vs his 10 / 22 / 45
//   M5 : 1.2 × Eng(M15)1.58 = 1.90 -> TP  4.4 /  9.5 / 19.6        vs his  5 / 10 / 20
// Two rungs gives exactly DOUBLE on H1 (40 / 86 / 178 / 516) — the error the
// user reported. His H4 card is excluded on purpose: its four targets need four
// different bases (13.3 / 16.0 / 18.4 / 14.3), i.e. that card is not one plan.
// The Sep table is still pinned in the golden test at rung 2 (generation 1);
// this constant selects generation 2.
#define TRADEPLAN_STRUCT_RUNGS 1

int TradePlanStructureMinutes(const int chartMinutes)
{
   int idx = TradePlanLadderIndex(chartMinutes);
   int strIdx = idx + TRADEPLAN_STRUCT_RUNGS;
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

// ─────────────────────────────────────────────────────────────────────────────
// P-LEGATR — THE LEG READ: the composite BEFORE the compression run.
// The professor's ATR defect: the live composite averages the trailing CP bars,
// so inside a CP it reads the CP's own sleep instead of the leg's power. The
// as-of composite (CalculateWeightedATRAt, ATR_A.mqh:1223) already reads any bar;
// the only missing piece is WHICH bar: the first expansion bar behind the
// trailing compression run (the "negative shift" by hand: shift = CP length).
// The run test is range-only (High-Low < liveRef/2) — a DETECTOR, never the
// measure (the measure stays the Trex composite, P-ATR-02, one ruler).
// THE SCAN SKIPS THE BASE BAR (starts at shift 2): the breakout bar itself is
// the leg's first bar — «حرکت بعد از سی پی یک لگ هستش» — so its stops ride the
// pre-squeeze power, not the depressed live the squeeze leaves behind. Inside
// an ongoing squeeze both starts agree (the base bar joins the run).
// COST: zero when OFF (one bool). When ON: ≤ LEGATR_MAX_SCAN × 2 series reads
// per TF, once per TF-bar (bar-count cache below); a still frame is reads only.
// No CP found (trending / cold history) = 0 = the live read, byte-identical.
// ─────────────────────────────────────────────────────────────────────────────
#define LEGATR_MAX_SCAN 48   // bars walked back, closed bars only (shift >= 2, base skipped)
static int      s_legAtrBars[TRADEPLAN_LADDER_SIZE];
static datetime s_legAtrAnchor[TRADEPLAN_LADDER_SIZE];
static bool     s_legAtrKnown[TRADEPLAN_LADDER_SIZE];
static int      s_legAtrRun[TRADEPLAN_LADDER_SIZE];   // trailing compression-run length of the last scan

datetime TradePlanLegAnchorRaw(const int tfMinutes)
{
   int idx = TradePlanLadderIndex(tfMinutes);
   if(idx < 0 || idx >= TRADEPLAN_LADDER_SIZE) idx = 0;
   ENUM_TIMEFRAMES tf = CompatTF(TradePlanLadderMinutes(idx));
   int nb = iBars(Symbol(), tf);
   if(nb <= 10) return 0;
   if(s_legAtrKnown[idx] && s_legAtrBars[idx] == nb) return s_legAtrAnchor[idx];
   datetime ans = 0;
   int smallN = 0;
   double ref = CalculateWeightedATRLive(tf);   // the ATR layer's own per-TF-bar cache — detector stays LIVE
   if(ref > 0.0)
   {
      double small = ref * 0.5;
      // Start at shift 2: shift 1 is the base bar the ref window is read at —
      // testing it would mute the anchor on the breakout bar itself (P-LEGATR).
      for(int s = 2; s <= LEGATR_MAX_SCAN + 1; s++)
      {
         if(s >= nb) break;
         double h = iHigh(Symbol(), tf, s);
         double l = iLow(Symbol(), tf, s);
         if(h <= 0.0 || l <= 0.0 || h < l) break;   // history hole: live fallback
         if(h - l < small) { smallN++; continue; }
         if(smallN > 0) ans = iTime(Symbol(), tf, s);   // first big bar behind the run
         break;
      }
   }
   s_legAtrBars[idx] = nb; s_legAtrAnchor[idx] = ans; s_legAtrKnown[idx] = true;
   s_legAtrRun[idx] = smallN;
   return ans;
}

// The gated read the plan uses. OFF = 0 = the live read, zero series reads.
// Raw (above) is the detector alone — the X-dump witness reads it so an
// "ON changes nothing" report names its anchor instead of guessing.
datetime TradePlanLegAnchor(const int tfMinutes)
{
   if(!inpUseLegATR) return 0;   // OFF: zero reads, the live path below is untouched
   return TradePlanLegAnchorRaw(tfMinutes);
}

// Trailing compression-run length of the last scan (X-dump witness only).
int TradePlanLegRunBars(const int tfMinutes)
{
   int idx = TradePlanLadderIndex(tfMinutes);
   if(idx < 0 || idx >= TRADEPLAN_LADDER_SIZE) return 0;
   return s_legAtrRun[idx];
}

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
   // P-UI-57: a non-finite pip/ATR passes every `<= 0` test (all NaN compares
   // are false) and would poison the whole plan — same finite-first gate as
   // the input validators, zero cost on valid data (two compares, no syscalls).
   if(!MathIsValidNumber(pip) || IsZero(pip, EPSILON_PRICE)) return 0.0;
   ENUM_TIMEFRAMES tf = CompatTF(tfMinutes);
   // P-LEGATR: an explicit anchor (knot as-of reads) always wins. A live read
   // with the switch ON resolves to the leg anchor; OFF or no CP found = live.
   datetime eff = anchor;
   // P-ANCHOR-LAST (2026-10-27, DELIBERATE): the LAST OBJECT switch has NO vote here.
   // It used to stand in this guard, so pressing it picked the plan's ATR source and
   // re-stepped the drawn levels — the one thing it must never move. A label lever
   // moves labels. An explicit per-box anchor (P-BK-79) still wins over P-LEGATR; the
   // chart-wide switch is not a source selector at all.
   if(eff <= 0 && inpUseLegATR) eff = TradePlanLegAnchor(tfMinutes);
   double atr = (eff > 0 ? CalculateWeightedATRAt(tf, eff) : CalculateWeightedATR(tf));
   if(!MathIsValidNumber(atr) || atr <= 0.0 || atr == EMPTY_VALUE) return 0.0;
   return atr / pip;
}

// P-BK-130 (2026-10-27) — A KNOT'S OWN MINUTES IS NOT A RUNG.
//
// P-BK-126 said it for the type's ladder («a knot's time is not a rung»), and it scaled the
// off-ladder row instead of renaming one. The PLAN kept the other half of the bug: every
// price it hands out was read through `TradePlanLadderMinutes(TradePlanLadderIndex(x))`, so a
// 360-minute ask silently became a 240-minute read.
// MEASURED on the user's own 6h FTR box (`nodeTF 6h`, h = 373.6 pips): the note printed
// `ATR 6h: 324.9` while the header printed `H4: 324.9` — ONE number under two names — and all
// four legs are that number times their own constant (TRex 15/64 = 76.2, Trigger 5/8 = 203.1,
// Pricle 75/64 = 381, Classic 45/16 = 914). So a 6h knot was priced as an H4 knot: entry,
// stop and every target, from one wrong read.
//
// THE RULE, and it is one sentence: read the ATR at the minutes the caller ASKED FOR whenever
// MT4 carries that series, and let the rung below answer only when it does not — `CompatTF`
// answers PERIOD_CURRENT for exactly the lengths with no series (8, 45, 700 minutes), and those
// are SCALED by the project's √-law (P-BK-131 below), never jumped to the chart's own TF and
// never left wearing the rung's number. A rung asks for a rung, so every on-ladder caller is
// byte-identical (the ladder's round trip returns its own minutes).
// COST: an on-ladder ask pays one switch compare and no read; an off-ladder ask pays ONE new
// cache row per (TF, anchor) — the live path is `g_multiTFCache` by TF, the as-of path is
// `g_atrAnchorCache` by (TF, anchor) — and a hit on every round after the first.
double TradePlanATROfOwnTime(const int chartMinutes, const datetime anchor = 0)
{
   ENUM_TIMEFRAMES own = CompatTF(chartMinutes);   // PERIOD_CURRENT == no series for this length
   if(own != PERIOD_CURRENT)
   {
      double v = TradePlanStripPips(chartMinutes, anchor);
      if(MathIsValidNumber(v) && v > 0.0) return v;   // the knot's OWN minutes, read for real
   }
   // P-BK-131 (2026-10-27) — NO SERIES IS NOT NO ANSWER: ONE CONTINUOUS RULER.
   //
   // The fence above leaves a length MT4 has no bar for (8 / 45 / 700 minutes — his own note read
   // `700m`) with the rung below's NUMBER, i.e. a 700-minute knot priced as an H4 knot: the same
   // defect P-BK-130 fixed for 6h, one row over. A knot's price must be a CONTINUOUS function of
   // its own minutes or two knots cannot be compared at all.
   // SO: scale the rung below by the project's own √-law — the law P-BK-126 already applies to
   // the type's row (`BaseKnotRungScale`, BaseKnot_Nodes; `CalculateHybridATR`, ATR_A:378 before
   // it), so the plan and the table answer the SAME number for the same time and cannot drift.
   // MEASURED on his H4 row (324.9): 360 -> 397.9, 700 -> 554.9 (x1.7078), D1 stays 999.3 — one
   // monotone ladder where `700m` used to read 324.9 beside a DIFFERENT `ATR 700m:` in the note.
   // The rung itself never reaches here (it has a series), and a cold row still degrades to the
   // rung's own number rather than to a scaled zero.
   int below = TradePlanLadderMinutes(TradePlanLadderIndex(chartMinutes));
   double base = TradePlanStripPips(below, anchor);
   if(!MathIsValidNumber(base) || base <= 0.0) return base;    // cold: the old number, never nothing
   if(below <= 0 || chartMinutes <= below) return base;        // on the rung: nothing to scale
   double scaled = base * MathSqrt((double)chartMinutes / (double)below);
   return (MathIsValidNumber(scaled) && scaled > 0.0 ? scaled : base);
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
   trigMinOut = TradePlanTriggerMinutes(cm);          // label only: the trigger ladder's own rung

   // P-BK-130: the LABEL stays on the ladder slot (`cm`); the READ does not. A 6h ask that
   // came back as H4's composite priced every leg below it as an H4 leg.
   double tr = TradePlanATROfOwnTime(chartMinutes, anchor);   // the box' OWN minutes
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
   // P-UI-57: non-finite input would round into a garbage int — report absence.
   if(!MathIsValidNumber(engTrue)) return 0.0;
   return TradePlanRound1(TRADEPLAN_HUNTER_NUM * engTrue / TRADEPLAN_HUNTER_DEN);
}

// P-BK-120 (2026-10-22) — THE TARGET LEGS OFF ANY STOP, not just off the plan's own.
//
// The ratios above are the plan's law: TP1 = 7/3 × SL, TP2 = 5 × SL, TP3 = 31/3 × SL,
// where the plan's own SL is `slTrue = 1.2 × Eng(StructureTF)` of ONE chart TF.
//
// A BaseKnot box does NOT stop at that SL. P-BK-51/83 draws its stop as ONE EngSL of
// the node TYPE's own time, so on a CTR box the drawn risk is Eng(H1) while the plan
// of its base TF (M5) sizes its targets off Eng(M15). The user (2026-10-22): «tp های
// که رسم شده باید از همون محاسبات باشه» — the ticks belong to the box, so they must
// ride the box' own stop. This is that call: the SAME ratios, applied to whatever
// stop the caller actually drew.
//
// One owner: the ratios live here and nowhere else. The pump calls this per row and
// pushes the answer, because BaseKnotTool sits BELOW this module (the layer law).
int TradePlanTPFromEng(const double stopPips, const int k)
{
   if(!MathIsValidNumber(stopPips) || stopPips <= 0.0) return 0;   // P-UI-57: absence, never garbage
   if(k == 1) return TradePlanRound(stopPips * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN);
   if(k == 2) return TradePlanRound(stopPips * TRADEPLAN_TP2_MULT);
   if(k == 3) return TradePlanRound(stopPips * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN);
   if(k == 4) return TradePlanRound(stopPips * TRADEPLAN_TP4_MULT);
   return 0;
}

//+------------------------------------------------------------------+
//| Trade-plan value set for one chart TF.                            |
//+------------------------------------------------------------------+
struct STradePlan
{
   bool   valid;
   int    chartMin;    // floored chart TF (ladder rung)
   int    strMin;      // structure TF (TRADEPLAN_STRUCT_RUNGS up)
   int    trigMin;     // trigger TF for Eng (2 rungs down from chart)
   double basePips;    // Eng(StructureTF) — the input to SL
   double ownPips;     // chart-TF composite ATR (info/display only)
   double slTrue;      // unrounded SL = 1.2 × basePips — EVERY leg from THIS
   double engTrue;     // unrounded Eng (Hunter derives from THIS)
   int    sl, tp1, tp2, tp3, tp4;
   double hunter, eng; // EngSL / HuntSL: 0.1 pip precision (TradePlanRound1)
   int    sb1, sb2;    // StrBond display legs (group layout, see below)
   int    pricicle;    // card leg 3 — 20/9 × slTrue (P-TP4)
   int    classic;     // card leg 4 — 16/3 × slTrue (P-TP4)
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
   p.sl = 0; p.tp1 = 0; p.tp2 = 0; p.tp3 = 0; p.tp4 = 0;
   p.hunter = 0.0; p.eng = 0.0; p.sb1 = 0; p.sb2 = 0;
   p.pricicle = 0; p.classic = 0;

   // Own strip ATR first: the alt path below derives EVERYTHING from it.
   // P-BK-130: `p.chartMin` is the LADDER SLOT — what strMin / trigMin / the SB rule are
   // measured from — and it is NOT the ATR's time. The read is the caller's own minutes, so a
   // 6h box is priced on 6h and its note's `ATR 6h:` stops equalling the header's `H4:`.
   p.ownPips = TradePlanATROfOwnTime(chartMinutes, anchor);

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
      // P-UI-57: NaN passes `<= 0` (false), so finiteness is tested first —
      // otherwise a NaN ATR (gap/offline/D1-loading) would validate a plan of
      // garbage ints. Valid data pays two compares, nothing else.
      p.basePips = TradePlanEngOf(p.strMin, anchor);   // SessionEng of structure TF
      if(!MathIsValidNumber(p.basePips) || p.basePips <= 0.0) return false;
      p.slTrue = TRADEPLAN_SL_COEFF * p.basePips;
   }
   if(!MathIsValidNumber(p.slTrue) || p.slTrue <= 0.0) return false;

   p.sl  = TradePlanRound(p.slTrue);
   p.tp1 = TradePlanRound(p.slTrue * TRADEPLAN_TP1_NUM / TRADEPLAN_TP1_DEN);
   p.tp2 = TradePlanRound(p.slTrue * TRADEPLAN_TP2_MULT);
   p.tp3 = TradePlanRound(p.slTrue * TRADEPLAN_TP3_NUM / TRADEPLAN_TP3_DEN);
   p.tp4 = TradePlanRound(p.slTrue * TRADEPLAN_TP4_MULT);

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
      // P-BK-130: the Eng is read at the SAME minutes `ownPips` was (the box' own), or the
      // entry's stop and the legs' base would be two times on one ruler (P-BK-127).
      double eT = TradePlanEngTrue(chartMinutes, p.trigMin, anchor);
      // P-UI-57: finite-first (see the SL gate above) — NaN Eng must read as
      // "not ready", never as rounded garbage.
      if(!MathIsValidNumber(eT) || eT <= 0.0) return false;
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

   // P-TP4: the card's 3rd and 4th legs — the SAME chart Eng the other two legs
   // ride (5× and 12×), read off the UNROUNDED engTrue so a small Eng does not
   // lose its size to the first leg's one-decimal round. Whole pips, like SL/TP.
   p.pricicle = TradePlanRound(TRADEPLAN_PRICE_MULT   * p.engTrue);
   p.classic  = TradePlanRound(TRADEPLAN_CLASSIC_MULT * p.engTrue);

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
   if(MathAbs(p.tp4 - p.slTrue * TRADEPLAN_TP4_MULT) > 0.5001) return false;
   if(MathAbs(p.pricicle - TRADEPLAN_PRICE_MULT   * p.engTrue) > 0.5001) return false;
   if(MathAbs(p.classic  - TRADEPLAN_CLASSIC_MULT * p.engTrue) > 0.5001) return false;
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

// P-TP4-LIVE (2026-10-19) — THE PER-BAR FREEZE IS GONE.
//
// What it did: inside one chart bar it served the bar's OPENING SL/TP/SB plus
// the two Eng legs, while Eng/Hunter stayed live. That could only ever make the
// card disagree with itself if the ATR moved intra-bar.
//
// It does not, in the default path. `TradePlanCompute` reads the composite at
// shift 1, which is the last CLOSED bar — constant for the whole chart bar. So
// the freeze was a no-op in practice: NZDUSD H1 2026-10-19 showed the identical
// card at 21:43, 22:03 and 22:12, and removing the freeze changed nothing. The
// earlier theory that it cost 6% on the legs was WRONG and is not the reason.
//
// It is still removed, for two honest reasons:
//   (a) it cannot help — Compute has already run with the current ATR, so the
//       restore branch can only overwrite fresh integers with older ones;
//   (b) with `inpUseLegATR` ON the leg anchor CAN grow inside a bar (P-LEGATR),
//       and then the freeze would split one card across two moments for real.
//
// The remaining gap to the master is NOT here: it is the H1 ATR level itself
// (ours ~8.45 vs his 7.8 on that bar). See TradePlanAutoDump for the witness.
bool TradePlanComputeLive(const int chartMinutes, STradePlan &p, const datetime anchor = 0)
{
   return TradePlanCompute(chartMinutes, p, anchor);
}

#endif // TRADE_PLAN_FORMULAS_MQH
