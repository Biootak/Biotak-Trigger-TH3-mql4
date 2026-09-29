//+------------------------------------------------------------------+
//|                                             RuntimeSettings.mqh  |
//|  SINGLE OWNER of the runtime-editable settings.                  |
//|                                                                  |
//|  The indicator has two ways to configure the same settings:      |
//|    1. MT4 Inputs dialog  ->  the real `input` variables declared |
//|       in PropertiesAndInputs.mqh (groups 01..18).                |
//|    2. Settings panels    ->  live edits on the chart.            |
//|                                                                  |
//|  Runtime-editable settings therefore keep a runtime copy (g_*)   |
//|  plus a macro redirection (#define inpX gX) so that ALL modules  |
//|  compiled after this file read the runtime copy — never the raw  |
//|  input variable (which the panels cannot update).                |
//|                                                                  |
//|  Ownership & lifecycle:                                          |
//|    · input declarations ......... PropertiesAndInputs.mqh        |
//|    · runtime copies + redirection  THIS FILE (RuntimeSettings)   |
//|    · seeding from the inputs .... RuntimeSettingsInit() called   |
//|      first thing in OnInitHandler — the MT4 Inputs dialog values |
//|      are copied into the runtime copies at attach time.          |
//|    · persisted overrides ........ RuntimeSettings(Load|Save)     |
//|      Overrides (OV_* chart-scoped GVs) re-applied on top after  |
//|      seeding; panels/hotkeys edit the runtime copies live.       |
//|                                                                  |
//|  Include order (both entry .mq4 files):                          |
//|    PropertiesAndInputs.mqh  (declares the real inputs)           |
//|    ... core/validation modules ...                               |
//|    RuntimeSettings.mqh      (THIS FILE — mirrors + #defines)     |
//|    GlobalVariables.mqh      (runtime indicator state)            |
//|    ... all consumers read inpX == runtime copy ...               |
//|                                                                  |
//|  NOTE: the seeding body below is written BEFORE the #define      |
//|  block on purpose — only there are the real input names still    |
//|  reachable (macros would rewrite them into no-op self-assigns).  |
//+------------------------------------------------------------------+
#ifndef RUNTIME_SETTINGS_MQH
#define RUNTIME_SETTINGS_MQH

#include "Runtime_A.mqh"
#include "Runtime_B.mqh"

#endif // RUNTIME_SETTINGS_MQH
