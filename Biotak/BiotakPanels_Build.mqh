// BiotakPanels_Build.mqh - BiotakPanels split 2026-09-29: exact lines 5984-7363 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_BUILD_MQH
#define BIOTAK_PANELS_BUILD_MQH

//+------------------------------------------------------------------+
//| One ROW of a settings card. `row` is a DISPLAY row (spec entry).  |
//+------------------------------------------------------------------+
void PnlCreateRow(const int item,const int row,const int px,const int py)
{
   int kind; string label,unit,opts; int minV,maxV; double step;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   int ry  = py + PNL_HEAD_H + PnlRowLine(item,row)*PNL_ROW_H;
   int acc = PnlCardAccent(item);
   color a1 = PnlAccentA1(acc);
   // WIDE: full-width elements span the whole card; half-column rows only
   // ever see their own column origin (the caller passes the shifted px).
   int cardW = PnlCardW(item);
   bool wide = PnlIsWide(item);

    // ── SECTION BAND — itself a 42px row, so the hit-test maths is untouched
    if(kind == PNL_K_SEC)
    {
       // P-UI-26: out-of-range display rows surface here as empty bands
       // (PnlRowDef defaults kind=SEC, label="") — never paint a blank
       // band with a "0" pill during dynamic rebuilds.
       if(label == "" && PnlSecCount(item,row) <= 0) return;
       PnlSetBitmap(PnlName(item,row,"BAND"), px, ry, cardW, PNL_ROW_H,
                    wide ? "::Files\\Icons\\pnl_secbandW.bmp" : "::Files\\Icons\\pnl_secband.bmp", Z_PANEL_BAND);
       ObjectSetString(0,PnlName(item,row,"BAND"),OBJPROP_TOOLTIP,"Collapse / expand this section");
      PnlSetBitmap(PnlName(item,row,"BDOT"), px+PNL_PAD_X-PNL_SECDOT_PAD, ry+18-PNL_SECDOT_PAD,
                   PNL_SECDOT_VIS+2*PNL_SECDOT_PAD, PNL_SECDOT_VIS+2*PNL_SECDOT_PAD,
                   PnlAccentRes(item,"pnl_secdot"), Z_PANEL_CHIP);
      PnlSetLabel(PnlName(item,row,"SL"), px+PNL_PAD_X+14, ry+14, label, PNL_CLR_MUTED, PNL_PT_SEC);
      ObjectSetString(0,PnlName(item,row,"SL"),OBJPROP_FONT,BioChromeFont());
      // colour strip (preview .cstrip) — the NEXT row is the group's colour set
      // P-UI-30: the hairline starts 10px after the caption's REAL advance
      // (preview `.row.sec .sr{margin-left:10px}`) — the old 6px/char guess
      // started it INSIDE the label ("GEOMETR", "SUB-CARDS' line).
      int hx0 = px+PNL_PAD_X+14+PnlTextW(label,PNL_PT_SEC)+PNL_ROW_GAP;
      if(PnlRowExt(item,row) == "strip" && PnlRowKind(item,row+1) == PNL_K_CSET)
      {
         int n = PnlRowMembers(item,row+1);
         for(int s=0;s<n;s++)
         {
            int sr = PnlMemberRow(item,row+1,s);
            int sx = px+PNL_PAD_X+14+PnlTextW(label,PNL_PT_SEC)+12 + s*(15+3);
            color sec= PnlCsetCellColor(PnlColorKindSet(item,sr));
            PnlSetRect(PnlName(item,row,"SECS"+IntegerToString(s)),
                       sx, ry+13, 15, 15, sec);
            ObjectSetInteger(0,PnlName(item,row,"SECS"+IntegerToString(s)),
                             OBJPROP_BORDER_COLOR,PnlSwatchBorder(sec,PNL_CLR_CARD));
         }
         hx0 = px+PNL_PAD_X+14+PnlTextW(label,PNL_PT_SEC)+12 + n*(15+3) + 8;
      }
       int cw = PNL_SEC_CNT_W;
       int hx1 = px + cardW - PNL_PAD_X - cw - 12 - 16;
       PnlSetRect(PnlName(item,row,"SHR"), hx0, ry+21, MathMax(0,hx1-hx0), 1, PNL_CLR_LINE);
       PnlSetBitmap(PnlName(item,row,"BCNT"), px+cardW-PNL_PAD_X-cw-PNL_CHIP_PAD-16, ry+11,
                    cw+2*PNL_CHIP_PAD, 20, "::Files\\Icons\\pnl_cntchip.bmp", Z_PANEL_CHIP);
       string cnt = IntegerToString(PnlSecCount(item,row));
       // preview `.row.sec .cnt` is a padded box with the number centred in it;
       // the chip bitmap's own centre is (canvas left + cw/2 + PNL_CHIP_PAD),
       // which is what the letter is centred on now (P-UI-32, was a 5px/char
       // guess right-anchored 8px in from the chevron).
       PnlSetLabel(PnlName(item,row,"BCNL"),
                   px+cardW-PNL_PAD_X-cw/2-16+PnlTextW(cnt,PNL_PT_SEC)/2,
                   ry+16, cnt, PNL_CLR_MUTED, PNL_PT_SEC);
      ObjectSetString(0,PnlName(item,row,"BCNL"),OBJPROP_FONT,BioChromeFont());
      ObjectSetInteger(0,PnlName(item,row,"BCNL"),OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      // collapse chevron (preview .acc .cv): down = open, right = collapsed
      int bb = PnlBandIndex(item,row);
      bool bcol = PnlBandCollapsed(item,bb);
       PnlSetBitmap(PnlName(item,row,"CV"), px+cardW-PNL_PAD_X-12, ry+16, 10, 10,
                    bcol ? PnlAccentRes(item,"pnl_chevr") : PnlAccentRes(item,"pnl_chev"), Z_PANEL_INK);
      ObjectSetString(0,PnlName(item,row,"CV"),OBJPROP_TOOLTIP,
                      bcol ? "Expand section" : "Collapse section");
      return;
   }

   // ── COLOUR SET — N colours in ONE 42px row (preview .cset): tap a cell to
   //    open the palette for THAT colour. Saves 3 rows on HTF / Base Box.
   if(kind == PNL_K_CSET)
   {
      int n = PnlRowMembers(item,row);
      int total = n*PNL_CSET_W + (n-1)*PNL_CSET_GAP;
      int x0 = px + (PNL_WEL - total)/2;
      for(int i=0;i<n;i++)
      {
         int sr = PnlMemberRow(item,row,i);
         string cl,cu,co; int ck,cmn,cmx; double cst;
         PnlSetDef(item,sr,ck,cl,cmn,cmx,cst,cu,co);
         int kk = PnlColorKindSet(item,sr);
         color cc = PnlCsetCellColor(kk);
         int cx = x0 + i*(PNL_CSET_W+PNL_CSET_GAP);
         if(g_PalOpen && g_PalKind == kk)   // the palette's current target
            PnlSetRect(PnlName(item,row,"CSK"+IntegerToString(i)),
                       cx-2, ry+15, PNL_CSET_W+4, PNL_CSET_H+4, a1);
          PnlSetRect(PnlName(item,row,"CS"+IntegerToString(i)),
                     cx, ry+17, PNL_CSET_W, PNL_CSET_H, cc);
          // P-UI-69: a cell holding the card's own colour is a hole, not a
          // swatch - the border is the legibility floor, the CSK ring above it
          // stays the selection mark.
          ObjectSetInteger(0,PnlName(item,row,"CS"+IntegerToString(i)),
                           OBJPROP_BORDER_COLOR,PnlSwatchBorder(cc,PNL_CLR_CARD));
          ObjectSetString(0,PnlName(item,row,"CS"+IntegerToString(i)),
                          OBJPROP_TOOLTIP, (cc==PNL_CLR_AUTO_CELL)
                            ? PnlCsetKey(cl)+" · Auto (follows the candle) — click to override"
                            : "Edit "+PnlCsetKey(cl)+" color");
          // RICH-MT4: glass frame over the flat cell (transparent middle).
          PnlSetBitmap(PnlName(item,row,"CSG"+IntegerToString(i)),
                       cx, ry+17, PNL_CSET_W, PNL_CSET_H,
                       "::Files\\Icons\\pnl_glass38.bmp", Z_PANEL_MARK);   // glass sheen
         PnlSetLabel(PnlName(item,row,"CSL"+IntegerToString(i)),
                     cx+PNL_CSET_W/2, ry+6, PnlCsetKey(cl), PNL_CLR_MUTED, PNL_PT_CSET);
         ObjectSetString(0,PnlName(item,row,"CSL"+IntegerToString(i)),OBJPROP_FONT,BioChromeFont());
         ObjectSetInteger(0,PnlName(item,row,"CSL"+IntegerToString(i)),OBJPROP_ANCHOR,ANCHOR_UPPER);
      }
      return;
   }

   // ── DUAL — two switches in one 42px row (preview .dual)
   if(kind == PNL_K_DUAL)
   {
      int n = PnlRowMembers(item,row);
      string extra = PnlRowExt(item,row);          // "ALL" adds the synthetic cell
      int cells = PnlDualCells(item,row);
      // right-align the cell group: [switch 34][gap 6][caption] [gap 14] ...
      int cx = px + PNL_WEL - PNL_PAD_X - PnlDualTotalW(item,row);
      for(int j=0;j<cells;j++)
      {
         string txt = "", cl,cu,co; int ck,cmn,cmx; double cst;
         bool on = false;
         if(j < n)
         {
            PnlSetDef(item,PnlMemberRow(item,row,j),ck,cl,cmn,cmx,cst,cu,co);
            txt = PnlShortCap(cl);
            on  = (PnlCurrentSet(item,PnlMemberRow(item,row,j)) > 0.5);
         }
         else
         {
            txt = extra;
            // P-UI-66: the ALL cell is the GROUP's switch (see PnlAllCellSpan)
            on  = PnlAllCellOn(item,row);
         }
         cx = px + PNL_WEL - PNL_PAD_X - PnlDualTotalW(item,row) + PnlDualCellX(item,row,j);
         PnlPaintSwitch(item,row,PnlName(item,row,"SW"+IntegerToString(j)), cx, ry+11, on, true);
         ObjectSetString(0,PnlName(item,row,"SW"+IntegerToString(j)),OBJPROP_TOOLTIP,"Flip "+txt);
         PnlSetLabel(PnlName(item,row,"DL"+IntegerToString(j)),
                     cx+PNL_DUAL_SW_W+8, ry+16, txt, PNL_CLR_MUTED, PNL_PT_CAP);
         ObjectSetString(0,PnlName(item,row,"DL"+IntegerToString(j)),OBJPROP_FONT,BioChromeFont());
      }
      PnlPaintChip(item,row,px+PNL_PAD_X,ry+PNL_CHIP_Y,false);
      // left label joins the member shorts ("L1 · L2"), like the preview.
      // P-LBL-01: the middle dot is code 183 set at runtime, never a literal.
      // When the join cannot fit before the right-aligned cells, it drops —
      // the cells themselves keep full captions, so nothing is lost (the band
      // above already names the group).
      string dsep = " . ";
      StringSetCharacter(dsep, 1, 183);
      string dj = "";
      for(int dq=0;dq<n;dq++)
      {
         string dcl,dcu,dco; int dck,dcmn,dcmx; double dcst;
         PnlSetDef(item,PnlMemberRow(item,row,dq),dck,dcl,dcmn,dcmx,dcst,dcu,dco);
         if(dq > 0) dj += dsep;
         dj += PnlShortCap(dcl);
      }
      if(extra != "") dj += dsep + extra;
      int djX = PnlLabelX(item,row,px);
      int djAvail = px+PNL_WEL-PNL_PAD_X-PnlDualTotalW(item,row)-PNL_ROW_GAP-djX;
      if(PnlTextW(dj,PNL_PT_LBL) > djAvail) dj = "";   // P-UI-30: real advance
      PnlPaintLabel(item,row,djX,ry+14,dj);
      return;
    }

    // ── SWITCH — icon chip + label (+ keycap) + 40x22 pill, rail when ON
   if(kind == PNL_K_SW)
   {
      bool on = (PnlCurrent(item,row) > 0.5);
      PnlPaintActive(item,row,px,ry,on);
      PnlPaintChip(item,row,px+PNL_PAD_X,ry+PNL_CHIP_Y,on);
      PnlPaintKey(item,row,px+PNL_PAD_X+PNL_CHIP_VIS+8,ry+12);
      // P-UI-30: the caption owns everything left of the pill, minus .row gap
      PnlPaintLabel(item,row,PnlLabelX(item,row,px),ry+14,label,PNL_PT_LBL,
                    px+PNL_SW_X-PnlLabelX(item,row,px)-PNL_ROW_GAP);
       PnlPaintSwitch(item,row,PnlName(item,row,"SW"),px+PNL_SW_X,ry+PNL_SW_Y,on,false);
       ObjectSetString(0,PnlName(item,row,"SW"),OBJPROP_TOOLTIP,label+": click to flip");
       return;
   }

   // ── COLOUR ROW — label above, then preview + 8 swatches + "+" (all 280px)
   if(kind == PNL_K_COL)
   {
      color cc = PnlRowColor(item,row);
      int kk = PnlColorKind(item,row);
      // P-UI-68's rule, here for the row's own PREVIEW: an unset colour is a STATE, and
      // MT4 paints clrNONE ink-black — so AUTO wears the glass face the cset cells wear.
      color ccVis = (cc == clrNONE) ? PNL_CLR_AUTO_CELL : cc;
       PnlSetBitmap(PnlName(item,row,"GL"), px+PNL_PAD_X-1, ry+PNL_CAP_Y,
                    PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS, PnlGlyphRes(item,PnlRowIcon(item,row),false), Z_PANEL_GLYPH);
       // P-UI-30: caption above the swatch strip — clipped to the content edge
       PnlSetLabel(PnlName(item,row,"L"), px+PNL_PAD_X+PNL_GLYPH_VIS+7, ry+PNL_CAP_Y,
                   PnlFit(label,PNL_PT_LBL_SM,PNL_WEL-2*PNL_PAD_X-PNL_GLYPH_VIS-7),
                   PNL_CLR_LABEL, PNL_PT_LBL_SM);
       ObjectSetString(0,PnlName(item,row,"L"),OBJPROP_FONT,BioChromeFont());
      int sy = ry + PNL_QSW_Y;

       PnlSetButton(PnlName(item,row,"CB"), px+PNL_PAD_X, sy, PNL_QSW_PREV, 22, "", ccVis,
                    (g_PalOpen && g_PalKind==kk) ? a1 : PnlSwatchBorder(ccVis,PNL_CLR_CARD), true);
       // RICH-MT4: glass frame over the flat preview block — transparent
       // middle (the colour shows through), baked top-light + bottom-shade.
       // Non-selectable, above the button: clicks still reach CB (footer pattern).
       PnlSetBitmap(PnlName(item,row,"GLS"), px+PNL_PAD_X, sy, PNL_QSW_PREV, 22,
                    "::Files\\Icons\\pnl_glass46.bmp", Z_PANEL_MARK);   // glass sheen
       ObjectSetString(0,PnlName(item,row,"CB"),OBJPROP_TOOLTIP,
                       label + ((cc==clrNONE) ? " — AUTO (derived) · open the picker"
                                              : " — open the color picker"));
       int qx = px+PNL_PAD_X+PNL_QSW_PREV+PNL_QSW_GAP;
       for(int qi=0; qi<PNL_QSW_N; qi++)
       {
          color qc = QuickPalColor(qi);
          PnlSetButton(PnlName(item,row,"Q"+IntegerToString(qi)),
                       qx+qi*(PNL_QSW_W+PNL_QSW_GAP), sy, PNL_QSW_W, 22, "", qc,
                       (qc==cc) ? a1 : PnlSwatchBorder(qc,PNL_CLR_CARD), true);
          PnlSetBitmap(PnlName(item,row,"GLS"+IntegerToString(qi)),
                       qx+qi*(PNL_QSW_W+PNL_QSW_GAP), sy, PNL_QSW_W, 22,
                       "::Files\\Icons\\pnl_glass22.bmp", Z_PANEL_MARK);   // glass sheen
         ObjectSetString(0,PnlName(item,row,"Q"+IntegerToString(qi)),
                         OBJPROP_TOOLTIP, "Apply this color");
      }
      int axx = qx + PNL_QSW_N*(PNL_QSW_W+PNL_QSW_GAP);
       PnlSetBitmap(PnlName(item,row,"QA"), axx-PNL_CHIP_PAD, sy-PNL_CHIP_PAD, 26, 26,
                    PnlAccentRes(item,"pnl_add"), Z_PANEL_CHIP);
       ObjectSetString(0,PnlName(item,row,"QA"),OBJPROP_TOOLTIP,"Open the full color picker");
      PnlSetBitmap(PnlName(item,row,"QAG"), axx+4, sy+4, PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS,
                   PnlAccentRes(item,"gl_plus"), Z_PANEL_GLYPH);
      return;
   }

   // ── NAV — label left, 118px pill right (preview `.nav` width is fixed)
   if(kind == PNL_K_NAV)
   {
      PnlPaintChip(item,row,px+PNL_PAD_X,ry+PNL_CHIP_Y,false);
      string sub = PnlRowExt(item,row);
       int nw = 118;
       int nx = px + PNL_WEL - PNL_PAD_X - nw;
      // P-UI-30: caption clipped to the 118px pill's left edge
      PnlPaintLabel(item,row,PnlLabelX(item,row,px),ry+14,label,PNL_PT_LBL,
                    nx-PnlLabelX(item,row,px)-PNL_ROW_GAP);
       // RICH-MT4: the pill FACE is a baked gradient skin (preview .nav);
       // the button stays underneath purely as the click target (footer
       // pattern) and is pushed under the skin.
       PnlSetButton(PnlName(item,row,"NAV"), nx, ry+PNL_CTL_Y-1, nw, 26, "",
                    PNL_CLR_CARD, PNL_CLR_CARD, true);
       ObjectSetInteger(0,PnlName(item,row,"NAV"),OBJPROP_ZORDER,Z_PANEL_BASE);
       PnlSetBitmap(PnlName(item,row,"NAVB"), nx, ry+PNL_CTL_Y-1, nw, 26,
                    "::Files\\Icons\\pnl_nav.bmp", Z_PANEL_SKIN);
      // P-UI-30: the pill caption keeps clear of the pill's own chevron
      PnlSetLabel(PnlName(item,row,"NAVL"), nx+10, ry+PNL_CTL_Y+4,
                  PnlFit(sub,PNL_PT_NAV,nw-10-22-PNL_ROW_GAP),
                  PNL_CLR_VALUE, PNL_PT_NAV);
      ObjectSetString(0,PnlName(item,row,"NAVL"),OBJPROP_FONT,BioChromeFont());
      bool isBack = (PnlRowIcon(item,row) == "back");
      PnlSetBitmap(PnlName(item,row,"NAVC"), nx+nw-20, ry+PNL_CTL_Y+4,
                   PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS,
                   PnlGlyphRes(item, isBack ? "back" : "nav", true), Z_PANEL_INK);
      ObjectSetString(0,PnlName(item,row,"NAV"),OBJPROP_TOOLTIP,"Open " + sub);
      return;
   }

   // ── TEXT FIELD (OBJ_EDIT) — MT4's one real text control
   if(kind == PNL_K_TXT)
   {
      string en = PnlName(item,row,"ED");
      string cur = "";
      if(item==12 && g_BkMiniBox!="" && BaseKnotFind(g_BkMiniBox)>=0)
         cur = BaseKnotGetText(BaseKnotPrefix(g_BkMiniBox));
      if(ObjectFind(0,en)<0) ObjectCreate(0,en,OBJ_EDIT,0,0,0);
      ObjectSetInteger(0,en,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,en,OBJPROP_XDISTANCE,px+PNL_PAD_X);
      ObjectSetInteger(0,en,OBJPROP_YDISTANCE,ry+18);   // P-UI-131d: 5px of air under the
                                                       // caption, was 1px
      ObjectSetInteger(0,en,OBJPROP_XSIZE,PNL_WEL-2*PNL_PAD_X);
      ObjectSetInteger(0,en,OBJPROP_YSIZE,22);
      ObjectSetString(0,en,OBJPROP_TEXT,cur);
      ObjectSetString(0,en,OBJPROP_FONT,BioChromeFont(false));
      ObjectSetInteger(0,en,OBJPROP_FONTSIZE,PnlPt(PNL_PT_CTL));   // P-UI-30
      ObjectSetInteger(0,en,OBJPROP_COLOR,PNL_CLR_TITLE);
      ObjectSetInteger(0,en,OBJPROP_BGCOLOR,PNL_CLR_FIELD);
       ObjectSetInteger(0,en,OBJPROP_BORDER_COLOR,PNL_CLR_FIELD_BD);
      ObjectSetInteger(0,en,OBJPROP_ALIGN,ALIGN_LEFT);
      ObjectSetInteger(0,en,OBJPROP_ZORDER,Z_PANEL_EDIT);
      ObjectSetInteger(0,en,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,en,OBJPROP_HIDDEN,true);
      bool noBox = (g_BkMiniBox=="" || BaseKnotFind(g_BkMiniBox)<0);
      ObjectSetInteger(0,en,OBJPROP_READONLY,noBox);
      ObjectSetString(0,en,OBJPROP_TOOLTIP,
                      noBox ? "Hold a box on the chart first — text needs a target"
                            : "Type the box text — ENTER applies (empty clears)");
      PnlSetBitmap(PnlName(item,row,"GL"), px+PNL_PAD_X-1, ry+2,
                   PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS, PnlGlyphRes(item,PnlRowIcon(item,row),false), Z_PANEL_GLYPH);
      PnlSetLabel(PnlName(item,row,"L"), px+PNL_PAD_X+PNL_GLYPH_VIS+7, ry+2,
                  PnlFit(label,PNL_PT_LBL_SM,PNL_WEL-2*PNL_PAD_X-PNL_GLYPH_VIS-7),
                  PNL_CLR_LABEL, PNL_PT_LBL_SM);
      ObjectSetString(0,PnlName(item,row,"L"),OBJPROP_FONT,BioChromeFont());
      return;
   }

   // ── SEGMENTS: underline TABS (with icons) / dropdown (4+ opts) / pills
   if(kind == 2)
   {
       string arr[];
       int cnt = PnlSplit(opts, arr, 12);
       // P-UI-26: an option-less kind=2 row paints nothing (not a blank
       // 104px control) — a misconfigured new row fails visibly at worst.
       if(cnt <= 0) return;
       if(IsTabRow(item,row))
      {
         // preview .tabs — content-sized tabs, a 2px accent underline on the
         // active one. The tab FACE is a flat button (MT4 buttons have no
         // radius) so the icon + caption ride on top at a higher Z.
         string ic = PnlRowExt(item,row);
         string iarr[];
         int nic = (ic=="") ? 0 : PnlSplit(ic, iarr, 8);
          int tx = px + 12;
          if(wide)   // WIDE: centre the strip across both columns
          {
             int tot = 0;
             for(int ti=0;ti<cnt;ti++) tot += 12 + PnlTextW(arr[ti],PNL_PT_CTL) + ((ti<nic) ? 20 : 0) + 4;
             tot -= 4;
             tx = px + (cardW - tot)/2;
          }
         int idx = ClampInt((int)MathRound(PnlCurrent(item,row)),0,cnt-1);
         for(int i=0;i<cnt;i++)
         {
            int tw = 12 + PnlTextW(arr[i],PNL_PT_CTL) + ((i<nic) ? 20 : 0);   // P-UI-30
            // P-UI-131d: the seam is 4 (the micro step the pills use), not 2 — a
            // 2px gap reads as one glued control, exactly what the user reported.
             PnlSetButton(PnlName(item,row,"C"+IntegerToString(i)), tx, ry+PNL_CTL_Y,
                          tw, PNL_CTL_H, "", PNL_CLR_CARD, PNL_CLR_CARD, true);
             ObjectSetString(0,PnlName(item,row,"C"+IntegerToString(i)),OBJPROP_TOOLTIP,arr[i]);
            if(i<nic)
               PnlSetBitmap(PnlName(item,row,"CI"+IntegerToString(i)), tx+5, ry+PNL_CTL_Y+4,
                            PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS,
                            PnlGlyphRes(item,iarr[i], i==idx), Z_PANEL_GLYPH);
            PnlSetLabel(PnlName(item,row,"CT"+IntegerToString(i)),
                        tx+12+((i<nic) ? 20 : 0), ry+PNL_CTL_Y+7, arr[i],
                        (i==idx) ? PNL_CLR_TITLE : PNL_CLR_SEG_TX, PNL_PT_CTL);
            ObjectSetString(0,PnlName(item,row,"CT"+IntegerToString(i)),OBJPROP_FONT,
                            (i==idx) ? "Arial Bold" : "Arial");
            if(i==idx)
            {
               PnlSetRect(PnlName(item,row,"TU"), tx+7, ry+PNL_CTL_Y+PNL_CTL_H-1,
                          tw-14, 2, a1);
               ObjectSetInteger(0,PnlName(item,row,"TU"),OBJPROP_ZORDER,Z_PANEL_MARK);   // tab underline
            }
            tx += tw + 4;
         }
      }
      else if(cnt >= 4)   // dropdown select (icon + value + chevron)
      {
         // Width = icon (7+15) + text (6px/char, Arial Bold 8) + 8px gap +
         // the baked 10px chevron + 8px right pad. It used to be 26+6*len,
         // which put the chevron 11px INSIDE the caption: every dropdown with
         // a value longer than one character drew its arrow on top of its own
         // text (BASIS "Control" read "Contro⌄"). The preview's .dd is
         // content-fitted (padding 10/9, gap 8, 7px chevron ≈ 50 + textW).
         int dw = 50 + PnlTextW(PnlDdOptText(item,row),PNL_PT_CTL);   // P-UI-30
         if(dw < 72) dw = 72;
         int dx = px + PNL_WEL - PNL_PAD_X - dw;
         int dy = ry + PNL_CTL_Y - 1;
          PnlSetButton(PnlName(item,row,"DD"), dx, dy, dw, 26, "",
                       PNL_CLR_FIELD, PNL_CLR_FIELD_BD, true);
         PnlSetBitmap(PnlName(item,row,"DDI"), dx+7, dy+7, PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS,
                      PnlGlyphRes(item,PnlRowIcon(item,row),true), Z_PANEL_INK);
         PnlSetLabel(PnlName(item,row,"DDT"), dx+24, dy+8, PnlDdOptText(item,row),
                     PNL_CLR_TITLE, PNL_PT_CTL);
         ObjectSetString(0,PnlName(item,row,"DDT"),OBJPROP_FONT,BioChromeFont());
         PnlSetBitmap(PnlName(item,row,"DDC"), dx+dw-13, dy+11, 10, 10,
                      PnlAccentRes(item,"pnl_chev"), Z_PANEL_GLYPH);
         ObjectSetString(0,PnlName(item,row,"DD"),OBJPROP_TOOLTIP,label);
         PnlPaintChip(item,row,px+PNL_PAD_X,ry+PNL_CHIP_Y,false);
         PnlPaintLabel(item,row,PnlLabelX(item,row,px),ry+14,label,PNL_PT_LBL,
                       dx-PnlLabelX(item,row,px)-PNL_ROW_GAP);
      }
      else                // segmented pills (2-3 options)
      {
         int idx = ClampInt((int)MathRound(PnlCurrent(item,row)),0,cnt-1);
         // content-sized, right-aligned, 4px gaps (preview .segs gap 3)
         int tot = 0;
         for(int i=0;i<cnt;i++) tot += 16 + PnlTextW(arr[i],PNL_PT_CTL);   // P-UI-30
         tot += (cnt-1)*4;
         // P-UI-131d: sx0 IS the control's left edge — and therefore the caption's
         // ceiling. This branch used to hand PnlPaintLabel the loop's own cursor
         // (sx2 AFTER the loop = the pills' RIGHT end), so a caption longer than the
         // gap was free to run straight into the first pill: the user's «زون استایل
         // چسبیده به Filled», measured off their screenshot at a 2px gap. Every other
         // kind (switch · slider · dropdown · dual) already passed the control's left
         // edge; this was the one row family that did not.
         int sx0 = px + PNL_WEL - PNL_PAD_X - tot;
         int sx2 = sx0;
         for(int j=0;j<cnt;j++)
         {
            int w = 16 + PnlTextW(arr[j],PNL_PT_CTL);   // P-UI-30
             PnlSetButton(PnlName(item,row,"C"+IntegerToString(j)), sx2, ry+PNL_CTL_Y+1, w, 24,
                          arr[j],
                          (j==idx) ? a1 : PNL_CLR_SEG_OFF,
                          (j==idx) ? PnlAccentA2(acc) : PNL_CLR_SEG_BD, true);
             ObjectSetString(0,PnlName(item,row,"C"+IntegerToString(j)),OBJPROP_TOOLTIP,arr[j]);
            ObjectSetInteger(0,PnlName(item,row,"C"+IntegerToString(j)),OBJPROP_COLOR,
                             (j==idx) ? PnlAccentInk(acc) : PNL_CLR_SEG_TX);
            ObjectSetInteger(0,PnlName(item,row,"C"+IntegerToString(j)),OBJPROP_FONTSIZE,PnlPt(PNL_PT_CTL));   // P-UI-30
            sx2 += w + 4;
         }
         PnlPaintChip(item,row,px+PNL_PAD_X,ry+PNL_CHIP_Y,false);
         int labW = sx0 - PnlLabelX(item,row,px) - PNL_ROW_GAP;
         // a caption the control left no room for is not painted at all: PnlFit is
         // SKIPPED when maxW <= 0, which is the other way this caption lands on top
         // of its own pills.
         if(labW > PNL_PT_LBL)
            PnlPaintLabel(item,row,PnlLabelX(item,row,px),ry+14,label,PNL_PT_LBL,labW);
      }
      return;
   }

   // ── SLIDER — label + value chip on line 1, track, then 9 ticks
   {
      int trackX = px + PNL_TRACK_X;
      int trackW = PNL_TRACK_W;
      int trackY = ry + PNL_TRK_Y;
      double val = PnlCurrent(item,row);

      // P-UI-30: slider rows put label + chip on the TOP line (preview .sltop),
      // the track below — the chip used to sit centred in the 42px row, so its
      // 26px canvas (and the knob at 0%) ate the track's first 24px.
      PnlPaintChip(item,row,px+PNL_PAD_X,ry+PNL_CHIP_Y_SL,false);
      PnlPaintKey(item,row,px+PNL_PAD_X+PNL_CHIP_VIS+8,ry+3);
      // accent value chip, right-aligned on the content edge (preview .val.chip)
      int vx = px + PNL_WEL - PNL_PAD_X - PNL_VCHIP_W;
      PnlPaintLabel(item,row,PnlLabelX(item,row,px),ry+6,label,PNL_PT_LBL,
                    vx-PnlLabelX(item,row,px)-PNL_ROW_GAP);
      PnlSetBitmap(PnlName(item,row,"VC"), vx-PNL_VCHIP_PAD, ry+PNL_VCHIP_Y-PNL_VCHIP_PAD,
                   PNL_VCHIP_W+2*PNL_VCHIP_PAD, PNL_VCHIP_H+2*PNL_VCHIP_PAD,
                   PnlAccentRes(item,"pnl_vchip"), Z_PANEL_CHIP);
      // preview `.val.chip` is `min-width:46px;text-align:center`: the run is
      // CENTRED on the 46px body (P-UI-32). It was right-anchored 8px in from
      // the edge, i.e. ~12px right of centre on a real chart.
      string vt = PnlFormat(item,row,val);
      PnlSetLabel(PnlName(item,row,"V"),
                  vx+PNL_VCHIP_W/2+PnlTextW(vt,PNL_PT_VAL)/2, ry+6,
                  vt, PnlAccentA1(acc), PNL_PT_VAL);
      ObjectSetString(0,PnlName(item,row,"V"),OBJPROP_FONT,BioChromeFont());
      ObjectSetInteger(0,PnlName(item,row,"V"),OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);

       PnlSetRect(PnlName(item,row,"T"),  trackX, trackY-1, trackW, PNL_TRK_H+2, PNL_CLR_TRACK_BD);
       ObjectSetString(0,PnlName(item,row,"T"),OBJPROP_TOOLTIP,"Drag to set "+label);
      PnlSetRect(PnlName(item,row,"TG"), trackX+1, trackY, trackW-2, PNL_TRK_H, PNL_CLR_TRACK);
      PnlSetRect(PnlName(item,row,"TF"), trackX+1, trackY, trackW-2, PNL_TRK_H, a1);

       int knobX = PnlSliderKnobX(item,row,val,minV,maxV);
       ObjectSetInteger(0,PnlName(item,row,"TF"),OBJPROP_XSIZE,
                        MathMax(0,knobX+PNL_KNOB_W/2-(trackX+1)));
       // RICH-MT4: baked gloss over the flat track+fill rects — top-light +
       // bottom-shade faux-gradient with a transparent middle, so the LIVE
       // fill colour shows through. Static geometry (one file, all sliders),
       // below the knob, above the rects. Footer-skin pattern (P-UI-02: purge!).
       PnlSetBitmap(PnlName(item,row,"TGLOSS"), trackX+1, trackY, trackW-2, PNL_TRK_H,
                    "::Files\\Icons\\pnl_trackgloss.bmp", Z_PANEL_GLOSS);
      PnlSetBitmap(PnlName(item,row,"KB"), knobX, trackY+PNL_TRK_H/2-PNL_KNOB_W/2,
                   PNL_KNOB_W, PNL_KNOB_W, "::Files\\Icons\\pnl_knob.bmp", Z_PANEL_KNOB);
      // 9 rail ticks (preview .ticks i) — a "where am I in the range" cue
      for(int t=0;t<PNL_TICK_N;t++)
      {
         int txx = trackX + (int)MathRound((double)t*(trackW-1)/(PNL_TICK_N-1));
         PnlSetRect(PnlName(item,row,"TIC"+IntegerToString(t)), txx, ry+PNL_TICK_Y, 1, 2,
                    C'52,58,70');
      }
   }
}
//+------------------------------------------------------------------+
//| Active-state of one segmented option (single-select: i == value). |
//+------------------------------------------------------------------+
bool PnlSegOn(const int item,const int row,const int i,const double val)
{
   return (i==(int)MathRound(val));
}

//+------------------------------------------------------------------+
//| Footer button — preview .ft .btn.                                  |
//| MT4 buttons are square and cannot gradient, so the FACE is a baked  |
//| skin (pnl_btn_ghost / pnl_btn_prim_<accent>, radius 8 + the        |
//| primary's accent glow). The OBJ_BUTTON stays the click target —    |
//| dispatch is by NAME — but is pushed UNDER the skin and filled with |
//| the card's footer colour so its square cannot show through the     |
//| rounded corners. Icon + caption ride on top as their own objects.  |
//+------------------------------------------------------------------+
// P-UI-130 (2026-09-25) — A FOOTER PILL IS AS WIDE AS ITS OWN CAPTION.
// User report: «دکمه ریست کار نیمکنه». The press path was proven working (four
// `[UI] panel press acted (rst)` lines in the live ledger), so what the user was
// pressing was a pill whose caption read **"Res.."** — the fixed 72px button
// reserved 32px for its icon inset and left 32 for the text, which fits "Done"
// and clips "Reset". B-07 forbids exactly this: a face sizes itself from
// `PnlTextW(txt, pt) + 2*pad`, never from a number that happens to fit one string.
// `PNL_BTN_W` is now a FLOOR (the shipped look is preserved) and the caption's own
// advance decides the rest. ONE owner: the paint, the hit rect (read back from the
// button, P-UI-79) and the Done pill's right-aligned x all ask this.
int PnlFootBtnW(const string label)
{
   return MathMax(PNL_BTN_W, 32 + PnlTextW(label,PNL_PT_FOOT) + PNL_BTN_PAD);
}

void PnlFooterBtn(const int item,const string tag,const int bx,const int fy,
                  const string label,const bool primary,const string ico)
{
   int acc = PnlCardAccent(item);
   int bw  = PnlFootBtnW(label);
   string nm = PnlHead(item,tag);
   PnlSetButton(nm, bx, fy+10, bw, PNL_BTN_H, "",
                PNL_CLR_FOOTBG, PNL_CLR_FOOTBG, true);
   ObjectSetInteger(0,nm,OBJPROP_ZORDER,Z_PANEL_BASE);
   ObjectSetString(0,nm,OBJPROP_TOOLTIP,label);
   PnlSetBitmap(nm+"bg", bx-PNL_BTN_PAD, fy+10-PNL_BTN_PAD,
                bw+2*PNL_BTN_PAD, PNL_BTN_H+2*PNL_BTN_PAD,
                primary ? PnlAccentRes(item,"pnl_btn_prim")
                        : "::Files\\Icons\\pnl_btn_ghost.bmp", Z_PANEL_SKIN);
   PnlSetBitmap(nm+"ic", bx+12, fy+16, PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS,
                primary ? PnlGlyphInkRes(item,ico)
                        : PnlGlyphRes(item,ico,false), Z_PANEL_INK);
   PnlSetLabel(nm+"lb", bx+32, fy+17,
               PnlFit(label,PNL_PT_FOOT,bw-32-PNL_BTN_PAD),   // P-UI-30
               primary ? PnlAccentInk(acc) : PNL_CLR_MUTED, PNL_PT_FOOT);
   ObjectSetString(0,nm+"lb",OBJPROP_FONT,BioChromeFont());
}

// ══════════════════════════════════════════════════════════════════════════
// R-KEYCAP (2026-09-14) — THE HEADER .key CAP IS A REAL SWITCH, AND IT WEARS
// ITS OWN STATE.
//
// «این دکمه چرا کار نمیکنه رنگ ها عوض نمیشه» + a screenshot with the card's
// header chip circled. That chip is `PnlKeycapAt`'s `.key` cap - a bitmap plus
// a label - and it was a HINT and nothing else: no hit test, no handler. The
// header it sits in is the card's DRAG HANDLE, so a press on it did not merely
// do nothing, it started a move gesture and walked the card out from under the
// cursor (P-UI-70's shape: a control that cannot be REACHED is worse than a
// missing one, and a button that only drags is worse than both).
//
// The chip now does the job it advertises: it is the card's OWN master switch -
// the same value its hotkey and the ring item write (`PnlKeyMasterSet` names
// the SETTING, never a display row: bands collapse and renumber those) -
// applied through `PnlApplySet` and repainted through `PnlSyncOpenCard`, the
// very calls the row's own press and the hotkey/ring path reach, so chip, row
// and chart cannot disagree about the value. AND it reads its state back: the
// letter wears the card's accent while the master is ON and
// `PNL_CLR_KEYCAP_OFF` while it is OFF, so "did it work?" is answered on the
// control itself, not only on the chart - which is the other half of the
// report («رنگ ها عوض نمیشه»).
//
// The cap lives on BOTH delivery channels: the press chain claims it before the
// body grab (P-UI-70's position rule) and `PnlClickFallback` re-enters that same
// chain for the click a bitmap skin produces (P-UI-74), so no channel can lose
// it. Its geometry is READ BACK from the drawn cap rather than recomputed, so
// the hit box follows a dragged card for free and cannot drift from the paint
// (P-UI-79) - four reads, and only on an actual press.
// ══════════════════════════════════════════════════════════════════════════
//--- the SETTING whose switch IS the card's master, in the SETTING address
//--- space (`PnlSetDef` row index) - NOT a display row: bands collapse and
//--- renumber those, which is exactly how a master would start pointing at
//--- another row.
int PnlKeyMasterSet(const int item)
{
   // The setting whose switch is exactly the state the card's own hotkey
   // toggles:
   //   card 0  (T) -> 3 SHOW       == the T hotkey, g_triggerLevelsEnabled
   //   card 7  (L) -> 1 SHOW       == the L hotkey, g_linesVisible
   if(item == 0) return 3;
   if(item == 7) return 1;
   return -1;   // a .key with no master stays a hint: nothing to press
}

bool PnlKeyOn(const int item)
{
   int ms = PnlKeyMasterSet(item);
   return (ms >= 0) && (PnlCurrentSet(item,ms) > 0.5);
}

color PnlKeycapInk(const int item)
{
   if(PnlKeyMasterSet(item) < 0) return PNL_CLR_KEYCAP_OFF;
   return PnlKeyOn(item) ? PnlAccentA1(PnlCardAccent(item)) : PNL_CLR_KEYCAP_OFF;
}

string PnlKeycapTip(const int item)
{
   string k = PnlCardKey(item);
   if(k == "" || PnlKeyMasterSet(item) < 0) return "";
   return k + " = " + PnlTitleText(item) + ": " + (PnlKeyOn(item) ? "ON" : "OFF") +
          "\nClick: toggle";
}

//--- the create pass: the cap bitmap AND its letter, in the state's own ink
void PnlKeycapDraw(const int item,const int x,const int y)
{
   string k = PnlCardKey(item);
   PnlKeycapAt(PnlHead(item,"keyc"), PnlHead(item,"keyl"), x, y, k,
               PnlKeycapInk(item), Z_PANEL_SKIN);
   string tip = PnlKeycapTip(item);
   if(tip == "") return;
   ObjectSetString(0,PnlHead(item,"keyc"),OBJPROP_TOOLTIP,tip);
   ObjectSetString(0,PnlHead(item,"keyl"),OBJPROP_TOOLTIP,tip);
}

//--- the state a writer OUTSIDE the panel changed (T/L hotkey, ring item) -
//--- change-guarded, so the per-sync cost is one read and one string compare.
void PnlKeycapSync(const int item)
{
   if(PnlKeyMasterSet(item) < 0) return;   // a hint-only cap has no state
   string lbl = PnlHead(item,"keyl");
   if(ObjectFind(0,lbl) < 0) return;        // the card painted no cap
   color want = PnlKeycapInk(item);
   if((int)ObjectGetInteger(0,lbl,OBJPROP_COLOR) != (int)want)
      ObjectSetInteger(0,lbl,OBJPROP_COLOR,want);
   string tip = PnlKeycapTip(item);
   if(ObjectGetString(0,lbl,OBJPROP_TOOLTIP) != tip)
   {
      ObjectSetString(0,lbl,OBJPROP_TOOLTIP,tip);
      ObjectSetString(0,PnlHead(item,"keyc"),OBJPROP_TOOLTIP,tip);
   }
}

bool PnlKeycapHit(const int mx,const int my,int &item)
{
   item = g_PnlOpen;
   if(item < 0 || item == 13) return false;
   if(PnlKeyMasterSet(item) < 0) return false;
   string nm = PnlHead(item,"keyc");
   if(ObjectFind(0,nm) < 0) return false;   // that card carries no .key cap
   int x = (int)ObjectGetInteger(0,nm,OBJPROP_XDISTANCE);
   int y = (int)ObjectGetInteger(0,nm,OBJPROP_YDISTANCE);
   int w = (int)ObjectGetInteger(0,nm,OBJPROP_XSIZE);
   int h = (int)ObjectGetInteger(0,nm,OBJPROP_YSIZE);
   return (mx >= x && mx <= x+w && my >= y && my <= y+h);
}

int PnlKeycapAct(const int item)
{
   int ms = PnlKeyMasterSet(item);
   if(ms < 0) return REFRESH_NONE;
   double v = PnlKeyOn(item) ? 0.0 : 1.0;
   // ONE owner: the SAME call the row's own switch reaches (the press chain
   // translates its display row through `PnlSetRow` and lands on exactly this).
   int flags = PnlApplySet(item,ms,v);
   // ... and the SAME repaint the hotkey/ring path gets: the owner of "the open
   // card follows a value it does not own" repaints every row of this card
   // (and, through the R-KEYCAP hook, the cap's own state).
   PnlSyncOpenCard();
   return flags;
}

//+------------------------------------------------------------------+
//| Create panel for one item                                         |
//+------------------------------------------------------------------+
void PnlCreate(const int item)
{
   if(item == 13)   // BASE BOX MINI = compact TV-style strip (R-BKSTRIP).
   {                // BkMiniStripCreate only clamps BkHoldFire's
      BkMiniStripCreate();   // box-relative anchor on-screen.
      return;
   }
   int rowsCount=PnlRowsCount(item);
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(cw<=0) cw=1920;
   if(ch<=0) ch=1080;
   // WIDE: tall cards pair rows into two columns — height follows pair-lines
   int pairN=PnlPairRows(item);
   int cardW=PnlCardW(item);
   bool wide=PnlIsWide(item);
   int ph=PNL_HEAD_H+pairN*PNL_ROW_H+PNL_FOOT_H;

   int px, py;
   PnlComputePosition(item, ph, px, py);
   g_PnlX[item]=px;
   g_PnlY[item]=py;

    // ── Card body. OBJ_BITMAP_LABEL XSIZE/YSIZE are read-only, so a BMP always
    //    renders at its native size — which is why a NARROW card (never taller
    //    than PNL_CARD_ROWS_MAX) can keep its one baked skin, and why a WIDE one
    //    cannot: `pnl_cardW{n}` stops at n = PNL_WIDE_ROWS_MAX, and card 2 needs
    //    13 pair-lines while BASE BOX needs 19. Clamping the count to the tallest
    //    skin that exists is what the user saw: 42 px of card 2 and 294 px (seven
    //    lines) of card 12 had NO body, so those rows drew straight on the chart —
    //    the colour strip "outside the panel", dead to clicks.
    //
    //    P-UI-71b: the body is COMPOSED instead of looked up, on the 42 px row
    //    grid: one header cap + one band per pair-line + one footer cap, sliced
    //    from a baked skin by `tools/slice-card-skins.py` (so the radius, the
    //    border, the shadow and the hairline are still the generator's pixels).
    //    Three small pieces now cover EVERY height, and the `.fade` wash is its
    //    own overlay, so no `W{n}f` skin needs baking either.
    if(!wide)
    {
      // P-UI-131: the floor is 1 — the generator bakes every count from 1 now, so a
      // short card (the Step card's TH mode is ONE row, the Hover Chip card two)
      // wears the skin that matches it instead of a taller one.
      int cardRows = MathMax(1, MathMin(PNL_CARD_ROWS_MAX, rowsCount));
      string cardRes = "::Files\\Icons\\pnl_card" + IntegerToString(cardRows) + ".bmp";
      PnlSetBitmap(PnlHead(item,"card"), px-PNL_MARGIN, py-PNL_MARGIN,
                  cardW+2*PNL_MARGIN, ph+2*PNL_MARGIN, cardRes, Z_PANEL_CARD);
      // ICON-DIET 2026-09-27: the `.fade` wash is an OVERLAY here, exactly as on
      // the wide body below — it used to be baked in, which cost ten extra skins
      // (4.71 MB) that differed only in these 26 rows. One extra object, on the
      // five PnlCardFade cards only, and only while one of them is open.
      if(PnlCardFade(item))
         PnlSetBitmap(PnlHead(item,"cardf"),
                      px-PNL_MARGIN, py+PNL_HEAD_H+cardRows*PNL_ROW_H-PNL_FADE_H,
                      cardW+2*PNL_MARGIN, PNL_FADE_H,
                      "::Files\\Icons\\pnl_cardfade.bmp", Z_PANEL_CARD);
   }
    else
    {
       // the header cap carries the top radius and the gradient's head
       PnlSetBitmap(PnlHead(item,"card"), px-PNL_MARGIN, py-PNL_MARGIN,
                    cardW+2*PNL_MARGIN, PNL_CARD_TOP_H,
                    "::Files\\Icons\\pnl_cardWtop.bmp", Z_PANEL_CARD);
       // one band per pair-line, on the same grid the panel draws its own
       // separators on — so a repeated tile's seam lands under a separator
       for(int li=0; li<pairN; li++)
          PnlSetBitmap(PnlHead(item,"cardm"+IntegerToString(li)),
                       px-PNL_MARGIN, py+PNL_HEAD_H+li*PNL_ROW_H,
                       cardW+2*PNL_MARGIN, PNL_ROW_H,
                       "::Files\\Icons\\pnl_cardWmid.bmp", Z_PANEL_CARD);
       // the footer cap carries the bottom radius, the footer and the shadow
       PnlSetBitmap(PnlHead(item,"cardb"),
                    px-PNL_MARGIN, py+PNL_HEAD_H+pairN*PNL_ROW_H,
                    cardW+2*PNL_MARGIN, PNL_CARD_BOT_H,
                    "::Files\\Icons\\pnl_cardWbot.bmp", Z_PANEL_CARD);
       // `.fade` — the 26 px wash hugging the footer, an overlay of its own
       if(PnlCardFade(item))
          PnlSetBitmap(PnlHead(item,"cardf"),
                       px-PNL_MARGIN, py+PNL_HEAD_H+pairN*PNL_ROW_H-PNL_FADE_H,
                       cardW+2*PNL_MARGIN, PNL_FADE_H,
                       "::Files\\Icons\\pnl_cardWfade.bmp", Z_PANEL_CARD);
    }

    // ── Header — preview .hd: a 30px accent .mark chip, the title, the
    //    uppercase subtitle, an optional .key cap, the .ver number badge and a
    //    26px ghost .x close, all sitting on the .hd::after accent hairline.
    //    R-PANELUI2 (2026-09-11). The card's own 3px accent top bar
    //    (.card::before) is blitted from pnl_topbar_<accent>.bmp.
    int hacc = PnlCardAccent(item);
    color ha1 = PnlAccentA1(hacc);

     PnlSetBitmap(PnlHead(item,"topbar"), px, py,
                  cardW, 3+2*PNL_CHIP_PAD, PnlWideAccentRes(item,"pnl_topbar",wide), Z_PANEL_TOPBAR);
     PnlSetBitmap(PnlHead(item,"hair"), px, py+PNL_HEAD_H-1-PNL_CHIP_PAD,
                  cardW, 1+2*PNL_CHIP_PAD,
                  PnlWideAccentRes(item,"pnl_hair",wide), Z_PANEL_HAIR);

    // .mark — 30px accent chip; its glyph is the 13px ink set centred inside
    PnlSetBitmap(PnlHead(item,"mark"), px+PNL_PAD_X-PNL_MARK_PAD, py+PNL_MARK_Y-PNL_MARK_PAD,
                 PNL_MARK_VIS+2*PNL_MARK_PAD, PNL_MARK_VIS+2*PNL_MARK_PAD,
                 PnlAccentRes(item,"pnl_mark"), Z_PANEL_SKIN);
    string mi = PnlMarkIcon(item);
    if(mi != "")
       PnlSetBitmap(PnlHead(item,"markg"),
                    px+PNL_PAD_X+(PNL_MARK_VIS-PNL_GLYPH_CANVAS)/2,
                    py+PNL_MARK_Y+(PNL_MARK_VIS-PNL_GLYPH_CANVAS)/2,
                    PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS, PnlGlyphInkRes(item,mi), Z_PANEL_INK);

    // .htxt — title over subtitle, 10px right of the mark (preview .hd gap)
    int htx = px+PNL_PAD_X+PNL_MARK_VIS+10;
    string head=PnlHead(item,"head");
    // .key + .ver + .x column — needed HERE (not only below) because the
    // title's own room ends one 10px .hd gap left of it (P-UI-30).
    string ck2 = PnlCardKey(item);
    string vtxt2 = IntegerToString(item);
    int vw2 = 10 + PnlTextW(vtxt2,PNL_PT_VER);
    int hx2 = px+cardW-PNL_PAD_X-PNL_XBTN_VIS-6;
    int chipL2 = hx2-vw2;
    if(ck2 != "")
       chipL2 -= 10 + PNL_KEYCAP_VIS + 2*PNL_KEYCAP_PAD + PNL_CHIP_PAD;
    // 9pt = 12px: the preview's .ttl is 12.5px, and 12pt (16px) made the title
    // read as a headline over its own card. P-UI-131d: the .htxt block is
    // title 12..24 · subtitle 35..43 — 11px of air in the MIDDLE (it was 3px,
    // the user's «از وسط چسبیده» on the header) and 12px above and below it,
    // which is also the mark's own 13..43.
    // P-UI-30: clipped to the .htxt box (the title used to run under .ver).
    PnlSetLabel(head, htx, py+12,
                PnlFit(PnlTitleText(item),PNL_PT_TITLE,chipL2-htx-PNL_ROW_GAP),
                PNL_CLR_TITLE, PNL_PT_TITLE);
    ObjectSetString(0,head,OBJPROP_FONT,BioChromeFont());
    // 6pt, not 7: the preview sets .subttl at 8.5px, and at 7pt (9.33px) the
    // two longest subtitles ("MID ZONES · UNIFIED LINES · STRUCTURE",
    // "COUNTDOWN · ATR BLOCK · TRADE PLAN") run past the .ver badge — the
    // badge's left edge is at x=249 and those two ended at 256/257. MT4's
    // OBJ_LABEL has no letter-spacing to claw the width back, so the size is
    // the only lever. 6pt = 8px puts the worst case at 225.
    //
    // .subttl is not always ONE label. The preview renders a 4px accent dot
    // before EVERY ' · ' segment (amber, jade, amber …), so the run is laid out
    // segment by segment here — each caption its own OBJ_LABEL, each dot its
    // own 8px bitmap.
    //
    // That costs a little width (a dot plus its two 5px gaps vs the plain
    // ' · ' separator) and MT4 cannot measure text, so the run is FITTED
    // against the right edge of the preview's own .htxt box before it is
    // drawn. R-SUBFIT (2026-09-11): that edge is NOT the .ver badge. The
    // preview's .subttl is overflow:hidden inside a flex:1 .htxt, which ends
    // one 10px .hd gap LEFT of .key (when the card has a hotkey) or of .ver.
    // MT4 knows both exactly, so the run stops there — the two hotkey cards
    // (0 "T", 7 "L") clip a whole segment earlier than a keyless card, which
    // is what the preview does too.
    string ck = ck2;    // one owner for the .key/.ver column (built with the title)
    string vtxt = vtxt2;
    int vw = vw2;
     int hx = hx2;
    int chipL = chipL2;                                  // left edge of .ver
    int subLimit = chipL - 10;                           // the .hd flex gap
    ObjectDelete(0, PnlHead(item,"sub"));   // pre-dot single-label charts
    string subarr[];
    int nsub = StringSplit(PnlHeaderSub(item), 183, subarr);   // 183 = '·'
    string segs[];
    ArrayResize(segs, nsub);
    int nseg = 0;
    for(int si=0; si<nsub; si++)
    {
       string sg = StringTrimLeft(StringTrimRight(subarr[si]));
       if(sg != "")
          segs[nseg++] = sg;
    }
    // Whole captions, then a CLIPPED tail — the honest MT4 twin of the preview's
    // overflow:hidden. The preview lays the run out at its natural width and the
    // .htxt box simply CUTS the last caption mid-word (card 0 ends "...LINES
    // LIVE", card 1 "...STRU", card 12 Setup "...R:R + LEGS + TEMPL"). Dropping
    // a caption that misses by a few pixels is NOT what the preview does: it
    // loses the dot too. R-SUBFIT2 (2026-09-11): draw each caption that fits,
    // and for the first one that crosses the box draw the longest PREFIX that
    // stays inside, then stop — exactly like the box, and it keeps the
    // amber/jade dot rhythm the preview has. MT4 cannot cut a glyph, so a whole
    // character prefix is the closest honest twin. The 5px/char figure stays the
    // conservative 6pt-Arial-Bold estimate the tab and section rows use, so the
    // stop is early by a hair, never late — the 10px .hd gap left of .key/.ver
    // is the safety margin. A caption's own width decides the fit, NOT its width
    // plus the 5px gap to the next dot (the preview is cut by the box, not by
    // the next dot).
    int nDrawn = 0, sdx = htx;
    for(int sd=0; sd<nseg; sd++)
    {
       int textX = sdx + 9;                                // 8px dot + its 1px gap
       int txtW  = PnlTextW(segs[sd],PNL_PT_SUB);          // P-UI-30: real advance
       string cap = segs[sd];
       if(textX + txtW > subLimit)                         // crosses the .htxt edge
       {
          cap = PnlFit(cap,PNL_PT_SUB,subLimit-textX);     // whole characters only
          if(cap == "")
             break;                                        // not even one fits
       }
       PnlSetBitmap(PnlHead(item,"subd"+IntegerToString(sd)), sdx-2, py+35,
                    8, 8, (sd%2==0) ? "::Files\\Icons\\pnl_subdot_amber.bmp"
                                    : "::Files\\Icons\\pnl_subdot_jade.bmp", Z_PANEL_CHIP);
       PnlSetLabel(PnlHead(item,"sub"+IntegerToString(sd)), textX, py+35,
                   cap, PNL_CLR_MUTED, PNL_PT_SUB);
       ObjectSetString(0,PnlHead(item,"sub"+IntegerToString(sd)),OBJPROP_FONT,BioChromeFont());
       nDrawn++;
       if(cap != segs[sd])
          break;                                           // that was the clipped tail
       sdx = textX + txtW + 5;                             // next dot sits 5px on
    }
    if(nDrawn == 0)   // not even one segment fits — the plain caption, no dot
    {
       PnlSetLabel(PnlHead(item,"sub"), htx, py+35, PnlHeaderSub(item), PNL_CLR_MUTED, PNL_PT_SUB);
       ObjectSetString(0,PnlHead(item,"sub"),OBJPROP_FONT,BioChromeFont());
    }

    // .key + .ver — the card hotkey and the accent-soft number badge, sitting
    // left of the close button in the preview's own order: .key THEN .ver
    // (preview .hd is a flex row — mark, .htxt, .key, .ver, .x). This used to
    // place .ver first, which read "0 T ×" instead of the preview's "T 0 ×".
    PnlSetButton(PnlHead(item,"ver"), hx-vw, py+20, vw, 16, vtxt,
                 PnlAccentSoft(hacc), PnlAccentBd(hacc), true);
    ObjectSetInteger(0,PnlHead(item,"ver"),OBJPROP_COLOR,ha1);
    ObjectSetInteger(0,PnlHead(item,"ver"),OBJPROP_FONTSIZE,PnlPt(PNL_PT_VER));   // P-UI-30
    hx -= vw+10;
    if(ck != "")
    {
       // same owner as the row keycaps (P-UI-32): the cap AND its centred
       // letter — the header used to place the letter at a hard-coded -9.
       // R-KEYCAP: the same owner now also paints the STATE (the card accent
       // while the master switch is ON) and attaches the live tooltip.
       PnlKeycapDraw(item, hx-PNL_KEYCAP_VIS-PNL_KEYCAP_PAD-PNL_CHIP_PAD,
                     py+19-PNL_KEYCAP_PAD);
    }

    // .x — 26px ghost close. The BUTTON stays the click target (name-based
    // dispatch needs it) but is pushed UNDER the rounded skin, which is what
    // actually shows: MT4 buttons are square, the preview's is radius 8.
     int xbx = px+cardW-PNL_PAD_X-PNL_XBTN_VIS;
     PnlSetButton(PnlHead(item,"close"), xbx, py+15, PNL_XBTN_VIS, PNL_XBTN_VIS, "",
                  C'28,34,44', C'28,34,44', true);   // #1C222C --ghostBg (1 LSB off before)
    ObjectSetInteger(0,PnlHead(item,"close"),OBJPROP_ZORDER,Z_PANEL_BASE);
    ObjectSetString(0,PnlHead(item,"close"),OBJPROP_TOOLTIP,"Close");
    PnlSetBitmap(PnlHead(item,"xbg"), xbx-PNL_XBTN_PAD, py+15-PNL_XBTN_PAD,
                 PNL_XBTN_VIS+2*PNL_XBTN_PAD, PNL_XBTN_VIS+2*PNL_XBTN_PAD,
                 "::Files\\Icons\\pnl_xbtn.bmp", Z_PANEL_SKIN);
    PnlSetBitmap(PnlHead(item,"xgl"), xbx+(PNL_XBTN_VIS-PNL_GLYPH_CANVAS)/2,
                 py+15+(PNL_XBTN_VIS-PNL_GLYPH_CANVAS)/2,
                 PNL_GLYPH_CANVAS, PNL_GLYPH_CANVAS, PnlGlyphRes(item,"x",false), Z_PANEL_INK);

   // ── Rows — WIDE cards paint pairs side by side (right column shifted
   // +312); full-width rows (bands/tabs) span. Separators run once per
   // pair-line, full card width. Narrow cards: line==r, shift==0 — identical.
   for(int r=0;r<rowsCount;r++)
   {
      int line = PnlRowLine(item,r);
      int bx = px + (PnlRowCol(item,r)==1 ? PNL_COL_DX : 0);
      if(line>0 && (r==0 || PnlRowLine(item,r-1)!=line))
      {
         string sep=PnlName(item,r,"RS");
          PnlSetRect(sep, px, py+PNL_HEAD_H+line*PNL_ROW_H, cardW, 1, PNL_CLR_LINE);
         ObjectSetInteger(0,sep,OBJPROP_ZORDER,Z_PANEL_SEP);
      }
      PnlCreateRow(item,r,bx,py);
   }

   // ── Footer: Reset (ghost) · Done (primary) for every panel. Both are baked
   //    rounded skins with the preview's reset/check glyphs. R-PANELUI2.
   int fy=py+PNL_HEAD_H+pairN*PNL_ROW_H;
   PnlFooterBtn(item,"rst",  px+PNL_PAD_X, fy, "Reset", false, "reset");
   PnlFooterBtn(item,"done", px+cardW-PNL_PAD_X-PnlFootBtnW("Done"), fy, "Done", true, "check");
}

//+------------------------------------------------------------------+
//| Destroy all panel objects                                         |
//+------------------------------------------------------------------+
void PnlDestroy(const int item)
{
   string head=g_UI.btnPrefix+"Pnl"+IntegerToString(item)+"_";
   // P-UI-71: ONE PREFIX WIPE instead of an index-bounded hand list.
   //
   // The list had a ceiling (`r < PNL_CARD_ROWS_MAX`) that could fall BELOW
   // what the drawers actually make, and every card that grew past it left its
   // rows on the chart forever:
   //   * card 2 declares 19 display rows, card 12 declares 24 - both ABOVE the
   //     old 16, so rows 16..23 kept their objects;
   //   * a row's OBJECT NAME carries its DISPLAY INDEX (`Pnl2_18_CS0`), and a
   //     section collapse renumbers the rows, so the old family survived under
   //     the OLD index while the live row drew under the NEW one - the chart
   //     then carried TWO copies of the same row. That is the report: the CARD
   //     COLORS strip sitting outside the card, movable, and dead to clicks
   //     (`PnlCsetHit` only walks the CURRENT rows, so the stale copy is in
   //     nobody's hit list).
   //
   // The prefix form cannot drift from the drawers: `PnlName` builds every row
   // object as `g_UI.btnPrefix + "Pnl" + item + "_" + ...`, so the wipe and the
   // drawer share ONE spelling (the gate asserts it). Cost is ONE terminal scan
   // per card teardown instead of ~450 ObjectDelete calls.
   ObjectsDeleteAll(0, head, -1, -1);
   // P-PERF-47: AND THAT ONE WIPE IS THE WHOLE TEARDOWN.
   //
   // This function used to follow the wipe with a SECOND full-chart prefix scan
   // (`head+"card"`) plus ~33 hand-listed `ObjectDelete(0, head+...)` probes.
   // Every one of those names is a strict SUBSET of the prefix just wiped —
   // `head+"card"`, `head+"ticon"`, `head+"head"`, `head+"sub"`, `head+"close"`,
   // `head+"topbar"`, ... — because `PnlName()`/`PnlHead()` (BiotakPanels.mqh:2472
   // and :2476) build every object of this family as
   // `g_UI.btnPrefix + "Pnl" + item + "_" + ...`, and `head` is exactly
   // `btnPrefix + "Pnl" + item + "_"`. So the extra scan and the 33 probes could
   // never find anything the wipe had not already removed: they were 33
   // guaranteed misses, and the live MT5 probe prices a miss at ~88 us — the most
   // expensive primitive on the chart, and ~360x the cost of the ObjectSetInteger
   // the same terminal answers in 0.245 us.
   //
   // The window argument is now -1 rather than 0 so this ONE wipe is a strict
   // superset of the hand list it replaces: `ObjectDelete(0,name)` searched every
   // subwindow while `ObjectsDeleteAll(...,0,...)` searched only the main one.
   // Panel objects are main-window by construction, so this changes nothing on a
   // healthy chart — it only removes a way for a stray to survive the teardown.
   //
   // PnlDdClose()/BkDdClose() are still called because they reset STATE
   // (g_PnlDdItem, g_BkDd) as well as removing objects; their own deletes are now
   // misses, and a miss on a handful of names is not worth a branch.
   PnlDdClose();   // open select popover (PDDBG/PDDSH/PDDR*) belongs to no row
   // purge: pre-fix builds created the switch faces as PREFIXLESS globals
   // ("SW","SW0".."SW3") — one object all rows fought over. The only names below
   // that the prefix wipe genuinely cannot reach.
   ObjectDelete(0,"SW");
   for(int swp=0;swp<4;swp++) ObjectDelete(0,"SW"+IntegerToString(swp));
   if(item == 13)   // TV-strip dropdown popover (TBdd + DD row set) — state + objects
   {
      BkDdClose();
   }
}

//--- chart foreground handling moved to BiotakUI.mqh ( definitions live there
//     so ToggleMenuVisibility can call them without forward declarations ).
//     The lock variables and functions are now owned by the UI module.

//+------------------------------------------------------------------+
//| Drag-to-move release — lock the spot in for future opens and     |
//| persist it (defined early so the pointer finalizer can call it). |
//+------------------------------------------------------------------+
void PnlCommitMove(const int item)
{
   g_PnlManualPos[item] = true;
   GlobalVariableSet(GetGVName("PNLP" + IntegerToString(item)),
                     g_PnlX[item] * 10000.0 + g_PnlY[item]);
}

//--- P-UI-75b: the drag's own frame window. File scope (and declared HERE,
//--- above the button-up finalizer that clears `s_PnlMoveMoved`), so the press
//--- chain and the polled shadow gate themselves through ONE window instead of
//--- each carrying its own. See the P-UI-75 block below for why the rate is
//--- adaptive and why the drag owns its frames.
//--- P-UI-127: LIVE again with the gesture — the press chain and `PnlDragStep`
//--- gate themselves through this ONE window (`PnlDragPoll` stays uncalled).
#define PNL_MOVE_COALESCE_MS  16   // the window at a grab (P-UI-75b)
#define PNL_MOVE_FRAME_MIN_MS 16   // floor: never slower than this
#define PNL_MOVE_FRAME_MAX_MS 50   // ceiling: a weak machine may back off here
#define PNL_MOVE_SLACK_MS      8   // headroom a batch needs beyond its own cost
#define PNL_DRAG_THRESHOLD_PX  3   // P-UI-80: menu parity (ORB_DRAG_THRESHOLD)
//--- P-UI-89: a press that landed on a CONTROL's own pixel owes the card a
//--- LONGER proof before it may drag it. P-UI-76 measured the hand that keeps
//--- reporting this ("a hand that moves 1-3 px on every real click"): with the
//--- menu's 3 px dead zone a toggle tap would creep the card by a pixel on every
//--- press, so the bound for those pixels is the project's own click-slop
//--- language (`BK_CLICK_SLOP` 10 px, the box tool's drag-vs-click separator).
#define PNL_DRAG_CTRL_PX      10

static uint s_PnlMoveTick    = 0;      // last applied batch (0 = none yet)
static int  s_PnlMoveFrameMs = PNL_MOVE_COALESCE_MS;
static bool s_PnlMoveMoved   = false;  // the card really moved (the poll may pin)
static int  s_PnlMoveGrabX   = 0;      // P-UI-80: press point, the dead-zone anchor
static int  s_PnlMoveGrabY   = 0;
// P-UI-77: WHO armed this drag. The event sparam bit is one witness of two
// (P-UI-73a) — a drag the poll armed never showed its press on that bit, so
// that bit must not own its release (below). Set on every arm, cleared on
// every finish; meaningful only while g_PnlMoveItem >= 0.
static bool s_PnlMoveByPoll  = false;
// P-UI-89: did this gesture START on a control's own pixel? Then the proof it
// owes the card is `PNL_DRAG_CTRL_PX`, not the menu's 3 px (PnlDragThreshPx) -
// the card is draggable from every pixel of the control's FACE, but a tap on a
// switch must still not nudge the card. Set on every arm, cleared on every
// finish; meaningful only while g_PnlMoveItem >= 0.
static bool s_PnlMoveOnCtrl  = false;
// P-UI-78: the poll's release rumour filter (below) — one up-reading arms,
// the second consecutive one finishes. Reset with every finish, like the rest.
static bool s_PnlPollUpArmed = false;
// P-UI-83: the batch counters the finish line reports (see the P-UI-83 block
// right below). Zero cost when no gesture is live: the poll's own first test
// returns before any of this is touched.
static int  s_PnlMoveFrames = 0;   // batches this gesture actually applied
static int  s_PnlMoveWorst  = 0;   // the worst single batch cost it paid (ms)

// ══════════════════════════════════════════════════════════════════════════
// P-UI-83 (2026-09-14) — the panel's drag died on witnesses the MENU never asks.
// The menu's drag lives on ONE witness (the event bit, `if(!leftDown)`); the panel
// had TWO more enders, both consulting the PHYSICAL probe `UILeftButtonUp()` —
// `PnlDragPoll`'s release rule and `ChartPointerFinalizeOnUps`'s teardown gate — and
// where that probe answers "free" while the button is HELD (P-UI-73) both of them end
// a live drag. Measured: 150 arms, ALL from the event channel (0 by the poll), 55
// finishes at 125-176 ms and 76 at 253-500 ms — NO drag outlived half a second.
// THE WITNESS that separates the P-UI-49b echo from a real release is the event bit's
// own RECENCY: a click landing while a down-reading is still warm belongs to that very
// press, while a release with the cursor held still emits NO move (P-BK-03) and its
// stamp is old by construction. ONE stamp, TWO gates — no non-event witness may end a
// gesture whose event channel is still delivering DOWN readings.
// ══════════════════════════════════════════════════════════════════════════
//--- P-UI-127: this recency witness is what keeps `ChartPointerFinalizeOnUps` from tearing the card MOVE, the SLIDER and the palette MIXER down on the P-UI-49b echo (one stamp, two gates).
#define PNL_DOWN_RECENT_MS 250   // a down-reading this fresh IS a live press
static uint s_PnlDownAt = 0;     // last leftDown=1 mouse-move (0 = never seen)

bool PnlPointerQuiet()
{
   return (s_PnlDownAt == 0 || GetTickCount() - s_PnlDownAt >= PNL_DOWN_RECENT_MS);
}

//--- chart-lock integrity layer ---------------------------------------
// BUG: MT4 emits CHARTEVENT_MOUSE_MOVE only on cursor MOVEMENT. A button-up
// with the cursor held perfectly still produces NO move event, so any drag
// engine's release path (which lives in the move handler) never runs and the
// refcounted chart lock leaks → chart scroll dead "sometimes" (until another
// full gesture or re-attach).
// FIX = two authoritative reconcilers:
//  1) ChartPointerFinalizeOnUps() — OBJECT_CLICK / CLICK fire reliably on
//     every button-up, even motionless ones → finalize ownership there.
//  2) ChartScrollReconcile() — rebuild the chart lock from OWNERSHIP intent
//     (panel open? pointer claimed?) instead of trusting paired calls;
//     called from that finalizer AND from OnTimer as a watchdog so a
//     missed release heals within one timer tick, and a template/terminal
//     reset of CHART_MOUSE_SCROLL is re-forced while we own the chart.
bool ChartLockIntended()
{
   // Base/Knot owns the chart while its draw session is armed (it locks
   // via raw Chart* calls so Lite works too — the watchdog must not fight it).
   // P-UI-53: the custom-price LINE drag owns the view the same way, from its own
   // raw lock in the domain layer (`CustomPriceDragLocked()`, EventHandlers —
   // included before this file, so Full and Lite both resolve it). Without this
   // term the reconcile would see "nobody intends the lock" while a line drag is
   // live and restore the user's scroll props UNDER the gesture — the exact pan
   // the lock exists to prevent.
   if(CustomPriceDragLocked()) return true;
   // P-UI-126: the hover chip's own re-place drag (BiotakMenu, included before this
   // file) takes the lock with the menu's counted pair, so the reconcile reads its
   // OWNER here — one bool read, and the day the gesture was born.
   if(CircTipDragLive()) return true;
   // P-BK-62: the Base/Knot tool's OWN latch — an IDLE body drag or a handle
   // RESIZE, which lock the view from its own module exactly as the draw session
   // does. `BaseKnotSessionActive()` alone was the blind spot: the session is only
   // the DRAW gesture, so this query answered "nobody intends the lock" while the
   // user's hand was on a box, the reconcile handed the view back mid-drag, and
   // the drag's own guard then kept it unlocked for the rest of the gesture. The
   // accessor answers all three gestures at once (two bool reads).
   if(BaseKnotViewOwned()) return true;
   // P-LM-11: the leg meter is the same story — its armed draw session and its
   // edit drag hold the lock from TH3Tool, a list that did not name them read
   // that as a leak and hard-released it under the user's hand every 250 ms
   // (the report: «موقع کشیدن صفحه اسکرول میشه نمیزاره درست کشیده بشه»).
    if(LegMeasureViewOwned()) return true;
    // P-TH3-PB-LOCK (2026-09-22): the base mark's PRESS-DRAG holds the view
    // from TH3Tool's own raw lock, exactly like the leg meter above. Without
    // this term the 250 ms reconcile read that lock as a LEAK and handed the
    // chart back under the hand mid-drag («اسکرول پشتش باید قفل باشه که راحت
    // بتونم بکشم مثل بقیه»). ARMED-but-idle stays FREE on purpose: the
    // two-click mode must scroll between its two clicks (P-TH3-PB-UI).
    if(TH3BaseMarkViewOwned()) return true;
    // P-TH3-PB-DRAG-LOCK (2026-09-22): the BAND's own anchor drag (resizing
    // the committed band by its anchors) holds the view the same way — the
    // press-drag lock above only covers the initial DRAW, not the resize,
    // and the chart was panning under the user's hand during the resize.
    if(TH3BaseBandDragViewOwned()) return true;
    // P-DRAW-19 (2026-09-24) — THE DRAW STRIP'S GRIP CARRY, the blind spot this
    // list just closed. Reported: «هنوز هنگام درگ چارت پشتش قفل نمیشه». The carry
    // takes the view from `DrawStrip.mqh`'s own lock (P-UI-113d: acquire at the
    // press edge, assert on every held step, release at every end) — and this list
    // did not name it, so the 250 ms reconcile read that lock as a LEAK, hard-
    // released it inside the first quarter second of the gesture and handed the
    // scroll back: the chart panned under the hand for the REST of the drag, which
    // is exactly what the user still saw. P-LM-11 / P-BK-62's law, one gesture
    // later: a gesture that takes the view lock names itself here the day it is
    // born. `DrawStrip.mqh` is a Full-only UI module included BEFORE this one, so
    // the accessor is defined by the time this line compiles (and Lite, which owns
    // no strip, does not include this file at all - P-BUILD-01).
    if(DrawStripViewOwned()) return true;
    // P-HR-03 (2026-09-28): the Horizontal Ray's arm + dot carry hold the view
    // from HRayTool (P-DRAW-19: named the day they were born).
    if(HRayViewOwned()) return true;
    // P-TH3-PB-OFF (2026-09-21): TH3BaseViewOwned retired with the stage-5
    // base drag — the base is hand-typed, so no term of it can hold the view.
    return (g_DragOwner != DRAG_NONE) || g_OrbDragging || (g_PnlOpen >= 0);
}

void ChartScrollReconcile()
{
   if(ChartLockIntended())
   {
      // P-UI-90: the props are no longer written here - they have ONE owner
      // (`ChartViewLockAssert`), read-guarded, which is what this branch used to
      // open-code for the scroll prop while the two panel globals restored a
      // value that could have been captured under somebody else's lock.
      ChartViewLockAssert();
      // Orphaned surplus locks (e.g., leaked press-lock + modal panel):
      // clamp count down to the intended number without touching props —
      // the chart stays locked exactly once and restores cleanly later.
      if(g_ChartLockCount > 1) g_ChartLockCount = 1;
      ChartViewLockClampToOne();
   }
   else if(g_ChartLockCount > 0 || ChartViewLockHeld())
   {
      // No owner and no modal panel: any remaining claim is a LEAK.
      // Hard-reset (bypasses the paired decrement) and hand the chart back to
      // the USER's captured pair - the one value that is guaranteed not to be
      // our own `false` (see the P-UI-90 block in GlobalVariables).
      g_ChartLockCount = 0;
      ChartViewLockForceRelease();
   }

}

// P-UI-100 (2026-09-22): THE LAST UI CURSOR, DECLARED HERE FOR ITS READER BELOW.
// Both callers of `ChartPointerFinalizeOnUps` publish the press position in the
// same event, immediately above the call (the mouse-move leg the moving cursor,
// the two click legs the click's own point), and the finalizer's own new question
// — "is this press on a hand-set line?" — is answered from it. The declaration
// used to sit ~2500 lines below, beside the BaseKnot hold that also reads it;
// this is the project's own rule for a value two readers need (GlobalVariables'
// note on `g_s1DragLive`): the FIRST reader in the translation unit declares it,
// so no reader can be compiled out of the answer by include position.
static int g_LastUIX = 0;
static int g_LastUIY = 0;

void ChartPointerFinalizeOnUps()
{
   // Every gesture ends here — OBJECT_CLICK / CHARTEVENT_CLICK fire reliably
   // on button-up, even motionless ones (MT4 emits no MOUSE_MOVE then). The
   // A click can only fire with the button UP — resync the rising-edge
   // detector here. MT4 emits no MOUSE_MOVE when the cursor is held still,
   // so without this the flag stayed true after a motionless click and made
   // every drag engine (and the ←/→ anchor guard) believe a press was live.
   g_MouseWasDown = false;

   // P-UI-126: and the chip's own re-place drag, on the same two rules — its latch is
   // one bool, and it is ended only while the pointer is QUIET, because one of these
   // two click events is delivered on the PRESS itself (P-UI-49b) and would otherwise
   // kill the drag in the event that started it.
   if(PnlPointerQuiet()) CircTipDragFinalize();

   // P-UI-48/P-UI-49b: every button-up is also the end of a custom-price grab, so
   // this is the second of the two gesture-end triggers (the first is the
   // button-up mouse move, which never arrives when the user releases without
   // moving) — but it must DEFER the clear, never write it inline.
   //
   // This finalizer is reached from CHARTEVENT_CLICK and CHARTEVENT_OBJECT_CLICK,
   // and one of those two is delivered on the PRESS that grabs a selectable
   // object (MT4 picks the object up first and lets the indicator see the event
   // of the same press). Clearing the line's selection HERE therefore dropped the
   // terminal's own selection in the very event that started the drag: the drag
   // engaged and died immediately ("the drag state is cut off very quickly"),
   // and the SAME event had just deferred it in the domain's click handler — the
   // two halves of one gesture disagreed. Arming the latch keeps the finalizer's
   // promise (a motionless release emits no mouse move, so its clear is owed to
   // the next button-up move, through the one owner) without ever touching the
   // line while the button is down. Cost: one bool store; a chart with no custom
   // price line still pays only the guarded read of the clear.
   g_customPriceNativeDrag = true;

   // P-UI-100 (2026-09-22): AND THE ONE PRESS THAT CANNOT BE DEFERRED IS DROPPED
   // NOW — everywhere it cannot be a grab of a hand-set line.
   //
   // The deferral above exists for exactly one press: the one that grabs a
   // selectable object, where the write would drop the terminal's own selection
   // out of the drag it just started. Every OTHER press (a panel, a card, the
   // ring, a pan) owns no hand-set line, and MT4 carries the line through that
   // whole gesture if it is still selected (P-UI-45's law — the interference this
   // file already arms the latch for). So the same hit test the claim uses, with
   // the same tolerance, answers which of the two this press is: over a UI surface
   // or away from both lines is not a grab, and the stale selection goes in the
   // press's OWN event, before any drag can carry it.
   //
   // The position is `g_LastUIX`/`g_LastUIY` — the press position both callers of
   // this finalizer publish in the same event, immediately above the call (the
   // mouse-move leg publishes the moving cursor, the two click legs the click's
   // own point). No parameter is added: the signature is the net's identity, and
   // three audits name it.
   {
      bool onHandLine = false;
      if(!UIPointerOverSurface(g_LastUIX, g_LastUIY))
      {
         string cpRow = "";
         onHandLine = CustomPriceGrabAt(g_LastUIX, g_LastUIY) ||
                      Step1HandleUnderCursor(g_LastUIX, g_LastUIY, cpRow);
      }
      if(!onHandLine) HandLinesSelectionGuard();
   }

   // P-UI-73 (2026-09-14) — A TEARDOWN NEEDS A RELEASE TO TEAR DOWN.
   //
   // This finalizer is reached from CHARTEVENT_CLICK *and*
   // CHARTEVENT_OBJECT_CLICK, and P-UI-49b already recorded that one of those
   // two is delivered ON THE PRESS that grabs an object. Everything below is the
   // "the gesture is over" half — releasing the drag claims, committing the
   // panel's new spot, settling the redraw budget — so running it on a press
   // echo kills the gesture that same press just started: the panel's move claim
   // is cleared in the instant it is made, the rest of the press produces no
   // drag at all, and it reads as "the panel can't be dragged" while every other
   // control behaves normally (and only where such an echo can be produced,
   // which is why it feels random).
   //
   // The witness is the CONSERVATIVE physical probe (`UILeftButtonUp`: both MQL4
   // conventions must agree the button is free). `g_MouseWasDown` was already
   // resynced to false just above, so an ignored echo leaves the press edge
   // available: the next MOUSE_MOVE of that same press registers as a fresh
   // press and RE-CLAIMS what the echo would have thrown away.
   //
   // P-UI-83: THE PROBE ALONE IS NOT ENOUGH TO TEAR A GESTURE DOWN. On a
   // terminal whose KEYSTATE probe reads "free" while the button is held, this
   // gate let the P-UI-49b delivery echo (the OBJECT_CLICK of the very press
   // that grabbed the card) end a live drag 125-176 ms into it — the ledger is
   // full of those (`via=finalizer`, today's session). The event bit's RECENCY
   // separates the two cases: an echo lands while the terminal is still
   // delivering down-readings, a release with the cursor held still emits NO
   // move at all (P-BK-03) and is therefore quiet by construction. Both must
   // agree, and if this click was an echo the press edge was already resynced
   // above, so the very next MOUSE_MOVE of that press re-claims the gesture.
   if(!UILeftButtonUp() || !PnlPointerQuiet()) return;

   // P-UI-33: EVERY button-up ends the heavy-pass budget (idempotent). A knob
   // gesture can only live while the button is down, so this ONE net makes a
   // forgotten release path impossible — the last value always lands.
   UIDragBudgetEnd();

    const bool owned = (g_DragOwner != DRAG_NONE) || g_OrbDragging;
    if(!owned && g_ChartLockCount <= 1 && g_PnlDragItem < 0 && g_PalMixDrag == 0 && !s_palMoveArmed)
    {
       ChartScrollReconcile();
       return;
    }
   // Release EVERYTHING the still-held pointer used to own. Long-press
   // bookkeeping, slider drag, and palette mixer — none should outlive a
   // button-up. g_PnlDragItem must be cleared here or the next MOUSE_MOVE
   // (cursor finally moving after a stationary release) will call
   // CircUnlockChart() for the drag's press-lock that was already clamped
   // away by ChartScrollReconcile, underflowing the panel's modal lock.
   // P-UI-78 ledger, last silent path: a release with no travel ends here, not
   // in PnlDragFinish — without this line an arm/arm pair 200 ms apart reads
   // as a double-grab instead of tap, release-click, tap.
   if(g_PnlMoveItem >= 0)
   {
      _LOG_GATE_W Print("[UI] panel drag finished moved=", (s_PnlMoveMoved ? 1 : 0),
                        " byPoll=", (s_PnlMoveByPoll ? 1 : 0),
                        " frames=", s_PnlMoveFrames, " worst=", s_PnlMoveWorst,
                        "ms via=finalizer");
      // P-UI-80 parity, closed on the last path: `s_PnlMoveMoved` IS the dragged
      // latch, so a TAP (press + release under the dead zone) must not pin the
      // spot either — `g_PnlManualPos` + its GV are the manual park, and pinning
      // them on every tap is how a card stops following the menu's auto-anchor.
      // A real drag still commits here, which is the missed-release case this
      // finalizer exists for.
      if(s_PnlMoveMoved) PnlCommitMove(g_PnlMoveItem);   // keep the spot a real drag reached
   }
   s_PnlMoveMoved   = false;   // P-UI-75a: the gesture is over — nothing left to pin
   s_PnlMoveByPoll  = false;   // P-UI-77: the channel flag dies with the gesture
   s_PnlMoveOnCtrl  = false;   // P-UI-89: and so does the control-press proof
   s_PnlPollUpArmed = false;   // P-UI-78: and so does the rumour filter
   //--- a STATIONARY release ends an orb drag here, not in the move handler
   //--- (no move event carries a motionless button-up). A drag that travelled
   //--- still owns its spot: save it exactly like the moving release does, or
   //--- the next reposition restores the stale home and the orb snaps back.
   bool orbLive = g_OrbDragging;
   bool orbDragged = (g_OrbDragging && g_OrbWasDragged);
   g_DragOwner      = DRAG_NONE;
   g_OrbDragging    = false;
    g_LongPressItem  = -1;
    g_PnlDragItem    = -1;
    g_PnlDragRow     = -1;
    g_PnlMoveItem    = -1;
     g_PalMixDrag     = 0;
     if(s_palMoveArmed) PalMoveDisarm();   // spot already parked on the proven move
     //--- mirror the move-path release: the travelled spot becomes home (saved),
     //--- the release click is spent, and the frozen layout may re-derive.
     if(orbDragged) { CircOrbHomeSet(g_UI.menuX, g_UI.menuY); SaveUIStates(); UISuppressNextClick(); }
     if(orbLive) SubRelayoutIfNeeded();
     ChartScrollReconcile();
}

// Commit a pending TEXT edit (TV "Add text" ≈ Ok-on-close): clicking away
// from the OBJ_EDIT loses focus without ENDEDIT in MT4, so flush before any
// other panel/strip action and on close — same pattern as FlushPalHex.
void BkFlushTextEdit()
{
   if(!g_BkTextFocus) return;
   g_BkTextFocus = false;
   if(g_PnlOpen != 12 || g_BkTab != 1) return;
   int er = PnlDispRowOfSet(12, 1);   // TEXT edit lives on the CONTENT section's row, not row 1
   if(er < 0) return;
   string en = PnlName(12, er, "ED");
   if(ObjectFind(0, en) < 0) return;
   string t = ObjectGetString(0, en, OBJPROP_TEXT);
   if(g_BkMiniBox != "" && BaseKnotFind(g_BkMiniBox) >= 0) BaseKnotSetText(g_BkMiniBox, t);
}

//+------------------------------------------------------------------+
//| P-UI-98r: publish the open surfaces' screen rects (margin incl.)  |
//| for chart-anchored readers that cannot see this module. HTFCandles|
//| is included BEFORE this file, so the card-cull reads these shared |
//| globals (the g_UIPanelOpen precedent) instead of calling back.    |
//+------------------------------------------------------------------+
void PnlPublishCover()
{
   if(g_PnlOpen >= 0)
   {
      g_UIPanelRX = g_PnlX[g_PnlOpen] - PNL_MARGIN;
      g_UIPanelRY = g_PnlY[g_PnlOpen] - PNL_MARGIN;
      g_UIPanelRW = PnlPanelW(g_PnlOpen) + 2 * PNL_MARGIN;
      g_UIPanelRH = PnlPanelH(g_PnlOpen) + 2 * PNL_MARGIN;
   }
   else { g_UIPanelRX = -1; g_UIPanelRY = -1; g_UIPanelRW = 0; g_UIPanelRH = 0; }
   if(g_PalOpen)
   {
      g_UIPPalRX = g_PalX; g_UIPPalRY = g_PalY;
      g_UIPPalRW = PalW(); g_UIPPalRH = PalH();
   }
   else { g_UIPPalRX = -1; g_UIPPalRY = -1; g_UIPPalRW = 0; g_UIPPalRH = 0; }
}

#endif // BIOTAK_PANELS_BUILD_MQH
