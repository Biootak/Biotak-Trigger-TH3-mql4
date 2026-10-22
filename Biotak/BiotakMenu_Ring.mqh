// BiotakMenu_Ring.mqh - the RING's own home, split out of BiotakMenu_A/B
// on 2026-10-17 because BiotakMenu_A.mqh reached 1584 and BiotakMenu_B.mqh
// 1565 lines and contract 7 says a file over the 1500-line ceiling never
// grows (P-SIZE-1500): touch it = split it by owner. This IS that owner -
// the catalog (every item the ring can hold, in ONE order), the membership
// mask behind the Tools stars, the growth law (the taper, the chord
// radius, the fit walk) and the shape law (P-UI-164: the capacity is the
// DRAWN layout's own). Included from BiotakMenu_A.mqh BELOW the
// TOOL_*/CIR_*/CIRC_* identities it reads and ABOVE every reader (the menu
// halves, the panels). Zero renames: every name here carried the same name
// before the split.
#ifndef BIOTAK_RING_MQH
#define BIOTAK_RING_MQH

//--- P-UI-161 (2026-10-17) — THE CATALOG: every item that can live in the main
// ring, in ONE order. The user's own model («خودش رینگ اصلی رو بچینه … هرچی خواست
// اضافه بکنه و هرچی بود به بخش تولز»): the Tools menu hosts the WHOLE catalog
// (each cell wears a membership STAR, top-right), the main ring shows the STARRED
// subset in catalog order + the Tools door as its LAST seat. The 7 tools keep
// their indices (0..6) — no object name, no key, no layout constant moves — and
// the 9 ring features are APPENDED (7..15), so the shipped star mask (bits 7..15,
// 0xFF80) reproduces the P-UI-161 ring order exactly and appends SESSIONS:
// ZONES, TRIGGER, ATR, TH, HTF, BASEKNOT, TH3, LEG, SESSIONS.
// RING_TOOLS is not a catalog item: it is the door and always occupies the last
// ring seat (RingFeature's own law below). The old RING_* slot table is retired —
// a seat's feature is now `RingFeature(seat)`, answered from the star mask.
#define CAT_TOOLS_COUNT 7            // cells 0..6 — the Tools half-circle, indices unchanged
#define CAT_COUNT       16           // 7 tools + 9 features — the whole catalog
#define RING_MAX_SEATS  (CAT_COUNT + 1)  // worst-case seats a purge loop must sweep
#define CAT_ZONES      7
#define CAT_TRIGGER    8
#define CAT_ATR        9
#define CAT_TH         10
#define CAT_HTF        11
#define CAT_BASEKNOT   12
#define CAT_TH3        13
#define CAT_LEG        14
#define CAT_SESSIONS   15            // P-SESS — Sessions Zones (card 15)
//--- the shipped membership: the 9 features are IN the ring, the 7 tools live in
//--- the Tools menu only. Bits are CAT_* indices; 0xFF80 = bits 7..15.
//--- P-SESS-04: bit 16 is the HANDOFF STAMP, not a membership bit (a cat is
//--- 0..15) — every post-SESSIONS save carries it, so an UNSTAMPED key was
//--- written before the clock existed and CircStarLoad stars SESSIONS once.
#define CIRC_STAR_STAMP   0x10000
#define CIRC_STAR_DEFAULT (0xFF80 | CIRC_STAR_STAMP)

// P-UI-161 (2026-10-17) — THE STAR IS THE MEMBERSHIP, THE CATALOG IS  |
// THE ONE ORDER, AND THE DOOR IS ALWAYS LAST.                         |
//                                                                     |
// The user's model, verbatim: «خودش رینگ اصلی رو بچینه و کم و زیاد بکنه|
// و هرچی خواست اضافه بکنه و هرچی بود به بخش تولز اونایی که نمیخوادش» and |
// «توی همون تولز که هستش یک علامت ستاره باشه که بهتر و سریع تره».       |
//                                                                     |
// So the Tools menu shows the WHOLE catalog and every cell wears a    |
// membership STAR (top-right). A click on the star toggles the bit;   |
// the main ring shows the STARRED subset in catalog order and the     |
// CIR_TOOLS door as its LAST seat — the door can never be unstarred,  |
// or the Tools menu (the only place a star exists) would become       |
// unreachable. ONE mask, ONE order, ONE door rule: the ring, the      |
// star ink and the persisted key all read THIS block.                 |
//                                                                     |
// The mask is 16 bits + the handoff stamp (CAT_COUNT + P-SESS-04), persisted
// as the "STAR" UI slot. A missing key = CIRC_STAR_DEFAULT (the 9 features,
// bits 7..15 + the stamp) — the shipped look. A SAVED unstamped mask was
// written before the Sessions cell existed: CircStarLoad stars SESSIONS into
// it ONCE, stamped, and the user's own bits are untouched (an ADD, never a
// reset). A STAMPED mask is the user's own membership, bit 15 clear included:
// an unstar is respected forever — the handoff can never fire twice.
//+------------------------------------------------------------------+
static uint g_CircStarMask = CIRC_STAR_DEFAULT;

