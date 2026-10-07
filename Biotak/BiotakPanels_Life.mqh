// BiotakPanels_Life.mqh - BiotakPanels split 2026-09-29: exact lines 9984-10399 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_LIFE_MQH
#define BIOTAK_PANELS_LIFE_MQH

void HandleUIChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Base/Knot session ended via ESC/right-click (handled in EventHandlers
   // BEFORE this runs): re-show the ring menu hidden at arm time.
   if(BaseKnotTakeRestoreFlag())
   {
      if(!g_UI.menuVisible)
      {
         g_UI.menuVisible = true;
         DeleteMenu();
         CreateMenu();
         SaveUIStates();
      }
      ChartRedraw();
   }
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mx = (int)lparam;
      int my = (int)dparam;
      g_LastUIX = mx;
      g_LastUIY = my;
      bool leftDown = (((int)sparam & 1) != 0);
      // P-UI-83: the bit's own RECENCY, stamped where the bit is read. Every
      // non-event witness (the KEYSTATE probe in the poll, the CLICK/OBJECT_CLICK
      // finalizer) must ask this before it may end a gesture: while the terminal
      // is still delivering down-readings the press is LIVE, and a click that
      // arrives in that window is the echo of that press (P-UI-49b), never its
      // release. One store per down-move; nothing else reads it on this path.
      if(leftDown) s_PnlDownAt = GetTickCount();
      bool pressStart = MousePressStart(leftDown);
      // P-PERF-15: the cursor-move path is the one the user FEELS ("the lag is
      // there when I work with the chart"), and the pair budget line can only
      // say the UI half owns it. The three owners are timed separately here and
      // reported only when the move blows its budget, so the next fix is aimed
      // by measurement like the base-price phase was.
      uint p15t = GetTickCount();
      // P-BK-02: while a Base/Knot draw session owns the mouse, the ring menu
      // is hidden — menu hover/drag/long-press must stay out of the gesture
      // (no orb drag, no armed long-press, no hover tip mid-draw). OBJECT_CLICK
      // still flows (orb-click = session exit) and open panels keep working.
      if(!BaseKnotSessionActive())
         CircHandleMouseMove(mx, my, leftDown, pressStart);
      uint p15ring = GetTickCount() - p15t; p15t = GetTickCount();
      PnlHandleMouseMove(mx, my, leftDown, pressStart);
      uint p15panel = GetTickCount() - p15t; p15t = GetTickCount();
       BkHoldOnMove(mx, my, leftDown, pressStart);
       CpHoldOnMove(mx, my, leftDown, pressStart);   // P-UI-101: the line's own hold
      uint p15hold = GetTickCount() - p15t;
      // P-UI-48: the custom price line is SELECTABLE again - that IS its drag -
      // so a press a UI owner just claimed must not leave MT4 holding the line:
      // a selection that outlives the press lets MT4 drag the line along with
      // the NEXT gesture too (the interference P-UI-45 removed by removing the
      // drag). The test is one bool read on a press edge; the clear is one
      // property write per UI press, and the line's own grab claims no owner, so
      // this can never drop the selection out of a legitimate line drag.
      // P-UI-100 (2026-09-22): and it is now the SHARED owner, so the step-1 pair
      // is released by the same press — the two hand-set lines answer one law, and
      // a UI press that keeps holding the red handles would drag the ladder's own
      // step-1 line along with the card.
      if(pressStart && g_DragOwner != DRAG_NONE) HandLinesDropAll();
      if(p15ring + p15panel + p15hold >= P_P4_MOVE_WARN_MS)
         _LOG_GATE_W Print("[W][PERF] mouse move breakdown: ring=", (int)p15ring, "ms panel=",
               (int)p15panel, "ms hold=", (int)p15hold, "ms");
      return;
   }

   if(id == CHARTEVENT_CLICK)
   {
      int cx = (int)lparam, cy = (int)dparam;
      g_LastUIX = cx;
      g_LastUIY = cy;
      // Classify the release BEFORE BkHoldOnBoxUp clears the latch: a button-up
      // far from its press-down is a drag end (read s_BkHoldX/Y while live —
      // disarmed-after-fire reads as "no press", covered by fireRel instead).
      bool dragRel = (s_BkHoldMs != 0 &&
                      (MathAbs(cx - s_BkHoldX) > BK_CLICK_SLOP ||
                       MathAbs(cy - s_BkHoldY) > BK_CLICK_SLOP));
      bool fireRel = s_BkFireReleasePending;   // the opening hold's own release
      s_BkFireReleasePending = false;          // one-shot — every CLICK consumes
      MousePressStart(false);      // button-up — resync the rising-edge detector
      s_PnlClickActed = false;     // P-UI-75a: a press echo cannot outlive its own
                                   // press — a release resyncs EVERY edge witness
      ChartPointerFinalizeOnUps(); // finalize every gesture reliably
      BkHoldOnBoxUp();             // box-hold release opens NOTHING (mid-hold already fired)
      // P-UI-40c: this release is one we already acted on, and it never reaches
      // HandleButtonClick's `if(g_LongPressFired)` guard - so the long-press
      // latch dies here (its own gesture is over) instead of eating the NEXT
      // click. See the note on UILongPressLatchClear.
      if(UIShouldSuppressClick()) { UILongPressLatchClear(); return; }   // release after a strip/drag/press action
      // Countdown tag = a chart object of its OWN layer: a plain left click on
      // it opens the ATR LABELS card, whose top rows are the countdown's own
      // settings (switch/color/size/gap). Right-click is left to the terminal.
      if(StringFind(sparam, "r") < 0 && LiveCountdownPointInside(cx, cy))
      {
         PnlOpen(2);
         UISuppressNextClick();   // the release that opened it must not double-act
         ChartRedraw();
         return;
      }
      // P-UI-74: the plain click is the card's second delivery channel too
      // (the cset cells / switch / band are coordinate controls whose objects
      // are bitmap skins — MT4 fires no OBJECT_CLICK for those at all).
      if(StringFind(sparam, "r") < 0 && PnlClickFallback(cx, cy)) return;
      // TV-like: an outside chart click dismisses the floating strip — but
      // never the gesture that opened it, never a drag-release, never a
      // right-click, and never a tap on its OWN box (the toolbar stays while
      // its object is selected — box clicks never reach here, BK owns them,
      // so re-hit-test the held box from pixels).
      bool onHeldBox = false;
      if(g_PnlOpen == 13 && g_BkMiniBox != "" && BaseKnotVisibleNow(g_BkMiniBox))
      {
         int hsw = 0; datetime hct = 0; double hcp = 0;
         if(ChartXYToTimePrice(0, cx, cy, hsw, hct, hcp) && hsw == 0 && hct > 0 && hcp > 0)
            onHeldBox = (BaseKnotBoxAt(hct, hcp) == g_BkMiniBox);
      }
      if(g_PnlOpen == 13 && !fireRel && !dragRel && !onHeldBox &&
         StringFind(sparam, "r") < 0 && !BkMiniStripPointInside(cx, cy))
         PnlCloseAll();
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      g_LastUIX = (int)lparam;
      g_LastUIY = (int)dparam;
      MousePressStart(false);
      s_PnlClickActed = false;     // P-UI-75a: same resync on the object-click leg
      ChartPointerFinalizeOnUps();
      BkHoldOnBoxUp();             // box-hold release opens NOTHING (mid-hold already fired)
      s_BkFireReleasePending = false;   // release over an object ends the opening gesture too
      // P-UI-40c: the long-press release lands HERE (suppressed), not in
      // HandleButtonClick - clear the latch with its gesture (see the note on
      // UILongPressLatchClear).
      if(UIShouldSuppressClick()) { UILongPressLatchClear(); return; }   // release after a drag/long-press
      // P-PERF-26: ONE PRESS, THREE OWNERS - and the event ledger could only say
      // "the UI half owns it". A ring/panel press is the interaction the user
      // repeats most (every show/hide switch is one), so each owner is timed and
      // the line appears only when the press blows the budget.
      uint p26t = GetTickCount();
      int flags = HandleButtonClick(sparam);
      uint p26btn = GetTickCount() - p26t; p26t = GetTickCount();
      flags |= PnlHandleClick(sparam, (int)lparam, (int)dparam);
      uint p26pnl = GetTickCount() - p26t; p26t = GetTickCount();
      if(flags != REFRESH_NONE) ApplyRefreshFlags(flags);
      uint p26apply = GetTickCount() - p26t;
      if(p26btn + p26pnl + p26apply >= P_P4_CLICK_WARN_MS)
         // P-PERF-26b: the three phases said WHERE the time went but not WHICH
         // control asked for it, so a 531 ms press could not be reproduced. The
         // control name turns the next log line into a target.
         _LOG_GATE_W Print("[W][PERF] click breakdown: button=", (int)p26btn, "ms panel=",
               (int)p26pnl, "ms apply=", (int)p26apply, "ms control=", sparam);
      return;
   }

   // TV "Add text" commit: ENTER in the card-12 TEXT field fires ENDEDIT.
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      int ei, er; string ek;
      ParsePnlName(sparam, ei, er, ek);
      // P-UI-91: the palette's HEX field gets the same treatment card 12 gets.
      // It was invisible here - the branch below only matches `ei == 12 &&
      // ek == "ED"` - so pressing Enter in the hex field did nothing at all and the
      // colour stayed uncommitted until the user happened to click another palette
      // control. FlushPalHex() clears g_PalHexFocus itself and applies the colour,
      // so the EventHandlers hotkey guard is released on the same event.
      if(g_PalOpen && sparam == g_UI.btnPrefix + "Pal_hex")
      {
         FlushPalHex();
         ChartRedraw();
         return;
      }
      if(ei == 12 && ek == "ED")
      {
         string t = ObjectGetString(0, sparam, OBJPROP_TEXT);
         g_BkTextFocus = false;
         if(g_BkMiniBox != "" && BaseKnotFind(g_BkMiniBox) >= 0)
         {
            BaseKnotSetText(g_BkMiniBox, t);
            RefreshDisplay(REFRESH_BUFFERS);
         }
         ChartRedraw();
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      // P-UI-48: a native drag that is NOT the line's own belongs to another
      // selectable object of ours - a BaseKnot box, whose handle IS its
      // OBJPROP_SELECTABLE and whose drag is MT4's. MT4 moves EVERY selected
      // object, so the line must not be selected while a box is being dragged,
      // or the box drag re-anchors the TH start price behind the user's back.
      // The line's own drag is excluded by NAME (its selection is what drives
      // the live update). One string compare; the write is guarded inside the
      // owner.
      if(sparam != g_customPriceHorizontalLineName) ClearCustomPriceSelection();
      // Real-time strip follow: the held box's drag reaches here in the SAME
      // event the domain used to re-sync the children (consumed ≠ hidden —
      // the entry forwards every event to both handlers). String pre-check
      // first (free), syscalls only on a hit; 30ms throttle + 4px dead band
      // inside BkStripFollow keep drag storms cheap (throttled, explicit list).
      if(g_PnlOpen == 13 && g_BkMiniBox != "" &&
         sparam == BaseKnotBoxName(BaseKnotPrefix(g_BkMiniBox)))
      {
         static uint s_BkFollowMs = 0;
         uint nowF = GetTickCount();
         if(nowF - s_BkFollowMs >= 30) { s_BkFollowMs = nowF; BkStripFollow(); }
      }
      int flags = PnlHandleDrag(sparam, g_LastUIX);
      if(flags != REFRESH_NONE) ApplyRefreshFlags(flags);
      return;
   }

   if(id == CHARTEVENT_KEYDOWN)
   {
      int key = (int)lparam;
      if(key == PNL_KEY_ESC)
      {
         if(g_PalOpen) { PalHandleKey(PNL_KEY_ESC); return; }
         // TV-like: Esc closes the open ▾ dropdown first, the panel second.
         if(g_PnlOpen == 13 && g_BkDd != 0) { BkDdClose(); ChartRedraw(); return; }
         if(g_PnlDdItem >= 0) { PnlDdClose(); ChartRedraw(); return; }
         if(g_PnlOpen >= 0) { PnlCloseAll(); return; }
      }
      else
      {
         PalHandleKey(key);
      }
      return;
   }

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      // P-PERF-16: the chart rect can have changed (resize, DPI, window). Drop the
      // cached UI metrics here so the first reader after this event re-reads the
      // size once, instead of every hit test re-reading it.
      CircUIMetricsInvalidate();
      // P-UI-140: and the two STORED places re-derive themselves from their fractions
      // BEFORE anything paints them, so a resize / maximize / restore / DPI change
      // lands on this frame instead of waiting for the 250 ms safety pass. This is
      // the scenario the report names first; the timer line covers a missed event.
      CircHomesRefresh();
      if(g_UI.menuVisible) UpdateCircularMenuPosition();
      // P-UI-93: and the event a DPI change is most likely to arrive on (a window
      // dragged to another monitor is resized by the terminal first). The probe is
      // time-gated, so a resize/zoom storm costs one compare per event; a real
      // change rebuilds every surface from the new metrics. It sits AFTER the pair
      // above on purpose: the rebuild re-derives the ring's geometry itself, and
      // the metrics invalidation is the contract this branch already declares
      // (probe-budget-audit's `chart change stops invalidating` seed anchors on it).
      if(PnlDpiPoll()) UIRebuildForMetrics();
      if(PnlClampOpenPanel()) ChartRedraw();   // shrunken chart: keep header grabbable
      // P-PERF-02: pan/zoom changes what the HTF overlay must cover — re-check
      // its viewport cap on the event that moved the view, not on the next 1 s
      // timer probe (internally throttled, so a zoom storm stays cheap).
      if(g_UI.showHTF) HTFEnsureDrawn();
      return;
   }
}

