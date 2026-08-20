//+------------------------------------------------------------------+
//| Biotak_ZoneRender_Test.mq4                                        |
//| Diagnostic: verifies MT4 OBJ_RECTANGLE fill behavior.             |
//| Run it on a chart: it draws two rectangles side by side - one     |
//| FILLED (red) and one EMPTY (blue) - using the exact same          |
//| properties as the indicator zones, then deletes them after 8s.    |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

//+------------------------------------------------------------------+
void OnStart()
{
    datetime startTime = Time[10];
    datetime endTime   = Time[0] + PeriodSeconds(Period()) * 100;

    string filledName = "ZBTest_Filled";
    string emptyName  = "ZBTest_Empty";

    // --- FILLED rectangle (should show color inside) ---
    if(ObjectFind(0, filledName) < 0)
        ObjectCreate(0, filledName, OBJ_RECTANGLE, 0, startTime, 1.0200, endTime, 1.0100);
    ObjectSetInteger(0, filledName, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, filledName, OBJPROP_BACK, true);
    ObjectSetInteger(0, filledName, OBJPROP_FILL, true);
    ObjectSetInteger(0, filledName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, filledName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, filledName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, filledName, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, filledName, OBJPROP_ZORDER, 0);

    // --- EMPTY rectangle (should show ONLY border, no fill) ---
    if(ObjectFind(0, emptyName) < 0)
        ObjectCreate(0, emptyName, OBJ_RECTANGLE, 0, startTime, 1.0000, endTime, 0.9900);
    ObjectSetInteger(0, emptyName, OBJPROP_COLOR, clrBlue);
    ObjectSetInteger(0, emptyName, OBJPROP_BACK, true);
    ObjectSetInteger(0, emptyName, OBJPROP_FILL, false);
    ObjectSetInteger(0, emptyName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, emptyName, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, emptyName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, emptyName, OBJPROP_RAY_RIGHT, true);
    ObjectSetInteger(0, emptyName, OBJPROP_ZORDER, 0);

    ChartRedraw();

    // Report the actual property values MT4 holds
    long filledFill = ObjectGetInteger(0, filledName, OBJPROP_FILL);
    long emptyFill  = ObjectGetInteger(0, emptyName, OBJPROP_FILL);
    Print("[ZBTEST] FILLED rectangle OBJPROP_FILL = ", filledFill,
          " (expected 1) | EMPTY rectangle OBJPROP_FILL = ", emptyFill,
          " (expected 0)");
    Print("[ZBTEST] If the BLUE rectangle shows color inside on your chart,");
    Print("[ZBTEST] this MT4 build renders OBJ_RECTANGLE fill incorrectly.");

    Sleep(8000);

    ObjectDelete(0, filledName);
    ObjectDelete(0, emptyName);
    ChartRedraw();
    Print("[ZBTEST] Test objects removed.");
}
//+------------------------------------------------------------------+
