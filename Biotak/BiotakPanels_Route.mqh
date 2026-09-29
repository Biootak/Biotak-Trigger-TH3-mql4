// BiotakPanels_Route.mqh - BiotakPanels split 2026-09-29: exact lines 8742-9983 of BiotakPanels.mqh, byte-identical, zero renames.
#ifndef BIOTAK_PANELS_ROUTE_MQH
#define BIOTAK_PANELS_ROUTE_MQH

//--- a CONTROL of the open card just acted. The latch is the whole point: the
//--- twin event of this release must not act a second time. The release claim
//--- (P-UI-65) is armed on the PRESS channel only — on the click channel the
//--- release IS the event being handled, and a claim armed there would eat the
//--- NEXT genuine click (the P-UI-01 symptom).
//--- P-UI-88: THE LEDGER'S ACT HALF. The grab's refusal line answered "which
//--- control owns the press that did nothing"; this answers "which control
//--- SPENT it". Together the two make the empty log impossible for any press
//--- inside the card — which is the property the last four "can't drag / can't
//--- click" reports were missing: "nothing happened" and "nothing was pressed"
//--- are different facts and only a line can tell them apart. ONE line per
//--- press that a control owned (the twin delivery is latched before it acts),
//--- and the code comes from the SAME names `PnlPressClaimCode` answers with.
void UIPressAct(const string code="")
{
   if(code != "")
      _LOG_GATE_W Print("[UI] panel press acted (", code, ") item=", g_PnlOpen);
   s_PnlActedSeq = g_UIPressSeq;
   // P-UI-127: a control SPENT this press, so the card's move gesture owes the
   // longer proof before it may move anything (P-UI-89's `PNL_DRAG_CTRL_PX`).
   // This is the proof's ONE writer: every control action passes through here,
   // so the answer costs no hit test and cannot disagree with what acted.
   if(g_PnlMoveItem >= 0) s_PnlMoveOnCtrl = true;
   if(!s_PnlClickChannel) UISuppressNextClick();
}

