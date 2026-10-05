//+------------------------------------------------------------------+
//| TH3/TH3DatasetPaths.mqh                                          |
//| P-TH3-REC — THE DATASET TREE, BY OWNER.                          |
//|                                                                  |
//| The recorder's paths are BEHAVIOUR, not text: a reader looking in |
//| MQL4\Files\TH3_Dataset must find a sample where the spec says.    |
//| This file is the ONE home for those paths so the recorder and the |
//| harness cannot disagree about where a sample lands. It is PURE:   |
//| string/datetime in, string out — no chart reads and no objects —  |
//| which is also what makes it harness-safe (P-BUILD-02:             |
//| Biotak_TH3_Test.mq4 cannot include the recorder itself, because    |
//| that pulls TH3Pivots_A/TH3Tool_A and the whole chart chain with  |
//| it).                                                             |
//|                                                                  |
//| MQL4 has no mkdir; the terminal's own FolderCreate is the only    |
//| way and it takes a path RELATIVE to MQL4\Files. It is idempotent  |
//| and returns 0 when the folder already exists, so these calls are |
//| safe on every press. A refusal is NOT fatal: the recorder then    |
//| falls back to the flat Screenshots/Logs pair and still records    |
//| the sample rather than losing it.                                |
//|                                                                  |
//| P-TH3-DB (2026-10-05) — ONE FOLDER PER SAMPLE, AND A DATABASE   |
//| THAT CAN BE READ WITHOUT OPENING A CHART. The flat pair put 20   |
//| shots in one folder and 20 TXT in another, so a reader had to    |
//| join Sample_015.txt with Sample_015_EURUSD_M5.png by NAME and    |
//| then read the numbers out of prose to compare them. Now every     |
//| sample owns a folder named <date>-<clock>_<SYMBOL>_<TF>_S<NNN>  |
//| [_<pattern>] holding its TXT, its PNG and its own one-row CSV,    |
//| and the global index TH3_Dataset/Dataset.csv holds one row per   |
//| sample with the date, the symbol, the timeframe, the pattern and |
//| the formula's answer beside the market's. The folder NAME is     |
//| derived from the capture stamp, so the tree sorts by time without |
//| a database, and the same rule is pinned by the harness.          |
//+------------------------------------------------------------------+
#ifndef TH3_DATASET_PATHS_MQH
#define TH3_DATASET_PATHS_MQH
#property strict

#define TH3_DATASET_DIR      "TH3_Dataset"
#define TH3_DATASET_SAMPLES  "TH3_Dataset/Samples"     // one folder per sample
#define TH3_DATASET_SHOTS    "TH3_Dataset/Screenshots"  // flat fallback only
#define TH3_DATASET_LOGS     "TH3_Dataset/Logs"         // flat fallback only
#define TH3_DATASET_DB_NAME  "Dataset.csv"
#define TH3_RECORDER_MAX     100

//+------------------------------------------------------------------+
//| The tree, and whether it took. `dirsOk` is the recorder's only   |
//| answer to "did the folders appear" — it is passed by reference so|
//| the caller can name the mode in its own output (the TXT says which|
//| path mode wrote it, so a flat fallback is never mistaken for the |
//| tree).                                                          |
//+------------------------------------------------------------------+
void TH3RecorderEnsureDirs(bool &dirsOk)
{
   dirsOk = true;
   if(FolderCreate(TH3_DATASET_SAMPLES) < 0) dirsOk = false;
   if(dirsOk && FolderCreate(TH3_DATASET_SHOTS) < 0) dirsOk = false;
   if(dirsOk && FolderCreate(TH3_DATASET_LOGS)  < 0) dirsOk = false;
   if(dirsOk && FolderCreate(TH3_DATASET_DIR) < 0) dirsOk = false;
}

//+------------------------------------------------------------------+
//| One joiner, so the tree prefix and the fallback are the SAME rule |
//| on both sides. Pure: string in, string out.                     |
//+------------------------------------------------------------------+
string TH3RecorderPath(const string dir, const string leaf, const bool dirsOk)
{
   return dirsOk ? (dir + "/" + leaf) : leaf;
}

//+------------------------------------------------------------------+
//| P-TH3-DB — A FOLDER NAME IS A FILENAME, SO IT IS SANITISED.     |
//| The symbol, the timeframe and the pattern name all end up on    |
//| disk, and the pattern name is a free string the renderer built.  |
//| Windows forbids \ / : * ? " < > | in a folder name, and a name  |
//| with a space in it is awkward in git; every other character      |
//| becomes '_' and the result is capped, so a pathological pattern |
//| name cannot produce a path longer than the terminal tolerates.   |
//| Pure: string in, string out, no chart, no files.                 |
//+------------------------------------------------------------------+
string TH3SafeName(const string raw, const int maxLen)
{
   string s = raw;
   for(int i = 0; i < StringLen(s); i++)
   {
      ushort c = StringGetCharacter(s, i);
      bool keep = ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
                   (c >= 'a' && c <= 'z') || c == '_' || c == '-');
      if(!keep) s = StringSetCharacter(s, i, '_');
   }
   if(maxLen > 0 && StringLen(s) > maxLen) s = StringSubstr(s, 0, maxLen);
   return s;
}

