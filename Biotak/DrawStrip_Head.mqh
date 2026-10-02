// DrawStrip_Head.mqh - DrawStrip split 2026-09-29: exact lines 15-677 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_HEAD_MQH
#define DRAW_STRIP_HEAD_MQH

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
//--- P-UI-131: the BACK seat's OFF twin. Declared beside its ON face so the strip's
//--- one control wears ONE shape in two inks (a #resource a painter names without a
//--- declaration is a SILENT no-op at paint time — tools/check-resources.js).
#resource "\\Files\\Icons\\bk_back_off.bmp"
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
#define DSTRIP_GLIST_MAX 24    // list rows in one gear block — P-DRAW-117: the
                               // GROUP HEADERS ride the same array as the open
                               // group's rows, so a fibo's 14 levels + both
                               // management rows + five headers (21) must fit
//--- P-DRAW-116 (2026-10-01) — THE PANEL'S NUMBERS ARE THE CARDS' NUMBERS. These
//--- five were the panel's own literals, each equal to the card's own by hand:
//--- 312 / 16 / 56 / 42 / 48 = PNL_WEL / PNL_PAD_X / PNL_HEAD_H / PNL_ROW_H /
//--- PNL_FOOT_H. They are now ALIASES of it — same value today (so not one pixel of
//--- any surface moves), and no longer two tables that can part company the first time
//--- either side is retuned. The table lives in `CardMetrics.mqh`, which the entry
//--- includes ABOVE this file; that is the only reason a `PNL_*` name can be read here
//--- at all (DrawStrip is include 99, BiotakPanels 118).
//--- DEPENDENTS, named as the Touch rule asks: `DSTRIP_GEAR_W` 10 reads / 5 files ·
//--- `DSTRIP_GEAR_PAD` 17/5 · `DSTRIP_GEAR_HEAD_H` 11/6 · `DSTRIP_GEAR_ROW_H` 27/6 ·
//--- `DSTRIP_GEAR_FOOT_H` 4/3 · `DSTRIP_GEAR_LBL_PT` 4/3 · `DSTRIP_SKIN_M` 35/6 —
//--- every one of them keeps its name and its value; only the number's owner changed.
#define DSTRIP_GEAR_W   PNL_WEL
#define DSTRIP_GEAR_PAD  PNL_PAD_X
#define DSTRIP_GEAR_HEAD_H PNL_HEAD_H
#define DSTRIP_GEAR_ROW_H  PNL_ROW_H
#define DSTRIP_GEAR_TB_H   7   // the head's own top bar, at the head's top edge
#define DSTRIP_GEAR_HR_H   5   // ...and the hair that CLOSES it (P-DRAW-73)
#define DSTRIP_GEAR_FOOT_H PNL_FOOT_H   // P-DRAW-116: the card's own footer (was 42)
//--- P-DRAW-74 (2026-09-28): the foot carries COMMANDS. Its Close stood beside the
//--- header's own X and wore the panel's one FILLED block, so the loudest thing on a
//--- card whose job is to change a drawing was the way out of it (C-03).
//--- P-DRAW-78: TWO foot buttons, All and Copy. The third was `Del`, and the
//--- strip's own command group already carries a trash cell that asks first
//--- (DrawSelCount in its tooltip) — so the panel carried a second, unconfirmed
//--- way to destroy the drawing. One owner per action.
//--- P-DRAW-90 (2026-09-30) — AND THE THIRD IS `Reset`, not `Del`. The design
//--- (tools/mock-strip-refactor.html:573, footer) draws three commands:
//--- `Reset` at the content's left edge (the only one wearing a glyph, the cards'
//--- own reset ring) and `All`·`Copy` as a pair flush to its right — the mock's
//--- own `.sp` spacer between them. The code shipped TWO, and gave the RESET ring
//--- to `All` (DrawStrip_GearB.mqh:1019): a face that lied about its action.
//--- `Reset` returns THIS drawing to its kind's factory look (the kind's own
//--- built-in preset 0), which the panel had no way to reach at all.
#define DSTRIP_GEAR_FOOT_N 3
//--- P-DRAW-80: the foot button's width is the CARDS' own formula
//--- (`max(72, 32 + advance + 8)`, BiotakPanels PnlFootBtnW) — the flat 64 that
//--- stood here is retired, and with it every reader.
#define DSTRIP_GEAR_FOOT_BW 72   // the formula's floor; the measured width wins above it
#define DSTRIP_GEAR_FOOT_GAP 8
//--- P-DRAW-107 (2026-10-01): the ring's advance inside a foot button — 15px of art
//--- plus its gap, i.e. the cards' own `bx+12 -> bx+32` relation (`32 - 12`), kept
//--- as ONE number. The ring's seat (DrawStripFootGlyphX) and the word's
//--- (DrawStripFootLabelX) both read it, so the pair cannot drift apart on a plate
//--- whose width is measured (`DrawStripFootBw`) rather than fixed.
#define DSTRIP_GEAR_FOOT_GLYPH_ADV 20
#define DSTRIP_GEAR_GRID_GAP 8
#define DSTRIP_GEAR_SWATCH 28
#define DSTRIP_GEAR_CHIP   48   // 5 chips per row in 280px content (5*48 + 4*8 = 272 < 280)
#define DSTRIP_GEAR_CHIP_H 32
#define DSTRIP_GEAR_EDIT_H 22   // P-DRAW-66: the board's own field height (DSTRIP_POP_EDIT_H)
//--- P-DRAW-117 (2026-10-01) — THE PANEL IS AN ACCORDION, AND A GROUP IS A ROW.
//--- The horizontal tab row (DSTRIP_TAB_H/GAP/PAD/UL and the GTrack bed under it)
//--- is RETIRED: the groups are first-class 42px ROWS now, each standing on the
//--- card's own row grid with its icon, its name and the value it currently holds,
//--- and the open group's settings hang directly under its own header. The retired
//--- spellings are deleted by the panel's own purge, so a chart painted by the tab
//--- build cannot leave a `GT*`/`GTrack`/`GU` behind (Touch rule 2).
#define DSTRIP_SEC_CNT_W 24    // P-DRAW-71: a band's count pill (the cards' .cnt)
#define DSTRIP_SEC_CNT_H 16    // P-DRAW-73: the bake's own height (cntChipSkin 24x16)
//--- P-DRAW-123 (2026-10-01) — THE PANEL'S OWN DIAG SWITCH, and the reason it exists:
//--- a paint defect that only the TERMINAL can show had no machine-readable output, so
//--- every report ended as a screenshot read by eye. With this 1, a panel OPEN or a group
//--- switch prints one `[dsdiag] EXPECT` line per painted panel object (name, role, seat,
//--- layer, text) immediately followed by the `[drawstrip] TABCENSUS` reality walk of the
//--- SAME state, and `python tools/diag-diff.py <log>` names the objects that differ.
//--- commented out = silent (the call sites compile away). Never per paint: armed by
//--- `DrawStripGearDiagDump()` on a user action, the same bound the census always had.
#define DSTRIP_DIAG 1
//--- the group row (DSTRIP_GRK_GROUP) and its own two seats: the value DIGEST is
//--- right-aligned `DSTRIP_GEAR_DG_PAD` in from the cell, and the label is fitted
//--- against it with the row's own gap between.
#define DSTRIP_GRK_GROUP  9    // gear row kind 9 = a group header (opens/collapses)
#define DSTRIP_GEAR_DG_PAD 12  // the digest's own inset from the cell's right edge
//--- P-DRAW-118 (2026-10-01) — THE COLOR ROWS ARE THE CARDS' OWN QUICK ROW.
//--- User order: «این color fill از همین جا بشه رنگها شو تغییر داد ... کد رنگ
//--- چیکارش کنم ... پنل تنظیمات اصلی ... مثل همون بکنش ... یک جا یک پارچه باشه».
//--- The panel's two hex BOXES are gone: a colour is chosen by a SWATCH, the way
//--- the cards' COUNT COLOR row does it — the colour the row holds now, then the
//--- palette's own first row (`QuickPalColor(i)` = `BioPal(i)` = `BioPickColor(0,i)`,
//--- the cards' same eight), then a `+` that opens the ONE picker: the strip's
//--- colour board, which keeps the HEX field, the 64-cell page, RECENT and the
//--- opacity bar. One place for a colour, and its face is a swatch (P-DRAW-24).
//--- GEOMETRY, one 42px row of the strip's own 280 cell: 24 + 4 + 8*24 + 7*4 + 4 +
//--- 22 = 274, from `DSTRIP_GEAR_PAD` (16) → +290, inside the plate's 296. The
//--- COUNT is the CARDS' own `PNL_QSW_N`, not a second number.
#define DSTRIP_GEAR_SWQ_N    PNL_QSW_N    // 8 — the cards' own quick count
#define DSTRIP_GEAR_SWQ_CELL 24           // ds_swatch24's native canvas
#define DSTRIP_GEAR_SWQ_GAP  4
#define DSTRIP_GEAR_SWQ_PREV 24           // the block wearing the colour this row owns
#define DSTRIP_GEAR_SWQ_PLUS 22           // the "+" chip (pnl_chip + gl_plus_m)
//--- the GRID's own kinds (`s_dsGGKind`). 1 is the chip `DrawStripGearGridChips`
//--- writes; these three are P-DRAW-118's colour row, and every cell of it rides the
//--- same seat arrays the paint, the hit test and the tool walk.
#define DSTRIP_GRG_SWATCH 0   // a colour cell — its colour is in s_dsGGC[g]
#define DSTRIP_GRG_PREV   2   // the row's own colour, big: tap opens the board
#define DSTRIP_GRG_PLUS   3   // "+" — the same opener
#define DSTRIP_GEAR_LVLBLK 5   // P-DRAW-117: a long LEVEL list opens a block every
                               // 5 rows, so the wide pass can split INSIDE the list
                               // while no group header ever leaves its own content.
