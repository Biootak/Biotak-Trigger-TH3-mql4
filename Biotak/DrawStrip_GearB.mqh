// DrawStrip_GearB.mqh - DrawStrip split 2026-09-29: exact lines 3365-4406 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_GEARB_MQH
#define DRAW_STRIP_GEARB_MQH


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
#endif // DRAW_STRIP_GEARB_MQH
