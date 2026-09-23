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
#define TH3_SESSION_POINTS 4   // A, B, C, D (P-TH3-D4: X retired, 4 clicks are A/B/C/D)
#define TH3_PIVOT_BASE_LEVELS 4  // 0, 0.333, 0.666, 1.0

//+------------------------------------------------------------------+
//| One pattern point (time + price)                                 |
//+------------------------------------------------------------------+
struct TH3Point {
    datetime time;
    double   price;
};

//+------------------------------------------------------------------+
//| THE SKELETON AXES                                                |
//|                                                                  |
//| The course describes a pivot's arrangement as a combination of   |
//| axes: momentum x pivot candle x cover depth x cover delay x      |
//| direction. Until these existed, TH3 stored only X/A/B/C plus one |
//| number (the movement step), so a drawn pattern could not say     |
//| WHICH arrangement it was — the axes were unmeasurable and the    |
//| step had nothing to be found FROM. These five types are what     |
//| let a live pattern carry a coordinate.                           |
//|                                                                  |
//| Every band below is a real boundary, not a placeholder: the      |
//| pivot-candle bands are the course's four movement-length classes |
//| (0.80 / 1.20 / 2.50 ATR), and the momentum bands are the         |
//| MOMENTUM_SPEED_* thresholds in TH3Math.mqh, in R units - the      |
//| impulse's speed against the trigger timeframe's own ATR. They     |
//| replace the ANGLE_* degree bands, which measured a speed but     |
//| reported it as an angle (MOMENTUM-ANGLE-OFF).                    |
//|                                                                  |
//| The bands select the step in ASCENDING order of size - WEAK the   |
//| smallest. That ordering is not cosmetic: without it the weaker    |
//| bands got the LARGER step and the axis decided against the        |
//| momentum it had just measured.                                    |
//+------------------------------------------------------------------+

//| مومنتوم — the impulse leg's strength, read off its SPEED            |
//| R = |A->B| / (ATR(trigger) * sqrt(elapsed / triggerBarMinutes))      |
//| R = 1 is exactly what the trigger timeframe's own ATR predicts for   |
//| that many bars, and it is kept as an exact bound. The other two are   |
//| read off the R ladder (see the band block in TH3Math.mqh), not       |
//| chosen, and the mix they produce is deliberately NOT the old         |
//| quantile mix - that one put 82.7% of legs in the top two bands and    |
//| left the axis inert.                                                  |
enum TH3_MOMENTUM {
    TH3_MOM_WEAK      = 0,   // R <  MOMENTUM_SPEED_BALANCED (1.00)
    TH3_MOM_NORMAL    = 1,   // 1.00 .. 1.30
    TH3_MOM_STRONG    = 2,   // 1.30 .. 1.60
    TH3_MOM_EXPLOSIVE = 3    // >= MOMENTUM_SPEED_SPIKE (1.60)
};

//| کندل پیوت — the pivot candle's own length, in chart-ATR units        |
enum TH3_PIVOT_CANDLE {
    TH3_PC_UNKNOWN  = 0,     // could not be measured (no bars / no ATR)
    TH3_PC_SPINNING = 1,     // range < 0.80 ATR
    TH3_PC_STANDARD = 2,     // 0.80 .. 1.20
    TH3_PC_LONGBAR  = 3,     // 1.20 .. 2.50
    TH3_PC_SPIKE    = 4      // >= 2.50
};

//| عمق پوشش — how completely the covering candle took the pivot out     |
enum TH3_COVER_DEPTH {
    TH3_CD_NONE    = 0,      // no candle before C covered B's range
    TH3_CD_SHALLOW = 1,      // range covered, but B's BODY survives
    TH3_CD_FULL    = 2,      // B's body covered too
    TH3_CD_DEEP    = 3       // body covered AND 2+ earlier candles engulfed
};