void PnlHandleMouseMove(const int mx,const int my,const bool leftDown,const bool pressStart)
{
   // P-UI-81: a NEW press is the proof that the previous gesture is over — reap
   // every panel latch BEFORE anything reads it, so one missed release can never
   // brick the card (see PnlReapStaleGestures). Paid only on a press edge, and
   // never on the click channel: that button is already UP, and a released button
   // must not kill a live drag.
   if(pressStart && !s_PnlClickChannel) PnlReapStaleGestures(s_PnlMoveMoved);
   // ── Palette popup mixer drag (independent channel; palette sits above) ──
   if(g_PalOpen)
   {
      // P-UI-131h: the colour grid previews under a MOVING, UNPRESSED pointer - one
      // apply per cell crossing, nothing while it stays, a restore when it leaves.
      if(!leftDown && !pressStart) PalHoverPreview(mx,my);
      if(g_PalMixDrag > 0)
      {          if(!leftDown)
          {
             g_PalMixDrag = 0;
             PalRefreshRecents(true);   // P-UI-69: flush the coalesced recents tail
             DragReleaseIf(DRAG_PANEL_KNOB);
             UIDragBudgetEnd();   // P-UI-33: settle the mixer's tail while still owned
             CircUnlockChart();
            UISuppressNextClick();
            return;
         }
         static uint s_PalMove = 0;
         uint now = GetTickCount();
         if(now - s_PalMove >= 30) { s_PalMove = now; CircReassertLock(); PaletteMixFromX(g_PalMixDrag, mx); }
         return;
      }
      if(pressStart && DragCanGrab(DRAG_PANEL_KNOB))
      {
         int d = PaletteMixHit(mx,my);
         if(d > 0)
         {
            g_PalMixDrag = d;
            DragClaim(DRAG_PANEL_KNOB);
            UIDragBudgetBegin();   // P-UI-33: charged to the shared heavy-pass budget
            CircLockChart();
            PaletteMixFromX(d,mx);   // first touch passes straight through
            return;
         }
      }
      // fall through: palette open but not on a mixer track → panel drags work
   }

   // Panel vanished mid-drag (Esc / Done) → drop the drag + its chart lock
   if(g_PnlDragItem >= 0 && (g_PnlOpen < 0 || g_PnlOpen != g_PnlDragItem))
   {
      g_PnlDragItem=-1; g_PnlDragRow=-1;
      DragReleaseIf(DRAG_PANEL_KNOB);
      UIDragBudgetEnd();   // P-UI-33: the surface vanished mid-gesture — settle once
      CircUnlockChart();
      return;
   }

    // ── Drag-to-move: the card is a handle from every pixel (P-UI-127) ──
    // Live again since P-UI-127, and its sibling latches are the slider
    // (`g_PnlDragItem`) and the palette mixer (`g_PalMixDrag`). The old
    // retirement note (kept whole in git and in the banner above the grab) said
    // `g_PnlMoveItem` was left at -1 by every path so the condition below was
    // dead by construction, while the
    // restore is this `false &&` deleted plus the arm site uncommented.
    if(s_palMoveArmed)   // the palette's own title carry runs before the card's
    {
       if(!g_PalOpen) { PalMoveDisarm(); return; }
       if(!leftDown) { PalMoveFinish(); return; }
       PalMoveStep(mx, my);
       return;
    }
    if(g_PnlMoveItem >= 0)
   {
      // Panel closed mid-drag (Esc / Done) → abort the move cleanly
      if(g_PnlOpen < 0 || g_PnlOpen != g_PnlMoveItem)
      {
         g_PnlMoveItem = -1;
         DragReleaseIf(DRAG_PANEL_MOVE);
         CircUnlockChart();
         return;
      }
      // P-UI-77: the channel that ARMED the drag owns its release. The event
      // sparam bit is one witness of two (P-UI-73a) — an event-armed drag ends
      // on it exactly as before, but a poll-armed drag (whose press that bit
      // never showed) ends only when the physical probe AGREES
      // (`UILeftButtonUp`). Otherwise the first disagreeing event murders a
      // working drag in its first step and eats its release — the card reads
      // as fixed. Healthy terminals never notice: the event edge wins the arm
      // race there, so `byPoll` is false and this line is the old line (the
      // `||` short-circuits before any terminal read — zero added cost).
      if(!leftDown && (!s_PnlMoveByPoll || UILeftButtonUp()))
      {
         // P-UI-80: menu parity — only a REAL drag (past the dead zone, like
         // `g_OrbWasDragged`) pins the spot and eats its release; a tap keeps
         // neither, so taps can never drift the card nor swallow a click. The
         // poll already finished this way — now both entries speak one rule.
         PnlDragFinish(s_PnlMoveMoved, s_PnlMoveMoved);
         return;
      }
      // ONE batch owner (P-UI-75b): the adaptive window coalesces, the batch
      // pays for exactly one frame. The poll calls the same function.
      PnlDragStep(mx, my);
      return;
   }

   if(g_PnlDragItem < 0)
   {
      // not dragging: a fresh press may grab the knob, jump+drag the track,
      // or flip a toggle — all coordinate-based (no invisible buttons).
      if(!pressStart) return;
      if(g_PnlOpen < 0) return;
      // P-UI-74: the click MIRROR of a gesture whose control already acted (the
      // click channel ran first — MT4 may deliver the click of the very press
      // that grabbed the object). One gesture, one owner: consume the echo.
      if(s_PnlClickActed) { s_PnlClickActed = false; return; }
      if(!PnlPressAllowed()) return;   // P-UI-70b: self-healing (a stale claim
                                       // used to kill every control here)

      // P-UI-24: X / Done close on PRESS — before strip/dropdown/knob/track/
      // switch/drag can claim the press and eat the release click.
      if(PnlClosePressHit(mx,my))
      {
         PnlCloseAll();
         UIPressAct("close");   // P-UI-74: latch the gesture + claim its release
         ChartRedraw();
         return;
      }

      if(g_PnlOpen == 13)   // BASE BOX MINI strip — icon buttons are
      {                     // OBJ_BITMAP_LABEL (no OBJECT_CLICK), so the
                            // press IS the click, hit by slot rects
         int sf = BkMiniStripPress(mx, my);
         if(sf != REFRESH_NONE) RefreshDisplay(sf);
         return;
      }

      int it,r;
      // open select-dropdown owns the next press (option = apply, outside = close)
      if(g_PnlDdItem>=0)
      {
         int df=PnlDdHit(mx,my);
         if(df!=-1)
         {
            UIPressAct("dd");   // P-UI-74
            if(df!=REFRESH_NONE) RefreshDisplay(df); else ChartRedraw();
            return;
         }
         // closed by an outside press — fall through so the press still acts
      }
      // closed select button → open its popover (the release click is swallowed)
      if(PnlDdAnchorHit(mx,my,it,r))
      {
         PnlDdOpen(it,r);
         UIPressAct("anch");   // P-UI-74
         return;
      }
      // P-UI-76: ONE slider gesture — the knob and the track are different shapes
      // of the SAME press, so they are claimed by ONE branch. The knob branch used
      // to arm the drag and apply NOTHING ("press position == knob position"), and
      // its grab zone is 12 px WIDER than the drawn knob on each side — so a click
      // 1-12 px off the white circle armed a drag that a motionless press never
      // fulfilled, and it read as «اینا کار نمیکنه». A press anywhere on a slider
      // now JUMPS the value to the cursor (standard slider behaviour, and the very
      // first pass the drag would have applied) and the drag continues from there.
      if(PnlKnobHit(mx,my,it,r) || PnlTrackHit(mx,my,it,r))
      {
         g_PnlDragItem=it; g_PnlDragRow=r;
         DragClaim(DRAG_PANEL_KNOB);
         UIDragBudgetBegin();   // P-UI-33: the jump is the gesture's first pass
         CircLockChart();
         double v;
         PnlValueFromX(it,r,mx,v);
         int flags0=PnlApply(it,r,v);
         PnlSetVisualValue(it,r,v);
         UIPressAct("slider");   // P-UI-74: the jump IS the gesture's action
         if(flags0!=REFRESH_NONE) RefreshDisplay(flags0);
         return;
      }
      // ══════════════════════════════════════════════════════════════════
      // P-UI-89 (2026-09-14) — THE CARD IS A HANDLE FROM EVERY PIXEL.
      //
      // «هنوز درگ نمیشه پنل تنظیمات هر ایتم» — the seventh report in the same
      // family, and this time the LIVE LEDGER said which pixels: of every drag
      // the user got all day, the arms that ended `moved=1` are all in the 56 px
      // HEADER; every arm inside the rows either died as a tap or was refused as
      // `(C)` on a control's own pixel. P-UI-70a made the body a handle, P-UI-88
      // softened the RELEASE-channel family — but a switch, a colour cell, the
      // colour strip, a band and the header cap still HARD-refused the press, so
      // a press on them could only do their own job. That is the whole remaining
      // gap between the card and the yardstick the user names («مثل منوی اصلی»).
      //
      // The menu's contract, applied to a card full of controls: THE PRESS ARMS
      // THE GESTURE, THE FIRST MOVEMENT PAST THE PROOF DECIDES WHO OWNS IT. A
      // tap stays the control's — its action fires on the press exactly as
      // before and a sub-threshold press moves nothing, pins nothing and eats
      // nothing (P-UI-80) — while a press that travels moves the CARD. ONE arm
      // site (never two): the widgets whose press IS their own pointer gesture
      // (the X/Done pair above, an open popover, its anchor, the slider) are
      // consulted BEFORE it, and the tap family below is consulted AFTER it and
      // still acts — which is what makes its pixels draggable without making it
      // unreachable (P-UI-70's position rule, now split by WHO OWNS THE MOVE).
      // P-UI-74: never on the click channel — a released button must not start a
      // move gesture.
      // P-UI-127 (2026-09-25) — THE CARD IS A HANDLE AGAIN (user order:
      // «پنل رو هم بشه درگ کرد»). PANELDRAG-OFF retired this one line on
      // 2026-09-14 for its PRICE, not its behaviour: it made every press of a
      // card a move candidate and paid the 12-family claim sweep to do it
      // (measured then: `[W][PERF] mouse move breakdown: panel=78ms`). The price
      // is paid once, in `PnlTryGrabMove`: the sweep became two compares and the
      // proof is raised by the control that acts (P-UI-127, UIPressAct). What
      // the arm may NOT do is steal a press an open dropdown owns (P-UI-76) or
      // start a move on the CLICK channel (a released button, P-UI-74).
      // NOT restored with it: `PnlDragPoll` — measured 197 drags armed by the
      // event channel against 0 by the poll, so the per-tick probe stays out
      // (G-09: the cheaper of two equal paths ships).
       if(!s_PnlClickChannel && g_PnlDdItem < 0)
       {
          if(g_PalOpen && PalTitleGrab(mx,my)) return;   // palette title carries first
          PnlTryGrabMove(mx,my,false);
       }
      // P-UI-128: THE BAKED FACES. The footer pair and the NAV pills sit UNDER
      // their own bitmap and the terminal sends them no click, so their action
      // lives here — AFTER the arm, so a drag on a pill still moves the card and
      // a tap still opens it (P-UI-89's split by WHO OWNS THE MOVE).
      if(PnlSkinButtonAct(mx,my)) return;
      if(PnlSwitchHit(mx,my,it,r))
      {
         double v=(PnlCurrent(it,r)>0.5)?0.0:1.0;
         int flags=PnlApply(it,r,v);
         PnlUpdateRow(it,r);
         UIPressAct("sw");   // P-UI-74: one flip, and the release stays spent
         if(flags!=REFRESH_NONE) RefreshDisplay(flags);
         return;
      }
      // colour-set cell → open the palette bound to THAT cell's target
      int csi,csr,css;
      if(PnlCsetHit(mx,my,csi,csr,css))
      {
         int ck=PnlColorKindSet(csi,css);
         if(ck>=0) PalOpenKind(csi,ck);
         UIPressAct("cset");   // P-UI-74
         return;
      }
      // dual cell → flip that member (ALL cell flips the whole group)
      int dui,dur,duc;
      if(PnlDualHit(mx,my,dui,dur,duc))
      {
         int dn=PnlRowMembers(dui,dur);
         int flags=REFRESH_NONE;
         bool grouped=false;   // P-UI-66: the ALL cell owns more than this row
         if(duc<dn)
         {
            int sr=PnlMemberRow(dui,dur,duc);
            double v=(PnlCurrentSet(dui,sr)>0.5)?0.0:1.0;
            flags=PnlApplySet(dui,sr,v);
         }
         else
         {
            // P-UI-66: the synthetic ALL cell owns the whole GROUP (the band's
            // members), not this row's members. On card 11 the row is `L5 | ALL`
            // with one member, so this used to re-write L5 and nothing else - the
            // design's "ALL" master switch did not exist.
            int af=0, ac=0;
            PnlAllCellSpan(dui,dur,af,ac);
            bool all=true;
            for(int dq=0;dq<ac;dq++)
               all=all && (PnlCurrentSet(dui,af+dq)>0.5);
            double v=all?0.0:1.0;
            grouped=(ac>dn);
            // One press = ONE recolour walk + ONE repaint (P-PERF-32's contract,
            // kept for a press that writes five switches instead of one).
            if(grouped) StructureSwitchBatchBegin();
            for(int dq2=0;dq2<ac;dq2++)
               flags|=PnlApplySet(dui,af+dq2,v);
            if(grouped) StructureSwitchBatchEnd();
         }
         // A group press moves switches that live on OTHER rows of the card, so
         // every row that renders one of them repaints - never just this row
         // (the face of a stale switch is a control that disagrees with the chart).
         if(grouped)
         {
            int rn=PnlRowsCount(dui);
            for(int gr=0;gr<rn;gr++)
               if(PnlRowKind(dui,gr) == PNL_K_DUAL) PnlUpdateRow(dui,gr);
         }
         else PnlUpdateRow(dui,dur);
         UIPressAct("dual");   // P-UI-74
         if(flags!=REFRESH_NONE) RefreshDisplay(flags);
         return;
      }
      // "+" quick-add cell → open the full picker for the row's target
      int qai,qar;
      if(PnlColorAddHit(mx,my,qai,qar))
      {
         PalOpen(qai,qar);
         UIPressAct("add");   // P-UI-74
         return;
      }
      // P-UI-87: the colour strip itself — the preview block and the eight
      // quick swatches. These are the pixels the grab used to refuse as `(C)`
      // while NOTHING owned the action, because their cells are covered by the
      // strip's own glass skins, for which MT4 fires no OBJECT_CLICK at all.
      // P-UI-127: the sweep that said `(C)` is gone, so they claim the press
      // softly here — like every other control that has a coordinate action.
      int qsi,qsr,qsq;
      if(PnlQuickSwatchHit(mx,my,qsi,qsr,qsq))
      {
         int qf = REFRESH_NONE;
         if(qsq < 0) PalOpen(qsi,qsr);                    // the preview → the picker
         else        qf = PnlQuickSwatchApply(qsi,qsr,qsq);
         UIPressAct("strip");   // P-UI-74: one gesture, one owner (both channels)
         if(qf != REFRESH_NONE) RefreshDisplay(qf);
         return;
      }
      // section band → collapse/expand (preview .acc intent); the card
      // rebuilds shorter/taller in place
      int bi,br;
      if(PnlBandHit(mx,my,bi,br))
      {
         int bb=PnlBandIndex(bi,br);
         if(bb>=0)
         {
            PnlToggleBand(bi,bb);
            PnlRebuildKeepSpot(bi);
            UIPressAct("band");   // P-UI-74
         }
         return;
      }
      // R-KEYCAP: the header's .key cap is the card's OWN master switch — the
      // same value its hotkey and the ring item write, applied through the row's
      // own owner. It MUST sit before the grab below (P-UI-70's position rule):
      // the cap lives inside the drag handle, so a press it does not claim drags
      // the card out from under the cursor instead of flipping anything.
      int kci = 0;
      if(PnlKeycapHit(mx,my,kci))
      {
         int kf = PnlKeycapAct(kci);
         UIPressAct("key");   // P-UI-74: one gesture, one owner (both channels)
         if(kf != REFRESH_NONE) RefreshDisplay(kf);
         return;
      }
      // The press landed on NO control of this card: the arm above is its whole
      // answer (the header, the card body and the pixels BETWEEN the controls all
      // grab there, P-UI-70a/P-UI-89), and the whole panel then follows the
      // cursor anywhere on the chart. There is deliberately NO second grab call
      // here: one arm site per press is what keeps the ledger at one line per
      // gesture and the claim at one owner.
      return;
   }

   if(!leftDown)
   {
      g_PnlDragItem=-1; g_PnlDragRow=-1;
      DragReleaseIf(DRAG_PANEL_KNOB);
      UIDragBudgetEnd();   // P-UI-33: release settles the tail exactly once
      UISuppressNextClick();   // release click must not be treated as a dismiss click
      CircUnlockChart();
      return;
   }

   // throttle UI work to ~every 30ms
   static uint s_LastMoveTick=0;
   uint now=GetTickCount();
   if(now - s_LastMoveTick < 30) return;
   s_LastMoveTick=now;
   CircReassertLock();   // LEARNING §5: the slider owns the view until release

   double v;
   PnlValueFromX(g_PnlDragItem,g_PnlDragRow,mx,v);
   int flags=PnlApply(g_PnlDragItem,g_PnlDragRow,v);
   PnlSetVisualValue(g_PnlDragItem,g_PnlDragRow,v);
   if(flags != REFRESH_NONE)
      RefreshDisplay(flags);
}

