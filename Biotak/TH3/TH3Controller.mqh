//+------------------------------------------------------------------+
//| TH3/TH3Controller.mqh                                            |
//| Drawing session state machine. Replaces the old g_abcd* globals  |
//| (g_abcdDrawing, g_abcdPointCount, g_abcdTimeX...C, prices...)    |
//| with one TH3DrawingSession struct and explicit transitions.      |
//|                                                                    |
//| Session flow: IDLE --Start--> PLACING --4 clicks--> COMPLETE     |
//|   Right-click or V key = Cancel (back to IDLE)                   |
//|   Backspace = Undo last point                                    |
//|   Mouse move updates the live preview (hover)                    |
//+------------------------------------------------------------------+
#ifndef TH3_CONTROLLER_MQH
#define TH3_CONTROLLER_MQH
#property strict

#include "TH3Types.mqh"

// The single drawing-session instance (replaces the 12 old globals)
TH3DrawingSession g_th3Session;

// Temp preview objects created while placing points
#define TH3_TEMP_X     "ABCD_Temp_X"
#define TH3_TEMP_A     "ABCD_Temp_A"
#define TH3_TEMP_B     "ABCD_Temp_B"
#define TH3_TEMP_C     "ABCD_Temp_C"
#define TH3_TEMP_D     "ABCD_Temp_D"
#define TH3_TEMP_LINE_XA "ABCD_Temp_Line_XA"
#define TH3_TEMP_LINE_AB "ABCD_Temp_Line_AB"
#define TH3_TEMP_LINE_BC "ABCD_Temp_Line_BC"

//+------------------------------------------------------------------+
//| Start a new drawing session                                      |
//+------------------------------------------------------------------+
void TH3SessionStart()
{
    g_th3Session.state = TH3_SESSION_PLACING;
    g_th3Session.pointCount = 0;
    g_th3Session.lastClickTime = 0;
    g_th3Session.hoverTime = 0;
    g_th3Session.hoverPrice = 0;
    for(int i = 0; i < TH3_SESSION_POINTS; i++) {
        g_th3Session.points[i].time = 0;
        g_th3Session.points[i].price = 0;
    }
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
    Print("TH3: AB=CD Mode - click 4 points (X, A, B, C). Right-click cancels, Backspace undoes.");
}

//+------------------------------------------------------------------+
//| Cancel the current session and clear preview objects             |
//+------------------------------------------------------------------+
void TH3SessionCancel()
{
    g_th3Session.state = TH3_SESSION_IDLE;
    g_th3Session.pointCount = 0;
    TH3PreviewClear();
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
    ThrottledChartRedraw();
    Print("TH3: AB=CD creation cancelled");
}

//+------------------------------------------------------------------+
//| Undo the last placed point (keeps session active)                |
//+------------------------------------------------------------------+
void TH3SessionUndo()
{
    if(g_th3Session.state != TH3_SESSION_PLACING) return;
    if(g_th3Session.pointCount <= 0) return;

    int count = g_th3Session.pointCount; // 1..4 = X, A, B, C
    string pointObj  = (count == 1) ? TH3_TEMP_X :
                       (count == 2) ? TH3_TEMP_A :
                       (count == 3) ? TH3_TEMP_B : TH3_TEMP_C;
    string lineObj   = (count == 2) ? TH3_TEMP_LINE_XA :
                       (count == 3) ? TH3_TEMP_LINE_AB :
                       (count == 4) ? TH3_TEMP_LINE_BC : "";
    if(ObjectFind(0, pointObj) >= 0) ObjectDelete(0, pointObj);
    if(lineObj != "" && ObjectFind(0, lineObj) >= 0) ObjectDelete(0, lineObj);

    g_th3Session.pointCount--;
    if(g_th3Session.pointCount == 0) g_th3Session.lastClickTime = 0;
    ThrottledChartRedraw();
    Print("TH3: Undo - ", g_th3Session.pointCount, " point(s) placed (X,A,B,C)");
}

