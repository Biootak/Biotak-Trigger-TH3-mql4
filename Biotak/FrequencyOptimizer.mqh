  //+------------------------------------------------------------------+
//| FrequencyOptimizer.mqh - Spectral Resonance Frequency Engine     |
//| v5.1: + Gann Square Root Price Harmony scoring                   |
//| Theory: The best frequency makes ALL steps (1,3,5,7) land on    |
//| key retracement levels of reference waves simultaneously.       |
//| Like finding the fundamental frequency of a standing wave where |
//| all harmonics align with structural nodes.                       |
//| Scoring: 35% multi-step + 12% pattern + 18% time + 12% sqrt    |
//|          + 13% harmonic + 10% history. Confidence = consistency. |
//| Uses binary subdivision: freq = index   1.5625% (depth=6, 64ths)|
//| Gilmore enhancement: adds  -based sacred ratios + confluence.   |
//| Gann enhancement:  price levels as independent scoring axis.    |
//+------------------------------------------------------------------+
#ifndef FREQUENCY_OPTIMIZER_MQH
#define FREQUENCY_OPTIMIZER_MQH

#property strict

// FrequencyResult struct is defined in ProjectConstants.mqh
// (included before GlobalVariables.mqh so it can be used as global state)

// Scoring weights (sum = 1.0)
// v5.1: Added Square Root Harmony. Redistributed from multi-step & time.
#define WEIGHT_MULTISTEP 0.35   // How many steps (1,3,5,7) align with reference levels
#define WEIGHT_PATTERN   0.12   // Harmonic pattern projection (Gartley/Bat/Butterfly/Crab)
#define WEIGHT_TIME      0.18   // Gann price=time alignment
#define WEIGHT_SQRT      0.12   // Gann square root price harmony (NEW)
#define WEIGHT_HARMONIC  0.13   // Binary subdivision harmonic properties
#define WEIGHT_HISTORY   0.10   // Coherence with past frequencies

// Minimum score to accept a frequency as valid
#define MIN_ACCEPTABLE_SCORE 0.20

// Top-N candidates to log for diagnostics
#define FREQ_TOP_N 3

//+------------------------------------------------------------------+
//| Store a scored candidate for top-N tracking                      |
//+------------------------------------------------------------------+
struct FreqCandidate {
    int    index;
    double frequency;
    double total;
    double sMulti;      // Multi-step resonance
    double sPat;        // Pattern projection
    double sTime;
    double sSqrt;       // Square root price harmony
    double sHarm;
    double sHist;
    int    depth;
    int    matchedSteps; // How many of 4 steps matched
    string matchLabel;
    string patternType;
    double confidence;
    double errorPips;
};

//+------------------------------------------------------------------+
//| Calculate Step3 price for a given frequency and ABCD pattern     |
//| Step3 = C   3   baseUnit, where baseUnit = AB   (freq/100)     |
//+------------------------------------------------------------------+
double CalculateStep3Price(double pA, double pB, double pC, double frequency) {
    double abDistance = MathAbs(pB - pA);
    if(abDistance <= 0 || frequency <= 0) return 0;

    double baseUnit = abDistance * (frequency / 100.0);
    bool isBullish = (pB > pA);

    // Step3 = C + 3*baseUnit (bullish) or C - 3*baseUnit (bearish)
    return isBullish ? (pC + 3.0 * baseUnit) : (pC - 3.0 * baseUnit);
}

//+------------------------------------------------------------------+
//| Calculate Step-N price for a given frequency and ABCD pattern    |
//| StepN = C   N   baseUnit, where baseUnit = AB   (freq/100)     |
//+------------------------------------------------------------------+
double CalculateStepNPrice(double pA, double pB, double pC, double frequency, double multiplier) {
    double abDistance = MathAbs(pB - pA);
    if(abDistance <= 0 || frequency <= 0) return 0;

    double baseUnit = abDistance * (frequency / 100.0);
    bool isBullish = (pB > pA);

    return isBullish ? (pC + multiplier * baseUnit) : (pC - multiplier * baseUnit);
}

