// FibPen.mqh - P-DRAW-74b: the fibo widths the terminal cannot draw (split 2026-10-03).
// MT4 draws STYLE_* only at width 1, so a thick + non-solid fibo level is a
// state no terminal can draw («استایل ها فقط روی 1px اعمال میشه»). The pen the
// terminal cannot draw is built beside it, PER LEVEL: the level keeps its
// STYLE at visible width 1 (the dash itself), and width-1 children carry the
// SAME style in the SAME ink, centred on the level — a thick dash in full ink,
// not a faint hint. The chosen width is remembered NOWHERE but the stack:
// logical width is 1 + children, read back by FibPenLogicalWidth.
// COST (fibo family only, event paths: open/route/tap/undo/drag): children
// exist ONLY for a thick + non-solid level (solid and 1px cost zero objects);
// a still frame pays reads, writes nothing. Bounded: the first 12 levels,
// at most 4 children each, off ONE scale read.
#ifndef FIBPEN_MQH
#define FIBPEN_MQH

#define FIBPEN_SUFFIX      "_FSD"
#define FIBPEN_MAX_LEVELS  12   // MT4's own nine plus customs; levels past it still demote, thin
//--- P-DRAGF2 (2026-10-04): how close to an anchor the press has to be to mean "this
//--- anchor". The repo's own grab radius (HandLinesSelectionGuard, CustomPriceGrabAt,
//--- PATH_GRAB_PX) — one number for "the hand is ON it", not a new tolerance.
#define FIBPEN_GRAB_PX     8
#define FIBPEN_GRAB_BODY   2   // the hand took the BODY: MT4 translates BOTH anchors
#define FIBPEN_TAG         "[FW]"   // retired: widths are remembered by the stack, never by text
//--- P-LOOK (2026-10-03) — THE FIBO'S OWN LOOKS. MT4's five native styles end
//--- where chic begins: a look rides the STYLE slot as 5/6/7 (NEON/CAPS/WASH),
//--- paints through this unit's own followers, and moves in the drag event that
//--- moved its owner — realtime, never a frame behind (contract §5). The look
//--- is a [LKn] tag beside the native pair the terminal holds; a native write
//--- from the MT4 dialog drops the stale tag instead of wearing two truths.
#define FIBPEN_LOOK_NEON   DRAW_LOOK_NEON   // P-UNIFY-4: the ids live in DrawKindProfile.mqh
#define FIBPEN_LOOK_CAPS   DRAW_LOOK_CAPS
#define FIBPEN_LOOK_WASH   DRAW_LOOK_WASH
//--- P-LOOK-3D RETIRED (2026-10-18, «3D کلا حذف کن»). The fourth look is gone: no
//--- [LK4] is ever read or written, no `_FSH` shadow is ever born. The family NAME
//--- and its sweeps stay (the sync's spend pass, the delete hub, HasPen and the
//--- early-out probe), so a chart from an older build degrades to the previous
//--- look — never to a dangling shadow.
#define FIBPEN_LK          DRAW_LOOK_TAG   // P-UNIFY-4: one tag for every look family
#define FIBPEN_CAP_SFX     "_FSC"
#define FIBPEN_WSH_SFX     "_FSW"
#define FIBPEN_SHW_SFX     "_FSH"
int FibPenLookNative(const int lk)
{
   int native = DrawLookNative(lk);
   return (native >= 0 ? native : (int)STYLE_SOLID);   // the retired 8 keeps the old solid fallback
}
int FibPenLookGet(const string fibo)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) return 0;
   int lk = DrawDescTagValue(ObjectGetString(0, fibo, OBJPROP_TEXT), FIBPEN_LK, 0);
   if(lk < FIBPEN_LOOK_NEON || lk > FIBPEN_LOOK_WASH) return 0;
   return lk;
}
void FibPenLookSet(const string fibo, const int lk)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) return;
   if(lk < FIBPEN_LOOK_NEON || lk > FIBPEN_LOOK_WASH) return;
   string d = ObjectGetString(0, fibo, OBJPROP_TEXT);
   string nd = DrawDescTag(d, FIBPEN_LK, IntegerToString(lk));
   if(nd != d) ObjectSetString(0, fibo, OBJPROP_TEXT, nd);
}
bool FibPenLookDrop(const string fibo)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) return false;
   string d = ObjectGetString(0, fibo, OBJPROP_TEXT);
   int at = StringFind(d, FIBPEN_LK);
   if(at < 0) return false;
   int e = StringFind(d, "]", at + StringLen(FIBPEN_LK));
   if(e <= at) return false;
   string nd = StringSubstr(d, 0, at) + StringSubstr(d, e + 1);
   if(StringLen(nd) > 0 && StringGetCharacter(nd, 0) == ' ') nd = StringSubstr(nd, 1);
   if(nd == d) return false;
   ObjectSetString(0, fibo, OBJPROP_TEXT, nd);
   return true;
}
//--- P-UNIFY-3 (2026-10-19) — WHO THE PEN SERVES. The LEVEL family is wider than the
//--- pen: a Pitchfork's own levels are drawn by MT4 on both teeth and its rails ARE
//--- the level family (PenStack.mqh:74), so the pen cannot state them without a
//--- measurement; a Fibo Arc is a circle and a Fibo Time Zones' levels are VERTICAL.
//--- What the pen can state is exactly the four kinds whose level geometry is known
//--- (`DrawLevelPriceAt`): the fibo, the fan, the channel and the expansion. The
//--- picker's three look rows ask THIS, never the cells' wider test, so a row can
//--- never be offered where the writer refuses to draw (C-04).
bool FibPenServesType(const int ty)
{
   return (DrawTypePenFamily(ty) == DKPEN_LEVEL);
}
bool FibPenServesName(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   return FibPenServesType(DrawObjectType(name));
}
string FibPenCapName(const string f, const int dl) { return f + FIBPEN_CAP_SFX + IntegerToString(dl); }
string FibPenWashName(const string f, const int dl) { return f + FIBPEN_WSH_SFX + IntegerToString(dl); }
string FibPenShwName(const string f, const int dl) { return f + FIBPEN_SHW_SFX + IntegerToString(dl); }
//--- P-LOOK-3D retired: the `_FSH` name above is spent only by sweeps now (the
//--- sync's spend pass, the delete hub, HasPen and the early-out probe) — nothing
//--- ever creates one, so a legacy shadow dies on the first sync and never returns.
//--- P-DRAGF (2026-10-03) — THE HAND'S OWN CADENCE. Measured DRAGSTAT: the
//--- terminal fires ~1-2 OBJECT_DRAG/s while the mouse moves ~60-100/s and the
//--- dragged master is blitted per move — followers parked on the drag event
//--- trail by whole seconds («موقع درگ فریمش عقب میمونه»). So a fibo drag ARMS
//--- the chase and every mouse move re-seats the children — geometry only
//--- (width, style, colour, demote, sweep and tags never change mid-gesture and
//--- stay on the discrete paths, which also converge on release). HOW the move
//--- question is answered is P-DRAGF2 below: the anchor by pixels at the press,
//--- the master by a snapshot resynced on every landing, the moved frame by its
//--- own flush. Cost per move: cursor + anchors + one value per level + one
//--- price read per standing child, moves only on diff. Unarmed (button up,
//--- deleted, never armed): two compares.
static string s_fibDragObj = "";
static uint s_fibMovMs = 0;   // DIAG-139 shared move-sample throttle (Sync + Follow)

//--- P-DRAGF2 (2026-10-04) — WHICH ANCHOR THE HAND TOOK, AND WHERE THE MASTER IS.
//---
//--- The first chase asked "the anchor nearest the CURSOR PRICE" and set that anchor's
//--- price to the cursor. That predicate is wrong on its own: the anchor the hand did NOT
//--- take is already a drag event old (measured DRAGSTAT 0.6-1.6 s against ~50-130
//--- moves/s), and once the hand travels that STALE side is the FARTHER one from the
//--- cursor — the price test then calls it "the hand's", and the stack rides the cursor
//--- on one side and the last landed price on the other, righting itself once per drag
//--- event.
//--- AND THE SESSION THAT REPORTED IT SAYS WORSE: the chase was not late, it never ran.
//--- Diag 2026-10-03, «Fibo 11000»: the stack came into being at 19:49:32.396 (`FIBPEN ...
//--- new=8`), the strip's dismiss click landed at :34.973, and the drag events at :34.972,
//--- :36.573, :38.236 and :39.860 — four in five seconds, `moved=14` children each, the
//--- drag event's own sync — were the ONLY re-seats between 252 left-button moves of the
//--- hand's stream. The follow sat under the shut-strip guard (see the seat note in
//--- DrawStrip_Router.mqh); four re-seats in five seconds IS «یک فریم عقب», and it is the
//--- same shape P-DRAW-64d fixed for the box's mid line one seat away.
//---
//--- So the chase answers the two questions the gesture actually asks:
//---   * WHICH anchor is under the hand — by PIXELS at the press (`ChartTimePriceToXY`
//---     against FIBPEN_GRAB_PX, the repo's own grab radius), decided ONCE and never
//---     re-guessed mid-gesture. The BODY is its own answer: MT4 translates BOTH anchors
//---     when the hand is not on one, which a single-anchor substitution cannot express;
//---   * WHERE the master is — a snapshot RESYNCED every time the terminal lands one of
//---     its own updates (live read != the probe), with the cursor origin moved with it,
//---     so the chase extrapolates between two lands and cannot accumulate an error.
static int      s_fibGrab   = -1;             // -1 undecided · 0/1 the hand's anchor · FIBPEN_GRAB_BODY
static double   s_fibP0[2]  = {0.0, 0.0};     // the master's anchors at the last resync
static datetime s_fibT0[2]  = {0, 0};
static double   s_fibProbeP[2] = {0.0, 0.0};  // ...and as read at the last look (the landing probe)
static datetime s_fibProbeT[2] = {0, 0};
static double   s_fibCurP0  = 0.0;            // the cursor that resync was taken at

