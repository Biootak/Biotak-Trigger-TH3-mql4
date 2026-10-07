// BaseKnot_Measure.mqh - BaseKnotTool split 2026-09-29: exact lines 1334-2762 of BaseKnotTool.mqh, byte-identical, zero renames.
#ifndef BASE_KNOT_MEASURE_MQH
#define BASE_KNOT_MEASURE_MQH


//+------------------------------------------------------------------+
//| Direction — decided at commit, then FOLLOWS the live price (see   |
//| the resolver below + BaseKnotRefreshDirection). Positional rule:  |
//| price above the box = Buy, below = Sell. Price INSIDE resolves by |
//| entry side (most recent close outside: from below → Buy, from      |
//| above → Sell); mid-vs-price is the last fallback. Boxes fully     |
//| outside keep following afterwards — the box itself is the          |
//| hysteresis band, so in-box vibration never flickers the lines.    |
//+------------------------------------------------------------------+
int BaseKnotResolveDirection(const double top, const double bot)
{
   double ref = iClose(_Symbol, 0, 0);
   if(ref <= 0) ref = g_currentPrice;
   if(ref > top) return 1;
   if(ref > 0 && ref < bot) return -1;
   if(ref > 0)   // inside the box (or exactly on an edge): entry side decides
   {
      for(int s = 1; s <= BK_DIR_LOOKBACK; s++)
      {
         double c = iClose(_Symbol, 0, s);
         if(c <= 0) continue;
         if(c < bot) return 1;    // rose into the box from below → demand → Buy
         if(c > top) return -1;   // fell into the box from above → supply → Sell
      }
      double mid = (top + bot) / 2.0;
      return (mid <= ref ? 1 : -1);
   }
   return 1;   // no live price at all — harmless default
}

//+------------------------------------------------------------------+
//| Live reference price — forming-bar close first (the freshest      |
//| chart price), g_currentPrice fallback (EventHandlers refreshes it |
//| per tick; the 500 ms pump also runs on the timer path with zero   |
//| ticks). <= 0 = no usable data — the caller must keep, never flip. |
//+------------------------------------------------------------------+
double BaseKnotLiveRef()
{
   double ref = iClose(_Symbol, 0, 0);
   if(ref <= 0) ref = g_currentPrice;
   return ref;
}

//+------------------------------------------------------------------+
//| Auto-follow (P-BK-13): the box itself is the hysteresis band —    |
//| fully outside takes that side, inside (or on an edge) keeps the   |
//| current one. No extra buffer to tune, no new inputs.              |
//+------------------------------------------------------------------+
int BaseKnotFollowDirection(const double top, const double bot, const int curDir, const double ref)
{
   if(ref <= 0) return curDir;   // weekend / data gap — never flip blind
   if(ref > top) return 1;       // box fully below the price = demand = Buy
   if(ref < bot) return -1;      // box fully above it = supply = Sell
   return curDir;                // inside — keep, so vibration can't flicker
}
// Refresh one box's dir from the live price. Returns true on a real flip
// (dir + chart-scoped GV persisted; the caller Syncs to rebuild the
// Entry/SL/TP lines, tooltips and INFO). Lite-safe: Object* + GV only.
bool BaseKnotRefreshDirection(const string id, const double ref)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return false;
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(p1 <= 0 || p2 <= 0) return false;
   // P-BK-46: A KNOT WHOSE BREAK'S STORY NAMES A SIDE IS NOT THE PRICE'S TO FLIP. The
   // story's answer (BaseKnotNodeDir) is published by Sync, so the live-price follow
   // below speaks only for a base with no break measured yet (P-BK-13's own case).
   // P-BK-47: the TYPE no longer answers this question — it is the node's LENGTH, and a
   // length is not a side. Keeping the retired `nodeKind` gate here (BKNODEDIR-OFF) would
   // freeze every box the moment it was classed.
   if(g_bkBoxes[k].nodeSide != 0) return false;
   int want = BaseKnotFollowDirection(MathMax(p1, p2), MathMin(p1, p2), g_bkBoxes[k].dir, ref);
   if(want == g_bkBoxes[k].dir) return false;
   g_bkBoxes[k].dir = want;
   GlobalVariableSet(BaseKnotGV(id), (double)want);
   GlobalVariableSet(BaseKnotGVTwin(id), (double)want);   // P-UI-142: restart layer
   return true;
}

//+------------------------------------------------------------------+
//| Registry helpers                                                  |
//+------------------------------------------------------------------+
int BaseKnotFind(const string id)
{
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
      if(g_bkBoxes[i].id == id) return i;
   return -1;
}
//--- BKDOT-OFF/BKGRIP-OFF/BKPOINT-OFF (P-BK-71) — THE RETIRED POINT TAILS: ONE table,
//--- TWO readers (the once-per-attach sweep in BaseKnotLazyInit and the deselect wipe in
//--- BaseKnotSelectionMarkersWipe). Every selectable square this module EVER drew is named
//--- here, so a chart any older build wrote cannot keep one: mid-edge chips (BKMIDGRIP-OFF),
//--- corner chips (BKGRIP2/BKGRIP-OFF), trendline ends (P-BK-68: G1/G2), the centre cover
//--- (P-BK-59/BKDOT-OFF: DOT) and the trendline points (P-BK-69/BKPOINT-OFF: P1/P2).
//--- Lives HERE (above the first reader) because MQL4 needs the define before use.
#define BK_RETIRED_POINTS 13
string BaseKnotRetiredPointName(const int i)
{
   string tails[BK_RETIRED_POINTS] = {"GT", "GB", "GL", "GR", "GTL", "GTR", "GBL", "GBR",
                                      "G1", "G2", "DOT", "P1", "P2"};
   if(i < 0 || i >= BK_RETIRED_POINTS) return "";
   return tails[i];
}
void BaseKnotRegister(const string id, const int dir, const int tfMin)
{
   if(BaseKnotFind(id) >= 0) return;
   int n = ArraySize(g_bkBoxes);
   ArrayResize(g_bkBoxes, n + 1);
   g_bkBoxes[n].id    = id;
   g_bkBoxes[n].dir   = (dir < 0 ? -1 : 1);
   g_bkBoxes[n].tfMin = tfMin;
   g_bkBoxes[n].commitMs = GetTickCount();   // fresh commit → Auto INFO grace starts now
   g_bkBoxes[n].locked = false;              // fresh boxes are always unlocked
   g_bkBoxes[n].nodeKind = BK_NODE_NONE;     // P-BK-29/47: no type published yet
   g_bkBoxes[n].nodeSide = 0;                // P-BK-46/47: no break's side published yet
   g_bkBoxes[n].baseTFMin = 0;               // P-BK-36/49: no class published yet
   g_bkBoxes[n].biasState = BK_STATE_UNKNOWN;   // P-BK-48/49: no life state measured yet
   g_bkBoxes[n].storyT = 0;                  // P-BK-41/49: no story candle published yet
   g_bkBoxes[n].exitT  = 0;                  // P-BK-81: no exit candle published yet
   GlobalVariableSet(BaseKnotGV(id), (double)g_bkBoxes[n].dir);
   GlobalVariableSet(BaseKnotGVTwin(id), (double)g_bkBoxes[n].dir);   // P-UI-142: restart layer
}
void BaseKnotUnregister(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   for(int i = k; i < ArraySize(g_bkBoxes) - 1; i++) g_bkBoxes[i] = g_bkBoxes[i + 1];
   ArrayResize(g_bkBoxes, ArraySize(g_bkBoxes) - 1);
   GlobalVariableDel(BaseKnotGV(id));
   GlobalVariableDel(BaseKnotGVTwin(id));   // P-UI-142: the twin dies with the box too
}
// Lock — a locked box is unselectable so it can never be dragged (hold still
// opens the mini strip, so it can always be unlocked). The flag rides the BOX
// handle's own SELECTABLE bit: no GV, survives TF-switches and restarts.
bool BaseKnotLocked(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   return g_bkBoxes[k].locked;
}
void BaseKnotSetLocked(const string id, const bool on)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   g_bkBoxes[k].locked = on;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, !on);
   BaseKnotSync(id);   // rebuild the live tooltip (coords · TF-scope · text · lock)
   ChartRedraw();
}
// Rebuild the registry from chart objects once (TF-switch safe: the box
// anchors ARE the spec, direction rides a chart-scoped GV, TF rides the id).
// Also purges the transient PREVIEW/HINT of a dead session (state resets on
// reload, so a reloaded indicator must never inherit a ghost rubber-band)
// and sweeps orphan direction-GVs of this chart whose boxes are gone.
void BaseKnotLazyInit()
{
   if(g_bkInitDone) return;
   g_bkInitDone = true;
   if(StringLen(inpObjectPrefix) == 0) return;
   string tag = inpObjectPrefix + BK_TAG;
   BaseKnotWipePreview();
   BaseKnotWipeLive();   // dead-session transients — never inherited
   ObjectDelete(0, BaseKnotHintName());
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, tag) != 0) continue;
      if(StringFind(nm, "BOX", StringLen(nm) - 3) < 0) continue;
       string id = StringSubstr(nm, StringLen(tag), StringLen(nm) - StringLen(tag) - 4);
       int dir = 1;
       if(GlobalVariableCheck(BaseKnotGV(id)))
          dir = ((int)GlobalVariableGet(BaseKnotGV(id)) < 0 ? -1 : 1);
       else if(GlobalVariableCheck(BaseKnotGVTwin(id)))   // P-UI-142: restart layer (chart ids are per-session)
          dir = ((int)GlobalVariableGet(BaseKnotGVTwin(id)) < 0 ? -1 : 1);
       else
       {
          // No frozen value (pre-GV box or a wiped GV): resolve positionally
          // exactly like a fresh commit instead of blindly defaulting to Buy —
          // Register persists it, so the rebuild is stable from here on.
          double iA = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
          double iB = ObjectGetDouble(0, nm, OBJPROP_PRICE, 1);
          dir = BaseKnotResolveDirection(MathMax(iA, iB), MathMin(iA, iB));
       }
       BaseKnotRegister(id, dir, BaseKnotIdTF(id));
      int q = BaseKnotFind(id);
      if(q >= 0)
      {
         g_bkBoxes[q].commitMs = 0;   // inherited box — long ago, no Auto grace flash
         g_bkBoxes[q].locked = (ObjectGetInteger(0, nm, OBJPROP_SELECTABLE) == 0);   // lock rides the handle itself — no GV, survives TF-switch/restart
      }
   }
   // P-BK-71 MIGRATION — A TRENDLINE CARRIER BECOMES THE BOX, ONCE PER ATTACH.
   // A chart saved by a P-BK-67/68/69 build carries the OBJ_TREND carrier; the carrier IS
   // the box again, so it is re-created as a RECTANGLE from its own two anchors (the
   // very same time/price, so no knot moves a pixel) and the trendline era's point
   // tails are swept — nothing re-creates them any more (BKPOINT-OFF), so without this
   // pass a saved chart would keep squares that no drag, no restyle and no Sync of the
   // new build would ever touch again. Name lookups + Object* only, and the re-sync
   // loop right below repaints the migrated family in the same attach.
   for(int mg = 0; mg < ArraySize(g_bkBoxes); mg++)
   {
      string mgPfx = BaseKnotPrefix(g_bkBoxes[mg].id);
      if(mgPfx == "") continue;
      string mgBox = BaseKnotBoxName(mgPfx);
      if(ObjectFind(0, mgBox) >= 0 &&
         (ENUM_OBJECT)ObjectGetInteger(0, mgBox, OBJPROP_TYPE) != OBJ_RECTANGLE)
      {
         datetime mgT1 = (datetime)ObjectGetInteger(0, mgBox, OBJPROP_TIME, 0);
         datetime mgT2 = (datetime)ObjectGetInteger(0, mgBox, OBJPROP_TIME, 1);
         double   mgP1 = ObjectGetDouble(0, mgBox, OBJPROP_PRICE, 0);
         double   mgP2 = ObjectGetDouble(0, mgBox, OBJPROP_PRICE, 1);
         bool     mgSel = (bool)ObjectGetInteger(0, mgBox, OBJPROP_SELECTED);
         ObjectDelete(0, mgBox);
         if(mgT1 > 0 && mgT2 > 0 && mgP1 > 0 && mgP2 > 0 &&
            ObjectCreate(0, mgBox, OBJ_RECTANGLE, 0, mgT1, mgP1, mgT2, mgP2))
         {
            BaseKnotStyleBox(mgBox);
            ObjectSetInteger(0, mgBox, OBJPROP_SELECTABLE, !g_bkBoxes[mg].locked);
            ObjectSetInteger(0, mgBox, OBJPROP_SELECTED, mgSel);
         }
      }
      for(int m = 0; m < BK_RETIRED_POINTS; m++)
      {
         string mtail = BaseKnotRetiredPointName(m);
         if(mtail == "") continue;
         string robj = mgPfx + mtail;
         if(ObjectFind(0, robj) >= 0) ObjectDelete(0, robj);
      }
   }
   // BKMIDGRIP-OFF (2026-09-16) — RETIRED-PAIR SWEEP, ONCE PER ATTACH.
   // Superseded by the table walk above (P-BK-71): the four mid-edge chips are four
   // of the table's thirteen tails now, swept for every box on the same pass.
   // BKMIDGRIP-OFF: for(int b = 0; b < ArraySize(g_bkBoxes); b++)
   // BKMIDGRIP-OFF: {
   // BKMIDGRIP-OFF:    string midPfx = BaseKnotPrefix(g_bkBoxes[b].id);
   // BKMIDGRIP-OFF:    if(midPfx == "") continue;
   // BKMIDGRIP-OFF:    string midNames[4] = {"GT", "GB", "GL", "GR"};
   // BKMIDGRIP-OFF:    for(int m = 0; m < 4; m++)
   // BKMIDGRIP-OFF:    {
   // BKMIDGRIP-OFF:       string mid = midPfx + midNames[m];
   // BKMIDGRIP-OFF:       if(ObjectFind(0, mid) >= 0) ObjectDelete(0, mid);
   // BKMIDGRIP-OFF:    }
   // BKMIDGRIP-OFF: }
   // P-BK-06 migration: hollow-by-construction (bg handle + edge segments) —
   // every inherited box is re-synced once so pre-edge boxes gain their
   // border edges and lose their visible fill immediately, no drag needed.
   for(int b = 0; b < ArraySize(g_bkBoxes); b++) BaseKnotSync(g_bkBoxes[b].id);
   // Orphan-GV sweep (this chart only — the GV carries the chart id suffix).
   string cid = GetCachedChartIdStr();
   for(int k = GlobalVariablesTotal() - 1; k >= 0; k--)
   {
      string gv = GlobalVariableName(k);
      if(StringFind(gv, "Biotak_BK_") != 0) continue;
      if(StringFind(gv, "_" + cid, StringLen(gv) - StringLen(cid) - 1) < 0) continue;
      string oid = StringSubstr(gv, 10, StringLen(gv) - 10 - StringLen(cid) - 1);
      if(BaseKnotFind(oid) < 0) GlobalVariableDel(gv);
   }
}

