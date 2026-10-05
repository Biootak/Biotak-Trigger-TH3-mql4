// EventHandlers_Router.mqh - EventHandlers split 2026-09-29: exact lines 4271-5820 of EventHandlers.mqh, byte-identical, zero renames.
// P-SIZE-1500 (2026-10-04): the file drifted to 1630 lines (baseline 1592). The custom
// price line's whole gesture stream (lines 1030-1495) moved verbatim into
// EventHandlers_Router_Gesture.mqh, included just above the router; the seat below is
// the same seat, in the same order, so the router's decisions are untouched.
#ifndef EVENT_HANDLERS_ROUTER_MQH
#define EVENT_HANDLERS_ROUTER_MQH

void OnChartEventHandler(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // P-UI-114 (2026-09-23): right-click era deleted — terminal menu untouched,
    // strip opens on a LEFT hold (DrawStripHoldStep/PollAt in DrawStrip.mqh).

    // Base / Knot tool FIRST: while armed it owns every mouse gesture (no
    // chart-click leak into custom-price/TH3/panels), and committed boxes own
    // their badge/drag/delete events in every state.
    if(BaseKnotOnChartEvent(id, lparam, dparam, sparam)) return;
    // P-HR-01 / P-UI-136: the Horizontal Ray and the Path own their arm click and their committed drags.
    if(HRayOnChartEvent(id, lparam, dparam, sparam) || PathOnChartEvent(id, lparam, dparam, sparam)) return;

    // P-UI-100b (2026-09-22): THE DETECTOR OF "A FOREIGN OBJECT JUST APPEARED".
    //
    // A gesture of ours never creates a chart object; the terminal's own drawing
    // tools (a fib, a rectangle, a trend line) always do. An object that is NOT
    // ours, appearing while a hand-set line's gesture is live, is therefore the
    // one proof that the press which started it was a DRAW and not a grab — the
    // question the press edge itself cannot answer («وقتی فیو یا باکس از همون محل
//--- P-UI-142: the arbiter's ONE writer + its census — the terminal's own voice is the only
   //--- signal MT4 has; law, heartbeat, lock and census live at their owner (GlobalVariables.mqh).
   //--- Lite ships no draw strip, so no flushed channel: the arbiter still WORKS there.
   {
      int gl=StringLen(inpObjectPrefix);
      bool gOurs=(gl>0 && StringLen(sparam)>=gl && StringSubstr(sparam,0,gl)==inpObjectPrefix);
      if(id == CHARTEVENT_OBJECT_DRAG && !gOurs && sparam != "") GestureForeignMotion(sparam);
#ifndef BUILD_LITE
      if(GestureCensusWanted(id, sparam)) { DrawStripDiagEmit("[gest] id="+IntegerToString(id)+" t="+IntegerToString(GetTickCount())+" xy="+IntegerToString((int)lparam)+","+IntegerToString((int)dparam)+" nm=\""+sparam+"\" ours="+IntegerToString(gOurs?1:0)); }
#endif
   }
   if(id == CHARTEVENT_OBJECT_CREATE && sparam != "")
   {
       int createPrefixLen = StringLen(inpObjectPrefix);
       bool createdByUs = (createPrefixLen > 0 && StringLen(sparam) >= createPrefixLen &&
                           StringSubstr(sparam, 0, createPrefixLen) == inpObjectPrefix);
       if(!createdByUs)
       {
           // P-DRAW-01 (2026-09-22): AND THE USER'S OWN DRAWING IS STYLED THE MOMENT
           // IT EXISTS — «آخرین تغییرات ذخیره بشه». A fresh object wears the KIND's
           // memory before the user can see it in the terminal's own look; a kind never
           // styled is left exactly as MT4 drew it (the memory answers "untouched").
           DrawStyleApplyOnCreate(sparam);
           CustomPriceForeignDrawSeen();
       }
   }
// P-TICKWRAP: the window is asked through its owner, never compared against GetTickCount()
    // directly — an absolute compare stays true forever after the 49.7-day counter wrap, and
    // then EVERY delete would be ignored for the rest of the cycle (TickDeadlinePending).
    bool suppressDeleteEvent = g_suppressDeleteEvents || TickDeadlinePending(g_suppressDeleteEventsUntilMs);
    if(id == CHARTEVENT_OBJECT_DELETE && !suppressDeleteEvent) {
        string indicatorPrefix = inpObjectPrefix;
        int prefixLen = StringLen(indicatorPrefix);
        // P-BK-01 / P-HR-01: Base/Knot deletes are owned by BaseKnotTool (cascade/heal) and
        // ray deletes by HRayTool (single object) — neither may flag a level redraw or
        // pollute the object cache, so they never reach the sweep below.
        if(prefixLen > 0 && StringLen(sparam) >= prefixLen && StringSubstr(sparam, 0, prefixLen) == indicatorPrefix &&
           StringFind(sparam, "_BK_") < 0 && StringFind(sparam, "_HRAY_") < 0) {
            // P-DEL-PROBE (2026-09-30) — OUR OWN MASS DELETE, LEAKING BACK IN.
            //
            // A delete of a name in OUR namespace that arrives OUTSIDE the
            // suppression window is read as a foreign/user delete: it drops the
            // cache entry, raises a FULL levels redraw and bumps the draw
            // generation (which also voids every stored tf-mask). So one leaked
            // event from our own ~70-band trigger wipe costs a whole family
            // re-render - and a burst of them is churn the user feels as "the
            // toggle is slow", with the flag set once per event.
            //
            // The window is 250 ms from the LAST delete (`g_suppressDeleteEvents
            // UntilMs`, set by every bulk path), so a terminal that delivers the
            // queued delete events later than that turns the wipe into a storm.
            // The probe is the number that says whether that is what happens here:
            // bounded to one line per second, so a storm cannot flood the log.
            static int  s_ownDeleteLeaks   = 0;
            static uint s_ownDeleteLeakMs  = 0;
            s_ownDeleteLeaks++;
            uint leakNow = GetTickCount();
            if(s_ownDeleteLeakMs == 0 || leakNow - s_ownDeleteLeakMs >= 1000)
            {
                Print("[P-DEL] own-name delete NOT suppressed: n=", s_ownDeleteLeaks,
                      " in <=1s, last=", sparam);
                s_ownDeleteLeakMs = leakNow;
                s_ownDeleteLeaks  = 0;
            }
            CacheRemoveObject(sparam);
            g_redrawTHLevelsNeeded = true;
            // P-PERF-02: a level vanished behind our back — the stored geometry
            // signature no longer describes the chart, so the next frame must
            // rebuild for real (this is the self-heal the per-object ObjectFind
            // used to provide on every frame).
            MarkDrawGeneration();
        }
    }
    // P-UI-98j: EVEN A SUPPRESSED DELETE IS VERIFIED FOR THE STEP-1 PAIR. Our
    // own bulk deletes never name a live handle (the surplus sweep starts past
    // it, the foreign sweep runs on handoff with a fresh stash), so a stashed
    // handle name that is really gone is an external delete that fell inside
    // the 250 ms window - and ignoring it is exactly the stuck-missing line
    // («ناپدید میشه ... دیگه نمیشه جابجاش کرد»). One probe, then the same two
    // lines as above; a live gesture is left to the settle (it owns recovery).
    else if(id == CHARTEVENT_OBJECT_DELETE && suppressDeleteEvent && sparam != "" &&
            !g_s1DragLive && g_thStartPointType == TH_START_POINT_CUSTOM_PRICE &&
            g_s1MarkPeriod == Period() &&
            (sparam == g_s1MarkAboveName || sparam == g_s1MarkBelowName) &&
            ObjectFind(0, sparam) < 0)
    {
        CacheRemoveObject(sparam);
        g_redrawTHLevelsNeeded = true;
        MarkDrawGeneration();
    }

    // VIEWLOCK-OFF:
    //if(id == CHARTEVENT_OBJECT_DELETE && !suppressDeleteEvent && sparam == g_viewAnchorLineName && g_viewLockEnabled) {
    //    ViewLockSetEnabled(false);
    //    ThrottledChartRedraw();
    //    return;
    //}

    if(id == CHARTEVENT_KEYDOWN)
    {
#ifndef BUILD_LITE
        // Hex edit box owns the keyboard (palette color field): A-F are valid
        // hex digits, so every letter hotkey below must stay silent while the
        // user types. ESC/ENTER still reach the palette via HandleUIChartEvent.
        // Same for the Base Box TEXT field (TV-parity 2026-09-07 — any letter
        // is valid box text).
        if(g_PalHexFocus || g_BkTextFocus) return;
#endif
        // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
        // Backspace = undo last TH3 drawing point (X, A, B, C placement)
        if((int)lparam == 8 && TH3SessionActive()) {
            TH3SessionUndo();
            return;
        }
#endif

        //
        // F key   Hide/Show All Objects (fast visibility toggle)
        //

        if(IsHotkeyPressed(lparam, sparam, inpHideKey))
        {
            // P-UI-93: the whole transition moved into ONE owner
            // (`ApplyHideAllState`, above the handler), because the panel's
            // family rows had no other way to reach it - that was half of
            // «این دکمه های با پنل هماهنگ نیستش».
            //
            // The target state is READ from the mute's own reader and
            // inverted, never re-derived from the raw GlobalVariable here:
            // exactly one writer (SetIndicatorHiddenState) and one reader
            // (IsIndicatorHidden) exist, so they cannot drift.
            ApplyHideAllState(!IsIndicatorHidden());
            // P-UI-93: the panel's visibility rows DISPLAY this mute
            // (PnlCurrentSet), and this file is compiled before the panel, so
            // the repaint has to be asked for - exactly what the L / A / D /
            // T / S / E hotkeys already do. Without this the rows keep
            // claiming their family is painted while the chart is blank.
            RequestUISync();
            // P-PERF-24: one owner for "a discrete action paints now" - it
            // forces the repaint even while hidden, which is what the old bare
            // ChartRedraw() here was working around.
            RepaintForDiscreteAction();
            return;
        }

        //  
        // L key   Toggle Lines Visibility (all LINE objects - not boxes)
        //  
        if(IsHotkeyPressed(lparam, sparam, inpLinesToggleKey))
        {
            // P-PERF-29: the switch's state, mirror, cache, persisted key and
            // object MASK all live in one owner now - the panel rows and the
            // factory reset used to raise the flag WITHOUT writing the mask,
            // which the P-PERF-25 skip then trusted and painted nothing.
            bool p26want = !g_linesVisible;
            // P-PERF-22: this was a full-chart walk - ObjectsTotal(0,-1,-1) then
            // ObjectName + ObjectGetInteger for EVERY object on the chart, ours
            // or not, plus one TIMEFRAMES write per line whether or not the mask
            // changed. The same repair already existed, correct, in
            // VisibilityManager (SetAllLineObjectsVisibility): it walks the
            // OBJECT CACHE - only our own objects, no ObjectName calls - and it
            // keeps this hotkey's exclusions (F-key border segments, _BK_
            // trade rays). It had no callers; it does now. It also bumps the
            // P-PERF-02 epoch itself, so the guards re-assert once.
            // P-PERF-26: the switch's own cost is measured, not guessed - on the
            // old shape a bare press had no line of its own (the event ledger
            // reports the whole event and the mask walk is the only work here).
            uint p26t = GetTickCount();
            SetLinesVisible(p26want, true);
            // P-UI-40: the ZONES card's SHOW LINES row and the LINES card display
            // this switch, and this path cannot repaint them (panel file comes
            // later). Ask the UI layer — the row reads the live flag, only its
            // IMAGE is stale.
            RequestUISync();
            P4ReportSlow("lines toggle (L) [lines=" + (g_linesVisible ? "1" : "0") + "]",
                         GetTickCount() - p26t, P_P4_MOVE_WARN_MS);
            LOG_I(LOG_CAT_LINES, "Lines " + (g_linesVisible ? "VISIBLE" : "HIDDEN"));
            // P-PERF-24: a key press is one event - paint it now instead of
            // waiting for the next tick to pass the 100 ms throttle.
            RepaintForDiscreteAction();
            return;
        }

        //  
        // C key   Set Custom Price
        //  
        if(IsHotkeyPressed(lparam, sparam, inpCustomPriceKey))
        {
            g_waitingForCustomPriceClick = true;
            g_customPriceKeyboardOverride = true;
            _LOG_GATE_D Print("[D][GEN] Press anywhere on the chart to set custom TH start price");
            ObjectDelete(0, g_customPriceHorizontalLineName);
            g_customPriceLineCreated = false;
            // P-UI-98d v2: the line is born at the vertical middle of the VISIBLE
            // chart — wherever the user has scrolled («هر جایی که کاربر هست وسط
            // صفحه ظاهر بشه») — the market's last price is only the fallback.
            double currentPrice = ScreenMiddlePrice();
            if(!(currentPrice > 0.0))
                currentPrice = iClose(_Symbol, CompatTF(GetCachedPeriod()), 0);
            g_customTHStartPrice = currentPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            HandsetPlacementArm();   // P-UI-98e: the fresh line and its handles wake draggable
            // P-UI-56: ONE writer for the placement pair (this chart's price + flag).
            CustomPricePersistPlacement(currentPrice);
            // P-UI-48: ONE creator. This block used to write the line's whole
            // property set by hand - the fifth copy of it in the file, and the
            // place a stale OBJPROP_SELECTED had survived longest.
            if(!CreateCustomPriceLine(currentPrice, Digits)) return;
            HandsetMarkersRide();   // the green handle is born with its line
            g_redrawTHLevelsNeeded = true;
            _LOG_GATE_D Print("[D][GEN] [PIN] Custom price set to: ", DoubleToString(currentPrice, Digits), " - Drag to adjust.");
            ThrottledChartRedraw();
            return;
        }

        //  
        // ESC key   Cancel Custom Price
        //  
        if(lparam == 27)
        {
            // P-UI-56: the active test reads THIS CHART's key (the resolver's own
            // owner). Reading the old symbol-scoped key would have made ESC a no-op
            // on a chart whose placement lives under the chart-scoped name.
            bool customPriceActive = GlobalVariableCheck(CustomPriceGVName());
            if(g_waitingForCustomPriceClick || customPriceActive || g_customPriceKeyboardOverride)
            {
                // P-UI-45: the sequence itself lives in ONE owner - the ring's PIN
                // item's OFF press runs the very same one.
                DeactivateCustomPriceMode("ESC");
                ThrottledChartRedraw();
                return;
            }
        }

        //  
        // T key   Toggle Trigger Zones (overlay only — unified lines are
        //         unaffected; line visibility belongs to the L key)
        //
        if(IsHotkeyPressed(lparam, sparam, inpTriggerLevelsKey))
        {
            // P-PERF-32b: ONE owner for the whole transition. This block used to
            // keep its own copy of the state, the persisted key and the render
            // request - the same three lines the ring item and the card's SHOW row
            // kept - and the pixels were the RENDER's to produce, so the press
            // waited for a heavy frame («سطوح تریگر دیر خاموش و روشن میشه»). The
            // owner (SetTriggerLevelsVisible, EventHandlers_Objects) now writes the
            // family's masks through the render's own writer and repaints on the
            // spot, exactly as the structure switches have since P-PERF-32.
            bool tNext = !g_triggerLevelsEnabled;
            RequestUISync();   // P-UI-40: the TRIGGER card's SHOW row + the ring badge
            LOG_I(LOG_CAT_KEYS, tNext ? "Trigger Zones: ON" : "Trigger Zones: OFF");
            // P-KEY-PROBE: the press is the FIRST timestamp of the latency pair; the
            // owner prints `[P-KEY] T applied … ms=` once the pixels are painted, and
            // the frame that reconciles prints `[P-KEY] T settled … ms=` at its own
            // end (EventHandlers_Calc). Both lines are ungated on purpose - one line
            // per key press, and they are the evidence the fix is judged by.
            g_triggerPressMs      = GetTickCount();
            g_triggerPressOn      = tNext ? 1 : 0;
            g_triggerPressHidden  = 0;
            g_triggerPressReached = 0;
            Print("[P-KEY] T press on=", g_triggerPressOn, " zones=", 
                  (tNext ? "show" : "hide"));
            // P-PERF-21: NO force-clear. The overlay owns ONE family - the trigger
            // zones - and RenderZones applies the live flag as a mask itself, so
            // this is a re-render, never a wipe: structure lines, zones and labels
            // are not deleted and re-materialised, and the geometry cache (which no
            // longer keys on the flag) answers with the identical lists instead of
            // recomputing them.
            SetTriggerLevelsVisible(tNext);
            ThrottledChartRedraw();
            return;
        }

        //  
        // A key   Toggle ATR Labels
        //  
        if(IsHotkeyPressed(lparam, sparam, inpATRLabelsKey))
        {
            string atrGvarNameKey = "Biotak_ATRLabels_" + GetCachedChartIdStr();
            g_atrLabelsVisible = !g_atrLabelsVisible;
            RequestUISync();   // P-UI-40: the ATR card's own rows show this switch
            g_showATRLabels = g_atrLabelsVisible;   // keep the ATR card mirror in sync
            GlobalVariableSet(atrGvarNameKey, g_atrLabelsVisible ? 1.0 : 0.0);
            
            string objectPrefix = GetLevelObjectPrefix();
            SetATRLabelsVisibility(objectPrefix, g_atrLabelsVisible); 
            g_labelsRelayoutNeeded = true;
            RedrawLabelsOnly();
            LOG_I(LOG_CAT_LABELS, "ATR Labels " + (g_atrLabelsVisible ? "VISIBLE" : "HIDDEN"));
            ThrottledChartRedraw();
            return;
        }

        //  
        // S key   Cycle TH Labels Mode
        //  
        //
        // D key   Toggle the bar-close countdown tag. Its OWN switch: the ATR
        //         labels key (A) must never take the countdown away, and this
        //         one never touches the ATR block (2026-09-11, user request).
        //  
        if(IsHotkeyPressed(lparam, sparam, inpCountdownKey))
        {
            g_showLiveCountdown = !g_showLiveCountdown;
            RequestUISync();   // P-UI-40: COUNTDOWN card row 0 shows this switch
            RuntimeSettingsSaveOverridesThrottled();   // OV_ CD/CDC/CDS/CDG
            RefreshLiveCountdown();
            LOG_I(LOG_CAT_LABELS, "Countdown tag " + (g_showLiveCountdown ? "VISIBLE" : "HIDDEN"));
            ThrottledChartRedraw();
            return;
        }

        if(IsHotkeyPressed(lparam, sparam, inpTHLabelsKey))
        {
            string thGvar = "Biotak_THLabels_" + GetCachedChartIdStr();
            
            // Cycle exclusive: ON -> OFF (remembers), OFF -> remembered ON (default STANDARD).
            if(g_thLabelsMode != 0) {
                g_thLabelsMode = 0;
            }
            else {
                g_thLabelsMode = g_thLastOnMode;
                if(g_thLabelsMode == 0) g_thLabelsMode = 2;
            }

            g_thLabelsVisible = (g_thLabelsMode != 0);
            RequestUISync();   // P-UI-40: the TH LABELS card cycles on this mode
            SyncTHFlagsFromMode();   // flags follow the mode → card never disagrees
            GlobalVariableSet(thGvar, (double)g_thLabelsMode);
            
            string objectPrefix = GetLevelObjectPrefix();
            SetTHLabelsVisibility(objectPrefix, g_thLabelsMode);
            g_labelsRelayoutNeeded = true;
            RedrawLabelsOnly();
            string logMsg = "TH Labels mode=" + IntegerToString(g_thLabelsMode) + " (0=OFF,1=FRACTAL,2=STANDARD)";
            LOG_I(LOG_CAT_LABELS, logMsg);
            ThrottledChartRedraw();
            return;
        }

        //
        // V key   Toggle TH3 Tool — TH3TOOL-ON (2026-09-19): restored.
        //
#ifndef BUILD_LITE
        if(IsHotkeyPressed(lparam, sparam, inpTH3ToolKey))
        {
            ToggleTH3Tool();
            ThrottledChartRedraw();
            return;
        }
#endif

        //
        // P key   Arm the leg meter (a measurement only).
        // P-TH3-PB-OFF (2026-09-21): the old coupling that stored a dragged leg
        // on the active pattern as its pivot base is retired — the base is
        // hand-typed in the TH3 TOOL card (`inpTH3PivotBasePips`), never drawn.
        //
#ifndef BUILD_LITE
        if((int)lparam == 80)   // 'P' — toggle Leg Measure session (same as ring CIR_LEG)
        {
            LegMeasureToggle();
            ThrottledChartRedraw();
            return;
        }
#endif

        //
        // B key   Arm/cancel the TH3 base mark: two clicks pin the base height
        // (P-TH3-PB-UI) — no drag, so scrolling between the clicks stays free.
        //
#ifndef BUILD_LITE
        if((int)lparam == 66)   // 'B' — arm/cancel the base mark
        {
            TH3BaseMarkToggle();
            ThrottledChartRedraw();
            return;
        }
#endif

        // E key   Cycle Step Mode (TH → SS-LS → Combo → Factor → TH).
        // Single mode: E writes the base directly — same value the Tools
        // ring item and the panel STEP MODE row write. GetCurrentStepMode()
        // just returns it.
        if(IsHotkeyPressed(lparam, sparam, inpStepModeKey))
        {
            RequestUISync();   // P-UI-40: the STEP card's mode row + the ring badge
            g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)(((int)GetCurrentStepMode() + 1) % 4);
            GlobalVariableDel("Biotak_StepMode_" + GetCachedChartIdStr());   // purge retired override key
            RuntimeSettingsSaveOverridesThrottled();   // persist OV_ SM now (E bypasses ApplyRefreshFlags)
            LOG_IP1(LOG_CAT_KEYS, "Step Mode changed to: ", GetStepModeName(GetCurrentStepMode()));
            g_forceClearOnNextDraw = true;
            g_redrawTHLevelsNeeded = true;
            g_calculatedOnce = false;
            RedrawAllObjects(true);
            RefreshComboLabelExtraInfo();
            UpdateStepModeLabel();
            ThrottledChartRedraw();
            return;
        }

        //  
        // 1/2 keys   Adjust Factor (always active)
        //  
        if(lparam == '1') { AdjustFactorValue(-1); return; }
        else if(lparam == '2') { AdjustFactorValue(+1); return; }

        //
        // 3/4 keys   Adjust TH3 Frequency — TH3TOOL-ON (2026-09-19): restored.
        //
#ifndef BUILD_LITE
        else if(lparam == '3') { DecrementTH3Frequency(); return; }
        else if(lparam == '4') { CycleTH3Frequency(); return; }
#endif

        //  
        // W key   Show Current Status
        //  
        if(IsHotkeyPressed(lparam, sparam, inpShowStatusKey))
        {
            RefreshComboLabelExtraInfo();
            ShowAllStatusLabels();
            ThrottledChartRedraw();
            return;
        }

        //  
        // R key   Reset All Overrides
        //  
        if(IsHotkeyPressed(lparam, sparam, inpResetKey))
        {
            // STEPOVERRIDE-OFF: single Step Mode — Q resets the base + levels
            // to factory, like the panel Reset does.
            g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)(int)FactoryDefault(FF_STEP_CALC_MODE);
            g_maxLevels = (int)FactoryDefault(FF_MAX_LEVELS);
            g_comboMode = (ENUM_COMBO_MODE)(int)FactoryDefault(FF_COMBO_MODE);
            g_comboPreset = (ENUM_COMBO_PRESET)(int)FactoryDefault(FF_COMBO_PRESET);
            g_comboComp1TF = (ENUM_COMBO_TIMEFRAME_TYPE)(int)FactoryDefault(FF_COMBO_C1TF);
            g_comboComp1Step = (ENUM_COMBO_STEP_TYPE)(int)FactoryDefault(FF_COMBO_C1STEP);
            g_comboOp1 = (ENUM_COMBO_OPERATION)(int)FactoryDefault(FF_COMBO_OP1);
            g_comboComp2Enabled = (FactoryDefault(FF_COMBO_C2ON) > 0.5);
            g_comboComp2TF = (ENUM_COMBO_TIMEFRAME_TYPE)(int)FactoryDefault(FF_COMBO_C2TF);
            g_comboComp2Step = (ENUM_COMBO_STEP_TYPE)(int)FactoryDefault(FF_COMBO_C2STEP);
            g_factorValueOverride = 0;
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            g_th3FreqOverride = 0;
            g_th3FreqIndex = DEFAULT_TH3_FREQ_INDEX;
#endif
            g_timeframeLocked = false;
            g_lockedPeriod = 0;
            // inpX is the runtime copy after the RuntimeSettings #defines —
            // restoring from the captured factory defaults instead (reading
            // inpX here is a self-assign no-op that kept the current values).
            g_triggerLevelsEnabled = (FactoryDefault(FF_TRIGGER_SHOW) > 0.5);
            // P-PERF-29: same owner as the hotkey and the panel rows, so the
            // restore writes the mask too (it used to leave the objects as they
            // were, which only a timeframe switch repaired).
            SetLinesVisible(FactoryDefault(FF_SHOW_LINES) > 0.5, false);
            InvalidateAllVisibilityCaches();
            g_atrLabelsVisible = (FactoryDefault(FF_SHOW_ATR) > 0.5);
            g_showLiveCountdown = (FactoryDefault(FF_SHOW_COUNTDOWN) > 0.5);
            g_countdownColor = (color)(int)FactoryDefault(FF_COUNTDOWN_COLOR);
            g_countdownFontSize = (int)FactoryDefault(FF_COUNTDOWN_SIZE);
            g_countdownGapPx = (int)FactoryDefault(FF_COUNTDOWN_GAP);
            RefreshLiveCountdown();
            g_thLabelsMode = (FactoryDefault(FF_SHOW_TH_LABELS) > 0.5) ? 2 : 0; // Default STANDARD if enabled
            g_thLabelsVisible = (g_thLabelsMode != 0);
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            if(inpEnableTH3Tool) {
                UpdateAllTH3Objects();
            }
#endif
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            // Cancel any active ABCD drawing session
            if(TH3SessionActive()) {
                TH3SessionCancel();
            }
#endif
            g_customPriceKeyboardOverride = false;
            g_thStartPointType = inpTHStartPointType;
            g_customTHStartPrice = inpCustomTHStartPrice;
            string chartIdStr = GetCachedChartIdStr();
            string symbolName = GetCachedSymbol();
            GlobalVariableDel("Biotak_StepMode_" + chartIdStr);
            // P-UI-67: the reset drops the override through its owner (state + key),
            // so the panel's SS/LS ORDER switch is the answer again.
            SSLSOrderOverrideClear();
            // P-UI-40: the reset key rewrites nearly every displayed state, so
            // the whole UI layer (ring states, badges, the open card) must be
            // told once. This is also how the reset path already behaved when it
            // was reached from the panel (PnlResetItem does exactly this pair).
            RequestUISync();
            GlobalVariableDel("Biotak_Factor_" + chartIdStr);
            GlobalVariableDel("Biotak_LockTF_" + chartIdStr);
            GlobalVariableDel("Biotak_LockTFPeriod_" + chartIdStr);
            // VIEWLOCK-OFF: if(g_viewLockEnabled) ViewLockSetEnabled(false);
            GlobalVariableDel("Biotak_ViewLock_" + chartIdStr);   // VIEWLOCK-OFF: purge only
            GlobalVariableDel("Biotak_ViewAnchorT_" + chartIdStr);
            GlobalVariableDel("Biotak_ViewAnchorMin_" + chartIdStr);
            GlobalVariableDel("Biotak_ViewAnchorMax_" + chartIdStr);
            GlobalVariableDel("Biotak_TriggerLevels_" + chartIdStr);
            GlobalVariableDel("Biotak_LinesVisible_" + chartIdStr);
            GlobalVariableDel("Biotak_ATRLabels_" + chartIdStr);
            GlobalVariableDel("Biotak_THLabels_" + chartIdStr);
            // P-UI-56: the Q reset drops THIS CHART's placement (both keys) through
            // their owner; the Input seed needs no key at all (the resolver reads it
            // directly), so the old "seed the price key from the Input" write is gone
            // - it was the same key that made an Input-seeded chart look like a
            // placement on the chart that shares its symbol.
            CustomPriceForgetPlacement();
            // P-UI-98: the reset returns the step to the mode's own answer too.
            StepOverrideFactorReset();
            // P-UI-98d: the hand-set lines wake ARMED again and their markers go
            // (the redraw below re-creates what the fresh state wants).
            g_cpLineArmed = true;
            g_s1LinesArmed = true;
            g_s1MarkAbovePrice = 0.0;
            g_s1MarkBelowPrice = 0.0;
            ObjectDelete(0, g_cpMarkerName);      CacheRemoveObject(g_cpMarkerName);
            ObjectDelete(0, S1MarkName(1));       CacheRemoveObject(S1MarkName(1));
            ObjectDelete(0, S1MarkName(-1));      CacheRemoveObject(S1MarkName(-1));
            // TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#ifndef BUILD_LITE
            GlobalVariableDel("Biotak_TH3Freq_" + chartIdStr);
            GlobalVariableDel("Biotak_TH3FreqIdx_" + chartIdStr);
#endif
            if(inpCustomTHStartPrice > 0.0) {
                CreateCustomPriceLine(inpCustomTHStartPrice, Digits);
            } else {
                ObjectDelete(0, g_customPriceHorizontalLineName);
                g_customPriceLineCreated = false;
            }
            UpdateLockStatusLabel();
            Comment("\n\n        [ RESET ]");
            g_resetCommentCreateTime = GetTickCount();
            LOG_I(LOG_CAT_KEYS, "Reset: All overrides cleared");
            ClearAllModeLabels();
            EventSetMillisecondTimer(250);   // keep 250 ms cadence (see OnInit)
            g_forceClearOnNextDraw = true;
            g_calculatedOnce = false;
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            ThrottledChartRedraw();
            return;
        }

        //
        // X key   On-demand diagnostic dump ([TRADEPLAN]+[SNAP]+[ATRLEGS]+[PROF*])
        //         No background auto-logging — this key is the only writer.
        //
        if(IsHotkeyPressed(lparam, sparam, inpLogDumpKey))
        {
            TradePlanDumpNow();
            return;
        }

        //
        // K key   Toggle Timeframe Lock
        //  
        if(IsHotkeyPressed(lparam, sparam, inpLockKey))
        {
            bool hadCustomPrice = (ObjectFind(0, g_customPriceHorizontalLineName) >= 0);
            double savedCustomPrice = hadCustomPrice ? ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0) : 0;
            // P-BK-17: the old raw ObjectsDeleteAll(0, inpObjectPrefix) wiped
            // the user's Base/Knot boxes too — and the registry rebuilds from
            // box anchors, so deleted boxes never came back. Guarded loop like
            // DeleteAllIndicatorObjects(false) (inlined: that fn is defined
            // below this caller — P-ARCH-02).
            g_suppressDeleteEvents = true;
            if(StringLen(inpObjectPrefix) > 0) {
               int lkTotal = ObjectsTotal(0, -1, -1);
               int lkPlen = StringLen(inpObjectPrefix);
               for(int lki = lkTotal - 1; lki >= 0; lki--) {
                  string lkName = ObjectName(0, lki, -1, -1);
                  if(StringLen(lkName) < lkPlen) continue;
                  if(StringSubstr(lkName, 0, lkPlen) != inpObjectPrefix) continue;
                  if(StringFind(lkName, "_BK_") >= 0) continue;
                  ObjectDelete(0, lkName);
               }
            }
            g_suppressDeleteEventsUntilMs = GetTickCount() + 250;
            g_suppressDeleteEvents = false;
            g_timeframeLocked = !g_timeframeLocked;
            RequestUISync();   // P-UI-40: the lock badge is derived from this state
            if(g_timeframeLocked)
            {
                g_lockedPeriod = GetCachedPeriod();
                LOG_I(LOG_CAT_KEYS, "Timeframe LOCKED to: " + GetCurrentTimeframe());
                _LOG_GATE_D Print("[D][GEN] [LOCK] Timeframe locked to: ", GetCurrentTimeframe());
            }
            else
            {
                LOG_I(LOG_CAT_KEYS, "Timeframe UNLOCKED - following chart: " + GetCurrentTimeframe());
                _LOG_GATE_D Print("[D][GEN] [UNLOCK] Timeframe unlocked - now following chart timeframe: ", GetCurrentTimeframe());
            }
            UpdateLockStatusLabel();
            string lockChartIdStr = GetCachedChartIdStr();
            string lockFlagName = "Biotak_LockTF_" + lockChartIdStr;
            GlobalVariableSet(lockFlagName, g_timeframeLocked);
            string lockPeriodName = "Biotak_LockTFPeriod_" + lockChartIdStr;
            GlobalVariableSet(lockPeriodName, g_lockedPeriod);
            g_forceClearOnNextDraw = true;
            g_calculatedOnce = false;
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            if(hadCustomPrice && savedCustomPrice > 0) {
                g_customTHStartPrice = savedCustomPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
                // P-UI-48: the owner, not another hand-written property set.
                CreateCustomPriceLine(savedCustomPrice, Digits);
            }
            ThrottledChartRedraw();
            return;
        }

        // VIEWLOCK-OFF: V key (View Lock) retired —
        //if(IsHotkeyPressed(lparam, sparam, inpViewLockKey))
        //{
        //    ViewLockSetEnabled(!g_viewLockEnabled);
        //    LOG_I(LOG_CAT_KEYS, "View Lock " + (g_viewLockEnabled ? "ON - view follows across timeframes" : "OFF - chart behaves normally"));
        //    ThrottledChartRedraw();
        //    return;
        //}
    } // end CHARTEVENT_KEYDOWN

    //
    // Leg Measure MOUSE_MOVE routing — drag-to-draw, runs before ABCD.
    // MOUSE_MOVE is needed so we get left-button press/hold/release edges.
    // P-TH3-PERF-07: CHART_EVENT_MOUSE_MOVE is chart-scoped and shared with
    // the ring, panels and BaseKnot — its ONE writer is OnInitHandler.
    // LegMeasure piggybacks on the existing MOUSE_MOVE stream; no extra flag write.
    //
    // P-UI-98e: a MOTIONLESS press/release emits no MOUSE_MOVE (P-BK-03), so a
    // still click on a step-1 handle would never reach the release latch — the
    // leg meter's own P-LM-13 trap, on the hand-set lines. The click DOES fire
    // CHARTEVENT_CLICK on button-up, and it is the only edge that sees this case.
    //
    if(id == CHARTEVENT_CLICK) Step1ClickFinalize();
    if(id == CHARTEVENT_CLICK) CustomPriceRearmFinalize();   // P-UI-98m: the still click on a SET line
    // P-UI-149/P-UI-151: AND A CLICK THAT LANDS ELSEWHERE GIVES THE REVEAL BACK —
    // every circle's, green included. It runs LAST on this edge on purpose: a click
    // ON a marker row has already been answered by that marker's own contract above
    // (reveal, or the SET candidate), and this owner asks the SAME two hit tests — so
    // the click that reveals can never be the click that hides. The button-up is
    // asked inside; the press's own twin echo touches nothing.
    if(id == CHARTEVENT_CLICK) HandsetRevealDropOnForeignClick((int)lparam, (int)dparam);

