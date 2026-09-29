// BiotakMenu_B.mqh - BiotakMenu.mqh split 2026-09-29: exact lines 1421-2841, byte-identical, zero renames.
#ifndef BIOTAK_MENU_B_MQH
#define BIOTAK_MENU_B_MQH

//+------------------------------------------------------------------+
//| CUSTOM HOVER TOOLTIP — the menu draws its own box (dark chip + amber|
//| title) instead of leaving hover text to the terminal. P-UI-119       |
//| (2026-09-25): the native channel is RETIRED on the menu's own objects|
//| — the user's screenshot showed BOTH boxes at once (the drawn chip and |
//| the OS grey tooltip), so the earlier "native tooltips do not display  |
//| here" is measurably false in this build. One text owner, one box.    |
//| Anchored above the hovered item (orb / ring / tools). P-UI-31: the   |
//| tip sits on the MENU rung of the Z ladder (Z_MENU_TIP), i.e. UNDER   |
//| the settings card — and CircTipOnMove(Disarm) hides it the moment a  |
//| card opens anyway.                                                   |
//| Non-intrusive by design:
//| CircTipOnMove only ARMS the tip; CircTipTick (per-tick) shows it   |
//| after CIRC_TIP_DELAY_MS of stationary hover, and any move/press    |
//| hides it instantly. CircTipRefresh keeps visible text fresh.       |
//+------------------------------------------------------------------+
#define CIRC_TIP_BG  C'13,20,32'
#define CIRC_TIP_BD  BIO_CLR_BRAND   // P-UI-117: the palette's own cell 0; the tip's
                                     // border follows the brand, not a copy of it
// Dwell before the tip appears: stationary hover only, so normal navigation
// never flashes it (native-OS-tooltip behavior, tuned long per UX request).
#define CIRC_TIP_DELAY_MS 1500
// P-UI-120 (2026-09-25): THE CHIP IS ONE LINE. User order: «چیپ زنده: یک خط، وسط‌چین،
// Tahoma 11pt، خط دوم حذف، قاب نازک (هیرلاین) + آلفای ملایم، زاویه ۳− درجه». The box is
// therefore MEASURED from that one line (PnlTextW / PnlLineH — the one metrics owner)
// and laid CENTERED on the anchor, instead of a fixed 290x56 rect holding two
// captions. MT4 labels carry no alpha channel, so "gentle" is a tone blend toward the
// chart's own background (P-DRAW-43's language).
#define CIRC_TIP_PT      11
#define CIRC_TIP_FONT    "Tahoma"
#define CIRC_TIP_PAD_X   14    // B-01: the scale's base step — text inset, both sides
#define CIRC_TIP_PAD_Y   6     // B-01: tight
#define CIRC_TIP_TINT    15    // % blended toward the chart bg — MT4's honest "alpha"
#define CIRC_TIP_W_MAX   620   // the box never gets wider than this, whoever hovers
// P-UI-120: THE ORB'S CHIP IS ART — the whole face, not just its title. A live label
// cannot carry the −3° the order asked for (error 230), and a rectangle label cannot
// be translucent or rounded either; one baked face gives all three at once, and the
// user's own calligraphy banner is the art (tools/orb/make-tip-face.ps1 ingests it,
// keys its painted checkerboard into real alpha and bakes it at this size - MT4
// crops a bitmap label instead of scaling it). The two numbers are the master's own
// size: gen-th3-icons.js refuses to embed a .bgra that disagrees with them, and MT4
// has no way to ask a bitmap how big it is, so they are the contract.
#define CIRC_TIP_FACE    "::Files\\Icons\\tip_face.bmp"     // 200x76, the master itself
#define CIRC_TIP_FACE_W  200
#define CIRC_TIP_FACE_H  76
// P-UI-122: THE FACE IS PLACED BY ITS INK, NOT BY ITS BOX. Measured on the baked
// master (alpha profile of `tools/orb/tip-face-master.bgra`, 2026-09-25): the 200x76
// box is NOT tight at the bottom — the calligraphy band's own lowest line is row 57
// while the side ornaments hang on to row 75. Placing the BOX 12 px off the orb
// therefore left a real gap of 12 + 19 = 31 px, the reported «تریگر پرایس
// اكشن از دایره اصلی خیلی دور شده». Row 57 is the hug line — the same line the two
// end tips ride (rows 55..58) — and P-UI-123's four variants all keep it the SAME
// distance off their own near edge, so ONE number places every side.
#define CIRC_TIP_FACE_HUG   57
#define CIRC_TIP_FACE_INSET (CIRC_TIP_FACE_H - 1 - CIRC_TIP_FACE_HUG)   // 18 px
// P-UI-126 (2026-09-25) — THE CHIP STOPS TURNING; IT GETS A PLACE OF ITS OWN.
// A 90 deg face carries the Persian calligraphy SIDEWAYS («این حالت‌ها گوشه هم باید
// درست بشه») and MT4 turns no bitmap back (a label takes no angle — error 230 — and a
// bitmap label is cropped, never scaled), so the side faces WERE the defect. The order
// that replaced them names both answers and no third: «اگر فضا داشته که همون بالا باز
// بشه، اگر فضا نداشت وسط صفحه» — ABOVE the orb while the whole box fits, otherwise the
// chip's OWN PLACE (the hand's, else the chart's middle). ONE up-face, every case.
// The MODE (g_UI.tipPin, the chip card's own switch) is the other half: OFF = «با موس»,
// the hover tip this always was and the shipped default («ولی با موس کلا بهتر باشه»);
// ON = «همیشه فعال», the banner kept up at its place with or without a hover.
// The chip's two clearances — the face's table below needs them, so they live with it
// (a macro must be defined before the line that reads it, not before its own comment).
#define CIRC_TIP_GAP   12   // px clear of the described surface's own edge
#define CIRC_TIP_EDGE   4   // px of the window the chip never crosses
bool CircTipIsFace(const int feat) { return (feat == -1); }   // the orb's chip only

//--- P-UI-126: the chip's own place lives with the UI-state block that persists it
//--- (`CircTipHomeGet`/`CircTipHomeSet`, above ResetUIToDefaults).
//--- The box the chip is WEARING right now — what a grab hit-tests and what
//--- a drag moves. Written by the one show path (and by the drag's own two writes),
//--- so nothing can disagree with what is on screen.
static int s_TipBoxX = 0, s_TipBoxY = 0, s_TipBoxW = 0, s_TipBoxH = 0;

//--- P-UI-122, kept: the face is placed by its INK, not by its box. Row 57 of the
//--- 200x76 master is the calligraphy band's OWN lowest line (the side ornaments hang
//--- on to row 75), so the box rides INSET px past the gap and the band's line — not
//--- the empty margin — lands CIRC_TIP_GAP off the orb.
void CircTipFaceAbove(const int ax, const int ay, int &x, int &y, int &w, int &h)
{
   w = CIRC_TIP_FACE_W; h = CIRC_TIP_FACE_H;
   x = ax - w / 2;
   y = ay - (CIRC_ORB_RADIUS + CIRC_TIP_GAP) - h + CIRC_TIP_FACE_INSET;
}

//--- P-UI-126: the fallback box — the hand's place, else the chart's middle, centred
//--- on that point and clamped inside the window. ONE owner for both answers, so a
//--- drag and a never-placed chip cannot disagree about what "its place" means.
void CircTipHomeBox(const int cw, const int ch, int &x, int &y, int &w, int &h)
{
   w = CIRC_TIP_FACE_W; h = CIRC_TIP_FACE_H;
   int hx = 0, hy = 0;
   if(!CircTipHomeGet(hx, hy)) { hx = cw / 2; hy = ch / 2; }   // the order's own default
   x = ClampInt(hx - w / 2, CIRC_TIP_EDGE, MathMax(CIRC_TIP_EDGE, cw - w - CIRC_TIP_EDGE));
   y = ClampInt(hy - h / 2, CIRC_TIP_EDGE, MathMax(CIRC_TIP_EDGE, ch - h - CIRC_TIP_EDGE));
}
#define CIRC_PT_BADGE   7     // retired ring badges (one-line restorable)

string CircTipBg() { return g_UI.btnPrefix + "CircTipBg"; }
string CircTipTxT() { return g_UI.btnPrefix + "CircTipTxT"; }
string CircTipTxH() { return g_UI.btnPrefix + "CircTipTxH"; }
string CircTipArt() { return g_UI.btnPrefix + "CircTipArt"; }
// -2 = hidden, -1 = orb, else a CIR_* feature code (unique across ring+tools)
static int s_CircTipFeat = -2;
// Armed (pending) tip: shown by CircTipTick after the dwell elapses.
static int s_TipPendFeat = -2;
static uint s_TipPendSince = 0;
static int s_TipMX = -1, s_TipMY = -1;

