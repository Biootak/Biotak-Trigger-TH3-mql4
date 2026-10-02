// BiotakPanels_State.mqh - BiotakPanels split 2026-09-29: exact lines 262-1097 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_STATE_MQH
#define BIOTAK_PANELS_STATE_MQH


//--- P-DRAW-116: the geometry and ink table is CardMetrics.mqh now, so the strip's
//--- settings panel (include 99, this file 118) can reach the SAME numbers instead of
//--- retyping them. The block is moved verbatim, not rewritten - zero renumber.
#include "CardMetrics.mqh"

// ══════════════════════════════════════════════════════════════════════════
// P-UI-69b (2026-09-25) — THE SWATCH FLOOR MOVED DOWN, NOT AWAY.
//
// The owner is now `BioSwatchBorder()` / `BIO_SWATCH_MIN_CONTRAST` in
// ConstantsAndEnums.mqh (include #1), because the drawing strip's OWN colour
// grids could not reach a floor that lived here (include 116 vs DrawStrip's
// 97) — and a rule you cannot reach is a rule that gets copied. The measured
// story of the user's «رنگ ها کار نمیکنه» (P-UI-69, 2026-09-14) and the 198-
// colour measurement that set the 1.7 boundary are kept THERE, with the value.
//
// The `Pnl*` names below are FACES of that owner: same rule, one
// implementation, no second threshold. Never re-derive the arithmetic here.
// ══════════════════════════════════════════════════════════════════════════
#define PNL_SWATCH_MIN_CONTRAST BIO_SWATCH_MIN_CONTRAST

//--- The floor's FACES (P-UI-69b). The owner is `BioLum` / `BioContrast` /
//--- `BioSwatchBorder` in ConstantsAndEnums.mqh — these three names keep the
//--- panel's call sites, exactly as `QuickPalColor` is a face of `BioPal` (and
//--- P-DRAW-46 made `BioPal` itself the face of `BioPickColor`'s first row).
//--- One implementation, never a second.
double PnlLum(const color c)                        { return BioLum(c); }
color  PnlSwatchBorder(const color fill,const color backdrop) { return BioSwatchBorder(fill,backdrop); }

// ══════════════════════════════════════════════════════════════════════════
// R-PANELUI2 (2026-09-11) — the 13-card redesign of
// panel_all_redesign_preview.html. The preview is the SPEC; every number
// below is taken from its CSS, never re-derived:
//   .gl 22px chip (+2px antialias pad baked into the BMP)   .mark 30px (+7 glow pad)
//   .sw 40x22 pill (+6 glow pad, both states)  .val.chip 46x22  .key 18x18
//   .x 26x26              .card::before 3px    .row.sec band / .rail 2px / .secdot 6px (+4)
// OBJ_BITMAP_LABEL always renders at NATIVE canvas size, so every bitmap
// object is placed at (realX - PAD, realY - PAD) with its own PNL_*_PAD twin
// of the generator pad (uiBox o.pad) — a twin one px short clips the glow
// and the control reads flat next to the preview.
// ══════════════════════════════════════════════════════════════════════════

//--- accent families — the SAME six the generator bakes (tools/gen-th3-icons.js
//--- ACCENTS / A2 / A_INK). body is always obsidian; only the accent changes.
#define PNL_ACC_N 6
#define PNL_A_GOLD   0
#define PNL_A_JADE   1
#define PNL_A_CYAN   2
#define PNL_A_VIOLET 3
#define PNL_A_EMBER  4
#define PNL_A_ROSE   5

#define PNL_ROW_GAP   10      // preview .row flex gap: label group | control
// ── UI TEXT METRICS moved to Biotak/UtilityFunctions.mqh (P-UI-34): the ring menu
// ── and its hover tooltip are INCLUDED BEFORE this file, so the owner has to sit below them.

string PnlAccentName(const int a)
{
   if(a==PNL_A_JADE)   return "jade";
   if(a==PNL_A_CYAN)   return "cyan";
   if(a==PNL_A_VIOLET) return "violet";
   if(a==PNL_A_EMBER)  return "ember";
   if(a==PNL_A_ROSE)   return "rose";
   return "gold";
}
color PnlAccentA1(const int a)   // --a1 (light stop)
{
   if(a==PNL_A_JADE)   return C'99,236,189';
   if(a==PNL_A_CYAN)   return C'121,220,255';
   if(a==PNL_A_VIOLET) return C'188,166,255';
   if(a==PNL_A_EMBER)  return C'255,192,140';
   if(a==PNL_A_ROSE)   return C'255,167,182';
   return C'255,194,71';
}
color PnlAccentA2(const int a)   // --a2 (deep stop)
{
   if(a==PNL_A_JADE)   return C'18,184,134';
   if(a==PNL_A_CYAN)   return C'31,168,224';
   if(a==PNL_A_VIOLET) return C'124,92,255';
   if(a==PNL_A_EMBER)  return C'255,106,43';
   if(a==PNL_A_ROSE)   return C'240,69,95';
   return C'255,138,0';
}
color PnlAccentInk(const int a)  // --aInk (text ON the accent ramp)
{
   if(a==PNL_A_JADE)   return C'4,20,15';
   if(a==PNL_A_CYAN)   return C'4,18,26';
   if(a==PNL_A_VIOLET) return C'12,7,34';
   if(a==PNL_A_EMBER)  return C'26,10,3';
   if(a==PNL_A_ROSE)   return C'28,4,9';
   return C'26,18,6';
}