//--- P-DRAW-32 (2026-09-24) — THE SETTINGS PANEL IS ITS OWN CARD. User order:
//--- «پنل تنظیمات از استریپ جدا باشه». It used to be the strip's plate GROWING
//--- tall (one window wearing both), so a settings panel meant the toolbar itself
//--- became a tower. It is now a separate surface at its own origin (`s_dsGEX` /
//--- `s_dsGEY`): its own 9-slice plate, its own placement, its own carry — the
//--- strip stays the compact quick row it is. The arithmetic that makes the nine
//--- slice reusable is this constant: the plate's height must read `48 + 42k`
//--- (the skin's own law, P-DRAW-29) and the panel's fixed part is head 56 +
//--- foot 48 + this air, so the height is `104 + AIR + 42R`. AIR is 0 and the law
//--- is therefore EXACTLY the cards' own `56 + n*42 + 48` (P-DRAW-78b) — every
//--- content row lands on a card row and one bake carries the plate. Change this
//--- and the gear falls back to the flat legacy rect (DrawStripSkinK refuses a
//--- plate off the grid).
//--- P-DRAW-117 (2026-10-01): the TAB ROW is retired, so the second addend is the
//--- head alone — `DSTRIP_GEAR_GRID_TOP` is 56 where it used to be 98. The AIR's
//--- number did not move; its readers did: one 42px band left the panel, so the
//--- same content now needs one row fewer and `gh` reads `104 + 42R`.
//--- RETIRED (2026-09-29, P-DRAW-78b): the air was the make-up gap between a 42px
//--- foot band and the cards' 48px footer. The foot band is 48 now (DSTRIP_GEAR_FOOT_H,
//--- whose own ghost face reaches fy0+46 and needs the room), so the card's footer is
//--- already paid for and the 6px was a SECOND count of it: every tab stood 6px over
//--- the cards' law, `cardExact` was false on all four, and the plate fell to the
//--- composed W body on every tab instead of one baked card. Kept at 0 rather than
//--- deleted so the retired law stays readable next to the number that replaced it.
#define DSTRIP_GEAR_AIR 0    // head 56 + 42R + foot 48 + this = 104 + 42R: EXACTLY
                             // the cards' own law (56 + n*42 + 48). The retired
                             // values are the record: 34 was the TAB-ERA air
                             // (140 + 34 = 174 ≡ 48 mod 42, and the tabs are gone),
                             // 6 was the double count of the cards' footer (78b),
                             // and either put every group's height off every bake.
