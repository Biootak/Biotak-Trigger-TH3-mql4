// DrawStrip_Paint.mqh - DrawStrip split 2026-09-29: exact lines 5339-6238 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_PAINT_MQH
#define DRAW_STRIP_PAINT_MQH


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
         //--- P-DRAW-101 (2026-09-30) — A PLATE THAT WILL NOT BUILD IS NOT A REASON
         //--- TO BUILD NOTHING. This was `if(!ObjectCreate(...)) return;`, and the
         //--- `return` is the whole painter: one refused object name (the terminal's
         //--- own object budget, a name already taken by a chart that died dirty)
         //--- took the grip, the badge, the quick cells, the actions, the colour
         //--- board, its RECENT band, the HEX field, the opacity bar, the popover,
         //--- AND the two calls at the bottom that place, plate and paint the gear
         //--- panel — with `dirty` never reaching ChartRedraw, so the frame before it
         //--- stayed frozen. Three surfaces to nothing, over one rectangle label.
         //--- The plate is the one piece that may be missing; everything after it
         //--- degrades to the previous look, which is what the guarded writes below
         //--- already are (a write aimed at a name the chart does not carry answers
         //--- nothing and costs one read).
         if(ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         {
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
                 dirty |= DrawStripBtn(DrawStripPageSeatName(k), pgx+k*20, pgy, 20, 20,
                                       DrawStripPlateFill(),
                                       edge ? DSTRIP_CLR_LINE : DSTRIP_CLR_LABEL,
                                       edge ? DSTRIP_CLR_LINE : DSTRIP_CLR_LINE,
                                       (k==0) ? "<" : ">",
                                       (k==0) ? "The palette's first 64 colors"
                                             : "The palette's other 64 colors");
              }
              dirty |= DrawStripLblIn(DrawStripPageLabelName(), pgx-24, hy0, DSTRIP_BOARD_HDR,
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
#endif // DRAW_STRIP_PAINT_MQH