bool CircCatStarred(const int cat)
{
   if(cat < 0 || cat >= CAT_COUNT) return false;
   return ((g_CircStarMask >> cat) & 1) != 0;
}

// The star mask's ONLY writer. Returns the previous state so the caller can
// witness the transition without re-reading.
bool CircStarSet(const int cat, const bool on)
{
   if(cat < 0 || cat >= CAT_COUNT) return false;
   bool was = CircCatStarred(cat);
   if(on) g_CircStarMask |=  (1 << cat);
   else   g_CircStarMask &= ~(1 << cat);
   return was;
}

// P-SESS-04 (2026-10-17) — THE SAVED-MASK HANDOFF. MEASURED on the reporting
// chart: the stored key read 31737 (0x7BF9) — a mask saved BEFORE the Sessions
// cell existed, so bit 15 was clear and the ring showed no clock («سشن ها …
// چیزی نمیبینم»). The handoff stars SESSIONS into an UNSTAMPED mask once
// (the user's own bits untouched — an ADD, never a reset), writes its own
// stamp so it fires once, not every load, and witnesses itself through the
// FLUSHED channel (a Print witness waits in MT4's RAM, P-DRAW-126).
uint CircStarLoad(const string key)
{
   if(!GlobalVariableCheck(key)) return CIRC_STAR_DEFAULT;
   uint v = (uint)GlobalVariableGet(key);
   if((v & CIRC_STAR_STAMP) == 0)
   {
      uint was = v;
      v |= (uint)(0x8000 | CIRC_STAR_STAMP);
      GlobalVariableSet(key, (double)v);
      DrawStripDiagEmit(StringFormat("[P-SESS-04] star handoff key=%s was=0x%X now=0x%X",
                                     key, (int)was, (int)v));
   }
   return v;
}

int CircStarCount()
{
   int n = 0;
   for(int c = 0; c < CAT_COUNT; c++)
      if(CircCatStarred(c)) n++;
   return n;
}

// The seat-th STARRED catalog item (ascending), or -1 when out of range.
int CircStarCatAtSeat(const int seat)
{
   int n = 0;
   for(int c = 0; c < CAT_COUNT; c++)
   {
      if(!CircCatStarred(c)) continue;
      if(n == seat) return c;
      n++;
   }
   return -1;
}

//--- Catalog mapping. ToolFeature is the alias every existing caller already
//--- reads (click branch, ToolPanel, ToolsCreateItem) — the catalog IS its table.
int ToolFeature(const int toolIdx)
{
   if(toolIdx == TOOL_PIN)             return CIR_PIN;
   if(toolIdx == TOOL_STEP_OVERRIDE)   return CIR_STEP_OVERRIDE;
   if(toolIdx == TOOL_GENERAL)         return CIR_GENERAL;   // P-UI-131
   if(toolIdx == TOOL_HRAY)            return CIR_HRAY;      // P-HR-01
   if(toolIdx == TOOL_PATH)            return CIR_PATH;      // Path tool
   if(toolIdx == TOOL_SCALE)           return CIR_SCALE;     // P-UI-159
   if(toolIdx == TOOL_HIDE)            return CIR_HIDE;      // P-UI-160
   // UIBK-OFF (P-UI-95): if(toolIdx == TOOL_BASEKNOT) return CIR_BASEKNOT;
   // FACTORBTN-OFF: if(toolIdx == TOOL_FACTOR_OVERRIDE) return CIR_FACTOR_OVERRIDE;
   //--- P-UI-161: the 9 ring features are catalog cells too (APPENDED at 7..15,
   //--- so no tool index moved and the shipped ring order is preserved).
   if(toolIdx == CAT_ZONES)            return CIR_ZONES;
   if(toolIdx == CAT_TRIGGER)          return CIR_TRIGGER;
   if(toolIdx == CAT_ATR)              return CIR_ATR;
   if(toolIdx == CAT_TH)               return CIR_TH;
   if(toolIdx == CAT_HTF)              return CIR_HTF;
   if(toolIdx == CAT_BASEKNOT)         return CIR_BASEKNOT;
   if(toolIdx == CAT_TH3)              return CIR_TH3;
   if(toolIdx == CAT_LEG)              return CIR_LEG;
   if(toolIdx == CAT_SESSIONS)         return CIR_SESSIONS;   // P-SESS
   return -1;
}

