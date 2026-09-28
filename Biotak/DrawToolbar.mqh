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
//--- P-DRAW-64a (2026-09-27) — THE BOX'S OWN TWO EXTRAS. User order: «یک ایکون
//--- برای 50 درصد طول باکس بزار ... و یک ایکون دیگه برای اکستند به راست بزار ...
//--- مهمه توی نوار استریپ باشه دم دست», then «۵۰ درصد باکس فقط میخوام، fill بهکارم
//--- نمیاد» (50 % OF THE BOX, not a half-filled interior) and then, after the length
//--- cut shipped: «خود باکس رو از وسط طول نصف میکنه که نباید باشه ... فقط 50 درصد مثل
//--- فیبو که 50 درصد مشخص میشه» — the 50 % is a LEVEL, the length is the hand's.
//--- Both marks already existed in the more-popover (P-DRAW-21/22, `[BX…]`); here they
//--- are SLOTS, one tap each:
//---   * BOXHALF — the 50 % line: `[BX50]`, a level at the box's own mid price, drawn by
//                `BoxMidSync` as the `<box>_BX50` child, the fib's own idiom;
//---   * EXTEND  — the box's later edge travels with the newest bar.
//--- APPENDED, so no existing slot index moved (the strip speaks these numbers).
#define DRAW_SLOT_BOXHALF 11
#define DRAW_SLOT_EXTEND  12
#define DRAW_SLOT_N        13
//--- P-DRAW-64 (2026-09-27) — THE SECOND COLOUR, ONE PER ROLE. User order: «رنگ
//--- بوردر بشه جدا تنظیم کرد ... و fill همه جدا. یک بخش براش اضافه کن». MT4 gives
//--- a drawing ONE colour (the docs' own `RectangleCreate` fills with `InpColor`;
//--- `OBJPROP_BGCOLOR` is the screen objects' — tool-parity-plan §5), so the split
//--- is: the LINE/BORDER stays `DRAW_SLOT_COLOR` and the INTERIOR is this slot.
//---   * the LEVEL family has a REAL second colour — `OBJPROP_LEVELCOLOR`;
//---   * the five FILLER kinds have none, so the interior is a CHILD object
//---     (`<drawing>_FL`, the `_BX50` pattern) wearing the interior's own colour.
//--- APPENDED, so no existing slot index moved (the strip speaks these numbers).
#define DRAW_SLOT_FILLCLR 10

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
#define DRAW_CAP_FILLCLR (1 << DRAW_SLOT_FILLCLR)   // P-DRAW-64: the interior's colour
#define DRAW_CAP_BOXHALF  (1 << DRAW_SLOT_BOXHALF)  // P-DRAW-64a: the box at 50% of its length
#define DRAW_CAP_EXTEND   (1 << DRAW_SLOT_EXTEND)   // P-DRAW-64a: the far edge travels
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
// P-HR-04 (2026-09-28) — THE RAY IS A DRAWING TOO. A Horizontal Ray carries
// the indicator prefix (so create/delete routing ignores it) but the STRIP
// serves it like a user trendline: hold-to-open, color/width/style/delete.
// The `_H` dot is nobody's drawing (handled by HRayTool, never hit, never
// served) — one suffix, one test, asked by every entry point below.
// P-HR-06: the marker is prefix-anchored — a USER drawing that merely
// mentions "_HRAY_" must never inherit ray behaviour.
bool DrawIsHRay(const string name)
{
   if(StringLen(inpObjectPrefix) == 0) return false;
   if(StringFind(name, inpObjectPrefix + "_HRAY_") != 0) return false;
   int l = StringLen(name);
   return !(l > 2 && StringSubstr(name, l - 2) == "_H");
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
//--- P-DRAW-64 (2026-09-27) — THE INTERIOR'S OWN CHILD, the same one-suffix / one-
//--- test the mid line took: MT4 gives a filler kind ONE colour, so a second colour
//--- for the interior is a child object (`<drawing>_FL`) wearing it. `DrawKindOf`
//--- answers DK_NONE for it, so the strip never serves it, the hit test never lands
//--- on it and no preset learns from it.
#define FILLCHILD_SUFFIX "_FL"
bool FillIsChild(const string name)
{
   int n = StringLen(name), s = StringLen(FILLCHILD_SUFFIX);
   if(n <= s) return false;
   return (StringSubstr(name, n - s, s) == FILLCHILD_SUFFIX);
}
string FillChildName(const string obj) { return obj + FILLCHILD_SUFFIX; }
string FillChildParent(const string child)
{
   if(!FillIsChild(child)) return "";
   return StringSubstr(child, 0, StringLen(child) - StringLen(FILLCHILD_SUFFIX));
}
//--- the five kinds whose interior MT4 can only draw in the LINE's colour (so the
//--- interior is a child); the level family's second colour is its LEVELCOLOR.
bool DrawKindHasFillBody(const EDrawKind k)
{
   return (k == DK_RECT || k == DK_TRIANGLE || k == DK_ELLIPSE ||
           k == DK_CHANNEL || k == DK_FIBOCHAN);
}
//--- ...and of those, the MT4 TYPES whose fill is a REAL fill of the type's own
//--- area (so a child of that type can carry the second colour). `DK_CHANNEL`
//--- covers three types and only one of them fills: a regression or a standard
//--- deviation channel has no fill property, so for those two the FILL slot keeps
//--- writing the MASTER's own property (exactly what it did before the split)
//--- instead of stacking a second outline on top of the first.
bool DrawTypeHasFillChild(const int type)
{
   return (type == OBJ_RECTANGLE || type == OBJ_TRIANGLE || type == OBJ_ELLIPSE ||
           type == OBJ_CHANNEL   || type == OBJ_FIBOCHANNEL);
}

// ══════════════════════════════════════════════════════════════════════════
// THE CLASSIFIER. MT4's type answers the kind, with ONE refinement: a trend
// line that carries a ray is a different ANIMAL on the chart (it runs to the
// edge and back), so the kind is decided by the flags, not by the type alone —
// that is also what makes the RAY slot meaningful for those objects only.
// ══════════════════════════════════════════════════════════════════════════
EDrawKind DrawKindOf(const string name)
{
   if(BoxIsMidChild(name)) return DK_NONE;    // P-DRAW-21: a box helper is served never
   if(FillIsChild(name))   return DK_NONE;    // P-DRAW-64: nor an interior's child
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
      // P-DRAW-64: the five FILLER kinds carry the interior too (FILL shows it,
      // FILLCLR is its colour), and the six LEVEL kinds' second colour IS their
      // levels (`OBJPROP_LEVELCOLOR`) — so every kind in the tool set that really
      // has a second colour shows the cell, and no other kind grows a control that
      // would only repeat the colour cell (C-04).
      //--- P-DRAW-64a: BOTH BOX EXTRAS ARE THE RECTANGLE'S ALONE. The 50 % is a line at
      //--- the box's own mid PRICE and the travelling edge is its far anchor, and both
      //--- are written for OBJ_RECTANGLE — a channel's third anchor and an ellipse's are
      //--- not that price, so a control there would be a promise nothing keeps (C-04:
      //--- no control where nothing would happen).
      case DK_CHANNEL:   return DRAW_CAP_COMMON | DRAW_CAP_FILL | DRAW_CAP_FILLCLR;
      case DK_FIBO:
      case DK_FIBOFAN:   return DRAW_CAP_COMMON | DRAW_CAP_FILLCLR;
      case DK_FIBOCHAN:  return DRAW_CAP_COMMON | DRAW_CAP_FILL | DRAW_CAP_FILLCLR;
      case DK_EXPANSION: return DRAW_CAP_COMMON | DRAW_CAP_FILLCLR;
      case DK_GANN:      return DRAW_CAP_COMMON | DRAW_CAP_FILLCLR;
      case DK_PITCHFORK: return DRAW_CAP_COMMON | DRAW_CAP_FILLCLR;
      case DK_RECT:      return DRAW_CAP_COMMON | DRAW_CAP_FILL | DRAW_CAP_FILLCLR |
                                DRAW_CAP_BOXHALF | DRAW_CAP_EXTEND;
      case DK_TRIANGLE:
      case DK_ELLIPSE:   return DRAW_CAP_COMMON | DRAW_CAP_FILL | DRAW_CAP_FILLCLR;
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
      if(nm == "" || (DrawIsIndicatorObject(nm) && !DrawIsHRay(nm))) continue;   // P-HR-04: rays are served
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
static color s_dkFillClr[DK_COUNT];  // P-DRAW-64: the interior's colour this kind last wore
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
      //--- P-DRAW-64: `clrNONE` is the "no colour of its own yet" of the interior —
      //--- a zero-initialised `color` is BLACK, which would be a colour the user
      //--- never chose (the P-DRAW-48 lesson, one slot over).
      s_dkFillClr[k] = clrNONE;
      s_dkWidth[k] = 1;
      s_dkStyle[k] = (int)STYLE_SOLID;
      s_dkFill[k]  = false;
      s_dkRay[k]   = 0;
      s_dkFont[k]  = DRAW_FONT_DEF;
      s_dkGlyph[k] = 0;
      s_dkBack[k]  = false;
   }
}

