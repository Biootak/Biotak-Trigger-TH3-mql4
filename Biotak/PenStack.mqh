// PenStack.mqh — P-DRAW-74c: the stacked pen for the WHOLE-OBJECT kinds.
//
// THE REPORT (the fibo's own law, one family over): «استایل ها در ضخامت های بالا
// درست کار نمیکنه». MEASURED and shipped for the fibo on 2026-10-05 (P-DRAW-74b,
// FibPen.mqh): MT4 draws STYLE_* only at width 1, so a thick + patterned drawing
// is a state the terminal cannot draw — and the two honest fallbacks it DOES have
// (fold the width to 1, or fold the style to Solid) are what «درست کار نمیکنه»
// describes: the style dies at width, or the width dies at style.
//
// THE ANSWER IS THE SAME PEN, POINTED AT ANOTHER FAMILY. The fibo's levels are
// FibPen's business; DK_HLINE, DK_VLINE and DK_LINE are this unit's. For a master
// wearing (pattern, width>1) the pen does what FibPen does, per drawing:
//   * the MASTER keeps its anchors, its selection and its drag — untouched by MT4 —
//     and is demoted to the VISIBLE width 1 wearing the pattern it chose (the dash
//     itself, exactly like a fibo level);
//   * `logical-1` width-1 children carry the SAME style in the SAME ink, seated on
//     FibPenOffPx's centred ring — the ONE offset law, never a second table;
//   * the LOGICAL width is 1 + children, read back by `PenStackLogicalWidth`, so
//     the strip's WIDTH cell keeps showing the number the user picked.
//
// WHY THIS IS THE NEAR-ZERO COST SHAPE (asked for: «با هزینه های نزدیک به صفر»):
//   * At rest: zero writes. The children are static objects; the only pass cost is
//     one memo compare in the 2 s chart-side walk (`PenStackHeal`), which already
//     pays one type read per object (DrawStrip_Pick).
//   * Bounded: at most DRAW_WIDTH_MAX-1 = 4 children per master, ever.
//   * Interaction untouched: the MASTER is still the native object — MT4 selects
//     and drags it exactly as before (this is the property a canvas layer cannot
//     keep without its own grab, hide and re-raster machinery — which is why the
//     bitmap white-alpha trap (P-DRAW-35) and the per-pan re-render stay out of
//     scope: the engine is a later phase, the pen is this fix).
//
// V1 EXCLUSIONS, named so nothing is silently half-served:
//   * HRay (P-HR-04) and path segments (P-UI-136) own their own pair laws —
//     `PenStackServes` refuses them and their fold behaviour is unchanged.
//   * A LINE steeper than ~70° gets a vertical (not perpendicular) row ring: the
//     anchors are bar-snapped, so a sub-bar horizontal step cannot be expressed;
//     the fallback is vertical offsets and the rule is written here, not hidden.
//   * Children are invisible to every surface: SELECTABLE=false, HIDDEN=true,
//     `DrawKindOf` answers DK_NONE, the orphan sweep names their parent.
//
// The integration is FibPen's own caller set, mirrored: the slot writes route
// here (Toolbar_B), the drag event arms a chase and the move stream follows it
// (DrawStrip_Router), the open/release/zoom re-states (Paint/Router), the 2 s
// walk heals (Pick), the delete path sweeps (Tap/Router), the strip's WIDTH cell
// reads the logical number (Toolbar_A). Gate: P-DRAW-74c.
#ifndef PENSTACK_MQH
#define PENSTACK_MQH

//--- P-DRAW-74c: the children's name tail — `<master>_PSK<q>`, q contiguus from 0.
//--- The test is the SUFFIX followed by digits-only to the end (FibPenIsChild's
//--- own shape): a name this unit never built simply probes absent.
#define PENSTACK_SUFFIX   "_PSK"
#define PENSTACK_NET_SLOTS 8

// ══════════════════════════════════════════════════════════════════════════
// P-PEN-ALL (2026-10-19) — THE SHAPE PEN. The line pen's law, one anchor set over.
// «همه مشکلاتی که برای فیبو انجام دادم رو برای بقیه چیزهای دیگه هم ببر». The line
// pen serves the three kinds MT4 draws as ONE line. The kinds below are whole
// SHAPES whose outline is the master's own TYPE drawn from its own anchors — so a
// copy of the master with every anchor shifted by the SAME pixel vector is the
// same shape moved, which is what a thick pen is: the master demoted to the
// pattern at width 1, `logical-1` width-1 copies seated beside it.
//
// WHAT IS SERVED, AND WHY EACH ONE IS EXACT:
//   * DK_RECT / DK_ELLIPSE (2 anchors) and DK_TRIANGLE (3): the outline is the
//     type's own drawing from those points — a shifted copy draws it shifted;
//   * DK_CHANNEL (its three types: a channel is 3 points, a regression and a
//     standard-deviation channel are 2 — the count is taken off the TYPE);
//   * DK_GANN (OBJ_GANNLINE / OBJ_GANNFAN / OBJ_GANNGRID, 2 anchors): the ray set
//     of its two points — a shifted copy is that set shifted. Its RAY pair is
//     mirrored onto every row (P-LOOK-RAY3's lesson: a row that stops at the
//     anchor while the master runs on wears no thickness on the extension).
// NOT SERVED, named so nothing is silently half-served:
//   * DK_PITCHFORK: its rails ARE its level family, so a whole-object copy would
//     carry a copy of the levels — and a fresh pitchfork is born with MT4's own
//     defaults, not the master's values. It keeps the native fold until a level
//     pen owns it;
//   * the level kinds (FIBO/FIBOFAN/FIBOCHAN/EXPANSION): same reason — a copy
//     duplicates the level family FibPen already styles;
//   * rays and paths: their own pair laws (V1, unchanged).
// THE RING: one line has a perpendicular, a shape has not, so the SAME ring value
// (`FibPenOffPx`) is applied to BOTH axes — the union of a diagonal ring thickens
// an edge by exactly the logical width where the edge is axis-aligned and by up
// to 41 % more on a 45° edge. One offset law, never a second table.
// THE INTERIOR: a shape may wear a fill child, and MT4 paints in CREATION order
// (P-LOG-10), so a fill child born after the rows covers the half of the thickness
// that lies inside the outline. The sync notices the fill child APPEARING (the net
// records it) and rebuilds the rows above it — once, at the transition.
//--- P-PEN-ALL: the LINE family — the kinds whose drawing is ONE line through the two
//--- anchors, so the ring is measured PERPENDICULAR to it (a price step), never on both
//--- axes. P-UNIFY-2 put the test in one place: a trend-by-angle IS that line with its
//--- angle pinned, and a second `k == DK_LINE` in the sync is exactly how a new line
//--- kind gets served on the write and left un-thickened on every frame after it.
bool PenStackLineKind(const EDrawKind k)
{
   return (k == DK_LINE || k == DK_TANGLE);
}
bool PenStackShapeKind(const EDrawKind k)
{
   return (k == DK_RECT || k == DK_ELLIPSE || k == DK_TRIANGLE ||
           k == DK_CHANNEL || k == DK_GANN || k == DK_CYCLES);
}
//--- how many anchors the master really has, off its own type: an equidistant
//--- channel and a triangle are three points, everything else here is two.
int PenStackAnchorCount(const int ty)
{
   return (ty == OBJ_TRIANGLE || ty == OBJ_CHANNEL) ? 3 : 2;
}
//--- the TYPE half of the same question, for the pass that already paid for the
//--- type read (DrawStrip_Pick's 2 s walk). ONE owner for the served set: the walk
//--- asks this, never a second list.
bool PenStackServesType(const int ty)
{
   return (DrawTypePenFamily(ty) == DKPEN_OBJECT);   // P-UNIFY-4: the profile owns the set
}

