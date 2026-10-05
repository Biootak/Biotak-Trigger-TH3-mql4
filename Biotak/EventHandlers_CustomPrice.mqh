//+------------------------------------------------------------------+
//| EventHandlers_CustomPrice.mqh                                    |
//|                                                                  |
//| P-SIZE-1500 (2026-10-04) - the custom price line's own owner.     |
//|                                                                  |
//| Exact lines 942-1748 of EventHandlers_Init.mqh, moved verbatim,   |
//| zero renames: the line's construction (CreateCustomPriceLine),    |
//| the selection it drops, the marker census, the handset pair's     |
//| reveal/arms, the drag lock and its heal, the tooltip, and the     |
//| Hide/Show All surface.                                            |
//|                                                                  |
//| WHY IT PRECEDES EventHandlers_Init.mqh in the hub: this half      |
//| calls NOTHING in Init (measured: 0 calls), while Init calls in    |
//| (CreateCustomPriceLine, ResetHideAllState) - and MQL4 resolves a  |
//| call top-down, so this order owes no prototype and adds no        |
//| warning 46 (the cross-file prototypes elsewhere in the tree are   |
//| exactly the ones that order could not avoid).                     |
//+------------------------------------------------------------------+
#ifndef EVENT_HANDLERS_CUSTOMPRICE_MQH
#define EVENT_HANDLERS_CUSTOMPRICE_MQH

// Helper function to create custom price horizontal line (DRY)
//
// P-UI-48: THE LINE IS ALWAYS GRABBABLE. "Why doesn't it move like it used
// to?" - because P-UI-45 answered the interference report by making a SETTLED
// line non-SELECTABLE, and the drag IS that flag. The interference was never
// selectability; it was a SELECTION THAT OUTLIVED ITS GESTURE:
//
//   * MT4 moves the SELECTED object on every later drag ANYWHERE on the chart,
//     so a line that stayed SELECTED was dragged along with the panel cards and
//     the BaseKnot boxes and kept re-anchoring the TH start price behind the
//     user's back;
//   * the old code wrote OBJPROP_SELECTED = true at creation, so this was the
//     line's state BEFORE any gesture of its own.
//
// So the flag pair is now: SELECTABLE true, ALWAYS (this is the movement), and
// SELECTED false, ALWAYS - MT4 selects the line ITSELF on the press that means
// to grab it (that is the moment the live-drag path polls for), and the
// selection it makes is dropped again on button-up (see
// ClearCustomPriceSelection + g_customPriceNativeDrag). Pre-selecting only ever
// enabled the hijack, and never selecting leaves the line as inert as it was
// before - both wrong. One wording for the tooltip too: every state of the line
// can be dragged and confirmed now, so a "PIN button to move" text would be a
// lie in the one place the user reads it.
bool CreateCustomPriceLine(double price, int digits,
                           string tooltipSuffix = "Drag to adjust, Double-click to confirm")
{
    if(ObjectFind(0, g_customPriceHorizontalLineName) < 0) {
        if(!ObjectCreate(0, g_customPriceHorizontalLineName, OBJ_HLINE, 0, 0, price)) {
            _LOG_GATE_E Print("[E][GEN] Failed to create custom price line. Error: ", GetLastError());
            g_customPriceLineCreated = false;
            return false;
        }
    } else {
        ObjectSetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, price);
    }
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_COLOR, GetCustomPriceRenderColor());
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_WIDTH, inpCustomPriceLevelWidth);
    // P-UI-98d: SELECTABLE follows the ARMED/SET state now — an armed line
    // drags (this IS the movement, P-UI-48), a set line is inert so no gesture
    // of any other object can steal it. The transitions go through the ONE
    // owner (CustomPriceLineOwnArm); this writer only re-asserts the state.
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, g_cpLineArmed);
    // P-UI-98p: the line is NEVER painted - the green circle is the placement
    // (user order: «خط ابی کاستوم پرایس لازم نیست همین دایره سبز کفایت
    // میکنه»). The object stays (the drag math, the grab test and the ladder
    // anchor all read it), only its picture goes. Skipped mid-gesture like
    // the selection above (P-BK-15); the transitions re-assert below.
    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&
       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    // P-UI-45/P-UI-50: never LEAVE a selection in place - a line saved into the chart
    // profile arrives SELECTED, and MT4 then moves it along with every LATER gesture
    // anywhere on the chart (the interference P-UI-45 removed) - but never write it
    // while a gesture is live. This creator is reached from the click that confirms
    // the price, and that click can arrive while the button is still DOWN: a write on
    // the object MT4 is dragging cancels that drag (P-BK-15), which is the "the drag
    // is cut off very quickly" report. So it is a compare-and-write, skipped for the
    // whole duration of a gesture: one guarded read per call, and this creator only
    // runs on init / restore / mode change, never per frame.
    if(!g_customPriceLineDragging && !g_customPriceNativeDrag &&
       (bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED))
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_ZORDER, Z_CHART_LABEL);   // P-UI-31
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP,
                  "[PIN] Custom Price: " + DoubleToString(price, digits) + " | " + tooltipSuffix);
    g_customPriceLineCreated = true;
    CustomPriceMarkerSync();   // P-UI-98d: the green dot rides the line's own writer
    return true;
}

// P-UI-48: the ONE owner of "drop the line's selection". MT4 selects a
// SELECTABLE object on the press that grabs it, and a selection that SURVIVES
// its gesture lets MT4 drag the line along with every later drag anywhere on the
// chart - the interference P-UI-45 removed by removing the movement. It is
// called from the button-up latch (the grab/click is over) AND from the UI press
// path (the press belonged to a panel or the ring, so the terminal's selection
// of the line must not outlive it). Guarded by the read: a no-op costs one
// ObjectGetInteger, and the write happens once per gesture.
void ClearCustomPriceSelection()
{
    if(!g_customPriceLineCreated) return;
    if(!(bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED)) return;
    ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTED, false);
}

