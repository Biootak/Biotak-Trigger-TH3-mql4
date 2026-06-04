//+------------------------------------------------------------------+
//| WaveAnalysis.mqh - Wave Data Structures & Analysis               |
//| Core theory: Every reversal is a reaction to a key retracement   |
//| level of a reference wave. Uses Gilmore's three ratio families:  |
//| Harmonic (50%,25%,75%), Geometric (38.2%,61.8%,78.6%), + Gann.  |
//| v5.0: Confluence zone detection — clusters of midpoints from     |
//| multiple waves converging on the same price = high-probability   |
//+------------------------------------------------------------------+
#ifndef WAVE_ANALYSIS_MQH
#define WAVE_ANALYSIS_MQH

#property strict

// Maximum number of reference midpoints to evaluate
// 6 waves × 7 types (50%, Gann, 25%, 75%, 38.2%, 61.8%, 78.6%) = 42, + safety
#define MAX_REFERENCE_MIDPOINTS 48
// Number of primary + compound waves from XABC pattern
#define WAVE_COUNT 6
// Maximum confluence zones to track
#define MAX_CONFLUENCE_ZONES 12
// Minimum midpoints from different waves to form a confluence zone
#define MIN_CONFLUENCE_COUNT 3

//+------------------------------------------------------------------+
//| Single wave data                                                 |
//+------------------------------------------------------------------+
struct WaveData {
    double    startPrice;
    double    endPrice;
    datetime  startTime;
    datetime  endTime;
    double    distance;         // |endPrice - startPrice|
    double    midArithmetic;    // (start + end) / 2
    double    midGann;          // (sqrt(start) + sqrt(end))^2 / 4
    double    quarter25;        // start + 0.25 * (end - start)
    double    quarter75;        // start + 0.75 * (end - start)
    // Gilmore sacred ratios from "Geometry of Markets Vol II" page 11
    // The three ratio families: Geometric(φ), Harmonic(√2), Arithmetic(√3)
    // φ-based retracements are among the most important market reversal levels
    double    fib382;           // start + 0.382 * (end - start) — φ² reciprocal
    double    fib618;           // start + 0.618 * (end - start) — φ reciprocal (Golden Ratio)
    double    fib786;           // start + 0.786 * (end - start) — √φ reciprocal
    int       barDuration;      // bars between start and end
    double    speed;            // distance / barDuration (Gann angle proxy)
    bool      isBullish;        // endPrice > startPrice
    bool      isValid;

    void Reset() {
        startPrice = 0; endPrice = 0;
        startTime = 0;  endTime = 0;
        distance = 0;   midArithmetic = 0; midGann = 0;
        quarter25 = 0;  quarter75 = 0;
        fib382 = 0;     fib618 = 0;   fib786 = 0;
        barDuration = 0; speed = 0;
        isBullish = false; isValid = false;
    }
};

//+------------------------------------------------------------------+
//| Reference midpoint for matching against Step3                    |
//+------------------------------------------------------------------+
struct ReferenceMidpoint {
    double    price;           // The midpoint price level
    int       waveIndex;       // Which wave (0-5) it belongs to
    string    label;           // e.g. "XA-50%", "AB-Gann", "BC-38.2%"
    int       type;            // 0=arithmetic50, 1=gann50, 2=quarter25, 3=quarter75,
                               // 4=fib382, 5=fib618, 6=fib786 (Gilmore sacred φ ratios)
};

//+------------------------------------------------------------------+
//| Confluence Zone — cluster of midpoints from multiple waves at    |
//| similar price levels (Gilmore's "Windows of Opportunity")        |
//| Confluence is the strongest confirmation in technical analysis:  |
//| independent measurements converging = high-probability level     |
//+------------------------------------------------------------------+
struct ConfluenceZone {
    double    centerPrice;     // Weighted average price of cluster members
    double    strength;        // Quality metric: uniqueWaves × uniqueTypes / 6
    int       memberCount;     // Total midpoints in this cluster
    int       uniqueWaves;     // How many different waves contribute
    int       uniqueTypes;     // How many different level types contribute
    double    lowPrice;        // Lower boundary of zone
    double    highPrice;       // Upper boundary of zone
};

