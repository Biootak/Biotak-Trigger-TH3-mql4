import io
p = 'Biotak/TH3Recorder.mqh'
s = io.open(p, encoding='utf-8').read()
BS = chr(92)


def rep(old, new, cnt=1):
    global s
    assert old in s, old[:90]
    s = s.replace(old, new, cnt)


# --- the header block now describes the per-sample folder
old_hdr = ('//| under MQL4' + BS + 'Files' + BS + 'TH3_Dataset' + BS +
           '{Screenshots,Logs}, and one row in   |\n'
           '//| the master CSV beside them.                                       |')
new_hdr = ('//| INSIDE ITS OWN FOLDER under                                       |\n'
           '//| MQL4' + BS + 'Files' + BS + 'TH3_Dataset' + BS +
           'Samples' + BS + '<date>-<clock>_<SYM>_<TF>_S<NNN>,   |\n'
           '//| one row in that folder sample.csv, and one row in the global    |\n'
           '//| TH3_Dataset' + BS + 'Dataset.csv beside them (P-TH3-DB).        |')
rep(old_hdr, new_hdr)

rep('''   bool dirsOk = false;
   TH3RecorderEnsureDirs(dirsOk);
   string sampleId = StringFormat("Sample_%03d", idx);
   string shotName  = StringFormat("Sample_%03d_%s_%s.png", idx, Symbol(), TH3TfName(Period()));
   string logName   = sampleId + ".txt";
   string shotPath  = TH3RecorderPath(TH3_DATASET_SHOTS, shotName, dirsOk);
   string logPath   = TH3RecorderPath(TH3_DATASET_LOGS,  logName,  dirsOk);
   string csvPath   = TH3RecorderPath(TH3_DATASET_DIR,   "Master_Dataset.csv", dirsOk);
''',
    '''   bool dirsOk = false;
   TH3RecorderEnsureDirs(dirsOk);
   datetime capAt = TimeCurrent();               // the press, not the D bar
   string sampleId = StringFormat("Sample_%03d", idx);
   string tfName   = TH3TfName(Period());
   string shotName = StringFormat("Sample_%03d_%s_%s.png", idx, Symbol(), tfName);
   string logName  = sampleId + ".txt";

   //--- P-TH3-DB (2026-10-05) - ONE FOLDER PER SAMPLE. The flat pair forced
   //--- a reader to join Sample_015.txt with Sample_015_EURUSD_M5.png by NAME
   //--- and then read its numbers out of prose; a sample nobody can take in
   //--- one glance is a sample nobody reviews. The folder is named from facts
   //--- the sample already carries - capture stamp, symbol, timeframe, counter
   //--- and pattern - so the tree sorts by time with no database at all, and
   //--- the name itself is the key a tool parses.
   string folderName = TH3SampleFolderName(capAt, Symbol(), tfName, idx, patName);
   string sampleDir  = TH3_DATASET_SAMPLES + "/" + folderName;
   bool sampleOk     = dirsOk && (FolderCreate(sampleDir) >= 0);
   string shotPath, logPath, rowPath;
   if(sampleOk)
   {
      shotPath = sampleDir + "/" + shotName;
      logPath  = sampleDir + "/" + logName;
      rowPath  = sampleDir + "/sample.csv";
   }
   else
   {
      //--- a refused folder is NOT a lost sample: the flat pair still holds
      //--- the same three files, and the TXT says which mode wrote it.
      shotPath = TH3RecorderPath(TH3_DATASET_SHOTS, shotName, dirsOk);
      logPath  = TH3RecorderPath(TH3_DATASET_LOGS,  logName,  dirsOk);
      rowPath  = TH3RecorderPath(TH3_DATASET_LOGS,  sampleId + ".csv", dirsOk);
   }
   string csvPath = TH3RecorderPath(TH3_DATASET_DIR, TH3_DATASET_DB_NAME, dirsOk);

   //--- P-TH3-DB - THE ROW, BUILT ONCE AND WRITTEN TWICE. The sample's own
   //--- CSV travels with its folder; the global Dataset.csv is the one file a
   //--- reader can sort, filter and pivot without opening twenty folders. Both
   //--- come from THIS array and from the header TH3DatasetHeader() owns, so
   //--- the two copies cannot drift the way two hand-written headers do.
   string row[];
   ArrayResize(row, TH3_DATASET_COLS);
   row[0]  = sampleId;
   row[1]  = TimeToString(capAt, TIME_DATE);
   row[2]  = TimeToString(capAt, TIME_MINUTES);
   row[3]  = TH3SampleStamp(capAt);
   row[4]  = Symbol();
   row[5]  = tfName;
   row[6]  = TH3TfName(ownerTF);
   row[7]  = TH3CsvField(patName);
   row[8]  = dirDown ? "down" : "up";
   row[9]  = TimeToString(pat.D.time);
   row[10] = DoubleToString(pat.D.price, Digits);
   row[11] = IntegerToString(Digits);
   row[12] = DoubleToString(pip, Digits);
   row[13] = DoubleToString(motherIn / pip, 1);
   row[14] = DoubleToString(legAB / pip, 1);
   row[15] = DoubleToString(legBC / pip, 1);
   row[16] = DoubleToString(legCD / pip, 1);
   row[17] = DoubleToString(ratioBC_AB, 3);
   row[18] = DoubleToString(ratioCD_BC, 3);
   row[19] = DoubleToString(kFactor, 3);
   row[20] = DoubleToString(stepMother / pip, 1);
   row[21] = DoubleToString(stepPattern / pip, 1);
   row[22] = DoubleToString(baseUnit / pip, 1);
   row[23] = DoubleToString(lv[0], Digits);
   row[24] = DoubleToString(lv[2], Digits);
   row[25] = DoubleToString(lv[4], Digits);
   row[26] = DoubleToString(lv[6], Digits);
   row[27] = hasTurn ? DoubleToString(turnPx, Digits) : "";
   row[28] = hasTurn ? DoubleToString(errPips, 1) : "";
   row[29] = hasTurn ? IntegerToString(hp.deepestRungs) : "0";
   row[30] = sampleOk ? folderName : "";
   row[31] = logName;
   row[32] = shotName;
''')

