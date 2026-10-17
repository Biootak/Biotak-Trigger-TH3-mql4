// BiotakMenu_D.mqh - BiotakMenu.mqh split 2026-09-29: exact lines 4016-4443, byte-identical, zero renames.
#ifndef BIOTAK_MENU_D_MQH
#define BIOTAK_MENU_D_MQH

//--- P-UI-163: the ring's own existence probe — ONE seat per tick, round-robin.
//--- MEASURED 2026-10-17 (the 12:05:39 frame): a seat whose icon create failed
//--- mid-burst kept its bg and lost its glyph for the rest of the attach — and NO
//--- writer re-created a missing icon (every path gated on ObjectFind>=0; the
//--- P-UI-161 sync's hash sees the DESIRED state, not the chart;
//--- CircRelayoutIfNeeded compares counts). Cost on a still frame: 2 ObjectFind
//--- per tick, 0 writes; the ring is swept in CircPlacedCount() ticks and a hole
//--- is rebuilt the tick it is seen (the tip's own one-probe-per-tick shape,
//--- P-PERF-17). P-SIZE-1500 sent it here from BiotakMenu_C (its owner file).
//--- P-UI-163c: while the fan is open the ring does not exist on purpose, so the
//--- probe serves the CELLS then — one per tick, the same hole class (a failed
//--- cell create was a permanent hole too: no writer re-created it). The whole
//--- seat family is probed: bg+icon always, badge when the feature has one, and
//--- the ring seat's badge likewise. Still ~2-4 ObjectFind/tick, 0 writes whole.
//--- Parked cells are skipped: a hole off-page is invisible by definition and
//--- heals the tick it is back on its page.
void CircHealRingStep()
{
   if(!g_UI.menuVisible || g_OrbDragging) return;
   if(g_ToolsOpen)
   {
      if(CAT_COUNT <= 0) return;
      static int s_healCell = 0;
      if(s_healCell >= CAT_COUNT) s_healCell = 0;
      int t = s_healCell++;
      if(!SubItemOnPage(t)) return;
      bool bHole = (ObjectFind(0, ToolsBg(t)) < 0 || ObjectFind(0, ToolsIcon(t)) < 0 ||
                    ObjectFind(0, ToolsStar(t)) < 0);
      if(!bHole && CircHasBadge(ToolFeature(t)))
         bHole = (ObjectFind(0, ToolsBadgeBg(t)) < 0 || ObjectFind(0, ToolsBadgeTxt(t)) < 0);
      if(bHole)
      {
         ToolsCreateItem(t);   // the whole cell family; on-page by the gate above
         DrawStripDiagEmit(StringFormat("[P-UI-163] tools heal cell=%d", t));
      }
      return;
   }
   int n = CircPlacedCount();
   if(n <= 0) return;
   static int s_healSeat = 0;
   if(s_healSeat >= n) s_healSeat = 0;
   int i = s_healSeat++;
   bool bHole = (ObjectFind(0, CircBg(i)) < 0 || ObjectFind(0, CircIcon(i)) < 0);
   if(!bHole && CircHasBadge(RingFeature(i)))
      bHole = (ObjectFind(0, CircBadgeBg(i)) < 0 || ObjectFind(0, CircBadgeTxt(i)) < 0);
   if(bHole)
   {
      CircCreateItem(i);
      DrawStripDiagEmit(StringFormat("[P-UI-163] ring heal seat=%d", i));
   }
}