//+------------------------------------------------------------------+
//| MULTI-STEP RESONANCE SCORE (40% weight)                         |
//| Like finding the fundamental frequency of a standing wave:       |
//| the best frequency makes ALL harmonics (Steps 1,3,5,7) align    |
//| with structural nodes (reference midpoints) simultaneously.     |
//|                                                                  |
//| Physics analogy: In a vibrating string, the fundamental freq    |
//| creates nodes at 1/n positions. The more nodes that land on     |
//| natural support points, the stronger the resonance.             |
//|                                                                  |
//| Probabilistic argument for multi-step vs single-step:           |
//|   P(1 random match)   0.1   weak signal                       |
//|   P(4 independent matches)   0.0001   strong signal (1000 )   |
//| Each additional step exponentially reduces false positive rate.  |
//|                                                                  |
//| Step weights: 3 (40%), 1 (25%), 5 (20%), 7 (15%)               |
//| Convergence bonus: (matchCount/4)    explosive reward for       |
//| frequencies where all steps converge simultaneously.            |
//| Confluence bonus: steps landing in detected confluence zones    |
//| get multiplied by zone strength (Gilmore "Window of Opp.")     |
//|                                                                  |
//| Returns: weighted sum of step matches   convergence bonus       |
//| Also outputs: matchedSteps count, bestMidpointIdx for Step3     |
//+------------------------------------------------------------------+
double ScoreMultiStepResonance(double pA, double pB, double pC, double frequency,
                               const WaveAnalysisResult &analysis, double abDistance,
                               int &bestMidpointIdx, int &matchedSteps) {
    bestMidpointIdx = -1;
    matchedSteps = 0;
    if(analysis.midpointCount <= 0 || abDistance <= 0) return 0;

    // Step multipliers and their weights
    // Step3 gets highest weight: it's the primary TH3 target
    // Step1 = first reaction, Step5/7 = confirmation/extension
    double stepMult[4]   = {1.0, 3.0, 5.0, 7.0};
    double stepWeight[4] = {0.25, 0.40, 0.20, 0.15};

    // Calculate all 4 step prices
    double stepPrices[4] = {0, 0, 0, 0};
    for(int s = 0; s < 4; s++) {
        stepPrices[s] = CalculateStepNPrice(pA, pB, pC, frequency, stepMult[s]);
    }

    // Greedy assignment: each step gets its best unused midpoint
    // Sort by quality (best match first) to avoid suboptimal assignments
    // PERF: Fixed-size array avoids per-call dynamic allocation
    // Track which midpoints have been claimed
    bool midpointUsed[MAX_REFERENCE_MIDPOINTS];
    ArrayInitialize(midpointUsed, false);

    // First pass: compute all step-midpoint scores
    struct StepMidScore {
        int    stepIdx;
        int    midIdx;
        double score;
    };

    // Build score matrix (4 steps   all midpoints)   find top match per step
    double stepScores[4] = {0, 0, 0, 0};
    int    stepBestMid[4] = {-1, -1, -1, -1};

    // Greedy: process steps in priority order (Step3 first, then Step1, Step5, Step7)
    int stepOrder[4] = {1, 0, 2, 3};  // indices into stepMult: 3, 1, 5, 7

    // Determine step direction: bearish steps go DOWN from C, bullish go UP
    bool stepsGoDown = (pB < pA);  // bearish AB   steps go below C

    for(int pri = 0; pri < 4; pri++) {
        int s = stepOrder[pri];
        double bestScore = 0;
        int bestIdx = -1;

        for(int m = 0; m < analysis.midpointCount; m++) {
            if(midpointUsed[m]) continue;
            double midPrice = analysis.midpoints[m].price;
            if(midPrice <= 0) continue;

            // FIX Bug 6: Directional filter   skip midpoints on wrong side of C
            // For bearish pattern (steps go down): only consider midpoints BELOW C
            // For bullish pattern (steps go up): only consider midpoints ABOVE C
            if(stepsGoDown && midPrice > pC) continue;
            if(!stepsGoDown && midPrice < pC) continue;

            double error = MathAbs(stepPrices[s] - midPrice);
            double normalizedError = error / abDistance;
            // FIX Bug 3/6: Sharper Lorentzian decay (k=20 instead of 10)
            // k=10: 20% error   0.33 (too generous, creates noise floor)
            // k=20: 20% error   0.20 (properly penalizes weak matches)
            double rawScore = 1.0 / (1.0 + normalizedError * 20.0);
            double score = rawScore * 0.75;

            // FIX Bug 2: Added missing type 2,3 (quarter 25%/75%) bonus
            int midType = analysis.midpoints[m].type;
            if(midType <= 1)                      score += 0.25 * rawScore;  // 50%/Gann
            else if(midType == 2 || midType == 3) score += 0.18 * rawScore;  // 25%/75% quarters
            else if(midType == 4 || midType == 5) score += 0.20 * rawScore;  // 38.2%/61.8% fib
            else if(midType == 6)                 score += 0.15 * rawScore;  // 78.6% fib

            if(score > bestScore) {
                bestScore = score;
                bestIdx = m;
            }
        }

        stepScores[s] = bestScore;
        stepBestMid[s] = bestIdx;

        // Claim this midpoint (greedy: higher-priority step gets first pick)
        // FIX Bug 7: Raised threshold from 0.3   0.5 to prevent weak claims
        if(bestIdx >= 0 && bestScore > 0.5) {
            midpointUsed[bestIdx] = true;
        }
    }

    // Step3's best midpoint is the primary match (for label display)
    bestMidpointIdx = stepBestMid[1];  // stepMult[1] = 3.0 = Step3

    // Confluence bonus: if a step lands in a confluence zone, amplify its score
    for(int s = 0; s < 4; s++) {
        double confStrength = GetConfluenceStrengthAtPrice(analysis, stepPrices[s]);
        if(confStrength > 0) {
            // Confluence multiplier: up to +30% bonus for strongest zones
            stepScores[s] = MathMin(1.0, stepScores[s] * (1.0 + 0.30 * confStrength));
        }
    }

    // Weighted sum of step scores
    double weightedSum = 0;
    for(int s = 0; s < 4; s++) {
        weightedSum += stepWeight[s] * stepScores[s];
    }

    // Count matched steps (score > 0.4 threshold = meaningful match)
    matchedSteps = 0;
    for(int s = 0; s < 4; s++) {
        if(stepScores[s] > 0.4) matchedSteps++;
    }

    // Convergence bonus: exponential reward for multi-step alignment
    // 1 step matched:  (0.25)  = 0.0625    0.5 after scaling
    // 2 steps:         (0.50)  = 0.25      0.7
    // 3 steps:         (0.75)  = 0.5625    0.9
    // 4 steps:         (1.00)  = 1.0       1.2 (reward)
    double convergenceRatio = (double)matchedSteps / 4.0;
    double convergenceBonus = 0.5 + 0.7 * (convergenceRatio * convergenceRatio);
    // At 0 steps: 0.5, at 1: 0.544, at 2: 0.675, at 3: 0.894, at 4: 1.2

    return MathMin(1.0, weightedSum * convergenceBonus);
}

//+------------------------------------------------------------------+
//| TIME SCORE (25% weight)   Gann: Price = Time                    |
//| Checks if the implied CD duration forms harmonic ratio with      |
//| AB and BC durations. Uses frequency for cycle-time resonance.    |
//+------------------------------------------------------------------+
double ScoreTimeAlignment(double step3Price, double pC, double frequency,
                          const WaveAnalysisResult &analysis) {
    if(!analysis.waveAB.isValid || !analysis.waveBC.isValid) return 0;
    if(analysis.waveBC.speed <= 0) return 0;

    // Estimate how many bars from C to reach Step3
    double step3Distance = MathAbs(step3Price - pC);
    if(step3Distance <= 0) return 0;

    // Use BC wave speed as reference for CD projection
    double estimatedBars = step3Distance / analysis.waveBC.speed;
    if(estimatedBars <= 0) return 0;

    // 1. Duration harmonic check (70% of time score)
    double bestTimeScore = 0;

    double refDurations[2];
    refDurations[0] = (double)analysis.waveAB.barDuration;
    refDurations[1] = (double)analysis.waveBC.barDuration;

    for(int d = 0; d < 2; d++) {
        if(refDurations[d] <= 0) continue;

        double ratio = estimatedBars / refDurations[d];

        // Find nearest harmonic multiple (0.5, 1.0, 1.5, 2.0, 2.5, 3.0)
        double nearestHarmonic = MathRound(ratio * 2.0) / 2.0;
        if(nearestHarmonic < 0.5) nearestHarmonic = 0.5;
        if(nearestHarmonic > 3.0) nearestHarmonic = 3.0;

        double deviation = MathAbs(ratio - nearestHarmonic);
        // Score: 1.0 at exact harmonic, 0.0 at deviation >= 0.5
        double score = MathMax(0, 1.0 - deviation * 2.0);

        // Bonus for 1:1 (Gann's ideal 45  angle)
        if(MathAbs(nearestHarmonic - 1.0) < 0.01) {
            score = MathMin(1.0, score * 1.15);
        }

        if(score > bestTimeScore) bestTimeScore = score;
    }

    // 2. Gann angle consistency (20% of time score)
    double angleScore = 0;
    if(analysis.waveAB.barDuration > 0 && analysis.waveAB.distance > 0) {
        double pricePerBar = analysis.waveAB.distance / (double)analysis.waveAB.barDuration;
        if(pricePerBar > 0) {
            double cdAngleRatio = (step3Distance / estimatedBars) / pricePerBar;
            // 1.0 = same angle as AB, which is ideal
            double angleDeviation = MathAbs(cdAngleRatio - 1.0);
            angleScore = MathMax(0, 1.0 - angleDeviation);
        }
    }

    // 3. Frequency-time resonance (10% of time score)   NEW
    //    Check if frequency/100 harmonizes with BC/AB time ratio
    double freqTimeScore = 0;
    if(analysis.waveAB.barDuration > 0 && analysis.waveBC.barDuration > 0 && frequency > 0) {
        double freqRatio = frequency / 100.0;
        double timeRatio = (double)analysis.waveBC.barDuration / (double)analysis.waveAB.barDuration;
        if(timeRatio > 0) {
            double ftRatio = freqRatio / timeRatio;
            double nearestFT = MathRound(ftRatio * 2.0) / 2.0;
            if(nearestFT < 0.5) nearestFT = 0.5;
            if(nearestFT > 4.0) nearestFT = 4.0;
            double ftDev = MathAbs(ftRatio - nearestFT);
            freqTimeScore = MathMax(0, 1.0 - ftDev * 3.0);
        }
    }

    // Blend: 70% duration harmonic + 20% angle + 10% freq-time resonance
    return bestTimeScore * 0.70 + angleScore * 0.20 + freqTimeScore * 0.10;
}

