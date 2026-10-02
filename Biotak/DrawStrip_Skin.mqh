// DrawStrip_Skin.mqh - DrawStrip split 2026-09-29: exact lines 4407-5338 of DrawStrip.mqh, byte-identical, zero renames.
#ifndef DRAW_STRIP_SKIN_MQH
#define DRAW_STRIP_SKIN_MQH


//--- P-DRAW-29 (2026-09-24) — THE PLATE WEARS THE CARDS' OWN SKIN. User order:
//--- «کل ظاهر پنل مثل بقیه بشه». The flat rectangle is retired for a 9-slice of
//--- the panels' own Obsidian-Gold surface (margin 14, radius 10, 1px #2C3444
//--- border, drop shadow, top catchlight — tools/gen-th3-icons.js `ds_*`): the
//--- plate's height is ALWAYS 48+36k (quick row + k bands on the CELL+GAP grid,
//--- DrawStripLayout's own arithmetic), so one top cap (margin + 44) + k mid
//--- bands (36) + one bottom cap (4 + margin) composes every height, and the
//--- middles crop to every width (MT4 crops a smaller XSIZE/YSIZE, never
//--- stretches — each middle is uniform along its crop axis, so the crop is
//--- invisible). The mid-row centre is a plain DSTRIP_CLR_PANEL rect (flat
//--- mid-tone, one level off the baked ramp — invisible). A plate that cannot
//--- be skinned (taller than 24 bands, wider than 660) keeps the legacy rect,
//--- so an unmeasurable layout never draws a half plate. (Metrics live with
//--- the V6 shell metrics above: MQL4 is define-before-use.)
string DrawStripSkinName(const int i)
{
   switch(i)
   {
      case 0: return "PnlDrawS_BGtL";
      case 1: return "PnlDrawS_BGtM";
      case 2: return "PnlDrawS_BGtR";
      case 3: return "PnlDrawS_BGmL";
      case 4: return "PnlDrawS_BGmM";
      case 5: return "PnlDrawS_BGmR";
      case 6: return "PnlDrawS_BGbL";
      case 7: return "PnlDrawS_BGbM";
      case 8: return "PnlDrawS_BGbR";
   }
   return "";
}
//--- P-DRAW-32: the SETTINGS PANEL'S OWN nine pieces. One baker, one skin, two
//--- plates — the family index is the whole difference.
string DrawStripGearSkinName(const int i)
{
   switch(i)
   {
      case 0: return "PnlDrawS_GBtL";
      case 1: return "PnlDrawS_GBtM";
      case 2: return "PnlDrawS_GBtR";
      case 3: return "PnlDrawS_GBmL";
      case 4: return "PnlDrawS_GBmM";
      case 5: return "PnlDrawS_GBmR";
      case 6: return "PnlDrawS_GBbL";
      case 7: return "PnlDrawS_GBbM";
      case 8: return "PnlDrawS_GBbR";
   }
   return "";
}
//--- P-DRAW-48 (2026-09-26) — THE BOARD'S OWN NINE PIECES, and they must be its
//--- own. `DrawStripSkinPiece` answered the STRIP's names for family 2, so the two
//--- plates were ONE set of objects: the strip's plate (height 48, k = 0) deletes
//--- the mid pieces on every paint and the board's plate (k = 10) re-created them
//--- as the NEWEST objects at Z_STRIP_ICON — i.e. over the board's 64 cells, its
//--- RECENT band and its HEX field. Measured on the reported chart: the board's
//--- whole body was ONE colour at 24,750 samples. One plate, one name.
string DrawStripBoardSkinName(const int i)
{
   switch(i)
   {
      case 0: return "PnlDrawS_BBtL";
      case 1: return "PnlDrawS_BBtM";
      case 2: return "PnlDrawS_BBtR";
      case 3: return "PnlDrawS_BBmL";
      case 4: return "PnlDrawS_BBmM";
      case 5: return "PnlDrawS_BBmR";
      case 6: return "PnlDrawS_BBbL";
      case 7: return "PnlDrawS_BBbM";
      case 8: return "PnlDrawS_BBbR";
   }
   return "";
}
//--- P-DRAW-89 (2026-09-29) — THE PLATE'S TRANSPARENCY IS RETIRED. User order:
//--- «این شفافیت پنل به کل حذف کن لازم نیستش». It was not a tint: with
//--- `s_dsPlateTIdx > 0` the underlayer stopped being a PANEL tone and became the
//--- CHART's own background (`DrawStripPlateFill` -> `GetCachedChartBgColor`), and
//--- `StrapBodyTone` returned that same raw colour for every cell. So the whole
//--- surface — track, rows, cells, grips — took one colour off `CHART_COLOR_BACKGROUND`:
//--- cyan on the dark template, magenta-blue on the light one. MEASURED, the panel
//--- census on 2026-09-29 11:29 read `PnlDrawS_GTrack bgcolor=-16924895` =
//--- `0xFEFDBF21` = R33 G191 B253, a value that exists in no palette and in no
//--- painter here — it was the chart's own. The four tabs beside it read 2892317
//--- (the card tone) because they are painted from a constant, not from the tone
//--- chain, which is exactly why only the tone-driven surfaces went wrong.
//---
//--- Why deletion and not a blend: a blend still asks the chart for a colour, and the
//--- chart's background is a USER choice (a template, a preset, a light theme) that
//--- the panel must never depend on. One look, one owner, zero chart reads on this
//--- surface. The `_t30/60/90.bmp` sets go with it — nothing asks for them any more.
int    DrawStripPlateT()      { return 0; }
int    DrawStripPlateTPct()   { return 0; }
void   DrawStripPlateTSet(const int i) { /* retired: the plate has one look */ }
string DrawStripSkinRes(const string base)
{
   return "::Files\\Icons\\" + base + ".bmp";
}
//--- P-PAL-17 (2026-10-02) — FAMILY 2 WEARS ITS OWN NINE. The strip and the
//--- settings panel keep the shipped `ds_*` art (byte-identical to what shipped);
//--- the colour board reads `ds_pb_*`, baked at the modern corner so the box speaks
//--- the same recipe as the cells inside it. A per-family base is the whole change:
//--- nine `DrawStripSkinResFor(fam, …)` calls where nine literals stood.
string DrawStripSkinResFor(const int fam, const string base)
{
   return DrawStripSkinRes((fam == 2) ? ("ds_pb_" + base) : ("ds_" + base));
}
//--- the underlayer behind the skin: the panel tone when the plate is solid, the
//--- chart's own background when it is translucent — which is what keeps P-DRAW-35's
//--- white-chart fringe fix while letting the chart show through the plate.
color DrawStripPlateFill()
{
   //--- P-DRAW-89: the chart's background is NEVER this panel's colour. It used to
   //--- be one of two answers, and on a light template the whole surface went
   //--- chart-coloured. One look, one owner.
   return DSTRIP_CLR_PANEL;
}

