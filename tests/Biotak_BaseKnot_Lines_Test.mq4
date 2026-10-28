//+------------------------------------------------------------------+
//| Biotak_BaseKnot_Lines_Test.mq4                                   |
//| FOUR TYPES x THREE COMPONENTS — ENTRY / STOP / TP1..3.           |
//|                                                                  |
//| WHY THIS EXISTS. docs/baseknot-four-nodes.html claims three      |
//| things a green compile cannot prove:                             |
//|   1. the TYPE is one number (the box' height) against three      |
//|      ATR rows read at ONE anchor — cut at their RATIO midpoints   |
//|      √(a·b) since P-BK-128, so a 1-pip nudge cannot flip it;      |
//|   2. the two LEGS ride ONE rung — the deepest one whose whole      |
//|      package (off 5/8 + risk 15/64 of that rung's ATR) still fits  |
//|      inside the box (P-BK-128); the type NAME is only the         |
//|      fallback for a box nobody has read yet (a live preview);     |
//|   3. the THREE targets are that same rung's legs, measured from   |
//|      the entry line.                                             |
//|                                                                  |
//| This harness drives the PRODUCTION owners —                      |
//| BaseKnotNodeKindOfLength, BaseKnotEntryTFMin,                    |
//| BaseKnotMeasureTFMin, BaseKnotCalcLevels, BaseKnotTPLevel —      |
//| with four rows pushed by hand, and asserts all three components  |
//| for each of the four types, BUY and SELL.                        |
//|                                                                  |
//| RUN: drag onto any chart (EURUSD H1 is enough — every number is  |
//| in PIPS, so the symbol does not matter), then read the Experts   |
//| tab for the [BKLINES] lines and the closing DONE line.           |
//+------------------------------------------------------------------+
#property strict

#include "..\Biotak\BuildConfig.mqh"
#include "..\Biotak\MathConstants.mqh"
#include "..\Biotak\Logger.mqh"
#include "..\Biotak\Profiler.mqh"
#include "..\Biotak\PropertiesAndInputs.mqh"
#include "..\Biotak\ConstantsAndEnums.mqh"
#include "..\Biotak\ProjectConstants.mqh"
#include "..\Biotak\InputValidator.mqh"
#include "..\Biotak\FloatingPointHelper.mqh"
#include "..\Biotak\ObjectCountManager.mqh"
#include "..\Biotak\PerformanceOptimizations.mqh"
#include "..\Biotak\InputValidationEnhanced.mqh"
#include "..\Biotak\RuntimeSettings.mqh"
#include "..\Biotak\GlobalVariables.mqh"
#include "..\Biotak\UtilityFunctions.mqh"
#include "..\Biotak\BaseKnotTool.mqh"
#include "..\Biotak\HRayTool.mqh"
#include "..\Biotak\PathTool.mqh"
#include "..\Biotak\CalculationCache.mqh"
#include "..\Biotak\ZoneFactory.mqh"
#include "..\Biotak\ZoneConfig.mqh"
#include "..\Biotak\ZoneValidator.mqh"
#include "..\Biotak\ZoneConstants.mqh"
#include "..\Biotak\ObjectCache.mqh"
#include "..\Biotak\PropertyChangeDetector.mqh"
#include "..\Biotak\VisibilityManager.mqh"
#include "..\Biotak\TimeframeFunctions.mqh"
#include "..\Biotak\FractalTimeframes.mqh"
#include "..\Biotak\StandardTimeframes.mqh"
#include "..\Biotak\THCalculations.mqh"
#include "..\Biotak\ATRCalculations.mqh"
#include "..\Biotak\TradePlanFormulas.mqh"
#include "..\Biotak\AdaptiveScaling.mqh"
#include "..\Biotak\BasePriceManager.mqh"
#ifndef BUILD_LITE
#include "..\Biotak\WaveAnalysis.mqh"
#include "..\Biotak\FrequencyOptimizer.mqh"
#include "..\Biotak\TH3Tool.mqh"
#endif
#include "..\Biotak\ObjectFunctions.mqh"
#include "..\Biotak\DrawToolbar.mqh"
#include "..\Biotak\CardMetrics.mqh"
#include "..\Biotak\DrawStrip.mqh"
#include "..\Biotak\ExtendedDrawingFunctions.mqh"
#include "..\Biotak\ComboEngine.mqh"
#include "..\Biotak\FactorMode.mqh"
#include "..\Biotak\LevelPipeline.mqh"
#include "..\Biotak\ModeDefinitions.mqh"
#include "..\Biotak\LabelFunctions.mqh"
#include "..\Biotak\AlertFunctions.mqh"
#include "..\Biotak\HistoricalDataFunctions.mqh"
// P-SESS: sessions renderer — mirrors the entry's seat (before EventHandlers,
// whose coop pump calls SessionsTick).
#include "..\Biotak\Sessions_Time.mqh"
#include "..\Biotak\Sessions_Model.mqh"
#include "..\Biotak\Sessions_Draw.mqh"
#include "..\Biotak\EventHandlers.mqh"
#include "..\Biotak\HTFCandles.mqh"
#include "..\Biotak\BiotakKit.mqh"
#include "..\Biotak\BiotakMenu.mqh"
#include "..\Biotak\BiotakPanels.mqh"