//+------------------------------------------------------------------+
//| PATTERN PROJECTION SCORE (15% weight)                            |
//| Detects harmonic patterns (Gartley/Bat/Butterfly/Crab) from     |
//| BC/AB ratio, computes ideal D-point, scores frequency alignment  |
//|                                                                  |
//| Scientific basis: Harmonic patterns (Gartley 1935, Carney 2001) |
//| are among the most rigorously validated technical analysis tools.|
//| Each pattern has a specific BC/AB retracement ratio that        |
//| predicts the ideal D reversal point with high precision.        |
//|                                                                  |
//| The ratio BC/AB determines pattern type:                        |
//|   Bat:       BC/AB = 0.382-0.50    D = X + 0.886 XA           |
//|   Gartley:   BC/AB = 0.618         D = X + 0.786 XA           |
//|   Butterfly: BC/AB = 0.786         D = A + 1.272 XA (extends) |
//|   Alt Bat:   BC/AB = 0.886         D = X + 1.130 XA           |
//|   Crab:      BC/AB = 1.27-1.618    D = A + 1.618 XA (extends) |
//|   Deep Crab: BC/AB = 0.886         D = A + 1.618 XA           |
//|                                                                  |
//| This provides a COMPLETELY INDEPENDENT prediction of where      |
//| price should reverse, validating the frequency selection.       |
//| When Step3 aligns with a pattern's ideal D   strong signal.     |
//+------------------------------------------------------------------+
double ScorePatternProjection(double step3Price, const WaveAnalysisResult &analysis,
                              double abDistance, string &detectedPattern) {
    detectedPattern = "";
    if(!analysis.waveXA.isValid || !analysis.waveAB.isValid || !analysis.waveBC.isValid)
        return 0;
    if(analysis.ratioBC_AB <= 0 || analysis.waveXA.distance <= 0 || abDistance <= 0)
        return 0;

    double bcab = analysis.ratioBC_AB;
    double pX = analysis.priceX;
    double pA = analysis.priceA;
    bool isBullish = analysis.isBullish;

    // Pattern definitions: name, BC/AB range, D projection method
    // D projection: from X using XA ratio, or from A using XA extension
    struct PatternDef {
        double bcabMin;       // Minimum BC/AB ratio
        double bcabMax;       // Maximum BC/AB ratio  
        double dRatio;        // D projection ratio (of XA distance)
        bool   fromX;         // true: D = X   ratio XA, false: D = A   ratio XA (extension)
        double quality;       // Base quality   how reliable this pattern is historically
    };

    // 6 patterns ordered by retracement depth
    PatternDef patterns[6];
    // Bat: shallow pullback   deep D
    patterns[0].bcabMin = 0.33;  patterns[0].bcabMax = 0.52;
    patterns[0].dRatio  = 0.886; patterns[0].fromX   = true; patterns[0].quality = 0.85;
    // Gartley: classic 61.8% pullback   78.6% D
    patterns[1].bcabMin = 0.55;  patterns[1].bcabMax = 0.67;
    patterns[1].dRatio  = 0.786; patterns[1].fromX   = true; patterns[1].quality = 0.90;
    // Butterfly: deep pullback   extension D  
    patterns[2].bcabMin = 0.72;  patterns[2].bcabMax = 0.82;
    patterns[2].dRatio  = 1.272; patterns[2].fromX   = false; patterns[2].quality = 0.80;
    // Alt Bat: deep pullback   moderate extension
    patterns[3].bcabMin = 0.82;  patterns[3].bcabMax = 0.92;
    patterns[3].dRatio  = 1.130; patterns[3].fromX   = true; patterns[3].quality = 0.75;
    // Crab: very wide BC   extreme extension D
    patterns[4].bcabMin = 1.20;  patterns[4].bcabMax = 1.70;
    patterns[4].dRatio  = 1.618; patterns[4].fromX   = false; patterns[4].quality = 0.80;
    // Deep Crab: moderate but extending
    patterns[5].bcabMin = 0.82;  patterns[5].bcabMax = 0.92;
    patterns[5].dRatio  = 1.618; patterns[5].fromX   = false; patterns[5].quality = 0.70;

    string patternNames[6];
    patternNames[0] = "Bat";      patternNames[1] = "Gartley";
    patternNames[2] = "Butterfly"; patternNames[3] = "AltBat";
    patternNames[4] = "Crab";     patternNames[5] = "DeepCrab";

    double xaDistance = analysis.waveXA.distance;
    double xaSigned = pA - pX;  // Signed XA direction

    double bestScore = 0;

    for(int p = 0; p < 6; p++) {
        // Check if BC/AB matches this pattern's range
        if(bcab < patterns[p].bcabMin || bcab > patterns[p].bcabMax) continue;

        // How close BC/AB is to the center of the valid range
        double rangeCenter = (patterns[p].bcabMin + patterns[p].bcabMax) / 2.0;
        double rangeWidth = (patterns[p].bcabMax - patterns[p].bcabMin) / 2.0;
        double ratioFit = 1.0 - MathAbs(bcab - rangeCenter) / rangeWidth;
        ratioFit = MathMax(0, MathMin(1.0, ratioFit));

        // Calculate ideal D price for this pattern
        double idealD;
        if(patterns[p].fromX) {
            // D = X + ratio   XA (same direction as XA)
            // e.g. Gartley: D = X + 0.786   (A-X)   78.6% of XA from X
            idealD = pX + patterns[p].dRatio * xaSigned;
        } else {
            // FIX Bug 1: Extension from A (not from X!)
            // D extends BEYOND A in the XA direction by ratio   XA distance
            // e.g. Butterfly: D = A + 1.272   (A-X)   127.2% extension from A
            // e.g. Crab:      D = A + 1.618   (A-X)   161.8% extension from A
            idealD = pA + patterns[p].dRatio * xaSigned;
        }

        if(idealD <= 0) continue;

        // Score: how close Step3 is to ideal D
        double dError = MathAbs(step3Price - idealD);
        double normalizedDError = dError / xaDistance;
        // D-point matching: tighter tolerance than midpoint matching
        // k=8 gives moderate sensitivity: 5% error   0.71 score, 10%   0.56
        double matchScore = 1.0 / (1.0 + normalizedDError * 8.0);

        // Final score: match quality   ratio fit   pattern reliability
        double score = matchScore * ratioFit * patterns[p].quality;

        if(score > bestScore) {
            bestScore = score;
            detectedPattern = patternNames[p];
        }
    }

    return MathMin(1.0, bestScore);
}

