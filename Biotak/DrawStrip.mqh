//+------------------------------------------------------------------+
//|                                                 DrawStrip.mqh     |
//|   P-DRAW-08 (2026-09-22) — THE FLOATING STRIP OF THE USER'S DRAWINGS.|
//|   P-DRAW-09 (2026-09-23) — THE MODERN FACE, THE GROUP, THREE CONTROLS.|
//|   P-DRAW-10 (2026-09-23) — THE TRADINGVIEW FACE: LIGHT ICON CELLS.    |
//|   P-DRAW-11 (2026-09-23) — DIRECT PICK, NO CYCLING (BASEKNOT PARITY+).|
//|   P-UI-113 (2026-09-23) — LEFT-HOLD OPENS (right-click era deleted).  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property strict

#ifndef DRAW_STRIP_MQH
#define DRAW_STRIP_MQH

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-10 (2026-09-23) — THE ICON FACE. User order: «مثل استریپ تریدینگ ویو بشه»:
// a small floating bar of LIGHT ICON CELLS, the value in the tooltip. Two laws
// carry it, and the 08i pass that concluded "a bitmap label ships empty" had both
// wrong (the reasoning is in git history):
//   * the raster must be EMBEDDED — `OBJPROP_BMPFILE` with a "::Files\\Icons\\"
//     path resolves only for a file this module `#resource`d, and every raster is
//     listed in `tools/icon-manifest.txt`;
//   * the CELL must be the control — MT4 paints a label at the file's NATIVE size
//     from its own corner, so the art is centred by arithmetic and the CLICK
//     target stays the OBJ_BUTTON underneath (Z_PANEL_BASE/Z_PANEL_SKIN): the
//     icon is a face, the button is the control, a click on either name routes.
// A cell whose value is a WORD (ray mode, caption size, arrow code, template
// name, "All") keeps the word: an icon that lies is worse than a word that says
// it (P-DRAW-08d, still binding).
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
#resource "\\Files\\Icons\\bk_half_off.bmp"
#resource "\\Files\\Icons\\bk_half_on.bmp"
#resource "\\Files\\Icons\\bk_ext_off.bmp"
#resource "\\Files\\Icons\\bk_ext_on.bmp"
#resource "\\Files\\Icons\\bk_back_on.bmp"
#resource "\\Files\\Icons\\bk_lock_on_g.bmp"
#resource "\\Files\\Icons\\ds_swatch24.bmp"
#resource "\\Files\\Icons\\gl_pin_m.bmp"
#resource "\\Files\\Icons\\gl_pin_gold.bmp"
#resource "\\Files\\Icons\\gl_plus_m.bmp"
#resource "\\Files\\Icons\\gl_check_m.bmp"
#resource "\\Files\\Icons\\gl_textsize_m.bmp"
//--- P-DRAW-29 (2026-09-24) — the plate wears the cards' own skin: the 9-slice
//--- `ds_*` set baked by tools/gen-th3-icons.js (R-ICON: manifest-listed, like
//--- every raster above). The mid-row centre is a plain DSTRIP_CLR_PANEL rect.
#resource "\\Files\\Icons\\ds_top_l.bmp"
#resource "\\Files\\Icons\\ds_top_m.bmp"
#resource "\\Files\\Icons\\ds_top_r.bmp"
#resource "\\Files\\Icons\\ds_mid_l.bmp"
#resource "\\Files\\Icons\\ds_mid_r.bmp"
#resource "\\Files\\Icons\\ds_bot_l.bmp"
#resource "\\Files\\Icons\\ds_bot_m.bmp"
#resource "\\Files\\Icons\\ds_bot_r.bmp"
//--- P-DRAW-43 (2026-09-25) — THE PLATE'S TRANSPARENCY LEVELS, baked (MT4 has no
//--- runtime image API, so a % plate is a file set, not a slider): the same eight
//--- pieces at 30/60/90 %, the levels `DSTRIP_PLATE_T` behind the gear's own row.
#resource "\\Files\\Icons\\ds_top_l_t30.bmp"
#resource "\\Files\\Icons\\ds_top_m_t30.bmp"
#resource "\\Files\\Icons\\ds_top_r_t30.bmp"
#resource "\\Files\\Icons\\ds_mid_l_t30.bmp"
#resource "\\Files\\Icons\\ds_mid_r_t30.bmp"
#resource "\\Files\\Icons\\ds_bot_l_t30.bmp"
#resource "\\Files\\Icons\\ds_bot_m_t30.bmp"
#resource "\\Files\\Icons\\ds_bot_r_t30.bmp"
#resource "\\Files\\Icons\\ds_top_l_t60.bmp"
#resource "\\Files\\Icons\\ds_top_m_t60.bmp"
#resource "\\Files\\Icons\\ds_top_r_t60.bmp"
#resource "\\Files\\Icons\\ds_mid_l_t60.bmp"
#resource "\\Files\\Icons\\ds_mid_r_t60.bmp"
#resource "\\Files\\Icons\\ds_bot_l_t60.bmp"
#resource "\\Files\\Icons\\ds_bot_m_t60.bmp"
#resource "\\Files\\Icons\\ds_bot_r_t60.bmp"
#resource "\\Files\\Icons\\ds_top_l_t90.bmp"
#resource "\\Files\\Icons\\ds_top_m_t90.bmp"
#resource "\\Files\\Icons\\ds_top_r_t90.bmp"
#resource "\\Files\\Icons\\ds_mid_l_t90.bmp"
#resource "\\Files\\Icons\\ds_mid_r_t90.bmp"
#resource "\\Files\\Icons\\ds_bot_l_t90.bmp"
#resource "\\Files\\Icons\\ds_bot_m_t90.bmp"
#resource "\\Files\\Icons\\ds_bot_r_t90.bmp"
//--- P-DRAW-33 (2026-09-24) — THE COLOUR SURFACES WEAR THE CARDS' GLASS. User
//--- report: «مشکلاتش چیه چرا از رنگ ها شیشه استفاده نشده مثل بقیه». Every card
//--- control in this project is a flat button with a `pnl_glass*` frame over it
//--- (RICH-MT4: transparent middle, so the colour shows through, plus the baked
//--- top-light / bottom-shade), and the strip's colour cells were the ONE surface
//--- left flat. Baked at the two sizes the strip actually uses: 32 (quick row +
//--- colour popover cell) and 28 (the gear's swatch grid) — MT4 CROPS a bitmap
//--- label, never scales it.
//--- ICON-DIET 2026-09-27: pnl_glass32 and pnl_glass28 are gone. Every face the
//--- gear, the picker and the recent ring draw is ds_cell32 / ds_ring32 /
//--- ds_swatch24 (the kind-0 swatch branch — the last pnl_glass28 caller — was
//--- deleted with the icon diet). The two size-table entries below went with
//--- them, so no branch can name a file that no longer exists.
#resource "\\Files\\Icons\\ds_cell32.bmp"
#resource "\\Files\\Icons\\ds_ring32.bmp"
#resource "\\Files\\Icons\\dsg_btn_ghost.bmp"
//--- P-DRAW-74: there is NO filled-primary bake left in the panel — the foot's Close
//--- took it. The builder is `tools/gen-th3-icons.js` -> `ftBtnSkin('gold', true, 64)`;
//--- the declaration, the manifest line and the file went with the caller (I3/I6).
#resource "\\Files\\Icons\\pnl_topbar_gold.bmp"
#resource "\\Files\\Icons\\pnl_hair_gold.bmp"
//--- P-DRAW-73: the W twins of the head's own two pieces, declared HERE because this
//--- is the only module that draws them (a wide gear head). They lived in
//--- BiotakPanels.mqh, so a wide panel's head art hung on an unrelated include.
#resource "\\Files\\Icons\\pnl_topbarW_gold.bmp"
#resource "\\Files\\Icons\\pnl_hairW_gold.bmp"
#resource "\\Files\\Icons\\pnl_mark_gold.bmp"
#resource "\\Files\\Icons\\pnl_chip.bmp"
#resource "\\Files\\Icons\\pnl_chip_gold.bmp"
#resource "\\Files\\Icons\\pnl_rail_gold.bmp"
#resource "\\Files\\Icons\\pnl_sw_off.bmp"
#resource "\\Files\\Icons\\pnl_sw_on_gold.bmp"
#resource "\\Files\\Icons\\pnl_vchip_gold.bmp"
#resource "\\Files\\Icons\\pnl_xbtn.bmp"
#resource "\\Files\\Icons\\pnl_subdot_amber.bmp"
#resource "\\Files\\Icons\\pnl_subdot_jade.bmp"
#resource "\\Files\\Icons\\pnl_secdot_gold.bmp"
#resource "\\Files\\Icons\\pnl_cntchip.bmp"
//--- P-DRAW-81: THE PANEL'S OWN PLATE, DECLARED HERE. This is the defect behind
//--- «the panel has no skin at all»: the settings panel paints `pnl_card{n}` and
//--- `pnl_cardW*` (DrawStripGearPlate) and `pnl_btn_ghost` (its foot), but those
//--- `#resource` lines lived only in BiotakPanels.mqh — which is included AFTER
//--- this file (entry lines 99 and 118). On MT4 `#resource` binds per COMPILING
//--- UNIT, not per module: a `::Files\...` BMPFILE resolves ONLY for a raster the
//--- unit declared, so every one of those writes was a silent no-op — the plate
//--- painted nothing at all and the foot button had no skin. A green compile said
//--- nothing, because the name is a string.
//--- The ten narrow bakes the generator emits (`PNL_CARD_ROWS_MAX` 10, one per
//--- row count, 340 x (174+42n)), plus the three composed W pieces and the ghost
//--- button this module paints. Declared where they are DRAWN, like every other
//--- raster above.
#resource "\\Files\\Icons\\pnl_card1.bmp"
#resource "\\Files\\Icons\\pnl_card2.bmp"
#resource "\\Files\\Icons\\pnl_card3.bmp"
#resource "\\Files\\Icons\\pnl_card4.bmp"
#resource "\\Files\\Icons\\pnl_card5.bmp"
#resource "\\Files\\Icons\\pnl_card6.bmp"
#resource "\\Files\\Icons\\pnl_card7.bmp"
#resource "\\Files\\Icons\\pnl_card8.bmp"
#resource "\\Files\\Icons\\pnl_card9.bmp"
#resource "\\Files\\Icons\\pnl_card10.bmp"
#resource "\\Files\\Icons\\pnl_cardWtop.bmp"
#resource "\\Files\\Icons\\pnl_cardWmid.bmp"
#resource "\\Files\\Icons\\pnl_cardWbot.bmp"
#resource "\\Files\\Icons\\pnl_btn_ghost.bmp"
//--- P-DRAW-81: the foot's reset glyph, same defect — the painter names it and
//--- this unit never declared it, so the button drew its skin and no icon.
#resource "\\Files\\Icons\\gl_reset_m.bmp"
//--- P-DRAW-81: the quick row's own "..." cell, found by the same audit — named at
//--- DrawStripActRes (line 1140) and never declared, so that one cell was blank.
#resource "\\Files\\Icons\\bk_more.bmp"
#resource "\\Files\\Icons\\gl_box_i_gold.bmp"
#resource "\\Files\\Icons\\gl_line_i_gold.bmp"
#resource "\\Files\\Icons\\gl_type_i_gold.bmp"
#resource "\\Files\\Icons\\gl_target_i_gold.bmp"
#resource "\\Files\\Icons\\gl_sigma_i_gold.bmp"
#resource "\\Files\\Icons\\gl_x_gold.bmp"
#resource "\\Files\\Icons\\gl_check_gold.bmp"
#resource "\\Files\\Icons\\gl_nav_m.bmp"
#resource "\\Files\\Icons\\gl_droplet_m.bmp"

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-08 — ONE STRIP, EVERY DRAWING TOOL, ITS OWN CONTROLS. A hold on any
// drawing opens ITS OWN toolbar, not the box's. Deliberately the OPPOSITE shape
// from item 13's bitmap strip: it renders itself from the drawing's KIND (so it
// shows exactly the controls that kind has), owns its objects
// (create/refresh/destroy) with no framework state, and one owner serves seventeen
// kinds with no per-type code.
// P-DRAW-11 retired the cycler (a value cell OPENS its picker now; only toggles and
// actions fire at once) and P-DRAW-09/10/13 shaped the face: a header naming the
// drawing, wrapping rows, state-coloured faces, contrast-correct swatch ink, the
// controls MT4 buries (font, glyph, behind) and the group. Every write is guarded
// (P-PERF-02) and the forced repaint fires only when a pixel moved — created once
// per hold, destroyed on dismiss, nothing in the mouse stream.
// ══════════════════════════════════════════════════════════════════════════

// P-DRAW-08i: the paint loop walks DSTRIP_MAX_SLOTS, so a slot past the ceiling
// would be silently never drawn. P-DRAW-13: quick cells are capped at six
// (DSTRIP_QUICK_CAP); the twelve is headroom for the cap plus chrome.
// P-DRAW-09: a kind has at most ten cells (six of its own + Tpl/Save/✕/All).
#define DSTRIP_MAX_SLOTS 12
//--- P-DRAW-11 (2026-09-23) — DIRECT PICK, NO CYCLING. The cycler is retired: a tap
// on a VALUE cell OPENS that value's picker and the pick applies directly; toggles
// (fill/lock/behind) and the three actions (Save/All/Del) fire at once — one tap, one
// list, the current value highlighted, for all seventeen drawing kinds. The picker is
// INLINE (the strip's own second block — no popover, no palette window, no card-12
// jump), it carries the palette plus the recents, the template list lives in the
// strip, the group rides every pick, and the picker survives a re-anchor.
// THE AFFORDANCE WITHOUT A CHEVRON BITMAP: MT4 renders "▼" as "?" in Wine fonts, so
// the rim carries it — a value cell wears DSTRIP_CLR_PICK (ACCENT while its own
// picker is open) and an ON toggle wears the ACCENT face. Rim = has a list.
// P-DRAW-13 — V6, icon-only one row (grip | badge | <=6 value icons | more | gear |
// pin | trash) plus one docked popover and a gear panel. What MT4 cannot do is cut
// with a named ceiling, never silently dropped: no text-edit in the row (the gear
// panel's OBJ_EDITs own typing), no per-level on/off (levels edit MEMBERSHIP), no
// font-name cycle, and trash is not undoable. Created on demand, destroyed with the
// strip; nothing here runs in the mouse stream.
#define DSTRIP_PICK_NONE (-99)  // no popover open
#define DSTRIP_MORE      (-60)  // the more-popover (sections, not a slot)
#define DSTRIP_SLOT_MORE   (-6) // quick: the "..." popover
#define DSTRIP_SLOT_GEAR   (-7) // quick: the full-settings panel
#define DSTRIP_SLOT_PIN    (-8) // quick: pin toggle (stays while editing)
#define DSTRIP_SLOT_LEVELS (-9) // quick: the fibo level-membership editor
//--- P-DRAW-13: the V6 shell metrics. ONE 30px row, icon-only, 2px gaps — the
//--- preview's minimal-space rule. Nothing wraps any more: overflow value slots
//--- live in the more-popover, never on a second row.
#define DSTRIP_CELL      32    // the one row's height, and every icon cell's width
#define DSTRIP_SWATCH    24    // the colour cell's own swatch (the preview's .swcell: 24px, B-05's floor)
#define DSTRIP_GAP        4
#define DSTRIP_PAD        8    // plate padding
#define DSTRIP_PICK_MAX  72    // popover rows/cells: the picker grid's 64 + recents (P-DRAW-46)
#define DSTRIP_PICK_ROW   42   // ONE mid band per swatch row — this pitch IS the plate's
                               // 48 + 42k law (DSTRIP_SKIN_MID, DrawStripSkinKFor)
#define DSTRIP_PICK_CELL  32
#define DSTRIP_PICK_GAP    8
#define DSTRIP_GRID_MAX  72    // option cells in one gear grid block (the picker's 64 fits)
#define DSTRIP_GLIST_MAX 16    // list rows in one gear block
#define DSTRIP_GEAR_W   312
#define DSTRIP_GEAR_PAD  16
#define DSTRIP_GEAR_HEAD_H 56
#define DSTRIP_GEAR_ROW_H  42
#define DSTRIP_GEAR_TB_H   7   // the head's own top bar, at the head's top edge
#define DSTRIP_GEAR_HR_H   5   // ...and the hair that CLOSES it (P-DRAW-73)
#define DSTRIP_GEAR_FOOT_H 48   // pnl_card* parity: PNL_FOOT_H=48 (was 42)
//--- P-DRAW-74 (2026-09-28): the foot carries COMMANDS. Its Close stood beside the
//--- header's own X and wore the panel's one FILLED block, so the loudest thing on a
//--- card whose job is to change a drawing was the way out of it (C-03).
//--- P-DRAW-78: TWO foot buttons, All and Copy. The third was `Del`, and the
//--- strip's own command group already carries a trash cell that asks first
//--- (DrawSelCount in its tooltip) — so the panel carried a second, unconfirmed
//--- way to destroy the drawing. One owner per action.
#define DSTRIP_GEAR_FOOT_N 2
//--- P-DRAW-80: the foot button's width is the CARDS' own formula
//--- (`max(72, 32 + advance + 8)`, BiotakPanels PnlFootBtnW) — the flat 64 that
//--- stood here is retired, and with it every reader.
#define DSTRIP_GEAR_FOOT_BW 72   // the formula's floor; the measured width wins above it
#define DSTRIP_GEAR_FOOT_GAP 8
#define DSTRIP_GEAR_GRID_GAP 8
#define DSTRIP_GEAR_SWATCH 28
#define DSTRIP_GEAR_CHIP   48   // 5 chips per row in 280px content (5*48 + 4*8 = 272 < 280)
#define DSTRIP_GEAR_CHIP_H 32
#define DSTRIP_GEAR_EDIT_H 22   // P-DRAW-66: the board's own field height (DSTRIP_POP_EDIT_H)
//--- P-DRAW-71 — THE TAB ROW IS THE CARDS' OWN `.tabs`: a 24px control on its own
//--- 42px row, a 4px micro seam, a 12px caption inset and a 2px accent underline
//--- under the active tab (BiotakPanels `kind==2` / `IsTabRow`). The segmented pill
//--- this panel wore — a filled track, a gold chip and a #333C4C rim on every
//--- unselected tab — was its own invention and read as a row of boxes.
#define DSTRIP_TAB_H     24
#define DSTRIP_TAB_GAP   4
#define DSTRIP_TAB_PAD   12
#define DSTRIP_TAB_UL    2
#define DSTRIP_SEC_CNT_W 24    // P-DRAW-71: a band's count pill (the cards' .cnt)
#define DSTRIP_SEC_CNT_H 16    // P-DRAW-73: the bake's own height (cntChipSkin 24x16)
//--- P-DRAW-32 (2026-09-24) — THE SETTINGS PANEL IS ITS OWN CARD. User order:
//--- «پنل تنظیمات از استریپ جدا باشه». It used to be the strip's plate GROWING
//--- tall (one window wearing both), so a settings panel meant the toolbar itself
//--- became a tower. It is now a separate surface at its own origin (`s_dsGEX` /
//--- `s_dsGEY`): its own 9-slice plate, its own placement, its own carry — the
//--- strip stays the compact quick row it is. The arithmetic that makes the nine
//--- slice reusable is this constant: the plate's height must read `48 + 42k`
//--- (the skin's own law, P-DRAW-29) and the panel's fixed part is head 56 +
//--- tabs 42 + foot 42 = 140, so the air below the foot is 34 — not the strip's
//--- 28 — and 140 + 34 = 174 ≡ 48 (mod 42). Change this and the gear falls back
//--- to the flat legacy rect (DrawStripSkinK refuses a plate off the grid).
//--- RETIRED (2026-09-29, P-DRAW-78b): the air was the make-up gap between a 42px
//--- foot band and the cards' 48px footer. The foot band is 48 now (DSTRIP_GEAR_FOOT_H,
//--- whose own ghost face reaches fy0+46 and needs the room), so the card's footer is
//--- already paid for and the 6px was a SECOND count of it: every tab stood 6px over
//--- the cards' law, `cardExact` was false on all four, and the plate fell to the
//--- composed W body on every tab instead of one baked card. Kept at 0 rather than
//--- deleted so the retired law stays readable next to the number that replaced it.
#define DSTRIP_GEAR_AIR 0    // was 6 — the foot band IS the card's 48px footer now
                             // head 56 + T rows + foot 42 + 6 = 104 + 42*(T-1):
                             // EXACTLY the cards' own law (56 + n*42 + 48), so the
                             // foot row plus the air fills the card's 48px footer
                             // and every content row lands on a card row. The old
                             // values (34, then 0) put every height off every bake.
//--- P-DRAW-69: THE FIRST 42px CELL OF EACH SURFACE'S OWN BODY. The cards have ONE
//--- grid — the row pitch — and the plate's ramp bands ride it, so a row's face IS
//--- the band under it. The strip's first popover row and the board's first grid row
//--- both land on the ramp's own start, the panel's on head(56)+tabs(42) = 98.
#define DSTRIP_STRIP_GRID_TOP 44
#define DSTRIP_STRIP_BODY_TOP (DSTRIP_SKIN_TOPT - DSTRIP_SKIN_M)   // 44 — the cap's own content
#define DSTRIP_BOARD_GRID_TOP 44
#define DSTRIP_GEAR_GRID_TOP  (DSTRIP_GEAR_HEAD_H + DSTRIP_GEAR_ROW_H)
//--- P-DRAW-70: WHERE A CARD'S BODY STARTS. `pnl_card7.bmp` content row 0 and 1 are
//--- the rim (#2C3444) and row 2 is the first body row (#1E242F) — measured. A plate
//--- that wears the card's ramp has to start its own body on the same row, or its
//--- baked 44px cap ramp shows through and the surface is 5-10 units dark.
#define DSTRIP_BODY_TOP 2
//--- the panel's default spot is BESIDE the strip's plate, never on it (P-DRAW-31's
//--- rule: no two surfaces on one pixel) — this is the air between them.
#define DSTRIP_GEAR_GAP 20   // must be >= DSTRIP_SKIN_BOTT(18) + DSTRIP_SKIN_M(14) - strip_h_remainder to avoid skin overlap
#define DSTRIP_GEAR_SECTION_MAX 8
//--- P-DRAW-30 (2026-09-24) — THE GEAR WEARS THE CARDS' WIDE RULE. Every settings
//--- surface in this project is a 312 card that turns into TWO 312 slots side by
//--- side once it carries more than ten rows (BiotakPanels.mqh `PNL_WEL` /
//--- `PNL_WIDE_WEL` / `PNL_COL_DX` / `PNL_WIDE_MIN_ROWS`); the gear panel was the
//--- one surface that never did, so its tall tabs (Style is 13 rows, a fibo's
//--- Levels up to 20) grew a single narrow column taller than the window and
//--- read as nothing like the cards. SAME numbers here: two 312 slots, 16px side
//--- pads, the middle 32px is the two pads back to back — so a column's content
//--- is the very same 280 the narrow layout always used and every existing
//--- block metric (swatch 28, chip 64, row 42) keeps its arithmetic.
#define DSTRIP_GEAR_W2   624   // wide content width: DSTRIP_GEAR_W * 2
#define DSTRIP_GEAR_COL  312   // a block's x shift for the right column
#define DSTRIP_GEAR_WIDE_ROWS 10 // PNL_WIDE_MIN_ROWS parity: > 10 rows goes wide
#define DSTRIP_GEAR_BLK_MAX 12 // section blocks one tab may open (<= SECTION_MAX + air)
#define DSTRIP_RECENT_MAX 5    // the trader's own recent colours
#define DSTRIP_UNDO_MAX  32    // single-step undo: members covered
#define DSTRIP_UNDO_LV   32    // ... and fibo levels on the held drawing
#define DSTRIP_HOVER_POP_BASE 1000 // popover colour cells offset from gear cells
#define DSTRIP_HOVER_REC_BASE 2000 // TV parity: the board's RECENT band cells
#define DSTRIP_GRIP_MS   30    // the grip carry's own cadence (BkStripFollow parity)
//--- P-DRAW-75 (2026-09-28): the two-line ink gap, MEASURED off the cards' own
//--- header — title 12..24 over subtitle 35..43, so 11 of air in the middle (the
//--- number P-UI-131d took off the user's «از وسط چسبیده»). This module wore the
//--- scale's 6, which left the panel's head the one glued header in the product; at
//--- 11 `StrapInkY2` returns the cards' own 12 and 35 (A-12: the rule moved down).
#define DSTRIP_INK_GAP   11
//--- P-DRAW-75: a row's label→control gap and its label's point size — the cards'
//--- `PNL_ROW_GAP 10` / `PNL_PT_LBL 9`, i.e. B-02's floor, named here because
//--- include 97 cannot read 116.
#define DSTRIP_ROW_GAP   10
#define DSTRIP_GEAR_LBL_PT 9
//--- P-DRAW-83: A CAPTION THAT SHARES ITS ROW WITH A CONTROL NAMES ITS CONTROL'S
//--- SEAT. The caption draws at `DSTRIP_GEAR_PAD + 14` (the cards' own row-label
//--- x, BiotakPanels 6007's `+16+14`) and the field starts at the seat the caption
//--- measured — 14 was a bare literal in the paint, so `DrawStripGearCapW` never
//--- counted it: the field began 30px INTO its own caption (label 30..76, field from
//--- 56), the hex text sat under the word that names it and the caption's own hit box
//--- covered the field's first 20px. One name for the one number, and the seat is
//--- `CAP_DX + the label + the gap` so the two can never disagree again.
#define DSTRIP_GEAR_CAP_DX 14
//--- 14 = the cards' caption x inside the row (PNL_PAD_X + 14 is 30, less the pad
//--- already in the origin). One owner of the caption's own seat.
#define DSTRIP_GEAR_CAP_X  (DSTRIP_GEAR_PAD + DSTRIP_GEAR_CAP_DX)
//--- P-DRAW-77: THE CARDS' OWN ROW SEATS, SPELLED ONCE HERE. Every number is the
//--- card's own constant (BiotakPanels 568/586/6155/6158), restated because
//--- `PNL_*` does not exist in this file (BiotakPanels is included AFTER it).
//--- 10 = (42-22)/2 chip+switch top · 14 = PNL_LBL_Y · 8 = the label's own gap
//--- after the chip · 40 = PNL_SW_W. One table, so the panel cannot drift from
//--- the card it stands beside a unit at a time.
#define DSTRIP_CARD_CHIP_Y 10
#define DSTRIP_CARD_LBL_Y  14
//--- P-DRAW-66: the quick row's THREE GROUPS — identity | values | commands. A
//--- separator is a 1x20 hairline centred in the row with 8 air on each side, so
//--- the chrome never reads as one more value; the head's air is the tight step.
#define DSTRIP_HEAD_AIR   8
#define DSTRIP_SEP_W      1
#define DSTRIP_SEP_H     20
#define DSTRIP_SEP_AIR    8
//--- P-DRAW-66: the command group's ids and count, moved UP from the layout block
//--- so the state block can size its own seat array by the count (one owner).
#define DSTRIP_QUICK_CAP 8
#define DSTRIP_ACT_MORE 0
#define DSTRIP_ACT_GEAR 1
#define DSTRIP_ACT_PIN 2
#define DSTRIP_ACT_DEL 3
#define DSTRIP_ACT_N 4
//--- P-DRAW-29 (2026-09-24) — the plate skin's own metrics (define-before-use:
//--- PointInside and the clamps read them far above the painters). The plate's
//--- height is ALWAYS 48+42k, so one top cap (margin + 44) + k mid bands (42)
//--- + one bottom cap (4 + margin) composes every height; middles crop to every
//--- width (baked wide, MT4 crops a smaller XSIZE/YSIZE, never stretches).
#define DSTRIP_SKIN_M      14    // baked shadow margin around the plate
#define DSTRIP_SKIN_CAP    28    // corner cap width (margin + radius)
#define DSTRIP_SKIN_EDGE   15    // mid-row side strip (margin + 1px border)
#define DSTRIP_SKIN_TOPT   58    // top cap: margin + 44 (quick row + gap)
#define DSTRIP_SKIN_BOTT   18    // bottom cap: 4 + margin
#define DSTRIP_SKIN_MID    42
#define DSTRIP_SKIN_MIDW   640   // baked middle width (covers s_dsW <= 660)
#define DSTRIP_SKIN_MAXK   24    // baked mid strips are 24 bands tall
#define DSTRIP_SKIN_MAXW   660   // wider than any kind's quick row + badge
//--- P-DRAW-17: how far the hand may travel between press and release and still
//--- count as a CLICK. Past it the gesture was a DRAG - the user moving the
//--- drawing, or MT4's own native drag - and a drag must not summon the strip.
#define DSTRIP_CLICK_SLOP 8   // px of press->release travel (P-UI-113d: a release past
                              // this ended a DRAG - never the outside-click dismissal)
//--- gear tabs (0 = shut)
#define DSTRIP_GEAR_STYLE 1
#define DSTRIP_GEAR_LEVELS 2   // fibo family; TEXT/ARROW see MARK instead
#define DSTRIP_GEAR_MARK 2     // same seat as LEVELS (one tab at a time by kind)
#define DSTRIP_GEAR_TPL 3
#define DSTRIP_GEAR_STRIP 4
#define DSTRIP_GEAR_PAINT 5   // P-DRAW-65: the colours + the interior moved OFF Style —
                             // the tab that carried FOUR sections was the one that forced
                             // the 624-wide plate on every kind (B-08/B-10)
#define DSTRIP_GEAR_TAB_MAX 5  // tab ids one kind may show at once (0 = shut)
//--- more-popover row kinds
#define DSTRIP_MK_APPLYALL 1
#define DSTRIP_MK_PRESET 2     // arg = preset index
#define DSTRIP_MK_SAVE 3
#define DSTRIP_MK_DUPE 4
#define DSTRIP_MK_UNDO 5
#define DSTRIP_MK_SLOT 6       // arg = overflow value slot (opens its grid)
#define DSTRIP_MK_BOX50 7      // P-DRAW-21: the box 50% line toggle (rect only)
#define DSTRIP_MK_BOXEXT 8     // P-DRAW-22: the box extend cycle (rect only)
#define DSTRIP_MK_FILL50 9     // P-DRAW-64: the interior ON at 50% tone, one tap
#define DSTRIP_FILL50_TONE 50  // ...the tone that row means

//--- P-DRAW-09c: the strip's palette. These are the settings cards' OWN tokens
//--- (CARD #1D222C, FIELD #181D27, LINE #222832, LABEL #CBD4E2, MUTED
//--- #8C96A6, ACCENT #FFC247, aInk #1A1206), and their owner — BiotakPanels.mqh
//--- — is included AFTER this module (P-BUILD-01's include order; MQL4 is
//--- define-before-use), which is why they used to be mirrored here as literals.
//
// P-UI-69b (2026-09-25): they are ALIASES now. The ink moved DOWN to
// ConstantsAndEnums.mqh (include #1 — below BOTH this module and the panels),
// so the mirror is gone and every name below still resolves here. Nine of the
// twelve were byte-for-byte duplicates of `PNL_CLR_*`; two tables that agree
// today are two tables that disagree tomorrow. The two inks that are the
// strip's own — a destructive action needs its own colour — stay literal.
#define DSTRIP_CLR_PANEL   BIO_CLR_PANEL
#define DSTRIP_CLR_CARD    BIO_CLR_CARD
#define DSTRIP_CLR_FIELD   BIO_CLR_FIELD
#define DSTRIP_CLR_FIELD_BD BIO_CLR_FIELD_BD
#define DSTRIP_CLR_FOOT    BIO_CLR_FOOT
#define DSTRIP_CLR_LINE    BIO_CLR_HAIRLINE
#define DSTRIP_CLR_LABEL   BIO_CLR_LABEL
#define DSTRIP_CLR_TITLE   BIO_CLR_MUTED
#define DSTRIP_CLR_VALUE   BIO_CLR_INK
#define DSTRIP_CLR_ACCENT  BIO_CLR_ACCENT
#define DSTRIP_CLR_ACCENT2 BIO_CLR_ACCENT2
#define DSTRIP_CLR_ACCENTT BIO_CLR_ACCENT_INK
#define DSTRIP_CLR_VER_BG  C'62,55,49'
#define DSTRIP_CLR_VER_BD  C'94,82,56'
//--- P-DRAW-66: `DSTRIP_CLR_DEL_BG` (C'58,26,30') is RETIRED with the loud bin —
//--- the quick row's cell and the foot's button wear the ghost face now and the
//--- red INK is the destructive cue. Written as prose, not as a define: a token
//--- nobody reads is catalogue 21's dead rung one layer up.
#define DSTRIP_CLR_DEL_INK C'255,138,138'
//--- P-DRAW-11: the "this cell has a list" rim (see the header block: rim = has
//--- a picker, face = is on — a text chevron renders as "?" in Wine fonts).
#define DSTRIP_CLR_PICK    C'62,72,92'

static string   s_dsObj  = "";       // the drawing this strip serves (the held one)
static EDrawKind s_dsKind = DK_NONE; // its kind, resolved once per open
static int      s_dsX    = 0;
static int      s_dsY    = 0;
static int      s_dsW    = 0;        // the width of THIS kind's strip (set on open)
static int      s_dsH    = 0;        // plate height: quick row + open blocks
static int      s_dsN    = 0;        // quick value/toggle cells on screen now
static bool     s_dsOpen = false;
static bool     s_dsPinned = false;  // P-DRAW-13: pin — outside click won't dismiss
//--- P-DRAW-41 (2026-09-25) — THE PLATE HAS A HOME. Reported: «پنل روی خوده ابجکت
//--- ظاهر میشه اصلا جالب نیست و تجربه کاربری بدی داره». A surface that re-places
//--- itself beside the drawing it serves cannot win: when the drawing fills the
//--- window EVERY candidate sits inside the work and the placer only picks the
//--- least-bad one. So the strip stops chasing — the first open measures the
//--- drawing ONCE and that answer becomes its home (`-1` = not measured yet).
//--- The old follow pair (`s_dsManual`/`s_dsAX`/`s_dsAY`) went with the chase.
static int      s_dsHomeX = -1, s_dsHomeY = -1;
//--- P-DRAW-13: the shell layout, computed by ONE pass (DrawStripLayout) and read
//--- by the painter, the hit test and the grip carry, so a cell's face and its
//--- gap can never be computed twice and disagree.
static int      s_dsCX[DSTRIP_MAX_SLOTS];
static int      s_dsCW[DSTRIP_MAX_SLOTS];   // the name is measured; icons are CELL
static int      s_dsBadgeW = 0;
//--- P-DRAW-66: the head's own x and the two group separators, computed once by
//--- the layout so the painter, the hit test and the carry can never disagree.
static int      s_dsBadgeX = 0;
static int      s_dsSepX[2];
static int      s_dsActX[DSTRIP_ACT_N];
//--- P-DRAW-08k/08j (open-guard) RETIRED with the hold (DRHOLD-OFF, 2026-09-23):
//--- the guard existed because the hold fired while the button was still DOWN
//--- and its release CLICK needed swallowing. Right-click opens ON the release
//--- event itself, so there is nothing left to swallow — kept as history.
//--- P-UI-113c (2026-09-23): AND IT IS BACK, because the LEFT HOLD is the trigger
//--- again and a hold FIRES WHILE THE BUTTON IS STILL DOWN - so its release lands
//--- on the drawing = outside the strip. The guard's state and owners live with
//--- the hold (`s_dsOpenerUntil` below), one window per opening press.
//--- P-DRAW-11: the open popover (ONE at a time, BaseKnot parity): a slot id,
//--- or DSTRIP_MORE for the more-popover. The gear panel is a separate seat
//--- (s_dsGear) and shuts the popover when it opens.
static int      s_dsPicker = DSTRIP_PICK_NONE;
static int      s_dsTpl[DK_COUNT];               // last applied preset per kind
static bool     s_dsTplNameArmed = false;      // P-DRAW-25: save is armed, name edit open
static int      s_dsGearMem[DK_COUNT];         // P-DRAW-26: last gear tab per kind (templates at hand)
static int      s_dsPN = 0;                      // popover rows on screen now
static int      s_dsPY[DSTRIP_PICK_MAX];         // row tops (rows are full-width)
static int      s_dsPHexY = -1;                  // color popover hex band top (-1 = none)
static int      s_dsPHeadY = -1;                 // color popover header band top (-1 = none)
static int      s_dsPRecY = -1;                  // color popover recents band top (-1 = none)
static int      s_dsPOpY = -1;                   // its OPACITY band top (P-DRAW-48)
static bool     s_dsOpGrab = false;              // the bar's own drag is live
static uint     s_dsOpMs = 0;                    // its cadence (DSTRIP_GRIP_MS)
//--- P-DRAW-64 (2026-09-27) — THE PALETTE SCRUB. User order: the live preview may
//--- come back ONLY while the left button is held and dragged across the cells, and
//--- the release applies what is under the pointer — never on a mere hover (that
//--- first cut wrote the PURE colour on the chart and cost the tuned tone). The
//--- gesture owns the view for its length and names itself in `DrawStripViewOwned`.
#define DSTRIP_PAL_TAIL_MS 400                  // the twin release channel's window
static bool     s_dsPalGrab = false;             // a scrub is live
static int      s_dsPalCell = -1;                // its last previewed cell
static uint     s_dsPalMs = 0;                   // its hit-test cadence (DSTRIP_GRIP_MS)
static uint     s_dsPalDoneMs = 0;               // the release that already applied
static string   s_dsPalName[DRAW_SEL_MAX];       // its members (the group, or the held one)
static int      s_dsPalN = 0;
static bool     s_dsHexFocus = false;            // the HEX field is being typed in
//--- P-DRAW-48 (2026-09-26): THE COLOUR BOARD IS ITS OWN CARD. User order:
//--- «پاپ بشه مثل همین» — the reference board floats: its own rounded plate with
//--- the family's shadow, carried by its header, pinned to the plate or left
//--- where the hand put it. It is a THIRD 9-slice family (2) at its own rect,
//--- the same architecture the settings panel took in P-DRAW-32 — the strip's
//--- plate stops growing under it, and the popover bands are measured from the
//--- BOARD's origin (`s_dsBX/s_dsBY`), never the strip's.
static int      s_dsBX = 0, s_dsBY = 0, s_dsBW = 0, s_dsBH = 0;   // the board's own rect
static bool     s_dsBManual = false;             // the hand placed the board: keep that spot
static bool     s_dsBDock = true;                 // pinned: the placer follows the strip
static bool     s_dsBGripLive = false;            // its header carries the BOARD
static int      s_dsBGripDX = 0, s_dsBGripDY = 0;
static uint     s_dsBGripMs = 0;
//--- P-DRAW-75 (2026-09-28): `s_dsBPlateLive` is GONE. "Is family 2 on the chart"
//--- is a fact the object list already answers, and the bool was a second copy of it
//--- (H-06, A-10): a plate a path painted while the flag read false, or one the
//--- P-DRAW-42 orphan sweep removed while it read true, left the copy answering
//--- about a plate that was not there. The two purges that read it are now ONE
//--- decision above the branches, and it asks `ObjectFind` (see DrawStripPaint).
#define DSTRIP_BOARD_HDR 44                      // the header band rides the skin's own top cap
//--- P-DRAW-64: 26, not 22 — B-05's 24 px floor was the thing a user reaching for
//--- the ✕ at the end of a transparency edit kept missing («نمیتونم بسته بکنم»).
#define DSTRIP_PHEAD_XW 26                       // header close button seat
#define DSTRIP_BPIN_XW   26                      // its pin (dock/undock) seat, one step left
#define DSTRIP_PREC_LW  52                       // "RECENT" label seat (its own band's left column)
#define DSTRIP_POP_EDIT_H 22                     // the board's HEX field (OBJ_EDIT) height
//--- P-DRAW-48: the OPACITY bar's own metrics — the cards' tracks, verbatim
//--- (BiotakPanels PNL_TRK_H/KNOB), because the preview's `.opwrap` and the panels'
//--- TRANSPARENCY rows are ONE language and a second set of numbers is a second look.
#define DSTRIP_TRK_H      8                      // the bed's height
#define DSTRIP_KNOB_W    10                      // the knob's seat
#define DSTRIP_KNOB_H    12
#define DSTRIP_OP_VW     38                      // the readout's seat (the preview's .ov 34px)
//--- P-DRAW-66: the HEX field's own seat inside the band it shares with the bar.
#define DSTRIP_HEX_W     96
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
static int      s_dsGRCol[DSTRIP_GLIST_MAX];     // P-DRAW-30: its column (0 left · 1 right)
static int      s_dsGRKind[DSTRIP_GLIST_MAX];    // 1 toggle-slot · 2 preset · 3 save ·
                                                 // 4 level-row · 5 levels All/None · 6 vis ·
                                                 // 7 default-learn · 8 option-row
