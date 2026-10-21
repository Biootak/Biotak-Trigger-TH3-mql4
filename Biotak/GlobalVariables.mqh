  #ifndef GLOBAL_VARIABLES_MQH
#define GLOBAL_VARIABLES_MQH

// Core State
static double g_highestHigh = EMPTY_VALUE;
static double g_lowestLow = EMPTY_VALUE;
// P-TH3-DEL2 (2026-09-22) -- OUR OWN deletes announce themselves by TIME.
// Redraws drop and remake family members (mother overlay with no match,
// proof with no vote, zone style switches); each drop queues an
// OBJECT_DELETE behind the draw. The delete cascade (OnABCDMouseEvent)
// heals those while this second is fresh and only wipes a family whose
// anchors are actually gone. Plain transient: never persisted, never read
// on the steady path.
// P-TH3-DEL3: WALL clock, not the tick clock. TimeCurrent only moves when the
// server sends a tick, so a drop queued behind our own multi-second redraw
// read the tick-time window as already closed on a live chart â€” and a frozen
// clock (no-tick chart) held it open forever. GetTickCount answers both.
static uint g_th3OwnDeleteMs = 0;
static double g_currentPrice = 0.0;
static datetime g_lastCalculation = 0;
static datetime g_lastHistoricalUpdate = 0;
static bool g_initialized = false;
static bool g_calculatedOnce = false;
static bool g_labelsRelayoutNeeded = false;

// P-KEY-PROBE (2026-09-30, Touch rule 5) â€” THE TRIGGER PRESS, TIMESTAMPED.
// Â«Ø³Ø·ÙˆØ­ ØªØ±ÛŒÚ¯Ø± Ø¯ÛŒØ± Ø®Ø§Ù…ÙˆØ´ Ùˆ Ø±ÙˆØ´Ù† Ù…ÛŒØ´Ù‡Â» is a latency complaint and latency has to be a
// number in the log or the next edit is a guess. P-PERF-32b made the toggle paint in
// its own event, so the pair is two lines now: the OWNER prints pressâ†’painted
// (`[P-KEY] T applied â€¦ ms=` bands=/masks=) and the frame that RECONCILES the family
// prints pressâ†’frame-end (`[P-KEY] T settled â€¦ ms=` hidden=/reached=). The fields
// below feed the second line only: the render counts the trigger bands whose mask it
// asserted for the press (hidden) and the bands it reached (reached).
// Cost: four int writes on a key press, one int read per trigger band while a press
// is outstanding, one compare at the end of every frame.
static uint g_triggerPressMs     = 0;   // 0 = no trigger toggle waiting for the frame
static int  g_triggerPressOn     = 0;
static int  g_triggerPressHidden = 0;   // bands this render masked OFF for the press
static int  g_triggerPressReached= 0;   // trigger bands this render reached for it
static double g_dailyClosePriceForTH = EMPTY_VALUE;
bool g_redrawTHLevelsNeeded = true;
bool g_forceClearOnNextDraw = false;
// P-PERF-38d: "this chart already carries our ladder, handed over by the
// instance a timeframe change unloaded" â€” resolved ONCE per instance at the end
// of OnInitHandler (ResolveTopologyAdoption, EventHandlers) and read in three
// places: the timeframe invalidation (which skips the wipe when it is true), the
// first level pass (which seeds the stored topology signature), and the ladder
// sweep in LevelPipeline (P-LEVEL-FOREIGN-02), which may only walk the chart
// when the handoff happened â€” a wiped chart has no foreign index to find.
//
// It is declared HERE rather than beside its resolver because LevelPipeline.mqh
// is included before EventHandlers.mqh (entry lines 93 and 99) and MQL4 has no
// forward reference for a global.
bool g_adoptPreviousTopology = false;
// g_viewportOnlyRedraw removed   scroll no longer triggers level redraw
int g_currentLabelYOffset = 0;       // Cumulative Y offset for stacking top label sections (ATR)
int g_currentLabelYOffsetBottom = 0;  // Cumulative Y offset for stacking bottom label sections (TH)
int g_modeLabelYOffset = 0;           // Final Y offset after all labels rendered
static bool g_redrawNeeded = true;

// Performance Tracking
static int g_objectCountLast = 0;
static datetime g_lastObjectCleanup = 0;

// P-UI-92b (2026-09-16) â€” THE UI LAYER'S LIVE "THIS RELEASE IS MINE" CLAIM, published.
//
// The composer runs OnChartEventHandler BEFORE HandleUIChartEvent, so the DOMAIN
// half of one click cannot call the UI state machine that knows whose gesture the
// release belongs to (the claim lives in BiotakMenu's file statics, and the domain
// is compiled from EventHandlers/BaseKnotTool, i.e. earlier). So the UI half
// MIRRORS its claim here â€” one writer, `UIPublishClickClaim()` in BiotakMenu, called
// from the two transitions of the claim and from its reset â€” and the domain PEEKS:
// `UIPeekClickClaim()` is a read, never a consume, because the UI half of the SAME
// release must still take the claim it published (P-UI-65: one claim, one consumer).
//
// `g_uiClickClaimMs` is the deadline the UI wrote for its own claim, so a claim that
// outlives its gesture (a press whose release never arrived) can never eat a later,
// genuine chart click. Both fields are plain state: no timer, no allocation, and the
// steady state is two bool reads for the domain (see UIPointerOverSurface for the
// WHERE half of the same rule â€” this is the WHOSE half).
// The mirror is the claim's OWN shape, not a summary of it: `down` + `seq` are the
// press-bound form (the release it belongs to is however long the user holds), the
// deadline is the up-armed form's TTL, and `pressSeq` is the counter's live value so
// the domain can apply the UI's exact "a new press owns the click" rule without
// reaching into the UI's file statics. All four are written by ONE function,
// `UIPublishClickClaim()` in BiotakMenu.
static bool g_uiClickClaimLive = false;
static bool g_uiClickClaimDown = false;   // armed under a live press (bound by seq)
static uint g_uiClickClaimSeq  = 0;       // the press it was armed under
static uint g_uiClickClaimMs   = 0;       // TTL of the up-armed form (0 = none)
static uint g_uiPressSeq       = 0;       // the UI's live press counter (mirrored)

// The domain's ONE reader of the UI's claim. A peek: it never clears, expires or
// consumes anything it looks at, so the UI half of the same event still finds its
// claim armed exactly as it left it (P-UI-65: one claim, one consumer).
// The three tests are the SAME three the UI applies, in the same order â€” that is the
// whole point: both halves of one event must classify the same release identically.
bool UIPeekClickClaim()
{
   if(!g_uiClickClaimLive) return false;
   // Press-bound: valid while its own press is still the live press (no clock â€”
   // how long the user holds a button is the user's choice, P-UI-65).
   if(g_uiClickClaimDown) return (g_uiClickClaimSeq == g_uiPressSeq);
   // A new press retired it: the click belongs to that press, not to this claim.
   if(g_uiClickClaimSeq != g_uiPressSeq) return false;
   // Up-armed (a drag end, a card opened by a release): it keeps its short TTL.
   if(g_uiClickClaimMs != 0 && (int)(GetTickCount() - g_uiClickClaimMs) >= 0) return false;
   return true;
}

#ifdef BUILD_LITE
//+------------------------------------------------------------------+
// P-UI-92c (2026-09-16) â€” THE LITE STUB OF THE UI'S PIXEL TEST.
//
// `UIPointerOverSurface` is the UI layer's own layout arithmetic, so its real
// body lives in BiotakPanels â€” the file that owns every surface rectangle (the
// card, its popovers, the strip, the ring menu, the countdown tag). The LITE
// entry has NO UI half (it includes EventHandlers/BaseKnotTool but not
// BiotakMenu/BiotakPanels), while the domain half that asks the question is
// shared. Without this stub the shared half would not COMPILE in Lite - which is
// exactly how the first cut of P-UI-92 shipped: `error 168: function not
// defined` at six sites, caught only by compiling the Lite entry.
//
// The answer is honest, not a fallback: Lite draws no UI, so no pixel belongs to
// the UI layer and the chart owns every one of them. Defined here (Lite only)
// so there is ONE call spelling at every domain site instead of a second,
// Lite-only branch that would rot.
//+------------------------------------------------------------------+
bool UIPointerOverSurface(const int mx,const int my)
{
   return false;
}
#endif