//==============================================================================
// P-UI-98d — THE ARMED/SET MODEL OF THE TWO HAND-SET LINES, AND THEIR MARKERS.
//
// User order: «خط کاستوم پرایس و خط step اول وقتی بعد جابجایی روش کلیک شد ست
// نهایی بشه و با دبل کلیک فعال بشه؛ تا زمانی که ست نهایی نشده آزادنه درگ بشه»
// and the marker order: «نشانهٔ رنگی (خط کاستوم سبز، step اول قرمز)، یک نشانه
// باشه که خیلی مزاحم هم نباشه» + «وقتی لاین ها رو خاموش میکنم نشان ها هم نباشه».
//
// ARMED: the line answers MT4's own drag, and ONE small dot at the chart's
// right edge marks it (green for the custom price line, red for the step-1
// handles; time-0 anchoring — the pip labels' own — so it follows the market
// with no per-bar write). SET: the line is inert — nothing can grab it, which
// is also the "dragging other objects must not steal it" half — and the dot is
// DELETED, not masked, so no other mask writer can resurrect it. A single
// click sets; a double-click re-arms. The single click waits out the
// double-click window in the pending slot (the sweep commits it), so the first
// click of a double never sets first.
//
// The markers obey the LINES switch (g_linesVisible) and the hide-all state —
// «فقط لاین ها» — and are re-owned by the same passes that already run (the
// render for the step-1 dots, this sync for the custom line's).
// P-UI-98g (2026-09-22): they also obey the REVEAL latch — «فقط وقتی روش کلیک
// کردیم دایره ها بیاد برای درگ کردن» — so an armed-but-unasked line keeps its
// circle parked.
//==============================================================================
void CustomPriceMarkerSync()
{
    // P-UI-98o: the green circle ignores the LINES switch - it marks the
    // custom price placement itself, not the line family, so L hides the
    // lines and the red circles but never it (hide-all still does it).
    // P-UI-98p: the line itself is never painted at all - the circle below
    // is the whole face of the placement.
    // P-UI-151 (2026-10-02): AND THAT FACE IS NOW THE REVEAL LATCH'S, EXACTLY
    // LIKE THE RED PAIR'S. User order: «این دایریه سبز اینطوری میمونه بد ...
    // وقتی کلیک شد جای دیگه پنهان بشه و وقتی روش کلیک شد دیده بشه». P-UI-98q
    // had the green circle up for as long as the placement lived, so the one
    // face of an invisible line (P-UI-98p) sat on the chart for ever. The
    // latch below is the SAME question the red circles answer through
    // `Step1HandleOwnFace` (P-UI-98g) - "the user asked for this marker" -
    // so ONE rule now serves every handset circle: a click that lands on a
    // marker reveals it, a click that lands on neither drops both
    // (`HandsetRevealDropOnForeignClick`), and a fresh placement is born
    // revealed because the click that asked for it IS the asking click
    // (`HandsetPlacementArm`).
    bool show = g_customPriceLineCreated &&
                g_cpHandleShown &&
                !IsIndicatorHidden() &&
                g_thStartPointType == TH_START_POINT_CUSTOM_PRICE;
    if(!show)
    {
        HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
        return;
    }
    double price = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(!(price > 0.0) || !MathIsValidNumber(price))
    {
        HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
        return;
    }
    // the circular drag handle, centred on the line at the screen's middle
    HandsetHandleAt(g_cpMarkerName, price, CP_HANDLE_RES);
    // P-UI-98p: the line is never painted, so its circle carries the hover
    // text in both states. Guarded: one string compare, a write only on drift.
    {
        static string s_cpMarkTip = "";
        string tip = g_cpLineArmed
            ? "Custom price: drag the green circle - click to commit, double-click re-arms"
            : "Custom price (set) - double-click to re-activate";
        if(s_cpMarkTip != tip)
        {
            s_cpMarkTip = tip;
            ObjectSetString(0, g_cpMarkerName, OBJPROP_TOOLTIP, tip);
        }
    }
}

// P-UI-98d v2: the ride channel. A pan, a zoom or a window resize moves the
// price scale under the handles — the same stream the leg meter's discs ride
// (P-LM-16b): every MOUSE_MOVE / CHART_CHANGE re-projects, guarded (a still
// chart costs reads only, a write lands only on drift). The step-1 prices are
// the render's own answers, stashed by the face owner — and OUTSIDE the
// custom-price mode the stash is a stale answer, so the red handles park (a
// resurrected handle over a mode that no longer owns a ladder is the bug).
void HandsetMarkersRide()
{
    CustomPriceMarkerSync();
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE)
    {
        HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
        HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
        return;
    }
    // P-UI-98e: the icon belongs to the ARMED pair: the price stash now also
    // carries a SET handle's address (the click contract needs it), so the ride
    // is what must not resurrect an icon over a line nothing can grab.
    // P-UI-98l: and the ride obeys the LINES switch and the hide-all state
    // like every other marker owner (CustomPriceMarkerSync, the face owner) -
    // without these terms the L key parked the circles through the render and
    // the very next mouse move put them back («لاین خاموش میکنم دایره هاش
    // میمونه»).
    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkAbovePrice > 0.0 && g_linesVisible && !IsIndicatorHidden())
        HandsetHandleAt(S1MarkName(1), g_s1MarkAbovePrice, S1_HANDLE_RES);
    else
        HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
    if(g_s1LinesArmed && g_s1HandleShown && g_s1MarkBelowPrice > 0.0 && g_linesVisible && !IsIndicatorHidden())
        HandsetHandleAt(S1MarkName(-1), g_s1MarkBelowPrice, S1_HANDLE_RES);
    else
        HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
}

