//+------------------------------------------------------------------+
//|                                                 DrawStrip.mqh     |
//|   P-DRAW-08 (2026-09-22) — THE FLOATING STRIP OF THE USER'S DRAWINGS.|
//|   P-DRAW-09 (2026-09-23) — THE MODERN FACE, THE GROUP, THREE CONTROLS.|
//|   P-DRAW-10 (2026-09-23) — THE TRADINGVIEW FACE: LIGHT ICON CELLS.    |
//|   P-DRAW-11 (2026-09-23) — DIRECT PICK, NO CYCLING (BASEKNOT PARITY+).|
//|   P-DRAW-12 (2026-09-23) — RIGHT-CLICK OPENS THE STRIP.               |
//|   P-DRAW-14 (2026-09-23) — RIGHT-CLICK REPLACES HOLD + MENU.          |
//|   P-DRAW-16 (2026-09-23) — MENU OFF FOR THE WHOLE ATTACH (no race).  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property strict

#ifndef DRAW_STRIP_MQH
#define DRAW_STRIP_MQH

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-10 (2026-09-23) — THE ICON FACE, AND WHY IT IS THIS RECIPE.
//
// User order: «مثل استریپ تریدینگ ویو بشه … هر ابزار یک تولبار داره و ایکون های
// سبک باشه». TradingView's object toolbar is the reference: a small floating bar
// whose cells are LIGHT ICONS — a width sample, a style sample, a colour swatch,
// a padlock, an eye, a bin — with the value in the tooltip, not spelled out in a
// word per cell.
//
// WHY THIS IS NOT P-DRAW-08i's FAILED BITMAP PASS. That pass concluded "a bitmap
// label ships empty" and fell back to words. The conclusion was WRONG, and the
// proof was already in this repository: the leg metre's handle discs are
// OBJ_BITMAP_LABELs loaded through `#resource` (P-LM-14/17) and they render on
// the user's own charts. What the 08i pass actually tripped on is the two things
// this module now does properly:
//   * the raster must be EMBEDDED. `ObjectSetString(..., OBJPROP_BMPFILE,
//     "::Files\\Icons\\x.bmp")` only resolves for a file that this module
//     `#resource`d — an un-embedded path draws NOTHING (and the R-ICON gate in
//     panel-wiring-audit calls that a ghost). Every raster below is `#resource`d
//     here and listed in `tools/icon-manifest.txt`;
//   * the CELL must be the control. MT4 paints a bitmap label at the file's
//     NATIVE size from the label's own corner, so the art is centred by
//     arithmetic, not by a box — and the CLICK target stays the OBJ_BUTTON
//     underneath it (the panels' own "a button stays under its skin" shape,
//     Z_PANEL_BASE/Z_PANEL_SKIN): the icon is a face, the button is the control,
//     and the router accepts a click on either name.
//
// THE CELL IS AN ICON ONLY WHERE AN ICON IS HONEST. A width cell's icon IS its
// value (the width sample), a style cell's too, and the binary states (fill,
// lock, behind) carry their state on the face AND in the raster pair. The cells
// whose value is a WORD — the ray mode, the caption size, the arrow's code, the
// template's name, "All" — keep the word: an icon that lies is worse than a
// word that says it (P-DRAW-08d's rule, still binding).
// ══════════════════════════════════════════════════════════════════════════

//--- P-DRAW-10: the embedded rasters. One line per icon family the strip can
//--- wear; R-ICON (panel-wiring-audit) fails the build if any of these is
//--- missing from `tools/icon-manifest.txt`, because a #resource outside the
//--- manifest embeds a ghost file nobody regenerates.
#resource "\\Files\\Icons\\bk_w1.bmp"
#resource "\\Files\\Icons\\bk_w2.bmp"
#resource "\\Files\\Icons\\bk_w3.bmp"
#resource "\\Files\\Icons\\bk_w4.bmp"
#resource "\\Files\\Icons\\bk_w5.bmp"
#resource "\\Files\\Icons\\bk_style0.bmp"
#resource "\\Files\\Icons\\bk_style1.bmp"
#resource "\\Files\\Icons\\bk_style2.bmp"
#resource "\\Files\\Icons\\bk_style3.bmp"
#resource "\\Files\\Icons\\bk_style4.bmp"
#resource "\\Files\\Icons\\bk_bucket.bmp"
#resource "\\Files\\Icons\\bk_lock_on.bmp"
#resource "\\Files\\Icons\\bk_lock_off.bmp"
#resource "\\Files\\Icons\\bk_del.bmp"
#resource "\\Files\\Icons\\gl_layers_m.bmp"
#resource "\\Files\\Icons\\gl_template_m.bmp"
//--- P-DRAW-13 (2026-09-23) — the V6 icon-only faces. State carriers vary per
//--- value (bk_ray0..3, like bk_w*/bk_style*); pure glyphs ride one raster and
//--- the gold face carries the state. gl_* reuses (pin/pin-gold, plus, check,
//--- textsize, layers) are owned by their own modules' #resource lines —
//--- R-ICON allows sharing: every raster below is #resource'd HERE, which is
//--- what the gate checks.
#resource "\\Files\\Icons\\bk_ray0.bmp"
#resource "\\Files\\Icons\\bk_ray1.bmp"
#resource "\\Files\\Icons\\bk_ray2.bmp"
#resource "\\Files\\Icons\\bk_ray3.bmp"
#resource "\\Files\\Icons\\bk_glyph.bmp"
#resource "\\Files\\Icons\\bk_levels.bmp"
#resource "\\Files\\Icons\\bk_gear.bmp"
#resource "\\Files\\Icons\\bk_grip.bmp"
#resource "\\Files\\Icons\\bk_copy.bmp"
#resource "\\Files\\Icons\\bk_undo.bmp"
#resource "\\Files\\Icons\\bk_fill_on.bmp"
#resource "\\Files\\Icons\\bk_back_on.bmp"
#resource "\\Files\\Icons\\bk_lock_on_d.bmp"
#resource "\\Files\\Icons\\gl_pin_m.bmp"
#resource "\\Files\\Icons\\gl_pin_gold.bmp"
#resource "\\Files\\Icons\\gl_plus_m.bmp"
#resource "\\Files\\Icons\\gl_check_m.bmp"
#resource "\\Files\\Icons\\gl_textsize_m.bmp"

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-08 — ONE STRIP, EVERY DRAWING TOOL, ITS OWN CONTROLS.
//
// User order: «روش نگه میدارم منوی تولباری باز نمیشه … مثل این برای هر ابزار به
// صورت اختصاصی با تنظیماتش باز بشه». The screenshot's strip is the BOX's own
// (item 13); this is the same idea for every drawing the user makes.
//
// WHY IT IS NOT ITEM 13's STRIP RETARGETED. That strip is a bitmap toolbar whose
// slots are box properties and it is wired into ~30 places of the panel
// framework. This one is deliberately the OPPOSITE shape: it renders itself from
// the DRAWING's own kind, so it shows exactly the controls that kind has and
// nothing else, and it owns its objects (create/refresh/destroy) with no
// framework state at all. That is why it can serve seventeen drawing types with
// one owner and no per-type code.
//
// THE MODEL — P-DRAW-11 RETIRED THE CYCLER (value cells open pickers now; only
// toggles/actions fire at once). Kept as history: every slot WAS a cycler —
// a tap advances the value, the cell always shows the CURRENT value (as its icon
// where the value IS visual, as a word where it is not), and the tooltip names
// the slot AND the value. No dropdown, no palette window, no second click to
// close — five taps style a fibo. Every write goes through `DrawSlotWrite`,
// which also learns the look for the next drawing of the kind (P-DRAW-01c), and
// the TEMPLATE slot cycles the presets (P-DRAW-02/07, names and all).
//
// ── P-DRAW-09 (2026-09-23) — WHY THE FACE CHANGED, AND WHAT ELSE IT CARRIES ──
//
// User order: «استریپ ابزارهای ترسیمات خیلی مشکلات داره باید از استریپ بیس نات
// هم مدرن تر باشه و همه نیازهای کاربر رو پوشش بده … و اینکه پرفورمنس فدا نشو …
// از دید کاربر همیشه نگاه کن که سهولت استفاده داشته باشه و سریع و راحت ولی پر
// امکانات». Four answers, each one measured against the box strip (item 13), the
// surface the user is comparing this to:
//
//   a. THE CONTROLS MT4 BURIES (P-DRAW-09a, in DrawToolbar): FONT for a text's
//      caption size, GLYPH for an arrow's mark, BEHIND for a zone. Three
//      properties MT4 HAS and reaches only through a per-object dialog — the
//      same class of gap the user names as «هر چیزی که متاتریدر پشتیبانی نمیکنه».
//
//   b. THE GROUP (P-DRAW-09b, in DrawToolbar): the terminal's own multi-select
//      IS the group, and every tap edits the whole group. MT4's dialog is one
//      object at a time and its style copy is all-or-nothing.
//
//   c. THE FACE (P-DRAW-09c + P-DRAW-10 here). A header line that NAMES the
//      drawing the toolbar serves (and how many more it is editing), rows that
//      wrap to a MINI toolbar instead of a ribbon, state-coloured faces (gold =
//      this is ON: Filled, Locked, Behind), the colour cell carrying a real
//      swatch with contrast-correct ink, and light ICON cells in the
//      TradingView language with the value in the tooltip.
//
//   d. THE FRAME BUDGET (P-DRAW-09d, here). Every write is guarded (P-PERF-02's
//      law: never touch a chart object with a value it already has) and the
//      forced `ChartRedraw()` fires only when a pixel really moved, so a pan or a
//      zoom no longer costs a full chart repaint per event. The re-anchor is
//      throttled to the project's own drag cadence on BOTH channels (the drag
//      and CHART_CHANGE), which is what "پرفورمنس فدا نشو" means in this file.
//
// COST. Created once per hold, destroyed on dismiss — never per frame. A refresh
// reads the cells of the ONE held object (3-4 terminal calls each) and repaints
// only when a value really changed. Nothing here runs in the mouse stream.
// ══════════════════════════════════════════════════════════════════════════

// P-DRAW-08i: the paint loop walks DSTRIP_MAX_SLOTS, so a slot past the ceiling
// would be silently never drawn. P-DRAW-13: quick cells are capped at six
// (DSTRIP_QUICK_CAP); the twelve is headroom for the cap plus chrome.
// P-DRAW-09: a kind has at most ten cells (six of its own + Tpl/Save/✕/All).
#define DSTRIP_MAX_SLOTS 12
//--- P-DRAW-11 (2026-09-23) — DIRECT PICK, NO CYCLING, AND WHY IT IS SHAPED LIKE THIS.
//
// User order: «حالت چرخشی نباشه مثل حالت بیس نات و بهتر ازش باشه». The cycler
// (P-DRAW-08: "every slot is a CYCLER, a tap advances the value") is retired:
// a tap on a VALUE cell no longer mutates anything — it OPENS that value's
// picker, and the pick applies directly. Toggles (fill/lock/behind) and the
// three actions (Save/All/Del) fire at once; they never had a list to show.
//
// WHY IT IS THE BASEKNOT SHAPE. The box strip (item 13, BiotakPanels.mqh:7011)
// never cycles: STYLE/WIDTH toggle their ▾ dropdowns (TV popovers, NOT cycles),
// pencil/bucket open the palette, and the popover owns the next press. This
// strip is the same contract for all seventeen drawing kinds: one tap, one
// list, the current value pill-highlighted, a row tap applies it live.
//
// WHY IT IS BETTER THAN ITEM 13, NOT A COPY OF IT:
//   * the picker is INLINE — the strip's own second block, not a third window
//     (no BkDdOpen/BkDdClose popover, no PalOpen palette, no card-12 jump for
//     font/glyph/ray/template: every one of those has its own picker here);
//   * the colour picker is 16 + the trader's own 5 recent (BaseKnot's is the
//     shared palette window; the old 8-cycle is gone with the cycler);
//   * the template list lives IN the strip (item 13 has no template row at all);
//   * the group rides every pick (P-DRAW-09b), and the tip scope says so;
//   * the picker survives a re-anchor (zoom/drag re-opens the strip around the
//     open picker; item 13 closes its dropdown on the ride instead).
//
// THE AFFORDANCE WITHOUT A CHEVRON BITMAP. MT4 renders a text "▼" as "?" in
// Wine fonts (BiotakPanels.mqh:4292), so a glued chevron would cost a baked
// raster per cell. The rim carries it instead: a value cell (it HAS a picker)
// wears DSTRIP_CLR_PICK, and the ACCENT rim while its own picker is open; an
// ON toggle wears the ACCENT face (P-DRAW-09c, unchanged). Rim = has a list,
// face = is on. The tooltip teaches it on the first hover ("tap to choose").
//
// COST. The picker is created on open demand and destroyed with the strip —
// never per frame. A pick is one Store.Write fan-out plus one guarded repaint,
// the same budget a cycler tap had. Nothing here runs in the mouse stream.
// P-DRAW-13 (2026-09-23) — V6: ICON-ONLY, ONE ROW, GEAR PANEL. The preview
// (`drawstrip-v2-preview.html`, "V6 - Icon-only") is the spec: one 30px row —
// grip | badge | <=6 value icons | more | gear | pin | trash — one docked
// popover at a time, and a gear panel (Style / Levels-or-Mark / Template /
// Strip + foot) for everything else. What the preview draws in SVG/CSS the
// strip draws in baked BMP + native buttons; what MT4 cannot do is cut with a
// named ceiling (ponytail), never silently dropped:
//   * no text-edit inside the strip's own row (caption/hex/level-add live in
//     the gear panel's OBJ_EDITs, the one place MT4 allows typing);
//   * no per-level on/off visibility: MT4 draws every level a fibo HAS, so the
//     levels editor edits MEMBERSHIP (add/remove), not visibility;
//   * no font-name cycle (marginal for captions; size stays);
//   * trash is not undoable (MT4 has no undelete; undo covers looks only).
#define DSTRIP_PICK_NONE (-99)  // no popover open
#define DSTRIP_MORE      (-60)  // the more-popover (sections, not a slot)
#define DSTRIP_SLOT_MORE   (-6) // quick: the "..." popover
#define DSTRIP_SLOT_GEAR   (-7) // quick: the full-settings panel
#define DSTRIP_SLOT_PIN    (-8) // quick: pin toggle (stays while editing)
#define DSTRIP_SLOT_LEVELS (-9) // quick: the fibo level-membership editor
//--- P-DRAW-13: the V6 shell metrics. ONE 30px row, icon-only, 2px gaps — the
//--- preview's minimal-space rule. Nothing wraps any more: overflow value slots
//--- live in the more-popover, never on a second row.
#define DSTRIP_CELL      30    // the one row's height, and every icon cell's width
#define DSTRIP_GAP        2
#define DSTRIP_PAD        6    // plate padding
#define DSTRIP_PICK_MAX  24    // popover rows (more sections + overflow slots)
#define DSTRIP_GRID_MAX  48    // option cells in one grid block (colour 16+5)
#define DSTRIP_GLIST_MAX 16    // list rows in one gear block
#define DSTRIP_GEAR_W   300    // the gear panel's fixed content width
#define DSTRIP_GRID_CHIP 56    // word-option chip width inside grids
#define DSTRIP_RECENT_MAX 5    // the trader's own recent colours
#define DSTRIP_UNDO_MAX  32    // single-step undo: members covered
#define DSTRIP_UNDO_LV   32    // ... and fibo levels on the held drawing
#define DSTRIP_FOLLOW_MS 50    // the project's own live-drag frame cadence
#define DSTRIP_GRIP_MS   30    // the grip carry's own cadence (BkStripFollow parity)
//--- gear tabs (0 = shut)
#define DSTRIP_GEAR_STYLE 1
#define DSTRIP_GEAR_LEVELS 2   // fibo family; TEXT/ARROW see MARK instead
#define DSTRIP_GEAR_MARK 2     // same seat as LEVELS (one tab at a time by kind)
#define DSTRIP_GEAR_TPL 3
#define DSTRIP_GEAR_STRIP 4
//--- more-popover row kinds
#define DSTRIP_MK_APPLYALL 1
#define DSTRIP_MK_PRESET 2     // arg = preset index
#define DSTRIP_MK_SAVE 3
#define DSTRIP_MK_DUPE 4
#define DSTRIP_MK_UNDO 5
#define DSTRIP_MK_SLOT 6       // arg = overflow value slot (opens its grid)