//+------------------------------------------------------------------+
//| HARMONIC SCORE (15% weight)                                      |
//| Checks if frequency has binary subdivision harmonic properties   |
//| Plus fractal-frequency bridge: bonus when freq aligns with       |
//| MODIFIED_FRACTAL_PERCENTAGES or their binary multiples           |
//+------------------------------------------------------------------+
double ScoreHarmonicPhase(double frequency, const WaveAnalysisResult &analysis) {
    double score = 0;

    // 1. Binary subdivision depth scoring (max 0.35)
    //    Find index from frequency, then check its 2-adic depth
    int freqIndex = FindNearestFreqIndex(frequency);
    int depth = GetBinaryDepthLevel(freqIndex);

    // Score based on depth: deeper = more harmonic
    // v5.0: reduced from 0.40 0.35 to make room for BC/AB ratio (sub-score 5)
    if(depth >= BINARY_SUBDIVISION_DEPTH)      score += 0.35;  // Pure octave (100%)
    else if(depth >= 5)                         score += 0.31;  // Halves
    else if(depth >= 4)                         score += 0.28;  // Quarters
    else if(depth >= 3)                         score += 0.24;  // Eighths
    else if(depth >= 2)                         score += 0.20;  // 16ths
    else if(depth >= 1)                         score += 0.17;  // 32nds
    else                                        score += 0.10;  // 64ths

    // 2. Check if index is power-of-2 OR a Gilmore sacred ratio (max 0.15)
    //    Power-of-2: indices 1,2,4,8,16,32,64,128   Harmonic family ( 2)
    //    Perfect-fifth: 3  power-of-2   e.g. 3,6,12,24,48,96
    //    Gilmore sacred ratios:  -based indices from "Geometry of Markets"
    //     =1.618, 1/ =0.618, 1/  =0.382,  (1/ )=0.786,  2=1.414, etc.
    if(freqIndex > 0) {
        double specialBonus = 0;

        // Power-of-2 (Harmonic family)
        if((freqIndex & (freqIndex - 1)) == 0) {
            specialBonus = 0.15;  // Pure octave   index is exact power of 2
        } else {
            // Perfect-fifth (3  power-of-2)
            int idx3 = freqIndex;
            if(idx3 % 3 == 0) {
                idx3 /= 3;
                if((idx3 & (idx3 - 1)) == 0) {
                    specialBonus = 0.08;
                }
            }
        }

        // Gilmore Geometric ( -based) sacred ratios   if not already a power-of-2
        // Check if frequency% is close to a sacred proportion from the book
        // Tolerance:  1 index step (1.5625%) = Gilmore's "lost motion" of ~1-2%
        if(specialBonus < 0.08) {
            // Sacred ratios expressed as percentages (= ratio   100)
            // Source: Geometry of Markets Vol II, pages 11, 116
            //   Geometric:   series spiral of   
            //   Also includes  2 (Harmonic crossover) and  3 (Arithmetic crossover)
            static const double GILMORE_SACRED_PCT[] = {
                14.6,    // 1/   = 0.146
                18.6,    // 1/   = 0.186
                23.6,    // 1/   = 0.236  (also  5-based)
                30.0,    // 1/        = 0.300
                38.2,    // 1/   = 0.382  *** PRIMARY ***
                44.7,    // 1/ 5 = 0.447 (root family)
                48.6,    //   /  = 0.486
                52.6,    // 1/1.902 = 0.526
                57.7,    // 1/ 3 = 0.577 (arithmetic family)
                61.8,    // 1/  = 0.618   *** PRIMARY ***
                70.7,    // 1/ 2 = 0.707 (harmonic crossover)
                78.6,    // 1/   = 0.786  *** PRIMARY ***
                87.5,    // 7/8 = 0.875
                127.2,   //    = 1.272
                141.4,   //  2 = 1.414
                161.8,   //   = 1.618     *** PRIMARY ***
                173.2,   //  3 = 1.732
                190.2    //  (  +1) = 1.902
            };
            int sacredCount = 18;

            for(int s = 0; s < sacredCount; s++) {
                double sacredFreq = GILMORE_SACRED_PCT[s];
                double deviation = MathAbs(frequency - sacredFreq);
                //  1 index step tolerance (1.5625%)   Gilmore's "lost motion" of 1-2%
                if(deviation <= 1.5625) {
                    // Primary sacred ratios (38.2%, 61.8%, 78.6%, 161.8%) get higher bonus
                    bool isPrimary = (s == 4 || s == 9 || s == 11 || s == 15);
                    double sacredBonus = isPrimary ? 0.12 : 0.07;
                    // Scale by proximity: exact match   full bonus, 1.5625 away   60%
                    double proximity = 1.0 - (deviation / 1.5625) * 0.40;
                    specialBonus = MathMax(specialBonus, sacredBonus * proximity);
                    break;
                }
            }
        }

        score += specialBonus;
    }

    // 3. Check if frequency relates to wave ratio AB/XA (max 0.20)
    //    FIX: also check sub-multiples (freq < ratio). Old code only checked
    //    nearestMult >= 1, missing valid sub-harmonics like 1/2, 1/3, 1/4 of ratio.
    //    v5.0: reduced from 0.25 0.20 to make room for BC/AB ratio (sub-score 5)
    if(analysis.ratioAB_XA > 0) {
        double freqRatio = frequency / 100.0;
        double abxaScore = 0;

        // Check super-multiples: freq   N   ratio (N=1..4)
        double nearestMult = MathRound(freqRatio / analysis.ratioAB_XA);
        if(nearestMult >= 1 && nearestMult <= 4) {
            double expected = nearestMult * analysis.ratioAB_XA;
            double ratioDeviation = MathAbs(freqRatio - expected);
            if(ratioDeviation < 0.02)
                abxaScore = 0.20;
            else if(ratioDeviation < 0.05)
                abxaScore = 0.12;
        }

        // Check sub-multiples: ratio   N   freq (N=2..4)   freq is 1/N of ratio
        if(abxaScore < 0.20 && freqRatio > 0) {
            double nearestSub = MathRound(analysis.ratioAB_XA / freqRatio);
            if(nearestSub >= 2 && nearestSub <= 4) {
                double expected = analysis.ratioAB_XA / nearestSub;
                double subDeviation = MathAbs(freqRatio - expected);
                if(subDeviation < 0.02)
                    abxaScore = MathMax(abxaScore, 0.18);
                else if(subDeviation < 0.05)
                    abxaScore = MathMax(abxaScore, 0.10);
            }
        }

        score += abxaScore;
    }

    // 4. Fractal-frequency bridge (max 0.15)
    //    Check if frequency matches a fractal percentage or its binary multiples
    //    MODIFIED_FRACTAL_PERCENTAGES[9] from ConstantsAndEnums.mqh
    //    NOTE: fractal values are ratios (0.0208 = 2.08%), multiply by 100 for percentage
    //    v5.0: reduced from 0.20 0.15 to make room for BC/AB ratio (sub-score 5)
    double bestFractalScore = 0;
    for(int f = 0; f < 9; f++) {
        double fracPct = MODIFIED_FRACTAL_PERCENTAGES[f];
        if(fracPct <= 0) continue;

        // Convert ratio   percentage
        double baseFracFreq = fracPct * 100.0;

        // Check binary multiples:  1,  2,  4,  8,  16,  32,  64
        double mult = baseFracFreq;
        for(int m = 0; m < 7 && mult <= 200.0; m++) {
            double fracError = MathAbs(frequency - mult) / MathMax(frequency, mult);
            if(fracError < 0.02) {
                bestFractalScore = MathMax(bestFractalScore, 0.15);
            } else if(fracError < 0.10) {
                double fs = 0.15 * (1.0 - fracError / 0.10);
                bestFractalScore = MathMax(bestFractalScore, fs);
            }

            // Also check intermediate  1.5 and  3 multiples at this level
            double mult15 = mult * 1.5;
            if(mult15 <= 200.0) {
                double err15 = MathAbs(frequency - mult15) / MathMax(frequency, mult15);
                if(err15 < 0.02) {
                    bestFractalScore = MathMax(bestFractalScore, 0.12);
                } else if(err15 < 0.10) {
                    double fs15 = 0.12 * (1.0 - err15 / 0.10);
                    bestFractalScore = MathMax(bestFractalScore, fs15);
                }
            }

            double mult3 = mult * 3.0;
            if(mult3 <= 200.0) {
                double err3 = MathAbs(frequency - mult3) / MathMax(frequency, mult3);
                if(err3 < 0.02) {
                    bestFractalScore = MathMax(bestFractalScore, 0.12);
                } else if(err3 < 0.10) {
                    double fs3 = 0.12 * (1.0 - err3 / 0.10);
                    bestFractalScore = MathMax(bestFractalScore, fs3);
                }
            }

            mult *= 2.0;
        }
    }
    score += bestFractalScore;

    // 5. Check if frequency relates to wave ratio BC/AB (max 0.15)   NEW in v5.0
    //    Previously computed but NEVER used. BC/AB tells us the retracement depth
    //    which is completely independent of AB/XA. Using both doubles our ratio info.
    //    Same logic as AB/XA check: super-multiples and sub-multiples of the ratio.
    if(analysis.ratioBC_AB > 0) {
        double freqRatio = frequency / 100.0;
        double bcabScore = 0;

        // Check super-multiples: freq   N   BC/AB ratio (N=1..4)
        double nearestMult = MathRound(freqRatio / analysis.ratioBC_AB);
        if(nearestMult >= 1 && nearestMult <= 4) {
            double expected = nearestMult * analysis.ratioBC_AB;
            double ratioDeviation = MathAbs(freqRatio - expected);
            if(ratioDeviation < 0.02)
                bcabScore = 0.15;
            else if(ratioDeviation < 0.05)
                bcabScore = 0.09;
        }

        // Check sub-multiples: BC/AB   N   freq (N=2..4)
        if(bcabScore < 0.15 && freqRatio > 0) {
            double nearestSub = MathRound(analysis.ratioBC_AB / freqRatio);
            if(nearestSub >= 2 && nearestSub <= 4) {
                double expected = analysis.ratioBC_AB / nearestSub;
                double subDeviation = MathAbs(freqRatio - expected);
                if(subDeviation < 0.02)
                    bcabScore = MathMax(bcabScore, 0.12);
                else if(subDeviation < 0.05)
                    bcabScore = MathMax(bcabScore, 0.07);
            }
        }

        score += bcabScore;
    }

    // Clamp to [0, 1]
    if(score > 1.0) score = 1.0;
    return score;
}

