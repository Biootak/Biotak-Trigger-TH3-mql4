// LevelPipe_A.mqh - LevelPipeline.mqh split 2026-09-29: exact lines 7-1438, byte-identical, zero renames.
#ifndef LEVEL_PIPE_A_MQH
#define LEVEL_PIPE_A_MQH


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
    bool   isTrigger;       // P-UI-131j: this line's LEVEL is a trigger subdivision,
                            // so its pip label wears the TRIGGER LABEL surface
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
        // P-LEVEL-BOUND-03: the step THIS iteration advances by, so the historical
        // bound can be extended by whole rungs instead of a price guess.
        double iterStep = stepSizes[0];
        if(stepMode == LEVEL_STEP_UNIFORM) {
            price = shiftedCenter + (stepSizes[0] * logicalStep);
        } else {
            // CUMULATIVE: alternate SS/LS. The first interval is controlled
            // by sslsLongFirst; subsequent intervals alternate strictly.
            int sequenceIndex = (sslsLongFirst && stepSizeCount > 1) ? 1 : 0;
            int parity = (logicalStep - 1) % 2;
            int selectedIndex = (parity == 0) ? sequenceIndex : ((sequenceIndex + 1) % stepSizeCount);
            double dist = stepSizes[selectedIndex];
            iterStep = dist;
            cumAbove += dist;
            price = shiftedCenter + cumAbove;
        }
        
        // Price boundary check — P-LEVEL-BOUND-03: the bound is extended by
        // `P_LEVEL_BOUND_OVERDRAW` whole rungs so the chart shows where the next
        // levels WOULD be, without touching where the historical extreme is.
        if(boundByHistorical && maxPrice > 0 && price > maxPrice + P_LEVEL_BOUND_OVERDRAW * iterStep) break;
        
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
        double iterStep = stepSizes[0];
        if(stepMode == LEVEL_STEP_UNIFORM) {
            price = shiftedCenter - (stepSizes[0] * logicalStep);
        } else {
            int sequenceIndex = (sslsLongFirst && stepSizeCount > 1) ? 1 : 0;
            int parity = (logicalStep - 1) % 2;
            int selectedIndex = (parity == 0) ? sequenceIndex : ((sequenceIndex + 1) % stepSizeCount);
            double dist = stepSizes[selectedIndex];
            iterStep = dist;
            cumBelow += dist;
            price = shiftedCenter - cumBelow;
        }
        
        // Price boundary check — P-LEVEL-BOUND-03, same margin as the above side.
        if(boundByHistorical && minPrice > 0 && price < minPrice - P_LEVEL_BOUND_OVERDRAW * iterStep) break;
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
//| P-UI-131m: A BAND'S INK IS ONE PAIR, FADED EXACTLY ONCE.         |
//|                                                                  |
//| The trigger card's COLOR row could not reach the chart:           |
//| `GetTriggerRenderColor()` had already blended g_triggerColor with  |
//| g_triggerTransparency, and CreateZone blended that result AGAIN   |
//| with the MID ZONE transparency - two owners fading one band. At   |
//| the measured 43 % the band kept 8 % of the picked colour.        |
//|                                                                  |
//| So a band carries a BASE that is never pre-faded plus the opacity |
//| that owns it: card 0's TRANSPARENCY for a trigger band, the band  |
//| row on card 1 for a structure one. The EDGE derives from the same |
//| base, so the trigger card's colour reaches the surface that is    |
//| actually visible. No reader may hand CreateZone a self-faded      |
//| colour (P-UI-66's law, applied to the band).                     |
//+------------------------------------------------------------------+
color PipelineBandBaseColor(const int step, const bool triggerEnabled, const int baseMultiplier)
{
    color zc = GetZoneColorForLevel(step, triggerEnabled, baseMultiplier);
    if(zc != clrNONE) return zc;     // a structure tier owns this band's ink
    return g_triggerColor;           // the trigger family's own ink, RAW
}