//--- Ring seats: the requested count (stars + the door) and the feature at a
//--- seat. The door is the LAST PLACED seat by law (P-UI-164: when the cap
//--- seats fewer than the mask, the excess stars drop — the door never does).
int RingCount() { return CircStarCount() + 1; }

int RingFeature(const int ringIdx)
{
   if(ringIdx < 0 || ringIdx >= RingCount()) return -1;
   if(ringIdx >= CircPlacedCount()) return -1;              // P-UI-164: a seat the layout does not draw
   if(ringIdx == CircPlacedCount() - 1) return CIR_TOOLS;   // the door, always last
   return ToolFeature(CircStarCatAtSeat(ringIdx));
}

//| P-UI-195 (2026-10-21) — TWO CIRCLES. P-UI-161's taper (the ring  |
//| grew by SHRINKING) is RETIRED for the ring: the first circle is  |
//| always the shipped nine at 44px, and everything else rides a     |
//| SECOND circle — bigger radius, smaller discs — instead of        |
//| squeezing the whole ring. The taper survives ONLY on the TRAIN   |
//| (the near-edge degrade), which keeps P-UI-166's law: the ladder  |
//| ends on the 35 floor and the train seats CIRC_SEAT_CAP (12).     |
//|                                                                  |
//| FIRST circle: seats 0..min(RingCount(),9)-1 — the first nine       |
//| SEATS in catalog order (eight stars + the door are still nine),    |
//| 44px at CIRC_RADIUS (80).                                          |
//| SECOND circle: every seat past the ninth — the extra stars and,    |
//| once the inner ring is full, the Tools door (still the LAST seat   |
//| of the whole ring, P-UI-161/164) — 32px at CircRing2Radius(),      |
//| which clears the first circle's discs, seated IN THE ROW'S GAPS    |
//| as a row (P-UI-195b): the LAST n2 gaps of the first circle, at the |
//| row's own pitch, ending just before 12 o'clock — so the smalls     |
//| never scatter 360/n2 apart and never sit radially behind an inner  |
//| seat.                                                              |
//|                                                                  |
//| The shape gate (CircRingFits) now proves BOTH circles fit before |
//| the ring is drawn; where it does not, the train is the degrade   |
//| (P-UI-13: the previous surface, never a stack).                  |
//+------------------------------------------------------------------+
#define CIRC_SEAT_CAP 12             // P-UI-166: the TRAIN's cap (twelve seats on a line)
#define CIRC_RING2_REACH (CIRC_RING2_BTN_SIZE / 2 + CIRC_BADGE_FLOAT + CIRC_BADGE_SIZE / 2)  // outermost badge pixel of an outer seat

//--- P-UI-195: the two circles' own counts. The FIRST circle is the shipped
//--- nine SEATS (P-UI-166's number, measured byte-identical: eight stars + the
//--- door still draw at 44px/r80); the second takes every seat past it — the
//--- stars past the ninth and, once the inner ring is full, the Tools door.
//--- RingCount() still counts stars + the door, so no seat index, key or feature
//--- mapping moves; the door stays the LAST seat (P-UI-161/164).
int CircRing1Count() { return MathMin(RingCount(), CIRC_RING1_SEATS); }
int CircRing2Count() { return RingCount() - CircRing1Count(); }
bool CircSeatOuter(const int i) { return (i >= CircRing1Count()); }

