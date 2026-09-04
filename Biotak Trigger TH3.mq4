  //+------------------------------------------------------------------+
//|                                           Biotak Trigger TH3.mq4 |
//+------------------------------------------------------------------+
#property copyright "  Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link      "@biotak"
#property version   "3.11"
#property strict
#property indicator_chart_window
#property description "Version 3.10 - GOLD: Post-Audit - All Critical Issues Fixed"
#property description "Race conditions fixed | Memory leaks eliminated | Buffer overflow prevented"

//                                                                    
// BUILD CONFIG - Must be first include!
//                      BuildConfig.mqh               
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

//                                                                    
// Security & Performance Foundations (must precede GlobalVariables)
//                                                                    
#include "Biotak\FloatingPointHelper.mqh"
#include "Biotak\ObjectCountManager.mqh"
#include "Biotak\PerformanceOptimizations.mqh"
#include "Biotak\InputValidationEnhanced.mqh"

//                                                                    
// RUNTIME SETTINGS - single owner of panel-editable setting mirrors.
// MUST follow PropertiesAndInputs.mqh (input declarations) and precede
// GlobalVariables.mqh + all consumers (redirection #defines start here).
//                                                                    
#include "Biotak\RuntimeSettings.mqh"

#include "Biotak\GlobalVariables.mqh"

#include "Biotak\UtilityFunctions.mqh"

//                                                                    
// Cache & Object Management Systems
//                                                                    
#include "Biotak\CalculationCache.mqh"
#include "Biotak\ZoneFactory.mqh"
#include "Biotak\ZoneConfig.mqh"       // single owner of zone settings
#include "Biotak\ZoneConstants.mqh"

#include "Biotak\ObjectCache.mqh"
#include "Biotak\PropertyChangeDetector.mqh"
#include "Biotak\VisibilityManager.mqh"

//                                                                    
// Timeframe & Calculation Modules
//                                                                    
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

//                                                                    
// Drawing & Rendering Pipeline
//                                                                    
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

//                                                                    
// UI MODULES — Circular Menu, Settings Panels & HTF Candles          
// (BiotakKit must precede BiotakMenu; HTFCandles precede the kit)  
//                                                                    
#include "Biotak\HTFCandles.mqh"
#include "Biotak\BiotakKit.mqh"
#include "Biotak\BiotakMenu.mqh"
#include "Biotak\BiotakPanels.mqh"

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    int result = OnInitHandler();
    if(result == INIT_SUCCEEDED)
    {
        // --- Circular menu / settings panels / HTF candles ---
        InitializeUIStates();      // menu + UI globals
        InitializeBiotakKit();   // panel state, colors, boxes, custom lines
        InitializeHTFCandles();    // HTF candle engine
        CreateMenu();              // orb + ring + tools
        ChartRedraw();
    }
    return result;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // --- UI teardown (before the base handler clears chart objects) ---
    DeleteMenu();
    DeleteHTFCandles();
    SaveBiotakKit();
    CleanupUIStates(reason);
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
    int result = OnCalculateHandler(rates_total, prev_calculated, time, open, high, low, close, tick_volume, real_volume, spread);
    // --- UI kit: HTF forming-candle live update + new-bar redraw ---
    RefreshKitOnBar();
    return result;
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
  // --- Circular menu / settings panels / palette ---
  HandleUIChartEvent(id,lparam,dparam,sparam);
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

    // --- UI kit: HTF forming candle + new-bar redraw + chart-lock watchdog ---
    RefreshKitOnBar();
    ChartScrollReconcile();
}