//--- card -> accent family. R-GOLDALL (2026-09-11, user order): EVERY card
//--- speaks the TRex gold ramp (#FFC247 -> #FF8A00) — the per-card families
//--- (cyan/jade/violet/ember) are retired. All chrome (mark, switches,
//--- chips, bands, topbar, footer Done, dropdown pills) derives from here,
//--- so one line repaints every panel; gold skins already exist for all
//--- chrome, no regen needed. Object NAMES carry no accent, so open charts
//--- just repaint gold on next open — no orphans, no purge change.
int PnlCardAccent(const int item)
{
   return PNL_A_GOLD;        // every card: one brand accent everywhere
}
string PnlAccentRes(const int item,const string stem)
{
   return "::Files\\Icons\\" + stem + "_" + PnlAccentName(PnlCardAccent(item)) + ".bmp";
}
// WIDE: full-width chrome has a W twin (pnl_topbarW_<a>, pnl_hairW_<a>).
string PnlWideAccentRes(const int item,const string stem,const bool wide)
{
   if(!wide) return PnlAccentRes(item,stem);
   return "::Files\\Icons\\" + stem + "W_" + PnlAccentName(PnlCardAccent(item)) + ".bmp";
}

//--- --aSoft / --aBd, already composited over the obsidian card body. MT4
//--- buttons and labels have no alpha channel, so the header's number badge
//--- cannot use rgba() — the blend is precomputed per accent instead.
//--- (card body ≈ #1D222C; soft = accent .12, bd = accent .40)
color PnlAccentSoft(const int a)
{
   if(a==PNL_A_JADE)   return C'28,52,55';
   if(a==PNL_A_CYAN)   return C'29,50,66';
   if(a==PNL_A_VIOLET) return C'40,41,69';
   if(a==PNL_A_EMBER)  return C'56,43,44';
   if(a==PNL_A_ROSE)   return C'54,38,50';
   return C'56,53,47';
}
color PnlAccentBd(const int a)
{
   if(a==PNL_A_JADE)   return C'25,94,80';
   if(a==PNL_A_CYAN)   return C'30,88,116';
   if(a==PNL_A_VIOLET) return C'67,57,128';
   if(a==PNL_A_EMBER)  return C'119,63,44';
   if(a==PNL_A_ROSE)   return C'113,48,64';
   return C'119,98,55';
}

//--- the header's .mark glyph + subtitle live further down (PnlMarkIcon /
//--- PnlHeaderSub) — they read g_BkTab, which is declared with the Base Box
//--- card state, so MQL4's declare-before-use forces them below it.

//--- the card-level hotkey shown as a .key cap in the header (preview CARDS[].key)
string PnlCardKey(const int item)
{
   if(item==0) return "T";
   if(item==7) return "L";
   return "";
}

//--- does this card carry the preview's .fade (the 26px wash just above the
//--- footer)? Only the scrollable cards do — preview CARDS[].fade. The card skin
//--- is chosen by ROW COUNT, and cards sharing a row count disagree (item 0 has
//--- fade, item 8 does not, both 6 rows), so the fade is a second skin variant:
//--- pnl_card<N>f.bmp instead of pnl_card<N>.bmp.
bool PnlCardFade(const int item)
{
   return (item==0 || item==1 || item==2 || item==6 || item==9);
}


//--- chrome metrics (preview CSS)
#define PNL_CHIP_VIS     22      // .gl width/height
#define PNL_CHIP_PAD     2       // antialias pad baked into pnl_chip*.bmp
#define PNL_CHIP_CANVAS  26
#define PNL_CHIP_Y       ((PNL_ROW_H-PNL_CHIP_VIS)/2)            // 10
//--- SLIDER rows (preview .row.sl/.sltop): label + chip sit on the TOP line so
//--- the full-width track below stays clear — a centred chip would cover the
//--- track's first 24px and collide with the knob at 0% (P-UI-30).
#define PNL_CHIP_Y_SL    1       // P-UI-131d: canvas 1..27 — the visible chip (3..25)
                                 // clears the track at 29 instead of resting on it
