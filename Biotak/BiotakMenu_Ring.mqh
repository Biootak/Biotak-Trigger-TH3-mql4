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

//| TH3TOOL-OFF (2026-10-24) — A RETIRED CELL KEEPS ITS INDEX AND LOSES |
//| ITS SEAT. The user's order: «ابزار th3tool … کامنت بشه … فعلا نمیخوام |
//| توی محصول اصلی باشه» with the scope «فقط ABCD، لگ‌متر بماند» and the   |
//| constraint «حذف نمیخوام کامنت بشه بعد شاید بخوام روش کار بکنم».       |
//|                                                                    |
//| So the ABCD drawing tool leaves the SHIPPED PRODUCT without a line   |
//| of its code leaving the repo: this one predicate answers "is this    |
//| catalog cell on sale?" and every seat/star reader below asks it.     |
//|                                                                    |
//| WHY THE READER AND NOT THE MASK. `CIRC_STAR_DEFAULT` is pinned       |
//| verbatim by the regression gate and by a mutation entry, and the     |
//| saved "STAR" key carries the user's own bits — rewriting either      |
//| would destroy membership the user can still want the day this cell   |
//| comes back. A retired bit is simply IGNORED here: the mask keeps     |
//| bit 13, the ring and the Tools grid both skip it, and re-enabling    |
//| is `return false;` -> `return (cat == CAT_TH3);` inverted, nothing   |
//| to migrate. Indices never move, so no persisted key and no object    |
//| name is orphaned (CAT_COUNT stays 16 — the gate's own number).       |
//+------------------------------------------------------------------+
bool CircCatRetired(const int cat)
{
   return (cat == CAT_TH3);   // [TH3-TOOLS-DISABLED] ABCD drawing tool: parked, not deleted
}

bool CircCatStarred(const int cat)
{
   if(cat < 0 || cat >= CAT_COUNT) return false;
   if(CircCatRetired(cat)) return false;   // TH3TOOL-OFF: a retired cell can never hold a seat
   return ((g_CircStarMask >> cat) & 1) != 0;
}

