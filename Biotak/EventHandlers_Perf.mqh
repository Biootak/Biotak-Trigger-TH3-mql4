// EventHandlers_Perf.mqh — the EVENT-BUDGET LEDGER, split out of
// EventHandlers_Objects.mqh on 2026-11-01 by contract §7 (one file, one owner;
// the ceiling is 1500 lines). Names, defines and behaviour are byte-identical;
// the block moved whole, nothing in it changed.
#ifndef EVENT_HANDLERS_PERF_MQH
#define EVENT_HANDLERS_PERF_MQH

//==============================================================================
// P-PERF-04 EVENT BUDGET — measure the paths the user FEELS
//
// P-PERF-02/03 instrumented the TICK path, which is why its fixes were real but
// incomplete: the complaints that survived were about INTERACTION — working
// with the chart, with the panel, and switching timeframe. None of those paths
// had a single line of measurement, so they could only be guessed at. These two
// helpers turn the next report into a named phase too. They log AT MOST one
// line per 2 s and only when the budget was blown, so the fast path pays one
// GetTickCount subtraction.
//==============================================================================
#define P_P4_EVENT_WARN_MS  40    // one chart event (chart handler + UI handler)
#define P_P4_INIT_WARN_MS   150   // attach / timeframe switch (OnInit+OnDeinit)
#define P_P4_MOVE_WARN_MS   20    // P-PERF-15: one cursor-move pass (ring + panel + hold)
#define P_P4_CLICK_WARN_MS  20    // P-PERF-26: one object-click pass (button + panel + apply)
static uint s_p4LogGateMs = 0;

// P-PERF-26: THE LEDGER WAS UNREADABLE, AND THAT COST A WHOLE CYCLE.
//
// Every perf line printed the raw chart-event id, so the reader had to REMEMBER
// what "id=1" meant. The project's own record shows the price of guessing: the
// 485-578 ms spikes were filed as "the cursor-move path" (P-PERF-15/16 notes),
// and the fix was aimed at hover work - while the constant is actually
// CHARTEVENT_OBJECT_CLICK. Measured, not recalled: the MQL4 compiler itself was
// asked (case-value collision probe) and reports
//   KEYDOWN=0 OBJECT_CLICK=1 OBJECT_DRAG=2 OBJECT_ENDEDIT=3 CLICK=4
//   OBJECT_DELETE=6 CHART_CHANGE=9 MOUSE_MOVE=10
// so id=1 is a BUTTON PRESS on the ring/panel - i.e. exactly the
// "toggling a switch takes half a second" the user reports - and no id=10 line
// exists because hover work is cheap. The ledger now prints the name next to
// the number, so the next report cannot be mis-read.
string P4EventName(const int id)
{
    if(id == CHARTEVENT_KEYDOWN)        return "KEYDOWN";
    if(id == CHARTEVENT_OBJECT_CLICK)   return "OBJ_CLICK";
    if(id == CHARTEVENT_OBJECT_DRAG)    return "OBJ_DRAG";
    if(id == CHARTEVENT_OBJECT_ENDEDIT) return "OBJ_ENDEDIT";
    if(id == CHARTEVENT_CLICK)          return "CLICK";
    if(id == CHARTEVENT_OBJECT_DELETE)  return "OBJ_DELETE";
    if(id == CHARTEVENT_CHART_CHANGE)   return "CHART_CHANGE";
    if(id == CHARTEVENT_MOUSE_MOVE)     return "MOUSE_MOVE";
    return "UNKNOWN";
}

void P4ReportSlow(const string what, const uint ms, const uint budget)
{
    if(ms < budget) return;
    uint now = GetTickCount();
    if(s_p4LogGateMs != 0 && now - s_p4LogGateMs < 2000) return;
    s_p4LogGateMs = now;
    _LOG_GATE_W Print("[W][PERF] ", what, " took ", (int)ms, "ms (budget ", (int)budget, "ms)");
#ifndef BUILD_LITE
    //--- P-COPY-STORM (2026-11-01): THE LEDGER WAS ONLY WRITTEN WHERE IT CANNOT BE
    //--- READ. This line is the whole slow-event record, and `Print` lands in MT4's
    //--- journal — a RAM cache (P-DRAW-126) that a killed terminal loses. The hang
    //--- the user reported («با دکمه کنترل میخوام کپی بکنم اینطوری میشه») ended with
    //--- MT4 closed by hand, and the journal held no trace of the 22:47→22:58 gap:
    //--- every number that would have named the stage died with the process. The
    //--- flushed file is the channel that survives a kill, so the ledger is twin-
    //--- written to it — same line, same 2 s gate, one extra FileWrite+FileFlush per
    //--- REPORTED slow event (never per event: this function already returned twice
    //--- before reaching here).
    DrawStripDiagEmit("[W][PERF] " + what + " took " + IntegerToString((int)ms) +
                      "ms (budget " + IntegerToString((int)budget) + "ms)");
#endif
}

string P4MsTag(const uint ms) { return IntegerToString((int)ms); }

#endif
