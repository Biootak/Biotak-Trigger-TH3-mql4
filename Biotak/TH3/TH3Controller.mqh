//+------------------------------------------------------------------+
//| TH3/TH3Controller.mqh                                            |
//| Drawing session state machine. Replaces the old g_abcd* globals  |
//| (g_abcdDrawing, g_abcdPointCount, g_abcdTimeX...C, prices...)    |
//| with one TH3DrawingSession struct and explicit transitions.      |
//|                                                                    |
//| Session flow: IDLE --Start--> PLACING --4 clicks--> COMPLETE --> IDLE |
//|   (P-TH3-PB-OFF 2026-09-21: the 5th stage — drag the pivot base — is   |
//|   retired; the base is hand-typed in the panel, so completing the      |
//|   pattern ends the session.)                                           |
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

// P-TH3-PERF-03 (2026-09-19) — THE HOVER CHANGE-GUARD. It lives at FILE scope
// (not inside TH3PreviewUpdateHover) so a session transition can RESET it: a
// new session, a cancel or an undo must be able to re-project the very
// (time, price) the guard was last left on. `TH3HoverGuardReset` is the one
// owner of that reset.
static datetime s_th3HovT     = 0;
static double   s_th3HovP     = 0.0;
static int      s_th3HovCount = -1;
void TH3HoverGuardReset()
{
    s_th3HovT = 0;
    s_th3HovP = 0.0;
    s_th3HovCount = -1;
}

// Temp preview objects created while placing points
#define TH3_TEMP_A     "ABCD_Temp_A"
#define TH3_TEMP_B     "ABCD_Temp_B"
#define TH3_TEMP_C     "ABCD_Temp_C"
#define TH3_TEMP_D     "ABCD_Temp_D"
#define TH3_TEMP_LINE_AB "ABCD_Temp_Line_AB"
#define TH3_TEMP_LINE_BC "ABCD_Temp_Line_BC"
#define TH3_TEMP_LINE_CD "ABCD_Temp_Line_CD"
// P-TH3-D4: TH3_TEMP_X / TH3_TEMP_LINE_XA retired - 4 clicks are A/B/C/D, no X.

//+------------------------------------------------------------------+
//| Start a new drawing session                                      |
//|                                                                  |
//| P-UI-96 (2026-09-19) — `swallowGesture`: the press that ARMED the  |
//| session is not pivot A. Arming from the ring item happens on that  |
//| item's own release, i.e. while the arming gesture is still in      |
//| flight, and MT4 can deliver the chart click of that same press     |
//| right after this returns — which would spend the A letter in the   |
//| corner the ring sits in, at a price the user never chose. Priming  |
//| `lastClickTime` hands the rejection to the debounce that is already |
//| there instead of adding a second rule. (BaseKnot's own             |
//| `g_bkLeftPrev = true` is the same trap on its polling side, P-BK-03.)|
//|                                                                    |
//| The V key passes false: a keyboard toggle carries no gesture to    |
//| swallow, and eating the user's first click would be a dead press.  |
//+------------------------------------------------------------------+
void TH3SessionStart(const bool swallowGesture = false)
{
    g_th3Session.state = TH3_SESSION_PLACING;
    g_th3Session.pointCount = 0;
    g_th3Session.lastClickTime = (swallowGesture ? GetTickCount() : 0);
    g_th3Session.hoverTime = 0;
    g_th3Session.hoverPrice = 0;
    for(int i = 0; i < TH3_SESSION_POINTS; i++) {
        g_th3Session.points[i].time = 0;
        g_th3Session.points[i].price = 0;
    }
    // P-TH3-PB-OFF (2026-09-21): no base gesture to reset — TH3SessionResetBase retired.
    // P-TH3-PERF-07 (2026-09-19) — THE SESSION DOES NOT OWN THE CHART-WIDE
    // MOUSE-MOVE CHANNEL. It used to switch the flag ON here and OFF in
    // `TH3SessionCancel` and on the 4th point, but that flag is chart-scoped
    // and SHARED: `OnInitHandler` already enables it (EventHandlers,
    // `ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true)`) because the orb drag,
    // the panel's drag/hover engines and BaseKnot's poll shadow all ride the
    // same stream. So the ON here was a no-op, and the OFF there SILENCED the
    // whole interactive UI for the rest of that attach: one cancelled or
    // completed AB=CD draw and the ring stopped dragging, hover tips stopped
    // following the cursor and a held panel knob stopped tracking. One owner,
    // zero session writes.
    TH3HoverGuardReset();   // P-TH3-PERF-03
    Print("TH3: AB=CD Mode - click 4 points (A, B, C, D). Right-click cancels, Backspace undoes.");
}