#define PNL_GLYPH_VIS    13      // .gl svg
#define PNL_GLYPH_PAD    1
#define PNL_GLYPH_CANVAS 15
#define PNL_MARK_VIS     30      // .mark
#define PNL_MARK_PAD     7       // holds the .mark glow (~2 sigma); twin of markSkin pad
#define PNL_MARK_Y       13      // centred in the 56px header
#define PNL_SW_W         40      // .sw
#define PNL_SW_H         22
#define PNL_SW_PAD       6       // holds the ON glow; OFF shares the canvas — twin of swSkin P
#define PNL_SECDOT_VIS   6       // .row.sec .sl i
#define PNL_SECDOT_PAD   4       // holds the dot glow — twin of secDotSkin pad
#define PNL_SW_X         (PNL_WEL-PNL_PAD_X-PNL_SW_W)      // right-aligned
#define PNL_SW_Y         ((PNL_ROW_H-PNL_SW_H)/2)          // 10
#define PNL_VCHIP_W      46      // .val.chip
#define PNL_VCHIP_H      22
#define PNL_VCHIP_PAD    2
#define PNL_VCHIP_Y      1       // P-UI-131d: rides the caption line, moved up 1
#define PNL_KEYCAP_VIS   18      // .key  (the visible cap body)
#define PNL_KEYCAP_PAD   2       // antialias pad baked into pnl_keycap.bmp
#define PNL_KEYCAP_CANVAS 22     // VIS + 2*PAD — the bitmap's own size
#define PNL_KEY_H        16      // keycap glyph area (9px Arial Bold letter)
#define PNL_XBTN_VIS     26      // .x
#define PNL_XBTN_PAD     2
#define PNL_FT_BTN_H     28      // .ft .btn
#define PNL_FT_BTN_W     74      // text-only part (the glyph rides left of it)
#define PNL_TICK_N       9       // .ticks i count
#define PNL_TICK_Y       37      // 1px under the track at PNL_TRK_Y (moved down 2),
                                 // so the rail still clears the row's floor by 3px
#define PNL_DUAL_SW_W    34      // .dual .sw
#define PNL_DUAL_SW_H    19
#define PNL_CSET_W       38      // .ccell i
#define PNL_CSET_H       20
#define PNL_CSET_GAP     6
#define PNL_SEC_CNT_W    24      // .row.sec .cnt pill
//--- tallest NARROW card skin the generator bakes (tools/gen-th3-icons.js
//--- PNL_CARD_ROWS_MAX). Narrow cards are those below PNL_WIDE_MIN_ROWS rows,
//--- so the clamp can never exceed 10 — anything longer is WIDE and its body
//--- is composed (P-UI-71b) from pnl_cardWtop/mid/bot/fade, because the baked
//--- bound used to bite: the old wide skins stopped at PNL_WIDE_ROWS_MAX and
//--- the rows past that drew on the chart with no card behind them.
//--- ICON-DIET 2026-09-27: 11..16 (+f) follow 17..20, 11.4 MB, same reason — the
//--- baked lookup lives only in the !wide branch, where rowsCount <= 10.
#define PNL_CARD_ROWS_MAX 10

//--- P-UI-71b: the WIDE card body is composed from three sliced pieces, so its
//--- height no longer depends on which skins were baked. Sliced from a baked
//--- skin by tools/slice-card-skins.py (which asserts the composition tiles and
//--- leaves no hole); the gate asserts these numbers still match it.
#define PNL_CARD_TOP_H   (PNL_MARGIN + PNL_HEAD_H)   // 70  margin + header
#define PNL_CARD_BOT_H   (PNL_FOOT_H + PNL_MARGIN)   // 62  footer + margin
#define PNL_FADE_H       26                          // .fade wash height

//--- display row kinds (superset of the legacy setting kinds; PnlRowDef
//--- returns one of these for every DISPLAY row)
#define PNL_K_SL     0    // slider (label + value chip + track + ticks)
#define PNL_K_SW     1    // switch row (icon chip + label + 40x22 pill)
#define PNL_K_SEG    2    // segmented pills / tab underline / dropdown select
#define PNL_K_COL    4    // colour row (preview + 8 swatches + "+")
#define PNL_K_NAV    5    // NAV row -> another card
#define PNL_K_TXT    6    // OBJ_EDIT text field
#define PNL_K_SEC    7    // SECTION BAND — itself a 42px row (hit maths intact)
#define PNL_K_CSET   8    // N colours in ONE 42px row (preview .cset)
#define PNL_K_DUAL   9    // two switches in one 42px row (preview .dual)
#define PNL_K_LEGACY (-1) // "whatever the setting's own def says"

//--- P-UI-67: the SS/LS sequence-order caption. ONE string, because the row is
//--- rendered from two places (the Step card's SS-LS ENGINE section builds its
//--- own descriptor BEFORE `PnlSetDef` exists — MQL4 is define-before-use — and
//--- the setting's own def names it too). Two spellings is how "LS FIRST" ended
//--- up naming the switch's ON state on a switch that can also be OFF: the label
//--- names the QUESTION (OFF = SS first · ON = LS first), never the answer.
#define PNL_LBL_SSLS_ORDER  "SS/LS ORDER"

//--- colour swatch row geometry (preview .q / .prev / .q.add):
//---   46 + 8*22 + 9*4 = 280 = exactly the content width. Never widen it.
//--- (was 6 swatches at a 5px gap; the redesign spends the freed 9px on two
//---  more swatches + the "+" button. R-PANELUI2 2026-09-11.)
#define PNL_QSW_ADD   22