//--- P-DRAW-09c: the strip's palette. These are the settings cards' OWN tokens
//--- (PNL_CLR_CARD #1D222C, FIELD #181D27, LINE #222832, LABEL #CBD4E2, MUTED
//--- #8C96A6, ACCENT #FFC247, aInk #1A1206), mirrored here because their owner —
//--- BiotakPanels.mqh — is included AFTER this module (P-BUILD-01's include
//--- order; MQL4 is define-before-use). Same numbers, one look. The two extra
//--- inks are the strip's own: a destructive action needs its own colour.
#define DSTRIP_CLR_CARD    C'29,34,44'
#define DSTRIP_CLR_FIELD   C'24,29,39'
#define DSTRIP_CLR_LINE    C'34,40,50'
#define DSTRIP_CLR_LABEL   C'203,212,226'
#define DSTRIP_CLR_TITLE   C'140,150,166'
#define DSTRIP_CLR_ACCENT  C'255,194,71'
#define DSTRIP_CLR_ACCENTT C'26,18,6'
#define DSTRIP_CLR_DEL_BG  C'58,26,30'
#define DSTRIP_CLR_DEL_INK C'255,138,138'
//--- P-DRAW-11: the "this cell has a list" rim (see the header block: rim = has
//--- a picker, face = is on — a text chevron renders as "?" in Wine fonts).
#define DSTRIP_CLR_PICK    C'110,124,150'

static string   s_dsObj  = "";       // the drawing this strip serves (the held one)
static EDrawKind s_dsKind = DK_NONE; // its kind, resolved once per open
static int      s_dsX    = 0;
static int      s_dsY    = 0;
static int      s_dsW    = 0;        // the width of THIS kind's strip (set on open)
static int      s_dsH    = 0;        // plate height: quick row + open blocks
static int      s_dsN    = 0;        // quick value/toggle cells on screen now
static bool     s_dsOpen = false;
static bool     s_dsPinned = false;  // P-DRAW-13: pin — outside click won't dismiss
static bool     s_dsManual = false;  // cursor/drag placed: re-anchor keeps x/y
static int      s_dsAX = 0, s_dsAY = 0; // last anchor px (the follow offset rides it)
//--- P-DRAW-13: the shell layout, computed by ONE pass (DrawStripLayout) and read
//--- by the painter, the hit test and the grip carry, so a cell's face and its
//--- gap can never be computed twice and disagree.
static int      s_dsCX[DSTRIP_MAX_SLOTS];
static int      s_dsCW[DSTRIP_MAX_SLOTS];   // badge is measured; icons are CELL
static int      s_dsBadgeW = 0;
static uint     s_dsAnchorMs = 0;    // P-DRAW-08e: the drag-follow throttle
//--- P-DRAW-08k/08j (open-guard) RETIRED with the hold (DRHOLD-OFF, 2026-09-23):
//--- the guard existed because the hold fired while the button was still DOWN
//--- and its release CLICK needed swallowing. Right-click opens ON the release
//--- event itself, so there is nothing left to swallow — kept as history.
//--- P-DRAW-11: the open popover (ONE at a time, BaseKnot parity): a slot id,
//--- or DSTRIP_MORE for the more-popover. The gear panel is a separate seat
//--- (s_dsGear) and shuts the popover when it opens.
static int      s_dsPicker = DSTRIP_PICK_NONE;
static int      s_dsTpl[DK_COUNT];               // last applied preset per kind
static int      s_dsPN = 0;                      // popover rows on screen now
static int      s_dsPY[DSTRIP_PICK_MAX];         // row tops (rows are full-width)
static int      s_dsMoreKind[DSTRIP_PICK_MAX];   // DSTRIP_MK_* per more-row
static int      s_dsMoreArg[DSTRIP_PICK_MAX];    // preset index / slot id
static color    s_dsRecent[DSTRIP_RECENT_MAX];   // the trader's recent colours
static int      s_dsRecentN = 0;
//--- P-DRAW-13: the gear panel (0 = shut, else DSTRIP_GEAR_*). Tabs after the
//--- content: gear rows live in GR/GRI/GRT, grid cells in GG/GGI, tabs in GT,
//--- foot in GF, edits in GE — one namespace per role so painters never share.
static int      s_dsGear = 0;
static int      s_dsGRN = 0;                     // gear list rows on screen
static int      s_dsGRY[DSTRIP_GLIST_MAX];
static int      s_dsGRKind[DSTRIP_GLIST_MAX];    // 1 toggle-slot · 2 preset · 3 save ·
                                                 // 4 level-row · 5 levels All/None · 6 vis ·
                                                 // 7 default-learn · 8 option-row
static int      s_dsGRArg[DSTRIP_GLIST_MAX];     // slot / preset idx / packed
static int      s_dsGGN = 0;                     // gear grid cells on screen
static int      s_dsGGX[DSTRIP_GRID_MAX];
static int      s_dsGGY[DSTRIP_GRID_MAX];
static int      s_dsGGW[DSTRIP_GRID_MAX];
static int      s_dsGGKind[DSTRIP_GRID_MAX];     // 0 swatch (colour in GGC) · 1 chip
static int      s_dsGGSlot[DSTRIP_GRID_MAX];
static int      s_dsGGArg[DSTRIP_GRID_MAX];
static color    s_dsGGC[DSTRIP_GRID_MAX];
static int      s_dsGearTab[5];                  // tab ids shown (count in [0])
static int      s_dsGearTabX[4], s_dsGearTabW[4];
static int      s_dsGearTabsY = 0;
static int      s_dsGearEditY[3];                // edit rows (hex/level-add/caption)
static int      s_dsGearFootY = 0;
static bool     s_dsVis[DK_COUNT][DRAW_SLOT_N];  // Strip tab: per-slot visibility
static bool     s_dsVisInit = false;
//--- P-DRAW-13: the grip carry (screen-object drag, no view lock: the plate is
//--- screen-fixed, so a chart scroll moves nothing we own — P-LM-11's race with
//--- the terminal's own drag cannot happen, our objects are SELECTABLE=false).
static bool     s_dsGripLive = false;
static int      s_dsGripDX = 0, s_dsGripDY = 0;
static uint     s_dsGripMs = 0;
static bool     s_dsLeftPrev = false;
//--- P-DRAW-16 (2026-09-23) — THE MENU IS OFF FOR THE WHOLE ATTACH. Three
//--- generations of press-timed suppression (open-time, right-DOWN edge, hover
//--- voter) all lost the same race: MT4 shows its object menu on the press, and
//--- a still press emits no MOVE to pre-empt it with — the user's screenshot is
//--- the proof. So the menu is not timed any more: Take() captures the user's
//--- value once per Full attach and forces it off; Give() hands it back on
//--- deinit (every reason — the entry calls it beside DrawStripClose). Menu-only
//--- on purpose: scroll stays alive, so this is NOT the view lock (P-UI-90) —
//--- no counter (the reconcile only hunts counters, never props), no watchdog
//--- term. Price, stated plainly: while attached, right-click NEVER shows the
//--- terminal menu anywhere on the chart (empty chart included — the strip, the
//--- gear and the hotkeys already cover Delete/Properties/Objects-List's jobs;
//--- Ctrl+B and the top menu bar are untouched). Remove the Take/Give pair to
//--- get the menu back; nothing else in this file touches the prop.
static bool     s_dsCtxUser = true;
void DrawStripMenuTake()
{
   s_dsCtxUser = ((bool)ChartGetInteger(0, CHART_CONTEXT_MENU));
   if(s_dsCtxUser) ChartSetInteger(0, CHART_CONTEXT_MENU, false);
}
void DrawStripMenuGive()
{
   if(!(bool)ChartGetInteger(0, CHART_CONTEXT_MENU) && s_dsCtxUser)
      ChartSetInteger(0, CHART_CONTEXT_MENU, true);
}
//--- P-DRAW-13: single-step undo — the pre-mutation looks of the group (names +
//--- packed slots), the held drawing's level set, and a duplicate's copy name.
//--- Trash is not undoable (MT4 has no undelete); undo covers looks only.
static bool     s_duValid = false;
static int      s_duN = 0;
static string   s_duName[DSTRIP_UNDO_MAX];
static color    s_duClr[DSTRIP_UNDO_MAX];
static int      s_duW[DSTRIP_UNDO_MAX], s_duSt[DSTRIP_UNDO_MAX];
static int      s_duFill[DSTRIP_UNDO_MAX], s_duRay[DSTRIP_UNDO_MAX];
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
//--- the gear panel: tabs (GT), grid cells (GG/GGI), list rows (GR/GRI/GRT),
//--- foot (GF), edits (GE).
string DrawStripGearTabName(const int t) { return "PnlDrawS_GT" + IntegerToString(t); }
string DrawStripGridName(const int g) { return "PnlDrawS_GG" + IntegerToString(g); }
string DrawStripGridIconName(const int g) { return "PnlDrawS_GG" + IntegerToString(g) + "I"; }
string DrawStripRowName(const int r) { return "PnlDrawS_GR" + IntegerToString(r); }
string DrawStripRowIconName(const int r) { return "PnlDrawS_GR" + IntegerToString(r) + "I"; }
string DrawStripRowLabelName(const int r) { return "PnlDrawS_GR" + IntegerToString(r) + "T"; }
string DrawStripFootName(const int f) { return "PnlDrawS_GF" + IntegerToString(f); }
string DrawStripEditName(const int e) { return "PnlDrawS_GE" + IntegerToString(e); }
string DrawStripBgName() { return "PnlDrawS_BG"; }
bool   DrawStripIsOpen() { return s_dsOpen; }
string DrawStripTarget() { return s_dsObj; }
//--- P-DRAW-09b: how many drawings this strip is editing (1 = the held one).
int    DrawStripGroupCount() { return DrawSelCount(); }

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
   if(!s_dsOpen || s_dsW <= 0 || s_dsH <= 0) return false;
   return (mx >= s_dsX - 2 && mx <= s_dsX + s_dsW + 2 &&
           my >= s_dsY - 2 && my <= s_dsY + s_dsH + 2);
}

//--- the slot -> capability map: the strip shows the kind's own controls, in
//--- the order this module declares them (COLOR · WIDTH · STYLE · FILL · RAY ·
//--- LOCK · FONT/GLYPH · BEHIND), each one only where the kind really carries it.
//--- A slot the kind does not carry is SKIPPED, so the strip is never wider than
//--- it needs to be and never shows a control that would do nothing.
//--- P-DRAW-08d: the strip's own DELETE lives in FireDelete (chrome trash +
//--- gear/undo rows) — with the menu suppressed, the strip OWNS delete.
//--- (P-DRAW-13: SAVE/ALL retired as quick cells — they ride the more-popover
//--- and the gear foot now, one tap further, zero cells wider.)
//--- P-DRAW-13: the QUICK slots — the kind's own controls, in the order
//--- DrawToolbar declares them, filtered by the Strip tab's visibility and
//--- capped at six (the preview's minimal-space rule). Anything past the cap
//--- (only CHANNEL/FIBOCHAN's levels) is NOT dropped: it rides the more-popover
//--- as an MK_SLOT row (P-DRAW-08i's lesson: a slot past the paint ceiling must
//--- stay reachable). LEVELS is the fibo level-membership editor, last.
//--- MORE/GEAR/PIN/DELETE are chrome, not slots — painted separately.
#define DSTRIP_QUICK_CAP 6
#define DSTRIP_ACT_MORE 0
#define DSTRIP_ACT_GEAR 1
#define DSTRIP_ACT_PIN 2
#define DSTRIP_ACT_DEL 3
#define DSTRIP_ACT_N 4
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
//--- one ordered pass over everything the quick row COULD show (value slots +
//--- LEVELS); the quick cap and the overflow split read this, so the two can
//--- never disagree about order.
int DrawStripAllSlotAt(const EDrawKind k, const int shown)
{
   int seen = 0;
   for(int s = 0; s < DRAW_SLOT_N; s++)
   {
      if(s == DRAW_SLOT_MORE) continue;   // no dialog to open from here
      if(!DrawSlotAvailable(k, s)) continue;
      if(!DrawStripVis(k, s)) continue;
      if(seen == shown) return s;
      seen++;
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
   if(slot == DRAW_SLOT_COLOR) return "";   // swatch: the face is the colour
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
   if(slot == DRAW_SLOT_LOCK)
      return ((DrawSlotRead(nm, DRAW_SLOT_LOCK) > 0.5) ? "::Files\\Icons\\bk_lock_on_d.bmp"
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
   return "Colour";
}

//--- the caption of one slot, always the CURRENT value (a value the user can
//--- read is worth more than a glyph they must learn — and the icons never
//--- REPLACE the state, they carry it: see the tooltips below).
//--- the WORD of one value (tooltips, grid chips, gear rows). Quick cells are
//--- icon-only and never read this; the words live where a value must be read.
string DrawStripSlotText(const EDrawKind k, const int slot, const string nm)
{
   if(slot == DSTRIP_SLOT_LEVELS) return "Levels";
   switch(slot)
   {
      case DRAW_SLOT_COLOR:
      {
         color c = (color)(int)DrawSlotRead(nm, DRAW_SLOT_COLOR);
         return DrawStripColorLabel(c);
      }
      case DRAW_SLOT_WIDTH:
         return IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_WIDTH)) + "px";
      case DRAW_SLOT_STYLE:
      {
         int st = (int)DrawSlotRead(nm, DRAW_SLOT_STYLE);
         if(st == STYLE_DASH) return "Dash";
         if(st == STYLE_DOT) return "Dot";
         if(st == STYLE_DASHDOT) return "D-Dash";
         if(st == STYLE_DASHDOTDOT) return "D-Dot";
         return "Solid";
      }
      case DRAW_SLOT_FILL:
         return (DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5) ? "Filled" : "Empty";
      case DRAW_SLOT_RAY:
      {
         int r = (int)DrawSlotRead(nm, DRAW_SLOT_RAY);
         if(r == 1) return "Ray>";
         if(r == 2) return "<Ray";
         if(r == 3) return "<Ray>";
         return "Segment";
      }
      case DRAW_SLOT_LOCK:
         return (DrawSlotRead(nm, DRAW_SLOT_LOCK) > 0.5) ? "Locked" : "Free";
      //--- P-DRAW-09a: the three appended controls. GLYPH shows the CODE, which
      //--- is the honest caption for a Wingdings mark the user is cycling to —
      //--- MT4's own dialog is where a number like 233 has to be typed.
      case DRAW_SLOT_FONT:
         return IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_FONT)) + "pt";
      case DRAW_SLOT_GLYPH:
         return "G" + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_GLYPH));
      case DRAW_SLOT_BACK:
         return (DrawSlotRead(nm, DRAW_SLOT_BACK) > 0.5) ? "Behind" : "Front";
      default: return "";
   }
}

//--- P-DRAW-11: the option lists, one owner per slot, so the picker and the
//--- write can never disagree about the list. The arrow marks are the small
//--- curated set traders actually use (Wingdings codes 233/234 are the classic
//--- up/down arrows), and the code number stays visible in the caption.
int DrawStripGlyphAt(const int i)
{
   static int gl[8] = {233, 234, 235, 236, 241, 242, 225, 226};
   if(i < 0 || i >= 8) return gl[0];
   return gl[i];
}
int DrawStripFontAt(const int i)
{
   static int fs[6] = {8, 10, 12, 14, 18, 24};
   if(i < 0 || i >= 6) return fs[0];
   return fs[i];
}
int DrawStripFontCount() { return 6; }
int DrawStripGlyphCount() { return 8; }

//--- P-DRAW-11: the 16-colour palette (a real palette, not the retired 8-cycle).
//--- One function, so the picker, the recency check and the write share it.
color DrawStripPal(const int i)
{
   switch(i)
   {
      case 0:  return clrWhite;
      case 1:  return clrGold;
      case 2:  return clrOrangeRed;
      case 3:  return clrCrimson;
      case 4:  return clrDodgerBlue;
      case 5:  return clrTeal;
      case 6:  return clrSilver;
      case 7:  return clrDimGray;
      case 8:  return clrLime;
      case 9:  return clrDeepPink;
      case 10: return clrViolet;
      case 11: return clrAqua;
      case 12: return clrYellow;
      case 13: return clrSaddleBrown;
      case 14: return clrBlack;
      default: return clrSteelBlue;
   }
}
int DrawStripPalCount() { return 16; }
int DrawStripPalIndex(const color c)
{
   for(int i = 0; i < DrawStripPalCount(); i++) if(DrawStripPal(i) == c) return i;
   return -1;
}
//--- the trader's own recent colours: deduped, newest first, capped.
void DrawStripRecentPush(const color c)
{
   int at = -1;
   for(int i = 0; i < s_dsRecentN; i++) if(s_dsRecent[i] == c) { at = i; break; }
   if(at == 0) return;
   if(at > 0) { for(int j = at; j > 0; j--) s_dsRecent[j] = s_dsRecent[j - 1]; }
   else
   {
      if(s_dsRecentN < DSTRIP_RECENT_MAX) s_dsRecentN++;
      for(int k = s_dsRecentN - 1; k > 0; k--) s_dsRecent[k] = s_dsRecent[k - 1];
   }
   s_dsRecent[0] = c;
}
//--- recent colours NOT already in the palette (the picker's second row).
int DrawStripRecentExtra(color &out[])
{
   int n = 0;
   for(int i = 0; i < s_dsRecentN && n < DSTRIP_RECENT_MAX; i++)
      if(DrawStripPalIndex(s_dsRecent[i]) < 0) { out[n] = s_dsRecent[i]; n++; }
   return n;
}