//+------------------------------------------------------------------+
//| GANN SQUARE ROOT PRICE HARMONY SCORE (12% weight)                |
//|                                                                  |
//| Gann's fundamental insight: markets move on a SQUARE ROOT scale. |
//| Equally-spaced levels in the  price domain are natural support & |
//| resistance. Gilmore (page 116, "Sacred Proportions") formalizes  |
//| this:  (P2/P1) should equal a sacred proportion for harmonically |
//| related price levels.                                            |
//|                                                                  |
//| This scoring checks TWO independent  -domain properties:        |
//|                                                                  |
//| 1. SQRT-RATIO HARMONY (60% of sub-score):                       |
//|    For each Step price and each anchor (X,A,B,C), compute the    |
//|    price ratio r = Step/Anchor (or Anchor/Step if r < 1).        |
//|    Then check if  r   a sacred proportion (Gilmore page 116):   |
//|    1/ (0.786), 1/ 2(0.707), 1(unity),   (1.272),  2(1.414),   |
//|     (1.618),  3(1.732), 2,  5(2.236)                           |
//|    Why: prices at sacred  -ratios act as harmonic nodes.        |
//|    Gann's "Squaring Price" = step prices related to anchors by  |
//|    sacred proportions in the   domain.                           |
//|                                                                  |
//| 2. SQRT-DOMAIN SPACING (40% of sub-score):                      |
//|    In the   domain, compute the distance from C to each Step:   |
//|      s = | Step_n -  C|                                        |
//|    The AB distance in   domain = | B -  A| = " -unit"          |
//|    Check if   s /  -unit   sacred proportion   multiplier      |
//|    Why: this verifies that the frequency creates steps that are  |
//|    harmonically spaced not just linearly (in price), but also   |
//|    in the  -price domain   a completely independent axis.        |
//|                                                                  |
//| The mathematical justification: linear % analysis (midpoints)   |
//| and  -domain analysis probe DIFFERENT geometric properties of   |
//| price structure. A frequency that scores well on BOTH is far    |
//| more likely to capture a genuine structural resonance.           |
//|                                                                  |
//| False-positive control:                                          |
//|   Tight tolerance ( 2.5% exact,  7% good). Convergence bonus   |
//|   requires  2 steps to have  -harmony. Single random match      |
//|   scores low; only systematic  -alignment scores high.          |
//+------------------------------------------------------------------+
double ScoreSquareRootHarmony(double pX, double pA, double pB, double pC,
                              double frequency, double abDistance,
                              bool isBullish) {
    if(pA <= 0 || pB <= 0 || pC <= 0 || abDistance <= 0 || frequency <= 0)
        return 0;

    // Calculate all 4 step prices
    double stepMult[4] = {1.0, 3.0, 5.0, 7.0};
    double stepPrices[4] = {0, 0, 0, 0};
    for(int s = 0; s < 4; s++) {
        stepPrices[s] = CalculateStepNPrice(pA, pB, pC, frequency, stepMult[s]);
        if(stepPrices[s] <= 0) stepPrices[s] = 0;
    }

    // Sacred proportions for  (ratio) check   from Gilmore page 116
    // "Three families of ratios": Geometric ( ), Harmonic ( 2), Arithmetic ( 3)
    // In the   domain these become the fundamental resonant intervals
    static const double SQRT_SACRED[] = {
        0.618,    // 1/  (golden cut reciprocal)
        0.707,    // 1/ 2 (harmonic family)
        0.786,    //  (1/ ) = 1/   (geometric family)
        1.000,    // Unity (fundamental)
        1.272,    //    (geometric family)
        1.414,    //  2 (harmonic family)
        1.618,    //   (golden ratio itself)
        1.732,    //  3 (arithmetic family)
        2.000,    // Octave (Gann's "full revolution")
        2.236     //  5 (root-five family, also   + 1/  =  5)
    };
    static const int SQRT_SACRED_COUNT = 10;

    // Tolerance bands: tight to avoid false positives
    // With 10 sacred values in range [0.618, 2.236] (span=1.618),
    //  0.07 tolerance per value = 1.40/1.618 = 86.5% coverage of full range.
    // But we require  2 step matches (convergence) which makes
    // random P(2 out of 4 steps matching)   0.865    C(4,2)/total   10-20%.
    // Combined with other scoring, this is discriminating enough.
    // FIX Bug 4: Tightened from  2.5%/ 7% to  1.5%/ 4%
    // Old tolerance gave ~87% per-step coverage   nearly constant score
    // New tolerance: ~40% per-step coverage   meaningful discrimination
    static const double EXACT_TOL = 0.015;   //  1.5% for near-perfect match
    static const double GOOD_TOL  = 0.040;   //  4.0% for good match

    // Anchor prices to check  -ratios against
    double anchors[4] = {0, 0, 0, 0};
    int anchorCount = 0;
    anchors[anchorCount++] = pA;
    anchors[anchorCount++] = pB;
    anchors[anchorCount++] = pC;
    if(pX > 0 && pX != pA && pX != pB) anchors[anchorCount++] = pX;

    // Step weights: Step3 most important, Step7 least
    double stepWeight[4] = {0.20, 0.40, 0.25, 0.15};

    //------------------------------------------------------------------
    // PART 1:  -RATIO HARMONY (60% of score)
    //   For each step, find best  (step/anchor) match with any sacred
    //------------------------------------------------------------------
    double ratioScore = 0;
    int ratioMatchCount = 0;

    for(int s = 0; s < 4; s++) {
        if(stepPrices[s] <= 0) continue;

        double bestStepMatch = 0;
        for(int a = 0; a < anchorCount; a++) {
            if(anchors[a] <= 0) continue;

            // Compute ratio (always   1)
            double ratio = stepPrices[s] / anchors[a];
            if(ratio < 1.0) ratio = 1.0 / ratio;
            if(ratio <= 0 || ratio > 6.0) continue;  // Skip extreme ratios

            double sqrtRatio = MathSqrt(ratio);

            for(int p = 0; p < SQRT_SACRED_COUNT; p++) {
                double dev = MathAbs(sqrtRatio - SQRT_SACRED[p]);
                if(dev < EXACT_TOL) {
                    // Near-perfect  -harmony
                    bestStepMatch = MathMax(bestStepMatch, 1.0);
                } else if(dev < GOOD_TOL) {
                    // Good  -harmony   linear decay from 0.85 to 0
                    double quality = 0.85 * (1.0 - (dev - EXACT_TOL) / (GOOD_TOL - EXACT_TOL));
                    bestStepMatch = MathMax(bestStepMatch, quality);
                }
            }
        }

        ratioScore += stepWeight[s] * bestStepMatch;
        if(bestStepMatch > 0.5) ratioMatchCount++;
    }

    //------------------------------------------------------------------
    // PART 2:  -DOMAIN SPACING (40% of score)
    //   Check if steps are harmonically spaced in the  -price domain
    //    -unit = | B -  A| (AB distance in   domain)
    //     s = | Step_n -  C| (step distance in   domain)
    //   Check if   s /  -unit   sacred   multiplier
    //------------------------------------------------------------------
    double spacingScore = 0;
    int spacingMatchCount = 0;

    double sqrtA = MathSqrt(pA);
    double sqrtB = MathSqrt(pB);
    double sqrtC = MathSqrt(pC);
    double sqrtUnit = MathAbs(sqrtB - sqrtA);  // AB distance in   domain

    if(sqrtUnit > 0) {
        for(int s = 0; s < 4; s++) {
            if(stepPrices[s] <= 0) continue;

            double sqrtStep = MathSqrt(stepPrices[s]);
            double deltaSqrt = MathAbs(sqrtStep - sqrtC);
            double normalizedDelta = deltaSqrt / sqrtUnit;

            // Check if normalizedDelta   sacred proportion (  small integer multiples)
            // Multiples 0.5 , 1 , 2 , 3  of each sacred proportion
            double bestSpacingMatch = 0;
            double spacingMult[4] = {0.5, 1.0, 2.0, 3.0};

            for(int m = 0; m < 4; m++) {
                for(int p = 0; p < SQRT_SACRED_COUNT; p++) {
                    double expected = SQRT_SACRED[p] * spacingMult[m];
                    if(expected <= 0 || expected > 10.0) continue;

                    double dev = MathAbs(normalizedDelta - expected) / expected;
                    if(dev < 0.02) {
                        // Near-exact  -spacing (tightened from 3% to 2%)
                        bestSpacingMatch = MathMax(bestSpacingMatch, 1.0);
                    } else if(dev < 0.06) {
                        // Good  -spacing (tightened from 10% to 6%)
                        double quality = 0.80 * (1.0 - (dev - 0.02) / 0.04);
                        bestSpacingMatch = MathMax(bestSpacingMatch, quality);
                    }
                }
            }

            spacingScore += stepWeight[s] * bestSpacingMatch;
            if(bestSpacingMatch > 0.5) spacingMatchCount++;
        }
    }

    // Combine parts: 60% ratio + 40% spacing
    double rawScore = ratioScore * 0.60 + spacingScore * 0.40;

    // Convergence bonus: multiple steps with  -harmony   much stronger signal
    // Single match could be coincidence; 3-4 matches = systematic resonance
    int totalMatches = MathMin(ratioMatchCount, 4) + MathMin(spacingMatchCount, 4);
    // totalMatches: 0..8 (from both sub-scores combined)
    double convBonus = 1.0;
    if(totalMatches >= 6)      convBonus = 1.30;  //  3 ratio +  3 spacing matches
    else if(totalMatches >= 4) convBonus = 1.15;  //  2 +  2
    else if(totalMatches >= 3) convBonus = 1.05;

    return MathMin(1.0, rawScore * convBonus);
}

