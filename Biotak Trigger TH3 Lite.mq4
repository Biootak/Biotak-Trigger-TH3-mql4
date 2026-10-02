  //+------------------------------------------------------------------+
//|                                      Biotak Trigger TH3 Lite.mq4 |
//+------------------------------------------------------------------+
#property copyright "  Formula by Professor Saeed Khakestar, Indicator by Biotak."
#property link      "@biotak"
#property version   "3.10"
#property strict
#property indicator_chart_window
#property description "Version 3.10 - LITE: Features like Profiler and Freq Optimizer removed"

//                                                                    
// LITE MODE ACTIVATION
//                                                                    
#define BUILD_LITE

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

// Base / Knot Measurement Tool (Lite: no ring menu to arm it, but committed
// boxes keep their drag/delete/badge behavior via EventHandlers).
#include "Biotak\BaseKnotTool.mqh"
// P-HR-01: Horizontal Ray (Lite: nothing arms it, committed rays keep drag/snap/delete).
#include "Biotak\HRayTool.mqh"
#include "Biotak\PathTool.mqh"

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
#include "Biotak\TradePlanFormulas.mqh"   // single source of trade-plan math (R-TRADEPLAN)
#include "Biotak\AdaptiveScaling.mqh"
#include "Biotak\BasePriceManager.mqh"

#ifndef BUILD_LITE
#include "Biotak\WaveAnalysis.mqh"
#include "Biotak\FrequencyOptimizer.mqh"
// TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF (Lite keeps its
// #ifndef BUILD_LITE guard, so this line compiles out here).
#include "Biotak\TH3Tool.mqh"
#endif

//                                                                    
// Drawing & Rendering Pipeline
//                                                                    
#include "Biotak\ObjectFunctions.mqh"
// P-DRAW-01/02: the user's own drawings and their style memory. Compiled in BOTH
// entries — the module owns no UI (the strip lives in the panels, which Lite does
// not have), so the style the user's drawings wear is the same in Lite as in Full
// (P-BUILD-01: a shared module that reached for a UI function would break here).
#include "Biotak\DrawToolbar.mqh"
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
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // P-PERF-04: attach / timeframe-switch budget (silent unless it overruns).
    // P-PERF-10: Lite has no UI half, but it carries the same domain phases
    // (settings / history / base-price file load / ATR) in the report.
    uint p4i = GetTickCount();
    int result = OnInitHandler();
    uint p4ind = GetTickCount() - p4i;
    P4ReportSlow("OnInit (" + (result == INIT_SUCCEEDED ? "ok" : "fail") + ")" +
                 P4InitLedgerTag(p4ind, 0),
                 p4ind, P_P4_INIT_WARN_MS);
    return result;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    uint p4d = GetTickCount();
    OnDeinitHandler(reason);
    P4ReportSlow("OnDeinit reason=" + IntegerToString(reason),
                 GetTickCount() - p4d, P_P4_INIT_WARN_MS);
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
  // P-PERF-34: scope the frame deferral to this window (see EventHandlers).
  g_inChartEvent = true;
  // P-PERF-04: interaction budget (Lite has no menu/panel half to time).
  uint p4t = GetTickCount();
  uint p4a = GetTickCount() - p4t;
  OnChartEventHandler(id,lparam,dparam,sparam);
  g_inChartEvent = false;
  // P-PERF-40: a user action settles the frame it owes, in the SAME event — see
  // the full note in "Biotak Trigger TH3.mq4". An event that only SCHEDULED its
  // frame was answered up to a timer cadence later (measured `waited=46..266ms`)
  // by a repaint of the OLD picture (`body=0ms`), which is the lag the user
  // reports. The pump owns owed work and is budget-bounded, so this cannot become
  // an unbounded in-event stall.
  p4t = GetTickCount();
  CoopPump();
  uint p4c = GetTickCount() - p4t;
  // P-PERF-26: name + id (see EventHandlers: id=1 is OBJECT_CLICK, not the cursor).
  // `settle=` is in the budget check on purpose — a drain must not hide its cost.
   // P-PERF-50: same gate as the Full entry — the ledger message is string
   // garbage on every MOUSE_MOVE while P4ReportSlow would stay silent under
   // budget. Total first, message only when it prints; identical log lines.
   uint p4tot = p4a + p4c;
   if(p4tot >= P_P4_EVENT_WARN_MS)
      P4ReportSlow("chart event " + P4EventName(id) + "(id=" + IntegerToString(id) + ")" +
                   " [settle=" + P4MsTag(p4c) + "]",
                   p4tot, P_P4_EVENT_WARN_MS);
}

//+------------------------------------------------------------------+
//| Timer function - periodic housekeeping                           |
//+------------------------------------------------------------------+
void OnTimer()
{
    // FIX: If indicator is not yet fully initialized (e.g. waiting for history),
    // retry drawing periodically even without new ticks.
    // P-PERF-06: a staged post-wipe rebuild (attach / TF switch / topology
    // toggle) also advances here, so a tick-less chart still settles in ~1 s.
    // P-PERF-35: the coop pump owns the timer's heavy work (see EventHandlers):
    // the sweep jobs are owed once per timer - the cadence they had - and the
    // owed frame is drained last under one millisecond slice.
    CoopOwe(COOP_JOB_OBJ_CLEANUP);
    CoopOwe(COOP_JOB_LABEL_EXPIRY);
    CoopOwe(COOP_JOB_STATUS_TEXT);
    CoopPump();

    // P-UI-100 (2026-09-22): the selection net of the two hand-set lines — the
    // custom price line and the step-1 pair exist in this entry too, so the law
    // and its net are compiled in both (P-BUILD-01: one rule, one spelling).
    // Cost: one probe while the button is down, then three guarded reads.
    HandLinesSelectionNet();
}
