// Toolbar_Hit.mqh - the PICK owner, split out of Toolbar_A.mqh on 2026-10-19 by
// P-SIZE-1500 (1526 lines, ceiling 1500). Moved verbatim: lines 524-751 of the
// pre-split file. "Which drawing is under the cursor?" is one owner: the measured
// hit tests, the terminal's own selected-object answer, and the shape-by-shape walk.
// It asks Toolbar_A (included above it in DrawToolbar.mqh) for the kind, the anchors
// and the segment distance - never the other way round.
#ifndef TOOLBAR_HIT_MQH
#define TOOLBAR_HIT_MQH
bool DrawHitLevels(const string name, const int px, const int py)
{
   int n = DrawLevelCount(name);
   if(n <= 0) return false;
   datetime t1 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
   double   p1 = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   double   p2 = ObjectGetDouble(0, name, OBJPROP_PRICE, 1);
   if(t1 <= 0 || !(p1 > 0.0) || !(p2 > 0.0)) return false;
   //--- P-UNIFY-3: the level's TWO ends are the kind's own geometry. The three-anchor
   //--- kinds (channel, expansion) read the third anchor here; every other family
   //--- answers the horizontal law it always did.
   EDrawKind k = DrawKindOf(name);
   bool three = (k == DK_FIBOCHAN || k == DK_EXPANSION);
   datetime t3 = three ? (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 2) : 0;
   double   p3 = three ? ObjectGetDouble(0, name, OBJPROP_PRICE, 2) : 0.0;
   if(three && (t3 <= 0 || !(p3 > 0.0))) return false;
   // the level lines of a plain fibo run from t1 to t2 at their own price; the
   // fan's run from the FIRST anchor's time to the second's, so the x span is
   // the same pair for both and only the y differs — measured from the object.
   int xa = 0, ya = 0, xb = 0, yb = 0;
   for(int k1 = 0; k1 < n; k1++)
   {
      double v = DrawLevelValue(name, k1);
      if(!MathIsValidNumber(v)) continue;
      double la = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t1);
      double lb = DrawLevelPriceAt(k, v, t1, p1, t2, p2, t3, p3, t2);
      if(!(la > 0.0) || !(lb > 0.0)) continue;
      if(!ChartTimePriceToXY(0, 0, t1, la, xa, ya)) continue;
      if(!ChartTimePriceToXY(0, 0, t2, lb, xb, yb)) continue;
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
      case DK_TANGLE:   // P-UNIFY-2: the same drawn shape as a trend — one segment
      {
         if(!DrawAnchorXY(name, 0, x1, y1)) return false;
         if(!DrawAnchorXY(name, 1, x2, y2)) return false;
         bool oA = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_LEFT) != 0);
         bool oB = ((int)ObjectGetInteger(0, name, OBJPROP_RAY_RIGHT) != 0);
         return (DrawSegDist(px, py, x1, y1, x2, y2, oA, oB) <= (double)tol);
      }
      //--- P-UNIFY-2: a cycles object draws a fan of VERTICALS at t1 + k*P, P = |t2-t1|.
      //--- The pick asks the terminal where the cursor's own period stands and probes it
      //--- and its two neighbours — three time->x conversions, never a chart-wide sweep,
      //--- and the answer is the drawn position in PIXELS (weekend gaps included, which
      //--- a pixel-modulo would get wrong).
      case DK_CYCLES:
      {
         datetime ta = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         datetime tb = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 1);
         double pa = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
         if(ta <= 0 || tb <= 0 || !(pa > 0.0)) return false;
         if(!DrawAnchorXY(name, 0, x1, y1)) return false;
         long per = (long)tb - (long)ta;
         if(per == 0) return (MathAbs(px - x1) <= tol);
         if(per < 0) per = -per;
         int sub = 0; datetime tc = 0; double pc = 0.0;
         if(!ChartXYToTimePrice(0, px, py, sub, tc, pc)) return false;
         long d = ((long)tc - (long)ta) / per;
         for(int ci = -1; ci <= 1; ci++)
         {
            int vx = 0, vy = 0;
            if(!ChartTimePriceToXY(0, 0, (datetime)((long)ta + (d + ci) * per), pa, vx, vy)) continue;
            if(MathAbs(px - vx) <= tol) return true;
         }
         return false;
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

#endif // TOOLBAR_HIT_MQH