//--- may this name be served by the pen at all? The kind is the gate; the two
//--- self-serving families (rays, paths) are refused; indicator objects never are.
//--- A child answers immediately on the name, so nothing recursive can happen.
bool PenStackServes(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   if(PenStackIsChild(name)) return false;
   if(DrawIsIndicatorObject(name)) return false;
   if(DrawIsHRay(name) || DrawIsPathSeg(name)) return false;   // v1: their own pair laws
   return (DrawKindPenFamily(DrawKindOf(name)) == DKPEN_OBJECT);   // P-UNIFY-4
}

string PenStackName(const string m, const int q)
{
   return m + PENSTACK_SUFFIX + IntegerToString(q);
}

//--- the name test: the suffix sits before a digits-only tail. Never "ends with".
bool PenStackIsChild(const string name)
{
   int s = StringLen(PENSTACK_SUFFIX);
   int pos = 0;
   while(true)
   {
      int at = StringFind(name, PENSTACK_SUFFIX, pos);
      if(at < 0) return false;
      string rest = StringSubstr(name, at + s);
      bool ok = (StringLen(rest) > 0);
      for(int i = 0; i < StringLen(rest); i++)
      {
         ushort ch = StringGetCharacter(rest, i);
         if(ch < '0' || ch > '9') { ok = false; break; }
      }
      if(ok) return true;
      pos = at + 1;
   }
   return false;
}

//--- the parent cut for the orphan sweep: everything before the suffix. The LAST
//--- occurrence wins (a master that itself carries the letters can never be one).
string PenStackChildParent(const string name)
{
   int cut = -1;
   int s = StringLen(PENSTACK_SUFFIX);
   for(int i = 0; i + s <= StringLen(name); i++)
   {
      bool hit = true;
      for(int j = 0; j < s; j++)
         if(StringGetCharacter(name, i + j) != StringGetCharacter(PENSTACK_SUFFIX, j)) { hit = false; break; }
      if(hit) cut = i;
   }
   if(cut <= 0) return "";
   return StringSubstr(name, 0, cut);
}

//--- how many children the master carries (contiguous from q=0). Bounded: <= 4.
int PenStackChildCount(const string m)
{
   int c = 0;
   for(int q = 0; q < DRAW_WIDTH_MAX; q++)
   {
      if(ObjectFind(0, PenStackName(m, q)) < 0) break;
      c++;
   }
   return c;
}