//--- "#RRGGBB" of a colour, and back. Moved DOWN from DrawStrip by P-DRAW-48
//--- because the description tags below are the slot owner's and need both — a
//--- second parser would be a second answer to one question (A-12).
string DrawStripColorHex(const color c)
{
   int v = (int)c;
   if(v < 0) v = 0;
   return StringFormat("#%02X%02X%02X", v % 256, (v / 256) % 256, v / 65536);
}
//--- P-DRAW-48 (2026-09-27) — THE TAG FORM IS SIX DIGITS, AND THE READER OWNS THE
//--- '#'. `DrawStripColorHex` is the DISPLAY form (`#RRGGBB`); writing that into
//--- `[CL…]` and then prepending a second '#' in the reader made every tag
//--- unparseable, so `DrawSlotColorPure` answered false and every read fell back
//--- to the ALREADY blended `OBJPROP_COLOR` — the opacity bar re-blended its own
//--- last blend on every frame (see the note on `DrawSlotOpacitySet`). One owner
//--- for the written form, so writer and reader cannot drift apart again.
string DrawDescColorHex(const color c) { return StringSubstr(DrawStripColorHex(c), 1); }
bool DrawStripHexToColor(const string s, color &c)
{
   string t = s;
   StringTrimLeft(t); StringTrimRight(t);
   if(StringLen(t) != 7 || StringGetCharacter(t, 0) != '#') return false;
   int v = 0;
   for(int i = 1; i < 7; i++)
   {
      int ch = StringGetCharacter(t, i);
      int d = -1;
      if(ch >= '0' && ch <= '9') d = ch - '0';
      else if(ch >= 'A' && ch <= 'F') d = ch - 'A' + 10;
      else if(ch >= 'a' && ch <= 'f') d = ch - 'a' + 10;
      if(d < 0) return false;
      v = v * 16 + d;
   }
   int r = (v >> 16) & 0xFF, g = (v >> 8) & 0xFF, b = v & 0xFF;
   c = (color)(r + g * 256 + b * 65536);
   return true;
}

