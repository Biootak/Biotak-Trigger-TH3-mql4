//+------------------------------------------------------------------+
//|                                              BaseKnotTool.mqh    |
//|        Base / Knot Measurement Tool — TradingView-style two-click |
//|        base-box drawer with Entry / SL / TP projections.          |
//+------------------------------------------------------------------+
//| LAYER: drawing/domain (no UI deps — compiles in Full AND Lite).   |
//| The Tools-ring button, menu hide/restore and chart-lock watchdog  |
//| hooks live on the UI side (BiotakMenu/BiotakPanels) and call into |
//| this module. Chart scroll is locked directly here (raw Chart*      |
//| calls) so Lite — which has no menu — keeps drag/delete working.   |
//|                                                                   |
//| STATE MACHINE (the ONLY mouse-event consumer while active):       |
//|   NATIVE DRAG (like MT4's own rectangle): press → corner 1,        |
//|   hold + move → live rubber-band + Entry/SL/TP, release → commit.  |
//|   TAP-TAP (TradingView-style): click 1 → corner 1, move (hover      |
//|   preview), click 2 → commit. Single-shot: commit → BK_IDLE.       |
//|   (ESC / right-click / orb → IDLE).                                 |
//| While BK_ARMED/BK_PREVIEW, BaseKnotOnChartEvent() returns true for |
//| consumed events so OnChartEventHandler returns early and nothing   |
//| else (custom-price, TH3, panels) sees the gesture.                 |
//|                                                                   |
//| PRODUCT RULES (2026-09-06 — no Buy/Sell button, fully automatic;     |
//|  2026-09-08 — frozen dir went LIVE: it follows the price, see below):  |
//|  * Direction is decided at commit, then FOLLOWS the live price — a    |
//|    box below it = demand = Buy (Entry=top, SL=bottom, TP=top+2R); a   |
//|    box above it = supply = Sell (mirrored). The BOX ITSELF is the     |
//|    hysteresis band: outside takes that side, inside keeps the current |
//|    one, so a price vibrating inside the box can never flicker the     |
//|    lines (the reason the dir was frozen before P-BK-13). Flips run in |
//|    the 500 ms pump (BaseKnotSyncBadges, Full + Lite) and instantly on |
//|    drag-release, and persist to the chart-scoped GV. A commit landing |
//|    with the price INSIDE the box resolves by entry side: the most    |
//|    recent close outside the box decides (from below → Buy, from    |
//|    above → Sell), mid-vs-price only as the last fallback.          |
//|  * Multi-instance: box ids are "<commitTFmin>_<tick>" (+ rand on   |
//|    collision), so any number of knots coexist; tails are split at  |
//|    the LAST underscore because ids themselves contain one.         |
//|  * TF-scoped visibility: each box carries its commit-TF mask and   |
//|    shows on that TF and lower ones only — a low-TF knot never      |
//|    collapses into a hairline on a much higher TF.                  |
//|  * BKMAGNET-OFF: NO magnet — click = corner, exactly like MT4's own |
//|    rectangle (snapping pulled corners to candle shadows).           |
//|  * Info label: chart-anchored "[H Pips | R:R 1:N]" — Auto (default)  |
//|    shows it live while sizing + 4 s after commit, then hides it so  |
//|    the chart stays clean (Base Box card INFO row pins it on); full  |
//|    numbers always ride the box/edge hover tooltips. Entry/SL/TP    |
//|    are OBJ_TREND rays (RAY_RIGHT) anchored at the box right edge,   |
//|    BACK + unselectable.                                             |
//|  * Chain cleanup: deleting the BOX wipes every child in one        |
//|    ObjectsDeleteAll(prefix) call; deleting a CHILD self-heals it   |
//|    via BaseKnotSync. The BK layer is independent: HideAllTHObjects,|
//|    the L/F toggles, DeleteAllIndicatorObjects (non-deep), the      |
//|    emergency + incremental cleanups and the generic OBJECT_DELETE   |
//|    redraw trigger all skip "_BK_" names (see P-BK-01).              |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_TOOL_MQH
#define BASE_KNOT_TOOL_MQH
#property strict

//--- session states
#define BK_IDLE    0
#define BK_ARMED   1   // menu hidden, waiting for the first corner click
#define BK_PREVIEW 2   // first corner set, rubber-band follows the cursor

//--- geometry / UX tuning
#define BK_TP_R_MULT      2.0    // TP distance = 2R (R = box height)
#define BK_ARM_GUARD      500    // ms — ignore the arming click's own release (CLICK fallback path)
#define BK_BADGE_W        46   // NOBKDEL: retired with the X badge (kept for one-line restore)
#define BK_BADGE_H        18   // NOBKDEL: retired with the X badge (kept for one-line restore)
#define BK_DIR_LOOKBACK   128   // bars scanned for the entry-side resolve
#define BK_INFO_GRACE_MS  4000  // Auto INFO: label stays this long after commit, then hides (chart stays clean)

//--- object-name tag: "<prefix>_BK_<id>_<KIND>"
#define BK_TAG "_BK_"

//--- committed-box registry (parent ↔ children share one id prefix)
struct BaseKnotBox
{
   string id;      // "<commitTFmin>_<tick>[rNNN]" (legacy: bare tick)
   int    dir;     // +1 Buy / -1 Sell — decided at commit, then follows the live price (P-BK-13)
   int    tfMin;   // chart Period() minutes at commit (0 = legacy = all TFs)
   uint   commitMs; // GetTickCount at commit — drives the Auto INFO grace (0 = long ago)
   bool   locked;  // mini LOCK row — locked boxes are unselectable (no drag)
};
static BaseKnotBox g_bkBoxes[];
static int         g_bkState      = BK_IDLE;
static datetime    g_bkT1         = 0;
static double      g_bkP1         = 0.0;
static uint        g_bkArmedMs    = 0;
static bool        g_bkLeftPrev   = false;
static bool        g_bkHeld       = false;   // left button held down inside our gesture (press without release yet)
static datetime    g_bkLiveT      = 0;       // last rubber-band cursor point (off-chart release fallback)
static double      g_bkLiveP      = 0.0;
static bool        g_bkInitDone   = false;
//--- IDLE box-drag follow (unified lean follow, P-BK-07): the press latches
//--- the drag candidate + its anchors; per-step moves go through
//--- BaseKnotFollowDrag ONLY — anchor-exact while the terminal moves the BOX
//--- anchors, cursor-delta fallback while they are frozen mid-drag (some
//--- builds); release re-syncs authoritatively. The two event channels
//--- (per-step OBJECT_DRAG + MOUSE_MOVE) share the one follow + paint budget,
//--- so they never fight over children positions.
static string      s_bkDragId = "";
static datetime    s_bkDragT0 = 0;
static double      s_bkDragP0 = 0.0;
static int         s_bkDragX0 = 0;
static int         s_bkDragY0 = 0;
static datetime    s_bkDragBT1 = 0;
static datetime    s_bkDragBT2 = 0;
static double      s_bkDragBP1 = 0.0;
static double      s_bkDragBP2 = 0.0;
static bool        s_bkDragMoved = false;
static uint        s_bkDragMs = 0;        // single follow budget: moves + paint (30ms)
static uint        s_bkDragPaintMs = 0;   // shared drag-paint budget (all painters)
static uint        s_bkDragActMs = 0;     // last drag activity — the stuck-lock watchdog (below) only fires when silent
static datetime    s_bkFolT1 = 0;         // last-followed BOX anchors — anchor-exact
static datetime    s_bkFolT2 = 0;         // source wins while the terminal moves them
static double      s_bkFolP1 = 0.0;
static double      s_bkFolP2 = 0.0;
// Press slop for drag-vs-hold/tap (mirrors the UI BK_HOLD_MOVE/BK_CLICK_SLOP
// language; defined HERE because Lite compiles this module without Panels).
#define BK_DRAG_SLOP 8
static bool        g_bkRestoreReq = false;  // UI side: re-show the menu once
static bool        g_bkTouched    = false;  // Arm ran → OnDeinit must restore chart props
static bool        g_bkScrollWas  = true;
static bool        g_bkCtxWas     = true;
static bool        g_bkAutoWas    = true;    // CHART_AUTOSCROLL before a gesture (ticks slide the view mid-drag)
static bool        s_bkChartLocked = false;  // a gesture currently holds the chart props below
static bool        s_bkDragLock    = false;  // holder is the IDLE box-drag (not the draw session)

