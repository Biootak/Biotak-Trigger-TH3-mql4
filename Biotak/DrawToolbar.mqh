  //+------------------------------------------------------------------+
//|                                              DrawToolbar.mqh      |
//|   P-DRAW-01 (2026-09-22) — THE USER'S OWN DRAWINGS, ONE OWNER.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Biotak Project"
#property strict

#ifndef DRAW_TOOLBAR_MQH
#define DRAW_TOOLBAR_MQH

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-01 — A MINI TOOLBAR FOR EVERY DRAWING THE USER MAKES (fibos, trendlines,
// horizontals, rays, lines, boxes) — explicitly NOT for the indicator's own objects,
// which already have their own toolbars.
// WHY THIS SHAPE. MT4 gives every drawing tool its own type and a property surface
// that is only MOSTLY common, so a per-type toolbar would be thirty copies of the same
// five controls. The whole feature is ONE classifier plus ONE table: `DrawKindOf`
// answers an EDrawKind, `DrawKindCaps` is the bitmask of slots that kind carries (a
// slot the kind lacks is not drawn, never greyed), and `DrawSlotRead/Write` is one pair
// per slot — so adding a drawing tool is one row in two switches, never a new control.
// THE HIT TEST IS MEASURED IN PIXELS: every anchor is projected with
// `ChartTimePriceToXY` and the cursor compared against the object's DRAWN shape within
// one px (MT4 itself has no "object under the cursor" call), with the terminal's own
// selection as a second opinion (`DrawSelectedObjectAt`).
// THE STYLE MEMORY IS THE "LAST CHANGE SAVED": every edit goes onto the object AND
// into that KIND's memory, and a freshly drawn object of the kind is given it on
// create (`DrawStyleApplyOnCreate`), per drawing TOOL, not globally.
// ══════════════════════════════════════════════════════════════════════════

//--- THE KINDS. One per drawing BEHAVIOUR the toolbar must speak, not one per
//--- MT4 type: a fan and a plain fibo share their level machinery, so they share
//--- the kind and differ in geometry only.
enum EDrawKind
{
   DK_NONE = 0,     // not a drawing of ours (the indicator's own, a panel, …)
   DK_LINE,         // OBJ_TREND (MT4 has no OBJ_ARROWED_LINE — the arrowed line IS a trend)
   DK_HLINE,        // OBJ_HLINE
   DK_VLINE,        // OBJ_VLINE
   DK_CHANNEL,      // OBJ_CHANNEL / OBJ_STDDEVCHANNEL / OBJ_REGRESSION
   DK_FIBO,         // OBJ_FIBO / OBJ_FIBOTIMES (horizontal level lines)
   DK_FIBOFAN,      // OBJ_FIBOFAN / OBJ_FIBOARC (levels slanted from the first anchor)
   DK_FIBOCHAN,     // OBJ_FIBOCHANNEL
   DK_EXPANSION,    // OBJ_EXPANSION
   DK_GANN,         // OBJ_GANNLINE / OBJ_GANNFAN / OBJ_GANNGRID
   DK_PITCHFORK,    // OBJ_PITCHFORK
   DK_RECT,         // OBJ_RECTANGLE
   DK_TRIANGLE,     // OBJ_TRIANGLE
   DK_ELLIPSE,      // OBJ_ELLIPSE
   DK_ARROW,        // OBJ_ARROW (one anchor, a glyph)
   DK_TEXT,         // OBJ_TEXT (one anchor, a caption)
   DK_COUNT
};

//--- THE SLOTS the strip can show, in the order it shows them. The index is the
//--- contract between this module and the strip; a kind simply does not carry
//--- the ones it has no meaning for.
#define DRAW_SLOT_COLOR   0   // the object's colour (a fibo: the level family's)
#define DRAW_SLOT_WIDTH   1   // 1..5 px
#define DRAW_SLOT_STYLE   2   // solid / dash / dot / …
#define DRAW_SLOT_FILL    3   // rectangle, triangle, ellipse, fibo channel
#define DRAW_SLOT_RAY     4   // a line's own RAY_RIGHT / RAY_LEFT
#define DRAW_SLOT_LOCK    5   // SELECTABLE = false: it cannot be grabbed or moved
#define DRAW_SLOT_MORE    6   // the terminal's own properties (a hint, see the strip)
//--- P-DRAW-09a (2026-09-23) — THE PROPERTIES MT4 ONLY REACHES THROUGH ITS
//--- 9-CHECKBOX DIALOG. User order: «هر چیزی که متاتریدر پشتیبانی نمیکنه [رو
//--- پوشش بده] … ولی پر امکانات باشه». Three controls MT4 HAS and buries, each
//--- one property write and each one tap here — APPENDED, so no existing slot
//--- index moved (the strip speaks these numbers).
//---   * FONT  — OBJ_TEXT's caption size: MT4's own properties dialog, one
//---             object at a time, and the size the user keeps re-setting by hand;
//---   * GLYPH — OBJ_ARROW's Wingdings code: MT4 makes the user hunt a code
//---             number; here the mark is a cycle with the number always shown;
//---   * BACK  — "draw as background": the Common tab's checkbox, which is where
//---             a trader's zones belong and is otherwise four clicks deep.
#define DRAW_SLOT_FONT    7
#define DRAW_SLOT_GLYPH   8
#define DRAW_SLOT_BACK    9
#define DRAW_SLOT_N      10

//--- THE CAPABILITIES, one bit per slot. A kind's mask IS its toolbar.
#define DRAW_CAP_COLOR   (1 << DRAW_SLOT_COLOR)
#define DRAW_CAP_WIDTH   (1 << DRAW_SLOT_WIDTH)
#define DRAW_CAP_STYLE   (1 << DRAW_SLOT_STYLE)
#define DRAW_CAP_FILL    (1 << DRAW_SLOT_FILL)
#define DRAW_CAP_RAY     (1 << DRAW_SLOT_RAY)
#define DRAW_CAP_LOCK    (1 << DRAW_SLOT_LOCK)
#define DRAW_CAP_MORE    (1 << DRAW_SLOT_MORE)
#define DRAW_CAP_FONT    (1 << DRAW_SLOT_FONT)
#define DRAW_CAP_GLYPH   (1 << DRAW_SLOT_GLYPH)
#define DRAW_CAP_BACK    (1 << DRAW_SLOT_BACK)
//--- every drawing tool the user has: the four common controls + the two that
//--- every MT4 object really carries (LOCK, BACK) + the terminal's own dialog
//--- hint. Kinds add FILL / RAY / FONT / GLYPH on top (see the table).
#define DRAW_CAP_COMMON  (DRAW_CAP_COLOR | DRAW_CAP_WIDTH | DRAW_CAP_STYLE | DRAW_CAP_LOCK | DRAW_CAP_BACK | DRAW_CAP_MORE)

//--- the pick tolerance, in PIXELS: the same "a few pixels around what is
//--- drawn" the terminal itself uses (the custom price line's own lesson,
//--- P-UI-49c: a hit test expressed in price drifts with the zoom).
#define DRAW_HIT_PX      6
#define DRAW_SELECTED_HANDLE_PX 8
//--- the style memory's bounds, mirrored from the panel's own rows.
#define DRAW_WIDTH_MIN   1
#define DRAW_WIDTH_MAX   5
//--- P-DRAW-09a: the two bounded properties the new slots cycle. FONT is the
//--- caption's own point size (MT4 draws OBJ_TEXT at it unchanged), GLYPH the
//--- Wingdings code of a mark.
#define DRAW_FONT_MIN    6
#define DRAW_FONT_MAX   30
#define DRAW_FONT_DEF   10
#define DRAW_GLYPH_MIN   0
#define DRAW_GLYPH_MAX 255

// ══════════════════════════════════════════════════════════════════════════
// IS THIS OBJECT OURS? The indicator's own drawings (levels, zones, the ABCD
// pattern and its harmonics, the BaseKnot boxes, the panels, the leg meter)
// all carry `inpObjectPrefix`; the user's own drawings never do. ONE test,
// asked by every entry point of this module — the user's order was explicit
// that the harmonics and the rest of the indicator's objects are NOT in scope.
// ══════════════════════════════════════════════════════════════════════════
bool DrawIsIndicatorObject(const string name)
{
   if(name == "") return true;                      // no name, no drawing
   int p = StringLen(inpObjectPrefix);
   if(p <= 0) return false;                         // an empty prefix matches nothing
   if(StringLen(name) < p) return false;
   return (StringSubstr(name, 0, p) == inpObjectPrefix);
}

//--- the object's MT4 type, or -1 when it is not on the chart.
int DrawObjectType(const string name)
{
   if(name == "") return -1;
   if(ObjectFind(0, name) < 0) return -1;
   return (int)ObjectGetInteger(0, name, OBJPROP_TYPE);
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-21 — THE BOX'S OWN CHILDREN. A box 50% line is a helper the terminal
// cannot draw (OBJ_RECTANGLE has no mid line), so it lives as a separate
// OBJ_TREND named `<box>_BX50`. It is nobody's drawing: the classifier below
// answers DK_NONE for it, so the strip never serves it, the hit test never
// lands on it, and no preset/style memory learns from it. One suffix, one
// test, asked by every entry point that meets an object name.
// ══════════════════════════════════════════════════════════════════════════
#define BOXCHILD_SUFFIX "_BX50"
bool BoxIsMidChild(const string name)
{
   int n = StringLen(name), s = StringLen(BOXCHILD_SUFFIX);
   if(n <= s) return false;
   return (StringSubstr(name, n - s, s) == BOXCHILD_SUFFIX);
}
string BoxMidName(const string box) { return box + BOXCHILD_SUFFIX; }
string BoxMidParent(const string child)
{
   if(!BoxIsMidChild(child)) return "";
   return StringSubstr(child, 0, StringLen(child) - StringLen(BOXCHILD_SUFFIX));
}

// ══════════════════════════════════════════════════════════════════════════
// THE CLASSIFIER. MT4's type answers the kind, with ONE refinement: a trend
// line that carries a ray is a different ANIMAL on the chart (it runs to the
// edge and back), so the kind is decided by the flags, not by the type alone —
// that is also what makes the RAY slot meaningful for those objects only.
// ══════════════════════════════════════════════════════════════════════════
EDrawKind DrawKindOf(const string name)
{
   if(BoxIsMidChild(name)) return DK_NONE;   // P-DRAW-21: a box helper is served never
   int t = DrawObjectType(name);
   if(t < 0) return DK_NONE;
   switch(t)
   {
      case OBJ_TREND:          return DK_LINE;
      case OBJ_HLINE:          return DK_HLINE;
      case OBJ_VLINE:          return DK_VLINE;
      case OBJ_CHANNEL:
      case OBJ_STDDEVCHANNEL:
      case OBJ_REGRESSION:     return DK_CHANNEL;
      case OBJ_FIBO:
      case OBJ_FIBOTIMES:      return DK_FIBO;
      case OBJ_FIBOFAN:
      case OBJ_FIBOARC:        return DK_FIBOFAN;
      case OBJ_FIBOCHANNEL:    return DK_FIBOCHAN;
      case OBJ_EXPANSION:      return DK_EXPANSION;
      case OBJ_GANNLINE:
      case OBJ_GANNFAN:
      case OBJ_GANNGRID:       return DK_GANN;
      case OBJ_PITCHFORK:      return DK_PITCHFORK;
      case OBJ_RECTANGLE:      return DK_RECT;
      case OBJ_TRIANGLE:       return DK_TRIANGLE;
      case OBJ_ELLIPSE:        return DK_ELLIPSE;
      case OBJ_ARROW:          return DK_ARROW;
      case OBJ_TEXT:           return DK_TEXT;
      default:                 return DK_NONE;
   }
}

// THE TABLE. A kind's mask is its whole toolbar — the strip reads nothing else.
int DrawKindCaps(const EDrawKind k)
{
   switch(k)
   {
      case DK_LINE:      return DRAW_CAP_COMMON | DRAW_CAP_RAY;
      case DK_HLINE:
      case DK_VLINE:     return DRAW_CAP_COMMON;
      case DK_CHANNEL:   return DRAW_CAP_COMMON | DRAW_CAP_FILL;
      case DK_FIBO:
      case DK_FIBOFAN:   return DRAW_CAP_COMMON;          // the levels' own look, one control
      case DK_FIBOCHAN:  return DRAW_CAP_COMMON | DRAW_CAP_FILL;
      case DK_EXPANSION: return DRAW_CAP_COMMON;
      case DK_GANN:      return DRAW_CAP_COMMON;
      case DK_PITCHFORK: return DRAW_CAP_COMMON;
      case DK_RECT:
      case DK_TRIANGLE:
      case DK_ELLIPSE:   return DRAW_CAP_COMMON | DRAW_CAP_FILL;
      // P-DRAW-09a: the two kinds whose OWN dialogs are the worst of the family —
      // a text's size and an arrow's code number — get their control in the strip.
      case DK_ARROW:     return DRAW_CAP_COMMON | DRAW_CAP_GLYPH;
      case DK_TEXT:      return DRAW_CAP_COMMON | DRAW_CAP_FONT;
      default:           return 0;
   }
}

bool DrawSlotAvailable(const EDrawKind k, const int slot)
{
   if(slot < 0 || slot >= DRAW_SLOT_N) return false;
   return ((DrawKindCaps(k) & (1 << slot)) != 0);
}

//--- the level family: every kind whose look lives on per-LEVEL colours.
bool DrawKindHasLevels(const EDrawKind k)
{
   return (k == DK_FIBO || k == DK_FIBOFAN || k == DK_FIBOCHAN ||
           k == DK_EXPANSION || k == DK_GANN || k == DK_PITCHFORK);
}

// ══════════════════════════════════════════════════════════════════════════
// THE HIT TEST, IN PIXELS.
//
// Every anchor is projected with `ChartTimePriceToXY` (the conversion this
// codebase already proved works — P-UI-50) and the cursor is compared against
// the object's DRAWN shape. The shapes are the ones a trader actually aims at:
//   * a horizontal line   → its row,
//   * a vertical line     → its column,
//   * a segment           → the distance to the segment, extended by the ray
//                           flags (a ray has no far end, so the projection is
//                           clamped on the side that exists),
//   * a rectangle family  → its border (and its inside when FILL is on, because
//                           then the inside IS drawn),
//   * the fibo family     → every LEVEL line the object draws,
//   * an arrow or a text  → a small box around its one anchor.
// ══════════════════════════════════════════════════════════════════════════
bool DrawAnchorXY(const string name, const int idx, int &x, int &y)
{
   datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, idx);
   double   p = ObjectGetDouble(0, name, OBJPROP_PRICE, idx);
   if(t <= 0 || !(p > 0.0)) return false;
   if(!ChartTimePriceToXY(0, 0, t, p, x, y)) return false;
   return true;
}

//--- the distance from (px,py) to the segment (x1,y1)-(x2,y2), with the ends
//--- CLAMPED or OPEN per the ray flags. `openA` = the first end runs on for
//--- ever (RAY_LEFT), `openB` = the second (RAY_RIGHT).
double DrawSegDist(const int px, const int py,
                   const int x1, const int y1, const int x2, const int y2,
                   const bool openA, const bool openB)
{
   double dx = (double)(x2 - x1), dy = (double)(y2 - y1);
   double len2 = dx * dx + dy * dy;
   if(len2 <= 0.0) return MathSqrt((double)((px - x1) * (px - x1) + (py - y1) * (py - y1)));
   double u = ((double)(px - x1) * dx + (double)(py - y1) * dy) / len2;
   if(!openA && u < 0.0) u = 0.0;          // the first end stops here
   if(!openB && u > 1.0) u = 1.0;          // the second end stops here
   double cx = x1 + u * dx, cy = y1 + u * dy;
   return MathSqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

//--- the level prices of a level family, straight off the object: level k is
//--- drawn at `p1 + (p2 - p1) * value_k`. Counted through OBJPROP_LEVELS so a
//--- fibo with a trimmed level set is measured as it is DRAWN.
int DrawLevelCount(const string name)
{
   int n = (int)ObjectGetInteger(0, name, OBJPROP_LEVELS);
   if(n < 0) n = 0;
   if(n > 64) n = 64;
   return n;
}
double DrawLevelValue(const string name, const int k)
{
   return ObjectGetDouble(0, name, OBJPROP_LEVELVALUE, k);
}

//--- THE LEVEL FAMILY'S LOOK IS PER LEVEL in MT4: each level carries its own
//--- colour, style and width, so "the whole family" is a LOOP, never one call —
//--- and a level the loop skips is a line the user sees unchanged.
void DrawLevelsSetColor(const string name, const color c)
{
   int n = DrawLevelCount(name);
   for(int k = 0; k < n; k++) ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, k, c);
}
void DrawLevelsSetWidth(const string name, const int w)
{
   int n = DrawLevelCount(name);
   for(int k = 0; k < n; k++) ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, k, w);
}
void DrawLevelsSetStyle(const string name, const int st)
{
   int n = DrawLevelCount(name);
   for(int k = 0; k < n; k++) ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, k, st);
}

