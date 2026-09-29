// BiotakPanels_Hit.mqh - BiotakPanels split 2026-09-29: exact lines 7364-8741 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_HIT_MQH
#define BIOTAK_PANELS_HIT_MQH

void PnlCloseAll()
{   BkFlushTextEdit();   // close = apply (TV Ok semantics)
   g_BkTextFocus = false;
   bool wasOpen = (g_PnlOpen >= 0);
   // P-PERF-47: ONE FAMILY WIPE INSTEAD OF FOURTEEN PER-ITEM TEARDOWNS.
   //
   // The loop this replaces called PnlDestroy(i) for ALL PNL_COUNT (14) items
   // whether or not that item had ever been built — and at most ONE panel is
   // ever on screen, because PnlOpen() calls PnlCloseAll() before it creates
   // (BiotakPanels.mqh:6441). So thirteen of the fourteen teardowns were work on
   // an empty family, and each one still paid a full-chart prefix scan plus its
   // own probes. The measured bill, on the live MT5 terminal:
   //
   //   [W][PERF] OnDeinit breakdown: pnl=437ms ...        (every timeframe switch)
   //   [W][PERF] OnDeinit reason=3 took 734ms (budget 150ms)
   //
   // against an MT4 teardown that never once exceeded the 150 ms budget in a
   // whole trading day (the AMarkets MT4 log for 2026-09-16 carries zero
   // OnDeinit budget warnings and completes a full Full-build timeframe switch
   // in 42 ms). The gap is not the platform being slow at the WORK — the MT5
   // probe prices a WRITE at 0.245 us — it is the platform charging for every
   // QUESTION, and this loop asked hundreds of them.
   //
   // WHY A PREFIX WIPE IS THE CORRECT FIX, NOT A LEDGER OF "WHICH PANELS EXIST":
   // a ledger can only ever be as right as every writer of it, and a panel that
   // is on the chart while its flag says "not built" leaks silently — which is
   // the exact ghost class the per-item list was written to fight (see P-UI-71).
   // A prefix wipe cannot leak: it removes by NAME, so it is complete by
   // construction and needs no bookkeeping to stay honest.
   //
   // The prefix is exact, not approximate. PnlName()/PnlHead() (:2472/:2476)
   // spell EVERY object of this family as
   // `g_UI.btnPrefix + "Pnl" + item + "_" + ...`, and `g_UI.btnPrefix` is
   // `"BiotakMenuV2_" + ChartID() + "_"` (BiotakMenu.mqh:680). So
   // `btnPrefix + "Pnl"` matches the whole panel family and nothing else — the
   // palette is `btnPrefix + "Pal_"`, the ring/menu are `btnPrefix` itself, and
   // the chart's own objects share none of it.
   //
   // Cost: ONE scan, one time, instead of 28 scans and ~560 absent-name probes.
   ObjectsDeleteAll(0, g_UI.btnPrefix + "Pnl", -1, -1);
   // The two popovers still go through their own closers because they reset
   // STATE as well as objects (g_PnlDdItem / g_BkDd), and both are guarded by
   // "is it open?" so a closed popover costs one compare.
   PnlDdClose();
   BkDdClose();
   // The pre-fix switch faces ("SW","SW0".."SW3") are PREFIXLESS globals that no
   // panel prefix can reach. Purged once per close, not once per panel.
   ObjectDelete(0, "SW");
   for(int swp = 0; swp < 4; swp++) ObjectDelete(0, "SW" + IntegerToString(swp));
   PalClose();
   g_PnlOpen=-1;
   g_UIPanelOpen = false;   // the menu hover tip may arm again
   // P-UI-98r: cover invalidated - give back what the cull took, now.
   PnlPublishCover();
   HTFCardCullRefresh();
   if(wasOpen)
   {
      CircUnlockChart();   // release the modal chart lock
      PnlUnlockForeground();
   }
   // P-UI-128: the ONE owner for "a discrete action paints now" — a bare
   // ChartRedraw() here was a second copy of it.
   RepaintForDiscreteAction();
}

void PnlOpen(const int item)
{
   if(item < 0 || item >= PNL_COUNT) return;
   // Card 12 opened from the ring (not from the strip's •••, and not a TAB
   // rebuild of the already-open card) has no held box: drop a stale
   // g_BkMiniBox so the TEXT field can't edit the wrong box.
   if(item==12 && g_PnlOpen!=13 && g_PnlOpen!=12) g_BkMiniBox="";
   PnlCloseAll();
   g_PnlOpen=item;
   g_UIPanelOpen = true;   // menu hover tip stays disarmed while the card covers the menu
   CircTipDisarm();        // a visible/armed tip never survives above the opening card
   CircAbortRingGesture(); // P-UI-73: a ring long-press latch armed BEFORE this
                           // card opened is taken back here — otherwise it sits
                           // in front of the modal guard and swallows the next
                           // press (the card reads as un-draggable)
   PnlCreate(item);
   CircLockChart();   // modal: freeze chart pan/context menu while settings are open
   PnlLockForeground(); // ensure panel is ABOVE candles (not under)
   // P-UI-98r: the card is placed - mask the HTF boxes under it at once
   // (chart rectangles paint over screen skins at any rung).
   PnlPublishCover();
   HTFCardCullRefresh();
   RepaintForDiscreteAction();   // P-UI-128: the card swap must be on screen when
                                 // the event that asked for it ends
}

//--- rebuild the open card WITHOUT moving it: a height change (collapse,
//--- tab/mode reshape) must not re-anchor the panel around the menu.
//--- The manual flag is only borrowed for the create call.
void PnlRebuildKeepSpot(const int item)
{
   if(item < 0 || item >= PNL_COUNT) return;
   int sx=g_PnlX[item], sy=g_PnlY[item];
   bool wm=g_PnlManualPos[item];
   g_PnlManualPos[item]=true; g_PnlX[item]=sx; g_PnlY[item]=sy;
   PnlOpen(item);
   g_PnlManualPos[item]=wm;
}

//+------------------------------------------------------------------+
//| Point inside the open panel card (incl. shadow fringe)?           |
//+------------------------------------------------------------------+
bool PnlPointInside(const int mx,const int my)
{
   if(g_PnlOpen < 0) return false;
   int ph = PnlPanelH(g_PnlOpen);   // R-BKSTRIP: item 13 is the short TV strip
   int pw = PnlPanelW(g_PnlOpen);   // TV-parity: the strip is 380px, not PNL_WEL
   if(mx >= g_PnlX[g_PnlOpen]-PNL_MARGIN && mx <= g_PnlX[g_PnlOpen]+pw+PNL_MARGIN &&
      my >= g_PnlY[g_PnlOpen]-PNL_MARGIN && my <= g_PnlY[g_PnlOpen]+ph+PNL_MARGIN)
      return true;
   // the palette popup hangs next to the panel — clicks on it must not dismiss
   if(g_PalOpen && mx >= g_PalX && mx <= g_PalX+PalW() &&
      my >= g_PalY && my <= g_PalY+PalH())
      return true;
   return false;
}

//+------------------------------------------------------------------+
// P-UI-92 (2026-09-16) — THE UI'S PIXEL SOVEREIGNTY TEST (the WHERE half).
// THE BUG: the composer runs the DOMAIN half of an event first, so the domain read a
// pixel that sat ON A PANEL as chart input — the armed Base/Knot tool committed a
// corner behind the card, the committed-box drag latch armed from the same press, and
// the Custom Price pick consumed the release as its starting price. One defect: the
// UI's pixels were not subtracted from the chart before the domain hit-tested them.
// THE RULE: the UI layer answers ONE question from the layout it already maintains —
// "does this pixel belong to a VISIBLE UI surface?" — and the domain asks it before
// reading a pixel; the WHOSE half is the published click claim (`UIPeekClickClaim`).
// WHY A HIT TEST AND NOT A TIME WINDOW: the rect is layout state, valid at the instant
// of the press, so a hover that stopped 10 s ago cannot leak and a press that emits no
// move at all (P-BK-03) is still classified. No TTL, no drift, no timer.
// WHAT IS CLAIMED: the ring's controls only while `g_UI.menuVisible` (P-BK-02 hides the
// menu for a draw session) and exactly what `CircPointOnMenu` answers, plus the
// countdown tag — the menu's TRANSPARENT gaps stay nobody's, because a click that hits
// no control IS a chart click. P-UI-116: the ring half was WRITTEN here and never
// COMPILED here, so every ring pixel read as free chart until the call was added.
// COST: a handful of int compares on a press/release, never on a hover.
//+------------------------------------------------------------------+
bool UIPointerOverSurface(const int mx,const int my)
{
   if(PnlPointInside(mx,my)) return true;            // open card + the palette popover
   if(BkMiniStripPointInside(mx,my)) return true;    // floating strip + its STYLE/WIDTH popover
   if(g_UI.menuVisible)
   {
      int bx = 0, by = 0, bw = 0, bh = 0;
      PnlComputeMenuBounds(bx,by,bw,bh);
      if(mx >= bx && mx <= bx + bw && my >= by && my <= by + bh) return true;
      if(CircPointOnMenu(mx,my)) return true;        // P-UI-116: the ring's own controls
   }
   if(LiveCountdownPointInside(mx,my)) return true;  // the countdown tag (a UI-layer object)
   return false;
}

