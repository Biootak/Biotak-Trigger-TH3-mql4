  //+------------------------------------------------------------------+
//|                                          MarketHoursDetector.mqh |
//|                                                                  |
//|  Market hours detection for different market types              |
//|                                                                 |
//+------------------------------------------------------------------+
#ifndef MARKET_HOURS_DETECTOR_MQH
#define MARKET_HOURS_DETECTOR_MQH
#property copyright "Biotak"
#property strict

//+------------------------------------------------------------------+
//| Market Type Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_MARKET_TYPE
{
    MARKET_FOREX,      // Forex pairs (EUR/USD, GBP/USD, etc.)
    MARKET_METALS,     // Precious metals (XAU/USD, XAG/USD)
    MARKET_CRYPTO,     // Cryptocurrencies (BTC/USD, ETH/USD)
    MARKET_STOCKS,     // Stock indices and individual stocks
    MARKET_UNKNOWN     // Unknown market type
};

//+------------------------------------------------------------------+
//| Detect market type from symbol name                              |
//+------------------------------------------------------------------+
ENUM_MARKET_TYPE DetectMarketType(string symbol)
{
    // Remove any suffixes or prefixes
    string cleanSymbol = symbol;
    StringToUpper(cleanSymbol);
    
    // Check for metals (Gold, Silver)
    if(StringFind(cleanSymbol, "XAU") >= 0 || 
       StringFind(cleanSymbol, "GOLD") >= 0 ||
       StringFind(cleanSymbol, "XAG") >= 0 ||
       StringFind(cleanSymbol, "SILVER") >= 0)
    {
        return MARKET_METALS;
    }
    
    // Check for crypto
    if(StringFind(cleanSymbol, "BTC") >= 0 ||
       StringFind(cleanSymbol, "ETH") >= 0 ||
       StringFind(cleanSymbol, "USDT") >= 0 ||
       StringFind(cleanSymbol, "CRYPTO") >= 0)
    {
        return MARKET_CRYPTO;
    }
    
    // Check for common forex pairs
    string forexPairs[] = {
        "EUR", "GBP", "USD", "JPY", "CHF", "CAD", "AUD", "NZD"
    };
    
    int forexCount = 0;
    for(int i = 0; i < ArraySize(forexPairs); i++)
    {
        if(StringFind(cleanSymbol, forexPairs[i]) >= 0)
            forexCount++;
    }
    
    // If symbol contains 2 or more forex currencies, it's a forex pair
    if(forexCount >= 2)
        return MARKET_FOREX;
    
    // Check for stock indices
    if(StringFind(cleanSymbol, "US30") >= 0 ||
       StringFind(cleanSymbol, "NAS100") >= 0 ||
       StringFind(cleanSymbol, "SPX") >= 0 ||
       StringFind(cleanSymbol, "DAX") >= 0 ||
       StringFind(cleanSymbol, "FTSE") >= 0)
    {
        return MARKET_STOCKS;
    }
    
    // Default to unknown
    return MARKET_UNKNOWN;
}

//+------------------------------------------------------------------+
//| Get start of trading day for symbol                              |
//| Returns hour (0-23) in GMT                                       |
//+------------------------------------------------------------------+
int GetTradingDayStartHour(string symbol)
{
    ENUM_MARKET_TYPE marketType = DetectMarketType(symbol);
    
    switch(marketType)
    {
        case MARKET_FOREX:
        case MARKET_METALS:
            // Forex and Metals start at 22:00 GMT (Sunday night)
            return 22;
            
        case MARKET_CRYPTO:
            // Crypto is 24/7, but we use 00:00 GMT for consistency
            return 0;
            
        case MARKET_STOCKS:
        case MARKET_UNKNOWN:
        default:
            // Stocks and unknown start at 00:00 GMT
            return 0;
    }
}

//+------------------------------------------------------------------+
//| Get start of trading day datetime                                |
//| For Forex/Metals: returns 22:00 GMT of previous day             |
//| For others: returns 00:00 GMT of current day                     |
//+------------------------------------------------------------------+
datetime GetStartOfTradingDay(string symbol, datetime currentTime)
{
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    
    int startHour = GetTradingDayStartHour(symbol);
    
    // Set to start hour
    dt.hour = startHour;
    dt.min = 0;
    dt.sec = 0;
    
    datetime startTime = StructToTime(dt);
    
    // If start hour is 22:00 and current time is before 22:00,
    // we need to go back to previous day's 22:00
    if(startHour == 22 && currentTime < startTime)
    {
        // Go back one day
        startTime -= 24 * 60 * 60;
    }
    
    return startTime;
}

//+------------------------------------------------------------------+
//| Get market type name as string                                   |
//+------------------------------------------------------------------+
string GetMarketTypeName(ENUM_MARKET_TYPE marketType)
{
    switch(marketType)
    {
        case MARKET_FOREX:   return "FOREX";
        case MARKET_METALS:  return "METALS";
        case MARKET_CRYPTO:  return "CRYPTO";
        case MARKET_STOCKS:  return "STOCKS";
        default:             return "UNKNOWN";
    }
}
// TestMarketDetection removed for production build optimization

#endif // MARKET_HOURS_DETECTOR_MQH