void FibPenChaseReset()
{
   s_fibGrab = -1;
   s_fibP0[0] = 0.0; s_fibP0[1] = 0.0;
   s_fibT0[0] = 0; s_fibT0[1] = 0;
   s_fibProbeP[0] = 0.0; s_fibProbeP[1] = 0.0;
   s_fibProbeT[0] = 0; s_fibProbeT[1] = 0;
   s_fibCurP0 = 0.0;
}
void FibPenDragArm(const string name)
{
   //--- P-DRAGF2: the drag event fires THROUGH a gesture (measured DRAGSTAT ~1/s), and
   //--- it lands the master — a landing is not a new ask. Re-arming here would re-run
   //--- FibPenChaseReset() mid-gesture, re-asking the anchor question at a cursor that
   //--- has already travelled (an anchor grab would read as a body drag) and dropping
   //--- the snapshot behind the hand. Only a new name — or the first event after a
   //--- disarm — opens a chase; the gesture's own end is FibPenDragDisarm (button up).
   if(name != "" && name == s_fibDragObj) return;
   s_fibDragObj = "";
   FibPenPreviewEnd();   // P-DRAGF3: a missed release must not hold the previous body hostage
   FibPenChaseReset();   // a new gesture asks its own questions: no snapshot survives it
   if(name == "" || ObjectFind(0, name) < 0) return;
   if(DrawIsIndicatorObject(name)) return;
   if(!FibPenServesType(DrawObjectType(name))) return;   // P-UNIFY-3: the four kinds whose levels the pen can state
   s_fibDragObj = name;
   FibPenPreviewArm();   // P-DRAGF3: a patterned thick fibo drags NATIVELY - see the block below
}
void FibPenDragDisarm()
{
   if(s_fibDragObj != "") { s_fibDragObj = ""; FibPenChaseReset(); }
}
//--- P-DRAGF3 (2026-10-17) - THE GESTURE BELONGS TO THE TERMINAL.
//--- MEASURED (P-DRAGF/P-DRAGF2, the numbers this file already carries): the terminal
//--- fires OBJECT_DRAG ~1-2/s (DRAGSTAT) while the hand's own moves arrive ~60-100/s,
//--- and a patterned thick fibo is a DEMOTED master (width 1) plus moved children per
//--- level - children WE re-seat on every move, in a frame painted AFTER the frame the
//--- terminal already blitted. The trail is structural: a follower cannot be painted in
//--- the frame it follows. So the PREVIEW hands the body BACK: at the arm (the gesture's
//--- first drag event) every stacked level's width goes back to the logical number -
//--- which MT4 draws SOLID at width>1, the very law this file exists around - and the
//--- stack (rows, caps, wash) is hidden ONCE. Through the whole gesture this unit then
//--- writes NOTHING (the three gates below), the terminal's own native blit carries the
//--- body, and there is no frame to be behind. At the release the preview ends, the
//--- children come back, and ONE FibPenSync re-demotes + re-seats + re-memoizes in the
//--- release's own flushed frame (DrawStrip_Router, the click door; the button-up move
//--- is the second door - a hand can let go with no click event naming an object).
//--- Cost per gesture: one LEVELWIDTH write per stacked level + one hide per child at
//--- the arm, one un-hide + one sync at the release - against the chase's per-move
//--- re-seats at up to 100 moves/s. The visible trade, stated: while the hand moves a
//--- patterned thick fibo previews as a SOLID thick one and the pattern returns at the
//--- release. MT4 cannot draw the pattern thick - the glass is solid anyway.
//--- P-DRAGF3a (2026-10-17): the same hand-back covers a LOOK whose children stand with
//--- NO stack (CAPS/WASH ride a solid level, `want` is 0) - their halo was re-seated by
//--- the chase one frame behind while the arm refused them on width alone.
static bool   s_fibPreview    = false;   // P-DRAGF3: the preview owns the gesture
static string s_fibPreviewObj = "";