//+------------------------------------------------------------------+
//| Naming: every structure shares ONE id — parent/child by suffix.  |
//| Dragging/deleting the BOX cascades to its ENTRY/SL/TP/badges.     |
//+------------------------------------------------------------------+
string BaseKnotPrefix(const string id)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + id + "_";
}
string BaseKnotBoxName(const string pfx)   { return pfx + "BOX"; }
string BaseKnotEntryName(const string pfx) { return pfx + "ENTRY"; }
string BaseKnotSLName(const string pfx)    { return pfx + "SL"; }
string BaseKnotTPName(const string pfx)    { return pfx + "TP"; }
string BaseKnotBuyName(const string pfx)   { return pfx + "BUY"; }
string BaseKnotDelName(const string pfx)   { return pfx + "DEL"; }
string BaseKnotInfoName(const string pfx)  { return pfx + "INFO"; }
// User TEXT (TV-parity 2026-09-07, Text tab): one OBJ_TEXT child per box,
// content edited via the full card's edit field. Lives in the chart object
// itself (no GV — strings don't fit doubles); delete = clear (Sync never
// resurrects a deleted TEXT, it only moves/restyles an existing one).
string BaseKnotTextName(const string pfx)  { return pfx + "TEXT"; }
string BaseKnotGetText(const string pfx)
{
   string tn = BaseKnotTextName(pfx);
   if(ObjectFind(0, tn) < 0) return "";
   return ObjectGetString(0, tn, OBJPROP_TEXT);
}
void BaseKnotSetText(const string id, const string txt)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string tn = BaseKnotTextName(pfx);
   string t = txt;
   StringTrimLeft(t); StringTrimRight(t);
   if(StringLen(t) == 0) { ObjectDelete(0, tn); ChartRedraw(); return; }   // empty = clear
   if(ObjectFind(0, tn) < 0)
   {
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) < 0) return;
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      double top = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      if(!ObjectCreate(0, tn, OBJ_TEXT, 0, t2, top)) return;
   }
   ObjectSetString(0, tn, OBJPROP_TEXT, t);
   BaseKnotSync(id);   // placement + font follow the box + mirrors
   ChartRedraw();
}
// Text anchor geometry — single source of truth for PlaceText (full restyle)
// and the drag mover below (position only). TV Text-tab alignment: horizontal
// (Left|Center|Right) picks the corner, vertical (Top|Inside/Bottom) picks
// above / inside-top / below the box (TV default Inside).
void BaseKnotTextPlace(const datetime t1, const datetime t2,
                       const double top, const double bot,
                       datetime &tx, double &px, int &anchor)
{
   int al = ClampSettingInt(g_bkAlign, 0, 2);
   int va = ClampSettingInt(g_bkVAlign, 0, 2);
   tx = (al == 0 ? t1 : (al == 1 ? t1 + (t2 - t1) / 2 : t2));
   px = top;
   anchor = ANCHOR_UPPER;
   if(va == 0)         // Top — text sits ABOVE the box top edge
      anchor = (al == 0 ? ANCHOR_LEFT_LOWER : (al == 1 ? ANCHOR_LOWER : ANCHOR_RIGHT_LOWER));
   else if(va == 2)    // Bottom — text sits BELOW the box bottom edge
   {
      px = bot;
      anchor = (al == 0 ? ANCHOR_LEFT_UPPER : (al == 1 ? ANCHOR_UPPER : ANCHOR_RIGHT_UPPER));
   }
   else                // Inside — text hangs from the box top edge
      anchor = (al == 0 ? ANCHOR_LEFT_UPPER : (al == 1 ? ANCHOR_UPPER : ANCHOR_RIGHT_UPPER));
}
// (Re)place + restyle an EXISTING text object (geometry via BaseKnotTextPlace).
void BaseKnotPlaceText(const string pfx, const datetime t1, const datetime t2,
                       const double top, const double bot, const long tfMask, const string tip)
{
   string tn = BaseKnotTextName(pfx);
   if(ObjectFind(0, tn) < 0) return;   // no text — never resurrect (delete = clear)
   datetime tx; double px; int anchor;
   BaseKnotTextPlace(t1, t2, top, bot, tx, px, anchor);
   ObjectSetInteger(0, tn, OBJPROP_TIME, 0, tx);
   ObjectSetDouble(0, tn, OBJPROP_PRICE, 0, px);
   ObjectSetString(0, tn, OBJPROP_FONT, BKTextFont());
   ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, ClampSettingInt(g_bkTextSize, 8, 24));
   ObjectSetInteger(0, tn, OBJPROP_COLOR, GetBKTextRenderColor());
   ObjectSetInteger(0, tn, OBJPROP_ANCHOR, anchor);
   if(StringLen(tip) > 0) ObjectSetString(0, tn, OBJPROP_TOOLTIP, tip);   // hover = full numbers, like box/edges
   ObjectSetInteger(0, tn, OBJPROP_BACK, false);
   ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, tn, OBJPROP_ZORDER, 61);
   ObjectSetInteger(0, tn, OBJPROP_TIMEFRAMES, tfMask);
}
// Short TF name for tooltips / visibility info ("M5 and lower").
string BaseKnotTFName(const int tfMin)
{
   if(tfMin <= 0) return "all TFs";
   if(tfMin == 1) return "M1"; if(tfMin == 5) return "M5";
   if(tfMin == 15) return "M15"; if(tfMin == 30) return "M30";
   if(tfMin == 60) return "H1"; if(tfMin == 240) return "H4";
   if(tfMin == 1440) return "D1"; if(tfMin == 10080) return "W1";
   if(tfMin == 43200) return "MN1";
   return IntegerToString(tfMin) + "m";
}
// ONE live tooltip language for box + edges (TV Coordinates/Visibility tabs
// live here in MT4: drag edits coords natively, visibility is automatic).
// Coords · TF-scope · user text · risk numbers — nothing unreachable.
string BaseKnotBoxTooltip(const string id, const datetime t1, const datetime t2,
                          const double top, const double bot, const string side,
                          const double hPips, const double rr)
{
   int k = BaseKnotFind(id);
   int tfMin = (k >= 0 ? g_bkBoxes[k].tfMin : 0);
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);
   string tt = "Base box " + side + " · " + DoubleToString(hPips, 1) + " pips · R:R 1:" + DoubleToString(rr, 0);
   tt += "\n" + TimeToString(t1, TIME_DATE|TIME_MINUTES) + " -> " + TimeToString(t2, TIME_DATE|TIME_MINUTES);
   tt += "\nVisible: " + BaseKnotTFName(tfMin) + (tfMin > 0 ? " and lower" : "") + " (drag to move)";
   string ut = (k >= 0 ? BaseKnotGetText(BaseKnotPrefix(id)) : "");
   if(StringLen(ut) > 0) tt += "\n\"" + ut + "\"";
   if(k >= 0 && g_bkBoxes[k].locked) tt += "\nLOCKED (hold to unlock)";
   else tt += "\nselect + Delete key removes all";
   return tt;
}
string BaseKnotPrevTag()   // sizing-preview edges live under this tag (4 segments)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "PREVIEW";
}
void BaseKnotWipePreview()
{
   string tag = BaseKnotPrevTag();
   if(tag != "") ObjectsDeleteAll(0, tag);
}
string BaseKnotHintName()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "HINT";
}
string BaseKnotGV(const string id)
{
   return "Biotak_BK_" + id + "_" + GetCachedChartIdStr();
}

//+------------------------------------------------------------------+
//| Box look — SINGLE source of truth (P-BK-04/06 + TV-fill 2026-09-07)|
//| Some MT4 builds render OBJ_RECTANGLE filled even with FILL=false   |
//| (see ZoneFactory), so the rectangle doubles as the FILL layer AND  |
//| the drag/select handle, while the VISIBLE border stays 4 OBJ_TREND |
//| edges from BaseKnotDrawEdges (edges can't fill, identical on every |
//| build). Fill invisible (TR=100, the pre-fill default) → bg color + |
//| FILL false = the old hollow look, pixel-identical. Fill set → FILL |
//| true + GetBoxFillRenderColor() (TV Style-tab bucket, e.g. 36%).    |
//+------------------------------------------------------------------+
//--- edge suffixes (committed pfx AND preview tag share them)
#define BK_EDGE_T "_T"
#define BK_EDGE_B "_B"
#define BK_EDGE_L "_L"
#define BK_EDGE_R "_R"
void BaseKnotStyleBox(const string box)   // fill layer + drag handle
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   if(BoxFillVisible())
   {
      ObjectSetInteger(0, box, OBJPROP_COLOR, GetBoxFillRenderColor());
      ObjectSetInteger(0, box, OBJPROP_FILL, true);
   }
   else
   {
      ObjectSetInteger(0, box, OBJPROP_COLOR, bg);
      ObjectSetInteger(0, box, OBJPROP_FILL, false);
   }
   ObjectSetInteger(0, box, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, box, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, box, OBJPROP_BACK, true);   // fill stays behind candles (zone-like); the 4 edges are the foreground border
   ObjectSetInteger(0, box, OBJPROP_ZORDER, 55);   // single source — Commit no longer sets it separately
}
// True when the BOX rect currently shows the live fill look (heal check).
bool BaseKnotFillHealed(const string box)
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   if(BoxFillVisible())
   {
      if(ObjectGetInteger(0, box, OBJPROP_FILL) == 0) return false;
      if((color)ObjectGetInteger(0, box, OBJPROP_COLOR) != GetBoxFillRenderColor()) return false;
      return true;
   }
   if(ObjectGetInteger(0, box, OBJPROP_FILL) != 0) return false;
   return ((color)ObjectGetInteger(0, box, OBJPROP_COLOR) == bg);
}

bool BaseKnotSessionActive() { return (g_bkState != BK_IDLE); }
int  BaseKnotCount()         { return ArraySize(g_bkBoxes); }

// UI side polls this after OnChartEventHandler to re-show the hidden menu.
bool BaseKnotTakeRestoreFlag()
{
   if(!g_bkRestoreReq) return false;
   g_bkRestoreReq = false;
   return true;
}

//+------------------------------------------------------------------+
//| Dynamic point/pip — gold, crypto, JPY and forex all covered via   |
//| the shared asset-aware cache (PerformanceOptimizations.mqh).      |
//+------------------------------------------------------------------+
double BaseKnotPipSize()
{
   double pip = GetCachedPipSize();
   if(pip <= 0) pip = GetCachedPoint();
   if(pip <= 0) pip = _Point;
   return pip;
}
double BaseKnotToPips(const double dist) { return dist / BaseKnotPipSize(); }

//+------------------------------------------------------------------+
//| Id helpers — ids are "<tfMin>_<tick>[rNNN]"; tails split at the   |
//| LAST underscore (StringFind from the right) because the id itself |
//| contains an underscore.                                           |
//+------------------------------------------------------------------+
void BaseKnotSplitTail(const string tail, string &bid, string &kind)
{
   bid = ""; kind = "";
   int last = -1, pos = 0;
   while(true)
   {
      int f = StringFind(tail, "_", pos);
      if(f < 0) break;
      last = f;
      pos = f + 1;
   }
   if(last <= 0) return;   // malformed (PREVIEW/HINT tails land here)
   bid  = StringSubstr(tail, 0, last);
   kind = StringSubstr(tail, last + 1);
}
// Commit-TF minutes encoded in the id head; 0 = legacy bare-tick id.
int BaseKnotIdTF(const string bid)
{
   int us = StringFind(bid, "_");
   if(us <= 0) return 0;
   return (int)StringToInteger(StringSubstr(bid, 0, us));
}
// Visibility mask: commit TF + every lower TF. Higher TFs stay hidden so
// a low-TF knot never renders as a hairline there (P-BK-01).
long BaseKnotTFMask(const int tfMin)
{
   if(tfMin <= 0) return OBJ_ALL_PERIODS;   // legacy box — keep old behavior
   long m = 0;
   if(tfMin >= 1)     m |= OBJ_PERIOD_M1;
   if(tfMin >= 5)     m |= OBJ_PERIOD_M5;
   if(tfMin >= 15)    m |= OBJ_PERIOD_M15;
   if(tfMin >= 30)    m |= OBJ_PERIOD_M30;
   if(tfMin >= 60)    m |= OBJ_PERIOD_H1;
   if(tfMin >= 240)   m |= OBJ_PERIOD_H4;
   if(tfMin >= 1440)  m |= OBJ_PERIOD_D1;
   if(tfMin >= 10080) m |= OBJ_PERIOD_W1;
   if(tfMin >= 43200) m |= OBJ_PERIOD_MN1;
   if(m == 0) m = OBJ_ALL_PERIODS;
   return m;
}
// Minutes compare — robust on exotic chart TFs (no flag mapping needed).
bool BaseKnotTFVisible(const int tfMin)
{
   if(tfMin <= 0) return true;
   return (Period() <= tfMin);
}

