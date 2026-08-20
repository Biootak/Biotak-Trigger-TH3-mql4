  //+------------------------------------------------------------------+
//|                                        ValidationUtilities.mqh   |
//|                     Centralized Validation Functions             |
//|                                                                  |
//|                     DRY Principle Implementation                 |
//+------------------------------------------------------------------+
#ifndef VALIDATION_UTILITIES_MQH
#define VALIDATION_UTILITIES_MQH
#property strict

#include "FloatingPointHelper.mqh"
#include "ErrorCodes.mqh"

//+------------------------------------------------------------------+
//| Validation Result Structure                                      |
//+------------------------------------------------------------------+
struct ValidationResult {
    bool isValid;
    int errorCode;
    string errorMessage;
    double correctedValue;
};

//+------------------------------------------------------------------+
//| Validate Array Index                                             |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateArrayIndex(int index, int arraySize, const string context = "") {
    if(index < 0) {
        Print("  ValidateArrayIndex: Negative index (", index, ")", 
              (StringLen(context) > 0) ? " in " + context : "");
        return false;
    }
    
    if(index >= arraySize) {
        Print("  ValidateArrayIndex: Index out of bounds (", index, " >= ", arraySize, ")",
              (StringLen(context) > 0) ? " in " + context : "");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Array Sizes Match                                       |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateArraySizesMatch(int size1, int size2, const string name1, const string name2) {
    if(size1 != size2) {
        Print("  Array size mismatch: ", name1, "=", size1, ", ", name2, "=", size2);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Validate Price Value                                             |
//|                                                                  |
//+------------------------------------------------------------------+
ValidationResult ValidatePrice(double price, const string paramName = "price") {
    ValidationResult result;
    result.isValid = true;
    result.errorCode = 0;
    result.errorMessage = "";
    result.correctedValue = price;
    
    // Check for negative
    if(price < 0) {
        result.isValid = false;
        result.errorCode = ERR_INVALID_PRICE;
        result.errorMessage = paramName + " cannot be negative: " + DoubleToString(price, 5);
        result.correctedValue = 0;
        return result;
    }
    
    // Check for zero (warning, not error)
    if(IsZero(price, EPSILON_PRICE)) {
        result.errorMessage = paramName + " is zero";
        result.correctedValue = 0;
        return result;
    }
    
    // Check for unreasonably large values
    double maxReasonablePrice = 1000000.0;
    if(price > maxReasonablePrice) {
        result.isValid = false;
        result.errorCode = ERR_OUT_OF_RANGE;
        result.errorMessage = paramName + " too large: " + DoubleToString(price, 2);
        result.correctedValue = maxReasonablePrice;
        return result;
    }
    
    // Check for unreasonably small values
    double minReasonablePrice = 0.00001;
    if(price > 0 && price < minReasonablePrice) {
        result.isValid = false;
        result.errorCode = ERR_OUT_OF_RANGE;
        result.errorMessage = paramName + " too small: " + DoubleToString(price, 8);
        result.correctedValue = minReasonablePrice;
        return result;
    }
    
    // Check for NaN or Infinity
    if(price != price || price == EMPTY_VALUE) {
        result.isValid = false;
        result.errorCode = ERR_INVALID_PRICE;
        result.errorMessage = paramName + " is NaN or EMPTY_VALUE";
        result.correctedValue = 0;
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Validate Percentage Value                                        |
//|                                                                  |
//+------------------------------------------------------------------+
ValidationResult ValidatePercentage(double percentage, double minValue = 0.001, 
                                    double maxValue = 100.0, const string paramName = "percentage") {
    ValidationResult result;
    result.isValid = true;
    result.errorCode = 0;
    result.errorMessage = "";
    result.correctedValue = percentage;
    
    // Check range
    if(percentage < minValue) {
        result.isValid = false;
        result.errorCode = ERR_OUT_OF_RANGE;
        result.errorMessage = paramName + " too small: " + DoubleToString(percentage, 3) + 
                            " (min: " + DoubleToString(minValue, 3) + ")";
        result.correctedValue = minValue;
        return result;
    }
    
    if(percentage > maxValue) {
        result.isValid = false;
        result.errorCode = ERR_OUT_OF_RANGE;
        result.errorMessage = paramName + " too large: " + DoubleToString(percentage, 3) + 
                            " (max: " + DoubleToString(maxValue, 3) + ")";
        result.correctedValue = maxValue;
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Validate Integer Range                                           |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateIntRange(int value, int minValue, int maxValue, const string paramName = "value") {
    if(value < minValue || value > maxValue) {
        Print("  ", paramName, " out of range: ", value, " (valid: ", minValue, "-", maxValue, ")");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Validate String Not Empty                                        |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateStringNotEmpty(const string str, const string paramName = "string") {
    if(StringLen(str) == 0) {
        Print("  ", paramName, " is empty");
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Validate Timeframe                                               |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateTimeframe(int timeframe) {
    // Valid MT4 timeframes
    switch(timeframe) {
        case PERIOD_M1:
        case PERIOD_M5:
        case PERIOD_M15:
        case PERIOD_M30:
        case PERIOD_H1:
        case PERIOD_H4:
        case PERIOD_D1:
        case PERIOD_W1:
        case PERIOD_MN1:
            return true;
        default:
            Print("  Invalid timeframe: ", timeframe);
            return false;
    }
}

//+------------------------------------------------------------------+
//| Validate Color Value                                             |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateColor(color clr, const string paramName = "color") {
    // In MQL4, color is uint, so always >= 0
    // Check for clrNONE (special value)
    if(clr == clrNONE) {
        Print("   ", paramName, " is clrNONE");
        return true; // Not an error, just a warning
    }
    
    // Check for valid RGB range (0x00RRGGBB)
    if(clr > 0x00FFFFFF) {
        Print("  ", paramName, " invalid: ", ColorToString(clr));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Batch Validation Helper                                          |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidatePriceRange(double price1, double price2, const string name1, const string name2) {
    ValidationResult result1 = ValidatePrice(price1, name1);
    ValidationResult result2 = ValidatePrice(price2, name2);
    
    if(!result1.isValid) {
        Print("  ", result1.errorMessage);
        return false;
    }
    
    if(!result2.isValid) {
        Print("  ", result2.errorMessage);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Division Operands                                       |
//|                                                                  |
//+------------------------------------------------------------------+
bool ValidateDivisionOperands(double numerator, double denominator, const string context = "") {
    if(IsZero(denominator, EPSILON_GENERAL)) {
        Print("  Division by zero", (StringLen(context) > 0) ? " in " + context : "",
              " (denominator=", DoubleToString(denominator, 10), ")");
        return false;
    }
    
    // Check for potential overflow
    if(MathAbs(numerator) > DBL_MAX / 2.0 && MathAbs(denominator) < 1.0) {        Print("   Potential overflow in division", (StringLen(context) > 0) ? " in " + context : "");
        return false;
    }

    return true;
}

#endif // VALIDATION_UTILITIES_MQH