//--- P-DRAW-48 (2026-09-26) — THE DRAWING'S OPACITY, AND WHY IT RIDES THE DESC.
//--- MT4 gives a drawing ONE colour and no alpha, so opacity is emulated the way
//--- every level in this product already emulates it: the object WEARS the colour
//--- blended towards the chart's own background (`BlendColorTowardsBG`, the one
//--- owner of that blend). The colour the user PICKED must not be lost inside that
//--- write, so it is stored beside the opacity on the object's own DESCRIPTION —
//--- `[OP70] [CLFFC247]` — the P-DRAW-21/22 channel: it survives reattach, a TF
//--- switch and a restart, and the user's own text rides along verbatim. Reads
//--- answer the PURE colour, so the picker's ring and the HEX field show what the
//--- user chose, never the blend. A TEXT object's description IS its content, so
//--- those kinds keep the pure colour and carry no tag (their row says so).
#define DRAW_OP_DEF 100
#define DRAW_OP_MIN   1     // 0 would be the chart's own background: invisible is a lie
//--- set/replace ONE `[TAGvalue]`, keeping every other byte. The tag LEADS, so
//--- `BoxMarkWrite`'s `pre` (everything before ` [BX`) keeps it and the extras of
//--- P-DRAW-21/22 survive a colour write.
string DrawDescTag(const string d, const string tag, const string val)
{
   string out = d;
   int at = StringFind(out, tag);
   if(at >= 0)
   {
      int e = StringFind(out, "]", at + StringLen(tag));
      if(e > at) out = StringSubstr(out, 0, at) + StringSubstr(out, e + 1);
   }
   if(StringLen(out) > 0 && StringGetCharacter(out, 0) == ' ') out = StringSubstr(out, 1);
   string want = tag + val + "]";
   return (out == "") ? want : (want + " " + out);
}
//--- ONE value reader and ONE colour reader for every tag (`[OP…]`, `[FT…]`, `[CL…]`,
//--- `[FL…]`), so a tag can never be parsed two ways (A-12). A colour tag's '#' is
//--- OPTIONAL: a build that wrote the display form heals on the next read (P-DRAW-48).
int DrawDescTagValue(const string d, const string tag, const int def)
{
   int at = StringFind(d, tag);
   if(at < 0) return def;
   int e = StringFind(d, "]", at + StringLen(tag));
   if(e <= at) return def;
   int n = e - at - StringLen(tag);
   if(n <= 0) return def;
   return (int)StringToInteger(StringSubstr(d, at + StringLen(tag), n));
}
bool DrawDescTagColor(const string d, const string tag, color &c)
{
   int at = StringFind(d, tag);
   if(at < 0) return false;
   int e = StringFind(d, "]", at + StringLen(tag));
   if(e <= at) return false;
   string t = StringSubstr(d, at + StringLen(tag), e - at - StringLen(tag));
   StringTrimLeft(t); StringTrimRight(t);
   if(t == "") return false;
   if(StringGetCharacter(t, 0) != '#') t = "#" + t;
   return DrawStripHexToColor(t, c);
}
//--- the LINE/BORDER's own alpha (`[OP…]`).
int DrawSlotOpacityGet(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return DRAW_OP_DEF;
   if(DrawKindOf(name) == DK_TEXT) return DRAW_OP_DEF;
   int v = DrawDescTagValue(ObjectGetString(0, name, OBJPROP_TEXT), "[OP", DRAW_OP_DEF);
   if(v < DRAW_OP_MIN) v = DRAW_OP_MIN;
   if(v > 100) v = 100;
   return v;
}
//--- P-DRAW-64: the INTERIOR's own alpha, as `[FT…]`. Its DEFAULT is the border's
//--- value, so a drawing made before the split wears exactly the pixels it wore (the
//--- interior was that colour at that alpha) and the user's own tone takes over the
//--- moment the tag exists. 100 is FULL and 0 is the chart's background — the same
//--- direction as `[OP…]`, through the one blend owner.
int DrawSlotFillOpacityGet(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return DRAW_OP_DEF;
   if(DrawKindOf(name) == DK_TEXT) return DRAW_OP_DEF;
   string d = ObjectGetString(0, name, OBJPROP_TEXT);
   if(StringFind(d, "[FT") < 0) return DrawSlotOpacityGet(name);
   int v = DrawDescTagValue(d, "[FT", 0);
   if(v < 0) v = 0;
   if(v > 100) v = 100;
   return v;
}
//--- "the alpha of THIS colour slot" — the bar the user drags and the render the
//--- chart wears both ask it, so the two cannot drift.
int DrawSlotAlphaGet(const string name, const int slot)
{
   return (slot == DRAW_SLOT_FILLCLR) ? DrawSlotFillOpacityGet(name)
                                      : DrawSlotOpacityGet(name);
}
//--- the LINE/BORDER's pure colour (`[CL…]`), or false when it has none yet.
bool DrawSlotColorPure(const string name, color &c)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   if(DrawKindOf(name) == DK_TEXT) return false;
   return DrawDescTagColor(ObjectGetString(0, name, OBJPROP_TEXT), "[CL", c);
}
//--- P-DRAW-64: the INTERIOR's pure colour (`[FL…]`), or false when it has none yet.
bool DrawSlotFillPure(const string name, color &c)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   if(DrawKindOf(name) == DK_TEXT) return false;
   return DrawDescTagColor(ObjectGetString(0, name, OBJPROP_TEXT), "[FL", c);
}
//--- the RENDER colour: what the chart must wear for this pure colour at the
//--- object's own opacity.
color DrawSlotRenderColor(const string name, const color pure)
{
   return BlendColorTowardsBG(pure, 100 - DrawSlotOpacityGet(name),
                              GetCachedChartBgColor());
}
//--- P-DRAW-64: the same question for the INTERIOR, at the INTERIOR's own tone.
//--- The one place the interior's pixels are computed, so the child, the level
//--- family and the strip's own swatch can never disagree about the tone.
color DrawSlotRenderFillColor(const string name, const color pure)
{
   return BlendColorTowardsBG(pure, 100 - DrawSlotFillOpacityGet(name),
                              GetCachedChartBgColor());
}
//--- the colour write's tag half: the PURE goes on the description, the object
//--- wears the blend. Returns what the chart must wear.
color DrawSlotColorStore(const string name, const color pure)
{
   if(name == "" || ObjectFind(0, name) < 0) return pure;
   if(DrawKindOf(name) == DK_TEXT) return pure;
   string d = ObjectGetString(0, name, OBJPROP_TEXT);
   d = DrawDescTag(d, "[CL", DrawDescColorHex(pure));
   ObjectSetString(0, name, OBJPROP_TEXT, d);
   return DrawSlotRenderColor(name, pure);
}
// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-64a (2026-09-27) — THE BOX'S MARK GROUP, MOVED DOWN TO THE SLOTS.
// `[BX…]` (the 50% mid line and the far-edge behaviour, P-DRAW-21/22) lived in
// DrawStrip.mqh. The two extras are SLOTS now — the user wants them one tap away
// in the strip's own row — and a slot is read and written HERE, where MQL4's
// define-before-use rule puts the group's one reader and one writer. The GEOMETRY
// the marks drive (the mid child, the extend step, the pump) stays in DrawStrip.
// One group, one writer: `[BX50]`, `[BXE1]`/`[BXE2]`/`[BXE3:N]`.
// ══════════════════════════════════════════════════════════════════════════
#define BOXEXT_OFF   0
#define BOXEXT_TOUCH 1
#define BOXEXT_END   2
#define BOXEXT_NBARS 3
//--- P-DRAW-64a, THIRD cut (2026-09-27) — THE 50 % IS THE LEVEL, NOT THE LENGTH.
//--- User order: «خود باکس رو از وسط طول نصف میکنه که نباید باشه … فقط 50 درصد مثل
//--- فیبو که 50 درصد مشخص میشه». So the cell is the `[BX50]` MARK and nothing else: the
//--- mid line the more-popover already drew, at the box's own mid PRICE, drawn by
//--- `BoxMidSync` (DrawStrip) and owned there. NO anchor of the drawing is touched —
//--- the box keeps the length the hand gave it, and the interior is not a party to it
//--- either. That kills the whole `[BXH:<seconds>]` payload with it: a remembered
//--- length existed only to put back what the cell had cut, and the third cut cuts
//--- nothing, so `DrawBoxHalfSpan/Read/Write` and `BoxHalfRecheck` are GONE rather than
//--- left as a second way to say "half".
void BoxMarkRead(const string name, bool &mid, int &ext, int &extN)
{
   mid = false; ext = BOXEXT_OFF; extN = 0;
   if(name == "" || ObjectFind(0, name) < 0) return;
   string d = ObjectGetString(0, name, OBJPROP_TEXT);
   if(StringFind(d, "[BX50]") >= 0) mid = true;
   int at = StringFind(d, "[BXE");
   if(at < 0) return;
   string tail = StringSubstr(d, at + 4);
   if(StringLen(tail) < 1) return;
   string m = StringSubstr(tail, 0, 1);
   if(m == "1") ext = BOXEXT_TOUCH;
   else if(m == "2") ext = BOXEXT_END;
   else if(m == "3")
   {
      ext = BOXEXT_NBARS;
      int c = StringFind(tail, ":"), e = StringFind(tail, "]");
      if(c > 0 && e > c) extN = (int)StringToInteger(StringSubstr(tail, c + 1, e - c - 1));
      if(extN <= 0) ext = BOXEXT_OFF;
   }
}
void BoxMarkWrite(const string name, const bool mid, const int ext, const int extN)
{
   if(name == "" || ObjectFind(0, name) < 0) return;
   string d = ObjectGetString(0, name, OBJPROP_TEXT);
   int at = StringFind(d, " [BX");
   string pre = (at >= 0) ? StringSubstr(d, 0, at) : d;
   if(at < 0 && StringFind(d, "[BX") == 0) pre = "";
   string want = pre;
   if(mid) want += ((want == "") ? "" : " ") + "[BX50]";
   if(ext == BOXEXT_TOUCH) want += ((want == "") ? "" : " ") + "[BXE1]";
   else if(ext == BOXEXT_END) want += ((want == "") ? "" : " ") + "[BXE2]";
   else if(ext == BOXEXT_NBARS && extN > 0)
      want += ((want == "") ? "" : " ") + "[BXE3:" + IntegerToString(extN) + "]";
   //--- the 50 % is the `[BX50]` MARK, nothing else: the mid line is a drawing of its
   //--- own, so this rewrite can never drop it and needs no payload to re-emit.
   if(want == d) return;
   ObjectSetString(0, name, OBJPROP_TEXT, want);
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
      {
         // P-DRAW-48: what the user CHOSE is the description's `[CL…]`; the
         // object's own colour is that colour blended at its opacity.
         color pure;
         if(DrawSlotColorPure(name, pure)) return (double)(int)pure;
         if(lvl) return (double)(int)ObjectGetInteger(0, name, OBJPROP_LEVELCOLOR, 0);
         return (double)(int)ObjectGetInteger(0, name, OBJPROP_COLOR);
      }
      case DRAW_SLOT_WIDTH:
         if(lvl) return (double)(int)ObjectGetInteger(0, name, OBJPROP_LEVELWIDTH, 0);
         return (double)(int)ObjectGetInteger(0, name, OBJPROP_WIDTH);
      case DRAW_SLOT_STYLE:
         if(lvl) return (double)(int)ObjectGetInteger(0, name, OBJPROP_LEVELSTYLE, 0);
         return (double)(int)ObjectGetInteger(0, name, OBJPROP_STYLE);
      case DRAW_SLOT_FILL:
      {
         // P-DRAW-64: for a FILLER kind the interior is the CHILD, so the flag means
         // "the interior is on the chart" — the child's existence, or the master's own
         // fill a build before the split left behind (adopted on the next sync, which
         // then clears it so two colours can coexist).
         if(DrawTypeHasFillChild(DrawObjectType(name)))
            return (((ObjectFind(0, FillChildName(name)) >= 0) ||
                     (int)ObjectGetInteger(0, name, OBJPROP_FILL) != 0) ? 1.0 : 0.0);
         return ((int)ObjectGetInteger(0, name, OBJPROP_FILL) != 0) ? 1.0 : 0.0;
      }
      case DRAW_SLOT_FILLCLR:
      {
         // P-DRAW-64: the user's own interior colour, else what the interior already
         // wears — the level family's level colour, or the LINE's own pure, so a
         // drawing made before the split answers the colour it is filled with.
         color ipure;
         if(DrawSlotFillPure(name, ipure)) return (double)(int)ipure;
         if(lvl) return (double)(int)ObjectGetInteger(0, name, OBJPROP_LEVELCOLOR, 0);
         return DrawSlotRead(name, DRAW_SLOT_COLOR);
      }
      //--- P-DRAW-64a: the box's own 50 % LEVEL, read off its mark group.
      case DRAW_SLOT_BOXHALF:
      {
         bool mid = false; int ext = BOXEXT_OFF, exn = 0;
         BoxMarkRead(name, mid, ext, exn);
         return (mid ? 1.0 : 0.0);
      }
      case DRAW_SLOT_EXTEND:
      {
         bool mid = false; int ext = BOXEXT_OFF, exn = 0;
         BoxMarkRead(name, mid, ext, exn);
         return ((ext != BOXEXT_OFF) ? 1.0 : 0.0);
      }
      case DRAW_SLOT_RAY:
      {
         int r = 0;
         if((int)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != 0) r |= 1;
         if((int)ObjectGetInteger(0, name, OBJPROP_RAY_LEFT) != 0)  r |= 2;
         return (double)r;
      }
      case DRAW_SLOT_LOCK:
         if(DrawIsHRay(name)) return 0.0;   // P-HR-04: lock is N/A on rays (dot carry instead)
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

//--- P-DRAW-64 — THE INTERIOR'S OWN CHILD (`<drawing>_FL`). ONE owner for "does this
//--- drawing show an interior, and of which colour": created while the FILL slot is
//--- on, the master's own MT4 shape and anchors, filled, in the BACKGROUND (a fill is
//--- a behind-the-bars layer — the product's own box fill has lived there since
//--- P-BK-58) and non-selectable, so the terminal's drag can only ever grab the
//--- master. Idempotent and guarded: a steady state costs reads, not writes.
//--- DROP first, then the maker and the state follower: MQL4 has no forward
//--- declarations, so every callee stands above its callers.
bool FillChildDrop(const string obj)
{
   if(obj == "") return false;
   string ch = FillChildName(obj);
   if(ObjectFind(0, ch) < 0) return false;
   return ObjectDelete(0, ch);
}
bool FillChildEnsure(const string obj)
{
   if(obj == "" || FillIsChild(obj)) return false;
   if(DrawIsIndicatorObject(obj)) return false;   // P-DRAW-64: the strip's scope, not the tool's
   if(ObjectFind(0, obj) < 0) return false;
   EDrawKind k = DrawKindOf(obj);
   if(!DrawKindHasFillBody(k)) return FillChildDrop(obj);
   int type = DrawObjectType(obj);
   if(!DrawTypeHasFillChild(type)) return FillChildDrop(obj);
   string ch = FillChildName(obj);
   // The master keeps ONLY its outline from now on: the interior is the child's
   // pixel, and the child's colour is the interior's own (it may differ).
   if((int)ObjectGetInteger(0, obj, OBJPROP_FILL) != 0)
      ObjectSetInteger(0, obj, OBJPROP_FILL, false);
   if(ObjectFind(0, ch) < 0)
   {
      datetime t1 = (datetime)ObjectGetInteger(0, obj, OBJPROP_TIME, 0);
      double   p1 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 0);
      if(t1 <= 0) return false;
      if(!ObjectCreate(0, ch, type, 0, t1, p1)) return false;
      ObjectSetInteger(0, ch, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ch, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, ch, OBJPROP_FILL, true);
      ObjectSetInteger(0, ch, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ch, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, ch, OBJPROP_ZORDER, Z_CHART_ZONE);
      ObjectSetString(0, ch, OBJPROP_TOOLTIP,
                      "Interior of \"" + obj + "\" — its colour and tone live in the strip");
   }
   //--- P-DRAW-64 addendum 7 (2026-09-27) — THE INTERIOR IS IN ITS BOX'S OWN LAYER.
   //--- The child was hard-wired `OBJPROP_BACK = true` (behind the bars) while the box
   //--- is in front, and THAT is the whole of the lag the user kept reporting: MT4 paints
   //--- the layer the dragged object lives in as soon as the drag moves it, so an interior
   //--- parked in the other layer is painted by the NEXT pass — «فقط رنگ‌کشی یک فریم عقب‌تر
   //--- است», the data long since correct (addendum 6). Same layer, one pass, no gap. The
   //--- interior therefore MIRRORS the box's own BACK, which also makes the strip's BACK
   //--- cell one honest switch for the whole drawing instead of a hidden rule. Cost: one
   //--- guarded compare per sync, a write only when the box's layer really changed.
   int mBack = (int)ObjectGetInteger(0, obj, OBJPROP_BACK);
   if((int)ObjectGetInteger(0, ch, OBJPROP_BACK) != mBack)
      ObjectSetInteger(0, ch, OBJPROP_BACK, mBack);
   //--- geometry: the master's own anchors, verbatim (three cover rect / triangle /
   //--- ellipse / channel / fibochannel — a child that drifts is worse than none).
   //--- P-DRAW-64a: the interior follows the box as it IS, and it is no party to any of
   //--- the box's own controls: the 50 % is a level at the mid PRICE, the extend moves
   //--- the far edge, and either way the interior is the same anchors it always was.
   for(int a = 0; a < 3; a++)
   {
      datetime tt = (datetime)ObjectGetInteger(0, obj, OBJPROP_TIME, a);
      double   pp = ObjectGetDouble(0, obj, OBJPROP_PRICE, a);
      if(tt <= 0) continue;
      if((datetime)ObjectGetInteger(0, ch, OBJPROP_TIME, a) != tt)
         ObjectSetInteger(0, ch, OBJPROP_TIME, a, tt);
      if(ObjectGetDouble(0, ch, OBJPROP_PRICE, a) != pp)
         ObjectSetDouble(0, ch, OBJPROP_PRICE, a, pp);
   }
   int st = (int)ObjectGetInteger(0, obj, OBJPROP_STYLE);
   if((int)ObjectGetInteger(0, ch, OBJPROP_STYLE) != st) ObjectSetInteger(0, ch, OBJPROP_STYLE, st);
   //--- P-DRAW-64 addendum 4 (2026-09-27): THE CHILD'S OWN FRAME IS THE THINNEST
   //--- LEGAL ONE. Its frame shares its fill's ink, so in step it hides under the
   //--- master's frame; the only thing a sub-frame lag could ever show is a 1 px
   //--- sliver instead of a lip («این لبها و دور کادرها ... گاه ظاهر میشن»).
   if((int)ObjectGetInteger(0, ch, OBJPROP_WIDTH) != 1) ObjectSetInteger(0, ch, OBJPROP_WIDTH, 1);
   color ipure = clrNONE;
   if(!DrawSlotFillPure(obj, ipure)) ipure = (color)(int)DrawSlotRead(obj, DRAW_SLOT_COLOR);
   if((int)ipure < 0) ipure = (color)(int)DrawSlotRead(obj, DRAW_SLOT_COLOR);
   color ink = BlendColorTowardsBG(ipure, 100 - DrawSlotFillOpacityGet(obj),
                                   GetCachedChartBgColor());
   if((color)ObjectGetInteger(0, ch, OBJPROP_COLOR) != ink)
      ObjectSetInteger(0, ch, OBJPROP_COLOR, ink);
   return true;
}
// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-64 (2026-09-27) — THE PREVIEW PAIR, AND IT WEARS THE OBJECT'S OWN TONE.
// First cut of the preview wrote `OBJPROP_COLOR = c` — the PURE colour — which is a
// second render owner, and the report proved the cost: «من این شفافیت تنظیم میکنم
// موس میره روی بقیه رنگه ناخواسته شفافیت [از دست میره]» — the moment the pointer
// crossed a cell, the tone the user had just tuned on the bar fell back to full
// strength. Both functions below go through the SAME two owners the real write
// does (`DrawSlotRenderColor` / `DrawSlotRenderFillColor`), so a previewed pixel is
// identical to the applied one. `DrawSlotRenderRestore` is the reverse: put the
// drawing back to the pixels its own tags say.
bool DrawSlotPreviewColor(const string name, const color c)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || !DrawSlotAvailable(k, DRAW_SLOT_COLOR)) return false;
   if(DrawIsHRay(name))   // P-HR-04: preview the plain ink the apply will write
   {
      if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) == c) return false;
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      return true;
   }
   color rc = DrawSlotRenderColor(name, c);
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) == rc) return false;
   ObjectSetInteger(0, name, OBJPROP_COLOR, rc);
   if(DrawKindHasLevels(k)) DrawLevelsSetColor(name, rc);
   return true;
}
bool DrawSlotPreviewFillColor(const string name, const color c)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || !DrawSlotAvailable(k, DRAW_SLOT_FILLCLR)) return false;
   color rc = DrawSlotRenderFillColor(name, c);
   if(DrawKindHasFillBody(k))
   {
      string ch = FillChildName(name);
      if(ObjectFind(0, ch) < 0) return false;   // no interior on the chart to preview
      if((color)ObjectGetInteger(0, ch, OBJPROP_COLOR) == rc) return false;
      ObjectSetInteger(0, ch, OBJPROP_COLOR, rc);
      return true;
   }
   if(!DrawKindHasLevels(k) || DrawLevelCount(name) <= 0) return false;
   if((color)ObjectGetInteger(0, name, OBJPROP_LEVELCOLOR, 0) == rc) return false;
   DrawLevelsSetColor(name, rc);
   return true;
}
//--- the pixels the tags say, and only those: the preview's undo. One owner, so a
//--- cancelled preview, a scrub left mid-air and a chart that drifted all land on
//--- the same answer.
bool DrawSlotRenderRestore(const string name)
{
   if(name == "" || ObjectFind(0, name) < 0) return false;
   EDrawKind k = DrawKindOf(name);
   if(k == DK_NONE || k == DK_TEXT) return false;
   color pure = clrNONE;
   bool havePure = DrawSlotColorPure(name, pure);
   if(havePure) pure = DrawSlotRenderColor(name, pure);
   else pure = (color)(int)DrawSlotRead(name, DRAW_SLOT_COLOR);
   bool changed = false;
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != pure)
   { ObjectSetInteger(0, name, OBJPROP_COLOR, pure); changed = true; }
   if(DrawKindHasLevels(k) && DrawLevelCount(name) > 0)
   {
      color ip;
      color ir = DrawSlotFillPure(name, ip) ? DrawSlotRenderFillColor(name, ip) : pure;
      if((color)ObjectGetInteger(0, name, OBJPROP_LEVELCOLOR, 0) != ir)
      { DrawLevelsSetColor(name, ir); changed = true; }
   }
   if(DrawKindHasFillBody(k))
   {
      string ch = FillChildName(name);
      if(ObjectFind(0, ch) >= 0)
      {
         color ip2;
         if(!DrawSlotFillPure(name, ip2)) ip2 = (color)(int)DrawSlotRead(name, DRAW_SLOT_COLOR);
         if((int)ip2 >= 0)
         {
            color ink = DrawSlotRenderFillColor(name, ip2);
            if((color)ObjectGetInteger(0, ch, OBJPROP_COLOR) != ink)
            { ObjectSetInteger(0, ch, OBJPROP_COLOR, ink); changed = true; }
         }
      }
   }
   return changed;
}

