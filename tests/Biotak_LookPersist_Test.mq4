//+------------------------------------------------------------------+
//| Biotak_LookPersist_Test.mq4                                      |
//| P-DRAW-09c + P-DRAW-132 (2026-10-18) — the memory half, live.      |
//|                                                                  |
//| «همیشه آخرین تغییرات روی ابجکت پیش‌فرض بشه و هر سری نیاز نباشه تنظیم  |
//| بکن» — the kind memory made the last look the default of the NEXT   |
//| drawing; P-DRAW-09c made it survive an ATTACH; P-DRAW-132 replaced  |
//| the fixed six-slot rack with a NAMED one («مثل تردینگ ویو سیو کنم»)  |
//| and moved the store to ONE file. This script measures the parts a   |
//| green compile cannot:                                               |
//|                                                                  |
//|   1. THE ROUND TRIP — a look packed, wiped and unpacked comes back  |
//|      slot for slot (the pack and the unpack are one bit-layout      |
//|      contract in two functions);                                    |
//|   2. clrNONE IS NOT A COLOUR — a slot the user never coloured must  |
//|      come back "no colour of its own", never a colour nobody chose; |
//|   3. THE NAMED RACK — put APPENDS a new name and REPLACES the same  |
//|      one case-insensitively, a FULL rack REFUSES and eats nothing,  |
//|      a delete COMPACTS the list;                                    |
//|   4. THE FILE HALF — through the REAL writer (DrawTplSave), the     |
//|      wipe, and the REAL reader (DrawTplLoad), names included;       |
//|   5. THE ONE-TIME MIGRATION — a hand-built P-DRAW-02 file comes     |
//|      back as named templates plus the 255/254 reserved rows;        |
//|   6. THE BOOT — with a file on disk the FILE is the truth (no        |
//|      re-seed); a legacy first run seeds, migrates, writes and        |
//|      retires the old file; a bare first run seeds.                  |
//|                                                                  |
//| HOW TO RUN: drag onto any chart, open the "Experts" tab, look for  |
//| [LOOKTEST] lines and the DONE line (0 failed is the pass).          |
//|                                                                  |
//| THE USER'S OWN FILES ARE THEIR DATA (P-DRAW-05): DrawTemplates.csv  |
//| and DrawPresets.csv are read whole, byte for byte, before the test  |
//| and written back byte for byte after it — as they were found.       |
//+------------------------------------------------------------------+
#property strict
#property description "P-DRAW-132/09c: the named rack and the last look survive an attach"

// Same include chain as the entry and the shot harness (P-BUILD-02): the test runs
// the real code, in the entry's own ORDER.
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

#include "..\Biotak\WaveAnalysis.mqh"

#include "..\Biotak\FrequencyOptimizer.mqh"

#include "..\Biotak\TH3Tool.mqh"

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


int g_lookOk = 0, g_lookFail = 0;

void LookChk(const string what, const bool ok)
{
   if(ok) { g_lookOk++; Print("[LOOKTEST] ok   ", what); return; }
   g_lookFail++;
   Print("[LOOKTEST] FAIL ", what);
}

//--- ONE known look: every field the memory carries, none of them a default, so a
//--- field that is not restored cannot pass by luck.
DrawLook LookKnown()
{
   DrawLook L;
   L.clr     = (color)0x123456;
   L.width   = 3;
   L.style   = 2;
   L.fill    = true;
   L.ray     = 3;
   L.font    = 17;
   L.glyph   = 233;
   L.back    = true;
   L.fillClr = (color)0x654321;
   return L;
}
bool LookIsSame(const DrawLook &A, const DrawLook &B)
{
   return ((int)A.clr == (int)B.clr && (int)A.fillClr == (int)B.fillClr &&
           A.width == B.width && A.style == B.style && A.fill == B.fill &&
           A.ray == B.ray && A.font == B.font && A.glyph == B.glyph && A.back == B.back);
}

