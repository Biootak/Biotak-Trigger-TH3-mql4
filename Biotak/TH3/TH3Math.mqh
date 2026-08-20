//+------------------------------------------------------------------+
//| TH3/TH3Math.mqh                                                  |
//| PURE TH3 math: wave analysis, point D, snapping, angles,        |
//| consolidation, rest candles, fib deviation.                     |
//| No chart-object access - only price/time inputs + built-ins.    |
//| Extracted verbatim (logic) from the old TH3Tool.mqh monolith.   |
//+------------------------------------------------------------------+
#ifndef TH3_MATH_MQH
#define TH3_MATH_MQH
#property strict

//+------------------------------------------------------------------+
//| Get Cached Daily ATR (performance optimization)                  |
//+------------------------------------------------------------------+
double GetCachedDailyATR()
{
    static double cachedATR = 0;
    static int cachedBar = -1;

    int currentBar = iBars(NULL, PERIOD_D1);

    if(currentBar != cachedBar || IsZero(cachedATR, EPSILON_PRICE)) {
        double atrValue = iATR(NULL, PERIOD_D1, 14, 0);
        cachedBar = currentBar;

        double pipSize = GetCachedPipSize();
        double minATR = pipSize * 10;  // Minimum 10 pips
        if(atrValue == EMPTY_VALUE || IsZero(atrValue, EPSILON_PRICE) || atrValue < minATR) {
            // Fallback: average range of last 20 daily bars
            double avgRange = 0;
            int validBars = 0;
            for(int i = 1; i <= 20; i++) {
                double high = iHigh(NULL, PERIOD_D1, i);
                double low = iLow(NULL, PERIOD_D1, i);
                if(high != EMPTY_VALUE && low != EMPTY_VALUE && high > low) {
                    avgRange += (high - low);
                    validBars++;
                }
            }
            cachedATR = (validBars > 0) ? (avgRange / validBars) : pipSize * 100;  // default 100 pips
        } else {
            cachedATR = atrValue;
        }
    }

    return cachedATR;
}

//+------------------------------------------------------------------+
//| Snap a price to the nearest OHLC of a bar (if within threshold)  |
//+------------------------------------------------------------------+
double SnapToOHLC(datetime barTime, double price, double pipSize)
{
    if(pipSize <= 0) pipSize = GetCachedPipSize();
    if(pipSize <= 0) return price;
    int barIndex = iBarShift(Symbol(), Period(), barTime);
    if(barIndex < 0) return price;
    double ohlc[4];
    ohlc[0] = iHigh(Symbol(), 0, barIndex);
    ohlc[1] = iLow(Symbol(), 0, barIndex);
    ohlc[2] = iClose(Symbol(), 0, barIndex);
    ohlc[3] = iOpen(Symbol(), 0, barIndex);
    double minDist = DBL_MAX;
    double snapped = price;
    for(int i = 0; i < 4; i++) {
        double dist = MathAbs(price - ohlc[i]) / pipSize;
        if(dist < minDist) {
            minDist = dist;
            snapped = ohlc[i];
        }
    }
    return (minDist <= TH3_SNAP_THRESHOLD_PIPS) ? snapped : price;
}

//+------------------------------------------------------------------+
//| Calculate Wave Angle (Gann angle, degrees 0-90)                  |
//+------------------------------------------------------------------+
double CalculateWaveAngle(datetime tStart, double pStart, datetime tEnd, double pEnd)
{
    if(tEnd <= tStart) {
        Print("TH3 Math: CalculateWaveAngle - Invalid time range");
        return 0;
    }
    if(pStart <= 0 || pEnd <= 0) {
        Print("TH3 Math: CalculateWaveAngle - Invalid prices");
        return 0;
    }

    double priceChange = MathAbs(pEnd - pStart);
    int timeChangeMinutes = (int)((tEnd - tStart) / 60);
    if(timeChangeMinutes <= 0) timeChangeMinutes = 1;

    double pipSize = GetCachedPipSize();
    double priceInPips = priceChange / pipSize;

    double dailyATR = GetCachedDailyATR();
    double minATR = pipSize * 10;
    if(dailyATR <= 0 || dailyATR < minATR) {
        double avgRange = 0;
        for(int i = 1; i <= 20; i++) {
            avgRange += (iHigh(NULL, PERIOD_D1, i) - iLow(NULL, PERIOD_D1, i));
        }
        dailyATR = avgRange / 20.0;
    }

    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0; // pips per minute
    if(referenceSpeed <= 0) referenceSpeed = 0.1;

    double actualSpeed = priceInPips / timeChangeMinutes;
    double speedRatio = actualSpeed / referenceSpeed;

    double angle = MathArctan(speedRatio) * 180.0 / M_PI;

    if(angle != angle) angle = 0;  // NaN check
    if(angle < 0) angle = 0;
    if(angle > 90) angle = 90;

    return angle;
}

