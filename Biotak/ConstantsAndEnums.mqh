   #ifndef CONSTANTS_AND_ENUMS_MQH
#define CONSTANTS_AND_ENUMS_MQH

#define MAX_LINES 10

// Object naming constants (for cleanup)
#define TH3_PATTERN_PREFIX      "ABCD_Pattern_"
#define TH3_TEMP_PREFIX         "ABCD_Temp_"
#define TH3_TEMP_LINE_PREFIX    "ABCD_Temp_Line_"
// P-LM-01: the leg-measure family (TH3Tool). Its own namespace so the REASON_REMOVE
// teardown can wipe it like every other family this tool creates.
#define TH3_LEG_PREFIX          "LM_"
#define CACHE_TIMEOUT 60

// ══════════════════════════════════════════════════════════════════════════
// P-UI-92 / P-UI-92b: THE TWO HALVES OF ONE RULE — a click on the UI never reaches
// the chart. (1) WHERE: `UIPointerOverSurface()` (BiotakPanels) hit-tests the pixel
// against the UI's own layout — exact, no constant needed. (2) WHOSE: the claim the
// UI publishes for the domain half of the same release (`UIPeekClickClaim` in
// GlobalVariables).
//
// This is the TTL of an UP-ARMED published claim (armed while the button is already
// UP — a drag end, a card opened by a release), i.e. the only form with no press to
// bind to. Long enough to cover the release plus its echo event (the UI's own
// UI_RELEASE_ECHO_MS is 80), short enough that a claim whose click event never arrived
// cannot swallow a later, genuine chart click. The press-bound form carries no clock
// at all — it retires with its own press.
#define UI_CLAIM_TTL_MS  600

// Z LADDER — the ONE owner of every OBJPROP_ZORDER in the project (P-UI-31)
//
// MT4 keeps the SCREEN-SPACE objects (OBJ_LABEL / OBJ_BUTTON / OBJ_BITMAP_LABEL
// / OBJ_EDIT / OBJ_RECTANGLE_LABEL) in one list and paints them in ZORDER
// order; an equal ZORDER falls back to creation order. The same property IS the
// click priority: "when objects are placed one atop another, only one of them
// with the highest priority will receive the CHARTEVENT_CLICK event"
// (docs.mql4.com — Object Properties). Both readings want the same thing here,
// so there is one ladder:
//
//     THE SETTINGS CARD OWNS THE TOP. Nothing the indicator draws may sit over a
//     card, and a click anywhere on a card must reach the card — never the orb,
//     never a hover tip, never a floating box badge. (P-UI-11 is the same rule
//     one level down: a row's caption must not be buried by its own control.)
//
// Three consequences that are NOT obvious:
//   1. The ring menu AND its hover tip sit BELOW the card: the menu is what
//      opens a card, so the card is always the newest surface (the tip is also
//      disarmed while g_UIPanelOpen — see BiotakMenu CircTipOnMove).
//   2. CHART_FOREGROUND is what lifts the panel over the CANDLES
//      (PnlLockForeground); ZORDER alone never raises an object over the bars.
//   3. Never invent a literal at a call site — add a name here, or the audit
//      in tools/zorder-audit.py fails and the ordering stops being provable.
// ══════════════════════════════════════════════════════════════════════════

// ── chart content: zones, level lines, tool dots, boxes — the floor// P-UI-64: the width a picture that DRAWS an edge falls back to when the card's BORDER
// WIDTH still holds the edge-less default (1). A 1px line drawn UNDER a translucent band
// - equal ZORDER, band first, so the band covers half of it - is invisible, which is
// exactly why the combined picture first looked like the filled one. 5 is the row's own
// maximum, i.e. "as visible as the control can make it", and the user can still dial it
// back: the promotion only fires while the width IS the older default.
#define MIDZONE_EDGE_VISIBLE_WIDTH 5

#define Z_CHART_ZONE 0      // zone bodies/borders, Trigger level lines
#define Z_CHART_LINE     1      // Factor level lines (drawn above their zone)
// P-LM-20: the leg metre's handle discs. They must paint ABOVE the measurement
// line they sit on - a line widened for the selection face (LEG_LINE_W_SEL)
// otherwise covers its own discs - and below every tool dot and label. The rung
// was introduced beside the leg metre as `LEG_HANDLE_ZORDER`; it carries its own
// Z_ ladder name now, because the Z ladder IS the paint order the zorder audit
// proves and a rung outside it is a rung nothing can reason about.
#define Z_CHART_LEG_HANDLE 3    // leg-metre handle discs (P-LM-20)
#define Z_CHART_TOOL    10      // TH3 tool dots
#define Z_BOX_RAY       50      // Base/Knot rays
#define Z_BOX_FILL      55      // box fill layer + drag handle
#define Z_BOX_EDGE      56      // box border edges
// P-BK-71 (2026-09-17): THE MARK IS A BOX AGAIN, WITH NO POINTS OF OURS. The carrier
// is MT4's OWN rectangle — moved and selected natively — so no family needs to cover
// or repeat the terminal's markers: the centre cover (P-BK-59/BKDOT-OFF), the resize
// chips (P-BK-61/BKGRIP-OFF) and the trendline points (P-BK-69/BKPOINT-OFF) are all
// retired, and Z_BOX_DOT / Z_BOX_GRIP stay UNUSED rungs. Both NUMBERS stay where they
// are: the ladder is a contract every rung above and below it is measured against,
// and the restore path wants them exactly where the P-BK-59/P-BK-61 notes put them.
// P-BK-59: the box' centre GRIP — a 5x5 SCREEN square in the box' border ink. It is not
// decoration: MetaTrader paints its OWN selection marker (a 2x2 WHITE square) at the centre of
// a SELECTED rectangle and gives the EA no colour for it («توی پس زمینه سفید به خوبی دیده
// نمیشه»). The marker is painted WITH the object, i.e. below every rung above it, so a screen
// object at this rung hides it — above the box art, below the text layer.
#define Z_BOX_DOT       58
// P-BK-61: the resize handles (a screen square on each CORNER of a selected rectangle —
// «یک کلیک چپ میکنم راحت هر طرف که بخوام میکشم اینطوری باشه»). BKMIDGRIP-OFF retired the
// four mid-edge squares (they did not behave: «این وسط‌ها که کار نمیکنن رو بردار»), which
// is also the whole delta for this rung — same family as Z_BOX_DOT above (they are the
// only two screen objects of the box), so they sit on the same rung band: above the box' art,
// below the text layer, and — like every rung here — under the card/strip rungs far above.
#define Z_BOX_GRIP      59
#define Z_BOX_INFO      60      // the base note's PLATE — P-BK-86: the note itself is a SCREEN object now and rides Z_CHART_LABEL, so this rung is what its background bar wears (under the ink, above the chart art). P-BK-56 left it free for a one-line restore; P-BK-86 is the second owner of the same number.
#define Z_BOX_TEXT      61      // box user text
// P-TH3-INFO-08 (2026-09-21) — THE READOUT'S OWN RUNGS. TH3ROPlateAt/TH3RORowAt
// (TH3Renderer.mqh) draw the AB=CD caption AND the leg box on the same fixed
// dark plate. Both wore the default ZORDER 0, so the paint order was creation
// order: a plate newer than its rows covered its own text (the top-left dark
// empty bar). Plate 62, ink 63 — above the box art, below the chart text layer.
#define Z_TH3_RO_PLATE  62      // readout plate (caption + leg box)
#define Z_TH3_RO_TEXT   63      // readout ink (always above its own plate)
#define Z_CHART_LABEL  100      // price/level labels, view anchor, countdown tag

// ── Base/Knot floating pills — over the chart, UNDER the settings card
#define Z_BOX_HINT    1400      // the wide floating hint
#define Z_BOX_BADGE   1410      // the small box badge

// ── the mini Base Box strip (item 13) — its own drawing family, still under
//    the full card 12 that it opens
#define Z_STRIP_BG    1439      // P-DRAW-35: solid underlayer below the skin (alpha fill)
#define Z_STRIP       1440      // bk_strip.bmp, the toolbar body
#define Z_STRIP_ICON  1441      // strip slot glyphs
#define Z_STRIP_OVER  1442      // strip popover chevrons