//+------------------------------------------------------------------+
//| Hint bar (bottom-left): guidance while sizing, auto-hiding result.|
//| Amber on dark charts is unreadable on light ones — pick the text   |
//| color from the chart background luminance. Result hints ("BASE #N  |
//| set") expire after 4 s so the corner never nags; guidance hints   |
//| stay until the session ends.                                       |
//+------------------------------------------------------------------+
static uint g_bkHintExpireMs = 0;   // 0 = persistent; else GetTickCount deadline
// Readable foreground for chart-anchored texts (hint + INFO label) — brand
// amber on dark charts, deep amber on light ones. P-UI-117: the gate AND both
// inks are the palette owner's now (`BioChartBgIsLight`, `BIO_CLR_BRAND`,
// `BIO_CLR_ON_LIGHT`) — this function is the decision, not a second copy of the
// rule (it used to carry its own luminance arithmetic and its own literals,
// beside RuntimeSettings' identical copy).
color BaseKnotFgForBg()
{
   return (BioChartBgIsLight() ? BIO_CLR_ON_LIGHT : BIO_CLR_BRAND);
}
void BaseKnotHintShow(const string text, const int ttlMs = 0)
{
   string hn = BaseKnotHintName();
   if(hn == "") return;
   if(ObjectFind(0, hn) < 0) ObjectCreate(0, hn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hn, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, hn, OBJPROP_YDISTANCE, 44);
   ObjectSetString(0, hn, OBJPROP_TEXT, text);
   ObjectSetString(0, hn, OBJPROP_FONT, BioChromeFont(false));
   ObjectSetInteger(0, hn, OBJPROP_FONTSIZE, PnlPt(BK_PT_HINT));
   ObjectSetInteger(0, hn, OBJPROP_COLOR, BaseKnotFgForBg());
   ObjectSetInteger(0, hn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_BACK, false);
   ObjectSetInteger(0, hn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, hn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_BOX_HINT);   // P-UI-31: under the settings card
   g_bkHintExpireMs = (ttlMs > 0 ? GetTickCount() + (uint)ttlMs : 0);
   ChartRedraw();
}
void BaseKnotHintHide()
{
   ObjectDelete(0, BaseKnotHintName());
   g_bkHintExpireMs = 0;
   ChartRedraw();
}
// Per-tick expiry pump (called from RefreshUIPerTick's 500 ms block).
void BaseKnotHintTick()
{
   if(g_bkHintExpireMs == 0) return;
   if((int)(GetTickCount() - g_bkHintExpireMs) >= 0) BaseKnotHintHide();
}

//+------------------------------------------------------------------+
//| Chart lock — MT4-like: while a gesture is active (drawing a new   |
//| box OR dragging a committed one) the view must not slide under    |
//| the hand. MOUSE_SCROLL blocks drag-panning, AUTOSCROLL suspend    |
//| stops live ticks from shifting the chart mid-gesture (restoring   |
//| it only re-arms the snap-to-live the ticks would have done        |
//| anyway). First locker saves, nested locks only re-assert, one     |
//| Unlock restores — so session and drag locks can never corrupt     |
//| each other's saved values. ctxToo=false for IDLE drags (the chart |
//| context menu stays available there, unlike in a draw session).    |
//+------------------------------------------------------------------+
void BaseKnotLockChart(const bool ctxToo)
{
   if(!s_bkChartLocked)
   {
      g_bkAutoWas = (ChartGetInteger(0, CHART_AUTOSCROLL) != 0);
      s_bkChartLocked = true;
      ChartViewLockAcquire();   // P-UI-90: scroll + context menu have ONE owner
   }
   if(g_bkAutoWas && (ChartGetInteger(0, CHART_AUTOSCROLL) != 0))
      ChartSetInteger(0, CHART_AUTOSCROLL, false);
   if(ctxToo && (bool)ChartGetInteger(0, CHART_CONTEXT_MENU))
      ChartSetInteger(0, CHART_CONTEXT_MENU, false);
   g_bkTouched = true;   // OnDeinit must restore, whatever happens
}
void BaseKnotUnlockChart()
{
   if(!s_bkChartLocked) return;
   ChartViewLockRelease();   // P-UI-90: hands the view back only when NO owner is left
   if(g_bkAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, true);
   s_bkChartLocked = false;
}
// Re-assert an OWNED lock (P-BK-14): a one-time lock is not enough — third
// writers (menu modal unlock when a strip/card closes mid-gesture, the panel
// watchdog restore, template/terminal resets) can flip the props back while
// the button is still down, and the chart then pans under the hand for the
// rest of the gesture. While we own it, every throttled step re-forces the
// props. Read-guarded: steady state costs only the reads, writes happen
// solely on drift. ctxToo mirrors the original locker (session=true, drag=false).
void BaseKnotReassertLock(const bool ctxToo)
{
   if(!s_bkChartLocked) return;
   ChartViewLockAssert();   // P-UI-90: read-guarded, one owner for scroll + ctx
   if(g_bkAutoWas && ChartGetInteger(0, CHART_AUTOSCROLL) != 0)
   { ChartSetInteger(0, CHART_AUTOSCROLL, false); g_bkTouched = true; }
   if(ctxToo && ChartGetInteger(0, CHART_CONTEXT_MENU) != 0)
   { ChartSetInteger(0, CHART_CONTEXT_MENU, false); g_bkTouched = true; }
}
// IDLE box-drag holder: lock once a REAL drag starts (past slop — taps never
// flicker the props), release on button-up. The state check keeps a drag
// release from unlocking a draw session's lock in the pathological overlap.
// P-BK-62 (2026-09-16): AN OWNED DRAG LOCK IS RE-ASSERTED ON EVERY STEP — the
// P-BK-14 rule, extended from the draw session to the drag/resize the session is
// NOT running. The one-time lock is not enough for exactly the reasons P-BK-14
// recorded (a panel release, a modal card, a template reset can flip the props
// back while the button is still down), and here it was worse than a leak: the
// guard below early-returns once `s_bkDragLock` is set, so a single third-writer
// flip left the chart panning under the hand for the REST of the gesture with
// nothing left to take the lock back. Read-guarded through `ChartViewLockAssert`
// (the props' ONE owner): steady state is two property reads per throttled step,
// a write only on drift.
void BaseKnotDragLockOn()
{
   if(s_bkDragLock)
   {
      BaseKnotReassertLock(false);   // P-BK-62: owned — re-force, never re-capture
      return;
   }
   if(g_bkState != BK_IDLE) return;   // taps/sessions never take the drag lock
   BaseKnotLockChart(false);
   s_bkDragLock = true;
}
// P-BK-65: THE GESTURE STATE HAS ONE OWNER, and teardown is one of its four callers
// (the others are the release, the watchdog and the terminal-named box drag). Called
// from OnDeinit (every reason) and from BaseKnotCancel: a removed or cancelled instance
// must not hand a stale "this press is a resize" answer to the next attach. No chart
// write, no probe — three stores.
void BaseKnotGestureClear()
{
   s_bkGripGesture = 0;
   s_bkGripLive    = 0;
   s_bkBoxNamed    = false;
   s_bkDragMoved   = false;
}
void BaseKnotDragLockOff()
{
   if(!s_bkDragLock || g_bkState != BK_IDLE) return;
   s_bkDragLock = false;
   BaseKnotUnlockChart();
}

