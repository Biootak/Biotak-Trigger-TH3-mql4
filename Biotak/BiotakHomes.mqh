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

//--- P-UI-131e — A HOME THAT OUTLIVES THE CHART. User order: «در هر چارت در هر شرایط
//--- همون جا باشه، بدون هزینه». A placed surface is the HAND's preference, not a fact
//--- of one window: the keys still carried ChartID(), and a CLAMP was saved back into
//--- the live pair (so one narrow chart ratcheted the place for good). A home lives
//--- under a key with no chart id in it; the value that paints is never the value
//--- stored; cost is one read at load and one write when the hand really moves.
//---
//--- P-UI-165 (2026-10-17) — THE PLACE BELONGS TO THE PAIR. User report: several
//--- indicators on different pairs «تداخل نداشته باشیم باهم و همین باعث میشه این
//--- مشکلات پیش بیاد» — 131e's chart-free key made ONE pair's hand land EVERY other
//--- pair (an orb parked near an edge came back near the edge everywhere, and
//--- P-UI-164's squeezed ring followed it). The SYMBOL is now in the key; the CHART
//--- ID still may not be (it is per SESSION — a home would be lost on every restart,
//--- the very defect 131e fixed). The pre-165 spellings below are READ-ONLY
//--- migration sources: `GVHomeLoadFrac` snapshots the shared pair into the pair's
//--- own key once, in a measured window, and no writer ever writes or deletes the
//--- shared keys — every other pair still needs them until it migrates.
string GVHomeName(const string id,const bool y) { return "BIOMENU_" + _Symbol + "_HOME_" + id + (y ? "Y" : "X"); }
string GVHomeNameShared(const string id,const bool y) { return "BIOMENU_HOME_" + id + (y ? "Y" : "X"); }