//--- live sync: an open Step card follows mode changes made OUTSIDE the panel
// (E key / Tools ring). Change-guarded — PnlUpdateRow runs only on a flip,
// so the per-tick cost is one int compare. (Other hotkey/panel pairs have the
// same staleness by design; step is synced because its three writers are
// advertised as one setting.)
void PnlSyncOpenStepRow()
{
   static int s_LastMode = -1;
   int cur = (int)g_stepCalculationMode;
   if(cur == s_LastMode) return;
   s_LastMode = cur;
   // The mode reshapes the open Step card (each mode's own rows live below
   // the segments) — rebuild it, don't just refresh row 0.
   if(g_PnlOpen == 9) PnlOpen(9);
}

//==============================================================================
// P-UI-40 — THE PANEL FOLLOWS STATE IT DOES NOT OWN
//
// PnlSyncOpenStepRow above is the only sync of this kind that existed: a
// change-guard that notices g_stepCalculationMode moving under the open card.
// It answered the E/Tools half of the problem and left every other shared state
// unsynchronised — which is exactly the "some switches work, some don't" shape
// of the report. It is also the wrong shape to copy N times: one guarded
// comparison per shared state, per tick, forever.
//
// The generalisation: a writer that cannot repaint RAISES A REQUEST
// (RequestUISync, GlobalVariables — the hotkeys live in a file included before
// this one, and Lite has no panel at all), and the UI layer drains it here. The
// drain repaints what the ring and the open card DISPLAY, reading the same live
// values the rows already read, so nothing can disagree about a value and no
// state needs its own guard.
void PnlSyncOpenCard()
{
   if(g_PnlOpen < 0) return;
   if(g_PnlOpen == 13) { BkMiniRefresh(); return; }   // item 13 is one toolbar, not rows
   int rows = PnlRowsCount(g_PnlOpen);
   for(int r = 0; r < rows; r++) PnlUpdateRow(g_PnlOpen, r);
   // R-KEYCAP: the header .key cap shows (and now flips) the card's master, so
   // it follows a hotkey / ring toggle exactly like the row that owns the value.
   PnlKeycapSync(g_PnlOpen);
}