//+------------------------------------------------------------------+
//| Arm / cancel — called from the Tools-ring click (menu side hides  |
//| the ring first). Raw Chart* scroll lock: no menu dependency, so   |
//| Lite compiles and keeps working on committed boxes.               |
//+------------------------------------------------------------------+
void BaseKnotArm()
{
   BaseKnotLazyInit();
   GestureTakeRelease();   // P-UI-144: a NEW box is never gated by the last one — the
                           // arbiter's ONE question is per drawing, so arming clears it
   g_bkState   = BK_ARMED;
   g_bkArmedMs = GetTickCount();
   g_bkLeftPrev = true;   // the arming press is still down — never take its release as click 1
   g_bkHeld = false;
   g_bkLiveT = 0; g_bkLiveP = 0.0;
   BaseKnotLockChart(true);   // no chart slide under the hand while drawing
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   // No bottom hint while armed either (user: nothing is written at the
   // bottom — guidance lives in the ring tooltip, errors stay silent).
   // BaseKnotHintShow("BASE TOOL — press + drag (release = done) · or click 2 corners · right-click / ESC: cancel");
   ChartRedraw();
}
void BaseKnotCancel()
{
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   BaseKnotHintHide();
   g_bkState = BK_IDLE;
   g_bkHeld = false;
   BaseKnotGestureClear();   // P-BK-65: a cancelled session leaves no gesture answer behind
   BaseKnotUnlockChart();
   g_bkRestoreReq = true;   // UI side re-shows the hidden ring menu
   ChartRedraw();
}

// Deinit safety (call from OnDeinitHandler, every reason): a remove /
// TF-switch / crash-reload mid-session must never leave the chart scroll
// locked, a ghost rubber-band behind, or a stale restore flag. Committed
// boxes are the independent layer and stay untouched here (REMOVE wipes
// them via DeleteAllIndicatorObjects(true) + the Biotak_BK_* GV sweep).
void BaseKnotOnDeinit(const int reason)
{
   BaseKnotUnlockChart();   // every reason — a stuck lock must never survive a switch/remove
   g_bkTouched = false;
   s_bkDragLock = false;
   s_bkDragId = ""; s_bkDragMoved = false;
   BaseKnotGestureClear();   // P-BK-65: no gesture state outlives the instance either
   g_bkState = BK_IDLE;
   g_bkRestoreReq = false;
   g_bkHeld = false;
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   ObjectDelete(0, BaseKnotHintName());
   BaseKnotCornerWipe();   // P-BK-58: the family's row is the chart's, not a box child — a remove /
                           // TF switch must never leave a ghost note behind (nor a "nothing changed"
                           // marker that would keep the next init from rebuilding it)
   if(reason == REASON_REMOVE) ArrayResize(g_bkBoxes, 0);
}

