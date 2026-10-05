// Toolbar_B.mqh - DrawToolbar.mqh split 2026-09-29: exact lines 1200-2053, byte-identical, zero renames.
#ifndef TOOLBAR_B_MQH
#define TOOLBAR_B_MQH

//--- write ONE slot onto an object, and LEARN it into the kind's memory. The
//--- two halves are one call on purpose: an edit the user made is an edit the
//--- next drawing of that kind must wear, and splitting them would let one of
//--- the two drift.
//--- the OPACITY row's write: one tag, and the object re-wears the blend of the
//--- colour it already holds. Nothing else is touched. (Defined here, after the
//--- reader it asks — a bare `f();` above its definition is an IMPORT to MQL4.)
//--- P-DRAW-48 (2026-09-27) — AND IT WRITES THE COLOUR IT READ, NEVER A NEW ONE.
//--- Reported: «شفافیت هر رنگی رو تغییر میدم فقط سیاه میشه». The bar re-reads the
//--- object's colour EVERY frame it moves, so a read that cannot answer (an
//--- unparseable `[CL…]`, or a colour MT4 answers as `clrNONE`) fed the blend its
//--- own last blend: ~20 frames at a 30 ms cadence is `0.69^20`, i.e. any colour
//--- reached black in under a second and the black was then STORED as the pure.
//--- So: the tag is written only from a colour that IS one, the tag form is the six
//--- digits the reader parses, and a drawing with no colour keeps the pixels it has
//--- (the `[OPnn]` value is still recorded, it just has nothing to blend).
//--- P-DRAW-64: AND IT IS ROLE-AWARE — one bar, two tags. `slot` names the colour
//--- the bar is tuning: the BORDER (`[OP…]`, the object's own pixels) or the
//--- INTERIOR (`[FT…]`, the child's, or the level family's levels). The strip hands
//--- it the cell whose board is open, so the bar and the colour it sits under are
//--- always the same role.
void DrawSlotOpacitySet(const string name, const int op, const int slot)
{
   if(name == "" || ObjectFind(0, name) < 0) return;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || k == DK_TEXT) return;
   bool inner = (slot == DRAW_SLOT_FILLCLR);
   if(inner && !DrawSlotAvailable(k, DRAW_SLOT_FILLCLR)) return;
   int v = op;
   if(v < DRAW_OP_MIN) v = DRAW_OP_MIN;
   if(v > 100) v = 100;
   //--- P-UI-137 (2026-10-02, user: "the transparency only applies to ONE of its
   //--- lines") — THE OPACITY IS THE PATH'S, NOT A SEGMENT'S. This writer aimed at
   //--- ONE name, so the fade landed on the segment under the hand and the polyline
   //--- came out half-faded (the measured screenshot: one pale leg among solid ones).
   //--- And the `[OP…]`/`[CL…]` tags it writes are PAINTED along a trend line, so the
   //--- path's numbers live in its own store and every sibling is re-inked in ONE
   //--- pass through the path's single writer. Cost: one blend + n writes, n = the
   //--- path's segment count, on the slider's own step. No other drawing is touched.
   if(DrawIsPathSeg(name))
   {
      string pid = "";
      if(!PathIdOfName(name, pid)) return;
      if(inner) return;              // a polyline has no interior: the Fill role is N/A
      color pp = clrNONE; int pv = 100;
      PathInkGet(pid, pp, pv);
      PathInkApply(pid, pp, v);
      return;
   }
   color pure = clrNONE;
   bool havePure = inner ? DrawSlotFillPure(name, pure) : DrawSlotColorPure(name, pure);
   if(!havePure)
   {
      pure = (color)(int)DrawSlotRead(name, inner ? DRAW_SLOT_FILLCLR : DRAW_SLOT_COLOR);
      havePure = ((int)pure >= 0);
   }
   string d = ObjectGetString(0, name, OBJPROP_TEXT);
   d = DrawDescTag(d, inner ? "[FT" : "[OP", IntegerToString(v));
   //--- the border's `[CL…]` is rewritten from the colour it READ (the healer); the
   //--- interior's is NOT: an interior with no colour of its own keeps following the
   //--- border, which is the state a pre-split drawing is in.
   if(!inner && havePure) d = DrawDescTag(d, "[CL", DrawDescColorHex(pure));
   if(d != ObjectGetString(0, name, OBJPROP_TEXT))
      ObjectSetString(0, name, OBJPROP_TEXT, d);
   if(!havePure) return;   // no colour on the drawing: nothing to blend, nothing written
   if(inner)
   {
      if(DrawKindHasFillBody(k)) FillChildSync(name);
      else DrawLevelsSetColor(name, DrawSlotRenderFillColor(name, pure));
      return;
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, DrawSlotRenderColor(name, pure));
   if(DrawKindHasLevels(k))
   {
      color ip;
      DrawLevelsSetColor(name, DrawSlotFillPure(name, ip) ? DrawSlotRenderFillColor(name, ip)
                                                          : DrawSlotRenderColor(name, pure));
   }
}
bool DrawSlotWrite(const string name, const int slot, const double v)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;
   switch(slot)
   {
      case DRAW_SLOT_COLOR:
      {
         color c = (color)(int)MathRound(v);
         // P-HR-04: plain ink on the ray — no `[CL` desc (it would paint text on
         // the line) and no kind learning (a ray must not dye the next trendline).
         if(DrawIsHRay(name)) { ObjectSetInteger(0, name, OBJPROP_COLOR, c); break; }
         // P-UI-136: a path segment is one drawing of N objects — the plain ink
         // (no `[CL` desc: it would paint text on the line) on EVERY sibling, at the
         // path's OWN opacity (P-UI-137: the pick and the TR step share one writer, so
         // choosing a colour can never drop the fade the user just set).
         if(DrawIsPathSeg(name)) { string pid = ""; PathIdOfName(name, pid); PathInkApply(pid, c, PathInkOpacityGet(pid)); break; }
         color rc = DrawSlotColorStore(name, c);   // P-DRAW-48: pure on the desc, blend on the chart
         //--- P-DRAW-BODY: for a LEVEL kind this cell is the LEVELS' — the body has its own
         //--- seat (`DRAW_SLOT_BODYCOLOR`) and the two may never write each other's half.
         if(!DrawKindHasLevels(k)) ObjectSetInteger(0, name, OBJPROP_COLOR, rc);
         //--- P-DRAW-64: an interior the user has NOT coloured follows the border,
         //--- so a border write re-inks it too — the child, or the levels.
         color ip;
         if(DrawKindHasLevels(k))
            DrawLevelsSetColor(name, DrawSlotFillPure(name, ip) ? DrawSlotRenderFillColor(name, ip) : rc);
         if(DrawKindHasFillBody(k)) FillChildSync(name);
         s_dkColor[k] = c;
         //--- P-DRAW-INK (2026-10-04): the ONE ink every kind shares is noted HERE,
         //--- where every pick arrives. The kind's own memory records what IT wore; this
         //--- records the last colour the HAND chose anywhere, so a kind with no colour
         //--- of its own can wear it at birth.
         if((int)c >= 0) s_dkAnyClr = c;
         break;
      }
      case DRAW_SLOT_WIDTH:
      {
         int w = (int)MathRound(v);
         if(w < DRAW_WIDTH_MIN) w = DRAW_WIDTH_MIN;
         if(w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MAX;
         // P-UI-136: the path is one drawing — the pen lands on every segment.
         if(DrawIsPathSeg(name)) PathFamilySet(name, OBJPROP_WIDTH, w);
         else if(!DrawKindHasLevels(k)) ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
         //--- P-DRAW-BODY: the LEVELS' width for a level kind; the body keeps its own
         //--- (`DRAW_SLOT_BODYWIDTH`), so neither choice restyles the other.
         if(DrawKindHasLevels(k)) DrawLevelsSetWidth(name, w);
         if(!DrawIsHRay(name) && !DrawIsPathSeg(name)) s_dkWidth[k] = w;   // P-HR-04/P-UI-136: rays and paths learn nothing
         //--- P-DRAW-74: a thick pen paints solid, so the pair resolves here - the
         //--- one owner, asked on the way every chip, preset and undo already takes.
         DrawStylePairCoerce(name);
         break;
      }
      case DRAW_SLOT_STYLE:
      {
         int st = (int)MathRound(v);
         //--- P-DRAW-74b (2026-10-03) — THE FIBO'S LOOKS LIVE ABOVE THE NATIVE FIVE.
         //--- MT4's five styles end where chic begins: STYLE 5/6/7 means the pen's own
         //--- looks (FIBPEN_LOOK_NEON/CAPS/WASH), each a `[LKn]` tag beside the NATIVE
         //--- pair the terminal holds and painted by the pen's own followers. This is the
         //--- ONE writer that translates the pick: the tag first, then the native style
         //--- the look really draws with.
         int lk = 0;
         if(st > (int)STYLE_DASHDOTDOT && DrawKindHasLevels(k))
         {
            int cand = st - (int)STYLE_DASHDOTDOT;   // 5 -> 1, 6 -> 2, 7 -> 3
            if(cand >= FIBPEN_LOOK_NEON && cand <= FIBPEN_LOOK_WASH) lk = cand;
            if(lk > 0) FibPenLookSet(name, lk);
         }
         if(st < 0) st = 0;
         if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
         //--- the look's native half is what the terminal can actually draw; and a
         //--- NATIVE pick (0..4) means the look is off — one truth, never two.
         if(lk > 0) st = FibPenLookNative(lk);
         else if(DrawKindHasLevels(k)) FibPenLookDrop(name);
         if(st != (int)STYLE_SOLID)
         {
            if((int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)
               ObjectSetInteger(0, name, OBJPROP_WIDTH, DRAW_WIDTH_MIN);
            //--- P-DRAW-74b (2026-10-04) — ON A PEN KIND THE WIDTH LIVES IN THE STACK.
            //--- While no stack exists, the LEVEL widths ARE the logical width
            //--- (`FibPenLogicalWidth` reads them), and `FibPenSync` demotes them to the
            //--- visible 1 itself — AFTER it has read the logical one. Folding them here,
            //--- before the style is even set, erased that memory one write early: the
            //--- pen then read 1, built nothing and the level came out a plain 1 px dash,
            //--- i.e. «استایل‌ها روی ضخامت‌های بزرگ اعمال نمی‌شد». Only the OBJECT's own
            //--- width is folded for these kinds; their levels are the pen's business.
            bool penKind = (k == DK_FIBO || k == DK_FIBOFAN);
            if(!penKind) DrawLevelsSetWidth(name, DRAW_WIDTH_MIN);
            //--- ...and the kind's remembered WIDTH is the LOGICAL one on a pen kind, so
            //--- a dash pick must not fold it to 1 either (the next fibo would be born
            //--- thin, losing the thickness the user chose). Other kinds keep the law:
            //--- a dash is a one-pixel pen.
            if(!DrawIsHRay(name) && !DrawIsPathSeg(name) && !penKind) s_dkWidth[k] = DRAW_WIDTH_MIN;
         }
         // P-UI-136: the dash lands on every segment of the path.
         if(DrawIsPathSeg(name)) PathFamilySet(name, OBJPROP_STYLE, st);
         //--- P-DRAW-BODY: the LEVELS' style for a level kind — the body answers to its own
         //--- seat, and the pair law (a dash is a one-pixel pen) is asked there, not here.
         else if(!DrawKindHasLevels(k)) ObjectSetInteger(0, name, OBJPROP_STYLE, st);
         if(DrawKindHasLevels(k)) DrawLevelsSetStyle(name, st);
         if(!DrawIsHRay(name) && !DrawIsPathSeg(name)) s_dkStyle[k] = st;   // P-HR-04/P-UI-136
         DrawStylePairCoerce(name);                  // P-DRAW-74: a dash is a 1 px pen
         break;
      }
      //--- P-DRAW-BODY — THE BODY'S OWN THREE SEATS. They write `OBJPROP_COLOR/WIDTH/
      //--- STYLE` and stop there: no `DrawLevelsSet*` (the levels are another picture),
      //--- no `[LK…]` look tag (the looks are the levels' — `FibPenSync` reads the LEVEL
      //--- style), and no kind memory (the levels' memory must not learn a body choice).
      //--- What MT4 cannot draw is still MT4's law: a body thicker than one pixel paints
      //--- solid, so the body's pair is coerced HERE, where the body is written.
      case DRAW_SLOT_BODYCOLOR:
      {
         color bc = (color)(int)MathRound(v);
         if((int)bc < 0) return false;              // no colour, no write (P-DRAW-48)
         ObjectSetInteger(0, name, OBJPROP_COLOR, bc);
         break;
      }
      case DRAW_SLOT_BODYWIDTH:
      {
         int bw = (int)MathRound(v);
         if(bw < DRAW_WIDTH_MIN) bw = DRAW_WIDTH_MIN;
         if(bw > DRAW_WIDTH_MAX) bw = DRAW_WIDTH_MAX;
         ObjectSetInteger(0, name, OBJPROP_WIDTH, bw);
         DrawStylePairCoerce(name);
         break;
      }
      case DRAW_SLOT_BODYSTYLE:
      {
         int bs = (int)MathRound(v);
         if(bs < 0) bs = 0;
         if(bs > (int)STYLE_DASHDOTDOT) bs = (int)STYLE_DASHDOTDOT;
         ObjectSetInteger(0, name, OBJPROP_STYLE, bs);
         if(bs != (int)STYLE_SOLID)
            ObjectSetInteger(0, name, OBJPROP_WIDTH, DRAW_WIDTH_MIN);
         DrawStylePairCoerce(name);
         break;
      }
      case DRAW_SLOT_FILL:
      {
         bool f = (v > 0.5);
         s_dkFill[k] = f;
         if(DrawTypeHasFillChild(DrawObjectType(name)))
         {
            //--- P-DRAW-64: the interior is the CHILD — on makes it (and takes the
            //--- master's own MT4 fill away, so two colours can coexist), off drops it.
            if(f) FillChildEnsure(name);
            else
            {
               //--- ...and OFF means off even for a drawing a build before the split
               //--- left with its OWN fill on: the child may not exist yet.
               if((int)ObjectGetInteger(0, name, OBJPROP_FILL) != 0)
                  ObjectSetInteger(0, name, OBJPROP_FILL, false);
               FillChildDrop(name);
            }
            break;
         }
         ObjectSetInteger(0, name, OBJPROP_FILL, f);
         break;
      }
      case DRAW_SLOT_FILLCLR:
      {
         // P-UI-137: A PATH HAS NO INTERIOR. The FILL role's whole vocabulary is the
         // `[FL…]` desc tag, and on a segment that tag is not metadata — MT4 PAINTS
         // it as text along the line (the same reason the colour slot takes the plain
         // ink above). So the write is refused here, not silently turned into a
         // caption on the chart: a click on the popup's `Fill` chip changes nothing
         // and draws nothing, which is the truth for a polyline.
         if(DrawIsPathSeg(name)) break;
         //--- P-DRAW-64: the interior's own colour (`[FL…]`). It is recorded even
         //--- while the interior is OFF, so choosing a colour and switching the fill
         //--- on are two acts in either order.
         color ic = (color)(int)MathRound(v);
         if((int)ic < 0) return false;   // no colour, no write (P-DRAW-48's lesson)
         string dd = ObjectGetString(0, name, OBJPROP_TEXT);
         dd = DrawDescTag(dd, "[FL", DrawDescColorHex(ic));
         if(dd != ObjectGetString(0, name, OBJPROP_TEXT))
            ObjectSetString(0, name, OBJPROP_TEXT, dd);
         s_dkFillClr[k] = ic;
         if(DrawKindHasFillBody(k)) FillChildSync(name);
         if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, DrawSlotRenderFillColor(name, ic));
         break;
      }
      case DRAW_SLOT_RAY:
      {
         int r = (int)MathRound(v);
         if(r < 0) r = 0;
         if(r > 3) r = 3;
         if(DrawIsHRay(name)) r = 1;   // P-HR-04: a ray stays a right-ray — the law, not a choice
         // P-UI-136: a path's ends are VERTICES, so the ray cell is a no-op on it —
         // a stretched segment would no longer meet the handle that owns its end.
         if(DrawIsPathSeg(name)) { PathFamilySet(name, OBJPROP_RAY_RIGHT, false); PathFamilySet(name, OBJPROP_RAY_LEFT, false); break; }
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, (r & 1) != 0);
         ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  (r & 2) != 0);
         if(!DrawIsHRay(name)) s_dkRay[k] = r;   // P-HR-04: rays learn nothing
         break;
      }
      case DRAW_SLOT_LOCK:
      {
         // P-HR-04: the ray is born unselectable and stays that way — the dot
         // carry is its lock's replacement, so the cell is a no-op on rays.
         if(DrawIsHRay(name)) break;
         // P-UI-138: A PATH'S LOCK IS ITS OWN FLAG. `OBJPROP_SELECTABLE` would hand
         // MT4 an anchor on ONE segment while the handles carry the whole drawing —
         // two owners for one drawing, and a locked path that still tears in half.
         // So the cell asks the path, and the path's press branch answers it.
         if(DrawIsPathSeg(name))
         {
            string pid = "";
            if(PathIdOfName(name, pid)) PathLockSet(pid, (v > 0.5));
            break;
         }
         bool locked = (v > 0.5);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, !locked);
         if(locked) ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
         // the lock is NOT a style: it must not travel to the next drawing, or
         // every new object would be born unmovable. Learned nowhere on purpose.
         break;
      }
      //--- P-DRAW-09a: the three appended slots. FONT and GLYPH are LOOKS (learned
      //--- like colour and width); BACK is a placement-like arrangement and is
      //--- learned too — «my zones go behind the candles» is a statement about the
      //--- user's zones, and one tap puts a stray one back in front.
      case DRAW_SLOT_FONT:
      {
         int fs = (int)MathRound(v);
         if(fs < DRAW_FONT_MIN) fs = DRAW_FONT_MIN;
         if(fs > DRAW_FONT_MAX) fs = DRAW_FONT_MAX;
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fs);
         s_dkFont[k] = fs;
         break;
      }
      case DRAW_SLOT_GLYPH:
      {
         int g = (int)MathRound(v);
         if(g < DRAW_GLYPH_MIN) g = DRAW_GLYPH_MIN;
         if(g > DRAW_GLYPH_MAX) g = DRAW_GLYPH_MAX;
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, g);
         s_dkGlyph[k] = g;
         break;
      }
      case DRAW_SLOT_BACK:
      {
         bool b = (v > 0.5);
         ObjectSetInteger(0, name, OBJPROP_BACK, b);
         //--- P-DRAW-64 addendum 7: the interior is in the box's own LAYER, so the switch
         //--- that moves the box behind the bars moves the interior with it — one honest
         //--- control for the whole drawing, and the frame that separates the two.
         if(DrawKindHasFillBody(k)) FillChildSync(name);
         s_dkBack[k] = b;
         break;
      }
      //--- P-DRAW-64a: NEITHER OF THE TWO IS A LOOK. The 50 % LEVEL and whether the far
      //--- edge travels are the drawing's own arrangement, so they are learned NOWHERE
      //--- (`s_dkValid` may not claim the kind has a style memory because of one tap, or
      //--- a fresh drawing would be born wearing a look the user never set) and they do
      //--- not ride the undo (P-DRAW-21's own rule: an extend moves TIME, not the look).
      //--- The 50 % is the box's own MID PRICE, drawn by `BoxMidSync` as the `[BX50]`
      //--- mark: a level like the fib's, and NOT a length — the third cut, the user's
      //--- own correction «خود باکس رو از وسط طول نصف میکنه که نباید باشه … فقط 50 درصد
      //--- مثل فیبو». So this writes the MARK and nothing else: no anchor of the drawing
      //--- moves, the box keeps the length the hand gave it, and the interior is not a
      //--- party to it («۵۰ درصد باکس فقط میخوام، fill بهکارم نمیاد»).
      case DRAW_SLOT_BOXHALF:
      {
         //--- P-UI-139: on a PATH the same cell is its 50 % MARKERS — one small
         //--- circle at each leg's middle, painted by the path's own owner. The
         //--- rectangle's own answer (the mid PRICE line) is untouched below.
         if(DrawIsPathSeg(name))
         {
            string pid = "";
            if(PathIdOfName(name, pid)) PathMidSet(pid, (v > 0.5));
            break;
         }
         if(DrawObjectType(name) != OBJ_RECTANGLE) return false;
         bool mid = false; int ext = BOXEXT_OFF, exn = 0;
         BoxMarkRead(name, mid, ext, exn);
         bool on = (v > 0.5);
         if(on == mid) return true;
         //--- the mid line and the travelling edge are two marks on one group and one
         //--- group has one writer — and they COEXIST now (the level is a horizontal line,
         //--- the extend is a time), so switching the level on PRESERVES the edge's mode
         //--- instead of killing it: a box whose edge travels and wears its level does both.
         BoxMarkWrite(name, on, ext, exn);
         return true;
      }
      case DRAW_SLOT_EXTEND:
      {
         if(DrawObjectType(name) != OBJ_RECTANGLE) return false;
         bool mid = false; int ext = BOXEXT_OFF, exn = 0;
         BoxMarkRead(name, mid, ext, exn);
         //--- the far edge travels with the newest bar. It and the 50 % LEVEL no longer
         //--- fight over one edge: the level is a horizontal line at the box's mid
         //--- PRICE, so the two can be on together (the line simply rides the edge).
         BoxMarkWrite(name, mid, (v > 0.5) ? BOXEXT_END : BOXEXT_OFF, 0);
         return true;
      }
      default: return false;
   }
   s_dkValid[k] = true;
   //--- P-DRAW-09c (2026-10-04): the ONE slot writer persists what it just learned —
   //--- «همیشه آخرین تغییرات روی ابجکت پیش‌فرض بشه» is true only if the last change
   //--- survives the session. One write per user act; a still frame never reaches here.
   DrawPresetsSave();
   return true;
}