//--- P-DRAW-11: which slots OPEN a picker (a value with a list) and which fire
//--- at once (a toggle or an action). ONE pair, so the tap router and the rim
//--- painter cannot disagree about a cell's behaviour.
bool DrawStripHasPicker(const int slot)
{
   return (slot == DRAW_SLOT_COLOR || slot == DRAW_SLOT_WIDTH ||
           slot == DRAW_SLOT_STYLE || slot == DRAW_SLOT_RAY ||
           slot == DRAW_SLOT_FONT  || slot == DRAW_SLOT_GLYPH ||
           slot == DSTRIP_SLOT_LEVELS);
}
bool DrawStripIsToggle(const int slot)
{
   return (slot == DRAW_SLOT_FILL || slot == DRAW_SLOT_LOCK || slot == DRAW_SLOT_BACK);
}
//--- how many options this popover shows right now (LEVELS = membership rows).
int DrawStripPickCount(const EDrawKind k, const int slot)
{
   if(slot == DRAW_SLOT_COLOR)
   {
      color ex[DSTRIP_RECENT_MAX];
      int n = DrawStripPalCount() + DrawStripRecentExtra(ex);
      return (n > DSTRIP_GRID_MAX ? DSTRIP_GRID_MAX : n);
   }
   if(slot == DRAW_SLOT_WIDTH) return 5;
   if(slot == DRAW_SLOT_STYLE) return 5;
   if(slot == DRAW_SLOT_RAY) return 4;
   if(slot == DRAW_SLOT_FONT) return DrawStripFontCount();
   if(slot == DRAW_SLOT_GLYPH) return DrawStripGlyphCount();
   if(slot == DSTRIP_SLOT_LEVELS) return DrawStripGearLevelCount();
   return 0;
}
//--- the option's colour (colour picker only; clrNONE elsewhere).
color DrawStripPickColor(const int slot, const int row)
{
   if(slot != DRAW_SLOT_COLOR || row < 0) return clrNONE;
   if(row < DrawStripPalCount()) return DrawStripPal(row);
   color ex[DSTRIP_RECENT_MAX];
   int n = DrawStripRecentExtra(ex);
   int j = row - DrawStripPalCount();
   if(j >= 0 && j < n) return ex[j];
   return clrNONE;
}
//--- the option's caption (colour cells are swatches: no text, tooltip speaks).
string DrawStripPickText(const EDrawKind k, const int slot, const int row)
{
   if(slot == DRAW_SLOT_WIDTH)
   {
      if(row < 0 || row > 4) return "";
      return IntegerToString(row + 1) + "px";
   }
   if(slot == DRAW_SLOT_STYLE)
   {
      if(row == 1) return "Dash";
      if(row == 2) return "Dot";
      if(row == 3) return "D-Dash";
      if(row == 4) return "D-Dot";
      if(row == 0) return "Solid";
      return "";
   }
   if(slot == DRAW_SLOT_RAY)
   {
      if(row == 1) return "Ray>";
      if(row == 2) return "<Ray";
      if(row == 3) return "<Ray>";
      if(row == 0) return "Segment";
      return "";
   }
   if(slot == DRAW_SLOT_FONT)
   {
      if(row < 0 || row >= DrawStripFontCount()) return "";
      return IntegerToString(DrawStripFontAt(row)) + "pt";
   }
   if(slot == DRAW_SLOT_GLYPH)
   {
      if(row < 0 || row >= DrawStripGlyphCount()) return "";
      return "G" + IntegerToString(DrawStripGlyphAt(row));
   }
   return "";
}
//--- is this option the one the drawing wears now (the gold pill)?
bool DrawStripPickIsCur(const string nm, const EDrawKind k, const int slot, const int row)
{
   if(slot == DRAW_SLOT_COLOR)
   {
      color c = DrawStripPickColor(slot, row);
      return (c != clrNONE && (color)(int)DrawSlotRead(nm, DRAW_SLOT_COLOR) == c);
   }
   if(slot == DRAW_SLOT_WIDTH) return ((int)DrawSlotRead(nm, DRAW_SLOT_WIDTH) == row + 1);
   if(slot == DRAW_SLOT_STYLE) return ((int)DrawSlotRead(nm, DRAW_SLOT_STYLE) == row);
   if(slot == DRAW_SLOT_RAY)   return ((int)DrawSlotRead(nm, DRAW_SLOT_RAY) == row);
   if(slot == DRAW_SLOT_FONT)  return ((int)DrawSlotRead(nm, DRAW_SLOT_FONT) == DrawStripFontAt(row));
   if(slot == DRAW_SLOT_GLYPH) return ((int)DrawSlotRead(nm, DRAW_SLOT_GLYPH) == DrawStripGlyphAt(row));
   return false;
}
//--- APPLY one picker row: moved after DrawStripWriteValue (MQL4 is
//--- define-before-use), see below. The contract lives here: through the group
//--- fan-out (P-DRAW-09b), learning the look for the next drawing (P-DRAW-01c).

//--- P-DRAW-09b: the tip says WHICH drawings the tap will change — the one thing
//--- a multi-drawing toolbar must never leave to guesswork.
string DrawStripTipScope()
{
   int n = DrawSelCount();
   if(n > 1) return "  ·  applies to all " + IntegerToString(n) + " selected";
   return "";
}

//--- P-DRAW-13: an icon cell's tooltip is where its VALUE is read (the face
//--- carries the picture, the words live here), so the value is interpolated.
string DrawStripSlotTip(const EDrawKind k, const int slot, const string nm)
{
   string scope = DrawStripTipScope();
   switch(slot)
   {
      case DRAW_SLOT_COLOR:
         return "Colour: " + DrawStripColorLabel((color)(int)DrawSlotRead(nm, DRAW_SLOT_COLOR)) +
                " — tap to choose" + scope;
      case DRAW_SLOT_WIDTH:
         return "Line width: " + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_WIDTH)) +
                " px — tap to choose" + scope;
      case DRAW_SLOT_STYLE:
         return "Line style: " + DrawStripSlotText(k, DRAW_SLOT_STYLE, nm) +
                " — tap to choose" + scope;
      case DRAW_SLOT_FILL:
         return "Fill: " + DrawStripSlotText(k, DRAW_SLOT_FILL, nm) + " — tap to toggle" + scope;
      case DRAW_SLOT_RAY:
         return "Ray: " + DrawStripSlotText(k, DRAW_SLOT_RAY, nm) +
                " — tap to choose segment/ray/both" + scope;
      case DRAW_SLOT_LOCK:
         return "Lock: " + DrawStripSlotText(k, DRAW_SLOT_LOCK, nm) +
                " — a locked drawing cannot be moved or edited" + scope;
      case DRAW_SLOT_FONT:
         return "Text size: " + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_FONT)) +
                " pt — tap to choose" + scope;
      case DRAW_SLOT_GLYPH:
         return "Arrow mark: glyph " + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_GLYPH)) +
                " — tap to choose" + scope;
      case DRAW_SLOT_BACK:
         return "Behind the candles: " + DrawStripSlotText(k, DRAW_SLOT_BACK, nm) +
                " — tap to toggle" + scope;
      default: break;
   }
   if(slot == DSTRIP_SLOT_LEVELS)
      return "Levels: " + IntegerToString(DrawLevelCount(nm)) + " on — tap to edit membership" +
             " (the held drawing; MT4 draws every level it has)";
   return "";
}
//--- chrome tooltips: grip/badge/actions.
string DrawStripActTip(const int a)
{
   if(a == DSTRIP_ACT_MORE) return "More: apply-to-all, templates, duplicate, undo";
   if(a == DSTRIP_ACT_GEAR) return "Full settings: style, levels, template, strip";
   if(a == DSTRIP_ACT_PIN) return (s_dsPinned ? "Pinned: outside click won't dismiss — tap to unpin"
                                              : "Pin: keep the strip while editing");
   if(a == DSTRIP_ACT_DEL)
   {
      int n = DrawSelCount();
      if(n > 1) return "Delete these " + IntegerToString(n) + " drawings (not undoable)";
      return "Delete this drawing (not undoable)";
   }
   return "";
}

//--- P-DRAW-11: the option's tooltip — the value AND the group it will change.
string DrawStripPickTip(const string nm, const EDrawKind k, const int slot, const int row)
{
   string scope = DrawStripTipScope();
   if(slot == DRAW_SLOT_COLOR)
   {
      color c = DrawStripPickColor(slot, row);
      if(c == clrNONE) return "";
      return "Colour: " + DrawStripColorLabel(c) + " — tap to apply" + scope;
   }
   string t = DrawStripPickText(k, slot, row);
   if(t == "") return "";
   return t + " — tap to apply" + scope;
}

//--- which cells wear the "this is ON" face. ONE function, so no cell can
//--- disagree with the state it reports.
bool DrawStripSlotOn(const int slot, const string nm)
{
   if(slot == DRAW_SLOT_FILL) return (DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5);
   if(slot == DRAW_SLOT_LOCK) return (DrawSlotRead(nm, DRAW_SLOT_LOCK) > 0.5);
   if(slot == DRAW_SLOT_BACK) return (DrawSlotRead(nm, DRAW_SLOT_BACK) > 0.5);
   return false;
}

//--- P-DRAW-09c: the badge text. ONE owner of what the strip says it is serving,
//--- so the group count can never be printed from one place and applied in another.
string DrawStripTitle()
{
   if(s_dsObj == "") return "";
   string t = DrawKindName(s_dsKind);
   int n = DrawSelCount();
   if(n > 1) t += "  x" + IntegerToString(n);
   return t;
}

//--- P-DRAW-13: the LEVELS union both the popover and the gear tab read — the
//--- nine common values plus the drawing's own customs, capped. ONE builder so
//--- the two editors can never disagree about row i.
bool DrawStripLevelIsCommon(const double v)
{
   for(int j = 0; j < DrawStripLevelCommonCount(); j++)
      if(MathAbs(DrawStripLevelCommon(j) - v) < 0.000001) return true;
   return false;
}
int DrawStripGearLevelCount()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return 0;
   if(!DrawKindHasLevels(s_dsKind)) return 0;
   int n = DrawStripLevelCommonCount();
   int cur = DrawLevelCount(s_dsObj);
   for(int i = 0; i < cur && n < DSTRIP_GLIST_MAX; i++)
   {
      double v = DrawLevelValue(s_dsObj, i);
      if(!MathIsValidNumber(v)) continue;
      if(DrawStripLevelIsCommon(v)) continue;
      bool dup = false;
      for(int j = 0; j < i; j++)
         if(MathAbs(DrawLevelValue(s_dsObj, j) - v) < 0.000001) { dup = true; break; }
      if(!dup) n++;
   }
   if(n > DSTRIP_GLIST_MAX) n = DSTRIP_GLIST_MAX;
   return n;
}
double DrawStripGearLevelAt(const int row)
{
   int nc = DrawStripLevelCommonCount();
   if(row >= 0 && row < nc) return DrawStripLevelCommon(row);
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return EMPTY_VALUE;
   int seen = nc;
   int cur = DrawLevelCount(s_dsObj);
   for(int i = 0; i < cur; i++)
   {
      double v = DrawLevelValue(s_dsObj, i);
      if(!MathIsValidNumber(v)) continue;
      if(DrawStripLevelIsCommon(v)) continue;
      bool dup = false;
      for(int j = 0; j < i; j++)
         if(MathAbs(DrawLevelValue(s_dsObj, j) - v) < 0.000001) { dup = true; break; }
      if(dup) continue;
      if(seen == row) return v;
      seen++;
      if(seen >= DSTRIP_GLIST_MAX) break;
   }
   return EMPTY_VALUE;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — THE FIBO LEVEL-MEMBERSHIP EDITOR. MT4 draws every level a fibo
// HAS, so there is no per-level visibility to toggle: the editor edits
// MEMBERSHIP (add/remove values), which is the power MT4 buries four dialogs
// deep. Structural: it rewrites the HELD drawing's level set only (a group
// with different sets has no well-defined union to edit).
// ══════════════════════════════════════════════════════════════════════════
double DrawStripLevelCommon(const int i)
{
   switch(i)
   {
      case 0: return 0.0;
      case 1: return 23.6;
      case 2: return 38.2;
      case 3: return 50.0;
      case 4: return 61.8;
      case 5: return 78.6;
      case 6: return 100.0;
      case 7: return 127.2;
      default: return 161.8;
   }
}
int DrawStripLevelCommonCount() { return 9; }
string DrawStripLevelName(const double v) { return DoubleToString(v, 1); }
int DrawStripLevelFind(const string nm, const double v)
{
   int n = DrawLevelCount(nm);
   for(int i = 0; i < n; i++)
      if(MathAbs(DrawLevelValue(nm, i) - v) < 0.000001) return i;
   return -1;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — THE MORE-POPOVER MODEL. Rows are typed (action vs preset vs
// overflow slot) and rebuilt by ONE builder the layout, the painter and the
// router all read — "which row does what" has exactly one answer.
// ══════════════════════════════════════════════════════════════════════════
void DrawStripMoreBuild()
{
   s_dsPN = 0;
   if(s_dsKind == DK_NONE || s_dsObj == "") return;
   EDrawKind k = s_dsKind;
   int r = 0;
   // 1. group apply-all (the retired ALL cell's seat, accent-styled, no icon)
   s_dsMoreKind[r] = DSTRIP_MK_APPLYALL; s_dsMoreArg[r] = 0; r++;
   // 2. templates: every preset + save (the retired TPL/SAVE seats)
   int np = DrawPresetCount(k);
   for(int i = 0; i < np && r < DSTRIP_PICK_MAX; i++)
   { s_dsMoreKind[r] = DSTRIP_MK_PRESET; s_dsMoreArg[r] = i; r++; }
   if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_SAVE; s_dsMoreArg[r] = 0; r++; }
   // 3. edit: duplicate + undo
   if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_DUPE; s_dsMoreArg[r] = 0; r++; }
   if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_UNDO; s_dsMoreArg[r] = 0; r++; }
   // 4. overflow value slots past the 6-cap (CHANNEL/FIBOCHAN levels)
   int no = DrawStripOverflowCount(k);
   for(int j = 0; j < no && r < DSTRIP_PICK_MAX; j++)
   { s_dsMoreKind[r] = DSTRIP_MK_SLOT; s_dsMoreArg[r] = DrawStripOverflowSlotAt(k, j); r++; }
   s_dsPN = r;
}
string DrawStripMoreText(const int r)
{
   if(r < 0 || r >= s_dsPN) return "";
   int kind = s_dsMoreKind[r], arg = s_dsMoreArg[r];
   if(kind == DSTRIP_MK_APPLYALL)
   {
      int n = DrawSelCount();
      return "Apply to all " + DrawKindName(s_dsKind) + (n > 1 ? " (x" + IntegerToString(n) + ")" : "");
   }
   if(kind == DSTRIP_MK_PRESET) return DrawPresetName(s_dsKind, arg);
   if(kind == DSTRIP_MK_SAVE) return "Save current look";
   if(kind == DSTRIP_MK_DUPE) return "Duplicate";
   if(kind == DSTRIP_MK_UNDO) return (s_duValid ? "Undo last look" : "Undo (nothing yet)");
   if(kind == DSTRIP_MK_SLOT) return DrawStripSlotText(s_dsKind, arg, s_dsObj) + " ...";
   return "";
}
string DrawStripMoreRes(const int r)
{
   if(r < 0 || r >= s_dsPN) return "";
   int kind = s_dsMoreKind[r];
   if(kind == DSTRIP_MK_PRESET) return "::Files\\Icons\\gl_template_m.bmp";
   if(kind == DSTRIP_MK_SAVE) return "::Files\\Icons\\gl_plus_m.bmp";
   if(kind == DSTRIP_MK_DUPE) return "::Files\\Icons\\bk_copy.bmp";
   if(kind == DSTRIP_MK_UNDO) return "::Files\\Icons\\bk_undo.bmp";
   if(kind == DSTRIP_MK_SLOT) return DrawStripIconRes(s_dsMoreArg[r], s_dsObj);
   return "";   // APPLYALL: accent-styled, no icon
}
string DrawStripMoreTip(const int r)
{
   if(r < 0 || r >= s_dsPN) return "";
   int kind = s_dsMoreKind[r], arg = s_dsMoreArg[r];
   string scope = DrawStripTipScope();
   if(kind == DSTRIP_MK_APPLYALL)
      return "This look on EVERY " + DrawKindName(s_dsKind) + " (MT4's dialog is one at a time)";
   if(kind == DSTRIP_MK_PRESET)
      return "Template: " + DrawPresetName(s_dsKind, arg) + " — tap to apply the whole look" + scope;
   if(kind == DSTRIP_MK_SAVE)
      return "Save this look as one of MY templates — the next drawing of this tool wears it";
   if(kind == DSTRIP_MK_DUPE) return "Copy this drawing beside itself (selects the copy)";
   if(kind == DSTRIP_MK_UNDO)
      return (s_duValid ? "Restore the look before the last edit" : "No edit to undo yet");
   if(kind == DSTRIP_MK_SLOT)
      return DrawStripSlotTip(s_dsKind, arg, s_dsObj);
   return "";
}
bool DrawStripMoreIsCur(const int r)
{
   if(r < 0 || r >= s_dsPN) return false;
   if(s_dsMoreKind[r] == DSTRIP_MK_PRESET) return (s_dsMoreArg[r] == s_dsTpl[s_dsKind]);
   return false;
}

