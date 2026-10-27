//+------------------------------------------------------------------+
//| Biotak_NodeType_Vol_Test.mq4                                    |
//| P-BK-106 (2026-10-09) — THE KNOT TYPE, ACROSS THE VOLATILITY     |
//| RANGE, OFF ONE ANCHORED ATR.                                     |
//|                                                                  |
//| The type (FTR/ETR/CTR/OTR) was read against TH up to 2026-10-09:|
//| `price * pct / 100` (THCalculations.mqh). TH is a fixed          |
//| percentage of PRICE — no volatility in it at all — so a calm     |
//| pair and a violent one at the SAME price were typed by the SAME  |
//| number («روی جفت ارزهای شارپ و یا کم نوسان فرق atr, th زیاد میشه»). |
//| The measure is the anchored composite ATR now, and the two upper  |
//| bands are that ATR scaled by the ladder's own √-law, so the       |
//| LADDER IS NOT WALKED for the type any more.                      |
//|                                                                  |
//| WHAT THIS RUNS (no quotes, no network, no history — it pushes     |
//| its own rows into the ability table and reads the rule back).     |
//| Everything is in PIPS, so it says the same on a 3-digit and a    |
//| 5-digit chart:                                                    |
//|   1. THE BAND TABLE of one node rung (H1), for a CALM pair (ATR  |
//|      8 pips) and a VIOLENT one (ATR 200 pips) — under TH those two|
//|      were the same number at the same price;                        |
//|   2. THE RATIO SWEEP — every rung of the ladder, nine ATR         |
//|      magnitudes from 2 to 5000 pips (a 2500x range), 200 heights  |
//|      across the whole band space plus the SIX exact band edges    |
//|      (±0.1 %), each against the shipped rule stated independently |
//|      below:                                                        |
//|        trig = ATR(nodeTF)                        (the ONE read)  |
//|        pat  = ATR * sqrt(up1/nodeTF)                            |
//|        str  = pat * sqrt(up2/up1)                               |
//|        FTR: h <= (trig+pat)/2 · ETR: <= (pat+str)/2 · CTR: <= str|
//|      Same height/ATR ratio -> same type at EVERY magnitude, which|
//|      is the property TH could not have;                            |
//|   3. MONOTONE — the type never moves backwards as the box grows;|
//|   4. THE ANCHOR — two rows, two bars, two answers, and the LIVE   |
//|      row is never quietly substituted for the anchored one;      |
//|   5. TWO COLUMNS, ONE KEY — the type reads the ATR column and the|
//|      step reads its own TH, so neither is read as the other;      |
//|   6. ABSENCE — a cold rung types BK_NODE_NONE, never a guess.     |
//|                                                                  |
//| HOW TO RUN: drag onto any chart, open the "Experts" tab, look for |
//| [NODEVOLTEST] lines.                                             |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

// Same include chain as the entry - the test runs the real code.
// P-BUILD-02: a harness mirrors the entry by hand; the ORDER below is the
// entry's own (Biotak Trigger TH3.mq4), because the layers resolve in it.
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

int g_nvPass = 0;
int g_nvFail = 0;
double g_nvPip = 1.0;   // the chart's own pip, so every number here is in PIPS

void NvCheck(const string label, const bool ok)
{
   if(ok) { g_nvPass++; Print("[NODEVOLTEST] PASS: ", label); }
   else   { g_nvFail++; Print("[NODEVOLTEST] FAIL: ", label); }
}