int PipelineBandTransparency(const bool isTrigger, const int bandTransparency)
{
    if(!isTrigger) return bandTransparency;
    int t = (int)MathMax(0, MathMin(100, g_triggerTransparency));
    return t;
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

        // Zone color from level (zones keep their family identity). RAW - the
        // fade belongs to the row that owns it, and CreateZone does it once.
        classified[i].zoneColor = PipelineBandBaseColor(step, triggerEnabled, baseMultiplier);
        
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
        lines[lIdx].isTrigger = s_aboveLevels[i].isTrigger;   // P-UI-131j
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
        lines[lIdx].isTrigger = s_belowLevels[i].isTrigger;   // P-UI-131j
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
// Returns true only when a real mask WRITE reached the chart (P-PERF-32b: the
// family walks report their cost as a number, and a guarded no-op is not a write).
bool SetPipelineObjectTimeframesIfExists(const string name, const long timeframes)
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
        return ApplyTfMaskGuarded(name, timeframes);
    }
    // P-PERF-07: the ObjectFind fallback is a terminal call, and this function
    // is reached 7x per ZONE plus once per LINE and once per LABEL of every
    // level — including the CULLED ones, which were never created and so can
    // never enter the main cache. Without a negative cache that fallback ran
    // for every culled level on every heavy frame (~2.6k probes/frame at
    // inpMaxLevels=144), each scanning a chart holding thousands of objects.
    // A name already proven absent on this chart costs one hash instead.
    if(CacheIsAbsentKnown(name)) return false;
    // Not in cache — check chart directly (only for sub-objects like _Top, _Bottom, _B_*)
    if(ObjectFind(0, name) >= 0) {
        CacheForgetAbsent(name);
        return ApplyTfMaskGuarded(name, timeframes);
    }
    CacheMarkAbsent(name);
    return false;
}

// Returns the number of masks that actually reached the chart (0..7).
// P-PERF-32b: the trigger family's press-time walk (TriggerFamilyWalk) and the
// render share THIS writer, so the two can never disagree about which objects a
// zone is made of or which of them L owns.
int SetPipelineZoneVisibility(const string zoneName, const bool visible)
{
    // FIX: The L key controls only the zone boundary LINES (_Top/_Bottom).
    // The box object itself (rectangle or empty-box borders) is never
    // affected by L - only by F.
    // P-PERF-02: 7 guarded writes per zone per heavy frame — free when the
    // zone's visibility did not change (the common case by far).
    long tfAll = (visible && !IsIndicatorHidden()) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    long tfLine = (visible && !IsIndicatorHidden() && GetCachedLinesVisible()) ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    int wrote = 0;
    if(SetPipelineObjectTimeframesIfExists(zoneName, tfAll)) wrote++;
    if(SetPipelineObjectTimeframesIfExists(zoneName + "_Top", tfLine)) wrote++;
    if(SetPipelineObjectTimeframesIfExists(zoneName + "_Bottom", tfLine)) wrote++;
    // Empty-box border segments follow the box itself (F key)
    if(SetPipelineObjectTimeframesIfExists(zoneName + "_B_Top", tfAll)) wrote++;
    if(SetPipelineObjectTimeframesIfExists(zoneName + "_B_Bottom", tfAll)) wrote++;
    if(SetPipelineObjectTimeframesIfExists(zoneName + "_B_Left", tfAll)) wrote++;
    if(SetPipelineObjectTimeframesIfExists(zoneName + "_B_Right", tfAll)) wrote++;
    return wrote;
}