//+------------------------------------------------------------------+
//| Angle thresholds + rest-candle constants                         |
//+------------------------------------------------------------------+
#define ANGLE_SPIKE_THRESHOLD 80.0
#define ANGLE_STRONG_THRESHOLD 55.0
#define ANGLE_BALANCED_THRESHOLD 40.0
#define ANGLE_SLOW_THRESHOLD 25.0

#define REST_SPIKE_BASE 3
#define REST_SPIKE_MAX 4
#define REST_STRONG_BASE 7
#define REST_STRONG_MAX 9
#define REST_BALANCED_BASE 15
#define REST_BALANCED_MAX 17
#define REST_SLOW_BASE 26
#define REST_SLOW_MAX 33
#define REST_VERY_SLOW_BASE 33
#define REST_VERY_SLOW_MAX 50

#define MAX_MOVEMENT_CANDLES 10000
#define MAX_REST_CANDLES 1000

//+------------------------------------------------------------------+
//| WaveAnalysis struct - result of AnalyzeThreeWaves               |
//| (declared early: referenced by CalculateConsolidationFactor)     |
//+------------------------------------------------------------------+
struct WaveAnalysis {
    double XA_Distance;
    double AB_Distance;
    double BC_Distance;

    int XA_Minutes;
    int AB_Minutes;
    int BC_Minutes;

    double XA_Speed;
    double AB_Speed;
    double BC_Speed;

    double XA_Angle;
    double AB_Angle;
    double BC_Angle;

    double AB_XA_Ratio;
    double BC_AB_Ratio;

    double AB_XA_TimeRatio;
    double BC_AB_TimeRatio;

    double AB_XA_SpeedRatio;
    double BC_AB_SpeedRatio;

    double XA_to_AB_Acceleration;
    double AB_to_BC_Acceleration;

    double XA_RawStrength;
    double AB_RawStrength;
    double BC_RawStrength;
    double XA_WeightedStrength;
    double AB_WeightedStrength;
    double BC_WeightedStrength;
    double XA_RelativeStrength;
    double AB_RelativeStrength;
    double BC_RelativeStrength;

    bool isImpulsive;
    bool isCorrectional;
    double avgSpeed;
    double speedConsistency;
    double timeSymmetry;
};

//+------------------------------------------------------------------+
//| Required rest candles based on movement angle                    |
//+------------------------------------------------------------------+
int CalculateRequiredRestCandles(double angle, int movementCandles)
{
    if(movementCandles < 0) movementCandles = 0;
    if(movementCandles > MAX_MOVEMENT_CANDLES) movementCandles = MAX_MOVEMENT_CANDLES;

    if(angle < 0) angle = 0;
    if(angle > 90) angle = 90;

    int restCandles = 0;

    if(angle >= ANGLE_SPIKE_THRESHOLD) {
        double temp = movementCandles * 0.1;
        if(temp > INT_MAX - REST_SPIKE_BASE) {
            restCandles = REST_SPIKE_MAX;
        } else {
            restCandles = REST_SPIKE_BASE + (int)temp;
            if(restCandles > REST_SPIKE_MAX) restCandles = REST_SPIKE_MAX;
        }
    }
    else if(angle >= ANGLE_STRONG_THRESHOLD) {
        double temp = movementCandles * 0.15;
        if(temp > INT_MAX - REST_STRONG_BASE) {
            restCandles = REST_STRONG_MAX;
        } else {
            restCandles = REST_STRONG_BASE + (int)temp;
            if(restCandles > REST_STRONG_MAX) restCandles = REST_STRONG_MAX;
        }
    }
    else if(angle >= ANGLE_BALANCED_THRESHOLD) {
        double temp = movementCandles * 0.2;
        if(temp > INT_MAX - REST_BALANCED_BASE) {
            restCandles = REST_BALANCED_MAX;
        } else {
            restCandles = REST_BALANCED_BASE + (int)temp;
            if(restCandles > REST_BALANCED_MAX) restCandles = REST_BALANCED_MAX;
        }
    }
    else if(angle >= ANGLE_SLOW_THRESHOLD) {
        double temp = movementCandles * 0.25;
        if(temp > INT_MAX - REST_SLOW_BASE) {
            restCandles = REST_SLOW_MAX;
        } else {
            restCandles = REST_SLOW_BASE + (int)temp;
            if(restCandles > REST_SLOW_MAX) restCandles = REST_SLOW_MAX;
        }
    }
    else {
        double temp = movementCandles * 0.3;
        if(temp > INT_MAX - REST_VERY_SLOW_BASE) {
            restCandles = REST_VERY_SLOW_MAX;
        } else {
            restCandles = REST_VERY_SLOW_BASE + (int)temp;
            if(restCandles > REST_VERY_SLOW_MAX) restCandles = REST_VERY_SLOW_MAX;
        }
    }

    if(restCandles < 0) restCandles = 0;
    if(restCandles > MAX_REST_CANDLES) restCandles = MAX_REST_CANDLES;

    return restCandles;
}