//--- P-DRAW-13: the gear panel's layout. Tabs after content width is fixed
//--- (DSTRIP_GEAR_W); grids wrap inside it, lists are full-width. Returns the
//--- y below the block (foot included). painters read the same arrays.
int DrawStripGearTabs()
{
   int n = 0;
   s_dsGearTab[n + 1] = DSTRIP_GEAR_STYLE; n++;
   if(DrawKindHasLevels(s_dsKind)) { s_dsGearTab[n + 1] = DSTRIP_GEAR_LEVELS; n++; }
   else if(s_dsKind == DK_TEXT || s_dsKind == DK_ARROW) { s_dsGearTab[n + 1] = DSTRIP_GEAR_MARK; n++; }
   s_dsGearTab[n + 1] = DSTRIP_GEAR_TPL; n++;
   s_dsGearTab[n + 1] = DSTRIP_GEAR_STRIP; n++;
   s_dsGearTab[0] = n;
   if(s_dsGear != 0)
   {
      bool ok = false;
      for(int i = 1; i <= n; i++) if(s_dsGearTab[i] == s_dsGear) ok = true;
      if(!ok) s_dsGear = s_dsGearTab[1];
   }
   return n;
}
string DrawStripGearTabText(const int tab)
{
   if(tab == DSTRIP_GEAR_STYLE) return "Style";
   if(tab == DSTRIP_GEAR_LEVELS) return "Levels";
   if(tab == DSTRIP_GEAR_MARK) return (s_dsKind == DK_ARROW ? "Mark" : "Text");
   if(tab == DSTRIP_GEAR_TPL) return "Template";
   if(tab == DSTRIP_GEAR_STRIP) return "Strip";
   return "";
}
bool DrawStripGearGridSwatches()
{
   color ex[DSTRIP_RECENT_MAX];
   int n = DrawStripPalCount() + DrawStripRecentExtra(ex);
   int cw = DSTRIP_GEAR_W - 2 * DSTRIP_PAD;
   int cols = (cw + DSTRIP_GAP) / (DSTRIP_CELL + DSTRIP_GAP);
   if(cols < 1) cols = 1;
   for(int i = 0; i < n; i++)
   {
      if(s_dsGGN >= DSTRIP_GRID_MAX) return false;
      int g = s_dsGGN++;
      color c = (i < DrawStripPalCount()) ? DrawStripPal(i) : ex[i - DrawStripPalCount()];
      s_dsGGKind[g] = 0; s_dsGGC[g] = c;
      s_dsGGW[g] = DSTRIP_CELL;
      s_dsGGX[g] = DSTRIP_PAD + (i % cols) * (DSTRIP_CELL + DSTRIP_GAP);
      s_dsGGY[g] = -1;   // filled by the block pass below (row top)
   }
   return true;
}
int DrawStripGearGridRowsUsed(const int n, const int cols) { return (n + cols - 1) / cols; }
bool DrawStripGearGridChips(const int slot, const int count)
{
   int cw = DSTRIP_GEAR_W - 2 * DSTRIP_PAD;
   int cols = (cw + DSTRIP_GAP) / (DSTRIP_GRID_CHIP + DSTRIP_GAP);
   if(cols < 1) cols = 1;
   for(int i = 0; i < count; i++)
   {
      if(s_dsGGN >= DSTRIP_GRID_MAX) return false;
      int g = s_dsGGN++;
      s_dsGGKind[g] = 1; s_dsGGSlot[g] = slot; s_dsGGArg[g] = i;
      s_dsGGW[g] = DSTRIP_GRID_CHIP;
      s_dsGGX[g] = DSTRIP_PAD + (i % cols) * (DSTRIP_GRID_CHIP + DSTRIP_GAP);
      s_dsGGY[g] = -1;
   }
   return true;
}
bool DrawStripGearRow(const int kind, const int arg)
{
   if(s_dsGRN >= DSTRIP_GLIST_MAX) return false;
   s_dsGRKind[s_dsGRN] = kind; s_dsGRArg[s_dsGRN] = arg;
   s_dsGRN++;
   return true;
}
//--- stamp row tops for grid cells appended since mark (one block = one call).
void DrawStripGearGridStamp(const int mark, int &y, const int cols)
{
   int n = s_dsGGN - mark;
   int rows = (n + cols - 1) / cols;
   if(rows < 1) rows = 1;
   for(int g = mark; g < s_dsGGN; g++)
   {
      int row = (g - mark) / cols;
      s_dsGGY[g] = y + row * (DSTRIP_CELL + DSTRIP_GAP);
   }
   y += rows * DSTRIP_CELL + (rows - 1) * DSTRIP_GAP + DSTRIP_GAP;
}
int DrawStripGearLayout(int y0)
{
   int cw = DSTRIP_GEAR_W - 2 * DSTRIP_PAD;
   int y = y0;
   int nt = DrawStripGearTabs();
   int tw = (nt > 0 ? (cw - (nt - 1) * DSTRIP_GAP) / nt : cw);
   s_dsGearTabsY = y;
   for(int t = 0; t < nt && t < 4; t++)
   {
      s_dsGearTabX[t] = DSTRIP_PAD + t * (tw + DSTRIP_GAP);
      s_dsGearTabW[t] = tw;
   }
   y += DSTRIP_CELL + DSTRIP_GAP;
   s_dsGRN = 0; s_dsGGN = 0;
   s_dsGearEditY[0] = -1; s_dsGearEditY[1] = -1; s_dsGearEditY[2] = -1;
   EDrawKind k = s_dsKind;
   if(s_dsGear == DSTRIP_GEAR_STYLE)
   {
      int mark = s_dsGGN;
      DrawStripGearGridSwatches();
      int cols = (cw + DSTRIP_GAP) / (DSTRIP_CELL + DSTRIP_GAP);
      DrawStripGearGridStamp(mark, y, cols);
      s_dsGearEditY[0] = y; y += DSTRIP_CELL + DSTRIP_GAP;   // hex edit row
      mark = s_dsGGN;
      DrawStripGearGridChips(DRAW_SLOT_WIDTH, 5);
      cols = (cw + DSTRIP_GAP) / (DSTRIP_GRID_CHIP + DSTRIP_GAP);
      DrawStripGearGridStamp(mark, y, cols);
      mark = s_dsGGN;
      DrawStripGearGridChips(DRAW_SLOT_STYLE, 5);
      DrawStripGearGridStamp(mark, y, cols);
      if(DrawSlotAvailable(k, DRAW_SLOT_RAY))
      {
         mark = s_dsGGN;
         DrawStripGearGridChips(DRAW_SLOT_RAY, 4);
         DrawStripGearGridStamp(mark, y, cols);
      }
      if(DrawSlotAvailable(k, DRAW_SLOT_FILL)) DrawStripGearRow(1, DRAW_SLOT_FILL);
      DrawStripGearRow(1, DRAW_SLOT_LOCK);
      DrawStripGearRow(1, DRAW_SLOT_BACK);
   }
   else if(s_dsGear == DSTRIP_GEAR_LEVELS)
   {
      int nl = DrawStripGearLevelCount();
      for(int i = 0; i < nl; i++) DrawStripGearRow(4, i);
      DrawStripGearRow(5, 0);   // All
      DrawStripGearRow(5, 1);   // None
      s_dsGearEditY[1] = y + s_dsGRN * (DSTRIP_CELL + DSTRIP_GAP);
   }
   else if(s_dsGear == DSTRIP_GEAR_MARK)
   {
      if(k == DK_TEXT)
      {
         s_dsGearEditY[2] = y; y += DSTRIP_CELL + DSTRIP_GAP;   // caption edit
         int mark = s_dsGGN;
         DrawStripGearGridChips(DRAW_SLOT_FONT, DrawStripFontCount());
         int cols = (cw + DSTRIP_GAP) / (DSTRIP_GRID_CHIP + DSTRIP_GAP);
         DrawStripGearGridStamp(mark, y, cols);
      }
      else
      {
         for(int g = 0; g < DrawStripGlyphCount(); g++)
            DrawStripGearRow(8, DRAW_SLOT_GLYPH * 256 + g);
      }
   }
   else if(s_dsGear == DSTRIP_GEAR_TPL)
   {
      int np = DrawPresetCount(k);
      for(int i = 0; i < np; i++) DrawStripGearRow(2, i);
      DrawStripGearRow(3, 0);   // save
      DrawStripGearRow(7, 0);   // default-learn
   }
   else if(s_dsGear == DSTRIP_GEAR_STRIP)
   {
      for(int s = 0; s < DRAW_SLOT_N; s++)
      {
         if(s == DRAW_SLOT_MORE) continue;
         if(!DrawSlotAvailable(k, s)) continue;
         DrawStripGearRow(6, s);
      }
      if(DrawKindHasLevels(k)) DrawStripGearRow(6, DRAW_SLOT_MORE);  // LEVELS seat
      DrawStripGearRow(5, 2);   // reset layout
   }
   // list rows + (levels) edit row
   for(int r = 0; r < s_dsGRN; r++) s_dsGRY[r] = y + r * (DSTRIP_CELL + DSTRIP_GAP);
   y += s_dsGRN * (DSTRIP_CELL + DSTRIP_GAP);
   if(s_dsGear == DSTRIP_GEAR_LEVELS && s_dsGearEditY[1] < 0)
      s_dsGearEditY[1] = y;
   if(s_dsGear == DSTRIP_GEAR_LEVELS) y += DSTRIP_CELL + DSTRIP_GAP;
   s_dsGearFootY = y;
   y += DSTRIP_CELL + DSTRIP_GAP;
   return y;
}

//--- P-DRAW-13: the shell's own widths and positions, in ONE pass: the painter,
//--- the plate's size, the hit test and the grip carry all read these, so
//--- "where a cell is" has exactly one answer. Single row, never wraps:
//--- [grip][badge][<=6 icons][more][gear][pin][del], then the open blocks.
void DrawStripLayout()
{
   DrawStripVisInit();
   EDrawKind k = s_dsKind;
   s_dsN = DrawStripQuickCount(k);
   int x = DSTRIP_PAD;
   x += DSTRIP_CELL + DSTRIP_GAP;                    // grip
   s_dsBadgeW = PnlTextW(DrawStripTitle(), 8) + 12;  // badge (info label)
   if(s_dsBadgeW < 40) s_dsBadgeW = 40;
   x += s_dsBadgeW + DSTRIP_GAP;
   for(int i = 0; i < s_dsN; i++)
   {
      s_dsCX[i] = x;
      s_dsCW[i] = DSTRIP_CELL;
      x += DSTRIP_CELL + DSTRIP_GAP;
   }
   for(int a = 0; a < DSTRIP_ACT_N; a++) x += DSTRIP_CELL + DSTRIP_GAP;
   int quickW = x - DSTRIP_GAP + DSTRIP_PAD;
   int y = DSTRIP_PAD + DSTRIP_CELL + DSTRIP_GAP;    // first open block's top
   int maxW = quickW;
   //--- popover block (ONE at a time): colour grid, or full-width list rows.
   s_dsPN = 0;
   if(s_dsPicker == DRAW_SLOT_COLOR)
   {
      color ex[DSTRIP_RECENT_MAX];
      int n = DrawStripPalCount() + DrawStripRecentExtra(ex);
      if(n > DSTRIP_GRID_MAX) n = DSTRIP_GRID_MAX;
      int cols = 8, cw = DSTRIP_CELL;
      int gw = cols * cw + (cols - 1) * DSTRIP_GAP;
      int rows = (n + cols - 1) / cols;
      for(int r = 0; r < n; r++)
      {
         s_dsPY[r] = y + (r / cols) * (DSTRIP_CELL + DSTRIP_GAP);
         // x stored implicitly: PAD + (r % cols) * (CELL+GAP), centred below
      }
      y += rows * DSTRIP_CELL + (rows - 1) * DSTRIP_GAP + DSTRIP_GAP;
      if(gw + 2 * DSTRIP_PAD > maxW) maxW = gw + 2 * DSTRIP_PAD;
      s_dsPN = n;
   }
   else if(s_dsPicker != DSTRIP_PICK_NONE)
   {
      if(s_dsPicker == DSTRIP_MORE) DrawStripMoreBuild();
      int need = 0;
      if(s_dsPicker == DSTRIP_MORE) need = s_dsPN;
      else need = DrawStripPickCount(k, s_dsPicker);
      if(need > DSTRIP_PICK_MAX) need = DSTRIP_PICK_MAX;
      // list width: widest row text + icon seat, capped
      int lw = 0;
      for(int r = 0; r < need; r++)
      {
         string t = DrawStripPopRowText(r);
         int w = PnlTextW(t, 7) + 34;
         if(w > lw) lw = w;
      }
      if(lw < 150) lw = 150;
      if(lw > 280) lw = 280;
      for(int r2 = 0; r2 < need; r2++) s_dsPY[r2] = y + r2 * (DSTRIP_CELL + DSTRIP_GAP);
      y += need * DSTRIP_CELL + (need - 1) * DSTRIP_GAP + DSTRIP_GAP;
      if(lw + 2 * DSTRIP_PAD > maxW) maxW = lw + 2 * DSTRIP_PAD;
      s_dsPN = need;
   }
   //--- gear block (shuts the popover; its own tabs/rows/foot follow).
   s_dsGRN = 0; s_dsGGN = 0;
   if(s_dsGear != 0)
   {
      y = DrawStripGearLayout(y);
      int gearW = DSTRIP_GEAR_W + 2 * DSTRIP_PAD;
      if(gearW > maxW) maxW = gearW;
   }
   s_dsW = maxW;
   s_dsH = y - DSTRIP_GAP + DSTRIP_PAD;
}
//--- popover list-row text, one owner for layout and paint.
string DrawStripPopRowText(const int r)
{
   if(s_dsPicker == DSTRIP_MORE) return DrawStripMoreText(r);
   if(s_dsPicker == DSTRIP_SLOT_LEVELS)
   {
      double v = DrawStripGearLevelAt(r);
      return (MathIsValidNumber(v) ? DrawStripLevelName(v) : "");
   }
   return DrawStripPickText(s_dsKind, s_dsPicker, r);
}
string DrawStripPopRowRes(const int r)
{
   if(s_dsPicker == DSTRIP_MORE) return DrawStripMoreRes(r);
   if(s_dsPicker == DRAW_SLOT_WIDTH)
      return "::Files\\Icons\\bk_w" + IntegerToString(r + 1) + ".bmp";
   if(s_dsPicker == DRAW_SLOT_STYLE)
      return "::Files\\Icons\\bk_style" + IntegerToString(r) + ".bmp";
   if(s_dsPicker == DRAW_SLOT_RAY)
      return "::Files\\Icons\\bk_ray" + IntegerToString(r) + ".bmp";
   if(s_dsPicker == DRAW_SLOT_FONT) return "::Files\\Icons\\gl_textsize_m.bmp";
   if(s_dsPicker == DRAW_SLOT_GLYPH) return "::Files\\Icons\\bk_glyph.bmp";
   if(s_dsPicker == DSTRIP_SLOT_LEVELS) return "::Files\\Icons\\bk_levels.bmp";
   return "";
}
string DrawStripPopRowTip(const int r)
{
   if(s_dsPicker == DSTRIP_MORE) return DrawStripMoreTip(r);
   if(s_dsPicker == DSTRIP_SLOT_LEVELS)
   {
      double v = DrawStripGearLevelAt(r);
      if(!MathIsValidNumber(v)) return "";
      bool on = (DrawStripLevelFind(s_dsObj, v) >= 0);
      return DrawStripLevelName(v) + (on ? " is on — tap to remove" : " — tap to add") +
             " (the held drawing)";
   }
   return DrawStripPickTip(s_dsObj, s_dsKind, s_dsPicker, r);
}
bool DrawStripPopRowIsCur(const int r)
{
   if(s_dsPicker == DSTRIP_MORE) return DrawStripMoreIsCur(r);
   if(s_dsPicker == DSTRIP_SLOT_LEVELS)
   {
      double v = DrawStripGearLevelAt(r);
      return (MathIsValidNumber(v) && DrawStripLevelFind(s_dsObj, v) >= 0);
   }
   return DrawStripPickIsCur(s_dsObj, s_dsKind, s_dsPicker, r);
}

