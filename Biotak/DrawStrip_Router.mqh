// DrawStrip_Router.mqh - DrawStrip split 2026-09-29: exact lines 7019-7969 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_ROUTER_MQH
#define DRAW_STRIP_ROUTER_MQH


void DrawStripGripMove(const int mx, const int my, const bool left)
{
   // P-DRAW-17: the press EDGE and the latch are the router head's (it runs on
   // every move, open or closed); this function only reads them.
   if(!s_dsOpen) { DrawStripGripRelease(); return; }
   if(left && s_dsLeftPress)
   {
      // P-DRAW-48: THE OPACITY BAR'S OWN PRESS, asked FIRST — the bar lives on the
      // board, so its press is never a carry and never the chart's. Without this
      // term the gesture fell through to the terminal and panned the chart under
      // the board (the report: «شفافیت که درگ میکنم چارت پشتش تکون میخوره»).
      if(DrawStripOpBarAt(mx, my))
      {
      //--- P-UI-113d: the bar owns the view while held
         ChartViewLockAcquire();   // P-UI-113d: the bar owns the view while held
         s_dsOpGrab = true;
         s_dsOpMs = 0;
         if(DrawStripOpDragTo(mx)) DrawStripPaint();   // a tap ON the bar sets it
         return;
      }
      //--- P-DRAW-50: the PAGE SEATS come before the scrub — a seat is a
      //--- one-shot step, not a colour cell, and a scrub started on one would
      //--- read the cell under it and paint a colour nobody pressed.
      int pgk=DrawStripPageAt(mx,my);
      if(pgk >= 0)
      {
         DrawStripPageStep(pgk);
         return;
      }
      //--- P-DRAW-64: THE PALETTE SCRUB — a press on a colour cell previews while
      //--- the hand drags (the release applies). Asked AFTER the bar (the bar owns
      //--- its own row) and BEFORE the carries, so a press on a swatch is never a
      //--- carry of the board it sits on.
      int palCell = -1;
      if(DrawStripPalHit(mx, my, palCell))
      {
         ChartViewLockAcquire();   // P-UI-113d: the scrub owns the view while held
         s_dsPalGrab = true;
         s_dsPalMs = 0;
         s_dsPalCell = -1;
         DrawStripPalMembers();
         DrawStripPalTo(palCell);
         return;
      }
      int which = DrawStripGripWhich(mx, my);
      if(which != 0)
      {
         if(!s_dsGripLive && !s_dsGGripLive) ChartViewLockAcquire();   // P-UI-113d: the carry owns the view
         if(which == 2)
         {
            s_dsGGripLive = true;
            s_dsGGripDX = mx - s_dsGEX;
            s_dsGGripDY = my - s_dsGEY;
         }
         else if(which == 3)
         {
            // P-DRAW-48: the board's own header — its offset is off ITS origin,
            // so the card follows the hand and the strip stays where it was put.
            s_dsBGripLive = true;
            s_dsBGripDX = mx - s_dsBX;
            s_dsBGripDY = my - s_dsBY;
         }
         else
         {
            s_dsGripLive = true;
            s_dsGripDX = mx - s_dsX;
            s_dsGripDY = my - s_dsY;
         }
      }
   }
   if(!left)
   {
      //--- P-DRAW-64: the scrub's own release — it applies (or cancels) FIRST, then
      //--- the one ender hands the view back (the flag is still its to clear).
      if(s_dsPalGrab) DrawStripPalRelease(mx, my);
      DrawStripGripRelease();
      return;
   }
   //--- P-DRAW-48: the bar's own carry — the value follows the hand and the view is
   //--- asserted every step, so the chart behind the board cannot take the scroll
   //--- back mid-drag (A-09/G-07). One paint per real change, on the carry's cadence.
   if(s_dsOpGrab)
   {
      ChartViewLockAssert();
      uint nowOp = GetTickCount();
      if(nowOp - s_dsOpMs < DSTRIP_GRIP_MS) return;
      s_dsOpMs = nowOp;
      if(DrawStripOpDragTo(mx)) DrawStripPaint();
      return;
   }
   //--- P-DRAW-64: the scrub's hold — the hit test on the carry's cadence, the
   //--- re-ink only when the CELL really changed (see the note on the state block).
   if(s_dsPalGrab)
   {
      ChartViewLockAssert();
      uint nowPal = GetTickCount();
      if(nowPal - s_dsPalMs < DSTRIP_GRIP_MS) return;
      s_dsPalMs = nowPal;
      int cell = -1;
      DrawStripPalTo(DrawStripPalHit(mx, my, cell) ? cell : -1);
      return;
   }
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   int gm = 4 + DSTRIP_SKIN_M;   // P-DRAW-29: the carried skin stays on screen
   //--- P-DRAW-32: the PANEL's own carry — its offset is off its own origin, so the
   //--- plate follows the hand exactly and the strip stays where it was put.
   if(s_dsGGripLive)
   {
      ChartViewLockAssert();
      uint nowG = GetTickCount();
      if(nowG - s_dsGGripMs < DSTRIP_GRIP_MS) return;
      s_dsGGripMs = nowG;
      int gx2 = mx - s_dsGGripDX, gy2 = my - s_dsGGripDY;
      if(gx2 < gm) gx2 = gm;
      if(gy2 < gm) gy2 = gm;
      if(gx2 > cw - s_dsGearW0 - gm) gx2 = cw - s_dsGearW0 - gm;
      if(gy2 > ch - s_dsGearH - gm) gy2 = ch - s_dsGearH - gm;
      if(gx2 == s_dsGEX && gy2 == s_dsGEY) return;
      s_dsGEX = gx2; s_dsGEY = gy2;
      s_dsGearManual = true;   // the hand placed the panel: keep its spot
      DrawStripPaint();
      return;
   }
   //--- P-DRAW-48: THE BOARD's carry (its header), before the strip's.
   if(s_dsBGripLive)
   {
      ChartViewLockAssert();
      uint nowB = GetTickCount();
      if(nowB - s_dsBGripMs < DSTRIP_GRIP_MS) return;
      s_dsBGripMs = nowB;
      int bx2 = mx - s_dsBGripDX, by2 = my - s_dsBGripDY;
      if(bx2 < gm) bx2 = gm;
      if(by2 < gm) by2 = gm;
      if(bx2 > cw - s_dsBW - gm) bx2 = cw - s_dsBW - gm;
      if(by2 > ch - s_dsBH - gm) by2 = ch - s_dsBH - gm;
      if(bx2 == s_dsBX && by2 == s_dsBY) return;
      s_dsBX = bx2; s_dsBY = by2;
      // The hand placed it: that spot IS the undocked state (the reference's pin).
      s_dsBManual = true;
      s_dsBDock = false;
      DrawStripPaint();
      return;
   }
   if(!s_dsGripLive) return;
   ChartViewLockAssert();   // P-BK-14: a third writer (a panel closing, a template reset) can
                            // flip the props back while the button is still down
   uint now = GetTickCount();
   if(now - s_dsGripMs < DSTRIP_GRIP_MS) return;
   s_dsGripMs = now;
   int nx = mx - s_dsGripDX, ny = my - s_dsGripDY;
   if(nx < gm) nx = gm;
   if(ny < gm) ny = gm;
   if(nx > cw - s_dsW - gm) nx = cw - s_dsW - gm;
   if(ny > ch - s_dsH - gm) ny = ch - s_dsH - gm;
   if(nx == s_dsX && ny == s_dsY) return;
   s_dsX = nx; s_dsY = ny;
   DrawStripHomeSet(s_dsX, s_dsY);   // P-DRAW-41: the hand just moved the home
   // P-DRAW-48: a DOCKED board follows its strip; a floated one stays where the
   // hand left it (that is the pin's own meaning).
   if(DrawStripIsColorSlot(s_dsPicker) && !s_dsBManual) DrawStripBoardPlace();
   DrawStripPaint();
}