bool DrawHitLevels(const string name, const int px, const int py)
{
   int n = DrawLevelCount(name);
   if(n <= 0) return false;
   datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
   double   p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   double   p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
   if(t1 <= 0 || !(p1 > 0.0) || !(p2 > 0.0)) return false;
   // the level lines of a plain fibo run from t1 to t2 at their own price; the
   // fan's run from the FIRST anchor's time to the second's, so the x span is
   // the same pair for both and only the y differs — measured from the object.
   int xa = 0, ya = 0, xb = 0, yb = 0;
   for(int k = 0; k < n; k++)
   {
      double v = DrawLevelValue(name, k);
      if(!MathIsValidNumber(v)) continue;
      double lv = p1 + (p2 - p1) * v;
      if(!(lv > 0.0)) continue;
      if(!ChartTimePriceToXY(0, 0, t1, lv, xa, ya)) continue;
      if(!ChartTimePriceToXY(0, 0, t2, lv, xb, yb)) continue;
      if(DrawSegDist(px, py, xa, ya, xb, yb, false, false) <= (double)DRAW_HIT_PX)
         return true;
   }
   return false;
}

bool DrawHitObject(const string name, const int px, const int py)
{
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE) return false;
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   int tol = DRAW_HIT_PX;

   switch(k)
   {
      case DK_HLINE:
      {
         if(!DrawAnchorXY(name, 0, x1, y1)) return false;
         return (MathAbs(py - y1) <= tol);
      }
      case DK_VLINE:
      {
         if(!DrawAnchorXY(name, 0, x1, y1)) return false;
         return (MathAbs(px - x1) <= tol);
      }
      case DK_ARROW:
      case DK_TEXT:
      {
         if(!DrawAnchorXY(name, 0, x1, y1)) return false;
         // the glyph's own box: 10 px around the anchor reads as "on it"
         return (MathAbs(px - x1) <= 10 && MathAbs(py - y1) <= 10);
      }
      case DK_LINE:
      {
         if(!DrawAnchorXY(name, 0, x1, y1)) return false;
         if(!DrawAnchorXY(name, 1, x2, y2)) return false;
         bool oA = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_LEFT) != 0);
         bool oB = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != 0);
         return (DrawSegDist(px, py, x1, y1, x2, y2, oA, oB) <= (double)tol);
      }
      case DK_CHANNEL:
      case DK_FIBOCHAN:
      case DK_GANN:
      case DK_PITCHFORK:
      {
         // the multi-line families: the FIRST two anchors name the span, and the
         // rails are the LEVELS (channels, fibo channels, gann fans, pitchforks
         // all draw them that way). Both are measured, so such an object is
         // grabbed by any line it draws — the way it is drawn.
         if(DrawAnchorXY(name, 0, x1, y1) && DrawAnchorXY(name, 1, x2, y2) &&
            DrawSegDist(px, py, x1, y1, x2, y2, false, false) <= (double)tol)
            return true;
         return DrawHitLevels(name, px, py);
      }
      case DK_RECT:
      case DK_TRIANGLE:
      case DK_ELLIPSE:
      {
         if(!DrawAnchorXY(name, 0, x1, y1)) return false;
         if(!DrawAnchorXY(name, 1, x2, y2)) return false;
         int xa = MathMin(x1, x2), xb = MathMax(x1, x2);
         int ya = MathMin(y1, y2), yb = MathMax(y1, y2);
         bool filled = ((int)ObjectGetInteger(0, name, OBJPROP_FILL) != 0);
         if(filled && px >= xa - tol && px <= xb + tol && py >= ya - tol && py <= yb + tol)
            return true;
         // P-DRAW-08g (the user's own report): A BOX IS HELD FROM THE INSIDE.
         // The border-only test below is MT4's own pick, and it is why «نگه میدارم
         // چیزی بالا نمیاد» — a hollow rectangle, triangle or ellipse is grabbed
         // in the middle by every trader alive, and the hold found nothing there.
         // The inside is therefore part of the shape this module serves, and the
         // border test stays for the drawing that is only an outline on screen
         // (the fill flag decides which is honest).
         if(px >= xa && px <= xb && py >= ya && py <= yb) return true;
         // the BORDER: the four edges, each a segment
         if(DrawSegDist(px, py, xa, ya, xb, ya, false, false) <= (double)tol) return true;
         if(DrawSegDist(px, py, xb, ya, xb, yb, false, false) <= (double)tol) return true;
         if(DrawSegDist(px, py, xb, yb, xa, yb, false, false) <= (double)tol) return true;
         if(DrawSegDist(px, py, xa, yb, xa, ya, false, false) <= (double)tol) return true;
         return false;
      }
      case DK_FIBO:
      case DK_FIBOFAN:
      case DK_EXPANSION:
         return DrawHitLevels(name, px, py);
      default:
         return false;
   }
}