//==============================================================================
// P-UI-151 (2026-10-02) — ONE REVEAL ARCHITECTURE FOR EVERY HANDSET CIRCLE.
//
// User order: «این دایریه سبز اینطوری میمونه بد ... وقتی کلیک شد جای دیگه پنهان
// بشه و وقتی روش کلیک شد دیده بشه» and, on the shape of the code itself, «بهترین
// معماری درست کن دیگه چون که من کدها رو محدودیت هاشو نمیدونم چطوریه».
//
// P-UI-149 had answered HALF of it (the red pair's reveal was temporary) by
// hard-coding the exceptions into the drop owner: a click on a rung-1 row was
// "the pair's", a click on the custom price row was "the anchor's", and the GREEN
// latch was neither read nor written. That is two rules pretending to be one, and
// it is exactly the shape that leaves a "staying" circle behind (the green one,
// by the user's own report). The question the click edge must answer is ONE
// question — "did this click land on a handset marker?" — and each marker answers
// it with its own hit test:
//
//   * the custom price row (or the 19 px green circle drawn on it):
//     `CustomPriceGrabAt`, the drag's own tolerance (P-UI-98q);
//   * a rung-1 row (or the 15 px red circle drawn on it): `Step1HandleUnderCursor`,
//     which already refuses a hidden/off ladder and another timeframe's stash.
//
//   `HandsetMarkerRevealAt` is that question, and it is the ONLY reveal writer on
//   this edge; `HandsetRevealDropOnForeignClick` is its sibling and the ONLY drop
//   writer: a click that lands on no marker gives BOTH reveals back, and a live
//   hand keeps its circles through the gesture flags. (The other reveal writers
//   are the ones that already exist off a press: the claim a hand makes on either
//   line — P-UI-98g — and the armed single-click contract. They stay: a hand on
//   the line IS the request.)
//
//   The PLACEMENT is exempt, and it has to be: while `g_waitingForCustomPriceClick`
//   is up the user is picking the price, so the click that settles it lands on
//   empty chart BY DESIGN (the line still sits at the screen's middle, C key /
//   ring PIN) — dropping the reveal there would hide the circle in the very
//   gesture that asked for it, and `CreateCustomPriceLine` at the end of that
//   path would then paint nothing at all.
//
// Cost: the click edge only. One completed click in custom-price mode runs at
// most two hit tests (each one `ChartXYToTimePrice` plus a couple of reads) and
// writes only when the answer CHANGED — an unrevealed pair costs the two tests
// and no write, a revealed one that keeps its circle costs the same. The button
// probe is the project's ONE witness (UILeftButtonUp, P-UI-73), so a CLICK the
// terminal delivers on the PRESS — the measured twin transport — answers nothing
// and the real release still decides.
//==============================================================================
bool HandsetMarkerRevealAt(const int x, const int y)
{
    if(g_customPriceLineCreated && CustomPriceGrabAt(x, y))
    {
        if(!g_cpHandleShown)
        {
            g_cpHandleShown = true;
            CustomPriceMarkerSync();
            ThrottledChartRedraw();
        }
        return true;   // the placement's own row: the click belongs to it
    }
    string row = "";
    if(Step1HandleUnderCursor(x, y, row))
    {
        if(!g_s1HandleShown)
        {
            g_s1HandleShown = true;
            HandsetMarkersRide();
            ThrottledChartRedraw();
        }
        return true;   // the pair's own row: the click belongs to it
    }
    return false;
}

void HandsetRevealDropOnForeignClick(const int x, const int y)
{
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return;
    if(g_waitingForCustomPriceClick) return;          // a placement in progress owns its markers
    if(g_s1DragLive || g_s1OwnActive || g_customPriceLineDragging) return;   // a live hand keeps its circles
    if(!UILeftButtonUp()) return;                     // the press's own echo (P-UI-73)
    // THE CLICK'S OWN QUESTION FIRST. It runs unconditionally on this edge (not
    // behind a `!shown` guard) because the reveal has to reach a pair that is
    // NOT up yet: a click delivered only on the release never saw the press
    // edge, and `shown` is false exactly then. The two hit tests are the price.
    if(HandsetMarkerRevealAt(x, y)) return;           // a marker's own click: nothing is dropped
    if(!g_cpHandleShown && !g_s1HandleShown) return;  // nothing revealed: nothing to drop
    g_cpHandleShown = false;
    g_s1HandleShown = false;
    HandsetMarkersRide();   // one ride parks the green dot and both red circles
    ThrottledChartRedraw();
}

