//+------------------------------------------------------------------+
//| TH3/TH3Renderer.mqh                                             |
//| Pure model->objects renderer: takes A/B/C points and draws the  |
//| complete AB=CD pattern (points, labels, lines, targets, zones,  |
//| info label). No state is stored here - chart objects are only   |
//| a projection of TH3Pattern models (TH3PatternStore.mqh).        |
//+------------------------------------------------------------------+
#ifndef TH3_RENDERER_MQH
#define TH3_RENDERER_MQH
#property strict

//+------------------------------------------------------------------+
//| Calculate AB=CD Point D (with 9-level validation)               |
//|       D       9                                |
//| Rule: AB distance = CD distance (equal price movement)          |
//+------------------------------------------------------------------+
//|      AB=CD     TH3                                    |
//| User provides A, B, C     System calculates D                      |
//| Targets (Step1/3/5/7) start from C (not D)                       |
//+------------------------------------------------------------------+
void DrawABCDPattern(string mainObjName, datetime tA, double pA, datetime tB, double pB,
                     datetime tC, double pC)
{
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawABCDPattern called | Name: ", mainObjName);
    Print("   A: ", TimeToString(tA), " @ ", DoubleToString(pA, Digits));
    Print("   B: ", TimeToString(tB), " @ ", DoubleToString(pB, Digits));
    Print("   C: ", TimeToString(tC), " @ ", DoubleToString(pC, Digits));
    #endif
    
    datetime tD;
    double pD;
    
    if(!CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD)) {
        #ifdef ENABLE_DEBUG_LOGS
        Print("==================== CalculateABCDPointD failed - cleaning up temp objects");
        #endif
        
        // Cleanup partial objects
        string pointNames[4] = {"A", "B", "C", "D"};
        for(int i = 0; i < 4; i++) {
            ObjectDelete(0, mainObjName + "_Point_" + pointNames[i]);
            ObjectDelete(0, mainObjName + "_Label_" + pointNames[i]);
        }
        ObjectDelete(0, mainObjName + "_Line_AB");
        ObjectDelete(0, mainObjName + "_Line_BC");
        ObjectDelete(0, mainObjName + "_Info");
        return;
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== Point D calculated: ", TimeToString(tD), " @ ", DoubleToString(pD, Digits));
    #endif
    
    double AB_Distance = MathAbs(pB - pA);
    bool isBullish = (pB > pA);
    double frequency = GetCurrentTH3Frequency();
    double baseUnit = AB_Distance * (frequency / 100.0);
    
    double pipSize = GetCachedPipSize();
    
    // DYNAMIC OFFSET: Calculate based on candle size for better positioning
    // Offset                          
    double labelOffset;
    
    if(inpABCDLabelOffsetPercent > 0) {
        // User-defined offset percentage
        double avgCandleSize = 0;
        int lookback = 20; //      20      
        for(int k = 0; k < lookback; k++) {
            avgCandleSize += (iHigh(NULL, 0, k) - iLow(NULL, 0, k));
        }
        avgCandleSize /= lookback;
        
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
    
    // Draw visible drag points for A, B, C (small circles with smart positioning)
    //            A  B  C (                   
    for(int i = 0; i < 3; i++) {
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
            ObjectSetInteger(0, pointName, OBJPROP_COLOR, inpABCDPointColor);
            ObjectSetInteger(0, pointName, OBJPROP_ARROWCODE, 159); // Small filled circle
            ObjectSetInteger(0, pointName, OBJPROP_WIDTH, 3); // Medium size for easy clicking
            ObjectSetInteger(0, pointName, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, pointName, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, pointName, OBJPROP_BACK, false); // Draw on top
            ObjectSetInteger(0, pointName, OBJPROP_ZORDER, 10); // High priority
            ObjectSetString(0, pointName, OBJPROP_TOOLTIP, "==================== Point " + pointNames[i] + " | Drag to adjust");
        } else {
            // Update existing point position
            ObjectMove(0, pointName, 0, pointTimes[i], pointPrices[i]);
            #ifdef ENABLE_DEBUG_LOGS
            Print("==================== Updated existing point ", pointNames[i]);
            #endif
        }
        
        // Smart label positioning relative to candle High/Low
        //                   High/Low    
        if(inpABCDShowLabels) {
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
                ObjectSetInteger(0, labelName, OBJPROP_COLOR, inpABCDPointColor);
                ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
                ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
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
        ObjectSetInteger(0, lineAB, OBJPROP_COLOR, inpABCDLineColor);
        ObjectSetInteger(0, lineAB, OBJPROP_WIDTH, inpABCDWidth);
        ObjectSetInteger(0, lineAB, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, lineAB, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, lineAB, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, lineAB, OBJPROP_BACK, false);
    } else {
        ObjectMove(0, lineAB, 0, tA, pA);
        ObjectMove(0, lineAB, 1, tB, pB);
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
        ObjectSetInteger(0, lineBC, OBJPROP_COLOR, clrGray);
        ObjectSetInteger(0, lineBC, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, lineBC, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, lineBC, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, lineBC, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, lineBC, OBJPROP_BACK, true);
    } else {
        ObjectMove(0, lineBC, 0, tB, pB);
        ObjectMove(0, lineBC, 1, tC, pC);
    }
    
    // Draw TH3-style targets (Step1, Step3, Step5, Step7) from C
    string targetNames[4] = {"Step1", "Step3", "Step5", "Step7"};
    color targetColors[4] = {clrDodgerBlue, clrOrangeRed, clrLimeGreen, clrGold};
    double targetLevels[4];
    
    if(isBullish) {
        targetLevels[0] = pC + (1.0 * baseUnit);
        targetLevels[1] = pC + (3.0 * baseUnit);
        targetLevels[2] = pC + (5.0 * baseUnit);
        targetLevels[3] = pC + (7.0 * baseUnit);
    } else {
        targetLevels[0] = pC - (1.0 * baseUnit);
        targetLevels[1] = pC - (3.0 * baseUnit);
        targetLevels[2] = pC - (5.0 * baseUnit);
        targetLevels[3] = pC - (7.0 * baseUnit);
    }
    
    double targetPips[4];
    for(int i = 0; i < 4; i++) {
        targetPips[i] = MathAbs(baseUnit * (i*2 + 1)) / pipSize;
    }
    
    datetime startTime = tC;
    int barShift = iBarShift(NULL, 0, startTime);
    datetime endTime = iTime(NULL, 0, MathMax(0, barShift - 100));
    
    // GOLD VERSION: Use configurable zone height from input parameter
    // Convert from percentage (1-100) to decimal (0.01-1.0)
    double zoneHeightPercent = inpTH3ZoneHeightPercent / 100.0;
    
    // Validate and clamp
    if(zoneHeightPercent < 0.01) zoneHeightPercent = 0.01;
    if(zoneHeightPercent > 1.0) zoneHeightPercent = 1.0;
    
    double zoneHalfWidth = baseUnit * zoneHeightPercent;
    
    for(int i = 0; i < 4; i++) {
        string lineName = mainObjName + "_Target_" + IntegerToString(i+1);
        double centerPrice = targetLevels[i];
        double upperZone = centerPrice + zoneHalfWidth;
        double lowerZone = centerPrice - zoneHalfWidth;
        color zoneColor = (inpTH3ZoneColor == clrNONE) ? targetColors[i] : inpTH3ZoneColor;
        // Apply the zone transparency to the box/border color (blend with background)
        zoneColor = GetZoneRenderColor(zoneColor, inpTH3ZoneTransparency);
        
        if(ObjectFind(0, lineName) < 0) {
            ObjectCreate(0, lineName, OBJ_FIBO, 0, startTime, centerPrice, endTime, centerPrice);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, targetColors[i]);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELCOLOR, targetColors[i]);
            ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELWIDTH, 2);
            ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, inpABCDExtendCD);
            ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, lineName, OBJPROP_LEVELS, 1);
            ObjectSetDouble(0, lineName, OBJPROP_LEVELVALUE, 0, 0.0);
            
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN) {
                double zonePips = (zoneHalfWidth * 2.0) / pipSize;
                string labelText = StringFormat("%s (%.1f) ====================%.1f", targetNames[i], targetPips[i], zonePips/2.0);
                ObjectSetString(0, lineName, OBJPROP_LEVELTEXT, 0, labelText);
            }
        } else {
            // CRITICAL FIX: Update position AND label text when frequency changes
            ObjectMove(0, lineName, 0, startTime, centerPrice);
            ObjectMove(0, lineName, 1, endTime, centerPrice);
            
            // Update label text with new pip values
            if(inpTH3LabelPosition != TH3_LABEL_HIDDEN) {
                double zonePips = (zoneHalfWidth * 2.0) / pipSize;
                string labelText = StringFormat("%s (%.1f) ====================%.1f", targetNames[i], targetPips[i], zonePips/2.0);
                ObjectSetString(0, lineName, OBJPROP_LEVELTEXT, 0, labelText);
            }
        }
        
        // Zone objects: BOX styles -> rectangle; HIDDEN -> nothing
        string zoneUpperName = mainObjName + "_ZoneUpper_" + IntegerToString(i+1);
        string zoneLowerName = mainObjName + "_ZoneLower_" + IntegerToString(i+1);
        string zoneBoxName = mainObjName + "_Zone_" + IntegerToString(i+1);
        
        if(inpTH3ZoneStyle == TH3_ZONE_HIDDEN) {
            // Clean up any leftover zone objects
            if(ObjectFind(0, zoneUpperName) >= 0) ObjectDelete(0, zoneUpperName);
            if(ObjectFind(0, zoneLowerName) >= 0) ObjectDelete(0, zoneLowerName);
            if(ObjectFind(0, zoneBoxName) >= 0) ObjectDelete(0, zoneBoxName);
            if(ObjectFind(0, zoneBoxName + "_B_Top") >= 0) ObjectDelete(0, zoneBoxName + "_B_Top");
            if(ObjectFind(0, zoneBoxName + "_B_Bottom") >= 0) ObjectDelete(0, zoneBoxName + "_B_Bottom");
            if(ObjectFind(0, zoneBoxName + "_B_Left") >= 0) ObjectDelete(0, zoneBoxName + "_B_Left");
        }
        else if(inpTH3ZoneStyle == TH3_ZONE_BOX_EMPTY) {
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
    
    // Info label (corner-based positioning - configurable)
    //     (        -      
    // VISIBILITY: Only shown for active pattern
    //         :                 
    double pips_AB = AB_Distance / pipSize;
    double pips_BC = MathAbs(pC - pB) / pipSize;
    
    string infoText = StringFormat("AB=CD | AB:%.1f | BC:%.1f | Freq:%.1f%%", 
                                   pips_AB, pips_BC, frequency);
    
    string infoLabel = mainObjName + "_Info";
    
    // Determine visibility based on active pattern
    //                     
    bool isActive = (g_activeABCDPattern == mainObjName);
    
    if(ObjectFind(0, infoLabel) < 0) {
        ObjectCreate(0, infoLabel, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, infoLabel, OBJPROP_CORNER, inpABCDInfoCorner);
        ObjectSetInteger(0, infoLabel, OBJPROP_XDISTANCE, inpABCDInfoXDistance);
        ObjectSetInteger(0, infoLabel, OBJPROP_YDISTANCE, inpABCDInfoYDistance);
        ObjectSetString(0, infoLabel, OBJPROP_TEXT, infoText);
        ObjectSetInteger(0, infoLabel, OBJPROP_COLOR, inpABCDInfoColor);
        ObjectSetInteger(0, infoLabel, OBJPROP_FONTSIZE, inpABCDInfoFontSize);
        ObjectSetString(0, infoLabel, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, infoLabel, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, infoLabel, OBJPROP_HIDDEN, true);
        
        // Set visibility based on active state
        ObjectSetInteger(0, infoLabel, OBJPROP_TIMEFRAMES, isActive ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
    } else {
        // Update text and visibility
        ObjectSetString(0, infoLabel, OBJPROP_TEXT, infoText);
        ObjectSetInteger(0, infoLabel, OBJPROP_CORNER, inpABCDInfoCorner);
        ObjectSetInteger(0, infoLabel, OBJPROP_XDISTANCE, inpABCDInfoXDistance);
        ObjectSetInteger(0, infoLabel, OBJPROP_YDISTANCE, inpABCDInfoYDistance);
        ObjectSetInteger(0, infoLabel, OBJPROP_COLOR, inpABCDInfoColor);
        ObjectSetInteger(0, infoLabel, OBJPROP_FONTSIZE, inpABCDInfoFontSize);
        
        // Update visibility based on active state
        ObjectSetInteger(0, infoLabel, OBJPROP_TIMEFRAMES, isActive ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
    }
    
    #ifdef ENABLE_DEBUG_LOGS
    Print("==================== DrawABCDPattern completed | Pattern: ", mainObjName);
    Print("   Objects: Points(3:A,B,C) + Labels(3) + Lines(2) + Targets(4) + Zones(8) + Info(1)");
    Print("   Note: Point D not shown - target levels indicate D zone");
    #endif
    
    ThrottledChartRedraw();
}

#endif // TH3_RENDERER_MQH