//--- THE STYLE THE USER LAST USED FOR THIS KIND, WRITTEN ONTO A FRESH OBJECT.
//--- Called the moment the terminal reports the creation (see the entry's
//--- OBJECT_CREATE branch): a drawing the user made is adjusted to their own
//--- last look before they can even see it in the old style.
// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-74 — THE PAIR IS ONE PICTURE. MT4 paints a line wider than 1 px SOLID:
// the terminal's own reference puts it plainly - a `STYLE_*` line style is used
// "only if the line width is equal to 0 or 1" (book.mql4.com, *Styles of drawing
// indicator lines*). So (3, Dash) is not a look, it is a state no terminal can
// draw, and every owner of a look has to refuse it rather than store it.
// ONE owner, two rules, and it is asked of an object NOT only when a chip fires
// but on the strip's own open, because the terminal's properties dialog writes
// the pair directly and never passes here.
//   width  > 1  =>  STYLE_SOLID   (a thick pen has no dash pattern)
//   style  != SOLID  =>  width 1   (a dash is a one-pixel pen)
// Both writes are guarded (one read, zero writes on a legal pair) and the KIND
// memory and the level family move with them, so the next drawing of the kind
// is born wearing what the last one really showed.
// ══════════════════════════════════════════════════════════════════════════
bool DrawStylePairCoerce(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;
   //--- P-DRAW-74b (2026-10-04) — A PEN KIND IS NOT THIS FUNCTION'S OBJECT. Its drawn
   //--- pair lives on the LEVELS (`OBJPROP_LEVELWIDTH`/`LEVELSTYLE`), and the object's
   //--- own pair is only a MEMORY. Reading that memory here meant a thick styled fibo
   //--- was forced back to STYLE_SOLID — every level with it — the moment the strip
   //--- opened or the chart repainted (`DrawStrip_Paint` calls this on every open), so
   //--- the stack died and the style vanished: the same report as (A), one seat over.
   //--- `FibPenSync` owns the visible pair for these kinds — a styled level is drawn at
   //--- width 1 with the thickness carried by the stack — so the pair is legal by
   //--- construction and this coercion has nothing true to say about it.
   if(k == DK_FIBO || k == DK_FIBOFAN) return false;
   int w = (int)ObjectGetInteger(0, name, OBJPROP_WIDTH);
   int st = (int)ObjectGetInteger(0, name, OBJPROP_STYLE);
   if(w < DRAW_WIDTH_MIN) w = DRAW_WIDTH_MIN;
   if(w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MAX;
   if(st < 0) st = 0;
   if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
   bool changed = false;
   if(w > DRAW_WIDTH_MIN)
   {
      if(st != (int)STYLE_SOLID)
      {
         st = (int)STYLE_SOLID;
         ObjectSetInteger(0, name, OBJPROP_STYLE, st);
         //--- P-DRAW-BODY: this is the BODY's pair law now. It must not reach for the
         //--- levels: a styled level the terminal cannot draw is exactly what the pen
         //--- exists to draw, and coercing it back to solid IS the reported defect.
         changed = true;
      }
   }
   else if(st != (int)STYLE_SOLID)
   {
      w = DRAW_WIDTH_MIN;
      ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
      changed = true;
   }
   if(!DrawIsHRay(name) && !DrawIsPathSeg(name))
   {
      if(s_dkWidth[k] != w) { s_dkWidth[k] = w; changed = changed || true; }
      if(s_dkStyle[k] != st) { s_dkStyle[k] = st; changed = changed || true; }
   }
   return changed;
}

bool DrawStyleApplyOnCreate(const string name)
{
   if(name == "" || DrawIsIndicatorObject(name)) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;   // a stranger: the terminal's own look, untouched
   if(ObjectFind(0, name) < 0) return false;
   //--- P-DRAW-INK (2026-10-04) — THE INK THE KIND HAS NO MEMORY OF. Reported on a
   //--- chart whose fibos had been given a width and a look but never a colour:
   //--- «چرا رنگش پیش‌فرض که میکشم سفید هستش؟ آخرین تغییرات آبی بود». The kind's own
   //--- colour is asked FIRST (P-DRAW-48/75); only a kind that has none takes the last
   //--- ink the hand picked ANYWHERE — so a fresh drawing wears the blue the last pick
   //--- painted, never the terminal's factory white.
   color want = s_dkColor[k];
    if((int)want < 0) want = s_dkAnyClr;
    if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0 && (int)want >= 0)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, want);
      if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, want);
   }
   //--- P-DRAW-INK: a kind the user has NEVER styled has exactly one thing of its own
   //--- to wear — the ink above. Its width, style, fill and ray were never chosen, so
   //--- they are left exactly as the terminal would have drawn them (P-DRAW-75).
   if(!s_dkValid[k]) return true;
   if((DrawKindCaps(k) & DRAW_CAP_WIDTH) != 0)
   {
      ObjectSetInteger(0, name, OBJPROP_WIDTH, s_dkWidth[k]);
      if(DrawKindHasLevels(k)) DrawLevelsSetWidth(name, s_dkWidth[k]);
   }
   if((DrawKindCaps(k) & DRAW_CAP_STYLE) != 0)
   {
      ObjectSetInteger(0, name, OBJPROP_STYLE, s_dkStyle[k]);
      if(DrawKindHasLevels(k)) DrawLevelsSetStyle(name, s_dkStyle[k]);
   }
   DrawStylePairCoerce(name);   // P-DRAW-74: the remembered pair is coerced, not trusted
   //--- P-DRAW-64: the interior first (the look it was born with), then the fill
   //--- that shows it — the child is made with the colour already on the drawing.
   if((DrawKindCaps(k) & DRAW_CAP_FILLCLR) != 0 && (int)s_dkFillClr[k] >= 0)
      DrawSlotWrite(name, DRAW_SLOT_FILLCLR, (double)(int)s_dkFillClr[k]);
   if((DrawKindCaps(k) & DRAW_CAP_FILL) != 0)
      DrawSlotWrite(name, DRAW_SLOT_FILL, s_dkFill[k] ? 1.0 : 0.0);   // P-DRAW-64: routes by TYPE
   if((DrawKindCaps(k) & DRAW_CAP_RAY) != 0)
   {
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, (s_dkRay[k] & 1) != 0);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  (s_dkRay[k] & 2) != 0);
   }
   //--- P-DRAW-09a: and the three appended slots, on the same "last change saved"
   //--- rule — a fresh caption keeps the size the user last used for one.
   if((DrawKindCaps(k) & DRAW_CAP_FONT) != 0)
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, s_dkFont[k]);
   if((DrawKindCaps(k) & DRAW_CAP_GLYPH) != 0)
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, s_dkGlyph[k]);
   if((DrawKindCaps(k) & DRAW_CAP_BACK) != 0)
      ObjectSetInteger(0, name, OBJPROP_BACK, s_dkBack[k]);
   return true;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-02 — THE PRESET LAYER: «چند نوع فیبو که هر بار لازم نباشه از نو تنظیم