//--- P-DRAW-69 — THE 42px CELL IS THE ONLY GRID, AND ONE CELL IS ONE TONE. The
//--- cards bake ONE body with a hairline at every row seam and NO per-row face
//--- (measured on `pnl_card7.bmp`: the body reads the same (24,29,38) at x=20, 100,
//--- 170, 240, 300, and the seam rows 69/70 read #222832 edge to edge). This panel
//--- had TWO grids: the bands split the body into 6, and every row drew its own
//--- face at the ramp's own centre — which lands 1 RGB unit off the band beneath it
//--- (row 98 -> (22,26,35); the band [93,142] -> (22,27,35)), so every row read as
//--- its own plate. The bands now ride the SURFACE's cell grid and the cells are
//--- 42px, so a row's face IS its band and the plate reads as one glass.
#define DSTRIP_BODY_MAX 40      // cells + the head and tail bands (k <= 24)
#define DSTRIP_SEAM_H    2       // the card's own seam is 2 rows of white @ 5.5 %
//--- P-DRAW-70 — THE RAMP IS THE CARD'S, PARAMETERISED BY THE SURFACE'S OWN HEIGHT.
//--- `BioCardTone(t)` IS `cardGrad(t)` in tools/gen-th3-icons.js, and the card bakes
//--- it as `cardGrad(cy / H)` over the WHOLE card: TOP at 0 %, MID at 52 %, BOT at
//--- 100 %. This function handed it `0.52 + 0.48·t` instead — it kept only the ramp's
//--- LOWER half and stretched it over the body, so a plate hit CARD_MID four times
//--- too early and sat 5-10 RGB units under the card at every height. Measured on the
//--- Paint tab (plate 342) against `pnl_card7.bmp` (content 398), same fraction:
//---   old  plate content 119 -> (22,26,35)   card at 119/398 -> (27,33,43)
//---   new  plate content 119 -> (25,31,40)   card at 119/398 -> (25,31,40)
color StrapBodyTone(const int dy, const int bandH, const int plateH)
{
   //--- P-DRAW-89: the tone is a TONE. It was short-circuited to the chart's own
   //--- background whenever the plate was translucent, which is how the tab track
   //--- came out cyan (measured -16924895 = 0xFEFDBF21) on a dark template. A
   //--- still plate falls back to the panel tone; a moving one always reads the ramp.
   if(plateH <= 0) return DSTRIP_CLR_PANEL;
   double t = ((double)dy + bandH * 0.5) / (double)plateH;
   if(t < 0.0) t = 0.0;
   if(t > 1.0) t = 1.0;
   return BioCardTone(t);
}
//--- the tone of the CELL that owns `contentY` — the ONE answer a row, a popover
//--- row, the tab track and the band under them all ask, so two owners can never
//--- disagree by a unit (H-06). Above `gridTop` is the head's own single band.
color StrapCellTone(const int contentY, const int bodyTop, const int gridTop, const int plateH)
{
   if(contentY < gridTop) return StrapBodyTone(bodyTop, gridTop - bodyTop, plateH);
   int cell = contentY - ((contentY - gridTop) % DSTRIP_SKIN_MID);
   return StrapBodyTone(cell, DSTRIP_SKIN_MID, plateH);
}
//--- the seat's ring wears the BORDER colour while it reads against the plate, else
//--- the legibility floor's own outline (catalogue 1: an invisible ring is the
//--- "empty slot"). `BioSwatchBorder` answers the same question with a neutral
//--- outline, which is why the ring cannot reuse it verbatim.
color StrapRingInk(const color c, const color backdrop)
{
   return (BioContrast(c, backdrop) < BIO_SWATCH_MIN_CONTRAST) ? BIO_CLR_MUTED : c;
}
//--- the body's bands: one name per band per family, and band 0 IS the shipped
//--- body object (piece 4), so an older build's plate cannot leave a ghost.
string DrawStripBodyName(const int fam, const int b)
{
   string base = DrawStripSkinPiece(fam, 4);
   return (b == 0) ? base : base + "B" + IntegerToString(b);
}
//--- P-DRAW-69: the seam rides the CELL, so the bands and the rules are one walk and
//--- one owner. Its name carries the plate's own prefix, so `DrawStripIsBg` reads a
//--- tap on it as a tap on the plate (P-DRAW-11) instead of a dead pixel.
string DrawStripSeamName(const int fam, const int b)
{
   return DrawStripBodyName(fam, b) + "S";
}
//--- one cell: its flat tone (the cards have no per-row face) and, from `seamFrom`
//--- down, the card's own 2px hairline at the cell's top edge, edge to edge.
bool DrawStripCellPaint(const int fam, const int b, const int plateTop, const int plateH,
                        const int x, const int y, const int w, const int h,
                        const int seamFrom)
{
   color tone = StrapBodyTone(y - plateTop, h, plateH);
   bool dirty = DrawStripBtnZ(DrawStripBodyName(fam, b), x, y, w, h,
                              tone, tone, tone, "", "", Z_STRIP);
   int cy = y - plateTop;
   if(cy >= seamFrom && seamFrom >= 0)
      dirty |= DrawStripRect(DrawStripSeamName(fam, b), x - 1, y,
                             w + 2, DSTRIP_SEAM_H,
                             DSTRIP_CLR_LINE, Z_STRIP_ICON);
   return dirty;
}
//--- P-DRAW-70: `bodyTop` is where this surface's ramp starts — DSTRIP_BODY_TOP (2,
//--- the card's own first body row) for the two cards, and the baked cap's content
//--- bottom (44) for the strip's 48px quick row, which is a TOOLBAR and keeps the
//--- shipped cap ramp. A card that starts its body at 44 wears the cap's own 44px
//--- CARD_TOP->CARD_MID walk on top of the card's ramp, which is the 5-10 unit hole.
bool DrawStripBodyPaint(const int fam, const int plateTop, const int plateH,
                        const int x, const int y, const int w, const int h,
                        const int gridTop, const int seamFrom)
{
   bool dirty = false;
   int b = 0, y0 = y, yEnd = y + h;
   int headBot = DSTRIP_SKIN_TOPT - DSTRIP_SKIN_M;
   if(gridTop > y0 && gridTop < yEnd)
   {
      dirty |= DrawStripCellPaint(fam, b++, plateTop, plateH, x, y0, w, gridTop - y0, seamFrom);
      y0 = gridTop;
   }
   while(y0 < yEnd && b < DSTRIP_BODY_MAX - 1)
   {
      int y1 = y0 + DSTRIP_SKIN_MID;
      if(y1 > yEnd) y1 = yEnd;
      dirty |= DrawStripCellPaint(fam, b++, plateTop, plateH, x, y0, w, y1 - y0, seamFrom);
      y0 = y1;
   }
   if(y0 < yEnd)   // the tail: the foot and the plate's own air, one band
      dirty |= DrawStripCellPaint(fam, b++, plateTop, plateH, x, y0, w, yEnd - y0, seamFrom);
   for(int t = b; t < DSTRIP_BODY_MAX; t++)
   {
      string nm = DrawStripBodyName(fam, t);
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
      string sn = DrawStripSeamName(fam, t);
      if(ObjectFind(0, sn) >= 0) { ObjectDelete(0, sn); dirty = true; }
   }
   return dirty;
}
bool DrawStripBodyPurge(const int fam)
{
   bool dirty = false;
   for(int b = 0; b < DSTRIP_BODY_MAX; b++)
   {
      string nm = DrawStripBodyName(fam, b);
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
      string sn = DrawStripSeamName(fam, b);
      if(ObjectFind(0, sn) >= 0) { ObjectDelete(0, sn); dirty = true; }
   }
   return dirty;
}

