  //+------------------------------------------------------------------+
//|                                       ZoneTrackingHelpers.mqh    |
//|                                  Copyright 2025, Biotak Project  |
//|                    Helper Functions for Zone Tracking            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property strict

#ifndef ZONE_TRACKING_HELPERS_MQH
#define ZONE_TRACKING_HELPERS_MQH

//+------------------------------------------------------------------+
//| Initialize Zone Tracking Variables - GOLD VERSION                |
//|                                Zone -                            |
//|                                                                  |
//| ARCHITECTURE:                                                    |
//| - Structure tracking: Draws zones between structure levels      |
//| - Trigger tracking: Skips first zone from center (starts at 0)  |
//| - Fallback tracking: Draws zones when neither S/T enabled       |
//|                                                                  |
//| CRITICAL RULES:                                                  |
//| 1. Always validate centerPrice before use                       |
//| 2. Always normalize to Digits precision                         |
//| 3. Trigger MUST start from 0 to skip first zone                 |
//|                                                                  |
//| @param centerPrice Center/midpoint price (must be > 0)          |
//| @param lastStructurePrice OUT: Structure tracking variable      |
//| @param lastTriggerPrice OUT: Trigger tracking variable          |
//| @param lastFallbackPrice OUT: Fallback tracking variable        |
//| @return true if successful, false if validation failed          |
//+------------------------------------------------------------------+
bool InitializeZoneTracking(const double centerPrice,
                            double &lastStructurePrice,
                            double &lastTriggerPrice,
                            double &lastFallbackPrice)
{
    //                                                                
    // PHASE 1: VALIDATION (Fail Fast)
    //                                                                
    
    if(centerPrice <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  InitializeZoneTracking: Invalid centerPrice=", centerPrice);
        #endif
        // Set to safe defaults
        lastStructurePrice = 0;
        lastTriggerPrice = 0;
        lastFallbackPrice = 0;
        return false;
    }
    
    // Additional safety: Check for extreme values
    if(centerPrice > 1000000000.0) {  // 1 billion
        #ifdef ENABLE_DEBUG_LOGS
        Print("   InitializeZoneTracking: Suspiciously large centerPrice=", centerPrice);
        #endif
        // Continue but log warning
    }
    
    //                                                                
    // PHASE 2: NORMALIZE FOR PRECISION
    // OPTIMIZATION: Use centralized cached Digits from PerformanceOptimizations.mqh
    //                                                                
    
    int s_cachedDigits = GetCachedDigits();
    
    double normalizedCenter = NormalizeDouble(centerPrice, s_cachedDigits);
    
    // Validate normalization didn't break the value
    if(normalizedCenter <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  InitializeZoneTracking: Normalization failed - result=", normalizedCenter);
        #endif
        lastStructurePrice = 0;
        lastTriggerPrice = 0;
        lastFallbackPrice = 0;
        return false;
    }
    
    //                                                                
    // PHASE 3: INITIALIZE TRACKING VARIABLES
    //                                                                
    
    // Structure: Start from center to draw zones between structure levels
    lastStructurePrice = normalizedCenter;
    
    // Trigger: Start from 0 to SKIP zone between center and first trigger level
    // This is CRITICAL for correct behavior
    lastTriggerPrice = 0;
    
    // Fallback: Start from center to draw zones when neither S/T enabled
    lastFallbackPrice = normalizedCenter;
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("  InitializeZoneTracking: SUCCESS");
    Print("   Center=", DoubleToString(normalizedCenter, s_cachedDigits));
    Print("   Structure=", DoubleToString(lastStructurePrice, s_cachedDigits));
    Print("   Trigger=", DoubleToString(lastTriggerPrice, s_cachedDigits), " (0=skip first zone)");
    Print("   Fallback=", DoubleToString(lastFallbackPrice, s_cachedDigits));
    #endif
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Zone Tracking State - GOLD VERSION                      |
//|                         Zone -                                   |
//|                                                                  |
//| Use this to verify tracking variables are in valid state        |
//|                                tracking                         |
//|                                                                  |
//| @param lastStructurePrice Structure tracking variable           |
//| @param lastTriggerPrice Trigger tracking variable               |
//| @param lastFallbackPrice Fallback tracking variable             |
//| @param contextName Name for logging (e.g., "M Mode Above")      |
//| @return true if state is valid, false otherwise                 |
//+------------------------------------------------------------------+
bool ValidateZoneTrackingState(const double lastStructurePrice,
                               const double lastTriggerPrice,
                               const double lastFallbackPrice,
                               const string contextName)
{
    bool isValid = true;
    
    // OPTIMIZATION: Use centralized cached Digits from PerformanceOptimizations.mqh
    int s_cachedDigitsValidate = GetCachedDigits();
    
    // Structure and Fallback should be > 0 (or both 0 if not initialized)
    if(lastStructurePrice < 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ", contextName, ": Invalid lastStructurePrice=", lastStructurePrice);
        #endif
        isValid = false;
    }
    
    if(lastFallbackPrice < 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ", contextName, ": Invalid lastFallbackPrice=", lastFallbackPrice);
        #endif
        isValid = false;
    }
    
    // Trigger can be 0 (intentionally, to skip first zone) or > 0
    if(lastTriggerPrice < 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ", contextName, ": Invalid lastTriggerPrice=", lastTriggerPrice);
        #endif
        isValid = false;
    }
    
    // Sanity check: Structure and Fallback should be similar (unless one is 0)
    if(lastStructurePrice > 0 && lastFallbackPrice > 0) {
        double ratio = lastStructurePrice / lastFallbackPrice;
        if(ratio < 0.5 || ratio > 2.0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("   ", contextName, ": Structure/Fallback mismatch - S=", 
                  DoubleToString(lastStructurePrice, s_cachedDigitsValidate), 
                  ", F=", DoubleToString(lastFallbackPrice, s_cachedDigitsValidate));
            #endif
            // Not necessarily an error, just suspicious
        }
    }
    
    return isValid;
}

#endif // ZONE_TRACKING_HELPERS_MQH
