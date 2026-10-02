// CardMetrics.mqh - THE CARD SURFACE'S OWN NUMBERS, AS A STANDALONE HEADER.
// P-DRAW-116 (2026-10-01) - ONE TABLE, TWO READERS, ZERO RENUMBER.
//
// These 145 lines are the cards' geometry and ink block, moved out of
// BiotakPanels_State.mqh VERBATIM (same order, same names, same values) and included
// by it, so the cards lose nothing and gain nothing. Why the move is the whole fix:
// the strip's settings panel wore the SAME numbers as its own literals -
// DSTRIP_GEAR_W 312 = PNL_WEL 312, PAD 16 = PNL_PAD_X 16, HEAD_H 56 = PNL_HEAD_H 56,
// ROW_H 42 = PNL_ROW_H 42, FOOT_H 48 = PNL_FOOT_H 48, LBL_PT 9 = PNL_PT_LBL 9,
// SKIN_M 14 = PNL_MARGIN 14 - across ~129 reads in six files. Two tables, one value
// today; two tables, two values the first time either side is retuned, and the panel
// is then "the surface that reads like a second card beside the cards" (P-DRAW-77).
//
// The include ORDER is why this file exists at all: DrawStrip.mqh is include 99 and
// BiotakPanels.mqh is 118, so the panel could never reach a PNL_* name - it could
// only retype the number. Including this header BEFORE DrawStrip (see the entry) puts
// the table where the panel can read it, and BiotakPanels_State.mqh's own #include
// keeps the cards correct whatever order they are compiled in.
//
// CONTRACT: this is a MOVE, not a rewrite. Nothing here may be renumbered, re-spelled
// or re-valued. A change to a number is a change to every surface that reads it.
#ifndef CARD_METRICS_MQH
#define CARD_METRICS_MQH


//--- geometry (content coordinates; card BMP carries its own shadow margin)
#define PNL_WEL        312
#define PNL_MARGIN     14     // transparent fringe baked into the card BMP
#define PNL_PAD_X      16
#define PNL_HEAD_H     56
#define PNL_ROW_H      42     // TV-dense single-line rows (label left · control right)
#define PNL_FOOT_H     48
#define PNL_CB_SZ      20      // TV checkbox size (kind=1 rows, pnl_cb_on/off.bmp)
#define PNL_CB_Y       11      // checkbox top inside its 42px row (label sits at +14)
//--- TV-modern single-line row anatomy (42px rows — R-PANELMOD 2026-09-07):
//--- label top +14 · single-line controls band +9..+33 · slider track +27 (h7)
#define PNL_LBL_Y      14      // row label top (all kinds; kind=6 moves it up)
//--- TYPOGRAPHY - the preview's CSS px converted to MT4 points (px * 3/4, the
//--- 96-DPI ratio MT4 renders OBJ_LABEL/OBJ_EDIT at). ONE table, read by both
//--- this renderer and tools/panel-mt4-sim.py, so a caption size can never
//--- drift again: the title sat at 12pt = 16px against the preview's 12.5px
//--- (28% oversized) since long before the redesign, which is exactly the
//--- "coarse next to the mock" look the preview was meant to end.
#define PNL_PT_TITLE   9       // .ttl             12.5px
#define PNL_PT_SUB     6       // .subttl           8.5px (7pt overruns .ver)
#define PNL_PT_LBL     9       // .lbl             11.5px (row labels)
#define PNL_PT_LBL_SM  8       // .lbl.sm          10.5px (colour/text row captions)
#define PNL_PT_SEC     7       // .row.sec .sl 9.5px + .cnt 9px
#define PNL_PT_CAP     7       // .dual .cell span  9.5px
#define PNL_PT_VAL     8       // .val / .val.chip   11px
#define PNL_PT_CTL     8       // .seg/.dd/.tab/.fld 10.5-11px
#define PNL_PT_NAV     8       // .nav             10.5px
#define PNL_PT_KEY     6       // .key              8.5px
#define PNL_PT_VER     6       // .ver                8px
#define PNL_PT_CSET    5       // .ccell b             7px
#define PNL_PT_FOOT    8       // .ft .btn            11px
#define PNL_PT_PAL     8       // .pal .ph .t         11px
#define PNL_PT_PALSEC  7       // .pal .plabel         9px
#define PNL_CTL_Y      9       // single-line control top (dropdown/select/nav/segments)
#define PNL_CTL_H      24      // single-line control height
#define PNL_TRK_Y      29      // P-UI-131d: the caption line above it keeps 11px of
                               // air now (was 27 = 8px) — the MIDDLE of a two-part row
                               // is where air is owed, and 8px read as glued.
