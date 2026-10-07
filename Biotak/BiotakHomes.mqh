// BiotakHomes.mqh - the PLACE of the three placeable surfaces, split out of
// BiotakMenu_A.mqh on 2026-10-05 because that file reached 1532 lines and
// contract 7 says a file over the 1500-line ceiling never grows (P-SIZE-1500):
// touch it = split it by owner. This IS that owner - one home per surface, the
// fraction it is stored as, and the one default when there is no home at all.
//
// MUST be included ABOVE BiotakMenu_A.mqh: MQL4 resolves a call top-down, and
// every reader of a home (LoadUIPlaces, SaveUIStates, the orb's release, the
// chip's drag) lives below the cut, so a half included under them is error 168.
#ifndef BIOTAK_HOMES_MQH
#define BIOTAK_HOMES_MQH

//+------------------------------------------------------------------+
//| P-UI-118 — THE ORB'S DEFAULT HOME IS THE CHART'S CENTRE, ONE OWNER.|
//|                                                                  |
//| User order 2026-09-25: «منو وسط باز بشه از هر طرف» — the menu must |
//| open as a RING, fanning from every side. `CircLayout` leaves the   |
//| arc the moment the orb is within `CIRC_EDGE_TRIGGER` (90 px) of    |
//| any edge and collapses the ring into a train along it — which is   |
//| exactly what a corner-parked orb does, and what the Tools          |
//| sub-menu escalates away from (fan -> rail -> grid). The centre is  |
//| the ONLY position where every layout family is reachable as         |
//| designed, so it is the default.                                    |
//|                                                                  |
//| BOTH readers ask here — the first-attach default and the fallback  |
//| when a saved position is missing — so the two can never disagree    |
//| about where "default" is. A SAVED position still wins: the user's   |
//| drag is the truth, and only a chart with no stored pair lands here. |
//| The value is clamped like every other orb write on the next pass.   |
//+------------------------------------------------------------------+
void CircDefaultMenuPos(int &x, int &y)
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1920;
   if(ch <= 0) ch = 1080;
   x = cw / 2;
   y = ch / 2;
}

//--- P-UI-131e — A HOME THAT OUTLIVES THE CHART AND THE SYMBOL. User order: «در هر چارت
//--- در هر شرایط همون جا باشه، بدون هزینه». A placed surface is the HAND's preference,
//--- not a fact of one window: the keys still carried ChartID(), and a CLAMP was saved
//--- back into the live pair (so one narrow chart ratcheted the place for good). A home
//--- lives under a key with no chart and no symbol in it; the value that paints is never
//--- the value stored; cost is one read at load and one write when the hand really moves.
string GVHomeName(const string id,const bool y) { return "BIOMENU_HOME_" + id + (y ? "Y" : "X"); }

//--- one home, three readers (the orb, the strip, the chip): the chart-free pair first,
//--- then the pre-131e per-chart pair it replaced, so the upgrade keeps the place the
//--- hand already chose instead of re-seeding the default. Absent both = no home.
bool GVHomeLoad(const string id,const string legacyInfix,int &x,int &y)
{
   string nx = GVHomeName(id,false), ny = GVHomeName(id,true);
   if(GlobalVariableCheck(nx) && GlobalVariableCheck(ny))
   {
      x = (int)GlobalVariableGet(nx); y = (int)GlobalVariableGet(ny);
      if(x >= 0 && y >= 0) return true;
   }
   string lx = GetGVName(legacyInfix + "X"), ly = GetGVName(legacyInfix + "Y");
   if(GlobalVariableCheck(lx) && GlobalVariableCheck(ly))
   {
      x = (int)GlobalVariableGet(lx); y = (int)GlobalVariableGet(ly);
      if(x >= 0 && y >= 0) return true;
   }
   x = -1; y = -1;
   return false;
}

//--- the orb's own home. -1 = the hand has never placed it: CircDefaultMenuPos answers.
static int s_OrbHomeX = -1, s_OrbHomeY = -1;
bool CircOrbHomeGet(int &x,int &y)
{
   x = s_OrbHomeX; y = s_OrbHomeY;
   return (s_OrbHomeX >= 0 && s_OrbHomeY >= 0);
}
void CircOrbHomeSet(const int x,const int y) { s_OrbHomeX = x; s_OrbHomeY = y; }

//--- P-UI-126: THE CHIP'S OWN PLACE — P-DRAW-41's home, one surface over, and owned
//--- here because the UI-state block below is its only reader and writer. (-1,-1) =
//--- the hand has never placed it: the chart's middle then answers, measured LIVE so a
//--- resized chart is never stuck with a stale centre. Stored as the BOX's centre.
static int s_TipHomeX = -1, s_TipHomeY = -1;
bool CircTipHomeGet(int &x, int &y)
{
   x = s_TipHomeX; y = s_TipHomeY;
   return (s_TipHomeX >= 0 && s_TipHomeY >= 0);
}
void CircTipHomeSet(const int x, const int y) { s_TipHomeX = x; s_TipHomeY = y; }

