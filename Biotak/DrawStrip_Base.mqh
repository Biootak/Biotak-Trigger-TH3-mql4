// DrawStrip_Base.mqh - DrawStrip split 2026-09-29: exact lines 678-1460 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_BASE_MQH
#define DRAW_STRIP_BASE_MQH

void DrawStripGripRelease()
{
   // P-DRAW-32: either carry owns the lock — one release ends whichever is live.
   // P-DRAW-48: and the BOARD's carry is the third, the opacity bar's own drag the
   // fourth (four owners, ONE ender — the button-up net, the close and Esc all
   // come through here).
   if(s_dsGripLive || s_dsGGripLive || s_dsBGripLive || s_dsOpGrab || s_dsPalGrab)
      ChartViewLockRelease();   // P-UI-90: one release per acquire
   s_dsGripLive = false;
   s_dsGGripLive = false;
   s_dsBGripLive = false;
   s_dsOpGrab = false;
   s_dsPalGrab = false;
}
//--- P-DRAW-31 (2026-09-24) — THE STRIP PUBLISHES ITS PLATE. The cards' placement
//--- (`PnlComputePosition`) cannot see this module (included after us, MQL4 is
//--- define-before-use), so the plate's rect is handed over instead: one writer, from
//--- every path that moves, opens or closes the strip, cleared when it is off screen.
//--- `-1` is the "no strip" answer — the same contract `g_UIPanelR*` uses.
//--- P-DRAW-32: and the SETTINGS PANEL is published with it — the two surfaces are ONE
//--- occupancy for every reader (a card must clear both, and a fresh strip must clear
//--- both), so the rect handed over is their UNION while the panel is open. One
//--- contract, one writer, no second global to keep in sync.
// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-64 (2026-09-27) — TWO COLOUR CELLS, ONE BOARD. User order: «رنگ بوردر
// بشه جدا تنظیم کرد ... و fill همه جدا. یک بخش براش اضافه کن». The owner module
// declares `DRAW_SLOT_FILLCLR` (the interior); HERE it is a COLOUR CELL exactly like
// `DRAW_SLOT_COLOR` — own swatch, board and tone — so every surface asks these two
// questions instead of naming one slot. Which board is open stays `s_dsPicker`.
// ══════════════════════════════════════════════════════════════════════════
bool DrawStripIsColorSlot(const int slot)
{
   return (slot == DRAW_SLOT_COLOR || slot == DRAW_SLOT_FILLCLR);
}
color DrawStripColorRead(const string nm, const int slot)
{
   return (color)(int)DrawSlotRead(nm, slot);
}
//--- what a colour CELL shows: the border cell stores and shows the pure colour,
//--- the interior cell shows the pixel the chart will wear (its own tone applied) —
//--- so the two cells are never two answers to one question.
color DrawStripColorFace(const string nm, const int slot)
{
   color c = DrawStripColorRead(nm, slot);
   if(slot != DRAW_SLOT_FILLCLR) return c;
   return DrawSlotRenderFillColor(nm, c);
}

void DrawStripPublishRect()
{
   if(!s_dsOpen || s_dsW <= 0 || s_dsH <= 0)
   {
      g_UIStripRX = -1; g_UIStripRY = -1; g_UIStripRW = 0; g_UIStripRH = 0;
      return;
   }
   int x1 = s_dsX - DSTRIP_SKIN_M;
   int y1 = s_dsY - DSTRIP_SKIN_M;
   int x2 = s_dsX + s_dsW + DSTRIP_SKIN_M;
   int y2 = s_dsY + s_dsH + DSTRIP_SKIN_M;
   if(s_dsGear != 0 && s_dsGearW0 > 0 && s_dsGearH > 0)
   {
      if(s_dsGEX - DSTRIP_SKIN_M < x1) x1 = s_dsGEX - DSTRIP_SKIN_M;
      if(s_dsGEY - DSTRIP_SKIN_M < y1) y1 = s_dsGEY - DSTRIP_SKIN_M;
      if(s_dsGEX + s_dsGearW0 + DSTRIP_SKIN_M > x2) x2 = s_dsGEX + s_dsGearW0 + DSTRIP_SKIN_M;
      if(s_dsGEY + s_dsGearH + DSTRIP_SKIN_M > y2) y2 = s_dsGEY + s_dsGearH + DSTRIP_SKIN_M;
   }
   //--- P-DRAW-48: the COLOUR BOARD is occupancy too — a card placed by the
   //--- neighbours must clear it, and a fresh board must clear them.
   if(DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0)
   {
      if(s_dsBX - DSTRIP_SKIN_M < x1) x1 = s_dsBX - DSTRIP_SKIN_M;
      if(s_dsBY - DSTRIP_SKIN_M < y1) y1 = s_dsBY - DSTRIP_SKIN_M;
      if(s_dsBX + s_dsBW + DSTRIP_SKIN_M > x2) x2 = s_dsBX + s_dsBW + DSTRIP_SKIN_M;
      if(s_dsBY + s_dsBH + DSTRIP_SKIN_M > y2) y2 = s_dsBY + s_dsBH + DSTRIP_SKIN_M;
   }
   g_UIStripRX = x1;
   g_UIStripRY = y1;
   g_UIStripRW = x2 - x1;
   g_UIStripRH = y2 - y1;
}
//--- P-UI-113c (2026-09-23): THE OPENING PRESS'S OWN CLICK-FAMILY WINDOW. The hold
//--- fires while the button is STILL DOWN, so the release that ends it lands on the
//--- drawing = outside the strip, and the TV-style dismissal would close what the
//--- hold just opened («چرا با رها کردن هولد استریپ هم بسته میشه»). A one-shot flag
//--- cannot fix it: ONE release is reported on more than one channel (the chart's
//--- own CHARTEVENT_CLICK and the object's OBJECT_CLICK), so a shot spends the
//--- first while the second dismisses the strip the user was just shown. So it is a
//--- WINDOW, re-armed by the press's own witnesses: ARM at the fire for the
//--- press's whole life, the MOVE STREAM's release witness shortens it to the
//--- twin-event tail, a new press edge (or a close) ends it.
#define DSTRIP_OPEN_TAIL_MS      800     // twin-event tail after the release witness
#define DSTRIP_OPEN_PRESS_MAX_MS 10000   // the longest a press may claim its own clicks
static uint s_dsOpenerUntil = 0;         // 0 = disarmed; else the press's own deadline
static uint s_dsOpenerTailUntil = 0;     // the twin-event tail (after the release witness)
void DrawStripOpenerArm()    { s_dsOpenerUntil = GetTickCount() + DSTRIP_OPEN_PRESS_MAX_MS; s_dsOpenerTailUntil = 0; }
void DrawStripOpenerDisarm() { s_dsOpenerUntil = 0; s_dsOpenerTailUntil = 0; }
bool DrawStripOpenerClickSpent() { return (TickDeadlinePending(s_dsOpenerUntil) || TickDeadlinePending(s_dsOpenerTailUntil)); }
//--- P-UI-113g (2026-09-24): SELECTION IS REPAIRED AFTER MT4'S CLICK, NOT INSIDE
//--- THE CLICK CALLBACK. P-UI-113f selected the hold target both at the fire and
//--- on the release event, but MT4 commits the terminal's own press/release
//--- selection state after this callback returns. Its last step therefore cleared
//--- the eight handles/context toolbar that the release had just restored. The
//--- repair belongs to the already-running tick/timer pump: one bounded wait past
//--- the event, guarded writes only, and a new press or a close cancels it so the
//--- user's next gesture always wins.
//--- The name is explicit because a same-object CHART_CHANGE/OBJECT_DRAG ride
//--- rebuilds the strip through DrawStripClose; OpenAt snapshots and restores this
//--- repair exactly as it restores the opening-press window.
#define DSTRIP_SELECT_REPAIR_DELAY_MS 120   // let MT4 finish the release callback first
#define DSTRIP_SELECT_REPAIR_TTL_MS   1800  // bounded proof window, not a selection lock
static string s_dsSelectRepairName = "";
static uint   s_dsSelectRepairAt = 0;      // first post-event repair is legal here
static uint   s_dsSelectRepairUntil = 0;   // 0 = no repair pending
void DrawStripHoldSelectionDisarm()
{
   s_dsSelectRepairName = "";
   s_dsSelectRepairAt = 0;
   s_dsSelectRepairUntil = 0;
}
//--- P-DRAW-17: the left button's press latch, and the ONE owner of the press
//--- edge fact (`s_dsLeftPress`). The trigger needs it (a click, not a drag) and
//--- the grip carry needs it (start a carry on the press) - so the edge is
//--- computed ONCE, in the router head, which runs on EVERY move whether the
//--- strip is open or not. Two owners of "the button just went down" is how the
//--- carry and the trigger would drift apart.
//--- P-UI-113b (2026-09-23): and the head STORES it (`s_dsLeftPrev = tleft`) -
//--- without that one line the "edge" is just the button state, re-read as a
//--- fresh press by every move of a held hand (see the head's own note). The
//--- button-up channels resync it, so an off-window release cannot stick it DOWN.
static bool     s_dsLeftPrev = false;
static bool     s_dsLeftPress = false;   // true on the move that carried the press edge
static int      s_dsPressX = 0, s_dsPressY = 0;
static string   s_dsPressObj = "";       // P-UI-113i: the drawing named by that press
static int      s_dsTravel = 0;          // furthest the LEFT hand got while held
static bool     s_dsPressTracked = false;   // P-UI-113d: a press EDGE was seen for this
                                            // cycle, so `s_dsTravel` is this gesture's
                                            // (a zero-move press leaves no edge: the
                                            // release then reads as a click, never a drag)