//--- 0 = the strip's plate · 1 = the settings panel's plate (P-DRAW-32).
string DrawStripSkinPiece(const int fam, const int i)
{
   return (fam == 1 ? DrawStripGearSkinName(i)
                    : (fam == 2 ? DrawStripBoardSkinName(i) : DrawStripSkinName(i)));
}
//--- the plate is a FAMILY now (9 skin pieces, or the legacy rect): a tap on
//--- any of them is a tap on the plate (P-DRAW-11's popover rule). P-DRAW-32: the
//--- SETTINGS PANEL's plate and its section bands belong to the same family, so a
//--- tap on the panel's own surface never reads as a tap on the chart.
bool DrawStripIsBg(const string nm)
{
//--- P-DRAW-83: THE PANEL'S OWN PLATE IS THE PANEL'S PLATE. `DrawStripGearBgName()`
   // ("PnlDrawS_GBG", the retired underlayer) matched here by the letter B, while
   // the plate this build really paints — "PnlDrawS_Gbake" / "Gtop" / "Gmid*" /
   // "Gbot" — differs by the case of that one letter and matched NOTHING. With the
   // plate back under its controls (see DrawStripGearPlate) that means the panel's
   // own margins, padding and air are pixels no control owns: a press there fell
   // past every branch of the router and out to the CHART, which is the half of
   // P-DRAW-32's rule ("a tap on the panel's own surface never reads as a tap on the
   // chart") the spelling left open. Case-sensitive, and no control name
   // begins `Gb`: GT/GG/GR/GF/GE/GS/GU/GH and the tab bed keep their own owners.
   //--- P-DRAW-114 (2026-10-01) — AND THE SAME SPELLING WAS WRONG FOR THE WIDE PLATE,
   //--- WHICH IS THE WHOLE BUG ON THE TWO TABS THAT MATTER. The `Gb` term above matches
   //--- `PnlDrawS_Gb*` — the NARROW bake AND the wide body's own `Gbot` (both are
   //--- `PnlDrawS_G` + a lowercase `b`), so those two were never the gap. The gap is
   //--- the other TWO pieces: a tab whose height is off the card set composes its plate
   //--- out of three instead (DrawStripGearPlate: "PnlDrawS_Gtop" 745,
   //--- "PnlDrawS_Gmid<0..11>" 752, "PnlDrawS_Gbot" 758), and `Gt` / `Gm` matched
   //--- nothing at all.
   //--- MEASURED: Style and Row are the only two tabs that take that branch
   //--- (`PLATE tab=1/4 ... branch=wide obj=PnlDrawS_Gtop` in every 2026-10-01 log
   //--- line), so on exactly those two tabs the panel's own body — three opaque
   //--- tiles, the largest click targets it owns — was not its surface: the press
   //--- fell past the `DrawStripIsBg` branch (DrawStrip_Router.mqh:732), past every
   //--- name loop below it, and out to the chart. Paint is unaffected by construction
   //--- (its plate is `Gbake`), which is why the report reads as a Style/Row fault.
   //--- `Gt` / `Gm` are safe to claim for the plate and nothing else: the controls are
   //--- GT (tabs), GG (chips), GR (rows), GF (foot), GE (fields), GS (bands),
   //--- GU (underline), GH (head) and `GTrack` — a different letter, or UPPERCASE.
   return (StringFind(nm, "PnlDrawS_BG") == 0 ||
           StringFind(nm, "PnlDrawS_Gb") == 0 ||   // Gbake (narrow) + Gbot (wide)
           StringFind(nm, "PnlDrawS_Gt") == 0 ||   // P-DRAW-114: the wide plate's top cap
           StringFind(nm, "PnlDrawS_Gm") == 0 ||   // P-DRAW-114: ...its mid tiles
           StringFind(nm, "PnlDrawS_BB") == 0 ||   // P-DRAW-48: the board's own plate
           StringFind(nm, "PnlDrawS_GB") == 0 ||   // the retired nine-slice family
           StringFind(nm, "PnlDrawS_GH") == 0 ||
           StringFind(nm, "PnlDrawS_GS") == 0 ||
           StringFind(nm, "PnlDrawS_GU") == 0);
}
//--- P-DRAW-48: which of those plates is the COLOUR BOARD's own (`BB…`, one letter
//--- apart from the strip's `BG…`). It is the one surface that must not shut the
//--- popover it belongs to — its body is the space between its own cells.
bool DrawStripIsBoardPlate(const string nm)
{
   return (StringFind(nm, "PnlDrawS_BB") == 0);
}
//--- mid bands below the plate's own top zone, from that plate's height
//--- (-1: this height is off the skin's own 48 + 42k grid).
int DrawStripSkinKFor(const int h)
{
   if(h < 48) return -1;
   int k = (h - 48) / DSTRIP_SKIN_MID;
   if(k < 0 || k > DSTRIP_SKIN_MAXK || 48 + k * DSTRIP_SKIN_MID != h) return -1;
   return k;
}
bool DrawStripSkinFitsFor(const int w, const int h)
{
   int k = DrawStripSkinKFor(h);
   return (k >= 0 && w > 0 && w <= DSTRIP_SKIN_MAXW &&
           w + 2 * DSTRIP_SKIN_M - 2 * DSTRIP_SKIN_CAP <= DSTRIP_SKIN_MIDW);
}
//--- P-PAL-17: the CAP the board's own bake needs: margin 14 + its modern 16px
//--- corner, where the strip's nine are margin 14 + 14. ONE owner, and the painter
//--- asks it for all six cap reads (three widths, three x) — a second literal here
//--- is a corner blitted 2px off its own cap (P-DRAW-68's class).
int DrawStripSkinCap(const int fam) { return (fam == 2) ? 30 : DSTRIP_SKIN_CAP; }
//--- P-PAL-17 (2026-10-02) — THE BOARD'S PLATE IS NOT ON THE 42-BAND GRID. The
//--- strip and the settings panel are baked strips whose middles are WHOLE 42px
//--- bands, so their heights must be `48 + k*42` (P-PAL-08's measurement). The
//--- colour board's height is a SUM of bands that are not multiples of 42, and the
//--- snap to the next band was the dead black block under HEX the report shows: up
//--- to 41px of plate carrying nothing. Its nine pieces are CROPPED, not stretched
//--- (P-DRAW-29 — MT4 crops a smaller XSIZE/YSIZE and never stretches), so the board
//--- can take its MEASURED height and its plate ends exactly where HEX ends. The
//--- width law is unchanged: a wider plate would need a wider middle bake.
//--- ONLY family 2 reads this; the strip's and the panel's own grid is untouched.
bool DrawStripSkinFitsForFam(const int fam, const int w, const int h)
{
   if(fam != 2) return DrawStripSkinFitsFor(w, h);
   int cap = DrawStripSkinCap(fam);
   return (h >= DSTRIP_SKIN_TOPT + DSTRIP_SKIN_BOTT && w > 0 && w <= DSTRIP_SKIN_MAXW &&
           w + 2 * DSTRIP_SKIN_M - 2 * cap <= DSTRIP_SKIN_MIDW);
}
int  DrawStripSkinK()     { return DrawStripSkinKFor(s_dsH); }
bool DrawStripSkinFits()  { return DrawStripSkinFitsFor(s_dsW, s_dsH); }
//--- one skin bitmap: created once with the rung's face, guarded after (the
//--- module's write law — every ObjectSet* repaints at the chart's object
//--- count, so a write of a value already there is pure loss).
bool DrawStripSkinBmp(const string nm, const int x, const int y, const int w,
                      const int h, const string res, const int z = Z_STRIP)
{
   bool dirty = false;
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_BITMAP_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_STATE, false);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, z);
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, "");
      dirty = true;
   }
   else
   {
      //--- the z is a write-on-create fact otherwise: a plate that was painted as
      //--- family 0 (Z_STRIP) and is now painted as a CARD must be re-asserted,
      //--- or the card keeps sitting UNDER the strip's own chrome. One compare.
      dirty |= DrawStripSetInt(nm, OBJPROP_ZORDER, z);
   }
   dirty |= DrawStripSetStr2(nm, OBJPROP_BMPFILE, 0, res);
   dirty |= DrawStripSetStr2(nm, OBJPROP_BMPFILE, 1, res);
   dirty |= DrawStripSetInt(nm, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(nm, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(nm, OBJPROP_XSIZE, w);
   dirty |= DrawStripSetInt(nm, OBJPROP_YSIZE, h);
   return dirty;
}
//--- delete one skin family (teardown law: by prefix family, 100%).
//--- P-DRAW-42 (2026-09-25) — AND THE FAMILY'S OWN BG RECT. Reported: a flat dark
//--- rectangle the size of the settings panel left on the chart with nothing on it.
//--- P-DRAW-35 made `PnlDrawS_BG`/`PnlDrawS_GBG` a permanent underlayer, and a purge
//--- that took the 9 tiles but not the underlayer left exactly that rectangle — the
//--- plate is ONE surface, so its one owner takes both, for both families.
bool DrawStripSkinPurgeAt(const int fam)
{
   bool dirty = false;
   for(int i = 0; i < 9; i++)
   {
      string nm = DrawStripSkinPiece(fam, i);
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
   }
   dirty |= DrawStripBodyPurge(fam);   // P-DRAW-67: the body's bands go with it
   if(fam == 1)
   {
      // pnl_card* path: also purge the bot-cap and the extended mid tiles (GBm9..11)
      string bc = DrawStripGearSkinName(0) + "Bot";
      if(ObjectFind(0, bc) >= 0) { ObjectDelete(0, bc); dirty = true; }
      for(int mi = 9; mi < DSTRIP_GEAR_BLK_MAX; mi++)
      {
         string mn = "PnlDrawS_GBm" + IntegerToString(mi);
         if(ObjectFind(0, mn) >= 0) { ObjectDelete(0, mn); dirty = true; }
      }
   }
   string bg = (fam == 1 ? DrawStripGearBgName()
                         : (fam == 2 ? DrawStripBoardBgName() : DrawStripBgName()));
   if(ObjectFind(0, bg) >= 0) { ObjectDelete(0, bg); dirty = true; }
   return dirty;
}
//--- P-DRAW-32: BOTH plates die together — a close (or a hide) owns the whole
//--- surface, and a family left behind is the ghost this project keeps paying for.
bool DrawStripSkinPurge()
{
   bool dirty = DrawStripSkinPurgeAt(0);
   dirty |= DrawStripSkinPurgeAt(1);
   dirty |= DrawStripSkinPurgeAt(2);   // P-DRAW-48: the colour board's own plate
   return dirty;
}
bool DrawStripGearSkinPurge()
{
   return DrawStripSkinPurgeAt(1);
}
//--- P-DRAW-32: ONE 9-slice painter, TWO plates. `fam` picks the family (the strip
//--- or the settings panel); the rect is the caller's, so the panel's plate can no
//--- longer be the strip's plate growing.
//--- P-LOG-10 (2026-10-02): raised when a 9-slice plate (strip fam 0, board fam 2)
//--- is purged by !DrawStripSkinFitsFor while its content survives. DrawStripPaint
//--- answers it at the TOP of the next pass — one purge before ANY painter runs —
//--- because a plate born after its content covers it (creation order is paint
//--- order; ZORDER rules clicks alone; a same-pixel write raises nothing).
bool s_dsSkinPlateDied = false;

bool DrawStripSkinPaintAt(const int fam, const int x, const int y, const int w, const int h,
                          const int gridTop, const int seamFrom, const int bodyTop)
{
   bool dirty = false;
   if(!DrawStripSkinFitsForFam(fam, w, h))
   {
      dirty |= DrawStripSkinPurgeAt(fam);
      s_dsSkinPlateDied = true;   // P-LOG-10: the content outlived its plate — the next paint purges before it paints
      return dirty;
   }
   //--- P-PAL-17: the middle is the MEASURED remainder (k*42 on the other two
   //--- families, h - top - bottom here), so the plate ends where the content does.
   int midH = (fam == 2) ? (h - DSTRIP_SKIN_TOPT - DSTRIP_SKIN_BOTT) : DrawStripSkinKFor(h) * DSTRIP_SKIN_MID;
   int cap = DrawStripSkinCap(fam);
   int sx = x - DSTRIP_SKIN_M, sy = y - DSTRIP_SKIN_M;
   int TW = w + 2 * DSTRIP_SKIN_M;
   int midW = TW - 2 * cap;
   int midY = sy + DSTRIP_SKIN_TOPT;
   int botY = midY + midH;
   color fill = DrawStripPlateFill();   // P-DRAW-43: solid tone, or the chart's own bg
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 0), sx, sy,
                             cap, DSTRIP_SKIN_TOPT,
                             DrawStripSkinResFor(fam, "top_l"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 1), sx + cap, sy,
                             midW, DSTRIP_SKIN_TOPT, DrawStripSkinResFor(fam, "top_m"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 2), sx + TW - cap, sy,
                             cap, DSTRIP_SKIN_TOPT,
                             DrawStripSkinResFor(fam, "top_r"));
   if(midH > 0)
   {
      dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 3), sx, midY,
                                DSTRIP_SKIN_EDGE, midH, DrawStripSkinResFor(fam, "mid_l"));
      // P-DRAW-48: the plate's own body — Z_STRIP, never the cells' layer.
      // P-DRAW-67: and it is the cards' RAMP now, band by band (see StrapBodyTone).
      // P-DRAW-69: on the SURFACE's own 42px cell grid, one flat tone per cell plus
      // P-DRAW-70: from `bodyTop` — the card's ramp covers the cap's own rows too.
      int bodyBot = y + h - (DSTRIP_SKIN_BOTT - DSTRIP_SKIN_M);
      if(bodyBot > y + bodyTop)
         dirty |= DrawStripBodyPaint(fam, y, h, sx + DSTRIP_SKIN_EDGE, y + bodyTop,
                                     TW - 2 * DSTRIP_SKIN_EDGE, bodyBot - bodyTop,
                                     gridTop, seamFrom);
      dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 5), sx + TW - DSTRIP_SKIN_EDGE, midY,
                                DSTRIP_SKIN_EDGE, midH, DrawStripSkinResFor(fam, "mid_r"));
   }
   else
   {
      for(int i = 3; i <= 5; i++)
      {
         // P-UI-34 (2026-09-25): was DrawStripSkinName(i) — always family 0.
         // When fam==1 (gear panel) the mid pieces are family 1 names, so the
         // family-0 names were never deleted and their stale OBJ_BUTTONs stayed
         // on the chart wearing the OS default (white) background.
         string nm = DrawStripSkinPiece(fam, i);
         if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); dirty = true; }
      }
      dirty |= DrawStripBodyPurge(fam);   // P-DRAW-67: a 48px plate has no body
   }
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 6), sx, botY,
                             cap, DSTRIP_SKIN_BOTT,
                             DrawStripSkinResFor(fam, "bot_l"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 7), sx + cap, botY,
                             midW, DSTRIP_SKIN_BOTT, DrawStripSkinResFor(fam, "bot_m"));
   dirty |= DrawStripSkinBmp(DrawStripSkinPiece(fam, 8), sx + TW - cap, botY,
                             cap, DSTRIP_SKIN_BOTT,
                             DrawStripSkinResFor(fam, "bot_r"));
   //--- P-PAL-17b (2026-10-02) — THE PLATE'S OWN NINE, AS THE TERMINATOR HOLDS IT.
   //--- The MEASURED report: the board's content ends where HEX ends (BH=556, the
   //--- flushed witness agrees) and the CARD carries ~75px more below it. The plate
   //--- is nine OBJ_BITMAP_LABELs and the model above says where each one lands — so
   //--- either the model is wrong or the objects are, and only the OBJECTS can say.
   //--- ONE line, once per open, through the flushed channel, naming every piece's
   //--- own x/y/size and the bmp the terminal resolved: XSIZE/YSIZE only CROP, so a
   //--- piece whose canvas is taller than its size shows more rows than the painter
   //--- believes, and nothing on the chart can say so but this read.
   if(fam == 2)
   {
      static bool said = false;
      if(!said)
      {
         said = true;
         string s = "[drawstrip] PLATE fam=2 rect=" + IntegerToString(x) + "," + IntegerToString(y)
                    + "," + IntegerToString(w) + "x" + IntegerToString(h)
                    + " midH=" + IntegerToString(midH) + " botY=" + IntegerToString(botY)
                    + " cap=" + IntegerToString(cap);
         for(int i = 0; i < 9; i++)
         {
            string pn = DrawStripSkinPiece(fam, i);
            s += " | " + pn + "=";
            if(ObjectFind(0, pn) < 0) s += "GONE";
            else s += IntegerToString(ObjectGetInteger(0, pn, OBJPROP_XDISTANCE)) + ","
                    + IntegerToString(ObjectGetInteger(0, pn, OBJPROP_YDISTANCE)) + ","
                    + IntegerToString(ObjectGetInteger(0, pn, OBJPROP_XSIZE)) + "x"
                    + IntegerToString(ObjectGetInteger(0, pn, OBJPROP_YSIZE))
                    + ",z" + IntegerToString(ObjectGetInteger(0, pn, OBJPROP_ZORDER));
         }
         DrawStripDiagEmit(s);
      }
   }
   //--- P-DRAW-35 (2026-09-25): OBJ_BITMAP_LABEL does NOT honour alpha on a white
   //--- chart — every transparent pixel in the skin BMP reads as white.  A solid
   //--- RECTANGLE_LABEL behind the skin (same content rect, no border, Z_STRIP-1)
   //--- fills the rounded-corner gap and the shadow margin so the panel looks
   //--- identical on white and black charts.  This replaces the old "delete bg when
   //--- skin fits" path; the bg rect is now the permanent underlayer.
   //--- P-DRAW-48: fam 2 (the board) has its OWN underlayer; the strip's
   //--- `PnlDrawS_BG` was reused by the first cut and moved the strip's own
   //--- floor under the board — one surface, one name.
   string bg = (fam == 1 ? DrawStripGearBgName()
                         : (fam == 2 ? DrawStripBoardBgName() : DrawStripBgName()));
   if(ObjectFind(0, bg) < 0)
   {
      if(!ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return dirty;
      ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR,       fill);
      ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, bg, OBJPROP_ZORDER,      Z_STRIP_BG);
      dirty = true;
   }
   //--- P-DRAW-122 (2026-10-01): THE UNDERLAYER'S RUNG IS RE-ASSERTED EVERY PAINT.
   //--- This is the one object every OTHER pixel of the strip is drawn over, so a
   //--- stale rung here is the whole surface: after a reattach the skin pieces are
   //--- born again at their own z while this rect keeps an older one, and the plate
   //--- swallows them. Compare-guarded; a still frame writes nothing.
   dirty |= DrawStripSetInt(bg, OBJPROP_ZORDER,      Z_STRIP_BG);
   dirty |= DrawStripSetInt(bg, OBJPROP_BACK,        false);
   dirty |= DrawStripSetInt(bg, OBJPROP_XDISTANCE, x);
   dirty |= DrawStripSetInt(bg, OBJPROP_YDISTANCE, y);
   dirty |= DrawStripSetInt(bg, OBJPROP_XSIZE,     w);
   dirty |= DrawStripSetInt(bg, OBJPROP_YSIZE,     h);
   dirty |= DrawStripSetInt(bg, OBJPROP_COLOR,     fill);
   dirty |= DrawStripSetInt(bg, OBJPROP_BGCOLOR,   fill);
   return dirty;
}
//--- the strip's own plate: the caller's rect is the strip's own content box.
bool DrawStripSkinPaint()
{
   return DrawStripSkinPaintAt(0, s_dsX, s_dsY, s_dsW, s_dsH,
                               DSTRIP_STRIP_GRID_TOP, -1, DSTRIP_STRIP_BODY_TOP);
}
//--- P-DRAW-32: the SETTINGS PANEL's plate, at ITS OWN origin and size.
//--- P-DRAW-35: DrawStripSkinPaintAt(1,...) now owns DrawStripGearBgName() — both the
//--- skin-fits underlayer and the fallback flat rect — so there is no duplication here.
//--- P-DRAW-40 (2026-09-25): the drawing's own pixel box, measured the way P-DRAW-20
//--- measures it (every anchor that projects; the anchors are the contiguous 0..n-1
//--- set). ONE implementation, because a second copy of a measurement is how two
//--- surfaces come to disagree about where the work is (H-06). P-DRAW-73: it sits
//--- ABOVE the board's placer too, which now asks the same question (H-05).
bool DrawStripDrawingBox(const string name, int &x1, int &y1, int &x2, int &y2)
{
   bool have = false;
   for(int i = 0; i < 3; i++)
   {
      int ax = 0, ay = 0;
      if(!DrawAnchorXY(name, i, ax, ay)) break;   // anchors are contiguous 0..n-1
      if(!have) { x1 = ax; x2 = ax; y1 = ay; y2 = ay; have = true; continue; }
      if(ax < x1) x1 = ax;
      if(ax > x2) x2 = ax;
      if(ay < y1) y1 = ay;
      if(ay > y2) y2 = ay;
   }
   return have;
}
//--- P-DRAW-45 (2026-09-25) — THE OVERLAP, IN PIXELS. One owner for both placers: the
//--- panel's eight scored positions and the board's docked spot, so two surfaces can
//--- never answer "do we touch?" two different ways (H-06).
int DrawStripRectOverlap(const int ax, const int ay, const int aw, const int ah,
                         const int bx, const int by, const int bw, const int bh)
{
   int x1 = MathMax(ax, bx), y1 = MathMax(ay, by);
   int x2 = MathMin(ax + aw, bx + bw), y2 = MathMin(ay + ah, by + bh);
   if(x2 <= x1 || y2 <= y1) return 0;
   long w = (long)x2 - (long)x1, h = (long)y2 - (long)y1;
   long a = w * h;
   if(a > 2147483647) return 2147483647;
   return (int)a;
}