//--- P-UI-195b (2026-10-22) — «دایره کوچیک‌تر به ردیف باشه» + the drawing (three
//--- 32px circles in the three gap slots before 12 o'clock). A gap k is the
//--- bisector of inner seats k and k+1: -90 + 360*k/n1 + 180/n1. The outer seats
//--- take the LAST n2 gaps, clockwise, so the tail (the door last) ends just
//--- before the 12 o'clock seat and the smalls sit in ONE row at the INNER pitch.
//--- MEASURED 2026-10-22 08:38 (biotak_diag_EURUSD_134362571361933145.txt:
//--- seats=11 ring1=9 ring2=2 r2=124.0): the old 360/n2 spread put the second
//--- small at 110 deg — radially BEHIND the inner seat at 110, not between two.
//--- More outer seats than gaps (n2 > n1) falls back to the even 360/n2 spread
//--- starting at the first gap; CircRing2Radius's chord floor keeps that legal.
double CircRing2StepDeg()
{
   int n1 = CircRing1Count();
   int n2 = CircRing2Count();
   if(n1 <= 0 || n2 <= 0) return 0.0;
   return (n2 > n1) ? (360.0 / n2) : (360.0 / n1);
}

double CircRing2StartDeg()
{
   int n1 = CircRing1Count();
   int n2 = CircRing2Count();
   if(n1 <= 0 || n2 <= 0) return -70.0;
   if(n2 > n1) return -90.0 + 180.0 / n1;          // more seats than gaps — the first gap
   int k = n1 - n2;                                 // the LAST n2 gaps of the row
   return -90.0 + 360.0 * k / n1 + 180.0 / n1;
}

//--- P-UI-195: the side a seat is DRAWN at. On the train every seat wears the
//--- taper's ONE side (CircBtnSize, P-UI-166); on the ring the first circle is 44
//--- and the second is CIRC_RING2_BTN_SIZE. The paint, the move, the badge seat,
//--- the hit test and the safe-zone rect all read THIS call — a second copy of the
//--- decision would be a second grid.
int CircSeatSize(const int i)
{
   bool vertical; int dir;
   if(CircRailShape(vertical, dir)) return CircBtnSize();
   return CircSeatOuter(i) ? CIRC_RING2_BTN_SIZE : CIRC_BTN_SIZE;
}

int CircBtnSizeForN(const int n)
{
   if(n <= 9)  return CIRC_BTN_SIZE;   // 44 — the shipped look, byte-identical
   if(n == 10) return 43;
   if(n == 11) return 39;
   return CIRC_BTN_MIN;                // 35 — the floor (P-UI-166; twelve seats and beyond)
}

//--- P-UI-162: the SKIN CANVAS must equal the drawn BOX (s + 2*CIRC_BG_MARGIN).
//--- MT4 blits an OBJ_BITMAP_LABEL's BMP 1:1 from the object's top-left corner
//--- and CLIPS it at XSIZE/YSIZE — it never scales — so the shipped 52px canvas
//--- inside the taper's smaller box cut the disc's right/bottom arc («این ایکون
//--- ها دیگه دایره نیست», 2026-10-17: the face's right edge measured constant at
//--- the box boundary for 17 rows). One baked pair per side, canvas == box;
//--- 44 (s <= 9 seats) keeps the shipped circ_off/on.bmp byte-identical.
//--- P-UI-195: the side is the SEAT's own (two circles draw two sides) — the
//--- caller hands in the side it painted, so no reader can mistake a ring-2
//--- 32px seat for the inner 44.
string CircBgRes(const int s, const bool on)
{
   if(s == 43) return on ? "::Files\\Icons\\circ_on_43.bmp" : "::Files\\Icons\\circ_off_43.bmp";
   if(s == 39) return on ? "::Files\\Icons\\circ_on_39.bmp" : "::Files\\Icons\\circ_off_39.bmp";
   if(s == 35) return on ? "::Files\\Icons\\circ_on_35.bmp" : "::Files\\Icons\\circ_off_35.bmp";
   if(s == 32) return on ? "::Files\\Icons\\circ_on_32.bmp" : "::Files\\Icons\\circ_off_32.bmp";
   if(s == 30) return on ? "::Files\\Icons\\circ_on_30.bmp" : "::Files\\Icons\\circ_off_30.bmp";
   return on ? "::Files\\Icons\\circ_on.bmp" : "::Files\\Icons\\circ_off.bmp";   // 44 — the shipped nine-seat canvas
}