// P-UI-98e: A FRESH PLACEMENT IS BORN ARMED. The activation (the C key, the ring
// PIN) deletes the line and creates a new one at the screen's middle; the
// armed/set state is per PLACEMENT (P-UI-98d), so the new one must wake
// draggable even when the user had SET the previous line — otherwise the very
// first gesture on the fresh line is refused, and «قابل درگ کردن نیستش» returns
// for a second reason (the state, not the drag channel). ONE owner, called by
// both activation paths, so the two can never disagree about what "fresh" means.
void HandsetPlacementArm()
{
    g_cpLineArmed  = true;
    g_s1LinesArmed = true;
    g_cpSetPending = "";   g_cpSetPendingMs = 0;
    g_s1SetPending = "";   g_s1SetPendingMs = 0;
    // P-UI-98m: no re-arm candidate survives into a fresh placement.
    g_cpClickArmed = false;   g_cpClickY = 0;
    // P-UI-98g: the RED circles are born HIDDEN - a rung-1 row is a painted
    // line, so the pair is one click away from being asked for, and the
    // tooltip says so.
    g_s1HandleShown = false;
    // P-UI-151: THE GREEN CIRCLE IS BORN REVEALED, because the line it marks is
    // NEVER PAINTED (P-UI-98p) - it is the placement's whole face, and hiding it
    // here would leave the user staring at a chart with no custom price on it at
    // all after the very gesture that asked for one. The C key / ring PIN press
    // IS the asking click (same rule as everywhere else: a marker appears when
    // the user asks for it), and the first click that lands on neither marker
    // takes it away (`HandsetRevealDropOnForeignClick`).
    g_cpHandleShown = true;
}

// The ONE owner of an armed/set TRANSITION of the custom price line. Guarded
// writes: never mid-gesture (P-BK-15), never on drift.
void CustomPriceLineOwnArm(const bool armed)
{
    // P-UI-101 (2026-09-22): A LOCKED LINE NEVER ARMS. The lock's promise is
    // «nothing moves it until I say so», and every way of grabbing this line runs
    // through this flag — the claim asks it first (P-UI-98d), the creator
    // publishes it as SELECTABLE, the double-click re-arm sets it. So the lock is
    // enforced HERE, in the one owner of the state, and not in a copy of the test
    // at each of those three places. (`want`, not `armed`: the parameter is const
    // by this function's own signature, and a lock is a REFUSAL, not a rewrite of
    // what the caller asked for.)
    bool want = (armed && !g_customPriceLocked);
    g_cpLineArmed = want;
    g_cpSetPending = "";
    g_cpSetPendingMs = 0;
    if(!g_customPriceLineCreated) return;
    if(g_customPriceLineDragging || g_customPriceNativeDrag) return;
    if((bool)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE) != want)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_SELECTABLE, want);
    if(!want) ClearCustomPriceSelection();
    // P-UI-98p: the mask is re-asserted, never lifted - the line is never
    // painted (see the creator), the green circle is the placement.
    if(ObjectFind(0, g_customPriceHorizontalLineName) >= 0 &&
       (long)ObjectGetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
    UpdateCustomPriceTooltip();   // the wording follows the state
    CustomPriceMarkerSync();
}

// P-UI-101 (2026-09-22) — THE PLACEMENT'S OWN LOCK, ONE OWNER.
//
// User order: «روی خط کاستوم پرایس که هولد کردم پنل تنظیماتش بازه بشه و بشه از
// اونجا قفلش کرد». The lock is not the armed/set state (P-UI-98d): SET is one
// click away from being undone (a double-click re-arms it), while the lock is
// released only from the panel. It is persisted with the placement, because the
// placement survives a re-attach and a lock that did not would be a lie after
// every recompile.
//
// The transition writes through the state owners, never around them: the armed
// owner (which is also the ONE enforcement point — see its own note) and the
// tooltip. A locked line is inert exactly like a SET one, so every law this
// project already measured for SET — no claim, no selection, no carry, no ride
// along with any foreign gesture — holds for it unchanged.
void CustomPriceLineOwnLock(const bool locked)
{
    if(g_customPriceLocked == locked) return;   // never write a state you would not change
    g_customPriceLocked = locked;
    CustomPriceLineOwnArm(!locked);             // locked = inert · unlocked = draggable again
    RuntimeSettingsSaveOverridesThrottled();    // the placement's lock outlives the session
}

//==============================================================================
// P-UI-98m — RE-ARMING A MASKED (SET) CUSTOM PRICE LINE (2026-09-22).
//
// User order: «وقتی سلکت نیس فقط همون دایره سبز بمونه ... خطو نشون نده».
// A masked line fires no OBJECT_CLICK, so the line's own click contract (which
// lives on that event) cannot wake it. The press edge still sees the row -
// CustomPriceGrabAt reads the object, masked or not - so the SET click is one
// owner reached from three edges, the step-1 shape: our own press/release
// pair on the mouse stream, the button-up finalize below (a motionless
// release emits no MOUSE_MOVE, P-BK-03), and the green circle's own
// OBJECT_CLICK. One physical click can reach it twice; a 60 ms twin guard
// drops the second. A single click here is a no-op (already set) and only a
// double re-arms, so no sweep slot is needed - the first click of a double
// can never commit anything.
//==============================================================================
void CustomPriceRearmClickAt()
{
    if(g_cpLineArmed) return;   // armed clicks belong to the line's own contract
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return;
    if(!g_customPriceLineCreated || ObjectFind(0, g_customPriceHorizontalLineName) < 0)
    {
        g_cpClickArmed = false;
        return;
    }
    uint now = GetTickCount();
    if(g_cpClickHandledMs != 0 && now - g_cpClickHandledMs < 60) return;   // the same click's twin event
    g_cpClickHandledMs = now;
    bool dbl = (g_cpClickLastMs != 0 && now - g_cpClickLastMs < DOUBLE_CLICK_THRESHOLD_MS);
    g_cpClickLastMs = now;
    if(!dbl) return;
    CustomPriceLineOwnArm(true);
    g_cpHandleShown = true;
    CustomPriceMarkerSync();
    ThrottledChartRedraw();
}

// The button-up that carries no move (P-BK-03): a motionless press/release on
// the SET line's row is a click, and only a double of those re-arms.
void CustomPriceRearmFinalize()
{
    if(!UILeftButtonUp()) return;   // the press's own echo (P-UI-73): keep the row for the real release
    if(!g_cpClickArmed) return;
    g_cpClickArmed = false;
    CustomPriceRearmClickAt();
}