//+------------------------------------------------------------------+
//| HISTORY SCORE (10% weight)                                       |
//| Coherence with previously found frequencies in the ring buffer   |
//| Rewards frequencies harmonically related to past results         |
//| Also rewards consistent AB scale (similar market conditions)     |
//+------------------------------------------------------------------+
double ScoreHistoryCoherence(int candidateIndex, double abDistance) {
    if(g_freqHistoryCount <= 0) return 0.5;  // Neutral when no history

    double totalScore = 0;
    int validEntries = 0;

    int count = MathMin(g_freqHistoryCount, FREQ_HISTORY_SIZE);
    for(int i = 0; i < count; i++) {
        if(!g_freqHistory[i].isUsed) continue;

        double entryScore = 0;

        // 1. Frequency harmonic relationship (max 0.6)
        //    Check if candidate is a binary multiple/divisor of past freq
        //    FIX: reduced same-index bonus from 0.60 0.40 to prevent lock-in.
        //    Added recency weighting: newer history entries count more.
        int pastIdx = g_freqHistory[i].freqIndex;

        // Recency factor: newer entries weighted more (slot 0=oldest)
        // Position of this entry relative to the newest
        int age = (g_freqHistoryHead - 1 - i + FREQ_HISTORY_SIZE) % FREQ_HISTORY_SIZE;
        double recencyWeight = 1.0 - (double)age / (double)(FREQ_HISTORY_SIZE * 2);  // 1.0 0.625

        if(pastIdx > 0 && candidateIndex > 0) {
            double harmBonus = 0;
            if(candidateIndex == pastIdx) {
                harmBonus = 0.40;  // Same index (was 0.60   reduced to prevent lock-in)
            } else {
                double ratio;
                if(candidateIndex >= pastIdx)
                    ratio = (double)candidateIndex / (double)pastIdx;
                else
                    ratio = (double)pastIdx / (double)candidateIndex;

                // Check if ratio is close to a power of 2
                if(ratio > 0) {
                    double log2Ratio = MathLog(ratio) / MathLog(2.0);
                    double log2Round = MathRound(log2Ratio);
                    double log2Err = MathAbs(log2Ratio - log2Round);

                    if(log2Err < 0.05)       harmBonus = 0.50;  // Exact octave
                    else if(log2Err < 0.15)  harmBonus = 0.35;  // Near octave
                    else if(log2Err < 0.30)  harmBonus = 0.15;  // Approximate
                }
            }
            entryScore += harmBonus * recencyWeight;
        }

        // 2. Scale similarity (max 0.4)
        //    Similar AB distance = similar market conditions = more relevant
        if(g_freqHistory[i].abDistance > 0 && abDistance > 0) {
            double scaleRatio = abDistance / g_freqHistory[i].abDistance;
            if(scaleRatio > 1.0) scaleRatio = 1.0 / scaleRatio;
            // scaleRatio in (0, 1], 1.0 = same scale
            entryScore += 0.4 * scaleRatio;
        }

        totalScore += entryScore;
        validEntries++;
    }

    if(validEntries <= 0) return 0.5;
    return MathMin(1.0, totalScore / (double)validEntries);
}