//+------------------------------------------------------------------+
//| P-UI-140 (2026-10-05) — A PLACE IS A PLACE ON THIS WINDOW.        |
//| Report: «این دوتا موقع ریستارت ترمینال از جاش تکون میخوره» — the  |
//| orb and the chip both MOVED on restart. Cause: both homes were     |
//| stored as ABSOLUTE PIXELS, a restart re-lays the window out, so    |
//| the same number is painted in a different box and clamped into it; |
//| a stored centre made it worse, because `ohx == defX` then read the |
//| OLD centre as «the hand moved it». ONE RULE, every scenario       |
//| (restart, resize, maximize, another monitor, another symbol or    |
//| chart): the STORED form is a FRACTION of the chart box and the     |
//| painted pixels are re-derived from it against the LIVE metrics —   |
//| (0.5,0.5) is the centre of every window, which retires the centre |
//| heuristic. Nothing is re-saved on the way (that ratchet is         |
//| P-UI-131e again) and a pixel home is migrated once, in the window   |
//| it is read in. Long form: docs/th3-ui-placement.md                  |
//+------------------------------------------------------------------+
string GVHomeFracName(const string id,const bool y) { return "BIOMENU_HOME_" + id + (y ? "_FY" : "_FX"); }
void HomeChartSize(int &cw, int &ch)
{
   cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1920;  if(ch <= 0) ch = 1080;   // the fallback every reader keeps
}
//--- the WRITER's size: no fallback. A fraction divided by a window that is not
//--- the one the pixels came from is the poisoned store (measured CHIP_FX=1.1075
//--- above) — and at teardown the terminal can report 0 for a window it is
//--- destroying. A writer that cannot measure the box stores nothing.
bool HomeChartSizeRaw(int &cw, int &ch)
{
   cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   return (cw > 0 && ch > 0);
}
bool GVHomeFracKnown(const string id)
{
   return GlobalVariableCheck(GVHomeFracName(id,false)) && GlobalVariableCheck(GVHomeFracName(id,true));
}
//--- ONE place a pixel becomes a fraction, so the writer and the slot guards in
//--- `SaveUIStates` can never disagree about what was stored.
double HomeFracOf(const int v, const int span)
{
   if(span <= 0) return 0.5;
   return (double)v / (double)span;
}
//--- ONE clamp, used by the reader below and by `GVHomeSaveFrac`. A live drag is already
//--- inside the window, so the write side only bites the one case that can be outside it:
//--- `SaveUIStates` re-deriving a pair whose window has since shrunk. A store holding a
//--- place outside the box is the state the reader has to repair; nothing here may
//--- create it, or the pair drifts a little further on every re-derivation.
double HomeFracClamp(const double f)
{
   if(f < 0.0) return 0.0;
   if(f > 1.0) return 1.0;
   return f;
}
//--- the ONE reader of a fractional home, and the only one the 250 ms pass may use:
//--- fractions only, NO writes. A read that repairs the store is a write under the
//--- user's hand — the ratchet P-UI-131e removed.
//---
//--- MEASURED 2026-10-05 in the trade terminal (`profiles/gvariables.dat`, read twice):
//--- a pair can sit OUTSIDE the box — that store carried `CHIP_FX = 1.1075`, greater
//--- than 1, in both reads (its sibling `ORB_FY` also read 1.613 once and was rewritten
//--- between the two reads, because the terminal keeps saving while it runs: that
//--- rewriting is the creep this block ends). The cause is a fraction divided by a
//--- window that was not the one the pixels came from. Such a value is not garbage: it
//--- is the same place said with a wrong denominator, so the place it MEANS is the near
//--- EDGE. So the reader CLAMPS (`1.1075` becomes `1.0` = the right edge, `0.0896` stays
//--- = the top, i.e. the pinned top-right chip of the report) — a reader that refused
//--- instead would drop a placed surface to the chart's centre, i.e. MOVE it on the
//--- upgrade that was supposed to stop the moving.
//--- Clamping is also what makes the answer DETERMINISTIC: every restart derives the
//--- same pixels from the same pair, so the drift cannot resume.
bool GVHomeFracRead(const string id, int &x, int &y)
{
   if(!GVHomeFracKnown(id)) return false;
   const double fx = HomeFracClamp(GlobalVariableGet(GVHomeFracName(id,false)));
   const double fy = HomeFracClamp(GlobalVariableGet(GVHomeFracName(id,true)));
   int cw = 0, ch = 0; HomeChartSize(cw, ch);
   x = (int)MathRound(fx * cw);
   y = (int)MathRound(fy * ch);
   return true;
}
void GVHomeSaveFrac(const string id, const int x, const int y)
{
   if(x < 0 || y < 0) return;
   int rcw = 0, rch = 0;
   if(!HomeChartSizeRaw(rcw, rch)) return;   // unknown denominator: store nothing,
                                            // and keep the pixel keys (no data loss)
   GlobalVariableSet(GVHomeFracName(id,false), HomeFracClamp(HomeFracOf(x, rcw)));
   GlobalVariableSet(GVHomeFracName(id,true), HomeFracClamp(HomeFracOf(y, rch)));
   //--- the pixel keys are dead on arrival: a reader that adopts a window-sized
   //--- number as a place is the bug this block exists to end.
   GlobalVariableDel(GVHomeName(id,false)); GlobalVariableDel(GVHomeName(id,true));
}
bool GVHomeLoadFrac(const string id, const string legacyInfix, int &x, int &y)
{
   if(GVHomeFracRead(id, x, y)) return true;
   int px = 0, py = 0;
   if(!GVHomeLoad(id, legacyInfix, px, py)) { x = -1; y = -1; return false; }
   GVHomeSaveFrac(id, px, py);          // migration, once, in the reading window
   x = px; y = py;
   return true;
}

#endif // BIOTAK_HOMES_MQH