// ══════════════════════════════════════════════════════════════════════════
// P-UI-113 (2026-09-23) — LEFT-HOLD OPENS THE STRIP. User order: «مدیریت کلیک
// راست ولش کن همون هولد با کلیک چپ باشه بهتره». One hold language with the
// boxes (BkHold*): a 500 ms still LEFT press on one of the user's own drawings
// opens the strip on it; a drag never opens, a release never opens (the fire
// happens mid-hold, then disarms, so the release that follows opens nothing).
// The release that ENDS the opening hold is swallowed for the whole press cycle
// (`s_dsOpenerUntil` below) or the TV-style outside-click dismissal would close
// what just opened (the P-DRAW-08k/08j guard, retired with right-click, reborn
// here as P-UI-113c).
// Zero-move presses emit no MOUSE_MOVE (P-LM-13), so DrawStripHoldPoll backs
// the move path from RefreshKitOnBar, beside BkHoldPoll/CpHoldPoll.
#define DSTRIP_HOLD_MS   500
#define DSTRIP_HOLD_MOVE 8
#define DSTRIP_HOLD_TTL  5000
static uint   s_dsHoldMs = 0;
static int    s_dsHoldX = 0, s_dsHoldY = 0;
static string s_dsHoldObj = "";
static bool   s_dsHoldDown = false;
//--- P-UI-115c (2026-09-29) — THE RELEASE IS A WINDOW FOR THE HOLD'S OWN END TOO.
//--- The opener's release has been a WINDOW since P-UI-113c; the hold's end still
//--- treated every click-family event as the release itself. Measured on the live
//--- chart (EURUSD,M1 18:38:20.170-21.089, one drawing, one pixel): four
//--- `hold latch at 391,158 hit="THLevels_HRAY_380119684538"` in 919 ms — gaps
//--- 179/252/488 ms — and only the 517 ms one reached `hold opened`. The terminal's
//--- own button bit flaps mid-press (first measured by P-UI-113j), so a CLICK arrives
//--- WHILE the hand is still down; the tail cleared the latch AND the press cycle on
//--- each one, and the next flap re-latched — which RESTARTED the 500 ms clock. No
//--- hand keeps every gap over 500 ms, so the strip opened by luck. A release is now
//--- stamped here and PROVEN by the window (`DSTRIP_OPEN_TAIL_MS`); the poll resolves
//--- the real one, and `DrawStripHoldLatch` refuses to re-time a press it already
//--- named at the same point.
static uint   s_dsHoldOffMs = 0;   // tick a release was SEEN at (0 = none)
//--- P-UI-130 (2026-10-02) — A DRAWING THE TERMINAL IS MOVING IS NEVER HELD.
//--- The user's second report, in one sentence: «موقعی که باکس جابجا میکنم یا
//--- ریساز میکنم نوار استریپ بالا میاد و مزاحم میشه». The press that STARTS a drag
//--- is a press on the drawing, so it arms the latch exactly like a hold does, and
//--- the 500 ms clock knows nothing about where the hand is going: the strip came
//--- up ON the drawing the user was about to move — and (P-UI-113f) left it
//--- natively selected while the anchors were being aimed at.
//---
//--- The witness is the terminal's OWN voice and this module already listens to
//--- it: CHARTEVENT_OBJECT_DRAG is fired for the user's gesture only (P-DRAW-64's
//--- interior rides it), it is the SAME trait P-BK-19a made the base box's owner
//--- (`BK_DRAG_OWNER_MS`: «a native drag announces itself with CHARTEVENT_OBJECT_DRAG
//--- this soon after the press»), and TH3Tool_C's band lock measured the resize
//--- half of it («MT4 fires CHARTEVENT_OBJECT_DRAG continuously while the user
//--- resizes the committed band»). So: the drag KILLS a live latch outright and
//--- FORBIDS the next one for as long as its own heartbeat keeps speaking.
//---
//--- The window is a HEARTBEAT, not a guess — the same shape as the band lock's
//--- `s_bandDragMs`. Events keep arriving while the object moves, so the window
//--- renews itself for exactly as long as the hand is moving the drawing, and
//--- past it the hand is at rest again (400 ms of silence = the drag is over).
//--- This is the protection the shortened press cycle (DSTRIP_PRESS_CYCLE_MS)
//--- traded away, and it is the honest swap: a PRESS is guarded by the press, a
//--- GESTURE IN MOTION by the motion.
#define DSTRIP_DRAG_HOLD_OFF_MS 400   // the drag heartbeat's own silence window
static uint   s_dsDragMs  = 0;         // last OBJECT_DRAG seen (the terminal's voice)
static string s_dsDragObj = "";        // the object it named
bool DrawStripDragLive()
{ return (s_dsDragMs != 0 && GetTickCount() - s_dsDragMs < DSTRIP_DRAG_HOLD_OFF_MS); }
//--- Called from the router's own OBJECT_DRAG branch, ABOVE every guard below (a
//--- drag with the strip OPEN still stamps: the strip may have to know the hand is
//--- on a drawing under it). Killing a latch costs two compares when none is live;
//--- the cycle goes with it because a press that has MOVED a drawing can never
//--- become a hold — the same law P-UI-113d wrote for the release (`relWasDrag`),
//--- applied at the moment the fact is measured instead of at the end of the press.
void DrawStripDragWitness(const string nm)
{
   s_dsDragMs  = GetTickCount();
   s_dsDragObj = nm;
   if(s_dsOpen) return;                       // an open strip owns no hold
   if(s_dsHoldMs == 0 && s_dsHoldObj == "") return;
   Print("[drawstrip] hold cancelled: native drag obj=\"", nm, "\"");
   s_dsHoldMs = 0; s_dsHoldObj = ""; s_dsHoldOffMs = 0;
   DrawStripPressCycleClear();   // proved a drag: this press may never become a hold
}
//--- P-UI-113c (2026-09-23) — THE OPENING PRESS OWNS ITS OWN CLICK-FAMILY EVENTS.
//--- Reported: «چرا با رها کردن هولد استریپ هم بسته میشه». The hold fires while the
//--- button is STILL DOWN, so the release that ends it lands on the drawing = the
//--- user's own click, and the outside-click dismissal read it as "clicked away" and
//--- closed the strip the hold had just shown: on with the press, gone on the release.
//--- A ONE-SHOT FLAG CANNOT FIX IT, and that is why this is a WINDOW: one physical
//--- release is reported on more than one channel (the chart's CHARTEVENT_CLICK and
//--- the object's CHARTEVENT_OBJECT_CLICK) and a one-shot spends the first while the
//--- second dismisses the strip. So the guard is armed for the PRESS CYCLE and
//--- re-armed by the press's own witnesses: ARM at the fire for
//--- DSTRIP_OPEN_PRESS_MAX_MS; the MOVE STREAM's release witness shortens it to
//--- DSTRIP_OPEN_TAIL_MS (the twin-event tail); a new press edge, a close or the TTL
//--- ends it. The state and its owners are in the file's state block above — the only
//--- place both sides can see.
void DrawStripHoldLatch(const int mx, const int my)
{
   uint now = GetTickCount();
   //--- P-UI-130: THE TERMINAL IS MOVING A DRAWING — the hand is not holding. FIRST
   //--- because it is one compare, and first because every fence BELOW has already
   //--- stamped a clock by the time it returns: a refusal here never leaves a live
   //--- latch for the poll to fire on (the trap `DrawStripHoldForget` used to keep).
   if(DrawStripDragLive())
   {
      if(!s_dsOpen) Print("[drawstrip] latch blocked: native drag obj=\"", s_dsDragObj, "\"");
      return;
   }
   string named = DrawObjectAtCached(mx, my);   // the one hit test this latch pays for
   //--- P-UI-115c — A FLAP IS NOT A NEW PRESS (P-UI-113j's own law: a press we
   //--- already NAMED is not a new gesture). Same drawing, same press point, a live
   //--- clock: the flap the log above measures. Re-arming the clock there is what made
   //--- the strip open only on the lucky gap, so it keeps the one it has.
   bool samePress = (s_dsHoldMs != 0 && s_dsHoldObj != "" && s_dsHoldObj == named &&
                     MathAbs(mx - s_dsHoldX) <= DSTRIP_HOLD_MOVE &&
                     MathAbs(my - s_dsHoldY) <= DSTRIP_HOLD_MOVE &&
                     (now - s_dsHoldMs) < DSTRIP_HOLD_TTL);
   s_dsHoldDown = true;
   if(!samePress) { s_dsHoldMs = now; s_dsHoldX = mx; s_dsHoldY = my; }
   s_dsHoldObj = "";
   DrawStripOpenerDisarm();   // P-UI-113c: a latch is a press cycle of its OWN
   //--- DIAG-116 (temporary, P-UI-115b). These seven fences return SILENTLY, so
   //--- a press they swallow leaves no line anywhere: the 2026-09-29 log has NO
   //--- `hold latch` at all after the 13:35 reload, and a line that is never
   //--- printed cannot say WHICH fence did it (or whether the edge ever came).
   //--- Each fence now names itself, only while the strip is shut - i.e. exactly
   //--- the state a hold opens from, and one line per press. Remove with DIAG-113.
   if(BaseKnotSessionActive()) { if(!s_dsOpen) Print("[drawstrip] latch blocked: baseknot session"); return; }
   if(UIPeekClickClaim())      { if(!s_dsOpen) Print("[drawstrip] latch blocked: ui peek claim"); return; }
   if(UIPointerOverSurface(mx, my)) { if(!s_dsOpen) Print("[drawstrip] latch blocked: ui pointer over surface at ", mx, ",", my); return; }
   if(BaseKnotViewOwned())     { if(!s_dsOpen) Print("[drawstrip] latch blocked: baseknot view owned"); return; }
   if(TH3SessionActive() || TH3BaseMarkArmed()) { if(!s_dsOpen) Print("[drawstrip] latch blocked: th3 session"); return; }
   if(LegMeasureSessionActive()) { if(!s_dsOpen) Print("[drawstrip] latch blocked: leg measure session"); return; }
   if(g_waitingForCustomPriceClick) { if(!s_dsOpen) Print("[drawstrip] latch blocked: waiting for custom price click"); return; }
   // P-UI-113j: NAME THE PRESS'S OWN DRAWING - and name it even while the strip is
   // OPEN, because the release that follows belongs to the same press and the
   // terminal's selected controls are not part of any drawn body. Cost: the one
   // hit test this latch already pays for on a press edge (P-DRAW-04), memoised;
   // the guards above stay first so a session that owns the mouse pays nothing.
   s_dsPressX = mx; s_dsPressY = my; s_dsTravel = 0; s_dsPressTracked = true;
   s_dsHoldObj = named;
   // P-UI-115: THE CYCLE BELONGS TO A PRESS THAT NAMED A DRAWING. It was armed
   // unconditionally, so the poll's own latch at the never-moved cursor (the
   // 2026-09-29 log's `hold latch at 0,0 hit="" lbtn=1`, 11 ms after attach)
   // owned the 10 s window with nothing under it and swallowed every real press
   // that followed. A press on empty chart names nothing, and it has nothing to
   // open — it must not spend the gesture budget of the press after it.
   if(s_dsHoldObj != "") DrawStripPressCycleSet(s_dsHoldObj);
   if(s_dsOpen) return;   // an open strip owns no hold - the press is only NAMED
   // DIAG-113 (temporary): one line per hold latch so the log proves whether the
   // press reached us, what the hit test saw, and what the live probe reads.
   Print("[drawstrip] hold latch at ", mx, ",", my, " hit=\"", s_dsHoldObj,
         "\" lbtn=", (UILeftButtonDown() ? 1 : 0));
}
//--- P-UI-130: A DROPPED LATCH IS NOT A GESTURE. This was ONE store (`s_dsHoldObj =
//--- ""`) and left the CLOCK running, so `DrawStripHoldGestureLive()` read a latch the
//--- position test had already dropped as LIVE at the release — and the release then
//--- stamped a window instead of clearing the press cycle, which is how a refusal
//--- outlived a release that DID arrive. The clock is the latch's own; when the
//--- latch is forgotten the clock goes with it. `s_dsHoldDown` deliberately stays:
//--- the hand may still be down, and the poll's zero-move latch must not re-arm on it.
void DrawStripHoldForget() { s_dsHoldMs = 0; s_dsHoldObj = ""; }
void DrawStripHoldClear() { s_dsHoldMs = 0; s_dsHoldObj = ""; s_dsHoldDown = false; s_dsHoldOffMs = 0; }
//--- P-UI-115c: is a latch live and young enough that a click-family event may only
//--- be a release SEEN, never its PROOF? (The window in the poll decides.)
bool DrawStripHoldGestureLive()
{
   return (s_dsHoldMs != 0 && !s_dsOpen && (GetTickCount() - s_dsHoldMs) < DSTRIP_HOLD_TTL);
}
//--- P-UI-113f (2026-09-24): THE HOLD LEAVES THE DRAWING NATIVELY SELECTED.
//---
//--- The strip's rectangle hit test deliberately owns a hollow box's INTERIOR
//--- (P-DRAW-08g), while MT4's own hit test sees only the drawn border. Therefore
//--- a hold can open the strip on a box that the terminal never selected; the
//--- release is then an empty-chart click and the eight resize anchors / native
//--- settings never appear. The user order is the terminal's own object model, not
//--- a second selection: a successful hold must leave an unlocked user drawing
//--- selected, so MT4 keeps its anchors, right-click properties and resize handles.
//---
//--- This is deliberately NOT a SELECTABLE write. Lock stays the lock, and an
//--- already-selected drawing pays no object write. The release reasserts the same
//--- fact because MT4 can clear selection immediately before reporting the click;
//--- the opening-press window bounds that repair to this exact gesture.
bool DrawStripHoldSelect()
{
   string nm = s_dsObj;
   if(nm == "" || ObjectFind(0, nm) < 0) return false;
   if(DrawKindOf(nm) == DK_NONE) return false;
   if(DrawIsHRay(nm)) return true;   // P-HR-04: the dot IS the selection — nothing to assert
   if(DrawIsIndicatorObject(nm)) return false;
   if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTABLE)) return false;
   if((bool)ObjectGetInteger(0, nm, OBJPROP_SELECTED)) return true;
   return ObjectSetInteger(0, nm, OBJPROP_SELECTED, true);
}
//--- P-UI-113g: arm the post-callback repair. Fire arms it too because MT4 may
//--- clear the selection before the physical release even arrives; every opening
//--- release re-arms the short window with a fresh post-event deadline.
void DrawStripHoldSelectArm()
{
   if(s_dsObj == "") return;
   uint now = GetTickCount();
   s_dsSelectRepairName = s_dsObj;
   s_dsSelectRepairAt = now + DSTRIP_SELECT_REPAIR_DELAY_MS;
   s_dsSelectRepairUntil = now + DSTRIP_SELECT_REPAIR_TTL_MS;
}
void DrawStripHoldSelectPoll()
{
   if(s_dsSelectRepairUntil == 0) return;
   uint now = GetTickCount();
   if(!TickDeadlinePending(s_dsSelectRepairUntil)) { DrawStripHoldSelectionDisarm(); return; }
   if(!TickDeadlinePending(s_dsSelectRepairAt)) return;   // still inside the release callback/tail
   if(!s_dsOpen || s_dsObj == "" || s_dsSelectRepairName != s_dsObj)
   { DrawStripHoldSelectionDisarm(); return; }

   bool wasSelected = (ObjectFind(0, s_dsObj) >= 0 &&
                       (bool)ObjectGetInteger(0, s_dsObj, OBJPROP_SELECTED));
   if(!DrawStripHoldSelect()) { DrawStripHoldSelectionDisarm(); return; }
   if(!wasSelected)
   {
      ChartRedraw();
      Print("[drawstrip] native selection repaired after release obj=\"", s_dsObj, "\"");
   }
   // Keep the guarded read alive until the short TTL: the timer is the proof that
   // MT4's delayed click state has committed. It never owns selection afterwards.
}
void DrawStripHoldFire()
{
   string hit = s_dsHoldObj;
   int hx = s_dsHoldX, hy = s_dsHoldY;
   s_dsHoldMs = 0; s_dsHoldObj = "";
   if(hit == "" || s_dsOpen) return;
   if(!DrawStripOpenAt(hit, hx, hy)) return;
   // P-HR-06: the dot IS the ray's selection — no native flag to assert and no
   // repair poll to arm (that poll would redraw + log on every ray open).
   if(!DrawIsHRay(hit))
   {
      DrawStripHoldSelect();     // P-UI-113f: native anchors/settings survive the hold
      DrawStripHoldSelectArm();  // P-UI-113g: prove it again after MT4 commits the release
   }
   DrawStripOpenerArm();   // P-UI-113c: the press that opened it owns its own clicks
   Print("[drawstrip] hold opened on \"", hit, "\" selected=",
         (bool)ObjectGetInteger(0, hit, OBJPROP_SELECTED));
}
void DrawStripHoldStep(const int mx, const int my, const bool leftDown, const bool pressStart)
{
   // P-UI-113j: a press we already NAMED is not a new gesture. The terminal's own
   // object machinery flaps the button bit mid-press (a selected drawing's native
   // drag), and re-latching there restarted the 500 ms clock every time it did.
   if(pressStart)
   {
      //--- P-UI-115c: a down-frame IS the hand — the release that arrived before it was
      //--- the flap, and the window it opened has no say any more.
      s_dsHoldOffMs = 0;
      if(!DrawStripPressCycleLive()) DrawStripHoldLatch(mx, my);
      //--- DIAG-116 (temporary): the edge ARRIVED and the cycle refused it. This is
      //--- the ONE case a missing `hold latch` line cannot be told apart from a dead
      //--- edge, and the cycle's own owner is the press before this one.
      else if(!s_dsOpen) Print("[drawstrip] press refused: cycle live obj=\"", s_dsPressCycleObj, "\"");
      return;
   }
   //--- P-UI-115b (2026-09-29) — A NON-EVENT WITNESS MAY NOT END A LIVE GESTURE.
   //--- P-UI-115's first half removed the fence that skipped the click-family
   //--- release, so the tail below (7570 `DrawStripPressCycleClear`, 7578
   //--- `DrawStripHoldClear`) now runs on every real release — and THIS term,
   //--- added in the same hour on the belief that the tail was unreachable, is
   //--- what is left killing the gesture: the terminal's button bit FLAPS
   //--- mid-press (P-UI-113j's own measurement, on a selected drawing's native
   //--- drag), and one up frame cleared the latch and the cycle together, so the
   //--- 500 ms clock never reached 500 ms and `hold opened` never printed. It is
   //--- the same law P-UI-83 wrote for the panel: no non-event witness may end a
   //--- gesture whose event channel is still delivering down-readings. The tap it
   //--- was meant to protect is the click-family release's own `DrawStripHoldClear`
   //--- (the note above the branch states exactly that), and the TTL bounds what
   //--- neither channel reports. Cost: the up frame is two compares and no write.
   if(s_dsHoldMs == 0 || s_dsHoldObj == "") return;
   //--- P-UI-130: THE TERMINAL'S OWN DRAG ENDS THE HOLD. A press that has MOVED the
   //--- drawing is a drag however few pixels it travelled, and the strip may not come
   //--- up mid-gesture over the thing the user is moving. (The witness has almost
   //--- always killed the latch before this line can see it — it stands as the
   //--- second reader of the same fact, so the fire can never outrun the drag.)
   if(DrawStripDragLive())
   {
      if(!s_dsOpen) Print("[drawstrip] hold dropped: native drag obj=\"", s_dsDragObj, "\"");
      DrawStripHoldForget(); return;
   }
   //--- P-UI-115c: inside the release's window a SEEN release may be the flap, so the
   //--- move path may not FIRE it — and it is not the move path's to end either (the
   //--- poll resolves the real one). One unsigned read on a live latch.
   if(s_dsHoldOffMs != 0 && GetTickCount() - s_dsHoldOffMs <= DSTRIP_OPEN_TAIL_MS) return;
   if(MathAbs(mx - s_dsHoldX) > DSTRIP_HOLD_MOVE || MathAbs(my - s_dsHoldY) > DSTRIP_HOLD_MOVE)
   {
      //--- DIAG-116 (temporary): the hand left the press point, so the gesture is a
      //--- drag and NOT a hold. One line per gesture; without it this exit is the
      //--- same silence as a press that never arrived.
      if(!s_dsOpen) Print("[drawstrip] hold dropped: moved from ", s_dsHoldX, ",", s_dsHoldY,
                          " to ", mx, ",", my, " obj=\"", s_dsHoldObj, "\"");
      DrawStripHoldForget(); return;
   }
   if(GetTickCount() - s_dsHoldMs >= DSTRIP_HOLD_MS) DrawStripHoldFire();
}
//--- P-UI-113: the POLL half rides a cursor it is GIVEN (DrawStripHoldPollAt,
//--- from RefreshKitOnBar) because the zero-move cursor (g_LastUIX/g_LastUIY)
//--- is declared in BiotakPanels.mqh, after this file. Same guards, same fire.
//---
//--- AND IT NEVER ENDS A HOLD BY ITSELF (P-UI-113b, 2026-09-23). The KEYSTATE
//--- probe it is handed does not answer "is the left mouse button down?" on this
//--- terminal: MQL4's `TERMINAL_KEYSTATE_LEFT` is the LEFT ARROW key, and the log
//--- proves the reading — every `[drawstrip] hold latch` line of the 20:17
//--- session prints `lbtn=0` while the mouse stream's own bit says the button is
//--- DOWN. Clearing on that reading killed every latch inside one 250 ms pass,
//--- i.e. before the 500 ms it needed to fire, so the hold could not open
//--- anything on ANY surface no matter how long the hand stayed still.
//--- The boxes' own law (P-BK-05) is the answer, worn here unchanged: the probe
//--- may only detect a down-transition when NOTHING is latched, never clear or
//--- re-time a live latch. A release is witnessed by the terminal's own button-up
//--- channels, which end the latch in the router below.
void DrawStripHoldPollAt(const int mx, const int my, const bool leftDown)
{
   if(s_dsHoldMs == 0)
   {
      // The zero-move press's backup latch, the box hold's own shape: nothing
      // latched, no press tracked, and the probe says the button is down.
      if(!s_dsHoldDown && !s_dsOpen && !DrawStripPressCycleLive() && leftDown) DrawStripHoldLatch(mx, my);
      else if(s_dsHoldDown && !leftDown) s_dsHoldDown = false;   // expire a stuck flag
      return;
   }
   uint now = GetTickCount();
   //--- P-UI-115c: THE RELEASE'S OWN WINDOW. A release SEEN inside `DSTRIP_OPEN_TAIL_MS`
   //--- may still be the hand's own press (the flap measured above), so it neither fires
   //--- nor ends the hold; past the window the hand let go and the gesture is over — the
   //--- tap case the tail's clear protects, resolved here because the KEYSTATE probe
   //--- cannot answer and the move stream never reports the missing down-frame.
   if(s_dsHoldOffMs != 0)
   {
      if(now - s_dsHoldOffMs <= DSTRIP_OPEN_TAIL_MS) return;
      DrawStripHoldClear(); DrawStripPressCycleClear(); return;
   }
   //--- P-UI-130: AND THE CYCLE GOES WITH IT. This branch is the "the press is over"
   //--- backstop, and it used to end the HOLD only — leaving the press cycle to run
   //--- down its own cap and refuse every press inside it, with no latch left alive
   //--- for any reader to explain why (the log's refusals all name an object that no
   //--- live latch owns). One fact, one clear.
   if(now - s_dsHoldMs > DSTRIP_HOLD_TTL) { DrawStripHoldClear(); DrawStripPressCycleClear(); return; }
   if(s_dsHoldObj == "" || s_dsOpen) return;
   //--- P-UI-130: and the POLL is the path that fires a hold the move stream never
   //--- saw (a motionless press emits no MOUSE_MOVE, P-LM-13) — which is exactly the
   //--- path a drag could not otherwise close: with the finger still and the object
   //--- under it, every other witness is quiet. The heartbeat is not.
   if(DrawStripDragLive())
   {
      if(!s_dsOpen) Print("[drawstrip] hold dropped: native drag obj=\"", s_dsDragObj, "\"");
      DrawStripHoldForget(); return;
   }
   if(now - s_dsHoldMs < DSTRIP_HOLD_MS) return;
   if(MathAbs(mx - s_dsHoldX) > DSTRIP_HOLD_MOVE || MathAbs(my - s_dsHoldY) > DSTRIP_HOLD_MOVE)
   { DrawStripHoldForget(); return; }
   if(DrawObjectAtCached(mx, my) != s_dsHoldObj)
   {
      //--- DIAG-116 (temporary): the cursor is on the same pixel the hold latched,
      //--- but the hit test now names something else (or nothing) - the one silent
      //--- exit between a live latch and its fire.
      if(!s_dsOpen) Print("[drawstrip] hold dropped: hit changed at ", mx, ",", my,
                          " was=\"", s_dsHoldObj, "\" now=\"", DrawObjectAtCached(mx, my), "\"");
      DrawStripHoldForget(); return;
   }
   DrawStripHoldFire();
}