#define PNL_CAP_Y      1       // P-DRAW-48: the caption line of a CAPTION-ABOVE-CONTROL row
                               // (the same top line PNL_CHIP_Y_SL puts the chip on)
#define PNL_QSW_Y      19      // ...and its 22px swatch strip. 42 = 1 + 13 + 5 + 22 + 1, so
                               // 5px of air in the middle is the MAX a 42px row can hold;
                               // the strip used to sit at 18 (3px, glued) — the one row
                               // family that never got P-UI-131d's air.
#define PNL_TRK_H      7       // slider track height
#define PNL_TRACK_X    (PNL_PAD_X)            // modern full-width track (no steppers)
#define PNL_TRACK_W    (PNL_WEL-2*PNL_PAD_X)
#define PNL_KNOB_W     18
//--- generic dropdown-select (kind=2, 4+ options) — TV popover language
#define PNL_DD_ROW_H   28
#define PNL_DD_PAD     8
// the popover ladder lives in ConstantsAndEnums.mqh (Z LADDER, P-UI-31) —
// these four names are kept as the call-site spelling inside this file.
#define PNL_DD_Z_SH    Z_PANEL_DD_SH
#define PNL_DD_Z_BG    Z_PANEL_DD_BG
#define PNL_DD_Z_SEL   Z_PANEL_DD_SEL
#define PNL_DD_Z_LBL   Z_PANEL_DD_LBL
//--- inline quick-pick swatches on COLOR rows (one-tap apply, no popup).
// Single-line layout: [preview 46][6][6×22 swatches +5 gaps], label above-left.
// New widget suffixes ("Q0".."Q5","PK","TU","DD","DDT","DDC") MUST also be
// deleted in PnlDestroy (see P-UI-02: leaked widgets stay on screen).
#define PNL_QSW_N      8       // 6 -> 8 in the redesign (46+8*22+9*4 = 280 exactly)
#define PNL_QSW_W      22
#define PNL_QSW_GAP    4
#define PNL_QSW_PREV   46
#define PNL_QSW_OGAP   6
color QuickPalColor(const int i)
{
   // P-DRAW-24 — ONE PALETTE: the 8 quick swatches are BioPal()'s first 8, in
   // order (changing the order re-paints every colour row). The table lives in
   // ConstantsAndEnums.mqh; this face only bounds the index.
   if(i < 0 || i > 7) return C'20,20,20';     // #141414
   return BioPal(i);
}
//--- .ft .btn — content-sized in the preview (Reset ~72px, Done ~69px), 28px
//--- tall with an 8px radius. The face is a BAKED skin (pnl_btn_ghost /
//--- pnl_btn_prim_<accent>) because MT4 buttons are square and cannot gradient;
//--- PNL_BTN_PAD is the glow margin baked around that skin.
#define PNL_BTN_W      72
#define PNL_BTN_H      28
#define PNL_BTN_PAD    8
#define PNL_KEY_ESC    27
#define PNL_BOTTOM_SAFE 30     // keep the card clear of the bottom date-scale bar
// P-UI-91: breathing room between a card and the price action it now avoids.
// A TASTE margin (the same language as PNL_PAD_X between card and menu), NOT a
// measurement: the candle band itself is measured bar by bar, so this only
// keeps a wick from touching the card's edge.
#define PNL_CANDLE_PAD  8

//--- TV-style floating strip (item 13 = Base Box MINI quick style) — the
//    mini is NOT a vertical row-card anymore: it is a compact horizontal
//    TradingView-like icon toolbar [pencil|bucket|T|width|style|lock|trash|
//    more] — bk_*.bmp glyphs generated by tools/gen-th3-icons.js
//    (style/width/lock variants swap at runtime; pencil/bucket/T carry a
//    live color underline bar = TV's current-color underlines), on an
//    obsidian-glass strip card (bk_strip.bmp, 380px). Anchored above the held box's
//    top-right corner (BkHoldFire); re-anchors on EVERY open, not
//    header-draggable (no persisted spot) — like a TV per-object toolbar.
//    Dismisses TV-like: outside chart click / Esc / trash / ••• (full card).
//    R-BKSTRIP (2026-09-07); TV-parity 2026-09-07.
#define PNL_TB_W      380    // strip content width (own width — NOT PNL_WEL)
#define PNL_TB_H      58     // strip height (was a 56 + 7*50 + 48 row-card)
#define PNL_TB_BTN_H  36     // strip button height
#define PNL_TB_TOP    ((PNL_TB_H - PNL_TB_BTN_H) / 2)   // button content offset