// The star mask's ONLY writer. Returns the previous state so the caller can
// witness the transition without re-reading.
bool CircStarSet(const int cat, const bool on)
{
   if(cat < 0 || cat >= CAT_COUNT) return false;
   if(CircCatRetired(cat)) return false;   // TH3TOOL-OFF: no star, so the ring cannot re-seat it
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

//| TH3TOOL-OFF (2026-10-24) — THE CELL SLOT, so a retired cell leaves |
//| no hole. The Tools grid lays its tiles on `k = i` (the catalog      |
//| index IS the screen slot). Retiring index 13 in place would punch   |
//| a 46px gap in the middle of the grid — the exact kind of thing the  |
//| user reports («یه جای خالی افتاده»), so the grid counts SLOTS, not  |
//| catalog indices: every non-retired cell keeps its order and closes  |
//| the gap. The index is still the cell's identity everywhere else     |
//| (object names, the star bit, the card number) — only the POSITION   |
//| is remapped, and only here.                                        |
//|                                                                    |
//| -1 = "this catalog entry has no slot" (retired): the callers park  |
//| it, which is exactly what SubItemOnPage already does for a cell on |
//| a page that is not shown.                                          |
//+------------------------------------------------------------------+
int CircCellCount()
{
   int n = 0;
   for(int c = 0; c < CAT_COUNT; c++)
      if(!CircCatRetired(c)) n++;
   return n;
}

// The catalog index -> its grid slot (0-based, dense), or -1 when retired.
int CircCatCell(const int cat)
{
   if(cat < 0 || cat >= CAT_COUNT) return -1;
   if(CircCatRetired(cat))         return -1;
   int cell = 0;
   for(int c = 0; c < cat; c++)
      if(!CircCatRetired(c)) cell++;
   return cell;
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
//| ends on the 35 floor at CIRC_SEAT_CAP (12) seats, and its        |
//| capacity is read from the RUN, never from that count (P-UI-218). |
//|                                                                  |
//| P-UI-218 (2026-10-30): the ring SHRINKS to the tighter of the    |
//| two circles' fits before the shape is refused — the train seats  |
//| fewer seats than the ring, so degrading to it lost three starred |
//| items on a release near an edge.                                 |
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
//--- P-UI-218 (2026-10-30): NO LONGER A CAPACITY. Twelve is the count from which the
//--- train's taper sits on its 35 floor (CircBtnSizeForN) — the run is what decides how
//--- many seats the row holds. MEASURED before: a 15-seat ring released at y=716 became a
//--- 12-seat train while the row had room for all fifteen, so three starred items vanished
//--- on release («چرا تعدادش کم میشه»).
#define CIRC_SEAT_CAP 12             // P-UI-166: the count at which the train reaches its 35 floor
#define CIRC_RING2_REACH (CIRC_RING2_BTN_SIZE / 2 + CIRC_BADGE_FLOAT + CIRC_BADGE_SIZE / 2)  // outermost badge pixel of an outer seat
//--- P-UI-218: the second circle's radius MINUS the first's — ONE owner, because the shrink
//--- cap in CircRadius() subtracts exactly this and CircRing2Radius() adds it.
#define CIRC_RING2_GAP (CIRC_BTN_SIZE / 2 + CIRC_GAP + CIRC_RING2_BTN_SIZE / 2)

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
   double r = CircRadius() + CIRC_RING2_GAP;   // P-UI-218: the same number CircRadius's cap subtracts
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
   //--- P-UI-218: the same tighter cap CircRadius() shrinks to. The ring is refused only
   //--- when the SHRUNK circle would still overlap its own seats — never merely because the
   //--- design radius (80) does not fit, which is what sent all fifteen seats to a train.
   if(CircRing2Count() > 0)
   {
      double r2cap = CircFitLimitOuter() - CIRC_RING2_GAP;
      if(r2cap < fit) fit = r2cap;
   }
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

//--- P-UI-207 (2026-10-22): A RAIL IS LAID OUT BY THE TILE IT PAINTS, never by
//--- the seat. Row A (the star ring's train, CircLayout) paints a tile of
//--- CircBtnSize()+2*CIRC_BG_MARGIN; row B (the Tools rail, SubPlaceItem) paints
//--- SubBgSize() == CIRC_BG_SIZE (52). Each row hands ITS OWN tile in here, so
//--- the fits test and the placement can only ever speak one number.
//--- MEASURED before this: row B stepped 50 (44+6) under a 52 tile — 2px of tile
//--- ON tile in every cell — and reserved 22px of cross-axis room where the
//--- tile's own half is 26. Row B names its tile in SubRailTile() rather than
//--- SubBgSize(), which asks SubMode() and would recurse back into this fits test.
int CircRailStep(const int tile) { return tile + CIRC_GAP; }                            // one tile centre -> the next
int CircRailLead(const int tile) { return CIRC_ORB_SIZE / 2 + tile / 2 + CIRC_GAP; }    // orb centre -> first tile centre
int CircRailRun(const int tile, const int n)                                            // orb centre -> the FAR tile's edge
{ return CircRailLead(tile) + (n - 1) * CircRailStep(tile) + tile / 2; }
int CircRailRoom(const int freeRun, const int tile) { return freeRun - CIRC_PAD - tile / 2; }   // the padded run the tiles must end inside

// The train's own fit walk: the longest count whose run at ITS OWN side seats
// the last seat's far edge inside the padded bound — the same numbers
// CircLayout paints with (room = dist - CIRC_PAD - box/2, len = ORB/2 + box/2 +
// GAP + (k-1)*(box+GAP)). 1 (the door alone) is the floor: degrade to the
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
      int box  = s + 2 * CIRC_BG_MARGIN;   // P-UI-204: the TILE the paint draws, not the seat
      int room = (dir < 0) ? (vertical ? oy : ox) - CIRC_PAD - box / 2
                           : (vertical ? ch - oy : cw - ox) - CIRC_PAD - box / 2;
      int len  = CIRC_ORB_SIZE / 2 + box / 2 + CIRC_GAP + (k - 1) * (box + CIRC_GAP);
      if(len <= room) return k;
   }
   return 1;   // the door alone — a degrade to the previous surface, never to nothing (P-UI-13)
}

//--- How many seats the DRAWN layout really shows. P-UI-164: the shape decides
//--- first — on the train the walk is CircRailCapacity (the edge's free run),
//--- on the ring it is every placed seat — P-UI-195's two circles with P-UI-218's
//--- shrink keep all of them, and where even the shrunk ring cannot fit the SHAPE
//--- becomes the train, whose capacity is its own RUN (never a count cap). The
//--- excess only stays in the Tools menu with its star ON when that run is too
//--- short for it (P-UI-166/218).
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
   //--- P-UI-218 (2026-10-30) — THE RING SHRINKS BEFORE IT GIVES UP. The SECOND circle
   //--- is what runs out of room first (it sits a fixed 44px outside the first, plus its
   //--- own 36px badge reach), so the cap is the TIGHTER of the two fits. Before this the
   //--- first circle kept r=80 and the outer one overran the box, CircRingFits() refused,
   //--- and the layout degraded to the TRAIN — which seats fewer seats than the ring.
   if(CircRing2Count() > 0)
   {
      double r2cap = CircFitLimitOuter() - CIRC_RING2_GAP;
      if(r2cap < fit) fit = r2cap;
   }
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
      s_liveR = CircRailCapacity(n, vertical, dir);   // P-UI-218: the RUN decides, not the old twelve
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