//--- P-UI-113h (2026-09-24): THE TERMINAL'S SELECTED HANDLES BELONG TO THE DRAWING.
//--- MT4 paints a rectangle/ellipse with nine controls when selected - four corners,
//--- four side midpoints and the centre - while OBJPROP_TIME/PRICE expose only the
//--- two diagonal construction anchors. Testing only 0..1 therefore recognises two
//--- of the visible controls and misses the very points the hand is on. The
//--- multi-point families have a third construction anchor; one-point families do
//--- not. This is a click-TARGET fact, never a drag: it is read only after
//--- DrawHitObject says the cursor is not already on the drawn shape.
bool DrawHitSelectedHandle(const string name, const int px, const int py)
{
   EDrawKind k = DrawKindOf(name);
   if(k == DK_RECT || k == DK_ELLIPSE)
   {
      int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
      if(!DrawAnchorXY(name, 0, x1, y1) || !DrawAnchorXY(name, 1, x2, y2)) return false;
      int xa = MathMin(x1, x2), xb = MathMax(x1, x2);
      int ya = MathMin(y1, y2), yb = MathMax(y1, y2);
      int mx = (xa + xb) / 2, my = (ya + yb) / 2;
      int hx[9], hy[9];
      hx[0] = xa;  hy[0] = ya;   // corners
      hx[1] = xb;  hy[1] = ya;
      hx[2] = xb;  hy[2] = yb;
      hx[3] = xa;  hy[3] = yb;
      hx[4] = mx;  hy[4] = ya;   // side midpoints
      hx[5] = mx;  hy[5] = yb;
      hx[6] = xa;  hy[6] = my;
      hx[7] = xb;  hy[7] = my;
      hx[8] = mx;  hy[8] = my;   // centre control
      for(int i = 0; i < 9; i++)
         if(MathAbs(px - hx[i]) <= DRAW_SELECTED_HANDLE_PX &&
            MathAbs(py - hy[i]) <= DRAW_SELECTED_HANDLE_PX) return true;
      return false;
   }

   int count = 3;   // channel / pitchfork and the other three-anchor families
   if(k == DK_HLINE || k == DK_VLINE || k == DK_ARROW || k == DK_TEXT) count = 1;
   for(int i = 0; i < count; i++)
   {
      int x = 0, y = 0;
      if(!DrawAnchorXY(name, i, x, y)) continue;
      if(MathAbs(px - x) <= DRAW_SELECTED_HANDLE_PX &&
         MathAbs(py - y) <= DRAW_SELECTED_HANDLE_PX) return true;
   }
   return false;
}