void RenderZones(
    const SZoneDefinition &zones[],
    const int zoneCount,
    const SModeConfig &config,
    const double vpTop,
    const double vpBottom)
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
        // P-VIEW-01 (2026-09-29) — THE CULL DECIDES PAINT, THE VIEWPORT NEVER OWNS
        // VISIBILITY. It used to write `SetPipelineZoneVisibility(name,false)` here,
        // i.e. the window HID the band — and a hidden object is only shown again by
        // the frame that re-decides it. Measured: the cull window is allowed to lag
        // the chart by P_P4_VP_HYSTERESIS_PCT 0.20 of the visible range
        // (ExtDraw_A.mqh 105-125) and the window is a term of the geometry signature
        // (EventHandlers_Calc.mqh 1329), so a band the price walked up to stayed
        // HIDDEN until some other input forced a rebuild — the report «سطوح حذف
        // میشه ولی دیگه نمیاد تا یک تکونی به چارت بدم». Now the band is asserted with
        // the SAME mask the in-window path asserts (F/L alone own it, read-guarded by
        // ApplyTfMaskGuarded: zero writes in steady state) and simply not painted this
        // frame. MT4 draws an object it already holds at its own paint time, so the
        // band is there BEFORE the user scrolls to it — the only allocation this
        // costs is MT4's own clipping, not an indicator write.
        // P-VIEW-03 (2026-09-29): the window no longer skips a band here either —
        // see the same law and the same MEASURED band (EURUSD M15: 1.11520..1.15185
        // missing between two drawn groups) at RenderTriggerLines below. A band that
        // is only \"not painted this frame\" is a band that can stay unpainted forever,
        // because nothing else re-decides it. The thin-zone guard below stays: it is
        // re-decided by the same frame that sees the scale change.

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
        
        // P-PERF-32b — THE TRIGGER OVERLAY IS A MASK, NOT A DESTRUCTION.
        //
        // This branch used to DELETE the band (and the F-show path's blanket
        // ALL_PERIODS was the reason it had to: a trigger band and a structure
        // band are the same `_Zone_` names, so a hidden trigger band would have
        // been re-shown by an F press - the flicker this delete existed to
        // prevent).
        //
        // What the delete could not survive is the LATENCY: the T toggle, the
        // ring's TRIGGER light and the card's SHOW row all flipped the switch
        // and then asked the RENDER for the pixels ("سطح تریگر دیر خاموش و روشن
        // میشه"), because a deleted band leaves the ON direction nothing to
        // show without a full family render. The structure switches (card 11,
        // P-PERF-32) have painted in their own event since they were fixed:
        // state + a walk over the objects + a discrete repaint.
        //
        // So the family is a MASK now, exactly like the mid-zone family
        // (P-PERF-41) and the unified lines (P-PERF-25): the band stays as a
        // hidden object and OFF/ON is one guarded mask per object, written by
        // the SAME `SetPipelineZoneVisibility` the press-time walk calls
        // (TriggerFamilyWalk, LevelPipe_B). A later render asserts the live
        // switch here and changes no pixel - and the F-show corner is closed at
        // the source: `ApplyHideAllState` re-asserts this family through its own
        // owner, in the same event.
        //
        // Cost: while the overlay is OFF the bands exist as masked objects
        // (MT4 culls a masked object before rasterising) - the same trade
        // P-PERF-41 made for the zone family, and what P-PERF-04's thin-zone
        // guard already does with a single band.
        //
        // AND HIDDEN, BUT NEVER STALE. The ON press paints from these very
        // objects (its walk writes masks, not geometry), so a band left at the
        // previous centre would flash at the old price for a frame - exactly the
        // class P-VIEW-01/03 refuse. The test is this list's own first guard, read
        // from the cache (the top price we last WROTE vs the top this geometry
        // gives): on a match the band is masked and skipped (seven guarded masks,
        // zero terminal calls); on a miss it falls through to the ONE creator
        // below, which updates it in place - still masked. That same fall-through
        // is what MATERIALISES the family while the overlay is off (the first
        // render after attach creates it), so the first ON press is a mask flip
        // too, exactly like a structure switch.
        bool triggerHidden = (zones[i].isTrigger && !triggerEnabled);
        if(triggerHidden) {
            SObjectCacheEntry trigEntry;
            if(CacheGetObject(zones[i].name, trigEntry) &&
               MathAbs(trigEntry.lastPrice - zones[i].renderTop) <= GetCachedPoint() * 0.1) {
                SetPipelineZoneVisibility(zones[i].name, false);
                // P-KEY-PROBE: only while a T press is outstanding (one int read per
                // band in the steady state would be the cost this project refuses).
                if(g_triggerPressMs != 0) g_triggerPressHidden++;
                continue;
            }
        }
        // P-KEY-PROBE: the bands this render reaches for the toggle (the show
        // direction pays these; the hide direction pays the masks above).
        if(zones[i].isTrigger && g_triggerPressMs != 0) g_triggerPressReached++;
        
        if(zones[i].renderTop <= zones[i].renderBottom) continue;
        
        {
            // P-UI-62: the two halves of the picture, transmitted as TWO flags.
            // `filled` = the band, `outline` = its edge (three segments), and each is
            // independent - so FILLED, EMPTY and OUTLINED are three real pictures and
            // the BORDER / BORDER WIDTH settings apply wherever an edge is drawn.
            SZoneCreationRequest request = ZoneRequestNew();   // P-UI-131h
            request.name = zones[i].name;
            request.topPrice = zones[i].renderTop;
            request.bottomPrice = zones[i].renderBottom;
            request.zoneColor = zones[i].zoneColor;
            // P-UI-131m: the band's OWN opacity, read live next to the border rows
            // below - a trigger band is faded by card 0's TRANSPARENCY, a structure
            // band by the band row on card 1. The BASE colour above is unfaded, so
            // this is the one fade (the double blend it replaces left a trigger band
            // at 8 % of the picked colour at 43 %).
            request.transparency = PipelineBandTransparency(zones[i].isTrigger, zones[i].transparency);
            request.filled = zones[i].filled;
            request.outline = zones[i].outline;
            request.borderStyle = inpMidZoneBorderStyle;
            request.borderWidth = inpMidZoneBorderWidth;
            // P-UI-63: the edge's OWN transparency - the two halves of the picture fade
            // independently, and both values are read here (next to the border style and
            // width they belong with) rather than threaded through the zone definition.
            request.borderTransparency = inpMidZoneBorderTransparency;
            // P-UI-131h: the two halves' own surfaces, read here with the three rows
            // above. AUTO (clrNONE / -1) is the factory state, so this changes nothing
            // until a row is touched.
            request.borderTopColor = inpZoneEdgeTopColor;
            request.borderBottomColor = inpZoneEdgeBottomColor;
            request.borderTopTransparency = inpZoneEdgeTopTransparency;
            request.borderBottomTransparency = inpZoneEdgeBottomTransparency;
            request.startTime = 0;
            request.endTime = 0;
            
            CreateZone(request);
            // P-PERF-32b: a band whose overlay is OFF is created/updated in place
            // and stays MASKED - the render never shows what the switch turned off.
            SetPipelineZoneVisibility(zones[i].name, !triggerHidden);
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
//| PipelineBandBaseColor, exactly as ClassifyLevels does).           |
//| Re-deriving the whole level                                        |
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
        // P-UI-131m: the walk repaints through the SAME two owners the paint path
        // uses, or a structure switch would write a trigger band a colour the
        // render never produces (it used to blend the mid-zone transparency into a
        // base that was already faded).
        bool isTrig = (GetHighestStructureLevel(step, g_cachedIntervals) <= 0);
        color zc = PipelineBandBaseColor(step, trigOn, baseMult);
        color want = GetZoneRenderColor(zc, PipelineBandTransparency(isTrig, tr));
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
//+------------------------------------------------------------------+
//| P-UI-98: THE STEP-1 HANDLE'S FACE AND ITS MARKER.                 |
//|                                                                   |
//| In custom-price start-point mode the two rung-1 trigger lines are |
//| the user's step handle: while ARMED they are SELECTABLE (MT4's    |
//| own drag moves them), they sit at a z-order above the zone fills  |
//| (a zone rectangle under the cursor would otherwise eat the grab — |
//| the reported «الان step اول قابل درگ کردن نیستش»), and ONE small  |
//| red dot at the chart's right edge (time 0 — the pip labels' own   |
//| anchoring, so it follows the market with no per-bar write) marks  |
//| them. The user's marker order: «خط کاستوم پرایس ... نشانه سبز و   |
//| step اول ... نشانه قرمز ... یک نشانه باشه که خیلی مزاحم هم نباشه» |
//| and «وقتی لاین ها رو خاموش میکنم نشان ها هم نباشه» — the dot      |
//| wears the line family's mask, so the L switch owns it with the    |
//| lines.                                                            |
//|                                                                   |
//| SET (the click-to-commit model, P-UI-98d): a set handle is not    |
//| selectable, its dot is gone, and the marker object is DELETED —   |
//| not masked — so no other mask writer can resurrect it. The       |
//| armed/set pair is owned HERE in the refresh path, so a state that |
//| changed under the chart is re-owned on the next render. Guarded:  |
//| one read per line per frame, a write only on drift (the perf law).|
//+------------------------------------------------------------------+
void Step1HandleOwnFace(const string name, const double price, const int direction,
                        const long lineTf, const string naturalTip)
{
    bool draggable = (g_thStartPointType == TH_START_POINT_CUSTOM_PRICE) && g_s1LinesArmed;
    // P-UI-98e: WHILE OUR OWN CARRY OWNS THIS LINE, THE FLAG IS BORROWED.
    // P-LM-21 learned it on the leg metre: MT4 re-arms its own per-object drag on
    // every paint for as long as SELECTABLE sits on the object, so the line fights
    // the hand and the gesture «سریع قطع میشه». The face owner must not re-arm
    // what the gesture took, and the selection face it would otherwise drop
    // mid-drag stays (that is the separate property the borrow leaves alone).
    bool dragOwnsThis = (g_s1DragLive && g_s1DragName == name);
    if(!dragOwnsThis)
    {
        bool current = (bool)ObjectGetInteger(0, name, OBJPROP_SELECTABLE);
        if(current != draggable)
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, draggable);
        if(!draggable && (bool)ObjectGetInteger(0, name, OBJPROP_SELECTED))
            ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    }
    // P-UI-31's rule: the rung is NOT read back (the zorder audit bans
    // OBJPROP_ZORDER reads in product code - a diagnostic, not a product
    // question) and it is not re-decided either: the handle's one rung is
    // Z_CHART_LABEL, spelled here and nowhere else.
    ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_CHART_LABEL);
    // P-UI-98g: an armed handle whose circle is not up yet asks for the click.
    string tip = draggable
        ? (g_s1HandleShown
           ? "[STEP 1] Drag the red handle to set the ladder step - click to commit, double-click re-arms"
           : "[STEP 1] Click it to bring up the red handle")
        : naturalTip;
    if(tip != "" && ObjectGetString(0, name, OBJPROP_TOOLTIP) != tip)
        ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);

    // the drag handle: ONE circular icon (S1_HANDLE_RES), centred on the line
    // at the screen's horizontal middle; a SET or hidden handle PARKS it
    // off-window (nothing can grab a set line, so nothing points at it either).
    // The name AND the price are stashed for the grab hit test and the ride
    // channels (P-UI-98e): the press edge must name the line it claims, and the
    // carry needs the object to move.
    // P-UI-98e: the rung-1 line's own NAME and PRICE are stashed whenever the
    // line is THERE — not only while it is draggable. A SET handle stays
    // CLICKABLE: the double-click that re-arms it has to find the row it names,
    // and the click's hit test reads this very stash. What a SET handle LOSES is
    // the icon (parked below), never the address — and the icon itself is placed
    // only while the pair is armed (HandsetMarkersRide obeys the same term).
    bool addressable = (price > 0.0) && MathIsValidNumber(price) && !IsIndicatorHidden();
    if(addressable) g_s1MarkPeriod = Period();   // P-UI-98e: the stash's own timeframe
    if(direction > 0) { g_s1MarkAbovePrice = addressable ? price : 0.0; g_s1MarkAboveName = addressable ? name : ""; }
    else              { g_s1MarkBelowPrice = addressable ? price : 0.0; g_s1MarkBelowName = addressable ? name : ""; }
    string mark = S1MarkName(direction);
    // P-UI-98g: the RED circle is painted on request too («فقط وقتی روش کلیک
    // کردیم دایره ها بیاد برای درگ کردن») — `g_s1HandleShown` is what the click
    // on the line sets, and a SET or unasked pair keeps the circle parked.
    if(!draggable || !g_s1HandleShown || !(price > 0.0) || !MathIsValidNumber(price) ||
       IsIndicatorHidden() || !g_linesVisible)
    {
        HandsetHandlePark(mark, S1_HANDLE_RES);
        return;
    }
    HandsetHandleAt(mark, price, S1_HANDLE_RES);
}

