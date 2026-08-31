//+------------------------------------------------------------------+
//|                                        BatchPropertyUpdater.mqh  |
//|                                      Biotak Trigger TH3 Indicator |
//|                    Batch Property Update Optimizations            |
//+------------------------------------------------------------------+
#property copyright "Biotak"
#property strict

//+------------------------------------------------------------------+
//| Batch Property Update Configuration                               |
//| Controls how properties are updated in batch operations          |
//+------------------------------------------------------------------+
struct SBatchPropertyConfig {
    bool updatePrice;      // Should price be updated?
    bool updateColor;      // Should color be updated?
    bool updateStyle;      // Should style be updated?
    bool updateWidth;      // Should width be updated?
    bool updateTooltip;    // Should tooltip be updated?
    bool updateSelectable; // Should selectable be updated?
};

//+------------------------------------------------------------------+
//| Line Object Properties for Batch Update                          |
//| All properties needed for a complete line object update          |
//+------------------------------------------------------------------+
struct SLineObjectProperties {
    double price;              // Line price
    color lineColor;           // Line color
    int style;                 // Line style (ENUM_LINE_STYLE)
    int width;                 // Line width
    string tooltip;            // Tooltip text
    bool selectable;           // Is selectable?
    bool back;                 // Draw in background?
};

//+------------------------------------------------------------------+
//| Zone Object Properties for Batch Update                          |
//| All properties needed for a complete zone object update          |
//+------------------------------------------------------------------+
struct SZoneObjectProperties {
    double topPrice;           // Top boundary price
    double bottomPrice;        // Bottom boundary price
    datetime startTime;        // Start time
    datetime endTime;          // End time
    color zoneColor;           // Zone color (with transparency)
    bool filled;               // Is filled?
    bool back;                 // Draw in background?
    bool selectable;           // Is selectable?
    bool rayRight;             // Extend to right?
};

//+------------------------------------------------------------------+
//| Batch Update Line Object Properties                              |
//| Updates all properties in sequence without intermediate operations|
//| Requirement 8.1, 8.3: Batch property setting                     |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the line object                           |
//|   props - Properties to set                                      |
//|   config - Which properties to update                            |
//| Returns: true if all updates succeeded                           |
//+------------------------------------------------------------------+
bool BatchUpdateLineProperties(const string objectName,
                               const SLineObjectProperties &props,
                               const SBatchPropertyConfig &config) {
    bool success = true;
    
    // Requirement 8.3: Set all properties in sequence without intermediate operations
    // No ObjectFind or other queries between ObjectSet calls
    
    if(config.updatePrice) {
        success = success && ObjectSetDouble(0, objectName, OBJPROP_PRICE, props.price);
    }
    
    if(config.updateColor) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_COLOR, props.lineColor);
    }
    
    if(config.updateStyle) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_STYLE, props.style);
    }
    
    if(config.updateWidth) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_WIDTH, props.width);
    }
    
    if(config.updateTooltip) {
        success = success && ObjectSetString(0, objectName, OBJPROP_TOOLTIP, props.tooltip);
    }
    
    if(config.updateSelectable) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, props.selectable);
    }
    
    // Always set back property for consistency
    success = success && ObjectSetInteger(0, objectName, OBJPROP_BACK, props.back);
    
    return success;
}

//+------------------------------------------------------------------+
//| Batch Update Zone Object Properties                              |
//| Updates all properties in sequence without intermediate operations|
//| Requirement 8.1, 8.3: Batch property setting                     |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the zone object                           |
//|   props - Properties to set                                      |
//| Returns: true if all updates succeeded                           |
//+------------------------------------------------------------------+
bool BatchUpdateZoneProperties(const string objectName,
                               const SZoneObjectProperties &props) {
    bool success = true;
    
    // Requirement 8.3: Set all properties in sequence without intermediate operations
    // No ObjectFind or other queries between ObjectSet calls
    
    // Update geometry (prices and times)
    success = success && ObjectSetDouble(0, objectName, OBJPROP_PRICE, 0, props.topPrice);
    success = success && ObjectSetDouble(0, objectName, OBJPROP_PRICE, 1, props.bottomPrice);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_TIME, 0, props.startTime);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_TIME, 1, props.endTime);
    
    // Update visual properties
    success = success && ObjectSetInteger(0, objectName, OBJPROP_COLOR, props.zoneColor);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_FILL, props.filled);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_BACK, props.back);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, props.selectable);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, props.rayRight);
    
    return success;
}

