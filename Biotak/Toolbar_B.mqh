// Toolbar_B.mqh - DrawToolbar.mqh split 2026-09-29: exact lines 1200-2053, byte-identical, zero renames.
#ifndef TOOLBAR_B_MQH
#define TOOLBAR_B_MQH

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-128 (2026-10-13) — THE NATIVE SURFACE'S COLOUR IS A COLOUR TOO.
//
// The strip's chips, the popup and the HEX field all learn through
// `DrawSlotWrite` — the one owner of the kind memory. The terminal's OWN
// surfaces (the properties dialog, the floating trend-line toolbar) write
// OBJPROP_COLOR directly and arrive as CHARTEVENT_OBJECT_CHANGE, so the
// memory never heard about them: a drawing recoloured there and then copied
// (the terminal's own Ctrl+drag duplicate) came back wearing the OLD colour
// — «برمیگرده به رنگ خودش مثلا اگر از جای غیره به جز نوار استرینگ تغییر بکنه».
//
// The one question a raw OBJECT_CHANGE cannot answer is WHETHER THE COLOUR
// MOVED: a drop after a drag fires the same event with the colour untouched,
// and learning there would teach the kind a factory colour the hand never
// picked. So each drawing's colour as the TERMINAL holds it is witnessed in
// one bounded memo — primed at attach and at the object's own create,
// re-noted by every writer that sets OBJPROP_COLOR (so our own writes read
// back as "nothing moved"), forgotten on delete. A level kind is never
// witnessed at all: its colours belong to the LEVEL family (P-DRAW-BODY), not
// to the object's own seat. Cost on a still frame: zero.
// Cost per native change: one property read and one scan of at most
// DRAW_INK_MEMO_MAX names. The write rides the memory's own owner
// (`DrawTplSave`) — there is never a second persistence path.
// ══════════════════════════════════════════════════════════════════════════
#define DRAW_INK_MEMO_MAX 48
static string s_inkMemoNm[DRAW_INK_MEMO_MAX];
static color  s_inkMemoClr[DRAW_INK_MEMO_MAX];
static int    s_inkMemoNext = 0;   // round-robin seat once every slot is full

//--- the colour the TERMINAL holds for a drawing the strip would serve —
//--- clrNONE for a stranger, a ray, a path, a level kind, or a kind with no
//--- colour seat of its own.
color DrawInkWitnessRead(const string name, EDrawKind &kout)
{
   kout = DK_NONE;
   if(name == "" || ObjectFind(0, name) < 0) return clrNONE;
   if(DrawIsIndicatorObject(name)) return clrNONE;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return clrNONE;
   if(DrawIsHRay(name) || DrawIsPathSeg(name)) return clrNONE;    // P-HR-04/P-UI-136: learn nothing
   if((DrawKindCaps(k) & DRAW_CAP_COLOR) == 0) return clrNONE;
   //--- P-DRAW-BODY + P-DRAW-128: a level kind carries DRAW_CAP_COLOR through
   //--- DRAW_CAP_COMMON, but ITS colours live in the LEVEL family
   //--- (`OBJPROP_LEVELCOLOR`) — reading the object's own `OBJPROP_COLOR` there
   //--- answers a property the object does not have, so such a drawing is never
   //--- witnessed and never learned from. Its `kout` stays DK_NONE.
   if(DrawKindHasLevels(k)) return clrNONE;
   kout = k;
   return (color)(int)ObjectGetInteger(0, name, OBJPROP_COLOR);
}

//--- note what the chart now wears (the blend, not the pick the user made).
void DrawInkMemoNote(const string name, const color c)
{
   if(name == "" || (int)c < 0) return;
   for(int i = 0; i < DRAW_INK_MEMO_MAX; i++)
      if(s_inkMemoNm[i] == name) { s_inkMemoClr[i] = c; return; }
   for(int i = 0; i < DRAW_INK_MEMO_MAX; i++)
      if(s_inkMemoNm[i] == "")
      {
         s_inkMemoNm[i] = name; s_inkMemoClr[i] = c; return;
      }
   s_inkMemoNm[s_inkMemoNext] = name; s_inkMemoClr[s_inkMemoNext] = c;
   s_inkMemoNext = (s_inkMemoNext + 1) % DRAW_INK_MEMO_MAX;
}

void DrawInkMemoForget(const string name)
{
   if(name == "") return;
   for(int i = 0; i < DRAW_INK_MEMO_MAX; i++)
      if(s_inkMemoNm[i] == name) { s_inkMemoNm[i] = ""; s_inkMemoClr[i] = clrNONE; }
}