// بکنه». Built-in suggestions AND the user's own, per drawing KIND.
//
// WHY A PRESET IS NOT A SETTING. A setting is one value the user changes; a
// preset is a WHOLE LOOK — colour, width, style, fill, ray — that a trader
// thinks of as one thing ("my demand box", "the fibo I trade with"). MT4 has no
// such concept at all: its own dialog can only save the CURRENT object's look as
// the default for the NEXT one, one object type at a time, and it cannot name
// it, cannot keep several, and cannot share it between two types of drawing.
// That gap is exactly what this layer fills, and it is the reason the strip can
// stay TINY: the presets are the power, the strip is the reach.
//
// THE MODEL. Every kind owns `DRAW_PRESET_MAX` slots. Slots 0..n are the
// BUILT-IN suggestions (fixed, seeded by `DrawPresetsInit`); the rest are the
// user's own (`DrawPresetCapture` writes the object's CURRENT look into a slot,
// which is how "save this as my box" is spelled without a text field). Applying
// a preset writes the whole look in one call and LEARNS it, so the next drawing
// of that kind wears it too — the same "last change saved" rule as P-DRAW-01,
// one level up.
//
// WHY THE PRESETS ARE PER KIND AND NOT GLOBAL. A fibo's level family and a
// rectangle's fill are different animals; a shared list would offer a rectangle
// a look it cannot wear. Per kind, every offered preset is always applicable —
// the strip can therefore show them all without a single disabled row.
// ══════════════════════════════════════════════════════════════════════════
#define DRAW_PRESET_MAX  6      // 3 built-in suggestions + 3 the user owns
#define DRAW_PRESET_BUILTIN 3   // slots 0..2 are the suggestions
//--- P-DRAW-09c (2026-10-04) — THE LOOK OUTLIVES THE SESSION. «همیشه آخرین تغییرات
//--- روی ابجکت پیش‌فرض بشه و هر سری نیاز نباشه تنظیم بکن» — the kind memory already
//--- made the last look the default of the NEXT drawing of that kind; what it did not
//--- do was survive an attach, so the first fibo of every session was born factory
//--- fresh. The nine values pack into TWO exact doubles and ride the presets' own file
//--- in this reserved slot, which is OUTSIDE every preset band on purpose (so the
//--- band's own guard can never eat the row).
#define DRAW_LASTLOOK_SLOT 255
//--- P-DRAW-INK (2026-10-04) — THE ONE INK EVERY KIND SHARES. The kind's own colour
//--- answers «what did THIS kind last wear»; this answers the question the hand's own
//--- report asks («چرا رنگش پیش‌فرض که میکشم سفید هستش؟ آخرین تغییرات آبی بود»): which
//--- colour the LAST pick painted, whichever kind it painted. A kind that has no
//--- colour of its own takes it at birth (a first-ever fibo wears the blue the last
//--- trendline was). Its own reserved row, one below the look's.
#define DRAW_LASTINK_SLOT  254