//--- P-DRAW-11: shut the popover without touching the strip (a pick, a second
//--- tap on its cell, a tap on the plate, Esc). Deletes the popover's objects;
//--- the caller re-layouts and repaints.
void DrawStripClosePicker()
{
   if(s_dsPicker == DSTRIP_PICK_NONE && s_dsPN <= 0) return;
   for(int r = 0; r < DSTRIP_PICK_MAX; r++)
   {
      ObjectDelete(0, DrawStripPickName(r));
      ObjectDelete(0, DrawStripPickIconName(r));
      ObjectDelete(0, DrawStripPickLabelName(r));
   }
   s_dsPicker = DSTRIP_PICK_NONE;
   s_dsPN = 0;
}
//--- P-DRAW-13: shut the gear panel (tab switch = shut + open).
void DrawStripGearClose()
{
   if(s_dsGear == 0 && s_dsGRN <= 0 && s_dsGGN <= 0) return;
   for(int t = 0; t < 5; t++) ObjectDelete(0, DrawStripGearTabName(t));
   for(int g = 0; g < DSTRIP_GRID_MAX; g++)
   {
      ObjectDelete(0, DrawStripGridName(g));
      ObjectDelete(0, DrawStripGridIconName(g));
   }
   for(int r = 0; r < DSTRIP_GLIST_MAX; r++)
   {
      ObjectDelete(0, DrawStripRowName(r));
      ObjectDelete(0, DrawStripRowIconName(r));
      ObjectDelete(0, DrawStripRowLabelName(r));
   }
   for(int f = 0; f < 4; f++) ObjectDelete(0, DrawStripFootName(f));
   for(int e = 0; e < 3; e++) ObjectDelete(0, DrawStripEditName(e));
   s_dsGear = 0; s_dsGRN = 0; s_dsGGN = 0;
}

void DrawStripClose()
{
   for(int i = 0; i < DSTRIP_MAX_SLOTS; i++)
   {
      ObjectDelete(0, DrawStripObjName(i));
      ObjectDelete(0, DrawStripIconName(i));
   }
   ObjectDelete(0, DrawStripGripName());
   ObjectDelete(0, DrawStripGripIconName());
   ObjectDelete(0, DrawStripBadgeName());
   for(int a = 0; a < DSTRIP_ACT_N; a++)
   {
      ObjectDelete(0, DrawStripActName(a));
      ObjectDelete(0, DrawStripActIconName(a));
   }
   for(int r = 0; r < DSTRIP_PICK_MAX; r++)
   {
      ObjectDelete(0, DrawStripPickName(r));
      ObjectDelete(0, DrawStripPickIconName(r));
      ObjectDelete(0, DrawStripPickLabelName(r));
   }
   DrawStripGearClose();
   ObjectDelete(0, DrawStripBgName());
   s_dsOpen = false;
   s_dsObj = "";
   s_dsKind = DK_NONE;
   s_dsN = 0;
   s_dsPicker = DSTRIP_PICK_NONE;   // the popover dies with the strip
   s_dsPN = 0;                      // (the recent colours survive: they are the trader's)
   s_dsPinned = false;
   s_dsGripLive = false;
   // P-DRAW-09b: the group belongs to the OPEN strip — a new one takes its own
   // snapshot (the selection may have changed on the chart in between).
   DrawSelClear();
}

//--- P-DRAW-09d: GUARDED WRITES. In MT4 every `ObjectSet*` marks the chart dirty
//--- and the repaint costs what the chart's object count costs (~1000-2500 here),
//--- so a write of a value the object already has is pure loss (P-PERF-02's law).
//--- These two are the strip's whole write path for faces, and both answer
//--- whether a pixel really moved.
bool DrawStripSetInt(const string nm, const int prop, const long v)
{
   if(ObjectGetInteger(0, nm, prop) == v) return false;
   ObjectSetInteger(0, nm, prop, v);
   return true;
}
bool DrawStripSetStr(const string nm, const int prop, const string v)
{
   if(ObjectGetString(0, nm, prop) == v) return false;
   ObjectSetString(0, nm, prop, v);
   return true;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — THREE PAINTERS, EVERY SURFACE. Buttons stay the controls (a
// button stays under its skin, Z_PANEL_BASE/Z_PANEL_SKIN parity); bitmaps are
// faces; labels are left-aligned ink. All guarded, all answering dirty.
// ══════════════════════════════════════════════════════════════════════════
bool DrawStripBtn(const string nm, const int x, const int y, const int w, const int h,
                  const color face, const color ink, const color rim,
                  const string txt, const string tip)
{
   bool dirty = false;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_BUTTON, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      // P-DRAW-09c: the cells speak the UI's own metric owner (P-UI-34), not a
      // raw point size: MT4 sizes a font at the terminal's DPI, so a literal
      // would draw 25% wider at 125% and overflow the cell.
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, PnlPt(7));
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_ICON);
      dirty = true;
   }
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);
   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);
   dirty |= DrawStripSetInt(nm, OBJPROP_COLOR, ink);
   dirty |= DrawStripSetInt(nm, OBJPROP_BORDER_COLOR, rim);
   dirty |= DrawStripSetStr(nm, OBJPROP_TEXT, txt);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
//--- the icon face, centred in its cell (MT4 paints at native size from the
//--- label's own corner). res == "" deletes the face. Whichever object the
//--- terminal's hover lands on (button or face) carries the same tooltip.
bool DrawStripFace(const string nm, const int x, const int y, const int w, const int h,
                   const string res, const string tip)
{
   if(res == "")
   {
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); return true; }
      return false;
   }
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_BITMAP_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_ICON + 1);
   }
   bool dirty = false;
   dirty |= DrawStripSetStr(nm, OBJPROP_BMPFILE, res);
   int px = DrawStripIconPx(res);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x + (w - px) / 2);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y + (h - px) / 2);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
//--- left-aligned ink for list rows (buttons centre their text; rows read left).
bool DrawStripLbl(const string nm, const int x, const int y, const string txt,
                  const color ink, const string tip)
{
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, PnlPt(8));
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_ICON + 1);
   }
   bool dirty = false;
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y + 5);
   dirty |= DrawStripSetInt(nm, OBJPROP_COLOR, ink);
   dirty |= DrawStripSetStr(nm, OBJPROP_TEXT, txt);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
//--- "#RRGGBB" of a colour (hex edit row + swatch tooltips).
string DrawStripColorHex(const color c)
{
   int v = (int)c;
   if(v < 0) v = 0;
   return StringFormat("#%02X%02X%02X", v % 256, (v / 256) % 256, v / 65536);
}
bool DrawStripHexToColor(const string s, color &c)
{
   string t = s;
   StringTrimLeft(t); StringTrimRight(t);
   if(StringLen(t) != 7 || StringGetCharacter(t, 0) != '#') return false;
   int v = 0;
   for(int i = 1; i < 7; i++)
   {
      int ch = StringGetCharacter(t, i);
      int d = -1;
      if(ch >= '0' && ch <= '9') d = ch - '0';
      else if(ch >= 'A' && ch <= 'F') d = ch - 'A' + 10;
      else if(ch >= 'a' && ch <= 'f') d = ch - 'a' + 10;
      if(d < 0) return false;
      v = v * 16 + d;
   }
   int r = (v >> 16) & 0xFF, g = (v >> 8) & 0xFF, b = v & 0xFF;
   c = (color)(r + g * 256 + b * 65536);
   return true;
}

//--- P-DRAW-13: gear list rows — one owner for text/face/tip/state, read by
//--- layout (nothing: rows are full-width), paint and router alike.
string DrawStripGearRowText(const int r)
{
   if(r < 0 || r >= s_dsGRN) return "";
   int kind = s_dsGRKind[r], arg = s_dsGRArg[r];
   if(kind == 1) return DrawStripSlotText(s_dsKind, arg, s_dsObj);
   if(kind == 2) return DrawPresetName(s_dsKind, arg);
   if(kind == 3) return "Save current look";
   if(kind == 4)
   {
      double v = DrawStripGearLevelAt(arg);
      return (MathIsValidNumber(v) ? DrawStripLevelName(v) : "");
   }
   if(kind == 5)
   {
      if(arg == 0) return "All levels on";
      if(arg == 1) return "No levels";
      return "Reset layout";
   }
   if(kind == 6)
   {
      if(arg == DRAW_SLOT_MORE) return "Levels";
      return DrawStripSlotText(s_dsKind, arg, s_dsObj);
   }
   if(kind == 7) return "New " + DrawKindName(s_dsKind) + " wears this look";
   if(kind == 8) return "G" + IntegerToString(DrawStripGlyphAt(arg % 256));
   return "";
}
string DrawStripGearRowRes(const int r)
{
   if(r < 0 || r >= s_dsGRN) return "";
   int kind = s_dsGRKind[r], arg = s_dsGRArg[r];
   if(kind == 1)
   {
      if(arg == DRAW_SLOT_COLOR) return "";
      return DrawStripIconRes(arg, s_dsObj);
   }
   if(kind == 2 || kind == 7) return "::Files\\Icons\\gl_template_m.bmp";
   if(kind == 3) return "::Files\\Icons\\gl_plus_m.bmp";
   if(kind == 4)
   {
      double v = DrawStripGearLevelAt(arg);
      bool on = (MathIsValidNumber(v) && DrawStripLevelFind(s_dsObj, v) >= 0);
      return (on ? "::Files\\Icons\\gl_check_m.bmp" : "::Files\\Icons\\bk_levels.bmp");
   }
   if(kind == 6)
   {
      if(arg == DRAW_SLOT_MORE) return "::Files\\Icons\\bk_levels.bmp";
      if(arg == DRAW_SLOT_COLOR) return "";
      return DrawStripIconRes(arg, s_dsObj);
   }
   if(kind == 8) return "::Files\\Icons\\bk_glyph.bmp";
   return "";
}
string DrawStripGearRowTip(const int r)
{
   if(r < 0 || r >= s_dsGRN) return "";
   int kind = s_dsGRKind[r], arg = s_dsGRArg[r];
   string scope = DrawStripTipScope();
   if(kind == 1) return DrawStripSlotTip(s_dsKind, arg, s_dsObj);
   if(kind == 2) return "Template: " + DrawPresetName(s_dsKind, arg) + " — tap to apply" + scope;
   if(kind == 3) return "Save this look as one of MY templates";
   if(kind == 4)
   {
      double v = DrawStripGearLevelAt(arg);
      if(!MathIsValidNumber(v)) return "";
      bool on = (DrawStripLevelFind(s_dsObj, v) >= 0);
      return DrawStripLevelName(v) + (on ? " is on — tap to remove" : " — tap to add") +
             " (the held drawing; stays open for the next one)";
   }
   if(kind == 5)
   {
      if(arg == 0) return "Every common level on (the held drawing)";
      if(arg == 1) return "Empty the level set (the held drawing)";
      return "Show every slot of this tool again";
   }
   if(kind == 6) return "Show this slot in the quick row — tap to hide / show";
   if(kind == 7) return "Learn the look on the chart as this tool's default (next drawing wears it)";
   if(kind == 8)
      return "Arrow mark: glyph " + IntegerToString(DrawStripGlyphAt(arg % 256)) + " — tap to apply" + scope;
   return "";
}
bool DrawStripGearRowIsCur(const int r)
{
   if(r < 0 || r >= s_dsGRN) return false;
   int kind = s_dsGRKind[r], arg = s_dsGRArg[r];
   if(kind == 1) return DrawStripSlotOn(arg, s_dsObj);
   if(kind == 2) return (arg == s_dsTpl[s_dsKind]);
   if(kind == 4)
   {
      double v = DrawStripGearLevelAt(arg);
      return (MathIsValidNumber(v) && DrawStripLevelFind(s_dsObj, v) >= 0);
   }
   if(kind == 6)
   {
      if(arg == DRAW_SLOT_MORE) return DrawStripVis(s_dsKind, DSTRIP_SLOT_LEVELS);
      return DrawStripVis(s_dsKind, arg);
   }
   if(kind == 8)
      return ((int)DrawSlotRead(s_dsObj, DRAW_SLOT_GLYPH) == DrawStripGlyphAt(arg % 256));
   return false;
}

//--- action X, ONE owner (Layout's quickW and Paint read the same answer).
int DrawStripActX(const int a)
{
   return DSTRIP_PAD + DSTRIP_CELL + DSTRIP_GAP + s_dsBadgeW + DSTRIP_GAP +
          s_dsN * (DSTRIP_CELL + DSTRIP_GAP) + a * (DSTRIP_CELL + DSTRIP_GAP);
}

//--- gear edit row: created with its seed, never re-seeded after (a repaint
//--- rewriting the TEXT would fight the user's typing mid-word).
bool DrawStripEdit(const int e, const int y, const int w, const string seed, const string tip)
{
   string nm = DrawStripEditName(e);
   bool dirty = false;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_EDIT, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, PnlPt(8));
      ObjectSetInteger(0, nm, OBJPROP_COLOR, DSTRIP_CLR_LABEL);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, DSTRIP_CLR_FIELD);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, DSTRIP_CLR_LINE);
      ObjectSetInteger(0, nm, OBJPROP_READONLY, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_ICON);
      ObjectSetString(0, nm, OBJPROP_TEXT, seed);
      dirty = true;
   }
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, s_dsX + DSTRIP_PAD);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, s_dsY + y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, DSTRIP_CELL);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
string DrawStripFootText(const int f)
{
   if(f == 0) return "All";
   if(f == 1) return "Copy";
   if(f == 2) return "Del";
   return "Close";
}
string DrawStripFootTip(const int f)
{
   if(f == 0) return "This look on EVERY " + DrawKindName(s_dsKind) + " (MT4's dialog is one at a time)";
   if(f == 1) return "Copy this drawing beside itself (selects the copy)";
   if(f == 2)
   {
      int n = DrawSelCount();
      if(n > 1) return "Delete these " + IntegerToString(n) + " drawings (not undoable)";
      return "Delete this drawing (not undoable)";
   }
   return "Close the strip";
}
//--- the gear panel's own paint: tabs, grids, rows, edits, foot.
bool DrawStripGearPaint(const int contentW)
{
   bool dirty = false;
   int nt = s_dsGearTab[0];
   for(int t = 0; t < 4; t++)
   {
      string tn = DrawStripGearTabName(t);
      if(t >= nt)
      {
         if(ObjectFind(0, tn) >= 0) { ObjectDelete(0, tn); dirty = true; }
         continue;
      }
      int tab = s_dsGearTab[t + 1];
      bool sel = (tab == s_dsGear);
      dirty |= DrawStripBtn(tn, s_dsX + s_dsGearTabX[t], s_dsY + s_dsGearTabsY,
                            s_dsGearTabW[t], DSTRIP_CELL,
                            sel ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_CARD,
                            sel ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL,
                            sel ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_LINE,
                            DrawStripGearTabText(tab),
                            DrawStripGearTabText(tab) + " settings");
   }
   //--- grids (swatches + chips).
   for(int g = 0; g < DSTRIP_GRID_MAX; g++)
   {
      string gn = DrawStripGridName(g), gi = DrawStripGridIconName(g);
      if(g >= s_dsGGN)
      {
         if(ObjectFind(0, gn) >= 0) { ObjectDelete(0, gn); dirty = true; }
         if(ObjectFind(0, gi) >= 0) { ObjectDelete(0, gi); dirty = true; }
         continue;
      }
      int gx = s_dsX + s_dsGGX[g], gy = s_dsY + s_dsGGY[g];
      if(s_dsGGKind[g] == 0)
      {
         color c = s_dsGGC[g];
         bool cur = ((color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR) == c);
         string tip = "Colour: " + DrawStripColorLabel(c) + " — tap to apply" + DrawStripTipScope();
         dirty |= DrawStripBtn(gn, gx, gy, s_dsGGW[g], DSTRIP_CELL, c, DrawStripInkOn(c),
                               cur ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_LINE, "", tip);
      }
      else
      {
         int slot = s_dsGGSlot[g], arg = s_dsGGArg[g];
         bool cur = DrawStripPickIsCur(s_dsObj, s_dsKind, slot, arg);
         string txt = PnlFit(DrawStripPickText(s_dsKind, slot, arg), 7, s_dsGGW[g] - 6);
         string tip = DrawStripPickTip(s_dsObj, s_dsKind, slot, arg);
         dirty |= DrawStripBtn(gn, gx, gy, s_dsGGW[g], DSTRIP_CELL,
                               cur ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_CARD,
                               cur ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL,
                               DSTRIP_CLR_LINE, txt, tip);
      }
   }
   //--- list rows (button + face + left label).
   for(int r = 0; r < DSTRIP_GLIST_MAX; r++)
   {
      string rn = DrawStripRowName(r), ri = DrawStripRowIconName(r), rl = DrawStripRowLabelName(r);
      if(r >= s_dsGRN)
      {
         if(ObjectFind(0, rn) >= 0) { ObjectDelete(0, rn); dirty = true; }
         if(ObjectFind(0, ri) >= 0) { ObjectDelete(0, ri); dirty = true; }
         if(ObjectFind(0, rl) >= 0) { ObjectDelete(0, rl); dirty = true; }
         continue;
      }
      int py = s_dsY + s_dsGRY[r];
      int px = s_dsX + DSTRIP_PAD;
      bool cur = DrawStripGearRowIsCur(r);
      string res = DrawStripGearRowRes(r);
      string txt = DrawStripGearRowText(r);
      string tip = DrawStripGearRowTip(r);
      color face = cur ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_CARD;
      color ink = cur ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL;
      if(s_dsGRKind[r] == 6 && !cur) { face = DSTRIP_CLR_FIELD; ink = DSTRIP_CLR_TITLE; }  // hidden slot
      dirty |= DrawStripBtn(rn, px, py, contentW, DSTRIP_CELL, face, ink, DSTRIP_CLR_LINE, "", tip);
      dirty |= DrawStripFace(ri, px + 2, py, DSTRIP_CELL, DSTRIP_CELL, res, tip);
      dirty |= DrawStripLbl(rl, px + DSTRIP_CELL + 4, py,
                            PnlFit(txt, 8, contentW - DSTRIP_CELL - 8), ink, tip);
   }
   //--- edits (one per tab that types).
   for(int e = 0; e < 3; e++)
   {
      string en = DrawStripEditName(e);
      bool want = ((e == 0 && s_dsGear == DSTRIP_GEAR_STYLE) ||
                   (e == 1 && s_dsGear == DSTRIP_GEAR_LEVELS) ||
                   (e == 2 && s_dsGear == DSTRIP_GEAR_MARK && s_dsKind == DK_TEXT));
      if(!want)
      {
         if(ObjectFind(0, en) >= 0) { ObjectDelete(0, en); dirty = true; }
         continue;
      }
      if(e == 0)
         dirty |= DrawStripEdit(e, s_dsGearEditY[e], contentW,
                                DrawStripColorHex((color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR)),
                                "Custom colour as #RRGGBB — Enter applies it");
      else if(e == 1)
         dirty |= DrawStripEdit(e, s_dsGearEditY[e], contentW, "",
                                "Add a level, e.g. 88.6 — Enter adds it (the held drawing)");
      else
         dirty |= DrawStripEdit(e, s_dsGearEditY[e], contentW,
                                ObjectGetString(0, s_dsObj, OBJPROP_TEXT),
                                "Caption — Enter applies it");
   }
   //--- foot: All / Copy / Del / Close.
   for(int f = 0; f < 4; f++)
   {
      string fn = DrawStripFootName(f);
      int fx = s_dsX + DSTRIP_PAD + f * (68 + DSTRIP_GAP);
      color face = DSTRIP_CLR_CARD, ink = DSTRIP_CLR_LABEL, rim = DSTRIP_CLR_LINE;
      if(f == 0) { face = DSTRIP_CLR_FIELD; ink = DSTRIP_CLR_ACCENT; rim = DSTRIP_CLR_ACCENT; }
      if(f == 2) { face = DSTRIP_CLR_DEL_BG; ink = DSTRIP_CLR_DEL_INK; }
      dirty |= DrawStripBtn(fn, fx, s_dsY + s_dsGearFootY, 68, DSTRIP_CELL,
                            face, ink, rim, DrawStripFootText(f), DrawStripFootTip(f));
   }
   return dirty;
}
//--- purge every gear object (gear shut).
bool DrawStripGearPurge()
{
   bool dirty = false;
   for(int t = 0; t < 4; t++)
      if(ObjectFind(0, DrawStripGearTabName(t)) >= 0)
      { ObjectDelete(0, DrawStripGearTabName(t)); dirty = true; }
   for(int g = 0; g < DSTRIP_GRID_MAX; g++)
   {
      if(ObjectFind(0, DrawStripGridName(g)) >= 0)
      { ObjectDelete(0, DrawStripGridName(g)); dirty = true; }
      if(ObjectFind(0, DrawStripGridIconName(g)) >= 0)
      { ObjectDelete(0, DrawStripGridIconName(g)); dirty = true; }
   }
   for(int r = 0; r < DSTRIP_GLIST_MAX; r++)
   {
      if(ObjectFind(0, DrawStripRowName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowIconName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowIconName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowLabelName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowLabelName(r)); dirty = true; }
   }
   for(int f = 0; f < 4; f++)
      if(ObjectFind(0, DrawStripFootName(f)) >= 0)
      { ObjectDelete(0, DrawStripFootName(f)); dirty = true; }
   for(int e = 0; e < 3; e++)
      if(ObjectFind(0, DrawStripEditName(e)) >= 0)
      { ObjectDelete(0, DrawStripEditName(e)); dirty = true; }
   return dirty;
}