// ── the ring menu — the card covers it (consequence 1 above)
#define Z_MENU_PANEL    1004    // sub-menu panel chrome
#define Z_MENU_DOT      1005    // sub-menu title dot
#define Z_MENU_CELL     1006    // RETIRED (P-UI-69c, 2026-09-25): its owner was the ctx menu's
                                        // icon-cell hover face (P-UI-105), and the whole right-click
                                        // era was DELETED by user order (P-UI-113/114, 2026-09-23).
                                        // The rung is kept, unused, exactly like Z_BOX_DOT/Z_BOX_GRIP:
                                        // the ladder's numbers are what every rung above and below is
                                        // measured against, so retiring the owner never renumbers it.
                                        // A grep for Z_MENU_CELL answers THIS LINE and nothing else —
                                        // that single hit IS the measurement that the face is gone.
#define Z_MENU_ITEM     1010    // ring/Tools item faces
#define Z_MENU_ICON     1011    // item glyphs
#define Z_MENU_BADGE    1012    // item badge bodies + captions
#define Z_MENU_BADGE_TX 1013    // badge ink
#define Z_MENU_PAGER    1014    // grid pager
#define Z_MENU_ORB      1200    // the TRex orb (was 2000 — ABOVE the card)
#define Z_MENU_TIP_BG   1300    // hover tip body
#define Z_MENU_TIP      1302    // hover tip caption/header

// ── the settings cards: 1480..1542 is ONE ladder in paint order
#define Z_PANEL_CARD   1480     // card skin (shadow fringe + body)
#define Z_PANEL_TOPBAR 1481     // .card::before accent bar
#define Z_PANEL_ACT    1484     // active-row wash
#define Z_PANEL_BAND   1486     // section band
#define Z_PANEL_SEP    1490     // row separators
#define Z_PANEL_HAIR   1495     // header hairline
#define Z_PANEL_BASE   1500     // covers + click targets (a button stays under its skin)
#define Z_PANEL_SKIN   1501     // skins over their own click target
#define Z_PANEL_CHIP   1502     // chip faces, dots, counters, value chip
#define Z_PANEL_INK    1503     // glyph ink, chevrons, keycap ink
#define Z_PANEL_GLYPH  1504     // row glyph ink
#define Z_PANEL_GLOSS  1505     // track gloss
#define Z_PANEL_SW     1506     // switch face
#define Z_PANEL_EDIT   1508     // OBJ_EDIT text field
#define Z_PANEL_KNOB   1512     // slider knob
#define Z_PANEL_TEXT   1520     // every caption
#define Z_PANEL_CTL    1540     // buttons/labels ON a control
#define Z_PANEL_MARK   1542     // active marks (tab underline, glass sheens)

// ── popovers, then the palette: the only things allowed over a card
#define Z_PANEL_DD_SH   1558    // dropdown shadow
#define Z_PANEL_DD_BG   1560    // dropdown body
#define Z_PANEL_DD_SEL  1566    // dropdown selected row
#define Z_PANEL_DD_LBL  1568    // dropdown captions
#define Z_PANEL_DD_ICO  1574    // dropdown glyphs
#define Z_PANEL_POP     1600    // palette card
#define Z_PANEL_POP_BG  1601    // palette body + mixer
#define Z_PANEL_POP_CTL 1602    // palette tabs/fields
#define Z_PANEL_POP_FG  1603    // palette knobs/ink
#define Z_PANEL_TOP     1650    // reserved: a full-card overlay, if one is ever added

// Performance & Safety Constants
#define MAX_SAFE_LEVELS 2000          // Maximum safe number of levels per side
#define MAX_SAFE_OBJECTS 5000         // Warning threshold for total objects
#define CRITICAL_OBJECT_LIMIT 50000   // Critical threshold (MT4 limit ~64K)
#define CPU_WARNING_MS 50             // Warning if OnCalculate takes >50ms
#define CPU_CRITICAL_MS 200           // Critical if OnCalculate takes >200ms

// Array Safety Constants (GOLD FIX v3)
#define MAX_PREFIX_COUNT 50           // Maximum number of object prefixes (with safety margin)
#define OBJECT_COUNT_INCREASE_THRESHOLD 100  // Trigger cleanup if objects increased by 100
#define REDRAW_THROTTLE_SECONDS 10    // Minimum 10 seconds between redraws
#define CLEANUP_INTERVAL_SECONDS 300  // 5 minutes between periodic cleanups
#define CHART_CHANGE_THROTTLE_MS 100  // Throttle CHARTEVENT_CHART_CHANGE bursts (ms)
#define DOUBLE_CLICK_THRESHOLD_MS 300 // Double-click detection window (ms)

// Live bar-close countdown tag (beside the live candle, at the live price).
// It is its OWN layer since 2026-09-11 (own switch/color/size/gap) and the
// name is deliberately free of "ATR_": the periodic object janitor in
// EventHandlers hides every object whose name contains "ATR_" while the ATR
// labels are off, and this tag must survive that.
#define LIVE_COUNTDOWN_NAME "CloseIn_Tag"
// Older builds drew the same tag as "...ATR_Trade_Current_CloseIn" (first a
// corner row, then candle text) — every path that used to own that name now
// just purges it so old charts lose it for good.
#define LIVE_COUNTDOWN_LEGACY_NAME "ATR_Trade_Current_CloseIn"

// The Base/Knot box' targets (P-BK-50, 2026-09-15): a box draws the TRADE PLAN's own
// TP1..TP3 legs, and the `TP COUNT` row (Base Box > Setup) picks HOW MANY of them are
// drawn. The bound lives here — ABOVE both owners: RuntimeSettings owns the setting's
// 1..3 clamp and BaseKnotTool draws the ticks, so the number is written ONCE (the
// layer law: the clamp cannot read a constant the drawing module declares).
#define BK_TP_PLAN_MAX 3

// The bottom-right trade card (P-LBL-06/07/08): `#SL/TP` row, then the
// `Hunter SL / Eng.SL` row, then the `TR|ex` brand. TWO clamps on the input
// that asks for blank rows between the trade row and the Hunter row:
//   TREX_CARD_MAX_GAP_ROWS  the user bound (what the settings dialog offers)
//   the chart's own height  the owner's second bound (a 400px chart cannot
//                           hold 20 rows, so the owner gives what fits)
// Named so `tools/chart-label-audit.py` reads the BOUNDS instead of trusting a
// comment, and so the same number is never typed twice.
#define TREX_CARD_MAX_GAP_ROWS 20
#define TREX_CARD_TOP_PAD      8    // the card may not touch the chart ceiling
// The card's SEAM is its own input (`inpATRTradeLabelRowGap`, "compact gap
// between ATR trade rows"), not the shared column `inpLabelRowGap`: the card is
// three rows in a corner and the columns are grids, so one number for both is
// why the card read as stretched (2026-09-14 user: "the rows are so far apart
// it looks broken"). Same rule as the row count: the bound is named, so the
// gate reads it and the number is never typed twice.
#define TREX_CARD_MAX_ROW_GAP  60
// How far the card may sit above the chart's bottom edge. The input
// (`inpLabelsMarginBottom`, group 13, personalisable) is applied RAW at init,
// so an input of 0 or -5 must not push the card through the floor; the upper
// bound keeps a mistyped value from parking the card in the middle of the
// screen, and the chart-height clamp in the owner is the second bound.
#define TREX_CARD_MAX_MARGIN_BOTTOM 200