//--- one home, three readers (the orb, the strip, the chip): the pair's OWN pixel pair
//--- first, then the pre-165 shared pair, then the pre-131e per-chart pair it replaced,
//--- so the upgrade keeps the place the hand already chose instead of re-seeding the
//--- default. Absent all three = no home.
bool GVHomeLoad(const string id,const string legacyInfix,int &x,int &y)
{
   string nx = GVHomeName(id,false), ny = GVHomeName(id,true);
   if(GlobalVariableCheck(nx) && GlobalVariableCheck(ny))
   {
      x = (int)GlobalVariableGet(nx); y = (int)GlobalVariableGet(ny);
      if(x >= 0 && y >= 0) return true;
   }
   string sx = GVHomeNameShared(id,false), sy = GVHomeNameShared(id,true);   // P-UI-165 legacy
   if(GlobalVariableCheck(sx) && GlobalVariableCheck(sy))
   {
      x = (int)GlobalVariableGet(sx); y = (int)GlobalVariableGet(sy);
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
string GVHomeFracName(const string id,const bool y) { return "BIOMENU_" + _Symbol + "_HOME_" + id + (y ? "_FY" : "_FX"); }
string GVHomeFracNameShared(const string id,const bool y) { return "BIOMENU_HOME_" + id + (y ? "_FY" : "_FX"); }
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
//+------------------------------------------------------------------+
//| P-UI-157 (2026-10-13) — A PLACE IS DERIVED AND STORED IN THE SAME |
//| WINDOW.                                                           |
//|                                                                   |
//| Report: «این هنوز جابجا میشه بعد اینکه متاتریدر باز و بسته میکنم  |
//| ... راه حل متفاوت که کار بکنه». MEASURED in `gvariables.dat`     |
//| across ONE close/open cycle (2026-10-13, 15:50 -> 15:56) — EVERY  |
//| stored place had moved:                                           |
//|     CHIP_FX  0.942731 -> 0.618392      ORB_FX  0.023128 -> 0.237335|
//|     ORB_FY   0.937656 -> 0.748130      STRIP_FX 0.296806 -> 0.606828|
//| and the terminal's own screenshot pair showed the «تریگر پرایس      |
//| اکشن» chip 589 px to the LEFT with an UNCHANGED y. A 15 s probe on |
//| the idle terminal showed the same keys FROZEN for two minutes — so |
//| the creep needs no user action and fires on ATTACH, which is the   |
//| report's own scenario.                                            |
//|                                                                   |
//| The whole family is ONE asymmetry. A home is a pair of PIXELS in   |
//| memory and a FRACTION on disk. The reader multiplies by the box it |
//| happens to see; the writer divides by the box it happens to see.   |
//| Whenever those are not the same window the fraction is REWRITTEN — |
//| and every path that could not measure the window substituted        |
//| 1920x1080 (`HomeChartSize`, `CircDefaultMenuPos`, `CircCreateOrb`,  |
//| `CircUIMetrics`, `DrawStripOpenAt`, `DrawStripPlaceFresh`), i.e. a  |
//| denominator the pixels did not come from. The substitution is the   |
//| creep: silent, needing no hand, firing exactly at attach and        |
//| teardown.                                                          |
//|                                                                   |
//| P-UI-158 (2026-10-13) — ONLY THE HAND MOVES A HOME.                |
//|                                                                   |
//| Report: «درست نشده ... پنل رینگ از چه روشی استفاده کرده مثل همون   |
//| بشه» — the chip still moved after a close/open, and the user asked  |
//| for the RING's method.                                             |
//|                                                                   |
//| THE RING HAS NO HOME. `CircMoveItem` derives every item from the   |
//| orb on every paint (`CircLayout(i, g_UI.menuX, g_UI.menuY)`), so    |
//| the ring CANNOT drift — there is no stored place of its own to      |
//| drift. The one place it does store is the ORB's, and that is        |
//| written in exactly ONE situation: the hand's own release.           |
//|                                                                   |
//| The chip had the other shape — a stored fraction AND an automatic   |
//| re-derivation that wrote it back (`SaveUIStates` re-derives all     |
//| three homes on every attach and teardown). A derivation in one      |
//| window and a save in another rewrites the fraction: the measured    |
//| creep (CHIP_FX 0.942731 -> 0.618392 across one close/open, a 589 px |
//| jump). P-UI-156 and P-UI-157 closed the two doors that could feed   |
//| it a wrong denominator; they did not remove the door.               |
//|                                                                   |
//| So the door goes. The AUTOMATIC path may not write a home at all.   |
//| A home changes only when a NEW ANSWER produced it — the hand's      |
//| release, the strip's first measured placement, a legacy migration.  |
//| `GVHomeAnswerNew(id)` is that claim. `SaveUIStates` still owns the  |
//| write, but through a door that refuses everything else. A derived   |
//| pair therefore PAINTS and is never STORED — exactly the ring's      |
//| property: derive freely, store only the hand's answer.              |
//+------------------------------------------------------------------+
//--- P-UI-165: true for the pair's OWN pair of keys OR the pre-165 shared pair, so a
//--- store written by the old build still answers on the first attach after the upgrade
//--- (and the snapshot in `GVHomeLoadFrac` can run).
bool GVHomeFracKnown(const string id)
{
   return (GlobalVariableCheck(GVHomeFracName(id,false)) || GlobalVariableCheck(GVHomeFracNameShared(id,false)))
       && (GlobalVariableCheck(GVHomeFracName(id,true))  || GlobalVariableCheck(GVHomeFracNameShared(id,true)));
}
//--- P-UI-165: the pair's OWN keys only — false while only the shared pair exists, and
//--- exactly that pair is the migration's trigger.
bool GVHomeFracKnownOwn(const string id)
{
   return GlobalVariableCheck(GVHomeFracName(id,false)) && GlobalVariableCheck(GVHomeFracName(id,true));
}
//--- P-UI-165: the value, from the pair's own key, else the pre-165 shared one (0.0 when
//--- neither exists). READ-ONLY — the one write is `GVHomeLoadFrac`'s snapshot door.
double GVHomeFracGet(const string id,const bool y)
{
   string own = GVHomeFracName(id,y);
   if(GlobalVariableCheck(own)) return GlobalVariableGet(own);
   return GlobalVariableGet(GVHomeFracNameShared(id,y));
}
//--- P-UI-158 — THE CLAIM. One flag per surface, because an answer is about a SURFACE,
//--- not a moment. It is set where a place is really decided (a release, a first
//--- measurement, a migration) and consumed by the one write that publishes it.
static bool s_homeAnsOrb = false, s_homeAnsStrip = false, s_homeAnsChip = false;
void GVHomeAnswerNew(const string id)
{
   if(id == "ORB")        s_homeAnsOrb   = true;
   else if(id == "STRIP") s_homeAnsStrip = true;
   else if(id == "CHIP")  s_homeAnsChip  = true;
}
bool GVHomeAnswerAny() { return (s_homeAnsOrb || s_homeAnsStrip || s_homeAnsChip); }
//--- spent when the homes were really evaluated (a box was measurable), NOT on every
//--- pass: a claim made while the terminal reports no window must survive to the first
//--- save that can measure one, or the hand's own drag would be lost at teardown.
void GVHomeAnswerClear() { s_homeAnsOrb = false; s_homeAnsStrip = false; s_homeAnsChip = false; }
//--- MQL4 forbids `static` on a global function (error 350), so this is a plain one; the
//--- door below is still the only caller, and the flag names are the private state.
bool GVHomeAnswerTake(const string id)
{
   if(id == "ORB")   { const bool had = s_homeAnsOrb;   s_homeAnsOrb   = false; return had; }
   if(id == "STRIP") { const bool had = s_homeAnsStrip; s_homeAnsStrip = false; return had; }
   if(id == "CHIP")  { const bool had = s_homeAnsChip;  s_homeAnsChip  = false; return had; }
   return false;
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
   //--- P-UI-156 (2026-10-13) — A READER WITH NO BOX DERIVES NOTHING.
   //--- Report: «این هنوز جابجا میشه بعد اینکه متاتریدر باز و بسته میکنم ... راه حل
   //--- متفاوت که کار بکنه». The reader used to fall back to 1920x1080 whenever the
   //--- terminal reported 0 for the chart box — and at attach and during a
   //--- CHART_CHANGE it does. That fallback is a DENOMINATOR THE PIXELS DID NOT COME
   //--- FROM, so the pair it produced was not a place, it was the same place said
   //--- with the wrong divisor. `CircHomesRefresh` then handed that pair to
   //--- `CircOrbHomeSet`/`CircTipHomeSet` — the in-memory HOME — and the next
   //--- `SaveUIStates` persisted `HomeFracOf(thatPair, the REAL box)`.
   //--- MEASURED, and still in the store: `BIOMENU_HOME_STRIP_FX` = **1.000000**
   //--- exactly, which is `HomeFracClamp` saturating a value that had gone past the
   //--- right edge; the same block already recorded `CHIP_FX = 1.1075` and
   //--- `ORB_FY = 1.613` on 2026-10-05. Every one of those is this read.
   //--- The writer has always refused this (`HomeChartSizeRaw`: «a writer that cannot
   //--- measure the box stores nothing»). The reader had no such rule, and THAT
   //--- ASYMMETRY was the ratchet: it could not save a bad place itself, but it could
   //--- manufacture one for the writer to save.
   //--- Refusing is also what makes the reader self-correcting: an absent answer
   //--- leaves the home as it was, and the first pass that CAN measure the box
   //--- derives the right pair — `CircHomesRefresh` runs again on every box change.
   int cw = 0, ch = 0;
   if(!HomeChartSizeRaw(cw, ch)) { x = -1; y = -1; return false; }
   //--- P-UI-158: nothing about this read is remembered. What it produces is a
   //--- DERIVATION, and the store refuses to accept one — only a claim may write — so
   //--- there is no second piece of state that has to stay in step with the writer.
   //--- P-UI-165: the value may come from the shared pre-165 key — still a pure
   //--- DERIVATION (the snapshot write lives in `GVHomeLoadFrac`), so the "nothing
   //--- about this read is remembered" law above is untouched.
   const double fx = HomeFracClamp(GVHomeFracGet(id,false));
   const double fy = HomeFracClamp(GVHomeFracGet(id,true));
   x = (int)MathRound(fx * cw);
   y = (int)MathRound(fy * ch);
   return true;
}
//--- P-UI-158 — THE RAW DOOR, and the only place a fraction is ever written. Two rules,
//--- both about the DENOMINATOR, and neither about who is calling:
//---   * no measured box, no write — a fraction divided by a window that is not the one
//---     the pixels came from is the poisoned store, and at teardown the terminal can
//---     report 0 for a window it is destroying (`HomeChartSizeRaw`);
//---   * a pair outside the box is not a place — it is two numbers measured against
//---     different windows — so the last good home is the better answer. The clamp below
//---     used to saturate such a pair into the store, which is how `STRIP_FX` became a
//---     permanent 1.0: the place the user chose was replaced by "as far right as
//---     possible" and every later read re-derived THAT (P-UI-156).
void GVHomeWriteFrac(const string id, const int x, const int y)
{
   if(x < 0 || y < 0) return;
   int rcw = 0, rch = 0;
   if(!HomeChartSizeRaw(rcw, rch)) return;   // unknown denominator: store nothing,
                                            // and keep the pixel keys (no data loss)
   if(x > rcw || y > rch) return;
   GlobalVariableSet(GVHomeFracName(id,false), HomeFracClamp(HomeFracOf(x, rcw)));
   GlobalVariableSet(GVHomeFracName(id,true), HomeFracClamp(HomeFracOf(y, rch)));
   //--- the pixel keys are dead on arrival: a reader that adopts a window-sized
   //--- number as a place is the bug this block exists to end. P-UI-165: only the
   //--- pair's OWN dead keys are swept — the shared pair is another pair's place.
   GlobalVariableDel(GVHomeName(id,false)); GlobalVariableDel(GVHomeName(id,true));
}
//--- P-UI-158 — THE AUTOMATIC DOOR, the one `SaveUIStates` uses. It writes ONLY when a
//--- new answer is waiting, and the claim is consumed by the write — so the derivation
//--- `SaveUIStates` performs on every attach and teardown can never reach the store.
//--- That is the whole fix: before this, `SaveUIStates` re-derived all three homes and
//--- wrote them, so a derivation made in one window and saved in another REWROTE the
//--- fraction (CHIP_FX 0.942731 -> 0.618392, the 589 px jump). The ring never had this
//--- shape — it stores no place of its own — and this makes the three surfaces match it.
void GVHomeSaveFrac(const string id, const int x, const int y)
{
   if(!GVHomeAnswerTake(id)) return;
   GVHomeWriteFrac(id, x, y);
}
//--- and the HAND's door: a release, the strip's first measured placement, a legacy
//--- migration. Same write, but it makes its own claim and spends it, so a caller that
//--- IS the answer never has to remember a second call or a second flag.
void GVHomeSaveFracHand(const string id, const int x, const int y)
{
   GVHomeAnswerNew(id);
   GVHomeWriteFrac(id, x, y);
   GVHomeAnswerTake(id);
}
bool GVHomeLoadFrac(const string id, const string legacyInfix, int &x, int &y)
{
   if(GVHomeFracRead(id, x, y))
   {
      //--- P-UI-165: a place derived from the SHARED pre-165 key is snapshotted into
      //--- the pair's own key once, here in the measured reading window (the write
      //--- itself refuses an unmeasured box). The shared key is never touched — it
      //--- belongs to every pair that has not migrated yet.
      if(!GVHomeFracKnownOwn(id)) GVHomeSaveFracHand(id, x, y);
      return true;
   }
   int px = 0, py = 0;
   if(!GVHomeLoad(id, legacyInfix, px, py)) { x = -1; y = -1; return false; }
   //--- P-UI-157: a migration is a WRITE, so it refuses to run at all without a
   //--- measured box. Migrating in the fallback window would store a fraction of
   //--- 1920x1080, which is the very creep this block ends.
   int cw = 0, ch = 0;
   if(!HomeChartSizeRaw(cw, ch))      // P-UI-157: no window, no migration
   { x = -1; y = -1; return false; }
   GVHomeSaveFracHand(id, px, py);      // migration, once, in the reading window
   x = px; y = py;
   return true;
}
//+------------------------------------------------------------------+
//| P-UI-157/158 — A HOME THE WINDOW IS TOO YOUNG TO RESOLVE IS STILL |
//| A PLACE.                                                          |
//|                                                                   |
//| `GVHomeFracRead` refuses to derive pixels without a measured box  |
//| (P-UI-156), and at `OnInit` the terminal routinely reports 0 — so  |
//| a stored fraction came back as «no home» and the surface was       |
//| seeded at a DEFAULT: the orb and the chip at the chart's CENTRE,   |
//| the strip by a fresh measurement. The first 250 ms pass then       |
//| corrected it, which is the visible JUMP the report describes, and  |
//| whether it happened at all depended on which timer tick first saw  |
//| a real box.                                                        |
//|                                                                   |
//| Seeding from the fraction itself — against the fallback window,    |
//| i.e. the same place said relatively — lands the FIRST paint in     |
//| the right spot and leaves the refresh nothing but a refinement.    |
//|                                                                   |
//| It is a SEED and never a home. Nothing writes it: the automatic    |
//| door refuses without a claim (P-UI-158), and the callers below     |
//| deliberately do not call the home setters with it. So a pair       |
//| measured in the fallback window can never reach the store.         |
//+------------------------------------------------------------------+
bool GVHomeFracSeed(const string id, int &x, int &y)
{
   if(!GVHomeFracKnown(id)) return false;
   int scw = 0, sch = 0; HomeChartSize(scw, sch);
   x = (int)MathRound(HomeFracClamp(GVHomeFracGet(id,false)) * scw);
   y = (int)MathRound(HomeFracClamp(GVHomeFracGet(id,true)) * sch);
   return true;
}

//+------------------------------------------------------------------+
//| P-UI-144 (2026-10-13) — THE GHOST SWEEP.                          |
//|                                                                  |
//| Report: «پنل‌ها، لوگو و منوها بعد از ری‌استارت ترمینال یا بستن و   |
//| باز کردن پنجره از جاش تکون میخوره، روی هم میافته» — measured on   |
//| the live terminal (AMarkets, data folder A1660DA4…):             |
//|   profiles/default/chart03.chr (DXY H4, written 2026-10-12        |
//|   15:58:11) holds                                                 |
//|     object_name=BiotakMenuV2_134342075006101685_CircOrbBg        |
//|     x_distance=70 y_distance=79 zorder=1200 selectable=0          |
//| while THIS session's EURUSD chart runs under chart id            |
//| 134362571361933137 (biotak_diag_EURUSD_134362571361933137.txt,    |
//| written 09:24 the same morning).                                 |
//|                                                                  |
//| Every object this family paints carries `BiotakMenuV2_<ChartID>` |
//| (BiotakMenu_A.mqh:867), and a chart id is per SESSION: the       |
//| terminal hands a new one out at every restart and at every       |
//| chart reopen. MT4 saves chart objects into the chart's profile   |
//| and restores them at their ABSOLUTE pixels, so the previous      |
//| session's names come back under a prefix this session can never  |
//| address — the teardown (`DeleteMenu`, the `Pnl`/`Pal_`/`Sub`     |
//| purges, `DeleteLegacyMenuObjects`) only knows the LIVE prefix.   |
//| The restored object is therefore a permanent ghost:              |
//|   * it stands at a stale absolute place, which is a different    |
//|     RELATIVE place on every window of another size — the         |
//|     «از جاش تکون میخوره» the user reports;                       |
//|   * the fresh family is painted at its home fraction BESIDE it —  |
//|     «روی هم افتاده», and a selectable ghost answers clicks the    |
//|     live surface should have had;                                 |
//|   * the next close saves it into the profile again, so the       |
//|     ghost re-enters the next session forever.                     |
//|                                                                  |
//| The strip family (`PnlDrawS_*`) never carried a chart id and is   |
//| therefore immune, and it got exactly this sweep at attach        |
//| (`DrawStripSweepStale`, DrawStrip_GearA.mqh:1165, wired from the |
//| entry's OnInit). This is that owner for the menu/panel families. |
//|                                                                  |
//| ONE prefix walk per init, both spellings the family ever painted  |
//| (V1 `BiotakMenu_<id>_`, retired, and V2 `BiotakMenuV2_<id>_`).   |
//| It is exact at attach: the paired teardown deleted THIS family   |
//| before OnInit ran (or it never existed), so the walk can only    |
//| remove foreign spellings. Two units on one chart are refused      |
//| (P-ARCH-03, before `InitializeUIStates` runs), so a live         |
//| sibling's objects are never the ones swept.                      |
//+------------------------------------------------------------------+
void BiotakMenuGhostSweep()
{
   ObjectsDeleteAll(0, "BiotakMenu_",   -1, -1);   // V1 + every older V2 spelling
   ObjectsDeleteAll(0, "BiotakMenuV2_", -1, -1);   // V2 (the char after "BiotakMenu" is 'V')
}

#endif // BIOTAK_HOMES_MQH
