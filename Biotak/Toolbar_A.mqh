// Toolbar_A.mqh - DrawToolbar.mqh split 2026-09-29: exact lines 10-1199, byte-identical, zero renames.
#ifndef TOOLBAR_A_MQH
#define TOOLBAR_A_MQH


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
//--- `OBJPROP_BGCOLOR` is the screen objects' — see docs/contract.md §2), so the split
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
//
// P-DRAW-87 (2026-09-30) — ONE FAMILY WAS NOT UNDER THAT PREFIX, AND THIS TEST
// WAS THE WHOLE BUG. «شادو رسم میشه بعد چند ثانیه نیست» (the HTF candle's shadow box
// is drawn and then gone) was NOT a look, a slider or a mask: the overlay's boxes
// are born `BiotakHTF_<chartid>_*` (HTFCandles' own namespace — `inpObjectPrefix`
// is "THLevels"), so every entry point below read them as the USER's drawings.
// The one that shows is the 2 s `BoxExtrasPump` (DrawStrip_Pick): it saw a filled
// rectangle that was not ours, ran the interior split on it, cleared the master's
// FILL and created `<name>_FL` filled with `BlendColorTowardsBG(..., background)`
// — the chart background itself, byte-identical, because a foreign object carries
// no opacity slot (100 - 0 = 100). The hollow BODIES survived untouched, which is
// why the report is about the shadow alone: `OBJPROP_FILL` is already 0 on them,
// so the pump's own `Fill != 0 || child exists` probe never fires.
//
// The name cannot be re-declared here (P-UI-68: HTFCandles is the ONE writer of an
// HTF name), and HTFCandles is included AFTER this file, so the overlay PUBLISHES
// its root — `g_OverlayNameRoot` (GlobalVariables) — and this is one head-on test
// of it. The level prefix is tested FIRST because it owns the walk's majority: a
// name it answers returns without paying for the second compare.
// ══════════════════════════════════════════════════════════════════════════
bool DrawIsIndicatorObject(const string name)
{
   if(name == "") return true;                      // no name, no drawing
   int n = StringLen(name);
   if(n == 0) return false;
   int p = StringLen(inpObjectPrefix);
   if(p > 0 && n >= p && StringSubstr(name, 0, p) == inpObjectPrefix) return true;
   //--- P-DRAW-87: the overlay's published namespace. "" until the HTF module
   //--- publishes it (one write, at its init), and then this answers false for
   //--- every name exactly as it did before the test existed.
   int o = StringLen(g_OverlayNameRoot);
   if(o > 0 && n >= o && StringSubstr(name, 0, o) == g_OverlayNameRoot) return true;
   return false;
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
// P-UI-136: THE PATH IS A DRAWING TOO — the strip serves a path segment exactly
// as it serves a ray (colour/width/style, hold-to-open, bin delete). The test is
// the path's OWN id parser (`PathIdOfName`), so a handle (`_H<n>`, whose tail is
// not digits) is never served and a user line that merely mentions "_PATH_" is
// never mistaken for one.
bool DrawIsPathSeg(const string name)
{
   if(StringLen(inpObjectPrefix) == 0) return false;
   if(StringFind(name, inpObjectPrefix + PATH_TAG) != 0) return false;
   string id;
   return PathIdOfName(name, id);
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
      if(nm == "" || (DrawIsIndicatorObject(nm) && !DrawIsHRay(nm) && !DrawIsPathSeg(nm))) continue;   // P-HR-04/P-UI-136: rays and paths are served
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
      //--- P-DRAW-64: `clrNONE` is the "no color of its own yet" of the interior —
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
   //--- P-UI-137: a path keeps its alpha in its OWN store, never in a `[OP…]` tag
   //--- (MT4 paints a desc along a trend line), so the read asks the path first.
   if(DrawIsPathSeg(name))
   {
      string pid = "";
      if(PathIdOfName(name, pid)) return PathInkOpacityGet(pid);
   }
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
//--- "the alpha of THIS color slot" — the bar the user drags and the render the
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
//--- P-UI-134 (2026-10-02) — THE MARKS ARE A KEY, NOT A SUBSTRING. The `[BX…]`
//--- design put two owners' state INSIDE a string that FOUR other owners rewrite
//--- (`[CL…]`, `[OP…]`, `[FL…]`, `[FT…]`), so every mark write had to re-serialise a
//--- string it does not own and then cut its own block out of it. Three attempts failed
//--- in a row: P-UI-133 fixed the cut point (`" [BX"` matched the space in front of the
//--- SECOND tag, so `pre` kept `[BX50]`), and the live box then refused BOTH marks to
//--- clear — `slot=11 … -> 0 read=1` AND `slot=12 … -> 0 read=1` («الان هیچکدوم درست
//--- کار نمیکنه»). A shared mutable string with four writers is not a serialisation; it
//--- is a parser racing three other parsers. **The architecture**: one keyed value per
//--- box in the TERMINAL'S OWN store — the same store `BaseKnotGV` already uses for
//--- per-box state (Biotak/BaseKnot_Base.mqh:802), so this is the project's existing
//--- pattern, not a new idea. Nothing is parsed, no block is cut, the mark owner never
//--- writes `OBJPROP_TEXT` again, and the legacy tags are READ ONCE (migration) and
//--- then left in place, inert.
//--- THE VALUE: an MQL4 global carries a double, so the three fields ride ONE integer
//--- (`fp << 22 | n << 12 | ext << 2 | mid`, exact well past 2^40). `fp` is a 20-bit
//--- fingerprint of the box's own NAME, so a key belonging to another box can never be
//--- believed, and a dead key heals to «no marks» instead of wearing someone else's.
#define BOXMARK_FP_MOD 1048576          // 2^20 — the fingerprint's space
string BoxMarkKey(const string name)
{
   long h = 5381;                      // djb2, truncated: stable across runs
   for(int i = 0; i < StringLen(name); i++)
      h = ((h * 33) + (long)StringGetCharacter(name, i)) % BOXMARK_FP_MOD;
   return "Biotak_BXM_" + IntegerToString((int)h) + "_" + GetCachedChartIdStr();
}
int BoxMarkFingerprint(const string name)
{
   long h = 5381;
   for(int i = 0; i < StringLen(name); i++)
      h = ((h * 33) + (long)StringGetCharacter(name, i)) % BOXMARK_FP_MOD;
   return (int)h;
}
//--- the legacy `[BX…]` format, parsed ONCE and never written again. PARSING a format
//--- you do not write is safe; WRITING it inside somebody else's string was the hazard.
void BoxMarkLegacyRead(const string d, bool &mid, int &ext, int &extN)
{
   mid = false; ext = BOXEXT_OFF; extN = 0;
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
void BoxMarkRead(const string name, bool &mid, int &ext, int &extN)
{
   mid = false; ext = BOXEXT_OFF; extN = 0;
   if(name == "" || ObjectFind(0, name) < 0) return;
   string key = BoxMarkKey(name);
   //--- the store is the census. One check per read; a present key costs one get, and
   //--- the fingerprint is verified BEFORE anything is believed (a 20-bit collision, or
   //--- a key left by an object that no longer exists, both fall through to migration).
   if(GlobalVariableCheck(key))
   {
      long v = (long)GlobalVariableGet(key);
      int md = (int)(v % 2); v /= 2;
      int ex = (int)(v % 4); v /= 4;
      int nn = (int)(v % 4096); v /= 4096;
      if((int)v == BoxMarkFingerprint(name))
      {
         mid = (md != 0);
         ext = ex;
         extN = (ex == BOXEXT_NBARS) ? nn : 0;
         return;
      }
   }
   //--- MIGRATION, once per box and only while the store is empty: adopt the legacy tags
   //--- and LEAVE THEM in the description. Cutting them would be one more edit of a
   //--- string four owners share — and inert text costs nothing.
   string d = ObjectGetString(0, name, OBJPROP_TEXT);
   if(StringFind(d, "[BX") < 0) return;
   bool lmid = false; int lext = BOXEXT_OFF, ln = 0;
   BoxMarkLegacyRead(d, lmid, lext, ln);
   if(lmid || lext != BOXEXT_OFF) BoxMarkWrite(name, lmid, lext, ln);
}
void BoxMarkWrite(const string name, const bool mid, const int ext, const int extN)
{
   if(name == "" || ObjectFind(0, name) < 0) return;
   string key = BoxMarkKey(name);
   //--- no marks = NO KEY. A box with nothing to remember owns nothing, so a plain
   //--- rectangle leaves no trace in the terminal's global list.
   if(!mid && ext == BOXEXT_OFF)
   {
      if(GlobalVariableCheck(key)) GlobalVariableDel(key);
      return;
   }
   int ex = (ext == BOXEXT_TOUCH) ? 1 : (ext == BOXEXT_END) ? 2 : (ext == BOXEXT_NBARS) ? 3 : 0;
   int nn = (ex == 3 && extN > 0 && extN < 4096) ? extN : 0;
   long v = BoxMarkFingerprint(name);
   v = v * 4096 + nn;
   v = v * 4 + ex;
   v = v * 2 + (mid ? 1 : 0);
   GlobalVariableSet(key, (double)v);
}
//--- the one place a box's key is DESTROYED: every delete path already calls
//--- `BoxMidDrop`/`FillChildDrop`, and this is their third sibling. MT4 reuses object
//--- names across sessions («Rectangle 17282» again), so a key that outlived its box
//--- would hand a fresh box a dead box's marks — the fingerprint cannot catch that
//--- (same name, same hash), only the delete can.
void BoxMarkDrop(const string name)
{
   if(name == "") return;
   string key = BoxMarkKey(name);
   if(GlobalVariableCheck(key)) GlobalVariableDel(key);
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
         // P-UI-137: a path has no description — its PURE lives in the path's own
         // store, so the HEX field and the readout show the colour the user picked,
         // not the blend the chart wears.
         if(DrawIsPathSeg(name))
         {
            string pid = "";
            color pp = clrNONE; int pv = 100;
            if(PathIdOfName(name, pid) && PathInkGet(pid, pp, pv)) return (double)(int)pp;
         }
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
         // P-UI-139: a path answers this cell from its OWN switch (the midpoint
         // markers); the rectangle answers it from the box's keyed marks store.
         if(DrawIsPathSeg(name))
         {
            string pid = "";
            if(PathIdOfName(name, pid)) return PathMidGet(pid) ? 1.0 : 0.0;
         }
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
         if(DrawIsHRay(name)) return 0.0;   // P-HR-04: the ray's lock is N/A (the dot carry replaces it)
      // P-UI-138: a PATH's lock is its OWN flag (Toolbar_B's write arms it, the press
      // branch asks it) — the read must answer the same owner or the cell could never
      // show the state the writer just set.
      if(DrawIsPathSeg(name))
      {
         string pid = "";
         if(PathIdOfName(name, pid)) return PathLockGet(pid) ? 1.0 : 0.0;
      }
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
      datetime t2 = (datetime)ObjectGetInteger(0, obj, OBJPROP_TIME, 1);
      double   p2 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 1);
      if(t1 <= 0) return false;
      if(t2 <= 0) { t2 = t1; p2 = p1; }
      if(!ObjectCreate(0, ch, type, 0, t1, p1, t2, p2)) return false;
      ObjectSetInteger(0, ch, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ch, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, ch, OBJPROP_FILL, true);
      ObjectSetInteger(0, ch, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, ch, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, ch, OBJPROP_ZORDER, Z_CHART_ZONE);
      ObjectSetString(0, ch, OBJPROP_TOOLTIP,
                      "Interior of \"" + obj + "\" — its color and tone live in the strip");
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
   // P-UI-136: the path previews on every segment — a preview that showed one
   // segment tinted would promise a write the apply fans out over the family — at
   // the path's own opacity (P-UI-137), or the hover would drop the user's fade.
   if(DrawIsPathSeg(name))
   {
      string pid = ""; PathIdOfName(name, pid);
      int pv = 0; color pp = clrNONE;
      PathInkGet(pid, pp, pv);
      color want = BlendColorTowardsBG(c, 100 - pv, GetCachedChartBgColor());
      if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) == want) return false;
      PathInkApply(pid, c, pv);
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
static long   s_fcmT0 = 0, s_fcmT1 = 0, s_fcmT2 = 0;
static double s_fcmP0 = 0.0, s_fcmP1 = 0.0, s_fcmP2 = 0.0;
void FillChildStampArm(const string obj)
{
   s_fcmName = "";
   if(obj == "" || ObjectFind(0, obj) < 0) return;
   if(!DrawTypeHasFillChild(DrawObjectType(obj))) return;
   if(ObjectFind(0, FillChildName(obj)) < 0) return;   // no interior: nothing follows
   s_fcmName = obj;
   s_fcmT0 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 0);
   s_fcmT1 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 1);
   s_fcmT2 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 2);
   s_fcmP0 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 0);
   s_fcmP1 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 1);
   s_fcmP2 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 2);
}
void FillChildStampRelease() { s_fcmName = ""; }
bool FillChildStamp(const string obj)
{
   if(obj == "" || obj != s_fcmName) return false;
   if(ObjectFind(0, obj) < 0) { s_fcmName = ""; return false; }
   long t0 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 0);
   long t1 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 1);
   long t2 = (long)ObjectGetInteger(0, obj, OBJPROP_TIME, 2);
   double p0 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 0);
   double p1 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 1);
   double p2 = ObjectGetDouble(0, obj, OBJPROP_PRICE, 2);
   if(t0 == s_fcmT0 && t1 == s_fcmT1 && t2 == s_fcmT2 && p0 == s_fcmP0 && p1 == s_fcmP1 && p2 == s_fcmP2) return false;
   s_fcmT0 = t0; s_fcmT1 = t1; s_fcmT2 = t2; s_fcmP0 = p0; s_fcmP1 = p1; s_fcmP2 = p2;
   return FillChildSync(obj);
}

#endif // TOOLBAR_A_MQH