// P-UI-131 — THE LABEL FAMILY'S FONT IS AN INDEX AT LAST. `inpFontName` is a
// STRING while every settings control is an INDEXED one (a dropdown), so the
// list is the owner here and the string is one of its faces: the readers keep
// reading `inpFontName` (RuntimeSettings re-points it at `LabelFontName()`),
// the panel row stores `g_labelFontIdx`, and ONE integer (`OV_LFI`) persists it.
// A font typed straight into the MT4 dialog still works — it is index -1 and
// the string wins until the row is used.
#define LABEL_FONT_N 6
string LabelFontNameAt(const int i)
{
   switch(i)
   {
      case 0: return "Arial Bold";   // the shipped default (P-UI-42 hands MT4 this)
      case 1: return "Arial";
      case 2: return "Tahoma";
      case 3: return "Verdana";
      case 4: return "Trebuchet MS";
      case 5: return "Courier New";
   }
   return "Arial Bold";
}
int LabelFontIdxOf(const string name)
{
   for(int i = 0; i < LABEL_FONT_N; i++)
      if(LabelFontNameAt(i) == name) return i;
   return -1;   // typed in the dialog: the string is the setting, not a list slot
}
string LabelFontOpts()   // the dropdown's own text, from the same list (one owner)
{
   string s = LabelFontNameAt(0);
   for(int i = 1; i < LABEL_FONT_N; i++) s += "|" + LabelFontNameAt(i);
   return s;
}

// Division Safety Constants (GOLD FIX v3)
#define MIN_SAFE_DIVISIONS 0.001      // Minimum divisions to prevent precision loss
#define MAX_SAFE_FACTOR 10000.0       // Maximum factor value to prevent overflow

// Visibility Constants for OBJPROP_TIMEFRAMES (visual align MT5)
// Used by VisibilityManager for hide/show without deletion
#ifndef OBJ_ALL_PERIODS
#define OBJ_ALL_PERIODS 0xFFFFFFFF  // Show on all timeframes
#endif
#ifndef OBJ_NO_PERIODS
#define OBJ_NO_PERIODS 0            // Hide on all timeframes
#endif

//                         
#ifndef OBJPROP_BOLD
#define OBJPROP_BOLD 5
#endif

const string FRACTAL_TIMEFRAMES[] = {
    "M1", "M4", "M16", "H1+M4", "H4+M16", "H17+M4",
    "D2+H20+M16", "D11+H9+M4", "D45+H12+M16"
};
// FRACTAL_SHORT_NAMES (visual align MT5     used for compact label rendering)
const string FRACTAL_SHORT_NAMES[] = {
    "M1", "M4", "M16", "H1.4", "H4.16", "H17.4",
    "D2.20.16", "D11.9.4", "D45.12.16"
};
// Adjusted by factor 1.0415625 so H17+M4 (1024min) = 66.66% instead of 64%
// These percentages MUST match MotiveWave Constants.java FRACTAL_PERCENTAGES
const double MODIFIED_FRACTAL_PERCENTAGES[] = {
    0.0208,   // M1: 2.08%
    0.0417,   // M4: 4.17%
    0.0833,   // M16: 8.33%
    0.1666,   // H1+M4: 16.66%
    0.3333,   // H4+M16: 33.33%
    0.6666,   // H17+M4: 66.66%  
    1.3332,   // D2+H20+M16: 133.32%
    2.6664,   // D11+H9+M4: 266.64%
    5.3328    // D45+H12+M16: 533.28%
};

//==============================================================================
// P-TH-01 (2026-09-18) — THE TH PERCENTAGE KNOB'S ONE BOUND.
//
// The table above is the professor's ladder and it is NEVER edited. The knob
// (`inpTHPercentOverride`) is read as "the percentage for THIS chart's own
// rung" and turns into ONE ratio (`FractalPercentScale()`,
// FractalTimeframes.mqh), which every rung is multiplied by — so the ladder's
// nine x2 relationships survive whatever the knob says.
//
// WHY 200 IS THE END STOP. The panel's slider is a POSITION, not a value:
// `PnlValueFromX` maps the track's ~230 px of travel onto [minV, maxV] and
// then rounds to `step`. At `step = 1` every integer is reachable only while
// `maxV <= the travel`, because a grid coarser than 1 makes the knob skip
// integers (at maxV = 533 one pixel is 2.32 and 75 is simply unreachable —
// the user's own example would be impossible to dial). 200 covers the whole
// research range on the charts that matter (D1's own rung is 66.66, so 100
// and 133.32 are inside it) and keeps every integer reachable. A value above
// 200 is still legal through the INPUT — only the slider stops there, and
// this bound is also what the persisted-override load clamps to, so a saved
// GV can never ask for a ladder the slider cannot reproduce.
//
// It is an INT on purpose: `PnlSetDef`'s `maxV` is `int&`, and the panel
// simulator resolves this name straight out of this file to draw the same
// track the MQL compiles — a `200.0` here would need a cast in the panel and
// the simulator's `int(eval(...))` would silently read 0.
#define TH_PERCENT_OVERRIDE_MAX 200

const color FRACTAL_COLORS[] = {
    clrBlack, clrBlack, clrBlack, clrBlue, clrRed,
    clrRed, clrGreen, clrBlack, clrBlack
};
const string STANDARD_TIMEFRAMES[] = {"M1", "M5", "M15", "H1", "H4", "D1", "W1", "MN1"};
const int STANDARD_MINUTES[] = {1, 5, 15, 60, 240, 1440, 10080, 43200};
// Column colors shared by the ATR overview and the standard TH strip (one owner).
const color STANDARD_COLORS[] = {clrBlack, clrBlack, clrBlack, clrBlue, clrRed, clrGreen, clrBlack, clrBlack};

enum ENUM_TH_START_POINT_TYPE {
    TH_START_POINT_MIDPOINT = 0,      // Midpoint (historical H+L / 2)
    TH_START_POINT_HISTORICAL_HIGH = 1, // Historical High
    TH_START_POINT_HISTORICAL_LOW = 2,  // Historical Low
    TH_START_POINT_CUSTOM_PRICE = 3,    // Custom Price
    TH_START_POINT_PREVIOUS_CLOSE = 4   // Previous Day Close
};

enum ENUM_LINE_OBJECT_TYPE {
    LINE_OBJECT_HORIZONTAL_LINE = 0,
    LINE_OBJECT_RAY_LINE = 1
};

enum ENUM_LABEL_CORNER_POSITION {
    LABEL_CORNER_LEFT_TOP = 0,
    LABEL_CORNER_LEFT_BOTTOM = 1
};

enum ENUM_LABEL_ARRANGEMENT {
    LABEL_ARRANGEMENT_VERTICAL = 0,
    LABEL_ARRANGEMENT_HORIZONTAL = 1
};

// Step calculation modes (matching MotiveWave implementation exactly)
// E_STEP removed - TP is now a standalone mode (like Java version)
enum ENUM_STEP_CALCULATION_MODE {
    TH_STEP = 0,        // Traditional TH step mode
    SS_LS_STEP = 1,     // Short Step / Long Step alternating mode
    COMBO_STEP = 2,     // Combo Step mode (customizable: Component1 + Component2)
    FACTOR_STEP = 3     // Factor Step mode (divides High-Low range by Factor    2)
};

// Factor calculation mode (Auto vs Manual)
enum ENUM_FACTOR_MODE {
    FACTOR_MODE_AUTO = 0,    // Auto (based on TH)
    FACTOR_MODE_MANUAL = 1   // Manual (user-defined)
};

//+------------------------------------------------------------------+
//| Factor Display Mode - How factor value is shown and operation    |
//|                                                                  |
//| CLASSIC: Traditional mode - number is Factor, Step is calculated |
//|   Input: Factor number  →  Step = Range / (Factor × 2)         |
//|   Display: "F: 50.00 | Step: 12.5 pips"                         |
//|                                                                  |
//| DIRECT: New mode - number IS the Step Size, Factor is internal   |
//|   Input: Step Size  →  Factor = Range / (Step × 2) (internal)   |
//|   Display: "Step: 12.5 pips | F: 50.00"                         |
//+------------------------------------------------------------------+
enum ENUM_FACTOR_DISPLAY_MODE {
    FACTOR_DISPLAY_CLASSIC = 0,  // Classic: Factor number (current behavior)
    FACTOR_DISPLAY_DIRECT = 1    // Direct: Step Size is the primary value
};