//+------------------------------------------------------------------+
//| Add a placed point. Returns true when the session is COMPLETE    |
//| (all 4 points X,A,B,C placed).                                   |
//+------------------------------------------------------------------+
bool TH3SessionAddPoint(const datetime t, const double p)
{
    if(g_th3Session.state != TH3_SESSION_PLACING) return false;
    if(t <= 0 || p <= 0) return false;

    g_th3Session.points[g_th3Session.pointCount].time = t;
    g_th3Session.points[g_th3Session.pointCount].price = p;
    g_th3Session.pointCount++;

    // Render the just-placed point + connecting line (preview)
    TH3PreviewDrawPoint(g_th3Session.pointCount, t, p);

    if(g_th3Session.pointCount >= TH3_SESSION_POINTS) {
        g_th3Session.state = TH3_SESSION_COMPLETE;
        ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Store the mouse position for the live preview (no rendering      |
//| here - the TH3Tool dispatcher draws the projected preview).      |
//+------------------------------------------------------------------+
void TH3SessionSetHover(const datetime t, const double p)
{
    g_th3Session.hoverTime = t;
    g_th3Session.hoverPrice = p;
}

//+------------------------------------------------------------------+
//| Accessor for a placed session point                              |
//+------------------------------------------------------------------+
bool TH3SessionGetPoint(const int index, datetime &t, double &p)
{
    if(index < 0 || index >= TH3_SESSION_POINTS) return false;
    t = g_th3Session.points[index].time;
    p = g_th3Session.points[index].price;
    return (t > 0 && p > 0);
}

//+------------------------------------------------------------------+
//| Delete all temp preview objects                                  |
//+------------------------------------------------------------------+
void TH3PreviewClear()
{
    if(ObjectFind(0, TH3_TEMP_X) >= 0) ObjectDelete(0, TH3_TEMP_X);
    if(ObjectFind(0, TH3_TEMP_A) >= 0) ObjectDelete(0, TH3_TEMP_A);
    if(ObjectFind(0, TH3_TEMP_B) >= 0) ObjectDelete(0, TH3_TEMP_B);
    if(ObjectFind(0, TH3_TEMP_C) >= 0) ObjectDelete(0, TH3_TEMP_C);
    if(ObjectFind(0, TH3_TEMP_D) >= 0) ObjectDelete(0, TH3_TEMP_D);
    if(ObjectFind(0, TH3_TEMP_LINE_XA) >= 0) ObjectDelete(0, TH3_TEMP_LINE_XA);
    if(ObjectFind(0, TH3_TEMP_LINE_AB) >= 0) ObjectDelete(0, TH3_TEMP_LINE_AB);
    if(ObjectFind(0, TH3_TEMP_LINE_BC) >= 0) ObjectDelete(0, TH3_TEMP_LINE_BC);
}

//+------------------------------------------------------------------+
//| Live hover preview: project the next point under the cursor and  |
//| (while placing C) the projected D from the AB=CD rule.           |
//| Uses the same temp-object namespace as placed points so a click  |
//| simply locks the hover position.                                 |
//+------------------------------------------------------------------+
void TH3PreviewUpdateHover(const datetime t, const double p)
{
    if(g_th3Session.state != TH3_SESSION_PLACING) return;
    if(g_th3Session.pointCount <= 0 || g_th3Session.pointCount >= 4) return;

    int nextCount = g_th3Session.pointCount + 1; // 2..4 -> placing A, B, C
    string names[4] = {"X", "A", "B", "C"};
    string objNames[4] = {TH3_TEMP_X, TH3_TEMP_A, TH3_TEMP_B, TH3_TEMP_C};
    string lineNames[4] = {"", TH3_TEMP_LINE_XA, TH3_TEMP_LINE_AB, TH3_TEMP_LINE_BC};

    // Candidate point follows the cursor
    string objName = objNames[nextCount - 1];
    if(ObjectFind(0, objName) < 0) {
        ObjectCreate(0, objName, OBJ_TEXT, 0, t, p);
        ObjectSetString(0, objName, OBJPROP_TEXT, names[nextCount - 1]);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrAqua);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
    } else {
        ObjectMove(0, objName, 0, t, p);
    }

    // Connecting line from the last placed point to the candidate
    datetime tPrev;
    double pPrev;
    if(TH3SessionGetPoint(nextCount - 2, tPrev, pPrev)) {
        string lineName = lineNames[nextCount - 1];
        if(ObjectFind(0, lineName) < 0) {
            ObjectCreate(0, lineName, OBJ_TREND, 0, tPrev, pPrev, t, p);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrAqua);
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
        } else {
            ObjectMove(0, lineName, 0, tPrev, pPrev);
            ObjectMove(0, lineName, 1, t, p);
        }
    }

    // While placing C, project where D will land (AB=CD rule)
    if(nextCount == 4) {
        datetime tA2, tB2;
        double pA2, pB2;
        if(TH3SessionGetPoint(1, tA2, pA2) && TH3SessionGetPoint(2, tB2, pB2)) {
            datetime tD;
            double pD;
            if(CalculateABCDPointD(tA2, pA2, tB2, pB2, t, p, tD, pD)) {
                if(ObjectFind(0, TH3_TEMP_D) < 0) {
                    ObjectCreate(0, TH3_TEMP_D, OBJ_ARROW, 0, tD, pD);
                    ObjectSetInteger(0, TH3_TEMP_D, OBJPROP_ARROWCODE, 159);
                    ObjectSetInteger(0, TH3_TEMP_D, OBJPROP_COLOR, clrLime);
                    ObjectSetInteger(0, TH3_TEMP_D, OBJPROP_WIDTH, 2);
                } else {
                    ObjectMove(0, TH3_TEMP_D, 0, tD, pD);
                }
            }
        }
    }
    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| Draw one placed preview point (letter + connecting line)         |
//| count: 1..4 -> X, A, B, C                                        |
//+------------------------------------------------------------------+
void TH3PreviewDrawPoint(const int count, const datetime t, const double p)
{
    string names[4] = {"X", "A", "B", "C"};
    string objNames[4] = {TH3_TEMP_X, TH3_TEMP_A, TH3_TEMP_B, TH3_TEMP_C};
    string lineNames[4] = {"", TH3_TEMP_LINE_XA, TH3_TEMP_LINE_AB, TH3_TEMP_LINE_BC};

    if(count < 1 || count > 4) return;

    string objName = objNames[count - 1];
    if(ObjectFind(0, objName) < 0) {
        ObjectCreate(0, objName, OBJ_TEXT, 0, t, p);
        ObjectSetString(0, objName, OBJPROP_TEXT, names[count - 1]);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrYellow);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
    } else {
        ObjectMove(0, objName, 0, t, p);
    }

    // connecting line from previous point
    if(count >= 2) {
        datetime tPrev;
        double pPrev;
        if(!TH3SessionGetPoint(count - 2, tPrev, pPrev)) return;
        string lineName = lineNames[count - 1];
        if(ObjectFind(0, lineName) < 0) {
            ObjectCreate(0, lineName, OBJ_TREND, 0, tPrev, pPrev, t, p);
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
            ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
        } else {
            ObjectMove(0, lineName, 0, tPrev, pPrev);
            ObjectMove(0, lineName, 1, t, p);
        }
    }
    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| Is a drawing session in progress?                                |
//+------------------------------------------------------------------+
bool TH3SessionActive()
{
    return (g_th3Session.state == TH3_SESSION_PLACING);
}

#endif // TH3_CONTROLLER_MQH