//+------------------------------------------------------------------+
//| P-UI-74 — the CLICK channel for the card's own controls.          |
//|                                                                   |
//| A card control that lives on the coordinate press chain only is    |
//| reachable only while that channel works. This is the second         |
//| channel: the click's OWN pixels are dispatched through the SAME     |
//| owner (`PnlHandleMouseMove`, synthetic fresh press), so the          |
//| affordance list, its order and every arm stay single-owned and      |
//| cannot drift — and the latches make a double delivery harmless.     |
//+------------------------------------------------------------------+
bool PnlCardPointInside(const int mx,const int my)
{
   if(g_PnlOpen < 0 || g_PnlOpen == 13) return false;
   return (mx >= g_PnlX[g_PnlOpen] && mx <= g_PnlX[g_PnlOpen] + PnlPanelW(g_PnlOpen) &&
           my >= g_PnlY[g_PnlOpen] && my <= g_PnlY[g_PnlOpen] + PnlPanelH(g_PnlOpen));
}

//--- returns TRUE only when a CONTROL of the open card acted (the caller then
//--- owns the event and must not also route it by name).
bool PnlClickFallback(const int cx,const int cy)
{
   if(g_PnlOpen < 0 || g_PnlOpen == 13) return false;
   if(PnlGestureConsumed()) return false;        // its press already owned it
   if(g_PalMixDrag > 0) return false;            // the mixer drag owns the pointer
   // A click that lands ON the popover belongs to the popover — it floats above
   // the card, so the pixels are its, never the card row underneath.
   if(PnlPalettePointInside(cx,cy)) return false;
   if(g_PnlDragItem >= 0 || g_PnlMoveItem >= 0) return false;   // live gesture
   if(!PnlCardPointInside(cx, cy)) return false;
   s_PnlClickChannel = true;
   PnlHandleMouseMove(cx, cy, false, true);      // the SAME dispatch, same owner
   s_PnlClickChannel = false;
   if(!PnlGestureConsumed()) return false;       // nothing in the card acted
   // The press event of THIS gesture may still be in flight (MT4 hands the
   // indicator the click of the press that grabbed the object) — the press
   // chain consumes that echo instead of acting on it.
   s_PnlClickActed = !UILeftButtonUp();
   ChartRedraw();
   return true;
}

//+------------------------------------------------------------------+
//| Drag preview: knob + value follow cursor before throttled apply   |
//+------------------------------------------------------------------+
void PnlSetVisualValue(const int item,const int row,const double val)
{
   if(g_PnlOpen!=item) return;
   int kind=0;
   int minV=0,maxV=0; double step=1; string label="",unit="",opts="";
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   if(kind!=0) return;
   int trackX=PnlRowBaseX(item,row)+PNL_TRACK_X;
   int knobX=PnlSliderKnobX(item,row,val,minV,maxV);
   ObjectSetInteger(0,PnlName(item,row,"KB"),OBJPROP_XDISTANCE,knobX);
   ObjectSetInteger(0,PnlName(item,row,"TF"),OBJPROP_XSIZE,
                    MathMax(0,knobX+PNL_KNOB_W/2-(trackX+1)));
   ObjectSetString(0,PnlName(item,row,"V"),OBJPROP_TEXT,PnlFormat(item,row,val));
}