//+------------------------------------------------------------------+
//| Factor Auto Basis - What to base the auto calculation on         |
//|           Factor                                       |
//|                                                                  |
//| CONTROL: Average of SS and LS (TH  - Balanced [DEFAULT]    |
//| SS: Short Step (TH  - Closer levels, more lines             |
//| LS: Long Step (TH  - Wider levels, fewer lines              |
//| TH: Pure TH (TH  - Standard spacing                         |
//| TRIGGER: Current timeframe TH - Responsive to current TF        |
//| PATTERN: 4x timeframe TH - Medium-term structure                |
//| STRUCTURE: 16x timeframe TH - Long-term structure               |
//| COMBO: Average of 2 components - Custom mix like Combo Mode     |
//+------------------------------------------------------------------+
enum ENUM_FACTOR_AUTO_BASIS {
    FACTOR_BASIS_CONTROL = 0,      // Control: (SS+LS)/2 = TH  [Balanced]
    FACTOR_BASIS_SS = 1,           // Short Step: TH  (More levels)
    FACTOR_BASIS_LS = 2,           // Long Step: TH  (Fewer levels)
    FACTOR_BASIS_TH = 3,           // Pure TH: TH  (Standard)
    FACTOR_BASIS_TRIGGER = 4,      // Trigger: Current TF (Responsive)
    FACTOR_BASIS_PATTERN = 5,      // Pattern: 4x TF (Medium-term)
    FACTOR_BASIS_STRUCTURE = 6,    // Structure: 16x TF (Long-term)
    FACTOR_BASIS_COMBO = 7         // Combo: Average of 2 components (Custom)
};

//+------------------------------------------------------------------+
//| Basis multiplier table - SINGLE SOURCE OF TRUTH (one table).     |
//| Derived from adapted current-TF TH:                              |
//|   CONTROL = (SS + LS) / 2 = 1.75 * TH  [Balanced, default]      |
//|   SS      = Short Step            = 1.5  * TH                   |
//|   LS      = Long Step             = 2.0  * TH                   |
//|   TH      = Pure TH               = 1.0  * TH                   |
//|   TRIGGER = Current TF TH         = 1.0  * TH                   |
//|                                                                  |
//| Lives here (next to the enum) so BOTH the raw path               |
//| (ExtendedDrawingFunctions.GetStepSizeForFactorBasis) and the      |
//| adapted path (FactorMode.GetFactorModeAutoStepSize) consume the   |
//| same numbers - adapted-vs-raw semantics of each path untouched.   |
//| PATTERN / STRUCTURE / COMBO use their own TF/config (no entry).  |
//+------------------------------------------------------------------+
struct SBasisMultiplierDef {
    ENUM_FACTOR_AUTO_BASIS basis;
    double                 multiplier;
};

const SBasisMultiplierDef FACTOR_BASIS_MULTIPLIERS[] = {
    {FACTOR_BASIS_CONTROL, 1.75},
    {FACTOR_BASIS_SS,      1.5},
    {FACTOR_BASIS_LS,      2.0},
    {FACTOR_BASIS_TH,      1.0},
    {FACTOR_BASIS_TRIGGER, 1.0}
};

//+------------------------------------------------------------------+
//| Get multiplier for a current-TF based basis                      |
//+------------------------------------------------------------------+
double GetFactorBasisMultiplier(const ENUM_FACTOR_AUTO_BASIS basis)
{
    int n = ArraySize(FACTOR_BASIS_MULTIPLIERS);
    for(int i = 0; i < n; i++) {
        if(FACTOR_BASIS_MULTIPLIERS[i].basis == basis)
            return FACTOR_BASIS_MULTIPLIERS[i].multiplier;
    }
    return 1.5; // Fallback = SS (unreachable for the 8 known bases)
}

//+------------------------------------------------------------------+
//| Structure Base Multiplier - Valid range 2-9                      |
//|        -                                            |
//|                                                                  |
//| Defines the hierarchical structure levels:                      |
//| L1 = base^1, L2 = base^2, L3 = base^3, L4 = base^4, L5 = base^5|
//|                                                                  |
//| Example with base=3: L1=3, L2=9, L3=27, L4=81, L5=243          |
//| Example with base=4: L1=4, L2=16, L3=64, L4=256, L5=1024       |
//|                                                                  |
//| NOTE: Value 1 is INVALID because all levels become identical    |
//| (1^1 = 1^2 = 1^3 = 1^4 = 1^5 = 1)                              |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_BASE_MULTIPLIER {
    BASE_MULTIPLIER_2 = 2,   // Base 2: L1=2, L2=4, L3=8, L4=16, L5=32
    BASE_MULTIPLIER_3 = 3,   // Base 3: L1=3, L2=9, L3=27, L4=81, L5=243 [DEFAULT]
    BASE_MULTIPLIER_4 = 4,   // Base 4: L1=4, L2=16, L3=64, L4=256, L5=1024
    BASE_MULTIPLIER_5 = 5,   // Base 5: L1=5, L2=25, L3=125, L4=625, L5=3125
    BASE_MULTIPLIER_6 = 6,   // Base 6: L1=6, L2=36, L3=216, L4=1296, L5=7776
    BASE_MULTIPLIER_7 = 7,   // Base 7: L1=7, L2=49, L3=343, L4=2401, L5=16807
    BASE_MULTIPLIER_8 = 8,   // Base 8: L1=8, L2=64, L3=512, L4=4096, L5=32768
    BASE_MULTIPLIER_9 = 9    // Base 9: L1=9, L2=81, L3=729, L4=6561, L5=59049
};

// Harmonic Ratio validation constants
#define MIN_HARMONIC_RATIO 1.01   //   1%   (meaningful alternation)
#define MAX_HARMONIC_RATIO 2.0    //   2x (maximum variation)
#define DEFAULT_HARMONIC_RATIO 1.333  // Golden-like ratio (4/3)

// NOTE: ENUM_QUICK_TEST_MODE / ENUM_MEAN_TYPE removed - not used
// Quick Test is controlled by ENUM_COMBO_MODE instead

//+------------------------------------------------------------------+
//| Quick Test Presets (Simplified Component Selection)              |
//| Preset        (      components)                     |
//|                                                                  |
//| NOTE: CUSTOM removed - use Advanced mode for full control       |
//+------------------------------------------------------------------+
enum ENUM_QUICK_TEST_PRESET {
    QUICK_PRESET_TRIGGER_PATTERN = 0,       // Trigger + Pattern (2 TF)
    QUICK_PRESET_ALL_4TF = 1,               // Sub + Trigger + Pattern + Structure (4 TF)
    QUICK_PRESET_TRIGGER_PATTERN_STRUCTURE = 2,  // Trigger + Pattern + Structure (3 TF)
    QUICK_PRESET_PATTERN_STRUCTURE = 3,     // Pattern + Structure (2 TF)
    QUICK_PRESET_TRIGGER_ONLY = 4           // Trigger only (1 TF)
};

// SS/LS basis type
enum ENUM_SSLS_BASIS_TYPE {
    SSLS_BASIS_STRUCTURE = 0,   // Based on Structure TH
    SSLS_BASIS_PATTERN = 1,     // Based on Pattern TH
    SSLS_BASIS_TRIGGER = 2      // Based on Trigger TH
};

//+------------------------------------------------------------------+
//| Calculation Basis (matching Java CalculationBasis enum)          |
//|         (                                          |
//|                                                                  |
//| TH_BASIS -        TH (                        |
//| ATR_BASIS -        ATR    (Weighted ATR)             |
//+------------------------------------------------------------------+
enum ENUM_CALCULATION_BASIS {
    CALC_BASIS_TH = 0,          // TH-Based (Theoretical) -   
    CALC_BASIS_ATR = 1          // ATR-Based (Actual) -   
};

// Combo components are now explicit (ENUM_COMBO_TIMEFRAME_TYPE + ENUM_COMBO_STEP_TYPE)
// and the operation enum is ENUM_COMBO_OPERATION - geometric/mean operators removed.