//--- THE SHIPPED RULE, STATED INDEPENDENTLY. The ladder's minutes and the √-law come from the
//--- ONE owner's own table (a mirror cannot own them), but the band arithmetic, the order the
//--- comparisons are applied in and the ≤ / > at each edge are what this run exists to check.
//--- P-BK-128: each edge is the RATIO midpoint of the two abilities it separates, √(a·b) —
//--- (a+b)/2 is "nearest" only for an additive ladder, and these rungs grow x1.73 / x2.00.
int NvType(const int nodeTF, const double hPips, const double atrPips)
{
   if(hPips <= 0.0 || atrPips <= 0.0) return BK_NODE_NONE;
   int up1 = BaseKnotNextTFMin(nodeTF);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   if(up1 <= 0 || up2 <= 0) return BK_NODE_NONE;
   double trig = atrPips;
   double pat  = atrPips * MathSqrt((double)up1 / (double)nodeTF);
   double str  = pat      * MathSqrt((double)up2 / (double)up1);
   if(hPips <= MathSqrt(trig * pat)) return BK_NODE_FTR;
   if(hPips <= MathSqrt(pat  * str)) return BK_NODE_ETR;
   if(hPips <= str)                  return BK_NODE_CTR;
   return BK_NODE_OTR;
}
// the three band edges of one node rung, in RATIOS of the ATR (magnitude-free):
//   FTR/ETR = √(1 x s1), ETR/CTR = √(s1 x s1·s2), CTR/OTR = s1·s2  (s1, s2 the two √-law steps)
double NvRatioFtrEtr(const int nodeTF)
{
   int up1 = BaseKnotNextTFMin(nodeTF);
   if(up1 <= 0) return 0.0;
   return MathSqrt(MathSqrt((double)up1 / (double)nodeTF));   // √(1 · s1)
}
double NvRatioEtrCtr(const int nodeTF)
{
   int up1 = BaseKnotNextTFMin(nodeTF);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   if(up1 <= 0 || up2 <= 0) return 0.0;
   double s1 = MathSqrt((double)up1 / (double)nodeTF);
   double s2 = MathSqrt((double)up2 / (double)up1);
   return s1 * MathSqrt(s2);                                  // √(s1 · s1·s2)
}
double NvRatioCtrOtr(const int nodeTF)   // CTR's own ceiling: the structure ability itself
{
   int up1 = BaseKnotNextTFMin(nodeTF);
   int up2 = (up1 > 0 ? BaseKnotNextTFMin(up1) : 0);
   if(up1 <= 0 || up2 <= 0) return 0.0;
   double s1 = MathSqrt((double)up1 / (double)nodeTF);
   double s2 = MathSqrt((double)up2 / (double)up1);
   return s1 * s2;   // P-BK-128: was s1*s1*s2, which probed a ceiling the rule never used
}
string NvName(const int kind)
{
   if(kind == BK_NODE_FTR) return "FTR";
   if(kind == BK_NODE_ETR) return "ETR";
   if(kind == BK_NODE_CTR) return "CTR";
   if(kind == BK_NODE_OTR) return "OTR";
   return "NONE";
}
int NvRung(const int i)   // the ladder's six rungs that HAVE two rungs above them
{
   int r[6] = {1, 5, 15, 60, 240, 1440};
   return r[i];
}