//+------------------------------------------------------------------+
//| Update row visuals after a value change                           |
//+------------------------------------------------------------------+
void PnlUpdateRow(const int item,const int row)
{
   if(g_PnlOpen!=item) return;
   if(item == 13) { BkMiniRefresh(); return; }   // TV strip — one whole-toolbar
                                                 // repaint, never row-level
   int px=PnlRowBaseX(item,row);
   int ry=g_PnlY[item]+PNL_HEAD_H+PnlRowLine(item,row)*PNL_ROW_H;
   int kind=0; string label="",unit="",opts="";
   int minV=0,maxV=0; double step=1;
   PnlRowDef(item,row,kind,label,minV,maxV,step,unit,opts);
   double val=PnlCurrent(item,row);

   if(kind==5) return;   // NAV rows are static buttons
   if(kind==6) return;   // TEXT edit field — content owned by the box, rebuilt on open
   if(kind==8)   // colour set: repaint every cell + move the selection ring
   {
      int m=PnlRowMembers(item,row);
      int total=m*PNL_CSET_W+(m-1)*PNL_CSET_GAP;
      int x0=px+(PNL_WEL-total)/2;
      for(int i=0;i<m;i++)
      {
         int sr=PnlMemberRow(item,row,i);
         int kk=PnlColorKindSet(item,sr);
         color cc=PnlCsetCellColor(kk);   // P-UI-68: clrNONE paints as the AUTO face
         string csn=PnlName(item,row,"CS"+IntegerToString(i));
         if(ObjectFind(0,csn)>=0)
         {
            ObjectSetInteger(0,csn,OBJPROP_BGCOLOR,cc);
            // P-UI-69: the legibility floor is re-asserted with the colour
            // (PnlCsetCellColor never returns clrNONE, so the old guard was
            // dead and the border stayed at its create-time value for ever).
            ObjectSetInteger(0,csn,OBJPROP_BORDER_COLOR,PnlSwatchBorder(cc,PNL_CLR_CARD));
         }
         string csk=PnlName(item,row,"CSK"+IntegerToString(i));
         bool sel=(g_PalOpen && kk>=0 && g_PalKind==kk);
         if(sel)
         {
            if(ObjectFind(0,csk)<0 && cc!=clrNONE)
            {
               int cx2=x0+i*(PNL_CSET_W+PNL_CSET_GAP);
               PnlSetRect(csk,cx2-2,ry+15,PNL_CSET_W+4,PNL_CSET_H+4,PNL_CLR_ACCENT);
            }
         }
         else ObjectDelete(0,csk);
      }
      return;
   }
   if(kind==9)   // dual: reswap every cell face (captions are static)
   {
      int dn=PnlRowMembers(item,row);
      int cells=PnlDualCells(item,row);
      for(int j=0;j<cells;j++)
      {
         bool on=false;
         if(j<dn) on=(PnlCurrentSet(item,PnlMemberRow(item,row,j))>0.5);
         else     on=PnlAllCellOn(item,row);   // P-UI-66: the group's own face
         string swn=PnlName(item,row,"SW"+IntegerToString(j));
         if(ObjectFind(0,swn)>=0)
         {
            string res=on ? PnlAccentRes(item,"pnl_dsw_on") : "::Files\\Icons\\pnl_dsw_off.bmp";
            ObjectSetString(0,swn,OBJPROP_BMPFILE,0,res);
            ObjectSetString(0,swn,OBJPROP_BMPFILE,1,res);
         }
      }
      return;
   }
   if(kind==4)   // color row: refresh preview swatch + quick-pick selection rings
   {
      color cur=PnlRowColor(item,row);
      // P-UI-131h: the LIVE refresh path painted `clrNONE` raw, i.e. MT4's ink-black —
      // the create path had the AUTO face (P-UI-68) but every update after a pick or a
      // Reset went through here and lost it.
      color curVis=(cur==clrNONE) ? PNL_CLR_AUTO_CELL : cur;
      string cb=PnlName(item,row,"CB");
      if(ObjectFind(0,cb)>=0)
      {
         ObjectSetInteger(0,cb,OBJPROP_BGCOLOR,curVis);
         // P-UI-69: the border follows the COLOUR, here as well as at create
         // time - a row switched to near-black must gain its outline the same
         // pixel it gains its fill, or the control reads empty until the card
         // is rebuilt (the create-only fix is the P-UI-66 shape).
         ObjectSetInteger(0,cb,OBJPROP_BORDER_COLOR,PnlSwatchBorder(curVis,PNL_CLR_CARD));
      }
      for(int qi=0; qi<PNL_QSW_N; qi++)
      {
         string qn=PnlName(item,row,"Q"+IntegerToString(qi));
         if(ObjectFind(0,qn)>=0)
         {
            color qc=QuickPalColor(qi);
            ObjectSetInteger(0,qn,OBJPROP_BORDER_COLOR,
                             (qc==cur) ? PNL_CLR_ACCENT : PnlSwatchBorder(qc,PNL_CLR_CARD));
         }
      }
      return;
   }
    if(kind==1)   // pill switch — reswap the face + chip, grow/prune rail+wash
    {
       bool on=(val>0.5);
       int acc=PnlCardAccent(item);
       string sw=PnlName(item,row,"SW");
       if(ObjectFind(0,sw)>=0)
       {
          string res=on ? PnlAccentRes(item,"pnl_sw_on") : "::Files\\Icons\\pnl_sw_off.bmp";
          ObjectSetString(0,sw,OBJPROP_BMPFILE,0,res);
          ObjectSetString(0,sw,OBJPROP_BMPFILE,1,res);
       }
       string act=PnlName(item,row,"ACT"), rail=PnlName(item,row,"RAIL");
       if(on)
       {
          if(ObjectFind(0,act)<0 || ObjectFind(0,rail)<0)
             PnlPaintActive(item,row,px,ry,true);
       }
       else
       {
          ObjectDelete(0,act);
          ObjectDelete(0,rail);
       }
       string chp=PnlName(item,row,"CHP"), gl=PnlName(item,row,"GL");
       string ico=PnlRowIcon(item,row);
       if(ObjectFind(0,chp)>=0)
       {
          string cres=on ? PnlAccentRes(item,"pnl_chip") : "::Files\\Icons\\pnl_chip.bmp";
          ObjectSetString(0,chp,OBJPROP_BMPFILE,0,cres);
          ObjectSetString(0,chp,OBJPROP_BMPFILE,1,cres);
       }
       if(ico!="" && ObjectFind(0,gl)>=0)
       {
          string gres=PnlGlyphRes(item,ico,on);
          ObjectSetString(0,gl,OBJPROP_BMPFILE,0,gres);
          ObjectSetString(0,gl,OBJPROP_BMPFILE,1,gres);
       }
       return;
    }
   else if(kind==2)   // tabs / dropdown select / segmented pills
   {
      string arr[];
      int n=PnlSplit(opts, arr, 12);
      if(IsTabRow(item,row))   // underline follows the active tab
      {
         // SAME content-sized walk as the create path above (tx starts px+12,
         // tw=12+6/char+20 with icon, 2px gaps) — equal slices drift the line.
         string ic2=PnlRowExt(item,row);
         string iarr2[];
         int nic2=(ic2=="")?0:PnlSplit(ic2,iarr2,8);
          int tx2=px+12;
          if(PnlIsWide(item))   // WIDE: same centred walk as the create path
          {
             int tot2=0;
             for(int ti=0;ti<n;ti++) tot2 += 12+PnlTextW(arr[ti],PNL_PT_CTL)+((ti<nic2)?20:0)+2;   // P-UI-30
             tot2 -= 2;
             tx2 = px + (PnlCardW(item)-tot2)/2;
          }
         for(int i=0;i<n;i++)
         {
            int tw2=12+PnlTextW(arr[i],PNL_PT_CTL)+((i<nic2)?20:0);   // P-UI-30
            string seg=PnlName(item,row,"C"+IntegerToString(i));
            if(ObjectFind(0,seg)<0) { tx2+=tw2+2; continue; }
            bool isAct=PnlSegOn(item,row,i,val);
            ObjectSetInteger(0,seg,OBJPROP_COLOR, isAct ? PNL_CLR_ACCENT : PNL_CLR_SEG_TX);
            ObjectSetString(0,seg,OBJPROP_FONT, BioChromeFont(isAct));
            string cii=PnlName(item,row,"CI"+IntegerToString(i));
            if(i<nic2 && ObjectFind(0,cii)>=0)
            {
               string ires=PnlGlyphRes(item,iarr2[i],isAct);
               ObjectSetString(0,cii,OBJPROP_BMPFILE,0,ires);
               ObjectSetString(0,cii,OBJPROP_BMPFILE,1,ires);
            }
            string cti=PnlName(item,row,"CT"+IntegerToString(i));
            if(ObjectFind(0,cti)>=0)
            {
               ObjectSetInteger(0,cti,OBJPROP_COLOR, isAct ? PNL_CLR_TITLE : PNL_CLR_SEG_TX);
               ObjectSetString(0,cti,OBJPROP_FONT, BioChromeFont(isAct));
            }
            if(isAct)
            {
               string tu=PnlName(item,row,"TU");
               if(ObjectFind(0,tu)>=0)
               {
                  ObjectSetInteger(0,tu,OBJPROP_XDISTANCE,tx2+7);
                  ObjectSetInteger(0,tu,OBJPROP_XSIZE,tw2-14);
               }
            }
            tx2+=tw2+2;
         }
      }
      else if(IsDdRow(item,row))   // select button shows the live option
      {
         // P-UI-26: the box is content-fitted at create (dw=50+6/char); a
         // longer/shorter option must resize it live, or text runs under
         // the chevron while the hit-rect (PnlDdRect, always fresh) moves on.
         int dw = 50 + PnlTextW(PnlDdOptText(item,row),PNL_PT_CTL);   // P-UI-30
         if(dw < 72) dw = 72;
         int dx = px + PNL_WEL - PNL_PAD_X - dw;
         string dd=PnlName(item,row,"DD");
         if(ObjectFind(0,dd)>=0)
         {
            ObjectSetInteger(0,dd,OBJPROP_XDISTANCE,dx);
            ObjectSetInteger(0,dd,OBJPROP_XSIZE,dw);
         }
         string ddi=PnlName(item,row,"DDI");
         if(ObjectFind(0,ddi)>=0) ObjectSetInteger(0,ddi,OBJPROP_XDISTANCE,dx+7);
         string dt=PnlName(item,row,"DDT");
         if(ObjectFind(0,dt)>=0)
         {
            ObjectSetInteger(0,dt,OBJPROP_XDISTANCE,dx+24);
            ObjectSetString(0,dt,OBJPROP_TEXT,PnlDdOptText(item,row));
         }
         string ddc=PnlName(item,row,"DDC");
         if(ObjectFind(0,ddc)>=0) ObjectSetInteger(0,ddc,OBJPROP_XDISTANCE,dx+dw-13);
      }
      else   // segmented pills: restyle every segment
      {
         int gap=4;
         int segW=(PNL_WEL-2*PNL_PAD_X-(n-1)*gap)/n;
         for(int i=0;i<n;i++)
         {
            string seg=PnlName(item,row,"C"+IntegerToString(i));
            if(ObjectFind(0,seg)<0) continue;
            bool isAct=PnlSegOn(item,row,i,val);
            ObjectSetInteger(0,seg,OBJPROP_BGCOLOR, isAct ? PNL_CLR_SEG_ON : PNL_CLR_SEG_OFF);
            ObjectSetInteger(0,seg,OBJPROP_BORDER_COLOR, isAct ? PNL_CLR_SEG_ON : PNL_CLR_SEG_BD);
            ObjectSetInteger(0,seg,OBJPROP_COLOR, isAct ? PNL_CLR_ACCENT_TX : PNL_CLR_SEG_TX);
         }
      }
   }
   else   // slider
   {
      int trackX=px+PNL_TRACK_X;
      int knobX=PnlSliderKnobX(item,row,val,minV,maxV);
      string kb=PnlName(item,row,"KB");
      if(ObjectFind(0,kb)>=0) ObjectSetInteger(0,kb,OBJPROP_XDISTANCE,knobX);
      string tf=PnlName(item,row,"TF");
      if(ObjectFind(0,tf)>=0)
         ObjectSetInteger(0,tf,OBJPROP_XSIZE,
                          MathMax(0,knobX+PNL_KNOB_W/2-(trackX+1)));
      string v=PnlName(item,row,"V");
      if(ObjectFind(0,v)>=0) ObjectSetString(0,v,OBJPROP_TEXT,PnlFormat(item,row,val));
   }
}

