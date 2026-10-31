//+------------------------------------------------------------------+
//| HRayNodes.mqh — the ray's LOWER-TIMEFRAME KINKS (RTM zones).     |
//+------------------------------------------------------------------+
//| LAYER: drawing/domain, FULL BUILD ONLY (the entry includes it     |
//| inside its `#ifndef BUILD_LITE` block, and HRayTool's calls wear  |
//| the same fence). Lite keeps a working ray; it paints no zone.     |
//|                                                                  |
//| P-HRN-01 (2026-10-31). User: «این خط هر چی گره هستش تا تایم پایین  |
//| رو برام مشخص بکنه تا یک دقیقه» + «گره‌هایی که توی این خط تشکیل    |
//| میشه رو باید باکس بکشی براش، باکس هم فیل نداشته باشه» + the RTM   |
//| Zones page: «It draws the RTM zones those lines produce, as       |
//| rectangles, across timeframes down to M1» and «it will draw your  |
//| main kink, and all to the pip kinks your history holds».          |
//|                                                                  |
//| THE GEOMETRY (P-HRN-06 corrected the DETECTOR, not this):        |
//|   * a box's NEAR edge is the LEVEL the user dropped — not a       |
//|     tolerance band; the line runs along/inside the box;           |
//|   * its FAR edge is THAT KINK'S OWN extreme away from the level;  |
//|   * it starts at the kink's first touch and ends at the touch that |
//|     closed it (a still-running kink ends on the last bar);        |
//|   * the deepest box of a ray is the MAIN kink and wears the thick  |
//|     border; every other one is a pip kink of its own rung;         |
//|   * HOLLOW — no fill, the candles stay readable through it.       |
//|                                                                  |//| THE TWO WRONG DETECTORS THIS REPLACED, both measured on the user's|
//| own charts: P-HRN-02 asked the TH3 six-condition pivot (a TRADING   |
//| gate that is right to refuse most bars — «مال ما چیزی مشخص          |
//| نمیکنه»), and the fractal swing that followed it asked "is there a |
//| swing near the level?", which drew a thin column of M1/M5 boxes on  |
//| the far left of a monthly chart. The level does not need swings NEAR|
//| it — it needs the TOUCHES of it (P-HRN-06, see the detector).      |
//|                                                                  |
//| COST, stated (contract §5): a scan is HRAYN_MAX_TF(4) rungs x up  |
//| to HRAYN_MAX_BARS(1200) bars of iHigh/iLow reads, and it runs on  |
//| the PLACEMENT and on a drag's RELEASE — never per tick, never in  |
//| the mouse-move stream. The answer is CACHED in s_hrn[] (4 records |
//| at most per ray), so hide/show repaints cost ZERO reads. A still  |
//| chart writes nothing.                                             |
//+------------------------------------------------------------------+
#ifndef HRAY_NODES_MQH
#define HRAY_NODES_MQH

#define HRAYN_MAX_TF     4      // rungs scanned, the chart's own TF first
#define HRAYN_LOOKBACK   400    // minimum bars handed to the kink walk
#define HRAYN_MAX_BARS   1200   // ... and the hard cap (the stated cost)
#define HRAYN_TOL_PIPS   0.5    // how close a bar must come to TOUCH the level (in pips)
#define HRAYN_MIN_PIPS   3.0    // a run away from the level shallower than this is noise
#define HRAYN_PER_TF     5      // kinks kept per rung (deepest first, bounded)
#define HRAYN_SPAN_BARS  40     // a zone's width, in ITS OWN tf's bars
#define HRAYN_FONT       7      // the TF tag's size
#define HRAYN_W          1      // zone border width
#define HRAYN_INIT_RAYS  4      // rays BUILT at attach when they own no zone (bounded)
#define HRAYN_MIN_BAND   10     // a band thinner than 1 pip is widened (below)
#define HRAYN_MAX_KINKS  192    // kinks kept per rung (bounded walk)