// ══════════════════════════════════════════════════════════════════════════
// THE TWO ANSWERS TO "WHICH DRAWING IS UNDER THE CURSOR?".
//
// `DrawSelectedObjectAt` is the terminal's OWN answer: MT4 selects the object
// it grabs on the press. It is asked first, but only after the cursor is proven
// to be on that selected object's drawn shape or one of its visible controls -
// selection alone is not a cursor hit.
//
// `DrawObjectAt` is the measured answer, for the builds and the moments the
// terminal's selection does not arrive (P-UI-49c's own lesson: the pick-up is
// not something to depend on alone). It walks the chart from the NEWEST object
// backwards — the last created is the one on top of the pile in practice — and
// returns the first shape the cursor is really on.
//
// Both refuse the indicator's own objects: the harmonics, the levels, the
// boxes and the panels have their own owners (the user's order).
// ══════════════════════════════════════════════════════════════════════════
string DrawSelectedObjectAt(const int px, const int py)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || DrawIsIndicatorObject(nm)) continue;
      if(DrawKindOf(nm) == DK_NONE) continue;
      if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTED)) continue;
      if(DrawHitObject(nm, px, py) || DrawHitSelectedHandle(nm, px, py)) return nm;
   }
   return "";
}

string DrawObjectAt(const int px, const int py)
{
   string sel = DrawSelectedObjectAt(px, py);
   if(sel != "") return sel;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || DrawIsIndicatorObject(nm)) continue;
      if(DrawKindOf(nm) == DK_NONE) continue;
      if(DrawHitObject(nm, px, py)) return nm;
   }
   return "";
}