// P-SIZE-1500 (2026-10-17): moved here from BiotakMenu_C, verbatim — its only
// caller (BiotakKit's per-tick pass) loads after this file, and C sat 22 lines
// over the ceiling. The law is unchanged: only a state edge runs the heavy pass.
//+------------------------------------------------------------------+
//| PERF: change-guarded periodic icon sync.                          |
//| Re-setting OBJPROP_BMPFILE makes MT4 re-decode the bitmap, so the |
//| old every-500ms unconditional pass churned the chart thread even  |
//| when nothing changed. We fingerprint the on/off state of all ring |
//| icons and only run the heavy pass when it actually differs.       |
//+------------------------------------------------------------------+
void UpdateMenuSyncIfChanged()
{
   static ulong s_LastStateHash = 0;

   // FNV-1a fingerprint of ring + tools on/off state AND badge TEXT, so
   // value-only changes (E/S hotkeys, factor override, TH mode) refresh the
   // badges — not just on/off flips. P-UI-161: the star MASK is in the hash too,
   // so a membership change repaints even when no feature state moved.
   ulong h = 1469598103934665603;
   h = (h ^ (ulong)g_CircStarMask) * 1099511628211;
   for(int i = 0; i < CircPlacedCount(); i++)
   {
      int feat = RingFeature(i);
      ulong v = (ulong)(CircFeatureLit(feat) ? 1 : 0);
      h = (h ^ (v + 0x9E3779B97F4A7C15 * (ulong)(feat + 1))) * 1099511628211;
      string t = CircBadgeText(feat);
      for(int c = 0; c < StringLen(t); c++)
         h = (h ^ StringGetCharacter(t, c)) * 1099511628211;
   }
   for(int t = 0; t < CAT_COUNT; t++)
   {
      int feat = ToolFeature(t);
      ulong v = (ulong)(CircFeatureLit(feat) ? 1 : 0);
      h = (h ^ (v + 0x9E3779B97F4A7C15 * (ulong)(feat + 1))) * 1099511628211;
      string bt = CircBadgeText(feat);
      for(int c = 0; c < StringLen(bt); c++)
         h = (h ^ StringGetCharacter(bt, c)) * 1099511628211;
   }
   if(h == s_LastStateHash) return;   // nothing visible changed -> no churn
   s_LastStateHash = h;

   if(g_UI.menuVisible)
      UpdateCircularItemStates();
   UpdateCircularBadges();
   CircTipRefresh();   // hovered tooltip follows the new state
}

// P-HTF-KEY — ONE owner for the HTF overlay switch: the R hotkey, the ring's
// HTF light and the card's ENABLED row. State + persisted key + mask walk
// (instant both ways, no delete/rebuild); first ON builds via the walk.
// Callers own nothing more (P-PERF-24 paints in the owner).
void SetHTFVisible(const bool on)
{
   uint t0 = GetTickCount();
   g_UI.showHTF = on;
   GlobalVariableSet(GetGVName("HTF_EN"), on ? 1.0 : 0.0);
   HTFApplyVisibleMasks();
   RepaintForDiscreteAction();      // P-PERF-24: the press paints NOW
   Print("[HTF] set on=", (on ? 1 : 0), " drawn=", g_HTFDrawnCount,
         " ms=", (int)(GetTickCount() - t0));
}

