  #property copyright "Copyright 2025, Biotak Project"
#property link      "https://www.mql5.com"
#property strict

#ifndef LEVEL_PIPELINE_MQH
#define LEVEL_PIPELINE_MQH

//+------------------------------------------------------------------+
//| LEVEL PIPELINE   Zone-First Architecture                         |
//|                                                                  |
//| PHILOSOPHY: Zone is the PRIMARY entity. Lines (triggers) are     |
//| derived from zone boundaries. Zones define the structure;        |
//| lines are visual markers at the edges where zones meet.          |
//|                                                                  |
//| PIPELINE STAGES:                                                 |
//|   Stage 1: CalculateLevels    SCalculatedLevel[]                 |
//|   Stage 2: ClassifyLevels     update classification in-place     |
//|   Stage 3: BuildZones         SZoneDefinition[] (PRIMARY)        |
//|   Stage 4: DeriveTriggers     STriggerLine[] (from zone bounds)  |
//|   Stage 5: RenderAll          MT5 objects (zones first, lines)   |
//|                                                                  |
//| BENEFITS:                                                        |
//|   - Zones are always geometrically correct (no state mutation)   |
//|   - Render order is independent of calculation order             |
//|   - Viewport culling only affects rendering, not geometry        |
//|   - New modes only need to implement Stage 1 (price calc)        |
//|   - Testable without MT5 (stages 1-4 are pure data)             |
//+------------------------------------------------------------------+

#include "ConstantsAndEnums.mqh"

//+------------------------------------------------------------------+
//| STAGE 1 OUTPUT: Raw calculated level                             |
//+------------------------------------------------------------------+
struct SCalculatedLevel {
    double price;           // Level price
    int    logicalStep;     // Original step number (1, 2, 3, ...)
    bool   isMidpoint;      // true = this is the center/anchor level (step 0)
    int    direction;       // +1 = above midpoint, -1 = below, 0 = midpoint
};

//+------------------------------------------------------------------+
//| STAGE 2 OUTPUT: Classification result for a level                |
//+------------------------------------------------------------------+
struct SLevelClassified {
    double price;
    int    logicalStep;
    bool   isMidpoint;
    int    direction;
    
    // Classification results
    int    structureLevel;  // 0 = not structure, 1-5 = L1-L5
    bool   isTrigger;       // true = trigger level (not structure)
    bool   isStructure;     // true = any structure level (L1-L5)
    color  levelColor;
    ENUM_LINE_STYLE levelStyle;
    int    levelWidth;
    color  zoneColor;       // Color for zone touching this level
    string labelText;
};

//+------------------------------------------------------------------+
//| STAGE 3 OUTPUT: Zone definition (PRIMARY ENTITY)                 |
//|                                                                  |
//| Each zone is centered ON a level price.                          |
//| renderTop/renderBottom define actual visual extent.              |
//+------------------------------------------------------------------+
struct SZoneDefinition {
    string name;            // Object name for this zone
    double midPrice;        // Center price (= level price)
    double renderTop;       // Visual top (midPrice + zoneHeight)
    double renderBottom;    // Visual bottom (midPrice - zoneHeight)
    int    logicalStep;     // Step number of the level this zone sits on
    int    direction;       // +1 = above midpoint, -1 = below, 0 = midpoint
    int    zoneIndex;       // Sequential zone index in this direction
    bool   isStructure;     // Structural level zone
    bool   isTrigger;       // Trigger subdivision zone
    color  zoneColor;       // Zone color
    int    transparency;
    ENUM_ZONE_STYLE style;
    // P-UI-62: the BAND and its EDGE are two halves of one picture, not one flag.
    //   FILLED   -> band, no edge      EMPTY -> edge, no band      OUTLINED -> both
    bool   filled;          // draw the band (filled rectangle)
    bool   outline;         // draw the edge (three border segments)
    bool   inViewport;      // false = skip render, geometry is valid
};

//+------------------------------------------------------------------+
//| STAGE 4 OUTPUT: Trigger line (DERIVED from zone boundaries)      |
//|                                                                  |
//| A trigger line sits at the boundary between two adjacent zones.  |
//| Its properties come from the dominant zone it borders.           |
//+------------------------------------------------------------------+
struct STriggerLine {
    string name;            // Object name for this line
    double price;           // = zone boundary price
    int    logicalStep;
    int    direction;       // +1 = above, -1 = below, 0 = midpoint
    color  lineColor;
    ENUM_LINE_STYLE lineStyle;
    int    lineWidth;
    string tooltip;
    color  clr;
    string labelText;
    bool   inViewport;      // false = skip render
    bool   isMidpoint;
    bool   setBack;         // OBJPROP_BACK value (mode-specific)
    int    zOrder;          // OBJPROP_ZORDER value (mode-specific)
};

//+------------------------------------------------------------------+
//| MODE CONFIGURATION: All mode-specific settings in one place      |
//+------------------------------------------------------------------+
struct SModeConfig {
    string modeName;        // "SSLS", "M", "TP", "Combo", "Factor", "MEq", "TH"
    string objectPrefix;    // Full prefix including inpObjectPrefix
    
    // Fallback colors (when not structure/trigger)
    color  fallbackColor;
    ENUM_LINE_STYLE fallbackStyle;
    int    fallbackWidth;
    
    // Secondary fallback (for alternating modes like SSLS)
    color  fallbackColor2;
    ENUM_LINE_STYLE fallbackStyle2;
    int    fallbackWidth2;
    
    // Midpoint styling
    color  midpointColor;
    ENUM_LINE_STYLE midpointStyle;
    int    midpointWidth;
    
    // Zone configuration
    bool   zonesEnabled;
    int    zoneTransparency;
    double zoneHeightPercent;
    color  zoneDefaultColor;
    ENUM_ZONE_STYLE zoneStyle;
    
    // Rendering flags
    bool   useObjPropBack;  // Set OBJPROP_BACK on lines (Factor modes)
    int    zOrder;          // OBJPROP_ZORDER value (Factor = 1, others = 0)
    bool   hideLineWhenTriggerOnly; // RETIRED (always false): lines are never
                                    // gated by the trigger switch — RenderZones
                                    // alone hides the trigger zones
    bool   useStepFilter;   // false for MEq (draws every step)
    
    // Price boundaries
    bool   boundByHistorical; // true = stop at g_highestHigh/g_lowestLow
    double maxPrice;        // Upper price boundary (0 = no limit)
    double minPrice;        // Lower price boundary (0 = no limit)
};

//+------------------------------------------------------------------+
//| STEP MODE: How price is computed at each level                   |
//+------------------------------------------------------------------+
enum ENUM_LEVEL_STEP_MODE {
    LEVEL_STEP_UNIFORM = 0,       // price = center   stepSize   N (no drift)
    LEVEL_STEP_CUMULATIVE = 1     // price = center   cumulative(steps[N % count])
};

//+------------------------------------------------------------------+
//| CLASSIFY MODE: Which Stage-2 classifier to use                   |
//+------------------------------------------------------------------+
enum ENUM_CLASSIFY_MODE {
    CLASSIFY_STANDARD = 0,        // Standard structure/trigger classification
    CLASSIFY_ALTERNATING = 1      // SSLS: alternating SS/LS fallback colors
};

//+------------------------------------------------------------------+
//| PIPELINE RESULT: Complete output ready for rendering             |
//+------------------------------------------------------------------+
struct SPipelineResult {
    int    zoneCount;
    int    lineCount;
    bool   success;
    string errorMessage;
};