//+------------------------------------------------------------------+
//| Determine reference TH% closest to the wave size                |
//+------------------------------------------------------------------+
double DetermineReferenceTimeframe(double waveDistance, double currentTH)
{
    double waveSizeInTH = (currentTH > 0) ? (waveDistance / currentTH) : 0;
    double targetTHMultiplier = waveSizeInTH / 3.0;

    int arraySize = ArraySize(MODIFIED_FRACTAL_PERCENTAGES);
    double closestTH = MODIFIED_FRACTAL_PERCENTAGES[0];
    double minDiff = 1000000.0;

    for(int i = 0; i < arraySize; i++) {
        double testTH = MODIFIED_FRACTAL_PERCENTAGES[i];
        double diff = MathAbs(testTH - (currentTH * targetTHMultiplier));
        if(diff < minDiff) {
            minDiff = diff;
            closestTH = testTH;
        }
    }

    return closestTH;
}

//+------------------------------------------------------------------+
//| Consolidation factor (Gann-based: angle + rest candles)          |
//+------------------------------------------------------------------+
double CalculateConsolidationFactor(datetime tA, datetime tB, datetime tC,
                                     WaveAnalysis &waves)
{
    double angleAB = waves.AB_Angle;

    int barA = iBarShift(NULL, 0, tA);
    int barB = iBarShift(NULL, 0, tB);
    int barC = iBarShift(NULL, 0, tC);

    int AB_Candles = MathAbs(barA - barB);
    int BC_Candles = MathAbs(barB - barC);

    if(AB_Candles < 1) AB_Candles = 1;
    if(BC_Candles < 1) BC_Candles = 1;

    int requiredRestCandles = CalculateRequiredRestCandles(angleAB, AB_Candles);
    double restRatio = (double)BC_Candles / requiredRestCandles;

    double consolidationFactor = 0.0;
    if(restRatio < 0.3) {
        consolidationFactor = 0.9;
    }
    else if(restRatio < 0.6) {
        consolidationFactor = 0.7;
    }
    else if(restRatio < 1.0) {
        consolidationFactor = 0.4;
    }
    else if(restRatio < 1.5) {
        consolidationFactor = 0.1;
    }
    else {
        consolidationFactor = 0.0;
    }

    if(angleAB >= 80) {
        consolidationFactor *= 1.3;
    }
    else if(angleAB >= 55) {
        consolidationFactor *= 1.15;
    }

    if(consolidationFactor > 1.0) consolidationFactor = 1.0;
    if(consolidationFactor < 0.0) consolidationFactor = 0.0;

    return consolidationFactor;
}

//+------------------------------------------------------------------+
//| Movement speed ratio (speed vs ATR-based reference)              |
//+------------------------------------------------------------------+
double CalculateMovementSpeed(datetime tA, double pA, datetime tB, double pB)
{
    double priceChange = MathAbs(pB - pA);
    int timeChangeMinutes = (int)((tB - tA) / 60);
    if(timeChangeMinutes <= 0) return 1.0;

    double pipSize = GetCachedPipSize();
    double priceInPips = priceChange / pipSize;
    double speed = priceInPips / timeChangeMinutes;

    double dailyATR = GetCachedDailyATR();
    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0;

    if(referenceSpeed <= 0) referenceSpeed = 0.1;

    double speedRatio = speed / referenceSpeed;
    if(speedRatio < 0.1) speedRatio = 0.1;
    if(speedRatio > 10.0) speedRatio = 10.0;

    return speedRatio;
}

