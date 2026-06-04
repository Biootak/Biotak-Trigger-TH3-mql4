#ifndef PROPERTY_CHANGE_DETECTOR_MQH
#define PROPERTY_CHANGE_DETECTOR_MQH

#property copyright "Biotak"
#property strict

struct SPropertyChangeResult {
    bool priceChanged;
    bool colorChanged;
    bool styleChanged;
    bool widthChanged;
    bool anyChanged;
};

bool HasPriceChanged(const double oldPrice, const double newPrice) {
    if(oldPrice == 0.0 && newPrice == 0.0) {
        return false;
    }
    double diff = MathAbs(oldPrice - newPrice);
    return diff > EPSILON_PRICE;
}

bool HasColorChanged(const color oldColor, const color newColor) {
    return oldColor != newColor;
}

bool HasStyleChanged(const int oldStyle, const int newStyle) {
    return oldStyle != newStyle;
}

bool HasWidthChanged(const int oldWidth, const int newWidth) {
    return oldWidth != newWidth;
}

bool HasAnyPropertyChanged(const double oldPrice, const double newPrice,
                           const color oldColor, const color newColor,
                           const int oldStyle, const int newStyle,
                           const int oldWidth, const int newWidth) {
    if(HasPriceChanged(oldPrice, newPrice)) return true;
    if(HasColorChanged(oldColor, newColor)) return true;
    if(HasStyleChanged(oldStyle, newStyle)) return true;
    if(HasWidthChanged(oldWidth, newWidth)) return true;
    return false;
}

SPropertyChangeResult DetectPropertyChanges(const double oldPrice, const double newPrice,
                                            const color oldColor, const color newColor,
                                            const int oldStyle, const int newStyle,
                                            const int oldWidth, const int newWidth) {
    SPropertyChangeResult result;
    result.priceChanged = HasPriceChanged(oldPrice, newPrice);
    result.colorChanged = HasColorChanged(oldColor, newColor);
    result.styleChanged = HasStyleChanged(oldStyle, newStyle);
    result.widthChanged = HasWidthChanged(oldWidth, newWidth);
    result.anyChanged = result.priceChanged || result.colorChanged || 
                        result.styleChanged || result.widthChanged;
    return result;
}

SPropertyChangeResult DetectPropertyChangesFromCache(const SObjectCacheEntry &cached,
                                                     const double newPrice,
                                                     const color newColor,
                                                     const int newStyle,
                                                     const int newWidth) {
    return DetectPropertyChanges(cached.lastPrice, newPrice,
                                 cached.lastColor, newColor,
                                 cached.lastStyle, newStyle,
                                 cached.lastWidth, newWidth);
}

bool HasAnyPropertyChangedFromCache(const SObjectCacheEntry &cached,
                                    const double newPrice,
                                    const color newColor,
                                    const int newStyle,
                                    const int newWidth) {
    return HasAnyPropertyChanged(cached.lastPrice, newPrice,
                                 cached.lastColor, newColor,
                                 cached.lastStyle, newStyle,
                                 cached.lastWidth, newWidth);
}

bool HasAnyPropertyChangedWithCacheLookup(const string objectName,
                                          const double newPrice,
                                          const color newColor,
                                          const int newStyle,
                                          const int newWidth) {
    SObjectCacheEntry cached;
    if(!CacheGetObject(objectName, cached)) {
        return true;  // Missing cache entry triggers full update
    }
    return HasAnyPropertyChangedFromCache(cached, newPrice, newColor, newStyle, newWidth);
}

#endif // PROPERTY_CHANGE_DETECTOR_MQH
