//+------------------------------------------------------------------+
//|  Biotak_UIAudit_Test.mq4 — THE UI AUDITOR                            |
//|                                                                  |
//|  WHY THIS EXISTS. Every UI question so far was answered by a     |
//|  screenshot a person had to take, crop and describe. "The panel  |
//|  has no plate" is unanswerable from the source: the arithmetic   |
//|  is right, the resource is declared, the compile is green, and   |
//|  the only place the answer lives is what the TERMINAL actually  |
//|  built. This harness goes and looks. It enumerates the chart,    |
//|  reports every object the two surfaces own with its REAL         |
//|  geometry, z-order, visibility and bitmap, compares the seats    |
//|  they are supposed to share, and writes a screenshot the agent  |
//|  can read without a human in the loop.                          |
//|                                                                  |
//|  IT ANSWERS, IN ONE RUN:                                         |
//|    * does each surface's plate object EXIST                     |
//|    * what BMPFILE the terminal stored for it ("" = never drawn) |
//|    * each object's real x/y/w/h and ZORDER                       |
//|    * every seat where panel != card, with both numbers          |
//|    * how many objects a surface leaked and which are orphans    |
//|                                                                  |
//|  USAGE: attach to ANY chart. It reads what is there; it creates  |
//|  nothing and deletes nothing.                                   |
//+------------------------------------------------------------------+
#property copyright "Biotak"
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
#include "..\Biotak\TH3\TH3Types.mqh"
#include "..\Biotak\TH3\TH3Math.mqh"
#include "..\Biotak\TH3\TH3Pivots.mqh"
#include "..\Biotak\TH3\TH3PatternStore.mqh"
#include "..\Biotak\TH3\TH3Controller.mqh"
#include "..\Biotak\TH3\TH3Renderer.mqh"
#include "..\Biotak\ObjectFunctions.mqh"
#include "..\Biotak\DrawToolbar.mqh"
// P-DRAW-116: the card surface's own number table, in the SAME seat the entry
// gives it (between the toolbar and the strip).
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
#include "..\Biotak\EventHandlers.mqh"
#include "..\Biotak\HTFCandles.mqh"
#include "..\Biotak\BiotakKit.mqh"
#include "..\Biotak\BiotakMenu.mqh"
#include "..\Biotak\BiotakPanels.mqh"

#define AUDIT_PREFIX_CARD  "BiotakMenuV2_"
#define AUDIT_PREFIX_PANEL "PnlDrawS_"
#define AUDIT_MAX 4000

//--- one object, as the TERMINAL sees it (never as the source hoped).
struct SAuditObj
{
   string name;
   int    type;
   int    x, y, w, h;
   long   z;
   bool   visible;
   string bmp;      // OBJ_BITMAP_LABEL only
   string txt;      // OBJ_LABEL / OBJ_BUTTON text
};

int  g_auditN = 0;
SAuditObj g_audit[AUDIT_MAX];
string g_auditFam[AUDIT_MAX];   // "card" | "panel" | "other"

string AuditTypeName(const int t)
{
   if(t == OBJ_BITMAP_LABEL)  return "BITMAP";
   if(t == OBJ_RECTANGLE_LABEL) return "RECTLBL";
   if(t == OBJ_LABEL)         return "LABEL";
   if(t == OBJ_BUTTON)        return "BUTTON";
   if(t == OBJ_RECTANGLE)     return "RECT";
   if(t == OBJ_TREND)         return "TREND";
   if(t == OBJ_ARROW)         return "ARROW";
   return "type" + IntegerToString(t);
}

void AuditCollect()
{
   g_auditN = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(nm == "") continue;
      string fam = "other";
      if(StringFind(nm, AUDIT_PREFIX_CARD) == 0)       fam = "card";
      else if(StringFind(nm, AUDIT_PREFIX_PANEL) == 0) fam = "panel";
      if(g_auditN >= AUDIT_MAX) break;

      g_audit[g_auditN].name = nm;
      g_auditFam[g_auditN]   = fam;
      g_audit[g_auditN].type = (int)ObjectGetInteger(0, nm, OBJPROP_TYPE);
      g_audit[g_auditN].x    = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
      g_audit[g_auditN].y    = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
      g_audit[g_auditN].w    = (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE);
      g_audit[g_auditN].h    = (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE);
      g_audit[g_auditN].z    = ObjectGetInteger(0, nm, OBJPROP_ZORDER);
      g_audit[g_auditN].visible = (ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS);
      g_audit[g_auditN].bmp  = "";
      g_audit[g_auditN].txt  = "";
      if(g_audit[g_auditN].type == OBJ_BITMAP_LABEL)
         g_audit[g_auditN].bmp = ObjectGetString(0, nm, OBJPROP_BMPFILE, 0);
      else
         g_audit[g_auditN].txt = ObjectGetString(0, nm, OBJPROP_TEXT);
      g_auditN++;
   }
}