static int      s_dsGRArg[DSTRIP_GLIST_MAX];     // slot / preset idx / packed
static int      s_dsGGN = 0;                     // gear grid cells on screen
static int      s_dsGGX[DSTRIP_GRID_MAX];
static int      s_dsGGY[DSTRIP_GRID_MAX];
static int      s_dsGGW[DSTRIP_GRID_MAX];
static int      s_dsGGH[DSTRIP_GRID_MAX];
static int      s_dsGGKind[DSTRIP_GRID_MAX];     // 0 swatch (colour in GGC) · 1 chip
static int      s_dsGGSlot[DSTRIP_GRID_MAX];
static int      s_dsGGArg[DSTRIP_GRID_MAX];
static color    s_dsGGC[DSTRIP_GRID_MAX];
//--- P-DRAW-64: the highlight is the CELL's (the rim), so there is no preview
//--- state left to carry — one index is the whole of it. The `s_dsColorHoverN/
//--- Name/Color` trio went with the retired chart preview (this note is why a
//--- future reader must not re-add them without re-reading the report above).
static int      s_dsColorHoverCell = -1;
static int      s_dsGearTab[DSTRIP_GEAR_TAB_MAX + 1];   // tab ids shown (count in [0])
//--- P-DRAW-76: the tab geometry is ONE slot per tab the row may show. These two
//--- arrays were `[4]` while `DSTRIP_GEAR_TAB_MAX` is 5 and the row really does
//--- open five (Paint · Style · Levels|Mark · Look · Row) — so the fifth tab's
//--- x/w was written and read one past the end.
static int      s_dsGearTabX[DSTRIP_GEAR_TAB_MAX], s_dsGearTabW[DSTRIP_GEAR_TAB_MAX];
static int      s_dsGearHeadY = -1;
static int      s_dsGearTabsY = 0;
static int      s_dsGearSecN = 0;
static int      s_dsGearSecY[DSTRIP_GEAR_SECTION_MAX];
static int      s_dsGearSecCol[DSTRIP_GEAR_SECTION_MAX];
static string   s_dsGearSecText[DSTRIP_GEAR_SECTION_MAX];
//--- P-DRAW-66: the caption's own row can carry its CONTROL (C-05: label left,
//--- value right). `s_dsGearSecCX` is that control's x inside the column (-1 = the
//--- caption owns its band alone, the retired two-rows-per-setting shape), and the
//--- two edit arrays are a hex field's own seat and width inside that seat.
static int      s_dsGearSecCX[DSTRIP_GEAR_SECTION_MAX];
static int      s_dsGearEditX[5];
static int      s_dsGearEditW[5];
//--- P-DRAW-30: the WIDE rule's own state. `s_dsGearW` is THIS tab's gear width
//--- (resolved once per layout, read by the head/track/sections painters), and
//--- `s_dsGearBlk*` is the block map the balance split is measured on — one entry
//--- per `DrawStripGearSection()`, i.e. per "header + the content under it".
static int      s_dsGearW = DSTRIP_GEAR_W;
//--- P-DRAW-32: the panel's OWN origin (absolute screen px, its top-left corner)
//--- and height. Every gear painter reads these instead of the strip's plate, so
//--- "where the panel is" has one answer and the two surfaces can never share a
//--- coordinate space again.
static int      s_dsGEX = 0, s_dsGEY = 0;
static int      s_dsGearH = 0;
static bool     s_dsGearManual = false;   // the hand placed the panel: keep its spot
//--- P-DRAW-88 (2026-09-29): THE PANEL STAYS WHERE IT IS. DrawStripPlaceGear's
//--- 8-position scorer ran on EVERY paint, so every tab switch (314 <-> 524 tall)
//--- re-scored from scratch and could crown a different corner — the panel jumped
//--- to "somewhere else" on the exact gesture the user uses most. User order:
//--- «همون‌جا باز بشه». Once placed, a paint only CLAMPS to the window (same as
//--- the manual carry above); a FRESH open — or a different drawing — scores anew.
//--- One flag + the served name, cleared where the panel dies (DrawStripGearClose).
static bool     s_dsGearPlaced = false;
static string   s_dsGearPlacedObj = "";
//--- P-DRAW-75: `s_dsGearPlateLive` went with the board's — the panel's plate is on
//--- the chart iff its own bg object is, and the paint asks.
//--- P-DRAW-89: retired. The plate had four transparency levels; the last reader of
//--- this index was `StrapBodyTone`, and it read the CHART's background through it.
static int      s_dsPlateTIdx = 0;
static int      s_dsGearW0 = 0;           // its outer width (content + pads), for the plate
static int      s_dsGearBlkN = 0;
static int      s_dsGearBlkY[DSTRIP_GEAR_BLK_MAX];
static int      s_dsGearEditY[5];                // edit rows (border-hex/fill-hex/level-add/
                                                 // caption/tpl-name — P-DRAW-64 appended 1)
static int      s_dsGearEditCol[5];              // P-DRAW-30: its column
static int      s_dsGearFootY = 0;
static bool     s_dsVis[DK_COUNT][DRAW_SLOT_N];  // Strip tab: per-slot visibility
static bool     s_dsVisInit = false;
//--- P-DRAW-13: the grip carry (screen-object drag). Screen objects are
//--- SELECTABLE=false, so MT4 never drags our plate for us and P-LM-11's race with
//--- the terminal's own drag cannot happen.
static bool     s_dsGripLive = false;
static int      s_dsGripDX = 0, s_dsGripDY = 0;
static uint     s_dsGripMs = 0;
//--- P-DRAW-32: and the SETTINGS PANEL carries itself the same way (its header is
//--- its handle), with its own offset and its own cadence — one cursor, one of the
//--- two gestures live at a time (`DrawStripGripWhich` answers which).
static bool     s_dsGGripLive = false;
static int      s_dsGGripDX = 0, s_dsGGripDY = 0;
static uint     s_dsGGripMs = 0;
//--- P-UI-113d (2026-09-23): AND THE CARRY TAKES THE PROJECT'S ONE VIEW LOCK for
//--- the length of the gesture (P-UI-53's law, P-UI-90's single owner). The chart
//--- BEHIND the plate stays live and CHART_MOUSE_SCROLL is ON by default, so a
//--- hand that wanders while carrying the plate PANS the view instead of moving
//--- the strip («با درگ استریپ چارت پشتش نباید تکون بخوره که درگ کردن نمیشه یا
//--- سخت میشه»). ONE ender owns the flag, so the acquire/release pair can never
//--- drift — and it lives in this block because `DrawStripClose`, defined below,
//--- must hand the view back (MQL4 reads a bare `void f();` prototype as an
//--- import, so owners are DEFINED before their first use here, never declared).
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
   for(int f = 0; f < DSTRIP_GEAR_FOOT_N; f++)
   {
      string flabel = DrawStripFootText(f);
      int bw = MathMax(DSTRIP_GEAR_FOOT_BW, 32 + PnlTextW(flabel, 8) + fpad);
      int fx = px + f * (bw + DSTRIP_GEAR_FOOT_GAP);
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
      case DRAW_SLOT_FILLCLR:
         return DrawStripColorLabel((color)(int)DrawSlotRead(nm, DRAW_SLOT_FILLCLR)) +
                " " + IntegerToString(DrawSlotAlphaGet(nm, DRAW_SLOT_FILLCLR)) + "%";
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
         // P-DRAW-65: a row NAMES its feature and the switch shows the state —
         // "Empty" was the OFF-state wearing the label's own seat (C-05/C-08).
         return (DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5) ? "Interior on" : "Interior off";
      case DRAW_SLOT_BOXHALF:
         return (DrawSlotRead(nm, DRAW_SLOT_BOXHALF) > 0.5) ? "50 % line on" : "50 % line off";
      case DRAW_SLOT_EXTEND:
         return (DrawSlotRead(nm, DRAW_SLOT_EXTEND) > 0.5) ? "Extend right on" : "Extend right off";
      case DRAW_SLOT_RAY:
      {
         int r = (int)DrawSlotRead(nm, DRAW_SLOT_RAY);
         if(r == 1) return "Ray>";
         if(r == 2) return "<Ray";
         if(r == 3) return "<Ray>";
         return "Segment";
      }
      case DRAW_SLOT_LOCK:
         return (DrawSlotRead(nm, DRAW_SLOT_LOCK) > 0.5) ? "Lock on" : "Lock off";
      //--- P-DRAW-09a: the three appended controls. GLYPH shows the CODE, which
      //--- is the honest caption for a Wingdings mark the user is cycling to —
      //--- MT4's own dialog is where a number like 233 has to be typed.
      case DRAW_SLOT_FONT:
         return IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_FONT)) + "pt";
      case DRAW_SLOT_GLYPH:
         return "G" + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_GLYPH));
      case DRAW_SLOT_BACK:
         // the slot IS `OBJPROP_BACK`, so the word follows the slot, not the wish
         return (DrawSlotRead(nm, DRAW_SLOT_BACK) > 0.5) ? "Layer: behind" : "Layer: front";
      default: return "";
   }
}

//--- P-DRAW-68: A ROW THAT CARRIES A SWITCH NAMES ITS FEATURE. `DrawStripSlotText`
//--- above is the QUICK ROW's cell caption — 32px wide, no switch, so the state has
//--- to live in the words. The settings panel's row is 280px wide and already wears
//--- a 40px switch, so the same string read the state twice ("Interior off" beside an
//--- OFF switch) and broke C-05/C-08 — the cards' own switch rows are all bare
//--- features ("MID ZONES", "SHOW LINES", "MAGNET"). Two questions, two owners.
string DrawStripSwitchName(const string nm, const int slot)
{
   if(slot == DRAW_SLOT_FILL)    return "Interior";
   if(slot == DRAW_SLOT_BOXHALF) return "50 % line";
   if(slot == DRAW_SLOT_EXTEND)  return "Extend right";
   if(slot == DRAW_SLOT_LOCK)    return "Lock";
   if(slot == DRAW_SLOT_BACK)    return "Behind candles";
   return DrawStripSlotText(s_dsKind, slot, nm);
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

//--- P-DRAW-46 (2026-09-26) — THE BOARD SHOWS THE USER'S OWN PALETTE. This face
//--- reads `BioPickAt` in ConstantsAndEnums.mqh (include #1, so both include 97
//--- and 116 can reach it — A-12), and it is the ONE palette face the strip needs:
//--- `DrawStripPal`/`DrawStripPalCount` (BioPal's own 16-colour grid went with
//--- P-DRAW-44) were reachable only through each other, so they went too.
//--- P-DRAW-50: the table is 16 families of 8 and the board shows ONE PAGE of it
//--- — the page is the palette's own state (`BioPickPage`), so this board and the
//--- cards' popup always show the same 64 of the 128, and `s_dsPN`/`DSTRIP_PICK_MAX`
//--- keep fitting 64 exactly as before (a flat 128 would have overflowed the
//--- popover's 72-cell cap and silently lost the second half).
color DrawStripPickPal(const int i)
{
   int n=BIOPICK_PAGE_ROWS*BIOPICK_COLS;
   if(i < 0 || i >= n) return clrSteelBlue;
   return BioPickColor(BioPickPageRow0() + i / BIOPICK_COLS, i % BIOPICK_COLS);
}
int DrawStripPickPalN() { return BIOPICK_PAGE_ROWS * BIOPICK_COLS; }
//--- P-DRAW-50: the board's PAGE SEATS, in its header (the space the pin and the
//--- close do not use). -1 = not on one. Asked before the palette scrub, so a
//--- press on a seat is never a scrub of a cell that is not there.
int DrawStripPageAt(const int mx,const int my)
{
   if(!DrawStripIsColorSlot(s_dsPicker) || s_dsBW <= 0 || s_dsBH <= 0 || s_dsPHeadY < 0) return -1;
   int hy0=s_dsBY+s_dsPHeadY, hy1=hy0+DSTRIP_BOARD_HDR;
   if(my < hy0 || my > hy1) return -1;
   int x0=s_dsBX+s_dsBW-DSTRIP_PAD-DSTRIP_BPIN_XW-2-10-2*20;
   for(int k=0;k<2;k++)
   {
      int xa=x0+k*20;
      if(mx >= xa && mx <= xa+20) return k;      // 0 = previous page, 1 = next
   }
   return -1;
}
void DrawStripPageStep(const int k)
{
   int want=BioPickPage() + ((k==0) ? -1 : 1);
   if(want < 0 || want >= BIOPICK_PAGES) return;
   BioPickPageSet(want);
   DrawStripPaint();   // the board's cells are page-local: a flip is a repaint
}
//--- TV parity board (2026-09-26): the recents are a BAND of their own now, so the
//--- grid indexer and the dedupe face that fed it (`DrawStripPickPalIndex`,
//--- `DrawStripRecentExtra`, `DrawStripPickSwatchAt`) were reachable only through
//--- each other and went with the change.
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
bool DrawStripHasPicker(const int slot)
{
   return (DrawStripIsColorSlot(slot) || slot == DRAW_SLOT_WIDTH ||
           slot == DRAW_SLOT_STYLE || slot == DRAW_SLOT_RAY ||
           slot == DRAW_SLOT_FONT  || slot == DRAW_SLOT_GLYPH ||
           slot == DSTRIP_SLOT_LEVELS);
}
bool DrawStripIsToggle(const int slot)
{
   return (slot == DRAW_SLOT_FILL || slot == DRAW_SLOT_LOCK || slot == DRAW_SLOT_BACK ||
           slot == DRAW_SLOT_BOXHALF || slot == DRAW_SLOT_EXTEND);
}
//--- how many options this popover shows right now (LEVELS = membership rows).
int DrawStripPickCount(const EDrawKind k, const int slot)
{
   // TV parity board: the grid is the user's own 64 — the recents have their own band.
   if(DrawStripIsColorSlot(slot)) return DrawStripPickPalN();
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
   if(!DrawStripIsColorSlot(slot) || row < 0 || row >= DrawStripPickPalN()) return clrNONE;
   return DrawStripPickPal(row);
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
   if(DrawStripIsColorSlot(slot))
   {
      color c = DrawStripPickColor(slot, row);
      return (c != clrNONE && (color)(int)DrawSlotRead(nm, slot) == c);
   }
   if(slot == DRAW_SLOT_WIDTH) return ((int)DrawSlotRead(nm, DRAW_SLOT_WIDTH) == row + 1);
   if(slot == DRAW_SLOT_STYLE) return ((int)DrawSlotRead(nm, DRAW_SLOT_STYLE) == row);
   if(slot == DRAW_SLOT_RAY)   return ((int)DrawSlotRead(nm, DRAW_SLOT_RAY) == row);
   if(slot == DRAW_SLOT_FONT)  return ((int)DrawSlotRead(nm, DRAW_SLOT_FONT) == DrawStripFontAt(row));
   if(slot == DRAW_SLOT_GLYPH) return ((int)DrawSlotRead(nm, DRAW_SLOT_GLYPH) == DrawStripGlyphAt(row));
   return false;
}

int DrawStripColorHoverCellAt(const int mx, const int my)
{
   if(!s_dsOpen) return -1;
   if(s_dsGear == DSTRIP_GEAR_STYLE)
   {
      for(int g = 0; g < s_dsGGN; g++)
      {
         if(s_dsGGKind[g] != 0) continue;
          int x = DrawStripGearX() + s_dsGGX[g], y = s_dsGEY + s_dsGGY[g] + (DSTRIP_GEAR_ROW_H - s_dsGGH[g]) / 2;
          if(mx >= x && mx <= x + s_dsGGW[g] && my >= y && my <= y + s_dsGGH[g]) return g;

      }
   }
   //--- P-DRAW-48: the colour board's bands are the BOARD's (its own origin), so
   //--- the hover must read them there — the strip's origin previewed the colour of
   //--- a phantom cell one row away (reported: the pointer sits on one colour and
   //--- the drawing takes another).
   if(DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0)
   {
      // TV parity board: the grid's own cells, then the RECENT band's.
      for(int r = 0; r < s_dsPN; r++)
      {
          int x = s_dsBX + DSTRIP_PAD + (r % BIOPICK_COLS) * (DSTRIP_PICK_CELL + DSTRIP_PICK_GAP);
          int y = s_dsBY + s_dsPY[r] + (DSTRIP_PICK_ROW - DSTRIP_PICK_CELL) / 2;
          if(mx >= x && mx <= x + DSTRIP_PICK_CELL && my >= y && my <= y + DSTRIP_PICK_CELL)

            return DSTRIP_HOVER_POP_BASE + r;
      }
      if(s_dsPRecY >= 0)
      {
         int ry = s_dsBY + s_dsPRecY + (DSTRIP_PICK_ROW - DSTRIP_PICK_CELL) / 2;
         for(int i = 0; i < s_dsRecentN; i++)
         {
            int rx = s_dsBX + DSTRIP_PAD + DSTRIP_PREC_LW + i * (DSTRIP_PICK_CELL + DSTRIP_PICK_GAP);
            if(mx >= rx && mx <= rx + DSTRIP_PICK_CELL && my >= ry && my <= ry + DSTRIP_PICK_CELL)
               return DSTRIP_HOVER_REC_BASE + i;
         }
      }
   }
   return -1;
}

color DrawStripColorHoverValue(const int cell)
{
   // TV parity board: the RECENT band is tested FIRST (its base is the higher one).
   if(cell >= DSTRIP_HOVER_REC_BASE)
   {
      int i = cell - DSTRIP_HOVER_REC_BASE;
      if(!DrawStripIsColorSlot(s_dsPicker) || i < 0 || i >= s_dsRecentN) return clrNONE;
      return s_dsRecent[i];
   }
   if(cell >= DSTRIP_HOVER_POP_BASE)
   {
      int r = cell - DSTRIP_HOVER_POP_BASE;
      if(!DrawStripIsColorSlot(s_dsPicker) || r < 0 || r >= s_dsPN) return clrNONE;
      return DrawStripPickColor(s_dsPicker, r);
   }
   if(cell < 0 || cell >= s_dsGGN || s_dsGGKind[cell] != 0) return clrNONE;
   return s_dsGGC[cell];
}

void DrawStripColorHoverFace(const int cell, const bool active)
{
   string nm;
   bool current = false;
   if(cell >= DSTRIP_HOVER_REC_BASE)
   {
      int i = cell - DSTRIP_HOVER_REC_BASE;
      if(!DrawStripIsColorSlot(s_dsPicker) || i < 0 || i >= s_dsRecentN) return;
      nm = DrawStripPRecName(i);
      current = (s_dsRecent[i] == DrawStripColorRead(s_dsObj, s_dsPicker));
   }
   else if(cell >= DSTRIP_HOVER_POP_BASE)
   {
      int r = cell - DSTRIP_HOVER_POP_BASE;
      if(!DrawStripIsColorSlot(s_dsPicker) || r < 0 || r >= s_dsPN) return;
      nm = DrawStripPickName(r);
      current = DrawStripPickIsCur(s_dsObj, s_dsKind, s_dsPicker, r);
   }
   else
   {
      if(cell < 0 || cell >= s_dsGGN || s_dsGGKind[cell] != 0) return;
      nm = DrawStripGridName(cell);
      current = (DrawStripColorRead(s_dsObj, DRAW_SLOT_COLOR) == s_dsGGC[cell]);
   }
   if(ObjectFind(0, nm) < 0) return;
   //--- P-UI-69b: the RESTORED rim is the swatch legibility floor, not a bare
   //--- hairline, so the leave-restore lands on exactly what the paint wrote.
   //--- DrawStripColorHoverValue() answers clrNONE for a non-swatch cell and
   //--- BioSwatchBorder reads clrNONE as white, i.e. the hairline — the old rim.
   color rim = (active || current) ? DSTRIP_CLR_ACCENT
                                   : BioSwatchBorder(DrawStripColorHoverValue(cell), BIO_CLR_CARD);
   if((color)ObjectGetInteger(0, nm, OBJPROP_BORDER_COLOR) != rim)
      ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, rim);
}

//--- P-DRAW-64 — THE SCRUB'S STATE, shared by the press, the drag and both release
//--- witnesses. Its writes scale with the GROUP, not with the frame: the hit test
//--- runs on the cadence, but a member is re-inked only when the CELL really
//--- changed, so a 64-drawing group costs 64 writes per cell crossing and none
//--- while the hand rests (G-08/G-09).
bool DrawStripPalHit(const int mx, const int my, int &cell)
{
   cell = -1;
   if(!s_dsOpen || !DrawStripIsColorSlot(s_dsPicker)) return false;
   cell = DrawStripColorHoverCellAt(mx, my);
   if(cell < 0) return false;
   return (DrawStripColorHoverValue(cell) != clrNONE);
}
void DrawStripPalMembers()
{
   s_dsPalN = 0;
   DrawSelPrune();
   int n = DrawSelCount();
   for(int i = 0; i < n && s_dsPalN < DRAW_SEL_MAX; i++)
   { s_dsPalName[s_dsPalN] = DrawSelAt(i); s_dsPalN++; }
   if(s_dsPalN <= 0 && s_dsObj != "")
   { s_dsPalName[0] = s_dsObj; s_dsPalN = 1; }
}
void DrawStripPalPreview(const int cell)
{
   color c = DrawStripColorHoverValue(cell);
   if(c == clrNONE) return;
   for(int i = 0; i < s_dsPalN; i++)
   {
      if(s_dsPicker == DRAW_SLOT_FILLCLR) DrawSlotPreviewFillColor(s_dsPalName[i], c);
      else DrawSlotPreviewColor(s_dsPalName[i], c);
   }
   DrawStripColorHoverFace(cell, true);
   ChartRedraw();
}
void DrawStripPalHighlightEnd()
{
   if(s_dsPalCell >= 0) DrawStripColorHoverFace(s_dsPalCell, false);
   s_dsPalCell = -1;
}
//--- where the scrub's preview points. `-1` = off the palette (the hand left the
//--- grid): the drawing wears its OWN pixels again, because a preview that lingered
//--- off the grid would be a colour the user never released on.
void DrawStripPalTo(const int cell)
{
   if(cell == s_dsPalCell) return;
   if(s_dsPalCell >= 0) DrawStripColorHoverFace(s_dsPalCell, false);
   s_dsPalCell = cell;
   if(cell >= 0) { DrawStripPalPreview(cell); return; }
   for(int i = 0; i < s_dsPalN; i++) DrawSlotRenderRestore(s_dsPalName[i]);
   ChartRedraw();
}

//--- P-DRAW-64 (2026-09-27) — THE HOVER LIGHTS THE CELL, NEVER THE CHART.
//--- Report: «من این شفافیت تنظیم میکنم موس میره روی بقیه رنگه ناخواسته شفافیت
//--- [از دست میره]» — the cell under the pointer used to be written onto the
//--- DRAWING as a live preview (P-DRAW-27). That write went straight to
//--- `OBJPROP_COLOR`, i.e. the PURE colour OUTSIDE the one render owner, so the tone
//--- the user had just tuned on the bar fell back to full strength the moment the
//--- hand crossed a cell on its way to the ✕. A hover is therefore a HIGHLIGHT only
//--- (`.swcell` rim lighting — what a picker is expected to do, and the cheaper path:
//--- not one object write per hovered cell, G-09); the chart preview now rides the
//--- PRESS-DRAG SCRUB above it, which is a deliberate gesture that ENDS in a commit.
void DrawStripColorHoverAt(const int mx, const int my)
{
   int cell = DrawStripColorHoverCellAt(mx, my);
   if(cell == s_dsColorHoverCell) return;
   int old = s_dsColorHoverCell;
   s_dsColorHoverCell = cell;
   if(old >= 0) DrawStripColorHoverFace(old, false);
   if(cell >= 0) DrawStripColorHoverFace(cell, true);
   ChartRedraw();   // the BOARD's own rim moved; the drawing was not touched
}

void DrawStripColorHoverClear()
{
   int old = s_dsColorHoverCell;
   s_dsColorHoverCell = -1;
   if(old >= 0) DrawStripColorHoverFace(old, false);
   //--- P-DRAW-64: "nothing is highlighted" means nothing is PREVIEWED either —
   //--- every close/dismissal path already comes through here, so a scrub that met
   //--- its own end (✕, Esc, another surface, the strip closing) leaves the drawing
   //--- wearing the pixels its tags say. The GRAB flag stays: the view lock belongs
   //--- to the one ender (`DrawStripGripRelease`).
   DrawStripPalTo(-1);
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
         return "Border color: " + DrawStripColorLabel((color)(int)DrawSlotRead(nm, DRAW_SLOT_COLOR)) +
                " — click to choose" + scope;
      case DRAW_SLOT_FILLCLR:
         return "Fill color: " + DrawStripColorLabel((color)(int)DrawSlotRead(nm, DRAW_SLOT_FILLCLR)) +
                " at " + IntegerToString(DrawSlotAlphaGet(nm, DRAW_SLOT_FILLCLR)) +
                "% (" + DrawStripSlotText(k, DRAW_SLOT_FILL, nm) + ") — click to choose, then drag the bar" + scope;
      case DRAW_SLOT_WIDTH:
         return "Line width: " + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_WIDTH)) +
                " px — click to choose" + scope;
      case DRAW_SLOT_STYLE:
         return "Line style: " + DrawStripSlotText(k, DRAW_SLOT_STYLE, nm) +
                " — click to choose" + scope;
      case DRAW_SLOT_FILL:
         return "Fill: " + DrawStripSlotText(k, DRAW_SLOT_FILL, nm) + " — click to toggle" + scope;
      case DRAW_SLOT_RAY:
         return "Ray: " + DrawStripSlotText(k, DRAW_SLOT_RAY, nm) +
                " — click to choose segment/ray/both" + scope;
      case DRAW_SLOT_LOCK:
         return "Lock: " + DrawStripSlotText(k, DRAW_SLOT_LOCK, nm) +
                " — a locked drawing cannot be moved or edited" + scope;
      case DRAW_SLOT_BOXHALF:
         return "50% level: " + DrawStripSlotText(k, DRAW_SLOT_BOXHALF, nm) +
                " — a line at the box's own middle, like a fib level; the box keeps the" +
                " length you drew" + scope;
      case DRAW_SLOT_EXTEND:
         return "Extend right: " + DrawStripSlotText(k, DRAW_SLOT_EXTEND, nm) +
                " — the far edge jumps to the newest bar at once, then travels with" +
                " each new bar (the \"...\" list has the" +
                " other modes: to first touch, or N bars)" + scope;
      case DRAW_SLOT_FONT:
         return "Text size: " + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_FONT)) +
                " pt — click to choose" + scope;
      case DRAW_SLOT_GLYPH:
         return "Arrow mark: glyph " + IntegerToString((int)DrawSlotRead(nm, DRAW_SLOT_GLYPH)) +
                " — click to choose" + scope;
      case DRAW_SLOT_BACK:
         return "Behind the candles: " + DrawStripSlotText(k, DRAW_SLOT_BACK, nm) +
                " — click to toggle" + scope;
      default: break;
   }
   if(slot == DSTRIP_SLOT_LEVELS)
      return "Levels: " + IntegerToString(DrawLevelCount(nm)) + " on — click to edit membership" +
             " (the held drawing; MT4 draws every level it has)";
   return "";
}
//--- P-DRAW-64a: the merged colour seat's two halves, each with its own words —
//--- MT4 shows whichever layer the hand is over, so the seat explains itself
//--- without a mode to remember.
string DrawStripColorRingTip(const string nm, const bool merged)
{
   string t = "Border color: " + DrawStripColorLabel((color)(int)DrawSlotRead(nm, DRAW_SLOT_COLOR)) +
              " — click the RING for its palette";
   if(merged)
      t += ", or the CENTRE for the fill's color (" +
           DrawStripColorLabel((color)(int)DrawSlotRead(nm, DRAW_SLOT_FILLCLR)) + " at " +
           IntegerToString(DrawSlotAlphaGet(nm, DRAW_SLOT_FILLCLR)) + "%)";
   return t + DrawStripTipScope();
}
string DrawStripColorMidTip(const string nm)
{
   return "Fill color: " + DrawStripColorLabel((color)(int)DrawSlotRead(nm, DRAW_SLOT_FILLCLR)) +
          " at " + IntegerToString(DrawSlotAlphaGet(nm, DRAW_SLOT_FILLCLR)) + " — " +
          ((DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5) ? "Filled" : "Empty") +
          " — click the CENTRE for its palette, then drag the bar" + DrawStripTipScope();
}
//--- chrome tooltips: grip/badge/actions.
string DrawStripActTip(const int a)
{
   if(a == DSTRIP_ACT_MORE) return "More: apply-to-all, templates, duplicate, undo";
   if(a == DSTRIP_ACT_GEAR) return "Full settings: style, levels, template, strip";
   if(a == DSTRIP_ACT_PIN) return (s_dsPinned ? "Pinned: outside click won't dismiss — click to unpin"
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
   if(DrawStripIsColorSlot(slot))
   {
      color c = DrawStripPickColor(slot, row);
      if(c == clrNONE) return "";
      return (slot == DRAW_SLOT_FILLCLR ? "Fill color: " : "Border color: ") +
             DrawStripColorLabel(c) + " — click to apply" + scope;
   }
   string t = DrawStripPickText(k, slot, row);
   if(t == "") return "";
   return t + " — click to apply" + scope;
}

//--- which cells wear the "this is ON" face. ONE function, so no cell can
//--- disagree with the state it reports.
bool DrawStripSlotOn(const int slot, const string nm)
{
   if(slot == DRAW_SLOT_FILL) return (DrawSlotRead(nm, DRAW_SLOT_FILL) > 0.5);
   if(slot == DRAW_SLOT_LOCK) return (DrawSlotRead(nm, DRAW_SLOT_LOCK) > 0.5);
   if(slot == DRAW_SLOT_BACK) return (DrawSlotRead(nm, DRAW_SLOT_BACK) > 0.5);
   if(slot == DRAW_SLOT_BOXHALF) return (DrawSlotRead(nm, DRAW_SLOT_BOXHALF) > 0.5);
   if(slot == DRAW_SLOT_EXTEND) return (DrawSlotRead(nm, DRAW_SLOT_EXTEND) > 0.5);
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
// P-DRAW-21/22 — BOX EXTRAS: the 50% line and the user-driven extend.
// Two things MT4's rectangle cannot do: draw its own middle, or reach into the
// future. Both live OUTSIDE the native object:
//   * the mid line is a child OBJ_TREND `<box>_BX50` (DrawToolbar.mqh owns the
//     suffix; the classifier answers DK_NONE for it, so it is never served,
//     never hit-tested, never learned);
//   * the mark itself (`[BX50]` mid, `[BXE1]`/`[BXE2]`/`[BXE3:N]` far edge,
//     `[BXH]` half interior — P-DRAW-64a) is the description channel; its reader
//     and writer moved DOWN to DrawToolbar.mqh with the two SLOTS the user
//     ordered, so both stand above the slot reader (MQL4 define-before-use).
// Everything below is the GEOMETRY those marks drive. The pump (BoxExtrasPump,
// from RefreshKitOnBar) is the only per-tick reader: 2 s throttle, or at once on a
// new bar — a still chart costs one iTime read. Undo stays look-only: an extend
// moves TIME, not the look.
// ══════════════════════════════════════════════════════════════════════════
bool BoxAnchors(const string name, datetime &t0, double &p0, datetime &t1, double &p1)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   t0 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   p0 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
   p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
   return (t0 > 0 && t1 > 0 && p0 > 0.0 && p1 > 0.0);
}
void BoxSetInt(const string nm, const int prop, const long v)
{
   if(ObjectGetInteger(0, nm, prop) != v) ObjectSetInteger(0, nm, prop, v);
}
void BoxSetColor(const string nm, const int prop, const color c)
{
   if((color)(int)ObjectGetInteger(0, nm, prop) != c) ObjectSetInteger(0, nm, prop, c);
}
//--- how far the 50 % line's ink steps back towards the chart background, in percent.
//--- 55 is the number that reads as a guide on both schemes: present enough to aim at,
//--- quiet enough that a box wearing it is not the loudest thing on the chart.
#define BOX_MID_FADE 55
bool BoxMidSync(const string box)
{
   if(box == "" || ObjectFind(0, box) < 0) return false;
   if(DrawObjectType(box) != OBJ_RECTANGLE) return false;
   bool want = false; int ext = BOXEXT_OFF, extN = 0;
   BoxMarkRead(box, want, ext, extN);
   string ch = BoxMidName(box);
   if(!want)
   {
      if(ObjectFind(0, ch) >= 0) ObjectDelete(0, ch);
      return false;
   }
   datetime t0 = 0, t1 = 0; double p0 = 0.0, p1 = 0.0;
   if(!BoxAnchors(box, t0, p0, t1, p1))
   {
      if(ObjectFind(0, ch) >= 0) ObjectDelete(0, ch);
      return false;
   }
   double mp = (p0 + p1) / 2.0;
   if(ObjectFind(0, ch) < 0)
   {
      if(!ObjectCreate(0, ch, OBJ_TREND, 0, t0, mp, t1, mp)) return false;
      ObjectSetInteger(0, ch, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ch, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, ch, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, ch, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, ch, OBJPROP_RAY_RIGHT, false);
      //--- P-DRAW-64a (2026-09-27) — THE LEVEL IS A WHISPER, AND WHISPERS ARE SET ONCE.
      //--- User order: «خط وسط باید نازک تر ... مینمال باشه که چارت شلوغ نشه». Two lines
      //--- did that: the width MIRRORED the box's own (a 2-3 px dotted rule in the same
      //--- ink as the border — the busiest thing a quiet box can wear), and the ink was
      //--- the master's at FULL strength. Now the frame is written here, at birth, and
      //--- never read or written again: 1 px (the thinnest MT4 draws) and STYLE_DOT, so
      //--- the steady state's per-frame cost loses a read AND a compare, and the line is
      //--- the minimum the terminal can put on the chart.
      ObjectSetInteger(0, ch, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, ch, OBJPROP_STYLE, STYLE_DOT);
   }
   else
   {
      //--- P-DRAW-64d: the moves are guarded, so an unthrottled stream costs reads
      //--- and never a repaint it did not earn. A drag event for a box that did not
      //--- move (a click, a selection) used to re-stamp two anchors and invalidate
      //--- the line for nothing; now it is four reads and two compares.
      datetime ct0 = (datetime)ObjectGetInteger(0, ch, OBJPROP_TIME, 0);
      double cp0 = ObjectGetDouble(0, ch, OBJPROP_PRICE, 0);
      datetime ct1 = (datetime)ObjectGetInteger(0, ch, OBJPROP_TIME, 1);
      double cp1 = ObjectGetDouble(0, ch, OBJPROP_PRICE, 1);
      if(ct0 != t0 || cp0 != mp) ObjectMove(0, ch, 0, t0, mp);
      if(ct1 != t1 || cp1 != mp) ObjectMove(0, ch, 1, t1, mp);
   }
   //--- and the INK recedes: the master's own PURE colour blended most of the way
   //--- to the chart background. Reads [CL] first: OBJPROP_COLOR is already the
   //--- blend, re-blending it each sync walks any colour to black in ~20 frames.
   color mc = clrNONE;
   if(!DrawSlotColorPure(box, mc)) mc = (color)(int)ObjectGetInteger(0, box, OBJPROP_COLOR);
   BoxSetColor(ch, OBJPROP_COLOR, BlendColorTowardsBG(mc, BOX_MID_FADE, GetCachedChartBgColor()));
   BoxSetInt(ch, OBJPROP_BACK, ObjectGetInteger(0, box, OBJPROP_BACK));
   return true;
}
void BoxMidDrop(const string box)
{
   if(box == "") return;
   string ch = BoxMidName(box);
   if(ObjectFind(0, ch) >= 0) ObjectDelete(0, ch);
}
void BoxMidSyncServed() { if(s_dsKind == DK_RECT && s_dsObj != "") BoxMidSync(s_dsObj); }
//--- P-DRAW-64a (2026-09-27) — THE LEVEL FOLLOWS THE BORDER'S INK, ON EVERY COMMIT.
//--- Found in the cross-tool pass: the 50 % line wears the border's colour (blended
//--- 55 %), but NO border-colour commit re-inked it — grid, recent, hex and tone all
//--- wrote the box and left the line wearing the OLD blend until the pump's 2 s pass.
//--- So every border-colour commit asks this, and the group gets the same fan-out the
//--- fill's own show has (`DrawStripFillShowGroup`). One description read per member,
//--- a write only when the ink really changed, nothing at rest.
void BoxMidSyncGroup()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return;
   DrawSelPrune();
   int n = DrawSelCount();
   if(n <= 0) { BoxMidSync(s_dsObj); return; }
   for(int i = 0; i < n; i++) BoxMidSync(DrawSelAt(i));
}
//--- P-DRAW-64c (2026-09-27) — THE FIRST STEP IS THE TAP'S, NOT THE NEXT BAR'S.
//--- The pump steps a travelling edge only on a new bar (`ext != OFF && newBar`), so a
//--- box whose edge sat weeks back showed NOTHING for up to a whole bar period after the
//--- tap — on H1, an hour of a gold button on a static box («دکمه اکستند باکس رو به جلو
//--- اکستند نمیکنه»). The tap therefore takes the first step itself, and the pump keeps
//--- it travelling from there. Same fan-out as the mid's: one guarded step per member,
//--- a no-op where the edge is already at the front or the mode is off.
void BoxExtendStepGroup()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return;
   DrawSelPrune();
   int n = DrawSelCount();
   if(n <= 0) { BoxExtendStep(s_dsObj); return; }
   for(int i = 0; i < n; i++) BoxExtendStep(DrawSelAt(i));
}
//--- P-DRAW-64a, third cut: there is NO recheck any more. The 50 % used to be a
//--- remembered LENGTH, so a hand that gave the box a new length had to drop the mark
//--- (else the next tap restored a length the user never chose). A 50 % LEVEL is a
//--- line at the box's own mid PRICE: it is TRUE for every box, at every length, in
//--- every position, so there is no payload to go stale and nothing to re-check.
//--- the extend cycle the strip row taps: off -> to touch -> to end ->
//--- 8 -> 16 -> 32 bars -> off. A tap mid-countdown turns it off outright.
int BoxExtCycle(const string name)
{
   bool mid = false; int ext = BOXEXT_OFF, n = 0;
   BoxMarkRead(name, mid, ext, n);
   if(ext == BOXEXT_OFF) { ext = BOXEXT_TOUCH; n = 0; }
   else if(ext == BOXEXT_TOUCH) { ext = BOXEXT_END; n = 0; }
   else if(ext == BOXEXT_END) { ext = BOXEXT_NBARS; n = 8; }
   else if(ext == BOXEXT_NBARS && n <= 8) n = 16;
   else if(ext == BOXEXT_NBARS && n <= 16) n = 32;
   else { ext = BOXEXT_OFF; n = 0; }
   BoxMarkWrite(name, mid, ext, n);
   return ext;
}
string BoxExtText(const string name)
{
   bool mid = false; int ext = BOXEXT_OFF, n = 0;
   BoxMarkRead(name, mid, ext, n);
   if(ext == BOXEXT_TOUCH) return "Extend: to touch";
   if(ext == BOXEXT_END) return "Extend: to end";
   if(ext == BOXEXT_NBARS) return "Extend: " + IntegerToString(n) + " bars";
   return "Extend: off";
}
//--- one new-bar step for a marked box: the LATER edge travels to the forming
//--- bar. TOUCH stops at the first closed bar whose range meets the box;
//--- NBARS counts down and clears itself. The mid line rides along.
bool BoxExtendStep(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   if(DrawObjectType(name) != OBJ_RECTANGLE) return false;
   bool mid = false; int ext = BOXEXT_OFF, n = 0;
   BoxMarkRead(name, mid, ext, n);
   if(ext == BOXEXT_OFF) return false;
   datetime t0 = 0, t1 = 0; double p0 = 0.0, p1 = 0.0;
   if(!BoxAnchors(name, t0, p0, t1, p1)) return false;
   datetime now = iTime(NULL, 0, 0);
   if(now <= 0) return false;
   int li = (t1 >= t0) ? 1 : 0;
   datetime te = (li == 1) ? t1 : t0;
   if(te < now)
   {
      if(ext == BOXEXT_TOUCH)
      {
         double top = MathMax(p0, p1), bot = MathMin(p0, p1);
         double bh = iHigh(NULL, 0, 1), bl = iLow(NULL, 0, 1);
         if(bl <= top && bh >= bot) { BoxMarkWrite(name, mid, BOXEXT_OFF, 0); return true; }
      }
      ObjectSetInteger(0, name, OBJPROP_TIME, li, now);
      if(ext == BOXEXT_NBARS)
      {
         n--;
         if(n <= 0) BoxMarkWrite(name, mid, BOXEXT_OFF, 0);
         else BoxMarkWrite(name, mid, ext, n);
      }
   }
   if(mid) BoxMidSync(name);
   //--- P-DRAW-64a (2026-09-27): the step moved the box's own edge, so the interior
   //--- gets the same frame the level does — otherwise an extending box with a fill
   //--- wears a stale interior until the pump's next pass. One guarded call per step
   //--- (once a bar), a no-op where no interior lives.
   FillChildSync(name);
   return true;
}
void BoxExtrasPump()
{
   static uint s_bxMs = 0;
   static datetime s_bxBar = 0;
   datetime cb = iTime(NULL, 0, 0);
   bool newBar = (cb != 0 && cb != s_bxBar);
   s_bxBar = cb;
   uint now = GetTickCount();
   if(!newBar && now - s_bxMs < 2000) return;
   s_bxMs = now;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      //--- P-DRAW-64: the interior's children are swept HERE — an orphan (its
      //--- master deleted) or one whose fill went off is dropped in this pass, and
      //--- one whose master moved while nothing was open is re-stamped.
      if(FillIsChild(nm))
      {
         string par = FillChildParent(nm);
         if(par == "" || ObjectFind(0, par) < 0) { ObjectDelete(0, nm); continue; }
         //--- P-DRAW-64: a child of an INDICATOR object is a STRAY — an earlier build
         //--- of this split synced any dragged rectangle, the product's own boxes
         //--- included, which moved such a box's interior into a child and left it
         //--- behind on the next drag («من اینو که جابجا میکنم اون یکی جا میمونه»).
         //--- It goes here, and the master's OWN fill comes back with it, because a
         //--- child only ever existed while that fill was on.
         if(DrawIsIndicatorObject(par))
         {
            ObjectDelete(0, nm);
            if((int)ObjectGetInteger(0, par, OBJPROP_FILL) == 0)
               ObjectSetInteger(0, par, OBJPROP_FILL, true);
            continue;
         }
         FillChildSync(par);
         continue;
      }
      if(nm == "" || DrawIsIndicatorObject(nm)) continue;
      //--- P-DRAW-64a (2026-09-27) — THE MID LINE'S OWN ORPHAN RULE. Deleting a box
      //--- that wore its 50 % left the `<box>_BX50` dotted line on the chart FOREVER:
      //--- the pass skipped anything that IS a mid child, and nothing else knew it.
      //--- So the child answers for its own parent here — one parse and one probe per
      //--- 2 s pass, a delete only when the parent is really gone (the interior's own
      //--- sweep is the same rule, one block up).
      if(BoxIsMidChild(nm))
      {
         string par = BoxMidParent(nm);
         if(par == "" || ObjectFind(0, par) < 0) ObjectDelete(0, nm);
         continue;
      }
      //--- P-DRAW-64: the pass was already paying for ONE type read, so the
      //--- interior's net rides it: a master whose fill is ON (an old build's
      //--- drawing, or one the terminal's own dialog switched back on — the split's
      //--- only silent conflict) and a master that MOVED while nothing was open are
      //--- both re-stamped here. A drawing with no interior costs one probe find.
      int ty = (int)ObjectGetInteger(0, nm, OBJPROP_TYPE);
      if(ty == OBJ_RECTANGLE || ty == OBJ_TRIANGLE || ty == OBJ_ELLIPSE ||
         ty == OBJ_CHANNEL || ty == OBJ_FIBOCHANNEL)
      {
         if(ObjectFind(0, FillChildName(nm)) >= 0 ||
            (int)ObjectGetInteger(0, nm, OBJPROP_FILL) != 0)
            FillChildSync(nm);
      }
      if(ty != OBJ_RECTANGLE) continue;
      if(StringFind(ObjectGetString(0, nm, OBJPROP_TEXT), "[BX") < 0) continue;
      bool mid = false; int ext = BOXEXT_OFF, n = 0;
      BoxMarkRead(nm, mid, ext, n);
      if(mid) BoxMidSync(nm);
      if(ext != BOXEXT_OFF && newBar) BoxExtendStep(nm);
   }
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — THE MORE-POPOVER MODEL. Rows are typed (action vs preset vs
// overflow slot) and rebuilt by ONE builder the layout, the painter and the
// router all read — "which row does what" has exactly one answer.
// ══════════════════════════════════════════════════════════════════════════
//--- P-DRAW-64 — «۵۰ درصد باکس»: THE ONE TAP that fills an interior at half tone.
//--- Its state is exact (interior on AND tone 50), so the row wears a check when
//--- the drawing already is that box; the write itself lives with the tap
//--- (`DrawStripFill50Apply`, after the undo owner).
bool DrawStripFill50IsCur()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   if(DrawSlotRead(s_dsObj, DRAW_SLOT_FILL) < 0.5) return false;
   return (DrawSlotAlphaGet(s_dsObj, DRAW_SLOT_FILLCLR) == DSTRIP_FILL50_TONE);
}
//--- P-DRAW-64 — AN INTERIOR EDIT TURNS THE INTERIOR ON. Choosing the fill's
//--- colour or dragging its bar is a statement about a fill the user expects to
//--- see; with the interior OFF the choice is invisible and reads as "nothing
//--- happened". The same reason `Fill 50%` sets both.
void DrawStripFillShow(const string nm)
{
   if(nm == "" || ObjectFind(0, nm) < 0) return;
   EDrawKind k = DrawKindOf(nm);
   if(!DrawSlotAvailable(k, DRAW_SLOT_FILLCLR)) return;
   if(DrawSlotAvailable(k, DRAW_SLOT_FILL) && DrawSlotRead(nm, DRAW_SLOT_FILL) < 0.5)
      DrawSlotWrite(nm, DRAW_SLOT_FILL, 1.0);
}
//--- the group face of the rule above (the held drawing when there is no group).
void DrawStripFillShowGroup()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return;
   DrawSelPrune();
   int n = DrawSelCount();
   if(n <= 0) { DrawStripFillShow(s_dsObj); return; }
   for(int i = 0; i < n; i++) DrawStripFillShow(DrawSelAt(i));
}
void DrawStripFill50On(const string nm)
{
   if(nm == "" || ObjectFind(0, nm) < 0) return;
   EDrawKind k = DrawKindOf(nm);
   if(!DrawSlotAvailable(k, DRAW_SLOT_FILLCLR)) return;
   if(DrawSlotAvailable(k, DRAW_SLOT_FILL)) DrawSlotWrite(nm, DRAW_SLOT_FILL, 1.0);
   DrawSlotOpacitySet(nm, DSTRIP_FILL50_TONE, DRAW_SLOT_FILLCLR);
}

