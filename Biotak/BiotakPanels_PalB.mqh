// BiotakPanels_PalB.mqh - BiotakPanels split 2026-09-29: exact lines 2442-3818 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_PALB_MQH
#define BIOTAK_PANELS_PALB_MQH

void PalDraw()
{
   ObjectsDeleteAll(0, g_UI.btnPrefix+"Pal_", 0, -1);
   // P-UI-131h: this paint is the only source of the hover regions — dropping them here
   // is what makes a close/tab switch leave nothing to hit-test (PalHoverPreview restores
   // the previewed colour on the first move that finds no cell).
   s_palRegionN = 0;
   int px=g_PalX, py=g_PalY, w=PalW(), h=PalH();
   string p=g_UI.btnPrefix+"Pal_";

    // card — RICH-MT4: baked gradient+radius face (preview .pal). Same object
    // name and Z as the old flat rect, so PalClose's prefix wipe is untouched.
    // P-DRAW-49: TWO bakes, one per cell size — MT4 crops a bitmap label and
    // never scales it, so a 268x509 face cannot stand in for a 268x477 one.
    PnlSetBitmap(p+"card", px, py, w, h,
                 (PalCellSize()>=PAL_CELL_BIG) ? "::Files\\Icons\\pal_card26.bmp"
                                               : "::Files\\Icons\\pal_card22.bmp",
                 Z_PANEL_POP);

   // header (names the LIVE target — the picked color goes there,
   // which may differ from the row that opened the popup via APPLY TO)
    // TV parity board: the reference's own title face — muted, letter-uppercase,
    // never bold (the strip's board wears the same one). The join is code 183
    // set at runtime (P-LBL-01): a literal `·` is read as a NUMBER and warns on
    // every concatenation; StringToUpper wants a variable, never a temporary.
    string pttl=" . ";
    StringSetCharacter(pttl,1,183);
    string pttl2="PALETTE "+pttl+" "+PalTgtLabel(g_PalTgt);
    StringToUpper(pttl2);
    PnlSetLabel(p+"ttl", px+PAL_PAD+14, py+7, pttl2, PNL_CLR_MUTED, PNL_PT_PAL);
    ObjectSetString(0,p+"ttl",OBJPROP_FONT,BioChromeFont(false));
    ObjectSetString(0,p+"ttl",OBJPROP_TOOLTIP,"Drag to move");
    ObjectSetInteger(0,p+"ttl",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   // P-DRAW-49: the carry grip, so the title says "I can be dragged" instead of
   // only being true. Baked once for the whole popup family (ds_grip is the
   // strip's; this is the popup's own 12px face).
   PnlSetBitmap(p+"grip", px+PAL_PAD, py+8, 12, 12, "::Files\\Icons\\pal_grip.bmp", Z_PANEL_POP_BG);
   ObjectSetString(0,p+"grip",OBJPROP_TOOLTIP,"Drag to move");
   // P-UI-150 (2026-10-13): the seat comes from the ONE owner `PalCloseSeat`
   // (PalA), the same one the title carry reads to exclude the button. Painted here
   // as `px+w-PAL_PAD-20, py+5, 20, 18` and tested there as `py+3..py+21`, the two
   // spellings disagreed by 2 px and the button's own bottom edge armed a drag.
   int cseX = 0, cseY = 0, cseW = 0, cseH = 0;
   PalCloseSeat(px, py, w, cseX, cseY, cseW, cseH);
   PnlSetButton(p+"close", cseX, cseY, cseW, cseH, "x", PNL_CLR_SEG_OFF, PNL_CLR_SEG_BD);   ObjectSetInteger(0,p+"close",OBJPROP_COLOR,PNL_CLR_MUTED);
   ObjectSetInteger(0,p+"close",OBJPROP_FONTSIZE,PnlPt(PNL_PT_PAL));   // P-UI-30
   ObjectSetInteger(0,p+"close",OBJPROP_ZORDER,Z_PANEL_POP_CTL);

   // P-DRAW-49: THE READOUT — the new band, and the reason this popup is worth
   // reopening. It shows the cell under the POINTER (or the mixer's own value
   // while a channel is being dragged) instead of leaving the pick to a native
   // tooltip that covers the cells, hides the chart and arrives late. One owner
   // (`PalPaintReadout`), so the hover, the mixer, the click and the open all
   // write the same three numbers by the same arithmetic.
   color cur=PaletteKindColor(g_PalKind);
   PalPaintReadout(cur);

   // tabs (2: PALETTE · MIXER — recents live inline on the PALETTE tab)
   int ty=py+PalTabsY();
   string tabs[2]={"PALETTE","MIXER"};
   int tgap=6;
   int tw2=(w-2*PAL_PAD-tgap)/2;
   for(int i=0;i<2;i++)
   {
      bool act=(i==g_PalTab);
      string tb=p+"t"+IntegerToString(i);
      PnlSetButton(tb, px+PAL_PAD+i*(tw2+tgap), ty, tw2, PAL_TABS-6, tabs[i],
                   act?PNL_CLR_SEG_ON:PNL_CLR_SEG_OFF,
                   act?PNL_CLR_SEG_ON:PNL_CLR_SEG_BD);
      ObjectSetInteger(0,tb,OBJPROP_COLOR, act?PNL_CLR_ACCENT_TX:PNL_CLR_SEG_TX);
      ObjectSetInteger(0,tb,OBJPROP_FONTSIZE,PnlPt(8));   // P-UI-30
      ObjectSetInteger(0,tb,OBJPROP_ZORDER,Z_PANEL_POP_CTL);
   }
   int contY=ty+PAL_TABS;

   if(g_PalTab==0)
   {
       // P-DRAW-50: the grid is a PAGE of the user's own 128 (8 families of 8).
       // Family names live in the tooltips + pager only — no caption line.
      PnlSetLabel(p+"rttl", px+PAL_PAD, py+PalRecCapY(), "RECENT", PNL_CLR_LABEL, PNL_PT_PALSEC);
      ObjectSetInteger(0,p+"rttl",OBJPROP_ZORDER,Z_PANEL_POP_BG);
      // P-UI-69: the strip is painted by ONE owner, shared with the live
      // refresh path (PalRefreshRecents), so the row on screen cannot disagree
      // with the list the picker just changed.
      PalPaintRecents(px, py+PalRecY());
       int cell=PalCellSize(), pitch=cell+PAL_CELLGAP;
       int gy=py+PalFamY();
       //--- the pager: the only way to the second 64. Two small seats plus
       //--- the page number LEFT of them, right-anchored so it never leaves the card.
       int pgx=px+w-PAL_PAD-2*18-4;
       for(int k=0;k<2;k++)
       {
          string pn=p+"pg"+IntegerToString(k);
          PnlSetButton(pn, pgx+k*20, gy-2, 18, 16, (k==0)?"<":">",
                       PNL_CLR_SEG_OFF, PNL_CLR_SEG_BD);
          ObjectSetInteger(0,pn,OBJPROP_COLOR,PNL_CLR_SEG_TX);
          ObjectSetInteger(0,pn,OBJPROP_FONTSIZE,PnlPt(7));
          ObjectSetInteger(0,pn,OBJPROP_ZORDER,Z_PANEL_POP_CTL);
          ObjectSetString(0,pn,OBJPROP_TOOLTIP,(k==0)?"Previous page":"Next page");
       }
       PnlSetLabel(p+"pgt", pgx-6, gy+2, IntegerToString(BioPickPage()+1)+"/"+IntegerToString(BIOPICK_PAGES),
                   PNL_CLR_MUTED, 7);
       ObjectSetInteger(0,p+"pgt",OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
       ObjectSetInteger(0,p+"pgt",OBJPROP_ZORDER,Z_PANEL_POP_BG);
      // P-UI-131h: the two blocks of cells the pointer may sweep (see PalHoverRegionAdd).
      int gy0=py+PalGridY();
      int row0=BioPickPageRow0();
      PalHoverRegionAdd(px+PAL_PAD, gy0, PAL_COLS, PAL_ROWS, cell, pitch, 0, 0);
      for(int qi=0;qi<PAL_COLS;qi++)
         for(int qj=0;qj<PAL_ROWS;qj++)
         {
            string n=p+"s"+IntegerToString(qj)+"_"+IntegerToString(qi);
            int sx=px+PAL_PAD+qi*pitch;
            int sy=gy0+qj*pitch;
             color sw=PalPickColor(row0+qj,qi);
             PnlSetButton(n, sx, sy, cell, cell, "", sw,
                          PnlSwatchBorder(sw,PNL_CLR_FIELD));
             ObjectSetInteger(0,n,OBJPROP_ZORDER,Z_PANEL_POP_CTL);
             ObjectSetString(0,n,OBJPROP_TOOLTIP, BioPickFamily(row0+qj)+"  ·  #"+PalHexText(sw));
             // TV parity: rounded cell face over the square button (one pair of
             // assets, worn by both palette grids; clicks route via the trailing G).
             string ng=n+"G";
             PnlSetBitmap(ng, sx, sy, cell, cell, PalCellFaceRes(sw, PaletteKindColor(g_PalKind)), Z_PANEL_POP_FG);
             ObjectSetString(0,ng,OBJPROP_TOOLTIP, BioPickFamily(row0+qj)+"  ·  #"+PalHexText(sw));
         }
   }
   else
   {
      PalDrawMixer(contY);
   }

   // TV parity board: the palette tab's own HEX band (the mixer seats the same
   // row under its tracks), directly above the APPLY TO row it belongs beside.
   if(g_PalTab!=1) PalDrawHexRow(px, py+PalHxY());

   // apply-to target row — with the TARGET'S OWN colour chip, so the row answers
   // "what am I about to recolor" and not only "what is it called" (P-DRAW-49).
   int tgy=py+PalTgtY();
   PnlSetLabel(p+"tgtl", px+PAL_PAD, tgy+8, "APPLY TO", PNL_CLR_MUTED, PNL_PT_PALSEC);
   ObjectSetInteger(0,p+"tgtl",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   //--- P-DRAW-64a2 (2026-10-02) — A DRAWING HAS TWO COLOURS, SO IT GETS TWO CHIPS.
   // The strip merged the border and the interior into ONE seat (P-DRAW-64a), so the
   // popup has to un-merge it: `cycle >>` walks ALL 29 product targets and a drawing's
   // own two are the LAST two rungs, so «از کجا رنگ بوردر رو عوض کنم» had no answer
   // here either. Two NAMED chips instead — each wearing its own colour — and the
   // click asks the STRIP which SLOT it means (below): the slot↔role vocabulary is
   // the strip's, the kind is the panels', and neither guesses the other's word.
   bool drawTgt = PalKindIsDrawing(g_PalKind);
   if(drawTgt)
   {
      int tw = (w - 2*PAL_PAD - 56 - 6) / 2;
      for(int r = 0; r < 2; r++)
      {
         bool isB = (r == 0);
         string sfx = isB ? "tgtB" : "tgtF";
         int bx = px + PAL_PAD + 56 + r*(tw+6);
         int knd = isB ? PAL_DRAW_BORDER : PAL_DRAW_FILL;
         color c = PaletteKindColor(knd);
         color vis = (c==clrNONE) ? PNL_CLR_AUTO_CELL : c;
         bool on = (g_PalKind == knd);
         //--- P-UI-137 (2026-10-02, user: the two APPLY-TO chips paint with NO WORDS):
         //--- MT4 PAINTS IN CREATION ORDER and a z-order write never raises anything
         //--- (P-LOG-10's measured law). `PalDraw` opens by wiping the whole `Pal_`
         //--- family, so the paint ORDER here IS the creation order — and the chip
         //--- and its name were born BEFORE their own button, so the button's face
         //--- covered both. That is why the `Z_PANEL_POP_FG` write (P-DRAW-64a2)
         //--- never fixed it: it ordered the CLICKS, not the paint.
         //--- THE HOST FIRST, THEN ITS INK — the plate law, applied to a button.
         PnlSetButton(p+sfx, bx, tgy+3, tw, 20, "", PNL_CLR_SEG_OFF, on ? PNL_CLR_ACCENT : PNL_CLR_SEG_BD);
         ObjectSetInteger(0,p+sfx,OBJPROP_ZORDER,Z_PANEL_POP_CTL);
         ObjectSetString(0,p+sfx,OBJPROP_TOOLTIP,
            isB ? "The drawing's BORDER — click, then pick a colour here"
                : "The drawing's FILL — click, then pick a colour here");
         PnlSetRect(p+sfx+"c", bx+5, tgy+7, 10, 10, vis);
         ObjectSetInteger(0,p+sfx+"c",OBJPROP_BORDER_COLOR,PnlSwatchBorder(vis,PNL_CLR_FIELD));
         //--- Z_PANEL_POP_FG, NOT _BG: the chip and the name sit INSIDE their own
         //--- button, and the button is on _CTL — at _BG they sat UNDER it in the
         //--- CLICK order too. The paint order above is what makes them VISIBLE;
         //--- this rung is what makes them hittable-inert and last-drawn.
         ObjectSetInteger(0,p+sfx+"c",OBJPROP_ZORDER,Z_PANEL_POP_FG);
         PnlSetLabel(p+sfx+"t", bx+19, tgy+8, isB ? "Border" : "Fill", PNL_CLR_TITLE, 8);
         ObjectSetInteger(0,p+sfx+"t",OBJPROP_ZORDER,Z_PANEL_POP_FG);
      }
      //--- and the single-target row leaves NOTHING behind (P-DRAW-14): the cycle
      //--- button and its name are not painted while a drawing is open.
      for(int q = 0; q < 3; q++)
      {
         string gn = (q==0) ? p+"tgt" : (q==1) ? p+"tgtc" : p+"tgtn";
         if(ObjectFind(0,gn) >= 0) ObjectDelete(0,gn);
      }
   }
   else
   {
      color tgtClr=PaletteKindColor(g_PalKind);
      color tgtVis=(tgtClr==clrNONE)?PNL_CLR_AUTO_CELL:tgtClr;
      PnlSetRect(p+"tgtc", px+PAL_PAD+62, tgy+6, 14, 14, tgtVis);
      ObjectSetInteger(0,p+"tgtc",OBJPROP_BORDER_COLOR,PnlSwatchBorder(tgtVis,PNL_CLR_FIELD));
      ObjectSetInteger(0,p+"tgtc",OBJPROP_ZORDER,Z_PANEL_POP_BG);
      PnlSetLabel(p+"tgtn", px+PAL_PAD+82, tgy+8, PalTgtLabel(g_PalTgt), PNL_CLR_TITLE, 8);
      ObjectSetInteger(0,p+"tgtn",OBJPROP_ZORDER,Z_PANEL_POP_BG);
      PnlSetButton(p+"tgt", px+w-PAL_PAD-64, tgy+3, 64, 20, "cycle  >>", PNL_CLR_SEG_OFF, PNL_CLR_SEG_BD);
      ObjectSetInteger(0,p+"tgt",OBJPROP_COLOR,PNL_CLR_SEG_TX);
      ObjectSetInteger(0,p+"tgt",OBJPROP_FONTSIZE,PnlPt(7));   // P-UI-30
      ObjectSetInteger(0,p+"tgt",OBJPROP_ZORDER,Z_PANEL_POP_CTL);
      ObjectSetString(0,p+"tgt",OBJPROP_TOOLTIP,"Which target gets the picked color — cycles all color targets (Trigger, Lines, HTF, ...)");
      for(int q = 0; q < 2; q++)
      {
         string sfx = (q==0) ? "tgtB" : "tgtF";
         for(int k2 = 0; k2 < 3; k2++)
         {
            string gn = (k2==0) ? p+sfx : (k2==1) ? p+sfx+"c" : p+sfx+"t";
            if(ObjectFind(0,gn) >= 0) ObjectDelete(0,gn);
         }
      }
   }

   // footer: Done + mini transparency (both tabs — no MIXER switch needed).
   // P-DRAW-49: the TRACK is measured from the columns left over (PalTrX/PalTrW),
   // so it can never leave the card — the 201px popup's hard-coded 100px track
   // started 5px past the edge and pushed its value 11px onto the chart.
   int fy=py+PalFootY();
   PnlSetButton(p+"done", px+PAL_PAD, fy+4, PAL_FT_DONE, 22, "Done", PNL_CLR_ACCENT, PNL_CLR_ACCENT);
   ObjectSetInteger(0,p+"done",OBJPROP_COLOR,PNL_CLR_DONE_TX);
   ObjectSetInteger(0,p+"done",OBJPROP_ZORDER,Z_PANEL_POP_CTL);
   int tr0=PaletteKindTransparency(g_PalKind);
   bool trOk=(tr0>=0);
   int olx=px+PAL_PAD+PAL_FT_DONE+PAL_FT_GAP;
   PnlSetLabel(p+"opl", olx, fy+9, "TR", trOk?PNL_CLR_LABEL:PNL_CLR_DISABLED, 7);
   ObjectSetInteger(0,p+"opl",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   ObjectSetString(0,p+"opl",OBJPROP_TOOLTIP,"Transparency of this target (drag or click the track)");
   int otx=PalTrX(), otw=PalTrW();
   PnlSetRect(p+"opg", otx, fy+11, otw, 8, PNL_CLR_TRACK_BD);
   ObjectSetInteger(0,p+"opg",OBJPROP_ZORDER,Z_PANEL_POP_BG);
   color trFill=trOk?PNL_CLR_ACCENT:PNL_CLR_DISABLED;
   int tfw=trOk?(int)MathRound(ClampInt(tr0,0,100)/100.0*otw):0;
   PnlSetRect(p+"opf", otx, fy+11, tfw, 8, trFill);
   ObjectSetInteger(0,p+"opf",OBJPROP_ZORDER,Z_PANEL_POP_CTL);
   PnlSetLabel(p+"opv", otx+otw+6, fy+9, trOk?IntegerToString(ClampInt(tr0,0,100))+"%":"--", PNL_CLR_VALUE, 8);
   ObjectSetInteger(0,p+"opv",OBJPROP_ZORDER,Z_PANEL_POP_BG);
//--- P-UI-137: the popup witnesses its own captions ONCE PER OPEN — the census and
//--- its epoch flag live in their own owners (`BiotakPanels_PalDiag.mqh` for the
//--- census, PalA for `PalDiagEpoch`), because a witness is an owner and PalB was one
//--- line over the 1500 ceiling with it inlined.
#ifndef BUILD_LITE
   PalDiagCensus(px, py, w, h);
#endif
   ChartRedraw();
}

//--- live-update preview chip, mixer sliders and the owning panel row
void PalUpdateLive()
{
   if(!g_PalOpen) return;
   string p=g_UI.btnPrefix+"Pal_";
   color cur=PaletteKindColor(g_PalKind);
   color curVis=(cur==clrNONE)?PNL_CLR_AUTO_CELL:cur;   // P-UI-131h: AUTO is a state
   ObjectSetInteger(0,p+"cur",OBJPROP_BGCOLOR,curVis);
   // P-UI-69: the current block is a SWATCH - dragging the mixer to near-black
   // must grow its outline in the same tick, or the popover's own "you picked
   // this colour" box reads as an empty slot (PalDraw set it once at open).
   ObjectSetInteger(0,p+"cur",OBJPROP_BORDER_COLOR,PnlSwatchBorder(curVis,PNL_CLR_FIELD));
   ObjectSetString(0,p+"curtx",OBJPROP_TEXT,
                   (cur==clrNONE)?"AUTO (derived)":(PalColorText(cur)+"  #"+PalHexText(cur)));
   if(g_PalTab==1)
   {
      int cv=(int)cur;
      int comps[3];
      comps[0]=cv%256; comps[1]=(cv/256)%256; comps[2]=cv/65536;
      int trackX=PalMixTrackX();
      int trackW=PalMixTrackW();
      for(int i=0;i<3;i++)
      {
         int kx=trackX+(int)MathRound(comps[i]/255.0*(trackW-10));
         ObjectSetInteger(0,p+"mknb"+IntegerToString(i),OBJPROP_XDISTANCE,kx);
         ObjectSetInteger(0,p+"mf"+IntegerToString(i),OBJPROP_XSIZE,MathMax(0,kx-trackX+10));
         ObjectSetString(0,p+"mv"+IntegerToString(i),OBJPROP_TEXT,IntegerToString(comps[i]));
      }
   // transparency channel follows the target's transparency
   int tr2=PaletteKindTransparency(g_PalKind);
   bool trOk=(tr2>=0);
   int tkx=trackX+(int)MathRound((trOk?ClampInt(tr2,0,100):0)/100.0*(trackW-10));
   ObjectSetInteger(0,p+"mknb3",OBJPROP_XDISTANCE,tkx);
   ObjectSetInteger(0,p+"mf3",OBJPROP_XSIZE,MathMax(0,tkx-trackX+10));
   ObjectSetString(0,p+"mv3",OBJPROP_TEXT, trOk ? IntegerToString(tr2)+"%" : "--");
   }
   // footer mini transparency (both tabs) — the track's width is the paint's own
   // (PalTrW), never a second set of numbers (P-DRAW-49).
   int ftr=PaletteKindTransparency(g_PalKind);
   bool fok=(ftr>=0);
   if(ObjectFind(0,p+"opf")>=0)
      ObjectSetInteger(0,p+"opf",OBJPROP_XSIZE,
                       fok?(int)MathRound(ClampInt(ftr,0,100)/100.0*PalTrW()):0);
   if(ObjectFind(0,p+"opv")>=0)
      ObjectSetString(0,p+"opv",OBJPROP_TEXT, fok?IntegerToString(ClampInt(ftr,0,100))+"%":"--");
   // P-DRAW-49: the readout is part of the live picture — a hovered cell, a mixer
   // channel and a click all land here, so the band is repainted by the ONE owner
   // from the same call that moves the knob.
   PalPaintReadout(PaletteKindColor(g_PalKind));
   int it,row;
   if(PalKindRow(g_PalKind,it,row) && g_PnlOpen==it)
   {
      int dr=PnlDispRowOfSet(it,row);   // PalKindRow speaks SETTING rows; the row engine needs display rows
      if(dr>=0) PnlUpdateRow(it,dr);
   }
    // keep the owning panel's TRANSPARENCY row in sync with the palette drag
   int oit=-1, orow=-1;
   switch(g_PalKind)
   {
      case PAL_TRIGGER: oit=0; orow=0; break;
      // P-UI-131j: the label's opacity row, so the popover's TR drag moves the number
      // on the card in the same tick (both write ONE mirror - not a second copy).
      case PAL_TRIGGER_LABEL: oit=0; orow=4; break;
      case PAL_LINE:    oit=7; orow=4; break;
      case PAL_BOX:     if(g_PnlOpen==12 && g_BkTab==0) { oit=12; orow=4; } break;
      case PAL_BOX_FILL: if(g_PnlOpen==12 && g_BkTab==0) { oit=12; orow=6; } break;
      case PAL_HTF_BULL:
      case PAL_HTF_BEAR:
      case PAL_HTF_WICK:
      case PAL_HTF_BORDER: oit=6; orow=2; break;
      // P-UI-131h: the half's opacity row, so the popover's TR drag moves the number on
      // the card in the same tick (both write ONE mirror - the row is not a second copy).
      case PAL_ZONE_EDGE_TOP:    oit=1; orow=16; break;
      case PAL_ZONE_EDGE_BOTTOM: oit=1; orow=17; break;
   }
   if(oit>=0 && g_PnlOpen==oit)
   {
      int odr=PnlDispRowOfSet(oit,orow);
      if(odr>=0) PnlUpdateRow(oit,odr);
   }
   // P-UI-69: an APPLY moved the recents list (PaletteApplyColor pushes it), so
   // the strip on screen is repainted here - the same owner PalDraw uses. The
   // call is free when the list did not move, and is coalesced while a mixer
   // drag is live (the release path flushes the tail).
   PalRefreshRecents(false);
   // P-PERF-06: this runs per mixer tick (30 Hz while dragging) AND on
   // discrete picks. The knob/preview already moved above; a raw repaint per
   // tick was ~33 full-chart repaints/s of a 1000+-object chart. Discrete
   // picks still land within 100 ms — imperceptible.
   ThrottledChartRedraw();
}

//--- mixer hit-test: 0 none, 1 R, 2 G, 3 B, 4 TRANSPARENCY, 5 the FOOTER TR track
int PaletteMixHit(const int mx,const int my)
{
   if(!g_PalOpen) return 0;
    // P-UI-131k: the FOOTER TR track is the SAME channel as the mixer's fourth slider
    // (`PaletteKindTransparency` / `PaletteApplyTransparency`), so it drags like one —
    // it used to answer on a discrete click only. Tested BEFORE the tab gate because
    // the footer belongs to BOTH tabs; its own origin and width are the paint's
    // (PalTrX/PalTrW), never a second set of numbers (P-DRAW-49).
    if(PaletteKindTransparency(g_PalKind) >= 0)
    {
       int fy=g_PalY+PalFootY();
       int fox=PalTrX(), fow=PalTrW();
       if(mx>=fox-4 && mx<=fox+fow+4 && my>=fy+6 && my<=fy+22) return 5;
    }
     if(g_PalTab!=1) return 0;
     int trackX=PalMixTrackX();
     int trackW=PalMixTrackW();
     //--- same rows the paint lays (`PalMixRowY`); bands tile edge-to-edge, so no
     //--- dead gap between two channels can swallow the press.
     for(int i=0;i<3;i++)
     {
        int y=PalMixRowY(i);
        if(mx>=trackX-4 && mx<=trackX+trackW+4 && my>=y-8 && my<=y+22) return i+1;
     }
     if(PaletteKindTransparency(g_PalKind) >= 0)
     {
        int y=PalMixRowY(3);
        if(mx>=trackX-4 && mx<=trackX+trackW+4 && my>=y-8 && my<=y+22) return 4;

    }
   return 0;
}

void PaletteMixFromX(const int comp,const int mx)
{
   // P-UI-131k: the footer TR track has its own origin and width, so it computes its
   // own fraction — the mixer's track geometry would map the pointer to the wrong value.
   if(comp==5)
   {
      int fox=PalTrX();
      double f=(mx-fox)/(double)PalTrW();
      f=MathMax(0.0,MathMin(1.0,f));
      int flags=PaletteApplyTransparency(g_PalKind,(int)MathRound(f*100.0));
      PalUpdateLive();
      if(flags!=REFRESH_NONE) RefreshDisplay(flags);
      return;
   }
    int trackX=PalMixTrackX();
    int trackW=PalMixTrackW();
    //--- knob-centre mapping: the knob is 10px wide over (trackW-10), so the value
    //--- under the pointer's grip is (mx-5), the exact inverse of the paint above.
    double frac=(mx-trackX-5)/(double)(trackW-10);
   frac=MathMax(0.0,MathMin(1.0,frac));
   if(comp==4)   // transparency channel → percent, not RGB
   {
      int trp=(int)MathRound(frac*100.0);
      int flags=PaletteApplyTransparency(g_PalKind,trp);
      PalUpdateLive();
      if(flags!=REFRESH_NONE) RefreshDisplay(flags);
      return;
   }
   int v=(int)MathRound(frac*255.0);
   color cur=PaletteKindColor(g_PalKind);
   int r=cur%256, g=(cur/256)%256, b=cur/65536;
   int nr=r, ng=g, nb=b;
   if(comp==1) nr=v;
   else if(comp==2) ng=v;
   else nb=v;
   color nclr=(color)(nr + ng*256 + nb*65536);
   int flags=PaletteApplyColor(g_PalKind,nclr);
   PalUpdateLive();
   if(flags!=REFRESH_NONE) RefreshDisplay(flags);
}

//--- P-UI-131h: leave → put back what was there. A no-op when nothing was previewed,
//--- and `remember=false` on both sides: a hovered colour was never chosen.
//--- P-UI-131k: the RESTORE ends the preview's budget, so the put-back is the last
//--- thing the chart wears (a tail left owed would settle one frame later, i.e. the
//--- colour the user just left behind would outlive the gesture).
void PalHoverRestore()
{
   if(s_palHoverCell < 0) return;
   int kind=s_palHoverKind;
   color was=s_palHoverWas;
   s_palHoverCell=-1; s_palHoverKind=-1;
   if(kind < 0) { UIDragBudgetEnd(); return; }
   int flags=PaletteApplyColor(kind,was,false);
   PalUpdateLive();
   if(flags != REFRESH_NONE) RefreshDisplay(flags);   // still inside the budget → folds in
   UIDragBudgetEnd();                                 // …then lands ONCE, here
}

//--- the driver: one call per mouse move, and a cell crossing is the only thing that
//--- writes. P-UI-131k: THE PREVIEW MUST REACH THE OBJECT. It used to only
//--- `ThrottledChartRedraw()`, which repaints the window — and every surface in this
//--- palette (zones, edges, lines, HTF, TH3) has its look BAKED into its objects at
//--- render time, so the hovered colour was stored and the chart kept the old one:
//--- the reported «موس که روی رنگ‌ها می‌برم سریع اعمال نمیشه روی سطوح». It now rides
//--- the ONE heavy-pass budget the sliders and the mixer already share (P-UI-33): the
//--- first crossing paints at once, then at most one pass per `UI_DRAG_HEAVY_MS`
//--- 120 ms with cheap repaints between, and a still pointer costs nothing at all —
//--- so a sweep is bounded and cannot outrun the frame, and the surface follows.
void PalHoverPreview(const int mx,const int my)
{
   if(!g_PalOpen || g_PalTab != 0) { PalHoverRestore(); return; }   // MIXER tab: sliders, no cells
   int c=-1, r=-1;
   int reg=PalHoverCellAt(mx,my,c,r);
   if(reg < 0) { PalHoverRestore(); return; }
   int cell=reg*1000+r*100+c;
   if(cell == s_palHoverCell) return;                 // the same cell → write NOTHING
   color sw=PalHoverColorAt(reg,c,r);
   if(sw == clrNONE) return;                          // an unset recents slot is not a colour
   if(s_palHoverCell < 0)
   {
      s_palHoverWas=PaletteKindColor(g_PalKind);
      s_palHoverKind=g_PalKind;
      UIDragBudgetBegin();   // P-UI-131k: the sweep is a gesture, charged to the one budget
   }
   s_palHoverCell=cell;
   int flags=PaletteApplyColor(g_PalKind,sw,false);
   PalUpdateLive();
   if(flags != REFRESH_NONE) RefreshDisplay(flags);
}

// returns refresh flags when a palette interaction changed a color
//--- P-UI-74: id parses are EXACT, never a prefix test (P-UI-69's law for
//--- `Q0..Q7`, which lived on only one of the two colour families). Two ids
//--- start with `s`/`r` and mean something else entirely — the recents strip's
//--- own "Pick any color…" hint (`rempty`) and every future `s*` control — and
//--- `StringToInteger()` reads their tail as 0, i.e. the control would silently
//--- apply the palette's own (0,0) / recent[0].
bool PalCellIdParse(const string id,int &r,int &c)
{
   r=-1; c=-1;
   if(StringLen(id) < 4) return false;                 // "s0_0" is the shortest
   if(StringGetCharacter(id,0) != 's') return false;
   int us = StringFind(id,"_");
   if(us <= 1 || us >= StringLen(id)-1) return false;
   for(int i=1;i<us;i++)
   {
      ushort ch=StringGetCharacter(id,i);
      if(ch < '0' || ch > '9') return false;
   }
   for(int j=us+1;j<StringLen(id);j++)
   {
      ushort ch2=StringGetCharacter(id,j);
      if(ch2 < '0' || ch2 > '9') return false;
   }
   r=(int)StringToInteger(StringSubstr(id,1,us-1));
   c=(int)StringToInteger(StringSubstr(id,us+1));
   // P-DRAW-50: the ids are PAGE-LOCAL (the paint rebuilds on a page flip), so
   // the bound is the page's row count, not the table's 16.
   return (r >= 0 && r < PAL_ROWS && c >= 0 && c < PAL_COLS);
}
bool PalRecentIdParse(const string id,int &i)
{
   i=-1;
   if(StringLen(id) < 2 || StringGetCharacter(id,0) != 'r') return false;
   for(int k=1;k<StringLen(id);k++)
   {
      ushort ch=StringGetCharacter(id,k);
      if(ch < '0' || ch > '9') return false;
   }
   i=(int)StringToInteger(StringSubstr(id,1));
   return (i >= 0 && i < g_PalRecentCount);
}

int PalHandleClick(const string name)
{
   if(!g_PalOpen) return REFRESH_NONE;

   // P-UI-91: commit a pending hex edit before ANYTHING ELSE - including a click
   // that is not ours at all.
   //
   // This used to sit BELOW the namespace test on the next line, so a click on the
   // chart, on a ring button, or on a card behind the palette returned at that test
   // and never committed the typed colour. The value was silently discarded AND
   // g_PalHexFocus stayed latched, which made EventHandlers' hotkey guard
   // (`if(g_PalHexFocus || g_BkTextFocus) return;`) swallow F, E and hide-all for
   // as long as the palette stayed open. The flush has to own the click-away case,
   // because MT4 gives a focused OBJ_EDIT no ENDEDIT when focus is lost that way.
   if(g_PalHexFocus) FlushPalHex();

   string pfx=g_UI.btnPrefix+"Pal_";
   if(StringFind(name,pfx)!=0) return REFRESH_NONE;
   string id=StringSubstr(name,StringLen(pfx));

   if(id=="done" || id=="close")
   {
      g_PalHexFocus=false;
      PalClose();
      return REFRESH_NONE;
   }
   if(id=="hex")
   {
      g_PalHexFocus=true;
      return REFRESH_NONE;
   }
   //--- P-DRAW-64a2 — THE TWO ROLE CHIPS. The popup holds the KIND, the strip holds the
   //--- SLOT, and a click that changed one without the other would paint the fill's
   //--- slot with the border's colour — so the strip is asked, in its own vocabulary,
   //--- and it answers with the slot the rest of this module already reads.
   if(id=="tgtB" || id=="tgtF")
   {
      bool wantBorder = (id=="tgtB");
      PalHoverRestore();   // leaving a role must not leave ITS colour behind
      DrawStripPalRoleSet(wantBorder ? 0 : 1);
      g_PalKind = wantBorder ? PAL_DRAW_BORDER : PAL_DRAW_FILL;
      g_PalTgt  = PalTgtIndexOfKind(g_PalKind);
      PalDraw();
      return REFRESH_NONE;
   }
   if(id=="tgt")
   {
      // P-UI-131h: a named-but-not-ring kind (26/27) can be the open page's index, so
      // the ring clamps before stepping - otherwise the first click jumped to a random
      // target instead of the next one.
      g_PalTgt=(ClampInt(g_PalTgt,0,PalTgtCount()-1)+1)%PalTgtCount();
      PalHoverRestore();   // P-UI-131h: leaving the page must not leave ITS colour behind
      g_PalKind=PalTgtToKind(g_PalTgt);
      PalDraw();
      return REFRESH_NONE;
   }
    // P-UI-131h: the tab owns the cells, so a switch first puts back a live preview.
    if(id=="t0") { PalHoverRestore(); g_PalTab=0; PalDraw(); return REFRESH_NONE; }
    if(id=="t1") { PalHoverRestore(); g_PalTab=1; PalDraw(); return REFRESH_NONE; }
    // (no t2 — RECENT lives inline on the PALETTE tab)
    //--- P-DRAW-50: THE PAGER — the only way to the second 64 of the table. A
    //--- flip is a full repaint (the ids are page-local), and it restores a live
    //--- preview first, exactly like a tab switch: leaving the page must not
    //--- leave ITS colour on the target.
    if(id=="pg0" || id=="pg1")
    {
       PalHoverRestore();
       int want=BioPickPage() + ((id=="pg0") ? -1 : 1);
       if(want >= 0 && want < BIOPICK_PAGES)
       {
          BioPickPageSet(want);
          PalDraw();
       }
       return REFRESH_NONE;
    }

     // a palette cell "s{r}_{c}" — EXACT id (P-UI-74, the P-UI-69 law).
     // TV parity faces ride the same click: a trailing G names the rounded overlay.
     string cid=id;
     int cL=StringLen(cid);
     if(cL>2 && StringGetCharacter(cid,cL-1)=='G') cid=StringSubstr(cid,0,cL-1);
     int mr,mc;
     if(PalCellIdParse(cid,mr,mc))
   {
      PalHoverCommit();   // P-UI-131h: the click is the commitment — nothing is put back
      // P-DRAW-50: the id is page-local, so the table row is this page's first
      // row plus the id's own — one mapping, the same one the paint and the
      // hover region use.
      int flags=PaletteApplyColor(g_PalKind, PalPickColor(BioPickPageRow0()+mr,mc));
      if(g_PalOpen) PalUpdateLive();
      ChartRedraw();
      return flags;
   }

    // recent swatch "r{i}" — EXACT id ("rempty" is the empty-state hint)
    int ri;
    if(PalRecentIdParse(cid,ri))
   {
      PalHoverCommit();   // P-UI-131h
      int flags=PaletteApplyColor(g_PalKind, g_PalRecent[ri]);
      if(g_PalOpen) PalUpdateLive();
      ChartRedraw();
      return flags;
   }
   return REFRESH_NONE;
}

// keys while the palette is open: Esc closes, Enter applies typed hex
bool PalHandleKey(const int key)
{
   if(!g_PalOpen) return false;
   if(key==PNL_KEY_ESC)
   {
      g_PalHexFocus=false;
      PalClose();
      ChartRedraw();
      return true;
   }
   if(key==13 && g_PalHexFocus)
   {
      FlushPalHex();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Naming helpers                                                   |
//+------------------------------------------------------------------+
string PnlName(const int item,const int row,const string kind)
{
   return g_UI.btnPrefix + "Pnl" + IntegerToString(item) + "_" + IntegerToString(row) + "_" + kind;
}
string PnlHead(const int item,const string kind)
{
   return g_UI.btnPrefix + "Pnl" + IntegerToString(item) + "_" + kind;
}

//--- DISPLAY-row count of a card (what the renderer / hit-tests iterate).
//    Since R-PANELUI2 this is the SPEC table's length, not the setting count:
//    a section band is itself a 42px row, so card 1 is 12 settings but 15
//    display rows. Card 9 (Step) and 12 (Base Box) stay dynamic — their spec
//    is rebuilt whenever the mode / open tab changes (see PnlEnsureSpec).
int PnlRowsCount(const int item)
{
   if(item < 0 || item >= PNL_COUNT) return 0;
   if(item == 13) return g_PnlRows[item];   // mini strip — no rows rendered
   return PnlSpecRows(item);
}

//--- overall on-screen size of one open item. Item 13 (Base Box MINI) is the
//    compact TV-style strip — everything else is a full row-card. Every
//    geometry caller (clamp, point-inside, BkHoldFire anchor) goes through
//    these so the strip is never treated as a 56+7*50+48 tall card.
//    R-BKSTRIP (2026-09-07).
int PnlPanelH(const int item)
{
   if(item == 13) return PNL_TB_H;
   if(item < 0 || item >= PNL_COUNT) return 0;
   return PNL_HEAD_H + PnlPairRows(item) * PNL_ROW_H + PNL_FOOT_H;
}
int PnlPanelW(const int item)
{
   if(item == 13) return PNL_TB_W;   // the TV strip is its own width, not a 312 card
   return PnlCardW(item);
}


//+------------------------------------------------------------------+
//| Parse "<prefix>Pnl<item>_<row>_<kind>"  or  "<prefix>Pnl<item>_<headkind>" |
//+------------------------------------------------------------------+
void ParsePnlName(const string name,int &item,int &row,string &kind)
{
   item=-1; row=-1; kind="";
   int pos=StringFind(name,"Pnl");
   if(pos<0) return;
   pos+=3;
   int s=pos;
   while(pos<StringLen(name) && name[pos]>='0' && name[pos]<='9') pos++;
   item=(int)StringToInteger(StringSubstr(name,s,pos-s));
   if(pos>=StringLen(name) || name[pos]!='_') return;
   pos++;
   s=pos;
   while(pos<StringLen(name) && name[pos]>='0' && name[pos]<='9') pos++;
   if(pos>s)
   {
      row=(int)StringToInteger(StringSubstr(name,s,pos-s));
      if(pos<StringLen(name) && name[pos]=='_') kind=StringSubstr(name,pos+1);
   }
   else
   {
      kind=StringSubstr(name,s);
   }
}

//--- Timeframe-lock option helpers (panel 4 — TIMEFRAME segment row)
//
// R-TF-UNIT: the lock period is a MINUTE COUNT everywhere it is consumed -
// `g_lockedPeriod` is compared against `Period()`, written to the lock's global
// variable, and named by `PeriodToString(g_lockedPeriod)`. These two helpers
// used to speak in PERIOD_* constants, which on MT4 are the same numbers and on
// MT5 are not: the badge read "16385" instead of "H1", and LockOptFromPeriod()
// matched nothing, so the panel always showed the segment as "Cur".
int LockOptFromPeriod(const int p)
{
   if(p==1)     return 1;
   if(p==5)     return 2;
   if(p==15)    return 3;
   if(p==30)    return 4;
   if(p==60)    return 5;
   if(p==240)   return 6;
   if(p==1440)  return 7;
   if(p==10080) return 8;
   if(p==43200) return 9;
   return 0;
}

// STEPOVERRIDE-OFF: override helpers retired with the OVERRIDE row —
// card 9 segments now map 1:1 onto the enum, no translation needed.
//int StepOverrideFromOpt(const int idx)
//{
//   if(idx <= 0) return -1;
//   return idx - 1;
//}
//
//int StepOverrideOpt(const int v)
//{
//   if(v < 0) return 0;
//   return v + 1;
//}

//+------------------------------------------------------------------+
//| PnlSetDef — the SETTING-level descriptor of one row.             |
//| Address space = the legacy per-card row index (what PnlDefVal /  |
//| PnlCurrent / PnlApply / the palette tables all speak). The      |
//| DISPLAY row the renderer uses is translated by PnlRowDef below.  |
//| Rule from here on: NEVER call this with a display row.           |
//+------------------------------------------------------------------+
void PnlSetDef(const int item,const int row,int &kind,string &label,
               int &minV,int &maxV,double &step,string &unit,string &opts)
{
   kind=0; label=""; minV=0; maxV=100; step=1; unit=""; opts="";
   if(item==0)   // TRIGGER ZONES — zone appearance only. Unified line look
                 // lives on the LINES card (7); MAX LEVELS lives on STEP MODE.
   {
      if(row==0)       { label="TRANSPARENCY"; unit="%"; }
      else if(row==1)  { kind=4; label="COLOR"; }
      else if(row==2)  { kind=4; label="LABEL COLOR"; }
      // P-UI-131j: the LABEL's opacity, minV -1 = the AUTO end (PnlFormat prints it):
      // -1 follows the Lines transparency, 0 stays a real, deliberate "solid".
      else if(row==4)  { label="LABEL OPACITY"; unit="%"; minV=-1; maxV=100; }
      else             { kind=1; label="SHOW"; }
   }
   else if(item==1)   // ZONES & LEVELS — the MAIN card. Row 0 = MID ZONES,
                      // the same master the ring item toggles; zone appearance
                      // grouped, then step order/midpoint, then sub-card navs
                      // (STRUCTURE zones + unified LINES).
   {
      if(row==0)       { kind=1; label="MID ZONES"; }
      else if(row==1)  { kind=1; label="SHOW LINES"; }
      // P-UI-62: three PICTURES, not two pictures and a second visibility switch.
      // "Hidden" was the MID ZONES master above under another name (it deleted the
      // family), so the third slot is the state that shows BOTH halves at once - the
      // band AND its edge - which is what makes the GEOMETRY card's BORDER and
      // BORDER WIDTH rows act on something the user can see.
      // P-UI-131d: "ZONE STYLE" (≈91px with the glyph chip) did NOT fit in the space
      // the three pills leave (≈87px) — the caption was eating the gap to pay for
      // itself. The band above already says ZONES, so the caption is "STYLE" now.
      else if(row==2)  { kind=2; label="STYLE"; opts="Filled|Empty|Outlined"; minV=0; maxV=2; }
      else if(row==3)  { label="TRANSPARENCY"; unit="%"; minV=0; maxV=100; }
      else if(row==4)  { label="HEIGHT"; unit="%"; minV=1; maxV=100; }
      else if(row==5)  { kind=2; label="BORDER"; opts="Solid|Dash|Dot|DashDot|DashDotDot"; minV=0; maxV=ILS_COUNT-1; }
      else if(row==6)  { label="BORDER WIDTH"; minV=1; maxV=5; }
      // P-UI-63: the EDGE's transparency. `TRANSPARENCY` above is the BAND's - one row
      // per half of the picture, so «شفافیت خط و زون جدا از هم» needs no other control.
      else if(row==7)  { label="BORDER TRANSPARENCY"; unit="%"; minV=0; maxV=100; }
      else if(row==8)  { kind=1; label=PNL_LBL_SSLS_ORDER; }
      // MIDPOINT-OFF (2026-09-13, P-UI-47): the midpoint line is deleted every
      // render by the pipeline's legacy cleanup — row kept for the address space
      // only, no display row renders it.
      else if(row==9)  { kind=1; label="MIDPOINT"; }
      else if(row==10) { kind=5; label="STRUCTURE L1-L5"; opts="11"; }   // NAV → structure sub-card
      // P-UI-126: the chip's card, reached from here (NAV rows are the only door a
      // card without a ring item has).
      else if(row==12) { kind=5; label="HOVER CHIP"; opts="4"; }
      // P-UI-131: the GENERAL card's door, APPENDED (row 13) so no address moved.
      else if(row==13) { kind=5; label="GENERAL"; opts="14"; }
      // P-UI-131h: the MID ZONE edge's two halves, each a colour and an opacity of its
      // own. minV -1 on the sliders is the AUTO end (see PnlFormat): -1 = follow BORDER
      // TRANSPARENCY above, and 0 stays a real, deliberate "solid".
      else if(row==14) { kind=4; label="EDGE TOP"; }         // lit/top line
      else if(row==15) { kind=4; label="EDGE BOTTOM"; }      // shaded/bottom line
      else if(row==16) { label="TOP OPACITY"; unit="%"; minV=-1; maxV=100; }
      else if(row==17) { label="BOTTOM OPACITY"; unit="%"; minV=-1; maxV=100; }
      // P-UI-220: the levels' own ANCHOR door. `inpTHStartPointType` (Midpoint|High|
      // Low|Custom|Prev Close) was settable from the dialog and from the CUSTOM PRICE
      // card's ANCHOR band, and that card has no ring item of its own — it opens by
      // HOLDING the PIN item or the custom-price line. So the setting read as missing
      // («توی پنل ها ندیدم کجاهستش») while it was live the whole time.
      else if(row==18) { kind=5; label="START POINT"; opts="8"; }   // NAV → custom price card
      else             { kind=5; label="LINES"; opts="7"; }              // NAV → unified lines card
   }
   else if(item==2)   // ATR LABELS — the chart-labels card (High/Low
                      // pip-distance labels were retired by P-LBL-12; this
                      // card keeps the countdown, ATR and trade-plan labels)
   {
      // Rows 0-3 = the countdown tag's OWN settings (independent of the ATR
      // block — turning the ATR labels off keeps the countdown).
      if(row==0)       { kind=1; label="COUNTDOWN"; }
      else if(row==1)  { kind=4; label="COUNT COLOR"; }
      else if(row==2)  { label="COUNT SIZE"; minV=0; maxV=24; unit="pt"; }
      else if(row==3)  { label="COUNT GAP"; minV=0; maxV=40; unit="px"; }
      else if(row==4)  { kind=1; label="ATR LABELS"; }
      else if(row==5)  { kind=1; label="ATR TARGETS"; }
      else if(row==6)  { kind=1; label="TRADE LABELS"; }
      else if(row==7)  { kind=1; label="HUNTER ROW"; }
      else if(row==8)  { kind=1; label="TP ROW"; }
      // P-UI-70c: «این pip label چیه؟» — the caption was the problem, not the
      // setting: it toggles the pip-DISTANCE labels ON THE HIGH/LOW LINES
      // (`inpShowPipDistanceLabels`, read by LabelFunctions AND LevelPipeline),
      // which no two-word caption in a corner card can convey. Renamed to say
      // WHERE those labels live; the setting address is untouched.
      // P-LBL-12 (2026-10-17): the pip labels themselves are retired, so this
      // row is off the card (see the spec table). The branch stays as the
      // address stub - `row_arms` counts branches, not displays, and a
      // renumbered fallthrough below would misland the proof (P-TH3-PB-MAN).
      else if(row==9)  { kind=1; label="H/L PIP LABELS"; }
      // ROW-GAP-OFF is OVER (P-UI-70c): the row was retired because its runtime
      // copy `g_atrLabelRowGap` was dead, and the trade card has consumed that
      // copy since P-LBL-09 (the settings layer redirects
      // `inpATRTradeLabelRowGap` to it) — so the slider moves the card's seam
      // for real and is rendered again. Its range is the CARD's clamp
      // (`TREX_CARD_MAX_ROW_GAP`), never a number of its own: a slider whose max
      // is past the engine's clamp stops responding at the end of its travel.
      else if(row==10) { label="ROW GAP"; minV=0; maxV=TREX_CARD_MAX_ROW_GAP; unit="px"; }
      // P-UI-70d: the trade card's OWN personalisation, in the panel (user:
      // «تنظیمات شخصی سازی این trex sl , tp ها چرا در پنل نیستش»). Every row here
      // writes the same setting the group-13 dialog input writes, so a panel row
      // can never disagree with the chart.
      else if(row==11) { label="TRADE SIZE"; minV=0; maxV=24; unit="pt"; }
      else if(row==12) { label="STAMP GAP"; minV=0; maxV=TREX_CARD_MAX_GAP_ROWS; unit="rows"; }
      else if(row==13) { label="CARD MARGIN"; minV=0; maxV=TREX_CARD_MAX_MARGIN_BOTTOM; unit="px"; }
      // P-UI-70d: the five colour cells of the CARD COLORS row. `PnlCsetKey`
      // strips " COLOR" for the cell tooltip, so the captions read as the piece
      // they paint (the palette header names the same piece via PalTgtLabel).
      else if(row==14) { kind=4; label="TR COLOR"; }
      else if(row==15) { kind=4; label="EX COLOR"; }
      else if(row==16) { kind=4; label="HUNTER COLOR"; }
      else if(row==17) { kind=4; label="TRADE COLOR"; }
      else if(row==18) { kind=4; label="SPREAD COLOR"; }
       // P-LEGATR: APPENDED (row 19), so rows 0..18 keep their addresses and the
       // persisted OV_ keys keep their meaning.
       // P-ANCHOR-LAST-MOVE (2026-10-22): row 20 (LAST OBJECT) left this card, so
       // PRE-CP ATR is the trailing branch and the card ends at 19 — `row_arms`
       // counts branches, and the fallthrough's row is "how many branches
       // preceded it", which is now 19, the same address it already wrote.
      else             { kind=1; label="PRE-CP ATR"; }
   }
    else if(item==3)   // TH LABELS
    {
       if(row==0)       { kind=1; label="TH LABELS"; }
       else if(row==1)  { kind=1; label="FRACTAL THs"; }
       else if(row==2)  { kind=1; label="STANDARD THs"; }
       else if(row==3)  { kind=1; label="TH TARGETS"; }
        else if(row==4)  { label="MARGIN BOTTOM"; minV=10; maxV=200; }
        // P-TH-VOLNORM: the price-only scale switch, as the block's trailing
       // fallthrough (the simulator counts preceding branches, so the appended
       // setting takes the trailing slot and every address above keeps its
       // number). Switch defaults (kind=1, 0/100): ON/OFF. OFF = classic TH.
       //
       // (Never write a COMPLETE row-branch test in this comment: `row_arms` in
       // panel-wiring-audit.py scans the raw text for the whole `if(`+`row`+`==`
       // shape, so a branch spelled here becomes a phantom arm with no caption
       // and the audit reports a blank control. This cost one red run already.)
       else             { kind=1; label="VOL NORM"; }
    }
    // P-UI-154 (2026-10-13) — THE HOVER CHIP'S ROW HAD NO DEFINITION.
    // MEASURED: this function carries a branch for every card EXCEPT 4, so the
    // chip's one row fell through to the opening defaults set at the top of it —
    // `kind=0` (PNL_K_SL, a slider) and `label=""`. The card the user opens to
    // configure the chip therefore showed a NAMELESS 0..100 SLIDER where its
    // single ON/OFF switch belongs («چرا تنظیماتش ناقص هستش»). OFF = «با موس»
    // (the hover tip, the shipped default), ON = «همیشه فعال» (the banner kept up
    // at its place). Every OTHER path already knew the setting: `PnlCurrent`
    // (case 4) reads it, `PnlApply` (case 4) writes it and calls
    // `CircTipModeChanged`, and `PnlDefValSet` falls through to `return 0` —
    // which IS that default. Only this descriptor was missing, which is exactly
    // why nothing else noticed. kind=1 (PNL_K_SW) is the switch the apply path
    // implements; the icon stays the spec's own "tag" (BiotakPanels_PalA).
    else if(item==4)   // HOVER CHIP — the chip's MODE (the card's only setting)
    {
       if(row==0)       { kind=1; label="ALWAYS SHOWN"; }
    }
    // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
    // P-TH3-PB-MAN (2026-09-21): BASE PIPS is the trailing fallthrough, like
    // VOL NORM on card 3 — `tools/panel-mt4-sim.py` derives the
    // fallthrough's row as "how many row branches preceded it", so it MUST be
    // the LAST branch or the simulator drops a row from the proof. SHOW LABELS
    // therefore gets its own EXPLICIT branch above (the wiring audit also
    // needs it: it reads the trailing statement as answering only row 8).
    else if(item==5)   // TH3 TOOL
    {
       if(row==0)       { kind=1; label="ENABLED"; }
       else if(row==1)  { kind=2; label="MODE"; opts="Steps|AB=CD"; }
       // "MOVEMENT STEP", not "BASE STEP": this slider is the step of the move
       // (its old label sat next to nothing called a "base", and the tool also
       // called the same number a "frequency" on the chart — one value, one name).
       else if(row==2)  { label="MOVEMENT STEP"; minV=1; maxV=100; step=0.5; unit="%"; }
       else if(row==3)  { label="WIDTH"; minV=1; maxV=5; }
       else if(row==4)  { label="STYLE"; minV=0; maxV=ILS_COUNT-1; }
       else if(row==5)  { kind=4; label="COLOR"; }
       else if(row==6)  { kind=4; label="PIP COLOR"; }
       else if(row==7)  { kind=1; label="SHOW LABELS"; }
       // 0 = OFF: the pattern timeframe's own ATR answers (the shipped default
       // before this knob). Same bound the load clamp reads, so the slider can
       // always reproduce what it saved.
       else             { label="BASE PIPS"; minV=0; maxV=2000; step=1; unit="p"; }
    }
   else if(item==6)   // HTF CANDLES
   {
       if(row==0)       { kind=1; label="ENABLED"; }
       else if(row==1)  { kind=2; label="TIMEFRAME"; opts="Structure|Pattern|H4|H1|M30|M15|D1|W1|MN1"; }
       else if(row==2)  { label="TRANSPARENCY"; unit="%"; }
      else if(row==3)  { kind=4; label="BULL COLOR"; }
      else if(row==4)  { kind=4; label="BEAR COLOR"; }
      else if(row==5)  { kind=4; label="WICK COLOR"; }
      else if(row==6)  { kind=4; label="BORDER COLOR"; }
      // P-UI-68: this slider is the shadow box's PIXEL FLOOR (the old WICK
      // WIDTH semantics, kept alive instead of retired): a percentage width
      // collapses to nothing when the chart is zoomed out, and this is what
      // guarantees the shadow stays visible. The label names the shadow, the
      // other two rows of the trio live in the CANDLE band with the body.
      // The slider RANGES are literals (this file declares no engine bounds) and
      // the engine's clamps are the named ones in HTFCandles.mqh — two places
      // that must agree, so write-budget-audit's `htf-geometry` group reads both
      // and fails if they drift (P-UI-68).
      else if(row==7)  { label="SHADOW MIN"; minV=1; maxV=5; }
      else if(row==8)  { label="BORDER WIDTH"; minV=1; maxV=5; }
      else if(row==9)  { kind=1; label="SHOW WICKS"; }
      // P-UI-131d: the caption sizes itself against the pills now, and at a 120-DPI
      // chart "BOX MODE" needs 81px of the 69 the three pills leave — it read as
      // glued. The card IS the candle's box, so "BOX" says the same thing.
      else if(row==10) { kind=2; label="BOX"; opts="Hollow|Filled|Both"; }
      else if(row==11) { label="SHADOW WIDTH"; unit="%"; minV=6; maxV=100; }
      else             { label="SHADOW GAP"; unit="%"; minV=0; maxV=40; }
   }
   else if(item==7)   // LINES — the unified [08.4] line appearance card.
                      // ONE color/style/width/transparency for ALL pipeline
                      // lines (trigger-subdivision + structure-interval).
                      // Row 1 SHOW mirrors the Zones card row 1 (same g_showLines).
   {
      if(row==0)       { kind=5; label="BACK"; opts="1"; }   // NAV → Zones & Levels card
      else if(row==1)  { kind=1; label="SHOW"; }
      else if(row==2)  { label="WIDTH"; minV=1; maxV=5; }
      else if(row==3)  { kind=2; label="STYLE"; opts="Solid|Dash|Dot|DashDot|DashDotDot"; minV=0; maxV=ILS_COUNT-1; }   // redesign: dropdown, not a slider
      else if(row==4)  { label="TRANSPARENCY"; unit="%"; minV=0; maxV=100; }
      else             { kind=4; label="COLOR"; }
   }
   // item==7 retired Tools/Misc rows are gone (were duplicates of CustomPrice,
   // Zones & the STRUCTURE card) — the slot now hosts the LINES card above.
    else if(item==8)   // CUSTOM PRICE PIN — the pin only (the pip-distance
                       // labels that used to live on the ATR LABELS card are
                       // retired, P-LBL-12)
    {
       if(row==0)       { label="WIDTH"; minV=1; maxV=5; }
       else if(row==1)  { kind=4; label="COLOR"; }
       // P-UI-101 (2026-09-22): row 2 is the LOCK now (the magnet's retired row).
       // Row 3 stays for the address space only — no display row renders it
       // (P-UI-47's convention); the engine that read it is commented.
       else if(row==2)  { kind=1; label="LOCK"; }
       else if(row==3)  { label="MAGNET SENS"; minV=0; maxV=100; unit="p"; }
       // P-UI-154: the START POINT as the block's trailing fallthrough (four
       // preceding branches, so the simulator reads row four). kind=2 options
       // run in enum order (ConstantsAndEnums.mqh:370): the press lands 0..4
       // and the apply writes the same number back — no index table to drift.
       else             { kind=2; label="START POINT"; opts="Midpoint|High|Low|Custom|Prev Close"; minV=0; maxV=4; }
    }
    else if(item==9)   // STEP MODE — mode segments + the SELECTED mode's
                       // own settings inline below + MAX LEVELS last.
    {
       if(row==0) { kind=2; label="STEP MODE"; opts="TH|SS-LS|Combo|Factor"; minV=0; maxV=3; }
       else if(row==PnlStepMaxLevelsRow()) { label="MAX LEVELS"; minV=1; maxV=MAX_SAFE_LEVELS; }
       else PnlStepSectionRowDef(row-1, kind, label, minV, maxV, step, unit, opts);
    }
   else if(item==11)  // STRUCTURE — sub-card opened from the Zones & Levels card
   {
      if(row==0)       { kind=5; label="BACK"; opts="1"; }   // NAV → Zones & Levels card
      else if(row==1)  { kind=1; label="SHOW STRUCTURE"; }
      else if(row==2)  { kind=1; label="STRUCTURE L1"; }
      else if(row==3)  { kind=1; label="STRUCTURE L2"; }
      else if(row==4)  { kind=1; label="STRUCTURE L3"; }
      else if(row==5)  { kind=1; label="STRUCTURE L4"; }
      else             { kind=1; label="STRUCTURE L5"; }
   }
   else if(item==10)  // FACTOR
   {
      if(row==0)       { kind=2; label="MODE"; opts="Auto|Manual"; minV=0; maxV=1; }
      else if(row==1)  { kind=2; label="DISPLAY"; opts="Classic|Direct"; minV=0; maxV=1; }
      else if(row==2)  { kind=2; label="BASIS"; opts="Control|SS|LS|TH|Trigger|Pattern|Structure|Combo"; minV=0; maxV=7; }
      else if(row==3)  { label="VALUE"; minV=1; maxV=500; }
      else if(row==4)  { label="WIDTH"; minV=1; maxV=5; }
      else if(row==5)  { kind=2; label="STYLE"; opts="Solid|Dash|Dot|DashDot|DashDotDot"; minV=0; maxV=ILS_COUNT-1; }   // redesign: dropdown, not a slider
      else             { kind=4; label="COLOR"; }
   }
   else if(item==12)  // BASE BOX — TV-parity 2026-09-07 tabbed card (row 0 =
                      // Style|Text|Setup segments, like the Step card's mode row).
                      // Style = border + fill (TV Style tab) · Text = user text
                      // inside the box (TV Text tab: content + size + B/I +
                      // align + color; coords are edited by dragging, shown in
                      // the box tooltip = TV Coordinates) · Setup = R:R +
                      // Entry/SL/TP + INFO + INFO SIZE (P-BK-27) + TEMPLATE
                      // (= TV Template dropdown; visibility is automatic:
                      // commit TF + lower, tooltip).
   {
      if(row==0) { kind=2; label="TAB"; opts="Style|Text|Setup"; minV=0; maxV=2; }
      else BkSecRowDef(row-1, kind, label, minV, maxV, step, unit, opts);
   }
   else   if(item==13)  // BASE BOX MINI — the row defs below are LEGACY: item 13 no
                      // longer renders as a row-card. PnlCreate(13) draws the
                      // compact TV-style strip (BkMiniStripCreate) and all
                      // presses route to BkMiniStripPress. Only row 0 (BORDER
                      // COLOR / PAL_BOX palette binding) is still consulted by
                      // the palette code. R-BKSTRIP (2026-09-07).
   {
      if(row==0)       { kind=4; label="BORDER COLOR"; }
      else if(row==1)  { label="TP COUNT"; minV=1; maxV=BK_TP_PLAN_MAX; }   // P-BK-50
      else if(row==2)  { kind=2; label="INFO"; opts="Auto|Show|Corner"; minV=0; maxV=2; }   // P-BK-58 (same mirror as card 12)
      else if(row==3)  { kind=2; label="PRESET"; opts="Navy|Ocean|Mono|Custom"; minV=0; maxV=3; }
      else if(row==4)  { kind=2; label="LOCK"; opts="Off|On"; minV=0; maxV=1; }
      else if(row==5)  { kind=5; label="DELETE"; opts="DEL"; }   // ACTION → delete held box
      else             { kind=5; label="MORE"; opts="12"; }      // NAV → full Base Box card
   }
   else if(item==14)  // P-UI-131 — GENERAL SETTINGS (cross-card). Every bound here is
   {                  // the SAME number the loader clamps with, so a saved value is
                      // one this control can reproduce.
      if(row==0)       { label="MAX LEVELS"; minV=1; maxV=MAX_SAFE_LEVELS; }
      else if(row==1)  { label="LABEL SIZE"; minV=4; maxV=24; unit="pt"; }
      else if(row==2)  { label="ROW GAP"; minV=0; maxV=TREX_CARD_MAX_ROW_GAP; unit="px"; }
      else if(row==3)  { kind=2; label="FONT"; opts=LabelFontOpts(); minV=0; maxV=LABEL_FONT_N-1; }
      else if(row==4)  { label="MARGIN TOP"; minV=0; maxV=200; unit="px"; }
      else if(row==5)  { label="MARGIN LEFT"; minV=0; maxV=300; unit="px"; }
      else if(row==6)  { label="COLUMN GAP"; minV=0; maxV=200; unit="px"; }
      else if(row==7)  { label="SECTION GAP"; minV=0; maxV=200; unit="px"; }
      else if(row==8)  { label="MAX WIDTH"; minV=50; maxV=600; unit="px"; }
      else if(row==9)  { label="CARD MARGIN"; minV=0; maxV=TREX_CARD_MAX_MARGIN_BOTTOM; unit="px"; }
      else if(row==10) { label="TH MARGIN"; minV=10; maxV=200; unit="px"; }   // card 3's own bounds
      else if(row==11) { label="ROW GAP"; minV=0; maxV=TREX_CARD_MAX_ROW_GAP; unit="px"; }
      else if(row==12) { label="TRADE SIZE"; minV=0; maxV=24; unit="pt"; }
      else if(row==13) { label="STAMP GAP"; minV=0; maxV=TREX_CARD_MAX_GAP_ROWS; unit="rows"; }
      else             { kind=5; label="HOVER CHIP"; opts="4"; }   // NAV → the chip's own card
   }
   else if(item==15)  // P-SESS — SESSIONS: the overview. Every bound is the same
   {                  // named number the loader clamps with (Runtime_A), so a
                      // saved value is one this control can reproduce.
      if(row==0)       { kind=1; label="SESSIONS"; }        // master (mute-gated, F)
      else if(row==1)  { label="PAST DAYS"; minV=0; maxV=SESS_HIST_MAX; }
      else if(row==2)  { label="FUTURE DAYS"; minV=0; maxV=SESS_FUT_MAX; }
      else if(row==3)  { kind=1; label="H/L LINES"; }
      else if(row==4)  { kind=1; label="LINE LABELS"; }
      else if(row==5)  { kind=1; label="RANGE TEXT"; }
      else if(row==6)  { kind=1; label="PRIOR DAY"; }
      else if(row==7)  { kind=1; label="OVERLAP"; }
      else if(row==8)  { kind=1; label="COUNTDOWN"; }
      else if(row==9)  { kind=1; label="ALERTS"; }
      // P-SESS-14 — THE LOOK. One numeric row after the seven switches.
      // P-SESS-25 (2026-10-30): THE ROW NOW SAYS WHAT IT DOES. «رنگ‌ها رو هم شفافیت
      // براش بزار … که کم رنگ بشه» — it was spelled FILL % (ink the body KEEPS), so
      // the number a user had to reach was the complement of the one he thinks in.
      // The address (10) and the stored SSFA (ink %) do NOT move; only the face and
      // the arithmetic: TRANSPARENCY = 100 - ink, and 0 is a solid box.
      else if(row==10) { label="TRANSPARENCY"; minV=0; maxV=100; unit="%"; }
      // P-SESS-25 — «یا باکس خالی باشه هر چی کاربر خواستش»: one STYLE row for the
      // whole family (the editor keeps its per-slot STYLE), APPENDED at 16 so no
      // address above it moves and no persisted slot re-decodes.
      else if(row==16) { kind=2; label="STYLE"; opts="Filled|Empty"; minV=0; maxV=1; }
      // P-SESS-15 — THE ZONE LAW. OFF = the classic fixed table every session chart
      // quotes (Tokyo 00-09Z, London 08-17Z, NY 13-22Z, Sydney 21-06Z); ON = each
      // city's OWN clock, so its DST term moves the edge by the hour it really moves.
      else if(row==11) { kind=1; label="ZONE LAW"; }
      // P-SESS-18 — THE TRADINGVIEW LEVELS. TV's Sessions draws the window's
      // MIDPOINT (50 % of its range), its MEAN (average price), its VWAP and its
      // TRENDLINE (least squares through the closes). One dropdown, five choices,
      // ALL by default: "make it like TradingView" means these are on.
      else if(row==13) { kind=2; label="TV LEVELS"; opts="Off|Midpoint|Mean|VWAP|Trend|All"; minV=0; maxV=5; }
      // P-SESS-19 — THE STRIP. TV's "Show Sessions Divider": the active session
      // coloured along the BOTTOM of the chart, plus a mark where it begins.
      else if(row==14) { kind=1; label="STRIP"; }
      else             { kind=5; label="EDIT SESSIONS"; opts="16"; }   // NAV → the editor
   }
   else if(item==16)  // P-SESS — SESSION EDITOR: one slot at a time (row 0 picks
   {                  // it, view-only). Time rows read/write the slot's minutes;
                      // the HH/MM pair splits one startMin into the two sliders.
      if(row==0)       { kind=2; label="SESSION"; opts="Tokyo|London|New York|Sydney|Frankfurt|Dubai|Chicago|Custom"; minV=0; maxV=SESS_SLOTS-1; }
      else if(row==1)  { kind=2; label="PRESET"; opts="Tokyo|London|New York|Sydney|Frankfurt|Dubai|Chicago|Custom"; minV=0; maxV=SESS_SLOTS-1; }
      else if(row==2)  { kind=2; label="TIMEZONE"; opts="Server|UTC|Tokyo|London|Frankfurt|New York|Chicago|Sydney|Dubai|Istanbul|Custom"; minV=0; maxV=SZ_CUSTOM; }
      // the offset slider is in HOURS (what a user says); the codec carries minutes
      else if(row==3)  { label="UTC OFFSET"; minV=SESS_CUSTOM_OFF_LO/60; maxV=SESS_CUSTOM_OFF_HI/60; unit="h"; }
      else if(row==4)  { label="START HOUR"; minV=0; maxV=23; }
      else if(row==5)  { label="START MIN"; minV=0; maxV=55; step=5; }
      else if(row==6)  { label="END HOUR"; minV=0; maxV=23; }
      else if(row==7)  { label="END MIN"; minV=0; maxV=55; step=5; }
      // the two grid rows: `opts` names the table the chips kind taps write
      else if(row==8)  { kind=PNL_K_CHIPS; label="DAYS"; opts="days"; }
      else if(row==9)  { kind=PNL_K_CHIPS; label="COLOR"; opts="color"; }
      else if(row==10) { kind=2; label="STYLE"; opts="Filled|Outline|Mid"; minV=0; maxV=2; }
      else if(row==11) { kind=1; label="ACTIVE"; }
      else             { kind=5; label="OVERVIEW"; opts="15"; }   // NAV → back to 15
   }
}


//--- how many SETTINGS this display row folds in (1 normally)
int PnlRowMembers(const int item,const int dispRow)
{
   int si = PnlSpecIdx(item,dispRow);
   if(si < 0) return 1;
   int n = g_PnlSpec[si].n;
   return (n < 1) ? 1 : n;
}

//--- the SETTING row behind the k-th member of a multi-setting display row
int PnlMemberRow(const int item,const int dispRow,const int k)
{
   int s0 = PnlSetRow(item,dispRow);
   if(s0 < 0) return -1;
   int n = PnlRowMembers(item,dispRow);
   if(k < 0 || k >= n) return -1;
   return s0 + k;
}

string PnlRowIcon(const int item,const int dispRow)
{
   int si = PnlSpecIdx(item,dispRow);
   if(si < 0) return "";
   return g_PnlSpec[si].ico;
}
string PnlRowKey(const int item,const int dispRow)
{
   int si = PnlSpecIdx(item,dispRow);
   if(si < 0) return "";
   return g_PnlSpec[si].key;
}
string PnlRowExt(const int item,const int dispRow)
{
   int si = PnlSpecIdx(item,dispRow);
   if(si < 0) return "";
   return g_PnlSpec[si].ext;
}
int PnlSecCount(const int item,const int dispRow)
{
   int si = PnlSpecIdx(item,dispRow);
   if(si < 0) return 0;
   return g_PnlSpec[si].cnt;
}

//--- the DISPLAY kind of a row (PNL_K_*). PNL_K_LEGACY defers to PnlSetDef.
int PnlRowKind(const int item,const int dispRow)
{
   int rk; string l,u,o; int mn,mx; double st;
   if(item < 0 || item >= PNL_COUNT) return PNL_K_SEC;
   PnlEnsureSpec(item);
   if(g_PnlSpecCount[item] == 0)                    // no spec -> the setting's kind
   {
      PnlSetDef(item,dispRow,rk,l,mn,mx,st,u,o);
      return rk;
   }
   int si = PnlSpecIdx(item,dispRow);
   if(si < 0) return PNL_K_SEC;
   int k = g_PnlSpec[si].kind;
   if(k != PNL_K_LEGACY) return k;
   PnlSetDef(item,g_PnlSpec[si].s0,rk,l,mn,mx,st,u,o);
   return rk;
}

//--- the k-th MEMBER's own setting kind (a .cset cell is a colour row, ...)
int PnlMemberKind(const int item,const int dispRow,const int k)
{
   int r = PnlMemberRow(item,dispRow,k);
   if(r < 0) return -1;
   int rk; string l,u,o; int mn,mx; double st;
   PnlSetDef(item,r,rk,l,mn,mx,st,u,o);
   return rk;
}

//--- .cset cell caption: "BULL COLOR" -> "BULL" (preview cell key)
string PnlCsetKey(const string lbl)
{
   int p = StringFind(lbl," COLOR");
   if(p > 0) return StringSubstr(lbl,0,p);
   return lbl;
}

//+------------------------------------------------------------------+
//| PnlRowDef — the DISPLAY-row descriptor every renderer / hit-test  |
//| uses. `row` is a display row (0 .. PnlRowsCount(item)-1).        |
//| A section band yields kind=PNL_K_SEC with the band title in        |
//| `label`; every other row yields the member settings' own kind /   |
//| label / range, so all existing callers keep working unchanged.    |
//+------------------------------------------------------------------+
void PnlRowDef(const int item,const int row,int &kind,string &label,
               int &minV,int &maxV,double &step,string &unit,string &opts)
{
   kind=PNL_K_SEC; label=""; minV=0; maxV=100; step=1; unit=""; opts="";
   if(item < 0 || item >= PNL_COUNT) return;
   PnlEnsureSpec(item);
   if(g_PnlSpecCount[item] == 0)            // no spec card (13) -> the legacy def
   {
      PnlSetDef(item,row,kind,label,minV,maxV,step,unit,opts);
      return;
   }
   int si = PnlSpecIdx(item,row);
   if(si < 0) return;                       // out of range -> a band that renders nothing
   if(g_PnlSpec[si].s0 < 0)                 // section band
   {
      label = g_PnlSpec[si].sec;
      return;
   }
   PnlSetDef(item,g_PnlSpec[si].s0,kind,label,minV,maxV,step,unit,opts);
   if(g_PnlSpec[si].kind != PNL_K_LEGACY) kind = g_PnlSpec[si].kind;
}

string PnlTitleText(const int item)
{
   if(item==1)  return "Zones & Levels";
   if(item==0)  return "Trigger Zones";
   if(item==2)  return "ATR Labels";
   if(item==3)  return "TH Labels";
   if(item==4)  return "Hover Chip";   // P-UI-126 (was the retired View Lock)
   if(item==5)  return "TH3 Tool";   // TH3TOOL-ON (2026-09-19)
   if(item==6)  return "HTF Candles";
   if(item==7)  return "Lines";
   if(item==8)  return "Custom Price";
   if(item==9)  return "Step Mode";
   if(item==11) return "Structure Levels";
   if(item==12) return "Base Box";
   if(item==13) return "Base Box";
   if(item==14) return "General Settings";   // P-UI-131
   if(item==15) return "Sessions";           // P-SESS
   if(item==16) return "Session Editor";
   return "Factor";
}

//--- Cycle options (P-UI-92): 0=Structure (16x — two fractal steps up, the
//--- shipped "Auto"), 1=Pattern (4x — one step up), 2..8 = fixed TFs.
//--- The two DYNAMIC entries are the Factor card's BASIS names, and W1/MN1
//--- close the ladder the overlay is most often asked for (a D1/H4 candle on
//--- an intraday chart). The MODE is the engine's state (HTFCandles.mqh) —
//--- these two functions only translate between an option INDEX and it, so a
//--- reordering here can never rename a rung.
int HTFOptionFromPeriod(const int p)
{
   if(g_HTFTfMode == HTF_TF_STRUCTURE) return 0;
   if(g_HTFTfMode == HTF_TF_PATTERN)   return 1;
   int vals[7]={240,60,30,15,1440,10080,43200};
   for(int i=0;i<7;i++) if(vals[i]==p) return i+2;
   // Manual TF outside the cycle list → snap display to the closest option
   int best=2; double bestD=1e18;
   for(int i=0;i<7;i++)
   {
      double d=MathAbs(MathLog((double)p/(double)vals[i]));
      if(d<bestD) { bestD=d; best=i+2; }
   }
   return best;
}
int HTFPeriodFromOption(const int idx)
{
   int vals[7]={240,60,30,15,1440,10080,43200};
   int i=idx-2;
   if(i<0) i=0; if(i>6) i=6;
   return vals[i];
}

//--- mini strip (item 13) target: the held committed box its LOCK/✕ buttons
//--- act on. Set by BkHoldFire, validated on every use.
#endif // BIOTAK_PANELS_PALB_MQH