//+------------------------------------------------------------------+
//| Full XABC wave analysis result                                   |
//+------------------------------------------------------------------+
struct WaveAnalysisResult {
    // Primary waves
    WaveData  waveXA;          // X → A
    WaveData  waveAB;          // A → B
    WaveData  waveBC;          // B → C

    // Compound waves
    WaveData  waveXB;          // X → B
    WaveData  waveAC;          // A → C
    WaveData  waveXC;          // X → C

    // Input points
    double    priceX, priceA, priceB, priceC;
    datetime  timeX, timeA, timeB, timeC;

    // Overall pattern
    bool      isBullish;       // pB > pA (AB wave direction)
    bool      isValid;

    // Wave ratios (for harmonic scoring)
    double    ratioAB_XA;      // AB.distance / XA.distance
    double    ratioBC_AB;      // BC.distance / AB.distance
    double    timeRatioAB_XA;  // AB.barDuration / XA.barDuration
    double    timeRatioBC_AB;  // BC.barDuration / AB.barDuration

    // Collected reference midpoints
    ReferenceMidpoint midpoints[];
    int       midpointCount;

    // Confluence zones — clusters of converging midpoints
    ConfluenceZone confluenceZones[];
    int       confluenceCount;

    void Reset() {
        waveXA.Reset(); waveAB.Reset(); waveBC.Reset();
        waveXB.Reset(); waveAC.Reset(); waveXC.Reset();
        priceX = 0; priceA = 0; priceB = 0; priceC = 0;
        timeX = 0;  timeA = 0;  timeB = 0;  timeC = 0;
        isBullish = false; isValid = false;
        ratioAB_XA = 0; ratioBC_AB = 0;
        timeRatioAB_XA = 0; timeRatioBC_AB = 0;
        midpointCount = 0; confluenceCount = 0;
        ArrayResize(midpoints, 0);
        ArrayResize(confluenceZones, 0);
    }
};

//+------------------------------------------------------------------+
//| Calculate Gann geometric midpoint: (√H + √L)² / 4              |
//| Gann's "square root" mean — the true geometric center            |
//+------------------------------------------------------------------+
double CalculateGannMidpoint(double price1, double price2) {
    if(price1 <= 0 || price2 <= 0) return 0;
    double sqrtSum = MathSqrt(price1) + MathSqrt(price2);
    return (sqrtSum * sqrtSum) / 4.0;
}

//+------------------------------------------------------------------+
//| Build a single WaveData from two price/time endpoints            |
//+------------------------------------------------------------------+
void BuildWaveData(WaveData &wave, double p1, datetime t1, double p2, datetime t2) {
    wave.Reset();
    if(p1 <= 0 || p2 <= 0 || t1 <= 0 || t2 <= 0) return;

    wave.startPrice = p1;
    wave.endPrice   = p2;
    wave.startTime  = t1;
    wave.endTime    = t2;
    wave.distance   = MathAbs(p2 - p1);
    wave.isBullish  = (p2 > p1);

    // Arithmetic midpoint
    wave.midArithmetic = (p1 + p2) / 2.0;

    // Gann sqrt midpoint
    wave.midGann = CalculateGannMidpoint(p1, p2);

    // Fractal quarters
    double dir = p2 - p1;  // signed direction
    wave.quarter25 = p1 + 0.25 * dir;
    wave.quarter75 = p1 + 0.75 * dir;

    // Gilmore sacred φ ratios (Geometry of Markets Vol II, page 11)
    // These are the Geometric ratio family: most important retracement/extension levels
    wave.fib382 = p1 + 0.382 * dir;   // φ² reciprocal — key retracement
    wave.fib618 = p1 + 0.618 * dir;   // φ reciprocal — the Golden Ratio
    wave.fib786 = p1 + 0.786 * dir;   // √φ reciprocal — deep retracement

    // Time/speed — iBarShift is native to MT4
    wave.barDuration = iBarShift(Symbol(), Period(), t1) - iBarShift(Symbol(), Period(), t2);
    if(wave.barDuration < 0) wave.barDuration = -wave.barDuration;
    if(wave.barDuration < 1) wave.barDuration = 1;
    wave.speed = wave.distance / (double)wave.barDuration;

    wave.isValid = (wave.distance > GetCachedPoint() * ABCD_MIN_DISTANCE_POINTS);
}