//+------------------------------------------------------------------+
//| Cancel the current session and clear preview objects             |
//+------------------------------------------------------------------+
void TH3SessionCancel()
{
    g_th3Session.state = TH3_SESSION_IDLE;
    g_th3Session.pointCount = 0;
    // P-TH3-PB-OFF (2026-09-21): no base stage to skip — TH3SessionResetBase retired.
    TH3HoverGuardReset();    // P-TH3-PERF-03
    TH3PreviewClear();
    // P-TH3-PERF-07: the mouse-move flag is NOT this session's to clear.
    ThrottledChartRedraw();
    Print("TH3: AB=CD creation cancelled");
}

// P-TH3-PB-OFF (2026-09-21) — STAGE 5 (THE PIVOT-BASE DRAG) RETIRED.
// TH3SessionEnterBaseStage / TH3SessionEndBase / TH3SessionResetBase lived
// here: the session walked into TH3_SESSION_BASE after the 4th click, the
// press armed one node edge, the drag drew a rubber band and the release
// committed it as Path 1 of TH3LockedStep. The base is hand-typed now
// (`inpTH3PivotBasePips` -> TH3ManualBaseStep), so TH3CompletePattern ends
// the session instead. History in git log; restore by re-adding the three
// functions, the TH3_SESSION_BASE enumerator and the gesture fields.

//+------------------------------------------------------------------+
//| Undo the last placed point (keeps session active)                |
//+------------------------------------------------------------------+
void TH3SessionUndo()
{
    if(g_th3Session.state != TH3_SESSION_PLACING) return;
    if(g_th3Session.pointCount <= 0) return;

    int count = g_th3Session.pointCount; // 1..4 = A, B, C, D
    string pointObj  = (count == 1) ? TH3_TEMP_A :
                       (count == 2) ? TH3_TEMP_B :
                       (count == 3) ? TH3_TEMP_C : TH3_TEMP_D;
    string lineObj   = (count == 2) ? TH3_TEMP_LINE_AB :
                       (count == 3) ? TH3_TEMP_LINE_BC :
                       (count == 4) ? TH3_TEMP_LINE_CD : "";
    if(ObjectFind(0, pointObj) >= 0) ObjectDelete(0, pointObj);
    if(lineObj != "" && ObjectFind(0, lineObj) >= 0) ObjectDelete(0, lineObj);

    g_th3Session.pointCount--;
    if(g_th3Session.pointCount == 0) g_th3Session.lastClickTime = 0;
    TH3HoverGuardReset();   // P-TH3-PERF-03
    ThrottledChartRedraw();
    Print("TH3: Undo - ", g_th3Session.pointCount, " point(s) placed (A,B,C,D)");
}