// P-UI-120: the caption owner is `CircItemTooltip` and nothing else — the orb's
// title left the TEXT channel entirely when it became art, so there is no longer a
// second spelling of it anywhere in MQL (the bake script draws the only copy).
// P-UI-120: ONE owner for the chip's caption AND its box. CircTipShow and
// CircTipRefresh both come through here, so a state change can never re-measure the
// text in one path and leave the other one's box stale. The width table is the
// Arial Bold one (PnlTextW), i.e. a deliberately safe OVER-estimate for Tahoma.
string CircTipLine(const int feat, int &tw, int &w, int &h)
{
   if(CircTipIsFace(feat))      // the orb: the face IS the box — it carries its own plate,
   {                            // its own padding and its own title, all in pixels
      tw = CIRC_TIP_FACE_W;
      w  = CIRC_TIP_FACE_W;
      h  = CIRC_TIP_FACE_H;
      return "";
   }
   int cw, ch;
   CircUIMetrics(cw, ch);
   int room = MathMin(CIRC_TIP_W_MAX, cw - 16) - 2 * CIRC_TIP_PAD_X;
   string line = PnlFit(CircItemTooltip(feat), CIRC_TIP_PT, room);
   tw = PnlTextW(line, CIRC_TIP_PT);
   w  = tw + 2 * CIRC_TIP_PAD_X;
   h = PnlLineH(CIRC_TIP_PT) + 2 * CIRC_TIP_PAD_Y;
   return line;
}
// P-UI-120: the −3° tilt cannot be an MT4 OBJECT — a label takes no angle
// ("'OBJPROP_ANGLE' - improper enumerator cannot be used", error 230, measured
// 2026-09-25) and a bitmap label cannot be rotated either. So the one caption whose
// text never changes (the orb's) is BAKED — plate, frame, tilt, all in pixels — and
// every caption that carries live state ("· ON", "144.0") stays live text, upright.

//+------------------------------------------------------------------+
//| P-PERF-17: THE TIP IS PARKED, NOT DELETED                        |
//|                                                                  |
//| The hover tip is three objects (bg + title + hints) and hiding it |
//| used to DELETE all three and call a FULL ChartRedraw - then the    |
//| next hover created them again. Moving the cursor across the ring   |
//| changes the hover target repeatedly, so that churn (delete 3,      |
//| create 3, repaint EVERY object on the chart) ran again and again   |
//| during exactly the gesture the user reports as lag, on a chart     |
//| that holds thousands of objects. The tip is an overlay, so it is   |
//| PARKED off-canvas with the CIRC_HIDE_POS idiom the Tools fan       |
//| already uses, and no repaint is forced: writing an object property |
//| dirties the chart by itself (the same finding as P-PERF-04 on the  |
//| panel move path), so an explicit ChartRedraw here was pure cost.   |
//+------------------------------------------------------------------+
void CircTipPark()
{
   string bg = CircTipBg();
   if(ObjectFind(0, bg) < 0) return;   // never shown yet - nothing to park
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, CIRC_HIDE_POS);
   ObjectSetInteger(0, CircTipTxT(), OBJPROP_XDISTANCE, CIRC_HIDE_POS);
   ObjectSetInteger(0, CircTipArt(), OBJPROP_XDISTANCE, CIRC_HIDE_POS);
}
// P-UI-120: the second (hints) line is gone, so a hint label left on the chart by
// an earlier build is a ghost the user would keep seeing. One probe per show — a rare
// event, never the move stream — clears it; the name stays, so the ghost is findable.
void CircTipDropLegacy()
{
   if(ObjectFind(0, CircTipTxH()) >= 0) ObjectDelete(0, CircTipTxH());
}

void CircTipHide()
{
   if(s_CircTipFeat == -2) return;
   s_CircTipFeat = -2;
   CircTipPark();
}
// Full disarm (hide + drop a pending arm): called when a settings card opens
// so no tip survives above it or fires while it is open (phantom tip).
// P-UI-126: a PINNED chip is not a tip that can be disarmed — it is the nameplate the
// user asked to keep («برای همیشه فعال باشه»), so only its pending arm dies here.
// The card still sits over it: the chip rides Z_MENU_TIP, under the card's plate.
void CircTipDisarm()
{
   s_TipPendFeat = -2;
   if(g_UI.tipPin) return;
   CircTipHide();
}

//+------------------------------------------------------------------+
//| P-UI-121: THE CHIP NEVER SITS ON WHAT IT DESCRIBES.              |
//| Reported: «یکم چسیده هستش ... روی همون نیم‌دایره بالا قرار بگیره».  |
//| The old placement put the box's bottom 12px above the anchor's   |
//| CENTER, so on the orb (r = 32) the art sat on the medallion's    |
//| top half — the screenshot — and the only fallback was the edge.  |
//| ONE placer. A live caption (a small text box) keeps the four     |
//| sides of the item's own button, ABOVE first, and must clear the  |
//| orb; the FACE has TWO answers now (P-UI-126: above, else its own |
//| place) because a bitmap cannot be turned, so a side is not a     |
//| place it can wear. Each spot counts only when its box fits WHOLE |
//| inside the window — the one case that cannot is clamped in.      |
//| Cost: integer boxes, no terminal read, no per-tick work.         |
//+------------------------------------------------------------------+
bool CircTipCoversOrb(const int x, const int y, const int w, const int h)
{
   int ol = g_UI.menuX - CIRC_ORB_RADIUS, ot = g_UI.menuY - CIRC_ORB_RADIUS;
   return (x < ol + CIRC_ORB_SIZE && x + w > ol &&
           y < ot + CIRC_ORB_SIZE && y + h > ot);
}

void CircTipPlace(const int feat, const int ax, const int ay, const int w, const int h,
                  int &x, int &y, int &side)
{
   int cw, ch;
   CircUIMetrics(cw, ch);   // P-PERF-16: cached metrics
   const bool face = CircTipIsFace(feat);
   // Every element is written before any read: four explicit spots, so the compiler
   // sees each one assigned (a loop index does not convince its flow analysis).
   int px[4] = {0, 0, 0, 0}, py[4] = {0, 0, 0, 0};
   int pw[4] = {0, 0, 0, 0}, ph[4] = {0, 0, 0, 0};
   int n = 4;   // how many of the four spots are real answers for this kind
   if(face)
   {
      // P-UI-126: above the orb (the arc's opening onto it), else the chip's OWN
      // place. A PINNED chip with a place the hand chose has only that one answer —
      // a banner that jumped back above the orb would not be pinned at all.
      n = 2;
      CircTipFaceAbove(ax, ay, px[0], py[0], pw[0], ph[0]);
      CircTipHomeBox(cw, ch, px[1], py[1], pw[1], ph[1]);
      int hx = 0, hy = 0;
      if(g_UI.tipPin && CircTipHomeGet(hx, hy))
      {
         px[0] = px[1]; py[0] = py[1]; pw[0] = pw[1]; ph[0] = ph[1];
         n = 1;
      }
   }
   else
   {
      // A live caption is ONE rectangle on all four sides: the reach is measured from
      // the described item's own button edge, and each axis clamps first, so the fit
      // test below reads the box the chip would really wear.
      const int reach = CIRC_BTN_SIZE / 2 + CIRC_TIP_GAP;
      int lx = ClampInt(ax - w / 2, CIRC_TIP_EDGE, MathMax(CIRC_TIP_EDGE, cw - w - CIRC_TIP_EDGE));
      int ly = ClampInt(ay - h / 2, CIRC_TIP_EDGE, MathMax(CIRC_TIP_EDGE, ch - h - CIRC_TIP_EDGE));
      px[0] = lx;             py[0] = ay - reach - h;   // above
      px[1] = lx;             py[1] = ay + reach;       // below
      px[2] = ax + reach;     py[2] = ly;               // right
      px[3] = ax - reach - w; py[3] = ly;               // left
      pw[0] = w; ph[0] = h; pw[1] = w; ph[1] = h;
      pw[2] = w; ph[2] = h; pw[3] = w; ph[3] = h;
   }
   // P-UI-122/123: ONE ladder for both kinds — above first («همیشه نباید بالای
   // المان‌ها باشه ... در هر موقعیت درست باشه»). The face's spots are measured off
   // the orb itself (+ the gap) and its fallback is CLAMPED by its own owner, so it
   // needs no second reading order and no air vote.
   side = -1;
   for(int pass = 0; pass < 2 && side < 0; pass++)   // 0 = clears the orb too, 1 = fits
      for(int s = 0; s < n; s++)
      {
         if(px[s] < CIRC_TIP_EDGE || py[s] < CIRC_TIP_EDGE) continue;
         if(px[s] + pw[s] + CIRC_TIP_EDGE > cw) continue;
         if(py[s] + ph[s] + CIRC_TIP_EDGE > ch) continue;
         // The face's spots are measured off the orb itself (+ the gap), so the
         // "clears it" pass is a live-caption test only (P-UI-122).
         if(pass == 0 && !face && CircTipCoversOrb(px[s], py[s], pw[s], ph[s])) continue;
         side = s;
         break;
      }
   // No spot holds the chip whole: the one with the most air on its own outward edge
   // wins, clamped to the window (never scaled — MT4 crops a bitmap label).
   if(side < 0)
   {
      int bestAir = 0;
      for(int s = 0; s < n; s++)
      {
         int air = 0;
         if(py[s] + ph[s] <= ay)  air = py[s] - CIRC_TIP_EDGE;
         else if(py[s] >= ay)     air = ch - (py[s] + ph[s]) - CIRC_TIP_EDGE;
         else if(px[s] >= ax)     air = cw - (px[s] + pw[s]) - CIRC_TIP_EDGE;
         else                     air = px[s] - CIRC_TIP_EDGE;
         if(side < 0 || air > bestAir) { bestAir = air; side = s; }
      }
   }
   x = ClampInt(px[side], CIRC_TIP_EDGE, MathMax(CIRC_TIP_EDGE, cw - pw[side] - CIRC_TIP_EDGE));
   y = ClampInt(py[side], CIRC_TIP_EDGE, MathMax(CIRC_TIP_EDGE, ch - ph[side] - CIRC_TIP_EDGE));
}

//--- P-UI-126: the mode switch owns exactly this much — raise the banner at once when
//--- it turns ON, park it when it turns OFF. After that the tick keeps it up, and a
//--- still pointer costs it compares (see CircTipTick). The property writes below ARE
//--- the repaint: writing an object property dirties the chart by itself (P-PERF-17).
void CircTipModeChanged()
{
   s_TipPendFeat = -2;
   if(g_UI.tipPin)
   {
      int ax = 0, ay = 0;
      if(CircTipAnchor(-1, ax, ay)) CircTipShow(-1, ax, ay);
   }
   else CircTipHide();
}