struct DrawPreset
{
   bool   used;
   string name;
   color  clr;
   int    width;
   int    style;
   bool   fill;
   int    ray;
};

static DrawPreset s_dkPreset[DK_COUNT][DRAW_PRESET_MAX];

void DrawPresetSet(const EDrawKind k, const int slot, const string nm,
                   const color c, const int w, const int st, const bool fl, const int ry)
{
   if(k <= DK_NONE || k >= DK_COUNT) return;
   if(slot < 0 || slot >= DRAW_PRESET_MAX) return;
   s_dkPreset[k][slot].used  = true;
   s_dkPreset[k][slot].name  = nm;
   s_dkPreset[k][slot].clr   = c;
   s_dkPreset[k][slot].width = w;
   s_dkPreset[k][slot].style = st;
   s_dkPreset[k][slot].fill  = fl;
   s_dkPreset[k][slot].ray   = ry;
}

//--- THE SUGGESTIONS. Three per kind family, chosen to be the three looks a
//--- trader actually reaches for: the plain one, the loud one, and the quiet one.
//--- Nothing here is a preference of the indicator's — they are SEEDS the user
//--- overwrites in one long press (see the strip's TEMPLATE slot).
void DrawPresetsInit()
{
   for(int k = 0; k < DK_COUNT; k++)
      for(int i = 0; i < DRAW_PRESET_MAX; i++)
      {
         s_dkPreset[k][i].used  = false;
         s_dkPreset[k][i].name  = "";
         s_dkPreset[k][i].clr   = clrNONE;
         s_dkPreset[k][i].width = 1;
         s_dkPreset[k][i].style = (int)STYLE_SOLID;
         s_dkPreset[k][i].fill  = false;
         s_dkPreset[k][i].ray   = 0;
      }
   //--- lines and rays: the workhorses
   DrawPresetSet(DK_LINE, 0, "Trend",   clrDodgerBlue, 1, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_LINE, 1, "Ray",     clrOrangeRed,  1, (int)STYLE_SOLID,     false, 1);
   DrawPresetSet(DK_LINE, 2, "Quiet",   clrGray,       1, (int)STYLE_DOT,       false, 0);
   //--- the horizontal/vertical levels: two looks, one for marking, one for reading
   DrawPresetSet(DK_HLINE, 0, "Level",  clrGold,       2, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_HLINE, 1, "Marker", clrRed,        1, (int)STYLE_DASH,      false, 0);
   DrawPresetSet(DK_HLINE, 2, "Quiet",  clrSilver,     1, (int)STYLE_DOT,       false, 0);
   DrawPresetSet(DK_VLINE, 0, "Session",clrGold,       1, (int)STYLE_DASH,      false, 0);
   DrawPresetSet(DK_VLINE, 1, "Marker", clrRed,        1, (int)STYLE_SOLID,     false, 0);
   //--- the fibo family: the levels ARE the object, so the presets carry the
   //--- LEVEL look (colour/style/width) that MT4 makes the user set level by level
   DrawPresetSet(DK_FIBO, 0, "Classic", clrGold,       1, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_FIBO, 1, "Zones",   clrOrange,     1, (int)STYLE_DASH,      false, 0);
   DrawPresetSet(DK_FIBO, 2, "Quiet",   clrDimGray,    1, (int)STYLE_DOT,       false, 0);
   DrawPresetSet(DK_FIBOFAN, 0, "Classic", clrGold,    1, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_FIBOFAN, 1, "Zones",   clrOrange,  1, (int)STYLE_DASH,      false, 0);
   DrawPresetSet(DK_FIBOCHAN, 0, "Classic", clrGold,   1, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_FIBOCHAN, 1, "Filled",  clrGold,   1, (int)STYLE_SOLID,     true,  0);
   DrawPresetSet(DK_EXPANSION, 0, "Classic", clrGold,  1, (int)STYLE_SOLID,     false, 0);
   //--- the boxes: the user's own example («چند باکس پرکاربرد»)
   DrawPresetSet(DK_RECT, 0, "Box",     clrDodgerBlue, 1, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_RECT, 1, "Zone",    clrTeal,       1, (int)STYLE_DASH,      true,  0);
   DrawPresetSet(DK_RECT, 2, "Demand",  clrCrimson,    1, (int)STYLE_SOLID,     true,  0);
   DrawPresetSet(DK_TRIANGLE, 0, "Wedge", clrDodgerBlue, 1, (int)STYLE_SOLID,   true,  0);
   DrawPresetSet(DK_TRIANGLE, 1, "Quiet", clrGray,     1, (int)STYLE_DASH,      false, 0);
   DrawPresetSet(DK_ELLIPSE, 0, "Cycle", clrDodgerBlue, 1, (int)STYLE_SOLID,    false, 0);
   DrawPresetSet(DK_CHANNEL, 0, "Channel", clrDodgerBlue, 1, (int)STYLE_SOLID,  false, 0);
   DrawPresetSet(DK_CHANNEL, 1, "Quiet",   clrGray,     1, (int)STYLE_DASH,     false, 0);
   DrawPresetSet(DK_GANN, 0, "Gann",    clrGold,       1, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_PITCHFORK, 0, "Fork", clrDodgerBlue, 1, (int)STYLE_SOLID,   false, 0);
   DrawPresetSet(DK_ARROW, 0, "Mark",   clrRed,        1, (int)STYLE_SOLID,     false, 0);
   DrawPresetSet(DK_TEXT, 0, "Note",    clrWhite,      1, (int)STYLE_SOLID,     false, 0);
}

