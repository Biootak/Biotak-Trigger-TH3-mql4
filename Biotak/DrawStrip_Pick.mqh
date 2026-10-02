// DrawStrip_Pick.mqh - DrawStrip split 2026-09-29: exact lines 1461-2380 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_PICK_MQH
#define DRAW_STRIP_PICK_MQH


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
      //--- P-DRAW-105: THE SEAT IS HALF-OPEN, LIKE THE PAINT. The painter's own
      //--- rect is `[pgx+k*20, pgx+k*20+20)` (DrawStrip_Paint, the page seats) and
      //--- this was `mx <= xa+20`, so the single column `pgx+20` belonged to seat 0
      //--- and to seat 1 at the same time — a 1px seam where the outer half of the
      //--- right arrow's own left edge turned the page backwards.
      if(mx >= xa && mx < xa+20) return k;      // 0 = previous page, 1 = next
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
   //--- P-DRAW-118 (2026-10-01): the SWATCH cells live in the Color group's quick
   //--- rows now (they were the retired Paint grid's, the last caller this fence
   //--- knew). Same seat arrays, one more group allowed to wear them.
   if(s_dsGear == DSTRIP_GEAR_STYLE || s_dsGear == DSTRIP_GEAR_PAINT)
   {
      for(int g = 0; g < s_dsGGN; g++)
      {
         if(s_dsGGKind[g] != DSTRIP_GRG_SWATCH) continue;
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
   if(cell < 0 || cell >= s_dsGGN || s_dsGGKind[cell] != DSTRIP_GRG_SWATCH) return clrNONE;
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
      if(cell < 0 || cell >= s_dsGGN || s_dsGGKind[cell] != DSTRIP_GRG_SWATCH) return;
      nm = DrawStripGridName(cell);
      //--- P-DRAW-118: the CELL says which role it belongs to — the FILL row's
      //--- swatches compare against the interior, not against the border.
      current = (DrawStripColorRead(s_dsObj, s_dsGGSlot[cell]) == s_dsGGC[cell]);
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
#endif // DRAW_STRIP_PICK_MQH