//+------------------------------------------------------------------+
//| One pattern's skeleton coordinate + the step derived from it      |
//+------------------------------------------------------------------+
struct TH3Skeleton {
    bool              valid;          // false = any axis unmeasured; read no field
    int               direction;      // +1 bullish (A->B up), -1 bearish
    TH3_MOMENTUM      momentum;       // axis 1
    TH3_PIVOT_CANDLE  pivotCandle;    // axis 2
    TH3_COVER_DEPTH   coverDepth;     // axis 3
    int               coverDelay;     // axis 4: candles from B to the covering candle
    int               coverEngulf;    // supporting count for axis 3 (0..4)
    double            abAngle;        // RETIRED momentum reading, degrees (MOMENTUM-ANGLE-OFF)
    double            abSpeed;        // raw momentum reading, R units (appended: no reordering)
    double            pivotAtrRatio;  // pivot candle range / chart ATR
    double            coverBodyRatio; // covering candle body / its own range
    double            stepPips;       // movement step derived FROM these axes (0 = absent)
    int               key;            // packed coordinate; -1 when not valid
};

//+------------------------------------------------------------------+
//| A complete AB=CD pattern model                                   |
//+------------------------------------------------------------------+
struct TH3Pattern {
    string     name;        // base name, e.g. "ABCD_Pattern_xxx"
    TH3Point   X;           // RETIRED (P-TH3-D4): kept as 0,0 for compat; the pattern starts at A
    TH3Point   A;
    TH3Point   B;
    TH3Point   C;
    TH3Point   D;           // placed 4th click (P-TH3-D4), no longer computed via AB=CD rule
    double     frequency;   // selected movement step, as the share of AB it cuts off (%)
    bool       bullish;     // A->B is upward
    TH3Skeleton skeleton;   // the five axes + the step they imply (appended: no reordering)
    // P-TH3-PB-OFF (2026-09-21): the DRAWN pivot base is retired — nothing is
    // dragged any more, Path 1 is the hand-typed `inpTH3PivotBasePips` (see
    // TH3ManualBaseStep, TH3Pivots.mqh). The two fields stay in the struct so
    // the store layout and the old pins keep compiling; the UI never writes
    // them and the renderer never reads them.
    double     pivotBaseTop;     // RETIRED (always 0 via TH3PatternBuild)
    double     pivotBaseBottom;  // RETIRED (always 0 via TH3PatternBuild)
};

//+------------------------------------------------------------------+
//| Drawing session states                                           |
//+------------------------------------------------------------------+
enum TH3_SESSION_STATE {
    TH3_SESSION_IDLE = 0,       // nothing in progress
    TH3_SESSION_PLACING,        // placing A, B, C, D in order (P-TH3-D4)
    TH3_SESSION_COMPLETE        // pattern finalized (drag/edit allowed) — transient, see below
    // P-TH3-PB-OFF (2026-09-21): TH3_SESSION_BASE (stage 5, drag the pivot
    // base) is retired — the base is hand-typed in the panel, so the session
    // ends when the pattern completes. Never re-add the enumerator without
    // re-teaching every switch that reads this state.
};

//+------------------------------------------------------------------+
//| Interactive drawing state - replaces the old g_abcd* globals.    |
//| One instance lives in TH3Controller.mqh.                         |
//+------------------------------------------------------------------+
struct TH3DrawingSession {
    TH3_SESSION_STATE state;
    int      pointCount;      // 0..4 placed so far (A,B,C,D - P-TH3-D4)
    TH3Point points[TH3_SESSION_POINTS];
    uint     lastClickTime;   // double-click guard
    datetime hoverTime;       // mouse position for live preview
    double   hoverPrice;
    // P-TH3-PB-OFF (2026-09-21): the stage-5 base gesture fields
    // (baseT/baseP/baseHeld/basePrevLeft/baseDraftName) are retired with the
    // stage itself — the base is hand-typed, never dragged.
};

//+------------------------------------------------------------------+
//| In-memory pattern registry (see TH3PatternStore.mqh)             |
//+------------------------------------------------------------------+
struct TH3PatternList {
    TH3Pattern items[TH3_MAX_PATTERNS];
    int        count;
};

#endif // TH3_TYPES_MQH
