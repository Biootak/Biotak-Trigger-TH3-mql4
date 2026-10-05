//+------------------------------------------------------------------+
//| PathTool.mqh — Path (TradingView Path parity).                    |
//+------------------------------------------------------------------+
//| LAYER: drawing/domain (no UI deps - compiles in Full AND Lite).   |
//| Arm → click adds a vertex, segments join consecutive vertices →   |
//| double-click (a still click within 400 ms/6 px of the last)       |
//| commits the path and disarms. IDLE: a click on a segment SELECTS |
//| the path (its dot lands on the free end) and a press near a       |
//| segment carries the WHOLE path. The DELETE lives on that dot      |
//| alone (P-UI-136: one pixel cannot host two gestures). ESC cancels |
//| the session (or restores a live drag), right-click cancels the arm.|
//+------------------------------------------------------------------+
#ifndef PATH_TOOL_MQH
#define PATH_TOOL_MQH

#define PATH_TAG "_PATH_"
#define PATH_COLOR clrRoyalBlue
#define PATH_WIDTH 2
#define PATH_STYLE STYLE_SOLID
#define PATH_GRAB_PX 8
#define PATH_DBL_MS 400
#define PATH_DBL_PX 6
#define PATH_DOT_PX 14    // the SELECT dot's grab radius (HRay's dot reads GRAB+4)
#define PATH_PREVIEW_TAG "PREVIEW"

// P-LOG-3 (AGENTS law 3): a witness is the FLUSHED file, never `Print` — MT4
// buffers the journal in RAM and a Print witness reads "nothing happened" long
// after the tap (P-DRAW-126). `DrawStripDiagEmit` is the channel's ONE owner
// (DrawStrip_Base.mqh), and it is BORROWED by name here: the path opens no
// second file and writes no second format.
#ifndef BUILD_LITE
// P-WARN-46 (2026-10-04): the prototype that stood here was the build's last warning 46
// in this file. A prototype is the IMPORT MQL4 needs for an #import-ed library, not for a
// body later in the same unit - MQL4 resolves that on its own (see the note in Toolbar_A).
void PathWitness(const string line) { DrawStripDiagEmit("[Path] " + line); }
#else
// Lite ships no draw strip, so it ships no diag channel — MQL4 rejects a
// prototype with no body anywhere in the unit (error 111), so the Lite witness
// is the journal. Same bytes, one owner per build.
void PathWitness(const string line) { Print("[Path] " + line); }
#endif

static bool   s_pathArmed       = false;
static bool   s_pathLeft        = false;
static string s_pathDrag        = "";      // path id under the hand ("" = no drag)
static bool   s_pathMoved       = false;
static datetime s_pathSnapT     = 0;       // cursor time under the press (drag origin)
static double s_pathSnapP       = 0.0;     // ... and price
static int    s_pathPressX      = 0;
static int    s_pathPressY      = 0;
static string s_pathSnapNames[];           // drag: segment names
static int    s_pathSnapIx[];             // ... and WHICH anchor each one moves:
                                           // 0 = point0 · 1 = point1 · 2 = both (the whole path)
static datetime s_pathSnapT0[];
static double s_pathSnapP0[];
static datetime s_pathSnapT1[];
static double s_pathSnapP1[];
static string s_pathIds[];                 // registry of committed path ids
static string s_pathSel      = "";        // the SELECTED path (the dot's owner)
static string s_pathClick     = "";        // P-UI-146: nothing arms a delete on the chart any more
static uint   s_pathEndMs     = 0;         // the last carry that MOVED (its trailing click reads it)
static datetime s_pathAnchorT = 0;         // last committed vertex (session live)
static double s_pathAnchorP   = 0.0;
static int    s_pathSegCount  = 0;         // committed segments of the live session
static string s_pathSessionId = "";        // live session's id
static uint   s_pathLastVerMs = 0;         // last committed-vertex click stamp
static int    s_pathLastVerX  = 0;
static int    s_pathLastVerY  = 0;
static uint   s_pathNoGrabMs  = 0;       // P-UI-142: the terminal's own motion forbids our grab
static bool   s_pathPrimed    = false;   // ...and the carry writes NOTHING until it knows
static datetime s_pathPrimT   = 0;       // the gesture is ours (the first move is buffered)
static double s_pathPrimP     = 0.0;
// P-UI-142: is OUR grab allowed to start at all? The terminal's own motion is
// answered by the SHARED arbiter (GlobalVariables.mqh — the project-wide owner, so
// the ray, Base/Knot, TH3 and the leg measure ask the same question and cannot drift
// from this copy). What is left is the OTHER half of P-HR-06's «one gesture at a
// time»: another session of ours that is ARMED owns the press. Cost: one deadline
// read and, in Full, up to three bools — per PRESS, never per tick.
bool PathGrabBlocked()
{
   if(GestureGrabBlocked()) return true;
   if(BaseKnotSessionActive() || HRaySessionActive()) return true;
#ifndef BUILD_LITE
   if(TH3SessionActive() || LegMeasureSessionActive()) return true;
#endif
   return false;
}

