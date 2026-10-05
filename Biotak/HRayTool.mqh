//+------------------------------------------------------------------+
//| HRayTool.mqh — Horizontal Ray (TradingView Alt+J parity).        |
//+------------------------------------------------------------------+
//| LAYER: drawing/domain (no UI deps — compiles in Full AND Lite).   |
//| Single-shot: arm → one chart click places → IDLE. The line is     |
//| NON-selectable (no native grips, no angle ever); the ONE grip is  |
//| the custom-price circle on the SELECTED ray's start only — a      |
//| click elsewhere dismisses it. Press near any ray selects + drags  |
//| it (price AND start time, length kept); double-click removes it.  |
//+------------------------------------------------------------------+
//| P-HR-01 (2026-09-28): ONE price, no angle — placement is a single |
//| click, the drag writes price only.                                |
//| P-HR-02 (2026-09-28): the native trend wore MT4's three grips and |
//| angled — retired. The cp_handle circle at the start is the grip.  |
//| P-HR-03 (2026-09-28, user: «صفحه موقع جابجایی باید قفل باشه» +    |
//| «کلیک جایی اون دایره بره»): the arm AND the carry take the view   |
//| lock (named in ChartLockIntended the day they were born, P-DRAW-  |
//| 19) and the dot lives on the selected ray only.                   |
//+------------------------------------------------------------------+
#ifndef HRAY_TOOL_MQH
#define HRAY_TOOL_MQH

#define HRAY_TAG "_HRAY_"
#define HRAY_COLOR clrRed
#define HRAY_WIDTH 1
#define HRAY_STYLE STYLE_SOLID
#define HRAY_GRAB_PX 8    // press band half-height around the ray, px
#define HRAY_DBL_MS 400   // double-click window for dot-delete
#define HRAY_DBL_PX 6     // ... and its pixel travel

static bool   s_hrayArmed    = false;  // arm session live (the menu light reads this)
static bool   s_hrayLeft     = false;  // mouse edge detector (P-LM-13: update on EVERY move)
static string s_hrayDrag     = "";     // line name under the hand ("" = no drag)
static string s_hraySel      = "";     // SELECTED ray ("" = none — no dot anywhere)
static bool   s_hrayMoved    = false;  // the press travelled (else it was a click)
static double s_hraySnapP    = 0.0;    // price the press found (right-click restores it)
static datetime s_hraySnapT  = 0;      // ... and its start time (the carry moves both axes)
static int    s_hraySnapSpan = 0;      // ... and the ray length the press found
static int    s_hrayPressX   = 0;
static int    s_hrayPressY   = 0;
static string s_hrayIds[];             // registry: ray ids (small — scans stay cheap)
static string s_hrayClick    = "";     // dot-delete: last clicked line
static uint   s_hrayClickMs  = 0;
static int    s_hrayClickX   = 0;
static int    s_hrayClickY   = 0;
static uint   s_hrayEndMs    = 0;      // moved-drag release stamp (trailing click guard)

bool HRaySessionActive() { return s_hrayArmed; }
// P-DRAW-19: every gesture holding the lock names itself here (BiotakPanels).
bool HRayViewOwned() { return (s_hrayArmed || s_hrayDrag != ""); }
// P-HR-06: arm is idempotent — a second arm without a cancel must not stack
// a second acquire (the reconcile would read one intent and two counts).
void HRayArm()
{
   if(s_hrayArmed) return;
   GestureTakeRelease();   // P-UI-144: a NEW drawing is never gated by the last one
   s_hrayArmed = true; ChartViewLockAcquire(); ChartRedraw();
}
void HRayCancel()
{
   if(!s_hrayArmed) return;
   s_hrayArmed = false;
   ChartViewLockRelease();   // exactly one release per arm acquire
   ChartRedraw();
}