// ══════════════════════════════════════════════════════════════════════════
// THE STYLE MEMORY — «آخرین تغییرات ذخیره بشه».
//
// ONE memory per KIND (not per object, not globally): the second fibo must look
// like the first one the user styled, and a fibo must not inherit a rectangle's
// fill. Five numbers cover every kind — colour, width, style, fill, ray — and
// `s_dkValid[k]` is what tells "the user has styled this kind once" from "this
// is still the factory look", so a kind the user never touched is left exactly
// as the terminal would have drawn it.
// ══════════════════════════════════════════════════════════════════════════
static bool  s_dkValid[DK_COUNT];
static color s_dkColor[DK_COUNT];
static int   s_dkWidth[DK_COUNT];
static int   s_dkStyle[DK_COUNT];
static bool  s_dkFill[DK_COUNT];
static int   s_dkRay[DK_COUNT];      // 0 none · 1 right · 2 left · 3 both
//--- P-DRAW-09a: the three new slots are LOOKS like the five above, so they are
//--- learned the same way — a caption size and a mark the user chose are theirs
//--- for the next one too, not a per-object whim.
static int   s_dkFont[DK_COUNT];     // OBJ_TEXT caption size (points)
static int   s_dkGlyph[DK_COUNT];    // OBJ_ARROW Wingdings code
static bool  s_dkBack[DK_COUNT];     // draw as background

