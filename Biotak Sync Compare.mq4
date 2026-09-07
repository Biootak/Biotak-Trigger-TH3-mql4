//+------------------------------------------------------------------+
//| Biotak Sync Compare.mq4                                        |
//| Sync verification tool. Renders EXACTLY like the production      |
//| Biotak Trigger TH3 (same include chain, same handlers) and also |
//| writes two CSV files on every new bar:                          |
//|   Files\biotak_sync_values.csv   - core computed values         |
//|   Files\biotak_sync_objects.csv  - drawn objects (positions,    |
//|                                     colors, styles, TFs, text)   |
//|                                                                  |
//| PROCEDURE:                                                       |
//| 1. Attach ONLY this indicator (instead of the real one) on the  |
//|    same symbol/timeframe with IDENTICAL settings in MT4 and MT5 |
//| 2. Let it run for a few bars/minutes                            |
//| 3. Send both CSV files for diffing                              |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property description "Sync compare: identical settings on MT4 and MT5, then diff the CSVs"

//                                                                    
// BUILD CONFIG - Must be first include!                              
//                                                                    
#include "Biotak\BuildConfig.mqh"

#include "Biotak\MathConstants.mqh"
#include "Biotak\Logger.mqh"

#ifndef BUILD_LITE
#include "Biotak\Profiler.mqh"
#endif

#include "Biotak\PropertiesAndInputs.mqh"
#include "Biotak\ConstantsAndEnums.mqh"
#include "Biotak\ProjectConstants.mqh"
#include "Biotak\InputValidator.mqh"

#include "Biotak\FloatingPointHelper.mqh"
#include "Biotak\ObjectCountManager.mqh"
#include "Biotak\PerformanceOptimizations.mqh"
#include "Biotak\InputValidationEnhanced.mqh"

#include "Biotak\GlobalVariables.mqh"

#include "Biotak\UtilityFunctions.mqh"

#include "Biotak\CalculationCache.mqh"
#include "Biotak\ZoneFactory.mqh"
#include "Biotak\ZoneValidator.mqh"
#include "Biotak\ZoneConstants.mqh"

#include "Biotak\ObjectCache.mqh"
#include "Biotak\PropertyChangeDetector.mqh"
#include "Biotak\VisibilityManager.mqh"

#include "Biotak\TimeframeFunctions.mqh"
#include "Biotak\FractalTimeframes.mqh"
#include "Biotak\StandardTimeframes.mqh"

#include "Biotak\THCalculations.mqh"
#include "Biotak\ATRCalculations.mqh"
#include "Biotak\AdaptiveScaling.mqh"
#include "Biotak\BasePriceManager.mqh"

#ifndef BUILD_LITE
#include "Biotak\WaveAnalysis.mqh"
#include "Biotak\FrequencyOptimizer.mqh"
// TH3TOOL-OFF (tool retired — commented out, not deleted):
// #include "Biotak\TH3Tool.mqh"
#endif

#include "Biotak\ObjectFunctions.mqh"
#include "Biotak\ExtendedDrawingFunctions.mqh"
#include "Biotak\ComboEngine.mqh"
#include "Biotak\FactorMode.mqh"
#include "Biotak\LevelPipeline.mqh"
#include "Biotak\ModeDefinitions.mqh"

#include "Biotak\LabelFunctions.mqh"
#include "Biotak\AlertFunctions.mqh"
#include "Biotak\HistoricalDataFunctions.mqh"
#include "Biotak\EventHandlers.mqh"

//+------------------------------------------------------------------+
//| Sync compare dump                                                |
//+------------------------------------------------------------------+
datetime g_syncLastDumpedBar = 0;
int      g_syncValuesFile    = INVALID_HANDLE;
int      g_syncObjectsFile   = INVALID_HANDLE;

#define SYNC_VALUES_FILE  "biotak_sync_values.csv"
#define SYNC_OBJECTS_FILE "biotak_sync_objects.csv"
#define SYNC_MAX_OBJECTS  2000

string SyncDumpStr(const double v)
{
    return DoubleToString(v, 10);
}

void SyncOpenFiles()
{
    if(g_syncValuesFile == INVALID_HANDLE)
        g_syncValuesFile = FileOpen(SYNC_VALUES_FILE, FILE_WRITE|FILE_READ|FILE_CSV, ',');
    if(g_syncObjectsFile == INVALID_HANDLE)
        g_syncObjectsFile = FileOpen(SYNC_OBJECTS_FILE, FILE_WRITE|FILE_READ|FILE_CSV, ',');
}

void SyncWriteHeader(const int fh)
{
    if(fh == INVALID_HANDLE) return;
    if(FileSize(fh) > 0) return;
    if(fh == g_syncValuesFile)
        FileWrite(fh, "barTime","barOpen","barHigh","barLow","barClose",
                  "basePrice","thPct","thStep","adaptedStep","atrStep","comboStep",
                  "structVal","patternVal","triggerVal",
                  "atrStruct","atrPattern","atrTrigger","calcMs");
    else
        FileWrite(fh, "barTime","name","type","price1","price2","time1","time2",
                  "color","style","width","timeframes","back","fill","ray","zorder","text");
}