#ifndef BUILD_LITE
    if(id == CHARTEVENT_MOUSE_MOVE && LegMeasureSessionActive())
    {
        if(LegMeasureMouseMove((int)lparam, (int)dparam, sparam))
            ThrottledChartRedraw();
        // Do NOT return — ABCD also needs MOUSE_MOVE for its own hover preview.
    }

    // P-LM-11: the leg's EDIT owner. The family is not selectable any more — the
    // line, its two rings and its mid handle are OURS — so the drag is not a
    // native one the terminal reports, it is THIS pass: a press hit-tests the
    // family in screen pixels, and every held move rewrites the whole drawing
    // from the same anchors in the same event. Nothing follows anything, so
    // nothing can lag behind (the report P-LM-10 could only chase).
    if(id == CHARTEVENT_MOUSE_MOVE && LegMeasureEditMouse((int)lparam, (int)dparam, sparam))
        ThrottledChartRedraw();

    // P-LM-08/P-LM-11: the object list is the one native delete the family still
    // answers (nothing of it is selectable) — deleting the LINE there cascades to
    // the rings, the mid handle, the plate and its three lines here.
    if(id == CHARTEVENT_OBJECT_DELETE)
        LegMeasureOnObjectDelete(sparam);

    // P-LM-13: a MOTIONLESS press/release emits no MOUSE_MOVE on release (an MT4
    // fact), but the click still fires CHARTEVENT_CLICK on button-up — so this is
    // where a still press on the family ends. Without it the drag state stuck
    // live: the view lock stayed held, the plate hung, and the Delete key found
    // no selection («چرا نمیشه حذفش کرد»).
    if(id == CHARTEVENT_CLICK) LegMeasureClickFinalize();

    // P-LM-20: the terminal's OWN selection event. A still click on the (now
    // selectable, P-LM-17) line reports OBJECT_CLICK, not a mouse move — so the
    // selection changed between two of our ride passes and the face assembled
    // itself from pieces that disagreed (the line widened while the discs kept
    // the resting rasters: «موقع سلکت دایره‌ها بهم مریزه»). The terminal names
    // the object it selected; the family answers in ONE atomic repaint. A click
    // anywhere ELSE deselects the line, and this is the only handler that sees
    // that path too — a repaint per leg in the registry answers it (the ride
    // pass re-reads every flag, so a cleared selection is painted back).
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(LegMeasureOnObjectClick(sparam)) ThrottledChartRedraw();
        else LegMeasureRideChart();   // a click off the family: deselection lands whole
    }