//--- P-DRAW-48 — THE OPACITY BAR'S OWN GEOMETRY AND ITS OWN GRAB. The paint and
//--- the hand read ONE answer: the label keeps the RECENT column, the readout its
//--- own seat, and the bar is what is left between them (the cards' track metrics).
int DrawStripHexX() { return s_dsBX + DSTRIP_PAD + DSTRIP_PREC_LW; }
//--- P-DRAW-66: the track starts after the FIELD now (the band is shared), so the
//--- hand's drag begins on the bar and a press on the field can never move it.
int DrawStripOpTrackX() { return DrawStripHexX() + DSTRIP_HEX_W + DSTRIP_PAD; }
int DrawStripOpTrackW()
{
   int w = s_dsBW - DSTRIP_PAD - (DrawStripOpTrackX() - s_dsBX) - DSTRIP_OP_VW;
   return (w > 2 * DSTRIP_KNOB_W) ? w : 2 * DSTRIP_KNOB_W;
}
//--- the value a pointer x means, over the SAME span the knob rides — the exact
//--- inverse of the knob's own position, so what the hand sees is what `NN%` says.
int DrawStripOpValueAt(const int mx)
{
   int span = DrawStripOpTrackW() - DSTRIP_KNOB_W;
   if(span <= 0) return DRAW_OP_MIN;
   double f = (mx - DrawStripOpTrackX()) / (double)span;
   if(f < 0.0) f = 0.0;
   if(f > 1.0) f = 1.0;
   int v = (int)MathRound(f * 100.0);
   if(v < DRAW_OP_MIN) v = DRAW_OP_MIN;
   if(v > 100) v = 100;
   return v;
}
//--- P-DRAW-75 (2026-09-28) — THE PLATE IS A DERIVED HEIGHT, SO IT IS ALSO A
//--- DERIVED RECT. Everything family 1 paints sits inside `s_dsGearW0 x s_dsGearH`,
//--- but a band left by a TALLER layout, or by a path that resized the plate without
//--- re-running the body walk, keeps its own object and its own Y — the reported tower
//--- of empty 42px bands under the panel, with no content owning them. One bounded
//--- sweep on a REAL layout change (never per paint) takes any band or seam whose own
//--- rect the plate no longer contains. `DrawStripBodyPaint` owns the bands this
//--- surface SHOULD have; this owns the ones it must not keep.
bool DrawStripGearTrimOverflow()
{
   bool dirty = false;
   for(int b = 0; b < DSTRIP_BODY_MAX; b++)
   {
      string nm = DrawStripBodyName(1, b);
      if(ObjectFind(0, nm) >= 0)
      {
         int by = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
         int bh = (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE);
         int bw = (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE);
         //--- the band's OWN bottom, not a 42px worst case: the last band is a
         //--- short tail, so `by + 42` killed a band the plate still holds and left
         //--- the ones a TALLER tab had put below the plate standing on the chart.
         if(by < s_dsGEY || by + bh > s_dsGEY + s_dsGearH || bw > s_dsGearW0)
         { ObjectDelete(0, nm); dirty = true; }
      }
      string sn = DrawStripSeamName(1, b);
      if(ObjectFind(0, sn) >= 0)
      {
         int sy = (int)ObjectGetInteger(0, sn, OBJPROP_YDISTANCE);
         if(sy < s_dsGEY || sy > s_dsGEY + s_dsGearH)
         { ObjectDelete(0, sn); dirty = true; }
      }
   }
   return dirty;
}
bool DrawStripGearPlate()
{
   bool dirty = false;
   // P-DRAW-xx: the gear panel wears the CARDS' own pnl_cardW* skin — the same
   // composed body BiotakPanels uses for wide cards (top cap + one mid per pair-line
   // + bot cap), so the panel reads as a card and the strip is the only ds_* surface.
   // Height = DSTRIP_GEAR_HEAD_H + (1+rows)*DSTRIP_GEAR_ROW_H + DSTRIP_GEAR_FOOT_H.
   // Card geometry mirrors BiotakPanels.mqh (included AFTER this file, so names
   // are unavailable here): margin=14 HEAD_H=56 FOOT_H=48 ROW_H=42.
   int gx = s_dsGEX, gy = s_dsGEY, gw = s_dsGearW0, gh = s_dsGearH;
   //--- P-DRAW-83 (2026-09-29) — THE PLATE IS THE BOTTOM OF ITS OWN LADDER, ALWAYS.
   //--- These four writers passed `Z_PANEL_CARD` (1480) while every control on this
   //--- panel is painted by `DrawStripBtn`/`DrawStripFace` — the STRIP's rungs,
   //--- Z_STRIP_ICON 1441 and Z_STRIP_OVER 1442. 1480 > 1441, so the plate's own card
   //--- bake (one opaque bitmap, the whole 340x348 of it) sat ABOVE the tabs, the
   //--- hex fields, the Interior switch and the foot: paint order hid them, and click
   //--- order gave every pixel of the panel to an object no branch of the click
   //--- router owns. The panel answered NOTHING. The cards' own ladder survives that
   //--- arrangement only because `PnlSkinButtonAct` hit-tests their controls back by
   //--- rectangle on the press (P-UI-128); this panel has no such second channel, so
   //--- the plate must not be above its controls at all. Z_STRIP is the rung the
   //--- strip's own plate wears (DrawStripSkinPaintAt, family 0) and the rung
   //--- `DrawStripSkinBmp` defaults to — one value, both plates.
   //--- P-DRAW-78: EXACT card rows. Content = head 56 + T rows + foot 42 + air 6;
   //--- the cards' own plate for that height is `pnl_card{T-1}` (56 + n*42 + 48):
   //--- the foot row plus the 6px air fills the card's 48px footer exactly, and
   //--- every content row lands on a card row. The old air (34) put every height
   //--- 28px off every bake, which is why the composed body never reached the
   //--- plate's bottom edge.
   //--- LITERALS, not PNL_*: BiotakPanels.mqh is included AFTER this file, so its
   //--- constants do not exist here. 104 = 56+48 · 42 = the row · 70 = 14+56 ·
   //--- 62 = 48+14.
   int cardN = (gh - 104) / 42;
   bool cardExact = ((gh - 104) % 42 == 0 && cardN >= 1 && cardN <= 10);
   bool narrow = (gw == DSTRIP_GEAR_W);
   //--- P-LOG-10 (2026-10-01) — THE PLATE MUST BE YOUNGER THAN NOTHING. MT4 paints
   //--- in creation order; OBJPROP_ZORDER rules CLICKS alone (P-DRAW-83 already met
   //--- this: «paint order hid them, and click order gave every pixel»). MEASURED
   //--- 23:48 frame + the user's own screen: the x button MOVED narrow->wide
   //--- (1178->1490), the census reads it sane at the wide seat, and it still shows
   //--- nothing — a write never raises a painted object. The wide tiles are CREATED
   //--- (re-created for every new pairN) after the content of earlier paints, so
   //--- everything born before them — the left column, the head, the x — paints
   //--- under the card while every click still lands (z 1441/1442 > 1440). The only
   //--- raise MT4 honours is CREATE: when the plate is about to (re)appear while
   //--- family content predates it, purge the family once — the tiles land first,
   //--- the DrawStripGearPaint() that follows in the same paint recreates every
   //--- control above them, and the order stays correct until the plate reshapes.
   static int s_dsPlatePairN = -1;   // -1 = the last paint was the bake (or the panel was shut)

   //--- P-DRAW-78: THE SQUARE UNDERLAYER IS THE SECOND BOX. The cards bake their
   //--- own radius, border and shadow into `pnl_card*` and carry NO rect behind
   //--- them; this rect filled the transparent corners of the rounded skin with a
   //--- hard square, which is the report: two boxes, mixed, the inner one with no
   //--- radius. It is deleted here, every paint, so it cannot survive an upgrade.
   if(ObjectFind(0, DrawStripGearBgName()) >= 0)
   { ObjectDelete(0, DrawStripGearBgName()); dirty = true; }

   if(narrow && cardExact)
   {
      //--- P-LOG-10: returning from a wide phase, the content was recreated ABOVE
      //   where a fresh bake would land — purge once so the bake is born first.
      if(s_dsPlatePairN >= 0 && ObjectFind(0, "PnlDrawS_Gbake") < 0)
         dirty |= DrawStripGearObjectsPurge();
      s_dsPlatePairN = -1;
      //--- ONE baked card, both corners rounded, zero composition. The bake
      //--- carries the 14px margin itself (cardW+28 x ph+28, PnlCreate's seats).
      dirty |= DrawStripSkinBmp("PnlDrawS_Gbake", gx - 14, gy - 14, gw + 28, gh + 28,
                                "::Files\\Icons\\pnl_card" + IntegerToString(cardN) + ".bmp",
                                Z_STRIP);
      //--- a tab that was wide keeps its composed tiles: they die here.
      if(ObjectFind(0, "PnlDrawS_Gtop") >= 0)
      { ObjectDelete(0, "PnlDrawS_Gtop"); dirty = true; }
      if(ObjectFind(0, "PnlDrawS_Gbot") >= 0)
      { ObjectDelete(0, "PnlDrawS_Gbot"); dirty = true; }
      for(int lm = 0; lm < DSTRIP_GEAR_BLK_MAX; lm++)
      {
         string lmn = "PnlDrawS_Gmid" + IntegerToString(lm);
         if(ObjectFind(0, lmn) >= 0) { ObjectDelete(0, lmn); dirty = true; }
      }
   }
   else
   {
      //--- WIDE (or the off-grid net, which by construction cannot happen): the
      //--- composed W body. pairN counts the same rows the bake above would, so
      //--- the caps land on the same edges either way.
      int pairN = cardExact ? cardN : (gh - 104 + 41) / 42;
      if(pairN < 1) pairN = 1;
      if(pairN > DSTRIP_GEAR_BLK_MAX) { DrawStripSkinPurgeAt(1); return false; }
      //--- P-LOG-10: entering the composed branch, or a body that changed height —
      //   any tile born now would cover every control born before it. Purge once;
      //   the tiles land first and GearPaint recreates the whole content above.
      if(s_dsPlatePairN != pairN)
         dirty |= DrawStripGearObjectsPurge();
      //--- P-DRAW-110 (2026-10-01) — THE BODY STARTS AT THE HEAD'S OWN EDGE.
      //--- The three W bakes are drawn from the SAME origin the bake above uses,
      //--- `gy - 14` (the plate's own 14px margin), and the top cap is `14 + 70`:
      //--- its own 14px pad is spent ABOVE the head, so the head band ends at
      //--- `gy + DSTRIP_GEAR_HEAD_H` (56) and the body must continue THERE. This
      //--- block started it at `gy + 70` — the cap's HEIGHT, not its edge — so on
      //--- every WIDE tab (Style, Row: the only two that compose instead of baking)
      //--- the whole body sat **14px low**: a 14px transparent band under the header
      //--- (`gy+56 .. gy+70`, where the tab track's bed was the only thing covering
      //--- it) and the bottom cap ending at `gy + gh + 28` instead of `gy + gh + 14`.
      //--- The owner is the cards' own composition (BiotakPanels_Build.mqh:727-737:
      //--- mids at `py + PNL_HEAD_H + li*PNL_ROW_H`, foot cap at `+ pairN*PNL_ROW_H`)
      //--- and this is the same law on the strip's origin: MEASURED, `pnl_cardWtop`
      //--- 652x70 with its opaque rows at y10..69, `pnl_cardWmid` 652x42 with y0..41
      //--- — so `56 + 42*pairN + 62` = `gh + 14`, the plate's own bottom.
      // top cap — pnl_cardWtop.bmp (14+56=70px)
      dirty |= DrawStripSkinBmp("PnlDrawS_Gtop",
                                gx - 14, gy - 14, gw + 28, 70,
                                "::Files\\Icons\\pnl_cardWtop.bmp", Z_STRIP);
      for(int li = 0; li < DSTRIP_GEAR_BLK_MAX; li++)
      {
         string mn = "PnlDrawS_Gmid" + IntegerToString(li);
         if(li < pairN)
            dirty |= DrawStripSkinBmp(mn, gx - 14, gy + DSTRIP_GEAR_HEAD_H + li * 42,
                                      gw + 28, 42, "::Files\\Icons\\pnl_cardWmid.bmp",
                                      Z_STRIP);
         else if(ObjectFind(0, mn) >= 0) { ObjectDelete(0, mn); dirty = true; }
      }
      // bot cap — pnl_cardWbot.bmp (48+14=62px)
      dirty |= DrawStripSkinBmp("PnlDrawS_Gbot",
                                gx - 14, gy + DSTRIP_GEAR_HEAD_H + pairN * 42, gw + 28, 62,
                                "::Files\\Icons\\pnl_cardWbot.bmp", Z_STRIP);
      if(ObjectFind(0, "PnlDrawS_Gbake") >= 0)
      { ObjectDelete(0, "PnlDrawS_Gbake"); dirty = true; }
      s_dsPlatePairN = pairN;   // P-LOG-10: this body's tiles are now the family's elders
   }
   //--- the retired `ds_*` nine-slice for this family goes with it, every paint.
   for(int op = 0; op <= 8; op++)
   {
      string on = DrawStripGearSkinName(op);
      if(ObjectFind(0, on) >= 0) { ObjectDelete(0, on); dirty = true; }
   }
   //--- P-DRAW-79: THE `Gcard*` SPELLING IS THE ORPHAN, AND IT IS NOT A THEORETICAL
   //--- ONE. `PnlDrawS_Gcard*` also matches the family purge's own
   //--- `PnlDrawS_GB*` test only by accident of the letter, but worse: a chart
   //--- painted by the build that introduced it carries those five objects, and
   //--- the `DrawStripSkinBmp` of THIS build never re-writes nor deletes them —
   //--- so a card-sized plate from the old build sits under the new one, at a
   //--- stale x/y, until the user's next full sweep. The rename ships with the
   //--- sweep that removes the old spelling. Bounded: five exact names, once per
   //--- paint, and a delete only when the object is really there.
   if(ObjectFind(0, "PnlDrawS_Gcard") >= 0)
   { ObjectDelete(0, "PnlDrawS_Gcard"); dirty = true; }
   if(ObjectFind(0, "PnlDrawS_GcardT") >= 0)
   { ObjectDelete(0, "PnlDrawS_GcardT"); dirty = true; }
   if(ObjectFind(0, "PnlDrawS_GcardB") >= 0)
   { ObjectDelete(0, "PnlDrawS_GcardB"); dirty = true; }
   for(int oc = 0; oc < DSTRIP_GEAR_BLK_MAX; oc++)
   {
      string ocn = "PnlDrawS_GcardM" + IntegerToString(oc);
      if(ObjectFind(0, ocn) >= 0) { ObjectDelete(0, ocn); dirty = true; }
   }
   // purge body/seam rects (DrawStripBodyPaint no longer used for fam=1)
   dirty |= DrawStripBodyPurge(1);

   //--- log once per real height change
   static int s_dsPlateTab = -1, s_dsPlateH = -1;
    if(s_dsGear != s_dsPlateTab || gh != s_dsPlateH)
    {
       s_dsPlateTab = s_dsGear; s_dsPlateH = gh;
       dirty |= DrawStripGearTrimOverflow();
       //--- P-DRAFT-02: THE PLATE'S OWN VERDICT, IN ONE LINE. Every earlier report
       //--- of "the panel has no skin" was answered by an argument about which
       //--- branch SHOULD run; this line reports which one DID, whether the object
       //--- exists, what the terminal actually stored for its file, and the
       //--- transparency index that silently replaces the card tone with the
       //--- chart's background. One line, and the next screenshot carries the
       //--- answer with it.
       string plateName = (narrow && cardExact) ? "PnlDrawS_Gbake" : "PnlDrawS_Gtop";
       string wantRes   = (narrow && cardExact)
                          ? ("::Files\\Icons\\pnl_card" + IntegerToString(cardN) + ".bmp")
                          : "::Files\\Icons\\pnl_cardWtop.bmp";
       Print("[drawstrip] PLATE tab=", s_dsGear, " h=", gh, " w=", gw,
             " cardN=", cardN, " exact=", (cardExact ? 1 : 0), " narrow=", (narrow ? 1 : 0),
             " -> branch=", (narrow && cardExact ? "bake" : "wide"),
             " obj=", plateName,
             " exists=", (ObjectFind(0, plateName) >= 0 ? 1 : 0),
             " want=", wantRes,
             " got=", (ObjectFind(0, plateName) >= 0
                       ? ObjectGetString(0, plateName, OBJPROP_BMPFILE, 0) : "-"),
             " xy=", gx, ",", gy,
             " z=", (ObjectFind(0, plateName) >= 0
                     ? (int)ObjectGetInteger(0, plateName, OBJPROP_ZORDER) : -1),
             " plateFill=", (int)DrawStripPlateFill(),
             " rows=", s_dsGRN, " grids=", s_dsGGN, " secs=", s_dsGearSecN);
    }
    return dirty;
}