// The ink ramp, low TF -> high TF (a warm ladder: the deeper the TF, the
// hotter the line, so a glance reads "M1 sits inside an M30 zone").
color HRayNodeInk(const int tf)
{
   if(tf <= 1)   return C'255,190,120';
   if(tf <= 5)   return C'255,160,80';
   if(tf <= 15)  return C'255,138,0';
   if(tf <= 30)  return C'230,110,0';
   if(tf <= 60)  return C'200,90,0';
   return C'170,70,0';
}
string HRayNodeTfName(const int tf)
{
   if(tf == 1)     return "M1";
   if(tf == 5)     return "M5";
   if(tf == 15)    return "M15";
   if(tf == 30)    return "M30";
   if(tf == 60)    return "H1";
   if(tf == 240)   return "H4";
   if(tf == 1440)  return "D1";
   if(tf == 10080) return "W1";
   if(tf == 43200) return "MN";
   return IntegerToString(tf);
}

struct HRayNodeRec
{
   string   ray;      // the ray LINE's own object name (the key)
   int      tf;       // the rung that owns the kink
   datetime t;        // the kink's extreme candle
   datetime tEnd;     // the zone's right edge (its swing partner, + a tail)
   double   lo;       // the zone's floor
   double   hi;       // ... and its ceiling
   bool     base;     // reserved: the base flag (not read by this detector yet)
   string   rect;     // the painted rectangle's name
   string   text;     // ... and its TF tag
};

static HRayNodeRec s_hrn[];   // the cache — painted from, never re-scanned

string HRayNodesPfx() { return HRayPrefix() + HRAY_NODES_TAG; }

string HRayNodeName(const string ray, const int tf, const datetime t, const string tail)
{
   string pfx = HRayNodesPfx();
   if(pfx == "") return "";
   string id = ray;
   string rp = HRayPrefix();
   if(rp != "" && StringFind(ray, rp) == 0) id = StringSubstr(ray, StringLen(rp));
   // one name per (ray, rung, kink) — stable across repaints, so a rebuild
   // rewrites the SAME object instead of leaving a twin behind.
   return pfx + id + "_" + IntegerToString(tf) + "_" + IntegerToString((long)t) + tail;
}

