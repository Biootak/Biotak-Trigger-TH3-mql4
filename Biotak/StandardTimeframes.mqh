  #property strict

#ifndef STANDARD_TIMEFRAMES_MQH
#define STANDARD_TIMEFRAMES_MQH
double CalculateStandardPercentage(const int timeInMinutes) {
    if(timeInMinutes <= 0) return 0.0;
    // PERF: Cache results   input is one of 8 fixed values (1, 5, 15, 60, 240, 1440, 10080, 43200)
    // MathLog/MathPow are expensive, result is purely a function of timeInMinutes and never changes
    static int    s_cachedMinutes[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    static double s_cachedResults[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    static int    s_cachedCount = 0;
    for(int c = 0; c < s_cachedCount; c++) {
        if(s_cachedMinutes[c] == timeInMinutes) return s_cachedResults[c];
    }
    int baseTimeMinutes = 1;
    //--- P-TH-17 (2026-10-29) — THE 66.66 BELONGS TO THE DAY, NOT TO THE 1024-MINUTE RUNG.
    //
    // This ladder is a sqrt law of the timeframe's minutes (2^(log4(min)) IS
    // sqrt(min)), and 66.66 is the professor's DAILY number — the APR table's
    // 66.66 is the day's ability, every other row is its fraction. The seed used
    // to be 2.083, picked so the value reached 66.66 at 1024 minutes, which is
    // the H17+M4 fractal rung and NOT a day: a day is 1440 minutes. Every
    // standard column therefore came out sqrt(1440/1024) = 1.1858x too large, so
    // the strip disagreed with the ladder drawn on the chart of the SAME
    // timeframe (D1 read 318.2 pips where the ladder's own step was 268).
    //
    // Measured against the master's strip on one XAUUSD H1 chart, one anchor
    // price, eight columns: M1 7, M5 16, M15 27, H1 55, H4 109, D1 268, W1 709,
    // MN1 1468. All eight sit on 66.66 x sqrt(min/1440) to within a pip, and this
    // seed reproduces them: 66.66 / sqrt(1440) = 1.756646.
    double basePercentage = 1.756646;  // 66.66% at 1440 min (the day)
    double result;
    if(timeInMinutes <= baseTimeMinutes) {
        result = basePercentage / 100.0;
    } else {
        double timeRatio = (double)timeInMinutes / baseTimeMinutes;
        double doublingFactor = MathLog(timeRatio) / MathLog(4.0);
        result = (basePercentage * MathPow(2.0, doublingFactor)) / 100.0;
    }
    // Store in cache if space available
    if(s_cachedCount < 8) {
        s_cachedMinutes[s_cachedCount] = timeInMinutes;
        s_cachedResults[s_cachedCount] = result;
        s_cachedCount++;
    }
    return result;
}

#endif // STANDARD_TIMEFRAMES_MQH