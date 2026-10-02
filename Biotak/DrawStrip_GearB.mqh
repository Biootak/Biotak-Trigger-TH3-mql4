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
//--- P-DRAW-112 (2026-10-01) — THE CENSUS WALKS THE WHOLE PANEL, AND A LABEL IS
//--- AN OBJECT WITH A BOX. User report on the Style tab: «تب استایل که میزنم اینطوری
//--- میشه، خود تب و دکمه حذف و غیره دیده نمیشه» — the head (title, version, close),
//--- the tab row, the foot and three of the four band CAPTIONS are gone, while the
//--- chips, the rows, the band dots and the count pills are all there. The census
//--- above could not have answered it: its band was the TAB ROW only, and its
//--- `else continue` threw away OBJ_LABEL — the caption labels, the head title, the
//--- foot words, every one of the missing names. So the band is the panel's own rect
//--- and a label's own text/colour/z is printed with it. Bounded: one walk per panel
//--- OPEN (never per paint), the call site is unchanged.
//--- P-DRAW-123 (2026-10-01) — WHAT THE PAINT DID, BESIDE WHAT THE TERMINAL HOLDS.
//--- The report («این هنوز درست نشده», a shot of the open Stroke tab with the SHAPE
//--- and LAYER captions plus `Behind candles`/`Look`/`Row` painted while both other
//--- band captions, the `50 % line`/`Extend right`/`Lock` names, every chip and the
//--- whole left column were bare) could only be closed by EYE, and that is the cost
//--- this closes: the census answers "what does the chart hold", and it answered it
//--- CORRECTLY for every object the screen did not show in the P-DRAW-120 case. What
//--- was missing is the OTHER half — what the paint INTENDED — in a form a machine can
//--- diff. So while `s_dsDiagArm` is set, the four writers every panel object goes
//--- through (label, face, rect, button) each print one `[dsdiag] EXPECT` line with the
//--- object's own name, role, seat, layer and text, at the moment they place it.
//--- This is the paint's OWN numbers — not a second table recomputed here — so a
//--- divergence is always the terminal's doing.
#ifdef DSTRIP_DIAG
bool s_dsDiagArm = false;   // P-DRAW-123: the dump's own one-paint latch
#endif
void DrawStripDiagExpect(const string nm, const string role, const int x, const int y,
                         const int w, const int h, const int z, const string txt)
{
   #ifdef DSTRIP_DIAG
   if(!s_dsDiagArm) return;
   //--- P-DRAW-126: same line, but through the flushed channel, so the reader
   //--- never has to wait for the terminal's own buffer (see DrawStripDiagEmit).
   DrawStripDiagEmit("[dsdiag] EXPECT obj=" + nm + " role=" + role +
                     " xywh=" + IntegerToString(x) + "," + IntegerToString(y) + "," +
                     IntegerToString(w) + "," + IntegerToString(h) +
                     " z=" + IntegerToString(z) + " txt=\"" + txt + "\"");
   #endif
}