#endif

    //
    // ABCD Mouse Event Routing — TH3TOOL-ON (2026-09-19): restored.
    // P-TH3-PB-UI: the armed base mark rides the same dispatcher (its CLICK
    // channel), so the router must wake for it even with no draw session.
#ifndef BUILD_LITE
    if(TH3SessionActive() ||
       TH3BaseMarkArmed() ||
       id == CHARTEVENT_OBJECT_DRAG ||
       id == CHARTEVENT_OBJECT_DELETE ||
       id == CHARTEVENT_MOUSE_MOVE) {
        OnABCDMouseEvent(id, lparam, dparam, sparam);
        if((TH3SessionActive() || TH3BaseMarkArmed()) && id == CHARTEVENT_CLICK) {
            return;
        }
    }
#endif

    //  
    // CHARTEVENT_CHART_CHANGE   Layout/Resize/Scroll/Zoom
    //  
    if(id == CHARTEVENT_CHART_CHANGE) {
        if(IsIndicatorHidden()) return;
        HandsetMarkersRide();   // P-UI-98d v2: the handles ride every layout change
        static uint s_lastLayoutMs = 0;
        static int s_lastW = -1;
        static int s_lastH = -1;
        static double s_lastVisibleMin = 0;
        static double s_lastVisibleMax = 0;
        static bool s_ccPrimed = false;   // P-PERF-28
        uint nowMs = GetTickCount();
        if(nowMs - s_lastLayoutMs < CHART_CHANGE_THROTTLE_MS) return;

        int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
        int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
        bool sizeChanged = (w != s_lastW || h != s_lastH);
        
        double visibleMin = ChartGetDouble(0, CHART_PRICE_MIN);
        double visibleMax = ChartGetDouble(0, CHART_PRICE_MAX);
        bool viewportChanged = (MathAbs(visibleMin - s_lastVisibleMin) > GetCachedPoint() ||
                                MathAbs(visibleMax - s_lastVisibleMax) > GetCachedPoint());
        // P-PERF-28: on the FIRST chart-change of an instance the snapshot is
        // still at its zero value, so `visibleMin - 0` is always > one point and
        // `viewportChanged` was unconditionally TRUE. That ran a full
        // RedrawAllObjects(false) inside the event on every attach and every
        // timeframe switch — the live log charges it to the event as
        //   [W][PERF] chart event id=9 [indicator=3375 ui=0] took 3375ms
        // (and 3750/3938/3766/3734/4063 ms in the same session, 53 such events
        // in one day). Nothing had actually changed: this instance's own initial
        // draw already covers the viewport it is looking at. Prime the snapshot
        // from the live chart instead of from 0 and the first event is a no-op.
        if(!s_ccPrimed)
        {
            s_ccPrimed = true;
            viewportChanged = false;
        }
        
        if(!sizeChanged && !viewportChanged) return;
        
        s_lastW = w;
        s_lastH = h;
        s_lastVisibleMin = visibleMin;
        s_lastVisibleMax = visibleMax;
        s_lastLayoutMs = nowMs;
        // VIEWLOCK-OFF: if(g_viewLockEnabled) ViewLockCapture();

        // P-PERF-28b: this branch was the biggest single stall in the log yet
        // had no sub-ledger of its own, so the named owner can only be guessed.
        // Split it the way every other ledger here is split, and only print
        // when the branch blows the event budget.
        uint p28t = GetTickCount();
        uint p28redraw = 0, p28labels = 0, p28leg = 0;
        if(sizeChanged) g_labelsRelayoutNeeded = true;
        if(viewportChanged) {
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(false);
            p28redraw = GetTickCount() - p28t;
        } else if(sizeChanged) {
            RedrawLabelsOnly();
            p28labels = GetTickCount() - p28t;
        }
        p28t = GetTickCount();
        // The live-price countdown tag is positioned off the price scale, so a
        // scroll/zoom/resize invalidates its Y even with zero ticks (weekend
        // charts). Re-derive it here, AFTER the redraws above (a label clear
        // would otherwise eat it) — the label pipeline itself is 2 s gated, so
        // this hook is what keeps the tag glued during a drag-scroll. Own
        // switch: never gated by the ATR block (2026-09-11).
        RefreshLiveCountdown();
        uint p28count = GetTickCount() - p28t;
        p28t = GetTickCount();
        // P-LM-02: the leg-measure readouts are SCREEN objects, so the chart moving
        // under them does not move them — and this branch is the one place that
        // already answers "the chart moved" (scroll, zoom, resize, auto-scroll).
        // The projection is READ-GUARDED: a box already where it belongs costs a
        // handful of terminal reads and not one ObjectSet* (P-PERF-02).
#ifndef BUILD_LITE
        LegMeasureFollowAll();
#endif
        p28leg = GetTickCount() - p28t;
        p28t = GetTickCount();
        ThrottledChartRedraw();
        uint p28paint = GetTickCount() - p28t;
        if(p28redraw + p28labels + p28leg + p28count + p28paint >= P_P4_EVENT_WARN_MS)
        {
            // P-PERF-49 (2026-09-16) - `tail=` HAD NO OWNER, AND IT WAS THE WHOLE
            // STALL. The live MT5 log:
            //   chart change breakdown: redraw=0ms labels=390ms tail=3016ms
            //   chart event CHART_CHANGE(id=9) [indicator=3485 ...] took 3485ms
            // so P-PERF-28b's split ended exactly where the biggest number began:
            // the tail is RefreshLiveCountdown() + ThrottledChartRedraw(), and 3016
            // of the 3485 ms sat in whichever of those two it was. They are two
            // different problems - one rebuilds a label, the other asks the
            // TERMINAL to repaint a chart carrying 500-850 objects (ChartRedraw is
            // 2.14 us on an idle chart and is priced per OBJECT on a full one) - so
            // they get a field each. A number without a cause is what this project
            // refuses to act on.
            //
            // THE SECOND FIELD NAMES THE PASS `redraw=` PAID FOR: the per-phase
            // ledger P-PERF-03 already keeps (EventHandlers ~1745..2036) describes
            // the very RedrawAllObjects() call made nine lines above, so it is read
            // here instead of duplicated. On MT5 that is the difference between
            // "a scroll costs 328 ms" and "the LEVELS block of that pass is 328 ms".
            //
            // READ THE NUMBERS AS TICK-QUANTIZED: GetTickCount() steps in Windows'
            // ~15.6 ms tick, so every ms in this ledger is n x 15.625 (the day's
            // 694 lines carry 56 distinct values and they are exactly that set).
            // A phase under one tick reads 0 ms; the ordering is trustworthy, the
            // absolute value is +/- one tick. Anything finer needs
            // GetMicrosecondCount(), which is MT5-only - see the next step.
            string renderSplit = " render[levels=" + IntegerToString((int)g_p3MsLevels) +
                                 " labels=" + IntegerToString((int)g_p3MsLabels) +
                                 " overlay=" + IntegerToString((int)g_p3MsOverlay) +
                                 " base=" + IntegerToString((int)g_p3MsBase) +
                                 " atr=" + IntegerToString((int)g_p3MsAtr) +
                                 " hist=" + IntegerToString((int)g_p3MsHistory) + "]";
            _LOG_GATE_W Print("[W][PERF] chart change breakdown: redraw=", (int)p28redraw,
                  "ms labels=", (int)p28labels, "ms leg=", (int)p28leg,
                  "ms tail=", (int)(p28count + p28paint),
                  "ms [count=", (int)p28count, " paint=", (int)p28paint, "]", renderSplit);
        }
        return;
    }

    //  
    // CHARTEVENT_CLICK   Custom Price Click
    //  
    // P-UI-92: the pick mode's click must be a CHART click. CLICK carries the price
    // under the cursor, so a click on an open card/strip/menu used to set the custom
    // price origin from the price hidden under that control (and the panel's own
    // press was handled in the UI half of the same event, which runs after this one).
    // Two tests, one rule (see UIPointerOverSurface): WHERE the release landed, and
    // WHOSE release it is (a claim the UI published before this half ran).
    if(id == CHARTEVENT_CLICK && g_waitingForCustomPriceClick &&
       !UIPeekClickClaim() && !UIPointerOverSurface((int)lparam, (int)dparam))
    {
        if(StringFind(sparam, "r") >= 0)
        {
            CleanupCustomPriceObjects(true, true);
            _LOG_GATE_D Print("[D][GEN] Custom price setting cancelled (right-click)");
            ThrottledChartRedraw();
            return;
        }
        double clickedPrice = dparam;
        if(!g_customPriceLineCreated)
        {
            if(!CreateCustomPriceLine(clickedPrice, Digits)) return;
            _LOG_GATE_D Print("[D][GEN] [PIN] Drag the orange dotted line to adjust price. Double-click to confirm.");
        }
        else
        {
            uint currentTickCount = GetTickCount();
            bool isDoubleClick = (currentTickCount - g_lastClickTickCount < DOUBLE_CLICK_THRESHOLD_MS);
            g_lastClickTickCount = currentTickCount;
            if (isDoubleClick || !g_customPriceLineCreated)
            {
                g_waitingForCustomPriceClick = false;
                g_customPriceKeyboardOverride = true;
                double selectedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
                g_customTHStartPrice = selectedPrice;
                g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
                CustomPricePersistPlacement(selectedPrice);   // P-UI-56: one writer
                // P-UI-98d: the confirm IS the placement's SET — the price is
                // final, the line goes inert, the double-click re-arms it. The
                // CREATE case (no line yet) stays armed: the fresh line must
                // drag freely until its own double-click confirms.
                if(g_customPriceLineCreated) g_cpLineArmed = false;
                // P-UI-45: settle - the line KEEPS its price and becomes inert again
                // (see CreateCustomPriceLine). Confirming must not leave it grabbed:
                // a selection outlives the gesture, and MT4 then drags the line on
                // every later drag anywhere on the chart.
                CreateCustomPriceLine(selectedPrice, Digits);
                g_redrawTHLevelsNeeded = true;
                RedrawAllObjects(true);
                _LOG_GATE_I Print("[I][GEN] Custom Price Mode activated! Using ", inpMaxLevels, " levels above/below price: ", DoubleToString(selectedPrice, Digits));
            }
        }
        ThrottledChartRedraw();
    }

    //  
    // CHARTEVENT_OBJECT_CLICK   Custom Price Line / ABCD Pattern
    //  
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_customPriceHorizontalLineName)
    {
        uint currentTickCount = GetTickCount();
        bool isDoubleClick = (currentTickCount - g_lastClickTickCount < DOUBLE_CLICK_THRESHOLD_MS);
        g_lastClickTickCount = currentTickCount;
        // P-UI-45: MT4 selects a selectable line on the press that grabs it, and a
        // SELECTED line is dragged by MT4 on every later drag anywhere on the chart.
        // Arm the deferred clear instead of writing the property HERE: this event
        // may arrive on the press, and clearing it then would drop the line out of
        // the very drag the user is starting.
        if(!isDoubleClick) g_customPriceNativeDrag = true;
        if (isDoubleClick)
        {
            // P-UI-98d: a SET line wakes on the double-click — silent, no
            // prompt: the SS/LS selector below belongs to a live line, and the
            // user's order names the double-click as the re-arm gesture.
            if(!g_cpLineArmed)
            {
                CustomPriceLineOwnArm(true);
                // P-UI-98g: re-armed AND revealed - the double-click is the user
                // asking for the handle back, so the circle comes with it.
                g_cpHandleShown = true;
                CustomPriceMarkerSync();
                ThrottledChartRedraw();
                return;
            }
            // A double-click on Custom Price is a fast SS/LS start selector.
            // The price remains unchanged; only the sequence origin changes.
            int selectedStart = MessageBox("SS/LS sequence start\n\nYes = LS first\nNo = SS first\nCancel = keep current",
                                           "Select SS/LS start", MB_YESNOCANCEL | MB_ICONQUESTION);
            // P-UI-67: the prompt is the per-chart OVERRIDE's owner (state + key in
            // one place, next to the getter that consults it). IDCANCEL keeps the
            // current answer, so it writes nothing.
            if(selectedStart == IDYES) SSLSOrderOverrideSet(1);
            else if(selectedStart == IDNO) SSLSOrderOverrideSet(0);
            g_waitingForCustomPriceClick = false;
            g_customPriceKeyboardOverride = true;
            double selectedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
            g_customTHStartPrice = selectedPrice;
            g_thStartPointType = TH_START_POINT_CUSTOM_PRICE;
            CustomPricePersistPlacement(selectedPrice);   // P-UI-56: one writer
            // P-UI-45/P-UI-48: settle - the line KEEPS its price and stays
            // grabbable (same owner as the chart-click confirm above).
            CreateCustomPriceLine(selectedPrice, Digits);
            g_redrawTHLevelsNeeded = true;
            RedrawAllObjects(true);
            _LOG_GATE_I Print("[I][GEN] Custom Price Mode activated! Using ", inpMaxLevels, " levels above/below price: ", DoubleToString(selectedPrice, Digits));
        }
        else if(g_cpLineArmed)
        {
            // P-UI-98g: THE FIRST CLICK SHOWS THE HANDLE. «فقط وقتی روش کلیک کردیم
            // دایره ها بیاد برای درگ کردن» — armed only means grabbable; the green
            // circle is painted once the user asks for it, and asking is this click.
            // It is not a SET: committing a line the user has not touched yet would
            // make the first click cost a double-click to undo.
            if(!g_cpHandleShown)
            {
                g_cpHandleShown = true;
                CustomPriceMarkerSync();
                ThrottledChartRedraw();
            }
            // P-UI-98d: a click on an ALREADY-SHOWN armed line is the SET candidate —
            // deferred past the double-click window (the sweep commits it), so the
            // first click of a double never sets first. A click that is the ECHO of
            // a drag release (the just-dragged stamp) sets nothing: the line drags
            // freely until the user deliberately clicks it.
            else if(currentTickCount - g_cpJustDraggedMs > 350)
            {
                g_cpSetPending = sparam;
                g_cpSetPendingMs = currentTickCount;
            }
        }
    }

    //
    // CHARTEVENT_OBJECT_CLICK   Step-1 handle: click = SET, double-click = re-arm
    //
    // P-UI-98d: the same contract the custom price line wears. While ARMED the
    // handle drags (the P-UI-98 OBJECT_DRAG channel recomputes the factor live);
    // a single click SETS it (the ladder keeps the dragged step, the handle
    // turns inert, the red dot goes); a double-click re-arms it. A click that is
    // the echo of a drag release sets nothing.
    if(id == CHARTEVENT_OBJECT_CLICK && Step1LineIsDragHandle(sparam))
        Step1HandleClickAt(sparam);   // P-UI-98e: the ONE click contract (the
                                      // terminal's own report is now one of three
                                      // edges; the dedupe drops its twin)

    // P-UI-98m: the green circle's own report - the third edge of the SET
    // line's re-arm contract (the masked line fires none itself). The 60 ms
    // twin guard inside drops the duplicate when the row pair already saw it.
    if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_cpMarkerName)
        CustomPriceRearmClickAt();

    //
    // CHARTEVENT_MOUSE_MOVE   Custom Price Drag Detection
    //
    // P-UI-98d: the double-click window's sweeper rides the mouse stream — the
    // cheapest always-on channel there is (two stamp compares when nothing is
    // pending). The tick path sweeps too, so a click that never moves again
    // still commits. And the handset handles ride the same stream (a pan moves
    // the price scale under them — the leg meter's own P-LM-16b answer).
    HandsetClickSweep();
    HandsetMarkersRide();
    // P-UI-98e: the step-1 handle's gesture walks the same stream as the
    // custom-price line's — and the custom-price line is not the only reason
    // this block exists any more: the handle is armed off the PLACEMENT, and a
    // chart that lost the line object must not lose the handle with it.
    // P-SIZE-1500: the custom price line's own gesture stream (press edge, claim,
    // carry, release, tooltip) moved to its own owner above -
    // EventHandlers_Router_Gesture.mqh, called at the exact seat it held.
    RoutCustomPriceGesture(id, lparam, dparam, sparam);

    //  
    // CHARTEVENT_OBJECT_DRAG   Custom Price Line Drag End
    //  
    if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_customPriceHorizontalLineName)
    {
        // P-UI-51: THE GESTURE FLAG BELONGS TO THE PRESS EDGE AND THE RELEASE,
        // NEVER TO THIS EVENT.
        //
        // This event is CONTINUOUS while MT4 drags the line, and the handler used
        // to clear g_customPriceLineDragging on every step of it. The mouse-move
        // path reads that flag as "the grab is decided, this gesture is mine":
        // cleared per step, its grab block re-ran per step and RE-ARMED the
        // carry's reference (s_ownGrabPrice) to the line's CURRENT price - so the
        // frozen test that keeps our writes off a live terminal drag
        // (|linePrice - reference| < half a point, P-BK-16's shape) compared the
        // price with ITSELF, always passed, and handed the line a fresh
        // OBJPROP_PRICE in the middle of the very drag MT4 was performing. MT4
        // cancels an in-progress native drag when the dragged object is rewritten
        // mid-gesture (P-BK-15): the line snapped back to the drag start, which is
        // the reported "the drag state is cut off very quickly / it cannot be
        // dragged". Leaving the flag alone for the whole gesture is also what
        // makes the carry stand down the moment the terminal moves the line
        // itself - one write per fallback gesture instead of one per step.
        // P-UI-45: MT4 keeps the object SELECTED after a native drag. Clearing it
        // HERE would let go of the line under the user's hand (this event is
        // CONTINUOUS while dragging), so the clear is deferred to the first
        // button-up mouse move - see g_customPriceNativeDrag below.
        g_customPriceNativeDrag = true;
        double draggedPrice = ObjectGetDouble(0, g_customPriceHorizontalLineName, OBJPROP_PRICE, 0);
        // P-UI-61: the anchor AND its persist are the one owner's now. The persist
        // used to live HERE only, which is exactly why the CARRY channel's key went
        // stale and the release re-anchored the ladder to it (the P-UI-56 writer is
        // still the only thing that writes the pair - one call, one place).
        bool anchorMoved = CustomPriceDragAnchorSet(draggedPrice);
        CustomPriceMarkerSync();   // P-UI-98d: the green dot follows the native drag (one guarded write)
        // P-UI-49: NO property write on the line HERE - the tooltip text is
        // written once at the release instead (UpdateCustomPriceTooltip). This
        // handler runs on EVERY step of a native drag, and MT4 cancels an
        // in-progress native drag when the dragged object is rewritten
        // mid-gesture (P-BK-15), so the tooltip write that used to sit here
        // cancelled the drag it was decorating: the line never followed the
        // cursor. Read-only + state, nothing on the object while the button is
        // down.
        if(!g_waitingForCustomPriceClick)
            _LOG_GATE_D Print("[D][GEN] Custom TH start price updated to: ", DoubleToString(draggedPrice, Digits));
        // P-UI-52: NO WIPE PER STEP - the live follow is an IN-PLACE re-assert.
        //
        // This handler used to raise `g_forceClearOnNextDraw` on every step of a
        // native drag, and that flag is the WIPE: `shouldClearLevels` calls
        // ClearAllLevels (every level, zone and label family deleted) and restarts
        // the four-frame staged rebuild. Per drag step that is hundreds of deletes
        // and re-creates for a picture that moved by one pixel - the family blinked
        // and lagged behind the line instead of following it, which is the cost the
        // report pays for "the levels do not move with the line". Nothing about a
        // move changes the TOPOLOGY, so the wipe is not needed to re-draw it: with
        // the start price now in the geometry signature the render re-derives the
        // levels and re-asserts the same object NAMES in place (no orphans - the
        // pipeline's own surplus pass owns the extras, already drag-throttled), and
        // the AUTHORITATIVE rebuild is the release: the button-up branch of the
        // drag's mouse-move handler raises the clear together with the frame, so
        // the settled picture is a full, staged, exact rebuild - the "settle at
        // the end" the report asks for, unchanged. Cost: strictly less work per
        // step (no wipe, no staged rebuild) and the same single frame per 50 ms.
        // P-UI-51: with the gesture flag alive for the whole drag (above), a forced
        // frame from here runs INLINE (the P-PERF-34 drag exemption) on EVERY step
        // MT4 reports. The live follow already spends that exemption from the
        // mouse-move path, so this channel shares its budget: one frame per window
        // across both channels - the cadence the drag already had, and strictly
        // less work than one frame per reported step.
        // P-UI-61: and that budget now has ONE owner, so a step whose anchor did not
        // move costs nothing at all instead of one more full pass.
        if(anchorMoved) CustomPriceDragFrame(false);
    }

    // P-UI-98: the step-1 handle's own drag channel. Continuous while MT4 moves
    // the line; each step recomputes the override factor and shares the ONE
    // frame budget (see the section above for the three P-BK-15 rules).
    if(id == CHARTEVENT_OBJECT_DRAG && Step1LineIsDragHandle(sparam))
        Step1LineDragApply(sparam);

    // VIEWLOCK-OFF: anchor-line drag retired —
    //if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_viewAnchorLineName && g_viewLockEnabled)
    //{
    //    datetime droppedTime = (datetime)ObjectGetInteger(0, g_viewAnchorLineName, OBJPROP_TIME, 0);
    //    if(droppedTime > 0 && droppedTime != g_viewAnchorTime)
    //    {
    //        g_viewAnchorTime = droppedTime;
    //        ViewLockPersistAnchor();
    //        if(ViewLockRestore()) g_viewRestorePending = false;
    //        else g_viewRestorePending = true;   // history not ready — retry next ticks
    //        ThrottledChartRedraw();
    //    }
    //    return;
    //}

    //
    // CHARTEVENT_OBJECT_CLICK   ABCD Pattern Selection — TH3TOOL-ON (2026-09-19): restored.
