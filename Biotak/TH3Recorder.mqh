// TH3Recorder.mqh - split from TH3Tool_C.mqh 2026-10-05 (P-SIZE-1500):
// the interactive audit recorder, by owner.
#ifndef TH3_RECORDER_MQH
#define TH3_RECORDER_MQH

//--- the dataset tree is one owner's (TH3DatasetPaths.mqh): the recorder
//--- writes through it and the harness pins the SAME names, so a reader and
//--- the writer can never disagree about where a sample lands.
#include "TH3/TH3DatasetPaths.mqh"

//+------------------------------------------------------------------+
//| P-TH3-REC (2026-10-05) — INTERACTIVE AUDIT RECORDER (key M, 77).  |
//| Human visual discretion is mandatory for telling a valid market   |
//| structure from an invented one, so the trader anchors the pattern |
//| and the mother pivot BY HAND and this captures the sample for     |
//| off-terminal formula validation: a PNG plus a full diagnostic TXT |
//| under MQL4\Files\TH3_Dataset\{Screenshots,Logs}, and one row in   |
//| the master CSV beside them.                                       |
//|                                                                  |
//| THE TREE (spec §4.B.1) is owned by TH3/TH3DatasetPaths.mqh,     |
//| which the harness includes too — one home for the folder names,  |
//| so the writer and a reader of the dataset cannot disagree.       |
//|                                                                  |
//| THE COUNTER lives in a chart-scoped GlobalVariable, 1..100, and   |
//| advances only when all three artifacts land — a partial export    |
//| keeps its number so a retry cannot overwrite a good sample with a |
//| half-written one. The banner is Comment(), overwritten by the    |
//| next capture. The observed turn reuses the proof diagnostic       |
//| (TH3HitPivotMeasure); an unreacted chart records none.            |
//| User-paced: one ~0.5 s settle Sleep per press so the centered    |
//| view is what the PNG holds.                                      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-TH3-REC — the capture. One press, one sample.                  |
//| `patternName` is the ACTIVE pattern's name (the spec's call site  |
//| passes g_activeABCDPattern); an empty argument means "whatever is |
//| active", so a caller that has no name is answered, not refused.    |
//+------------------------------------------------------------------+
void TH3_ExportCurrentSample(const string patternName = "")
{
   string patName = (patternName != "") ? patternName : g_activeABCDPattern;
   if(patName == "")
   {
      Print("[TH3 RECORDER] no active pattern — place an ABCD first.");
      return;
   }
   TH3Pattern pat;
   if(!TH3PatternStoreGet(patName, pat) || pat.D.time <= 0 || pat.D.price <= 0)
   {
      Print("[TH3 RECORDER] active pattern has no D — nothing to export.");
      return;
   }
   double pip = GetCachedPipSize();
   if(!(pip > 0)) pip = Point;

   //--- the formula's own inputs, read exactly as the renderer reads them
   double legAB = MathAbs(pat.B.price - pat.A.price);
   double legBC = MathAbs(pat.C.price - pat.B.price);
   double legCD = MathAbs(pat.D.price - pat.C.price);
   double ratioBC_AB = (legAB > 0) ? legBC / legAB : 0.0;
   double ratioCD_BC = (legBC > 0) ? legCD / legBC : 0.0;
   double kFactor = TH3UnifiedK(ratioCD_BC);
   double motherIn = TH3ManualBaseStep(inpTH3PivotBasePips, pip);
   int cdBars = TH3ClosedBars(pat.C.time, pat.D.time);
   int ownerTF = TH3ClosedOwnerTF(cdBars);
   double rung = TH3PatternStepRungTF(ownerTF);
   if(rung <= 0) rung = TH3PatternStepRung();
   double stepMother = (motherIn >= 2.5 * rung) ? (motherIn / 3.0) : motherIn;
   if(stepMother <= 0) stepMother = rung;
   double stepPattern = (kFactor > 0) ? legCD / kFactor : 0.0;
   double baseUnit = CalculateUnifiedMasterStep(legCD, ratioCD_BC, motherIn, rung);
   if(baseUnit <= 0)
      baseUnit = (rung > 0) ? rung
                 : ((legCD > 0 ? legCD : MathAbs(pat.B.price - pat.A.price)) * (GetCurrentTH3Frequency() / 100.0));
   //--- the ladder, projected from D along the movement direction
   bool dirDown = (pat.D.price > pat.C.price);
   double lv[7];
   for(int li = 0; li < 7; li++)
      lv[li] = dirDown ? pat.D.price - ((li + 1) * baseUnit)
                       : pat.D.price + ((li + 1) * baseUnit);
   //--- the observed turn: DIAGNOSTIC ONLY. TH3HitPivotMeasure reads the
   //--- closed bars; P-TH3-STEP-16 forbids it from touching baseUnit, and
   //--- here it only fills MARKET_REACTION so the error margin is measured.
   double closedStep = 0, closedK = 0, closedRatio = 0;
   TH3ClosedStepFromLegs(pat.B.price, pat.C.price, pat.D.price, closedStep, closedK, closedRatio);
   TH3HitProof hp;
   bool hitOK = TH3HitPivotMeasure(pat.D.time, pat.D.price, dirDown, baseUnit, hp, closedStep);
   bool hasTurn = (hitOK && hp.deepestRungs > 0);
   double turnPx = hasTurn ? hp.tipPrice : 0.0;
   double errPips = hasTurn ? MathAbs(turnPx - lv[2]) / pip : 0.0;

   //--- the index. The GLOBAL is the counter's only home, so two charts of
   //--- one symbol never share a number.
   string gvName = "Biotak_TH3Sample_" + GetCachedChartIdStr();
   int idx = 0;
   if(GlobalVariableCheck(gvName)) idx = (int)GlobalVariableGet(gvName);
   idx++;
   if(idx > TH3_RECORDER_MAX)
   {
      Print("[TH3 RECORDER] dataset full (", TH3_RECORDER_MAX, ") — nothing written.");
      return;
   }

   bool dirsOk = false;
   TH3RecorderEnsureDirs(dirsOk);
   string sampleId = StringFormat("Sample_%03d", idx);
   string shotName  = StringFormat("Sample_%03d_%s_%s.png", idx, Symbol(), TH3TfName(Period()));
   string logName   = sampleId + ".txt";
   string shotPath  = TH3RecorderPath(TH3_DATASET_SHOTS, shotName, dirsOk);
   string logPath   = TH3RecorderPath(TH3_DATASET_LOGS,  logName,  dirsOk);
   string csvPath   = TH3RecorderPath(TH3_DATASET_DIR,   "Master_Dataset.csv", dirsOk);

   //--- center the chart on Point D and the forward reaction
   int sh = iBarShift(NULL, 0, pat.D.time);
   int pos = sh - 30;
   if(pos < 0 || sh < 0) pos = 0;
   ChartNavigate(0, CHART_END, pos);
   ChartRedraw();
   Sleep(500);
   bool okShot = WindowScreenShot(shotPath, 1920, 1080);

   int fh = FileOpen(logPath, FILE_WRITE | FILE_TXT | FILE_ANSI);
   bool okTxt = (fh != INVALID_HANDLE);
   if(okTxt)
   {
      FileWrite(fh, "SAMPLE_ID: " + sampleId);
      FileWrite(fh, "SYMBOL: " + Symbol());
      FileWrite(fh, "TIMEFRAME: " + TH3TfName(Period()));
      FileWrite(fh, "DATETIME_D: " + TimeToString(pat.D.time));
      FileWrite(fh, "PATTERN: " + patName);
      FileWrite(fh, "DATASET_PATH_MODE: " + (dirsOk ? "TH3_Dataset/" : "flat (FolderCreate refused)"));
      FileWrite(fh, "OWNER_TF: " + TH3TfName(ownerTF));
      FileWrite(fh, "COORDINATES:");
      FileWrite(fh, "  Point_A: {Price: " + DoubleToString(pat.A.price, Digits) + ", Time: " + TimeToString(pat.A.time) + "}");
      FileWrite(fh, "  Point_B: {Price: " + DoubleToString(pat.B.price, Digits) + ", Time: " + TimeToString(pat.B.time) + "}");
      FileWrite(fh, "  Point_C: {Price: " + DoubleToString(pat.C.price, Digits) + ", Time: " + TimeToString(pat.C.time) + "}");
      FileWrite(fh, "  Point_D: {Price: " + DoubleToString(pat.D.price, Digits) + ", Time: " + TimeToString(pat.D.time) + "}");
      FileWrite(fh, "LEGS:");
      FileWrite(fh, "  Leg_AB_Pips: " + DoubleToString(legAB / pip, 1));
      FileWrite(fh, "  Leg_BC_Pips: " + DoubleToString(legBC / pip, 1));
      FileWrite(fh, "  Leg_CD_Pips: " + DoubleToString(legCD / pip, 1));
      FileWrite(fh, "  Ratio_BC_AB: " + DoubleToString(ratioBC_AB, 3));
      FileWrite(fh, "  Ratio_CD_BC: " + DoubleToString(ratioCD_BC, 3));
      FileWrite(fh, "  K_Factor: " + DoubleToString(kFactor, 3));
      FileWrite(fh, "MOTHER_PIVOT:");
      FileWrite(fh, "  Size_Pips: " + DoubleToString(motherIn / pip, 1));
      FileWrite(fh, "  Type: \"External_Historical_Shelf\"");
      FileWrite(fh, "FORMULA_OUTPUT:");
      FileWrite(fh, "  Step_Mother: " + DoubleToString(stepMother / pip, 1));
      FileWrite(fh, "  Step_Pattern: " + DoubleToString(stepPattern / pip, 1));
      FileWrite(fh, "  Final_Step_BaseUnit: " + DoubleToString(baseUnit / pip, 1));
      FileWrite(fh, "LADDER_TARGETS:");
      FileWrite(fh, "  Step_1: " + DoubleToString(lv[0], Digits));
      FileWrite(fh, "  Step_2_Mid: " + DoubleToString(lv[1], Digits));
      FileWrite(fh, "  Step_3_Target: " + DoubleToString(lv[2], Digits));
      FileWrite(fh, "  Step_4_Mid: " + DoubleToString(lv[3], Digits));
      FileWrite(fh, "  Step_5_Target: " + DoubleToString(lv[4], Digits));
      FileWrite(fh, "  Step_6_Mid: " + DoubleToString(lv[5], Digits));
      FileWrite(fh, "  Step_7_Target: " + DoubleToString(lv[6], Digits));
      FileWrite(fh, "MARKET_REACTION:");
      FileWrite(fh, "  Actual_Reversal_Low: " + (hasTurn ? DoubleToString(turnPx, Digits) : "none"));
      FileWrite(fh, "  Actual_Reversal_High: " + (hasTurn ? DoubleToString(turnPx, Digits) : "none"));
      FileWrite(fh, "  Error_Margin_Pips: " + DoubleToString(errPips, 1));
      FileWrite(fh, "  Against: " + sampleId + " Step_3_Target");
      FileWrite(fh, "SCREENSHOT: " + shotPath);
      FileClose(fh);
      fh = INVALID_HANDLE;
   }

   //--- the master CSV: header on the empty file, then ONE appended row
   bool okCsv = false;
   int ch = FileOpen(csvPath, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(ch != INVALID_HANDLE)
   {
      if(FileSize(ch) == 0)
         FileWrite(ch, "Sample_ID", "Symbol", "TF", "DateTime_D", "Mother_Pips",
                   "LegAB", "LegBC", "LegCD", "Ratio", "K", "Step_Pips",
                   "L3_Target", "Actual_Turn", "Error_Pips", "Screenshot_Path");
      FileSeek(ch, 0, SEEK_END);
      FileWrite(ch, sampleId, Symbol(), TH3TfName(Period()),
                TimeToString(pat.D.time),
                DoubleToString(motherIn / pip, 1),
                DoubleToString(legAB / pip, 1), DoubleToString(legBC / pip, 1),
                DoubleToString(legCD / pip, 1), DoubleToString(ratioCD_BC, 3),
                DoubleToString(kFactor, 3), DoubleToString(baseUnit / pip, 1),
                DoubleToString(lv[2], Digits),
                (hasTurn ? DoubleToString(turnPx, Digits) : "none"),
                DoubleToString(errPips, 1), shotPath);
      FileClose(ch);
      okCsv = true;
   }
   if(okShot && okTxt && okCsv)
   {
      //--- the counter advances only on a COMPLETE export, so a retry cannot
      //--- reuse a number whose PNG or row is already on disk
      GlobalVariableSet(gvName, idx);
      string msg = StringFormat("[TH3 RECORDER] Sample #%03d Saved | Log & Screenshot Exported Successfully!", idx);
      Comment(msg);
      Print(msg);
   }
   else
   {
      if(fh != INVALID_HANDLE) FileClose(fh);
      Print("[TH3 RECORDER] export failed (shot=", okShot, " txt=", okTxt, " csv=", okCsv,
            ") — counter kept, nothing advanced.");
   }
   ThrottledChartRedraw();
}

#endif // TH3_RECORDER_MQH
