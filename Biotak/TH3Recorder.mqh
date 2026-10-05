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
//| P-TH3-REC-06 (2026-10-05) — THE MIRROR: SAMPLES REACH THE REPO.  |
//|                                                                   |
//| The samples were only ever in `MQL4\Files\TH3_Dataset`, which is   |
//| inside the TERMINAL's data folder. Nothing outside the machine    |
//| could see them, and deleting that folder (a reinstall, a "clean   |
//| up my MT4 data" step) destroys the whole labelled set — the one   |
//| asset the formula is being tuned AGAINST. So every artifact is    |
//| ALSO written into the PROJECT, where it is reviewable, diffable   |
//| and survives the terminal.                                        |
//|                                                                   |
//| MT4 CANNOT DO THIS ITSELF: `FileOpen` is sandboxed to the data    |
//| folder, so the project path is not writable from inside the       |
//| terminal. The copy is therefore the USER'S side: a one-line      |
//| `node tools/th3-dataset-sync.js` (or the tray) moves the same     |
//| files across. This function only REPORTS where to find them and   |
//| writes the pointer the sync reads — it never pretends to have     |
//| copied anything it could not.                                    |
//+------------------------------------------------------------------+
#define TH3_PROJECT_SAMPLES  "Samples/TH3_Dataset"

// Where the project copy must land, stated in the log and in every TXT so
// the sync and any reviewer read the SAME string. One home for the path.
string TH3RecorderProjectDir()
{
   return TH3_PROJECT_SAMPLES;
}

//+------------------------------------------------------------------+
//| P-TH3-REC-03 — THE ONE-SECOND PROOF, IN THE MIDDLE.              |
//| A capture with no visible answer reads as a capture that did     |
//| nothing, so the press paints one centred label and clears it.    |
//| `Comment()` was the wrong instrument twice over: it writes in the |
//| corner (where the eye is not) and it PERSISTS, so the next       |
//| capture would overwrite a message that had already done its job. |
//|                                                                   |
//| ONE OBJECT, one second, then it is deleted. OBJ_LABEL with       |
//| CORNER=0 (centre) and an absolute XY seat is how a label is       |
//| centred in MT4 — ANCHOR alone moves the text, not the box, and a |
//| centred box is what «وسط صفحه» means. The delete is UNCONDITIONAL |
//| (the same call on success and on failure), so a failed export    |
//| still leaves nothing behind and a second press cannot stack two. |
//|                                                                   |
//| It is created AFTER the screenshot, so the PNG holds the chart   |
//| and not the receipt.                                              |
//|                                                                   |
//| P-TH3-REC-04 (2026-10-05) — NO SLEEP. The first version slept a   |
//| second after painting the label, and it showed NOTHING: MT4 paints |
//| when the event handler RETURNS, so a Sleep inside OnChartEvent    |
//| froze the whole terminal with the label still unpainted, and the   |
//| delete on the far side of the Sleep removed it before it ever      |
//| reached the screen. The trader saw a one-second freeze — which is  |
//| exactly the «چیزی نمیاد، فقط فریز» report. The label is created,   |
//| the handler returns (so it paints), and the DELETE is owed to      |
//| OnTimer, which the project already runs every 250 ms (P-PERF-16).  |
//| Nothing blocks; the label lives exactly one second of wall clock.  |
//+------------------------------------------------------------------+
#define TH3_REC_FLASH_MS  1000
#define TH3_REC_FLASH_XML  "Biotak_TH3_RecorderFlash"

//--- the deadline is the terminal's own clock, not a frame count: a
//--- tick-less chart still ages the label out through OnTimer.
static datetime g_th3FlashDue = 0;