//+------------------------------------------------------------------+
//| STAGE 1: Unified level price calculator                          |
//|                                                                  |
//| Handles ALL modes via stepMode enum:                             |
//|   LEVEL_STEP_UNIFORM:    price = center   step   N              |
//|   LEVEL_STEP_CUMULATIVE: price = center     steps[i % count]    |
//|                                                                  |
//| KEY PRINCIPLE: ALL levels are calculated. Every step is always   |
//| included   there is no filtering/skipping.                       |
//+------------------------------------------------------------------+
int CalculateLevels(
    const double centerPrice,
    const double &stepSizes[],
    const int stepSizeCount,
    const ENUM_LEVEL_STEP_MODE stepMode,
    const bool sslsLongFirst,
    const int maxLevelsAbove,
    const int maxLevelsBelow,
    const bool boundByHistorical,
    const double maxPrice,
    const double minPrice,
    SCalculatedLevel &levels[],
    int &maxStepOut)
{
    maxStepOut = 0;
    // P-UI-57: `<= 0` IS NaN-BLIND — every comparison against NaN is false, so a
    // poisoned price/step passed straight through the guards that were supposed to
    // stop it and turned every derived level into NaN (NaN prices then reach
    // `ObjectSetDouble`, where MT4 stores a value no comparison can reason about:
    // invisible objects, labels reading `nan`, a level family that never matches
    // its own signature). `MathIsValidNumber` is the only test that catches it, and
    // it is here - at the ONE entry every calculating mode goes through - rather
    // than at the dozens of consumers.
    if(!MathIsValidNumber(centerPrice) || centerPrice <= 0 || stepSizeCount < 1) return 0;
    for(int s = 0; s < stepSizeCount; s++) {
        if(!MathIsValidNumber(stepSizes[s]) || stepSizes[s] <= 0) return 0;
    }
    
    int safeMaxAbove = MathMin(maxLevelsAbove, MAX_SAFE_LEVELS);
    int safeMaxBelow = MathMin(maxLevelsBelow, MAX_SAFE_LEVELS);
    if(safeMaxAbove < 1) safeMaxAbove = 1;
    if(safeMaxBelow < 1) safeMaxBelow = 1;
    
    int maxTotal = (safeMaxAbove + safeMaxBelow) * 2 + 1;
    ArrayResize(levels, maxTotal, 64);
    int count = 0;
    
    // Midpoint (always first). In SS/LS mode the short step is the zone
    // width, while the first center-to-center interval is user-selectable.
    double offset = (stepMode == LEVEL_STEP_CUMULATIVE && stepSizeCount > 1 && sslsLongFirst)
                    ? (stepSizes[1] * 0.5) : (stepSizes[0] * 0.5);
    double shiftedCenter = centerPrice + offset;
    
    levels[count].price = shiftedCenter;
    levels[count].logicalStep = 0;
    levels[count].isMidpoint = true;
    levels[count].direction = 0;
    count++;
    
    // --- Above levels ---
    int drawnAbove = 0;
    int logicalStep = 1;
    double cumAbove = 0;
    int maxIterations = safeMaxAbove * 2;
    int iterations = 0;
    
    while(drawnAbove < safeMaxAbove && iterations < maxIterations) {
        iterations++;
        double price;
        if(stepMode == LEVEL_STEP_UNIFORM) {
            price = shiftedCenter + (stepSizes[0] * logicalStep);
        } else {
            // CUMULATIVE: alternate SS/LS. The first interval is controlled
            // by sslsLongFirst; subsequent intervals alternate strictly.
            int sequenceIndex = (sslsLongFirst && stepSizeCount > 1) ? 1 : 0;
            int parity = (logicalStep - 1) % 2;
            int selectedIndex = (parity == 0) ? sequenceIndex : ((sequenceIndex + 1) % stepSizeCount);
            double dist = stepSizes[selectedIndex];
            cumAbove += dist;
            price = shiftedCenter + cumAbove;
        }
        
        // Price boundary check
        if(boundByHistorical && maxPrice > 0 && price > maxPrice) break;
        
        levels[count].price = price;
        levels[count].logicalStep = logicalStep;
        levels[count].isMidpoint = false;
        levels[count].direction = 1;
        count++;
        
        drawnAbove++;
        logicalStep++;
    }
    
    // --- Below levels ---
    int drawnBelow = 0;
    logicalStep = 1;
    double cumBelow = 0;
    maxIterations = safeMaxBelow * 2;
    iterations = 0;
    
    while(drawnBelow < safeMaxBelow && iterations < maxIterations) {
        iterations++;
        double price;
        if(stepMode == LEVEL_STEP_UNIFORM) {
            price = shiftedCenter - (stepSizes[0] * logicalStep);
        } else {
            int sequenceIndex = (sslsLongFirst && stepSizeCount > 1) ? 1 : 0;
            int parity = (logicalStep - 1) % 2;
            int selectedIndex = (parity == 0) ? sequenceIndex : ((sequenceIndex + 1) % stepSizeCount);
            double dist = stepSizes[selectedIndex];
            cumBelow += dist;
            price = shiftedCenter - cumBelow;
        }
        
        // Price boundary check
        if(boundByHistorical && minPrice > 0 && price < minPrice) break;
        if(price <= 0) break;
        
        levels[count].price = price;
        levels[count].logicalStep = logicalStep;
        levels[count].isMidpoint = false;
        levels[count].direction = -1;
        count++;
        
        drawnBelow++;
        logicalStep++;
    }
    
    // PERF: maxStep is known   drawnAbove and drawnBelow track the actual max logicalStep
    maxStepOut = (drawnAbove > drawnBelow) ? drawnAbove : drawnBelow;
    ArrayResize(levels, count);
    return count;
}

//+------------------------------------------------------------------+
//| HELPER: Get descriptive label text for a level                   |
//+------------------------------------------------------------------+
string GetLabelTextForLevel(const SLevelClassified &level, const int baseMultiplier) {
    if(level.isMidpoint) return "Midpoint";
    
    string direction = (level.direction > 0) ? "+" : "-";
    
    if(level.structureLevel > 0) {
        return StringFormat("L%d %s%d", level.structureLevel, direction, level.logicalStep);
    }
    
    // For trigger subdivisions, show distance in base multiplier units if possible
    return StringFormat("%s%d", direction, level.logicalStep);
}

//+------------------------------------------------------------------+
//| STAGE 2: Classify all levels                                     |
//|                                                                  |
//| Structure/trigger identity drives ONLY the zones. ALL lines take |
//| the unified [08.4] appearance via GetLineRenderColor().          |
//+------------------------------------------------------------------+
int ClassifyLevels(
    const SCalculatedLevel &rawLevels[],
    const int rawCount,
    const SModeConfig &config,
    const bool triggerEnabled,
    const int baseMultiplier,
    SLevelClassified &classified[])
{
    ArrayResize(classified, rawCount, 64);
    EnsureIntervalsCache(baseMultiplier);
    
    for(int i = 0; i < rawCount; i++) {
        // Copy base data
        classified[i].price = rawLevels[i].price;
        classified[i].logicalStep = rawLevels[i].logicalStep;
        classified[i].isMidpoint = rawLevels[i].isMidpoint;
        classified[i].direction = rawLevels[i].direction;
        
        // Default classification
        classified[i].structureLevel = 0;
        classified[i].isTrigger = false;
        classified[i].isStructure = false;
        classified[i].levelColor = config.fallbackColor;
        classified[i].levelStyle = config.fallbackStyle;
        classified[i].levelWidth = config.fallbackWidth;
        classified[i].zoneColor = clrNONE;
        classified[i].labelText = "";
        
        int step = rawLevels[i].logicalStep;
        
        // Midpoint classification
        if(rawLevels[i].isMidpoint) {
            color mc; ENUM_LINE_STYLE ms; int mw;
            if(GetPathForLevelOptimized(0, mc, ms, mw, triggerEnabled)) {
                classified[i].levelColor = mc;
                classified[i].levelStyle = ms;
                classified[i].levelWidth = mw;
            } else {
                classified[i].levelColor = config.midpointColor;
                classified[i].levelStyle = config.midpointStyle;
                classified[i].levelWidth = config.midpointWidth;
            }
            classified[i].labelText = GetLabelTextForLevel(classified[i], baseMultiplier);
            continue;
        }
        
        // BASE PLAYER: Structure/Trigger classification.
        // The structure/trigger identity below drives ONLY the zones:
        // structure zones keep their L1-L5 colors, trigger zones keep the
        // trigger color. ALL LINES share ONE appearance (the [08.4] unified
        // line settings) regardless of family, and the trigger overlay
        // switch (inpShowTrigger / T) must NOT restyle lines here — it gates
        // only the trigger zones in RenderZones. Line visibility belongs to
        // the L switch / g_linesVisible alone, never to triggerEnabled.
        classified[i].structureLevel = GetHighestStructureLevel(step, g_cachedIntervals);
        classified[i].isStructure = (classified[i].structureLevel > 0);

        // UNIFIED LINES: every non-midpoint level draws its line with the
        // same [08.4] settings (GetLineRenderColor blends g_lineColor with
        // g_lineTransparency; style/width are inpLineStyle/inpLineWidth).
        classified[i].levelColor = GetLineRenderColor();
        classified[i].levelStyle = inpLineStyle;
        classified[i].levelWidth = inpLineWidth;
        if(!classified[i].isStructure) {
            classified[i].isTrigger = true;
        }

        // Zone color from level (zones keep their family identity)
        classified[i].zoneColor = GetZoneColorForLevel(step, triggerEnabled, baseMultiplier);
        if(classified[i].zoneColor == clrNONE) {
            // Trigger-subdivision zones fall back to the trigger zone color
            // (NOT the unified line color — zones and lines are independent).
            classified[i].zoneColor = GetTriggerRenderColor();
        }
        
        // Populate label text
        classified[i].labelText = GetLabelTextForLevel(classified[i], baseMultiplier);
    }
    
    return rawCount;
}

//+------------------------------------------------------------------+
//| STAGE 2 VARIANT: Classify with alternating fallback (SSLS)       |
//|                                                                  |
//| Lines are unified (see ClassifyLevels): every line — structure or|
//| trigger subdivision — shares the [08.4] line appearance, so there|
//| is no per-family line override here. This variant is kept for    |
//| signature compatibility and delegates to the standard classifier;|
//| the SS/LS order flag (lsFirst) still drives the step geometry in |
//| Stage 1 (CalculateLevels), and lsFirst is panel-editable.        |
//+------------------------------------------------------------------+
int ClassifyLevelsAlternating(
    const SCalculatedLevel &rawLevels[],
    const int rawCount,
    const SModeConfig &config,
    const bool triggerEnabled,
    const int baseMultiplier,
    const bool lsFirst,
    SLevelClassified &classified[])
{
    return ClassifyLevels(rawLevels, rawCount, config, triggerEnabled, baseMultiplier, classified);
}