//--- the FILL slot's follower: on means "the interior is on the chart" — the
//--- child, or the master's own fill a build before the split left behind.
//--- P-DRAW-64 (2026-09-27) — AND IT IS THE USER'S DRAWINGS' BUSINESS ONLY.
//--- Reported: «من اینو که جابجا میکنم اون یکی جا میمونه» with a screenshot of an
//--- indicator box whose interior had been turned into a stale child. The split is
//--- the STRIP's, i.e. the objects the strip serves; the indicator's OWN drawings
//--- (its boxes, zones, levels, the panels) carry `inpObjectPrefix` and are out of
//--- scope by the module's first law — every entry point here asks that first, so a
//--- drag anywhere on the chart (this call rides `CHARTEVENT_OBJECT_DRAG`, which
//--- fires for EVERY object) can never touch the product's own rendering.
bool FillChildSync(const string obj)
{
   if(obj == "" || FillIsChild(obj)) return false;
   if(DrawIsIndicatorObject(obj)) return false;   // the product's own: not ours to split
   if(ObjectFind(0, obj) < 0) return false;
   if(!DrawTypeHasFillChild(DrawObjectType(obj))) return false;   // cheapest out
   if(!DrawKindHasFillBody(DrawKindOf(obj))) return false;
   if(DrawSlotRead(obj, DRAW_SLOT_FILL) < 0.5) return FillChildDrop(obj);
   return FillChildEnsure(obj);
}
//--- P-DRAW-64 addendum 6 (2026-09-27) — THE INTERIOR RIDES THE HAND, NOT THE DRAG
//--- EVENT. The report that outlived three builds: «این باکس که جابجا میکنه این fill
//--- ازش جا میمکون بعد چند میلی ثانیه بعدش جفت میشه». Two causes, both closed here and
//--- in addendum 7, and neither of them is a missing witness — the witness already sat at
//--- the head of the router and stamped the child in the very event that moved the master.
//---   (a) THE EVENT COALESCES. MT4 merges a run of identical ids, so a dropped
//---       OBJECT_DRAG frame is a frame the interior did not move in. The MOVE STREAM does
//---       not coalesce (every pixel of travel is its own event) and the press already
//---       named the object (`s_dsPressObj`, P-UI-113i), so this costs NO hit test.
//---   (b) THE LAYER DID NOT. The child was hard-wired behind the bars while the box is in
//---       front, so the terminal painted the box's layer on the drag and the interior's in
//---       the next pass — «فقط رنگ‌کشی یک فریم عقب‌تر است», the data long since correct.
//--- Cost: a still frame pays four reads and one compare, a real move the guarded sync, an
//--- idle hand one string compare, and the arming rides the drag event too, so a gesture
//--- MT4 reports only as OBJECT_CHANGE is covered as well. One hand at a time, so the memo
//--- is one slot; it re-arms on the name and rests on the release.
static string s_fcmName = "";
static long   s_fcmT0 = 0, s_fcmT1 = 0;
static double s_fcmP0 = 0.0, s_fcmP1 = 0.0;
void FillChildStampArm(const string obj)
{
   s_fcmName = "";
   if(obj == "" || ObjectFind(0, obj) < 0) return;
   if(!DrawTypeHasFillChild(DrawObjectType(obj))) return;
   if(ObjectFind(0, FillChildName(obj)) < 0) return;   // no interior: nothing follows
   s_fcmName = obj;
   s_fcmT0 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 0);
   s_fcmT1 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 1);
   s_fcmP0 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 0);
   s_fcmP1 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 1);
}
void FillChildStampRelease() { s_fcmName = ""; }
bool FillChildStamp(const string obj)
{
   if(obj == "" || obj != s_fcmName) return false;
   if(ObjectFind(0, obj) < 0) { s_fcmName = ""; return false; }
   long t0 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 0);
   long t1 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 1);
   double p0 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 0);
   double p1 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 1);
   if(t0 == s_fcmT0 && t1 == s_fcmT1 && p0 == s_fcmP0 && p1 == s_fcmP1) return false;
   s_fcmT0 = t0; s_fcmT1 = t1; s_fcmP0 = p0; s_fcmP1 = p1;
   return FillChildSync(obj);
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
         color rc = DrawSlotColorStore(name, c);   // P-DRAW-48: pure on the desc, blend on the chart
         ObjectSetInteger(0, name, OBJPROP_COLOR, rc);
         //--- P-DRAW-64: an interior the user has NOT coloured follows the border,
         //--- so a border write re-inks it too — the child, or the levels.
         color ip;
         if(DrawKindHasLevels(k))
            DrawLevelsSetColor(name, DrawSlotFillPure(name, ip) ? DrawSlotRenderFillColor(name, ip) : rc);
         if(DrawKindHasFillBody(k)) FillChildSync(name);
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
         if(!DrawIsHRay(name)) s_dkWidth[k] = w;   // P-HR-04: rays learn nothing
         break;
      }
      case DRAW_SLOT_STYLE:
      {
         int st = (int)MathRound(v);
         if(st < 0) st = 0;
         if(st > (int)STYLE_DASHDOTDOT) st = (int)STYLE_DASHDOTDOT;
         ObjectSetInteger(0, name, OBJPROP_STYLE, st);
         if(DrawKindHasLevels(k)) DrawLevelsSetStyle(name, st);
         if(!DrawIsHRay(name)) s_dkStyle[k] = st;   // P-HR-04: rays learn nothing
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
   if(hold == "" || (DrawIsIndicatorObject(hold) && !DrawIsHRay(hold))) return 0;   // P-HR-04
   EDrawKind k = DrawKindOf(hold);
   if(k <= DK_NONE || k >= DK_COUNT) return 0;
   s_dkSel[0] = hold;
   s_dkSelN = 1;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0 && s_dkSelN < DRAW_SEL_MAX; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm == "" || nm == hold) continue;
      if(DrawIsIndicatorObject(nm) && !DrawIsHRay(nm)) continue;   // P-HR-04: rays group too
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