//+------------------------------------------------------------------+
//| BKMAGNET-OFF (2026-09-06, user decision — corners jumped to candle|
//| shadows and the box never landed where clicked, unlike the native |
//| rectangle tool): NO snapping — a click IS the corner, exactly like |
//| MT4's own box. Body kept (commented) for a one-line restore.      |
//+------------------------------------------------------------------+
double BaseKnotSnapPrice(const datetime t, const double price)
{
   return price;   // BKMAGNET-OFF: click = corner, no High/Low pull
   //--- retired snap body (restore by deleting the line above) ---
   //if(!inpEnableMagnet) return price;
   //if(t <= 0 || price <= 0) return price;
   //int shift = iBarShift(_Symbol, 0, t, false);
   //if(shift < 0) return price;
   //double hi = High[shift], lo = Low[shift];
   //if(hi <= 0 || lo <= 0 || hi < lo) return price;
   //double dH = MathAbs(price - hi), dL = MathAbs(price - lo);
   //double gate = (double)inpMagnetSensitivityPips * BaseKnotPipSize();
   //if(gate <= 0) gate = BaseKnotPipSize();   // sensitivity 0 = exact touch only
   //if(MathMin(dH, dL) > gate) return price;  // too far — leave the hand-drawn value
   //return (dH <= dL ? hi : lo);
}

//+------------------------------------------------------------------+
//| Direction — decided at commit, then FOLLOWS the live price (see   |
//| the resolver below + BaseKnotRefreshDirection). Positional rule:  |
//| price above the box = Buy, below = Sell. Price INSIDE resolves by |
//| entry side (most recent close outside: from below → Buy, from      |
//| above → Sell); mid-vs-price is the last fallback. Boxes fully     |
//| outside keep following afterwards — the box itself is the          |
//| hysteresis band, so in-box vibration never flickers the lines.    |
//+------------------------------------------------------------------+
int BaseKnotResolveDirection(const double top, const double bot)
{
   double ref = iClose(_Symbol, 0, 0);
   if(ref <= 0) ref = g_currentPrice;
   if(ref > top) return 1;
   if(ref > 0 && ref < bot) return -1;
   if(ref > 0)   // inside the box (or exactly on an edge): entry side decides
   {
      for(int s = 1; s <= BK_DIR_LOOKBACK; s++)
      {
         double c = iClose(_Symbol, 0, s);
         if(c <= 0) continue;
         if(c < bot) return 1;    // rose into the box from below → demand → Buy
         if(c > top) return -1;   // fell into the box from above → supply → Sell
      }
      double mid = (top + bot) / 2.0;
      return (mid <= ref ? 1 : -1);
   }
   return 1;   // no live price at all — harmless default
}

//+------------------------------------------------------------------+
//| Live reference price — forming-bar close first (the freshest      |
//| chart price), g_currentPrice fallback (EventHandlers refreshes it |
//| per tick; the 500 ms pump also runs on the timer path with zero   |
//| ticks). <= 0 = no usable data — the caller must keep, never flip. |
//+------------------------------------------------------------------+
double BaseKnotLiveRef()
{
   double ref = iClose(_Symbol, 0, 0);
   if(ref <= 0) ref = g_currentPrice;
   return ref;
}

//+------------------------------------------------------------------+
//| Auto-follow (P-BK-13): the box itself is the hysteresis band —    |
//| fully outside takes that side, inside (or on an edge) keeps the   |
//| current one. No extra buffer to tune, no new inputs.              |
//+------------------------------------------------------------------+
int BaseKnotFollowDirection(const double top, const double bot, const int curDir, const double ref)
{
   if(ref <= 0) return curDir;   // weekend / data gap — never flip blind
   if(ref > top) return 1;       // box fully below the price = demand = Buy
   if(ref < bot) return -1;      // box fully above it = supply = Sell
   return curDir;                // inside — keep, so vibration can't flicker
}
// Refresh one box's dir from the live price. Returns true on a real flip
// (dir + chart-scoped GV persisted; the caller Syncs to rebuild the
// Entry/SL/TP lines, tooltips and INFO). Lite-safe: Object* + GV only.
bool BaseKnotRefreshDirection(const string id, const double ref)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return false;
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(p1 <= 0 || p2 <= 0) return false;
   int want = BaseKnotFollowDirection(MathMax(p1, p2), MathMin(p1, p2), g_bkBoxes[k].dir, ref);
   if(want == g_bkBoxes[k].dir) return false;
   g_bkBoxes[k].dir = want;
   GlobalVariableSet(BaseKnotGV(id), (double)want);
   return true;
}

//+------------------------------------------------------------------+
//| Registry helpers                                                  |
//+------------------------------------------------------------------+
int BaseKnotFind(const string id)
{
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
      if(g_bkBoxes[i].id == id) return i;
   return -1;
}
void BaseKnotRegister(const string id, const int dir, const int tfMin)
{
   if(BaseKnotFind(id) >= 0) return;
   int n = ArraySize(g_bkBoxes);
   ArrayResize(g_bkBoxes, n + 1);
   g_bkBoxes[n].id    = id;
   g_bkBoxes[n].dir   = (dir < 0 ? -1 : 1);
   g_bkBoxes[n].tfMin = tfMin;
   g_bkBoxes[n].commitMs = GetTickCount();   // fresh commit → Auto INFO grace starts now
   g_bkBoxes[n].locked = false;              // fresh boxes are always unlocked
   GlobalVariableSet(BaseKnotGV(id), (double)g_bkBoxes[n].dir);
}
void BaseKnotUnregister(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   for(int i = k; i < ArraySize(g_bkBoxes) - 1; i++) g_bkBoxes[i] = g_bkBoxes[i + 1];
   ArrayResize(g_bkBoxes, ArraySize(g_bkBoxes) - 1);
   GlobalVariableDel(BaseKnotGV(id));
}
// Lock — a locked box is unselectable so it can never be dragged (hold still
// opens the mini strip, so it can always be unlocked). The flag rides the BOX
// handle's own SELECTABLE bit: no GV, survives TF-switches and restarts.
bool BaseKnotLocked(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   return g_bkBoxes[k].locked;
}
void BaseKnotSetLocked(const string id, const bool on)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   g_bkBoxes[k].locked = on;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, !on);
   BaseKnotSync(id);   // rebuild the live tooltip (coords · TF-scope · text · lock)
   ChartRedraw();
}
// Rebuild the registry from chart objects once (TF-switch safe: the box
// anchors ARE the spec, direction rides a chart-scoped GV, TF rides the id).
// Also purges the transient PREVIEW/HINT of a dead session (state resets on
// reload, so a reloaded indicator must never inherit a ghost rubber-band)
// and sweeps orphan direction-GVs of this chart whose boxes are gone.
void BaseKnotLazyInit()
{
   if(g_bkInitDone) return;
   g_bkInitDone = true;
   if(StringLen(inpObjectPrefix) == 0) return;
   string tag = inpObjectPrefix + BK_TAG;
   BaseKnotWipePreview();
   BaseKnotWipeLive();   // dead-session transients — never inherited
   ObjectDelete(0, BaseKnotHintName());
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, tag) != 0) continue;
      if(StringFind(nm, "BOX", StringLen(nm) - 3) < 0) continue;
       string id = StringSubstr(nm, StringLen(tag), StringLen(nm) - StringLen(tag) - 4);
       int dir = 1;
       if(GlobalVariableCheck(BaseKnotGV(id)))
          dir = ((int)GlobalVariableGet(BaseKnotGV(id)) < 0 ? -1 : 1);
       else
       {
          // No frozen value (pre-GV box or a wiped GV): resolve positionally
          // exactly like a fresh commit instead of blindly defaulting to Buy —
          // Register persists it, so the rebuild is stable from here on.
          double iA = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
          double iB = ObjectGetDouble(0, nm, OBJPROP_PRICE, 1);
          dir = BaseKnotResolveDirection(MathMax(iA, iB), MathMin(iA, iB));
       }
       BaseKnotRegister(id, dir, BaseKnotIdTF(id));
      int q = BaseKnotFind(id);
      if(q >= 0)
      {
         g_bkBoxes[q].commitMs = 0;   // inherited box — long ago, no Auto grace flash
         g_bkBoxes[q].locked = (ObjectGetInteger(0, nm, OBJPROP_SELECTABLE) == 0);   // lock rides the handle itself — no GV, survives TF-switch/restart
      }
   }
   // P-BK-06 migration: hollow-by-construction (bg handle + edge segments) —
   // every inherited box is re-synced once so pre-edge boxes gain their
   // border edges and lose their visible fill immediately, no drag needed.
   for(int b = 0; b < ArraySize(g_bkBoxes); b++) BaseKnotSync(g_bkBoxes[b].id);
   // Orphan-GV sweep (this chart only — the GV carries the chart id suffix).
   string cid = GetCachedChartIdStr();
   for(int k = GlobalVariablesTotal() - 1; k >= 0; k--)
   {
      string gv = GlobalVariableName(k);
      if(StringFind(gv, "Biotak_BK_") != 0) continue;
      if(StringFind(gv, "_" + cid, StringLen(gv) - StringLen(cid) - 1) < 0) continue;
      string oid = StringSubstr(gv, 10, StringLen(gv) - 10 - StringLen(cid) - 1);
      if(BaseKnotFind(oid) < 0) GlobalVariableDel(gv);
   }
}

//+------------------------------------------------------------------+
//| Hint bar (bottom-left): guidance while sizing, auto-hiding result.|
//| Amber on dark charts is unreadable on light ones — pick the text   |
//| color from the chart background luminance. Result hints ("BASE #N  |
//| set") expire after 4 s so the corner never nags; guidance hints   |
//| stay until the session ends.                                       |
//+------------------------------------------------------------------+
static uint g_bkHintExpireMs = 0;   // 0 = persistent; else GetTickCount deadline
// Readable foreground for chart-anchored texts (hint + INFO label) — amber on
// dark charts, dark brown on light ones (same luminance gate, one place).
color BaseKnotFgForBg()
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int lum = ((((int)bg) & 0xFF) * 299 + ((((int)bg) >> 8) & 0xFF) * 587 +
              ((((int)bg) >> 16) & 0xFF) * 114) / 1000;
   return (lum > 128 ? C'150,70,0' : C'255,171,0');
}
void BaseKnotHintShow(const string text, const int ttlMs = 0)
{
   string hn = BaseKnotHintName();
   if(hn == "") return;
   if(ObjectFind(0, hn) < 0) ObjectCreate(0, hn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hn, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, hn, OBJPROP_YDISTANCE, 44);
   ObjectSetString(0, hn, OBJPROP_TEXT, text);
   ObjectSetString(0, hn, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, hn, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, hn, OBJPROP_COLOR, BaseKnotFgForBg());
   ObjectSetInteger(0, hn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_BACK, false);
   ObjectSetInteger(0, hn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, hn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, hn, OBJPROP_ZORDER, 1500);
   g_bkHintExpireMs = (ttlMs > 0 ? GetTickCount() + (uint)ttlMs : 0);
   ChartRedraw();
}
void BaseKnotHintHide()
{
   ObjectDelete(0, BaseKnotHintName());
   g_bkHintExpireMs = 0;
   ChartRedraw();
}
// Per-tick expiry pump (called from RefreshUIPerTick's 500 ms block).
void BaseKnotHintTick()
{
   if(g_bkHintExpireMs == 0) return;
   if((int)(GetTickCount() - g_bkHintExpireMs) >= 0) BaseKnotHintHide();
}