//+------------------------------------------------------------------+
//| Click handler — header buttons, steppers, toggles, segments, track|
//+------------------------------------------------------------------+
int PnlHandleClick(const string name,const int mouseX,const int mouseY)
{
   // P-UI-91: DRAIN THE OTHER TEXT FIELD BEFORE THE CLICK IS ROUTED ANYWHERE.
   //
   // Card 12's commit used to sit BELOW the `palFlags` early return on the next
   // block, so a click on a palette control skipped it and left g_BkTextFocus
   // latched - the same "hotkeys are dead until you close the surface" symptom as
   // the palette's hex field, reached from the other direction. Hoisting it here
   // gives both fields the one click-away rule, in the one place that can see it.
   int feI, feR; string feK;
   ParsePnlName(name, feI, feR, feK);
   const bool clickIsBkEdit = (feI == 12 && feK == "ED");
   if(g_BkTextFocus && !clickIsBkEdit) BkFlushTextEdit();

   // Palette popup first (it sits above any open panel). Swatch/mixer/hex
   // clicks are consumed; panel clicks still pass through so the user can
   // tweak other rows while the palette stays open.
   int palFlags=PalHandleClick(name);
   if(palFlags!=REFRESH_NONE) return palFlags;
   // TEXT edit focus (card 12 Text tab): the ED field owns the keyboard
   // (letter-hotkey guard in EventHandlers); clicking the field sets the focus.
   if(clickIsBkEdit) { g_BkTextFocus = true; return REFRESH_NONE; }
   // footer mini-opacity track (click-to-set; geometry mirrors PalDraw)
   if(g_PalOpen)
   {
      string pfx=g_UI.btnPrefix+"Pal_";
      if(name==pfx+"opg" || name==pfx+"opf")
      {
         if(PaletteKindTransparency(g_PalKind)>=0)
         {
             int otx=PalTrX();
             int pct=(int)MathRound((mouseX-otx)/(double)PalTrW()*100.0);

            int flags=PaletteApplyTransparency(g_PalKind,ClampInt(pct,0,100));
            PalUpdateLive();
            return flags;
         }
         return REFRESH_NONE;
      }
   }
   if(g_PalOpen && StringFind(name, g_UI.btnPrefix+"Pal_") == 0) return REFRESH_NONE;
   // P-UI-74: the click's coordinates get first refusal on the card's OWN
   // controls (switch pill / cset cell / "+" chip / band / dropdown / X+Done).
   // When one of them acts, the event is spent and the name router is skipped;
   // when none of them answers (nav, segments, the colour preview, the quick
   // swatches) this returns FALSE and the name router runs exactly as before.
   if(PnlClickFallback(mouseX, mouseY)) return REFRESH_NONE;

   for(int i = 0; i < PNL_COUNT; i++)   // every settings card
   {
      if(name == PnlHead(i, "close") || name == PnlHead(i, "done"))
      {
         PnlCloseAll();
         return REFRESH_NONE;
      }
      if(name == PnlHead(i, "rst"))
         return PnlResetItem(i);
      if(name == PnlHead(i, "pal"))
      {
         PalOpenForItem(i);
         return REFRESH_NONE;
      }
   }

   int item,row; string kind;
   ParsePnlName(name,item,row,kind);
   if(item<0) return REFRESH_NONE;
   if(g_PnlOpen!=item) return REFRESH_NONE;
   if(row<0) return REFRESH_NONE;

   int rkind=0; string label="",unit="",opts="";
   int minV=0,maxV=0; double step=1;
   PnlRowDef(item,row,rkind,label,minV,maxV,step,unit,opts);

   // ── Color preview / PICK → open the palette popup bound to this row ──
   if(kind=="CB" || kind=="PK")
   {
      if(rkind!=4) return REFRESH_NONE;
      PalOpen(item,row);
      return REFRESH_NONE;
   }

   // ── Quick swatch "Q0".."Q5" → apply instantly, chart updates live ──
   // "Q0".."Q7" EXACTLY (P-UI-69). The old prefix test accepted ANY two-char id
   // starting with 'Q' - including the "+" chip ("QA"), which
   // StringToInteger() then read as 0, so a click on the add chip would have
   // silently applied the FIRST swatch while the tooltip promised the picker.
   if(StringLen(kind)==2 && StringGetCharacter(kind,0)=='Q' &&
      StringGetCharacter(kind,1)>='0' && StringGetCharacter(kind,1)<='9')
   {
      if(rkind!=4) return REFRESH_NONE;
      int qi=(int)StringToInteger(StringSubstr(kind,1));
      if(qi<0 || qi>=PNL_QSW_N) return REFRESH_NONE;
      // P-UI-87: ONE owner — the coordinate chain's own quick-swatch branch
      // calls this very function, so the two channels cannot apply twice
      // (`UIPressAct` latches the gesture) nor apply different colours.
      return PnlQuickSwatchApply(item,row,qi);
   }

   // ── NAV row → open the target card (STRUCTURE sub-card / BACK) ──
   // ── DEL action → delete the mini strip's held box, then close ──
   if(kind=="NAV")
   {
      if(rkind!=5) return REFRESH_NONE;
      if(opts=="DEL")   // mini ACTION: delete the held box, then close (inlined:
      {                 // BkMiniDeleteBox would sit after PnlCloseAll's callers)
         if(g_BkMiniBox != "" && BaseKnotFind(g_BkMiniBox) >= 0) BaseKnotDelete(g_BkMiniBox);
         g_BkMiniBox = "";
         PnlCloseAll();
         return REFRESH_NONE;
      }
      int tgt=(int)StringToInteger(opts);
      if(tgt>=0 && tgt<PNL_COUNT && tgt!=item) PnlOpen(tgt);
      return REFRESH_NONE;
   }

   // ── Stepper − / + ──
   if(kind=="MNS" || kind=="PLS")
   {
      if(rkind!=0) return REFRESH_NONE;
      double dir=(kind=="PLS") ? 1.0 : -1.0;
      double v=PnlCurrent(item,row)+dir*step;
      if(v<minV) v=minV;
      if(v>maxV) v=maxV;
      int flags=PnlApply(item,row,v);
      PnlUpdateRow(item,row);
      return flags;
   }

   // ── Segmented selector: "C0","C1",... → select directly ──
   // (slider track/knob, toggle and dropdown presses are coordinate-based in
   //  PnlHandleMouseMove — invisible OBJ_BUTTON hit-areas are gone)
   if(StringLen(kind)>1 && StringGetCharacter(kind,0)=='C')
   {
      if(rkind!=2) return REFRESH_NONE;
      int seg=(int)StringToInteger(StringSubstr(kind,1));
      return PnlApplyOption(item,row,seg);
   }

   return REFRESH_NONE;
}