//+------------------------------------------------------------------+
//| P-UI-98f: WHICH LINE WEARS THE STEP-1 HANDLE (2026-09-22).        |
//|                                                                   |
//| Reported: «استپ اول که کلیک میکنم دوتا فعال میشه ... اون قرمز    |
//| خیلی نزدیک کاستوم پرایس نباید باشه». The old rule was             |
//| `logicalStep == 1` — the LADDER's rung 1, which is not the line    |
//| one STEP away from the custom price. Trigger lines are drawn at    |
//| the MIDPOINT of each pair of neighbouring levels, and the custom   |
//| price line is a zone EDGE (the ladder's centre sits half a step    |
//| above it, P-UI-98's `shiftedCenter`), so the drawn family is:      |
//|                                                                   |
//|     above:  start + 1*step, + 2*step, + 3*step ...  (= _Above_1)   |
//|     below:  start + 0*step, - 1*step, - 2*step ...  (= _Below_2)   |
//|                                                                   |
//| `_Below_1` is the boundary between the centre zone and the first   |
//| below zone: it is drawn ON the custom price line, so its red icon  |
//| landed exactly under the custom price line's green one - the two   |
//| reds the user saw, one of them «خیلی نزدیک». And the drag math     |
//| (`newFirst = |dragged - start| / natural`, the ONE owner in        |
//| EventHandlers) only reads correctly for a line that IS one step    |
//| from the start: on the coincident line it read 0 at rest and any   |
//| hair of a downward move collapsed the whole ladder to a fraction   |
//| of a step - «step اول سریع قطع میشه».                             |
//|                                                                   |
//| So the handle is picked by GEOMETRY, never by rung number: on each |
//| side, the drawn trigger line nearest ONE STEP from the custom      |
//| price line, and never a line closer than half a step to it (the    |
//| coincident boundary can never carry a handle - nothing may be      |
//| grabbed on top of the custom price line's own handle). The step is |
//| the project's ONE owner of "the current step", F x the F-free       |
//| natural first step the mode factory noted, so the pick is          |
//| invariant under the override: F scales every line and the step     |
//| together, and the same two lines stay the handle (a drag can       |
//| never hand the gesture to a different line mid-flight).            |
//+------------------------------------------------------------------+
void Step1HandlePick(const STriggerLine &lines[], const int lineCount,
                     const double anchor, const double stepNow,
                     string &aboveName, string &belowName)
{
    aboveName = "";
    belowName = "";
    if(!(anchor > 0.0) || !(stepNow > 0.0)) return;   // no step known = no handle
    double bestAbove = 0.0, bestBelow = 0.0;
    for(int i = 0; i < lineCount; i++)
    {
        if(lines[i].isMidpoint) continue;
        if(!(lines[i].price > 0.0) || !MathIsValidNumber(lines[i].price)) continue;
        double dist = MathAbs(lines[i].price - anchor);
        if(dist < stepNow * 0.5) continue;             // on the anchor: never a handle
        double err = MathAbs(dist - stepNow);          // how far from ONE step
        if(lines[i].direction > 0)
        {
            if(aboveName == "" || err < bestAbove)
            { bestAbove = err; aboveName = lines[i].name; }
        }
        else
        {
            if(belowName == "" || err < bestBelow)
            { bestBelow = err; belowName = lines[i].name; }
        }
    }
}