//+------------------------------------------------------------------+
//| Time symmetry factor (1.0 = perfect AB/BC time symmetry)         |
//+------------------------------------------------------------------+
double CalculateTimeSymmetry(datetime tA, datetime tB, datetime tC)
{
    int timeAB = (int)((tB - tA) / 60);
    int timeBC = (int)((tC - tB) / 60);

    if(timeAB <= 0 || timeBC <= 0) return 1.0;

    double ratio = 0;
    if(timeAB > 0 && timeBC > 0) {
        ratio = (timeAB > timeBC) ? ((double)timeBC / timeAB) : ((double)timeAB / timeBC);
    }

    return ratio;
}

//+------------------------------------------------------------------+
//| Analyze three waves X->A->B->C (pure, chart-free math)           |
//+------------------------------------------------------------------+
WaveAnalysis AnalyzeThreeWaves(datetime tX, double pX, datetime tA, double pA,
                                datetime tB, double pB, datetime tC, double pC)
{
    WaveAnalysis analysis;
    double pipSize = GetCachedPipSize();

    if(!(tX < tA && tA < tB && tB < tC)) {
        Print("TH3 Math: AnalyzeThreeWaves - Invalid time ordering (X < A < B < C required)");
        analysis.XA_Distance = 0;
        analysis.AB_Distance = 0;
        analysis.BC_Distance = 0;
        analysis.XA_Minutes = 1;
        analysis.AB_Minutes = 1;
        analysis.BC_Minutes = 1;
        analysis.XA_Speed = 0;
        analysis.AB_Speed = 0;
        analysis.BC_Speed = 0;
        analysis.XA_Angle = 0;
        analysis.AB_Angle = 0;
        analysis.BC_Angle = 0;
        analysis.AB_XA_Ratio = 1;
        analysis.BC_AB_Ratio = 1;
        analysis.AB_XA_TimeRatio = 1;
        analysis.BC_AB_TimeRatio = 1;
        analysis.AB_XA_SpeedRatio = 1;
        analysis.BC_AB_SpeedRatio = 1;
        analysis.isImpulsive = false;
        analysis.isCorrectional = false;
        analysis.avgSpeed = 0;
        analysis.speedConsistency = 0;
        analysis.timeSymmetry = 0;
        return analysis;
    }

    analysis.XA_Distance = MathAbs(pA - pX);
    analysis.AB_Distance = MathAbs(pB - pA);
    analysis.BC_Distance = MathAbs(pC - pB);

    analysis.XA_Minutes = (int)((tA - tX) / 60);
    analysis.AB_Minutes = (int)((tB - tA) / 60);
    analysis.BC_Minutes = (int)((tC - tB) / 60);

    if(analysis.XA_Minutes <= 0) analysis.XA_Minutes = 1;
    if(analysis.AB_Minutes <= 0) analysis.AB_Minutes = 1;
    if(analysis.BC_Minutes <= 0) analysis.BC_Minutes = 1;

    if(MathAbs(analysis.AB_Minutes) < 0.001) {
        analysis.AB_Speed = 0;
    } else {
        analysis.AB_Speed = (analysis.AB_Distance / pipSize) / analysis.AB_Minutes;
    }

    if(MathAbs(analysis.XA_Minutes) < 0.001) {
        analysis.XA_Speed = 0;
    } else {
        analysis.XA_Speed = (analysis.XA_Distance / pipSize) / analysis.XA_Minutes;
    }

    if(MathAbs(analysis.BC_Minutes) < 0.001) {
        analysis.BC_Speed = 0;
    } else {
        analysis.BC_Speed = (analysis.BC_Distance / pipSize) / analysis.BC_Minutes;
    }

    analysis.XA_Angle = CalculateWaveAngle(tX, pX, tA, pA);
    analysis.AB_Angle = CalculateWaveAngle(tA, pA, tB, pB);
    analysis.BC_Angle = CalculateWaveAngle(tB, pB, tC, pC);

    analysis.AB_XA_Ratio = (analysis.XA_Distance > 0) ? (analysis.AB_Distance / analysis.XA_Distance) : 1.0;
    analysis.BC_AB_Ratio = (analysis.AB_Distance > 0) ? (analysis.BC_Distance / analysis.AB_Distance) : 1.0;

    analysis.AB_XA_TimeRatio = (double)analysis.AB_Minutes / analysis.XA_Minutes;
    analysis.BC_AB_TimeRatio = (double)analysis.BC_Minutes / analysis.AB_Minutes;

    analysis.AB_XA_SpeedRatio = (analysis.XA_Speed > 0) ? (analysis.AB_Speed / analysis.XA_Speed) : 1.0;
    analysis.BC_AB_SpeedRatio = (analysis.AB_Speed > 0) ? (analysis.BC_Speed / analysis.AB_Speed) : 1.0;

    // Acceleration (speed change per minute)
    double velocityChange_XA_AB = analysis.AB_Speed - analysis.XA_Speed;
    analysis.XA_to_AB_Acceleration = velocityChange_XA_AB / MathMax(analysis.AB_Minutes, 1);

    double velocityChange_AB_BC = analysis.BC_Speed - analysis.AB_Speed;
    analysis.AB_to_BC_Acceleration = velocityChange_AB_BC / MathMax(analysis.BC_Minutes, 1);

    if(analysis.XA_to_AB_Acceleration != analysis.XA_to_AB_Acceleration) analysis.XA_to_AB_Acceleration = 0;
    if(analysis.AB_to_BC_Acceleration != analysis.AB_to_BC_Acceleration) analysis.AB_to_BC_Acceleration = 0;

    // Raw strength = velocity (pips/min)
    analysis.XA_RawStrength = (analysis.XA_Distance / pipSize) / MathMax(analysis.XA_Minutes, 1);
    analysis.AB_RawStrength = (analysis.AB_Distance / pipSize) / MathMax(analysis.AB_Minutes, 1);
    analysis.BC_RawStrength = (analysis.BC_Distance / pipSize) / MathMax(analysis.BC_Minutes, 1);

    if(analysis.XA_RawStrength != analysis.XA_RawStrength) analysis.XA_RawStrength = 0;
    if(analysis.AB_RawStrength != analysis.AB_RawStrength) analysis.AB_RawStrength = 0;
    if(analysis.BC_RawStrength != analysis.BC_RawStrength) analysis.BC_RawStrength = 0;

    // Weighted strength = raw * sin(angle)
    double angleWeight_XA = MathSin(analysis.XA_Angle * M_PI / 180.0);
    double angleWeight_AB = MathSin(analysis.AB_Angle * M_PI / 180.0);
    double angleWeight_BC = MathSin(analysis.BC_Angle * M_PI / 180.0);

    analysis.XA_WeightedStrength = analysis.XA_RawStrength * angleWeight_XA;
    analysis.AB_WeightedStrength = analysis.AB_RawStrength * angleWeight_AB;
    analysis.BC_WeightedStrength = analysis.BC_RawStrength * angleWeight_BC;

    if(analysis.XA_WeightedStrength != analysis.XA_WeightedStrength) analysis.XA_WeightedStrength = 0;
    if(analysis.AB_WeightedStrength != analysis.AB_WeightedStrength) analysis.AB_WeightedStrength = 0;
    if(analysis.BC_WeightedStrength != analysis.BC_WeightedStrength) analysis.BC_WeightedStrength = 0;

    // Relative strength vs ATR reference
    double dailyATR = GetCachedDailyATR();
    double dailyATRInPips = dailyATR / pipSize;
    double referenceSpeed = dailyATRInPips / 1440.0;
    if(referenceSpeed <= 0) referenceSpeed = 0.1;

    analysis.XA_RelativeStrength = analysis.XA_WeightedStrength / referenceSpeed;
    analysis.AB_RelativeStrength = analysis.AB_WeightedStrength / referenceSpeed;
    analysis.BC_RelativeStrength = analysis.BC_WeightedStrength / referenceSpeed;

    if(analysis.XA_RelativeStrength != analysis.XA_RelativeStrength) analysis.XA_RelativeStrength = 0;
    if(analysis.AB_RelativeStrength != analysis.AB_RelativeStrength) analysis.AB_RelativeStrength = 0;
    if(analysis.BC_RelativeStrength != analysis.BC_RelativeStrength) analysis.BC_RelativeStrength = 0;

    // Average speed + consistency (std-dev based)
    analysis.avgSpeed = (analysis.XA_Speed + analysis.AB_Speed + analysis.BC_Speed) / 3.0;

    double speedVariance = MathPow(analysis.XA_Speed - analysis.avgSpeed, 2) +
                          MathPow(analysis.AB_Speed - analysis.avgSpeed, 2) +
                          MathPow(analysis.BC_Speed - analysis.avgSpeed, 2);
    double speedStdDev = MathSqrt(speedVariance / 3.0);
    analysis.speedConsistency = (analysis.avgSpeed > 0) ? (1.0 - MathMin(speedStdDev / analysis.avgSpeed, 1.0)) : 0.5;

    if(analysis.speedConsistency != analysis.speedConsistency) analysis.speedConsistency = 0.5;

    double avgSpeedRatio = analysis.avgSpeed / referenceSpeed;
    analysis.isImpulsive = (avgSpeedRatio > 1.2);
    analysis.isCorrectional = (avgSpeedRatio < 0.8);

    analysis.timeSymmetry = CalculateTimeSymmetry(tA, tB, tC);

    return analysis;
}

