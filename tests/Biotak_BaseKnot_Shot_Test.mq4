//+------------------------------------------------------------------+
//| Biotak_BaseKnot_Shot_Test.mq4                                    |
//| P-BK-124 — ONE PRESS, ONE SAMPLE FOLDER, PROVEN.                 |
//|                                                                  |
//| WHY THIS EXISTS. `BaseKnotCaptureSample` claims four things that  |
//| a green compile cannot prove:                                    |
//|   1. it writes a folder under MQL4\Files\BK_Dataset\Samples;     |
//|   2. the folder holds a non-empty shot.png AND a sample.txt;     |
//|   3. the sidecar carries EVERY key the sync tool reads, each with |
//|      a non-empty value (a missing key is a silent column of      |
//|      blanks on the site, and nothing would say which one);        |
//|   4. the numbers are the INK's numbers — read back off the drawn  |
//|      ENTRY/SL/TP objects, not re-derived — and `u` is the ladder  |
//|      coordinate of the height that was read back.                 |
//|                                                                  |
//| The expected values are LITERALS off the pushed table below, never |
//| a read-back of the reader under test: a harness that asks the code |
//| it is testing for the answer can only agree with it.              |
//|                                                                  |
//| RUN: drag onto any chart (EURUSD H1 is enough — every number is in |
//| PIPS), then read the Experts tab for the [BKSHOT] lines and the    |
//| closing DONE line. The test deletes its own folder, because a      |
//| leftover would be filed as a real sample by bk-shot-sync.js.       |
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

//--- the four rungs, stated here and nowhere else (same table as the Lines harness)
double BkRowEng(const int tf)
{
   if(tf == 5)   return 43.4;
   if(tf == 15)  return 73.3;
   if(tf == 60)  return 136.3;
   if(tf == 240) return 311.0;
   return 0.0;
}
void BkPushRows(const datetime an)
{
   int      tfs[4]  = {5, 15, 60, 240};
   datetime ans[4];
   double   eng[4], hunt[4], t1[4], t2[4], t3[4];
   BaseKnotAbilityReset();
   for(int i = 0; i < 4; i++)
   {
      ans[i]  = an;
      // P-BK-125: THE ENGSL, NOT THE ATR. `BkRowEng` is the ATR row (the type's measure);
      // the trade plan's `eng` is that rung's EngSL — ATR / 4.2666, one decimal — and it is
      // what the box draws its stop with. The two were conflated here until 2026-10-27: the
      // harness passed because every assertion compared the file to the plan it had just
      // computed, so a wrong table proved a wrong number consistently. With the real EngSL
      // the four stops below are the four MEASURED rows of the dataset: 10.2 / 17.2 / 32.0 /
      // 72.9 pips (BK-0001 FTR, BK-0002 ETR, BK-0003 CTR, BK-0004 OTR) and the targets fall
      // on 75 / 160 / 331 for the CTR box — exactly the numbers the log carried.
      eng[i]  = MathRound(BkRowEng(tfs[i]) / 4.2666 * 10.0) / 10.0;
      hunt[i] = BkRowEng(tfs[i]) * 5.0 / 8.0;
      t1[i]   = MathRound(eng[i] * 7.0 / 3.0);
      t2[i]   = MathRound(eng[i] * 5.0);
      t3[i]   = MathRound(eng[i] * 31.0 / 3.0);
      BaseKnotAbilityPush(tfs[i], an, BkRowEng(tfs[i]) * g_bkPip, 8.3 * g_bkPip);
   }
   BaseKnotEngPush(tfs, ans, eng, hunt, t1, t2, t3, 4);
}

bool BkNear(const double a, const double b, const double tol = 0.005) { return (MathAbs(a - b) < tol); }
void BkCheck(const string what, const bool ok, const double got, const double want)
{
   if(ok) { g_bkPass++; Print("[BKSHOT] PASS  ", what, "  got=", DoubleToString(got, 3), "  want=", DoubleToString(want, 3)); }
   else   { g_bkFail++; Print("[BKSHOT] FAIL  ", what, "  got=", DoubleToString(got, 3), "  want=", DoubleToString(want, 3)); }
}