//+------------------------------------------------------------------+
//| Generic dropdown-select engine (TV popover language)              |
//| One open at a time; content-fitted width; dark-pill selection.    |
//| Selecting applies through PnlApplyOption — the same path as a     |
//| segment tap (full card rebuild, reshape-safe like TAB switches).  |
//+------------------------------------------------------------------+
void PnlDdOpen(const int item,const int row)
{
   PnlDdClose();
   PalClose();   // P-UI-26/F8: mutual exclusion both ways — a card dropdown
                 // must never open underneath the palette (Z1560 < Z1600).
   int kind; string label,unit,opts; int minV,maxV; double step;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   string arr[]; int cnt=PnlSplit(opts,arr,12);
   if(cnt<=0) return;
   int maxLen=0;
   for(int i=0;i<cnt;i++) maxLen=MathMax(maxLen,StringLen(arr[i]));
   int bw=MathMax(120,MathMin(264,maxLen*7+40));
   int ax,ay,aw,ah; PnlDdRect(item,row,ax,ay,aw,ah);
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0); if(cw<=0) cw=1920;
   int ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0); if(ch<=0) ch=1080;
   int ph=cnt*PNL_DD_ROW_H+2*PNL_DD_PAD;
   int bx=ax+aw-bw;                        // right-align under the button
   bx=MathMax(4,MathMin(cw-bw-4,bx));
   int by=ay+ah+6;
   if(by+ph>ch-8) by=ay-6-ph;              // flip above without room
   if(by<4) by=4;
   g_PnlDdItem=item; g_PnlDdRow=row;
   g_PnlDdX=bx; g_PnlDdY=by; g_PnlDdW=bw; g_PnlDdH=ph; g_PnlDdN=cnt;
   string hh=PnlHead(item,"");
   PnlSetRect(hh+"PDDSH",bx+3,by+4,bw,ph,PNL_CLR_SHADOW);
   ObjectSetInteger(0,hh+"PDDSH",OBJPROP_ZORDER,PNL_DD_Z_SH);
   PnlSetRect(hh+"PDDBG",bx,by,bw,ph,PNL_CLR_FIELD);
   ObjectSetInteger(0,hh+"PDDBG",OBJPROP_BORDER_COLOR,PNL_CLR_SEG_BD);
   ObjectSetInteger(0,hh+"PDDBG",OBJPROP_ZORDER,PNL_DD_Z_BG);
   int cur=ClampInt((int)MathRound(PnlCurrent(item,row)),0,cnt-1);
   for(int r=0;r<cnt;r++)
   {
      int ryy=by+PNL_DD_PAD+r*PNL_DD_ROW_H;
      if(r==cur)
      {
         PnlSetRect(hh+"PDDR"+IntegerToString(r)+"s",bx+6,ryy+1,bw-12,PNL_DD_ROW_H-2,PNL_CLR_ACCENT);
         ObjectSetInteger(0,hh+"PDDR"+IntegerToString(r)+"s",OBJPROP_ZORDER,PNL_DD_Z_SEL);
      }
      PnlSetLabel(hh+"PDDR"+IntegerToString(r)+"l",bx+16,ryy+7,arr[r],
                  (r==cur)?C'255,255,255':PNL_CLR_LABEL,8);
      ObjectSetInteger(0,hh+"PDDR"+IntegerToString(r)+"l",OBJPROP_ZORDER,PNL_DD_Z_LBL);
   }
   ChartRedraw();
}
// -1 = outside (closed, press falls through); else refresh flags (consumed).
int PnlDdHit(const int mx,const int my)
{
   if(g_PnlDdItem<0) return -1;
   if(mx<g_PnlDdX || mx>g_PnlDdX+g_PnlDdW || my<g_PnlDdY || my>g_PnlDdY+g_PnlDdH)
   { PnlDdClose(); return -1; }
   int idx=ClampInt((my-(g_PnlDdY+PNL_DD_PAD))/PNL_DD_ROW_H,0,MathMax(0,g_PnlDdN-1));
   int item=g_PnlDdItem, row=g_PnlDdRow;
   return PnlApplyOption(item,row,idx);
}
bool PnlDdAnchorHit(const int mx,const int my,int &item,int &row)
{
   item=-1; row=-1;
   if(g_PnlOpen<0 || g_PnlOpen==13) return false;
   int rowsCount=PnlRowsCount(g_PnlOpen);
   for(int r=0;r<rowsCount;r++)
   {
      if(!IsDdRow(g_PnlOpen,r)) continue;
      int x,y,w,h; PnlDdRect(g_PnlOpen,r,x,y,w,h);
      if(mx>=x && mx<=x+w && my>=y && my<=y+h) { item=g_PnlOpen; row=r; return true; }
   }
   return false;
}
// Shared option-apply: segment taps and dropdown picks behave identically.
int PnlApplyOption(const int item,const int row,const int idx)
{
   int flags=PnlApply(item,row,(double)idx);
   PnlDdClose();      // popover gone before the rebuild (destroy also covers)
   PnlOpen(item);     // full rebuild — reshape-safe like TAB switches
   return flags;
}

//+------------------------------------------------------------------+
//| BASE BOX MINI strip press (item 13) — TV-parity 2026-09-07        |
//| The strip buttons are OBJ_BITMAP_LABEL glyphs (MT4 fires no        |
//| OBJECT_CLICK for them), so presses are hit by coordinates in       |
//| PnlHandleMouseMove — the same pattern as slider knobs / switches.  |
//| pencil → border palette · bucket → fill palette (kind 17 needs a   |
//| card-12 row: PalOpen(12,5) with Style tab forced) · T → card 12 on |
//| the Text tab · STYLE/WIDTH toggle their ▾ dropdowns (TV popovers,  |
//| NOT cycles) · LOCK/trash act on the held box · ••• → full card 12.|
//| An open dropdown eats the press first (row = apply live, padding = |
//| close). Same mirrors as card 12 — never duplicated.                |
//+------------------------------------------------------------------+
int BkMiniStripPress(const int mx, const int my)
{
   if(g_PnlOpen != 13) return REFRESH_NONE;
   if(g_BkTextFocus) BkFlushTextEdit();   // stale focus can never survive here
   //--- open dropdown first (TV: the popover owns the next press)
   if(g_BkDd != 0)
   {
      int dh = BkDdHit(mx, my);
      if(dh >= 0) { UISuppressNextClick(); return dh; }
      BkDdClose();   // pressed its anchor's sibling — fall through to the strip
   }
   for(int i = 0; i < BK_TB_N; i++)
   {
      int x, y, w, h;
      BkMiniSlot(i, x, y, w, h);
      if(mx < x || mx > x + w || my < y || my > y + h) continue;
      if(i == 0)   // pencil → BORDER palette (color + transparency)
      {
         BkDdClose();   // a slot press replaces any open ▾ popover
         PalOpen(13, 0);
         UISuppressNextClick();
         return REFRESH_NONE;
      }
      if(i == 1)   // bucket → FILL palette (Style tab row 5 owns PAL_BOX_FILL)
      {
         BkDdClose();
         g_BkTab = 0;
         PalOpen(12, 5);
         UISuppressNextClick();
         return REFRESH_NONE;
      }
      if(i == 2)   // T → full card 12 on the Text tab (TV Text tab)
      {
         g_BkTab = 1;
         PnlOpen(12);
         return REFRESH_NONE;
      }
      if(i == 3)   // STYLE ▾ dropdown (TV popover — Line / Dashed / Dotted…)
      {
         if(g_BkDd == BK_DD_STY) BkDdClose();
         else BkDdOpen(BK_DD_STY);
         UISuppressNextClick();
         return REFRESH_NONE;
      }
      if(i == 4)   // WIDTH ▾ dropdown (TV popover — 1px…5px)
      {
         if(g_BkDd == BK_DD_WID) BkDdClose();
         else BkDdOpen(BK_DD_WID);
         UISuppressNextClick();
         return REFRESH_NONE;
      }
      // LOCK / trash act on the held box — a gone box means the strip is pointless
      if(g_BkMiniBox == "" || BaseKnotFind(g_BkMiniBox) < 0)
      {
         PnlCloseAll();
         return REFRESH_NONE;
      }
      if(i == 5)   // LOCK toggle (held box)
      {
         BkDdClose();
         BaseKnotSetLocked(g_BkMiniBox, !BaseKnotLocked(g_BkMiniBox));
         BkMiniRefresh();
         UISuppressNextClick();
         return REFRESH_NONE;
      }
      if(i == 6)   // trash: delete the HELD box (children cascade by prefix)
      {
         BaseKnotDelete(g_BkMiniBox);
         g_BkMiniBox = "";
         PnlCloseAll();
         return REFRESH_NONE;
      }
      // i == 7 ••• → full Base Box card 12 (keeps the current tab)
      PnlOpen(12);
      return REFRESH_NONE;
   }
   return REFRESH_NONE;
}

// Move the strip by (dx,dy) WITHOUT a full-chart scan: every strip object is
// moved by its explicit head-name (slots via BkMiniSlotName = single source —
// a new slot is picked up automatically; the fixed tail covers bars/labels).
// PnlMoveBy's ObjectsTotal loop is for generic row-cards; at drag-event rate
// the strip must cost ~15 syscalls, not thousands (explicit names, never a scan).
void BkStripMoveBy(const int dx, const int dy)
{
   if(dx == 0 && dy == 0) return;
   int ndx, ndy;
   PnlClampSpot(13, dx, dy, ndx, ndy);   // clamp FIRST — logic/graphics never diverge
   if(ndx == 0 && ndy == 0) return;
   for(int i = 0; i < BK_TB_N; i++) BkStripMoveOne(BkMiniBtn(BkMiniSlotName(i)), ndx, ndy);
   BkStripMoveOne(BkMiniBtn("card"), ndx, ndy);
   BkStripMoveOne(BkMiniBtn("TBbar0"), ndx, ndy);
   BkStripMoveOne(BkMiniBtn("TBbar1"), ndx, ndy);
   BkStripMoveOne(BkMiniBtn("TBbar2"), ndx, ndy);
   BkStripMoveOne(BkMiniBtn("TBwlabel"), ndx, ndy);
   BkStripMoveOne(BkMiniBtn("TBchev1"), ndx, ndy);
   BkStripMoveOne(BkMiniBtn("TBchev2"), ndx, ndy);
   // NOTE: no DD* popover objects — the follow always BkDdClose()es first,
   // so moving them would only resurrect stale hit rects.
   g_PnlX[13] += ndx;
   g_PnlY[13] += ndy;
}
void BkStripMoveOne(const string nm, const int dx, const int dy)
{
   if(ObjectFind(0, nm) < 0) return;
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, ObjectGetInteger(0, nm, OBJPROP_XDISTANCE) + dx);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, ObjectGetInteger(0, nm, OBJPROP_YDISTANCE) + dy);
}