//+------------------------------------------------------------------+
//| Handle Button Click Events                                       |
//+------------------------------------------------------------------+
int HandleButtonClick(const string clickedObject)
{
   if(clickedObject == CircOrbBg())
   {
      // Orb doubles as the session EXIT while drawing (menu is hidden then).
      if(BaseKnotSessionActive()) { BaseKnotExitToMenu(); return REFRESH_NONE; }
      if(HRaySessionActive()) { HRayCancel(); return REFRESH_NONE; }   // P-HR-01: orb exits the ray arm
      if(PathSessionActive()) { PathSessionClear(); PathCancel(); return REFRESH_NONE; }
      if(g_OrbWasDragged)
      {
         g_OrbWasDragged = false;   // P-UI-147: this flag is the CLICK-EATER's alone. It used
         //--- to also carry «the hand really moved the orb», and clearing it here could land
         //--- before the release read it — the orb's home was then never saved and the next
         //--- repaint put it back where it was. The movement has its own flag (g_OrbMoved),
         //--- which only the release clears.
         return REFRESH_NONE;
      }
      // Hierarchy: orb -> ring -> sub-menu. While the sub-menu is open the ring is
      // hidden (the fan/ring geometry cannot coexist with it), so the orb is the
      // only way BACK — it closes the sub-menu instead of hiding the whole menu.
      // Without this the sub-menu could only be dismissed by hiding the terminal
      // menu entirely, and the TOOLS button it was opened from no longer exists.
      if(g_ToolsOpen) { DeleteToolsMenu(); return REFRESH_NONE; }
      ToggleMenuVisibility();
      return REFRESH_NONE;
   }

   // --- Tools sub-menu panel: pager first, then dead space ---
   if(g_ToolsOpen)
   {
      // P-UI-151: the chevrons are OBJ_BUTTONs born SELECTABLE=false, so MT4
      // may never emit OBJECT_CLICK for them (P-DRAW-84). Keep the name route,
      // but when it did not match, ask the coordinates — the same door the
      // cards use (P-UI-74). `SubPagerAt` reads `SubPagerGeom`, the one owner
      // the paint already uses, so this is not a second grid.
      string pagerName = clickedObject;
      if(pagerName != SubPagerPrev() && pagerName != SubPagerNext())
      {
         int pdir = 0;
         if(SubPagerAt(g_LastUIX, g_LastUIY, pdir))
            pagerName = (pdir > 0) ? SubPagerNext() : SubPagerPrev();
      }
      if(pagerName == SubPagerPrev() || pagerName == SubPagerNext())
      {
         // MT4 LATCHES an OBJ_BUTTON after a click (STATE stays true → the
         // chevron looks stuck down). Clear it on every pager click — but only
         // if the object exists: the coordinate door can name a chevron that
         // this page's chrome did not create.
         if(ObjectFind(0, pagerName) >= 0)
            ObjectSetInteger(0, pagerName, OBJPROP_STATE, false);
         int pages = SubPageCount();
         int np = g_ToolsPage + ((pagerName == SubPagerNext()) ? 1 : -1);
          if(np >= 0 && np < pages)
          {
             g_ToolsPage = np;
             // P-UI-26/F12: a visible/armed hover tip describes the OLD page's
             // cell — disarm it, or it sticks to the wrong tool (or thin air).
             CircTipDisarm();
             SubApplyPage();   // park the old page's cells, show the new ones
          }
         ChartRedraw();
         return REFRESH_NONE;
      }
      // Header, accent dot, count and page dots are decoration, not controls —
      // swallow the click so it never falls through to the chart.
      if(clickedObject == SubPanelBg() || clickedObject == SubPanelDot() ||
         clickedObject == SubPanelHdr() || clickedObject == SubPanelCnt() ||
         clickedObject == SubPagerTxt() ||
         StringFind(clickedObject, g_UI.btnPrefix + "SubPagerDot") == 0)
         return REFRESH_NONE;
   }

   // --- Tools half-circle items ---
   int tidx = ToolsIndexFromName(clickedObject);
   if(tidx >= 0)
   {
      if(StringFind(clickedObject, g_UI.btnPrefix + "ToolsBadge") == 0)
      {
         UISuppressNextClick();
         PnlOpen(ToolPanel(tidx));
         return REFRESH_NONE;
      }
      // P-UI-161: the membership star — a TOGGLE and nothing else. It sits before
      // the long-press latch (like the badge): the star is its own control, and a
      // stale latch from a previous gesture must not eat its click. No suppression
      // either — nothing else acts on this release (the ring toggles' own rule).
      if(StringFind(clickedObject, g_UI.btnPrefix + "ToolsStar") == 0)
      {
         CircStarToggle(tidx);
         return REFRESH_NONE;
      }
      if(g_LongPressFired)
      {
         g_LongPressFired = false;
         g_LongPressItem = -1;
         return REFRESH_NONE;
      }
      int tfeat = ToolFeature(tidx);
      int tflags = REFRESH_NONE;
      if(tfeat == CIR_PIN)
      {
         // P-UI-45: THE BUTTON IS A TOGGLE. It used to ALWAYS re-arm: every press
         // deleted the line and re-created it at the market price (and left it
         // SELECTED), so the light could be switched ON and never OFF and the only
         // way back to the default start point was the ESC key - a control that
         // moves its own state in one direction only. OFF runs the SAME owner the
         // ESC key does, so the two can never drift.
         if(g_customPriceLineCreated || g_waitingForCustomPriceClick ||
            g_customPriceKeyboardOverride)
         {
            DeactivateCustomPriceMode("ring PIN");
            tflags = REFRESH_ALL;
         }
         else
         {
            g_waitingForCustomPriceClick = true;
            g_customPriceKeyboardOverride = true;
            ObjectDelete(0, g_customPriceHorizontalLineName);
            g_customPriceLineCreated = false;
            // P-UI-98d v2: the line is born where the user is LOOKING — the
            // vertical middle of the visible chart, wherever they have scrolled
            // («زمانی که فعال میشه هر جایی که کاربر هست وسط صفحه ظاهر بشه») —
            // and the market's last price is only the fallback.
            double currentPrice = ScreenMiddlePrice();
            if(!(currentPrice > 0.0))
                currentPrice = iClose(_Symbol, CompatTF(GetCachedPeriod()), 0);
            g_customTHStartPrice = currentPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            // P-UI-98e: a FRESH placement wakes the armed/set pair through its
            // ONE owner - a line the user had SET must not come back inert.
            HandsetPlacementArm();
            // P-UI-56: the placement pair has ONE writer, in the domain layer
            // (`EventHandlers`, included before this file). The keys are chart-scoped
            // now, so pressing PIN on this chart can no longer move the ladder of
            // another chart of the same symbol.
            CustomPricePersistPlacement(currentPrice);
            // P-UI-48: always grabbable, never pre-SELECTED - the line's drag IS
            // its SELECTABLE flag, and the interference was a selection that
            // outlived its gesture (see CreateCustomPriceLine).
            CreateCustomPriceLine(currentPrice, Digits);
            g_redrawTHLevelsNeeded = true;
            tflags = REFRESH_ALL;
         }
      }
       else if(tfeat == CIR_STEP_OVERRIDE)
       {
          // STEPOVERRIDE-OFF: single Step Mode — cycle the base 0..3 (same as
          // the E key and the panel row). OV_ persist rides on REFRESH_ALL.
          g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)(((int)GetCurrentStepMode() + 1) % 4);
          // P-UI-40b: this item is the SAME control as the E key (which asks, see
          // EventHandlers) one surface over. The STEP card's mode row displays this
          // value and the ring cannot repaint an open card from here.
          RequestUISync();   // P-UI-40b: the STEP card's mode row displays this value
          GlobalVariableDel("Biotak_StepMode_" + GetCachedChartIdStr());   // purge retired override key
          UpdateStepModeLabel();   // same confirmation as E / panel (redraw below only repositions it)
          g_forceClearOnNextDraw = true;
          g_redrawTHLevelsNeeded = true;
          tflags = REFRESH_ALL;
       }
       else if(tfeat == CIR_GENERAL)   // P-UI-131: a pure door — no switch to invert
       {
          // OPEN on the CLICK, the same act the HOLD performs (the long-press path
          // asks ToolPanel too), so the one gesture the user already knows works and
          // nothing else in the ladder changes state.
          UISuppressNextClick();
          PnlOpen(ToolPanel(tidx));
          return REFRESH_NONE;
       }
        else if(tfeat == CIR_HRAY)   // P-HR-01: momentary toggle — the cell light is the session
        {
           tflags = CircArmHRay();
        }
        else if(tfeat == CIR_PATH)
        {
           tflags = CircArmPath();
        }
        else if(tfeat == CIR_SCALE)   // P-UI-159 — MT4's own scale-fix as one cell
        {
           // ONE live writer of the chart's scale-fix bit (the retired View Lock's
           // writes are dormant, VIEWLOCK-OFF): read → flip → READ BACK, and the
           // witness goes through the FLUSHED channel (P-DRAW-126) carrying the
           // value the CHART holds, not the one we asked for. No recalc — the
           // cell light below reads the same bit (CircFeatureOn).
           bool wasFixed = (ChartGetInteger(0, CHART_SCALEFIX) != 0);
           bool retOk    = ChartSetInteger(0, CHART_SCALEFIX, !wasFixed);
           bool nowFixed = (ChartGetInteger(0, CHART_SCALEFIX) != 0);
           DrawStripDiagEmit("[P-UI-159] scale was=" + IntegerToString(wasFixed ? 1 : 0) +
                             " now=" + IntegerToString(nowFixed ? 1 : 0) +
                             " ret=" + IntegerToString(retOk ? 1 : 0));
           ChartRedraw();   // P-DRAW-127: the click owns its frame
        }
        else if(tfeat == CIR_HIDE)   // P-UI-160 — the F mute, one surface over
        {
           // The cell IS the F key: the same ONE owner (`ApplyHideAllState`,
           // EventHandlers_Objects), the same target-state rule (read the mute's
           // own reader and invert, never a delta), and the same follow-ups the
           // Router's F branch runs (RequestUISync for the panels' family rows,
           // then the forced paint). The witness carries what the READER holds
           // after the write, through the FLUSHED channel (P-DRAW-126).
           bool wasHidden = IsIndicatorHidden();
           int  hideRet   = ApplyHideAllState(!wasHidden);
           bool nowHidden = IsIndicatorHidden();
           DrawStripDiagEmit("[P-UI-160] hide was=" + IntegerToString(wasHidden ? 1 : 0) +
                             " now=" + IntegerToString(nowHidden ? 1 : 0) +
                             " ret=" + IntegerToString(hideRet));
           RequestUISync();               // P-UI-93: the panel's family rows display this mute
           RepaintForDiscreteAction();    // P-PERF-24: the press paints NOW
        }
       else if(tfeat == CIR_BASEKNOT)
       {
          // UIBK-OFF (P-UI-95): the MEASURING tool has its own RING slot now
          // (RING_BASEKNOT) and this cell is retired in place. It can no longer be
          // reached (ToolFeature no longer maps TOOL_BASEKNOT), and the arm path it
          // ran is `CircArmBaseKnot`'s own — restore the cell by counting
          // TOOL_BASEKNOT back into the catalog count and uncommenting these two lines.
          // UIBK-OFF: ToolsUpdateItemState(tidx);
          // UIBK-OFF: return CircArmBaseKnot();
       }
       // P-UI-161: the 9 ring features are catalog cells too — a click on one in
       // the Tools menu runs the SAME switch the ring runs. ONE owner
       // (`RingFeatureClick`), so the two surfaces can never drift.
       else if(tfeat == CIR_ZONES || tfeat == CIR_TRIGGER || tfeat == CIR_ATR ||
               tfeat == CIR_TH    || tfeat == CIR_HTF     || tfeat == CIR_TH3 ||
               tfeat == CIR_LEG   || tfeat == CIR_SESSIONS)   // P-SESS
       {
          tflags = RingFeatureClick(tfeat);
       }
      // FACTORBTN-OFF:
      //else if(tfeat == CIR_FACTOR_OVERRIDE)
      //{
      //   if(g_factorValueOverride == 0) g_factorValueOverride = 25;
      //   else if(g_factorValueOverride == 25) g_factorValueOverride = 50;
      //   else if(g_factorValueOverride == 50) g_factorValueOverride = 100;
      //   else if(g_factorValueOverride == 100) g_factorValueOverride = 144;
      //   else g_factorValueOverride = 0;
      //   string factorGvarName = "Biotak_Factor_" + GetCachedChartIdStr();
      //   if(g_factorValueOverride == 0) GlobalVariableDel(factorGvarName);
      //   else GlobalVariableSet(factorGvarName, g_factorValueOverride);
      //   g_forceClearOnNextDraw = true;
      //   g_redrawTHLevelsNeeded = true;
      //   tflags = REFRESH_ALL;
      //}
      ToolsUpdateItemState(tidx);
      UpdateCircularBadges();
      SaveUIStates();
      return tflags;
   }

   int idx = CircIndexFromName(clickedObject);
   if(idx < 0) return REFRESH_NONE;

   if(StringFind(clickedObject, g_UI.btnPrefix + "CircBadge") == 0)
   {
      UISuppressNextClick();
      PnlOpen(RingPanel(idx));
      return REFRESH_NONE;
   }

   if(g_LongPressFired)
   {
      g_LongPressFired = false;
      g_LongPressItem  = -1;
      return REFRESH_NONE;
   }

   int feat = RingFeature(idx);
   if(feat == CIR_TOOLS)
   {
      if(g_ToolsOpen) DeleteToolsMenu();
      else CreateToolsMenu();
      return REFRESH_NONE;
   }

   // P-UI-161: the feature's own switch is ONE owner (`RingFeatureClick`) — the
   // same body the Tools menu's feature cells run, so the two surfaces can never
   // drift. The ring's own tail stays here (the Tools tail is ToolsUpdateItemState's).
   int refreshFlags = RingFeatureClick(feat);
   CircUpdateItemState(idx);
   UpdateCircularBadges();
   SaveUIStates();
   return refreshFlags;
}