// Custom Price Selection
static bool g_waitingForCustomPriceClick = false;
static string g_customPriceHorizontalLineName = "CustomPriceHorizontalLine";
// P-UI-98d: the line's ONE small marker â€” a green dot at the chart's right edge
// (time 0 â€” the anchoring the retired pip labels also used) that shows the line is ARMED.
static string g_cpMarkerName = "CustomPriceHorizontalLine_Mark";
// P-UI-98: the step-1 handles' markers â€” red, one per armed rung-1 line. The
// names carry "_Above_"/"_Below_" so the L-switch visibility walk covers them
// with the line family, and no mode name, so a mode switch orphans none.
string S1MarkName(const int direction)
{
   return inpObjectPrefix + "_Mark_" + (direction > 0 ? "Above_1" : "Below_1");
}
// P-UI-98d v2 â€” THE MARKERS ARE BAKED DRAG HANDLES (user order: Â«Ù†Ø´Ø§Ù†Ù‡ Ù‡Ø§
// Ù‡Ù†Ø¯Ù„Ø± ÙˆØ³Ø· Ø®Ø· Ø¨Ø§Ø´Ù‡ Ùˆ Ø¨Ù‡ ØµÙˆØ±Øª Ø§ÛŒÚ©ÙˆÙ† Ø¯Ø±Ú¯ Ùˆ Ø¨Ù‡ ØµÙˆØ±Øª Ø¯Ø§ÛŒØ±Ù‡ Ø¨Ø§Ø´Ù‡ Ø§Ø² Ù‡Ø± Ø·Ø±Ù ÙˆØ³Ø·Â»).
// The leg meter's own P-LM-14 language: OBJ_BITMAP_LABEL rasters, centred ON
// the line, in SCREEN pixels. The X is the chart's horizontal middle (the line
// spans the whole chart, so its middle IS the screen's middle) and the Y is the
// line's price projected through the price scale â€” the same three reads the
// pipeline's own pixel math uses. The step-1 projections are stashed here by
// the render's face owner so the ride channels re-project without re-rendering.
#resource "\\Files\\Icons\\cp_handle.bmp"
#resource "\\Files\\Icons\\s1_handle.bmp"
#define CP_HANDLE_RES  "::Files\\Icons\\cp_handle.bmp"
#define S1_HANDLE_RES  "::Files\\Icons\\s1_handle.bmp"
#define HANDSET_HANDLE_HALF  7       // the 15 px icon's half, for the centring
#define CP_HANDLE_HALF       9       // P-UI-98q: the green raster reads one size up (19 px)
#define HANDSET_HANDLE_PARK  (-100)  // anchor off-window: park the icon outside it
static double g_s1MarkAbovePrice = 0.0;  // the render's own projection answers
static double g_s1MarkBelowPrice = 0.0;
// P-UI-98e: the armed handles' own OBJECT NAMES, stashed by the same face owner.
// The grab hit test must name the line it claims without walking the chart, and
// the carry must know which object to move â€” the render has both in hand.
static string g_s1MarkAboveName = "";
static string g_s1MarkBelowName = "";
// P-UI-98e: the step-1 handle's OWN carry â€” the custom-price line's channel
// (P-UI-49c/P-UI-99), worn by the second hand-set line, because MT4's native
// per-object drag never engaged on the user's build (Â«Ø§Ù„Ø§Ù† step Ø§ÙˆÙ„ Ø¯Ø± Ù‡Ø± ØªØ§ÛŒÙ…
// Ú©Ù‡ Ø¯Ø±Ø´ Ù‡Ø³ØªÛŒÙ… Ù‚Ø§Ø¨Ù„ Ø¯Ø±Ú¯ Ú©Ø±Ø¯Ù† Ù†ÛŒØ³ØªØ´Â»). Declared HERE, beside the gesture flags
// they heal and settle beside, so every reader in the translation unit sees them
// regardless of include position (the same rule g_s1DragLive follows).
static int    g_s1OwnGrabY = 0;                  // cursor pixel row at the grab
static double g_s1OwnGrabCursorPrice = 0.0;      // price under that pixel at the grab
static double g_s1OwnGrabPrice = 0.0;            // the handle's own price at the grab
static double g_s1OwnLastWrite = 0.0;            // the last price WE wrote (0 = none)
static bool   g_s1OwnActive = false;             // THIS gesture is ours (our press claimed it)
// P-UI-98e: the draggable flag is BORROWED for the length of our own carry
// (P-LM-21's rule): MT4 re-arms its own per-object drag on every paint for as
// long as SELECTABLE sits on the object, and the line then fights the hand -
// Â«Ø³Ø±ÛŒØ¹ Ù‚Ø·Ø¹ Ù…ÛŒØ´Ù‡Â». Cleared (and the flag returned) at the settle and by the heal.
static bool   g_s1OwnBorrowed = false;
// P-UI-98e: the CHART PERIOD the stash below belongs to. Â«ÙÙ‚Ø· Ù‡Ø± step Ø§ÙˆÙ„ Ø¯Ø± ØªØ§ÛŒÙ…
// Ø®ÙˆØ¯Ø´ ÙØ¹Ø§Ù„ Ø¨Ø§Ø´Ù‡Â»: a stash left by the previous timeframe must not answer a
// press on the new one (the render re-stashes on the TF switch's own frame).
static int    g_s1MarkPeriod = 0;
// P-UI-98e: THE CLICK CONTRACT's state. Declared here (not beside the functions
// that use it) because the stale-drag HEAL - a hundred lines above them, and the
// one path that must consume a lost press - has to see every one of them.
static string g_s1ClickRow = "";        // the rung-1 line the current press landed on
static int    g_s1ClickRowY = 0;        // its pixel row at the press (the travel test)
static uint   g_s1ClickLastMs = 0;      // the contract's own double-click stamp
static uint   g_s1ClickHandledMs = 0;   // the twin-event dedupe (two transports, one click)

void HandsetHandleAtXY(const string hn, const int cx, const int cy, const int half, const string bmp)
{
   if(ObjectFind(0, hn) < 0)
   {
      if(!ObjectCreate(0, hn, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, hn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, hn, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, hn, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, hn, OBJPROP_BACK, false);
      ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_CHART_LABEL);
   }
   // The rung is re-asserted on every pass, UNGUARDED: a handle a pre-rung build
   // drew keeps ObjectCreate's default 0 until something lifts it. It is not
   // read back â€” the zorder audit bans OBJPROP_ZORDER reads in product code
   // (a diagnostic, not a product question, P-UI-31's rule).
   ObjectSetInteger(0, hn, OBJPROP_ZORDER, Z_CHART_LABEL);
   // the BMPFILE re-push forces MT4 to re-decode â€” change-guarded (P-LM-15)
   if((string)ObjectGetString(0, hn, OBJPROP_BMPFILE, 0) != bmp)
   {
      ObjectSetString(0, hn, OBJPROP_BMPFILE, 0, bmp);
      ObjectSetString(0, hn, OBJPROP_BMPFILE, 1, bmp);
   }
   if(cx <= 0)
   {
      // unprojectable: park, never guess a screen position (the leg meter's rule)
      if((int)ObjectGetInteger(0, hn, OBJPROP_XDISTANCE) != HANDSET_HANDLE_PARK)
         ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, HANDSET_HANDLE_PARK);
      return;
   }
   int nx = cx - half, ny = cy - half;   // the icon's CENTRE sits on the anchor
   if((int)ObjectGetInteger(0, hn, OBJPROP_XDISTANCE) != nx)
      ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, nx);
   if((int)ObjectGetInteger(0, hn, OBJPROP_YDISTANCE) != ny)
      ObjectSetInteger(0, hn, OBJPROP_YDISTANCE, ny);
}

void HandsetHandlePark(const string hn, const string bmp)
{
   HandsetHandleAtXY(hn, HANDSET_HANDLE_PARK, HANDSET_HANDLE_PARK, HANDSET_HANDLE_HALF, bmp);
}

// The projection: X = the chart's horizontal middle, Y = the price's pixel row.
void HandsetHandleAt(const string hn, const double price, const string bmp)
{
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   double pmax = ChartGetDouble(0, CHART_PRICE_MAX);
   double pmin = ChartGetDouble(0, CHART_PRICE_MIN);
   if(w <= 0 || h <= 0 || !(pmax > pmin) || !(price > 0.0) || !MathIsValidNumber(price))
   {
      HandsetHandleAtXY(hn, HANDSET_HANDLE_PARK, HANDSET_HANDLE_PARK, HANDSET_HANDLE_HALF, bmp);
      return;
   }
   int y = (int)(((pmax - price) / (pmax - pmin)) * (double)h);
   // P-UI-98q: centre with the raster's own half - the green circle is 19 px,
   // the reds 15 px.
   int half = (bmp == CP_HANDLE_RES) ? CP_HANDLE_HALF : HANDSET_HANDLE_HALF;
   HandsetHandleAtXY(hn, w / 2, y, half, bmp);
}
static bool g_customPriceLineCreated = false;
static double g_customTHStartPrice = 0.0;
static ENUM_TH_START_POINT_TYPE g_thStartPointType = TH_START_POINT_PREVIOUS_CLOSE;
static int g_startPointOverride = -1;   // panel START POINT row: -1 = none (dialog+placement rules), else 0..4
static uint g_lastClickTickCount = 0;
static bool g_customPriceLineDragging = false;
// P-UI-45: "this gesture touched the custom price line" (a native drag, or a plain
// click that MT4 answered by SELECTING it). MT4 keeps the object SELECTED after
// such a gesture and then moves it on EVERY later drag anywhere on the chart, so
// the clear is deferred to the first button-up mouse move - writing it while the
// drag is live would drop the line out of the user's hand.
static bool g_customPriceNativeDrag = false;
// P-UI-49c: THIS gesture is OURS - we carry the line ourselves. MT4's per-object
// native drag needs the terminal to grab the object first (SELECTABLE + its own
// hit test) and several builds never engage it at all - the same reality the
// BaseKnot boxes already live with in P-BK-16 ("frozen build / grab never
// engaged"). So the grab is decided by us: MT4 selected it, OR the press edge
// landed on the line (CustomPriceGrabAt). While this flag is set, the mouse-move
// path feeds the line the price under the cursor - but ONLY while the terminal's
// price still equals what we last put there (if MT4 moved it, its own drag wins
// and we touch nothing: P-BK-15's rule).
//
// P-UI-51: that reference is FIXED AT THE GRAB for the whole gesture (and the
// carry holds off on the press edge's own move, where the price still equals the
// grab price by definition). Re-arming it mid-gesture - which is what the line's
// own CHARTEVENT_OBJECT_DRAG handler used to do on every step - made the frozen
// test compare the price with itself, so the carry wrote the dragged object in
// the middle of MT4's live drag and MT4 cancelled it (P-BK-15).
static bool g_customPriceDragOwn = false;
static double g_lastCustomPriceLinePos = 0.0;
static bool g_customPriceKeyboardOverride = false;
//
// P-UI-98 (2026-09-21) â€” THE FIRST STEP IS DRAGGABLE (custom-price step override).
//
// In custom-price start-point mode the trigger line ONE STEP from the custom
// price line on each side is the user's step handle (P-UI-98f: picked by
// geometry, `_Above_1` above and `_Below_2` below â€” the below side's own rung-1
// line is drawn exactly ON the custom price line, so it can never carry the
// handle): dragging one sets the ladder's step to the distance the user dropped
// it at. The setting is ONE MULTIPLIER of the
// mode's own natural first step, stored chart-scoped so a timeframe switch
// carries it over and re-scales THAT timeframe's natural steps by the same
// factor â€” the relative ratios between timeframes (and between the SS/LS
// short/long pair, and the Factor harmonic pair) stay exactly as the course
// defines them. F = 1.0 (or the key absent) is "no override".
//
// The stash below is the F-FREE first interval of the mode that was last
// rendered (DrawLevelsBasedOnMode notes it straight off the mode factory's own
// stepSizes, so there is no second copy of the per-mode first-step logic to
// drift). The drag math is newFirst / NaturalFirstStep().
static double g_stepOverrideFactor = 1.0;      // runtime mirror of the chart key
static double g_naturalFirstStep = 0.0;        // F-free first interval, price units
// The step-1 drag gesture's own flags (P-UI-98). Declared here, beside the
// custom-price gesture flags they heal and settle beside, so every reader in
// the translation unit sees them regardless of include position.
static bool   g_s1DragLive = false;            // a step-1 handle gesture is in flight
static string g_s1DragName = "";               // the handle being dragged (its writes are skipped)
string StepOverrideFactorName() { return "Biotak_StepFactor_" + GetCachedChartIdStr(); }

void NaturalFirstStepNote(const double step)
{
   if(step > 0.0 && MathIsValidNumber(step)) g_naturalFirstStep = step;
}
double NaturalFirstStep() { return g_naturalFirstStep; }

// The ONE reader. Reads the key through the mirror; a missing key is the
// natural ladder (1.0), not an error.
double StepOverrideFactor()
{
   if(GlobalVariableCheck(StepOverrideFactorName()))
   {
      double v = GlobalVariableGet(StepOverrideFactorName());
      if(v > 0.0 && MathIsValidNumber(v)) g_stepOverrideFactor = v;
   }
   if(!(g_stepOverrideFactor > 0.0) || !MathIsValidNumber(g_stepOverrideFactor))
      g_stepOverrideFactor = 1.0;
   return g_stepOverrideFactor;
}

// The ONE writer. `factor` is the ratio the user's drag produced; sane bounds
// keep a stray drop from flattening the ladder to nothing or blowing it out.
void StepOverrideFactorSet(const double factor)
{
   if(!MathIsValidNumber(factor) || factor <= 0.0) return;
   double clamped = MathMax(0.05, MathMin(20.0, factor));
   g_stepOverrideFactor = clamped;
   GlobalVariableSet(StepOverrideFactorName(), clamped);
}