//--- the remembered width: >1 while the terminal holds the logical number on the
//--- object itself; once demoted (width 1), the children ARE the memory. Mirrors
//--- FibPenLogicalWidth's shape — one law, two families. The dialog-ambiguity is
//--- the fibo's accepted one: a width-1 write on a stacked master keeps the stack
//--- (children win), because the demotion itself wears width 1.
int PenStackLogicalWidth(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return DRAW_WIDTH_MIN;
   int w = (int)ObjectGetInteger(0, name, OBJPROP_WIDTH);
   if(w < DRAW_WIDTH_MIN) w = DRAW_WIDTH_MIN;
   if(w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MAX;
   if(w > DRAW_WIDTH_MIN) return w;
   int c = PenStackChildCount(name);
   if(c > 0)
   {
      int lg = 1 + c;
      if(lg > DRAW_WIDTH_MAX) lg = DRAW_WIDTH_MAX;
      return lg;
   }
   return DRAW_WIDTH_MIN;
}

//--- ONE pixel's worth of TIME, off the chart's own pitch (the VLINE's axis).
//--- A local probe on a real span: the forming bar's time and half an hour of
//--- bars later, both projected through the terminal's own call. Zero when the
//--- window cannot answer — the caller then degrades to the native pair.
double PenStackSecPerPx()
{
   datetime t0 = iTime(NULL, 0, 0);
   if(t0 <= 0) return 0.0;
   double hi = ChartGetDouble(0, CHART_PRICE_MAX);
   double lo = ChartGetDouble(0, CHART_PRICE_MIN);
   if(!(hi > lo)) return 0.0;
   double anyP = (hi + lo) / 2.0;
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   if(!ChartTimePriceToXY(0, 0, t0, anyP, x1, y1)) return 0.0;
   datetime t2 = t0 + (datetime)(PeriodSeconds() * 30);
   if(!ChartTimePriceToXY(0, 0, t2, anyP, x2, y2)) return 0.0;
   int dx = x2 - x1;
   if(dx < 4) return 0.0;
   double s = (double)(t2 - t0) / (double)dx;
   return (s > 0.0) ? s : 0.0;
}

//--- the LINE's row step in PRICE: FibPenOffPx's ring, magnified so the rows sit
//--- ONE PIXEL apart PERPENDICULAR to the line. A vertical offset of d reads as
//--- d*cos(a) perpendicular (a = the line's angle off horizontal), so the step is
//--- px/cos(a) = px*len/|dx|. Anchors are bar-snapped, so a sub-bar horizontal
//--- step cannot be expressed: past ~70° the fallback is the vertical step and the
//--- rule says so instead of pretending. Zero means "no scale" — the caller keeps
//--- the native pair.
double PenStackLineStep(const datetime t1, const double p1, const datetime t2, const double p2)
{
   double px = FibPenPixelPrice();
   if(!(px > 0.0)) return 0.0;
   if(t1 <= 0 || t2 <= 0 || !(p1 > 0.0) || !(p2 > 0.0)) return 0.0;
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   if(!ChartTimePriceToXY(0, 0, t1, p1, x1, y1)) return 0.0;
   if(!ChartTimePriceToXY(0, 0, t2, p2, x2, y2)) return 0.0;
   double dx = (double)(x2 - x1), dy = (double)(y2 - y1);
   double len = MathSqrt(dx * dx + dy * dy);
   if(!(len > 0.0)) return 0.0;
   double adx = MathAbs(dx);
   if(adx >= 0.35 * len) return px * (len / adx);   // the perpendicular ring
   return px;                                       // steep fallback, stated above
}

//--- the net's ring: what the LAST sync built, so the 2 s walk is one compare.
//--- (P-LOOK-RAY2's shape, one family over — a master the terminal lands after the
//--- last event would otherwise keep a stale pen forever.)
static string s_psNetName[PENSTACK_NET_SLOTS];
static long   s_psNetT0[PENSTACK_NET_SLOTS], s_psNetT1[PENSTACK_NET_SLOTS];
static double s_psNetP0[PENSTACK_NET_SLOTS], s_psNetP1[PENSTACK_NET_SLOTS];
static int    s_psNetW[PENSTACK_NET_SLOTS], s_psNetSt[PENSTACK_NET_SLOTS];
static int    s_psNetC[PENSTACK_NET_SLOTS], s_psNetBk[PENSTACK_NET_SLOTS];
static int    s_psNetRay[PENSTACK_NET_SLOTS];
//--- P-PEN-ALL: the three-point shapes' THIRD anchor, and whether an interior child
//--- stood beside the master when the rows were last built (the paint-order edge).
static long   s_psNetT2[PENSTACK_NET_SLOTS];
static double s_psNetP2[PENSTACK_NET_SLOTS];
static int    s_psNetFill[PENSTACK_NET_SLOTS];
static int    s_psNetNext = 0;
static uint   s_psMovMs = 0;

int PenStackNetFind(const string m)
{
   if(m == "") return -1;
   for(int i = 0; i < PENSTACK_NET_SLOTS; i++)
      if(s_psNetName[i] == m) return i;
   return -1;
}
//--- the memo is a CACHE of a state, so a state a caller just changed underneath it
//--- has to be spendable: the interior's birth (P-PEN-ALL) and nothing else today.
bool PenStackNetForget(const string m)
{
   int at = PenStackNetFind(m);
   if(at < 0) return false;
   s_psNetName[at] = "";
   return true;
}
void PenStackNetWrite(const string m, const long t0, const long t1, const double p0, const double p1,
                      const long t2, const double p2, const int w, const int st, const int c,
                      const int bk, const int ray, const int fill)
{
   int at = PenStackNetFind(m);
   if(at < 0)
   {
      at = s_psNetNext;
      s_psNetNext = (s_psNetNext + 1) % PENSTACK_NET_SLOTS;
      s_psNetName[at] = m;
   }
   s_psNetT0[at] = t0; s_psNetT1[at] = t1;
   s_psNetP0[at] = p0; s_psNetP1[at] = p1;
   s_psNetT2[at] = t2; s_psNetP2[at] = p2;
   s_psNetW[at] = w; s_psNetSt[at] = st; s_psNetC[at] = c;
   s_psNetBk[at] = bk; s_psNetRay[at] = ray; s_psNetFill[at] = fill;
}

//--- the master's anchors, read once per sync/probe. HLINE: price only; VLINE:
//--- time only; LINE: both pairs. t/p zero where the axis does not apply.
void PenStackAnchors(const string name, const int k, datetime &t1, double &p1, datetime &t2, double &p2)
{
   t1 = 0; t2 = 0; p1 = 0.0; p2 = 0.0;
   if(k == DK_HLINE)
   {
      p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
      p2 = p1;
      return;
   }
   if(k == DK_VLINE)
   {
      t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
      t2 = t1;
      return;
   }
   t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
   p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
}
int PenStackRayBits(const string name)
{
   int rl = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_LEFT) != 0) ? 2 : 0;
   int rr = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != 0) ? 1 : 0;
   return rl | rr;
}