//+------------------------------------------------------------------+
//| P-UI-161 — ONE OWNER for a ring feature's press.                  |
//|                                                                  |
//| The ring seat and the Tools cell are the SAME control one        |
//| surface over (the 8 features are catalog cells too), so both     |
//| routes run THIS body — a switch written twice is the drift this  |
//| project keeps paying for. The caller owns the tail: the ring's   |
//| (CircUpdateItemState) and the Tools menu's (ToolsUpdateItemState)|
//| — this function touches neither.                                  |
//+------------------------------------------------------------------+
int RingFeatureClick(const int feat)
{
   // P-UI-93 — THE PRESS ANSWERS WHAT THE LIGHT SHOWED.
   //
   // While the chart is muted the four family lights read OFF (CircFeatureOn
   // folds the mute), so this press means "show the family again", and the mute
   // has to go for that to be visible at all. `wantOn` is captured BEFORE the
   // release, because the release is exactly what changes what the light reports.
   //
   // The mute is NOT a switch (P-PERF-41 stays intact: each light still owns one
   // switch), it is the whole-indicator master every family already shares.
   bool familyToggle = (feat == CIR_TRIGGER || feat == CIR_ZONES ||
                        feat == CIR_ATR     || feat == CIR_TH ||
                        feat == CIR_SESSIONS);   // P-SESS
   bool mutedPress   = (familyToggle && IsIndicatorHidden());
   bool wantOn       = (familyToggle && !mutedPress) ? !CircFeatureOn(feat) : mutedPress;
   if(mutedPress) ReleaseIndicatorMute();

   int refreshFlags = REFRESH_NONE;
   if(feat == CIR_TRIGGER)
   {
      // P-UI-40: the ring repaints ITSELF below (CircUpdateItemState +
      // UpdateCircularBadges), but it cannot repaint an OPEN card — this file is
      // included before the panel's. The same state is the TRIGGER card's SHOW
      // row, so the UI layer is asked as well; the drain is idempotent.
      RequestUISync();
      // P-PERF-32b: ONE owner for the transition (state, persisted key, the
      // family's own mask walk, the discrete repaint). This branch, the T hotkey
      // and the card's SHOW row used to keep three copies of the state write and
      // let the RENDER produce the pixels - which is why the light felt dead on
      // a weak PC. The structure switches' technique (P-PERF-32), for the family
      // whose property is its mask; P-PERF-21 still holds: NO force-clear.
      SetTriggerLevelsVisible(wantOn);
      refreshFlags = REFRESH_NONE;   // the owner painted; the ring repaints below
   }
   else if(feat == CIR_ZONES)
   {
      // P-PERF-41: ONE switch, and only its own. The zone family is masked by
      // the render (LevelPipeline P-PERF-41), so this is a state flip plus masks -
      // no delete, no rebuild, and nothing else on the chart moves.
      //
      // It must NOT call SetLinesVisible: the SHOW LINES row (and the L key) own
      // that switch, and a press that turned the lines on would overwrite a
      // choice the user made elsewhere. See the note on CircFeatureOn.
      g_showMidZones = wantOn;   // P-UI-93: what the light showed, inverted
      RequestUISync();   // P-UI-40: the Zones card's MID ZONES row shows this
      g_redrawTHLevelsNeeded = true;
      refreshFlags = REFRESH_BUFFERS;
   }
   else if(feat == CIR_ATR)
   {
      g_atrLabelsVisible = wantOn;   // P-UI-93: what the light showed, inverted
      RequestUISync();   // P-UI-40: the ATR card's own rows show this switch
      g_showATRLabels = g_atrLabelsVisible;   // keep the ATR card mirror in sync
      string atrGvarNameKey = "Biotak_ATRLabels_" + GetCachedChartIdStr();
      GlobalVariableSet(atrGvarNameKey, g_atrLabelsVisible ? 1.0 : 0.0);
      string objectPrefix = GetLevelObjectPrefix();
      SetATRLabelsVisibility(objectPrefix, g_atrLabelsVisible);
      g_labelsRelayoutNeeded = true;
      refreshFlags = REFRESH_ALL;
   }
   else if(feat == CIR_TH)
   {
       // Exclusive: ON -> OFF (remembers), OFF -> remembered ON (default STANDARD).
       if(g_thLabelsMode != 0) {
          g_thLabelsMode = 0;
       }
       else {
          g_thLabelsMode = g_thLastOnMode;
          if(g_thLabelsMode == 0) g_thLabelsMode = 2;
       }
       // P-UI-93: this item CYCLES the mode rather than flipping a switch, and the
       // cycle contains 0 (off). A muted press means "show TH", so it must not land
       // on 0 - the mute would go and the family would stay hidden, which is the
       // dead press again. A mode of 0 is raised to the remembered ON mode.
       if(mutedPress && g_thLabelsMode == 0) {
          g_thLabelsMode = g_thLastOnMode;
          if(g_thLabelsMode == 0) g_thLabelsMode = 2;
       }
      g_thLabelsVisible = (g_thLabelsMode != 0);
      RequestUISync();   // P-UI-40: the TH LABELS card cycles on this mode
      SyncTHFlagsFromMode();   // flags follow the mode → TH card stays in sync
      string thGvar = "Biotak_THLabels_" + GetCachedChartIdStr();
      GlobalVariableSet(thGvar, (double)g_thLabelsMode);
      string objectPrefix = GetLevelObjectPrefix();
      SetTHLabelsVisibility(objectPrefix, g_thLabelsMode);
      g_labelsRelayoutNeeded = true;
      refreshFlags = REFRESH_ALL;
   }
   // VIEWLOCK-OFF:
   //else if(feat == CIR_VLOCK)
   //{
   //   // View Lock needs no indicator recalc — it only pins the chart view.
   //   ViewLockSetEnabled(!g_viewLockEnabled);
   //   CircUpdateItemState(idx);
   //   ThrottledChartRedraw();
   //   SaveUIStates();
   //   return REFRESH_NONE;
   //}
   // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
   else if(feat == CIR_TH3)
   {
      // P-UI-96: the press ARMS the AB=CD draw. One owner for the whole
      // decision (enable + mode repairs + the session itself) lives in
      // `CircArmTH3Draw`; the ENABLED switch this branch used to flip is the
      // TH3 TOOL card's row 0.
      refreshFlags = CircArmTH3Draw();
   }
    else if(feat == CIR_HTF)
    {
       SetHTFVisible(!g_UI.showHTF);
      // P-UI-40b (2026-09-13): the HTF card's row 0 displays THIS flag, and this
      // file is included BEFORE the panel's - so the ring cannot repaint that card
      // itself. The ring repairs its own light/status on the next tick
      // (UpdateMenuSyncIfChanged fingerprints CircFeatureOn), but an open card has
      // no such net: without this request it kept the previous switch position
      // until it was reopened. Same asymmetry P-UI-40 fixed for the other
      // switches; this one was missed because `g_UI.showHTF` was not on the
      // gate's displayed-state list (it is now).
      RequestUISync();   // P-UI-40b: the HTF card's SHOW row displays this flag
      refreshFlags = REFRESH_NONE;   // P-HTF-KEY: the owner masked + painted; a refresh flag would rebuild the family it just kept
   }
   else if(feat == CIR_SESSIONS)   // P-SESS
   {
      // A FAMILY SWITCH, like ZONES: one switch, and only its own. The renderer
      // masks by g_sessMaster, so this is a state write + a persisted key + the
      // tick that owns the pixels - no delete, no rebuild, the old frames sweep
      // on the OFF edge. Refresh flags stay NONE: the master's own wing repaints
      // its turn, and a builder flag would rebuild the family the switch kept.
      g_sessMaster = wantOn;        // P-UI-93: what the light showed, inverted
      RuntimeSettingsSaveOverridesThrottled();   // OV_SSON
      SessionsTick();
      RequestUISync();   // an open Sessions card's master row shows this switch
      refreshFlags = REFRESH_NONE;
   }
   else if(feat == CIR_BASEKNOT)
   {
      // P-UI-95: the MEASURING tool. It carries NO on/off state of its own — the light
      // is `BaseKnotSessionActive` (CircFeatureOn) and the press ARMS the drag-draw
      // session through the ONE arm path, exactly as the Tools cell used to. Nothing
      // on the chart is recalculated for it (REFRESH_NONE).
      refreshFlags = CircArmBaseKnot();
   }
#ifndef BUILD_LITE
   else if(feat == CIR_LEG)
   {
      // Momentary: the light is LegMeasureSessionActive(). A press arms/cancels
      // the 2-click trendline session. No chart recalc needed.
      LegMeasureToggle();
      refreshFlags = REFRESH_NONE;
   }
#endif

   return refreshFlags;
}