int    g_bkPass = 0;
int    g_bkFail = 0;
double g_bkPip  = 0.0001;

//--- THE FOUR PUSHED ROWS, STATED HERE AND NOWHERE ELSE. The expected numbers below are
//--- literals off THIS table, never a read-back of the production readers: a harness that
//--- asks the code it is testing for the answer can only agree with it.
//---   node M5 · pattern M15 · structure H1 · one rung past H4
//---   EngSL 43.4 / 73.3 / 136.3 / 311.0 pips   (the four samples' own H1/H4 numbers)
//---   HuntSL = EngSL x 5/8, the plan's own leg
//---   TPk = round(EngSL x 7/3 | 5 | 31/3), the plan's three ratios
double BkRowEng(const int tf)
{
   if(tf == 5)   return 43.4;
   if(tf == 15)  return 73.3;
   if(tf == 60)  return 136.3;
   if(tf == 240) return 311.0;
   return 0.0;
}
double BkRowHunt(const int tf) { return BkRowEng(tf) * 5.0 / 8.0; }
double BkRowTP(const int tf, const int k)
{
   double e = BkRowEng(tf);
   double r = (k == 1 ? 7.0 / 3.0 : (k == 2 ? 5.0 : 31.0 / 3.0));
   return MathRound(e * r);
}
//--- the rung each type's STOP is read on (FTR +0, ETR +1, CTR +2, OTR +3)
int BkStopTF(const int kind)
{
   if(kind == BK_NODE_ETR) return 15;
   if(kind == BK_NODE_CTR) return 60;
   if(kind == BK_NODE_OTR) return 240;
   return 5;
}

bool BkNear(const double a, const double b) { return (MathAbs(a - b) < 0.005); }

void BkCheck(const string what, const bool ok, const double got, const double want)
{
   if(ok) { g_bkPass++; Print("[BKLINES] PASS  ", what, "  got=", DoubleToString(got, 2), "  want=", DoubleToString(want, 2)); }
   else   { g_bkFail++; Print("[BKLINES] FAIL  ", what, "  got=", DoubleToString(got, 2), "  want=", DoubleToString(want, 2)); }
}
// P-BK-129: the same report for a TEXT field — the note's TF spelling is a string, so a
// number-only checker would have to compare lengths instead of the name.
void BkCheckS(const string what, const string got, const string want)
{
   if(got == want) { g_bkPass++; Print("[BKLINES] PASS  ", what, "  got=", got, "  want=", want); }
   else            { g_bkFail++; Print("[BKLINES] FAIL  ", what, "  got=", got, "  want=", want); }
}

