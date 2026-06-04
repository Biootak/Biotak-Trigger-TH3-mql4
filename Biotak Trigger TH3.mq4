//+------------------------------------------------------------------+
//|                                           Biotak Trigger TH3.mq4 |
//+------------------------------------------------------------------+
#property copyright "© Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link      "@biotak"
#property version   "3.10"
#property strict
#property indicator_chart_window
#property description "Version 3.10 - GOLD: Post-Audit - All Critical Issues Fixed"
#property description "Race conditions fixed | Memory leaks eliminated | Buffer overflow prevented"

// ═══════════════════════════════════════════════════════════════════
// BUILD CONFIG - Must be first include!
// برای تغییر مود، فایل BuildConfig.mqh را ویرایش کنید
// ═══════════════════════════════════════════════════════════════════
#include "Biotak\BuildConfig.mqh"

#include "Biotak\MathConstants.mqh"
#include "Biotak\Logger.mqh"
#include "Biotak\Profiler.mqh"

#include "Biotak\PropertiesAndInputs.mqh"
#include "Biotak\ConstantsAndEnums.mqh"
#include "Biotak\ProjectConstants.mqh"
#include "Biotak\InputValidator.mqh"

// ═══════════════════════════════════════════════════════════════════
// Security & Performance Foundations (must precede GlobalVariables)
// ═══════════════════════════════════════════════════════════════════
#include "Biotak\FloatingPointHelper.mqh"
#include "Biotak\ObjectCountManager.mqh"
#include "Biotak\PerformanceOptimizations.mqh"
#include "Biotak\InputValidationEnhanced.mqh"

#include "Biotak\GlobalVariables.mqh"

#include "Biotak\UtilityFunctions.mqh"

// ═══════════════════════════════════════════════════════════════════
// Cache & Object Management Systems
// ═══════════════════════════════════════════════════════════════════
#include "Biotak\CalculationCache.mqh"
#include "Biotak\ZoneFactory.mqh"
#include "Biotak\ZoneValidator.mqh"
#include "Biotak\ZoneConstants.mqh"

#include "Biotak\ObjectCache.mqh"
#include "Biotak\PropertyChangeDetector.mqh"
#include "Biotak\VisibilityManager.mqh"

// ═══════════════════════════════════════════════════════════════════
// Timeframe & Calculation Modules
// ═══════════════════════════════════════════════════════════════════
#include "Biotak\TimeframeFunctions.mqh"
#include "Biotak\FractalTimeframes.mqh"
#include "Biotak\StandardTimeframes.mqh"

#include "Biotak\THCalculations.mqh"
#include "Biotak\ATRCalculations.mqh"
#include "Biotak\AdaptiveScaling.mqh"
#include "Biotak\BasePriceManager.mqh"
#include "Biotak\WaveAnalysis.mqh"
#include "Biotak\FrequencyOptimizer.mqh"
#include "Biotak\TH3Tool.mqh"

// ═══════════════════════════════════════════════════════════════════
// Drawing & Rendering Pipeline
// ═══════════════════════════════════════════════════════════════════
#include "Biotak\ObjectFunctions.mqh"
#include "Biotak\ExtendedDrawingFunctions.mqh"
#include "Biotak\LevelPipeline.mqh"

#include "Biotak\LabelFunctions.mqh"
#include "Biotak\AlertFunctions.mqh"
#include "Biotak\HistoricalDataFunctions.mqh"
#include "Biotak\EventHandlers.mqh"

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    return OnInitHandler();
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    OnDeinitHandler(reason);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
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
    return OnCalculateHandler(rates_total, prev_calculated, time, open, high, low, close, tick_volume, real_volume, spread);
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
  OnChartEventHandler(id,lparam,dparam,sparam);
}

//+------------------------------------------------------------------+
//| Timer function - periodic housekeeping                           |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Periodic housekeeping runs here (kept lightweight by internal throttles)
    RunIncrementalObjectCleanup();
    // Keep label expiry logic; no timer kill because cleanup also depends on timer cadence
    CheckAndClearExpiredLabels();
}