// The ONE clearer: custom-price mode OFF and the R reset land here.
void StepOverrideFactorReset()
{
   g_stepOverrideFactor = 1.0;
   GlobalVariableDel(StepOverrideFactorName());
}

// P-UI-98d (2026-09-21) â€” THE ARMED/SET STATE OF THE TWO HAND-SET LINES.
// User order: Â«Ø®Ø· Ú©Ø§Ø³ØªÙˆÙ… Ù¾Ø±Ø§ÛŒØ³ Ùˆ Ø®Ø· step Ø§ÙˆÙ„ ÙˆÙ‚ØªÛŒ Ø¨Ø¹Ø¯ Ø¬Ø§Ø¨Ø¬Ø§ÛŒÛŒ Ø±ÙˆØ´ Ú©Ù„ÛŒÚ© Ø´Ø¯ Ø³Øª
// Ù†Ù‡Ø§ÛŒÛŒ Ø¨Ø´Ù‡ Ùˆ Ø¨Ø§ Ø¯Ø¨Ù„ Ú©Ù„ÛŒÚ© ÙØ¹Ø§Ù„ Ø¨Ø´Ù‡Ø› ØªØ§ Ø²Ù…Ø§Ù†ÛŒ Ú©Ù‡ Ø³Øª Ù†Ù‡Ø§ÛŒÛŒ Ù†Ø´Ø¯Ù‡ Ø¢Ø²Ø§Ø¯Ù†Ù‡ Ø¯Ø±Ú¯ Ø¨Ø´Ù‡Â».
// ARMED = draggable (the line's native drag answers), SET = inert (nothing can
// grab it â€” a drag of any other object can never steal it, which is the other
// half of the same order). A single click sets, a double-click re-arms; the
// single click waits out the double-click window in the pending slots below
// (the sweep commits it) so the second click of a double can never land on an
// already-set line.
static bool   g_cpLineArmed  = true;       // custom price line: armed = draggable
static bool   g_s1LinesArmed = true;       // the two step-1 handles: armed = draggable
// P-UI-98g (2026-09-22) â€” THE CIRCLES COME WHEN YOU CLICK. User order: Â«ÙÙ‚Ø·
// ÙˆÙ‚ØªÛŒ Ø±ÙˆØ´ Ú©Ù„ÛŒÚ© Ú©Ø±Ø¯ÛŒÙ… Ø¯Ø§ÛŒØ±Ù‡ Ù‡Ø§ Ø¨ÛŒØ§Ø¯ Ø¨Ø±Ø§ÛŒ Ø¯Ø±Ú¯ Ú©Ø±Ø¯Ù†Â». ARMED and SHOWN are two
// different questions: armed means the line can be grabbed, shown means its
// circular drag handle is PAINTED. The circles were painted whenever the pair
// was armed, so they sat on the chart the whole time (Â«Ø®ÛŒÙ„ÛŒ Ù…Ø²Ø§Ø­Ù…Â»), and the
// user asked for the leg meter's own reading of "a marker you ask for": click
// the line, the circle comes, drag it. The latch lives per line (the green one
// for the custom price line, one for the step-1 pair), it is cleared by a SET
// (a set line cannot be grabbed, so nothing points at it), by the placement's
// own teardown and by `HandsetPlacementArm` (a fresh placement is born
// ARMED-but-HIDDEN), and OUR OWN drag reveals it too - a hand on the line is
// the loudest way of asking for its handle.
// P-UI-149/P-UI-151 (2026-10-02): AND BOTH ARE NOW THE LOOK-AWAY'S â€” user order:
// Â«Ø¨Ø§ Ú©Ù„ÛŒÚ© Ø¯ÛŒØ¯Ù‡ Ø¨Ø´Ù† Ùˆ Ø¬Ø§ÛŒ Ø¯ÛŒÚ¯Ù‡ Ú©Ù„ÛŒÚ© Ø´Ø¯ Ø®ÙˆØ¯Ú©Ø§Ø± Ù¾Ù†Ù‡Ø§Ù† Ø¨Ø´Ù†Â» and, for the green one
// that P-UI-149 had exempted, Â«Ø§ÛŒÙ† Ø¯Ø§ÛŒØ±ÛŒÙ‡ Ø³Ø¨Ø² Ø§ÛŒÙ†Ø·ÙˆØ±ÛŒ Ù…ÛŒÙ…ÙˆÙ†Ù‡ Ø¨Ø¯ ... ÙˆÙ‚ØªÛŒ Ú©Ù„ÛŒÚ© Ø´Ø¯
// Ø¬Ø§ÛŒ Ø¯ÛŒÚ¯Ù‡ Ù¾Ù†Ù‡Ø§Ù† Ø¨Ø´Ù‡ Ùˆ ÙˆÙ‚ØªÛŒ Ø±ÙˆØ´ Ú©Ù„ÛŒÚ© Ø´Ø¯ Ø¯ÛŒØ¯Ù‡ Ø¨Ø´Ù‡Â». ONE owner answers both
// latches from the click edge: `HandsetMarkerRevealAt` shows the marker the
// click landed on (each with its own hit test), and
// `HandsetRevealDropOnForeignClick` clears BOTH when it landed on neither
// (EventHandlers_Init). So a click on a marker is its show, and a click on
// anything else is every marker's hide - one rule, three circles.
static bool   g_cpHandleShown = false;     // the green circle: painted on request
static bool   g_s1HandleShown = false;     // the red circles: painted on request
static string g_cpSetPending = "";         // a single click waiting out the window
static uint   g_cpSetPendingMs = 0;
static string g_s1SetPending = "";
static uint   g_s1SetPendingMs = 0;
static uint   g_cpJustDraggedMs = 0;       // a drag release that MOVED the line:
static uint   g_s1JustDraggedMs = 0;       //   its click echo must not set anything
// P-UI-98m: the re-arm candidate for a SET (masked) custom price line. A masked
// line fires no OBJECT_CLICK, so the press edge records the row off the line's
// own grab test and the button-up / CHARTEVENT_CLICK edges ask it - exactly
// the step-1 click shape, except a single click here is a no-op (already set)
// and only a double re-arms, so no sweep slot is needed.
static bool   g_cpClickArmed = false;      // press landed on the SET line's row
static int    g_cpClickY = 0;              // its pixel row (the travel test)
static uint   g_cpClickLastMs = 0;         // double-click window
static uint   g_cpClickHandledMs = 0;      // twin-transport dedupe
// TV-parity 2026-09-07: the Base Box TEXT edit field (card 12, OBJ_EDIT) owns
// the keyboard while focused â€” letter hotkeys must stay silent or typing box
// text would toggle indicator state (same pattern as the palette hex field).
static bool g_BkTextFocus = false;
// A settings card is open (set in PnlOpen, cleared in PnlCloseAll): the menu's
// custom hover tooltip must not arm/fire over the open panel (phantom tip).
// Lives here (not Panels) so BiotakMenu â€” included BEFORE BiotakPanels â€” can
// read it without breaking the bottom-up include order.
static bool g_UIPanelOpen = false;
// P-UI-98r: the open surfaces' screen rects, published by the panels module
// (PnlPublishCover) for readers that cannot see it (HTFCandles is included
// BEFORE BiotakPanels, so the layer rule forbids the call). Margin included
// by the publisher; -1 = no surface. Lets chart-anchored art stay out from
// under opaque UI without asking the UI layer per box.
static int g_UIPanelRX = -1, g_UIPanelRY = -1, g_UIPanelRW = 0, g_UIPanelRH = 0;
static int g_UIPPalRX = -1, g_UIPPalRY = -1, g_UIPPalRW = 0, g_UIPPalRH = 0;
// P-DRAW-31 (2026-09-24): and the DRAW-STRIP's own plate, published the same way
// by `DrawStripPublishRect()` for the ONE reader that cannot see it â€”
// `PnlComputePosition` sizes a card with BiotakPanels' own arithmetic, and
// BiotakPanels is included AFTER DrawStrip (MQL4 is define-before-use), so a card
// must be TOLD where the strip is instead of re-deriving its geometry. Two panels
// on one pixel is the user's own complaint (Â«Ø¬Ø§ÛŒÛŒ Ú©Ù‡ Ø±ÙˆÛŒ Ù‡Ù… Ù†ÛŒØ§ÙØªÙ†Â»); margin
// included by the publisher; -1 = no strip on the chart.
static int g_UIStripRX = -1, g_UIStripRY = -1, g_UIStripRW = 0, g_UIStripRH = 0;
// P-DRAW-87 (2026-09-30): and the OVERLAY's name root, published the same way by the
// HTF module for the one reader that cannot see it. `DrawIsIndicatorObject`
// (DrawToolbar, included BEFORE HTFCandles) answers "is this the product's object or
// the user's drawing?" and the whole draw-strip hangs off it â€” the press hit test,
// the interior split, the APPLY-ALL walk, the delete router. The HTF family is born
// `BiotakHTF_<chartid>_*`, which `inpObjectPrefix` ("THLevels") does not cover, so
// every one of those paths read it as a USER drawing. Measured 2026-09-30: the 2 s
// `BoxExtrasPump` moved each shadow's interior into an `<name>_FL` child painted in
// the chart BACKGROUND and cleared the master's own FILL, which is the report
// Â«Ø´Ø§Ø¯Ùˆ Ø±Ø³Ù… Ù…ÛŒØ´Ù‡ Ø¨Ø¹Ø¯ Ú†Ù†Ø¯ Ø«Ø§Ù†ÛŒÙ‡ Ù†ÛŒØ³ØªÂ» (the pixel was byte-identical to the background).
// The name itself stays HTFCandles' own (P-UI-68: ONE writer of an HTF name); this
// variable only PUBLISHES it, exactly like the rects above. "" = no overlay on this
// chart yet, and then the predicate answers what it answered before this line existed.
static string g_OverlayNameRoot = "";

// Toggle States (hotkey-controlled)
// NOTE: g_triggerLevelsEnabled moved to RuntimeSettings.mqh â€” it is the runtime
// copy of inpShowTrigger (seeded at attach) and doubles as the hotkey toggle.
static bool g_linesVisible = true;
static bool g_atrLabelsVisible = true;
// Live countdown tag (CreateLivePriceCountdown): the pixel rect it was last
// painted at, so a chart click can be hit-tested against it WITHOUT making the
// object selectable (selectable = the user could drag it).
static int  g_cdTagX = 0, g_cdTagY = 0, g_cdTagW = 0, g_cdTagH = 0;
static bool g_cdTagValid = false;
static bool g_thLabelsVisible = true;
static int  g_thLabelsMode = 0; // 0=OFF, 1=FRACTAL, 2=STANDARD (exclusive, never both)
static int  g_thLastOnMode = 2; // remembered ON mode for the A toggle, default STANDARD

//--- TH labels single source of truth: g_thLabelsMode drives the drawing and
//    the hotkey cycle; the flag mirrors (g_showTHLabels / g_showFractalTHs /
//    g_showStandardTHs in RuntimeSettings) are derived FROM it so the settings
//    card can never disagree with what is actually drawn. Call SyncTHFlagsFromMode()
//    after ANY change to g_thLabelsMode.
int THModeFromFlags()
{
   if(g_showStandardTHs) return 2;
   if(g_showFractalTHs)  return 1;
   return 0;
}