//+------------------------------------------------------------------+
//| Drag handler for slider knobs                                    |
//+------------------------------------------------------------------+
int PnlHandleDrag(const string name,const int mouseX)
{
   int item,row; string kind;
   ParsePnlName(name,item,row,kind);
   if(item<0 || row<0 || kind!="K") return REFRESH_NONE;

   // P-UI-33: a NATIVE knob drag is a gesture like the pointer drags — its heavy
   // passes obey the same budget (armed here; ChartPointerFinalizeOnUps ends it
   // on the button-up that closes the drag). Without this a non-RECALC drag
   // (its own 250ms gate only covers RECALC) ran the full pass per event.
   UIDragBudgetBegin();

   int rkind=0; string label="",unit="",opts="";
   int minV=0,maxV=0; double step=1;
   PnlRowDef(item,row,rkind,label,minV,maxV,step,unit,opts);
   if(rkind!=0) return REFRESH_NONE;

   double frac=(mouseX-(PnlRowBaseX(item,row)+PNL_TRACK_X)) / (double)(PNL_TRACK_W-PNL_KNOB_W);
   frac=MathMax(0.0,MathMin(1.0,frac));
   double v=minV + frac*(maxV-minV);
   v=MathRound(v/step)*step;
   if(v<minV) v=minV;
   if(v>maxV) v=maxV;

   int flags=PnlApply(item,row,v);
   PnlSetVisualValue(item,row,v);
   if((flags & REFRESH_RECALC) != 0)
   {
      static uint s_LastDragTick=0;
      uint now=GetTickCount();
      if(now - s_LastDragTick < 250)
         return REFRESH_NONE;
      s_LastDragTick=now;
   }
   return flags;
}

//+------------------------------------------------------------------+
//| UI chart-event bridge                                            |
//| Called from the indicator's OnChartEvent AFTER the base handler. |
//| Feeds the circular menu + settings panels from chart events.     |
//| MOUSE_MOVE: sparam bit 0 = left mouse button state (MQL4).       |
//+------------------------------------------------------------------+
// (P-UI-100: `g_LastUIX`/`g_LastUIY` are declared ABOVE `ChartPointerFinalizeOnUps`
//  — the first reader in the translation unit — so this bridge and the finalizer
//  read the same pair. Do not re-declare them here.)

//--- hold-on-box → Base Box MINI (TradingView-like floating icon strip):
//--- press on a committed BK box, hold still ≥500ms → PnlOpen(13) fires WHILE
//--- HELD, like the menu long-press. The strip = [color chip][STYLE][WIDTH]
//--- [LOCK][✕ delete][••• full card 12][✓ close] — drawn by
//--- BkMiniStripCreate (R-BKSTRIP 2026-09-07). SINGLE METHOD (2026-09-06): it
//--- opens only mid-hold — never on release, never via Shift+click. Passive
//--- observer (same 500ms/8px language): never consumes, never claims drags.
//--- A quick tap does nothing (native select only).
//--- STATE DISCIPLINE: press DOWN-transitions latch (event rising edge, or
//--- the KEYSTATE poll backup for zero-move presses); ANY button-up clears
//--- everything and opens nothing. KEYSTATE is consulted ONLY to detect a
//--- down-transition when nothing is latched — never to clear or re-time an
//--- existing latch (a flaky up-reading mid-hold used to restart the timer
//--- forever, so the card only ever appeared on release — P-BK-05).
static string s_BkHoldId = "";   // box under the latched press ("" = none/dragged-off)
static uint   s_BkHoldMs = 0;    // press-down moment (0 = no press latched)
static int    s_BkHoldX = 0, s_BkHoldY = 0;   // press-down cursor
static bool   s_BkDownNow = false;            // button seen down since last up-event
// The button-up ending the OPENING hold belongs to the open gesture — never
// a dismissal click, not a drag-release, never consumed twice (cleared on
// every CLICK + on every new press).
static bool   s_BkFireReleasePending = false;
#define BK_HOLD_MS   500   // one hold language with the menu (P-UI-14): 250ms fired on press-pause-drags
#define BK_HOLD_MOVE 8
#define BK_CLICK_SLOP 10   // button-up farther than this from its press-down is a
                           // drag end, never a dismissal click (hold slop is 8)
#define BK_LATCH_TTL 30000   // stale-press safety (capture loss etc.)
// ══════════════════════════════════════════════════════════════════════════
// P-UI-101 (2026-09-22) — THE CUSTOM PRICE LINE'S OWN HOLD.
//
// User order: «روی خط کاستوم پرایس که هولد کردم پنل تنظیماتش بازه بشه و بشه از
// اونجا قفلش کرد مثل مینی تولبار گره ها». It is the BOXES' own language, worn by
// the second object that has settings: a 500 ms still press on the line opens its
// card (the Custom Price card, item 8), whose first row is the LOCK.
//
// WHY IT CAN COEXIST WITH THE DRAG. The press on the line already claims the drag
// (P-UI-99: the claim is immediate), but a claim only ever MOVES the line after
// real travel (`CP_DRAG_SLOP`), so a still press moves nothing. The hold is
// therefore a second reading of the same press: it latches on the press edge,
// stands down the moment the cursor travels past the hold slop (that gesture is a
// drag, and the drag owns it), and fires while the button is still down.
//
// The release that ends a fired hold must NOT also be read as a click on the line
// (a single click SETS it, a double re-arms it): `CpHoldFire` clears the click
// contract's own state in the same breath, which is the one-shot release guard
// the box strip uses (`s_BkFireReleasePending`) in the shape this gesture needs.
//
// The hit test is the DRAG's own (`CustomPriceGrabAt`, the drawn tolerance) and
// deliberately does NOT ask the armed state: a SET or LOCKED line must still be
// reachable by the hold — that is how it is ever unlocked again.
// ══════════════════════════════════════════════════════════════════════════
#define CP_HOLD_UI_MS  500     // one hold language with the ring and the boxes
#define CP_HOLD_MOVE   8       // travel past this = a drag, never a hold
static uint s_CpHoldMs     = 0;
static int  s_CpHoldX      = 0;
static int  s_CpHoldY      = 0;
static bool s_CpDownNow    = false;   // a press is tracked (zero-move backup)
static bool s_CpHoldOnLine = false;   // THIS press landed on the line