// The double-click window's own sweeper: a single click that stayed single
// commits the SET here. Skipped while ANY handset gesture is live — the click
// that opened a drag must not set the line under the user's hand.
void HandsetClickSweep()
{
    uint now = GetTickCount();
    // P-UI-98h: a COMMIT happens with the button FREE. Both click transports
    // can arrive on the PRESS, so a pending slot may be waiting while the user
    // is still holding - the probe keeps it pending instead of committing a
    // SET under a hand that has not let go yet (and may still drag).
    if(g_cpSetPendingMs != 0 && now - g_cpSetPendingMs >= DOUBLE_CLICK_THRESHOLD_MS
       && UILeftButtonUp())
    {
        g_cpSetPendingMs = 0;
        g_cpSetPending = "";
        if(g_cpLineArmed)
        {
            CustomPriceLineOwnArm(false);
            g_cpHandleShown = false;   // P-UI-98g: SET takes the green circle away
            CustomPriceMarkerSync();
        }
    }
    if(g_s1SetPendingMs != 0 && now - g_s1SetPendingMs >= DOUBLE_CLICK_THRESHOLD_MS
       && UILeftButtonUp())
    {
        g_s1SetPendingMs = 0;
        g_s1SetPending = "";
        if(g_s1LinesArmed && !g_s1DragLive)
        {
            g_s1LinesArmed = false;   // SET: the factor stays, the ladder keeps the step
            g_s1HandleShown = false;  // P-UI-98g: nothing points at a set line
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);   // the face owner re-owns selectability + parks the dot
        }
    }
}

//==============================================================================
// P-UI-53 — THE DRAG OWNS THE VIEW UNTIL THE RELEASE.
//
// Reported: "while dragging, the chart behind scrolls/pans and the drag breaks -
// lock or prepare the chart during the drag". The line's movement is MT4's own
// native object drag; the chart underneath stays live, so a gesture that wanders
// past the line - and CHART_MOUSE_SCROLL is ENABLED BY DEFAULT - pans the view.
// The price scale then slides under the cursor and MT4 answers the pan by moving
// the dragged object against a rebased price: the line jumps, the drag dies, or
// it never engages at all. BaseKnot already lives with this and solved it
// (`BaseKnotLockChart` + P-BK-14 "the drag owns the view until release"), with RAW
// Chart* calls so the Lite build compiles without the UI module. This is the same
// lock, same shape, for the line, in the same domain layer.
//
// P-UI-90 (2026-09-15) superseded the fourth bullet's "remembers what the user
// had" and the sentence that closed this block: the capture moved to ONE owner,
// because four private copies of it (this one, BaseKnot's, the panels' and the
// watchdog's) read the props while somebody ELSE held the lock and recorded our
// own `false` as the user's - so the last release wrote `false` back and the
// chart stayed scroll-locked until re-attach, and after Remove too. The lock's
// SHAPE is unchanged: the grab takes it, every throttled step re-asserts it, the
// button-up hands it back, the watchdog heals a release that never arrived, and
// OnDeinit releases it for EVERY reason. Only the bookkeeping moved.
//
// Four owners keep it honest:
//   * the GRAB takes it (once per gesture; `ChartViewLockAcquire` remembers what
//     the user had, and only at the moment NO owner holds the lock);
//   * every throttled drag step RE-ASSERTS it - read-guarded, a write only on
//     drift, because third writers (a panel closing, a watchdog restore, a
//     template reset) can flip the props back while the button is still down;
//   * the BUTTON-UP releases it (`ChartViewLockRelease` restores the user's pair,
//     and only on the LAST release - never a blind true);
//   * a watchdog heals a release that never arrived (off-window release, lost
//     focus): the P-BK-03 trap - no mouse move, so no release event either.
// CHART_AUTOSCROLL is held down too while we own the view: a tick sliding the
// scale mid-drag moves the line with it (BaseKnot makes the same call).
// OnDeinit releases it for EVERY reason (`ChartViewLockForceRelease` is the net),
// so a stale lock can never outlive the instance.
//==============================================================================
static bool s_cpChartLocked = false;
// P-UI-90: this owner no longer SAVES the scroll / context-menu pair. Its own
// capture could be taken while the Base/Knot tool (or the panels) already held
// the lock, so it recorded OUR `false` as "what the user had" and wrote it back
// on release - one of the four writers behind the chart that stayed scroll-locked
// for the life of the terminal. `ChartViewLock*` (GlobalVariables) is the single
// owner of that capture/restore now; AUTOSCROLL stays here because nothing else
// ratchets it (both writers only restore what they saw).
static bool s_cpAutoWas     = true;
static uint s_cpLockActMs   = 0;       // last activity of the owning gesture

bool CustomPriceDragLocked() { return s_cpChartLocked; }

void CustomPriceDragLockOn()
{
    if(!s_cpChartLocked)
    {
        s_cpAutoWas   = (ChartGetInteger(0, CHART_AUTOSCROLL) != 0);
        s_cpChartLocked = true;
        ChartViewLockAcquire();   // P-UI-90: scroll + context menu have ONE owner
    }
    else ChartViewLockAssert();
    if(s_cpAutoWas && (ChartGetInteger(0, CHART_AUTOSCROLL) != 0))
        ChartSetInteger(0, CHART_AUTOSCROLL, false);
    // P-UI-106 (2026-09-23): CHART_CONTEXT_MENU is a stub on this build
    // (CTXMENU-OFF) - writing it costs a repaint for zero effect, so it is
    // not written any more.
    s_cpLockActMs = GetTickCount();
}