void BkPushRows(const datetime an)
{
   int      tfs[4]  = {5, 15, 60, 240};
   datetime ans[4];
   double   eng[4], hunt[4], t1[4], t2[4], t3[4];
   BaseKnotAbilityReset();                // the TYPE reads this table (ATR, PRICE units)
   for(int i = 0; i < 4; i++)
   {
      ans[i]  = an;
      eng[i]  = BkRowEng(tfs[i]);         // PIPS — BaseKnotEngPush's own unit
      hunt[i] = BkRowHunt(tfs[i]);
      t1[i]   = BkRowTP(tfs[i], 1);
      t2[i]   = BkRowTP(tfs[i], 2);
      t3[i]   = BkRowTP(tfs[i], 3);
      BaseKnotAbilityPush(tfs[i], an, BkRowEng(tfs[i]) * g_bkPip, 8.3 * g_bkPip);
   }
   BaseKnotEngPush(tfs, ans, eng, hunt, t1, t2, t3, 4);   // the LEGS (pips) the lines read
}

//--- ONE TYPE, ALL THREE COMPONENTS. hPips is what the box would measure; the RATIO bands are
//--- √(43.4x73.3)=56.40 / √(73.3x136.3)=99.95 / 136.3 off the rows above (P-BK-128), so
//--- 40 / 90 / 110 / 136.8 land in the four, and the NAME path (hop = -1) still steps one TF
//--- per type — that fallback is what a preview with no box carries.
void BkCase(const int kind, const string name, const double hPips, const datetime an)
{
   double h   = hPips * g_bkPip;
   double top = 2000.0 + h;
   double bot = 2000.0;

   //---- 1. THE TYPE, from the height alone
   int got = BaseKnotNodeKindOfLength(5, h, an);
   BkCheck(name + " · type", got == kind, got, kind);

   //---- 2. THE TWO OWNERS: ONE RULER — both legs on the type's rung (P-BK-127)
   int etf = BaseKnotEntryTFMin(got, 5);
   int mtf = BaseKnotMeasureTFMin(got, 5);
   BkCheck(name + " · entry TF (type's rung)", etf == BkStopTF(kind), etf, BkStopTF(kind));
   BkCheck(name + " · one ruler (entry TF == stop TF)", etf == mtf, etf, mtf);
   BkCheck(name + " · stop TF (type's rung)", mtf == BkStopTF(kind), mtf, BkStopTF(kind));

   //---- 3. BUY: entry / stop / three targets
   double entry = 0.0, sl = 0.0, off = 0.0, risk = 0.0;
   BaseKnotCalcLevels(top, bot, +1, got, 5, entry, sl, off, risk, an);

   double wantOff  = (kind == BK_NODE_FTR ? BkRowEng(mtf) : BkRowHunt(mtf));   // P-BK-127: the RUNG's own leg, not the base's
   double wantRisk = BkRowEng(mtf);
   BkCheck(name + " · entry depth (pips)", BkNear(off, wantOff), off, wantOff);
   BkCheck(name + " · stop risk (pips)", BkNear(risk, wantRisk), risk, wantRisk);
   BkCheck(name + " · BUY entry = top - off", BkNear(entry, top - off * g_bkPip), entry, top - off * g_bkPip);
   BkCheck(name + " · BUY sl = entry - risk", BkNear(sl, entry - risk * g_bkPip), sl, entry - risk * g_bkPip);

   for(int k = 1; k <= BK_TP_PLAN_MAX; k++)
   {
      double lv   = BaseKnotTPLevel(entry, +1, mtf, k, an);
      double tpP  = (lv - entry) / g_bkPip;
      BkCheck(name + " · TP" + IntegerToString(k) + " (pips off entry)", BkNear(tpP, BkRowTP(mtf, k)), tpP, BkRowTP(mtf, k));
      // the leg belongs to the STOP's rung, never the node's own — the two rows differ
      if(mtf != 5)
         BkCheck(name + " · TP" + IntegerToString(k) + " is not the node rung's leg",
                 MathAbs(tpP - BkRowTP(5, k)) > 0.5, MathAbs(tpP - BkRowTP(5, k)), 0);
   }

   //---- 4. SELL is the mirror, same three numbers
   double e2 = 0.0, s2 = 0.0, o2 = 0.0, r2 = 0.0;
   BaseKnotCalcLevels(top, bot, -1, got, 5, e2, s2, o2, r2, an);
   BkCheck(name + " · SELL entry = bot + off", BkNear(e2, bot + o2 * g_bkPip), e2, bot + o2 * g_bkPip);
   BkCheck(name + " · SELL sl = entry + risk", BkNear(s2, e2 + r2 * g_bkPip), s2, e2 + r2 * g_bkPip);
   BkCheck(name + " · SELL TP1 = entry - leg", BkNear((e2 - BaseKnotTPLevel(e2, -1, mtf, 1, an)) / g_bkPip, BkRowTP(mtf, 1)), (e2 - BaseKnotTPLevel(e2, -1, mtf, 1, an)) / g_bkPip, BkRowTP(mtf, 1));
}