//--- P-UI-126: the orb's own move path calls this (one bool) so a pinned banner that
//--- rides "above the orb" is re-placed by the next tick, not per move event.
static bool s_TipDirty = false;
void CircTipPinnedTouch() { s_TipDirty = true; }

//+------------------------------------------------------------------+
//| P-UI-126: THE HAND PLACES THE CHIP.                              |
//|                                                                  |
//| Pinned mode is the ONE state where the banner stands still (so a |
//| press on it is unambiguous) and where the user's own place is     |
//| what it wears — so the grab lives there, under the menu's own     |
//| drag claim, and a ring item under the box cannot also answer the  |
//| press. Bound: one re-place per REAL pointer move (the art's two   |
//| coordinates — the plate and the label are parked), no timer, no   |
//| per-tick work, and the place is written to the UI block once, on  |
//| release («فشار بار الکی نداشته باشیم»).                           |
//+------------------------------------------------------------------+
static bool s_TipDrag = false;
static bool s_TipMoved = false;   // a real move (>= 1 px) eats the release's click echo
static int  s_TipGrabDX = 0, s_TipGrabDY = 0;

bool CircTipGrabStart(const int mx, const int my)
{
   if(!g_UI.tipPin || s_CircTipFeat == -2) return false;
   if(mx < s_TipBoxX || mx > s_TipBoxX + s_TipBoxW) return false;
   if(my < s_TipBoxY || my > s_TipBoxY + s_TipBoxH) return false;
   s_TipDrag = true;
   s_TipGrabDX = (s_TipBoxX + s_TipBoxW / 2) - mx;   // the place IS the box's centre
   s_TipGrabDY = (s_TipBoxY + s_TipBoxH / 2) - my;
   return true;
}

void CircTipDragTo(const int mx, const int my)
{
   if(!s_TipDrag) return;
   int cw, ch;
   CircUIMetrics(cw, ch);
   const int hw = CIRC_TIP_FACE_W / 2, hh = CIRC_TIP_FACE_H / 2;
   int cx = ClampInt(mx + s_TipGrabDX, CIRC_TIP_EDGE + hw, MathMax(CIRC_TIP_EDGE + hw, cw - CIRC_TIP_EDGE - hw));
   int cy = ClampInt(my + s_TipGrabDY, CIRC_TIP_EDGE + hh, MathMax(CIRC_TIP_EDGE + hh, ch - CIRC_TIP_EDGE - hh));
   int hx = 0, hy = 0;
   if(CircTipHomeGet(hx, hy) && hx == cx && hy == cy) return;   // same spot: no write at all
   CircTipHomeSet(cx, cy);
   int x = 0, y = 0, w = 0, h = 0;
   CircTipHomeBox(cw, ch, x, y, w, h);
   if(x == s_TipBoxX && y == s_TipBoxY) return;
   s_TipBoxX = x; s_TipBoxY = y;
   s_TipMoved = true;
   string ar = CircTipArt();
   ObjectSetInteger(0, ar, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, ar, OBJPROP_YDISTANCE, y);
}

void CircTipDragEnd(const bool dropped)
{
   if(!s_TipDrag) return;
   s_TipDrag = false;
   if(!dropped) return;
   SaveUIStates();    // the hand's answer becomes durable with the key it lives under
   s_TipDirty = true; // the tick settles the plate and the label into the same box
}

//--- P-UI-126: the release net (`ChartPointerFinalizeOnUps`) — a motionless release
//--- emits no move event, so the drag would outlive its own button-up. Its caller gates
//--- it on a QUIET pointer, because that same net also runs on the press itself.
void CircTipDragFinalize()
{
   if(!s_TipDrag) return;
   CircTipDragEnd(true);
   DragReleaseIf(DRAG_MENU);
   CircUnlockChart();
   if(s_TipMoved) UISuppressNextClick();
   s_TipMoved = false;
}

//--- P-DRAW-19/A-09: this gesture takes the view lock, so it NAMES itself to the 250 ms
//--- reconcile (`ChartLockIntended`, BiotakPanels) or the lock is read as a leak and
//--- freed under the hand. One bool read, and the day it is born.
bool CircTipDragLive() { return s_TipDrag; }

void CircTipShow(const int feat, const int ax, const int ay)
{
   int tw = 0, w = 0, h = 0;
   const bool isFace = CircTipIsFace(feat);
   string line = CircTipLine(feat, tw, w, h);
   int x = 0, y = 0, side = 0;
   CircTipPlace(feat, ax, ay, w, h, x, y, side);   // P-UI-121/126: the box's ONE placer
   s_TipBoxX = x; s_TipBoxY = y; s_TipBoxW = w; s_TipBoxH = h;

   CircTipDropLegacy();
   // The LIVE plate: every item caption wears it. For the orb it is PARKED — the
   // face brings its own plate, its own gold hairline and a real alpha channel.
   string bg = CircTipBg();
   if(ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, isFace ? CIRC_HIDE_POS : x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, isFace ? CIRC_HIDE_POS : y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, GetZoneRenderColor(CIRC_TIP_BG, CIRC_TIP_TINT));
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, CIRC_TIP_BD);
   ObjectSetInteger(0, bg, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER, Z_MENU_TIP_BG);

   // ONE centered line — the whole chip is the caption now (P-UI-120). TWO content
   // kinds share this one box: the LIVE line (every feature whose text carries
   // state) and the BAKED art (the orb's title). The one that is not in use is
   // PARKED, never left behind, so a hover moving orb -> item -> orb shows one
   // caption at a time.
   string tt = CircTipTxT();
   if(ObjectFind(0, tt) < 0) ObjectCreate(0, tt, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, tt, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   // Centered, not padded: the box hugs the caption, so the slack the measurement
   // leaves is what centers it (a magic pad only ever fits one caption's length).
   int lh = PnlLineH(CIRC_TIP_PT);
   ObjectSetInteger(0, tt, OBJPROP_XDISTANCE, isFace ? CIRC_HIDE_POS : x + (w - tw) / 2);
   ObjectSetInteger(0, tt, OBJPROP_YDISTANCE, isFace ? CIRC_HIDE_POS : y + (h - lh) / 2);
   ObjectSetString(0, tt, OBJPROP_TEXT, line);
   ObjectSetString(0, tt, OBJPROP_FONT, CIRC_TIP_FONT);
   ObjectSetInteger(0, tt, OBJPROP_FONTSIZE, PnlPt(CIRC_TIP_PT));
   ObjectSetInteger(0, tt, OBJPROP_COLOR, CIRC_TIP_BD);
   ObjectSetInteger(0, tt, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, tt, OBJPROP_BACK, false);
   ObjectSetInteger(0, tt, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tt, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, tt, OBJPROP_ZORDER, Z_MENU_TIP);

   string ar = CircTipArt();
   if(ObjectFind(0, ar) < 0)
   {
      // P-UI-126: the face is ONE file in ONE orientation now, so its bitmap and its
      // size are written at CREATION and never again — a hover that crosses orb and
      // items re-writes two positions instead of re-pointing a resource.
      ObjectCreate(0, ar, OBJ_BITMAP_LABEL, 0, 0, 0);
      ObjectSetString(0, ar, OBJPROP_BMPFILE, 0, CIRC_TIP_FACE);
      ObjectSetString(0, ar, OBJPROP_BMPFILE, 1, CIRC_TIP_FACE);
      ObjectSetInteger(0, ar, OBJPROP_XSIZE, CIRC_TIP_FACE_W);
      ObjectSetInteger(0, ar, OBJPROP_YSIZE, CIRC_TIP_FACE_H);
   }
   ObjectSetInteger(0, ar, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, ar, OBJPROP_XDISTANCE, isFace ? x : CIRC_HIDE_POS);
   ObjectSetInteger(0, ar, OBJPROP_YDISTANCE, isFace ? y : CIRC_HIDE_POS);
   ObjectSetInteger(0, ar, OBJPROP_BACK, false);
   ObjectSetInteger(0, ar, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, ar, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, ar, OBJPROP_ZORDER, Z_MENU_TIP);

   s_CircTipFeat = feat;
   // P-PERF-17: no forced repaint - the property writes above already dirtied the
   // chart, and this runs on the hover path where a full repaint is the cost.
}

// Feature under the cursor (-2 = none, -1 = orb, else CIR_* code).
int CircTipFeatAt(const int mx, const int my)
{
   int ox = g_UI.menuX - CIRC_ORB_SIZE / 2;
   int oy = g_UI.menuY - CIRC_ORB_SIZE / 2;
   bool onOrb = (mx >= ox && mx <= ox + CIRC_ORB_SIZE && my >= oy && my <= oy + CIRC_ORB_SIZE);
   if(!g_UI.menuVisible)
      return onOrb ? -1 : -2;   // collapsed: orb only
   int hit = CircItemAt(mx, my);
   if(hit >= 0) return RingFeature(hit);
   int th2 = ToolsItemAt(mx, my);
   if(th2 >= 0) return ToolFeature(th2);
   return onOrb ? -1 : -2;
}

// Anchor (item center) for a feature; false when the item is gone.
bool CircTipAnchor(const int feat, int &ax, int &ay)
{
   if(feat == -1) { ax = g_UI.menuX; ay = g_UI.menuY; return true; }
   if(g_UI.menuVisible)
   {
      for(int i = 0; i < RING_COUNT; i++)
         if(RingFeature(i) == feat) { CircLayout(i, ax, ay); return true; }
      for(int t = 0; t < TOOL_COUNT; t++)
         if(ToolFeature(t) == feat) { ToolsLayout(t, ax, ay); return true; }
   }
   return false;
}

