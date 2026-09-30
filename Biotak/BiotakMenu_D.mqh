// BiotakMenu_D.mqh - BiotakMenu.mqh split 2026-09-29: exact lines 4016-4443, byte-identical, zero renames.
#ifndef BIOTAK_MENU_D_MQH
#define BIOTAK_MENU_D_MQH

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
      if(g_OrbWasDragged)
      {
         g_OrbWasDragged = false;
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
      if(clickedObject == SubPagerPrev() || clickedObject == SubPagerNext())
      {
         // MT4 LATCHES an OBJ_BUTTON after a click (STATE stays true → the
         // chevron looks stuck down). Clear it on every pager click.
         ObjectSetInteger(0, clickedObject, OBJPROP_STATE, false);
         int pages = SubPageCount();
         int np = g_ToolsPage + ((clickedObject == SubPagerNext()) ? 1 : -1);
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
       else if(tfeat == CIR_BASEKNOT)
       {
          // UIBK-OFF (P-UI-95): the MEASURING tool has its own RING slot now
          // (RING_BASEKNOT) and this cell is retired in place. It can no longer be
          // reached (ToolFeature no longer maps TOOL_BASEKNOT), and the arm path it
          // ran is `CircArmBaseKnot`'s own — restore the cell by counting
          // TOOL_BASEKNOT back into TOOL_COUNT and uncommenting these two lines.
          // UIBK-OFF: ToolsUpdateItemState(tidx);
          // UIBK-OFF: return CircArmBaseKnot();
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
                        feat == CIR_ATR     || feat == CIR_TH);
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
      g_UI.showHTF = !g_UI.showHTF;
      // P-UI-40b (2026-09-13): the HTF card's row 0 displays THIS flag, and this
      // file is included BEFORE the panel's - so the ring cannot repaint that card
      // itself. The ring repairs its own light/status on the next tick
      // (UpdateMenuSyncIfChanged fingerprints CircFeatureOn), but an open card has
      // no such net: without this request it kept the previous switch position
      // until it was reopened. Same asymmetry P-UI-40 fixed for the other
      // switches; this one was missed because `g_UI.showHTF` was not on the
      // gate's displayed-state list (it is now).
      RequestUISync();   // P-UI-40b: the HTF card's SHOW row displays this flag
      refreshFlags = REFRESH_HTF;
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

   CircUpdateItemState(idx);
   UpdateCircularBadges();
   SaveUIStates();
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
      for(int i = 0; i < RING_COUNT; i++) CircCreateItem(i);
      if(g_ToolsOpen)
         for(int t = 0; t < TOOL_COUNT; t++) ToolsCreateItem(t);
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