//--- P-UI-113j (2026-09-25) — THE PRESS NAMES ITS OWN DRAWING. `s_dsPressObj`
//--- above exists only when the MOVE STREAM carried the press edge: a still press
//--- carries none (P-LM-13). The release then fell back to a live hit test, and
//--- MT4's selected controls are terminal UI - their handles are accepted only
//--- while the object IS selected (P-UI-113h), which the terminal clears around
//--- its own click. Reported: hold a SELECTED drawing, the strip opens, and the
//--- release closes it - while the same gesture works on an unselected one.
//--- So the latch - which hit-tests the press pixel anyway - KEEPS its answer for
//--- the whole press cycle: one hit test per press (P-DRAW-04), selection-free.
static bool     s_dsPressCycle = false;  // the latch named THIS press cycle
static string   s_dsPressCycleObj = "";  // the drawing its press pixel landed on ("" = chart)
static uint     s_dsPressCycleMs = 0;    // the cycle's life bound: the press cap below
void DrawStripPressCycleSet(const string nm)
{ s_dsPressCycle = true; s_dsPressCycleObj = nm; s_dsPressCycleMs = GetTickCount() + DSTRIP_OPEN_PRESS_MAX_MS; }
void DrawStripPressCycleClear() { s_dsPressCycle = false; s_dsPressCycleObj = ""; s_dsPressCycleMs = 0; }
bool DrawStripPressCycleLive()
{ return (s_dsPressCycle && TickDeadlinePending(s_dsPressCycleMs)); }
//--- P-UI-114 (2026-09-23) — dead right-click era deleted (user order:
//--- extra code out, compile back down). The strip opens on a LEFT hold now.

//--- P-DRAW-13: single-step undo — the pre-mutation looks of the group (names +
//--- packed slots), the held drawing's level set, and a duplicate's copy name.
//--- Trash is not undoable (MT4 has no undelete); undo covers looks only.
static bool     s_duValid = false;
static int      s_duN = 0;
static string   s_duName[DSTRIP_UNDO_MAX];
static color    s_duClr[DSTRIP_UNDO_MAX];
static int      s_duW[DSTRIP_UNDO_MAX], s_duSt[DSTRIP_UNDO_MAX];
static int      s_duFill[DSTRIP_UNDO_MAX], s_duRay[DSTRIP_UNDO_MAX];
static color    s_duFillClr[DSTRIP_UNDO_MAX];    // P-DRAW-64: the interior's colour
static int      s_duFillOp[DSTRIP_UNDO_MAX];     // and its own tone
static int      s_duFont[DSTRIP_UNDO_MAX], s_duGlyph[DSTRIP_UNDO_MAX], s_duBack[DSTRIP_UNDO_MAX];
static int      s_duLvN = 0;
static double   s_duLvV[DSTRIP_UNDO_LV];
static color    s_duLvC[DSTRIP_UNDO_LV];
static int      s_duLvW[DSTRIP_UNDO_LV], s_duLvS[DSTRIP_UNDO_LV];
static string   s_duCopy = "";