//--- P-DRAW-32 (2026-09-24) — WHERE THE SETTINGS PANEL OPENS. User order: «پنل
//--- تنظیمات از استریپ جدا باشه». The panel is its own card, so it needs its own spot
//--- and the project's two placement laws apply unchanged (P-BK-27: a toolbar never
//--- covers the handle it belongs to; P-DRAW-31: no two surfaces on one pixel). The
//--- hand's own carry (`s_dsGearManual`) wins everything and is only clamped — a panel
//--- the user placed is not moved by a repaint.
//--- P-DRAW-45 (2026-09-25) — EIGHT POSITIONS, SCORED, ON THE FINAL HEIGHT. User
//--- order: «حتما نباید به سمت پایین باز بشه، باید هوشمند باز بشه سمت راست بالا...
//--- بهترین برای همه سناریو ممکن ... هر دفهه باید کاربر بگیره درگ بکنه». The old
//--- ladder was four sides in a FIXED order and, when none fitted whole, it clamped
//--- candidate 0 — hanging the panel off the bottom edge until the user dragged it
//--- every time. Now four sides AND four corners are measured against the panel's
//--- FINAL height (the layout pass before this paint owns `s_dsGearH`), scored by
//--- what they cover and by the window they leave; the least-bad wins, not the first.
#define DSTRIP_GEAR_POS_N 8
string DrawStripGearSideName(const int i)
{
   string n[DSTRIP_GEAR_POS_N] = {"below", "above", "right", "left",
                                  "below-right", "above-right", "right-low", "left-low"};
   if(i < 0 || i >= DSTRIP_GEAR_POS_N) return "?";
   return n[i];
}