void DrawStyleInit()
{
   for(int k = 0; k < DK_COUNT; k++)
   {
      s_dkValid[k] = false;
      s_dkColor[k] = clrNONE;
      s_dkWidth[k] = 1;
      s_dkStyle[k] = (int)STYLE_SOLID;
      s_dkFill[k]  = false;
      s_dkRay[k]   = 0;
      s_dkFont[k]  = DRAW_FONT_DEF;
      s_dkGlyph[k] = 0;
      s_dkBack[k]  = false;
   }
}

//--- read ONE slot off an object. `slot` is the strip's own index.
double DrawSlotRead(const string name, const int slot)
{
   if(name == "" || ObjectFind(0, name) < 0) return 0.0;
   EDrawKind k = DrawKindOf(name);
   bool lvl = (DrawKindHasLevels(k) && DrawLevelCount(name) > 0);
   switch(slot)
   {
      case DRAW_SLOT_COLOR:
         if(lvl) return (double)(int)ObjectGetInteger(0, name, OBJPROP_LEVELCOLOR, 0);
         return (double)(int)ObjectGetInteger(0, name, OBJPROP_COLOR);
      case DRAW_SLOT_WIDTH:
         if(lvl) return (double)(int)ObjectGetInteger(0, name, OBJPROP_LEVELWIDTH, 0);
         return (double)(int)ObjectGetInteger(0, name, OBJPROP_WIDTH);
      case DRAW_SLOT_STYLE:
         if(lvl) return (double)(int)ObjectGetInteger(0, name, OBJPROP_LEVELSTYLE, 0);
         return (double)(int)ObjectGetInteger(0, name, OBJPROP_STYLE);
      case DRAW_SLOT_FILL:  return ((int)ObjectGetInteger(0, name, OBJPROP_FILL) != 0) ? 1.0 : 0.0;
      case DRAW_SLOT_RAY:
      {
         int r = 0;
         if((int)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != 0) r |= 1;
         if((int)ObjectGetInteger(0, name, OBJPROP_RAY_LEFT) != 0)  r |= 2;
         return (double)r;
      }
      case DRAW_SLOT_LOCK:
         return ((bool)ObjectGetInteger(0, name, OBJPROP_SELECTABLE)) ? 0.0 : 1.0;
      //--- P-DRAW-09a: the three appended slots, read straight off the object.
      case DRAW_SLOT_FONT:
      {
         int fs = (int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE);
         if(fs < DRAW_FONT_MIN || fs > DRAW_FONT_MAX) fs = DRAW_FONT_DEF;
         return (double)fs;
      }
      case DRAW_SLOT_GLYPH: return (double)(int)ObjectGetInteger(0, name, OBJPROP_ARROWCODE);
      case DRAW_SLOT_BACK:  return ((int)ObjectGetInteger(0, name, OBJPROP_BACK) != 0) ? 1.0 : 0.0;
      default: return 0.0;
   }
}