//+------------------------------------------------------------------+
//| Helper structure to hold common calculation values              |
//| All values are in PRICE units (matching MotiveWave)             |
//+------------------------------------------------------------------+
struct SCommonStepData {
    double thValue;              // TH value in PRICE units
    double structureValue;       // Structure value in PRICE units
    double patternValue;         // Pattern value in PRICE units
    double triggerValue;         // Trigger value in PRICE units
    double shortStep;            // SS = 1.5 * Structure (PRICE units)
    double longStep;             // LS = 2.0 * Structure (PRICE units)
    double pointSize;            // DEPRECATED: No longer used (set to 1.0)
    double midpointPrice;        // Start point price
    int maxLevelsAbove;          // Adaptive max levels above
    int maxLevelsBelow;          // Adaptive max levels below
};

//+------------------------------------------------------------------+
//| Advanced Combo Operations for Factor Auto Basis                  |
//|      Combo   Factor Auto Basis                  |
//+------------------------------------------------------------------+
enum ENUM_COMBO_OPERATION {
    COMBO_OP_AVERAGE = 0,       // Average: (A + B) / 2 [Default]
    COMBO_OP_ADD = 1,           // Add: A + B
    COMBO_OP_SUBTRACT = 2,      // Subtract: A - B (or |A - B|)
    COMBO_OP_MULTIPLY = 3,      // Multiply: A   B
    COMBO_OP_MIN = 4,           // Minimum: min(A, B) or min(A, B, C)
    COMBO_OP_MAX = 5,           // Maximum: max(A, B) or max(A, B, C)
    COMBO_OP_WEIGHTED = 6       // Weighted: A  + B  (W1+W2=1)
};

//+------------------------------------------------------------------+
//| Combo Mode Selection (Preset / Advanced)                         |
//|                       Combo (Preset /               )                             |
//|                                                                  |
//| TWO INDEPENDENT MODES - Simplified and user-friendly             |
//|                                                                  |
//| PRESET: Quick select from the 8 ready-to-use combinations        |
//|   Uses: inpComboPreset                                           |
//|                                                                  |
//| ADVANCED: Manual control - two components (TF + Step each) and   |
//| one operation (ENUM_COMBO_OPERATION).                            |
//|   Uses: inpComboComp1TF/Step, inpComboOp1, inpComboComp2Enabled, |
//|         inpComboComp2TF/Step                                     |
//+------------------------------------------------------------------+
enum ENUM_COMBO_MODE {
    COMBO_MODE_PRESET = 0,      // Preset Mode (Recommended)
    COMBO_MODE_ADVANCED = 1     // Advanced Mode (Full control)
};

//+------------------------------------------------------------------+
//| Timeframe Types for Advanced Combo                               |
//+------------------------------------------------------------------+
enum ENUM_COMBO_TIMEFRAME_TYPE {
    COMBO_TF_SUB = 0,           // Sub: 1/4 current (faster)
    COMBO_TF_TRIGGER = 1,       // Trigger: Current timeframe
    COMBO_TF_PATTERN = 2,       // Pattern: 4x current
    COMBO_TF_STRUCTURE = 3      // Structure: 16x current
};

//+------------------------------------------------------------------+
//| Step Size Type (TH, SS, LS, 4/3 ratio)                            |
//+------------------------------------------------------------------+
enum ENUM_COMBO_STEP_TYPE {
    COMBO_STEP_TH = 0,          // TH: Base step (1.0  )
    COMBO_STEP_SS = 1,          // SS: Short step (1.5  )
    COMBO_STEP_LS = 2,          // LS: Long step (2.0  )
    COMBO_STEP_RATIO_4_3 = 3    // 4/3 ratio: TH * 1.333333...
};

//+------------------------------------------------------------------+
//| Preset Combinations - practical daily-use set (8 presets)        |
//|                                                                  |
//| DESIGN PRINCIPLE: keep only the commonly used combinations;      |
//| anything else can be built with Advanced Mode.                  |
//+------------------------------------------------------------------+
enum ENUM_COMBO_PRESET {
    COMBO_PRESET_BALANCED_MEDIUM = 0,   // (Pattern + Trigger) / 2 [Most Popular]
    COMBO_PRESET_BALANCED_LONG = 1,     // (Structure + Pattern) / 2
    COMBO_PRESET_BALANCED_TRIPLE = 2,   // (Trigger + Pattern + Structure) / 3
    COMBO_PRESET_CONSERVATIVE = 3,      // max(Structure, Pattern)
    COMBO_PRESET_AGGRESSIVE = 4,        // min(Trigger, Sub)
    COMBO_PRESET_TREND_FILTER = 5,      // Structure - Sub
    COMBO_PRESET_SS = 6,                 // Pattern / SS = same spacing as Short Step mode
    COMBO_PRESET_RATIO_4_3 = 7           // Pattern / (TH * 4/3) = TH * 1.333333...
};

// TH3 Label Position
//         label    TH3
enum ENUM_TH3_LABEL_POSITION {
    TH3_LABEL_START = 0,        // Start (Beginning of line)
    TH3_LABEL_MIDDLE = 1,       // Middle (Center of visible range)
    TH3_LABEL_END = 2,          // End (Right side - Default)
    TH3_LABEL_HIDDEN = 3        // Hidden (No labels)
};

// Unified Zone Display Style (Used by ALL modes)
//
// P-UI-62: THIS IS AN APPEARANCE AXIS, NOT A VISIBILITY AXIS.
//
// Slot 2 used to be `ZONE_STYLE_HIDDEN`, which DELETED the zone objects - a second
// mechanism for the question the MID ZONES master switch already owns ("are zones
// shown at all?"). Two owners for one question is how a user ends up with a card
// whose third pill fights the switch directly above it, and it is what the report
// names: «هیدن از همون دکمه بالا استفاده میشه دیگه».
//
// The three states are now three genuinely different PICTURES of the same band, and
// the two halves of a zone - the BAND and its EDGE - can be set independently:
//
//   FILLED   : band only            (filled = true,  outline = false)
//   EMPTY    : edge only            (filled = false, outline = true)
//   OUTLINED : band AND edge at once (filled = true,  outline = true)
//
// The edge half is not decoration: OBJ_RECTANGLE ignores OBJPROP_STYLE/WIDTH, so a
// FILLED band has no visible line to style - which is exactly why the BORDER and
// BORDER WIDTH rows of the card did nothing until now. The edge is drawn as its own
// object family and takes those settings.
enum ENUM_ZONE_STYLE {
    ZONE_STYLE_BOX_FILLED = 0,    // Filled (band only)
    ZONE_STYLE_BOX_EMPTY = 1,     // Empty (edge only, no band)
    ZONE_STYLE_BOX_OUTLINED = 2   // Outlined (band AND its edge)
};

// Legacy aliases for backward compatibility
//                      
#define ENUM_TH3_ZONE_STYLE ENUM_ZONE_STYLE
#define ENUM_FACTOR_ZONE_STYLE ENUM_ZONE_STYLE
#define TH3_ZONE_BOX_FILLED ZONE_STYLE_BOX_FILLED
#define TH3_ZONE_BOX_EMPTY ZONE_STYLE_BOX_EMPTY
#define TH3_ZONE_BOX_OUTLINED ZONE_STYLE_BOX_OUTLINED
#define FACTOR_ZONE_BOX_FILLED ZONE_STYLE_BOX_FILLED
#define FACTOR_ZONE_BOX_EMPTY ZONE_STYLE_BOX_EMPTY
#define FACTOR_ZONE_BOX_OUTLINED ZONE_STYLE_BOX_OUTLINED

// TH3 Drawing Mode
//     TH3 (Steps       AB=CD)
enum ENUM_TH3_DRAWING_MODE {
    TH3_MODE_STEPS = 0,         // Steps Mode (2-point drag)
    TH3_MODE_ABCD = 1           // AB=CD Mode (3-point click: A, B, C       calculates D)
};