//==============================================================================
// P-UI-58 — A ZONE BAND MAY NEVER REACH THE LINE FAMILY (minimum gap)
//
// The drawing architecture is: ZONES are centered ON the levels, and the visible
// LINES are drawn at the MIDPOINT between two neighbouring levels
// (`lineMidPrice = (prevPrice + currentPrice) / 2` below). That is what puts a
// line in the clear space between two bands — the "gap" — and the gap exists only
// while the band is SHORTER than half the interval: a band whose half-height
// reaches `interval / 2` touches exactly the line that belongs to it, and any
// rounding then puts the line INSIDE the band. `inpMidZoneHeightPercent` is allowed
// up to 100 (heightPercent 1.0 = the FULL step), which is that boundary case — so a
// control the user may legitimately push to its maximum silently swallows the lines
// it is supposed to sit beside.
//
// P-UI-59 — ONE INTERVAL IS NOT ENOUGH: A BAND HAS TWO NEIGHBOURS.
//
// P-UI-58 clamped a band with the interval it was BUILT from, which is only ever
// ONE of the two midpoint lines that bracket it. In SS/LS mode the two are not
// equal (the steps alternate short/long, so a level routinely has a SHORT interval
// on one side and a LONG one on the other), and a band clamped by the long side
// still reached the midpoint line of the short side. 100% height in SS/LS: the
// band half-height is `min(ss, ls) * 0.5 = ss/2` and the line in the ss interval
// sits at exactly `ss/2` — the line lands ON the band edge and renders inside it.
// That is the reported «خط میآید داخل زون». The invariant belongs to the LINE, not
// to the band: the line at `interval/2` needs the zones on BOTH of its ends to stay
// clear, so a band is clamped by the NEARER of its two intervals.
//
// The invariant is enforced where the band is BUILT, from the interval the band
// actually sits in (never from the "fixed" step, which in SS/LS mode is not the
// interval), and it keeps ZONE_MIN_GAP_RATIO of the half-interval clear. Every
// setting at or below `2 × (1 − ratio) = 80%` is pixel-identical (the factory
// default is 33%), so a chart changes only where it would otherwise violate the
// invariant. Cost: three compares, no work in the normal case.
//==============================================================================
#define ZONE_MIN_GAP_RATIO 0.20

double ClampZoneHalfHeight(const double wantedHalfHeight, const double neighbourInterval)
{
    if(!MathIsValidNumber(neighbourInterval) || neighbourInterval <= 0.0) return wantedHalfHeight;
    double ceiling = neighbourInterval * 0.5 * (1.0 - ZONE_MIN_GAP_RATIO);
    if(ceiling <= 0.0) return wantedHalfHeight;
    return (wantedHalfHeight > ceiling) ? ceiling : wantedHalfHeight;
}

// The two-sided form. `stepBelow` / `stepAbove` are the intervals on the two sides
// of the band; 0 means "no such neighbour" (the outermost level), which is not a
// constraint. Both are validated before the comparison because a NaN would make
// `stepAbove < bound` false and quietly drop the real constraint (P-UI-57).
double ClampZoneHalfHeightBoth(const double wantedHalfHeight,
                               const double stepBelow,
                               const double stepAbove)
{
    double bound = 0.0;
    if(MathIsValidNumber(stepBelow) && stepBelow > 0.0) bound = stepBelow;
    if(MathIsValidNumber(stepAbove) && stepAbove > 0.0 &&
       (bound <= 0.0 || stepAbove < bound)) bound = stepAbove;
    return ClampZoneHalfHeight(wantedHalfHeight, bound);
}