//--- ONE painter, called on open and after every tap: reads the held object and
//--- writes only what changed (the guarded-write law of this codebase), and asks
//--- for a repaint only when something really moved (P-DRAW-09d).
void DrawStripPaint()
{
   if(!s_dsOpen || s_dsObj == "") return;
   if(s_dsKind == DK_NONE || ObjectFind(0, s_dsObj) < 0) { DrawStripClose(); return; }
   // P-DRAW-08c: the strip is the indicator's surface, so the indicator's own
   // hide-all (the F key) hides it too — a toolbar left floating over a chart the
   // user just muted is the same complaint as a label that stays lit.
   if(IsIndicatorHidden()) { DrawStripClose(); return; }
   // P-DRAW-08f: and a drawing the user put away ON THIS TIMEFRAME (the terminal's
   // own "hide on this period", which is OBJPROP_TIMEFRAMES) must not leave a
   // toolbar floating over nothing — the strip serves what is on screen.
   if((long)ObjectGetInteger(0, s_dsObj, OBJPROP_TIMEFRAMES) == OBJ_NO_PERIODS)
   { DrawStripClose(); return; }
   s_dsN = DrawStripQuickCount(s_dsKind);
   bool dirty = false;

   //--- the plate: created once, guarded after (X, Y, W, H all drift).
   string bg = DrawStripBgName();
   if(ObjectFind(0, bg) < 0)
   {
      if(!ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'16,18,24');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, DSTRIP_CLR_LINE);
      ObjectSetInteger(0, bg, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER, Z_STRIP);
      dirty = true;
   }
   dirty |= DrawStripSetInt(bg, OBJPROP_XDISTANCE, s_dsX);
   dirty |= DrawStripSetInt(bg, OBJPROP_YDISTANCE, s_dsY);
   dirty |= DrawStripSetInt(bg, OBJPROP_XSIZE, s_dsW);
   dirty |= DrawStripSetInt(bg, OBJPROP_YSIZE, s_dsH);

   int rowY = s_dsY + DSTRIP_PAD;
   //--- grip (drag) + badge (kind xN, info only).
   string hg = DrawStripGripName();
   string tipGrip = "Drag to move the strip";
   dirty |= DrawStripBtn(hg, s_dsX + DSTRIP_PAD, rowY, DSTRIP_CELL, DSTRIP_CELL,
                         DSTRIP_CLR_CARD, DSTRIP_CLR_LABEL, DSTRIP_CLR_LINE, "", tipGrip);
   dirty |= DrawStripFace(DrawStripGripIconName(), s_dsX + DSTRIP_PAD, rowY,
                          DSTRIP_CELL, DSTRIP_CELL, "::Files\\Icons\\bk_grip.bmp", tipGrip);
   string badgeTip = "This toolbar serves " + DrawStripTitle() +
                     " — right-click a drawing to bring it up, click away to dismiss" +
                     DrawStripTipScope();
   dirty |= DrawStripLbl(DrawStripBadgeName(),
                         s_dsX + DSTRIP_PAD + DSTRIP_CELL + DSTRIP_GAP, rowY,
                         DrawStripTitle(), DSTRIP_CLR_TITLE, badgeTip);

   //--- quick icon cells (icon-only; the colour cell is a swatch, no raster).
   for(int i = 0; i < DSTRIP_MAX_SLOTS; i++)
   {
      string on = DrawStripObjName(i);
      string ic = DrawStripIconName(i);
      bool live = (i < s_dsN);
      int slot = live ? DrawStripQuickSlotAt(s_dsKind, i) : -1;
      if(!live || slot < 0)
      {
         if(ObjectFind(0, on) >= 0) { ObjectDelete(0, on); dirty = true; }
         if(ObjectFind(0, ic) >= 0) { ObjectDelete(0, ic); dirty = true; }
         continue;
      }
      int x = s_dsX + s_dsCX[i];
      string res = DrawStripIconRes(slot, s_dsObj);
      string tip = DrawStripSlotTip(s_dsKind, slot, s_dsObj);
      color face = DSTRIP_CLR_CARD, ink = DSTRIP_CLR_LABEL, rim = DSTRIP_CLR_LINE;
      if(slot == DRAW_SLOT_COLOR)
      {
         face = (color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR);
         ink = DrawStripInkOn(face);
      }
      else if(DrawStripSlotOn(slot, s_dsObj))
      {
         face = DSTRIP_CLR_ACCENT;   // ON toggle: gold face + dark-ink twin raster
         ink = DSTRIP_CLR_ACCENTT;
      }
      if(DrawStripHasPicker(slot))
         rim = (s_dsPicker == slot) ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_PICK;
      dirty |= DrawStripBtn(on, x, rowY, DSTRIP_CELL, DSTRIP_CELL, face, ink, rim, "", tip);
      dirty |= DrawStripFace(ic, x, rowY, DSTRIP_CELL, DSTRIP_CELL, res, tip);
   }

   //--- chrome actions: more / gear / pin / del.
   for(int a = 0; a < DSTRIP_ACT_N; a++)
   {
      string an = DrawStripActName(a), ai = DrawStripActIconName(a);
      int x = s_dsX + DrawStripActX(a);
      string tip = DrawStripActTip(a);
      color face = DSTRIP_CLR_CARD, ink = DSTRIP_CLR_LABEL, rim = DSTRIP_CLR_LINE;
      if(a == DSTRIP_ACT_DEL) { face = DSTRIP_CLR_DEL_BG; ink = DSTRIP_CLR_DEL_INK; }
      if(a == DSTRIP_ACT_PIN && s_dsPinned) rim = DSTRIP_CLR_ACCENT;
      if(a == DSTRIP_ACT_MORE && s_dsPicker == DSTRIP_MORE) rim = DSTRIP_CLR_ACCENT;
      else if(a == DSTRIP_ACT_MORE) rim = DSTRIP_CLR_PICK;
      if(a == DSTRIP_ACT_GEAR && s_dsGear != 0) rim = DSTRIP_CLR_ACCENT;
      else if(a == DSTRIP_ACT_GEAR) rim = DSTRIP_CLR_PICK;
      dirty |= DrawStripBtn(an, x, rowY, DSTRIP_CELL, DSTRIP_CELL, face, ink, rim, "", tip);
      dirty |= DrawStripFace(ai, x, rowY, DSTRIP_CELL, DSTRIP_CELL, DrawStripActRes(a), tip);
   }

   //--- popover block (ONE at a time).
   int contentW = s_dsW - 2 * DSTRIP_PAD;
   if(s_dsPicker == DRAW_SLOT_COLOR)
   {
      for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
         string pn = DrawStripPickName(r);
         if(r >= s_dsPN)
         {
            if(ObjectFind(0, pn) >= 0) { ObjectDelete(0, pn); dirty = true; }
            continue;
         }
         color pc = DrawStripPickColor(s_dsPicker, r);
         bool cur = DrawStripPickIsCur(s_dsObj, s_dsKind, s_dsPicker, r);
         int px = s_dsX + DSTRIP_PAD + (r % 8) * (DSTRIP_CELL + DSTRIP_GAP);
         int py = s_dsY + s_dsPY[r];
         string tip = "Colour: " + DrawStripColorLabel(pc) + " — tap to apply" + DrawStripTipScope();
         dirty |= DrawStripBtn(pn, px, py, DSTRIP_CELL, DSTRIP_CELL, pc, DrawStripInkOn(pc),
                               cur ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_LINE, "", tip);
      }
   }
   else if(s_dsPicker != DSTRIP_PICK_NONE)
   {
      for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
         string pn = DrawStripPickName(r), pi = DrawStripPickIconName(r),
                pt = DrawStripPickLabelName(r);
         if(r >= s_dsPN)
         {
            if(ObjectFind(0, pn) >= 0) { ObjectDelete(0, pn); dirty = true; }
            if(ObjectFind(0, pi) >= 0) { ObjectDelete(0, pi); dirty = true; }
            if(ObjectFind(0, pt) >= 0) { ObjectDelete(0, pt); dirty = true; }
            continue;
         }
         int py = s_dsY + s_dsPY[r];
         int px = s_dsX + DSTRIP_PAD;
         bool cur = DrawStripPopRowIsCur(r);
         string res = DrawStripPopRowRes(r);
         string txt = DrawStripPopRowText(r);
         string tip = DrawStripPopRowTip(r);
         bool accent = cur;
         bool dimmed = (s_dsPicker == DSTRIP_MORE && s_dsMoreKind[r] == DSTRIP_MK_UNDO && !s_duValid);
         color face = accent ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_CARD;
         color ink = accent ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL;
         if(s_dsPicker == DSTRIP_MORE && s_dsMoreKind[r] == DSTRIP_MK_APPLYALL)
         { face = DSTRIP_CLR_FIELD; ink = DSTRIP_CLR_ACCENT; }
         if(dimmed) { face = DSTRIP_CLR_FIELD; ink = DSTRIP_CLR_TITLE; }
         dirty |= DrawStripBtn(pn, px, py, contentW, DSTRIP_CELL, face, ink, DSTRIP_CLR_LINE, "", tip);
         dirty |= DrawStripFace(pi, px + 2, py, DSTRIP_CELL, DSTRIP_CELL, res, tip);
         dirty |= DrawStripLbl(pt, px + DSTRIP_CELL + 4, py,
                               PnlFit(txt, 8, contentW - DSTRIP_CELL - 8), ink, tip);
      }
   }
   else
   {
      for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
         bool gone = false;
         if(ObjectFind(0, DrawStripPickName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickName(r)); gone = true; }
         if(ObjectFind(0, DrawStripPickIconName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickIconName(r)); gone = true; }
         if(ObjectFind(0, DrawStripPickLabelName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickLabelName(r)); gone = true; }
         if(gone) dirty = true;
      }
   }

   //--- gear panel.
   if(s_dsGear != 0)
      dirty |= DrawStripGearPaint(contentW);
   else
      dirty |= DrawStripGearPurge();

   if(dirty) ChartRedraw();
}

//--- OPEN AT CURSOR (P-DRAW-13, preview parity): the trigger's press point
//--- answers where, clamped like the preview's openStripAt (+12, +12, 4px
//--- margins). OPEN (anchor-0) is the fallback with no cursor in hand.
bool DrawStripOpenAt(const string name, const int mx, const int my)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;
   // P-DRAW-08c: opening the SAME object again is a RE-ANCHOR, not a no-op.
   int keepPicker = s_dsPicker, keepGear = s_dsGear;
   bool keepPin = s_dsPinned;
   bool ride = (s_dsOpen && s_dsObj == name);
   bool keepManual = ride ? s_dsManual : (mx >= 0);
   int keepDX = 0, keepDY = 0;
   if(ride) { keepDX = s_dsX - s_dsAX; keepDY = s_dsY - s_dsAY; }
   DrawStripClose();
   // P-DRAW-09b: THE GROUP IS TAKEN HERE, ONCE, and AFTER the close (a close
   // drops the group, because a group belongs to an open strip). The terminal's
   // own selection is the user's statement of "these", and an open is the only
   // moment it can legitimately change — a live read would walk the object list
   // on a stream, and a group that shifted mid-edit is worse than a stale one.
   DrawSelSnapshot(name);
   int ax = 0, ay = 0;
   if(!DrawAnchorXY(name, 0, ax, ay)) return false;
   s_dsKind = k;
   s_dsObj = name;
   s_dsOpen = true;
   s_dsManual = keepManual;
   s_dsPicker = DSTRIP_PICK_NONE;
   if((keepPicker != DSTRIP_PICK_NONE) &&
      (keepPicker == DSTRIP_MORE || DrawStripHasPicker(keepPicker)))
      s_dsPicker = keepPicker;
   s_dsGear = 0;
   if(keepGear != 0) s_dsGear = keepGear;
   s_dsPinned = keepPin;
   s_dsN = DrawStripQuickCount(k);
   DrawStripLayout();
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   if(s_dsManual)
   {
      if(keepDX != 0 || keepDY != 0)   // a ride: keep the hand's offset
      { s_dsX = ax + keepDX; s_dsY = ay + keepDY; }
      else                             // a fresh cursor opening: beside the press
      { s_dsX = mx + 12; s_dsY = my + 12; }
   }
   else
   {
      s_dsX = ax - s_dsW / 2;
      s_dsY = ay - s_dsH - 18;
      if(s_dsY < 4) s_dsY = ay + 18;
   }
   if(s_dsX < 4) s_dsX = 4;
   if(s_dsY < 4) s_dsY = 4;
   if(s_dsX > cw - s_dsW - 4) s_dsX = cw - s_dsW - 4;
   if(s_dsY > ch - s_dsH - 4) s_dsY = ch - s_dsH - 4;
   s_dsAX = ax; s_dsAY = ay;
   DrawStripPaint();
   return true;
}
bool DrawStripOpen(const string name)
{
   return DrawStripOpenAt(name, -1, -1);   // anchor placement (mx < 0)
}