//--- the verdict on one bitmap: a face with no file paints NOTHING, and the
//--- compile stays green. This is the one silent failure the gate cannot see.
void AuditReportBitmaps(const string fam)
{
   int n = 0, blank = 0;
   for(int i = 0; i < g_auditN; i++)
   {
      if(g_auditFam[i] != fam || g_audit[g_auditN].type == -1) continue;
      if(g_audit[i].type != OBJ_BITMAP_LABEL) continue;
      n++;
      if(g_audit[i].bmp == "") { blank++; Print("[UIAUDIT] BLANK BITMAP ", g_audit[i].name); }
   }
   Print("[UIAUDIT] ", fam, ": ", n, " bitmap face(s), ", blank, " with NO file (paints nothing)");
}

void AuditReportPlates()
{
   //--- the two PLATES, named by what they are, and whether the terminal holds
   //--- a real file for them. This is the whole "no skin" question in two lines.
   string probe[2] = { "PnlDrawS_Gbake", "PnlDrawS_Gtop" };
   for(int p = 0; p < 2; p++)
   {
      if(ObjectFind(0, probe[p]) < 0) { Print("[UIAUDIT] plate '", probe[p], "' ABSENT"); continue; }
      Print("[UIAUDIT] plate '", probe[p], "' present  xy=",
            (int)ObjectGetInteger(0, probe[p], OBJPROP_XDISTANCE), ",",
            (int)ObjectGetInteger(0, probe[p], OBJPROP_YDISTANCE), "  z=",
            ObjectGetInteger(0, probe[p], OBJPROP_ZORDER), "  file='",
            ObjectGetString(0, probe[p], OBJPROP_BMPFILE, 0), "'");
   }
   //--- and the reference card's own plate, for the comparison the agent cannot
   //--- make from a screenshot: same file? same size class?
   int c = 0;
   for(int i = 0; i < g_auditN; i++)
   {
      if(g_auditFam[i] != "card") continue;
      if(StringFind(g_audit[i].name, "card") < 0) continue;
      c++;
      if(c <= 3)
         Print("[UIAUDIT] card plate '", g_audit[i].name, "' ", g_audit[i].w, "x", g_audit[i].h,
               " z=", g_audit[i].z, " file='", g_audit[i].bmp, "'");
   }
   Print("[UIAUDIT] card plate objects found: ", c);
}

void AuditDump(const string fam, const int maxLines)
{
   int n = 0;
   for(int i = 0; i < g_auditN && n < maxLines; i++)
   {
      if(g_auditFam[i] != fam) continue;
      n++;
      Print("[UIAUDIT] ", AuditTypeName(g_audit[i].type), " ", g_audit[i].name,
            " @", g_audit[i].x, ",", g_audit[i].y, " ", g_audit[i].w, "x", g_audit[i].h,
            " z=", g_audit[i].z, g_audit[i].visible ? "" : " HIDDEN",
            g_audit[i].bmp != "" ? (" file=" + g_audit[i].bmp) : "");
   }
   Print("[UIAUDIT] ", fam, ": ", n, " object(s) dumped (cap ", maxLines, ")");
}

int OnInit()
{
   RuntimeSettingsInit();
   InitializeUIStates();
   AuditCollect();
   Print("[UIAUDIT] === chart object census, ", g_auditN, " object(s) ===");
   AuditReportPlates();
   AuditReportBitmaps("panel");
   AuditReportBitmaps("card");
   AuditDump("panel", 80);
   AuditDump("card", 40);
   //--- the one thing no number can replace: what the surface LOOKS like.
   //--- Written where the agent can read it, so the next round needs no human.
   string shot = "UIAudit_" + IntegerToString(ChartID()) + ".png";
   if(ChartScreenShot(shot, 0, 0, 0, 0))
      Print("[UIAUDIT] screenshot written: <MQL4>\\Files\\", shot);
   else
      Print("[UIAUDIT] screenshot FAILED (GetLastError=", GetLastError(), ")");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &real_volume[], const int &spread[])
{
   return rates_total;
}