//+------------------------------------------------------------------+
//| STAGE 3+4 (MERGED): Build zones AND derive midpoint lines        |
//|                                                                  |
//| Single pass over classified levels produces both zones and lines.|
//| Zone = centered ON each level price.                             |
//| Line = midpoint between consecutive zones (between-zone marker). |
//|                                                                  |
//| This eliminates the duplicate 2-pass iteration that existed      |
//| when BuildZones and DeriveTriggerLines were separate functions.  |
//|                                                                  |
//| With base multiplier N per structural interval:                  |
//|   Zones: N+1 (2 structure + N-1 trigger)                        |
//|   Lines: N (midpoint markers between zones)                     |
//|                                                                  |
//| EDGE CASE: If midpoint has no neighbors (aboveCount=0 AND       |
//| belowCount=0), we use a fallback zone height based on the       |
//| symbol's point value to prevent silent invisible midpoint.       |
//+------------------------------------------------------------------+
void BuildZonesAndLines(
    const SLevelClassified &classified[],
    const int classifiedCount,
    const SModeConfig &config,
    const double vpTop,
    const double vpBottom,
    const double fixedZoneStepSize,
    SZoneDefinition &zones[],
    int &zoneCount,
    STriggerLine &lines[],
    int &lineCount)
{
    zoneCount = 0;
    lineCount = 0;
    
    // PERF: Single-pass separation using pre-allocated static arrays
    // Avoids two full iterations over classifiedCount and repeated ArrayResize
    static SLevelClassified s_aboveLevels[];
    static SLevelClassified s_belowLevels[];
    static int s_aboveCapacity = 0;
    static int s_belowCapacity = 0;
    SLevelClassified midLevel;
    midLevel.price = 0;
    midLevel.isMidpoint = false;
    bool hasMid = false;
    
    // Ensure capacity (only grows, never shrinks   eliminates per-frame allocation)
    if(s_aboveCapacity < classifiedCount) {
        ArrayResize(s_aboveLevels, classifiedCount, 64);
        s_aboveCapacity = classifiedCount;
    }
    if(s_belowCapacity < classifiedCount) {
        ArrayResize(s_belowLevels, classifiedCount, 64);
        s_belowCapacity = classifiedCount;
    }
    
    // Single pass: count AND collect simultaneously — and COMPACT.
    // P-UI-59: a level that does not ADVANCE the sequence (a duplicate price, or a
    // non-ordered one) used to be skipped by a `continue` INSIDE each build loop,
    // which left that loop's `prevPrice` pointing at the skipped level and made "the
    // level after this one" unknowable without a forward scan. Dropping it here
    // instead leaves s_aboveLevels strictly ascending and s_belowLevels strictly
    // descending, so i-1 / i+1 ARE the two neighbours of level i — which is exactly
    // what the two-sided gap clamp needs. Same arrays, still one pass, and the build
    // loops lose a branch each.
    int aboveCount = 0, belowCount = 0;
    for(int i = 0; i < classifiedCount; i++) {
        if(classified[i].isMidpoint) { hasMid = true; midLevel = classified[i]; continue; }
        double price = classified[i].price;
        if(!MathIsValidNumber(price) || price <= 0.0) continue;   // P-UI-57: never carry a non-finite price
        if(classified[i].direction > 0) {
            if(aboveCount > 0 && price <= s_aboveLevels[aboveCount - 1].price) continue;
            s_aboveLevels[aboveCount] = classified[i]; aboveCount++;
        } else if(classified[i].direction < 0) {
            if(belowCount > 0 && price >= s_belowLevels[belowCount - 1].price) continue;
            s_belowLevels[belowCount] = classified[i]; belowCount++;
        }
    }
    
    // Pre-allocate output arrays (max possible sizes)
    int maxZones = (hasMid ? 1 : 0) + aboveCount + belowCount;
    int maxLines = aboveCount + belowCount;
    if(config.zonesEnabled) ArrayResize(zones, maxZones, 64);
    ArrayResize(lines, maxLines, 64);
    
    int zIdx = 0, lIdx = 0;
    
    // --- MIDPOINT ZONE (step 0) ---
    if(hasMid && config.zonesEnabled) {
        double neighborDist = 0;
        if(aboveCount > 0) {
            neighborDist = s_aboveLevels[0].price - midLevel.price;
        } else if(belowCount > 0) {
            neighborDist = midLevel.price - s_belowLevels[0].price;
        }
        // Edge case fix: no neighbors - use 100 points as fallback height
        if(neighborDist <= 0) {
            neighborDist = GetCachedPoint() * 100;
        }
        double zoneStepSize = (fixedZoneStepSize > 0) ? fixedZoneStepSize : neighborDist;
        // P-UI-58/59: `neighborDist` IS the nearer of the two neighbour intervals,
        // so this call already is the two-sided clamp the siblings below need — the
        // midpoint line above/below the centre zone is what must stay clear.
        double zoneHeight = ClampZoneHalfHeight(zoneStepSize * config.zoneHeightPercent * 0.5,
                                                neighborDist);
        
        zones[zIdx].name = config.objectPrefix + config.modeName + "_Zone_Center_0";
        zones[zIdx].midPrice = midLevel.price;
        zones[zIdx].renderTop = NormalizeDouble(midLevel.price + zoneHeight, GetCachedDigits());
        zones[zIdx].renderBottom = NormalizeDouble(midLevel.price - zoneHeight, GetCachedDigits());
        zones[zIdx].logicalStep = 0;
        zones[zIdx].direction = 0;
        zones[zIdx].zoneIndex = 0;
        zones[zIdx].isStructure = true;
        zones[zIdx].isTrigger = false;
        zones[zIdx].zoneColor = config.zoneDefaultColor;
        zones[zIdx].transparency = config.zoneTransparency;
        zones[zIdx].style = config.zoneStyle;
        zones[zIdx].filled  = (config.zoneStyle != ZONE_STYLE_BOX_EMPTY);     // P-UI-62
        zones[zIdx].outline = (config.zoneStyle != ZONE_STYLE_BOX_FILLED);    // P-UI-62
        zones[zIdx].inViewport = (zones[zIdx].renderTop >= vpBottom && 
                       zones[zIdx].renderBottom <= vpTop);
        zIdx++;
    }
    
    // --- ABOVE DIRECTION: zones on levels + lines between them ---
    double prevPrice = hasMid ? midLevel.price : 0;
    for(int i = 0; i < aboveCount && prevPrice > 0; i++) {
        double currentPrice = s_aboveLevels[i].price;
        double stepSize = currentPrice - prevPrice;
        if(stepSize <= 0) { prevPrice = currentPrice; continue; }   // P-UI-59: cannot fire on a compacted array
        // P-UI-59: the interval ABOVE this level — the second line this band has to
        // stay clear of. 0 = this is the outermost level, so there is no line there.
        double stepAbove = (i + 1 < aboveCount) ? (s_aboveLevels[i + 1].price - currentPrice) : 0.0;
        // In SS/LS mode every zone uses the configured short-step width,
        // regardless of whether this interval is SS or LS.
        double zoneStepSize = (fixedZoneStepSize > 0) ? fixedZoneStepSize : stepSize;
        
        // Line at midpoint between prev and current
        double lineMidPrice = (prevPrice + currentPrice) / 2.0;
        lines[lIdx].name = config.objectPrefix + config.modeName + "_Above_" + 
                           IntegerToString(s_aboveLevels[i].logicalStep);
        lines[lIdx].price = lineMidPrice;
        lines[lIdx].logicalStep = s_aboveLevels[i].logicalStep;
        lines[lIdx].direction = 1;
        lines[lIdx].lineColor = s_aboveLevels[i].levelColor;
        lines[lIdx].lineStyle = s_aboveLevels[i].levelStyle;
        lines[lIdx].lineWidth = s_aboveLevels[i].levelWidth;
        lines[lIdx].clr = s_aboveLevels[i].levelColor;
        lines[lIdx].labelText = s_aboveLevels[i].labelText;
        lines[lIdx].tooltip = "Midpoint +" + IntegerToString(s_aboveLevels[i].logicalStep) + 
            " (" + DoubleToString(lineMidPrice, GetCachedDigits()) + ")";
        lines[lIdx].isMidpoint = false;
        lines[lIdx].setBack = config.useObjPropBack;
        lines[lIdx].zOrder = config.zOrder;
        lines[lIdx].inViewport = (lineMidPrice >= vpBottom && lineMidPrice <= vpTop);
        lIdx++;
        
        // Zone centered on this level
        if(config.zonesEnabled) {
            // P-UI-58/59: the midpoint line below this level is `stepSize / 2` away and
            // the one ABOVE it is `stepAbove / 2` — the band must fit under the NEARER.
            double zoneHeight = ClampZoneHalfHeightBoth(zoneStepSize * config.zoneHeightPercent * 0.5,
                                                        stepSize, stepAbove);
            
            zones[zIdx].name = config.objectPrefix + config.modeName + "_Zone_Above_" + 
                               IntegerToString(s_aboveLevels[i].logicalStep);
            zones[zIdx].midPrice = currentPrice;
            zones[zIdx].renderTop = NormalizeDouble(currentPrice + zoneHeight, GetCachedDigits());
            zones[zIdx].renderBottom = NormalizeDouble(currentPrice - zoneHeight, GetCachedDigits());
            zones[zIdx].logicalStep = s_aboveLevels[i].logicalStep;
            zones[zIdx].direction = 1;
            zones[zIdx].zoneIndex = i;
            zones[zIdx].isStructure = s_aboveLevels[i].isStructure;
            zones[zIdx].isTrigger = s_aboveLevels[i].isTrigger;
            zones[zIdx].zoneColor = (s_aboveLevels[i].zoneColor != clrNONE) ? 
                                     s_aboveLevels[i].zoneColor : config.zoneDefaultColor;
            zones[zIdx].transparency = config.zoneTransparency;
            zones[zIdx].style = config.zoneStyle;
            zones[zIdx].filled  = (config.zoneStyle != ZONE_STYLE_BOX_EMPTY);     // P-UI-62
            zones[zIdx].outline = (config.zoneStyle != ZONE_STYLE_BOX_FILLED);    // P-UI-62
            zones[zIdx].inViewport = (zones[zIdx].renderTop >= vpBottom && 
                                      zones[zIdx].renderBottom <= vpTop);
            zIdx++;
        }
        
        prevPrice = currentPrice;
    }
    
    // --- BELOW DIRECTION: zones on levels + lines between them ---
    prevPrice = hasMid ? midLevel.price : 0;
    for(int i = 0; i < belowCount && prevPrice > 0; i++) {
        double currentPrice = s_belowLevels[i].price;
        double stepSize = prevPrice - currentPrice;
        if(stepSize <= 0) { prevPrice = currentPrice; continue; }   // P-UI-59: cannot fire on a compacted array
        // P-UI-59: the interval BELOW this level (0 = outermost level, no line there).
        double stepBelow = (i + 1 < belowCount) ? (currentPrice - s_belowLevels[i + 1].price) : 0.0;
        // In SS/LS mode every zone uses the configured short-step width.
        double zoneStepSize = (fixedZoneStepSize > 0) ? fixedZoneStepSize : stepSize;
        
        // Line at midpoint between prev and current
        double lineMidPrice = (prevPrice + currentPrice) / 2.0;
        lines[lIdx].name = config.objectPrefix + config.modeName + "_Below_" + 
                           IntegerToString(s_belowLevels[i].logicalStep);
        lines[lIdx].price = lineMidPrice;
        lines[lIdx].logicalStep = s_belowLevels[i].logicalStep;
        lines[lIdx].direction = -1;
        lines[lIdx].lineColor = s_belowLevels[i].levelColor;
        lines[lIdx].lineStyle = s_belowLevels[i].levelStyle;
        lines[lIdx].lineWidth = s_belowLevels[i].levelWidth;
        lines[lIdx].clr = s_belowLevels[i].levelColor;
        lines[lIdx].labelText = s_belowLevels[i].labelText;
        lines[lIdx].tooltip = "Midpoint -" + IntegerToString(s_belowLevels[i].logicalStep) + 
            " (" + DoubleToString(lineMidPrice, GetCachedDigits()) + ")";
        lines[lIdx].isMidpoint = false;
        lines[lIdx].setBack = config.useObjPropBack;
        lines[lIdx].zOrder = config.zOrder;
        lines[lIdx].inViewport = (lineMidPrice >= vpBottom && lineMidPrice <= vpTop);
        lIdx++;
        
        // Zone centered on this level
        if(config.zonesEnabled) {
            // P-UI-58/59: same invariant as the Above branch, both neighbours
            // (`stepSize` is the interval above this level here, `stepBelow` the one below).
            double zoneHeight = ClampZoneHalfHeightBoth(zoneStepSize * config.zoneHeightPercent * 0.5,
                                                        stepBelow, stepSize);
            
            zones[zIdx].name = config.objectPrefix + config.modeName + "_Zone_Below_" + 
                               IntegerToString(s_belowLevels[i].logicalStep);
            zones[zIdx].midPrice = currentPrice;
            zones[zIdx].renderTop = NormalizeDouble(currentPrice + zoneHeight, GetCachedDigits());
            zones[zIdx].renderBottom = NormalizeDouble(currentPrice - zoneHeight, GetCachedDigits());
            zones[zIdx].logicalStep = s_belowLevels[i].logicalStep;
            zones[zIdx].direction = -1;
            zones[zIdx].zoneIndex = i;
            zones[zIdx].isStructure = s_belowLevels[i].isStructure;
            zones[zIdx].isTrigger = s_belowLevels[i].isTrigger;
            zones[zIdx].zoneColor = (s_belowLevels[i].zoneColor != clrNONE) ? 
                                     s_belowLevels[i].zoneColor : config.zoneDefaultColor;
            zones[zIdx].transparency = config.zoneTransparency;
            zones[zIdx].style = config.zoneStyle;
            zones[zIdx].filled  = (config.zoneStyle != ZONE_STYLE_BOX_EMPTY);     // P-UI-62
            zones[zIdx].outline = (config.zoneStyle != ZONE_STYLE_BOX_FILLED);    // P-UI-62
            zones[zIdx].inViewport = (zones[zIdx].renderTop >= vpBottom && 
                                      zones[zIdx].renderBottom <= vpTop);
            zIdx++;
        }
        
        prevPrice = currentPrice;
    }
    
    // Trim output arrays
    if(config.zonesEnabled) ArrayResize(zones, zIdx);
    ArrayResize(lines, lIdx);
    zoneCount = zIdx;
    lineCount = lIdx;
}

//+------------------------------------------------------------------+
//| STAGE 5a: Render zones (FIRST   zones are primary)               |
//|                                                                  |
//| Creates/updates MT5 rectangle objects for each zone.             |
//| Handles all zone styles: Lines, Filled Box, Empty Box, Hidden.   |
//+------------------------------------------------------------------+
void SetPipelineObjectTimeframesIfExists(const string name, const long timeframes)
{
    // PERF FIX: Check object cache first to skip ObjectFind MT4 syscall when object is known absent.
    // ObjectFind is a slow kernel call; using CacheObjectExists avoids it for untracked names.
    // Fall back to ObjectFind only when cache has no info (returns false = not in cache).
    //
    // P-PERF-02: and the WRITE itself is guarded — this function is called for
    // every line, label and zone on EVERY heavy frame, so an unconditional
    // ObjectSetInteger here was the single largest write source on the chart
    // (hundreds of writes per frame for masks that had not changed).
    bool knownInCache = CacheObjectExists(name);
    if(knownInCache) {
        ApplyTfMaskGuarded(name, timeframes);
        return;
    }
    // P-PERF-07: the ObjectFind fallback is a terminal call, and this function
    // is reached 7x per ZONE plus once per LINE and once per LABEL of every
    // level — including the CULLED ones, which were never created and so can
    // never enter the main cache. Without a negative cache that fallback ran
    // for every culled level on every heavy frame (~2.6k probes/frame at
    // inpMaxLevels=144), each scanning a chart holding thousands of objects.
    // A name already proven absent on this chart costs one hash instead.
    if(CacheIsAbsentKnown(name)) return;
    // Not in cache — check chart directly (only for sub-objects like _Top, _Bottom, _B_*)
    if(ObjectFind(0, name) >= 0) {
        CacheForgetAbsent(name);
        ApplyTfMaskGuarded(name, timeframes);
    } else {
        CacheMarkAbsent(name);
    }
}