// ══════════════════════════════════════════════════════════════════════════
// P-UI-129 (2026-09-25) — A TOGGLE CHANGES VISIBILITY, NOT THE WORLD.
//
// User report: «روی منوی اصلی که کلیک میکنم او تریگر پرایس اکشن هم حالت پرپر
// میکنه که نباید باشه و هزینه مصرف بارش باید نزدیک صفر باشه کلا».
//
// The old body called `DeleteMenu()` + `CreateMenu()`, which delete and re-create
// the ORB and the HOVER CHIP as well as the ring. The pointer is ON the orb at
// that moment, so the chip that had just told the user what the orb does was
// destroyed and re-made under the cursor: the flash is the chip's own lifetime
// being punched per click. The click also paid a full family rebuild (orb +
// chip + ring + badges) for a state change that only the RING and the tools
// family can express — the orb's art does not depend on the state at all
// (ORBSTATE is retired: `CircOrbRes()` returns one skin).
//
// So the toggle owns EXACTLY the two families that change sides. The orb and the
// chip are never named here, their statics (`s_CircTipFeat`) stay valid because
// nothing they own was deleted, and the orb-skin write is change-guarded
// (P-PERF-51) so today's call is a read and nothing else. When ORBSTATE returns,
// `CircRefreshOrbSkin()` is already on the state edge where it belongs.
// ══════════════════════════════════════════════════════════════════════════
void ToggleMenuVisibility()
{
   bool willShow = !g_UI.menuVisible;
   if(willShow) PnlLockForeground();
   else PnlUnlockForeground();
   g_UI.menuVisible = willShow;
   if(!g_UI.menuVisible) PnlCloseAll();
   // kept from the pair's CreateMenu half: a toggle during a click must not
   // change that click's outcome (two bool reads under a live press, so it is a
   // no-op inside the dispatch that just called us).
   UIReleaseClaimReset();
   if(willShow)
   {
      // Same rule as CreateMenu: no ring behind an open Tools submenu.
      // P-UI-161: the ring's seats are the PLACED ones (the star mask decides),
      // the Tools menu's are the whole catalog.
      if(!g_ToolsOpen)
         for(int i = 0; i < CircPlacedCount(); i++) CircCreateItem(i);
      if(g_ToolsOpen)
         for(int t = 0; t < CAT_COUNT; t++) ToolsCreateItem(t);
   }
   else
   {
      DeleteRing();
      if(g_ToolsOpen) DeleteToolsMenu(false);
   }
   CircRefreshOrbSkin();   // ORBSTATE's state edge — one read today
   SaveUIStates();
   ChartRedraw();
}