//--- key: value lookup over the sidecar's lines. A missing key answers "" and false.
bool BkKey(const string &lines[], const int n, const string key, string &val)
{
   string pre = key + ": ";
   for(int i = 0; i < n; i++)
      if(StringFind(lines[i], pre) == 0) { val = StringSubstr(lines[i], StringLen(pre)); return (StringLen(val) > 0); }
   val = "";
   return false;
}

//--- draw the three leg objects exactly where the plan says, so the capture has something
//--- real to read back. This is the ONLY way the test can prove the read-back: if the
//--- sidecar's numbers were re-derived instead, it would still pass with no objects at all.
void BkDrawLegs(const string pfx, const double entry, const double sl,
                const double tp1, const double tp2, const double tp3,
                const datetime t1, const datetime t2)
{
   datetime tFar = t2 + (t2 - t1) * 2;
   double px[4];
   px[1] = tp1; px[2] = tp2; px[3] = tp3;   // element-wise: MQL4 array initialisers want constants
   string en = BaseKnotEntryName(pfx), sn = BaseKnotSLName(pfx);
   ObjectCreate(0, en, OBJ_TREND, 0, t2, entry, tFar, entry);
   ObjectCreate(0, sn, OBJ_TREND, 0, t2, sl,    tFar, sl);
   for(int k = 1; k <= 3; k++)
   {
      string nm = BaseKnotTPTickName(pfx, k);
      if(px[k] > 0.0) ObjectCreate(0, nm, OBJ_TREND, 0, t2, px[k], tFar, px[k]);
   }
}