void HRayNodeDropObjects(const int i)
{
   if(i < 0 || i >= ArraySize(s_hrn)) return;
   if(s_hrn[i].rect != "") ObjectDelete(0, s_hrn[i].rect);
   if(s_hrn[i].text != "") ObjectDelete(0, s_hrn[i].text);
   s_hrn[i].rect = "";
   s_hrn[i].text = "";
}
// Wipe the PAINT of every cached kink, keep the cache (the F mute's own move:
// a rectangle cannot be period-masked — contract §2 — so hiding is EXISTENCE).
void HRayNodesUnpaint()
{
   for(int i = 0; i < ArraySize(s_hrn); i++) HRayNodeDropObjects(i);
}
// Forget one ray: its objects AND its records (a delete, not a hide).
void HRayNodesForget(const string ray)
{
   for(int i = ArraySize(s_hrn) - 1; i >= 0; i--)
   {
      if(s_hrn[i].ray != ray) continue;
      HRayNodeDropObjects(i);
      int n = ArraySize(s_hrn);
      for(int k = i; k < n - 1; k++) s_hrn[k] = s_hrn[k + 1];
      ArrayResize(s_hrn, n - 1);
   }
}
void HRayNodesForgetAll()
{
   for(int i = 0; i < ArraySize(s_hrn); i++) HRayNodeDropObjects(i);
   ArrayResize(s_hrn, 0);
}
int HRayNodesCount(const string ray)
{
   int n = 0;
   for(int i = 0; i < ArraySize(s_hrn); i++) if(s_hrn[i].ray == ray) n++;
   return n;
}
// THE BAND, one owner for the test and the paint (they must never disagree).
// lo/hi are the zone's own edges; a band thinner than HRAYN_MIN_BAND is widened
// about its middle, because a zero-height rectangle draws NOTHING — and the
// reference drawing never leaves a kink without a visible zone.
void HRayNodeBand(const double a, const double b, double &lo, double &hi)
{
   lo = MathMin(a, b);
   hi = MathMax(a, b);
   double floorPts = HRAYN_MIN_BAND * Point;
   if(hi - lo < floorPts)
   {
      double mid = (hi + lo) * 0.5;
      lo = mid - floorPts * 0.5;
      hi = mid + floorPts * 0.5;
   }
}
// Paint ONE cached kink. Hollow and BACK (the candles stay the foreground,
// exactly like the reference's own screenshots); the tag is a TEXT so the TF is
// readable without opening anything.
// P-HRN-01b: the name is DETERMINISTIC, so a repaint after a TF switch finds the
// previous instance's object still on the chart. It is MOVED and rewritten, never
// skipped (a skip would leave the old build's geometry under a new level).
void HRayNodePaint(const int i)
{
   if(i < 0 || i >= ArraySize(s_hrn)) return;
   if(s_hrn[i].rect == "") return;
   datetime t2 = (s_hrn[i].tEnd > s_hrn[i].t ? s_hrn[i].tEnd
                    : s_hrn[i].t + (datetime)(HRAYN_SPAN_BARS * s_hrn[i].tf * 60));
   if(ObjectFind(0, s_hrn[i].rect) < 0 &&
      !ObjectCreate(0, s_hrn[i].rect, OBJ_RECTANGLE, 0, s_hrn[i].t, s_hrn[i].lo, t2, s_hrn[i].hi))
      return;
   color ink = HRayNodeInk(s_hrn[i].tf);
   ObjectMove(0, s_hrn[i].rect, 0, s_hrn[i].t, s_hrn[i].lo);
   ObjectMove(0, s_hrn[i].rect, 1, t2, s_hrn[i].hi);
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_COLOR, ink);
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_STYLE, STYLE_SOLID);
   // P-HRN-06: the MAIN kink wears the thick border (the reference draws only one
   // box and calls it the main kink; here the rest are the pip kinks of the rungs).
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_WIDTH, s_hrn[i].base ? 2 : HRAYN_W);
   // P-HRN-04 (MEASURED on the user's chart: a solid block over the candles):
   // FILL false alone is NOT a hollow box — MT4 fills a rectangle that sits in
   // the BACKGROUND. The project's own rule (BaseKnot_Base.mqh:1110, P-BK-23) is
   // that a hollow box must also be FOREGROUND, and the reference's borders do
   // draw over the candles. Both properties, or it ships as a slab.
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_FILL, false);
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_BACK, false);
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_HIDDEN, true);
   ObjectSetString(0, s_hrn[i].rect, OBJPROP_TOOLTIP,
                   HRayNodeTfName(s_hrn[i].tf) + " kink zone — " +
                   DoubleToString(s_hrn[i].lo, Digits) + " / " +
                   DoubleToString(s_hrn[i].hi, Digits));
   // P-HRN-03 (MQL4 has no OBJPROP_DESCRIPTION — the record rides OBJPROP_TEXT,
