// TH3Recorder.mqh - split from TH3Tool_C.mqh 2026-10-05 (P-SIZE-1500):
// the interactive audit recorder, by owner. Same names, same output.
#ifndef TH3_RECORDER_MQH
#define TH3_RECORDER_MQH

//+------------------------------------------------------------------+
//| P-TH3-REC (2026-10-05) — INTERACTIVE AUDIT RECORDER (key M, 77).  |
//| Snapshots the ACTIVE pattern for off-terminal formula validation: |
//| a PNG beside a TXT diagnostic plus one Master-CSV row, all flat   |
//| in MQL4\Files (MQL4 cannot create subfolders, so no TH3_Dataset/   |
//| tree). Counter lives in a chart-scoped GlobalVariable, 1..100; the |
//| banner is Comment(), overwritten by the next capture. The observed |
//| turn reuses the proof diagnostic (TH3HitPivotMeasure); an         |
//| unreacted chart records none. User-paced: one ~0.5 s settle Sleep  |
//| per press so the centered view is what the PNG holds.              |
//+------------------------------------------------------------------+
void TH3_ExportCurrentSample()
{
    if(g_activeABCDPattern == "")
    {
        Print("[TH3 RECORDER] no active pattern — place an ABCD first.");
        return;
    }
    TH3Pattern pat;
    if(!TH3PatternStoreGet(g_activeABCDPattern, pat) || pat.D.time <= 0 || pat.D.price <= 0)
    {
        Print("[TH3 RECORDER] active pattern has no D — nothing to export.");
        return;
    }
    double pip = GetCachedPipSize();
    if(!(pip > 0)) pip = Point;

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
    bool dirDown = (pat.D.price > pat.C.price);
    double lv[7];
    for(int li = 0; li < 7; li++)
        lv[li] = dirDown ? pat.D.price - ((li + 1) * baseUnit)
                         : pat.D.price + ((li + 1) * baseUnit);
    double closedStep = 0, closedK = 0, closedRatio = 0;
    TH3ClosedStepFromLegs(pat.B.price, pat.C.price, pat.D.price, closedStep, closedK, closedRatio);
    TH3HitProof hp;
    bool hitOK = TH3HitPivotMeasure(pat.D.time, pat.D.price, dirDown, baseUnit, hp, closedStep);
    bool hasTurn = (hitOK && hp.deepestRungs > 0);
    double turnPx = hasTurn ? hp.tipPrice : 0.0;
    double errPips = hasTurn ? MathAbs(turnPx - lv[2]) / pip : 0.0;

    string gvName = "Biotak_TH3Sample_" + GetCachedChartIdStr();
    int idx = 0;
    if(GlobalVariableCheck(gvName)) idx = (int)GlobalVariableGet(gvName);
    idx++;
    if(idx > 100)
    {
        Print("[TH3 RECORDER] dataset full (100) — nothing written.");
        return;
    }
    string tag = StringFormat("TH3_Sample_%03d_%s_%s", idx, Symbol(), TH3TfName(Period()));
    int sh = iBarShift(NULL, 0, pat.D.time);
    int pos = sh - 30;
    if(pos < 0 || sh < 0) pos = 0;
    ChartNavigate(0, CHART_END, pos);
    ChartRedraw();
    Sleep(500);
    bool okShot = WindowScreenShot(tag + ".png", 1920, 1080);

    int fh = FileOpen(tag + ".txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
    bool okTxt = (fh != INVALID_HANDLE);
    if(okTxt)
    {
        FileWrite(fh, "SAMPLE_ID: Sample_" + StringFormat("%03d", idx));
        FileWrite(fh, "SYMBOL: " + Symbol());
        FileWrite(fh, "TIMEFRAME: " + TH3TfName(Period()));
        FileWrite(fh, "DATETIME_D: " + TimeToString(pat.D.time));
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
        FileWrite(fh, "  Type: External_Historical_Shelf");
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
        FileWrite(fh, "  Observed_Turn: " + (hasTurn ? DoubleToString(turnPx, Digits) : "none"));
        FileWrite(fh, "  Error_Margin_Pips: " + DoubleToString(errPips, 1));
        FileClose(fh);
        fh = INVALID_HANDLE;
    }
    bool okCsv = false;
    int ch = FileOpen("TH3_Master_Dataset.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
    if(ch != INVALID_HANDLE)
    {
        if(FileSize(ch) == 0)
            FileWrite(ch, "Sample_ID", "Symbol", "TF", "DateTime_D", "Mother_Pips",
                      "LegAB", "LegBC", "LegCD", "Ratio", "K", "Step_Pips",
                      "L3_Target", "Actual_Turn", "Error_Pips", "Screenshot_Path");
        FileSeek(ch, 0, SEEK_END);
        FileWrite(ch, StringFormat("Sample_%03d", idx), Symbol(), TH3TfName(Period()),
                  TimeToString(pat.D.time),
                  DoubleToString(motherIn / pip, 1),
                  DoubleToString(legAB / pip, 1), DoubleToString(legBC / pip, 1),
                  DoubleToString(legCD / pip, 1), DoubleToString(ratioCD_BC, 3),
                  DoubleToString(kFactor, 3), DoubleToString(baseUnit / pip, 1),
                  DoubleToString(lv[2], Digits),
                  (hasTurn ? DoubleToString(turnPx, Digits) : "none"),
                  DoubleToString(errPips, 1), tag + ".png");
        FileClose(ch);
        okCsv = true;
    }
    if(okShot && okTxt && okCsv)
    {
        GlobalVariableSet(gvName, idx);
        string msg = StringFormat("[TH3 RECORDER] Sample #%03d saved | Log & Screenshot exported.", idx);
        Comment(msg);
        Print(msg);
    }
    else
    {
        if(fh != INVALID_HANDLE) FileClose(fh);
        Print("[TH3 RECORDER] export failed (shot=", okShot, " txt=", okTxt, " csv=", okCsv, ") — counter kept.");
    }
    ThrottledChartRedraw();
}

#endif // TH3_RECORDER_MQH