//--- the test's own tools: a rack wipe (boot's clear, without its file rules) and
//--- a byte-exact backup pair, so the user's files leave as they arrived.
void RackClear()
{
   for(int k = 0; k < DK_COUNT; k++)
      for(int i = 0; i < DRAW_TPL_MAX; i++)
      {
         s_dkTpl[k][i].used  = false;
         s_dkTpl[k][i].name  = "";
         s_dkTpl[k][i].packA = 0.0;
         s_dkTpl[k][i].packB = 0.0;
      }
}
bool FileBackup(const string path, uchar &buf[], int &n)
{
   n = 0;
   ArrayResize(buf, 0);
   int h = FileOpen(path, FILE_READ | FILE_BIN);
   if(h == INVALID_HANDLE) return false;
   n = (int)FileSize(h);
   if(n > 0)
   {
      ArrayResize(buf, n);
      if(FileReadArray(h, buf, 0, n) != n) n = 0;
   }
   FileClose(h);
   return true;
}
bool FileRestore(const string path, const uchar &buf[], const int n, const bool had)
{
   FileDelete(path);
   if(!had) return true;
   int h = FileOpen(path, FILE_WRITE | FILE_BIN);
   if(h == INVALID_HANDLE) return false;
   if(n > 0) FileWriteArray(h, buf, 0, n);
   FileClose(h);
   return true;
}

//--- P-DRAW-02's file, hand-built the way the OLD build wrote it: a user slot
//--- `kind;3;name;packed33`, the last look with its columns swapped (B in `name`,
//--- A in `packed`) and the shared ink as a number in `name`.
void WriteLegacy(const DrawLook &K)
{
   int h = FileOpen(DRAW_TPL_LEGACY, FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) { Print("[LOOKTEST] WARNING: legacy fixture could not be written"); return; }
   FileWrite(h, (int)DK_TRIANGLE, 3, "Old Wave", DoubleToString(DrawLookPackA(K), 0));
   FileWrite(h, (int)DK_TEXT, DRAW_LASTLOOK_SLOT, DoubleToString(DrawLookPackB(K), 0),
             DoubleToString(DrawLookPackA(K), 0));
   FileWrite(h, 1, DRAW_LASTINK_SLOT, IntegerToString(0x0A0B0C), "0");
   FileClose(h);
}