void SetPipelineZoneVisibility(const string zoneName, const bool visible)
{
    // FIX: The L key controls only the zone boundary LINES (_Top/_Bottom).
    // The box object itself (rectangle or empty-box borders) is never
    // affected by L - only by F.
    // P-PERF-02: 7 guarded writes per zone per heavy frame — free when the
    // zone's visibility did not change (the common case by far).
    long tfAll = (visible && !IsIndicatorHidden()) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long tfLine = (visible && !IsIndicatorHidden() && GetCachedLinesVisible()) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    SetPipelineObjectTimeframesIfExists(zoneName, tfAll);
    SetPipelineObjectTimeframesIfExists(zoneName + "_Top", tfLine);
    SetPipelineObjectTimeframesIfExists(zoneName + "_Bottom", tfLine);
    // Empty-box border segments follow the box itself (F key)
    SetPipelineObjectTimeframesIfExists(zoneName + "_B_Top", tfAll);
    SetPipelineObjectTimeframesIfExists(zoneName + "_B_Bottom", tfAll);
    SetPipelineObjectTimeframesIfExists(zoneName + "_B_Left", tfAll);
    SetPipelineObjectTimeframesIfExists(zoneName + "_B_Right", tfAll);
}

void RenderZones(
    const SZoneDefinition &zones[],
    const int zoneCount,
    const SModeConfig &config)
{
    // P-PERF-41: THE FAMILY SWITCH IS A MASK, NOT A DESTRUCTION.
    //
    // The mid-zone family used to be turned off by DELETING it (the cleanup walk
    // started at 0 when `zonesEnabled` was false) and turned back on by
    // RE-CREATING it: ~7 terminal calls per zone per direction for a switch that
    // moves no price and no geometry. That is why turning zones on/off was slow
    // and fragile next to F, which has always been a mask.
    //
    // A hidden object costs nothing to draw (MT4 culls it before rasterising)
    // and the guarded writer behind VisibilityZoneMask makes a repeat call free,
    // so OFF is now the SAME change L makes - one mask per object - over EVERY
    // zone object the cache knows, with zero index assumptions and zero
    // ObjectFind probes. The owner lives in VisibilityManager because the F show
    // path writes the same masks and the two must agree (P-PERF-41 there).
    if(!config.zonesEnabled) { HideAllZoneFamilyObjects(); return; }

    bool triggerEnabled = IsTriggerLevelsEnabled();

    // P-PERF-04 PIXEL AWARENESS: a zone is a full-chart-width FILL, the most
    // expensive thing this indicator paints and the reason a zoomed-out chart
    // crawls — MT4 must rasterise every one of them on every repaint even when
    // a zone is a hairline tall and shows nothing the level line does not
    // already show. Measure the price->pixel scale ONCE per render and hide
    // any zone thinner than P_P4_MIN_ZONE_PX (hiding is what this loop already
    // does for off-screen zones, so it is stateless: zooming back in redraws).
    double p4PxPerPrice = 0.0;
    {
        int    p4H    = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
        double p4Pmax = ChartGetDouble(0, CHART_PRICE_MAX);
        double p4Pmin = ChartGetDouble(0, CHART_PRICE_MIN);
        if(p4H > 0 && p4Pmax > 0 && p4Pmin > 0 && p4Pmax > p4Pmin)
            p4PxPerPrice = (double)p4H / (p4Pmax - p4Pmin);
    }

    for(int i = 0; i < zoneCount; i++) {
        if(!zones[i].inViewport) {
            SetPipelineZoneVisibility(zones[i].name, false);
            continue;
        }

        if(p4PxPerPrice > 0.0 &&
           (zones[i].renderTop - zones[i].renderBottom) * p4PxPerPrice < P_P4_MIN_ZONE_PX)
        {
            SetPipelineZoneVisibility(zones[i].name, false);
            continue;
        }

        // P-UI-62: there is deliberately NO `ZONE_STYLE_HIDDEN` branch here any more.
        // "Are zones drawn at all?" belongs to the MID ZONES master switch (the zone
        // family mask), and a second owner for it - a style value that DELETES the
        // family - is exactly what the card's third pill used to be: the user could
        // see two controls claiming to do the same thing, and they disagreed.
        
        // Trigger bands when the trigger overlay is off: DELETE, as it always
        // did - and the reason is worth recording, because "hide it instead" is
        // the obvious-looking edit.
        //
        // A trigger band and a structure band are the SAME `_Zone_` names with
        // the same object shape, so nothing outside this list can tell them
        // apart: hiding one would also commit the F show path
        // (VisibilityShowAllCached) to repaint it ALL_PERIODS, because the only
        // input that path has is the FAMILY switch. The band would then blink
        // back for the frame between the F press and the render that re-hides
        // it - a new flicker, traded for nothing: after the first delete this
        // branch costs 7 proved-absent hash lookups per band (P-PERF-07/13),
        // and the render itself only runs when IsTriggerLevelsEnabled() moved
        // (it is in frameCore). Hiding would add a repaint risk to the one
        // switch whose whole job is to make a family visible.
        if(zones[i].isTrigger && !triggerEnabled) {
            DeleteManagedZoneObjects(zones[i].name);
            continue;
        }
        
        if(zones[i].renderTop <= zones[i].renderBottom) continue;
        
        {
            // P-UI-62: the two halves of the picture, transmitted as TWO flags.
            // `filled` = the band, `outline` = its edge (three segments), and each is
            // independent - so FILLED, EMPTY and OUTLINED are three real pictures and
            // the BORDER / BORDER WIDTH settings apply wherever an edge is drawn.
            SZoneCreationRequest request;
            request.name = zones[i].name;
            request.topPrice = zones[i].renderTop;
            request.bottomPrice = zones[i].renderBottom;
            request.zoneColor = zones[i].zoneColor;
            request.transparency = zones[i].transparency;
            request.filled = zones[i].filled;
            request.outline = zones[i].outline;
            request.borderStyle = inpMidZoneBorderStyle;
            request.borderWidth = inpMidZoneBorderWidth;
            // P-UI-63: the edge's OWN transparency - the two halves of the picture fade
            // independently, and both values are read here (next to the border style and
            // width they belong with) rather than threaded through the zone definition.
            request.borderTransparency = inpMidZoneBorderTransparency;
            request.startTime = 0;
            request.endTime = 0;
            
            CreateZone(request);
            SetPipelineZoneVisibility(zones[i].name, true);
        }
    }
}

//+------------------------------------------------------------------+
//| P-PERF-32: STRUCTURE RECOLOUR WALK -- the toggle paints, nothing  |
//| recomputes.                                                      |
//|                                                                  |
//| A structure switch (master / L1-L5, card 11) changes NO geometry: |
//| the level SET is switch-invariant (ClassifyLevels always builds   |
//| every step; the switches only choose zone colours via              |
//| GetZoneColorForLevel + the GetTriggerRenderColor fallback, exactly |
//| as ClassifyLevels lines 395-400 do). Re-deriving the whole level  |
//| family to repaint a few hundred zone colours is what made the     |
//| switch feel dead on a weak PC. So the switch never reaches the    |
//| render: this walk rewrites the blended colour of every cached     |
//| zone object whose live colour moved, and nothing else. Lines are  |
//| unified (switch-free), Center zones wear the mode colour, HTF/BK/ |
//| labels carry no "_Zone_" -- none of them is visited. Filled/empty  |
//| shape is toggle-invariant, so entries that do not exist (culled   |
//| zones, migrated-away rects/borders) are skipped, never created: a |
//| zone scrolled back into view is created later with live switches. |
//| The geometry key keeps the switch terms, so any LATER real render |
//| recomputes with live switches -- the walk can never desync it.     |
//+------------------------------------------------------------------+
// Tail step of a pipeline zone object name: "<pfx><mode>_Zone_Above_12"
// (or _Below_), with one optional border/legacy sub-suffix. Returns the
// step, or <= 0 when the name carries none (Center, foreign, malformed).
int StructureZoneStepFromName(const string nm)
{
    string base = nm;
    int blen = StringLen(base);
    // Longer sub-suffixes first: "_B_Bottom" ends with "_Bottom".
    if(blen > 9 && StringSubstr(base, blen - 9, 9) == "_B_Bottom") base = StringSubstr(base, 0, blen - 9);
    else if(blen > 8 && StringSubstr(base, blen - 8, 8) == "_B_Right") base = StringSubstr(base, 0, blen - 8);
    else if(blen > 7 && StringSubstr(base, blen - 7, 7) == "_B_Left") base = StringSubstr(base, 0, blen - 7);
    else if(blen > 7 && StringSubstr(base, blen - 7, 7) == "_Bottom") base = StringSubstr(base, 0, blen - 7);
    else if(blen > 6 && StringSubstr(base, blen - 6, 6) == "_B_Top") base = StringSubstr(base, 0, blen - 6);
    else if(blen > 4 && StringSubstr(base, blen - 4, 4) == "_Top") base = StringSubstr(base, 0, blen - 4);
    int ulen = StringLen(base);
    int sep = ulen - 1;
    while(sep >= 0 && StringGetCharacter(base, (ushort)sep) != '_') sep--;
    if(sep < 0 || sep + 1 >= ulen) return 0;
    return (int)StringToInteger(StringSubstr(base, sep + 1));
}