// Hover dispatcher — call on every mouse move (before any press/visibility
// guards so leaving the menu also hides a stale tip). Only ARMS the tip;
// CircTipTick() (per-tick) shows it after CIRC_TIP_DELAY_MS of stationary
// hover, so it never intrudes on normal navigation.
void CircTipOnMove(const int mx, const int my, const bool leftDown)
{
   // same-spot repeats (MT4 re-fires move events) need no re-hit-test
   static bool s_TipDown = false;
   if(mx == s_TipMX && my == s_TipMY && leftDown == s_TipDown) return;
   s_TipMX = mx; s_TipMY = my; s_TipDown = leftDown;
   // P-UI-126: a PINNED chip is not hover-driven — it stays up wherever the pointer
   // is and the tick keeps its placement true, so there is nothing to arm or hide.
   if(g_UI.tipPin) return;
   if(leftDown || g_LongPressItem >= 0) { s_TipPendFeat = -2; CircTipHide(); return; }
   if(g_UIPanelOpen) { s_TipPendFeat = -2; CircTipHide(); return; }   // a card covers the menu — never arm under it
   int feat = CircTipFeatAt(mx, my);
   if(feat == -2) { s_TipPendFeat = -2; CircTipHide(); return; }
   // P-PERF-17: the tip's visibility is the STATE variable, not an ObjectFind -
   // the objects live on permanently now (parked), so probing the chart per move
   // would both cost a terminal call and answer the wrong question.
   if(feat != -2 && feat == s_CircTipFeat) { s_TipPendFeat = -2; return; }
   if(feat != s_TipPendFeat) { s_TipPendFeat = feat; s_TipPendSince = GetTickCount(); }
   if(s_CircTipFeat != -2) CircTipHide();   // moved to another item: hide now, arm new
}

// Per-tick: show an armed tip once its dwell elapsed (mouse stationary — any
// move re-arms/cancels via CircTipOnMove first).
void CircTipTick()
{
   // P-PERF-17: the tip's objects are permanent now, so a bulk wipe elsewhere in
   // the session (a parameter rebuild clears the chart) could leave the STATE
   // saying "shown" while nothing is painted. One existence probe per TICK (4/s)
   // instead of per move keeps that self-healing at a negligible cost.
   if(s_CircTipFeat != -2 && ObjectFind(0, CircTipBg()) < 0) s_CircTipFeat = -2;

   // P-UI-126: «همیشه فعال» — the orb's banner at its place, hovered or not. The tick
   // owns the PLACEMENT and the one show it owes when the box really moved or the
   // chip is not up yet; a resting tick is compares only (the orb's own move path
   // raises s_TipDirty, so nothing walks the hover stream for this).
   if(g_UI.tipPin)
   {
      s_TipPendFeat = -2;
      if(s_CircTipFeat == -1 && !s_TipDirty) return;
      int pax = 0, pay = 0;
      if(!CircTipAnchor(-1, pax, pay)) return;
      s_TipDirty = false;
      CircTipShow(-1, pax, pay);
      return;
   }

   if(s_TipPendFeat == -2) return;
   if(g_UIPanelOpen) { s_TipPendFeat = -2; return; }   // opened after arming — never fire over it
   if(GetTickCount() - s_TipPendSince < CIRC_TIP_DELAY_MS) return;
   int feat = s_TipPendFeat;
   s_TipPendFeat = -2;
   int ax = 0, ay = 0;
   if(CircTipFeatAt(s_TipMX, s_TipMY) != feat) return;   // moved on without events
   if(!CircTipAnchor(feat, ax, ay)) return;
   CircTipShow(feat, ax, ay);
}

// Re-apply the text while visible (state changed under a stationary cursor).
void CircTipRefresh()
{
   if(s_CircTipFeat == -2) return;   // P-PERF-17: state, not ObjectFind
   // P-UI-120: a re-state, not a text write: the status fragment changes the
   // caption's LENGTH, so its box has to be re-measured with it — one path owns both.
   int ax = 0, ay = 0;
   if(!CircTipAnchor(s_CircTipFeat, ax, ay)) return;
   CircTipShow(s_CircTipFeat, ax, ay);
   ThrottledChartRedraw();   // P-PERF-17: coalesced, never a bare full repaint
}

//+------------------------------------------------------------------+
//| P-PERF-16: CHART METRICS ARE CACHED, NOT RE-READ PER ITEM         |
//|                                                                  |
//| WHY (measured shape, not a guess): CircItemAt() asks CircLayout() |
//| once per ring item, ToolsItemAt() asks SubPlaceItem() once per    |
//| tile, and CircPointOnMenu() asks both. Each of those read          |
//| CHART_WIDTH_IN_PIXELS + CHART_HEIGHT_IN_PIXELS straight from the   |
//| terminal, and CircLayout() also called CircFitRadius(), which      |
//| walks every ring item doing sin/cos - so ONE hit test cost 16-40   |
//| terminal reads and O(RING_COUNT^2) trigonometry just to answer     |
//| "which button is under the cursor?". Every cursor move repeats it. |
//|                                                                  |
//| The size cannot change inside a hit test, so the metrics are read  |
//| once and invalidated on the events that can change them (chart-    |
//| change notification + a 250 ms safety refresh in OnTimer), which   |
//| is how UI toolkits keep a layout cache honest. The reader keeps the|
//| old "<=0 -> 1920x1080" fallback so no caller can see a bad size.   |
//+------------------------------------------------------------------+
static int  s_uiCw = 0, s_uiCh = 0;
static bool s_uiMetricsStale = true;

void CircUIMetricsInvalidate() { s_uiMetricsStale = true; }

void CircUIMetrics(int &cw, int &ch)
{
   if(s_uiMetricsStale || s_uiCw <= 0 || s_uiCh <= 0)
   {
      s_uiCw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
      s_uiCh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
      s_uiMetricsStale = false;
   }
   cw = s_uiCw;
   ch = s_uiCh;
   if(cw <= 0) cw = 1920;
   if(ch <= 0) ch = 1080;
}

double CircFitRadius(const int cw, const int ch, const int ox, const int oy)
{
   // P-PERF-16: pure function of its four arguments and compile-time constants,
   // asked once per ring item per hit test. The fit does not depend on the item,
   // so it is computed once per (cw,ch,ox,oy) and remembered.
   static int    s_fitCw = 0, s_fitCh = 0, s_fitOx = 0, s_fitOy = 0;
   static double s_fitR = 0.0;
   if(s_fitR > 0.0 && cw == s_fitCw && ch == s_fitCh && ox == s_fitOx && oy == s_fitOy)
      return s_fitR;

   double r = CIRC_RADIUS;
   for(int i = 0; i < RING_COUNT; i++)
   {
      double deg = (-90.0 + 360.0 * i / RING_COUNT) * M_PI / 180.0;
      double c = MathCos(deg);
      double s = MathSin(deg);
      double lim = 1e18;
      if(c > 1e-6)        lim = MathMin(lim, (cw - CIRC_PAD - ox - CIRC_ITEM_REACH) / c);
      else if(c < -1e-6)  lim = MathMin(lim, (ox - CIRC_PAD - CIRC_ITEM_REACH) / (-c));
      if(s > 1e-6)        lim = MathMin(lim, (ch - CIRC_PAD - oy - CIRC_ITEM_REACH) / s);
      else if(s < -1e-6)  lim = MathMin(lim, (oy - CIRC_PAD - CIRC_ITEM_REACH) / (-s));
      if(lim < 1e17) r = MathMin(r, lim);
   }
   if(r < CIRC_MIN_RADIUS) r = CIRC_MIN_RADIUS;
   if(r > CIRC_RADIUS) r = CIRC_RADIUS;

   s_fitCw = cw; s_fitCh = ch; s_fitOx = ox; s_fitOy = oy; s_fitR = r;
   return r;
}

void CircLayout(const int i, int &x, int &y)
{
   int cw, ch;
   CircUIMetrics(cw, ch);   // P-PERF-16: cached - no terminal read per item
   int ox = g_UI.menuX;
   int oy = g_UI.menuY;

   bool nearLeft   = (ox <= CIRC_EDGE_TRIGGER);
   bool nearRight  = (ox >= cw - CIRC_EDGE_TRIGGER);
   bool nearTop    = (oy <= CIRC_EDGE_TRIGGER);
   bool nearBottom = (oy >= ch - CIRC_EDGE_TRIGGER);

   if(nearLeft || nearRight || nearTop || nearBottom)
   {
      int step = CIRC_BTN_SIZE + CIRC_GAP;
      int trainLen = CIRC_ORB_SIZE / 2 + CIRC_BTN_SIZE / 2 + CIRC_GAP + (RING_COUNT - 1) * step;
      // P-UI-26: clamp the rail's CROSS axis so buttons never draw half
      // off-chart. One uniform shift for the whole train — never a per-item
      // clamp (that stacks the train, P-UI-13) and never a radius shrink
      // (R-SUBLADDER). The orb itself stays where the user put it.
      int half = CIRC_BTN_SIZE / 2 + CIRC_PAD;
      if(nearLeft || nearRight)
      {
         x = MathMax(half, MathMin(cw - half, ox));
         int upRoom   = oy - CIRC_PAD - CIRC_BTN_SIZE / 2;
         int downRoom = ch - CIRC_PAD - oy - CIRC_BTN_SIZE / 2;
         int dir = (upRoom >= downRoom) ? -1 : 1;
         if(dir == -1 && upRoom < trainLen && downRoom >= trainLen) dir = 1;
         else if(dir == 1 && downRoom < trainLen && upRoom >= trainLen) dir = -1;
         y = oy + dir * (CIRC_ORB_SIZE / 2 + CIRC_BTN_SIZE / 2 + CIRC_GAP + i * step);
      }
      else
      {
         y = MathMax(half, MathMin(ch - half, oy));
         int leftRoom  = ox - CIRC_PAD - CIRC_BTN_SIZE / 2;
         int rightRoom = cw - CIRC_PAD - ox - CIRC_BTN_SIZE / 2;
         int dir = (leftRoom >= rightRoom) ? -1 : 1;
         if(dir == -1 && leftRoom < trainLen && rightRoom >= trainLen) dir = 1;
         else if(dir == 1 && rightRoom < trainLen && leftRoom >= trainLen) dir = -1;
         x = ox + dir * (CIRC_ORB_SIZE / 2 + CIRC_BTN_SIZE / 2 + CIRC_GAP + i * step);
      }
   }
   else
   {
      double r = CircFitRadius(cw, ch, ox, oy);
      double deg = (-90.0 + 360.0 * i / RING_COUNT) * M_PI / 180.0;
      x = ox + (int)MathRound(r * MathCos(deg));
      y = oy + (int)MathRound(r * MathSin(deg));
   }
}