// TV-like: the floating toolbar rides its box — when the held box is dragged
// the strip re-anchors next to the new corner (same formula as BkHoldFire).
// Change-guarded to a 4px dead band. TWO channels: (1) the drag EVENT itself
// (HandleUIChartEvent OBJECT_DRAG — BK consumes box drags for the domain, but
// the entry still forwards every event here, so the strip moves in the SAME
// frame as the children, throttled 30ms); (2) the per-tick heal below as
// fallback (wheel-zoom/TF-switch move corners with no drag event).
void BkStripFollow()
{
   string pfx = BaseKnotPrefix(g_BkMiniBox);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double tp = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                       ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
   int x2 = 0, y2 = 0;
   if(!ChartTimePriceToXY(0, 0, t2, tp, x2, y2)) return;   // corner off-screen
   // P-PERF-16: strip-follow runs at drag rate (30 ms throttle + 4 px dead band).
   int cw = 0, ch = 0;
   CircUIMetrics(cw, ch);
   int nx = x2 + 14;
   int ny = y2 - PNL_TB_H - 14;
   if(ny < 4) ny = y2 + 14;
   if(nx < 4) nx = 4; if(nx > cw - PNL_TB_W - 4) nx = cw - PNL_TB_W - 4;
   if(ny < 4) ny = 4; if(ny > ch - PNL_TB_H - PNL_BOTTOM_SAFE) ny = ch - PNL_TB_H - PNL_BOTTOM_SAFE;
   if(nx < 4) nx = 4; if(ny < 4) ny = 4;
   // P-UI-26/F3: pinned at the right edge while the box keeps moving right,
   // the gap only grows — flip to the corner's LEFT when it has room.
   if(nx != x2 + 14 && x2 - 14 - PNL_TB_W >= 4) nx = x2 - 14 - PNL_TB_W;
   int dx = nx - g_PnlX[13], dy = ny - g_PnlY[13];
   if(MathAbs(dx) < 4 && MathAbs(dy) < 4) return;
   BkDdClose();   // a riding strip never keeps a stale popover (hit rects would lie)
   if(g_PalOpen) PalClose();   // nor an orphaned palette (it hangs off stale pixels)
   BkStripMoveBy(dx, dy);   // explicit TB* list — no full-chart scan at drag rate
   BaseKnotDragPaint();   // shared drag-paint budget (one repaint per drag frame max)
}

// Per-tick heal (RefreshKitOnBar): if the held box vanished while its strip
// is open — keyboard Delete on a native selection, another box stealing the
// hold, template load — close the strip, nothing left to edit. Change-
// guarded by the open-item check, so steady state costs one int compare.
void BkMiniStripHeal()
{
   if(g_PnlOpen != 13) return;
   if(g_BkMiniBox == "" || BaseKnotFind(g_BkMiniBox) < 0) { PnlCloseAll(); return; }
   // A box hidden by its TF mask (switched above its commit TF) owns no
   // toolbar — TV hides the toolbar with the object. Re-hold to reopen.
   if(!BaseKnotVisibleNow(g_BkMiniBox)) { PnlCloseAll(); return; }
   BkStripFollow();
}

//+------------------------------------------------------------------+
//| Drag-to-move engine — grab the panel header and the whole panel  |
//| follows the cursor anywhere on the chart. The final spot is      |
//| remembered (g_PnlManualPos + GV) so the panel reopens exactly    |
//| where it was left instead of snapping back next to the menu.     |
//+------------------------------------------------------------------+
int  g_PnlMoveItem  = -1;   // panel being dragged by its header (-1 = none)
int  g_PnlMoveLastX = 0;
int  g_PnlMoveLastY = 0;

