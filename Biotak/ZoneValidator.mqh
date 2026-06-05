  //+------------------------------------------------------------------+
//|                                                ZoneValidator.mqh |
//|                                  Copyright 2025, Biotak Project  |
//|                                    Zone Validation & Safety      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#include "ConstantsAndEnums.mqh"
#include "ZoneConstants.mqh"

//+------------------------------------------------------------------+
//| Validate Input Arrays                                            |
//|                                                                   |
//+------------------------------------------------------------------+
bool ValidateInputArrays(const SLevelRawData &levels[], int &outCount)
{
    outCount = ArraySize(levels);
    
    if(outCount <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateInputArrays: Empty levels array");
        #endif
        return false;
    }
    
    // Check for NULL prices
    for(int i = 0; i < outCount; i++) {
        if(levels[i].price <= 0) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("  ValidateInputArrays: Invalid price at index ", i, ": ", levels[i].price);
            #endif
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Step Size                                               |
//|                                                                   |
//+------------------------------------------------------------------+
bool ValidateStepSize(double stepSize)
{
    if(stepSize <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateStepSize: Invalid stepSize=", stepSize);
        #endif
        return false;
    }
    
    // Check for unreasonably large step (> 50% of typical price)
    double typicalPrice = (Bid + Ask) / 2.0;
    if(typicalPrice > 0 && stepSize > typicalPrice * 0.5) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   ValidateStepSize: Suspiciously large stepSize=", stepSize, 
              " (> 50% of price=", typicalPrice, ")");
        #endif
        // Don't fail, just warn
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Style Config                                            |
//|                                                                   |
//+------------------------------------------------------------------+
bool ValidateStyleConfig(const SStyleConfig &config)
{
    // Validate zone height percent
    if(config.zoneHeightPercent < 0 || config.zoneHeightPercent > 1.0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateStyleConfig: Invalid zoneHeightPercent=", config.zoneHeightPercent,
              " (must be 0.0-1.0)");
        #endif
        return false;
    }
    
    // Validate transparency
    if(config.zoneTransparency < 0 || config.zoneTransparency > 100) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateStyleConfig: Invalid zoneTransparency=", config.zoneTransparency,
              " (must be 0-100)");
        #endif
        return false;
    }
    
    // Validate base multiplier (CRITICAL: prevent division by zero)
    if(config.baseMultiplier < 1) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateStyleConfig: Invalid baseMultiplier=", config.baseMultiplier,
              " (must be >= 1)");
        #endif
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Zone Height                                             |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateZoneHeight(double zoneHeight, double stepSize)
{
    if(zoneHeight <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateZoneHeight: Invalid zoneHeight=", zoneHeight);
        #endif
        return false;
    }
    
    // Zone height should not exceed step size
    if(zoneHeight > stepSize) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("   ValidateZoneHeight: Zone height (", zoneHeight, 
              ") exceeds step size (", stepSize, ")");
        #endif
        // Don't fail, just warn
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Zone Geometry                                           |
//|                                                                  |
//+------------------------------------------------------------------+
SZoneValidationResult ValidateZoneGeometry(
    double prevPrice, 
    double currentPrice,
    double zoneHeight)
{
    SZoneValidationResult result;
    result.isValid = false;
    result.errorCode = ZONE_ERROR_NONE;
    result.errorMessage = "";
    
    // OPTIMIZATION: Use centralized cached values from PerformanceOptimizations.mqh
    int s_cachedDigits = GetCachedDigits();
    double s_cachedPoint = GetCachedPoint();
    
    // Check for invalid prices
    if(prevPrice <= 0 || currentPrice <= 0) {
        result.errorCode = ZONE_ERROR_INVALID_PRICES;
        result.errorMessage = "Invalid prices: prev=" + DoubleToString(prevPrice, s_cachedDigits) +
                            ", current=" + DoubleToString(currentPrice, s_cachedDigits);
        return result;
    }
    
    // Check for equal prices (use cached Point)
    if(MathAbs(prevPrice - currentPrice) < s_cachedPoint) {
        result.errorCode = ZONE_ERROR_EQUAL_PRICES;
        result.errorMessage = "Prices are equal (no zone needed)";
        return result;
    }
    
    // Check zone height
    if(zoneHeight <= 0) {
        result.errorCode = ZONE_ERROR_INVALID_HEIGHT;
        result.errorMessage = "Invalid zone height: " + DoubleToString(zoneHeight, s_cachedDigits);
        return result;
    }
    
    // Calculate midpoint and boundaries
    double midPoint = (prevPrice + currentPrice) / 2.0;
    double topPrice = midPoint + zoneHeight;
    double bottomPrice = midPoint - zoneHeight;
    
    // Check for inverted bounds
    if(topPrice <= bottomPrice) {
        result.errorCode = ZONE_ERROR_INVERTED_BOUNDS;
        result.errorMessage = "Inverted bounds: top=" + DoubleToString(topPrice, s_cachedDigits) +
                            ", bottom=" + DoubleToString(bottomPrice, s_cachedDigits);
        return result;
    }
    
    // Check for reasonable range (not too far from current price)
    //            cached market price                
    double currentMarketPrice = GetCachedMarketPrice();
    if(currentMarketPrice > 0) {
        double maxReasonableDistance = currentMarketPrice * 2.0; // 200% of current price
        
        if(MathAbs(topPrice - currentMarketPrice) > maxReasonableDistance ||
           MathAbs(bottomPrice - currentMarketPrice) > maxReasonableDistance) {
            result.errorCode = ZONE_ERROR_OUT_OF_RANGE;
            result.errorMessage = "Zone too far from current price";
            // Don't fail, just warn
            #ifdef ENABLE_DEBUG_LOGS
            Print("   ValidateZoneGeometry: ", result.errorMessage);
            #endif
        }
    }
    
    // All checks passed
    result.isValid = true;
    return result;
}

//+------------------------------------------------------------------+
//| Validate Complete Configuration                                  |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateCompleteConfig(
    const SLevelRawData &levels[],
    double stepSize,
    const SStyleConfig &config,
    int &outCount,
    double &outZoneHeight)
{
    // GOLD FIX v3: Use existing validation functions (DRY principle)
    
    // Validate input arrays
    if(!ValidateInputArrays(levels, outCount)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateCompleteConfig: Input array validation failed");
        #endif
        return false;
    }
    
    // Validate step size
    if(!ValidateStepSize(stepSize)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateCompleteConfig: Step size validation failed");
        #endif
        return false;
    }
    
    // Validate style config
    if(!ValidateStyleConfig(config)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateCompleteConfig: Style config validation failed");
        #endif
        return false;
    }
    
    // Calculate and validate zone height (unique to this function)
    outZoneHeight = stepSize * config.zoneHeightPercent * 0.5;
    if(outZoneHeight <= 0) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("  ValidateCompleteConfig: Invalid zoneHeight=", outZoneHeight);
        #endif
        return false;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    // OPTIMIZATION: Use centralized cached Digits value
    int s_cachedDigitsConfig = GetCachedDigits();
    
    Print("  ValidateCompleteConfig: All validations passed");
    Print("   Count=", outCount, ", StepSize=", DoubleToString(stepSize, s_cachedDigitsConfig),
          ", ZoneHeight=", DoubleToString(outZoneHeight, s_cachedDigitsConfig));
    #endif
    
    return true;
}