void DrawStripMoreBuild()
{
   s_dsPN = 0;
   if(s_dsKind == DK_NONE || s_dsObj == "") return;
   EDrawKind k = s_dsKind;
   int r = 0;
   // 1. group apply-all (the retired ALL cell's seat, accent-styled, no icon)
   s_dsMoreKind[r] = DSTRIP_MK_APPLYALL; s_dsMoreArg[r] = 0; r++;
   // 2. templates: every preset + save (the retired TPL/SAVE seats)
   //--- P-DRAW-76: the arg is the SLOT ID, never a position in the list. A cleared template
   //--- leaves a hole (the store keeps the user's numbering), and a position would point at
   //--- that hole and hide the template standing behind it.
   for(int i = 0; i < DRAW_PRESET_MAX && r < DSTRIP_PICK_MAX; i++)
   { if(DrawPresetName(k, i) == "") continue; s_dsMoreKind[r] = DSTRIP_MK_PRESET; s_dsMoreArg[r] = i; r++; }
   if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_SAVE; s_dsMoreArg[r] = 0; r++; }
   // 3. edit: duplicate + undo
   if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_DUPE; s_dsMoreArg[r] = 0; r++; }
   if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_UNDO; s_dsMoreArg[r] = 0; r++; }
   // P-DRAW-21/22: box extras ride the more-popover (the quick row is full for
   // rect: colour/width/style/fill/lock/back) — toggle + cycle, state in text.
   if(k == DK_RECT)
   {
      if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_BOX50; s_dsMoreArg[r] = 0; r++; }
      if(r < DSTRIP_PICK_MAX) { s_dsMoreKind[r] = DSTRIP_MK_BOXEXT; s_dsMoreArg[r] = 0; r++; }
   }
   //--- P-DRAW-64: the half-filled interior, for every kind that HAS one.
   if(DrawKindHasFillBody(k) && r < DSTRIP_PICK_MAX)
   { s_dsMoreKind[r] = DSTRIP_MK_FILL50; s_dsMoreArg[r] = 0; r++; }
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
   if(kind == DSTRIP_MK_BOX50) return "Mid 50% line";
   if(kind == DSTRIP_MK_BOXEXT) return BoxExtText(s_dsObj);
   if(kind == DSTRIP_MK_FILL50) return "Fill 50%";
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
   if(kind == DSTRIP_MK_BOX50)
   {
      bool mid = false; int ext = BOXEXT_OFF, n = 0;
      BoxMarkRead(s_dsObj, mid, ext, n);
      return (mid ? "::Files\\Icons\\gl_check_m.bmp" : "::Files\\Icons\\bk_levels.bmp");
   }
   if(kind == DSTRIP_MK_BOXEXT) return "::Files\\Icons\\bk_ray1.bmp";
   if(kind == DSTRIP_MK_FILL50)
      return (DrawStripFill50IsCur() ? "::Files\\Icons\\gl_check_m.bmp"
                                     : "::Files\\Icons\\gl_droplet_m.bmp");
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
      return "Template: " + DrawPresetName(s_dsKind, arg) +
             (DrawPresetIsBuiltin(arg) ? " (built-in)" : " (mine)") +
             " — click to apply the whole look" + scope +
             (DrawPresetIsBuiltin(arg) ? "" : " — Shift+click deletes it");
   if(kind == DSTRIP_MK_SAVE)
      return "Save this look as one of MY templates — the next drawing of this tool wears it";
   if(kind == DSTRIP_MK_DUPE) return "Copy this drawing beside itself (selects the copy)";
   if(kind == DSTRIP_MK_UNDO)
      return (s_duValid ? "Restore the look before the last edit" : "No edit to undo yet");
   if(kind == DSTRIP_MK_BOX50)
      return "A 50% line across this box (MT4 rectangles have none) — click to toggle" + scope;
   if(kind == DSTRIP_MK_BOXEXT)
      return "Push the far edge with new bars: to first touch, to the end, or N bars — click to cycle" + scope;
   if(kind == DSTRIP_MK_FILL50)
      return "Fill this " + DrawKindName(s_dsKind) + " at 50%: the interior ON, its tone at half" +
             " — one click over the fill color and its bar" + scope;
   if(kind == DSTRIP_MK_SLOT)
      return DrawStripSlotTip(s_dsKind, arg, s_dsObj);
   return "";
}
bool DrawStripMoreIsCur(const int r)
{
   if(r < 0 || r >= s_dsPN) return false;
   if(s_dsMoreKind[r] == DSTRIP_MK_PRESET) return (s_dsMoreArg[r] == s_dsTpl[s_dsKind]);
   if(s_dsMoreKind[r] == DSTRIP_MK_BOX50)
   {
      bool mid = false; int ext = BOXEXT_OFF, n = 0;
      BoxMarkRead(s_dsObj, mid, ext, n);
      return mid;
   }
   if(s_dsMoreKind[r] == DSTRIP_MK_BOXEXT)
   {
      bool mid = false; int ext = BOXEXT_OFF, n = 0;
      BoxMarkRead(s_dsObj, mid, ext, n);
      return (ext != BOXEXT_OFF);
   }
   if(s_dsMoreKind[r] == DSTRIP_MK_FILL50) return DrawStripFill50IsCur();
   return false;
}

//--- P-DRAW-13: the gear panel's layout. Tabs after content width is fixed
//--- (DSTRIP_GEAR_W); grids wrap inside it, lists are full-width. Returns the
//--- y below the block (foot included). painters read the same arrays.
int DrawStripGearTabs()
{
   int n = 0;
   s_dsGearTab[n + 1] = DSTRIP_GEAR_PAINT; n++;
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
   if(tab == DSTRIP_GEAR_PAINT) return "Paint";
   if(tab == DSTRIP_GEAR_STYLE) return "Style";
   if(tab == DSTRIP_GEAR_LEVELS) return "Levels";
   if(tab == DSTRIP_GEAR_MARK) return (s_dsKind == DK_ARROW ? "Mark" : "Text");
   // P-DRAW-65: the two housekeeping tabs wear their short names — with five tabs
   // on a 312 plate the long pair was 45px of the 280 content (B-07).
   if(tab == DSTRIP_GEAR_TPL) return "Look";
   if(tab == DSTRIP_GEAR_STRIP) return "Row";
   return "";
}
bool DrawStripGearGridChips(const int slot, const int count)
{
   int cw = DSTRIP_GEAR_W - 2 * DSTRIP_GEAR_PAD;
   int cols = (cw + DSTRIP_GEAR_GRID_GAP) / (DSTRIP_GEAR_CHIP + DSTRIP_GEAR_GRID_GAP);
   if(cols < 1) cols = 1;
   for(int i = 0; i < count; i++)
   {
      if(s_dsGGN >= DSTRIP_GRID_MAX) return false;
      int g = s_dsGGN++;
      s_dsGGKind[g] = 1; s_dsGGSlot[g] = slot; s_dsGGArg[g] = i;
      s_dsGGW[g] = DSTRIP_GEAR_CHIP;
      s_dsGGH[g] = DSTRIP_GEAR_CHIP_H;
      s_dsGGX[g] = DSTRIP_GEAR_PAD + (i % cols) * (DSTRIP_GEAR_CHIP + DSTRIP_GEAR_GRID_GAP);
      s_dsGGY[g] = -1;
   }
   return true;
}
//--- P-DRAW-73 (2026-09-28): the ceiling is REPORTED once, not obeyed silently. The
//--- owner returned false and every caller dropped the answer, so a tab that outgrew
//--- DSTRIP_GLIST_MAX lost rows with no trace — and the plate shrank to match, so the
//--- panel looked right and was missing settings. Bounded: one static flag, one line.
bool DrawStripGearRow(const int kind, const int arg)
{
   if(s_dsGRN >= DSTRIP_GLIST_MAX)
   {
      static bool said = false;
      if(!said)
      {
         said = true;
         Print("[drawstrip] gear row ceiling reached (", DSTRIP_GLIST_MAX,
               ") — a row was dropped; tab=", s_dsGear, " kind=", (int)s_dsKind);
      }
      return false;
   }
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
      s_dsGGY[g] = y + row * DSTRIP_GEAR_ROW_H;
   }
   y += rows * DSTRIP_GEAR_ROW_H;
}
void DrawStripGearSection(const string text, int &y)
{
   if(s_dsGearSecN < DSTRIP_GEAR_SECTION_MAX)
   {
      s_dsGearSecY[s_dsGearSecN] = y;
      s_dsGearSecCol[s_dsGearSecN] = 0;
      s_dsGearSecText[s_dsGearSecN] = text;
      s_dsGearSecCX[s_dsGearSecN] = -1;   // P-DRAW-66: its own band, no control
      s_dsGearSecN++;
   }
   // P-DRAW-30: a section OPENS A BLOCK — "this header and the content under it"
   // is the unit the wide rule balances, so a header can never be separated from
   // what it labels (the cards' own band rule, PnlRowFull).
   if(s_dsGearBlkN < DSTRIP_GEAR_BLK_MAX) s_dsGearBlkY[s_dsGearBlkN++] = y;
   y += DSTRIP_GEAR_ROW_H;
}
//--- P-DRAW-66 — A CAPTION AND ITS CONTROL ON ONE ROW (C-05). The retired shape
//--- spent TWO bands per setting — a caption band (42) and a control row (42) — so
//--- the Paint tab's three settings cost 252px. This registers the caption on the
//--- row the control then occupies: three settings, 126px, and the card 426 -> 342
//--- (both on the plate law: 48 + 42k).
void DrawStripGearCaptionIn(const string text, const int ctlX, int &y)
{
   if(s_dsGearSecN < DSTRIP_GEAR_SECTION_MAX)
   {
      s_dsGearSecY[s_dsGearSecN] = y;
      s_dsGearSecCol[s_dsGearSecN] = 0;
      s_dsGearSecText[s_dsGearSecN] = text;
      s_dsGearSecCX[s_dsGearSecN] = ctlX;
      s_dsGearSecN++;
   }
   if(s_dsGearBlkN < DSTRIP_GEAR_BLK_MAX) s_dsGearBlkY[s_dsGearBlkN++] = y;
}

//--- P-DRAW-75 (2026-09-28) — A ROW LABEL'S SEAT IS MEASURED, NOT GUESSED. The
//--- Paint tab's two hex fields sat at a fixed 96 written as "12 x 8", but a row
//--- label DRAWS at pt 9 and "COLOR" is 46px: 40px of dead air opened between each
//--- label and its own field, and the band rule was left as a 26px STUB inside it
//--- (LEVEL 90 no. 4 — a hairline carrying no information; B-06/B-07, a real pad).
int DrawStripGearCapW()
{
   int w = PnlTextW("COLOR", DSTRIP_GEAR_LBL_PT);
   int f = PnlTextW("FILL",  DSTRIP_GEAR_LBL_PT);
   if(f > w) w = f;
   //--- P-DRAW-83: the seat is measured FROM THE CAPTION'S OWN X, which is where
   //--- `DrawStripGearSectionsPaint` writes the label (`DSTRIP_GEAR_CAP_X`) — the
   //--- old `w + DSTRIP_ROW_GAP` counted the label's width and forgot the 30px of
   //--- seat the label itself occupies, so the field was placed inside the caption.
   int seat = DSTRIP_GEAR_CAP_X + w + DSTRIP_ROW_GAP;
   return (seat < DSTRIP_PAD) ? DSTRIP_PAD : seat;
}

//--- P-DRAW-74: the panel's content box AFTER the wide pass — the one width the tab
//--- row and the foot centre on. It stood written twice, 32 apart: the tabs asked
//--- `s_dsGearW - 2*PAD` (280) and the foot `s_dsGearW0 - 2*PAD` (312, the PLATE's
//--- inner box), so the foot sat on a rail of its own (H-06). The NARROW build
//--- column below is a different fact and keeps its own constant.
int DrawStripGearColW() { return s_dsGearW - 2 * DSTRIP_GEAR_PAD; }

//--- P-DRAW-30: THE TAB'S CONTENT, built in the NARROW column's own y-space (the
//--- one every block metric above was written for). The wide pass below never
//--- re-derives a block, it TRANSLATES whole blocks into a second column.
void DrawStripGearContent(int &y, bool &levelEdit)
{
   int cw = DSTRIP_GEAR_W - 2 * DSTRIP_GEAR_PAD;
   EDrawKind k = s_dsKind;
   int chipCols = (cw + DSTRIP_GEAR_GRID_GAP) / (DSTRIP_GEAR_CHIP + DSTRIP_GEAR_GRID_GAP);
   if(s_dsGear == DSTRIP_GEAR_PAINT)
   {
      // P-DRAW-44 (2026-09-25) — NO COLOUR GRID HERE. User order: «رنگ و تنظیماتِ
      // استریپ روی همان دو مالکِ کارتها سوار شود». The popover's 60-swatch Material
      // grid is this project's ONE picker (P-DRAW-39) and this tab's 16 was its
      // duplicate — the open item the audit record kept as row 13. HEX stays: an
      // exact value typed by hand exists nowhere else.
      //--- P-DRAW-64: TWO COLOUR FIELDS, because the drawing wears two colours
      //--- now — `e0` is the BORDER's (`[CL…]`) and `e4` the FILL's (`[FL…]`), the
      //--- same two the strip's own cells own. Typing either is the exact-value
      //--- path the palette cannot offer.
      //--- P-DRAW-75: both fields take the ONE measured label seat, so they align on
      //--- the same x without a guessed 96.
      //--- Card parity: one band groups COLOR/FILL/Interior, like the cards'
      //--- own ZONES/GEOMETRY bands (dot + count + hairline).
      DrawStripGearSection("COLORS", y);
      int capW = DrawStripGearCapW();
      //--- P-DRAW-82: THE FIELD IS SIZED FROM THE COLUMN, NOT FROM `cw - seat`.
      //--- `s_dsGearEditW` was `cw - capW` with `cw` hard-coded 280 — the NARROW
      //--- column's width — so on a WIDE panel (624, two columns) the field ran
      //--- 16px past the column's right edge and past the card's own pad. The one
      //--- number that answers "how wide is this column" is `DrawStripGearColW()`
      //--- (the content box the wide pass resolved), and that is what the field
      //--- must measure itself against — the same owner the tab row and the foot
      //--- already ask.
      int colW = DrawStripGearColW();
      DrawStripGearCaptionIn("COLOR", capW, y);
      s_dsGearEditY[0] = y;
      s_dsGearEditX[0] = capW;
      s_dsGearEditW[0] = colW - capW;
      y += DSTRIP_GEAR_ROW_H;
      if(DrawSlotAvailable(k, DRAW_SLOT_FILLCLR))
      {
         DrawStripGearCaptionIn("FILL", capW, y);
         s_dsGearEditY[4] = y;
         s_dsGearEditX[4] = capW;
         s_dsGearEditW[4] = colW - capW;   // P-DRAW-82: the column's own width
         y += DSTRIP_GEAR_ROW_H;
      }
      // P-DRAW-65: the interior is the FILL's own switch, so it stands on the tab
      // that owns the two colour seats — one value, one home.
      //--- P-DRAW-73 (2026-09-28): on the SHARED row, like COLOR and FILL. It wore
      //--- a band of its own for a single member — 42px of plate for one label and a
      //--- "1" pill, which is why the Paint tab read 342 instead of 300.
      //--- P-DRAW-74: the caption and its control are ONE registration now. The label
      //--- was written unconditionally and the switch behind `DrawSlotAvailable`, so a
      //--- line (no interior) got a labelled row with nothing in it and a 42px plate
      //--- to prove it (C-04: a control that cannot act is not shown).
      //--- P-DRAW-75: the CAPTION IS GONE. The row already names its own feature
      //--- (P-DRAW-68: "Interior" beside a switch that says on/off), so a caption
      //--- reading DRAWING beside it was a second name for one value (LEVEL 90
      //--- no. 20/22) plus a gold dot and a rule around nothing. One name.
      if(DrawSlotAvailable(k, DRAW_SLOT_FILL))
         DrawStripGearRow(1, DRAW_SLOT_FILL);
   }
   else if(s_dsGear == DSTRIP_GEAR_STYLE)
   {
      DrawStripGearSection("STROKE", y);
      int mark = s_dsGGN;
      DrawStripGearGridChips(DRAW_SLOT_WIDTH, 5);
      DrawStripGearGridStamp(mark, y, chipCols);
      DrawStripGearSection("LINE STYLE", y);
      mark = s_dsGGN;
      DrawStripGearGridChips(DRAW_SLOT_STYLE, 5);
      DrawStripGearGridStamp(mark, y, chipCols);
      if(DrawSlotAvailable(k, DRAW_SLOT_RAY))
      {
         DrawStripGearSection("RAY", y);
         mark = s_dsGGN;
         DrawStripGearGridChips(DRAW_SLOT_RAY, 4);
         DrawStripGearGridStamp(mark, y, chipCols);
      }
      DrawStripGearSection("SHAPE", y);
      //--- P-DRAW-64a: the strip's two cells are switches of the DRAWING's own
      //--- geometry, so they stand together — one value, two surfaces.
      if(DrawSlotAvailable(k, DRAW_SLOT_BOXHALF)) DrawStripGearRow(1, DRAW_SLOT_BOXHALF);
      if(DrawSlotAvailable(k, DRAW_SLOT_EXTEND))      DrawStripGearRow(1, DRAW_SLOT_EXTEND);
      DrawStripGearSection("LAYER", y);
      DrawStripGearRow(1, DRAW_SLOT_LOCK);
      DrawStripGearRow(1, DRAW_SLOT_BACK);
   }
   else if(s_dsGear == DSTRIP_GEAR_LEVELS)
   {
      DrawStripGearSection("LEVELS", y);
      int nl = DrawStripGearLevelCount();
      //--- P-DRAW-73: a refused row STOPS the loop, so what is left is a prefix of the
      //--- list and the owner has already named the loss in the log.
      for(int i = 0; i < nl; i++) { if(!DrawStripGearRow(4, i)) break; }
      DrawStripGearRow(5, 0);
      DrawStripGearRow(5, 1);
      levelEdit = true;
   }
   else if(s_dsGear == DSTRIP_GEAR_MARK)
   {
      if(k == DK_TEXT)
      {
         DrawStripGearSection("CAPTION", y);
         s_dsGearEditY[2] = y; y += DSTRIP_GEAR_ROW_H;
         DrawStripGearSection("SIZE", y);
         int mark = s_dsGGN;
         DrawStripGearGridChips(DRAW_SLOT_FONT, DrawStripFontCount());
         DrawStripGearGridStamp(mark, y, chipCols);
      }
      else
      {
         DrawStripGearSection("MARK", y);
         for(int g = 0; g < DrawStripGlyphCount(); g++)
            if(!DrawStripGearRow(8, DRAW_SLOT_GLYPH * 256 + g)) break;
      }
   }
   else if(s_dsGear == DSTRIP_GEAR_TPL)
   {
      DrawStripGearSection("TEMPLATES", y);
      //--- P-DRAW-76: slot ids (see the more-popover's builder) — a hole never shifts the list.
      for(int i = 0; i < DRAW_PRESET_MAX; i++)
      { if(DrawPresetName(k, i) == "") continue; if(!DrawStripGearRow(2, i)) break; }
      DrawStripGearRow(3, 0);
      DrawStripGearRow(7, 0);
   }
   else if(s_dsGear == DSTRIP_GEAR_STRIP)
   {
      DrawStripGearSection("QUICK ROW", y);
      for(int s = 0; s < DRAW_SLOT_N; s++)
      {
         if(s == DRAW_SLOT_MORE) continue;
         if(!DrawSlotAvailable(k, s)) continue;
         if(!DrawStripGearRow(6, s)) break;
      }
      if(DrawKindHasLevels(k)) DrawStripGearRow(6, DRAW_SLOT_MORE);
      DrawStripGearRow(5, 2);
   }
}
//--- P-DRAW-30: move every item whose y sits inside one block into its column.
//--- Grids carry their own X (the colour hover hit test reads it back), so their
//--- column shift is baked here; rows, sections and edits keep a column index the
//--- painter adds. Membership by Y is exact: every block boundary and every item
//--- in a block sits on the same 42px grid the content was built on.
void DrawStripGearShiftItems(const int yFrom, const int yTo, const int shift, const int col)
{
   for(int r = 0; r < s_dsGRN; r++)
      if(s_dsGRY[r] >= yFrom && s_dsGRY[r] < yTo)
      { s_dsGRY[r] += shift; s_dsGRCol[r] = col; }
   for(int g = 0; g < s_dsGGN; g++)
      if(s_dsGGY[g] >= yFrom && s_dsGGY[g] < yTo)
      { s_dsGGY[g] += shift; s_dsGGX[g] += col * DSTRIP_GEAR_COL; }
   for(int i = 0; i < s_dsGearSecN; i++)
      if(s_dsGearSecY[i] >= yFrom && s_dsGearSecY[i] < yTo)
      { s_dsGearSecY[i] += shift; s_dsGearSecCol[i] = col; }
   for(int e = 0; e < 5; e++)
      if(s_dsGearEditY[e] >= yFrom && s_dsGearEditY[e] < yTo)
      { s_dsGearEditY[e] += shift; s_dsGearEditCol[e] = col; }
}
//--- P-DRAW-30 — THE WIDE PASS. `contentEnd` comes in as the narrow stack's own
//--- bottom and leaves as the two-column stack's, so the plate's height (always
//--- 48 + 42k, the skin's own arithmetic) stays on the grid either way.
//---   * a tab with TWO OR MORE blocks: the block map is the balance, and the
//---     split is the contiguous boundary that minimises the taller column —
//---     reading order is kept column by column, and no header leaves its rows;
//---   * a tab with ONE block (a fibo's level list): there is no boundary to
//---     choose, so the ROW RUN splits at its own middle and the section header
//---     stays at the top of the left column. Without this a 20-level fibo would
//---     still grow one 20-row tower — the very complaint this rule answers.
//--- P-DRAW-82: A FIELD'S WIDTH IS A DERIVED RECT, SO IT IS RE-DERIVED WHEN THE
//--- COLUMN CHANGES. `DrawStripGearContent` measured it against the narrow
//--- column (280) because that is the only width known while the content is still
//--- being built; the wide pass then moved the same field into a 592px column and
//--- nothing re-measured it — so on a wide tab every hex field ran 312px past its
//--- column and off the card. One pass, on the two paths that change the width,
//--- and only over the five edit slots.
void DrawStripGearResizeEdits()
{
   int colW = DrawStripGearColW();
   for(int e = 0; e < 5; e++)
      if(s_dsGearEditY[e] >= 0)
      {
         int seat = s_dsGearEditX[e];
         //--- a clamp to zero would delete the field's own object mid-paint, and
         //--- a field is the only way to type an exact value: if the caption
         //--- leaves no room, the field keeps the WHOLE column rather than none.
         if(seat >= colW) { s_dsGearEditX[e] = 0; seat = 0; }
         if(seat < colW)   s_dsGearEditW[e] = colW - seat;
      }
}

void DrawStripGearPlace(const int contentTop, int &contentEnd)
{
   s_dsGearW = DSTRIP_GEAR_W;
   for(int r = 0; r < s_dsGRN; r++) s_dsGRCol[r] = 0;
   for(int i = 0; i < s_dsGearSecN; i++) s_dsGearSecCol[i] = 0;
   for(int e = 0; e < 5; e++) s_dsGearEditCol[e] = 0;
   //--- P-DRAW-86 (2026-09-29) — A NARROW PLATE MUST FIT THE BAKED CARD SET.
   //--- The guard said "<= 10 content rows stays narrow", but the plate's height is
   //--- `contentEnd + FOOT_H` (48) and `DrawStripGearPlate` builds `cardN = (gh-104)/42`
   //--- from it — so n content rows need card `n + 1`, and `pnl_card<n>.bmp` stops at
   //--- 10 (measured on the files: 174..552 tall, 340 wide). A tab with exactly 10
   //--- content rows therefore stayed NARROW with `cardN = 11`, no bake existed,
   //--- `cardExact` read 0 and the plate fell into the composed W body — whose bake is
   //--- `pnl_cardWtop/mid/bot.bmp` at **652 px**, cropped by MT4 to the 340 the narrow
   //--- plate asked for: a 312px panel drawn as the LEFT HALF of a 624px card.
   //--- MEASURED: log `PLATE tab=1 h=566 w=312 cardN=11 exact=0 narrow=1 -> branch=wide`
   //--- (Style, 10 content rows: 4 bands + 2 chip rows + 4 switches) against
   //--- `pnl_cardWtop.bmp 652 70` and a request of `gw + 28 = 340`. Style is reachable
   //--- on every rectangle/line kind, so the user saw a half-card plate.
   //--- The card set is the law: narrow only while the narrow plate's OWN card exists,
   //--- i.e. at most `WIDE_ROWS - 1` content rows. Read by this one owner.
   if(contentEnd - contentTop <= (DSTRIP_GEAR_WIDE_ROWS - 1) * DSTRIP_GEAR_ROW_H) return;
   if(s_dsGearBlkN >= 2)
   {
      int split = -1, bestH = 0;
      for(int b = 1; b < s_dsGearBlkN; b++)
      {
         int hL = s_dsGearBlkY[b] - contentTop;
         int hR = contentEnd - s_dsGearBlkY[b];
         int h = (hL > hR ? hL : hR);
         if(split < 0 || h < bestH) { bestH = h; split = b; }
      }
      if(split > 0)
      {
         int top[2];
         top[0] = contentTop; top[1] = contentTop;
         for(int b2 = 0; b2 < s_dsGearBlkN; b2++)
         {
            int from = s_dsGearBlkY[b2];
            int to = (b2 + 1 < s_dsGearBlkN ? s_dsGearBlkY[b2 + 1] : contentEnd);
            int col = (b2 < split ? 0 : 1);
            DrawStripGearShiftItems(from, to, top[col] - from, col);
            top[col] += to - from;
         }
         contentEnd = (top[0] > top[1] ? top[0] : top[1]);
         s_dsGearW = DSTRIP_GEAR_W2;
         DrawStripGearResizeEdits();   // P-DRAW-82: a column just became 592
         return;
      }
   }
   if(s_dsGRN < 4) return;
   int half = (s_dsGRN + 1) / 2;
   if(half < 1 || half >= s_dsGRN) return;
   int splitY = s_dsGRY[half];
   DrawStripGearShiftItems(splitY, contentEnd, contentTop - splitY, 1);
   int hL = splitY - contentTop, hR = contentEnd - splitY;
   contentEnd = contentTop + (hL > hR ? hL : hR);
   s_dsGearW = DSTRIP_GEAR_W2;
   DrawStripGearResizeEdits();   // P-DRAW-82: a column just became 592
}
int DrawStripGearLayout(int y0)
{
   int y = y0;
   s_dsGearHeadY = y0;
   int nt = DrawStripGearTabs();
   int total = 0;
   for(int t = 0; t < nt && t < DSTRIP_GEAR_TAB_MAX; t++)
      total += DSTRIP_TAB_PAD + PnlTextW(DrawStripGearTabText(s_dsGearTab[t + 1]), 8);
   if(nt > 1) total += (nt - 1) * DSTRIP_TAB_GAP;
   s_dsGearTabsY = y + DSTRIP_GEAR_HEAD_H;
   for(int t2 = 0; t2 < nt && t2 < DSTRIP_GEAR_TAB_MAX; t2++)
   {
      int tab = s_dsGearTab[t2 + 1];
      s_dsGearTabW[t2] = DSTRIP_TAB_PAD + PnlTextW(DrawStripGearTabText(tab), 8);
      s_dsGearTabX[t2] = 0;   // centred below, once the panel's own width is known
   }
   y += DSTRIP_GEAR_HEAD_H + DSTRIP_GEAR_ROW_H;
   int contentTop = y;
   s_dsGRN = 0; s_dsGGN = 0; s_dsGearSecN = 0; s_dsGearBlkN = 0;
   for(int e0 = 0; e0 < 5; e0++)
   { s_dsGearEditY[e0] = -1; s_dsGearEditX[e0] = 0; s_dsGearEditW[e0] = 0; }
   bool levelEdit = false;
   DrawStripGearContent(y, levelEdit);
   for(int r = 0; r < s_dsGRN; r++) { s_dsGRY[r] = y + r * DSTRIP_GEAR_ROW_H; s_dsGRCol[r] = 0; }
   y += s_dsGRN * DSTRIP_GEAR_ROW_H;
   if(levelEdit)
   {
      s_dsGearEditY[1] = y;
      y += DSTRIP_GEAR_ROW_H;
   }
   if(s_dsGear == DSTRIP_GEAR_TPL && s_dsTplNameArmed)
   {
      s_dsGearEditY[3] = y;
      y += DSTRIP_GEAR_ROW_H;
   }
   int contentEnd = y;
   DrawStripGearPlace(contentTop, contentEnd);
    // P-DRAW-36: the tab row centres on the width THIS pass just decided — the wide
    // pass has already run and owns s_dsGearW. `s_dsGearW0` is written by the CALLER
    // after this function returns, so reading it here answered with the previous
    // panel's width: 0 on a fresh open, which pinned the row to the left edge.
    // P-DRAW-74: and on the content box's ONE owner, which the foot asks too.
    int gcw = DrawStripGearColW();
   int tx = DSTRIP_GEAR_PAD + MathMax(0, (gcw - total) / 2);
   for(int t3 = 0; t3 < nt && t3 < DSTRIP_GEAR_TAB_MAX; t3++)
   {
      s_dsGearTabX[t3] = tx;
      tx += s_dsGearTabW[t3] + DSTRIP_TAB_GAP;
   }
   s_dsGearFootY = contentEnd;
   y = contentEnd + DSTRIP_GEAR_FOOT_H;
   //--- P-DRAW-78: the height reads the CARDS' law now (56 + n*42 + 48), not the
   //--- retired 48 + 42k skin law — see DSTRIP_GEAR_AIR. A height off that grid
   //--- falls back to the composed W body inside DrawStripGearPlate.
   y += DSTRIP_GEAR_AIR;
   return y;
}