//--- P-UI-164: the CHORD radius — the true no-overlap minimum of n seats on
//--- the full circle, (S+CIRC_GAP)/(2·sin(π/n)): the SubChordRadius invariant
//--- applied to a CLOSED sweep. For n > 9 it IS CircRadiusForN's answer; for
//--- n <= 9 it is the number the shape gate must test, because CircRadiusForN
//--- answers the shipped 80 there (the byte-identical look) and 80 is not what
//--- "no overlap" means at the squeeze.
double CircChordRadiusForN(const int n)
{
   if(n < 2) return 0.0;               // one seat can never collide
   double s = MathSin(M_PI / n);
   if(s < 1e-9) return CIRC_RADIUS;
   return (CircBtnSizeForN(n) + CIRC_GAP) / (2.0 * s);
}

double CircRadiusForN(const int n)
{
   if(n <= 9) return CIRC_RADIUS;      // 80 — the shipped look, byte-identical
   return CircChordRadiusForN(n);      // ONE chord formula in this file
}

//--- P-UI-195: the SECOND circle's radius. Its inner edge clears the first
//--- circle's discs (r1 + 22 + gap + 16), and its own chord law is the floor —
//--- the same no-overlap invariant the inner ring has always used.
double CircRing2Radius()
{
   int n2 = CircRing2Count();
   if(n2 <= 0) return 0.0;
   double r = CircRadius() + CIRC_BTN_SIZE / 2.0 + CIRC_GAP + CIRC_RING2_BTN_SIZE / 2.0;
   if(n2 > 1)
   {
      double chord = (CIRC_RING2_BTN_SIZE + CIRC_GAP) / (2.0 * MathSin(M_PI / n2));
      if(chord > r) r = chord;
   }
   return r;
}

//--- The outer circle's own fit walk: the CircFitLimit ray-vs-bounds at the OUTER
//--- seats' angles and the outer seat's reach. P-PERF-16's cache law (it is asked
//--- by the capacity, the paint and every hit test; none re-walks).
double CircFitLimitOuter()
{
   static int    s_f2N1 = 0, s_f2N2 = 0, s_f2Cw = 0, s_f2Ch = 0, s_f2Ox = 0, s_f2Oy = 0;
   static double s_f2R = 0.0;
   int n1 = CircRing1Count();
   int n2 = CircRing2Count();
   if(n2 <= 0) return 1e18;            // nothing outside the first circle
   int cw, ch;
   CircUIMetrics(cw, ch);
   int ox = g_UI.menuX;
   int oy = g_UI.menuY;
   if(s_f2R > 0.0 && n1 == s_f2N1 && n2 == s_f2N2 && cw == s_f2Cw && ch == s_f2Ch &&
      ox == s_f2Ox && oy == s_f2Oy)
      return s_f2R;

   double start = CircRing2StartDeg();
   double step  = CircRing2StepDeg();   // P-UI-195b: the ring's own pitch — the paint's number
   double r = 1e18;
   for(int i = 0; i < n2; i++)
   {
      double deg = (start + step * i) * M_PI / 180.0;
      double c = MathCos(deg);
      double s = MathSin(deg);
      double lim = 1e18;
      if(c > 1e-6)        lim = MathMin(lim, (cw - CIRC_PAD - ox - CIRC_RING2_REACH) / c);
      else if(c < -1e-6)  lim = MathMin(lim, (ox - CIRC_PAD - CIRC_RING2_REACH) / (-c));
      if(s > 1e-6)        lim = MathMin(lim, (ch - CIRC_PAD - oy - CIRC_RING2_REACH) / s);
      else if(s < -1e-6)  lim = MathMin(lim, (oy - CIRC_PAD - CIRC_RING2_REACH) / (-s));
      if(lim < 1e17) r = MathMin(r, lim);
   }
   if(r > 1e17) r = CIRC_RADIUS;       // degenerate (no bound) — the design radius

   s_f2N1 = n1; s_f2N2 = n2; s_f2Cw = cw; s_f2Ch = ch; s_f2Ox = ox; s_f2Oy = oy; s_f2R = r;
   return r;
}

