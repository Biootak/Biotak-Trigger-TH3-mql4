  //+------------------------------------------------------------------+
//|                                   InputValidationEnhanced.mqh     |
//|                                  GOLD FIX: Input Security Layer   |
//|                                  Comprehensive Validation         |
//+------------------------------------------------------------------+
#property copyright "  Biotak - Security Enhanced"
#property strict

//+------------------------------------------------------------------+
//| GOLD FIX #19: Enhanced Input Validation with Range Checking      |
//+------------------------------------------------------------------+

// Validation result structure
struct ValidationResult {
    bool isValid;
    string errorMessage;
    double correctedValue;
};

//+------------------------------------------------------------------+
//| Validate price input with comprehensive checks                   |
//+------------------------------------------------------------------+
ValidationResult ValidatePriceInput(double price, const string paramName) {
    ValidationResult result;
    result.isValid = true;
    result.correctedValue = price;
    result.errorMessage = "";
    
    // Check for negative
    if(price < 0) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s cannot be negative: %.5f", paramName, price);
        result.correctedValue = 0;
        return result;
    }
    
    // Check for zero (if not allowed)
    if(price == 0) {
        result.errorMessage = StringFormat("%s is zero - using default", paramName);
        result.correctedValue = 0;
        return result;
    }
    
    // Check for unreasonably large values
    double maxReasonablePrice = 1000000.0;  // 1 million
    if(price > maxReasonablePrice) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too large: %.2f (max: %.2f)", 
                                          paramName, price, maxReasonablePrice);
        result.correctedValue = maxReasonablePrice;
        return result;
    }
    
    // Check for unreasonably small values (but not zero)
    double minReasonablePrice = 0.00001;
    if(price > 0 && price < minReasonablePrice) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too small: %.8f (min: %.8f)", 
                                          paramName, price, minReasonablePrice);
        result.correctedValue = minReasonablePrice;
        return result;
    }
    
    // Check for NaN or Infinity
    if(price != price || price == EMPTY_VALUE) {  // NaN check
        result.isValid = false;
        result.errorMessage = StringFormat("%s is NaN or EMPTY_VALUE", paramName);
        result.correctedValue = 0;
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Validate percentage input (0-100 or 0-1000 depending on context) |
//+------------------------------------------------------------------+
ValidationResult ValidatePercentageInput(double percentage, const string paramName,
                                         double minValue = 0.001, double maxValue = 100.0) {
    ValidationResult result;
    result.isValid = true;
    result.correctedValue = percentage;
    result.errorMessage = "";
    
    // Check range
    if(percentage < minValue) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too small: %.3f (min: %.3f)", 
                                          paramName, percentage, minValue);
        result.correctedValue = minValue;
        return result;
    }
    
    if(percentage > maxValue) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too large: %.3f (max: %.3f)", 
                                          paramName, percentage, maxValue);
        result.correctedValue = maxValue;
        return result;
    }
    
    // Check for NaN
    if(percentage != percentage) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s is NaN", paramName);
        result.correctedValue = minValue;
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Validate integer input with range                                |
//+------------------------------------------------------------------+
ValidationResult ValidateIntegerInput(int value, const string paramName,
                                      int minValue, int maxValue) {
    ValidationResult result;
    result.isValid = true;
    result.correctedValue = value;
    result.errorMessage = "";
    
    if(value < minValue) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too small: %d (min: %d)", 
                                          paramName, value, minValue);
        result.correctedValue = minValue;
        return result;
    }
    
    if(value > maxValue) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too large: %d (max: %d)", 
                                          paramName, value, maxValue);
        result.correctedValue = maxValue;
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Validate color input                                             |
//+------------------------------------------------------------------+
bool ValidateColorInput(color clr, const string paramName) {
    // Check if color is valid (not clrNONE unless explicitly allowed)
    if(clr == clrNONE) {
        Print("   ", paramName, " is clrNONE - using default");
        return false;
    }
    
    // MQL4 colors are 32-bit integers, check if in valid range
    int colorValue = (int)clr;
    if(colorValue < 0 || colorValue > 0xFFFFFF) {
        Print("  ", paramName, " has invalid color value: ", colorValue);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate string input (non-empty, length limits)                 |
//+------------------------------------------------------------------+
ValidationResult ValidateStringInput(const string value, const string paramName,
                                     int minLength = 1, int maxLength = 255) {
    ValidationResult result;
    result.isValid = true;
    result.errorMessage = "";
    
    int length = StringLen(value);
    
    if(length < minLength) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too short: %d chars (min: %d)", 
                                          paramName, length, minLength);
        return result;
    }
    
    if(length > maxLength) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s too long: %d chars (max: %d)", 
                                          paramName, length, maxLength);
        return result;
    }
    
    // Check for null bytes
    if(StringFind(value, "\0") >= 0) {
        result.isValid = false;
        result.errorMessage = StringFormat("%s contains null bytes", paramName);
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Validate array size before operations                            |
//+------------------------------------------------------------------+
bool ValidateArraySize(const int size, const string arrayName, 
                       int minSize = 0, int maxSize = 100000) {
    if(size < minSize) {
        Print("  ", arrayName, " size too small: ", size, " (min: ", minSize, ")");
        return false;
    }
    
    if(size > maxSize) {
        Print("  ", arrayName, " size too large: ", size, " (max: ", maxSize, ")");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Sanitize filename for safe file operations                       |
//+------------------------------------------------------------------+
string SanitizeFilename(const string filename) {
    string safe = filename;
    
    // Remove path traversal
    StringReplace(safe, "..", "");
    StringReplace(safe, "/", "_");
    StringReplace(safe, "\\", "_");
    
    // Remove dangerous characters
    StringReplace(safe, ":", "");
    StringReplace(safe, "*", "");
    StringReplace(safe, "?", "");
    StringReplace(safe, "\"", "");
    StringReplace(safe, "<", "");
    StringReplace(safe, ">", "");
    StringReplace(safe, "|", "");
    StringReplace(safe, "\0", "");
    StringReplace(safe, "\n", "");
    StringReplace(safe, "\r", "");
    
    // Ensure not empty
    if(StringLen(safe) == 0) {
        safe = "default";
    }
    
    // Limit length
    if(StringLen(safe) > 200) {
        safe = StringSubstr(safe, 0, 200);
    }
    
    return safe;
}