//--- P-UI-113i (2026-09-24): RELEASE OWNERSHIP IS GEOMETRY, NOT SELECTION STATE.
//--- User proof: the same left release works while the drawing is unselected and
//--- closes the strip while that drawing is selected. The old dismissal asked
//--- only whether the release pixel was on the drawn body; MT4's selected controls
//--- are terminal UI, not the object, so a release there read as outside. The
//--- robust contract is wider: a release belongs to the strip's drawing when the
//--- PRESS already named that drawing, OR when the release pixel still resolves to
//--- it through the same body/control hit test. Selected or not is therefore not a
//--- branch: both states feed this one owner and produce the same answer.
bool DrawStripReleaseOnDrawing(const string pressedName, const int px, const int py)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   if(pressedName != "" && pressedName == s_dsObj) return true;
   // A motionless press emitted no move edge to clear the gesture memo. At the
   // release there is no earlier answer worth trusting, so this fallback takes a
   // live hit test instead of inheriting the same pixel's last 400 ms owner.
   DrawHitCacheClear();
   return (DrawObjectAtCached(px, py) == s_dsObj);
}

//--- THE EVENT ROUTER. Called from the entry's OnChartEvent tail (Full only):
//--- it sees the button clicks the terminal reports and the clicks that land
//--- anywhere else (which dismiss the strip, TV-style).
bool DrawStripOnEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // P-UI-113d: the button-up's OWN fact, measured once in the click head below
   // and read by the dismissal at the tail of this one call (the two halves are
   // one invocation, so this is a local, not state).
   bool relWasDrag = false;
   string relPressObj = "";   // P-UI-113i: this button-up's own press owner
   //--- P-DRAW-64 addendum 5 (2026-09-27) — THE INTERIOR'S STEP IS NOT THE STRIP'S.
   //--- This witness stands ABOVE EVERY GUARD below, because the split belongs to
   //--- the DRAWING: with the strip shut, the old placement sat two hundred lines
   //--- further down and returned first, so a box dragged then kept its pre-drag
   //--- interior until the pump's 2 s pass («این باکس هنوز همین طوریه … اون fill
   //--- ریل تایم همراه جابجا نمیشه»), and the terminal's own properties dialog fires
   //--- no drag event at all. Cost per witness: 1-2 compares for a line or any other
   //--- kind, ~12 guarded reads for a user FILLER kind, a write only on a real move.
   if((id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE) && sparam != "")
   {
      //--- P-UI-130: THE DRAWING IS MOVING, SO NOTHING MAY BE HELD ON IT. Only the
      //--- DRAG channel is the hand (OBJECT_CHANGE is the properties dialog: a still
      //--- hand, no gesture in flight to end).
      if(id == CHARTEVENT_OBJECT_DRAG) DrawStripDragWitness(sparam);
      //--- P-DRAW-64 addendum 6: the drag event stamps, and it ARMS the move memo, so
      //--- a frame the terminal coalesces away is still covered by the hand's own stream.
      FillChildStampArm(sparam);
      FillChildSync(sparam);
      //--- P-DRAW-64d (2026-09-27): THE LEVEL RIDES THE SAME EVENT. The mid line's own
      //--- sync sat two hundred lines down, BELOW the shut-strip guard — so a box dragged
      //--- with the strip shut kept its pre-drag level until the pump's 2 s pass (the
      //--- stuck dotted line in the user's screenshot: «این خط 50 درصد چند فریم عقب زمانی
      //--- که باکس و جابجا میکنم»). It stands here now, beside the interior, UNTHROTTLED:
      //--- the moves below are guarded, so a still frame is reads and never a repaint,
      //--- and the hand's own cadence IS the cadence (the realtime law — a 50 ms cap on
      //--- a hairline is three frames the user explicitly refused). The pump stays the
      //--- net for gestures that fire no event at all.
      BoxMidSync(sparam);
   }
   // P-DRAW-17: the left button's press edge and travel, on EVERY move — the
   // trigger needs them while the strip is CLOSED, the grip carry needs the edge
   // while it is OPEN. Computed once here, read by both.
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int tmx = (int)lparam, tmy = (int)dparam;
      int mstate = (int)StringToInteger(sparam);
      bool tleft = ((mstate & 1) != 0);
      // P-UI-113b (2026-09-23) — THE PRESS EDGE IS A STORE, NOT A COMPARISON.
      //
      // The P-UI-114 sweep moved the edge's computation out of `DrawStripGripMove`
      // (which stored `s_dsLeftPrev = left;` at its tail) into this head and left
      // the store behind, so `s_dsLeftPress` WAS `tleft`: every move under a held
      // button read as a fresh press. Measured on the live chart (EURUSD,H1,
      // 20:17:21-25): one press on `Rectangle 664` produced eight `[drawstrip]
      // hold latch` lines in 4.7 s, because the hold's latch — and `s_dsHoldMs`
      // with it — was re-armed on every one of them, so the 500 ms clock kept
      // restarting and `hold opened` never printed once. The grip carry's own
      // press edge was equally false. One store per move is the whole fix.
      s_dsLeftPress = (tleft && !s_dsLeftPrev);
      s_dsLeftPrev = tleft;
      if(s_dsLeftPress)
      {
         //--- DIAG-116 (temporary): THE EDGE ITSELF. Every witness downstream prints
         //--- only once the press reached IT, so a press that dies before the latch
         //--- is invisible by construction - and that is the whole state of the
         //--- 2026-09-29 log after the 13:35 reload (no line of any kind). Gated to
         //--- the shut strip: a hold only opens from there, and an open strip's
         //--- presses are the panel's own. One line per press edge.
         if(!s_dsOpen) Print("[drawstrip] press edge at ", tmx, ",", tmy, " bit=", (tleft ? 1 : 0));
         // P-UI-113j: the LATCH already named this press (a still press takes its
         // edge from the poll, and a flapping bit re-reports ONE press as many).
         // Its owner, its press point and the opening window survive untouched -
         // re-declaring them here is what let a mid-press flap kill the window.
         if(!DrawStripPressCycleLive())
         {
             s_dsPressX = tmx; s_dsPressY = tmy; s_dsTravel = 0;
             s_dsPressTracked = true;   // P-UI-113d: this cycle's travel is a fact we own
             //--- P-DRAW-102: A NEW PRESS IS NEVER THE PREVIOUS GESTURE'S RELEASE.
             //--- `s_dsGearPressSpent` is armed by the panel's coordinate channel
             //--- below and spent by the release that follows it, and the only other
             //--- places that clear it are the panel's close and the strip's. A press
             //--- on a control whose release the terminal never reported as a click
             //--- (the hand let go outside the chart window) left it armed, and the
             //--- NEXT click on the chart was spent at 682 as a twin release: the
             //--- click the user made to dismiss the strip did nothing, and the one
             //--- after it worked. It is this press's own flag, so a new press edge
             //--- is where it starts again — set below, on the same block.
             s_dsGearPressSpent = false;

            DrawHitCacheClear();   // the hit memo is a GESTURE's, never a session's
            s_dsPressObj = DrawObjectAtCached(tmx, tmy);  // P-UI-113i: own the press
            FillChildStampArm(s_dsPressObj);   // P-DRAW-64 addendum 6: the hand's own ride
            DrawStripOpenerDisarm();   // P-UI-113c: a NEW press is never the old gesture
            DrawStripHoldSelectionDisarm();  // P-UI-113g: nor may the repair fight it
            //--- P-DRAW-84 (2026-09-29) — THE PANEL'S BUTTONS, ON THE PRESS EDGE.
            // Every painter in this file is born OBJPROP_SELECTABLE=false (3317,
            // 3366, 3413, 3444), so MT4 never fires OBJECT_CLICK for a control and
            // the panel's name router (7538+) could not answer a single tab, row,
            // switch or foot button. The cards work because BiotakPanels has
            // P-UI-74's coordinate channel (PnlClickFallback, called at 9488
            // before the name router). This is that channel, on the press edge —
            // which fires for EVERY press, whatever object (or none) is under the
            // cursor, so it is the only place that does not depend on which event
            // MT4 chose. Routed to the SAME *Tap functions the name router calls,
            // so no action logic was duplicated. The panel is a surface of its own
            // (DrawStripPointInside:953), so this press is never a chart press.
            //
            // It does NOT return: this is the middle of the mouse-move block, and
            // an early return here would also cancel the hover, the hold latch and
            // the travel bookkeeping every later branch below this one owns. It
            // only SPENDS the press — the carry, the opener and the hold are
            // disarmed, so the rest of this block finds nothing to do with it.
            //
            //--- P-DRAW-113 (2026-10-01): AND `DrawStripGearSurfaceAt` IS THE OTHER
            //--- HALF OF THAT SENTENCE. `DrawStripGearHit` declines the panel's own
            //--- dead pixels — the tab TRACK between two tabs (Base:399), a cell's
            //--- margins, the plate's own skin margin — and the release below asks
            //--- ONLY this flag, so a press there read as a click on the chart and
            //--- `ObjectsDeleteAll("PnlDrawS_G")` took the head, the tab row and the
            //--- foot with it. MEASURED (H1 10:14:30 `dismiss click at 1126,230`
            //--- against `PLATE tab=1 ... xy=766,148`: 82px down = inside the tab
            //--- buttons, 360px across = the 8px gap between tab 2 and tab 3).
            //--- The panel is a surface of its own, so a press on ANY of its pixels
            //--- is spent here; its head stays out of it, because that band is the
            //--- panel's carry and needs the press left tracked (P-DRAW-85).
            if(s_dsGear != 0 &&
               (DrawStripGearHit(tmx, tmy) || DrawStripGearSurfaceAt(tmx, tmy)))
            {
               s_dsPressTracked = false;        // the panel had it: not a carry
               DrawStripPressCycleClear();
               DrawStripOpenerDisarm();
               DrawStripHoldSelectionDisarm();
               s_dsGearPressSpent = true;       // the release knows the panel had it
            }
         }
      }
      else if(tleft)
      {
         int adx = tmx - s_dsPressX; if(adx < 0) adx = -adx;
         int ady = tmy - s_dsPressY; if(ady < 0) ady = -ady;
         if(adx + ady > s_dsTravel) s_dsTravel = adx + ady;
         //--- P-DRAW-64 addendum 6: under a held button the interior rides the HAND.
         //--- One compare against the memo's four values; a frame that really moved
         //--- pays the guarded sync, a still frame costs four reads and nothing else.
         FillChildStamp(s_dsPressObj);
      }
      else if(s_dsOpenerUntil != 0)
      {
         // P-UI-113c: THE STREAM'S OWN RELEASE WITNESS. The opening press is
         // over, so the guard drops to the twin-event tail: the terminal's other
         // report of this ONE release may still be in flight behind this move.
         s_dsOpenerUntil = 0;
         s_dsOpenerTailUntil = GetTickCount() + DSTRIP_OPEN_TAIL_MS;
      }
       DrawStripHoldStep(tmx, tmy, tleft, s_dsLeftPress);   // P-UI-113: left-hold opens
       if(!tleft) DrawStripColorHoverAt(tmx, tmy);
    }

    // P-DRAW-17: THE OPEN PATH RUNS BEFORE THE GUARD — the guard below says the strip
    // must be open, and the open trigger used to sit under it ("the strip never appears").
    // P-UI-113/113b — the release that ENDS the opening hold belongs to the gesture that
    // opened it, so it is SPENT as a WINDOW (P-UI-113c, `s_dsOpenerUntil`), never as a
    // one-shot: one physical release arrives on CHARTEVENT_CLICK and on the object's
    // OBJECT_CLICK, and spending only the first lets the second dismiss the strip the hold
    // just opened — or, landing on the strip's own cells (it floats 12 px off the cursor),
    // DELETE the drawing. MT4 has exactly two release channels and neither is ever a press,
    // so the hold is ARMED from the mouse stream's own edge and DISARMED here, never by the
    // poll (whose probe cannot answer at all). Clearing on the OBJECT channel is what lets
    // a HOLD reach its 500 ms: a plain tap's release arrives here as OBJECT_CLICK, and
    // without this term the latch stays live and the poll opens the strip on a tap.
     if(id == CHARTEVENT_CLICK || id == CHARTEVENT_OBJECT_CLICK)
     {
         // P-UI-115 (2026-09-29) — THE PROBE MAY NOT GATE THE RELEASE. This read
         // `if(UILeftButtonDown()) return true;` and skipped the WHOLE block below
         // — including the tail that ends the press cycle — whenever the
         // terminal's KEYSTATE probe said "pressed", which on this terminal is
         // every time: the 2026-09-29 log prints `lbtn=1` on all 368
         // `[drawstrip] hold latch` lines, one of them 11 ms after attach when no
         // button can be down. The cycle the tail ends lives
         // `DSTRIP_OPEN_PRESS_MAX_MS` = 10 s, and `DrawStripHoldStep` refuses
         // every press inside it: latch-to-latch spacing in the log is exactly
         // 10 s (`12:53:07 -> :17 -> :27`) and only 36 of 368 latches opened the
         // strip. The fence was also the opposite of the law the comment below
         // states — «a click-family event IS a release on this terminal» — and
         // MT4 emits a click on release only, so the release is not a probe's to
         // guess. The tap protection it was meant to add is the tail's own
         // `DrawStripHoldClear()`, which the fence is what skipped.
         if(UIPeekClickClaim()) return true;
         // P-UI-113c: the opening press cycle owns its own events — all of them.
         bool openerSpent = DrawStripOpenerClickSpent();
       // P-UI-113d: and this is where the BUTTON-UP's own fact is measured — a
       // release whose hand left its press point is the END OF A DRAG (of the
       // drawing, of the plate, or of the chart), never the "clicked away"
       // gesture the TV-style dismissal below is for. Measured HERE because this
       // is also the event that ends the press cycle.
       relWasDrag = (s_dsPressTracked && s_dsTravel > DSTRIP_CLICK_SLOP);
       relPressObj = s_dsPressObj;   // P-UI-113i: keep the press owner for the tail
       // P-UI-113j: ELSE THE LATCH'S OWN OWNER. A still press left no move edge, and
       // the terminal's LIVE selection is not a fact this release may ask: MT4
       // clears it around its own click, and the control the hand is on stops being
       // part of any drawn body at that exact moment.
       if(relPressObj == "") relPressObj = s_dsPressCycleObj;
       //--- P-DRAW-64 addendum 5 (2026-09-27): THE RELEASE RE-STAMPS THE CHILDREN.
       //--- A gesture's LAST drag frame can be coalesced away, and a release is the
       //--- end of every gesture AND names its own object — so this one call is the
       //--- cheap witness that repairs it in the frame the hand lets go, before the
       //--- dismissal below can return. Once per gesture, ~12 guarded reads.
        if(relPressObj != "")
        {
           FillChildSync(relPressObj);
           BoxMidSync(relPressObj);
        }
        FillChildStampRelease();   // P-DRAW-64 addendum 6: the hand let go, so the memo rests

       s_dsPressObj = "";

       s_dsPressTracked = false;
       //--- P-UI-115c: a release SEEN is not a release PROVEN while the latch is live —
       //--- the window in the poll decides, and the cycle is kept with the hold so the
       //--- flap's next down-frame cannot re-time the gesture's clock.
       bool relHoldSeen = DrawStripHoldGestureLive();
       if(relHoldSeen) s_dsHoldOffMs = GetTickCount();
       else            DrawStripPressCycleClear();   // P-UI-113j: this event IS this press's release
       if(openerSpent)
       {
          DrawStripHoldSelect();   // P-UI-113f: the release must not steal the anchors back
          DrawStripHoldSelectArm();  // P-UI-113g: repair it again AFTER the callback
          return true;
       }
       DrawStripHoldSelectionDisarm();  // P-UI-113g: a later click owns selection now
       if(!relHoldSeen) DrawStripHoldClear();   // P-UI-115c: else the window proves it (poll)
       s_dsLeftPrev = false;   // (every release emits one: the boxes' own law, BkHoldOnBoxUp)
    }
    if(id == CHARTEVENT_CLICK && !s_dsOpen) return false;
   if(!s_dsOpen) return false;
     //--- P-DRAW-84: the gear panel's press already acted (7337). This release is
     //--- the SAME gesture on the other channel: it must be spent here, or the
     //--- "clicked away" branch below reads a press on the panel as a press on the
     //--- chart and shuts the panel the user was working in.
     //--- P-DRAW-115 (2026-10-01) — AND THE FLAG'S LIFETIME IS THE GESTURE, NOT THE
     //--- FIRST EVENT THAT SEES IT. `s_dsGearPressSpent = false` stood HERE, and this
     //--- branch is the one place every release passes: MT4 reports ONE release on TWO
     //--- channels (`CHARTEVENT_OBJECT_CLICK` and `CHARTEVENT_CLICK`), so the first one
     //--- consumed the flag and the second found it clear and fell through into the
     //--- dismissal at 951 — where the release pixel is asked `DrawStripPointInside`.
     //--- P-DRAW-84's own arming note (553) says the lifetime is the gesture: the flag
     //--- is armed by the press edge and cleared by the NEXT press edge, by the panel's
     //--- close (DrawStrip_GearB:83) and by the strip's open (DrawStrip_Paint:702).
     //--- This line was the fourth writer and the only one that shortened it.
     //--- WHY IT SHOWS AS «PANEL HALF GONE» AND NOT AS A STUCK TAB: the press edge
     //--- ALREADY acted (598), and a tab press re-lays-out and re-places the plate —
     //--- MEASURED in one log second: `PLATE tab=5 ... xy=196,37` then
     //--- `PLATE tab=1 ... xy=196,18`, and the tab seats move with it
     //--- (`GT2 356,102` -> `GT2 512,83`). So by the time the second channel arrives,
     //--- the control under the hand is a different one and the plate under the release
     //--- pixel may not be the plate at all: `DrawStripClose()` runs, and it is
     //--- `ObjectsDeleteAll("PnlDrawS_G")` — the head, the tab row and the foot with it.
     //--- The cards never had this shape: `PnlClickFallback` spends the gesture and the
     //--- press chain consumes the echo (`s_PnlClickActed`), ONE arbiter for two
     //--- channels. This flag is that arbiter; it now has the lifetime the cards' has.
     if(s_dsGearPressSpent)
        return DrawStripClickFamily();
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
       // P-UI-113-OFF (2026-09-23): the closed-state right-click open channel
       // retired with the trigger — unreachable now (`!s_dsOpen` returned above).
        if(!s_dsOpen) return false;
        DrawStripGripRelease();   // a click ends any grip carry (stale-grab net)
        //--- P-DRAW-84: the panel's coordinate channel lives on the PRESS EDGE
        // (7337), not here. It cannot live here alone: every control in this file
        // is non-selectable, so this event never fires for one, and a second call
        // would fire the same control twice on a release that does arrive.
        if(sparam == DrawStripGearCloseName() || sparam == DrawStripGearCloseSkinName() ||
           sparam == DrawStripGearCloseIconName())
       {
          DrawStripClose();
          ChartRedraw();
          return DrawStripClickFamily();
       }
       // P-DRAW-11: the plate itself is not a control — a tap on it shuts the

      // open popover (the popover owns the next press, BaseKnot parity) and
      // keeps the strip (and its gear) itself. P-DRAW-29: the plate is a
      // FAMILY (9 skin pieces, or the legacy rect) — any of them is the plate.
      if(DrawStripIsBg(sparam))
      {
         //--- P-DRAW-48: the BOARD's own plate is dead space — a near miss between
         //--- two cells (the 8 px gap) landed on the plate's body and shut the whole
         //--- board, which is half of the report «روی رنگ کلیک میکنم بسته میشه».
         //--- Only the STRIP's and the PANEL's plates still shut the popover.
         if(!DrawStripIsBoardPlate(sparam) && s_dsPicker != DSTRIP_PICK_NONE)
         {
            DrawStripClosePicker();
            DrawStripLayout();
            DrawStripPaint();
         }
         return DrawStripClickFamily();
      }
      // P-DRAW-10: a cell answers by BOTH of its names — the button (its control)
      // and the icon label (its face), because MT4 gives the click to whichever
      // screen object sits highest under the cursor.
      for(int i = 0; i < DSTRIP_MAX_SLOTS; i++)
      {          if(sparam == DrawStripObjName(i) || sparam == DrawStripIconName(i) ||
             sparam == DrawStripIconName(i) + "C" || sparam == DrawStripIconName(i) + "S" ||
             sparam == DrawStripIconName(i) + "C2")
          { DrawStripTap(i, sparam); return DrawStripClickFamily(); }
      }       if(sparam == DrawStripGripName() || sparam == DrawStripGripIconName() ||
          sparam == DrawStripGripIconName() + "C" || sparam == DrawStripBadgeName() ||
          //--- P-DRAW-83: the head's version chip is chrome on the head's own
          //--- carry (the head's drag is geometric, `DrawStripGripWhich`), never a
          //--- control — and it was not named anywhere, so a press on it fell past
          //--- every branch and out to the CHART. One more no-op, like the mark and
          //--- the title beside it.
          sparam == DrawStripGearHeadName("VB") ||
          // TV parity board: its grip / name tiles are the carry's, not a control's.
          sparam == DrawStripPHeadGName() || sparam == DrawStripPHeadGChipName() ||
          sparam == DrawStripPHeadGIconName() || sparam == DrawStripPRecLabelName() ||
          sparam == DrawStripPHexLbName())
          return DrawStripClickFamily();   // drag / info / tab bed: no tap
      for(int a = 0; a < DSTRIP_ACT_N; a++)
      {
         if(sparam == DrawStripActName(a) || sparam == DrawStripActIconName(a) ||
            sparam == DrawStripActIconName(a) + "C")
         { DrawStripActTap(a); return DrawStripClickFamily(); }
      }
       // popover header close seat.
       if(sparam == "PnlDrawS_PHeadX")
       {
          DrawStripClosePicker();
          DrawStripLayout();
          DrawStripPaint();
          return DrawStripClickFamily();
       }
       // P-DRAW-64a: the board's header NAMES THE ROLES — each segment sets its own
       // (see the paint), so there is no secret toggle to discover.
       if(sparam == "PnlDrawS_PHeadB" && DrawStripMergedColor(s_dsKind) &&
          DrawStripIsColorSlot(s_dsPicker))
       {
          if(s_dsPicker == DRAW_SLOT_COLOR) return DrawStripClickFamily();
          s_dsPicker = DRAW_SLOT_COLOR;
          DrawStripLayout();
          DrawStripPaint();
          return DrawStripClickFamily();
       }
       if(sparam == "PnlDrawS_PHeadF" && DrawStripMergedColor(s_dsKind) &&
          DrawStripIsColorSlot(s_dsPicker))
       {
          if(s_dsPicker == DRAW_SLOT_FILLCLR) return DrawStripClickFamily();
          s_dsPicker = DRAW_SLOT_FILLCLR;
          DrawStripLayout();
          DrawStripPaint();
          return DrawStripClickFamily();
       }
       // TV parity board: the RECENT band's cells, and the HEX field (a tap there
       // is a tap on the field itself — it takes focus for typing, no action).
       for(int i = 0; i < DSTRIP_RECENT_MAX; i++)
          if(sparam == DrawStripPRecName(i) || sparam == DrawStripPRecGlassName(i))
          { DrawStripPickTapRecent(i); return DrawStripClickFamily(); }
       // P-DRAW-48: a tap on the field takes the focus, and `s_dsHexFocus` is what
       // stops the live seed from overwriting the hex being typed.
       if(sparam == DrawStripPHexEdName()) { s_dsHexFocus = true; return DrawStripClickFamily(); }
       // P-DRAW-48: the board's PIN (the reference's dock/undock).
       if(sparam == "PnlDrawS_PHeadP" || sparam == "PnlDrawS_PHeadPI")
       {
          s_dsBDock = !s_dsBDock;
          s_dsBManual = !s_dsBDock;      // floating = wherever it stands now
          if(s_dsBDock) DrawStripBoardPlace();
          DrawStripLayout();
          DrawStripPaint();
          return DrawStripClickFamily();
       }
       // popover rows (button, face, label — one tap).
      for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
          if(sparam == DrawStripPickName(r) || sparam == DrawStripPickIconName(r) ||
             sparam == DrawStripPickLabelName(r) || sparam == DrawStripPickChipName(r) ||
             sparam == DrawStripPickRailName(r) || sparam == DrawStripPickGlassName(r))

         { DrawStripPickTap(r); return DrawStripClickFamily(); }
      }
      // gear grid cells, rows, foot. Edits take focus for typing.
      //--- P-DRAW-117 (2026-10-01): THE TAB LOOP IS GONE WITH THE TAB ROW. A group
      //--- header is a ROW (`DSTRIP_GRK_GROUP`), and the row loop below answers it
      //--- through `DrawStripRowName(r)` — the same seat array the paint writes, which
      //--- is the coordinate channel's own rule (P-DRAW-84). The retired `GT*` /
      //--- `GTrack` / `GU` names have no branch here on purpose: no painter in this
      //--- build produces them, and the panel's own paint and purge sweep them.
      for(int g = 0; g < DSTRIP_GRID_MAX; g++)
         if(sparam == DrawStripGridName(g) || sparam == DrawStripGridIconName(g) ||
            sparam == DrawStripGridGlassName(g))
         { DrawStripGridTap(g); return DrawStripClickFamily(); }
      for(int gr = 0; gr < DSTRIP_GLIST_MAX; gr++)
          if(sparam == DrawStripRowName(gr) || sparam == DrawStripRowIconName(gr) ||
             sparam == DrawStripRowLabelName(gr) || sparam == DrawStripRowChipName(gr) ||
             sparam == DrawStripRowRailName(gr) || sparam == DrawStripRowStateName(gr))
         { DrawStripGearRowTap(gr); return DrawStripClickFamily(); }   // P-DRAW-69: the row's private separator is gone
       //--- P-DRAW-83: AND THE FOOT'S OWN GLYPH. `DrawStripFootGlyphName(f)` (the
       //--- 15x15 icon the cards' foot wears at `bx+12`, one `DrawStripFace` above the
       //--- button on Z_STRIP_OVER) was the one member of the foot family the router
       //--- did not answer: a press on the icon itself — the part of a ghost button a
       //--- hand aims at — was the topmost object under the pointer and reached no
       //--- branch at all.
       for(int f = 0; f < DSTRIP_GEAR_FOOT_N; f++)
           if(sparam == DrawStripFootName(f) || sparam == DrawStripFootSkinName(f) ||
              sparam == DrawStripFootGlyphName(f) || sparam == DrawStripFootLabelName(f))
          { DrawStripFootTap(f); return DrawStripClickFamily(); }

      for(int e = 0; e < 5; e++)
         if(sparam == DrawStripEditName(e)) return DrawStripClickFamily();
   }
   // P-DRAW-08f: the drawing was deleted from the TERMINAL's own menu (or by the
   // ✕ of another tool). The paint would notice it on the next click, but a
   // toolbar left floating over nothing is exactly the untidy state the user
   // sees first — so the delete closes it in its own event.
   if(id == CHARTEVENT_OBJECT_DELETE)
   {
      if(sparam == s_dsObj) { Print("[drawstrip] close: OBJECT_DELETE of \"", sparam, "\""); DrawStripClose(); }
      // A deleted CHILD is its parent's business: drop the child, heal parent.
      if(BoxIsMidChild(sparam)) { string par = BoxMidParent(sparam); if(par != "" && ObjectFind(0, par) >= 0) BoxMidSync(par); return false; }
      if(FillIsChild(sparam)) { string fpar = FillChildParent(sparam); if(fpar != "" && ObjectFind(0, fpar) >= 0) FillChildSync(fpar); return false; }
      BoxMidDrop(sparam);
      FillChildDrop(sparam);
      BoxMarkDrop(sparam);   // P-UI-134: a deleted box's KEY goes with it
      return false;
   }
   // P-DRAW-41 (2026-09-25) — THIS CHANNEL USED TO FOLLOW. P-DRAW-08c/08e/09d made
   // the drag and the chart change re-anchor the plate onto the object's own anchor
   // (throttled to a live-drag cadence), which is exactly how the strip came to sit
    // on the drawing it serves: the plate chased the work into the work. The home is
    // the answer — the plate stays where the user put it.
    if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_CHART_CHANGE)
    {
       // P-DRAW-64d: the mid's own ride left this branch for the router's head (it
       // must follow with the strip SHUT, and this whole channel returns below it),
       // and the interior's never lived here (addendum 4/5). All this channel still
       // owes is the window's clamp (compare-only when kept).
       // Nothing open: this channel has no work at all — and no "object gone" line
       // for a strip that was never there.
       if(s_dsObj == "") return false;

      if(ObjectFind(0, s_dsObj) < 0)
      { Print("[drawstrip] close: object gone on drag/zoom \"", s_dsObj, "\""); DrawStripClose(); return false; }
      // P-DRAW-41 (2026-09-25): NO RE-ANCHOR, and no re-open either. The plate has a
      // home, so a zoom, a scroll or the drawing's own drag moves the WORK and
      // leaves the plate; the strip is already the right picture at the right spot.
      // All this channel still owes is the window's clamp (compare-only when kept).
      DrawStripHomeClamp();
      return false;
   }
   // P-DRAW-13: the grip carry rides the terminal's own move stream (left = bit 0,
   // BaseKnotTool.mqh:6887 parity). Never consumed: every other half reads moves.
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      DrawStripGripMove((int)lparam, (int)dparam, ((st & 1) != 0));
      return false;
   }
    // P-DRAW-13: Esc dismisses inside-out (gear, then popover, then strip — even
    // pinned: Esc is an explicit dismissal, pin only survives outside clicks).
    if(id == CHARTEVENT_KEYDOWN && lparam == 27)
    {
       if(s_dsGear != 0)
      {
         DrawStripGearClose();
         DrawStripLayout();
         DrawStripPaint();
         return true;
      }
      if(s_dsPicker != DSTRIP_PICK_NONE)
      {
         DrawStripClosePicker();
         DrawStripLayout();
         DrawStripPaint();
         return true;
      }
      Print("[drawstrip] close: Esc key");
      DrawStripClose();
      ChartRedraw();
      return true;
   }
   // P-DRAW-13: gear edits commit on Enter (ENDEDIT).
   // P-DRAW-48: THE `if` WAS INSIDE THIS COMMENT (the closing `)` and the `if` on one
   // line), so the block below ran on EVERY event — the hex field's commit fired on
   // its own click, before the field had ever taken a keystroke.
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
    {
       if(sparam == DrawStripPHexEdName()) { DrawStripPopHexEnd(); return true; }
       for(int e = 0; e < 5; e++)
          if(sparam == DrawStripEditName(e)) { DrawStripEditEnd(e); return true; }
       return false;
    }
     if(id == CHARTEVENT_CLICK)
     {
        int rcx = (int)lparam, rcy = (int)dparam;
        //--- P-DRAW-97 (2026-09-30) — THE SCRUB'S RELEASE, ON THE ONLY CHANNEL THAT
        //--- CARRIES IT. A press on a swatch starts the preview on the press EDGE
        //--- (DrawStripGripMove:40-48) and a MOTIONLESS release emits no MOUSE_MOVE
        //--- — the very fact the line below was written for (P-LM-13) — so the one
        //--- event that ends the gesture is this one, and it reached only
        //--- DrawStripGripRelease, which clears `s_dsPalGrab` and nothing else. The
        //--- drawing therefore kept the PREVIEW's pixels: `DrawSlotPreviewColor`
        //--- writes `OBJPROP_COLOR` (Toolbar_A) and NOT the pure tag its own
        //--- property is read from, so the shape wore a colour its tags did not
        //--- name. Measured consequence of one press-and-lift on a swatch: the swatch
        //--- stayed rimmed in the accent (`s_dsPalCell` never cleared), the panel's
        //--- colour cell, the board's HEX field and every `PickIsCur` ring kept
        //--- showing the OLD colour, and no undo step existed for the change. The
        //--- move path already had the right order — apply, then the one ender — and
        //--- `DrawStripPalRelease`'s own `s_dsPalDoneMs` witness makes a second
        //--- report of the same release a no-op, so this is safe on both channels.
        if(s_dsPalGrab) DrawStripPalRelease(rcx, rcy);
        DrawStripGripRelease();   // motionless releases emit no MOVE (P-LM-13 net)
        // P-UI-113i: THE RELEASE'S OWN DRAWING IS NEVER AN OUTSIDE CLICK. The press

       // owner is accepted even if the terminal's control shifts under the hand,
       // and the release pixel gets the same body/control hit test as a still press.
       // Selection is not consulted here: selected and unselected drawings therefore
       // cannot take different paths through dismissal (P-UI-113h's selected handle
       // is geometry, not a special privilege).
       if(DrawStripReleaseOnDrawing(relPressObj, rcx, rcy)) return false;
      // P-DRAW-13: pin survives outside clicks (only ✕ paths, Del and Esc dismiss).
      if(s_dsPinned) return false;
      // P-UI-113d: A DRAG-RELEASE IS NOT A DISMISSAL (the box mini-strip's own
      // `dragRel` / BK_CLICK_SLOP rule, measured in the click head above). Reading
      // it as one is the second way a strip vanished on the user's own hand: hold
      // on a drawing, the strip appears, the hand drifts two digits, let go — and
      // the toolbar they were reaching for is gone.
      if(relWasDrag) return false;
      if(!DrawStripPointInside(rcx, rcy))
      {
         // DIAG-113 (temporary): one line per dismissal so the log names the
         // gesture that closed the strip, not a guess about it.
         Print("[drawstrip] dismiss click at ", rcx, ",", rcy, " travel=", s_dsTravel,
               " obj=\"", s_dsObj, "\"");
         DrawStripClose();
      }
   }
   return false;
}

#endif // DRAW_STRIP_ROUTER_MQH