//+------------------------------------------------------------------+
int OnStart()
{
   g_nvPip = BaseKnotPipSize();
   Print("[NODEVOLTEST] ============ knot type across the volatility range (P-BK-106)");
   Print("[NODEVOLTEST] pip=", DoubleToString(g_nvPip, 6),
         " · a node's TWO UPPER BANDS ARE DERIVED (ATR x the ladder's own sqrt), never read");

   //---- 1. ONE NODE RUNG, TWO MARKETS, THE SAME PRICE -----------------
   datetime an = D'2026.09.15.10:00';   // the box' own anchor: the bar its base ended on
   double calmPips    = 8.0;            // EURUSD, Asia session
   double violentPips = 200.0;          // GBPJPY, a news bar
   BaseKnotAbilityReset();
   BaseKnotAbilityPush(60, an, calmPips * g_nvPip, calmPips * 2.0 * g_nvPip);
   double calmAtr = 0.0, calmPat = 0.0, calmStr = 0.0, calmStep = 0.0;
   bool calmWarm = BaseKnotAbilityGet(60, an, calmAtr, calmPat, calmStr);
   BaseKnotStepRow(60, an, calmStep);
   // a repeated (TF, anchor) overwrites: the newest round wins, so the two markets are read
   // in two rounds, exactly as the pump answers two different symbols.
   BaseKnotAbilityReset();
   BaseKnotAbilityPush(60, an, violentPips * g_nvPip, violentPips * 3.0 * g_nvPip);
   double vAtr = 0.0, vPat = 0.0, vStr = 0.0, vStep = 0.0;
   bool vWarm = BaseKnotAbilityGet(60, an, vAtr, vPat, vStr);
   BaseKnotStepRow(60, an, vStep);
   Print("[NODEVOLTEST]   node H1 (60) at ONE price, anchor ", TimeToString(an), ":");
   Print("[NODEVOLTEST]     calm    ATR ", DoubleToString(calmPips, 1), " pips -> bands ",
         DoubleToString(BaseKnotToPips(calmPat), 1), " / ", DoubleToString(BaseKnotToPips(calmStr), 1),
         "  FTR<", DoubleToString(BaseKnotToPips(MathSqrt(calmAtr * calmPat)), 1),
         " ETR<", DoubleToString(BaseKnotToPips(MathSqrt(calmPat * calmStr)), 1),
         " CTR<", DoubleToString(BaseKnotToPips(calmStr), 1));
   Print("[NODEVOLTEST]     violent ATR ", DoubleToString(violentPips, 1), " pips -> bands ",
         DoubleToString(BaseKnotToPips(vPat), 1), " / ", DoubleToString(BaseKnotToPips(vStr), 1),
         "  FTR<", DoubleToString(BaseKnotToPips(MathSqrt(vAtr * vPat)), 1),
         " ETR<", DoubleToString(BaseKnotToPips(MathSqrt(vPat * vStr)), 1),
         " CTR<", DoubleToString(BaseKnotToPips(vStr), 1));
   NvCheck("both markets answer their own band (the row is warm)", calmWarm && vWarm);
   NvCheck("the violent market's bands are the calm ones x 25 — ATR carries the volatility, TH did not",
           MathAbs(BaseKnotToPips(vPat) / BaseKnotToPips(calmPat) - 25.0) < 0.05);
   NvCheck("the STEP column keeps its own number per row (the rung's TH, not the ATR)",
           MathAbs(BaseKnotToPips(calmStep) - calmPips * 2.0) < 0.01 &&
           MathAbs(BaseKnotToPips(vStep) - violentPips * 3.0) < 0.01);

   //---- 2. THE RATIO SWEEP: every rung x nine magnitudes x the whole band space ----
   double mags[9] = {2.0, 10.0, 50.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 20000.0};
   int cases = 0, bad = 0, badRung = 0;
   double badRatio = -1.0, badAtr = -1.0; int badGot = -1;
   for(int r = 0; r < 6; r++)
   {
      int nodeTF = NvRung(r);
      double eF = NvRatioFtrEtr(nodeTF);     // the FTR | ETR edge
      double eE = NvRatioEtrCtr(nodeTF);     // the ETR | CTR edge
      double eC = NvRatioCtrOtr(nodeTF);     // the CTR | OTR edge
      for(int m = 0; m < 9; m++)
      {
         double atrPips = mags[m];
         BaseKnotAbilityReset();
         BaseKnotAbilityPush(nodeTF, an, atrPips * g_nvPip, atrPips * g_nvPip);
         // (a) 200 heights across the whole band space
         for(int k = 0; k <= 200; k++)
         {
            double ratio = 0.05 + (6.5 - 0.05) * (double)k / 200.0;
            double hPips = atrPips * ratio;
            int got  = BaseKnotNodeKindOfLength(nodeTF, hPips * g_nvPip, an);
            int want = NvType(nodeTF, hPips, atrPips);
            cases++;
            if(got != want) { bad++; if(badRung == 0) { badRung = nodeTF; badRatio = ratio; badAtr = atrPips; badGot = got; } }
         }
         // (b) the SIX edges, ±0.1 %: the ≤ / > at each one is the rule
         double edges[3];          // runtime values: MQL4 wants constants in an initialiser
         edges[0] = eF; edges[1] = eE; edges[2] = eC;
         for(int e = 0; e < 3; e++)
         {
            double edge = edges[e] * atrPips;
            double probes[6];
            probes[0] = edge * 0.999;  probes[1] = edge * 0.9999; probes[2] = edge;
            probes[3] = edge * 1.0001; probes[4] = edge * 1.001;  probes[5] = edge * 1.05;
            for(int q = 0; q < 6; q++)
            {
               double hPips = probes[q];
               int got  = BaseKnotNodeKindOfLength(nodeTF, hPips * g_nvPip, an);
               int want = NvType(nodeTF, hPips, atrPips);
               cases++;
               if(got != want) { bad++; if(badRung == 0) { badRung = nodeTF; badRatio = probes[q] / atrPips; badAtr = atrPips; badGot = got; } }
            }
         }
      }
   }
   NvCheck("the shipped rule matches the independent bands (" + IntegerToString(cases) +
           " heights over 6 rungs x 9 ATR magnitudes, edges included)", bad == 0);
   if(bad > 0)
      Print("[NODEVOLTEST]   first miss: rung ", badRung, " ratio ", DoubleToString(badRatio, 4),
            " atr ", DoubleToString(badAtr, 1), " pips -> got ", NvName(badGot));

   //---- 3. MONOTONE: the type never moves backwards as the box grows ----
   bool mono = true;
   for(int r = 0; r < 6; r++)
   {
      int nodeTF = NvRung(r);
      double atrPips = 50.0;
      BaseKnotAbilityReset();
      BaseKnotAbilityPush(nodeTF, an, atrPips * g_nvPip, atrPips * g_nvPip);
      int prev = -1;
      for(int k = 0; k <= 120; k++)
      {
         int got = BaseKnotNodeKindOfLength(nodeTF, atrPips * (0.01 + 0.1 * k) * g_nvPip, an);
         if(got == BK_NODE_NONE) continue;
         if(prev > 0 && got < prev) mono = false;
         prev = got;
      }
   }
   NvCheck("the type is monotone in the box' height on every rung (no band is crossed twice)", mono);

   //---- 4. THE ANCHOR: two bars, two answers; the live row is never substituted ----
   BaseKnotAbilityReset();
   BaseKnotAbilityPush(60, an, calmPips * g_nvPip, calmPips * g_nvPip);        // the box' own bar
   BaseKnotAbilityPush(60, 0,    violentPips * g_nvPip, violentPips * g_nvPip); // the LIVE row
   double tA = 0.0, pA = 0.0, sA = 0.0, tL = 0.0, pL = 0.0, sL = 0.0;
   bool anchoredWarm = BaseKnotAbilityGet(60, an, tA, pA, sA);
   bool liveWarm     = BaseKnotAbilityGet(60, 0, tL, pL, sL);
   // a box that sits BETWEEN the two markets' FTR/ETR edges must answer each market by its own row
   double hPips = calmPips * 1.6;   // 12.8 pips: ETR on the calm bar, FTR on the violent live row
   int typeAnchored = BaseKnotNodeKindOfLength(60, hPips * g_nvPip, an);
   int typeLive     = BaseKnotNodeKindOfLength(60, hPips * g_nvPip, 0);
   NvCheck("the anchored row and the live row are two rows, both warm", anchoredWarm && liveWarm);
   NvCheck("the anchor decides: 12.8 pips is ETR on the calm bar and FTR on the violent live row",
           typeAnchored == BK_NODE_ETR && typeLive == BK_NODE_FTR);
   NvCheck("a closed knot reads its own bar (8 pips), never today's (200 pips)",
           MathAbs(BaseKnotToPips(tA) - calmPips) < 0.01 && MathAbs(BaseKnotToPips(tL) - violentPips) < 0.01);

   //---- 5. TWO COLUMNS, ONE KEY ---------------------------------------------
   BaseKnotAbilityReset();
   BaseKnotAbilityPush(60, an, 0.0, 2.0 * g_nvPip);   // ATR cold, the step's TH warm
   double atrCol = 0.0, stepCol = 0.0;
   bool atrCold  = BaseKnotAbilityRow(60, an, atrCol);
   bool stepWarm = BaseKnotStepRow(60, an, stepCol);
   NvCheck("a cold ATR column types NOTHING (absence), while the step column still answers its own TH",
           !atrCold && stepWarm && MathAbs(BaseKnotToPips(stepCol) - 2.0) < 0.01 &&
           BaseKnotNodeKindOfLength(60, 1.0 * g_nvPip, an) == BK_NODE_NONE);
   BaseKnotAbilityReset();
   BaseKnotAbilityPush(60, an, 2.0 * g_nvPip, 0.0);   // ATR warm (2 pips), the step cold
   bool atrWarm2 = BaseKnotAbilityRow(60, an, atrCol);
   bool stepCold = BaseKnotStepRow(60, an, stepCol);
   // 5 pips on a 2-pip ATR at H1 sits between FTR<3.0 and ETR<6.9 (the bands the sweep proves)
   NvCheck("the type is decided by the ATR column alone (the step is not a threshold)",
           atrWarm2 && !stepCold && BaseKnotNodeKindOfLength(60, 5.0 * g_nvPip, an) == BK_NODE_ETR);

   //---- 6. ABSENCE ------------------------------------------------------------
   BaseKnotAbilityReset();
   NvCheck("a rung nobody pushed answers BK_NODE_NONE (never a guess)",
           BaseKnotNodeKindOfLength(60, 1.0 * g_nvPip, an) == BK_NODE_NONE);
   NvCheck("a zero box' height claims nothing", BaseKnotNodeKindOfLength(60, 0.0, an) == BK_NODE_NONE);
   BaseKnotAbilityPush(43200, an, 1.0 * g_nvPip, 1.0 * g_nvPip);
   NvCheck("MN1 has no pattern/structure rung above it: NONE, not a band out of thin air",
           BaseKnotNodeKindOfLength(43200, 0.5 * g_nvPip, an) == BK_NODE_NONE &&
           BaseKnotRungScale(43200, 0) == 0.0);

   //---- the √-law itself, so a future edit to the ladder cannot drift silently ----
   bool lawOk = true;
   int pairs[5][2] = {{1, 5}, {5, 15}, {15, 60}, {60, 240}, {240, 1440}};
   double ratio[5];   // runtime: MQL4 wants a constant expression in an initialiser
   ArrayInitialize(ratio, 0.0);
   for(int i = 0; i < 5; i++) ratio[i] = (double)pairs[i][1] / (double)pairs[i][0];
   double expect[5];
   ArrayInitialize(expect, 0.0);   // explicit: the loops below fill them, the walk reads them whole
   for(int i = 0; i < 5; i++) expect[i] = MathSqrt(ratio[i]);
   for(int i = 0; i < 5; i++)
      if(MathAbs(BaseKnotRungScale(pairs[i][0], pairs[i][1]) - expect[i]) > 0.0001) lawOk = false;
   NvCheck("the ladder's own scale is sqrt(ratio) on all five steps (1->5, 5->15, 15->60, 60->H4, H4->D1)", lawOk);

   Print("[NODEVOLTEST] ", g_nvPass, " pass / ", g_nvFail, " fail");
   Print("[NODEVOLTEST] ============ done");
   return 0;
}