//--- P-DRAW-09b: ONE write for a value, delivered to the WHOLE group. The
//--- learning half lives in `DrawSlotWrite` (P-DRAW-01c), so every member and the
//--- kind's memory move together — and the group is pruned first, because a
//--- member another gesture deleted is not a name to write. Every caller pushes
//--- undo FIRST (single-step looks).
int DrawStripWriteValue(const int slot, const double v)
{
   DrawSelPrune();
   int n = DrawSelCount();
   if(n <= 0)
   {
      if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return 0;
      return (DrawSlotWrite(s_dsObj, slot, v) ? 1 : 0);
   }
   int done = 0;
   for(int i = 0; i < n; i++)
   {
      string nm = DrawSelAt(i);
      if(nm == "" || ObjectFind(0, nm) < 0) continue;
      if(DrawSlotWrite(nm, slot, v)) done++;
   }
   return done;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — SINGLE-STEP UNDO. The pre-mutation looks of the group (capped),
// the held drawing's level set, and a duplicate's copy name. Every mutating
// path pushes FIRST; undo pops once. Trash is not undoable (no undelete).
// ══════════════════════════════════════════════════════════════════════════
void DrawStripUndoLook(const string nm, const int i)
{
   s_duName[i] = nm;
   s_duClr[i] = (color)(int)DrawSlotRead(nm, DRAW_SLOT_COLOR);
   s_duW[i] = (int)DrawSlotRead(nm, DRAW_SLOT_WIDTH);
   s_duSt[i] = (int)DrawSlotRead(nm, DRAW_SLOT_STYLE);
   s_duFill[i] = (DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5 ? 1 : 0);
   s_duRay[i] = (int)DrawSlotRead(nm, DRAW_SLOT_RAY);
   s_duFont[i] = (int)DrawSlotRead(nm, DRAW_SLOT_FONT);
   s_duGlyph[i] = (int)DrawSlotRead(nm, DRAW_SLOT_GLYPH);
   s_duBack[i] = (DrawSlotRead(nm, DRAW_SLOT_BACK) > 0.5 ? 1 : 0);
}
void DrawStripUndoPush()
{
   DrawSelPrune();
   s_duN = 0;
   int n = DrawSelCount();
   if(n <= 0 && s_dsObj != "" && ObjectFind(0, s_dsObj) >= 0)
   {
      DrawStripUndoLook(s_dsObj, 0);
      s_duN = 1;
   }
   else
   {
      for(int i = 0; i < n && s_duN < DSTRIP_UNDO_MAX; i++)
      {
         string nm = DrawSelAt(i);
         if(nm == "" || ObjectFind(0, nm) < 0) continue;
         DrawStripUndoLook(nm, s_duN);
         s_duN++;
      }
   }
   s_duLvN = 0;
   if(s_dsObj != "" && ObjectFind(0, s_dsObj) >= 0 && DrawKindHasLevels(s_dsKind))
   {
      int nl = DrawLevelCount(s_dsObj);
      for(int l = 0; l < nl && s_duLvN < DSTRIP_UNDO_LV; l++)
      {
         s_duLvV[s_duLvN] = DrawLevelValue(s_dsObj, l);
         s_duLvC[s_duLvN] = (color)(int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELCOLOR, l);
         s_duLvW[s_duLvN] = (int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELWIDTH, l);
         s_duLvS[s_duLvN] = (int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELSTYLE, l);
         s_duLvN++;
      }
   }
   s_duCopy = "";
   s_duValid = true;
}
bool DrawStripUndoPop()
{
   if(!s_duValid) return false;
   if(s_duCopy != "")
   {
      if(ObjectFind(0, s_duCopy) >= 0) ObjectDelete(0, s_duCopy);
      if(s_duCopy == s_dsObj) { DrawStripClose(); ChartRedraw(); s_duValid = false; return true; }
      s_duValid = false;
      DrawStripPaint();
      ChartRedraw();
      return true;
   }
   for(int i = 0; i < s_duN; i++)
   {
      string nm = s_duName[i];
      if(nm == "" || ObjectFind(0, nm) < 0) continue;
      DrawSlotWrite(nm, DRAW_SLOT_COLOR, (double)(int)s_duClr[i]);
      DrawSlotWrite(nm, DRAW_SLOT_WIDTH, (double)s_duW[i]);
      DrawSlotWrite(nm, DRAW_SLOT_STYLE, (double)s_duSt[i]);
      if(DrawSlotAvailable(DrawKindOf(nm), DRAW_SLOT_FILL))
         DrawSlotWrite(nm, DRAW_SLOT_FILL, (double)s_duFill[i]);
      if(DrawSlotAvailable(DrawKindOf(nm), DRAW_SLOT_RAY))
         DrawSlotWrite(nm, DRAW_SLOT_RAY, (double)s_duRay[i]);
      if(DrawSlotAvailable(DrawKindOf(nm), DRAW_SLOT_FONT))
         DrawSlotWrite(nm, DRAW_SLOT_FONT, (double)s_duFont[i]);
      if(DrawSlotAvailable(DrawKindOf(nm), DRAW_SLOT_GLYPH))
         DrawSlotWrite(nm, DRAW_SLOT_GLYPH, (double)s_duGlyph[i]);
      DrawSlotWrite(nm, DRAW_SLOT_BACK, (double)s_duBack[i]);
   }
   if(s_duLvN > 0 && s_dsObj != "" && ObjectFind(0, s_dsObj) >= 0 && DrawKindHasLevels(s_dsKind))
   {
      ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELS, s_duLvN);
      for(int l = 0; l < s_duLvN; l++)
      {
         ObjectSetDouble(0, s_dsObj, OBJPROP_LEVELVALUE, l, s_duLvV[l]);
         ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELCOLOR, l, s_duLvC[l]);
         ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELWIDTH, l, s_duLvW[l]);
         ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELSTYLE, l, s_duLvS[l]);
      }
   }
   s_duValid = false;
   DrawStripPaint();
   ChartRedraw();
   return true;
}
//--- a whole LOOK onto the group (template rows, more + gear): undoable, learned.
bool DrawStripPresetApplyGroup(const int row)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   EDrawKind k = s_dsKind;
   if(k == DK_NONE) return false;
   int n = DrawPresetCount(k);
   if(row < 0 || row >= n) return false;
   DrawStripUndoPush();
   DrawSelPrune();
   int gn = DrawSelCount();
   if(gn > 0) { for(int j = 0; j < gn; j++) DrawPresetApply(DrawSelAt(j), row); }
   else DrawPresetApply(s_dsObj, row);
   s_dsTpl[k] = row;
   return true;
}
//--- "New <kind> wears this look": learn the chart's current look into the
//--- kind's memory WITHOUT changing the drawing (same-value writes).
void DrawStripLearnCurrent()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return;
   EDrawKind k = s_dsKind;
   if(k == DK_NONE) return;
   for(int s = 0; s < DRAW_SLOT_N; s++)
   {
      if(s == DRAW_SLOT_MORE || s == DRAW_SLOT_LOCK || s == DRAW_SLOT_BACK) continue;
      if(!DrawSlotAvailable(k, s)) continue;
      DrawSlotWrite(s_dsObj, s, DrawSlotRead(s_dsObj, s));
   }
}

//--- P-DRAW-11: APPLY one picker row — through the group fan-out (P-DRAW-09b),
//--- learning the look for the next drawing of the kind (P-DRAW-01c). Placed
//--- here (after DrawStripWriteValue) because MQL4 is define-before-use.
bool DrawStripPickApply(const int slot, const int row)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   EDrawKind k = s_dsKind;
   if(k == DK_NONE) return false;
   if(slot == DRAW_SLOT_COLOR)
   {
      color c = DrawStripPickColor(slot, row);
      if(c == clrNONE) return false;
      DrawStripRecentPush(c);
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_COLOR, (double)(int)c);
      return true;
   }
   if(slot == DRAW_SLOT_WIDTH)
   {
      if(row < 0 || row > 4) return false;
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_WIDTH, (double)(row + 1));
      return true;
   }
   if(slot == DRAW_SLOT_STYLE)
   {
      if(row < 0 || row > 4) return false;
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_STYLE, (double)row);
      return true;
   }
   if(slot == DRAW_SLOT_RAY)
   {
      if(row < 0 || row > 3) return false;
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_RAY, (double)row);
      return true;
   }
   if(slot == DRAW_SLOT_FONT)
   {
      if(row < 0 || row >= DrawStripFontCount()) return false;
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_FONT, (double)DrawStripFontAt(row));
      return true;
   }
   if(slot == DRAW_SLOT_GLYPH)
   {
      if(row < 0 || row >= DrawStripGlyphCount()) return false;
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_GLYPH, (double)DrawStripGlyphAt(row));
      return true;
   }
   return false;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — LEVEL MEMBERSHIP WRITES (held drawing only) + DUPLICATE.
// ══════════════════════════════════════════════════════════════════════════
bool DrawStripLevelsRewrite(double &vals[], color &clrs[], int &wds[], int &sts[], const int n)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   if(!DrawKindHasLevels(s_dsKind)) return false;
   if(n < 0 || n > 32) return false;
   ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELS, n);
   for(int i = 0; i < n; i++)
   {
      ObjectSetDouble(0, s_dsObj, OBJPROP_LEVELVALUE, i, vals[i]);
      ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELCOLOR, i, clrs[i]);
      ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELWIDTH, i, wds[i]);
      ObjectSetInteger(0, s_dsObj, OBJPROP_LEVELSTYLE, i, sts[i]);
   }
   return true;
}
void DrawStripLevelsCollect(double &vals[], color &clrs[], int &wds[], int &sts[], int &n)
{
   n = 0;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return;
   int cur = DrawLevelCount(s_dsObj);
   for(int i = 0; i < cur && n < 32; i++)
   {
      double v = DrawLevelValue(s_dsObj, i);
      if(!MathIsValidNumber(v)) continue;
      vals[n] = v;
      clrs[n] = (color)(int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELCOLOR, i);
      wds[n] = (int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELWIDTH, i);
      sts[n] = (int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELSTYLE, i);
      n++;
   }
}
//--- toggle one membership value (multi-stay: the editor does NOT close).
bool DrawStripLevelsToggle(const double v)
{
   if(!MathIsValidNumber(v)) return false;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   DrawStripUndoPush();
   double vals[32]; color clrs[32]; int wds[32]; int sts[32]; int n = 0;
   DrawStripLevelsCollect(vals, clrs, wds, sts, n);
   int at = -1;
   for(int i = 0; i < n; i++)
      if(MathAbs(vals[i] - v) < 0.000001) { at = i; break; }
   if(at >= 0)
   {
      for(int j = at; j < n - 1; j++)
      { vals[j] = vals[j + 1]; clrs[j] = clrs[j + 1]; wds[j] = wds[j + 1]; sts[j] = sts[j + 1]; }
      n--;
   }
   else
   {
      if(n >= 32) return false;
      vals[n] = v;
      clrs[n] = (color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR);
      wds[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
      sts[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE);
      n++;
   }
   return DrawStripLevelsRewrite(vals, clrs, wds, sts, n);
}
//--- All / None for the common nine.
bool DrawStripLevelsSetAll(const bool on)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   if(!DrawKindHasLevels(s_dsKind)) return false;
   DrawStripUndoPush();
   if(!on)
   {
      double vals[32]; color clrs[32]; int wds[32]; int sts[32];
      int n = 0;
      return DrawStripLevelsRewrite(vals, clrs, wds, sts, n);
   }
   double vals2[32]; color clrs2[32]; int wds2[32]; int sts2[32];
   int n2 = 0;
   color c = (color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR);
   int w = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
   int st = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE);
   for(int i = 0; i < DrawStripLevelCommonCount(); i++)
   {
      vals2[n2] = DrawStripLevelCommon(i);
      clrs2[n2] = c; wds2[n2] = w; sts2[n2] = st;
      n2++;
   }
   return DrawStripLevelsRewrite(vals2, clrs2, wds2, sts2, n2);
}
//--- DUPLICATE: a true clone beside itself (anchors + look + levels), the copy
//--- selected and served. Time anchors step one chart bar so the two do not sit
//--- exactly atop each other. Undoable (the copy is deleted).
bool DrawStripDuplicate()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   int type = DrawObjectType(s_dsObj);
   if(type < 0) return false;
   DrawStripUndoPush();
   string base = s_dsObj + "_c";
   string nm = base;
   for(int i = 2; i < 100; i++)
   {
      if(ObjectFind(0, nm) < 0) break;
      nm = base + IntegerToString(i);
   }
   if(ObjectFind(0, nm) >= 0) return false;
   datetime t0 = (datetime)ObjectGetInteger(0, s_dsObj, OBJPROP_TIME, 0);
   double p0 = ObjectGetDouble(0, s_dsObj, OBJPROP_PRICE, 0);
   if(t0 <= 0 || !(p0 > 0.0)) return false;
   if(!ObjectCreate(0, nm, type, 0, t0, p0)) return false;
   long step = (long)Period() * 60;
   if(step <= 0) step = 60;
   for(int a = 0; a < 3; a++)
   {
      datetime t = (datetime)ObjectGetInteger(0, s_dsObj, OBJPROP_TIME, a);
      double p = ObjectGetDouble(0, s_dsObj, OBJPROP_PRICE, a);
      if(t > 0) ObjectSetInteger(0, nm, OBJPROP_TIME, a, t + step);
      if(p > 0.0) ObjectSetDouble(0, nm, OBJPROP_PRICE, a, p);
   }
   ObjectSetInteger(0, nm, OBJPROP_COLOR, ObjectGetInteger(0, s_dsObj, OBJPROP_COLOR));
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, ObjectGetInteger(0, s_dsObj, OBJPROP_WIDTH));
   ObjectSetInteger(0, nm, OBJPROP_STYLE, ObjectGetInteger(0, s_dsObj, OBJPROP_STYLE));
   ObjectSetInteger(0, nm, OBJPROP_FILL, ObjectGetInteger(0, s_dsObj, OBJPROP_FILL));
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, ObjectGetInteger(0, s_dsObj, OBJPROP_RAY_RIGHT));
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, ObjectGetInteger(0, s_dsObj, OBJPROP_RAY_LEFT));
   ObjectSetInteger(0, nm, OBJPROP_BACK, ObjectGetInteger(0, s_dsObj, OBJPROP_BACK));
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTED, false);
   if(DrawKindOf(nm) == DK_TEXT)
   {
      ObjectSetString(0, nm, OBJPROP_TEXT, ObjectGetString(0, s_dsObj, OBJPROP_TEXT));
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, ObjectGetInteger(0, s_dsObj, OBJPROP_FONTSIZE));
      ObjectSetString(0, nm, OBJPROP_FONT, ObjectGetString(0, s_dsObj, OBJPROP_FONT));
   }
   if(DrawKindOf(nm) == DK_ARROW)
      ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, ObjectGetInteger(0, s_dsObj, OBJPROP_ARROWCODE));
   ObjectSetString(0, nm, OBJPROP_TEXT,
                   ObjectGetString(0, s_dsObj, OBJPROP_TEXT));
   if(DrawKindHasLevels(s_dsKind))
   {
      double vals[32]; color clrs[32]; int wds[32]; int sts[32]; int n = 0;
      DrawStripLevelsCollect(vals, clrs, wds, sts, n);
      ObjectSetInteger(0, nm, OBJPROP_LEVELS, n);
      for(int l = 0; l < n; l++)
      {
         ObjectSetDouble(0, nm, OBJPROP_LEVELVALUE, l, vals[l]);
         ObjectSetInteger(0, nm, OBJPROP_LEVELCOLOR, l, clrs[l]);
         ObjectSetInteger(0, nm, OBJPROP_LEVELWIDTH, l, wds[l]);
         ObjectSetInteger(0, nm, OBJPROP_LEVELSTYLE, l, sts[l]);
         ObjectSetString(0, nm, OBJPROP_LEVELTEXT, l,
                         ObjectGetString(0, s_dsObj, OBJPROP_LEVELTEXT, l));
      }
   }
   s_duCopy = nm;
   ObjectSetInteger(0, nm, OBJPROP_SELECTED, true);
   DrawStripOpen(nm);
   ChartRedraw();
   return true;
}