// The drain. Called from the event tail (so a hotkey is reflected in the SAME
// event) and from RefreshKitOnBar (so a path that misses the tail still settles
// within a tick). Consuming the request first is what keeps it idempotent: two
// drains cost one repaint.
void UISyncDrain()
{
   if(!UISyncRequested()) return;
   UISyncConsume();
   // The ring's own layer: item activity state + the badges derived from it.
   UpdateCircularItemStates();
   UpdateCircularBadges();
   PnlSyncOpenCard();
}

//+------------------------------------------------------------------+
//| Kit lifecycle entry points (called from Biotak Trigger TH3.mq4)  |
//+------------------------------------------------------------------+
void InitializeBiotakKit()
{
   InitializeUISupport();
}

void SaveBiotakKit()
{
   SaveUISupport();
}

// P-UI-142: snapshot the open surfaces at teardown START (Full entry calls this
// BEFORE PnlCloseAll/DeleteMenu clear the flags they would otherwise persist as
// closed). Plain Sets: teardown-time only, the teardown flush makes them durable.
// Lite owns no surfaces and never calls this (its unit has no panels/menu).
void SnapshotOpenSurfaces()
{
   GlobalVariableSet(GetGVName("PNLOPN"), (double)(g_PnlOpen == 13 ? -1 : g_PnlOpen));   // mini strip is box-bound: never reopened blind
   GlobalVariableSet(GetGVName("TOOLS"), g_ToolsOpen ? 1.0 : 0.0);
}

