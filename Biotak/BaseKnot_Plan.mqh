// BaseKnot_Plan.mqh - BaseKnotTool split 2026-09-29: exact lines 4053-5374 of BaseKnotTool.mqh, byte-identical, zero renames.
#ifndef BASE_KNOT_PLAN_MQH
#define BASE_KNOT_PLAN_MQH

// P-BK-27 — THE INFO READOUT'S SIZE (user: «اطلاعات بیس نوت خیلی ریزه»).
// It used to be frozen at PnlPt(BK_PT_INFO): a DESIGN nominal, so on a 120-DPI
// terminal the readout drew at 6pt while the box' own text drew at
// `g_bkTextSize` (10 raw pt) — the numbers were the smallest text on the box.
// One owner now, two rungs:
//   * 0 (shipped) = the LABEL FAMILY's own size, `inpFontSize` (P-BK-56 — see below);
//   * 1..24 = the user's OWN raw points, the same unit the neighbouring SIZE /
//     COUNT SIZE / TRADE SIZE rows use. Never PnlPt here: that re-expresses the
//     module's NON-user chrome (P-UI-34), and a panel number that means a
//     different size than the number beside it is the bug, not the feature.
// P-BK-56 (2026-09-16, user: «این لیبل اطلاعات مثل بقیه لیبل اطلاعات باشه»): the shipped
// rung used to be the BOX' text size (`g_bkTextSize`, 10 raw pt), which made the note the
// one readout on the chart sized by a different grid than the label family it sits among
// (``Arial Bold`` 8pt — the ATR/TH columns and the trade card). The note IS that family's
// sibling — a chart-anchored text a human reads (P-UI-85's Z_CHART_LABEL rung) — so it
// follows the SAME grid now: font `inpFontName`, size `inpFontSize`, rung Z_CHART_LABEL.
// The box' own TEXT (the TV-style box label) keeps `g_bkTextSize`: it is box art, not a
// readout. BKINFOSIZE-OFF keeps the retired rung one uncomment away.
int BKInfoFontPt()
{
   int own = ClampSettingInt(g_bkInfoFontSize, 0, 24);
   if(own > 0) return own;                            // the user's own pt — unchanged
   return ClampSettingInt(inpFontSize, 4, 24);         // P-BK-56: the label family's grid
   // BKINFOSIZE-OFF (P-BK-27/56): the retired rung — the box' own text size.
   // BKINFOSIZE-OFF: return ClampSettingInt(g_bkTextSize, 8, 24);
}
//--- P-BK-86 — THE NOTE'S PLATE: geometry, the plate itself, and its follower. --------
//--- The plate's height and the pair's two rectangles come from ONE owner, so the writer
//--- and the follower can never place them differently: a plate that drifts off its own
//--- ink is worse than no plate at all.
int BaseKnotNotePlateH() { return PnlRawLineH(BKInfoFontPt()) + 2 * BK_NOTE_PAD_Y; }
//--- the plate's WIDTH, off the very string the note prints — its own ONE owner, so the
//--- writer (which draws the plate) and the follower (which keeps its size in step with the
//--- ink, P-BK-87) can never measure two different things.
int BaseKnotNotePlateW(const string txt)
{
   int pw = PnlRawTextW(txt, BKInfoFontPt()) + 2 * BK_NOTE_PAD_X;
   if(pw < 2 * BK_NOTE_PAD_X + 8) pw = 2 * BK_NOTE_PAD_X + 8;   // a not-yet-written note still gets a plate
   return pw;
}
//--- the pair's two TOP-LEFT corners, from the projected corner. ONE owner of the offsets:
//--- the writer and the follower both come through here, so the plate and the ink inside it can
//--- never be placed by two spellings of the same arithmetic — a plate that drifts off its own
//--- ink is worse than none.
//--- `sx,sy` = the box' top-left corner in chart-window pixels (ChartTimePriceToXY); the
//--- plate's BOTTOM edge sits on that corner, so the note still reads as the box' own caption
//--- and grows to the RIGHT exactly as the chart-space text it replaced did.
//--- P-BK-87: and then the pair is FITTED BACK INTO THE WINDOW. `pw` is an input here, not a
//--- by-product — the right-hand fit cannot be decided without it. A screen object has no chart
//--- to clip it, so this is the only place the note can be kept on screen at all.
void BaseKnotNotePlateTop(const int sx, const int sy, const int pw, const int ph,
                          int &px, int &py, int &tx, int &ty)
{
   px = sx - BK_NOTE_PAD_X;
   py = sy - BK_NOTE_LIFT - ph;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   if(cw > 0)
   {
      int right = cw - MathMax(8, inpLabelsMarginLeft);   // the label family's own right boundary
      if(px + pw > right) px = right - pw;
      if(px < BK_NOTE_EDGE_MARGIN) px = BK_NOTE_EDGE_MARGIN;
   }
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(ch > 0)
   {
      if(py < BK_NOTE_EDGE_MARGIN) py = BK_NOTE_EDGE_MARGIN;
      else if(py + ph > ch - BK_NOTE_BOTTOM_SAFE) py = ch - BK_NOTE_BOTTOM_SAFE - ph;
      if(py < BK_NOTE_EDGE_MARGIN) py = BK_NOTE_EDGE_MARGIN;   // a window shorter than the plate
   }
   tx = px + BK_NOTE_PAD_X;
   ty = py + BK_NOTE_PAD_Y;
}
void BaseKnotNotePlatePx(const int sx, const int sy, const string txt,
                         int &px, int &py, int &pw, int &ph, int &tx, int &ty)
{
   ph = BaseKnotNotePlateH();
   pw = BaseKnotNotePlateW(txt);
   BaseKnotNotePlateTop(sx, sy, pw, ph, px, py, tx, ty);
}
//--- The plate: the CHART'S OWN background, and no border of its own — invisible over an
//--- empty chart, an honest cut-out where the candles are (the way MetaTrader's own price
//--- label reads). It rides Z_BOX_INFO, BELOW the note's own Z_CHART_LABEL rung, so the ink
//--- is always painted on top of its plate; and both are SCREEN objects, so no chart-space
//--- art — a candle, a zone edge, a level line — can reach either one again.
void BaseKnotNotePlateDraw(const string pn, const int px, const int py, const int pw,
                           const int ph)
{
   if(ObjectFind(0, pn) < 0) ObjectCreate(0, pn, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   ObjectSetInteger(0, pn, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, pn, OBJPROP_XDISTANCE, px);
   ObjectSetInteger(0, pn, OBJPROP_YDISTANCE, py);
   ObjectSetInteger(0, pn, OBJPROP_XSIZE, pw);
   ObjectSetInteger(0, pn, OBJPROP_YSIZE, ph);
   ObjectSetInteger(0, pn, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, pn, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, pn, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, pn, OBJPROP_COLOR, bg);       // the frame …
   ObjectSetInteger(0, pn, OBJPROP_BGCOLOR, bg);     // … and the fill: ONE ink, the chart's own
   ObjectSetInteger(0, pn, OBJPROP_BACK, false);
   ObjectSetInteger(0, pn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, pn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, pn, OBJPROP_ZORDER, Z_BOX_INFO);
   // P-BK-92: NO TIMEFRAMES on a plate. OBJPROP_TIMEFRAMES is a LABEL-only property —
   // an OBJ_RECTANGLE_LABEL keeps showing under any mask (P-TH3-INFO-10 had to delete
   // its bar for exactly this). So its visibility is EXISTENCE: BaseKnotPlaceBadges
   // deletes this plate on a hidden TF, BaseKnotNotePlateFollow grows it back. A mask
   // write here is the empty bar over the candles (P-BK-86) the day BKTFSCOPE is
   // restored — one line away (BaseKnotTFMask's own note).
   ObjectSetString(0, pn, OBJPROP_TOOLTIP,
                   "BK note plate (P-BK-86): the chart's own background color, drawn UNDER the "
                   "note so the candles and the level lines can never be read through its ink");
}
//--- P-BK-86: a SCREEN object does not follow the chart by itself — the chart-space text it
//--- replaced did. The projection is therefore ours to redo, and it is redone in exactly the
//--- two places that already keep the note on its box: the child-move path (a drag) and the
//--- pump (a scroll, a zoom, a window resize, a new bar). READ-GUARDED the project's own way:
//--- while the pair is where it already is this costs six terminal reads and NOT ONE
//--- ObjectSet*, so a still chart pays nothing for it.
//--- P-BK-87: the guard covers the plate's SIZE too. The note's own text is not constant — the
//--- bar count, the risk, the type — so a plate that only ever moved would sooner or later be
//--- too narrow for the ink it carries, which is the one thing a plate exists to prevent.
// P-BK-91: the home is the box' TOP-LEFT corner (was top-right) - the note
// reads before the price reaches it, and the plate never covers the fresh candles.
void BaseKnotNotePlateFollow(const string pfx, const datetime t1, const double top)
{
   string in = BaseKnotInfoName(pfx);
   if(ObjectFind(0, in) < 0) return;   // this box carries no note — the common case
   int sx = 0, sy = 0;
   if(!ChartTimePriceToXY(0, 0, t1, top, sx, sy)) return;   // the window cannot answer yet: keep the last pixels
   string pn = BaseKnotInfoPlateName(in);
   bool hasPlate = (ObjectFind(0, pn) >= 0);
   int ph = BaseKnotNotePlateH();
   int pw = BaseKnotNotePlateW(ObjectGetString(0, in, OBJPROP_TEXT));
   int px, py, tx, ty;
   BaseKnotNotePlateTop(sx, sy, pw, ph, px, py, tx, ty);
   if(hasPlate &&
      (int)ObjectGetInteger(0, pn, OBJPROP_XDISTANCE) == px &&
      (int)ObjectGetInteger(0, pn, OBJPROP_YDISTANCE) == py &&
      (int)ObjectGetInteger(0, pn, OBJPROP_XSIZE) == pw &&
      (int)ObjectGetInteger(0, pn, OBJPROP_YSIZE) == ph &&
      (int)ObjectGetInteger(0, in, OBJPROP_XDISTANCE) == tx &&
      (int)ObjectGetInteger(0, in, OBJPROP_YDISTANCE) == ty) return;   // steady state: reads only
   if(hasPlate)
   {
      ObjectSetInteger(0, pn, OBJPROP_XDISTANCE, px);
      ObjectSetInteger(0, pn, OBJPROP_YDISTANCE, py);
      ObjectSetInteger(0, pn, OBJPROP_XSIZE, pw);
      ObjectSetInteger(0, pn, OBJPROP_YSIZE, ph);
   }
   else
   {
      // P-BK-92: the plate lives by EXISTENCE (BaseKnotPlaceBadges deletes it on a hidden
      // TF), so a visible note grows its bar back here — and the ink is re-created the
      // younger object, or the fresh plate paints over its own text (P-BK-88).
      BaseKnotNotePlateDraw(pn, px, py, pw, ph);
      BaseKnotNoteInkToFront(in);
   }
   ObjectSetInteger(0, in, OBJPROP_XDISTANCE, tx);
   ObjectSetInteger(0, in, OBJPROP_YDISTANCE, ty);
}
//+------------------------------------------------------------------+
//| P-BK-88 — THE INK IS RE-CREATED YOUNGER THAN ITS PLATE.           |
//|                                                                  |
//| The terminal draws overlapping objects in CREATION order - ZORDER  |
//| is click priority only (MQL4/MQL5 reference on OBJPROP_ZORDER) -  |
//| so the plate, created after the ink on the first draw, covered    |
//| its own text with an opaque bar: a correctly-sized empty plate    |
//| and invisible numbers, on every chart, even inside the Auto       |
//| grace. Re-creating the ink last wins under BOTH orderings (its    |
//| ZORDER already sits above the plate's), and it runs only on the   |
//| first draw - steady state stays read-only. The text properties    |
//| are read back off the object, so no field builder is spelled      |
//| twice; the rung is NOT read back (reads are banned) - it is       |
//| restated from the ink's own declared rung, see the write below.   |
//+------------------------------------------------------------------+
void BaseKnotNoteInkToFront(const string o)
{
   if(ObjectFind(0, o) < 0) return;
   string keepTxt    = ObjectGetString(0, o, OBJPROP_TEXT);
   string keepFont   = ObjectGetString(0, o, OBJPROP_FONT);
   int    keepSize   = (int)ObjectGetInteger(0, o, OBJPROP_FONTSIZE);
   color  keepClr    = (color)ObjectGetInteger(0, o, OBJPROP_COLOR);
   int    keepAnchor = (int)ObjectGetInteger(0, o, OBJPROP_ANCHOR);
   long   keepMask   = ObjectGetInteger(0, o, OBJPROP_TIMEFRAMES);
   string keepTip    = ObjectGetString(0, o, OBJPROP_TOOLTIP);
   ObjectDelete(0, o);
   if(!ObjectCreate(0, o, OBJ_LABEL, 0, 0, 0)) return;
   ObjectSetString(0, o, OBJPROP_TEXT, keepTxt);
   ObjectSetString(0, o, OBJPROP_FONT, keepFont);
   ObjectSetInteger(0, o, OBJPROP_FONTSIZE, keepSize);
   ObjectSetInteger(0, o, OBJPROP_COLOR, keepClr);
   ObjectSetInteger(0, o, OBJPROP_ANCHOR, keepAnchor);
   ObjectSetInteger(0, o, OBJPROP_BACK, false);
   ObjectSetInteger(0, o, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, o, OBJPROP_HIDDEN, true);
   // The rung is NOT read back (the zorder audit bans OBJPROP_ZORDER reads in
   // product code - a diagnostic, not a product question) and it is not
   // re-decided either: the only object this function ever re-creates is the
   // note ink, whose one declared rung is Z_CHART_LABEL - the same constant the
   // writer above spells (P-BK-56). Restating it here is not a new decision.
   ObjectSetInteger(0, o, OBJPROP_ZORDER, Z_CHART_LABEL);
   ObjectSetInteger(0, o, OBJPROP_TIMEFRAMES, keepMask);
   ObjectSetString(0, o, OBJPROP_TOOLTIP, keepTip);
}
// Chart-anchored "[<side> · <riskTag> <risk> | <box height> | N bars · <class> <type>]"
// label at the box' top-left corner (P-BK-57: the second number, bare — BaseKnotHeightTag).
// P-BK-46: the first number is the TRADE'S RISK (R) and `riskTag` NAMES WHERE IT
// CAME FROM — "EngSL" of the knot's own TF (or the node's own when it capped the plan,
// P-BK-52/53), or "box height" while neither answered. A size without its source is a
// number nobody can check.
// P-BK-54 (2026-09-16, user: «تی پی رو … در اطلاعات نشون نده … EngSL 17.9 همین بنویسه
// فقط اینطوری خلاصه‌ه») — THE NOTE CARRIES NO TARGETS AND NO UNIT WORD. WHY: the note is
// read AT A GLANCE on a live chart, and the plan's TP1..TP3 field made it a sentence:
// three numbers the user did not ask for, printed between the risk and the bar count,\r
// while the targets are ALREADY DRAWN (P-BK-50's ticks) and ALREADY SPELLED OUT leg by
// leg in the hover (`tpTip`). So the field is retired IN PLACE (BKTAGTP-OFF —
// `BaseKnotTPPlanTag` is kept, one call away) and the risk reads `EngSL 17.9`, the unit
// implied by the plan's own row (the TRex card prints `Eng.SL: 0.2` the same way).
// WHAT IS NOT AFFECTED: the hover still prints every leg with its level, its pips from
// the entry and its R (BaseKnotTPPlanTip), and the ticks on the chart are unchanged.
// P-BK-57 (2026-09-16, user: «مقدار حرکت رو هم به صورت عدد فقط نمایش بده بفهمیم چقدره»)
// — the SECOND number is the box' OWN HEIGHT, bare (BaseKnotHeightTag): the risk says how
// big the stop is, this says how big the thing the order is read on is. The chart face
// keeps the number alone; the hover right below names it, spells `top - bottom` and gives
// its pips, so the number is checkable where there is room to check it (P-BK-46/53's split).
// THE GATE: tools/base-count-audit.py [note fields]/[note height] reads the note's own TEXT
// expression AND the field's builder — a target field, the word "Pips", or a height field
// that grew a name (or a second copy beside the fallback risk) fails the build.
void BaseKnotWriteInfo(const string in, const datetime t1, const datetime t2,
                       const double top, const double bot,
                       const double hPips, const string tpTip,
                       const string side, BaseKnotSpan &sp,
                       BaseKnotNode &nd, const long tfMask, const string riskTag,
                       const string tradeTip,   // P-BK-51: the stop's sentence + the entry's own
                       const bool atCorner = false)   // P-BK-58: the family's row instead of the box
{
   // P-BK-58: ONE object at a time. The placement is a PARAMETER (decided by
   // BaseKnotNoteAtCorner), and the other home is emptied as this one is written, so a mode
   // change can never leave two copies of the same number on the chart. The box-side note is
   // an OBJ_TEXT pinned to the box' top-left corner (time/price); the corner row is an
   // OBJ_LABEL pinned to the slot the label module pushed in — the same text, the same font,
   // size, colour and rung (P-BK-27/56), only its anchor differs.
   string cn = BaseKnotCornerName();
   if(atCorner)
   {
      if(cn == "" || s_bkCornerSide < 0) return;   // no slot pushed: nothing to draw into
      if(ObjectFind(0, in) >= 0) ObjectDelete(0, in);   // the box-side copy goes with the mode that wanted it
      ObjectDelete(0, BaseKnotInfoPlateName(in));   // P-BK-86: and its plate goes with it — an empty bar is not a readout
   }
   else if(!BaseKnotNoteInCorner() && cn != "" && ObjectFind(0, cn) >= 0)
      ObjectDelete(0, cn);   // a MODE change took the note back to the box (P-BK-58); while the mode
                             // IS corner the row belongs to BaseKnotNoteCornerRefresh, so a box that
                             // is not the one it answers never wipes it
   // ONE name: everything below is the SAME write in either home — the text, the font, the
   // size, the colour, the rung and the hover are shared, and only the last lines differ.
   string o = (atCorner ? cn : in);
   // P-BK-86: BOTH homes are SCREEN objects now — the box-side note moved off the chart layer
   // (it was an OBJ_TEXT, and MT4 painted the candles and the level lines over its glyphs).
   // ObjectCreate never re-types an object it finds, so a pre-plate build's note is purged
   // here; it is the one read that lets an upgrade heal instead of keeping the old object.
   if(ObjectFind(0, o) >= 0 && (int)ObjectGetInteger(0, o, OBJPROP_TYPE) != OBJ_LABEL)
      ObjectDelete(0, o);
   if(ObjectFind(0, o) < 0) ObjectCreate(0, o, OBJ_LABEL, 0, 0, 0);
   int bars = sp.life, still = sp.still;   // P-BK-41: one span, read once
   string barsPart = (bars > 0 ? " | " + IntegerToString(bars) + " bars" : "");
   datetime ws1, ws2;                       // P-BK-84: the class' span — box ∪ base (the box is a floor)
   BaseKnotClassSpan(sp, t1, t2, ws1, ws2);
   // P-BK-28: the BASE'S SIZE CLASS rides the note itself — "… | 12 bars · H1 base".
   // P-BK-29: so does the node type — "… · FTR" — when there is one to claim.
   // BKTAGTP-OFF (P-BK-54): the retired plan-target field sat here — restore it by
   // putting `+ tpTag` back after the risk (and taking BaseKnotTPPlanTag from BKTAGTP-OFF
   // in BaseKnotSync / BaseKnotSyncLive, which still build `tpTip` for the hover).
   ObjectSetString(0, o, OBJPROP_TEXT,
                   "[" + side + " · " + riskTag + " " + DoubleToString(hPips, 1) + BaseKnotHeightTag(top, bot, riskTag) + barsPart + BaseKnotBaseTag(still, ws1, ws2, top, bot) + BaseKnotNodeTag(nd) + "]");   // P-BK-46/40/41: the risk and its source, then the box' own height (P-BK-57), then the class — P-BK-84: off the BASE'S OWN span (∪ the box'), so neither a narrow box nor the chart TF can move it. P-BK-81: the four pattern names are gone — `side` (BUY/SELL) IS the direction now
   ObjectSetString(0, o, OBJPROP_FONT, inpFontName);   // P-BK-56: the label family's own font
   ObjectSetInteger(0, o, OBJPROP_FONTSIZE, BKInfoFontPt());   // P-BK-27/56
   ObjectSetInteger(0, o, OBJPROP_COLOR, BaseKnotFgForBg());
   ObjectSetInteger(0, o, OBJPROP_ANCHOR, (atCorner ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_UPPER));   // P-BK-58: the row is right-aligned in the family's column — P-BK-86: the box-side note's TOP-LEFT is the ink's corner inside its plate, so its bottom edge still sits on the box' top edge the way the chart-space text's baseline did
   ObjectSetInteger(0, o, OBJPROP_BACK, false);
   ObjectSetInteger(0, o, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, o, OBJPROP_HIDDEN, true);
   // P-BK-56: the note is TEXT A HUMAN READS, so it rides the TEXT layer's rung — the rung
   // the whole label family writes (P-UI-85) and the one that is ABOVE every chart-space art
   // rung, so no box, ray, zone edge or drawn HTF candle can be painted over it. It used to
   // ride Z_BOX_INFO (60): the box family's own rung, i.e. under the box' art and under every
   // label. P-BK-58: the corner row is the same readout, so it rides the same rung.
   // P-BK-86: and the rung is now a REAL guarantee, not a hope — the box-side note is a SCREEN
   // object, i.e. one layer above every chart-space rung, which is where Z_BOX_INFO went: the
   // PLATE rides it (under the ink, above the chart), so the two are ordered against each
   // other and against nothing else. See the P-BK-86 block by the constants for the whole why.
   ObjectSetInteger(0, o, OBJPROP_ZORDER, Z_CHART_LABEL);
   ObjectSetInteger(0, o, OBJPROP_TIMEFRAMES, tfMask);
   // P-BK-51: the trade's numbers arrive READY-BUILT (`tradeTip` — the stop's size and its
   // placement behind the entry, then how deep the entry waits and what sized it), so this
   // writer never spells a geometry of its own.
   ObjectSetString(0, o, OBJPROP_TOOLTIP, "BK " + side + ": " + tradeTip +
                   (bars > 0 ? ", " + IntegerToString(bars) + " bars" : "") +
                   tpTip +   // P-BK-50: the plan's own targets, leg by leg (level + pips + R) — P-BK-54: the note's ONLY home for them
                   BaseKnotHeightTip(top, bot, riskTag) +   // P-BK-57: the note's bare second number, NAMED here, with its arithmetic
                   BaseKnotBaseLine(still, ws1, ws2, top, bot) +   // P-BK-84: the class, off the BASE'S OWN span
                   (bars > 0 ? "\n     " + IntegerToString(bars) + " bars: between the ENTRY candle " +
                               "and the EXIT candle (entry not counted, exit counted) · " +
                               IntegerToString(still) + " stood still in the band" : "") +   // P-BK-40/42
                   (bars > 0 ? "\n     band -> entry candle " + TimeToString(sp.tStart, TIME_DATE|TIME_MINUTES) +
                               (sp.tExit > sp.tLast
                                ? " -> exit candle " + TimeToString(sp.tExit, TIME_DATE|TIME_MINUTES)
                                : " -> no exit yet: the base is still holding the band") : "") +
                   BaseKnotNodeLine(nd, top, bot) +   // P-BK-29
                   (atCorner ? "\n     the row above the trade card is this box' note (P-BK-58): " +
                               "the selected box, or the newest while nothing is selected" : ""));
   // P-BK-58: the ONE difference between the two homes — the slot the label module pushed in,
   // or the box' own corner. P-BK-86: BOTH are screen objects now, so the difference is only
   // WHERE the pixels come from (a pushed slot vs a projection of `t2, top`).
   if(atCorner)
   {
      ObjectSetInteger(0, o, OBJPROP_CORNER, s_bkCornerSide);
      ObjectSetInteger(0, o, OBJPROP_XDISTANCE, MathMax(8, s_bkCornerX));
      ObjectSetInteger(0, o, OBJPROP_YDISTANCE, MathMax(8, s_bkCornerY));
   }
   else
   {
      // P-BK-86: the box-side home is a SCREEN PAIR — the note, and the plate behind it. Both
      // are pinned by the projection of the box' top-left corner (the same projection the
      // box' own handles used, P-BK-59/61). If the window cannot answer it yet, the note keeps
      // its last pixels instead of jumping to a guessed corner.
      int sx = 0, sy = 0;
      if(ChartTimePriceToXY(0, 0, t1, top, sx, sy))
      {
         int px, py, pw, ph, tx, ty;
         // the plate is MEASURED against the very string that was just written — read back off
         // the object, so a width typed here could never disagree with the ink that is drawn.
          BaseKnotNotePlatePx(sx, sy, ObjectGetString(0, o, OBJPROP_TEXT), px, py, pw, ph, tx, ty);
          string plateName = BaseKnotInfoPlateName(o);
          bool plateNew = (ObjectFind(0, plateName) < 0);
          BaseKnotNotePlateDraw(plateName, px, py, pw, ph);
          // P-BK-88: the plate is the younger object on this first draw, so
          // without this the opaque bar covers its own ink (creation order
          // paints, ZORDER only clicks). Steady state never reaches here.
          if(plateNew) BaseKnotNoteInkToFront(o);
          ObjectSetInteger(0, o, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, o, OBJPROP_XDISTANCE, tx);
         ObjectSetInteger(0, o, OBJPROP_YDISTANCE, ty);
      }
   }
}
// Live sizing set — Entry/SL/TP + info shown WHILE drawing (before click 2).
// ONE fixed tag (single sizing at a time); wiped at commit/cancel/deinit.
string BaseKnotLiveTag()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "LIVE_";
}
void BaseKnotWipeLive()
{
   string tag = BaseKnotLiveTag();
   if(tag != "") ObjectsDeleteAll(0, tag);
}
// Live setup preview from corner 1 to the cursor. Direction re-resolves here;
// the commit freezes it. Zero-height cursor = rays hidden, preview rect stays.
void BaseKnotSyncLive(const datetime t2raw, const double p2raw)
{
   string tag = BaseKnotLiveTag();
   if(tag == "") return;
   double top = MathMax(g_bkP1, p2raw), bot = MathMin(g_bkP1, p2raw);
   if(top <= bot) { BaseKnotWipeLive(); return; }
   datetime t1 = g_bkT1, te = t2raw;
   if(te < t1) { datetime tt = t1; t1 = te; te = tt; }
   int dir = BaseKnotResolveDirection(top, bot);
   long tfMask = BaseKnotTFMask(Period());
   // P-BK-46/50: the preview is sized the SAME way the committed box is, with THIS
   // chart's TF as the knot's own — a box being drawn has no class and no type yet
   // (both are readings of the whole story and land at commit), so the side is the
   // live price's, R is EngSL of this chart's TF and the targets are that TF's own
   // plan legs. The commit re-reads all of them.
   // P-BK-51: and with no TYPE there is no HuntSL read either — the preview is the FTR
   // case (ONE EngSL of penetration), and the stop is ONE EngSL behind the entry.
   // P-BK-79: AND WITH NO STORY YET THERE IS NO ANCHOR — every read below asks for the LIVE
   // row (anchor 0), which is exactly the row BaseKnotEngNeeds always pushes first for this
   // chart's TF. The committed Sync re-reads all of them at the box' own `storyT`.
   int    liveTF = Period();
   double entry = 0, sl = 0;
   BaseKnotCalcLevels(top, bot, dir, BK_NODE_NONE, liveTF, entry, sl, 0);
   string riskTag   = BaseKnotRiskTag(liveTF, liveTF, top, bot, 0);   // P-BK-52: named with the number the pick drew
    double hPips  = BaseKnotRiskPips(liveTF, top, bot, 0);
    // BKE2-OFF (2026-09-28): 2nd entry retired — purge any live leftovers.
    ObjectDelete(0, tag + "ENTRY2");
    ObjectDelete(0, tag + "SL2");
    for(int e2k = 1; e2k <= BK_TP_PLAN_MAX; e2k++) ObjectDelete(0, tag + "E2TP" + IntegerToString(e2k));
    int dg = GetCachedDigits();
   string side = (dir >= 0 ? "BUY" : "SELL");
   // BKTAGTP-OFF (P-BK-54): string tpTag = BaseKnotTPPlanTag(0);   // the retired note field
   string tpTip = BaseKnotTPPlanTip(0, entry, dir, hPips, 0);   // P-BK-54: the hover keeps every leg
   string edgeLive  = (dir >= 0 ? "top" : "bottom");
   string lvWhy = " (ONE " + BaseKnotEntryOffsetTag(false) + " INSIDE the box' " + edgeLive +
                  " edge — " + BaseKnotEntryWhy(BK_NODE_NONE, liveTF, false, top, bot, 0) + ")";
   string stopWhyLive = " (INSIDE the box' " + edgeLive + " edge, ONE " + riskTag + " behind the entry" +
                        BaseKnotStopWhy(liveTF, top, bot, 0) + ")";
    string tradeTipLive = "risk " + DoubleToString(hPips, 1) + " pips (" + riskTag + ") = the stop" + stopWhyLive +
                          BaseKnotEntryLine(BK_NODE_NONE, liveTF, false, dir, top, bot, 0);
    datetime tLiveFar = te + (te > t1 ? (te - t1) : PeriodSeconds());
    datetime tLiveTps, tLiveTpe;
    BaseKnotTPTickSpan(t1, te, tLiveTps, tLiveTpe);
    BaseKnotMakeRay(tag + "ENTRY", te, tLiveFar, entry, g_bkEntryColor, STYLE_SOLID, BK_LEVEL_WIDTH,
                    "BK " + side + " Entry (sizing): " + DoubleToString(entry, dg) + lvWhy, tfMask, true);
    BaseKnotMakeRay(tag + "SL", te, tLiveFar, sl, g_bkStopColor, STYLE_DASH, BK_LEVEL_WIDTH,
                    "BK " + side + " Stop (sizing): " + DoubleToString(sl, dg) + stopWhyLive, tfMask, true);
    // BKE2-OFF: no 2nd-entry rays here (created above only to purge).
   // P-BK-50: the targets are the plan's own legs — one short, THICK tick each at the
   // chart's right edge (never a ray), drawn only for the legs the plan has pushed.
   for(int tk = 1; tk <= BaseKnotTPCount(); tk++)
   {
      double lv = BaseKnotTPLevel(entry, dir, 0, tk, 0);
      if(lv <= 0.0) continue;
      double tpP = BaseKnotPlanTPPips(0, tk, 0);
      BaseKnotMakeRay(tag + "TP" + IntegerToString(tk), tLiveTps, tLiveTpe, lv, g_bkTargetColor,
                      BK_TP_TICK_STYLE, BK_TP_TICK_WIDTH,
                      "BK " + side + " TP" + IntegerToString(tk) + " (sizing): " + DoubleToString(lv, dg) + " (+" +
                      DoubleToString(tpP, 0) + " pips from the entry" +
                      (hPips > 0.0 ? " = " + DoubleToString(tpP + hPips, 0) + " from the stop, " +
                                     DoubleToString(tpP / hPips, 1) + "R" : "") +
                      " — the plan's own TP" + IntegerToString(tk) + ")", tfMask, false);
   }
    // BKE2-OFF: no set-2 ticks here.
    BaseKnotSpan spLive;   // P-BK-41: the live label reads the same span record
   BaseKnotLiveBarCount(t1, te, top, bot, spLive);
   // P-BK-29: a box being SIZED pays no STORY read here — the walk of the past market
   // (side, break, second break, state) is what the hot sizing path must not run per mouse
   // move; the committed Sync reads it.
   // P-BK-55 (2026-09-16, user: «توی اطلاعات چرا نوع گره رو نشون نمیده»): THE TYPE IS NOT
   // THAT READ. The type is the node's LENGTH (P-BK-75/78: the box' own HEIGHT against the
   // THs of the node's own time and the two rungs above it) — pure arithmetic on numbers
   // the module was PUSHED, no series and no TH call, so a box being SIZED answers it from
   // the VERY span its class came from. The sizing note used to show a class with no type.
   // ONE RULE, ONE READ: the same two owners the committed read uses
   // (BaseKnotBaseTFMin for the node's time, BaseKnotNodeKindOfLength for the type).
   // The record is zeroed in the SAME shape BaseKnotNodeRead opens with, so an unread half
   // can never be a garbage field the hover prints.
   BaseKnotNode ndLive;
   ndLive.anchor = 0;   // P-BK-79: the preview has no base yet, so it asks for the LIVE row
   ndLive.kind = BK_NODE_NONE; ndLive.rungs = -1; ndLive.nodeTF = 0; ndLive.baseTF = 0;
   ndLive.side = 0; ndLive.barsAgo = 0; ndLive.rebreaks = 0;
   ndLive.returned = false; ndLive.crossed = false;
   ndLive.baseStep = 0.0; ndLive.breakStep = 0.0; ndLive.retStep = 0.0; ndLive.storyTF = 0;
   ndLive.state = 0; ndLive.depBars = 0; ndLive.depStep = 0.0;
   ndLive.revisits = 0; ndLive.lastSide = 0; ndLive.lifeBars = 0;
   ndLive.ctxAlign = 0; ndLive.sideLevel = 0;
   // ... and the TYPE half is read, off the span the note's class came from (P-BK-55).
   datetime ls1, ls2;                       // P-BK-84: the class' span — box ∪ base
   BaseKnotClassSpan(spLive, t1, te, ls1, ls2);
   int liveClass = BaseKnotBaseTFMin(spLive.still, ls1, ls2, top, bot);   // P-BK-84: the node's time, off the BASE'S OWN span (∪ the box')
   ndLive.height = top - bot;   // P-BK-75: «طول گره» is the box' own height
   ndLive.kind   = BaseKnotNodeKindOfLength(liveClass, ndLive.height, ndLive.anchor);   // P-BK-78/79: the SAME node's time and the SAME anchor the committed read uses
   BaseKnotAbilityGet(liveClass, ndLive.anchor, ndLive.abTrig, ndLive.abPat, ndLive.abStr);
   ndLive.nodeTF = liveClass;   // P-BK-78: the TF the type was read against, published for the hover
   ndLive.baseTF = liveClass;
   bool liveCorner = BaseKnotNoteAtCorner("");   // P-BK-58: while the user SIZES, the row is the answer
   BaseKnotWriteInfo(tag + "INFO", t1, te, top, bot, hPips, tpTip, side,
                     spLive, ndLive, tfMask, riskTag, tradeTipLive, liveCorner);   // P-BK-55: the type rides in `ndLive`
}
// INFO text is chart-anchored and only TF-gated (no pixel button —
// NOBKDEL 2026-09-06: the X delete badge is retired, boxes delete via
// select + Delete key). TF-hidden boxes stay hidden here even when
// their corner is on-screen.
void BaseKnotPlaceBadges(const string pfx, const datetime t1, const datetime t2,
                          const double top, const int tfMin, const long tfMask)
{
   bool tfVis = BaseKnotTFVisible(tfMin);
   string in = BaseKnotInfoName(pfx);
   long mask = (tfVis ? tfMask : OBJ_NO_PERIODS);
   ObjectSetInteger(0, in, OBJPROP_TIMEFRAMES, mask);   // AND the commit mask — never plain ALL
   // P-BK-92: the PLATE asks the same question through a different mechanism. The ink is
   // an OBJ_LABEL and honours the mask; the plate is an OBJ_RECTANGLE_LABEL and does not
   // (P-TH3-INFO-10), so a mask on it would leave the bar on a TF the note is hidden on —
   // the empty bar P-BK-86 exists to prevent. The plate's visibility is EXISTENCE.
   if(!tfVis) { BaseKnotNotePlateDrop(in); return; }
   // P-BK-86: this is the box-side home's POSITION owner — the note and its plate are screen
   // objects, so the projection (never a time/price write) is what keeps them on the box.
   BaseKnotNotePlateFollow(pfx, t1, top);
}
//+------------------------------------------------------------------+
//| P-BK-59 (2026-09-16) — THE CENTRE GRIP WEARS THE BORDER'S OWN INK.|
//|                                                                  |
//| The dot a user sees in the middle of a SELECTED box is NOT drawn  |
//| by this module: MetaTrader paints its own selection marker there  |
//| (a 2x2 WHITE square, plus one on each control corner — «the       |
//| object can be considered as selected if square markers … appear», |
//| MT4 Help), and it is white on every chart, which is why it        |
//| vanishes on a white background and why no EA call can recolour it.|
//| What CAN be done is cover it: the marker is painted WITH the object|
//| and therefore BELOW every rung above it — the amber edges already  |
//| clip the two corner markers exactly this way (visible in the user's|
//| own screenshot) — so a SCREEN square of our own, wearing the box'  |
//| border ink, hides it whole. A screen object (OBJ_RECTANGLE_LABEL)  |
//| is painted above the whole chart layer (P-UI-31's ladder), so the  |
//| cover cannot be defeated by a re-paint of the chart's own art.    |
//|                                                                  |
//| PLACEMENT IS THE MARKER'S OWN: the box' PIXEL centre, from the two|
//| corners the terminal marks, one read-only ChartTimePriceToXY pair |
//| per pass (never a guess at the chart's zoom, and the same pattern  |
//| BaseKnotGrabRole already uses). A conversion that fails (a box     |
//| scrolled out of the window by TIME) retires the grip: the terminal |
//| draws no marker for an object it cannot place either.              |
//|                                                                  |
//| IT MIRRORS THE TERMINAL, it never invents state: the grip exists   |
//| exactly while MT4 would draw that marker — the box is SELECTABLE   |
//| (unlocked) and SELECTED — so a chart nobody has clicked gains      |
//| nothing. The 500 ms pump is the keeper (selection is an event that |
//| pass already watches, P-BK-58), the drag's own child step carries  |
//| it while the hand moves the box, and the sizing PREVIEW stays out  |
//| of it: the rubber band draws no selectable object, so there is no  |
//| marker to cover until the box is committed.                        |
//+------------------------------------------------------------------+
// P-BK-59 size (2026-09-16, user: «این وسط باکس اون نقطه ضخیم بشه دیده نمیشه
// 5 باشه»): MT4's own marker is a 2x2 at the box' centre, and a 3x3 cover of it
// was still easy to MISS on a busy chart (the user's own screenshot: a navy box
// on a dark chart). 5 px is the user's number — it still reads as a dot on a
// 160x60 px box, and it leaves a clear margin around the marker it covers.
#define BK_DOT_SIZE 5   // px — the user's size (5), always ODD so it centres on one pixel
string BaseKnotDotName(const string pfx)   { return pfx + "DOT"; }
// The box' PIXEL centre — the point the terminal's marker is drawn on.
bool BaseKnotDotPixel(const datetime t1, const datetime t2, const double top, const double bot,
                      int &cx, int &cy)
{
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   if(!ChartTimePriceToXY(0, 0, t1, top, x1, y1)) return false;
   if(!ChartTimePriceToXY(0, 0, t2, bot, x2, y2)) return false;
   cx = (x1 + x2) / 2;
   cy = (y1 + y2) / 2;
   return true;
}
// Create + style once: the ink is written here and re-compared on later passes.
void BaseKnotDotCreate(const string name, const color clr, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_DOT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_DOT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);     // the frame …
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);   // … and the fill: ONE ink, the border's
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);   // the BOX is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_DOT);
   // BKDOT-OFF (P-BK-92): this mask is a no-op on a RECTANGLE_LABEL — a restore of the
   // dot must DELETE it on a hidden TF (BaseKnotNotePlateDrop's pattern), never mask it.
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);   // a box hidden on this TF carries no marker
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   "BK box centre grip (P-BK-59): the box' own border ink, drawn over MetaTrader's " +
                   "white selection marker — drag the BOX, never the grip");
}
// Keep or retire the grip of ONE box. Returns true when it wrote anything, so
// the caller can pay ONE repaint (MT4 repaints on every ObjectSet*). Steady state
// is reads only: zero writes while the box, its selection and the ink are still.
bool BaseKnotDotFollow(const string pfx, const datetime t1, const datetime t2,
                       const double top, const double bot, const bool selectable,
                       const bool selected, const color clr, const long tfMask)
{
   if(pfx == "") return false;
   string nm = BaseKnotDotName(pfx);
   if(!selectable || !selected)
   {
      if(ObjectFind(0, nm) >= 0)   // the box is locked, or nothing selected it — the terminal
      {                            // draws no marker here, so the grip goes with it
         ObjectDelete(0, nm);
         return true;
      }
      return false;
   }
   int cx = 0, cy = 0;
   if(!BaseKnotDotPixel(t1, t2, top, bot, cx, cy))   // off the window by TIME: no placeable dot
   {
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); return true; }
      return false;
   }
   if(ObjectFind(0, nm) < 0)
   {
      BaseKnotDotCreate(nm, clr, tfMask);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, cx - BK_DOT_SIZE / 2);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, cy - BK_DOT_SIZE / 2);
      return true;
   }
   bool wrote = false;
   if((color)ObjectGetInteger(0, nm, OBJPROP_BGCOLOR) != clr)   // the card's border colour moved
   {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, clr);
      wrote = true;
   }
   if((long)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != tfMask)
   {
      ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, tfMask);
      wrote = true;
   }
   int nx = cx - BK_DOT_SIZE / 2, ny = cy - BK_DOT_SIZE / 2;
   if((int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) != nx ||
      (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != ny)
   {
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, nx);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ny);
      wrote = true;
   }
   return wrote;
}
//+------------------------------------------------------------------+
//| P-BK-61 (2026-09-16) — THE GRIP HANDLES.                          |
//|                                                                  |
//| «یک کلیک چپ میکنم راحت هر طرف که بخوام میکشم اینطوری باشه» — the |
//| user's own TradingView screenshot: a selected rectangle wearing    |
//| handles. WHY THEY MUST BE OUR OWN OBJECTS: MetaTrader's own        |
//| rectangle has NO resize points at all (a native drag moves the     |
//| rectangle has NO resize points at all (a native drag moves the     |
//| whole rect), so resize was reachable only through the cursor       |
//| fallback P-BK-18/P-BK-19 retired (BKCURSOR-OFF) — i.e. today it is |
//| simply absent, which is exactly what the user reported.           |
//|                                                                  |
//| MT4 DRAGS OUR CHIP, AND WE WRITE THE BOX. Each handle is a 9x9    |
//| SCREEN square (OBJ_RECTANGLE_LABEL — the family the P-BK-59 grip  |
//| and every card already live in), filled with the box' own border  |
//| ink, sitting exactly ON the point it moves. `SELECTABLE` is the   |
//| whole feature: the terminal hands a press on a selectable screen  |
//| object to its OWN drag — the very thing P-BK-59 had to refuse     |
//| («drag the BOX, never the grip»). So the hand never touches the    |
//| box, the ONE writer of the gesture is this module, and the reading |
//| is the CHIP'S OWN PIXEL (OBJECT_DRAG carries no trusted cursor —   |
//| the box' own follow reads live anchors for the same reason).       |
//|                                                                  |
//| WHEN THEY EXIST: exactly while the box would show MT4's selection |
//| markers — unlocked AND selected (P-BK-59's rule) — PLUS the one    |
//| case that rule cannot see: MT4 single-selects, so grabbing a chip  |
//| takes the selection OFF the box. A chip of this family being        |
//| selected therefore keeps the whole family alive, and the release   |
//| hands the selection BACK to the box, so the next side is one grab  |
//| away — «یک کلیک چپ ... راحت هر طرف که بخوام» with no second click. |
//|                                                                  |
//| BKMIDGRIP-OFF (2026-09-16, user decision — «این وسط‌ها که کار    |
//| نمی‌کنن رو بردار کلا همون چهار گوشه کافیه») : the four MID-EDGE  |
//| chips are RETIRED — four corner handles remain. Restore by adding |
//| the four rows back to `BaseKnotGripSideAt` and raising           |
//| `BK_GRIP_COUNT`; the rest of the family (names, names→side, the   |
//| pixel projection, the keeper's sweep) is deliberately kept TOTAL   |
//| over the side bits, so those rows are the whole restore.           |
//|                                                                  |
//| COST: 4 objects, and steady state is READS ONLY (ink, mask and the|
//| two pixels are compared before every write — the BaseKnotDotFollow|
//| contract). The 500 ms pump is the keeper, the box' own Sync/CLICK  |
//| path is the instant one (a click shows the handles on that frame), |
//| and a box MOVE carries them in its own child step (BK_CH_GRIP).    |
//+------------------------------------------------------------------+
#define BK_GRIP_PX 9      // the chip a hand aims at; odd, so it centres on one pixel
#define BK_GRIP_COUNT 0   // BKGRIP-OFF (P-BK-71): NO live chips — a native MT4 box is moved
                          // by its own body drag, and the user retired every point family. The count
                          // lives HERE so a restore is one number, and every sweep asks it,
                          // never a literal.