// Row counts per settings panel. State lives in BiotakKit.mqh.
// 0 Trigger Zones (zones-only, 4 → 5 rows — P-UI-131j: the trigger LABEL got its
//   own OPACITY row beside its long-dead COLOUR row) · 1 ZONES & LEVELS (main card)
// 2 ATR · 3 TH · 4 HOVER CHIP (P-UI-126 — the retired View Lock slot, revived) ·
// 5 TH3 · 6 HTF · 7 LINES (unified [08.4] line appearance)
// 8 CustomPrice · 9 StepMode (mode + selected mode's rows + levels, dynamic —
// see PnlStepSectionRows) · 10 Factor · 11 STRUCTURE (sub-card)
// (g_PnlRows[4] was kept =1 dormant through VIEWLOCK-OFF so the panel keys stayed
// stable — that is exactly the budget this card spends, so nothing renumbered.)
// STEPOVERRIDE-OFF: g_PnlRows[9] 3→2 (OVERRIDE row retired; rows inside a card
// are positional — CALC MODE was row 0, MAX LEVELS row 1 back then).
// STEPSECTIONS: g_PnlRows[9] is only the BASE (2); PnlRowsCount(9) returns
// 2 + the selected mode's section rows (TH 0 / SS-LS 1 / Combo 8 / Factor 7),
// so MAX LEVELS floats to PnlStepMaxLevelsRow(). Never hardcode card-9 rows.
// (PNL_COUNT lives in BiotakKit.mqh — Kit is included first.)
// [2] ATR LABELS: 7 → 11 on 2026-09-11 — the countdown tag's OWN rows sit on
// top (switch/color/size/gap), then the ATR block's rows unchanged.
// P-TH-01: [3] TH 5 → 6 — the TH-percentage research knob is setting index 5
// (the address is APPENDED, so nothing above it moved).
// P-UI-126: [1] 11 → 12 (the HOVER CHIP NAV row, APPENDED — nothing renumbered) and
// [4] revived at its own dormant 1 (the chip's card, reached from that NAV row).
// P-UI-131h: [1] 14 → 18 — the MID ZONE EDGE's two halves each got a COLOUR row and an
// OPACITY row (addresses 14..17, APPENDED inside the GEOMETRY band, which goes 4 → 8
// members). The card reads 15 → 19 display rows, still far inside PNL_SPEC_MAX 32, and a
// wide card stays wide (it was already above PNL_WIDE_MIN_ROWS 10).
// P-UI-131: [1] 13 → 14 (the GENERAL NAV row, APPENDED) and [14] added — the
// GENERAL SETTINGS card (15 addresses in 4 bands, reached from that NAV row and
// from the TOOLS sub-menu's third cell). Nothing else renumbered: [9] stays 2,
// because MAX LEVELS left only card 9's DISPLAY (its address keeps its branch),
// and [2]/[3] keep their numbers the same way while TRADE CARD and MARGIN BOTTOM
// left THEIR displays. The moved rows never took a setting with them.
int g_PnlRows[PNL_COUNT] = {5,18,11,6,1,8,11,6,4,2,7,7,1,7,15};

// g_PnlRows[12] is the BASE (TAB row only) — PnlRowsCount(12) returns
// 1 + the open tab's section rows (6 each tab), the same dynamic pattern
// as the Step card 9. Never hardcode card-12 rows.
int g_PnlOpen      = -1;
//--- Base Box card (12) TAB state — 0 Style · 1 Text · 2 Setup (TV-parity
//--- 2026-09-07: mirrors TV's Style/Text dialog tabs; the card keeps the last
//--- open tab across opens, like the Step card keeps its mode section).
static int g_BkTab = 0;

//--- header .mark glyph + subtitle (preview CARDS[].mi / CARDS[].s). They sit
//--- here, not next to PnlCardAccent, because they read g_BkTab above and MQL4
//--- needs the declaration first. R-PANELUI2.
string PnlMarkIcon(const int item)
{
   if(item==0)  return "crosshair";
   if(item==1)  return "layers";
   if(item==2)  return "gauge";
   if(item==3)  return "wave";
   if(item==6)  return "candle";
   if(item==7)  return "line";
   if(item==8)  return "pin";
   if(item==9)  return "steps";
   if(item==10) return "sigma";
   if(item==11) return "steps";
   // P-UI-131: a frame with a header — the card is the cross-card surface, and
   // "steps"/"layers" already mark the Step and Zones cards.
   if(item==14) return "template";
   if(item==12)                       // Base Box — the mark follows the tab
   {
      if(g_BkTab==1) return "type";
      if(g_BkTab==2) return "target";
      return "box";
   }
   return "";
}
string PnlHeaderSub(const int item)
{
   if(item==0)  return "ZONE OVERLAY · LINES LIVE ON LINES";
   if(item==1)  return "MID ZONES · UNIFIED LINES · STRUCTURE";
   if(item==2)  return "COUNTDOWN · ATR BLOCK · TRADE PLAN";
   if(item==3)  return "FRACTAL · STANDARD · TARGETS";
   if(item==6)  return "HIGHER TIMEFRAME OVERLAY";
   if(item==7)  return "ONE STYLE FOR ALL LINES";
   if(item==8)  return "PIN · WIDTH + COLOR";   // P-UI-47: MAGNET retired (BKMAGNET-OFF); BKMAGNET2-OFF keeps it retired
   if(item==9)  return "ENGINE · SECTION SWAPS WITH MODE";
   if(item==10) return "AUTO / MANUAL STEP ENGINE";
   if(item==11) return "L1 - L5 ZONE TOGGLES";
   if(item==14) return "ENGINE · LABEL GRID · TRADE CARD · INTERFACE";   // P-UI-131
   if(item==12)                       // Base Box — the subtitle follows the tab
   {
      if(g_BkTab==1) return "TEXT TAB · OBJ_EDIT FIELD";
      if(g_BkTab==2) return "SETUP TAB · R:R + LEGS + TEMPLATE";
      return "STYLE TAB · BORDER + FILL";
   }
   return "";
}
// Section row counts (WITHOUT the TAB row 0): Style 6 · Text 6 · Setup 7
// (P-BK-27 added INFO SIZE to Setup) — tallest is 8 rows total, and the card
// skins are baked for up to card16, so no new asset is needed. Returns the
// MAX a skin carries (card16 bake); a tab's real length is the display spec (PnlSpecRows).