//+------------------------------------------------------------------+
//| P-UI-131j - THE TRIGGER LABEL'S OWN COLOUR + OPACITY.            |
//|                                                                  |
//| The trigger card has carried a LABEL COLOR row since the first   |
//| card layout and nothing ever read it: the pip label took the     |
//| unified line colour. The row is now live, with an opacity beside |
//| it (the LABEL OPACITY row), and BOTH ends of both are AUTO -     |
//| which is the shipped picture, so an untouched chart cannot move. |
//|                                                                  |
//| Lives here, not in RuntimeSettings (which owns the two mirrors), |
//| because the generic blender `GetZoneRenderColor` is defined in   |
//| ZoneFactory, a LATER file than RuntimeSettings - same include      |
//| order that made the two effective-colour getters there duplicate |
//| the blend inline. Cost: the AUTO/AUTO call is one cached         |
//| getter, and a pinned one blends once per render pass.            |
//+------------------------------------------------------------------+
color GetTriggerLabelRenderColor()
{
    if(g_triggerLabelColor == clrNONE && g_triggerLabelTransparency < 0)
        return GetLineRenderColor();   // AUTO/AUTO = P-UI-66's shipped look
    color base = (g_triggerLabelColor == clrNONE) ? g_lineColor : g_triggerLabelColor;
    int   tr   = (g_triggerLabelTransparency >= 0) ? g_triggerLabelTransparency
                                                   : g_lineTransparency;
    return GetZoneRenderColor(base, tr);
}

