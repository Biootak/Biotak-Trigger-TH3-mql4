#property strict

double CalculatePercentage(const int timeInMinutes) {
    if(timeInMinutes<=0) return 0.0;
    int baseTimeMinutes=1;
    double basePercentage=2.083;  // Adjusted so 1024min = 66.66%
    if (timeInMinutes <= baseTimeMinutes) return basePercentage / 100.0;
    else {
        double timeRatio=(double)timeInMinutes/baseTimeMinutes;
        double doublingFactor=MathLog(timeRatio)/MathLog(4.0);
        return (basePercentage*MathPow(2.0,doublingFactor))/100.0;
    }
}