string DrawStripObjName(const int i)  { return "PnlDrawS_" + IntegerToString(i); }
string DrawStripIconName(const int i) { return "PnlDrawS_" + IntegerToString(i) + "I"; }
//--- the shell chrome: grip (drag), badge (kind xN, info only), actions.
string DrawStripGripName() { return "PnlDrawS_H"; }
string DrawStripGripIconName() { return "PnlDrawS_HI"; }
string DrawStripBadgeName() { return "PnlDrawS_B"; }
string DrawStripActName(const int a) { return "PnlDrawS_A" + IntegerToString(a); }
string DrawStripActIconName(const int a) { return "PnlDrawS_A" + IntegerToString(a) + "I"; }
//--- the popover's rows (P = button, PI = icon face, PT = left-aligned label).
string DrawStripPickName(const int r) { return "PnlDrawS_P" + IntegerToString(r); }
string DrawStripPickIconName(const int r) { return "PnlDrawS_P" + IntegerToString(r) + "I"; }
string DrawStripPickLabelName(const int r) { return "PnlDrawS_P" + IntegerToString(r) + "T"; }
string DrawStripPickChipName(const int r) { return DrawStripPickIconName(r) + "C"; }
string DrawStripPickRailName(const int r) { return DrawStripPickName(r) + "R"; }
//--- P-DRAW-33: the colour surfaces' glass sheen — one face per colour cell, so a
//--- tap on the sheen is a tap on the cell (the `+ "C"` chip pattern, one letter up).
string DrawStripPickGlassName(const int r) { return DrawStripPickName(r) + "G"; }
string DrawStripGridGlassName(const int g) { return DrawStripGridName(g) + "G"; }
//--- TV parity board (2026-09-26): the popover's own chrome — grip seat, the
//--- RECENT band's own cells (the grid is the user's 64 only) and the HEX field.
string DrawStripPHeadGName() { return "PnlDrawS_PHeadG"; }
string DrawStripPHeadGChipName() { return "PnlDrawS_PHeadGC"; }
string DrawStripPHeadGIconName() { return "PnlDrawS_PHeadGI"; }
//--- P-DRAW-92 (2026-09-30) — THE BOARD'S PAGE SEATS, NAMED LIKE EVERY OTHER
//--- BOARD OBJECT. They were spelled inline in the paint (`"PnlDrawS_Page" +
//--- IntegerToString(k)`), and `DrawStripPopChromePrune` — the ONE owner of taking
//--- the board's chrome down (DrawStrip_GearA.mqh) — never listed them: close the
//--- board, or switch a colour slot to a width/style list, and the two `<` `>` seats
//--- and the "1/2" caption stayed floating over the strip. Found by
//--- `node tools/object_lifecycle_check.js` once its helper table went tree-wide:
//--- `DrawStripBtn paints PnlDrawS_Page…"PnlDrawS_Page" — no destroy path`.
string DrawStripPageSeatName(const int k)  { return "PnlDrawS_Page" + IntegerToString(k); }
string DrawStripPageLabelName()            { return "PnlDrawS_PageT"; }
string DrawStripPRecName(const int i) { return "PnlDrawS_PR" + IntegerToString(i); }
string DrawStripPRecGlassName(const int i) { return DrawStripPRecName(i) + "G"; }
string DrawStripPRecLabelName() { return "PnlDrawS_PRecT"; }
string DrawStripPHexLbName() { return "PnlDrawS_PHexLb"; }
string DrawStripPHexEdName() { return "PnlDrawS_PHexEd"; }
//--- P-DRAW-48: the OPACITY band's own five objects (Lb = its label, T = the bed,
//--- F = the filled part, K = the knob, V = the `NN%` readout).
string DrawStripPOpLbName()    { return "PnlDrawS_POpLb"; }
string DrawStripPOpBedName()   { return "PnlDrawS_POpT"; }
string DrawStripPOpFillName()  { return "PnlDrawS_POpF"; }
string DrawStripPOpKnobName()  { return "PnlDrawS_POpK"; }
string DrawStripPOpValName()   { return "PnlDrawS_POpV"; }
//--- the gear panel: tabs (GT), grid cells (GG/GGI), list rows (GR/GRI/GRT),
//--- foot (GF), edits (GE).
string DrawStripGearTabName(const int t) { return "PnlDrawS_GT" + IntegerToString(t); }
string DrawStripGridName(const int g) { return "PnlDrawS_GG" + IntegerToString(g); }
string DrawStripGridIconName(const int g) { return "PnlDrawS_GG" + IntegerToString(g) + "I"; }
string DrawStripRowName(const int r) { return "PnlDrawS_GR" + IntegerToString(r); }
string DrawStripRowIconName(const int r) { return "PnlDrawS_GR" + IntegerToString(r) + "I"; }
string DrawStripRowLabelName(const int r) { return "PnlDrawS_GR" + IntegerToString(r) + "T"; }
string DrawStripRowChipName(const int r) { return DrawStripRowIconName(r) + "C"; }
string DrawStripRowRailName(const int r) { return DrawStripRowName(r) + "R"; }
string DrawStripRowStateName(const int r) { return DrawStripRowName(r) + "S"; }
string DrawStripRowSepName(const int r) { return DrawStripRowName(r) + "L"; }
string DrawStripFootName(const int f) { return "PnlDrawS_GF" + IntegerToString(f); }
string DrawStripFootSkinName(const int f) { return DrawStripFootName(f) + "B"; }
string DrawStripFootGlyphName(const int f) { return DrawStripFootName(f) + "G"; }
string DrawStripFootLabelName(const int f) { return DrawStripFootName(f) + "T"; }
string DrawStripEditName(const int e) { return "PnlDrawS_GE" + IntegerToString(e); }
string DrawStripBgName() { return "PnlDrawS_BG"; }
string DrawStripBoardBgName() { return "PnlDrawS_BBG"; }   // P-DRAW-48: the board's own plate bg
//--- P-DRAW-32: the SETTINGS PANEL's own plate — its own family, so the two
//--- surfaces paint, purge and answer a tap apart (`DrawStripIsBg` matches both).
string DrawStripGearBgName() { return "PnlDrawS_GBG"; }
//--- P-DRAW-29: the tab track — one CARD bed under the tab row so separate
//--- buttons read as one segmented control (the preview's .segPill).
string DrawStripGearTrackName() { return "PnlDrawS_GTrack"; }
string DrawStripGearTabLineName() { return "PnlDrawS_GU"; }
string DrawStripGearHeadName(const string s) { return "PnlDrawS_GH" + s; }
string DrawStripGearSectionName(const int i) { return "PnlDrawS_GS" + IntegerToString(i); }
string DrawStripGearSectionLineName(const int i) { return DrawStripGearSectionName(i) + "L"; }
string DrawStripGearCloseName() { return DrawStripGearHeadName("X"); }
string DrawStripGearCloseSkinName() { return DrawStripGearCloseName() + "B"; }
string DrawStripGearCloseIconName() { return DrawStripGearCloseName() + "I"; }
int    DrawStripGearX() { return s_dsGEX; }   // P-DRAW-32: the panel's own origin
//--- P-DRAW-73: `DrawStripGearCW()` is retired here — 1 hit in the tree (its own
//--- definition) since birth, and the head painter's write to `s_dsGearW` made it
//--- answer 312 where the layout means 280. The paint asks `DSTRIP_GEAR_W - 2*PAD`
//--- (narrow) or `s_dsGearW0 - 2*PAD` (the plate) directly, one line each.
//--- P-DRAW-19 (2026-09-24) — DOES THE CARRY OWN THE VIEW?
//--- The grip carry takes the project's ONE view lock (P-UI-113d:
//--- `ChartViewLockAcquire` at the press edge, `ChartViewLockAssert` on every held
//--- step, `DrawStripGripRelease` at every end). The 250 ms watchdog that rebuilds
//--- that lock from OWNERSHIP intent (`ChartScrollReconcile` -> `ChartLockIntended`,
//--- BiotakPanels.mqh - included AFTER this module, so this accessor is DEFINED
//--- before its ONE reader) must be able to NAME it: without the term the reconcile
//--- reads the carry's lock as a LEAK, hard-releases it inside the first 250 ms of
//--- the gesture and hands the scroll back under the hand - the report this answers
//--- («هنوز هنگام درگ چارت پشتش قفل نمیشه»). P-LM-11/P-BK-62's law, worn here
//--- unchanged: a gesture that takes the view lock names itself in that list the day
//--- it is born. ONE reader, so the answer cannot drift from the lock it explains.
//--- P-DRAW-32: the SETTINGS PANEL's carry takes it too (its header bar is its
//--- handle), so BOTH latches are named here — one reader, two owners. P-DRAW-48:
//--- the OPACITY BAR's own drag, the fourth, added the day it was born (A-09/G-07).
bool   DrawStripViewOwned() { return (s_dsGripLive || s_dsGGripLive || s_dsBGripLive || s_dsOpGrab || s_dsPalGrab); }
//--- P-DRAW-09b: how many drawings this strip is editing (1 = the held one).

