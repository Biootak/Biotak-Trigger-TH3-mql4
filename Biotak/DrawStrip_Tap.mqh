// DrawStrip_Tap.mqh - DrawStrip split 2026-09-29: exact lines 6239-7018 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_TAP_MQH
#define DRAW_STRIP_TAP_MQH


//--- P-DRAW-118 (2026-10-01) — A COLOUR HAS ONE OWNER. The palette cell, the
//--- panel's quick swatch and the board's HEX field all end in this write: RECENT,
//--- undo, the fill's own show group, the value, and the level's border sync. One
//--- place, so a new face for a colour cannot miss a step the old one took.
//--- P-DRAW-130 (2026-10-13): `remember=false` is a HOVER PREVIEW (the popup's
//--- PalHoverPreview applies this way). The drawing still wears the colour live —
//--- that is the point of a preview — but the look must not be LEARNED as the
//--- kind's last change, or the next drawing of the kind is born wearing a colour
//--- the hand only passed over (and every crossing persisted it to disk). A click
//--- keeps the default; only the preview asks for the write-without-learn half.
bool DrawStripColorCommit(const int slot, const color c, const bool remember=true)
{
   if(!DrawStripIsColorSlot(slot)) return false;
   if(c == clrNONE) return false;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   //--- P-PAL-21: the strip's own RECENT ring went with its board (nothing paints
   //--- it any more); the cards' palette keeps the history this product shares.
   DrawStripUndoPush();
   if(slot == DRAW_SLOT_FILLCLR) DrawStripFillShowGroup();   // P-DRAW-64: a colour is a fill
   DrawStripWriteValue(slot, (double)(int)c, remember);
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
   if(slot == DRAW_SLOT_WIDTH || slot == DRAW_SLOT_BODYWIDTH)
   {
      if(row < 0 || row > 4) return false;
      DrawStripUndoPush();
      DrawStripWriteValue(slot, (double)(row + 1));
      return true;
   }
   //--- P-DRAW-BODY-UI: native five only — never a look tag, never the levels.
   if(slot == DRAW_SLOT_BODYSTYLE)
   {
      if(row < 0 || row > 4) return false;
      DrawStripUndoPush();
      DrawStripWriteValue(DRAW_SLOT_BODYSTYLE, (double)row);
      return true;
   }
   if(slot == DRAW_SLOT_STYLE)
   {
      // P-LOOK: the count lives in DrawStripPickCount — a second bound here is
      // how the fibo's own rows 5/6/7 arrived dead (painted, never applied).
      if(row < 0 || row >= DrawStripPickCount(k, slot)) return false;
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
bool DrawStripLevelsRewrite(double &vals[], color &clrs[], int &wds[], int &sts[], string &txts[], const int n)
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
      //--- P-LVL-TEXT: texts ride index-aligned with values — a rewrite that
      //--- moved values but not texts would glue notes onto the wrong levels.
      ObjectSetString(0, s_dsObj, OBJPROP_LEVELTEXT, i, txts[i]);
   }
   FibPenTagDrop(s_dsObj);   // P-DRAW-74b: rewritten truth spends the memory
   FibPenSync(s_dsObj, false);   // P-DRAW-74b: rewritten truth converges here
   //--- DIAG-139 (2026-10-18) — THE ONE FUNNEL EVERY MEMBERSHIP EDIT PASSES. The gear
   //--- panel's typist commits with NO tap at all (DrawStripEditEnd, e1), so the ADD
   //--- half of «لول دلخواه اضافه نمیشه» has no gesture to witness: the set it wrote is
   //--- the only proof it ran, and it rides here for the remove half too (P-LOG-3).
   string lvset = "";
   for(int w = 0; w < n; w++) lvset += (w > 0 ? "|" : "") + DrawStripLevelName(vals[w]);
   DrawStripDiagEmit("[drawstrip] LVLSET obj=\"" + s_dsObj + "\" n=" + IntegerToString(n) +
                     " vals=" + lvset);
   return true;
}
void DrawStripLevelsCollect(double &vals[], color &clrs[], int &wds[], int &sts[], string &txts[], int &n)
{
   n = 0;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return;
   int cur = DrawLevelCount(s_dsObj);
   for(int i = 0; i < cur && n < 32; i++)
   {
      //--- P-LVL-SCALE: the funnel migrates old percent-stored sets (23.6) to
      //--- ratios (0.236) on the next rewrite — every toggle/add/set-all heals.
      double v = DrawStripLevelNorm(DrawLevelValue(s_dsObj, i));
      if(!MathIsValidNumber(v)) continue;
      vals[n] = v;
      clrs[n] = (color)(int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELCOLOR, i);
      wds[n] = FibPenLogicalWidth(s_dsObj, i);   // P-DRAW-74b: collect the remembered width, not the thinned one
      sts[n] = (int)ObjectGetInteger(0, s_dsObj, OBJPROP_LEVELSTYLE, i);
      txts[n] = ObjectGetString(0, s_dsObj, OBJPROP_LEVELTEXT, i);
      n++;
   }
}
//--- toggle one membership value (multi-stay: the editor does NOT close).
bool DrawStripLevelsToggle(const double v)
{
   //--- P-LVL-SCALE: the value rides normalized (ratio) — collected rows already
   //--- are, so a percent-typed 88.6 meets the stored 0.886 instead of doubling it.
   double nv = DrawStripLevelNorm(v);
   if(!MathIsValidNumber(nv)) return false;
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   DrawStripUndoPush();
   double vals[32]; color clrs[32]; int wds[32]; int sts[32]; string txts[32]; int n = 0;
   DrawStripLevelsCollect(vals, clrs, wds, sts, txts, n);
   int at = -1;
   for(int i = 0; i < n; i++)
      if(MathAbs(vals[i] - nv) < 0.000001) { at = i; break; }
   if(at >= 0)
   {
      for(int j = at; j < n - 1; j++)
      { vals[j] = vals[j + 1]; clrs[j] = clrs[j + 1]; wds[j] = wds[j + 1]; sts[j] = sts[j + 1]; txts[j] = txts[j + 1]; }
      n--;
   }
   else
   {
      if(n >= 32) return false;
      vals[n] = nv;
      clrs[n] = (color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR);
      wds[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
      sts[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE);
      txts[n] = "";
      n++;
   }
   bool lvlOk = DrawStripLevelsRewrite(vals, clrs, wds, sts, txts, n);
   //--- P-DRAW-135: the toggle is the user's «کم و زیاد» gesture and it had NO witness
   //--- on the flushed channel — «کم و زیاد نمیشه» was unprovable. Value, action,
   //--- count and read-back ride one line (P-LOG-3).
   DrawStripDiagEmit("[drawstrip] LVLTOG obj=\"" + s_dsObj + "\" v=" + DrawStripLevelName(nv) +
                     " act=" + (at >= 0 ? "del" : "add") + " n=" + IntegerToString(n) +
                     " ok=" + (lvlOk ? "1" : "0"));
   return lvlOk;
}
//--- All / None for the common nine.
bool DrawStripLevelsSetAll(const bool on)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return false;
   if(!DrawKindHasLevels(s_dsKind)) return false;
   DrawStripUndoPush();
   if(!on)
   {
      double vals[32]; color clrs[32]; int wds[32]; int sts[32]; string txts[32];
      int n = 0;
      return DrawStripLevelsRewrite(vals, clrs, wds, sts, txts, n);
   }
   //--- P-LVL-KEEP: "All levels on" is a UNION — the hand's customs (0.3, 88.6)
   //--- keep their own rows and colors; only the missing commons are appended in
   //--- the slot's look. The old shape rewrote the nine commons alone and silently
   //--- dropped every custom the user had added.
   double vals[32]; color clrs[32]; int wds[32]; int sts[32]; string txts[32]; int n = 0;
   DrawStripLevelsCollect(vals, clrs, wds, sts, txts, n);
   color c = (color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR);
   int w = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
   int st = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE);
   for(int i = 0; i < DrawStripLevelCommonCount() && n < 32; i++)
   {
      double cv = DrawStripLevelCommon(i);
      bool has = false;
      for(int j = 0; j < n; j++)
         if(MathAbs(vals[j] - cv) < 0.000001) { has = true; break; }
      if(has) continue;
      vals[n] = cv; clrs[n] = c; wds[n] = w; sts[n] = st; txts[n] = "";
      n++;
   }
   return DrawStripLevelsRewrite(vals, clrs, wds, sts, txts, n);
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
   //--- P-DRAW-74c: on a line the master's raw width is the DEMOTED 1 once stacked -
   //--- the copy takes the LOGICAL width (asked of the stack) and the sync below
   //--- re-forms the rows, or a 3 px line would clone as a 1 px dash.
   int duW = (int)ObjectGetInteger(0, s_dsObj, OBJPROP_WIDTH);
   if(duW <= DRAW_WIDTH_MIN && ObjectFind(0, PenStackName(s_dsObj, 0)) >= 0)
      duW = PenStackLogicalWidth(s_dsObj);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, duW);
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
      double vals[32]; color clrs[32]; int wds[32]; int sts[32]; string txts[32]; int n = 0;
      DrawStripLevelsCollect(vals, clrs, wds, sts, txts, n);
      ObjectSetInteger(0, nm, OBJPROP_LEVELS, n);
      for(int l = 0; l < n; l++)
      {
         ObjectSetDouble(0, nm, OBJPROP_LEVELVALUE, l, vals[l]);
         ObjectSetInteger(0, nm, OBJPROP_LEVELCOLOR, l, clrs[l]);
         ObjectSetInteger(0, nm, OBJPROP_LEVELWIDTH, l, wds[l]);
         ObjectSetInteger(0, nm, OBJPROP_LEVELSTYLE, l, sts[l]);
         //--- P-LVL-TEXT: the collected note rides its own value (source indices
         //--- shift past invalid rows, so re-reading by index would mis-glue them).
         ObjectSetString(0, nm, OBJPROP_LEVELTEXT, l, txts[l]);
      }
      FibPenSync(nm, false);   // P-DRAW-74b: the copy converges beside the copy
   }
   //--- P-DRAW-74c: a copied line re-forms its rows beside itself in the same pass,
   //--- so the clone never shows one frame as a bare 1 px dash before the open's
   //--- converge reaches it. Refuses non-pen kinds itself.
   PenStackSync(nm, false);
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
   //--- P-PAL-19 (2026-10-02) — A COLOUR CELL DOES NOT OPEN A BOARD. The strip used
   //--- to paint its own palette here (a second one, with its own catalogue, recents
   //--- and hex field) while every card opened `PalOpenKind`. It does not any more:
   //--- the tap leaves a REQUEST and the entry's bridge opens the cards' palette on
   //--- this drawing, so there is ONE palette in the product. The board code and its
   //--- objects go with the next step of the migration; until then the request is the
   //--- only thing this branch does, which is why it is the FIRST branch — a colour
   //--- slot must never reach the `HasPicker` grid below.
   if(DrawStripIsColorSlot(slot))
   {
      DrawStripPalAsk(slot);
      return true;
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
   //--- P-ANCHOR-LAST-MOVE (2026-10-22) — THE ONE SEAT WHOSE STATE IS NOT AN OBJECT
   //--- PROPERTY. It is the chart's own ATR-anchor switch, so it flips HERE instead of
   //--- riding `DrawStripWriteValue` — a write to a property the rectangle/trend line
   //--- does not have is the silent no-op this strip refuses (C-04). It sits before
   //--- the toggle branch for that reason, and it flushes: P-UI-131's law is that a
   //--- user action gets ONE unconditional redraw, never the paint's own `dirty` gate.
   if(slot == DRAW_SLOT_ANCHOR)
   {
      CalcAnchorSetOn(!g_calcAnchorOn);
      DrawStripDiagEmit("[drawstrip] ANCHOR on=" + IntegerToString(g_calcAnchorOn ? 1 : 0) +
                        " obj=\"" + s_dsObj + "\" at=" +
                        (g_calcAnchorTime > 0 ? TimeToString(g_calcAnchorTime, TIME_DATE | TIME_MINUTES)
                                              : (string)"live"));
      DrawStripPaint();
      //--- P-ANCHOR-LAST-MOVE: the SAME-PASS half. The ATR the switch changes is read
      //--- by the label/level/plan pass, which a bare `ChartRedraw` does not run — so
      //--- the press asks the ONE dispatcher the cards use (through the bridge above,
      //--- because BiotakKit is include 128 and this file is 99). One press, one full
      //--- refresh; a still frame asks nothing and pays nothing.
      DrawStripRefreshAsk();
      ChartRedraw();
      return true;
   }
   if(DrawStripIsToggle(slot))
   {
      DrawStripUndoPush();
      double tv = (DrawSlotRead(s_dsObj, slot) > 0.5) ? 0.0 : 1.0;
      DrawStripWriteValue(slot, tv);
      //--- DIAG-131 (2026-10-02): the tap names itself, the slot, and the value the
      //--- OBJECT now holds — and it goes through the FLUSHED channel
      //--- (`DrawStripDiagEmit`), not `Print`: MEASURED 2026-10-02, the Experts
      //--- journal stood at 08:47:07 for seven minutes while the user's clicks went
      //--- into MT4's RAM buffer (P-DRAW-126's own finding), so a witness written
      //--- with `Print` answers «nothing happened» long after the tap happened. The
      //--- layers/BACK cell was reported as «کارش درست انجام نمیشه» with nothing to
      //--- confirm or refute it, so the line carries the ONE fact that settles it:
      //--- the FILL slot's read-back beside the tapped slot's, plus whether the
      //--- interior child exists — a tap that moved the layer never touches either.
      DrawStripDiagEmit("[drawstrip] SLOT slot=" + IntegerToString(slot) +
                        " name=" + DrawStripSwitchName(s_dsObj, slot) +
                        " obj=\"" + s_dsObj + "\" -> " + DoubleToString(tv, 0) +
                        " read=" + DoubleToString(DrawSlotRead(s_dsObj, slot), 0) +
                        " fill=" + DoubleToString(DrawSlotRead(s_dsObj, DRAW_SLOT_FILL), 0) +
                        " child=" + IntegerToString(ObjectFind(0, FillChildName(s_dsObj)) >= 0) +
                        //--- DIAG-133: the DESCRIPTION ITSELF, quoted. P-UI-133 was fixed
                        //--- against a model of this string and the live box disagreed with
                        //--- the model (both marks still refused to clear), so the witness
                        //--- now carries the bytes the surgery runs on. One read, on the tap
                        //--- path only — the cost that matters is per-frame, and a tap is not
                        //--- a frame.
                        " desc=\"" + ObjectGetString(0, s_dsObj, OBJPROP_TEXT) + "\"");
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
      //--- P-UI-132 (2026-10-02): and the ORDER is the fix. The edge the hand drew is
      //--- remembered BEFORE the first step moves it, and the tap that switches the
      //--- travel OFF gives it back — «اکستند خاموش میکنم بر نمیگرده به حالت اول» is one
      //--- missing restore, and the 50 % line riding the stretched edge («50 درصد …
      //--- خاموش و روشن نمیشه چرا تداخل داره») stops riding the moment the edge is
      //--- given back. Both halves are the same two numbers, so the cost is one memo
      //--- write at the arming and one at the disarming, and nothing at all per frame.
      if(slot == DRAW_SLOT_EXTEND)
      {
         if(tv > 0.5) { BoxEdgeRememberGroup(); BoxExtendStepGroup(); }
         else          { BoxEdgeRestoreGroup(); }
      }
      //--- P-UI-131 (2026-10-02): P-DRAW-127's own law — «A user action gets one
      //--- unconditional flush; a paint pass never does» — was carried by the GEAR
      //--- branch below and missing HERE, on the branch that flips a cell's whole
      //--- face (the BACK/layers glyph is 15px art in a 26px seat, so its two states
      //--- also swap art, not only a chip). `DrawStripPaint` flushes only
      //--- `if(dirty)`, and the measured failure of relying on that (P-DRAW-127) is
      //--- «the object LIST is right and the PIXELS are one frame behind» — a cell
      //--- that reports the new state while the chart still shows the old one, which
      //--- to the user is a tap that did not happen. One flush, here, ends that.
      ChartRedraw();
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
      //--- P-UI-131: the pin's ONE line of code, and the one flush P-DRAW-127 asks
      //--- every user action for — the GEAR branch below has carried it since that
      //--- measurement, the pin never did. A toggle whose only visible proof is a
      //--- chip colour and a glyph swap is exactly the case the law names, so the
      //--- tap now says WHICH way it went (DIAG-131) as well as flushing.
      s_dsPinned = !s_dsPinned;
      DrawStripDiagEmit("[drawstrip] PIN " + (s_dsPinned ? "pinned" : "unpinned") +
                        " obj=\"" + s_dsObj + "\"");
      DrawStripPaint();
      ChartRedraw();
      return true;
   }
   if(a == DSTRIP_ACT_DIR)
   {
      //--- P-BK-111: THE CELL IS A CALL ON THE KNOT LAYER, so the call and the rebuild
      //--- are the same branch: the side is a published fact (the marker, the note's
      //--- caption, the family's colours), so a flip that does not repaint is a flip the
      //--- user cannot see. `BaseKnotSync` is the family's own owner for that reason.
      DrawStripClosePicker();
      string id = BaseKnotDirBoxFor(s_dsObj);
      if(id != "" && BaseKnotFlipDirection(id))
      {
         BaseKnotSync(id);
         DrawStripLayout();
         DrawStripPaint();
         ChartRedraw();   // P-DRAW-127: a user action flushes its own frame
      }
      //--- NOT A BASE BOX: the cell consumed the click and changed nothing, on purpose.
      //--- A refused action must not fall through to a neighbour's tap, and it must not
      //--- repaint either - there is nothing new on the chart to show.
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
         // P-UI-136: a segment in the bin takes its WHOLE path with it — one drawing,
         // one sweep. `continue` because the generic branch would delete the segment
         // alone and leave the rest of the polyline on the chart.
         if(DrawIsPathSeg(DrawSelAt(j))) { string tmpId = ""; if(PathIdOfName(DrawSelAt(j), tmpId)) PathDelete(tmpId, "strip bin"); continue; }
         BoxEdgeForget(DrawSelAt(j));   // P-UI-132: a deleted box spends its edge memo here, not by expiry
         BoxMarkDrop(DrawSelAt(j));   // P-UI-134: ...and so does its marks KEY
         FibPenSync(DrawSelAt(j), true);   // P-DRAW-74b: strays and the tag die with the object
      PenStackSync(DrawSelAt(j), true);   // P-DRAW-74c: the rows die with the line
         BoxMidDrop(DrawSelAt(j)); FillChildDrop(DrawSelAt(j)); ObjectDelete(0, DrawSelAt(j));
      }
   }
   else if(s_dsObj != "")
   {
      if(DrawIsHRay(s_dsObj)) HRayDelete(s_dsObj, "strip bin");   // P-HR-04
      // P-UI-136: and the single held object is a segment — the whole path goes.
      else if(DrawIsPathSeg(s_dsObj)) { string tmpId = ""; if(PathIdOfName(s_dsObj, tmpId)) PathDelete(tmpId, "strip bin"); }
      else { BoxEdgeForget(s_dsObj); BoxMarkDrop(s_dsObj); FibPenSync(s_dsObj, true); PenStackSync(s_dsObj, true); BoxMidDrop(s_dsObj); FillChildDrop(s_dsObj); ObjectDelete(0, s_dsObj); }
   }
   DrawStripClose();
   ChartRedraw();
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
      //--- DIAG-139 (2026-10-18) — A LEVEL ROW HAD NO WITNESS OF ITS OWN. «لول دلخواه
      //--- اضافه/حذف نمیشه» cannot be told from a tap that never reached the row, and
      //--- the silent `return false` below drew no line either. The arrival, the
      //--- popover's own row count and the value the row read back ride ONE flushed
      //--- line (P-LOG-3: DrawStripDiagEmit, never Print).
      DrawStripDiagEmit("[drawstrip] LVLPICK obj=\"" + s_dsObj + "\" row=" + IntegerToString(row) +
                        " pn=" + IntegerToString(s_dsPN) + " v=" +
                        (MathIsValidNumber(v) ? DrawStripLevelName(v) : "EMPTY"));
      if(!MathIsValidNumber(v)) return false;
      DrawStripLevelsToggle(v);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   DrawStripPickApply(s_dsPicker, row);
   // DIAG-137 (2026-10-03) — EVERY tap leaves its number: slot, row, object and
   // the read-back. A control that paints but never writes («هرچی ضخیم تر
   // انتخاب میکنم تاثییری نداره») is otherwise indistinguishable from a paint
   // that ignores the write. The tap IS the event, so there is no dirty-only.
   if(s_dsPicker != DSTRIP_MORE && s_dsPicker != DSTRIP_SLOT_LEVELS)
   {
      // DIAG-138 (2026-10-03) — the tag ITSELF joins the line: lk/gi parsed value
      // beside haslk/raw search tells a failed drop (haslk=1) from a misread.
      string ptxt = ObjectGetString(0, s_dsObj, OBJPROP_TEXT);
      int plk = FibPenLookGet(s_dsObj);
      DrawStripDiagEmit("[drawstrip] PICK slot=" + IntegerToString(s_dsPicker) +
                        " row=" + IntegerToString(row) + " obj=\"" + s_dsObj +
                        "\" read=" + DoubleToString(DrawSlotRead(s_dsObj, s_dsPicker), 0) +
                        " lk=" + IntegerToString(plk) +
                        " haslk=" + (StringFind(ptxt, FIBPEN_LK) >= 0 ? "1" : "0"));
   }
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
      DrawStripTplApplyGroup(arg);
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(kind == DSTRIP_MK_TPLNAV)
   {
      //--- P-DRAW-132: the rack REPEATS — the page after the last is the first, so
      //--- one row walks every template without a second control. The popover stays
      //--- open on the new page (the layout rebuilds its rows, GearA's builder).
      int n = DrawTplCount(s_dsKind);
      int pages = (n <= 0 ? 1 : (n + DRAW_TPL_PAGE - 1) / DRAW_TPL_PAGE);
      s_dsTplPage[s_dsKind] = (s_dsTplPage[s_dsKind] + 1) % pages;
      DrawStripLayout();
      DrawStripPaint();
      ChartRedraw();   // P-UI-131: a user action flushes its own frame
      DrawStripDiagEmit("[drawstrip] TPLNAV obj=\"" + s_dsObj + "\" page=" +
                        IntegerToString(s_dsTplPage[s_dsKind] + 1) + "/" + IntegerToString(pages));
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
      DrawStripTplNameFocus();   // P-DRAW-131: the field opens FOCUSED — type the name, Enter
      return true;
   }
   if(kind == DSTRIP_MK_DUPE) return DrawStripDuplicate();
   if(kind == DSTRIP_MK_BOX50)
   {
      bool mid = false; int ext = BOXEXT_OFF, n = 0;
      BoxMarkRead(s_dsObj, mid, ext, n);
      //--- DIAG-134: the 50 % row reads the mark, flips it, and answers with the mark
      //--- AFTER the write plus whether the line object exists — the exact fact that
      //--- failed three times over («50 درصد … چرا تداخل داره»), now settled by one read.
      BoxMarkWrite(s_dsObj, !mid, ext, n);
      BoxMidSync(s_dsObj);
      bool am = false; int ae = BOXEXT_OFF, an = 0;
      BoxMarkRead(s_dsObj, am, ae, an);
      DrawStripDiagEmit("[drawstrip] BOX50 name=\"" + s_dsObj + "\" " +
                        (mid ? "on->off" : "off->on") + " read=" +
                        DoubleToString((am ? 1.0 : 0.0), 0) + " line=" +
                        IntegerToString(ObjectFind(0, BoxMidName(s_dsObj)) >= 0) +
                        " ext=" + IntegerToString(ae));
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      ChartRedraw();   // P-UI-131: the 50 % is the cell the user watches for its own frame
      return true;
   }
   if(kind == DSTRIP_MK_BOXEXT)
   {
      //--- DIAG-134 (2026-10-02) — THE OTHER TWO DOORS ANSWER TOO. DIAG-131 witnessed the
      //--- quick cell, and it is what finally closed the 50 % / EXTEND report — but the
      //--- cycle and the gear switch were fixed on the SAME DAY with NO witness, which is
      //--- exactly how a fix can be wrong and still look green. A witness is cheap on a
      //--- tap (the cost that matters is per-frame) and it is the only thing that makes
      //--- the NEXT report answerable without a reproduction round-trip. Read BEFORE, so
      //--- the line names the mode it walked FROM as well as the one it landed on, and
      //--- the memo slot, so «extend off did not come back» is settled by the memo.
      bool bmid = false; int bext = BOXEXT_OFF, bn = 0;
      BoxMarkRead(s_dsObj, bmid, bext, bn);
      string was = BoxExtText(s_dsObj);
      BoxExtCycle(s_dsObj);
      //--- P-DRAW-64c: the cycle may have armed TOUCH/END/NBARS — the first step is
      //--- still the tap's, so the edge moves in this frame even when the next bar is
      //--- an hour away. A cycle that landed on OFF is a no-op here by construction.
      BoxExtendStep(s_dsObj);
      DrawStripDiagEmit("[drawstrip] BOXEXT name=\"" + s_dsObj + "\" from=\"" + was +
                        "\" to=\"" + BoxExtText(s_dsObj) + "\" memo=" +
                        IntegerToString(BoxEdgeSlot(s_dsObj)));
      DrawStripClosePicker();
      DrawStripLayout();
      DrawStripPaint();
      ChartRedraw();   // P-UI-131: ...and the edge it just moved is the visible half
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
//--- P-DRAW-134 (2026-10-18) — the template row's ✕, the delete door the user
//--- ordered visible («شیبف کلکی بردار بجاش یک دکمه حذف برای هر کدوم بزار»). The
//--- delete itself is the ONE body (`DrawStripTplRowDelete`, DrawStrip_Paint.mqh);
//--- this door adds the two facts a list mutation owes its popover: the rows moved
//--- up, so the layout REBUILDS the seats (the page, the count, every row below)
//--- and the paint shows it in the same frame. The popover STAYS OPEN — deleting
//--- the next one is the gesture the user just learned, not a re-open.
bool DrawStripPickTapDel(const int row)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(s_dsPicker != DSTRIP_MORE || row < 0 || row >= s_dsPN) return false;
   if(s_dsMoreKind[row] != DSTRIP_MK_PRESET) return false;
   if(!DrawStripTplRowDelete(s_dsMoreArg[row])) return false;
   DrawStripLayout();
   DrawStripPaint();
   ChartRedraw();   // P-UI-131: a user action flushes its own frame
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
   //--- the preview block and the `+` are the SAME act: the palette on this role. The
   //--- strip keeps ONE picker at a time (DrawStripTap does exactly this for a
   //--- quick-row colour cell), so the panel steps aside for the popup it opens — and
   //--- P-PAL-19: for a COLOUR role that popup is the CARDS' palette, through the same
   //--- request/bridge as the quick cell. Two doors, one act, one palette.
   if(gk == DSTRIP_GRG_PREV || gk == DSTRIP_GRG_PLUS)
   {
      DrawStripGearClose();
      if(DrawStripIsColorSlot(slot))
      {
         DrawStripPalAsk(slot);
         return true;
      }
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
      //--- P-UI-132 addendum: and it is the SAME cell, so it carries the same memo. This
      //--- row armed the mode and moved the edge with no memo written, and its disarm
      //--- half had nothing to restore from — the strip row was fixed and the gear row
      //--- left holding the defect, which is how a fix reads as «sometimes works». One
      //--- remember, one restore, both group fan-outs (the group here is the whole
      //--- multi-selection, exactly as above).
      if(arg == DRAW_SLOT_EXTEND)
      {
         if(tv > 0.5) { BoxEdgeRememberGroup(); BoxExtendStepGroup(); }
         else          { BoxEdgeRestoreGroup(); }
      }
      //--- DIAG-134: the gear switch is the same cell as the quick one and it gets the
      //--- same witness, for the same reason — it is one of the three doors into EXTEND,
      //--- and it is the door a report names least often while being the one a fix is
      //--- most likely to have missed. The memo slot is the fact that settles «the box
      //--- never came back»: armed must leave a memo, a disarm must leave none.
      if(arg == DRAW_SLOT_EXTEND)
         DrawStripDiagEmit("[drawstrip] GEAREXT name=\"" + s_dsObj + "\" -> " +
                           DoubleToString(tv, 0) + " read=" +
                           DoubleToString(DrawSlotRead(s_dsObj, arg), 0) + " memo=" +
                           IntegerToString(BoxEdgeSlot(s_dsObj)));
      ChartRedraw();   // P-UI-131: a user action flushes its own frame
      return true;
   }

   if(kind == 2)
   {
      DrawStripTplApplyGroup(arg);
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
      DrawStripTplNameFocus();   // P-DRAW-131: the second door focuses the field the same way
      return true;
   }
    if(kind == DSTRIP_GRK_TPLNAV)
    {
      //--- P-DRAW-132: the Look tab's page walk — the same repeat-the-list turn the
      //--- more-popover's nav row takes, on the tab's own row list.
      int n = DrawTplCount(s_dsKind);
      int pages = (n <= 0 ? 1 : (n + DRAW_TPL_PAGE - 1) / DRAW_TPL_PAGE);
      s_dsTplPage[s_dsKind] = (s_dsTplPage[s_dsKind] + 1) % pages;
      DrawStripLayout();
      DrawStripPaint();
      ChartRedraw();   // P-UI-131: a user action flushes its own frame
      DrawStripDiagEmit("[drawstrip] TPLNAV obj=\"" + s_dsObj + "\" page=" +
                        IntegerToString(s_dsTplPage[s_dsKind] + 1) + "/" + IntegerToString(pages));
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
   //--- P-DRAW-133 (2026-10-18): a stray `return true;` stood HERE and made every rung
   //--- below it unreachable — kinds 5/6/7/8 (the level-set rows, the slot-visibility
   //--- rows, the default-learn row, the glyph rows) compiled, painted and hit-tested
   //--- perfectly and answered nothing: a painted control is not a working one
   //--- (P-DRAW-84's law, one panel over). Gone — every kind the builders emit has a
   //--- live branch from here down.
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
      //--- P-UI-176 (2026-10-20): the MERGED colour seat is ONE cell for TWO
      //--- roles (P-DRAW-64a): the quick row folds COLOR into FILLCLR and the
      //--- cell is visible while EITHER role is on. So the row is one control for
      //--- one cell: its switch reads the CELL and its press flips the CELL, both
      //--- roles together. Two rows for one cell was the lie - the switch showed
      //--- a state the row did not have, and hiding one role never hid the cell.
      bool merged = (seat == DRAW_SLOT_FILLCLR) && DrawStripMergedColor(s_dsKind);
      if(merged)
      {
         bool cellOn = DrawStripSeatVis(s_dsKind, seat, true);
         s_dsVis[s_dsKind][DRAW_SLOT_FILLCLR] = !cellOn;
         s_dsVis[s_dsKind][DRAW_SLOT_COLOR]   = !cellOn;
      }
      else
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
//--- P-LVL-COLOR — ONE LEVEL'S SWATCH. The row's chip shows the ink that level
//--- wears; tapping it opens the cards palette on that STORED level (same popup
//--- as every color cell, P-PAL-19). A row whose level is not on the chart has
//--- no ink to edit, so its swatch is the same act as the row: add it.
bool DrawStripGearLevelColorTap(const int r)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(r < 0 || r >= s_dsGRN) return false;
   if(s_dsGRKind[r] != 4) return DrawStripGearRowTap(r);
   if(!DrawKindHasLevels(s_dsKind)) return false;
   double v = DrawStripGearLevelAt(s_dsGRArg[r]);
   if(!MathIsValidNumber(v)) return false;
   int idx = DrawStripLevelFind(s_dsObj, v);
   if(idx < 0)
   {
      DrawStripLevelsToggle(v);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   DrawStripDiagEmit("[drawstrip] LVLCOLOR obj=\"" + s_dsObj + "\" level=" +
                     IntegerToString(idx) + " v=" + DrawStripLevelName(v));
   DrawStripPalAskLevel(DRAW_SLOT_COLOR, idx);
   return true;
}
//--- P-LVL-TEXT — ONE LEVEL'S LABEL ZONE. Arms the e4 note field on that STORED
//--- level, seeded with what it wears; a re-arm on another row drops the field
//--- so it is reborn with the new seed instead of keeping the old row's word.
//--- A row whose level is not on the chart has nothing to note: same as toggle.
bool DrawStripGearLevelDescTap(const int r)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(r < 0 || r >= s_dsGRN || s_dsGRKind[r] != 4) return DrawStripGearRowTap(r);
   if(!DrawKindHasLevels(s_dsKind)) return false;
   double v = DrawStripGearLevelAt(s_dsGRArg[r]);
   if(!MathIsValidNumber(v)) return false;
   int idx = DrawStripLevelFind(s_dsObj, v);
   if(idx < 0)
   {
      DrawStripLevelsToggle(v);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   if(s_dsLvlDescArmed && (s_dsLvlDescObj != s_dsObj || s_dsLvlDescIdx != idx))
      ObjectDelete(0, DrawStripEditName(4));
   s_dsLvlDescArmed = true; s_dsLvlDescObj = s_dsObj; s_dsLvlDescIdx = idx;
   DrawStripDiagEmit("[drawstrip] LVLDESC obj=\"" + s_dsObj + "\" level=" +
                     IntegerToString(idx) + " v=" + DrawStripLevelName(v));
   DrawStripLayout();
   DrawStripPaint();
   if(ObjectFind(0, DrawStripEditName(4)) >= 0)
      ObjectSetInteger(0, DrawStripEditName(4), OBJPROP_STATE, true);
   return true;
}
//--- gear foot: Reset / All / Copy. P-DRAW-78: `Del` is retired from the panel —
//--- the strip's own command group already carries a trash cell, so this was a
//--- second, unconfirmed way to destroy the drawing. The head's X is the close.
//--- P-DRAW-90 (2026-09-30): `Reset` is the design's own first command (the third
//--- seat the panel was missing) — it puts THIS drawing back on its kind's first
//--- template, row 0 (`DrawTplApply`; P-DRAW-132: the rack is seeded on a first run,
//--- so row 0 exists for every kind the user has not emptied), and it is UNDOABLE
//--- like every other look change (DrawStripUndoPush, the same single-step undo the
//--- more-popover's template rows push). `All` keeps its own action, one seat right;
//--- `Copy` is the third. One action per seat, and the seat's glyph now matches it.
bool DrawStripFootTap(const int f)
{
   if(!s_dsOpen || s_dsObj == "") return false;
   if(f == 0)
   {
      DrawStripUndoPush();
      DrawTplApply(s_dsObj, 0);
      //--- P-DRAW-96 (2026-09-30): `DrawTplApply` writes DRAW_SLOT_COLOR, so it owes
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
   //--- P-DRAW-131: a header tap FOLDS or SWITCHES the body away, and the armed
   //--- name field dies with it — so the pending save commits HERE, before the
   //--- group changes, while the field still holds the user's own word.
   DrawStripTplCommit("group");
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
//--- P-UI-146 (2026-10-13) — THE RESTORE'S ONE DOOR. The saved gear tab is
//--- re-opened by the SAME sequence a group tap runs (set the group, keep or
//--- drop its collapse, layout, paint, dump) — defined HERE, in the strip's own
//--- tap owner, because a repaint from outside the strip is a REQUEST the
//--- bridge spends (P-PAL-19f/P-PAL-20): the restore asks the strip to restore
//--- itself, it never paints someone else's surface. Called once, on the first
//--- tick after a fresh attach, by `DrawStripStateRestore` (BiotakPanels_Life).
void DrawStripGearRestoreTab(const int gid, const bool collapsed)
{
   if(!s_dsOpen || gid <= 0) return;
   s_dsGear = gid;
   s_dsGearCollapsed = collapsed;
   DrawStripLayout();
   DrawStripPaint();
   DrawStripGearDiagDump();
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
      //--- P-LVL-SCALE: typed percent rides /100 ("88.6" -> 0.886); a typed ratio
      //--- rides as-is ("0.5" -> 0.5). Guard is the ratio band now, not percent.
      double v = DrawStripLevelNorm(StringToDouble(t));
      if(!MathIsValidNumber(v) || v < -10.0 || v > 10.0) return true;
      if(DrawStripLevelFind(s_dsObj, v) >= 0) return true;
      DrawStripUndoPush();
      double vals[32]; color clrs[32]; int wds[32]; int sts[32]; string txts[32]; int n = 0;
      DrawStripLevelsCollect(vals, clrs, wds, sts, txts, n);
      if(n >= 32) return true;
      vals[n] = v;
      clrs[n] = (color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR);
      wds[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
      sts[n] = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE);
      txts[n] = "";
      n++;
      DrawStripLevelsRewrite(vals, clrs, wds, sts, txts, n);
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
   //--- P-LVL-TEXT: the armed note commits onto its stored level (Enter). Empty
   //--- clears the note back to the value alone. Undoable like every look write.
   if(e == 4 && s_dsGear == DSTRIP_GEAR_LEVELS && DrawStripLvlDescWant())
   {
      string nt = txt;
      StringTrimLeft(nt); StringTrimRight(nt);
      if(StringLen(nt) > 63) nt = StringSubstr(nt, 0, 63);   // contract §2: object text truncates at 63
      DrawStripUndoPush();
      ObjectSetString(0, s_dsObj, OBJPROP_LEVELTEXT, s_dsLvlDescIdx, nt);
      s_dsLvlDescArmed = false;
      DrawStripDiagEmit("[drawstrip] LVLTEXT obj=\"" + s_dsObj + "\" level=" +
                        IntegerToString(s_dsLvlDescIdx) + " text=\"" + nt + "\"");
      DrawStripLayout();
      DrawStripPaint();
      ChartRedraw();   // P-UI-131: the line the user watches re-inks in its own frame
      return true;
   }
   if(e == 2 && DrawKindOf(s_dsObj) == DK_TEXT)
   {
      ObjectSetString(0, s_dsObj, OBJPROP_TEXT, txt);
      ChartRedraw();
      return true;
   }
   // P-DRAW-25: the armed save commits under the typed name (empty keeps the
   // "My N" fallback inside DrawTplSaveAs). The file write is the commit.
   // P-DRAW-131: Enter is ONE door into the same commit every exit uses — one
   // owner for the write, so «clicked away» and Enter cannot drift apart.
   if(e == 3 && s_dsGear == DSTRIP_GEAR_TPL && s_dsTplNameArmed)
   {
      DrawStripTplCommit("enter");
      DrawStripLayout();
      DrawStripPaint();
      return true;
   }
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
      mx >= hx && mx <= hx + s_dsGearW0 - DSTRIP_GEAR_PAD - DSTRIP_GEAR_XW - DSTRIP_GEAR_PAD) return true;
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
   //--- P-PAL-21: the BOARD's own header clause is retired with the board
   //--- (`s_dsBW/s_dsBH` are 0 at every write, so the clause never fired).
   return 0;
}
#endif // DRAW_STRIP_TAP_MQH