//+------------------------------------------------------------------+
//| Chart lock — MT4-like: while a gesture is active (drawing a new   |
//| box OR dragging a committed one) the view must not slide under    |
//| the hand. MOUSE_SCROLL blocks drag-panning, AUTOSCROLL suspend    |
//| stops live ticks from shifting the chart mid-gesture (restoring   |
//| it only re-arms the snap-to-live the ticks would have done        |
//| anyway). First locker saves, nested locks only re-assert, one     |
//| Unlock restores — so session and drag locks can never corrupt     |
//| each other's saved values. ctxToo=false for IDLE drags (the chart |
//| context menu stays available there, unlike in a draw session).    |
//+------------------------------------------------------------------+
void BaseKnotLockChart(const bool ctxToo)
{
   if(!s_bkChartLocked)
   {
      g_bkScrollWas = (ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0);
      g_bkCtxWas    = (ChartGetInteger(0, CHART_CONTEXT_MENU) != 0);
      g_bkAutoWas   = (ChartGetInteger(0, CHART_AUTOSCROLL) != 0);
      s_bkChartLocked = true;
   }
   ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
   if(g_bkAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, false);
   if(ctxToo) ChartSetInteger(0, CHART_CONTEXT_MENU, false);
   g_bkTouched = true;   // OnDeinit must restore, whatever happens
}
void BaseKnotUnlockChart()
{
   if(!s_bkChartLocked) return;
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_bkScrollWas);
   ChartSetInteger(0, CHART_CONTEXT_MENU, g_bkCtxWas);
   if(g_bkAutoWas) ChartSetInteger(0, CHART_AUTOSCROLL, true);
   s_bkChartLocked = false;
}
// Re-assert an OWNED lock (P-BK-14): a one-time lock is not enough — third
// writers (menu modal unlock when a strip/card closes mid-gesture, the panel
// watchdog restore, template/terminal resets) can flip the props back while
// the button is still down, and the chart then pans under the hand for the
// rest of the gesture. While we own it, every throttled step re-forces the
// props. Read-guarded: steady state costs only the reads, writes happen
// solely on drift. ctxToo mirrors the original locker (session=true, drag=false).
void BaseKnotReassertLock(const bool ctxToo)
{
   if(!s_bkChartLocked) return;
   if(ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0)
   { ChartSetInteger(0, CHART_MOUSE_SCROLL, false); g_bkTouched = true; }
   if(g_bkAutoWas && ChartGetInteger(0, CHART_AUTOSCROLL) != 0)
   { ChartSetInteger(0, CHART_AUTOSCROLL, false); g_bkTouched = true; }
   if(ctxToo && ChartGetInteger(0, CHART_CONTEXT_MENU) != 0)
   { ChartSetInteger(0, CHART_CONTEXT_MENU, false); g_bkTouched = true; }
}
// IDLE box-drag holder: lock once a REAL drag starts (past slop — taps never
// flicker the props), release on button-up. The state check keeps a drag
// release from unlocking a draw session's lock in the pathological overlap.
void BaseKnotDragLockOn()
{
   if(s_bkDragLock || g_bkState != BK_IDLE) return;   // taps/sessions never take the drag lock
   BaseKnotLockChart(false);
   s_bkDragLock = true;
}
void BaseKnotDragLockOff()
{
   if(!s_bkDragLock || g_bkState != BK_IDLE) return;
   s_bkDragLock = false;
   BaseKnotUnlockChart();
}

//+------------------------------------------------------------------+
//| Arm / cancel — called from the Tools-ring click (menu side hides  |
//| the ring first). Raw Chart* scroll lock: no menu dependency, so   |
//| Lite compiles and keeps working on committed boxes.               |
//+------------------------------------------------------------------+
void BaseKnotArm()
{
   BaseKnotLazyInit();
   g_bkState   = BK_ARMED;
   g_bkArmedMs = GetTickCount();
   g_bkLeftPrev = true;   // the arming press is still down — never take its release as click 1
   g_bkHeld = false;
   g_bkLiveT = 0; g_bkLiveP = 0.0;
   BaseKnotLockChart(true);   // no chart slide under the hand while drawing
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   BaseKnotHintShow("BASE TOOL — press + drag (release = done) · or click 2 corners · right-click / ESC: cancel");
   ChartRedraw();
}
void BaseKnotCancel()
{
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   BaseKnotHintHide();
   g_bkState = BK_IDLE;
   g_bkHeld = false;
   BaseKnotUnlockChart();
   g_bkRestoreReq = true;   // UI side re-shows the hidden ring menu
   ChartRedraw();
}

// Deinit safety (call from OnDeinitHandler, every reason): a remove /
// TF-switch / crash-reload mid-session must never leave the chart scroll
// locked, a ghost rubber-band behind, or a stale restore flag. Committed
// boxes are the independent layer and stay untouched here (REMOVE wipes
// them via DeleteAllIndicatorObjects(true) + the Biotak_BK_* GV sweep).
void BaseKnotOnDeinit(const int reason)
{
   BaseKnotUnlockChart();   // every reason — a stuck lock must never survive a switch/remove
   g_bkTouched = false;
   s_bkDragLock = false;
   s_bkDragId = ""; s_bkDragMoved = false;
   g_bkState = BK_IDLE;
   g_bkRestoreReq = false;
   g_bkHeld = false;
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   ObjectDelete(0, BaseKnotHintName());
   if(reason == REASON_REMOVE) ArrayResize(g_bkBoxes, 0);
}

//+------------------------------------------------------------------+
//| Border edges — the VISIBLE box outline (finite segments, never a |
//| ray). Ensure-create + move + style in one call, so drag-sync,     |
//| restyle-all and child-delete-heal all rebuild missing edges.      |
//+------------------------------------------------------------------+
void BaseKnotMakeEdge(const string name, const datetime t1, const double p1,
                      const datetime t2, const double p2,
                      const color clr, const int style, const int width,
                      const string tooltip, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // the BOX rect is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);   // the visible border always reads (like TH lines + MT4 tools)
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 56);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
// Draw/refresh the 4 outline edges under one tag (committed pfx or preview
// tag) — the hollow look on builds that ignore FILL (P-BK-06).
void BaseKnotDrawEdges(const string tag, datetime t1, const double p1,
                       datetime t2, const double p2,
                       const color clr, const int style, const int width,
                       const string tooltip, const long tfMask)
{
   if(tag == "") return;
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   BaseKnotMakeEdge(tag + BK_EDGE_T, t1, top, t2, top, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_B, t1, bot, t2, bot, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_L, t1, bot, t1, top, clr, style, width, tooltip, tfMask);
   BaseKnotMakeEdge(tag + BK_EDGE_R, t2, bot, t2, top, clr, style, width, tooltip, tfMask);
}

