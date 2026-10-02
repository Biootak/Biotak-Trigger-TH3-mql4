// DrawStrip_Tap.mqh - DrawStrip split 2026-09-29: exact lines 6239-7018 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_TAP_MQH
#define DRAW_STRIP_TAP_MQH


//--- P-DRAW-118 (2026-10-01) — A COLOUR HAS ONE OWNER. The palette cell, the
//--- panel's quick swatch and the board's HEX field all end in this write: RECENT,
//--- undo, the fill's own show group, the value, and the level's border sync. One
//--- place, so a new face for a colour cannot miss a step the old one took.
bool DrawStripColorCommit(const int slot, const color c)
{
   if(!DrawStripIsColorSlot(slot)) return false;
   if(c == clrNONE) return false;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   DrawStripRecentPush(c);
   DrawStripUndoPush();
   if(slot == DRAW_SLOT_FILLCLR) DrawStripFillShowGroup();   // P-DRAW-64: a colour is a fill
   DrawStripWriteValue(slot, (double)(int)c);
   if(slot == DRAW_SLOT_COLOR) BoxMidSyncGroup();   // P-DRAW-64a: the level wears the border
   return true;
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
      return DrawStripColorCommit(slot, DrawStripPickColor(slot, row));
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
       //--- P-DRAW-65: the colours open first. P-DRAW-117: and a fresh open shows
       //--- that group's SETTINGS — the panel never opens folded.
       else { s_dsGear = DSTRIP_GEAR_PAINT; s_dsGearCollapsed = false; }
       //--- P-DRAW-86 (2026-09-29): THE OPEN SWEEPS FIRST. The close-purge kills
       //--- every PnlDrawS_G* — but only if the close ran. A terminal restart, a
       //--- crash, or a build that predates the purge leaves same-prefix objects
       //--- on the chart, and the new paint repaints same-name ones but never
       //--- deletes a stale bed (the blue GTrack that survived three re-adds).
       //--- One bounded pass on open, never on paint.
       DrawStripGearObjectsPurge();
       DrawStripLayout();
       DrawStripPaint();
       //--- P-DRAW-123: the dump, not the bare census — one armed repaint prints the
       //--- `[dsdiag] EXPECT` half of what the terminal is about to answer with.
       DrawStripGearDiagDump();   // P-DRAW-87/112/123: the panel names its objects
       //--- P-DRAW-127 (2026-10-01) — A PANEL OPEN FLUSHES ITS OWN FRAME.
       //--- MEASURED on the 22:10/22:13 frames of
       //--- `biotak_diag_EURUSD_134342075006101685.txt`: the WIDE (624px) open declared
       //--- all 91 objects correct and unoccluded while the SCREEN showed its left
       //--- column empty — the object LIST was right and the PIXELS were one frame
       //--- behind. `DrawStripPaint` flushes with `if(dirty) ChartRedraw()` (its own
       //--- line), and the dump's repaint above (P-DRAW-125a) DISCARDS its return, so a
       //--- panel whose geometry moved without any write reporting dirty kept the
       //--- previous frame — and a second click "fixed" it because that one did write.
       //--- A user action gets one unconditional flush; a paint pass never does.
       ChartRedraw();
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
   //--- P-DRAW-95 (2026-09-30): ONE SHOW, NOT TWO. The pair below was the same two
   //--- lines pasted twice (P-DRAW-64's note carried two call sites while the code
   //--- carried one act): a second writer of the same fact, and every recent tap paid
   //--- a member walk twice — once per copy, on the group and on each member's own
   //--- description. One writer, one walk.
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
//--- gear grid cells: swatches (P-DRAW-118), the two openers, and the chips.
bool DrawStripGridTap(const int g)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(g < 0 || g >= s_dsGGN) return false;
   DrawStripColorHoverClear();
   int gk = s_dsGGKind[g], slot = s_dsGGSlot[g];
   //--- P-DRAW-118: a swatch APPLIES THE COLOUR IT WEARS — read from `s_dsGGC`, the
   //--- array the paint wrote (Touch rule 7: a hit test with its own arithmetic is a
   //--- second grid) — through the colour's one owner.
   if(gk == DSTRIP_GRG_SWATCH)
   {
      if(!DrawStripColorCommit(slot, s_dsGGC[g])) return false;
      DrawStripPaint();
      BoxMidSyncServed();   // P-DRAW-21: a grid restyle restyles the mid
      return true;
   }
   //--- the preview block and the `+` are the SAME act: the board on this role. The
   //--- strip keeps ONE popover at a time (DrawStripTap does exactly this for a
   //--- quick-row colour cell), so the panel steps aside for the picker it opens.
   if(gk == DSTRIP_GRG_PREV || gk == DSTRIP_GRG_PLUS)
   {
      DrawStripGearClose();
      if(s_dsPicker == slot) DrawStripClosePicker();
      else s_dsPicker = slot;
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   DrawStripPickApply(slot, s_dsGGArg[g]);   // P-DRAW-44: chips
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
   //--- P-DRAW-117: a group header opens (or folds) its own group. The row probe
   //--- reaches this the same way it reaches a switch — one hit test, no second grid
   //--- (P-DRAW-84's own law: the hit test reads the seat arrays the paint wrote).
   if(kind == DSTRIP_GRK_GROUP) return DrawStripGearGroupTap(arg);
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
//--- gear foot: Reset / All / Copy. P-DRAW-78: `Del` is retired from the panel —
//--- the strip's own command group already carries a trash cell, so this was a
//--- second, unconfirmed way to destroy the drawing. The head's X is the close.
//--- P-DRAW-90 (2026-09-30): `Reset` is the design's own first command (the third
//--- seat the panel was missing) — it puts THIS drawing back on its kind's factory
//--- look, i.e. the kind's own built-in preset 0 (`DrawPresetApply`, Toolbar_B:
//--- slots 0..DRAW_PRESET_BUILTIN-1 are the shipped looks), and it is UNDOABLE
//--- like every other look change (DrawStripUndoPush, the same single-step undo the
//--- more-popover's template rows push). `All` keeps its own action, one seat right;
//--- `Copy` is the third. One action per seat, and the seat's glyph now matches it.
bool DrawStripFootTap(const int f)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(f == 0)
   {
      DrawStripUndoPush();
      DrawPresetApply(s_dsObj, 0);
      //--- P-DRAW-96 (2026-09-30): `DrawPresetApply` writes DRAW_SLOT_COLOR, so it owes
      //--- the box's own mid line the new ink — every other colour path in this group
      //--- carries `BoxMidSyncGroup()`/`BoxMidSyncServed()` for exactly that reason
      //--- (P-DRAW-64a), and Reset was the one that did not: after a Reset the 50 % line
      //--- kept the pre-Reset border colour until the pump's next pass. Served, not the
      //--- group: Reset touched the held drawing only.
      BoxMidSyncServed();   // P-DRAW-21: the level wears the border
      DrawStripPaint();
      return true;
   }
   if(f == 1)
   {
      DrawStyleApplyToKind(s_dsObj);
      DrawStripPaint();
      return true;
   }
   if(f == 2) return DrawStripDuplicate();
   return false;
}
//--- P-DRAW-117 (2026-10-01) — THE GROUP HEADER IS THE PANEL'S ONE GESTURE.
//--- A tap on a group's own row OPENS that group's settings (only one body is built
//--- at a time, so the group that was open folds); a tap on the group that IS open
//--- folds its body away and leaves the list — the panel stays open, with its head,
//--- its other groups and its foot exactly where they were. `s_dsGear` is still "the
//--- open group" (never 0 while the panel is open), so every reader that asks
//--- `s_dsGear != 0` keeps its answer, and `s_dsGearCollapsed` is the one new fact.
bool DrawStripGearGroupTap(const int gid)
{
   DrawStripColorHoverClear();
   if(!s_dsOpen) return false;
   bool known = false;
   for(int i = 1; i <= s_dsGearGrp[0]; i++) if(s_dsGearGrp[i] == gid) known = true;
   if(!known) return false;
   DrawStripClosePicker();
   if(s_dsGear == gid) s_dsGearCollapsed = !s_dsGearCollapsed;
   else { s_dsGear = gid; s_dsGearCollapsed = false; }
   // P-DRAW-26: the kind remembers its group (a shut panel remembers shut).
   if(s_dsKind > DK_NONE && s_dsKind < DK_COUNT) s_dsGearMem[s_dsKind] = s_dsGear;
   DrawStripLayout();
   DrawStripPaint();
   //--- P-DRAW-112 (2026-10-01): the census ran ONLY on the panel's OPEN, and a
   //--- tab switch is not an open — which is why every Style-tab report in the
   //--- 2026-10-01 log carries `PLATE tab=1` and not one `TABCENSUS` line: the one
   //--- walk that can name what the terminal actually holds for the tab that
   //--- misbehaves was never fired on it. Same owner, same bound (one walk per user
   //--- action, never per paint), and a GROUP OPEN is the same user action.
   //--- P-DRAW-123: and the walk now carries the paint's OWN declaration beside it
   //--- (`[dsdiag] EXPECT` + TABCENSUS of one state), which is what `tools/diag-diff.py`
   //--- diffs to name the objects the terminal did not honour.
   DrawStripGearDiagDump();
   return true;
}
//--- gear edits (ENDEDIT): hex colour, level add, caption. Invalid input keeps
//--- the typed text for another try (paint re-seeds a field only while it is NOT
//--- the focus, so an unparsable half-word is never overwritten under the hand).
//--- P-DRAW-100: AND THE COMMIT RELEASES THE FIELD. `s_dsHexFocus` is the guard the
//--- Paint tab's live re-seed asks, and only the BOARD's commit released it
//--- (P-DRAW-48, two lines below) — so one hex typed into the panel's own COLOR
//--- box armed the guard for the rest of the session and that field never showed a
//--- colour again. One line, at the one place the field stops being typed in, and
//--- an invalid parse keeps the focus so the hand's word survives either way.
bool DrawStripEditEnd(const int e)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   string nm = DrawStripEditName(e);
   if(ObjectFind(0, nm) < 0) return false;
   string txt = ObjectGetString(0, nm, OBJPROP_TEXT);
   //--- P-DRAW-118 (2026-10-01): e0/e4 (the panel's two hex boxes) are RETIRED —
   //--- the colour is a swatch now and the exact value is the BOARD's HEX field,
   //--- whose own commit is `DrawStripPopHexEnd` below (P-DRAW-100's site moved with
   //--- the field). Their objects are swept by the paint's own `!want` branch, so a
   //--- chart that carried them keeps nothing.
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
   //--- P-DRAW-64: the field belongs to the BOARD it sits on, so it writes the
   //--- board's own role — typing a hex while the FILL board is open is a fill.
   //--- P-DRAW-118: and it writes it through the COLOUR's own owner, the same one the
   //--- palette cell and the panel's quick swatch call.
   int hslot = DrawStripIsColorSlot(s_dsPicker) ? s_dsPicker : DRAW_SLOT_COLOR;
   DrawStripColorCommit(hslot, c);
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
//--- P-DRAW-113 (2026-10-01) — THE PANEL'S OWN PLATE IS NOT THE CHART, EVEN WHERE NO
//--- CONTROL IS. `DrawStripGearHit` answers "did a control act", and it answers FALSE
//--- on the panel's own dead pixels ON PURPOSE: the tab TRACK between two tabs
//--- (DrawStrip_Base.mqh:399), the 42px cell's own margins, and the plate's own 14px
//--- skin margin — which P-DRAW-83 already named as "pixels no control owns" without
//--- ever wiring them to anything.
//--- The press edge spent the event only on a TRUE (DrawStrip_Router.mqh:578), and the
//--- release's dismissal branch asks ONLY that flag — so a press on the panel's own
//--- dead space reached it unsunk and was read as a click on the CHART:
//--- `DrawStripClose()` → `DrawStripGearClose()` → `ObjectsDeleteAll("PnlDrawS_G")`,
//--- the whole family gone at once.
//--- MEASURED, EURUSD,H1 2026-10-01 10:14, Style tab: panel at (766,148) 624x398, and
//---   PLATE tab=1 ... xy=766,148 with the row's seats at 220/269/318/367 (w 41/45/37/37)
//---   [drawstrip] dismiss click at 1126,230 travel=0 obj="Rectangle 320"
//--- 230-148 = 82, inside the tab buttons' band (gy+65..gy+89); 1126-766 = 360, the 8px
//--- GAP between tab 2 (ends 359) and tab 3 (starts 367) — the track, the one place the
//--- hit test declines by design. The panel was torn down and came back with its head,
//--- its tab row and its foot gone: the report «خود تب و دکمه حذف و غیره دیده نمیشه».
//--- ONE owner, and it reads the panel's own numbers (`s_dsGEX/s_dsGEY/s_dsGearW0/
//--- s_dsGearH`), the same rect `DrawStripPointInside` and `DrawStripGearHit` already
//--- read. THE HEAD IS EXCLUDED: `DrawStripGearGripAt` is the panel's carry and needs
//--- the press left tracked, so the head's own band stays the carry's (P-DRAW-85).
bool DrawStripGearSurfaceAt(const int mx, const int my)
{
   if(!s_dsOpen || s_dsGear == 0) return false;
   if(s_dsGearW0 <= 0 || s_dsGearH <= 0) return false;
//--- ONE owner, ONE number. This is the same rect `DrawStripPointInside` answers for
//--- the panel (DrawStrip_Base.mqh:301-303) and it must carry the SAME margin: that
//--- function is the one the release's dismissal asks (`DrawStripPointInside`, router
//--- :988), and this one is the one that decides whether the press was spent. A press
//--- the release would call a dismissal but the press edge did not spend is exactly the
//--- `ObjectsDeleteAll("PnlDrawS_G")` this rule exists to stop — so both read
//--- `DSTRIP_SKIN_M + 2`, not two numbers 2px apart. The 2px is P-DRAW-31's air between
//--- the two surfaces, not a disagreement about where the panel ends.
int m = DSTRIP_SKIN_M + 2;   // the panel's own skin margin is plate, not chart
if(mx < s_dsGEX - m || mx > s_dsGEX + s_dsGearW0 + m) return false;
if(my < s_dsGEY - m || my > s_dsGEY + s_dsGearH + m) return false;
if(DrawStripGearGripAt(mx, my)) return false;   // the head is the carry's
return true;
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
#endif // DRAW_STRIP_TAP_MQH