// NOTE: TH3_TEST_FREQUENCIES[] removed   replaced by Binary Subdivision Frequency System
// in ProjectConstants.mqh (runtime calculation via GetFrequencyByIndex())

//+------------------------------------------------------------------+
//| ENUM: Adaptive Scaling Mode                                      |
//|                                                    |
//+------------------------------------------------------------------+
enum ENUM_ADAPTIVE_MODE {
    ADAPTIVE_FIXED   = 0,    // Fixed (No Adaptation)
    ADAPTIVE_ATR     = 1,    // ATR Adaptive (Full)
    ADAPTIVE_BLENDED = 2,    // Blended (Mix ATR + TH)
    ADAPTIVE_FRACTAL = 3     // Fractal Jump (Power of 2 steps based on ATR)
};

// Fractal Jump Strategy
enum ENUM_FRACTAL_JUMP_STRATEGY {
    JUMP_CONSERVATIVE = 0,   // Conservative (Original log2 with bias)
    JUMP_AGGRESSIVE   = 1    // Aggressive (Jump to higher levels earlier)
};

// Adaptive Scaling Constants
#define MIN_SCALING_FACTOR      0.1    // Minimum allowed scaling factor
#define MAX_SCALING_FACTOR      10.0   // Maximum allowed scaling factor
#define DEFAULT_SMOOTHING_PERIOD 20    // Default EMA smoothing period
#define DEFAULT_BLEND_RATIO     0.5    // Default blend ratio (50/50)

// Global State Variables for Adaptive Scaling
static int g_fractalShift = 0;          // Current fractal level shift (power of 2)

//+------------------------------------------------------------------+
//| TH3 Object Name Suffixes (Magic Numbers Elimination)            |
//|            TH3 (  Magic Numbers)                       |
//+------------------------------------------------------------------+
#define TH3_SUFFIX_LINE_AB "_Line_AB"
#define TH3_SUFFIX_LINE_BC "_Line_BC"
#define TH3_SUFFIX_TARGET  "_Target_"
#define TH3_SUFFIX_POINT   "_Point_"
#define TH3_SUFFIX_LABEL   "_Label_"
#define TH3_SUFFIX_INFO    "_Info"
#define TH3_SUFFIX_ZONE    "_Zone"

//  
// ZONE ERROR CODES (used by ZoneValidator / ZoneCalculator)
//  
#define ZONE_ERROR_NONE             0
#define ZONE_ERROR_INVALID_PRICES   1
#define ZONE_ERROR_EQUAL_PRICES     2
#define ZONE_ERROR_INVALID_HEIGHT   3
#define ZONE_ERROR_INVERTED_BOUNDS  4
#define ZONE_ERROR_OUT_OF_RANGE     5

//  
// PIPELINE STRUCTS (used by Zone system)
//  

struct SLevelRawData {
    double price;
    int    logicalStep;
    int    stepTypeIndex;
};

struct SStyleConfig {
    double zoneHeightPercent;
    int    zoneTransparency;
    int    baseMultiplier;
    bool   showStructure;
    bool   showTrigger;
    bool   showZones;
    bool   globalShowLines;
    color  structColorL1;
    color  triggerColor;
    int    structStyleL1;
    int    structWidthL1;
    int    triggerStyle;
    int    triggerWidth;
};

struct SZoneValidationResult {
    bool   isValid;
    int    errorCode;
    string errorMessage;
};

struct SLevelClassification {
    bool   isStructure;
    bool   isActive;
    color  levelColor;
    int    style;
    int    width;
};

struct SZoneGeometry {
    bool   isValid;
    double topPrice;
    double bottomPrice;
    double midPoint;
    int    linkedLevelIndex;
};

struct SLineRenderInfo {
    bool           isVisible;
    color          clr;
    ENUM_LINE_STYLE style;
    int            width;
    string         name;
    double         price;
    string         tooltip;
    bool           selectable;
};

struct SZoneRenderInfo {
    bool   isVisible;
    string name;
    color  clr;
    int    transparency;
    bool   filled;
    double topPrice;
    double bottomPrice;
};

struct FrequencyResult {
    int       bestIndex;
    double    bestFrequency;
    double    totalScore;
    double    multiStepScore;
    double    patternScore;
    double    timeScore;
    double    sqrtScore;
    double    harmonicScore;
    double    historyScore;
    double    confidence;
    double    step1Price;
    double    step3Price;
    double    step5Price;
    double    step7Price;
    int       matchedSteps;
    string    matchLabel;
    string    patternType;
    int       matchWaveIndex;
    double    errorPips;
    bool      isValid;
    void Reset() {
        bestIndex = -1;
        bestFrequency = 0;
        totalScore = 0;
        multiStepScore = 0;
        patternScore = 0;
        timeScore = 0;
        sqrtScore = 0;
        harmonicScore = 0;
        historyScore = 0;
        confidence = 0;
        step1Price = 0;
        step3Price = 0;
        step5Price = 0;
        step7Price = 0;
        matchedSteps = 0;
        matchLabel = "";
        patternType = "";
        matchWaveIndex = -1;
        errorPips = 0;
        isValid = false;
    }
};

#define FREQ_HISTORY_SIZE 20