// The four sides as BITS (`GS` = grip side) — the node's own bias ladder above
// spells its answers `BK_SIDE_*`, which is a different question entirely. A
// CORNER is two bits (the two sides it moves), so the family below stays total
// over the bit space even though only corners carry chips now.
#define BK_GS_T 1
#define BK_GS_B 2
#define BK_GS_L 4
#define BK_GS_R 8
// A chip's name tail is `G` + a tag (two letters for a corner, one for a retired
// edge chip). NO other child of this family starts with G (BOX, _T/_B/_L/_R,
// ENTRY, SL, TPn, INFO, TEXT, HINT, DOT), so a tag can never be read as another
// child's.
//--- The retired tails' ONE table lives ABOVE, beside BaseKnotRegister (MQL4 needs the
//--- define before its first reader in BaseKnotLazyInit) — see BKDOT-OFF/BKGRIP-OFF/
//--- BKPOINT-OFF (P-BK-71) there.
// BKMIDGRIP-OFF: four corners, `BK_GRIP_COUNT` of them. The single-bit rows are
// the retirement (kept in the comment so the restore is one edit):
//   if(i == 4) return BK_GS_T;   // the top edge's mid chip — retired
//   if(i == 5) return BK_GS_B;   // ...and its three siblings
//   if(i == 6) return BK_GS_L;
//   if(i == 7) return BK_GS_R;
int BaseKnotGripSideAt(const int i)
{
   // BKGRIP-OFF (P-BK-71): the four CORNER rows are retired with the chips — a plain
   // MT4 box has no resize points of its own to cover, and the user asked for no
   // points of ours either («یک باکس خود متاتریدر باشه»). The plan is empty
   // (`BK_GRIP_COUNT` is 0); the rows below ARE the restore path.
   // BKGRIP-OFF: if(i == 0) return (BK_GS_T | BK_GS_L);
   // BKGRIP-OFF: if(i == 1) return (BK_GS_T | BK_GS_R);
   // BKGRIP-OFF: if(i == 2) return (BK_GS_B | BK_GS_L);
   // BKGRIP-OFF: if(i == 3) return (BK_GS_B | BK_GS_R);
   return 0;
}
string BaseKnotGripName(const string pfx, const int side)
{
   if(side == (BK_GS_T | BK_GS_L)) return pfx + "GTL";
   if(side == (BK_GS_T | BK_GS_R)) return pfx + "GTR";
   if(side == (BK_GS_B | BK_GS_L)) return pfx + "GBL";
   if(side == (BK_GS_B | BK_GS_R)) return pfx + "GBR";
   // BKMIDGRIP-OFF: the four mid-edge tails. No live chip carries them, but the
   // function stays TOTAL over the bit space (and the one-time sweep below names
   // them to clean a chart an older build already wrote).
   if(side == BK_GS_T) return pfx + "GT";
   if(side == BK_GS_B) return pfx + "GB";
   if(side == BK_GS_L) return pfx + "GL";
   if(side == BK_GS_R) return pfx + "GR";
   return "";
}
// The name TAIL → side. 0 = not a handle of ours (every other child tail, the BOX
// itself and the four edge tails land here — which is what keeps the router honest).
// BKMIDGRIP-OFF: the single-letter tails stay MAPPED on purpose — a chart that the
// older build already wrote may still carry such a chip until the one-time sweep in
// `BaseKnotLazyInit` deletes it, and a chip the router cannot name would be a
// selectable square that drags nothing.
int BaseKnotGripSide(const string tag)
{
   if(tag == "GTL") return (BK_GS_T | BK_GS_L);
   if(tag == "GTR") return (BK_GS_T | BK_GS_R);
   if(tag == "GBL") return (BK_GS_B | BK_GS_L);
   if(tag == "GBR") return (BK_GS_B | BK_GS_R);
   if(tag == "GT") return BK_GS_T;
   if(tag == "GB") return BK_GS_B;
   if(tag == "GL") return BK_GS_L;
   if(tag == "GR") return BK_GS_R;
   return 0;
}
// The ONE point a chip stands on, in PIXELS: its corner (the mid-edge rows are
// BKMIDGRIP-OFF, kept TOTAL over the bit space for a restore). false = that chip
// has no place on this window (the box is out of it by TIME) and is retired ALONE
// — the terminal places no object it cannot place either (P-BK-59), and the chips
// that still have a place keep theirs.
bool BaseKnotGripPixel(const datetime tL, const double top, const datetime tR, const double bot,
                       const int side, int &cx, int &cy)
{
   long   half = (long)(tR - tL) / 2;
   datetime tMid = (datetime)((long)tL + half);
   double pMid = bot + (top - bot) / 2.0;
   if(side == (BK_GS_T | BK_GS_L)) return ChartTimePriceToXY(0, 0, tL, top, cx, cy);
   if(side == (BK_GS_T | BK_GS_R)) return ChartTimePriceToXY(0, 0, tR, top, cx, cy);
   if(side == (BK_GS_B | BK_GS_L)) return ChartTimePriceToXY(0, 0, tL, bot, cx, cy);
   if(side == (BK_GS_B | BK_GS_R)) return ChartTimePriceToXY(0, 0, tR, bot, cx, cy);
   if(side == BK_GS_T) return ChartTimePriceToXY(0, 0, tMid, top, cx, cy);
   if(side == BK_GS_B) return ChartTimePriceToXY(0, 0, tMid, bot, cx, cy);
   if(side == BK_GS_L) return ChartTimePriceToXY(0, 0, tL, pMid, cx, cy);
   if(side == BK_GS_R) return ChartTimePriceToXY(0, 0, tR, pMid, cx, cy);
   return false;
}
// Create + style once (the ink is written here and RE-COMPARED on every later pass
// — the BaseKnotDotCreate contract). The fill IS the box' border ink, so a handle
// reads as the shape's own mark, the way the user's own screenshot shows it.
void BaseKnotGripCreate(const string name, const color clr, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_GRIP_PX);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_GRIP_PX);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);     // the frame …
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);   // … and the fill: ONE ink
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);   // THIS is the drag (P-BK-61)
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_BOX_GRIP);
   // BKGRIP-OFF (P-BK-92): a no-op on a RECTANGLE_LABEL for the same reason as the dot —
   // a restore deletes chips on a hidden TF instead of masking them.
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   "Base box corner — drag it to resize the box (Shift held = magnet: the price " +
                   "snaps to the nearest candle OHLC under it)");
}
// Keep / place / retire the corner chips of ONE box (`BK_GRIP_COUNT` of them).
// true = it wrote something (the caller owes one repaint). `skip` = the side the
// hand is dragging right now (0 = none): THAT chip may never be written mid-gesture
// (P-BK-15 — the terminal cancels a native drag whose object is rewritten), which is
// also the reason the handles are their own objects instead of a resize on the box
// itself.
bool BaseKnotGripsFollow(const string id, const datetime tL, const double top, const datetime tR,
                         const double bot, const bool unlocked, const color clr, const long tfMask,
                         const int skip)
{
   if(BK_GRIP_COUNT <= 0) return false;   // BKGRIP-OFF (P-BK-71): the family is retired —
                                          // the keeper refuses to run, so a partial restore that
                                          // uncomments a call site without a plan still draws nothing
   if(StringLen(inpObjectPrefix) == 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return false;
   // SELECTION, MEASURED (never assumed): either the box', or — the case MT4's own
   // single-select creates — one of the chips'. ONE probe decides whether the sweep
   // below is worth its reads at all (the family is created and retired as a set).
   bool sel = (bool)ObjectGetInteger(0, box, OBJPROP_SELECTED);
   if(!sel && ObjectFind(0, BaseKnotGripName(pfx, (BK_GS_T | BK_GS_L))) >= 0)
   {
      for(int i = 0; i < BK_GRIP_COUNT && !sel; i++)
      {
         string cn = BaseKnotGripName(pfx, BaseKnotGripSideAt(i));
         if(cn != "" && ObjectFind(0, cn) >= 0 &&
            (bool)ObjectGetInteger(0, cn, OBJPROP_SELECTED)) sel = true;
      }
   }
   bool want = (unlocked && (sel || skip != 0));
   bool wrote = false;
   for(int i = 0; i < BK_GRIP_COUNT; i++)
   {
      int side = BaseKnotGripSideAt(i);
      if(side == 0 || side == skip) continue;   // the hand's own chip is never touched
      string nm = BaseKnotGripName(pfx, side);
      if(nm == "") continue;
      if(!want)
      {
         if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); wrote = true; }
         continue;
      }
      int cx = 0, cy = 0;
      if(!BaseKnotGripPixel(tL, top, tR, bot, side, cx, cy))
      {
         if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); wrote = true; }
         continue;
      }
      int nx = cx - BK_GRIP_PX / 2, ny = cy - BK_GRIP_PX / 2;
      if(ObjectFind(0, nm) < 0)
      {
         BaseKnotGripCreate(nm, clr, tfMask);
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, nx);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ny);
         wrote = true;
         continue;
      }
      if((color)ObjectGetInteger(0, nm, OBJPROP_BGCOLOR) != clr ||
         (color)ObjectGetInteger(0, nm, OBJPROP_COLOR) != clr)
      {
         ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, clr);
         wrote = true;
      }
      if((long)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != tfMask)
      {
         ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, tfMask);
         wrote = true;
      }
      if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTABLE))
      {
         // heal: a chip stored unselectable could never be dragged, i.e. the whole
         // feature would be silently absent (the P-BK-05/06 self-heal pattern).
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, true);
         wrote = true;
      }
      if((int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) != nx ||
         (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) != ny)
      {
         ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, nx);
         ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ny);
         wrote = true;
      }
   }
   return wrote;
}
// The release hands the SELECTION back to the box (the terminal gave it to the chip
// the hand grabbed): the keeper's rule above then keeps the eight handles on screen
// and the NEXT side is one grab away — the user's «یک کلیک چپ ... راحت هر طرف که
// بخوام میکشم» with no second click. Never re-selects a locked box (the keeper
// retires that family anyway) nor one the terminal no longer offers for selection.
void BaseKnotGripReselect(const string id)
{
   if(id == "") return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   if(!(bool)ObjectGetInteger(0, box, OBJPROP_SELECTABLE)) return;
   if(!(bool)ObjectGetInteger(0, box, OBJPROP_SELECTED))
      ObjectSetInteger(0, box, OBJPROP_SELECTED, true);
}
//+------------------------------------------------------------------+
//| P-BK-63 (2026-09-16) — A CLICK OUTSIDE THE BOX LETS IT GO.        |
//|                                                                  |
//| «زمانی که خارج از باکس کلیک شد سلکت بودنش غیرفعال بشه» — the box  |
//| KEEPS its selection where MT4's own rectangle does (BKSELECT-KEPT: |
//| a drag, a resize and a click ON the box never drop it, so the next |
//| gesture needs no re-click), and a click anywhere ELSE on the chart  |
//| lets it go — the same pair MT4's own rectangle answers.            |
//|                                                                  |
//| WHY THIS IS OURS AND NOT THE TERMINAL'S: the box IS selectable, so |
//| an empty-chart click usually deselects it natively. The exception  |
//| is the family we added in P-BK-61: the eight handles are           |
//| SELECTABLE objects too, and MT4 single-selects — so a resize      |
//| hands the selection to the CHIP, and its release hands it BACK to  |
//| the box (`BaseKnotGripReselect`). From the terminal's side the user  |
//| never selected anything but a screen square, so there is no        |
//| terminal-side event that owes the box a deselect; from the user's  |
//| side the box is plainly selected (it wears its handles). One        |
//| explicit owner makes the pair deterministic instead of             |
//| build-dependent — and it is the exact mirror of GripReselect above.|
//|                                                                  |
//| COST — the pass is gated three times BEFORE it reads anything, and |
//| a chart click is user-paced, never a tick:                             |
//|   * the tool must be IDLE (no draw session, no live drag) — a click|
//|     during a gesture is the gesture's own;                       |
//|   * the click must not be the UI's (P-UI-92: a card sits OVER the   |
//|     box, and the Base Box strip EDITS the selected box — dropping  |
//|     that selection on a card click would kill the thing the card is|
//|     editing);                                                      |
//|   * the point must be OUTSIDE every box (a click inside it, or on  |
//|     its drawn border within P-BK-24's own slop, is the box' press).|
//| Only then is the registry walked, and only for a box the terminal   |
//| really reports as SELECTED: no box on the chart, or none selected,  |
//| is one short loop of reads and ZERO writes (steady state).          |
//+------------------------------------------------------------------+
// The box the terminal reports as SELECTED right now — "" when none is.
// Deliberately NOT `BaseKnotSelectedId()`: that answers the NEWEST box when
// nothing is selected (the note's own question, P-BK-58), and a drop must never
// touch a box the user did not select.
string BaseKnotSelectedBoxId()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   BaseKnotLazyInit();
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      if((bool)ObjectGetInteger(0, box, OBJPROP_SELECTED)) return g_bkBoxes[i].id;
   }
   return "";
}
// P-BK-71: THE SELECTION WEARS NO MARK OF OURS. P-BK-59's centre grip and P-BK-61's
// handles USED to exist exactly while the box was selected, and their keepers
// re-measured that on the 500 ms pump — that is why a drop used to wipe them on the
// click's own frame. Both families are retired now (BKDOT-OFF/BKGRIP-OFF), so the wipe
// below answers the same call with the retired tails' table and nothing else.
// A locked box answers nothing here (the keeper retired its family already), and
// a name that was never created is one `ObjectFind` and no delete.
// P-BK-71: NO live point family is left to wipe on a deselect — the box wears the
// terminal's own markers and nothing of ours. What stays is the FAST cleanup of a chart
// an older build already drew: the retired tails' ONE table (BaseKnotRetiredPointName),
// walked here on the click's own frame so no ghost square waits for the next re-attach.
// A name that was never created is one `ObjectFind` and no delete.
bool BaseKnotSelectionMarkersWipe(const string id)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   bool wrote = false;
   // BKDOT-OFF (P-BK-71): the centre cover is one of the thirteen tails the table
   // names ("DOT"), so it is swept by the same walk — BaseKnotDotName stays the name's
   // ONE owner for the restore.
   // BKGRIP-OFF (P-BK-71): the family plans no live chip (`BK_GRIP_COUNT` is 0), so this
   // walks the RETIRED tails from their ONE table instead — every square that could still
   // sit on a chart an older build wrote and drag nothing.
   for(int i = 0; i < BK_RETIRED_POINTS; i++)
   {
      string tail = BaseKnotRetiredPointName(i);
      if(tail == "") continue;
      string nm = pfx + tail;
      if(ObjectFind(0, nm) >= 0) { ObjectDelete(0, nm); wrote = true; }
   }
   return wrote;
}
// THE entry, called from `BaseKnotOnChartEvent`'s CLICK branch (id 4 — the event
// MT4 sends for a click on the CHART; a click on a SELECTABLE object is
// CHARTEVENT_OBJECT_CLICK, id 1, and the branches above own it). true = it
// dropped a selection, so the caller owes one repaint.
bool BaseKnotDeselectOnChartClick(const int mx, const int my)
{
   if(g_bkState != BK_IDLE || s_bkDragId != "") return false;   // a gesture owns the mouse
   if(!UILeftButtonUp()) return false;   // the ONE button owner (P-UI-73): a press echo is
                                         // not a click, and the "outside" test below is
                                         // measured against a live native drag otherwise
   if(UIPointerOverSurface(mx, my)) return false;               // P-UI-92: the UI is over the box
   int sw = 0; datetime ct = 0; double cp = 0;
   if(ChartXYToTimePrice(0, mx, my, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
   {
      if(BaseKnotBoxAt(ct, cp) != "") return false;     // inside a box: its own press
      if(BaseKnotBoxAtPx(mx, my) != "") return false;   // ...or on its drawn border (P-BK-24)
   }
   string sel = BaseKnotSelectedBoxId();
   if(sel == "") return false;   // nothing of ours is selected — the common case
   BaseKnotDropSelection(sel);   // P-BK-26's ONE owner: read-guarded, one write
   BaseKnotSelectionMarkersWipe(sel);
   return true;
}
// (Re)build every child of one box from its live anchors. Direction is read
// from the registry — NEVER recomputed here (P-BK-13: the pump /
// drag-release refresh it via BaseKnotRefreshDirection BEFORE calling Sync,
// so Sync itself stays flicker-free).
void BaseKnotSync(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   int dir = g_bkBoxes[k].dir;
   int tfMin = g_bkBoxes[k].tfMin;
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);   // legacy registry rows
   long tfMask = BaseKnotTFMask(tfMin);
   ObjectSetInteger(0, box, OBJPROP_TIMEFRAMES, tfMask);
   BaseKnotStyleBox(box);   // fill layer + drag handle — the VISIBLE border is the 4 edges below
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, !g_bkBoxes[k].locked);   // lock heal: handle follows the registry
   // P-BK-46/50: the trade's own numbers are computed BELOW, right after the node read
   // — the knot's TYPE decides which edge the entry sits on and its CLASS (its own
   // TF) decides what R is measured in (and which TF's plan the targets come from),
   // and both arrive from the walk and the read.
   double entry = 0, sl = 0;
   int dg = GetCachedDigits();
   // P-BK-30: ONE walk per Sync, shared by the box tooltip, the four edges and
   // the note — the count used to be computed twice per Sync (the tooltip and the
   // INFO label), so a box that is repainted (drag release, 500 ms pump, TF
   // switch) paid the bar walk twice over. With the body rule the walk is also
   // the same number everywhere on the box, so the note and the hover can never
   // disagree about how many candles the base holds.
   // P-BK-41: ONE SPAN for everything — the base's own story (its first candle to the
   // candle that closed outside the band). The number, the class, the node's story and
   // the note's own badge all read THIS record, so no two of them can disagree about
   // where the base started, where it ended, or which TF it belongs to.
   BaseKnotSpan sp;
   int bars = BaseKnotBarCount(t1, t2, top, bot, sp);
   int still = sp.still;
   // P-BK-36/38: the CLASS comes first now, because it is also what the node's
   // story is read on — one box, one TF, one story, whichever chart opens it. Both
   // numbers are published on the registry, so the pump's change check reads the
   // SAME story instead of a second one of its own. P-BK-40: the class is read from
   // the candles that STOOD STILL (a base's own length), while the note's number
   // stays the base's LIFE.
   // P-BK-75: anchored on the TF the BOX is seen on, so a TF switch cannot move the
   // class (and with it the story, the entry and the plan legs that ride it).
   // P-BK-84: AND THE SPAN IS THE BASE'S OWN — the drawn rectangle is a POINTER, not the
   // measurement (the user draws with the measuring tool, and P-BK-44 already ruled that the
   // run is walked on both sides of the box' right edge, so the base is routinely WIDER than
   // the box). The box' two anchors stay as the FLOOR, so a box dragged wide cannot shrink
   // the reading either. `t1..t2` below are the box' own; the union is what the class reads.
   datetime bs1, bs2;
   BaseKnotClassSpan(sp, t1, t2, bs1, bs2);
   int baseTF = BaseKnotBaseTFMin(still, bs1, bs2, top, bot);   // P-BK-84: the node's time, from the base's own span
   g_bkBoxes[k].baseTFMin = baseTF;
   g_bkBoxes[k].storyT = sp.tLast;   // P-BK-41: the same story the pump re-reads
   g_bkBoxes[k].exitT  = sp.tExit;   // P-BK-81: the base's OWN exit candle — the ONE candle the
                                     //          direction is read from, published so the pump's
                                     //          own read cannot land on a different one
   // P-BK-29/47: ONE node read per Sync — the note's suffix, its hover sentence, the
   // box/edge tooltip and the pump's shadow all read the SAME record, so the type (the
   // LENGTH) and the side (the break's story) can never disagree with themselves between
   // two objects on one box.
   BaseKnotNode nd;
   // P-BK-41: the story starts where the BASE stopped moving (its last stand-still
   // candle), not at the box' right edge — a box dragged past its own break no longer
   // pushes the read forward and hides the break that made the knot.
   // P-BK-47/78: and the LENGTH is read on the NODE'S OWN TIME (P-BK-77's answer — the rung
   // whose own three candles stood still), while `baseTF` IS that answer: those two were
   // the whole input of the type, so no TH, no chart TF and no drag can move it. The box'
   // commit TF no longer enters here at all: the user draws with the measuring tool.
   // P-BK-81: and the DIRECTION is read at the base's OWN EXIT CANDLE (`sp.tExit`) — the same
   // candle the note's number is counted to, so the two can never describe different bars.
   BaseKnotNodeRead((sp.tLast > 0 ? sp.tLast : t2), top, bot, baseTF,
                    sp.tExit, g_bkBoxes[k].storyT, nd);   // P-BK-79: the SAME anchor the pump keyed its rows on
   g_bkBoxes[k].nodeKind = nd.kind;   // published → the pump's gate compares against this
   // P-BK-46 — THE BREAK'S STORY NAMES THE SIDE (BaseKnotNodeDir), and the answer
   // is PUBLISHED (registry + chart GV) because the pump's price-follow must not
   // flip a knot whose trade is already named by what price DID.
   int ndDir = BaseKnotNodeDir(nd);
   g_bkBoxes[k].nodeSide = ndDir;     // P-BK-47: published for the same reason (the follow reads it)
   if(ndDir != 0 && ndDir != dir)
   {
      dir = ndDir;
      g_bkBoxes[k].dir = dir;
      GlobalVariableSet(BaseKnotGV(id), (double)dir);
   }
   // P-BK-46/50/51 — R IS EngSL OF THE STOP'S OWN TF (P-BK-83: the TYPE'S own time — the rung
   // the node's length matched), and the box' own height only while the pump has no EngSL for
   // that TF. P-BK-51's geometry: the ENTRY waits ONE EngSL (FTR) or ONE HuntSL (ETR/CTR/OTR)
   // INSIDE the edge the side comes in on, the STOP is ONE EngSL behind the entry, and the
   // TARGETS are the plan's own TP1..TP3 of the node's own TF — every one of them SAYS which
   // measure / which TF / which plan it rode.
   // P-BK-51/83: WHICH TF EACH LEG IS READ ON — the ENTRY on the node's own class, the STOP on
   // the TYPE'S own time (BaseKnotEntryTFMin / BaseKnotMeasureTFMin are the TWO owners; the
   // geometry below asks the same pair, so the drawn legs and the texts cannot part).
   // P-BK-79: AND EVERY ONE OF THEM IS READ AT THE BOX' OWN ANCHOR (`nd.anchor` — the bar its
   // story ended on), the very key the pump pushed its rows with, so the drawn legs and the
   // printed pips come off ONE row and a box whose base ended on an older bar keeps the numbers
   // that bar's market gave it instead of today's drifted TH.
   int    mTF       = BaseKnotMeasureTFMin(nd.kind, baseTF);   // P-BK-83: the STOP's own time
   if(mTF <= 0) mTF = (baseTF > 0 ? baseTF : Period());
   int    eTF       = BaseKnotEntryTFMin(nd.kind, baseTF);     // ... and the ENTRY's own time
   string riskTag   = BaseKnotRiskTag(mTF, baseTF, top, bot, nd.anchor);   // P-BK-52: named with the number the pick drew
   double hPips  = BaseKnotRiskPips(mTF, top, bot, nd.anchor);
   bool   offIsHunt = BaseKnotOffsetIsHunt(nd.kind, eTF, nd.anchor);   // P-BK-51/83: which measure the TYPE asks for, read on the ENTRY's own time
    BaseKnotCalcLevels(top, bot, dir, nd.kind, baseTF, entry, sl, nd.anchor);
    // BKE2-OFF (2026-09-28): 2nd entry retired — purge leftovers from older builds.
    ObjectDelete(0, BaseKnotEntry2Name(pfx));
    ObjectDelete(0, BaseKnotSL2Name(pfx));
    for(int e2p = 1; e2p <= BK_TP_PLAN_MAX; e2p++) ObjectDelete(0, BaseKnotTPTick2Name(pfx, e2p));
    string entryLine2 = "";   // BKE2-OFF: always "" (keeps the tooltip signature compiling)
   // BKTAGTP-OFF (P-BK-54): string tpTag = BaseKnotTPPlanTag(baseTF);   // the retired note field
    string tpTip = BaseKnotTPPlanTip(baseTF, entry, dir, hPips, nd.anchor);   // P-BK-54: the hover keeps every leg
    string side = (dir >= 0 ? "BUY" : "SELL");
   // P-BK-51: the trade's own two sentences, ready-built — how deep the entry waits and
   // what sized the stop. The box hover, the note's hover and the two rays read THESE.
   string edgeName  = (dir >= 0 ? "top" : "bottom");
   string entryLine = BaseKnotEntryLine(nd.kind, eTF, offIsHunt, dir, top, bot, nd.anchor);
   string stopWhy   = " (ONE " + riskTag + " behind the entry, INSIDE the box' " + edgeName + " edge" +
                      BaseKnotStopWhy(mTF, top, bot, nd.anchor) + ")";
   string tradeTip  = "risk " + DoubleToString(hPips, 1) + " pips (" + riskTag + ") = the stop" + stopWhy + entryLine + entryLine2;
   string tip = BaseKnotBoxTooltip(id, t1, t2, top, bot, side, hPips, tpTip, sp,
                                   riskTag, BaseKnotNodeLine(nd, top, bot), entryLine, entryLine2);
   ObjectSetString(0, box, OBJPROP_TOOLTIP, tip);
   // BKEDGE-OFF (P-BK-74): the visible border is the BOX' OWN outline now — the
   // rectangle wears the border ink in BaseKnotStyleBox, so there is nothing to
   // draw beside it. The four trend-line children are retired in place: the
   // function below stays compiled and this one call is the whole restore.
   // BaseKnotDrawEdges(pfx, t1, p1, t2, p2,
   //                   GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth, tip, tfMask);
   BaseKnotPlaceText(pfx, t1, t2, top, bot, tfMask, tip);   // existing user text follows the box (never resurrected)
   datetime tFar = t2 + (t2 > t1 ? (t2 - t1) : PeriodSeconds());
   datetime tps, tpe;
   BaseKnotTPTickSpan(t1, t2, tps, tpe);   // TP tick rides the right edge, not the box
   // P-BK-46/50: the entry line names the edge the side came in on AND the one-R
   // offset (the user's own call), the stop names the edge it IS — the knot's own
   // trade, spelled out.
   // P-BK-47: this edge is the SIDE's call (the break's story, or the live price when the
   // story names none) — the TYPE is a length and never claimed an edge. The tooltip says
   // which of the two spoke, the same way the entry's measure names where its depth came from.
   // P-BK-51: and HOW DEEP the entry waits INSIDE that edge (EngSL for FTR, HuntSL for the
   // longer nodes) — the box hover's own sentence, spelled once by BaseKnotEntryLine.
   // P-BK-83: on the ENTRY's own time (`eTF` — the node's class), never the stop's rung.
   string entryWhy = " (ONE " + BaseKnotEntryOffsetTag(offIsHunt) + " INSIDE the box' " + edgeName + " edge — " +
                     BaseKnotEntryWhy(nd.kind, eTF, offIsHunt, top, bot, nd.anchor) + "; the side is " +
                     (nd.side != 0 ? "the base's own exit candle" : "the live price") + ")";
   BaseKnotMakeRay(BaseKnotEntryName(pfx), t2, tFar, entry, g_bkEntryColor, STYLE_SOLID, BK_LEVEL_WIDTH,
                   "BK " + side + " Entry: " + DoubleToString(entry, dg) + entryWhy, tfMask, true);
   BaseKnotMakeRay(BaseKnotSLName(pfx), t2, tFar, sl, g_bkStopColor, STYLE_DASH, BK_LEVEL_WIDTH,
                   "BK " + side + " Stop: " + DoubleToString(sl, dg) + ", INSIDE the box' " + edgeName +
                   " edge, ONE " + riskTag + " behind the entry" + BaseKnotStopWhy(mTF, top, bot, nd.anchor) + ")", tfMask, true);
    // BKE2-OFF: no 2nd-entry rays (purged above).
    // P-BK-50: the TARGETS are the plan's own legs (TP1..TP3) — one SHORT, THICK tick
   // each at the chart's right edge, never a ray and never box-wide (the user's own
   // 2026-09-08 decision, now for three of them). A leg the plan has not pushed is
   // NOT drawn: absence is never turned into a level.
   for(int tk = 1; tk <= BaseKnotTPCount(); tk++)
   {
      double lv = BaseKnotTPLevel(entry, dir, baseTF, tk, nd.anchor);
      if(lv <= 0.0) continue;
      double tpP = BaseKnotPlanTPPips(baseTF, tk, nd.anchor);
      BaseKnotMakeRay(BaseKnotTPTickName(pfx, tk), tps, tpe, lv, g_bkTargetColor,
                      BK_TP_TICK_STYLE, BK_TP_TICK_WIDTH,
                      "BK " + side + " TP" + IntegerToString(tk) + ": " + DoubleToString(lv, dg) + " (+" +
                      DoubleToString(tpP, 0) + " pips from the entry" +
                      (hPips > 0.0 ? " = " + DoubleToString(tpP + hPips, 0) + " from the stop, " +
                                     DoubleToString(tpP / hPips, 1) + "R" : "") +
                      " — the plan's own TP" + IntegerToString(tk) + " of " + BaseKnotTFName(baseTF) + ")", tfMask, false);
   }
    ObjectDelete(0, BaseKnotTPName(pfx));   // BKTPR-OFF: purge a pre-P-BK-50 build's single tick
   ObjectDelete(0, BaseKnotDelName(pfx));   // NOBKDEL 2026-09-06: X badge retired — purge pre-retire badges
   ObjectDelete(0, BaseKnotBuyName(pfx));   // NOBUYSELL: purge pre-2026-09-06 direction badges
   // P-BK-58: WHERE this box' note is drawn is ONE question, asked once (BaseKnotNoteAtCorner):
   // the family's row for the selected/newest box in the corner mode, the box' own corner
   // otherwise. A box the row does not answer keeps NO box-side note in that mode — the note
   // exists in exactly one place at a time.
   bool atCorner = BaseKnotNoteAtCorner(id);
   if(atCorner || BaseKnotInfoVisible(id))
   {
      BaseKnotWriteInfo(BaseKnotInfoName(pfx), t1, t2, top, bot, hPips, tpTip, side,
                        sp, nd, tfMask, riskTag, tradeTip, atCorner);
      if(!atCorner) BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin, tfMask);
   }
   else
      BaseKnotInfoWipe(pfx);   // the other home owns it (P-BK-58), or the grace is over — P-BK-86: the PAIR goes, never half of it
   // BKDOT-OFF (P-BK-71): the centre cover is retired — a native box wears the
   // terminal's own markers and no cover of ours.
   // BKDOT-OFF: BaseKnotDotFollow(pfx, t1, t2, top, bot, !g_bkBoxes[k].locked,
   // BKDOT-OFF:                      (bool)ObjectGetInteger(0, box, OBJPROP_SELECTED),
   // BKDOT-OFF:                      GetBoxBorderRenderColor(), tfMask);
   // BKGRIP-OFF (P-BK-71): and the corner chips are retired — the INSTANT half of
   // their keeper goes with them.
   // BKGRIP-OFF: if(BaseKnotGripsFollow(id, t1, top, t2, bot, !g_bkBoxes[k].locked,
   // BKGRIP-OFF:                           GetBoxBorderRenderColor(), tfMask, s_bkGripLive))
   // BKGRIP-OFF:    ChartRedraw();
}
// Shared drag-paint budget: position writes are cheap, FULL repaints are not
// (a heavy chart costs 100ms+ per repaint — an unthrottled ChartRedraw per
// drag event turns dragging into a slideshow that only settles on release).
// Every drag painter (event sync, cursor follow, strip follow) draws through
// here (30ms); the release path repaints unconditionally (final frame).
void BaseKnotDragPaint()
{
   uint now = GetTickCount();
   if(now - s_bkDragPaintMs < 30) return;
   s_bkDragPaintMs = now;
   ChartRedraw();
}
// Lean child mover — ObjectMove ONLY (no style/color/create/delete syscalls)
// for per-step drag following. Same geometry as Sync (levels via
// BaseKnotCalcLevels, text via BaseKnotTextPlace), so the authoritative
// release Sync lands on identical pixels. Missing children are skipped (the
// release Sync rebuilds them) — never resurrect mid-drag.
// P-PERF-42: the ONE existence probe — reads only, 15 names (P-BK-61 added the handle
// set, which is one name: the eight chips live and die together), once per gesture.
int BaseKnotChildMaskBuild(const string pfx)
{
   int m = 0;
   // BKEDGE-OFF (P-BK-74): the border is the box' own outline, so the four edge
   // names are gone and their four probes could only ever answer "no" — the
   // gesture's ONE existence sweep is that much cheaper.
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_T) >= 0)            m |= BK_CH_EDGE_T;
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_B) >= 0)            m |= BK_CH_EDGE_B;
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_L) >= 0)            m |= BK_CH_EDGE_L;
   // BKEDGE-OFF: if(ObjectFind(0, pfx + BK_EDGE_R) >= 0)            m |= BK_CH_EDGE_R;
    if(ObjectFind(0, BaseKnotEntryName(pfx)) >= 0)     m |= BK_CH_ENTRY;
    if(ObjectFind(0, BaseKnotSLName(pfx)) >= 0)        m |= BK_CH_SL;
    // BKE2-OFF: the 2nd set is retired — no probes (Sync purges leftovers).
    // BKE2-OFF: if(ObjectFind(0, BaseKnotEntry2Name(pfx)) >= 0)    m |= BK_CH_ENTRY2;
    // BKE2-OFF: if(ObjectFind(0, BaseKnotSL2Name(pfx)) >= 0)       m |= BK_CH_SL2;
    // BKE2-OFF: if(ObjectFind(0, BaseKnotTPTick2Name(pfx, 1)) >= 0) m |= BK_CH_E2TP1;
    // BKE2-OFF: if(ObjectFind(0, BaseKnotTPTick2Name(pfx, 2)) >= 0) m |= BK_CH_E2TP2;
    // BKE2-OFF: if(ObjectFind(0, BaseKnotTPTick2Name(pfx, 3)) >= 0) m |= BK_CH_E2TP3;
   if(ObjectFind(0, BaseKnotTPTickName(pfx, 1)) >= 0) m |= BK_CH_TP;    // P-BK-50: bit 6 = TP1
   if(ObjectFind(0, BaseKnotTPTickName(pfx, 2)) >= 0) m |= BK_CH_TP2;   //           TP2/TP3 take the
   if(ObjectFind(0, BaseKnotTPTickName(pfx, 3)) >= 0) m |= BK_CH_TP3;   //           next free bits
   if(ObjectFind(0, BaseKnotInfoName(pfx)) >= 0)      m |= BK_CH_INFO;
   if(ObjectFind(0, BaseKnotTextName(pfx)) >= 0)      m |= BK_CH_TEXT;
   // BKDOT-OFF (P-BK-71): the centre cover is retired — nothing probes it any more.
   // BKDOT-OFF: if(ObjectFind(0, BaseKnotDotName(pfx)) >= 0)       m |= BK_CH_DOT;   // P-BK-59: the centre grip
   // BKGRIP-OFF (P-BK-71): same for the corner chips (the plan is empty, so a probe
   // could only ever answer "no").
   // BKGRIP-OFF: if(ObjectFind(0, BaseKnotGripName(pfx, (BK_GS_T | BK_GS_L))) >= 0) m |= BK_CH_GRIP;   // P-BK-61: the handle set (one probe)
   return m;
}
// ObjectMove ONLY (no style/color/create/delete syscalls) for per-step drag
// following. P-PERF-42: no `ObjectFind` here any more — the caller only passes
// names its gesture mask proved exist (a missing object would have made
// ObjectMove a silent no-op, i.e. the probe only paid terminal calls).
void BaseKnotMoveOne(const string nm, const datetime tA, const double pA,
                     const datetime tB, const double pB)
{
   ObjectMove(0, nm, 0, tA, pA);
   ObjectMove(0, nm, 1, tB, pB);
}
void BaseKnotMoveChildren(const string id, datetime t1, const double p1,
                          datetime t2, const double p2)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   if(ObjectFind(0, BaseKnotBoxName(pfx)) < 0) return;
   // P-PERF-42: built on the gesture's FIRST move (a tap never builds it), and
   // rebuilt whenever the id it was built for is not the box being moved.
   if(s_bkChildMaskId != id)
   {
      s_bkChildMaskId = id;
      s_bkChildMask = BaseKnotChildMaskBuild(pfx);
   }
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   double entry = 0, sl = 0;
   // P-BK-46/50/51: the SAME geometry the release Sync lands on — the node's TYPE (published
   // on the registry, so a drag never moves the levels to another measure mid-gesture) and
   // the TF its class was read on, so the entry / stop / targets never jump during a drag.
   // P-BK-79: and the SAME ANCHOR — the box' own `storyT`, the key the pump pushed its rows
   // with, so a drag follows the levels the release Sync will land on and never a live row
   // the box does not draw with.
   datetime an = g_bkBoxes[k].storyT;
    BaseKnotCalcLevels(top, bot, g_bkBoxes[k].dir, g_bkBoxes[k].nodeKind, g_bkBoxes[k].baseTFMin, entry, sl, an);
    // BKE2-OFF: no 2nd set on the drag (Sync purges it at release).
    datetime tFar = t2 + (t2 > t1 ? (t2 - t1) : PeriodSeconds());
   datetime tps, tpe;
   BaseKnotTPTickSpan(t1, t2, tps, tpe);   // TP tick rides the right edge, not the box
   // BKEDGE-OFF (P-BK-74): the border IS the box, so a body drag carries no edge
   // — the terminal moves the rectangle and its outline with it, natively and for
   // free. The four lines below are the whole restore (with the four probes above
   // and the Sync call site).
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_T) != 0) BaseKnotMoveOne(pfx + BK_EDGE_T, t1, top, t2, top);
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_B) != 0) BaseKnotMoveOne(pfx + BK_EDGE_B, t1, bot, t2, bot);
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_L) != 0) BaseKnotMoveOne(pfx + BK_EDGE_L, t1, bot, t1, top);
   // BKEDGE-OFF: if((s_bkChildMask & BK_CH_EDGE_R) != 0) BaseKnotMoveOne(pfx + BK_EDGE_R, t2, bot, t2, top);
    if((s_bkChildMask & BK_CH_ENTRY) != 0)  BaseKnotMoveOne(BaseKnotEntryName(pfx), t2, entry, tFar, entry);
    if((s_bkChildMask & BK_CH_SL) != 0)     BaseKnotMoveOne(BaseKnotSLName(pfx), t2, sl, tFar, sl);
    // BKE2-OFF: the 2nd set is never carried mid-drag.
   // P-BK-50: one tick per DRAWN plan leg — the mask bit the gesture's probe found
   // decides, so a leg that was not there at the press is never created mid-drag.
   for(int tk = 1; tk <= BK_TP_PLAN_MAX; tk++)
   {
      int bit = (tk == 1 ? BK_CH_TP : (tk == 2 ? BK_CH_TP2 : BK_CH_TP3));
      if((s_bkChildMask & bit) == 0) continue;
      double lv = BaseKnotTPLevel(entry, g_bkBoxes[k].dir, g_bkBoxes[k].baseTFMin, tk, an);
      if(lv <= 0.0) continue;
      BaseKnotMoveOne(BaseKnotTPTickName(pfx, tk), tps, lv, tpe, lv);
   }
    // BKE2-OFF: set 2 retired — no drag loop.
    // BKDOT-OFF (P-BK-71): the centre cover is retired, so the drag carries nothing here.
   // BKDOT-OFF: if((s_bkChildMask & BK_CH_DOT) != 0)
   // BKDOT-OFF: {
   // BKDOT-OFF:    int dcx = 0, dcy = 0;
   // BKDOT-OFF:    if(BaseKnotDotPixel(t1, t2, top, bot, dcx, dcy))
   // BKDOT-OFF:    {
   // BKDOT-OFF:       string dn = BaseKnotDotName(pfx);
   // BKDOT-OFF:       ObjectSetInteger(0, dn, OBJPROP_XDISTANCE, dcx - BK_DOT_SIZE / 2);
   // BKDOT-OFF:       ObjectSetInteger(0, dn, OBJPROP_YDISTANCE, dcy - BK_DOT_SIZE / 2);
   // BKDOT-OFF:    }
   // BKDOT-OFF: }
   if((s_bkChildMask & BK_CH_INFO) != 0)   BaseKnotNotePlateFollow(pfx, t1, top);   // P-BK-86: a screen pair is moved by its projection, never by ObjectMove
   if((s_bkChildMask & BK_CH_TEXT) != 0)
   {
      string tn = BaseKnotTextName(pfx);
      datetime tx; double px; int anchor;
      BaseKnotTextPlace(t1, t2, top, bot, tx, px, anchor);
      ObjectMove(0, tn, 0, tx, px);
   }
   // BKGRIP-OFF (P-BK-71): the corner chips are retired, so the move step carries none —
   // a native box drag moves the whole box and every live child above follows it.
   // BKGRIP-OFF: if((s_bkChildMask & BK_CH_GRIP) != 0)
   // BKGRIP-OFF: {
   // BKGRIP-OFF:    int gTf = g_bkBoxes[k].tfMin;
   // BKGRIP-OFF:    if(gTf <= 0) gTf = BaseKnotIdTF(id);
   // BKGRIP-OFF:    BaseKnotGripsFollow(id, t1, top, t2, bot, !g_bkBoxes[k].locked,
   // BKGRIP-OFF:                        GetBoxBorderRenderColor(), BaseKnotTFMask(gTf), s_bkGripLive);
   // BKGRIP-OFF: }
}
#endif // BASE_KNOT_PLAN_MQH