void OnStart()
{
   Print("[BKSHOT] START one press, one sample folder");
   g_bkPip = BaseKnotPipSize();
   if(g_bkPip <= 0) { Print("[BKSHOT] FAIL  no pip size"); return; }

   datetime an = D'2026.09.15.10:00';
   BkPushRows(an);

   //---- one CTR box: h = 129.0 pips, the same height sample BK-0003 carried
   const double hPips = 129.0;
   const string id    = "5_999001";
   double bot = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bot <= 0.0) bot = 1.10000;
   double top = bot + hPips * g_bkPip;

   BaseKnotRegister(id, +1, 5);
   int k = BaseKnotFind(id);
   g_bkBoxes[k].baseTFMin = 5;              // the node's rung
   g_bkBoxes[k].storyT    = an;             // the story bar the ATRs are read at
   g_bkBoxes[k].nodeKind  = BK_NODE_CTR;    // the type the note would have published

   string pfx = BaseKnotPrefix(id);
   string box = BaseKnotBoxName(pfx);
   datetime t2 = TimeCurrent();
   datetime t1 = t2 - 20 * PeriodSeconds();
   ObjectCreate(0, box, OBJ_RECTANGLE, 0, t1, top, t2, bot);
   ObjectSetInteger(0, box, OBJPROP_SELECTED, true);   // BaseKnotSelectedId answers a selected box first

   //---- the plan's own legs, then the objects at exactly those prices
   double entry = 0.0, sl = 0.0, off = 0.0, risk = 0.0;
   BaseKnotCalcLevels(top, bot, +1, BK_NODE_CTR, 5, entry, sl, off, risk, an);
   double tp[4];
   ArrayInitialize(tp, 0.0);   // explicit: the checks below read every index
   for(int i = 1; i <= 3; i++)
   {
      double lv = BaseKnotTPLevel(entry, +1, BaseKnotMeasureTFMin(BK_NODE_CTR, 5), i, an);
      tp[i] = (lv > 0.0 && entry > 0.0 ? BaseKnotToPips(MathAbs(lv - entry)) : 0.0);
   }
   BkDrawLegs(pfx, entry, sl, BaseKnotTPLevel(entry, +1, BaseKnotMeasureTFMin(BK_NODE_CTR, 5), 1, an),
              BaseKnotTPLevel(entry, +1, BaseKnotMeasureTFMin(BK_NODE_CTR, 5), 2, an),
              BaseKnotTPLevel(entry, +1, BaseKnotMeasureTFMin(BK_NODE_CTR, 5), 3, an), t1, t2);

   //---- 1. THE PRESS
   bool ok = BaseKnotCaptureSample();
   BkCheck("capture returned true", ok, ok ? 1 : 0, 1);
   string leaf = g_bkShotLastDir;
   BkCheck("a leaf was named", StringLen(leaf) > 0, StringLen(leaf), 1);
   if(!ok || StringLen(leaf) == 0) { Print("[BKSHOT] DONE pass=", g_bkPass, " fail=", g_bkFail); return; }

   string dir = BK_SHOT_SAMPLES + "\\" + leaf;
   Print("[BKSHOT] folder=", dir);

   //---- 1b. THE RECEIPT (P-BK-124b). P-BK-124 measured the FOLDER and left the SCREEN
   //     unmeasured, so five complete folders and «چیزی روی صفحه نمیاد که سیو شده یا نه»
   //     were both true at once. The label is read back here: that it exists, that it wears
   //     the readable face, and that it carries the three facts a trader checks - did it land,
   //     what kind of knot, and the clock the record itself holds.
   {
      bool there = (ObjectFind(0, BK_SHOT_FLASH) >= 0);
      string rt = (there ? ObjectGetString(0, BK_SHOT_FLASH, OBJPROP_TEXT) : "");
      int face = (there ? (int)ObjectGetInteger(0, BK_SHOT_FLASH, OBJPROP_FONTSIZE) : 0);
      Print("[BKSHOT] receipt=\"", rt, "\" face=", face);
      BkCheck("the receipt is on the chart", there, there ? 1 : 0, 1);
      BkCheck("the receipt says SAVED first", StringFind(rt, "SAVED") == 0, StringFind(rt, "SAVED"), 0);
      BkCheck("the receipt names the knot's type", StringFind(rt, "CTR") > 0, StringFind(rt, "CTR"), -1);
      BkCheck("the receipt names the node's TF", StringFind(rt, "M5") > 0, StringFind(rt, "M5"), -1);
      BkCheck("the receipt carries the capture's clock", StringFind(rt, ":") > 0, StringFind(rt, ":"), -1);
      BkCheck("the receipt's face is the readable one", face == BK_SHOT_FACE_PX, face, BK_SHOT_FACE_PX);
   }

   //---- 2. THE TWO FILES
   string txtP = dir + "\\sample.txt";
   string pngP = dir + "\\shot.png";
   bool hasTxt = FileIsExist(txtP);
   bool hasPng = FileIsExist(pngP);
   BkCheck("sample.txt exists", hasTxt, hasTxt ? 1 : 0, 1);
   BkCheck("shot.png exists",   hasPng, hasPng ? 1 : 0, 1);
   if(!hasTxt) { Print("[BKSHOT] DONE pass=", g_bkPass, " fail=", g_bkFail); return; }

   //---- 3. EVERY KEY THE SYNC TOOL READS
   string lines[64];
   int n = 0;
   int fh = FileOpen(txtP, FILE_READ | FILE_TXT | FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      while(!FileIsEnding(fh) && n < 64) { lines[n] = FileReadString(fh); if(StringLen(lines[n]) > 0) n++; }
      FileClose(fh);
   }
   BkCheck("sidecar line count >= 38", n >= 38, n, 38);

   string keys[] = {"Folder", "Capture_Date", "Capture_Clock", "Symbol", "Chart_TF", "Node_TF",
                    "Box_ID", "Story_Anchor", "Edge_Anchor", "Box_Pips", "ATR_Trig", "ATR_Pat",
                    "ATR_Str", "ATR_Fourth", "Band_FTR", "Band_ETR", "Band_CTR", "Type",
                    "Edge_Margin_Pips", "U", "U_Margin", "Entry_Off_Pips", "Stop_Pips",
                    "Stop_V1_Pips", "TP1_Pips", "TP2_Pips", "TP3_Pips", "PerPip", "Balance",
                    "Risk_Pct", "Lot", "Risk_USD", "Direction", "Formula_Version", "Screenshot",
                    "Shot_Ok", "Shot_Px", "Chart_ID"};
   int missing = 0;
   for(int i = 0; i < ArraySize(keys); i++)
   {
      string v = "";
      if(!BkKey(lines, n, keys[i], v)) { missing++; Print("[BKSHOT] MISSING KEY: ", keys[i]); }
   }
   BkCheck("no key is missing or empty", missing == 0, missing, 0);

   //---- 4. THE NUMBERS ARE THE INK'S
   string s = "";
   BkKey(lines, n, "Box_Pips", s);   BkCheck("Box_Pips",     BkNear(StringToDouble(s), hPips, 0.15), StringToDouble(s), hPips);
   BkKey(lines, n, "Entry_Off_Pips", s); BkCheck("Entry_Off_Pips (read back)", BkNear(StringToDouble(s), off, 0.15), StringToDouble(s), off);
   BkKey(lines, n, "Stop_Pips", s);  BkCheck("Stop_Pips (read back)",  BkNear(StringToDouble(s), risk, 0.15), StringToDouble(s), risk);
   BkKey(lines, n, "TP1_Pips", s);   BkCheck("TP1_Pips (read back)",   BkNear(StringToDouble(s), tp[1], 0.15), StringToDouble(s), tp[1]);
   BkKey(lines, n, "Direction", s);  BkCheck("Direction is BUY", (s == "BUY"), (s == "BUY") ? 1 : 0, 1);
   BkKey(lines, n, "Type", s);       BkCheck("Type is CTR", (s == "CTR"), (s == "CTR") ? 1 : 0, 1);
   BkKey(lines, n, "Shot_Ok", s);    BkCheck("Shot_Ok is 1", (s == "1"), (s == "1") ? 1 : 0, 1);
   //     the lot is sized off the BALANCE, and an ini-launched terminal logs in to nothing:
   //     Balance 0 is the environment, not the capture. Asserted only when there is an account.
   string sBal = "";
   BkKey(lines, n, "Balance", sBal);
   BkKey(lines, n, "Lot", s);
   if(StringToDouble(sBal) > 0.0)
      BkCheck("Lot > 0", StringToDouble(s) > 0.0, StringToDouble(s), 1);
   else
      Print("[BKSHOT] note  Lot not asserted: this terminal has no account (Balance 0) - the size is 0 by arithmetic, not by defect");

   //---- 5. THE LADDER COORDINATE, off the pushed table, on the v7 (ratio) scale:
   //     u = 1 + ln(129.0/73.3) / ln(136.3/73.3) = 1.911 · margin to the 2.0 edge = 0.089
   //     (a v6 sample printed the linear 1.884 — the two are not comparable, P-BK-128)
   BkKey(lines, n, "U", s);          BkCheck("U (ladder coordinate)", BkNear(StringToDouble(s), 1.911, 0.002), StringToDouble(s), 1.911);
   BkKey(lines, n, "U_Margin", s);   BkCheck("U_Margin", BkNear(StringToDouble(s), 0.089, 0.002), StringToDouble(s), 0.089);
   BkKey(lines, n, "ATR_Fourth", s); BkCheck("ATR_Fourth (the OTR rung)", BkNear(StringToDouble(s), 311.0, 0.15), StringToDouble(s), 311.0);

   //---- the pure helpers, stated independently of the file
   BkCheck("U(43.4) = 0",        BkNear(BaseKnotLadderU(43.4, 43.4, 73.3, 136.3, 311.0), 0.0,   0.002), BaseKnotLadderU(43.4, 43.4, 73.3, 136.3, 311.0), 0.0);
   BkCheck("U(136.8) = 2.004",   BkNear(BaseKnotLadderU(136.8, 43.4, 73.3, 136.3, 311.0), 2.004, 0.002), BaseKnotLadderU(136.8, 43.4, 73.3, 136.3, 311.0), 2.004);
   BkCheck("U with no 4th rung = -1", BaseKnotLadderU(200.0, 43.4, 73.3, 136.3, 0.0) < 0.0, BaseKnotLadderU(200.0, 43.3, 73.3, 136.3, 0.0), -1);

   //---- 5b. P-BK-125/128 — THE STOP'S RUNG IS THE PACKAGE THE BOX CAN HOLD (formula v3)
   //     The type names a BAND; the stop used to jump a whole rung at the band's edge, so a
   //     box a hair above the structure ceiling wore a rung it was nowhere near. v2 answered
   //     round(u), which is a PRICE midpoint again — v3 asks which rung's whole leg package
   //     (55/64 of its ATR: off 5/8 + risk 15/64) still fits inside the box' own height.
   //     On these rows fit x a = 37.30 / 62.99 / 117.13 / 267.27 pips.
   BkCheck("h=43.4 holds the node's own package (37.30)", BaseKnotLadderHopAt(5, 43.4  * g_bkPip, an) == 0, BaseKnotLadderHopAt(5, 43.4  * g_bkPip, an), 0);
   BkCheck("h=60.0 cannot hold the pattern's (62.99)",    BaseKnotLadderHopAt(5, 60.0  * g_bkPip, an) == 0, BaseKnotLadderHopAt(5, 60.0  * g_bkPip, an), 0);
   BkCheck("h=129.0 holds the structure's (117.13)",      BaseKnotLadderHopAt(5, 129.0 * g_bkPip, an) == 2, BaseKnotLadderHopAt(5, 129.0 * g_bkPip, an), 2);
   BkCheck("h=136.8 holds it too - no knife edge",        BaseKnotLadderHopAt(5, 136.8 * g_bkPip, an) == 2, BaseKnotLadderHopAt(5, 136.8 * g_bkPip, an), 2);
   BkCheck("h=250.0 cannot hold the fourth's (267.27)",   BaseKnotLadderHopAt(5, 250.0 * g_bkPip, an) == 2, BaseKnotLadderHopAt(5, 250.0 * g_bkPip, an), 2);
   //     ... and a ladder with NO fourth rung is an absence, never a guess: three rows only.
   {
      int      t3[3]  = {5, 15, 60};
      BaseKnotAbilityReset();   // the four rows above would answer for the rung we are removing
      for(int i = 0; i < 3; i++) BaseKnotAbilityPush(t3[i], an, BkRowEng(t3[i]) * g_bkPip, 8.3 * g_bkPip);
      BkCheck("hop = -1 when the 4th rung is cold", BaseKnotLadderHopAt(5, 136.8 * g_bkPip, an) == -1, BaseKnotLadderHopAt(5, 136.8 * g_bkPip, an), -1);
      BkPushRows(an);   // the four rows the rest of the test reads (Reset + push + EngPush)
   }
   //     ... and the name's own answer is still there for a caller that cannot know the box:
   BkCheck("the name still answers 3 for OTR", BaseKnotMeasureTFMin(BK_NODE_OTR, 5) == 240, BaseKnotMeasureTFMin(BK_NODE_OTR, 5), 240);
   BkCheck("the pushed hop answers 2 for the same OTR", BaseKnotMeasureTFMin(BK_NODE_OTR, 5, 2) == 60, BaseKnotMeasureTFMin(BK_NODE_OTR, 5, 2), 60);

   //---- 5c. THE TWINS, END TO END: BK-0003 and BK-0004 are the SAME box 4 s apart, +7.8 pips
   //     taller (+6.0 %), and v1 charged the second one 72.9 pips of stop against the first's
   //     32.0 — a 2.28x jump. v2 answered round(u) and put both on the structure's rung; v3
   //     (P-BK-128) asks the capacity question instead and lands them there too — 136.8 pips
   //     holds 0.859 x 136.3 = 117.1 of legs, and 250.0 (the next rung's 267.3) does not.
   double twinBot = bot;
   double e3 = 0.0, s3 = 0.0, o3 = 0.0, r3 = 0.0;
   double e4 = 0.0, s4 = 0.0, o4 = 0.0, r4 = 0.0;
   BaseKnotCalcLevels(bot + 129.0 * g_bkPip, twinBot, +1, BK_NODE_CTR, 5, e3, s3, o3, r3, an);   // BK-0003, v1 and v2 alike
   BaseKnotCalcLevels(bot + 136.8 * g_bkPip, twinBot, +1, BK_NODE_OTR, 5, e4, s4, o4, r4, an);   // BK-0004 by NAME (v1)
   double e5 = 0.0, s5 = 0.0, o5 = 0.0, r5 = 0.0;
   BaseKnotCalcLevels(bot + 136.8 * g_bkPip, twinBot, +1, BK_NODE_OTR, 5, e5, s5, o5, r5, an,
                      BaseKnotLadderHopAt(5, 136.8 * g_bkPip, an));                            // BK-0004 on the LADDER (v2)
   BkCheck("BK-0003 stop = 31.9 (the M60 EngSL)",    BkNear(r3, 31.9, 0.05), r3, 31.9);
   //     the log's 32.0 is the same number off an UNROUNDED ATR (136.3 here is 1 dp), so the
   //     tick level reads 74.0 where the plan's pips say 75 — the tick grid, not a defect.
   BkCheck("BK-0003 TP1 = 74.0 (tick-rounded)",      BkNear(BaseKnotToPips(MathAbs(BaseKnotTPLevel(e3, +1, 60, 1, an) - e3)), 74.0, 0.6), BaseKnotToPips(MathAbs(BaseKnotTPLevel(e3, +1, 60, 1, an) - e3)), 74.0);
   BkCheck("BK-0004 by name = 72.9 (v1)",            BkNear(r4, 72.9, 0.05), r4, 72.9);
   BkCheck("BK-0004 on the ladder = 31.9 (v2)",      BkNear(r5, 31.9, 0.05), r5, 31.9);
   BkCheck("the twins now share one stop",           BkNear(r3, r5, 0.05), r5, r3);

   //---- 5d. THE KNOT'S TIME (P-BK-126): three candles standing still, on ANY timeframe,
   //     with the WHOLE candle inside the box. The fixtures below are hand-built M1 windows,
   //     so the numbers are the rule itself and not a series the terminal happens to hold.
   //     `t[]` is NEWEST FIRST, exactly the shape BaseKnotM1Window produces.
   {
      //     P-BK-126c: the grid is the CLOCK's, so the fixture is aligned to it (s2 on a whole
      //     day) — otherwise a bucket boundary falls mid-bar and the numbers describe the
      //     fixture's phase, not the rule. Every number below is that grid's OWN answer: the
      //     edge-cut grid this replaced read 2 at 3m and 1 at 8m off the very same bars.
      datetime s2 = (datetime)86400000;
      datetime t[6]; double h[6], l[6];
      for(int i = 0; i < 6; i++) { t[i] = s2 - i * 60; h[i] = 99.0; l[i] = 91.0; }
      //     A WICK THAT CLEARS THE BOX IS NOT STANDING STILL. The OLDEST bar's body is inside
      //     [90,100] but its high is 101, so the newest run is two candles -> 2, never 3. The
      //     retired read asked open/close only and would have answered 3 here.
      double hw[3], lw[3]; datetime tw[3];
      for(int i = 0; i < 3; i++) { tw[i] = s2 - i * 60; hw[i] = 99.0; lw[i] = 91.0; }
      hw[2] = 101.0;                                     // the wick that leaves the box
      int cWick = BaseKnotStillCount(1, s2, tw, hw, lw, 3, 100.0, 90.0);
      BkCheck("a candle whose WICK clears the box does not stand still", cWick == 2, cWick, 2);
      int cAll = BaseKnotStillCount(1, s2, t, h, l, 6, 100.0, 90.0);
      BkCheck("six still M1 candles -> the count stops at 3", cAll == 3, cAll, 3);
      int c2 = BaseKnotStillCount(2, s2, t, h, l, 6, 100.0, 90.0);
      BkCheck("the same six read at 2m -> three candles, all still", c2 == 3, c2, 3);
      int c3 = BaseKnotStillCount(3, s2, t, h, l, 6, 100.0, 90.0);
      BkCheck("3m on the CLOCK's grid -> three buckets, all still (the edge grid read 2)", c3 == 3, c3, 3);
      //     EIGHT MINUTES IS NOT A METATRADER TIMEFRAME and it is not on the ladder — the
      //     whole point of P-BK-126. It must be READ (two clock buckets over the 6-minute
      //     window), never refused with -1.
      int c8 = BaseKnotStillCount(8, s2, t, h, l, 6, 100.0, 90.0);
      BkCheck("8m is read like any other time (never -1)", c8 == 2, c8, 2);
      //     P-BK-126c — ONE BAND, ONE ANSWER. The box' edge only CLOSES the window: the same
      //     bars read with the edge 55 s further on are the same three 3m candles.
      int cEdge = BaseKnotStillCount(3, s2 + 55, t, h, l, 6, 100.0, 90.0);
      BkCheck("an edge 55 s further on cannot move the knot", cEdge == c3, cEdge, c3);
      int cNone = BaseKnotStillCount(8, s2, t, h, l, 0, 100.0, 90.0);
      BkCheck("no series -> -1, never a 0 dressed up as an answer", cNone == -1, cNone, -1);
      //     P-BK-126d/e — THE CLASS IS THE COUNT OVER THREE, AND NOTHING ELSE IS ITS INPUT. The
      //     first two numbers are the user's own two screenshots of ONE knot: 12 bars of M5 read
      //     20m and 8 bars read 13m (13.33 truncated, never rounded up to a ladder rung). The
      //     third says the box' own two ends and its prices cannot move that class at all — the
      //     entry..exit run does (P-BK-126e), which is why the run, not the rectangle, is read.
      int n12 = BaseKnotBaseTFRead(12, s2 - 3600, s2, 100.0, 90.0, 5);
      BkCheck("12 bars of M5 -> 20m (the user's own sample)", n12 == 20, n12, 20);
      int n8 = BaseKnotBaseTFRead(8, s2 - 3600, s2, 100.0, 90.0, 5);
      BkCheck("8 bars of M5 -> 13m (the other screenshot)", n8 == 13, n8, 13);
      int nEdges = BaseKnotBaseTFRead(12, s2 - 86400, s2 + 400, 2000.0, 10.0, 5);
      BkCheck("... and the box' times and prices cannot move the class", nEdges == n12, nEdges, n12);
   }

   //---- print the record so the proof is in the log, not only in a folder
   for(int i = 0; i < n; i++) Print("[BKSHOT] | ", lines[i]);

   //---- 6. LEAVE NO TRACE. A leftover folder would be filed as a real sample.
   FileDelete(txtP);
   FileDelete(pngP);
   bool gone = FolderDelete(dir);
   BkCheck("the test folder is gone", gone, gone ? 1 : 0, 1);

   ObjectDelete(0, box);
   ObjectDelete(0, BaseKnotEntryName(pfx));
   ObjectDelete(0, BaseKnotSLName(pfx));
   for(int i = 1; i <= 3; i++) ObjectDelete(0, BaseKnotTPTickName(pfx, i));
   ObjectDelete(0, BK_SHOT_FLASH);
   BaseKnotUnregister(id);

   Print("[BKSHOT] DONE pass=", g_bkPass, " fail=", g_bkFail);
}