//+------------------------------------------------------------------+
//| Add a placed point. Returns true when the session is COMPLETE    |
//| (all 4 points A,B,C,D placed).                                   |
//+------------------------------------------------------------------+
bool TH3SessionAddPoint(const datetime t, const double p)
{
    if(g_th3Session.state != TH3_SESSION_PLACING) return false;
    if(t <= 0 || p <= 0) return false;

    // P-UI-96b (2026-09-19) — TWO CONSECUTIVE PIVOTS CANNOT BE THE SAME POINT.
    // MT4 can report ONE press on two channels: the move stream carries its
    // press edge and `CHARTEVENT_CLICK` follows its release. The existing 300 ms
    // debounce only rejects the echo of a SHORT click - hold the button a little
    // longer and the same press is stored twice, so A and B land on one candle,
    // `AB_Distance` is 0 and the pattern drawn from it collapses. The rule
    // is stated by what a point IS rather than by when it arrived: a zero-length
    // leg is not a pattern, so nothing legitimate is refused (no user marks two
    // different pivots on the same bar within one point of each other).
    if(g_th3Session.pointCount > 0)
    {
        const int prev = g_th3Session.pointCount - 1;
        const int prevBar = iBarShift(NULL, 0, g_th3Session.points[prev].time);
        const int newBar  = iBarShift(NULL, 0, t);
        if(prevBar >= 0 && newBar == prevBar &&
           MathAbs(g_th3Session.points[prev].price - p) <= GetCachedPoint())
        {
            Print("TH3: duplicate click ignored on bar ", newBar,
                  " - one press is one pivot (the letter is not spent twice)");
            return false;
        }
    }

    g_th3Session.points[g_th3Session.pointCount].time = t;
    g_th3Session.points[g_th3Session.pointCount].price = p;
    g_th3Session.pointCount++;

    // Render the just-placed point + connecting line (preview)
    TH3PreviewDrawPoint(g_th3Session.pointCount, t, p);

    if(g_th3Session.pointCount >= TH3_SESSION_POINTS) {
        g_th3Session.state = TH3_SESSION_COMPLETE;
        // P-TH3-PERF-07: not ours to clear here either — see TH3SessionStart.
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
//| P-UI-97 (2026-09-19) — AN INK THAT READS ON THE CHART IT IS ON.   |
//|                                                                  |
//| The session preview was hardcoded: the placed letter and the line  |
//| into it in `clrYellow`, the candidate point and its rubber-band in |
//| `clrAqua`, the projected D in `clrLime`. On the WHITE chart the     |
//| user reported that the drawing cannot be seen - and it cannot: a    |
//| yellow letter on white paper is a smudge, and aqua is worse. The    |
//| committed pattern's own inks are already dark (`inpABCDPointColor`  |
//| / `inpABCDLineColor` are `clrDarkBlue`, "Visual align MT5"), so the |
//| preview and the pattern it turns into could not even agree on a     |
//| colour: the four hardcoded values above were the dark chart's half  |
//| of a pair that light charts were never given.                       |
//|                                                                    |
//| ONE OWNER, TWO RULES, and every TH3 ink goes through it - preview,  |
//| points, labels, lines, the ladder and the zones:                    |
//|                                                                    |
//|   * `TH3SessionPointInk` / `TH3SessionLineInk` spell the SAME       |
//|     `(g_th3* == clrNONE) ? inpABCD* : g_th3*` rule the renderer     |
//|     applies when it creates the objects, so what you draw IS the    |
//|     colour you get (and the card's COLOR / PIP COLOR rows move it); |
//|   * `TH3InkForChart` keeps an ink that is too bright for the paper  |
//|     but changes only its LIGHTNESS, never its hue: on a light chart |
//|     gold -> olive, lime -> forest green, aqua -> dark teal, and on  |
//|     a dark chart every ink is returned untouched, which is why the  |
//|     four colours above stay exactly as they were where they worked. |
//|                                                                    |
//| The weights are the project's own 299/587/114 (the hint bar and     |
//| `BaseKnotFgForBg` beside it), so the whole indicator judges "light"  |
//| the same way. `clrNONE` is never touched: it means "no color", not |
//| black - and `clrGray` (luma 128) is left alone, so the dotted BC    |
//| guideline keeps the quiet grey it was designed with (P-UI-31).      |
//+------------------------------------------------------------------+
int TH3ChartBgLuma()
{
    color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
    return (int)((((int)bg) & 0xFF) * 299 + ((((int)bg) >> 8) & 0xFF) * 587 +
                 ((((int)bg) >> 16) & 0xFF) * 114) / 1000;
}

color TH3InkForChart(const color c)
{
    if(c == clrNONE) return c;
    if(TH3ChartBgLuma() <= 128) return c;   // dark chart: this ink was designed for it
    int r = ((int)c) & 0xFF;
    int g = (((int)c) >> 8) & 0xFF;
    int b = (((int)c) >> 16) & 0xFF;
    int ink = (r * 299 + g * 587 + b * 114) / 1000;
    if(ink <= 128) return c;                // already dark enough for light paper
    // Scale toward black keeping the hue's own ratio, to the luma `k`. Every
    // division is on a non-zero `ink` (the `<= 128` line above returned already).
    int k = 96;
    return (color)(((r * k) / ink) | (((g * k) / ink) << 8) | (((b * k) / ink) << 16));
}

//+------------------------------------------------------------------+
//| P-TH3-INFO-04 (2026-09-20) — THE READOUT PALETTE: THE ONE INK     |
//| SET THE PAPER MUST NOT DECIDE.                                    |
//|                                                                  |
//| The leg meter prints its three lines inside a dark plate with a   |
//| hairline border (P-LM-01), and the user's ask is that the AB=CD   |
//| caption read the SAME way — one tool, one visual language. Both   |
//| therefore draw on the SAME fixed surface, and that is exactly why |
//| this palette is NOT put through `TH3InkForChart`: the plate is a  |
//| fixed dark ink on every theme, so a resolved row would be dark    |
//| blue ON the dark plate on light paper and near-white on white —   |
//| the one thing a readout cannot be, unreadable. The inks live HERE,|
//| with the chart's ink resolver, because this module is the one     |
//| that answers "what ink does this surface wear": `TH3InkForChart`  |
//| for anything drawn ON the paper, `TH3ReadoutInk` for the plate.   |
//|                                                                  |
//| `TH3ReadoutInk(row, rowCount)` is the whole rule the user sees,   |
//| and it has ONE owner so the two readouts cannot drift: every row  |
//| wears the palette's near-white, and the LIVE row — the last one,  |
//| the number that moves — wears its violet.                         |
//+------------------------------------------------------------------+
#define TH3RO_FILL     BIO_CLR_DEEP       // the plate's own ink — the SAME on every theme.
                                          // P-UI-117: it used to spell `C'18,22,33'` again;
                                          // the intent (a theme-independent plate) is the
                                          // ALIAS's, and the value is the palette owner's.
#define TH3RO_EDGE     C'140,150,166'     // ... and its hairline border
#define TH3RO_TEXT     C'235,240,248'     // a readout row (CIRC_TIP_TX's near-white)
#define TH3RO_ACCENT   C'124,92,255'      // the live row: the palette's own violet (#7C5CFF)

color TH3ReadoutInk(const int row, const int rowCount)
{
    if(rowCount > 1 && row == rowCount - 1) return TH3RO_ACCENT;
    return TH3RO_TEXT;
}

// The preview's own pair — the renderer's rule, in one place: the session and the
// committed pattern read the SAME settings, so a preview can never promise a colour
// the pattern will not keep.
color TH3SessionPointInk()
{
    return TH3InkForChart((g_th3PipTextColor == clrNONE) ? inpABCDPointColor
                                                         : g_th3PipTextColor);
}
color TH3SessionLineInk()
{
    return TH3InkForChart((g_th3Color == clrNONE) ? inpABCDLineColor : g_th3Color);
}

//+------------------------------------------------------------------+
//| Delete all temp preview objects                                  |
//+------------------------------------------------------------------+
void TH3PreviewClear()
{
    // P-TH3-PERF-06 (2026-09-19) — NO PROBE BEFORE THE DELETE. `ObjectDelete`
    // is safe on a name that does not exist (it returns false and sets no
    // state), so the eight `ObjectFind` probes that used to precede each delete
    // were pure lookups: a session cancel paid eight of them for nothing. The
    // delete is now the ONE owner of "this temp object is gone".
    ObjectDelete(0, TH3_TEMP_A);
    ObjectDelete(0, TH3_TEMP_B);
    ObjectDelete(0, TH3_TEMP_C);
    ObjectDelete(0, TH3_TEMP_D);
    ObjectDelete(0, TH3_TEMP_LINE_AB);
    ObjectDelete(0, TH3_TEMP_LINE_BC);
    ObjectDelete(0, TH3_TEMP_LINE_CD);
    // P-TH3-D4: legacy X temps swept for charts drawn before the retire.
    // P-TH3-PB-OFF: the stage-5 draft is gone too; its legacy objects die in
    // the pattern-delete sweep (TH3Tool.mqh), not here.
    ObjectDelete(0, "ABCD_Temp_X");
    ObjectDelete(0, "ABCD_Temp_Line_XA");
}

//+------------------------------------------------------------------+
//| Live hover preview: project the next point under the cursor      |
//| Uses the same temp-object namespace as placed points so a click  |
//| simply locks the hover position.                                 |
//+------------------------------------------------------------------+
void TH3PreviewUpdateHover(const datetime t, const double p)
{
    if(g_th3Session.state != TH3_SESSION_PLACING) return;
    if(g_th3Session.pointCount <= 0 || g_th3Session.pointCount >= 4) return;

    int nextCount = g_th3Session.pointCount + 1; // 2..4 -> placing B, C, D

    // P-TH3-PERF-03 (2026-09-19) — A HOVER THAT PROJECTS TO THE SAME POINT IS
    // NOT A MOVE. MT4 fires MOUSE_MOVE far more often than the cursor crosses a
    // bar/pixel, and the old path re-projected the candidate point, re-wrote up
    // to three temp objects and requested a repaint on every one of them. When
    // (time, price, placement step) are unchanged the result is byte-identical,
    // so the whole body — including `ThrottledChartRedraw` — is skipped. The
    // guard is file-scope so the session transitions can reset it.
    if(t == s_th3HovT && p == s_th3HovP && nextCount == s_th3HovCount) return;
    s_th3HovT = t; s_th3HovP = p; s_th3HovCount = nextCount;

    string names[4] = {"A", "B", "C", "D"};
    string objNames[4] = {TH3_TEMP_A, TH3_TEMP_B, TH3_TEMP_C, TH3_TEMP_D};
    string lineNames[4] = {"", TH3_TEMP_LINE_AB, TH3_TEMP_LINE_BC, TH3_TEMP_LINE_CD};

    // Candidate point follows the cursor
    string objName = objNames[nextCount - 1];
    // P-TH3-PERF-06 (2026-09-19) — MOVE FIRST, NO LOOKUP. MT4 has no object
    // handles, so the cheapest equivalent is to let the WRITE be the existence
    // test: a successful `ObjectMove` proves the object is there, and a FAILED
    // one is the self-heal signal (create + style it). The per-move `ObjectFind`
    // is therefore gone, and the properties are only written on creation — never
    // rewritten on a move (perf law).
    if(!ObjectMove(0, objName, 0, t, p))
    {
        if(ObjectCreate(0, objName, OBJ_TEXT, 0, t, p))
        {
            ObjectSetString(0, objName, OBJPROP_TEXT, names[nextCount - 1]);
            // P-UI-97: the candidate is the "not placed yet" ink — aqua on a dark
            // chart, its dark-teal counterpart on light paper (never invisible).
            ObjectSetInteger(0, objName, OBJPROP_COLOR, TH3InkForChart(clrAqua));
            ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
        }
    }

    // Connecting line from the last placed point to the candidate
    datetime tPrev;
    double pPrev;
    if(TH3SessionGetPoint(nextCount - 2, tPrev, pPrev)) {
        string lineName = lineNames[nextCount - 1];
        // P-TH3-PERF-06: move-first; the second anchor only needs a write when
        // the object already existed (a create sets BOTH anchors at once).
        if(!ObjectMove(0, lineName, 0, tPrev, pPrev))
        {
            if(ObjectCreate(0, lineName, OBJ_TREND, 0, tPrev, pPrev, t, p))
            {
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, TH3InkForChart(clrAqua));
                ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
            }
        }
        else
        {
            ObjectMove(0, lineName, 1, t, p);
        }
    }

    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| Draw one placed preview point (letter + connecting line)         |
//| count: 1..4 -> A, B, C, D                                        |
//+------------------------------------------------------------------+
void TH3PreviewDrawPoint(const int count, const datetime t, const double p)
{
    string names[4] = {"A", "B", "C", "D"};
    string objNames[4] = {TH3_TEMP_A, TH3_TEMP_B, TH3_TEMP_C, TH3_TEMP_D};
    string lineNames[4] = {"", TH3_TEMP_LINE_AB, TH3_TEMP_LINE_BC, TH3_TEMP_LINE_CD};

    if(count < 1 || count > 4) return;

    string objName = objNames[count - 1];
    // P-TH3-PERF-06 (2026-09-19): move-first — the write IS the existence test.
    if(!ObjectMove(0, objName, 0, t, p))
    {
        if(ObjectCreate(0, objName, OBJ_TEXT, 0, t, p))
        {
            ObjectSetString(0, objName, OBJPROP_TEXT, names[count - 1]);
            // P-UI-97: the placed letter wears the PATTERN's own point ink
            // (clrYellow on a dark chart, the dark blue a committed pattern uses
            // on light paper) — the preview no longer disagrees with its result.
            ObjectSetInteger(0, objName, OBJPROP_COLOR, TH3SessionPointInk());
            ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
        }
    }
    else
    {
        // P-UI-97b (2026-09-19): THE CANDIDATE MUST RE-INK WHEN IT IS PLACED.
        // The hover pass created this very object as the candidate letter in the
        // candidate ink (TH3InkForChart(clrAqua)), and P-TH3-PERF-06's
        // properties-only-on-create rule then kept that ink forever: A wore the
        // pattern's own ink while a placed B/C/D stayed candidate-teal, so the
        // drawing contradicted both itself and the pattern it becomes. The
        // placement is a rare event (one write per placed point), so the perf
        // law is not strained: this is a property we DO change.
        ObjectSetInteger(0, objName, OBJPROP_COLOR, TH3SessionPointInk());
    }

    // connecting line from previous point
    if(count >= 2) {
        datetime tPrev;
        double pPrev;
        if(!TH3SessionGetPoint(count - 2, tPrev, pPrev)) return;
        string lineName = lineNames[count - 1];
        // P-TH3-PERF-06 (2026-09-19): move-first, same as the hover path.
        if(!ObjectMove(0, lineName, 0, tPrev, pPrev))
        {
            if(ObjectCreate(0, lineName, OBJ_TREND, 0, tPrev, pPrev, t, p))
            {
                ObjectSetInteger(0, lineName, OBJPROP_COLOR, TH3SessionLineInk());
                ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
            }
        }
        else
        {
            ObjectMove(0, lineName, 1, t, p);
            // P-UI-97b: the rubber band this line was born as (the hover pass
            // created it in the candidate ink) re-inks to the PATTERN's own line
            // ink at placement - the same rule the letter above follows.
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, TH3SessionLineInk());
        }
    }
    ThrottledChartRedraw();
}

//+------------------------------------------------------------------+
//| Is a drawing session in progress?                                |
//| P-TH3-PB-OFF (2026-09-21): the base stage is retired, so the     |
//| session is PLACING or it is over — the F key, the ring badge and |
//| the click-echo swallow read this one predicate.                  |
//+------------------------------------------------------------------+
bool TH3SessionActive()
{
    return (g_th3Session.state == TH3_SESSION_PLACING);
}

#endif // TH3_CONTROLLER_MQH