void CleanupUIStates(const int reason)
{
   if(StringLen(g_UI.gvPrefix) == 0) return;   // UI never initialized
   // Chart props are USER property: a TF-switch/remove with an open panel or
   // a mid-air drag must never leave scroll/context-menu/foreground disabled
   // (fresh-instance statics reset to 0, so the watchdog could never heal it
   // — restore here while the old-instance saved values are still intact).
   // No-op when we hold no lock, so a user's own disabled scroll is kept.
   while(g_ChartLockCount > 0) CircUnlockChart();
   while(g_PnlForegroundLock > 0) PnlUnlockForeground();
   // P-UI-131e: A REMOVE IS NOT AN UNINSTALL. This branch used to ClearAllGVs() — every
   // saved key (the orb's place, the strip's and the chip's homes, the panel positions,
   // the card settings) died with the indicator, so the next attach re-seeded the
   // defaults: the user's «اندیکاتور رو خاموش و روشن میکنی … جاش عوض میشه». A remove
   // SAVES like any other teardown now. The HTF block keeps its own rule (its own prefix
   // and its own writer, untouched here).
   if(reason == REASON_REMOVE)
      CleanupHTFCandlesGVs();   // the HTF block keeps its OWN rule (prefix + writer)
   // P-PERF-44 (2): the HTF block writes FIRST so the ONE disk flush covers
   // it as well. The two used to serialise the terminal's whole
   // global-variable table back to back.
   SaveHTFCandlesSettings();
   SaveUIStates(true);
   // The teardown's ONE flush point. `SaveUIStates(true)` already commits
   // whatever was owed, and this call is the net for the case where it
   // early-returned (nothing of ITS six keys moved while the HTF block did
   // edit one): a request nobody commits is a setting that only lives in
   // memory, and the previous shape let exactly that happen. Nothing owed ⇒
   // one bool read, zero terminal calls.
   GVFlushCommit();
}

#endif // BIOTAK_MENU_D_MQH