// Returns the number of colour writes issued.
int StructureRecolourWalk()
{
    // Same inputs ClassifyLevels (lines 395-400) reads: the walk repaints
    // exactly what a recompute would have stored.
    bool trigOn = IsTriggerLevelsEnabled();
    int baseMult = GetValidatedBaseMultiplier();
    int tr = inpMidZoneTransparency;
    if(tr < 0) tr = 0;
    if(tr > 100) tr = 100;

    int touched = 0;
    int visited = 0;
    for(int i = 0; i < CACHE_HASH_BUCKETS && visited < g_objectCacheSize; i++)
    {
        if(!g_objectCacheHash[i].occupied) continue;
        visited++;
        // P-UI-62: a dead slot is not "nothing painted under this name" - it is a name
        // this chart does not carry at all, and the colour it holds belongs to a
        // PICTURE (the edge-only zone), not to an object. Repainting it would be a
        // terminal write the terminal drops on the floor.
        if(!CacheSlotIsLive(i)) continue;
        const string nm = g_objectCacheHash[i].name;
        if(StringFind(nm, "_Zone_") < 0) continue;         // lines/labels/HTF
        if(StringFind(nm, "_Zone_Center_") >= 0) continue; // mode colour, not structure
        if(StringFind(nm, "_BK_") >= 0) continue;          // independent layer
        int step = StructureZoneStepFromName(nm);
        if(step <= 0) continue;
        color zc = GetZoneColorForLevel(step, trigOn, baseMult);
        if(zc == clrNONE) zc = GetTriggerRenderColor();
        color want = GetZoneRenderColor(zc, tr);
        color have = clrNONE;
        if(!CacheGetColor(nm, have)) continue;   // nothing painted under this name
        if(have == want) continue;
        if(!ObjectSetInteger(0, nm, OBJPROP_COLOR, want)) continue;
        CacheSetColor(nm, want);
        touched++;
    }
    return touched;
}

//+------------------------------------------------------------------+
//| STAGE 5b: Render trigger lines (SECOND   derived from zones)     |
//|                                                                  |
//| Creates/updates MT5 horizontal line objects.                     |
//| Uses CreateOrUpdateHLine for consistency.                        |
//+------------------------------------------------------------------+
void RenderTriggerLines(
    const STriggerLine &lines[],
    const int lineCount,
    const SModeConfig &config,
    const bool makeLines,
    const bool makeLabels)
{    double currentPrice = GetCurrentPriceForLabels();

    // P-PERF-03: record the level prices in the pass that already has them in
    // hand. CheckAlerts() then scans this array instead of walking the chart
    // with 2 x inpMaxLevels ObjectFind/ObjectGetDouble calls per heavy frame.
    // NOTE: recorded BEFORE the viewport cull, so an off-screen level can
    // still alert (the chart holds it; we simply do not paint it).
    AlertCacheReset(g_drawGeneration);

    for(int i = 0; i < lineCount; i++)
    {
        string labelName = lines[i].name + "_Label";

        AlertCacheAdd(lines[i].name, lines[i].price, lines[i].logicalStep,
                      lines[i].direction > 0);


        // ALL pipeline lines (trigger-subdivision AND structure-interval)
        // share the unified [08.4] appearance set in ClassifyLevels. They are
        // drawn whenever the Lines switch (L / g_linesVisible) shows them and
        // are NEVER hidden or restyled by the trigger switch. RenderZones is
        // the ONLY place the trigger overlay hides things — the trigger ZONES.
        // (The old Factor hideLineWhenTriggerOnly inversion is retired: every
        //  mode config leaves it false, and line visibility belongs to L alone.)
        if(!lines[i].inViewport) {
            // P-PERF-06: a staged family asserts only its own visibility — the
            // other family was (or will be) culled by its own stage frame.
            if(makeLines)  SetPipelineObjectTimeframesIfExists(lines[i].name, OBJ_NO_PERIODS);
            if(makeLabels) SetPipelineObjectTimeframesIfExists(labelName, OBJ_NO_PERIODS);
            continue;
        }

        // Use the individual line color instead of config.triggerColor
        if(makeLines) {
            bool isNew = CreateOrUpdateHLine(lines[i].name, lines[i].price,
                                              lines[i].clr, lines[i].lineStyle, lines[i].lineWidth,
                                              lines[i].tooltip);
            long lineTf = (IsIndicatorHidden() || !g_linesVisible) ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
            SetPipelineObjectTimeframesIfExists(lines[i].name, lineTf);

            // Set mode-specific properties on new objects
            if(isNew) {
                if(config.useObjPropBack) {
                    ObjectSetInteger(0, lines[i].name, OBJPROP_BACK, false);
                }
                if(config.zOrder > 0) {
                    ObjectSetInteger(0, lines[i].name, OBJPROP_ZORDER, config.zOrder);
                }
            }
        }

        // Render Pip Distance Label
        if(makeLabels && inpShowPipDistanceLabels) {
            // P-UI-52: the pip has ONE owner - `GetCachedPipSize()`, which reads the
            // symbol's own digits (metals 2-digit -> 10 points, JPY 3-digit -> 10,
            // FX 4/5-digit -> 10, and everything else -> 1 POINT). `point * 10` was a
            // hard-coded assumption that quietly disagrees with that owner on a
            // 2-digit index or crypto symbol, where one pip is one point: the label
            // then read 10x smaller than every other pip figure the indicator shows
            // for the same symbol (ATR scaling, combo, the Base/Knot box). One cached
            // getter replaces the constant, so the cost is unchanged - the guard keeps
            // the old value as the fallback, never a division by a zero pip.
            double pipNow = GetCachedPipSize();
            double pips = (pipNow > 0) ? MathAbs(lines[i].price - currentPrice) / pipNow
                                       : MathAbs(lines[i].price - currentPrice) / GetCachedPoint() / 10.0;
            CreatePipDistanceLabel(labelName, lines[i].price, pips, lines[i].clr, lines[i].labelText);
            long labelTf = IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
            SetPipelineObjectTimeframesIfExists(labelName, labelTf);
        }
    }
}

//+------------------------------------------------------------------+
//| HELPER: Get current price for distance labels                    |
//+------------------------------------------------------------------+
double GetCurrentPriceForLabels() {
    return (g_currentPrice > 0) ? g_currentPrice : Bid;
}

//+------------------------------------------------------------------+
//| STAGE 5c: Cleanup surplus objects from previous render           |
//+------------------------------------------------------------------+
void CleanupSurplusPipeline(
    const SModeConfig &config,
    const int maxLogicalStep)
{
    // During custom-price drag, do lightweight throttled cleanup instead of skipping entirely.
    if(g_customPriceLineDragging) {
        static uint s_lastDragCleanupMs = 0;
        uint nowMs = GetTickCount();
        if(s_lastDragCleanupMs != 0 && (nowMs - s_lastDragCleanupMs) < 250)
            return;
        s_lastDragCleanupMs = nowMs;
    }
    
    //======================================================================
    // P-PERF-36 - A FAMILY'S CLEANUP MUST NOT BE GUARDED BY THE FLAG THAT
    //             TURNS THE FAMILY OFF
    //
    // Cleanup has exactly one job: remove what THIS render no longer produces.
    // "Mid zones off" is precisely the state in which every zone must go, so
    // guarding the zone cleanup on `zonesEnabled` skipped the delete in the ONE
    // state that needed it. The chain is complete and provable:
    //
    //   ring CIR_ZONES -> g_showMidZones (== inpShowMidZones macro)
    //     -> GetUnifiedZoneConfig().enabled -> cfg.zonesEnabled
    //     -> zone BUILDING is gated on it (lines above: ArrayResize/hasMid/zIdx)
    //     -> so `zones[]` arrives EMPTY at RenderZones, which only walks the list
    //        it is handed and has NO delete-stale path of its own
    //     -> and this cleanup - the only remover of zone objects - was skipped
    //
    // Result: the switch stopped the zones being RE-CREATED while every zone
    // object already on the chart stayed put, which is the reported symptom:
    // "levels don't turn on/off with this button". Turning it back ON also did
    // nothing visible, because the objects had never left.
    //
    // P-PERF-41 supersedes the P-PERF-36 window: "zones off" is no longer an
    // ABSENCE at all. RenderZones hides the whole family with one mask walk the
    // moment the switch goes off, so cleanup is once more exactly what its name
    // says - "remove what THIS render no longer produces" - and it walks past the
    // newest logical step in BOTH states. Deleting the family on the way out was
    // the expensive half of the old toggle (7 deletes per zone, then 7 writes
    // per zone to come back) and the reason a hidden object could never be
    // brought back for free.
    //
    // The invariant P-PERF-36 was protecting is kept and strengthened: cleanup
    // may never be guarded by the flag that turns the family off, and the OFF
    // state is handled explicitly, one branch above.
    //======================================================================
    const int zoneCleanupFrom = maxLogicalStep + 1;
    CleanupSurplusObjects(config.objectPrefix + config.modeName + "_Zone_Above_", zoneCleanupFrom);
    CleanupSurplusObjects(config.objectPrefix + config.modeName + "_Zone_Below_", zoneCleanupFrom);
    CleanupSurplusObjects(config.objectPrefix + config.modeName + "_Zone_Center_", 1);
    
    // Cleanup surplus lines and their labels
    CleanupSurplusObjects(config.objectPrefix + config.modeName + "_Above_", maxLogicalStep + 1);
    CleanupSurplusObjects(config.objectPrefix + config.modeName + "_Below_", maxLogicalStep + 1);
    CleanupSurplusObjects(config.objectPrefix + config.modeName + "_Above_", maxLogicalStep + 1, 6, "_Label");
    CleanupSurplusObjects(config.objectPrefix + config.modeName + "_Below_", maxLogicalStep + 1, 6, "_Label");
    
    // Legacy cleanup
    string midpointName = config.objectPrefix + config.modeName + "_Midpoint_0";
    if(ObjectFind(0, midpointName) >= 0) {
        CacheRemoveObject(midpointName);
        ObjectDelete(0, midpointName);
    }
}