//--- display name for a line-style index (panel value text)
string StyleName(const int idx)
{
   switch(idx)
   {
      case ILS_DASH:         return "Dash";
      case ILS_DOT:          return "Dot";
      case ILS_DASH_DOT:     return "Dash-Dot";
      case ILS_DASH_DOT_DOT: return "Dash-Dot-Dot";
   }
   return "Solid";
}

//--- true for the STYLE rows (value text = style name). DISPLAY-row keyed.
bool PnlIsStyleRow(const int item,const int row)
{
   // Only native line-style rows need the style-name value text.
   // (The Zones card's BORDER row renders its own option names and must NOT
   //  match here.)
   int s = PnlSetRow(item,row);
   if(s < 0) return false;
   if(item==7 && s==3) return true;        // Lines STYLE
   if(item==12 && s==3 && g_BkTab==0) return true;   // Base Box STYLE (Style tab)
   if(item==10 && s==5) return true;       // Factor STYLE
   if(item==9 && s==6 && (int)g_stepCalculationMode==3) return true;   // Step card Factor STYLE
   return false;
}

//+------------------------------------------------------------------+
//| Palette color picker — target model                               |
//| Every COLOR row on every panel maps to one "palette kind" (the   |
//| PAL_* constants owned by BiotakKit.mqh). The palette popup edits |
//| the kind currently selected (cycle button) and applies the color |
//| live to the chart.                                               |
//+------------------------------------------------------------------+

//--- palette kind of a COLOR row (kind=4), or -1 when the row has none.
//--- DISPLAY-row keyed (translated to the setting row first).
int PnlColorKind(const int item,const int row)
{
   int s = PnlSetRow(item,row);
   if(s < 0) return -1;
   return PnlColorKindSet(item,s);
}
int PnlColorKindSet(const int item,const int row)
{
   // P-UI-131h: the MID ZONE edge's two halves (the rows the palette edits).
   if(item==1 && row==14) return PAL_ZONE_EDGE_TOP;
   if(item==1 && row==15) return PAL_ZONE_EDGE_BOTTOM;
   if(item==0 && row==1)  return PAL_TRIGGER;
   if(item==0 && row==2)  return PAL_TRIGGER_LABEL;
   if(item==5 && row==5)  return PAL_TH3;
   if(item==5 && row==6)  return PAL_TH3_PIP;
   if(item==6 && row==3)  return PAL_HTF_BULL;
   if(item==6 && row==4)  return PAL_HTF_BEAR;
   if(item==6 && row==5)  return PAL_HTF_WICK;
   if(item==6 && row==6)  return PAL_HTF_BORDER;
   if(item==7 && row==5)  return PAL_LINE;
   if(item==8 && row==1)  return PAL_CUSTOM_PRICE;
   if(item==10 && row==6) return PAL_FACTOR;
   if(item==2 && row==1)  return PAL_COUNTDOWN;   // countdown tag color (own layer)
   // P-UI-70d: the card's five colours, ONE cset row (setting rows 14..18).
   if(item==2 && row>=14 && row<=18) return PAL_ATR_TR + (row-14);
   if(item==12) return BkSecColorKind(row);   // tabbed card — section mapping below
   if(item==13 && row==0) return PAL_BOX;   // Mini BORDER COLOR (same mirror)
   if(item==9 && row==7 && (int)g_stepCalculationMode==3) return PAL_FACTOR;   // Step card Factor COLOR
   return -1;
}

//--- current color behind a palette kind
color PaletteKindColor(const int k)
{
   switch(k)
   {
      case PAL_TRIGGER:        return g_triggerColor;
      case PAL_TRIGGER_LABEL:  return g_triggerLabelColor;
      case PAL_SS:             return g_ssLevelColor;
      case PAL_LS:             return g_lsLevelColor;
      case PAL_TH3:            return g_th3Color;
      case PAL_TH3_PIP:        return g_th3PipTextColor;
      case PAL_HTF_BULL:       return g_HTFBullColor;
      case PAL_HTF_BEAR:       return g_HTFBearColor;
      case PAL_HTF_WICK:       return g_HTFWickColor;
      case PAL_HTF_BORDER:     return g_HTFBorderColor;
      case PAL_COUNTDOWN:      return g_countdownColor;
      case PAL_ATR_TR:         return g_atrTradeTRColor;        // P-UI-70d
      case PAL_ATR_EX:         return g_atrTradeExColor;
      case PAL_ATR_HUNTER:     return g_atrTradeHunterColor;
      case PAL_ATR_TRADE:      return g_atrTradeRowColor;
      case PAL_ATR_SPREAD:     return g_atrTradeSpreadColor;
      case PAL_CUSTOM_PRICE:  return g_customPriceLevelColor;
      case PAL_FACTOR:         return g_factorLevelColor;
      case PAL_LINE:           return g_lineColor;
      case PAL_BOX:            return g_boxBorderColor;
      case PAL_BK_ENTRY:       return g_bkEntryColor;
      case PAL_BK_SL:          return g_bkStopColor;
      case PAL_BK_TP:          return g_bkTargetColor;
      case PAL_BOX_FILL:       return g_boxFillColor;      case PAL_BK_TEXT:       return g_bkTextColor;
      case PAL_ZONE_EDGE_TOP:    return g_zoneEdgeTopColor;      // P-UI-131h
      case PAL_ZONE_EDGE_BOTTOM: return g_zoneEdgeBottomColor;
   }
   return clrNONE;
}