//--- the number of slots that are actually FILLED for a kind (built-ins first,
//--- then the user's own) — what the strip's TEMPLATE list shows, and nothing else.
int DrawPresetCount(const EDrawKind k)
{
   if(k <= DK_NONE || k >= DK_COUNT) return 0;
   int n = 0;
   for(int i = 0; i < DRAW_PRESET_MAX; i++) if(s_dkPreset[k][i].used) n++;
   return n;
}
string DrawPresetName(const EDrawKind k, const int slot)
{
   if(k <= DK_NONE || k >= DK_COUNT) return "";
   if(slot < 0 || slot >= DRAW_PRESET_MAX) return "";
   return s_dkPreset[k][slot].used ? s_dkPreset[k][slot].name : "";
}
bool DrawPresetIsBuiltin(const int slot) { return (slot >= 0 && slot < DRAW_PRESET_BUILTIN); }

//--- ONE TAP: the whole look, onto the object AND into the kind's memory.
bool DrawPresetApply(const string name, const int slot)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || slot < 0 || slot >= DRAW_PRESET_MAX) return false;
   if(!s_dkPreset[k][slot].used) return false;
   DrawSlotWrite(name, DRAW_SLOT_COLOR, (double)(int)s_dkPreset[k][slot].clr);
   DrawSlotWrite(name, DRAW_SLOT_WIDTH, (double)s_dkPreset[k][slot].width);
   DrawSlotWrite(name, DRAW_SLOT_STYLE, (double)s_dkPreset[k][slot].style);
   if(DrawSlotAvailable(k, DRAW_SLOT_FILL))
      DrawSlotWrite(name, DRAW_SLOT_FILL, s_dkPreset[k][slot].fill ? 1.0 : 0.0);
   if(DrawSlotAvailable(k, DRAW_SLOT_RAY))
      DrawSlotWrite(name, DRAW_SLOT_RAY, (double)s_dkPreset[k][slot].ray);
   return true;
}