//--- P-DRAW-69: THE FIRST 42px CELL OF EACH SURFACE'S OWN BODY. The cards have ONE
//--- grid — the row pitch — and the plate's ramp bands ride it, so a row's face IS
//--- the band under it. The strip's first popover row and the board's first grid row
//--- both land on the ramp's own start, the panel's on its head (56) — the tab
//--- band's 42 above it is retired (P-DRAW-117).
#define DSTRIP_STRIP_GRID_TOP 44
#define DSTRIP_STRIP_BODY_TOP (DSTRIP_SKIN_TOPT - DSTRIP_SKIN_M)   // 44 — the cap's own content
#define DSTRIP_BOARD_GRID_TOP 44
#define DSTRIP_GEAR_GRID_TOP  (DSTRIP_GEAR_HEAD_H)   // P-DRAW-117: no tab row — the
                               // panel's first cell is the group list's own top row
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
#define DSTRIP_GEAR_W2   (2*PNL_WEL)   // P-DRAW-116: TWO cards side by side, so the wide width IS the card width twice
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
#define DSTRIP_GEAR_LBL_PT PNL_PT_LBL   // P-DRAW-116: the cards' own row-label point size
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
#define DSTRIP_SKIN_M      PNL_MARGIN  // P-DRAW-116: the card bake's own transparent fringe
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
#define DSTRIP_GEAR_GRP_MAX 5  // group ids one kind may show at once (0 = shut)
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
static int      s_dsGearGrp[DSTRIP_GEAR_GRP_MAX + 1];   // group ids shown (count in [0])
//--- P-DRAW-117: `s_dsGear` IS THE OPEN GROUP (never 0 while the panel is open), so
//--- every reader that asks `s_dsGear != 0` keeps its answer; this flag is the ONE
//--- new fact — the user collapsed the open group's settings with its own header,
//--- and the panel is then the group list alone.
static bool     s_dsGearCollapsed = false;
static int      s_dsGearHeadY = -1;
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
#endif // DRAW_STRIP_HEAD_MQH