//+------------------------------------------------------------------+
//| R-SUBLADDER — the scalable sub-menu geometry engine.             |
//|                                                                  |
//| Pure maths + chart metrics; all object plumbing stays in the     |
//| create/move/delete sections below. Nothing here draws.           |
//|                                                                  |
//| The ONE invariant: two sub-menu buttons are never closer than    |
//| CIRC_BTN_SIZE + SUB_MIN_GAP, and nothing ever lands on the orb.  |
//| That is why the radius is never shrunk below SubChordRadius() —  |
//| shrinking past it is exactly how P-UI-13 stacked a fan onto one  |
//| line. When a geometry cannot hold the invariant at the current   |
//| menu position, the mode ESCALATES (fan -> rail -> grid panel)    |
//| instead of squeezing. Proven by tools/submenu_geometry_check.js. |
//+------------------------------------------------------------------+

//--- chart metrics + menu origin, shared by every mode below
void SubChartRect(int &cw, int &ch, int &ox, int &oy)
{
   CircUIMetrics(cw, ch);   // P-PERF-16: cached - SubPlaceItem/SubMode call this per tile
   ox = g_UI.menuX;
   oy = g_UI.menuY;
}

// How many rows this CHART can actually show. Deliberately computed WITHOUT
// SubIsPaged() so SubMode() can call SubPageSize() without recursing; it always
// reserves the pager strip, so the answer is never larger than reality.
int SubPageRowsCap()
{
   int cw, ch, ox, oy;
   SubChartRect(cw, ch, ox, oy);
   int room = ch - 2 * CIRC_PAD - SUB_GRID_HDR - SUB_GRID_PAD - SUB_GRID_PGR
              + SUB_CELL_GAP;
   int r = room / SUB_GRID_PITCH;
   if(r < 1) r = 1;
   if(r > SUB_PAGE_ROWS) r = SUB_PAGE_ROWS;
   return r;
}
// Cells shown per page = columns x rows-that-fit. Both are chart-derived, so a
// short chart pages EARLIER instead of pushing rows off the bottom edge.
int SubPageSize() { return SUB_GRID_COLS * SubPageRowsCap(); }

// Minimum radius at which `n` buttons on a sweep of `sweepDeg` still keep
// SUB_MIN_GAP clear between neighbours. Never go below this.
double SubChordRadius(const int n, const double sweepDeg)
{
   if(n < 2) return 0.0;
   double halfStep = (sweepDeg / (n - 1)) / 2.0;
   double s = MathSin(halfStep * M_PI / 180.0);
   if(s < 1e-6) return 1e9;
   return (CIRC_BTN_SIZE + SUB_MIN_GAP) / (2.0 * s);
}

// Radius that keeps every FAN button inside the padded chart rect (the same
// ray-vs-bounds walk CircFitRadius() does for the ring). Capped at TOOL_RADIUS;
// the caller compares the result against SubChordRadius() to decide whether the
// fan is usable at all at this position.
double SubFanFitRadius(const int ox, const int oy, const int cw, const int ch)
{
   double r = TOOL_RADIUS;
   double reach = CIRC_PAD + CIRC_BTN_SIZE / 2 + CIRC_BG_MARGIN;
   double step = (TOOL_COUNT > 1) ? TOOL_SPREAD / (TOOL_COUNT - 1) : 0.0;
   double start = 210.0 - TOOL_SPREAD / 2.0;      // 210 deg = the Tools axis
   for(int k = 0; k < TOOL_COUNT; k++)
   {
      double deg = (start + k * step) * M_PI / 180.0;
      double c = MathCos(deg);
      double s = MathSin(deg);
      double lim = 1e18;
      if(c > 1e-6)       lim = MathMin(lim, (cw - reach - ox) / c);
      else if(c < -1e-6) lim = MathMin(lim, (ox - reach) / (-c));
      if(s > 1e-6)       lim = MathMin(lim, (ch - reach - oy) / s);
      else if(s < -1e-6) lim = MathMin(lim, (oy - reach) / (-s));
      if(lim < 1e17) r = MathMin(r, lim);
   }
   if(r > TOOL_RADIUS) r = TOOL_RADIUS;
   return r;
}

// The ring's OWN rail rule (CircLayout): the train runs along the axis of the
// near edge and points at the side with more room. Returns false when no edge is
// near — the caller then uses the arc/ring. `fits` tells whether the train
// actually has room; when it does not the caller escalates to the grid panel.
// NOTE: the old Tools rail MIRRORED ring item 1's direction, which pointed the
// train off-chart at a corner (top-left/bottom-right) — this picks the free axis
// instead, so the train is correct on all four edges and all four corners.
bool SubRailAxis(const int n, const int ox, const int oy, const int cw, const int ch,
                 int &ux, int &uy, bool &fits)
{
   ux = 0; uy = 0; fits = false;
   bool nearLeft   = (ox <= CIRC_EDGE_TRIGGER);
   bool nearRight  = (ox >= cw - CIRC_EDGE_TRIGGER);
   bool nearTop    = (oy <= CIRC_EDGE_TRIGGER);
   bool nearBottom = (oy >= ch - CIRC_EDGE_TRIGGER);
   if(!(nearLeft || nearRight || nearTop || nearBottom)) return false;

   int pitch    = CIRC_BTN_SIZE + CIRC_GAP;
   int trainLen = CIRC_ORB_SIZE / 2 + CIRC_BTN_SIZE / 2 + CIRC_GAP
                  + (n - 1) * pitch + CIRC_BTN_SIZE / 2 + CIRC_BG_MARGIN;
   if(nearLeft || nearRight)
   {
      int upRoom   = oy - CIRC_PAD - CIRC_BTN_SIZE / 2;
      int downRoom = ch - CIRC_PAD - oy - CIRC_BTN_SIZE / 2;
      int dir = (upRoom >= downRoom) ? -1 : 1;
      if(dir == -1 && upRoom < trainLen && downRoom >= trainLen) dir = 1;
      else if(dir == 1 && downRoom < trainLen && upRoom >= trainLen) dir = -1;
      uy = dir;
      fits = ((dir == -1) ? upRoom : downRoom) >= trainLen;
      return true;
   }
   int leftRoom  = ox - CIRC_PAD - CIRC_BTN_SIZE / 2;
   int rightRoom = cw - CIRC_PAD - ox - CIRC_BTN_SIZE / 2;
   int dir = (leftRoom >= rightRoom) ? -1 : 1;
   if(dir == -1 && leftRoom < trainLen && rightRoom >= trainLen) dir = 1;
   else if(dir == 1 && rightRoom < trainLen && leftRoom >= trainLen) dir = -1;
   ux = dir;
   fits = ((dir == -1) ? leftRoom : rightRoom) >= trainLen;
   return true;
}

// A full ring needs SUB_RING_RADIUS + half a button + the glow margin clear on
// all four sides, otherwise items leave the chart and the clamp destroys the
// spread (P-UI-13). Not fitting is fine — the caller escalates to the grid.
bool SubRingFits(const int ox, const int oy, const int cw, const int ch)
{
   int need = SUB_RING_RADIUS + CIRC_BTN_SIZE / 2 + CIRC_BG_MARGIN;
   return (ox - need >= CIRC_PAD) && (ox + need <= cw - CIRC_PAD) &&
          (oy - need >= CIRC_PAD) && (oy + need <= ch - CIRC_PAD);
}

//--- active mode + paging state. The mode is cached against a cheap fingerprint
//    (count, chart, menu origin) because ToolsLayout() runs per item on several
//    paths. While the orb is being dragged the mode is FROZEN: switching geometry
//    mid-drag would rebuild objects under the hand (and flicker) — the release
//    path re-evaluates instead.
static int s_SubMode    = -1;   // ENUM_SUB_MODE, -1 = not computed yet
static int s_SubModeKey = 0;
static int g_ToolsPage  = 0;    // paged grid only (0-based)

void SubInvalidateLayout()
{
   s_SubMode    = -1;
   s_SubModeKey = 0;
}