//--- did the COLOUR move since we last saw this drawing? A first sight is a
//--- witness, not a change — the attach walk and the create prime make first
//--- sights rare — but it is noted, so the NEXT change on it is still seen.
bool DrawInkMemoDelta(const string name, const color c)
{
   for(int i = 0; i < DRAW_INK_MEMO_MAX; i++)
      if(s_inkMemoNm[i] == name)
      {
         if(s_inkMemoClr[i] == c) return false;
         s_inkMemoClr[i] = c;
         return true;
      }
   DrawInkMemoNote(name, c);
   return false;
}

//--- one drawing, witnessed now (used at attach and at its own create).
void DrawInkMemoPrime(const string name)
{
   EDrawKind k;
   color c = DrawInkWitnessRead(name, k);
   if((int)c < 0) return;
   DrawInkMemoNote(name, c);
}

//--- once per attach, right after the memory tables load: every drawing already
//--- on the chart is witnessed, so the first native change after a reload is
//--- recognised as a change (the reload is exactly when the user tests this).
void DrawInkMemoInit()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "") continue;
      DrawInkMemoPrime(nm);
   }
}

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
   color worn = DrawSlotRenderColor(name, pure);
   ObjectSetInteger(0, name, OBJPROP_COLOR, worn);
   //--- P-DRAW-128: the blend we just set IS the witness the native learner reads
   //--- back — without this note the opacity step's own OBJECT_CHANGE would look
   //--- like the hand re-inking the drawing and would be learned as a fresh pick.
   DrawInkMemoNote(name, worn);
   if(DrawKindHasLevels(k))
   {
      color ip;
      DrawLevelsSetColor(name, DrawSlotFillPure(name, ip) ? DrawSlotRenderFillColor(name, ip)
                                                          : DrawSlotRenderColor(name, pure));
   }
}
//--- P-DRAW-130 (2026-10-13): `remember=false` is a HOVER PREVIEW — the drawing
//--- still wears the value live (P-UI-131k's requirement), but the kind's memory
//--- learns nothing and no disk write is paid for a colour the hand only passed
//--- over. Every other caller is a real pick and keeps the default.
bool DrawSlotWrite(const string name, const int slot, const double v, const bool remember=true)
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
         //--- P-DRAW-128: the writer that owns the value owns its witness — the blend
         //--- it just put on the chart is noted, so the OBJECT_CHANGE our own write
         //--- fires reads back to the native learner as "nothing moved" (a level kind
         //--- owns no colour seat on the object — the witness refuses it, look above).
         if(!DrawKindHasLevels(k)) DrawInkMemoNote(name, rc);
         //--- P-DRAW-64: an interior the user has NOT coloured follows the border,
         //--- so a border write re-inks it too — the child, or the levels.
         color ip;
         if(DrawKindHasLevels(k))
            DrawLevelsSetColor(name, DrawSlotFillPure(name, ip) ? DrawSlotRenderFillColor(name, ip) : rc);
         if(DrawKindHasFillBody(k)) FillChildSync(name);
         //--- P-DRAW-74c: and a line's rows wear the same ink - one write reaches the stack.
         PenStackSync(name, false);
         //--- P-DRAW-130: a preview writes the drawing and learns nothing; only the
         //--- hand's own pick teaches the kind what it last wore.
         if(remember)
         {
            s_dkColor[k] = c;
            //--- P-DRAW-INK (2026-10-04): the ONE ink every kind shares is noted HERE,
            //--- where every pick arrives. The kind's own memory records what IT wore; this
            //--- records the last colour the HAND chose anywhere, so a kind with no colour
            //--- of its own can wear it at birth.
            if((int)c >= 0) s_dkAnyClr = c;
         }
         break;
      }
      case DRAW_SLOT_WIDTH:
      {
         int w = (int)MathRound(v);
         if(w < DRAW_WIDTH_MIN) w = DRAW_WIDTH_MIN;
         if(w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MAX;
         //--- P-DRAW-74c (2026-10-17): the pick IS the logical width; the stack is only
         //--- the visible half. A pick of 1 is the one write the stack cannot express on
         //--- its own (children outrank a width-1 read - the fibo's accepted ambiguity),
         //--- so it is resolved HERE, where the user's intent is known: the rows die
         //--- first and the sync then keeps the plain 1 px.
         bool penKind = PenStackServes(name);
         // P-UI-136: the path is one drawing — the pen lands on every segment.
         if(DrawIsPathSeg(name)) PathFamilySet(name, OBJPROP_WIDTH, w);
         else if(!DrawKindHasLevels(k)) ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
         //--- P-DRAW-BODY: the LEVELS' width for a level kind; the body keeps its own
         //--- (`DRAW_SLOT_BODYWIDTH`), so neither choice restyles the other.
         if(DrawKindHasLevels(k)) DrawLevelsSetWidth(name, w);
         if(!DrawIsHRay(name) && !DrawIsPathSeg(name)) s_dkWidth[k] = w;   // P-HR-04/P-UI-136: rays and paths learn nothing
         if(penKind)
         {
            if(w <= DRAW_WIDTH_MIN) PenStackStraysDrop(name);
            PenStackSync(name, false);
         }
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
         if(st > (int)STYLE_DASHDOTDOT && FibPenServesName(name))
         {
            lk = DrawLookFromSlot(st);   // P-UNIFY-4: 5 -> 1, 6 -> 2, 7 -> 3; 8 and above -> 0
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
            //--- P-DRAW-74c (2026-10-17) — AND THE FOLD IS THE FIBO'S LAW TOO: on a pen
            //--- kind the OBJECT's own width is the LOGICAL memory until the first
            //--- demotion, so folding it here - one write before the style lands and two
            //--- before the sync reads - erases the thickness the pick means to apply.
            //--- The sync below writes the visible 1 itself.
            bool penKind = FibPenServesName(name) || PenStackServes(name);   // P-UNIFY-3: the pen's own four; the other level kinds fall back to the native fold
            if(!penKind && (int)ObjectGetInteger(0, name, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)
               ObjectSetInteger(0, name, OBJPROP_WIDTH, DRAW_WIDTH_MIN);
            //--- P-DRAW-74b (2026-10-04) — ON A PEN KIND THE WIDTH LIVES IN THE STACK.
            //--- While no stack exists, the LEVEL widths ARE the logical width
            //--- (`FibPenLogicalWidth` reads them), and `FibPenSync` demotes them to the
            //--- visible 1 itself — AFTER it has read the logical one. Folding them here,
            //--- before the style is even set, erased that memory one write early: the
            //--- pen then read 1, built nothing and the level came out a plain 1 px dash,
            //--- i.e. «استایل‌ها روی ضخامت‌های بزرگ اعمال نمی‌شد». Only the OBJECT's own
            //--- width is folded for these kinds; their levels are the pen's business.
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
         //--- P-UNIFY-4b: the KIND's memory keeps the LOOK's slot, not its native
         //--- half - otherwise the next drawing of this kind is born with the right
         //--- dash and no `[LKn]` tag (Caps/Wash silently gone).
         int memSt = (lk > 0 ? DrawLookToSlot(lk) : st);
         if(!DrawIsHRay(name) && !DrawIsPathSeg(name)) s_dkStyle[k] = memSt;   // P-HR-04/P-UI-136
         //--- P-DRAW-74c: a line's rows wear the master's pattern - demote the undrawable
         //--- pair and re-dress the stack in ONE pass (a solid pick above the rows already
         //--- dissolved them back into the master's width). Refuses non-pen kinds itself.
         PenStackSync(name, false);
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
            //--- P-PEN-ALL: THE INTERIOR IS A LATER PIXEL THAN THE OUTLINE'S ROWS. MT4
            //--- paints in CREATION order (P-LOG-10), so a fill child that appeared after
            //--- a shape's pen rows covers the half of the thickness that lies inside the
            //--- outline. The sync re-states the pen in this same frame; it sees the
            //--- transition in its own net and rebuilds the rows above the interior. One
            //--- transition, then silence — a still frame pays two memo reads.
            PenStackSync(name, false);
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
         if(remember) s_dkFillClr[k] = ic;   // P-DRAW-130: a preview's fill is not a remembered fill
         if(DrawKindHasFillBody(k)) FillChildSync(name);
         //--- P-PEN-ALL: the interior's own colour is a pick like the FILL switch, and
         //--- on a shape it can bring the fill child into being (FillChildSync ensures
         //--- it) — so the pen is re-stated in the same frame, above the new pixel.
         PenStackSync(name, false);
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
   //--- P-DRAW-130: a preview marks nothing and pays no disk write; the hand's own
   //--- pick does both, exactly as it did before the preview existed.
   if(remember)
   {
      s_dkValid[k] = true;
      //--- P-DRAW-09c (2026-10-04): the ONE slot writer persists what it just learned —
      //--- «همیشه آخرین تغییرات روی ابجکت پیش‌فرض بشه» is true only if the last change
      //--- survives the session. One write per user act; a still frame never reaches here.
      //--- P-DRAW-132: EXCEPT while an apply holds the pen — a template apply writes the
      //--- whole look (5..9 slots) and pays the file write ONCE, after its last slot.
      if(s_dkTplHold <= 0) DrawTplSave();
   }
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
   if(FibPenServesName(name)) return false;   // P-UNIFY-3: the pen's own four — its sync owns the visible pair; the other level kinds fall back to the native fold
   //--- P-DRAW-74c (2026-10-17) — A LINE PEN KIND IS NOT THIS FUNCTION'S OBJECT EITHER,
   //--- the same law one family over. Its LOGICAL width lives on the master (before the
   //--- first demotion) or in the rows (after it), and this function can only see - or
   //--- produce - the demoted 1. The fold it would write erases the memory one write
   //--- before `PenStackSync` reads it: the dash would come out a plain 1 px and the
   //--- thickness would vanish - P-DRAW-74b's defect, one family over. The sync owns
   //--- the visible pair for these kinds; the pair is legal by construction.
   if(PenStackServes(name)) return false;
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
      //--- P-UNIFY-4b: the memory is a SLOT (5/6/7 = a look). Translate ONCE, here:
      //--- the terminal gets the look's native half and its `[LKn]` tag goes back on
      //--- the drawing, so the next attach or a fresh drawing keeps Neon/Caps/Wash.
      int memSt = s_dkStyle[k];
      int mlk = (memSt > (int)STYLE_DASHDOTDOT ? DrawLookFromSlot(memSt) : 0);
      int native = (mlk > 0 ? FibPenLookNative(mlk) : memSt);
      if(native < 0 || native > (int)STYLE_DASHDOTDOT) native = (int)STYLE_SOLID;
      ObjectSetInteger(0, name, OBJPROP_STYLE, native);
      if(DrawKindHasLevels(k)) DrawLevelsSetStyle(name, native);
      if(mlk > 0 && FibPenServesName(name)) { FibPenLookSet(name, mlk); FibPenSync(name, false); }
      else if(DrawKindHasLevels(k)) FibPenLookDrop(name);
   }
   DrawStylePairCoerce(name);   // P-DRAW-74: the remembered pair is coerced, not trusted
   //--- P-DRAW-74c: a fresh line born with a remembered THICK + DASH pair is stacked
   //--- here, at birth - otherwise it would flash a solid thick line until the next
   //--- heal pass. The sync reads the remembered width off the master and demotes it.
   PenStackSync(name, false);
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
// (3-4 terminal calls); `DrawTplApply` touches one object; the create hook
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

//--- P-DRAGF3d (2026-10-17) — THE PEN'S THIRD ANSWER: THE SELECTED LEVEL FAMILY'S
//--- FULL SHAPE, THE DIAGONAL INCLUDED. MEASURED (the 20:51 frame,
//--- biotak_diag_EURUSD_134362571361933137: FIBPENPRE view=on 25 against FIBPENARM 22 —
//--- 4 of the 25 real drags armed only at the release door, the user's own
//--- «بعضی وقتا که سریع»): a fast flick grabs the fibo by a line the press pick never
//--- measures. The press naming spans the LEVEL LINES (DrawHitLevels, t1..t2 at each
//--- level's own price) and the anchor handles (DrawHitSelectedHandle), but the
//--- anchor-to-anchor DIAGONAL — with the object's own RAY_LEFT/RIGHT, the part of a
//--- fibo a hand is on most — is tested by neither, so the press named nothing, the
//--- P-DRAGF3c trip never fired, and the stack stood frozen until the release door.
//--- The terminal's own pick DOES grab there, and a grab is a selection: this asks
//--- THAT, fenced by the cursor still resting on the full grabbable shape. The fence
//--- is exact because a pan holds a selected fibo at the cursor's own paper offset —
//--- cursor on the shape at the first traveled move is a terminal DRAG, cursor off it
//--- can only be a pan. One walk per press (the trip's own memo spends it, miss or
//--- hit); the cost note above stands — this is press-edge work merely DECIDED at the
//--- first traveled move.
bool DrawFiboFullHit(const string name, const int px, const int py)
{
   if(DrawHitSelectedHandle(name, px, py)) return true;   // the visible anchor controls
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   if(!DrawAnchorXY(name, 0, x1, y1) || !DrawAnchorXY(name, 1, x2, y2)) return false;
   bool oA = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_LEFT) != 0);
   bool oB = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != 0);
   if(DrawSegDist(px, py, x1, y1, x2, y2, oA, oB) <= (double)DRAW_HIT_PX) return true;   // the diagonal
   // the level lines, measured the way the terminal DRAWS them — P-LOOK-ANCHOR's law on
   // a plain fibo, and P-UNIFY-3's per-kind geometry on the fan, the channel and the
   // expansion (two ends, the kind's own) — extended by the same ray pair, so a fibo
   // that runs edge to edge is grabbed along its whole run.
   int n = DrawLevelCount(name);
   if(n <= 0) return false;
   datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
   double   p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   double   p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
   if(t1 <= 0 || !(p1 > 0.0) || !(p2 > 0.0)) return false;
   EDrawKind k = DrawKindOf(name);
   bool three = (k == DK_FIBOCHAN || k == DK_EXPANSION);
   datetime t3 = three ? (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 2) : 0;
   double   p3 = three ? ObjectGetDouble(0, name, OBJPROP_PRICE, 2) : 0.0;
   if(three && (t3 <= 0 || !(p3 > 0.0))) return false;
   int xa = 0, ya = 0, xb = 0, yb = 0;
   for(int k2 = 0; k2 < n; k2++)
   {
      double v = DrawLevelValue(name, k2);
      if(!MathIsValidNumber(v)) continue;
      double la = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t1);
      double lb = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t2);
      if(!(la > 0.0) || !(lb > 0.0)) continue;
      if(!ChartTimePriceToXY(0, 0, t1, la, xa, ya)) continue;
      if(!ChartTimePriceToXY(0, 0, t2, lb, xb, yb)) continue;
      if(DrawSegDist(px, py, xa, ya, xb, yb, oA, oB) <= (double)DRAW_HIT_PX) return true;
   }
   return false;
}
string DrawSelectedFiboAt(const int px, const int py)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || DrawIsIndicatorObject(nm)) continue;
      if(!FibPenServesName(nm)) continue;   // P-UNIFY-3: the pen's own four — a pitchfork and an arc have no chase
      if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTED)) continue;
      if(DrawFiboFullHit(nm, px, py)) return nm;
   }
   return "";
}


// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-128 — THE NATIVE SURFACE'S PICK IS A PICK TOO.
// Called from the CHARTEVENT_OBJECT_CHANGE branch (DrawStrip_Router.mqh's sync
// block), which is where the terminal reports its own dialog and toolbar: the
// hand recoloured a drawing OUTSIDE every surface we own. The witness above
// says whether the COLOUR is what moved (a move-drop fires the same event and
// must teach nothing); the memory below is asked compare-first, so a colour
// the kind already wears — or the ink it merely BORROWED at birth (P-DRAW-INK)
// — is not news. What survives is one write through the memory's own owner.
// Cost on a still frame: zero (no event, no call). Cost per native change: one
// property read, one bounded scan, and — only when the colour truly moved —
// the same single file write every other pick already pays.
// ══════════════════════════════════════════════════════════════════════════
void DrawInkLearnNative(const string name)
{
   EDrawKind k;
   color c = DrawInkWitnessRead(name, k);
   if((int)c < 0) return;                    // a stranger, a ray, a path, a level kind, or a colour nobody can hold
   if(!DrawInkMemoDelta(name, c)) return;    // nothing moved: our own write, or a drop
   if(c == s_dkColor[k]) return;             // the kind already wears it
   if((int)s_dkColor[k] < 0 && c == s_dkAnyClr) return;   // a borrowed ink is not this kind's own
   s_dkColor[k] = c;
   s_dkAnyClr   = c;
   s_dkValid[k] = true;
   DrawTplSave();
}

//--- P-DRAW-132: `DrawPresetClear` (P-DRAW-76) and `DrawPresetCaptureAndSave`
//--- (P-DRAW-08b) stood here. The named store above owns both now — `DrawTplDelete`
//--- (a compaction, so no hole survives a removal) and `DrawTplSaveAs` (one act:
//--- capture + persist) — and the built-in refusal died with the concept itself:
//--- every row of the rack is the user's, seeds included.
//--- The P-DRAW-76 note for `DrawPresetsForget()` (a whole-file `FileDelete`) is
//--- kept: the file must OUTLIVE the session, so no teardown may delete it.

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
      case DK_TANGLE:    return "Trend by Angle";   // P-UNIFY-2
      case DK_CYCLES:    return "Cycles";           // P-UNIFY-2
      default:           return "Drawing";
   }
}

#endif // TOOLBAR_B_MQH