//--- P-UI-68: a colour target that is deliberately UNSET (clrNONE) means
//    "follow something else": WICK COLOR follows the candle's own colour
//    (clrNONE -> candleClr, exactly like BORDER COLOR -> borderClr has always
//    meant "the body's color"). The colour-strip cells painted such a target
//    with clrNONE, which is MT4's value for NONE — so a setting that simply had
//    no override showed up as an INK-BLACK swatch, i.e. the strip read as a
//    colour choice nobody made. The cell now shows the AUTO face (a muted
//    glass tone) so "not set" looks like a state, and the tooltip says which.
color PnlCsetCellColor(const int kind)
{
   if(kind < 0) return PNL_CLR_AUTO_CELL;
   color c = PaletteKindColor(kind);
   if(c == clrNONE) return PNL_CLR_AUTO_CELL;
   return c;
}

//--- current color behind a COLOR row (kind=4)
color PnlRowColor(const int item,const int row)
{
   int k = PnlColorKind(item,row);
   if(k < 0) return clrNONE;
   return PaletteKindColor(k);
}

//--- number of "Apply to" targets (= PAL_BASE_TARGETS from BiotakKit)
int PalTgtCount()
{
   return PAL_BASE_TARGETS;
}

//--- P-UI-131h: the NAME table is wider than the "apply to" ring on purpose. The ring
//--- stops at PAL_BASE_TARGETS (a bulk pick over an AUTO surface only turns AUTO off),
//--- while a palette page opened on a kind above it still has to name its surface —
//--- clamping to the ring put "TRex Spread" in the header while the page edited a zone
//--- edge. Declared BEFORE both maps because MQL4 expands macros top-down: a #define
//--- below its first use is an unknown identifier, not a late binding.
#define PAL_TGT_NAMES_N 27   // = PAL_BASE_TARGETS (25) + the two AUTO edge halves

//--- cycle index t → palette kind
int PalTgtToKind(const int t)
{
   // P-UI-131h: the NAME table's tail (25/26) names the two AUTO edge halves, whose kinds
   // are 26/27 — kind 25 does not exist, so the tail must be MAPPED, not clamped. Clamping
   // it made the cycler label the page "Edge Top" while it edited kind 24 (TRex Spread).
   int k = ClampInt(t, 0, PAL_TGT_NAMES_N - 1);
   return (k <= PAL_BASE_TARGETS - 1) ? k : k + 1;
}

//--- palette kind → its cycle index
int PalTgtIndexOfKind(const int k)
{
   return ClampInt(k, 0, PAL_TGT_NAMES_N - 1);
}

string PalTgtLabel(const int t)
{
   static string names[PAL_TGT_NAMES_N] =
      {
         "Trigger", "Trigger Label", "SS Level", "LS Level",
         "TH3 Line", "TH3 Pip", "HTF Bull", "HTF Bear",
         "HTF Wick", "HTF Border", "Custom Price", "Factor",
         "Lines", "Base Box", "BK Entry", "BK Stop", "BK Target",
         "Base Fill", "BK Text", "Countdown",
         "TRex TR", "TRex ex", "TRex Hunter", "TRex Trade", "TRex Spread",
         // P-UI-131h: named even though they are NOT "apply to" targets — a palette
         // page opened on one of them must say which line it is editing.
         "Edge Top", "Edge Bottom"
      };
   int k = ClampInt(t, 0, PAL_TGT_NAMES_N - 1);
   return names[k];
}