//--- P-DRAW-08c: is this point ON the strip? Two gaps came from not asking:
//---   * a button tap also arrives as a chart CLICK on some builds, and the
//---     dismissal branch below ate the strip in the same event that used it;
//---   * a press that lands on the strip must never be read as a press on the
//---     drawing underneath it (the hold's own hit test starts with this).
//--- The size is the one the OPEN measured (`s_dsW`/`s_dsH`), never re-derived
//--- here: this question is asked on the press edge, where a kind lookup would be
//--- work for an answer already in hand.
bool DrawStripPointInside(const int mx, const int my)
{
   if(!s_dsOpen) return false;
   //--- P-DRAW-29: the skin stands DSTRIP_SKIN_M past the content on every
   //--- side — its fringe is plate, not chart.
   int m = DSTRIP_SKIN_M + 2;
   if(s_dsW > 0 && s_dsH > 0 &&
      mx >= s_dsX - m && mx <= s_dsX + s_dsW + m &&
      my >= s_dsY - m && my <= s_dsY + s_dsH + m) return true;
   //--- P-DRAW-32: the SETTINGS PANEL is our surface too. A tap on its plate is
   //--- not a tap on the chart, so it must never dismiss the strip that owns it
   //--- (the panel is where the user was just working).
   if(s_dsGear != 0 && s_dsGearW0 > 0 && s_dsGearH > 0 &&
      mx >= s_dsGEX - m && mx <= s_dsGEX + s_dsGearW0 + m &&
      my >= s_dsGEY - m && my <= s_dsGEY + s_dsGearH + m) return true;
   //--- P-DRAW-48: the COLOUR BOARD is our surface too — it can float anywhere,
   //--- including over the chart, and a click on its plate is not a click on the
   //--- chart (it would dismiss the very strip the board belongs to).
   if(DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0 &&
      mx >= s_dsBX - m && mx <= s_dsBX + s_dsBW + m &&
      my >= s_dsBY - m && my <= s_dsBY + s_dsBH + m) return true;
   return false;
}

