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

//| P-UI-161 (2026-10-17) — THE RING GROWS BY SHRINKING, NEVER BY     |
//| STACKING.                                                         |
//|                                                                  |
//| The button side S(n) holds the shipped 44 through nine seats      |
//| (byte-identical — a pre-sessions star mask still seats nine at    |
//| 44), tapers 43→32 entering the teens and floors at 30; P-SESS     |
//| stars SESSIONS by default, so a fresh catalog seats TEN (9 stars  |
//| + the door) and the taper's first leg — 43px — is now the fresh   |
//| default look. The radius follows the chord law (S+CIRC_GAP)/      |
//| (2·sin(π/n)) — exactly the SubChordRadius invariant applied to a  |
//| full circle, so the pitch is never lost. The fit cap still rules  |
//| (a menu near an edge pulls the ring in, exactly as before), and   |
//| when the capped circle cannot seat every starred item, the excess |
//| stays in the Tools menu with its star ON (P-UI-13: degrade to the |
//| previous surface, never to a stack).                              |
//+------------------------------------------------------------------+
int CircBtnSizeForN(const int n)
{
   if(n <= 9)  return CIRC_BTN_SIZE;   // 44 — the shipped look, byte-identical
   if(n == 10) return 43;
   if(n == 11) return 39;
   if(n == 12) return 35;
   if(n == 13) return 32;
   return CIRC_BTN_MIN;                // 30 — the floor (n >= 14)
}

//--- P-UI-162: the SKIN CANVAS must equal the drawn BOX (s + 2*CIRC_BG_MARGIN).
//--- MT4 blits an OBJ_BITMAP_LABEL's BMP 1:1 from the object's top-left corner
//--- and CLIPS it at XSIZE/YSIZE — it never scales — so the shipped 52px canvas
//--- inside the taper's smaller box cut the disc's right/bottom arc («این ایکون
//--- ها دیگه دایره نیست», 2026-10-17: the face's right edge measured constant at
//--- the box boundary for 17 rows). One baked pair per side, canvas == box;
//--- 44 (s <= 9 seats) keeps the shipped circ_off/on.bmp byte-identical.
string CircBgRes(const bool on)
{
   int s = CircBtnSize();
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
   double fit = MathMax(CircFitLimit(), (double)CIRC_MIN_RADIUS);
   int n = RingCount();
   if(n <= 9) return CircChordRadiusForN(n) <= fit;
   for(int k = n; k > 9; k--)
      if(CircRadiusForN(k) <= fit) return true;
   return CircChordRadiusForN(9) <= fit;
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
//--- on the ring it is the P-UI-161 walk (nine or fewer: all of them; more: the
//--- largest count whose chord radius still fits; when even nine cannot, nine —
//--- the excess stays in the Tools menu with its star ON).
//--- (CircPlacedCountLive is the unfrozen half; the FROZEN half,
//--- CircPlacedCount, stays with the built-seat state in BiotakMenu_B.)
//--- P-PERF-16: cached on (seat count, cw, ch, ox, oy) — the release, the
//--- paint's per-item CircLayout and the chart-change path all ask it, none
//--- re-walks.

double CircRadius()
{
   double fit = MathMax(CircFitLimit(), (double)CIRC_MIN_RADIUS);
   double r = CircRadiusForN(CircPlacedCount());
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
      s_liveR = CircRailCapacity(n, vertical, dir);
   }
   else if(n <= 9)
   {
      s_liveR = n;                     // nine or fewer: all of them (the 44px look is never dropped)
   }
   else
   {
      double fit = MathMax(CircFitLimit(), (double)CIRC_MIN_RADIUS);
      s_liveR = 9;                     // the floor; the excess stays in the Tools menu
      for(int k = n; k > 9; k--)
         if(CircRadiusForN(k) <= fit) { s_liveR = k; break; }
   }
   s_liveN = n; s_liveCw = cw; s_liveCh = ch; s_liveOx = ox; s_liveOy = oy;
   return s_liveR;
}

#endif
