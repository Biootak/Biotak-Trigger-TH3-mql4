// BiotakMenu_Ring.mqh - the RING's own home, split out of BiotakMenu_A/B
// on 2026-10-17 because BiotakMenu_A.mqh reached 1584 and BiotakMenu_B.mqh
// 1565 lines and contract 7 says a file over the 1500-line ceiling never
// grows (P-SIZE-1500): touch it = split it by owner. This IS that owner -
// the catalog (every item the ring can hold, in ONE order), the membership
// mask behind the Tools stars, and the growth law (the taper, the chord
// radius, the fit walk). Included from BiotakMenu_A.mqh BELOW the
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
#define CIRC_STAR_DEFAULT 0xFF80

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
// The mask is 16 bits (CAT_COUNT), persisted as the "STAR" UI slot.   |
// A missing key = CIRC_STAR_DEFAULT (the 9 features, bits 7..15) —   |
// the shipped look, so an upgrade changes nothing until the user      |
// moves a star (a saved 0x7F80 mask keeps sessions unstarred until    |
// the user stars it — the old bits mean what they always meant).      |
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
//--- seat. The door is the LAST seat by law — see the block above.
int RingCount() { return CircStarCount() + 1; }

int RingFeature(const int ringIdx)
{
   if(ringIdx < 0 || ringIdx >= RingCount()) return -1;
   if(ringIdx == RingCount() - 1) return CIR_TOOLS;   // the door, always last
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

double CircRadiusForN(const int n)
{
   if(n <= 9) return CIRC_RADIUS;      // 80 — the shipped look, byte-identical
   double s = MathSin(M_PI / n);
   if(s < 1e-9) return CIRC_RADIUS;
   return (CircBtnSizeForN(n) + CIRC_GAP) / (2.0 * s);
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

//--- How many seats the capped circle really shows. Nine or fewer: all of them
//--- (the 44px look is never dropped). More: the largest count whose chord
//--- radius still fits; when even nine cannot (the squeeze zone the old ring
//--- already had at a tight spot), nine — the excess stays in the Tools menu.
//--- (CircPlacedCountLive is the unfrozen half; the FROZEN half,
//--- CircPlacedCount, stays with the built-seat state in BiotakMenu_B.)

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
   int n = RingCount();
   if(n <= 9) return n;
   double fit = MathMax(CircFitLimit(), (double)CIRC_MIN_RADIUS);
   for(int k = n; k > 9; k--)
      if(CircRadiusForN(k) <= fit) return k;
   return 9;
}

#endif