//--- P-DRAW-13: the shell's own widths and positions, in ONE pass: the painter,
//--- the plate's size, the hit test and the grip carry all read these, so
//--- "where a cell is" has exactly one answer. Single row, never wraps:
//--- [grip][badge][<=6 icons][more][gear][pin][del], then the open blocks.
void DrawStripLayout()
{
   DrawStripColorHoverClear();
   DrawStripVisInit();
   EDrawKind k = s_dsKind;
   s_dsN = DrawStripQuickCount(k);
   //--- P-DRAW-66: THE THREE GROUPS. The name's reservation IS its ink (the
   //--- retired `+12` with a 40px floor floated it in a gap of its own), and two
   //--- separators split [identity | values | commands].
   int x = DSTRIP_PAD;
   x += DSTRIP_CELL;                                  // grip
   x += DSTRIP_HEAD_AIR;                              // grip → the name
   s_dsBadgeX = x;
   s_dsBadgeW = PnlTextW(DrawStripTitle(), 9);        // the name's own ink
   x += s_dsBadgeW;
   x += DSTRIP_SEP_AIR;                               // identity | values
   s_dsSepX[0] = x;
   x += DSTRIP_SEP_W + DSTRIP_SEP_AIR;
   for(int i = 0; i < s_dsN; i++)
   {
      if(i > 0) x += DSTRIP_GAP;
      s_dsCX[i] = x;
      s_dsCW[i] = DSTRIP_CELL;
      x += DSTRIP_CELL;
   }
   x += DSTRIP_SEP_AIR;                               // values | commands
   s_dsSepX[1] = x;
   x += DSTRIP_SEP_W + DSTRIP_SEP_AIR;
   for(int a = 0; a < DSTRIP_ACT_N; a++)
   {
      if(a > 0) x += DSTRIP_GAP;
      s_dsActX[a] = x;
      x += DSTRIP_CELL;
   }
   x += DSTRIP_PAD;
   int quickW = x;
   int y = DSTRIP_PAD + DSTRIP_CELL + DSTRIP_GAP;    // first open block's top
   int maxW = quickW;
    //--- popover block (ONE at a time): colour grid, or full-width list rows.
    s_dsPN = 0;
    s_dsPHexY = -1;
    s_dsPHeadY = -1;
    s_dsPRecY = -1;
    s_dsPOpY = -1;
    s_dsBW = 0; s_dsBH = 0;   // P-DRAW-48: the board's rect exists only for a colour board
    if(DrawStripIsColorSlot(s_dsPicker))   // P-DRAW-64: the BORDER's or the INTERIOR's
    {
       // P-DRAW-46: the picker's OWN columns — 8 cells per row (the user's own
       // chart).
       // TV parity (2026-09-26): the board reads like the reference — a header
       // band (grip + name + pin + close, and the carry handle), the 8 x 8 grid,
       // a labelled RECENT band, then the HEX field.
       // P-DRAW-48: and its bands are measured from the BOARD's origin, because
       // the board is its own card. The header rides the skin's own 44px top cap
       // and the remaining ten bands are the middles, so the plate is on the
       // family's own law: 48 + 42k (k = rows + recents + hex).
      int n = DrawStripPickPalN();
      int cols = BIOPICK_COLS, cw = DSTRIP_PICK_CELL;
      int gw = cols * cw + (cols - 1) * DSTRIP_PICK_GAP;
      int rows = (n + cols - 1) / cols;
      s_dsBW = gw + 2 * DSTRIP_PAD;
      // P-DRAW-48: FOUR bands under the grid — RECENT, HEX and the reference's
      // own OPACITY bar («نوار شفافیت رو نداره مثل پیش نمایش»), so k = rows + 3.
      s_dsBH = 48 + DSTRIP_PICK_ROW * (rows + 2);
      s_dsPHeadY = 0;
      int by = DSTRIP_BOARD_HDR;
      for(int r = 0; r < n; r++) s_dsPY[r] = by + (r / cols) * DSTRIP_PICK_ROW;
      by += rows * DSTRIP_PICK_ROW;
      s_dsPRecY = by;
      //--- P-DRAW-66: HEX and the OPACITY bar share ONE band — the board is
      //--- 48 + 42 * (rows + 2) = 468 tall instead of 510, and the two things a
      //--- colour is judged by (its exact value and its tone) sit side by side.
      s_dsPHexY = by + DSTRIP_PICK_ROW;
      s_dsPOpY  = s_dsPHexY;
      s_dsPN = n;
      //--- the STRIP stays the compact quick row: the board never widens its
      //--- plate (P-DRAW-48) and never grows it taller either.
      DrawStripBoardPlace();
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
      for(int r2 = 0; r2 < need; r2++) s_dsPY[r2] = y + r2 * DSTRIP_PICK_ROW;
      y += need * DSTRIP_PICK_ROW;
      if(lw + 2 * DSTRIP_PAD > maxW) maxW = lw + 2 * DSTRIP_PAD;
      s_dsPN = need;
   }
   //--- P-DRAW-32 (2026-09-24) — THE SETTINGS PANEL IS ITS OWN SURFACE. It used
   //--- to be THIS plate GROWING tall (one window wearing both), so opening
   //--- settings turned the toolbar into a tower. It is laid out in its OWN
   //--- y-space now (0 = the panel plate's own top) and can no longer move
   //--- s_dsW/s_dsH — the strip stays the compact quick row it is, and the two
   //--- rects are placed and carried apart (`DrawStripPlaceGear`).
   s_dsGRN = 0; s_dsGGN = 0;
   s_dsGearH = 0; s_dsGearW0 = 0; s_dsGearHeadY = -1;
   if(s_dsGear != 0)
   {
      s_dsGearH = DrawStripGearLayout(0);
      // P-DRAW-30: the panel's own width, wide (624 + pads) or narrow (312 + pads).
      s_dsGearW0 = s_dsGearW;   // P-DRAW-75: the plate IS the card (312/624), not card+pads
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
      return DrawStripLevelName(v) + (on ? " is on — click to remove" : " — click to add") +
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
//--- TV parity board: its chrome — the grip band, the RECENT band and the HEX
//--- field — belongs to the COLOUR popover alone, and the ONE owner of taking it
//--- down. A slot switch does NOT pass a close (`DrawStripTap` assigns the new
//--- slot directly), so the paint's list branch prunes it too; without that a
//--- width/style list would open under the board's leftover header and field.
bool DrawStripPopChromePrune()
{
   bool dirty = false;
   string fx[17];
   fx[0] = "PnlDrawS_PHeadT";
   fx[1] = "PnlDrawS_PHeadX";
   fx[2] = DrawStripPHeadGName();
   fx[3] = DrawStripPHeadGChipName();
   fx[4] = DrawStripPHeadGIconName();
   fx[5] = DrawStripPRecLabelName();
   fx[6] = DrawStripPHexLbName();
   fx[7] = DrawStripPHexEdName();
   //--- P-DRAW-48: the board's own pin seat + its face — the header's two new
   //--- children, so a close cannot leave a dock glyph over a gone plate.
   fx[8] = "PnlDrawS_PHeadP";
   fx[9] = "PnlDrawS_PHeadPI";
   //--- and the OPACITY band's own five: its chrome dies with the board's.
   fx[10] = DrawStripPOpLbName();
   fx[11] = DrawStripPOpBedName();
   fx[12] = DrawStripPOpFillName();
   fx[13] = DrawStripPOpKnobName();
   fx[14] = DrawStripPOpValName();
   //--- P-DRAW-64a: the header's two role segments — a close cannot leave a
   //--- BORDER / FILL caption over a gone plate.
   fx[15] = "PnlDrawS_PHeadB";
   fx[16] = "PnlDrawS_PHeadF";
   for(int i = 0; i < 17; i++)
      if(ObjectFind(0, fx[i]) >= 0) { ObjectDelete(0, fx[i]); dirty = true; }
   for(int k = 0; k < DSTRIP_RECENT_MAX; k++)
   {
      if(ObjectFind(0, DrawStripPRecName(k)) >= 0)
      { ObjectDelete(0, DrawStripPRecName(k)); dirty = true; }
      if(ObjectFind(0, DrawStripPRecGlassName(k)) >= 0)
      { ObjectDelete(0, DrawStripPRecGlassName(k)); dirty = true; }
   }
   s_dsPRecY = -1;
   s_dsPOpY = -1;
   s_dsOpGrab = false;
   s_dsHexFocus = false;
   //--- P-DRAW-48: and the BOARD's own state — a fresh board is a fresh PLACE
   //--- (the pin's DOCK choice is the user's preference and survives).
   s_dsBManual = false;
   s_dsBW = 0; s_dsBH = 0;
   s_dsBGripLive = false;
   return dirty;
}
void DrawStripClosePicker()
{
   DrawStripColorHoverClear();
   DrawStripPopChromePrune();   // TV parity board: its chrome dies with it
   //--- P-DRAW-75 (2026-09-28): the board's plate (family 2) dies with it, and the
   //--- gate is the PLATE, not a flag — a list popover probes nothing it never made,
   //--- and a plate a path left behind can no longer outlive the state that painted
   //--- it. DrawStripPaint asks the same question and answers it the same way.
   if(ObjectFind(0, DrawStripBoardBgName()) >= 0) DrawStripSkinPurgeAt(2);
   if(s_dsPicker == DSTRIP_PICK_NONE && s_dsPN <= 0) return;
   for(int r = 0; r < DSTRIP_PICK_MAX; r++)
   {
      ObjectDelete(0, DrawStripPickName(r));
      ObjectDelete(0, DrawStripPickIconName(r));
      ObjectDelete(0, DrawStripPickLabelName(r));
      ObjectDelete(0, DrawStripPickChipName(r));
      ObjectDelete(0, DrawStripPickRailName(r));
       ObjectDelete(0, DrawStripPickGlassName(r));   // P-DRAW-33: the glass sheen
    }
    s_dsPicker = DSTRIP_PICK_NONE;
    s_dsPN = 0;
    s_dsPHexY = -1;
    s_dsPHeadY = -1;
    s_dsPRecY = -1;
    s_dsPOpY = -1;
    s_dsOpGrab = false;
    s_dsHexFocus = false;
}
//--- P-DRAW-13: shut the gear panel (tab switch = shut + open).
//--- P-DRAW-77: ONE PREFIX WIPE, not a hand list. The list below could only delete
//--- the names it knew, so every object a previous build had created under a name
//--- this one no longer paints (a retired head chip, a renamed close) survived
//--- every tab switch and every close — which is the report: a second header and a
//--- second close sitting on the chart beside the panel's own, the two mixed. The
//--- plate goes with the wipe and `DrawStripGearPlate` rebuilds it on the next
//--- paint, so nothing is lost and nothing can be stranded. One terminal scan
//--- instead of ~300 ObjectDelete calls.
bool DrawStripGearObjectsPurge()
{
   bool dirty = false;
   //--- One prefix wipe when the panel owned anything: the plate rebuilds on the
   //--- next paint while the panel is open, and stays gone when it is shut.
   if(ObjectFind(0, DrawStripGearTabName(0)) >= 0 || ObjectFind(0, DrawStripGearBgName()) >= 0
      || ObjectFind(0, "PnlDrawS_Gtop") >= 0)
   { ObjectsDeleteAll(0, "PnlDrawS_G", -1, -1); dirty = true; return dirty; }
   for(int t = 0; t < 5; t++)
      if(ObjectFind(0, DrawStripGearTabName(t)) >= 0)
      { ObjectDelete(0, DrawStripGearTabName(t)); dirty = true; }
   if(ObjectFind(0, DrawStripGearTrackName()) >= 0)
   { ObjectDelete(0, DrawStripGearTrackName()); dirty = true; }
   if(ObjectFind(0, DrawStripGearTabLineName()) >= 0)
   { ObjectDelete(0, DrawStripGearTabLineName()); dirty = true; }
   string hn = DrawStripGearHeadName("TB"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("HR"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("MK"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("MG"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("TT"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("ST"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("VB"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("VT"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("X"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("XB"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   hn = DrawStripGearHeadName("XI"); if(ObjectFind(0, hn) >= 0) { ObjectDelete(0, hn); dirty = true; }
   for(int s = 0; s < DSTRIP_GEAR_SECTION_MAX; s++)
   {
      string sn = DrawStripGearSectionName(s);
      if(ObjectFind(0, sn) >= 0) { ObjectDelete(0, sn); dirty = true; }
      if(ObjectFind(0, sn + "D") >= 0) { ObjectDelete(0, sn + "D"); dirty = true; }
      if(ObjectFind(0, sn + "T") >= 0) { ObjectDelete(0, sn + "T"); dirty = true; }
      if(ObjectFind(0, DrawStripGearSectionLineName(s)) >= 0)
      { ObjectDelete(0, DrawStripGearSectionLineName(s)); dirty = true; }
   }
   for(int g = 0; g < DSTRIP_GRID_MAX; g++)
   {
      if(ObjectFind(0, DrawStripGridName(g)) >= 0)
      { ObjectDelete(0, DrawStripGridName(g)); dirty = true; }
      if(ObjectFind(0, DrawStripGridIconName(g)) >= 0)
      { ObjectDelete(0, DrawStripGridIconName(g)); dirty = true; }
      if(ObjectFind(0, DrawStripGridGlassName(g)) >= 0)
      { ObjectDelete(0, DrawStripGridGlassName(g)); dirty = true; }   // P-DRAW-33
   }
   for(int r = 0; r < DSTRIP_GLIST_MAX; r++)
   {
      if(ObjectFind(0, DrawStripRowName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowIconName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowIconName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowLabelName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowLabelName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowChipName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowChipName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowRailName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowRailName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowStateName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowStateName(r)); dirty = true; }
      if(ObjectFind(0, DrawStripRowSepName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowSepName(r)); dirty = true; }
   }
    for(int f = 0; f < DSTRIP_GEAR_FOOT_N; f++)
    {
      if(ObjectFind(0, DrawStripFootName(f)) >= 0)
      { ObjectDelete(0, DrawStripFootName(f)); dirty = true; }
      if(ObjectFind(0, DrawStripFootSkinName(f)) >= 0)
      { ObjectDelete(0, DrawStripFootSkinName(f)); dirty = true; }
      if(ObjectFind(0, DrawStripFootGlyphName(f)) >= 0)
      { ObjectDelete(0, DrawStripFootGlyphName(f)); dirty = true; }
      if(ObjectFind(0, DrawStripFootLabelName(f)) >= 0)
      { ObjectDelete(0, DrawStripFootLabelName(f)); dirty = true; }
   }
   for(int e = 0; e < 5; e++)
      if(ObjectFind(0, DrawStripEditName(e)) >= 0)
      { ObjectDelete(0, DrawStripEditName(e)); dirty = true; }
   return dirty;
}
//--- P-DRAW-85 (2026-09-29) — A FRESH ATTACH OWNS A CLEAN CHART.
//--- Reported: «جابجا بین تب‌ها می‌شم این‌طوری می‌شه» with a screenshot of ONE card
//--- carrying TWO tabs at once (Style's LINE STYLE / SHAPE / LAYER bands beside the
//--- Look tab's template rows), its head and tab row gone. The section half of that
//--- is the incomplete delete in `DrawStripGearSectionsPaint` — fixed there. The
//--- half no painter can answer is the OTHER writer of these names: the terminal's
//--- object list outlives an instance whose teardown never ran (a crash, a chart
//--- closed under it), and `DrawStripSkinBmp`/`DrawStripBtnZ`/`DrawStripFaceZ` all
//--- decide "create or rewrite?" from `ObjectFind(0, nm) < 0` alone. A name that is
//--- already there IS reused — with whatever TYPE the older build created it, and
//--- MT4 draws a button's text onto a bitmap label by writing properties nobody
//--- reads: an object that exists, answers ObjectFind, and paints NOTHING. There is
//--- no reader of "is this mine?" that a fresh instance can trust, so the ONE that
//--- it can prove is the family prefix: every `PnlDrawS_*` object is this module's
//--- (the plate, the quick row, the popover, the board, the settings panel) and a
//--- fresh instance has opened NONE of them. The contract's own line decides it —
//--- «every created name is deleted by the same surface's destroy» — and the destroy
//--- an attach can prove is the one at attach.
//--- COST: one prefix scan per ATTACH (never per frame, never per tick). One call,
//--- from the entry's OnInit beside the teardown's own `DrawStripClose()`.
void DrawStripSweepStale()
{
   ObjectsDeleteAll(0, "PnlDrawS_", -1, -1);
}

//--- P-DRAW-87 (2026-09-29) — NAME THE OBJECT, DON'T GUESS IT. The tab row's bed
//--- showed MT4's default blue face on a green build whose every painted colour
//--- is dark by construction (track #1C222C, plate <= 28,34,44, no blue in the
//--- palette, no blue BMP). A colour that cannot come out of this file's pipeline
//--- is either a foreign object or a rendering the code does not own — and which
//--- of the two decides the fix. So on every panel OPEN (user action: rare,
//--- bounded, never on paint) this walks the chart ONCE and prints every object
//--- whose box touches the tab band, with its type and its stored BGCOLOR. The
//--- next screenshot of a blue bar arrives WITH its name attached.
void DrawStripGearTabCensus()
{
   if(s_dsGear == 0 || s_dsGearW0 <= 0) return;
   int bx0 = s_dsGEX, bx1 = s_dsGEX + s_dsGearW0;
   int by0 = s_dsGEY + s_dsGearTabsY, by1 = by0 + DSTRIP_GEAR_ROW_H;
   int n = ObjectsTotal(0, -1);
   for(int oi = 0; oi < n; oi++)
   {
      string on = ObjectName(0, oi, -1);
      if(on == "") continue;
      int oty = (int)ObjectGetInteger(0, on, OBJPROP_TYPE);
      int ox = (int)ObjectGetInteger(0, on, OBJPROP_XDISTANCE);
      int oy = (int)ObjectGetInteger(0, on, OBJPROP_YDISTANCE);
      int ow = 0, oh = 0;
      if(oty == OBJ_BUTTON || oty == OBJ_RECTANGLE_LABEL || oty == OBJ_EDIT)
      {
         ow = (int)ObjectGetInteger(0, on, OBJPROP_XSIZE);
         oh = (int)ObjectGetInteger(0, on, OBJPROP_YSIZE);
      }
      else if(oty == OBJ_BITMAP_LABEL)
      {
         string bf = ObjectGetString(0, on, OBJPROP_BMPFILE, 0);
         ow = DrawStripResW(bf); oh = DrawStripResH(bf);
      }
      else continue;   // lines, arrows and texts are points, not the bar
      if(ox + ow < bx0 || ox > bx1 || oy + oh < by0 || oy > by1) continue;
      color bg = (color)ObjectGetInteger(0, on, OBJPROP_BGCOLOR);
      int zz = (int)ObjectGetInteger(0, on, OBJPROP_ZORDER);
      //--- P-DRAW-89: the TRACK's tone, printed. It is the one surface on the tab
      //--- band whose colour is COMPUTED rather than a constant, so it is the one
      //--- that can disagree with the four tabs beside it (measured: they read
      //--- 2892317 and it read -16924895 = 0xFEFDBF21). Reading the value back out
      //--- of the object is the fact; recomputing it here would be the guess.
      int tone = -1;
      if(on == DrawStripGearTrackName())
      {
         color ct = StrapCellTone(s_dsGearTabsY, DSTRIP_BODY_TOP, DSTRIP_GEAR_GRID_TOP, s_dsGearH);
         tone = (int)ct;
      }
      Print("[drawstrip] TABCENSUS obj=", on, " type=", oty,
            " xywh=", ox, ",", oy, ",", ow, ",", oh,
            " bgcolor=", (int)bg, " tone=", tone, " z=", zz);
   }
}

void DrawStripGearClose()
{
   DrawStripColorHoverClear();
   if(s_dsGear == 0 && s_dsGRN <= 0 && s_dsGGN <= 0 && s_dsGearHeadY < 0) return;
   DrawStripGearObjectsPurge();
   s_dsGear = 0; s_dsGRN = 0; s_dsGGN = 0;
   s_dsGearHeadY = -1; s_dsGearSecN = 0;
   s_dsGearPressSpent = false;   // P-DRAW-84: the purge is where a panel's press ends
   s_dsGearPlaced = false; s_dsGearPlacedObj = "";   // P-DRAW-88: next open scores anew
   s_dsTplNameArmed = false;
}

void DrawStripClose()
{
   DrawStripColorHoverClear();
   for(int i = 0; i < DSTRIP_MAX_SLOTS; i++)

   {        ObjectDelete(0, DrawStripObjName(i));
        ObjectDelete(0, DrawStripIconName(i));
        ObjectDelete(0, DrawStripIconName(i) + "C");
        ObjectDelete(0, DrawStripIconName(i) + "S");    // P-DRAW-64a: the colour seat's centre
        ObjectDelete(0, DrawStripIconName(i) + "C2");   // ...and its swatch skin
   }
   ObjectDelete(0, DrawStripGripName());
   ObjectDelete(0, DrawStripGripIconName());
   ObjectDelete(0, DrawStripGripIconName() + "C");
   ObjectDelete(0, DrawStripBadgeName());
   for(int g = 0; g < 2; g++) ObjectDelete(0, DrawStripSepName(g));   // P-DRAW-66
   for(int a = 0; a < DSTRIP_ACT_N; a++)
   {
      ObjectDelete(0, DrawStripActName(a));
      ObjectDelete(0, DrawStripActIconName(a));
      ObjectDelete(0, DrawStripActIconName(a) + "C");
   }
   for(int r = 0; r < DSTRIP_PICK_MAX; r++)
   {
      ObjectDelete(0, DrawStripPickName(r));
      ObjectDelete(0, DrawStripPickIconName(r));
      ObjectDelete(0, DrawStripPickLabelName(r));
      ObjectDelete(0, DrawStripPickChipName(r));
      ObjectDelete(0, DrawStripPickRailName(r));
      ObjectDelete(0, DrawStripPickGlassName(r));   // P-DRAW-33: the glass sheen
   }
   DrawStripGearClose();
   ObjectDelete(0, DrawStripBgName());
   DrawStripSkinPurge();   // P-DRAW-29: the skin family dies with the strip
   s_dsOpen = false;
   s_dsObj = "";
   s_dsKind = DK_NONE;
   s_dsN = 0;
   DrawStripPublishRect();   // P-DRAW-31: a closed strip occupies no pixels
    s_dsPicker = DSTRIP_PICK_NONE;   // the popover dies with the strip
    s_dsPN = 0;                      // (the recent colours survive: they are the trader's)
    s_dsPHexY = -1;
    s_dsPHeadY = -1;
    s_dsPOpY = -1;
    s_dsOpGrab = false;
    s_dsHexFocus = false;
    DrawStripPopChromePrune();   // TV parity board: its chrome dies with the strip
   //--- P-DRAW-32: the panel's placement belongs to THIS strip session — a fresh
   //--- open lands the panel beside the plate it serves, never where the last
   //--- strip's hand left it (the free space around a new drawing is new space).
   s_dsGearManual = false;
   s_dsPinned = false;
   DrawStripGripRelease();   // P-UI-113d: a close never leaves the view locked
   DrawStripOpenerDisarm();  // P-UI-113c: nor the opener guard armed
   DrawStripHoldSelectionDisarm();  // P-UI-113g: no close outlives a selection repair
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
//--- the modifier form (bitmap ON/OFF states share one face here).
bool DrawStripSetStr2(const string nm, const int prop, const int mod, const string v)
{
   if(ObjectGetString(0, nm, prop, mod) == v) return false;
   ObjectSetString(0, nm, prop, mod, v);
   return true;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-13 — THREE PAINTERS, EVERY SURFACE. Buttons stay the controls (a
// button stays under its skin, Z_PANEL_BASE/Z_PANEL_SKIN parity); bitmaps are
// faces; labels are left-aligned ink. All guarded, all answering dirty.
// ══════════════════════════════════════════════════════════════════════════
//--- P-DRAW-48 (2026-09-26) — THE PLATE'S OWN BODY RIDES THE PLATE'S Z.
//--- The skin's mid band is a filled button the size of the whole plate and it was
//--- born at Z_STRIP_ICON — the CELLS' z. Equal z is settled by the creation order,
//--- so any repaint that re-created the mid band put it over the board's 64 cells,
//--- its RECENT band and its HEX field (the reported empty board). At Z_STRIP the
//--- plate can never be drawn over its own contents, whatever the order did.
bool DrawStripBtnZ(const string nm, const int x, const int y, const int w, const int h,
                   const color face, const color ink, const color rim,
                   const string txt, const string tip, const int z)
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
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, z);
      // P-UI-34 (2026-09-25): STATE must be false on birth. MT4 on Windows 11
      // flips a button to its OS "pressed" skin (white/grey) whenever STATE is
      // left at default — the panels' own PnlSetButton does the same init.
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      dirty = true;
   }
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);
   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);
   dirty |= DrawStripSetInt(nm, OBJPROP_COLOR, ink);
   dirty |= DrawStripSetInt(nm, OBJPROP_BORDER_COLOR, rim);
   // P-DRAW-48: the z is re-asserted every paint — an object born before this law
   // carries the old one, and a write of the value already there is free.
   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);
   // P-UI-34: re-assert STATE=false every paint so a click that toggled the
   // button's own state (MT4 toggles STATE on click internally) cannot leave
   // the face white for the next frame.
   dirty |= DrawStripSetInt(nm, OBJPROP_STATE, false);
   dirty |= DrawStripSetStr(nm, OBJPROP_TEXT, txt);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
//--- the ordinary cell: the icon layer, above the plate it sits on.
bool DrawStripBtn(const string nm, const int x, const int y, const int w, const int h,
                  const color face, const color ink, const color rim,
                  const string txt, const string tip)
{
   return DrawStripBtnZ(nm, x, y, w, h, face, ink, rim, txt, tip, Z_STRIP_ICON);
}
//--- the icon face, centred in its cell (MT4 paints at native size from the
//--- label's own corner). res == "" deletes the face. Whichever object the
//--- terminal's hover lands on (button or face) carries the same tooltip.
bool DrawStripFaceZ(const string nm, const int x, const int y, const int w, const int h,
                    const string res, const string tip, const int z)
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
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, z);
   }
   bool dirty = false;
   int pw = DrawStripResW(res), ph = DrawStripResH(res);
   dirty |= DrawStripSetStr(nm, OBJPROP_BMPFILE, res);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x + (w - pw) / 2);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y + (h - ph) / 2);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
bool DrawStripFace(const string nm, const int x, const int y, const int w, const int h,
                   const string res, const string tip)
{
   return DrawStripFaceZ(nm, x, y, w, h, res, tip, Z_STRIP_OVER);
}
//--- P-DRAW-66 (2026-09-27) — THE ONE INK BASELINE. User report: «فونت پدینگ»
//--- with a crop of the badge sitting on the row's top edge. The retired writer
//--- added a bare `y + 5` — one constant for every point size and every DPI, and
//--- right only at 192. Its measured errors at 96 DPI: the quick row's badge 5px
//--- high, the foot buttons 8px, the version chip 7px, the board header 4px low.
//--- Three owners now, and a caller names its BAND, never an ink offset:
//---   StrapInkY  — one line centred in a band
//---   StrapInkY2 — a two-line stack centred as a block (returns line 0's top)
//---   DrawStripLblAt — the raw writer, for a y that is already resolved
int StrapInkY(const int bandTop, const int bandH, const int pt)
{
   int y = bandTop + (bandH - PnlLineH(pt)) / 2;
   return (y < bandTop) ? bandTop : y;
}
int StrapInkY2(const int bandTop, const int bandH, const int ptA, const int ptB)
{
   int h = PnlLineH(ptA) + DSTRIP_INK_GAP + PnlLineH(ptB);
   int y = bandTop + (bandH - h) / 2;
   return (y < bandTop) ? bandTop : y;
}
//--- left-aligned ink for list rows (buttons centre their text; rows read left).
//--- `inkTop` IS the ink's top; a caller with a band asks DrawStripLblIn instead.
bool DrawStripLblAt(const string nm, const int x, const int inkTop, const string txt,
                    const color ink, const string tip, const int pt, const bool bold)
{
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_OVER);
   }
   bool dirty = false;
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, inkTop);
   dirty |= DrawStripSetInt(nm, OBJPROP_COLOR, ink);
   dirty |= DrawStripSetInt(nm, OBJPROP_FONTSIZE, PnlPt(pt));
   dirty |= DrawStripSetStr(nm, OBJPROP_FONT, BioChromeFont(bold));
   dirty |= DrawStripSetStr(nm, OBJPROP_TEXT, txt);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
//--- the everyday face: a line centred in the band it belongs to.
bool DrawStripLblIn(const string nm, const int x, const int bandTop, const int bandH,
                    const string txt, const color ink, const string tip,
                    const int pt, const bool bold)
{
   return DrawStripLblAt(nm, x, StrapInkY(bandTop, bandH, pt), txt, ink, tip, pt, bold);
}
bool DrawStripRect(const string nm, const int x, const int y, const int w, const int h,
                   const color face, const int z)
{
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, face);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, z);
   }
   bool dirty = false;
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);
   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);
   return dirty;
}
//--- "#RRGGBB" of a colour and back moved DOWN to DrawToolbar.mqh (P-DRAW-48):
//--- the description tags the slot owner writes are the same question, so one
//--- owner answers both (an A-12 move — not one call site changed).