//+------------------------------------------------------------------+
//| Children geometry — single source of truth for commit / drag-sync.|
//| Buy: Entry=top, SL=bottom, TP=top+NxR (N = Base Box TARGET R).    |
//| Sell mirrored.                                                    |
//+------------------------------------------------------------------+
void BaseKnotCalcLevels(const double top, const double bot, const int dir,
                        double &entry, double &sl, double &tp)
{
   double h = top - bot;
   double mult = (g_bkTargetR >= 1 ? (double)g_bkTargetR : BK_TP_R_MULT);
   if(dir >= 0) { entry = top; sl = bot; tp = top + h * mult; }
   else         { entry = bot; sl = top; tp = bot - h * mult; }
}
void BaseKnotMakeRay(const string name, const datetime tA, const datetime tB,
                     const double level, const color clr, const int style, const int width,
                     const string tooltip, const long tfMask, const bool rayRight)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, tA, level, tB, level);
   ObjectMove(0, name, 0, tA, level);
   ObjectMove(0, name, 1, tB, level);   // horizontal — Entry/SL project forward (ray-right),
                                          // TP is a short target tick at the right edge (never a ray)
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);   // TF-scoped with the box
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // the BOX is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);   // levels read over candles (like TH lines)
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 50);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
// TP tick span — the target marker hugs the chart's RIGHT edge, next to the
// price axis (user decision 2026-09-08): a SHORT fixed tick (2 bars) ending
// exactly at the window's right edge time — never a ray, never box-wide.
// Falls back to the current bar (then box-anchored) when the edge/series is
// not convertible.
datetime BaseKnotTPEdgeTime()
{
   long wpx = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(wpx <= 10) return 0;
   int sw = 0; datetime et = 0; double ep = 0;
   if(!ChartXYToTimePrice(0, (int)wpx - 1, 10, sw, et, ep)) return 0;
   if(sw != 0 || et <= 0) return 0;
   return et;
}
void BaseKnotTPTickSpan(const datetime t1, const datetime t2, datetime &ts, datetime &te)
{
   datetime et = BaseKnotTPEdgeTime();
   if(et > 0) { te = et; ts = et - (datetime)(2 * PeriodSeconds()); return; }
   datetime cur0 = iTime(_Symbol, 0, 0);
   ts = (cur0 > 0 ? cur0 : t2);
   te = ts + (datetime)(2 * PeriodSeconds());
}
// Lean edge glue for the 500ms pump: scroll/zoom/new bars only remap TIME, so
// the tick is re-anchored with two ObjectMoves (level untouched) — never a
// full Sync. Missing TPs heal via OBJECT_DELETE, ray-flagged ones via Sync.
void BaseKnotTPGlue(const string pfx, const datetime edgeT)
{
   string tpNm = BaseKnotTPName(pfx);
   if(ObjectFind(0, tpNm) < 0) return;
   if(ObjectGetInteger(0, tpNm, OBJPROP_RAY_RIGHT) != 0) return;   // structural — the Sync path rebuilds it
   datetime ts = edgeT - (datetime)(2 * PeriodSeconds());
   if((datetime)ObjectGetInteger(0, tpNm, OBJPROP_TIME, 0) != ts ||
      (datetime)ObjectGetInteger(0, tpNm, OBJPROP_TIME, 1) != edgeT)
   {
      ObjectMove(0, tpNm, 0, ts, ObjectGetDouble(0, tpNm, OBJPROP_PRICE, 0));
      ObjectMove(0, tpNm, 1, edgeT, ObjectGetDouble(0, tpNm, OBJPROP_PRICE, 1));
   }
}
// TP tick look — SOLID + width 2: a 2-bar DASHED tick renders as almost
// nothing, so the tiny marker must be solid and thicker to read instantly.
#define BK_TP_TICK_STYLE STYLE_SOLID
#define BK_TP_TICK_WIDTH 2
// TP staleness for the 500ms pump: only STRUCTURAL drift (a pre-tick ray, or
// an older dashed/thin tick) heals via a full Sync here — edge/scroll/new-bar
// drift is glued lean by BaseKnotTPGlue below. Read-guarded: steady state is
// compares only, no Sync.
bool BaseKnotTPStale(const string pfx)
{
   string tpNm = BaseKnotTPName(pfx);
   if(ObjectFind(0, tpNm) < 0) return false;   // user-deleted children heal via OBJECT_DELETE, not here
   if(ObjectGetInteger(0, tpNm, OBJPROP_RAY_RIGHT) != 0) return true;
   if(ObjectGetInteger(0, tpNm, OBJPROP_STYLE) != BK_TP_TICK_STYLE) return true;
   if(ObjectGetInteger(0, tpNm, OBJPROP_WIDTH) != BK_TP_TICK_WIDTH) return true;
   return false;
}
void BaseKnotMakeBadge(const string name, const string text, const color bg)   // NOBKDEL: retired — no badge is created anymore (kept for one-line restore)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_BADGE_W);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_BADGE_H);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'18,22,33');
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1600);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}
// INFO visibility — Show mode pins the label on; Auto shows it live while
// sizing (LIVE_ tag always writes) and for BK_INFO_GRACE_MS after commit,
// then hides it so the chart stays clean. Full numbers always ride the
// box/edge hover tooltips, so nothing is ever unreachable.
bool BaseKnotInfoVisible(const string id)
{
   if(g_bkShowInfo == 1) return true;
   int k = BaseKnotFind(id);
   if(k < 0) return true;
   return ((int)(GetTickCount() - g_bkBoxes[k].commitMs) < (int)BK_INFO_GRACE_MS);
}
// Chart-anchored "[H Pips | R:R 1:N]" label at the box top-right corner.
void BaseKnotWriteInfo(const string in, const datetime t2, const double top,
                       const double hPips, const double rr, const double tpPips,
                       const string side, const long tfMask)
{
   if(ObjectFind(0, in) < 0) ObjectCreate(0, in, OBJ_TEXT, 0, t2, top);
   ObjectSetString(0, in, OBJPROP_TEXT,
                   "[" + side + " " + DoubleToString(hPips, 1) + " Pips | R:R 1:" + DoubleToString(rr, 0) + "]");
   ObjectSetString(0, in, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, in, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, in, OBJPROP_COLOR, BaseKnotFgForBg());
   ObjectSetInteger(0, in, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, in, OBJPROP_BACK, false);
   ObjectSetInteger(0, in, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, in, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, in, OBJPROP_ZORDER, 60);
   ObjectSetInteger(0, in, OBJPROP_TIMEFRAMES, tfMask);
   ObjectSetString(0, in, OBJPROP_TOOLTIP, "BK " + side + ": risk " + DoubleToString(hPips, 1) +
                   " pips, target +" + DoubleToString(tpPips, 1) + " pips");
   ObjectSetInteger(0, in, OBJPROP_TIME, 0, t2);
   ObjectSetDouble(0, in, OBJPROP_PRICE, 0, top);
}
// Live sizing set — Entry/SL/TP + info shown WHILE drawing (before click 2).
// ONE fixed tag (single sizing at a time); wiped at commit/cancel/deinit.
string BaseKnotLiveTag()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "LIVE_";
}
void BaseKnotWipeLive()
{
   string tag = BaseKnotLiveTag();
   if(tag != "") ObjectsDeleteAll(0, tag);
}
// Live setup preview from corner 1 to the cursor. Direction re-resolves here;
// the commit freezes it. Zero-height cursor = rays hidden, preview rect stays.
void BaseKnotSyncLive(const datetime t2raw, const double p2raw)
{
   string tag = BaseKnotLiveTag();
   if(tag == "") return;
   double top = MathMax(g_bkP1, p2raw), bot = MathMin(g_bkP1, p2raw);
   if(top <= bot) { BaseKnotWipeLive(); return; }
   datetime t1 = g_bkT1, te = t2raw;
   if(te < t1) { datetime tt = t1; t1 = te; te = tt; }
   int dir = BaseKnotResolveDirection(top, bot);
   long tfMask = BaseKnotTFMask(Period());
   double entry = 0, sl = 0, tp = 0;
   BaseKnotCalcLevels(top, bot, dir, entry, sl, tp);
   double hPips  = BaseKnotToPips(top - bot);
   double tpPips = BaseKnotToPips(MathAbs(tp - entry));
   double rr     = (hPips > 0 ? tpPips / hPips : (g_bkTargetR >= 1 ? (double)g_bkTargetR : BK_TP_R_MULT));
   int dg = GetCachedDigits();
   string side = (dir >= 0 ? "BUY" : "SELL");
   datetime tLiveFar = te + (te > t1 ? (te - t1) : PeriodSeconds());
   datetime tLiveTps, tLiveTpe;
   BaseKnotTPTickSpan(t1, te, tLiveTps, tLiveTpe);
   BaseKnotMakeRay(tag + "ENTRY", te, tLiveFar, entry, g_bkEntryColor, STYLE_SOLID, 1,
                   "BK " + side + " Entry (sizing): " + DoubleToString(entry, dg), tfMask, true);
   BaseKnotMakeRay(tag + "SL", te, tLiveFar, sl, g_bkStopColor, STYLE_DASH, 1,
                   "BK " + side + " Stop (sizing): " + DoubleToString(sl, dg) + " (" + DoubleToString(hPips, 1) + " pips)", tfMask, true);
   BaseKnotMakeRay(tag + "TP", tLiveTps, tLiveTpe, tp, g_bkTargetColor, BK_TP_TICK_STYLE, BK_TP_TICK_WIDTH,
                   "BK " + side + " Target (sizing): " + DoubleToString(tp, dg) + " (+" + DoubleToString(tpPips, 1) + " pips, R:R 1:" + DoubleToString(rr, 0) + ")", tfMask, false);
   BaseKnotWriteInfo(tag + "INFO", te, top, hPips, rr, tpPips, side, tfMask);
}
// INFO text is chart-anchored and only TF-gated (no pixel button —
// NOBKDEL 2026-09-06: the X delete badge is retired, boxes delete via
// select + Delete key). TF-hidden boxes stay hidden here even when
// their corner is on-screen.
void BaseKnotPlaceBadges(const string pfx, const datetime t1, const datetime t2,
                          const double top, const int tfMin, const long tfMask)
{
   bool tfVis = BaseKnotTFVisible(tfMin);
   string in = BaseKnotInfoName(pfx);
   ObjectSetInteger(0, in, OBJPROP_TIMEFRAMES, (tfVis ? tfMask : OBJ_NO_PERIODS));   // AND the commit mask — never plain ALL
   if(!tfVis) return;
   ObjectSetInteger(0, in, OBJPROP_TIME, 0, t2);
   ObjectSetDouble(0, in, OBJPROP_PRICE, 0, top);
}
// (Re)build every child of one box from its live anchors. Direction is read
// from the registry — NEVER recomputed here (P-BK-13: the pump /
// drag-release refresh it via BaseKnotRefreshDirection BEFORE calling Sync,
// so Sync itself stays flicker-free).
void BaseKnotSync(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   int dir = g_bkBoxes[k].dir;
   int tfMin = g_bkBoxes[k].tfMin;
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);   // legacy registry rows
   long tfMask = BaseKnotTFMask(tfMin);
   ObjectSetInteger(0, box, OBJPROP_TIMEFRAMES, tfMask);
   BaseKnotStyleBox(box);   // fill layer + drag handle — the VISIBLE border is the 4 edges below
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, !g_bkBoxes[k].locked);   // lock heal: handle follows the registry
   double entry = 0, sl = 0, tp = 0;
   BaseKnotCalcLevels(top, bot, dir, entry, sl, tp);
   double hPips  = BaseKnotToPips(top - bot);
   double tpPips = BaseKnotToPips(MathAbs(tp - entry));
   double rr     = (hPips > 0 ? tpPips / hPips : (g_bkTargetR >= 1 ? (double)g_bkTargetR : BK_TP_R_MULT));
   string side = (dir >= 0 ? "BUY" : "SELL");
   int dg = GetCachedDigits();
   string tip = BaseKnotBoxTooltip(id, t1, t2, top, bot, side, hPips, rr);
   ObjectSetString(0, box, OBJPROP_TOOLTIP, tip);
   BaseKnotDrawEdges(pfx, t1, p1, t2, p2,
                     GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth, tip, tfMask);
   BaseKnotPlaceText(pfx, t1, t2, top, bot, tfMask, tip);   // existing user text follows the box (never resurrected)
   datetime tFar = t2 + (t2 > t1 ? (t2 - t1) : PeriodSeconds());
   datetime tps, tpe;
   BaseKnotTPTickSpan(t1, t2, tps, tpe);   // TP tick rides the right edge, not the box
   BaseKnotMakeRay(BaseKnotEntryName(pfx), t2, tFar, entry, g_bkEntryColor, STYLE_SOLID, 1,
                   "BK " + side + " Entry: " + DoubleToString(entry, dg), tfMask, true);
   BaseKnotMakeRay(BaseKnotSLName(pfx), t2, tFar, sl, g_bkStopColor, STYLE_DASH, 1,
                   "BK " + side + " Stop: " + DoubleToString(sl, dg) + " (" + DoubleToString(hPips, 1) + " pips)", tfMask, true);
   BaseKnotMakeRay(BaseKnotTPName(pfx), tps, tpe, tp, g_bkTargetColor, BK_TP_TICK_STYLE, BK_TP_TICK_WIDTH,
                   "BK " + side + " Target: " + DoubleToString(tp, dg) + " (+" + DoubleToString(tpPips, 1) + " pips, R:R 1:" + DoubleToString(rr, 0) + ")", tfMask, false);
   ObjectDelete(0, BaseKnotDelName(pfx));   // NOBKDEL 2026-09-06: X badge retired — purge pre-retire badges
   ObjectDelete(0, BaseKnotBuyName(pfx));   // NOBUYSELL: purge pre-2026-09-06 direction badges
   if(BaseKnotInfoVisible(id))
   {
      BaseKnotWriteInfo(BaseKnotInfoName(pfx), t2, top, hPips, rr, tpPips, side, tfMask);
      BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin, tfMask);
   }
   else
      ObjectDelete(0, BaseKnotInfoName(pfx));   // Auto mode, grace over — chart stays clean
}
// Shared drag-paint budget: position writes are cheap, FULL repaints are not
// (a heavy chart costs 100ms+ per repaint — an unthrottled ChartRedraw per
// drag event turns dragging into a slideshow that only settles on release).
// Every drag painter (event sync, cursor follow, strip follow) draws through
// here (30ms); the release path repaints unconditionally (final frame).
void BaseKnotDragPaint()
{
   uint now = GetTickCount();
   if(now - s_bkDragPaintMs < 30) return;
   s_bkDragPaintMs = now;
   ChartRedraw();
}
// Lean child mover — ObjectMove ONLY (no style/color/create/delete syscalls)
// for per-step drag following. Same geometry as Sync (levels via
// BaseKnotCalcLevels, text via BaseKnotTextPlace), so the authoritative
// release Sync lands on identical pixels. Missing children are skipped (the
// release Sync rebuilds them) — never resurrect mid-drag.
void BaseKnotMoveOne(const string nm, const datetime tA, const double pA,
                     const datetime tB, const double pB)
{
   if(ObjectFind(0, nm) < 0) return;
   ObjectMove(0, nm, 0, tA, pA);
   ObjectMove(0, nm, 1, tB, pB);
}
void BaseKnotMoveChildren(const string id, datetime t1, const double p1,
                          datetime t2, const double p2)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   if(ObjectFind(0, BaseKnotBoxName(pfx)) < 0) return;
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   double entry = 0, sl = 0, tp = 0;
   BaseKnotCalcLevels(top, bot, g_bkBoxes[k].dir, entry, sl, tp);
   datetime tFar = t2 + (t2 > t1 ? (t2 - t1) : PeriodSeconds());
   datetime tps, tpe;
   BaseKnotTPTickSpan(t1, t2, tps, tpe);   // TP tick rides the right edge, not the box
   BaseKnotMoveOne(pfx + BK_EDGE_T, t1, top, t2, top);
   BaseKnotMoveOne(pfx + BK_EDGE_B, t1, bot, t2, bot);
   BaseKnotMoveOne(pfx + BK_EDGE_L, t1, bot, t1, top);
   BaseKnotMoveOne(pfx + BK_EDGE_R, t2, bot, t2, top);
   BaseKnotMoveOne(BaseKnotEntryName(pfx), t2, entry, tFar, entry);
   BaseKnotMoveOne(BaseKnotSLName(pfx), t2, sl, tFar, sl);
   BaseKnotMoveOne(BaseKnotTPName(pfx), tps, tp, tpe, tp);
   string in = BaseKnotInfoName(pfx);
   if(ObjectFind(0, in) >= 0) ObjectMove(0, in, 0, t2, top);
   string tn = BaseKnotTextName(pfx);
   if(ObjectFind(0, tn) >= 0)
   {
      datetime tx; double px; int anchor;
      BaseKnotTextPlace(t1, t2, top, bot, tx, px, anchor);
      ObjectMove(0, tn, 0, tx, px);
   }
}
// Unified per-step drag follow — the ONLY mid-drag children writer (P-BK-07).
// Both event channels call it with what they carry: OBJECT_DRAG brings live
// anchors only (its cursor coords are untrusted — in-repo pattern, TH3Tool
// reads anchors there too), MOUSE_MOVE brings the trusted cursor. Source
// priority is single: BOX live anchors while the terminal moves them (exact —
// MT4 magnet/snap included, ~14 cheap syscalls, never a full Sync),
// cursor-delta from the press latch only while anchors sit frozen mid-drag
// (builds that refresh anchors at release). One 30ms budget covers moves +
// paint; release still does the authoritative BaseKnotSync.
void BaseKnotFollowDrag(const string id, const datetime curT, const double curP)
{
   s_bkDragActMs = GetTickCount();   // activity even when the 30ms gate below absorbs this call
   uint now = s_bkDragActMs;
   if(now - s_bkDragMs < 30) return;   // one budget for moves + paint
   s_bkDragMs = now;
   BaseKnotReassertLock(false);   // P-BK-14: the drag owns the view until release (drag took ctxToo=false)
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(t1 != s_bkFolT1 || t2 != s_bkFolT2 || p1 != s_bkFolP1 || p2 != s_bkFolP2)
   {
      s_bkFolT1 = t1; s_bkFolT2 = t2; s_bkFolP1 = p1; s_bkFolP2 = p2;
      BaseKnotMoveChildren(id, t1, p1, t2, p2);
   }
   else if(curT > 0 && curP > 0 && id == s_bkDragId && s_bkDragT0 > 0)
   {
      // Anchors frozen on this build — cursor-delta fallback (the press latch
      // belongs to s_bkDragId, so only that box may use it).
      int dt = (int)(curT - s_bkDragT0);
      double dp = curP - s_bkDragP0;
      BaseKnotMoveChildren(id,
         s_bkDragBT1 + dt, s_bkDragBP1 + dp,
         s_bkDragBT2 + dt, s_bkDragBP2 + dp);
   }
   else return;   // nothing moved and no cursor — skip the repaint too
   BaseKnotDragPaint();
}
void BaseKnotDelete(const string id)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx != "") ObjectsDeleteAll(0, pfx);   // one call wipes box + all children
   BaseKnotUnregister(id);
   ChartRedraw();
}
// Re-assert the border look on every committed box (Base Box card edits
// apply live; Lite-safe: mirrors + Object* calls only). Delegates to
// BaseKnotSync so the 4 edge segments (the visible border) follow too.
void BaseKnotRestyleAll()
{
   if(StringLen(inpObjectPrefix) == 0) return;
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      BaseKnotSync(g_bkBoxes[i].id);
   }
   ChartRedraw();
}
// Visible right now? Box exists AND its commit-TF mask covers the current
// chart TF (hidden-above boxes report false — UI side closes their strip).
bool BaseKnotVisibleNow(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   if(ObjectFind(0, BaseKnotBoxName(pfx)) < 0) return false;
   int tfMin = g_bkBoxes[k].tfMin;
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);
   return BaseKnotTFVisible(tfMin);
}
// Hit-test: id of the committed box containing (t,price), or "".
// UI side uses it for hold-on-box → settings (no UI deps here).
string BaseKnotBoxAt(const datetime t, const double price)
{
   if(t <= 0 || price <= 0 || StringLen(inpObjectPrefix) == 0) return "";
   BaseKnotLazyInit();
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
      double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
      if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
      double top = MathMax(p1, p2), bot = MathMin(p1, p2);
      if(t >= t1 && t <= t2 && price >= bot && price <= top) return g_bkBoxes[i].id;
   }
   return "";
}
// Per-tick (500 ms) re-glue: scroll/zoom moves pixel badges, box anchors don't.
void BaseKnotSyncBadges()
{
   BaseKnotLazyInit();   // the registry IS the box list — rebuild once (guarded, O(1) after)
   if(BaseKnotSessionActive()) BaseKnotReassertLock(true);   // P-BK-14: pump drift-heal (timer path, tick-less charts)
   if(s_bkDragLock && g_bkState == BK_IDLE &&
      (TerminalInfoInteger(TERMINAL_KEYSTATE_LEFT) & 1) == 0 &&
      GetTickCount() - s_bkDragActMs > 1500)
   {
      // Missed release (button up off-window, event stream silent): never
      // leave the view locked. The 1.5 s silence requirement keeps KEYSTATE
      // flicker mid-hold (P-BK-05) from false-triggering — a real drag keeps
      // producing events. KEYSTATE poll in the timer path is P-BK-03 pattern.
      s_bkDragId = ""; s_bkDragMoved = false;
      BaseKnotDragLockOff();
   }
   if(ArraySize(g_bkBoxes) == 0) return;
   datetime tpEdge = BaseKnotTPEdgeTime();   // chart-global: one conversion for the whole pump
   double bkRef = BaseKnotLiveRef();         // P-BK-13: one live price for every follow check below
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      // P-BK-15: hands off the actively-dragged box — MT4 cancels an
      // in-progress native drag when the object is rewritten mid-gesture, so
      // any pump Sync/heal/glue here snaps the box back to the drag start.
      // The release path Syncs authoritatively (dir flip included), so
      // nothing is lost by skipping these 500 ms rounds.
      if(s_bkDragId != "" && g_bkBoxes[i].id == s_bkDragId) continue;
      string pfx = BaseKnotPrefix(g_bkBoxes[i].id);
      if(pfx == "") continue;
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) < 0) continue;
      // P-BK-13 auto-follow: a stale side (committed long ago and crossed
      // since, or dragged across the price) flips here — one Sync rebuilds
      // Entry/SL/TP + tooltips. Inside keeps, so vibration never flickers.
      if(BaseKnotRefreshDirection(g_bkBoxes[i].id, bkRef))
      {
         BaseKnotSync(g_bkBoxes[i].id);
         if(g_bkState == BK_IDLE && BaseKnotVisibleNow(g_bkBoxes[i].id))
            BaseKnotHintShow("Base box -> " + (g_bkBoxes[i].dir >= 0 ? "BUY" : "SELL") + " (price crossed the box)", 3000);
         ChartRedraw();
      }
      // P-BK-05/06 self-heal + TV-fill 2026-09-07: the BOX rect is the fill
      // layer. Re-assert it within 500 ms when it drifts from the live fill
      // look (bg + FILL false when fill invisible) — read-guarded, so steady
      // state costs syscalls only. Missing edge segments (the visible
      // border) are rebuilt via a full Sync.
      if(!BaseKnotFillHealed(box))
      {
         BaseKnotStyleBox(box);
         ChartRedraw();
      }
      if(ObjectFind(0, pfx + BK_EDGE_T) < 0 || ObjectFind(0, pfx + BK_EDGE_B) < 0 ||
         ObjectFind(0, pfx + BK_EDGE_L) < 0 || ObjectFind(0, pfx + BK_EDGE_R) < 0 ||
         BaseKnotTPStale(pfx))   // pre-tick ray → rebuild
      {
         BaseKnotSync(g_bkBoxes[i].id);
         ChartRedraw();
      }
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
      double top = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      double bot = MathMin(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      int tfMin = g_bkBoxes[i].tfMin;
      if(tfMin <= 0) tfMin = BaseKnotIdTF(g_bkBoxes[i].id);
      if(tpEdge > 0 && BaseKnotTFVisible(tfMin)) BaseKnotTPGlue(pfx, tpEdge);   // right-edge hug, hidden-TF boxes skipped
      if(ObjectFind(0, BaseKnotTextName(pfx)) >= 0)   // user text re-glues with the box
         BaseKnotPlaceText(pfx, t1, t2, top, bot, BaseKnotTFMask(tfMin), "");
      if(BaseKnotInfoVisible(g_bkBoxes[i].id))
         BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin, BaseKnotTFMask(tfMin));
      else if(ObjectFind(0, BaseKnotInfoName(pfx)) >= 0)
      {
         ObjectDelete(0, BaseKnotInfoName(pfx));   // Auto grace over — hide within 500 ms
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| Commit click 2 → freeze the box, spawn Entry/SL/TP + badges.      |
//+------------------------------------------------------------------+
void BaseKnotCommit(const datetime t2, const double p2raw)
{
   double pt = GetCachedPoint();
   if(pt <= 0) pt = _Point;
   double p2 = BaseKnotSnapPrice(t2, p2raw);
   if(t2 <= 0) return;
   datetime tc = t2;
   if(tc == g_bkT1) tc = g_bkT1 + PeriodSeconds();   // same-bar drag: corner times snap to bar opens,
                                                     // so the honest box is one bar wide — never reject it
   if(tc < g_bkT1) { datetime tt = g_bkT1; g_bkT1 = tc; tc = tt; double pp = g_bkP1; g_bkP1 = p2; p2 = pp; }   // dragged right-to-left: store canonical corner order
   if(MathAbs(p2 - g_bkP1) < pt)   // a true point-click, not a box — say so instead of dying silent
   {
      BaseKnotHintShow("Too small — press + drag a real box (needs height + width)", 2000);
      return;
   }
   int tfMin = Period();
   string id = IntegerToString((long)tfMin) + "_" + IntegerToString((long)GetTickCount());
   while(BaseKnotFind(id) >= 0) id += "r" + IntegerToString(MathRand() % 1000);
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(!ObjectCreate(0, box, OBJ_RECTANGLE, 0, g_bkT1, g_bkP1, tc, p2)) return;
   BaseKnotStyleBox(box);   // fill layer + drag handle (ZORDER included) — the VISIBLE border is 4 edges drawn in Sync below
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, true);   // THE handle: drag moves children
   ObjectSetInteger(0, box, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, box, OBJPROP_TIMEFRAMES, BaseKnotTFMask(tfMin));
   ObjectSetString(0, box, OBJPROP_TOOLTIP, "Base box — drag to move (lines follow) · select + Delete key removes all");
   // Direction is AUTOMATIC at commit (no Buy/Sell badge): box below
   // the live price = demand = Buy; box above it = supply = Sell; a commit
   // landing with the price inside resolves by entry side (see resolver).
   // Afterwards it keeps following via BaseKnotRefreshDirection (P-BK-13).
   double bkTop = MathMax(g_bkP1, p2), bkBot = MathMin(g_bkP1, p2);
   int dir = BaseKnotResolveDirection(bkTop, bkBot);
   BaseKnotRegister(id, dir, tfMin);
   BaseKnotSync(id);
   BaseKnotWipePreview();
   BaseKnotWipeLive();
   g_bkState = BK_IDLE;   // single-shot: tool OFF after one box — stray clicks draw nothing
   g_bkHeld = false;
   BaseKnotUnlockChart();
   g_bkRestoreReq = true;   // UI side re-shows the hidden ring menu
   double hPips = BaseKnotToPips(MathAbs(p2 - g_bkP1));
   BaseKnotHintShow("BASE #" + IntegerToString(ArraySize(g_bkBoxes)) + " " +
                    (dir >= 0 ? "BUY" : "SELL") + " set (" +
                    DoubleToString(hPips, 1) + " pips)", 4000);   // result nags 4 s, then clean
   ChartRedraw();
}