void SyncTHFlagsFromMode()
{
   if(g_thLabelsMode == 3) g_thLabelsMode = 2; // legacy BOTH migrates to STANDARD
   if(g_thLabelsMode == 1 || g_thLabelsMode == 2) g_thLastOnMode = g_thLabelsMode;
   g_thLabelsVisible    = (g_thLabelsMode != 0);
   g_showTHLabels       = (g_thLabelsMode != 0);
   g_showFractalTHs     = (g_thLabelsMode == 1);
   g_showStandardTHs    = (g_thLabelsMode == 2);
}
// STEPOVERRIDE-OFF (2026-09-05, user decision): single Step Mode â€” the override
// layer is retired. E / Tools-ring / panel all write g_stepCalculationMode now.
// static int g_stepModeOverride = -1;        // -1 = Auto (follow CALC MODE), 0-3 = force TH/SS-LS/Combo/Factor
static int g_sslsFirstOverride = -1;       // -1 = use inpLSFirst, 0 = SS first, 1 = LS first
static double g_factorValueOverride = 0;   // 0 = use input, >0 = override
static int g_factorColorOverride = -1;     // -1 = use input
#ifndef BUILD_LITE
static double g_th3FreqOverride = 0;       // 0 = use input, >0 = override
static int    g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX; // Binary subdivision index
#endif

// Alert Tracking
static datetime g_lastAlertTime = 0;
static string g_lastAlertLevel = "";

// Timeframe Lock (keyboard-only since 2026-09-04: no menu item, no card)
static bool g_timeframeLocked = false;
static int g_lockedPeriod = 0;
// VIEWLOCK-OFF (2026-09-05, user decision): View Lock retired â€” the state +
// core fns below are kept compiling DORMANT (same pattern as TH3TOOL-OFF
// remnants) so the feature restores by uncommenting the VIEWLOCK-OFF call
// sites. Nothing sets g_viewLockEnabled anymore â€” it stays false forever.
// View Lock â€” keep the same chart view (bar position + price range) when the
// user switches timeframes. Toggled from the ring menu (VLOCK slot), the
// View Lock card, or the V hotkey. Anchor = first-visible-bar time + visible
// price min/max, captured on scroll/zoom (CHARTEVENT_CHART_CHANGE), at
// enable time, and persisted at the TF-switch handoff (OnDeinit
// REASON_CHARTCHANGE â†’ OnInit â†’ first OnCalculate restores).
static bool g_viewLockEnabled = false;
static datetime g_viewAnchorTime = 0;
static double g_viewAnchorMin = 0.0;
static double g_viewAnchorMax = 0.0;
static bool g_viewRestorePending = false;
// Anchor handle: draggable vertical line showing the locked view's time.
// Created/moved only by ViewAnchorLineEnsure(); deleting it turns the lock off.
static string g_viewAnchorLineName = "Biotak_ViewAnchor_Line";
static string g_lockStatusLabelName = "Biotak_LockStatus_Label";
static string g_stepModeLabelName = "Biotak_StepMode_Label";

// Combo calc breakdown text for the step-mode label. Filled by
// RefreshComboLabelExtraInfo() in ComboEngine.mqh (included AFTER the
// label builder, so it communicates through this global instead of a
// forward declaration - MQL4 treats bare prototypes as #imports).
string g_comboLabelExtraInfo = "";
static string g_factorLabelName = "Biotak_Factor_Label";
#ifndef BUILD_LITE
static string g_th3FreqLabelName = "Biotak_TH3Freq_Label";
#endif

// Independent label expiry timestamps (tick count)
static uint g_stepModeLabelCreateTime = 0;
static uint g_factorLabelCreateTime = 0;
#ifndef BUILD_LITE
static uint g_th3FreqLabelCreateTime = 0;
#endif
static uint g_lockStatusLabelCreateTime = 0;
static uint g_resetCommentCreateTime = 0;  // For "[ RESET ]" comment auto-clear

// ChartRedraw Throttling
static uint g_lastChartRedrawTime = 0;
#define CHART_REDRAW_THROTTLE_MS 100
// P-PERF-02 DRAW GENERATION: bumped by every path that WIPES our chart objects
// (bulk clears, emergency cleanup, cache reset, an external object delete). The
// level render is skipped when its geometry signature is unchanged â€” which is
// only sound while the objects that signature produced are still on the chart,
// so the generation is part of the signature.
static int g_drawGeneration = 1;
void MarkDrawGeneration()
{
    g_drawGeneration++;
    if(g_drawGeneration <= 0) g_drawGeneration = 1;   // overflow guard
}

// P-PERF-06 STAGED REBUILD: a post-wipe level build materialises ~600 chart
// objects (289 zones + 288 lines at inpMaxLevels=144; a third family of pip
// labels sat in the count before P-LBL-12 retired them). Doing it in ONE
// frame freezes a weak PC for seconds on every attach, TF switch
// and topology toggle. While g_buildStage != 0 the wipe is rebuilt one family
// per frame (1=lines, 2=zones, 4=the labels block): every gate
// treats a staging frame as pending work, the geometry signature is stored
// only when the last stage lands, and heavy neighbours (HTF history bulk)
// wait for stage 0. The 250 ms timer pumps RedrawAllObjects while staging so
// a tick-less chart still settles in ~1 s. State lives HERE (not in
// EventHandlers statics) so HTFCandles â€” included LATER â€” can see it
// (P-ARCH-02: an earlier-included module can never see a later one).
#define BUILD_STAGE_LINES  1
#define BUILD_STAGE_ZONES  2
// P-LBL-12 (2026-10-17): BUILD_STAGE_LABELS stood here (3, the pip-label
// family frame). The labels are retired and the advance/paint rungs that used
// the value are gone â€” the number is skipped, not reused, so every remaining
// stage keeps its name.
#define BUILD_STAGE_BLOCK  4
static int g_buildStage = 0;
// Viewport snapshot taken on the stage-1 frame: stages 2-4 cull against the
// SAME window so a pan mid-staging cannot split families across viewports.
// Stale at most ~1 s by construction; the next viewport-driven render heals it.
static double g_stageVpTop = 0.0;
static double g_stageVpBottom = 0.0;

// P-PERF-03 ALERT LEVEL CACHE: the level prices the render just put on the
// chart, recorded ONCE while the pipeline is already iterating them.
//
// WHY: CheckAlerts() walked the chart with a ~288-iteration
// StringFormat + ObjectFind + ObjectGetDouble loop on EVERY heavy frame, and
// the redraw that drew those levels had already had every price in hand. The
// check is now a plain scan of this array: zero kernel calls, and it can only
// fire for levels the chart is actually showing.
#define ALERT_LEVEL_CACHE_MAX 768
struct SAlertLevel {
    string name;    // object name == anti-spam key
    double price;
    int    step;    // logicalStep (alert text)
    bool   above;   // true = a level above the midpoint
};
SAlertLevel g_alertLevels[ALERT_LEVEL_CACHE_MAX];
int g_alertLevelCount = 0;
int g_alertLevelGen = -1;   // g_drawGeneration this cache describes

void AlertCacheReset(const int gen)
{
    g_alertLevelCount = 0;
    g_alertLevelGen = gen;
}

void AlertCacheAdd(const string name, const double price, const int step, const bool above)
{
    if(g_alertLevelCount >= ALERT_LEVEL_CACHE_MAX) return;
    g_alertLevels[g_alertLevelCount].name  = name;
    g_alertLevels[g_alertLevelCount].price = price;
    g_alertLevels[g_alertLevelCount].step  = step;
    g_alertLevels[g_alertLevelCount].above = above;
    g_alertLevelCount++;
}

// P-PERF-02: did the last RedrawAllObjects frame actually paint something?
// The tick path used to issue ThrottledChartRedraw() unconditionally after
// every non-throttled tick â€” up to 10 full chart repaints per second on a
// chart carrying a thousand objects, for a frame that had drawn nothing.
static bool g_lastRedrawDidWork = false;

// P-PERF-03 PHASE LEDGER: milliseconds the last redraw frame spent in each of
// its phases. Printed ONLY when the frame overruns CPU_WARNING_MS, so the next
// freeze reports which phase ate the time instead of being re-investigated
// from zero. Plain integer adds â€” no syscalls, no effect on the fast path.
static uint g_p3MsBase = 0;      // UpdateBasePrice / base-price gate
static uint g_p3MsAtr = 0;       // P-PERF-05: ATR composite + adaptive scaling
static uint g_p3MsHistory = 0;   // UpdateHistoricalValues
static uint g_p3MsLevels = 0;    // level pipeline block
static uint g_p3MsLabels = 0;    // ATR/TH label block
static uint g_p3MsPre = 0;      // P-PERF-49b: OnCalculate BEFORE RedrawAllObjects (incl. the TF-switch wipe)
static uint g_p3MsPost = 0;     // P-PERF-49b: OnCalculate AFTER it (ChartRedraw + object-count check)
static uint g_p3MsOverlay = 0;   // DrawMainLevels + overlay reposition
// P-PERF-53 (2026-10-19) - THE COST HAS A PHASE; THE PHASE HAS A CAUSE.
// MEASURED: 49 CPU warnings in one day of logs, every one of them
// `[base=0 atr=0 hist=0 levels=94..125 labels=0 overlay=0 pre=0 post=0 rest=0]` - the
// whole frame inside the level family render, and not one field saying WHY that frame
// ran at all. A 94 ms render every couple of seconds is either the price of a real edit
// or a rebuild nothing asked for, and those are two different fixes: the reader had to
// guess between the 38 writers of `g_redrawTHLevelsNeeded` alone. The flags are ORed
// into one mask on the frame that owns them - no string work on the hot path - and
// decoded only when a frame overruns, so the price and its cause share one line.
static int g_p3ArmMask = 0;

//--- The mask as names. Runs only on a frame that already overran CPU_WARNING_MS.
string PerfArmWhy(const int m)
{
   string s = "";
   if((m & 1) != 0)   s += "force ";
   if((m & 2) != 0)   s += "labels ";
   if((m & 4) != 0)   s += "th ";
   if((m & 8) != 0)   s += "histRange ";
   if((m & 16) != 0)  s += "base ";
   if((m & 32) != 0)  s += "stage ";
   if((m & 64) != 0)  s += "heavy ";
   if((m & 128) != 0) s += "renderAll ";
   if((m & 256) != 0) s += "clear ";
   if(s == "") s = "sig";        // only the geometry signature moved
   return s;
}
static uint g_p3MsLastTick = 0;  // frame-local scratch