//--- P-DRAW-13: gear list rows — one owner for text/face/tip/state, read by
//--- layout (nothing: rows are full-width), paint and router alike.
string DrawStripGearRowText(const int r)
{
   if(r < 0 || r >= s_dsGRN) return "";
   int kind = s_dsGRKind[r], arg = s_dsGRArg[r];
   if(kind == 1) return DrawStripSwitchName(s_dsObj, arg);
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
      if(arg == DRAW_SLOT_COLOR) return "::Files\\Icons\\gl_droplet_m.bmp";
      return DrawStripIconRes(arg, s_dsObj);
   }
   if(kind == 2 || kind == 7) return "::Files\\Icons\\gl_template_m.bmp";
   if(kind == 3) return "::Files\\Icons\\gl_plus_m.bmp";
   if(kind == 4) return "::Files\\Icons\\bk_levels.bmp";
   if(kind == 6)
   {
      if(arg == DRAW_SLOT_MORE) return "::Files\\Icons\\bk_levels.bmp";
      if(arg == DRAW_SLOT_COLOR) return "::Files\\Icons\\gl_droplet_m.bmp";
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
   if(kind == 2)
      return "Template: " + DrawPresetName(s_dsKind, arg) +
             (DrawPresetIsBuiltin(arg) ? " (built-in)" : " (mine)") +
             " — click to apply" + scope +
             (DrawPresetIsBuiltin(arg) ? "" : " — Shift+click deletes it");
   if(kind == 3) return "Save this look as one of MY templates";
   if(kind == 4)
   {
      double v = DrawStripGearLevelAt(arg);
      if(!MathIsValidNumber(v)) return "";
      bool on = (DrawStripLevelFind(s_dsObj, v) >= 0);
      return DrawStripLevelName(v) + (on ? " is on — click to remove" : " — click to add") +
             " (the held drawing; stays open for the next one)";
   }
   if(kind == 5)
   {
      if(arg == 0) return "Every common level on (the held drawing)";
      if(arg == 1) return "Empty the level set (the held drawing)";
      return "Show every slot of this tool again";
   }
   if(kind == 6) return "Show this slot in the quick row — click to hide / show";
   if(kind == 7) return "Learn the look on the chart as this tool's default (next drawing wears it)";
   if(kind == 8)
      return "Arrow mark: glyph " + IntegerToString(DrawStripGlyphAt(arg % 256)) + " — click to apply" + scope;
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
//--- P-DRAW-66: a face of the layout's own seat array — the command group's x is
//--- computed ONCE (in DrawStripLayout) and every reader asks the same table.
int DrawStripActX(const int a)
{
   if(a < 0 || a >= DSTRIP_ACT_N) return DSTRIP_PAD;
   return s_dsActX[a];
}
string DrawStripSepName(const int g) { return "PnlDrawS_SEP" + IntegerToString(g); }

//--- gear edit row: created with its seed, never re-seeded after (a repaint
//--- rewriting the TEXT would fight the user's typing mid-word).
//--- P-DRAW-32: `y` is the PANEL's own row top — the plate's origin is added
//--- exactly once, HERE, so the two surfaces' coordinate spaces stay apart.
bool DrawStripEdit(const int e, const int x, const int y, const int w, const string seed, const string tip)
{
   string nm = DrawStripEditName(e);
   bool dirty = false;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_EDIT, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, PnlPt(8));
      //--- P-DRAW-67: the cards' field font. Without this the gear's hex fields wore
      //--- MT4's own default face while the cards and the strip's own board wore
      //--- Consolas — the "same field, two fonts" half of the report.
      ObjectSetString(0, nm, OBJPROP_FONT, BIO_FONT_MONO);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, DSTRIP_CLR_LABEL);
       ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, DSTRIP_CLR_FIELD);
       ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, DSTRIP_CLR_FIELD_BD);
       ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
       ObjectSetInteger(0, nm, OBJPROP_ALIGN, ALIGN_LEFT);
       ObjectSetInteger(0, nm, OBJPROP_READONLY, false);

      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_ICON);
      ObjectSetString(0, nm, OBJPROP_TEXT, seed);
      dirty = true;
   }
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, s_dsGEY + y + (DSTRIP_GEAR_ROW_H - DSTRIP_GEAR_EDIT_H) / 2);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, DSTRIP_GEAR_EDIT_H);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   return dirty;
}
//--- TV parity board: the HEX field. It is NOT a gear edit (`DrawStripEdit` adds
//--- the settings panel's own origin), so it has its own owner and its own name.
//--- P-DRAW-48: the seed is the LIVE colour now — the field used to be seeded once
//--- and a grid pick left the old hex on screen («hex ناقص پیاده سازی شده»);
//--- `s_dsHexFocus` is the one guard: while the user is typing, nothing writes.
bool DrawStripPopHex(const int x, const int y, const int w, const string seed)
{
   string nm = DrawStripPHexEdName();
   bool dirty = false;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_EDIT, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, PnlPt(8));
      ObjectSetString(0, nm, OBJPROP_FONT, BIO_FONT_MONO);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, DSTRIP_CLR_LABEL);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, DSTRIP_CLR_FIELD);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_COLOR, DSTRIP_CLR_FIELD_BD);
      ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, nm, OBJPROP_ALIGN, ALIGN_LEFT);
      ObjectSetInteger(0, nm, OBJPROP_READONLY, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_ICON);
      ObjectSetString(0, nm, OBJPROP_TEXT,
                      DrawStripColorHex((color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR)));
      dirty = true;
   }
   //--- the live seed: a guarded write, so a repaint that changed nothing writes
   //--- nothing — and the field follows a colour picked on the grid or typed
   //--- elsewhere. An empty seed (the field holds the focus) never writes.
   if(seed != "" && ObjectGetString(0, nm, OBJPROP_TEXT) != seed)
      dirty |= DrawStripSetStr(nm, OBJPROP_TEXT, seed);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, DSTRIP_POP_EDIT_H);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP,
                            "Type #RRGGBB, Enter applies it" + DrawStripTipScope());
   return dirty;
}
string DrawStripFootText(const int f)
{
   return (f == 0) ? "All" : "Copy";
}
string DrawStripFootTip(const int f)
{
   if(f == 0) return "This look on EVERY " + DrawKindName(s_dsKind) + " (MT4's dialog is one at a time)";
   return "Copy this drawing beside itself (selects the copy)";
}
//--- the gear panel's own paint: tabs, grids, rows, edits, foot.
string DrawStripGearHeadTitle()
{
   return DrawKindName(s_dsKind) + " Settings";
}
//--- P-DRAW-66: the subtitle says what the title does not — what this panel serves
//--- and how many of them the strip's group holds ("DRAWING TOOL . LIVE" was the
//--- title's own word twice).
string DrawStripGearHeadSub()
{
   int n = DrawSelCount();
   if(n < 1) n = 1;
   return "SERVING " + IntegerToString(n) + (n == 1 ? " DRAWING" : " DRAWINGS");
}
string DrawStripGearMarkRes()
{
   if(s_dsKind == DK_RECT || s_dsKind == DK_TRIANGLE || s_dsKind == DK_ELLIPSE)
      return "::Files\\Icons\\gl_box_i_gold.bmp";
   if(s_dsKind == DK_FIBO || s_dsKind == DK_FIBOFAN || s_dsKind == DK_FIBOCHAN ||
      s_dsKind == DK_EXPANSION || s_dsKind == DK_GANN)
      return "::Files\\Icons\\gl_sigma_i_gold.bmp";
   if(s_dsKind == DK_ARROW) return "::Files\\Icons\\gl_target_i_gold.bmp";
   if(s_dsKind == DK_TEXT) return "::Files\\Icons\\gl_type_i_gold.bmp";
   return "::Files\\Icons\\gl_line_i_gold.bmp";
}
bool DrawStripGearHeadPaint()
{
   bool dirty = false;
   int gx = DrawStripGearX();
   int hy = s_dsGEY + s_dsGearHeadY;
   // P-DRAW-31: the header IS a handle, and it says so (the whole top row of the
   // plate carries it too — see DrawStripGripWhich).
   string tip = DrawKindName(s_dsKind) + " settings — drag this bar to move the panel";
    // P-DRAW-36 (2026-09-25): the head spans the PLATE's own width, not the content
    // width — the old `s_dsGearW` left a bare 32px strip of plate on the right while
    // the left sat at 16px, so the header read as narrower than the card it belongs
    // to (the cards' own header spans the whole card).
     //--- P-DRAW-73: through a LOCAL. This painter used to write `s_dsGearW =
     //--- s_dsGearW0`, so a layout variable carried the plate's width from the first
     //--- paint on — two meanings in one name, and the one reader (`DrawStripGearCW`,
     //--- no callers, retired below) answered 312 where the layout means 280.
     int pw = s_dsGearW0;
     bool gearWide = (pw > DSTRIP_GEAR_W);
     string tbRes  = gearWide ? "::Files\\Icons\\pnl_topbarW_gold.bmp" : "::Files\\Icons\\pnl_topbar_gold.bmp";
     string hrRes  = gearWide ? "::Files\\Icons\\pnl_hairW_gold.bmp"   : "::Files\\Icons\\pnl_hair_gold.bmp";
     //--- P-DRAW-74: a BAKED piece is asked for at its OWN width. Both bakes are
     //--- 312/624 (measured on the files) and both were asked for at the plate's
     //--- 344/656, so MT4 — which crops a label and never scales it — drew each one
     //--- 32px SHORT: the card's top edge and the seam closing the head stopped
     //--- before the plate's right edge, beside a body seam that runs full width.
      int bw = pw;   // P-DRAW-75: the plate IS the card, so the bake's 312/624 is the plate's width
      //--- P-DRAW-80: the head rides the CARDS' z ladder (BiotakPanels 6727/6729),
      //--- not the strip's. `Z_STRIP_ICON` is 1441, BELOW the whole panel range
      //--- (1480+), so the card body painted over its own top bar and hair.
      dirty |= DrawStripFaceZ(DrawStripGearHeadName("TB"), gx, hy, bw, DSTRIP_GEAR_TB_H,
                              tbRes, tip, Z_PANEL_TOPBAR);
      //--- P-DRAW-73: the hair CLOSES the head, so it ends ON the head's bottom edge.
      //--- It stood at +53 with height 5 inside a 56px head — 2px into the tab row,
      //--- while P-DRAW-69's seam rides that same edge at exactly HEAD_H.
      dirty |= DrawStripFaceZ(DrawStripGearHeadName("HR"), gx,
                              hy + DSTRIP_GEAR_HEAD_H - DSTRIP_GEAR_HR_H, bw, DSTRIP_GEAR_HR_H,
                              hrRes, tip, Z_PANEL_HAIR);
     //--- P-DRAW-83: THE SECOND WRITE IS DELETED. This pair was one intent pasted
     //--- twice — the same object, the same rect, the same tooltip — and only the
     //--- rung differed: `Z_PANEL_HAIR` 1495 first, `Z_STRIP_ICON` 1441 second. The
     //--- second one WON (a later write is the value the terminal holds), so the hair
     //--- the P-DRAW-73 note above places on the head's bottom edge was re-sat on the
     //--- strip's icon rung, under the top bar it closes and under the section rules.
     //--- One owner, one write: the rung above is the one the note describes.
   //--- P-DRAW-80: THE HEADER, ON THE CARDS' OWN SEATS (BiotakPanels 6734-6742).
   //--- mark canvas 44 at `+16-7, +13-7`; glyph 15 at `+16+7, +13+7`; text
   //--- column at `+16+30+10`. This panel drew the mark in a 30px box at +16
   //--- (7px right and 7px low of the cards' canvas) and the glyph by hand at
   //--- +23/+20 — so the disc floated off its own glyph and the whole head sat
   //--- 7px off the card it belongs to. LITERALS, not PNL_*: BiotakPanels is
   //--- included AFTER this file.
   dirty |= DrawStripFace(DrawStripGearHeadName("MK"), gx + 9, hy + 6, 44, 44,
                           "::Files\\Icons\\pnl_mark_gold.bmp", tip);
   dirty |= DrawStripFace(DrawStripGearHeadName("MG"), gx + 23, hy + 20, 15, 15,
                           DrawStripGearMarkRes(), tip);
   int htx = gx + 56;   // PNL_PAD_X + PNL_MARK_VIS + 10
   // P-DRAW-36: the version chip and the close button sit at the PLATE's right
   // inset (s_dsGearW0 - PAD), so they read as flush with the content's own
   // right edge instead of 32px short of it.
    //--- P-DRAW-71: the cards' own `.ver` — 16px high at +20, as wide as its own
    //--- text (10 + the advance at pt 6), a 6px gap before the X (the fixed 46x22
    //--- gold chip stood 30px wider than any number it holds).
    //--- P-DRAW-73: it carries a VERSION. It wore `(int)s_dsKind`, so a rectangle
    //--- read "11" — a number the user cannot act on or quote (J-02). The build tag
    //--- is the same string the log prints as [BUILD]: screen and log, one voice.
    string ver = TH3_BUILD_TAG;
   int vw = 10 + PnlTextW(ver, 6);
   //--- P-DRAW-80: the right column, on the cards' own chain (BiotakPanels
   //--- 6749-6755/6857): ver left = cardW-16-26-6-vw, and the close sits
   //--- 6px right of it. This panel put the chip at `-16-26-6-vw` of the WIDTH
   //--- but measured from `s_dsGearW0` while the head spans the same value —
   //--- consistent, so the 6px gap is kept; what moved is the chip's own y.
   int verX = gx + s_dsGearW0 - 16 - 26 - 6 - vw;
   if(verX < htx + 10) verX = htx + 10;                        // a narrow panel keeps the old seat
   //--- P-DRAW-80: the two lines are NOT centred as a block. The cards place
   //--- title at `+12` and subtitle at `+35` (BiotakPanels 6762/6834) — the
   //--- vertical centring this panel inherited from the strip left both
   //--- floating and the pair read lower than every card's. Same two numbers.
   dirty |= DrawStripLblAt(DrawStripGearHeadName("TT"), htx, hy + 12,
                           PnlFit(DrawStripGearHeadTitle(), 9, verX - htx - 10),
                           DSTRIP_CLR_VALUE, tip, 9, true);
   dirty |= DrawStripLblAt(DrawStripGearHeadName("ST"), htx, hy + 35,
                           PnlFit(DrawStripGearHeadSub(), 6, verX - htx - 10),
                           DSTRIP_CLR_TITLE, tip, 6, true);   // = BIO_CLR_MUTED
   //--- P-DRAW-71: ONE object, the cards' own `.ver` chip — a 16px face in the
   //--- accent soft/border pair with the number centred in it (was a 50x26 BMP plus
   //--- a label, and the pair could drift apart).
   dirty |= DrawStripBtn(DrawStripGearHeadName("VB"), verX, hy + 20, vw, 16,
                         DSTRIP_CLR_VER_BG, DSTRIP_CLR_ACCENT, DSTRIP_CLR_VER_BD, ver, tip);
   dirty |= DrawStripSetInt(DrawStripGearHeadName("VB"), OBJPROP_FONTSIZE, PnlPt(6));
   if(ObjectFind(0, DrawStripGearHeadName("VT")) >= 0)      // the retired label
   { ObjectDelete(0, DrawStripGearHeadName("VT")); dirty = true; }
   int closeX = gx + s_dsGearW0 - DSTRIP_GEAR_PAD - 26;
   dirty |= DrawStripBtn(DrawStripGearCloseName(), closeX, hy + 17, 26, 26,
                         DSTRIP_CLR_FOOT, DSTRIP_CLR_FOOT, DSTRIP_CLR_LINE, "", "Close settings");
   dirty |= DrawStripFace(DrawStripGearCloseSkinName(), closeX, hy + 17, 26, 26,
                          "::Files\\Icons\\pnl_xbtn.bmp", "Close settings");
   dirty |= DrawStripFace(DrawStripGearCloseIconName(), closeX, hy + 17, 26, 26,
                          "::Files\\Icons\\gl_x_gold.bmp", "Close settings");
   return dirty;
}
//--- P-DRAW-71 — A BAND'S OWN MEMBER COUNT, the cards' `.cnt`. One owner walks
//--- the tab's blocks: a ROW, or a chip BLOCK (one setting, whatever its options),
//--- whose y sits inside this band's range and in the band's own column counts
//--- once. The wide pass translates a whole block into its column, so the column
//--- filter is what keeps the count honest on a two-column panel.
int DrawStripGearSectionCount(const int i)
{
   if(i < 0 || i >= s_dsGearSecN) return 0;
   int col = s_dsGearSecCol[i], y0 = s_dsGearSecY[i], y1 = 0x7FFFFFFF;
   for(int j = i + 1; j < s_dsGearSecN; j++)
      if(s_dsGearSecCol[j] == col && s_dsGearSecY[j] > y0 && s_dsGearSecY[j] < y1)
         y1 = s_dsGearSecY[j];
   int n = 0;
   for(int r = 0; r < s_dsGRN; r++)
      if(s_dsGRCol[r] == col && s_dsGRY[r] >= y0 && s_dsGRY[r] < y1) n++;
   for(int g = 0; g < s_dsGGN; g++)
   {
      if(s_dsGGY[g] < y0 || s_dsGGY[g] >= y1) continue;
      if(((s_dsGGX[g] >= DSTRIP_GEAR_COL) ? 1 : 0) != col) continue;
      bool dup = false;
      for(int h = 0; h < g; h++)
         if(s_dsGGY[h] == s_dsGGY[g] &&
            (((s_dsGGX[h] >= DSTRIP_GEAR_COL) ? 1 : 0) == col)) { dup = true; break; }
      if(!dup) n++;
   }
   return n;
}
bool DrawStripGearSectionsPaint(const int x, const int w)
{
   bool dirty = false;
   for(int i = 0; i < DSTRIP_GEAR_SECTION_MAX; i++)
   {
      string sn = DrawStripGearSectionName(i), sl = DrawStripGearSectionLineName(i);
      if(i >= s_dsGearSecN)
      {
         //--- P-DRAW-84 (2026-09-29) — A RETIRED BAND TAKES ITS WHOLE FAMILY WITH IT.
         //--- This branch deleted two names and only ONE of them is ever painted:
         //--- `sn` is a frame no painter creates any more (the band is the dot `snD`,
         //--- the label `snT`, the rule `sl` and — when it owns its row — the count
         //--- pill `snC` and its number `snN`). So a tab switch that SHRINKS the band
         //--- list (Style's four bands → Look's one) left the previous tab's captions,
         //--- dots and pills painted on the new tab's plate — the reported «جابجا
         //--- بین تب‌ها می‌شم این‌طوری می‌شه»: LINE STYLE / SHAPE / LAYER floating over
         //--- the template rows, two tabs in one card. Deleting a name that cannot
         //--- exist is not a delete; the family is five names and the rule makes six.
         //--- Bounded: 5 ObjectFind + 1 per retired index, per paint.
         string gone = sn;
         for(int gi = 0; gi < 5; gi++)
         {
            if(gi == 1) gone = sn + "D";
            else if(gi == 2) gone = sn + "T";
            else if(gi == 3) gone = sn + "C";
            else if(gi == 4) gone = sn + "N";
            if(ObjectFind(0, gone) >= 0) { ObjectDelete(0, gone); dirty = true; }
         }
         if(ObjectFind(0, sl) >= 0) { ObjectDelete(0, sl); dirty = true; }
         continue;
      }
      int y = s_dsGEY + s_dsGearSecY[i];
      // P-DRAW-30: the band belongs to its block's column (the hair stops at that
      // column's own right edge, never across the gutter).
      int x0 = x + s_dsGearSecCol[i] * DSTRIP_GEAR_COL;
      //--- P-DRAW-80: `x` is the CONTENT box (card + 16), the cards' captions
      //--- measure from the CARD edge — so every seat below is `+16 - 16` from
      //--- here, i.e. exactly the card's own arithmetic restated on this origin.
      //--- The card's own numbers: dot `+16-4` at `+18-4`, label `+16+14` at
      //--- `+14`, rule at `+21` 1px, count chip `cardW-58` at `+11` 24x20, the
      //--- number centred in it, rule's right end `cardW-68`.
      const int SEC_DX = DSTRIP_GEAR_PAD;   // 16 = PNL_PAD_X
      string txt = s_dsGearSecText[i];
      //--- P-DRAW-66: a caption that shares its row with a control is a ROW LABEL,
      //--- not a section band — pt 9 in the label ink, which is exactly the cards'
      //--- own row label (PNL_PT_LBL 9 / PNL_CLR_LABEL). A caption that owns its band
      //--- keeps the 7pt muted band treatment.
      bool rowLbl = (s_dsGearSecCX[i] >= 0);
      //--- P-DRAW-75 (2026-09-28): THE DOT IS THE BAND'S MARK, SO A ROW LABEL WEARS
      //--- NONE — the cards put `pnl_secdot` on `PNL_K_SEC` alone (BiotakPanels
      //--- 6053) and their row labels are bare ink ("MID ZONES", "SHOW LINES"). Here
      //--- every shared-row caption wore one, so COLOR and FILL each carried a GOLD
      //--- DOT: a second accent meaning nothing, which C-03 bans by name, on a plate
      //--- whose only accent is the active tab and the value itself.
      string dot = sn + "D";
      if(rowLbl) { if(ObjectFind(0, dot) >= 0) { ObjectDelete(0, dot); dirty = true; } }
      //--- P-DRAW-80: the cards' OWN section dot — canvas 14 at `+16-4, +18-4`
      //--- (BiotakPanels 6053-6055), on their z rung.
      else
         dirty |= DrawStripFaceZ(dot, x0 + SEC_DX - 4, y + 14, 14, 14,
                                 "::Files\\Icons\\pnl_secdot_gold.bmp", txt, Z_PANEL_CHIP);
      //--- P-DRAW-73 (2026-09-28): ONE point size for the ink and for the measure.
      //--- The rule below started at `PnlTextW(txt, 7)` while a row label draws at 9,
      //--- so every caption sharing a row had its hair start ~8px early and run
      //--- under the last letters of its own word.
      int lpt = (rowLbl ? DSTRIP_GEAR_LBL_PT : 7);
      //--- P-DRAW-80: the label sits on the card's seat — `+16+14` from the CARD,
      //--- `+14` down, muted at pt 7 for a band (BiotakPanels 6007-6008).
      dirty |= DrawStripLblIn(sn + "T", x0 + DSTRIP_GEAR_CAP_X, y, DSTRIP_GEAR_ROW_H, txt,
                              rowLbl ? DSTRIP_CLR_LABEL : DSTRIP_CLR_TITLE, txt,
                              lpt, true);
      //--- P-DRAW-66: a caption that SHARES its row with a control draws its rule
      //--- only up to that control (`s_dsGearSecCX`), never through it.
      int lx = x0 + DSTRIP_GEAR_CAP_X + PnlTextW(txt, lpt) + DSTRIP_ROW_GAP;
      //--- P-DRAW-71: a BAND (one that owns its row) also carries the cards' own
      //--- `.cnt` pill, and its rule stops 36px short of the column's right edge for
      //--- it (the pill is 24 wide + 12 of air). A caption that SHARES its row with a
      //--- control is a row label — short rule, no pill.
      int cnt = rowLbl ? 0 : DrawStripGearSectionCount(i);
      //--- P-DRAW-80: the rule's right end is the card's own formula — `cardW-16-24-12-16`
      //--- (BiotakPanels 6027) — which is 68px in from the card's right edge.
      int rEnd = (cnt > 0) ? x0 + w - 16 - 16 : x0 + w;
      int lw = (s_dsGearSecCX[i] >= 0) ? MathMin(x0 + s_dsGearSecCX[i], x0 + w) - lx
                                       : rEnd - lx;
      //--- P-DRAW-75: A RULE WITH NO ROOM IS NOT A RULE. With the seat measured, a
      //--- shared-row caption's hair measures zero or less — the label already stands
      //--- B-02's 10 from its own control — and what it used to draw there was the
      //--- 26px stub LEVEL 90 no. 4 names. A band keeps its hair; a hair with no room
      //--- takes its object with it (no. 12).
      if(lw < DSTRIP_ROW_GAP)
      {
         if(ObjectFind(0, sl) >= 0) { ObjectDelete(0, sl); dirty = true; }
      }
      else
         dirty |= DrawStripRect(sl, lx, y + 21, lw, 1, DSTRIP_CLR_LINE, Z_PANEL_BASE);
      string cchip = sn + "C", clbl = sn + "N";
      if(cnt > 0)
      {
         string cs = IntegerToString(cnt);
         //--- P-DRAW-80: the card's own `.cnt` — canvas 24x20 at `cardW-58`,
         //--- `+11` (BiotakPanels 6032-6033), and the number centred in the
         //--- CANVAS's own centre at `+16` (6039-6041). This panel drew the bake
         //--- 24x16 at a centred y and the number off that 16px box, so the pill
         //--- lost its bottom edge to MT4's crop and the digit drifted.
         dirty |= DrawStripFaceZ(cchip, x0 + w - DSTRIP_SEC_CNT_W - 2, y + 11,
                                 DSTRIP_SEC_CNT_W + 4, 20,
                                 "::Files\\Icons\\pnl_cntchip.bmp", txt, Z_PANEL_CHIP);
         dirty |= DrawStripLblAt(clbl, x0 + w - DSTRIP_SEC_CNT_W / 2 - 2 + PnlTextW(cs, lpt) / 2,
                                 y + 16, cs, DSTRIP_CLR_TITLE, txt, lpt, true);
      }
      else
      {
         if(ObjectFind(0, cchip) >= 0) { ObjectDelete(0, cchip); dirty = true; }
         if(ObjectFind(0, clbl) >= 0) { ObjectDelete(0, clbl); dirty = true; }
      }
   }
   return dirty;
}
bool DrawStripGearPaint()
{
   bool dirty = false;
   int gx = DrawStripGearX();
   int cw = DSTRIP_GEAR_W - 2 * DSTRIP_GEAR_PAD;   // ONE column's content width
   //--- P-DRAW-36 (2026-09-25): the tab row spans the PLATE's own width, so a wide
   //--- panel's row is as wide as the card itself and not 32px short of it.
   int gw = s_dsGearW0 - 2 * DSTRIP_GEAR_PAD;      // P-DRAW-30: the row the panel wears
   int px = gx + DSTRIP_GEAR_PAD;
   dirty |= DrawStripGearHeadPaint();
   //--- P-DRAW-67/69: the bed is the HEAD'S OWN CELL (one grid, one tone, no border)
   //--- and the row's dead space — a press on it is the carry, never a tap.
   //--- P-DRAW-71: P-UI-34's segmented pill and its floating 2px bar are retired;
   //--- the row wears the cards' own `.tabs` now.
   color trkTone = StrapCellTone(s_dsGearTabsY, DSTRIP_BODY_TOP, DSTRIP_GEAR_GRID_TOP, s_dsGearH);
    dirty |= DrawStripBtn(DrawStripGearTrackName(), px, s_dsGEY + s_dsGearTabsY, gw, DSTRIP_GEAR_ROW_H,
                          trkTone, trkTone, trkTone, "",
                          "Settings section");
   int nt = s_dsGearTab[0];
   int ty = s_dsGEY + s_dsGearTabsY + (DSTRIP_GEAR_ROW_H - DSTRIP_TAB_H) / 2;
   bool ulDrawn = false;
   for(int t = 0; t < DSTRIP_GEAR_TAB_MAX; t++)
   {
      string tn = DrawStripGearTabName(t);
      if(t >= nt)
      {
         if(ObjectFind(0, tn) >= 0) { ObjectDelete(0, tn); dirty = true; }
         continue;
      }
      int tab = s_dsGearTab[t + 1];
      bool sel = (tab == s_dsGear);
      int tx = gx + s_dsGearTabX[t], tw = s_dsGearTabW[t];
      //--- P-DRAW-71: the cards' own `.tab` — ONE face (BIO_CLR_CARD) in BOTH states
      //--- and NO rim, so the row reads as a line of words, not a row of boxes; the
      //--- state is the ink (TITLE bold / MUTED) plus the accent underline below.
      dirty |= DrawStripBtn(tn, tx, ty, tw, DSTRIP_TAB_H,
                            DSTRIP_CLR_CARD, sel ? DSTRIP_CLR_VALUE : DSTRIP_CLR_TITLE,
                            DSTRIP_CLR_CARD,
                            DrawStripGearTabText(tab),
                            DrawStripGearTabText(tab) + " settings");
      dirty |= DrawStripSetInt(tn, OBJPROP_FONTSIZE, PnlPt(8));
      dirty |= DrawStripSetStr(tn, OBJPROP_FONT, BioChromeFont(sel));
      if(sel && !ulDrawn)
      {
         dirty |= DrawStripRect(DrawStripGearTabLineName(), tx + 7,
                                ty + DSTRIP_TAB_H - 1, tw - 14, DSTRIP_TAB_UL,
                                DSTRIP_CLR_ACCENT, Z_STRIP_ICON);
         ulDrawn = true;
      }
   }
   if(!ulDrawn && ObjectFind(0, DrawStripGearTabLineName()) >= 0)
   { ObjectDelete(0, DrawStripGearTabLineName()); dirty = true; }
   for(int g = 0; g < DSTRIP_GRID_MAX; g++)
   {
      string gn = DrawStripGridName(g), gi = DrawStripGridIconName(g);
      if(g >= s_dsGGN)
      {
         if(ObjectFind(0, gn) >= 0) { ObjectDelete(0, gn); dirty = true; }
         if(ObjectFind(0, gi) >= 0) { ObjectDelete(0, gi); dirty = true; }
         if(ObjectFind(0, DrawStripGridGlassName(g)) >= 0)
         { ObjectDelete(0, DrawStripGridGlassName(g)); dirty = true; }
         continue;
      }
      int cx = gx + s_dsGGX[g];
      int cy = s_dsGEY + s_dsGGY[g] + (DSTRIP_GEAR_ROW_H - s_dsGGH[g]) / 2;
      // P-DRAW-44: the grid carries CHIPS only now (border width, line style, ray);
      // the colour cells were the duplicate of the popover's own grid.
      {
         int slot = s_dsGGSlot[g], arg = s_dsGGArg[g];
         bool cur = DrawStripPickIsCur(s_dsObj, s_dsKind, slot, arg);
         string txt = PnlFit(DrawStripPickText(s_dsKind, slot, arg), 8, s_dsGGW[g] - 8);
         string tip = DrawStripPickTip(s_dsObj, s_dsKind, slot, arg);
         dirty |= DrawStripBtn(gn, cx, cy, s_dsGGW[g], s_dsGGH[g],
                               cur ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_FIELD,
                               cur ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL,
                               cur ? DSTRIP_CLR_ACCENT2 : DSTRIP_CLR_FIELD_BD, txt, tip);
      }
   }
   dirty |= DrawStripGearSectionsPaint(px, cw);
   for(int r = 0; r < DSTRIP_GLIST_MAX; r++)
   {
      string rn = DrawStripRowName(r), ri = DrawStripRowIconName(r), rl = DrawStripRowLabelName(r);
      string rc = DrawStripRowChipName(r), rr = DrawStripRowRailName(r);
      string rs = DrawStripRowStateName(r), rp = DrawStripRowSepName(r);
      if(r >= s_dsGRN)
      {
         if(ObjectFind(0, rn) >= 0) { ObjectDelete(0, rn); dirty = true; }
         if(ObjectFind(0, ri) >= 0) { ObjectDelete(0, ri); dirty = true; }
         if(ObjectFind(0, rl) >= 0) { ObjectDelete(0, rl); dirty = true; }
         if(ObjectFind(0, rc) >= 0) { ObjectDelete(0, rc); dirty = true; }
         if(ObjectFind(0, rr) >= 0) { ObjectDelete(0, rr); dirty = true; }
         if(ObjectFind(0, rs) >= 0) { ObjectDelete(0, rs); dirty = true; }
         if(ObjectFind(0, rp) >= 0) { ObjectDelete(0, rp); dirty = true; }
         continue;
      }
      int py = s_dsGEY + s_dsGRY[r];
      int rx = px + s_dsGRCol[r] * DSTRIP_GEAR_COL;   // P-DRAW-30: this row's column
      bool cur = DrawStripGearRowIsCur(r);
      string res = DrawStripGearRowRes(r);
      string txt = DrawStripGearRowText(r);
      string tip = DrawStripGearRowTip(r);
      color ink = (s_dsGRKind[r] == 6 && !cur) ? DSTRIP_CLR_TITLE : DSTRIP_CLR_LABEL;
      //--- P-DRAW-69: the row's own face is its CELL — one tone, one owner, so it
      //--- cannot sit a unit off the band under it. The hairline above it is the
      //--- cell seam now (edge to edge, the cards' own), so this row's private 1px
      //--- stub is gone: it stopped 32px short of the plate and drew nothing at all
      //--- under a caption band, which is why COLOR/FILL and Interior read as two
      //--- different objects in one card.
      if(ObjectFind(0, rp) >= 0) { ObjectDelete(0, rp); dirty = true; }
      color rowTone = StrapCellTone(s_dsGRY[r], DSTRIP_BODY_TOP, DSTRIP_GEAR_GRID_TOP, s_dsGearH);
      dirty |= DrawStripBtn(rn, rx, py, cw, DSTRIP_GEAR_ROW_H, rowTone, ink, rowTone, "", tip);
      if(res != "")
      {
         //--- P-DRAW-77: THE CARDS' OWN SEATS, MEASURED, NOT DERIVED. The chip is
         //--- `px+PNL_PAD_X, ry+PNL_CHIP_Y` and the label `PnlLabelX()` = PAD_X +
         //--- CHIP_VIS + 8 at `ry+PNL_LBL_Y` (BiotakPanels 6155/6158) — this panel
         //--- sat them on a tighter 12/32 grid of its own, which is the whole of
         //--- "the panel reads as a second grid beside the cards".
         dirty |= DrawStripFace(rc, rx + DSTRIP_GEAR_PAD, py + DSTRIP_CARD_CHIP_Y, 22, 22,
                                cur ? "::Files\\Icons\\pnl_chip_gold.bmp" : "::Files\\Icons\\pnl_chip.bmp", tip);
         dirty |= DrawStripFace(ri, rx + DSTRIP_GEAR_PAD, py + DSTRIP_CARD_CHIP_Y, 22, 22, res, tip);
      }
      int labelX = rx + DSTRIP_GEAR_PAD + (res == "" ? 0 : 22 + 8);
      int k = s_dsGRKind[r];
      bool isSw = (k == 1 || k == 4 || k == 6);
      int stateW = isSw ? 40 : 20;          // PNL_SW_W 40 · the check/nav glyph 20
      //--- P-DRAW-68: the cards' own row label, weight included — `PnlPaintLabel`
      //--- writes Arial Bold at PNL_PT_LBL and this row sat in Arial regular, the
      //--- one font difference between the panel and the card it stands beside.
      dirty |= DrawStripLblIn(rl, labelX, py, DSTRIP_GEAR_ROW_H,
                              PnlFit(txt, 9, cw - (labelX - rx) - stateW - DSTRIP_ROW_GAP),
                              ink, tip, 9, true);
      dirty |= DrawStripFace(rr, rx, py, 2, DSTRIP_GEAR_ROW_H,
                             cur ? "::Files\\Icons\\pnl_rail_gold.bmp" : "", tip);
      string state = "";
      if(isSw)
         state = cur ? "::Files\\Icons\\pnl_sw_on_gold.bmp" : "::Files\\Icons\\pnl_sw_off.bmp";
      else if(cur && (k == 2 || k == 8))
         state = "::Files\\Icons\\gl_check_gold.bmp";
      else if(k == 3 || k == 5 || k == 7)
         state = "::Files\\Icons\\gl_nav_m.bmp";   // the level's own stepper
      //--- P-DRAW-77: the control sits on the cards' own seat — right-aligned
      //--- `px+PNL_SW_X` = contentW-40, at `ry+PNL_SW_Y` = +10, 40x22
      //--- (BiotakPanels 6160). The old `cw-18 / 15` was a narrower pill on a
      //--- different right inset, so the switch column read narrower than the
      //--- cards' beside it.
      dirty |= DrawStripFace(rs, rx + cw - (isSw ? 40 : 18), py + DSTRIP_CARD_CHIP_Y,
                             isSw ? 40 : 15, 22, state, tip);
   }
   for(int e = 0; e < 5; e++)
   {
      string en = DrawStripEditName(e);
      bool want = ((e == 0 && s_dsGear == DSTRIP_GEAR_PAINT) ||
                   (e == 4 && s_dsGear == DSTRIP_GEAR_PAINT &&
                    DrawSlotAvailable(s_dsKind, DRAW_SLOT_FILLCLR)) ||
                   (e == 1 && s_dsGear == DSTRIP_GEAR_LEVELS) ||
                   (e == 2 && s_dsGear == DSTRIP_GEAR_MARK && s_dsKind == DK_TEXT) ||
                   (e == 3 && s_dsGear == DSTRIP_GEAR_TPL && s_dsTplNameArmed));
      if(!want)
      {
         if(ObjectFind(0, en) >= 0) { ObjectDelete(0, en); dirty = true; }
         continue;
      }
      //--- P-DRAW-82: THE FIELD'S WIDTH IS THE CARD'S CONTENT BOX, NOT
      //--- `cw - seat`. `cw` here is `DSTRIP_GEAR_W - 2*PAD` = 280 measured from
      //--- `px` (the card + 16), so `cw - seat` double-counted the 16px pad: the
      //--- field ended 16px PAST the card's right edge on every wide hex row —
      //--- which is the field hanging off the card in the report. The field's own
      //--- right end is `cardRight - PAD`, one pad in, exactly like a card row's
      //--- control (PNL_SW_X = PNL_WEL-2*PNL_PAD_X = 280).
      int ex = px + s_dsGearEditCol[e] * DSTRIP_GEAR_COL + s_dsGearEditX[e];
      int ew = (s_dsGearEditW[e] > 0) ? s_dsGearEditW[e] : cw;
      if(e == 0)
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew,
                                DrawStripColorHex((color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR)),
                                "Custom color as #RRGGBB — Enter applies it");
      else if(e == 1)
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew, "",
                                "Add a level, e.g. 88.6 — Enter adds it (the held drawing)");
      else if(e == 3)
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew, "",
                                "Template name — Enter saves this look under your name");
      else if(e == 4)
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew,
                                DrawStripColorHex(DrawStripColorRead(s_dsObj, DRAW_SLOT_FILLCLR)),
                                "Fill color as #RRGGBB — Enter applies it (the interior)");
      else
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew,
                                ObjectGetString(0, s_dsObj, OBJPROP_TEXT),
                                "Caption — Enter applies it");
   }
    //--- P-DRAW-80: THE FOOT IS THE CARDS' FOOT (BiotakPanels 6486-6507, 6901-6903).
    //--- LEFT-ALIGNED at `+16` and `+10` down, each button a 28px ghost with its
    //--- GLYPH at `bx+12` and its label at `bx+32` — the pair the cards wear. This
    //--- panel centred a bare word with no glyph at all, so its foot read as a row
    //--- of captions under a card that has two buttons with icons.
    int fy0 = s_dsGEY + s_dsGearFootY;
    for(int f = 0; f < DSTRIP_GEAR_FOOT_N; f++)
    {
      string fn = DrawStripFootName(f);
      string label = DrawStripFootText(f);
      //--- P-DRAW-80: the cards' OWN width formula (BiotakPanels 6481-6484) —
      //--- `max(72, 32 + advance + 8)`. This panel used a flat 64, so "All" and
      //--- "Copy" were both 64 while the cards' are 72 or wider: the foot was
      //--- narrower than the card it belongs to even with the same left seat.
      int bw = MathMax(72, 32 + PnlTextW(label, 8) + 8);
      int fx = px + f * (bw + DSTRIP_GEAR_FOOT_GAP);
      int fy = fy0 + 10;
      string tip = DrawStripFootTip(f);
      color ink = DSTRIP_CLR_TITLE;                       // = BIO_CLR_MUTED
      dirty |= DrawStripBtn(fn, fx, fy, bw, 28, DSTRIP_CLR_FOOT,
                            DSTRIP_CLR_FOOT, DSTRIP_CLR_FOOT, "", tip);
      dirty |= DrawStripFace(DrawStripFootSkinName(f), fx - 8, fy - 8,
                             bw + 16, 44,
                             "::Files\\Icons\\pnl_btn_ghost.bmp", tip);
      //--- the card's own glyph seat, 15x15 on Z_PANEL_INK; one glyph per action
      //--- (the cards give Reset a reset ring and Done a check, PnlFooterBtn's
      //--- `ico` argument, BiotakPanels 6901-6902).
      dirty |= DrawStripFace(DrawStripFootGlyphName(f), fx + 12, fy + 6, 15, 15,
                             (f == 0) ? "::Files\\Icons\\gl_reset_m.bmp"
                                      : "::Files\\Icons\\gl_check_gold.bmp", tip);
      dirty |= DrawStripLblIn(DrawStripFootLabelName(f), fx + 32, fy, 28,
                              PnlFit(label, 8, bw - 32 - 8),
                              ink, tip, 8, true);
   }
   //--- P-DRAW-78: the retired third button (`Del`) dies here, not in the purge
   //--- above — this loop is the only other writer of the GF family, and without
   //--- a stale branch a chart that wore the 3-button foot keeps a dead Del.
   //--- Bounded: exactly the one retired seat.
   for(int fd = DSTRIP_GEAR_FOOT_N; fd < 3; fd++)
   {
      //--- P-DRAW-84: ...and its GLYPH, which is a member of the same family
      //--- (`DrawStripFootGlyphName`) and was not in this list either — the same
      //--- partial-delete shape as the band family above, one seat over.
      if(ObjectFind(0, DrawStripFootName(fd)) >= 0)
      { ObjectDelete(0, DrawStripFootName(fd)); dirty = true; }
      if(ObjectFind(0, DrawStripFootSkinName(fd)) >= 0)
      { ObjectDelete(0, DrawStripFootSkinName(fd)); dirty = true; }
      if(ObjectFind(0, DrawStripFootGlyphName(fd)) >= 0)
      { ObjectDelete(0, DrawStripFootGlyphName(fd)); dirty = true; }
      if(ObjectFind(0, DrawStripFootLabelName(fd)) >= 0)
      { ObjectDelete(0, DrawStripFootLabelName(fd)); dirty = true; }
   }
   return dirty;
}

//--- purge every gear object (gear shut).
bool DrawStripGearPurge()
{
   if(s_dsGearHeadY < 0 && s_dsGRN <= 0 && s_dsGGN <= 0) return false;
   return DrawStripGearObjectsPurge();
}

//--- P-DRAW-29 (2026-09-24) — THE PLATE WEARS THE CARDS' OWN SKIN. User order:
//--- «کل ظاهر پنل مثل بقیه بشه». The flat rectangle is retired for a 9-slice of
//--- the panels' own Obsidian-Gold surface (margin 14, radius 10, 1px #2C3444
//--- border, drop shadow, top catchlight — tools/gen-th3-icons.js `ds_*`): the
//--- plate's height is ALWAYS 48+36k (quick row + k bands on the CELL+GAP grid,
//--- DrawStripLayout's own arithmetic), so one top cap (margin + 44) + k mid
//--- bands (36) + one bottom cap (4 + margin) composes every height, and the
//--- middles crop to every width (MT4 crops a smaller XSIZE/YSIZE, never
//--- stretches — each middle is uniform along its crop axis, so the crop is
//--- invisible). The mid-row centre is a plain DSTRIP_CLR_PANEL rect (flat
//--- mid-tone, one level off the baked ramp — invisible). A plate that cannot
//--- be skinned (taller than 24 bands, wider than 660) keeps the legacy rect,
//--- so an unmeasurable layout never draws a half plate. (Metrics live with
//--- the V6 shell metrics above: MQL4 is define-before-use.)
string DrawStripSkinName(const int i)
{
   switch(i)
   {
      case 0: return "PnlDrawS_BGtL";
      case 1: return "PnlDrawS_BGtM";
      case 2: return "PnlDrawS_BGtR";
      case 3: return "PnlDrawS_BGmL";
      case 4: return "PnlDrawS_BGmM";
      case 5: return "PnlDrawS_BGmR";
      case 6: return "PnlDrawS_BGbL";
      case 7: return "PnlDrawS_BGbM";
      case 8: return "PnlDrawS_BGbR";
   }
   return "";
}
//--- P-DRAW-32: the SETTINGS PANEL'S OWN nine pieces. One baker, one skin, two
//--- plates — the family index is the whole difference.
string DrawStripGearSkinName(const int i)
{
   switch(i)
   {
      case 0: return "PnlDrawS_GBtL";
      case 1: return "PnlDrawS_GBtM";
      case 2: return "PnlDrawS_GBtR";
      case 3: return "PnlDrawS_GBmL";
      case 4: return "PnlDrawS_GBmM";
      case 5: return "PnlDrawS_GBmR";
      case 6: return "PnlDrawS_GBbL";
      case 7: return "PnlDrawS_GBbM";
      case 8: return "PnlDrawS_GBbR";
   }
   return "";
}
//--- P-DRAW-48 (2026-09-26) — THE BOARD'S OWN NINE PIECES, and they must be its
//--- own. `DrawStripSkinPiece` answered the STRIP's names for family 2, so the two
//--- plates were ONE set of objects: the strip's plate (height 48, k = 0) deletes
//--- the mid pieces on every paint and the board's plate (k = 10) re-created them
//--- as the NEWEST objects at Z_STRIP_ICON — i.e. over the board's 64 cells, its
//--- RECENT band and its HEX field. Measured on the reported chart: the board's
//--- whole body was ONE colour at 24,750 samples. One plate, one name.
string DrawStripBoardSkinName(const int i)
{
   switch(i)
   {
      case 0: return "PnlDrawS_BBtL";
      case 1: return "PnlDrawS_BBtM";
      case 2: return "PnlDrawS_BBtR";
      case 3: return "PnlDrawS_BBmL";
      case 4: return "PnlDrawS_BBmM";
      case 5: return "PnlDrawS_BBmR";
      case 6: return "PnlDrawS_BBbL";
      case 7: return "PnlDrawS_BBbM";
      case 8: return "PnlDrawS_BBbR";
   }
   return "";
}
//--- P-DRAW-89 (2026-09-29) — THE PLATE'S TRANSPARENCY IS RETIRED. User order:
//--- «این شفافیت پنل به کل حذف کن لازم نیستش». It was not a tint: with
//--- `s_dsPlateTIdx > 0` the underlayer stopped being a PANEL tone and became the
//--- CHART's own background (`DrawStripPlateFill` -> `GetCachedChartBgColor`), and
//--- `StrapBodyTone` returned that same raw colour for every cell. So the whole
//--- surface — track, rows, cells, grips — took one colour off `CHART_COLOR_BACKGROUND`:
//--- cyan on the dark template, magenta-blue on the light one. MEASURED, the panel
//--- census on 2026-09-29 11:29 read `PnlDrawS_GTrack bgcolor=-16924895` =
//--- `0xFEFDBF21` = R33 G191 B253, a value that exists in no palette and in no
//--- painter here — it was the chart's own. The four tabs beside it read 2892317
//--- (the card tone) because they are painted from a constant, not from the tone
//--- chain, which is exactly why only the tone-driven surfaces went wrong.
//---
//--- Why deletion and not a blend: a blend still asks the chart for a colour, and the
//--- chart's background is a USER choice (a template, a preset, a light theme) that
//--- the panel must never depend on. One look, one owner, zero chart reads on this
//--- surface. The `_t30/60/90.bmp` sets go with it — nothing asks for them any more.
int    DrawStripPlateT()      { return 0; }
int    DrawStripPlateTPct()   { return 0; }
void   DrawStripPlateTSet(const int i) { /* retired: the plate has one look */ }
string DrawStripSkinRes(const string base)
{
   return "::Files\\Icons\\" + base + ".bmp";
}
//--- the underlayer behind the skin: the panel tone when the plate is solid, the
//--- chart's own background when it is translucent — which is what keeps P-DRAW-35's
//--- white-chart fringe fix while letting the chart show through the plate.
color DrawStripPlateFill()
{
   //--- P-DRAW-89: the chart's background is NEVER this panel's colour. It used to
   //--- be one of two answers, and on a light template the whole surface went
   //--- chart-coloured. One look, one owner.
   return DSTRIP_CLR_PANEL;
}