string HRayPrefix()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + HRAY_TAG;
}
string HRayLineName(const string id) { return HRayPrefix() + id; }
string HRayHandleName(const string line) { return line + "_H"; }
bool HRayIsHandle(const string nm)
{
   int l = StringLen(nm);
   return (l > 2 && StringSubstr(nm, l - 2) == "_H");
}
int HRayRegFind(const string id)
{
   for(int i = 0; i < ArraySize(s_hrayIds); i++)
      if(s_hrayIds[i] == id) return i;
   return -1;
}
void HRayRegAdd(const string id)
{
   if(HRayRegFind(id) >= 0) return;
   int n = ArraySize(s_hrayIds);
   ArrayResize(s_hrayIds, n + 1);
   s_hrayIds[n] = id;
}
void HRayRegDel(const string id)
{
   int k = HRayRegFind(id);
   if(k < 0) return;
   int n = ArraySize(s_hrayIds);
   for(int i = k; i < n - 1; i++) s_hrayIds[i] = s_hrayIds[i + 1];
   ArrayResize(s_hrayIds, n - 1);
}
string HRayTooltip(const double price)
{
   return "Horizontal ray " + DoubleToString(price, Digits) +
          " — drag the dot to move · double-click the dot to remove";
}
// The dot lives on the SELECTED ray only — anywhere else it is deleted, so a
// click on empty chart leaves no circle behind to annoy (P-HR-03).
void HRaySelect(const string line)
{
   if(s_hraySel != "" && s_hraySel != line)
      ObjectDelete(0, HRayHandleName(s_hraySel));
   s_hraySel = line;
   s_hrayClick = "";
}
void HRayHandleFollow(const string line)
{
   string hn = HRayHandleName(line);
   if(line != s_hraySel || ObjectFind(0, line) < 0) { ObjectDelete(0, hn); return; }
   datetime t1 = (datetime)ObjectGetInteger(0, line, OBJPROP_TIME, 0);
   double   p1 = ObjectGetDouble(0, line, OBJPROP_PRICE, 0);
   int x = 0, y = 0;
   if(!(p1 > 0) || !ChartTimePriceToXY(0, 0, t1, p1, x, y))
      HandsetHandleAtXY(hn, HANDSET_HANDLE_PARK, HANDSET_HANDLE_PARK, CP_HANDLE_HALF, CP_HANDLE_RES);
   else
      HandsetHandleAtXY(hn, x, y, CP_HANDLE_HALF, CP_HANDLE_RES);
}
// P-HR-02 migration: a v1 ray (selectable trend, no dot) is adopted — the
// flag comes off. Runs on chart change only, never hot.
void HRayNormalise(const string line)
{
   if(ObjectFind(0, line) < 0) return;
   if((bool)ObjectGetInteger(0, line, OBJPROP_SELECTABLE))
      ObjectSetInteger(0, line, OBJPROP_SELECTABLE, false);
   if((bool)ObjectGetInteger(0, line, OBJPROP_SELECTED))
      ObjectSetInteger(0, line, OBJPROP_SELECTED, false);
}
void HRayAdoptOrphans()
{
   string pfx = HRayPrefix();
   if(pfx == "") return;
   int n = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < n; i++)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, pfx) != 0 || HRayIsHandle(nm)) continue;
      HRayRegAdd(StringSubstr(nm, StringLen(pfx)));
      HRayNormalise(nm);
   }
}
void HRayFollowAll()
{
   if(s_hraySel != "" && ObjectFind(0, s_hraySel) >= 0) { HRayHandleFollow(s_hraySel); return; }
   if(s_hraySel != "")
   {
      ObjectDelete(0, HRayHandleName(s_hraySel));   // wiped behind our back — forget it
      s_hraySel = "";
   }
   for(int i = ArraySize(s_hrayIds) - 1; i >= 0; i--)
   {
      string ln = HRayLineName(s_hrayIds[i]);
      if(ObjectFind(0, ln) < 0)
      {
         ObjectDelete(0, HRayHandleName(ln));
         HRayRegDel(s_hrayIds[i]);
      }
   }
}
// One price, one ray: t2 only gives the ray its rightward direction. The
// line is born NON-selectable — no native grips, so no angle, ever.
void HRayPlace(const datetime t, const double price)
{
   string pfx = HRayPrefix();
   if(pfx == "" || t <= 0 || !(price > 0)) return;
   // tick+rand ids collide only in theory — retry a few times instead of
   // swallowing the click (a click that draws nothing is P-UI-93's failure).
   string ln = "";
   for(int a = 0; a < 5; a++)
   {
      ln = HRayLineName(IntegerToString((long)GetTickCount()) + IntegerToString(MathRand()));
      if(ObjectFind(0, ln) < 0) break;
      ln = "";
   }
   if(ln == "") return;
   string id = StringSubstr(ln, StringLen(pfx));
   int span = (PeriodSeconds() > 0 ? 10 * PeriodSeconds() : 600);
   if(ObjectCreate(0, ln, OBJ_TREND, 0, t, price, t + span, price))
   {
      ObjectSetInteger(0, ln, OBJPROP_COLOR, HRAY_COLOR);
      ObjectSetInteger(0, ln, OBJPROP_STYLE, HRAY_STYLE);
      ObjectSetInteger(0, ln, OBJPROP_WIDTH, HRAY_WIDTH);
      ObjectSetInteger(0, ln, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, ln, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, ln, OBJPROP_BACK, false);
      ObjectSetInteger(0, ln, OBJPROP_ZORDER, Z_BOX_RAY);
      ObjectSetString(0, ln, OBJPROP_TOOLTIP, HRayTooltip(price));
      HRayRegAdd(id);
      HRaySelect(ln);   // the fresh ray is selected, so its dot answers at once
      HRayHandleFollow(ln);
      Print("[HRay] placed \"", ln, "\" at ", DoubleToString(price, Digits));
   }
}
// THE lock giver-backer for the carry — every path that drops the drag goes
// through here, so an acquire can never outlive its gesture (P-HR-06).
void HRayDragRelease()
{
   if(s_hrayDrag == "") return;
   s_hrayDrag = "";
   ChartViewLockRelease();   // exactly one release per drag acquire
}
void HRayDelete(const string line, const string why)
{
   Print("[HRay] delete \"", line, "\" (", why, ")");
   if(s_hrayDrag == line) HRayDragRelease();
   ObjectDelete(0, HRayHandleName(line));
   ObjectDelete(0, line);
   string pfx = HRayPrefix();
   if(pfx != "" && StringFind(line, pfx) == 0)
      HRayRegDel(StringSubstr(line, StringLen(pfx)));
   if(s_hrayDrag == line) s_hrayDrag = "";
   if(s_hraySel == line) s_hraySel = "";
   s_hrayClick = "";
   ChartRedraw();
}
// Press-near-line: the ray reads horizontal on screen, so proximity is one
// row test from the start anchor rightward. Nearest wins; "" = empty chart.
bool HRayPressHit(const int mx, const int my, string &line)
{
   line = "";
   int best = 0x7fff;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   for(int i = 0; i < ArraySize(s_hrayIds); i++)
   {
      string ln = HRayLineName(s_hrayIds[i]);
      if(ObjectFind(0, ln) < 0) continue;
      int x = 0, y = 0;
      if(!ChartTimePriceToXY(0, 0, (datetime)ObjectGetInteger(0, ln, OBJPROP_TIME, 0),
                             ObjectGetDouble(0, ln, OBJPROP_PRICE, 0), x, y)) continue;
      if(mx < x - HRAY_GRAB_PX || mx > cw) continue;
      int d = MathAbs(my - y);
      if(d <= HRAY_GRAB_PX && d < best) { best = d; line = ln; }
   }
   return (line != "");
}
// Dot hit (the selected ray only — it is the only one wearing a dot).
bool HRayDotHit(const int mx, const int my, string &line)
{
   line = "";
   if(s_hraySel == "" || ObjectFind(0, s_hraySel) < 0) return false;
   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, (datetime)ObjectGetInteger(0, s_hraySel, OBJPROP_TIME, 0),
                          ObjectGetDouble(0, s_hraySel, OBJPROP_PRICE, 0), x, y)) return false;
   int d = (int)MathSqrt((double)((mx - x) * (mx - x) + (my - y) * (my - y)));
   if(d > HRAY_GRAB_PX + 4) return false;
   line = s_hraySel;
   return true;
}
// One drag step: the whole ray rides the cursor — price from its row, start
// time from its column, length kept. p2 == p1 always (the no-angle law), so
// sliding along the candles can never tilt it. Dot in the same pass (P-LM-16).
void HRayDragApply(const string line, const datetime curT, const double curP)
{
   if(ObjectFind(0, line) < 0) { HRayDragRelease(); return; }
   if(!(curP > 0) || curT <= 0) return;
   int span = s_hraySnapSpan;
   if(span <= 0) span = (PeriodSeconds() > 0 ? 10 * PeriodSeconds() : 600);
   datetime t1 = curT, t2 = curT + span;
   if(ObjectGetDouble(0, line, OBJPROP_PRICE, 0) != curP)
      ObjectMove(0, line, 0, t1, curP);
   else if((datetime)ObjectGetInteger(0, line, OBJPROP_TIME, 0) != t1)
      ObjectMove(0, line, 0, t1, curP);
   ObjectMove(0, line, 1, t2, curP);
   ObjectSetString(0, line, OBJPROP_TOOLTIP, HRayTooltip(curP));
   HRayHandleFollow(line);
}
void HRayDragStart(const string line)
{
   s_hrayDrag = line;
   s_hrayMoved = false;
   s_hraySnapP = ObjectGetDouble(0, line, OBJPROP_PRICE, 0);
   s_hraySnapT = (datetime)ObjectGetInteger(0, line, OBJPROP_TIME, 0);
   s_hraySnapSpan = (int)((datetime)ObjectGetInteger(0, line, OBJPROP_TIME, 1) - s_hraySnapT);
   ChartViewLockAcquire();   // P-HR-03: the carry owns the view (named below)
   HRaySelect(line);
   Print("[HRay] drag start \"", line, "\"");
}
void HRayDragEnd()
{
   if(s_hrayDrag == "") return;
   Print("[HRay] drag end \"", s_hrayDrag, "\" moved=", (s_hrayMoved ? "yes" : "no"));
   if(s_hrayMoved) s_hrayEndMs = GetTickCount();   // trailing release-click is select-only
   HRayDragRelease();
   ChartRedraw();
}
// Abort: the ray goes back EXACTLY where the press found it (both axes).
void HRayDragRestore()
{
   string line = s_hrayDrag;
   if(line != "" && ObjectFind(0, line) >= 0 && s_hraySnapT > 0 && s_hraySnapP > 0)
   {
      int span = (s_hraySnapSpan > 0 ? s_hraySnapSpan : (PeriodSeconds() > 0 ? 10 * PeriodSeconds() : 600));
      ObjectMove(0, line, 0, s_hraySnapT, s_hraySnapP);
      ObjectMove(0, line, 1, s_hraySnapT + span, s_hraySnapP);
      ObjectSetString(0, line, OBJPROP_TOOLTIP, HRayTooltip(s_hraySnapP));
      HRayHandleFollow(line);
   }
}
bool HRayOnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   string pfx = HRayPrefix();
   // A line deleted behind our back takes its dot with it — one way, never back.
   if(id == CHARTEVENT_OBJECT_DRAG)
   {
      // P-UI-142: THE TERMINAL'S OWN MOTION IS NOT OURS. A drag on a FOREIGN object
      // means the hand is busy with MT4's own drawing tool — «از همون نقطه که یه
      // چیزی میکشم، اینم میاد» — so the shared arbiter (GlobalVariables.mqh) is told
      // by the router, and the ray's own two lines: a live carry goes back where the
      // press found it, and the next grab is the arbiter's to refuse. One window for
      // the whole product; no tool re-derives it.
      string gpfx = HRayPrefix();
      if(gpfx != "" && StringFind(sparam, gpfx) == 0) return false;
      if(s_hrayDrag != "") { HRayDragRestore(); HRayDragEnd(); }
      return false;
   }
   if(id == CHARTEVENT_OBJECT_DELETE && pfx != "" && StringFind(sparam, pfx) == 0)
   {
      if(g_suppressDeleteEvents || TickDeadlinePending(g_suppressDeleteEventsUntilMs)) return false;   // bulk teardown — nothing to heal
      Print("[HRay] object-delete seen \"", sparam, "\"");
      // P-HR-07 (2026-09-28, user: «روی استریپ کلیک میکنم همه پاک میشه»): the
      // cascade is ONE WAY. The dot is the ray's CHILD, so a deleted LINE takes
      // its dot with it — but a deleted DOT takes nothing, because the dot dies
      // on every click that dismisses it (`HRaySelect("")`) and on every new
      // placement. The old two-way rule read that dismissal as "the ray is gone"
      // and deleted the line under the hand: one click on a strip cell erased
      // the ray, and placing a second ray erased the first.
      if(HRayIsHandle(sparam)) return false;
      string ln = sparam;
      ObjectDelete(0, HRayHandleName(ln));
      if(ObjectFind(0, ln) < 0)
         HRayRegDel(StringSubstr(ln, StringLen(pfx)));
      if(s_hrayDrag != "" && ObjectFind(0, s_hrayDrag) < 0) HRayDragRelease();   // P-HR-06: lock back
      if(s_hraySel != "" && ObjectFind(0, s_hraySel) < 0) s_hraySel = "";
      return false;
   }
   // The dot rides every channel the chart moves in (pan stream included);
   // orphans are adopted here too — chart change is rare, the scan is not hot.
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      HRayAdoptOrphans();
      HRayFollowAll();
      return false;
   }
   if(id == CHARTEVENT_KEYDOWN && lparam == 27)   // ESC ends drag AND arm
   {
      if(s_hrayDrag != "") { HRayDragRestore(); HRayDragEnd(); return true; }
      if(s_hrayArmed) { HRayCancel(); return true; }
      return false;
   }
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      bool leftDown = ((st & 1) != 0);
      bool rightDown = ((st & 2) != 0);
      bool pressed = (leftDown && !s_hrayLeft);
      s_hrayLeft = leftDown;   // ... updated on EVERY event (a still click emits none)
      // P-UI-145: there is no lock state in this file — the arbiter's single stamp is the whole law.
      if(s_hrayDrag != "")
      {
         if(rightDown)   // right-click puts the ray back where the press found it
         {
            HRayDragRestore();
            HRayDragEnd();
            return true;
         }
         //--- P-UI-143 (2026-10-02, MEASURED): a move with the button bit CLEAR while
         //--- we hold the ray is the TERMINAL drawing its own thing (it does not claim
         //--- the button for its own tools), and its only other word comes once, at the
         //--- very end — so this is the one place the ray can be put back in flight.
         if(!leftDown && (int)StringToInteger(sparam) == 0)
         {
            HRayDragRestore();
            HRayDragEnd();
            return true;
         }
         if(!leftDown) { HRayDragEnd(); return true; }   // release = final
         ChartViewLockAssert();   // re-assert every held step (a reset must not win)
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
         {
            if(!s_hrayMoved &&
               (MathAbs((int)lparam - s_hrayPressX) > 2 || MathAbs((int)dparam - s_hrayPressY) > 2))
               s_hrayMoved = true;   // pixels, not ticks: a still hand is a click
            if(s_hrayMoved) HRayDragApply(s_hrayDrag, ct, cp);
         }
         return true;
      }
      if(s_hrayArmed)   // armed: right cancels, hovers pass
      {
         if(rightDown) { HRayCancel(); return true; }
         return false;
      }
      // P-LM-13: a press while a gesture is still "live" never happens here —
      // the drag above owns release, so a rising edge is always a fresh press.
      if(pressed && pfx != "")
      {
         // P-UI-92: a press on a UI surface (strip, card) belongs to the UI —
         // grabbing a ray from under the strip would answer two owners at once.
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return false;
         // P-UI-142: ...and so does a hand that is busy with the TERMINAL's own tool
         // (the shared arbiter's question) or with another one of OUR armed sessions
         // (P-HR-06's one gesture at a time). A press in either window is not ours.
         if(GestureGrabBlocked()) return false;
         if(BaseKnotSessionActive() || PathSessionActive()) return false;
         string ln = "";
         if(HRayPressHit((int)lparam, (int)dparam, ln))
         {
            // P-UI-144: THE HAND IS OURS TO GIVE — the same question the path asks (the arbiter
            // owns it, GlobalVariables.mqh): a drawing that is not already TAKEN cannot
            // be taken, so the first press selects and writes no anchor. Three
            // measurements closed the detection road (no "native tool armed" flag; the
            // terminal is silent for a whole native stroke and speaks once at its end;
            // its button bit flaps mid-press), so the owner is decided, not detected.
            if(!GestureTakeAllowed(ln))
            {
               s_hrayPressX = (int)lparam; s_hrayPressY = (int)dparam;
               HRaySelect(ln); HRayHandleFollow(ln); GestureTakeNote(ln);
               return true;
            }
            s_hrayPressX = (int)lparam; s_hrayPressY = (int)dparam;   // the carry's own origin
HRayDragStart(ln);   // select + carry in one press
             Print("[HRay] carry ", ln, " why=", GestureTakeWhy());   // P-UI-144: the carry's own half of the proof
             return true;
         }
      }
      if(s_hraySel != "") HRayHandleFollow(s_hraySel);   // pan stream (guarded: still = reads)
      return false;
   }
   if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") >= 0)   // right-click encoding
   {
      if(s_hrayArmed) { HRayCancel(); return true; }
      return false;
   }
   if(id == CHARTEVENT_CLICK)
   {
      // P-LM-13: a motionless press emits NO mouse move, so a still press on a
      // ray leaves the carry live with no release coming — and a release move
      // lost off-chart does the same. The click IS the end, moved or not.
      if(s_hrayDrag != "") HRayDragEnd();
      if(s_hrayArmed)
      {
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;   // P-UI-92: the tap is the UI's
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
         {
            HRayPlace(ct, cp);
            s_hrayArmed = false;
            ChartViewLockRelease();   // the arm's acquire ends with the commit
            ChartRedraw();
         }
         return true;
      }
      // Idle click: on the dot = select (+double = remove), anywhere else the
      // dot goes — an unselected chart wears no circle (P-HR-03).
      string ln = "";
      if(pfx != "" && HRayDotHit((int)lparam, (int)dparam, ln))
      {
         uint now = GetTickCount();
         // P-HR-06: the release-click trailing a moved drag is select-only —
         // counting it as double-click #1 would delete on the next single tap.
         if(s_hrayEndMs != 0 && now - s_hrayEndMs <= HRAY_DBL_MS)
         {
            s_hrayEndMs = 0; s_hrayClick = "";
            HRaySelect(ln); HRayHandleFollow(ln);
            return true;
         }
         if(s_hrayClick == ln && now - s_hrayClickMs <= HRAY_DBL_MS &&
            MathAbs((int)lparam - s_hrayClickX) <= HRAY_DBL_PX &&
            MathAbs((int)dparam - s_hrayClickY) <= HRAY_DBL_PX)
         {
            s_hrayClick = "";
            HRayDelete(ln, "dot double-click");
         }
         else
         {
            HRaySelect(ln);
            HRayHandleFollow(ln);
            Print("[HRay] select \"", ln, "\"");
            s_hrayClick = ln; s_hrayClickMs = now;
            s_hrayClickX = (int)lparam; s_hrayClickY = (int)dparam;
         }
         return true;
      }
      if(s_hraySel != "")
      {
         Print("[HRay] dismiss dot \"", s_hraySel, "\" (line stays)");
         HRaySelect(""); ChartRedraw();
      }
      s_hrayClick = "";
      return false;
   }
   return false;
}
// Fresh instance (attach / TF switch reuses the same chart): adopt the chart's
// rays — statics may not know them yet, but the objects survived. Idempotent.
void HRayOnInit()
{
   s_hrayArmed = false;
   s_hrayDrag = "";
   s_hraySel = "";
   s_hrayClick = "";
   HRayAdoptOrphans();
}
// Deinit safety: a remove must never leave a stuck arm; committed rays are
// chart objects, so only REASON_REMOVE sweeps them (a TF switch keeps them).
void HRayOnDeinit(const int reason)
{
   s_hrayArmed = false;
   s_hrayDrag = "";
   s_hraySel = "";
   if(reason == REASON_REMOVE)
   {
      string pfx = HRayPrefix();
      if(pfx != "") ObjectsDeleteAll(0, pfx);
      ArrayResize(s_hrayIds, 0);
   }
}

#endif // HRAY_TOOL_MQH