// which for a non-text object IS its description): the record travels ON the object, so a fresh instance (attach /
   // TF switch) can rebuild its cache from the chart WITHOUT re-scanning. That is
   // what makes the F mute correct after a switch: hide walks the cache, and an
   // empty cache would leave every zone painted while the rest of the chart went.
   ObjectSetString(0, s_hrn[i].rect, OBJPROP_TEXT,
                   IntegerToString(s_hrn[i].tf) + "|" + DoubleToString(s_hrn[i].lo, Digits) +
                   "|" + DoubleToString(s_hrn[i].hi, Digits) + "|" +
                   IntegerToString((long)s_hrn[i].t) + "|" +
                   IntegerToString((long)s_hrn[i].tEnd));
   if(s_hrn[i].text == "") return;
   if(ObjectFind(0, s_hrn[i].text) < 0 &&
      !ObjectCreate(0, s_hrn[i].text, OBJ_TEXT, 0, s_hrn[i].t, s_hrn[i].hi))
      return;
   ObjectMove(0, s_hrn[i].text, 0, s_hrn[i].t, s_hrn[i].hi);
   ObjectSetString(0, s_hrn[i].text, OBJPROP_TEXT, HRayNodeTfName(s_hrn[i].tf));
   ObjectSetString(0, s_hrn[i].text, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, s_hrn[i].text, OBJPROP_FONTSIZE, HRAYN_FONT);
   ObjectSetInteger(0, s_hrn[i].text, OBJPROP_COLOR, ink);
   ObjectSetInteger(0, s_hrn[i].text, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, s_hrn[i].text, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, s_hrn[i].text, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, s_hrn[i].text, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, s_hrn[i].text, OBJPROP_BACK, false);
}
void HRayNodesPaintAll()
{
   if(IsIndicatorHidden()) return;   // P-UI-160b: the F mute owns the chart
   for(int i = 0; i < ArraySize(s_hrn); i++) HRayNodePaint(i);
}
void HRayNodesPaintRay(const string ray)
{
   if(IsIndicatorHidden()) return;
   for(int i = 0; i < ArraySize(s_hrn); i++) if(s_hrn[i].ray == ray) HRayNodePaint(i);
}
// The rungs this chart owes: its OWN timeframe first (the reference drawing's
// boxes ARE chart-TF kinks — the sales screenshot is a monthly chart wearing
// monthly boxes), then the ladder below it, cut at HRAYN_MAX_TF.
int HRayNodesTFs(int &tfs[])
{
   int ladder[8] = {1, 5, 15, 30, 60, 240, 1440, 43200};
   int chartTF = Period();
   int n = 0;
   ArrayResize(tfs, 1); tfs[0] = chartTF; n = 1;
   for(int i = 7; i >= 0 && n < HRAYN_MAX_TF; i--)
   {
      if(ladder[i] <= 0 || ladder[i] >= chartTF) continue;
      ArrayResize(tfs, n + 1);
      tfs[n] = ladder[i];
      n++;
   }
   return n;
}
// How many bars of `tf` the VISIBLE chart covers, clamped to the budget. A rung
// deeper than the budget reads its own most recent slice instead of nothing.
int HRayNodeBars(const int tf)
{
   int bars = HRAYN_LOOKBACK;
   int fv = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   if(fv >= 0 && fv < Bars)
   {
      long winSec = (long)Time[0] - (long)Time[fv];
      if(winSec > 0 && tf > 0)
      {
         bars = (int)(winSec / ((long)tf * 60));
         if(bars < HRAYN_LOOKBACK) bars = HRAYN_LOOKBACK;
      }
   }
   if(bars > HRAYN_MAX_BARS) bars = HRAYN_MAX_BARS;
   return bars;
}
//+------------------------------------------------------------------+
//| P-HRN-06 (2026-10-31) — A KINK IS A TOUCH AND A TURN, NOT A PIVOT |
//| THAT HAPPENS TO SIT NEAR THE LINE.                                  |
//|                                                                   |
//| «مرجع یک چیز دیگه، منطقش اشتباه هستش». The reference states its own |
//| rule on the image: «Drag and drop the line (ideally to LS or SR, of |
//| course), and it will draw your main kink, and all to the pip kinks  |
//| your history holds.» So the zones are produced BY THE LINE: every   |
//| place price TOUCHED that level and turned away is a kink, the       |
//| deepest one is the MAIN kink, and the shallow ones are the pip      |
//| kinks.                                                             |
//|                                                                   |
//| The detector this replaces asked a different question — "is there a |
//| fractal swing ANYWHERE within half an ATR of the level?" — which is |
//| why the user's EURUSD monthly chart drew a thin cluster of boxes on |
//| the far left (the only swings that happened to sit inside an ATR)   |
//| and nothing at the kinks themselves.                                |
//|                                                                   |
//| THE ALGORITHM, one pass per rung over the window the chart covers:  |
//|   * a bar TOUCHES the level when  low <= P + tol  &&  high >= P - tol;
//|   * between two touches, the run's excursion away from P is the      |
//|     kink's DEPTH, and its extreme is the zone's FAR edge (P is the  |
//|     near edge — the line runs along the box, as in the reference);  |
//|   * the zone spans [first touch .. the touch that closes it] in     |
//|     time, [P .. extreme] in price;                                  |
//|   * a run still open at the last bar closes THERE (the reference     |
//|     keeps its live zone current, it does not hide it);              |
//|   * a run shallower than HRAYN_MIN_PIPS is noise, not a kink.       |
//| Cost: the same walk the fractal version paid — one bar pass per rung.|
//+------------------------------------------------------------------+
int HRayNodeKinksAtLevel(const int tf, const int depth, const double P, const double tol,
                         const double minDepth,
                         datetime &ks[], datetime &ke[], double &kfar[], double &kdepth[])
{
   int cnt = 0;
   bool open = false;
   datetime oStart = 0;
   double oFar = 0.0;      // the run's extreme price (the far edge once it closes)
   double oRun = 0.0;      // ... and its distance from the level
   datetime lastT = 0;
   for(int i = depth; i >= 1; i--)        // OLDEST .. NEWEST (i = bar index)
   {
      double h = iHigh(NULL, tf, i), l = iLow(NULL, tf, i);
      if(h <= 0.0 || l <= 0.0) continue;
      datetime bt = iTime(NULL, tf, i);
      if(bt <= 0) continue;
      lastT = bt;
      bool touch = (l <= P + tol && h >= P - tol);
      if(!open)
      {
         if(!touch) continue;              // price has not reached the level yet
         open = true; oStart = bt; oFar = P; oRun = 0.0;
         continue;
      }
      // the run grows AWAY from the level — either side is a kink (support or
      // resistance), and the deeper side of the bar is the one that counts
      double up = h - P, dn = P - l;
      if(up > oRun) { oRun = up; oFar = h; }
      if(dn > oRun) { oRun = dn; oFar = l; }
      if(!touch) continue;
      // the level was touched again: the run between the two touches is a kink
      if(oRun >= minDepth && cnt < HRAYN_MAX_KINKS)
      {
         ArrayResize(ks, cnt + 1); ArrayResize(ke, cnt + 1);
         ArrayResize(kfar, cnt + 1); ArrayResize(kdepth, cnt + 1);
         ks[cnt] = oStart;
         ke[cnt] = bt;
         kfar[cnt] = oFar;
         kdepth[cnt] = oRun;
         cnt++;
      }
      // and THIS bar opens the next run — the level is being touched again
      open = true; oStart = bt; oFar = P; oRun = 0.0;
   }
   // a run still open at the last bar is the LIVE kink: close it there
   if(open && oRun >= minDepth && cnt < HRAYN_MAX_KINKS)
   {
      ArrayResize(ks, cnt + 1); ArrayResize(ke, cnt + 1);
      ArrayResize(kfar, cnt + 1); ArrayResize(kdepth, cnt + 1);
      ks[cnt] = oStart;
      ke[cnt] = (lastT > oStart ? lastT : oStart);
      kfar[cnt] = oFar;
      kdepth[cnt] = oRun;
      cnt++;
   }
   return cnt;
}
// P-HRN-06: the MAIN kink is the deepest one of each ray — the reference draws it
// first and calls it that. One pass over the cache (<= ~20 records), so the paint
// can read a single flag instead of comparing every box on every frame.
void HRayNodesMarkMain()
{
   int n = ArraySize(s_hrn);
   for(int i = 0; i < n; i++) s_hrn[i].base = false;
   for(int i = 0; i < n; i++)
   {
      int best = i;
      for(int k = 0; k < n; k++)
      {
         if(s_hrn[k].ray != s_hrn[i].ray) continue;
         if(MathAbs(s_hrn[k].hi - s_hrn[k].lo) <= MathAbs(s_hrn[best].hi - s_hrn[best].lo)) continue;
         best = k;
      }
      if(best == i) s_hrn[i].base = true;
   }
}
// THE SCAN — one box per KINK, built the way the reference draws it:
//   near edge = THE LEVEL the user dropped (the line runs along the box), and
//   far edge  = that kink's own extreme away from the level.
// Every rung on the ladder answers the SAME question of its own history, so the
// chart ends up wearing the main kink (the deepest) plus the pip kinks each rung
// holds — down to M1, which is the whole reason the box is drawn at all: the user
// must not have to switch the chart to a lower timeframe to see them.
// P-HRN-06: the deepest of each ray is flagged `base` (HRayNodesMarkMain) and the
// paint gives it the thick border — the reference's "main kink".
void HRayNodesScan(const string ray)
{
   HRayNodesForget(ray);                       // one ray, one answer set
   if(IsIndicatorHidden()) return;
   if(ObjectFind(0, ray) < 0) return;
   double P = ObjectGetDouble(0, ray, OBJPROP_PRICE, 0);
   if(!(P > 0)) return;
   int tfs[];
   int nt = HRayNodesTFs(tfs);
   // P-HRN-06: the level is a PRICE the user dropped; "touching" it is measured in
   // PIPS (a chart-independent unit), and the same pip decides what is noise.
   double pip = Point * (((Digits == 3 || Digits == 5) ? 10 : 1));
   double tol = pip * HRAYN_TOL_PIPS;
   double minDepth = pip * HRAYN_MIN_PIPS;
   int found = 0;
   string ledger = "";
   uint t0 = GetTickCount();   // the scan's own cost, printed below (contract §5)
   for(int i = 0; i < nt; i++)
   {
      int tf = tfs[i];
      int depth = HRayNodeBars(tf);
      int have = iBars(NULL, tf);
      if(depth > have - 2) depth = have - 2;
      if(depth < 10) { ledger = ledger + " " + HRayNodeTfName(tf) + ":cold"; continue; }
      datetime ks[], ke[];
      double kfar[], kd[];
      int n = HRayNodeKinksAtLevel(tf, depth, P, tol, minDepth, ks, ke, kfar, kd);
      ledger = ledger + " " + HRayNodeTfName(tf) + ":" + IntegerToString(depth) + "b/" +
               IntegerToString(n) + "k";
      // KEEP THE DEEPEST HRAYN_PER_TF of this rung — a selection, not a sort, so the
      // cost is n * HRAYN_PER_TF compares over numbers already in RAM (zero reads).
      for(int take = 0; take < HRAYN_PER_TF; take++)
      {
         int best = -1;
         double bestD = 0.0;
         for(int k = 0; k < n; k++)
         {
            if(kd[k] <= 0.0) continue;          // already spent
            if(kd[k] > bestD) { bestD = kd[k]; best = k; }
         }
         if(best < 0) break;
         int r = ArraySize(s_hrn);
         ArrayResize(s_hrn, r + 1);
         s_hrn[r].ray  = ray;
         s_hrn[r].tf   = tf;
         s_hrn[r].t    = ks[best];                                    // the FIRST touch
         datetime tEnd = ke[best];
         if(tEnd <= ks[best]) tEnd = ks[best] + (datetime)(tf * 60);   // a visible width
         s_hrn[r].tEnd = tEnd;                                        // the closing touch
         HRayNodeBand(P, kfar[best], s_hrn[r].lo, s_hrn[r].hi);        // near edge = the LEVEL
         s_hrn[r].base = false;
         s_hrn[r].rect = HRayNodeName(ray, tf, ks[best], "R");
         s_hrn[r].text = HRayNodeName(ray, tf, ks[best], "T");
         found++;
         kd[best] = 0.0;                       // spend it, so the next take is deeper
      }
   }
   HRayNodesMarkMain();   // P-HRN-06: the deepest box of this ray is the MAIN kink
   HRayNodesPaintRay(ray);
   double mainPips = 0.0;
   for(int i = 0; i < ArraySize(s_hrn); i++)
   {
      if(s_hrn[i].ray != ray || !s_hrn[i].base) continue;
      mainPips = (s_hrn[i].hi - s_hrn[i].lo) / pip;
      break;
   }
   HRayWitness("nodes \"" + ray + "\" level=" + DoubleToString(P, Digits) +
               " rungs=" + IntegerToString(nt) + " boxes=" + IntegerToString(found) +
               " main=" + DoubleToString(mainPips, 1) + "p" +
               " ms=" + IntegerToString((int)(GetTickCount() - t0)) + " |" + ledger);
}
// P-HRN-03 — ADOPT WHAT THE CHART STILL WEARS. A TF switch is a deinit + init on
// MT4: the statics die, the objects survive. Walking the object list once and
// reading each rectangle's own DESCRIPTION rebuilds the cache at ZERO scan cost,
// so the mute, the delete sweep and the show path all keep working on the new
// instance. Bounded: one ObjectsTotal walk per attach.
void HRayNodesAdopt()
{
   string pfx = HRayNodesPfx();
   if(pfx == "") return;
   string rp = HRayPrefix();
   int total = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < total; i++)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, pfx) != 0) continue;
      int l = StringLen(nm);
      if(l < 2 || StringSubstr(nm, l - 1) != "R") continue;   // rectangles only
      string desc = ObjectGetString(0, nm, OBJPROP_TEXT);
      string f[];
      if(StringSplit(desc, '|', f) < 4) continue;
      int r = ArraySize(s_hrn);
      ArrayResize(s_hrn, r + 1);
      s_hrn[r].tf   = (int)StringToInteger(f[0]);
      s_hrn[r].lo   = StringToDouble(f[1]);
      s_hrn[r].hi   = StringToDouble(f[2]);
      s_hrn[r].t    = (datetime)StringToInteger(f[3]);
      s_hrn[r].tEnd = (ArraySize(f) > 4 ? (datetime)StringToInteger(f[4]) : 0);
      s_hrn[r].base = false;
      s_hrn[r].rect = nm;
      s_hrn[r].text = StringSubstr(nm, 0, l - 1) + "T";
      // the ray is the name between the prefix and "_<tf>_<time>"
      string body = StringSubstr(nm, StringLen(pfx));
      int cut = StringLen(body) - (StringLen(IntegerToString(s_hrn[r].tf)) +
                                   StringLen(IntegerToString((long)s_hrn[r].t)) + 3);
      s_hrn[r].ray = (cut > 0 ? rp + StringSubstr(body, 0, cut) : "");
   }
   HRayNodesMarkMain();   // P-HRN-06: the adopted set gets its main kink back too
}
// Attach: adopt what the chart still wears (free), then build the rays that own
// nothing — a ray placed by an OLDER build has no zones at all, and without this
// it would stay empty until the user dragged it. Bounded: HRAYN_INIT_RAYS rays.
void HRayNodesAdoptAndFill()
{
   HRayNodesAdopt();
   int built = 0;
   for(int i = 0; i < ArraySize(s_hrayIds) && built < HRAYN_INIT_RAYS; i++)
   {
      string ln = HRayLineName(s_hrayIds[i]);
      if(HRayNodesCount(ln) > 0) continue;
      HRayNodesScan(ln);
      built++;
   }
}
// The F mute's show path — cache only, zero reads.
void HRayNodesShowAll() { HRayNodesPaintAll(); }
void HRayNodesHideAll() { HRayNodesUnpaint(); }
#endif // HRAY_NODES_MQH