//+------------------------------------------------------------------+
//| Frequency search result struct                                   |
//+------------------------------------------------------------------+
struct FrequencySearchResult {
    double frequency;
    int frequencyIndex;
    int targetStep;
    double errorPercent;
    double calculatedD;
    double targetPrice;
    double errorPips;
    double gannAngle;
    double angleWeight;
    double timeSymmetry;
    double totalScore;
};

//+------------------------------------------------------------------+
//| Frequency error for AB=CD (0 = perfect match)                    |
//+------------------------------------------------------------------+
double CalculateFrequencyError(double pA, double pB, double pC,
                               double frequency, int targetStep,
                               double &calculatedD, double &targetPrice)
{
    double AB_Distance = MathAbs(pB - pA);
    double pipSize = GetCachedPipSize();
    double minDistance = pipSize * 10;

    if(AB_Distance < minDistance) {
        calculatedD = 0.0;
        targetPrice = 0.0;
        return 999.99;
    }

    bool isBullish = (pB > pA);
    double baseUnit = AB_Distance * (frequency / 100.0);

    double pD;
    if(isBullish) {
        pD = pC + AB_Distance;
    } else {
        pD = pC - AB_Distance;
    }
    calculatedD = pD;

    double stepPrice;
    if(isBullish) {
        stepPrice = pC + (targetStep * baseUnit);
    } else {
        stepPrice = pC - (targetStep * baseUnit);
    }
    targetPrice = stepPrice;

    double error = MathAbs(pD - stepPrice);

    double errorPercent = 0;
    if(MathAbs(AB_Distance) > 0.000001) {
        errorPercent = (error / AB_Distance) * 100.0;
    }

    return errorPercent;
}