//--- TV-white panel palette (2026-09-07 R-PANELS: all settings cards speak the
//--- white-dialog language of the strip/dropdowns + TV dialogs). ONE primary:
//--- navy C'38,44,56' (same as the dropdown selection pill); amber lives only
//--- in the ring/strip icon art, never in panel chrome. Geometry untouched.
//--- Obsidian Gold language (2026-09-11 — panel_all_redesign_preview.html).
//--- The cards left the TV-white family, so every ink here is the preview's
//--- own token: --title/--val #F3F6FB, --muted #8C96A6, --lbl #CBD4E2,
//--- --field #181D27, --track #222937, --card #1D222C. The single primary is
//--- the gold accent ramp (#FFC247 -> #FF8A00) with --aInk #1A1206 on top.
//--- Geometry is untouched — only paint.
#define PNL_CLR_TITLE    BIO_CLR_INK        // #F3F6FB --title / --val (= BIO_CLR_INK)
#define PNL_CLR_MUTED    BIO_CLR_MUTED      // #8C96A6 --muted (= BIO_CLR_MUTED)
#define PNL_CLR_LABEL    BIO_CLR_LABEL      // #CBD4E2 --lbl (= BIO_CLR_LABEL)
// R-KEYCAP: the header .key cap's letter when its master switch is OFF (the
// shipped ink, unchanged - pixel parity for every card whose cap is a hint).
#define PNL_CLR_KEYCAP_OFF C'183,193,208'
#define PNL_CLR_ACCENT   BIO_CLR_ACCENT     // #FFC247 --a1 (gold ramp top)
#define PNL_CLR_ACCENT_TX BIO_CLR_ACCENT_INK // #1A1206 --aInk
#define PNL_CLR_VALUE    BIO_CLR_INK        // #F3F6FB --val (= BIO_CLR_INK)
#define PNL_CLR_TRACK_BD C'52,61,77'      // #343D4D --trackBd (spec, not the card border)
#define PNL_CLR_TRACK    C'34,41,55'      // #222937 --track
#define PNL_CLR_FIELD_BD BIO_CLR_FIELD_BD   // #333C4C --fieldBd (edit/DD rims — NOT the seg border)
#define PNL_CLR_SEG_ON   BIO_CLR_ACCENT     // .seg.on  = accent ramp
#define PNL_CLR_SEG_OFF  BIO_CLR_CARD       // #1D222C .seg face (= BIO_CLR_CARD)
#define PNL_CLR_SEG_BD   C'45,52,65'      // #2D3441 .seg border
#define PNL_CLR_SEG_TX   BIO_CLR_MUTED      // --muted on a dark seg
#define PNL_CLR_DONE_TX  BIO_CLR_ACCENT_INK // --aInk on the primary button
#define PNL_CLR_LINE     BIO_CLR_HAIRLINE   // row separators + control borders
#define PNL_CLR_FIELD    BIO_CLR_FIELD      // #181D27 edit fields + popover faces
#define PNL_CLR_CARD     BIO_CLR_CARD       // #1D222C palette card + inactive tabs
//--- the card body at the FOOTER (cardGrad bottoms out at #12161D). The footer
//--- buttons carry a baked rounded skin whose corners are transparent, so the
//--- OBJ_BUTTON beneath them must be filled with exactly this or its square
//--- would show through the radius.
#define PNL_CLR_FOOTBG   BIO_CLR_FOOT       // #12161D card footer (= BIO_CLR_FOOT)
#define PNL_CLR_DISABLED C'90,98,110'     // greyed-out (no-transparency targets)
#define PNL_CLR_DIS_BD   C'58,66,80'      // greyed-out control borders
#define PNL_CLR_SHADOW   C'8,10,14'       // popover drop shadows (dark chart)
#define PNL_CLR_AUTO_CELL C'52,60,74'     // P-UI-68: colour strip cell for "no override"
#define PNL_KNOB_BMP     18

#endif // CARD_METRICS_MQH