//--- «save this as my own»: the object's CURRENT look into the next free slot
//--- (or the given one). The NAME is the caller's business — the strip hands it
//--- the object's own label, so a saved preset is never an anonymous number.
bool DrawPresetCapture(const string name, const string label)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;
   DrawStylePairCoerce(name);   // P-DRAW-74: never learn an illegal pair from the terminal dialog
   int slot = -1;
   for(int i = DRAW_PRESET_BUILTIN; i < DRAW_PRESET_MAX; i++)
      if(!s_dkPreset[k][i].used) { slot = i; break; }
   if(slot < 0) slot = DRAW_PRESET_MAX - 1;   // full: the newest user slot is overwritten
   DrawPresetSet(k, slot,
                 (label == "" ? ("My " + IntegerToString(slot - DRAW_PRESET_BUILTIN + 1)) : label),
                 (color)(int)DrawSlotRead(name, DRAW_SLOT_COLOR),
                 (int)DrawSlotRead(name, DRAW_SLOT_WIDTH),
                 (int)DrawSlotRead(name, DRAW_SLOT_STYLE),
                 (DrawSlotRead(name, DRAW_SLOT_FILL) > 0.5),
                 (int)DrawSlotRead(name, DRAW_SLOT_RAY));
   return true;
}

//--- P-DRAW-76: `DrawPresetApplyToKind` (a chart-wide walk per apply) is DELETED. P-DRAW-03's
//--- "one look, every drawing of the kind" is live as `DrawStyleApplyToKind` (the popover's
//--- APPLY-ALL row), and a preset reaches a whole GROUP through the strip's own selection loop
//--- (`DrawStripPresetApplyGroup` -> `DrawPresetApply` per member). Two owners of one act was
//--- the defect, and this one had no caller in any commit.

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-04 — THE PERFORMANCE CONTRACT OF THIS MODULE. «کاربر اندیکاتور کند قبول
// نداره» — so the rules are written down where they are obeyed, not discovered
// later in a profile.
//
// WHAT COSTS, AND WHAT DOES NOT.
//   * The CLASSIFIER, the CAPABILITY TABLE and the STYLE MEMORY are array
//     lookups and switch tables: a handful of instructions, no terminal call.
//   * The HIT TEST is the only expensive thing in the file: it walks the chart's
//     object list (one `ObjectName` + one `OBJPROP_TYPE` per object) and projects
//     anchors (`ChartTimePriceToXY`) only for the objects that pass the type and
//     the prefix filter. On a chart with 1500 objects that is 1500 string
//     compares — cheap, but not free, and NOT something a mouse-move may do.
//   * Therefore the hit test is PRESS-EDGE ONLY, and this module enforces it
//     itself instead of trusting its callers: `DrawObjectAtCached` is the only
//     entry point a gesture may use, it memoises its answer for
//     `DRAW_HIT_CACHE_MS`, and a second caller inside that window pays ONE tick
//     read instead of a walk.
//   * The steady state — no press, no hold, nothing held — costs NOTHING: no
//     call into this module happens at all until a gesture asks for one, and
//     every entry point starts with a bool read (is there anything to do?).
//
// THE MOUSE STREAM IS NEVER WALKED. `DrawSlotRead/Write` touch ONE named object
// (3-4 terminal calls); `DrawPresetApply` touches one object; the create hook
// runs once per object the user draws. A per-move repaint of the strip is the
// renderer's own business and re-reads the slots of the ONE held object — never
// the chart.
// ══════════════════════════════════════════════════════════════════════════
#define DRAW_HIT_CACHE_MS 400     // one walk per press, whatever asks twice

static string s_dkAtName = "";
static int    s_dkAtX = -1;
static int    s_dkAtY = -1;
static uint   s_dkAtMs = 0;

// THE entry point for every gesture: the hit test with its own press-edge memo.
// A move that asks again for the SAME pixel inside the window pays a tick read;
// a move that asks for a DIFFERENT pixel (the hand moved) pays one walk — which
// is the honest answer, because the object under the cursor really changed.
string DrawObjectAtCached(const int px, const int py)
{
   uint now = GetTickCount();
   if(s_dkAtX == px && s_dkAtY == py && (now - s_dkAtMs) < DRAW_HIT_CACHE_MS)
      return s_dkAtName;
   s_dkAtX = px; s_dkAtY = py; s_dkAtMs = now;
   s_dkAtName = DrawObjectAt(px, py);
   return s_dkAtName;
}