// ═══════════════════════════════════════════════════════════════════════════
// P-DRAW-84 (2026-09-29) — THE PANEL'S BUTTONS ARE DEAD, AND THE REASON IS ONE
// FLAG, NOT TWELVE BUGS.
//
// Every painter in this file is born `OBJPROP_SELECTABLE = false`
// (DrawStripBtnZ:3317, DrawStripFaceZ:3366, DrawStripLblAt:3413,
// DrawStripRect:3444), and that is CORRECT for this project: the indicator owns
// all input, and the strip opens by a coordinate hit test (DrawStripOpenAt),
// not by a click on an object. But the gear panel's ROUTER is a NAME router:
// every branch of the CHARTEVENT_OBJECT_CLICK chain at 7408-7433 compares
// `sparam` against a control's own object name — DrawStripGearTabName(t),
// DrawStripRowName(r), DrawStripFootName(f), and so on. MT4 never emits
// OBJECT_CLICK for a non-selectable object, so `sparam` can never BE one of
// those names: every tab, row, switch, grid chip and foot button was dead on a
// green compile. The cards work because BiotakPanels has P-UI-74's
// `PnlClickFallback(mouseX, mouseY)` — the COORDINATE channel gets first
// refusal, the name router only runs when no control acted. The panel had no
// such channel at all.
//
// This function IS that channel for the gear panel, and it is deliberately
// written to read the SAME seat arrays the paint writes (`s_dsGearTabX/W`,
// `s_dsGRY/Col`, `s_dsGGX/Y/W/H`, `s_dsGearFootY`, `s_dsGearEditX/W/Y`,
// `s_dsGEY`, `s_dsGEX`, `s_dsGearW0`) — never a re-derived number. A hit test
// with its own arithmetic is a second grid, which is P-DRAW-77's defect again.
//
// Order is Z-order, topmost first, because the panel's controls overlap: the
// head's X sits over the plate, the tab underline over its tab, the grid chips
// over their row. Returns true when a control acted (the caller spends the
// event); false when the point is dead space, so the name router below can
// still have it.
// ═══════════════════════════════════════════════════════════════════════════
bool DrawStripGearHit(const int mx, const int my)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(s_dsGear == 0 || s_dsGearW0 <= 0 || s_dsGearH <= 0) return false;
   if(mx < s_dsGEX || mx > s_dsGEX + s_dsGearW0) return false;
   if(my < s_dsGEY || my > s_dsGEY + s_dsGearH) return false;

   int gx = s_dsGEX, gy = s_dsGEY;
   int colW = DrawStripGearColW();
   int px = gx + DSTRIP_GEAR_PAD;

   // --- the head's own X, and the grip that carries the panel. Both live in the
   // head band, which is above everything below, so they are asked first. The X's
   // seat is the paint's own: `closeX = gx + W0 - PAD - 26`, at `hy + 17`, 26x26
   // (3913-3914) — the 26 is the cards' own XBTN and is written there twice, so it
   // is read here from the same expression rather than a third literal.
   if(s_dsGearHeadY >= 0)
   {
      int hy = gy + s_dsGearHeadY;
      if(my >= hy && my < hy + DSTRIP_GEAR_HEAD_H)
      {
         const int xbtn = 26;
         int cx0 = gx + s_dsGearW0 - DSTRIP_GEAR_PAD - xbtn;
         int cy0 = hy + 17;
         int mxp = mx - (cx0 + xbtn / 2);
         int myp = my - (cy0 + xbtn / 2);
         int half = xbtn / 2 + 3;                 // the square plus a 3px thumb pad
         if(mxp * mxp + myp * myp <= half * half)
         { DrawStripGearClose(); return true; }
      }
      //--- P-DRAW-85: the head is ALSO the panel's carry. Outside the X, a press
      //--- on it drags the panel (DrawStripGearGripAt owns the exact seat); the
      //--- user could not move the panel at all before this.
      if(DrawStripGearGripAt(mx, my)) return false;   // the grip's own handler acts
   }

   // --- the tab row. The underline (P-DRAW-83) is matched to its tab here too,
   // so a press on the 2px accent under the selected tab is that tab, not dead
   // plate — the same rule the name router states at 7411-7412.
   int ty = gy + s_dsGearTabsY + (DSTRIP_GEAR_ROW_H - DSTRIP_TAB_H) / 2;
   if(my >= ty && my < ty + DSTRIP_TAB_H)
   {
      for(int t = 0; t < s_dsGearTab[0] && t < DSTRIP_GEAR_TAB_MAX; t++)
      {
         int tx = gx + s_dsGearTabX[t], tw = s_dsGearTabW[t];
         if(mx >= tx && mx < tx + tw)
         { DrawStripGearTabTap(t); return true; }
      }
      return false;   // the track between tabs is dead space (P-DRAW-67)
   }

   // --- the hex / text fields: a press takes focus for typing, no action
   // (P-DRAW-48). The seat is the SAME `s_dsGearEditX/W/Y` the paint wrote.
   for(int e = 0; e < 5; e++)
   {
      if(s_dsGearEditW[e] <= 0) continue;
      int ex = px + s_dsGearEditX[e];
      int ey = gy + s_dsGearEditY[e] + (DSTRIP_GEAR_ROW_H - DSTRIP_GEAR_EDIT_H) / 2;
      if(mx >= ex && mx < ex + s_dsGearEditW[e] &&
         my >= ey && my < ey + DSTRIP_GEAR_EDIT_H)
      {
         if(ObjectFind(0, DrawStripEditName(e)) >= 0)
            ObjectSetInteger(0, DrawStripEditName(e), OBJPROP_STATE, true);
         s_dsHexFocus = (e == 0 || e == 4);   // the two colour fields own the hex
         return true;
      }
   }

   // --- the grid chips (Style tab's width / style / ray rows).
   for(int g = 0; g < s_dsGGN && g < DSTRIP_GRID_MAX; g++)
   {
      if(s_dsGGH[g] <= 0) continue;
      int cx = gx + s_dsGGX[g];
      int cy = gy + s_dsGGY[g] + (DSTRIP_GEAR_ROW_H - s_dsGGH[g]) / 2;
      if(mx >= cx && mx < cx + s_dsGGW[g] && my >= cy && my < cy + s_dsGGH[g])
      { DrawStripGridTap(g); return true; }
   }

   // --- the list rows. A row is a full-width CELL (P-DRAW-69: one tone, one
   // owner), so the whole band answers, not just its chip — the same contract
   // the cards' rows have.
   for(int r = 0; r < s_dsGRN && r < DSTRIP_GLIST_MAX; r++)
   {
      int ry = gy + s_dsGRY[r];
      if(my < ry || my >= ry + DSTRIP_GEAR_ROW_H) continue;
      int rx = px + s_dsGRCol[r] * DSTRIP_GEAR_COL;
      if(mx < rx || mx >= rx + colW) continue;
      DrawStripGearRowTap(r);
      return true;
   }

   // --- the foot (All / Copy). The seats are the paint's own, read not re-derived
   // (4281-4283): the ghost face is `fx-8`, `fy-8`, `bw+16` x `44` around a 28px
   // button at `fy = footY + 10`. The hit box is the GHOST, not the button — a hand
   // aims at the plate it can see, and the ghost is 8px of it on every side.
   const int fpad = 8, fbtnH = 28, ftop = 10;
   int fy0 = gy + s_dsGearFootY;
   //--- P-DRAW-90: the width AND the seat are the paint's own owners now
   //--- (DrawStripFootBw / DrawStripFootX), read here, never re-derived: the old
   //--- `px + f*(bw+gap)` stood in this file and in DrawStripGearPaint at once,
   //--- and the moment `Reset` moves the pair to the right edge the two would
   //--- have disagreed on screen. `colW` is the same DrawStripGearColW() the
   //--- paint passes (280 on a 312 tab, 592 on a 624 one).
   for(int f = 0; f < DSTRIP_GEAR_FOOT_N; f++)
   {
      int bw = DrawStripFootBw(f);
      int fx = DrawStripFootX(f, px, colW);
      int fy = fy0 + ftop;
      if(mx >= fx - fpad && mx < fx + bw + fpad &&
         my >= fy - fpad && my < fy + fbtnH + fpad)
      { DrawStripFootTap(f); return true; }
   }

   return false;   // the plate's own dead space: never a tap
}

bool DrawStripClickFamily()
{
   UISuppressNextClick();
   return true;
}