//+------------------------------------------------------------------+
//| BUILD MODE CONFIG: Create config from current input parameters   |
//+------------------------------------------------------------------+
SModeConfig BuildModeConfig(const string objectPrefix, const string modeName)
{
    SModeConfig cfg;
    cfg.modeName = modeName;
    cfg.objectPrefix = objectPrefix;
    
    // Read zone settings from unified zone config
    SUnifiedZoneConfig zoneConfig = GetUnifiedZoneConfig();
    cfg.zonesEnabled = zoneConfig.enabled;
    cfg.zoneTransparency = zoneConfig.transparency;
    cfg.zoneHeightPercent = zoneConfig.heightPercent;
    
    // GOLD FIX: Factor mode steps are defined differently in user's mind (or original logic)
    // If it looks double, we apply a 0.5 scaling factor specifically for Factor modes.
    if(modeName == "Factor" || modeName == "Factor_Harmonic") {
        cfg.zoneHeightPercent *= 0.5;
    }
    
    cfg.zoneDefaultColor = zoneConfig.defaultColor;
    cfg.zoneStyle = zoneConfig.style;
    
    // Default rendering flags
    cfg.useObjPropBack = false;
    cfg.zOrder = Z_CHART_ZONE;   // P-UI-31: mode configs override (Factor -> Z_CHART_LINE)
    cfg.hideLineWhenTriggerOnly = false;
    cfg.useStepFilter = true;
    
    // Defaults for fallback colors (overridden per mode)
    cfg.fallbackColor = clrDodgerBlue;
    cfg.fallbackStyle = STYLE_DOT;
    cfg.fallbackWidth = 1;
    cfg.fallbackColor2 = clrDodgerBlue;
    cfg.fallbackStyle2 = STYLE_DOT;
    cfg.fallbackWidth2 = 1;
    cfg.midpointColor = clrDodgerBlue;
    cfg.midpointStyle = STYLE_DOT;
    cfg.midpointWidth = 1;
    
    // Price boundaries
    bool isCustomPrice = (g_thStartPointType == TH_START_POINT_CUSTOM_PRICE);
    cfg.boundByHistorical = !isCustomPrice;
    cfg.maxPrice = isCustomPrice ? 0 : g_highestHigh;
    cfg.minPrice = isCustomPrice ? 0 : g_lowestLow;
    
    return cfg;
}

//+------------------------------------------------------------------+
//| P-PERF-18: the identity of a built geometry.                     |
//|                                                                  |
//| Every input the three pure stages read is folded in, so a change  |
//| in ANY of them misses the cache and rebuilds for real:           |
//|   - center price + step sizes   (a tick that moved the base price)|
//|   - the cull window             (a scroll or a zoom)             |
//|   - mode / classify / lsFirst / max levels / trigger switch      |
//|   - every zone and fallback colour/style field of SModeConfig    |
//|   - the custom-price drag flag  (the drag path re-culls)         |
//| Doubles are quantised with DoubleToString(...,8) so a sub-point  |
//| wobble cannot masquerade as a new geometry, and the string is     |
//| built once per frame - microseconds against the thousands of      |
//| level computations it can save.                                  |
//+------------------------------------------------------------------+
string PipelineGeometryKey(const SModeConfig &config,
                           const double centerPrice,
                           const double &stepSizes[],
                           const int stepSizeCount,
                           const ENUM_LEVEL_STEP_MODE stepMode,
                           const ENUM_CLASSIFY_MODE classifyMode,
                           const bool lsFirst,
                           const int maxLevelsAbove,
                           const int maxLevelsBelow,
                           const double vpTop,
                           const double vpBottom,
                           const int baseMultiplier)
{
    string key = config.modeName + "|" + config.objectPrefix;
    key += "|" + DoubleToString(centerPrice, 8);
    key += "|" + IntegerToString(stepSizeCount) + "," + IntegerToString((int)stepMode);
    for(int s = 0; s < stepSizeCount; s++) key += "," + DoubleToString(stepSizes[s], 8);
    key += "|" + IntegerToString((int)classifyMode) + IntegerToString(lsFirst ? 1 : 0);
    key += "|" + IntegerToString(maxLevelsAbove) + "," + IntegerToString(maxLevelsBelow);
    key += "|" + DoubleToString(vpTop, 8) + "," + DoubleToString(vpBottom, 8);
    // P-PERF-21: `triggerEnabled` used to sit here, and it was a FALSE
    // dependency. The trigger overlay owns exactly ONE family - the trigger
    // zones - and that decision lives in RenderZones (`zones[i].isTrigger &&
    // !triggerEnabled`), which reads the LIVE flag at paint time. Nothing that
    // BUILDS this geometry reads it: CalculateLevels does not touch it,
    // BuildZonesAndLines does not touch it, and the two classify-time helpers
    // that take it as a parameter (`GetPathForLevelOptimized`,
    // `GetZoneColorForLevel`) never look at it. So a T press threw away the
    // whole geometry and recomputed byte-identical lists - the recompute half
    // of "the trigger toggle redraws all my levels".
    key += "|" + IntegerToString(baseMultiplier);
    key += "|" + IntegerToString(config.zonesEnabled ? 1 : 0) + "," + IntegerToString((int)config.zoneStyle);
    key += "," + IntegerToString(config.zoneTransparency) + "," + DoubleToString(config.zoneHeightPercent, 6);
    key += "," + IntegerToString((int)config.zoneDefaultColor);
    key += "|" + IntegerToString(config.useObjPropBack ? 1 : 0) + "," + IntegerToString(config.zOrder);
    key += "," + IntegerToString(config.useStepFilter ? 1 : 0);
    key += "," + IntegerToString(config.boundByHistorical ? 1 : 0);
    key += "," + DoubleToString(config.maxPrice, 8) + "," + DoubleToString(config.minPrice, 8);
    key += "|" + IntegerToString((int)config.fallbackColor) + "," + IntegerToString((int)config.fallbackStyle);
    key += "," + IntegerToString(config.fallbackWidth);
    key += "," + IntegerToString((int)config.fallbackColor2) + "," + IntegerToString((int)config.fallbackStyle2);
    key += "," + IntegerToString(config.fallbackWidth2);
    key += "," + IntegerToString((int)config.midpointColor) + "," + IntegerToString((int)config.midpointStyle);
    key += "," + IntegerToString(config.midpointWidth);
    // P-PERF-21b: the ZONE COLOURS are part of what this geometry carries
    // (ClassifyLevels stores zoneColor per level, read from GetZoneColorForLevel
    // and GetTriggerRenderColor), yet none of THOSE inputs were in the key: a
    // structure-tier colour, a tier's show flag, the zones switch or the trigger
    // colour could change while the key stayed equal and the cached zones would
    // keep painting the old colour. The staleness was invisible because every
    // one of those edits also changes levelSig and therefore wipes - but the
    // cache must not RELY on a different guard to be correct.
    key += "|zc" + IntegerToString(inpShowMidZones ? 1 : 0)
              + IntegerToString(inpShowStructure ? 1 : 0)
              + IntegerToString(inpShowStructureL1 ? 1 : 0) + IntegerToString(inpShowStructureL2 ? 1 : 0)
              + IntegerToString(inpShowStructureL3 ? 1 : 0) + IntegerToString(inpShowStructureL4 ? 1 : 0)
              + IntegerToString(inpShowStructureL5 ? 1 : 0)
              + "," + IntegerToString((int)inpStructureL1Color) + IntegerToString((int)inpStructureL2Color)
              + IntegerToString((int)inpStructureL3Color) + IntegerToString((int)inpStructureL4Color)
              + IntegerToString((int)inpStructureL5Color)
              + "," + IntegerToString((int)GetTriggerRenderColor());
    key += "|" + IntegerToString(g_customPriceLineDragging ? 1 : 0);
    // ClassifyLevels() reads the LIVE line appearance, so a style/colour edit
    // mid-rebuild must miss the cache too (otherwise the other families of that
    // rebuild would paint the pre-edit look).
    key += "|" + IntegerToString((int)g_lineColor) + "," + IntegerToString(g_lineTransparency);
    // P-PERF-23b: `g_linesVisible` used to sit here, described as "ClassifyLevels()
    // reads the LIVE line appearance and the L toggle". That was FALSE: no stage
    // of this pipeline reads it. grep says it has exactly two consumers in the
    // whole file - the RenderTriggerLines paint line (`long lineTf = ...
    // !g_linesVisible ...`, plus ObjectFunctions) and this key. The L switch and
    // the panels' SHOW LINES row are a MASK decision taken at paint time, so the
    // term turned every visibility flip into a full recompute of
    // CalculateLevels/Classify/Build that produced byte-identical lists, and
    // then the paint re-read the live flag anyway. Removed: the picture still
    // follows the switch (the mask writer owns it), the math no longer restarts.
    // ClassifyLevels() -> GetHighestStructureLevel() reads the structure-interval
    // table (g_cachedIntervals). That table is a pure function of the VALIDATED
    // base multiplier (already in the key), but the key names its five values
    // directly, so a future change to how the table is derived cannot silently
    // serve structure levels computed against the old table. (The term here used
    // to be ArraySize(g_cachedIntervals), the constant 5 - it asserted a
    // property instead of proving it.)
    key += "|iv";
    for(int iv = 0; iv < 5; iv++) key += "," + IntegerToString(g_cachedIntervals[iv]);
    return key;
}

