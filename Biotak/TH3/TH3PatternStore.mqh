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
//| Build a TH3Pattern model from A/B/C (+optional X)                |
//| Computes D via the pure AB=CD rule. Returns false if invalid.    |
//+------------------------------------------------------------------+
bool TH3PatternBuild(const string name,
                     datetime tX, double pX,
                     datetime tA, double pA,
                     datetime tB, double pB,
                     datetime tC, double pC,
                     TH3Pattern &out)
{
    datetime tD;
    double pD;
    if(!CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD)) return false;

    out.name = name;
    out.X.time = tX;   out.X.price = pX;
    out.A.time = tA;   out.A.price = pA;
    out.B.time = tB;   out.B.price = pB;
    out.C.time = tC;   out.C.price = pC;
    out.D.time = tD;   out.D.price = pD;
    out.bullish = (pB > pA);
    out.frequency = 0; // set by caller (auto-selected or override)
    return true;
}

#endif // TH3_PATTERN_STORE_MQH