void SyncDumpValues()
{
    SyncOpenFiles();
    if(g_syncValuesFile == INVALID_HANDLE) return;
    SyncWriteHeader(g_syncValuesFile);
    FileSeek(g_syncValuesFile, 0, SEEK_END);

    uint t0 = GetTickCount();

    double basePrice   = GetBasePriceForTH();
    double thPct       = GetTimeframeTH();
    double thStep      = CalculateTH(basePrice, Digits, thPct);
    double adaptedStep = GetAdaptedStepSize(thStep);
    double atrStep     = CalculateATRBasedStep();
    double comboStep   = GetComboStepSize(basePrice);

    double structVal = 0.0, patternVal = 0.0, triggerVal = 0.0;
    CalculateFractalValues(adaptedStep, structVal, patternVal, triggerVal);

    double atrStruct = 0.0, atrPattern = 0.0, atrTrigger = 0.0;
    CalculateATRFractalValues(atrStruct, atrPattern, atrTrigger);

    uint t1 = GetTickCount();

    FileWrite(g_syncValuesFile,
              TimeToString(Time[0], TIME_DATE|TIME_MINUTES|TIME_SECONDS),
              SyncDumpStr(Open[0]), SyncDumpStr(High[0]), SyncDumpStr(Low[0]), SyncDumpStr(Close[0]),
              SyncDumpStr(basePrice), SyncDumpStr(thPct), SyncDumpStr(thStep), SyncDumpStr(adaptedStep),
              SyncDumpStr(atrStep), SyncDumpStr(comboStep),
              SyncDumpStr(structVal), SyncDumpStr(patternVal), SyncDumpStr(triggerVal),
              SyncDumpStr(atrStruct), SyncDumpStr(atrPattern), SyncDumpStr(atrTrigger),
              IntegerToString((int)(t1 - t0)));
}

void SyncDumpObjects()
{
    SyncOpenFiles();
    if(g_syncObjectsFile == INVALID_HANDLE) return;
    SyncWriteHeader(g_syncObjectsFile);
    FileSeek(g_syncObjectsFile, 0, SEEK_END);

    string barTag = TimeToString(Time[0], TIME_DATE|TIME_MINUTES|TIME_SECONDS);
    int total = ObjectsTotal();
    int dumped = 0;
    for(int i = 0; i < total && dumped < SYNC_MAX_OBJECTS; i++)
    {
        string name = ObjectName(i);
        if(StringFind(name, inpObjectPrefix) != 0) continue;

        long type = ObjectGetInteger(0, name, OBJPROP_TYPE);
        double p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
        double p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
        long   t1 = ObjectGetInteger(0, name, OBJPROP_TIME, 0);
        long   t2 = ObjectGetInteger(0, name, OBJPROP_TIME, 1);

        FileWrite(g_syncObjectsFile,
                  barTag,
                  name,
                  IntegerToString((int)type),
                  SyncDumpStr(p1), SyncDumpStr(p2),
                  TimeToString((datetime)t1, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                  TimeToString((datetime)t2, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_COLOR)),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_STYLE)),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_WIDTH)),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_TIMEFRAMES)),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_BACK)),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_FILL)),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT)),
                  IntegerToString((int)ObjectGetInteger(0, name, OBJPROP_ZORDER)),
                  ObjectGetString(0, name, OBJPROP_TEXT));
        dumped++;
    }
}

void SyncCompareTick()
{
    if(Bars <= 0) return;
    if(Time[0] == g_syncLastDumpedBar) return;
    g_syncLastDumpedBar = Time[0];
    SyncDumpValues();
    SyncDumpObjects();
}

//+------------------------------------------------------------------+
//| Handlers - mirror the production indicator exactly               |
//+------------------------------------------------------------------+
int OnInit()
{
    return OnInitHandler();
}

void OnDeinit(const int reason)
{
    OnDeinitHandler(reason);
    if(g_syncValuesFile != INVALID_HANDLE) { FileClose(g_syncValuesFile); g_syncValuesFile = INVALID_HANDLE; }
    if(g_syncObjectsFile != INVALID_HANDLE) { FileClose(g_syncObjectsFile); g_syncObjectsFile = INVALID_HANDLE; }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &real_volume[],
                const int &spread[])
{
    int res = OnCalculateHandler(rates_total, prev_calculated, time, open, high, low, close, tick_volume, real_volume, spread);
    SyncCompareTick();
    return res;
}

//+------------------------------------------------------------------+
//| Timer function - periodic housekeeping                           |
//+------------------------------------------------------------------+
void OnTimer()
{
    // FIX: If indicator is not yet fully initialized (e.g. waiting for history),
    // retry drawing periodically even without new ticks.
    if(!g_initialized) {
        RedrawAllObjects(false);
    }

    // Periodic housekeeping runs here (kept lightweight by internal throttles)
    RunIncrementalObjectCleanup();
    // Keep label expiry logic; no timer kill because cleanup also depends on timer cadence
    CheckAndClearExpiredLabels();
    // Real-time refresh of visible info labels (text updated in place only when changed)
    RefreshComboLabelExtraInfo();
    RefreshVisibleStatusLabels();

    SyncCompareTick();
}