//+------------------------------------------------------------------+
//| Optimized Single Property Update - Price Only                    |
//| Requirement 8.2: Single property update optimization             |
//|                                                                  |
//| When only price needs updating, this function provides the       |
//| fastest path by updating only the price property.                |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the object                                |
//|   newPrice - New price value                                     |
//| Returns: true if update succeeded                                |
//+------------------------------------------------------------------+
bool UpdatePriceOnly(const string objectName, const double newPrice) {
    // Requirement 8.2: Optimize single property updates (price only)
    // Skip all other ObjectSet calls when only price changes
    return ObjectSetDouble(0, objectName, OBJPROP_PRICE, newPrice);
}

//+------------------------------------------------------------------+
//| Optimized Single Property Update - Color Only                    |
//| Requirement 8.2: Single property update optimization             |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the object                                |
//|   newColor - New color value                                     |
//| Returns: true if update succeeded                                |
//+------------------------------------------------------------------+
bool UpdateColorOnly(const string objectName, const color newColor) {
    // Requirement 8.2: Optimize single property updates
    return ObjectSetInteger(0, objectName, OBJPROP_COLOR, newColor);
}

//+------------------------------------------------------------------+
//| Optimized Single Property Update - Style Only                    |
//| Requirement 8.2: Single property update optimization             |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the object                                |
//|   newStyle - New style value                                     |
//| Returns: true if update succeeded                                |
//+------------------------------------------------------------------+
bool UpdateStyleOnly(const string objectName, const int newStyle) {
    // Requirement 8.2: Optimize single property updates
    return ObjectSetInteger(0, objectName, OBJPROP_STYLE, newStyle);
}

//+------------------------------------------------------------------+
//| Optimized Single Property Update - Width Only                    |
//| Requirement 8.2: Single property update optimization             |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the object                                |
//|   newWidth - New width value                                     |
//| Returns: true if update succeeded                                |
//+------------------------------------------------------------------+
bool UpdateWidthOnly(const string objectName, const int newWidth) {
    // Requirement 8.2: Optimize single property updates
    return ObjectSetInteger(0, objectName, OBJPROP_WIDTH, newWidth);
}

//+------------------------------------------------------------------+
//| Smart Property Update - Detects and Updates Only Changed Props   |
//| Requirement 8.5: Avoid redundant property calls                  |
//|                                                                  |
//| This function uses PropertyChangeDetector to identify which      |
//| properties have changed and updates only those properties.       |
//| It also uses single-property optimizations when only one         |
//| property has changed.                                            |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the object                                |
//|   cached - Cached object entry with old values                   |
//|   newProps - New property values                                 |
//| Returns: true if update succeeded                                |
//+------------------------------------------------------------------+
bool SmartUpdateLineProperties(const string objectName,
                               const SObjectCacheEntry &cached,
                               const SLineObjectProperties &newProps) {
    // Detect which properties have changed
    SPropertyChangeResult changes = DetectPropertyChanges(
        cached.lastPrice, newProps.price,
        cached.lastColor, newProps.lineColor,
        cached.lastStyle, newProps.style,
        cached.lastWidth, newProps.width
    );
    
    // Requirement 8.5: Avoid redundant property calls
    // If no properties changed, skip all updates
    if(!changes.anyChanged) {
        return true;
    }
    
    // Requirement 8.2: Optimize single property updates
    // If only one property changed, use optimized single-property update
    int changedCount = 0;
    if(changes.priceChanged) changedCount++;
    if(changes.colorChanged) changedCount++;
    if(changes.styleChanged) changedCount++;
    if(changes.widthChanged) changedCount++;
    
    if(changedCount == 1) {
        // Single property optimization
        if(changes.priceChanged) {
            return UpdatePriceOnly(objectName, newProps.price);
        }
        if(changes.colorChanged) {
            return UpdateColorOnly(objectName, newProps.lineColor);
        }
        if(changes.styleChanged) {
            return UpdateStyleOnly(objectName, newProps.style);
        }
        if(changes.widthChanged) {
            return UpdateWidthOnly(objectName, newProps.width);
        }
    }
    
    // Multiple properties changed - use batch update
    // Requirement 8.3: Batch property setting
    SBatchPropertyConfig config;
    config.updatePrice = changes.priceChanged;
    config.updateColor = changes.colorChanged;
    config.updateStyle = changes.styleChanged;
    config.updateWidth = changes.widthChanged;
    config.updateTooltip = false; // Tooltip doesn't change typically
    config.updateSelectable = false; // Selectable doesn't change typically
    
    return BatchUpdateLineProperties(objectName, newProps, config);
}