//--- P-DRAW-69 — THE 42px CELL IS THE ONLY GRID, AND ONE CELL IS ONE TONE. The
//--- cards bake ONE body with a hairline at every row seam and NO per-row face
//--- (measured on `pnl_card7.bmp`: the body reads the same (24,29,38) at x=20, 100,
//--- 170, 240, 300, and the seam rows 69/70 read #222832 edge to edge). This panel
//--- had TWO grids: the bands split the body into 6, and every row drew its own
//--- face at the ramp's own centre — which lands 1 RGB unit off the band beneath it
//--- (row 98 -> (22,26,35); the band [93,142] -> (22,27,35)), so every row read as
//--- its own plate. The bands now ride the SURFACE's cell grid and the cells are
//--- 42px, so a row's face IS its band and the plate reads as one glass.
#define DSTRIP_BODY_MAX 40      // cells + the head and tail bands (k <= 24)
#define DSTRIP_SEAM_H    2       // the card's own seam is 2 rows of white @ 5.5 %
//--- P-DRAW-70 — THE RAMP IS THE CARD'S, PARAMETERISED BY THE SURFACE'S OWN HEIGHT.
//--- `BioCardTone(t)` IS `cardGrad(t)` in tools/gen-th3-icons.js, and the card bakes
//--- it as `cardGrad(cy / H)` over the WHOLE card: TOP at 0 %, MID at 52 %, BOT at
//--- 100 %. This function handed it `0.52 + 0.48·t` instead — it kept only the ramp's
//--- LOWER half and stretched it over the body, so a plate hit CARD_MID four times
//--- too early and sat 5-10 RGB units under the card at every height. Measured on the
//--- Paint tab (plate 342) against `pnl_card7.bmp` (content 398), same fraction:
//---   old  plate content 119 -> (22,26,35)   card at 119/398 -> (27,33,43)
//---   new  plate content 119 -> (25,31,40)   card at 119/398 -> (25,31,40)
color StrapBodyTone(const int dy, const int bandH, const int plateH)
{
   //--- P-DRAW-89: the tone is a TONE. It was short-circuited to the chart's own
   //--- background whenever the plate was translucent, which is how the tab track
   //--- came out cyan (measured -16924895 = 0xFEFDBF21) on a dark template. A
   //--- still plate falls back to the panel tone; a moving one always reads the ramp.
   if(plateH <= 0) return DSTRIP_CLR_PANEL;
   double t = ((double)dy + bandH * 0.5) / (double)plateH;
   if(t < 0.0) t = 0.0;
   if(t > 1.0) t = 1.0;
   return BioCardTone(t);
}
//--- the tone of the CELL that owns `contentY` — the ONE answer a row, a popover
//--- row, the tab track and the band under them all ask, so two owners can never
//--- disagree by a unit (H-06). Above `gridTop` is the head's own single band.
color StrapCellTone(const int contentY, const int bodyTop, const int gridTop, const int plateH)
{
   if(contentY < gridTop) return StrapBodyTone(bodyTop, gridTop - bodyTop, plateH);
   int cell = contentY - ((contentY - gridTop) % DSTRIP_SKIN_MID);
   return StrapBodyTone(cell, DSTRIP_SKIN_MID, plateH);
}
//--- the seat's ring wears the BORDER colour while it reads against the plate, else
//--- the legibility floor's own outline (catalogue 1: an invisible ring is the
//--- "empty slot"). `BioSwatchBorder` answers the same question with a neutral
//--- outline, which is why the ring cannot reuse it verbatim.
color StrapRingInk(const color c, const color backdrop)
{
   return (BioContrast(c, backdrop) < BIO_SWATCH_MIN_CONTRAST) ? BIO_CLR_MUTED : c;
}
//--- the body's bands: one name per band per family, and band 0 IS the shipped
//--- body object (piece 4), so an older build's plate cannot leave a ghost.
string DrawStripBodyName(const int fam, const int b)
{
   string base = DrawStripSkinPiece(fam, 4);
   return (b == 0) ? base : base + "B" + IntegerToString(b);
}
//--- P-DRAW-69: the seam rides the CELL, so the bands and the rules are one walk and
//--- one owner. Its name carries the plate's own prefix, so `DrawStripIsBg` reads a
//--- tap on it as a tap on the plate (P-DRAW-11) instead of a dead pixel.
string DrawStripSeamName(const int fam, const int b)
{
   return DrawStripBodyName(fam, b) + "S";
}
//--- one cell: its flat tone (the cards have no per-row face) and, from `seamFrom`
//--- down, the card's own 2px hairline at the cell's top edge, edge to edge.
bool DrawStripCellPaint(const int fam, const int b, const int plateTop, const int plateH,
                        const int x, const int y, const int w, const int h,
                        const int seamFrom)
{
   color tone = StrapBodyTone(y - plateTop, h, plateH);
   bool dirty = DrawStripBtnZ(DrawStripBodyName(fam, b), x, y, w, h,
                              tone, tone, tone, "", "", Z_STRIP);
   int cy = y - plateTop;
   if(cy >= seamFrom && seamFrom >= 0)
      dirty |= DrawStripRect(DrawStripSeamName(fam, b), x - 1, y,
                             w + 2, DSTRIP_SEAM_H,
                             DSTRIP_CLR_LINE, Z_STRIP_ICON);
   return dirty;
}
//--- P-DRAW-70: `bodyTop` is where this surface's ramp starts — DSTRIP_BODY_TOP (2,
//--- the card's own first body row) for the two cards, and the baked cap's content
//--- bottom (44) for the strip's 48px quick row, which is a TOOLBAR and keeps the
//--- shipped cap ramp. A card that starts its body at 44 wears the cap's own 44px
//--- CARD_TOP->CARD_MID walk on top of the card's ramp, which is the 5-10 unit hole.
bool DrawStripBodyPaint(const int fam, const int plateTop, const int plateH,
                        const int x, const int y, const int w, const int h,
                        const int gridTop, const int seamFrom)
{
   bool dirty = false;
   int b = 0, y0 = y, yEnd = y + h;
   int headBot = DSTRIP_SKIN_TOPT - DSTRIP_SKIN_M;
   if(gridTop > y0 && gridTop < yEnd)
   {
      dirty |= DrawStripCellPaint(fam, b++, plateTop, plateH, x, y0, w, gridTop - y0, seamFrom);
      y0 = gridTop;
   }
   while(y0 < yEnd && b < DSTRIP_BODY_MAX - 1)
   {
      int y1 = y0 + DSTRIP_SKIN_MID;
      if(y1 > yEnd) y1 = yEnd;
      dirty |= DrawStripCellPaint(fam, b++, plateTop, plateH, x, y0, w, y1 - y0, seamFrom);
      y0 = y1;
   }
   if(y0 < yEnd)   // the tail: the foot and the plate's own air, one band
      dirty |= DrawStripCellPaint(fam, b++, plateTop, plateH, x, y0, w, yEnd - y0, seamFrom);
   for(int t = b; t < DSTRIP_BODY_MAX; t++)
   {
      string nm = DrawStripBodyName(fam, t);
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
      string sn = DrawStripSeamName(fam, t);
      if(ObjectFind(0, sn) >= 0) { ObjectDelete(0, sn); dirty = true; }
   }
   return dirty;
}
bool DrawStripBodyPurge(const int fam)
{
   bool dirty = false;
   for(int b = 0; b < DSTRIP_BODY_MAX; b++)
   {
      string nm = DrawStripBodyName(fam, b);
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
      string sn = DrawStripSeamName(fam, b);
      if(ObjectFind(0, sn) >= 0) { ObjectDelete(0, sn); dirty = true; }
   }
   return dirty;
}

//--- 0 = the strip's plate · 1 = the settings panel's plate (P-DRAW-32).
string DrawStripSkinPiece(const int fam, const int i)
{
   return (fam == 1 ? DrawStripGearSkinName(i)
                    : (fam == 2 ? DrawStripBoardSkinName(i) : DrawStripSkinName(i)));
}
//--- the plate is a FAMILY now (9 skin pieces, or the legacy rect): a tap on
//--- any of them is a tap on the plate (P-DRAW-11's popover rule). P-DRAW-32: the
//--- SETTINGS PANEL's plate and its section bands belong to the same family, so a
//--- tap on the panel's own surface never reads as a tap on the chart.
bool DrawStripIsBg(const string nm)
{
   //--- P-DRAW-83: THE PANEL'S OWN PLATE IS THE PANEL'S PLATE. `DrawStripGearBgName()`
   //--- ("PnlDrawS_GBG", the retired underlayer) matched here by the letter B, while
   //--- the plate this build really paints — "PnlDrawS_Gbake" / "Gtop" / "Gmid*" /
   //--- "Gbot" — differs by the case of that one letter and matched NOTHING. With the
   //--- plate back under its controls (see DrawStripGearPlate) that means the panel's
   //--- own margins, padding and air are pixels no control owns: a press there fell
   //--- past every branch of the router and out to the CHART, which is the half of
   //--- P-DRAW-32's rule ("a tap on the panel's own surface never reads as a tap on
   //--- the chart") the spelling left open. Case-sensitive, and no control name
   //--- begins `Gb`: GT/GG/GR/GF/GE/GS/GU/GH and the tab bed keep their own owners.
   return (StringFind(nm, "PnlDrawS_BG") == 0 ||
           StringFind(nm, "PnlDrawS_Gb") == 0 ||
           StringFind(nm, "PnlDrawS_BB") == 0 ||   // P-DRAW-48: the board's own plate
           StringFind(nm, "PnlDrawS_GB") == 0 ||
           StringFind(nm, "PnlDrawS_GH") == 0 ||
           StringFind(nm, "PnlDrawS_GS") == 0 ||
           StringFind(nm, "PnlDrawS_GU") == 0);
}
//--- P-DRAW-48: which of those plates is the COLOUR BOARD's own (`BB…`, one letter
//--- apart from the strip's `BG…`). It is the one surface that must not shut the
//--- popover it belongs to — its body is the space between its own cells.
bool DrawStripIsBoardPlate(const string nm)
{
   return (StringFind(nm, "PnlDrawS_BB") == 0);
}
//--- mid bands below the plate's own top zone, from that plate's height
//--- (-1: this height is off the skin's own 48 + 42k grid).
int DrawStripSkinKFor(const int h)
{
   if(h < 48) return -1;
   int k = (h - 48) / DSTRIP_SKIN_MID;
   if(k < 0 || k > DSTRIP_SKIN_MAXK || 48 + k * DSTRIP_SKIN_MID != h) return -1;
   return k;
}
bool DrawStripSkinFitsFor(const int w, const int h)
{
   int k = DrawStripSkinKFor(h);
   return (k >= 0 && w > 0 && w <= DSTRIP_SKIN_MAXW &&
           w + 2 * DSTRIP_SKIN_M - 2 * DSTRIP_SKIN_CAP <= DSTRIP_SKIN_MIDW);
}
int  DrawStripSkinK()     { return DrawStripSkinKFor(s_dsH); }
bool DrawStripSkinFits()  { return DrawStripSkinFitsFor(s_dsW, s_dsH); }
//--- one skin bitmap: created once with the rung's face, guarded after (the
//--- module's write law — every ObjectSet* repaints at the chart's object
//--- count, so a write of a value already there is pure loss).
bool DrawStripSkinBmp(const string nm, const int x, const int y, const int w,
                      const int h, const string res, const int z = Z_STRIP)
{
   bool dirty = false;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_BITMAP_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, z);
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, "");
      dirty = true;
   }
   else
   {
      //--- the z is a write-on-create fact otherwise: a plate that was painted as
      //--- family 0 (Z_STRIP) and is now painted as a CARD must be re-asserted,
      //--- or the card keeps sitting UNDER the strip's own chrome. One compare.
      dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);
   }
   dirty |= DrawStripSetStr2(nm, OBJPROP_BMPFILE, 0, res);
   dirty |= DrawStripSetStr2(nm, OBJPROP_BMPFILE, 1, res);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);
   return dirty;
}
//--- delete one skin family (teardown law: by prefix family, 100%).
//--- P-DRAW-42 (2026-09-25) — AND THE FAMILY'S OWN BG RECT. Reported: a flat dark
//--- rectangle the size of the settings panel left on the chart with nothing on it.
//--- P-DRAW-35 made `PnlDrawS_BG`/`PnlDrawS_GBG` a permanent underlayer, and a purge
//--- that took the 9 tiles but not the underlayer left exactly that rectangle — the
//--- plate is ONE surface, so its one owner takes both, for both families.
bool DrawStripSkinPurgeAt(const int fam)
{
   bool dirty = false;
   for(int i = 0; i < 9; i++)
   {
      string nm = DrawStripSkinPiece(fam, i);
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
   }
   dirty |= DrawStripBodyPurge(fam);   // P-DRAW-67: the body's bands go with it
   if(fam == 1)
   {
      // pnl_card* path: also purge the bot-cap and the extended mid tiles (GBm9..11)
      string bc = DrawStripGearSkinName(0) + "Bot";
      if(ObjectFind(0, bc) >= 0) { ObjectDelete(0, bc); dirty = true; }
      for(int mi = 9; mi < DSTRIP_GEAR_BLK_MAX; mi++)
      {
         string mn = "PnlDrawS_GBm" + IntegerToString(mi);
         if(ObjectFind(0, mn) >= 0) { ObjectDelete(0, mn); dirty = true; }
      }
   }
   string bg = (fam == 1 ? DrawStripGearBgName()
                         : (fam == 2 ? DrawStripBoardBgName() : DrawStripBgName()));
   if(ObjectFind(0, bg) >= 0) { ObjectDelete(0, bg); dirty = true; }
   return dirty;
}
//--- P-DRAW-32: BOTH plates die together — a close (or a hide) owns the whole
//--- surface, and a family left behind is the ghost this project keeps paying for.
bool DrawStripSkinPurge()
{
   bool dirty = DrawStripSkinPurgeAt(0);
   dirty |= DrawStripSkinPurgeAt(1);
   dirty |= DrawStripSkinPurgeAt(2);   // P-DRAW-48: the colour board's own plate
   return dirty;
}
bool DrawStripGearSkinPurge()
{
   return DrawStripSkinPurgeAt(1);
}
//--- P-DRAW-32: ONE 9-slice painter, TWO plates. `fam` picks the family (the strip
//--- or the settings panel); the rect is the caller's, so the panel's plate can no
//--- longer be the strip's plate growing.
bool DrawStripSkinPaintAt(const int fam, const int x, const int y, const int w, const int h,
                          const int gridTop, const int seamFrom, const int bodyTop)
{
   bool dirty = false;
   if(!DrawStripSkinFitsFor(w, h)) { dirty |= DrawStripSkinPurgeAt(fam); return dirty; }
   int k = DrawStripSkinKFor(h);
   int sx = x - DSTRIP_SKIN_M, sy = y - DSTRIP_SKIN_M;
   int TW = w + 2 * DSTRIP_SKIN_M;
   int midW = TW - 2 * DSTRIP_SKIN_CAP;
   int midY = sy + DSTRIP_SKIN_TOPT, midH = k * DSTRIP_SKIN_MID;
   int botY = midY + midH;
   color fill = DrawStripPlateFill();   // P-DRAW-43: solid tone, or the chart's own bg
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 0), sx, sy,
                             DSTRIP_SKIN_CAP, DSTRIP_SKIN_TOPT,
                             DrawStripSkinRes("ds_top_l"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 1), sx + DSTRIP_SKIN_CAP, sy,
                             midW, DSTRIP_SKIN_TOPT, DrawStripSkinRes("ds_top_m"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 2), sx + TW - DSTRIP_SKIN_CAP, sy,
                             DSTRIP_SKIN_CAP, DSTRIP_SKIN_TOPT,
                             DrawStripSkinRes("ds_top_r"));
   if(k > 0)
   {
      dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 3), sx, midY,
                                DSTRIP_SKIN_EDGE, midH, DrawStripSkinRes("ds_mid_l"));
      // P-DRAW-48: the plate's own body — Z_STRIP, never the cells' layer.
      // P-DRAW-67: and it is the cards' RAMP now, band by band (see StrapBodyTone).
      // P-DRAW-69: on the SURFACE's own 42px cell grid, one flat tone per cell plus
      // P-DRAW-70: from `bodyTop` — the card's ramp covers the cap's own rows too.
      int bodyBot = y + h - (DSTRIP_SKIN_BOTT - DSTRIP_SKIN_M);
      if(bodyBot > y + bodyTop)
         dirty |= DrawStripBodyPaint(fam, y, h, sx + DSTRIP_SKIN_EDGE, y + bodyTop,
                                     TW - 2 * DSTRIP_SKIN_EDGE, bodyBot - bodyTop,
                                     gridTop, seamFrom);
      dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 5), sx + TW - DSTRIP_SKIN_EDGE, midY,
                                DSTRIP_SKIN_EDGE, midH, DrawStripSkinRes("ds_mid_r"));
   }
   else
   {
      for(int i = 3; i <= 5; i++)
      {
         // P-UI-34 (2026-09-25): was DrawStripSkinName(i) — always family 0.
         // When fam==1 (gear panel) the mid pieces are family 1 names, so the
         // family-0 names were never deleted and their stale OBJ_BUTTONs stayed
         // on the chart wearing the OS default (white) background.
         string nm = DrawStripSkinPiece(fam, i);
         if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
      }
      dirty |= DrawStripBodyPurge(fam);   // P-DRAW-67: a 48px plate has no body
   }
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 6), sx, botY,
                             DSTRIP_SKIN_CAP, DSTRIP_SKIN_BOTT,
                             DrawStripSkinRes("ds_bot_l"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 7), sx + DSTRIP_SKIN_CAP, botY,
                             midW, DSTRIP_SKIN_BOTT, DrawStripSkinRes("ds_bot_m"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 8), sx + TW - DSTRIP_SKIN_CAP, botY,
                             DSTRIP_SKIN_CAP, DSTRIP_SKIN_BOTT,
                             DrawStripSkinRes("ds_bot_r"));
   //--- P-DRAW-35 (2026-09-25): OBJ_BITMAP_LABEL does NOT honour alpha on a white
   //--- chart — every transparent pixel in the skin BMP reads as white.  A solid
   //--- RECTANGLE_LABEL behind the skin (same content rect, no border, Z_STRIP-1)
   //--- fills the rounded-corner gap and the shadow margin so the panel looks
   //--- identical on white and black charts.  This replaces the old "delete bg when
   //--- skin fits" path; the bg rect is now the permanent underlayer.
   //--- P-DRAW-48: fam 2 (the board) has its OWN underlayer; the strip's
   //--- `PnlDrawS_BG` was reused by the first cut and moved the strip's own
   //--- floor under the board — one surface, one name.
   string bg = (fam == 1 ? DrawStripGearBgName()
                         : (fam == 2 ? DrawStripBoardBgName() : DrawStripBgName()));
   if(ObjectFind(0, bg) < 0)
   {
      if(!ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return dirty;
      ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR,       fill);
      ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER,      Z_STRIP_BG);
      dirty = true;
   }
   dirty |= DrawStripSetInt(bg, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(bg, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(bg, OBJPROP_XSIZE,     w);
   dirty |= DrawStripSetInt(bg, OBJPROP_YSIZE,     h);
   dirty |= DrawStripSetInt(bg, OBJPROP_COLOR,     fill);
   dirty |= DrawStripSetInt(bg, OBJPROP_BGCOLOR,   fill);
   return dirty;
}
//--- the strip's own plate: the caller's rect is the strip's own content box.
bool DrawStripSkinPaint()
{
   return DrawStripSkinPaintAt(0, s_dsX, s_dsY, s_dsW, s_dsH,
                               DSTRIP_STRIP_GRID_TOP, -1, DSTRIP_STRIP_BODY_TOP);
}
//--- P-DRAW-32: the SETTINGS PANEL's plate, at ITS OWN origin and size.
//--- P-DRAW-35: DrawStripSkinPaintAt(1,...) now owns DrawStripGearBgName() — both the
//--- skin-fits underlayer and the fallback flat rect — so there is no duplication here.
//--- P-DRAW-40 (2026-09-25): the drawing's own pixel box, measured the way P-DRAW-20
//--- measures it (every anchor that projects; the anchors are the contiguous 0..n-1
//--- set). ONE implementation, because a second copy of a measurement is how two
//--- surfaces come to disagree about where the work is (H-06). P-DRAW-73: it sits
//--- ABOVE the board's placer too, which now asks the same question (H-05).
bool DrawStripDrawingBox(const string name, int &x1, int &y1, int &x2, int &y2)
{
   bool have = false;
   for(int i = 0; i < 3; i++)
   {
      int ax = 0, ay = 0;
      if(!DrawAnchorXY(name, i, ax, ay)) break;   // anchors are contiguous 0..n-1
      if(!have) { x1 = ax; x2 = ax; y1 = ay; y2 = ay; have = true; continue; }
      if(ax < x1) x1 = ax;
      if(ax > x2) x2 = ax;
      if(ay < y1) y1 = ay;
      if(ay > y2) y2 = ay;
   }
   return have;
}
//--- P-DRAW-45 (2026-09-25) — THE OVERLAP, IN PIXELS. One owner for both placers: the
//--- panel's eight scored positions and the board's docked spot, so two surfaces can
//--- never answer "do we touch?" two different ways (H-06).
int DrawStripRectOverlap(const int ax, const int ay, const int aw, const int ah,
                         const int bx, const int by, const int bw, const int bh)
{
   int x1 = MathMax(ax, bx), y1 = MathMax(ay, by);
   int x2 = MathMin(ax + aw, bx + bw), y2 = MathMin(ay + ah, by + bh);
   if(x2 <= x1 || y2 <= y1) return 0;
   long w = (long)x2 - (long)x1, h = (long)y2 - (long)y1;
   long a = w * h;
   if(a > 2147483647) return 2147483647;
   return (int)a;
}

//--- P-DRAW-48: THE BOARD's own plate — its own origin, its own family, so the
//--- strip stays the compact quick row it is (the reference's architecture).
bool DrawStripBoardPlate()
{
   if(s_dsBW <= 0 || s_dsBH <= 0) return false;
   return DrawStripSkinPaintAt(2, s_dsBX, s_dsBY, s_dsBW, s_dsBH,
                               DSTRIP_BOARD_GRID_TOP, DSTRIP_BOARD_GRID_TOP, DSTRIP_BODY_TOP);
}
//--- WHERE THE BOARD OPENS. Docked: beside the strip, SCORED against the two surfaces
//--- it must not touch (the settings panel and the drawing it serves), so the colour
//--- board can no longer land on the panel that was opened under the strip.
//--- Float: the hand's own spot, clamped — the pin's OFF state.
void DrawStripBoardPlace()
{
   if(s_dsBW <= 0 || s_dsBH <= 0) return;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   int gm = 4 + DSTRIP_SKIN_M;   // P-DRAW-29: the carried skin stays on screen
   int maxX = cw - s_dsBW - gm, maxY = ch - s_dsBH - gm;
   if(maxX < gm) maxX = gm;
   if(maxY < gm) maxY = gm;
   if(s_dsBManual)
   {
      if(s_dsBX < gm) s_dsBX = gm;
      if(s_dsBY < gm) s_dsBY = gm;
      if(s_dsBX > maxX) s_dsBX = maxX;
      if(s_dsBY > maxY) s_dsBY = maxY;
      return;
   }
   //--- P-DRAW-73: H-05 made real for the board. It docked at ONE spot (under the
   //--- strip) and knew neither the panel nor the drawing, so a panel placed below the
   //--- strip and one tap on the colour seat put a 468px board straight through it.
   //--- Four sides scored with the panel's own weights (the drawing x1000, a surface
   //--- x20), each that needs no clamping, the reading order when none fits. Bounded:
   //--- 4 candidates x 3 rects, once per open — never in a paint (G-12).
   int dx1 = 0, dy1 = 0, dx2 = 0, dy2 = 0;
   bool haveDraw = DrawStripDrawingBox(s_dsObj, dx1, dy1, dx2, dy2);
   const int W = s_dsBW, H = s_dsBH;
   int px[4], py[4];
   px[0] = s_dsX;                     py[0] = s_dsY + s_dsH + 2;              // below
   px[1] = s_dsX;                     py[1] = s_dsY - H - 2;                  // above
   px[2] = s_dsX + s_dsW + 2;         py[2] = s_dsY;                          // right
   px[3] = s_dsX - W - 2;             py[3] = s_dsY;                          // left
   int best = -1; long bestScore = 0;
   for(int c = 0; c < 4; c++)
   {
      if(px[c] < gm || py[c] < gm || px[c] > maxX || py[c] > maxY) continue;
      const int oDraw  = haveDraw ? DrawStripRectOverlap(px[c], py[c], W, H, dx1, dy1, dx2 - dx1, dy2 - dy1) : 0;
      const int oPanel = (s_dsGear != 0 && s_dsGearW0 > 0 && s_dsGearH > 0)
                         ? DrawStripRectOverlap(px[c], py[c], W, H, s_dsGEX, s_dsGEY, s_dsGearW0, s_dsGearH) : 0;
      const int oPlate = DrawStripRectOverlap(px[c], py[c], W, H, s_dsX, s_dsY, s_dsW, s_dsH);
      const long score = -((long)oDraw * 1000 + (long)oPanel * 20 + (long)oPlate * 20);
      if(best < 0 || score > bestScore) { best = c; bestScore = score; }
   }
   if(best < 0) best = 0;   // nothing fits whole: the reading order, clamped below
   int bx = px[best], by = py[best];
   if(bx > maxX) bx = maxX;
   if(by > maxY) by = maxY;
   if(bx < gm) bx = gm;
   if(by < gm) by = gm;
   s_dsBX = bx; s_dsBY = by;
}

//--- P-DRAW-48 — THE OPACITY BAR'S OWN GEOMETRY AND ITS OWN GRAB. The paint and
//--- the hand read ONE answer: the label keeps the RECENT column, the readout its
//--- own seat, and the bar is what is left between them (the cards' track metrics).
int DrawStripHexX() { return s_dsBX + DSTRIP_PAD + DSTRIP_PREC_LW; }
int DrawStripHexW() { return DSTRIP_HEX_W; }
//--- P-DRAW-66: the track starts after the FIELD now (the band is shared), so the
//--- hand's drag begins on the bar and a press on the field can never move it.
int DrawStripOpTrackX() { return DrawStripHexX() + DSTRIP_HEX_W + DSTRIP_PAD; }
int DrawStripOpTrackW()
{
   int w = s_dsBW - DSTRIP_PAD - (DrawStripOpTrackX() - s_dsBX) - DSTRIP_OP_VW;
   return (w > 2 * DSTRIP_KNOB_W) ? w : 2 * DSTRIP_KNOB_W;
}
//--- the value a pointer x means, over the SAME span the knob rides — the exact
//--- inverse of the knob's own position, so what the hand sees is what `NN%` says.
int DrawStripOpValueAt(const int mx)
{
   int span = DrawStripOpTrackW() - DSTRIP_KNOB_W;
   if(span <= 0) return DRAW_OP_MIN;
   double f = (mx - DrawStripOpTrackX()) / (double)span;
   if(f < 0.0) f = 0.0;
   if(f > 1.0) f = 1.0;
   int v = (int)MathRound(f * 100.0);
   if(v < DRAW_OP_MIN) v = DRAW_OP_MIN;
   if(v > 100) v = 100;
   return v;
}
//--- is this press on the bar's own band? The whole 42 px row is the target (an
//--- 8 px bed is no touch target, B-05) and the readout's seat is EXCLUDED, so
//--- tapping `NN%` never jumps the slider.
bool DrawStripOpBarAt(const int mx, const int my)
{
   if(!s_dsOpen || !DrawStripIsColorSlot(s_dsPicker)) return false;
   if(s_dsBW <= 0 || s_dsBH <= 0 || s_dsPOpY < 0) return false;
   int oy0 = s_dsBY + s_dsPOpY;
   if(my < oy0 || my > oy0 + DSTRIP_PICK_ROW) return false;
   int otx = DrawStripOpTrackX(), otw = DrawStripOpTrackW();
   return (mx >= otx - DSTRIP_PICK_GAP && mx <= otx + otw + DSTRIP_PICK_GAP);
}
//--- the bar's write, through the ONE owner (`DrawToolbar`: the `[OPnn]` tag and
//--- the blend the chart wears). One write per real change, so a held bar costs a
//--- paint per move and nothing else (G-09: the cheaper of two equal paths).
bool DrawStripOpDragTo(const int mx)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   //--- P-DRAW-64: the bar follows the OPEN BOARD's role — the border's `[OPnn]` or
   //--- the interior's `[FTnn]`. One bar, one owner, two tags.
   int slot = DrawStripIsColorSlot(s_dsPicker) ? s_dsPicker : DRAW_SLOT_COLOR;
   int op = DrawStripOpValueAt(mx);
   if(slot == DRAW_SLOT_FILLCLR) DrawStripFillShow(s_dsObj);   // P-DRAW-64: tone ⇒ a fill
   if(op == DrawSlotAlphaGet(s_dsObj, slot)) return false;
   DrawSlotOpacitySet(s_dsObj, op, slot);
   if(slot == DRAW_SLOT_COLOR) BoxMidSyncGroup();   // P-DRAW-64a: the tone changed the border's ink
   return true;
}
//--- P-DRAW-75 (2026-09-28) — THE PLATE IS A DERIVED HEIGHT, SO IT IS ALSO A
//--- DERIVED RECT. Everything family 1 paints sits inside `s_dsGearW0 x s_dsGearH`,
//--- but a band left by a TALLER layout, or by a path that resized the plate without
//--- re-running the body walk, keeps its own object and its own Y — the reported tower
//--- of empty 42px bands under the panel, with no content owning them. One bounded
//--- sweep on a REAL layout change (never per paint) takes any band or seam whose own
//--- rect the plate no longer contains. `DrawStripBodyPaint` owns the bands this
//--- surface SHOULD have; this owns the ones it must not keep.
bool DrawStripGearTrimOverflow()
{
   bool dirty = false;
   for(int b = 0; b < DSTRIP_BODY_MAX; b++)
   {
      string nm = DrawStripBodyName(1, b);
      if(ObjectFind(0, nm) >= 0)
      {
         int by = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
         int bh = (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE);
         int bw = (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE);
         //--- the band's OWN bottom, not a 42px worst case: the last band is a
         //--- short tail, so `by + 42` killed a band the plate still holds and left
         //--- the ones a TALLER tab had put below the plate standing on the chart.
         if(by < s_dsGEY || by + bh > s_dsGEY + s_dsGearH || bw > s_dsGearW0)
         { ObjectDelete(0, nm); dirty = true; }
      }
      string sn = DrawStripSeamName(1, b);
      if(ObjectFind(0, sn) >= 0)
      {
         int sy = (int)ObjectGetInteger(0, sn, OBJPROP_YDISTANCE);
         if(sy < s_dsGEY || sy > s_dsGEY + s_dsGearH)
         { ObjectDelete(0, sn); dirty = true; }
      }
   }
   return dirty;
}
bool DrawStripGearPlate()
{
   bool dirty = false;
   // P-DRAW-xx: the gear panel wears the CARDS' own pnl_cardW* skin — the same
   // composed body BiotakPanels uses for wide cards (top cap + one mid per pair-line
   // + bot cap), so the panel reads as a card and the strip is the only ds_* surface.
   // Height = DSTRIP_GEAR_HEAD_H + (1+rows)*DSTRIP_GEAR_ROW_H + DSTRIP_GEAR_FOOT_H.
   // Card geometry mirrors BiotakPanels.mqh (included AFTER this file, so names
   // are unavailable here): margin=14 HEAD_H=56 FOOT_H=48 ROW_H=42.
   int gx = s_dsGEX, gy = s_dsGEY, gw = s_dsGearW0, gh = s_dsGearH;
   //--- P-DRAW-83 (2026-09-29) — THE PLATE IS THE BOTTOM OF ITS OWN LADDER, ALWAYS.
   //--- These four writers passed `Z_PANEL_CARD` (1480) while every control on this
   //--- panel is painted by `DrawStripBtn`/`DrawStripFace` — the STRIP's rungs,
   //--- Z_STRIP_ICON 1441 and Z_STRIP_OVER 1442. 1480 > 1441, so the plate's own card
   //--- bake (one opaque bitmap, the whole 340x348 of it) sat ABOVE the tabs, the
   //--- hex fields, the Interior switch and the foot: paint order hid them, and click
   //--- order gave every pixel of the panel to an object no branch of the click
   //--- router owns. The panel answered NOTHING. The cards' own ladder survives that
   //--- arrangement only because `PnlSkinButtonAct` hit-tests their controls back by
   //--- rectangle on the press (P-UI-128); this panel has no such second channel, so
   //--- the plate must not be above its controls at all. Z_STRIP is the rung the
   //--- strip's own plate wears (DrawStripSkinPaintAt, family 0) and the rung
   //--- `DrawStripSkinBmp` defaults to — one value, both plates.
   //--- P-DRAW-78: EXACT card rows. Content = head 56 + T rows + foot 42 + air 6;
   //--- the cards' own plate for that height is `pnl_card{T-1}` (56 + n*42 + 48):
   //--- the foot row plus the 6px air fills the card's 48px footer exactly, and
   //--- every content row lands on a card row. The old air (34) put every height
   //--- 28px off every bake, which is why the composed body never reached the
   //--- plate's bottom edge.
   //--- LITERALS, not PNL_*: BiotakPanels.mqh is included AFTER this file, so its
   //--- constants do not exist here. 104 = 56+48 · 42 = the row · 70 = 14+56 ·
   //--- 62 = 48+14.
   int cardN = (gh - 104) / 42;
   bool cardExact = ((gh - 104) % 42 == 0 && cardN >= 1 && cardN <= 10);
   bool narrow = (gw == DSTRIP_GEAR_W);

   //--- P-DRAW-78: THE SQUARE UNDERLAYER IS THE SECOND BOX. The cards bake their
   //--- own radius, border and shadow into `pnl_card*` and carry NO rect behind
   //--- them; this rect filled the transparent corners of the rounded skin with a
   //--- hard square, which is the report: two boxes, mixed, the inner one with no
   //--- radius. It is deleted here, every paint, so it cannot survive an upgrade.
   if(ObjectFind(0, DrawStripGearBgName()) >= 0)
   { ObjectDelete(0, DrawStripGearBgName()); dirty = true; }

   if(narrow && cardExact)
   {
      //--- ONE baked card, both corners rounded, zero composition. The bake
      //--- carries the 14px margin itself (cardW+28 x ph+28, PnlCreate's seats).
      dirty |= DrawStripSkinBmp("PnlDrawS_Gbake", gx - 14, gy - 14, gw + 28, gh + 28,
                                "::Files\\Icons\\pnl_card" + IntegerToString(cardN) + ".bmp",
                                Z_STRIP);
      //--- a tab that was wide keeps its composed tiles: they die here.
      if(ObjectFind(0, "PnlDrawS_Gtop") >= 0)
      { ObjectDelete(0, "PnlDrawS_Gtop"); dirty = true; }
      if(ObjectFind(0, "PnlDrawS_Gbot") >= 0)
      { ObjectDelete(0, "PnlDrawS_Gbot"); dirty = true; }
      for(int lm = 0; lm < DSTRIP_GEAR_BLK_MAX; lm++)
      {
         string lmn = "PnlDrawS_Gmid" + IntegerToString(lm);
         if(ObjectFind(0, lmn) >= 0) { ObjectDelete(0, lmn); dirty = true; }
      }
   }
   else
   {
      //--- WIDE (or the off-grid net, which by construction cannot happen): the
      //--- composed W body. pairN counts the same rows the bake above would, so
      //--- the caps land on the same edges either way.
      int pairN = cardExact ? cardN : (gh - 104 + 41) / 42;
      if(pairN < 1) pairN = 1;
      if(pairN > DSTRIP_GEAR_BLK_MAX) { DrawStripSkinPurgeAt(1); return false; }
      // top cap — pnl_cardWtop.bmp (14+56=70px)
      dirty |= DrawStripSkinBmp("PnlDrawS_Gtop",
                                gx - 14, gy - 14, gw + 28, 70,
                                "::Files\\Icons\\pnl_cardWtop.bmp", Z_STRIP);
      for(int li = 0; li < DSTRIP_GEAR_BLK_MAX; li++)
      {
         string mn = "PnlDrawS_Gmid" + IntegerToString(li);
         if(li < pairN)
            dirty |= DrawStripSkinBmp(mn, gx - 14, gy + 70 + li * 42,
                                      gw + 28, 42, "::Files\\Icons\\pnl_cardWmid.bmp",
                                      Z_STRIP);
         else if(ObjectFind(0, mn) >= 0) { ObjectDelete(0, mn); dirty = true; }
      }
      // bot cap — pnl_cardWbot.bmp (48+14=62px)
      dirty |= DrawStripSkinBmp("PnlDrawS_Gbot",
                                gx - 14, gy + 70 + pairN * 42, gw + 28, 62,
                                "::Files\\Icons\\pnl_cardWbot.bmp", Z_STRIP);
      if(ObjectFind(0, "PnlDrawS_Gbake") >= 0)
      { ObjectDelete(0, "PnlDrawS_Gbake"); dirty = true; }
   }
   //--- the retired `ds_*` nine-slice for this family goes with it, every paint.
   for(int op = 0; op <= 8; op++)
   {
      string on = DrawStripGearSkinName(op);
      if(ObjectFind(0, on) >= 0) { ObjectDelete(0, on); dirty = true; }
   }
   //--- P-DRAW-79: THE `Gcard*` SPELLING IS THE ORPHAN, AND IT IS NOT A THEORETICAL
   //--- ONE. `PnlDrawS_Gcard*` also matches the family purge's own
   //--- `PnlDrawS_GB*` test only by accident of the letter, but worse: a chart
   //--- painted by the build that introduced it carries those five objects, and
   //--- the `DrawStripSkinBmp` of THIS build never re-writes nor deletes them —
   //--- so a card-sized plate from the old build sits under the new one, at a
   //--- stale x/y, until the user's next full sweep. The rename ships with the
   //--- sweep that removes the old spelling. Bounded: five exact names, once per
   //--- paint, and a delete only when the object is really there.
   if(ObjectFind(0, "PnlDrawS_Gcard") >= 0)
   { ObjectDelete(0, "PnlDrawS_Gcard"); dirty = true; }
   if(ObjectFind(0, "PnlDrawS_GcardT") >= 0)
   { ObjectDelete(0, "PnlDrawS_GcardT"); dirty = true; }
   if(ObjectFind(0, "PnlDrawS_GcardB") >= 0)
   { ObjectDelete(0, "PnlDrawS_GcardB"); dirty = true; }
   for(int oc = 0; oc < DSTRIP_GEAR_BLK_MAX; oc++)
   {
      string ocn = "PnlDrawS_GcardM" + IntegerToString(oc);
      if(ObjectFind(0, ocn) >= 0) { ObjectDelete(0, ocn); dirty = true; }
   }
   // purge body/seam rects (DrawStripBodyPaint no longer used for fam=1)
   dirty |= DrawStripBodyPurge(1);

   //--- log once per real height change
   static int s_dsPlateTab = -1, s_dsPlateH = -1;
    if(s_dsGear != s_dsPlateTab || gh != s_dsPlateH)
    {
       s_dsPlateTab = s_dsGear; s_dsPlateH = gh;
       dirty |= DrawStripGearTrimOverflow();
       //--- P-DRAFT-02: THE PLATE'S OWN VERDICT, IN ONE LINE. Every earlier report
       //--- of "the panel has no skin" was answered by an argument about which
       //--- branch SHOULD run; this line reports which one DID, whether the object
       //--- exists, what the terminal actually stored for its file, and the
       //--- transparency index that silently replaces the card tone with the
       //--- chart's background. One line, and the next screenshot carries the
       //--- answer with it.
       string plateName = (narrow && cardExact) ? "PnlDrawS_Gbake" : "PnlDrawS_Gtop";
       string wantRes   = (narrow && cardExact)
                          ? ("::Files\\Icons\\pnl_card" + IntegerToString(cardN) + ".bmp")
                          : "::Files\\Icons\\pnl_cardWtop.bmp";
       Print("[drawstrip] PLATE tab=", s_dsGear, " h=", gh, " w=", gw,
             " cardN=", cardN, " exact=", (cardExact ? 1 : 0), " narrow=", (narrow ? 1 : 0),
             " -> branch=", (narrow && cardExact ? "bake" : "wide"),
             " obj=", plateName,
             " exists=", (ObjectFind(0, plateName) >= 0 ? 1 : 0),
             " want=", wantRes,
             " got=", (ObjectFind(0, plateName) >= 0
                       ? ObjectGetString(0, plateName, OBJPROP_BMPFILE, 0) : "-"),
             " xy=", gx, ",", gy,
             " z=", (ObjectFind(0, plateName) >= 0
                     ? (int)ObjectGetInteger(0, plateName, OBJPROP_ZORDER) : -1),
             " plateFill=", (int)DrawStripPlateFill(),
             " rows=", s_dsGRN, " grids=", s_dsGGN, " secs=", s_dsGearSecN);
    }
    return dirty;
}