void CpHoldClear() { s_CpHoldMs = 0; s_CpHoldOnLine = false; }

void CpHoldLatch(const int mx, const int my)
{
   s_CpDownNow = true;
   s_CpHoldMs = GetTickCount();
   s_CpHoldX = mx; s_CpHoldY = my;
   s_CpHoldOnLine = false;
   if(!g_customPriceLineCreated) return;
   if(g_PnlOpen == 8 && PnlPointInside(mx, my)) return;   // a press inside the open card is the card's
   if(UIPointerOverSurface(mx, my)) return;               // a panel owns its own presses
   s_CpHoldOnLine = CustomPriceGrabAt(mx, my);            // the drag's own tolerance
}

void CpHoldFire()
{
   s_CpHoldMs = 0;
   s_CpHoldOnLine = false;
   if(!g_customPriceLineCreated) return;
   // the press that opened the card is not a click on the line — see the note above
   g_cpClickArmed = false;
   g_cpClickY = 0;
   g_cpSetPending = "";
   g_cpSetPendingMs = 0;
   if(g_PnlOpen == 8) { PnlCloseAll(); return; }   // the same hold closes what it opened
   PnlOpen(8);
   ChartRedraw();
}

void CpHoldOnMove(const int mx, const int my, const bool leftDown, const bool pressStart)
{
   if(pressStart) { CpHoldLatch(mx, my); return; }
   if(!leftDown) { CpHoldClear(); return; }               // release — opens NOTHING
   if(s_CpHoldMs == 0 || !s_CpHoldOnLine) return;
   if(MathAbs(mx - s_CpHoldX) > CP_HOLD_MOVE || MathAbs(my - s_CpHoldY) > CP_HOLD_MOVE)
   { s_CpHoldOnLine = false; return; }                    // it is a drag, not a hold
   if(GetTickCount() - s_CpHoldMs >= CP_HOLD_UI_MS) CpHoldFire();
}

//--- the polled half, for a press with ZERO movement (no MOUSE_MOVE is emitted):
//--- the box hold's own P-BK-03 lesson, same shape, same 250 ms + tick cadence.
void CpHoldPoll()
{
   if(s_CpHoldMs == 0 && !s_CpDownNow && g_customPriceLineCreated && UILeftButtonDown())
      CpHoldLatch(g_LastUIX, g_LastUIY);
   if(s_CpHoldMs == 0)
   {
      if(s_CpDownNow && UILeftButtonUp()) s_CpDownNow = false;
      return;
   }
   if(!s_CpDownNow) { CpHoldClear(); return; }
   if(GetTickCount() - s_CpHoldMs < CP_HOLD_UI_MS) return;
   if(MathAbs(g_LastUIX - s_CpHoldX) > CP_HOLD_MOVE || MathAbs(g_LastUIY - s_CpHoldY) > CP_HOLD_MOVE)
   { s_CpHoldOnLine = false; return; }
   if(!s_CpHoldOnLine) return;
   CpHoldFire();
}

// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-06 (2026-09-22) — THE DRAWINGS' OWN HOLD: THE LEAST-SPACE TOOLBAR.
// RETIRED — see DRHOLD-OFF below (right-click is the trigger since 2026-09-23).
// History kept: the paragraphs below are why the hold existed first.
//
// «ابزار تولبار باید با کمترین فضا بهترین نتیجه رو بده» — taken literally, the
// least space a toolbar can occupy is NONE, and the presets (P-DRAW-02) are what
// make that possible: the looks are already saved, so the only thing the gesture
// has to say is WHICH one. A 500 ms still press on any drawing the user made
// applies that kind's NEXT preset and remembers it as the kind's look, so the
// next drawing of the same tool wears it too (P-DRAW-01c).
//
// WHY THIS IS THE RIGHT FIRST SURFACE, AND NOT A PLACEHOLDER. It costs no panel,
// no bitmap, no z-order rung and no per-move work: the hit test is the memoised
// one (`DrawObjectAtCached`: ONE walk per press, P-DRAW-04), the apply touches
// the one held object, and the steady state is a single bool read in the mouse
// stream the panels already walk. A visual strip can be laid over this later
// without changing any of it — the gesture, the target and the presets are the
// parts that had to exist first.
//
// It also obeys the two laws this project paid for: the indicator's OWN objects
// are never touched (the classifier's prefix test), and a press that lands on a
// panel, a card or our own strip is never claimed (the same guards the box hold
// uses).
// ══════════════════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════════════════
// P-DRAW-06 — RETIRED (DRHOLD-OFF, 2026-09-23). User order: «به جای هولد راست
// کلیک باشه» — right-click is the strip's trigger now (P-DRAW-12/13/14), the
// 500 ms hold no longer opens anything. Deleted owners: DRAW_HOLD_UI_MS,
// DRAW_HOLD_MOVE, s_DrHoldMs/X/Y/DownNow/Name, s_DrCycle, DrHoldClear/Latch/
// Fire/OnMove/Poll + the two call sites below. Restore = git (this deletion),
// not a rewrite. The box hold (BkHold*) and the custom-price hold (CpHold*)
// are separate gestures and stay.
// ══════════════════════════════════════════════════════════════════════════

