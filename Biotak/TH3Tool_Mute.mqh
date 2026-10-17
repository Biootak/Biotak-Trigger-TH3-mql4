// TH3Tool_Mute.mqh — P-UI-160b (2026-10-16): the DRAWING families' answer to
// the F mute. Split out of TH3Tool_A/TH3Tool_B by P-SIZE-1500 (both crossed the
// 1500-line ceiling): the four functions below are byte-identical moves, zero
// renames. Included by TH3Tool.mqh after TH3Tool_D, so TH3LadderSetVisible /
// TH3InfoFamilySetVisible (TH3Renderer_A, reached through TH3Tool_A) and the leg
// meter's writers (TH3Tool_B) are all defined above them.
#ifndef TH3_TOOL_MUTE_MQH
#define TH3_TOOL_MUTE_MQH

// ── P-UI-160b (2026-10-16) — THE PATTERN FAMILY ANSWERS THE F MUTE ───
// The report: «دکمه f که فقط زون ها رو خاموش و روشن میکنه پیس همه رو باید خاموش
// بکنه». Same law as the leg meter's LegMeasureHideAll: the mute is a STATE
// (P-PERF-02), applied once per transition. This family hides through its OWN
// owners, NEVER through a delete — the store is the source of truth and the
// delete cascade would read a swept family as a lost pattern (the store-wipe
// branch of OnABCDMouseEvent). The ladder and the caption are mask owners
// (TH3LadderSetVisible / TH3InfoFamilySetVisible — the plate drops by
// EXISTENCE, P-TH3-INFO-10, and that drop is routine maintenance); everything
// else the namespace carries (points, legs, labels, rays, zone lines and
// boxes, borders, the MP overlay, temps) is chart-space and takes
// OBJ_NO_PERIODS directly, skipping the two owner families so the owners'
// own states are never fought. Show re-asserts the owners' own states — one
// ladder lit (P-TH3-P6f), the rest dark — and the caption heals through the
// frame's own RepositionABCDInfoLabels (the visit clock stays the only clock).
int TH3PatternsHideAll()
{
    for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
    {
        string nm = ObjectName(0, i, -1, -1);
        bool ours = (StringFind(nm, TH3_PATTERN_PREFIX) == 0 ||
                     StringFind(nm, TH3_TEMP_PREFIX) == 0 ||
                     StringFind(nm, "TH3_MP_") == 0);   // the MP overlay's own namespace
        if(!ours) continue;
        if(TH3IsLadderName(nm) || TH3IsInfoLabelName(nm)) continue;   // owners below
        if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    }
    int n = TH3PatternStoreCount();
    for(int i = 0; i < n; i++)
    {
        string base = g_th3Patterns.items[i].name;
        TH3LadderSetVisible(base, false);
        TH3InfoFamilySetVisible(base, false);   // rows mask, plate drops (existence)
    }
    return n;
}

int TH3PatternsShowAll()
{
    for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
    {
        string nm = ObjectName(0, i, -1, -1);
        bool ours = (StringFind(nm, TH3_PATTERN_PREFIX) == 0 ||
                     StringFind(nm, TH3_TEMP_PREFIX) == 0 ||
                     StringFind(nm, "TH3_MP_") == 0);
        if(!ours) continue;
        if(TH3IsLadderName(nm) || TH3IsInfoLabelName(nm)) continue;   // owners below
        if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
            ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    int n = TH3PatternStoreCount();
    for(int i = 0; i < n; i++)
    {
        string base = g_th3Patterns.items[i].name;
        TH3LadderSetVisible(base, (base == g_activeABCDPattern));   // P-TH3-P6f: one ladder lit
    }
    return n;
}

// ── P-UI-160b (2026-10-16) — THE FAMILY ANSWERS THE F MUTE ───────────
// The report: «دکمه f که فقط زون ها رو خاموش و روشن میکنه پیس همه رو باید خاموش
// بکنه» — F darkened the level families and left every DRAWING standing (this
// one, the ABCD family, the rays and the paths). The mute is a STATE (P-PERF-02),
// so hide masks what a mask can reach and parks what it cannot, once per
// transition; show undoes exactly that, and the riders (LegMeasureHandles /
// LegMeasureInk) carry the same hidden term so no channel can re-show a line
// the mute took. The plate is a timed readout — its visit does not survive the
// mute (the same rule the expiry already enforces).
int LegMeasureHideAll()
{
    int n = 0;
    for(int i = 0; i < g_legCount; i++)
    {
        string ln = g_legBase[i] + "_Line";
        if(ObjectFind(0, ln) < 0) continue;
        if((int)ObjectGetInteger(0, ln, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
            ObjectSetInteger(0, ln, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
        LegMeasureHandles(g_legBase[i],
                          (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0),
                          ObjectGetDouble(0, ln, OBJPROP_PRICE, 0),
                          (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 1),
                          ObjectGetDouble(0, ln, OBJPROP_PRICE, 1),
                          g_legAccent[i]);              // parks through its hidden branch
        LegMeasurePlateHide(i);
        n++;
    }
    return n;
}

int LegMeasureShowAll()
{
    int n = 0;
    for(int i = 0; i < g_legCount; i++)
    {
        string ln = g_legBase[i] + "_Line";
        if(ObjectFind(0, ln) < 0) continue;
        if((int)ObjectGetInteger(0, ln, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
            ObjectSetInteger(0, ln, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        n++;
    }
    // the icons ride back through the ONE rider (the same pass the timer runs)
    LegMeasureRideChart();
    return n;
}

#endif // TH3_TOOL_MUTE_MQH