//+------------------------------------------------------------------+
//| Create Line Object with Batch Property Setting                   |
//| Requirement 8.1: Batch property setting for new objects          |
//|                                                                  |
//| Creates a new line object and sets all properties in a single    |
//| batch operation without intermediate queries.                    |
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the object to create                      |
//|   objectType - Type of object (OBJ_HLINE, OBJ_TREND, etc.)      |
//|   props - All properties to set                                  |
//| Returns: true if creation and property setting succeeded         |
//+------------------------------------------------------------------+
bool CreateLineObjectWithBatchProperties(const string objectName,
                                         const ENUM_OBJECT objectType,
                                         const SLineObjectProperties &props) {
    // Create the object first — use cached frame time to avoid syscall per creation
    datetime currentTime = CacheGetFrameTime();
    if(currentTime == 0) currentTime = TimeCurrent();
    datetime futureTime = currentTime + PeriodSeconds((ENUM_TIMEFRAMES)GetCachedPeriod()) * 100;
    
    bool created = false;
    if(objectType == OBJ_TREND) {
        created = ObjectCreate(0, objectName, objectType, 0, currentTime, props.price, futureTime, props.price);
    } else {
        created = ObjectCreate(0, objectName, objectType, 0, currentTime, props.price);
    }
    
    if(!created) {
        return false;
    }
    
    // Requirement 8.1: Set all properties in sequence without intermediate operations
    // Batch set all visual properties immediately after creation
    bool success = true;
    success = success && ObjectSetInteger(0, objectName, OBJPROP_COLOR, props.lineColor);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_STYLE, props.style);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_WIDTH, props.width);
    success = success && ObjectSetString(0, objectName, OBJPROP_TOOLTIP, props.tooltip);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, props.selectable);
    success = success && ObjectSetInteger(0, objectName, OBJPROP_BACK, props.back);
    
    if(!success) {
        // Cleanup on failure
        ObjectDelete(0, objectName);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Batch Update Multiple Objects                                     |
//| Requirement 8.4: Process multiple objects in a single loop       |
//|                                                                  |
//| Updates multiple line objects in a single batch operation.       |
//|                                                                  |
//| Parameters:                                                       |
//|   objectNames - Array of object names                            |
//|   properties - Array of properties (must match objectNames size)|
//|   count - Number of objects to update                            |
//| Returns: Number of successfully updated objects                  |
//+------------------------------------------------------------------+
int BatchUpdateMultipleLineObjects(const string &objectNames[],
                                   const SLineObjectProperties &properties[],
                                   const int count) {
    int successCount = 0;
    
    // Requirement 8.4: Process multiple objects in a single loop
    for(int i = 0; i < count; i++) {
        SBatchPropertyConfig config;
        config.updatePrice = true;
        config.updateColor = true;
        config.updateStyle = true;
        config.updateWidth = true;
        config.updateTooltip = true;
        config.updateSelectable = false;
        
        if(BatchUpdateLineProperties(objectNames[i], properties[i], config)) {
            successCount++;
        }
    }
    
    return successCount;
}

//+------------------------------------------------------------------+
//| Prevent Redundant Property Calls                                 |
//| Requirement 8.5: No redundant property calls                     |
//|                                                                  |
//| This structure tracks which properties have been set in the      |
//| current update cycle to prevent setting the same property twice. |
//+------------------------------------------------------------------+
struct SPropertySetTracker {
    bool priceSet;
    bool colorSet;
    bool styleSet;
    bool widthSet;
    bool tooltipSet;
    bool selectableSet;
};

//+------------------------------------------------------------------+
//| Tracked Property Update - Prevents Duplicate Calls               |
//| Requirement 8.5: Avoid redundant property calls                  |
//|                                                                  |
//| Updates a property only if it hasn't been set already in this    |
//| update cycle. Uses a tracker to prevent duplicate ObjectSet calls|
//|                                                                  |
//| Parameters:                                                       |
//|   objectName - Name of the object                                |
//|   props - Properties to set                                      |
//|   tracker - Tracks which properties have been set                |
//| Returns: true if all updates succeeded                           |
//+------------------------------------------------------------------+
bool TrackedUpdateLineProperties(const string objectName,
                                 const SLineObjectProperties &props,
                                 SPropertySetTracker &tracker) {
    bool success = true;
    
    // Requirement 8.5: Track and prevent redundant property calls
    // Only set each property once per update cycle
    
    if(!tracker.priceSet) {
        success = success && ObjectSetDouble(0, objectName, OBJPROP_PRICE, props.price);
        tracker.priceSet = true;
    }
    
    if(!tracker.colorSet) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_COLOR, props.lineColor);
        tracker.colorSet = true;
    }
    
    if(!tracker.styleSet) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_STYLE, props.style);
        tracker.styleSet = true;
    }
    
    if(!tracker.widthSet) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_WIDTH, props.width);
        tracker.widthSet = true;
    }
    
    if(!tracker.tooltipSet) {
        success = success && ObjectSetString(0, objectName, OBJPROP_TOOLTIP, props.tooltip);
        tracker.tooltipSet = true;
    }
    
    if(!tracker.selectableSet) {
        success = success && ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, props.selectable);
        tracker.selectableSet = true;
    }
    
    return success;
}

//+------------------------------------------------------------------+