//--- write ONE slot onto an object, and LEARN it into the kind's memory. The
//--- two halves are one call on purpose: an edit the user made is an edit the
//--- next drawing of that kind must wear, and splitting them would let one of
//--- the two drift.
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
         ObjectSetInteger(0, name, OBJPROP_COLOR, c);
         if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, c);
         s_dkColor[k] = c;
         break;
      }
      case DRAW_SLOT_WIDTH:
      {
         int w = (int)MathRound(v);
         if(w < DRAW_WIDTH_MIN) w = DRAW_WIDTH_MIN;
         if(w > DRAW_WIDTH_MAX) w = DRAW_WIDTH_MAX;
         ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
         if(DrawKindHasLevels(k)) DrawLevelsSetWidth(name, w);
         s_dkWidth[k] = w;
         break;
      }
      case DRAW_SLOT_STYLE:
      {
         int st = (int)MathRound(v);
         if(st < 0) st = 0;
         if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
         ObjectSetInteger(0, name, OBJPROP_STYLE, st);
         if(DrawKindHasLevels(k)) DrawLevelsSetStyle(name, st);
         s_dkStyle[k] = st;
         break;
      }
      case DRAW_SLOT_FILL:
      {
         bool f = (v > 0.5);
         ObjectSetInteger(0, name, OBJPROP_FILL, f);
         s_dkFill[k] = f;
         break;
      }
      case DRAW_SLOT_RAY:
      {
         int r = (int)MathRound(v);
         if(r < 0) r = 0;
         if(r > 3) r = 3;
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, (r & 1) != 0);
         ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  (r & 2) != 0);
         s_dkRay[k] = r;
         break;
      }
      case DRAW_SLOT_LOCK:
      {
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
         s_dkBack[k] = b;
         break;
      }
      default: return false;
   }
   s_dkValid[k] = true;
   return true;
}