int SubMode()
{
   if(g_OrbDragging && s_SubMode >= 0) return s_SubMode;   // frozen mid-drag

   int cw, ch, ox, oy;
   SubChartRect(cw, ch, ox, oy);
   int key = TOOL_COUNT * 1000003 + cw * 1009 + ch * 101 + ox * 7 + oy;
   if(s_SubMode >= 0 && key == s_SubModeKey) return s_SubMode;

   int mode = SUB_MODE_GRID;                    // the grid is the universal fallback
   int ux = 0, uy = 0;
   bool railFits = false;
   if(TOOL_COUNT <= SUB_FAN_MAX)
   {
      if(SubRailAxis(TOOL_COUNT, ox, oy, cw, ch, ux, uy, railFits))
         mode = railFits ? SUB_MODE_RAIL : SUB_MODE_GRID;
      else if(SubFanFitRadius(ox, oy, cw, ch) >= SubChordRadius(TOOL_COUNT, TOOL_SPREAD))
         mode = SUB_MODE_FAN;
      else
         mode = SUB_MODE_GRID;                 // the arc cannot hold the invariant
   }
   else if(TOOL_COUNT <= SUB_RING_MAX)
      mode = SubRingFits(ox, oy, cw, ch) ? SUB_MODE_RING : SUB_MODE_GRID;
   else
      mode = (TOOL_COUNT > SubPageSize()) ? SUB_MODE_GRID_PAGED : SUB_MODE_GRID;

   s_SubMode    = mode;
   s_SubModeKey = key;
   return mode;
}

bool SubIsPanelMode()
{
   int m = SubMode();
   return (m == SUB_MODE_GRID || m == SUB_MODE_GRID_PAGED);
}
bool SubIsPaged() { return (SubMode() == SUB_MODE_GRID_PAGED); }

int SubPageCount()
{
   if(!SubIsPaged()) return 1;
   int ps = SubPageSize();
   return (TOOL_COUNT + ps - 1) / ps;
}
// Only the items on the current page are real; the rest park off-screen.
bool SubItemOnPage(const int i)
{
   if(!SubIsPaged()) return true;
   return ((i / SubPageSize()) == g_ToolsPage);
}
int SubVisibleRows()
{
   int n;
   if(!SubIsPaged())
      n = TOOL_COUNT;
   else
      n = TOOL_COUNT - g_ToolsPage * SubPageSize();
   int rows = (n + SUB_GRID_COLS - 1) / SUB_GRID_COLS;
   int cap  = SubPageRowsCap();
   if(rows < 1)   return 1;
   if(rows > cap) return cap;
   return rows;
}
// Panel WIDTH is fixed (4 columns) so exactly one BMP covers it; the HEIGHT
// varies with the row count, which is why sub_panel_r<N>[p].bmp exists per row.
int SubPanelWidth()  { return SUB_GRID_COLS * SUB_CELL_VIS + (SUB_GRID_COLS - 1) * SUB_CELL_GAP + 2 * SUB_GRID_PAD; }
int SubPanelHeight()
{
   int rows = SubVisibleRows();
   return SUB_GRID_HDR + rows * SUB_CELL_VIS + (rows - 1) * SUB_CELL_GAP
          + SUB_GRID_PAD + (SubIsPaged() ? SUB_GRID_PGR : 0);
}

// Panel rect: beside the orb on whichever side has room, then clamped on-chart.
// The orb gap guarantees the panel can never cover the orb, so no z-order fight.
// The clamp is a FLOOR (never a spread): the panel's left/top edge always stays
// on-chart even when the chart is narrower than the panel, so a shrunken chart
// clips the far edge instead of pushing the panel off-screen (same degradation
// the settings cards accept — PnlClampOpenPanel).
void SubPanelRect(int &px, int &py, int &pw, int &ph)
{
   int cw, ch, ox, oy;
   SubChartRect(cw, ch, ox, oy);
   pw = SubPanelWidth();
   ph = SubPanelHeight();

   int gap = CIRC_ORB_SIZE / 2 + SUB_ORB_GAP;
   int minX = CIRC_PAD, maxX = cw - CIRC_PAD - pw;
   int minY = CIRC_PAD, maxY = ch - CIRC_PAD - ph;
   if(maxX < minX) maxX = minX;
   if(maxY < minY) maxY = minY;

   int leftX  = ox - gap - pw;
   int rightX = ox + gap;
   int belowY = oy + gap;
   int aboveY = oy - gap - ph;

   bool okLeft  = (leftX  >= minX && leftX  <= maxX);
   bool okRight = (rightX >= minX && rightX <= maxX);
   bool okBelow = (belowY >= minY && belowY <= maxY);
   bool okAbove = (aboveY >= minY && aboveY <= maxY);

   // Prefer the LEFT side (the Tools axis points up-left, so the panel lands in
   // the sub-menu's own direction); fall back to the side with room, then to a
   // band above/below the orb, and only then to a clamped placement.
   px = rightX;
   py = oy - ph / 2;
   if(okLeft)             px = leftX;
   else if(okRight)       px = rightX;
   else if(okBelow)     { px = ox - pw / 2; py = belowY; }
   else if(okAbove)     { px = ox - pw / 2; py = aboveY; }
   else if(leftX > rightX) px = leftX;

   if(px < minX) px = minX;
   if(px > maxX) px = maxX;
   if(py < minY) py = minY;
   if(py > maxY) py = maxY;
}

// Centre of sub-item `i` in the active mode. Items on a page that is not shown
// park at CIRC_HIDE_POS so the hit-test and the tooltip can never answer for them.
void SubPlaceItem(const int i, int &x, int &y)
{
   int cw, ch, ox, oy;
   SubChartRect(cw, ch, ox, oy);
   int mode = SubMode();

   if(mode == SUB_MODE_GRID || mode == SUB_MODE_GRID_PAGED)
   {
      if(!SubItemOnPage(i)) { x = CIRC_HIDE_POS; y = CIRC_HIDE_POS; return; }
      int px, py, pw, ph;
      SubPanelRect(px, py, pw, ph);
      int k = SubIsPaged() ? (i % SubPageSize()) : i;
      x = px + SUB_GRID_PAD + (k % SUB_GRID_COLS) * SUB_GRID_PITCH + SUB_CELL_VIS / 2;
      y = py + SUB_GRID_HDR + (k / SUB_GRID_COLS) * SUB_GRID_PITCH + SUB_CELL_VIS / 2;
      return;
   }

   if(mode == SUB_MODE_RAIL)
   {
      int ux = 0, uy = 0;
      bool fits = false;
      SubRailAxis(TOOL_COUNT, ox, oy, cw, ch, ux, uy, fits);
      int dist = CIRC_ORB_SIZE / 2 + CIRC_BTN_SIZE / 2 + CIRC_GAP
                 + i * (CIRC_BTN_SIZE + CIRC_GAP);
      x = ox + ux * dist;
      y = oy + uy * dist;
      return;
   }

   double r, startDeg, stepDeg;
   if(mode == SUB_MODE_RING)
   {
      r = SUB_RING_RADIUS;
      startDeg = -90.0;
      stepDeg  = 360.0 / TOOL_COUNT;
   }
   else
   {
      r = MathMin(TOOL_RADIUS, SubFanFitRadius(ox, oy, cw, ch));
      double floorR = SubChordRadius(TOOL_COUNT, TOOL_SPREAD);
      if(r < floorR) r = floorR;               // never below the collision floor
      startDeg = 210.0 - TOOL_SPREAD / 2.0;
      stepDeg  = (TOOL_COUNT > 1) ? TOOL_SPREAD / (TOOL_COUNT - 1) : 0.0;
   }
   double deg = (startDeg + i * stepDeg) * M_PI / 180.0;
   x = ox + (int)MathRound(r * MathCos(deg));
   y = oy + (int)MathRound(r * MathSin(deg));
}

void ToolsLayout(const int toolIdx, int &x, int &y)
{
   SubPlaceItem(toolIdx, x, y);
   if(x <= CIRC_HIDE_POS / 2) return;    // parked off-page — leave it parked

   // Last-resort safety clamp only. The fit maths above already keeps every button
   // inside the padded rect; never rely on this clamp to spread items (P-UI-13).
   // The margin follows the ACTIVE SKIN (the grid tile is 6px narrower than the
   // disc), so the clamp is exactly as tight as the art really is.
   int cw, ch, ox, oy;
   SubChartRect(cw, ch, ox, oy);
   int half = SubBgSize() / 2;
   int minX = CIRC_PAD + half;
   int maxX = cw - CIRC_PAD - half;
   int minY = CIRC_PAD + half;
   int maxY = ch - CIRC_PAD - half;
   if(x < minX) x = minX;
   if(x > maxX) x = maxX;
   if(y < minY) y = minY;
   if(y > maxY) y = maxY;
}

int ToolsItemAt(const int mx, const int my)
{
   if(!g_ToolsOpen || !g_UI.menuVisible) return -1;
   // Hit tile == the item's own canvas: 52px in the fan/ring (the disc skin),
   // 46px in the grid (== SUB_GRID_PITCH, so adjacent tiles ABUT exactly — no
   // dead strip between cells and no overlap that would make a click ambiguous).
   int hitHalf = SubIsPanelMode() ? SUB_GRID_PITCH / 2
                                  : CIRC_BTN_SIZE / 2 + CIRC_BG_MARGIN;
   for(int i = 0; i < TOOL_COUNT; i++)
   {
      if(!SubItemOnPage(i)) continue;    // parked items must never answer a click
      int ix, iy;
      SubPlaceItem(i, ix, iy);
      if(mx >= ix - hitHalf && mx <= ix + hitHalf &&
         my >= iy - hitHalf && my <= iy + hitHalf)
         return i;
   }
   return -1;
}