//+------------------------------------------------------------------+
//| Apply a picked color to a palette kind → REFRESH_* flags.         |
//| Every change is also pushed to the recent-colors ring.            |
//+------------------------------------------------------------------+
// P-PERF-52: same-value apply changes nothing on the chart. Before this,
// every hover crossing AND every restore set g_labelsRelayoutNeeded, so the
// next frame deleted and recreated every label (ClearAllLabels) — the card
// flashed through each hovered blue and snapped back on leave. Unchanged now
// costs a compare and REFRESH_NONE; the pixels are already correct.
int PalCardNoChange(const bool remember,const color clr)
{
   if(remember) PushPalRecent(clr);
   return REFRESH_NONE;
}
int PaletteApplyColor(const int kind,const color clr,const bool remember=true)
{
   switch(kind)
   {
      case PAL_TRIGGER:       g_triggerColor = clr; break;
      case PAL_TRIGGER_LABEL: g_triggerLabelColor = clr; break;
      case PAL_SS:            g_ssLevelColor = clr; break;
      case PAL_LS:            g_lsLevelColor = clr; break;
      case PAL_TH3:           g_th3Color = clr; break;
      case PAL_TH3_PIP:       g_th3PipTextColor = clr; break;
      case PAL_HTF_BULL:      g_HTFBullColor = clr; break;
      case PAL_HTF_BEAR:      g_HTFBearColor = clr; break;
      case PAL_HTF_WICK:      g_HTFWickColor = clr; break;
      case PAL_HTF_BORDER:    g_HTFBorderColor = clr; break;
      case PAL_COUNTDOWN:     g_countdownColor = clr; break;
      // P-UI-70d: the trade card is chart-side, so a pick asks for a LABEL
      // relayout and the discrete-action repaint (REFRESH_ALL) - the card's
      // rows are redrawn by that pass, never by a per-property poke here.
      case PAL_ATR_TR:        if(g_atrTradeTRColor == clr) return PalCardNoChange(remember, clr); g_atrTradeTRColor = clr;     g_labelsRelayoutNeeded=true; break;
      case PAL_ATR_EX:        if(g_atrTradeExColor == clr) return PalCardNoChange(remember, clr); g_atrTradeExColor = clr;     g_labelsRelayoutNeeded=true; break;
      case PAL_ATR_HUNTER:    if(g_atrTradeHunterColor == clr) return PalCardNoChange(remember, clr); g_atrTradeHunterColor = clr; g_labelsRelayoutNeeded=true; break;
      case PAL_ATR_TRADE:     if(g_atrTradeRowColor == clr) return PalCardNoChange(remember, clr); g_atrTradeRowColor = clr;    g_labelsRelayoutNeeded=true; break;
      case PAL_ATR_SPREAD:    if(g_atrTradeSpreadColor == clr) return PalCardNoChange(remember, clr); g_atrTradeSpreadColor = clr; g_labelsRelayoutNeeded=true; break;
      case PAL_CUSTOM_PRICE:  g_customPriceLevelColor = clr; break;
      case PAL_FACTOR:        g_factorLevelColor = clr; break;
      case PAL_LINE:          g_lineColor = clr; break;
      case PAL_BOX:           g_boxBorderColor = clr; BaseKnotRestyleAll(); break;
      case PAL_BK_ENTRY:      g_bkEntryColor = clr; BaseKnotRestyleAll(); break;
      case PAL_BK_SL:         g_bkStopColor = clr; BaseKnotRestyleAll(); break;
      case PAL_BK_TP:         g_bkTargetColor = clr; BaseKnotRestyleAll(); break;
      case PAL_BOX_FILL:      g_boxFillColor = clr; BaseKnotRestyleAll(); break;
      case PAL_BK_TEXT:       g_bkTextColor = clr; BaseKnotRestyleAll(); break;
      // P-UI-131h: the edge halves are painted by the ZONE BUILD, so the colour rides
      // REFRESH_BUFFERS like every other level colour - the zones are rebuilt from it,
      // and clrNONE (the palette's no-override cell) puts the half back on AUTO.
      case PAL_ZONE_EDGE_TOP:    g_zoneEdgeTopColor = clr;    break;
      case PAL_ZONE_EDGE_BOTTOM: g_zoneEdgeBottomColor = clr; break;
      default:                return REFRESH_NONE;
   }
   // P-UI-131h: a HOVER PREVIEW is not a choice — pushing it would fill the recents ring
   // with every colour the pointer merely passed over.
   if(remember) PushPalRecent(clr);

   int flags = REFRESH_BUFFERS;
   if(kind==PAL_COUNTDOWN)
   {
      // Own layer: repaint the tag right away; REFRESH_ALL also carries the
      // OV_CDC persist through ApplyRefreshFlags.
      RefreshLiveCountdown();
      flags = REFRESH_ALL;
   }
   else if(kind==PAL_TH3 || kind==PAL_TH3_PIP) flags = REFRESH_TH3;
   else if(kind==PAL_HTF_BULL || kind==PAL_HTF_BEAR ||
           kind==PAL_HTF_WICK || kind==PAL_HTF_BORDER) flags = REFRESH_HTF;
   // P-UI-70d: the trade card lives on the CHART LABEL layer, so a pick must
   // ride the label pass (REFRESH_ALL also carries the label relayout through
   // ApplyRefreshFlags). The default REFRESH_BUFFERS would repaint the levels
   // and leave the card on its old colour until the 2 s pump.
   else if(kind==PAL_ATR_TR || kind==PAL_ATR_EX || kind==PAL_ATR_HUNTER ||
           kind==PAL_ATR_TRADE || kind==PAL_ATR_SPREAD) flags = REFRESH_ALL;
   return flags;
}

//--- apply a picked palette color to the COLOR row's target
int PnlSetColor(const int item,const int row,const color clr)
{
   int k = PnlColorKind(item,row);
   if(k < 0) return REFRESH_NONE;
   return PaletteApplyColor(k, clr);
}