void DrawStripPlaceGear()
{
   if(s_dsGear == 0 || s_dsGearW0 <= 0 || s_dsGearH <= 0) return;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
   int gm = 4 + DSTRIP_SKIN_M;   // P-DRAW-29: the skin stands past the content
   int maxX = cw - s_dsGearW0 - gm, maxY = ch - s_dsGearH - gm;
   if(maxX < gm) maxX = gm;
   if(maxY < gm) maxY = gm;
   if(s_dsGearManual || (s_dsGearPlaced && s_dsGearPlacedObj == s_dsObj))
   {
      //--- P-DRAW-88: the hand's spot — or the last scored one — is kept. A tab
      //--- switch changes the HEIGHT, never the home: clamp to the window so a
      //--- taller tab cannot hang off the edge, but never re-score to a corner.
      if(s_dsGEX < gm) s_dsGEX = gm;
      if(s_dsGEY < gm) s_dsGEY = gm;
      if(s_dsGEX > maxX) s_dsGEX = maxX;
      if(s_dsGEY > maxY) s_dsGEY = maxY;
      return;
   }
   //--- P-DRAW-40 (2026-09-25): THE DRAWING IS A HARD RULE FOR THE PANEL TOO.
   //--- Reported: «پنل روی خوده ابجکت ظاهر میشه» — the placer knew the plate and
   //--- the open card and nothing about the object this strip serves (B-10: a
   //--- surface never covers the drawing it belongs to; P-DRAW-31's one-rule-two-
   //--- rects law). Same owner the fresh strip asks: `DrawStripDrawingBox`.
   int dx1 = 0, dy1 = 0, dx2 = 0, dy2 = 0;
   bool haveDraw = DrawStripDrawingBox(s_dsObj, dx1, dy1, dx2, dy2);
   const int W = s_dsGearW0, H = s_dsGearH;
   int px[DSTRIP_GEAR_POS_N], py[DSTRIP_GEAR_POS_N];
   px[0] = s_dsX;                    py[0] = s_dsY + s_dsH + DSTRIP_GEAR_GAP;   // below
   px[1] = s_dsX;                    py[1] = s_dsY - H - DSTRIP_GEAR_GAP;       // above
   px[2] = s_dsX + s_dsW + DSTRIP_GEAR_GAP; py[2] = s_dsY;                    // right
   px[3] = s_dsX - W - DSTRIP_GEAR_GAP;     py[3] = s_dsY;                    // left
   px[4] = s_dsX + s_dsW - W;        py[4] = s_dsY + s_dsH + DSTRIP_GEAR_GAP;   // below-right
   px[5] = s_dsX + s_dsW - W;        py[5] = s_dsY - H - DSTRIP_GEAR_GAP;       // above-right
   px[6] = s_dsX + s_dsW + DSTRIP_GEAR_GAP; py[6] = s_dsY + s_dsH - H;         // right, low
   px[7] = s_dsX - W - DSTRIP_GEAR_GAP;     py[7] = s_dsY + s_dsH - H;         // left, low
   const bool cardOpen = (g_UIPanelRX >= 0 && g_UIPanelRW > 0 && g_UIPanelRH > 0);
   //--- P-DRAW-73 (2026-09-28): the COLOUR BOARD is a surface too, and the panel's
   //--- score did not know it — so the panel could be placed straight through an open
   //--- board (H-05's other half; the board's placer now answers the same question).
   const bool boardOpen = (DrawStripIsColorSlot(s_dsPicker) && s_dsBW > 0 && s_dsBH > 0);
   int best = -1, bestAir = 0; long bestScore = 0;
   for(int c = 0; c < DSTRIP_GEAR_POS_N; c++)
   {
      if(px[c] < gm || py[c] < gm || px[c] > maxX || py[c] > maxY) continue;   // off the window
      const int oDraw  = haveDraw ? DrawStripRectOverlap(px[c], py[c], W, H, dx1, dy1, dx2 - dx1, dy2 - dy1) : 0;
      const int oPlate = DrawStripRectOverlap(px[c], py[c], W, H, s_dsX, s_dsY, s_dsW, s_dsH);
      const int oCard  = cardOpen ? DrawStripRectOverlap(px[c], py[c], W, H, g_UIPanelRX, g_UIPanelRY, g_UIPanelRW, g_UIPanelRH) : 0;
      const int oBoard = boardOpen ? DrawStripRectOverlap(px[c], py[c], W, H, s_dsBX, s_dsBY, s_dsBW, s_dsBH) : 0;
      // P-DRAW-45: the WORK is punished an order of magnitude above the surfaces it
      // shares the screen with (B-10: the panel never covers the drawing it serves),
      // the plate next (P-DRAW-31: two surfaces never share a pixel) and the open card
      // last; between two spots that cover nothing, the one leaving more window wins,
      // and a real tie keeps the reading order (below, above, right, left, corners).
      const long score = -((long)oDraw * 1000 + (long)oPlate * 20 + (long)oBoard * 20 + (long)oCard * 5);
      const int air = MathMin(MathMin(px[c] - gm, py[c] - gm),
                              MathMin(maxX - px[c], maxY - py[c]));
      if(best < 0 || score > bestScore || (score == bestScore && air > bestAir))
      { best = c; bestScore = score; bestAir = air; }
   }
   if(best < 0) best = 0;   // nothing fits whole: the reading order, clamped below
   s_dsGEX = px[best]; s_dsGEY = py[best];
   s_dsGearPlaced = true; s_dsGearPlacedObj = s_dsObj;   // P-DRAW-88: scored once
   if(s_dsGEX < gm) s_dsGEX = gm;
   if(s_dsGEY < gm) s_dsGEY = gm;
   if(s_dsGEX > maxX) s_dsGEX = maxX;
   if(s_dsGEY > maxY) s_dsGEY = maxY;
   //--- P-DRAW-45: ONE line per REAL move — a paint may run many times a second while
   //--- the pointer moves and this project bans unbounded logging. It names the side,
   //--- the spot, the panel size, the window and the air the winner left.
   static int  s_gpLogX = -1, s_gpLogY = -1, s_gpLogSide = -9;
   if(s_gpLogSide != best || s_gpLogX != s_dsGEX || s_gpLogY != s_dsGEY)
   {
      s_gpLogSide = best;
      s_gpLogX = s_dsGEX; s_gpLogY = s_dsGEY;
      Print("[drawstrip] gear side=", DrawStripGearSideName(best),
            " pos=(", s_dsGEX, ",", s_dsGEY, ") size=", W, "x", H,
            " chart=", cw, "x", ch, " air=", bestAir);
   }
}

//--- P-DRAW-42 (2026-09-25) — NO ORPHAN SURVIVES A REATTACH. `PnlDrawS_*` carries no
//--- chart id (one instance per chart), so a plate family or a flat bg rect left by
//--- a killed terminal is still on the chart at the next attach while every static
//--- here starts clean — the user's dark rectangle with nothing on it. One sweep,
//--- once per session, at the first paint: before this session made anything, and
//--- all of one ObjectsDeleteAll call (the same orphan purge InitializeUIStates does
//--- for its own prefix). Costs nothing after the first paint.
static bool s_dsSwept = false;
//--- P-DRAW-84: the gear panel's press already found its control. A release then
//--- arrives on BOTH channels (CHARTEVENT_CLICK and CHARTEVENT_OBJECT_CLICK), and
//--- the dismissal branch below reads a press that lands on the panel as a click on
//--- the chart — which would shut the panel the user is working in. One flag, set by
//--- the press edge and read by the release, so one gesture is one owner.
static bool s_dsGearPressSpent = false;
void DrawStripOrphanSweep()
{
   if(s_dsSwept) return;
   s_dsSwept = true;
   ObjectsDeleteAll(0, "PnlDrawS_");
}
#endif // DRAW_STRIP_SKIN_MQH