//+------------------------------------------------------------------+
//| Hit test on the header strip — the drag-to-move grab zone.       |
//| Excludes the close/palette buttons so their clicks keep working. |
//+------------------------------------------------------------------+
bool PnlHeaderHit(const int mx, const int my)
{
   if(g_PnlOpen < 0) return false;
   if(g_PnlOpen == 13) return false;   // TV strip: re-anchors to its box on
                                       // every open — no manual-park drag
   int px = g_PnlX[g_PnlOpen], py = g_PnlY[g_PnlOpen];
   int pw = PnlPanelW(g_PnlOpen);
   if(mx < px - PNL_MARGIN || mx > px + pw + PNL_MARGIN) return false;
   if(my < py - PNL_MARGIN || my > py + PNL_HEAD_H + PNL_MARGIN) return false;
    // close exclusion in xbx terms (not magic offsets): the xbg skin runs
    // xbx-PAD .. xbx+26+PAD and py+15-PAD .. py+41+PAD — anything inside must
    // never start a drag (P-UI-21's py+39 sliver, P-UI-24's eaten click).
    int xbx = px + pw - PNL_PAD_X - PNL_XBTN_VIS;
    if(mx >= xbx - PNL_XBTN_PAD - 6 && mx <= xbx + PNL_XBTN_VIS + PNL_XBTN_PAD &&
       my >= py + 3 && my <= py + 43)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Shift every object of one panel by (dx,dy) px — live drag.       |
//| The palette popup hangs off this panel, so it rides along too.   |
//+------------------------------------------------------------------+
// Clamp one panel's logical spot on-screen; returns the applied delta.
// Same bounds as PnlComputePosition.
void PnlClampSpot(const int item, const int dx, const int dy, int &ndx, int &ndy)
{
   // P-PERF-16: the drag path asks for the chart rect on every move event; the
   // shared cached reader (BiotakMenu) owns it, and both invalidation points
   // (CHART_CHANGE + the 250 ms timer) already exist.
   int cw = 0, ch = 0;
   CircUIMetrics(cw, ch);
   int ph = PnlPanelH(item);   // R-BKSTRIP: item 13 is the short TV strip
   int pw = PnlPanelW(item);
   int maxX = cw - pw - 8;
   int maxY = ch - ph - PNL_BOTTOM_SAFE;
   int cx = (maxX >= 4) ? MathMax(4, MathMin(maxX, g_PnlX[item] + dx)) : 4;
   int cy = (maxY >= 4) ? MathMax(4, MathMin(maxY, g_PnlY[item] + dy)) : 4;
   ndx = cx - g_PnlX[item];
   ndy = cy - g_PnlY[item];
}

// P-PERF-06: one candidate of the type-filtered panel-move scan. Panels and
// the palette create ONLY label-family objects (the four PnlSet* helpers make
// LABEL / RECTANGLE_LABEL / BUTTON / BITMAP_LABEL, plus two OBJ_EDIT fields);
// the ~900 level/zone objects are HLINE / TREND / RECTANGLE / TEXT and can
// never match a Pnl_/Pal_ prefix, so enumerating them per move tick was pure
// waste. Same match, same move — fewer candidates.
// P-UI-82: and the AXIS that does not move is not written at all — R-PERF's
// own law ("never write an object property you would not change"). A horizontal
// drag used to pay the Y read+write on every one of the card's objects: half of
// the batch spent on a value that never changed.
//
// P-UI-83: **A BATCH COMPUTES, IT NEVER READS BACK** — the menu's own rule.
// `SubChromeMove` (the engine the user compares this one to) sets `px + offset`
// and never asks an object where it is. The card used to pay GET+SET per object
// per axis, i.e. HALF OF EVERY BATCH was a read of a value that cannot change
// while the press is held (the card is frozen: the move chain returns before
// any control can touch it). The offsets are now read ONCE per gesture, at the
// grab (`PnlMoveListBuild`), into `s_PnlMoveX0/Y0` against the card origin
// `s_PnlMoveOx/Oy`, so a batch is exactly `x0 + (target - origin)`: SET-only.
// Two futures follow from that, and the menu has both: a dropped frame can no
// longer drift the card (every batch writes the ABSOLUTE spot the cursor asks
// for, in the frame the offsets were read in), and the measured batch cost —
// the very number the adaptive window converges onto — is halved.
void PnlMoveOne(const int i,const int nx,const int ny)
{
   if(nx != s_PnlMoveOx)
      ObjectSetInteger(0, s_PnlMoveNm[i], OBJPROP_XDISTANCE,
                       s_PnlMoveX0[i] + (nx - s_PnlMoveOx));
   if(ny != s_PnlMoveOy)
      ObjectSetInteger(0, s_PnlMoveNm[i], OBJPROP_YDISTANCE,
                       s_PnlMoveY0[i] + (ny - s_PnlMoveOy));
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-82 (2026-09-14) — THE DRAG PAYS FOR ITS OWN OBJECTS, AND THE SPOT IS
// PARKED THE MOMENT THE DRAG IS PROVEN.
//
// THE REPORT: «جابه جا میشه ولی به صورت ریل تایم نیستش یعنی وقتی باز و بسته کنه
// پنل رو موقعیتش عوض میشه» — the card moves, but the move is not LIVE: only
// after closing and reopening does the position come out right.
//
// TWO DEFECTS, one per half of that sentence.
//
// (a) NOT LIVE — the batch re-scanned the chart to re-derive a list that cannot
//     have changed. `PnlMoveBy` walked the five UI types (5 `ObjectsTotal` +
//     one `ObjectName` + one `StringFind` per candidate, EVERY batch) sixty
//     times a second, although the card is FROZEN while a press is held: the
//     move chain returns before any control can rebuild it. That scan is the
//     cost the adaptive window (P-UI-75b) was converging onto, so the window sat
//     at its ceiling and the card stepped to the cursor instead of tracking it.
//     The list is now built ONCE PER GESTURE (at the grab) into `s_PnlMoveNm`,
//     and a batch is exactly N writes. The palette rides the same list (its
//     `Pal_` family is appended when it is anchored to this card), and a SHAPE
//     KEY (item · rows · width · height · palette-follows · this card's popover)
//     still re-builds on the one case a same-shape rebuild cannot cover: a
//     dropdown popover that appeared after the cached list was built. Same-shape
//     rebuilds need no invalidation at all — `PnlDestroy`/`PnlCreate` recreate
//     the SAME names for the same shape, which is why this is a key, not an
//     epoch. Idle cost: zero callers; the key is six compares.
//
// (b) NOT PARKED — `PnlCommitMove` ran only at the END of a gesture, so between
//     the first applied batch and the release the LOGICAL spot (what the next
//     open reads: `g_PnlManualPos` + `PnlComputePosition`) was still the OLD
//     one. Anything that ended the gesture without a release — a hotkey that
//     closes the card, a timeframe switch, a release MT4 never reported —
//     reopened the card at the previous spot: the report's second half, exactly.
//     The park is now written when the drag is PROVEN (the first batch past the
//     dead zone, which is what P-UI-80 defines a park to be), and the release
//     still refreshes it with the final pixel. ONE `GlobalVariableSet` per
//     gesture, never per batch.
// ══════════════════════════════════════════════════════════════════════════
#define PNL_MOVE_LIST_MAX 768
static string s_PnlMoveNm[PNL_MOVE_LIST_MAX];
static int    s_PnlMoveX0[PNL_MOVE_LIST_MAX];   // P-UI-83: object X when built
static int    s_PnlMoveY0[PNL_MOVE_LIST_MAX];   //            object Y when built
static int    s_PnlMoveN      = 0;      // names in the list (0 = never built)
static int    s_PnlMoveOx     = 0;      // P-UI-83: the card origin those X0/Y0
static int    s_PnlMoveOy     = 0;      // belong to (the frame of the batch)
static int    s_PnlMoveItemLk = -1;     // the SHAPE the list was built for
static int    s_PnlMoveRowsLk = -1;
static int    s_PnlMoveWLk    = 0;
static int    s_PnlMoveHLk    = 0;
static bool   s_PnlMovePalLk  = false;
static bool   s_PnlMoveDdLk   = false;  // this card's dropdown popover existed

//--- ONE owner for the palette-rides-along rule (P-UI-26/F5): only one panel is
//--- ever open, and a strip (13) move carries a hanging palette whatever its
//--- anchor item says (the bucket opens Pal(12,5) while the strip stays open).
//--- The shape key and the coordinate bookkeeping MUST agree, so both ask this.
bool PnlPalFollows(const int item)
{
   return (g_PalOpen && (g_PalAnchorItem == item || item == 13));
}

//--- does the cached list still describe the card as it is drawn NOW?
bool PnlMoveListFresh(const int item,const int rows,const int w,const int h,
                      const bool palFollow,const bool ddOpen)
{
   return (s_PnlMoveN > 0 && s_PnlMoveItemLk == item && s_PnlMoveRowsLk == rows &&
           s_PnlMoveWLk == w && s_PnlMoveHLk == h &&
           s_PnlMovePalLk == palFollow && s_PnlMoveDdLk == ddOpen);
}

//--- ONE scan per gesture: every name this card owns, by the P-PERF-06 type
//--- filter (the five UI types panels create — never the whole chart).
void PnlMoveListBuild(const int item,const int rows,const int w,const int h,
                      const bool palFollow,const bool ddOpen)
{
   s_PnlMoveN      = 0;
   s_PnlMoveItemLk = item;
   s_PnlMoveRowsLk = rows;
   s_PnlMoveWLk    = w;
   s_PnlMoveHLk    = h;
   s_PnlMovePalLk  = palFollow;
   s_PnlMoveDdLk   = ddOpen;
   // P-UI-83: the FRAME every offset below is measured in. The objects are read
   // once, here, at the origin the card is drawn at right now — so a batch may
   // write `x0 + (target - origin)` for the rest of the gesture without ever
   // reading again, exactly like the menu's chrome translate.
   s_PnlMoveOx     = g_PnlX[item];
   s_PnlMoveOy     = g_PnlY[item];
   const string pfx   = g_UI.btnPrefix + "Pnl" + IntegerToString(item) + "_";
   const string palPx = g_UI.btnPrefix + "Pal_";
   // P-UI-84: THE TYPE FILTER IS A TEST, NOT AN ARGUMENT SLOT.
   //
   // This used to be five passes of
   //     ObjectsTotal(0, otype, -1) / ObjectName(0, i, otype, -1)
   // which pass the OBJECT TYPE into the `sub_window` slot. Both platforms now
   // share one signature —
   //     ObjectsTotal(chart_id, sub_window = -1, type = -1)
   //     ObjectName (chart_id, index,      sub_window = -1, type = -1)
   // — and OBJ_LABEL is 22, OBJ_BUTTON 23, so the terminal was asked for the
   // object count of sub-window 22 of a chart that has one window. It returned
   // 0. The loop body never ran, `s_PnlMoveN` stayed 0, `PnlMoveListFresh()`
   // could never be true, and the drag batch had an empty list — so GRABBING A
   // PANEL AND MOVING IT DID NOTHING, silently, on both platforms. (An empty
   // list is not an error the terminal reports; it is simply nothing to move.)
   //
   // The repair is deliberately NOT `ObjectsTotal(0, -1, otype)`. Whether MQL4
   // honours a type filter in that third slot is a platform question, and a
   // build that compiles while quietly ignoring the filter would be a parity
   // bug of exactly the kind this project exists to prevent. So the type is
   // tested explicitly, and the enumeration uses the four-argument form that
   // every other walk in this tree already uses (`ObjectsTotal(0,-1,-1)` /
   // `ObjectName(0,i,-1,-1)`).
   //
   // One pass instead of five, the prefix still scopes the scan to this card
   // (a panel name is `btnPrefix + "Pnl<item>_"`; no level, zone or HTF object
   // can match it), and the type test runs only on names that already matched.
   const int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      if(s_PnlMoveN >= PNL_MOVE_LIST_MAX) break;
      const string nm = ObjectName(0, i, -1, -1);
      const bool isCard = (StringFind(nm, pfx) == 0);
      const bool isPal  = (palFollow && StringFind(nm, palPx) == 0);
      if(!isCard && !isPal) continue;
      const int otype = (int)ObjectGetInteger(0, nm, OBJPROP_TYPE);
      if(otype != OBJ_LABEL && otype != OBJ_BUTTON && otype != OBJ_BITMAP_LABEL &&
         otype != OBJ_EDIT  && otype != OBJ_RECTANGLE_LABEL) continue;
      {
         s_PnlMoveNm[s_PnlMoveN] = nm;
         // P-UI-83: the ONE read of this object's coordinates (the batch never
         // reads again) — the offset is fixed for the whole gesture.
         s_PnlMoveX0[s_PnlMoveN] = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
         s_PnlMoveY0[s_PnlMoveN] = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
         s_PnlMoveN++;
      }
   }
}

//--- the ONE place the key is computed (grab, batch and clamp all agree).
void PnlMoveListSync(const int item,const bool force)
{
   const bool palFollow = PnlPalFollows(item);
   const int  rows      = PnlRowsCount(item);
   const int  w         = PnlPanelW(item);
   const int  h         = PnlPanelH(item);
   const bool ddOpen    = (g_PnlDdItem == item);
   if(force || !PnlMoveListFresh(item, rows, w, h, palFollow, ddOpen))
      PnlMoveListBuild(item, rows, w, h, palFollow, ddOpen);
}

void PnlMoveBy(const int item, const int dx, const int dy)
{
   if(dx == 0 && dy == 0) return;
   // Clamp FIRST so logic and graphics can never diverge: a panel dragged
   // off-chart — or stranded there after the chart shrank — leaves its
   // header unreachable otherwise.
   int ndx, ndy;
   PnlClampSpot(item, dx, dy, ndx, ndy);
   if(ndx == 0 && ndy == 0) return;
   // P-UI-26/F5: only one panel is ever open — a strip (13) move carries a
   // hanging palette whatever its anchor item says (bucket opens Pal(12,5)
   // while the strip stays open, so anchor!=13 and the old test stranded it).
   const bool palFollow = PnlPalFollows(item);
   // P-UI-82: the list is built ONCE per gesture (`PnlTryGrabMove`) and only
   // re-built here when the card's SHAPE moved under it — never per batch.
   PnlMoveListSync(item, false);
   // P-UI-83: the batch's target is ABSOLUTE — the card's new origin — and each
   // object is the offset it had in the frame the list was read in. No reads,
   // and a dropped frame cannot drift (the next batch writes the true spot).
   const int nx = g_PnlX[item] + ndx;
   const int ny = g_PnlY[item] + ndy;
   for(int i = 0; i < s_PnlMoveN; i++) PnlMoveOne(i, nx, ny);
   if(palFollow) { g_PalX += ndx; g_PalY += ndy; }
   if(g_PnlDdItem == item) { g_PnlDdX += ndx; g_PnlDdY += ndy; }   // generic-dropdown hit-rect rides the header drag (PDDR objects move via the same list)
   // P-UI-26/F4: the strip popover hit-rect rides too — header drag can
   // never open one (PnlHeaderHit refuses 13) but the resize clamp moves it.
   if(item == 13 && g_BkDd != 0) { g_BkDdX += ndx; g_BkDdY += ndy; }
   g_PnlX[item] += ndx;
   g_PnlY[item] += ndy;
   // P-UI-98r: the card moved under the hand - republish and re-cull now
   // (projections + cache probes, writes only for flipped boxes).
   PnlPublishCover();
   HTFCardCullRefresh();
}

// Clamp the OPEN panel into a shrunken chart (Ctrl+T / navigator toggles).
// Parked (closed) panels re-clamp on next open via PnlComputePosition.
bool PnlClampOpenPanel()
{
   if(g_PnlOpen < 0) return false;
   int ndx, ndy;
   PnlClampSpot(g_PnlOpen, 0, 0, ndx, ndy);
   if(ndx == 0 && ndy == 0) return false;
   PnlMoveBy(g_PnlOpen, ndx, ndy);
   return true;
}

//+------------------------------------------------------------------+
//| Knob drag engine — mouse-move based.                              |
//| MT4 cannot natively drag OBJ_BUTTONs (only clicks), so the slider |
//| thumb is dragged with the same CHARTEVENT_MOUSE_MOVE pattern as   |
//| the orb / box-anchor engines.                                     |
//+------------------------------------------------------------------+
int g_PnlDragItem = -1;
int g_PnlDragRow  = -1;

bool PnlKnobHit(const int mx,const int my,int &item,int &row)
{
   item=-1; row=-1;
   if(g_PnlOpen < 0) return false;
   int px=g_PnlX[g_PnlOpen], py=g_PnlY[g_PnlOpen];
   int rowsCount=PnlRowsCount(g_PnlOpen);
   for(int r=0;r<rowsCount;r++)
   {
      int kind; string label,unit,opts; int minV,maxV; double step;
      PnlRowDef(g_PnlOpen,r,kind,label,minV,maxV,step,unit,opts);
      if(kind!=0) continue;
      double val=PnlCurrent(g_PnlOpen,r);
       int knobX=PnlSliderKnobX(g_PnlOpen,r,val,minV,maxV);      // absolute X
       // P-UI-131d: derived from the track's own centre, never a 42px-row literal —
       // the old `+21` was PNL_TRK_Y+PNL_TRK_H/2-PNL_KNOB_W/2 frozen for TRK_Y 27, so
       // moving the track moved the knob's GRAB ZONE (or not) by accident.
       int knobY=py+PNL_HEAD_H+PnlRowLine(g_PnlOpen,r)*PNL_ROW_H
                 +PNL_TRK_Y+PNL_TRK_H/2-PNL_KNOB_W/2;
      // generous grab zone: knob ±half width sideways, tight vertically — and the
      // floor is the ROW's own (P-UI-131d: knobY moved with the track, so `+2` past
      // the knob claimed a pixel of the row below — the classic ghost target).
      if(mx >= knobX-PNL_KNOB_W/2 && mx <= knobX+PNL_KNOB_W+PNL_KNOB_W/2 &&
         my >= knobY-4 && my <= knobY+PNL_KNOB_W)
      {
         item=g_PnlOpen; row=r;
         return true;
      }
   }
   return false;
}

//--- slider track rect (absolute px): click = jump + start dragging
bool PnlTrackHit(const int mx,const int my,int &item,int &row)
{
   item=-1; row=-1;
   if(g_PnlOpen < 0) return false;
   int px=g_PnlX[g_PnlOpen], py=g_PnlY[g_PnlOpen];
   int rowsCount=PnlRowsCount(g_PnlOpen);
   for(int r=0;r<rowsCount;r++)
   {
      int kind; string label,unit,opts; int minV,maxV; double step;
      PnlRowDef(g_PnlOpen,r,kind,label,minV,maxV,step,unit,opts);
       if(kind!=0) continue;
       int trackX=PnlRowBaseX(g_PnlOpen,r)+PNL_TRACK_X;
       int trackY=py+PNL_HEAD_H+PnlRowLine(g_PnlOpen,r)*PNL_ROW_H+PNL_TRK_Y;
      if(mx >= trackX && mx <= trackX+PNL_TRACK_W &&
         my >= trackY-8 && my <= trackY+PNL_TRK_H+5)
      {
         item=g_PnlOpen; row=r;
         return true;
      }
   }
   return false;
}

//--- switch pill rect (absolute px): press = flip instantly. The pill is
//--- right-aligned (PNL_SW_X); the old left-side checkbox box is gone.
bool PnlSwitchHit(const int mx,const int my,int &item,int &row)
{
   item=-1; row=-1;
   if(g_PnlOpen < 0) return false;
   int px=g_PnlX[g_PnlOpen], py=g_PnlY[g_PnlOpen];
   int rowsCount=PnlRowsCount(g_PnlOpen);
   for(int r=0;r<rowsCount;r++)
   {
      int kind; string label,unit,opts; int minV,maxV; double step;
      PnlRowDef(g_PnlOpen,r,kind,label,minV,maxV,step,unit,opts);
       if(kind!=1) continue;
       int swX=PnlRowBaseX(g_PnlOpen,r)+PNL_SW_X-PNL_SW_PAD;
       int swY=py+PNL_HEAD_H+PnlRowLine(g_PnlOpen,r)*PNL_ROW_H+PNL_SW_Y-PNL_SW_PAD;
      if(mx >= swX-5 && mx <= swX+PNL_SW_W+2*PNL_SW_PAD+5 &&
         my >= swY-5 && my <= swY+PNL_SW_H+2*PNL_SW_PAD+5)
      {
         item=g_PnlOpen; row=r;
         return true;
      }
   }
   return false;
}

void PnlValueFromX(const int item,const int row,const int mouseX,double &v)
{
   int kind; string label,unit,opts; int minV,maxV; double step;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   double frac=(mouseX-(PnlRowBaseX(item,row)+PNL_TRACK_X)) / (double)(PNL_TRACK_W-PNL_KNOB_W);
   frac=MathMax(0.0,MathMin(1.0,frac));
   v=minV + frac*(maxV-minV);
   v=MathRound(v/step)*step;
   if(v<minV) v=minV;
   if(v>maxV) v=maxV;
}

//+------------------------------------------------------------------+
//| P-UI-24: X / Done close on PRESS, not on release-click. The      |
//| release click (OBJECT_CLICK) can be eaten whenever the press     |
//| also arms another gesture (header-drag grab + release suppress   |
//| is the classic: the click never arrives and nothing closes). The |
//| press itself is unambiguous, so X + Done act the instant the     |
//| button goes down — strip-button parity (BkMiniStripPress works   |
//| the same way). The OBJECT_CLICK close stays as a fallback;       |
//| PnlCloseAll is idempotent so a double close is harmless.         |
//+------------------------------------------------------------------+
bool PnlClosePressHit(const int mx,const int my)
{
   if(g_PnlOpen < 0 || g_PnlOpen == 13) return false;   // strip has no X/Done
   int it = g_PnlOpen;
   int px = g_PnlX[it], py = g_PnlY[it];
   int cw = PnlCardW(it);
   // X button skin rect (the generous target the user sees)
   int xbx = px+cw-PNL_PAD_X-PNL_XBTN_VIS;
   if(mx >= xbx-PNL_XBTN_PAD && mx <= xbx+PNL_XBTN_VIS+PNL_XBTN_PAD &&
      my >= py+15-PNL_XBTN_PAD && my <= py+15+PNL_XBTN_VIS+PNL_XBTN_PAD)
      return true;
   // Done button (footer)
   int fy = py+PNL_HEAD_H+PnlPairRows(it)*PNL_ROW_H;
   int dx = px+cw-PNL_PAD_X-PNL_BTN_W;
   if(mx >= dx && mx <= dx+PNL_BTN_W && my >= fy+10 && my <= fy+10+PNL_BTN_H)
      return true;
   return false;
}

//+------------------------------------------------------------------
//| P-UI-70 (2026-09-14) — TWO UI BUGS THE USER FELT AS "the panel is
//| broken", both in this press pipeline.
//|                                                                    |
//| (a) THE WHOLE CARD IS A DRAG HANDLE. Only the 56 px header used to |
//|     be one (`PnlHeaderHit`), so a press anywhere in the card's BODY |
//|     — the natural place to grab a big card — fell on the floor and  |
//|     read as "the panels can't be dragged". `PnlCardBodyHit` is the  |
//|     background case: it is consulted LAST, so every real control    |
//|     still wins its own pixels.
//|                                                                    |
//| (b) A STALE CLAIM MUST NOT DEAD-LOCK THE PANEL. Every coordinate   |
//|     control of the panel (knobs, tracks, switches, cells, bands,    |
//|     the header drag) sits behind ONE guard — `DragCanGrab`. The    |
//|     claim is released by the button-up that ends its gesture, and  |
//|     MT4 emits NO mouse-move while the cursor is still, so a dropped |
//|     release left the claim set: from then on the panel ignored     |
//|     every press until it was re-attached. `PnlPressAllowed` makes   |
//|     the guard self-healing — an owner whose button is no longer     |
//|     down is stale by definition, and is taken back.
//+------------------------------------------------------------------
bool PnlPressAllowed()
{
   if(g_DragOwner == DRAG_NONE || g_DragOwner == DRAG_PANEL_KNOB ||
      g_DragOwner == DRAG_PANEL_MOVE) return true;
   // Another engine (orb move / ring long-press / box drag) owns the pointer.
   // TWO witnesses and ONE owner (`UILeftButtonDown`, P-UI-73) — the claim is
   // respected only while BOTH say the gesture is still live:
   //   * the physical probe covers the release MT4 never reported (no MOUSE_MOVE
   //     arrives while the cursor is still — the trap this whole guard exists
   //     for), and it now answers under EITHER MQL4 convention (`<0` vs bit 0),
   //     so the recovery can no longer be dead code on one build lineage;
   //   * the event latch (`g_MouseWasDown`, cleared by every CLICK /
   //     OBJECT_CLICK we see) covers the opposite error: a probe that reads
   //     "down" after the button is already up would otherwise keep the stale
   //     claim and lock every coordinate control of the open card out for good.
   // Either witness saying "free" takes the claim back — the safe direction,
   // because the panel is only ever taking its OWN pointer back.
   if(g_MouseWasDown && UILeftButtonDown())
   {
      // P-UI-88: the ONE press shape that used to vanish without a line. A
      // foreign live claim is respected by design, so a stuck DRAG_MENU / box
      // drag reads as "the whole panel is dead" with nothing in the log to say
      // so - name the owner instead (gated: one line per refused press, and
      // only when the press really is refused).
      _LOG_GATE_W Print("[UI] panel press refused (foreign claim owner=", (int)g_DragOwner, ")");
      return false;
   }
   g_DragOwner = DRAG_NONE;
   return true;
}

//--- the CARD's own rect — the drag-to-move fallback (P-UI-70a). Items 13/14
//--- are excluded like the header is: the strip re-anchors to its box.
bool PnlCardBodyHit(const int mx,const int my)
{
   if(g_PnlOpen < 0 || g_PnlOpen == 13) return false;
   int pw = PnlPanelW(g_PnlOpen);
   int ph = PnlPanelH(g_PnlOpen);
   return (mx >= g_PnlX[g_PnlOpen] && mx <= g_PnlX[g_PnlOpen] + pw &&
           my >= g_PnlY[g_PnlOpen] && my <= g_PnlY[g_PnlOpen] + ph);
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-75 (2026-09-14) — the drag has TWO entries and ONE contract, and it pays for
// its own frames. Reported (fourth time): the settings card cannot be dragged at all,
// and where it moves it does not follow the cursor.
// (a) A DRAG LIVED ON ONE DELIVERY CHANNEL — the MOUSE_MOVE press edge, and MT4 emits
// NO mouse-move for a press that does not move (P-BK-03), while `sparam`'s button bit
// can disagree with the physical button (P-UI-73a). Every other gesture here has a
// polled shadow, so the drag has one now: `PnlDragPoll()` arms through the SAME
// `PnlTryGrabMove`, steps through `PnlDragStep` and ends through `PnlDragFinish` — never
// on a control (`PnlPointOnControl`) and only while the physical button reads down AND
// the event latch never saw that press.
// (b) THE DRAG DID NOT PAY FOR ITS OWN FRAMES — a 30 Hz coalesce and a 100 ms redraw
// throttle could not compose (one repaint per ~10 batches). The window is adaptive now:
// cursor-glued at the grab, moving a quarter toward the measured batch cost, capped at
// `PNL_MOVE_FRAME_MAX_MS`. At rest the poll reads one int.
// ══════════════════════════════════════════════════════════════════════════
//--- the drag's frame window lives with the other gesture state below
//--- (`PnlCommitMove`, P-UI-75b), because the button-up finalizer resets one of its counters.

//--- is the point inside the palette popover? It floats ABOVE the card, so its
//--- pixels are the popover's and a press there never belongs to the card.
//--- ONE owner: the click channel's refusal and the drag's grab both ask it.
bool PnlPalettePointInside(const int cx,const int cy)
{
   if(!g_PalOpen) return false;
   return (cx >= g_PalX && cx <= g_PalX + PalW() &&
           cy >= g_PalY && cy <= g_PalY + PalH());
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-76 (2026-09-14) — A RELEASE-CHANNEL CONTROL IS A CONTROL TOO.
//
// THE REPORT: «اینا کار نمیکنه چرا» — a screenshot with two arrows, one on the
// TRANSPARENCY track, one on a COLOR quick-swatch whose own tooltip («Apply this
// colour», set only by the `Q0..Q7` buttons) names the object under the cursor.
//
// WHY THOSE TWO ARE THE SAME DEFECT, and why every gate was green: this card has
// TWO KINDS of control and they are claimed at DIFFERENT MOMENTS. The coordinate
// controls (switch / cset / `+` / band / dropdown / sliders) act on the PRESS.
// The NAME router's controls (colour preview `CB`, quick swatches `Q0..Q7`, NAV
// pill, segmented cells `C0..Cn`, the text field, the header/footer buttons) act
// on the RELEASE — MT4 hands the indicator OBJECT_CLICK when the button comes up.
// And the card body is a DRAG HANDLE (P-UI-70a), so a press on such a control was
// claimed by the grab: `PnlDragFinish(true, true)` then arms the release claim
// (P-UI-65, so a drag's release cannot double as a click) and the OBJECT_CLICK of
// that very gesture is spent ⇒ the control is DEAD. Only a click that moved ZERO
// pixels survived, because MT4 emits no MOUSE_MOVE for a motionless press (the
// `UILeftButtonDown` trap) and the grab therefore never armed — which is exactly
// the "sometimes it works, sometimes it doesn't" the user kept reporting, in a
// hand that moves 1-3 px on every real click.
//
// THE FIX: the grab refuses EVERY control's pixels, whichever channel claims it,
// so a control keeps both of its events and an empty pixel of the card keeps the
// drag. The geometry is READ BACK from the control's OWN object (OBJPROP_*
// distance + size) instead of re-derived from the paint constants: the object IS
// what the painter drew, so a hit can never drift from a paint — the failure mode
// that has cost this project four rounds. Cost: only ever paid on a press (the
// poll calls it after the physical-button gate), never on a tick.
// ══════════════════════════════════════════════════════════════════════════
bool PnlCtrlRectHit(const string nm,const int mx,const int my,const int pad)
{
   if(ObjectFind(0,nm) < 0) return false;
   int x=(int)ObjectGetInteger(0,nm,OBJPROP_XDISTANCE);
   int y=(int)ObjectGetInteger(0,nm,OBJPROP_YDISTANCE);
   int w=(int)ObjectGetInteger(0,nm,OBJPROP_XSIZE);
   int h=(int)ObjectGetInteger(0,nm,OBJPROP_YSIZE);
   if(w<=0 || h<=0) return false;   // a label has no box: never a control hit
   return (mx >= x-pad && mx <= x+w+pad && my >= y-pad && my <= y+h+pad);
}

//--- P-UI-127: THE RELEASE-CHANNEL PREDICATES ARE DELETED WITH THE SWEEP THAT
//--- ASKED THEM. P-UI-76 needed `PnlNameControlAt` because a control whose
//--- action arrived on the RELEASE had to keep a press the grab would steal;
//--- P-UI-87 gave every one of those families a coordinate action, and the card
//--- is a soft-claim handle now, so "which control owns this pixel?" has no
//--- reader left. Deleted as one unit: `PnlNameControlAt`, `PnlPressClaimCode`,
//--- `PnlPointOnControl` (the last had no caller in any commit). The compiler is
//--- the proof nothing lost its callee; `PnlCtrlRectHit` stays (the strip and the
//--- skin hit tests read their controls back through it).

//+------------------------------------------------------------------+
//| P-UI-128 (2026-09-25) — A BAKED FACE WEARS ITS ACTION ON THE PRESS.|
//|                                                                   |
//| The footer pair (`rst` / `pal`) and every NAV pill keep an         |
//| OBJ_BUTTON UNDER their bitmap face (`pnl_btn_ghost.bmp`,          |
//| `pnl_nav.bmp`, both Z_PANEL_SKIN) and pushed the button to         |
//| Z_PANEL_BASE — deliberately, so the rounded bake is what shows.    |
//| MT4 hands OBJECT_CLICK to the object under the pointer, and a      |
//| bitmap label above a button answers no click at all (P-UI-87's     |
//| measured rule), so those two families could only ever be reached   |
//| by a name the terminal never sent. Measured on the live ledger:    |
//| taps at (1262,566) armed the move, finished `moved=0` and NOTHING  |
//| acted, while the terminal still showed the row's own "Open …"      |
//| tooltip. The click a bake swallows is not a delivery to wait for:  |
//| ONE read-back hit test per family, acted on the PRESS through the  |
//| SAME owners the name router calls, so one click opens the card.    |
//| Cost: two `PnlCtrlRectHit` reads, plus one rect read per NAV row,  |
//| and only while a press is being delivered.                        |
//+------------------------------------------------------------------+
bool PnlSkinButtonAct(const int mx,const int my)
{
   const int item = g_PnlOpen;
   if(item < 0 || item == 13) return false;   // the strip owns its own buttons
   // ── the footer pair ──
   if(PnlCtrlRectHit(PnlHead(item,"rst"),mx,my,PNL_BTN_PAD))
   {
      UIPressAct("rst");
      const int f = PnlResetItem(item);
      // P-UI-130: "reset did nothing" and "reset was never reached" are different
      // facts. `(rst)` already names the press; this names its EFFECT in one line
      // (how many rows it walked, what it asked the chart to re-render), so the
      // next report cannot be answered with a guess.
      _LOG_GATE_W Print("[UI] panel reset item=", item, " rows=", PnlRowsCount(item),
                        " flags=", f);
      if(f != REFRESH_NONE) RefreshDisplay(f); else RepaintForDiscreteAction();
      return true;
   }
   if(PnlCtrlRectHit(PnlHead(item,"pal"),mx,my,PNL_BTN_PAD))
   {
      UIPressAct("pal");
      PalOpenForItem(item);
      RepaintForDiscreteAction();
      return true;
   }
   // ── NAV rows — the pill's own button IS the face's own rect ──
   const int rows = PnlRowsCount(item);
   for(int r=0;r<rows;r++)
   {
      int kind=0,minV=0,maxV=0; double step=1; string label="",unit="",opts="";
      PnlRowDef(item,r,kind,label,minV,maxV,step,unit,opts);
      if(kind != PNL_K_NAV) continue;
      if(!PnlCtrlRectHit(PnlName(item,r,"NAV"),mx,my,0)) continue;
      UIPressAct("nav");                     // names the PRESSED card, before the swap
      if(opts == "DEL")                      // the mini strip's own action
      {
         if(g_BkMiniBox != "" && BaseKnotFind(g_BkMiniBox) >= 0) BaseKnotDelete(g_BkMiniBox);
         g_BkMiniBox = "";
         PnlCloseAll();
      }
      else
      {
         const int tgt = (int)StringToInteger(opts);
         if(tgt >= 0 && tgt < PNL_COUNT && tgt != item) PnlOpen(tgt);
      }
      RepaintForDiscreteAction();            // P-PERF-24's owner, not a bare redraw
      return true;
   }
   return false;
}
// ══════════════════════════════════════════════════════════════════════════
// P-UI-87 (2026-09-14) — A CLAIM IS NOT AN ACTION.
//
// «این رنگ ها کار نمیکنه هر چی روش کلیک میکنم انگار ایراد داره» + the ATR
// card's COUNT COLOR strip. The LIVE LEDGER named it in one line: on EURUSD M1
// three presses landed on card 0's colour strip (x 697/720/725, y 285 - inside
// the strip's own 275..297 band) and each was refused by the grab with `(C)`,
// i.e. "a card control owns this pixel" (`PnlNameControlAt`, P-UI-76; deleted with
// its sweep by P-UI-127) - and nothing ever acted, and no colour changed.
//
// That is the P-UI-74 defect one widget further in: `PnlNameControlAt` CLAIMED
// the preview block and the eight quick swatches - which is what keeps the grab
// from dragging the card out from under them - but the strip existed ONLY on
// the NAME router (`PnlHandleClick`), and this is the one widget family whose
// pixels are its own glass skins (`pnl_glass46`/`pnl_glass22`), the objects MT4
// hands no `OBJECT_CLICK` for. A claim without an action is a control that eats
// its own press.
//
// So the strip is a REAL affordance of the coordinate chain now, applied
// through ONE owner (`PnlQuickSwatchApply`) that the name router also calls -
// the swatches cannot apply twice or drift apart, and the preview block opens
// the picker from either channel.
// ══════════════════════════════════════════════════════════════════════════
int PnlQuickSwatchApply(const int item,const int row,const int qi)
{
   if(g_PnlOpen != item) return REFRESH_NONE;
   if(qi < 0 || qi >= PNL_QSW_N) return REFRESH_NONE;
   int k = PnlColorKind(item,row);
   if(k < 0) return REFRESH_NONE;
   color qc = QuickPalColor(qi);
   int flags = PaletteApplyColor(k,qc);
   PushPalRecent(qc);
   PnlUpdateRow(item,row);
   if(g_PalOpen && g_PalKind==k) PalUpdateLive();
   return flags;
}

//--- where IS the strip? Read back from the cells the row PAINTED (P-UI-79's
//--- doctrine), never recomputed from the layout maths. `qi == -1` = the
//--- preview block, whose press opens the full picker.
bool PnlQuickSwatchHit(const int mx,const int my,int &item,int &row,int &qi)
{
   item = g_PnlOpen;
   row = -1; qi = -2;
   if(item < 0 || item == 13) return false;
   int rows = PnlRowsCount(item);
   for(int r=0;r<rows;r++)
   {
      int kind=0,minV=0,maxV=0; double step=1; string label="",unit="",opts="";
      PnlRowDef(item,r,kind,label,minV,maxV,step,unit,opts);
      if(kind != PNL_K_COL) continue;
      if(PnlCtrlRectHit(PnlName(item,r,"CB"),mx,my,0)) { row=r; qi=-1; return true; }
      for(int q=0;q<PNL_QSW_N;q++)
         if(PnlCtrlRectHit(PnlName(item,r,"Q"+IntegerToString(q)),mx,my,0))
         { row=r; qi=q; return true; }
   }
   return false;
}

//--- P-UI-78: WHY the grab refused, in one place — and the ledger prints it
//--- here, but ONLY for the event channel (one line per user press). Codes:
//--- M = a move already owns it, X = closed/strip, P = the palette owns the
//--- pixel, C:close/C:dd = the two pixels that keep their press whole
//--- (P-UI-127), H = neither the header nor the body is under the cursor.
void PnlGrabRefused(const string why,const bool byPoll,const int mx,const int my,
                    const int px,const int py,const int pw,const int ph)
{
   if(!byPoll)
      _LOG_GATE_W Print("[UI] panel drag grab refused (" + why + ") item=", g_PnlOpen,
                        " at ", mx, ",", my, " rect=", px, ",", py, ",", pw, ",", ph);
}

//--- P-UI-79: is the press on the card's own DRAWN body skin? The skins are
//--- created from the same px,py the remembered rect is built from — but they
//--- ARE the paint, so when the two ever disagree the skins win. Narrow body
//--- is "card"; a wide one adds "cardm0..n" bands plus "cardb" (and the
//--- "cardf" wash never decides: it overlays the footer). Only ObjectFind +
//--- rect reads, and only called after the rect already missed — zero
//--- steady-state cost, and a miss here is a press on no card pixel at all.
bool PnlSkinHit(const int item,const int mx,const int my)
{
   if(item < 0 || item >= PNL_COUNT || item == 13) return false;
   if(PnlCtrlRectHit(PnlHead(item,"card"),mx,my,0)) return true;
   if(PnlCtrlRectHit(PnlHead(item,"cardb"),mx,my,0)) return true;
   int n = PnlPairRows(item);
   for(int li=0; li<n; li++)
      if(PnlCtrlRectHit(PnlHead(item,"cardm"+IntegerToString(li)),mx,my,0)) return true;
   return false;
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-127 (2026-09-25) — THE CARD-MOVE GESTURE IS BACK, AT A PRICE IT CAN AFFORD.
// The user asked for it again («پنل رو هم بشه درگ کرد»), so PANELDRAG-OFF (2026-09-14)
// is reversed — but not the way it was retired. Its two measured costs are answered
// instead of paid: the 12-family `PnlPressClaimCode` sweep (78-79 ms on a press) is
// DELETED — the arm now asks two compares for the only two pixels that keep a press
// whole, and the longer control proof is raised by `UIPressAct` when a control really
// acts (ONE writer, no hit test); and `PnlDragPoll` stays UNCALLED, because the same
// measurement recorded 197 drags armed by the event channel against ZERO by the poll.
// Live again: `PnlTryGrabMove` (the arm site), the move branch of `PnlHandleMouseMove`,
// `PnlDragStep`/`PnlDragFinish`, the `PNL_MOVE_*` window. Still uncalled, kept compiled
// as the restore path: `PnlDragPoll`. Deleted with the sweep: `PnlNameControlAt`,
// `PnlPressClaimCode`, `PnlPointOnControl`.
// ══════════════════════════════════════════════════════════════════════════
//--- THE GRAB — one owner, two entries (the press chain and the poll); `byPoll` records WHO armed it (P-UI-77), so the release belongs to the arming channel.
bool PnlTryGrabMove(const int mx,const int my,const bool byPoll)
{
   // The remembered rect, for the ledger (P-UI-79): when a press misses it,
   // the line must show WHERE the rect was — "outside" is only an answer
   // against a stated rect.
   int rpx = (g_PnlOpen >= 0 ? g_PnlX[g_PnlOpen] : 0);
   int rpy = (g_PnlOpen >= 0 ? g_PnlY[g_PnlOpen] : 0);
   int rpw = (g_PnlOpen >= 0 ? PnlPanelW(g_PnlOpen) : 0);
   int rph = (g_PnlOpen >= 0 ? PnlPanelH(g_PnlOpen) : 0);
   if(g_PnlMoveItem >= 0) { PnlGrabRefused("M",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }
   //--- the palette's title carry is live: it owns DRAG_PANEL_MOVE, so a second
   //--- arm here would starve behind it and jump on its finish (stale anchor).
   if(s_palMoveArmed) { PnlGrabRefused("T",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }
   if(g_PnlOpen < 0 || g_PnlOpen == 13) { PnlGrabRefused("X",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }
   if(PnlPalettePointInside(mx,my)) { PnlGrabRefused("P",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }
   // P-UI-127 (2026-09-25) — THE SWEEP IS GONE, AND THE HARD REFUSALS ARE TWO.
   // P-UI-88's 12-family `PnlPressClaimCode` sweep ran on EVERY press while the
   // tap family below ran the same families a SECOND time (measured then:
   // `[W][PERF] mouse move breakdown: panel=78ms`). Its only job here was to
   // separate the widgets whose press IS their own pointer gesture from the ones
   // a tap may keep — and that first group has already RETURNED above (the slider
   // branch) or is answered by two compares: X/Done, and an open dropdown. Every
   // other claim is SOFT by P-UI-89, and "was this pixel a control's?" now costs
   // nothing at all: `UIPressAct` — the one place a control's action passes
   // through — raises the proof (PnlDragThreshPx) on the tap family's own path.
   if(PnlClosePressHit(mx,my)) { PnlGrabRefused("C:close",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }
   if(g_PnlDdItem >= 0)        { PnlGrabRefused("C:dd",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }
   // P-UI-89, KEPT: EVERY OTHER PIXEL CLAIMS THE PRESS SOFTLY. A switch, a
   // colour cell, the colour strip, a section band, the header's .key cap, the
   // RELEASE-channel family (a NAV pill, a segmented cell, the text field, the
   // footer's console button) — all arm this move AND still act: a TAP ends
   // `moved=0`, so nothing is committed and no click is eaten (the control's own
   // action lands exactly as before), while a DRAG past `PnlDragThreshPx()`
   // moves the card and eats that click (P-UI-65). What a control keeps is the
   // press ITSELF; what the card takes is the MOVEMENT past the proof.
   // The rect missed — ask the PAINT itself before giving up. When rect and
   // paint ever disagree, the skins are ground truth and the grab still
   // stands (ledgered as via=skin, so the divergence stays visible too).
   bool viaSkin = false;
   if(!PnlHeaderHit(mx,my) && !PnlCardBodyHit(mx,my))
   {
      if(!PnlSkinHit(g_PnlOpen,mx,my)) { PnlGrabRefused("H",byPoll,mx,my,rpx,rpy,rpw,rph); return false; }
      viaSkin = true;
   }
   // P-UI-82: ONE scan per gesture — the batch then pays N writes, never a
   // chart sweep. Forced here (not only key-checked) so a gesture ALWAYS starts
   // from the drawing as it is, whatever an earlier gesture cached.
   PnlMoveListSync(g_PnlOpen, true);
   g_PnlMoveItem    = g_PnlOpen;
   g_PnlMoveLastX   = mx;
   g_PnlMoveLastY   = my;
   s_PnlMoveGrabX   = mx;   // P-UI-80: the dead zone is measured from the press
   s_PnlMoveGrabY   = my;
   s_PnlMoveMoved   = false;
   s_PnlMoveByPoll  = byPoll;
   s_PnlMoveOnCtrl  = false;   // P-UI-89: the proof starts short; a control that
                               // ACTS on this press raises it (UIPressAct)
   s_PnlMoveFrameMs = PNL_MOVE_FRAME_MIN_MS;   // a fresh gesture starts smooth
   s_PnlMoveTick    = 0;                       // its first batch applies at once
   s_PnlMoveFrames  = 0;                       // P-UI-83: its evidence starts empty
   s_PnlMoveWorst   = 0;
   DragClaim(DRAG_PANEL_MOVE);
   CircLockChart();
   // P-UI-78: one line per gesture (never per move) — the next "can't drag"
   // names its own arming channel instead of being re-investigated.
   // P-UI-79: via=skin names a grab the remembered rect missed.
   _LOG_GATE_W Print("[UI] panel drag armed by " + (byPoll ? "poll" : "event") + " item=", g_PnlOpen, " via=", (viaSkin ? "skin" : "rect"), " at ", mx, ",", my);
   return true;
}

//--- P-UI-89: how far the pointer must travel before THIS gesture is a DRAG.
//--- A press that landed on a control's own pixel owes the longer proof
//--- (`PNL_DRAG_CTRL_PX`), a press on the card's own body the menu's 3 px. ONE
//--- owner: the batch path asks it twice and can never resolve its own bound.
int PnlDragThreshPx()
{
   return (s_PnlMoveOnCtrl ? PNL_DRAG_CTRL_PX : PNL_DRAG_THRESHOLD_PX);
}

//--- ONE batch of the move: apply what the cursor travelled since the last one,
//--- then pay for exactly one frame. Both entries (event + poll) call THIS.
void PnlDragStep(const int mx,const int my)
{
   if(g_PnlMoveItem < 0) return;
   // P-UI-75b: the adaptive window IS the coalescer now (P-PERF-04's promise —
   // the delta accumulates, so the card still tracks the cursor exactly — kept,
   // at a rate the machine can hold instead of a hard 30 Hz).
   uint now = GetTickCount();
   if(s_PnlMoveTick != 0 && now - s_PnlMoveTick < (uint)s_PnlMoveFrameMs) return;
   if(mx == g_PnlMoveLastX && my == g_PnlMoveLastY) return;   // nothing to apply
   // P-UI-80: the menu's dead zone (ORB_DRAG_THRESHOLD parity) — tremor at or
   // under the threshold tracks the cursor but moves NOTHING and paints
   // nothing, so a tap can never drift the card nor eat its own release. The
   // last point still advances, so crossing the threshold later starts clean
   // with no jump. `s_PnlMoveMoved` is the dragged latch from here on, exactly
   // like the menu's `g_OrbWasDragged`.
   if(!s_PnlMoveMoved &&
      MathAbs(mx - s_PnlMoveGrabX) <= PnlDragThreshPx() &&
      MathAbs(my - s_PnlMoveGrabY) <= PnlDragThreshPx())
   {
      g_PnlMoveLastX = mx;
      g_PnlMoveLastY = my;
      return;
   }
   s_PnlMoveTick = now;
   uint t0 = GetTickCount();
   CircReassertLock();   // LEARNING §5: the panel owns the view until release
   PnlMoveBy(g_PnlMoveItem, mx - g_PnlMoveLastX, my - g_PnlMoveLastY);
   g_PnlMoveLastX = mx;
   g_PnlMoveLastY = my;
   // P-UI-82: park the spot the moment the drag is PROVEN, not at the release.
   // The next open reads `g_PnlManualPos` + `g_PnlX/Y`, so a gesture that never
   // gets its release (hotkey close, TF switch, focus stolen, a missed event)
   // must still reopen exactly where the user left it — that IS the report
   // «وقتی باز و بسته کنیم پنل رو موقعیتش عوض میشه». One write per gesture; the
   // release below still refreshes it with the final pixel.
   if(!s_PnlMoveMoved) PnlCommitMove(g_PnlMoveItem);
   s_PnlMoveMoved = true;
   DragFrameRedraw();    // the drag's own frame, once per applied batch
   // Converge the window on the MEASURED batch (writes + frame). GetTickCount()
   // resolves ~16 ms and that is enough: the question is the order of magnitude,
   // and the floor keeps a zero measurement from asking for an unbounded rate.
   int cost = (int)(GetTickCount() - t0) + PNL_MOVE_SLACK_MS;
   // P-UI-83: and the gesture MEASURES ITSELF, so "not live" can be answered
   // from the log instead of re-investigated: the finish line prints how many
   // batches this press really bought and what the worst one cost. Both are
   // gesture-scoped (never per-frame output — the ledger stays off the batch
   // path, P-UI-78).
   s_PnlMoveFrames++;
   if(cost > s_PnlMoveWorst) s_PnlMoveWorst = cost;
   if(cost < PNL_MOVE_FRAME_MIN_MS) cost = PNL_MOVE_FRAME_MIN_MS;
   if(cost > PNL_MOVE_FRAME_MAX_MS) cost = PNL_MOVE_FRAME_MAX_MS;
   s_PnlMoveFrameMs = (s_PnlMoveFrameMs * 3 + cost) / 4;   // EWMA 3:1, no oscillation
}

//--- END the drag. `commit` pins the spot for future opens; `suppressClick`
//--- eats the release that belongs to this gesture (P-UI-65's one-gesture rule).
void PnlDragFinish(const bool commit,const bool suppressClick)
{
   if(g_PnlMoveItem < 0) return;
   // P-UI-78: one line per gesture — did it move, and whose release rule ran?
   // Read BEFORE the resets below. The next "jumped / never moved" starts here.
   _LOG_GATE_W Print("[UI] panel drag finished moved=", (s_PnlMoveMoved ? 1 : 0), " byPoll=", (s_PnlMoveByPoll ? 1 : 0), " frames=", s_PnlMoveFrames, " worst=", s_PnlMoveWorst, "ms");
   if(commit) PnlCommitMove(g_PnlMoveItem);   // keep the spot even on a missed release
   g_PnlMoveItem = -1;
   s_PnlMoveMoved = false;
   s_PnlMoveByPoll = false;   // P-UI-77: the channel flag dies with the gesture
   s_PnlMoveOnCtrl = false;   // P-UI-89: and so does the control-press proof
   s_PnlPollUpArmed = false;  // P-UI-78: the rumour filter dies with it too
   DragReleaseIf(DRAG_PANEL_MOVE);
   if(suppressClick) UISuppressNextClick();
   CircUnlockChart();
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-81 (2026-09-14) — A NEW PRESS IS THE PROOF THAT THE LAST GESTURE IS OVER.
// Reported (fifth time, and the first that names the second half): the card CAN be
// moved, and from that moment the panel is DEAD until the indicator is re-attached —
// not a drag defect but a LATCH one: the move chain returns early while
// `g_PnlMoveItem >= 0`, and the slider / mixer latches skip the same block, so ONE
// panel latch left set switches off EVERY control of EVERY card.
// WHY A LATCH COULD STAY SET: all three of its exits need a witness the terminal may
// never deliver — a later MOUSE_MOVE carrying the release bit (MT4 emits NO move for a
// release that does not travel, P-BK-03), the physical probe `UILeftButtonUp()` (a
// heuristic whose KEYSTATE spelling differs by build lineage, P-UI-73a), and the
// button-up finalizer, itself gated by that probe.
// THE WITNESS THAT CANNOT BE MISSED IS THE NEXT PRESS: a press EDGE means the button
// went up and came back down, so a panel latch still set belongs to a gesture already
// over. Healthy gestures are untouched (exactly ONE edge exists while the button is
// held), and the P-UI-49b echo case re-grabs from the same press, re-anchored on the
// CURRENT cursor — one frame paid, never a bricked panel.
// ══════════════════════════════════════════════════════════════════════════
void PnlReapStaleGestures(const bool commitMove)
{
   // The slider drag and the palette mixer drag end exactly as their own release
   // paths end them, so neither can leave its claim, its heavy-pass budget or
   // its chart lock behind.
   if(g_PnlDragItem >= 0)
   {
      g_PnlDragItem = -1;
      g_PnlDragRow  = -1;
      DragReleaseIf(DRAG_PANEL_KNOB);
      UIDragBudgetEnd();
      CircUnlockChart();
   }
   if(g_PalMixDrag > 0)
   {
      g_PalMixDrag = 0;
      PalRefreshRecents(true);   // the coalesced recents tail still lands
      DragReleaseIf(DRAG_PANEL_KNOB);
      UIDragBudgetEnd();
      CircUnlockChart();
   }
    // The move drag goes through its OWN finish — ONE owner for its claim, its
    // chart lock, its release claim and its ledger line. Never `suppressClick`
    // here: the click that follows belongs to the NEW press, not to the dead
    // gesture (arming a claim for it would eat the next genuine click, P-UI-65).
    if(g_PnlMoveItem >= 0) PnlDragFinish(commitMove, false);
    if(s_palMoveArmed) PalMoveDisarm();   // the palette title carry: same rule
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-74 (2026-09-14) — EVERY CARD CONTROL ANSWERS ON BOTH DELIVERY CHANNELS, AND
// ONE GESTURE STILL HAS EXACTLY ONE OWNER. Reported (third time): clicking the colour
// strip of the ATR card does nothing, while the palette opened elsewhere applies fine.
// MEASURED FIRST: the shipped build paints that strip exactly where `PnlCsetHit` looks
// (columns 617/661/705/749/793, band y 790..818 against a paint at 794..813) and every
// gate was green — so the geometry and the apply logic were never the hole. The hole is
// DELIVERY: the NAME-based router (`PnlHandleClick`) owns the nav buttons, the colour
// preview, X/Done and the swatches, while the COORDINATE press chain owns the switch
// pill, the cset cells, the "+" chip, the section bands and the sliders — and only that
// channel, whose events can be eaten by a foreign drag claim (P-UI-70b/72) or simply not
// delivered for a control topped by a bitmap (MT4 fires no OBJECT_CLICK for the glass
// skin).
// THE FIX IS NOT A SECOND COPY OF THE DISPATCH (that is the two-deciders shape): the
// CLICK channel re-enters the SAME `PnlHandleMouseMove` with a synthetic fresh press, and
// three latches make the twin delivery safe — `s_PnlActedSeq` (the press identity already
// acted for), `s_PnlClickActed` (acted while the button was still down, so the next press
// pass consumes it) and `s_PnlClickChannel` (no click claim may be armed there, and the
// card-body drag grab is refused — only a press may start a move).
// ══════════════════════════════════════════════════════════════════════════
static uint s_PnlActedSeq     = 0;      // press identity that a CONTROL acted for
static bool s_PnlClickChannel = false;  // TRUE while the CLICK channel dispatches
static bool s_PnlClickActed   = false;  // the click channel acted; its press echo
                                        // is still due and must not act again

//--- did a control already act for the gesture currently being delivered?
bool PnlGestureConsumed()
{
   return (g_UIPressSeq != 0 && s_PnlActedSeq == g_UIPressSeq);
}

#endif // BIOTAK_PANELS_HIT_MQH
