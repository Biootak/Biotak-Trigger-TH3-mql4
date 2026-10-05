//+------------------------------------------------------------------+
//| EventHandlers_Router_Gesture.mqh                                 |
//|                                                                  |
//| P-SIZE-1500 (2026-10-04) - the custom price line's gesture stream.|
//|                                                                  |
//| Exact lines 1030-1495 of EventHandlers_Router.mqh, moved verbatim |
//| into one function, zero renames: the press edge, the claim, the   |
//| carry the terminal does not do itself, the release that drops the |
//| selection it took, and the tooltip the release is owed (P-UI-49c/ |
//| P-UI-99/P-UI-100b). It owes the move because the router was 1630  |
//| lines against a 1592 baseline (contract 7).                       |
//|                                                                  |
//| Kept byte-identical for a reason: the block has NO `return` (its  |
//| own `if` guards it) and reads no router local - so lifting it out |
//| cannot change what the router does. It is included BEFORE the     |
//| router: MQL4 resolves a call top-down.                            |
//+------------------------------------------------------------------+
#ifndef EVENT_HANDLERS_ROUTER_GESTURE_MQH
#define EVENT_HANDLERS_ROUTER_GESTURE_MQH

void RoutCustomPriceGesture(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_MOUSE_MOVE &&
       (g_customPriceLineCreated || g_thStartPointType == TH_START_POINT_CUSTOM_PRICE))
    {
        int mouseFlags = (int)StringToInteger(sparam);
        bool leftButtonDown = (mouseFlags & 1) != 0;
        // P-UI-49c: the press EDGE is the only moment a grab can start here. A
        // press that emits no mouse move is invisible (P-BK-03), so the edge is
        // seen on the first move after it - a few pixels from the press point,
        // which is what CustomPriceGrabAt's tolerance covers.
        static bool s_dragDownSeen = false;
        bool pressEdge = (leftButtonDown && !s_dragDownSeen);
        s_dragDownSeen = leftButtonDown;
        // P-UI-99 (2026-09-21): THE HOLD IS RETIRED — THE CLAIM IS IMMEDIATE.
        // User order: «اون هولد از خط کاستوم پرایس بردار به جاش سلکت و انسلاکت
        // شو درست کن که کاربر راحت باشه و همچنین کلیک شو بقیه ابجکت ها در حین
        // درگ کردن روش ندزده». The P-UI-97 hold-to-arm (a 500 ms beat the press
        // had to outlast before the drag engaged) is gone: a press on the line
        // claims the gesture the way every other chart object does. The comfort
        // the user asked for lives in the pair the hold used to stand between:
        //   * SELECT — the claim selects the line (P-UI-49d's guarded write), so
        //     a grab shows its face, and a plain click selects natively;
        //   * DESELECT — the selection is dropped at THIS gesture's button-up
        //     (the deferred latch below), and a STALE one is drained by arming
        //     the same latch on every foreign press - which is the "while I drag
        //     the other objects the line must not come along" half: a selection
        //     that outlived its gesture is what let MT4 move the line under
        //     another drag (P-UI-45), so the drain stays and fires on the same
        //     events it always did.
        // The foreign-drag discrimination is untouched (P-UI-92/P-UI-96): past
        // the press edge a terminal selection counts only with the cursor really
        // on the line, so a pan or a box drag started elsewhere is never claimed.
        if(leftButtonDown)
        {
            // P-UI-98e: our own step-1 carry, ONE pass per held event. It runs
            // before the claim below so a press that already belongs to the
            // handle is never re-claimed by the custom-price line (one cursor,
            // one gesture).
            if(g_s1OwnActive)
            {
                Step1HandleOwnDragMove((int)lparam, (int)dparam);
            }
            // P-UI-98i: A NATIVE-ONLY DRAG IS ADOPTED. MT4's own per-object drag
            // claimed the line first (the OBJECT_DRAG channel set `g_s1DragLive`
            // with our carry never armed), so this gesture lives or dies by
            // OBJECT_DRAG alone - and on the builds that stutter it (P-UI-49c)
            // that is the cut. With the cursor still on the dragged row the
            // gesture is adopted into our own carry (the claim re-latches the
            // grab at the CURRENT price, so the relative math cannot jump, and
            // the borrow ends the terminal's own loop per P-LM-21); from the
            // next held event both channels drive it. Never while the custom
            // price line owns the gesture (one cursor, one gesture).
            // P-UI-148 (2026-10-02): AND THE TERMINAL'S OWN HOLD IS A SECOND
            // OPINION, because the row test alone is not enough on the build this
            // was reported on («ریل تایم سطوح مثل خود خط کاستوم جابجا نمیشه ...
            // وقتی درگ رها بشه سطوح میاد»): the terminal moves the line itself and
            // reports nothing per step, so between two reports the cursor has
            // already travelled off the row the test last read - the adoption
            // refused, `g_s1OwnActive` stayed false, `Step1HandleOwnDragMove`
            // never ran on the held stream, and the step factor (hence the whole
            // ladder) was only recomputed when the terminal finally spoke, i.e. at
            // the release. This is the custom price line's own recovery shape
            // (`terminalGrab`, P-UI-98i's note 2): a SELECTED live handle IS the
            // terminal saying the press is on it. The claim re-latches the grab at
            // the CURRENT price, so a stale row cannot make the handle jump. Cost:
            // one ObjectFind + one read, only while a gesture of ours is live and
            // our carry has not taken it - never a steady frame.
            else if(g_s1DragLive && !g_s1OwnActive && !g_customPriceLineDragging)
            {
                string adoptRow = "";
                bool onRow = (g_s1DragName != "" &&
                              Step1HandleUnderCursor((int)lparam, (int)dparam, adoptRow) &&
                              adoptRow == g_s1DragName);
                bool terminalHoldsIt = (g_s1DragName != "" &&
                                        ObjectFind(0, g_s1DragName) >= 0 &&
                                        (bool)ObjectGetInteger(0, g_s1DragName, OBJPROP_SELECTED));
                if(g_s1DragName != "" && (onRow || terminalHoldsIt))
                    Step1HandleOwnClaim(g_s1DragName, (int)lparam, (int)dparam);
                if(g_s1OwnActive)
                    Step1HandleOwnDragMove((int)lparam, (int)dparam);
            }
            else if(!g_customPriceLineDragging && !g_s1DragLive)
            {
                // P-UI-98e: the step-1 handle's claim comes FIRST at the press
                // edge — a press on its row belongs to it, and `s1Claimed` is the
                // one term the custom-price claim below yields to. The ROW is
                // recorded for the click contract whether or not the claim takes
                // it: the DRAG needs the armed state, the CLICK does not (a SET
                // handle is exactly what the double-click has to reach).
                // P-UI-98e: A PRESS ON THE CUSTOM PRICE LINE IS NOT OURS - with the
                // P-UI-98i reading: NEAREST WINS. The step-1 claim runs FIRST, so
                // without a yield the gesture the user aimed at the LINE re-steps
                // the ladder instead («میخوام خط کاستوم پرایس جابجا بکنم ... و step
                // جابجا میشن»). A press clearly on the line stays the line's; a
                // press nearer the handle's own row belongs to the handle even
                // when the line's tolerance also covers it (a coarse chart puts
                // both within a few pixels). An exact tie stays with the line.
                // The line's own grab test decides, and the CLICK contract reads
                // the same answer.
                bool onCustomLine = CustomPriceGrabAt((int)lparam, (int)dparam);
                string s1Row = "";
                bool s1Hit = (pressEdge &&
                              !UIPointerOverSurface((int)lparam, (int)dparam) &&
                              Step1HandleUnderCursor((int)lparam, (int)dparam, s1Row));
                bool s1OnRow = (s1Hit && (!onCustomLine ||
                                          Step1NearerThanCustom((int)lparam, (int)dparam, s1Row)));
                // P-UI-98i: A MISSED PRESS EDGE STILL CLAIMS. The edge above is
                // seen on the first MOVE after the press - a press whose first
                // move never arrived here (a release off-chart leaves the shared
                // latch set, so the next press has no edge) could never claim,
                // while the custom-price claim beside it recovers through MT4's
                // own selection. The terminal's pick-up is the second opinion
                // here too: a SELECTED handle with the cursor really on its row
                // is claimed past the edge (and the custom line keeps its own
                // priority - a press on it is never adopted).
                //
                // P-UI-150 (2026-10-02): AND ON THE PRESS EDGE TOO. User order:
                // «دقیقا مثل خود خط کاستوم پرایس باشه نحوه درگ کردنش». The line's claim
                // is `(pressEdge && (terminalGrab || pixelHit)) || (terminalGrab &&
                // atLineNow)`: MT4's own hold counts ON the edge as well as past it,
                // and that second term is what makes the line's drag survive a build
                // whose press edge never arrives here (P-BK-03). The handle had it
                // only past the edge (`!pressEdge`), so on the edge the ONLY route in
                // was the tolerance test - and a press that the terminal had already
                // honoured by selecting the rung-1 line was refused, leaving the whole
                // gesture to the terminal's sparse reports and moving the ladder at the
                // release instead of under the hand. The cursor must still be really ON
                // the row (the row is read live now, P-UI-148) and the row must be the
                // terminal's SELECTED one, so a stale selection can never claim a press
                // aimed elsewhere - the hazard P-UI-96 measured on the line.
                if(!s1OnRow && g_s1LinesArmed && !onCustomLine &&
                   !UIPointerOverSurface((int)lparam, (int)dparam))
                {
                    string selRow = "";
                    if(Step1HandleUnderCursor((int)lparam, (int)dparam, selRow) &&
                       selRow != "" && ObjectFind(0, selRow) >= 0 &&
                       (bool)ObjectGetInteger(0, selRow, OBJPROP_SELECTED))
                    {
                        s1Row = selRow;
                        s1OnRow = true;
                    }
                }
                if(s1OnRow)
                {
                    g_s1ClickRow = s1Row;
                    g_s1ClickRowY = (int)dparam;
                }
                bool s1Claimed = (s1OnRow &&
                                  Step1HandleOwnClaim(s1Row, (int)lparam, (int)dparam));
                // WHO owns this gesture: MT4 grabbed the line (SELECTABLE + the
                // terminal's own hit test), OR our press-edge hit test says the
                // press landed on it. The second term is what makes the drag
                // independent of the terminal's selection behaviour - the drag
                // must not disappear because a build/setting never selects the
                // object (the P-BK-16 reality, on the boxes).
                bool terminalGrab = (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED);
                // P-UI-92: the pixel test guards the PIXEL hit test only. `terminalGrab`
                // is deliberately left alone: that is MT4's own selection, i.e. the
                // terminal already decided the press belongs to the line (and P-UI-45
                // exists precisely because a selection outlives its gesture).
                // P-UI-96: ... but a selection ALSO outlives into FOREIGN drags (a
                // click leaves the line selected; the drain only runs on a later
                // button-up move). Honouring `terminalGrab` with no position check
                // claimed every such drag for the line - it activated mid-pan/box
                // drag and rode along, and the gesture lock made the chart feel
                // stuck. So past the press edge a terminal grab counts only with
                // the cursor really on the line; the press edge itself keeps the
                // untested honour (MT4 just picked it for THIS press).
                bool atLineNow = false;
                if(terminalGrab && !pressEdge)
                    atLineNow = CustomPriceGrabAt((int)lparam, (int)dparam);
                bool pixelHit = (pressEdge && !UIPointerOverSurface((int)lparam, (int)dparam) &&
                                 CustomPriceGrabAt((int)lparam, (int)dparam));
                // P-UI-98m: the re-arm candidate for a SET (masked) line. The
                // armed claim below refuses a SET line, and a masked line fires
                // no OBJECT_CLICK - without this row nobody could wake it. The
                // DRAG needs the armed state, the CLICK does not (a SET line is
                // exactly what the double-click has to reach).
                if(pixelHit && !g_cpLineArmed)
                {
                    g_cpClickArmed = true;
                    g_cpClickY = (int)dparam;
                }
                // P-UI-98d: the claim asks the ARMED state first — a set line is
                // inert; nothing may grab it, not even our own pixel test.
                // P-UI-100b: AND IT ASKS WHETHER THE PRESS IS ALREADY A DRAW. A
                // foreign object that appeared inside the witness window means the
                // terminal is drawing something (its own tool owns this press),
                // and the pixel test cannot tell that from a grab: both are a press
                // on the line followed by a drag. Refusing here is what makes the
                // draw cost NOTHING — no claim, no selection, no carry, so the line
                // never moves and there is nothing to put back. The CLICK rows above
                // are deliberately NOT gated by it: a SET line's double-click to
                // re-arm is not a draw and must keep working.
                if(!s1Claimed && g_cpLineArmed && !TickDeadlinePending(s_cpForeignDrawUntil) &&
                   ((pressEdge && (terminalGrab || pixelHit)) || (terminalGrab && atLineNow)))
                {
                    g_customPriceLineDragging = true;
                    g_customPriceDragOwn = true;
                    // P-UI-98g: a hand on the LINE is the request for its circle —
                    // the same reading the step-1 claim uses (see there).
                    g_cpHandleShown = true;
                    CustomPriceMarkerSync();
                    s_ownLastWrite = 0.0;
                    s_ownGrabPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                    // P-UI-55: the press latch - ONE conversion per gesture, and only
                    // to define the base our own carry moves FROM.
                    s_ownGrabX = (int)lparam;
                    s_ownGrabY = (int)dparam;
                    s_ownGrabCursorPrice = 0.0;
                    {
                        int gW = 0; datetime gT = 0;
                        if(!ChartXYToTimePrice(0, s_ownGrabX, s_ownGrabY, gW, gT, s_ownGrabCursorPrice))
                            s_ownGrabCursorPrice = 0.0;
                    }
                    // P-UI-49d: THE OLD MECHANISM, restored under a guard. git
                    // says the drag was never ours: the old C-key/chart-click
                    // paths created the line `OBJPROP_SELECTED = true` and MT4
                    // moves the SELECTED object on each mouse move - that IS the
                    // movement the user remembers (commit 3a288fb removed that
                    // one write, and no per-object grab ever replaced it).
                    // Selecting here is safe where selecting at CREATION was not:
                    // the gesture is provably OURS (the press landed on the line),
                    // so MT4 has no foreign drag in flight to hijack, and the
                    // selection is dropped at this gesture's end through the same
                    // deferred latch. Written ONLY when the terminal did not
                    // already select it - a property write on an object MT4 is
                    // dragging cancels that drag (P-BK-15).
                    if(!terminalGrab)
                        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, true);
                    g_customPriceNativeDrag = true;   // owed clear at this gesture's button-up
                    // P-UI-53: and the GESTURE owns the view from here to the
                    // release - the chart behind the line must not pan under it.
                    CustomPriceDragLockOn();
                }
                else if(pressEdge || terminalGrab)
                {
                    // A press that is NOT ours starts somebody else's gesture
                    // (a pan, a box, the ring, a card): the line must not STAY
                    // SELECTED through it, or MT4 moves it with that drag -
                    // which is the interference this cycle started from.
                    // P-UI-96: `|| terminalGrab` - a stuck selection seen while
                    // the button is down arms the same drain even when the press
                    // edge was missed (release off-chart leaves s_dragDownSeen
                    // set, so the next press has no edge to arm on).
                    // P-UI-51: the clear is ARMED here, never WRITTEN. This hit
                    // test runs on the first MOVE after the press, already a few
                    // pixels away from it and further the faster the drag starts,
                    // so it can MISS a press the TERMINAL did pick up - and
                    // ClearCustomPriceSelection only ever writes while
                    // OBJPROP_SELECTED is true, i.e. exactly when the terminal is
                    // holding the line. Writing it then dropped MT4's own
                    // selection out of the drag that same press had just started:
                    // the gesture engaged and died on its first event - "the drag
                    // state is cut off very quickly", "it cannot be dragged".
                    // Deferring costs one bool store and keeps the promise: the
                    // latch is drained at the button-up by the one clear owner.
                    g_customPriceNativeDrag = true;
                    // P-UI-100 (2026-09-22): AND THE CLEAR IS ALSO WRITTEN HERE —
                    // everywhere it cannot touch a grab.
                    //
                    // Deferring is only needed for the one press that might BE a
                    // grab of this line (P-UI-51's lesson). Every other press —
                    // a pan, a panel, a box, MT4's own fib or rectangle drawn from
                    // somewhere else — has already been answered by the hit test
                    // above, and MT4 will carry the line through that whole gesture
                    // if it is still selected (the law P-UI-45/P-BK-26 measured).
                    // The witness is the SAME test the claim uses, with the same
                    // tolerance, and ours is the wider one (it covers the visible
                    // circle): a cursor that fails it is not a cursor MT4 picked
                    // the line up with, so the write cannot cancel anything.
                    bool onLineNow = (!UIPointerOverSurface((int)lparam, (int)dparam) &&
                                      CustomPriceGrabAt((int)lparam, (int)dparam));
                    if(!onLineNow) HandLinesSelectionGuard();
                }
            }
            if(g_customPriceLineDragging)
            {
                double currentLinePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                // P-UI-49c (P-BK-16's shape): while OUR gesture owns the line,
                // carry it - but ONLY while the terminal is NOT moving it: its
                // price still equals the grab price / our last write. A working
                // native drag keeps its price moving, this branch stands down and
                // the object is never rewritten mid-gesture (P-BK-15). Absolute
                // from the cursor (never incremental), so it converges exactly.
                // P-UI-51: the press edge's OWN move is the one event where the
                // frozen test below is meaningless - the line's price equals the
                // grab price by definition there, whether the terminal is about to
                // move it or never will. Writing on that event was the last way
                // our own carry could rewrite the object MT4 had just grabbed, so
                // the fallback starts one event later (a few ms; absolute from the
                // cursor, so it converges on the same price anyway).
                // P-UI-55: the slop fence and the delta. `cursorY` is compared with the
                // GRAB's pixel (Y only - an HLINE cannot be moved horizontally), so the
                // jitter of a click never opens this door; `wishPrice` is the grab price
                // plus the cursor's TRAVEL since the grab, never the cursor's price, so
                // the press offset survives and the line can never snap onto the cursor.
                int cursorY = (int)dparam;
                bool pastSlop = (MathAbs(cursorY - s_ownGrabY) >= CP_DRAG_SLOP);
                // P-UI-100b: AND THE CARRY STANDS DOWN THE MOMENT THE GESTURE IS
                // KNOWN TO BE A DRAW. `s_drawNotGrab` is set by the OBJECT_CREATE
                // detector when a foreign object appeared while this claim was live:
                // the terminal is drawing something, our press was its anchor, and
                // moving the line along with it is exactly the report. The release
                // then puts the line back (CustomPriceRestoreGrabPrice), so the
                // gesture ends with the price the user left behind either way.
                if(g_customPriceDragOwn && !pressEdge && pastSlop && !s_drawNotGrab &&
                   currentLinePrice > 0 && s_ownGrabCursorPrice > 0)
                {
                    double refPrice = (s_ownLastWrite > 0.0) ? s_ownLastWrite : s_ownGrabPrice;
                    if(MathAbs(currentLinePrice - refPrice) < _Point * 0.5)
                    {
                        int subW = 0; datetime curT = 0; double cursorPrice = 0.0;
                        if(ChartXYToTimePrice(0, (int)lparam, cursorY, subW, curT, cursorPrice) &&
                           cursorPrice > 0)
                        {
                            double wishPrice = s_ownGrabPrice + (cursorPrice - s_ownGrabCursorPrice);
                            if(wishPrice > 0 && MathAbs(wishPrice - currentLinePrice) > _Point * 0.5)
                            {
                                ObjectSetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, wishPrice);
                                s_ownLastWrite = wishPrice;
                                currentLinePrice = wishPrice;
                                CustomPriceMarkerSync();   // P-UI-98d: the dot rides the carry too
                            }
                        }
                    }
                }
                // P-UI-61: the STATE is no longer inside the frame's gate. The anchor
                // advances on EVERY event that moved the line - a lagging anchor is a
                // ladder drawn where the line is not - and only the FRAME is budgeted
                // (one owner, shared with the native-drag channel). A refused frame is
                // owed; the release and the next tick both pick the flag up.
                if(currentLinePrice > 0 && CustomPriceDragAnchorSet(currentLinePrice))
                    CustomPriceDragFrame(false);
            }
        }
        else
        {
            // P-UI-45/P-UI-48: the gesture is over - drop the selection a grab (or
            // a plain click on the line) left behind. A SELECTED line is moved by
            // MT4 on every LATER drag anywhere on the chart, which is what made it
            // fight the panels, the cards and the BaseKnot boxes. One bool read per
            // mouse-move; the clear runs once per gesture, through its one owner.
            // P-UI-99: the hold is gone — nothing to disarm here. The step-1
            // handle's gesture still ends at this latch: forced frame, deselect,
            // the view handed back. The custom-price flags below belong to a
            // different gesture and stay alone.
            // THE TRAVEL IS READ BEFORE THE SETTLE, and the settle clears the
            // carry's own write stamp - a gesture that wrote a price HAS travelled,
            // and asking after the settle would always answer "no".
            bool s1Wrote = (g_s1OwnLastWrite > 0.0);
            if(g_s1DragLive) Step1DragSettle();
            // P-UI-98e: the OTHER half of the click contract — the button-up that
            // ends a press which never TRAVELLED is a click on the handle, and the
            // row the press edge recorded names it. A press that travelled is a
            // drag (its settle already answered), and a motionless release that
            // emits no event here is caught by Step1ClickFinalize.
            if(g_s1ClickRow != "")
            {
                bool rowTravelled = s1Wrote ||
                                    (MathAbs((int)dparam - g_s1ClickRowY) >= CP_DRAG_SLOP);
                string row = g_s1ClickRow;
                g_s1ClickRow = "";
                if(!rowTravelled) Step1HandleClickAt(row);
            }
            // P-UI-98m: the SET line's own half - a press on its row that never
            // travelled is a click, and only a double of those re-arms (a single
            // is a no-op: already set). A motionless release emits no event
            // here and is caught by CustomPriceRearmFinalize instead.
            if(g_cpClickArmed)
            {
                bool cpTravelled = (MathAbs((int)dparam - g_cpClickY) >= CP_DRAG_SLOP);
                g_cpClickArmed = false;
                if(!cpTravelled) CustomPriceRearmClickAt();
            }
            if(g_customPriceNativeDrag)
            {
                g_customPriceNativeDrag = false;
                ClearCustomPriceSelection();
            }
            if(g_customPriceLineDragging) {
                g_customPriceLineDragging = false;
                g_customPriceDragOwn = false;
                // P-UI-53: the gesture is over - hand the view back EXACTLY as the
                // user had it (the props the lock saved at the grab).
                CustomPriceDragLockOff();
                // P-UI-54: A CLICK IS NOT A MOVE, AND A WIPE IS NOT A MOTION SIGNAL.
                //
                // Reported: "click the custom price line and every level is rebuilt
                // on the chart - it flickers". It was this branch: the settle raised
                // `g_forceClearOnNextDraw` UNCONDITIONALLY, and MT4 selects the line
                // on the press that clicks it, so our drag path engaged for a plain
                // CLICK as well - every single click therefore ran ClearAllLevels
                // (the whole family deleted) followed by the four-frame staged
                // rebuild of ~900 objects: the flicker, for a gesture that moved
                // NOTHING.
                //
                // The question the release must ask is "did this gesture move the
                // line?" - nothing else. If it did not, the picture on the chart is
                // already the one the user is looking at (the live follow re-asserted
                // it, and the geometry signature carries the start price since
                // P-UI-52), so the release owes no frame at all. If it did, the settle
                // is the in-place re-assert below - NOT a wipe: a wipe answers a
                // TOPOLOGY change (the start point's type, the mode, the timeframe),
                // never a price. That is also why the confirm paths keep theirs: they
                // really do change `g_thStartPointType`, which is in `levelSig`.
                // `s_ownGrabPrice` is the line's price when the gesture was grabbed
                // and `s_ownLastWrite` is set when WE carried it, so the test is exact
                // in both movement directions (the terminal's own drag and our carry).
                // P-UI-61: THE RELEASE SETTLES FROM THE OBJECT - the one value MT4
                // itself keeps exact - and it settles with a FRAME, never with a
                // re-anchor. `CustomPriceDragAnchorSet` is the only writer here and it
                // persists, so the frame's own resolver (P-UI-56) now answers with the
                // SAME price the anchor holds: its `priceMoved` branch can no longer
                // overwrite the gesture's result with an older key. That overwrite WAS
                // «وقتی خط را رها میکنم سطوح از یک جای دیگه رسم میشن» - the carry
                // channel never persisted, so the key held a pre-gesture price and the
                // settle rebuilt the whole ladder there.
                double settledPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                // P-UI-100b (2026-09-22): A DRAW IS NOT A DRAG, AND IT SETTLES BACK.
                //
                // This claim turned out to be the anchor of a DRAW the terminal was
                // performing (a fib, a rectangle — the OBJECT_CREATE detector saw the
                // object it made): the price under `settledPrice` is where the DRAW
                // ended, not where the user put the line, and every level derived from
                // it would move with it («کاستوم پرایس جابجا میشه»). The gesture is
                // rolled back to the price the grab found — the same number the claim
                // latched before it touched anything — through the one writer, which
                // re-anchors it, drops the selection the claim made and repaints.
                // The flag is cleared HERE, at the one place a claim ends, so a stale
                // one can never reach the next gesture.
                if(s_drawNotGrab)
                {
                    s_drawNotGrab = false;
                    CustomPriceRestoreGrabPrice();
                }
                else
                {
                bool movedByGesture = (s_ownLastWrite > 0.0) ||
                                      MathAbs(g_customTHStartPrice - s_ownGrabPrice) > _Point * 0.5 ||
                                      (settledPrice > 0.0 &&
                                       MathAbs(settledPrice - s_ownGrabPrice) > _Point * 0.5);
                if(movedByGesture)
                {
                    CustomPriceDragAnchorSet(settledPrice);
                    CustomPriceDragFrame(true);   // force: the gesture's last pixel is always painted
                    CustomPriceMarkerSync();      // P-UI-98d: the dot settles with the line
                    // P-UI-98d: stamp the echo — the OBJECT_CLICK MT4 reports at
                    // the end of this drag must not set the line the user just
                    // moved (the click that commits is a deliberate one later).
                    g_cpJustDraggedMs = GetTickCount();
                }
                else if(CustomPriceDragFrameOwed())
                {
                    // A click that moved nothing still owes nothing (P-UI-54), but a
                    // frame the throttle refused while the gesture was live is owed -
                    // and this is its last chance to be painted.
                    CustomPriceDragFrame(true);
                }
                // P-UI-49: the gesture is over - the button is UP, so NOW the
                // line may be written again. This is the release the tooltip is
                // owed to; nothing touches the line while it is being dragged.
                UpdateCustomPriceTooltip();
                }   // P-UI-100b: end of the "this gesture really moved the line" half
            }
        }
    }
}

#endif // EVENT_HANDLERS_ROUTER_GESTURE_MQH
