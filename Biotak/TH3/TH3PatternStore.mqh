//+------------------------------------------------------------------+
//| TH3/TH3PatternStore.mqh                                          |
//| In-memory registry of TH3Pattern models - the single source of   |
//| truth. Chart objects are only a projection (TH3Renderer.mqh).    |
//| The old registry stored only NAMES; this stores full models.     |
//+------------------------------------------------------------------+
#ifndef TH3_PATTERN_STORE_MQH
#define TH3_PATTERN_STORE_MQH
#property strict

#include "TH3Types.mqh"
#include "TH3Math.mqh"

TH3PatternList g_th3Patterns;

//+------------------------------------------------------------------+
//| Find a pattern by name (-1 if not found)                         |
//+------------------------------------------------------------------+
int TH3PatternStoreFind(const string name)
{
    for(int i = 0; i < g_th3Patterns.count; i++) {
        if(g_th3Patterns.items[i].name == name) return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Add or replace a pattern model                                   |
//+------------------------------------------------------------------+
bool TH3PatternStoreAdd(const TH3Pattern &pattern)
{
    int idx = TH3PatternStoreFind(pattern.name);
    if(idx >= 0) {
        g_th3Patterns.items[idx] = pattern;
        return true;
    }
    if(g_th3Patterns.count >= TH3_MAX_PATTERNS) return false;
    g_th3Patterns.items[g_th3Patterns.count] = pattern;
    g_th3Patterns.count++;
    return true;
}

//+------------------------------------------------------------------+
//| Remove a pattern model by name                                   |
//+------------------------------------------------------------------+
bool TH3PatternStoreRemove(const string name)
{
    int idx = TH3PatternStoreFind(name);
    if(idx < 0) return false;
    for(int i = idx; i < g_th3Patterns.count - 1; i++) {
        g_th3Patterns.items[i] = g_th3Patterns.items[i + 1];
    }
    g_th3Patterns.count--;
    return true;
}

//+------------------------------------------------------------------+
//| Get a pattern model by name                                      |
//+------------------------------------------------------------------+
bool TH3PatternStoreGet(const string name, TH3Pattern &out)
{
    int idx = TH3PatternStoreFind(name);
    if(idx < 0) return false;
    out = g_th3Patterns.items[idx];
    return true;
}

//+------------------------------------------------------------------+
//| Count of registered patterns                                     |
//+------------------------------------------------------------------+
int TH3PatternStoreCount()
{
    return g_th3Patterns.count;
}

//+------------------------------------------------------------------+
//| Clear the registry (does NOT touch chart objects)                |
//+------------------------------------------------------------------+
void TH3PatternStoreClear()
{
    g_th3Patterns.count = 0;
}

//+------------------------------------------------------------------+
//| Build a TH3Pattern model from A/B/C/D                            |
//| If D is not provided, computes D via the AB=CD rule.             |
//+------------------------------------------------------------------+
bool TH3PatternBuild(const string name,
                     datetime tA, double pA,
                     datetime tB, double pB,
                     datetime tC, double pC,
                     datetime tD, double pD,
                     TH3Pattern &out)
{
    if(tD <= 0 || pD <= 0) {
        if(!CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD)) return false;
    }

    out.name = name;
    out.X.time = 0;    out.X.price = 0;
    out.A.time = tA;   out.A.price = pA;
    out.B.time = tB;   out.B.price = pB;
    out.C.time = tC;   out.C.price = pC;
    out.D.time = tD;   out.D.price = pD;
    out.bullish = (pB > pA);
    out.frequency = 0; // set by caller (auto-selected or override)
    // P-TH3-PB-OFF (2026-09-21): the drawn base is retired — a fresh model
    // carries none, and Path 1 comes from `inpTH3PivotBasePips` instead.
    out.pivotBaseTop = 0;
    out.pivotBaseBottom = 0;

    // Measure the five arrangement axes off the bars and derive the step they
    // imply. A pattern that cannot be measured still builds - it just carries an
    // INVALID skeleton rather than a fabricated one, so "unmeasured" stays
    // distinguishable from "a standard pivot with no cover" all the way out.
    out.skeleton.valid = false;
    TH3Skeleton skel;
    if(TH3SkeletonFromBars(tA, pA, tB, pB, tC, pC, skel)) out.skeleton = skel;

    return true;
}

// P-TH3-D4: legacy X overload removed (same arity as the A/B/C/D build,
// MQL4 error 165). Callers pass placed A/B/C/D directly.
#endif // TH3_PATTERN_STORE_MQH