//+------------------------------------------------------------------+
//| Add a reference midpoint to the analysis result                  |
//+------------------------------------------------------------------+
void AddReferenceMidpoint(WaveAnalysisResult &result, double price, int waveIdx, 
                          const string lbl, int type) {
    if(price <= 0) return;
    int idx = result.midpointCount;
    if(idx >= MAX_REFERENCE_MIDPOINTS) return;

    result.midpoints[idx].price     = price;
    result.midpoints[idx].waveIndex = waveIdx;
    result.midpoints[idx].label     = lbl;
    result.midpoints[idx].type      = type;
    result.midpointCount = idx + 1;
}

//+------------------------------------------------------------------+
//| Collect all reference midpoints from 6 waves × 4 levels         |
//| = up to 24 midpoints                                             |
//+------------------------------------------------------------------+
void CollectReferenceMidpoints(WaveAnalysisResult &result) {
    // PERF: Pre-allocate to max capacity — avoids up to 42 incremental ArrayResize calls
    ArrayResize(result.midpoints, MAX_REFERENCE_MIDPOINTS);
    // Wave names for labels
    string waveNames[6];
    waveNames[0] = "XA"; waveNames[1] = "AB"; waveNames[2] = "BC";
    waveNames[3] = "XB"; waveNames[4] = "AC"; waveNames[5] = "XC";

    // Type suffixes — 7 retracement levels per wave
    string typeSuffix[7];
    typeSuffix[0] = "50%"; typeSuffix[1] = "Gann"; typeSuffix[2] = "25%";
    typeSuffix[3] = "75%"; typeSuffix[4] = "38.2%"; typeSuffix[5] = "61.8%";
    typeSuffix[6] = "78.6%";

    // All 6 waves as array of pointers (MQL5 doesn't support, so access directly)
    WaveData waves[6];
    waves[0] = result.waveXA;
    waves[1] = result.waveAB;
    waves[2] = result.waveBC;
    waves[3] = result.waveXB;
    waves[4] = result.waveAC;
    waves[5] = result.waveXC;

    for(int w = 0; w < WAVE_COUNT; w++) {
        if(!waves[w].isValid) continue;

        // Arithmetic 50%
        AddReferenceMidpoint(result, waves[w].midArithmetic, w,
                             waveNames[w] + "-" + typeSuffix[0], 0);
        // Gann 50%
        AddReferenceMidpoint(result, waves[w].midGann, w,
                             waveNames[w] + "-" + typeSuffix[1], 1);
        // 25%
        AddReferenceMidpoint(result, waves[w].quarter25, w,
                             waveNames[w] + "-" + typeSuffix[2], 2);
        // 75%
        AddReferenceMidpoint(result, waves[w].quarter75, w,
                             waveNames[w] + "-" + typeSuffix[3], 3);
        // 38.2% — Gilmore Geometric (φ² reciprocal)
        AddReferenceMidpoint(result, waves[w].fib382, w,
                             waveNames[w] + "-" + typeSuffix[4], 4);
        // 61.8% — Gilmore Geometric (Golden Ratio)
        AddReferenceMidpoint(result, waves[w].fib618, w,
                             waveNames[w] + "-" + typeSuffix[5], 5);
        // 78.6% — Gilmore Geometric (√φ reciprocal)
        AddReferenceMidpoint(result, waves[w].fib786, w,
                             waveNames[w] + "-" + typeSuffix[6], 6);
    }
}