string ToolsBg(const int i)   { return g_UI.btnPrefix + "ToolsBg" + IntegerToString(i); }
string ToolsIcon(const int i) { return g_UI.btnPrefix + "ToolsIcon" + IntegerToString(i); }
string ToolsBadgeBg(const int i) { return g_UI.btnPrefix + "ToolsBadge" + IntegerToString(i); }
string ToolsBadgeTxt(const int i) { return g_UI.btnPrefix + "ToolsBadgeTxt" + IntegerToString(i); }

//--- sub-item SKIN. The sub-menu speaks two visual languages: the fan/rail/ring
//    reuse the ring's circular glass disc (circ_*.bmp, 52px canvas = 44px disc +
//    4px glow), while the grid panel uses the rounded-square tile (cell_*.bmp,
//    46px canvas = 40px tile + 3px glow). A grid of discs reads as scattered
//    debris; a grid of tiles reads as one control block. Size AND margin must
//    follow the skin, or the icon drifts off-centre and the hit tile mis-sizes.
int SubBgSize()
{
   return SubIsPanelMode() ? SUB_CELL_CANVAS : CIRC_BG_SIZE;
}
string SubBgRes(const bool on)
{
   if(SubIsPanelMode()) return on ? "::Files\\Icons\\cell_on.bmp" : "::Files\\Icons\\cell_off.bmp";
   return on ? "::Files\\Icons\\circ_on.bmp" : "::Files\\Icons\\circ_off.bmp";
}
// The panel backdrop BMP for the CURRENT row count + paging state. One BMP per
// height because scaling a rounded panel would distort its corners/border.
string SubPanelRes()
{
   int rows = SubVisibleRows();
   return "::Files\\Icons\\sub_panel_r" + IntegerToString(rows)
          + (SubIsPaged() ? "p" : "") + ".bmp";
}

// Park an item's objects off-screen. Needed because ToolsLayout() refuses to
// clamp a parked item (the clamp would drag it back onto the chart), so a cell
// that WAS on the previous page must be moved here explicitly — otherwise it
// keeps sitting at its old coordinates after a page flip.
void SubParkItem(const int i)
{
   if(ObjectFind(0, ToolsBg(i)) >= 0)
   {
      ObjectSetInteger(0, ToolsBg(i), OBJPROP_XDISTANCE, CIRC_HIDE_POS);
      ObjectSetInteger(0, ToolsBg(i), OBJPROP_YDISTANCE, CIRC_HIDE_POS);
   }
   if(ObjectFind(0, ToolsIcon(i)) >= 0)
   {
      ObjectSetInteger(0, ToolsIcon(i), OBJPROP_XDISTANCE, CIRC_HIDE_POS);
      ObjectSetInteger(0, ToolsIcon(i), OBJPROP_YDISTANCE, CIRC_HIDE_POS);
   }
   ToolsShowBadge(i, false);
}

//+------------------------------------------------------------------+
//| Sub-menu panel chrome (grid modes only).                          |
//|                                                                  |
//| WHY A PANEL AT ALL: a bare grid of tiles floating over candles  |
//| reads as debris — the eye cannot tell the button block from the  |
//| chart. The backdrop is what makes it read as one control.        |
//|                                                                  |
//| The backdrop is a BMP (sub_panel_r<N>[p].bmp) so it keeps the     |
//| rounded corners, the 1px border, the inset top highlight and the  |
//| drop shadow of panel_all_redesign_preview.html's .tgrid — none of |
//| which an OBJ_RECTANGLE_LABEL can express. One BMP per visible row |
//| count because STRETCHING a rounded panel turns its 13px corners   |
//| into ellipses and blurs its border (never scale a skin).          |
//|                                                                  |
//| Every colour lives in a SUB_CLR_* define so one edit restyles the |
//| whole panel (P-UI-09); the BMP is generated from the same palette |
//| in tools/gen-th3-icons.js.                                        |
//| Z-ORDER: backdrop 1004 < accent dot 1005 < cells (ToolsBg 1010 /  |
//| ToolsIcon 1011) < header 1012 < pager 1014 < orb 2000 < panels    |
//| 1500+ < hover tip 1700+. The orb is never covered because         |
//| SubPanelRect() keeps SUB_ORB_GAP clear of it.                     |
//+------------------------------------------------------------------+
#define SUB_CLR_HDR       BIO_CLR_MUTED    // #8C96A6 header text — was a pasted literal (P-UI-69c)
#define SUB_CLR_ACCENT    BIO_CLR_ACCENT   // #FFC247 gold — same
#define SUB_CLR_DOT_OFF   C'58,66,82'      // inactive page dot
// The pager chevrons are OBJ_BUTTONs (the only reliably clickable object) but
// must read as PLAIN TEXT on the panel: bg == the panel body at that height and
// border == bg, so no button chrome is visible (the preview has bare chevrons).
#define SUB_CLR_BTN_BG    C'21,26,35'
#define SUB_CLR_BTN_BD    C'21,26,35'
#define SUB_PAGER_DOTS_MAX 6               // beyond this the pager shows n/N text
#define SUB_DOT_SIZE      5
#define SUB_DOT_GAP       7

string SubPanelBg()   { return g_UI.btnPrefix + "SubPanelBg"; }
string SubPanelDot()  { return g_UI.btnPrefix + "SubPanelDot"; }
string SubPanelHdr()  { return g_UI.btnPrefix + "SubPanelHdr"; }
string SubPanelCnt()  { return g_UI.btnPrefix + "SubPanelCnt"; }
string SubPagerPrev() { return g_UI.btnPrefix + "SubPagerPrev"; }
string SubPagerNext() { return g_UI.btnPrefix + "SubPagerNext"; }
string SubPagerTxt()  { return g_UI.btnPrefix + "SubPagerTxt"; }
string SubPagerDot(const int k) { return g_UI.btnPrefix + "SubPagerDot" + IntegerToString(k); }

void SubChromeDelete()
{
   ObjectDelete(0, SubPanelBg());
   ObjectDelete(0, SubPanelDot());
   ObjectDelete(0, SubPanelHdr());
   ObjectDelete(0, SubPanelCnt());
   ObjectDelete(0, SubPagerPrev());
   ObjectDelete(0, SubPagerNext());
   ObjectDelete(0, SubPagerTxt());
   for(int k = 0; k < SUB_PAGER_DOTS_MAX; k++)
      ObjectDelete(0, SubPagerDot(k));
}

// The panel backdrop: one bitmap label, offset by the BMP's baked shadow margin
// so the BODY (not the shadow canvas) lands on the panel rect.
void SubSetPanel(const int px, const int py, const int pw, const int ph)
{
   string name = SubPanelBg();
   if(ObjectFind(0, name) < 0)
      if(!ObjectCreate(0, name, OBJ_BITMAP_LABEL, 0, 0, 0)) return;
   string res = SubPanelRes();
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, px - SUB_PANEL_MARG);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, py - SUB_PANEL_MARG);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, pw + 2 * SUB_PANEL_MARG);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, ph + 2 * SUB_PANEL_MARG);
   ObjectSetString(0, name, OBJPROP_BMPFILE, 0, res);
   ObjectSetString(0, name, OBJPROP_BMPFILE, 1, res);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_MENU_PANEL);
}


// One flat rectangle label. Change-guarded: re-setting a property forces a
// repaint, so only write what actually differs (P-PERF-01).
void SubSetRect(const string name, const int x, const int y, const int w, const int h,
                const color bg, const bool bordered, const color border, const int z)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, bordered ? BORDER_FLAT : BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bordered ? border : bg);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, z);
}

void SubSetLabel(const string name, const int x, const int y, const string txt,
                 const color clr, const int size, const int z)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, BioChromeFont());
   // `size` is the NOMINAL (design) pt - PnlPt re-expresses it for this display.
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PnlPt(size));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, z);
}

// Single source of truth for the pager strip geometry: SubChromeCreate DRAWs it
// and SubChromeMove translates it, so the two can never drift apart.
//
// P-UI-116: this used to promise a third reader, `SubPagerAt`, that was never
// written — no commit contains it (`git log -S SubPagerAt` is empty), so the
// comment named a hit test no reader could find. The pager needs none of its own:
// the arrows and the dots sit INSIDE the panel plate, the plate is claimed as a
// whole by `CircPointOnMenu` (its one test), and a pager press arrives by object
// name in the click handler below. Geometry stays shared by the two real readers.
void SubPagerGeom(const int px, const int py, const int pw, const int ph,
                  int &by, int &bh, int &bw, int &prevX, int &nextX)
{
   bh = 16;
   bw = 22;
   by    = py + ph - SUB_GRID_PGR + (SUB_GRID_PGR - bh) / 2;
   prevX = px + SUB_GRID_PAD;
   nextX = px + pw - SUB_GRID_PAD - bw;
}

// P-UI-34: the readout captions' own x - MEASURED, never guessed. `5 * StringLen(s)` was
// the estimate at FOUR sites (create + move, counter + pager text); 8pt Arial Bold runs
// ~5.8px/char at 96dpi, so the counter drifted toward the panel edge and the "n/N" pager
// caption sat off-centre - and because create AND move used the same guess, the drift
// survived a drag. One owner for both paths (P-UI-26: update mirrors create).
int SubReadoutX(const int px, const int pw, const string s)
{
   return px + pw - SUB_GRID_PAD - PnlTextW(s, SUB_PT_READOUT);
}
int SubPagerTxtX(const int px, const int pw, const string s)
{
   return px + (pw - PnlTextW(s, SUB_PT_READOUT)) / 2;
}