void FibPenPreviewArm()
{
   if(s_fibPreview) return;
   string fibo = s_fibDragObj;
   if(fibo == "" || ObjectFind(0, fibo) < 0) return;
   int nl = DrawLevelCount(fibo);
   int nw = (nl > FIBPEN_MAX_LEVELS) ? FIBPEN_MAX_LEVELS : nl;
   if(nw <= 0) return;
   int refLog = FibPenLogicalWidth(fibo, 0);   // the sync's OWN reference (level 0)
   //--- P-DRAGF3a (2026-10-17) — A LOOK'S CHILDREN EXIST WITH NO STACK AT ALL. CAPS and
   //--- WASH ride a SOLID level (`want` is 0 for them), so `refLog` stays the logical
   //--- width while their children stand — the old `refLog <= DRAW_WIDTH_MIN` fence and
   //--- the `nW <= 0` gate both refused exactly those looks, and the halo went back to
   //--- the chase: the one-frame lag this preview exists to end, one look over. The look
   //--- tag answers for one read; only a THIN, LOOK-LESS fibo has nothing to hand back.
   if(FibPenLookGet(fibo) == 0 && refLog <= DRAW_WIDTH_MIN) return;
   int nW = 0, nH = 0;
   for(int l = 0; l < nw; l++)
   {
      int c = FibPenChildCount(fibo, l);
      if(c > 0)   // a stacked level: the width goes back and the rows hide with it
      {
         if((int)ObjectGetInteger(0, fibo, OBJPROP_LEVELWIDTH, l) != refLog)
         { ObjectSetInteger(0, fibo, OBJPROP_LEVELWIDTH, l, refLog); nW++; }
         for(int q = 0; q < c; q++)
         {
            string nm = FibPenName(fibo, l, q);
            if(ObjectFind(0, nm) < 0) continue;
            if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
            { ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); nH++; }
         }
      }
      //--- caps and wash are the LOOK's own children, hidden whether or not
      //--- the level stacked — the chase re-seats them on every move like any row
      //--- (P-DRAGF3a).
      string cn = FibPenCapName(fibo, l);
      if(ObjectFind(0, cn) >= 0 && (int)ObjectGetInteger(0, cn, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
      { ObjectSetInteger(0, cn, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); nH++; }
      string wn = FibPenWashName(fibo, l);
      if(ObjectFind(0, wn) >= 0 && (int)ObjectGetInteger(0, wn, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
      { ObjectSetInteger(0, wn, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); nH++; }
   }
   if(nW <= 0 && nH <= 0) return;   // nothing demoted and no look child: no preview, no flag
   s_fibPreview = true;
   s_fibPreviewObj = fibo;
   // The flush is the caller's: this arm runs inside the drag branch whose own tail
   // already ends in ChartRedraw() (P-DRAW-74b-f, DrawStrip_Router).
   DrawStripDiagEmit("[drawstrip] FIBPENPRE view=on fibo=\"" + fibo + "\" lv=" + IntegerToString(nW) +
                     " hid=" + IntegerToString(nH) + " w=" + IntegerToString(refLog));
}

bool FibPenPreviewEnd()
{
   if(!s_fibPreview) return false;
   string fibo = s_fibPreviewObj;
   s_fibPreview = false;   // cleared FIRST: the sync below must not read its own gate
   s_fibPreviewObj = "";
   if(fibo == "" || ObjectFind(0, fibo) < 0) return false;
   int nl = DrawLevelCount(fibo);
   int nw = (nl > FIBPEN_MAX_LEVELS) ? FIBPEN_MAX_LEVELS : nl;
   int nU = 0;
   for(int l = 0; l < nw; l++)
   {
      int c = FibPenChildCount(fibo, l);
      if(c > 0)   // the rows the arm hid
      {
         for(int q = 0; q < c; q++)
         {
            string nm = FibPenName(fibo, l, q);
            if(ObjectFind(0, nm) < 0) continue;
            if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
            { ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS); nU++; }
         }
      }
      //--- P-DRAGF3a: and the look's own children, which the arm hid with no stack too —
      //--- an un-hide that skipped them would leave the halo invisible on every period.
      string cn = FibPenCapName(fibo, l);
      if(ObjectFind(0, cn) >= 0 && (int)ObjectGetInteger(0, cn, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
      { ObjectSetInteger(0, cn, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS); nU++; }
      string wn = FibPenWashName(fibo, l);
      if(ObjectFind(0, wn) >= 0 && (int)ObjectGetInteger(0, wn, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
      { ObjectSetInteger(0, wn, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS); nU++; }
   }
   // ONE convergence, same frame: the full-width master demotes back to 1 (the sync's
   // own guarded write), the children are re-seated at the landed anchors, the net's
   // memo re-learns the master. The caller owns the flush (the release path already
   // redraws; the button-up door flushes on this call's verdict).
   bool dirty = FibPenSync(fibo, false);
   DrawStripDiagEmit("[drawstrip] FIBPENPRE view=off fibo=\"" + fibo + "\" unhid=" + IntegerToString(nU) +
                     " sync=" + IntegerToString(dirty ? 1 : 0));
   return (nU > 0 || dirty);
}
//--- P-WARN-46 (2026-10-04): the three forward declarations that stood here went with
//--- the build's `warning 46` lines. MQL4 resolves a function defined LATER in the unit
//--- on its own; it does not for a variable, and this file reads none of those before
//--- its reader's own body (see the P-WARN-46 note in Toolbar_A.mqh for the measured
//--- precedent: EventHandlers_Router has called UIPointerOverSurface - body in a
//--- later-included file - with no prototype since P-UI-92c).
void FibPenDragFollow(const int mx, const int my)
{
   if(s_fibPreview) return;   // P-DRAGF3: the preview owns the gesture - zero writes per move
   if(s_fibDragObj == "") return;
   string fibo = s_fibDragObj;
   if(ObjectFind(0, fibo) < 0) { FibPenChaseReset(); s_fibDragObj = ""; return; }
   //--- P-UNIFY-3: the chase's law below is the HORIZONTAL fibo's. The slanted kinds
   //--- (fan, channel, expansion) hand their body to the terminal at the first drag
   //--- event (`FibPenPreviewArm`) and re-seat through the sync, so the only shape the
   //--- chase must express is still the two-anchor fibo.
   if(DrawObjectType(fibo) != OBJ_FIBO) return;
   datetime ct = 0; double cp = 0.0;
   int px_ = mx, py_ = my;   // ChartXYToTimePrice takes refs: never pass consts
   if(!ChartXYToTimePrice(0, 0, px_, py_, ct, cp)) return;
   if(!(cp > 0.0) || ct <= 0) return;
   double p1 = ObjectGetDouble(0, fibo, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, fibo, OBJPROP_PRICE, 1);
   if(!(p1 > 0.0) || !(p2 > 0.0)) return;
   datetime t1 = (datetime)ObjectGetInteger(0, fibo, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, fibo, OBJPROP_TIME, 1);
   if(t1 <= 0 || t2 <= 0) return;
   double px = FibPenPixelPrice();
   if(!(px > 0.0)) return;
   //--- (1) THE HAND'S ANCHOR, decided ONCE per gesture, by PIXELS — the question the
   //--- press can answer and a mid-gesture price compare cannot (the not-taken anchor is
   //--- the stale one, and it is the far one as soon as the hand moves).
   if(s_fibGrab < 0)
   {
      int ax = 0, ay = 0, bx = 0, by = 0;
      bool okA = ChartTimePriceToXY(0, 0, (int)t1, p1, ax, ay);
      bool okB = ChartTimePriceToXY(0, 0, (int)t2, p2, bx, by);
      if(!okA && !okB) return;
      if(okA && okB)
      {
         int dA = MathAbs(mx - ax) + MathAbs(my - ay);
         int dB = MathAbs(mx - bx) + MathAbs(my - by);
         if(dA <= FIBPEN_GRAB_PX && dA <= dB)      s_fibGrab = 0;
         else if(dB <= FIBPEN_GRAB_PX)             s_fibGrab = 1;
         else                                      s_fibGrab = FIBPEN_GRAB_BODY;
      }
      else s_fibGrab = okA ? 0 : 1;
      s_fibP0[0] = p1; s_fibP0[1] = p2;
      s_fibT0[0] = t1; s_fibT0[1] = t2;
      s_fibProbeP[0] = p1; s_fibProbeP[1] = p2;
      s_fibProbeT[0] = t1; s_fibProbeT[1] = t2;
      s_fibCurP0 = cp;
      return;   // the press frame asks; it does not move
   }
   //--- (2) A TERMINAL LANDING RESYNCS THE SNAPSHOT. The master's own truth wins and the
   //--- cursor origin moves with it, so the delta below is always "since the last time
   //--- the master agreed with itself" — never a growing error.
   if(p1 != s_fibProbeP[0] || p2 != s_fibProbeP[1] || t1 != s_fibProbeT[0] || t2 != s_fibProbeT[1])
   {
      s_fibP0[0] = p1; s_fibP0[1] = p2;
      s_fibT0[0] = t1; s_fibT0[1] = t2;
      s_fibProbeP[0] = p1; s_fibProbeP[1] = p2;
      s_fibProbeT[0] = t1; s_fibProbeT[1] = t2;
      s_fibCurP0 = cp;
   }
   //--- (3) THE GEOMETRY: the snapshot plus the hand's own delta since it. A body drag
   //--- translates the WHOLE pair (the only shape that can keep a translated drawing a
   //--- drawing); an anchor drag is a single side riding the cursor.
   //--- (3) THE GEOMETRY: the snapshot plus the hand's own delta since it. A body drag
   //--- translates the WHOLE pair (the only shape that can keep a translated drawing a
   //--- drawing); an anchor drag is a single side riding the cursor.
   //--- AND THE SPAN IS THE MASTER'S OWN (P-LOOK-RAY2). The children's TIMES are the two
   //--- anchors the master has RIGHT NOW - never an estimate: the pen must cover the span
   //--- the line covers (a level line that stops at its anchors, `levels_ray` off, would
   //--- otherwise get a pen that stops somewhere else - the very defect the mirror rule
   //--- exists to end). The PRICES ride ahead (that is the drag event's own lag, and the
   //--- reason the chase exists); the span never does.
   double dp = cp - s_fibCurP0;
   double pa = 0.0, pb = 0.0;
   if(s_fibGrab == FIBPEN_GRAB_BODY)
   {
      pa = s_fibP0[0] + dp; pb = s_fibP0[1] + dp;
   }
   else if(s_fibGrab == 0)
   {
      pa = cp;            pb = s_fibP0[1];
   }
   else
   {
      pa = s_fibP0[0];    pb = cp;
   }
   if(!(pa > 0.0) || !(pb > 0.0)) return;
    datetime ta = t1, tb = t2;
    datetime ts0 = (ta < tb ? ta : tb);   // P-LOOK-RAY5b: rows ride ordered time, even mid-gesture
    datetime ts1 = (ta < tb ? tb : ta);
   int nl = DrawLevelCount(fibo);
   if(nl <= 0) return;
   int nw = (nl > FIBPEN_MAX_LEVELS) ? FIBPEN_MAX_LEVELS : nl;
   int nMov = 0;
   for(int l = 0; l < nw; l++)
   {
      string c0 = FibPenName(fibo, l, 0);
      string cpnm = FibPenCapName(fibo, l);
      string wsnm = FibPenWashName(fibo, l);
      if(ObjectFind(0, c0) < 0 && ObjectFind(0, cpnm) < 0 &&
         ObjectFind(0, wsnm) < 0) continue;
      double v = ObjectGetDouble(0, fibo, OBJPROP_LEVELVALUE, l);
      if(!MathIsValidNumber(v)) continue;
      double lva = pb + (pa - pb) * v;   // P-LOOK-ANCHOR: 0 % at the SECOND anchor (the terminal's law)
      if(!(lva > 0.0)) continue;
      int logical = FibPenLogicalWidth(fibo, l);
      for(int q = 0; q < logical && q <= DRAW_WIDTH_MAX; q++)
      {
         string nm = FibPenName(fibo, l, q);
         if(ObjectFind(0, nm) < 0) break;
          double rowP = lva + FibPenOffPx(logical, q) * px;
          if(ObjectGetDouble(0, nm, OBJPROP_PRICE, 0) != rowP)
          { ObjectMove(0, nm, 0, ts0, rowP); nMov++; }
          if(ObjectGetDouble(0, nm, OBJPROP_PRICE, 1) != rowP)
          { ObjectMove(0, nm, 1, ts1, rowP); nMov++; }
      }
       if(ObjectFind(0, cpnm) >= 0)
       {
          datetime tc = tb - (tb - ta) / 8;
          if(!(tc > ta)) tc = ta;
          if(ObjectGetDouble(0, cpnm, OBJPROP_PRICE, 0) != lva)
          { ObjectMove(0, cpnm, 0, tc, lva); nMov++; }
          if(ObjectGetDouble(0, cpnm, OBJPROP_PRICE, 1) != lva)
          { ObjectMove(0, cpnm, 1, tb, lva); nMov++; }
       }
        if(ObjectFind(0, wsnm) >= 0)
        {
           double hp = lva + 2.0 * px;
           if(ObjectGetDouble(0, wsnm, OBJPROP_PRICE, 0) != hp)
           { ObjectMove(0, wsnm, 0, ts0, hp); nMov++; }
           if(ObjectGetDouble(0, wsnm, OBJPROP_PRICE, 1) != hp)
           { ObjectMove(0, wsnm, 1, ts1, hp); nMov++; }
        }
     }
   //--- (4) THE FRAME THE CHASE MOVED IS THE FRAME IT PAINTS. The DRAG channel flushes
   //--- its own frame (P-DRAW-74b-f); the MOVE channel is this one's only painter, and
   //--- without a flush the children wait for the terminal's own next repaint — the
   //--- "one frame behind" the flush law exists to end. A still frame moves nothing and
   //--- therefore repaints nothing.
   if(nMov > 0) ChartRedraw();
   //--- DIAG-139/141: same sampled witness as the sync — one line per second max, and it
   //--- now names the CHANNEL's own answer: which anchor the hand took and the delta it is
   //--- being carried by, so the next drag reports its case instead of asking for one.
   if(nMov > 0)
   {
      uint nowMs = GetTickCount();
      if(nowMs - s_fibMovMs > 1000 || nowMs < s_fibMovMs)
      {
         s_fibMovMs = nowMs;
         DrawStripDiagEmit("[drawstrip] FIBPENMOV fibo=\"" + fibo + "\" moved=" + IntegerToString(nMov) +
                           " ta=" + IntegerToString((long)ta) + " tb=" + IntegerToString((long)tb) +
                           " p1=" + DoubleToString(pa, _Digits) + " p2=" + DoubleToString(pb, _Digits) +
                           " g=" + IntegerToString(s_fibGrab) + " dp=" + DoubleToString(dp, _Digits) +
                           " s=" + IntegerToString((int)GetTickCount()));
      }
   }
}
//--- the second family test: caps, wash and shadow strays are served never, like the stack's.
bool FibPenFamIsChild(const string name)
{
   int pos = 0;
   while(true)
   {
      int at = StringFind(name, "_FS", pos);
      if(at < 0) return false;
      string rest = StringSubstr(name, at + 3);
      bool ok = (StringLen(rest) > 1);
      if(ok)
      {
         ushort fc = StringGetCharacter(rest, 0);
         if(fc != 'C' && fc != 'W' && fc != 'H') ok = false;
         else
         {
            for(int i = 1; i < StringLen(rest); i++)
            {
               ushort ch = StringGetCharacter(rest, i);
               if(ch < '0' || ch > '9') { ok = false; break; }
            }
         }
      }
      if(ok) return true;
      pos = at + 1;
   }
   return false;
}

int FibPenCount(const int w) { return (w < 2 ? 0 : (w > DRAW_WIDTH_MAX ? DRAW_WIDTH_MAX - 1 : w - 1)); }
string FibPenName(const string f, const int dl, const int dq)
{ return f + FIBPEN_SUFFIX + IntegerToString(dl) + "." + IntegerToString(dq); }

//--- the leftover test: the suffix sits BEFORE the "<level>.<q>" tail, never
//--- at the end (the old test matched the last chars, so no child was ever
//--- one: each stacked line was served, hit and learned as a drawing of its
//--- own). `DrawKindOf` answers DK_NONE for one, so nothing serves, hits or
//--- learns a child.
bool FibPenIsChild(const string name)
{
   int s = StringLen(FIBPEN_SUFFIX);
   int pos = 0;
   while(true)
   {
      int at = StringFind(name, FIBPEN_SUFFIX, pos);
      if(at < 0) return false;
      string rest = StringSubstr(name, at + s);
      bool ok = (StringLen(rest) > 0);
      int dot = -1;
      for(int i = 0; i < StringLen(rest); i++)
      {
         ushort ch = StringGetCharacter(rest, i);
         if(ch == '.') { if(dot >= 0) { ok = false; break; } dot = i; continue; }
         if(ch < '0' || ch > '9') { ok = false; break; }
      }
      if(ok && dot > 0 && dot < StringLen(rest) - 1) return true;
      pos = at + 1;
   }
   return false;
}

//--- how many children level dl carries (contiguous from q=0).
int FibPenChildCount(const string f, const int dl)
{
   int c = 0;
   for(int q = 0; q < DRAW_WIDTH_MAX; q++)
   {
      if(ObjectFind(0, FibPenName(f, dl, q)) < 0) break;
      c++;
   }
   return c;
}

//--- the remembered width of one level: 1 + children while demoted, else the line's own.
int FibPenLogicalWidth(const string fibo, const int lvl)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) return DRAW_WIDTH_MIN;
   int w = (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELWIDTH, lvl);
   if(w < DRAW_WIDTH_MIN) w = DRAW_WIDTH_MIN;
   if(w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MAX;
   if(w == DRAW_WIDTH_MIN)
   {
      int c = FibPenChildCount(fibo, lvl);
      if(c > 0)
      {
         //--- a neon core (solid) is the tube, not thickness: counting it would
         //--- grow the stack by one on every sync. Children are contiguous, so
         //--- the top one tells.
         int lg = 1 + c;
         string top = FibPenName(fibo, lvl, c - 1);
         if((int)ObjectGetInteger(0, top, OBJPROP_STYLE) == (int)STYLE_SOLID) lg = c;
         if(lg < DRAW_WIDTH_MIN) lg = DRAW_WIDTH_MIN;
         if(lg > DRAW_WIDTH_MAX) lg = DRAW_WIDTH_MAX;
         return lg;
      }
   }
   return w;
}

//--- ONE pixel's worth of price, from the chart's OWN scale.
double FibPenPixelPrice()
{
   int    h  = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   double hi = ChartGetDouble(0, CHART_PRICE_MAX);
   double lo = ChartGetDouble(0, CHART_PRICE_MIN);
   if(h <= 0 || !(hi > lo)) return 0.0;
   double px = (hi - lo) / (double)h;
   return (MathIsValidNumber(px) && px > 0.0) ? px : 0.0;
}

//--- centred offsets in px, inner first: 2:[+1] 3:[-1,+1] 4:[-1,+1,+2] 5:[-1,+1,-2,+2].
int FibPenOffPx(const int w, const int q)
{
   int half = (w - 1) / 2;
   int idx = q;
   for(int d = 1; d <= half; d++)
   {
      if(idx == 0) return -d;
      idx--;
      if(idx == 0) return d;
      idx--;
   }
   if(w % 2 == 0 && idx == 0) return half + 1;
   return 0;
}

//--- spend a v2 [FWn]: truth is explicit again since widths live in the stack,
//--- so the tag would lie. Guarded: one TEXT read, a write only when present.
bool FibPenTagDrop(const string fibo)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) return false;
   string d = ObjectGetString(0, fibo, OBJPROP_TEXT);
   int at = StringFind(d, FIBPEN_TAG);
   if(at < 0) return false;
   int e = StringFind(d, "]", at + StringLen(FIBPEN_TAG));
   if(e <= at) return false;
   string nd = StringSubstr(d, 0, at) + StringSubstr(d, e + 1);
   if(StringLen(nd) > 0 && StringGetCharacter(nd, 0) == ' ') nd = StringSubstr(nd, 1);
   if(nd == d) return false;
   ObjectSetString(0, fibo, OBJPROP_TEXT, nd);
   return true;
}

//--- P-LOOK-RAY3 (2026-10-04) — THE PEN'S SPAN IS MT4'S SPAN, AND MT4 WILL NOT TELL US.
//---
//--- P-LOOK-RAY2 believed the master's OWN ray pair (`OBJPROP_RAY_LEFT/RIGHT`) was the
//--- fibo's level ray, and mirrored it onto every row of the pen. MEASURED FALSE on the
//--- hand's own chart, 2026-10-04 12:08 (EURUSD M1, AMarkets demo): the four level lines
//--- run edge to edge — x=250..1863, one 1 px dash-dot-dot row each — while the two rows the
//--- pen stacks beside them stop dead at x=595, the second anchor, which is the report
//--- («چرا امتداد خط ها استایل اعمال نشده باید همه جا باشه دیگه»). Counted, not
//--- eyeballed: between the anchors each level occupies rows 292..294 (level + 2 pen rows);
//--- past x=580 only row 293 survives — the master ran on to the chart edge, the pen did
//--- not, so the extension wore no thickness at all.
//---
//--- WHY the mirror read false every single time: on OBJ_FIBO that pair is NOT the level
//--- ray. MT4 keeps the level ray in a field of its own — the chart's own file stores
//--- `levels_ray=0` for a fibo and writes NO `ray=` entry for it at all, while the pen's
//--- rows (type=2, OBJ_TREND) carry `ray=1` — and MQL4 exposes nothing that reads or writes
//--- it: `ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false)` does NOT stop a fibo's levels
//--- from reaching the right chart edge (mql5.com/forum/164640, MT4 build 1030+: "it always
//--- stretch the fibo retracement to right end of the chart"). A read that can only ever
//--- answer false is not a mirror, it is a trimmer: the pen was shortened to the anchors
//--- while the line it belongs to went on.
//---
//--- So the truth is not a flag we own but a SHAPE MT4 draws: a fibo's level lines run from
//--- the FIRST anchor to the RIGHT edge of the chart, and never to the left (measured on
//--- the same frame: they begin at x=250 while the chart's own left edge is x=48). The pen
//--- states that shape instead of guessing it — right on, left off, on every dash row, the
//--- neon core and the wash halo, at birth and on every heal. One shape, one law: the
//--- style is the line's style WHEREVER THE LINE GOES, which is the whole of the report.
//---
//--- P-LOOK-RAY4 (2026-10-04 14:27) — THE RAY TURNS WITH THE ANCHORS. RAY3 measured that
//--- shape on a FORWARD-drawn fibo; the hand then dragged point0 past point1 (diag:
//--- FIBPENMOV ta=1790975520 > tb=1790973360) and the run fled the wrong way («این امتداد
//--- به عقب و جلو چرا استایل و ضخامت نمیگیره»). Measured on that frame, pixel by pixel:
//--- the children sit at ±1/±2 px and NEVER on the level's own row, so the centre row IS
//--- MT4's own line — centre 0.01 left of the earlier anchor (x=648) against 0.62 from it
//--- to the right edge, while the pen's ring rows read 0.63 left of 648 (hanging in empty
//--- space) and 0.00 right of point0 (the bare extension). So MT4's law, in both orders:
//--- the level line runs from the EARLIER anchor to the right chart edge, never left of
//--- it — and MT4's OBJ_TREND rays are DIRECTIONAL (RAY_RIGHT extends past point1 ALONG
//--- point0→point1, RAY_LEFT past point0 against it), so "right on, left off" is only
//--- right while t0 <= t1. The pen states the shape in both orders: EXACTLY ONE ray is
//--- on, always the RIGHTWARD one — forward anchors carry it on RAY_RIGHT, reversed
//--- anchors on RAY_LEFT. One shape, one law, both ways: the style and the thickness the
//--- hand chose ride the line WHEREVER THE LINE GOES.
//--- P-LOOK-RAY5 (2026-10-04) — BOTH EXTENSIONS WEAR IT. The hand's own two frames
//--- (EURUSD M1: the middle thick, BOTH extensions thin — «امتداد به عقب و جلو چرا
//--- استایل و ضخامت نمیگیره») show the master spanning the FULL width both ways, so
//--- the one-ray law always left one side bare. The pen states BOTH rays on, in both
//--- anchor orders. No flag is read (RAY3 stands); no single-ray branch (RAY4 retires).
//--- P-LOOK-RAY5b (2026-10-04) — THE CHILDREN WEAR ORDERED TIME. Both rays on was
//--- not enough: MEASURED on the hand's next frame (EURUSD M1, diag `Fibo 11855`
//--- `rays=3 ta=1790979000 tb=1790978280`) the pen covered the left edge to the late
//--- anchor while the right extension stayed bare. MT4 extends a trend ray past the
//--- side its own order names — children born with the master's REVERSED order keep
//--- only one extension. So every rayed row is seated early→late (`ts0/ts1`), the one
//--- order MT4 extends both ways from; the master's own anchors are never reordered,
//--- only the rows the pen owns. First pass after load re-seats every row (fresh memo).
void FibPenRayPair(const string fibo, bool &rl, bool &rr)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) { rl = false; rr = false; return; }
   rl = true;    // P-LOOK-RAY5: the backward extension wears the style too
   rr = true;    // P-LOOK-RAY5: ...and the forward one — full width, both anchor orders
}
int FibPenRayBits(const string fibo)
{
   bool rl = false, rr = false;
   FibPenRayPair(fibo, rl, rr);
   return (rl ? 2 : 0) | (rr ? 1 : 0);
}
//--- the pen's own existence test: any of the families it builds — the retired
//--- `_FSH` still counts, or a legacy 3D shadow would never reach its own sweep.
bool FibPenHasPen(const string fibo)
{
   if(fibo == "") return false;
   if(ObjectFind(0, FibPenName(fibo, 0, 0)) >= 0) return true;
   if(ObjectFind(0, FibPenCapName(fibo, 0)) >= 0) return true;
   if(ObjectFind(0, FibPenWashName(fibo, 0)) >= 0) return true;
   if(ObjectFind(0, FibPenShwName(fibo, 0)) >= 0) return true;
   return false;
}
//--- P-LOOK-RAY2 - THE PEN'S OWN NET. Every other follower in this repo has one seat that
//--- needs no event (the box's interior and its 50 % line ride the 2 s chart-side pass,
//--- P-DRAW-64 / addendum 5). The pen had only EVENT paths - open, route, tap, undo,
//--- release, OBJECT_DRAG/CHANGE - so when the terminal landed the master's final anchors
//--- AFTER the last of those events, nothing ever re-anchored the children: the stale pen
//--- measured above was hours old, not a frame (its right anchor still named the anchor
//--- the fibo had one drag earlier). The 2 s pass (`DrawStrip_Pick` - it already pays one
//--- type read per object) now asks each fibo THE question: "is the pen still the one your
//--- master would build?" - one probe, four anchor reads, one ray read and one memo
//--- compare while healthy; only a MISMATCH pays the sync (which re-anchors the rows,
//--- mirrors the rays and re-memoizes). A still chart pays reads and writes nothing.
#define FIBPEN_NET_SLOTS 8
static string s_fpNetName[FIBPEN_NET_SLOTS];
static long   s_fpNetT0[FIBPEN_NET_SLOTS], s_fpNetT1[FIBPEN_NET_SLOTS], s_fpNetT2[FIBPEN_NET_SLOTS];
static double s_fpNetP0[FIBPEN_NET_SLOTS], s_fpNetP1[FIBPEN_NET_SLOTS], s_fpNetP2[FIBPEN_NET_SLOTS];
static int    s_fpNetRay[FIBPEN_NET_SLOTS], s_fpNetPen[FIBPEN_NET_SLOTS];
static int    s_fpNetNext = 0;
int FibPenNetFind(const string fibo)
{
   if(fibo == "") return -1;
   for(int i = 0; i < FIBPEN_NET_SLOTS; i++)
      if(s_fpNetName[i] == fibo) return i;
   return -1;
}
//--- P-UNIFY-3: the memo carries the THIRD anchor too — a channel's width anchor or an
//--- expansion's third point is geometry the rows hang on, so a move of it alone must
//--- read as a mismatch (0/0 on the two-anchor kinds keeps one compare shape).
void FibPenNetWrite(const string fibo, const long t0, const long t1, const long t2,
                    const double p0, const double p1, const double p2,
                    const int ray, const bool pen)
{
   int at = FibPenNetFind(fibo);
   if(at < 0)
   {
      at = s_fpNetNext;
      s_fpNetNext = (s_fpNetNext + 1) % FIBPEN_NET_SLOTS;
      s_fpNetName[at] = fibo;
   }
   s_fpNetT0[at] = t0; s_fpNetT1[at] = t1; s_fpNetT2[at] = t2;
   s_fpNetP0[at] = p0; s_fpNetP1[at] = p1; s_fpNetP2[at] = p2;
   s_fpNetRay[at] = ray;
   s_fpNetPen[at] = (pen ? 1 : 0);
}
bool FibPenHeal(const string fibo)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) return false;
   if(s_fibPreview && fibo == s_fibPreviewObj) return false;   // P-DRAGF3: the preview owns the gesture
   int ty = DrawObjectType(fibo);
   if(!FibPenServesType(ty)) return false;   // P-UNIFY-3: the heal, the pen's own four
   long   t0 = (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 0);
   long   t1 = (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 1);
   double p0 = ObjectGetDouble(0, fibo, OBJPROP_PRICE, 0);
   double p1 = ObjectGetDouble(0, fibo, OBJPROP_PRICE, 1);
   bool three = (ty == OBJ_FIBOCHANNEL || ty == OBJ_EXPANSION);
   long   t2 = three ? (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 2) : 0;
   double p2 = three ? ObjectGetDouble(0, fibo, OBJPROP_PRICE, 2) : 0.0;
   int    ray = FibPenRayBits(fibo);
   bool   pen = FibPenHasPen(fibo);
   int    at  = FibPenNetFind(fibo);
   if(at >= 0 && s_fpNetT0[at] == t0 && s_fpNetT1[at] == t1 && s_fpNetT2[at] == t2 &&
      s_fpNetP0[at] == p0 && s_fpNetP1[at] == p1 && s_fpNetP2[at] == p2 &&
      s_fpNetRay[at] == ray && s_fpNetPen[at] == (pen ? 1 : 0))
      return false;   // the pen is what the master's last sync built: reads only
   return FibPenSync(fibo, false);
}
//--- the pen's children answer for their own parent (the sweep's orphan rule, the same
//--- shape the interior's and the 50 % line's already have): a reload while a fibo was
//--- deleted must not leave a styled band hanging on nothing.
string FibPenChildParent(const string name)
{
   int cut = -1;
   for(int i = 0; i + 3 < StringLen(name); i++)
      if(StringGetCharacter(name, i) == '_' &&
         StringGetCharacter(name, i + 1) == 'F' &&
         StringGetCharacter(name, i + 2) == 'S') cut = i;
   if(cut <= 0) return "";
   return StringSubstr(name, 0, cut);
}
//--- the FIBPEN witness channel (PathTool.mqh:31 is the precedent): Full borrows
//--- the strip's flushed file; Lite ships no strip, so MQL4's no-body rule
//--- (error 111) needs the journal fallback defined HERE, in the caller file.
#ifndef BUILD_LITE
//--- P-WARN-46 (2026-10-04): no prototype owed - `DrawStripDiagEmit`'s body is in this
//--- unit (DrawStrip_Base.mqh) and MQL4 resolves it.
#else
void DrawStripDiagEmit(const string line) { Print(line); }
#endif