//--- P-PEN-ALL: a SHAPE row's geometry — the master's OWN anchors, every one of them
//--- shifted by the same pixel vector. `ObjectMove` is MQL4's only per-anchor mover,
//--- so a time-only anchor takes the TIME setter and a price-only one the PRICE setter
//--- (a shape's anchors carry both; the branches are here so a stranger degrades
//--- instead of writing a zero). Returns true when it really wrote something.
bool PenStackShapeSeat(const string m, const string nm, const int nA,
                       const int off, const double px, const double secPx)
{
   bool moved = false;
   for(int a = 0; a < nA; a++)
   {
      datetime mt = (datetime)ObjectGetInteger(0, m, OBJPROP_TIME, a);
      double   mp = ObjectGetDouble(0, m, OBJPROP_PRICE, a);
      if(mt > 0 && mp > 0.0)
      {
         datetime rt = mt + (datetime)(long)MathRound((double)off * secPx);
         double   rp = mp + off * px;
         if((datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, a) != rt ||
            ObjectGetDouble(0, nm, OBJPROP_PRICE, a) != rp)
         {
            ObjectMove(0, nm, a, rt, rp);
            moved = true;
         }
      }
      else if(mt > 0)
      {
         datetime rt = mt + (datetime)(long)MathRound((double)off * secPx);
         if((datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, a) != rt)
         { ObjectSetInteger(0, nm, OBJPROP_TIME, a, rt); moved = true; }
      }
      else if(mp > 0.0)
      {
         double rp = mp + off * px;
         if(ObjectGetDouble(0, nm, OBJPROP_PRICE, a) != rp)
         { ObjectSetDouble(0, nm, OBJPROP_PRICE, a, rp); moved = true; }
      }
   }
   return moved;
}

//--- a shape row at birth: the master's own TYPE and anchors, already on the row's
//--- seat (so the first frame is right and the seat call above finds it settled).
bool PenStackShapeCreate(const string m, const string nm, const int ty, const int nA,
                         const int off, const double px, const double secPx)
{
   datetime t0 = 0, t1c = 0, t2c = 0;
   double   p0 = 0.0, p1c = 0.0, p2c = 0.0;
   for(int b = 0; b < nA && b < 3; b++)
   {
      datetime mt = (datetime)ObjectGetInteger(0, m, OBJPROP_TIME, b);
      double   mp = ObjectGetDouble(0, m, OBJPROP_PRICE, b);
      if(mt <= 0 || !(mp > 0.0)) return false;   // a shape anchor carries both axes
      datetime rt = mt + (datetime)(long)MathRound((double)off * secPx);
      double   rp = mp + off * px;
      if(b == 0)      { t0 = rt;  p0 = rp;  }
      else if(b == 1) { t1c = rt; p1c = rp; }
      else            { t2c = rt; p2c = rp; }
   }
   if(nA >= 3) return ObjectCreate(0, nm, ty, 0, t0, p0, t1c, p1c, t2c, p2c);
   return ObjectCreate(0, nm, ty, 0, t0, p0, t1c, p1c);
}

//--- P-DRAGF3 (2026-10-17) - THE GESTURE BELONGS TO THE TERMINAL (born with the law,
//--- the fibo's own preview is FibPen.mqh's, same defect same numbers): OBJECT_DRAG
//--- fires ~1-2/s while the hand's moves arrive ~60-100/s, and a patterned thick master
//--- is a demoted width-1 line plus moved `_PSK` children the chase re-seats per move
//--- in a frame painted AFTER the terminal's own blit. Preview: at the arm the stacked
//--- master goes back to its logical width - MT4 draws SOLID at width>1 - and its
//--- children hide ONCE; through the gesture this unit writes NOTHING, and at the
//--- release ONE PenStackSync re-demotes + re-seats + re-memoizes in the release's own
//--- flushed frame. Cost: one width write + one hide per child at the arm, one un-hide
//--- + one sync at the release. The visible trade, stated: a patterned thick line
//--- previews SOLID while the hand moves; the pattern returns at the release.
static bool   s_psPreview    = false;   // P-DRAGF3: the preview owns the gesture
static string s_psPreviewObj = "";

void PenStackPreviewArm(const string name)
{
   if(s_psPreview) return;
   string m = name;
   if(m == "" || ObjectFind(0, m) < 0) return;
   int log = PenStackLogicalWidth(m);
   if(log <= DRAW_WIDTH_MIN) return;   // solid, or nothing stacked: the native line already is the picture
   int st = (int)ObjectGetInteger(0, m, OBJPROP_STYLE);
   if(st < 0) st = 0;
   if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
   bool pattern = (st != (int)STYLE_SOLID && log > DRAW_WIDTH_MIN);
   if(!pattern) return;   // the sync's own demote test: only a patterned thick line stacks
   int nW = 0, nH = 0;
   if((int)ObjectGetInteger(0, m, OBJPROP_WIDTH) != log)
   { ObjectSetInteger(0, m, OBJPROP_WIDTH, log); nW++; }
   int c = PenStackChildCount(m);
   for(int q = 0; q < c; q++)
   {
      string nm = PenStackName(m, q);
      if(ObjectFind(0, nm) < 0) continue;
      if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_NO_PERIODS)
      { ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS); nH++; }
   }
   if(nW <= 0) return;   // nothing was demoted on this gesture: no preview, no flag
   s_psPreview = true;
   s_psPreviewObj = m;
   DrawStripDiagEmit("[drawstrip] PENSTACKPRE view=on obj=\"" + m + "\" w=" + IntegerToString(log) +
                     " hid=" + IntegerToString(nH));
}

bool PenStackPreviewEnd()
{
   if(!s_psPreview) return false;
   string m = s_psPreviewObj;
   s_psPreview = false;   // cleared FIRST: the sync below must not read its own gate
   s_psPreviewObj = "";
   if(m == "" || ObjectFind(0, m) < 0) return false;
   int nU = 0;
   int c = PenStackChildCount(m);
   for(int q = 0; q < c; q++)
   {
      string nm = PenStackName(m, q);
      if(ObjectFind(0, nm) < 0) continue;
      if((int)ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) != OBJ_ALL_PERIODS)
      { ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS); nU++; }
   }
   bool dirty = PenStackSync(m, false);
   DrawStripDiagEmit("[drawstrip] PENSTACKPRE view=off obj=\"" + m + "\" unhid=" + IntegerToString(nU) +
                     " sync=" + IntegerToString(dirty ? 1 : 0));
   return (nU > 0 || dirty);
}

