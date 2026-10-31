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
//| THE GEOMETRY, measured off the reference drawing (2560x1234, its  |
//| own price axis ~0.00068/px):                                     |
//|   * a box's NEAR edge is the LEVEL the user dropped — not a       |
//|     tolerance band; the line runs along/inside the box;           |
//|   * its FAR edge is the next kink level that rung's history holds |
//|     (that is why the reference's two boxes share one bottom: both |
//|     end on the same next kink);                                   |
//|   * the box starts at the kink's own candle and runs right for a  |
//|     bounded span (40 bars of ITS timeframe — a monthly box is ~3  |
//|     years, exactly the reference's width);                        |
//|   * HOLLOW — no fill, the candles stay readable through it.       |
//|                                                                  |
//| P-HRN-02 (2026-10-31, MEASURED): the first build asked the TH3    |
//| six-condition pivot (TH3SixPivotsScanTF) for the kink, and the    |
//| user's EURUSD monthly chart drew NOTHING — «مال ما چیزی مشخص       |
//| نمیکنه». That detector is a TRADING gate (master candle + cover + |
//| final-third close + 0.8 ATR reversal, TH3Pivots_A.mqh:133), not a |
//| drawing primitive: it is right to refuse most bars, and a chart   |
//| that must show EVERY kink cannot be built on a filter that says   |
//| no. The kink is now the swing extreme itself (HRAYN_FRACTAL bars  |
//| each side), which is also what the reference calls a kink.        |
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
#define HRAYN_FRACTAL    2      // bars each side that make a swing extreme
#define HRAYN_TOL_ATR    0.5    // "the level is ON the kink": share of that TF's ATR
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
   ObjectSetInteger(0, s_hrn[i].rect, OBJPROP_WIDTH, HRAYN_W);
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
// THE KINKS of one rung: swing extremes on COMPLETED bars only. A bar is a kink
// high when its high is the highest of HRAYN_FRACTAL bars on each side (strictly
// on the right, so a plateau counts once). Bounded by HRAYN_MAX_KINKS.
int HRayNodeKinks(const int tf, const int bars,
                  datetime &kt[], double &kp[], bool &kh[])
{
   int have = iBars(NULL, tf);
   if(have < (2 * HRAYN_FRACTAL + 3)) return 0;
   int depth = bars;
   if(depth > have - HRAYN_FRACTAL - 1) depth = have - HRAYN_FRACTAL - 1;
   if(depth < HRAYN_FRACTAL + 2) return 0;
   int cnt = 0;
   for(int i = HRAYN_FRACTAL + 1; i <= depth; i++)
   {
      double h = iHigh(NULL, tf, i), l = iLow(NULL, tf, i);
      if(h <= 0 || l <= 0) continue;
      bool isHi = true, isLo = true;
      for(int k = 1; k <= HRAYN_FRACTAL; k++)
      {
         double hb = iHigh(NULL, tf, i - k), hf = iHigh(NULL, tf, i + k);
         double lb = iLow(NULL, tf, i - k),  lf = iLow(NULL, tf, i + k);
         if(!(h >= hb && h > hf)) isHi = false;
         if(!(l <= lb && l < lf)) isLo = false;
         if(!isHi && !isLo) break;
      }
      if(!isHi && !isLo) continue;
      ArrayResize(kt, cnt + 1); ArrayResize(kp, cnt + 1); ArrayResize(kh, cnt + 1);
      kt[cnt] = iTime(NULL, tf, i);
      kp[cnt] = (isHi ? h : l);
      kh[cnt] = isHi;
      cnt++;
      if(cnt >= HRAYN_MAX_KINKS) break;
   }
   return cnt;
}
// THE SCAN — ONE box per rung, built the way the reference draws it:
//   near edge = THE LEVEL the user dropped, and
//   far edge  = the next kink level the same rung's history holds below it
//               (above it, for a kink under the level).
// That is why the reference's two boxes share one bottom: both end on the same
// next kink. A rung whose history has no kink at the level draws nothing.
void HRayNodesScan(const string ray)
{
   HRayNodesForget(ray);                       // one ray, one answer set
   if(IsIndicatorHidden()) return;
   if(ObjectFind(0, ray) < 0) return;
   double P = ObjectGetDouble(0, ray, OBJPROP_PRICE, 0);
   if(!(P > 0)) return;
   int tfs[];
   int nt = HRayNodesTFs(tfs);
   int found = 0;
   string ledger = "";
   uint t0 = GetTickCount();   // the scan's own cost, printed below (contract §5)
   for(int i = 0; i < nt; i++)
   {
      int tf = tfs[i];
      int bars = HRayNodeBars(tf);
      datetime kt[]; double kp[]; bool kh[];
      int n = HRayNodeKinks(tf, bars, kt, kp, kh);
      double atr = iATR(NULL, tf, 14, 1);
      double tol = (atr > 0 ? HRAYN_TOL_ATR * atr : 0.0);
      int hit = 0;
      for(int k = 0; k < n; k++) if(MathAbs(kp[k] - P) <= tol) hit++;
      ledger = ledger + " " + HRayNodeTfName(tf) + ":" + IntegerToString(bars) + "b/" +
               IntegerToString(n) + "k/" + IntegerToString(hit) + "h";
      // THE nearest kink at the level, one per rung
      int best = -1;
      double bestD = 0;
      for(int k = 0; k < n; k++)
      {
         double d = MathAbs(kp[k] - P);
         if(d > tol) continue;
         if(best < 0 || d < bestD) { best = k; bestD = d; }
      }
      if(best < 0) continue;
      // THE far edge = THE SWING'S PARTNER: the next kink IN TIME that turns the
      // other way. P-HRN-05 (the user: «اون پایینی ... ولی برای ما چی مشخص کرده»):
      // the price-nearest rule produced a 400-pip sliver where the reference draws
      // the whole swing (its 2008 high box runs to the 2009 low). Kinks are stored
      // newest-first, so "later in time" is a LOWER index.
      double far = 0;
      datetime tFar = 0;
      for(int j = best - 1; j >= 0; j--)
      {
         if(kh[j] == kh[best]) continue;   // same direction — keep walking
         far  = kp[j];
         tFar = kt[j];
         break;
      }
      if(far == 0)   // no partner in the window: fall back to the nearest level
      {
         for(int j = 0; j < n; j++)
         {
            if(j == best) continue;
            if(kh[best]) { if(kp[j] < P && (far == 0 || kp[j] > far)) far = kp[j]; }
            else         { if(kp[j] > P && (far == 0 || kp[j] < far)) far = kp[j]; }
         }
      }
      if(far == 0) continue;
      int r = ArraySize(s_hrn);
      ArrayResize(s_hrn, r + 1);
      s_hrn[r].ray  = ray;
      s_hrn[r].tf   = tf;
      s_hrn[r].t    = kt[best];
      s_hrn[r].tEnd = (tFar > 0 ? tFar + (datetime)(10 * tf * 60)
                                : kt[best] + (datetime)(HRAYN_SPAN_BARS * tf * 60));
      HRayNodeBand(P, far, s_hrn[r].lo, s_hrn[r].hi);
      s_hrn[r].base = false;
      s_hrn[r].rect = HRayNodeName(ray, tf, kt[best], "R");
      s_hrn[r].text = HRayNodeName(ray, tf, kt[best], "T");
      found++;
   }
   HRayNodesPaintRay(ray);
   HRayWitness("nodes \"" + ray + "\" level=" + DoubleToString(P, Digits) +
               " rungs=" + IntegerToString(nt) + " boxes=" + IntegerToString(found) +
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