//--- name-keyed sweep for the delete hub (DrawStrip_Router): the object is gone,
//--- so no kind check — names this unit never built simply probe absent. The ONE
//--- sweep; the sync's delete path calls it instead of keeping a second copy.
//---
//--- P-LOOK-3D-f (2026-10-22) — ONE PREFIX, FOUR FAMILIES, NO GAP. The sweep was
//--- a walk of `dl = 0..11` that asked `q = 0,1,2…` and STOPPED at the first absent
//--- name, then probed `_FSC`/`_FSW`/`_FSH` per level. Two holes in that shape: a
//--- stack whose q=0 was already gone (or whose only child sat on level 3 while
//--- level 0 carried none) broke the walk early, and the strays behind the gap
//--- survived every delete — the class P-ORPHAN-ALL was written for. Every name
//--- this unit builds starts with `<master>_FS` (`_FSD` stack rows, `_FSC` caps,
//--- `_FSW` wash, `_FSH` the retired shadow), so ONE prefix delete answers for all
//--- four, covers any gap, and costs one object-list pass instead of ~100 probes.
//--- The child guard stays: a CHILD's delete must never walk its master's sweep
//--- (measured 1000-7125 ms per event before it, P-DRAW-74b).
bool FibPenStraysDrop(const string fibo)
{
   if(fibo == "") return false;
   if(FibPenChildParent(fibo) != "") return false;
   return (ObjectsDeleteAll(0, fibo + "_FS") > 0);
}

