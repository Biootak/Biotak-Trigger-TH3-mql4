// TH3Renderer_B.mqh - TH3Renderer.mqh split 2026-09-29: exact lines 969-2355, byte-identical, zero renames.
#ifndef TH3_RENDERER_B_MQH
#define TH3_RENDERER_B_MQH

void DrawABCDPattern(string mainObjName, datetime tA, double pA, datetime tB, double pB,
                     datetime tC, double pC, datetime tD = 0, double pD = 0)
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawABCDPattern called | Name: ", mainObjName);
    Print("   A: ", TimeToString(tA), " @ ", DoubleToString(pA, Digits));
    Print("   B: ", TimeToString(tB), " @ ", DoubleToString(pB, Digits));
    Print("   C: ", TimeToString(tC), " @ ", DoubleToString(pC, Digits));
    Print("   D: ", TimeToString(tD), " @ ", DoubleToString(pD, Digits));
    #endif
    
    if(tD <= 0 || pD <= 0) {
        if(!CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== CalculateABCDPointD failed - cleaning up temp objects");
            #endif
            
            // Cleanup partial objects
            string pointNames[5] = {"X", "A", "B", "C", "D"};
            for(int i = 0; i < 5; i++) {
                ObjectDelete(0, mainObjName + "_Point_" + pointNames[i]);
                ObjectDelete(0, mainObjName + "_Label_" + pointNames[i]);
            }
            ObjectDelete(0, mainObjName + "_Line_XA");
            ObjectDelete(0, mainObjName + "_Line_AB");
            ObjectDelete(0, mainObjName + "_Line_BC");
            ObjectDelete(0, mainObjName + "_Line_CD");
            ObjectDelete(0, mainObjName + "_Ray_D");
            ObjectDelete(0, mainObjName + "_Ray_C");
            ObjectDelete(0, mainObjName + "_CDLabel");
            ObjectDelete(0, mainObjName + "_MPTick");
            ObjectDelete(0, mainObjName + "_MPTickB");
            for(int _i = 0; _i < TH3_PIVOT_BASE_LEVELS; _i++) {
                ObjectDelete(0, mainObjName + "_PBLine_"  + IntegerToString(_i));
                ObjectDelete(0, mainObjName + "_PBLabel_" + IntegerToString(_i));
            }
            TH3InfoFamilyDelete(mainObjName);   // P-TH3-INFO-01: the whole caption family
            return;
        }
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== Point D: ", TimeToString(tD), " @ ", DoubleToString(pD, Digits));
    #endif
    
    double AB_Distance = MathAbs(pB - pA);
    double BC_Distance = MathAbs(pC - pB);
    double CD_Distance = MathAbs(pD - pC);
    bool dirDown = (pD > pC);   // D is a high, reversal runs down; if D is a low (pD < pC), reversal runs up
    bool isBullish = !dirDown;
    double frequency = GetCurrentTH3Frequency();

    // The ABCD pattern completes at Point D (tD, pD).
    // Closed legs: impulse leg CD and prior retracement leg BC.
    double closedStep = 0, closedK = 0, closedRatio = 0;
    bool closedOK = TH3ClosedStepFromLegs(pB, pC, pD, closedStep, closedK, closedRatio);
    int cdBars = TH3ClosedBars(tC, tD);
    int ownerTF = TH3ClosedOwnerTF(cdBars);
    double seedRung = TH3PatternStepRungTF(ownerTF);
    if(seedRung <= 0) seedRung = TH3PatternStepRung();
    double pip0 = GetCachedPipSize();   // local: the seed/lock blocks sit above pipSize's decl
    if(pip0 <= 0) pip0 = Point;

    // P-TH3-STEP-16 (2026-10-05) — THE UNIFIED EQUATION. One formula, no
    // branches: the B-marked mother (mandatory anchor) and the ABCD leg
    // resonate geometrically (CalculateUnifiedMasterStep, TH3Pivots_B.mqh).
    // TH3ClosedK above stays as the lock's diagnostic reference only — the
    // decider ladder is TH3UnifiedK inside the function.
    double motherSize = TH3ManualBaseStep(inpTH3PivotBasePips, pip0);
    double uniRatio = (closedOK ? closedRatio : 0.0);
    if(!closedOK && BC_Distance > 0 && CD_Distance > 0)
        uniRatio = CD_Distance / BC_Distance;
    double uniK = TH3UnifiedK(uniRatio);
    double baseUnit = 0;
    string seedHow = "";
    double uniStep = CalculateUnifiedMasterStep(CD_Distance, uniRatio, motherSize, seedRung);
    if(uniStep > 0) {
        baseUnit = uniStep;
        seedHow = StringFormat("uni K=%.1f pat=%.1f mom=%.1f th=%.1f%s", uniK,
                               CD_Distance / pip0, motherSize / pip0, seedRung / pip0,
                               (ownerTF != Period() ? " up" : ""));
    } else if(seedRung > 0) {
        baseUnit = seedRung;
        seedHow = (ownerTF != Period()
                   ? StringFormat("TH rung up %s", TH3TfName(ownerTF))
                   : "TH rung");
    }
    bool atrBasis = (baseUnit > 0);
    if(!atrBasis) baseUnit = (CD_Distance > 0 ? CD_Distance : AB_Distance) * (frequency / 100.0);

    // P-TH3-PB-MAN (2026-09-21) — PATH 1 IS HAND-TYPED, NOT DRAWN.
    // The user types the pivot base's height in the TH3 TOOL card, in pips
    // (`inpTH3PivotBasePips`); TH3ManualBaseStep turns it into a price and it
    // enters TH3LockedStep as pbStep. 0 = OFF: no Path 1 at all, and the seed
    // below (the pattern TF's own ATR) is the whole answer — which is the
    // "default from the same timeframe's ATRs" the user asked for. The
    // detector's own candidate (TH3NodeStepAt) no longer answers the LOCK: a
    // hand-typed number is an instruction, a scanned one is not, and the two
    // must never be averaged into each other. (The detector still answers the
    // SEED above, as the synthesis' mother factor.)
    // P-TH3-PB-RET8 (2026-09-22) — THE TYPED NUMBER IS A RETRACE: one R wears
    // eight candidate steps (TH3RetraceBestStep, TH3Pivots.mqh). The winner is
    // the candidate nearest the ABCD step (closedStep: pattern momentum, 60%)
    // and the owner TF's rung (seedRung: fractal volatility, 40%) — the TF
    // comparison rides inside those two anchors, so no new bar read is added.
    // The ref is CLOSED step, never the synthesis: synth already blends TH and
    // the mother, so anchoring Path 1 to it and then locking Path 1 against it
    // is a circle that fires LOCKED by construction. ABCD-anchored Path 1 vs
    // synthesis Path 2 lets TH3LockedStep arbitrate two INDEPENDENT answers.
    // The caption words it as `ret <q>`.
    double pbRaw = motherSize;  // same hand thickness the synthesis above consumes
    double pbStep = pbRaw;
    string retHow = "";
    if(pbRaw > 0)
    {
        double retRef = (closedOK && closedStep > 0 ? closedStep : 0.0);
        double bS = 0, bQ = 0; int bI = -1;
        if(TH3RetraceBestStep(pbRaw, retRef, seedRung, bS, bQ, bI) && bS > 0)
        {
            pbStep = bS;
            retHow = StringFormat("ret %s", TH3RetraceQName(bI));
        }
    }

    // P-TH3-STEP-16: the lock is now a SECOND OPINION, never the decider.
    // The unified step above stands; this verdict (does the hand base agree
    // with it?) is logged in TH3LOG and captioned, never applied.
    bool stepLocked = false;   // the verdict is carried by `lockHow`'s own word
    string lockHow = "";
    double lockedUnit = 0.0;
    TH3LockedStep(lockedUnit, lockHow, stepLocked,
                  baseUnit, pbStep, 0.0,
                  ownerTF, Period(), pip0);
    if(lockHow != "") seedHow += " | " + lockHow;
    if(retHow != "") seedHow += " | " + retHow;

    // Reaction proof from Point D — DIAGNOSTIC ONLY (P-TH3-STEP-16). The
    // reaction no longer moves the ladder; the unified step stands. The vote
    // is still measured, printed and logged (TH3LOG proof/deep) so the chart
    // says whether the market confirmed the equation's answer.
    TH3HitProof hitProof;
    bool hitOK = TH3HitPivotMeasure(tD, pD, dirDown, baseUnit,
                                    hitProof, (closedOK ? closedStep : 0.0));
    // P-TH3-STEP-04e: when no reaction has voted, the label says how far the
    // reaction DID reach, against the floor — the difference between "nothing
    // reacted" and "the walk never ran" was invisible before this number.
    string stepHow = StringFormat("%s; reaction %.2f/%.2f rungs",
                                   seedHow, hitProof.deepestRungs, TH3_STEP_MIN_LEG_RUNGS);
    string hitOwnerTF = "";
    // P-TH3-STEP-09 (BUG B): the vote refines the seed only inside ±25% —
    // the measure already enforces this gate; this second lock stands for
    // any future caller that skips the refStep. A refused vote keeps seed.
    if(hitOK && closedOK && closedStep > 0
       && MathAbs(hitProof.step - closedStep) / closedStep > TH3_HIT_MAX_STEP_ERR)
        hitOK = false;
    if(hitOK) {
        // P-TH3-STEP-16: NO overwrite — the unified step stands; the vote below
        // is corroboration (diagnostic), never the decider.
        hitOwnerTF = (hitProof.hasPivot ? TH3TfName(hitProof.pivTF) : "");
        stepHow = hitProof.hasPivot
                ? StringFormat("T3@%s err %.1f%% x%d", hitOwnerTF,
                               hitProof.rungErr * 100.0, hitProof.touches)
                : StringFormat("T3 reaction x%.2f", hitProof.step / hitProof.rung);
        // which grid does the proved step belong to? Walk the fractal chain
        // up and keep the TF whose own rung sits nearest the step — the
        // user's "شاید مال تایم بزرگ‌تر باشه", answered with numbers. When no
        // six-condition pivot sat on the tip, a bigger TF that still CLAIMS it
        // names the grid in the verdict too (the arithmetic stays the tip's).
        string owner = "";
        double bestR = 1e9;
        int tfWalk = Period();
        for(int w = 0; w < 6; w++) {
            // P-TH3-STEP-08: rungs are TH of their own TFs — same ruler as
            // the ladder (last completed bar of each).
            double r = TH3PatternStepRungTF(tfWalk);
            if(tfWalk != Period() && hitOwnerTF == "" && r > 0) {
                double claimed = 0;
                if(TH3SixPivotsHasPivotAt(tfWalk, hitProof.tipTime, hitProof.tipPrice,
                                          0.5 * r, claimed)) {
                    hitOwnerTF = TH3TfName(tfWalk);
                    stepHow = StringFormat("T3 reaction x%.2f <- %s grid",
                                           hitProof.step / hitProof.rung, hitOwnerTF);
                }
            }
            if(r > 0) {
                double ratio = hitProof.step / r;
                if(MathAbs(ratio - 1.0) < bestR) {
                    bestR = MathAbs(ratio - 1.0);
                    owner = StringFormat("%s x%.2f", THRungNameForTFMin(tfWalk), ratio);
                }
            }
            int up = TH3FractalStepTF(tfWalk, 1);
            if(up == tfWalk) break;
            tfWalk = up;
        }
        Print("TH3: step proof - tip ", DoubleToString(hitProof.tipPrice, Digits),
              " (", (hitProof.pivIsHigh ? "HIGH" : "LOW"), "), step=",
              DoubleToString(hitProof.step / GetCachedPipSize(), 1),
              " pips vs rung ", DoubleToString(hitProof.rung / GetCachedPipSize(), 1),
              " pips (x", DoubleToString(hitProof.step / hitProof.rung, 2), ") ",
              (hitProof.hasPivot ? "on a six-condition pivot" : "- no pivot at the tip"),
              (hitProof.hasPivot ? StringFormat(", err %.1f%%, %d touch(es)",
                                                hitProof.rungErr * 100.0, hitProof.touches) : ""),
              ", grid: ", owner);
    }
    else {
        // P-TH3-STEP-04e: the rejection is logged with its own number, so the
        // chart's own log says whether the ladder is on its seed because the
        // market has not reacted or because the walk was never reached.
        Print("TH3: step not proved - deepest reaction ",
              DoubleToString(hitProof.deepestRungs, 2), " rungs of the ",
              DoubleToString(TH3_STEP_MIN_LEG_RUNGS, 2), " the vote needs; seed ",
              seedHow, " ",
              DoubleToString(baseUnit / GetCachedPipSize(), 1),
              " pips stays the step (thin market / young reaction).");
    }

    // P-TH3-LOG1 (2026-09-22) — THE FEEDBACK LOOP, ONE LINE PER VERDICT.
    // The user marks the chart (ABCD + BASE PIPS) and sends screenshots; the
    // formula updates off DATA, so every input and every verdict lands in the
    // Experts log in one parseable shape (tools/th3_log_collect.py reads it
    // back into CSV: q distribution, lock rate, step-vs-closed bias). Ring of
    // 8 verdict keys: drags and ticks re-derive the same answer for free.
    {
        string logQ = (retHow == "" ? "off" : StringSubstr(retHow, 4));
        string logKey = StringFormat("%s|%.1f|%.1f|%.1f|%s|%d|%.1f|%d",
                                     mainObjName, pbRaw / pip0,
                                     (closedOK ? closedStep / pip0 : 0.0),
                                     seedRung / pip0, logQ,
                                     (stepLocked ? 1 : 0), baseUnit / pip0,
                                     (hitOK ? 1 : 0));
        bool logSeen = false;
        int logSlot = -1;
        for(int lq = 0; lq < 8; lq++)
        {
            if(s_th3LogPat[lq] == mainObjName)
            {
                logSlot = lq;
                if(s_th3LogKey[lq] == logKey) logSeen = true;
                break;
            }
        }
        if(!logSeen)
        {
            if(logSlot < 0) { logSlot = s_th3LogPos % 8; s_th3LogPos++; }
            s_th3LogPat[logSlot] = mainObjName;
            s_th3LogKey[logSlot] = logKey;
            string logLine = StringFormat(
                "TH3LOG pat=%s chart=%d st=%d R=%.1f closed=%.1f K=%.2f rung=%.1f owner=%s q=%s pb=%.1f synth=%.1f macro=%d lock=%d step=%.1f proof=%d deep=%.2f",
                mainObjName, Period(), (long)TimeCurrent(), pbRaw / pip0,
                (closedOK ? closedStep / pip0 : 0.0),
                (closedOK ? closedK : 0.0), seedRung / pip0,
                TH3TfName(ownerTF), logQ, pbStep / pip0,
                (baseUnit / pip0),
                0, (stepLocked ? 1 : 0),
                baseUnit / pip0, (hitOK ? 1 : 0), hitProof.deepestRungs);
            Print(logLine);
            TH3LogFileAppend(logLine);
        }
    }
    
    double pipSize = GetCachedPipSize();
    
    // DYNAMIC OFFSET: Calculate based on candle size for better positioning
    // Offset                          
    double labelOffset;
    
    if(inpABCDLabelOffsetPercent > 0) {
        // User-defined offset percentage (P-TH3-PERF-01: cached per bar)
        double avgCandleSize = TH3AvgCandleSize();
        
        // Use user-defined percentage of average candle size
        labelOffset = avgCandleSize * (inpABCDLabelOffsetPercent / 100.0);
        
        // Minimum offset: 3 pips (prevent labels too close)
        double minOffset = 3.0 * pipSize;
        if(labelOffset < minOffset) labelOffset = minOffset;
        
        // Maximum offset: 100 pips (prevent labels too far)
        double maxOffset = 100.0 * pipSize;
        if(labelOffset > maxOffset) labelOffset = maxOffset;
    } else {
        // Auto mode: Use fixed 15 pips (legacy behavior)
        labelOffset = 15.0 * pipSize;
    }
    
    // Cleanup any lingering legacy X objects
    ObjectDelete(0, mainObjName + "_Point_X");
    ObjectDelete(0, mainObjName + "_Label_X");
    ObjectDelete(0, mainObjName + "_Line_XA");

    // Draw points A, B, C, D with smart label positioning
    string pointNames[4];
    pointNames[0] = "A";
    pointNames[1] = "B";
    pointNames[2] = "C";
    pointNames[3] = "D";
    
    datetime pointTimes[4];
    pointTimes[0] = tA;
    pointTimes[1] = tB;
    pointTimes[2] = tC;
    pointTimes[3] = tD;
    
    double pointPrices[4];
    pointPrices[0] = pA;
    pointPrices[1] = pB;
    pointPrices[2] = pC;
    pointPrices[3] = pD;
    
    // Draw visible drag points for A, B, C, D (small circles with smart positioning)
    for(int i = 0; i < 4; i++) {
        string pointName = mainObjName + "_Point_" + pointNames[i];
        
        // SMART POSITIONING: Place point above/below candle based on price level
        //                     /              
        int barIndex = iBarShift(NULL, 0, pointTimes[i]);
        double pointPrice = pointPrices[i];
        
        if(barIndex >= 0) {
            double high = iHigh(NULL, 0, barIndex);
            double low = iLow(NULL, 0, barIndex);
            double mid = (high + low) / 2.0;
            
            // Determine if point is at top or bottom of candle
            //                         
            bool isAtTop = (pointPrice >= mid);
            
            // Offset point slightly outside candle for visibility
            //                           
            double offset = (high - low) * 0.15; // 15% of candle range
            double minOffset = pipSize * 10;  // Minimum 10 pips
            if(offset < minOffset) offset = minOffset; // Minimum offset
            
            if(isAtTop) {
                // Point at top - place above high
                pointPrice = high + offset;
            } else {
                // Point at bottom - place below low
                pointPrice = low - offset;
            }
        }
        
        // OPTIMIZED: Use small circle (ARROWCODE 159) - visible and draggable
        //             -          
        if(ObjectFind(0, pointName) < 0) {
            if(!ObjectCreate(0, pointName, OBJ_ARROW, 0, pointTimes[i], pointPrices[i])) {
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== Failed to create point ", pointNames[i], " | Error: ", GetLastError());
                #endif
            } else {
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== Created point ", pointNames[i], " at ", TimeToString(pointTimes[i]), " @ ", DoubleToString(pointPrices[i], Digits));
                #endif
            }
            
            // CRITICAL: Visible circle with smart positioning
            // P-UI-97: every ink in this file goes through TH3InkForChart, so a light
            // chart gets the same hues at a readable lightness (and a dark chart is
            // untouched). A raw input written straight into OBJPROP_COLOR is how a
            // gold/lime pattern ended up unreadable on white paper.
            ObjectSetInteger(0, pointName, OBJPROP_COLOR, TH3InkForChart(inpABCDPointColor));
            ObjectSetInteger(0, pointName, OBJPROP_ARROWCODE, 159); // Small filled circle
            ObjectSetInteger(0, pointName, OBJPROP_WIDTH, 3); // Medium size for easy clicking
            ObjectSetInteger(0, pointName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, pointName, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, pointName, OBJPROP_BACK, false); // Draw on top
            ObjectSetInteger(0, pointName, OBJPROP_ZORDER, Z_CHART_TOOL); // P-UI-31: over the level lines, under every label
            ObjectSetString(0, pointName, OBJPROP_TOOLTIP, "==================== Point " + pointNames[i] + " | Drag to adjust");
        } else {
            // Update existing point position
            ObjectMove(0, pointName, 0, pointTimes[i], pointPrices[i]);
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Updated existing point ", pointNames[i]);
            #endif
        }
        // P-DRAW-122 (2026-10-01) — A PAINTED LAYER IS RE-ASSERTED EVERY PASS. This
        // point's rung was written inside its birth block only, while the branch above
        // MOVES an object that already exists: an arrow that survived a reattach (or a
        // pattern redrawn onto objects the terminal still held) kept the rung of the
        // instance that born it, and `Z_CHART_TOOL` is exactly "over the level lines,
        // under every label" — lose it and the point paints under the lines it marks.
        // Same law as the strip's own painters (DrawStrip_GearB/Paint/Skin); compare-
        // guarded, so a still frame writes nothing.
        if((long)ObjectGetInteger(0, pointName, OBJPROP_ZORDER) != Z_CHART_TOOL ||
           (long)ObjectGetInteger(0, pointName, OBJPROP_BACK) != 0)
        {
            ObjectSetInteger(0, pointName, OBJPROP_BACK, false);
            ObjectSetInteger(0, pointName, OBJPROP_ZORDER, Z_CHART_TOOL);
        }
        
        // Smart label positioning relative to candle High/Low
        //                   High/Low    
        // TH3TOOL-ON (2026-09-19): the card's SHOW LABELS row is honored here too
        // (two owners, one gate): the tool's own switch AND the AB=CD input.
        if(inpABCDShowLabels && g_showTH3Labels) {
            string labelName = mainObjName + "_Label_" + pointNames[i];
            double labelPrice = pointPrices[i];
            ENUM_ANCHOR_POINT anchor = ANCHOR_CENTER;
            
            // Get candle High/Low for this point
            int labelBarIndex = iBarShift(NULL, 0, pointTimes[i]);
            double candleHigh = (labelBarIndex >= 0) ? iHigh(NULL, 0, labelBarIndex) : pointPrices[i];
            double candleLow = (labelBarIndex >= 0) ? iLow(NULL, 0, labelBarIndex) : pointPrices[i];
            
            // Position label relative to candle High/Low (not point price)
            //              High/Low     (         
            if(i == 0 || i == 2) { // A or C (swing lows in bullish, swing highs in bearish)
                if(isBullish) {
                    // A/C are lows - place label below candle low
                    labelPrice = candleLow - labelOffset;
                    anchor = ANCHOR_UPPER;
                } else {
                    // A/C are highs - place label above candle high
                    labelPrice = candleHigh + labelOffset;
                    anchor = ANCHOR_LOWER;
                }
            } else { // B or D (swing highs in bullish, swing lows in bearish)
                if(isBullish) {
                    // B/D are highs - place label above candle high
                    labelPrice = candleHigh + labelOffset;
                    anchor = ANCHOR_LOWER;
                } else {
                    // B/D are lows - place label below candle low
                    labelPrice = candleLow - labelOffset;
                    anchor = ANCHOR_UPPER;
                }
            }
            
            if(ObjectFind(0, labelName) < 0) {
                if(!ObjectCreate(0, labelName, OBJ_TEXT, 0, pointTimes[i], labelPrice)) {
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("==================== Failed to create label ", pointNames[i], " | Error: ", GetLastError());
                    #endif
                } else {
                    #ifdef ENABLE_DEBUG_LOGS
                    Print("==================== Created label ", pointNames[i]);
                    #endif
                }
                ObjectSetString(0, labelName, OBJPROP_TEXT, pointNames[i]);
                ObjectSetInteger(0, labelName, OBJPROP_COLOR, TH3SessionPointInk());
                ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
                ObjectSetString(0, labelName, OBJPROP_FONT, BioChromeFont());
                ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, anchor);
                ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
            } else {
                ObjectMove(0, labelName, 0, pointTimes[i], labelPrice);
                ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, anchor);
                #ifdef ENABLE_DEBUG_LOGS
                Print("==================== Updated existing label ", pointNames[i]);
                #endif
            }
        }
    }
    
    // Draw line AB (solid)
    string lineAB = mainObjName + "_Line_AB";
    if(ObjectFind(0, lineAB) < 0) {
        if(!ObjectCreate(0, lineAB, OBJ_TREND, 0, tA, pA, tB, pB)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Failed to create Line AB | Error: ", GetLastError());
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Created Line AB");
            #endif
        }
        // TH3TOOL-ON (2026-09-19): the card's own LOOK rows are honored here —
        // COLOR / WIDTH / STYLE (and PIP COLOR on the info text) were the tool's
        // own settings. Without these readers the three rows could only move
        // their own switch (P-UI-46's shape; probe-budget's live-control caught
        // exactly that). The AB=CD inputs stay the FALLBACK when the tool's own
        // colour is clrNONE (its shipped default).
        ObjectSetInteger(0, lineAB, OBJPROP_COLOR, TH3SessionLineInk());
        ObjectSetInteger(0, lineAB, OBJPROP_WIDTH, g_th3Width);
        ObjectSetInteger(0, lineAB, OBJPROP_STYLE, g_th3Style);
        ObjectSetInteger(0, lineAB, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, lineAB, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, lineAB, OBJPROP_BACK, false);
    } else {
        ObjectMove(0, lineAB, 0, tA, pA);
        ObjectMove(0, lineAB, 1, tB, pB);
        // P-TH3-PERF-02 (2026-09-19) — a panel LOOK edit lands HERE, without
        // recreating the object — and only when it actually changed. MT4
        // repaints on every ObjectSet*, so the read-then-write guard is what
        // keeps a drag/repaint loop from paying for three writes per frame
        // (the project's perf law: never write a chart property you would not
        // change). Without this the WIDTH/STYLE/COLOR rows had a reader but no
        // re-apply path, so an edit only showed up after the object was gone.
        color wantClr = TH3SessionLineInk();   // P-UI-97: the same resolved ink as the create path
        if((color)ObjectGetInteger(0, lineAB, OBJPROP_COLOR) != wantClr)
            ObjectSetInteger(0, lineAB, OBJPROP_COLOR, wantClr);
        if((int)ObjectGetInteger(0, lineAB, OBJPROP_WIDTH) != g_th3Width)
            ObjectSetInteger(0, lineAB, OBJPROP_WIDTH, g_th3Width);
        if((int)ObjectGetInteger(0, lineAB, OBJPROP_STYLE) != (int)g_th3Style)
            ObjectSetInteger(0, lineAB, OBJPROP_STYLE, g_th3Style);
    }
    
    // Draw line BC (dotted)
    string lineBC = mainObjName + "_Line_BC";
    if(ObjectFind(0, lineBC) < 0) {
        if(!ObjectCreate(0, lineBC, OBJ_TREND, 0, tB, pB, tC, pC)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Failed to create Line BC | Error: ", GetLastError());
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Created Line BC");
            #endif
        }
        ObjectSetInteger(0, lineBC, OBJPROP_COLOR, TH3InkForChart(clrGray));   // P-UI-97: gray 128 is left as it is on either paper
        ObjectSetInteger(0, lineBC, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, lineBC, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, lineBC, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, lineBC, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, lineBC, OBJPROP_BACK, true);
    } else {
        ObjectMove(0, lineBC, 0, tB, pB);
        ObjectMove(0, lineBC, 1, tC, pC);
    }

    // P-TH3-D4 (2026-09-20) — THE CD LEG DRAWS. Clicks are A/B/C/D, so the
    // C->D leg is user-placed ink like AB (same width/style/ink), not a
    // computed projection. Without it D floated with no leg into it.
    string lineCD = mainObjName + "_Line_CD";
    if(ObjectFind(0, lineCD) < 0) {
        if(!ObjectCreate(0, lineCD, OBJ_TREND, 0, tC, pC, tD, pD)) {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Failed to create Line CD | Error: ", GetLastError());
            #endif
        } else {
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Created Line CD");
            #endif
        }
        ObjectSetInteger(0, lineCD, OBJPROP_COLOR, TH3SessionLineInk());
        ObjectSetInteger(0, lineCD, OBJPROP_WIDTH, g_th3Width);
        ObjectSetInteger(0, lineCD, OBJPROP_STYLE, g_th3Style);
        ObjectSetInteger(0, lineCD, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, lineCD, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, lineCD, OBJPROP_BACK, false);
    } else {
        ObjectMove(0, lineCD, 0, tC, pC);
        ObjectMove(0, lineCD, 1, tD, pD);
        color wantCD = TH3SessionLineInk();   // P-TH3-PERF-02: read-then-write like Line_AB
        if((color)ObjectGetInteger(0, lineCD, OBJPROP_COLOR) != wantCD)
            ObjectSetInteger(0, lineCD, OBJPROP_COLOR, wantCD);
        if((int)ObjectGetInteger(0, lineCD, OBJPROP_WIDTH) != g_th3Width)
            ObjectSetInteger(0, lineCD, OBJPROP_WIDTH, g_th3Width);
        if((int)ObjectGetInteger(0, lineCD, OBJPROP_STYLE) != (int)g_th3Style)
            ObjectSetInteger(0, lineCD, OBJPROP_STYLE, g_th3Style);
    }

    // P-TH3-D4h (2026-09-21, user: «خط های بنفش که از سر نقاط به عقب کشیده شده
    // رو حذف کن»): the two magenta level lines are RETIRED — _Ray_D (D's price
    // rayed LEFT into the past) and _Ray_C (C's price, B->C). The names survive
    // only as a retired sweep: a pattern drawn by an older build carries them,
    // and its next redraw deletes them. Never create them again.
    ObjectDelete(0, mainObjName + "_Ray_D");
    ObjectDelete(0, mainObjName + "_Ray_C");

    // P-TH3-D4f — CD LEG LABEL. A small text at the midpoint of CD showing
    // only the ownerTF name (e.g. "H1") so the trader reads which timeframe
    // owns the leg without needing the full caption.
    {
        string cdLbl = mainObjName + "_CDLabel";
        datetime tCD_mid = tC + (tD - tC) / 2;
        double   pCD_mid = (pC + pD) / 2.0;
        string   cdLblText = TH3TfName(ownerTF);
        if(ObjectFind(0, cdLbl) < 0) {
            if(ObjectCreate(0, cdLbl, OBJ_TEXT, 0, tCD_mid, pCD_mid)) {
                ObjectSetString( 0, cdLbl, OBJPROP_TEXT,      cdLblText);
                ObjectSetString( 0, cdLbl, OBJPROP_FONT,      BioChromeFont());
                ObjectSetInteger(0, cdLbl, OBJPROP_FONTSIZE,  9);
                ObjectSetInteger(0, cdLbl, OBJPROP_COLOR,     clrMagenta);
                ObjectSetInteger(0, cdLbl, OBJPROP_ANCHOR,    ANCHOR_CENTER);
                ObjectSetInteger(0, cdLbl, OBJPROP_SELECTABLE,false);
                ObjectSetInteger(0, cdLbl, OBJPROP_BACK,      false);
            }
        } else {
            ObjectMove(0, cdLbl, 0, tCD_mid, pCD_mid);
            if(ObjectGetString(0, cdLbl, OBJPROP_TEXT) != cdLblText)
                ObjectSetString(0, cdLbl, OBJPROP_TEXT, cdLblText);
        }
    }

    // P-TH3-D4f — MOTHER LEG MARKER (v12).
    // Two-pass approach (no running-opposite ambiguity):
    //
    // Pass 1 — find the END bar of the mother leg:
    //   The mother leg ends at the local extreme NEAREST to pA in the CD
    //   direction, BEFORE barA, with |extreme - pA| <= 1 ATR.
    //   We take the CLOSEST (smallest distance) such bar.
    //
    // Pass 2 — find the START bar of the mother leg:
    //   From the END bar, walk further back and find the HIGHEST high
    //   (bearish) or LOWEST low (bullish) — that is the mother start.
    //   No distance gate; just the global max/min before the end bar.
    //
        // Size check: mother leg must be >= CD * 0.80. mlMotherSize feeds the
        // caption's 1/3M row, so the measure stays even though its ticks are gone
        // (P-TH3-D4h).
    double mlMotherSize = 0;
    double mlRatio      = 0;
    {
        int    barA      = iBarShift(NULL, 0, tA);
        int    lookback  = MathMin(500, iBars(NULL, 0) - 1);
        double atrWindow = TH3PatternStepRung();
        if(atrWindow <= 0) atrWindow = CD_Distance;

        // --- Pass 1: END bar = bar with extreme closest to pA before barA ---
        int    bestEndBar  = -1;
        double bestEndDist = 1e9;
        for(int k = barA + 1; k <= lookback; k++)
        {
            double ext  = dirDown ? iLow(NULL, 0, k) : iHigh(NULL, 0, k);
            double dist = MathAbs(ext - pA);
            if(dist <= atrWindow && dist < bestEndDist)
            {
                bestEndDist = dist;
                bestEndBar  = k;
            }
        }

        // --- Pass 2: START bar = global opposite extreme before END bar ---
        int    bestStartBar = -1;
        double bestStartVal = dirDown ? -1e9 : 1e9;
        if(bestEndBar >= 0)
        {
            for(int k = bestEndBar + 1; k <= lookback; k++)
            {
                double ext = dirDown ? iHigh(NULL, 0, k) : iLow(NULL, 0, k);
                if(dirDown ? (ext > bestStartVal) : (ext < bestStartVal))
                {
                    bestStartVal = ext;
                    bestStartBar = k;
                }
            }
        }

        // Size check
        if(bestEndBar >= 0 && bestStartBar >= 0)
        {
            double endExt   = dirDown ? iLow (NULL,0,bestEndBar)
                                      : iHigh(NULL,0,bestEndBar);
            mlMotherSize = MathAbs(bestStartVal - endExt);
        }

        // P-TH3-D4h (2026-09-21, user: «تیک های مادر»): the mother-leg ticks are
        // RETIRED — _MPTick (start) and _MPTickB (end), lime/red width-3. The
        // measurement above STAYS (mlMotherSize feeds the caption); only the two
        // objects go, swept here so an older build's ticks die on redraw. Never
        // create them again.
        ObjectDelete(0, mainObjName + "_MPTick");
        ObjectDelete(0, mainObjName + "_MPTickB");
    }

    // Draw TH3-style targets (Step1, Step3, Step5, Step7) from D (P-TH3-D4)
    string targetNames[4] = {"Step1", "Step3", "Step5", "Step7"};
    color targetColors[4] = {clrDodgerBlue, clrOrangeRed, clrLimeGreen, clrGold};
    double targetLevels[4];
    
    // P-TH3-D4 (2026-09-20) — THE LADDER PROJECTS FROM THE PLACED D.
    // The 4th click IS D (tD,pD): Step1 sits exactly one step past D
    // (pD +/- 1.0*step), Step3/5/7 at 3/5/7 steps. No RealD walk shifts
    // the origin: the 83.1-vs-39.7 gap was that walk moving the base 68
    // bars into the future while the caption still read the seed step.
    if(isBullish) {
        targetLevels[0] = pD + (1.0 * baseUnit);
        targetLevels[1] = pD + (3.0 * baseUnit);
        targetLevels[2] = pD + (5.0 * baseUnit);
        targetLevels[3] = pD + (7.0 * baseUnit);
    } else {
        targetLevels[0] = pD - (1.0 * baseUnit);
        targetLevels[1] = pD - (3.0 * baseUnit);
        targetLevels[2] = pD - (5.0 * baseUnit);
        targetLevels[3] = pD - (7.0 * baseUnit);
    }
    
    double targetPips[4];
    for(int i = 0; i < 4; i++) {
        targetPips[i] = MathAbs(baseUnit * (i*2 + 1)) / pipSize;
    }

    // P-TH3-DISC: the EVEN rungs (2/4/6) ride WITH the ladder, another ink.
    double midLevels[3];
    double midPips[3];
    ArrayInitialize(midLevels, 0.0);
    ArrayInitialize(midPips, 0.0);
    for(int mi = 0; mi < 3; mi++) {
        int mStep = 2 * (mi + 1);
        midLevels[mi] = isBullish ? pD + (mStep * baseUnit) : pD - (mStep * baseUnit);
        midPips[mi] = MathAbs(baseUnit * mStep) / pipSize;
    }
    
    datetime startTime = tD;   // P-TH3-D4: the ladder starts at the placed D
    // P-TH3-ZONE-03 (2026-10-05) — THE BANDS TRADE FORWARD. The boxes ended
    // 100 bars BEHIND D (history side) while the lines ray right into the
    // trade: every zone stood 4/4 in the census yet none painted beside its
    // line. Rectangles cannot ray, so the end anchors 100 bars past the
    // CURRENT bar — the bands now ride under the lines where price goes.
    // (The fibo lines share these times; their RAY_RIGHT makes the end
    // anchor irrelevant to them, so their look does not move.)
    datetime endTime = iTime(NULL, 0, 0) + (100 * PeriodSeconds());
    
    // GOLD VERSION: Use configurable zone height from input parameter
    // Convert from percentage (1-100) to decimal (0.01-1.0)
    double zoneHeightPercent = inpTH3ZoneHeightPercent / 100.0;
    
    // Validate and clamp
    if(zoneHeightPercent < 0.01) zoneHeightPercent = 0.01;
    if(zoneHeightPercent > 1.0) zoneHeightPercent = 1.0;
    
    // P-TH3-ZONE-01 (2026-09-19) — THE PERCENT IS THE WHOLE BAND, NOT ITS HALF.
    // The line read `baseUnit * zoneHeightPercent`, so a 33% input drew a band of
    // 2 x 33% = 66% of the step while every other zone family in this project
    // reads the SAME input as the FULL height: `UnifiedZoneSystem`/`LevelPipeline`
    // build `zoneHeight = stepSize * heightPercent * 0.5` (their comment: "0.5
    // because height"), i.e. `heightPercent == 1.0` is the boundary case of one
    // whole step. The label below printed the full height in pips, so label and
    // band disagreed by exactly 2x — the user's «بازه رو اشتباه میندازه»: he set
    // 33% and the chart threw a band twice that. Now the drawn band IS the
    // percentage of the step, both halves come from one number, and the label
    // states the height it draws.
    double zoneHalfWidth = baseUnit * zoneHeightPercent * 0.5;
    
    for(int i = 0; i < 4; i++) {
        string lineName = mainObjName + "_Target_" + IntegerToString(i+1);
        double centerPrice = targetLevels[i];
        double upperZone = centerPrice + zoneHalfWidth;
        double lowerZone = centerPrice - zoneHalfWidth;
        // P-UI-97: the ladder's four hues (dodger blue / orange red / lime green / gold)
        // are a palette, not a promise — gold and lime green are invisible on white, so
        // the ink is resolved BEFORE the transparency blend that mixes it with the paper.
        color zoneColor = TH3InkForChart((inpTH3ZoneColor == clrNONE) ? targetColors[i] : inpTH3ZoneColor);
        color targetInk = TH3InkForChart(targetColors[i]);
        // Apply the zone transparency to the box/border color (blend with background)
        zoneColor = GetZoneRenderColor(zoneColor, inpTH3ZoneTransparency);
        
        if(ObjectFind(0, lineName) < 0) {
            ObjectCreate(0, lineName, OBJ_FIBO, 0, startTime, centerPrice, endTime, centerPrice);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, targetInk);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELCOLOR, targetInk);
            ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELWIDTH, 2);
            ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
            ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELS, 1);
            ObjectSetDouble(0, lineName, OBJPROP_LEVELVALUE, 0, 0.0);
            
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN) {
                // P-TH3-ZONE-01: the number is the band's FULL height in pips (what
                // is drawn), and the separator is short enough that it stays INSIDE
                // the plot — 20 dashes ran the text past the right edge and cut the
                // height off the chart entirely.
                double zonePips = (zoneHalfWidth * 2.0) / pipSize;
                string labelText = StringFormat("%s (%.1f) ========%.1f", targetNames[i], targetPips[i], zonePips);
                ObjectSetString(0, lineName, OBJPROP_LEVELTEXT, 0, labelText);
            }
        } else {
            // CRITICAL FIX: Update position AND label text when frequency changes
            ObjectMove(0, lineName, 0, startTime, centerPrice);
            ObjectMove(0, lineName, 1, endTime, centerPrice);
            
            // Update label text with new pip values (P-TH3-ZONE-01: full height)
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN) {
                double zonePips = (zoneHalfWidth * 2.0) / pipSize;
                string labelText = StringFormat("%s (%.1f) ========%.1f", targetNames[i], targetPips[i], zonePips);
                ObjectSetString(0, lineName, OBJPROP_LEVELTEXT, 0, labelText);
            }
        }
        
        // Zone objects: BOX styles -> rectangle; HIDDEN -> nothing
        string zoneUpperName = mainObjName + "_ZoneUpper_" + IntegerToString(i+1);
        string zoneLowerName = mainObjName + "_ZoneLower_" + IntegerToString(i+1);
        string zoneBoxName = mainObjName + "_Zone_" + IntegerToString(i+1);

        // P-UI-62: the "hidden" style is retired - visibility is the zone master
        // switch's question, and slot 2 of ENUM_ZONE_STYLE is now OUTLINED. (This
        // module is not included by any build - see ARCHITECTURE.md's retired-modules
        // note - so the edit is here only to keep the names honest for a revival.)
        if(inpTH3ZoneStyle == TH3_ZONE_BOX_EMPTY) {
            // EMPTY BOX: hollow outline drawn as border segments. Works on
            // every MT4 build - OBJ_RECTANGLE with FILL=false is unreliable.
            if(ObjectFind(0, zoneUpperName) >= 0) ObjectDelete(0, zoneUpperName);
            if(ObjectFind(0, zoneLowerName) >= 0) ObjectDelete(0, zoneLowerName);
            if(ObjectFind(0, zoneBoxName) >= 0) ObjectDelete(0, zoneBoxName);
            
            string topBorder = zoneBoxName + "_B_Top";
            string bottomBorder = zoneBoxName + "_B_Bottom";
            string leftBorder = zoneBoxName + "_B_Left";
            
            // Top border (extends right, matching the filled box)
            if(ObjectFind(0, topBorder) < 0) {
                ObjectCreate(0, topBorder, OBJ_TREND, 0, startTime, upperZone, endTime, upperZone);
                ObjectSetInteger(0, topBorder, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, topBorder, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, topBorder, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
                ObjectSetInteger(0, topBorder, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
                ObjectSetInteger(0, topBorder, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, topBorder, OBJPROP_BACK, true);
            } else {
                ObjectMove(0, topBorder, 0, startTime, upperZone);
                ObjectMove(0, topBorder, 1, endTime, upperZone);
                ObjectSetInteger(0, topBorder, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, topBorder, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, topBorder, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
            }
            
            // Bottom border (extends right, matching the filled box)
            if(ObjectFind(0, bottomBorder) < 0) {
                ObjectCreate(0, bottomBorder, OBJ_TREND, 0, startTime, lowerZone, endTime, lowerZone);
                ObjectSetInteger(0, bottomBorder, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, bottomBorder, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, bottomBorder, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
                ObjectSetInteger(0, bottomBorder, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
                ObjectSetInteger(0, bottomBorder, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, bottomBorder, OBJPROP_BACK, true);
            } else {
                ObjectMove(0, bottomBorder, 0, startTime, lowerZone);
                ObjectMove(0, bottomBorder, 1, endTime, lowerZone);
                ObjectSetInteger(0, bottomBorder, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, bottomBorder, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, bottomBorder, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
            }
            
            // Left border (vertical - closes the outline)
            if(ObjectFind(0, leftBorder) < 0) {
                ObjectCreate(0, leftBorder, OBJ_TREND, 0, startTime, lowerZone, startTime, upperZone);
                ObjectSetInteger(0, leftBorder, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, leftBorder, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, leftBorder, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
                ObjectSetInteger(0, leftBorder, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, leftBorder, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, leftBorder, OBJPROP_BACK, true);
            } else {
                ObjectMove(0, leftBorder, 0, startTime, lowerZone);
                ObjectMove(0, leftBorder, 1, startTime, upperZone);
                ObjectSetInteger(0, leftBorder, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, leftBorder, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                ObjectSetInteger(0, leftBorder, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
            }
        }
        else {
            // BOX_FILLED: single filled rectangle zone
            if(ObjectFind(0, zoneUpperName) >= 0) ObjectDelete(0, zoneUpperName);
            if(ObjectFind(0, zoneLowerName) >= 0) ObjectDelete(0, zoneLowerName);
            if(ObjectFind(0, zoneBoxName + "_B_Top") >= 0) ObjectDelete(0, zoneBoxName + "_B_Top");
            if(ObjectFind(0, zoneBoxName + "_B_Bottom") >= 0) ObjectDelete(0, zoneBoxName + "_B_Bottom");
            if(ObjectFind(0, zoneBoxName + "_B_Left") >= 0) ObjectDelete(0, zoneBoxName + "_B_Left");
            
            if(ObjectFind(0, zoneBoxName) < 0) {
                if(ObjectCreate(0, zoneBoxName, OBJ_RECTANGLE, 0, startTime, lowerZone, endTime, upperZone)) {
                    ObjectSetInteger(0, zoneBoxName, OBJPROP_COLOR, zoneColor);
                    ObjectSetInteger(0, zoneBoxName, OBJPROP_FILL, true);
                    ObjectSetInteger(0, zoneBoxName, OBJPROP_STYLE, inpTH3ZoneBorderStyle);
                    ObjectSetInteger(0, zoneBoxName, OBJPROP_WIDTH, inpTH3ZoneBorderWidth);
                    ObjectSetInteger(0, zoneBoxName, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
                    ObjectSetInteger(0, zoneBoxName, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(0, zoneBoxName, OBJPROP_BACK, true);
                }
            } else {
                ObjectMove(0, zoneBoxName, 0, startTime, lowerZone);
                ObjectMove(0, zoneBoxName, 1, endTime, upperZone);
                ObjectSetInteger(0, zoneBoxName, OBJPROP_COLOR, zoneColor);
                ObjectSetInteger(0, zoneBoxName, OBJPROP_FILL, true);
            }
        }
    }
    
    // P-TH3-DISC: the even rungs' ink — dotted gray, no zones. Same family
    // discipline as the targets (create once, move after; masked with the
    // ladder in TH3LadderSetVisible, matched in TH3IsLadderName).
    for(int mi = 0; mi < 3; mi++) {
        int mStep = 2 * (mi + 1);
        string midName = mainObjName + "_Mid_" + IntegerToString(mStep);
        string midText = StringFormat("Step%d (%.1f)", mStep, midPips[mi]);
        if(ObjectFind(0, midName) < 0) {
            if(ObjectCreate(0, midName, OBJ_FIBO, 0, startTime, midLevels[mi], endTime, midLevels[mi])) {
                ObjectSetInteger(0, midName, OBJPROP_COLOR, TH3InkForChart(clrGray));
                ObjectSetInteger(0, midName, OBJPROP_LEVELCOLOR, TH3InkForChart(clrGray));
                ObjectSetInteger(0, midName, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, midName, OBJPROP_LEVELWIDTH, 1);
                ObjectSetInteger(0, midName, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, midName, OBJPROP_LEVELSTYLE, STYLE_DOT);
                ObjectSetInteger(0, midName, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
                ObjectSetInteger(0, midName, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, midName, OBJPROP_LEVELS, 1);
                ObjectSetDouble(0, midName, OBJPROP_LEVELVALUE, 0, 0.0);
                if(inpTH3LabelPosition != TH3_LABEL_HIDDEN)
                    ObjectSetString(0, midName, OBJPROP_LEVELTEXT, 0, midText);
            }
        } else {
            ObjectMove(0, midName, 0, startTime, midLevels[mi]);
            ObjectMove(0, midName, 1, endTime, midLevels[mi]);
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN)
                ObjectSetString(0, midName, OBJPROP_LEVELTEXT, 0, midText);
        }
    }

    // P-TH3-ZONE-02 (2026-10-05) — ZONE CENSUS, ONE LINE PER DRAW. The lines
    // paint while the bands read missing, and both come from one loop — so the
    // next occurrence must name setting-vs-code itself: how many of the four
    // zone boxes stand, and the three inputs that render them. Draw-paced
    // (never per tick), so the cost is one line per user gesture.
    {
        int zoneStand = 0;
        string zoneSeen = "";
        for(int zi = 1; zi <= 4; zi++)
        {
            string znm = mainObjName + "_Zone_" + IntegerToString(zi);
            if(ObjectFind(0, znm) < 0) continue;
            zoneStand++;
            // existence is not paint: mask, box and ink decide the pixels.
            zoneSeen += StringFormat(" [%d t0=%s t1=%s p0=%s p1=%s tf=%d cl=%d]",
                zi, TimeToString((datetime)ObjectGetInteger(0, znm, OBJPROP_TIME, 0)),
                TimeToString((datetime)ObjectGetInteger(0, znm, OBJPROP_TIME, 1)),
                DoubleToString(ObjectGetDouble(0, znm, OBJPROP_PRICE, 0), Digits),
                DoubleToString(ObjectGetDouble(0, znm, OBJPROP_PRICE, 1), Digits),
                (int)ObjectGetInteger(0, znm, OBJPROP_TIMEFRAMES),
                (int)ObjectGetInteger(0, znm, OBJPROP_COLOR));
        }
        Print("TH3: zones stand=", zoneStand, "/4 style=", (int)inpTH3ZoneStyle,
              " tr=", inpTH3ZoneTransparency, " h%=", DoubleToString(inpTH3ZoneHeightPercent, 1),
              zoneSeen);
    }

    // P-TH3-STEP-03: the proof objects (retired by P-TH3-DISC below — the
    // step lines already say where L3 sits; the measure, logs and TH3LOG stay).
    // P-TH3-D4: the interval starts at the placed D (tD,pD), not C.
    // P-TH3-STEP-06/07 (2026-09-19) — THE VERDICT ONLY SPEAKS WHEN IT HAS ONE.
    // The interval and the verdict describe the step the ladder now wears, so
    // they draw exactly when the market voted (hitOK — P-TH3-STEP-07 made that
    // the only condition, pivot or not). Without it there is no proof to show
    // and the two objects are DELETED, so a stale interval from a previous
    // render cannot stay parked on the chart, and a verdict can never carry the
    // empty timeframe name an unclaimed tip used to print ("T3 <-  grid").
    // P-TH3-DISC: the proof interval and verdict are OFF the chart — the step
    // lines already say where L3 sits. The measure, the log lines and TH3LOG
    // stay (the formula still wears the proved step); only the two objects
    // go. Old charts drop them on next redraw.
    ObjectDelete(0, mainObjName + "_HitLine");
    ObjectDelete(0, mainObjName + "_HitLabel");

    // P-TH3-P6e + P-TH3-D4 — MOTHER PIVOT AT D, ON THE CHART.
    // The matcher (TH3Pivots.mqh) answers which six-condition pivot the
    // placed D hit (tD,pD); this is its ink — ACTIVE pattern only, one badge
    // per chart (the clean-chart rule). Two dotted bounds (extreme +
    // key line, pivot bar -> D, BACK=true so candles stay on top) plus
    // Head/Tail markers at the pivot bar (extreme + keyPrice) plus one
    // compact badge at D: "[ H1 Mother Pivot | 8.7p | FRESH ]".
    // D is the collision point, so wantHigh = dirDown: a bearish D is a
    // high, a bullish D a low. tol = half the live step, the same ruler
    // the tip corroboration uses. Everything wears the TH3_MP_ prefix:
    // pattern delete (TH3Tool.mqh) and the full teardown (EventHandlers.mqh)
    // sweep it bulk, and a render with no match DELETES the five objects,
    // so no stale zone survives a drag.
    // mpState feeds the corner info label (diagnostics): the chart always
    // says WHY no mother zone is drawn — off / none / TF+state — so a
    // missing badge is a readable verdict, never a silent mystery.
    string mpState = "MP:none";
    bool mpActive = (g_activeABCDPattern == mainObjName);
    string mpHi = "TH3_MP_" + mainObjName + "_Hi";
    string mpLo = "TH3_MP_" + mainObjName + "_Lo";
    string mpHead = "TH3_MP_" + mainObjName + "_Head";
    string mpTail = "TH3_MP_" + mainObjName + "_Tail";
    string mpBadge = "TH3_MP_" + mainObjName + "_Badge";
    TH3PivotSix mp;
    // Pillars 1+4 (P-TH3-MP2): the mother must predate the pattern origin
    // A (P-TH3-D4: X retired), and distance is scored in closed-step units.
    // The anchor PRICE (A) is wired for the launch test — the leg whose
    // start sits in the node is the leg the node launched. tol is the
    // tier-1 entry only; the matcher's ladder widens it to reach a far mother.
    datetime mpAnchor = tA;
    double   mpAnchorPrice = pA;
    bool mpShow = (inpShowMotherPivotZone && mpActive && atrBasis
                   && TH3MotherPivotAt(tD, pD, dirDown, 0.5 * baseUnit, mp,
                                       mpAnchor, (closedOK ? closedStep : 0.0), true,
                                       mpAnchorPrice));
    if(mpShow) {
        double mpTop = MathMax(mp.price, mp.keyPrice);
        double mpBot = MathMin(mp.price, mp.keyPrice);
        // bounds: create once, move after (same pattern as _HitLine).
        // P-UI-97: the resolver sits AT the write (no local ink var) —
        // panel-wiring-audit [th3ink] rejects an unresolved ink variable.
        if(ObjectFind(0, mpHi) < 0) {
            if(ObjectCreate(0, mpHi, OBJ_TREND, 0, mp.time, mpTop, tD, mpTop)) {
                ObjectSetInteger(0, mpHi, OBJPROP_COLOR, TH3InkForChart(inpTH3Color));
                ObjectSetInteger(0, mpHi, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, mpHi, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, mpHi, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, mpHi, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, mpHi, OBJPROP_BACK, true);
            }
        } else {
            ObjectMove(0, mpHi, 0, mp.time, mpTop);
            ObjectMove(0, mpHi, 1, tD, mpTop);
        }
        if(ObjectFind(0, mpLo) < 0) {
            if(ObjectCreate(0, mpLo, OBJ_TREND, 0, mp.time, mpBot, tD, mpBot)) {
                ObjectSetInteger(0, mpLo, OBJPROP_COLOR, TH3InkForChart(inpTH3Color));
                ObjectSetInteger(0, mpLo, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, mpLo, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, mpLo, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, mpLo, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, mpLo, OBJPROP_BACK, true);
            }
        } else {
            ObjectMove(0, mpLo, 0, mp.time, mpBot);
            ObjectMove(0, mpLo, 1, tD, mpBot);
        }
        // P-TH3-D4 — HEAD/TAIL MARKERS. Head = the pivot extreme (mp.price),
        // Tail = the key line (mp.keyPrice): two small circles ON the pivot
        // bar so سر و ته پیوت مادر reads at a glance. Same prefix, same
        // delete discipline as Hi/Lo.
        if(ObjectFind(0, mpHead) < 0) {
            if(ObjectCreate(0, mpHead, OBJ_ARROW, 0, mp.time, mp.price)) {
                ObjectSetInteger(0, mpHead, OBJPROP_ARROWCODE, 159);
                ObjectSetInteger(0, mpHead, OBJPROP_WIDTH, 3);
                ObjectSetInteger(0, mpHead, OBJPROP_COLOR, TH3InkForChart(inpTH3Color));
                ObjectSetInteger(0, mpHead, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, mpHead, OBJPROP_BACK, false);
            }
        } else {
            ObjectMove(0, mpHead, 0, mp.time, mp.price);
        }
        if(ObjectFind(0, mpTail) < 0) {
            if(ObjectCreate(0, mpTail, OBJ_ARROW, 0, mp.time, mp.keyPrice)) {
                ObjectSetInteger(0, mpTail, OBJPROP_ARROWCODE, 159);
                ObjectSetInteger(0, mpTail, OBJPROP_WIDTH, 2);
                ObjectSetInteger(0, mpTail, OBJPROP_COLOR, TH3InkForChart(inpTH3Color));
                ObjectSetInteger(0, mpTail, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, mpTail, OBJPROP_BACK, false);
            }
        } else {
            ObjectMove(0, mpTail, 0, mp.time, mp.keyPrice);
        }
        double mpThickPips = (mpTop - mpBot) / pipSize;
        string mpFlip = ((mp.isHigh != dirDown) ? " | FLIP" : "");
        string mpText = StringFormat("[ %s Mother Pivot | %.1fp | %s%s ]",
                                     TH3TfName(mp.tf), mpThickPips,
                                     (mp.mitigated ? "MITIGATED" : "FRESH"), mpFlip);
        mpState = StringFormat("MP:%s %s%s", TH3TfName(mp.tf),
                               (mp.mitigated ? "MIT" : "FRESH"), mpFlip);
        double mpMid = (mpTop + mpBot) / 2.0;
        // P-UI-97: the badge's ink is resolved where it is computed and then worn,
        // so `inpABCDInfoColor` still paints the one caption-side surface that is
        // drawn ON the paper — the readout plate's rows are its own palette now
        // (TH3ReadoutInk), because a theme-flipped row on a fixed dark plate is
        // unreadable (P-TH3-INFO-04).
        color wantInk = TH3InkForChart(inpABCDInfoColor);
        if(ObjectFind(0, mpBadge) < 0) {
            if(ObjectCreate(0, mpBadge, OBJ_TEXT, 0, tD, mpMid)) {
                ObjectSetString(0, mpBadge, OBJPROP_TEXT, mpText);
                ObjectSetInteger(0, mpBadge, OBJPROP_COLOR, wantInk);
                ObjectSetInteger(0, mpBadge, OBJPROP_FONTSIZE, 8);
                ObjectSetString(0, mpBadge, OBJPROP_FONT, BIO_FONT_BADGE);
                ObjectSetInteger(0, mpBadge, OBJPROP_ANCHOR, ANCHOR_LEFT);
                ObjectSetInteger(0, mpBadge, OBJPROP_SELECTABLE, false);
            }
        } else {
            ObjectMove(0, mpBadge, 0, tD, mpMid);
            if(ObjectGetString(0, mpBadge, OBJPROP_TEXT) != mpText)
                ObjectSetString(0, mpBadge, OBJPROP_TEXT, mpText);
        }
    } else {
        if(!inpShowMotherPivotZone) mpState = "MP:off";
        else if(!mpActive) mpState = "MP:idle";
        // P-TH3-D4b: a miss on the ACTIVE pattern is logged with its own
        // inputs, so the log says whether D found no pivot or was never
        // allowed to look (off/idle/no-step). Rare path (one draw), not per tick.
        if(inpShowMotherPivotZone && mpActive && atrBasis)
        {
            Print("TH3: no mother at D ", TimeToString(tD), " @ ",
                  DoubleToString(pD, Digits), " dirDown=", (dirDown ? "1" : "0"),
                  " tol=", DoubleToString(0.5 * baseUnit / pipSize, 1), "p",
                  " anchor=", TimeToString(mpAnchor));
            // P-TH3-D4e: scan each TF DIRECTLY (bypassing the read memos) and
            // print (bars, anchor-shift, depth, count) — the memo-vs-scan
            // split pinpoints an empty cache to either "no bars" or a memo bug.
            // Rare path (one miss-draw), never per tick.
            int nTF0 = Period();
            int nTF1 = TH3FractalStepTF(Period(), 1);
            int nTF2 = TH3FractalStepTF(Period(), 2);
            TH3PivotSix nChart[], nStruct[], nMacro[];
            ArrayResize(nChart, TH3_P6_MAX_PIVOTS);
            ArrayResize(nStruct, TH3_P6_MAX_PIVOTS);
            ArrayResize(nMacro, TH3_P6_MAX_PIVOTS);
            int nStf = nTF1, nMtf = nTF2;
            int nNc = TH3SixPivotsScanTF(nTF0, nChart, TH3_P6_MAX_PIVOTS, 400, tD);
            Print("TH3: pivscan tf=", TH3TfName(nTF0), " bars=", iBars(NULL, nTF0),
                  " last=", iBarShift(NULL, nTF0, tD), " found=", nNc);
            int nNs = TH3SixPivotsScanTF(nTF1, nStruct, TH3_P6_MAX_PIVOTS, 400, tD);
            Print("TH3: pivscan tf=", TH3TfName(nTF1), " bars=", iBars(NULL, nTF1),
                  " last=", iBarShift(NULL, nTF1, tD), " found=", nNs);
            int nNm = TH3SixPivotsScanTF(nTF2, nMacro, TH3_P6_MAX_PIVOTS, 400, tD);
            Print("TH3: pivscan tf=", TH3TfName(nTF2), " bars=", iBars(NULL, nTF2),
                  " last=", iBarShift(NULL, nTF2, tD), " found=", nNm);
            bool nFound = false;
            TH3PivotSix nBest;   // initialised below; the compiler cannot see that
            nBest.valid = false; // `nFound` and the assignment are one condition, so
                                 // it warns — an invalid struct is the honest default.
            double nBestD = 1e9;
            for(int nL = 0; nL < 3; nL++)
            {
                int nN = (nL == 0 ? nNc : (nL == 1 ? nNs : nNm));
                for(int nI = 0; nI < nN; nI++)
                {
                    TH3PivotSix nC = (nL == 0 ? nChart[nI] : (nL == 1 ? nStruct[nI] : nMacro[nI]));
                    if(!nC.valid || nC.time > tD) continue;
                    double nD = MathAbs(nC.price - pD);
                    if(nD < nBestD) { nBestD = nD; nBest = nC; nFound = true; }
                }
            }
            if(nFound)
                Print("TH3: nearest pivot to D ",
                      TH3TfName(nBest.tf), (nBest.isHigh ? " H" : " L"),
                      " ", TimeToString(nBest.time), " @ ",
                      DoubleToString(nBest.price, Digits), " (",
                      DoubleToString(nBestD / pipSize, 1), "p away",
                      (nBest.time >= mpAnchor ? ", AFTER anchor" : ", before anchor"),
                      ((nBest.isHigh != dirDown) ? ", FLIP-kind" : ""), ")");
            else
                Print("TH3: nearest pivot to D none (cache nc=", nNc,
                      " ns=", nNs, " nm=", nNm, ")");
        }
        if(ObjectFind(0, mpHi) >= 0) ObjectDelete(0, mpHi);
        if(ObjectFind(0, mpLo) >= 0) ObjectDelete(0, mpLo);
        if(ObjectFind(0, mpHead) >= 0) ObjectDelete(0, mpHead);
        if(ObjectFind(0, mpTail) >= 0) ObjectDelete(0, mpTail);
        if(ObjectFind(0, mpBadge) >= 0) ObjectDelete(0, mpBadge);
    }

    // P-TH3-P6e Tier-2 — ORIGIN, ON THE CHART. Tier-1 answers "which level
    // is D sitting on" (P-TH3-D4) and correctly says nothing when the true
    // base is 300 pips behind: a fixed half-step tol can never reach it.
    // The origin answers "where did the move start": macro layer only,
    // ruler = the pattern's own span |D-A| (a base farther than the pattern
    // is long is another pattern's base). ONE dotted BACK line, origin bar
    // -> D at the origin price, plus an ORG token in the info state —
    // no second badge (the clean-chart rule). Same TH3_MP_ prefix, same
    // delete discipline as the Tier-1 set above.
    string mpOrg = "TH3_MP_" + mainObjName + "_Org";
    TH3PivotSix org;
    double orgSpan = MathAbs(pD - pA);   // P-TH3-D4: span measured to the placed D
    bool orgShow = (inpShowMotherPivotZone && mpActive && atrBasis && orgSpan > 0
                    && TH3OriginPivotAt(tD, pD, dirDown, orgSpan, mpAnchor, org));
    if(orgShow) {
        if(ObjectFind(0, mpOrg) < 0) {
            if(ObjectCreate(0, mpOrg, OBJ_TREND, 0, org.time, org.price, tD, org.price)) {
                ObjectSetInteger(0, mpOrg, OBJPROP_COLOR, TH3InkForChart(inpTH3Color));
                ObjectSetInteger(0, mpOrg, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, mpOrg, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, mpOrg, OBJPROP_RAY_RIGHT, false);
                ObjectSetInteger(0, mpOrg, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, mpOrg, OBJPROP_BACK, true);
            }
        } else {
            ObjectMove(0, mpOrg, 0, org.time, org.price);
            ObjectMove(0, mpOrg, 1, tD, org.price);
        }
        mpState += (" ORG:" + TH3TfName(org.tf));
    } else {
        if(ObjectFind(0, mpOrg) >= 0) ObjectDelete(0, mpOrg);
    }

    // P-TH3-DISC: the CD-leg pivot marker is retired with the auto markers —
    // display-only, never in the formula. Old charts drop it on next redraw.
    ObjectDelete(0, mainObjName + "_LegPiv");

    // P-TH3-LOCK — THE STATE MACHINE, ON THE LABEL (the user formula's §4).
    // The gate is measured FROM THE LINES, not from the tip: L3 touched ->
    // >= 1.0-step pullback from the L3 line -> Level5 armed (M1). L5 touched
    // -> >= 2.0-step pullback from the L5 line (M2). Until the gate passes,
    // the chart says WHY the ladder is not yet at Level5 — the red-line rule
    // ("قیمت حق ندارد به صورت شارپ از گام ۳ به گام ۵ برود") made readable.
    string mileState = "";
    {
        double retraceSteps = 0;
        bool ladderUp = !dirDown;   // dirDown: D is a high, the ladder runs DOWN (P-TH3-D4)
        int mile = TH3LadderMilestone(tD, pD, ladderUp, baseUnit, retraceSteps);
        if(mile == 2)      mileState = StringFormat("M2(%.1f)", retraceSteps);
        else if(mile == 1) mileState = StringFormat("M1(%.1f)", retraceSteps);
        else               mileState = StringFormat("M0(%.1f/1.0)", retraceSteps);
    }

    // Info label (corner-based positioning - configurable)
    //     (        -      
    // VISIBILITY: Only shown for active pattern
    //         :                 
    double pips_AB = AB_Distance / pipSize;
    double pips_BC = MathAbs(pC - pB) / pipSize;
    
    // "Step", not "Freq": this number is the movement step — the LIVE one,
    // with its own provenance: which step, from what. The hunter's question
    // ("where do T3 and T5 sit ahead of me?") then answers itself off the
    // ladder lines, because the number that built them is printed here.
    // P-TH3-STEP-04e (2026-09-19) — THE SEED SHOWS BESIDE THE LIVE STEP. The
    // user's demand is that the LADDER ride the movement step, and the movement
    // step is the market's: once a reaction has voted, `Step` is the proved
    // number, not the pattern TF's ATR. Printing the seed too (`rung`) is what
    // makes the two readable against each other on the chart — the earlier twin
    // label did exactly that, and it is how a reader can tell a recalibrated
    // ladder from one still standing on its seed (step == rung, stepHow says
    // so). On XAUUSD H1 2026-09-19 this reads "Step:163.3 pips [T3 reaction
    // x0.90 | rung 175.6] | T3=489.9 T5=816.5" — the ladder the market voted.
    // P-TH3-INFO-04 (2026-09-20) — THE CAPTION IS A READOUT, NOT A LINE.
    // The user's ask: the AB=CD caption must read like the leg meter's box, because
    // it is the same tool — so it is THREE ROWS inside the same dark plate, in the
    // same order and the same ink (the family owner draws it, P-TH3-INFO-01):
    //
    //   AB=CD | H1 | CD 18 bars          <- what this pattern IS
    //   AB 504p | BC 765p | CD 1200p     <- what its legs MEASURE
    //   Step 255.0p | K 3.0 | M0(0.4)    <- the LIVE number, on the accent row
    //   (+ P-TH3-DISC discovery rows: prices, harmonic, mother, calc, lock,
    //   ladder prices — nine rows until the formula locks)
    //
    // The rows are joined with "\n": the family owner wraps WITHIN a row (MT4's
    // 63-character cliff is per object) but never across two of them, so the shape
    // survives a long pattern name. Every number here is one the ladder above has
    // already computed, or division-only off it — the caption adds no reader.
    string cdTfName = TH3TfName(ownerTF);
    double stepPips = baseUnit / pipSize;
    // P-TH3-DISC (2026-10-05) — DISCOVERY ROWS, TEMPORARY. While the master
    // step formula is being found the caption carries every number the
    // synthesis consumes: prices, ratios, mother, rung, calc stages, ladder
    // prices, mid steps, proof state. Ten short rows (each under the 63-char cliff, so
    // no row ever wraps); the plate measures off the rows as-is. Words are
    // spelled out (no cryptic codes) so an outside reader with no project
    // access can still parse the box. When the formula locks this shrinks
    // back and this tag dies with it. Division-only off numbers computed
    // above — no new reader, no new writer.
    string rowIdentity = StringFormat("AB=CD %s CD %d bars %s",
                                      cdTfName, cdBars, (dirDown ? "down" : "up"));
    string rowLegs     = StringFormat("legs AB %.0fp | BC %.0fp | CD %.0fp",
                                      pips_AB, pips_BC, CD_Distance / pipSize);
    string rowPrices    = StringFormat("A %s B %s C %s D %s",
                                      DoubleToString(pA, Digits),
                                      DoubleToString(pB, Digits),
                                      DoubleToString(pC, Digits),
                                      DoubleToString(pD, Digits));
    double bcabRatio = (AB_Distance > 0) ? BC_Distance / AB_Distance : 0.0;
    string rowHarmonic = StringFormat("BC/AB %.2f | CD/BC %.2f | K %.1f | fibdev %.2f",
                                      bcabRatio,
                                      uniRatio,
                                      uniK,
                                      (uniRatio > 0 ? CalculateFibonacciDeviation(uniRatio) : 0.0));
    string rowMother = "Mother: none";
    if(pbRaw > 0)
        rowMother = StringFormat("Mother hand %.1fp", pbRaw / pipSize);
    string rowCalc  = StringFormat("pattern %.1fp rung %.1fp uni %.1fp",
                                   (CD_Distance / uniK) / pipSize,
                                   seedRung / pipSize,
                                   baseUnit / pipSize);
    string rowLock  = StringFormat("base %.1fp %s final %.1fp %s",
                                   pbStep / pipSize,
                                   (stepLocked ? "LOCKED" : "UNLOCKED"),
                                   stepPips,
                                   (hitOK ? "proved" : "seed"));
    string rowLadder = StringFormat("Targets T1 %s T3 %s T5 %s T7 %s",
                                    DoubleToString(targetLevels[0], Digits),
                                    DoubleToString(targetLevels[1], Digits),
                                    DoubleToString(targetLevels[2], Digits),
                                    DoubleToString(targetLevels[3], Digits));
    string rowMid = StringFormat("Mid T2 %s T4 %s T6 %s",
                                 DoubleToString(midLevels[0], Digits),
                                 DoubleToString(midLevels[1], Digits),
                                 DoubleToString(midLevels[2], Digits));
    string rowLive;
    if(atrBasis) {
        rowLive = StringFormat("Step %.1fp", stepPips);
        if(mlMotherSize > 0) {
            mlRatio = baseUnit / mlMotherSize;
            rowLive += StringFormat(" | momleg %.2f", mlRatio);
        }
    } else {
        rowLive = StringFormat("Step %.1f%% | freq", frequency);
    }
    if(StringLen(mileState) > 0) rowLive += " | gate " + mileState;
    rowLive += (hitOK ? " | proved" : " | seed");

    // P-TH3-INFO-14: ONE visible caption, ONE Y — the slot pitch is retired (its
    // note lives in the geometry block above with the arithmetic). Only the active
    // family carries a plate (INFO-10), so `patIdx` buys nothing and costs the
    // user a 64 px empty slot above the caption plus a jump whenever the active
    // pattern changes. The caption sits at the base of the safe area.
    bool isActive = (g_activeABCDPattern == mainObjName);
    int rowY    = inpABCDInfoYDistance;
    int infoLines = TH3InfoFamilyDraw(mainObjName,
                                       rowIdentity + "\n" + rowLegs + "\n" + rowPrices + "\n" +
                                       rowHarmonic + "\n" + rowMother + "\n" + rowCalc + "\n" +
                                       rowLock + "\n" + rowLadder + "\n" + rowMid + "\n" + rowLive,
                                       isActive, rowY);
    // P-TH3-INFO-13: a redraw that TOUCHED the active family re-arms its
    // visit — a re-step, a point drag or a settings press restarts the few
    // seconds the caption lives, exactly like re-showing the leg plate.
    if(isActive) TH3InfoVisitArm();

    // P-TH3-P6f (2026-09-22): the ladder follows the caption — drawn for every
    // pattern, worn by the active one only.
    TH3LadderSetVisible(mainObjName, isActive);

    // P-TH3-PB-OFF (2026-09-21) — the pivot-base LEVEL LINES are retired with
    // the drag that placed them (the base is a hand-typed HEIGHT now, with no
    // chart anchor to hang lines on). This block only sweeps the legacy
    // objects, so a chart drawn by the old build cleans itself on the next
    // redraw instead of wearing four dotted lines to a deleted gesture.
    {
        for(int _pb = 0; _pb < TH3_PIVOT_BASE_LEVELS; _pb++) {
            ObjectDelete(0, mainObjName + "_PBLine_"  + IntegerToString(_pb));
            ObjectDelete(0, mainObjName + "_PBLabel_" + IntegerToString(_pb));
        }
    }

    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawABCDPattern completed | Pattern: ", mainObjName);
    Print("   Caption lines: ", infoLines, " x <= ", TH3_INFO_TEXT_MAX, " chars");
    Print("   Objects: Points(3:A,B,C) + Labels(3) + Lines(2) + Targets(4) + Zones(8) + Info(", infoLines, ")");
    Print("   Note: Point D not shown - target levels indicate D zone");
    #endif

    // P-TH3-DEL2: this draw's own drops queue their OBJECT_DELETEs behind it.
    g_th3OwnDeleteMs = GetTickCount();
    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| P-TH3-P6 (2026-09-19) — THE SIX-CONDITION PIVOTS, ON THE CHART.  |
//|                                                                  |
//| The detector (TH3Pivots.mqh, from the course PDF pp. 6-7) finds  |
//| the pivots; this is their ink. Two layers, one per fractal TF:   |
//|                                                                  |
//|   * the CHART TF's pivots wear a triangle — Wingdings 218 hangs  |
//|     above an H pivot, 217 sits below an L pivot — ~one candle    |
//|     clear of the wick, so the side reads at a glance (P-TH3-P6b);|
//|   * the STRUCTURE TF's (one chain step up, p. 3) wear the same   |
//|     triangles in the structure's own ink, a fatter width — the   |
//|     bigger structure the small one lives in, big-to-small and    |
//|     small-to-big in one picture;                                 |
//|   * a chart pivot that a structure pivot claims (p. 50, the      |
//|     shared rule: the higher TF owns it) wears the structure ink  |
//|     too, so the eye can see which pivots are the structure's.    |
//|                                                                  |
//| PERF: the scan is cached per new bar of its own TF (inside the   |
//| detector); this painter redraws on a new chart bar or every 5 s  |
//| at most, bulk-clears its own namespace first (teardown/show-hide |
//| are bulk operations), and never writes a property it would not   |
//| change. Inks go through TH3InkForChart (P-UI-97).                |
//+------------------------------------------------------------------+
#define TH3_P6_PREFIX      "TH3_P6_"
void TH3PivotMarkersClear()
{
    for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
    {
        string nm = ObjectName(0, i, -1, -1);
        if(StringFind(nm, TH3_P6_PREFIX) == 0) ObjectDelete(0, nm);
    }
}

#endif // TH3_RENDERER_B_MQH