//--- the memo is a GESTURE's, never a session's: the next press must not inherit
//--- the previous answer (the chart may have changed under it).
void DrawHitCacheClear()
{
   s_dkAtName = "";
   s_dkAtX = -1; s_dkAtY = -1;
   s_dkAtMs = 0;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-07 — THE PRESETS LIVE IN A FILE, BECAUSE A NAME IS NOT A NUMBER.
//
// P-DRAW-05 stored one slot per GlobalVariable and hit the terminal's own wall:
// a GV holds a DOUBLE, so the user's label («My Box», «Supply 4H») had nowhere
// to go and every user slot came back as "My 1". That is the shape of limit this
// project refuses to ship: a template the user cannot NAME is a template they
// cannot find — exactly the ceiling MT4's own dialog has, where a look can only
// be "the last one" and never "my demand box".
//
// So the store is a FILE. MQL4's file API carries strings, and the project
// already keeps persistent state in files (the base-price history), so this is
// the codebase's own language, not a new one:
//
//   MQL4/Files/Biotak/DrawPresets.csv      (ONE file, GLOBAL, not per chart)
//   kind ; slot ; name ; packed-look
//
// WHY ONE GLOBAL FILE AND NOT ONE PER CHART: a template is the USER's look, not
// the chart's — «چند نوع فیبو که هر بار لازم نباشه از نو تنظیم بکنه» is a
// statement about the trader, and the same fibo look belongs on every chart they
// open. The chart id stays out of the name for that reason.
//
// The look itself is still ONE number (colour 24 bits · width 3 · style 3 ·
// fill 1 · ray 2 = 33 bits, exact in a double, unpacked through `long`), so a
// line is four fields and the whole file is a few hundred bytes.
//
// WRITES ARE RARE AND GUARDED: a save happens when a slot is captured or
// changed, never per frame, and `DrawPresetsSave` compares the slot it would
// write against the one it already has on disk only through its caller's own
// change detection (`DrawPresetCapture` / the strip's edit) — the file is
// rewritten in full, which for 8 slots × 17 kinds is trivial and keeps ONE
// writer instead of an append log to reconcile.
// ══════════════════════════════════════════════════════════════════════════
#define DRAW_PRESET_DIR  "Biotak"
#define DRAW_PRESET_FILE "Biotak\\DrawPresets.csv"

string DrawPresetPath() { return DRAW_PRESET_FILE; }

double DrawPresetPack(const DrawPreset &p)
{
   long v = (long)(int)p.clr;
   v += ((long)p.width << 24);
   v += ((long)p.style << 27);
   v += ((long)(p.fill ? 1 : 0) << 30);
   v += ((long)p.ray << 31);
   return (double)v;
}
void DrawPresetUnpack(const double raw, DrawPreset &p)
{
   long v = (long)raw;
   p.clr   = (color)(int)(v & 0xFFFFFF);
   p.width = (int)((v >> 24) & 0x7);
   p.style = (int)((v >> 27) & 0x7);
   p.fill  = (((v >> 30) & 0x1) != 0);
   p.ray   = (int)((v >> 31) & 0x3);
   p.used  = true;
}

//--- the whole store, one line per slot, the user's NAME included. The built-ins
//--- are NOT written: they are code, and freezing today's suggestions into a file
//--- would make tomorrow's build ship yesterday's defaults.
//--- P-DRAW-09c (2026-10-04) — THE LAST LOOK, PACKED EXACTLY. Two doubles carry the
//--- nine values of one kind's memory: word A holds the border's pair (colour 24 bits,
//--- width 3, style 3, fill 1, ray 2) plus the three appended looks (font 7, glyph 8,
//--- back 1) and a PRESENCE BIT at 33; word B holds the interior's colour (24 bits)
//--- and its own presence bit at 24. Nothing is ever a guess: `clrNONE` is -1 and
//--- `-1 & 0xFFFFFF` is WHITE, so the presence bit is what tells "no colour of its own"
//--- from a colour nobody chose (P-DRAW-75's rule, one file over).
double DrawStylePackA(const int k)
{
   if(k <= DK_NONE || k >= DK_COUNT) return 0.0;
   long v = (long)((int)s_dkColor[k] & 0xFFFFFF);
   v += ((long)(s_dkWidth[k] & 0x7) << 24);
   v += ((long)(s_dkStyle[k] & 0x7) << 27);
   v += ((long)((s_dkFill[k] ? 1 : 0)) << 30);
   v += ((long)(s_dkRay[k] & 0x3) << 31);
   v += ((long)(((int)s_dkColor[k] >= 0) ? 1 : 0) << 33);
   v += ((long)(s_dkFont[k] & 0x7F) << 34);
   v += ((long)(s_dkGlyph[k] & 0xFF) << 41);
   v += ((long)((s_dkBack[k] ? 1 : 0)) << 49);
   return (double)v;
}
double DrawStylePackB(const int k)
{
   if(k <= DK_NONE || k >= DK_COUNT) return 0.0;
   long v = (long)((int)s_dkFillClr[k] & 0xFFFFFF);
   v += ((long)(((int)s_dkFillClr[k] >= 0) ? 1 : 0) << 24);
   return (double)v;
}
//--- THE UNPACK — the other half of the SAME contract. Word B is 25 bits by design, so
//--- its own mask (`0x1FFFFFF`) is what keeps the presence bit and the colour in one
//--- read; word A's fields are read with the shifts its pack wrote, and a colour is
//--- returned only when the presence bit says there was one.
void DrawStyleUnpack(const int k, const double rawA, const double rawB)
{
   if(k <= DK_NONE || k >= DK_COUNT) return;
   long a = (long)rawA;
   s_dkColor[k] = (((((a >> 33) & 0x1) != 0)) ? (color)(int)(a & 0xFFFFFF) : clrNONE);
   s_dkWidth[k] = (int)((a >> 24) & 0x7);
   s_dkStyle[k] = (int)((a >> 27) & 0x7);
   s_dkFill[k]  = (((a >> 30) & 0x1) != 0);
   s_dkRay[k]   = (int)((a >> 31) & 0x3);
   s_dkFont[k]  = (int)((a >> 34) & 0x7F);
   s_dkGlyph[k] = (int)((a >> 41) & 0xFF);
   s_dkBack[k]  = (((a >> 49) & 0x1) != 0);
   long b = (long)rawB;
   b &= 0x1FFFFFF;   // word B is 25 bits: 24 of colour + its own presence bit
   s_dkFillClr[k] = ((((b >> 24) & 0x1) != 0) ? (color)(int)(b & 0xFFFFFF) : clrNONE);
   s_dkValid[k] = true;
}

void DrawPresetsSave()
{
   int h = FileOpen(DrawPresetPath(), FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   for(int k = 1; k < DK_COUNT; k++)
   {
      for(int i = DRAW_PRESET_BUILTIN; i < DRAW_PRESET_MAX; i++)
      {
         if(!s_dkPreset[k][i].used) continue;
         FileWrite(h, (int)k, i, s_dkPreset[k][i].name,
                   DoubleToString(DrawPresetPack(s_dkPreset[k][i]), 0));
      }
      //--- P-DRAW-09c: the kind's LAST LOOK rides the same file, in the reserved slot
      //--- (outside every preset band). A kind the user never styled writes nothing, so
      //--- the load can leave it factory-fresh (the test's own «nobody styled» case).
      if(!s_dkValid[k]) continue;
      FileWrite(h, (int)k, DRAW_LASTLOOK_SLOT,
                DoubleToString(DrawStylePackB(k), 0), DoubleToString(DrawStylePackA(k), 0));
   }
   //--- P-DRAW-INK: and the ONE ink every kind shares has its own row. It is not a
   //--- kind's look, so it does not ride a kind's slot: a single reserved row answers
   //--- the next attach's first drawing.
   if((int)s_dkAnyClr >= 0)
      FileWrite(h, 1, DRAW_LASTINK_SLOT, IntegerToString((int)s_dkAnyClr), "0");
   FileClose(h);
}

//--- called once per attach, right after the suggestions are seeded: a slot the
//--- user saved wins over the empty one it is restored into, NAME and all.
void DrawPresetsLoad()
{
   int h = FileOpen(DrawPresetPath(), FILE_READ | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      int k = (int)StringToInteger(FileReadString(h));
      int i = (int)StringToInteger(FileReadString(h));
      string nm = FileReadString(h);
      string pk = FileReadString(h);
      if(FileIsEnding(h) && pk == "") break;
      //--- P-DRAW-09c / P-DRAW-INK: the two reserved rows are answered BEFORE the preset
      //--- bands reject them — 255 and 254 are outside every band ON PURPOSE, so a guard
      //--- read first would eat the very rows these features write.
      if(i == DRAW_LASTLOOK_SLOT) { DrawStyleUnpack(k, StringToDouble(pk), StringToDouble(nm)); continue; }
      if(i == DRAW_LASTINK_SLOT) { int ink = (int)StringToInteger(nm); if(ink >= 0) s_dkAnyClr = (color)ink; continue; }
      if(k <= DK_NONE || k >= DK_COUNT) continue;
      if(i < DRAW_PRESET_BUILTIN || i >= DRAW_PRESET_MAX) continue;
      DrawPresetUnpack(StringToDouble(pk), s_dkPreset[k][i]);
      s_dkPreset[k][i].name = (nm == "" ? ("My " + IntegerToString(i - DRAW_PRESET_BUILTIN + 1)) : nm);
   }
   FileClose(h);
}

//--- P-DRAW-76: ONE slot goes, on the user's own say-so. The BUILT-INS refuse: they are code
//--- (`DrawPresetsInit` seeds them), and "delete a suggestion" would have to mean "put the
//--- suggestion back". The file is rewritten in full by the same single writer every capture
//--- uses (P-DRAW-08b), so the user's numbering survives the hole.
bool DrawPresetClear(const EDrawKind k, const int slot)
{
   if(k <= DK_NONE || k >= DK_COUNT) return false;
   if(slot < 0 || slot >= DRAW_PRESET_MAX || DrawPresetIsBuiltin(slot)) return false;
   if(!s_dkPreset[k][slot].used) return false;
   s_dkPreset[k][slot].used = false;
   s_dkPreset[k][slot].name = "";
   DrawPresetsSave();
   return true;
}
//--- P-DRAW-76: `DrawPresetsForget()` (a whole-file `FileDelete`) stood here and is DELETED.
//--- Its note claimed "the OFF paths and a removed instance must not leave the file behind",
//--- but the shipped design is the opposite: P-DRAW-05 loads the user's own templates at init
//--- and they must OUTLIVE the session, so wiring that delete into a teardown would have wiped
//--- them on an ordinary re-attach. It had no caller in any commit.

//--- P-DRAW-08b: THE ONE CALL A UI SHOULD MAKE when the user says "save this
//--- look as mine". The capture and the persist are one act — a capture that is
//--- not written is a template the user loses on the next attach, which is the
//--- failure mode P-DRAW-05 was retired for. It lives HERE (after both halves)
//--- because MQL4 has no forward declarations, and the strip calls this, never
//--- the two separately.
bool DrawPresetCaptureAndSave(const string name, const string label)
{
   if(!DrawPresetCapture(name, label)) return false;
   DrawPresetsSave();
   return true;
}

//--- P-DRAW-08f: "ALL" MEANS **THIS** LOOK, not "the preset the strip happens to
//--- be cycling". The cycle index is the strip's own state and the user cannot see
//--- it, so applying it to every drawing of the kind applies something they never
//--- chose — the look on the chart in front of them is the one they mean. One walk,
//--- the kind's own slots, the object itself skipped.
int DrawStyleApplyToKind(const string fromName)
{
   EDrawKind k = DrawKindOf(fromName);
   if(k == DK_NONE || ObjectFind(0, fromName) < 0) return 0;
   color  c  = (color)(int)DrawSlotRead(fromName, DRAW_SLOT_COLOR);
   int    w  = (int)DrawSlotRead(fromName, DRAW_SLOT_WIDTH);
   int    st = (int)DrawSlotRead(fromName, DRAW_SLOT_STYLE);
   double f  = DrawSlotRead(fromName, DRAW_SLOT_FILL);
   double r  = DrawSlotRead(fromName, DRAW_SLOT_RAY);
   //--- P-DRAW-64: the interior is part of the look this group wears.
   double fc = DrawSlotRead(fromName, DRAW_SLOT_FILLCLR);
   double fo = DrawSlotAlphaGet(fromName, DRAW_SLOT_FILLCLR);
   int done = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || nm == fromName || DrawIsIndicatorObject(nm)) continue;
      if(DrawKindOf(nm) != k) continue;
      DrawSlotWrite(nm, DRAW_SLOT_COLOR, (double)(int)c);
      DrawSlotWrite(nm, DRAW_SLOT_WIDTH, (double)w);
      DrawSlotWrite(nm, DRAW_SLOT_STYLE, (double)st);
      if(DrawSlotAvailable(k, DRAW_SLOT_FILL)) DrawSlotWrite(nm, DRAW_SLOT_FILL, f);
      if(DrawSlotAvailable(k, DRAW_SLOT_RAY))  DrawSlotWrite(nm, DRAW_SLOT_RAY, r);
      if(DrawSlotAvailable(k, DRAW_SLOT_FILLCLR))
      {
         DrawSlotWrite(nm, DRAW_SLOT_FILLCLR, fc);
         DrawSlotOpacitySet(nm, (int)fo, DRAW_SLOT_FILLCLR);
      }
      done++;
   }
   return done;
}