void RenderTriggerLines(
    const STriggerLine &lines[],
    const int lineCount,
    const SModeConfig &config,
    const bool makeLines,
    const bool makeLabels,
    const double vpTop,
    const double vpBottom)
{    double currentPrice = GetCurrentPriceForLabels();

    // P-UI-98f: the step-1 handle is picked by GEOMETRY once per render (the
    // line one step from the custom price on each side - see Step1HandlePick),
    // so the face owner below is reached by the same pair the click and drag
    // channels will answer, in every start-point mode (the owner itself makes
    // the handle grabbable in the custom-price mode only).
    string s1AboveName = "", s1BelowName = "";
    Step1HandlePick(lines, lineCount, GetMidpointPrice(g_thStartPointType),
                    StepOverrideFactor() * NaturalFirstStep(),
                    s1AboveName, s1BelowName);

    // P-UI-66: THE LOOK IS A PAINT PROPERTY. `lines[].clr/lineStyle/lineWidth`
    // are the BUILD's copy of the unified [08.4] look, and they are only correct
    // in the frame that rebuilt the geometry (see PipelineGeometryKey). Painting
    // from them is what made the Lines card's WIDTH and STYLE rows dead: the
    // panel wrote the global, the key stayed equal, the cache served the old
    // array, and the old array painted the old look.
    //
    // Read once per pass - `GetLineRenderColor()` is change-cached internally,
    // and every writer below is already change-guarded against the object cache
    // (`CreateOrUpdateHLine` compares colour/style/width before it writes), so a
    // steady frame still costs zero terminal calls for an unchanged look.
    color           lineClr   = GetLineRenderColor();
    // P-UI-131j: read once per pass - the trigger label's own surface. In the shipped
    // AUTO state this is the line colour again (one cached getter, three compares).
    color           lblClr    = GetTriggerLabelRenderColor();
    ENUM_LINE_STYLE lineStyle = inpLineStyle;
    int             lineWidth = inpLineWidth;

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

        // P-UI-98: the step-1 handle. While ITS gesture is live the line is
        // MT4's to move: nothing on the object (P-BK-15), and the recomputed
        // line price equals the dragged price anyway (it is where F came
        // from) — the settle frame re-asserts it. Keyed on the NAME alone
        // (P-UI-98f): the handle is not always the ladder's rung 1, so a rung
        // number here let the render write the line the hand was holding.
        if(g_s1DragLive && lines[i].name == g_s1DragName)
            continue;

        // ALL pipeline lines (trigger-subdivision AND structure-interval)
        // share the unified [08.4] appearance set in ClassifyLevels. They are
        // drawn whenever the Lines switch (L / g_linesVisible) shows them and
        // are NEVER hidden or restyled by the trigger switch. RenderZones is
        // the ONLY place the trigger overlay hides things — the trigger ZONES.
        // (The old Factor hideLineWhenTriggerOnly inversion is retired: every
        //  mode config leaves it false, and line visibility belongs to L alone.)
        // P-VIEW-01 (2026-09-29) — THE CULL DECIDES PAINT, THE VIEWPORT NEVER OWNS
        // VISIBILITY. This branch used to write OBJ_NO_PERIODS on the line AND its
        // label, i.e. the window HID them, and only the frame that re-evaluated
        // `inViewport` could bring them back. Measured on this machine: the cull
        // window is deliberately allowed to lag P_P4_VP_HYSTERESIS_PCT = 0.20 of the
        // visible range (ExtDraw_A.mqh 105-125) while the geometry signature that
        // decides whether a render runs AT ALL carries that same window
        // (EventHandlers_Calc.mqh 1329-1330). So a level the price walked to could sit
        // hidden through any number of frames — exactly the report «سطوح حذف میشه
        // ولی دیگه نمیاد تا یک تکونی به چارت بدم» — and every window re-derivation
        // flipped the mask on hundreds of objects in ONE frame, which is the flicker
        // that carried the whole chart with it (the card and the countdown are
        // re-created by the same rebuild).
        //
        // The mask is now the OWNER's (F / L / IsIndicatorHidden), asserted exactly as
        // the in-window path asserts it and read-guarded in ApplyTfMaskGuarded — zero
        // writes in steady state, one cache read per object — and this branch only
        // skips the PAINT. The object keeps its price, so when the user scrolls to it
        // MT4 draws it from its own state at its own paint time: nothing to wait for,
        // nothing to flip, no cost on this side (that is the "قبل از کاربر" order).
        long lineTf  = (IsIndicatorHidden() || !g_linesVisible) ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
        long labelTf = IsIndicatorHidden() ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
        // P-VIEW-03 (2026-09-29) — THE WINDOW IS NOT AN OWNER OF THE OBJECT, AND A
        // FRAME THAT SKIPS A PAINT IS A LEVEL THAT CAN STAY MISSING.
        //
        // This is where an `if(!inView) { assert mask; continue; }` fence stood (and,
        // before that, an `if(!inView) SetPipelineObjectTimeframesIfExists(...,
        // OBJ_NO_PERIODS)`). Both shapes are the same defect with different clothes:
        // they make the object's EXISTENCE depend on the moment the render happened
        // to run, and nothing guarantees a later frame re-decides it. MEASURED in the
        // user's own chart (2026-09-29, EURUSD M15, this build): the family above the
        // live price was drawn from 1.15185 up to 1.17630 and two rungs at the bottom
        // (1.11520 / 1.11250) were drawn, while the whole band around the price —
        // 1.11520..1.15185, nine rungs on the same 41-pip pitch — was simply ABSENT.
        // A hole in the MIDDLE cannot come from the level list (the ladder is built
        // outward from the centre and is contiguous, and BuildZonesAndLines culls
        // nothing — it only FLAGS `inViewport`), so the band existed in `lines[]` and
        // was skipped here, with no later frame to bring it back after a scale change.
        //
        // The law this restores, and it is the same one the class already follows for
        // zones and labels: THE WINDOW DECIDES NOTHING. Every level the build produced
        // is asserted with the OWNER's mask (F / L / IsIndicatorHidden, read-guarded in
        // ApplyTfMaskGuarded) and painted; MT4 clips what is off the chart itself, and
        // that clipping costs this indicator nothing. "Painted but off-screen" is free;
        // "not painted and back in view" is a hole.
        //
        // Cost, stated: the loop no longer skips, so a level outside the window now
        // runs the same change-guarded `CreateOrUpdateHLine` the in-window ones run —
        // a handful of property reads that write NOTHING when the object already holds
        // those values (P-PERF-51's law), against a full level family (bounded by the
        // ladder's own count, the same number the level list already carries). And it
        // removes the reason for a pan to rebuild anything: with no window term in the
        // frame signature (P-VIEW-02) a scroll now costs zero indicator work AND the
        // picture is complete, which is the "قبل از کاربر" order the user asked for.
        //

        // Use the individual line color instead of config.triggerColor
        if(makeLines) {
            bool isNew = CreateOrUpdateHLine(lines[i].name, lines[i].price,
                                              lineClr, lineStyle, lineWidth,
                                              lines[i].tooltip);
            SetPipelineObjectTimeframesIfExists(lines[i].name, lineTf);   // P-VIEW-01: hoisted, one owner

            // Set mode-specific properties on new objects
            if(isNew) {
                if(config.useObjPropBack) {
                    ObjectSetInteger(0, lines[i].name, OBJPROP_BACK, false);
                }
                if(config.zOrder > 0) {
                    ObjectSetInteger(0, lines[i].name, OBJPROP_ZORDER, config.zOrder);
                }
            }
            // P-UI-98: the face is owned AFTER the creator — CreateOrUpdateHLine
            // writes SELECTABLE=false on every fresh object, so a face write
            // before it landed on nothing and a just-created handle stayed
            // un-grabbable until a topology change re-rendered the family.
            if(lines[i].name == s1AboveName || lines[i].name == s1BelowName)
                Step1HandleOwnFace(lines[i].name, lines[i].price, lines[i].direction,
                                   lineTf, lines[i].tooltip);
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
            // P-UI-66: the pip label wears the same live look as its line -
            // `lines[i].clr` is the BUILD's copy, so a colour edit would have
            // gone stale on the label in exactly the frames the line was fixed
            // up in (`CreatePipDistanceLabel` is change-guarded too).
            // P-UI-131j: ... unless the level is the TRIGGER's, whose label is a
            // surface of its own (`lblClr` == `lineClr` while both its ends are AUTO).
            CreatePipDistanceLabel(labelName, lines[i].price, pips,
                                   lines[i].isTrigger ? lblClr : lineClr,
                                   lines[i].labelText);
            SetPipelineObjectTimeframesIfExists(labelName, labelTf);   // P-VIEW-01: hoisted, one owner
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
    // During a hand-set drag (custom-price or step-1), do lightweight throttled
    // cleanup instead of skipping entirely. P-UI-98i: the step-1 drag re-steps
    // the ladder live like the line's drag, so it owns the same throttle - a
    // full surplus sweep mid-gesture deletes under the hand.
    if(g_customPriceLineDragging || g_s1DragLive) {
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

#endif // LEVEL_PIPE_A_MQH