// P-PERF-10: the same treatment for the INIT path. The live log shows OnInit at
// 3.2-4.1 s on EVERY attach and timeframe switch and a first CHART_CHANGE frame
// at 3.2-4.25 s, while the tick ledger reports all phases at zero â€” i.e. the
// seconds are spent in code no ledger brackets. These are the boundaries of
// that path, so the next log names the phase instead of the next session
// guessing at it (the P-PERF-05 lesson). Written by OnInitHandler and the
// entry's OnInit wrapper; read only when the budget was blown.
static uint g_pInitMsSettings = 0;   // seeding, state restores, input validation
static uint g_pInitMsHistory  = 0;   // historical high/low + previous-day price
static uint g_pInitMsBase     = 0;   // base-price subsystem (history FILE load)
static uint g_pInitMsAtr      = 0;   // ATR cache init + warmup step
static uint g_pInitMsInd      = 0;   // whole OnInitHandler half
static uint g_pInitMsUI       = 0;   // UI kit / menu / HTF half
// P-PERF-11b: the base-price phase is the one that owns seconds, so it is
// split four ways and reported only when it overruns. "rebuild" must stay 0
// on a stamped history file - that is the proof the per-init rebuild is gone.
static uint g_pInitBaseFileMs    = 0;   // version check + integrity + file read
static uint g_pInitBaseMigrateMs = 0;   // legacy check + dedup + save
static uint g_pInitBaseRebuildMs = 0;   // M30/M1 rebuild from start of day
static uint g_pInitBaseCleanupMs = 0;   // history-directory cleanup
static uint g_lastDragRedrawTime = 0;
#define DRAG_REDRAW_THROTTLE_MS 50

// Suppression flag: prevents CHARTEVENT_OBJECT_DELETE cascade during programmatic deletions
static bool g_suppressDeleteEvents = false;
static uint g_suppressDeleteEventsUntilMs = 0;

