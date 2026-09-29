// BaseKnot_Drag.mqh - BaseKnotTool split 2026-09-29: exact lines 5375-6813 of BaseKnotTool.mqh, byte-identical, zero renames.
#ifndef BASE_KNOT_DRAG_MQH
#define BASE_KNOT_DRAG_MQH

// Unified per-step drag follow — the ONLY mid-drag children writer (P-BK-07).
// Both event channels call it with what they carry: OBJECT_DRAG brings live
// anchors only (its cursor coords are untrusted — in-repo pattern, TH3Tool
// reads anchors there too), MOUSE_MOVE brings the trusted cursor. Source
// priority is single: BOX live anchors while the terminal moves them (exact —
// MT4 magnet/snap included, ~14 cheap syscalls, never a full Sync),
// [BKCURSOR-OFF: the cursor-delta path that used to run "only while anchors sit
// frozen mid-drag" is retired dead-by-construction below — the terminal's own
// native drag is the ONE writer of a box, and it is the LIVE one.] Release still does the
// authoritative BaseKnotSync; the 500 ms pump heals anything that loses it
// (P-BK-18).
//
// P-BK-18 (2026-09-14, user report «یکیش لایو درگ میشه یکیش نمیشه»): the
// CHILD MOVE STEP IS NOT BUDGETED ANY MORE. It used to share one 30 ms gate
// with the cursor fallback and the paint, so the border (4 OBJ_TREND edges) was
// up to 30 ms of cursor travel BEHIND the native BOX rectangle — the fill
// tracked the hand at event rate while the border stepped at 33 fps, which is
// exactly what "one drags live, the other does not" looks like on a fast drag.
// The move step is CHANGE-DRIVEN (4 property reads, then writes only when the
// box really moved), so an unbudgeted call is free while nothing moves, and it
// never adds a REPAINT: MT4 already repaints the dragged box on this very
// frame, and BaseKnotDragPaint() keeps its own 30 ms gate. The runs are
// therefore pixel-locked with the fill and no heavier than before.
void BaseKnotFollowDrag(const string id, const datetime curT, const double curP)
{
   s_bkDragActMs = GetTickCount();   // activity even when the cursor budget below absorbs this call
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
      // P-BK-19a: the anchors moved WITHOUT us — a fallback write folds itself
      // into s_bkFol* the moment it lands, so a difference here IS somebody else
      // moving the box, i.e. the TERMINAL's own native drag. The gesture is
      // claimed for the rest of it: a second writer is the P-BK-07 fight, and
      // P-BK-15 says MT4 cancels the drag the second writer would be fighting.
      s_bkNativeClaim = true;
      s_bkFolT1 = t1; s_bkFolT2 = t2; s_bkFolP1 = p1; s_bkFolP2 = p2;
      uint mkT = GetTickCount();   // P-PERF-43: this gesture measures itself (see the release line)
      BaseKnotMoveChildren(id, t1, p1, t2, p2);
      uint mkD = GetTickCount() - mkT;
      if(mkD > s_bkPerfMoveWorst) s_bkPerfMoveWorst = mkD;
      s_bkPerfPasses++;
   }
   // BKCURSOR-OFF (2026-09-14, user decision — «داخل باکس دوتا درگ فعال داریم،
   // یکیش رو حذف کن، اونی که لایو نیست»). TWO drags wrote the box: the
   // TERMINAL's own native drag (the LIVE one — it moves the anchors at event
   // rate and MT4 repaints the fill on that same frame) and this CURSOR-DELTA
   // fallback, which was rate-limited by design (BK_DRAG_CURSOR_MS 30) because
   // every write it makes is a full repaint the terminal did not ask for — i.e.
   // the one the user feels as stepped, not live. The live path is enough on any
   // build that drags the box at all (that is what the gesture ledger shows:
   // `native=1` on every real drag), so the second writer is retired DEAD BY
   // CONSTRUCTION, exactly like the panel drag (PANELDRAG-OFF). Its whole body
   // stays in place and compiles, so a restore is one word. TO RESTORE: drop the
   // `false &&`, and keep the P-BK-19a claim + the P-BK-19b role measurement
   // (BaseKnotGrabRole) that made it a second writer of ONE owner instead of a
   // fight — the gate group `[bkcursor-off]` asserts the retirement in both
   // directions, so a half-restore FAILS.
   else if(false && !s_bkNativeClaim &&
           curT > 0 && curP > 0 && id == s_bkDragId && s_bkDragT0 > 0 &&
           GetTickCount() - s_bkOwnerMs >= BK_DRAG_OWNER_MS)
   {
      // P-BK-18: THIS path moves the BOX itself (below), so it keeps the budget
      // — an unbudgeted box-write storm would drive a repaint per mouse move
      // where the terminal is not repainting anything of its own.
      uint cms = GetTickCount();
      if(cms - s_bkDragMs < BK_DRAG_CURSOR_MS) return;
      s_bkDragMs = cms;
      // Anchors frozen and NOBODY else claimed the box: the terminal is NOT
      // moving it natively on this gesture (frozen build, or the grab never
      // engaged), so the cursor owns it (the press latch belongs to s_bkDragId,
      // so only that box may use it). Absolute from the press base (never
      // incremental), so rounds converge exactly and can never drift or
      // double-count; the moment the terminal moves the anchors itself, the
      // exact branch above wins again.
      //
      // P-BK-19b: write ONLY what the press grabbed (s_bkGrabSel, measured on the
      // press pixels). A body grab translates both corners with their offset kept
      // — byte-identical to P-BK-16 — while an edge/corner grab is a RESIZE: that
      // side's value follows the cursor and the OPPOSITE side is never written.
      int dt = (int)(curT - s_bkDragT0);
      double dp = curP - s_bkDragP0;
      datetime ft1 = s_bkDragBT1, ft2 = s_bkDragBT2;
      double fp1 = s_bkDragBP1, fp2 = s_bkDragBP2;
      if(s_bkGrabSel == BK_GRAB_ALL)   // body grab = MOVE (the press offset is preserved)
      {
         ft1 += dt; ft2 += dt; fp1 += dp; fp2 += dp;
      }
      else                             // edge/corner grab = RESIZE (only the grabbed side travels)
      {
         if((s_bkGrabSel & BK_GRAB_T1) != 0) ft1 = curT;
         if((s_bkGrabSel & BK_GRAB_P1) != 0) fp1 = curP;
         if((s_bkGrabSel & BK_GRAB_T2) != 0) ft2 = curT;
         if((s_bkGrabSel & BK_GRAB_P2) != 0) fp2 = curP;
      }
      if(!s_bkFallLogged)   // ONE line per gesture: who owned it is the answer the next report needs
      {
         s_bkFallLogged = true;
         Print("[BK] drag cursor-owned box=", id, " role=", s_bkGrabSel,
               (s_bkGrabSel == BK_GRAB_ALL ? " (move)" : " (resize)"));
      }
      ObjectMove(0, box, 0, ft1, fp1);
      ObjectMove(0, box, 1, ft2, fp2);
      s_bkFolT1 = ft1; s_bkFolT2 = ft2; s_bkFolP1 = fp1; s_bkFolP2 = fp2;
      uint fkT = GetTickCount();   // P-PERF-43
      BaseKnotMoveChildren(id, ft1, fp1, ft2, fp2);
      uint fkD = GetTickCount() - fkT;
      if(fkD > s_bkPerfMoveWorst) s_bkPerfMoveWorst = fkD;
      s_bkPerfPasses++;
   }
   // BKCURSOR-OFF: the live path is the ONLY path — no anchor move and no
   // terminal drag means there is nothing to follow and nothing to paint.
   else return;   // nothing moved — skip the repaint too
   uint pkT = GetTickCount();   // P-PERF-43: the repaint is the other half of the lag
   BaseKnotDragPaint();
   uint pkD = GetTickCount() - pkT;
   if(pkD > s_bkPerfPaintWorst) s_bkPerfPaintWorst = pkD;
}
//+------------------------------------------------------------------+
//| P-BK-61 — THE HANDLE GESTURE: the terminal drags the CHIP, we    |
//| write the grabbed side of the box.                               |
//|                                                                  |
//| ONE WRITER, AND IT IS NOT THE DRAGGED OBJECT. A native drag is   |
//| cancelled by rewriting the object the terminal drags (P-BK-15) — |
//| here that object is the CHIP, so the box, its four edges,         |
//| Entry/SL/TP, the note and every OTHER chip are free to follow     |
//| live, while the chip under the hand is left exactly where the     |
//| terminal put it (the keeper's `skip`). The P-BK-59 grip already   |
//| proved the other half of the same rule: a screen object written   |
//| during a BOX drag does not cancel that drag.                     |
//|                                                                  |
//| ROLES BY VALUE, NEVER BY INDEX: the box' two anchors arrive in    |
//| either order (every other reader here normalises with min/max),   |
//| so "the top edge" IS whichever anchor holds the top price. A side |
//| dragged past the far one MIRRORS the rectangle instead of          |
//| inverting it — what the terminal's own rectangle does — and since |
// the roles are min/max the box can never collapse to zero height.  |
//|                                                                  |
//| THE TIME LANDS ON A BAR OPEN when one is that close (`the terminal|
// snaps corner times to bar opens` — BaseKnotCommit's own rule), so  |
// a resized box keeps the base walk counting WHOLE candles. A time  |
// PAST the last bar (the very common "pull the right edge into the  |
// future") has no such bar and is kept exactly as the hand left it. |
//+------------------------------------------------------------------+
datetime BaseKnotGripSnapTime(const datetime t)
{
   if(t <= 0) return t;
   int shift = iBarShift(_Symbol, 0, t, false);
   if(shift < 0) return t;
   datetime bo = iTime(_Symbol, 0, shift);
   if(bo <= 0) return t;
   double half = (double)PeriodSeconds() / 2.0;
   if(MathAbs((double)(t - bo)) > half) return t;   // not "that close" to a bar open
   return bo;
}
//+------------------------------------------------------------------+
//| P-BK-61 — AND THE CONTROL MAGNET.                                |
//|                                                                  |
//| «با کنترل هم مگنت فعال میشه ... حرکت رو چسبوند به کندل های و لو  |
//| که دقیق باشه» — while the hand drags a handle AND Shift is held, |
//| the price it writes snaps to the candle HIGH/LOW of the bar under|
//| the cursor, inside `inpMagnetSensitivityPips` (MAGNET SENS — the |
//| user's own input, still editable on the indicator's Inputs tab;   |
//| its card row stays retired). A plain (Shift-free) handle drag is  |
//| still hand-exact, which is the whole point of the modifier.       |
//|                                                                  |
//| WHY THIS IS NOT BKMAGNET2-OFF REVIVED: that decision («مگنت نمیخواد|
// باشه حذفش کن») retired the magnet on the BOX' OWN drag, and the box |
// still stays exactly where the hand let it go. This is a different  |
// gesture, asked for later, gated by a modifier the user holds on     |
// purpose, and it never runs inside BaseKnotFollowDrag (the box' live |
// follow) nor in BaseKnotSnapPrice (the draw-time owner, which stays  |
// the identity). `check_bkmagnet` now asserts all four of those —    |
// see tools/panel-wiring-audit.py, and never relax that group without|
// reading it first.
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-BK-66 — THE MAGNET'S MODIFIER IS SHIFT, NOT CONTROL.           |
//|                                                                  |
//| Reported: «من ctrl که میگیرم برای مگنت این باکس رو کپی میکنه» —  |
//| MetaTrader's own Ctrl+drag DUPLICATES a draggable object, and    |
//| the box' handles ARE draggable objects (their OBJPROP_SELECTABLE |
//| is what makes them handles at all, P-BK-61), so the terminal     |
//| cloned the chip instead of letting the magnet snap it. Ctrl is   |
//| the terminal's copy gesture, so the magnet needed another key.   |
//|                                                                  |
//| THE FOUR POLLABLE MODIFIERS, and why only one works:             |
//|   * SHIFT   — pollable as TERMINAL_KEYSTATE_SHIFT, and MT4 binds |
//|               no object-drag behaviour to it. THIS IS THE CHOICE.|
//|   * CONTROL — the terminal's duplicate gesture. Never again.     |
//|   * ALT     — pollable as TERMINAL_KEYSTATE_MENU, but Windows    |
//|               and the terminal both eat it (menus, Alt+Tab):     |
//|               a magnet that dies on a window switch is worse     |
//|               than no magnet.                                    |
//|   * MIDDLE  — pollable (TERMINAL_KEYSTATE_MIDDLE), but no hand   |
//|              holds the middle button while dragging the left one.|
//|                                                                  |
//| The probe is ONE function by ROLE (UIMagnetModifierDown(), see   |
//| UtilityFunctions.mqh), so the next report is a key name, not a   |
//| refactor — and `check_bkmagnet` asserts BOTH halves: the probe   |
//| reads SHIFT, and nothing in the magnet's path spells CONTROL.    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-BK-64 (2026-09-16) — THE MAGNET MEASURES IN PIXELS.            |
//|                                                                  |
//| Reported: «مگنت درست کار نمی‌کنه». The gate was the UNIT, not the |
//| idea: `inpMagnetSensitivityPips` × the symbol's pip. 10 pips on a |
//| D1 GBP/USD chart is under ONE pixel of a 1000-pip candle — the    |
//| hand aims at a wick it can SEE, and at that zoom ±5 px IS ±50     |
//| pips, so the gate was narrower than the eye and the magnet never  |
//| fired. A magnet that only works when you are already exact reads  |
//| as dead.                                                          |
//|                                                                  |
//| HOW THE SHIPPED MAGNETS DO IT (the reference this follows, from   |
//| the published MetaTrader magnet utilities — MT5's own chart       |
//| magnet and the MQL5 market tools «OHLC Magnet» 38178, «KT Drawing |
//| Tool» 161169, «Easy Toolbar»'s magnet mode — all of them the SAME |
//| rule): the reach is a PIXEL PROXIMITY, and the target is the      |
//| NEAREST of a bar's FOUR prices — «drag ... within the Pixel        |
//| Proximity ... snaps to Open/High/Low/Close», «stick to nearest     |
//| Open/High/Low/Close values of bars». Pixels are what the hand     |
//| actually controls, and the conversion is the chart's own price→Y   |
//| projection, so nothing here assumes a zoom, a timeframe or an      |
//| instrument.                                                       |
//|                                                                  |
//| SO: the candidates are O/H/L/C of the bar under the cursor (the    |
//| time was already snapped to a bar OPEN by BaseKnotGripSnapTime, so |
//| it is the bar the user points at); the winner is the smallest PIXEL|
//| distance to the dragged point; the reach is the user's own        |
//| `inpMagnetSensitivityPips` converted through the LIVE pip→pixel    |
//| scale and then clamped to [BK_MAGNET_MIN_PX, BK_MAGNET_MAX_PX] —   |
//| so a snap is never unreachable (a wide zoom cannot shrink the      |
//| reach to nothing) and never wild (a tight zoom cannot fling the    |
//| edge across the candle). Sensitivity 0 keeps its old meaning as    |
//| the tightest reach the hand can still use.                        |
//|                                                                  |
//| COST: reads only, on the gesture's own OBJECT_DRAG steps (nothing  |
//| per tick): 4 bar reads + up to 6 projections per step, and ZERO    |
//| when the magnet is off or Shift is not held — `BaseKnotGripDrag`   |
//| gates the call, and the two early returns here are the other half. |
//+------------------------------------------------------------------+
#define BK_MAGNET_MIN_PX 8    // a hand cannot aim finer than this at any zoom
#define BK_MAGNET_MAX_PX 26   // ...and a snap must stay local (never across the candle)
static double s_bkMagnetPx = -1.0;   // px distance of the last snap (-1 = it did not fire)
double BaseKnotGripSnapPrice(const datetime t, const double price)
{
   s_bkMagnetPx = -1.0;
   if(t <= 0 || price <= 0) return price;
   if(!inpEnableMagnet) return price;
   int shift = iBarShift(_Symbol, 0, t, false);
   if(shift < 0) return price;
   double cand[4];
   cand[0] = iOpen(_Symbol, 0, shift);
   cand[1] = iHigh(_Symbol, 0, shift);
   cand[2] = iLow(_Symbol, 0, shift);
   cand[3] = iClose(_Symbol, 0, shift);
   int dx = 0, dy = 0;
   if(!ChartTimePriceToXY(0, 0, t, price, dx, dy)) return price;
   double pipPx = 0.0;   // the user's own sensitivity, in the unit the hand uses
   int sx = 0, sy = 0;
   if(ChartTimePriceToXY(0, 0, t, price + BaseKnotPipSize(), sx, sy))
      pipPx = MathAbs((double)(sy - dy));
   double gatePx = pipPx * (double)inpMagnetSensitivityPips;
   if(gatePx < BK_MAGNET_MIN_PX) gatePx = BK_MAGNET_MIN_PX;
   if(gatePx > BK_MAGNET_MAX_PX) gatePx = BK_MAGNET_MAX_PX;
   double best = price, bestPx = -1.0;
   for(int i = 0; i < 4; i++)
   {
      if(cand[i] <= 0) continue;   // an absence (no data for that bar) — never invented
      int cx = 0, cy = 0;
      if(!ChartTimePriceToXY(0, 0, t, cand[i], cx, cy)) continue;
      double d = MathAbs((double)(cy - dy));
      if(bestPx < 0.0 || d < bestPx) { bestPx = d; best = cand[i]; }
   }
   if(bestPx < 0.0 || bestPx > gatePx) return price;   // nothing inside the proximity
   s_bkMagnetPx = bestPx;   // the gesture ledger reads this (one line per snap)
   return best;
}
// A handle drag → the grabbed side of the box, live (one OBJECT_DRAG per step: the
// channel the box' own follow already runs on). `name` is the chip the terminal moved;
// its CENTRE pixel is the reading (see the block above). Locked boxes answer nothing:
// the keeper has already retired their family.
void BaseKnotGripDrag(const string id, const int side, const string name)
{
   if(id == "" || name == "" || side == 0) return;
   if(BaseKnotFind(id) < 0) return;
   if(BaseKnotLocked(id)) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   int gx = (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) + BK_GRIP_PX / 2;
   int gy = (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) + BK_GRIP_PX / 2;
   int w = 0; datetime gt = 0; double gp = 0;
   if(!ChartXYToTimePrice(0, gx, gy, w, gt, gp)) return;
   if(w != 0 || gt <= 0 || gp <= 0) return;
   bool modifier = UIMagnetModifierDown();   // P-BK-66: SHIFT — MT4's Ctrl+drag copies the chip
   gt = BaseKnotGripSnapTime(gt);
   if(modifier && (side & (BK_GS_T | BK_GS_B)) != 0) gp = BaseKnotGripSnapPrice(gt, gp);
   // P-BK-64: the magnet answers with a NUMBER — once per gesture, on the step that
   // snapped, carrying the pixel distance it accepted and the value it took. A
   // snapping gesture is rare (modifier held + inside the proximity), so the line costs
   // nothing in steady state and turns the next report into a reading.
   if(s_bkMagnetPx >= 0.0 && !s_bkMagnetLogged)
   {
      s_bkMagnetLogged = true;
      Print("[BK] magnet box=", id, " side=", side, " px=", (int)s_bkMagnetPx,
            " -> ", DoubleToString(gp, GetCachedDigits()));
   }
   datetime bt1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime bt2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double bp1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double bp2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   datetime tL = bt1, tR = bt2;
   if(tR < tL) { datetime tt = tL; tL = tR; tR = tt; }
   double top = MathMax(bp1, bp2), bot = MathMin(bp1, bp2);
   if((side & BK_GS_T) != 0) top = gp;
   if((side & BK_GS_B) != 0) bot = gp;
   if((side & BK_GS_L) != 0) tL = gt;
   if((side & BK_GS_R) != 0) tR = gt;
   // THE GESTURE IS THE TERMINAL'S (it drags the chip): claim it, so the release path
   // Syncs exactly this box, the pump leaves it alone for the rest of the gesture
   // (P-BK-15), and the retired cursor fallback could never touch it either.
   s_bkNativeClaim = true;
   // P-BK-65: the terminal NAMED this chip, so THIS PRESS IS A RESIZE — the answer
   // the release needs, latched here and cleared only by a witness that cannot lie
   // (the release, the pump's silence watchdog, an OBJECT_DRAG that names the BOX
   // instead, or teardown). `s_bkGripLive` below stays what it always was: which
   // chip the hand holds RIGHT NOW, i.e. the keeper's skip.
   s_bkGripGesture = side;
   s_bkBoxNamed    = false;   // it is dragging a CHIP, so by definition not the box
   s_bkGripLive = side;
   s_bkDragId = id;
   s_bkDragActMs = GetTickCount();
   ObjectMove(0, box, 0, tL, top);
   ObjectMove(0, box, 1, tR, bot);
   BaseKnotMoveChildren(id, tL, top, tR, bot);   // the SAME mover every other live step uses
   BaseKnotDragLockOn();                         // a resize owns the view, like a move
   if(!s_bkGripLogged)
   {
      s_bkGripLogged = true;
      Print("[BK] grip resize box=", id, " side=", side,
            " tag=", StringSubstr(name, StringLen(pfx)), " magnet=", (modifier ? 1 : 0));
   }
   BaseKnotDragPaint();
}
//+------------------------------------------------------------------+
//| P-BK-61b (2026-09-16) — THE BODY DRAG IS A MOVE, AND ONLY A MOVE.|
//|                                                                  |
//| User: «این باکس الآن از دو روش میشه بزرگ و کوچیکش کرد ... از رنگ  |
//| ریسایز نشه فقط درگ بشه» — resize must have ONE home (the eight   |
//| handles on the border), and grabbing the FILL must only carry the|
//| box. WHY IT COULD GROW BEFORE: MetaTrader's own magnet snaps EACH |
//| of a dragged rectangle's two anchors to a wick INDEPENDENTLY (the |
//| fact behind P-BK-25's "a whole-box MOVE can read as a one-side     |
//| resize"), so a body drag on a magnet-enabled terminal could leave |
//| the box a different SIZE than the hand took it with.             |
//|                                                                  |
//| WHAT IS RESTORED, AND WHAT IS NOT: only the SIZE — from the      |
//| press-time snapshot, which P-BK-25's `s_bkSnapTrusted` proves was |
//| taken BEFORE the terminal moved anything (a snapshot taken mid-   |
//| drag could read a translation as a resize, and a role that cannot |
//| be measured must not invent one). The POSITION stays exactly where|
//| the hand let it go, magnet included (BKMAGNET2-OFF's own rule).   |
//|                                                                  |
//| COST: one call at the RELEASE only, steady state an anchor read   |
//| plus a compare; and it runs after the button is up, never into a  |
//| live native drag (P-BK-15). The alternative — translating the box |
//| by the hand's own cursor delta — was rejected because it would    |
//| throw the terminal's own position snapping away with it.          |
//+------------------------------------------------------------------+
bool BaseKnotBodySizeHeal(const string id)
{
   if(id == "" || !s_bkSnapTrusted) return false;   // unmeasured baseline — never invent
   // P-BK-65: AND THE HEAL'S OWN PRECONDITION IS THE GESTURE, NOT THE BASELINE. This
   // function exists for ONE fault shape — MetaTrader's magnet enlarging the FILL of a
   // rectangle the TERMINAL is moving. A press that dragged a CHIP is a resize the user
   // asked for, and restoring a press-time size there is exactly the «برمی‌گرده سر جای
   // خودش» report (the far edge jumped to `tL + wT`). `s_bkBoxNamed` is that answer from
   // the terminal's own mouth (its OBJECT_DRAG named the BOX), so the heal now needs the
   // trusted baseline AND a terminal-named box drag: even if the release's own gate were
   // ever lost to a future edit, a chip gesture still cannot spring the box back.
   if(!s_bkBoxNamed) return false;
   int k = BaseKnotFind(id);
   if(k < 0) return false;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return false;
   datetime pT1 = s_bkDragBT1, pT2 = s_bkDragBT2;
   if(pT2 < pT1) { datetime pt = pT1; pT1 = pT2; pT2 = pt; }
   double pTop = MathMax(s_bkDragBP1, s_bkDragBP2), pBot = MathMin(s_bkDragBP1, s_bkDragBP2);
   long   wT = (long)(pT2 - pT1);
   double hP = pTop - pBot;
   if(wT <= 0 || hP <= 0) return false;   // the snapshot cannot describe a box
   datetime lt1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime lt2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double lp1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double lp2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   datetime tL = lt1, tR = lt2;
   if(tR < tL) { datetime tt = tL; tL = tR; tR = tt; }
   double top = MathMax(lp1, lp2), bot = MathMin(lp1, lp2);
   if((long)(tR - tL) == wT && MathAbs((top - bot) - hP) < GetCachedPoint())
      return false;   // the size IS the press-time size — a pure move, nothing to write
   // The size comes back around the corner the drop left in place (the box' left /
   // top edge IS the hand's own answer for where the box went): one write pair, and
   // never a touch on the position.
   ObjectMove(0, box, 0, tL, top);
   ObjectMove(0, box, 1, (datetime)((long)tL + wT), top - hP);
   return true;
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
// P-BK-24 — THE SAME QUESTION, ASKED IN PIXELS. `BaseKnotBoxAt` is an exact
// INSIDE test in price/time terms, which is the right answer when the cursor is
// genuinely inside the box — and the wrong one when the user presses the drawn
// border: the visible line is `inpBoxBorderWidth` px wide and sits ON the
// boundary, so its outer half is already outside the rectangle, and the terminal
// accepts that press (its own hit test has a few px of tolerance) while our
// latch did not. The press point is therefore measured against the box's two
// corners through `ChartTimePriceToXY` (the same projection `BaseKnotGrabRole`
// already uses), inflated by `BK_PRESS_SLOP_PX` — never a price estimate.
string BaseKnotBoxAtPx(const int mx, const int my)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   BaseKnotLazyInit();
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string box = BaseKnotBoxName(BaseKnotPrefix(g_bkBoxes[i].id));
      if(ObjectFind(0, box) < 0) continue;
      int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
      if(!ChartTimePriceToXY(0, 0, (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0),
                             ObjectGetDouble(0, box, OBJPROP_PRICE, 0), x1, y1)) continue;
      if(!ChartTimePriceToXY(0, 0, (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1),
                             ObjectGetDouble(0, box, OBJPROP_PRICE, 1), x2, y2)) continue;
      if(mx >= MathMin(x1, x2) - BK_PRESS_SLOP_PX && mx <= MathMax(x1, x2) + BK_PRESS_SLOP_PX &&
         my >= MathMin(y1, y2) - BK_PRESS_SLOP_PX && my <= MathMax(y1, y2) + BK_PRESS_SLOP_PX)
         return g_bkBoxes[i].id;
   }
   return "";
}
// P-BK-19b — WHAT did this press grab? MEASURED in pixels against the box's own
// two corners (ChartTimePriceToXY — the same call the placement rule and the
// box's own preview place objects with), never assumed: inside
// BK_GRAB_CORNER_PX of a corner ⇒ that corner's two values; inside
// BK_GRAB_EDGE_PX of one edge ⇒ that edge's single value; anywhere else ⇒ the
// body (all four = the P-BK-16 MOVE). Neither axis counts as an edge if the box
// is too small to aim inside it (every press would land in the band), and a box
// whose corners cannot be projected (off-window, zero-size) answers BK_GRAB_ALL —
// a role that cannot be measured must not invent, it falls back to the move it
// always did. Reads only; called once per gesture, at the press.
int BaseKnotGrabRole(const string box, const int mx, const int my)
{
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   datetime bt1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime bt2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   if(!ChartTimePriceToXY(0, 0, bt1, ObjectGetDouble(0, box, OBJPROP_PRICE, 0), x1, y1)) return BK_GRAB_ALL;
   if(!ChartTimePriceToXY(0, 0, bt2, ObjectGetDouble(0, box, OBJPROP_PRICE, 1), x2, y2)) return BK_GRAB_ALL;
   int dCorner = BK_GRAB_CORNER_PX, dEdge = BK_GRAB_EDGE_PX;
   if(MathAbs(mx - x1) <= dCorner && MathAbs(my - y1) <= dCorner)   // corner at anchor 1
      return BK_GRAB_T1 | BK_GRAB_P1;
   if(MathAbs(mx - x2) <= dCorner && MathAbs(my - y2) <= dCorner)   // corner at anchor 2
      return BK_GRAB_T2 | BK_GRAB_P2;
   int wSpan = MathAbs(x2 - x1), hSpan = MathAbs(y2 - y1);
   if(wSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(mx - x1) <= dEdge) return BK_GRAB_T1;   // vertical edge, anchor 1
   if(wSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(mx - x2) <= dEdge) return BK_GRAB_T2;   // vertical edge, anchor 2
   if(hSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(my - y1) <= dEdge) return BK_GRAB_P1;   // horizontal edge, anchor 1
   if(hSpan >= BK_GRAB_MIN_SPAN_PX && MathAbs(my - y2) <= dEdge) return BK_GRAB_P2;   // horizontal edge, anchor 2
   return BK_GRAB_ALL;   // body press = MOVE
}
// P-BK-18 — does the box's own VISIBLE top edge still describe the box?
// The top edge is the child that carries both the box's time span and its top
// price, so it is the cheapest honest witness that the border is where the box
// is; false = the border is behind and needs the authoritative Sync (the pump's
// settle heal). Reads only: three property reads in steady state, no writes.
bool BaseKnotBorderSettled(const string pfx, const datetime t1, const datetime t2, const double top)
{
   string edgeT = pfx + BK_EDGE_T;
   if(ObjectFind(0, edgeT) < 0) return false;   // missing edge = not settled (Sync rebuilds it)
   if((datetime)ObjectGetInteger(0, edgeT, OBJPROP_TIME, 0) != t1) return false;
   if((datetime)ObjectGetInteger(0, edgeT, OBJPROP_TIME, 1) != t2) return false;
   return (ObjectGetDouble(0, edgeT, OBJPROP_PRICE, 0) == top);
}
// Per-tick (500 ms) re-glue: scroll/zoom moves pixel badges, box anchors don't.
void BaseKnotSyncBadges()
{
   BaseKnotLazyInit();   // the registry IS the box list — rebuild once (guarded, O(1) after)
   // P-BK-58: the corner row's own keeper rides this pump (≤500 ms in Lite, and on every chart
   // change): a selection, a mode change, a pushed slot or a box that left this TF are all
   // noticed here, without a second event path of its own. NOTHING is written while nothing
   // changed — steady state is a compare (see BaseKnotNoteCornerRefresh).
   BaseKnotNoteCornerRefresh();
   if(BaseKnotSessionActive()) BaseKnotReassertLock(true);   // P-BK-14: pump drift-heal (timer path, tick-less charts)
   if(s_bkDragLock && g_bkState == BK_IDLE &&
      UILeftButtonUp() &&          // the ONE button owner (P-UI-73): both MQL4
                                   // conventions must agree, or a live drag
                                   // would be torn down by the watchdog
      GetTickCount() - s_bkDragActMs > 1500)
   {
      // Missed release (button up off-window, event stream silent): never
      // leave the view locked. The 1.5 s silence requirement keeps KEYSTATE
      // flicker mid-hold (P-BK-05) from false-triggering — a real drag keeps
      // producing events. KEYSTATE poll in the timer path is P-BK-03 pattern.
      s_bkDragId = "";
      BaseKnotGestureClear();   // P-BK-65/P-BK-61: no release, no live side — and the
                                // gesture's KIND goes with it, so the next press starts
                                // fresh. The settle heal below then Syncs the box from the
                                // anchors the resize already wrote.
      s_bkGripLogged = false; s_bkMagnetLogged = false;
      BaseKnotDragLockOff();
   }
   if(ArraySize(g_bkBoxes) == 0) return;
    datetime tpEdge = BaseKnotTPEdgeTime();   // chart-global: one conversion for the whole pump
    double bkRef = BaseKnotLiveRef();         // P-BK-13: one live price for every follow check below
    // BKEDGE-OFF (P-BK-74): this probe fed the P-BK-18 settle heal only, so it is
    // dormant with it — the restore re-adds this line and the heal together.
    // BKEDGE-OFF: bool bkHandOff = UILeftButtonUp();   // P-BK-18: ONE button probe for the settle heal below
    // P-BK-29/47 — the NOTE'S TWO ANSWERS are derived closed-bar data, so the pump is
    // what has to notice they moved: the LENGTH moves with the class (a new closed bar
    // the rung's own candles are re-read on, or a drag) and the SIDE with the break's
    // story (a break, a return or a second break). The step arrives from the UI layer
    // asynchronously (which zeroes s_bkNodeBar). One chart read for the WHOLE pump,
    // never per box; steady state costs nothing and a moved answer costs one Sync.
    datetime bkNodeBarNow = iTime(_Symbol, 0, 0);
    bool bkNodeDue = (bkNodeBarNow != s_bkNodeBar);
    if(bkNodeDue) s_bkNodeBar = bkNodeBarNow;
    // P-BK-46 — a pushed EngSL that MOVED rewrites every knot's stop and target (the
    // entry and the side stay), so the whole pump rebuilds them once. The ask / push
    // pair runs BEFORE this function (see BaseKnotEngPump), so the epoch read here is
    // this round's own answer; steady state is one compare.
    bool bkEngDue = (s_bkEngEpoch != s_bkEngSeen);
    if(bkEngDue) s_bkEngSeen = s_bkEngEpoch;
    // PERF: coalesce repaints — N boxes healing in one pump used to issue N
    // full ChartRedraws; final pixels are identical with one after the loop.
    bool bkNeedPaint = false;
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
         // No bottom hint on flip either: the rebuilt badge + tooltips already
         // show the new side where the box is.
         bkNeedPaint = true;
      }
      // P-BK-05/06 self-heal + TV-fill 2026-09-07: the BOX rect is the fill
      // layer. Re-assert it within 500 ms when it drifts from the live fill
      // look (bg + FILL false when fill invisible) — read-guarded, so steady
      // state costs syscalls only. Missing edge segments (the visible
      // border) are rebuilt via a full Sync.
      if(!BaseKnotFillHealed(box))
      {
         BaseKnotStyleBox(box);
         bkNeedPaint = true;
      }
      // BKEDGE-OFF (P-BK-74): the four "is an edge segment missing" probes are
      // retired with the family — there is nothing beside the box to lose.
      if(BaseKnotTPStale(pfx))   // pre-tick ray → rebuild
       {
         BaseKnotSync(g_bkBoxes[i].id);
         bkNeedPaint = true;
      }
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
      double top = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      double bot = MathMin(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      // BKEDGE-OFF (P-BK-74) — RETIRED HERE: the P-BK-18 SETTLE HEAL. It compared
      // the top edge against the box on this 500 ms pump because the visible border
      // was a COPY of the box (four trend lines our own follow had to keep in step),
      // so a lost gesture end — a motionless release emits NO mouse-move at all
      // (P-BK-03), a registry gap skips the follow, MT4's own snap at the drop can
      // land a pixel the last follow never saw — left the copy behind until a TF
      // switch. The border IS the box now: the terminal moves it with the rectangle,
      // natively, so there is no second copy to fall behind and nothing to compare.
      // The full story, the dormant `BaseKnotBorderSettled` and the one-line restore
      // are at the retired block below.
      // P-BK-29: the type moved (new bar / warm step) → publish it through the
      // same authoritative Sync the flip and settle heals use. The dragged box
      // never reaches here (it is skipped at the top of the loop — P-BK-15:
      // writing into a live native drag cancels it), and the shadow compare is
      // two ints, so a box whose story is unchanged is never touched.
      if(bkNodeDue)
      {
         BaseKnotNode ndNow;
         BaseKnotNodeRead((g_bkBoxes[i].storyT > 0 ? g_bkBoxes[i].storyT : t2), top, bot,
                          g_bkBoxes[i].baseTFMin,
                          g_bkBoxes[i].exitT, g_bkBoxes[i].storyT, ndNow);   // P-BK-38/41/47/78/79/81: the SAME story, from the SAME exit candle, on the SAME node's time, at the SAME anchor
         // P-BK-47: BOTH answers are compared — the type (the LENGTH: the class or the box'
         // TF moved) and the side (the break's story: a break, a return, a second break).
         if(ndNow.kind != g_bkBoxes[i].nodeKind || BaseKnotNodeDir(ndNow) != g_bkBoxes[i].nodeSide)
         {
            BaseKnotSync(g_bkBoxes[i].id);
            bkNeedPaint = true;
         }
      }
      // P-BK-46: the knot's risk moved (a new bar's EngSL, or the class it is read
      // on) — one authoritative Sync re-measures the stop, the target and the texts.
      if(bkEngDue)
      {
         BaseKnotSync(g_bkBoxes[i].id);
         bkNeedPaint = true;
      }
      // BKEDGE-OFF (P-BK-74): THE SETTLE HEAL IS RETIRED WITH THE THING IT HEALED.
      // P-BK-18 existed because the visible border was a COPY of the box (four
      // trend lines that our own follow had to keep in step), so a lost gesture
      // end left the copy behind. The border IS the box now — the terminal moves
      // it with the rectangle, natively, and there is no second copy to fall
      // behind. `BaseKnotBorderSettled` stays compiled (dead by construction) and
      // this one line is the restore.
      // BKEDGE-OFF: if(bkHandOff && !BaseKnotBorderSettled(pfx, t1, t2, top))
      // BKEDGE-OFF: {
      // BKEDGE-OFF:    BaseKnotSync(g_bkBoxes[i].id);
      // BKEDGE-OFF:    bkNeedPaint = true;
      // BKEDGE-OFF: }
      int tfMin = g_bkBoxes[i].tfMin;
      if(tfMin <= 0) tfMin = BaseKnotIdTF(g_bkBoxes[i].id);
      if(tpEdge > 0 && BaseKnotTFVisible(tfMin)) BaseKnotTPGlue(pfx, tpEdge);   // right-edge hug, hidden-TF boxes skipped
      if(ObjectFind(0, BaseKnotTextName(pfx)) >= 0)   // user text re-glues with the box
         BaseKnotPlaceText(pfx, t1, t2, top, bot, BaseKnotTFMask(tfMin), "");
      if(BaseKnotInfoVisible(g_bkBoxes[i].id))
         BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin, BaseKnotTFMask(tfMin));
      else if(ObjectFind(0, BaseKnotInfoName(pfx)) >= 0)
      {
         BaseKnotInfoWipe(pfx);   // Auto grace over — hide within 500 ms (P-BK-86: the plate goes with the note)
         bkNeedPaint = true;
      }
      // BKDOT-OFF (P-BK-71): the centre cover is retired — the keeper has no call site.
      // BKDOT-OFF: if(BaseKnotDotFollow(pfx, t1, t2, top, bot, !g_bkBoxes[i].locked,
      // BKDOT-OFF:                            (bool)ObjectGetInteger(0, box, OBJPROP_SELECTED),
      // BKDOT-OFF:                            GetBoxBorderRenderColor(), BaseKnotTFMask(tfMin)))
      // BKDOT-OFF:          bkNeedPaint = true;
      // BKGRIP-OFF (P-BK-71): and the corner chips ride no pass any more (`skip` was 0
      // here on purpose; the retired keeper refuses to run anyway).
      // BKGRIP-OFF: if(BaseKnotGripsFollow(g_bkBoxes[i].id, t1, top, t2, bot, !g_bkBoxes[i].locked,
      // BKGRIP-OFF:                              GetBoxBorderRenderColor(), BaseKnotTFMask(tfMin), 0))
      // BKGRIP-OFF:          bkNeedPaint = true;
   }
   if(bkNeedPaint) ChartRedraw();
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
   if(MathAbs(p2 - g_bkP1) < pt)   // a true point-click, not a box — ignore it silently (no bottom text)
   {
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
   // No bottom hint: the info lives ON the box (INFO badge + hover tooltips).
   // To look again: tap the box (re-opens the badge grace) or hover it.
   // P-BK-73: and the box is handed ITS OWN selection, exactly as MT4's own
   // rectangle is still in edit mode when the draw is let go — that is what
   // makes the terminal paint the five markers, i.e. the corner handles the
   // native resize (P-BK-72) is measured against. Last write of the commit,
   // after every property this function owns, so nothing here can undo it.
   BaseKnotSelectBox(id);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| P-BK-21 — THE ADJUST MAGNET: the magnet lives on the RELEASE.     |
//|
//| «می‌خوام روی یک شدو بزارم، بارها باید انجام بدم که روی همون چیز |
//| بزارم» — placing an EDGE of a committed box on a wick was          |
//| pixel work: the terminal's native drag lands the anchor where the  |
//| cursor is, and one chart pixel is many pips once the chart is      |
//| zoomed out, so the target is reachable only by repeating the drag. |
//|
//| BKMAGNET-OFF (2026-09-06) retired the DRAW-time magnet for a real    |
//| reason — corners jumped onto candle shadows and the box never        |
//| landed where the user clicked — and that decision stands:            |
//| `BaseKnotSnapPrice` is still the identity for corner 1 / corner 2.   |
//| The two gestures are NOT the same question, though. While DRAWING    |
//| the user is sketching a range and any pull is noise; while ADJUSTING |
//| he has already chosen the edge and is asking for EXACTLY that wick.  |
//| So the magnet is now a property of the ADJUST gesture only:          |
//|  · it runs ONCE, on the release (the terminal's drag is over —       |
//|    writing into a live native drag would cancel it, P-BK-15);        |
//|  · it may move ONE price anchor — the side the gesture moved and     |
//|    only when it is the ONLY side that moved, so a whole-box move     |
//|    keeps its exact geometry;                                         |
//|  · it is side-aware (the top side may only take a High, the bottom   |
//|    side only a Low), so a snap can never cross the opposite edge;    |
//|  · candidate wicks are the moved anchor's own bar ±BK_MAGNET_BARS,   |
//|    inside `g_magnetSensitivityPips` × the SYMBOL's pip (gold, JPY,   |
//|    indices and crypto included — never a hard-coded point).          |
//| These are the retirement's own knobs, so the two settings that the   |
//| card had left inert (MAGNET / MAGNET SENS) are live again.           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| BKMAGNET2-OFF (2026-09-15, user decision — «مگنت نمیخواد باشه حذفش |
//| کن»): the ADJUST magnet is RETIRED — both functions below are        |
//| commented in place (the BKMAGNET-OFF pattern), so the release does   |
//| not snap and the box stays where the hand let it go, exactly like    |
//| MT4's own rectangle. `g_enableMagnet` / `g_magnetSensitivityPips`     |
//| have no reader again, so the card hides their rows (P-UI-47's shape).|
//| To restore: uncomment the two functions + the release call and       |
//| re-add the two card rows, then re-teach `[bkmagnet]`.                |
//+------------------------------------------------------------------+
// #define BK_MAGNET_BARS 1   // candidate window around the anchor's bar (taste)

// Nearest candle extreme to `price`, restricted to the side being moved.
// `topSide` = the anchor is the box's upper corner, so only Highs qualify.
// double BaseKnotMagnetPrice(const datetime t, const double price, const bool topSide)
// {
//    if(!g_enableMagnet) return price;
//    if(t <= 0 || price <= 0) return price;
//    double pip = BaseKnotPipSize();
//    double gate = (double)g_magnetSensitivityPips * pip;
//    if(gate <= 0) gate = pip;   // sensitivity 0 = exact touch only (retired rule)
//    int sh = iBarShift(_Symbol, 0, t, false);
//    if(sh < 0) return price;
//    double best = price, bestD = gate;
//    for(int k = -BK_MAGNET_BARS; k <= BK_MAGNET_BARS; k++)
//    {
//       int s = sh + k;
//       if(s < 0) continue;
//       double cand = 0.0;
//       if(topSide) cand = iHigh(_Symbol, 0, s);
//       else        cand = iLow(_Symbol, 0, s);
//       if(cand <= 0) continue;
//       double d = MathAbs(price - cand);
//       if(d <= bestD) { bestD = d; best = cand; }   // <= : a tie takes the LATER bar
//    }
//    return best;
// }

// ONE write per adjusted gesture, issued on the release, before the Sync that
// repaints the children. Compares the box's live anchors against the press-time
// snapshot the native-drag latch already took (s_bkDragBP1/BP2).
// void BaseKnotMagnetSettle(const string bid)
// {
//    if(!g_enableMagnet || bid == "") return;
//    // P-BK-25: the magnet's whole decision is "did ONE side move?" — a comparison
//    // against a snapshot of the press. A gesture we ADOPTED mid-drag has no such
//    // snapshot (its baseline was taken after the terminal had already moved the
//    // box), so the honest answer is to snap NOTHING: leave the box exactly where
//    // the hand let it go. A role that cannot be measured must not invent.
//    if(!s_bkSnapTrusted) return;
//    if(BaseKnotFind(bid) < 0) return;
//    string box = BaseKnotBoxName(BaseKnotPrefix(bid));
//    if(ObjectFind(0, box) < 0) return;
//    double pt = GetCachedPoint();
//    if(pt <= 0) pt = _Point;
//    double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
//    double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
//    bool moved1 = (MathAbs(p1 - s_bkDragBP1) > pt * 0.5);
//    bool moved2 = (MathAbs(p2 - s_bkDragBP2) > pt * 0.5);
//    if(moved1 == moved2) return;   // a whole-box move (or a tap) — never re-shape it
//    int idx = (moved1 ? 0 : 1);
//    datetime ta = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, idx);
//    double pa = (idx == 0 ? p1 : p2);
//    double other = (idx == 0 ? p2 : p1);
//    double snap = BaseKnotMagnetPrice(ta, pa, (pa > other));
//    if(MathAbs(snap - pa) <= pt * 0.5) return;   // already on the wick — zero writes
//    if(!ObjectMove(0, box, idx, ta, snap)) return;
//    Print("[BK] magnet box=", bid, " side=", (idx == 0 ? 1 : 2), " ",
//          DoubleToString(pa, _Digits), " -> ", DoubleToString(snap, _Digits),
//          " (", DoubleToString(BaseKnotToPips(MathAbs(snap - pa)), 1), " pips)");
// }

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
   // P-BK-74: the rubber band is ONE rectangle again (the family the commit
   // hands over), hollow and foreground, wearing the final look — what the user
   // sizes is literally what he gets.
   BaseKnotDrawPreviewRect(pv, t, p, t, p,
                           GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth,
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

   //--- P-UI-100 (2026-09-22): WHILE THIS LAYER OWNS A GESTURE, NO HAND-SET LINE
   //--- MAY STAY SELECTED.
   //---
   //--- Reported: «وقتی فیو یا باکس از همون محل میکشم کاستوم پرایس جابجا میشه».
   //--- MT4's drag does not move the object under the cursor, it moves EVERY
   //--- SELECTED object (P-UI-45/P-BK-26), so a hand-set line left selected by an
   //--- earlier gesture rides along with whatever this layer draws or drags — and
   //--- its price lands wherever the gesture ended, with the whole ladder derived
   //--- from it.
   //---
   //--- This handler is the FIRST thing every chart event reaches and it consumes
   //--- its own gestures whole (`return true` below), so the custom-price block —
   //--- whose claim AND whose selection drain live there — never sees the events
   //--- of a box draw at all. That is exactly why the guard is called HERE as well
   //--- as there: the layer that owns the gesture is the layer that must not let
   //--- another object's selection survive it.
   //---
   //--- Gated by this layer's OWN live gesture (the armed session, its preview, or
   //--- the terminal dragging a committed box), so a chart nobody is drawing on
   //--- pays one compare per event and nothing else; inside a live gesture it is
   //--- three name compares plus a guarded read per hand-set line.
   if((id == CHARTEVENT_MOUSE_MOVE || id == CHARTEVENT_OBJECT_DRAG) &&
      (g_bkState != BK_IDLE ||
       (id == CHARTEVENT_OBJECT_DRAG && tag != "" && StringFind(sparam, tag) == 0)))
   {
      HandLinesSelectionGuard();
      //--- P-UI-100c (2026-09-22): AND THE HAND-SET LINE GOES BACK ON ITS
      //--- ANCHOR. The guard removes the cause this project has measured (MT4
      //--- carries every SELECTED object with a drag); this is the invariant
      //--- itself, for the mechanism nobody has named yet: while THIS layer owns
      //--- the gesture, the custom price line must sit on the price the ladder
      //--- is built from. The report — «میخواستم باکس بکشم» and the line went
      //--- down with the cursor and stayed — is exactly this test failing, and a
      //--- write only happens when it really drifted (two guarded reads a call).
      HandLineHealToAnchor();
   }

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
         // Click-to-recall: a tap on a committed box re-opens its INFO grace,
         // so the badge comes back for BK_INFO_GRACE_MS — the "look again"
         // path, with the info exactly ON the box (never at the bottom).
         // One Sync per click (clicks are rare; drags already Sync on release).
         int kr = BaseKnotFind(bid);
         if(kr >= 0)
         {
            g_bkBoxes[kr].commitMs = GetTickCount();
            BaseKnotSync(bid);
            ChartRedraw();
         }
         return true;   // clicks on box/lines/info text die here — never reach menus
      }
   }

   //--- BKGRIP-OFF (P-BK-71): the HANDLE drag is retired with the chips — the box'
   //--- own body drag is the only native gesture now, and it arrives on the BOX branch
   //--- below. The tail mapping stays (that is how a ghost chip from an older build is
   //--- still NAMED), but nothing routes into the resize writer any more.
   if(id == CHARTEVENT_OBJECT_DRAG && tag != "" && StringFind(sparam, tag) == 0)
   {
      string gtail = StringSubstr(sparam, StringLen(tag));
      string gid = "", gkind = "";
      BaseKnotSplitTail(gtail, gid, gkind);
      int gside = BaseKnotGripSide(gkind);
      if(gside != 0)
      {
         // BKGRIP-OFF: BaseKnotGripDrag(gid, gside, sparam);
         // BKGRIP-OFF: return true;
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
           // P-BK-19a: the terminal just NAMED the object it is dragging, so the
           // gesture is ITS — the cursor fallback stays off for the rest of it.
           s_bkNativeClaim = true;
           // P-BK-65: AND IT JUST SAID WHICH OBJECT: the BOX, not a chip. That is the
           // ground truth behind two answers this press needs — "the body-size heal may
           // run" (`s_bkBoxNamed`) and "this press is NOT a resize" (a chip gesture
           // latched earlier belongs to a gesture that is already over: the terminal
           // cannot drag a chip and the box at once). Two stores on the gesture's own
           // events; nothing here runs per tick.
           s_bkBoxNamed    = true;
           s_bkGripGesture = 0;
           // Unified lean follow (P-BK-07): anchor-exact moves only — never a
           // full Sync per step (its style/tooltip rewrites lagged children
           // behind the native BOX on heavy charts). This event carries no
           // trusted cursor (in-repo pattern: TH3Tool reads live anchors here
           // too), so it is anchor-exact only — the cursor fallback that used to
           // ride the MOUSE_MOVE channel is RETIRED (BKCURSOR-OFF). Release still
           // does the authoritative Sync.
           if(bid != s_bkDragId)
           {
              // Overlap hole: the press latched another box — adopt the
              // actually-dragged one (cursor base stays: same press point).
              string abox = BaseKnotBoxName(BaseKnotPrefix(bid));
              if(ObjectFind(0, abox) >= 0)
              {
                 s_bkDragId = bid; s_bkDragMoved = true;
                 Print("[BK] drag adopt box=", bid, " (the press missed it)");   // diag: terminal drags a box the press missed
                 s_bkSnapTrusted = false;   // P-BK-25: this baseline is taken MID-DRAG
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
            { s_bkDiagUnk = bid; s_bkDiagUnkMs = unow; Print("[BK] drag: box not in registry ", bid); }
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
    //--- moves the BOX natively and children follow through BaseKnotFollowDrag —
    //--- anchor-exact and unbudgeted (the ONE, LIVE writer; the cursor-delta
    //--- fallback is retired, BKCURSOR-OFF). One paint budget, then one
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
          s_bkDragActMs = GetTickCount();
          // P-BK-65: A RISING EDGE WHILE A CHIP IS HELD IS A FLICKER, NOT A PRESS.
          // The terminal's own OBJECT_DRAG of a chip is the ground truth that this
          // press is a RESIZE, and re-labelling it here is what made a resize snap
          // back (see the P-BK-65 block above the statics): the release then read it
          // as a body drag and the size heal put the old size back, and the keeper
          // rewrote the chip under the hand. While that latch is live the press edge
          // leaves the GESTURE's identity alone — it may only touch the fields a new
          // gesture needs. A REAL press always finds the latch at 0 (the release or
          // the silence watchdog cleared it), so a fresh gesture still starts fresh.
          const bool bkGripHeld = (s_bkGripGesture != 0);
          if(!bkGripHeld)
          {
             s_bkDragId = ""; s_bkDragMoved = false;
             s_bkSnapTrusted = false;   // P-BK-25: a fresh press has no trusted baseline yet
             // P-BK-19: a fresh press is a fresh gesture — nobody owns it yet, and
             // the window in which the terminal is asked first starts NOW.
             s_bkNativeClaim = false; s_bkOwnerMs = GetTickCount(); s_bkFallLogged = false;
             s_bkBoxNamed = false;   // P-BK-65: no terminal-named box drag in this press yet
             // P-PERF-42/41: the child mask is re-probed for THIS gesture (the same
             // box dragged twice probes twice) and the timing counters restart.
             s_bkChildMaskId = ""; s_bkPerfMoveWorst = 0; s_bkPerfPaintWorst = 0; s_bkPerfPasses = 0;
             s_bkGripLive = 0; s_bkGripLogged = false; s_bkMagnetLogged = false;   // P-BK-61: a fresh press is a fresh gesture
          }
          int ssw = 0; datetime sct = 0; double scp = 0;
         // P-UI-92: a press that lands ON a visible UI surface is the UI's pixel — the
         // card/strip/menu sits OVER the box, so the user is reading or setting a
         // control, not grabbing what is behind it. Without this test the latch armed
         // on the hidden box and the next move dragged it (click bleed-through: the
         // panel's own press is classified in the UI half of the same event, which
         // runs AFTER this one). The press is never consumed by the box tool — the
         // rejection is deliberately NOT a claim on the gesture.
         // P-BK-65: while a chip is held this press edge owns NOTHING — the live
         // resize already latched its box and took its baseline before the terminal
         // moved anything, and a mid-drag snapshot here would be the P-BK-25 trap.
         if(!bkGripHeld &&
            !UIPointerOverSurface((int)lparam, (int)dparam) &&
            ChartXYToTimePrice(0, (int)lparam, (int)dparam, ssw, sct, scp) && ssw == 0 && sct > 0 && scp > 0)
         {
            string shit = BaseKnotBoxAt(sct, scp);   // exact INSIDE test first — it never lies
            if(shit == "") shit = BaseKnotBoxAtPx((int)lparam, (int)dparam);   // P-BK-24: the drawn BORDER is a target too
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
                     // P-BK-72: the press-time grab role is LIVE — its consumer is NOT the
                     // retired cursor fallback (BKCURSOR-OFF stays dead) but the release's
                     // size heal below: a press on a corner/edge marker is a native RESIZE
                     // (the docs' own rule — anchors change the size), and the heal must
                     // only ever fire for a BODY move. BaseKnotGrabRole stays the measurer.
                     s_bkGrabSel = BaseKnotGrabRole(shbox, s_bkDragX0, s_bkDragY0);
                    s_bkSnapTrusted = true;   // P-BK-25: OUR press latched it — the baseline predates any terminal move
                    Print("[BK] drag latch box=", shit);   // diag: press found a box — follow armed
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
          // P-BK-61: a HANDLE resize ends here too, and it owes the same authoritative
          // Sync even when the hand barely moved (a 3px correction is a resize, not a
          // tap) — so the gesture's own flag joins the condition. P-BK-65: that flag
          // is the KIND (`s_bkGripGesture`, latched from the terminal's own
          // OBJECT_DRAG of a chip), never the keeper's `s_bkGripLive` — a mouse-channel
          // flicker cleared the skip and the release then re-sized the box back. The
          // flag is READ and CLEARED first, so the Sync below may glue every chip, the
          // one the hand just let go of included (never written while the terminal
          // still held it).
          // P-BK-65: THE KIND OF GESTURE DECIDES THIS PATH, NEVER THE SKIP FIELD.
          // `s_bkGripLive` says which chip the hand holds (the keeper's skip, cleared
          // by a press edge); `s_bkGripGesture` says this press WAS a resize, and only
          // a real end can clear it. Reading the skip here is the bug the user
          // reported: one flicker made the release call a resize a body drag.
          int bkGripWas = s_bkGripGesture;
          s_bkGripLive = 0; s_bkGripLogged = false; s_bkMagnetLogged = false;
          s_bkGripGesture = 0; s_bkBoxNamed = false;   // this gesture is over
          if(s_bkDragId != "" && (s_bkDragMoved || bkGripWas != 0))
          {
              // P-PERF-43: the same line carries WHAT the gesture cost, split by
              // phase — the ledger that answers the next "the drag lags" with a
              // number (children/box writes vs the throttled repaint) instead of a
              // guess. One line per gesture, never per step.
              Print("[BK] drag release sync box=", s_bkDragId, " native=", (s_bkNativeClaim ? 1 : 0),
                    " follow=", s_bkPerfPasses, " move=", (int)s_bkPerfMoveWorst, "ms paint=",
                    (int)s_bkPerfPaintWorst, "ms resize=", bkGripWas);   // diag: authoritative final
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
                 // BKMAGNET2-OFF (2026-09-15, user decision): the ADJUST magnet
                 // is retired — the release does not snap (the engine above is
                 // commented). The box stays where the hand let it go.
                 // BaseKnotMagnetSettle(s_bkDragId);
                  // P-BK-61b/P-BK-72: a BODY drag carries the box and nothing else — the size
                  // the hand took it with comes back before the authoritative Sync (a
                  // HANDLE drag, bkGripWas, IS the size gesture and is left alone — and so
                  // is a NATIVE corner/edge resize: the press-time role says it was never
                  // a body move, so the heal would spring the user's own resize back).
                  if(bkGripWas == 0 && s_bkGrabSel == BK_GRAB_ALL) BaseKnotBodySizeHeal(s_bkDragId);
                 BaseKnotRefreshDirection(s_bkDragId, relRef);
                BaseKnotSync(s_bkDragId);
                painted = true;
             }
            if(painted) ChartRedraw();
            // P-BK-61: a RESIZE hands the selection back to the box (the terminal gave
            // it to the chip), so the corner handles stay on screen and the next side is
            // one grab away — no second click.
            if(bkGripWas != 0) BaseKnotGripReselect(s_bkDragId);
          }
           // BKSELECT-KEPT (2026-09-15, user decision — «مثل خود متاتریدر»):
           // the box STAYS selected after a drag, like MT4's own rectangle, so
           // a second resize needs no re-click (P-BK-26's drop forced a
           // select-then-drag double step for every edge). The hijack P-BK-26
           // feared is gone with the retired cursor fallback (BKCURSOR-OFF):
           // nothing of ours writes the box except this gesture's own follow,
           // and the terminal single-selects on press like for its own objects.
           // Deselect as always via empty-chart click / Esc / another object.
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

   //--- P-BK-63: a CLICK (id 4 = a click on the CHART; a click on a SELECTABLE
   //--- object arrives as OBJECT_CLICK, id 1, and the branches above own it)
   //--- that lands OUTSIDE every box lets the box' selection go — the mirror of
   //--- `BaseKnotGripReselect`, so the handles that a click shows disappear on
   //--- the click that dismisses them. Right-clicks are left alone (the context
   //--- menu is a different gesture), and the event is NOT consumed: the menu
   //--- and panel halves read it exactly as they did before.
   if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") < 0 &&
      BaseKnotDeselectOnChartClick((int)lparam, (int)dparam))
   {
      ChartRedraw();
      return false;
   }

   if(!BaseKnotSessionActive()) return false;

    //--- right-click cancels (both encodings MT4 uses).
    if(id == CHARTEVENT_MOUSE_MOVE)
    {
       int st = (int)StringToInteger(sparam);
       if((st & 2) != 0) { BaseKnotCancel(); return true; }
    }
    if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") >= 0)
       { BaseKnotCancel(); return true; }

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
         // P-UI-92: a press on a UI surface belongs to the UI, not to the draw session.
         // Corner 1 must not be placed at the chart price hidden under the card (a
         // press/release pair on the panel used to place BOTH corners of a box the
         // user never saw). The event is still swallowed so the session keeps owning
         // the mouse; the UI half of this same event runs right after the domain half.
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
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
         // P-UI-92: the release that lands on a UI surface is not a chart release —
         // committing here would put corner 2 under the panel from a press the panel
         // already consumed. The session stays alive so sizing continues from the last
         // chart point the cursor actually visited.
         if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
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
            // P-BK-74: ONE rectangle, moved — no delete/recreate per frame, so a
            // hover costs two ObjectMove calls and one paint, not a create storm.
            BaseKnotDrawPreviewRect(pv, g_bkT1, g_bkP1, ht, hp,
                                    GetBoxBorderRenderColor(), inpBoxBorderStyle, inpBoxBorderWidth,
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
      // P-UI-92: the tap/commit path is the one that actually leaked — CLICK carries
      // the price under the cursor (`dparam`), so a click on a panel committed a box
      // corner AT THE PRICE HIDDEN BEHIND IT. A click on a UI surface is the UI's:
      // swallowed here, acted on by the UI half of the same event.
      if(UIPointerOverSurface((int)lparam, (int)dparam)) return true;
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

#endif // BASE_KNOT_DRAG_MQH