//+------------------------------------------------------------------+
//| Push a result onto the frequency history ring buffer              |
//+------------------------------------------------------------------+
void PushFrequencyHistory(const FrequencyResult &result, double abDistance, double ratioBC_AB) {
    int slot = g_freqHistoryHead;
    g_freqHistory[slot].result     = result;
    g_freqHistory[slot].abDistance = abDistance;
    g_freqHistory[slot].ratioBC_AB = ratioBC_AB;
    g_freqHistory[slot].freqIndex  = result.bestIndex;
    g_freqHistory[slot].timestamp  = TimeCurrent();
    g_freqHistory[slot].isUsed     = true;

    g_freqHistoryHead = (g_freqHistoryHead + 1) % FREQ_HISTORY_SIZE;
    if(g_freqHistoryCount < FREQ_HISTORY_SIZE)
        g_freqHistoryCount++;
}

//+------------------------------------------------------------------+
//| Insert candidate into sorted top-N array (descending by total)   |
//+------------------------------------------------------------------+
void InsertTopN(FreqCandidate &topN[], int &topCount, const FreqCandidate &cand, int maxN) {
    // Find insertion position
    int pos = topCount;
    for(int i = 0; i < topCount; i++) {
        if(cand.total > topN[i].total) { pos = i; break; }
    }
    if(pos >= maxN) return;  // Not in top N

    // Shift down
    int newCount = MathMin(topCount + 1, maxN);
    for(int j = newCount - 1; j > pos; j--) {
        topN[j] = topN[j - 1];
    }
    topN[pos] = cand;
    topCount = newCount;
}

//+------------------------------------------------------------------+
//| Compute confidence score from component score consistency        |
//| Uses coefficient of variation: lower CV = higher confidence     |
//| All high + consistent      , mixed     , erratic              |
//+------------------------------------------------------------------+
double ComputeConfidence(double sMulti, double sPat, double sTime, double sSqrt, double sHarm, double sHist) {
    double scores[6];
    scores[0] = sMulti; scores[1] = sPat; scores[2] = sTime;
    scores[3] = sSqrt;  scores[4] = sHarm; scores[5] = sHist;

    // Mean
    double sum = 0;
    for(int i = 0; i < 6; i++) sum += scores[i];
    double mean = sum / 6.0;
    if(mean <= 0) return 0;

    // Standard deviation
    double varSum = 0;
    for(int i = 0; i < 6; i++) {
        double diff = scores[i] - mean;
        varSum += diff * diff;
    }
    double stddev = MathSqrt(varSum / 6.0);

    // Coefficient of variation: 0 = perfectly consistent, >1 = erratic
    double cv = stddev / mean;

    // Confidence: high mean + low CV   high confidence
    // Mean component (0..1): how good the scores are overall
    // Consistency component (0..1): how consistent they are (1 - cv)
    double consistency = MathMax(0, 1.0 - cv);
    double confidence = mean * 0.6 + consistency * 0.4;

    return MathMin(1.0, MathMax(0, confidence));
}