// ASCII text only: "<" / ">" are inside Windows-1252 so they are safe as font
// text; a chevron glyph (U+2039/U+25BC) renders as "?" in MT4/Wine Arial (P-UI-06).
void SubSetPagerBtn(const string name, const int x, const int y, const int w, const int h,
                    const string txt, const bool enabled)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, BioChromeFont());
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, PnlPt(SUB_PT_PAGER));
   ObjectSetInteger(0, name, OBJPROP_COLOR, enabled ? SUB_CLR_ACCENT : SUB_CLR_DOT_OFF);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, SUB_CLR_BTN_BG);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, SUB_CLR_BTN_BD);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, Z_MENU_PAGER);
}

void SubChromeCreate()
{
   if(!SubIsPanelMode()) { SubChromeDelete(); SubNoteBuilt(); return; }

   int px, py, pw, ph;
   SubPanelRect(px, py, pw, ph);

   SubSetPanel(px, py, pw, ph);
   SubSetRect(SubPanelDot(), px + SUB_GRID_PAD, py + 11, 5, 5,
              SUB_CLR_ACCENT, false, SUB_CLR_ACCENT, Z_MENU_DOT);
   SubSetLabel(SubPanelHdr(), px + SUB_GRID_PAD + 11, py + 8, "TOOLS", SUB_CLR_HDR, 8, Z_MENU_BADGE);

   // right-hand readout: total when the whole grid is visible, "page/total" when paged
   int pages = SubPageCount();
   string cnt = SubIsPaged()
                ? (IntegerToString(g_ToolsPage + 1) + "/" + IntegerToString(pages))
                : IntegerToString(TOOL_COUNT);
   SubSetLabel(SubPanelCnt(), SubReadoutX(px, pw, cnt), py + 8,
               cnt, SUB_CLR_ACCENT, SUB_PT_READOUT, Z_MENU_BADGE);

   if(!SubIsPaged())
   {
      ObjectDelete(0, SubPagerPrev());
      ObjectDelete(0, SubPagerNext());
      ObjectDelete(0, SubPagerTxt());
      for(int k = 0; k < SUB_PAGER_DOTS_MAX; k++) ObjectDelete(0, SubPagerDot(k));
      return;
   }

   int by, bh, bw, prevX, nextX;
   SubPagerGeom(px, py, pw, ph, by, bh, bw, prevX, nextX);
   SubSetPagerBtn(SubPagerPrev(), prevX, by, bw, bh, "<", g_ToolsPage > 0);
   SubSetPagerBtn(SubPagerNext(), nextX, by, bw, bh, ">", g_ToolsPage < pages - 1);

   // Page indicator: one dot per page (gold = current) while they fit, otherwise
   // the "n/N" text — so the strip can never overflow however many tools arrive.
   if(pages <= SUB_PAGER_DOTS_MAX)
   {
      ObjectDelete(0, SubPagerTxt());
      int total = pages * SUB_DOT_SIZE + (pages - 1) * SUB_DOT_GAP;
      int x0 = px + (pw - total) / 2;
      int dy = py + ph - SUB_GRID_PGR + (SUB_GRID_PGR - SUB_DOT_SIZE) / 2;
      for(int k = 0; k < SUB_PAGER_DOTS_MAX; k++)
      {
         if(k >= pages) { ObjectDelete(0, SubPagerDot(k)); continue; }
         bool on = (k == g_ToolsPage);
         color dc = on ? SUB_CLR_ACCENT : SUB_CLR_DOT_OFF;
         SubSetRect(SubPagerDot(k), x0 + k * (SUB_DOT_SIZE + SUB_DOT_GAP), dy,
                    SUB_DOT_SIZE, SUB_DOT_SIZE, dc, false, dc, Z_MENU_PAGER);
      }
   }
   else
   {
      for(int k = 0; k < SUB_PAGER_DOTS_MAX; k++) ObjectDelete(0, SubPagerDot(k));
      string pt = IntegerToString(g_ToolsPage + 1) + "/" + IntegerToString(pages);
      SubSetLabel(SubPagerTxt(), SubPagerTxtX(px, pw, pt),
                  py + ph - SUB_GRID_PGR + 8, pt, SUB_CLR_HDR, SUB_PT_READOUT, Z_MENU_BADGE);
   }
   SubNoteBuilt();   // remember the shape this chrome was built for (SubRelayoutIfNeeded)
}

// Drag path: TRANSLATE the chrome without re-setting every property. A full
// SubChromeCreate per drag frame would re-decode the panel bitmap every 30ms
// (P-PERF-01). Safe because the mode is frozen while the orb is dragged, so the
// visible row count — and therefore the panel BMP — cannot change mid-drag.
void SubChromeMove()
{
   if(!SubIsPanelMode()) return;
   if(ObjectFind(0, SubPanelBg()) < 0) { SubChromeCreate(); return; }   // not built yet

   int px, py, pw, ph;
   SubPanelRect(px, py, pw, ph);

   ObjectSetInteger(0, SubPanelBg(), OBJPROP_XDISTANCE, px - SUB_PANEL_MARG);
   ObjectSetInteger(0, SubPanelBg(), OBJPROP_YDISTANCE, py - SUB_PANEL_MARG);
   ObjectSetInteger(0, SubPanelDot(), OBJPROP_XDISTANCE, px + SUB_GRID_PAD);
   ObjectSetInteger(0, SubPanelDot(), OBJPROP_YDISTANCE, py + 11);
   ObjectSetInteger(0, SubPanelHdr(), OBJPROP_XDISTANCE, px + SUB_GRID_PAD + 11);
   ObjectSetInteger(0, SubPanelHdr(), OBJPROP_YDISTANCE, py + 8);

   int pages = SubPageCount();
   if(ObjectFind(0, SubPanelCnt()) >= 0)
   {
      string cnt = SubIsPaged()
                   ? (IntegerToString(g_ToolsPage + 1) + "/" + IntegerToString(pages))
                   : IntegerToString(TOOL_COUNT);
      ObjectSetInteger(0, SubPanelCnt(), OBJPROP_XDISTANCE, SubReadoutX(px, pw, cnt));
      ObjectSetInteger(0, SubPanelCnt(), OBJPROP_YDISTANCE, py + 8);
   }
   if(!SubIsPaged()) return;

   int by, bh, bw, prevX, nextX;
   SubPagerGeom(px, py, pw, ph, by, bh, bw, prevX, nextX);
   if(ObjectFind(0, SubPagerPrev()) >= 0)
   {
      ObjectSetInteger(0, SubPagerPrev(), OBJPROP_XDISTANCE, prevX);
      ObjectSetInteger(0, SubPagerPrev(), OBJPROP_YDISTANCE, by);
   }
   if(ObjectFind(0, SubPagerNext()) >= 0)
   {
      ObjectSetInteger(0, SubPagerNext(), OBJPROP_XDISTANCE, nextX);
      ObjectSetInteger(0, SubPagerNext(), OBJPROP_YDISTANCE, by);
   }
   if(pages <= SUB_PAGER_DOTS_MAX)
   {
      int total = pages * SUB_DOT_SIZE + (pages - 1) * SUB_DOT_GAP;
      int x0 = px + (pw - total) / 2;
      int dy = py + ph - SUB_GRID_PGR + (SUB_GRID_PGR - SUB_DOT_SIZE) / 2;
      for(int k = 0; k < pages; k++)
      {
         if(ObjectFind(0, SubPagerDot(k)) < 0) continue;
         ObjectSetInteger(0, SubPagerDot(k), OBJPROP_XDISTANCE, x0 + k * (SUB_DOT_SIZE + SUB_DOT_GAP));
         ObjectSetInteger(0, SubPagerDot(k), OBJPROP_YDISTANCE, dy);
      }
   }
   else if(ObjectFind(0, SubPagerTxt()) >= 0)
   {
      string pt = IntegerToString(g_ToolsPage + 1) + "/" + IntegerToString(pages);
      ObjectSetInteger(0, SubPagerTxt(), OBJPROP_XDISTANCE, SubPagerTxtX(px, pw, pt));
      ObjectSetInteger(0, SubPagerTxt(), OBJPROP_YDISTANCE, py + ph - SUB_GRID_PGR + 8);
   }
}

// The pager chevrons are real OBJ_BUTTONs, so the click router reaches them
// through CHARTEVENT_OBJECT_CLICK by name — no pixel hit-test is needed here.
// SubPagerGeom() is still the single source of their geometry (SubChromeCreate
// draws them, SubChromeMove translates them), so the two can never drift apart.



// Badge anchor for a Tools item: pushed outward from the menu center
void ToolsBadgePos(const int i, int &x, int &y)
{
   int cx, cy;
   ToolsLayout(i, cx, cy);
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1920;
   if(ch <= 0) ch = 1080;
   double dx = cx - g_UI.menuX;
   double dy = cy - g_UI.menuY;
   if(g_UI.menuX <= CIRC_EDGE_TRIGGER)      { dx = 1;  dy = 0;  }
   else if(g_UI.menuX >= cw - CIRC_EDGE_TRIGGER) { dx = -1; dy = 0;  }
   else if(g_UI.menuY <= CIRC_EDGE_TRIGGER) { dx = 0;  dy = 1;  }
   else if(g_UI.menuY >= ch - CIRC_EDGE_TRIGGER) { dx = 0;  dy = -1; }
   else
   {
      double len = MathSqrt(dx * dx + dy * dy);
      if(len > 0.1) { dx /= len; dy /= len; } else { dx = 0; dy = 1; }
   }
   double off = CIRC_BTN_SIZE / 2 + CIRC_BADGE_FLOAT;
   x = (int)MathRound(cx + dx * off - CIRC_BADGE_SIZE / 2.0);
   y = (int)MathRound(cy + dy * off - CIRC_BADGE_SIZE / 2.0);
}

#endif // BIOTAK_MENU_B_MQH