//--- user-facing transparency (%) of a palette kind; -1 = no transparency
//    setting. ONE language everywhere (panel TRANSPARENCY sliders speak it
//    too): 0 = solid, 100 = invisible. Engine internals may store opacity
//    (e.g. g_HTFOpacity) — converted here, so stored values never migrate.
//    (Trigger uses its TRANSPARENCY % directly; Lines ditto.)
int PaletteKindTransparency(const int kind)
{
   switch(kind)
   {
      case PAL_TRIGGER: return g_triggerTransparency;
      case PAL_TRIGGER_LABEL: return g_triggerLabelTransparency;   // P-UI-131j (-1 = AUTO: the track reads --)
      case PAL_LINE:    return g_lineTransparency;
      case PAL_SS:      return g_ssTransparency;
      case PAL_LS:      return g_lsTransparency;
      case PAL_CUSTOM_PRICE: return g_customPriceTransparency;
      case PAL_FACTOR:  return g_factorTransparency;
      case PAL_BOX:     return g_boxBorderTransparency;
      case PAL_BOX_FILL: return g_boxFillTransparency;
      // P-UI-131h: the two edge halves answer here as well as on their own rows — the
      // popover's TR channel and the row are two faces of ONE value (the shape card 0
      // has had for the trigger since the beginning), and -1 (AUTO) shows as its greyed
      // "--" the way every other target without a value does.
      case PAL_ZONE_EDGE_TOP:    return g_zoneEdgeTopTransparency;
      case PAL_ZONE_EDGE_BOTTOM: return g_zoneEdgeBottomTransparency;
      case PAL_HTF_BULL:
      case PAL_HTF_BEAR:
      case PAL_HTF_WICK:
      case PAL_HTF_BORDER: return 100 - g_HTFOpacity;
   }
   return -1;
}

//--- apply a transparency % to a palette kind → REFRESH_* flags.
int PaletteApplyTransparency(const int kind, const int tr)
{
   int t = ClampInt(tr, 0, 100);
   switch(kind)
   {
      case PAL_TRIGGER:  g_triggerTransparency = t; return REFRESH_BUFFERS;
      // P-UI-131j: the trigger LABEL's opacity, reached from the popover's TR track
      // AND from the card's own LABEL OPACITY row — two faces, one mirror.
      case PAL_TRIGGER_LABEL: g_triggerLabelTransparency = t; return REFRESH_BUFFERS;
      case PAL_LINE:     g_lineTransparency = t; return REFRESH_BUFFERS;
      case PAL_SS:       g_ssTransparency = t; return REFRESH_BUFFERS;
      case PAL_LS:       g_lsTransparency = t; return REFRESH_BUFFERS;
      case PAL_CUSTOM_PRICE: g_customPriceTransparency = t; return REFRESH_BUFFERS;
      case PAL_FACTOR:   g_factorTransparency = t; return REFRESH_BUFFERS;
      case PAL_BOX:
         g_boxBorderTransparency = t; BaseKnotRestyleAll();
         return REFRESH_BUFFERS;
      case PAL_BOX_FILL:
         g_boxFillTransparency = t; BaseKnotRestyleAll();
         return REFRESH_BUFFERS;
      case PAL_ZONE_EDGE_TOP:    g_zoneEdgeTopTransparency = t;    return REFRESH_BUFFERS;
      case PAL_ZONE_EDGE_BOTTOM: g_zoneEdgeBottomTransparency = t; return REFRESH_BUFFERS;
      case PAL_HTF_BULL:
      case PAL_HTF_BEAR:
      case PAL_HTF_WICK:
      case PAL_HTF_BORDER: g_HTFOpacity = 100 - t; return REFRESH_HTF;
   }
   return REFRESH_NONE;
}

//--- factory default color of a COLOR row (Reset action) — DISPLAY-row keyed
color PnlDefColor(const int item,const int row)
{
   int s = PnlSetRow(item,row);
   if(s < 0) return clrNONE;
   return PnlDefColorSet(item,s);
}
color PnlDefColorSet(const int item,const int row)
{
   if(item==0 && row==1)  return DefTriggerColor();
   if(item==0 && row==2)  return DefTriggerLabelColor();
   if(item==5 && row==5)  return DefTH3Color();
   if(item==5 && row==6)  return DefTH3PipColor();
   if(item==6 && row==3)  return InpHTFBullColor;
   if(item==6 && row==4)  return InpHTFBearColor;
   if(item==6 && row==5)  return InpHTFWickColor;
   if(item==6 && row==6)  return InpHTFBorderColor;
   if(item==7 && row==5)  return DefLineColor();
   if(item==12) return BkSecDefColor(row);   // tabbed card — section mapping below
   if(item==13 && row==0) return DefBoxBorderColor();
   if(item==2 && row==1)  return (color)(int)FactoryDefault(FF_COUNTDOWN_COLOR);
   if(item==2 && row>=14 && row<=18)   // P-UI-70d (indices match PAL_ATR_TR..SPREAD)
      return (color)(int)FactoryDefault(FF_ATR_TR_COLOR + (row-14));
   if(item==8 && row==1)  return DefCustomPriceColor();
   if(item==10 && row==6) return DefFactorColor();
   if(item==9 && row==7 && (int)g_stepCalculationMode==3) return DefFactorColor();
   return clrNONE;
}

//+------------------------------------------------------------------+
//| Recent colors ring (persisted, packed two colors per GV)         |
//+------------------------------------------------------------------+
#define PAL_RECENT_MAX 24

color g_PalRecent[PAL_RECENT_MAX];
int   g_PalRecentCount = 0;

#endif // BIOTAK_PANELS_STATE_MQH