void BkHoldLatch(const int mx, const int my)   // (re)start press tracking
{
   s_BkDownNow = true;
   s_BkHoldMs = GetTickCount(); s_BkHoldX = mx; s_BkHoldY = my;
   s_BkHoldId = "";
   // A new press means any previous gesture ended (its release was missed) —
   // the stale fire-release flag must not swallow a future dismissal click.
   s_BkFireReleasePending = false;
   if(BaseKnotSessionActive() || g_PalOpen) return;
   // Presses on the open strip / its dropdown / any panel must never arm a
   // box hold (the strip often floats ABOVE its own box — without this the
   // hold would refire mid-read and rebuild the strip under the cursor).
   if(g_PnlOpen == 13 && BkMiniStripPointInside(mx, my)) return;
   if(PnlPointInside(mx, my)) return;
   int sw = 0; datetime ct = 0; double cp = 0;
   if(ChartXYToTimePrice(0, mx, my, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
      s_BkHoldId = BaseKnotBoxAt(ct, cp);   // exact INSIDE test first
   // P-BK-24: the SAME press tolerance the drag latch has. The user holds the
   // DRAWN border (a line `inpBoxBorderWidth` px wide sitting exactly ON the
   // boundary, so its outer half is outside the rectangle) and an inside-only
   // test made the toolbar of every border-held box unreachable — the hold
   // simply never fired. Measured in pixels against the box's corners, never
   // guessed in price.
   if(s_BkHoldId == "") s_BkHoldId = BaseKnotBoxAtPx(mx, my);
}
void BkHoldForgetBox() { s_BkHoldId = ""; }   // keep the press latch (dragging!)
void BkHoldClear() { s_BkHoldId = ""; s_BkHoldMs = 0; s_BkDownNow = false; }
// THE single opener: fires while the button is still down, then disarms the
// press so the release that follows opens nothing. Keeps s_BkDownNow=true so
// the poll backup below cannot re-latch the same press (no refire flicker).
void BkHoldFire()
{
   string id = s_BkHoldId;
   s_BkHoldId = ""; s_BkHoldMs = 0;   // disarmed — release opens nothing
   if(id == "" || BaseKnotSessionActive() || g_PalOpen) return;
   if(BaseKnotFind(id) < 0) return;   // box deleted mid-hold
   if(!BaseKnotVisibleNow(id)) return;   // TF-hidden box owns no toolbar (no flash-open)
   g_BkMiniBox = id;   // LOCK/DELETE rows act on this box (validated on every use)
   // TV-like: anchor the strip next to the held box (above its top-right
   // corner, flipping below when there is no room). It re-anchors on EVERY
   // open — no header, not drag-parkable (R-BKSTRIP).
   string pfx = BaseKnotPrefix(id);
   if(pfx != "")
   {
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) >= 0)
      {
         datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
         double tp = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                             ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
         int x2 = 0, y2 = 0;
         if(ChartTimePriceToXY(0, 0, t2, tp, x2, y2))
         {
            int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0); if(cw <= 0) cw = 1920;
            int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); if(ch <= 0) ch = 1080;
            int mh = PNL_TB_H;   // TV strip height, not the old 7-row card (R-BKSTRIP)
            int nx = x2 + 14;
            int ny = y2 - mh - 14;
            if(ny < 4)
            {
               // P-BK-27: NO ROOM ABOVE → BELOW THE BOX'S BOTTOM EDGE, not below
               // its top edge. Flipping under the TOP edge drops the whole strip
               // INSIDE the rectangle, and then the press on any of its controls
               // lands on the box as well — the terminal grabs the SELECTABLE
               // handle, so picking a width or a style drags the box with the
               // hand. The toolbar never overlaps the handle it belongs to.
               double bp = MathMin(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                                   ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
               int bx = 0, by = 0;
               if(ChartTimePriceToXY(0, 0, t2, bp, bx, by) && by > y2) ny = by + 14;
               else ny = y2 + 14;   // unprojectable (off-window) — the old flip
            }
            if(nx < 4) nx = 4; if(nx > cw - PNL_TB_W - 4) nx = cw - PNL_TB_W - 4;
            if(ny < 4) ny = 4; if(ny > ch - mh - PNL_BOTTOM_SAFE) ny = ch - mh - PNL_BOTTOM_SAFE;
            if(nx < 4) nx = 4; if(ny < 4) ny = 4;   // tiny-chart fallback
            g_PnlX[13] = nx; g_PnlY[13] = ny;
         }
      }
   }
   PnlOpen(13);   // mini quick-style (••• inside opens the full card 12)
   // The button-up that ends THIS hold is part of the open gesture (it lands
   // on the box = outside the strip) — arm the one-shot release guard so the
   // TV-style outside-click dismissal below never eats its own opening click.
   s_BkFireReleasePending = true;
   ChartRedraw();
}
void BkHoldOnMove(const int mx, const int my, const bool leftDown, const bool pressStart)
{
   if(pressStart) { BkHoldLatch(mx, my); return; }
   if(!leftDown) { BkHoldClear(); return; }   // release — opens NOTHING
   if(s_BkHoldMs == 0 || s_BkHoldId == "") return;
   if(MathAbs(mx - s_BkHoldX) > BK_HOLD_MOVE || MathAbs(my - s_BkHoldY) > BK_HOLD_MOVE)
   { BkHoldForgetBox(); return; }   // it's a drag, not a hold
   if(GetTickCount() - s_BkHoldMs >= BK_HOLD_MS) BkHoldFire();   // still held still → open NOW
}
//--- polled half: a press with ZERO mouse movement emits NO MOUSE_MOVE, so
//--- the move path above can never latch it. Runs per tick + 250 ms timer via
//--- RefreshKitOnBar. Fires the same mid-hold open for the zero-move case —
//--- the button is definitionally still down (every release emits CLICK /
//--- OBJECT_CLICK, which clear the latch), re-verified by hit-test.
void BkHoldPoll()
{
   // Backup latch for the zero-move press ONLY (nothing latched + fresh
   // down-transition). Never touches a live latch — no timer reset, ever.
   if(s_BkHoldMs == 0 && !s_BkDownNow && !BaseKnotSessionActive() && !g_PalOpen &&
      UILeftButtonDown())
      BkHoldLatch(g_LastUIX, g_LastUIY);
   if(s_BkHoldMs == 0)   // nothing latched (or already fired) — expire a stuck
   {                     // down-flag so one missed up-event can't jam holds forever
      if(s_BkDownNow && UILeftButtonUp()) s_BkDownNow = false;
      return;
   }
   uint now = GetTickCount();
   if(now - s_BkHoldMs > BK_LATCH_TTL) { BkHoldClear(); return; }
   if(BaseKnotSessionActive() || g_PalOpen) { BkHoldClear(); return; }
   if(s_BkHoldId == "" || !s_BkDownNow) return;
   if(now - s_BkHoldMs < BK_HOLD_MS) return;
   if(MathAbs(g_LastUIX - s_BkHoldX) > BK_HOLD_MOVE || MathAbs(g_LastUIY - s_BkHoldY) > BK_HOLD_MOVE)
   { BkHoldForgetBox(); return; }
   int sw = 0; datetime ct = 0; double cp = 0;   // re-hit-test: box still under cursor?
   string under = "";
   if(ChartXYToTimePrice(0, g_LastUIX, g_LastUIY, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
      under = BaseKnotBoxAt(ct, cp);
   if(under != s_BkHoldId) { BkHoldForgetBox(); return; }
   BkHoldFire();
}
// Release NEVER opens (single method: mid-hold fire above). Any button-up only
// clears the latch — the press already fired, or it was a tap/drag.
void BkHoldOnBoxUp()
{
   // BKSELECT-KEPT (2026-09-15): the strip no longer deselects the box — the
   // selection stays like MT4's own rectangle, so styling then resizing needs
   // no re-click (retired with the release drop in `BaseKnotOnChartEvent`).
   BkHoldClear();
}

// ════════════════════════════════════════════════════════════════════════
// P-UI-93 (2026-09-16) — ONE REACTION TO "THE DISPLAY CHANGED".
//
// `PnlDpiPoll()` (UtilityFunctions) answers the QUESTION — has the
// terminal's screen DPI moved since we last looked — and this is the ONE
// place that answers it. No surface may probe the terminal itself, and no
// surface may keep a metric it was sized with before the change: every
// one of them is rebuilt from the new numbers through its OWN existing
// builder, so this function owns nothing but the roll call.
//
// Why the ring/panel are DELETED and recreated instead of re-asserted:
// a point size and a measured caption width decide object GEOMETRY
// (positions, XSIZE of the cells, where a row's text is centred), and the
// create pair is the only path that re-derives all of it - the same pair
// the ring already uses for "the menu came back" and "the menu was
// toggled" (BiotakMenu: BaseKnotExitToMenu / ToggleMenuVisibility).
// `PnlRebuildKeepSpot` is the card's version of it: the card is built
// again where it is (a metric change must not re-anchor a card the user
// is looking at), which is exactly what a height-changing tab already
// asked it for.
//
// The floaters are re-derived rather than closed: the palette is rebuilt
// through `PalOpenKind` (same anchor item, same colour target - the
// rebuild its own draw path already uses), and a hanging Base Box
// dropdown is closed with `BkDdClose`, which is a pure delete (no click
// is eaten, so the user's next press still lands where it was aimed).
//
// Cost: this runs ONLY on a real DPI change (a monitor move, a Windows
// scale change) - i.e. essentially never in a session, and never on a
// tick. Steady state pays one time-gated probe, in `RefreshKitOnBar`.
void UIRebuildForMetrics()
{
   // A rebuild while the user is mid-gesture would fight the gesture for the
   // same objects (the ring/panel builders delete what the drag is holding).
   // The probe keeps running, so the change lands on the first frame after
   // the hand comes off - one event on a display that was just moved.
    if(g_DragOwner != DRAG_NONE || g_PnlDragItem >= 0 || g_PalMixDrag > 0 ||
       g_OrbDragging || g_LongPressItem >= 0 || g_BkTextFocus || s_palMoveArmed)
   {
      CircUIMetricsInvalidate();
      return;
   }
   CircUIMetricsInvalidate();
   // 1. the ring / orb (and whatever sub-menu the ring was showing)
   DeleteMenu();
   CreateMenu();
   // 2. the open card - rebuilt on the spot, never re-anchored
   if(g_PnlOpen >= 0) PnlRebuildKeepSpot(g_PnlOpen);
   // 3. the floaters (the palette first: it anchors off the card above)
   if(g_BkDd != 0) BkDdClose();
   if(g_PalOpen) PalOpenKind(g_PalAnchorItem, g_PalKind);
   // 4. the chart-side text is measured with the same em box (`PnlRawLineH`),
   //    so the ATR/TH columns and the trade-plan card must re-lay-out too.
   g_labelsRelayoutNeeded = true;
   RepaintForDiscreteAction();   // P-PERF-24's owner: a discrete event paints now
}

#endif // BIOTAK_PANELS_ROUTE_MQH