//+------------------------------------------------------------------+
// P-TICKWRAP (2026-09-16) â€” THE ONE OWNER OF "IS THIS DEADLINE STILL AHEAD?".
//
// `GetTickCount()` wraps every ~49.7 days, and the two spellings of a deadline
// test are NOT equivalent:
//   * `GetTickCount() <= deadline`  - WRONG after a wrap. A deadline armed before
//     the wrap is a huge number; once the counter restarts near 0 the test stays
//     TRUE for the rest of the cycle (up to 49 days), so the window it was armed
//     for never closes. The reader here gates the OBJECT_DELETE path: a chart left
//     open that long would silently keep ignoring every delete.
//   * `(int)(GetTickCount() - deadline) <= 0` - the SIGNED DIFFERENCE, correct
//     across the wrap for any interval under 2^31 ms (24 days), which is what a
//     tick-window here always is.
// One owner, so the next window asks it instead of re-deriving the comparison.
// Cost: one subtraction, one compare, and the sentinel test first.
//+------------------------------------------------------------------+
bool TickDeadlinePending(const uint deadlineMs)
{
   if(deadlineMs == 0) return false;                  // never armed
   return (int)(GetTickCount() - deadlineMs) <= 0;    // wrap-safe
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// P-UI-142 (2026-10-02) â€” THE GESTURE ARBITER: WHO OWNS THIS HAND.
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//
// THE FACT, from MetaQuotes' own chart-event list: there are eleven
// CHARTEVENT_* kinds and NONE of them answers "is a native drawing tool armed".
// MT4 itself never has to ask â€” the terminal owns its tools, so its own tools
// always win and an indicator is simply a guest. A GUEST that implements its own
// drag (Path, the ray, Base/Knot, TH3, the leg measure) can therefore not tell,
// at the press, whether it is taking a drawing or WATCHING the start of one â€”
// which is the report Â«Ø§Ø² Ù‡Ù…ÙˆÙ† Ù†Ù‚Ø·Ù‡ Ú©Ù‡ ØªØ±Ù†Ø¯Ù„Ø§ÛŒÙ† Ù…ÛŒÚ©Ø´Ù…ØŒ Ø§ÙˆÙ† ÛŒÚ©ÛŒ Ù‡Ù… Ù…ÛŒØ§Ø¯Â».
//
// THE ONLY VOICE: `CHARTEVENT_OBJECT_DRAG` on an object that is not ours. That is
// P-UI-130 law 3 (the hold's own rule, Â«a gesture IN MOTION is never oursÂ») with
// the scope widened from the hold to EVERY custom drag in the product.
//
// THE ARBITER, therefore, is one writer and one question:
//   `GestureForeignMotion(name)` â€” the ONE place that sees the terminal's drag.
//   `GestureGrabBlocked()`       â€” the ONE question every tool asks before it
//                                  takes a press, and the answer is "not while
//                                  the hand is busy with the terminal".
// A tool that is mid-carry asks it too and, on a foreign motion, puts its own
// snapshot back: the geometry belongs to the tool, the DECISION is shared.
//
// The window is the terminal's own drag HEARTBEAT â€” MT4 re-reports a native drag
// about every 400 ms (P-UI-130's measurement), so that is the honest length for
// "the hand is still busy". Our own objects never emit the event (they are born
// non-selectable), so a path can never forbid itself.
//
// Cost: ONE compare per drag event and ONE subtraction per press. Nothing on a
// tick, nothing per frame, and no second copy of this rule anywhere in the tree â€”
// a tool that re-derives it is a tool that will drift from it.
//+------------------------------------------------------------------+
#define GESTURE_HEARTBEAT_MS 400
static uint g_gestureForeignUntilMs = 0;
static string g_gestureForeignName = "";
static uint g_gesturePressMs = 0;
//--- P-UI-145 (2026-10-02, user: Â«ÛŒÚ© Ø±Ø§Ù‡Ú©Ø§Ø± Ù‚Ø·Ø¹ÛŒ Ú©Ù‡ Ø¯Ø±Ø³Øª Ú©Ø§Ø± Ø¨Ú©Ù†Ù‡ØŒ Ù…Ø¹Ù…Ø§Ø±ÛŒÂ»): THE WHOLE
//--- ARCHITECTURE IS ONE STAMP AND NOTHING ELSE. MEASURED 21:06, the log named the wall:
//--- four `press refused: the terminal is still dragging one of ours, why=release` â€” the lock
//--- was CLOSED by the terminal's own drag and OPENED by nobody, so after the first native
//--- stroke every press of ours stayed dead for the session. A sticky bool with no opener IS
//--- the incomplete architecture, and it is gone: no state is left that can get stuck.
//--- A foreign drag stamps `now + 400 ms` (the terminal's own drag rate, P-UI-130) and the
//--- deadline answers for itself until it passes â€” Â«Ø®ÙˆØ¯Ø´ Ø¨Ø§Ø² Ù…ÛŒØ´Ù‡Â», no timer, no polling,
//--- nothing per frame, one subtraction per press. The detection road stays closed on
//--- purpose (MEASURED: a native stroke reports button=0 on all ~40 of its moves and speaks
//--- once at its end), and the structural half carries the work: a path's BODY selects and
//--- never carries, so a line press can start nothing; its DOTS are the only carry, and they
//--- are painted only for the selected path (PathTool.mqh).
void GestureForeignMotion(const string name)
{
   g_gestureForeignName = name;
   g_gestureForeignUntilMs = GetTickCount() + GESTURE_HEARTBEAT_MS;
}
bool GestureGrabBlocked()
{
   return TickDeadlinePending(g_gestureForeignUntilMs);
}
string GestureForeignName() { return g_gestureForeignName; }
//--- P-UI-145 (2026-10-02): THE SCREEN LOCK IS RETIRED, and the log says why. It was to
//--- close for as long as the terminal's own hand was busy â€” MEASURED 20:35, a native stroke
//--- reports button=0 on ALL ~40 of its moves (the census line's `nm` is the button state,
//--- not a name), so the signal the lock waited for does not exist during the very gesture it
//--- was built for: four `drag start â€¦ why=carry: it was taken` landed back to back and the
//--- path still walked away (`moved=yes`). The answer is structural, not detectable â€” a path's
//--- BODY selects and never carries, so no press can start a carry on a line (PathTool.mqh),
//--- and its VERTICES answer only while it is selected, so the hand is on a dot. Nothing is
//--- left for a foreign press to steal. The foreign-drag lock below stays: it is measured, it
//--- is the terminal's own voice, and it is the backstop for any carry that is live.

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// P-UI-144 â€” "WE DECIDE", AS ONE QUESTION.
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Three measurements closed the detection road (no armed-tool flag; the terminal is
// silent for a whole native stroke and speaks once at its end; its button bit flaps
// mid-press), so the owner of the hand is DECIDED here instead of guessed at:
//
//   A DRAWING THAT IS NOT ALREADY TAKEN CANNOT BE TAKEN. The first press on it
//   selects it and writes no anchor at all; the second carries it.
//
// That is TradingView's own model â€” a drawing tool is a MODE, and inside a mode the
// hand belongs to the new drawing â€” and it needs nothing from MT4, so it holds even
// on a terminal that says nothing at all. One state, one question, and every custom
// drag in the product asks it (the path and the ray today; Base/Knot, TH3 and the
// leg measure join when their press paths are read).
//
// Cost per press: one string compare. Nothing per tick, nothing per frame.
//+------------------------------------------------------------------+
static string g_gestureTaken = "";
static string g_gestureTakeWhy = "";
void GestureTakeNote(const string name) { g_gestureTaken = name; g_gestureTakeWhy = "note:" + name; }
void GestureTakeRelease()             { g_gestureTaken = "";  g_gestureTakeWhy = "release"; }
bool GestureTakeAllowed(const string name)
{
   if(name == "")                    { g_gestureTakeWhy = "refuse: no name"; return false; }
   if(GestureGrabBlocked())          { g_gestureTakeWhy = "refuse: terminal is dragging one of ours"; return false; }
   if(g_gestureTaken == name)        { g_gestureTakeWhy = "carry: it was taken"; return true; }
   g_gestureTakeWhy = "refuse: taken=\"" + g_gestureTaken + "\" asked=\"" + name + "\"";
   return false;
}
//--- WHY a press was refused, in the caller's own words. MEASURED 2026-10-02 19:20: the
//--- live journal carried EIGHT consecutive `[Path] press selects â€¦ (no carry on the first
//--- gesture)` on one path id over forty seconds â€” the take never became effective, so the
//--- user's own drag could not start, and no line said WHICH refusal it was. The arbiter
//--- answers that in its own words now, and the caller prints it beside its own witness:
//--- one string, written on the press edge only (nothing on a tick, nothing per frame).
string GestureTakeWhy() { return g_gestureTakeWhy; }
//--- THE CENSUS, beside the arbiter it measures (P-UI-142). Â«It did not workÂ» is not a
//--- verdict; the ORDER the terminal speaks is. This answers, for one reproduction, the
//--- only question no amount of reading can: does a native draw started ON our own
//--- drawing speak at all, and does it arrive BEFORE or AFTER our first write? It also
//--- keeps the writer honest â€” a tool can only be refused by a signal that exists.
//--- Returns TRUE when the caller should print one line (the caller owns the flushed
//--- channel: the arbiter is compiled before it). Bounded by design: a press, a move
//--- while the button is down or the heartbeat is live, a foreign drag, a foreign create.
//--- P-PERF-40 (2026-10-13) â€” THE CENSUS'S BOUND IS ON EVENTS, NEVER ON RATE.
//--- MEASURED on the live journal, 2026-10-13: one day held 22,281 lines and 17,547 of
//--- them (79%) were `[gest]` â€” at up to 160 lines in ONE SECOND and 634 in ten. The
//--- note above says Â«bounded by design: a press, a move while the button is down or the
//--- heartbeat is live, a foreign drag, a foreign createÂ», and that bound is on WHICH
//--- events pass, not on HOW MANY per second. A press therefore arms a window in which
//--- EVERY mouse-move of the next three seconds prints â€” and each of those lines is not
//--- cheap: `DrawStripDiagEmit` is a `Print()` (a journal write) PLUS a `FileWrite` +
//--- `FileFlush` on the per-chart diag file (`DrawStrip_Base.mqh:37`), on the chart
//--- thread, during the user's own gesture.
//--- This project already ruled on exactly that cost (BuildConfig.mqh:28-36, P-LOG-3:
//--- Â«MT4's Print() is a file write with a flush, so on the weakest machine this is pure
//--- cost for a log nobody reads in productionÂ»), and round 1's own diag frame was
//--- unreadable for the same reason (Â«176 of 186 lines are [gest]Â»). So the census keeps
//--- its standing rule â€” `DSTRIP_DIAG` stays 1 (contract.md:321) â€” and gains a RATE
//--- bound instead.
//--- The census answers an ORDER question: does a native draw speak at all, and does it
//--- arrive BEFORE or AFTER our first write? Every EDGE still prints unconditionally â€” a
//--- foreign drag, a foreign create, and the press â€” and so does the first move after a
//--- gap. Only the repeated moves inside a live window are coalesced, to 10 Hz.
#define GEST_CENSUS_MIN_MS 100
static uint g_gestCensusMs = 0;
static bool g_gestCensusDown = false;

bool GestureCensusWanted(const int id, const string sparam)
{
   int st = (int)StringToInteger(sparam);
   bool down = ((st & 1) != 0);
   //--- Every event passes through here, so the press is stamped HERE (the caller stays
   //--- flat, and a stamp is state this arbiter already owns).
   if(down && id == CHARTEVENT_MOUSE_MOVE) g_gesturePressMs = GetTickCount();
   //--- EDGES ARE NEVER COALESCED. A foreign drag or create IS the P-UI-142 discriminator,
   //--- and the order it arrives in is the whole measurement â€” so it is answered before
   //--- any rate is considered.
   if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CREATE) return true;
   if(id != CHARTEVENT_MOUSE_MOVE) return false;
   //--- P-UI-143: a move that arrives with NO button down is the only shape a native
   //--- stroke has while the terminal draws it (it does not claim the button), and that
   //--- asymmetry is the whole basis of the free discriminator â€” so it is printed too,
   //--- for as long as a press could still belong to it (three seconds: the longest
   //--- deliberate stroke a hand makes before the terminal reports anything).
   bool wanted = (down || GestureGrabBlocked()
                  || (st == 0 && g_gesturePressMs != 0 && TickDeadlinePending(g_gesturePressMs + 3000)));
   if(!wanted)
   {
      g_gestCensusDown = false;   // a refusal ends the stroke, so the next press is an edge
      return false;
   }
   //--- P-PERF-40: the press edge and the first move after a gap always print; the
   //--- repeated moves inside the window are coalesced. `g_gestCensusDown` is the edge
   //--- detector, and every refusal above clears it, so a stale `true` can never swallow
   //--- the next press. `g_gestCensusMs` is only advanced when a line IS printed, which
   //--- is what makes "the first move after a gap" fall out for free.
   uint now = GetTickCount();
   bool pressEdge = (down && !g_gestCensusDown);
   g_gestCensusDown = down;
   if(pressEdge || (now - g_gestCensusMs) >= GEST_CENSUS_MIN_MS)
   {
      g_gestCensusMs = now;
      return true;
   }
   return false;
}

#ifndef BUILD_LITE
// AB=CD drawing state now lives in TH3DrawingSession (TH3Controller.mqh)
static string g_activeABCDPattern = "";

// Frequency Optimizer Result (last auto-find result for info label)
FrequencyResult g_lastFreqResult;

// Frequency History Ring Buffer   last FREQ_HISTORY_SIZE patterns
FrequencyHistoryEntry g_freqHistory[FREQ_HISTORY_SIZE];
int g_freqHistoryCount = 0;   // Total entries added (for < FREQ_HISTORY_SIZE check)
int g_freqHistoryHead  = 0;   // Next write position (wraps around)
#endif

// TH Storage
struct TimeframeTH {
    string timeframeName;
    double thValue;
};
TimeframeTH g_storedTHs[];

// Label Positioning
struct LabelPosition {
    string name;
    int xPos;
    int yPos;
};
LabelPosition g_labelPositions[];

//+------------------------------------------------------------------+
//| Hidden State Cache (TTL-based, matching MT5)                     |
//+------------------------------------------------------------------+
bool g_isHiddenCached = false;
uint g_isHiddenCacheTime = 0;

void RefreshIsHiddenCache() {
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    if(!GlobalVariableCheck(gvar_name))
        g_isHiddenCached = false;
    else
        g_isHiddenCached = (bool)GlobalVariableGet(gvar_name);
    g_isHiddenCacheTime = GetTickCount();
}

bool IsIndicatorHidden() {
    uint now = GetTickCount();
    if(now - g_isHiddenCacheTime > HIDDEN_CACHE_TTL_MS)
        RefreshIsHiddenCache();
    return g_isHiddenCached;
}

//+------------------------------------------------------------------+
//| P-UI-93 â€” THE WRITE OWNER FOR THE F MUTE, beside the read owner.  |
//|                                                                   |
//| Reported: Â«Ø§ÛŒÙ† Ø±ÙˆØ´Ù† Ùˆ Ø®Ø§Ù…ÙˆØ´ Ú©Ø±Ø¯Ù† Ø³Ø·ÙˆØ­ Ø±ÙˆÛŒ Ø¨Ù‚ÛŒÙ‡ Ù„ÛŒØ¨Ù„Ù‡Ø§ Ú†Ø±Ø§ ØªØ§Ø«ÛŒØ±    |
//| Ù…ÛŒØ²Ø§Ø±Ù‡ ... Ø§ÛŒÙ† Ø¯Ú©Ù…Ù‡ Ù‡Ø§ÛŒ Ø¨Ø§ Ù¾Ù†Ù„ Ù‡Ù…Ø§Ù‡Ù†Ú¯ Ù†ÛŒØ³ØªØ´ Ù‡Ù…Ù‡ Ø±Ùˆ Ù‡Ù…Ø§Ù‡Ù†Ú¯ Ú©Ù†Â».     |
//|                                                                   |
//| The mute is the ONE term the whole ENGINE already shares:          |
//| IsIndicatorHidden() gates the labels, the zones, the level writer  |
//| and the mode labels (30-odd sites across LabelFunctions,           |
//| LevelPipeline, ObjectFunctions, UtilityFunctions, VisibilityManager|
//| and ExtendedDrawingFunctions), and the countdown's own owner spells |
//| its switch `inpShowLiveCountdown && !IsIndicatorHidden()`. So the   |
//| engine never needed this fix.                                      |
//|                                                                   |
//| The PANEL did: its family rows answered the STORED switch alone, so |
//| after an F press every row still claimed its family was painted     |
//| while the chart was blank - the two controls answering different    |
//| questions, the same disagreement P-PERF-41 fixed for the zone walk.|
//|                                                                   |
//| TWO callers only - the F transition and the panel row that releases |
//| the mute - and both come through here, so the GlobalVariable and the |
//| TTL cache can never disagree with each other.                       |
//+------------------------------------------------------------------+
void SetIndicatorHiddenState(const bool hidden)
{
    string gvar_name = "Biotak_isHidden_" + GetCachedChartIdStr();
    if(!GlobalVariableSet(gvar_name, hidden ? 1.0 : 0.0))
        LOG_W(LOG_CAT_KEYS, "hidden state: Failed to set GlobalVariable, Error: " + IntegerToString(GetLastError()));
    // Same-line refresh: the reader is TTL-cached, and the panel reads it in
    // the SAME event as the press - a stale cache would repaint the row with
    // the old answer and the desync would survive one more frame.
    RefreshIsHiddenCache();
}

//+------------------------------------------------------------------+
//| Sanitize Symbol Name (cached, matching MT5)                      |
//+------------------------------------------------------------------+
string SanitizeSymbolName(const string symbol) {
    // PERF: Cache result since symbol never changes during indicator lifetime
    static string s_cachedInput = "";
    static string s_cachedResult = "";
    if(symbol == s_cachedInput && s_cachedResult != "") return s_cachedResult;
    s_cachedInput = symbol;
    string safe = symbol;
    // Remove all unsafe characters via loop
    static const string unsafeChars[] = {"_","|",":","/","\\", " ",".","*","?","<",">","\"","'","-"};
    int numChars = ArraySize(unsafeChars);
    for(int i = 0; i < numChars; i++)
        StringReplace(safe, unsafeChars[i], "");
    if(StringLen(safe) == 0) safe = "UNKNOWN";
    if(StringLen(safe) > 50) safe = StringSubstr(safe, 0, 50);
    s_cachedResult = safe;
    return safe;
}

// Effective SS/LS sequence origin. The chart menu override takes priority
// over the input and survives a redraw/timeframe change.
bool GetEffectiveSSLSLongFirst()
{
    if(g_sslsFirstOverride == 0) return false;
    if(g_sslsFirstOverride == 1) return true;
    return inpLSFirst;
}

//+------------------------------------------------------------------+
//| P-UI-67 â€” THE TWO WRITERS OF ONE QUESTION, IN ONE PLACE.        |
//|                                                                  |
//| "Which of SS/LS comes first?" has two surfaces: the chart prompt  |
//| (double-click Custom Price) answers it PER CHART and persists the |
//| answer under a `Biotak_SSLSFirst_` key, and the panel's SS/LS      |
//| ORDER switch answers the DEFAULT. The override WINS (see           |
//| GetEffectiveSSLSLongFirst), so pressing the switch while a stale   |
//| override existed wrote `g_lsFirst` and changed nothing on the      |
//| chart â€” a row that looks dead, and the same "two owners disagree"   |
//| shape as the zone picture's retired third pill (P-UI-62).          |
//|                                                                  |
//| One owner per DIRECTION, so the chart always uses the last thing    |
//| the user actually touched: the prompt SETS (and persists), the      |
//| panel CLEARS (and drops the key), and the reset path clears too.    |
//| Both are pure state writers â€” no caller has to remember the key     |
//| name, and no writer can forget to delete it.                       |
//+------------------------------------------------------------------+
void SSLSOrderOverrideSet(const int v)
{
    if(v != 0 && v != 1) { SSLSOrderOverrideClear(); return; }
    g_sslsFirstOverride = v;
    GlobalVariableSet("Biotak_SSLSFirst_" + GetCachedChartIdStr(), (double)v);
}
void SSLSOrderOverrideClear()
{
    g_sslsFirstOverride = -1;
    GlobalVariableDel("Biotak_SSLSFirst_" + GetCachedChartIdStr());
}

//+------------------------------------------------------------------+
//| Cleanup All GlobalVariables (array-based, matching MT5)          |
//+------------------------------------------------------------------+
//| VIEW LOCK core â€” VIEWLOCK-OFF: retired, kept dormant (see note above).|
//| Anchor (first-visible-bar time + visible price min/max) is       |
//| captured on scroll/zoom, at enable time, and at the TF-switch    |
//| handoff in OnDeinit(REASON_CHARTCHANGE); OnInit re-arms it and   |
//| the first OnCalculate restores it. Pure Chart*/GV calls only â€”  |
//| callable from anything included after this file.                 |
//+------------------------------------------------------------------+
string ViewLockGV(const string key)
{
    return "Biotak_" + key + "_" + GetCachedChartIdStr();
}

void ViewLockPersistAnchor()
{
    GlobalVariableSet(ViewLockGV("ViewAnchorT"), (double)g_viewAnchorTime);
    GlobalVariableSet(ViewLockGV("ViewAnchorMin"), g_viewAnchorMin);
    GlobalVariableSet(ViewLockGV("ViewAnchorMax"), g_viewAnchorMax);
}

void ViewLockCapture()
{
    int bars = iBars(_Symbol, CompatTF(Period()));
    if(bars <= 0) return;
    int firstVisible = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
    if(firstVisible < 0 || firstVisible >= bars) return;
    datetime t = iTime(_Symbol, CompatTF(Period()), firstVisible);
    if(t <= 0) return;
    double mn = ChartGetDouble(0, CHART_PRICE_MIN);
    double mx = ChartGetDouble(0, CHART_PRICE_MAX);
    if(mx <= mn) return;
    g_viewAnchorTime = t;
    g_viewAnchorMin = mn;
    g_viewAnchorMax = mx;
    ViewLockPersistAnchor();
}

// Returns true when the pending restore is settled (applied or moot).
bool ViewLockRestore()
{
    if(g_viewAnchorTime <= 0 || g_viewAnchorMax <= g_viewAnchorMin) return true;
    if(iBars(_Symbol, 0) <= 5) return false;   // history not ready â€” retry next tick
    int sh = iBarShift(_Symbol, 0, g_viewAnchorTime, false);
    if(sh < 0) return false;                  // anchor not in history yet â€” retry
    ChartSetInteger(0, CHART_AUTOSCROLL, false);
    ResetLastError();
    bool ok = ChartSetInteger(0, CHART_FIRST_VISIBLE_BAR, sh);
    if(!ok || GetLastError() != 0)
    {
        // Fallback: relative navigate so the anchor bar lands at the left edge
        int cur = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
        ChartNavigate(0, CHART_CURRENT_POS, sh - cur);
    }
    ChartSetInteger(0, CHART_SCALEFIX, true);
    ChartSetDouble(0, CHART_FIXED_MAX, g_viewAnchorMax);
    ChartSetDouble(0, CHART_FIXED_MIN, g_viewAnchorMin);
    ViewAnchorLineEnsure();
    return true;
}

void ViewLockSetEnabled(const bool on)
{
    g_viewLockEnabled = on;
    GlobalVariableSet(ViewLockGV("ViewLock"), on ? 1.0 : 0.0);
    if(on)
    {
        ViewLockCapture();   // anchor = wherever the view is right now
        ViewAnchorLineEnsure();
    }
    else
    {
        ViewAnchorLineDelete();
        // Hand the chart back: auto-scroll + auto-scale like a plain chart
        ChartSetInteger(0, CHART_AUTOSCROLL, true);
        ChartSetInteger(0, CHART_SCALEFIX, false);
        g_viewRestorePending = false;
    }
}

// Anchor handle â€” visible only while locked with a valid anchor. Repositioned
// by ensure (enable/restore/init); moved by the user via drag (drag-end
// handler commits the line time as the new anchor); deleting the line turns
// the lock off (handled in OnChartEvent, not here).
void ViewAnchorLineEnsure()
{
    if(!g_viewLockEnabled || g_viewAnchorTime <= 0)
    {
        ObjectDelete(0, g_viewAnchorLineName);
        return;
    }
    if(ObjectFind(0, g_viewAnchorLineName) < 0)
    {
        if(!ObjectCreate(0, g_viewAnchorLineName, OBJ_VLINE, 0, g_viewAnchorTime, 0)) return;
    }
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_TIME, 0, (long)g_viewAnchorTime);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_COLOR, BIO_CLR_BRAND);   // P-UI-117
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_SELECTABLE, true);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_ZORDER, Z_CHART_LABEL);   // P-UI-31
    ObjectSetInteger(0, g_viewAnchorLineName, OBJPROP_BACK, false);
    ObjectSetString(0, g_viewAnchorLineName, OBJPROP_TOOLTIP,
                    "View anchor â€” drag to move the locked view Â· Del turns View Lock off");
}