// P-UI-142: reopen what the snapshot saw open — once, on the first tick after a
// FRESH attach (terminal restart / re-add). A timeframe switch closes panels by
// design: the switch stamp is fresh then, so this stays out of its way. Item 13
// (box-bound mini strip) is never reopened blind; an already-open card wins.
void PnlRestoreSaved()
{
   static bool done = false;
   if(done) return;
   done = true;
   if(g_PnlOpen >= 0) return;
   string vn = GetGVName("PNLOPN");
   if(!GlobalVariableCheck(vn)) return;
   int want = (int)GlobalVariableGet(vn);
   if(want < 0 || want >= PNL_COUNT || want == 13) return;
   string stamp = "Biotak_LastTFSwitch_" + GetCachedChartIdStr();
   datetime nowT = TimeCurrent();
   if(nowT > 0 && GlobalVariableCheck(stamp))
   {
      datetime lastSw = (datetime)GlobalVariableGet(stamp);
      if(lastSw > 0 && (nowT - lastSw) <= 20) return;   // a switch just closed these: stay closed
   }
   PnlOpen(want);
}

//--- per-tick / per-bar UI refresh (HTF forming candle + menu badge sync)
//--- P-UI-75a: THE DRAG'S POLLED SHADOW — the tick/timer half of the grab.
//|     A press that never moved emits NO CHARTEVENT_MOUSE_MOVE (the P-BK-03
//|     trap `UILeftButtonDown` documents), and the button bit of `sparam` is a
//|     second witness that can be wrong on its own — so a drag reachable only
//|     from a fresh mouse-move press edge is dead for that whole gesture, which
//|     is the fourth report of the same shape. This runs beside `BkHoldPoll`
//|     (per tick + 250 ms timer) and can only ADD entries, never re-route one:
//|       * it arms ONLY while the physical button is down and the event latch
//|         never saw that press (`!g_MouseWasDown`) — a working event channel
//|         keeps its own gesture, always;
//|       * the grab itself is the SAME `PnlTryGrabMove` the press chain uses,
//|         so the control list, the palette exclusion and the claim cannot
//|         drift from it;
//|       * it steps through the SAME `PnlDragStep`, so the adaptive window and
//|         the single frame owner are shared, not duplicated;
//|       * it ends through the SAME `PnlDragFinish`, and it PINS the spot only
//|         when it can prove the card moved (a recovery path stays conservative
//|         — the `UILeftButtonUp` rule one gesture up).
//|     Cost when no drag is live: four reads.
//--- P-UI-127: STILL NOT CALLED, and that is the measurement, not a retirement:
//--- P-UI-75a measured 197 drags armed by the event channel against ZERO by this
//--- poll, so the per-tick KEYSTATE probe bought nothing (G-09 — the cheaper of
//--- two equal paths ships). Kept compiled: it is the one path to a drag whose
//--- press edge the terminal never delivered.
void PnlDragPoll()
{
   if(g_PnlMoveItem >= 0)
   {
      // The release MT4 never reported (cursor held still, focus lost, another
      // chart). Both KEYSTATE conventions must agree it is free (P-UI-73a) —
      // TWICE in a row (P-UI-78): a single up-reading is a rumour, the probe
      // flickers mid-gesture (P-BK-05) and one agreement murdered live drags
      // mid-press. A real release spans many passes, and the event path plus
      // the CLICK finalizer usually finish first anyway — so this costs a live
      // drag nothing and a real release at most one poll period.
      // P-UI-83: TWO witnesses again — the probe AND the event bit's recency (see
      // the P-UI-83 block above PnlPointerQuiet). This rule was the OTHER way a
      // live press died: on a terminal whose probe always reads "free", the
      // poll's second pass (a tick or the 250 ms timer) executed every drag it
      // had not armed — 253-500 ms per press, exactly what the ledger shows. A
      // gesture whose event channel is still delivering down-readings is live,
      // whatever the probe says about the button.
      if(UILeftButtonUp() && PnlPointerQuiet())
      {
         if(!s_PnlPollUpArmed) { s_PnlPollUpArmed = true; return; }
         s_PnlPollUpArmed = false;
         PnlDragFinish(s_PnlMoveMoved, s_PnlMoveMoved);
         return;
      }
      s_PnlPollUpArmed = false;
      PnlDragStep(g_LastUIX, g_LastUIY);   // apply what the event channel missed
      return;
   }
   if(g_PnlOpen < 0 || g_PnlOpen == 13) return;
   if(g_PnlDragItem >= 0 || g_PalMixDrag > 0) return;   // another panel gesture owns it
   if(g_DragOwner != DRAG_NONE) return;                 // the ring / orb owns it
   if(g_MouseWasDown) return;      // the event channel saw this press: its gesture
   if(s_PnlClickActed) return;     // a control already consumed this gesture
   if(!UILeftButtonDown()) return;
   if(!PnlTryGrabMove(g_LastUIX, g_LastUIY,true)) return;
   _LOG_GATE_W Print("[W][PERF] panel drag armed by the poll (no mouse-move press edge)");
}