void CustomPriceDragReassertLock()
{
    if(!s_cpChartLocked) return;
    s_cpLockActMs = GetTickCount();
    ChartViewLockAssert();   // P-UI-90: read-guarded, one owner for scroll + ctx
    if(s_cpAutoWas && ChartGetInteger(0, CHART_AUTOSCROLL) != 0)
    { ChartSetInteger(0, CHART_AUTOSCROLL, false); }
    // P-UI-106: stub write retired (see CustomPriceDragLockOn above).
}

void CustomPriceDragLockOff()
{
    if(!s_cpChartLocked) return;
    ChartViewLockRelease();   // P-UI-90: hands the view back only when NO owner is left
    if(s_cpAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, true);
    s_cpChartLocked = false;
}

// The P-BK-03 net (shape: BaseKnotSyncBadges' own stale-drag heal): a press whose
// release emits NO mouse move cannot be ended by the gesture path, so the lock (and
// the gesture flags) are healed here once the button is provably up and nothing has
// moved for 1.5 s. Cost in steady state: the caller reads one bool; the KEYSTATE
// probe runs only while a lock is actually held.
void CustomPriceDragHealStale()
{
    if(!s_cpChartLocked) return;
    if(GetTickCount() - s_cpLockActMs <= 1500) return;                     // a live drag keeps producing events
    if(!UILeftButtonUp()) return;             // still holding the button (one owner, P-UI-73)
    CustomPriceDragLockOff();
    g_customPriceLineDragging = false;
    g_customPriceDragOwn = false;
    // P-UI-98: a step-1 gesture whose release never arrived heals the same way —
    // the flags drop and the handle's selection goes (a stuck g_s1DragLive would
    // pin the handle's price forever, since the render skips its writes while the
    // flag is up). No forced frame here: the owed-frame machinery and the next
    // natural frame re-assert the picture.
    if(g_s1DragLive)
    {
        g_s1DragLive = false;
        // P-UI-98e: the carry's own state heals with the gesture's flags - a
        // live g_s1OwnActive on a healed drag would keep the held-move pass
        // reading a cursor that is no longer dragging anything. P-UI-98f: it is
        // the SAME owner the settle uses - this path used to leave the echo
        // stamp's base and the press baseline behind, and the next gesture read
        // them as its own.
        Step1GestureStateClear();
        // P-UI-98e: the borrow heals with the gesture - the face owner's next
        // frame writes the truthful flag (armed means grabbable).
        g_s1OwnBorrowed = false;
        // and a press whose release was lost is a GESTURE, never a click: the
        // candidate dies here so no later CHARTEVENT_CLICK can SET the line the
        // user had been dragging.
        g_s1ClickRow = "";
        string s1HealName = g_s1DragName;
        g_s1DragName = "";
        if(s1HealName != "" && (bool)ObjectGetInteger(0, s1HealName, OBJPROP_SELECTED))
            ObjectSetInteger(0, s1HealName, OBJPROP_SELECTED, false);
    }
}

//==============================================================================
// P-UI-98j — THE STEP-1 PAIR HEALS ITSELF (2026-09-22).
//
// Reported: «بعضی وقتا این خطش ناپدید میشه step و دیگه نمیشه جابجاش کرد ...
// تایم بالا میریم دوباره درست میشه». The shape is exact: a stashed handle
// whose OBJECT is gone. The stash - and the red circle riding it - survives,
// the claim refuses (ObjectFind < 0, P-UI-98e), and nothing re-creates the
// line: steady-state frames are sealed by the geometry signature (the levels
// block only runs on `g_redrawTHLevelsNeeded || g_buildStage != 0`), and the
// external-delete self-heal in OnChartEventHandler only fires when the delete
// event is NOT suppressed - a delete landing inside our own 250 ms
// post-delete suppression window is ignored, the cache keeps vouching for a
// name the chart no longer carries, and the picture stays wrong until
// something unrelated rebuilds (a TF switch does it for real: OnInit bumps
// the epoch, resets the absent table and rebuilds the whole family).
//
// The net is this function, called from the tick path beside
// CustomPriceDragHealStale (throttled to S1_HEAL_MS; reads-only while
// healthy): in custom-price mode, armed, same-TF stash, no live gesture and
// no rebuild in flight, a stashed handle whose price sits inside the RAW
// visible window but whose object is gone arms the delete branch's own two
// lines (redraw flag + generation bump) - an in-place re-assert, never a
// wipe. The raw window (not the ±25% cull window) is the proof the line must
// be painted: anything on screen is inside every cull window by construction
// (P-PERF-04's margin covers the hysteresis band), so a correctly culled
// off-screen line can never trip it, and a line the build legitimately
// dropped has no stash to trip it with.
//==============================================================================
#define S1_HEAL_MS 2000
void Step1HandleHealMissing()
{
    if(g_thStartPointType != TH_START_POINT_CUSTOM_PRICE) return;
    if(!g_s1LinesArmed || g_s1DragLive) return;
    if(IsIndicatorHidden() || !g_linesVisible) return;
    if(g_s1MarkPeriod != Period()) return;
    if(g_buildStage != 0 || g_forceClearOnNextDraw) return;
    static uint s_s1HealLastMs = 0;
    uint now = GetTickCount();
    if(s_s1HealLastMs != 0 && now - s_s1HealLastMs < S1_HEAL_MS) return;
    s_s1HealLastMs = now;
    double wMax = WindowPriceMax();
    double wMin = WindowPriceMin();
    if(!(wMax > wMin)) return;   // no window known: do not guess
    bool missing = false;
    if(g_s1MarkAboveName != "" && g_s1MarkAbovePrice >= wMin && g_s1MarkAbovePrice <= wMax &&
       ObjectFind(0, g_s1MarkAboveName) < 0)
        missing = true;
    if(!missing && g_s1MarkBelowName != "" && g_s1MarkBelowPrice >= wMin && g_s1MarkBelowPrice <= wMax &&
       ObjectFind(0, g_s1MarkBelowName) < 0)
        missing = true;
    if(!missing) return;
    // A stashed handle the chart should paint but does not carry: the stored
    // geometry no longer describes the chart, so the next frame rebuilds for
    // real and the render re-creates it in place. No wipe - a wipe answers a
    // topology change, never a hole.
    g_redrawTHLevelsNeeded = true;
    MarkDrawGeneration();
}