bool PathSessionActive() { return s_pathArmed; }
bool PathViewOwned() { return (s_pathArmed || s_pathDrag != ""); }
void PathArm()
{
   if(s_pathArmed) return;
   GestureTakeRelease();   // P-UI-144: a NEW drawing is never gated by the last one — the
                           // arbiter's ONE question is per drawing, so arming clears it
   s_pathArmed = true; ChartViewLockAcquire(); ChartRedraw();
}
void PathCancel()
{
   if(!s_pathArmed) return;
   s_pathArmed = false;
   ChartViewLockRelease();
   ChartRedraw();
}
string PathPrefix()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + PATH_TAG;
}
string PathSegName(const string id, const int i) { return PathPrefix() + id + "_" + IntegerToString(i); }
string PathPreviewName() { return PathPrefix() + PATH_PREVIEW_TAG; }
int PathSegCount(const string id)
{
   int n = 0;
   for(int i = 0; i < 256; i++)
   {
      if(ObjectFind(0, PathSegName(id, i)) < 0) break;
      n++;
   }
   return n;
}
void PathRegAdd(const string id)
{
   for(int i = 0; i < ArraySize(s_pathIds); i++)
      if(s_pathIds[i] == id) return;
   int n = ArraySize(s_pathIds);
   ArrayResize(s_pathIds, n + 1);
   s_pathIds[n] = id;
}
// P-UI-136 — THE VERTEX HANDLES. HRay parity, one shape: the drawing carries the
// handle, the handle owns the delete, and the drawing's own pixels mean only
// "take me" (HRayHandleName/HRayIsHandle/HRaySelect). A path wears one handle per
// VERTEX (n segments = n+1 points, the free end included), so a press on a
// handle edits that point — and a press on a segment only SELECTS (P-UI-145).
// The `H` in the name keeps `PathIdOfName` from reading a handle as a SEGMENT (its
// tail is not digits), so the orphan walk and the delete watcher skip it without
// a second test.
string PathHandleName(const string id, const int k) { return PathPrefix() + id + "_H" + IntegerToString(k); }
bool PathIsHandle(const string nm)
{
   string pfx = PathPrefix();
   if(pfx == "" || StringFind(nm, pfx) != 0) return false;
   string rest = StringSubstr(nm, StringLen(pfx));
   int ulast = -1;
   for(int i = 0; i < StringLen(rest); i++)
      if(StringGetChar(rest, i) == 95) ulast = i;
   return (ulast > 0 && ulast + 1 < StringLen(rest) && StringGetChar(rest, ulast + 1) == 72);   // 'H'
}
// The handles go with the path, always as one family (P-LOG-10 law 4). It sits ABOVE
// PathRegDel on purpose: P-UI-146 makes the registrar the one sweep, and MQL4 has no
// prototype that is not a warning (warning 46), so the order carries the dependency.
void PathHandlesDrop(const string id)
{
   int m = PathSegCount(id);
   for(int k = 0; k <= m; k++) ObjectDelete(0, PathHandleName(id, k));
}
void PathRegDel(const string id)
{
   //--- P-UI-146 (2026-10-02, user: «ابزار path که حذف میشه وابتگی‌هاهم حذف بشه» — the
   //--- screenshot showed five blue dots and no lines): the sweep lives HERE, in the one
   //--- function that means «this path no longer exists», so no route can forget it. Three
   //--- routes ended a path and only two took the dots with them: PathDelete dropped the
   //--- handles of whatever was SELECTED (PathSelect("")), not of the path it was deleting,
   //--- and the cascade at the OBJECT_DELETE watcher deregistered with no sweep at all. A
   //--- child outliving its parent is the orphan class this closes.
   PathHandlesDrop(id);
   if(s_pathSel == id) s_pathSel = "";
   int n = ArraySize(s_pathIds);
   for(int i = 0; i < n; i++)
      if(s_pathIds[i] == id)
      {
         for(int j = i; j < n - 1; j++) s_pathIds[j] = s_pathIds[j + 1];
         ArrayResize(s_pathIds, n - 1);
         return;
      }
}
// The handles go with the path, always as one family (P-LOG-10 law 4).
void PathSelect(const string id)
{
   if(s_pathSel != "" && s_pathSel != id) PathHandlesDrop(s_pathSel);
   s_pathSel = id;
   s_pathClick = "";   // a selection is not a delete witness — HRaySelect's rule
}
// Vertex k of the path: k=0 is the first segment's anchor, k=n the free end, and
// every k in between is the shared point of segments k-1 and k.
bool PathVertex(const string id, const int k, datetime &t, double &p)
{
   t = 0; p = 0.0;
   int n = PathSegCount(id);
   if(n <= 0 || k < 0 || k > n) return false;
   int si = (k == n ? n - 1 : k);
   int pt = (k == n ? 1 : 0);
   string nm = PathSegName(id, si);
   if(ObjectFind(0, nm) < 0) return false;
   t = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, pt);
   p = ObjectGetDouble(0, nm, OBJPROP_PRICE, pt);
   return (t > 0 && p > 0);
}
// One handle, placed. Off-path or unselected -> the handle does not exist (an
// unselected chart wears no circles, P-HR-03's rule).
void PathHandleAt(const string id, const int k)
{
   string hn = PathHandleName(id, k);
   if(id == "" || id != s_pathSel) { ObjectDelete(0, hn); return; }
   datetime t = 0; double p = 0.0;
   if(!PathVertex(id, k, t, p)) { ObjectDelete(0, hn); return; }
   int x = 0, y = 0;
   if(!(p > 0) || !ChartTimePriceToXY(0, 0, t, p, x, y))
      HandsetHandleAtXY(hn, HANDSET_HANDLE_PARK, HANDSET_HANDLE_PARK, CP_HANDLE_HALF, CP_HANDLE_RES);
   else
      HandsetHandleAtXY(hn, x, y, CP_HANDLE_HALF, CP_HANDLE_RES);
}
// The whole set, in one pass — the seat every gesture re-reads. Cost: one
// ChartTimePriceToXY per vertex, on gesture events only (never on a tick). ONE
// name for the job, so no caller can re-place only the free end.
void PathHandleFollow(const string id)
{
   if(id == "" || id != s_pathSel) return;
   if(PathSegCount(id) <= 0) { PathSelect(""); return; }   // the path died: the handles go with it
   PathHandlesFollowAll(id);
}
void PathHandlesFollowAll(const string id)
{
   int n = PathSegCount(id);
   for(int k = 0; k <= n; k++) PathHandleAt(id, k);
}
// The handle's own hit test — the ONLY surface that can answer "remove", and the
// only surface that can answer "move this point".
bool PathDotHit(const int mx, const int my, string &id, int &k)
{
   id = ""; k = -1;
   if(s_pathSel == "") return false;
   int n = PathSegCount(s_pathSel);
   int best = 0x7fff;
   for(int i = 0; i <= n; i++)
   {
      if(ObjectFind(0, PathHandleName(s_pathSel, i)) < 0) continue;
      datetime t = 0; double p = 0.0;
      if(!PathVertex(s_pathSel, i, t, p)) continue;
      int x = 0, y = 0;
      if(!ChartTimePriceToXY(0, 0, t, p, x, y)) continue;
      int d = (int)MathSqrt((double)((mx - x) * (mx - x) + (my - y) * (my - y)));
      if(d <= PATH_DOT_PX && d < best) { best = d; k = i; }
   }
   if(k < 0) return false;
   id = s_pathSel;
   return true;
}
bool PathIdOfName(const string nm, string &id)
{
   string pfx = PathPrefix();
   if(pfx == "" || StringFind(nm, pfx) != 0) return false;
   string rest = StringSubstr(nm, StringLen(pfx));
   // last underscore splits the segment index; the id itself must be all digits
   int ulast = -1;
   for(int i = 0; i < StringLen(rest); i++)
      if(StringGetChar(rest, i) == 95) ulast = i;
   if(ulast <= 0) return false;
   string maybeIdx = StringSubstr(rest, ulast + 1);
   for(int i = 0; i < StringLen(maybeIdx); i++)
      if(StringGetChar(maybeIdx, i) < 48 || StringGetChar(maybeIdx, i) > 57) return false;
   id = StringSubstr(rest, 0, ulast);
   return (id != "" && id != PATH_PREVIEW_TAG);
}
string PathTooltip(const int segs)
{
   return "Path · " + IntegerToString(segs + 1) + " points — click to select, drag to move — double-click the dot to remove";
}
void PathDelete(const string id, const string why)
{
   PathWitness("delete id=" + id + " segs=" + IntegerToString(PathSegCount(id)) + " why=" + why);
   if(s_pathDrag == id) PathDragRelease();
   PathSelect("");                       // every handle is the path's CHILD (P-HR-07's rule, one way)
   int n = PathSegCount(id);
   for(int i = 0; i < n; i++) ObjectDelete(0, PathSegName(id, i));
   PathRegDel(id);
   PathInkForget(id);            // P-UI-137: the ink row dies with its path (no leak)
   PathMidDrop(id);              // P-UI-139: ...and its 50 % markers with it (one sweep)
   if(s_pathDrag == id) s_pathDrag = "";
   if(s_pathClick == id) s_pathClick = "";
   ChartRedraw();
}
void PathSessionClear()
{
   string pfx = PathPrefix();
   if(pfx != "" && s_pathSessionId != "")
      for(int i = 0; i < s_pathSegCount; i++) ObjectDelete(0, PathSegName(s_pathSessionId, i));
   ObjectDelete(0, PathPreviewName());
   s_pathAnchorT = 0; s_pathAnchorP = 0;
   s_pathSegCount = 0;
   s_pathSessionId = "";
   s_pathLastVerMs = 0;
}
int PathPointToSegPx(const int mx, const int my, const datetime t1, const double p1, const datetime t2, const double p2)
{
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   if(!ChartTimePriceToXY(0, 0, t1, p1, x1, y1)) return 0x7fff;
   if(!ChartTimePriceToXY(0, 0, t2, p2, x2, y2)) return 0x7fff;
   double dx = (double)(x2 - x1), dy = (double)(y2 - y1);
   double len2 = dx * dx + dy * dy;
   double u = 0;
   if(len2 > 0) u = ((mx - x1) * dx + (my - y1) * dy) / len2;
   if(u < 0) u = 0; if(u > 1) u = 1;
   double px = x1 + u * dx, py = y1 + u * dy;
   return (int)MathSqrt((px - mx) * (px - mx) + (py - my) * (py - my));
}
bool PathPressHit(const int mx, const int my, string &id)
{
   int best = 0x7fff;
   for(int i = 0; i < ArraySize(s_pathIds); i++)
   {
      int n = PathSegCount(s_pathIds[i]);
      for(int s = 0; s < n; s++)
      {
         string nm = PathSegName(s_pathIds[i], s);
         if(ObjectFind(0, nm) < 0) continue;
         datetime t1 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
         double   p1 = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
         datetime t2 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1);
         double   p2 = ObjectGetDouble(0, nm, OBJPROP_PRICE, 1);
         int d = PathPointToSegPx(mx, my, t1, p1, t2, p2);
         if(d <= PATH_GRAB_PX && d < best) { best = d; id = s_pathIds[i]; }
      }
   }
   return (id != "");
}
void PathPreviewMove(const datetime t, const double p)
{
   if(s_pathAnchorT <= 0 || !(s_pathAnchorP > 0)) return;
   string nm = PathPreviewName();
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_TREND, 0, s_pathAnchorT, s_pathAnchorP, t, p);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, PATH_COLOR);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, PATH_WIDTH);
   ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_BOX_RAY);
   ObjectMove(0, nm, 0, s_pathAnchorT, s_pathAnchorP);
   ObjectMove(0, nm, 1, t, p);
}
void PathNormalise(const string id)
{
   int n = PathSegCount(id);
   for(int i = 0; i < n; i++)
   {
      string nm = PathSegName(id, i);
      if(ObjectFind(0, nm) < 0) continue;
      if((bool)ObjectGetInteger(0, nm, OBJPROP_SELECTABLE))
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      if((bool)ObjectGetInteger(0, nm, OBJPROP_SELECTED))
         ObjectSetInteger(0, nm, OBJPROP_SELECTED, false);
   }
}
void PathAdoptOrphans()
{
   string pfx = PathPrefix();
   if(pfx == "") return;
   int n = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < n; i++)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, pfx) != 0) continue;
      string id;
      if(!PathIdOfName(nm, id))
      {
         //--- P-UI-146 (2026-10-02, user: «ابزار path که حذف میشه وابتگی‌هاهم حذف بشه» —
         //--- the screenshot was five blue dots and no lines): a VERTEX DOT whose path has no
         //--- segments left is an orphan. Two older builds wrote them: their delete routes
         //--- swept only the selection, not the path being deleted, and this walk could never
         //--- see them again because `PathIdOfName` rightly refuses to read a handle as a
         //--- segment. So the sweep lives here, where the family is already being walked, and
         //--- it costs one string scan per prefixed object ONCE per attach.
         if(PathIsHandle(nm))
         {
            string rest = StringSubstr(nm, StringLen(pfx));
            int us = -1;
            for(int c = 0; c < StringLen(rest); c++)
               if(StringGetChar(rest, c) == 95) us = c;
            if(us > 0 && PathSegCount(StringSubstr(rest, 0, us)) == 0) ObjectDelete(0, nm);
         }
         continue;
      }
      PathRegAdd(id);
      PathNormalise(id);
   }
}
// P-UI-136 — THE STRIP WRITES THE WHOLE PATH, NEVER ONE SEGMENT. The strip's slot
// writer aims at ONE name (`DrawSlotWrite(name, …)`), and a path is N segments: a
// colour or a width that reached only the segment under the hand would leave the
// drawing two-toned. So this is the ONE fan-out the path owns — the strip calls
// it instead of ObjectSetInteger, and every sibling inherits the write in the
// same pass. Cost: one ObjectSetInteger per sibling, on a user action.
void PathFamilySet(const string segName, const int prop, const long value)
{
   ObjectSetInteger(0, segName, (ENUM_OBJECT_PROPERTY_INTEGER)prop, value);
   string id;
   if(!PathIdOfName(segName, id)) return;
   int n = PathSegCount(id);
   for(int i = 0; i < n; i++)
   {
      string sib = PathSegName(id, i);
      if(sib == segName) continue;
      ObjectSetInteger(0, sib, (ENUM_OBJECT_PROPERTY_INTEGER)prop, value);
   }
}
// P-UI-137 — THE PATH'S OWN INK + OPACITY STORE. Every OTHER drawing keeps its pure
// colour and its `[OP…]` alpha in a DESCRIPTION TAG on the object; a path segment
// is an OBJ_TREND and MT4 PAINTS OBJPROP_TEXT along the line, so a tag would draw
// "#RRGGBB" on the chart (the same law that gives the colour slot its plain ink).
// So the path keeps the two numbers in a file-scope store, one row per path id:
//   PURE colour (what the user chose - the HEX field and the readout read THIS)
//   opacity 0..100 (100 = full, the same direction as `[OP…]`)
// and every SEGMENT wears the blend. Cost: a scan over a handful of store rows (no
// object reads) plus ONE blend, then n ObjectSetInteger for n segments - a 3-point
// path is 2 writes - on the slider's own step, never on a tick.
static string s_pathInkId[];
static color  s_pathInkPure[];
static int    s_pathInkOp[];
static int    s_pathLock[];   // P-UI-138: the lock rides the SAME row (one store, one id)
static int    s_pathMid[];    // P-UI-139: ...and so does the 50 % marker switch
// P-UI-137: `DRAW_OP_MIN` (Toolbar_A, included AFTER this file) is 1 — "0 would be
// the chart's own background: invisible is a lie" — and the floor is stated HERE for
// the same reason, so the path's slider can never rest on 0 while the strip's rests on 1.
#define PATH_OP_MIN 1
int PathInkFind(const string id)
{
   for(int i = 0; i < ArraySize(s_pathInkId); i++)
      if(s_pathInkId[i] == id) return i;
   return -1;
}
int PathInkRow(const string id)
{
   int k = PathInkFind(id);
   if(k >= 0) return k;
   int n = ArraySize(s_pathInkId);
   ArrayResize(s_pathInkId, n + 1);
   ArrayResize(s_pathInkPure, n + 1);
   ArrayResize(s_pathInkOp, n + 1);
   ArrayResize(s_pathLock, n + 1);      // P-UI-138: same length BY CONSTRUCTION
   ArrayResize(s_pathMid, n + 1);       // P-UI-139: ...and so is this one
   s_pathInkId[n] = id;
   s_pathInkPure[n] = clrNONE;
   s_pathInkOp[n] = 100;      // a fresh row is FULL: the birth ink, unblended
   s_pathLock[n] = 0;         // ...and UNLOCKED
   s_pathMid[n] = 0;          // ...and with no midpoint markers
   return n;
}
void PathInkForget(const string id)
{
   int k = PathInkFind(id);
   if(k < 0) return;
   int n = ArraySize(s_pathInkId);
   for(int i = k; i < n - 1; i++)
   {
      s_pathInkId[i] = s_pathInkId[i + 1];
      s_pathInkPure[i] = s_pathInkPure[i + 1];
      s_pathInkOp[i] = s_pathInkOp[i + 1];
      s_pathLock[i] = s_pathLock[i + 1];
      s_pathMid[i] = s_pathMid[i + 1];
   }
   ArrayResize(s_pathInkId, n - 1);
   ArrayResize(s_pathInkPure, n - 1);
   ArrayResize(s_pathInkOp, n - 1);
   ArrayResize(s_pathLock, n - 1);
   ArrayResize(s_pathMid, n - 1);
}
// What the user chose (false = never picked: the segments keep their birth ink).
bool PathInkGet(const string id, color &pure, int &op)
{
   int k = PathInkFind(id);
   if(k < 0) { pure = clrNONE; op = 100; return false; }
   pure = s_pathInkPure[k];
   op = s_pathInkOp[k];
   return ((int)pure >= 0);
}
int PathInkOpacityGet(const string id)
{
   int k = PathInkFind(id);
   return (k < 0 ? 100 : s_pathInkOp[k]);
}
// P-UI-138 (2026-10-02, user: "the strip's lock does not work for the path") — THE
// LOCK IS THE PATH'S, NOT MT4'S. Every other drawing arms `OBJPROP_SELECTABLE`, and
// MT4 then owns its anchors. A path's segments are born NON-selectable on purpose
// (the handles are its own edit surface, and a native anchor would drag ONE segment
// and leave the rest of the polyline behind — two owners for one drawing), so the
// same property flip could only hand MT4 a second drag owner. So the strip's LOCK
// cell arms the path's own flag, and the path's press branch asks it before ANY
// carry starts: locked = the drawing stays, nothing about it moves.
bool PathLockGet(const string id)
{
   int k = PathInkFind(id);
   return (k >= 0 && s_pathLock[k] != 0);
}
void PathLockSet(const string id, const bool on)
{
   int k = PathInkRow(id);
   s_pathLock[k] = (on ? 1 : 0);
   PathWitness("lock id=" + id + " on=" + IntegerToString(s_pathLock[k]));
}
//--- P-UI-139 (2026-10-02, user: "a strip option that shows these 50 %s with a
//--- smaller circle") — THE MIDPOINT MARKERS. The strip's 50 % cell (DRAW_SLOT_BOXHALF,
//--- the box's own mid PRICE line) is the seat that already means "the middle" for
//--- this product, so the path WEARS that cell and answers it in its own terms: one
//--- small circle at each SEGMENT's own middle, in the path's own ink, so the
//--- polyline can be read at a glance where its legs turn.
//--- WHY AN OBJ_OVAL AND NOT A HANDLE: the vertices ride pixels (`HandsetHandleAtXY`),
//--- because a vertex is something the hand GRABS. A midpoint is not grabbable, and
//--- anchoring it in time/price means the terminal re-projects it on every pan and
//--- zoom for free — zero work per tick, which is the whole cost argument.
//--- Naming: `<pfx>_PATH_<id>_M<k>` — the `M` tail is not digits, so `PathIdOfName`
//--- (the orphan walk, the delete watcher) never reads a marker as a segment.
// P-UI-140: the mid marker's disc is declared HERE, beside the code that paints it —
// a `#resource` is a compile-time bind of the unit that paints the raster (P-UI-131's
// two-tree law), and this file is in BOTH builds while DrawStrip_Head is in neither Lite.
#resource "\\Files\\Icons\\path_mid_dot.bmp"
#define PATH_MID_HALF 5     // the disc's CENTRE offset on its 11px canvas (P-LM-19's rule:
                            // the canvas is 11px, so half = outSize/2, not the grab radius)
