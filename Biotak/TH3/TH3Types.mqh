//+------------------------------------------------------------------+
//| TH3/TH3Types.mqh                                                 |
//| TH3 data model - the single source of truth for patterns and    |
//| drawing state. Chart objects are only a projection of this      |
//| model (see TH3Renderer.mqh).                                    |
//+------------------------------------------------------------------+
#ifndef TH3_TYPES_MQH
#define TH3_TYPES_MQH
#property strict

#define TH3_MAX_PATTERNS 64
#define TH3_SESSION_POINTS 4   // X, A, B, C

//+------------------------------------------------------------------+
//| One pattern point (time + price)                                 |
//+------------------------------------------------------------------+
struct TH3Point {
    datetime time;
    double   price;
};

//+------------------------------------------------------------------+
//| A complete AB=CD pattern model                                   |
//+------------------------------------------------------------------+
struct TH3Pattern {
    string     name;        // base name, e.g. "ABCD_Pattern_xxx"
    TH3Point   X;           // origin (used for wave analysis)
    TH3Point   A;
    TH3Point   B;
    TH3Point   C;
    TH3Point   D;           // computed via AB=CD rule
    double     frequency;   // selected TH3 frequency (%)
    bool       bullish;     // A->B is upward
};

//+------------------------------------------------------------------+
//| Drawing session states                                           |
//+------------------------------------------------------------------+
enum TH3_SESSION_STATE {
    TH3_SESSION_IDLE = 0,   // nothing in progress
    TH3_SESSION_PLACING,    // placing X, A, B, C in order
    TH3_SESSION_COMPLETE    // pattern finalized (drag/edit allowed)
};

//+------------------------------------------------------------------+
//| Interactive drawing state - replaces the old g_abcd* globals.    |
//| One instance lives in TH3Controller.mqh.                         |
//+------------------------------------------------------------------+
struct TH3DrawingSession {
    TH3_SESSION_STATE state;
    int      pointCount;      // 0..4 placed so far (X,A,B,C)
    TH3Point points[TH3_SESSION_POINTS];
    uint     lastClickTime;   // double-click guard
    datetime hoverTime;       // mouse position for live preview
    double   hoverPrice;
};

//+------------------------------------------------------------------+
//| In-memory pattern registry (see TH3PatternStore.mqh)             |
//+------------------------------------------------------------------+
struct TH3PatternList {
    TH3Pattern items[TH3_MAX_PATTERNS];
    int        count;
};

#endif // TH3_TYPES_MQH