//--- P-DRAW-32 (2026-09-24) — WHERE THE SETTINGS PANEL OPENS. User order: «پنل
//--- تنظیمات از استریپ جدا باشه». The panel is its own card, so it needs its own spot
//--- and the project's two placement laws apply unchanged (P-BK-27: a toolbar never
//--- covers the handle it belongs to; P-DRAW-31: no two surfaces on one pixel). The
//--- hand's own carry (`s_dsGearManual`) wins everything and is only clamped — a panel
//--- the user placed is not moved by a repaint.
//--- P-DRAW-45 (2026-09-25) — EIGHT POSITIONS, SCORED, ON THE FINAL HEIGHT. User
//--- order: «حتما نباید به سمت پایین باز بشه، باید هوشمند باز بشه سمت راست بالا...
//--- بهترین برای همه سناریو ممکن ... هر دفهه باید کاربر بگیره درگ بکنه». The old
//--- ladder was four sides in a FIXED order and, when none fitted whole, it clamped
//--- candidate 0 — hanging the panel off the bottom edge until the user dragged it
//--- every time. Now four sides AND four corners are measured against the panel's
//--- FINAL height (the layout pass before this paint owns `s_dsGearH`), scored by
//--- what they cover and by the window they leave; the least-bad wins, not the first.
#define DSTRIP_GEAR_POS_N 8
string DrawStripGearSideName(const int i)
{
   string n[DSTRIP_GEAR_POS_N] = {"below", "above", "right", "left",
                                  "below-right", "above-right", "right-low", "left-low"};
   if(i < 0 || i >= DSTRIP_GEAR_POS_N) return "?";
   return n[i];
}

void DrawStripPlaceGear()
{
   if(s_dsGear == 0 || s_dsGearW0 <= 0 || s_dsGearH <= 0) return;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   int gm = 4 + DSTRIP_SKIN_M;   // P-DRAW-29: the skin stands past the content
   int maxX = cw - s_dsGearW0 - gm, maxY = ch - s_dsGearH - gm;
   if(maxX < gm) maxX = gm;
   if(maxY < gm) maxY = gm;
   if(s_dsGearManual || (s_dsGearPlaced && s_dsGearPlacedObj == s_dsObj))
   {
      //--- P-DRAW-88: the hand's spot — or the last scored one — is kept. A tab
      //--- switch changes the HEIGHT, never the home: clamp to the window so a
      //--- taller tab cannot hang off the edge, but never re-score to a corner.
      if(s_dsGEX < gm) s_dsGEX = gm;
      if(s_dsGEY < gm) s_dsGEY = gm;
      if(s_dsGEX > maxX) s_dsGEX = maxX;
      if(s_dsGEY > maxY) s_dsGEY = maxY;
      return;
   }
   //--- P-DRAW-40 (2026-09-25): THE DRAWING IS A HARD RULE FOR THE PANEL TOO.
   //--- Reported: «پنل روی خوده ابجکت ظاهر میشه» — the placer knew the plate and
   //--- the open card and nothing about the object this strip serves (B-10: a
   //--- surface never covers the drawing it belongs to; P-DRAW-31's one-rule-two-
   //--- rects law). Same owner the fresh strip asks: `DrawStripDrawingBox`.
   int dx1 = 0, dy1 = 0, dx2 = 0, dy2 = 0;
   bool haveDraw = DrawStripDrawingBox(s_dsObj, dx1, dy1, dx2, dy2);
   const int W = s_dsGearW0, H = s_dsGearH;
   int px[DSTRIP_GEAR_POS_N], py[DSTRIP_GEAR_POS_N];
   px[0] = s_dsX;                    py[0] = s_dsY + s_dsH + DSTRIP_GEAR_GAP;   // below
   px[1] = s_dsX;                    py[1] = s_dsY - H - DSTRIP_GEAR_GAP;       // above
   px[2] = s_dsX + s_dsW + DSTRIP_GEAR_GAP; py[2] = s_dsY;                    // right
   px[3] = s_dsX - W - DSTRIP_GEAR_GAP;     py[3] = s_dsY;                    // left
   px[4] = s_dsX + s_dsW - W;        py[4] = s_dsY + s_dsH + DSTRIP_GEAR_GAP;   // below-right
   px[5] = s_dsX + s_dsW - W;        py[5] = s_dsY - H - DSTRIP_GEAR_GAP;       // above-right
   px[6] = s_dsX + s_dsW + DSTRIP_GEAR_GAP; py[6] = s_dsY + s_dsH - H;         // right, low
   px[7] = s_dsX - W - DSTRIP_GEAR_GAP;     py[7] = s_dsY + s_dsH - H;         // left, low
   const bool cardOpen = (g_UIPanelRX >= 0 && g_UIPanelRW > 0 && g_UIPanelRH > 0);
   //--- P-DRAW-73 (2026-09-28): the COLOUR BOARD is a surface too, and the panel's
   //--- score did not know it — so the panel could be placed straight through an open
   //--- board (H-05's other half; the board's placer now answers the same question).
   const bool boardOpen = (DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0);
   int best = -1, bestAir = 0; long bestScore = 0;
   for(int c = 0; c < DSTRIP_GEAR_POS_N; c++)
   {
      if(px[c] < gm || py[c] < gm || px[c] > maxX || py[c] > maxY) continue;   // off the window
      const int oDraw  = haveDraw ? DrawStripRectOverlap(px[c], py[c], W, H, dx1, dy1, dx2 - dx1, dy2 - dy1) : 0;
      const int oPlate = DrawStripRectOverlap(px[c], py[c], W, H, s_dsX, s_dsY, s_dsW, s_dsH);
      const int oCard  = cardOpen ? DrawStripRectOverlap(px[c], py[c], W, H, g_UIPanelRX, g_UIPanelRY, g_UIPanelRW, g_UIPanelRH) : 0;
      const int oBoard = boardOpen ? DrawStripRectOverlap(px[c], py[c], W, H, s_dsBX, s_dsBY, s_dsBW, s_dsBH) : 0;
      // P-DRAW-45: the WORK is punished an order of magnitude above the surfaces it
      // shares the screen with (B-10: the panel never covers the drawing it serves),
      // the plate next (P-DRAW-31: two surfaces never share a pixel) and the open card
      // last; between two spots that cover nothing, the one leaving more window wins,
      // and a real tie keeps the reading order (below, above, right, left, corners).
      const long score = -((long)oDraw * 1000 + (long)oPlate * 20 + (long)oBoard * 20 + (long)oCard * 5);
      const int air = MathMin(MathMin(px[c] - gm, py[c] - gm),
                              MathMin(maxX - px[c], maxY - py[c]));
      if(best < 0 || score > bestScore || (score == bestScore && air > bestAir))
      { best = c; bestScore = score; bestAir = air; }
   }
   if(best < 0) best = 0;   // nothing fits whole: the reading order, clamped below
   s_dsGEX = px[best]; s_dsGEY = py[best];
   s_dsGearPlaced = true; s_dsGearPlacedObj = s_dsObj;   // P-DRAW-88: scored once
   if(s_dsGEX < gm) s_dsGEX = gm;
   if(s_dsGEY < gm) s_dsGEY = gm;
   if(s_dsGEX > maxX) s_dsGEX = maxX;
   if(s_dsGEY > maxY) s_dsGEY = maxY;
   //--- P-DRAW-45: ONE line per REAL move — a paint may run many times a second while
   //--- the pointer moves and this project bans unbounded logging. It names the side,
   //--- the spot, the panel size, the window and the air the winner left.
   static int  s_gpLogX = -1, s_gpLogY = -1, s_gpLogSide = -9;
   if(s_gpLogSide != best || s_gpLogX != s_dsGEX || s_gpLogY != s_dsGEY)
   {
      s_gpLogSide = best;
      s_gpLogX = s_dsGEX; s_gpLogY = s_dsGEY;
      Print("[drawstrip] gear side=", DrawStripGearSideName(best),
            " pos=(", s_dsGEX, ",", s_dsGEY, ") size=", W, "x", H,
            " chart=", cw, "x", ch, " air=", bestAir);
   }
}

//--- P-DRAW-42 (2026-09-25) — NO ORPHAN SURVIVES A REATTACH. `PnlDrawS_*` carries no
//--- chart id (one instance per chart), so a plate family or a flat bg rect left by
//--- a killed terminal is still on the chart at the next attach while every static
//--- here starts clean — the user's dark rectangle with nothing on it. One sweep,
//--- once per session, at the first paint: before this session made anything, and
//--- all of one ObjectsDeleteAll call (the same orphan purge InitializeUIStates does
//--- for its own prefix). Costs nothing after the first paint.
static bool s_dsSwept = false;
//--- P-DRAW-84: the gear panel's press already found its control. A release then
//--- arrives on BOTH channels (CHARTEVENT_CLICK and CHARTEVENT_OBJECT_CLICK), and
//--- the dismissal branch below reads a press that lands on the panel as a click on
//--- the chart — which would shut the panel the user is working in. One flag, set by
//--- the press edge and read by the release, so one gesture is one owner.
static bool s_dsGearPressSpent = false;
void DrawStripOrphanSweep()
{
   if(s_dsSwept) return;
   s_dsSwept = true;
   ObjectsDeleteAll(0, "PnlDrawS_");
}

//--- ONE painter, called on open and after every tap: reads the held object and
//--- writes only what changed (the guarded-write law of this codebase), and asks
//--- for a repaint only when something really moved (P-DRAW-09d).
void DrawStripPaint()
{
   if(!s_dsOpen || s_dsObj == "") return;
   DrawStripOrphanSweep();
   if(s_dsKind == DK_NONE || ObjectFind(0, s_dsObj) < 0)
   { Print("[drawstrip] close: paint found no object obj=\"", s_dsObj, "\" kind=", (int)s_dsKind); DrawStripClose(); return; }
   // P-DRAW-08c: the strip is the indicator's surface, so the indicator's own
   // hide-all (the F key) hides it too — a toolbar left floating over a chart the
   // user just muted is the same complaint as a label that stays lit.
   if(IsIndicatorHidden()) { Print("[drawstrip] close: indicator hidden (F) obj=\"", s_dsObj, "\""); DrawStripClose(); return; }
   // P-DRAW-08f: and a drawing the user put away ON THIS TIMEFRAME (the terminal's
   // own "hide on this period", which is OBJPROP_TIMEFRAMES) must not leave a
   // toolbar floating over nothing — the strip serves what is on screen.
   if((long)ObjectGetInteger(0, s_dsObj, OBJPROP_TIMEFRAMES) == OBJ_NO_PERIODS)
   { Print("[drawstrip] close: drawing masked off this timeframe obj=\"", s_dsObj, "\""); DrawStripClose(); return; }
   s_dsN = DrawStripQuickCount(s_dsKind);
   bool dirty = false;

   //--- the plate: the cards' own skin when it fits (P-DRAW-29), the legacy
   //--- flat rect when the layout cannot be skinned — created once, guarded
   //--- after (X, Y, W, H all drift).
   dirty |= DrawStripSkinPaint();
   string bg = DrawStripBgName();
   if(!DrawStripSkinFits())
   {
      if(ObjectFind(0, bg) < 0)
      {
         if(!ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
         ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, DrawStripPlateFill());

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
   }

   int rowY = s_dsY + DSTRIP_PAD;
   //--- grip (drag) + badge (kind xN, info only).
   string hg = DrawStripGripName();
   string tipGrip = "Drag to move the strip";
   dirty |= DrawStripBtn(hg, s_dsX + DSTRIP_PAD, rowY, DSTRIP_CELL, DSTRIP_CELL,
                         DrawStripPlateFill(), DSTRIP_CLR_LABEL, DrawStripPlateFill(), "", tipGrip);
   dirty |= DrawStripFace(DrawStripGripIconName() + "C", s_dsX + DSTRIP_PAD, rowY,
                          DSTRIP_CELL, DSTRIP_CELL, "::Files\\Icons\\pnl_chip.bmp", tipGrip);
   dirty |= DrawStripFace(DrawStripGripIconName(), s_dsX + DSTRIP_PAD, rowY,
                          DSTRIP_CELL, DSTRIP_CELL, "::Files\\Icons\\bk_grip.bmp", tipGrip);
   string badgeTip = "This toolbar serves " + DrawStripTitle() +
                     " — hold the left button on a drawing to bring it up, click away to dismiss" +
                     DrawStripTipScope();
   // P-DRAW-66: the badge's band is the quick row — its ink sits on the row's own
   // centre (the retired writer put it 5px above it) and speaks the title rung.
   dirty |= DrawStripLblIn(DrawStripBadgeName(),
                           s_dsX + s_dsBadgeX, rowY, DSTRIP_CELL,
                           DrawStripTitle(), DSTRIP_CLR_LABEL, badgeTip, 9, true);
   //--- P-DRAW-66: the two group separators (identity | values | commands).
   for(int g = 0; g < 2; g++)
      dirty |= DrawStripRect(DrawStripSepName(g), s_dsX + s_dsSepX[g],
                             rowY + (DSTRIP_CELL - DSTRIP_SEP_H) / 2,
                             DSTRIP_SEP_W, DSTRIP_SEP_H, DSTRIP_CLR_LINE, Z_STRIP_ICON);

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
          if(ObjectFind(0, ic + "C") >= 0) { ObjectDelete(0, ic + "C"); dirty = true; }
          if(ObjectFind(0, ic + "S") >= 0) { ObjectDelete(0, ic + "S"); dirty = true; }
          if(ObjectFind(0, ic + "C2") >= 0) { ObjectDelete(0, ic + "C2"); dirty = true; }
          continue;
      }
      int x = s_dsX + s_dsCX[i];
      string res = DrawStripIconRes(slot, s_dsObj);
      string tip = DrawStripSlotTip(s_dsKind, slot, s_dsObj);
       //--- P-DRAW-64a (2026-09-27) — THE ONE COLOUR SEAT: A RING AROUND A CENTRE.
       //--- User order: «این دوتا باکس ... میشه یکی بشه» + «اونیکه برای رنگ بوردر
       //--- هستش رو ایکونش نباید وسط رنگی باشه باید دورش رنگ باشه». So the seat's own
       //--- button wears the BORDER colour and the nested 24px swatch wears the
       //--- interior's — the border really is AROUND — and a kind with no interior
       //--- shows the plate tone in the middle, i.e. a ring with a hole. Each layer
       //--- names its own role, because the hand lands on one of them (the tip and
       //--- the tap both read which).
       if(DrawStripIsColorSlot(slot))
       {
          bool merged = (slot == DRAW_SLOT_FILLCLR);
          int sw = DSTRIP_SWATCH;   // B-05's 24px floor, the centre's own target
          int swx = x + (DSTRIP_CELL - sw) / 2, swy = rowY + (DSTRIP_CELL - sw) / 2;
          color bcol = DrawStripColorRead(s_dsObj, DRAW_SLOT_COLOR);
          color ccol = merged ? DrawStripColorFace(s_dsObj, DRAW_SLOT_FILLCLR)
                              : DrawStripPlateFill();
          string rtip = DrawStripColorRingTip(s_dsObj, merged);
          string ctip = (merged ? DrawStripColorMidTip(s_dsObj) : rtip);
          bool bOpen = (s_dsPicker == DRAW_SLOT_COLOR);
          //--- P-DRAW-66 — THE RING, NOT THE BLOCK. The seat's own button wore the
          //--- BORDER colour as its whole 32x32 face, so a bright border painted
          //--- 1024 px of pure red into a dark row (the crop that started this).
          //--- The cell is the plate's tone now and the border is its 1px OUTLINE —
          //--- the ring IS the rect's own border, so no bake was needed — with the
          //--- interior's swatch nested inside. 124 coloured px instead of 1024,
          //--- and the seat finally wears the same chip face as its neighbours (it
          //--- was the quick row's one ds_cell32).
          dirty |= DrawStripBtn(on, x, rowY, DSTRIP_CELL, DSTRIP_CELL, DrawStripPlateFill(),
                                DSTRIP_CLR_LABEL,
                                bOpen ? DSTRIP_CLR_ACCENT : StrapRingInk(bcol, DSTRIP_CLR_PANEL),
                                "", rtip);
          dirty |= DrawStripFace(ic + "C", x, rowY, DSTRIP_CELL, DSTRIP_CELL,
                                 bOpen ? "::Files\\Icons\\pnl_chip_gold.bmp"
                                       : "::Files\\Icons\\pnl_chip.bmp", rtip);
          dirty |= DrawStripBtn(ic + "S", swx, swy, sw, sw, ccol, DrawStripInkOn(ccol),
                                (s_dsPicker == DRAW_SLOT_FILLCLR) ? DSTRIP_CLR_ACCENT
                                                                  : BioSwatchBorder(ccol, BIO_CLR_CARD),
                                "", ctip);
          dirty |= DrawStripFace(ic + "C2", swx, swy, sw, sw, "::Files\\Icons\\ds_swatch24.bmp", ctip);
          if(ObjectFind(0, ic) >= 0) { ObjectDelete(0, ic); dirty = true; }   // the seat has no glyph
          continue;
       }
       color face = DrawStripPlateFill(), ink = DSTRIP_CLR_LABEL, rim = DrawStripPlateFill();
       bool chipOn = false;
       if(DrawStripSlotOn(slot, s_dsObj))
          chipOn = true;
       if(DrawStripHasPicker(slot))
          rim = (s_dsPicker == slot) ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_PICK;
       else if(chipOn)
          //--- TV parity: an ON toggle wears the accent hairline (the preview's
          //--- `.scell.on{box-shadow:inset 0 0 0 1px rgba(255,194,71,.34)}`) on
          //--- top of the accent wash the chip below lays down.
          rim = DSTRIP_CLR_ACCENT;
       dirty |= DrawStripBtn(on, x, rowY, DSTRIP_CELL, DSTRIP_CELL, face, ink, rim, "", tip);
       dirty |= DrawStripFace(ic + "C", x, rowY, DSTRIP_CELL, DSTRIP_CELL,
                              chipOn ? "::Files\\Icons\\pnl_chip_gold.bmp" : "::Files\\Icons\\pnl_chip.bmp", tip);
       //--- a seat that was a COLOUR one up to this paint leaves no half behind:
       //--- two probes per non-colour cell, on the repaint path only.
       if(ObjectFind(0, ic + "S") >= 0)  { ObjectDelete(0, ic + "S"); dirty = true; }
       if(ObjectFind(0, ic + "C2") >= 0) { ObjectDelete(0, ic + "C2"); dirty = true; }
       dirty |= DrawStripFace(ic, x, rowY, DSTRIP_CELL, DSTRIP_CELL, res, tip);

   }

   //--- chrome actions: more / gear / pin / del.
   for(int a = 0; a < DSTRIP_ACT_N; a++)
   {
      string an = DrawStripActName(a), ai = DrawStripActIconName(a);
      int x = s_dsX + DrawStripActX(a);
      string tip = DrawStripActTip(a);
       color face = DrawStripPlateFill(), ink = DSTRIP_CLR_LABEL, rim = DrawStripPlateFill();
       bool chipOn = false;
       //--- P-DRAW-66: the chrome wears a rim ONLY while it is active (closed more
       //--- and gear were rimmed into a constant glow), and the bin wears the same
       //--- chip as its neighbours with the destructive INK as its only colour.
       if(a == DSTRIP_ACT_DEL) ink = DSTRIP_CLR_DEL_INK;
       if(a == DSTRIP_ACT_PIN && s_dsPinned) { rim = DSTRIP_CLR_ACCENT; chipOn = true; }
       if(a == DSTRIP_ACT_MORE && s_dsPicker == DSTRIP_MORE) { rim = DSTRIP_CLR_ACCENT; chipOn = true; }
       if(a == DSTRIP_ACT_GEAR && s_dsGear != 0) { rim = DSTRIP_CLR_ACCENT; chipOn = true; }
       dirty |= DrawStripBtn(an, x, rowY, DSTRIP_CELL, DSTRIP_CELL, face, ink, rim, "", tip);
       dirty |= DrawStripFace(ai + "C", x, rowY, DSTRIP_CELL, DSTRIP_CELL,
                              chipOn ? "::Files\\Icons\\pnl_chip_gold.bmp" : "::Files\\Icons\\pnl_chip.bmp", tip);
       dirty |= DrawStripFace(ai, x, rowY, DSTRIP_CELL, DSTRIP_CELL, DrawStripActRes(a), tip);

   }

   //--- P-DRAW-75 (2026-09-28) — THE BOARD'S PLATE IS A FUNCTION OF ONE FACT, so one
   //--- line decides it and no branch can be the one that forgets. P-DRAW-73 moved
   //--- the purge into each of the paint's three branches: three chances to be wrong,
   //--- and still a second answer to a question the object list holds — family 2 (the
   //--- colour board's own 9-slice, 328 x 468) exists iff a colour board is open. The
   //--- probe is the plate itself, not a flag about it (H-06). Bound: one probe per
   //--- paint, and a delete only when the object is really there.
   bool boardWanted = (DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0);
   if(!boardWanted && ObjectFind(0, DrawStripBoardBgName()) >= 0)
      dirty |= DrawStripSkinPurgeAt(2);

   //--- popover block (ONE at a time).
   int contentW = s_dsW - 2 * DSTRIP_PAD;
    if(DrawStripIsColorSlot(s_dsPicker))
    {
       //--- P-DRAW-64: ONE board, TWO roles — `s_dsPicker` is the colour it edits.
       bool fillBoard = (s_dsPicker == DRAW_SLOT_FILLCLR);
       color hc = DrawStripColorRead(s_dsObj, s_dsPicker);
       // P-DRAW-48: THE BOARD IS ITS OWN CARD — one more 9-slice plate, at its own
       // rect, with the family's baked shadow (= the reference's raised board).
       dirty |= DrawStripBoardPlate();
       // TV parity header: the carry grip + the board's own name + pin + close.
       if(s_dsPHeadY >= 0)
       {
          int hy0 = s_dsBY + s_dsPHeadY;
          int gy = hy0 + (DSTRIP_BOARD_HDR - DSTRIP_CELL) / 2;
          int gx = s_dsBX + DSTRIP_PAD;
          int xx = s_dsBX + s_dsBW - DSTRIP_PAD - DSTRIP_PHEAD_XW;
          int px2 = xx - DSTRIP_BPIN_XW - 2;
          int xy = hy0 + (DSTRIP_BOARD_HDR - DSTRIP_PHEAD_XW) / 2;
          //--- P-UI-133 (2026-09-29) — THE PAGE SEATS ARE PLACED BEFORE THE TEXT,
          //--- because the text has to FIT in front of them. Measured by tools/
          //--- before-after.py's board pair: on a 328px board the kind caption ran to
          //--- x=223 while the "1/2" page label sat at 190..204 — text over text, on
          //--- every colour slot of every merged kind. The seats keep their own
          //--- arithmetic (this variable IS the one they used) and the two trailing
          //--- captions are now fitted to the space left of them.
          int pgx = xx - DSTRIP_BPIN_XW - 2 - 10 - 2*20;
          int hdrFit = pgx - 24;   // the page LABEL's own left edge IS the limit
          string gtip = "Drag this band to move the board";
          dirty |= DrawStripFace(DrawStripPHeadGChipName(), gx, gy, DSTRIP_CELL, DSTRIP_CELL,
                                 "::Files\\Icons\\pnl_chip.bmp", gtip);
          dirty |= DrawStripFace(DrawStripPHeadGIconName(), gx, gy, DSTRIP_CELL, DSTRIP_CELL,
                                 "::Files\\Icons\\bk_grip.bmp", gtip);
          // The join is code 183 set at runtime (a literal `·` is read as a
          // NUMBER and warns on every concatenation) and StringToUpper takes a
          // variable, never a temporary.
          string dot=" . ";
          StringSetCharacter(dot,1,183);
          string kindT = DrawKindName(s_dsKind);
          StringToUpper(kindT);
          //--- P-DRAW-64a, third cut (2026-09-27): THE HEADER NAMES BOTH ROLES.
          //--- «این بوردر و fill کاربر متوجه نمیشه» — a single caption ("FILL · BOX")
          //--- whose tap secretly switches the role is a control that cannot be found,
          //--- so the header is a real segmented pair now: BORDER and FILL both legible,
          //--- the active one in the accent (and bold), each a tap target that SETS its
          //--- role outright — never a toggle to guess at. Kinds with ONE colour role
          //--- keep the single caption. No new layout: three labels ride the same band
          //--- the one caption used, and the prune list takes the two new names.
          if(DrawStripMergedColor(s_dsKind) && DrawStripIsColorSlot(s_dsPicker))
          {
             string bRole = "BORDER", fRole = "FILL";
             bool onB = (s_dsPicker == DRAW_SLOT_COLOR);
             int hx0 = gx + DSTRIP_CELL + 8;
             int hhY = StrapInkY(hy0, DSTRIP_BOARD_HDR, 9);
             dirty |= DrawStripLblAt("PnlDrawS_PHeadB", hx0, hhY, bRole,
                                     onB ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_LABEL,
                                     "Border color — click to edit it", 9, onB);
             int hx1 = hx0 + PnlTextW(bRole, 9) + 12;
             dirty |= DrawStripLblAt("PnlDrawS_PHeadF", hx1, hhY, fRole,
                                     onB ? DSTRIP_CLR_LABEL : DSTRIP_CLR_ACCENT,
                                     "Fill color — click to edit it", 9, !onB);
             int hx2 = hx1 + PnlTextW(fRole, 9) + 12;
              dirty |= DrawStripLblAt("PnlDrawS_PHeadT", hx2, hhY,
                                      PnlFit(dot + " " + kindT, 9, hdrFit - hx2),
                                      DSTRIP_CLR_TITLE, gtip, 9, true);   // P-DRAW-68
          }
          else
          {
             string btl=(fillBoard ? "FILL " : "BORDER ")+dot+" "+kindT;
             StringToUpper(btl);
              dirty |= DrawStripLblIn("PnlDrawS_PHeadT", gx + DSTRIP_CELL + 8, hy0, DSTRIP_BOARD_HDR,
                                      PnlFit(btl, 9, hdrFit - (gx + DSTRIP_CELL + 8)),
                                      DSTRIP_CLR_TITLE, gtip, 9, true);   // P-DRAW-68
          }
           //--- P-DRAW-50: the PAGE SEATS — the only way to the second 64 of the
           //--- table. They sit in the header's own free width, left of the pin, and
           //--- they are the SHARED page: flipping here moves the cards' popup too.
           if(DrawStripIsColorSlot(s_dsPicker))
           {
              int pgy = hy0 + (DSTRIP_BOARD_HDR - 20) / 2;
              for(int k=0;k<2;k++)
              {
                 bool edge = ((k==0 && BioPickPage()==0) || (k==1 && BioPickPage()==BIOPICK_PAGES-1));
                 dirty |= DrawStripBtn("PnlDrawS_Page"+IntegerToString(k), pgx+k*20, pgy, 20, 20,
                                       DrawStripPlateFill(),
                                       edge ? DSTRIP_CLR_LINE : DSTRIP_CLR_LABEL,
                                       edge ? DSTRIP_CLR_LINE : DSTRIP_CLR_LINE,
                                       (k==0) ? "<" : ">",
                                       (k==0) ? "The palette's first 64 colors"
                                             : "The palette's other 64 colors");
              }
              dirty |= DrawStripLblIn("PnlDrawS_PageT", pgx-24, hy0, DSTRIP_BOARD_HDR,
                                      IntegerToString(BioPickPage()+1)+"/"+IntegerToString(BIOPICK_PAGES),
                                      DSTRIP_CLR_LABEL,
                                      "Palette page — 16 families of 8", 7, false);
           }
           // The reference's own pin: DOWN = docked (the board follows the strip),

          // UP = the hand's spot. One compare per press, no state of its own.
          dirty |= DrawStripBtn("PnlDrawS_PHeadP", px2, xy, DSTRIP_BPIN_XW, DSTRIP_BPIN_XW,
                                DrawStripPlateFill(), DSTRIP_CLR_LABEL,
                                s_dsBDock ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_LINE,
                                "", s_dsBDock ? "Docked to the strip — click to leave it where you drag it"
                                             : "Floating — click to dock it to the strip again");
          dirty |= DrawStripFace("PnlDrawS_PHeadPI", px2, xy, DSTRIP_BPIN_XW, DSTRIP_BPIN_XW,
                                 s_dsBDock ? "::Files\\Icons\\gl_pin_gold.bmp"
                                           : "::Files\\Icons\\gl_pin_m.bmp",
                                 "Dock / undock the board");
          dirty |= DrawStripBtn("PnlDrawS_PHeadX", xx, xy, DSTRIP_PHEAD_XW, DSTRIP_PHEAD_XW,
                                DrawStripPlateFill(), DSTRIP_CLR_LABEL, DSTRIP_CLR_LINE,
                                "x", "Close the color picker");
       }
       // TV parity bands: RECENT (the trader's own five) and HEX (an exact typed
       // value). The read-only preview band the reference does not have is gone —
       // the current colour is marked by the RING on its own cell instead.
       if(s_dsPRecY >= 0 && s_dsObj != "")
       {
          int ry = s_dsBY + s_dsPRecY + (DSTRIP_PICK_ROW - DSTRIP_PICK_CELL) / 2;
          dirty |= DrawStripLblIn(DrawStripPRecLabelName(), s_dsBX + DSTRIP_PAD,
                                  s_dsBY + s_dsPRecY, DSTRIP_PICK_ROW,
                                  "RECENT", DSTRIP_CLR_TITLE,
                                  "Your last colors — click to reuse" + DrawStripTipScope(), 8, false);
          for(int i = 0; i < DSTRIP_RECENT_MAX; i++)
          {
             string rn = DrawStripPRecName(i);
             if(i >= s_dsRecentN)
             {
                if(ObjectFind(0, rn) >= 0) { ObjectDelete(0, rn); dirty = true; }
                if(ObjectFind(0, DrawStripPRecGlassName(i)) >= 0)
                { ObjectDelete(0, DrawStripPRecGlassName(i)); dirty = true; }
                continue;
             }
             color rc = s_dsRecent[i];
             bool rcur = (rc == hc);
             int rpx = s_dsBX + DSTRIP_PAD + DSTRIP_PREC_LW + i * (DSTRIP_PICK_CELL + DSTRIP_PICK_GAP);
             string rtip = "Recent " + DrawStripColorHex(rc) + " — click to apply" + DrawStripTipScope();
             dirty |= DrawStripBtn(rn, rpx, ry, DSTRIP_PICK_CELL, DSTRIP_PICK_CELL, rc, DrawStripInkOn(rc),
                                   rcur ? DSTRIP_CLR_ACCENT : BioSwatchBorder(rc, BIO_CLR_CARD), "", rtip);
             dirty |= DrawStripFace(DrawStripPRecGlassName(i), rpx, ry, DSTRIP_PICK_CELL, DSTRIP_PICK_CELL,
                                    rcur ? "::Files\\Icons\\ds_ring32.bmp" : "::Files\\Icons\\ds_cell32.bmp", rtip);
          }
       }
       if(s_dsPHexY >= 0 && s_dsObj != "")
       {
          int hy0 = s_dsBY + s_dsPHexY;
          dirty |= DrawStripLblIn(DrawStripPHexLbName(), s_dsBX + DSTRIP_PAD,
                                  hy0, DSTRIP_PICK_ROW,
                                  "HEX", DSTRIP_CLR_TITLE, "Type #RRGGBB, Enter applies it", 8, false);
          dirty |= DrawStripPopHex(DrawStripHexX(),
                                   hy0 + (DSTRIP_PICK_ROW - DSTRIP_POP_EDIT_H) / 2,
                                   DrawStripHexW(),
                                   s_dsHexFocus ? ""
                                      : DrawStripColorHex(DrawStripColorRead(s_dsObj, s_dsPicker)));
       }
       //--- P-DRAW-48: THE OPACITY BAR — the reference's own row on the cards' track
       //--- metrics (a bed, the filled part, a knob) with the `NN%` readout in its
       //--- own seat. The VALUE is the object's (`[OPnn]` on its description —
       //--- DrawToolbar owns the tag and the blend the chart wears).
       if(s_dsPOpY >= 0 && s_dsObj != "")
       {
          int op  = DrawSlotAlphaGet(s_dsObj, s_dsPicker);
          int oy0 = s_dsBY + s_dsPOpY;
          int oy  = oy0 + (DSTRIP_PICK_ROW - DSTRIP_TRK_H) / 2;
          int otx = DrawStripOpTrackX();
          int otw = DrawStripOpTrackW();
          int okx = otx + (int)MathRound(op / 100.0 * (otw - DSTRIP_KNOB_W));
          string ov = IntegerToString(op) + "%";
          //--- P-DRAW-66: the band is SHARED with the HEX field, so the bar keeps no
          //--- label seat of its own — the `NN%` readout names the value and its
          //--- tooltip names the act. A board left by an older build loses the object.
          if(ObjectFind(0, DrawStripPOpLbName()) >= 0)
          { ObjectDelete(0, DrawStripPOpLbName()); dirty = true; }
          dirty |= DrawStripRect(DrawStripPOpBedName(), otx, oy, otw, DSTRIP_TRK_H,
                                 DSTRIP_CLR_LINE, Z_STRIP_ICON);
          if(okx > otx)
             dirty |= DrawStripRect(DrawStripPOpFillName(), otx, oy, okx - otx, DSTRIP_TRK_H,
                                    DSTRIP_CLR_ACCENT, Z_STRIP_ICON);
          else if(ObjectFind(0, DrawStripPOpFillName()) >= 0)
          { ObjectDelete(0, DrawStripPOpFillName()); dirty = true; }
          dirty |= DrawStripBtn(DrawStripPOpKnobName(), okx,
                                oy0 + (DSTRIP_PICK_ROW - DSTRIP_KNOB_H) / 2,
                                DSTRIP_KNOB_W, DSTRIP_KNOB_H, DSTRIP_CLR_ACCENT,
                                DSTRIP_CLR_ACCENT, DSTRIP_CLR_LINE, "",
                                "Drag to set the opacity");
          dirty |= DrawStripLblIn(DrawStripPOpValName(),
                                  s_dsBX + s_dsBW - DSTRIP_PAD - PnlTextW(ov, 8),
                                  oy0, DSTRIP_PICK_ROW,
                                  ov, DSTRIP_CLR_VALUE,
                                  (fillBoard ? "Fill strength — 50% is the half-filled box"
                                             : "Opacity of the drawing's color") +
                                  " — drag the bar" + DrawStripTipScope(), 8, false);
       }
       for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
         string pn = DrawStripPickName(r);
         if(r >= s_dsPN)
         {
            if(ObjectFind(0, pn) >= 0) { ObjectDelete(0, pn); dirty = true; }
            if(ObjectFind(0, DrawStripPickGlassName(r)) >= 0)
            { ObjectDelete(0, DrawStripPickGlassName(r)); dirty = true; }
            continue;
         }
         color pc = DrawStripPickColor(s_dsPicker, r);
         bool cur = DrawStripPickIsCur(s_dsObj, s_dsKind, s_dsPicker, r);
         int px = s_dsBX + DSTRIP_PAD + (r % BIOPICK_COLS) * (DSTRIP_PICK_CELL + DSTRIP_PICK_GAP);
         int py = s_dsBY + s_dsPY[r] + (DSTRIP_PICK_ROW - DSTRIP_PICK_CELL) / 2;
         string tip = "Color: " + DrawStripColorLabel(pc) + " — click to apply" + DrawStripTipScope();
         //--- P-UI-69b: same floor as the gear grid (the popover body is #171C25,
         //--- the plate #1D222C — the floor's verdict is identical for both).
         dirty |= DrawStripBtn(pn, px, py, DSTRIP_PICK_CELL, DSTRIP_PICK_CELL, pc, DrawStripInkOn(pc),
                               cur ? DSTRIP_CLR_ACCENT : BioSwatchBorder(pc, BIO_CLR_CARD), "", tip);
         //--- P-DRAW-33: every colour surface wears the cards' glass sheen — flat
         //--- button underneath (the click target), glass frame on top. The cell
         //--- the drawing wears now takes the RING bake instead: on a rounded
         //--- face the button's own border is covered, so the selected cell
         //--- would otherwise read as an unselected one.
         dirty |= DrawStripFace(DrawStripPickGlassName(r), px, py,
                                DSTRIP_PICK_CELL, DSTRIP_PICK_CELL,
                                cur ? "::Files\\Icons\\ds_ring32.bmp" : "::Files\\Icons\\ds_cell32.bmp", tip);
      }
   }
   else if(s_dsPicker != DSTRIP_PICK_NONE)
   {
      dirty |= DrawStripPopChromePrune();   // a slot switch skips the close (see it)
      //--- P-DRAW-75: the board's plate goes with it, and the ONE decision above the
      //--- branches (family 2 lives iff a colour board is open) has already asked.
      for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
         string pn = DrawStripPickName(r), pi = DrawStripPickIconName(r),
                pt = DrawStripPickLabelName(r), pc = DrawStripPickChipName(r),
                pr = DrawStripPickRailName(r);
         if(r >= s_dsPN)
         {
            if(ObjectFind(0, pn) >= 0) { ObjectDelete(0, pn); dirty = true; }
            if(ObjectFind(0, pi) >= 0) { ObjectDelete(0, pi); dirty = true; }
            if(ObjectFind(0, pt) >= 0) { ObjectDelete(0, pt); dirty = true; }
            if(ObjectFind(0, pc) >= 0) { ObjectDelete(0, pc); dirty = true; }
            if(ObjectFind(0, pr) >= 0) { ObjectDelete(0, pr); dirty = true; }
            continue;
         }
         int py = s_dsY + s_dsPY[r];
         int px = s_dsX + DSTRIP_PAD;
         bool cur = DrawStripPopRowIsCur(r);
         string res = DrawStripPopRowRes(r);
         string txt = DrawStripPopRowText(r);
         string tip = DrawStripPopRowTip(r);
         bool dimmed = (s_dsPicker == DSTRIP_MORE && s_dsMoreKind[r] == DSTRIP_MK_UNDO && !s_duValid);
         color ink = dimmed ? DSTRIP_CLR_TITLE : DSTRIP_CLR_LABEL;
         if(s_dsPicker == DSTRIP_MORE && s_dsMoreKind[r] == DSTRIP_MK_APPLYALL)
            ink = DSTRIP_CLR_ACCENT;
         color popTone = StrapCellTone(s_dsPY[r], DSTRIP_STRIP_BODY_TOP, DSTRIP_STRIP_GRID_TOP, s_dsH);   // P-DRAW-69
         dirty |= DrawStripBtn(pn, px, py, contentW, DSTRIP_PICK_ROW,
                               popTone, ink, popTone, "", tip);
         dirty |= DrawStripFace(pr, px, py, 2, DSTRIP_PICK_ROW,
                                cur ? "::Files\\Icons\\pnl_rail_gold.bmp" : "", tip);
         if(res != "")
         {
            dirty |= DrawStripFace(pc, px, py + 10, 22, 22,
                                   cur ? "::Files\\Icons\\pnl_chip_gold.bmp" : "::Files\\Icons\\pnl_chip.bmp", tip);
            dirty |= DrawStripFace(pi, px - 2, py + 8, 26, 26, res, tip);
         }
         int labelX = px + (res == "" ? 12 : 32);
         dirty |= DrawStripLblIn(pt, labelX, py, DSTRIP_PICK_ROW,
                                 PnlFit(txt, 9, contentW - (labelX - px) - 12),
                                 ink, tip, 9, true);   // P-DRAW-68: the cards' row label
      }
   }
   else
   {
      //--- P-DRAW-75 (2026-09-28): the board's PLATE is taken by the ONE decision
      //--- above the branches, so this branch carries only the board's own CELLS.
      //--- P-DRAW-73 put the purge here, on a bool that could not see a plate; the
      //--- reported artefact is the empty 42px banded tower under the panel (ten
      //--- bands of family 2 at 328 wide, no content, nothing owning them).
      for(int r = 0; r < DSTRIP_PICK_MAX; r++)
      {
         bool gone = false;
         if(ObjectFind(0, DrawStripPickName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickName(r)); gone = true; }
         if(ObjectFind(0, DrawStripPickIconName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickIconName(r)); gone = true; }
         if(ObjectFind(0, DrawStripPickLabelName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickLabelName(r)); gone = true; }
         if(ObjectFind(0, DrawStripPickChipName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickChipName(r)); gone = true; }
         if(ObjectFind(0, DrawStripPickRailName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickRailName(r)); gone = true; }
         if(ObjectFind(0, DrawStripPickGlassName(r)) >= 0)
         { ObjectDelete(0, DrawStripPickGlassName(r)); gone = true; }
         if(gone) dirty = true;
      }
   }

   //--- P-DRAW-32: the SETTINGS PANEL — its own plate, at its own origin. Placed
   //--- FIRST (plate, head, tabs, rows and the carry all read one origin), then
   //--- painted; a shut panel takes its plate away with its controls.
   if(s_dsGear != 0)
   {
      //--- P-DRAW-73 (2026-09-28): the panel's plate and its content both read the
      //--- LAYOUT (`s_dsGearH` + the item arrays), and only a tap runs one. An open
      //--- panel with no layout would paint its controls onto a bare chart, so the
      //--- state is named once instead of being drawn wrong (F2: the log IS a channel).
      if(s_dsGearH <= 0)
      {
         static bool said = false;
         if(!said)
         {
            said = true;
            Print("[drawstrip] panel open with no layout (gearH=", s_dsGearH,
                  ") — a path changed the content without DrawStripLayout()");
         }
      }
      DrawStripPlaceGear();
      dirty |= DrawStripGearPlate();
      dirty |= DrawStripGearPaint();
   }
   else if(ObjectFind(0, DrawStripGearBgName()) >= 0)
   {
      //--- P-DRAW-75: the gate is the plate itself, not a flag about it (the
      //--- board's own decision above). It is owed nothing when it was never painted,
      //--- so the popover's own path still probes nothing it does not own.
      dirty |= DrawStripGearPurge();
      dirty |= DrawStripGearSkinPurge();
   }

   DrawStripPublishRect();   // P-DRAW-31: the cards' placement reads the plate here
   if(dirty) ChartRedraw();
}