// P-UI-49: the ONE owner of the line's drag TOOLTIP TEXT. It used to be written
// in the drag handler itself, i.e. on EVERY step of a native drag - and MT4
// CANCELS an in-progress native drag when the dragged object is rewritten
// mid-gesture (P-BK-15's rule, learned on the BaseKnot box: the pump "snapped
// the box back to the drag start"; the level-family follow obeys it too -
// "never a full Sync per step, its style/tooltip rewrites lagged children behind
// the native BOX"). While the line was created pre-SELECTED the movement came
// from the SELECTION (MT4 moves every selected object on each mouse-move), so
// that write was invisible; the moment P-UI-45/48 moved the movement onto the
// PER-OBJECT native drag it cancelled the very gesture it was decorating and the
// line stopped following the cursor - the reported "the custom price line cannot
// be dragged". So the line is written ONCE per gesture, from the release, and
// NOTHING touches it while the button is down. Cost: fewer writes than before
// (one per gesture instead of one per drag step), no per-frame work.
void UpdateCustomPriceTooltip()
{
    if(!g_customPriceLineCreated) return;
    // P-UI-98g: the wording follows the state the user is actually in — an armed
    // line whose handle is not up yet asks for the click that brings it up.
    string text = g_waitingForCustomPriceClick
                  ? "Current price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Double-click to confirm"
                  : (g_cpLineArmed
                     ? (g_cpHandleShown
                        ? "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Drag the green handle, click to commit"
                        : "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Click it to bring up the green handle")
                     : "Custom TH start price: " + DoubleToString(g_customTHStartPrice, Digits) + " - Set. Double-click to re-arm");
    ObjectSetString(0, g_customPriceHorizontalLineName, OBJPROP_TOOLTIP, text);
}

// P-UI-49c: the gesture's own bookkeeping. `s_ownGrabPrice` is the line's price
// when the grab started and `s_ownLastWrite` the last price WE wrote; they are
// what tells a working native drag (the terminal's price moves on its own - we
// then touch nothing, P-BK-15) from a frozen one (it does not - we carry it).
static double s_ownGrabPrice = 0.0;
static double s_ownLastWrite = 0.0;

// P-UI-100b (2026-09-22): THE DRAW THAT LOOKED LIKE A GRAB.
//
// A press that lands ON the custom price line is claimed by us and P-UI-49d
// hands the movement to the terminal - correct for a GRAB, wrong for a DRAW: with
// MT4's fib tool armed, the same press starts a fib and the line we just selected
// is carried to the fib's other end («وقتی فیو یا باکس از همون محل میکشم کاستوم
// پرایس جابجا میشه»). At the press the two are indistinguishable, so the answer
// is the OUTCOME, and the outcome is an OBJECT: a gesture of ours never CREATES
// one, and the terminal's own drawing tools always do. Two witnesses, both fed by
// the one detector in OnChartEventHandler:
//   * `s_cpForeignDrawUntil` — the WINDOW a foreign create opens. The claim asks
//     it at the press edge: a draw that was already under way (MT4 creates a
//     drawn object on the press) is refused before it can move anything at all.
//   * `s_drawNotGrab`     — THIS GESTURE is a draw, not a grab. Set only while a
//     claim of ours is live; it stands the carry down and the release puts the
//     line back. ONE flag for BOTH hand-set lines: a claim of the step-1 pair and
//     a claim of the custom price line are mutually exclusive (one cursor, one
//     gesture — the step claim runs first and the other yields), so there is never
//     a second gesture for it to describe, and each settle clears it.
static uint s_cpForeignDrawUntil = 0;   // the deadline a foreign create opens
static bool s_drawNotGrab      = false;  // the live gesture turned out to be a draw
#define CP_DRAW_WITNESS_MS 600       // how long a foreign create disqualifies a claim