void DrawStripGearTabCensus()
{
   if(s_dsGear == 0 || s_dsGearW0 <= 0) return;
   int bx0 = s_dsGEX, bx1 = s_dsGEX + s_dsGearW0;
   int by0 = s_dsGEY, by1 = s_dsGEY + s_dsGearH;   // P-DRAW-112: the WHOLE plate
   DrawStripDiagEmit("[drawstrip] CENSUS rect=" + IntegerToString(bx0) + "," + IntegerToString(by0) + "," + IntegerToString(s_dsGearW0) + "," + IntegerToString(s_dsGearH) + " chart=" + IntegerToString((int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS)) + "x" + IntegerToString((int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS)));   // P-LOG-7: the frame a corner-bound reader needs
   DrawStripDiagSnapRect(bx0, by0, bx1, by1);   // P-LOG-8: the AFTER walk bounds its NEW scan by it
   int n = ObjectsTotal(0, -1);
   for(int oi = 0; oi < n; oi++)
   {
      string on = ObjectName(0, oi, -1);
      if(on == "") continue;
      //--- P-DRAW-124 (2026-10-01) — THE CENSUS WALKS THE STRIP'S WHOLE FAMILY, NOT
      //--- THE GEAR'S OWN NAMES. P-DRAW-112 scoped it to `PnlDrawS_G*` — "this panel
      //--- only" — and that scope is the one blind spot the live hunt needed: the
      //--- objects that can HIDE this panel's ink are exactly the ones the prefix
      //--- threw away. MEASURED (2026-10-01 18:42:35, the report «این هنوز درست نشده»):
      //--- the chart carried `PnlDrawS_GT0..GT3` / `GTrack` (the RETIRED tab family,
      //--- P-DRAW-117) and `PnlDrawS_GE0/GE4` (the retired fields) — none of them
      //--- this build's, none of them in a census that could answer "who is on top".
      //--- P-LOG-7 (2026-10-01) — NO NAME FILTER AT ALL. P-DRAW-124 widened the net to
      //--- `PnlDrawS_`, which still drops every object that is NOT this family — and a
      //--- cover that hides this panel's ink is, by definition, not this panel's; the
      //--- box test below still bounds the walk to the panel's own rect.
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
      {   //--- P-LOG-6: the OBJECT's own size; the resource table read 0 for the plate.
         ow = DrawStripCensusSize(on, oty, 0); oh = DrawStripCensusSize(on, oty, 1);
      }
      else DrawStripCensusAnyBox(on, oty, ox, oy, ow, oh);   // P-LOG-7/8c: a foreign TYPE too — and a chart object's box is its TIME/PRICE anchors
      //--- P-LOG-6: the box the walk tests is the object's OWN box (see
      //--- DrawStripCensusInPanel) — the plate starts 14px outside this rect.
      if(!DrawStripCensusInPanel(on, oty, ox, oy, bx0, by0, bx1, by1)) continue;
      color bg = (color)ObjectGetInteger(0, on, OBJPROP_BGCOLOR);
      int zz = (int)ObjectGetInteger(0, on, OBJPROP_ZORDER);
      //--- P-DRAW-89: the TRACK's tone, printed. It is the one surface on the tab
      //--- band whose colour is COMPUTED rather than a constant, so it is the one
      //--- that can disagree with the four tabs beside it (measured: they read
      //--- 2892317 and it read -16924895 = 0xFEFDBF21). Reading the value back out
      //--- of the object is the fact; recomputing it here would be the guess.
      //--- P-DRAW-117: the track's tone probe went with the track — the census below
      //--- already prints every object's own `bgcolor`, and the retired `GTrack` is
      //--- not a surface this build paints (it is swept, not measured).
      int tone = -1;
      //--- P-DRAW-112 + P-LOG-5: a caption carries its answer in TEXT and COLOR,
      //--- not in a box — and a BUTTON is captioned too (see DrawStripCensusInk).
      string ink = DrawStripCensusInk(on, oty);
      //--- P-DRAW-120: THE FOUR PROPERTIES THAT DECIDE WHETHER MT4 DRAWS IT AT ALL.
      //--- The census carried xywh + bgcolor + z + the label's ink, and the 2026-10-01
      //--- 15:18 report could not be closed with those: every missing object read
      //--- CORRECT here while the screen showed a bare plate (see DrawStripFaceZ).
      //--- `back` is the layer MT4 draws it in (a background object hides under the
      //--- plate), `fnt` a label's point size (0 draws nothing), `tf` its period mask
      //--- (a LABEL-only property per the contract — OBJ_NO_PERIODS draws nothing) and
      //--- `bmp` the face a bitmap label actually resolved, which is the one thing a
      //--- hot reload can break under a name that still exists. Four reads per object,
      //--- on the panel's OPEN only.
      string bmpf = "";
      if(oty == OBJ_BITMAP_LABEL)
         bmpf = ObjectGetString(0, on, OBJPROP_BMPFILE, 0);
      //--- P-DRAW-124: AND THE ONE NUMBER THE TERMINAL DECIDES ITSELF. Two objects on
      //--- the SAME rung are drawn in the terminal's OWN list order — the index this
      //--- walk is already standing on (`oi`), i.e. the order MT4 holds them in. The
      //--- z decides first, the index decides a tie, so `z` alone can never say which
      //--- of two equal-rung objects the screen shows: BOTH the intruder and the ink
      //--- read the same rung and the same seat, and only the index separates them.
      //--- MEASURED on the 15:18 and 18:42 reports: every hidden object's z/back/fnt
      //--- read CORRECT — the tie is the whole story, and it was the one column the
      //--- census did not carry. `tf` reads 0 for every object of this family, shown
      //--- or not, so a reader must NOT translate it into OBJ_NO_PERIODS. P-DRAW-126:
      DrawStripDiagEmit("[drawstrip] TABCENSUS idx=" + IntegerToString(oi) + " obj=" + on +
            " type=" + IntegerToString(oty) + " xywh=" + IntegerToString(ox) + "," +
            IntegerToString(oy) + "," + IntegerToString(ow) + "," + IntegerToString(oh) +
            " bgcolor=" + IntegerToString((int)bg) + " tone=" + IntegerToString(tone) +
            " z=" + IntegerToString(zz) +
            " back=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_BACK)) +
            " fnt=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_FONTSIZE)) +
            " tf=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_TIMEFRAMES)) +
            " bmp=\"" + bmpf + "\" ink=" + ink +
            " win=" + IntegerToString(ObjectFind(0, on)) +            " corner=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_CORNER)) + " font=\"" + ObjectGetString(0, on, OBJPROP_FONT) + "\" anch=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_ANCHOR)) +
            " xof=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_XOFFSET)) + " yof=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_YOFFSET)) + " bord=" + IntegerToString((int)ObjectGetInteger(0, on, OBJPROP_BORDER_COLOR)));
   // P-LOG-7
      DrawStripDiagSnapAdd(on, ox, oy, ow, oh, zz, (int)ObjectGetInteger(0, on, OBJPROP_BACK));   // P-LOG-8
   }
}
//--- P-DRAW-123: THE DUMP — the paint declares, then the chart answers. Arm, repaint
//--- (the panel's own painter, so the declaration and the census describe ONE state),
//--- disarm, then walk. Called from the two user actions that change the state (panel
//--- open, group open/switch) — the census's own bound — and with the `DSTRIP_DIAG`
//--- line commented out it is the census alone, so the switch turns off without
//--- touching a call site (`#ifdef`: the tree's own idiom — `#if <expr>` is not MQL4).
void DrawStripGearDiagDump()
{
   #ifdef DSTRIP_DIAG
   //--- P-DRAW-125 (2026-10-01) — THE DUMP REPAINTS ONLY WHAT IS OPEN.
   //--- MEASURED (2026-10-01 19:25:07.379): this function is called from
   //--- `DrawStripActTap` on the GEAR button, and that path runs on the CLOSE too —
   //--- `DrawStripGearClose()` sets `s_dsGear = 0` and this call follows. The
   //--- unguarded `DrawStripGearPaint()` below then ran with `s_dsGRN = s_dsGGN =
   //--- s_dsGearSecN = 0` (the layout cannot have built a shut panel): it DELETED
   //--- every grid, section and row object of the panel — and, because the head and
   //--- the foot are painted unconditionally, it left the HEAD and the FOOT of a
   //--- closed panel standing on the chart, drawn from the stale origin. The log
   //--- carries that frame in full: `[dsdiag] EXPECT` for `GHTB..GHXI` and
   //--- `GF0..GF2T` — twenty objects, head then foot, nothing between them.
   //--- The diagnostic must never move a pixel the product would not: one guard on
   //--- the panel's own open fact, and a shut dump is the census alone (which
   //--- returns by itself when `s_dsGear == 0`).
   if(s_dsGear != 0 && s_dsGearH > 0)
   {
      s_dsDiagArm = true; s_dsDiagAfter = 1;   // P-LOG-8: the NEXT paint pass re-walks this name list
      DrawStripGearPaint();
      s_dsDiagArm = false;
   }
   #endif
   DrawStripGearTabCensus();
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
        ObjectDelete(0, DrawStripIconName(i) + "R");    // P-DRAW-64a2: ...and the merged seat's BORDER bar
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
   DrawStripSurfaceClear();  // P-PAL-20: owns no popup pixels either — the ledger dies with its owner
    s_dsPicker = DSTRIP_PICK_NONE;   // the popover dies with the strip
    s_dsPN = 0;                      // (the recent colours survive: they are the trader's)
    s_dsPHexY = -1;
    s_dsPHeadY = -1;
    s_dsPOpY = -1;
    s_dsOpGrab = false;
    s_dsHexFocus = false;
    //--- P-PAL-21: the board's chrome prune is gone with the board.
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
   DrawStripForeign(nm, OBJ_BUTTON);   // P-DRAW-125: a name of another type is not mine
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
   DrawStripDiagExpect(nm, "btn", x, y, w, h, z, txt);
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
   DrawStripForeign(nm, OBJ_BITMAP_LABEL);   // P-DRAW-125: the type, not the name
   int made = 0;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_BITMAP_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, z);
      made = 1;
   }
   bool dirty = (made > 0);   // P-DRAW-125: a birth IS a change, whatever the defaults read
   //--- P-DRAW-120 (2026-10-01) — THE TWO PROPERTIES THAT DECIDE WHETHER MT4 DRAWS
   //--- THIS FACE ARE RE-ASSERTED EVERY PAINT, NOT ONLY AT BIRTH.
   //--- MEASURED on the 2026-10-01 15:18 shot (EURUSD,M5, src 729d3b567d3dd197): the
   //--- terminal held every object of the open Stroke tab at its right seat with the
   //--- right ink — TABCENSUS read `GR2T "50 % line":14865611 z=1442`, `GS0T
   //--- "STROKE"`, the chip/icon faces, the head, the foot — while the SCREEN showed
   //--- 31 of those 104 (tools/tmp-measure-shot.py), the whole left column, the head
   //--- and the foot bare plate. The
   //--- one difference the painters had between those 21 and the rest: `DrawStripBtnZ`
   //--- re-asserts `OBJPROP_ZORDER` every paint (P-DRAW-48's own law, GearB:213) and
   //--- the FACE and LABEL painters only ever wrote it inside their `ObjectFind < 0`
   //--- block — so a face or a label born under an older rung keeps that rung for the
   //--- life of the object, and equal z is settled by CREATION ORDER (P-DRAW-48), which
   //--- no later build can reach. Same heal, same owner: the write is compare-guarded,
   //--- so a still frame still costs two reads per face and touches nothing.
   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);
   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);
   int pw = DrawStripResW(res), ph = DrawStripResH(res);
   dirty |= DrawStripSetStr(nm, OBJPROP_BMPFILE, res);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x + (w - pw) / 2);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y + (h - ph) / 2);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   DrawStripDiagExpect(nm, "bmp", x, y, w, h, z, res);
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
   //--- P-DRAW-124/125 — A LABEL THAT IS NEVER BORN LEAVES NO TRACE, and a label born
   //--- of ANOTHER TYPE paints nothing either. One reader answers both: the type check.
   DrawStripForeign(nm, OBJ_LABEL);
   int made = 0;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0))
      {
         //--- P-DRAW-124: name the one silent path in the label's own birth, once a
         //--- session, with the terminal's error (P-DRAW-73's one-shot idiom).
         static bool saidLblBirth = false;
         if(!saidLblBirth)
         {
            saidLblBirth = true;
            Print("[drawstrip] label birth failed obj=", nm, " err=", GetLastError());
         }
         return false;
      }
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_STRIP_OVER);
      made = 1;
   }
   bool dirty = (made > 0);   // P-DRAW-125: a birth IS a change
   //--- P-DRAW-120: the same heal for the ink. A label born under an older rung (or
   //--- behind the plate after the wide pass moved its row into the second column)
   //--- kept that rung forever, and its TEXT/COLOUR/ZORDER reads in TABCENSUS stayed
   //--- correct while the screen never painted it. Two compare-guarded writes.
   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, Z_STRIP_OVER);
   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, inkTop);
   dirty |= DrawStripSetInt(nm, OBJPROP_COLOR, ink);
   dirty |= DrawStripSetInt(nm, OBJPROP_FONTSIZE, PnlPt(pt));
   dirty |= DrawStripSetStr(nm, OBJPROP_FONT, BioChromeFont(bold));
   dirty |= DrawStripSetStr(nm, OBJPROP_TEXT, txt);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP, tip);
   DrawStripDiagExpect(nm, "lbl", x, inkTop, 0, 0, Z_STRIP_OVER, txt);
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
   DrawStripForeign(nm, OBJ_RECTANGLE_LABEL);   // P-DRAW-125: the type, not the name
   int made = 0;
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
      made = 1;
   }
   bool dirty = (made > 0);   // P-DRAW-125: a birth IS a change
   //--- P-DRAW-122 (2026-10-01) — THE LAYER IS RE-ASSERTED EVERY PAINT, NOT ONLY AT
   //--- BIRTH. P-DRAW-120 stated the law and healed the two painters the 15:18 shot
   //--- convicted (face, label); the rule is the RULE, so it now covers the rest of
   //--- the family: equal z is settled by CREATION ORDER, so an object that survives a
   //--- reattach keeps the rung it was born with, and a rect the census reads at the
   //--- right seat with the right ink paints UNDER the plate. Compare-guarded (the
   //--- shared write path), so a still frame costs two reads and writes nothing.
   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);
   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);
   dirty |= DrawStripSetInt(nm, OBJPROP_BGCOLOR, face);
   DrawStripDiagExpect(nm, "rect", x, y, w, h, z, "");
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
   //--- P-DRAW-117: a GROUP HEADER carries its own name — the row's label IS the
   //--- group's word now, so the panel's nav has no second table to drift from.
   if(kind == DSTRIP_GRK_GROUP) return DrawStripGearGroupText(arg);
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
   if(kind == DSTRIP_GRK_GROUP) return DrawStripGearGroupRes(arg);   // P-DRAW-117
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
   if(kind == DSTRIP_GRK_GROUP) return DrawStripGearGroupTip(arg);   // P-DRAW-117
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
   //--- P-DRAW-117: a group header is "current" exactly while ITS settings are the
   //--- ones on screen — the open group, and not folded away.
   if(kind == DSTRIP_GRK_GROUP) return (arg == s_dsGear && !s_dsGearCollapsed);
   return false;
}
//--- P-DRAW-117 (2026-10-01) — THE VALUE THE GROUP HOLDS, ON ITS OWN ROW.
//--- A folded panel still answers the first question a settings card is asked
//--- («این شکل الان چی پوشیده؟»): Color states the border's hex and the interior's
//--- tone, Stroke the width and the line style, Levels how many levels the held
//--- drawing shows, Look the template in force, Row how many cells the quick row
//--- carries — and the Mark group its face. ONE owner: read by the row's paint and
//--- by the row's tooltip, never re-derived at either site.
//--- Bounded: a handful of slot reads and one text format per group row per paint
//--- (five rows), and nothing here runs in the mouse or tick stream.
string DrawStripGearGroupDigest(const int gid)
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return "";
   if(gid == DSTRIP_GEAR_PAINT)
   {
      string hex = DrawStripColorHex((color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR));
      if(!DrawSlotAvailable(s_dsKind, DRAW_SLOT_FILL)) return hex;
      if(DrawSlotRead(s_dsObj, DRAW_SLOT_FILL) < 0.5) return hex;
      return hex + " · " + IntegerToString((int)DrawSlotAlphaGet(s_dsObj, DRAW_SLOT_FILLCLR)) + "%";
   }
   if(gid == DSTRIP_GEAR_STYLE)
   {
      int w = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
      string st = DrawStripPickText(s_dsKind, DRAW_SLOT_STYLE, (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE));
      if(w < 1 || w > 5) return st;
      if(st == "") return IntegerToString(w) + "px";
      return IntegerToString(w) + "px · " + st;
   }
   if(gid == DSTRIP_GEAR_LEVELS)
   {
      int n = DrawStripGearLevelCount();
      return (n == 1) ? "1 level" : (IntegerToString(n) + " levels");
   }
   if(gid == DSTRIP_GEAR_MARK)
   {
      if(s_dsKind == DK_TEXT)
         return IntegerToString((int)DrawSlotRead(s_dsObj, DRAW_SLOT_FONT)) + "pt";
      return "glyph " + IntegerToString((int)DrawSlotRead(s_dsObj, DRAW_SLOT_GLYPH));
   }
   if(gid == DSTRIP_GEAR_TPL)
   {
      if(s_dsKind <= DK_NONE || s_dsKind >= DK_COUNT) return "";
      string nm = DrawPresetName(s_dsKind, s_dsTpl[s_dsKind]);
      return (nm == "") ? "none" : nm;
   }
   //--- the Row group: how many cells the quick row really shows, counted by the
   //--- SAME conditions its own list is built with (available slots, minus the more
   //--- seat, plus the levels cell on the kinds that have levels).
   if(gid != DSTRIP_GEAR_STRIP) return "";   // P-DRAW-117: the fallback is EMPTY —
                                              // an unknown group states nothing
   DrawStripVisInit();
   int on = 0;
   for(int s = 0; s < DRAW_SLOT_N; s++)
   {
      if(s == DRAW_SLOT_MORE) continue;
      if(!DrawSlotAvailable(s_dsKind, s)) continue;
      if(DrawStripVis(s_dsKind, s)) on++;
   }
   if(DrawKindHasLevels(s_dsKind) && DrawStripVis(s_dsKind, DSTRIP_SLOT_LEVELS)) on++;
   return IntegerToString(on) + " cells";
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
//--- P-DRAW-100: ...UNLESS THE CALLER SAYS THE FIELD MAY FOLLOW ITS VALUE. That
//--- sentence above was the whole of the rule, and for the two colour fields it
//--- made the field a LIE: `OBJPROP_TEXT` was written once, inside the create, so
//--- the Paint tab's `COLOR` box showed the hex the drawing wore the first time the
//--- tab was opened and nothing ever changed it. Press `Reset` in the foot
//--- (`DrawPresetApply`, DrawStrip_Tap) or pick a colour on the board and the
//--- drawing changed while the field kept the old hex — the one field whose whole
//--- job is to state the current value, stating a value the drawing had left. The
//--- board's own hex field already solved this and its law is copied here verbatim
//--- (`DrawStripPopHex`, this file): a guarded write that follows the value, and an
//--- EMPTY seed never writes, so the field the user is typing in is the caller's
//--- word to keep. `reseed` is that word: the two hex seats pass the value while
//--- `s_dsHexFocus` is false, the three typed seats pass false and are untouched.
bool DrawStripEdit(const int e, const int x, const int y, const int w,
                   const string seed, const string tip, const bool reseed)
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
   else if(reseed && seed != "" && ObjectGetString(0, nm, OBJPROP_TEXT) != seed)
      dirty |= DrawStripSetStr(nm, OBJPROP_TEXT, seed);
   //--- P-DRAW-122: the layer, every paint — a field that survives a reattach with an
   //--- older rung paints under the plate, and the ROW'S OWN WORD is what goes missing.
   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, Z_STRIP_ICON);
   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);
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
   //--- P-DRAW-122: the layer, every paint (same heal as the panel's fields and rects:
   //--- a bare HEX box on the board is this field painting under the plate).
   dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, Z_STRIP_ICON);
   dirty |= DrawStripSetInt(nm, OBJPROP_BACK, false);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, DSTRIP_POP_EDIT_H);
   dirty |= DrawStripSetStr(nm, OBJPROP_TOOLTIP,
                            "Type #RRGGBB, Enter applies it" + DrawStripTipScope());
   return dirty;
}
//--- P-DRAW-90 (2026-09-30) — THE FOOT'S THREE COMMANDS AND ITS OWN GRID.
//--- The design draws `Reset | All · Copy`; the code shipped `All · Copy` and
//--- put the reset ring on `All`. Three owners now, one per question: the LABEL
//--- and its tooltip, the GLYPH (only `Reset` wears one — the mock's own rule;
//--- `""` makes DrawStripFace DELETES the face, which is the orphan sweep for the
//--- ring the old `All` wore), and the SEAT (`DrawStripFootX`).
//--- `DrawStripFootX` is read by the paint (DrawStripGearPaint) AND the hit test
//--- (DrawStripGearHit): the same arithmetic in two places is a second grid, and
//--- the old foot proved it — it stood at `px + f*(bw+gap)` twice, once in each.
string DrawStripFootText(const int f)
{
   if(f == 0) return "Reset";
   return (f == 1) ? "All" : "Copy";
}
string DrawStripFootTip(const int f)
{
   if(f == 0) return "This " + DrawKindName(s_dsKind) + " back to its factory look (undoable)";
   if(f == 1) return "This look on EVERY " + DrawKindName(s_dsKind) + " (MT4's dialog is one at a time)";
   return "Copy this drawing beside itself (selects the copy)";
}
string DrawStripFootRes(const int f)
{
   return (f == 0) ? "::Files\\Icons\\gl_reset_m.bmp" : "";
}
//--- P-DRAW-80: the cards' OWN width formula, `max(72, 32 + advance + 8)`.
int DrawStripFootBw(const int f)
{
   return MathMax(DSTRIP_GEAR_FOOT_BW, 32 + PnlTextW(DrawStripFootText(f), 8) + 8);
}
//--- the seat: `f == 0` at the content's left edge, the rest a pair flush to its
//--- right. `cw` is the foot's own content width — DrawStripGearColW(), the same
//--- answer on a 312 tab and on a 624 one (280 / 592).
int DrawStripFootX(const int f, const int px, const int cw)
{
   if(f <= 0) return px;
   int total = 0;
   for(int i = 1; i < DSTRIP_GEAR_FOOT_N; i++)
      total += DrawStripFootBw(i) + ((i > 1) ? DSTRIP_GEAR_FOOT_GAP : 0);
   int x = px + cw - total;
   for(int i = 1; i < f; i++) x += DrawStripFootBw(i) + DSTRIP_GEAR_FOOT_GAP;
   return x;
}
//--- P-DRAW-107 (2026-10-01) — THE SEAT IS THE CENTRE OF THE BUTTON.
//--- P-DRAW-80 copied the cards' left-aligned pair (`glyph at bx+12`, `label at
//--- bx+32`, BiotakPanels 6486-6507) onto this foot. A card's footer button is
//--- ~100px wide and left-aligned ink reads as a button there; this foot's plate is
//--- `DSTRIP_GEAR_FOOT_BW` 72 and the same seat parks the word against its LEFT
//--- edge. MEASURED with the panel's own metrics (`mt4.text_w`, `PnlTextW`): `All`
//--- is 14px and began at `fx+16` inside a plate whose own fill runs `fx+2 .. fx+70`
//--- — 14px of plate to its left, 40px to its right; `Copy` (27px) 14/27 and
//--- `Reset` (29px, after its ring) 12/18. The button's ink is ONE group,
//--- `[ring 15 + ADV][word]`, so the GROUP is what is centred:
//--- `x0 = fx + (bw - adv - tw) / 2`, and the ring sits one ADV inside it. `Reset`
//--- therefore moves 1px, `Copy` 6 and `All` 13, and each word's own gaps come out
//--- 27/27 (`Reset` 9/10 around its ring+word pair). The width, the advance and the
//--- advance's own number are each ONE owner.
int DrawStripFootLabelX(const int f, const int fx)
{
   int adv = (DrawStripFootRes(f) == "") ? 0 : DSTRIP_GEAR_FOOT_GLYPH_ADV;
   return fx + (DrawStripFootBw(f) - adv - PnlTextW(DrawStripFootText(f), 8)) / 2 + adv;
}
//--- the ring's own seat: ONE advance left of the word it belongs to, so the pair
//--- cannot drift apart on a measured plate (P-DRAW-90: `Reset` is the one action
//--- the design gives a glyph, and an empty `DrawStripFootRes` makes DrawStripFaceZ
//--- DELETE the seat — the sweep for the ring the old two-button foot wore on `All`).
int DrawStripFootGlyphX(const int f, const int fx)
{
   return DrawStripFootLabelX(f, fx) - DSTRIP_GEAR_FOOT_GLYPH_ADV;
}
//--- the gear panel's own paint: tabs, grids, rows, edits, foot.
string DrawStripGearHeadTitle()
{
   return DrawKindName(s_dsKind) + " Settings";
}
//--- P-DRAW-117 (2026-10-01) — THE HEAD STATES THE DRAWING, NOT ITS PAPERWORK.
//--- The second line carried `SERVING n DRAWINGS` — a count the strip's own badge
//--- already carries — while the one thing a settings card is opened to see stood
//--- nowhere on it: what this drawing wears RIGHT NOW. The line is the LIVE look
//--- now — the border's hex, the width, the line style, and the interior's tone when
//--- the drawing has one — read through the same slot owners every other surface
//--- reads, and re-read on every paint (so a board pick, a template, or the foot's
//--- own Reset moves it in the same frame).
string DrawStripGearHeadSub()
{
   if(s_dsObj == "" || ObjectFind(0, s_dsObj) < 0) return "";
   string line = DrawStripColorHex((color)(int)DrawSlotRead(s_dsObj, DRAW_SLOT_COLOR));
   int w = (int)DrawSlotRead(s_dsObj, DRAW_SLOT_WIDTH);
   if(w >= 1 && w <= 5) line += " · " + IntegerToString(w) + "px";
   string st = DrawStripPickText(s_dsKind, DRAW_SLOT_STYLE, (int)DrawSlotRead(s_dsObj, DRAW_SLOT_STYLE));
   if(st != "") line += " · " + st;
   if(DrawSlotAvailable(s_dsKind, DRAW_SLOT_FILL) && DrawSlotRead(s_dsObj, DRAW_SLOT_FILL) >= 0.5)
      line += " · " + IntegerToString((int)DrawSlotAlphaGet(s_dsObj, DRAW_SLOT_FILLCLR)) + "%";
   return line;
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
    //--- read "11" — a number the user cannot act on or quote (J-02).
    //--- P-BUILD-08: the OLD tag here was a hand-typed word ("T2") that did not
    //--- change when the code did, so two different ex4s showed the same chip. The
    //--- chip now shows the SHORT form of the SAME source hash the log prints as
    //--- [BUILD] src= (Biotak/BuildHash.mqh) — screen and log, one voice, and it
    //--- moves the moment any compiled byte moves. 8 chars, not 16: the chip is
    //--- 16px high and stands in a 312px head, and the log carries the full hash.
    string ver = TH3_SRC_SHORT;
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
//--- P-DRAW-121 (2026-10-01) — AND A GROUP HEADER IS NOT A MEMBER. The accordion's
//--- own nav rides the SAME row array (`s_dsGR*`, P-DRAW-117) in the SAME column, so
//--- on a wide tab the headers BELOW the open group pack into the last band's range
//--- and this loop counted them as settings: reported from the terminal as the Stroke
//--- tab's LAYER pill reading 4 (`Behind candles` + `Look` + `Row` for a band that
//--- owns TWO rows, Lock and Behind candles), and the same rule gave the Colour tab's
//--- FILL band 5 for its two members. Reproduced offline by
//--- `python tools/debug-doctor.py --symptom count` (S3), whose delta IS the defect:
//--- the pill counted NAV. `s_dsGRKind` is the row's own kind and the group row is
//--- `DSTRIP_GRK_GROUP`, so the row loop skips it and nothing else moves — the grid
//--- loop below was never affected (a header writes no `s_dsGG` cell).
int DrawStripGearSectionCount(const int i)
{
   if(i < 0 || i >= s_dsGearSecN) return 0;
   int col = s_dsGearSecCol[i], y0 = s_dsGearSecY[i], y1 = 0x7FFFFFFF;
   for(int j = i + 1; j < s_dsGearSecN; j++)
      if(s_dsGearSecCol[j] == col && s_dsGearSecY[j] > y0 && s_dsGearSecY[j] < y1)
         y1 = s_dsGearSecY[j];
   int n = 0;
   for(int r = 0; r < s_dsGRN; r++)
      if(s_dsGRKind[r] != DSTRIP_GRK_GROUP &&
         s_dsGRCol[r] == col && s_dsGRY[r] >= y0 && s_dsGRY[r] < y1) n++;
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
   int cw = DrawStripGearCellW();   // P-DRAW-99: ONE column's cell — the owner
   int px = gx + DSTRIP_GEAR_PAD;
   dirty |= DrawStripGearHeadPaint();
   //--- P-DRAW-117 (2026-10-01) — THE TAB BAND IS RETIRED, AND THIS IS ITS SWEEP.
   //--- The track bed, the five tab buttons and the accent underline are objects the
   //--- TAB build painted and this one does not: a chart that upgrades under the panel
   //--- would keep a second nav standing under the group rows, and no painter here
   //--- would ever take them down (a name a previous build wrote is an ORPHAN — Touch
   //--- rule 2). They die by literal name on every paint: seven ObjectFinds, no write
   //--- once they are gone, and the family's own prefix wipe covers them on any close
   //--- or open that follows.
   if(ObjectFind(0, "PnlDrawS_GTrack") >= 0) { ObjectDelete(0, "PnlDrawS_GTrack"); dirty = true; }
   if(ObjectFind(0, "PnlDrawS_GU") >= 0) { ObjectDelete(0, "PnlDrawS_GU"); dirty = true; }
   for(int gt = 0; gt < DSTRIP_GEAR_GRP_MAX; gt++)
   {
      string tn = "PnlDrawS_GT" + IntegerToString(gt);
      if(ObjectFind(0, tn) >= 0) { ObjectDelete(0, tn); dirty = true; }
   }
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
      //--- P-DRAW-118 (2026-10-01): the grid carries the COLOUR ROLE ROWS too now.
      //--- A swatch cell's colour IS the cell (`s_dsGGC[g]`, written by the row's own
      //--- builder), and its skin is the strip's own `ds_swatch24` — the same face
      //--- the quick row's colour cell wears (P-DRAW-33), because the icon diet
      //--- removed the cards' glass at these sizes. The PREVIEW and the `+` are the
      //--- same act (open the board on this role), so one tooltip, one branch.
      {
         int slot = s_dsGGSlot[g], arg = s_dsGGArg[g], gk = s_dsGGKind[g];
         if(gk == DSTRIP_GRG_SWATCH)
         {
            color sc = s_dsGGC[g];
            string stip = "Color: " + DrawStripColorLabel(sc) + " — click to apply" + DrawStripTipScope();
            dirty |= DrawStripBtn(gn, cx, cy, s_dsGGW[g], s_dsGGH[g], sc, DrawStripInkOn(sc),
                                  (DrawStripColorRead(s_dsObj, slot) == sc) ? DSTRIP_CLR_ACCENT
                                                                           : BioSwatchBorder(sc, BIO_CLR_CARD),
                                  "", stip);
            dirty |= DrawStripFace(DrawStripGridGlassName(g), cx, cy, s_dsGGW[g], s_dsGGH[g],
                                   "::Files\\Icons\\ds_swatch24.bmp", stip);
         }
         else if(gk == DSTRIP_GRG_PREV || gk == DSTRIP_GRG_PLUS)
         {
            string otip = "Open the color picker" + DrawStripTipScope();
            if(gk == DSTRIP_GRG_PREV)
            {
               color oc = DrawStripColorRead(s_dsObj, slot);
               dirty |= DrawStripBtn(gn, cx, cy, s_dsGGW[g], s_dsGGH[g], oc, DrawStripInkOn(oc),
                                     BioSwatchBorder(oc, BIO_CLR_CARD), "", otip);
               dirty |= DrawStripFace(DrawStripGridGlassName(g), cx, cy, s_dsGGW[g], s_dsGGH[g],
                                      "::Files\\Icons\\ds_swatch24.bmp", otip);
               if(ObjectFind(0, gi) >= 0) { ObjectDelete(0, gi); dirty = true; }
            }
            else
            {
               dirty |= DrawStripBtn(gn, cx, cy, s_dsGGW[g], s_dsGGH[g], DSTRIP_CLR_FIELD,
                                     DSTRIP_CLR_LABEL, DSTRIP_CLR_FIELD_BD, "", otip);
               dirty |= DrawStripFace(gi, cx, cy, DSTRIP_GEAR_SWQ_PLUS, DSTRIP_GEAR_SWQ_PLUS,
                                      "::Files\\Icons\\gl_plus_m.bmp", otip);
            }
         }
         else
         {
            //--- P-DRAW-124 (2026-10-01) — A CELL THAT CHANGED ROLE TAKES ITS OLD
            //--- ROLE'S FACES WITH IT. The swatch and the chip ride the SAME grid
            //--- arrays, so one index is a colour cell on the Paint tab and a
            //--- width/style chip on the Style one — and only the FACES differ: the
            //--- swatch branch paints the glass (`ds_swatch24`) plus the glyph face
            //--- `gi`, and the chip branch below paints NEITHER and deleted neither,
            //--- so the previous tab's faces stayed standing at their old seat.
            //--- MEASURED live (2026-10-01 18:42:35, the report «این هنوز درست نشده»):
            //--- `GG0G..GG8G`, NINE 24x24 glass faces at y=186 — the PAINT tab's own
            //--- swatch row — while this tab's ten chips sit at y=224 and y=308, all
            //--- of them at z=1442, the LABELS' rung, over the band that shares that
            //--- row (the `STROKE` caption is at y=193). A face no branch of this
            //--- paint claims is exactly what P-DRAW-42 forbids: two probes here,
            //--- every paint, and the survivors go in the same frame the cell is
            //--- drawn as a chip (the PREV branch below already did this for `gi`).
            if(ObjectFind(0, DrawStripGridGlassName(g)) >= 0)
            { ObjectDelete(0, DrawStripGridGlassName(g)); dirty = true; }
            if(ObjectFind(0, gi) >= 0) { ObjectDelete(0, gi); dirty = true; }
            // P-DRAW-44: a chip — the width / line style / ray options.
            bool cur = DrawStripPickIsCur(s_dsObj, s_dsKind, slot, arg);
            string txt = PnlFit(DrawStripPickText(s_dsKind, slot, arg), 8, s_dsGGW[g] - 8);
            string tip = DrawStripPickTip(s_dsObj, s_dsKind, slot, arg);
            dirty |= DrawStripBtn(gn, cx, cy, s_dsGGW[g], s_dsGGH[g],
                                  cur ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_FIELD,
                                  cur ? DSTRIP_CLR_ACCENTT : DSTRIP_CLR_LABEL,
                                  cur ? DSTRIP_CLR_ACCENT2 : DSTRIP_CLR_FIELD_BD, txt, tip);
         }
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
         //--- P-DRAW-117: and the row's DIGEST — a retired row takes its value with
         //--- it, or a stale hex hangs over the row that replaced it.
         if(ObjectFind(0, DrawStripRowDigestName(r)) >= 0)
         { ObjectDelete(0, DrawStripRowDigestName(r)); dirty = true; }
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
      //--- P-DRAW-117 — A GROUP HEADER: icon, name, and the value it holds.
      //--- One muscle per face and no switch (a group is not a boolean): the chip is
      //--- the cards' own, gold while THIS group is the open one, the label is the
      //--- row's own ink (INK when open, LABEL when closed) and the digest is
      //--- right-aligned with `DSTRIP_GEAR_DG_PAD` of air to the cell's edge — the
      //--- label is fitted against it, so the two can never collide at any DPI.
      if(s_dsGRKind[r] == DSTRIP_GRK_GROUP)
      {
         string dg = PnlFit(DrawStripGearGroupDigest(s_dsGRArg[r]), 8, cw / 2);
         int dw = (dg == "") ? 0 : PnlTextW(dg, 8);
         dirty |= DrawStripFace(rc, rx + DSTRIP_GEAR_PAD, py + DSTRIP_CARD_CHIP_Y, 22, 22,
                                cur ? "::Files\\Icons\\pnl_chip_gold.bmp" : "::Files\\Icons\\pnl_chip.bmp", tip);
         dirty |= DrawStripFace(ri, rx + DSTRIP_GEAR_PAD, py + DSTRIP_CARD_CHIP_Y, 22, 22, res, tip);
         int gx0 = rx + DSTRIP_GEAR_PAD + 22 + 8;
         dirty |= DrawStripLblIn(rl, gx0, py, DSTRIP_GEAR_ROW_H,
                                 PnlFit(txt, 9, cw - (gx0 - rx) - dw - DSTRIP_GEAR_DG_PAD - DSTRIP_ROW_GAP),
                                 cur ? DSTRIP_CLR_VALUE : DSTRIP_CLR_LABEL, tip, 9, true);
         if(dw > 0)
            dirty |= DrawStripLblAt(DrawStripRowDigestName(r), rx + cw - DSTRIP_GEAR_DG_PAD - dw,
                                    StrapInkY(py, DSTRIP_GEAR_ROW_H, 8), dg,
                                    cur ? DSTRIP_CLR_ACCENT : DSTRIP_CLR_TITLE, tip, 8, true);
         else if(ObjectFind(0, DrawStripRowDigestName(r)) >= 0)
         { ObjectDelete(0, DrawStripRowDigestName(r)); dirty = true; }
         dirty |= DrawStripFace(rr, rx, py, 2, DSTRIP_GEAR_ROW_H,
                                cur ? "::Files\\Icons\\pnl_rail_gold.bmp" : "", tip);
         //--- and the SWITCH seat is not this row's: a stale one from a previous
         //--- tab (or a previous kind) is taken down here, the same rule the row's
         //--- own separator follows above.
         if(ObjectFind(0, rs) >= 0) { ObjectDelete(0, rs); dirty = true; }
         continue;
      }
      //--- P-DRAW-124: AND THE DIGEST IS THE GROUP'S OWN FACE. A row that was a
      //--- group header on the previous tab and is a switch on this one kept its
      //--- digest OBJECT: the group branch gives an empty digest the delete, the
      //--- switch branch below never asked the question at all. MEASURED live
      //--- (2026-10-01 18:42:35): `GR2D`/`GR3D`/`GR4D` still read `"3px · Solid"`
      //--- at (1310,360)/(1348,402)/(1334,444) — the PAINT tab's own digest seats
      //--- — at z=1442, the labels' rung, over whatever now shares that seat. The
      //--- row's value is the group's; a switch states its own state and nothing
      //--- else. One probe, on the path that is not a group.
      if(ObjectFind(0, DrawStripRowDigestName(r)) >= 0)
      { ObjectDelete(0, DrawStripRowDigestName(r)); dirty = true; }
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
      //--- P-DRAW-118 (2026-10-01): the two COLOUR seats (e0, e4) are RETIRED with
      //--- the hex boxes they typed into — a colour is a swatch now, and the exact
      //--- value is the board's HEX field (behind the row's `+`). Their objects die in
      //--- the `!want` branch below, which is the same sweep every retired field uses.
      bool want = ((e == 1 && s_dsGear == DSTRIP_GEAR_LEVELS) ||
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
      //--- P-DRAW-118 (2026-10-01): the two colour seats are gone with their boxes
      //--- (see the `want` above); the three that remain are typed VALUES, not
      //--- readings, so none of them re-seeds itself while a hand is in it.
      //--- The board's own HEX field still follows the colour it states — that law is
      //--- `DrawStripPopHex`'s, and it is the one the retired panel boxes copied
      //--- (P-DRAW-100, whose site moved with the field).
      if(e == 1)
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew, "",
                                "Add a level, e.g. 88.6 — Enter adds it (the held drawing)", false);
      else if(e == 3)
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew, "",
                                "Template name — Enter saves this look under your name", false);
      else
         dirty |= DrawStripEdit(e, ex, s_dsGearEditY[e], ew,
                                ObjectGetString(0, s_dsObj, OBJPROP_TEXT),
                                "Caption — Enter applies it", false);
   }
    //--- P-DRAW-80: THE FOOT IS THE CARDS' FOOT (BiotakPanels 6486-6507, 6901-6903).
    //--- LEFT-ALIGNED at `+16` and `+10` down, each button a 28px ghost with its
    //--- GLYPH at `bx+12` and its label at `bx+32` — the pair the cards wear. This
    //--- panel centred a bare word with no glyph at all, so its foot read as a row
    //--- of captions under a card that has two buttons with icons.
    int fy0 = s_dsGEY + s_dsGearFootY;
    //--- P-DRAW-90: the foot's own width is the COLUMN's (DrawStripGearColW), the
    //--- same answer the hit test reads — the local `cw` above is one 312 column's
    //--- 280 on EVERY tab, which would park the pair 312px short on a 624 one.
    int fcw = DrawStripGearColW();
    for(int f = 0; f < DSTRIP_GEAR_FOOT_N; f++)
    {
      string fn = DrawStripFootName(f);
      string label = DrawStripFootText(f);
      //--- P-DRAW-80: the cards' OWN width formula (BiotakPanels 6481-6484) —
      //--- `max(72, 32 + advance + 8)`, owned by DrawStripFootBw (P-DRAW-90: the
      //--- hit test spends the same function, never a second arithmetic).
      int bw = DrawStripFootBw(f);
      int fx = DrawStripFootX(f, px, fcw);
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
      //--- `ico` argument, BiotakPanels 6901-6902). P-DRAW-90: `Reset` is the one
      //--- the design gives a glyph — DrawStripFootRes answers "" for the pair,
      //--- and DrawStripFaceZ DELETES on "", which is the sweep for the ring the
      //--- old two-button foot wore on `All`.
      //--- P-DRAW-107: BOTH seats come from the one centred group above — the paint
      //--- asks for `fgx` and `lx` and derives neither (`gx` is the GEAR PLATE's own
      //--- left edge in this function — a shadowed name here is a second meaning for
      //--- one word). `fx + 12` (the cards' own glyph seat) is what stood here, and on
      //--- a plate this narrow it was the left half of a left-aligned pair.
      int lx = DrawStripFootLabelX(f, fx);
      int fgx = DrawStripFootGlyphX(f, fx);
      dirty |= DrawStripFace(DrawStripFootGlyphName(f), fgx, fy + 6, 15, 15,
                             DrawStripFootRes(f), tip);
      dirty |= DrawStripLblIn(DrawStripFootLabelName(f), lx, fy, 28,
                              PnlFit(label, 8, fx + bw - 8 - lx),
                              ink, tip, 8, true);
   }
   //--- P-DRAW-78: the retired third button (`Del`) dies here, not in the purge
   //--- above — this loop is the only other writer of the GF family, and without
   //--- a stale branch a chart that wore the 3-button foot keeps a dead Del.
   //--- Bounded: exactly the one retired seat.
   //--- P-DRAW-90: and it is EMPTY again, by construction — `Del`'s seat 2 is
   //--- `Copy`'s now (`DSTRIP_GEAR_FOOT_N` is 3), so seats 0..2 are all live and
   //--- the loop runs zero times. It stays as the family's guard, and its bound
   //--- still names the highest seat this family has ever owned (3). A chart that
   //--- wore the old two-button foot needs no sweep either: seat 2 was never
   //--- written then, and seat 1's stale `gl_check_gold` ring is deleted by the
   //--- paint itself (DrawStripFootRes -> "" -> DrawStripFaceZ deletes).
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