//--- the slot -> capability map: the strip shows the kind's own controls, in the
//--- order this module declares them, each only where the kind really carries it. A
//--- slot the kind does not carry is SKIPPED, so the strip is never wider than it
//--- needs to be and never shows a control that would do nothing. DELETE lives in
//--- FireDelete (the strip owns it since the menu went); SAVE/ALL are not quick
//--- cells (they ride the more-popover and the gear foot, one tap further). The cap
//--- is EIGHT (P-DRAW-64 -> 64a): worst case DK_RECT = 8 cells + 4 chrome, ~616px,
//--- inside DSTRIP_SKIN_MAXW 660. Past the cap a slot rides the more-popover as an
//--- MK_SLOT row (P-DRAW-08i: a slot past the paint ceiling stays reachable).
void DrawStripVisInit()
{
   if(s_dsVisInit) return;
   s_dsVisInit = true;
   for(int k = 0; k < DK_COUNT; k++)
      for(int s = 0; s < DRAW_SLOT_N; s++) s_dsVis[k][s] = true;
}
bool DrawStripVis(const EDrawKind k, const int slot)
{
   DrawStripVisInit();
   if(k <= DK_NONE || k >= DK_COUNT) return false;
   int seat = (slot == DSTRIP_SLOT_LEVELS) ? DRAW_SLOT_MORE : slot;
   if(seat < 0 || seat >= DRAW_SLOT_N) return true;
   return s_dsVis[k][seat];
}
//--- P-DRAW-64a (2026-09-27) — ONE COLOUR SEAT FOR TWO ROLES. User order: «این
//--- دوتا باکس که برای یک کار هستش میشه باهم ادغام کرد ... میشه یکی بشه». A kind
//--- that carries the interior's colour too shows ONE colour cell whose RING is the
//--- BORDER's colour and whose CENTRE is the interior's (see the paint), so the seat
//--- is `DRAW_SLOT_FILLCLR` and `DRAW_SLOT_COLOR` is folded into it.
//--- P-DRAW-64a: and a KIND-level cap can be finer than it looks. DK_CHANNEL covers
//--- three MT4 types and two of them — the regression and the standard-deviation
//--- channel — have no interior of their own (`DrawTypeHasFillChild`), so the
//--- interior's COLOUR would be a silent no-op there: the seat is not shown at all
//--- (C-04). Asked ONLY for that one kind, so every other kind pays one compare and
//--- no terminal call; the two reads are the channel's own seat, on a repaint.
//--- (The box's own 50 % is NOT in this test: it moves the drawing's own anchor, so
//--- it works on every channel type.)
bool DrawStripSeatAvail(const EDrawKind k, const int slot)
{
   if(!DrawSlotAvailable(k, slot)) return false;
   if(k != DK_CHANNEL) return true;
   if(slot != DRAW_SLOT_FILLCLR) return true;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return true;
   return DrawTypeHasFillChild(DrawObjectType(s_dsObj));
}
bool DrawStripMergedColor(const EDrawKind k)
{
   return (DrawStripSeatAvail(k, DRAW_SLOT_FILLCLR) && DrawSlotAvailable(k, DRAW_SLOT_COLOR));
}
//--- is a seat on the row? The merged colour seat is one seat for two roles, so it
//--- takes the WIDER of the two answers — a control the user asked to see is never
//--- silently dropped by a hide of the other role.
bool DrawStripSeatVis(const EDrawKind k, const int s, const bool merged)
{
   if(merged && s == DRAW_SLOT_FILLCLR)
      return (DrawStripVis(k, DRAW_SLOT_FILLCLR) || DrawStripVis(k, DRAW_SLOT_COLOR));
   return DrawStripVis(k, s);
}
//--- one ordered pass over everything the quick row COULD show (value slots +
//--- LEVELS); the quick cap and the overflow split read this, so the two can
//--- never disagree about order.
int DrawStripAllSlotAt(const EDrawKind k, const int shown)
{
   //--- The order is the module's own (index ascending), with ONE exception: the
   //--- FILL FAMILY reads together — FILL, then the two extras the user asked to
   //--- keep at hand (HALF · EXTEND) — so a box reads "filled · half · extends · …".
   bool merged = DrawStripMergedColor(k);
   int seen = 0;
   for(int s = 0; s < DRAW_SLOT_N; s++)
   {
      if(s == DRAW_SLOT_MORE) continue;   // no dialog to open from here
      if(merged && s == DRAW_SLOT_COLOR) continue;                 // folded into the colour seat
      if(s == DRAW_SLOT_BOXHALF || s == DRAW_SLOT_EXTEND) continue;  // served beside FILL
      if(!DrawStripSeatAvail(k, s)) continue;
      if(!DrawStripSeatVis(k, s, merged)) continue;
      if(seen == shown) return s;
      seen++;
      if(s == DRAW_SLOT_FILL)
      {
         if(DrawStripSeatAvail(k, DRAW_SLOT_BOXHALF) && DrawStripVis(k, DRAW_SLOT_BOXHALF))
         {
            if(seen == shown) return DRAW_SLOT_BOXHALF;
            seen++;
         }
         if(DrawSlotAvailable(k, DRAW_SLOT_EXTEND) && DrawStripVis(k, DRAW_SLOT_EXTEND))
         {
            if(seen == shown) return DRAW_SLOT_EXTEND;
            seen++;
         }
      }
   }
   if(DrawKindHasLevels(k) && DrawStripVis(k, DSTRIP_SLOT_LEVELS))
   {
      if(seen == shown) return DSTRIP_SLOT_LEVELS;
      seen++;
   }
   return -1;
}
int DrawStripAllSlotCount(const EDrawKind k)
{
   int n = 0;
   while(DrawStripAllSlotAt(k, n) != -1 && n < DSTRIP_MAX_SLOTS + 4) n++;
   return n;
}
int DrawStripQuickSlotAt(const EDrawKind k, const int shown)
{
   if(shown < 0 || shown >= DSTRIP_QUICK_CAP) return -1;
   return DrawStripAllSlotAt(k, shown);
}
int DrawStripQuickCount(const EDrawKind k)
{
   int n = DrawStripAllSlotCount(k);
   if(n > DSTRIP_QUICK_CAP) n = DSTRIP_QUICK_CAP;
   return n;
}
int DrawStripOverflowSlotAt(const EDrawKind k, const int shown)
{
   if(shown < 0) return -1;
   return DrawStripAllSlotAt(k, DSTRIP_QUICK_CAP + shown);
}
int DrawStripOverflowCount(const EDrawKind k)
{
   int n = DrawStripAllSlotCount(k) - DSTRIP_QUICK_CAP;
   return (n > 0 ? n : 0);
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-10 — THE ICON FACE.
// ══════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — EVERY QUICK CELL WEARS A RASTER (icon-only row). State carriers
// vary per value (width/style/ray — the P-DRAW-10 honesty rule); pure glyphs
// ride one raster and the gold face carries the state; the colour cell is a
// swatch (no raster, ""), its face IS the object's colour (P-DRAW-09c).
// ══════════════════════════════════════════════════════════════════════════
string DrawStripIconRes(const int slot, const string nm)
{
   //--- P-DRAW-64a: the colour seat wears no raster — its face IS the two colours it
   //--- edits (the border's ring and the interior's centre), which is the answer
   //--- DRAW_SLOT_COLOR always gave. The droplet that told the two cells apart went
   //--- with the merge; the seat is one cell now, so nothing needs telling apart.
   if(DrawStripIsColorSlot(slot)) return "";
   //--- P-DRAW-64a: the fill family's two extras. OFF is the plate ink, ON the
   //--- amber twin, so the ON cell stays quiet (one shape on the accent wash).
   if(slot == DRAW_SLOT_BOXHALF)
      return ((DrawSlotRead(nm, DRAW_SLOT_BOXHALF) > 0.5) ? "::Files\\Icons\\bk_half_on.bmp"
                                                          : "::Files\\Icons\\bk_half_off.bmp");
   if(slot == DRAW_SLOT_EXTEND)
      return ((DrawSlotRead(nm, DRAW_SLOT_EXTEND) > 0.5) ? "::Files\\Icons\\bk_ext_on.bmp"
                                                         : "::Files\\Icons\\bk_ext_off.bmp");
   if(slot == DRAW_SLOT_WIDTH)
   {
      int w = (int)DrawSlotRead(nm, DRAW_SLOT_WIDTH);
      if(w < DRAW_WIDTH_MIN || w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MIN;
      return "::Files\\Icons\\bk_w" + IntegerToString(w) + ".bmp";
   }
   if(slot == DRAW_SLOT_STYLE)
   {
      int st = (int)DrawSlotRead(nm, DRAW_SLOT_STYLE);
      if(st < 0 || st > 4) st = 0;
      return "::Files\\Icons\\bk_style" + IntegerToString(st) + ".bmp";
   }
   if(slot == DRAW_SLOT_RAY)
   {
      int r = (int)DrawSlotRead(nm, DRAW_SLOT_RAY);
      if(r < 0 || r > 3) r = 0;
      return "::Files\\Icons\\bk_ray" + IntegerToString(r) + ".bmp";
   }
   if(slot == DRAW_SLOT_FILL)
      return ((DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5) ? "::Files\\Icons\\bk_fill_on.bmp"
                                                       : "::Files\\Icons\\bk_bucket.bmp");
   //--- P-DRAW-47: the ON faces are the AMBER twins (`bk_*_on` / `bk_lock_on_g`).
   //--- Their dark-ink predecessors were drawn for a solid gold plate, while the
   //--- ON face here is a translucent WASH — measured, the dark art's own mean
   //--- luminance is ~12 against a wash whose premultiplied mean is (33,22,0), so
   //--- ON read as NO glyph at all. The preview's rule is accent ink on the wash.
   if(slot == DRAW_SLOT_LOCK)
      return ((DrawSlotRead(nm, DRAW_SLOT_LOCK) > 0.5) ? "::Files\\Icons\\bk_lock_on_g.bmp"
                                                       : "::Files\\Icons\\bk_lock_off.bmp");
   if(slot == DRAW_SLOT_BACK)
      return ((DrawSlotRead(nm, DRAW_SLOT_BACK) > 0.5) ? "::Files\\Icons\\bk_back_on.bmp"
                                                       : "::Files\\Icons\\gl_layers_m.bmp");
   if(slot == DRAW_SLOT_FONT) return "::Files\\Icons\\gl_textsize_m.bmp";
   if(slot == DRAW_SLOT_GLYPH) return "::Files\\Icons\\bk_glyph.bmp";
   if(slot == DSTRIP_SLOT_LEVELS) return "::Files\\Icons\\bk_levels.bmp";
   return "";
}
//--- chrome faces: grip, badge has none (text label), actions by seat.
string DrawStripActRes(const int a)
{
   if(a == DSTRIP_ACT_MORE) return "::Files\\Icons\\bk_more.bmp";
   if(a == DSTRIP_ACT_GEAR) return "::Files\\Icons\\bk_gear.bmp";
   if(a == DSTRIP_ACT_PIN)
      return (s_dsPinned ? "::Files\\Icons\\gl_pin_gold.bmp" : "::Files\\Icons\\gl_pin_m.bmp");
   if(a == DSTRIP_ACT_DEL) return "::Files\\Icons\\bk_del.bmp";
   return "";
}

//--- MT4 paints a bitmap label at the file's NATIVE size from the label's own
//--- top-left corner, so centring the art is arithmetic — and the arithmetic
//--- needs the art's size. The families in this strip are fixed:
//---   `bk_w*` / `bk_style*` / `bk_ray*` = 16, every other `bk_*` = 24, `gl_*` = 15.
//--- (Measured off the shipped files; a new family must be added here, which is
//--- what keeps a 24 px raster from hanging off a 30 px cell.)
int DrawStripIconPx(const string res)
{
   if(StringFind(res, "bk_w") >= 0 || StringFind(res, "bk_style") >= 0 ||
      StringFind(res, "bk_ray") >= 0) return 16;
   if(StringFind(res, "gl_") >= 0) return 15;
   if(StringFind(res, "bk_") >= 0) return 24;
   return 0;
}
int DrawStripResW(const string res)
{
   // P-UI-34: W-variants are 624px (wide panel header); narrow variants are 312px.
   if(StringFind(res, "pnl_topbarW") >= 0 || StringFind(res, "pnl_hairW") >= 0) return 624;
   if(StringFind(res, "pnl_topbar") >= 0 || StringFind(res, "pnl_hair") >= 0) return 312;
   if(StringFind(res, "pnl_mark") >= 0) return 44;
   if(StringFind(res, "dsg_btn") >= 0) return 80;
   if(StringFind(res, "pnl_sw_") >= 0) return 52;
    // P-UI-34 (2026-09-25): sheen sizes must be known for correct centring —
    // without an entry here DrawStripFaceZ gets pw=0 and places the art at the
    // cell's own centre instead of its corner. ICON-DIET 2026-09-27: the two
    // pnl_glass entries left with their bitmaps (see the #resource block).
    if(StringFind(res, "ds_cell32") >= 0) return 32;
    if(StringFind(res, "ds_ring32") >= 0) return 32;
    if(StringFind(res, "ds_swatch24") >= 0) return 24;
    if(StringFind(res, "pnl_chip") >= 0) return 26;
    if(StringFind(res, "pnl_rail") >= 0) return 4;
    if(StringFind(res, "pnl_vchip") >= 0) return 50;
    if(StringFind(res, "pnl_xbtn") >= 0) return 30;
    if(StringFind(res, "pnl_secdot") >= 0) return 14;   // P-DRAW-71: the cards' own section dot
    if(StringFind(res, "pnl_cntchip") >= 0) return 28;  // ... and its count pill (24+2*2)
    if(StringFind(res, "pnl_subdot") >= 0) return 8;
    return DrawStripIconPx(res);
}
int DrawStripResH(const string res)
{
   if(StringFind(res, "pnl_topbarW") >= 0) return 7;
   if(StringFind(res, "pnl_hairW") >= 0) return 5;
   if(StringFind(res, "pnl_topbar") >= 0) return 7;
   if(StringFind(res, "pnl_hair") >= 0) return 5;
   if(StringFind(res, "pnl_mark") >= 0) return 44;
   if(StringFind(res, "dsg_btn") >= 0) return 44;
   if(StringFind(res, "pnl_sw_") >= 0) return 34;
    // P-UI-34 (2026-09-25): glass sheen heights. ICON-DIET 2026-09-27: the
    // pnl_glass pair left with its bitmaps (see the #resource block).
    if(StringFind(res, "ds_cell32") >= 0) return 32;
    if(StringFind(res, "ds_ring32") >= 0) return 32;
    if(StringFind(res, "ds_swatch24") >= 0) return 24;
    if(StringFind(res, "pnl_chip") >= 0) return 26;
    if(StringFind(res, "pnl_rail") >= 0) return 42;
   if(StringFind(res, "pnl_vchip") >= 0) return 26;
   if(StringFind(res, "pnl_xbtn") >= 0) return 30;
   if(StringFind(res, "pnl_secdot") >= 0) return 14;
   if(StringFind(res, "pnl_cntchip") >= 0) return 20;
   if(StringFind(res, "pnl_subdot") >= 0) return 8;
   return DrawStripIconPx(res);
}

//--- P-DRAW-09c — THE CELL'S TWO READING AIDS.
//
// 1. THE COLOUR CELL SHOWS A NAME A TRADER CAN READ. `ColorToString` says
//    `clrWhite` (a programming name) or `C'255,128,0'` (a compiler literal).
//    Neither is a caption: the first loses its spaces — `clrDodgerBlue` — and the
//    second is unreadable at a glance. So the MT4 names are un-CamelCased into
//    words («Dodger Blue») and anything else becomes the hex the rest of the
//    industry shows («#FF8000»), which is both modern and exact.
//
// 2. AND ITS INK CONTRASTS WITH THE SWATCH. The cell's face IS the object's
//    colour (that is what makes it a swatch), so the label sits on a colour the
//    user chose — and this project already paid for this lesson once (P-UI-69,
//    «رنگ ها کار نمیکنه»: an invisible control reads as a broken one). The maths
//    is WCAG's relative luminance, the same one `PnlLum` uses; it is local
//    because its owner (`BiotakPanels.mqh`) is included after this module.
// ══════════════════════════════════════════════════════════════════════════
double DrawStripLum(const color c)
{
   // `color` is UNSIGNED in MQL4, so `c < 0` is always false (warning 65): a
   // stray clrNONE only shows up once the value is seen as a signed int.
   int v = (int)c;
   if(v < 0) return 1.0;
   double r = (double)(v % 256) / 255.0;
   double g = (double)((v / 256) % 256) / 255.0;
   double b = (double)(v / 65536) / 255.0;
   if(r > 0.03928) r = MathPow((r + 0.055) / 1.055, 2.4); else r = r / 12.92;
   if(g > 0.03928) g = MathPow((g + 0.055) / 1.055, 2.4); else g = g / 12.92;
   if(b > 0.03928) b = MathPow((b + 0.055) / 1.055, 2.4); else b = b / 12.92;
   return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

color DrawStripInkOn(const color bg)
{
   // the threshold sits where the eye does: above it the face is light, so the
   // ink is the dark plate's own ink; below it, the light one. No colour is
   // rejected — the swatch keeps the user's exact colour either way.
   return (DrawStripLum(bg) > 0.45) ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL;
}

string DrawStripColorLabel(const color c)
{
   string s = ColorToString(c, false);
   if(StringFind(s, "clr") == 0)
   {
      s = StringSubstr(s, 3);
      string out = "";
      for(int i = 0; i < StringLen(s); i++)
      {
         // a capital that is not the first character starts a new word (a plain
         // character-code test: `StringToUpper(ch)` on a one-char string costs a
         // temporary and warns on some builds' implicit conversions)
         int code = StringGetCharacter(s, i);
         if(i > 0 && code >= 'A' && code <= 'Z') out += " ";
         out += StringSubstr(s, i, 1);
      }
      if(StringLen(out) > 10) out = StringSubstr(out, 0, 10);
      return out;
   }
   // `C'r,g,b'` -> `#RRGGBB`
   int nOpen = StringFind(s, "'");
   int nClose = StringFind(s, "'", nOpen + 1);
   if(nOpen >= 0 && nClose > nOpen)
   {
      string t = StringSubstr(s, nOpen + 1, nClose - nOpen - 1);
      int p1 = StringFind(t, ",");
      int p2 = StringFind(t, ",", p1 + 1);
      if(p1 > 0 && p2 > p1)
      {
         int r = (int)StringToInteger(StringSubstr(t, 0, p1));
         int g = (int)StringToInteger(StringSubstr(t, p1 + 1, p2 - p1 - 1));
         int b = (int)StringToInteger(StringSubstr(t, p2 + 1, StringLen(t) - p2 - 1));
         return StringFormat("#%02X%02X%02X", r, g, b);
      }
   }
   return "Color";   // P-UI-69d: ONE spelling in user-visible text (`Color`), like the one verb
}
#endif // DRAW_STRIP_BASE_MQH