// P-UI-55: THE PRESS LATCH FOR OUR OWN CARRY, IN PIXELS.
//
// Reported with two screenshots: "I CLICK the line - I did not move it - and every
// level lands somewhere else: 1.15697 becomes 1.15705." Eight points on a 5-digit
// chart is ~1.6 px, which is the hit tolerance itself. The carry used to be
// ABSOLUTE TO THE CURSOR and it engaged on ANY button-down mouse move after the
// press edge, so the one-pixel jitter of a CLICK was enough to hand the line the
// cursor's price: the press had landed ~2 px off the line (exactly what
// CustomPriceGrabAt tolerates as "on the line") and that offset was copied onto the
// PRICE. The user did not move anything on purpose, yet the line's price changed -
// and every level, which is derived from that price, moved with it. A price that
// changes without the user moving something is the "the levels are not reliable"
// bug, so the carry is fenced by the two rules the BaseKnot box already uses:
//   * SLOP: only a gesture that has actually TRAVELLED may drive the line, and an
//     HLINE can only be moved along Y - so a click's jitter can never pass, and a
//     click is honest: the price does not change at all.
//   * DELTA from the press latch, never absolute-to-cursor: the press offset is
//     preserved (the line follows the mouse exactly like MT4's own drag does) and
//     the movement can never snap the line onto the cursor.
static int    s_ownGrabX = 0;             // cursor pixel at the grab
static int    s_ownGrabY = 0;
static double s_ownGrabCursorPrice = 0.0; // price under that pixel at the grab
#define CP_DRAG_SLOP 3                    // px of vertical travel before it is a DRAG (P-UI-96: was 6; 6px ate precise nudges on coarse charts, clicks still filter via !pressEdge + jitter < 3px)
// P-UI-99-OFF (2026-09-21, user order): CP_HOLD_MS / CP_HOLD_MOVE (the 500 ms
// hold-to-arm beat, P-UI-97) are retired — the line's claim is immediate, the
// select/deselect pair carries the comfort instead. Restore is a git revert of
// the claim block, not a rewrite.

// P-UI-49c/P-UI-50: did the press at (x,y) land on the line? ONE conversion, the
// one already proven to work in this codebase (ChartXYToTimePrice - the panels and
// the carry below use it), never one per move: the answer only decides WHO owns the
// gesture. The first version converted the LINE to a pixel with
// ChartTimePriceToXY(0, 0, 0, ...) and MT4 REFUSES that call with time = 0, so the hit
// test could never fire at all (zero "grab hit-test" lines in a whole session of
// drags) and the drag lived or died by the terminal's own pick-up. Now the cursor's
// price is compared against the line's, with the tolerance expressed in PIXELS
// through the very price-per-pixel the chart is drawn at: the line as drawn plus a
// few pixels, i.e. what the terminal itself uses - a normal press grabs the line, a
// press clearly away still pans the chart.
bool CustomPriceGrabAt(const int x, const int y)
{
    if(!g_customPriceLineCreated) return false;
    double linePrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
    if(linePrice <= 0) return false;
    int subW = 0; datetime cursorT = 0; double priceAtCursor = 0.0;
    if(!ChartXYToTimePrice(0, x, y, subW, cursorT, priceAtCursor)) return false;
    int heightPx = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
    double span = WindowPriceMax() - WindowPriceMin();
    if(heightPx <= 0 || span <= 0) return false;
    // P-UI-98q: the tolerance covers the visible affordance - the 19 px green
    // circle, not the unpainted line under it.
    int tolPx = (int)inpCustomPriceLevelWidth + 4 + (CP_HANDLE_HALF - HANDSET_HANDLE_HALF);
    if(tolPx < 5) tolPx = 5;
    double tolPrice = span * ((double)tolPx / (double)heightPx);
    return (MathAbs(linePrice - priceAtCursor) <= tolPrice);
}

//| Helper function to hide all TH objects (DRY)                     |
//|                                                                  |
//| Centralized hide logic to avoid code duplication                 |
//| Used by: OnInit, RedrawAllObjects, F key handler                 |
//| COVERS: TH levels, labels, zones, mode labels, custom price      |
//+------------------------------------------------------------------+
// P-PERF-02: hide is a STATE, not a per-frame action. RedrawAllObjects calls
// HideAllTHObjects() from its hidden early-exit on every heavy frame, so the
// old code walked every chart object and wrote a mask on every hit for as long
// as the indicator stayed hidden (the whole point of the F key). Nothing can
// re-show those objects while we are hidden, so the pass runs once per hide
// transition; ResetHideAllState() re-arms it from every path that can show
// objects again (F key show branch, OnInit, OnDeinit).
static bool g_hideAllApplied = false;

void ResetHideAllState() { g_hideAllApplied = false; }

void HideAllTHObjectsPass()
{
    // P-PERF-31: the walk lives in the visibility owner and follows the
    // object cache (only our objects, zero ObjectName calls over foreign
    // chart objects, zero type probes — hiding needs no classification).
    // A fresh instance with a cold cache falls back to one legacy chart
    // scan for the previous instance's leftovers; steady state never scans.
    VisibilityHideAllCached();
    // PERF: Batch special label hide - ObjectSetInteger is no-op if object doesn't exist
    long noPeriodsVal = OBJ_NO_PERIODS;
    ObjectSetInteger(0, g_stepModeLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    ObjectSetInteger(0, g_factorLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
    ObjectSetInteger(0, g_th3FreqLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
#endif
    ObjectSetInteger(0, g_lockStatusLabelName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    if(g_customPriceLineCreated)
        ObjectSetInteger(0, g_customPriceHorizontalLineName, OBJPROP_TIMEFRAMES, noPeriodsVal);
    // P-UI-98d: the handset handles hide with everything else (F key). They are
    // screen-pixel BITMAP_LABELs — no TF mask applies — so they PARK off-window;
    // the next sync (ride channel / face owner) re-places them on the show path.
    HandsetHandlePark(g_cpMarkerName, CP_HANDLE_RES);
    HandsetHandlePark(S1MarkName(1), S1_HANDLE_RES);
    HandsetHandlePark(S1MarkName(-1), S1_HANDLE_RES);
    // NOTE: ABCD pattern objects are NOT hidden by F key
}

// Returns true when this call performed the (once per transition) pass.
bool HideAllTHObjects()
{
    if(g_hideAllApplied) return false;
    g_hideAllApplied = true;
    HideAllTHObjectsPass();
    // Written outside the visibility guard → invalidate every stored mask.
    BumpTfEpoch();
    return true;
}
#endif // EVENT_HANDLERS_CUSTOMPRICE_MQH