void ViewAnchorLineDelete()
{
    ObjectDelete(0, g_viewAnchorLineName);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-PERF-38c/38f: THE ONE-TIME LEGACY-NAMING MIGRATION STAMP        |
//|                                                                  |
//| Two places care whether this chart still carries objects named by  |
//| the OLD timeframe-in-the-name scheme: the migration that removes  |
//| them (EventHandlers.OnInit) and the label sweep that used to      |
//| remove the label half of them on EVERY timeframe switch          |
//| (LabelFunctions.ClearAllLabels). They must not each own a copy of  |
//| the stamp name, and LabelFunctions is included BEFORE            |
//| EventHandlers, so the owner lives here with the rest of the state. |
//+------------------------------------------------------------------+
string NameSchemeStampName() { return "Biotak_NameScheme_" + GetCachedChartIdStr(); }
bool LegacyNameSchemeMigrated() { return GlobalVariableCheck(NameSchemeStampName()); }

//+------------------------------------------------------------------+
//| P-UI-40 - A STATE CHANGE FROM A PATH THAT CANNOT REPAINT MUST ASK  |
//|                                                                  |
//| The panel's rows read LIVE globals (PnlCurrentSet), so the VALUE    |
//| can never disagree between the keyboard and the panel. The IMAGE    |
//| can: a switch is an OBJ_BITMAP_LABEL whose bitmap is only replaced  |
//| by a paint pass. Every writer INSIDE the panel file repaints its    |
//| own row after a press, and the panel file is included AFTER         |
//| EventHandlers â€” where every HOTKEY lives. So a hotkey changed the    |
//| state, the chart obeyed, and an open card kept showing the previous  |
//| switch position until it was reopened. That asymmetry IS the         |
//| "keyboard and panel are out of sync" report.                        |
//|                                                                  |
//| The hotkeys cannot call the panel (include order, and Lite has no     |
//| panel at all), so they raise a request here and the UI layer drains  |
//| it. That is the same owe/drain pair the coop pump uses: one owner,   |
//| one flag, and a no-op in steady state â€” even a hotkey whose row is   |
//| not on screen costs one boolean.                                    |
//+------------------------------------------------------------------+
static bool g_uiSyncRequested = false;
void RequestUISync() { g_uiSyncRequested = true; }
bool UISyncRequested() { return g_uiSyncRequested; }
void UISyncConsume() { g_uiSyncRequested = false; }

//+------------------------------------------------------------------+
//| P-UI-90 â€” THE CHART'S VIEW HAS ONE OWNER (scroll + context menu)  |
//+------------------------------------------------------------------+
// Reported (recurring, and it OUTLIVES the indicator): Â«ÙˆÙ‚ØªÛŒ Ø§Ù†Ø¯ÛŒÚ©Ø§ØªÙˆØ± Ø±Ùˆ
// Ø±ÙˆÛŒ Ú†Ø§Ø±Øª Ù…ÛŒâ€ŒÙ†Ø¯Ø§Ø²Ù… Ø§Ø³Ú©Ø±ÙˆÙ„ Ú†Ø§Ø±Øª Ù‚ÙÙ„ Ù…ÛŒØ´Ù‡ â€¦ Ùˆ ÙˆÙ‚ØªÛŒ Ø­Ø°ÙØ´ Ù…ÛŒâ€ŒÚ©Ù†Ù… Ù‡Ù… Ù‡Ù…Ú†Ù†Ø§Ù†
// Ù‚ÙÙ„ Ù…ÛŒâ€ŒÙ…ÙˆÙ†Ù‡Â». Four writers owned the same two chart properties (the ring/panels,
// the Base/Knot tool, the custom-price line drag and the watchdog) and each one SAVED
// "what the user had" and wrote it back ITSELF â€” so the pair was READ while another
// owner already held the lock (OUR OWN `false` recorded as the user's preference) and
// whoever released LAST restored it. A one-way ratchet, and it survives Remove because
// the properties belong to the CHART and not to the indicator.
// ONE owner now: CAPTURE on the 0 -> 1 step of ONE shared refcount (the only instant
// nobody else holds the lock), RESTORE on the 1 -> 0 step or a force-release from that
// one pair, persisted per chart, and written only ON DRIFT (steady state: two reads).
// `ChartViewLockForceRelease()` is the net every teardown and watchdog calls; the
// one-time heal hands back a chart whose BOTH props read false with no owner live â€” the
// exact signature our own lock writes (a user's pair is never that).
//+------------------------------------------------------------------+
static int  s_viewLockCount     = 0;      // live owners (ring/panels + tool + line)
static bool s_viewScrollUser    = true;   // the USER's pair - captured at 0 -> 1 ONLY
static bool s_viewCtxUser       = true;
static bool s_viewPersistKnown  = false;  // the pair is mirrored in the GVars below
static bool s_viewPersistScroll = true;   // last pair PERSISTED (change guard)
static bool s_viewPersistCtx    = true;
static bool s_viewInitDone      = false;

bool ChartViewLockHeld()  { return (s_viewLockCount > 0); }

// ONE accessor per family: the literal keeps a single owner, and the
// REASON_REMOVE purge reaches it by NAME (see CleanupAllGlobalVariables and the
// teardown census that enforces it).
string ChartViewScrollGV() { return "Biotak_ViewScroll_" + GetCachedChartIdStr(); }
string ChartViewCtxGV()    { return "Biotak_ViewCtx_"    + GetCachedChartIdStr(); }
string ChartViewKnownGV()  { return "Biotak_ViewKnown_"  + GetCachedChartIdStr(); }

// Persist the user's pair - change-guarded, so a gesture that starts on the
// same pair as the last one costs nothing.
void ChartViewPersistUser()
{
    if(s_viewPersistKnown && s_viewScrollUser == s_viewPersistScroll &&
       s_viewCtxUser == s_viewPersistCtx) return;
    GlobalVariableSet(ChartViewScrollGV(), s_viewScrollUser ? 1.0 : 0.0);
    GlobalVariableSet(ChartViewCtxGV(),    s_viewCtxUser    ? 1.0 : 0.0);
    GlobalVariableSet(ChartViewKnownGV(),  1.0);
    s_viewPersistScroll = s_viewScrollUser;
    s_viewPersistCtx    = s_viewCtxUser;
    s_viewPersistKnown  = true;
}

// The lock's own state. Read-guarded on every write.
// CTXMENU-OFF (P-UI-100d, 2026-09-23): the menu half is RETIRED BY MEASUREMENT.
// `CHART_CONTEXT_MENU` is a STUB on MT4 - `ChartSetInteger(0, ..., true)` returns
// FALSE (refused) and `ChartGetInteger` answers 0 forever, while the control
// property `CHART_MOUSE_SCROLL` reads back its own real value (the terminal's own
// log: `[ctxmenu] impl-probe: mouseScroll=1 write(true)=refused readback=0 =>
// STUB`). Writing it locked nothing, so the lock now holds the ONE property that
// exists. Only `CHART_MOUSE_SCROLL` is locked.
void ChartViewForceLocked()
{
    if((bool)ChartGetInteger(0, CHART_MOUSE_SCROLL))
        ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
}


// Hand the view back to the captured pair - and ONLY the props that actually
// drifted, so a user who disables scroll between gestures is never overridden
// and a restore costs zero terminal writes in steady state.
void ChartViewRestoreUser()
{
    if(((bool)ChartGetInteger(0, CHART_MOUSE_SCROLL)) != s_viewScrollUser)
        ChartSetInteger(0, CHART_MOUSE_SCROLL, s_viewScrollUser);
    // P-UI-114: menu half never restored - stub, unwritable (CTXMENU-OFF).
}



// THE taker. Every caller pairs it with exactly one Release.
void ChartViewLockAcquire()
{
    if(s_viewLockCount == 0)
    {
        // P-UI-114: no suppression exists - live value IS the user.
        s_viewCtxUser = (ChartGetInteger(0, CHART_CONTEXT_MENU) != 0);
        ChartViewPersistUser();
    }
    s_viewLockCount++;
    ChartViewForceLocked();
}

// THE giver-backer. Restores on the LAST release, never before.
void ChartViewLockRelease()
{
    if(s_viewLockCount <= 0) return;   // a release without a claim is a no-op, never an underflow
    s_viewLockCount--;
    if(s_viewLockCount == 0) ChartViewRestoreUser();
}

// Re-force an OWNED lock - every throttled step of every gesture. A third
// writer (a template reset, a leaked native drag) can flip the props back while
// the button is down; read-guarded, so steady state is two reads.
void ChartViewLockAssert()
{
    if(s_viewLockCount <= 0) return;
    ChartViewForceLocked();
}

// The watchdog's "one lock is enough" - clamp a surplus without touching props.
void ChartViewLockClampToOne()
{
    if(s_viewLockCount > 1) s_viewLockCount = 1;
}

// THE NET: every teardown (all reasons) and every watchdog calls this, so
// whatever the counters believe, the chart gets the USER's view back.
void ChartViewLockForceRelease()
{
    s_viewLockCount = 0;
    ChartViewRestoreUser();
}

// Once per instance, BEFORE any owner can take the lock.
void ChartViewLockInit()
{
    if(s_viewInitDone) return;
    s_viewInitDone = true;

    bool liveScroll = (ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0);
    bool liveCtx    = (ChartGetInteger(0, CHART_CONTEXT_MENU) != 0);

    if(GlobalVariableCheck(ChartViewKnownGV()))
    {
        s_viewScrollUser = (GlobalVariableGet(ChartViewScrollGV()) != 0.0);
        s_viewCtxUser    = (GlobalVariableGet(ChartViewCtxGV())    != 0.0);
        // The GVars already hold this exact pair: nothing to write below.
        s_viewPersistKnown = true;
    }
    else if(!liveScroll && !liveCtx)
    {
        // No memory of this chart AND the lock signature: an older build (or a
        // template saved mid-gesture) left it locked. MT4 ships both ON and no
        // consumer leaves exactly one of the pair off under a lock, so ON/ON is
        // what preceded it.
        s_viewScrollUser = true;
        s_viewCtxUser    = true;
        // This chart has no memory yet, so the memory MUST be created here -
        // otherwise every later attach re-learns the pair from whatever the
        // props happen to read and the heal could never tell "the user turned
        // both off" from "an older build left them off".
        s_viewPersistKnown = false;
    }
    else
    {
        // A fresh chart, seen for the first time: the live props ARE the user's.
        s_viewScrollUser   = liveScroll;
        s_viewCtxUser      = liveCtx;
        s_viewPersistKnown = false;   // create the memory (see the branch above)
    }

    s_viewPersistScroll = s_viewScrollUser;
    s_viewPersistCtx    = s_viewCtxUser;
    ChartViewPersistUser();   // no-op when the GVars already hold this pair

    // The one-time heal - narrow by construction (see the block note above).
    if(!liveScroll && !liveCtx && (s_viewScrollUser || s_viewCtxUser))
    {
        ChartViewRestoreUser();
        _LOG_GATE_W Print("[W][UI] P-UI-90: healed a chart-view lock (scroll + context menu "
                          "were BOTH off with no gesture live) - the chart is the user's again");
    }
}

void CleanupAllGlobalVariables() {
    string chartIdStr = GetCachedChartIdStr();
    string rawSymbolName = GetCachedSymbol();
    string sanitizedSymbolName = SanitizeSymbolName(rawSymbolName);
    string gvars[];
    ArrayResize(gvars, 32);
    gvars[24] = "Biotak_CustomPrice_" + chartIdStr;             // P-UI-56: the live (chart-scoped) pair
    gvars[25] = "Biotak_CustomPriceOverride_" + chartIdStr;     //   must not outlive the indicator
    gvars[0]  = "Biotak_isHidden_" + chartIdStr;
    gvars[1]  = "Biotak_CustomPrice_" + rawSymbolName;
    gvars[2]  = "Biotak_LockTF_" + chartIdStr;
    gvars[3]  = "Biotak_LockTFPeriod_" + chartIdStr;
    gvars[4]  = "Biotak_TriggerLevels_" + chartIdStr;
    gvars[5]  = "Biotak_CustomPriceOverride_" + rawSymbolName;
    gvars[6]  = "Biotak_StepMode_" + chartIdStr;
    gvars[7]  = "Biotak_Factor_" + chartIdStr;
    gvars[8]  = "Biotak_TH3Freq_" + chartIdStr;
    gvars[9]  = "Biotak_TH3FreqIdx_" + chartIdStr;
    gvars[10] = "Biotak_LinesVisible_" + chartIdStr;
    gvars[11] = "Biotak_ATRLabels_" + chartIdStr;
    gvars[12] = "Biotak_THLabels_" + chartIdStr;
    gvars[13] = "Biotak_LastTFSwitch_" + chartIdStr;
    gvars[14] = "Biotak_BaseInit_" + chartIdStr;
    gvars[15] = "Biotak_ATRWarmup_" + chartIdStr;
    gvars[16] = "Biotak_TH3_NeedsUpdate_" + chartIdStr;
    gvars[17] = "Biotak_SSLSFirst_" + chartIdStr;
    gvars[18] = "Biotak_CustomPrice_" + sanitizedSymbolName;
    gvars[19] = "Biotak_CustomPriceOverride_" + sanitizedSymbolName;
    gvars[20] = "Biotak_ViewLock_" + chartIdStr;
    gvars[21] = "Biotak_ViewAnchorT_" + chartIdStr;
    gvars[22] = "Biotak_ViewAnchorMin_" + chartIdStr;
    gvars[23] = "Biotak_ViewAnchorMax_" + chartIdStr;
    // P-UI-90: the view-ownership pair + its stamp go with the chart they
    // describe - a REMOVE empties the chart, so nothing here has a reason to
    // outlive it (and the next attach re-learns the user's pair from the props
    // themselves).
    gvars[26] = "Biotak_ViewScroll_" + chartIdStr;
    gvars[27] = "Biotak_ViewCtx_" + chartIdStr;
    gvars[28] = "Biotak_ViewKnown_" + chartIdStr;
    gvars[29] = "Biotak_StepFactor_" + chartIdStr;              // P-UI-98: the step override dies with the chart
    gvars[30] = "Biotak_LockTFSym_" + rawSymbolName;              // P-UI-142: the lock's symbol twins
    gvars[31] = "Biotak_LockTFPeriodSym_" + rawSymbolName;
    for(int i = 0; i < ArraySize(gvars); i++) {
        if(GlobalVariableCheck(gvars[i])) GlobalVariableDel(gvars[i]);
    }
    // Base/Knot tool direction keys are dynamic (one per box id) â€” sweep by
    // prefix so a removed indicator never leaves stale direction state.
    // (P-DRAW-05 retired: the drawing toolbar's templates live in a FILE now â€”
    //  P-DRAW-07 â€” because a slot's NAME does not fit in a double. Nothing of
    //  ours is left in the GV table, so this sweep stays the box's own.)
    // P-UI-142: the BKS_ symbol twins die here too (same boxes, other prefix).
    for(int k = GlobalVariablesTotal() - 1; k >= 0; k--)
    {
        string bkn = GlobalVariableName(k);
        if(StringFind(bkn, "Biotak_BK_") == 0) GlobalVariableDel(bkn);
        if(StringFind(bkn, "Biotak_BKS_") == 0) GlobalVariableDel(bkn);
    }
}

//+------------------------------------------------------------------+
//| Restore Bool GlobalVar (epsilon-based, matching MT5)             |
//+------------------------------------------------------------------+
bool RestoreBoolGlobalVar(const string gvarName, bool defaultVal) {
    if(GlobalVariableCheck(gvarName)) {
        double gvarValue = GlobalVariableGet(gvarName);
        bool isZero = MathAbs(gvarValue - 0.0) < EPSILON_GENERAL;
        bool isOne  = MathAbs(gvarValue - 1.0) < EPSILON_GENERAL;
        if(isZero || isOne) {
            return isOne;
        } else {
            DEBUG_PRINTF2("OnInit: Corrupted state for ", gvarName, ", resetting");
            GlobalVariableSet(gvarName, defaultVal ? 1.0 : 0.0);
            return defaultVal;
        }
    }
    return defaultVal;
}

//+------------------------------------------------------------------+
//| P-ANCHOR-LAST - the ONE active historical calculation anchor.       |
//|                                                                  |
//| The newest committed LegMeasure or BaseKnot owns the read: its    |
//| end bar is written here, and the ATR layer reads every live       |
//| composite AT that bar while the ATR card's LAST OBJECT switch is  |
//| ON. The switch is per chart and survives an attach; the active    |
//| object itself is deliberately NOT persisted (an object list can   |
//| differ after a restart, so restoring a name would anchor to a     |
//| ghost). Deleting the owner clears the anchor; drawing again       |
//| re-arms it. Cost: two compares in the ATR read, and writes only   |
//| on commit/delete/toggle.                                         |
//+------------------------------------------------------------------+
static bool     g_calcAnchorOn        = false;
static datetime g_calcAnchorTime      = 0;
static string   g_calcAnchorOwner     = "";
static datetime g_calcAnchorLastTime  = 0;
static string   g_calcAnchorLastOwner = "";

// The owner's functions live in their own unit; the state above is read here so
// every test harness that includes GlobalVariables gets the same API as the product.
#include "CalcAnchor.mqh"

#endif // GLOBAL_VARIABLES_MQH