bool DrawSlotPreviewColor(const string name, const color c)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || !DrawSlotAvailable(k, DRAW_SLOT_COLOR)) return false;
   bool same = ((color)ObjectGetInteger(0, name, OBJPROP_COLOR) == c);
   if(DrawKindHasLevels(k) && DrawLevelCount(name) > 0)
      same = same && ((color)ObjectGetInteger(0, name, OBJPROP_LEVELCOLOR, 0) == c);
   if(same) return false;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, c);
   return true;
}

//--- THE STYLE THE USER LAST USED FOR THIS KIND, WRITTEN ONTO A FRESH OBJECT.
//--- Called the moment the terminal reports the creation (see the entry's
//--- OBJECT_CREATE branch): a drawing the user made is adjusted to their own
//--- last look before they can even see it in the old style.
bool DrawStyleApplyOnCreate(const string name)
{
   if(name == "" || DrawIsIndicatorObject(name)) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || !s_dkValid[k]) return false;   // never touched: leave the terminal's own look
   if(ObjectFind(0, name) < 0) return false;
   if((DrawKindCaps(k) & DRAW_CAP_COLOR) != 0)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, s_dkColor[k]);
      if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, s_dkColor[k]);
   }
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
   if((DrawKindCaps(k) & DRAW_CAP_FILL) != 0)
      ObjectSetInteger(0, name, OBJPROP_FILL, s_dkFill[k]);
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

//--- P-DRAW-03, WHAT MT4 CANNOT DO AT ALL: the same look applied to EVERY
//--- drawing of the same kind on the chart. MT4's own dialog is strictly one
//--- object at a time; a trader who changes their mind about how their fibos
//--- look has to redo each one by hand. ONE walk, one look, and the kinds that
//--- are not the caller's are untouched.
int DrawPresetApplyToKind(const string fromName, const int slot)
{
   EDrawKind k = DrawKindOf(fromName);
   if(k == DK_NONE || slot < 0 || slot >= DRAW_PRESET_MAX) return 0;
   if(!s_dkPreset[k][slot].used) return 0;
   int done = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || DrawIsIndicatorObject(nm)) continue;
      if(DrawKindOf(nm) != k) continue;
      if(DrawPresetApply(nm, slot)) done++;
   }
   return done;
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
void DrawPresetsSave()
{
   int h = FileOpen(DrawPresetPath(), FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   for(int k = 1; k < DK_COUNT; k++)
      for(int i = DRAW_PRESET_BUILTIN; i < DRAW_PRESET_MAX; i++)
      {
         if(!s_dkPreset[k][i].used) continue;
         FileWrite(h, (int)k, i, s_dkPreset[k][i].name,
                   DoubleToString(DrawPresetPack(s_dkPreset[k][i]), 0));
      }
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
      if(k <= DK_NONE || k >= DK_COUNT) continue;
      if(i < DRAW_PRESET_BUILTIN || i >= DRAW_PRESET_MAX) continue;
      DrawPresetUnpack(StringToDouble(pk), s_dkPreset[k][i]);
      s_dkPreset[k][i].name = (nm == "" ? ("My " + IntegerToString(i - DRAW_PRESET_BUILTIN + 1)) : nm);
   }
   FileClose(h);
}

//--- the OFF paths and a removed instance must not leave the file behind.
void DrawPresetsForget()
{
   FileDelete(DrawPresetPath());
}

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
      done++;
   }
   return done;
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
#define DRAW_SEL_MAX 64

static string s_dkSel[DRAW_SEL_MAX];
static int    s_dkSelN = 0;

int DrawSelCount() { return s_dkSelN; }
bool DrawSelHas(const string name)
{
   for(int i = 0; i < s_dkSelN; i++) if(s_dkSel[i] == name) return true;
   return false;
}
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

//--- SNAPSHOT: the terminal's selected drawings of THIS kind, the held one
//--- always in. Returns the group size (0 when `hold` is not a drawing of ours).
int DrawSelSnapshot(const string hold)
{
   DrawSelClear();
   if(hold == "" || DrawIsIndicatorObject(hold)) return 0;
   EDrawKind k = DrawKindOf(hold);
   if(k <= DK_NONE || k >= DK_COUNT) return 0;
   s_dkSel[0] = hold;
   s_dkSelN = 1;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0 && s_dkSelN < DRAW_SEL_MAX; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || nm == hold) continue;
      if(DrawIsIndicatorObject(nm)) continue;
      if(DrawKindOf(nm) != k) continue;
      if(!(bool)ObjectGetInteger(0, nm, OBJPROP_SELECTED)) continue;
      s_dkSel[s_dkSelN] = nm;
      s_dkSelN++;
   }
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

#endif // DRAW_TOOLBAR_MQH
