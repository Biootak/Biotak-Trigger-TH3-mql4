#property strict

bool UpdateHistoricalValues() {
    // Only update if necessary
    datetime currentTime = TimeCurrent();
    if(currentTime - g_lastHistoricalUpdate < 3600 && g_initialized) return true;

    // OPTIMIZATION: Use dynamic arrays and ensure cleanup
    double highArray[], lowArray[];
    
    // MT4 approach: User has full control via input parameters
    // inpHistoricalPeriods = 0 means use all available bars
    // Otherwise use the specified number of periods
    int totalBars = inpHistoricalPeriods == 0 ? 
                   iBars(Symbol(), inpHistoricalTimeframe) : 
                   inpHistoricalPeriods;
    
    if(totalBars <= 0) {
        Print("UpdateHistoricalValues: Invalid totalBars=", totalBars);
        return false;
    }

    // Resize arrays
    if(ArrayResize(highArray, totalBars) != totalBars || ArrayResize(lowArray, totalBars) != totalBars) {
        Print("UpdateHistoricalValues: Failed to resize arrays. Error: ", GetLastError());
        ArrayFree(highArray);
        ArrayFree(lowArray);
        return false;
    }

    // Use single error check for data copying
    int copiedHigh = CopyHigh(Symbol(), inpHistoricalTimeframe, 0, totalBars, highArray);
    int copiedLow = CopyLow(Symbol(), inpHistoricalTimeframe, 0, totalBars, lowArray);
    
    if(copiedHigh <= 0 || copiedLow <= 0) {
        Print("UpdateHistoricalValues: Failed to copy data. High=", copiedHigh, ", Low=", copiedLow);
        ArrayFree(highArray);
        ArrayFree(lowArray);
        return false;
    }

    // Optimize max/min calculation
    g_highestHigh = highArray[ArrayMaximum(highArray)];
    g_lowestLow = lowArray[ArrayMinimum(lowArray)];
    
    // MEMORY CLEANUP: Free temporary arrays immediately after use
    ArrayFree(highArray);
    ArrayFree(lowArray);
    
    if(g_highestHigh <= 0 || g_lowestLow <= 0) {
        Print("UpdateHistoricalValues: Invalid high/low values");
        return false;
    }
    
    g_lastHistoricalUpdate = currentTime;
    // g_thCache removed - matching MT5
    
    return true;
}

// Cache previous day prices
double GetPriceForPreviousDay(ENUM_APPLIED_PRICE priceType) {
    static datetime lastUpdate = 0;
    static double cachedPrices[6] = {0};
    
    datetime currentTime = TimeCurrent();
    if(currentTime-lastUpdate >= 86400 || lastUpdate==0) { // Update cache daily
        cachedPrices[0]=iClose(Symbol(),PERIOD_D1,1);
        cachedPrices[1]=iOpen(Symbol(),PERIOD_D1,1);
        cachedPrices[2]=iHigh(Symbol(),PERIOD_D1,1);
        cachedPrices[3]=iLow(Symbol(),PERIOD_D1,1);
        cachedPrices[4]=(cachedPrices[2]+cachedPrices[3])/2.0;
        cachedPrices[5]=(cachedPrices[2]+cachedPrices[3]+cachedPrices[0])/3.0;
        lastUpdate = currentTime;
    }
    
    switch(priceType) {
        case 1: return cachedPrices[1]; // Open
        case 2: return cachedPrices[2]; // High
        case 3: return cachedPrices[3]; // Low
        case 4: return cachedPrices[4]; // Median
        case 5: return cachedPrices[5]; // Typical
        case 0: default: return cachedPrices[0]; // Close
    }
    return EMPTY_VALUE;
}