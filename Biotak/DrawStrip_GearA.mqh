// DrawStrip_GearA.mqh - DrawStrip split 2026-09-29: exact lines 2381-3364 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_GEARA_MQH
#define DRAW_STRIP_GEARA_MQH


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

//--- P-DRAW-117 (2026-10-01) — THE GROUPS, AND THEY ARE ROWS NOW.
//--- The five seats are the same five the tab row offered (same ids, same
//--- conditions, same per-kind memory) — what changed is that a group is a 42px
//--- ROW of the card's own grid: an icon, its name, and the value it currently
//--- holds. The list is built once per layout, and the walk, the paint, the hit
//--- test and the tool all read THIS answer — "which groups does this kind have"
//--- has exactly one owner, the same way the tab list did.
int DrawStripGearGroups()
{
   int n = 0;
   s_dsGearGrp[n + 1] = DSTRIP_GEAR_PAINT; n++;
   s_dsGearGrp[n + 1] = DSTRIP_GEAR_STYLE; n++;
   if(DrawKindHasLevels(s_dsKind)) { s_dsGearGrp[n + 1] = DSTRIP_GEAR_LEVELS; n++; }
   else if(s_dsKind == DK_TEXT || s_dsKind == DK_ARROW) { s_dsGearGrp[n + 1] = DSTRIP_GEAR_MARK; n++; }
   s_dsGearGrp[n + 1] = DSTRIP_GEAR_TPL; n++;
   s_dsGearGrp[n + 1] = DSTRIP_GEAR_STRIP; n++;
   s_dsGearGrp[0] = n;
   if(s_dsGear != 0)
   {
      bool ok = false;
      for(int i = 1; i <= n; i++) if(s_dsGearGrp[i] == s_dsGear) ok = true;
      if(!ok) s_dsGear = s_dsGearGrp[1];
   }
   return n;
}
string DrawStripGearGroupText(const int gid)
{
   //--- P-DRAW-117: the two look groups wear the word their content is (the old
   //--- `Paint`/`Style` named the retired tab row, not the settings under them).
   if(gid == DSTRIP_GEAR_PAINT) return "Color";
   if(gid == DSTRIP_GEAR_STYLE) return "Stroke";
   if(gid == DSTRIP_GEAR_LEVELS) return "Levels";
   if(gid == DSTRIP_GEAR_MARK) return (s_dsKind == DK_ARROW ? "Mark" : "Text");
   if(gid == DSTRIP_GEAR_TPL) return "Look";
   if(gid == DSTRIP_GEAR_STRIP) return "Row";
   return "";
}
string DrawStripGearGroupRes(const int gid)
{
   if(gid == DSTRIP_GEAR_PAINT) return "::Files\\Icons\\gl_droplet_m.bmp";
   if(gid == DSTRIP_GEAR_STYLE) return "::Files\\Icons\\bk_w2.bmp";
   if(gid == DSTRIP_GEAR_LEVELS) return "::Files\\Icons\\bk_levels.bmp";
   if(gid == DSTRIP_GEAR_MARK) return "::Files\\Icons\\bk_glyph.bmp";
   if(gid == DSTRIP_GEAR_TPL) return "::Files\\Icons\\gl_template_m.bmp";
   if(gid == DSTRIP_GEAR_STRIP) return "::Files\\Icons\\bk_more.bmp";
   return "";
}
string DrawStripGearGroupTip(const int gid)
{
   string nm = DrawStripGearGroupText(gid);
   if(gid == DSTRIP_GEAR_PAINT)
      return nm + " — the border and the interior; click the group to fold it away";
   if(gid == DSTRIP_GEAR_STYLE)
      return nm + " — width, line style, shape and layer; click to open";
   if(gid == DSTRIP_GEAR_LEVELS)
      return nm + " — which levels the held drawing shows; click to open";
   if(gid == DSTRIP_GEAR_MARK)
      return nm + " — the mark's own face; click to open";
   if(gid == DSTRIP_GEAR_TPL)
      return nm + " — the saved looks of this tool; click to open";
   if(gid == DSTRIP_GEAR_STRIP)
      return nm + " — which cells the strip's quick row shows; click to open";
   return "";
}
bool DrawStripGearGridChips(const int slot, const int count)
{
   int cw = DrawStripGearCellW();   // P-DRAW-99: the chips sit in ONE column
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
//--- P-DRAW-111 (2026-10-01) — A ROW IS PLACED WHERE IT IS DECLARED. The row took no
//--- `y`: the layout stamped the whole run AFTER the content walk
//--- (`s_dsGRY[r] = y + r*42`, DrawStripGearLayout), so on a tab that mixes bands and
//--- rows every row landed BELOW the last band — outside its own band's block range
//--- (`DrawStripGearSection` registers the block start; `DrawStripGearShiftItems`
//--- moves an item by the block whose [from,to) CONTAINS its y).
//--- MEASURED on the Style tab, DK_RECT, narrow y-space (contentTop = 98):
//--- blocks STROKE@98 · LINE STYLE@182 · SHAPE@266 · LAYER@308, contentEnd = 518.
//--- The wide pass splits at block 3 (`DrawStripGearPlace`: 84/336, 168/252, 210/210
//--- — the 210 wins), so every row — including SHAPE's own two, BOXHALF and EXTEND —
//--- sits in [308,518) and is TRANSLATED into column 1 with LAYER, while SHAPE's
//--- caption stays alone in column 0. The screenshot is exactly that: a bare SHAPE
//--- band on the left, and `Extend right` (a SHAPE row) stacked under `LAYER` on the
//--- right. Only Style mixes the two — Paint, Look, Row, Levels and Mark declare
//--- their rows after their last band, so for them the stamp and the cursor are the
//--- same number and the plate does not move a pixel.
bool DrawStripGearRow(const int kind, const int arg, int &y)
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
   s_dsGRY[s_dsGRN] = y;
   s_dsGRN++;
   y += DSTRIP_GEAR_ROW_H;
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
//--- P-DRAW-118 (2026-10-01) — ONE COLOUR ROLE AS THE CARDS' OWN QUICK ROW.
//--- The row the hand reads is the CARDS' COUNT COLOR strip: the colour this role
//--- holds NOW, then the palette's first row (`QuickPalColor` = `BioPal` = the
//--- board's own row 0), then the `+` that opens the board (the HEX field, the 64
//--- cells, RECENT and opacity). Every cell lands in the SAME grid arrays the paint,
//--- the hit test and the tool walk (`s_dsGG*` + `s_dsGGC`), so the row has ONE
//--- owner, and it is placed by the same stamp a chip grid uses — one y for the lot.
bool DrawStripGearQuickRow(const int slot, int &y)
{
   int mark = s_dsGGN;
   if(s_dsGGN >= DSTRIP_GRID_MAX) return false;
   {
      int g = s_dsGGN++;
      s_dsGGKind[g] = DSTRIP_GRG_PREV;   s_dsGGSlot[g] = slot; s_dsGGArg[g] = -1;
      s_dsGGW[g]  = DSTRIP_GEAR_SWQ_PREV; s_dsGGH[g] = DSTRIP_GEAR_SWQ_CELL;
      s_dsGGX[g]  = DSTRIP_GEAR_PAD;      s_dsGGY[g] = -1;
   }
   int x = DSTRIP_GEAR_PAD + DSTRIP_GEAR_SWQ_PREV + DSTRIP_GEAR_SWQ_GAP;
   for(int qi = 0; qi < DSTRIP_GEAR_SWQ_N; qi++)
   {
      if(s_dsGGN >= DSTRIP_GRID_MAX) return false;
      int g = s_dsGGN++;
      s_dsGGKind[g] = DSTRIP_GRG_SWATCH; s_dsGGSlot[g] = slot; s_dsGGArg[g] = qi;
      s_dsGGW[g]  = DSTRIP_GEAR_SWQ_CELL; s_dsGGH[g] = DSTRIP_GEAR_SWQ_CELL;
      s_dsGGC[g]  = QuickPalColor(qi);    // P-DRAW-24: ONE palette
      s_dsGGX[g]  = x;                    s_dsGGY[g] = -1;
      x += DSTRIP_GEAR_SWQ_CELL + DSTRIP_GEAR_SWQ_GAP;
   }
   if(s_dsGGN >= DSTRIP_GRID_MAX) return false;
   {
      int g = s_dsGGN++;
      s_dsGGKind[g] = DSTRIP_GRG_PLUS;   s_dsGGSlot[g] = slot; s_dsGGArg[g] = -1;
      s_dsGGW[g]  = DSTRIP_GEAR_SWQ_PLUS; s_dsGGH[g] = DSTRIP_GEAR_SWQ_PLUS;
      s_dsGGX[g]  = x;                    s_dsGGY[g] = -1;
   }
   //--- ONE row: the stamp's own pitch with a column count wider than the run, so
   //--- every cell of the strip shares this row's y (P-DRAW-111: a row is placed
   //--- where it is declared, and this one is declared as a single line).
   DrawStripGearGridStamp(mark, y, DSTRIP_GRID_MAX);
   return true;
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

//--- P-DRAW-99 (2026-09-30) — ONE COLUMN'S OWN CELL, AND IT IS NOT THE BOX.
//--- `DrawStripGearColW()` above is the tab's WHOLE content box: 280 on a 312 tab,
//--- 592 on a 624 one. A 624 tab is TWO columns, not one wide column — the wide pass
//--- walks whole blocks into column 1 at a `DSTRIP_GEAR_COL` (312) pitch, so each
//--- column is 280 wide with a 32px gutter, and 312 + 280 = 592 closes the box
//--- exactly. So "how wide is ONE column" is `280` on every tab, and two readers
//--- were asking the BOX instead and getting two different wrong answers:
//---   * `DrawStripGearResizeEdits` (this file) re-measured a moved field against
//---     592, so the Levels tab's `add a level` was an OBJ_EDIT 592 wide starting at
//---     `px + 312` — its right edge `s_dsGEX+920` against a card that ends at
//---     `s_dsGEX+624`: 296px of live text field painted over the chart.
//---   * `DrawStripGearHit` (DrawStrip_Base) probed a list row 592 wide while
//---     `DrawStripGearPaint` gave that same row a 280 cell, so 312px of bare plate
//---     to the right of the row acted as the row (a click on nothing toggled a
//---     switch). P-DRAW-90 had already made the FOOT ask `DrawStripGearColW()` and
//---     named this exact hazard in the comment above it; the rows were the two
//---     readers it did not reach.
//--- ONE owner here, read by the field, the row, the chip column and the hit test.
//--- The narrow tab's answer is unchanged at 280, so no narrow paint moves a pixel.
int DrawStripGearCellW() { return DSTRIP_GEAR_W - 2 * DSTRIP_GEAR_PAD; }

//--- P-DRAW-30: THE TAB'S CONTENT, built in the NARROW column's own y-space (the
//--- one every block metric above was written for). The wide pass below never
//--- re-derives a block, it TRANSLATES whole blocks into a second column.
void DrawStripGearContent(int &y, bool &levelEdit)
{
   int cw = DrawStripGearCellW();   // P-DRAW-99: ONE column's cell, the owner
   EDrawKind k = s_dsKind;
   int chipCols = (cw + DSTRIP_GEAR_GRID_GAP) / (DSTRIP_GEAR_CHIP + DSTRIP_GEAR_GRID_GAP);
   //--- P-DRAW-117 (2026-10-01) — THE PANEL IS AN ACCORDION, AND THE GROUP LIST
   //--- BRACKETS THE OPEN GROUP. The headers above the open one are laid out, then
   //--- that group's own settings (the chain below, unchanged), then the headers
   //--- BELOW it — so the open group's rows stand directly under their own header
   //--- and every other group is one row away, in reading order.
   //--- Each header OPENS A BLOCK (`DrawStripGearSection`'s own law, P-DRAW-30): "this
   //--- group and the content under it" is the unit the wide pass balances, so a
   //--- header can never be translated away from the settings it names.
   int ng = DrawStripGearGroups();
   int navAt = 0;
   for(int gn = 0; gn < ng; gn++) if(s_dsGearGrp[gn + 1] == s_dsGear) navAt = gn;
   for(int gb = 0; gb <= navAt; gb++)
   {
      if(s_dsGearBlkN < DSTRIP_GEAR_BLK_MAX) s_dsGearBlkY[s_dsGearBlkN++] = y;
      if(!DrawStripGearRow(DSTRIP_GRK_GROUP, s_dsGearGrp[gb + 1], y)) return;
   }
   //--- a FOLDED group is the list alone: the body is asked for the one id no group
   //--- can have, so every branch below declines without a second fence (Touch rule
   //--- 4: the list is still painted — this is not an early return).
   int gOpen = s_dsGearCollapsed ? -1 : s_dsGear;
   if(gOpen == DSTRIP_GEAR_PAINT)
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
      //--- P-DRAW-117: THE BAND IS GONE — the group's own header row carries the
      //--- word "Color" and its hex, so a COLORS band above COLOR/FILL was the same
      //--- name twice (and 42px of plate for it). A band survives only where it
      //--- labels settings the group's name does not: the Style group's STROKE /
      //--- LINE STYLE / SHAPE / LAYER, and the text group's CAPTION / SIZE.
      //--- P-DRAW-118 (2026-10-01): THE TWO HEX BOXES ARE GONE. The user's order:
      //--- «این color fill از همین جا بشه رنگها شو تغییر داد ... کد رنگ چیکارش کنم»
      //--- — and the answer is the cards' own: a colour is a SWATCH. Each role is a
      //--- band (the cards' caption line) + the quick row under it, and the exact
      //--- value lives where it always lived for a precise hand: the board's HEX
      //--- field, behind the row's `+`. Two surfaces, one colour each, and the
      //--- panel keeps no second face for either (P-DRAW-44's own ruling, one step
      //--- further: the box was the LAST duplicate the group still carried).
      DrawStripGearSection("BORDER", y);
      DrawStripGearQuickRow(DRAW_SLOT_COLOR, y);
      if(DrawSlotAvailable(k, DRAW_SLOT_FILLCLR))
      {
         DrawStripGearSection("FILL", y);
         DrawStripGearQuickRow(DRAW_SLOT_FILLCLR, y);
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
         DrawStripGearRow(1, DRAW_SLOT_FILL, y);
   }
   else if(gOpen == DSTRIP_GEAR_STYLE)
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
      if(DrawStripSeatAvail(k, DRAW_SLOT_BOXHALF)) DrawStripGearRow(1, DRAW_SLOT_BOXHALF, y);
      if(DrawSlotAvailable(k, DRAW_SLOT_EXTEND))      DrawStripGearRow(1, DRAW_SLOT_EXTEND, y);
      DrawStripGearSection("LAYER", y);
      DrawStripGearRow(1, DRAW_SLOT_LOCK, y);
      DrawStripGearRow(1, DRAW_SLOT_BACK, y);
   }
   else if(gOpen == DSTRIP_GEAR_LEVELS)
   {
      int nl = DrawStripGearLevelCount();
      //--- P-DRAW-73: a refused row STOPS the loop, so what is left is a prefix of the
      //--- list and the owner has already named the loss in the log.
      //--- P-DRAW-104: BUT THE TWO MANAGEMENT ROWS ARE NOT PART OF THAT BUDGET. The
      //--- loop below ran to `nl` — up to `DSTRIP_GLIST_MAX` (16), because
      //--- `DrawStripGearLevelCount` caps the LIST at the same 16 the ROW array holds
      //--- — and the two rows after it (`All levels on` / `No levels`) were then
      //--- refused by the very same ceiling. So at 9 common + 7 custom levels the two
      //--- rows that are the ONLY way to clear the level set in one gesture were
      //--- simply not built, and the only trace was the one-shot log line: the user
      //--- lost the ability to turn the fibo's levels off and had to delete them one
      //--- at a time. The list is the elastic half; reserve its two seats here, where
      //--- the two mandatory rows are known, rather than raise the array for every
      //--- tab (the other three tabs build at most 12). Nothing is dropped: a level
      //--- past the reserve is simply not LISTED, and the drawing keeps it.
      //--- P-DRAW-117: AND THE GROUP LIST'S OWN HEADERS ARE SPENT SEATS. The list
      //--- rides the same row array as the headers, so `room` reserves what is
      //--- already standing (the headers above AND below this group) as well as the
      //--- two management rows — the P-DRAW-104 defect (a row refused by a ceiling
      //--- nobody re-derived) re-opened in the new shape.
      int room = DSTRIP_GLIST_MAX - 2 - s_dsGRN;   // the two rows below are not optional
      if(room < 0) room = 0;
      for(int i = 0; i < nl && i < room; i++)
      {
         //--- P-DRAW-117: a long list opens a block every DSTRIP_GEAR_LVLBLK rows,
         //--- so the wide pass can split INSIDE the list (P-DRAW-30's own complaint:
         //--- a 20-level fibo must not grow one tower) while no header moves away
         //--- from its content — a header only ever opens a block at a row boundary.
         if((i % DSTRIP_GEAR_LVLBLK) == 0 && s_dsGearBlkN < DSTRIP_GEAR_BLK_MAX)
            s_dsGearBlkY[s_dsGearBlkN++] = y;
         if(!DrawStripGearRow(4, i, y)) break;
      }
      DrawStripGearRow(5, 0, y);
      DrawStripGearRow(5, 1, y);
      levelEdit = true;
   }
   else if(gOpen == DSTRIP_GEAR_MARK)
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
         for(int g = 0; g < DrawStripGlyphCount(); g++)
            if(!DrawStripGearRow(8, DRAW_SLOT_GLYPH * 256 + g, y)) break;
      }
   }
   else if(gOpen == DSTRIP_GEAR_TPL)
   {
      //--- P-DRAW-76: slot ids (see the more-popover's builder) — a hole never shifts the list.
      for(int i = 0; i < DRAW_PRESET_MAX; i++)
      { if(DrawPresetName(k, i) == "") continue; if(!DrawStripGearRow(2, i, y)) break; }
      DrawStripGearRow(3, 0, y);
      DrawStripGearRow(7, 0, y);
   }
   else if(gOpen == DSTRIP_GEAR_STRIP)
   {
      for(int s = 0; s < DRAW_SLOT_N; s++)
      {
         if(s == DRAW_SLOT_MORE) continue;
         if(!DrawSlotAvailable(k, s)) continue;
         if(!DrawStripGearRow(6, s, y)) break;
      }
      if(DrawKindHasLevels(k)) DrawStripGearRow(6, DRAW_SLOT_MORE, y);
      DrawStripGearRow(5, 2, y);
   }
   //--- P-DRAW-117: the groups BELOW the open one close the accordion.
   for(int ga = navAt + 1; ga < ng; ga++)
   {
      if(s_dsGearBlkN < DSTRIP_GEAR_BLK_MAX) s_dsGearBlkY[s_dsGearBlkN++] = y;
      if(!DrawStripGearRow(DSTRIP_GRK_GROUP, s_dsGearGrp[ga + 1], y)) return;
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
//--- COLUMN CHANGES. `DrawStripGearContent` measures it against the narrow column
//--- (280) because that is the only width known while the content is still being
//--- built; the wide pass then moves the same field into a 592px BOX holding two
//--- 280 columns. One pass, on the two paths that change the width, and only over
//--- the five edit slots.
//--- P-DRAW-99: AND THE PASS MEASURES THE COLUMN, NOT THE BOX. It asked
//--- `DrawStripGearColW()`, which is the whole 592 content box, so a field the wide
//--- pass had just moved into column 1 was re-measured to 592 - 0 and hung 296px
//--- past the card. One owner, `DrawStripGearCellW()` (280 on every tab), and the
//--- narrow answer is identical.
void DrawStripGearResizeEdits()
{
   int colW = DrawStripGearCellW();
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
   //--- P-DRAW-91: the reset of `s_dsGearW` MOVED UP to the top of
   //--- DrawStripGearLayout, before the content pass — this was the second writer
   //--- of one value, and it was too late for the first reader. The only write
   //--- left here is the one this pass owns: GROWING the column to 624.
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
   //--- The card set is the law: narrow only while the narrow plate's OWN card exists.
   //--- P-DRAW-117 (2026-10-01): AND THE COUNT IS THE ROWS THEMSELVES NOW. With the
   //--- tab band retired the body starts at the head (`contentTop` = 56) and the
   //--- height is `56 + 42R + 48` = `104 + 42R`, i.e. `cardN = R` — so R rows need
   //--- card R and the ceiling is exactly `DSTRIP_GEAR_WIDE_ROWS` (10) rows, one more
   //--- than the `WIDE_ROWS - 1` the tab build could fit (it carried the tab row as
   //--- its extra cell). Read by this one owner; `tools/check-gear-panel.py` reads the
   //--- expression back out of this line against the bakes on disk.
   if(contentEnd - contentTop <= DSTRIP_GEAR_WIDE_ROWS * DSTRIP_GEAR_ROW_H) return;
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
   DrawStripGearGroups();   // P-DRAW-117: the group list IS the panel's nav now
   //--- P-DRAW-117 (2026-10-01): THE TAB BAND IS RETIRED, so the panel's first
   //--- cell is the group list's own first row and the body starts at the head's
   //--- bottom edge (56) — one 42px row higher than the tab build. The plate's own
   //--- arithmetic follows: gh = 104 + 42*R with `cardN = R` (DrawStripGearPlate),
   //--- so the narrow ceiling is R <= DSTRIP_GEAR_WIDE_ROWS rows (DrawStripGearPlace).
   y += DSTRIP_GEAR_HEAD_H;
   int contentTop = y;
   s_dsGRN = 0; s_dsGGN = 0; s_dsGearSecN = 0; s_dsGearBlkN = 0;
   for(int e0 = 0; e0 < 5; e0++)
   { s_dsGearEditY[e0] = -1; s_dsGearEditX[e0] = 0; s_dsGearEditW[e0] = 0; }
   //--- P-DRAW-91 (2026-09-30) — THE COLUMN WIDTH IS THIS TAB'S BEFORE ANYTHING
   //--- READS IT. User report: on the Paint tab the COLOR and FILL hex fields ran
   //--- off the card (two dark bars ~312px past the plate's right edge). MEASURED:
   //--- `DrawStripGearContent` writes `s_dsGearEditW[e] = DrawStripGearColW() - capW`
   //--- and `DrawStripGearColW()` is `s_dsGearW - 2*PAD` — but the ONLY reset of
   //--- `s_dsGearW` stood inside `DrawStripGearPlace`, which runs AFTER this call.
   //--- Open a WIDE tab (Style/Row, 624), switch to Paint, and the content measured
   //--- itself against the PREVIOUS tab's 592 while the plate asked for 312: field
   //--- width `592 - capW`, off the card by exactly the 312 that separated the two
   //--- columns. P-DRAW-82 had already made the field ask `DrawStripGearColW()` —
   //--- the missing half is that the number must be THIS tab's from the first
   //--- reader. ONE writer, at the top of the pass, before anything can ask.
   s_dsGearW = DSTRIP_GEAR_W;
   bool levelEdit = false;
   DrawStripGearContent(y, levelEdit);
   //--- P-DRAW-111: the row run is NO LONGER stamped here. `DrawStripGearRow` took the
   //--- content cursor by reference and placed each row where it was declared, so this
   //--- loop would have re-written every y the same way it did before — and that second
   //--- write is the defect: a mixed tab's rows came back to a contiguous run below the
   //--- last band, outside the block that owns their header. The column reset stays
   //--- (DrawStripGearPlace owns the same value and runs on every path).
   for(int r = 0; r < s_dsGRN; r++) s_dsGRCol[r] = 0;
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
   //--- P-DRAW-117: the tab row owned this pass's tail (`s_dsGearTabX/W` and the
   //--- rail it centred on). With the groups as rows there is no rail to seat: the
   //--- foot is the only thing left to place, and the wide pass has already decided
   //--- the width every reader of it asks.
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
    s_dsPOpY = -1;s_dsBW = 0; s_dsBH = 0;   // P-DRAW-48: the board's rect exists only for a colour board
   //--- P-PAL-21 (2026-10-02) — THERE IS NO COLOUR BOARD LEFT. `s_dsPicker` cannot
   //--- hold a colour seat since P-PAL-19: a tap on the colour cell asks the CARDS'
   //--- palette (`DrawStripPalAsk`) and nothing writes a colour seat back. So the
   //--- whole `DrawStripIsColorSlot(s_dsPicker)` branch — the grid, the RECENT band,
   //--- the HEX field, the opacity bar, the page seats and the studio — was a layout
   //--- for a plate that no longer exists, and its plate was measured by
   //--- `DrawStripPalLayout` in a file that this build no longer has. The list rows
   //--- below are the picker that is still real (width, style, level, MORE).
   if(s_dsPicker != DSTRIP_PICK_NONE)
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
   //--- P-PAL-21: the board's placement pass went with the board (a colour seat is
   //--- never the picker now), so the layout ends at the strip's own rect.
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

void DrawStripClosePicker()
{
   DrawStripColorHoverClear();
   //--- P-PAL-21: the board's chrome prune went with the board (nothing painted it
   //--- any more); `DrawStripSkinPurgeAt(2)` below is what still has a plate to take.
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
   //--- P-DRAW-117: the probe is the FAMILY, not one spelling — a chart painted by
   //--- the tab build carries `GT0..GT4`, the `GTrack` bed and the `GU` underline,
   //--- and none of the three is painted by this build any more, so the owner that
   //--- takes the panel down must recognise the OLD names as evidence the family is
   //--- on the chart (Touch rule 2: the rename ships with the sweep).
   if(ObjectFind(0, DrawStripRowName(0)) >= 0 || ObjectFind(0, DrawStripGearBgName()) >= 0
      || ObjectFind(0, "PnlDrawS_Gtop") >= 0 || ObjectFind(0, "PnlDrawS_GT0") >= 0
      || ObjectFind(0, "PnlDrawS_GTrack") >= 0 || ObjectFind(0, "PnlDrawS_GU") >= 0)
   { ObjectsDeleteAll(0, "PnlDrawS_G", -1, -1); dirty = true; return dirty; }
   //--- the requested-tab-room of a chart that predates the accordion: the group
   //--- row is a ROW now (`DrawStripRowName`), so these five are orphans by the same
   //--- ruling as their bed and underline — deleted here so a half-upgraded chart
   //--- cannot keep a second nav under the new one.
   for(int t = 0; t < DSTRIP_GEAR_GRP_MAX; t++)
   {
      string tn = "PnlDrawS_GT" + IntegerToString(t);
      if(ObjectFind(0, tn) >= 0) { ObjectDelete(0, tn); dirty = true; }
   }
   if(ObjectFind(0, "PnlDrawS_GTrack") >= 0)
   { ObjectDelete(0, "PnlDrawS_GTrack"); dirty = true; }
   if(ObjectFind(0, "PnlDrawS_GU") >= 0)
   { ObjectDelete(0, "PnlDrawS_GU"); dirty = true; }
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
      //--- P-DRAW-117: and the group row's own DIGEST — the value its name does not
      //--- carry. A member of the row family, so it is deleted by the row's owner.
      if(ObjectFind(0, DrawStripRowDigestName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowDigestName(r)); dirty = true; }
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
#endif // DRAW_STRIP_GEARA_MQH
