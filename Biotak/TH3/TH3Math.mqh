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

// The skeleton axis types live in TH3Types.mqh and are declared before this file
// by every host (TH3PatternStore.mqh includes Types first). Including it here too
// keeps this file compilable on its own: the axis-measuring functions at the
// bottom return a TH3Skeleton, so they cannot be declared without it.
#include "TH3Types.mqh"
#include "TH3Pivots.mqh"   // the course's own six-condition pivot + fractal TF chain (PDF pp. 3, 6-7, 50)

//+------------------------------------------------------------------+
//| Get Cached Daily ATR (performance optimization)                  |
//|                                                                  |
//| P-TH3-STEP-01 (2026-09-19) — THE STRUCTURE ATR READS COMPLETED   |
//| DAYS. Shift 0 on D1 is the FORMING day: its range is partial     |
//| until the day closes, so the ATR(14) it feeds is biased low, and |
//| the per-day cache freeze (invalidated only when a new daily bar  |
//| appears) then locks the biased value in for the whole day -      |
//| measured over the broker's own daily series the bias is -5.8% at |
//| h02 falling to -0.2% at h22, so a continuously-attached chart    |
//| carried ~6% less structure for every step the skeleton derives   |
//| (S enters the candidates with weight 3 and -2). The function's   |
//| own fallback (the 20-bar average below) already reads bars 1..20 |
//| - completed days only - so the primary path now agrees with it:  |
//| shift 1. With shift 1 the cached value is constant within the    |
//| day, which makes the per-day freeze correct instead of harmful.  |
//+------------------------------------------------------------------+
double GetCachedDailyATR()
{
    static double cachedATR = 0;
    static int cachedBar = -1;

    int currentBar = iBars(NULL, PERIOD_D1);

    if(currentBar != cachedBar || IsZero(cachedATR, EPSILON_PRICE)) {
        double atrValue = iATR(NULL, PERIOD_D1, 14, 1);   // P-TH3-STEP-01: completed days only
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

//+------------------------------------------------------------------+
//| THE MOMENTUM BANDS, in R units (see TH3MomentumSpeed)             |
//|                                                                  |
//| These are NOT a conversion of the degree bands above - the two    |
//| metrics are not proportional, so no factor exists. They are the   |
//| degree bands' own QUANTILES read on 22,538 real zigzag legs from  |
//| 15 series (gold / euro / cable, M5..H4) by                     |
//| `python tools/th3_momentum_bands.py --report`, which prints the   |
//| class mix both ways. The mix is preserved to 0.1pp, so the axis   |
//| keeps classifying the same share of legs and the step the axis    |
//| selects does not silently change: 7.3% weak / 10.0% normal /      |
//| 44.0% strong / 38.7% explosive against the old 7.3 / 10.0 /       |
//| 43.9 / 38.7.                                                      |
//|                                                                  |
//| The tool reads the trigger ATR at pivot B, because that is the    |
//| series TH3SkeletonFromBars passes in. Reading it at the leg's     |
//| START instead gives 0.66 / 0.85 / 1.43 - a one-index slip would   |
//| have shipped bands that are subtly off their own evidence.        |
//|                                                                  |
//| WHY THE QUANTILE MIX WAS ITSELF THE DEFECT, and these bounds are  |
//| no longer read that way. The quantile rule preserved the OLD      |
//| class mix, and the old mix was the problem: 7.3% weak /           |
//| 10.0% normal / 44.0% strong / 38.7% explosive, i.e. 82.7% of      |
//| legs at STRONG or better. TH3StepFromSkeleton then answered the   |
//| same thing for almost every pattern. Preserving a lopsided mix    |
//| only preserves the inertia, so the bounds are read off the R      |
//| ladder below and the mix is allowed to move.                      |
//|                                                                  |
//| THE LADDER (pooled legs, R):                                      |
//|    p5 0.65  p10 0.78  p25 1.01  p50 1.28  p75 1.63  p90 2.06      |
//|                                                                  |
//| R = 1 IS KEPT EXACTLY. It is the one bound whose meaning does not |
//| depend on any sample: below it a leg travelled less than the      |
//| trigger timeframe's own ATR predicts for its duration. The        |
//| measured p25 is 1.01, so honouring R = 1 costs a 0.01 shift and   |
//| buys a bound that can be argued about instead of quoted. The      |
//| other two are that ladder rounded - 1.30 is p52, 1.60 is p73.     |
//|                                                                  |
//| THE RESULTING MIX: 24.1% weak / 27.7% normal / 21.4% strong /     |
//| 26.7% explosive. STRONG-or-better falls from 82.7% to 48.1%, so   |
//| the axis now separates rather than stamps.                        |
//|                                                                  |
//| MOMENTUM_SPEED_SPIKE DOES NOT MOVE THE STEP. STRONG and           |
//| EXPLOSIVE both select the largest candidate, so the third bound   |
//| is a LABEL: it changes what the log calls a pattern and nothing   |
//| about the step. Do not retune it expecting a number to change -   |
//| the two bounds that matter are BALANCED and STRONG.               |
//+------------------------------------------------------------------+
#define MOMENTUM_SPEED_BALANCED 1.00
#define MOMENTUM_SPEED_STRONG   1.30
#define MOMENTUM_SPEED_SPIKE    1.60

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
    // P-TH3-PT: never floor on a zero point. Raw Point is 0 until the contract
    // loads (P-UI-57b), and a zero floor accepts a degenerate AB — and this file
    // must stay compilable standalone (tests\Biotak_TH3_Test.mqh includes only
    // this chain, so GetCachedPoint() is NOT in scope here). Digits IS fixed, so
    // the fallback derives the point from it; WaveAnalysis.mqh:188 filters on
    // GetCachedPoint() for the same distance where that owner is in scope.
    double th3pt = Point;
    if(!(th3pt > 0.0) || !MathIsValidNumber(th3pt)) th3pt = MathPow(10, -Digits);
    double minDistance = th3pt * ABCD_MIN_DISTANCE_POINTS;
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

//+==================================================================+
//| THE SKELETON: five measured axes, and the step they imply        |
//+==================================================================+
//| Mapping to the ABCD model, stated once so it is not re-guessed:  |
//|                                                                  |
//|   A -> B   the IMPULSE.  Its angle is the momentum axis.         |
//|   B        the PIVOT.    Its own candle is the pivot-candle axis.|
//|   B -> C   the COVER.    The first candle here that reverses     |
//|            B's range is the covering candle; its distance from B |
//|            is the cover delay, and how completely it takes B out |
//|            is the cover depth.                                   |
//|   direction  pB > pA.                                            |
//+==================================================================+

//+------------------------------------------------------------------+
//| Classify one candle's length into the course's four classes      |
//| Bands 0.80 / 1.20 / 2.50 ATR are the course's published ones.   |
//+------------------------------------------------------------------+
TH3_PIVOT_CANDLE TH3ClassifyCandle(const double candleRange, const double atr)
{
    if(candleRange <= 0 || atr <= 0) return TH3_PC_UNKNOWN;
    double x = candleRange / atr;
    if(x < 0.80) return TH3_PC_SPINNING;
    if(x < 1.20) return TH3_PC_STANDARD;
    if(x < 2.50) return TH3_PC_LONGBAR;
    return TH3_PC_SPIKE;
}

//+------------------------------------------------------------------+
//| The impulse leg's momentum, as a speed the trigger clock can      |
//| actually express.                                                |
//|                                                                  |
//|        R = |A->B| / (ATR(trigger) * sqrt(elapsed / triggerBar))   |
//|                                                                  |
//| WHY NOT AN ANGLE. `CalculateWaveAngle` is not one. It computes    |
//| atan((pips/min) / (dailyATR/1440)), and a geometric angle needs a |
//| fixed price-per-pixel and time-per-pixel scale that MT4's          |
//| autoscaled chart does not have. So the shipped number is a speed   |
//| ratio mislabelled as an angle, and it carries two real defects:    |
//|                                                                  |
//|  * Its reference is the DAILY ATR. A fast H1 impulse is scored     |
//|    against that day's range, so it reads WEAK exactly when the day  |
//|    is busy - the opposite of what momentum should say.             |
//|  * It divides by elapsed time LINEARLY. Displacement accumulates    |
//|    like the SQUARE ROOT of time, so a leg taking 4x as long is      |
//|    penalised 4x when volatility justifies only 2x: long legs read   |
//|    weak by construction.                                           |
//|                                                                  |
//| R has neither problem. Both sides are in the same units, so no pip  |
//| convention is involved. R = 1 means the leg travelled exactly as    |
//| far as the trigger timeframe predicts for that many bars; R = 2 is  |
//| twice that. Time enters under the sqrt, at the rate volatility      |
//| actually grows. And nothing mentions the D1 series, so "weak" no   |
//| longer means "big daily range".                                    |
//|                                                                  |
//| Timeframe invariance is preserved because the timeframe enters as   |
//| a RATIO (elapsed / bar minutes) and the ATR is the same clock's -   |
//| which is what lets ONE band set serve every chart. Dividing by a    |
//| raw bar count instead would have needed separate bands per          |
//| timeframe, wrong on the one nobody tested.                          |
//+------------------------------------------------------------------+
double TH3MomentumSpeed(const datetime tA, const double pA,
                        const datetime tB, const double pB,
                        const double atrTrigger)
{
    if(atrTrigger <= 0 || atrTrigger == EMPTY_VALUE) return 0.0;

    double dp = MathAbs(pB - pA);
    if(dp <= 0) return 0.0;

    int minutes = (int)((tB - tA) / 60);
    if(minutes <= 0) minutes = 1;

    double barMinutes = (double)Period();
    if(barMinutes <= 0) barMinutes = 1.0;

    double bars = (double)minutes / barMinutes;
    if(bars < 1.0) bars = 1.0;   // a same-bar leg is still one bar of travel

    double r = dp / (atrTrigger * MathSqrt(bars));
    if(r != r) return 0.0;       // NaN guard, same reason the old path had one
    return r;
}

//+------------------------------------------------------------------+
//| Momentum band from the impulse's R reading.                      |
//| The bounds are measured, not chosen - see the band block above.  |
//+------------------------------------------------------------------+
TH3_MOMENTUM TH3MomentumFromSpeed(const double speed)
{
    if(speed >= MOMENTUM_SPEED_SPIKE)    return TH3_MOM_EXPLOSIVE;
    if(speed >= MOMENTUM_SPEED_STRONG)   return TH3_MOM_STRONG;
    if(speed >= MOMENTUM_SPEED_BALANCED) return TH3_MOM_NORMAL;
    return TH3_MOM_WEAK;
}

//+------------------------------------------------------------------+
//| Momentum band from the impulse angle - RETIRED (MOMENTUM-ANGLE-OFF)|
//|                                                                  |
//| Kept for two reasons and no others: `Biotak_TH3_Test.mq4` still   |
//| pins its boundaries, and keeping it makes the old reading and the  |
//| new one comparable from one build. NOTHING decides on it. To      |
//| restore the old axis, point TH3SkeletonFromBars back here and      |
//| re-teach those test lines - do not rewrite the function.           |
//+------------------------------------------------------------------+
TH3_MOMENTUM TH3MomentumFromAngle(const double angle)
{
    if(angle >= ANGLE_SPIKE_THRESHOLD)    return TH3_MOM_EXPLOSIVE;
    if(angle >= ANGLE_STRONG_THRESHOLD)   return TH3_MOM_STRONG;
    if(angle >= ANGLE_BALANCED_THRESHOLD) return TH3_MOM_NORMAL;
    return TH3_MOM_WEAK;
}

//+------------------------------------------------------------------+
//| Pack the five axes into one coordinate                           |
//|                                                                  |
//| Mixed radix 4 x 4 x 4 x 6 x 2 = 768 cells. That is NOT the       |
//| atlas's 1440, and the difference is deliberate: the atlas         |
//| enumerates 8 pivot-candle ARRANGEMENTS and 3 momentum classes,    |
//| while these are 4 classes and 4 bands - the coarse, MEASURABLE    |
//| subset. The point is not to reach a particular count; it is that  |
//| a live pattern finally has a coordinate at all.                   |
//+------------------------------------------------------------------+
int TH3SkeletonKey(const TH3Skeleton &skel)
{
    if(!skel.valid) return -1;
    int pc = ((int)skel.pivotCandle) - 1;          // SPINNING..SPIKE -> 0..3
    if(pc < 0) return -1;                          // UNKNOWN has no coordinate
    int mom = (int)skel.momentum;                  // 0..3
    int cd  = (int)skel.coverDepth;                // 0..3
    int dl  = skel.coverDelay;
    if(dl < 1) dl = 1;
    if(dl > 6) dl = 6;                             // 1..6 -> 0..5
    int dir = (skel.direction > 0) ? 1 : 0;
    return ((((mom * 4 + pc) * 4 + cd) * 6 + (dl - 1)) * 2 + dir);
}

//+------------------------------------------------------------------+
//| The movement step implied by the skeleton                        |
//|                                                                  |
//| Course method 1 gives three step lengths from the two timeframe  |
//| abilities:                                                       |
//|   long  = 3 x ATR(structure) - 2 x ATR(pattern)                  |
//|   med   = 2 x ATR(structure) -     ATR(pattern)                  |
//|   short = (long + med) / 2                                       |
//| Momentum picks which of the three applies, and it picks them in   |
//| ASCENDING order of size: WEAK the smallest, NORMAL the middle,    |
//| STRONG and EXPLOSIVE the largest. The order is the point -        |
//| `short` is a BLEND and does not sit below the other two, so       |
//| handing it to WEAK made the axis run backwards over its own mid   |
//| band. The three values are the course's; only the assignment is   |
//| ours. Cover depth and cover delay then CONTAIN the step: a fully  |
//| covered pivot has less room left to travel, and a late cover      |
//| means the move already spent itself - both shrink the step.       |
//| Those two multipliers are deliberate choices, not course numbers, |
//| and are the only part of this function that is tunable.           |
//|                                                                  |
//| Returns false and leaves stepOut alone when there is no answer:   |
//| the SELECTED candidate goes non-positive - `long` as soon as the  |
//| pattern's ATR passes 1.5 times the structure's, which the course's|
//| own formula does, and the smallest candidate for a WEAK impulse   |
//| earlier than that.                                                |
//| A negative step is not a small step, it is no step - so callers   |
//| keep what they had rather than being handed a guess.              |
//+------------------------------------------------------------------+
bool TH3StepFromSkeleton(const TH3Skeleton &skel,
                         const double atrStructure, const double atrPattern,
                         double &stepOut)
{
    if(!skel.valid) return false;
    if(atrStructure <= 0 || atrPattern <= 0) return false;

    double longStep  = 3.0 * atrStructure - 2.0 * atrPattern;
    double medStep   = 2.0 * atrStructure -       atrPattern;
    double shortStep = 0.5 * (longStep + medStep);

    // THE THREE CANDIDATES ARE ORDERED, NOT ASSUMED, and the assignment to the
    // momentum bands is then MONOTONE. This is a bug fix with a measurement
    // behind it: `shortStep` is a BLEND, 0.5*(long+med), so it sits BETWEEN the
    // other two rather than below them. Shipping `base = shortStep` for WEAK
    // therefore handed the weakest impulses a step BIGGER than NORMAL's on every
    // chart where P < S - which is every intraday chart, since P here is the
    // chart ATR and S the daily one. Measured over 22,538 real legs the shipped
    // assignment gave WEAK 2.264 S against NORMAL 1.870 S: +21.1% for a weaker
    // impulse. The candidate VALUES are unchanged - no new number is invented -
    // only which band gets which, and the harness already asserted the ordered
    // behaviour at `3S - 2P <= 0` (which the old assignment could never reach
    // from WEAK, because the blend stayed positive).
    double cand[3];
    cand[0] = longStep;
    cand[1] = medStep;
    cand[2] = shortStep;
    for(int i = 1; i < 3; i++) {           // three elements, insertion sort
        double v = cand[i];
        int j = i - 1;
        while(j >= 0 && cand[j] > v) {
            cand[j + 1] = cand[j];
            j--;
        }
        cand[j + 1] = v;
    }

    double base = (skel.momentum >= TH3_MOM_STRONG) ? cand[2]
                : (skel.momentum == TH3_MOM_NORMAL) ? cand[1]
                :                                     cand[0];
    if(base <= 0) return false;

    double mult = 1.0;
    if(skel.coverDepth == TH3_CD_DEEP)       mult *= 0.70;
    else if(skel.coverDepth == TH3_CD_FULL)  mult *= 0.85;
    if(skel.coverDelay >= 4)                 mult *= 0.80;
    else if(skel.coverDelay == 3)            mult *= 0.90;

    stepOut = base * mult;
    return (stepOut > 0);
}

//+------------------------------------------------------------------+
//| Measure all five axes from the bars themselves                   |
//|                                                                  |
//| Cost: this runs ONCE per finalised pattern (TH3PatternBuild),     |
//| never per tick and never on mouse-move, so the handful of bar     |
//| reads here do not touch TH3's hot path.                           |
//+------------------------------------------------------------------+
bool TH3SkeletonFromBars(const datetime tA, const double pA,
                         const datetime tB, const double pB,
                         const datetime tC, const double pC,
                         TH3Skeleton &out)
{
    out.valid          = false;
    out.direction      = (pB > pA) ? 1 : -1;
    out.momentum       = TH3_MOM_WEAK;
    out.pivotCandle    = TH3_PC_UNKNOWN;
    out.coverDepth     = TH3_CD_NONE;
    out.coverDelay     = 0;
    out.coverEngulf    = 0;
    out.abAngle        = 0;
    out.abSpeed        = 0;
    out.pivotAtrRatio  = 0;
    out.coverBodyRatio = 0;
    out.stepPips       = 0;
    out.key            = -1;

    if(tA <= 0 || tB <= 0 || pA <= 0 || pB <= 0) return false;

    int barB = iBarShift(NULL, 0, tB, false);
    if(barB < 0) return false;
    int barC = (tC > 0) ? iBarShift(NULL, 0, tC, false) : 0;
    if(barC < 0) barC = 0;
    if(barC > barB) barC = barB;   // C must not sit before B in time

    // The two timeframe abilities the step formula consumes: the structure's
    // (daily, cached) and the pattern's (this chart, at the pivot bar).
    double atrStructure = GetCachedDailyATR();
    double atrPattern   = iATR(NULL, 0, 14, barB);
    if(atrPattern == EMPTY_VALUE || atrPattern <= 0) atrPattern = atrStructure;

    // --- axis 1: momentum, from the impulse leg's SPEED on this clock.
    // atrPattern IS the trigger timeframe's ability - the same series the step
    // formula consumes - so the axis and the step are read off one ruler, and the
    // axis no longer depends on the daily ATR of whatever day it is run.
    // This must come after barB: it is the reason axis 1 moved down.
    out.abSpeed  = TH3MomentumSpeed(tA, pA, tB, pB, atrPattern);
    out.momentum = TH3MomentumFromSpeed(out.abSpeed);

    // The retired angle is still filled, once per finalised pattern, so the log
    // can print both readings side by side while the change is being checked.
    out.abAngle  = CalculateWaveAngle(tA, pA, tB, pB);   // MOMENTUM-ANGLE-OFF

    // --- axis 2: the pivot candle, at B
    double pHigh = iHigh(NULL, 0, barB);
    double pLow  = iLow(NULL, 0, barB);
    double pOpen = iOpen(NULL, 0, barB);
    double pClose= iClose(NULL, 0, barB);
    if(pHigh <= 0 || pLow <= 0) return false;
    out.pivotAtrRatio = (pHigh - pLow) / atrPattern;
    out.pivotCandle   = TH3ClassifyCandle(pHigh - pLow, atrPattern);

    // --- axes 3+4: walk B -> C for the first candle that reverses B's range
    double pBodyHi = MathMax(pOpen, pClose);
    double pBodyLo = MathMin(pOpen, pClose);
    int coverIdx = -1;
    for(int i = barB - 1; i >= barC && i >= 0; i--) {
        double h = iHigh(NULL, 0, i);
        double l = iLow(NULL, 0, i);
        if(h <= 0 || l <= 0) continue;
        if(h >= pHigh && l <= pLow) { coverIdx = i; break; }
    }

    if(coverIdx >= 0) {
        out.coverDelay = barB - coverIdx;
        double cHigh = iHigh(NULL, 0, coverIdx);
        double cLow  = iLow(NULL, 0, coverIdx);
        double cRange= cHigh - cLow;
        out.coverBodyRatio = (cRange > 0)
                           ? MathAbs(iClose(NULL, 0, coverIdx) - iOpen(NULL, 0, coverIdx)) / cRange
                           : 0;

        // how many candles OLDER than the covering candle fit inside its range
        int bars = iBars(NULL, 0);
        int engulf = 0;
        for(int k = coverIdx + 1; k <= coverIdx + 4 && k < bars; k++) {
            double h = iHigh(NULL, 0, k);
            double l = iLow(NULL, 0, k);
            if(h > 0 && l > 0 && cHigh >= h && cLow <= l) engulf++;
        }
        out.coverEngulf = engulf;

        bool bodyCovered = (cHigh >= pBodyHi && cLow <= pBodyLo);
        if(bodyCovered && engulf >= 2) out.coverDepth = TH3_CD_DEEP;
        else if(bodyCovered)           out.coverDepth = TH3_CD_FULL;
        else                           out.coverDepth = TH3_CD_SHALLOW;
    }

    out.valid = true;
    // TH3StepFromSkeleton works in PRICE units so it stays pure and testable
    // with two numbers; the field is in PIPS, converted once here, because every
    // other surface in this tool speaks pips and one unit change beats a
    // conversion scattered across the label, the log and the panel.
    double stepPrice = 0;
    if(TH3StepFromSkeleton(out, atrStructure, atrPattern, stepPrice)) {
        double pipSize = GetCachedPipSize();
        if(pipSize > 0) out.stepPips = stepPrice / pipSize;
    }
    out.key = TH3SkeletonKey(out);
    return true;
}

//+------------------------------------------------------------------+
//| Human-readable skeleton, for logs and the test harness           |
//+------------------------------------------------------------------+
string TH3SkeletonDescribe(const TH3Skeleton &skel)
{
    if(!skel.valid) return "skeleton: unmeasured";
    // Both momentum readings are printed: `speed` is what the axis decides on,
    // `angle` is the retired one (MOMENTUM-ANGLE-OFF), kept here so the two can be
    // compared on live patterns without a second build.
    return StringFormat("skeleton key=%d dir=%s mom=%d pivot=%d depth=%d delay=%d "
                        "engulf=%d speed=%.2f angle=%.1f pivotATR=%.2f coverBody=%.2f "
                        "step=%.1f pips",
                        skel.key, (skel.direction > 0 ? "up" : "down"),
                        (int)skel.momentum, (int)skel.pivotCandle, (int)skel.coverDepth,
                        skel.coverDelay, skel.coverEngulf, skel.abSpeed, skel.abAngle,
                        skel.pivotAtrRatio, skel.coverBodyRatio, skel.stepPips);
}

#endif // TH3_MATH_MQH