// Press (MOUSE_MOVE rising edge, or a CLICK when no press edge was seen —
// some builds/mice emit no clean rising edge): ARMED → corner 1. Never
// commits — the release (or the next click) is corner 2.
void BaseKnotPress(const datetime t, const double praw)
{
   if(g_bkState != BK_ARMED) return;
   uint now = GetTickCount();
   if(now - g_bkArmedMs < BK_ARM_GUARD) return;      // the arming click's own echo (CLICK path only)
   double p = BaseKnotSnapPrice(t, praw);
   g_bkT1 = t; g_bkP1 = p;
   g_bkLiveT = t; g_bkLiveP = p;
   g_bkHeld = true;
   g_bkState = BK_PREVIEW;
   string pv = BaseKnotPrevTag();
   if(pv == "") return;
   ObjectDelete(0, pv);   // legacy single-rect preview (pre-P-BK-06) — edges replace it
   BaseKnotDrawEdges(pv, t, p, t, p,
                     GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth,   // preview wears the final look (no fill yet)
                     "Base box sizing — release / second click to commit", BaseKnotTFMask(Period()));
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Master event entry — call FIRST in OnChartEventHandler; true =    |
//| consumed (caller must return immediately, no chart-click leak).   |
//+------------------------------------------------------------------+
bool BaseKnotOnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   BaseKnotLazyInit();
   string tag = (StringLen(inpObjectPrefix) > 0 ? inpObjectPrefix + BK_TAG : "");

   //--- BK clicks die here (any state, incl. IDLE) so they never reach menus.
   //--- Direction is automatic (box below live price = Buy, above = Sell).
   //--- NOBKDEL: no X badge is created anymore; a DEL click below only fires
   //--- for pre-retire badges and still deletes the box (then purges).
   if(id == CHARTEVENT_OBJECT_CLICK && tag != "")
   {
      if(StringFind(sparam, tag) == 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         string bid = "", kind = "";
         BaseKnotSplitTail(tail, bid, kind);   // LAST underscore: ids hold one too
         if(kind == "DEL")
         {
            int k = BaseKnotFind(bid);
            BaseKnotDelete(bid);   // unknown id → still wipe by prefix
            if(k < 0 && tag != "")
            {
               ObjectsDeleteAll(0, tag + bid + "_");
               ChartRedraw();
            }
            return true;
         }
         if(kind == "BUY") { ObjectDelete(0, sparam); return true; }   // NOBUYSELL leftover
         if(kind == "") return true;   // PREVIEW/HINT tails — swallow, no action
         return true;   // clicks on box/lines/info text die here — never reach menus
      }
   }

   //--- box drag → children follow; box delete → cascade; child delete → heal
   if(id == CHARTEVENT_OBJECT_DRAG && tag != "" && StringFind(sparam, tag) == 0 &&
      StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
   {
       string tail = StringSubstr(sparam, StringLen(tag));
       string bid = StringSubstr(tail, 0, StringLen(tail) - 4);
       if(bid == "PREVIEW") return true;
        if(BaseKnotFind(bid) >= 0)
        {
           if(BaseKnotLocked(bid)) return true;   // locked — swallow, children stay put
           // Unified lean follow (P-BK-07): anchor-exact moves only — never a
           // full Sync per step (its style/tooltip rewrites lagged children
           // behind the native BOX on heavy charts). This event carries no
           // trusted cursor (in-repo pattern: TH3Tool reads live anchors here
           // too), so it is anchor-exact only — the cursor fallback rides the
           // MOUSE_MOVE channel. Release still does the authoritative Sync.
           if(bid != s_bkDragId)
           {
              // Overlap hole: the press latched another box — adopt the
              // actually-dragged one (cursor base stays: same press point).
              string abox = BaseKnotBoxName(BaseKnotPrefix(bid));
              if(ObjectFind(0, abox) >= 0)
              {
                 s_bkDragId = bid; s_bkDragMoved = true;
                 LOG_IP1(LOG_CAT_DRAW, "BK drag adopt ", bid);   // diag: terminal drags a box the press missed
                 BaseKnotDragLockOn();   // definitively dragging — freeze the view
                 s_bkDragBT1 = (datetime)ObjectGetInteger(0, abox, OBJPROP_TIME, 0);
                 s_bkDragBT2 = (datetime)ObjectGetInteger(0, abox, OBJPROP_TIME, 1);
                 s_bkDragBP1 = ObjectGetDouble(0, abox, OBJPROP_PRICE, 0);
                 s_bkDragBP2 = ObjectGetDouble(0, abox, OBJPROP_PRICE, 1);
                    s_bkFolT1 = s_bkDragBT1; s_bkFolT2 = s_bkDragBT2;
                    s_bkFolP1 = s_bkDragBP1; s_bkFolP2 = s_bkDragBP2;
                }
             }
            BaseKnotFollowDrag(bid, 0, 0);
         }
         else
         {
            // Diag: a BK BOX is being dragged but the registry doesn't know
            // it — children can't follow. Throttled: DRAG fires per step.
            static string s_bkDiagUnk = "";
            static uint s_bkDiagUnkMs = 0;
            uint unow = GetTickCount();
            if(bid != s_bkDiagUnk || unow - s_bkDiagUnkMs > 5000)
            { s_bkDiagUnk = bid; s_bkDiagUnkMs = unow; LOG_WP1(LOG_CAT_DRAW, "BK drag: box not in registry ", bid); }
         }
         return true;
    }
   if(id == CHARTEVENT_OBJECT_DELETE && tag != "" && StringFind(sparam, tag) == 0)
   {
      string ltag = BaseKnotLiveTag();
      if(ltag != "" && StringFind(sparam, ltag) == 0) return true;   // live sizing set — owned by the draw flow
      // Only the BOX triggers the cascade (children deletes re-enter as no-ops).
      if(StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         string bid = StringSubstr(tail, 0, StringLen(tail) - 4);
         if(bid == "PREVIEW" || bid == "HINT") return true;
         BaseKnotDelete(StringSubstr(tail, 0, StringLen(tail) - 4));
      }
       else
       {
          // A manually deleted child (ENTRY/SL/TP/INFO/edge, or a pre-retire
          // DEL) self-heals via re-sync; trailing deletes of an already-gone box just mop up.
          // Edge segments (P-BK-06 visible border) end with _T/_B/_L/_R — strip
          // to the parent id first (SplitTail would cut at the wrong underscore).
          int slen = StringLen(sparam);
          if(slen >= 2 &&
             (StringSubstr(sparam, slen - 2) == BK_EDGE_T || StringSubstr(sparam, slen - 2) == BK_EDGE_B ||
              StringSubstr(sparam, slen - 2) == BK_EDGE_L || StringSubstr(sparam, slen - 2) == BK_EDGE_R))
          {
             string tailE = StringSubstr(sparam, StringLen(tag));
             string bidE = StringSubstr(tailE, 0, StringLen(tailE) - 2);   // drop "_X"
             if(StringLen(bidE) > 0 && StringSubstr(bidE, StringLen(bidE) - 1) == "_")
                bidE = StringSubstr(bidE, 0, StringLen(bidE) - 1);          // drop pfx trailing "_"
             if(BaseKnotFind(bidE) >= 0)
             {
                string pfxE = BaseKnotPrefix(bidE);
                if(ObjectFind(0, BaseKnotBoxName(pfxE)) >= 0) BaseKnotSync(bidE);
                else BaseKnotDelete(bidE);
                ChartRedraw();
             }
             return true;
          }
          string tail = StringSubstr(sparam, StringLen(tag));
         string bid = "", kind = "";
         BaseKnotSplitTail(tail, bid, kind);
         if(kind == "") return true;   // PREVIEW/HINT transient — swallow
         if(BaseKnotFind(bid) >= 0)
         {
            string pfx = BaseKnotPrefix(bid);
            if(ObjectFind(0, BaseKnotBoxName(pfx)) >= 0) BaseKnotSync(bid);
            else BaseKnotDelete(bid);
            ChartRedraw();
         }
         else if(bid != "")
         {
            // Trailing delete of an already-removed box (or a half-built
            // orphan): mop up by prefix, no redraw — the BOX branch redraws.
            ObjectsDeleteAll(0, BaseKnotPrefix(bid));
         }
      }
      return true;
   }

   //--- view moved under pixel badges → re-glue (never consumed)
   if(id == CHARTEVENT_CHART_CHANGE) { BaseKnotSyncBadges(); return false; }

   //--- ESC leaves the session from anywhere
   if(id == CHARTEVENT_KEYDOWN && lparam == 27 && BaseKnotSessionActive())
   {
      BaseKnotCancel();
      return true;
   }

    //--- IDLE box-drag follow (unified lean follow, P-BK-07): the terminal
    //--- moves the BOX natively, children follow through BaseKnotFollowDrag —
    //--- anchor-exact while anchors move, cursor-delta fallback while frozen
    //--- (build-dependent). One 30ms budget for moves + paint, then one
    //--- authoritative BaseKnotSync from the committed anchors on release.
    //--- Never consumes — menus/panels/hold still see every move (Lite-safe:
    //--- Object* only).
   if(id == CHARTEVENT_MOUSE_MOVE && g_bkState == BK_IDLE)
   {
      int sst = (int)StringToInteger(sparam);
      bool sleft = ((sst & 1) != 0);
      bool srising = (sleft && !g_bkLeftPrev);
      bool sfalling = (!sleft && g_bkLeftPrev);
      g_bkLeftPrev = sleft;
       if(srising)
       {
          s_bkDragId = ""; s_bkDragMoved = false; s_bkDragActMs = GetTickCount();
         int ssw = 0; datetime sct = 0; double scp = 0;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, ssw, sct, scp) && ssw == 0 && sct > 0 && scp > 0)
         {
            string shit = BaseKnotBoxAt(sct, scp);
            if(shit != "" && BaseKnotFind(shit) >= 0 && !BaseKnotLocked(shit))
            {
               string shbox = BaseKnotBoxName(BaseKnotPrefix(shit));
               if(ObjectFind(0, shbox) >= 0)
               {
                  s_bkDragId = shit;
                  s_bkDragT0 = sct; s_bkDragP0 = scp;
                  s_bkDragX0 = (int)lparam; s_bkDragY0 = (int)dparam;
                   s_bkDragBT1 = (datetime)ObjectGetInteger(0, shbox, OBJPROP_TIME, 0);
                   s_bkDragBT2 = (datetime)ObjectGetInteger(0, shbox, OBJPROP_TIME, 1);
                    s_bkDragBP1 = ObjectGetDouble(0, shbox, OBJPROP_PRICE, 0);
                    s_bkDragBP2 = ObjectGetDouble(0, shbox, OBJPROP_PRICE, 1);
                    s_bkFolT1 = s_bkDragBT1; s_bkFolT2 = s_bkDragBT2;
                    s_bkFolP1 = s_bkDragBP1; s_bkFolP2 = s_bkDragBP2;
                    LOG_IP1(LOG_CAT_DRAW, "BK drag latch ", shit);   // diag: press found a box — follow armed
                }
            }
         }
      }
      else if(sfalling)
      {
         // Release after a REAL drag: authoritative final from committed anchors
         // (guarantees "correct on release" even where no mid-drag event fired).
         // A tap (no move) syncs nothing — tap-select stays untouched.
         // Overlap hole: the press candidate may differ from the truly dragged
         // box — the drop point is under the cursor, so sync that box too.
          if(s_bkDragId != "" && s_bkDragMoved)
          {
              LOG_IP1(LOG_CAT_DRAW, "BK drag release sync ", s_bkDragId);   // diag: authoritative final
              bool painted = false;
             double relRef = BaseKnotLiveRef();   // P-BK-13: a drag across the price flips NOW, not 500 ms later
             int ssw3 = 0; datetime sct3 = 0; double scp3 = 0;
             if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, ssw3, sct3, scp3) && ssw3 == 0 && sct3 > 0 && scp3 > 0)
             {
                string sdrop = BaseKnotBoxAt(sct3, scp3);
                if(sdrop != "" && sdrop != s_bkDragId && BaseKnotFind(sdrop) >= 0 && !BaseKnotLocked(sdrop))
                {
                   BaseKnotRefreshDirection(sdrop, relRef);
                   BaseKnotSync(sdrop);
                   painted = true;
                }
             }
             if(BaseKnotFind(s_bkDragId) >= 0)
             {
                BaseKnotRefreshDirection(s_bkDragId, relRef);
                BaseKnotSync(s_bkDragId);
                painted = true;
             }
            if(painted) ChartRedraw();
          }
          s_bkDragId = ""; s_bkDragMoved = false;
          BaseKnotDragLockOff();   // gesture over — hand the view back (self-guarded)
       }
      else if(sleft && s_bkDragId != "")
      {
         if(BaseKnotFind(s_bkDragId) < 0) { s_bkDragId = ""; s_bkDragMoved = false; }
         else
         {
            int smx = (int)lparam, smy = (int)dparam;
            if(!s_bkDragMoved &&
               MathAbs(smx - s_bkDragX0) <= BK_DRAG_SLOP && MathAbs(smy - s_bkDragY0) <= BK_DRAG_SLOP)
            {
               // still inside press slop — a hold, not a drag (strip may open)
            }
             else
             {
                s_bkDragMoved = true;
                BaseKnotDragLockOn();   // past slop = real drag: freeze the view like MT4's own tools
                // Cursor-carrying channel (MOUSE_MOVE coords are trusted —
                // OBJECT_DRAG's are not, so that branch is anchor-exact only).
                // Same unified follow; the shared 30ms gate inside absorbs
                // duplicates, so the channels never fight and neither starves.
                int ssw2 = 0; datetime sct2 = 0; double scp2 = 0;
                if(ChartXYToTimePrice(0, smx, smy, ssw2, sct2, scp2) && ssw2 == 0 && sct2 > 0 && scp2 > 0)
                   BaseKnotFollowDrag(s_bkDragId, sct2, scp2);
             }
         }
      }
   }

   if(!BaseKnotSessionActive()) return false;

   //--- right-click cancels (both encodings MT4 uses)
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      if((st & 2) != 0) { BaseKnotCancel(); return true; }
   }
   if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") >= 0) { BaseKnotCancel(); return true; }

   //--- press / drag / release (native-like). Rising = corner 1 on PRESS;
   //--- held moves = live preview; falling (release) = commit at release.
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      bool left = ((st & 1) != 0);
      bool rising  = (left && !g_bkLeftPrev);
      bool falling = (!left && g_bkLeftPrev);
      g_bkLeftPrev = left;
      if(rising)
      {
         if(g_bkState == BK_ARMED)
         {
            int sw = 0; datetime ct = 0; double cp = 0;
            if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
               BaseKnotPress(ct, cp);
         }
         else if(g_bkState == BK_PREVIEW)
            g_bkHeld = true;   // corner-2 drag begins (corner 1 stays)
         return true;
      }
      if(falling)
      {
         if(g_bkState == BK_PREVIEW)
         {
            g_bkHeld = false;
            int sw = 0; datetime ft = 0; double fp = 0;
            if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ft, fp) && sw == 0 && ft > 0 && fp > 0)
               BaseKnotCommit(ft, fp);
            else if(g_bkLiveT > 0)
               BaseKnotCommit(g_bkLiveT, g_bkLiveP);   // released off-chart → last seen point
         }
         return true;
      }
      //--- rubber-band: live preview follows the cursor while HELD (drag)
      //--- and while hovering (tap-tap sizing) — zero indicator work.
      //--- throttled: a mouse-move storm must never pin the CPU (30 ms ≈ 33 fps).
      if(g_bkState == BK_PREVIEW)
      {
         static uint s_bkRubberMs = 0;
         uint nowR = GetTickCount();
         if(nowR - s_bkRubberMs < 30) return true;   // swallow, skip the redraw
         s_bkRubberMs = nowR;
         BaseKnotReassertLock(true);   // P-BK-14: the session owns the view until commit/cancel
         int sw = 0; datetime ht = 0; double hp = 0;
         string pv = BaseKnotPrevTag();
         if(pv != "" && ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ht, hp) && sw == 0 && ht > 0 && hp > 0)
         {
            hp = BaseKnotSnapPrice(ht, hp);   // click = corner (magnet off — identity)
            ObjectDelete(0, pv);   // legacy single-rect preview — edges only from P-BK-06
            BaseKnotDrawEdges(pv, g_bkT1, g_bkP1, ht, hp,
                              GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth,   // preview wears the final look (no fill yet)
                              "Base box sizing — release / second click to commit", BaseKnotTFMask(Period()));
             g_bkLiveT = ht; g_bkLiveP = hp;
             BaseKnotSyncLive(ht, hp);   // Entry/SL/TP + info follow while sizing
            ChartRedraw();
         }
         return true;
      }
      return (g_bkState == BK_PREVIEW);   // swallow moves mid-gesture, ignore idle hovers
   }

   //--- CLICK fallback (tap path + builds with no clean press/release edge:
   //--- ARMED+CLICK = corner 1, PREVIEW+CLICK = corner 2 commit; after a
   //--- drag-release commit the state is IDLE so the trailing CLICK dies).
   if(id == CHARTEVENT_CLICK)
   {
      int sw = 0; datetime ct = 0; double cp = 0;
      if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
      {
         if(g_bkState == BK_ARMED)
            BaseKnotPress(ct, cp);
         else if(g_bkState == BK_PREVIEW)
         {
            g_bkHeld = false;
            BaseKnotCommit(ct, cp);
         }
      }
      return true;
   }

   return false;
}

#endif // BASE_KNOT_TOOL_MQH
