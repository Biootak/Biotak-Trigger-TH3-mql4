  //+------------------------------------------------------------------+
//|                                            ATRCalculations.mqh   |
//|                                                                  |
//| ATR-Based Calculations for Biotak Trigger TH3                   |
//|                  ATR                                            |
//|                                                                  |
//| This module implements ATR_BASIS calculation mode matching       |
//| the Java/MotiveWave implementation exactly.                      |
//|                                                                  |
//| Key Features:                                                    |
//| - Weighted ATR calculation (multiple periods with weights)       |
//| - Hybrid ATR (current TF + fractal scaling for others)          |
//| - Batch ATR calculation for performance                          |
//| - Full compatibility with existing TH_BASIS mode                 |
//|                                                                  |
//| AUDIT UPDATE v3.11 (2026-02-02):                                 |
//|   Added FloatingPointHelper integration for safe comparisons    |
//|   Implemented SafeDivide/SafeSqrt for all calculations          |
//|   Enhanced validation for all inputs and outputs                |
//|   Multi-timeframe caching for better performance                |
//|   Comprehensive error handling with debug logs                  |
//|   Overflow protection in weighted calculations                  |
//|   Array bounds checking in batch operations                     |
//+------------------------------------------------------------------+
#ifndef ATR_CALCULATIONS_MQH
#define ATR_CALCULATIONS_MQH

#include "ATR_A.mqh"
#include "ATR_B.mqh"

#endif // ATR_CALCULATIONS_MQH