#ifndef BUILD_LITE
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(StringFind(sparam, "ABCD_Pattern_") == 0)
        {
            string patternName = "";
            int suffixPos = -1;
            if(StringFind(sparam, "_Point_") > 0) suffixPos = StringFind(sparam, "_Point_");
            else if(StringFind(sparam, "_Label_") > 0) suffixPos = StringFind(sparam, "_Label_");
            else if(StringFind(sparam, "_Line_") > 0) suffixPos = StringFind(sparam, "_Line_");
            else if(StringFind(sparam, "_Target_") > 0) suffixPos = StringFind(sparam, "_Target_");
            else if(StringFind(sparam, "_Zone") > 0) suffixPos = StringFind(sparam, "_Zone");
            if(suffixPos > 0) {
                patternName = StringSubstr(sparam, 0, suffixPos);
            } else {
                patternName = sparam;
            }
            if(patternName != "") {
                SetActiveABCDPattern(patternName);
            }
        }
        // P-TH3-BANDSEL (2026-09-22): the TH3 tool's OWN objects are not a
        // deselection. Clicking the base editor band — and the click echo that
        // follows EVERY band drag's button-up — fell in here, blanked the
        // active pattern, masked its ladder and dropped its caption plate, and
        // the next band re-step redraw kept them dark: the whole ABCD read as
        // deleted («بیس مبنا که میکشم ... باعث حذف abcd میشه»). The band, its
        // "1" tag, the P6 pivot triangles and the TH3_MP_ mother overlay are
        // the pattern's own tooling — a click on any of them is a no-op here.
        else if(StringFind(sparam, "TH3_") != 0)
        {
            SetActiveABCDPattern("");
        }
    }
#endif
}
#endif // EVENT_HANDLERS_ROUTER_MQH