//--- the ONE sync: demotes the undrawable width, builds / refreshes / drops
//--- each level's stack in the level's own style and ink. Guarded throughout:
//--- a still frame pays reads, writes nothing. dropAll is the delete path.
bool FibPenSync(const string fibo, const bool dropAll)
{
   if(fibo == "" || ObjectFind(0, fibo) < 0) return false;
   if(DrawIsIndicatorObject(fibo)) return false;   // the indicator's own levels are never served
   if(s_fibPreview && !dropAll && fibo == s_fibPreviewObj) return false;   // P-DRAGF3: gated while the preview owns the gesture; dropAll (delete) is never gated
   EDrawKind k = DrawKindOf(fibo);
   if(!FibPenServesType(DrawObjectType(fibo))) return false;   // P-UNIFY-3: the pen's four kinds — the kind carries the geometry
   bool dirty = FibPenTagDrop(fibo);   // transition: spend a v2 [FWn], never written again
   int nDem = 0, nNew = 0, nDrop = 0, nUni = 0;   // the flushed witness counts below
   int nMov = 0;   // DIAG-139: child moves this call (the drag question below)
   bool coreN[FIBPEN_MAX_LEVELS] = {false, false, false, false, false, false, false, false, false, false, false, false};
   color wbg = GetCachedChartBgColor();
   int lk = FibPenLookGet(fibo);
   if(lk > 0 && (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELSTYLE, 0) != FibPenLookNative(lk))
   {
      FibPenLookDrop(fibo);   // the MT4 dialog wrote native: one truth, not two
      lk = 0;
   }
   int nl = DrawLevelCount(fibo);
   int nw = (nl > FIBPEN_MAX_LEVELS) ? FIBPEN_MAX_LEVELS : nl;
   if(nw <= 0 || dropAll)
   {
      // P-LOOK: every family the unit ever built dies here — a look switch strands
      // the previous look's children, and only this sweep can name them all.
      //--- P-LOOK-3D-f (2026-10-22): the fence that stood here asked LEVEL 0 for
      //--- four names and returned early when it found none. A stack lives on the
      //--- level that NEEDED it, so a fibo whose level 3 wore a thick non-solid pen
      //--- had no level-0 child: the sweep never ran, the strays stayed for good,
      //--- and the early return also skipped the memo write below — the 2 s net then
      //--- read "pen=0 vs memo=1" on every pass and re-synced the same dead pen
      //--- forever (a mismatch it could never settle). The sweep IS the probe now:
      //--- one prefix call answers for the whole family, and every exit writes the
      //--- memo, so the net settles on the first pass.
      bool dd = FibPenStraysDrop(fibo);
      if(dd || dirty)
         DrawStripDiagEmit("[drawstrip] FIBPEN fibo=\"" + fibo + "\" dropall=1 look=" + IntegerToString(lk));
      //--- P-LOOK-RAY2: the net's memo follows the truth - no pen stands here now, so the
      //--- next pass asks the master (and only a master that asks for one is served).
      //--- P-UNIFY-3: the third anchor rides the memo too (0/0 on the two-anchor kinds).
      bool three = (k == DK_FIBOCHAN || k == DK_EXPANSION);
      FibPenNetWrite(fibo, (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 0),
                     (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 1),
                     three ? (long)ObjectGetInteger(0, fibo, OBJPROP_TIME, 2) : 0,
                     ObjectGetDouble(0, fibo, OBJPROP_PRICE, 0),
                     ObjectGetDouble(0, fibo, OBJPROP_PRICE, 1),
                     three ? ObjectGetDouble(0, fibo, OBJPROP_PRICE, 2) : 0.0,
                     FibPenRayBits(fibo), false);
      return (dd || dirty);
   }
   double px = FibPenPixelPrice();
   bool pxOk = (px > 0.0);
   //--- P-LOOK-ALL (2026-10-03) — ONE fibo, ONE look. MT4 lets every level wear
   //--- its own width and style (the dialog edits one level at a time), so a fibo
   //--- arrives mixed and the strip can only show — and keep — level 0's. The
   //--- reference IS level 0 (what the strip displays); every other level is
   //--- converged onto it through the same demote/stack flow. Guarded: a uniform
   //--- fibo pays reads, writes nothing.
   int refSt = (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELSTYLE, 0);
   if(refSt < (int)STYLE_SOLID || refSt > (int)STYLE_DASHDOTDOT) refSt = (int)STYLE_SOLID;
   int refLog = FibPenLogicalWidth(fibo, 0);
    datetime ta = (datetime)ObjectGetInteger(0, fibo, OBJPROP_TIME, 0);
    datetime tb = (datetime)ObjectGetInteger(0, fibo, OBJPROP_TIME, 1);
    datetime ts0 = (ta < tb ? ta : tb);   // P-LOOK-RAY5b: the rows' span is ordered
    datetime ts1 = (ta < tb ? tb : ta);   // ...early to late, whatever order the hand drew
   double p1 = ObjectGetDouble(0, fibo, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, fibo, OBJPROP_PRICE, 1);
   //--- P-UNIFY-3: the channel and the expansion carry a THIRD anchor, and their level
   //--- geometry hangs on it (the channel's width, the expansion's base). Missing it is
   //--- as fatal as a missing pair, so it is part of the same fence.
   bool three = (k == DK_FIBOCHAN || k == DK_EXPANSION);
   datetime t3 = three ? (datetime)ObjectGetInteger(0, fibo, OBJPROP_TIME, 2) : 0;
   double   p3 = three ? ObjectGetDouble(0, fibo, OBJPROP_PRICE, 2) : 0.0;
   bool anchorsOk = (ta > 0 && tb > 0 && p1 > 0.0 && p2 > 0.0 &&
                     (!three || (t3 > 0 && p3 > 0.0)));
   //--- P-LOOK-ANCHOR (2026-10-18) — MT4 PUTS 0 % AT THE SECOND ANCHOR. MEASURED on the
   //--- shot chart (StripShot_fibo_3d3.png, AMarkets A1660): the band carrying the «0.0»
   //--- label sits at PRICE,1 (y=445) and «423.6» at PRICE,1 + (PRICE,0 - PRICE,1) * 4.236
   //--- = 1.11605 (y=633) — label text and pixels agree within 1 px across all nine bands,
   //--- and the FSH family dump sits exactly where its own prices say. So the terminal's
   //--- law is lv = PRICE,1 + (PRICE,0 - PRICE,1) * v, and the old p1 + (p2 - p1) * v wore
   //--- the mirror twin R(1 - v): every child (stack rows, caps, wash) sat under the
   //--- wrong level — the «3D واقعی نیست» report, whose 3D shadow measured at 305/376/420
   //--- (since retired) — and both hit tests (DrawHitLevels, DrawFiboFullHit) measured
   //--- lines MT4 never draws. Every mapping site states THIS law: this head, the chase,
   //--- caps, wash, and the two hit tests. Gate: P-LOOK-ANCHOR.
   //--- P-LOOK-RAY2: the pen mirrors the master's own level rays (one read per sync).
   bool penRL = false, penRR = false;
   FibPenRayPair(fibo, penRL, penRR);
   int backLayer = (int)ObjectGetInteger(0, fibo, OBJPROP_BACK);
   bool need[FIBPEN_MAX_LEVELS] = {false, false, false, false, false, false, false, false, false, false, false, false};
   int wantN[FIBPEN_MAX_LEVELS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
   int logW[FIBPEN_MAX_LEVELS] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
   int styA[FIBPEN_MAX_LEVELS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
   color colA[FIBPEN_MAX_LEVELS] = {clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE, clrNONE};
   datetime t1a[FIBPEN_MAX_LEVELS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
   datetime t2a[FIBPEN_MAX_LEVELS] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
   double lva[FIBPEN_MAX_LEVELS] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
   double lvb[FIBPEN_MAX_LEVELS] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
   for(int l = 0; l < nw; l++)
   {
      int curW = (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELWIDTH, l);
      int curSt = (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELSTYLE, l);
      if(curW < DRAW_WIDTH_MIN) curW = DRAW_WIDTH_MIN;
      if(curW > DRAW_WIDTH_MAX) curW = DRAW_WIDTH_MAX;
      if(curSt != refSt)
      {
         ObjectSetInteger(0, fibo, OBJPROP_LEVELSTYLE, l, refSt);
         dirty = true; nUni++;
         curSt = refSt;
      }
      bool rowOk = false;
      double lvA = 0.0, lvB = 0.0;
      if(anchorsOk)
      {
         double v = ObjectGetDouble(0, fibo, OBJPROP_LEVELVALUE, l);
         if(MathIsValidNumber(v))
         {
            //--- P-UNIFY-3: the two ends are the KIND's geometry (DrawLevelPriceAt).
            //--- DK_FIBO answers the same constant price at both — P-LOOK-ANCHOR's law.
            lvA = DrawLevelPriceAt(k, v, ta, p1, tb, p2, t3, p3, ts0);
            lvB = DrawLevelPriceAt(k, v, ta, p1, tb, p2, t3, p3, ts1);
            if(lvA > 0.0 && lvB > 0.0) rowOk = true;
         }
      }
      int want = 0, vis = curW;
      if(rowOk && pxOk)
      {
         vis = (refSt != (int)STYLE_SOLID && refLog > DRAW_WIDTH_MIN) ? DRAW_WIDTH_MIN : refLog;
         want = (refSt != (int)STYLE_SOLID && refLog > DRAW_WIDTH_MIN) ? refLog - 1 : 0;
      }
      if(curW != vis)
      {
         ObjectSetInteger(0, fibo, OBJPROP_LEVELWIDTH, l, vis);
         dirty = true; nDem++;
      }
      need[l] = (want > 0);
      wantN[l] = want;
      logW[l] = refLog;
      styA[l] = refSt;
       colA[l] = (color)(int)ObjectGetInteger(0, fibo, OBJPROP_LEVELCOLOR, l);
       t1a[l] = ts0;
       t2a[l] = ts1;
       lva[l] = lvA;
       lvb[l] = lvB;
   }
   //--- levels past the stack cap converge the same way (thin dash), never stack.
   for(int lx = nw; lx < nl; lx++)
   {
      int wX = (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELWIDTH, lx);
      int sX = (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELSTYLE, lx);
      if(sX != refSt)
      {
         ObjectSetInteger(0, fibo, OBJPROP_LEVELSTYLE, lx, refSt);
         dirty = true; nUni++;
      }
      int visX = wX;
      if(pxOk) visX = (refSt != (int)STYLE_SOLID && refLog > DRAW_WIDTH_MIN) ? DRAW_WIDTH_MIN : refLog;
      if(wX != visX)
      {
         ObjectSetInteger(0, fibo, OBJPROP_LEVELWIDTH, lx, visX);
         dirty = true; nDem++;
      }
   }
   for(int l2 = 0; l2 < nw; l2++)
   {
      if(!need[l2]) continue;
      for(int q2 = 0; q2 < wantN[l2]; q2++)
      {
         string nm2 = FibPenName(fibo, l2, q2);
         //--- P-UNIFY-3: the offset is vertical in PRICE, so each end rides its own
         //--- level price — identical on a horizontal fibo, parallel on the slanted kinds.
         double rowPa = lva[l2] + FibPenOffPx(logW[l2], q2) * px;
         double rowPb = lvb[l2] + FibPenOffPx(logW[l2], q2) * px;
         if(ObjectFind(0, nm2) < 0)
         {
            if(!pxOk) continue;
            if(!ObjectCreate(0, nm2, OBJ_TREND, 0, t1a[l2], rowPa, t2a[l2], rowPb)) continue;
            ObjectSetInteger(0, nm2, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, nm2, OBJPROP_HIDDEN, true);
            // P-LOOK-RAY2: the pen is as wide as the LINE, not wider. The fibo's own
            // level-ray pair is read once above; a level line that stops at its anchors
            // gets a pen that stops with it, one that runs edge to edge gets a pen that
            // does the same.
            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);
            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);
            dirty = true; nNew++;
         }
         if(pxOk)
         {
            if((datetime)ObjectGetInteger(0, nm2, OBJPROP_TIME, 0) != t1a[l2] ||
               ObjectGetDouble(0, nm2, OBJPROP_PRICE, 0) != rowPa)
               { ObjectMove(0, nm2, 0, t1a[l2], rowPa); nMov++; }
            if((datetime)ObjectGetInteger(0, nm2, OBJPROP_TIME, 1) != t2a[l2] ||
               ObjectGetDouble(0, nm2, OBJPROP_PRICE, 1) != rowPb)
               { ObjectMove(0, nm2, 1, t2a[l2], rowPb); nMov++; }
         }
         if((int)ObjectGetInteger(0, nm2, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)
            ObjectSetInteger(0, nm2, OBJPROP_WIDTH, DRAW_WIDTH_MIN);
         if((int)ObjectGetInteger(0, nm2, OBJPROP_STYLE) != styA[l2])
            ObjectSetInteger(0, nm2, OBJPROP_STYLE, styA[l2]);
         if((color)(int)ObjectGetInteger(0, nm2, OBJPROP_COLOR) != colA[l2])
            ObjectSetInteger(0, nm2, OBJPROP_COLOR, colA[l2]);
         if((int)ObjectGetInteger(0, nm2, OBJPROP_BACK) != backLayer)
            ObjectSetInteger(0, nm2, OBJPROP_BACK, backLayer);
         // P-LOOK-RAY2: heal the mirror - guarded, and in BOTH directions, because a
         // fibo whose levels ray was turned off must take its pen back to the anchors
         // (the case the old heal could not express: it only ever raised).
         if(((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_LEFT) != 0) != penRL)
            ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT, penRL);
         if(((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_RIGHT) != 0) != penRR)
            ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, penRR);
      }
   }
   //--- P-LOOK — NEON core: one solid light tube at the level's own price.
   //--- Only a band 3+ wide has room for a tube; the dash edges keep the level's ink.
   for(int l3 = 0; l3 < nw; l3++)
   {
      coreN[l3] = false;
      if(lk != FIBPEN_LOOK_NEON || !need[l3] || logW[l3] < 3) continue;
      string cnm = FibPenName(fibo, l3, wantN[l3]);
      color lite = BlendColorTowardsBG(colA[l3], 50, clrWhite);
      if(ObjectFind(0, cnm) < 0)
      {
            if(!ObjectCreate(0, cnm, OBJ_TREND, 0, t1a[l3], lva[l3], t2a[l3], lvb[l3])) continue;
            ObjectSetInteger(0, cnm, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, cnm, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, cnm, OBJPROP_RAY_LEFT, penRL);   // P-LOOK-RAY2: the tube rides the line's own span
            ObjectSetInteger(0, cnm, OBJPROP_RAY_RIGHT, penRR);
         dirty = true; nNew++;
      }
      if((datetime)ObjectGetInteger(0, cnm, OBJPROP_TIME, 0) != t1a[l3] ||
            ObjectGetDouble(0, cnm, OBJPROP_PRICE, 0) != lva[l3])
            { ObjectMove(0, cnm, 0, t1a[l3], lva[l3]); nMov++; }
      if((datetime)ObjectGetInteger(0, cnm, OBJPROP_TIME, 1) != t2a[l3] ||
            ObjectGetDouble(0, cnm, OBJPROP_PRICE, 1) != lvb[l3])
            { ObjectMove(0, cnm, 1, t2a[l3], lvb[l3]); nMov++; }
      if((int)ObjectGetInteger(0, cnm, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)
         ObjectSetInteger(0, cnm, OBJPROP_WIDTH, DRAW_WIDTH_MIN);
      if((int)ObjectGetInteger(0, cnm, OBJPROP_STYLE) != (int)STYLE_SOLID)
         ObjectSetInteger(0, cnm, OBJPROP_STYLE, STYLE_SOLID);
      if((color)(int)ObjectGetInteger(0, cnm, OBJPROP_COLOR) != lite)
         ObjectSetInteger(0, cnm, OBJPROP_COLOR, lite);
      if((int)ObjectGetInteger(0, cnm, OBJPROP_BACK) != backLayer)
         ObjectSetInteger(0, cnm, OBJPROP_BACK, backLayer);
      if(((int)ObjectGetInteger(0, cnm, OBJPROP_RAY_LEFT) != 0) != penRL)
         ObjectSetInteger(0, cnm, OBJPROP_RAY_LEFT, penRL);
      if(((int)ObjectGetInteger(0, cnm, OBJPROP_RAY_RIGHT) != 0) != penRR)
         ObjectSetInteger(0, cnm, OBJPROP_RAY_RIGHT, penRR);
      coreN[l3] = true;
   }
   //--- P-LOOK — CAPS: one solid end block per level over the span's last eighth.
   //--- P-UNIFY-3: the block follows the LEVEL's own slope — its two ends ask the same
   //--- geometry the rows did (identical prices on a horizontal fibo).
   for(int l4 = 0; l4 < nw; l4++)
   {
      string pnm = FibPenCapName(fibo, l4);
      datetime tc = tb - (tb - ta) / 8;
      if(!(tc > ta)) tc = ta;
      double lpA = 0.0, lpB = 0.0;
      bool capOk = (lk == FIBPEN_LOOK_CAPS && anchorsOk);
      if(capOk)
      {
         double vv4 = ObjectGetDouble(0, fibo, OBJPROP_LEVELVALUE, l4);
         if(!MathIsValidNumber(vv4)) capOk = false;
         else
         {
            lpA = DrawLevelPriceAt(k, vv4, ta, p1, tb, p2, t3, p3, tc);
            lpB = DrawLevelPriceAt(k, vv4, ta, p1, tb, p2, t3, p3, tb);
            if(!(lpA > 0.0) || !(lpB > 0.0)) capOk = false;
         }
      }
      if(!capOk)
      {
         if(ObjectFind(0, pnm) >= 0) { ObjectDelete(0, pnm); dirty = true; nDrop++; }
         continue;
      }
      int cw = logW[l4];
      if(cw < DRAW_WIDTH_MIN) cw = DRAW_WIDTH_MIN;
      if(cw > DRAW_WIDTH_MAX) cw = DRAW_WIDTH_MAX;
      if(ObjectFind(0, pnm) < 0)
      {
         if(!ObjectCreate(0, pnm, OBJ_TREND, 0, tc, lpA, tb, lpB)) continue;
         ObjectSetInteger(0, pnm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, pnm, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, pnm, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, pnm, OBJPROP_RAY_RIGHT, false);
         dirty = true; nNew++;
      }
      if((datetime)ObjectGetInteger(0, pnm, OBJPROP_TIME, 0) != tc ||
            ObjectGetDouble(0, pnm, OBJPROP_PRICE, 0) != lpA)
            { ObjectMove(0, pnm, 0, tc, lpA); nMov++; }
      if((datetime)ObjectGetInteger(0, pnm, OBJPROP_TIME, 1) != tb ||
            ObjectGetDouble(0, pnm, OBJPROP_PRICE, 1) != lpB)
            { ObjectMove(0, pnm, 1, tb, lpB); nMov++; }
      if((int)ObjectGetInteger(0, pnm, OBJPROP_WIDTH) != cw)
         ObjectSetInteger(0, pnm, OBJPROP_WIDTH, cw);
      if((int)ObjectGetInteger(0, pnm, OBJPROP_STYLE) != (int)STYLE_SOLID)
         ObjectSetInteger(0, pnm, OBJPROP_STYLE, STYLE_SOLID);
      if((color)(int)ObjectGetInteger(0, pnm, OBJPROP_COLOR) != colA[l4])
         ObjectSetInteger(0, pnm, OBJPROP_COLOR, colA[l4]);
      if((int)ObjectGetInteger(0, pnm, OBJPROP_BACK) != backLayer)
         ObjectSetInteger(0, pnm, OBJPROP_BACK, backLayer);
   }
   //--- P-LOOK — WASH: one dotted halo hugging each level, sunk behind the bars.
   //--- P-UNIFY-3: the halo rides the LEVEL's own slope, two pixels beside it — the
   //--- rows' geometry, read from the arrays the loop above already measured.
   for(int l5 = 0; l5 < nw; l5++)
   {
      string wnm = FibPenWashName(fibo, l5);
      double hpA = 0.0, hpB = 0.0;
      color haze = clrNONE;
      bool washOk = (lk == FIBPEN_LOOK_WASH && pxOk && anchorsOk &&
                     lva[l5] > 0.0 && lvb[l5] > 0.0);
      if(washOk)
      {
         hpA = lva[l5] + 2.0 * px;
         hpB = lvb[l5] + 2.0 * px;
         haze = BlendColorTowardsBG(colA[l5], 65, wbg);
      }
      if(!washOk)
      {
         if(ObjectFind(0, wnm) >= 0) { ObjectDelete(0, wnm); dirty = true; nDrop++; }
         continue;
      }
       if(ObjectFind(0, wnm) < 0)
       {
             if(!ObjectCreate(0, wnm, OBJ_TREND, 0, ts0, hpA, ts1, hpB)) continue;
            ObjectSetInteger(0, wnm, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, wnm, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, wnm, OBJPROP_RAY_LEFT, penRL);   // P-LOOK-RAY2: the halo hugs the level's own span
            ObjectSetInteger(0, wnm, OBJPROP_RAY_RIGHT, penRR);
         dirty = true; nNew++;
      }
       if((datetime)ObjectGetInteger(0, wnm, OBJPROP_TIME, 0) != ts0 ||
             ObjectGetDouble(0, wnm, OBJPROP_PRICE, 0) != hpA)
             { ObjectMove(0, wnm, 0, ts0, hpA); nMov++; }
       if((datetime)ObjectGetInteger(0, wnm, OBJPROP_TIME, 1) != ts1 ||
             ObjectGetDouble(0, wnm, OBJPROP_PRICE, 1) != hpB)
             { ObjectMove(0, wnm, 1, ts1, hpB); nMov++; }
      if((int)ObjectGetInteger(0, wnm, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)
         ObjectSetInteger(0, wnm, OBJPROP_WIDTH, DRAW_WIDTH_MIN);
      if((int)ObjectGetInteger(0, wnm, OBJPROP_STYLE) != (int)STYLE_DOT)
         ObjectSetInteger(0, wnm, OBJPROP_STYLE, STYLE_DOT);
      if((color)(int)ObjectGetInteger(0, wnm, OBJPROP_COLOR) != haze)
         ObjectSetInteger(0, wnm, OBJPROP_COLOR, haze);
      if((int)ObjectGetInteger(0, wnm, OBJPROP_BACK) == 0)
         ObjectSetInteger(0, wnm, OBJPROP_BACK, true);
      if(((int)ObjectGetInteger(0, wnm, OBJPROP_RAY_LEFT) != 0) != penRL)
         ObjectSetInteger(0, wnm, OBJPROP_RAY_LEFT, penRL);
       if(((int)ObjectGetInteger(0, wnm, OBJPROP_RAY_RIGHT) != 0) != penRR)
          ObjectSetInteger(0, wnm, OBJPROP_RAY_RIGHT, penRR);
   }
    //--- P-LOOK-3D RETIRED (2026-10-18, «3D کلا حذف کن») — the shadow is never born
    //--- again. The `_FSH` family this unit still knows (the name, HasPen, the
    //--- early-out probe, the delete hub's sweep) is spent HERE: the first sync after
    //--- a reload deletes whatever an older build left, so a 3D fibo degrades to the
    //--- previous look — never to a dangling shadow. Present-only: still frames pay
    //--- one probe per level and write nothing.
    for(int l6 = 0; l6 < nw; l6++)
    {
       string snm = FibPenShwName(fibo, l6);
       if(ObjectFind(0, snm) >= 0) { ObjectDelete(0, snm); dirty = true; nDrop++; }
    }
   for(int dl2 = 0; dl2 < FIBPEN_MAX_LEVELS; dl2++)
   {
      int from = (!need[dl2] ? 0 : wantN[dl2] + (coreN[dl2] ? 1 : 0));
      for(int q3 = from; ; q3++)
      {
         string nm3 = FibPenName(fibo, dl2, q3);
         if(ObjectFind(0, nm3) < 0) break;
            ObjectDelete(0, nm3);
            dirty = true; nDrop++;
      }
   }
   //--- DIAG-136 (2026-10-03) — THE SYNC WITNESSES ITS OWN WRITES. A change the
   //--- terminal never shows («هرچی ضخیم تر انتخاب میکنم تاثییری نداره») is
   //--- unprovable from a screenshot: the line below says, per fibo, how many
   //--- levels demoted, children were born and strays dropped — through the
   //--- FLUSHED channel, never Print. Dirty-only: a still frame emits nothing.
   if(dirty)
      DrawStripDiagEmit("[drawstrip] FIBPEN fibo=\"" + fibo + "\" lv=" + IntegerToString(nl) +
                        " dem=" + IntegerToString(nDem) + " new=" + IntegerToString(nNew) +
                        " drop=" + IntegerToString(nDrop) + " uni=" + IntegerToString(nUni) +
                        " look=" + IntegerToString(lk) +
                        " rays=" + IntegerToString(FibPenRayBits(fibo)));
   //--- DIAG-139 (2026-10-03) — THE DRAG QUESTION, ANSWERED BY NUMBERS. A lag
   //--- report during a gesture («موقع درگ فریمش عقب میمونه») needs to know
   //--- whether the sync ran and what anchors it saw — not a screenshot. At most
   //--- one line per second while children actually move; still frames are silent.
   if(nMov > 0)
   {
      uint nowMs = GetTickCount();
      if(nowMs - s_fibMovMs > 1000 || nowMs < s_fibMovMs)
      {
         s_fibMovMs = nowMs;
         DrawStripDiagEmit("[drawstrip] FIBPENMOV fibo=\"" + fibo + "\" moved=" + IntegerToString(nMov) +
                           " ta=" + IntegerToString((long)ta) + " tb=" + IntegerToString((long)tb) +
                           " p1=" + DoubleToString(p1, _Digits) + " p2=" + DoubleToString(p2, _Digits));
      }
   }
   //--- P-LOOK-RAY2: the pen just built IS the pen this master asks for - the net's
   //--- memo records the master it was built from, so the next 2 s pass is one compare.
   //--- P-UNIFY-3: the third anchor is part of the master (0/0 on the two-anchor kinds).
   FibPenNetWrite(fibo, (long)ta, (long)tb, three ? (long)t3 : 0,
                  p1, p2, three ? p3 : 0.0, FibPenRayBits(fibo), FibPenHasPen(fibo));
   return dirty;
}
#endif // FIBPEN_MQH