#define PATH_MID_RES  "::Files\\Icons\\path_mid_dot.bmp"
//--- P-UI-142: the terminal's own drag HEARTBEAT — the window a foreign motion keeps
//--- the path's hands off for. P-UI-130 already measured it: MT4 re-reports a native
//--- drag about every 400 ms, and that heartbeat is the only honest length for "the
//--- hand is busy with the terminal's own drawing".
#define PATH_NO_GRAB_MS 400
string PathMidName(const string id, const int k) { return PathPrefix() + id + "_M" + IntegerToString(k); }
void PathMidDrop(const string id)
{
   int m = PathSegCount(id);
   for(int k = 0; k < m; k++) ObjectDelete(0, PathMidName(id, k));
   ObjectDelete(0, PathMidName(id, m));
}
bool PathMidGet(const string id)
{
   int k = PathInkFind(id);
   return (k >= 0 && ArraySize(s_pathMid) > k && s_pathMid[k] != 0);
}
// One marker per segment, at that segment's own (t,p) middle. Bounded by the path's
// segment count and it runs only on a cell press, a drag step and a chart change —
// never on a tick.
void PathMidApply(const string id)
{
   bool on = PathMidGet(id);
   int made = 0;
   int wAx1 = 0, wAy1 = 0, wAx2 = 0, wAy2 = 0, wMx = 0, wMy = 0;   // the first leg, for the witness
   int n = PathSegCount(id);
   for(int k = 0; k < n; k++)
   {
      string nm = PathMidName(id, k);
      string seg = PathSegName(id, k);
      if(!on || ObjectFind(0, seg) < 0) { ObjectDelete(0, nm); continue; }
      datetime t1 = (datetime)ObjectGetInteger(0, seg, OBJPROP_TIME, 0);
      double   p1 = ObjectGetDouble(0, seg, OBJPROP_PRICE, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, seg, OBJPROP_TIME, 1);
      double   p2 = ObjectGetDouble(0, seg, OBJPROP_PRICE, 1);
      if(t1 <= 0 || t2 <= 0 || !(p1 > 0) || !(p2 > 0)) { ObjectDelete(0, nm); continue; }
      //--- P-UI-141 (2026-10-02, user: "it came, but it is not in the middle of the
      //--- line") — THE MIDDLE IS A PIXEL FACT, NOT A PRICE ONE. The marker used the
      //--- arithmetic mean of TIME and PRICE and handed it back to the terminal, which
      //--- is only the middle of the drawn line when the terminal's own mapping is
      //--- linear in both; the hand reads the middle of what it SEES, and that is the
      //--- middle of the two projected pixels. So both anchors are projected and the
      //--- marker sits on their average — a projection the product already does for
      //--- every vertex handle, and the same arithmetic the vertex hit test uses.
      //--- Cost: TWO ChartTimePriceToXY per marker (was one), on a press / a drag step /
      //--- a chart change — never on a tick.
      int ax1 = 0, ay1 = 0, ax2 = 0, ay2 = 0;
      if(!ChartTimePriceToXY(0, 0, t1, p1, ax1, ay1) || !ChartTimePriceToXY(0, 0, t2, p2, ax2, ay2))
      {
         HandsetHandleAtXY(nm, HANDSET_HANDLE_PARK, HANDSET_HANDLE_PARK, PATH_MID_HALF, PATH_MID_RES);
         continue;
      }
      int mx = (ax1 + ax2) / 2, my = (ay1 + ay2) / 2;
      if(k == 0) { wAx1 = ax1; wAy1 = ay1; wAx2 = ax2; wAy2 = ay2; wMx = mx; wMy = my; }
      // P-UI-140 (MEASURED `made=6 … sz=0x0 … tf=0`): MT4 gives an OBJ_ELLIPSE its size
      // from its SECOND ANCHOR, so a fixed-PIXEL round marker cannot be a time/price
      // shape — six objects existed and drew nothing. It is a baked 11px disc on a pixel
      // seat instead, placed through the ONE owner of "this raster on this pixel"
      // (`HandsetHandleAtXY`) — the same call the vertex handles use, so a marker and a
      // handle can never disagree about what a seat is.
      HandsetHandleAtXY(nm, mx, my, PATH_MID_HALF, PATH_MID_RES);
      made++;
   }
   //--- P-UI-140 (2026-10-02): THE PASS ANSWERS WITH ITS OWN NUMBERS. The store said
   //--- ON and the chart showed nothing, and the only way to tell "the create was
   //--- refused" from "it exists and the terminal will not draw it" is to read the
   //--- object back in the same breath: how many markers exist, and the FIRST one's
   //--- seat, ink, size and period mask. Cost: one flushed line per PRESS.
   if(on)
   {
      string f = PathMidName(id, 0);
      PathWitness("mid PASS id=" + id + " made=" + IntegerToString(made) +
                  " leg0=" + IntegerToString(wAx1) + "," + IntegerToString(wAy1) +
                  "->" + IntegerToString(wAx2) + "," + IntegerToString(wAy2) +
                  " mid=" + IntegerToString(wMx) + "," + IntegerToString(wMy) +
                  " first=\"" + f + "\" find=" + IntegerToString(ObjectFind(0, f)) +
                  " type=" + IntegerToString((int)ObjectGetInteger(0, f, OBJPROP_TYPE)) +
                  " xy=" + IntegerToString((int)ObjectGetInteger(0, f, OBJPROP_XDISTANCE)) + "," +
                       IntegerToString((int)ObjectGetInteger(0, f, OBJPROP_YDISTANCE)) +
                  " sz=" + IntegerToString((int)ObjectGetInteger(0, f, OBJPROP_XSIZE)) + "x" +
                        IntegerToString((int)ObjectGetInteger(0, f, OBJPROP_YSIZE)) +
                  " bmp=\"" + ObjectGetString(0, f, OBJPROP_BMPFILE, 0) + "\"" +
                  " z=" + IntegerToString((int)ObjectGetInteger(0, f, OBJPROP_ZORDER)) +
                  " tf=" + IntegerToString((int)ObjectGetInteger(0, f, OBJPROP_TIMEFRAMES)));
   }
}
void PathMidSet(const string id, const bool on)
{
   int k = PathInkRow(id);
   s_pathMid[k] = (on ? 1 : 0);
   PathMidApply(id);
   PathWitness("mid id=" + id + " on=" + IntegerToString(s_pathMid[k]));
}
// THE ONE WRITE. A pick and an opacity step both end here, so the two can never
// disagree: the store is updated first, then every sibling wears the blend of the
// ONE blend owner (`BlendColorTowardsBG`, the product's own - a path's fade looks
// exactly like every other drawing's fade).
void PathInkApply(const string id, const color pure, const int op)
{
   int k = PathInkRow(id);
   if((int)pure >= 0) s_pathInkPure[k] = pure;
   int v = op;                          // the same clamp `DrawSlotOpacitySet` does, spelled
   if(v < PATH_OP_MIN) v = PATH_OP_MIN;   // here: Lite compiles this file without `ClampInt`.
   if(v > 100) v = 100;
   s_pathInkOp[k] = v;
   int n = PathSegCount(id);
   if((int)s_pathInkPure[k] >= 0 && n > 0)
   {
      color ink = BlendColorTowardsBG(s_pathInkPure[k], 100 - v, GetCachedChartBgColor());
      for(int i = 0; i < n; i++)
      {
         string sib = PathSegName(id, i);
         if(ObjectFind(0, sib) < 0) continue;
         ObjectSetInteger(0, sib, OBJPROP_COLOR, ink);
      }
   }
   PathWitness("ink id=" + id + " pure=" + IntegerToString((int)s_pathInkPure[k]) +
               " op=" + IntegerToString(v) + " segs=" + IntegerToString(n));
}
// The handles ride every channel the chart moves in (pan/zoom stream included) and
// die with their path — one sweep, HRayFollowAll's shape.
void PathFollowAll()
{
   if(s_pathSel != "") { PathHandleFollow(s_pathSel); if(s_pathSel != "") return; }
   for(int i = ArraySize(s_pathIds) - 1; i >= 0; i--)
   {
      string id = s_pathIds[i];
      if(PathSegCount(id) == 0)
      {
         PathRegDel(id);   // P-UI-146: the sweep is inside — its handles die with it
      }
   }
}
void PathMakeSegment(const string id, const int idx, const datetime t1, const double p1, const datetime t2, const double p2)
{
   string nm = PathSegName(id, idx);
   if(ObjectCreate(0, nm, OBJ_TREND, 0, t1, p1, t2, p2))
   {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, PATH_COLOR);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, PATH_STYLE);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, PATH_WIDTH);
      ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, Z_BOX_RAY);
      ObjectSetString(0, nm, OBJPROP_TOOLTIP, PathTooltip(idx + 1));
   }
}
void PathCommitVertex(const datetime t, const double p)
{
   if(s_pathSessionId == "")
   {
      for(int a = 0; a < 5; a++)
      {
         s_pathSessionId = IntegerToString((long)GetTickCount()) + IntegerToString(MathRand());
         if(ObjectFind(0, PathSegName(s_pathSessionId, 0)) < 0) break;
         s_pathSessionId = "";
      }
      if(s_pathSessionId == "") return;
   }
   if(s_pathAnchorT > 0 && s_pathAnchorP > 0)
   {
      PathMakeSegment(s_pathSessionId, s_pathSegCount, s_pathAnchorT, s_pathAnchorP, t, p);
      s_pathSegCount++;
   }
   s_pathAnchorT = t;
   s_pathAnchorP = p;
}
void PathFinish()
{
   string id = s_pathSessionId;
   int segs = s_pathSegCount;
   ObjectDelete(0, PathPreviewName());
   if(id != "" && segs >= 1)
   {
      PathRegAdd(id);
      PathWitness("commit segs=" + IntegerToString(segs) + " id=" + id);
      for(int i = 0; i < segs; i++)
         ObjectSetString(0, PathSegName(id, i), OBJPROP_TOOLTIP, PathTooltip(segs));
   }
   else if(id != "")
   {
      for(int i = 0; i < segs; i++) ObjectDelete(0, PathSegName(id, i));
   }
   s_pathAnchorT = 0; s_pathAnchorP = 0;
   s_pathSegCount = 0;
   s_pathSessionId = "";
   s_pathLastVerMs = 0;
   s_pathArmed = false;
   ChartViewLockRelease();   // the arm's acquire ends with the commit
   ChartRedraw();
}
void PathDragRelease()
{
   if(s_pathDrag == "") return;
   s_pathDrag = "";
   ChartViewLockRelease();
}
// ONE snap store, three gestures. `ix` says which anchor each snapshotted segment
// moves, so the whole-path carry (ix=2 everywhere) and a single-vertex edit (one
// or two segments, ix=0/1) share the same apply, the same restore and the same
// press bookkeeping — a second drag path would be a second geometry.
void PathSnapAdd(const string nm, const int ix)
{
   if(ObjectFind(0, nm) < 0) return;
   int k = ArraySize(s_pathSnapNames);
   ArrayResize(s_pathSnapNames, k + 1);
   ArrayResize(s_pathSnapIx, k + 1);
   ArrayResize(s_pathSnapT0, k + 1);
   ArrayResize(s_pathSnapP0, k + 1);
   ArrayResize(s_pathSnapT1, k + 1);
   ArrayResize(s_pathSnapP1, k + 1);
   s_pathSnapNames[k] = nm;
   s_pathSnapIx[k] = ix;
   s_pathSnapT0[k] = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 0);
   s_pathSnapP0[k] = ObjectGetDouble(0, nm, OBJPROP_PRICE, 0);
   s_pathSnapT1[k] = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME, 1);
   s_pathSnapP1[k] = ObjectGetDouble(0, nm, OBJPROP_PRICE, 1);
}
// P-UI-145: the whole-path carry is RETIRED with the body press that used to start it
// (a body press selects and nothing more). Its snap store is still the one a vertex carry
// uses — PathVertDragStart below — so the geometry half of this code lives on; only the
// entry point is gone, and the whole-path DRAG was never reachable from the strip.
// P-UI-136: A HANDLE DRAG EDITS ONE POINT. Vertex k lives in segment k's anchor 0
// (and in segment k-1's point 1 when it is a shared vertex) — so the snap store
// holds one segment at the ends and two in the middle, and nothing else on the
// path can move.
void PathVertDragStart(const string id, const int k)
{
   s_pathDrag = id;
   s_pathMoved = false;
   s_pathPrimed = false;    // P-UI-142: same rule for a single-point edit
   PathSelect(id);
   PathHandleFollow(id);
   ArrayResize(s_pathSnapNames, 0);
   int n = PathSegCount(id);
   if(k > 0) PathSnapAdd(PathSegName(id, k - 1), 1);
   if(k < n) PathSnapAdd(PathSegName(id, k), 0);
   ChartViewLockAcquire();
   PathWitness("drag start id=" + id + " vertex=" + IntegerToString(k));
}
void PathDragApply(const datetime curT, const double curP)
{
   long dt = (long)(curT - s_pathSnapT);
   double dp = curP - s_pathSnapP;
   for(int i = 0; i < ArraySize(s_pathSnapNames); i++)
   {
      if(ObjectFind(0, s_pathSnapNames[i]) < 0) continue;
      int ix = s_pathSnapIx[i];
      if(ix != 1) ObjectMove(0, s_pathSnapNames[i], 0, s_pathSnapT0[i] + dt, s_pathSnapP0[i] + dp);
      if(ix != 0) ObjectMove(0, s_pathSnapNames[i], 1, s_pathSnapT1[i] + dt, s_pathSnapP1[i] + dp);
   }
   PathHandleFollow(s_pathDrag);   // the handles ride the carry, one probe per vertex
   // P-UI-139: the 50 % markers ride it too — and only when the switch is on, so the
   // default path pays ONE array read per drag step and not one object write.
   if(PathMidGet(s_pathDrag)) PathMidApply(s_pathDrag);
}
void PathDragRestore()
{
   for(int i = 0; i < ArraySize(s_pathSnapNames); i++)
   {
      if(ObjectFind(0, s_pathSnapNames[i]) < 0) continue;
      int ix = s_pathSnapIx[i];
      if(ix != 1) ObjectMove(0, s_pathSnapNames[i], 0, s_pathSnapT0[i], s_pathSnapP0[i]);
      if(ix != 0) ObjectMove(0, s_pathSnapNames[i], 1, s_pathSnapT1[i], s_pathSnapP1[i]);
   }
   PathHandleFollow(s_pathDrag);
}
void PathDragEnd()
{
   if(s_pathDrag == "") return;
   PathWitness("drag end id=" + s_pathDrag + " moved=" + (s_pathMoved ? "yes" : "no"));
   if(s_pathMoved) s_pathEndMs = GetTickCount();
   s_pathPrimed = false;
   PathDragRelease();
   ChartRedraw();
}
bool PathOnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   string pfx = PathPrefix();
   //--- P-UI-142 (2026-10-02, user: "from that same point I want to draw a trend line
   //--- and THIS one moves too") — THE TERMINAL'S OWN MOTION IS NOT OURS. A press that
   //--- lands on a path is ambiguous: it may be the hand taking the path, or the hand
   //--- STARTING a native drawing (a trend line, a ray, a fib) from that very pixel. The
   //--- indicator cannot ask which — but MT4 answers the second one a moment later, in
   //--- its own voice: `CHARTEVENT_OBJECT_DRAG` on an object that is NOT ours. That is
   //--- P-UI-130 law 3 applied one level up (the hold's own rule: a gesture IN MOTION is
   //--- never ours), so a foreign drag (a) puts a live carry back exactly where the
   //--- press found it, and (b) FORBIDS the next grab for the heartbeat that follows
   //--- (400 ms, the terminal's own drag rate) so the path cannot be re-grabbed out
   //--- from under the stroke still in progress. Two comparisons per drag event and one
   //--- deadline read per press; our own segments never emit this event (they are born
   //--- non-selectable), so the path cannot forbid itself.
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      if(pfx != "" && StringFind(sparam, pfx) == 0) return false;   // our own geometry is never dragged
      //--- P-UI-142: the terminal's voice, answered by the SHARED arbiter (its one
      //--- writer is the router) — and the path's own two lines: a live carry goes
      //--- back exactly where the press found it, and the next grab is the arbiter's
      //--- to refuse. Geometry is ours; the DECISION is the project's.
      if(s_pathDrag != "")
      {
         PathWitness("foreign drag \"" + sparam + "\" put the path back");
         PathDragRestore();
         PathDragEnd();
      }
      return false;
   }
   if(id == CHARTEVENT_OBJECT_DELETE && pfx != "" && StringFind(sparam, pfx) == 0)
   {
      if(g_suppressDeleteEvents || TickDeadlinePending(g_suppressDeleteEventsUntilMs)) return false;
      string pid;
      if(PathIdOfName(sparam, pid))
      {
         if(PathSegCount(pid) == 0) PathRegDel(pid);
         if(s_pathDrag == pid) PathDragRelease();
         // The handles follow their path: a segment gone RE-PLACES the vertex set,
         // and the last one gone takes the whole family with it (one sweep).
         if(s_pathSel == pid)
         {
            if(PathSegCount(pid) <= 0) { PathHandlesDrop(pid); s_pathSel = ""; }
            else PathHandleFollow(pid);
         }
      }
      return false;
   }
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      PathAdoptOrphans();
      PathFollowAll();
      // P-UI-139: a chart change re-projects the 50 % markers for free (they are
      // time/price objects) — but only the paths that ASKED for them are walked.
      for(int i = 0; i < ArraySize(s_pathIds); i++)
         if(PathMidGet(s_pathIds[i])) PathMidApply(s_pathIds[i]);
      return false;
   }
   if(id == CHARTEVENT_KEYDOWN && lparam == 27)
   {
      if(s_pathDrag != "") { PathDragRestore(); PathDragEnd(); return true; }
      if(s_pathArmed) { PathSessionClear(); PathCancel(); return true; }
      return false;
   }
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      bool leftDown = ((st & 1) != 0);
      bool rightDown = ((st & 2) != 0);
      bool pressed = (leftDown && !s_pathLeft);
      s_pathLeft = leftDown;
      //--- P-UI-145: there is no lock state in this file. The arbiter owns ONE stamp that expires
      //--- by itself (GlobalVariables.mqh), and the structural half is right here: a press on
      //--- the BODY selects and never carries, so a native stroke's press can start nothing;
      //--- the DOTS are the only carry in this tool, and they are painted only for the
      //--- selected path (PathHandleAt), so a visible dot means the hand chose this drawing.
      if(s_pathDrag != "")
      {
         if(rightDown) { PathDragRestore(); PathDragEnd(); return true; }
         //--- P-UI-143 (2026-10-02, MEASURED AND RETIRED IN THE SAME BREATH): a rule was
         //--- written here that read the button bit as «whose hand is this» — it looked
         //--- proven, and it was not. The census shows the bit FLAPPING mid-press, at one
         //--- and the same pixel: `nm="1"` then `nm="0"` then `nm="1"`, the cursor never
         //--- moving. That is the terminal's own object machinery reporting its button
         //--- state unreliably (P-LM-13 measured it years ago on the leg carry), so the
         //--- bit is NOT an owner — and a rule built on it killed our OWN carry. What the
         //--- same run measured is the finding that matters: MT4 is silent for the whole
         //--- of a native stroke and speaks ONCE at its end, so nothing can be decided
         //--- in flight. The owner has to be the terminal itself — which means the
         //--- segments become SELECTABLE and its anchors move the geometry (P-UI-144).
         if(!leftDown) { PathDragEnd(); return true; }
         ChartViewLockAssert();
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
         {
            if(!s_pathMoved &&
               (MathAbs((int)lparam - s_pathPressX) > 2 || MathAbs((int)dparam - s_pathPressY) > 2))
               s_pathMoved = true;
            //--- P-UI-142: THE FIRST MOVE IS BUFFERED, NEVER WRITTEN. A press on a path
            //--- pixel cannot be told apart from the START of a native drawing, and the
            //--- terminal's own answer (OBJECT_DRAG on a foreign object) arrives with
            //--- that first move. Holding the first sample back means a native stroke
            //--- kills the carry BEFORE this drawing has written a single anchor — the
            //--- path never moves at all, not even for one frame. A real carry pays one
            //--- move of latency (~16 ms) and nothing else. Cost: two scalars.
            if(!s_pathMoved) { s_pathPrimed = false; return true; }
            if(!s_pathPrimed)
            {
               s_pathPrimed = true;
               s_pathPrimT = ct; s_pathPrimP = cp;
               return true;
            }
            PathDragApply(ct, cp);
         }
         return true;
      }
      if(s_pathArmed)
      {
         if(rightDown) { PathSessionClear(); PathCancel(); return true; }
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
            PathPreviewMove(ct, cp);
         return false;
      }
      //--- P-UI-144 (2026-10-02): THE HAND IS OURS TO GIVE. Three measurements closed the