//+------------------------------------------------------------------+
//| P-TH3-DB — THE DASHBOARD AND THE DATABASE SORT LIKE FOLDERS.     |
//| "20261005-1743_EURUSD_M5_S015_ABCD_Pattern_7040265" sorts by     |
//| capture time, then symbol, then timeframe, then the counter, and |
//| every piece of that is a fact already in the sample — the date   |
//| and clock come from the capture stamp, not from a filesystem     |
//| mtime that a copy would rewrite. Pure.                           |
//+------------------------------------------------------------------+
string TH3SampleStamp(const datetime when)
{
   //--- NOT TimeToString(when, TIME_DATE): this build resolves that two-argument
   //--- form as a symbol, not the builtin (compile error 137), and a folder name
   //--- has to be locale-free anyway - a German or Persian terminal would spell
   //--- the same capture differently. So the stamp is formatted from the integer
   //--- parts, which is pure, exact, and identical on every machine.
   return StringFormat("%04d%02d%02d-%02d%02d",
                       TimeYear(when), TimeMonth(when), TimeDay(when),
                       TimeHour(when), TimeMinute(when));
}

//+------------------------------------------------------------------+
//| The same stamp split for the database: the day, and the clock.   |
//| The dashboard groups by these, so they must be plain text a     |
//| spreadsheet sorts - not "2026.10.05 17:43" in one field.        |
//+------------------------------------------------------------------+
string TH3SampleDate(const datetime when)
{
   return StringFormat("%04d.%02d.%02d", TimeYear(when), TimeMonth(when), TimeDay(when));
}

string TH3SampleClock(const datetime when)
{
   return StringFormat("%02d:%02d", TimeHour(when), TimeMinute(when));
}

string TH3SampleFolderName(const datetime when, const string sym, const string tf,
                           const int idx, const string pattern)
{
   string name = TH3SampleStamp(when) + "_" + TH3SafeName(sym, 12) + "_"
               + TH3SafeName(tf, 6) + "_" + StringFormat("S%03d", idx);
   string p = TH3SafeName(pattern, 20);
   if(p != "") name += "_" + p;
   return name;
}

//+------------------------------------------------------------------+
//| The sample's own folder, relative to MQL4\Files.                 |
//+------------------------------------------------------------------+
string TH3SampleFolder(const datetime when, const string sym, const string tf,
                       const int idx, const string pattern)
{
   return TH3_DATASET_SAMPLES + "/" + TH3SampleFolderName(when, sym, tf, idx, pattern);
}

//+------------------------------------------------------------------+
//| P-TH3-DB — A CSV FIELD CANNOT CARRY A COMMA. The pattern name is |
//| free text; MQL4's CSV writer does not quote it, so one pattern   |
//| containing ',' would silently shift every later column. Pure.    |
//+------------------------------------------------------------------+
string TH3CsvField(const string raw)
{
   string s = raw;                    // StringReplace takes its input by reference
   s = StringReplace(s, ",", " ");
   s = StringReplace(s, "\n", " ");
   s = StringReplace(s, "\r", " ");
   s = StringReplace(s, "\"", "'");
   return s;
}

//+------------------------------------------------------------------+
//| P-TH3-DB — THE DATABASE'S COLUMNS, ONCE.                         |
//| The global Dataset.csv and every per-sample sample.csv are       |
//| written from THIS list, so a reader can join the two without     |
//| guessing. Pure, and pinned by the harness: the column COUNT and  |
//| the first names are behaviour (a tool reads them by name), and a |
//| silent change would empty a dashboard instead of breaking it.    |
//|                                                                  |
//| Ordered so the file reads by eye: who and when, what was drawn,  |
//| what the formula answered, what the market did, where the files  |
//| are.                                                             |
//+------------------------------------------------------------------+
#define TH3_DATASET_COLS 34

void TH3DatasetHeader(string &cols[])
{
   ArrayResize(cols, TH3_DATASET_COLS);
   cols[0]  = "Sample_ID";
   cols[1]  = "Capture_Date";       // yyyy.MM.dd — the day the press happened
   cols[2]  = "Capture_Clock";      // HH:mm
   cols[3]  = "Capture_Stamp";      // yyyyMMdd-HHmm — the folder's own prefix
   cols[4]  = "Symbol";
   cols[5]  = "TF";
   cols[6]  = "Owner_TF";
   cols[7]  = "Pattern";
   cols[8]  = "Direction";          // down | up
   cols[9]  = "D_Time";
   cols[10] = "D_Price";
   cols[11] = "Digits";
   cols[12] = "Pip_Size";
   cols[13] = "Mother_Pips";
   cols[14] = "Leg_AB";
   cols[15] = "Leg_BC";
   cols[16] = "Leg_CD";
   cols[17] = "Ratio_BC_AB";
   cols[18] = "Ratio_CD_BC";
   cols[19] = "K";
   cols[20] = "Step_Mother";
   cols[21] = "Step_Pattern";
   cols[22] = "Step_Pips";
   cols[23] = "Target_1";
   cols[24] = "Target_3";
   cols[25] = "Target_5";
   cols[26] = "Target_7";
   cols[27] = "Actual_Turn";
   cols[28] = "Error_Pips";
   cols[29] = "Rungs_Hit";
   cols[30] = "Folder";
   cols[31] = "Log_File";
   cols[32] = "Screenshot";
   // P-TH3-DB: the TF rung (TH3PatternStepRungTF) is an INPUT of the formula —
   // it decides whether the mother is a macro span — and the dataset that exists
   // to tune the formula has to carry it, or a tuner can only guess. Appended
   // last so every column index already pinned and every tool that reads by
   // position stays exactly where it was.
   cols[33] = "Rung_Pips";
}

#endif // TH3_DATASET_PATHS_MQH