//+------------------------------------------------------------------+
//| Minimum deviation from standard Fibonacci ratios                 |
//+------------------------------------------------------------------+
double CalculateFibonacciDeviation(double ratio)
{
    double fibRatios[9] = {0.236, 0.382, 0.5, 0.618, 0.786, 1.0, 1.272, 1.618, 2.618};

    double minDeviation = 1000.0;
    for(int i = 0; i < 9; i++) {
        double deviation = MathAbs(ratio - fibRatios[i]);
        if(deviation < minDeviation) {
            minDeviation = deviation;
        }
    }

    return minDeviation;
}

//+------------------------------------------------------------------+
//| Calculate point D from A, B, C (AB=CD rule)                      |
//+------------------------------------------------------------------+
bool CalculateABCDPointD(datetime tA, double pA, datetime tB, double pB,
                         datetime tC, double pC, datetime &tD, double &pD)
{
    if(tA <= 0 || tB <= 0 || tC <= 0) return false;
    if(pA <= 0 || pB <= 0 || pC <= 0) return false;
    if(!(tA < tB && tB < tC)) return false;

    double AB_Distance = MathAbs(pB - pA);
    double minDistance = Point * ABCD_MIN_DISTANCE_POINTS;
    if(AB_Distance < minDistance) return false;

    bool isBullish = (pB > pA);
    double CD_Distance = AB_Distance;

    if(isBullish) {
        pD = pC + CD_Distance;
    } else {
        pD = pC - CD_Distance;
    }

    int BC_Bars = iBarShift(NULL, 0, tB) - iBarShift(NULL, 0, tC);
    if(BC_Bars < 1) BC_Bars = 1;

    int CD_Bars = BC_Bars;
    int barD = iBarShift(NULL, 0, tC) - CD_Bars;
    if(barD < 0) barD = 0;

    tD = iTime(NULL, 0, barD);
    if(tD <= 0) tD = tC + (tC - tB);

    if(pD <= 0) return false;

    return true;
}

#endif // TH3_MATH_MQH