//--- P-DRAW-13 — A TAP OPENS, IT NEVER GUESSES. Quick value cells toggle their
//--- popover (BaseKnot's dropdown contract); toggles flip at once; chrome
//--- actions fire at once. No branch here mutates a value off a value cell.
bool DrawStripTap(const int idx)
{
   if(!s_dsOpen || s_dsObj == "" || idx < 0 || idx >= DSTRIP_MAX_SLOTS) return false;
   if(idx >= s_dsN) return false;
   EDrawKind k = s_dsKind;
   if(k == DK_NONE) { DrawStripClose(); return true; }
   int slot = DrawStripQuickSlotAt(k, idx);
   if(slot < 0) return true;
   if(DrawStripHasPicker(slot))
   {
      DrawStripGearClose();
      if(s_dsPicker == slot) DrawStripClosePicker();
      else s_dsPicker = slot;
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(DrawStripIsToggle(slot))
   {
      DrawStripUndoPush();
      DrawStripWriteValue(slot, (DrawSlotRead(s_dsObj, slot) > 0.5) ? 0.0 : 1.0);
      // P-DRAW-09b: locking is the one tap that can end the group's usefulness
      // (a locked member cannot be grabbed again by accident), so the strip
      // loses nothing here — it stays, and one more tap frees it.
      DrawStripPaint();
      return true;
   }
   return true;
}
//--- chrome: more / gear / pin / del.
bool DrawStripActTap(const int a)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(a == DSTRIP_ACT_MORE)
   {
      DrawStripGearClose();
      if(s_dsPicker == DSTRIP_MORE) DrawStripClosePicker();
      else s_dsPicker = DSTRIP_MORE;
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(a == DSTRIP_ACT_GEAR)
   {
      DrawStripClosePicker();
      if(s_dsGear != 0) DrawStripGearClose();
      else s_dsGear = DSTRIP_GEAR_STYLE;
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(a == DSTRIP_ACT_PIN)
   {
      s_dsPinned = !s_dsPinned;
      DrawStripPaint();
      return true;
   }
   if(a == DSTRIP_ACT_DEL) { DrawStripFireDelete(); return true; }
   return true;
}
//--- group delete from the strip (P-DRAW-08d). Not undoable: MT4 has no undelete.
void DrawStripFireDelete()
{
   if(!s_dsOpen) return;
   DrawSelPrune();
   int n = DrawSelCount();
   if(n > 0) { for(int j = 0; j < n; j++) ObjectDelete(0, DrawSelAt(j)); }
   else if(s_dsObj != "") ObjectDelete(0, s_dsObj);
   DrawStripClose();
   ChartRedraw();
}
//--- P-DRAW-11 — A PICK APPLIES AND SHUTS (levels: multi-stay). The caller passes
//--- the popover row; the row is validated against the open popover's own count.
bool DrawStripPickTap(const int row)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(s_dsPicker == DSTRIP_PICK_NONE) return false;
   if(row < 0 || row >= s_dsPN) return false;
   if(s_dsPicker == DSTRIP_MORE) return DrawStripMoreTap(row);
   if(s_dsPicker == DSTRIP_SLOT_LEVELS)
   {
      double v = DrawStripGearLevelAt(row);
      if(!MathIsValidNumber(v)) return false;
      DrawStripLevelsToggle(v);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   DrawStripPickApply(s_dsPicker, row);
   DrawStripClosePicker();
   DrawStripLayout();
   DrawStripPaint();
   return true;
}
//--- more-popover rows.
bool DrawStripMoreTap(const int row)
{
   if(row < 0 || row >= s_dsPN) return false;
   int kind = s_dsMoreKind[row], arg = s_dsMoreArg[row];
   if(kind == DSTRIP_MK_APPLYALL)
   {
      // THE CONTROL MT4 DOES NOT HAVE: this look, on every drawing of this tool.
      DrawStyleApplyToKind(s_dsObj);
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_PRESET)
   {
      DrawStripPresetApplyGroup(arg);
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_SAVE)
   {
      // the look the user just built becomes one of THEIR templates, and the file
      // is written in the same act (P-DRAW-08b) — a save that is not persisted is
      // a template they lose on the next attach.
      DrawPresetCaptureAndSave(s_dsObj, "");
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_DUPE) return DrawStripDuplicate();
   if(kind == DSTRIP_MK_UNDO)
   {
      if(!s_duValid) return true;
      DrawStripUndoPop();
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_SLOT)
   {
      s_dsPicker = arg;   // overflow value slot: its grid replaces more
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   return true;
}
//--- gear grid cells (swatches + chips stay in the panel).
bool DrawStripGridTap(const int g)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(g < 0 || g >= s_dsGGN) return false;
   if(s_dsGGKind[g] == 0)
   {
      color c = s_dsGGC[g];
      DrawStripRecentPush(c);
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_COLOR, (double)(int)c);
   }
   else
      DrawStripPickApply(s_dsGGSlot[g], s_dsGGArg[g]);
   DrawStripPaint();
   return true;
}
//--- gear list rows.
bool DrawStripGearRowTap(const int r)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(r < 0 || r >= s_dsGRN) return false;
   int kind = s_dsGRKind[r], arg = s_dsGRArg[r];
   if(kind == 1)
   {
      DrawStripUndoPush();
      DrawStripWriteValue(arg, (DrawSlotRead(s_dsObj, arg) > 0.5) ? 0.0 : 1.0);
      DrawStripPaint();
      return true;
   }
   if(kind == 2)
   {
      DrawStripPresetApplyGroup(arg);
      DrawStripPaint();
      return true;
   }
   if(kind == 3)
   {
      DrawPresetCaptureAndSave(s_dsObj, "");
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == 4)
   {
      double v = DrawStripGearLevelAt(arg);
      if(!MathIsValidNumber(v)) return false;
      DrawStripLevelsToggle(v);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == 5)
   {
      if(arg == 2)
      {
         for(int s = 0; s < DRAW_SLOT_N; s++) s_dsVis[s_dsKind][s] = true;
      }
      else DrawStripLevelsSetAll(arg == 0);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == 6)
   {
      int seat = (arg == DRAW_SLOT_MORE) ? DRAW_SLOT_MORE : arg;
      DrawStripVisInit();
      s_dsVis[s_dsKind][seat] = !s_dsVis[s_dsKind][seat];
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == 7)
   {
      DrawStripLearnCurrent();
      DrawStripPaint();
      return true;
   }
   if(kind == 8)
   {
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_GLYPH, (double)DrawStripGlyphAt(arg % 256));
      DrawStripPaint();
      return true;
   }
   return true;
}
//--- gear foot: All / Copy / Del / Close.
bool DrawStripFootTap(const int f)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(f == 0)
   {
      DrawStyleApplyToKind(s_dsObj);
      DrawStripPaint();
      return true;
   }
   if(f == 1) return DrawStripDuplicate();
   if(f == 2) { DrawStripFireDelete(); return true; }
   DrawStripClose();
   ChartRedraw();
   return true;
}
//--- gear tab switch (shuts the popover; one panel at a time).
bool DrawStripGearTabTap(const int t)
{
   if(!s_dsOpen) return false;
   if(t < 0 || t >= s_dsGearTab[0]) return false;
   DrawStripClosePicker();
   int tab = s_dsGearTab[t + 1];
   if(s_dsGear == tab) DrawStripGearClose();
   else s_dsGear = tab;
   DrawStripLayout();
   DrawStripPaint();
   return true;
}
//--- gear edits (ENDEDIT): hex colour, level add, caption. Invalid input keeps
//--- the typed text (paint never re-seeds an existing edit) for another try.
bool DrawStripEditEnd(const int e)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   string nm = DrawStripEditName(e);
   if(ObjectFind(0, nm) < 0) return false;
   string txt = ObjectGetString(0, nm, OBJPROP_TEXT);
   if(e == 0)
   {
      color c;
      if(!DrawStripHexToColor(txt, c)) return true;
      DrawStripRecentPush(c);
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_COLOR, (double)(int)c);
      DrawStripPaint();
      return true;
   }
   if(e == 1)
   {
      string t = txt;
      StringTrimLeft(t); StringTrimRight(t);
      double v = StringToDouble(t);
      if(!MathIsValidNumber(v) || v < -100.0 || v > 500.0) return true;
      if(DrawStripLevelFind(s_dsObj, v) >= 0) return true;
      DrawStripUndoPush();
      double vals[32]; color clrs[32]; int wds[32]; int sts[32]; int n = 0;
      DrawStripLevelsCollect(vals, clrs, wds, sts, n);
      if(n >= 32) return true;
      vals[n] = v;
      clrs[n] = (color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR);
      wds[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
      sts[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE);
      n++;
      DrawStripLevelsRewrite(vals, clrs, wds, sts, n);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(e == 2 && DrawKindOf(s_dsObj) == DK_TEXT)
   {
      ObjectSetString(0, s_dsObj, OBJPROP_TEXT, txt);
      ChartRedraw();
      return true;
   }
   return true;
}
//--- P-DRAW-13: the grip carry. Screen objects only (SELECTABLE=false), so the
//--- terminal never fights the hand and no view lock is needed — the plate is
//--- screen-fixed, a chart scroll moves nothing we own. Stale grabs (a
//--- motionless release emits no MOUSE_MOVE, P-LM-13) die on the next CLICK.
bool DrawStripGripAt(const int mx, const int my)
{
   if(!s_dsOpen) return false;
   return (mx >= s_dsX + DSTRIP_PAD && mx <= s_dsX + DSTRIP_PAD + DSTRIP_CELL &&
           my >= s_dsY + DSTRIP_PAD && my <= s_dsY + DSTRIP_PAD + DSTRIP_CELL);
}
void DrawStripGripRelease() { s_dsGripLive = false; }
void DrawStripGripMove(const int mx, const int my, const bool left)
{
   if(!s_dsOpen) { s_dsGripLive = false; s_dsLeftPrev = left; return; }
   if(left && !s_dsLeftPrev)
   {
      if(DrawStripGripAt(mx, my))
      {
         s_dsGripLive = true;
         s_dsGripDX = mx - s_dsX;
         s_dsGripDY = my - s_dsY;
      }
   }
   if(!left) s_dsGripLive = false;
   s_dsLeftPrev = left;
   if(!s_dsGripLive) return;
   uint now = GetTickCount();
   if(now - s_dsGripMs < DSTRIP_GRIP_MS) return;
   s_dsGripMs = now;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   int nx = mx - s_dsGripDX, ny = my - s_dsGripDY;
   if(nx < 4) nx = 4;
   if(ny < 4) ny = 4;
   if(nx > cw - s_dsW - 4) nx = cw - s_dsW - 4;
   if(ny > ch - s_dsH - 4) ny = ch - s_dsH - 4;
   if(nx == s_dsX && ny == s_dsY) return;
   s_dsX = nx; s_dsY = ny;
   s_dsManual = true;   // the hand placed it: re-anchors keep the offset
   DrawStripPaint();
}

//--- THE EVENT ROUTER. Called from the entry's OnChartEvent tail (Full only):
//--- it sees the button clicks the terminal reports and the clicks that land
//--- anywhere else (which dismiss the strip, TV-style).
bool DrawStripOnEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!s_dsOpen) return false;
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      DrawStripGripRelease();   // a click ends any grip carry (stale-grab net)
      // P-DRAW-11: the plate itself is not a control — a tap on it shuts the
      // open popover (the popover owns the next press, BaseKnot parity) and
      // keeps the strip (and its gear) itself.
      if(sparam == DrawStripBgName())
      {
         if(s_dsPicker != DSTRIP_PICK_NONE)
         {
            DrawStripClosePicker();
            DrawStripLayout();
            DrawStripPaint();
         }
         return true;
      }
      // P-DRAW-10: a cell answers by BOTH of its names — the button (its control)
      // and the icon label (its face), because MT4 gives the click to whichever
      // screen object sits highest under the cursor.
      for(int i = 0; i < DSTRIP_MAX_SLOTS; i++)
      {
         if(sparam == DrawStripObjName(i) || sparam == DrawStripIconName(i))
         { DrawStripTap(i); return true; }
      }
      if(sparam == DrawStripGripName() || sparam == DrawStripGripIconName() ||
         sparam == DrawStripBadgeName()) return true;   // drag / info: no tap
      for(int a = 0; a < DSTRIP_ACT_N; a++)
      {
         if(sparam == DrawStripActName(a) || sparam == DrawStripActIconName(a))
         { DrawStripActTap(a); return true; }
      }
      // popover rows (button, face, label — one tap).
      for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
         if(sparam == DrawStripPickName(r) || sparam == DrawStripPickIconName(r) ||
            sparam == DrawStripPickLabelName(r))
         { DrawStripPickTap(r); return true; }
      }
      // gear tabs, grid cells, rows, foot. Edits take focus for typing.
      for(int t = 0; t < 4; t++)
         if(sparam == DrawStripGearTabName(t)) { DrawStripGearTabTap(t); return true; }
      for(int g = 0; g < DSTRIP_GRID_MAX; g++)
         if(sparam == DrawStripGridName(g) || sparam == DrawStripGridIconName(g))
         { DrawStripGridTap(g); return true; }
      for(int gr = 0; gr < DSTRIP_GLIST_MAX; gr++)
         if(sparam == DrawStripRowName(gr) || sparam == DrawStripRowIconName(gr) ||
            sparam == DrawStripRowLabelName(gr))
         { DrawStripGearRowTap(gr); return true; }
      for(int f = 0; f < 4; f++)
         if(sparam == DrawStripFootName(f)) { DrawStripFootTap(f); return true; }
      for(int e = 0; e < 3; e++)
         if(sparam == DrawStripEditName(e)) return true;
   }
   // P-DRAW-08f: the drawing was deleted from the TERMINAL's own menu (or by the
   // ✕ of another tool). The paint would notice it on the next click, but a
   // toolbar left floating over nothing is exactly the untidy state the user
   // sees first — so the delete closes it in its own event.
   if(id == CHARTEVENT_OBJECT_DELETE)
   {
      if(sparam == s_dsObj) DrawStripClose();
      return false;
   }
   // P-DRAW-08c: the two flows that used to be incomplete from the user's seat —
   //   * the DRAWING WAS MOVED: the strip is anchored to its anchor, so it must
   //     follow it rather than sit over the old spot (a drag re-anchors, and the
   //     same branch covers the terminal's own drag of the object);
   //   * the CHART CHANGED (zoom, scroll, resize): the object's pixels moved, so
   //     the strip re-anchors with them instead of closing on the user's zoom.
   // P-DRAW-08e: the drag channel is the one event that arrives at pointer rate, so
   // it is THROTTLED to the project's own drag cadence (50 ms, the frame budget the
   // custom price line uses) — the strip follows the hand, and a fast drag costs
   // twenty re-anchors a second instead of two hundred.
   // P-DRAW-09d: AND SO IS CHART_CHANGE. A scroll or a zoom is a BURST of the
   // same event (a wheel spin, a drag of the axis), and every one of them was a
   // full re-open — twelve guarded reads and a repaint — on a channel the user
   // drives at pointer rate. The two channels now share ONE throttle, because
   // they are one question: "the object's pixels moved, is it time to re-anchor?"
   if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_CHART_CHANGE)
   {
      uint now = GetTickCount();
      if(now - s_dsAnchorMs < DSTRIP_FOLLOW_MS) return false;
      s_dsAnchorMs = now;
      if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) { DrawStripClose(); return false; }
      if(s_dsGripLive)
      {
         // the hand owns the plate: refresh the anchor, keep the position.
         int gx = 0, gy = 0;
         if(DrawAnchorXY(s_dsObj, 0, gx, gy)) { s_dsAX = gx; s_dsAY = gy; }
         return false;
      }
      DrawStripOpen(s_dsObj);
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
      DrawStripClose();
      ChartRedraw();
      return true;
   }
   // P-DRAW-13: gear edits commit on Enter (ENDEDIT).
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      for(int e = 0; e < 3; e++)
         if(sparam == DrawStripEditName(e)) { DrawStripEditEnd(e); return true; }
      return false;
   }
   if(id == CHARTEVENT_CLICK)
   {
      DrawStripGripRelease();   // motionless releases emit no MOVE (P-LM-13 net)
      // P-DRAW-14/16 — RIGHT-CLICK IS THE TRIGGER and owns the menu's place.
      // The button encoding is the project's own measured one: on CHARTEVENT_CLICK
      // a right button is an "r" in sparam (EventHandlers.mqh:5226,
      // BaseKnotTool.mqh:6881). A right-click on a user drawing opens the strip
      // beside the press (OpenAt, preview parity). The terminal menu cannot pop:
      // it has been off since attach (Take/Give, P-DRAW-16 above). A right-click
      // on the strip itself is owned by the strip (never a self-dismiss); on
      // empty chart it falls through to the dismissal below. A click on the held
      // drawing never dismisses either (every click, not just the first).
      bool right = (StringFind(sparam, "r") >= 0);
      if(right)
      {
         if(DrawStripPointInside((int)lparam, (int)dparam)) return false;
         string hit = DrawObjectAtCached((int)lparam, (int)dparam);
         if(hit != "") { DrawStripOpenAt(hit, (int)lparam, (int)dparam); return true; }
      }
      if(s_dsObj != "" && DrawHitObject(s_dsObj, (int)lparam, (int)dparam)) return false;
      // P-DRAW-13: pin survives outside clicks (only ✕ paths, Del and Esc dismiss).
      if(s_dsPinned) return false;
      if(!DrawStripPointInside((int)lparam, (int)dparam)) DrawStripClose();
   }
   return false;
}

#endif // DRAW_STRIP_MQH