//--- THE ONE SYNC: demotes the undrawable width, builds / refreshes / drops the
//--- stack in the master's own style and ink. `dropAll` is the delete path. Guarded
//--- throughout: a still frame pays reads, writes nothing.
bool PenStackSync(const string name, const bool dropAll)
{
   if(!PenStackServes(name)) return false;
   if(s_psPreview && !dropAll && name == s_psPreviewObj) return false;   // P-DRAGF3: gated while the preview owns the gesture; dropAll (delete) is never gated
   EDrawKind k = DrawKindOf(name);
   //--- P-PEN-ALL: the shape half of the same sync. `ty` is read once and answers the
   //--- anchor count; `fillNow` is the interior child the rows must be born ABOVE
   //--- (MT4 paints in CREATION order, P-LOG-10).
   bool shape = PenStackShapeKind(k);
   int ty = (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
   int nA = shape ? PenStackAnchorCount(ty) : 0;
   int fillNow = (shape && ObjectFind(0, FillChildName(name)) >= 0) ? 1 : 0;
   int w = (int)ObjectGetInteger(0, name, OBJPROP_WIDTH);
   if(w < DRAW_WIDTH_MIN) w = DRAW_WIDTH_MIN;
   if(w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MAX;
   int st = (int)ObjectGetInteger(0, name, OBJPROP_STYLE);
   if(st < 0) st = 0;
   if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
   int cur = PenStackChildCount(name);
   int log = (w > DRAW_WIDTH_MIN) ? w : ((cur > 0) ? cur + 1 : DRAW_WIDTH_MIN);
   if(log > DRAW_WIDTH_MAX) log = DRAW_WIDTH_MAX;
   bool pattern = (st != (int)STYLE_SOLID && log > DRAW_WIDTH_MIN);
   //--- the scale each kind's ring needs: price-per-px (HLINE/LINE) or sec-per-px
   //--- (VLINE), plus anchors. When the window cannot answer, NOTHING is demoted —
   //--- the master keeps the native (solid) pair and the next pass heals it: a
   //--- degraded frame is better than a stack of rows at the wrong pitch.
   datetime t1 = 0, t2 = 0; double p1 = 0.0, p2 = 0.0;
   PenStackAnchors(name, k, t1, p1, t2, p2);
   bool anchorsOk = (k == DK_HLINE)   ? (p1 > 0.0)
                  : (k == DK_VLINE)   ? (t1 > 0)
                  :                    (t1 > 0 && t2 > 0 && p1 > 0.0 && p2 > 0.0);
   double px = 0.0, secPx = 0.0;
   if(k == DK_HLINE || PenStackLineKind(k) || shape) px = FibPenPixelPrice();
   if(k == DK_VLINE || shape) secPx = PenStackSecPerPx();
   //--- a shape row moves on BOTH axes (the ring law, applied to time and price), so
   //--- both scales must answer before anything is demoted — otherwise the shape keeps
   //--- the native pair and the next pass heals it, exactly like the line kinds.
   bool scaleOk = shape ? (px > 0.0 && secPx > 0.0)
                        : ((k == DK_VLINE) ? (secPx > 0.0) : (px > 0.0));
   int vis = log, want = 0;
   if(pattern) { vis = DRAW_WIDTH_MIN; want = log - 1; }
   if(dropAll) { want = 0; vis = w; }            // the object is going: strays die, width is not ours to write
   if(dropAll || !anchorsOk || !scaleOk) { vis = w; want = 0; }
   int nDem = 0, nNew = 0, nDrop = 0, nMov = 0;
   bool dirty = false;
   //--- P-PEN-ALL: A FRESH INTERIOR IS A LATER PIXEL. The net remembers whether a fill
   //--- child stood beside the master when the rows were last built; when one appears
   //--- now, the rows are spent HERE and rebuilt twenty lines down — above it, because
   //--- creation order is paint order (P-LOG-10). One transition, then silence: with no
   //--- fill child on either side the comparison is two memo reads.
   {
      int fillAt = PenStackNetFind(name);
      int fillWas = (fillAt >= 0) ? s_psNetFill[fillAt] : -1;
      if(!dropAll && shape && fillNow == 1 && fillWas == 0 && cur > 0)
      {
         PenStackStraysDrop(name);
         cur = 0;
         dirty = true;
      }
   }
   if(!dropAll && w != vis)
   {
      ObjectSetInteger(0, name, OBJPROP_WIDTH, vis);
      dirty = true; nDem++;
   }
   if(cur > want)
   {
      for(int q = want; ; q++)
      {
         string nm = PenStackName(name, q);
         if(ObjectFind(0, nm) < 0) break;
         ObjectDelete(0, nm);
         dirty = true; nDrop++;
      }
   }
   int back = (int)ObjectGetInteger(0, name, OBJPROP_BACK);
   color ink = (color)(int)ObjectGetInteger(0, name, OBJPROP_COLOR);
   int ray = PenStackRayBits(name);
   double step = 0.0;
   if(want > 0 && PenStackLineKind(k)) step = PenStackLineStep(t1, p1, t2, p2);
   if(want > 0)
   {
      for(int q2 = 0; q2 < want; q2++)
      {
         string nm2 = PenStackName(name, q2);
         int off = FibPenOffPx(log, q2);          // the ONE offset law (FibPen's ring)
         if(ObjectFind(0, nm2) < 0)
         {
            bool made = false;
            if(k == DK_HLINE)
               made = ObjectCreate(0, nm2, OBJ_HLINE, 0, 0, p1 + off * px);
            else if(k == DK_VLINE)
               made = ObjectCreate(0, nm2, OBJ_VLINE, 0, t1 + (datetime)(long)MathRound(off * secPx), 0);
            else if(shape)
               made = PenStackShapeCreate(name, nm2, ty, nA, off, px, secPx);
            else
               made = ObjectCreate(0, nm2, OBJ_TREND, 0, t1, p1 + off * step, t2, p2 + off * step);
            if(!made) continue;
            ObjectSetInteger(0, nm2, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, nm2, OBJPROP_HIDDEN, true);
            //--- P-PEN-ALL: a row never carries an interior — the fill is the fill
            //--- child's pixel alone (P-DRAW-64), and a row that filled would hide the
            //--- very thickness it was born to draw.
            if(shape) ObjectSetInteger(0, nm2, OBJPROP_FILL, false);
            dirty = true; nNew++;
         }
         if(shape)
         {
            if(PenStackShapeSeat(name, nm2, nA, off, px, secPx)) nMov++;
         }
         else if(k == DK_HLINE)
         {
            double rp = p1 + off * px;
            if(ObjectGetDouble(0, nm2, OBJPROP_PRICE, 0) != rp)
            { ObjectSetDouble(0, nm2, OBJPROP_PRICE, rp); nMov++; }
         }
         else if(k == DK_VLINE)
         {
            datetime rt = t1 + (datetime)(long)MathRound(off * secPx);
            if((datetime)ObjectGetInteger(0, nm2, OBJPROP_TIME, 0) != rt)
            { ObjectSetInteger(0, nm2, OBJPROP_TIME, 0, rt); nMov++; }
         }
         else
         {
            if((datetime)ObjectGetInteger(0, nm2, OBJPROP_TIME, 0) != t1 ||
               ObjectGetDouble(0, nm2, OBJPROP_PRICE, 0) != p1 + off * step)
               { ObjectMove(0, nm2, 0, t1, p1 + off * step); nMov++; }
            if((datetime)ObjectGetInteger(0, nm2, OBJPROP_TIME, 1) != t2 ||
               ObjectGetDouble(0, nm2, OBJPROP_PRICE, 1) != p2 + off * step)
               { ObjectMove(0, nm2, 1, t2, p2 + off * step); nMov++; }
         }
         if((int)ObjectGetInteger(0, nm2, OBJPROP_WIDTH) != DRAW_WIDTH_MIN)
            ObjectSetInteger(0, nm2, OBJPROP_WIDTH, DRAW_WIDTH_MIN);
         if((int)ObjectGetInteger(0, nm2, OBJPROP_STYLE) != st)
            ObjectSetInteger(0, nm2, OBJPROP_STYLE, st);
         if((color)(int)ObjectGetInteger(0, nm2, OBJPROP_COLOR) != ink)
            ObjectSetInteger(0, nm2, OBJPROP_COLOR, ink);
         if((int)ObjectGetInteger(0, nm2, OBJPROP_BACK) != back)
            ObjectSetInteger(0, nm2, OBJPROP_BACK, back);
         //--- P-PEN-ALL: a shape's own ray pair is mirrored too — a gann line runs on
         //--- to the right edge and a row that stopped at the anchor would wear no
         //--- thickness on the extension (P-LOOK-RAY2/RAY3's lesson). For a type with
         //--- no ray the master's bits read 0 and the child's read 0, so nothing is
         //--- written: the mirror is silent where it does not apply.
         if(PenStackLineKind(k) || shape)
         {
            if(((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_LEFT) != 0 ? 2 : 0) + ((int)ObjectGetInteger(0, nm2, OBJPROP_RAY_RIGHT) != 0 ? 1 : 0) != ray)
            {
               ObjectSetInteger(0, nm2, OBJPROP_RAY_LEFT,  (ray & 2) != 0);
               ObjectSetInteger(0, nm2, OBJPROP_RAY_RIGHT, (ray & 1) != 0);
            }
         }
      }
   }
   //--- DIAG-146 (2026-10-14) — THE SYNC WITNESSES ITS OWN WRITES, the FIBPEN shape:
   //--- «در ضخامت بالا استایل اعمال نمیشود» is unprovable from a screenshot, so one
   //--- flushed line per real change names the numbers the sync just moved. Still
   //--- frames emit nothing.
   if(dirty)
      DrawStripDiagEmit("[drawstrip] PENSTACK obj=\"" + name + "\" log=" + IntegerToString(log) +
                        " vis=" + IntegerToString(vis) + " want=" + IntegerToString(want) +
                        " dem=" + IntegerToString(nDem) + " new=" + IntegerToString(nNew) +
                        " drop=" + IntegerToString(nDrop) + " st=" + IntegerToString(st));
   //--- the net's memo records what was just built: the next 2 s pass is one compare.
   //--- P-PEN-ALL: three-point shapes add their third anchor, and every shape records
   //--- whether an interior stood beside it (the paint-order transition above).
   long t3 = 0; double p3 = 0.0;
   if(nA >= 3)
   {
      t3 = (long)ObjectGetInteger(0, name, OBJPROP_TIME, 2);
      p3 = ObjectGetDouble(0, name, OBJPROP_PRICE, 2);
   }
   PenStackNetWrite(name, (long)t1, (long)t2, p1, p2, t3, p3, log, st, want, back, ray, fillNow);
   return dirty;
}

//--- the whole pen of one master dies, wherever the object itself is going.
//--- Name-keyed (the object may already be gone): a name this unit never built
//--- simply probes absent. The ONE sweep; Sync's drop path and the orphan walk
//--- both reach it.
bool PenStackStraysDrop(const string name)
{
   if(name == "") return false;
   bool dd = false;
   for(int q = 0; q < DRAW_WIDTH_MAX; q++)
   {
      string nm = PenStackName(name, q);
      if(ObjectFind(0, nm) < 0) break;
      ObjectDelete(0, nm);
      dd = true;
   }
   return dd;
}

//--- the 2 s walk's half (P-LOOK-RAY2's shape): one memo compare while the pen is
//--- what the last sync built; the sync only on a mismatch. A still chart pays
//--- reads and writes nothing.
bool PenStackHeal(const string name)
{
   if(!PenStackServes(name)) return false;
   if(s_psPreview && name == s_psPreviewObj) return false;   // P-DRAGF3: the preview owns the gesture
   EDrawKind k = DrawKindOf(name);
   datetime t1 = 0, t2 = 0; double p1 = 0.0, p2 = 0.0;
   PenStackAnchors(name, k, t1, p1, t2, p2);
   int w = PenStackLogicalWidth(name);
   int st = (int)ObjectGetInteger(0, name, OBJPROP_STYLE);
   int c = PenStackChildCount(name);
   int bk = (int)ObjectGetInteger(0, name, OBJPROP_BACK);
   int ray = PenStackRayBits(name);
   //--- P-PEN-ALL: a shape's THIRD anchor and the interior's own presence are part of
   //--- the state the rows were built from — a moved corner, or a fill child appearing
   //--- beside them, must fail the compare or the rows keep a stale seat (the
   //--- P-LOOK-RAY2 defect, one family over). Two reads, and only for a shape kind.
   long t3 = 0; double p3 = 0.0; int fl = 0;
   if(PenStackShapeKind(k))
   {
      if(PenStackAnchorCount((int)ObjectGetInteger(0, name, OBJPROP_TYPE)) >= 3)
      {
         t3 = (long)ObjectGetInteger(0, name, OBJPROP_TIME, 2);
         p3 = ObjectGetDouble(0, name, OBJPROP_PRICE, 2);
      }
      fl = (ObjectFind(0, FillChildName(name)) >= 0) ? 1 : 0;
   }
   int at = PenStackNetFind(name);
   if(at >= 0 && s_psNetT0[at] == (long)t1 && s_psNetT1[at] == (long)t2 &&
      s_psNetP0[at] == p1 && s_psNetP1[at] == p2 && s_psNetW[at] == w &&
      s_psNetSt[at] == st && s_psNetC[at] == c && s_psNetBk[at] == bk && s_psNetRay[at] == ray &&
      s_psNetT2[at] == t3 && s_psNetP2[at] == p3 && s_psNetFill[at] == fl)
      return false;
   return PenStackSync(name, false);
}

// ══════════════════════════════════════════════════════════════════════════
// THE CHASE — a dragged master is blitted live by the terminal while its drag
// event fires ~1/s (measured DRAGSTAT). The rows must ride the HAND's stream
// (FibPen's P-DRAGF2 shape), not the master's own cadence, or the stack trails
// the gesture — the defect «موقع درگ کردن فریمش عقب میمونه» one family over.
// ══════════════════════════════════════════════════════════════════════════
static string   s_psDragObj = "";
static int      s_psGrab = -1;         // -1 unasked, 0/1 the LINE's anchors, 2 body
static int      s_psKind = 0;
static double   s_psP0[2], s_psProbeP[2], s_psCurP;
static datetime s_psT0[2], s_psProbeT[2], s_psCurT;

void PenStackChaseReset()
{
   s_psGrab = -1;
   s_psP0[0] = 0.0; s_psP0[1] = 0.0;
   s_psT0[0] = 0; s_psT0[1] = 0;
   s_psProbeP[0] = 0.0; s_psProbeP[1] = 0.0;
   s_psProbeT[0] = 0; s_psProbeT[1] = 0;
   s_psCurP = 0.0; s_psCurT = 0;
   s_psKind = 0;
}
void PenStackDragArm(const string name)
{
   if(name != "" && name == s_psDragObj) return;
   s_psDragObj = "";
   PenStackPreviewEnd();   // P-DRAGF3: a missed release must not hold the previous body hostage
   PenStackChaseReset();
   if(name == "" || !PenStackServes(name)) return;
   s_psDragObj = name;
   s_psKind = (int)DrawKindOf(name);
   PenStackPreviewArm(name);   // P-DRAGF3: a patterned thick line drags NATIVELY
}
void PenStackDragDisarm()
{
   if(s_psDragObj != "") { s_psDragObj = ""; PenStackChaseReset(); }
}

//--- the moves this call really made, for the rate-limited witness.
void PenStackDragFollow(const int mx, const int my)
{
   if(s_psPreview) return;   // P-DRAGF3: the preview owns the gesture - zero writes per move
   if(s_psDragObj == "") return;
   string m = s_psDragObj;
   if(ObjectFind(0, m) < 0) { PenStackChaseReset(); s_psDragObj = ""; return; }
   int cur = PenStackChildCount(m);
   if(cur <= 0) return;                       // a solid pair: nothing to carry
   int cc = 0; datetime curT = 0; double curP = 0.0;
   if(!ChartXYToTimePrice(0, mx, my, cc, curT, curP)) return;
   if(cc != 0) return;
   //--- P-PEN-ALL: A SHAPE RIDES THE HAND WITHOUT ASKING WHICH ANCHOR IT HOLDS. Its
   //--- rows read the master's OWN live anchors on every move and are simply shifted,
   //--- so a corner drag deforms them for free and a body drag slides them — the grab
   //--- states below exist for the LINE's price projection, which a shape needs not.
   //--- Named for the record: a THREE-point shape whose third corner the hand drags
   //--- still reshapes on the terminal's own stream, so the rows meet it at the next
   //--- probe (and the release's sync always lands exact).
   if(PenStackShapeKind((EDrawKind)s_psKind))
   {
      int nAs = PenStackAnchorCount((int)ObjectGetInteger(0, m, OBJPROP_TYPE));
      double pxs = FibPenPixelPrice();
      double secs = PenStackSecPerPx();
      if(!(pxs > 0.0) || !(secs > 0.0)) return;
      int logs = PenStackLogicalWidth(m);
      int nMovS = 0;
      for(int q = 0; q < cur; q++)
      {
         string nmq = PenStackName(m, q);
         if(ObjectFind(0, nmq) < 0) break;
         if(PenStackShapeSeat(m, nmq, nAs, FibPenOffPx(logs, q), pxs, secs)) nMovS++;
      }
      if(nMovS > 0)
      {
         ChartRedraw();
         uint nowMs2 = GetTickCount();
         if(nowMs2 - s_psMovMs > 1000 || nowMs2 < s_psMovMs)
         {
            s_psMovMs = nowMs2;
            DrawStripDiagEmit("[drawstrip] PENSTACKMOV obj=\"" + m + "\" moved=" + IntegerToString(nMovS) +
                              " g=shape t1=" + IntegerToString((long)ObjectGetInteger(0, m, OBJPROP_TIME, 0)) +
                              " p1=" + DoubleToString(ObjectGetDouble(0, m, OBJPROP_PRICE, 0), _Digits));
         }
      }
      return;
   }
   datetime t1 = 0, t2 = 0; double p1 = 0.0, p2 = 0.0;
   PenStackAnchors(m, s_psKind, t1, p1, t2, p2);
   if(s_psKind == DK_HLINE)
   {
      if(!(p1 > 0.0) || !(curP > 0.0)) return;
      if(s_psGrab < 0)
      {
         s_psGrab = 2;
         s_psP0[0] = p1; s_psT0[0] = 0;
         s_psProbeP[0] = p1; s_psProbeT[0] = 0;
         s_psCurP = curP;
         return;   // the press frame asks; it does not move
      }
      if(p1 != s_psProbeP[0])
      {
         s_psP0[0] = p1; s_psProbeP[0] = p1; s_psCurP = curP;
      }
      p1 = s_psP0[0] + (curP - s_psCurP);
   }
   else if(s_psKind == DK_VLINE)
   {
      if(t1 <= 0 || curT <= 0) return;
      if(s_psGrab < 0)
      {
         s_psGrab = 2;
         s_psT0[0] = t1; s_psP0[0] = 0.0;
         s_psProbeT[0] = t1; s_psProbeP[0] = 0.0;
         s_psCurT = curT;
         return;
      }
      if(t1 != s_psProbeT[0])
      {
         s_psT0[0] = t1; s_psProbeT[0] = t1; s_psCurT = curT;
      }
      t1 = s_psT0[0] + (datetime)((long)curT - (long)s_psCurT);
   }
   else
   {
      if(t1 <= 0 || t2 <= 0 || !(p1 > 0.0) || !(p2 > 0.0) || curT <= 0 || !(curP > 0.0)) return;
      if(s_psGrab < 0)
      {
         int ax = 0, ay = 0, bx = 0, by = 0;
         bool okA = ChartTimePriceToXY(0, 0, t1, p1, ax, ay);
         bool okB = ChartTimePriceToXY(0, 0, t2, p2, bx, by);
         if(!okA && !okB) return;
         if(okA && okB)
         {
            int dA = MathAbs(mx - ax) + MathAbs(my - ay);
            int dB = MathAbs(mx - bx) + MathAbs(my - by);
            if(dA <= FIBPEN_GRAB_PX && dA <= dB)   s_psGrab = 0;
            else if(dB <= FIBPEN_GRAB_PX)          s_psGrab = 1;
            else                                   s_psGrab = 2;
         }
         else s_psGrab = okA ? 0 : 1;
         s_psP0[0] = p1; s_psP0[1] = p2;
         s_psT0[0] = t1; s_psT0[1] = t2;
         s_psProbeP[0] = p1; s_psProbeP[1] = p2;
         s_psProbeT[0] = t1; s_psProbeT[1] = t2;
         s_psCurP = curP; s_psCurT = curT;
         return;
      }
      if(p1 != s_psProbeP[0] || p2 != s_psProbeP[1] || t1 != s_psProbeT[0] || t2 != s_psProbeT[1])
      {
         s_psP0[0] = p1; s_psP0[1] = p2;
         s_psT0[0] = t1; s_psT0[1] = t2;
         s_psProbeP[0] = p1; s_psProbeP[1] = p2;
         s_psProbeT[0] = t1; s_psProbeT[1] = t2;
         s_psCurP = curP; s_psCurT = curT;
      }
      double dp = curP - s_psCurP;
      if(s_psGrab == 2)      { p1 = s_psP0[0] + dp; p2 = s_psP0[1] + dp; }
      else if(s_psGrab == 0) { p1 = curP; p2 = s_psP0[1]; }
      else                   { p1 = s_psP0[0]; p2 = curP; }
      if(!(p1 > 0.0) || !(p2 > 0.0)) return;
   }
   double px = FibPenPixelPrice();
   if(!(px > 0.0)) return;
   double secPx = 0.0;
   if(s_psKind == DK_VLINE)
   {
      secPx = PenStackSecPerPx();
      if(!(secPx > 0.0)) return;
   }
   int log = PenStackLogicalWidth(m);
   double step = 0.0;
   if(s_psKind == DK_LINE)
   {
      step = PenStackLineStep(t1, p1, t2, p2);
      if(!(step > 0.0)) return;
   }
   int nMov = 0;
   for(int q = 0; q < cur; q++)
   {
      string nm = PenStackName(m, q);
      if(ObjectFind(0, nm) < 0) break;
      int off = FibPenOffPx(log, q);
      if(s_psKind == DK_HLINE)
      {
         double rp = p1 + off * px;
         if(ObjectGetDouble(0, nm, OBJPROP_PRICE, 0) != rp)
         { ObjectSetDouble(0, nm, OBJPROP_PRICE, rp); nMov++; }
      }
      else if(s_psKind == DK_VLINE)
      {
         datetime rt = t1 + (datetime)(long)MathRound(off * secPx);
         if((datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0) != rt)
         { ObjectSetInteger(0, nm, OBJPROP_TIME, 0, rt); nMov++; }
      }
      else
      {
         if((datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0) != t1 ||
            ObjectGetDouble(0, nm, OBJPROP_PRICE, 0) != p1 + off * step)
            { ObjectMove(0, nm, 0, t1, p1 + off * step); nMov++; }
         if((datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1) != t2 ||
            ObjectGetDouble(0, nm, OBJPROP_PRICE, 1) != p2 + off * step)
            { ObjectMove(0, nm, 1, t2, p2 + off * step); nMov++; }
      }
   }
   //--- the frame the chase moved is the frame it paints (P-DRAW-74b-f's law, one
   //--- family over). A still frame moves nothing and therefore repaints nothing.
   if(nMov > 0)
   {
      ChartRedraw();
      uint nowMs = GetTickCount();
      if(nowMs - s_psMovMs > 1000 || nowMs < s_psMovMs)
      {
         s_psMovMs = nowMs;
         DrawStripDiagEmit("[drawstrip] PENSTACKMOV obj=\"" + m + "\" moved=" + IntegerToString(nMov) +
                           " g=" + IntegerToString(s_psGrab) +
                           " t1=" + IntegerToString((long)t1) +
                           " p1=" + DoubleToString(p1, _Digits));
      }
   }
}
#endif // PENSTACK_MQH