//--- P-DRAW-20 (2026-09-24) — THE FRESH PLACEMENT IS THE DRAWING'S OWN CORNER.
//---
//--- User order: «به صورت پیش فرض استریپ در جای هوشمند ظاهر بشه». The hold that
//--- opens the strip fires ON the drawing, so the old +12/+12 CURSOR offset parked
//--- the plate on top of the very object it serves — and near the right/bottom
//--- edge the clamp then pushed it further onto that object, never off it. The box
//--- strip's own rule (P-BK-27) is the precedent this wears: THE TOOLBAR NEVER
//--- COVERS THE HANDLE IT BELONGS TO. P-DRAW-41 asks it ONE time only: from then
//--- on the plate wears its home and no placement runs.
//---
//--- P-DRAW-41 (2026-09-25) — THE HOME'S OWNERS. One reader pair and one clamp, so
//--- "where does the strip live" and "is it still reachable" each have one answer.
bool DrawStripHomeGet(int &x, int &y)
{
   if(s_dsHomeX < 0 || s_dsHomeY < 0) return false;
   x = s_dsHomeX;
   y = s_dsHomeY;
   return true;
}

void DrawStripHomeSet(const int x, const int y)
{
   if(x < 0 || y < 0) return;
   s_dsHomeX = x;
   s_dsHomeY = y;
}

//--- A shrunk window must never strand the home off-screen (E-05: no dead zone).
//--- While the strip is open this is ALL a zoom or a scroll still owes the plate:
//--- window arithmetic, zero projections, and a paint only if it really moved.
void DrawStripHomeClamp()
{
   if(!s_dsOpen || s_dsHomeX < 0) return;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   int nx = s_dsHomeX, ny = s_dsHomeY;
   if(nx > cw - s_dsW - 4) nx = cw - s_dsW - 4;
   if(ny > ch - s_dsH - 4) ny = ch - s_dsH - 4;
   if(nx < 4) nx = 4;
   if(ny < 4) ny = 4;
   if(nx == s_dsHomeX && ny == s_dsHomeY) return;
   s_dsHomeX = nx; s_dsHomeY = ny;
   if(nx == s_dsX && ny == s_dsY) return;
   s_dsX = nx; s_dsY = ny;
   DrawStripLayout();
   DrawStripPaint();
}
//---
//--- So the fresh spot is measured off the drawing itself, not the hand: its pixel
//--- box (every anchor that projects — 1 for a hline, 2 for a segment/box, 3 for a
//--- channel/fork) answers four candidates — above its top edge, below its bottom
//--- edge, left of it, right of it — all right/edge-aligned so the plate sits where
//--- the eye expects it, and the FIRST candidate that needs no clamping AND does
//--- not overlap the drawing wins. A drawing too big for the window has no such
//--- spot: then the reading order stands (above, else below) and the result is
//--- clamped, never left inside the drawing by accident. And a drawing whose
//--- anchors do not project at all (off-window) falls back to the PRE-P-DRAW-20
//--- spot: a placement that cannot measure the object must not invent one.
//--- The user's own carry rewrites the HOME (`DrawStripHomeSet`), and the home wins
//--- every open after it (P-DRAW-41).
#define DSTRIP_PLACE_GAP 14    // clear air between the drawing's pixel box and the plate
void DrawStripPlaceFresh(const string name, const int mx, const int my, int &x, int &y)
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   bool have = DrawStripDrawingBox(name, x1, y1, x2, y2);   // P-DRAW-40: one owner
   if(!have)
   {
      x = mx + 12; y = my + 12;   // the pre-P-DRAW-20 spot (unmeasurable drawing)
      int cm0 = 4 + DSTRIP_SKIN_M;   // P-DRAW-29: the skin stands past the content
      if(x < cm0) x = cm0;
      if(y < cm0) y = cm0;
      if(x > cw - s_dsW - cm0) x = cw - s_dsW - cm0;
      if(y > ch - s_dsH - cm0) y = ch - s_dsH - cm0;
      return;
   }
   int cx[4], cy[4];
   cx[0] = x2 - s_dsW;                    cy[0] = y1 - s_dsH - DSTRIP_PLACE_GAP;   // above
   cx[1] = x2 - s_dsW;                    cy[1] = y2 + DSTRIP_PLACE_GAP;           // below (P-BK-27)
   cx[2] = x1 - s_dsW - DSTRIP_PLACE_GAP; cy[2] = y1;                              // left of it
   cx[3] = x2 + DSTRIP_PLACE_GAP;         cy[3] = y1;                              // right of it
   // P-DRAW-31: and the OPEN CARD is a third thing every spot must clear — the user's
   // rule is that two surfaces never sit on one pixel («جایی که روی هم نیافتن»). The
   // card publishes its own rect (g_UIPanelR*, P-UI-98r) for exactly this kind of
   // reader; when no card is open the terms are inert. Priority: a spot that clears
   // BOTH beats one that only clears the drawing, which beats the clamped fallback.
   bool card = (g_UIPanelRX >= 0 && g_UIPanelRW > 0 && g_UIPanelRH > 0);
   int fb = -1;
   for(int c = 0; c < 4; c++)
   {
      int px = cx[c], py = cy[c];
      int cm = 4 + DSTRIP_SKIN_M;   // P-DRAW-29: keep the skin, not just the content
      bool onWin  = (px >= cm && py >= cm && px <= cw - s_dsW - cm && py <= ch - s_dsH - cm);
      bool misses = (px + s_dsW <= x1 || px >= x2 || py + s_dsH <= y1 || py >= y2);
      bool onCard = card && !(px + s_dsW <= g_UIPanelRX - DSTRIP_PLACE_GAP ||
                              px >= g_UIPanelRX + g_UIPanelRW + DSTRIP_PLACE_GAP ||
                              py + s_dsH <= g_UIPanelRY - DSTRIP_PLACE_GAP ||
                              py >= g_UIPanelRY + g_UIPanelRH + DSTRIP_PLACE_GAP);
      if(onWin && misses && !onCard) { x = px; y = py; return; }
      if(onWin && !onCard && fb < 0) fb = c;   // clears the card, not the drawing
   }
   if(fb >= 0) { x = cx[fb]; y = cy[fb]; return; }
   x = cx[0]; y = cy[0];   // no clean spot: reading order (above, else below), clamped
   if(y < 4 + DSTRIP_SKIN_M)
   {
      y = cy[1];
      if(y > ch - s_dsH - 4 - DSTRIP_SKIN_M) y = ch - s_dsH - 4 - DSTRIP_SKIN_M;
   }
   if(x < 4 + DSTRIP_SKIN_M) x = 4 + DSTRIP_SKIN_M;
   if(y < 4 + DSTRIP_SKIN_M) y = 4 + DSTRIP_SKIN_M;
   if(x > cw - s_dsW - 4 - DSTRIP_SKIN_M) x = cw - s_dsW - 4 - DSTRIP_SKIN_M;
   if(y > ch - s_dsH - 4 - DSTRIP_SKIN_M) y = ch - s_dsH - 4 - DSTRIP_SKIN_M;
}

//--- OPEN AT CURSOR (P-DRAW-13, preview parity): the trigger's press point answers
//--- where, clamped like the preview's openStripAt (+12, +12, 4px margins).
//--- P-DRAW-20: the CURSOR only answers when the drawing itself cannot be measured
//--- (see `DrawStripPlaceFresh`). P-DRAW-41: and only on the ONE open that has no
//--- home yet — after that the plate wears the home and no placer runs at all.
bool DrawStripOpenAt(const string name, const int mx, const int my)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;
   // P-DRAW-41 (2026-09-25): the SAME object again is a re-state, not a move — the
   // plate wears its home and nothing is re-measured. This is what P-DRAW-37's ride
   // shrank to once the home existed: the rebuild it replaced deleted and re-created
   // the whole family (~40 objects) at the drawing's own drag cadence.
   if(s_dsOpen && s_dsObj == name)
   {
      if(s_dsKind == DK_RECT) BoxMidSync(name);   // P-DRAW-21: the mid rides this event
      return true;
   }
   int keepPicker = s_dsPicker, keepGear = s_dsGear;
   bool keepPin = s_dsPinned;
   // P-DRAW-41: MEASURE BEFORE THE CLOSE — an object that cannot project must not
   // leave the surface torn down (J-02: nothing may advertise a state that did not
   // happen). The ride above keeps what was already open; this is the fresh path.
   int ax = 0, ay = 0;
   if(!DrawAnchorXY(name, 0, ax, ay))
   { Print("[drawstrip] close: anchor projection failed on \"", name, "\""); return false; }
   DrawStripClose();
   // P-DRAW-09b: THE GROUP IS TAKEN HERE, ONCE, and AFTER the close (a close
   // drops the group, because a group belongs to an open strip). The terminal's
   // own selection is the user's statement of "these", and an open is the only
   // moment it can legitimately change — a live read would walk the object list
   // on a stream, and a group that shifted mid-edit is worse than a stale one.
   DrawSelSnapshot(name);
   //--- P-DRAW-74: THE TERMINAL'S OWN DIALOG IS A SECOND WRITER. MT4's properties
   //--- window stores width and style straight onto the object and never passes
   //--- `DrawSlotWrite`, so an impossible pair (3 px + Dash) can be born there. One
   //--- ask on the open - the ONE place every served drawing passes - and the pair
   //--- is legal before the panel ever prints a caption for it.
   DrawStylePairCoerce(name);
   s_dsKind = k;
   s_dsObj = name;
   s_dsOpen = true;
   s_dsPicker = DSTRIP_PICK_NONE;
   if((keepPicker != DSTRIP_PICK_NONE) &&
      (keepPicker == DSTRIP_MORE || DrawStripHasPicker(keepPicker)))
      s_dsPicker = keepPicker;
   s_dsGear = 0;
   s_dsGearPressSpent = false;   // P-DRAW-84: a spent flag outlives its panel
   if(keepGear != 0) s_dsGear = keepGear;
   else
   {
      // fresh open: compact quick row only, no gear panel.
      s_dsTplNameArmed = false;
   }
   s_dsPinned = keepPin;
   s_dsN = DrawStripQuickCount(k);
   DrawStripLayout();
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   // P-DRAW-41 (2026-09-25): the HOME is the placement, and the first open on a
   // chart is the only one without one — it measures the drawing through the
   // P-DRAW-20 placer once (the drawing's own corner, never the cursor under the
   // hand) and that answer becomes the home for every open after it.
   if(!DrawStripHomeGet(s_dsX, s_dsY)) DrawStripPlaceFresh(name, mx, my, s_dsX, s_dsY);
   if(s_dsX < 4) s_dsX = 4;
   if(s_dsY < 4) s_dsY = 4;
   if(s_dsX > cw - s_dsW - 4) s_dsX = cw - s_dsW - 4;
   if(s_dsY > ch - s_dsH - 4) s_dsY = ch - s_dsH - 4;
   DrawStripHomeSet(s_dsX, s_dsY);   // P-DRAW-41: what was placed (or clamped) IS the home
   if(k == DK_RECT) BoxMidSync(name);   // P-DRAW-21: the drag/zoom ride moves the mid too
   DrawStripPaint();
   return true;
}
bool DrawStripOpen(const string name)
{
   // P-DRAW-20: no cursor in hand is the NORMAL case — the measured spot is what a
   // fresh open wears and `mx` only answers when the drawing cannot be measured.
   // P-DRAW-41: both only matter for the first open; a home answers every other.
   return DrawStripOpenAt(name, -1, -1);
}

//--- P-DRAW-09b: ONE write for a value, delivered to the WHOLE group. The
//--- learning half lives in `DrawSlotWrite` (P-DRAW-01c), so every member and the
//--- kind's memory move together — and the group is pruned first, because a
//--- member another gesture deleted is not a name to write. Every caller pushes
//--- undo FIRST (single-step looks).
int DrawStripWriteValue(const int slot, const double v)
{
   //--- P-DRAW-64a: the box's own 50 % needs no "show the interior" rule — it moves
   //--- the DRAWING's far anchor, so it is visible with the fill off, on, or never
   //--- (the user's own correction: «۵۰ درصد باکس فقط میخوام، fill بهکارم نمیاد»).
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
   //--- P-DRAW-64: undo restores the interior too — a 50% fill the user did not
   //--- want must come back off in ONE step like every other look change.
   s_duFillClr[i] = (color)(int)DrawSlotRead(nm, DRAW_SLOT_FILLCLR);
   s_duFillOp[i]  = DrawSlotAlphaGet(nm, DRAW_SLOT_FILLCLR);
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
      if(s_duCopy == s_dsObj)
      { Print("[drawstrip] close: undo popped the strip's own copy"); DrawStripClose(); ChartRedraw(); s_duValid = false; return true; }
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
      if(DrawSlotAvailable(DrawKindOf(nm), DRAW_SLOT_FILLCLR))
      {
         DrawSlotWrite(nm, DRAW_SLOT_FILLCLR, (double)(int)s_duFillClr[i]);
         DrawSlotOpacitySet(nm, s_duFillOp[i], DRAW_SLOT_FILLCLR);
      }
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
   //--- P-DRAW-76: `row` IS the slot id (both list builders pass one), so the guard is the slot
   //--- range plus "is it filled" — never the count, which a cleared slot turns into a lie.
   if(row < 0 || row >= DRAW_PRESET_MAX || DrawPresetName(k, row) == "") return false;
   //--- P-DRAW-76: SHIFT turns the same click into a DELETE of the user's own template
   //--- (`UIMagnetModifierDown` is the project's ONE Shift reader, P-BK-66). A built-in refuses,
   //--- and its tooltip says so instead of pretending the click did something.
   if(UIMagnetModifierDown())
   {
      if(DrawPresetIsBuiltin(row) || !DrawPresetClear(k, row)) return false;
      s_dsTpl[k] = -1;   // nothing is applied any more (no row can match -1)
      DrawStripPaint();
      ChartRedraw();
      return true;
   }
   DrawStripUndoPush();
   DrawSelPrune();
   int gn = DrawSelCount();
   if(gn > 0) { for(int j = 0; j < gn; j++) DrawPresetApply(DrawSelAt(j), row); }
   else DrawPresetApply(s_dsObj, row);
   //--- P-DRAW-64a: a preset re-inks the border, so a box wearing its level gets the
   //--- new blend at once — not on the pump's next pass. One guarded call per member.
   BoxMidSyncGroup();
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
      //--- P-DRAW-64a: the level and the travelling edge are ARRANGEMENTS, not looks —
      //--- "learn the look" must not touch them, and same-value writes on them would
      //--- cost two description reads for a guaranteed no-op.
      if(s == DRAW_SLOT_BOXHALF || s == DRAW_SLOT_EXTEND) continue;
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
   if(DrawStripIsColorSlot(slot))
   {
      color c = DrawStripPickColor(slot, row);
      if(c == clrNONE) return false;
      DrawStripRecentPush(c);
      DrawStripUndoPush();
      if(slot == DRAW_SLOT_FILLCLR) DrawStripFillShowGroup();   // P-DRAW-64: a colour is a fill
      DrawStripWriteValue(slot, (double)(int)c);
      if(slot == DRAW_SLOT_COLOR) BoxMidSyncGroup();   // P-DRAW-64a: the level wears the border
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
   // P-DRAW-23: a copy starts CLEAN. The description carries the box extras
   // markers, and inheriting them would arm mid + extend on a box the user
   // never asked for (a duplicate that runs away on the next bar).
   if(DrawKindOf(nm) == DK_RECT) BoxMarkWrite(nm, false, BOXEXT_OFF, 0);
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
//--- P-DRAW-64a: `tap` names the OBJECT the terminal reported, because the merged
//--- colour seat carries two roles and the hand's own landing decides which one:
//--- the centred swatch and its skin are the INTERIOR's, the cell's button and its
//--- 32px skin the BORDER's.
bool DrawStripTap(const int idx, const string tap)
{
   if(!s_dsOpen || s_dsObj == "" || idx < 0 || idx >= DSTRIP_MAX_SLOTS) return false;
   if(idx >= s_dsN) return false;
   EDrawKind k = s_dsKind;
   if(k == DK_NONE) { DrawStripClose(); return true; }
   int slot = DrawStripQuickSlotAt(k, idx);
   if(slot < 0) return true;
   if(slot == DRAW_SLOT_FILLCLR)
   {
      string seat = DrawStripIconName(idx);
      if(tap != seat + "S" && tap != seat + "C2") slot = DRAW_SLOT_COLOR;
   }
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
      double tv = (DrawSlotRead(s_dsObj, slot) > 0.5) ? 0.0 : 1.0;
      DrawStripWriteValue(slot, tv);
      // P-DRAW-09b: locking is the one tap that can end the group's usefulness
      // (a locked member cannot be grabbed again by accident), so the strip
      // loses nothing here — it stays, and one more tap frees it.
      DrawStripPaint();
      //--- P-DRAW-64a: the WHOLE group, not just the held box — a BACK flip moves every
      //--- member's layer, and every member wearing its level needs the new one. One
      //--- description read per member per tap (a tap is not a stream), writes only
      //--- where something really changed.
      BoxMidSyncGroup();   // P-DRAW-21: a fill/lock/back flip restyles the mid
      //--- P-DRAW-64c: ...and a tap that SWITCHED THE TRAVEL ON takes the first step
      //--- itself, so the edge moves in this frame instead of on the next bar.
      if(slot == DRAW_SLOT_EXTEND && tv > 0.5) BoxExtendStepGroup();
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
       else s_dsGear = DSTRIP_GEAR_PAINT;   // P-DRAW-65: the colours open first
       //--- P-DRAW-86 (2026-09-29): THE OPEN SWEEPS FIRST. The close-purge kills
       //--- every PnlDrawS_G* — but only if the close ran. A terminal restart, a
       //--- crash, or a build that predates the purge leaves same-prefix objects
       //--- on the chart, and the new paint repaints same-name ones but never
       //--- deletes a stale bed (the blue GTrack that survived three re-adds).
       //--- One bounded pass on open, never on paint.
       DrawStripGearObjectsPurge();
       DrawStripLayout();
       DrawStripPaint();
       DrawStripGearTabCensus();   // P-DRAW-87: the tab band names its objects
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
   // P-DRAW-21: a box delete takes its mid child (else an orphan trend survives).
   //--- P-DRAW-64: and its interior. A child MT4 never cascades: leaving it behind
   //--- would be a filled shape with no drawing around it.
   if(n > 0)
   {
      for(int j = 0; j < n; j++)
      {
         if(DrawIsHRay(DrawSelAt(j))) { HRayDelete(DrawSelAt(j), "strip bin"); continue; }   // P-HR-04: dot goes with the line
         BoxMidDrop(DrawSelAt(j)); FillChildDrop(DrawSelAt(j)); ObjectDelete(0, DrawSelAt(j));
      }
   }
   else if(s_dsObj != "")
   {
      if(DrawIsHRay(s_dsObj)) HRayDelete(s_dsObj, "strip bin");   // P-HR-04
      else { BoxMidDrop(s_dsObj); FillChildDrop(s_dsObj); ObjectDelete(0, s_dsObj); }
   }
   DrawStripClose();
   ChartRedraw();
}
//--- TV parity board: a RECENT cell applies the colour it shows. Same three
//--- steps as a grid cell (`DrawStripPickApply`'s colour branch, which cannot
//--- reach these rows any more: they are their own band now) and the board STAYS
//--- (P-DRAW-48 multi-stay: the opacity bar beside it is the user's next act).
bool DrawStripPickTapRecent(const int i)
{
   if(!s_dsOpen || s_dsObj == "" || !DrawStripIsColorSlot(s_dsPicker)) return false;
   if(i < 0 || i >= s_dsRecentN) return false;
   //--- P-DRAW-64: the scrub's release witness (see `DrawStripPalRelease`).
   if(s_dsPalDoneMs != 0 && GetTickCount() - s_dsPalDoneMs < DSTRIP_PAL_TAIL_MS)
      return DrawStripClickFamily();
   if(s_dsPalGrab) { s_dsPalDoneMs = GetTickCount(); DrawStripPalHighlightEnd(); }
   DrawStripColorHoverClear();
   color c = s_dsRecent[i];
   DrawStripRecentPush(c);   // reusing one moves it back to the front
   DrawStripUndoPush();
   //--- P-DRAW-64: the recents are the board's own colours too — a recent tapped on
   //--- the FILL board is a fill, exactly like the grid, the hex and the bar. Was the
   //--- one path that forgot it: a tap that changed no pixel read as "nothing happened".
   if(DrawStripIsColorSlot(s_dsPicker) && s_dsPicker == DRAW_SLOT_FILLCLR)
      DrawStripFillShowGroup();
   if(DrawStripIsColorSlot(s_dsPicker) && s_dsPicker == DRAW_SLOT_FILLCLR)
      DrawStripFillShowGroup();
   DrawStripWriteValue(s_dsPicker, (double)(int)c);
   if(s_dsPicker == DRAW_SLOT_COLOR) BoxMidSyncGroup();   // P-DRAW-64a: the level wears the border
   DrawStripPaint();   // P-DRAW-48 multi-stay: the board waits for ✕ / Esc / its own cell
   return true;
}
//--- P-DRAW-11 — A PICK APPLIES AND SHUTS (levels, and the colour board since
//--- P-DRAW-48: multi-stay). The caller passes the popover row; the row is
//--- validated against the open popover's own count.
bool DrawStripPickTap(const int row)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(s_dsPicker == DSTRIP_PICK_NONE) return false;
   //--- P-DRAW-64: the scrub's release witness, asked FIRST — whichever channel gets
   //--- here first applies; the second only clears the highlight.
   if(s_dsPalDoneMs != 0 && GetTickCount() - s_dsPalDoneMs < DSTRIP_PAL_TAIL_MS)
      return DrawStripClickFamily();
   if(s_dsPalGrab) { s_dsPalDoneMs = GetTickCount(); DrawStripPalHighlightEnd(); }
   if(DrawStripIsColorSlot(s_dsPicker)) DrawStripColorHoverClear();
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
   //--- P-DRAW-48 — THE COLOUR BOARD STAYS. User order: «روی رنگ کلیک میکنم بسته
   //--- میشه نمیزاره شفافیت تنظیم بکنم» — the board carries the opacity bar, so a
   //--- pick that shuts it takes the bar away exactly when the next act is tuning
   //--- it. The value applies; ✕, Esc or the strip's colour cell close the board.
   if(DrawStripIsColorSlot(s_dsPicker)) { DrawStripPaint(); return true; }
   DrawStripClosePicker();
   DrawStripLayout();
   DrawStripPaint();
   return true;
}
//--- P-DRAW-64 — THE 50% FILL's write: the group fan-out, undoable, through the
//--- one owner of the FILL slot and the one owner of the tone (`DrawStripFill50On`
//--- above). It lives here because the undo push and the group are defined here.
bool DrawStripFill50Apply()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   if(!DrawSlotAvailable(s_dsKind, DRAW_SLOT_FILLCLR)) return false;
   DrawStripUndoPush();
   DrawSelPrune();
   int n = DrawSelCount();
   if(n <= 0) { DrawStripFill50On(s_dsObj); return true; }
   for(int i = 0; i < n; i++) DrawStripFill50On(DrawSelAt(i));
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
      // P-DRAW-25: the more-menu save arms the same name edit (one seat, in
      // the Template tab) instead of an anonymous "My N".
      s_dsTplNameArmed = true;
      DrawStripClosePicker();
      s_dsGear = DSTRIP_GEAR_TPL;
      if(s_dsKind > DK_NONE && s_dsKind < DK_COUNT) s_dsGearMem[s_dsKind] = s_dsGear;
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_DUPE) return DrawStripDuplicate();
   if(kind == DSTRIP_MK_BOX50)
   {
      bool mid = false; int ext = BOXEXT_OFF, n = 0;
      BoxMarkRead(s_dsObj, mid, ext, n);
      BoxMarkWrite(s_dsObj, !mid, ext, n);
      BoxMidSync(s_dsObj);
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_BOXEXT)
   {
      BoxExtCycle(s_dsObj);
      //--- P-DRAW-64c: the cycle may have armed TOUCH/END/NBARS — the first step is
      //--- still the tap's, so the edge moves in this frame even when the next bar is
      //--- an hour away. A cycle that landed on OFF is a no-op here by construction.
      BoxExtendStep(s_dsObj);
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_FILL50)
   {
      DrawStripFill50Apply();
      DrawStripPaint();
      return true;   // the row's own state changed: the popover stays where it is
   }
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
   DrawStripColorHoverClear();
   DrawStripPickApply(s_dsGGSlot[g], s_dsGGArg[g]);   // P-DRAW-44: chips only
   DrawStripPaint();
   BoxMidSyncServed();   // P-DRAW-21: a grid restyle restyles the mid
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
      double tv = (DrawSlotRead(s_dsObj, arg) > 0.5) ? 0.0 : 1.0;
      DrawStripWriteValue(arg, tv);
      DrawStripPaint();
      BoxMidSyncServed();   // P-DRAW-21: a gear toggle restyles the mid
      //--- P-DRAW-64c: the gear's switch takes the first travel step too — same frame,
      //--- same rule as the quick cell above.
      if(arg == DRAW_SLOT_EXTEND && tv > 0.5) BoxExtendStepGroup();
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
      // P-DRAW-25: save ARMS the name edit («نام تمپلت‌ها رو خودمون بتونیم
      // بذاریم») — the file is still written once, on Enter (P-DRAW-08b).
      s_dsTplNameArmed = true;
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
//--- gear foot: All / Copy. P-DRAW-78: `Del` is retired from the panel — the
//--- strip's own command group already carries a trash cell, so this was a
//--- second, unconfirmed way to destroy the drawing. The head's X is the close.
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
   return false;
}
//--- gear tab switch (shuts the popover; one panel at a time).
bool DrawStripGearTabTap(const int t)
{
   DrawStripColorHoverClear();
   if(!s_dsOpen) return false;
   if(t < 0 || t >= s_dsGearTab[0]) return false;
   DrawStripClosePicker();
   int tab = s_dsGearTab[t + 1];
   if(s_dsGear == tab) DrawStripGearClose();
   else s_dsGear = tab;
   // P-DRAW-26: the kind remembers its tab (a shut panel remembers shut).
   if(s_dsKind > DK_NONE && s_dsKind < DK_COUNT) s_dsGearMem[s_dsKind] = s_dsGear;
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
   }    if(e == 4)
   {
      //--- P-DRAW-64: the FILL field — the interior's own colour, typed exactly.
      color fc;
      if(!DrawStripHexToColor(txt, fc)) return true;
      DrawStripRecentPush(fc);
      DrawStripUndoPush();
      DrawStripFillShowGroup();   // P-DRAW-64: a colour is a fill
      DrawStripWriteValue(DRAW_SLOT_FILLCLR, (double)(int)fc);
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
   // P-DRAW-25: the armed save commits under the typed name (empty keeps the
   // "My N" fallback inside DrawPresetCapture). The file write is the commit.
   if(e == 3 && s_dsGear == DSTRIP_GEAR_TPL && s_dsTplNameArmed)
   {
      string t = txt;
      StringTrimLeft(t); StringTrimRight(t);
      DrawPresetCaptureAndSave(s_dsObj, t);
      s_dsTplNameArmed = false;
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   return true;
}
//--- TV parity board: the HEX field's commit (Enter). The parse and the write are
//--- the gear's own (`DrawStripHexToColor` + the one write path) — an invalid
//--- string keeps the typed text for another try, like every other edit here.
bool DrawStripPopHexEnd()
{
   if(!s_dsOpen || s_dsObj == "") return false;
   string nm = DrawStripPHexEdName();
   if(ObjectFind(0, nm) < 0) return false;
   color c;
   if(!DrawStripHexToColor(ObjectGetString(0, nm, OBJPROP_TEXT), c)) return true;
   DrawStripRecentPush(c);
   DrawStripUndoPush();
   //--- P-DRAW-64: the field belongs to the BOARD it sits on, so it writes the
   //--- board's own role — typing a hex while the FILL board is open is a fill.
   int hslot = DrawStripIsColorSlot(s_dsPicker) ? s_dsPicker : DRAW_SLOT_COLOR;
   if(hslot == DRAW_SLOT_FILLCLR) DrawStripFillShowGroup();   // P-DRAW-64: a colour is a fill
   DrawStripWriteValue(hslot, (double)(int)c);
   if(hslot == DRAW_SLOT_COLOR) BoxMidSyncGroup();   // P-DRAW-64a: the level wears the border
   s_dsHexFocus = false;   // P-DRAW-48: the field is the colour's face again
   DrawStripPaint();
   return true;
}
//--- P-DRAW-13: the grip carry. Screen objects only (SELECTABLE=false), so the
//--- terminal never drags the plate for us and P-LM-11's race cannot happen — but
//--- the view lock IS needed now (P-UI-113d): the chart BEHIND the plate pans on
//--- a left drag, which is what made carrying the strip hard. Stale grabs (a
//--- motionless release emits no MOUSE_MOVE, P-LM-13) die on the next CLICK.
//--- P-DRAW-31 (2026-09-24) — THE PLATE IS A HANDLE, like a card's own skin. User
//--- order: «همه پنل ها درگ بشن راحت». The cards are carried by a press ANYWHERE on
//--- their chrome (`PnlSkinHit`); the strip answered only its 32px grip cell, so a
//--- hand that grabbed the plate by its title got nothing and the gesture fell
//--- through to the chart. The handle is the whole top row that carries no control —
//--- the grip cell and the BADGE beside it — plus the gear panel's own header bar
//--- while it is open, stopping `26 + 2 * pad` short of the close button's corner.
bool DrawStripGearGripAt(const int mx, const int my)
{
   if(!s_dsOpen || s_dsGear == 0 || s_dsGearHeadY < 0) return false;
   if(s_dsGearW0 <= 0 || s_dsGearH <= 0) return false;
   int hx = DrawStripGearX();
   if(my >= s_dsGEY + s_dsGearHeadY &&
      my <= s_dsGEY + s_dsGearHeadY + DSTRIP_GEAR_HEAD_H &&
      // P-DRAW-36: the handle spans the head's own width (s_dsGearW0) minus the
      // close button's corner — the same corner rule, measured off the plate.
      mx >= hx && mx <= hx + s_dsGearW0 - DSTRIP_GEAR_PAD - 26 - DSTRIP_GEAR_PAD) return true;
   return false;
}
//--- WHICH surface is under this press? 0 = neither · 1 = the strip's plate ·
//--- 2 = the settings panel. ONE reader (the carry), so the two gestures can never
//--- both own one press: the panel's header is asked FIRST, because a panel is
//--- never drawn on top of the strip's own row (`DrawStripPlaceGear` keeps them apart).
int DrawStripGripWhich(const int mx, const int my)
{
   if(!s_dsOpen) return 0;
   if(DrawStripGearGripAt(mx, my)) return 2;
   int rowY = s_dsY + DSTRIP_PAD;
   //--- P-DRAW-66: the identity group IS one handle — grip, its air and the name,
   //--- with no dead pixel between them (the old pair left the 4px gap ownerless).
   if(my >= rowY && my <= rowY + DSTRIP_CELL &&
      mx >= s_dsX + DSTRIP_PAD && mx <= s_dsX + s_dsBadgeX + s_dsBadgeW) return 1;
    // P-DRAW-48: the BOARD's own header carries the BOARD (its two seats — pin
    // and close — excluded). It is asked FIRST: the board can sit anywhere,
    // including over the strip, and a press on ITS header is never the strip's.
    if(DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0 && s_dsPHeadY >= 0)
    {
       int hy0 = s_dsBY + s_dsPHeadY, hy1 = hy0 + DSTRIP_BOARD_HDR;
       int xx0 = s_dsBX + s_dsBW - DSTRIP_PAD - 2 * DSTRIP_PHEAD_XW - 2 - 2;
       if(my >= hy0 && my <= hy1 && mx >= s_dsBX && mx <= s_dsBX + s_dsBW && mx < xx0) return 3;
    }
    return 0;
}
//--- DrawStripGripRelease lives with the carry's STATE (the file's state block):
//--- it owns the view lock's release, and `DrawStripClose` must be able to call it.
//--- P-DRAW-64 — THE SCRUB'S RELEASE. Either witness applies and marks the tail;
//--- the other one inside the window only clears the highlight, because ONE
//--- physical release arrives on more than one channel (P-UI-113c's own lesson) and
//--- two applications would be two undo steps for one gesture. A release off the
//--- grid is a CANCEL: the pixels go back to what the tags say.
bool DrawStripPalRelease(const int mx, const int my)
{
   bool fresh = (s_dsPalDoneMs != 0 && GetTickCount() - s_dsPalDoneMs < DSTRIP_PAL_TAIL_MS);
   DrawStripPalHighlightEnd();
   if(fresh) return true;   // the click channel already applied it
   int cell = -1;
   if(!DrawStripPalHit(mx, my, cell))
   {
      DrawStripPalTo(-1);   // off the palette: cancel
      s_dsPalDoneMs = GetTickCount();
      return true;
   }
   if(cell >= DSTRIP_HOVER_REC_BASE) DrawStripPickTapRecent(cell - DSTRIP_HOVER_REC_BASE);
   else DrawStripPickApply(s_dsPicker, cell - DSTRIP_HOVER_POP_BASE);
   s_dsPalDoneMs = GetTickCount();
   return true;
}

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
void DrawStripHoldForget() { s_dsHoldObj = ""; }
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
   if(now - s_dsHoldMs > DSTRIP_HOLD_TTL) { DrawStripHoldClear(); return; }
   if(s_dsHoldObj == "" || s_dsOpen) return;
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
            if(s_dsGear != 0 && DrawStripGearHit(tmx, tmy))
            {
               s_dsPressTracked = false;        // a control acted: not a carry
               DrawStripPressCycleClear();
               DrawStripOpenerDisarm();
               DrawStripHoldSelectionDisarm();
               s_dsGearPressSpent = true;       // the release knows a control had it
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
     if(s_dsGearPressSpent)
     {
        s_dsGearPressSpent = false;
        return DrawStripClickFamily();
     }
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
          sparam == DrawStripGearTrackName() ||
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
      // gear tabs, grid cells, rows, foot. Edits take focus for typing.
      //--- P-DRAW-83 (2026-09-29) — THE BOUND IS THE ARRAY'S OWN. `t < 4` was written
      //--- by hand against `DSTRIP_GEAR_TAB_MAX` (5): a kind that shows five tabs
      //--- (fibo/level, text, arrow — LEVELS/MARK inserts one before the pair) draws
      //--- five and could only ever answer four, so the LAST tab — "Row", the tab
      //--- that carries the quick row — stood there dead on exactly those kinds. The
      //--- arrays below were widened from [4] to [DSTRIP_GEAR_TAB_MAX] for the same
      //--- reason; the router was missed.
      //--- The selected tab's own UNDERLINE is the same tab: it is drawn over that
      //--- tab's bottom 2px and its name matched `DrawStripIsBg` as a PLATE, so a
      //--- press on it was read as the plate's dead space and the tab under it never
      //--- answered. Asked here as the tab it belongs to.
      for(int t = 0; t < DSTRIP_GEAR_TAB_MAX; t++)
      {
         bool tabName = (sparam == DrawStripGearTabName(t));
         bool tabLine = (sparam == DrawStripGearTabLineName() &&
                         t < s_dsGearTab[0] && s_dsGearTab[t + 1] == s_dsGear);
         if(tabName || tabLine) { DrawStripGearTabTap(t); return DrawStripClickFamily(); }
      }
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
       DrawStripGripRelease();   // motionless releases emit no MOVE (P-LM-13 net)
       int rcx = (int)lparam, rcy = (int)dparam;
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

#endif // DRAW_STRIP_MQH