//+------------------------------------------------------------------+
//| Detect Confluence Zones — clusters of midpoints from multiple    |
//| waves converging at the same price level                         |
//| Based on Gilmore's "Windows of Opportunity" (pages 84-97):      |
//| When 3+ independent reference levels cluster within ±0.5% of AB |
//| distance, that price zone has extraordinary reversal probability |
//|                                                                  |
//| Algorithm: Sort midpoints by price → sliding window → find      |
//| clusters of ≥3 from ≥2 different waves within tolerance.        |
//| Strength = uniqueWaves × uniqueTypes (max: 6 × 7 = 42)         |
//+------------------------------------------------------------------+
void DetectConfluenceZones(WaveAnalysisResult &result, double abDistance) {
    result.confluenceCount = 0;
    if(result.midpointCount < MIN_CONFLUENCE_COUNT || abDistance <= 0) return;

    // FIX Bug 5: Widened from ±0.5% to ±2% of AB distance
    double tolerance = abDistance * 0.02;
    if(tolerance <= 0) return;

    // Sort midpoints by price (insertion sort — small array)
    int sortedIdx[];
    ArrayResize(sortedIdx, result.midpointCount);
    for(int i = 0; i < result.midpointCount; i++) sortedIdx[i] = i;

    for(int i = 1; i < result.midpointCount; i++) {
        int key = sortedIdx[i];
        double keyPrice = result.midpoints[key].price;
        int j = i - 1;
        while(j >= 0 && result.midpoints[sortedIdx[j]].price > keyPrice) {
            sortedIdx[j + 1] = sortedIdx[j];
            j--;
        }
        sortedIdx[j + 1] = key;
    }

    // Track which midpoints are already assigned to a zone
    bool assigned[];
    ArrayResize(assigned, result.midpointCount);
    ArrayInitialize(assigned, false);

    ArrayResize(result.confluenceZones, MAX_CONFLUENCE_ZONES);

    // Sliding window: for each unassigned midpoint, expand window while within tolerance
    for(int i = 0; i < result.midpointCount && result.confluenceCount < MAX_CONFLUENCE_ZONES; i++) {
        int si = sortedIdx[i];
        if(assigned[si]) continue;

        double basePrice = result.midpoints[si].price;
        if(basePrice <= 0) continue;

        // Collect all midpoints within ±tolerance of this base
        int clusterMembers[];
        int clusterSize = 0;
        ArrayResize(clusterMembers, result.midpointCount);

        for(int j = i; j < result.midpointCount; j++) {
            int sj = sortedIdx[j];
            if(assigned[sj]) continue;
            double diff = result.midpoints[sj].price - basePrice;
            if(diff > 2.0 * tolerance) break;  // Sorted, so no more within range
            if(diff <= 2.0 * tolerance) {
                clusterMembers[clusterSize++] = sj;
            }
        }

        if(clusterSize < MIN_CONFLUENCE_COUNT) continue;

        // Count unique waves and unique types in this cluster
        bool wavesSeen[6];  // WAVE_COUNT
        bool typesSeen[7];  // 7 midpoint types
        ArrayInitialize(wavesSeen, false);
        ArrayInitialize(typesSeen, false);

        double priceSum = 0;
        double lowP = DBL_MAX, highP = 0;

        for(int k = 0; k < clusterSize; k++) {
            int idx = clusterMembers[k];
            wavesSeen[result.midpoints[idx].waveIndex] = true;
            typesSeen[result.midpoints[idx].type] = true;
            priceSum += result.midpoints[idx].price;
            if(result.midpoints[idx].price < lowP) lowP = result.midpoints[idx].price;
            if(result.midpoints[idx].price > highP) highP = result.midpoints[idx].price;
        }

        int uniqueWaves = 0, uniqueTypes = 0;
        for(int w = 0; w < 6; w++) if(wavesSeen[w]) uniqueWaves++;
        for(int t = 0; t < 7; t++) if(typesSeen[t]) uniqueTypes++;

        // Require midpoints from at least 2 different waves
        if(uniqueWaves < 2) continue;

        // Build confluence zone
        int zIdx = result.confluenceCount;
        result.confluenceZones[zIdx].centerPrice  = priceSum / (double)clusterSize;
        result.confluenceZones[zIdx].memberCount   = clusterSize;
        result.confluenceZones[zIdx].uniqueWaves   = uniqueWaves;
        result.confluenceZones[zIdx].uniqueTypes   = uniqueTypes;
        result.confluenceZones[zIdx].lowPrice      = lowP;
        result.confluenceZones[zIdx].highPrice     = highP;
        // Strength: normalized product of diversity dimensions
        result.confluenceZones[zIdx].strength = (double)(uniqueWaves * uniqueTypes) / 12.0;
        if(result.confluenceZones[zIdx].strength > 1.0)
            result.confluenceZones[zIdx].strength = 1.0;

        result.confluenceCount++;

        // Mark members as assigned so they don't form overlapping zones
        for(int k = 0; k < clusterSize; k++) {
            assigned[clusterMembers[k]] = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Get confluence zone strength at a specific price level           |
//| Returns 0 if price is not in any confluence zone                 |
//+------------------------------------------------------------------+
double GetConfluenceStrengthAtPrice(const WaveAnalysisResult &analysis, double price) {
    double bestStrength = 0;
    for(int i = 0; i < analysis.confluenceCount; i++) {
        if(price >= analysis.confluenceZones[i].lowPrice &&
           price <= analysis.confluenceZones[i].highPrice) {
            if(analysis.confluenceZones[i].strength > bestStrength)
                bestStrength = analysis.confluenceZones[i].strength;
        }
    }
    return bestStrength;
}

//+------------------------------------------------------------------+
//| Main analysis: build all waves from XABC points and collect      |
//| all reference midpoints                                          |
//+------------------------------------------------------------------+
bool AnalyzeWaves(double pX, datetime tX, double pA, datetime tA,
                  double pB, datetime tB, double pC, datetime tC,
                  WaveAnalysisResult &result) {
    result.Reset();

    // Validate inputs
    if(pX <= 0 || pA <= 0 || pB <= 0 || pC <= 0) return false;
    if(tX <= 0 || tA <= 0 || tB <= 0 || tC <= 0) return false;

    // Store input points
    result.priceX = pX; result.priceA = pA;
    result.priceB = pB; result.priceC = pC;
    result.timeX  = tX; result.timeA  = tA;
    result.timeB  = tB; result.timeC  = tC;

    // Build primary waves
    BuildWaveData(result.waveXA, pX, tX, pA, tA);
    BuildWaveData(result.waveAB, pA, tA, pB, tB);
    BuildWaveData(result.waveBC, pB, tB, pC, tC);

    // Build compound waves
    BuildWaveData(result.waveXB, pX, tX, pB, tB);
    BuildWaveData(result.waveAC, pA, tA, pC, tC);
    BuildWaveData(result.waveXC, pX, tX, pC, tC);

    // Validate critical waves
    if(!result.waveAB.isValid) return false;

    result.isBullish = result.waveAB.isBullish;

    // Calculate ratios
    if(result.waveXA.isValid && result.waveXA.distance > 0) {
        result.ratioAB_XA     = result.waveAB.distance / result.waveXA.distance;
        result.timeRatioAB_XA = (double)result.waveAB.barDuration / (double)result.waveXA.barDuration;
    }
    if(result.waveAB.distance > 0) {
        result.ratioBC_AB     = result.waveBC.distance / result.waveAB.distance;
        result.timeRatioBC_AB = (double)result.waveBC.barDuration / (double)result.waveAB.barDuration;
    }

    // Collect ALL reference midpoints (42 potential)
    CollectReferenceMidpoints(result);

    // Detect confluence zones — clusters of converging midpoints
    DetectConfluenceZones(result, result.waveAB.distance);

    result.isValid = true;
    return true;
}

#endif // WAVE_ANALYSIS_MQH