//--- The uncapped fit walk (the same ray-vs-bounds as the retired CircFitRadius,
//--- now WITHOUT the [MIN,RADIUS] clamp so the growth law can read it).
//--- P-PERF-16: cached on (seat count, cw, ch, ox, oy) — every hit test asks it,
//--- none re-walks. CIRC_ITEM_REACH stays the S=44 reach: conservative for a
//--- shrunk ring (its real reach is smaller) and byte-identical for n <= 9.
double CircFitLimit()
{
   static int    s_fitN = 0, s_fitCw = 0, s_fitCh = 0, s_fitOx = 0, s_fitOy = 0;
   static double s_fitR = 0.0;
   int cw, ch;
   CircUIMetrics(cw, ch);
   int ox = g_UI.menuX;
   int oy = g_UI.menuY;
   int n  = RingCount();
   if(s_fitR > 0.0 && n == s_fitN && cw == s_fitCw && ch == s_fitCh &&
      ox == s_fitOx && oy == s_fitOy)
      return s_fitR;

   double r = 1e18;
   for(int i = 0; i < n; i++)
   {
      double deg = (-90.0 + 360.0 * i / n) * M_PI / 180.0;
      double c = MathCos(deg);
      double s = MathSin(deg);
      double lim = 1e18;
      if(c > 1e-6)        lim = MathMin(lim, (cw - CIRC_PAD - ox - CIRC_ITEM_REACH) / c);
      else if(c < -1e-6)  lim = MathMin(lim, (ox - CIRC_PAD - CIRC_ITEM_REACH) / (-c));
      if(s > 1e-6)        lim = MathMin(lim, (ch - CIRC_PAD - oy - CIRC_ITEM_REACH) / s);
      else if(s < -1e-6)  lim = MathMin(lim, (oy - CIRC_PAD - CIRC_ITEM_REACH) / (-s));
      if(lim < 1e17) r = MathMin(r, lim);
   }
   if(r > 1e17) r = CIRC_RADIUS;       // degenerate (no bound) — the design radius

   s_fitN = n; s_fitCw = cw; s_fitCh = ch; s_fitOx = ox; s_fitOy = oy; s_fitR = r;
   return r;
}

//| P-UI-164 (2026-10-17) — THE CAPACITY IS THE DRAWN LAYOUT'S OWN.    |
//|                                                                   |
//| MEASURED (biotak_diag_EURUSD_134362571361933137.txt): a 13-seat    |
//| ring dragged to the left edge and released came back as NINE seats |
//| — the DELFLUSH sweep carries 13 names and the re-create writes 9 — |
//| so the tail stars AND the Tools door vanished («بقیه ایتم ها چرا    |
//| گم میشن و نیستش»). The capacity answered CircFitLimit's ray-vs-   |
//| bounds — a RING's question — while the DRAWN layout near an edge   |
//| is the TRAIN, whose room is the free run of the edge. CircRailShape|
//| is the ONE shape decision — the capacity, the paint (CircLayout)   |
//| and the hit test all read THIS call; a second copy of the branch   |
//| is a second grid.                                                  |
//+------------------------------------------------------------------+
bool CircRingFits()
{
   // P-UI-195: BOTH circles must fit. The first circle's chord law is P-UI-164's
   // own (nine seats at most now, so the answer is the shipped 80 whenever the
   // bounds allow it); the second circle's radius must sit inside its own reach.
   double fit = MathMax(CircFitLimit(), (double)CIRC_MIN_RADIUS);
   int n1 = CircRing1Count();
   if(n1 > 1 && CircChordRadiusForN(n1) > fit) return false;
   if(CircRing2Count() > 0 && CircRing2Radius() > CircFitLimitOuter()) return false;
   return true;
}

// The ONE shape decision: true = the seats ride the TRAIN (vertical on a
// left/right edge, else horizontal), dir = ±1 along that axis; false = the
// ring — answered only where CircRingFits() proves the chord fits (P-UI-13:
// never a stack, never a capped circle below its chord). Axis: the near edge
// first (the shipped priority — left/right before top/bottom), else the
// nearest edge (the 90..131px squeeze band whose squeezed ring would overlap).
// dir: the side of the axis with more room — s-free, because both rooms
// subtract s/2, so the comparison is 2*oy vs ch / 2*ox vs cw (the old argmax).
bool CircRailShape(bool &vertical, int &dir)
{
   int cw, ch;
   CircUIMetrics(cw, ch);       // P-PERF-16: cached metrics, no terminal read
   int ox = g_UI.menuX;
   int oy = g_UI.menuY;
   bool nearLeft   = (ox <= CIRC_EDGE_TRIGGER);
   bool nearRight  = (ox >= cw - CIRC_EDGE_TRIGGER);
   bool nearTop    = (oy <= CIRC_EDGE_TRIGGER);
   bool nearBottom = (oy >= ch - CIRC_EDGE_TRIGGER);
   if(!nearLeft && !nearRight && !nearTop && !nearBottom && CircRingFits())
      return false;             // the ring really fits — the shipped circle
   if(nearLeft || nearRight) vertical = true;
   else if(nearTop || nearBottom) vertical = false;
   else vertical = (MathMin(ox, cw - ox) <= MathMin(oy, ch - oy));
   dir = vertical ? ((oy >= ch - oy) ? -1 : 1) : ((ox >= cw - ox) ? -1 : 1);
   return true;
}