//--- P-DRAW-09b-RETIRED (2026-10-03): HOW MANY DRAWINGS «Apply to all <Kind>» WILL
//--- REALLY TOUCH. The row's label used to print the SELECTION's size, so it promised
//--- «all 2 selected» while the act underneath reached every drawing of the kind. This is
//--- the walk `DrawStyleApplyToKind` performs, so the number and the act are one fact.
int DrawStyleKindCount(const string fromName)
{
   EDrawKind k = DrawKindOf(fromName);
   if(k == DK_NONE) return 0;
   int n = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || nm == fromName || DrawIsIndicatorObject(nm)) continue;
      if(DrawKindOf(nm) != k) continue;
      n++;
   }
   return n;
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-09b (2026-09-23) — THE GROUP: ONE TOOLBAR, MANY DRAWINGS.
//
// User order: «همه نیازهای کاربر رو پوشش بده» + «سریع و راحت ولی پر امکانات».
// MT4's own properties dialog is strictly ONE object at a time, and
// `DrawStyleApplyToKind` (P-DRAW-03) was the blunt answer — every drawing of the
// kind, whether the user meant them or not. The honest middle, «these five boxes
// and not the two on the other side of the chart», has no MT4 control at all,
// and it is the one a trader reaches for every session: point at what you mean,
// then edit it once.
//
// THE MODEL. The terminal's OWN selection IS the group. MT4 already has a
// multi-select (Ctrl+click), and a selected object is exactly "the user pointed
// at this one" — so nothing new has to be taught, and no second selection state
// can drift from the one on the chart. The group is a SNAPSHOT taken when the
// strip opens, and it is HOMOGENEOUS BY KIND: a slot means the same thing on
// every member or it is not a group at all (a fibo has no fill, a box has no
// ray). A mixed selection therefore falls back to the ONE drawing the user
// actually held — the behaviour that cannot surprise anybody.
//
// WHY A SNAPSHOT, NOT A LIVE READ. A walk of the object list is a session cost
// (P-DRAW-04's rule), the selection emits no event to subscribe to, and a group
// that changed under the user's hand mid-edit is worse than a stale one. The
// strip re-reads on every open, which is the moment the group can legitimately
// change.
// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-09b-RETIRED (2026-10-03): THE STRIP SERVES ONE OBJECT. Reported: «مثلا من
// اگر دوتا فيبو داشته باشم بخوام رنگ يک شو عوض کنم روي ديگر هم اعمال ميشه» — two fibos,
// one colour tap, the second changed too. The writer was not the colour writer: this
// store walked the chart for every drawing of the held kind whose OBJPROP_SELECTED was
// true, and MT4 keeps that flag long after the gesture, so a Ctrl+click made hours
// earlier became a standing instruction. The store holds the held name and nothing else
// now, so every fan-out loop in the strip is gone by ARITHMETIC; «Apply to all <Kind>»
// stays the ONE explicit multi-object command (`DrawStyleApplyToKind`).
#define DRAW_SEL_MAX 1

static string s_dkSel[DRAW_SEL_MAX];
static int    s_dkSelN = 0;

int DrawSelCount() { return s_dkSelN; }
string DrawSelAt(const int i)
{
   if(i < 0 || i >= s_dkSelN) return "";
   return s_dkSel[i];
}
void DrawSelClear() { s_dkSelN = 0; }

//--- the members the chart still has (a delete, a legacy object) are dropped; the
//--- group never holds a name that would make a write a no-op.
void DrawSelPrune()
{
   int w = 0;
   for(int i = 0; i < s_dkSelN; i++)
   {
      if(s_dkSel[i] == "" || ObjectFind(0, s_dkSel[i]) < 0) continue;
      s_dkSel[w] = s_dkSel[i];
      w++;
   }
   for(int j = w; j < s_dkSelN; j++) s_dkSel[j] = "";
   s_dkSelN = w;
}

//--- SNAPSHOT: THE SERVED NAME, and never a walk (P-DRAW-09b-RETIRED). The terminal's
//--- own selection was once the group, but `OBJPROP_SELECTED` outlives the gesture that
//--- set it, so «these drawings» was a statement from an hour ago. The served drawing is
//--- the one the hand opened, and the callers' loops keep their shape (`DrawSelCount` is
//--- 0 or 1), so no fan-out can run without a caller first writing a second name.
int DrawSelSnapshot(const string hold)
{
   DrawSelClear();
   if(hold == "" || (DrawIsIndicatorObject(hold) && !DrawIsHRay(hold) && !DrawIsPathSeg(hold))) return 0;   // P-HR-04/P-UI-136
   EDrawKind k = DrawKindOf(hold);
   if(k <= DK_NONE || k >= DK_COUNT) return 0;
   s_dkSel[0] = hold;
   s_dkSelN = 1;
   return s_dkSelN;
}

//--- THE KIND'S OWN NAME, for the strip's header («Fibo», «Box»). One owner, so
//--- no two surfaces can call the same drawing two different things.
string DrawKindName(const EDrawKind k)
{
   switch(k)
   {
      case DK_LINE:      return "Trend Line";
      case DK_HLINE:     return "Horizontal Line";
      case DK_VLINE:     return "Vertical Line";
      case DK_CHANNEL:   return "Channel";
      case DK_FIBO:      return "Fibo";
      case DK_FIBOFAN:   return "Fibo Fan";
      case DK_FIBOCHAN:  return "Fibo Channel";
      case DK_EXPANSION: return "Expansion";
      case DK_GANN:      return "Gann";
      case DK_PITCHFORK: return "Pitchfork";
      case DK_RECT:      return "Box";
      case DK_TRIANGLE:  return "Triangle";
      case DK_ELLIPSE:   return "Ellipse";
      case DK_ARROW:     return "Arrow";
      case DK_TEXT:      return "Text";
      default:           return "Drawing";
   }
}

#endif // TOOLBAR_B_MQH