//+------------------------------------------------------------------+
//| UNIFIED PIPELINE EXECUTOR                                        |
//+------------------------------------------------------------------+
SPipelineResult ExecutePipeline(
    const SModeConfig &config,
    const double centerPrice,
    const double &stepSizes[],
    const int stepSizeCount,
    const ENUM_LEVEL_STEP_MODE stepMode,
    const ENUM_CLASSIFY_MODE classifyMode,
    const bool lsFirst,
    const int maxLevelsAbove,
    const int maxLevelsBelow,
    const double vpTop,
    const double vpBottom,
    const int buildStage)
{
    SPipelineResult result;
    result.zoneCount = 0;
    result.lineCount = 0;
    result.success = false;
    result.errorMessage = "";
    
    if(centerPrice <= 0) {
        result.errorMessage = "Invalid center price";
        return result;
    }
    for(int s = 0; s < stepSizeCount; s++) {
        if(stepSizes[s] <= 0) {
            result.errorMessage = "Invalid step size";
            return result;
        }
    }
    
    bool triggerEnabled = IsTriggerLevelsEnabled();
    int baseMultiplier = GetValidatedBaseMultiplier();
    // P-PERF-06: the cull window arrives from the caller (RedrawAllObjects owns
    // the hysteretic window AND the staging snapshot — deriving it here a
    // second time could split staged families across two viewports).

    double fixedZoneStepSize = 0.0;
    if(config.modeName == "SSLS" && stepSizeCount > 1)
        fixedZoneStepSize = MathMin(stepSizes[0], stepSizes[1]);

    SZoneDefinition zones[];
    STriggerLine lines[];
    int maxStep = 0;

    //                                                                
    // P-PERF-18: THE STAGED REBUILD WAS RE-COMPUTING THE SAME MATH    
    //                                                                
    // P-PERF-06 splits a post-wipe rebuild (attach / TF switch /       
    // topology toggle) into four frames - lines, zones, labels, block  
    // - and every one of those frames called this function again, so   
    // CalculateLevels -> ClassifyLevels/Alternating -> BuildZonesAnd-  
    // Lines ran FOUR times with IDENTICAL inputs: on the weakest        
    // machine that is four times the level arithmetic and four times   
    // four times the label strings, for one switch. This is the         
    // "compute it once, at the right moment" rule (LEARNING §16): the   
    // staged frames are by construction "same geometry, another          
    // family", so the built lists are remembered under a key made of    
    // every input the three stages read. A tick that moves the base     
    // price, a scroll that moves the cull window, an input edit, or a   
    // mode switch changes the key and the math runs again - the cache   
    // can only ever answer for an unchanged geometry.                   
    //                                                                
    string geoKey = PipelineGeometryKey(config, centerPrice, stepSizes, stepSizeCount,
                                       stepMode, classifyMode, lsFirst, maxLevelsAbove,
                                       maxLevelsBelow, vpTop, vpBottom,
                                       baseMultiplier);
    static string s_geoKey = "";
    static bool   s_geoValid = false;
    static SZoneDefinition s_geoZones[];
    static STriggerLine    s_geoLines[];
    static int    s_geoZoneCount = 0;
    static int    s_geoLineCount = 0;
    static int    s_geoMaxStep = 0;

    if(s_geoValid && geoKey == s_geoKey) {
        // Same geometry, another family: copy the built lists, skip the math.
        ArrayResize(zones, s_geoZoneCount);
        for(int z = 0; z < s_geoZoneCount; z++) zones[z] = s_geoZones[z];
        ArrayResize(lines, s_geoLineCount);
        for(int l = 0; l < s_geoLineCount; l++) lines[l] = s_geoLines[l];
        result.zoneCount = s_geoZoneCount;
        result.lineCount = s_geoLineCount;
        maxStep = s_geoMaxStep;
    }
    else {
        // Stage 1: Calculate (unified)
        SCalculatedLevel rawLevels[];
        int rawCount = CalculateLevels(centerPrice, stepSizes, stepSizeCount, stepMode,
                                        lsFirst, maxLevelsAbove, maxLevelsBelow,
                                        config.boundByHistorical, config.maxPrice, config.minPrice,
                                        rawLevels, maxStep);
        if(rawCount == 0) {
            result.errorMessage = "No levels calculated";
            s_geoValid = false;   // never serve a geometry for a config that produced none
            return result;
        }

        // Stage 2: Classify (mode-specific variant)
        SLevelClassified classified[];
        int classifiedCount = 0;
        switch(classifyMode) {
            case CLASSIFY_ALTERNATING:
                classifiedCount = ClassifyLevelsAlternating(rawLevels, rawCount, config,
                                                            triggerEnabled, baseMultiplier, lsFirst,
                                                            classified);
                break;
            default: // CLASSIFY_STANDARD
                classifiedCount = ClassifyLevels(rawLevels, rawCount, config,
                                                  triggerEnabled, baseMultiplier, classified);
                break;
        }

        // Stages 3+4: Build zones and lines (merged   single pass)
        BuildZonesAndLines(classified, classifiedCount, config, vpTop, vpBottom,
                           fixedZoneStepSize, zones, result.zoneCount, lines, result.lineCount);

        // Remember the result for the other families of this same rebuild.
        ArrayResize(s_geoZones, result.zoneCount);
        for(int zc = 0; zc < result.zoneCount; zc++) s_geoZones[zc] = zones[zc];
        ArrayResize(s_geoLines, result.lineCount);
        for(int lc = 0; lc < result.lineCount; lc++) s_geoLines[lc] = lines[lc];
        s_geoZoneCount = result.zoneCount;
        s_geoLineCount = result.lineCount;
        s_geoMaxStep = maxStep;
        s_geoKey = geoKey;
        s_geoValid = true;
    }
    
    // Stage 5: Render and cleanup.
    // P-PERF-06 STAGED RENDER: the math above (Calculate/Classify/Build) is
    // pure CPU (~ms) and re-runs every stage; only ONE object family is
    // materialised per frame, so a post-wipe build lands as four ~2k-call
    // frames instead of one ~8k-call freeze. buildStage 0 (or anything
    // unexpected) is the full legacy render — steady frames always take it.
    if(buildStage == BUILD_STAGE_LINES) {
        RenderTriggerLines(lines, result.lineCount, config, true, false);
    } else if(buildStage == BUILD_STAGE_ZONES) {
        RenderZones(zones, result.zoneCount, config);
    } else if(buildStage == BUILD_STAGE_LABELS) {
        RenderTriggerLines(lines, result.lineCount, config, false, true);
        // PERF: maxStep already known from CalculateLevels output (no extra O(n) scan needed)
        CleanupSurplusPipeline(config, maxStep);
    } else {
        RenderZones(zones, result.zoneCount, config);
        RenderTriggerLines(lines, result.lineCount, config, true, true);

        // PERF: maxStep already known from CalculateLevels output (no extra O(n) scan needed)
        CleanupSurplusPipeline(config, maxStep);
    }
    
    result.success = true;
    return result;
}

//+------------------------------------------------------------------+
//| SUFFIX REGISTRY: Centralized suffix tracking                     |
//|                                                                  |
//| All mode suffixes registered in one place.                       |
//| Adding a new mode = add one entry here.                          |
//+------------------------------------------------------------------+
struct SModeSuffixEntry {
    string zoneSuffix;      // e.g., "SSLS_Zone_"
    string levelAbove;      // e.g., "SSLS_Above_"
    string levelBelow;      // e.g., "SSLS_Below_"
    string midpoint;        // e.g., "SSLS_Midpoint_"
    string zoneCenter;      // e.g., "SSLS_Zone_Center_"   zone on midpoint/anchor level
};

// GetAll registered mode suffixes   used by ClearAllLevels and DeleteAllIndicatorObjects
void GetAllModeSuffixes(SModeSuffixEntry &entries[], int &count)
{
    static string modeNames[] = {"SSLS", "Combo", "Factor", "Factor_Harmonic", "TH_Level"};
    count = ArraySize(modeNames);
    ArrayResize(entries, count);
    
    for(int i = 0; i < count; i++) {
        entries[i].zoneSuffix = modeNames[i] + "_Zone_";
        entries[i].levelAbove = modeNames[i] + "_Above_";
        entries[i].levelBelow = modeNames[i] + "_Below_";
        entries[i].midpoint = modeNames[i] + "_Midpoint_";
        entries[i].zoneCenter = modeNames[i] + "_Zone_Center_";
        
        // Manual overrides for non-standard legacy suffixes
        if(modeNames[i] == "Factor") entries[i].midpoint = "Factor_Center_";
        if(modeNames[i] == "Factor_Harmonic") entries[i].midpoint = "Factor_Harmonic_Center_";
    }
}

// Get all zone suffixes as a flat array (for ClearAllLevels compatibility)
void GetAllZoneSuffixes(string &suffixes[], int &count)
{
    SModeSuffixEntry entries[];
    int entryCount = 0;
    GetAllModeSuffixes(entries, entryCount);
    
    // Each mode has 2 zone suffix families: zoneSuffix (Above/Below) + zoneCenter
    count = entryCount * 2;
    ArrayResize(suffixes, count);
    int idx = 0;
    for(int i = 0; i < entryCount; i++) {
        suffixes[idx++] = entries[i].zoneSuffix;
        suffixes[idx++] = entries[i].zoneCenter;
    }
    count = idx;
}

// Get all level suffixes as a flat array (for ClearAllLevels compatibility)
void GetAllLevelSuffixes(string &suffixes[], int &count)
{
    SModeSuffixEntry entries[];
    int entryCount = 0;
    GetAllModeSuffixes(entries, entryCount);
    
    // Each mode has 3 level suffixes (above, below, midpoint)
    // Plus legacy suffixes for backward compatibility
    count = entryCount * 3;
    ArrayResize(suffixes, count);
    int idx = 0;
    for(int i = 0; i < entryCount; i++) {
        suffixes[idx++] = entries[i].levelAbove;
        suffixes[idx++] = entries[i].levelBelow;
        suffixes[idx++] = entries[i].midpoint;
    }
    count = idx;
}

#endif // LEVEL_PIPELINE_MQH