void RefreshKitOnBar()
{
   // Called from OnCalculate AND OnTimer — i.e. on every tick twice.
   PnlRestoreSaved();   // P-UI-142: once — reopens the teardown snapshot's panel, if any
   // RefreshUIPerTick() already self-throttles (500ms + change guards), so
   // this is a straight pass-through; kept as a seam for future bar-only work.
   RefreshUIPerTick();
   BkHoldPoll();   // stationary-press hold needs key-state polling (no event exists for it)
   CpHoldPoll();   // P-UI-101: the custom price line's own hold, same zero-move backup
   DrawStripHoldSelectPoll();   // P-UI-113g: restore native selection after MT4's release
   BoxExtrasPump();             // P-DRAW-21/22: box mid follow + extend steps (2s/new-bar throttled)
   // P-UI-127: the card drag's polled shadow stays out, on its own measurement
   // (P-UI-75a): it armed ZERO of that session's 197 drags (the terminal's
   // KEYSTATE probe never reads "down", P-UI-83) while its per-tick probe was
   // the feature's ONLY always-on cost. The event channel arms every real drag,
   // so serving the poll too is exactly the «هزینه اضافی» the user removed. The
   // function stays below; restore = uncomment this call.
   // PnlDragPoll();  // P-UI-75a: the same net for the card drag (one press contract)
   PnlSyncOpenStepRow();   // open Step card follows E/Tools changes (change-guarded)
   UISyncDrain();          // P-UI-40: hotkey-raised requests settle here too
   BkMiniStripHeal();      // strip closes itself when its box vanished (R-BKSTRIP)
   // P-UI-93: the display is a measurement too. The tick/timer pump is where a
   // DPI change that emits NO chart event is still caught (a Windows scale
   // change with the window in place); the probe is 2 s-gated, and the rebuild
   // happens only when the value really moved.
   if(PnlDpiPoll()) UIRebuildForMetrics();
}
#endif // BIOTAK_PANELS_LIFE_MQH
