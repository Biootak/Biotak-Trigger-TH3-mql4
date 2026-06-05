  #property strict

double CalculateStandardPercentage(const int timeInMinutes) {
    if(timeInMinutes <= 0) return 0.0;
    // PERF: Cache results   input is always one of 3 fixed values (1440, 10080, 43200)
    // MathLog/MathPow are expensive, result is purely a function of timeInMinutes and never changes
    static int    s_cachedMinutes[3] = {0, 0, 0};
    static double s_cachedResults[3] = {0, 0, 0};
    static int    s_cachedCount = 0;
    for(int c = 0; c < s_cachedCount; c++) {
        if(s_cachedMinutes[c] == timeInMinutes) return s_cachedResults[c];
    }
    int baseTimeMinutes = 1;
    double basePercentage = 2.083;  // Adjusted so 1024min = 66.66%
    double result;
    if(timeInMinutes <= baseTimeMinutes) {
        result = basePercentage / 100.0;
    } else {
        double timeRatio = (double)timeInMinutes / baseTimeMinutes;
        double doublingFactor = MathLog(timeRatio) / MathLog(4.0);
        result = (basePercentage * MathPow(2.0, doublingFactor)) / 100.0;
    }
    // Store in cache if space available
    if(s_cachedCount < 3) {
        s_cachedMinutes[s_cachedCount] = timeInMinutes;
        s_cachedResults[s_cachedCount] = result;
        s_cachedCount++;
    }
    return result;
}