struct FrequencyHistoryEntry {
    FrequencyResult result;
    double    abDistance;
    double    ratioBC_AB;
    int       freqIndex;
    datetime  timestamp;
    bool      isUsed;
    void Reset() {
        result.Reset();
        abDistance = 0;
        ratioBC_AB = 0;
        freqIndex = -1;
        timestamp = 0;
        isUsed = false;
    }
};

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-46 (2026-09-26) — ONE PALETTE, AND IT IS THE USER'S OWN 64.
// The user sent a palette chart (8 rows x 8 cells) and ordered it to BE the
// palette. This table is the single owner: `BioPickColor` is its only reader,
// `BioPal`'s quick row is its own first row, and BOTH pickers (the strip's
// popover, the cards' popup) iterate the same 64 through faces. The retired
// Material 19x10 matrix and its hue/shade mapping (P-DRAW-39) are deleted with
// it: a curated chart has no families and no shades, so the family/shade
// captions had nothing left to name and every cell reads as its own hex.
// ══════════════════════════════════════════════════════════════════════════
// P-UI-69c: the brand amber IS the palette's cell 0 — ONE literal, and it must be
// declared BEFORE its readers: MQL4 is define-before-use, and a define placed
// after its user is `error 256: undeclared identifier` (measured 2026-09-25).
#define BIO_CLR_BRAND      C'255,171,0'     // #FFAB00 brand amber = cell 0
#define BIOPICK_COLS 8
#define BIOPICK_ROWS 8
#define BIOPICK_N    (BIOPICK_COLS * BIOPICK_ROWS)
//--- the user's chart, read left to right then top to bottom; row 1 is the
//--- quick row. Measured off the chart itself (2026-09-26): every cell a flat
//--- fill, a 5x5 pixel vote at its centre agreeing 25/25 on all 64.
color BioPickColor(const int row, const int col)
{
   static color pal[BIOPICK_N] =
   {
      BIO_CLR_BRAND,  C'240,69,95',   C'18,184,134',  C'76,141,255',  C'155,93,229',  C'0,194,209',   C'255,138,0',   C'243,246,251',
      C'140,150,166', C'29,34,44',    C'255,208,138', C'255,163,179', C'141,227,201', C'169,198,255', C'205,180,246', C'140,230,238',
      C'255,194,71',  C'203,212,226', C'90,101,119',  C'18,22,29',    C'122,82,0',    C'122,31,46',   C'10,90,66',    C'32,64,112',
      C'74,44,116',   C'0,94,102',    C'255,233,199', C'247,249,252', C'174,184,198', C'42,49,61',    C'201,138,0',   C'179,36,59',
      C'6,122,92',    C'19,50,94',    C'94,58,153',   C'0,99,107',    C'255,201,163', C'240,242,247', C'154,164,178', C'5,7,10',
      C'232,237,245', C'61,70,97',    C'0,163,163',   C'180,83,9',    C'124,58,237',  C'219,39,119',  C'21,128,61',   C'14,165,233',
      C'253,230,138', C'252,165,165', C'167,243,208', C'191,219,254', C'221,214,254', C'103,232,249', C'253,186,116', C'229,231,235',
      C'17,24,39',    C'55,65,81',    C'107,114,128', C'156,163,175', C'209,213,219', C'110,231,183', C'251,191,36',  C'124,45,18'
   };
   if(row < 0 || row >= BIOPICK_ROWS) return clrNONE;
   if(col < 0 || col >= BIOPICK_COLS) return clrNONE;
   return pal[row*BIOPICK_COLS + col];
}
color BioPickAt(const int i)
{
   if(i < 0 || i >= BIOPICK_N) return clrNONE;
   return BioPickColor(i / BIOPICK_COLS, i % BIOPICK_COLS);
}
//--- P-DRAW-24's quick row survives as the table's FIRST row: one table, so a
//--- reorder of the quick row can no longer disagree with the pickers.
#define BIOPAL_N BIOPICK_COLS
color BioPal(const int i)
{
   if(i < 0 || i >= BIOPAL_N) return clrBlack;
   return BioPickColor(0, i);
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-69b (2026-09-25) — THE INK HAS ONE OWNER, AND THE SWATCH FLOOR MOVES
// DOWN WITH IT.
//
// `BioPal` above is the palette's one owner, and THIS file is include #1 in
// every entry (Biotak Trigger TH3.mq4 line 26) — the only address a rule can
// have that BOTH the drawing strip (include 97) and the settings cards
// (include 116) obey. The ink used to be quoted twice: `PNL_CLR_*`
// (BiotakPanels) and `DSTRIP_CLR_*` (DrawStrip), nine of them byte-for-byte
// identical. Two tables that agree today are two tables that disagree
// tomorrow, so the ink lives here now and both old families are ALIASES:
// same names, same call sites, one literal each.
//
// P-UI-34 made the same move for the text metrics (`PnlPt`/`PnlTextW` left
// BiotakPanels for UtilityFunctions): a rule the surfaces NEEDING it most
// cannot see gets copied. And a copied swatch floor is exactly how the strip's
// own colour grids went on painting #141414 on #1D222C through a 1.04:1
// hairline — the "empty slot" the user reports as «رنگ ها کار نمیکنه» — the
// same report P-UI-69 closed on the cards eleven days earlier.
// ══════════════════════════════════════════════════════════════════════════
#define BIO_CLR_INK        C'243,246,251'   // #F3F6FB --title / --val
#define BIO_CLR_MUTED      C'140,150,166'   // #8C96A6 --muted (+ the swatch outline)
#define BIO_CLR_LABEL      C'203,212,226'   // #CBD4E2 --lbl
#define BIO_CLR_ACCENT     C'255,194,71'    // #FFC247 --a1 (gold ramp top)
#define BIO_CLR_ACCENT_INK C'26,18,6'       // #1A1206 --aInk on the primary
#define BIO_CLR_HAIRLINE   C'34,40,50'      // #222832 rows/controls — NOT a text ink
#define BIO_CLR_FIELD      C'24,29,39'      // #181D27 edit fields + popover faces
#define BIO_CLR_FIELD_BD   C'51,60,76'      // #333C4C edit/DD rims
#define BIO_CLR_CARD       C'29,34,44'      // #1D222C card + plate body
#define BIO_CLR_FOOT       C'18,22,29'      // #12161D card footer
#define BIO_CLR_PANEL      C'23,28,37'      // #171C25 strip / popover body
#define BIO_CLR_ACCENT2    C'255,138,0'     // #FF8A00 gold ramp bottom
#define BIO_CLR_DEEP       C'18,22,33'      // deep navy ink — the ring badge's ink, the
                                            // retired box badge's rim and the TH3 readout
                                            // plate's own fill. Pasted at all three before
                                            // P-UI-117 gave it a name (one value, one owner).
#define BIO_CLR_ON_LIGHT   C'150,70,0'      // deep amber — the readable ink on a LIGHT chart
                                            // background. Was pasted twice, next to a second
                                            // copy of the gate below (P-UI-117).
#define BIO_BG_LUM_THRESHOLD 128            // the ONE boundary of "this background is light":
                                            // ask BioChartBgIsLight(), never re-derive it.

//+------------------------------------------------------------------+
//| P-UI-117 — THE READABLE-INK GATE, ONE OWNER (A-05/A-10/A-12).     |
//|                                                                  |
//| Two surfaces ask the same question — "is this chart's background |
//| light?" — and each answered with its own copy of the same        |
//| 299/587/114 luminance arithmetic AND its own `C'150,70,0'`        |
//| (BaseKnotTool's corner hint, `BaseKnotFgForBg`, and               |
//| RuntimeSettings' `GetBKTextRenderColor`). A palette change could  |
//| only ever fix one of the two, and the second copy was already     |
//| annotated "same luminance gate as the INFO label" — the comment   |
//| knew, which is exactly the shape A-10 names.                      |
//|                                                                  |
//| The owner lives HERE because `ConstantsAndEnums` is included      |
//| before `RuntimeSettings` (43) and before every UI file, so both    |
//| readers can reach it — and, per A-12, neither may copy it up.      |
//|                                                                  |
//| The decision itself stays with the caller: the hint wears brand    |
//| amber on a dark chart and `BIO_CLR_ON_LIGHT` on a light one; the   |
//| box user text keeps the colour the user picked and only FACTORY    |
//| WHITE is routed to the readable ink (an explicit pick is honoured  |
//| untouched).                                                        |
//+------------------------------------------------------------------+
bool BioChartBgIsLight()
{
   static color s_bg = clrNONE;
   static bool  s_light = false;
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   if(bg != s_bg)
   {
      s_bg = bg;
      int lum = ((((int)bg) & 0xFF) * 299 + ((((int)bg) >> 8) & 0xFF) * 587 +
                 ((((int)bg) >> 16) & 0xFF) * 114) / 1000;
      s_light = (lum > BIO_BG_LUM_THRESHOLD);
   }
   return s_light;
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-69 (2026-09-14) — A SWATCH THAT IS THE BACKDROP'S OWN COLOUR IS A HOLE.
// MOVED here by P-UI-69b; the VALUES are unchanged, only the address is — the
// strip could not reach a floor that lived 19 includes above it.
//
// User report: «رنگ ها کار نمیکنه». The colour row read as seven swatches and
// one EMPTY SLOT, and tapping the "slot" applied a near-black that then
// vanished on the chart. Measured from the shipped screenshot, not recalled:
// QuickPalColor(7) = #141414 (20,20,20) painted on the card face #1A2029
// (26,32,41) with a PNL_CLR_LINE border #222832 (34,40,50) — contrast 1.05:1
// for the fill and 1.11:1 for the border. P-UI-68 closed exactly this trap one
// layer down (a colour STRIP cell whose target was clrNONE painted ink-black);
// the quick strip, the palette's own swatches and the strip cells still had it.
//
// ONE owner for "will this swatch be visible on its own backdrop?", used by
// every swatch family (quick strip, preview block, palette matrix, recents,
// strip cells, the palette's current-colour block, AND the drawing strip's own
// colour grids). Under the threshold the swatch keeps its COLOUR — fidelity
// matters, the user asked for black — and gains a border that contrasts, so
// the affordance can never read as empty.
// ══════════════════════════════════════════════════════════════════════════
//--- The floor is MEASURED, not chosen: over the 198 colours the panel could then
//--- paint as a swatch (the 8 quick ones + the retired 190-cell matrix), the
//--- shipped build had ELEVEN indistinguishable from the face they sit on —
//--- from 1.05:1 to
//--- 1.68:1 — and the first genuinely visible tone was 1.72:1. The boundary sits
//--- in that gap, so "add an outline" fires on exactly the swatches that read as
//--- empty space and on nothing else (WCAG's stricter 3:1 for non-text UI is NOT
//--- enforced: the card's own subtle border is the design language for every
//--- visible swatch, and raising the floor would re-outline half the palette).
#define BIO_SWATCH_MIN_CONTRAST 1.7

//--- WCAG relative luminance (Rec.709 over linearised channels). MT4 packs a
//--- colour BGR, so R is the LOW byte — the same extraction PalColorText uses.
//--- clrNONE (-1) has no channels: reported as white, so a stray value can never
//--- pass the threshold by accident.
double BioLum(const color c)
{
   // `color` is UNSIGNED in MQL4, so `c < 0` is always false (warning 65): a
   // stray clrNONE only shows up once the value is seen as a signed int.
   int v=(int)c;
   if(v < 0) return 1.0;
   int cr=v%256, cg=(v/256)%256, cb=v/65536;
   double r=(double)cr/255.0, g=(double)cg/255.0, b=(double)cb/255.0;
   if(r > 0.03928) r=MathPow((r+0.055)/1.055,2.4); else r=r/12.92;
   if(g > 0.03928) g=MathPow((g+0.055)/1.055,2.4); else g=g/12.92;
   if(b > 0.03928) b=MathPow((b+0.055)/1.055,2.4); else b=b/12.92;
   return 0.2126*r + 0.7152*g + 0.0722*b;
}

//--- contrast ratio between two colours (1.0 = identical, 21.0 = black|white)
double BioContrast(const color a,const color b)
{
   double la=BioLum(a), lb=BioLum(b);
   double hi=MathMax(la,lb), lo=MathMin(la,lb);
   return (hi+0.05)/(lo+0.05);
}

//--- the border a swatch of `fill` must carry on `backdrop`. The SELECTION ring
//--- is the caller's business (it passes the accent); this is the legibility
//--- floor that keeps every swatch visible whatever colour it holds.
color BioSwatchBorder(const color fill,const color backdrop)
{
   return (BioContrast(fill,backdrop) < BIO_SWATCH_MIN_CONTRAST)
             ? BIO_CLR_MUTED : BIO_CLR_HAIRLINE;
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-131f/g — THE 3D EDGE, ONE OWNER, ANCHORED TO ITS OWN SURFACE.
//
// A zone's edge is ALREADY three objects (`_B_Top`/`_B_Bottom`/`_B_Left`,
// ZoneFactory), so a bevel costs NO new object and NO extra draw call: the SAME
// three lines wear a LIT and a SHADED tone. What v1 got wrong is the ANCHOR — a
// fixed 0.38 toward white/black ignores what the line lies ON, so a band washed
// toward a light chart had no room above it and its "lit" half walked into its own
// fill (measured 1.44 against 5.05: one border read as if IT carried the
// transparency). The tones are therefore anchored to the SURFACE, and the two
// halves are pulled apart on whichever side that surface leaves free.
// ══════════════════════════════════════════════════════════════════════════
#define BIO_EDGE_CONTRAST 2.00   // the SHADOW half reads by LUMA, so it carries the floor
#define BIO_EDGE_LIT_MIN  1.40   // the HIGHLIGHT reads by CHROMA - luma understates it
#define BIO_EDGE_CHROMA   1.55   // the lit tone's chroma gain (free on a pale fill)
#define BIO_EDGE_TOPUP    0.35   // one push until the two halves separate from each other
#define BIO_EDGE_STEP_N   4
#define BIO_EDGE_MEMO_N   16

double BIO_EDGE_STEP[BIO_EDGE_STEP_N] = {0.20, 0.32, 0.46, 0.60};

//--- one per-channel mix: `t` 0 = a, 1 = b. The owner of the arithmetic both bevel
//--- tones (and any future tone) go through, in the palette's BGR packing.
color BioMixColor(const color a,const color b,const double t)
{
   int k  = (int)MathRound(MathMax(0.0, MathMin(1.0, t)) * 100.0);
   int ar = (int)a & 0xFF, ag = ((int)a >> 8) & 0xFF, ab = ((int)a >> 16) & 0xFF;
   int br = (int)b & 0xFF, bg = ((int)b >> 8) & 0xFF, bb = ((int)b >> 16) & 0xFF;
   int r  = (ar * (100 - k) + br * k) / 100;
   int g  = (ag * (100 - k) + bg * k) / 100;
   int bl = (ab * (100 - k) + bb * k) / 100;
   return (color)(r | (g << 8) | (bl << 16));
}

//--- the same colour further from its own grey. Chroma is the one axis a pale
//--- surface cannot take away, so the LIT tone starts here (P-UI-131g).
color BioChroma(const color c,const double k)
{
   int r = (int)c & 0xFF, g = ((int)c >> 8) & 0xFF, b = ((int)c >> 16) & 0xFF;
   double m = (r + g + b) / 3.0;
   int rr = (int)MathRound(m + (r - m) * k);
   int gg = (int)MathRound(m + (g - m) * k);
   int bb = (int)MathRound(m + (b - m) * k);
   return (color)(MathMax(0,MathMin(255,rr)) | (MathMax(0,MathMin(255,gg)) << 8) |
                  (MathMax(0,MathMin(255,bb)) << 16));
}

//--- the tone of this edge toward `target`: the CHROMA one if it already reads, else
//--- the WEAKEST step that does, else the strongest of the lot. Walking toward white
//--- moves TOWARD a pale surface rather than away from it, so "first step that fails"
//--- must never mean "keep walking": the best tone is what is kept (P-UI-131g).
color BioEdgeTone(const color base,const color under,const color target,const double floorC)
{
   color c = BioChroma(base, BIO_EDGE_CHROMA);
   color best = c;
   double bestC = BioContrast(c, under);
   if(bestC >= floorC) return c;
   for(int i = 0; i < BIO_EDGE_STEP_N; i++)
   {
      color t = BioMixColor(c, target, BIO_EDGE_STEP[i]);
      double ct = BioContrast(t, under);
      if(ct >= floorC) return t;
      if(ct > bestC) { bestC = ct; best = t; }
   }
   return best;
}

//--- the two tones of one zone edge: LIT for `_B_Top`/`_B_Left`, SHADED for `_B_Bottom`.
//--- Memoised on (base, under) — the ladder runs once per colour PAIR, not once per zone
//--- per render; a hit is one key compare. `under` is the band when there is one and the
//--- chart's background otherwise, which is exactly what the line lies on.
void BioZoneEdgeTones(const color base,const color under,color &lit,color &shade)
{
   static int   s_key[BIO_EDGE_MEMO_N];
   static bool  s_used[BIO_EDGE_MEMO_N];
   static color s_lit[BIO_EDGE_MEMO_N], s_shade[BIO_EDGE_MEMO_N];
   int k = (int)base * 31 + (int)under;
   int slot = (int)MathAbs(k % BIO_EDGE_MEMO_N);
   for(int i = 0; i < BIO_EDGE_MEMO_N; i++)
   {
      int j = (slot + i) % BIO_EDGE_MEMO_N;
      if(!s_used[j]) { slot = j; break; }
      if(s_key[j] == k) { lit = s_lit[j]; shade = s_shade[j]; return; }
   }
   lit   = BioEdgeTone(base, under, clrWhite, BIO_EDGE_LIT_MIN);
   shade = BioEdgeTone(base, under, clrBlack, BIO_EDGE_CONTRAST);
   // The halves must also separate from EACH OTHER — that is the bevel — pushed into the
   // side the surface leaves free: above a BRIGHT surface the shadow, below a DARK one
   // the light, so light-from-the-top-left holds on a light chart and a dark one alike.
   bool pushShade = (BioLum(under) >= 0.5);
   for(int i = 0; i < BIO_EDGE_STEP_N && BioContrast(lit, shade) < BIO_SWATCH_MIN_CONTRAST; i++)
   {
      if(pushShade) shade = BioMixColor(shade, clrBlack, BIO_EDGE_TOPUP);
      else          lit   = BioMixColor(lit,   clrWhite, BIO_EDGE_TOPUP);
   }
   s_key[slot] = k; s_used[slot] = true; s_lit[slot] = lit; s_shade[slot] = shade;
}

#endif // CONSTANTS_AND_ENUMS_MQH