rep('''      FileWrite(fh, "DATETIME_D: " + TimeToString(pat.D.time));
      FileWrite(fh, "PATTERN: " + patName);
      FileWrite(fh, "DATASET_PATH_MODE: " + (dirsOk ? "TH3_Dataset/" : "flat (FolderCreate refused)"));''',
    '''      FileWrite(fh, "CAPTURE_TIME: " + TimeToString(capAt, TIME_DATE|TIME_SECONDS));
      FileWrite(fh, "CAPTURE_STAMP: " + TH3SampleStamp(capAt));
      FileWrite(fh, "DATETIME_D: " + TimeToString(pat.D.time));
      FileWrite(fh, "PATTERN: " + patName);
      FileWrite(fh, "SAMPLE_FOLDER: " + (sampleOk ? folderName : "(none - flat fallback)"));
      FileWrite(fh, "DATASET_PATH_MODE: " + (sampleOk ? "TH3_Dataset/Samples/<folder>/"
                                                     : "flat (FolderCreate refused)"));''')

rep('''      FileWrite(fh, "PROJECT_COPY: " + TH3RecorderProjectDir() + "/Screenshots/" + shotName);
      FileWrite(fh, "PROJECT_COPY_LOG: " + TH3RecorderProjectDir() + "/Logs/" + logName);''',
    '''      FileWrite(fh, "PROJECT_COPY: " + TH3RecorderProjectDir() + "/Samples/" + folderName + "/" + shotName);
      FileWrite(fh, "PROJECT_COPY_LOG: " + TH3RecorderProjectDir() + "/Samples/" + folderName + "/" + logName);
      FileWrite(fh, "PROJECT_COPY_ROW: " + TH3RecorderProjectDir() + "/Samples/" + folderName + "/sample.csv");
      FileWrite(fh, "PROJECT_COPY_DB: " + TH3RecorderProjectDir() + "/" + TH3_DATASET_DB_NAME);''')

rep('''   //--- the master CSV: header on the empty file, then ONE appended row
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
   if(okShot && okTxt && okCsv)''',
    '''   //--- the sample's own CSV: the header plus exactly one row, inside its folder
   bool okRow = false;
   int rh = FileOpen(rowPath, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(rh != INVALID_HANDLE)
   {
      string hdr[];
      TH3DatasetHeader(hdr);
      FileWriteArray(rh, hdr);
      FileWriteArray(rh, row);
      FileClose(rh);
      rh = INVALID_HANDLE;
      okRow = true;
   }

   //--- the global DB: the header on the empty file, then ONE appended row
   bool okCsv = false;
   int ch = FileOpen(csvPath, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(ch != INVALID_HANDLE)
   {
      string hdr[];
      TH3DatasetHeader(hdr);
      if(FileSize(ch) == 0) FileWriteArray(ch, hdr);
      FileSeek(ch, 0, SEEK_END);
      FileWriteArray(ch, row);
      FileClose(ch);
      ch = INVALID_HANDLE;
      okCsv = true;
   }
   if(okShot && okTxt && okRow && okCsv)''')

rep('''      string bad = StringFormat("FAILED #%03d  png:%s txt:%s csv:%s",
                                idx, (okShot ? "ok" : "X"), (okTxt ? "ok" : "X"), (okCsv ? "ok" : "X"));
      Print("[TH3 RECORDER] Sample #", idx, " FAILED (shot=", okShot, " txt=", okTxt,
            " csv=", okCsv, ")''',
    '''      string bad = StringFormat("FAILED #%03d  png:%s txt:%s row:%s db:%s",
                                idx, (okShot ? "ok" : "X"), (okTxt ? "ok" : "X"),
                                (okRow ? "ok" : "X"), (okCsv ? "ok" : "X"));
      Print("[TH3 RECORDER] Sample #", idx, " FAILED (shot=", okShot, " txt=", okTxt,
            " row=", okRow, " db=", okCsv, ")''')

io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('recorder patched')