void TH3RecorderFlashClear()
{
   g_th3FlashDue = 0;
   if(ObjectFind(0, TH3_REC_FLASH_XML) >= 0) ObjectDelete(0, TH3_REC_FLASH_XML);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| The 250 ms OnTimer beat that ages the label out. One comparison   |
//| per tick of wall clock; the object exists for exactly the second  |
//| the trader asked for and not a millisecond of the next press.     |
//+------------------------------------------------------------------+
void TH3RecorderFlashTick()
{
   if(g_th3FlashDue == 0) return;          // nothing owed: the common case, one compare
   if(TimeCurrent() < g_th3FlashDue) return;
   TH3RecorderFlashClear();
}

void TH3RecorderFlash(const string msg)
{
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(w <= 0 || h <= 0) { w = 1024; h = 768; }   // never divide by nothing

   //--- P-TH3-REC-05 (2026-10-05) — THE SEAT IS MEASURED, NOT GUESSED. A
   //--- fixed 420px box for a message whose length is now a few characters put
   //--- the text off-centre («از هر طرف»): the LABEL centres the TEXT on its
   //--- anchor, so a too-wide box moves the text off the chart's middle by
   //--- half the slack. So the box is sized FROM the string (7 px per char at
   //--- the 13px face, plus the padding OBJ_LABEL's border adds) and the anchor
   //--- is then placed at the exact middle of what is left.
   //--- P-TH3-REC-05: a mono face, because the box width is DERIVED from the
   //--- string length. A proportional face makes that arithmetic a guess, and
   //--- a guess is exactly what put the text off the middle before. The face is
   //--- the product's own (BioChromeFont) so the receipt matches every other
   //--- caption on the chart.
   int fontSize = 13;
   int tw = (StringLen(msg) * 7) + 30;      // 7 px/char + padding + the 3px border
   if(tw < 110) tw = 110;                    // never a sliver
   if(tw > w - 20) tw = w - 20;               // never wider than the chart
   int th = fontSize + 18;

   //--- re-press: clear the previous one FIRST, so a fast second press never
   //--- stacks two labels and the old text never survives into the new second.
   if(ObjectFind(0, TH3_REC_FLASH_XML) >= 0) ObjectDelete(0, TH3_REC_FLASH_XML);

   if(ObjectCreate(0, TH3_REC_FLASH_XML, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_CORNER, 0);          // absolute
      //--- the middle of the CHART, on both axes, from the box's own size
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_XDISTANCE, (w - tw) / 2);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_YDISTANCE, (h - th) / 2);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, TH3_REC_FLASH_XML, OBJPROP_FONT, BioChromeFont(false));
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_WIDTH, 3);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_BACK, false);       // on the graph
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, TH3_REC_FLASH_XML, OBJPROP_HIDDEN, true);
      ObjectSetString(0, TH3_REC_FLASH_XML, OBJPROP_TEXT, msg);
   }
   ChartRedraw();

   //--- the one second is OWED to OnTimer, not slept here. Returning now is
   //--- what lets MT4 paint the label at all (see the header).
   g_th3FlashDue = TimeCurrent() + 1;
}

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

   //--- P-TH3-REC-02 (2026-10-05) — THE VIEW IS NOT OURS TO MOVE. The spec
   //--- said «center the chart on D», and this did: a ChartNavigate to 30 bars
   //--- before D plus a 0.5 s settle, so the capture showed a view the trader
   //--- never asked for — and on a chart whose D sits far back in history it
   //--- scrolled the whole screen to the left («دکمه m میزنم میره اول چارت»).
   //--- The trader has already framed the structure by hand; the capture's job
   //--- is to RECORD that frame, not to re-frame it. So the view is left alone
   //--- and the shot is one redraw away, with no Sleep either — a still chart
   //--- needs no settle, and the settle was the whole cost of the old path.
   ChartRedraw();

   //--- P-TH3-REC-04 (2026-10-05) — THE SHOT IS 1:1 WITH THE CHART, NOT A
   //--- STRETCH. The call passed a FIXED 1920x1080 while the chart is a
   //--- different size, and `WindowScreenShot` scales whatever it is given
   //--- into those numbers: the capture came out upscaled and soft, the caption
   //--- unreadable, and the exact price of a rung not legible off the picture —
   //--- which defeats the whole point of a dataset whose numbers have to be
   //--- checked against the pixels.
   //---
   //--- MEASURED on the user's own chart (2026-10-05, Samples 001/002): the
   //--- 1920x1080 PNGs held a plot area with the border at y=2 and y=1056 and
   //--- the caption plate 1018px tall — text rows of 9-12px, i.e. stretched
   //--- pixels, not rendered ones.
   //---
   //--- A HONEST LIMIT (the docs, docs.mql4.com/chart_operations/
   //--- windowscreenshot): the signature is
   //---   WindowScreenShot(filename, size_x, size_y, start_bar, scale, mode)
   //--- and it captures the CHART AREA ONLY — the toolbar, the Market Watch
   //--- and the desktop are outside what MQL4 can hand back. A true full-desktop
   //--- grab is not available from inside an indicator. What this now gives is
   //--- the widest TRUE capture: every bar, every rung and the caption at one
   //--- screen pixel per image pixel, sharp. `start_bar=0` pins the shot to the
   //--- bars currently on screen instead of the end-of-chart default, so the
   //--- frame the trader framed is the frame that is written.
   int shotW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int shotH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(shotW <= 0) shotW = 1920;   // never hand the API a zero width
   if(shotH <= 0) shotH = 1080;
   bool okShot = WindowScreenShot(shotPath, shotW, shotH, 0);

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
      //--- P-TH3-REC-04: the capture's own size, so a reader never has to guess
      //--- whether the PNG is 1:1 with the screen or a rescale of it.
      FileWrite(fh, "SCREENSHOT_SIZE: " + IntegerToString(shotW) + "x" + IntegerToString(shotH));
      FileWrite(fh, "SCREENSHOT_AREA: chart_only (MQL4 WindowScreenShot cannot reach the toolbar or desktop)");
      //--- P-TH3-REC-06: the project copy's name, so the file is findable from
      //--- the repo without knowing the sync tool. The terminal CANNOT write
      //--- there itself (FileOpen is sandboxed) — this is the pointer, not a
      //--- claim that it landed.
      FileWrite(fh, "PROJECT_COPY: " + TH3RecorderProjectDir() + "/Screenshots/" + shotName);
      FileWrite(fh, "PROJECT_COPY_LOG: " + TH3RecorderProjectDir() + "/Logs/" + logName);
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
      //--- P-TH3-REC-05: the ON-SCREEN receipt is short and LATIN, and the long
      //--- form stays in the journal and the TXT. Two reasons for the alphabet:
      //--- MT4 does not render Persian reliably on OBJ_LABEL (no on-chart label
      //--- in this whole product carries Persian — every one is Latin), and a
      //--- receipt a trader cannot read is no receipt. A receipt is read in a
      //--- glance, not parsed, and every character here is one the box has to
      //--- be sized around (see TH3RecorderFlash).
      string msg = StringFormat("SAVED  #%03d", idx);
      //--- P-TH3-REC-03: the proof is ON the screen, for ONE second, in the
      //--- MIDDLE. `Comment()` writes into the corner, where the eye is not and
      //--- where the next capture overwrites it — a press with no visible answer
      //--- reads as a press that did nothing. A centred label that clears itself
      //--- says «گرفته شد» without becoming furniture. Created after the shot,
      //--- so it never lands in the PNG.
      TH3RecorderFlash(msg);
      Print(msg);
   }
   else
   {
      if(fh != INVALID_HANDLE) FileClose(fh);
      string bad = StringFormat("FAILED #%03d  png:%s txt:%s csv:%s",
                                idx, (okShot ? "ok" : "X"), (okTxt ? "ok" : "X"), (okCsv ? "ok" : "X"));
      Print("[TH3 RECORDER] Sample #", idx, " FAILED (shot=", okShot, " txt=", okTxt,
            " csv=", okCsv, ") — nothing advanced.");
      //--- P-TH3-REC-03: the FAILURE gets the same one second. A silent miss is
      //--- the exact case the user cannot diagnose — the press looked identical
      //--- to the working one. The counter is deliberately NOT advanced.
      TH3RecorderFlash(bad);
      Print(bad);
   }
   //--- P-TH3-REC-03: the flash is gone either way, and this redraw is what
   //--- removes the last frame of it, so no label survives the press.
   ThrottledChartRedraw();
}

#endif // TH3_RECORDER_MQH