void OnStart()
{
   Print("[LOOKTEST] P-DRAW-132/P-DRAW-09c - the named rack and the last look across an attach (file: ",
         DrawTplPath(), ")  rack 0..", IntegerToString(DRAW_TPL_MAX - 1),
         "  lastlook=", IntegerToString(DRAW_LASTLOOK_SLOT),
         "  lastink=", IntegerToString(DRAW_LASTINK_SLOT));

   //--- the user's files, read whole and put back byte for byte at the end.
   uchar bkTpl[], bkPre[]; int nTpl = 0, nPre = 0;
   bool hadTpl = FileBackup(DRAW_TPL_FILE, bkTpl, nTpl);
   bool hadPre = FileBackup(DRAW_TPL_LEGACY, bkPre, nPre);
   Print("[LOOKTEST] the files before the test: new=", hadTpl ? (IntegerToString(nTpl) + " byte(s), kept") : "absent",
         "  legacy=", hadPre ? (IntegerToString(nPre) + " byte(s), kept") : "absent");

   DrawStyleInit();
   s_dkAnyClr = clrNONE;
   RackClear();

   DrawLook K = LookKnown();

   //--- 1. THE ROUND TRIP, with no file in the way.
   double pa = DrawLookPackA(K), pb = DrawLookPackB(K);
   DrawLook R; DrawLookUnpackA(pa, R); DrawLookUnpackB(pb, R);
   LookChk("DrawLook pack/unpack round trip, every field (A=" + DoubleToString(pa, 0) +
           " B=" + DoubleToString(pb, 0) + ")", LookIsSame(K, R));

   //--- 2. clrNONE is "no colour of its own", never a colour nobody chose.
   DrawLook N = K; N.clr = clrNONE; N.fillClr = clrNONE;
   DrawLookUnpackA(DrawLookPackA(N), R); DrawLookUnpackB(DrawLookPackB(N), R);
   LookChk("clrNONE comes back as no colour of its own (border=" + IntegerToString((int)R.clr) +
           ", interior=" + IntegerToString((int)R.fillClr) + ")",
           ((int)R.clr < 0 && (int)R.fillClr < 0 && (int)R.clr != 0xFFFFFF && (int)R.fillClr != 0xFFFFFF));

   //--- 3. THE NAMED RACK.
   RackClear();
   DrawLook L2 = K; L2.width = 5; L2.style = 0;
   LookChk("a new name APPENDS (Put=1)",
           (DrawTplPut(DK_RECT, "Supply", K) == 1 && DrawTplCount(DK_RECT) == 1));
   LookChk("the same name REPLACES, case-insensitively (Put=2, count stays 1)",
           (DrawTplPut(DK_RECT, "sUpPlY", L2) == 2 && DrawTplCount(DK_RECT) == 1 &&
            DrawTplIndex(DK_RECT, "SUPPLY") == 0));
   DrawLook R2; DrawLookUnpackA(s_dkTpl[DK_RECT][0].packA, R2); DrawLookUnpackB(s_dkTpl[DK_RECT][0].packB, R2);
   LookChk("the replaced row carries the NEW look (width=" + IntegerToString(R2.width) +
           " style=" + IntegerToString(R2.style) + ")", (R2.width == 5 && R2.style == 0));

   for(int j = 1; j < DRAW_TPL_MAX; j++)
      DrawTplPut(DK_RECT, "T" + IntegerToString(j), K);
   int resFull = DrawTplPut(DK_RECT, "Overflow", K);
   LookChk("a full rack REFUSES the next row (0), the oldest survives",
           (resFull == 0 && DrawTplCount(DK_RECT) == DRAW_TPL_MAX &&
            DrawTplName(DK_RECT, 0) == "Supply" && DrawTplIndex(DK_RECT, "Overflow") < 0));

   string second = DrawTplName(DK_RECT, 1);
   string third = DrawTplName(DK_RECT, 2);
   bool delOk = DrawTplDelete(DK_RECT, 1);
   LookChk("a delete COMPACTS the list (row 1 was \"" + second + "\", now \"" + DrawTplName(DK_RECT, 1) + "\")",
           (delOk && DrawTplCount(DK_RECT) == DRAW_TPL_MAX - 1 && DrawTplName(DK_RECT, 1) == third &&
            DrawTplName(DK_RECT, DRAW_TPL_MAX - 1) == ""));

   //--- 4. THE FILE HALF: the real writer, the wipe, the real reader.
   DrawStyleInit();
   s_dkAnyClr = clrNONE;
   RackClear();
   s_dkValid[DK_TEXT] = true;
   s_dkColor[DK_TEXT] = (color)0x123456; s_dkFillClr[DK_TEXT] = (color)0x654321;
   s_dkWidth[DK_TEXT] = 3; s_dkStyle[DK_TEXT] = 2; s_dkFill[DK_TEXT] = true; s_dkRay[DK_TEXT] = 3;
   s_dkFont[DK_TEXT] = 17; s_dkGlyph[DK_TEXT] = 233; s_dkBack[DK_TEXT] = true;
   s_dkAnyClr = (color)0x0A0B0C;
   DrawTplPut(DK_TEXT, "Note A", K);
   DrawTplSave();
   DrawStyleInit();
   s_dkAnyClr = clrNONE;
   RackClear();
   LookChk("a fresh attach starts with no look of its own and an empty rack",
           (!s_dkValid[DK_TEXT] && !s_dkValid[DK_RECT] &&
            DrawTplCount(DK_TEXT) == 0 && DrawTplCount(DK_RECT) == 0 && (int)s_dkAnyClr < 0));
   DrawTplLoad();
   LookChk("the saved look came back from the file (border=" + IntegerToString((int)s_dkColor[DK_TEXT]) +
           " interior=" + IntegerToString((int)s_dkFillClr[DK_TEXT]) + ")",
           (s_dkValid[DK_TEXT] && (int)s_dkColor[DK_TEXT] == 0x123456 &&
            (int)s_dkFillClr[DK_TEXT] == 0x654321 && s_dkWidth[DK_TEXT] == 3 &&
            s_dkStyle[DK_TEXT] == 2 && s_dkFill[DK_TEXT] && s_dkRay[DK_TEXT] == 3 &&
            s_dkFont[DK_TEXT] == 17 && s_dkGlyph[DK_TEXT] == 233 && s_dkBack[DK_TEXT]));
   LookChk("the named row came back with its name, case-insensitively findable",
           (DrawTplName(DK_TEXT, 0) == "Note A" && DrawTplIndex(DK_TEXT, "note a") == 0 &&
            DrawTplCount(DK_RECT) == 0));
   LookChk("the shared ink came back (" + IntegerToString((int)s_dkAnyClr) + ")",
           ((int)s_dkAnyClr == 0x0A0B0C));
   LookChk("a kind nobody styled stayed untouched", !s_dkValid[DK_TRIANGLE]);
   LookChk("the reserved slots sit outside every template band",
           (DRAW_LASTLOOK_SLOT >= DRAW_TPL_MAX && DRAW_LASTINK_SLOT >= DRAW_TPL_MAX &&
            DRAW_LASTLOOK_SLOT != DRAW_LASTINK_SLOT));

   //--- 5. THE ONE-TIME MIGRATION, unit first.
   DrawStyleInit();
   s_dkAnyClr = clrNONE;
   RackClear();
   WriteLegacy(K);
   DrawTplMigrate();
   DrawLook RM; DrawLookUnpackA(s_dkTpl[DK_TRIANGLE][0].packA, RM); DrawLookUnpackB(s_dkTpl[DK_TRIANGLE][0].packB, RM);
   LookChk("the legacy user row migrated whole, wearing its old name and look",
           (DrawTplCount(DK_TRIANGLE) == 1 && DrawTplName(DK_TRIANGLE, 0) == "Old Wave" &&
            (int)RM.clr == 0x123456 && RM.width == 3 && RM.style == 2 && RM.fill && RM.ray == 3));
   LookChk("the legacy 255 row unpacked into the kind's memory",
           (s_dkValid[DK_TEXT] && (int)s_dkColor[DK_TEXT] == 0x123456 &&
            (int)s_dkFillClr[DK_TEXT] == 0x654321));
   LookChk("the legacy 254 row set the shared ink", ((int)s_dkAnyClr == 0x0A0B0C));

   //--- 6. THE BOOT. (a) with a file on disk the FILE is the truth.
   RackClear();
   DrawTplPut(DK_RECT, "FromFile", K);
   DrawTplSave();
   RackClear();
   DrawTplPut(DK_RECT, "InRam", K);
   DrawTplBoot();
   LookChk("boot made the FILE the truth (RAM row replaced by the file's \"" + DrawTplName(DK_RECT, 0) + "\")",
           (DrawTplCount(DK_RECT) == 1 && DrawTplName(DK_RECT, 0) == "FromFile"));

   //--- (b) the REAL upgrade: no new file, the legacy one present -> seed + migrate
   //--- + write + retire, in ONE boot.
   DrawStyleInit();
   s_dkAnyClr = clrNONE;
   RackClear();
   FileDelete(DRAW_TPL_FILE);
   FileDelete(DRAW_TPL_LEGACY);
   WriteLegacy(K);
   DrawTplBoot();
   LookChk("a legacy first run seeds, migrates, writes and retires (TRIANGLE=" +
           IntegerToString(DrawTplCount(DK_TRIANGLE)) + " LINE=" + IntegerToString(DrawTplCount(DK_LINE)) + ")",
           (DrawTplCount(DK_TRIANGLE) == 3 && DrawTplIndex(DK_TRIANGLE, "Old Wave") == 2 &&
            DrawTplCount(DK_LINE) >= 2 &&
            s_dkValid[DK_TEXT] && (int)s_dkColor[DK_TEXT] == 0x123456 &&
            FileIsExist(DRAW_TPL_FILE) && !FileIsExist(DRAW_TPL_LEGACY)));

   //--- (c) a bare first run: seed only.
   DrawStyleInit();
   s_dkAnyClr = clrNONE;
   RackClear();
   FileDelete(DRAW_TPL_FILE);
   FileDelete(DRAW_TPL_LEGACY);
   DrawTplBoot();
   LookChk("a first run with no file at all seeds the named rack and writes it (RECT=" +
           IntegerToString(DrawTplCount(DK_RECT)) + " LINE=" + IntegerToString(DrawTplCount(DK_LINE)) + ")",
           (DrawTplCount(DK_RECT) >= 1 && DrawTplCount(DK_LINE) >= 2 && FileIsExist(DRAW_TPL_FILE)));

   //--- the user's own files back, byte for byte (or gone, if they were not there).
   if(!FileRestore(DRAW_TPL_FILE, bkTpl, nTpl, hadTpl))
      Print("[LOOKTEST] WARNING: DrawTemplates.csv could not be restored");
   if(!FileRestore(DRAW_TPL_LEGACY, bkPre, nPre, hadPre))
      Print("[LOOKTEST] WARNING: DrawPresets.csv could not be restored");
   Print("[LOOKTEST] DONE: ", g_lookOk, " ok, ", g_lookFail, " failed");
}

void OnDeinit(const int reason) { }