int OnStart()
{
   g_bkPip = BaseKnotPipSize();
   if(g_bkPip <= 0.0) g_bkPip = 0.0001;

   datetime an = D'2026.09.15.10:00';   // one anchor for all four rows and all four boxes
   Print("[BKLINES] ============ four types x three components (entry / stop / TP1..3)");
   Print("[BKLINES] pip=", DoubleToString(g_bkPip, 6),
         "  rows: EngSL 43.4/73.3/136.3/311.0 pips on M5/M15/H1/H4 at ", TimeToString(an));
   BkPushRows(an);

   BkCase(BK_NODE_FTR, "FTR", 40.0,  an);
   BkCase(BK_NODE_ETR, "ETR", 90.0,  an);
   BkCase(BK_NODE_CTR, "CTR", 110.0, an);   // P-BK-128: the ETR/CTR edge is √(73.3x136.3)=99.95 now
   BkCase(BK_NODE_OTR, "OTR", 136.8, an);

   //---- 6. P-BK-128: THE TYPE IS A RATIO COMPARISON, AND THE RUNG IS A CAPACITY ONE, so the
   //---- old knife edge (58.35 = the ARITHMETIC midpoint of 43.4 and 73.3) no longer moves the
   //---- answer, and the type may part from the rung (ETR read on the node's OWN ATR) when the
   //---- pattern's leg package does not fit inside the box.
   Print("[BKLINES] ============ P-BK-128: ratio boundaries + the rung the box can hold");
   BkCheck("P-BK-128 · FTR/ETR edge is the ratio one (56.40)",
           BkNear(BaseKnotToPips(BaseKnotNodeBandFtrEtr(5, an)), MathSqrt(BkRowEng(5) * BkRowEng(15))),
           BaseKnotToPips(BaseKnotNodeBandFtrEtr(5, an)), MathSqrt(BkRowEng(5) * BkRowEng(15)));
   BkCheck("P-BK-128 · ETR/CTR edge is the ratio one (99.95)",
           BkNear(BaseKnotToPips(BaseKnotNodeBandEtrCtr(5, an)), MathSqrt(BkRowEng(15) * BkRowEng(60))),
           BaseKnotToPips(BaseKnotNodeBandEtrCtr(5, an)), MathSqrt(BkRowEng(15) * BkRowEng(60)));
   BkCheck("P-BK-128 · 58.3 below the OLD edge is ETR",
           BaseKnotNodeKindOfLength(5, 58.3 * g_bkPip, an) == BK_NODE_ETR,
           BaseKnotNodeKindOfLength(5, 58.3 * g_bkPip, an), BK_NODE_ETR);
   BkCheck("P-BK-128 · 58.4 above it is ETR too - one box, one type",
           BaseKnotNodeKindOfLength(5, 58.4 * g_bkPip, an) == BK_NODE_ETR,
           BaseKnotNodeKindOfLength(5, 58.4 * g_bkPip, an), BK_NODE_ETR);
   BkCheck("P-BK-128 · 58.3 and 58.4 read the SAME rung",
           BaseKnotLadderHopAt(5, 58.3 * g_bkPip, an) == BaseKnotLadderHopAt(5, 58.4 * g_bkPip, an),
           BaseKnotLadderHopAt(5, 58.3 * g_bkPip, an), BaseKnotLadderHopAt(5, 58.4 * g_bkPip, an));
   // the capacity edge: 55/64 x 73.3 = 63.0 — under it the pattern's legs do not fit the box
   BkCheck("P-BK-128 · 60 pips cannot hold the pattern package (55/64 x 73.3 = 63.0)",
           BaseKnotLadderHopAt(5, 60.0 * g_bkPip, an) == 0,
           BaseKnotLadderHopAt(5, 60.0 * g_bkPip, an), 0);
   BkCheck("P-BK-128 · 66 pips can hold it",
           BaseKnotLadderHopAt(5, 66.0 * g_bkPip, an) == 1,
           BaseKnotLadderHopAt(5, 66.0 * g_bkPip, an), 1);
   // ... and the legs of that ETR box really are the node's own row: Eng 43.4, Hunt 27.125
   double o60 = 0.0, r60 = 0.0;
   BaseKnotLegPair(2000.0 + 60.0 * g_bkPip, 2000.0, BK_NODE_ETR, 5, o60, r60, an,
                   BaseKnotLadderHopAt(5, 60.0 * g_bkPip, an));
   BkCheck("P-BK-128 · ETR on the node's rung · entry = Hunt(M5) 27.125", BkNear(o60, BkRowHunt(5)), o60, BkRowHunt(5));
   BkCheck("P-BK-128 · ETR on the node's rung · stop = Eng(M5) 43.4", BkNear(r60, BkRowEng(5)), r60, BkRowEng(5));

   //---- 5. THE INK CONTRACT the page prints: 2px entry/stop, 3px target ticks, solid ticks
   BkCheck("ink · entry/stop width", BK_LEVEL_WIDTH == 2, BK_LEVEL_WIDTH, 2);
   BkCheck("ink · TP tick width", BK_TP_TICK_WIDTH == 3, BK_TP_TICK_WIDTH, 3);
   BkCheck("ink · TP tick style is SOLID", BK_TP_TICK_STYLE == STYLE_SOLID, BK_TP_TICK_STYLE, STYLE_SOLID);
   BkCheck("ink · TP count", BaseKnotTPCount() == 3, BaseKnotTPCount(), 3);

   //---- 7. P-BK-129: THE FACE SPELLS THE TF AS A CLOCK. His own note read `35 bars · 700m base`,
   //---- and 700m IS 35 bars x 20m, i.e. 11h40m of market — a number a reader can size. A ladder
   //---- rung keeps its own name (`4h` beside `H4` would be a second name for one rung), and the
   //---- MACHINE spelling (`readTF=` / `nodeTF=` / the sample's `Node_TF:`) is untouched.
   Print("[BKLINES] ============ P-BK-129: the note's TF reads as a clock");
   BkCheckS("P-BK-129 · 700m -> 11h40m",            BaseKnotTFHuman(700),  "11h40m");
   BkCheckS("P-BK-129 · 235m -> 3h55m",             BaseKnotTFHuman(235),  "3h55m");
   BkCheckS("P-BK-129 · 20m stays 20m",             BaseKnotTFHuman(20),   "20m");
   BkCheckS("P-BK-129 · 2000m -> 1d9h20m",          BaseKnotTFHuman(2000), "1d9h20m");
   BkCheckS("P-BK-129 · a rung keeps its name (H4)", BaseKnotTFHuman(240),  "H4");
   BkCheckS("P-BK-129 · a rung keeps its name (D1)", BaseKnotTFHuman(1440), "D1");
   BkCheckS("P-BK-129 · the machine spelling is untouched", BaseKnotTFName(700), "700m");

   //---- 8. P-BK-130: A KNOT'S OWN MINUTES IS NOT A RUNG. His own 6h FTR box printed
   //---- `ATR 6h: 324.9` while the header printed `H4: 324.9` — ONE number under two names —
   //---- because the plan read the ladder SLOT (240) instead of the 360 the box asked for, and
   //---- all four legs are that number x their own constant (TRex 15/64, Trigger 5/8,
   //---- Pricle 75/64, Classic 45/16). The fence: a length MT4 carries a series for is read at
   //---- THAT length; a length with no series (700m) keeps the rung below, never the chart's TF.
   Print("[BKLINES] ============ P-BK-130: a knot's own minutes is not a rung");
   int slot360 = TradePlanLadderMinutes(TradePlanLadderIndex(360));
   BkCheck("P-BK-130 · the ladder has no 6h slot (360 snaps to 240)", slot360 == 240, slot360, 240);
   BkCheck("P-BK-130 · MT4 HAS a 6h series (CompatTF 360 -> H6)",
           (int)CompatTF(360) == (int)PERIOD_H6, (int)CompatTF(360), (int)PERIOD_H6);
   BkCheck("P-BK-130 · a 700m time has NO series (CompatTF -> CURRENT)",
           (int)CompatTF(700) == (int)PERIOD_CURRENT, (int)CompatTF(700), (int)PERIOD_CURRENT);
   double h4Read = TradePlanStripPips(240, 0);
   double ownH4  = TradePlanATROfOwnTime(240, 0);
   BkCheck("P-BK-130 · a rung is read on its own series (H4 unchanged)",
           BkNear(ownH4, h4Read), ownH4, h4Read);
   double ownH6 = TradePlanATROfOwnTime(360, 0);
   BkCheck("P-BK-130 · the 6h row IS the 6h read",
           BkNear(ownH6, TradePlanStripPips(360, 0)), ownH6, TradePlanStripPips(360, 0));
   if(TradePlanStripPips(360, 0) > 0.0 && h4Read > 0.0)
      BkCheck("P-BK-130 · the 6h read is NOT the H4 number", !BkNear(ownH6, h4Read), ownH6, h4Read);
   else
      Print("[BKLINES] SKIP  P-BK-130 · the 6h read is NOT the H4 number  (no H6 history yet)");
   double own700 = TradePlanATROfOwnTime(700, 0);
   // P-BK-131: a length MT4 has no bar for is the rung below x sqrt(own / below) — the SAME law
   // BaseKnotRungScale applies to the type's row — so `700m` (his own note's spelling) stops
   // wearing H4's number and cannot read the chart's own TF either. One continuous ruler.
   double want700 = h4Read * MathSqrt(700.0 / 240.0);
   BkCheck("P-BK-131 · a series-less time is SCALED by the same sqrt law",
           BkNear(own700, want700), own700, want700);
   if(h4Read > 0.0)
      BkCheck("P-BK-131 · a 700m knot is no longer an H4 knot (x1.7078)",
              !BkNear(own700, h4Read), own700, h4Read);
   else
      Print("[BKLINES] SKIP  P-BK-131 · a 700m knot is no longer an H4 knot  (H4 row cold)");
   Print("[BKLINES] P-BK-131 comparable ladder (pips): H4=", DoubleToString(TradePlanATROfOwnTime(240, 0), 1),
         "  6h=", DoubleToString(TradePlanATROfOwnTime(360, 0), 1),
         "  700m=", DoubleToString(TradePlanATROfOwnTime(700, 0), 1),
         "  D1=", DoubleToString(TradePlanATROfOwnTime(1440, 0), 1));
   STradePlan p6;
   bool ok6 = TradePlanCompute(360, p6, 0);
   BkCheck("P-BK-130 · the ladder slot stays the label (chartMin = 240)", p6.chartMin == 240, p6.chartMin, 240);
   BkCheck("P-BK-130 · the plan's own ATR is the box' own minutes",
           BkNear(p6.ownPips, ownH6), p6.ownPips, ownH6);
   Print("[BKLINES] P-BK-130 plan valid=", (ok6 ? "true" : "false"),
         " chartMin=", p6.chartMin, " ownPips=", DoubleToString(p6.ownPips, 2),
         " eng=", DoubleToString(p6.eng, 1), " hunter=", DoubleToString(p6.hunter, 1),
         " | H4 read=", DoubleToString(h4Read, 2), " | 6h read=", DoubleToString(TradePlanStripPips(360, 0), 2));

   //---- 9. P-BK-132: THE BOX' OWN POWER IS THE FLOOR OF THE LEG. His 6h FTR box had drifted a
   //---- short step past its own time's ability but had not reached the next rung's range, and the
   //---- ladder still priced it on its own rung - so its entry, stop and targets kept the size of a
   //---- box it no longer was. The law is the log interpolation's own identity: a leg graded by the
   //---- box' height across [a_k, a_k+1] IS h / 4.266666 (the parameter and the curve cancel), so ONE
   //---- factor - boxLeg / rungLeg, clamped at 1 - turns the rung's pair into the box' pair. The
   //---- fence: a box AT or UNDER its rung is byte-identical (the pushed leg is never shrunk).
   Print("[BKLINES] ============ P-BK-132: the box' own power is the floor of the leg");
   BkCheck("P-BK-132 - a box under its rung is untouched", BkNear(BaseKnotLegGrade(9.4, 43.4), 1.0), BaseKnotLegGrade(9.4, 43.4), 1.0);
   BkCheck("P-BK-132 - a box exactly its rung is untouched", BkNear(BaseKnotLegGrade(43.4, 43.4), 1.0), BaseKnotLegGrade(43.4, 43.4), 1.0);
   BkCheck("P-BK-132 - twice the box, twice the leg", BkNear(BaseKnotLegGrade(86.8, 43.4), 2.0), BaseKnotLegGrade(86.8, 43.4), 2.0);
   BkCheck("P-BK-132 - no leg, no grade", BkNear(BaseKnotLegGrade(86.8, 0.0), 1.0), BaseKnotLegGrade(86.8, 0.0), 1.0);
   // the boundary: h = 43.4 x 4.2667 = 185.2 pips makes the box' own power EQUAL the rung's leg
   double hB = 43.4 * 4.2667, tB = 3000.0 + hB * g_bkPip, bB = 3000.0;
   double eB = 0.0, sB = 0.0, oB = 0.0, rB = 0.0;
   BaseKnotCalcLevels(tB, bB, +1, BK_NODE_FTR, 5, eB, sB, oB, rB, an);
   BkCheck("P-BK-132 - the boundary is byte-identical (both legs = the rung's)",
           BkNear(oB, 43.4) && BkNear(rB, 43.4), rB, 43.4);
   // twice the rung: h = 86.8 x 4.2667 = 370.4 pips -> BOTH legs 86.8, never one of the two
   double hC = 86.8 * 4.2667, tC = 3000.0 + hC * g_bkPip, bC = 3000.0;
   double eC = 0.0, sC = 0.0, oC = 0.0, rC = 0.0;
   BaseKnotCalcLevels(tC, bC, +1, BK_NODE_FTR, 5, eC, sC, oC, rC, an);
   BkCheck("P-BK-132 - a box twice its rung doubles BOTH legs", BkNear(oC, 86.8) && BkNear(rC, 86.8), rC, 86.8);
   BkCheck("P-BK-132 - the stop line moves with it (entry = top - 86.8)", BkNear(eC, tC - 86.8 * g_bkPip), eC, tC - 86.8 * g_bkPip);
   double noteC = BaseKnotRiskPips(5, tC, bC, an);
   BkCheck("P-BK-132 - the note's risk IS the drawn stop", BkNear(noteC, rC), noteC, rC);
   BkCheck("P-BK-132 - the graded pair fills exactly 30/64 of the box (off/risk = 1)", BkNear(oC + rC, 30.0 / 64.0 * hC), oC + rC, 30.0 / 64.0 * hC);
   double tpC = BaseKnotPlanTPPips(5, 1, an, noteC);
   BkCheck("P-BK-132 - TP1 rides the same ruler (x2)", BkNear(tpC, BkRowTP(5, 1) * 2.0), tpC, BkRowTP(5, 1) * 2.0);
   BkCheck("P-BK-132 - an ungraded read keeps the plan's own leg", BkNear(BaseKnotPlanTPPips(5, 1, an), BkRowTP(5, 1)),
           BaseKnotPlanTPPips(5, 1, an), BkRowTP(5, 1));
   BkCheck("P-BK-132 - the R on a tick never moves", BkNear(tpC / noteC, BkRowTP(5, 1) / 43.4), tpC / noteC, BkRowTP(5, 1) / 43.4);
   // ... and the HUNT side grades by the SAME factor: an ETR box twice its rung's ability (2 x 73.3)
   double hE = 2.0 * 73.3 * 4.2667, tE = 3000.0 + hE * g_bkPip, bE = 3000.0;
   double eE = 0.0, sE = 0.0, oE = 0.0, rE = 0.0;
   BaseKnotCalcLevels(tE, bE, +1, BK_NODE_ETR, 5, eE, sE, oE, rE, an);
   BkCheck("P-BK-132 - an ETR grades its entry AND its stop (off 91.6 / risk 146.6)",
           BkNear(oE, 2.0 * BkRowHunt(15)) && BkNear(rE, 2.0 * BkRowEng(15)), rE, 2.0 * BkRowEng(15));
   BkCheck("P-BK-132 - the grade preserves the entry/stop ratio", BkNear(oE / rE, BkRowHunt(15) / BkRowEng(15)), oE / rE, BkRowHunt(15) / BkRowEng(15));
   // the product's real Hunt/Eng is 8/3 (5/8 of the ATR against 15/64 of it), so the deepest graded
   // pair fills 55/64 of the box - the SAME constant the hop test reserves (BK_AB_FIT_NUM/DEN).
   BkCheck("P-BK-132 - the product's Hunt/Eng fills 55/64 of the box (the ladder's own fit)",
           BkNear((1.0 + 8.0 / 3.0) * (15.0 / 64.0), 55.0 / 64.0), (1.0 + 8.0 / 3.0) * (15.0 / 64.0), 55.0 / 64.0);

   // P-BK-132: the SAME production geometry serves all four names. For each type, make a box
   // whose own Eng leg is twice that type's pushed stop rung; entry, stop, target and note must
   // all read x2. This checks the four callers' type-specific rung choice, not four formulas.
   Print("[BKLINES] ============ P-BK-132: the same grade across FTR / ETR / CTR / OTR");
   int gradeKinds[4] = {BK_NODE_FTR, BK_NODE_ETR, BK_NODE_CTR, BK_NODE_OTR};
   for(int gi = 0; gi < 4; gi++)
   {
      int kind = gradeKinds[gi];
      int tf = BkStopTF(kind);
      double eng = BkRowEng(tf);
      double hh = 2.0 * eng * BK_NODE_POWER_DIV;
      double top = 3000.0 + hh * g_bkPip, bot = 3000.0;
      double en = 0.0, st = 0.0, off = 0.0, risk = 0.0;
      BaseKnotCalcLevels(top, bot, +1, kind, 5, en, st, off, risk, an);
      string typeName = BaseKnotNodeShort(kind);
      double wantOff = 2.0 * (kind == BK_NODE_FTR ? eng : BkRowHunt(tf));
      BkCheck("P-BK-132 " + typeName + " - entry follows the shared grade",
              BkNear(off, wantOff), off, wantOff);
      BkCheck("P-BK-132 " + typeName + " - stop follows the shared grade",
              BkNear(risk, 2.0 * eng), risk, 2.0 * eng);
      BkCheck("P-BK-132 " + typeName + " - note risk matches the drawn stop",
              BkNear(BaseKnotRiskPips(tf, top, bot, an), risk), BaseKnotRiskPips(tf, top, bot, an), risk);
      BkCheck("P-BK-132 " + typeName + " - TP1 follows the same grade",
              BkNear(BaseKnotPlanTPPips(tf, 1, an, risk), 2.0 * BkRowTP(tf, 1)),
              BaseKnotPlanTPPips(tf, 1, an, risk), 2.0 * BkRowTP(tf, 1));
   }

   Print("[BKLINES] DONE pass=", g_bkPass, " fail=", g_bkFail);
   return (g_bkFail == 0 ? 0 : 1);
}
//+------------------------------------------------------------------+