// The train's own fit walk: the longest count whose run at ITS OWN side seats
// the last seat's far edge inside the padded bound — the same numbers
// CircLayout paints with (room = dist - CIRC_PAD - s/2, len = ORB/2 + s/2 +
// GAP + (k-1)*(s+GAP)). 1 (the door alone) is the floor: degrade to the
// previous surface, never to nothing and never to a stack (P-UI-13).
int CircRailCapacity(const int n, const bool vertical, const int dir)
{
   int cw, ch;
   CircUIMetrics(cw, ch);
   int ox = g_UI.menuX;
   int oy = g_UI.menuY;
   for(int k = n; k >= 2; k--)
   {
      int s    = CircBtnSizeForN(k);   // each candidate at ITS OWN side — the paint's own number
      int room = (dir < 0) ? (vertical ? oy : ox) - CIRC_PAD - s / 2
                           : (vertical ? ch - oy : cw - ox) - CIRC_PAD - s / 2;
      int len  = CIRC_ORB_SIZE / 2 + s / 2 + CIRC_GAP + (k - 1) * (s + CIRC_GAP);
      if(len <= room) return k;
   }
   return 1;   // the door alone — a degrade to the previous surface, never to nothing (P-UI-13)
}

//--- How many seats the DRAWN layout really shows. P-UI-164: the shape decides
//--- first — on the train the walk is CircRailCapacity (the edge's free run),
//--- on the ring it is the P-UI-161 walk capped at CIRC_SEAT_CAP (nine or
//--- fewer: all of them; more: the largest count up to twelve whose chord
//--- radius still fits; when even nine cannot, nine — the excess stays in the
//--- Tools menu with its star ON, P-UI-166).
//--- (CircPlacedCountLive is the unfrozen half; the FROZEN half,
//--- CircPlacedCount, stays with the built-seat state in BiotakMenu_B.)
//--- P-PERF-16: cached on (seat count, cw, ch, ox, oy) — the release, the
//--- paint's per-item CircLayout and the chart-change path all ask it, none
//--- re-walks.

//--- P-UI-195: the FIRST circle's radius — the shipped 80 for nine or fewer
//--- (byte-identical), the fit cap under a squeeze. The second circle reads it
//--- (CircRing2Radius clears these discs), so this is the ONE inner-radius owner.
double CircRadius()
{
   double fit = MathMax(CircFitLimit(), (double)CIRC_MIN_RADIUS);
   double r = CircRadiusForN(CircRing1Count());
   if(r > fit) r = fit;                 // the fit cap (reachable for k <= 9's squeeze)
   if(r < CIRC_MIN_RADIUS) r = CIRC_MIN_RADIUS;
   return r;
}

int CircPlacedCountLive()
{
   static int s_liveN = 0, s_liveCw = 0, s_liveCh = 0, s_liveOx = 0, s_liveOy = 0;
   static int s_liveR = 0;
   int cw, ch;
   CircUIMetrics(cw, ch);
   int ox = g_UI.menuX;
   int oy = g_UI.menuY;
   int n  = RingCount();
   if(s_liveR > 0 && n == s_liveN && cw == s_liveCw && ch == s_liveCh &&
      ox == s_liveOx && oy == s_liveOy)
      return s_liveR;

   bool vertical;
   int  dir;
   if(CircRailShape(vertical, dir))
   {
      s_liveR = CircRailCapacity(MathMin(n, CIRC_SEAT_CAP), vertical, dir);   // P-UI-166: the train honours the cap too
   }
   else
   {
      // P-UI-195: the drawn ring is TWO circles — nine inner seats at 44 and every
      // remaining star + the door on the outer one — so every seat has a place.
      // CircRailShape's own CircRingFits() proved both circles fit before this
      // branch was reached; the train (above) keeps P-UI-166's twelve-seat cap.
      s_liveR = n;
   }
   s_liveN = n; s_liveCw = cw; s_liveCh = ch; s_liveOx = ox; s_liveOy = oy;
   return s_liveR;
}

#endif