//+------------------------------------------------------------------+
//| Border edges — the VISIBLE box outline (finite segments, never a |
//| ray). Ensure-create + move + style in one call, so drag-sync,     |
//| restyle-all and child-delete-heal all rebuild missing edges.      |
//+------------------------------------------------------------------+
void BaseKnotMakeEdge(const string name, const datetime t1, const double p1,
                      const datetime t2, const double p2,
                      const color clr, const int style, const int width,
                      const string tooltip, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // the BOX rect is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);   // the visible border always reads (like TH lines + MT4 tools)
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_EDGE);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
// Draw/refresh the 4 outline edges under one tag (committed pfx or preview
// tag) — the hollow look on builds that ignore FILL (P-BK-06).
// BKEDGE-OFF (P-BK-74) — DORMANT, DEAD BY CONSTRUCTION: the border is the box'
// OWN outline now (BaseKnotStyleBox wears the border ink), so no call site draws
// this family any more. The body stays compiled and whole so a restore is ONE
// uncomment — the `BaseKnotDrawEdges(pfx, ...)` call in BaseKnotSync.
void BaseKnotDrawEdges(const string tag, datetime t1, const double p1,
                       datetime t2, const double p2,
                       const color clr, const int style, const int width,
                       const string tooltip, const long tfMask)
{
   if(tag == "") return;
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   BaseKnotMakeEdge(tag + BK_EDGE_T, t1, top, t2, top, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_B, t1, bot, t2, bot, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_L, t1, bot, t1, top, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_R, t2, bot, t2, top, clr, style, width, tooltip, tfMask);
}
//+------------------------------------------------------------------+
//| P-BK-74 (2026-09-17) — THE PREVIEW IS ONE RECTANGLE AGAIN.         |
//|                                                                   |
//| The sizing rubber band used to be four OBJ_TREND edges too (the    |
//| "legacy single-rect preview" the two call sites kept deleting).    |
//| With the edges retired it goes back to the family it belongs to:   |
//| ONE OBJ_RECTANGLE, hollow, foreground, wearing the final look —    |
//| the same object the commit will hand over, so what the user sizes  |
//| is literally what he gets. Ensure-create + move + style in one     |
//| call, so a TF switch or a deleted object heals on the next frame.  |
//| It carries NO selection: the terminal marks nothing while sizing,  |
//| and `BaseKnotCommit` is the one place the selection is granted     |
//| (P-BK-73).                                                        |
//+------------------------------------------------------------------+
void BaseKnotDrawPreviewRect(const string tag, const datetime t1, const double p1,
                             const datetime t2, const double p2,
                             const color clr, const int style, const int width,
                             const string tooltip, const long tfMask)
{
   if(tag == "") return;
   if(ObjectFind(0, tag) < 0) ObjectCreate(0, tag, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectMove(0, tag, 0, t1, p1);
   ObjectMove(0, tag, 1, t2, p2);
   ObjectSetInteger(0, tag, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, tag, OBJPROP_STYLE, style);
   ObjectSetInteger(0, tag, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, tag, OBJPROP_FILL, false);        // hollow — the user's own default
   ObjectSetInteger(0, tag, OBJPROP_BACK, false);        // foreground
   ObjectSetInteger(0, tag, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetInteger(0, tag, OBJPROP_SELECTABLE, false);  // nothing is selected until the commit
   ObjectSetInteger(0, tag, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, tag, OBJPROP_ZORDER, Z_BOX_EDGE);
   ObjectSetString(0, tag, OBJPROP_TOOLTIP, tooltip);
}
//+------------------------------------------------------------------+
//| Children geometry — single source of truth for commit / drag-sync.|
//| P-BK-51 (2026-09-15) — BOTH LEGS SIT INSIDE THE KNOT, and the      |
//| PENETRATION the entry waits for is named by the node's own TYPE.   |
//| The user's rule, word for word: «برای گره اف تی ار میشه به اندازه    |
//| engsl محل ورود داخل گره و به اندازه engsl از محل ورود استاپ» +      |
//| «و برای گره etr میشه به اندازه huntsl محل ورود و به اندازه engsl از|
//| محل ورود میشه استاپ لاسش» + «و برای نوع هی بعدی بای از engsl ,     |
//| huntsl یک تایم بالاتر استفاده کرده». So:                            |
//|   * THE EDGE IS THE SIDE'S OWN EDGE — the one the departure left   |
//|     by (BaseKnotNodeDir / P-BK-49; top for a Buy, bottom for a     |
//|     Sell: WHICH side that is is the PATTERN's call, never a type). |
//|   * BOTH LEGS ARE INSIDE, measured from it:                        |
//|       Buy : Entry = top - offset, SL = Entry - EngSL               |
//|       Sell: Entry = bot + offset, SL = Entry + EngSL               |
//|   * THE OFFSET (the penetration the entry waits for) follows the   |
//|     node's TYPE:                                                   |
//|       FTR (and the live preview, which has no type yet) = ONE      |
//|           EngSL («به اندازه engsl ... داخل گره»);                  |
//|       ETR / CTR / OTR = ONE HuntSL («به اندازه huntsl محل ورود»);   |
//|   * THE STOP IS ALWAYS ONE EngSL BEHIND THE ENTRY, whichever of    |
//|     the two sized the entry («به اندازه engsl از محل ورود استاپ»),  |
//|     and it is read on the NODE TYPE'S OWN TIME (P-BK-83 — ETR one   |
//|     rung above the node's own time, CTR two, OTR three) while the   |
//|     ENTRY stays on the node's own («ورودش که درسته») —             |
//|     BaseKnotMeasureTFMin owns that hop and BaseKnotEntryTFMin the   |
//|     entry's own time, and each is the only place its answer exists. |
//| Both numbers are PUSHED IN (EngSL / HuntSL per TF — trade-plan math|
//| sits ABOVE this module, the P-BK-46/50 ask / push pair), and a TF  |
//| the table cannot answer is NO LONGER the box' whole height: the     |
//| node's OWN power caps it (P-BK-52, BaseKnotLegPair) — the ABSENCE  |
//| never a guess. P-BK-50's geometry (entry ONE R OUTSIDE the edge,   |
//| the stop ON that edge) is SUPERSEDED IN PLACE by the two lines     |
//| below — the pair it replaced is kept verbatim under BKGEOM-OFF, one |
//| uncomment away. The TARGETS are the TRADE PLAN's own legs          |
//| (BaseKnotTPLevel — the TP1/TP2/TP3 the label's `#SL/-TP` row       |
//| prints for the same TF), measured from the entry exactly as that   |
//| row measures them; the old `TARGET R`-multiple target stays        |
//| RETIRED IN PLACE (BKTPR-OFF) and the SAME state picks how many of   |
//| the plan's legs are drawn (BaseKnotTPCount).                       |
//+------------------------------------------------------------------+
// P-BK-51 — WHICH TF'S NUMBERS SIZE THE TRADE. The knot's own TF is the class the note
// names (P-BK-46). P-BK-83 (2026-09-17) — AND THE TWO LEGS DO NOT SHARE ONE ANSWER:
//   * THE ENTRY's penetration is read on the NODE'S OWN time (the class the note prints),
//     because that is the reading the user checked and confirmed is right («ورودش که درسته»);
//   * THE STOP is read on the NODE TYPE'S OWN time: the type IS the rung whose ability the
//     node's LENGTH matched (P-BK-75/78), so the time that OWNS the node — the one whose
//     EngSL the risk belongs to — is the node's own time stepped up by the type's own count.
// The user, on the stop only: «استاپ باید از eng sl تایم etr بیاد براساس نوع گره که هستش» +
// «باید از همون تایم etr که تایم بالاتر از تایم گره هستش گرفته بشه و بقیه هم همین طور».
// THE BUG THIS REPLACES: ETR shared FTR's branch, so an ETR node standing on an M1 class wore
// EngSL(M1) — the user's own box read `[BUY · EngSL 0.3 | 2.9 | 5 bars · M1 base · ETR]`, a
// 0.3-pip stop on a 2.9-pip node whose length belongs to M5.
// ONE OWNER EACH, so the geometry, the pump's own TF list (BaseKnotEngNeeds) and every text
// that names a source ask the right one of the two: BaseKnotEntryTFMin for the entry,
// BaseKnotMeasureTFMin (with BaseKnotMeasureHops as its count) for the stop.
int BaseKnotMeasureHops(const int kind)
{
   if(kind == BK_NODE_ETR) return 1;   // the PATTERN time   — one rung above the node's own
   if(kind == BK_NODE_CTR) return 2;   // the STRUCTURE time — two rungs above
   if(kind == BK_NODE_OTR) return 3;   // past the structure — three rungs above
   return 0;                           // FTR (and no type yet): the node's own time
}
int BaseKnotMeasureTFMin(const int kind, const int tfMin)
{
   int hops = BaseKnotMeasureHops(kind);
   if(hops <= 0) return tfMin;   // FTR / no type yet — the node's own time, unchanged
   int r = (tfMin > 0 ? tfMin : Period());
   for(int i = 0; i < hops; i++)
   {
      int up = BaseKnotNextTFMin(r);
      if(up <= 0) break;   // the ladder's top — the highest rung it can reach stands
      r = up;
   }
   return r;
}
// ... and the ENTRY's own time: the NODE'S OWN, whatever its type is (the user's «ورودش که
// درسته» — the entry was already the reading he confirmed). A function rather than a bare
// `tfMin` at the call sites because the two readings must never be confused: a leg measured on
// the other one is a silent mispricing, and this name is what the geometry, the texts and the
// gate all ask. SAFE BY CONSTRUCTION: both legs stay inside the box whatever this answers —
// P-BK-52 caps each at the NODE's own power (off + risk <= 55/64 x H).
int BaseKnotEntryTFMin(const int kind, const int tfMin)
{
   if(kind == BK_NODE_NONE && tfMin <= 0) return Period();   // the sizing preview: this chart's TF
   return (tfMin > 0 ? tfMin : Period());
}
// P-BK-51 — DID THE ENTRY'S PENETRATION COME FROM THE HUNTER LEG? The TYPE asks (ETR and
// the longer CTR/OTR want HuntSL), the TABLE answers: a TF whose HuntSL was never pushed
// falls back to EngSL instead of inventing a size, and every text says so
// (BaseKnotEntryWhy). The FTR node and the box being SIZED are EngSL reads.
// P-BK-79: AND AT ONE ANCHOR. Every reader below takes the bar the row was pushed at
// (`anchor` — the box' own story end, 0 = the live row), because a TF-keyed read could only
// ever answer ONE of two boxes whose bases ended on different bars («با گذشت زمان ممکن 40
// بشه یا 10 بشه»). The default keeps the live callers byte-identical.
bool BaseKnotOffsetIsHunt(const int kind, const int tfMin, const datetime anchor = 0)
{
   if(kind == BK_NODE_FTR || kind == BK_NODE_NONE) return false;
   return (BaseKnotHuntPips(tfMin, anchor) > 0.0);
}
string BaseKnotEntryOffsetTag(const bool isHunt) { return (isHunt ? "HuntSL" : "EngSL"); }
// The penetration itself, in PIPS. 0 = nothing pushed for that (TF, anchor) — an ABSENCE
// the caller turns into the box' own height, exactly like the risk below.
double BaseKnotEntryOffsetPips(const int kind, const int tfMin, const datetime anchor = 0)
{
   if(BaseKnotOffsetIsHunt(kind, tfMin, anchor)) return BaseKnotHuntPips(tfMin, anchor);
   return BaseKnotEngPips(tfMin, anchor);
}
// P-BK-51 — WHY THE ENTRY WAITS THAT DEEP: the node's TYPE names the measure, and the
// number is never shown without the TF it was read on. ONE owner, so the box hover, the
// entry ray and the note's hover can never describe two different measurements.
// P-BK-83: AND THAT TF IS THE NODE'S OWN TIME. The entry's penetration never hops to the
// type's rung — that is the STOP's own time (BaseKnotMeasureTFMin) — so the sentence names
// the class the note already prints, and says so in words: a reader who is told «one TF above
// the base» must be looking at a line that was really drawn one TF above it.
string BaseKnotEntryWhy(const int kind, const int entryTF, const bool isHunt,
                        const double top, const double bot, const datetime anchor = 0)
{
   string what = BaseKnotEntryOffsetTag(isHunt);
   string tf   = BaseKnotTFName(entryTF > 0 ? entryTF : Period());
   string why;
   if(kind == BK_NODE_FTR)      why = "FTR — the node is the TRIGGER length: " + what + " of " + tf;
   else if(kind == BK_NODE_ETR) why = "ETR — the node is the PATTERN length: " + what + " of " + tf;
   else if(kind == BK_NODE_CTR) why = "CTR — the node is the STRUCTURE length: " + what + " of " + tf;
   else if(kind == BK_NODE_OTR) why = "OTR — longer than the structure time: " + what + " of " + tf;
   else                         why = "no type yet (the box is being sized): " + what + " of " + tf;
   if(kind != BK_NODE_NONE) why += ", the node's own time";   // P-BK-83: the entry never hops
     if(!isHunt && kind != BK_NODE_FTR && kind != BK_NODE_NONE
        && BaseKnotHuntPips(entryTF, anchor) <= 0.0)   // BKE2-OFF: E1 fallback note (kept)
       why += " — no HuntSL pushed for " + tf + " yet, so EngSL stands in";
   why += BaseKnotCapClause(entryTF, isHunt, top, bot, anchor);   // P-BK-52: ... and the ceiling, when it spoke
   return why;
}
// ... and the SHORT form of the same fact — the box hover's first line and the note's
// own hover read THIS sentence, so "how deep" is answered once. P-BK-83: its TF is the
// ENTRY's own time (the node's class), never the stop's rung.
// BKE2-OFF: 2nd entry retired — kept as the name the purge deletes, never drawn.
string BaseKnotEntryLine2(const int kind, const int entryTF, const bool isHunt, const int dir,
                          const double top, const double bot, const datetime anchor = 0)
{
   return "";
}
string BaseKnotEntryLine(const int kind, const int entryTF, const bool isHunt, const int dir,
                         const double top, const double bot, const datetime anchor = 0)
{
   return " · the entry waits ONE " + BaseKnotEntryOffsetTag(isHunt) + " INSIDE the box' " +
          (dir >= 0 ? "top" : "bottom") + " edge (" +
          BaseKnotEntryWhy(kind, entryTF, isHunt, top, bot, anchor) + ")";
}
// P-BK-52 (2026-09-16) — THE NODE'S OWN POWER IS THE CEILING OF BOTH LEGS.
// WHY: P-BK-46/51 push the plan's EngSL / HuntSL in, and a plan leg can be DEEPER than the
// node it is drawn in — a 9-pip node measured with EngSL(M15) = 17 pips put the entry 8 pips
// BEYOND the box' opposite edge while the hover still said «ONE EngSL INSIDE the box' top
// edge» (the user's «برای محل های ورود میگم که دقیق باشه»), and a TF the pump had never
// pushed fell back to the box' WHOLE height, putting the stop a whole box past the entry.
// WHAT: the node's OWN power is its height over the SAME divisor the plan divides its
// composite TR by (64/15), so the ceiling is the same UNIT as the leg it bounds — only
// sourced from the node instead of the market:
//   EngSL_node  = H / 4.266666                    (BK_NODE_POWER_DIV)
//   HuntSL_node = 8/3 x EngSL_node = H x 5/8      (BK_NODE_HUNT_NUM / BK_NODE_HUNT_DEN)
//   leg = min(planLeg, nodeLeg)                   (BaseKnotLegPick — the only rule)
// A node BIGGER than the plan's leg keeps the plan's number exactly (nothing a user sees
// today moves); a node SMALLER than it is sized by its own power. And because
//   off + risk <= HuntSL_node + EngSL_node = (5/8 + 15/64) x H = 55/64 x H < H,
// BOTH legs sit strictly inside the box on EVERY node type — no reserve percentage, no clamp
// constant and no per-type special case.
// THE GATE: the divisor belongs to the plan and the layering law forbids reading
// TradePlanFormulas from this module, so the constants below are kept IN SYNC (and the 55/64
// bound PROVEN from them) by tools/base-count-audit.py [leg-fit], which reads both files —
// drift fails the build, not the chart.
// ONE OWNER: BaseKnotLegPair is the only place the two sizes are decided; the geometry
// (BaseKnotCalcLevels), the R every hover prints (BaseKnotRiskPips), the NAME of that R
// (BaseKnotRiskTag), the stop's sentence (BaseKnotStopWhy) and the entry's
// (BaseKnotEntryWhy / BaseKnotCapClause) all read IT — no line and no number can describe
// two different measurements.
#define BK_NODE_POWER_DIV 4.266666   // == TradePlanFormulas TRADEPLAN_ENG_DIVISOR (gate: leg-fit)
#define BK_NODE_HUNT_NUM  5.0        // 8/3 / 4.266666 == 5/8 exactly — the NODE's own HuntSL
#define BK_NODE_HUNT_DEN  8.0        // ... against the plan's 8/3 (gate: leg-fit keeps one unit)
// The node's own power, in pips — its height over the plan's own Eng divisor. 0 when the box
// has no height yet or the symbol has no pip size: an ABSENCE every caller's fallback names.
double BaseKnotNodeEngPips(const double top, const double bot)
{
   double pip = BaseKnotPipSize();
   if(pip <= 0.0 || BK_NODE_POWER_DIV <= 0.0) return 0.0;
   double h = (top - bot) / pip;
   return (h > 0.0 ? h / BK_NODE_POWER_DIV : 0.0);
}
double BaseKnotNodeHuntPips(const double top, const double bot)
{
   double pip = BaseKnotPipSize();
   if(pip <= 0.0 || BK_NODE_HUNT_DEN <= 0.0) return 0.0;
   double h = (top - bot) / pip;
   return (h > 0.0 ? BK_NODE_HUNT_NUM * h / BK_NODE_HUNT_DEN : 0.0);
}
// THE RULE, in one place — the plan's leg when it is no deeper than the node's own power, the
// node's own power when it is. 0 = BOTH absent (the caller falls back, and NAMES it).
bool BaseKnotLegCapped(const double planPips, const double capPips)
{
   return (capPips > 0.0 && (planPips <= 0.0 || planPips > capPips));
}
double BaseKnotLegPick(const double planPips, const double capPips)
{
   if(BaseKnotLegCapped(planPips, capPips)) return capPips;
   return (planPips > 0.0 ? planPips : 0.0);
}
// THE EFFECTIVE PAIR of one node, in pips — the ONE owner the geometry, the R every text
// prints and both sentences read, so the drawn lines and the printed pips cannot part.
//+------------------------------------------------------------------+
//| BKE2-OFF - THE 2ND ENTRY IS RETIRED (2026-09-28, chart too busy).|
//| E1 stays the knot's own trade; E2 answers absence (0/"") below.  |
//+------------------------------------------------------------------+
// BKE2-OFF: 2nd entry retired — the measure answers 0 (absence), never a level.
double BaseKnotEntry2OffPips(const double top, const double bot, const int kind,
                             const int entryTF, const datetime anchor = 0)
{
   return 0.0;
}
// BKE2-OFF: 2nd entry retired — 0,0 keeps it off the chart.
void BaseKnotCalcEntry2(const double top, const double bot, const int dir, const int kind,
                        const int entryTF, const double riskPips,
                        double &entry2, double &sl2, const datetime anchor = 0)
{
   entry2 = 0.0; sl2 = 0.0; return;
}
void BaseKnotLegPair(const double top, const double bot, const int kind, const int tfMin,
                     double &offPips, double &riskPips, const datetime anchor = 0)
{
   // P-BK-83 — TWO TFs, ONE LEG EACH: the ENTRY's penetration is the NODE'S OWN time's leg
   // (HuntSL for ETR/CTR/OTR, EngSL for FTR — the reading the user confirmed is right), while
   // the STOP is the EngSL of the TYPE'S OWN time (the time the node's LENGTH belongs to).
   // Both owners are asked HERE and nowhere else, so the drawn lines and every printed number
   // come off the same pair.
   int    etf   = BaseKnotEntryTFMin(kind, tfMin);
   int    stf   = BaseKnotMeasureTFMin(kind, tfMin);
   bool   hunt  = BaseKnotOffsetIsHunt(kind, etf, anchor);
   double capE  = BaseKnotNodeEngPips(top, bot);
   double planO = BaseKnotEntryOffsetPips(kind, etf, anchor);
   double planR = BaseKnotEngPips(stf, anchor);
   offPips  = BaseKnotLegPick(planO, hunt ? BaseKnotNodeHuntPips(top, bot) : capE);
   riskPips = BaseKnotLegPick(planR, capE);
   double h = BaseKnotToPips(top - bot);
   if(offPips  <= 0.0) offPips  = (h > 0.0 ? h : 0.0);   // neither source answered — the box'
   if(riskPips <= 0.0) riskPips = (h > 0.0 ? h : 0.0);   //   own height, named by the texts
}
// P-BK-53 (2026-09-16) — ONE SHORT NAME ON THE CHART, THE PROOF IN THE HOVER.
// WHY: P-BK-52 named the ceiling with its formula EVERYWHERE it spoke, so the box' own note
// read «[BUY · the node's own EngSL (its height / 4.2667) 17.9 Pips | …]» — a sentence where
// a NAME belongs (user: «اطلاعات خلاصه و قابل فهمی باشه»). What the user reads a level off is
// the LEG and its SOURCE; the divisor is the PROOF that the number was measured at all, and a
// proof belongs where there is room to read it.
// WHAT: TWO names for ONE fact, both decided by the ONE flag the pick was made with
// (`isHunt` — BaseKnotLegPair's own):
//   * BaseKnotCapTag — the SHORT name ("node EngSL" / "node HuntSL"): what the chart-side
//     note prints and what every `riskTag` inside a hover's parentheses prints;
//   * BaseKnotCapWhy — the SAME source spelled out WITH the arithmetic that sized it
//     ("the node's own EngSL (its height / 4.2667)"): the hovers' own clauses only.
// P-BK-52's rule — a number nobody can check is never printed — still holds: the name rides
// the chart, the proof rides the hover, and neither is a second number.
// THE GATE: tools/base-count-audit.py [leg-fit / the chart's own label] reads BOTH — a formula
// smuggled back into the tag, or a short name leaking into the clause, fails the build.
string BaseKnotCapTag(const bool isHunt)
{
   return (isHunt ? "node HuntSL" : "node EngSL");
}
// ... and the SAME source spelled for the room a HOVER has: the source and the formula that
// sized it, so a number nobody can check never gets printed where it is read out.
string BaseKnotCapWhy(const bool isHunt)
{
   return (isHunt ? "the node's own HuntSL (its height x 5/8)"
                  : "the node's own EngSL (its height / 4.2667)");
}
// ... and the ONE clause every entry sentence appends when the ceiling really spoke (an empty
// string while the plan's leg still fits): the box hover, the note's hover and the entry ray
// share these exact words — the PROOF form (P-BK-53), because a hover has the room for it.
string BaseKnotCapClause(const int measureTF, const bool isHunt, const double top, const double bot,
                         const datetime anchor = 0)
{
   double plan = (isHunt ? BaseKnotHuntPips(measureTF, anchor) : BaseKnotEngPips(measureTF, anchor));
   double cap  = (isHunt ? BaseKnotNodeHuntPips(top, bot) : BaseKnotNodeEngPips(top, bot));
   if(!BaseKnotLegCapped(plan, cap)) return "";
   return " — CAPPED by " + BaseKnotCapWhy(isHunt) + " = " + DoubleToString(cap, 1) + " pips";
}
// ... and the stop's own sentence, shared by the hover and the note, so the two texts can
// never name two different sources for the one R they draw. P-BK-53: it answers WHICH source
// spoke and WHY in plain words (the plan's leg against the node's own), never in code words
// («power stands in» said nothing a user could check).
string BaseKnotStopWhy(const int measureTF, const double top, const double bot, const datetime anchor = 0)
{
   double plan = BaseKnotEngPips(measureTF, anchor);
   double cap  = BaseKnotNodeEngPips(top, bot);
   if(BaseKnotLegCapped(plan, cap))
      return (BaseKnotRiskIsEng(measureTF, anchor)
              ? " — the plan's EngSL of " + BaseKnotTFName(measureTF) + " (" + DoubleToString(plan, 1) +
                " pips) is deeper than the node, so " + BaseKnotCapWhy(false) + " stands in"
              : " — the pump has no EngSL for " + BaseKnotTFName(measureTF) +
                " yet, so " + BaseKnotCapWhy(false) + " stands in");
   if(plan > 0.0) return "";
   return " — neither the plan nor the node could size it, so the box' own height stands in";
}
void BaseKnotCalcLevels(const double top, const double bot, const int dir,
                        const int kind, const int tfMin, double &entry, double &sl,
                        const datetime anchor = 0)
{
   double pip  = BaseKnotPipSize();
   // P-BK-52: the pair comes from ONE owner — the plan's legs, bounded by the node's own
   // power — so the lines drawn here and the R every hover prints cannot part.
   // BKATRLEG-OFF (P-BK-51/52): the retired pair that used the plan's leg UNBOUNDED — a leg
   // deeper than the node put the entry past the box' far edge, and a TF the pump had not
   // pushed put the stop a whole box behind it. Restore by uncommenting the three lines below
   // and dropping the pair above them.
   // BKATRLEG-OFF: int    mtf  = BaseKnotMeasureTFMin(kind, tfMin);
   // BKATRLEG-OFF: double off  = BaseKnotEntryOffsetPips(kind, mtf) * pip;   // P-BK-51: the entry waits this deep
   // BKATRLEG-OFF: double risk = BaseKnotEngPips(mtf) * pip;                 // ... and the stop is ONE EngSL behind it
   double offP = 0.0, riskP = 0.0;
   BaseKnotLegPair(top, bot, kind, tfMin, offP, riskP, anchor);   // P-BK-79: the pair is read at the box' own anchor
   double off  = offP  * pip;   // the entry waits this deep INSIDE the side's own edge
   double risk = riskP * pip;   // ... and the stop is ONE EngSL behind it
   // BKGEOM-OFF (P-BK-50): the retired "ONE R OUTSIDE the edge, stop ON that edge" pair —
   // restore by uncommenting these four lines and DROPPING the two below (the R it reads
   // carries the P-BK-52 ceiling, so restoring it restores that geometry, not the old sizes).
   // BKGEOM-OFF: double r = BaseKnotRiskPips(tfMin, top, bot) * BaseKnotPipSize();
   // BKGEOM-OFF: if(r <= 0.0) r = top - bot;
   // BKGEOM-OFF: if(dir >= 0) { entry = top + r; sl = top; }
   // BKGEOM-OFF: else         { entry = bot - r; sl = bot; }
   if(off  <= 0.0) off  = top - bot;   // no pip size and no pushed value — the box' own height
   if(risk <= 0.0) risk = top - bot;   //   (the same absence rule; every text NAMES the source)
   if(dir >= 0) { entry = top - off; sl = entry - risk; }   // Buy: inside = below the top edge
   else         { entry = bot + off; sl = entry + risk; }   // Sell: inside = above the bottom edge
   // BKTPR-OFF (P-BK-50): the retired R-multiple target. Restore by uncommenting
   // these two lines (and the `TARGET R` sites in BaseKnotSync / BaseKnotSyncLive).
   // BKTPR-OFF: double mult = (g_bkTargetR >= 1 ? (double)g_bkTargetR : BK_TP_R_MULT);
   // BKTPR-OFF: double tp = (dir >= 0 ? entry + r * mult : entry - r * mult);
}

void BaseKnotMakeRay(const string name, const datetime tA, const datetime tB,
                     const double level, const color clr, const int style, const int width,
                     const string tooltip, const long tfMask, const bool rayRight)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, tA, level, tB, level);
   ObjectMove(0, name, 0, tA, level);
   ObjectMove(0, name, 1, tB, level);   // horizontal — Entry/SL project forward (ray-right),
                                          // TP is a short target tick at the right edge (never a ray)
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);   // TF-scoped with the box
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // the BOX is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);   // levels read over candles (like TH lines)
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_RAY);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
// TP tick span — the target marker hugs the chart's RIGHT edge, next to the
// price axis (user decision 2026-09-08): a SHORT fixed tick (2 bars) ending
// exactly at the window's right edge time — never a ray, never box-wide.
// Falls back to the current bar (then box-anchored) when the edge/series is
// not convertible.
datetime BaseKnotTPEdgeTime()
{
   long wpx = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(wpx <= 10) return 0;
   int sw = 0; datetime et = 0; double ep = 0;
   if(!ChartXYToTimePrice(0, (int)wpx - 1, 10, sw, et, ep)) return 0;
   if(sw != 0 || et <= 0) return 0;
   return et;
}
void BaseKnotTPTickSpan(const datetime t1, const datetime t2, datetime &ts, datetime &te)
{
   datetime et = BaseKnotTPEdgeTime();
   if(et > 0) { te = et; ts = et - (datetime)(2 * PeriodSeconds()); return; }
   datetime cur0 = iTime(_Symbol, 0, 0);
   ts = (cur0 > 0 ? cur0 : t2);
   te = ts + (datetime)(2 * PeriodSeconds());
}
// Lean edge glue for the 500ms pump: scroll/zoom/new bars only remap TIME, so
// the tick is re-anchored with two ObjectMoves (level untouched) — never a
// full Sync. Missing TPs heal via OBJECT_DELETE, ray-flagged ones via Sync.
// P-BK-50: the box carries up to THREE of these now, and the glue walks exactly
// the set BaseKnotTPCount() draws — the same set the Sync builds and the probe
// below guards, so the three can never drift apart.
void BaseKnotTPGlue(const string pfx, const datetime edgeT)
{
   int n = BaseKnotTPCount();
   // BKE2-OFF: set 2 retired — leftovers are purged by Sync, never glued.
   for(int k2 = 1; k2 <= n; k2++) ObjectDelete(0, BaseKnotTPTick2Name(pfx, k2));
   for(int k = 1; k <= n; k++)
   {
      string tpNm = BaseKnotTPTickName(pfx, k);
      if(ObjectFind(0, tpNm) < 0) continue;
      if(ObjectGetInteger(0, tpNm, OBJPROP_RAY_RIGHT) != 0) continue;   // structural — the Sync path rebuilds it
      datetime ts = edgeT - (datetime)(2 * PeriodSeconds());
      if((datetime)ObjectGetInteger(0, tpNm, OBJPROP_TIME, 0) != ts ||
         (datetime)ObjectGetInteger(0, tpNm, OBJPROP_TIME, 1) != edgeT)
      {
         ObjectMove(0, tpNm, 0, ts, ObjectGetDouble(0, tpNm, OBJPROP_PRICE, 0));
         ObjectMove(0, tpNm, 1, edgeT, ObjectGetDouble(0, tpNm, OBJPROP_PRICE, 1));
      }
   }
}
// TP tick look — SOLID + THICK: a 2-bar DASHED tick renders as almost nothing,
// so the tiny marker must be solid and thicker to read instantly. P-BK-50 (user:
// «با یک خط کوچک ولی ضخیم که دیده بشه»): 2px was still thin at native res, and the
// box draws up to THREE of these now, so they have to be read apart at a glance.
#define BK_TP_TICK_STYLE STYLE_SOLID
#define BK_TP_TICK_WIDTH 3
// TP staleness for the 500ms pump: only STRUCTURAL drift (a pre-tick ray, an
// older dashed/thin tick, or the retired single tick a pre-P-BK-50 build left
// behind) heals via a full Sync here — edge/scroll/new-bar drift is glued lean by
// BaseKnotTPGlue above. Read-guarded: steady state is compares only, no Sync.
// P-BK-50: the walk is over the DRAWN legs (1..TP COUNT) — a missing tick is the
// OBJECT_DELETE path's business (user-deleted children are not resurrected here),
// and a count the user lowered is healed by the setting's own restyle → Sync.
bool BaseKnotTPStale(const string pfx)
{
   if(ObjectFind(0, BaseKnotTPName(pfx)) >= 0) return true;   // BKTPR-OFF: the pre-P-BK-50 single tick
   int n = BaseKnotTPCount();
   for(int k = 1; k <= n; k++)
   {
      string tpNm = BaseKnotTPTickName(pfx, k);
      if(ObjectFind(0, tpNm) < 0) continue;   // user-deleted children heal via OBJECT_DELETE, not here
      if(ObjectGetInteger(0, tpNm, OBJPROP_RAY_RIGHT) != 0) return true;
      if(ObjectGetInteger(0, tpNm, OBJPROP_STYLE) != BK_TP_TICK_STYLE) return true;
      if(ObjectGetInteger(0, tpNm, OBJPROP_WIDTH) != BK_TP_TICK_WIDTH) return true;
   }
   // BKE2-OFF: set 2 retired — any leftover tick counts as stale so Sync purges it.
   for(int k2 = 1; k2 <= n; k2++)
   {
      if(ObjectFind(0, BaseKnotTPTick2Name(pfx, k2)) >= 0) return true;
   }
   if(ObjectFind(0, BaseKnotEntry2Name(pfx)) >= 0) return true;
   if(ObjectFind(0, BaseKnotSL2Name(pfx)) >= 0) return true;
   return false;
}
void BaseKnotMakeBadge(const string name, const string text, const color bg)   // NOBKDEL: retired — no badge is created anymore (kept for one-line restore)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_BADGE_W);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_BADGE_H);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, BioChromeFont());
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PnlPt(BK_PT_BADGE));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, BIO_CLR_DEEP);   // P-UI-117: the shared
                                    // deep navy — a one-line restore must not reintroduce
                                    // the literal the owner now names
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_BADGE);  // P-UI-31: under the settings card
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}
// INFO visibility — Show mode pins the label on; Auto shows it live while
// sizing (LIVE_ tag always writes) and for BK_INFO_GRACE_MS after commit,
// then hides it so the chart stays clean. Full numbers always ride the
// box/edge hover tooltips, so nothing is ever unreachable.
// P-BK-58: and the CORNER rung (2) takes the note off the box altogether — the box-side copy
// is the one that has to be off, because the note then lives in ONE place only (the family's
// row, BaseKnotNoteAtCorner). Both callers of this probe already delete a note they are told
// not to show, so the rung needs no second switch anywhere.
bool BaseKnotInfoVisible(const string id)
{
   if(BaseKnotNoteInCorner()) return false;   // P-BK-58: the note's home is the family's column
   if(g_bkShowInfo == 1) return true;
   int k = BaseKnotFind(id);
   if(k < 0) return true;
   return ((int)(GetTickCount() - g_bkBoxes[k].commitMs) < (int)BK_INFO_GRACE_MS);
}
//+------------------------------------------------------------------+
//| P-BK-58 — THE NOTE HAS TWO HOMES, AND THE USER PICKS ONE.        |
//|                                                                  |
//| «لیبل اطلاعات بیس را کنار همان کارت/ردیف خانوادهٔ لیبلها هم نشان  |
//| بده تا کاربر بتواند بین «چسبیده به باکس» و «گوشهٔ ثابت» یکی را    |
//| انتخاب کند». What each home is FOR: the box-side note tells the  |
//| box' own story where the box is (it moves with the trade, and    |
//| that is what makes it hard to read on a busy chart); the CORNER   |
//| row lines up with the ATR/TH columns and the TRex trade card, so  |
//| the same numbers can be read as a readout.                       |
//| WHAT DOES NOT CHANGE: the TEXT (one writer, BaseKnotWriteInfo),  |
//| its size/font/colour/rung (P-BK-27/56), the box hover tooltips    |
//| and every drawn level. The two homes differ ONLY in the object    |
//| they write to and how it is anchored.                            |
//|                                                                  |
//| WHICH BOX the corner answers (user decision 2026-09-16): THE       |
//| SELECTED one — the user clicked it, so the row answers the        |
//| question he just asked. MT4's own single-select is READ           |
//| (`OBJPROP_SELECTED` on the box' handle, which P-BK-26's           |
//| BKSELECT-KEPT leaves intact), never re-implemented; with nothing  |
//| selected the NEWEST box answers, and the box being SIZED always   |
//| wins (sizing is the one moment the readout is looked at).         |
//|                                                                  |
//| THE SLOT IS PUSHED IN, never read here: the column's margins and  |
//| its row pitch belong to the label module (`inpLabelsMarginLeft`,  |
//| the ATR trade card's own layout), which sits ABOVE this module —  |
//| so it pushes the corner, the x and the y (BaseKnotCornerSlotPush) |
//| and this module only draws there. No margin is ever guessed.      |
//|                                                                  |
//| ONE OBJECT AT A TIME: the writer empties the other home as it     |
//| fills this one, so a mode change can never leave two copies of    |
//| the same number on the chart. Steady state costs NOTHING: the row |
//| is written on a CHANGE (mode, selection, slot, or the box' own    |
//| Sync), never once per pump round.                                 |
//+------------------------------------------------------------------+
bool BaseKnotNoteInCorner() { return (g_bkShowInfo == BK_NOTE_CHART); }
// The row's object name. ONE row for the whole chart (it is the family's column, not a box
// child — see BK_NOTE_CORNER).
string BaseKnotCornerName()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + BK_NOTE_CORNER;
}
// The pushed slot (-1 = the family has never pushed one, i.e. there is nowhere to draw).
static int  s_bkCornerSide  = -1;
static int  s_bkCornerX     = 0;
static int  s_bkCornerY     = 0;
static bool s_bkCornerDirty = true;   // a slot write is owed (the row may not exist yet)
static string s_bkCornerId  = "";     // the box the row currently carries ("" = the sizing box)
// The row's own wipe (deinit + a mode change): the object goes AND the books are cleared, so the
// next refresh rebuilds instead of believing the row it just deleted is still there.
void BaseKnotCornerWipe()
{
   string nm = BaseKnotCornerName();
   if(nm != "" && ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   s_bkCornerId    = "";
   s_bkCornerDirty = true;
}
void BaseKnotCornerSlotPush(const int corner, const int xPos, const int yPos)
{
   if(corner == s_bkCornerSide && xPos == s_bkCornerX && yPos == s_bkCornerY) return;
   s_bkCornerSide  = corner;
   s_bkCornerX     = xPos;
   s_bkCornerY     = yPos;
   s_bkCornerDirty = true;   // read by the pump (≤500 ms) — never a chart write per push
}
// THE box the corner answers — see the block above: the SELECTED one, else the NEWEST.
string BaseKnotSelectedId()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   string best = "";
   uint   bestMs = 0;
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string pfx = BaseKnotPrefix(g_bkBoxes[i].id);
      if(pfx == "") continue;
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) < 0) continue;
      if((bool)ObjectGetInteger(0, box, OBJPROP_SELECTED)) return g_bkBoxes[i].id;   // clicked = the answer
      if(best == "" || g_bkBoxes[i].commitMs >= bestMs)
      {
         best = g_bkBoxes[i].id;
         bestMs = g_bkBoxes[i].commitMs;
      }
   }
   return best;
}
// ONE decision owner for WHERE the note is drawn: the writer (and its callers) ask THIS.
// `id` = "" is the box being SIZED (its own live tag is not in the registry) — it always wins,
// because while the user draws the readout must answer the box under his cursor.
bool BaseKnotNoteAtCorner(const string id)
{
   if(!BaseKnotNoteInCorner()) return false;
   if(id == "") return true;
   return (id == BaseKnotSelectedId());
}
// The row's own keeper — called from the existing 500 ms pump (BaseKnotSyncBadges), so the
// corner follows a selection change, a mode change, a pushed slot or a box that left this TF
// without a new event path of its own. NOTHING IS WRITTEN while nothing changed.
void BaseKnotNoteCornerRefresh()
{
   string nm = BaseKnotCornerName();
   if(nm == "") return;
   if(!BaseKnotNoteInCorner())
   {
      if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);   // the box-side home owns the note now
      s_bkCornerId    = "";
      s_bkCornerDirty = false;   // nothing is owed while the rung is not the corner one
      return;
   }
   if(g_bkState == BK_PREVIEW)
   {
      s_bkCornerDirty = true;   // the live writer owns the row while the user draws — the NEXT round
      return;                    // re-decides, so a cancelled BAND cannot leave its preview text behind
   }
   string id = BaseKnotSelectedId();
   if(id != "" && !BaseKnotVisibleNow(id)) id = "";   // a box hidden on this TF claims no row
   if(id == s_bkCornerId && !s_bkCornerDirty)
   {
      // Steady state: not one chart write. The ONE read left is the heal — something else
      // (a chart-wide cleanup, the user's own delete) may have taken the row away, and a
      // readout that silently disappears is the bug this keeper exists for.
      if(id == "" || ObjectFind(0, nm) >= 0) return;
      s_bkCornerDirty = true;   // rebuild it below
   }
   s_bkCornerId = id;
   s_bkCornerDirty = false;
   if(id == "")
   {
      if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);   // nothing answers: a stale note is worse than none
      return;
   }
   BaseKnotSync(id);   // the ONE writer rebuilds the box AND its note — into the row
   ChartRedraw();
}
// ONE candle's "is it inside the box" read — the BODY is the criterion (both
// open and close inside [bot,top], boundary INCLUSIVE, direction-free): wicks may
// pierce the band, a candle whose BODY is outside is not part of the base.
// Single definition, so every caller counts the same candle the same way.
bool BaseKnotBarBodyInside(const int shift, const double top, const double bot)
{
   double o = iOpen(_Symbol, 0, shift);
   double c = iClose(_Symbol, 0, shift);
   return (o >= bot && o <= top && c >= bot && c <= top);
}
//+------------------------------------------------------------------+
//| P-BK-85 (2026-09-18) — THE EXIT CANDLE IS THE ONE THAT CLOSED      |
//| OUTSIDE, AND THAT IS THE ONLY TEST.                                |
//|                                                                  |
//| P-BK-42's own definition, word for word: the ENTRY is the base's   |
//| oldest candle whose body is inside the band and is NOT counted;    |
//| the EXIT is the candle that CLOSED OUTSIDE it and IS counted. The  |
//| two are told apart by the BAND, and the exit's own test is its     |
//| CLOSE — P-BK-41 calls `tExit` «the candle that closed outside the  |
//| band», and P-BK-81 reads the whole trade's DIRECTION off that same |
//| candle's close.                                                    |
//|                                                                  |
//| `BaseKnotBarBodyInside` asks for open AND close, so a candle that  |
//| poked out of the band and CLOSED BACK INSIDE it fails that test    |
//| while it never closed outside at all. Reading the exit off it      |
//| would put the knot's formation one candle too early — and since    |
//| P-BK-84 that candle's time is also the class' span's right end and |
//| the direction walk's own start, so one wrong candle moves the      |
//| count, the node's time AND the side together.                      |
//|                                                                  |
//| The user: «کندل ورود و خروج بیس باید دقیق پیدا بشه … اگر تعداد      |
//| اشتباه بشه همه چیز اشتباه میشه پس باید صد در صد کندل ورود و خروج   |
//| رو مطمئن باشیم که تعداد درست باشه».                               |
//+------------------------------------------------------------------+
bool BaseKnotBarCloseOut(const int shift, const double top, const double bot)
{
   double c = iClose(_Symbol, 0, shift);
   if(c <= 0) return false;              // series not ready — never a CLAIMED exit
   return (c < bot || c > top);
}
// THE BASE'S OWN LENGTH — the candles that go nowhere, ending where it BREAKS.
// P-BK-31 (2026-09-15) — «عدد واقعی ۱۹ باید در هر حالت نشون بده، الان ۲۰ نشون
// میده؛ عقب بکشیم ۴۳ میشه». Two earlier rules measured the WRONG THING (every close
// inside the band over the box's span; every BODY inside it anywhere in the box) —
// both measured the BOX, and the base is a property of the PRICE ACTION: the run of
// candles that sit inside the band, ending where price leaves it.
// HOW IT IS READ (P-BK-31/32/39): the anchor is the box's RIGHT edge and the walk
// goes OLDER; ONE isolated out-of-band body is stepped over and NOT counted
// (BK_BASE_GAP), while a cluster is the base's end; a re-entry joins only once
// BK_BASE_MIN_BARS of them in a row hold the band; the anchor may step over up to
// BK_BASE_SKIP bars (the walk's own cap — a bar count is TF-dependent, and 30 blew a
// D1 box out); the LEFT edge bounds NOTHING (t1 is only a validity check), so
// dragging the box back cannot inflate the number.
// THE TOLERANCE IS A COUNT OF CANDLES, NEVER A PRICE MARGIN — widening the band for
// the test would put the BAND back inside the number. Coherent with P-BK-28/29's
// class and type, which read the same base. 0 = nothing measurable (callers then omit
// the bars part). Cost: one bounded walk (~2 · BK_BASE_MAX series reads).
#define BK_BASE_SKIP 300      // candles the anchor may step over the break (P-BK-39: the walk's cap)
#define BK_BASE_GAP    1      // isolated out-of-band BODIES the run steps over (a COUNT of candles)
#define BK_BASE_MIN_BARS 3    // «سه کندل درجا زدن» — a re-entry needs a base's own length to count
#define BK_BASE_MAX  300      // hard cap on one walking run (M1: 5 hours — no base is longer)
// P-BK-41 (2026-09-15) — ONE SPAN: THE BASE'S OWN STORY.
// «از جای که وارد بیس شده تا جایی که ازش خارج شده و شکسه و کلوز کرده 9 کندل هستش این
// چرا 38 نوشته … فکر کنم بهتر که از زمانی که وارد بیس شده تا زمانیکه خارج از بیس یا
// گره معاملاتی شده رو تعداد کندل ها شو نشون بده» — the number must be the candles the
// BASE lasted: from the candle that entered the band to the candle that CLOSED OUTSIDE
// it (the break — the knot's own formation), and nothing else.
//
// P-BK-37 had read it as «from the base's start to the BOX' right edge», which made the
// number a property of the BOX instead of the base: with the anchor search budget at
// the walk's cap (P-BK-39: 300 candles — needed so a box drawn over a break still finds
// its base on a higher TF) every candle between the base's exit and the box' right
// edge — a dead zone, or a box simply dragged forward — was counted as if the base had
// lasted it. His own M15 box: a 9-candle base whose box reached ~29 candles past the
// exit printed «38 bars». The END is not the box: the anchor search checked EVERY
// candle from the box' right edge back to the anchor and found them all OUTSIDE the
// band, so the first of them (anchor - 1) IS «the candle that closed outside» — it is
// counted (the knot forms on its close) and the story stops there. Dragging the box
// further right is now FREE — it cannot add a candle the base never lasted — and the
// left edge still bounds nothing at all (P-BK-31).
//
// The CLASS rides the SAME span (one walk, one story — the P-BK-40 law): the rung's
// own candles are read between the base's first candle and its exit, so a box that is
// merely long can no longer let a higher TF be named by candles that are not the base.
// (the span RECORD itself is declared up beside the registry — the tooltip and the
// note read it there, far above this walk.)
// P-BK-40 (2026-09-15) — THE WALK REPORTS BOTH NUMBERS, because they answer two
// different questions and the user needs to see which one he is reading: the return
// is the base's LIFE — its own two ends only, P-BK-41/42 SUPERSEDING the "to the box'
// right edge" reading of P-BK-37 (the note's "N bars": «کندل ورود جز شمارش حساب نکنیم
// ولی کندل خروج جز شمارش حساب بکنیم»), and `sp.still` is how many candles STOOD STILL
// (bodies inside the band — «سه کندل درجا زدن», the base's own length the SIZE CLASS is
// read from, P-BK-28/36). One walk, several answers, never a second count: on the
// user's own D1 box they are 10 and 10 («اینجا چرا ده تا نشون میده در صورتی که 13 تا
// هستش» — the 13 was the box' own reach, which is no longer part of the base), and the
// box hover now spells the band, the entry, the exit and the number out, in that order.
int BaseKnotBarCount(const datetime t1, const datetime t2, const double top, const double bot,
                     BaseKnotSpan &sp)
{
   BaseKnotSpanClear(sp);
   if(t1 <= 0 || t2 <= 0 || top <= bot) return 0;
   int sh1 = iBarShift(_Symbol, 0, t1, false);
   int sh2 = iBarShift(_Symbol, 0, t2, false);
   if(sh1 < 0 || sh2 < 0) return 0;
   // Shift 0 is the LIVE bar, so the box's RIGHT edge (the newer end, where the
   // break is) is the SMALLER shift; walking OLDER increases it.
   int s = (sh1 < sh2 ? sh1 : sh2);
   int total = Bars;
   if(s < 0 || s >= total) return 0;
   // P-BK-34 (2026-09-15) — THE COUNT IS CLOSED-BAR DATA, the same law the node
   // read already obeys (P-BK-29). Shift 0 is the FORMING candle, and iBarShift()
   // answers 0 for ANY time after the last one, so a right edge dragged past the
   // live candle used to anchor the walk — and count — a candle whose body is
   // still moving: on the user's D1 chart that half-formed body was the only one
   // left in the band (the two candles before it ended 0.1..7 points above the
   // box' top), so the note read «1 bars · struct» for a box on a base — «باکس که
   // از کندل لایو جلو میزنه تعداد کندل اشتباه میکنه». A forming candle has not
   // «gone nowhere» yet, and an edge past the live candle must read exactly like
   // an edge ON the newest closed one, so the anchor is at least shift 1.
   if(s == 0) s = 1;
   if(s >= total) return 0;   // the series is a single, still-forming candle
   // P-BK-37 (2026-09-15) — THE NUMBER IS THE BASE'S LIFE. (Its END is no longer the
   // box' right edge — P-BK-41/42 below supersede that half: the number stops at the
   // candle that closed outside the band, and the entry candle is not counted.)
   // The RULE that finds the base is untouched (P-BK-31/32: the anchored
   // run of in-band bodies, one poke stepped over, a re-entry confirmed at a base's
   // own length); what changes is WHICH of its two ends the number reports. It now
   // reports the START (the run's own oldest in-band candle — a property of the
   // price action) instead of the count of in-band bodies, so:
   //   * P-BK-31's promise holds: the box' LEFT edge still bounds nothing (43);
   //   * P-BK-33's promise (a box dragged forward over its own break no longer read
   //     zero) holds through P-BK-41's exit rule instead of by counting the drag;
   //   * the user's own D1 box (13 candles over the base and its break, band
   //     1.1508..1.1579, in-band bodies Aug 5..18 = 10, box reached Aug 21) reads
   //     10 bars · D1 base (P-BK-42: the entry is out, the exit is in);
   //   * a poke INSIDE the base is one of the candles the base lasted, so it is
   //     inside the number (the poke's job is not cutting the RUN — P-BK-32 — not
   //     vanishing from the count).
   // The SIZE CLASS (P-BK-28/36/41) is read on the SAME span — the base's own story —
   // so count and class describe one object, and the rung confirmation is what keeps a
   // box dragged over a long break from inflating the class.
   int edge = s;   // the box' right edge, off the forming candle (P-BK-34)
   // P-BK-43 (2026-09-15) — A STRAY CANDLE IS NOT A BASE, and the anchor search is ONE
   // walk. «الان یک درست برای این بازه باگ داریم … اینجا های که شلوغ میشه همه نباید باگ
   // داشته باشیم»: in a congested zone the candle nearest the box' right edge can be a
   // lone body that happens to hold the band while everything around it pokes out — and
   // that candle used to ANCHOR the whole answer, so the note printed «1 bars · struct»
   // (or a base that is not there) for a box drawn on a real range. The search now asks
   // the SAME question of every candidate it meets: does a base start here? — and only a
   // candle whose run holds a base's own length (BK_BASE_MIN_BARS standing candles, the
   // same three the size class is read from, P-BK-28/36) becomes the anchor. The budget
   // is untouched: every candle examined counts against BK_BASE_SKIP from the box' right
   // edge, so a box dragged further than a whole walk from any base still reads none
   // (P-BK-39) instead of latching onto a range that is not there.
   int anchor = 0;   // the base's NEWEST stand-still candle (P-BK-41)
   int head   = 0;   // ... found on BOTH sides of the box' right edge (P-BK-44)
   int n      = 0;   // base candles counted (drives the cap and the confirmation)
   int gap    = 0;   // consecutive bodies outside the band since the last one inside
   int probe  = 0;   // in-band bodies past a tolerated gap, not yet a base's length
   int oldest = 0;   // shift of the OLDEST candle the base lasted (P-BK-37: the start)
   while(s < total && s - edge < BK_BASE_SKIP)
   {
      if(!BaseKnotBarBodyInside(s, top, bot)) { s++; continue; }   // the break / the dead zone
      // P-BK-44 (2026-09-15) — THE BOX' LINES EXTEND FORWARD TOO. «این چرا عقب میارمش
      // فرق میکنه اعداد … 36 تا درست بودش اون نباید 20 باشه … باید امتداده باکس ها به
      // عقب و جلو خطوط شو در نظر بگیر بای کندل ورود و خروج، ملاک که سقف و کف بیس هستش نه
      // داخل باکس»: when the box' right edge is pulled back INTO the base, the candles
      // that are still holding the band to the RIGHT of that edge are the same base —
      // the drawn rectangle is a pointer, the band is the criterion. So the run is
      // walked NEWER first (the exit side), with the SAME tolerance as the entry side,
      // and only then OLDER (the entry side) from its own newest candle. A box whose
      // edge is inside a base reads the WHOLE base now (his 20 became the 36 his wider
      // box read), and a box dragged past its own break is unchanged: the first candle
      // newer than the run already closed outside, so the run cannot extend at all.
      head = s;
      {
         int fup = s - 1, fgap = 0, fprobe = 0, fn = 0;
         while(fup >= 1 && fn + fprobe < BK_BASE_MAX)
         {
            if(BaseKnotBarBodyInside(fup, top, bot))
            {
               if(fgap == 0) { fn++; head = fup; }
               else
               {
                  fprobe++;
                  if(fprobe >= BK_BASE_MIN_BARS) { fn += fprobe; fprobe = 0; fgap = 0; head = fup; }
               }
            }
            else
            {
               fgap++;
               if(fgap > BK_BASE_GAP) break;
            }
            fup--;
         }
      }
      anchor = head;                   // the run's OWN newest candle: the exit is read off it
      n = 0; gap = 0; probe = 0; oldest = 0;
      // P-BK-32 — THE RUN WITH THE TOLERANCE, walked on its own cursor so a candidate
      // that does not hold a base leaves `s` free to look behind it. `gap` counts the
      // consecutive bodies OUTSIDE the band: one of them (BK_BASE_GAP) is stepped over —
      // a poke does not cut the base — and a CLUSTER ends it. `probe` holds the candles
      // found past a tolerated gap until BK_BASE_MIN_BARS of them in a row hold the band;
      // they join the base only then, which is what stops a stray in-band candle on the
      // ENTRY side from re-opening the run (the 19 -> 20 P-BK-31 rejected). The budget
      // covers the probe as well, so the WALK is capped, not only the count.
      int t = head;   // P-BK-44: the older walk starts at the run's head, so BOTH sides
                      // of the box' right edge are inside the number and the class
      while(t < total && n + probe < BK_BASE_MAX)
      {
         if(BaseKnotBarBodyInside(t, top, bot))
         {
            if(gap == 0)
            {
               n++;                            // the run continues — this candle is base
               oldest = t;                     // ... and it is the new START of the life
            }
            else
            {
               probe++;                        // inside AGAIN, just past the poke
               if(probe >= BK_BASE_MIN_BARS)   // ... and it holds a base's own length
               {
                  n += probe;                  // only then do those candles join the base
                  probe = 0;
                  gap   = 0;
                  oldest = t;                  // the oldest of the confirmed probe candles
               }
            }
         }
         else
         {
            gap++;                             // one body outside — a poke (or the entry)
            if(gap > BK_BASE_GAP) break;       // a CLUSTER of them: this candidate ended here
         }
         t++;
      }
      if(n >= BK_BASE_MIN_BARS && oldest > 0) break;   // THIS candle anchors a base
      s = t;                                           // a stray body: look behind it
      anchor = 0;
   }
   if(anchor <= 0 || oldest <= 0) return 0;   // no base inside the walk's own budget
   // P-BK-44: the EXIT is the first candle NEWER than the run's own newest candle —
   // so it is the real exit candle even when the box' right edge sits inside the base
   // (the run extends past that edge and the exit lies to the RIGHT of the box), and
   // when the newest closed candle is itself still the base there is no exit yet: the
   // number then stops at it instead of reaching into the forming candle (P-BK-34).
   // P-BK-41 — THE STORY ENDS WHERE THE BASE ENDED, and since P-BK-44 that END belongs
   // to the RUN, not to the box: `head` is the run's own newest stand-still candle
   // (found on both sides of the box' right edge), so `head - 1` is the candle that
   // CLOSED OUTSIDE the band — «the candle that closed outside» (the break / the knot's
   // formation). It is INSIDE the story and the story stops there, no matter where the
   // drawn rectangle happens to end: dragged back into the base it still reads the
   // whole base, and dragged forward past the break the run cannot extend at all (the
   // next candle out is already outside), so the number cannot be inflated by the drag.
   int end = (head > 1 ? head - 1 : head);
   // P-BK-85 — AND THE EXIT IS VERIFIED, NOT ASSUMED. `head` is the run's newest candle whose
   // BODY is inside the band, so `head - 1` is normally the first candle past it — but «past
   // the body» is not «closed outside»: a candle that poked out and closed back inside is
   // still a candle the base holds, and naming it the exit would count the knot's formation
   // one candle early and hand P-BK-84's span a break that never happened. The CLOSE is the
   // only test (P-BK-42/41/81). When nothing closed outside yet, the base simply has NO exit:
   // the end stays the base's OWN right side (`head`, == `tLast`), which is exactly what
   // P-BK-34 asks for — the number stops at the newest closed candle, never one past it.
   if(!BaseKnotBarCloseOut(end, top, bot)) end = head;
   // P-BK-42 (2026-09-15) — HOW THE TWO ENDS ARE COUNTED: «اول باید سقف و کف بیس یا
   // گره معاملاتی رو مشخص کنیم که ببینم کدوم کندل وارد شده و کدوم کندل خارج شده — کندل
   // ورود جز شمارش حساب نکنیم ولی کندل خروج جز شمارش حساب بکنیم». The band (top/bot) is
   // what tells the two candles apart: the ENTRY is the base's oldest candle whose body
   // is inside it (`oldest`) and it is NOT counted; the EXIT is the candle that CLOSED
   // OUTSIDE it (`end`) and it IS counted. The note's number is therefore the span
   // between the two, endpoints counted only at the exit end — the candles the base
   // actually held between entering and leaving it. (`still` keeps its own meaning and
   // still counts the entry candle, because it is the base's own LENGTH that the size
   // class is read from — P-BK-28/40 — not the note's span.)
   sp.still  = n;                              // P-BK-40: the class's input (entry included)
   sp.tStart = iTime(_Symbol, 0, oldest);      // the ENTRY candle (not counted)
   sp.tLast  = iTime(_Symbol, 0, head);        // the base's own right side (both sides)
   sp.tExit  = iTime(_Symbol, 0, end);         // the EXIT candle (counted)
   sp.life   = oldest - end;                   // P-BK-42: entry out, exit in
   return sp.life;
}
#endif // BASE_KNOT_MEASURE_MQH