//+------------------------------------------------------------------+
//| MAIN: Find optimal frequency for an ABCD pattern                 |
//| v5.1: Spectral Resonance Frequency Engine + Gann  Price          |
//| Tests all binary subdivision frequencies (index 1..128),         |
//| scores each with 6 components (multi-step, pattern, time,       |
//| sqrt, harmonic, history), tie-breaks by depth, logs top-3       |
//+------------------------------------------------------------------+
bool FindOptimalFrequency(double pX, datetime tX, double pA, datetime tA,
                          double pB, datetime tB, double pC, datetime tC,
                          FrequencyResult &result) {
    result.Reset();

    // Step 1: Analyze all waves + detect confluence zones
    WaveAnalysisResult analysis;
    if(!AnalyzeWaves(pX, tX, pA, tA, pB, tB, pC, tC, analysis)) {
        _LOG_GATE_E Print("[E][FreqOpt] AnalyzeWaves failed   invalid XABC points");
        return false;
    }

    double abDistance = analysis.waveAB.distance;
    if(abDistance <= 0) return false;

    double pipSize = GetCachedPipSize();
    if(pipSize <= 0) pipSize = GetCachedPoint();

    // Log confluence zones if found
    if(analysis.confluenceCount > 0) {
        for(int c = 0; c < analysis.confluenceCount; c++) {
            Print("[FreqOpt] Confluence Zone #", c + 1, ": ",
                  DoubleToString(analysis.confluenceZones[c].centerPrice, (int)Digits),
                  " (", analysis.confluenceZones[c].memberCount, " levels, ",
                  analysis.confluenceZones[c].uniqueWaves, " waves, ",
                  "strength:", DoubleToString(analysis.confluenceZones[c].strength, 2), ")");
        }
    }

    // Step 2: Test every frequency with 6-component scoring
    FreqCandidate topN[FREQ_TOP_N];
    int topCount = 0;

    double bestTotal = -1;
    int    bestIdx   = -1;
    int    bestDepth = -1;

    // Pre-compute direction for sqrt scoring
    bool isBullish = analysis.isBullish;

    for(int i = MIN_TH3_FREQ_INDEX; i <= MAX_TH3_FREQ_INDEX; i++) {
        double freq = GetFrequencyByIndex(i);

        // Minimum step filter: Step1 must be >= MIN_STEP1_PIPS
        double step1Size = abDistance * (freq / 100.0);
        if(pipSize > 0 && (step1Size / pipSize) < MIN_STEP1_PIPS)
            continue;

        // Calculate Step3 price for this frequency (for time + pattern scoring)
        double step3 = CalculateStep3Price(pA, pB, pC, freq);
        if(step3 <= 0) continue;

        // Score 6 components
        int bestMidIdx = -1;
        int matchedStepsCount = 0;
        double sMulti = ScoreMultiStepResonance(pA, pB, pC, freq, analysis, abDistance,
                                                 bestMidIdx, matchedStepsCount);
        string patternType = "";
        double sPat   = ScorePatternProjection(step3, analysis, abDistance, patternType);
        double sTime  = ScoreTimeAlignment(step3, pC, freq, analysis);
        double sSqrt  = ScoreSquareRootHarmony(pX, pA, pB, pC, freq, abDistance, isBullish);
        double sHarm  = ScoreHarmonicPhase(freq, analysis);
        double sHist  = ScoreHistoryCoherence(i, abDistance);

        // Weighted total (6 components, sum of weights = 1.0)
        double total = WEIGHT_MULTISTEP * sMulti
                     + WEIGHT_PATTERN   * sPat
                     + WEIGHT_TIME      * sTime
                     + WEIGHT_SQRT      * sSqrt
                     + WEIGHT_HARMONIC  * sHarm
                     + WEIGHT_HISTORY   * sHist;

        // Tie-break by binary depth: prefer cleaner subdivision levels
        int depth = GetBinaryDepthLevel(i);
        bool isBetter = (total > bestTotal + 0.001)  // Clear win
                     || (MathAbs(total - bestTotal) <= 0.001 && depth > bestDepth);  // Tie -> higher depth

        if(isBetter) {
            bestTotal = total;
            bestIdx   = i;
            bestDepth = depth;
            result.multiStepScore = sMulti;
            result.patternScore   = sPat;
            result.timeScore      = sTime;
            result.sqrtScore      = sSqrt;
            result.harmonicScore  = sHarm;
            result.historyScore   = sHist;
            result.step3Price     = step3;
            result.step1Price     = CalculateStepNPrice(pA, pB, pC, freq, 1.0);
            result.step5Price     = CalculateStepNPrice(pA, pB, pC, freq, 5.0);
            result.step7Price     = CalculateStepNPrice(pA, pB, pC, freq, 7.0);
            result.matchedSteps   = matchedStepsCount;
            result.patternType    = patternType;
            result.matchWaveIndex = (bestMidIdx >= 0) ? analysis.midpoints[bestMidIdx].waveIndex : -1;
            result.matchLabel     = (bestMidIdx >= 0) ? analysis.midpoints[bestMidIdx].label : "";
            if(bestMidIdx >= 0 && pipSize > 0)
                result.errorPips = MathAbs(step3 - analysis.midpoints[bestMidIdx].price) / pipSize;
            result.confidence = ComputeConfidence(sMulti, sPat, sTime, sSqrt, sHarm, sHist);
        }

        // Track top-N candidates for diagnostics
        FreqCandidate cand;
        cand.index        = i;
        cand.frequency    = freq;
        cand.total        = total;
        cand.sMulti       = sMulti;
        cand.sPat         = sPat;
        cand.sTime        = sTime;
        cand.sSqrt        = sSqrt;
        cand.sHarm        = sHarm;
        cand.sHist        = sHist;
        cand.depth        = depth;
        cand.matchedSteps = matchedStepsCount;
        cand.patternType  = patternType;
        cand.confidence   = ComputeConfidence(sMulti, sPat, sTime, sSqrt, sHarm, sHist);
        cand.matchLabel   = (bestMidIdx >= 0) ? analysis.midpoints[bestMidIdx].label : "";
        cand.errorPips    = (bestMidIdx >= 0 && pipSize > 0) ?
                            MathAbs(step3 - analysis.midpoints[bestMidIdx].price) / pipSize : 0;
        InsertTopN(topN, topCount, cand, FREQ_TOP_N);
    }

    if(bestIdx < 0 || bestTotal < MIN_ACCEPTABLE_SCORE) {
        _LOG_GATE_W Print("[W][FreqOpt] No acceptable frequency found. Best score: ",
                          DoubleToString(bestTotal, 4),
                          " (threshold: ", DoubleToString(MIN_ACCEPTABLE_SCORE, 2), ")");
        return false;
    }

    result.bestIndex     = bestIdx;
    result.bestFrequency = GetFrequencyByIndex(bestIdx);
    result.totalScore    = bestTotal;
    result.isValid       = true;

    // Log top-N candidates for diagnostics (v5.1 format: 6 components + confidence)
    for(int t = 0; t < topCount; t++) {
        string rank = (t == 0) ? ">>> BEST" : ("    #" + IntegerToString(t + 1));
        string stars = (topN[t].confidence >= 0.7) ? "***" :
                       (topN[t].confidence >= 0.4) ? "**" : "*";
        string pat = (topN[t].patternType != "") ? (" [" + topN[t].patternType + "]") : "";
        Print("[FreqOpt] ", rank, ": ",
              DoubleToString(topN[t].frequency, 4), "% [#", topN[t].index, "]",
              " d=", topN[t].depth,
              " | ", DoubleToString(topN[t].total, 3),
              " (MS:", DoubleToString(topN[t].sMulti, 2),
              " P:", DoubleToString(topN[t].sPat, 2),
              " T:", DoubleToString(topN[t].sTime, 2),
              " R:", DoubleToString(topN[t].sSqrt, 2),
              " H:", DoubleToString(topN[t].sHarm, 2),
              " Hi:", DoubleToString(topN[t].sHist, 2), ")",
              " | ", stars, " ", topN[t].matchedSteps, "/4 steps",
              pat,
              " | ", topN[t].matchLabel,
              " err:", DoubleToString(topN[t].errorPips, 1), "p");
    }

    return true;
}

//+------------------------------------------------------------------+
//| Apply optimal frequency to the global state + push to history    |
//+------------------------------------------------------------------+
void ApplyOptimalFrequency(const FrequencyResult &result) {
    if(!result.isValid) return;

    g_th3FreqIndex    = result.bestIndex;
    g_th3FreqOverride = result.bestFrequency;

    // Push to history ring buffer for future coherence scoring
    double abDist = MathAbs(g_abcdPriceB - g_abcdPriceA);
    double bcDist = MathAbs(g_abcdPriceC - g_abcdPriceB);
    double ratioBCab = (abDist > 0) ? bcDist / abDist : 0;
    PushFrequencyHistory(result, abDist, ratioBCab);

    // Persist
    string chartIdStr = GetCachedChartIdStr();
    GlobalVariableSet("Biotak_TH3Freq_" + chartIdStr, g_th3FreqOverride);
    GlobalVariableSet("Biotak_TH3FreqIdx_" + chartIdStr, (double)g_th3FreqIndex);
}

#endif // FREQUENCY_OPTIMIZER_MQH