//--- detection road (no "native tool armed" flag; the terminal is silent for the whole
//--- of a native stroke and speaks once at its end; its button bit flaps mid-press), so
//--- the owner is DECIDED by one shared question instead of guessed at: a drawing that
//--- is not already TAKEN cannot be taken. The press that takes it for the first time
//--- SELECTS it and writes no anchor, so a trend line started on a path point leaves the
//--- path exactly where it was. The question lives in the arbiter (GlobalVariables.mqh)
//--- so this file and the ray cannot drift into two different rules.
if(pressed && pfx != "")
      {
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return false;
         //--- P-UI-145: THE ORDER IS THE RULE. The DOT is asked FIRST and it carries on one
         //--- press; the foreign-drag lock is asked after it, so a terminal that is still
         //--- finishing its own stroke cannot eat the one gesture a visible handle owes the
         //--- user (that ordering is why a painted dot could not be dragged: the lock was
         //--- asked first and the 400 ms window after every native stroke swallowed it).
         int sw = 0; datetime ct = 0; double cp = 0;
         bool tp = ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp);
         s_pathPressX = (int)lparam; s_pathPressY = (int)dparam;
         if(tp) { s_pathSnapT = ct; s_pathSnapP = cp; }
         // A HANDLE FIRST: the handles sit ON the path, so without this the whole
         // -path carry would swallow the press and a point could never be edited.
         string hid = ""; int hk = -1;
         if(PathDotHit((int)lparam, (int)dparam, hid, hk))
         {
            // P-UI-144: THE LOCK AND THE TAKE ARE TWO QUESTIONS. Folding them into one
            // branch let a press on a LOCKED path write the take, so the locked path was
            // silently "given" to the next gesture and never answered with its own witness.
            if(PathLockGet(hid))
            {
               PathWitness("press refused: locked id=" + hid);
               return true;
            }
            //--- P-UI-145 (2026-10-02, user: «نقاطشو نمیشه جابجا کرد، باید ترکیبی بشه»):
            //--- THE DOT IS THE HANDLE, and a handle needs no second gesture. The dot is
            //--- painted ONLY for the selected path (PathHandleAt: an unselected chart wears
            //--- no circles), so a visible dot already means the hand chose this drawing —
            //--- the take gate that guarded the BODY is not repeated here, because the one
            //--- press a native tool makes on a line can never reach this branch: a line
            //--- press selects and stops (below), and only a DOT carries.
            PathVertDragStart(hid, hk);
            PathWitness("carry the dot of id=" + hid + " v=" + IntegerToString(hk) + " why=" + GestureTakeWhy());
            return true;
         }
         //--- …and only now the lock, which is the terminal's own voice and guards the BODY:
         //--- a foreign drag that is still finishing must not start a new grab either.
         if(PathGrabBlocked())
         {
            PathWitness("press refused: the terminal is still dragging one of ours, why=" + GestureTakeWhy());
            return false;
         }
         string pid = "";
         if(PathPressHit((int)lparam, (int)dparam, pid))
         {
            //--- P-UI-145 (2026-10-02, user: «فقط رأس‌ها، بدنه آزاد»): THE BODY IS FREE.
            //--- A press on a segment SELECTS and nothing else — it never latches a carry.
            //--- This is the structural answer, not a detection: MEASURED, a native stroke
            //--- reports button=0 on all ~40 of its moves and speaks once at its end, so NO
            //--- press-time question can tell it from a carry of ours, and every lock built
            //--- on that question left the drawing free to walk away (four `drag start … why=carry:
            //--- it was taken` in a row, then `moved=yes`). A body that cannot carry cannot be
            //--- carried away by anything: the chart is free for the terminal's own tools.
            //--- A path is moved by its VERTICES (the branch above), which answer only while
            //--- the path is selected — so the hand is on a dot, not on a line.
            if(PathLockGet(pid)) { PathWitness("press refused: locked id=" + pid); return true; }
            PathWitness("press on the BODY of id=" + pid + " — select only, never a carry");
            PathSelect(pid); PathHandleFollow(pid); GestureTakeNote(pid);
            return true;
         }
         //--- P-UI-145: THE PRESS THAT FOUND NEITHER A DOT NOR A BODY is the one silence a
         //--- hit test must never keep: the log used to read «select … select …» and a user
         //--- pressing a visible dot learned nothing from it. It names the selection, the
         //--- dots it owns and the lock, on the press edge only.
         PathWitness("press found neither dot nor body: sel=" + s_pathSel
                     + " dots=" + IntegerToString(PathSegCount(s_pathSel))
                     + " at " + IntegerToString((int)lparam) + "," + IntegerToString((int)dparam)
                     + " why=" + GestureTakeWhy());
      }
      return false;
   }
   if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") >= 0)
   {
      if(s_pathArmed) { PathSessionClear(); PathCancel(); return true; }
      return false;
   }
   if(id == CHARTEVENT_CLICK)
   {
      if(s_pathDrag != "") PathDragEnd();
      if(s_pathArmed)
      {
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
         {
            uint now = GetTickCount();
            if(s_pathLastVerMs != 0 && now - s_pathLastVerMs <= PATH_DBL_MS &&
               MathAbs((int)lparam - s_pathLastVerX) <= PATH_DBL_PX &&
               MathAbs((int)dparam - s_pathLastVerY) <= PATH_DBL_PX &&
               s_pathSegCount >= 1)
            {
               PathFinish();
               return true;
            }
            PathCommitVertex(ct, cp);
            s_pathLastVerMs = now;
            s_pathLastVerX = (int)lparam;
            s_pathLastVerY = (int)dparam;
         }
         return true;
      }
      // P-UI-136 (2026-10-02, user: "after the double-click that finishes the draw,
      // I select and move it and every point of it is deleted") — ONE PIXEL, TWO
      // GESTURES. The segment used to host BOTH the carry and the double-click
      // delete, so the finishing double-click's OWN release click armed the delete
      // witness (the arm is disarmed by then, so the arm-less branch answers it),
      // and the hand's very next press — the "select it" tap — was the witness's
      // second half: the path died instead of moving. An armed flag outliving its
      // own gesture is P-UI-130 law 1, and no timing rule fixes it: two still
      // presses in 400 ms are a double-click AND a select-then-move.
      // So the delete moved to the VERTEX HANDLES (HRay parity: HRayDotHit/
      // HRaySelect): a segment press can now only ever mean "select + carry", a
      // handle press "edit this point", and no release click arms anything.
      string did = ""; int hk = -1;
      if(pfx != "" && PathDotHit((int)lparam, (int)dparam, did, hk))
      {
         //--- P-UI-142: a release that trails the terminal's own motion selects and
         //--- arms NOTHING — the hand was busy drawing something else, and a witness
         //--- armed here is the second half of a delete the user never asked for.
         if(PathGrabBlocked()) return true;
         //--- P-UI-146 (2026-10-02, user: «بعضی وقتا خودکار ابزار path حذف میشه چرا»): THE
         //--- DOUBLE-CLICK DELETE IS RETIRED. It was the only route that could delete a path
         //--- with no intent behind it, and the terminal's own button bit FLAPS at a still
         //--- pixel — MEASURED by the census (`nm="1"` → `"0"` → `"1"`, cursor fixed, ~100 ms
         //--- apart), all of it inside PATH_DBL_MS=400 and PATH_DBL_PX=6 of the first click.
         //--- So ONE press could arm and fire the delete and the path vanished «خودکار», with
         //--- no line in the log to explain it. No timing rule separates the two: a real
         //--- double-click is also two still presses. So the delete is not a gesture here at
         //--- all — the strip's bin is its one owner (`why=strip bin`, DrawStrip_Tap.mqh),
         //--- which is the only place a deletion is a CHOICE rather than an accident.
         PathSelect(did); PathHandleFollow(did);
         PathWitness("handle click id=" + did + " v=" + IntegerToString(hk)
                     + " — select only; delete lives in the strip's bin");
         s_pathClick = "";   // P-UI-146: nothing arms a delete on the chart any more
         return true;
      }
      // A segment release: the press already selected and started the carry, or a
      // still press only got here — either way the dot is the answer, and the click
      // ARMS NOTHING.
      string pid = "";
      if(pfx != "" && PathPressHit((int)lparam, (int)dparam, pid))
      {
         // P-UI-138: locked = no handles, no witness, nothing to arm. A still press on
         // a locked path is a no-op that the strip's own hold still owns (the hold is
         // polled from the cursor, not from this event).
         if(PathLockGet(pid)) { PathWitness("click refused: locked id=" + pid); s_pathClick = ""; return true; }
         PathSelect(pid); PathHandleFollow(pid);
         PathWitness("select id=" + pid + " segs=" + IntegerToString(PathSegCount(pid)));
         s_pathClick = "";
         return true;
      }
      // P-UI-140 (2026-10-02, measured: a tap on the strip's own cell emitted
      // `[Path] dismiss id=…` right after `[drawstrip] SLOT slot=9 …`) — A CLICK ON
      // A UI SURFACE IS THE UI'S. The terminal reports every press as a chart click
      // with coordinates, so a tap on a strip cell landed here, hit no path (the strip
      // is over the chart), and DROPPED the selection the user had just made — the
      // «میزنم هم سلکت میپره» report. The armed branch already asks
      // `UIPointerOverSurface`; the dismiss branch did not, and a selection is worth
      // more than the dismiss gesture it was protecting.
      if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
      if(s_pathSel != "")
      {
         PathWitness("dismiss id=" + s_pathSel);
         PathSelect("");
      }
      s_pathClick = "";
      return false;
   }
   return false;
}
void PathOnInit()
{
   s_pathArmed = false;
   s_pathDrag = "";
   s_pathClick = "";
   s_pathSel = "";      // a fresh attach owns no selection: the dot is drawn, not adopted
   PathAdoptOrphans();
}
void PathOnDeinit(const int reason)
{
   s_pathArmed = false;
   s_pathDrag = "";
   s_pathSel = "";
   if(reason == REASON_REMOVE)
   {
      string pfx = PathPrefix();
      if(pfx != "") ObjectsDeleteAll(0, pfx);   // one sweep: segments AND dot (P-LOG-10 law 4)
      ArrayResize(s_pathIds, 0);
   }
}

#endif // PATH_TOOL_MQH
